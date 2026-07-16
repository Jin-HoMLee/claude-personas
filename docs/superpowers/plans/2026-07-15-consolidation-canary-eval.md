# Consolidation Canary Eval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the AC1 kill-gate eval for claude-personas#87: seed canaries into a synthetic memory store, run a consolidation pass, deterministically verify 100% canary survival.

**Architecture:** A `consolidation_eval` package under `framework/tools/` with three CLIs (`seed.py`, `check.py`, `run_eval.py`) plus scripted `fake_passes.py`; a unittest suite proves the eval discriminates a no-op pass from a naive summarizer before it ever judges the real pass.

**Tech Stack:** Python 3 stdlib only (argparse/json/os/re/subprocess/tempfile), bash test wrapper, unittest via `python3 -m unittest discover`.

**Spec:** `docs/superpowers/specs/2026-07-15-consolidation-canary-eval-design.md`. Tracking: claude-personas#88.

## Global Constraints

- stdlib-only Python, in the style of `framework/tools/memory_cliff.py`; no third-party deps, zero network in seed/check/fakes/tests.
- The manifest (answer key) is written OUTSIDE the store directory; the pass under eval must never see it.
- Fixture content is fully synthetic; nothing copied from cerebrum, splice, or user memory (public repo).
- No LLM judge anywhere in the gate path; survival checks are substring + regex only.
- Gate rule: N runs (default 10), 100% of the 9 canaries survive in every run; cleanup score (x/6) is reported, never gated on.
- Planted `description:` frontmatter lines must never contain the item's atom (the naive summarizer keeps descriptions; atoms live in bodies only).
- Do NOT add the eval to `framework/FILES` (it is framework-dev tooling, not installable instance payload).
- All new `.sh` files must pass the repo's shellcheck CI gate (warning severity).
- Commit prefix: `claude-personas: ...`. No AI co-author lines.
- No em dashes in any authored file; use plain dashes.

## File Structure

```
framework/tools/consolidation_eval/
  __init__.py        # empty package marker
  seed.py            # fixture generator + manifest writer (Task 1)
  check.py           # survival/cleanup verdict engine + CLI (Task 2)
  fake_passes.py     # scripted no-op + naive-summarizer passes (Task 3)
  run_eval.py        # N-run driver: seed -> git -> pass-cmd -> check (Task 4)
framework/tools/tests/
  test_consolidation_eval.py   # unittest suite (grown across Tasks 1-4)
  test_consolidation_eval.sh   # wrapper so run_all.sh picks the suite up (Task 5)
```

Interfaces between modules (used by every later task):

- `seed.build_store() -> tuple[dict[str, str], dict]` - returns `(files, manifest)`: relative-filename -> full file content, and the manifest dict.
- `seed.write_store(store_dir: str, manifest_path: str) -> dict` - materializes files under `store_dir`, writes manifest JSON to `manifest_path`, returns the manifest dict.
- `check.evaluate(manifest: dict, store_dir: str) -> dict` - returns the verdict dict (schema in Task 2).
- `fake_passes.noop(store_dir: str)` / `fake_passes.naive_summarize(store_dir: str)`.
- `run_eval.run(runs: int, pass_cmd: str, model: str | None, keep: bool, timeout: int) -> dict` - returns the aggregate results dict (schema in Task 4).

Manifest schema (produced by Task 1, consumed by Tasks 2-4):

```json
{
  "version": 1,
  "retirement_regex": "(?i)retired|superseded|obsolete|deleted|archived|no longer",
  "items": [
    {"id": "exc-1", "kind": "exception", "gate": true, "atom": "RT-4491",
     "assertion_regexes": ["RT-4491", "merge commit"],
     "files": ["feedback_merge_policy_rt4491_exception.md"]},
    {"id": "dup-1", "kind": "duplicate", "gate": false, "atom": "pool_max=47",
     "files": ["reference_db_pool_cap.md", "feedback_db_pool_sizing.md"]},
    {"id": "dead-1", "kind": "dead", "gate": false, "atom": "deploy-legacy-2019",
     "files": ["project_deploy_branch_2019.md"],
     "superseded_by": "project_deploy_from_main_2026.md"}
  ]
}
```

---

### Task 1: seed.py - fixture generator + manifest

**Files:**
- Create: `framework/tools/consolidation_eval/__init__.py`
- Create: `framework/tools/consolidation_eval/seed.py`
- Test: `framework/tools/tests/test_consolidation_eval.py`

**Interfaces:**
- Consumes: nothing (leaf module).
- Produces: `build_store() -> (files: dict[str, str], manifest: dict)`, `write_store(store_dir: str, manifest_path: str) -> dict`, module constants `RETIREMENT_REGEX: str` and `FRONTMATTER: str`. Filenames are `<type>_<name-with-underscores>.md` plus `MEMORY.md`.

- [ ] **Step 1: Write the failing tests**

