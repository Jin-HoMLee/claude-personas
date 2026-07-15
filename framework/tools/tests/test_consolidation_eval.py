import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

# Import the package under test from the parent framework/tools/ dir
# (same pattern as test_memory_cliff.py).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from consolidation_eval import seed  # noqa: E402

_FM_RE = re.compile(r"\A---\nname: .+\ndescription: .+\ntype: \w+\n---\n\n", re.M)


class TestSeedBuildStore(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files, cls.manifest = seed.build_store()

    def test_store_size_is_realistic(self):
        # Spec: roughly 40 memory files so the pass has real work to do.
        md = [f for f in self.files if f != "MEMORY.md"]
        self.assertGreaterEqual(len(md), 40)

    def test_item_counts(self):
        items = self.manifest["items"]
        kinds = {}
        for it in items:
            kinds[it["kind"]] = kinds.get(it["kind"], 0) + 1
        self.assertEqual(kinds, {"exception": 3, "rare": 3, "stale": 3,
                                 "duplicate": 3, "dead": 3})
        self.assertEqual(sum(1 for it in items if it["gate"]), 9)
        self.assertEqual(sum(1 for it in items if not it["gate"]), 6)

    def test_every_file_has_frontmatter(self):
        for fname, content in self.files.items():
            if fname == "MEMORY.md":
                continue
            self.assertRegex(content, _FM_RE, f"bad frontmatter in {fname}")

    def test_index_lists_every_file(self):
        index = self.files["MEMORY.md"]
        for fname in self.files:
            if fname == "MEMORY.md":
                continue
            self.assertIn(f"({fname})", index, f"{fname} missing from MEMORY.md")

    def test_atom_hygiene(self):
        # Each atom appears ONLY in its manifest-listed files (dead items:
        # also the superseding file), never in MEMORY.md or any other file.
        for it in self.manifest["items"]:
            allowed = set(it["files"]) | ({it["superseded_by"]}
                                          if "superseded_by" in it else set())
            hits = {f for f, c in self.files.items() if it["atom"] in c}
            self.assertEqual(hits, allowed,
                             f"atom {it['atom']!r} leaked: {hits ^ allowed}")

    def test_atoms_not_in_descriptions(self):
        # The naive summarizer keeps descriptions; atoms must live in bodies.
        for fname, content in self.files.items():
            if fname == "MEMORY.md":
                continue
            desc = content.split("description:", 1)[1].split("\n", 1)[0]
            for it in self.manifest["items"]:
                self.assertNotIn(it["atom"], desc,
                                 f"atom in description of {fname}")

    def test_canaries_pass_their_own_assertions(self):
        # Seed-time sanity: every canary's regexes match its own file.
        for it in self.manifest["items"]:
            if not it["gate"]:
                continue
            content = self.files[it["files"][0]]
            for rx in it["assertion_regexes"]:
                self.assertRegex(content, rx,
                                 f"{it['id']}: regex {rx!r} misses own file")

    def test_dead_items_superseding_note_marks_retirement(self):
        rx = self.manifest["retirement_regex"]
        for it in self.manifest["items"]:
            if it["kind"] != "dead":
                continue
            self.assertRegex(self.files[it["superseded_by"]], rx)
            # ...but the dead note itself asserts the fact as current.
            self.assertNotRegex(self.files[it["files"][0]], rx)


class TestSeedWriteStore(unittest.TestCase):
    def test_write_store_materializes_and_keeps_manifest_outside(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = os.path.join(tmp, "store")
            manifest_path = os.path.join(tmp, "manifest.json")
            manifest = seed.write_store(store, manifest_path)
            self.assertTrue(os.path.isfile(os.path.join(store, "MEMORY.md")))
            with open(manifest_path, encoding="utf-8") as f:
                on_disk = json.load(f)
            self.assertEqual(on_disk, manifest)
            # The answer key must not be inside the store the pass reads.
            self.assertFalse(os.path.exists(os.path.join(store, "manifest.json")))

    def test_cli_smoke(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = os.path.join(tmp, "store")
            manifest_path = os.path.join(tmp, "m.json")
            script = os.path.join(os.path.dirname(os.path.dirname(
                os.path.abspath(__file__))), "consolidation_eval", "seed.py")
            r = subprocess.run(
                [sys.executable, script, "--store", store,
                 "--manifest", manifest_path],
                capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(os.path.isfile(manifest_path))


if __name__ == "__main__":
    unittest.main()
