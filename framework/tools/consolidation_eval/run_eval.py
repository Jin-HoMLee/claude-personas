#!/usr/bin/env python3
"""run_eval.py - N-run canary-eval driver, the canonical kill-gate mode (#88).

Each run: seed a fresh fixture store into a temp git repo, execute the
consolidation pass command inside it, then check canary survival on the
result. If the pass created a consolidate/* branch (the #89 contract), that
branch is checked out before checking; otherwise the working tree is checked.

Gate rule (spec): 100% canary survival in EVERY run. Cleanup is reported,
never gated on. The model, when given, is recorded verbatim in the results
so a silent provider update shows up as an eval change; pass --model
whenever --pass-cmd invokes an LLM.

The real gate run against the #89 consolidation skill looks like:
    python3 run_eval.py --runs 10 --model <pinned-model> \
        --pass-cmd 'claude -p "/consolidate-memory ." --model <pinned-model>'
(exact skill invocation lands with #89; any command that mutates the store
or leaves a consolidate/* branch works.)

Usage:
    python3 run_eval.py --runs N --pass-cmd CMD [--model NAME]
                        [--out results.json] [--keep] [--timeout SECONDS]
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

try:
    from . import check, seed
except ImportError:  # executed as a script, not a package
    import check
    import seed


def _git(store: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", store,
         "-c", "user.email=canary-eval@local", "-c", "user.name=canary-eval",
         *args],
        check=True, capture_output=True, text=True)


def _run_once(run_no: int, pass_cmd: str, keep: bool, timeout: int) -> dict:
    workdir = tempfile.mkdtemp(prefix=f"canary-eval-run{run_no}-")
    store = os.path.join(workdir, "store")
    manifest = seed.write_store(store, os.path.join(workdir, "manifest.json"))
    _git(store, "init", "-q")
    _git(store, "add", "-A")
    _git(store, "commit", "-q", "-m", "canary-eval: seeded fixture store")

    subprocess.run(pass_cmd, shell=True, cwd=store, timeout=timeout,
                   check=False)

    branches = _git(store, "branch", "--list", "consolidate/*",
                    "--format=%(refname:short)").stdout.split()
    if branches:
        _git(store, "checkout", "-q", branches[0])

    verdict = check.evaluate(manifest, store)
    result = {"run": run_no, "workdir": workdir if keep else None,
              "branch_checked": branches[0] if branches else None,
              "gate_pass": verdict["gate_pass"],
              "canaries_survived": verdict["canaries_survived"],
              "canaries_total": verdict["canaries_total"],
              "cleanup_done": verdict["cleanup_done"],
              "cleanup_total": verdict["cleanup_total"],
              "results": verdict["results"]}
    if not keep:
        shutil.rmtree(workdir, ignore_errors=True)
    return result


def run(runs: int, pass_cmd: str, model, keep: bool, timeout: int) -> dict:
    per_run = []
    for i in range(1, runs + 1):
        r = _run_once(i, pass_cmd, keep, timeout)
        print(f"run {i}/{runs}: gate={'PASS' if r['gate_pass'] else 'FAIL'} "
              f"survival={r['canaries_survived']}/{r['canaries_total']} "
              f"cleanup={r['cleanup_done']}/{r['cleanup_total']}")
        per_run.append(r)
    return {"runs": runs, "pass_cmd": pass_cmd, "model": model,
            "gate_pass": all(r["gate_pass"] for r in per_run),
            "per_run": per_run}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--runs", type=int, default=10)
    p.add_argument("--pass-cmd", required=True,
                   help="shell command executed with cwd=<fixture store>")
    p.add_argument("--model", default=None,
                   help="pinned model id, recorded in the results; give this "
                        "whenever --pass-cmd invokes an LLM")
    p.add_argument("--out", default=None,
                   help="write full results JSON to this path")
    p.add_argument("--keep", action="store_true",
                   help="keep per-run workdirs for inspection")
    p.add_argument("--timeout", type=int, default=1800,
                   help="per-run pass-cmd timeout in seconds")
    args = p.parse_args(argv)
    results = run(args.runs, args.pass_cmd, args.model, args.keep,
                  args.timeout)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2)
            f.write("\n")
    print("aggregate gate:",
          "PASS" if results["gate_pass"] else "FAIL",
          f"({args.runs} runs, model={args.model or 'n/a'})")
    return 0 if results["gate_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