Create `framework/tools/tests/test_consolidation_eval.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: FAIL at import time with `ModuleNotFoundError: No module named 'consolidation_eval'`.

- [ ] **Step 3: Create the package and seed.py**

Create empty `framework/tools/consolidation_eval/__init__.py` (zero bytes).

Create `framework/tools/consolidation_eval/seed.py`:

```python
#!/usr/bin/env python3
"""seed.py - generate the canary-eval fixture store (claude-personas#88).

Builds a synthetic substrate memory store (MEMORY.md index + one-fact-per-file
Markdown with frontmatter) containing:
  - 9 kill-gate canaries (3 outvoted exceptions, 3 rare-but-critical facts,
    3 stale-looking survivors) that a consolidation pass MUST preserve, and
  - 6 cleanup targets (3 duplicate pairs, 3 dead facts) that a working pass
    SHOULD consolidate.
Writes a manifest.json answer key OUTSIDE the store directory: the pass under
evaluation reads the store and must never see the key.

All content is synthetic. Nothing here is copied from any real memory store.

Usage:
    python3 seed.py --store DIR --manifest PATH
"""
from __future__ import annotations

import argparse
import json
import os
import sys

FRONTMATTER = "---\nname: {name}\ndescription: {description}\ntype: {type}\n---\n\n"

RETIREMENT_REGEX = r"(?i)retired|superseded|obsolete|deleted|archived|no longer"


def _f(name: str, description: str, body: str, type_: str = "feedback") -> dict:
    return {"name": name, "description": description, "body": body, "type": type_}


# --------------------------------------------------------------------------- #
# Filler: plausible generic notes, including the three 3-note majority
# clusters that each exception canary contradicts.
# --------------------------------------------------------------------------- #
FILLER = [
    # Majority cluster A: squash-merge everywhere (exc-1 is the exception).
    _f("squash-merge-default", "PRs are squash-merged to keep main linear",
       "Squash-merge every PR.\n\n**Why:** one commit per change keeps main linear and revertable.\n"),
    _f("squash-merge-release-notes", "Squash merges make release notes map 1:1 to PRs",
       "Because we squash-merge, each main commit maps to exactly one PR, so release notes are generated from the commit log.\n"),
    _f("squash-merge-bisect", "git bisect works best on our squash-merged history",
       "Keep squash-merging PRs; bisect runs assume every main commit builds.\n"),
    # Majority cluster B: retry API calls (exc-2 is the exception).
    _f("retry-api-calls", "Transient API failures are retried up to 3 times",
       "Retry failed API calls up to 3 times with exponential backoff.\n"),
    _f("retry-backoff-jitter", "Retries use jittered exponential backoff",
       "All HTTP retries use exponential backoff with jitter to avoid thundering herds.\n"),
    _f("retry-idempotent-get", "GET requests are always safe to retry",
       "GETs are idempotent; retry them freely on 5xx responses.\n"),
    # Majority cluster C: pin dependencies (exc-3 is the exception).
    _f("pin-dependencies", "Dependencies are pinned to exact versions",
       "Pin every dependency to an exact version in the lockfile.\n"),
    _f("pin-docker-base", "Docker base images are pinned by digest",
       "Base images are pinned by sha256 digest, not by tag.\n"),
    _f("pin-ci-actions", "CI actions are pinned to commit SHAs",
       "Pin GitHub Actions to full commit SHAs rather than version tags.\n"),
    # Generic filler.
    _f("tests-before-commit", "Run the test suite before every commit",
       "Run the full test suite locally before committing.\n"),
    _f("small-prs", "Keep PRs small and single-purpose",
       "One logical change per PR; split refactors from behavior changes.\n"),
    _f("review-checklist", "Code review uses the shared checklist",
       "Reviewers walk the shared checklist: tests, docs, error paths, naming.\n"),
    _f("feature-flags", "Risky changes ship behind feature flags",
       "Gate risky changes behind a flag; default off in production.\n"),
    _f("log-structured", "Logs are structured JSON, one event per line",
       "Emit structured JSON logs; no multi-line log records.\n"),
    _f("timezone-utc", "All timestamps are stored in UTC",
       "Store and log timestamps in UTC; convert only at display time.\n"),
    _f("secrets-in-vault", "Secrets live in the vault, never in the repo",
       "No secrets in the repo or CI variables; fetch from the vault at runtime.\n"),
    _f("branch-naming", "Branches are named issue-number-topic",
       "Branch names: <issue-number>-<short-topic>, lowercase, hyphenated.\n"),
    _f("todo-issues", "TODOs in code must reference an issue",
       "A TODO comment without an issue number fails review.\n"),
    _f("api-versioning", "Public API routes carry a version prefix",
       "All public routes are versioned: /v1/, /v2/; no unversioned endpoints.\n"),
    _f("error-messages-actionable", "Error messages say what to do next",
       "Every user-facing error names the failing input and the next step.\n"),
    _f("db-migrations-forward", "Database migrations are forward-only",
       "Never edit an applied migration; add a new forward migration instead.\n"),
    _f("changelog-generated", "The changelog is generated, never hand-edited",
       "CHANGELOG.md is tool-generated from commit messages; do not edit it by hand.\n"),
    _f("weekly-deps-audit", "Dependency audit runs weekly in CI",
       "The weekly CI job audits dependencies for known CVEs.\n"),
]

