"""Tests for classify_findings.py - deterministic classification of raw
structural-audit findings into experiment analysis classes."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import classify_findings as cf  # noqa: E402


class _StoreBuilderMixin:
    def _write(self, store, rel, content):
        path = os.path.join(store, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)


class TestClassifyOrphan(_StoreBuilderMixin, unittest.TestCase):
    def test_orphan_listed_in_archive_index_is_archive_covered(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "project_archive_index.md",
                        "- [Old thing](project_old.md) - done\n")
            self._write(store, "project_old.md", "body\n")
            c = cf.classify_orphan(store, "project_old.md")
            self.assertEqual(c, "archive-indexed")

    def test_dated_artifact_orphan_is_dated_artifact(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "digest_2026-05-13.md", "body\n")
            self.assertEqual(
                cf.classify_orphan(store, "digest_2026-05-13.md"),
                "dated-artifact")

    def test_plain_orphan_is_unindexed(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "project_lost.md", "body\n")
            self.assertEqual(
                cf.classify_orphan(store, "project_lost.md"), "unindexed")


class TestClassifyWikilink(_StoreBuilderMixin, unittest.TestCase):
    def test_dash_underscore_mismatch(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "feedback_audit_fix.md", "body\n")
            c = cf.classify_wikilink(store, "feedback-audit-fix")
            self.assertEqual(c, "slug-style-mismatch")

    def test_md_suffix_mismatch(self):
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "feedback_x.md", "body\n")
            self.assertEqual(
                cf.classify_wikilink(store, "feedback_x.md"),
                "extension-suffixed")

    def test_non_memory_reference(self):
        with tempfile.TemporaryDirectory() as store:
            for target in ("superpowers:brainstorming",
                           "superpowers verification-before-completion",
                           "AskUserQuestion", "spin-off-project"):
                with self.subTest(target=target):
                    self.assertEqual(
                        cf.classify_wikilink(store, target),
                        "non-memory-reference")

    def test_truly_dangling(self):
        with tempfile.TemporaryDirectory() as store:
            self.assertEqual(
                cf.classify_wikilink(store, "feedback_never_written"),
                "dangling")


class TestSummaryMode(_StoreBuilderMixin, unittest.TestCase):
    def test_summary_prints_counts_but_no_filenames(self):
        # Data-minimization mode: aggregate class counts only, publishable
        # from a private store without leaking its filenames.
        import io
        from contextlib import redirect_stdout
        with tempfile.TemporaryDirectory() as store:
            self._write(store, "MEMORY.md",
                        "# Index\n\n- [Ghost](ghost_secret_project.md) - x\n")
            self._write(store, "orphan_secret_topic.md", "see [[nope]]\n")
            buf = io.StringIO()
            with redirect_stdout(buf):
                cf.main(["--store", store, "--summary"])
            out = buf.getvalue()
            self.assertIn("orphan/unindexed=1", out)
            self.assertIn("index-ghost=1", out)
            self.assertNotIn("secret", out)     # no filenames in summary mode
            self.assertNotIn("nope", out)       # no link targets either


if __name__ == "__main__":
    unittest.main()
