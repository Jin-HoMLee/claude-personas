# Consolidation Pass Mechanics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the explicit-only consolidation pass for #89: a deterministic git wrapper (`consolidate_pass.py`) plus a self-contained skill (`consolidate-memory`), with the CONVENTIONS.md contract, per the approved spec `docs/superpowers/specs/2026-07-16-consolidation-pass-mechanics-design.md`.

**Architecture:** The wrapper owns the entire git surface (branch isolation, path scope, typed commits, index-file sync) so every AC guarantee is a property of code; the skill owns semantics (what to dedupe/retire/redistribute) and may only write through the wrapper. Delivery is a `consolidate/*` branch, plus an auto-opened PR when a remote exists.

**Tech Stack:** stdlib-only Python 3 (argparse + subprocess, `memory_cliff.py` style), unittest + bash shim tests wired into `run_all.sh`, SKILL.md skill format.

## Global Constraints

- stdlib-only Python; no third-party imports (spec: "stdlib-only Python in the style of `memory_cliff.py`").
- All wrapper failures are non-interactive: clear message to stderr, non-zero exit; success prints to stdout and exits 0.
- Pass state lives ONLY in local git config keys `consolidate.store`, `consolidate.base`, `consolidate.branch`, `consolidate.baseref`; nothing eval-visible in the tree.
- Typed commit format is exactly `consolidate(<op>): <msg>` with `<op>` one of `dedupe|redistribute|retire`.
- `gh pr create` is always called with explicit `--title` and `--body`, never `--fill`, and only after a successful push.
- Shell test shims must be bash-3.2 compatible and shellcheck warning-clean (CI gates on both).
- New `.py` files with a shebang must be `chmod +x`; shebang-less modules must NOT be executable (CI shebang<->x-bit gate).
- Markdown docs: one sentence per line; plain dashes only, never an em dash.
- Commit messages: prefix `claude-personas:`, suffix `(#89)`, no co-author lines.

---

### Task 1: Live probe of the headless invocation mechanism

No repo code; de-risks the gate-run mechanism the spec commits to (`--append-system-prompt-file` reaching a cwd with no skills).

**Files:**
- Create (scratch only, not committed): `/tmp`-equivalent scratchpad probe files.

**Interfaces:**
- Produces: a recorded YES/NO on "does `claude -p` + `--append-system-prompt-file` act on instructions inside a foreign tempdir", noted in the PR body and used verbatim as the gate-run mechanism in Task 6's SKILL.md invocation docs.

- [ ] **Step 1: Build a minimal probe fixture in the scratchpad**

```bash
PROBE=$(mktemp -d "${TMPDIR:-/tmp}/probe-XXXXXX")
cd "$PROBE" && git init -q . && echo "# notes" > notes.md && git add . && git -c user.email=p@l -c user.name=p commit -qm snap
cat > /tmp/probe-instructions.md <<'EOF'
When asked to tidy, create a git branch named consolidate/probe, append the line "tidied" to notes.md, commit with message "consolidate(dedupe): probe", and stop.
EOF
```

- [ ] **Step 2: Run the probe headlessly**

Run:
```bash
cd "$PROBE" && claude -p "tidy this repo" \
  --append-system-prompt-file /tmp/probe-instructions.md \
  --permission-mode acceptEdits --allowedTools "Bash(git *)"
```
Expected: exit 0; `git -C "$PROBE" log --oneline consolidate/probe` shows the `consolidate(dedupe): probe` commit.

- [ ] **Step 3: Record the outcome**