# --------------------------------------------------------------------------- #
# Kill-gate canaries. Each carries a distinctive atom that appears nowhere
# else in the fixture, plus assertion regexes that a legitimate rephrase
# still matches but a smoothed-away fact does not.
# --------------------------------------------------------------------------- #
CANARIES = [
    {
        "id": "exc-1", "kind": "exception", "atom": "RT-4491",
        "assertion_regexes": ["RT-4491", "merge commit"],
        "file": _f("merge-policy-audited-repo-exception",
                   "Exception to the squash-merge rule for one audited repo",
                   "Repo RT-4491 uses merge commits, not squash merges.\n\n"
                   "**Why:** its history is externally audited; squashing destroys the audit trail.\n"),
    },
    {
        "id": "exc-2", "kind": "exception", "atom": "PX-7203",
        "assertion_regexes": ["PX-7203", r"(?i)(never|not).{0,60}retr"],
        "file": _f("batch-export-no-retry",
                   "One endpoint must never be retried despite the retry rule",
                   "The /v2/batch-export endpoint must NEVER be retried.\n\n"
                   "**Why:** its idempotency token PX-7203 is single-use; a retry double-submits the export.\n"),
    },
    {
        "id": "exc-3", "kind": "exception", "atom": "tk-braid",
        "assertion_regexes": ["tk-braid", r"(?i)float|minor version"],
        "file": _f("internal-package-floats",
                   "One internal package deliberately floats on minor versions",
                   "The internal package tk-braid floats on minor versions on purpose.\n\n"
                   "**Why:** upstream ships hotfixes as minors; pinning it exact has caused two incident nights.\n"),
    },
    {
        "id": "rare-1", "kind": "rare", "atom": "SK-stg-",
        "assertion_regexes": ["SK-stg-", "SK-prd-"],
        "file": _f("api-key-prefixes",
                   "Staging and production API keys have distinct prefixes",
                   "Staging API keys use the SK-stg- prefix; production keys use SK-prd-.\n\n"
                   "A key with the wrong prefix fails silently with a 200 and an empty payload.\n",
                   type_="reference"),
    },
    {
        "id": "rare-2", "kind": "rare", "atom": "03:15 UTC",
        "assertion_regexes": ["03:15", "03:20"],
        "file": _f("backup-cron-deadline",
                   "The backup job has a hard finish deadline before the snapshot",
                   "The backup cron must finish before 03:15 UTC.\n\n"
                   "The volume snapshot fires at 03:20 and captures a half-written backup if the job is still running.\n",
                   type_="reference"),
    },
    {
        "id": "rare-3", "kind": "rare", "atom": "WH-88410",
        "assertion_regexes": ["WH-88410", r"(?i)rotat"],
        "file": _f("webhook-hmac-key",
                   "Vendor webhook signatures use one specific HMAC key id",
                   "Vendor webhook signatures are verified against HMAC key id WH-88410.\n\n"
                   "Rotating it requires emailing the vendor first; they hard-code the key id on their side.\n",
                   type_="reference"),
    },
    {
        "id": "stale-1", "kind": "stale", "atom": "/healthz-legacy",
        "assertion_regexes": ["healthz-legacy"],
        "file": _f("lb-health-check-path",
                   "The load balancer health check path (2019 note, still configured)",
                   "(2019-03-10) The load balancer health check path is /healthz-legacy.\n",
                   type_="reference"),
    },
    {
        "id": "stale-2", "kind": "stale", "atom": "INV-00001234",
        "assertion_regexes": ["INV-00001234", r"(?i)zero.?pad"],
        "file": _f("invoice-number-format",
                   "Invoice numbers are zero-padded to 8 digits (2018 note)",
                   "(2018-06-02) Invoice numbers are zero-padded to 8 digits, e.g. INV-00001234.\n"
                   "Downstream accounting imports reject shorter numbers.\n",
                   type_="reference"),
    },
    {
        "id": "stale-3", "kind": "stale", "atom": "corp-legacy.example",
        "assertion_regexes": ["corp-legacy.example"],
        "file": _f("printer-dns-zone",
                   "Office printers resolve via an old DNS zone (2017 note)",
                   "(2017-11-20) Office printers resolve only via the corp-legacy.example DNS zone.\n",
                   type_="reference"),
    },
]

# --------------------------------------------------------------------------- #
# Cleanup targets: duplicates (should merge) and dead facts (should retire).
# --------------------------------------------------------------------------- #
DUPLICATES = [
    {
        "id": "dup-1", "atom": "pool_max=47",
        "file_a": _f("db-pool-cap",
                     "The database connection pool cap",
                     "The database connection pool is capped at pool_max=47 in db.conf.\n",
                     type_="reference"),
        "file_b": _f("db-pool-sizing",
                     "Why the connection pool is sized the way it is",
                     "We size the pool below the DB's 50-connection license limit: pool_max=47 leaves headroom for two admin sessions and the monitor.\n"),
    },
    {
        "id": "dup-2", "atom": "artifact-cache.example.net",
        "file_a": _f("artifact-mirror-host",
                     "The artifact mirror hostname",
                     "Build artifacts are mirrored at artifact-cache.example.net.\n",
                     type_="reference"),
        "file_b": _f("artifact-mirror-usage",
                     "Use the artifact mirror for CI downloads",
                     "CI downloads dependencies from artifact-cache.example.net instead of the upstream registry.\n"),
    },
    {
        "id": "dup-3", "atom": "ttl=900",
        "file_a": _f("dns-ttl-services",
                     "Service DNS records use a 15-minute TTL",
                     "Service DNS records are created with ttl=900.\n",
                     type_="reference"),
        "file_b": _f("dns-ttl-rationale",
                     "The DNS TTL balances failover speed against query load",
                     "We keep ttl=900 on service records: short enough for failover, long enough to keep resolver load sane.\n"),
    },
]

