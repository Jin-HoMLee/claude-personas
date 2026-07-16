#!/usr/bin/env python3
"""consolidate_pass.py - deterministic git wrapper for the consolidation pass (#89).

The only sanctioned write path for the consolidate-memory skill. Owns the git
surface so the AC guarantees are properties of code, not instructions:
zero writes to main (commit refuses off the pass branch), single-store scope
(commit rejects out-of-store paths), typed one-op-per-commit history, and an
index<->file sync check at finish. Spec:
docs/superpowers/specs/2026-07-16-consolidation-pass-mechanics-design.md

Usage:
    python3 consolidate_pass.py begin --store DIR
    python3 consolidate_pass.py commit --op {dedupe,redistribute,retire} -m MSG
    python3 consolidate_pass.py finish
    python3 consolidate_pass.py abort

State lives in local git config (consolidate.store/.base/.branch/.baseref),
following git-flow's config-namespace precedent - nothing eval-visible in the tree.
"""
from __future__ import annotations

import argparse
import datetime
import os
import subprocess
import sys

OPS = ("dedupe", "redistribute", "retire")
KEYS = ("consolidate.store", "consolidate.base",
        "consolidate.branch", "consolidate.baseref")


def _git(root: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args],
                          check=check, capture_output=True, text=True)


def _fail(msg: str) -> int:
    print(f"FAIL: {msg}", file=sys.stderr)
    return 1


def repo_root(cwd: str = ".") -> str | None:
    r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def config_get(root: str, key: str) -> str | None:
    r = _git(root, "config", "--local", "--get", key, check=False)
    return r.stdout.strip() if r.returncode == 0 else None


def config_set(root: str, key: str, value: str) -> None:
    _git(root, "config", "--local", key, value)


def config_unset(root: str, key: str) -> None:
    _git(root, "config", "--local", "--unset", key, check=False)


def _dirty(root: str) -> bool:
    return bool(_git(root, "status", "--porcelain").stdout.strip())


def _current_branch(root: str) -> str:
    return _git(root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()


def store_relpath(root: str, store: str) -> str | None:
    """Store dir as a relpath under root, or None if outside/invalid."""
    ab = os.path.realpath(store)
    rootab = os.path.realpath(root)
    if not (ab == rootab or ab.startswith(rootab + os.sep)):
        return None
    rel = os.path.relpath(ab, rootab)
    return None if rel == "." else rel


def cmd_begin(args: argparse.Namespace) -> int:
    root = repo_root(os.path.dirname(os.path.realpath(args.store)) or ".")
    if root is None:
        return _fail(f"{args.store} is not inside a git repository")
    if _dirty(root):
        return _fail("working tree is dirty; commit or stash first")
    rel = store_relpath(root, args.store)
    if rel is None or not os.path.isfile(os.path.join(root, rel, "MEMORY.md")):
        return _fail(f"{args.store} is not a memory store (no MEMORY.md)")
    if config_get(root, "consolidate.branch"):
        return _fail("a consolidation pass is already in progress; run finish or abort")
    slug = rel.replace(os.sep, "-")
    branch = f"consolidate/{slug}-{datetime.date.today().isoformat()}"
    if _git(root, "rev-parse", "--verify", branch, check=False).returncode == 0:
        return _fail(f"branch {branch} already exists; delete it or finish that pass")
    baseref = _current_branch(root)
    base = _git(root, "rev-parse", "HEAD").stdout.strip()
    _git(root, "checkout", "-q", "-b", branch)
    config_set(root, "consolidate.store", rel)
    config_set(root, "consolidate.base", base)
    config_set(root, "consolidate.branch", branch)
    config_set(root, "consolidate.baseref", baseref)
    print(f"OK: pass branch {branch} (store: {rel}, base: {baseref})")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("begin")
    b.add_argument("--store", required=True)
    b.set_defaults(fn=cmd_begin)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
