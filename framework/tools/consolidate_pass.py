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
import re
import shutil
import subprocess
import sys

OPS = ("dedupe", "redistribute", "retire")
KEYS = ("consolidate.store", "consolidate.base",
        "consolidate.branch", "consolidate.baseref")

INDEX_LINK_RE = re.compile(r"\]\(([^)]+\.md)\)")


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
    """Store dir as a relpath under root, or None if outside/invalid.
    A store that IS the repo root (rel == ".") is a legitimate shape -
    it returns "." rather than being rejected. This assumes the root
    contains ONLY the index and fact files (no README.md or other
    root-level .md siblings), matching the canary-eval fixture's shape;
    index_sync_errors requires every root .md except MEMORY.md to be
    indexed, so a root store with an un-indexed doc file can never finish."""
    ab = os.path.realpath(store)
    rootab = os.path.realpath(root)
    if not (ab == rootab or ab.startswith(rootab + os.sep)):
        return None
    return os.path.relpath(ab, rootab)


def changed_paths(root: str) -> list[str]:
    """Working-tree changes vs HEAD. Rename lines (`old -> new`) yield BOTH
    endpoints, so a rename that crosses the store boundary on either side
    is visible to the offender check."""
    out = _git(root, "status", "--porcelain").stdout
    paths = []
    for line in out.splitlines():
        path = line[3:]
        if " -> " in path:
            old, new = path.split(" -> ", 1)
            paths.append(old.strip().strip('"'))
            paths.append(new.strip().strip('"'))
        else:
            paths.append(path.strip().strip('"'))
    return paths


def cmd_commit(args: argparse.Namespace) -> int:
    root = repo_root()
    if root is None:
        return _fail("not inside a git repository")
    branch = config_get(root, "consolidate.branch")
    store = config_get(root, "consolidate.store")
    if not branch or not store:
        return _fail("no consolidation pass in progress; run begin first")
    if _current_branch(root) != branch:
        return _fail(f"not on the pass branch {branch}; refusing to commit")
    paths = changed_paths(root)
    if not paths:
        return _fail("nothing to commit")
    # store == "." means the store IS the repo root, so every changed path
    # is in-store by definition - skip the filter rather than compare
    # against a nonsensical "./" prefix.
    offenders = [] if store == "." else [
        p_ for p_ in paths if not (p_ == store or p_.startswith(store + "/"))]
    if offenders:
        print("FAIL: changes outside the store; revert these and retry:",
              file=sys.stderr)
        for o in offenders:
            print(f"  {o}", file=sys.stderr)
        return 1
    _git(root, "add", "-A", "--", store)
    _git(root, "commit", "-m", f"consolidate({args.op}): {args.m}")
    print(f"OK: consolidate({args.op}): {args.m}")
    return 0


def cmd_begin(args: argparse.Namespace) -> int:
    # Derive root from the store dir itself, not its parent: `git
    # rev-parse --show-toplevel` finds the enclosing repo regardless of
    # depth, so this works whether the store is a subdir OR is itself the
    # repo root (the canary-eval fixture's shape).
    root = repo_root(os.path.realpath(args.store))
    if root is None:
        return _fail(f"{args.store} is not inside a git repository")
    if _dirty(root):
        return _fail("working tree is dirty; commit or stash first")
    rel = store_relpath(root, args.store)
    if rel is None or not os.path.isfile(os.path.join(root, rel, "MEMORY.md")):
        return _fail(f"{args.store} is not a memory store (no MEMORY.md)")
    if config_get(root, "consolidate.branch"):
        return _fail("a consolidation pass is already in progress; run finish or abort")
    slug = "root" if rel == "." else rel.replace(os.sep, "-")
    branch = f"consolidate/{slug}-{datetime.date.today().isoformat()}"
    if _git(root, "rev-parse", "--verify", branch, check=False).returncode == 0:
        return _fail(f"branch {branch} already exists; delete it or finish that pass")
    baseref = _current_branch(root)
    if baseref == "HEAD":
        return _fail("detached HEAD; check out a branch before starting a pass")
    base = _git(root, "rev-parse", "HEAD").stdout.strip()
    _git(root, "checkout", "-q", "-b", branch)
    config_set(root, "consolidate.store", rel)
    config_set(root, "consolidate.base", base)
    config_set(root, "consolidate.branch", branch)
    config_set(root, "consolidate.baseref", baseref)
    print(f"OK: pass branch {branch} (store: {rel}, base: {baseref})")
    return 0