DEAD = [
    {
        "id": "dead-1", "atom": "deploy-legacy-2019",
        "dead": _f("deploy-branch",
                   "Deploys happen from the dedicated deploy branch",
                   "Deploys happen from the deploy-legacy-2019 branch.\n",
                   type_="project"),
        "superseding": _f("deploy-from-main",
                          "Deploys moved to main in 2026",
                          "Since 2026-01, deploys happen from main. The deploy-legacy-2019 branch was deleted.\n",
                          type_="project"),
    },
    {
        "id": "dead-2", "atom": "ubuntu-legacy-18",
        "dead": _f("ci-runner-image",
                   "CI runs on the standard runner image",
                   "CI runs on the ubuntu-legacy-18 runner image.\n",
                   type_="project"),
        "superseding": _f("ci-runner-migration",
                          "CI runners migrated to ubuntu-24",
                          "CI runners migrated to ubuntu-24 in 2026-03; the ubuntu-legacy-18 image is obsolete.\n",
                          type_="project"),
    },
    {
        "id": "dead-3", "atom": "#ops-pager-legacy",
        "dead": _f("alert-channel",
                   "Error-budget alerts go to the ops pager channel",
                   "Error-budget alerts go to the #ops-pager-legacy channel.\n",
                   type_="project"),
        "superseding": _f("alert-channel-move",
                          "Alerts moved to the new ops channel",
                          "Alerts moved to #ops-alerts in 2026-02; #ops-pager-legacy is archived.\n",
                          type_="project"),
    },
]


def _filename(entry: dict) -> str:
    return "{}_{}.md".format(entry["type"], entry["name"].replace("-", "_"))


def _render(entry: dict) -> str:
    return FRONTMATTER.format(name=entry["name"], description=entry["description"],
                              type=entry["type"]) + entry["body"]


def build_store() -> tuple[dict, dict]:
    """Return (files, manifest): filename -> content, and the answer key."""
    files: dict[str, str] = {}
    descriptions: dict[str, str] = {}

    def add(entry: dict) -> str:
        fname = _filename(entry)
        if fname in files:
            raise ValueError(f"duplicate fixture filename: {fname}")
        files[fname] = _render(entry)
        descriptions[fname] = entry["description"]
        return fname

    items = []
    for entry in FILLER:
        add(entry)
    for c in CANARIES:
        fname = add(c["file"])
        items.append({"id": c["id"], "kind": c["kind"], "gate": True,
                      "atom": c["atom"],
                      "assertion_regexes": c["assertion_regexes"],
                      "files": [fname]})
    for d in DUPLICATES:
        fa, fb = add(d["file_a"]), add(d["file_b"])
        items.append({"id": d["id"], "kind": "duplicate", "gate": False,
                      "atom": d["atom"], "files": [fa, fb]})
    for d in DEAD:
        f_dead, f_new = add(d["dead"]), add(d["superseding"])
        items.append({"id": d["id"], "kind": "dead", "gate": False,
                      "atom": d["atom"], "files": [f_dead],
                      "superseded_by": f_new})

    index_lines = ["# Memory Index\n", "\n"]
    for fname in sorted(files):
        index_lines.append("- [{}]({}) - {}\n".format(
            fname[:-3], fname, descriptions[fname]))
    files["MEMORY.md"] = "".join(index_lines)

    manifest = {"version": 1, "retirement_regex": RETIREMENT_REGEX,
                "items": items}
    _assert_atom_hygiene(files, manifest)
    return files, manifest


def _assert_atom_hygiene(files: dict, manifest: dict) -> None:
    """Every atom appears only where the manifest says it does."""
    for it in manifest["items"]:
        allowed = set(it["files"])
        if "superseded_by" in it:
            allowed.add(it["superseded_by"])
        hits = {f for f, c in files.items() if it["atom"] in c}
        if hits != allowed:
            raise AssertionError(
                f"atom hygiene violated for {it['id']}: atom {it['atom']!r} "
                f"found in {sorted(hits)}, expected {sorted(allowed)}")


