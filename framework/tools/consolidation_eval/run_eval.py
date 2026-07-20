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

The pass command must exit 0 (part of the #89 contract): a non-zero exit
is treated as a FAILED run and check.evaluate is never even called - a
crashing or no-op-by-error pass must never read as a canary-survival PASS.
The pass's own stdout/stderr is captured (not streamed) and its tail is
recorded per run for diagnosis. To keep the pass under eval from finding
or recognizing the answer key: the manifest lives in its own tempdir,
separate from the fixture store's tempdir; both tempdir prefixes and the
seeded commit message are generic ("mem-" / "memory store snapshot"), not
eval-identifying.

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
         "-c", "user.email=memory@local", "-c", "user.name=memory",
         *args],
        check=True, capture_output=True, text=True)


def _run_once(run_no: int, pass_cmd: str, keep: bool, timeout: int) -> dict:
    # Tempdir prefixes and the seeded commit message are deliberately
    # generic ("mem-" / "memory store snapshot"), and the manifest (answer
    # key) lives in its own separate tempdir, not workdir's parent or a
    # sibling the pass could find by walking up from its cwd=store - the
    # pass under eval must not be able to locate or recognize the eval.
    workdir = tempfile.mkdtemp(prefix="mem-")
    manifest_dir = tempfile.mkdtemp(prefix="mem-")
    store = os.path.join(workdir, "store")
    # The adjacent tier (#102) sits beside the store, outside its git repo,
    # reachable from inside via the seeded `shared` symlink - the pass may
    # read it; any write to it is caught by the cross_tier hash check.
    adjacent = os.path.join(workdir, "shared")
    manifest = seed.write_store(store, os.path.join(manifest_dir, "manifest.json"),
                                adjacent_dir=adjacent)
    _git(store, "init", "-q")
    _git(store, "add", "-A")
    _git(store, "commit", "-q", "-m", "memory store snapshot")

    try:
        proc = subprocess.run(pass_cmd, shell=True, cwd=store, timeout=timeout,
                              check=False, capture_output=True, text=True)
        pass_output_tail = (proc.stderr + proc.stdout)[-2000:]
        # Reported, never gated - mirrors the cleanup score (#102). Counted
        # over the FULL output, not the recorded tail.
        flags_emitted = (proc.stdout + proc.stderr).count("flag(cross-tier-dup):")

        if proc.returncode != 0:
            # A pass command that exits non-zero (crashed, or a shell
            # no-op like `exit 1`) must never be scored as canary
            # survival - check.evaluate is never even called.
            result = {"run": run_no, "workdir": workdir if keep else None,
                      "manifest_dir": manifest_dir if keep else None,
                      "branch_checked": None, "gate_pass": False,
                      "error": f"pass_cmd exited {proc.returncode}",
                      "pass_returncode": proc.returncode,
                      "pass_output_tail": pass_output_tail,
                      "flags_emitted": flags_emitted,
                      "canaries_survived": 0, "canaries_total": 0,
                      "cleanup_done": 0, "cleanup_total": 0, "results": []}
            return result

        branches = _git(store, "branch", "--list", "consolidate/*",
                        "--format=%(refname:short)").stdout.split()
        if branches:
            _git(store, "checkout", "-q", branches[0])

        verdict = check.evaluate(manifest, store, adjacent_dir=adjacent)
        result = {"run": run_no, "workdir": workdir if keep else None,
                  "manifest_dir": manifest_dir if keep else None,
                  "branch_checked": branches[0] if branches else None,
                  "gate_pass": verdict["gate_pass"],
                  "pass_returncode": proc.returncode,
                  "pass_output_tail": pass_output_tail,
                  "flags_emitted": flags_emitted,
                  "canaries_survived": verdict["canaries_survived"],
                  "canaries_total": verdict["canaries_total"],
                  "cleanup_done": verdict["cleanup_done"],
                  "cleanup_total": verdict["cleanup_total"],
                  "results": verdict["results"]}
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError,
            OSError, UnicodeDecodeError, ValueError) as exc:
        # A pass that hangs past --timeout, leaves the repo in a state git
        # can't check out, or blows up some other way (bad output encoding,
        # OS-level failure) is a FAILED run - not a crash that kills the
        # other N-1 runs and loses their already-collected results.
        result = {"run": run_no, "workdir": workdir if keep else None,
                  "manifest_dir": manifest_dir if keep else None,
                  "branch_checked": None, "gate_pass": False,
                  "error": f"{type(exc).__name__}: {exc}",
                  "flags_emitted": 0,
                  "canaries_survived": 0, "canaries_total": 0,
                  "cleanup_done": 0, "cleanup_total": 0, "results": []}
    finally:
        if not keep:
            shutil.rmtree(workdir, ignore_errors=True)
            shutil.rmtree(manifest_dir, ignore_errors=True)
    return result


def run(runs: int, pass_cmd: str, model, keep: bool, timeout: int) -> dict:
    if runs < 1:
        # runs=0 means per_run=[] and all([]) is True: a vacuous PASS.
        # Reject it here too, not just in the CLI's argparse validation,
        # so a direct run() caller can't hit the same false-PASS path.
        raise ValueError("runs must be >= 1")
    per_run = []
    for i in range(1, runs + 1):
        r = _run_once(i, pass_cmd, keep, timeout)
        msg = (f"run {i}/{runs}: gate={'PASS' if r['gate_pass'] else 'FAIL'} "
               f"survival={r['canaries_survived']}/{r['canaries_total']} "
               f"cleanup={r['cleanup_done']}/{r['cleanup_total']} "
               f"flags={r['flags_emitted']}")
        if "error" in r:
            msg += f" error={r['error']}"
        print(msg)
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
    if args.runs < 1:
        # runs=0 would make per_run=[] and all([]) True: a vacuous PASS
        # that never ran a single canary check. Reject it outright.
        p.error("--runs must be >= 1")
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
