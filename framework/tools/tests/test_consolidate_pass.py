"""test_consolidate_pass.py - guard tests for consolidate_pass.py (#89)."""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

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


def make_root_store_repo(tmp):
    """Git repo whose root IS the store (the canary-eval fixture's shape):
    MEMORY.md + fact_a.md live directly at the repo root, no subdir."""
    _git(tmp, "init", "-q", "-b", "main", ".")
    _git(tmp, "config", "user.email", "t@l")
    _git(tmp, "config", "user.name", "t")
    with open(os.path.join(tmp, "MEMORY.md"), "w") as f:
        f.write("# Index\n\n- [Fact A](fact_a.md) - a fact\n")
    with open(os.path.join(tmp, "fact_a.md"), "w") as f:
        f.write("---\nname: fact-a\n---\n\nFact A body.\n")
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

    def test_begin_refuses_detached_head(self):
        _git(self.root, "checkout", "-q", "--detach")
        self.assertNotEqual(self._begin(), 0)
        self.assertIsNone(cp.config_get(self.root, "consolidate.branch"))
        branches = _git(self.root, "branch", "--list", "consolidate/*").stdout.strip()
        self.assertEqual(branches, "")

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

    def test_commit_rejects_rename_smuggled_from_outside(self):
        _git(self.root, "mv", "README.md", "mem/readme_fact.md")
        self.assertNotEqual(
            cp.main(["commit", "--op", "redistribute", "-m", "m"]), 0)
        self.assertEqual(
            _git(self.root, "log", "-1", "--format=%s").stdout.strip(), "seed")

    def test_commit_allows_in_store_rename(self):
        _git(self.root, "mv", "mem/fact_a.md", "mem/fact_b.md")
        self._edit("mem/MEMORY.md", "# Index\n\n- [Fact A](fact_b.md) - a fact\n")
        rc = cp.main(["commit", "--op", "redistribute", "-m", "rename a to b"])
        self.assertEqual(rc, 0)
        subj = _git(self.root, "log", "-1", "--format=%s").stdout.strip()
        self.assertEqual(subj, "consolidate(redistribute): rename a to b")


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

    def test_index_sync_ignores_cross_store_links(self):
        # A cross-store link (e.g. shared/MEMORY.md) never resolves against
        # this store's flat os.listdir() basenames and must not be flagged.
        idx = os.path.join(self.root, "mem", "MEMORY.md")
        with open(idx, "a") as f:
            f.write("- [Shared](shared/MEMORY.md) - cross-store\n")
        # Also make a real in-store edit so there's something to commit.
        with open(os.path.join(self.root, "mem", "fact_a.md"), "w") as f:
            f.write("---\nname: fact-a\n---\n\nMerged.\n")
        rc = cp.main(["commit", "--op", "redistribute", "-m", "add cross-store link"])
        self.assertEqual(rc, 0)
        self.assertEqual(cp.index_sync_errors(self.root, "mem"), [])
        self.assertEqual(cp.main(["finish"]), 0)

    def test_index_sync_accepts_dot_slash_links(self):
        # A `./`-prefixed same-directory link (e.g. `./fact_a.md`) must be
        # normalized before the cross-store "/" filter, else the on-disk
        # file is falsely flagged as "file not in index" and finish wedges.
        idx = os.path.join(self.root, "mem", "MEMORY.md")
        with open(idx, "w") as f:
            f.write("# Index\n\n- [Fact A](./fact_a.md) - a fact\n")
        with open(os.path.join(self.root, "mem", "fact_a.md"), "w") as f:
            f.write("---\nname: fact-a\n---\n\nMerged.\n")
        rc = cp.main(["commit", "--op", "redistribute", "-m", "dot-slash link"])
        self.assertEqual(rc, 0)
        self.assertEqual(cp.index_sync_errors(self.root, "mem"), [])
        self.assertEqual(cp.main(["finish"]), 0)

    def test_finish_fails_cleanly_when_index_deleted(self):
        os.remove(os.path.join(self.root, "mem", "MEMORY.md"))
        rc = cp.main(["commit", "--op", "retire", "-m", "removed index"])
        self.assertEqual(rc, 0)
        self.assertNotEqual(cp.main(["finish"]), 0)

    def test_finish_without_gh_keeps_config(self):
        # Approach chosen: strip PATH down to a temp bin dir containing only
        # a symlink to the real git binary, so `gh` genuinely resolves to
        # nothing via shutil.which - exercising the real guard end-to-end
        # rather than mocking it.
        git_path = shutil.which("git")
        self.assertIsNotNone(git_path, "git must be on PATH to run this test")
        with tempfile.TemporaryDirectory(prefix="bare-") as bare_dir, \
                tempfile.TemporaryDirectory(prefix="bin-") as bin_dir:
            bare_repo = os.path.join(bare_dir, "origin.git")
            subprocess.run(["git", "init", "-q", "--bare", bare_repo],
                           check=True, capture_output=True, text=True)
            _git(self.root, "remote", "add", "origin", f"file://{bare_repo}")
            self._commit_op()
            os.symlink(git_path, os.path.join(bin_dir, "git"))
            old_path = os.environ.get("PATH")
            os.environ["PATH"] = bin_dir
            try:
                rc = cp.main(["finish"])
            finally:
                if old_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = old_path
            self.assertNotEqual(rc, 0)
            self.assertIsNotNone(cp.config_get(self.root, "consolidate.branch"))
            branch = _git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
            self.assertTrue(branch.startswith("consolidate/"))


