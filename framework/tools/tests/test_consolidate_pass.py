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
