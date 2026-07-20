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
import hashlib
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
        "assertion_regexes": ["healthz-legacy", r"(?i)health.?check"],
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
        "assertion_regexes": ["corp-legacy.example", r"(?i)printer|dns zone"],
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
                     "We size the pool below the DB's 50-connection license limit: pool_max=47 leaves headroom for two admin sessions and the monitor.\n",
                     type_="reference"),
    },
    {
        "id": "dup-2", "atom": "artifact-cache.example.net",
        "file_a": _f("artifact-mirror-host",
                     "The artifact mirror hostname",
                     "Build artifacts are mirrored at artifact-cache.example.net.\n",
                     type_="reference"),
        "file_b": _f("artifact-mirror-usage",
                     "Use the artifact mirror for CI downloads",
                     "CI downloads dependencies from artifact-cache.example.net instead of the upstream registry.\n",
                     type_="reference"),
    },
    {
        "id": "dup-3", "atom": "ttl=900",
        "file_a": _f("dns-ttl-services",
                     "Service DNS records use a 15-minute TTL",
                     "Service DNS records are created with ttl=900.\n",
                     type_="reference"),
        "file_b": _f("dns-ttl-rationale",
                     "The DNS TTL balances failover speed against query load",
                     "We keep ttl=900 on service records: short enough for failover, long enough to keep resolver load sane.\n",
                     type_="reference"),
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


# --------------------------------------------------------------------------- #
# Cross-tier near-duplicate (#102): the same fact stated once in the store
# and once in the adjacent tier that the store's `shared` symlink points at.
# A contract-obedient pass FLAGS this pair and touches neither copy - so it
# seeds as a gate item whose survival means both copies stayed intact.
# --------------------------------------------------------------------------- #
CROSS_TIER = {
    "id": "xtier-1", "atom": "CW-2210",
    "assertion_regexes": ["CW-2210", r"(?i)freeze|change window"],
    "store_file": _f("deploy-freeze-window",
                     "Deploys freeze during the weekly change window",
                     "Deploys freeze during change window CW-2210 "
                     "(Fri 16:00 - Mon 08:00 UTC).\n"),
    "adjacent_file": _f("no-deploys-change-window",
                        "Never deploy inside the change window",
                        "Never deploy inside change window CW-2210; "
                        "the Fri-to-Mon freeze is absolute.\n"),
}

# Innocent adjacent-tier content, so the adjacent store is not a single-file
# giveaway that its one fact is the planted pair.
ADJACENT_FILLER = [
    _f("meeting-notes-live-in-wiki",
       "Meeting notes belong in the wiki, not the repo",
       "Keep meeting notes in the wiki; the repo holds decisions, not minutes.\n"),
    _f("prefer-text-diagram-sources",
       "Diagrams are checked in as plain-text sources",
       "Check in diagram sources (mermaid/dot), never only binary exports.\n"),
]


def _filename(entry: dict) -> str:
    return "{}_{}.md".format(entry["type"], entry["name"].replace("-", "_"))


def _render(entry: dict) -> str:
    return FRONTMATTER.format(name=entry["name"], description=entry["description"],
                              type=entry["type"]) + entry["body"]


def _build_dir(entries: list[dict], files: dict, descriptions: dict) -> None:
    for entry in entries:
        fname = _filename(entry)
        if fname in files:
            raise ValueError(f"duplicate fixture filename: {fname}")
        files[fname] = _render(entry)
        descriptions[fname] = entry["description"]


def _index_for(files: dict, descriptions: dict) -> str:
    lines = ["# Memory Index\n", "\n"]
    for fname in sorted(files):
        lines.append("- [{}]({}) - {}\n".format(
            fname[:-3], fname, descriptions[fname]))
    return "".join(lines)


def build_fixture(adjacent: bool = False) -> tuple[dict, dict, dict]:
    """Return (store_files, adjacent_files, manifest). With adjacent=False
    the classic single-store fixture is reproduced exactly (adjacent_files
    empty, no cross_tier manifest items)."""
    files: dict[str, str] = {}
    descriptions: dict[str, str] = {}

    def add(entry: dict) -> str:
        _build_dir([entry], files, descriptions)
        return _filename(entry)

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

    adj_files: dict[str, str] = {}
    if adjacent:
        adj_descriptions: dict[str, str] = {}
        store_copy = add(CROSS_TIER["store_file"])
        _build_dir([CROSS_TIER["adjacent_file"], *ADJACENT_FILLER],
                   adj_files, adj_descriptions)
        adj_copy = _filename(CROSS_TIER["adjacent_file"])
        adj_files["MEMORY.md"] = _index_for(adj_files, adj_descriptions)
        items.append({
            "id": CROSS_TIER["id"], "kind": "cross_tier", "gate": True,
            "atom": CROSS_TIER["atom"],
            "assertion_regexes": CROSS_TIER["assertion_regexes"],
            "files": [store_copy], "adjacent_file": adj_copy,
            "adjacent_sha256": hashlib.sha256(
                adj_files[adj_copy].encode("utf-8")).hexdigest()})

    files["MEMORY.md"] = _index_for(files, descriptions)

    manifest = {"version": 1, "retirement_regex": RETIREMENT_REGEX,
                "items": items}
    _assert_atom_hygiene(files, manifest, adj_files)
    return files, adj_files, manifest


def build_store() -> tuple[dict, dict]:
    """Classic entry point: the single-store fixture, no adjacent tier."""
    files, _, manifest = build_fixture(adjacent=False)
    return files, manifest


def _assert_atom_hygiene(files: dict, manifest: dict,
                         adjacent_files: dict | None = None) -> None:
    """Every atom appears only where the manifest says it does - across the
    store AND the adjacent tier (adjacent keys are namespaced so a shared
    filename can never mask a leak)."""
    merged = dict(files)
    for fname, content in (adjacent_files or {}).items():
        merged[f"adjacent:{fname}"] = content
    for it in manifest["items"]:
        allowed = set(it["files"])
        if "superseded_by" in it:
            allowed.add(it["superseded_by"])
        if "adjacent_file" in it:
            allowed.add(f"adjacent:{it['adjacent_file']}")
        hits = {f for f, c in merged.items() if it["atom"] in c}
        if hits != allowed:
            raise AssertionError(
                f"atom hygiene violated for {it['id']}: atom {it['atom']!r} "
                f"found in {sorted(hits)}, expected {sorted(allowed)}")


def write_store(store_dir: str, manifest_path: str,
                adjacent_dir: str | None = None) -> dict:
    store_abs = os.path.abspath(store_dir)
    manifest_abs = os.path.abspath(manifest_path)
    if manifest_abs.startswith(store_abs + os.sep):
        raise ValueError("manifest_path must lie outside store_dir (the pass must not see the answer key)")
    if adjacent_dir is not None:
        adjacent_abs = os.path.abspath(adjacent_dir)
        if adjacent_abs == store_abs or adjacent_abs.startswith(store_abs + os.sep):
            raise ValueError("adjacent_dir must lie outside store_dir "
                             "(it models a different tier, not a subdir)")
    files, adj_files, manifest = build_fixture(adjacent=adjacent_dir is not None)
    os.makedirs(store_dir, exist_ok=True)
    for fname, content in files.items():
        with open(os.path.join(store_dir, fname), "w", encoding="utf-8") as f:
            f.write(content)
    if adjacent_dir is not None:
        os.makedirs(adjacent_dir, exist_ok=True)
        for fname, content in adj_files.items():
            with open(os.path.join(adjacent_dir, fname), "w", encoding="utf-8") as f:
                f.write(content)
        # The store reaches its adjacent tier the way real role stores do:
        # a `shared` symlink (role-dir convention), relative so the fixture
        # survives being moved as a pair.
        link = os.path.join(store_dir, "shared")
        if not os.path.lexists(link):
            os.symlink(os.path.relpath(adjacent_abs, store_abs), link)
    os.makedirs(os.path.dirname(manifest_abs), exist_ok=True)
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    return manifest


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--store", required=True, help="directory to create the fixture store in")
    p.add_argument("--manifest", required=True,
                   help="path for the manifest answer key (must be outside --store)")
    p.add_argument("--adjacent", default=None,
                   help="also seed an adjacent-tier store here, linked from "
                        "the store as `shared` (adds the cross-tier pair)")
    args = p.parse_args(argv)
    try:
        manifest = write_store(args.store, args.manifest, adjacent_dir=args.adjacent)
    except ValueError as e:
        p.error(str(e))
    files, adj_files, _ = build_fixture(adjacent=args.adjacent is not None)
    print(f"seeded {len(files)} store + {len(adj_files)} adjacent files into "
          f"{args.store} ({len(manifest['items'])} planted items); "
          f"manifest: {args.manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