def index_sync_errors(root: str, store: str) -> list[str]:
    """Index<->file sync, same-directory links only - cross-store references
    like shared/MEMORY.md are legitimate and skipped, as are URLs. A leading
    `./` on a same-directory link (e.g. `./fact_a.md`) is normalized away
    before the cross-store filter, so it isn't mistaken for a path."""
    storedir = os.path.join(root, store)
    idx_path = os.path.join(storedir, "MEMORY.md")
    with open(idx_path, encoding="utf-8") as f:
        links = INDEX_LINK_RE.findall(f.read())
    links = [l[2:] if l.startswith("./") else l for l in links]
    linked = {l for l in links if "/" not in l and "://" not in l}
    on_disk = {f_ for f_ in os.listdir(storedir)
               if f_.endswith(".md") and f_ != "MEMORY.md"}
    errors = []
    for ghost in sorted(linked - on_disk):
        errors.append(f"index links missing file: {ghost}")
    for orphan in sorted(on_disk - linked):
        errors.append(f"file not in index: {orphan}")
    return errors


def _op_log(root: str, base: str) -> list[str]:
    out = _git(root, "log", "--reverse", "--format=%s", f"{base}..HEAD").stdout
    return [s for s in out.splitlines() if s.strip()]


def _cleanup(root: str, branch: str, baseref: str) -> None:
    _git(root, "checkout", "-q", baseref)
    _git(root, "branch", "-D", branch)
    for key in KEYS:
        config_unset(root, key)


def cmd_finish(args: argparse.Namespace) -> int:
    root = repo_root()
    if root is None:
        return _fail("not inside a git repository")
    branch = config_get(root, "consolidate.branch")
    store = config_get(root, "consolidate.store")
    base = config_get(root, "consolidate.base")
    baseref = config_get(root, "consolidate.baseref")
    if not all((branch, store, base, baseref)):
        return _fail("no consolidation pass in progress; run begin first")
    if _current_branch(root) != branch:
        return _fail(f"not on the pass branch {branch}")
    if _dirty(root):
        return _fail("uncommitted changes; land them via commit or revert them")
    ops = _op_log(root, base)
    if not ops:
        print("OK: nothing to consolidate; cleaning up")
        _cleanup(root, branch, baseref)
        return 0
    idx_path = os.path.join(root, store, "MEMORY.md")
    if not os.path.isfile(idx_path):
        return _fail(f"{store}/MEMORY.md missing - the pass must never delete the store index")
    errors = index_sync_errors(root, store)
    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1
    if not _git(root, "remote", check=False).stdout.strip():
        for key in KEYS:
            config_unset(root, key)
        print(f"OK: {len(ops)} operation(s) on {branch} (no remote; branch is the deliverable)")
        return 0
    # Same slug rule as begin: "root" for a store-at-repo-root pass, else
    # the store's relpath - keeps the PR title consistent with the branch
    # name instead of printing the raw "." store string.
    slug = "root" if store == "." else store
    title = f"consolidate: {slug} pass {datetime.date.today().isoformat()}"
    body = "Consolidation pass operations:\n\n" + "\n".join(f"- {s}" for s in ops)
    if not shutil.which("gh"):
        return _fail("gh not found; branch intact - deliver manually:\n"
                     f"  git push -u origin {branch}\n"
                     f"  gh pr create --title '{title}' --body-file <ops>")
    push = _git(root, "push", "-u", "origin", branch, check=False)
    if push.returncode != 0:
        print(push.stderr, file=sys.stderr)
        return _fail("push failed; branch intact - deliver manually:\n"
                     f"  git push -u origin {branch}\n"
                     f"  gh pr create --title '{title}' --body-file <ops>")
    pr = subprocess.run(["gh", "pr", "create", "--title", title, "--body", body],
                        cwd=root, capture_output=True, text=True)
    if pr.returncode != 0:
        print(pr.stderr, file=sys.stderr)
        return _fail("gh pr create failed; branch pushed - open the PR manually:\n"
                     f"  gh pr create --title '{title}' --body '...op log...'")
    for key in KEYS:
        config_unset(root, key)
    print(f"OK: PR opened for {branch}\n{pr.stdout.strip()}")
    return 0


def cmd_abort(args: argparse.Namespace) -> int:
    root = repo_root()
    if root is None:
        return _fail("not inside a git repository")
    branch = config_get(root, "consolidate.branch")
    baseref = config_get(root, "consolidate.baseref")
    if not branch or not baseref:
        return _fail("no consolidation pass in progress")
    _git(root, "checkout", "-qf", baseref)
    _git(root, "branch", "-D", branch)
    for key in KEYS:
        config_unset(root, key)
    print(f"OK: aborted; back on {baseref}, {branch} deleted")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("begin")
    b.add_argument("--store", required=True)
    b.set_defaults(fn=cmd_begin)
    c = sub.add_parser("commit")
    c.add_argument("--op", required=True, choices=OPS)
    c.add_argument("-m", required=True)
    c.set_defaults(fn=cmd_commit)
    f = sub.add_parser("finish")
    f.set_defaults(fn=cmd_finish)
    a = sub.add_parser("abort")
    a.set_defaults(fn=cmd_abort)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
