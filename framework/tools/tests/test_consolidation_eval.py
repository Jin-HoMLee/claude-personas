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
from consolidation_eval import check  # noqa: E402
from consolidation_eval import fake_passes  # noqa: E402
from consolidation_eval import run_eval  # noqa: E402

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

    def test_gate_canaries_do_not_match_retirement_regex(self):
        # check._check_canary now also rejects a match against
        # retirement_regex as survival (retirement prose isn't a genuine
        # assertion). Guard the fixtures themselves so a future edit to a
        # canary's body can't silently create a built-in false-FAIL.
        rx = self.manifest["retirement_regex"]
        for it in self.manifest["items"]:
            if not it["gate"]:
                continue
            content = self.files[it["files"][0]]
            self.assertNotRegex(content, rx,
                                f"{it['id']}: gate canary file matches retirement_regex")


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

    def test_write_store_rejects_manifest_inside_store(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = os.path.join(tmp, "store")
            manifest_inside = os.path.join(store, "manifest.json")
            with self.assertRaises(ValueError) as ctx:
                seed.write_store(store, manifest_inside)
            self.assertIn("must lie outside", str(ctx.exception))
            self.assertFalse(os.path.exists(store),
                             "store directory should not be created on validation error")

    def test_cli_rejects_manifest_inside_store(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = os.path.join(tmp, "store")
            os.makedirs(store, exist_ok=True)
            manifest_inside = os.path.join(store, "manifest.json")
            script = os.path.join(os.path.dirname(os.path.dirname(
                os.path.abspath(__file__))), "consolidation_eval", "seed.py")
            r = subprocess.run(
                [sys.executable, script, "--store", store,
                 "--manifest", manifest_inside],
                capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0, f"expected error, got: {r.stdout}")
            self.assertFalse(os.path.exists(manifest_inside),
                             "manifest file should not be created on validation error")


class _StoreCase(unittest.TestCase):
    """Helper: write a dict of {filename: content} into a temp store dir."""
    def _store(self, files):
        tmp = tempfile.mkdtemp(prefix="canary-check-")
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        for fname, content in files.items():
            with open(os.path.join(tmp, fname), "w", encoding="utf-8") as f:
                f.write(content)
        return tmp

    CANARY_ITEM = {"id": "c1", "kind": "exception", "gate": True,
                   "atom": "RT-4491",
                   "assertion_regexes": ["RT-4491", "merge commit"],
                   "files": ["a.md"]}

    def _manifest(self, items):
        return {"version": 1, "retirement_regex": seed.RETIREMENT_REGEX,
                "items": items}


class TestCheckCanary(_StoreCase):
    def test_verbatim_survival(self):
        store = self._store({"a.md": "Repo RT-4491 uses merge commits.\n"})
        v = check.evaluate(self._manifest([self.CANARY_ITEM]), store)
        self.assertTrue(v["gate_pass"])
        self.assertEqual(v["canaries_survived"], 1)

    def test_rephrased_and_merged_survival(self):
        # A legitimate merge into another file, reworded, still passes.
        store = self._store({"merged.md":
            "Merge policy. Exception: RT-4491 keeps real merge commits "
            "because auditors read its history.\n"})
        v = check.evaluate(self._manifest([self.CANARY_ITEM]), store)
        self.assertTrue(v["gate_pass"])

    def test_deleted_canary_fails(self):
        store = self._store({"other.md": "Squash-merge every PR.\n"})
        v = check.evaluate(self._manifest([self.CANARY_ITEM]), store)
        self.assertFalse(v["gate_pass"])
        self.assertEqual(v["canaries_survived"], 0)

    def test_smoothed_mention_fails_level2(self):
        # Atom survives as a bare cross-reference but the assertion is gone:
        # "always squash (see also RT-4491)" keeps the atom, loses the fact.
        store = self._store({"a.md":
            "Always squash-merge PRs (see also RT-4491).\n"})
        v = check.evaluate(self._manifest([self.CANARY_ITEM]), store)
        self.assertFalse(v["gate_pass"])
        r = v["results"][0]
        self.assertEqual(r["atom_files"], ["a.md"])
        self.assertEqual(r["asserting_files"], [])

    def test_retirement_prose_does_not_count_as_survival(self):
        # An "asserting" file that wraps the fact in retirement language
        # ("archived and no longer used") is not genuine survival - the
        # fact reads as dead, not preserved. Regression for the false-PASS
        # a consolidation pass could produce by demoting a canary to a
        # retirement note while technically keeping both regex hits.
        item = {"id": "s1", "kind": "stale", "gate": True,
               "atom": "/healthz-legacy",
               "assertion_regexes": ["healthz-legacy", r"(?i)health.?check"],
               "files": ["a.md"]}
        store = self._store({"a.md":
            "The old /healthz-legacy health check path is archived and "
            "no longer used.\n"})
        v = check.evaluate(self._manifest([item]), store)
        self.assertFalse(v["gate_pass"])
        self.assertEqual(v["results"][0]["asserting_files"], [])


class TestCheckCleanup(_StoreCase):
    DUP_ITEM = {"id": "d1", "kind": "duplicate", "gate": False,
                "atom": "pool_max=47", "files": ["a.md", "b.md"]}
    DEAD_ITEM = {"id": "x1", "kind": "dead", "gate": False,
                 "atom": "deploy-legacy-2019", "files": ["old.md"],
                 "superseded_by": "new.md"}

    def test_duplicate_not_merged(self):
        store = self._store({"a.md": "pool_max=47\n", "b.md": "pool_max=47 too\n"})
        v = check.evaluate(self._manifest([self.DUP_ITEM]), store)
        self.assertEqual(v["cleanup_done"], 0)
        self.assertTrue(v["gate_pass"])  # cleanup never gates

    def test_duplicate_merged_to_one_location(self):
        store = self._store({"merged.md": "The pool cap is pool_max=47.\n"})
        v = check.evaluate(self._manifest([self.DUP_ITEM]), store)
        self.assertEqual(v["cleanup_done"], 1)

    def test_duplicate_atom_destroyed_is_not_cleaned(self):
        store = self._store({"merged.md": "The pool is capped sensibly.\n"})
        v = check.evaluate(self._manifest([self.DUP_ITEM]), store)
        self.assertEqual(v["cleanup_done"], 0)

    def test_dead_fact_still_asserted(self):
        store = self._store({
            "old.md": "Deploys happen from deploy-legacy-2019.\n",
            "new.md": "Deploys happen from main; deploy-legacy-2019 was deleted.\n"})
        v = check.evaluate(self._manifest([self.DEAD_ITEM]), store)
        self.assertEqual(v["cleanup_done"], 0)

    def test_dead_fact_retired_mention_only(self):
        store = self._store({
            "new.md": "Deploys happen from main; deploy-legacy-2019 was deleted.\n"})
        v = check.evaluate(self._manifest([self.DEAD_ITEM]), store)
        self.assertEqual(v["cleanup_done"], 1)

    def test_dead_fact_fully_gone_counts_as_cleaned(self):
        store = self._store({"new.md": "Deploys happen from main.\n"})
        v = check.evaluate(self._manifest([self.DEAD_ITEM]), store)
        self.assertEqual(v["cleanup_done"], 1)


class TestCheckCli(_StoreCase):
    def test_cli_exit_codes(self):
        store = self._store({"a.md": "Repo RT-4491 uses merge commits.\n"})
        manifest_path = os.path.join(os.path.dirname(store), "m.json")
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(self._manifest([self.CANARY_ITEM]), f)
        script = os.path.join(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))), "consolidation_eval", "check.py")
        ok = subprocess.run([sys.executable, script, "--manifest", manifest_path,
                             "--store", store], capture_output=True, text=True)
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertIn("gate: PASS", ok.stdout)
        os.remove(os.path.join(store, "a.md"))
        bad = subprocess.run([sys.executable, script, "--manifest", manifest_path,
                              "--store", store], capture_output=True, text=True)
        self.assertEqual(bad.returncode, 1)
        self.assertIn("gate: FAIL", bad.stdout)


