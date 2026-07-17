"""Tests for structural_audit.py - the deterministic baseline of the #91
side-by-side experiment (consolidation pass vs structural audit).

Run from the experiment dir: python3 -m unittest discover -s tests
"""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import structural_audit as sa  # noqa: E402


class _StoreBuilderMixin:
    def _write(self, store, rel, content):
        path = os.path.join(store, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

    def _index(self, store, entries):
        """Write MEMORY.md with one `- [Title](file.md) - hook` line per entry."""
        lines = ["# Index", ""]
        lines += [f"- [{e}]({e}) - hook" for e in entries]
        self._write(store, "MEMORY.md", "\n".join(lines) + "\n")


class TestIndexSync(_StoreBuilderMixin, unittest.TestCase):
    def test_clean_store_no_findings(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "fact_a.md", "body\n")
            self._index(store, ["fact_a.md"])
            self.assertEqual(sa.audit(store), [])

    def test_index_link_to_missing_file_reported(self):
        with tempfile.TemporaryDirectory() as store:
            self._index(store, ["ghost.md"])
            findings = sa.audit(store)
            self.assertEqual(len(findings), 1)
            self.assertIn("index links missing file: ghost.md", findings[0])

    def test_orphan_file_reported(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "orphan.md", "body\n")
            self._index(store, [])
            findings = sa.audit(store)
            self.assertEqual(len(findings), 1)
            self.assertIn("file not in index: orphan.md", findings[0])


class TestWikilinks(_StoreBuilderMixin, unittest.TestCase):
    def test_broken_wikilink_reported_with_source(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "fact_a.md", "see [[no_such_memory]]\n")
            self._index(store, ["fact_a.md"])
            findings = sa.audit(store)
            self.assertEqual(len(findings), 1)
            self.assertIn("broken wikilink", findings[0])
            self.assertIn("fact_a.md", findings[0])
            self.assertIn("no_such_memory", findings[0])

    def test_wikilink_resolving_to_filename_ok(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "fact_a.md", "see [[fact_b]]\n")
            self._write(store, "fact_b.md", "body\n")
            self._index(store, ["fact_a.md", "fact_b.md"])
            self.assertEqual(sa.audit(store), [])

    def test_wikilink_resolving_via_frontmatter_name_ok(self):
        # `[[x]]` references another memory's `name:` slug, which need not
        # equal its filename.
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "fact_a.md", "see [[the-slug]]\n")
            self._write(
                store, "fact_b.md",
                "---\nname: the-slug\ndescription: d\n---\nbody\n",
            )
            self._index(store, ["fact_a.md", "fact_b.md"])
            self.assertEqual(sa.audit(store), [])

    def test_wikilink_in_fenced_block_ignored(self):
        # A convention doc showing `[[name]]` inside a code fence is not a link.
        with tempfile.TemporaryDirectory() as store:
            self._write(
                store, "fact_a.md",
                "example:\n```\nlink with [[not_a_real_target]]\n```\n",
            )
            self._index(store, ["fact_a.md"])
            self.assertEqual(sa.audit(store), [])

    def test_wikilink_in_inline_code_ignored(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(
                store, "fact_a.md",
                "the `[[name]]` convention links memories.\n",
            )
            self._index(store, ["fact_a.md"])
            self.assertEqual(sa.audit(store), [])

    def test_wikilink_in_index_checked_too(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "MEMORY.md", "# Index\n\nsee [[nope]]\n")
            findings = sa.audit(store)
            self.assertEqual(len(findings), 1)
            self.assertIn("MEMORY.md", findings[0])
            self.assertIn("nope", findings[0])

    def test_quoted_frontmatter_name_resolves(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "fact_a.md", "see [[quoted-slug]]\n")
            self._write(
                store, "fact_b.md",
                '---\nname: "quoted-slug"\ndescription: d\n---\nbody\n',
            )
            self._index(store, ["fact_a.md", "fact_b.md"])
            self.assertEqual(sa.audit(store), [])


class TestCli(_StoreBuilderMixin, unittest.TestCase):
    def _main(self, args):
        buf, err = io.StringIO(), io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            rc = sa.main(args)
        return rc, buf.getvalue(), err.getvalue()

    def test_clean_store_exit_0(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "fact_a.md", "body\n")
            self._index(store, ["fact_a.md"])
            rc, _, _ = self._main(["--store", store])
            self.assertEqual(rc, 0)

    def test_findings_exit_1(self):
        with tempfile.TemporaryDirectory() as store:
            self._index(store, ["ghost.md"])
            rc, out, _ = self._main(["--store", store])
            self.assertEqual(rc, 1)
            self.assertIn("ghost.md", out)

    def test_missing_index_clean_error_exit_2(self):
        with tempfile.TemporaryDirectory() as store:
            rc, _, err = self._main(["--store", store])
            self.assertEqual(rc, 2)
            self.assertIn("error", err.lower())


if __name__ == "__main__":
    unittest.main()