def write_store(store_dir: str, manifest_path: str) -> dict:
    files, manifest = build_store()
    os.makedirs(store_dir, exist_ok=True)
    for fname, content in files.items():
        with open(os.path.join(store_dir, fname), "w", encoding="utf-8") as f:
            f.write(content)
    os.makedirs(os.path.dirname(os.path.abspath(manifest_path)), exist_ok=True)
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    return manifest


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--store", required=True, help="directory to create the fixture store in")
    p.add_argument("--manifest", required=True,
                   help="path for the manifest answer key (must be outside --store)")
    args = p.parse_args(argv)
    store_abs = os.path.abspath(args.store)
    manifest_abs = os.path.abspath(args.manifest)
    if manifest_abs.startswith(store_abs + os.sep):
        p.error("--manifest must lie outside --store (the pass must not see the answer key)")
    manifest = write_store(args.store, args.manifest)
    n_files = len(build_store()[0])
    print(f"seeded {n_files} files into {args.store} "
          f"({len(manifest['items'])} planted items); manifest: {args.manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: all tests PASS. If `test_atom_hygiene` fails, an atom string leaked into filler or a description; fix the colliding text in `seed.py`, not the test.

- [ ] **Step 5: Commit**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas
git add framework/tools/consolidation_eval/__init__.py framework/tools/consolidation_eval/seed.py framework/tools/tests/test_consolidation_eval.py
git commit -m "claude-personas: canary-eval fixture generator seed.py (#88)"
```

---

### Task 2: check.py - verdict engine + CLI

**Files:**
- Create: `framework/tools/consolidation_eval/check.py`
- Modify: `framework/tools/tests/test_consolidation_eval.py` (append test classes)

**Interfaces:**
- Consumes: manifest dict schema from Task 1.
- Produces: `scan_store(store_dir: str) -> dict[str, str]`, `evaluate(manifest: dict, store_dir: str) -> dict`. Verdict schema:

```json
{
  "gate_pass": true,
  "canaries_survived": 9, "canaries_total": 9,
  "cleanup_done": 0, "cleanup_total": 6,
  "results": [
    {"id": "exc-1", "kind": "exception", "gate": true, "survived": true,
     "atom_files": ["feedback_merge_policy_audited_repo_exception.md"],
     "asserting_files": ["feedback_merge_policy_audited_repo_exception.md"]},
    {"id": "dup-1", "kind": "duplicate", "gate": false, "cleaned": false,
     "atom_files": ["...", "..."]}
  ]
}
```

- [ ] **Step 1: Write the failing tests**

Append to `framework/tools/tests/test_consolidation_eval.py` (and add `from consolidation_eval import check  # noqa: E402` next to the existing seed import):

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: FAIL with `ImportError: cannot import name 'check'`.

- [ ] **Step 3: Write check.py**

Create `framework/tools/consolidation_eval/check.py`:

```python
#!/usr/bin/env python3
"""check.py - canary-eval verdict engine (claude-personas#88).

Reads the seed-time manifest (answer key) plus a consolidated store and
reports, deterministically (substring + regex, no LLM anywhere):
  - kill-gate canary survival: the item's atom appears in some file whose
    content also matches every assertion regex (rephrase/merge passes,
    smoothing fails), and
  - cleanup score: duplicates reduced to one location; dead facts gone or
    mentioned only in retirement context.

Exit code 0 iff every gate canary survived (single-run gate semantics).
The cleanup score is reported but never gates.

Usage:
    python3 check.py --manifest PATH --store DIR [--json PATH]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys


def scan_store(store_dir: str) -> dict:
    """Return {relative_path: content} for every .md file (skips dot-dirs)."""
    out = {}
    for root, dirs, files in os.walk(store_dir):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for fn in files:
            if fn.endswith(".md"):
                path = os.path.join(root, fn)
                rel = os.path.relpath(path, store_dir)
                with open(path, encoding="utf-8") as f:
                    out[rel] = f.read()
    return out


def _files_with_atom(store: dict, atom: str) -> list:
    return sorted(rel for rel, content in store.items() if atom in content)


def _check_canary(item: dict, store: dict) -> dict:
    hits = _files_with_atom(store, item["atom"])
    asserting = [rel for rel in hits
                 if all(re.search(rx, store[rel])
                        for rx in item["assertion_regexes"])]
    return {"id": item["id"], "kind": item["kind"], "gate": True,
            "survived": bool(asserting),
            "atom_files": hits, "asserting_files": asserting}


def _check_duplicate(item: dict, store: dict) -> dict:
    hits = _files_with_atom(store, item["atom"])
    return {"id": item["id"], "kind": item["kind"], "gate": False,
            "cleaned": len(hits) == 1, "atom_files": hits}


def _check_dead(item: dict, store: dict, retirement_regex: str) -> dict:
    hits = _files_with_atom(store, item["atom"])
    cleaned = all(re.search(retirement_regex, store[rel]) for rel in hits)
    return {"id": item["id"], "kind": item["kind"], "gate": False,
            "cleaned": cleaned, "atom_files": hits}


def evaluate(manifest: dict, store_dir: str) -> dict:
    store = scan_store(store_dir)
    retirement_regex = manifest["retirement_regex"]
    results = []
    for item in manifest["items"]:
        if item["gate"]:
            results.append(_check_canary(item, store))
        elif item["kind"] == "duplicate":
            results.append(_check_duplicate(item, store))
        elif item["kind"] == "dead":
            results.append(_check_dead(item, store, retirement_regex))
        else:
            raise ValueError(f"unknown item kind: {item['kind']!r}")
    canaries = [r for r in results if r["gate"]]
    cleanup = [r for r in results if not r["gate"]]
    return {
        "gate_pass": all(r["survived"] for r in canaries),
        "canaries_survived": sum(1 for r in canaries if r["survived"]),
        "canaries_total": len(canaries),
        "cleanup_done": sum(1 for r in cleanup if r["cleaned"]),
        "cleanup_total": len(cleanup),
        "results": results,
    }


def format_verdict(verdict: dict) -> str:
    lines = []
    for r in verdict["results"]:
        if r["gate"]:
            mark = "OK  " if r["survived"] else "LOST"
            lines.append(f"  [{mark}] {r['id']} ({r['kind']}) "
                         f"atom in: {r['atom_files'] or '-'}")
        else:
            mark = "done" if r["cleaned"] else "todo"
            lines.append(f"  [{mark}] {r['id']} ({r['kind']}) "
                         f"atom in: {r['atom_files'] or '-'}")
    lines.append(f"survival: {verdict['canaries_survived']}"
                 f"/{verdict['canaries_total']}"
                 f"  cleanup: {verdict['cleanup_done']}"
                 f"/{verdict['cleanup_total']}")
    lines.append("gate: PASS" if verdict["gate_pass"] else "gate: FAIL")
    return "\n".join(lines)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", required=True)
    p.add_argument("--store", required=True)
    p.add_argument("--json", help="also write the full verdict to this path")
    args = p.parse_args(argv)
    with open(args.manifest, encoding="utf-8") as f:
        manifest = json.load(f)
    verdict = evaluate(manifest, args.store)
    print(format_verdict(verdict))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(verdict, f, indent=2)
            f.write("\n")
    return 0 if verdict["gate_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: all tests PASS (Task 1 classes included).

- [ ] **Step 5: Commit**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas
git add framework/tools/consolidation_eval/check.py framework/tools/tests/test_consolidation_eval.py
git commit -m "claude-personas: canary-eval verdict engine check.py (#88)"
```

---

### Task 3: fake_passes.py + the discrimination self-test

**Files:**
- Create: `framework/tools/consolidation_eval/fake_passes.py`
- Modify: `framework/tools/tests/test_consolidation_eval.py` (append the end-to-end class)

**Interfaces:**
- Consumes: `seed.write_store`, `check.evaluate`.
- Produces: `noop(store_dir: str) -> None`, `naive_summarize(store_dir: str) -> None`, CLI `python3 fake_passes.py --mode {noop,summarize} STORE`.

- [ ] **Step 1: Write the failing test**

Append to `framework/tools/tests/test_consolidation_eval.py` (add `from consolidation_eval import fake_passes  # noqa: E402` next to the other imports):

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: FAIL with `ImportError: cannot import name 'fake_passes'`.

- [ ] **Step 3: Write fake_passes.py**

Create `framework/tools/consolidation_eval/fake_passes.py`:

```python
#!/usr/bin/env python3
"""fake_passes.py - scripted consolidation passes for eval self-testing (#88).

Two deterministic, zero-token stand-ins for the real consolidation pass:
  - noop: changes nothing. Must score full canary survival and zero cleanup.
  - naive_summarize: the smoothing failure mode made flesh. Collapses every
    file group into one summary of description lines, discarding bodies
    (where the atoms live). Must fail canary survival.

If check.py cannot discriminate these two, the eval itself is broken.

Usage:
    python3 fake_passes.py --mode {noop,summarize} STORE_DIR
"""
from __future__ import annotations

import argparse
import os
import re
import sys

_FM_RE = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def _description(content: str) -> str:
    m = _FM_RE.match(content)
    if not m:
        return ""
    for line in m.group(1).splitlines():
        if line.startswith("description:"):
            return line.split(":", 1)[1].strip()
    return ""


def noop(store_dir: str) -> None:
    """The do-nothing pass."""


def naive_summarize(store_dir: str) -> None:
    """Collapse each <type>_ group into one summary file of description
    lines; delete the originals; rewrite the index."""
    groups: dict = {}
    for fn in sorted(os.listdir(store_dir)):
        if not fn.endswith(".md") or fn == "MEMORY.md":
            continue
        path = os.path.join(store_dir, fn)
        with open(path, encoding="utf-8") as f:
            content = f.read()
        prefix = fn.split("_", 1)[0]
        groups.setdefault(prefix, []).append(_description(content))
        os.remove(path)
    index_lines = ["# Memory Index\n", "\n"]
    for prefix in sorted(groups):
        out = f"{prefix}_consolidated_notes.md"
        body = "".join(f"- {d}\n" for d in groups[prefix])
        header = ("---\nname: {p}-consolidated-notes\n"
                  "description: Consolidated {p} notes\n"
                  "type: {p}\n---\n\n").format(p=prefix)
        with open(os.path.join(store_dir, out), "w", encoding="utf-8") as f:
            f.write(header + body)
        index_lines.append(
            f"- [{out[:-3]}]({out}) - Consolidated {prefix} notes\n")
    with open(os.path.join(store_dir, "MEMORY.md"), "w", encoding="utf-8") as f:
        f.write("".join(index_lines))


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=("noop", "summarize"), required=True)
    p.add_argument("store", help="store directory to run the fake pass on")
    args = p.parse_args(argv)
    if args.mode == "noop":
        noop(args.store)
    else:
        naive_summarize(args.store)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: all tests PASS. If `test_naive_summarizer_fails_survival` unexpectedly passes survival, an atom leaked into a `description:` line; fix the seed data (Task 1 guards this too).

- [ ] **Step 5: Commit**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas
git add framework/tools/consolidation_eval/fake_passes.py framework/tools/tests/test_consolidation_eval.py
git commit -m "claude-personas: canary-eval fake passes + discrimination self-test (#88)"
```

---

### Task 4: run_eval.py - the N-run gate driver

**Files:**
- Create: `framework/tools/consolidation_eval/run_eval.py`
- Modify: `framework/tools/tests/test_consolidation_eval.py` (append the driver class)

**Interfaces:**
- Consumes: `seed.write_store`, `check.evaluate`.
- Produces: `run(runs: int, pass_cmd: str, model: str | None, keep: bool, timeout: int) -> dict`. Results schema:

```json
{
  "runs": 2, "pass_cmd": "...", "model": null, "gate_pass": true,
  "per_run": [
    {"run": 1, "workdir": "...", "gate_pass": true,
     "canaries_survived": 9, "canaries_total": 9,
     "cleanup_done": 0, "cleanup_total": 6}
  ]
}
```

- [ ] **Step 1: Write the failing test**

Append to `framework/tools/tests/test_consolidation_eval.py` (add `from consolidation_eval import run_eval  # noqa: E402`):

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: FAIL with `ImportError: cannot import name 'run_eval'`.

- [ ] **Step 3: Write run_eval.py**

Create `framework/tools/consolidation_eval/run_eval.py`:

```python
#!/usr/bin/env python3
"""run_eval.py - N-run canary-eval driver, the canonical kill-gate mode (#88).

Each run: seed a fresh fixture store into a temp git repo, execute the
consolidation pass command inside it, then check canary survival on the
result. If the pass created a consolidate/* branch (the #89 contract), that
branch is checked out before checking; otherwise the working tree is checked.

Gate rule (spec): 100% canary survival in EVERY run. Cleanup is reported,
never gated on. The model, when given, is recorded verbatim in the results
so a silent provider update shows up as an eval change; pass --model
whenever --pass-cmd invokes an LLM.

The real gate run against the #89 consolidation skill looks like:
    python3 run_eval.py --runs 10 --model <pinned-model> \
        --pass-cmd 'claude -p "/consolidate-memory ." --model <pinned-model>'
(exact skill invocation lands with #89; any command that mutates the store
or leaves a consolidate/* branch works.)

Usage:
    python3 run_eval.py --runs N --pass-cmd CMD [--model NAME]
                        [--out results.json] [--keep] [--timeout SECONDS]
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

try:
    from . import check, seed
except ImportError:  # executed as a script, not a package
    import check
    import seed


def _git(store: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", store,
         "-c", "user.email=canary-eval@local", "-c", "user.name=canary-eval",
         *args],
        check=True, capture_output=True, text=True)


def _run_once(run_no: int, pass_cmd: str, keep: bool, timeout: int) -> dict:
    workdir = tempfile.mkdtemp(prefix=f"canary-eval-run{run_no}-")
    store = os.path.join(workdir, "store")
    manifest = seed.write_store(store, os.path.join(workdir, "manifest.json"))
    _git(store, "init", "-q")
    _git(store, "add", "-A")
    _git(store, "commit", "-q", "-m", "canary-eval: seeded fixture store")

    subprocess.run(pass_cmd, shell=True, cwd=store, timeout=timeout,
                   check=False)

    branches = _git(store, "branch", "--list", "consolidate/*",
                    "--format=%(refname:short)").stdout.split()
    if branches:
        _git(store, "checkout", "-q", branches[0])

    verdict = check.evaluate(manifest, store)
    result = {"run": run_no, "workdir": workdir if keep else None,
              "branch_checked": branches[0] if branches else None,
              "gate_pass": verdict["gate_pass"],
              "canaries_survived": verdict["canaries_survived"],
              "canaries_total": verdict["canaries_total"],
              "cleanup_done": verdict["cleanup_done"],
              "cleanup_total": verdict["cleanup_total"],
              "results": verdict["results"]}
    if not keep:
        shutil.rmtree(workdir, ignore_errors=True)
    return result


def run(runs: int, pass_cmd: str, model, keep: bool, timeout: int) -> dict:
    per_run = []
    for i in range(1, runs + 1):
        r = _run_once(i, pass_cmd, keep, timeout)
        print(f"run {i}/{runs}: gate={'PASS' if r['gate_pass'] else 'FAIL'} "
              f"survival={r['canaries_survived']}/{r['canaries_total']} "
              f"cleanup={r['cleanup_done']}/{r['cleanup_total']}")
        per_run.append(r)
    return {"runs": runs, "pass_cmd": pass_cmd, "model": model,
            "gate_pass": all(r["gate_pass"] for r in per_run),
            "per_run": per_run}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--runs", type=int, default=10)
    p.add_argument("--pass-cmd", required=True,
                   help="shell command executed with cwd=<fixture store>")
    p.add_argument("--model", default=None,
                   help="pinned model id, recorded in the results; give this "
                        "whenever --pass-cmd invokes an LLM")
    p.add_argument("--out", default=None,
                   help="write full results JSON to this path")
    p.add_argument("--keep", action="store_true",
                   help="keep per-run workdirs for inspection")
    p.add_argument("--timeout", type=int, default=1800,
                   help="per-run pass-cmd timeout in seconds")
    args = p.parse_args(argv)
    results = run(args.runs, args.pass_cmd, args.model, args.keep,
                  args.timeout)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2)
            f.write("\n")
    print("aggregate gate:",
          "PASS" if results["gate_pass"] else "FAIL",
          f"({args.runs} runs, model={args.model or 'n/a'})")
    return 0 if results["gate_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && python3 -m unittest discover -s framework/tools/tests -p test_consolidation_eval.py -v`
Expected: all tests PASS. Requires `git` on PATH (CI and dev machines have it).

- [ ] **Step 5: Commit**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas
git add framework/tools/consolidation_eval/run_eval.py framework/tools/tests/test_consolidation_eval.py
git commit -m "claude-personas: canary-eval N-run gate driver run_eval.py (#88)"
```

---

### Task 5: test wrapper for run_all.sh + full-suite verification

**Files:**
- Create: `framework/tools/tests/test_consolidation_eval.sh`

**Interfaces:**
- Consumes: the completed test suite from Tasks 1-4.
- Produces: run_all.sh coverage (it executes every `test_*.sh` in the dir).

- [ ] **Step 1: Write the wrapper (mirrors test_memory_cliff.sh)**

Create `framework/tools/tests/test_consolidation_eval.sh`:

```bash
#!/usr/bin/env bash
# Run the Python unit tests for the consolidation canary eval (#88).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 -m unittest discover -s "$SCRIPT_DIR" -p test_consolidation_eval.py -v
```

- [ ] **Step 2: Verify the wrapper and shellcheck pass**

Run: `bash framework/tools/tests/test_consolidation_eval.sh`
Expected: full suite PASS.

Run: `shellcheck --severity=warning framework/tools/tests/test_consolidation_eval.sh`
Expected: no output, exit 0 (the CI gate from PR #85 checks this).

- [ ] **Step 3: Run the whole repo test suite**

Run: `bash framework/tools/tests/run_all.sh`
Expected: every suite PASSES, including the pre-existing ones (nothing regressed).

- [ ] **Step 4: Commit and push**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas
git add framework/tools/tests/test_consolidation_eval.sh
git commit -m "claude-personas: canary-eval test wrapper for run_all.sh (#88)"
git push origin 88-consolidation-canary-eval
```

---

## After the plan: PR + gate run (not tasks in this plan)

- Open the PR for `88-consolidation-canary-eval` with `Closes #88` noting deliverable order: seed/check/fakes/driver land now; the real 10-run gate record on #88 waits for #89's skill.
- The AC1 checkbox "eval run results recorded on this issue" is satisfied only after that gate run; the issue stays open until then unless re-scoped.

## Deviations from the planned code

- Task 1 (earlier deviation): the manifest-placement guard moved from the CLI's `main()` into `seed.write_store()` itself, so any caller gets the protection, not just the CLI; negative tests were added for both the function and the CLI path.
- Review round 1 on Task 4 found the planned `run_eval.py` crashed the whole N-run driver on a pass-cmd timeout or a broken post-pass git checkout, and left the `consolidate/*` branch-checkout path completely untested.
- `run_eval.py` now wraps pass execution, branch discovery/checkout, and `check.evaluate` in a try/except, turning `TimeoutExpired`/`CalledProcessError` into a normal FAILED run carrying an `"error"` field instead of an uncaught exception.
- Workdir cleanup moved into a `finally` block so it runs on every path (unless `--keep`); two tests were added to `TestRunEvalDriver` covering the branch-checkout discrimination and the timeout-becomes-a-failed-run behavior.
- Final review found three more false-PASS vectors: the pass command's exit code was ignored, retirement prose could count as canary survival, and `--runs 0` was a vacuous pass; it also found the answer-key manifest and the eval's own bookkeeping were reachable from the pass's cwd.
- `run_eval.py` was hardened: a non-zero pass-cmd exit is now a FAILED run before `check.evaluate` even runs, the pass's stdout/stderr is captured and its tail recorded, the manifest now lives in its own separate tempdir, tempdir prefixes and the seeded commit message no longer identify the eval, and `--runs < 1` is rejected by argparse and by `run()` itself.
- `check.py`'s `_check_canary` now also rejects a retirement_regex match as survival, so a fact only asserted inside retirement prose (e.g. "...is archived and no longer used") does not count; `seed.py`'s stale-1 and stale-3 canaries gained a genuine second assertion regex so this rule has something to bite on.
- Every one of these fixes carries a new covering test in `TestRunEvalDriver`, `TestCheckCanary`, or `TestSeedBuildStore`.