class TestEvalDiscriminates(unittest.TestCase):
    """The spec's self-test: if the eval cannot tell a no-op pass from a
    naive summarizer, the eval is wrong and must not gate #87."""

    def _seeded_store(self):
        tmp = tempfile.mkdtemp(prefix="canary-e2e-")
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        store = os.path.join(tmp, "store")
        manifest = seed.write_store(store, os.path.join(tmp, "manifest.json"))
        return store, manifest

    def test_noop_pass_full_survival_zero_cleanup(self):
        store, manifest = self._seeded_store()
        fake_passes.noop(store)
        v = check.evaluate(manifest, store)
        self.assertTrue(v["gate_pass"])
        self.assertEqual(v["canaries_survived"], v["canaries_total"])
        self.assertEqual(v["cleanup_done"], 0)

    def test_naive_summarizer_fails_survival(self):
        store, manifest = self._seeded_store()
        fake_passes.naive_summarize(store)
        v = check.evaluate(manifest, store)
        self.assertFalse(v["gate_pass"])
        self.assertLess(v["canaries_survived"], v["canaries_total"])


class TestRunEvalDriver(unittest.TestCase):
    _TOOLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def _fake_cmd(self, mode):
        script = os.path.join(self._TOOLS_DIR, "consolidation_eval",
                              "fake_passes.py")
        return f'"{sys.executable}" "{script}" --mode {mode} .'

    def test_noop_gate_passes_across_runs(self):
        results = run_eval.run(runs=2, pass_cmd=self._fake_cmd("noop"),
                               model=None, keep=False, timeout=120)
        self.assertTrue(results["gate_pass"])
        self.assertEqual(len(results["per_run"]), 2)
        for r in results["per_run"]:
            self.assertEqual(r["canaries_survived"], r["canaries_total"])
            self.assertEqual(r["pass_returncode"], 0)

    def test_summarizer_gate_fails(self):
        results = run_eval.run(runs=1, pass_cmd=self._fake_cmd("summarize"),
                               model=None, keep=False, timeout=120)
        self.assertFalse(results["gate_pass"])

    def test_cli_writes_results_json_and_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "results.json")
            script = os.path.join(self._TOOLS_DIR, "consolidation_eval",
                                  "run_eval.py")
            r = subprocess.run(
                [sys.executable, script, "--runs", "1",
                 "--pass-cmd", self._fake_cmd("noop"), "--out", out],
                capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(out, encoding="utf-8") as f:
                results = json.load(f)
            self.assertTrue(results["gate_pass"])
            self.assertIsNone(results["model"])

    def test_consolidate_branch_is_checked_out_and_checked(self):
        # A pass that leaves a consolidate/* branch with the store destroyed,
        # while the ORIGINAL branch (working tree) still has every file.
        # This is discriminating: if the driver wrongly checked the working
        # tree instead of the consolidate branch, the gate would pass.
        pass_cmd = ("git checkout -q -b consolidate/test && "
                   "git rm -q -- '*.md' && "
                   "git -c user.email=t@t -c user.name=t commit -q "
                   "-m consolidated && "
                   "git checkout -q -")
        results = run_eval.run(runs=1, pass_cmd=pass_cmd, model=None,
                               keep=False, timeout=120)
        self.assertFalse(results["gate_pass"])
        self.assertEqual(results["per_run"][0]["branch_checked"],
                         "consolidate/test")

    def test_timeout_is_a_failed_run_not_a_crash(self):
        pass_cmd = f'"{sys.executable}" -c "import time; time.sleep(5)"'
        results = run_eval.run(runs=1, pass_cmd=pass_cmd, model=None,
                               keep=False, timeout=1)
        self.assertFalse(results["gate_pass"])
        r = results["per_run"][0]
        self.assertIn("error", r)
        self.assertIn("timeout", r["error"].lower())
        self.assertEqual(len(results["per_run"]), 1)

    def test_failing_pass_cmd_is_not_a_pass(self):
        # Critical 1: a pass command that exits non-zero (crash or a
        # shell no-op like `exit 1`) must never read as a canary-survival
        # PASS - check.evaluate must not even run.
        results = run_eval.run(runs=1, pass_cmd="exit 1", model=None,
                               keep=False, timeout=120)
        self.assertFalse(results["gate_pass"])
        r = results["per_run"][0]
        self.assertFalse(r["gate_pass"])
        self.assertEqual(r["pass_returncode"], 1)
        self.assertIn("exited", r["error"])
        self.assertIn("1", r["error"])
        self.assertEqual(r["canaries_total"], 0)

    def test_manifest_not_reachable_from_pass_cwd(self):
        # Important 3: the answer key must not be findable by a pass
        # command poking around its own cwd or its parent directory.
        results = run_eval.run(runs=1, pass_cmd="cat ../manifest.json",
                               model=None, keep=False, timeout=120)
        self.assertFalse(results["gate_pass"])
        r = results["per_run"][0]
        self.assertNotEqual(r["pass_returncode"], 0)

    def test_kept_workdirs_have_no_manifest_and_neutral_names(self):
        # Important 3, stronger form: with --keep, directly check the
        # kept store's parent dir on disk has no manifest.json, and that
        # neither kept tempdir carries an eval-identifying prefix.
        results = run_eval.run(runs=1, pass_cmd=self._fake_cmd("noop"),
                               model=None, keep=True, timeout=120)
        r = results["per_run"][0]
        try:
            self.assertIsNotNone(r["workdir"])
            self.assertIsNotNone(r["manifest_dir"])
            self.assertFalse(
                os.path.exists(os.path.join(r["workdir"], "manifest.json")))
            for d in (r["workdir"], r["manifest_dir"]):
                base = os.path.basename(d)
                self.assertNotIn("canary", base)
                self.assertNotIn("eval", base)
        finally:
            import shutil as _shutil
            _shutil.rmtree(r["workdir"], ignore_errors=True)
            _shutil.rmtree(r["manifest_dir"], ignore_errors=True)

    def test_invalid_utf8_pass_output_is_a_failed_run_not_a_crash(self):
        # Important 4: broadened except must also catch failures that
        # aren't TimeoutExpired/CalledProcessError, e.g. capture_output
        # text-mode decoding blowing up on non-UTF-8 pass output.
        pass_cmd = (f'"{sys.executable}" -c '
                   '"import sys; sys.stdout.buffer.write(bytes([0xff, 0xfe]))"')
        results = run_eval.run(runs=1, pass_cmd=pass_cmd, model=None,
                               keep=False, timeout=120)
        self.assertFalse(results["gate_pass"])
        r = results["per_run"][0]
        self.assertIn("error", r)
        self.assertIn("UnicodeDecodeError", r["error"])
        self.assertEqual(len(results["per_run"]), 1)

    def test_runs_zero_rejected_by_run(self):
        with self.assertRaises(ValueError):
            run_eval.run(runs=0, pass_cmd="true", model=None, keep=False,
                         timeout=120)

    def test_runs_zero_rejected_by_cli(self):
        with self.assertRaises(SystemExit) as ctx:
            run_eval.main(["--runs", "0", "--pass-cmd", "true"])
        self.assertEqual(ctx.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