class TestStoreAtRoot(unittest.TestCase):
    # Same cwd note as TestCommit/TestFinishAbort: commit/finish resolve
    # the repo from the process cwd, so chdir into the fixture. This
    # fixture is the canary-eval store shape (store == repo root) that
    # begin/commit/finish previously rejected - see the plan doc's
    # Deviations entry for smoke round 2.
    def setUp(self):
        self._td = tempfile.TemporaryDirectory(prefix="mem-root-")
        self.root = make_root_store_repo(self._td.name)
        self._oldcwd = os.getcwd()
        os.chdir(self.root)

    def tearDown(self):
        os.chdir(self._oldcwd)
        self._td.cleanup()

    def test_begin_root_store_creates_root_branch(self):
        rc = cp.main(["begin", "--store", self.root])
        self.assertEqual(rc, 0)
        branch = _git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        self.assertTrue(branch.startswith("consolidate/root-"))
        self.assertEqual(cp.config_get(self.root, "consolidate.store"), ".")

    def test_commit_root_store_typed_prefix(self):
        self.assertEqual(cp.main(["begin", "--store", self.root]), 0)
        with open(os.path.join(self.root, "fact_a.md"), "w") as f:
            f.write("---\nname: fact-a\n---\n\nMerged body.\n")
        rc = cp.main(["commit", "--op", "dedupe", "-m", "merge a into a"])
        self.assertEqual(rc, 0)
        subj = _git(self.root, "log", "-1", "--format=%s").stdout.strip()
        self.assertEqual(subj, "consolidate(dedupe): merge a into a")

    def test_finish_root_store_remoteless_succeeds(self):
        self.assertEqual(cp.main(["begin", "--store", self.root]), 0)
        # Body-only edit to fact_a.md keeps index<->file sync intact:
        # MEMORY.md still links fact_a.md, and fact_a.md still exists.
        with open(os.path.join(self.root, "fact_a.md"), "w") as f:
            f.write("---\nname: fact-a\n---\n\nMerged body.\n")
        self.assertEqual(cp.main(["commit", "--op", "dedupe", "-m", "merge"]), 0)
        rc = cp.main(["finish"])
        self.assertEqual(rc, 0)
        branch = _git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        self.assertTrue(branch.startswith("consolidate/root-"))
        self.assertIsNone(cp.config_get(self.root, "consolidate.branch"))

    def test_begin_refuses_dirty_root_store(self):
        with open(os.path.join(self.root, "fact_a.md"), "a") as f:
            f.write("dirt\n")
        rc = cp.main(["begin", "--store", self.root])
        self.assertNotEqual(rc, 0)
        self.assertIsNone(cp.config_get(self.root, "consolidate.branch"))


class TestDotDirStore(unittest.TestCase):
    """#95: a store under a dot-directory (.agents/memory - the framework's
    own documented instance layout) must yield a valid pass branch; a ref
    component starting with '.' is rejected by git check-ref-format."""

    def setUp(self):
        self._td = tempfile.TemporaryDirectory(prefix="mem-")
        tmp = self._td.name
        _git(tmp, "init", "-q", "-b", "main", ".")
        _git(tmp, "config", "user.email", "t@l")
        _git(tmp, "config", "user.name", "t")
        os.makedirs(os.path.join(tmp, ".agents", "memory"))
        with open(os.path.join(tmp, ".agents", "memory", "MEMORY.md"), "w") as f:
            f.write("# Index\n\n- [Fact A](fact_a.md) - a fact\n")
        with open(os.path.join(tmp, ".agents", "memory", "fact_a.md"), "w") as f:
            f.write("---\nname: fact-a\n---\n\nFact A body.\n")
        _git(tmp, "add", ".")
        _git(tmp, "commit", "-qm", "seed")
        self.root = tmp

    def tearDown(self):
        self._td.cleanup()

    def test_begin_dot_dir_store_creates_valid_branch(self):
        rc = cp.main(
            ["begin", "--store", os.path.join(self.root, ".agents", "memory")])
        self.assertEqual(rc, 0)
        branch = _git(self.root, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        self.assertTrue(branch.startswith("consolidate/agents-memory-"), branch)
        self.assertEqual(
            cp.config_get(self.root, "consolidate.store"),
            os.path.join(".agents", "memory"))


class TestBranchSlug(unittest.TestCase):
    def test_plain_path_unchanged(self):
        self.assertEqual(cp.branch_slug("mem"), "mem")

    def test_nested_path_joined(self):
        self.assertEqual(cp.branch_slug(os.path.join("a", "b")), "a-b")

    def test_leading_dot_component_stripped(self):
        self.assertEqual(
            cp.branch_slug(os.path.join(".agents", "memory")), "agents-memory")

    def test_ref_hostile_chars_mapped_and_collapsed(self):
        self.assertEqual(cp.branch_slug("a b..c"), "a-b-c")

    def test_all_hostile_falls_back(self):
        self.assertEqual(cp.branch_slug("..."), "store")


class TestIndexSyncCodeStripping(unittest.TestCase):
    """#97 defect 1: links inside inline code or fenced blocks are format
    examples, not index entries - they must not register as ghosts."""

    def _errors(self, index_text):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "mem"))
            with open(os.path.join(tmp, "mem", "MEMORY.md"), "w") as f:
                f.write(index_text)
            with open(os.path.join(tmp, "mem", "fact_a.md"), "w") as f:
                f.write("body\n")
            return cp.index_sync_errors(tmp, "mem")

    def test_inline_code_format_example_not_a_ghost(self):
        # cerebrum's real index header shape: the format documented in backticks.
        errs = self._errors(
            "# Index\n\nOne line per file (`- [Title](file.md) - hook`).\n\n"
            "- [Fact A](fact_a.md) - a fact\n")
        self.assertEqual(errs, [])

    def test_fenced_block_example_not_a_ghost(self):
        errs = self._errors(
            "# Index\n\n```\n- [Example](ghost.md) - not real\n```\n\n"
            "- [Fact A](fact_a.md) - a fact\n")
        self.assertEqual(errs, [])

    def test_real_ghost_still_detected(self):
        errs = self._errors(
            "# Index\n\n- [Fact A](fact_a.md) - a\n- [Gone](missing.md) - b\n")
        self.assertEqual(errs, ["index links missing file: missing.md"])


