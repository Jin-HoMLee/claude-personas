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


if __name__ == "__main__":
    unittest.main()