Record PASS/FAIL plus the claude-code version (`claude --version`) as a checklist note for the eventual PR body.
If FAIL: stop and re-plan the invocation mechanism before any implementation (the spec's decision log names this the fallback fork).

### Task 2: `consolidate_pass.py` helpers + `begin`

**Files:**
- Create: `framework/tools/consolidate_pass.py` (mode 100755)
- Test: `framework/tools/tests/test_consolidate_pass.py` (mode 100644, no shebang)

**Interfaces:**
- Produces: `repo_root(cwd)`, `_git(root, *args, check=True)`, `config_get/config_set/config_unset(root, key)`, `store_relpath(root, store)`, `cmd_begin(args) -> int`, CLI `begin --store DIR`; git config keys `consolidate.store` (relpath), `consolidate.base` (sha), `consolidate.branch`, `consolidate.baseref` (branch name at begin). Branch name: `consolidate/<store-slug>-<YYYY-MM-DD>` where store-slug is the relpath with `/` replaced by `-`.

- [ ] **Step 1: Write failing tests for `begin`**

```python
"""test_consolidate_pass.py - guard tests for consolidate_pass.py (#89)."""
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import consolidate_pass as cp  # noqa: E402


def _git(root, *args):
    return subprocess.run(
        ["git", "-C", root, "-c", "user.email=t@l", "-c", "user.name=t", *args],
        check=True, capture_output=True, text=True)


def make_repo(tmp):
    """Git repo with a valid store dir `mem/` (MEMORY.md + one fact file).
    Local identity is set because the WRAPPER's commits pass no -c identity
    flags; without this, tests fail on machines with no global git config."""
    _git(tmp, "init", "-q", "-b", "main", ".")
    _git(tmp, "config", "user.email", "t@l")
    _git(tmp, "config", "user.name", "t")
    os.makedirs(os.path.join(tmp, "mem"))
    with open(os.path.join(tmp, "mem", "MEMORY.md"), "w") as f:
        f.write("# Index\n\n- [Fact A](fact_a.md) - a fact\n")
    with open(os.path.join(tmp, "mem", "fact_a.md"), "w") as f:
        f.write("---\nname: fact-a\n---\n\nFact A body.\n")
    with open(os.path.join(tmp, "README.md"), "w") as f:
        f.write("readme\n")
    _git(tmp, "add", ".")
    _git(tmp, "commit", "-qm", "seed")
    return tmp


class TestBegin(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory(prefix="mem-")
        self.root = make_repo(self._td.name)

    def tearDown(self):
        self._td.cleanup()

    def _begin(self, store="mem"):
        return cp.main(["begin", "--store", os.path.join(self.root, store)])

    def test_begin_creates_branch_and_config(self):
        self.assertEqual(self._begin(), 0)
        branch = _git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        self.assertTrue(branch.startswith("consolidate/mem-"))
        self.assertEqual(cp.config_get(self.root, "consolidate.store"), "mem")
        self.assertEqual(cp.config_get(self.root, "consolidate.baseref"), "main")

    def test_begin_refuses_dirty_tree(self):
        with open(os.path.join(self.root, "README.md"), "a") as f:
            f.write("dirt\n")
        self.assertNotEqual(self._begin(), 0)
        self.assertIsNone(cp.config_get(self.root, "consolidate.branch"))

    def test_begin_refuses_non_store(self):
        os.makedirs(os.path.join(self.root, "notastore"))
        self.assertNotEqual(self._begin("notastore"), 0)

    def test_begin_refuses_when_pass_in_progress(self):
        self.assertEqual(self._begin(), 0)
        self.assertNotEqual(self._begin(), 0)

    def test_begin_refuses_when_todays_branch_exists(self):
        self.assertEqual(self._begin(), 0)
        # Simulate stale state: config gone but today's branch left behind.
        for key in ("consolidate.store", "consolidate.base",
                    "consolidate.branch", "consolidate.baseref"):
            cp.config_unset(self.root, key)
        _git(self.root, "checkout", "-q", "main")
        self.assertNotEqual(self._begin(), 0)

    def test_begin_refuses_outside_git_repo(self):
        with tempfile.TemporaryDirectory(prefix="mem-") as td:
            os.makedirs(os.path.join(td, "mem"))
            with open(os.path.join(td, "mem", "MEMORY.md"), "w") as f:
                f.write("# Index\n")
            old = os.getcwd()
            os.chdir(td)
            try:
                self.assertNotEqual(cp.main(["begin", "--store", "mem"]), 0)
            finally:
                os.chdir(old)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m unittest discover -s framework/tools/tests -p test_consolidate_pass.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'consolidate_pass'`

- [ ] **Step 3: Implement helpers + `begin`**

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest discover -s framework/tools/tests -p test_consolidate_pass.py -v`
Expected: 6 tests PASS

- [ ] **Step 5: Set the executable bit and commit**

```bash
chmod +x framework/tools/consolidate_pass.py
git add framework/tools/consolidate_pass.py framework/tools/tests/test_consolidate_pass.py
git commit -m "claude-personas: consolidate_pass.py begin - preflight + pass branch + config state (#89)"
```

### Task 3: `consolidate_pass.py commit`

**Files:**
- Modify: `framework/tools/consolidate_pass.py`
- Test: `framework/tools/tests/test_consolidate_pass.py` (append class)

**Interfaces:**
- Consumes: helpers + config keys from Task 2.
- Produces: `cmd_commit(args) -> int`, CLI `commit --op OP -m MSG`; commit subject `consolidate(<op>): <msg>`; `changed_paths(root) -> list[str]` (porcelain parse, rename-aware: takes the NEW path after `->`).

- [ ] **Step 1: Write failing tests**

Append to `test_consolidate_pass.py`:

```python
class TestCommit(unittest.TestCase):
    # commit/finish/abort resolve the repo from the process cwd (repo_root()),
    # so these classes chdir into the fixture - otherwise the wrapper would
    # act on the claude-personas repo the tests run from.
    def setUp(self):
        self._td = tempfile.TemporaryDirectory(prefix="mem-")
        self.root = make_repo(self._td.name)
        self._oldcwd = os.getcwd()
        os.chdir(self.root)
        cp.main(["begin", "--store", os.path.join(self.root, "mem")])

    def tearDown(self):
        os.chdir(self._oldcwd)
        self._td.cleanup()

    def _edit(self, relpath, text):
        with open(os.path.join(self.root, relpath), "w") as f:
            f.write(text)

    def test_commit_typed_prefix(self):
        self._edit("mem/fact_a.md", "---\nname: fact-a\n---\n\nMerged body.\n")
        rc = cp.main(["commit", "--op", "dedupe", "-m", "merge a into a"])
        self.assertEqual(rc, 0)
        subj = _git(self.root, "log", "-1", "--format=%s").stdout.strip()
        self.assertEqual(subj, "consolidate(dedupe): merge a into a")

    def test_commit_refuses_off_pass_branch(self):
        _git(self.root, "checkout", "-q", "main")
        self._edit("mem/fact_a.md", "x\n")
        self.assertNotEqual(cp.main(["commit", "--op", "retire", "-m", "m"]), 0)
        self.assertEqual(_git(self.root, "log", "-1", "--format=%s").stdout.strip(), "seed")

    def test_commit_rejects_out_of_store_paths_and_stages_nothing(self):
        self._edit("mem/fact_a.md", "in-store edit\n")
        self._edit("README.md", "stray edit\n")
        self.assertNotEqual(cp.main(["commit", "--op", "dedupe", "-m", "m"]), 0)
        staged = _git(self.root, "diff", "--cached", "--name-only").stdout.strip()
        self.assertEqual(staged, "")

    def test_commit_refuses_empty(self):
        self.assertNotEqual(cp.main(["commit", "--op", "dedupe", "-m", "m"]), 0)

    def test_commit_rejects_bad_op(self):
        with self.assertRaises(SystemExit):
            cp.main(["commit", "--op", "tidy", "-m", "m"])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m unittest discover -s framework/tools/tests -p test_consolidate_pass.py -v`
Expected: TestCommit cases ERROR (`invalid choice`/`AttributeError`), TestBegin still PASS

- [ ] **Step 3: Implement `commit`**

Add to `consolidate_pass.py`:

```python
def changed_paths(root: str) -> list[str]:
    """Working-tree changes vs HEAD, rename-aware (new path after ' -> ')."""
    out = _git(root, "status", "--porcelain").stdout
    paths = []
    for line in out.splitlines():
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
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
    offenders = [p_ for p_ in paths
                 if not (p_ == store or p_.startswith(store + "/"))]
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
```

And in `main()` after the `begin` parser:

```python
    c = sub.add_parser("commit")
    c.add_argument("--op", required=True, choices=OPS)
    c.add_argument("-m", required=True)
    c.set_defaults(fn=cmd_commit)
```

Note: `cmd_commit` uses `repo_root()` with no argument (cwd-based); the skill always runs the wrapper from inside the repo.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest discover -s framework/tools/tests -p test_consolidate_pass.py -v`
Expected: 11 tests PASS

- [ ] **Step 5: Commit**

```bash
git add framework/tools/consolidate_pass.py framework/tools/tests/test_consolidate_pass.py
git commit -m "claude-personas: consolidate_pass.py commit - typed ops, branch + store-scope guards (#89)"
```

### Task 4: `consolidate_pass.py finish` + `abort`

**Files:**
- Modify: `framework/tools/consolidate_pass.py`
- Test: `framework/tools/tests/test_consolidate_pass.py` (append classes)

**Interfaces:**
- Consumes: Tasks 2-3 helpers, keys, `changed_paths`.
- Produces: `cmd_finish(args) -> int`, `cmd_abort(args) -> int`, `index_sync_errors(root, store) -> list[str]`, `_op_log(root, base) -> list[str]`. finish clears config on success and zero-op, KEEPS config on delivery failure (retryable). PR title: `consolidate: <store> pass <date>`; body: the op log, one line per typed commit.

- [ ] **Step 1: Write failing tests**

Append to `test_consolidate_pass.py`:

```python
class TestFinishAbort(unittest.TestCase):
    # Same cwd note as TestCommit: chdir into the fixture.
    def setUp(self):
        self._td = tempfile.TemporaryDirectory(prefix="mem-")
        self.root = make_repo(self._td.name)
        self._oldcwd = os.getcwd()
        os.chdir(self.root)
        cp.main(["begin", "--store", os.path.join(self.root, "mem")])

    def tearDown(self):
        os.chdir(self._oldcwd)
        self._td.cleanup()

    def _commit_op(self):
        with open(os.path.join(self.root, "mem", "fact_a.md"), "w") as f:
            f.write("---\nname: fact-a\n---\n\nMerged.\n")
        cp.main(["commit", "--op", "dedupe", "-m", "merge"])

    def test_zero_op_finish_cleans_up(self):
        self.assertEqual(cp.main(["finish"]), 0)
        self.assertEqual(_git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip(), "main")
        self.assertIsNone(cp.config_get(self.root, "consolidate.branch"))
        branches = _git(self.root, "branch", "--list", "consolidate/*").stdout.strip()
        self.assertEqual(branches, "")

    def test_finish_refuses_dirty_tree(self):
        with open(os.path.join(self.root, "mem", "fact_a.md"), "a") as f:
            f.write("dirt\n")
        self.assertNotEqual(cp.main(["finish"]), 0)

    def test_finish_remoteless_stops_at_branch(self):
        self._commit_op()
        self.assertEqual(cp.main(["finish"]), 0)
        branch = _git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        self.assertTrue(branch.startswith("consolidate/"))
        self.assertIsNone(cp.config_get(self.root, "consolidate.branch"))

    def test_finish_catches_dangling_index_line(self):
        idx = os.path.join(self.root, "mem", "MEMORY.md")
        with open(idx, "a") as f:
            f.write("- [Ghost](ghost.md) - dangles\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "consolidate(retire): bad edit")
        self.assertNotEqual(cp.main(["finish"]), 0)

    def test_finish_catches_orphan_file(self):
        with open(os.path.join(self.root, "mem", "orphan.md"), "w") as f:
            f.write("---\nname: orphan\n---\n\nNot indexed.\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "consolidate(redistribute): bad split")
        self.assertNotEqual(cp.main(["finish"]), 0)

    def test_abort_restores_base(self):
        self._commit_op()
        self.assertEqual(cp.main(["abort"]), 0)
        self.assertEqual(_git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip(), "main")
        self.assertIsNone(cp.config_get(self.root, "consolidate.store"))
        subj = _git(self.root, "log", "-1", "--format=%s").stdout.strip()
        self.assertEqual(subj, "seed")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m unittest discover -s framework/tools/tests -p test_consolidate_pass.py -v`
Expected: TestFinishAbort cases ERROR (`invalid choice: 'finish'`), earlier classes PASS

- [ ] **Step 3: Implement `finish`, `abort`, and the sync check**

Add to `consolidate_pass.py`:

```python
import re

INDEX_LINK_RE = re.compile(r"\]\(([^)]+\.md)\)")


def index_sync_errors(root: str, store: str) -> list[str]:
    """Index<->file sync: every store .md file indexed, every index link live."""
    storedir = os.path.join(root, store)
    idx_path = os.path.join(storedir, "MEMORY.md")
    with open(idx_path, encoding="utf-8") as f:
        linked = set(INDEX_LINK_RE.findall(f.read()))
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
    push = _git(root, "push", "-u", "origin", branch, check=False)
    title = f"consolidate: {store} pass {datetime.date.today().isoformat()}"
    body = "Consolidation pass operations:\n\n" + "\n".join(f"- {s}" for s in ops)
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
```

And in `main()`:

```python
    f = sub.add_parser("finish")
    f.set_defaults(fn=cmd_finish)
    a = sub.add_parser("abort")
    a.set_defaults(fn=cmd_abort)
```

Move the `import re` to the top-of-file import block (stdlib imports stay alphabetized: `argparse, datetime, os, re, subprocess, sys`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest discover -s framework/tools/tests -p test_consolidate_pass.py -v`
Expected: 18 tests PASS

- [ ] **Step 5: Commit**

```bash
git add framework/tools/consolidate_pass.py framework/tools/tests/test_consolidate_pass.py
git commit -m "claude-personas: consolidate_pass.py finish/abort - sync check, PR delivery, retryable failure (#89)"
```

### Task 5: CLI shim + `run_all.sh` wiring

**Files:**
- Create: `framework/tools/tests/test_consolidate_pass.sh` (mode 100755)

**Interfaces:**
- Consumes: the wrapper CLI from Tasks 2-4.
- Produces: shell-level coverage that the installed CLI surface works via `python3 framework/tools/consolidate_pass.py ...` subprocess calls (the `test_memory_cliff.sh` split: Python-internal logic vs actually invoking the script); auto-picked-up by `run_all.sh`'s `test_*.sh` glob.

- [ ] **Step 1: Write the shim**

```bash
#!/usr/bin/env bash
# Shim so run_all.sh (which globs test_*.sh) runs the Python unittest suite for
# framework/tools/consolidate_pass.py, PLUS CLI-level (subprocess, not import)
# checks - the same split test_memory_cliff.sh uses. bash-3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
CP="$(cd "$SCRIPT_DIR/.." && pwd)/consolidate_pass.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not found (required for consolidate_pass tests)"
  exit 1
fi

python3 -m unittest discover -s "$SCRIPT_DIR" -p test_consolidate_pass.py -v
unittest_exit=$?

echo "=== CLI-level: consolidate_pass.py ==="
fixture="$(mktemp -d "${TMPDIR:-/tmp}/mem-XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q -b main .
# Local identity so the wrapper's own `git commit` works on machines with no
# global git config (the wrapper deliberately sets no identity itself).
git -C "$fixture" config user.email t@l
git -C "$fixture" config user.name t
mkdir "$fixture/mem"
printf '# Index\n\n- [Fact A](fact_a.md) - a fact\n' > "$fixture/mem/MEMORY.md"
printf -- '---\nname: fact-a\n---\n\nFact A body.\n' > "$fixture/mem/fact_a.md"
git -C "$fixture" add .
git -C "$fixture" commit -qm seed

(cd "$fixture" && python3 "$CP" begin --store mem >/dev/null)
assert_equal "0" "$?" "CLI begin exits 0 on a valid store"

printf -- '---\nname: fact-a\n---\n\nMerged.\n' > "$fixture/mem/fact_a.md"
(cd "$fixture" && python3 "$CP" commit --op dedupe -m "merge" >/dev/null)
assert_equal "0" "$?" "CLI commit lands a typed commit"

subject="$(git -C "$fixture" log -1 --format=%s)"
assert_equal "consolidate(dedupe): merge" "$subject" "typed commit subject is exact"

rc=0
(cd "$fixture" && python3 "$CP" commit --op dedupe -m "empty" >/dev/null 2>&1) || rc=$?
assert_matches "$rc" "^[1-9]" "CLI commit refuses with nothing to commit"

(cd "$fixture" && python3 "$CP" finish >/dev/null)
assert_equal "0" "$?" "CLI finish exits 0 remoteless"

rm -rf "$fixture"
trap - EXIT

print_summary
summary_exit=$?

if [ "$unittest_exit" -ne 0 ] || [ "$summary_exit" -ne 0 ]; then
  exit 1
fi
exit 0
```

The unittest fixture (`make_repo` in `test_consolidate_pass.py`) handles the same concern by setting local `user.email`/`user.name` right after `git init`.

- [ ] **Step 2: Run the shim and the full suite**

Run: `bash framework/tools/tests/test_consolidate_pass.sh && bash framework/tools/tests/run_all.sh`
Expected: shim PASSes all CLI checks; full suite exits 0 (including eval fake-pass discrimination tests, untouched)

- [ ] **Step 3: Shellcheck**

Run: `shellcheck -x --severity=warning framework/tools/tests/test_consolidate_pass.sh`
Expected: no output, exit 0

- [ ] **Step 4: Commit**

```bash
chmod +x framework/tools/tests/test_consolidate_pass.sh
git add framework/tools/tests/test_consolidate_pass.sh
git commit -m "claude-personas: consolidate_pass CLI shim wired into run_all (#89)"
```

### Task 6: `consolidate-memory` skill + FILES registration

**Files:**
- Create: `framework/skills/consolidate-memory/SKILL.md`
- Modify: `framework/FILES` (append two mappings)

**Interfaces:**
- Consumes: the wrapper CLI (exact subcommands from Tasks 2-4).
- Produces: the self-contained skill; FILES lines `framework/tools/consolidate_pass.py -> .agents/tools/consolidate_pass.py` and `framework/skills/consolidate-memory/SKILL.md -> .agents/skills/consolidate-memory/SKILL.md`.

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: consolidate-memory
description: Explicit-only consolidation pass over ONE memory store - proposes dedupe/redistribute/retire operations on a consolidate/* branch via consolidate_pass.py, delivered as a PR to the human/MM merge gate. Never auto-run; never mutates main.
---

# Consolidate Memory

## Purpose

Propose a tidied reorganization of one memory store as a reviewable branch/PR.
You are the semantic half of a two-part design: all git writes go through `consolidate_pass.py` (the deterministic half), which enforces branch isolation, store scope, and typed commits.
This skill is self-contained: follow it identically whether it was invoked as a skill or injected as a system prompt.

## Hard rules

- Explicit invocation only: never start a pass on your own initiative.
- One store per pass: the store is the directory you were pointed at; it must contain a `MEMORY.md`. If it does not, refuse and report - never guess a different directory.
- Never run `git commit`, `git push`, `git checkout`, or `gh pr create` yourself: the wrapper is the only write path.
- Never demote content out of its tier or move content to another store: you clean WITHIN the store only.

## The preservation stance (anti-smoothing)

LLM consolidation is documented to smooth away rare-but-valid facts. These rules are the countermeasure; they outrank tidiness:

- An exception NEVER merges into the rule it excepts. "Always X" + "except in S, do Y" stay distinct facts (merging them into one file is allowed only if both assertions survive verbatim in meaning).
- A fact referenced by nothing else is not therefore disposable.
- An old date is not staleness. Retire a fact ONLY when a newer fact in this store contradicts it, and cite that newer fact in the commit message.
- When in doubt, keep. A missed cleanup costs a little; a destroyed fact costs the store its trustworthiness.

## Operations

Exactly three operation types, one logical operation per commit:

- `dedupe`: two files assert the same fact -> merge into one, delete the other, update the index line(s).
- `redistribute`: one file has grown to cover several facts -> split it, add index lines for the new files.
- `retire`: a fact is contradicted by a newer fact in this store -> delete the file (or fold a one-line retirement note into the newer file), remove its index line, cite the contradicting fact in the commit message.

Every operation updates `MEMORY.md` in the same commit: after every operation, every store file has exactly one index line and every index line points at an existing file.

## Procedure

1. `python3 <tools-dir>/consolidate_pass.py begin --store <store>` (resolve `<tools-dir>`: `.agents/tools/` in an installed instance, `framework/tools/` in the framework repo).
   If begin fails, report its message and stop - do not work around it.
2. Read the ENTIRE store: `MEMORY.md` plus every linked file. Build the full operation list BEFORE editing anything, applying the preservation stance.
3. Per operation: edit the files (all pieces of the logical op together, including the index update), then
   `python3 <tools-dir>/consolidate_pass.py commit --op <dedupe|redistribute|retire> -m "<what merged/split/retired and why>"`.
   If commit rejects out-of-store paths, revert the stray edit and retry the operation.
4. `python3 <tools-dir>/consolidate_pass.py finish`.
   Report its output verbatim (PR URL, branch name, or "nothing to consolidate").
5. On any unrecoverable error, run `python3 <tools-dir>/consolidate_pass.py abort` and report what failed.

## What a good pass looks like

A handful of well-argued operations, each auditable from its commit message alone, with zero canary-type facts (exceptions, rare-but-critical, old-but-true) touched.
An empty pass on a clean store is a correct outcome, not a failure.
```

- [ ] **Step 2: Register in FILES**

Append to `framework/FILES`:

```text
framework/tools/consolidate_pass.py -> .agents/tools/consolidate_pass.py
framework/skills/consolidate-memory/SKILL.md -> .agents/skills/consolidate-memory/SKILL.md
```

- [ ] **Step 3: Run the framework-files test and full suite**

Run: `bash framework/tools/tests/test_framework_files.sh && bash framework/tools/tests/run_all.sh`
Expected: exit 0 (FILES entries resolve; nothing else regresses)

- [ ] **Step 4: Commit**

```bash
git add framework/skills/consolidate-memory/SKILL.md framework/FILES
git commit -m "claude-personas: consolidate-memory skill + FILES registration (#89)"
```

### Task 7: CONVENTIONS.md contract section

**Files:**
- Modify: `CONVENTIONS.md` (new H2 after "## Symlinks", before "## Getting started")

**Interfaces:**
- Consumes: nothing programmatic; states the contract for Tasks 2-6's artifacts.
- Produces: the AC5 doc.

- [ ] **Step 1: Write the section**

Insert into `CONVENTIONS.md`:

```markdown
## The consolidation pass

An explicit-only pass that proposes a tidied reorganization of ONE memory store on a `consolidate/*` branch, delivered as a PR to the human/MM merge gate (issue #87).
Run it via the `consolidate-memory` skill; all writes go through `consolidate_pass.py`.

**It may:** dedupe duplicate facts, redistribute an overgrown file, and retire facts contradicted by newer facts - all within a single store per pass.

**It may not:** write to `main` (the wrapper refuses to commit off its own `consolidate/*` branch), touch paths outside the target store (the wrapper rejects them), move content across stores or tiers, demote a rule out of a tier (that is the promotion ladder's job), or run unattended (no cron; `memory_cliff.py` may at most *suggest* a pass when a store nears a cliff).

**Review requirement:** the pass's output is never adopted directly; the branch/PR goes to the same human/MM merge gate as any other memory change, and the typed commit log - `consolidate(dedupe|redistribute|retire): ...`, one operation per commit - is the unit of review.

**Which guarantees are code and which are convention:** branch isolation, store scope, typed commit format, and the index<->file sync check at finish are enforced by `consolidate_pass.py`; the preservation stance (exceptions survive, old-but-true survives, retire needs a cited contradiction) and operation atomicity live in the skill text and the PR review.
The canary eval (`framework/tools/consolidation_eval/`) is the kill gate for the semantic half: the pass ships only while seeded outlier facts survive it 100%.
```

- [ ] **Step 2: Check memory_cliff still passes (CONVENTIONS.md is tier-referenced)**

Run: `python3 framework/tools/memory_cliff.py && bash framework/tools/tests/run_all.sh`
Expected: exit 0 both

- [ ] **Step 3: Commit**

```bash
git add CONVENTIONS.md
git commit -m "claude-personas: CONVENTIONS.md consolidation-pass contract (AC5) (#89)"
```

### Task 8: Live end-to-end smoke + PR

**Files:**
- None new (verification + delivery).

**Interfaces:**
- Consumes: everything above.
- Produces: a single-run live smoke record; the #89 PR.

- [ ] **Step 1: Single-run live smoke against the eval fixture**

Run (from the framework repo root; pin the session's model):
```bash
python3 framework/tools/consolidation_eval/run_eval.py --runs 1 --model "$MODEL" \
  --pass-cmd "claude -p 'You are running a consolidation pass. Consolidate the memory store in the current directory.' \
    --model $MODEL \
    --append-system-prompt-file $(pwd)/framework/skills/consolidate-memory/SKILL.md \
    --permission-mode acceptEdits --allowedTools 'Bash(python3 *),Bash(git *)'" \
  --out /tmp/smoke-89.json
```
Expected: the run completes; the pass produces a `consolidate/*` branch with typed commits; survival/cleanup numbers are reported.
This is a smoke (does the machinery work end-to-end), NOT the gate (that is 10 runs, recorded on #88 after merge).
A survival failure here is still a red flag: investigate the skill's preservation wording before opening the PR.

- [ ] **Step 2: Full verification sweep**

Run:
```bash
bash framework/tools/tests/run_all.sh && \
shellcheck -x --severity=warning framework/tools/*.sh framework/hooks/*.sh framework/tools/tests/*.sh && \
python3 framework/tools/memory_cliff.py
```
Expected: all exit 0

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin 89-consolidation-pass-mechanics
```

Then `gh pr create` with title `claude-personas: consolidation pass mechanics - wrapper + skill + contract (#89)` and a body covering: what (wrapper/skill/contract per spec), the Task 1 probe record, the Task 8 smoke record, the store-only-v1 scope trim (comment this on #89 too), and `Closes #89`.
Merge is Jin-Ho's gate; do not self-merge.

- [ ] **Step 4: Post the scope-trim note on #89**

One comment: transcripts input deferred (store-only v1, per approved spec section "Scope decisions"); link the spec file on the branch.

## Deviations

Task 6 review: SKILL.md step 5's blanket abort-on-error contradicted finish's retryable branch-intact failure paths (data-loss risk).
Step 5 rewritten to reserve abort for begin/commit failures and abandoned passes.
Sentence-per-line splits applied to five bullets.