class TestFinishDeltaGate(unittest.TestCase):
    """#97 defect 2: finish must block only on sync errors the PASS introduced.
    Pre-existing store rot (e.g. layered-index conventions the flat check
    can't see) is warned about, never a delivery blocker."""

    def setUp(self):
        self._td = tempfile.TemporaryDirectory(prefix="mem-")
        self.root = make_repo(self._td.name)
        # Pre-existing rot, committed BEFORE the pass: an unindexed file.
        with open(os.path.join(self.root, "mem", "orphan.md"), "w") as f:
            f.write("unindexed but legitimate (archive-indexed in real life)\n")
        _git(self.root, "add", ".")
        _git(self.root, "commit", "-qm", "pre-existing orphan")
        self._oldcwd = os.getcwd()
        os.chdir(self.root)
        cp.main(["begin", "--store", os.path.join(self.root, "mem")])

    def tearDown(self):
        os.chdir(self._oldcwd)
        self._td.cleanup()

    def _edit(self, relpath, text):
        with open(os.path.join(self.root, relpath), "w") as f:
            f.write(text)

    def _finish(self):
        buf, err = io.StringIO(), io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            rc = cp.main(["finish"])
        return rc, buf.getvalue(), err.getvalue()

    def test_begin_snapshots_preexisting_errors(self):
        snap = cp.snapshot_path(self.root)
        self.assertTrue(os.path.isfile(snap))
        with open(snap) as f:
            self.assertIn("file not in index: orphan.md", f.read())

    def test_finish_delivers_despite_preexisting_errors(self):
        self._edit("mem/fact_a.md", "---\nname: fact-a\n---\n\nTidied body.\n")
        self.assertEqual(cp.main(["commit", "--op", "dedupe", "-m", "tidy"]), 0)
        rc, out, err = self._finish()
        self.assertEqual(rc, 0)                    # no remote -> branch deliverable
        self.assertIn("OK: 1 operation(s)", out)
        self.assertIn("pre-existing", err)         # warned, not silent
        self.assertIn("orphan.md", err)

    def test_finish_blocks_on_error_introduced_by_pass(self):
        os.remove(os.path.join(self.root, "mem", "fact_a.md"))
        self.assertEqual(cp.main(["commit", "--op", "retire", "-m", "drop a"]), 0)
        rc, _, err = self._finish()
        self.assertNotEqual(rc, 0)
        self.assertIn("fact_a.md", err)            # the NEW ghost blocks
        # the pre-existing orphan is not among the blocking FAIL lines
        fail_lines = [l for l in err.splitlines() if l.startswith("FAIL")]
        self.assertFalse(any("orphan.md" in l for l in fail_lines))

    def test_successful_finish_removes_snapshot(self):
        self._edit("mem/fact_a.md", "---\nname: fact-a\n---\n\nTidied body.\n")
        cp.main(["commit", "--op", "dedupe", "-m", "tidy"])
        rc, _, _ = self._finish()
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(cp.snapshot_path(self.root)))

    def test_abort_removes_snapshot(self):
        buf, err = io.StringIO(), io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            self.assertEqual(cp.main(["abort"]), 0)
        self.assertFalse(os.path.exists(cp.snapshot_path(self.root)))


if __name__ == "__main__":
    unittest.main()
