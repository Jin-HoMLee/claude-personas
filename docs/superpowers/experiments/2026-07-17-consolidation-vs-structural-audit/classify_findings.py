#!/usr/bin/env python3
"""classify_findings.py - deterministic classification of structural_audit
raw findings into experiment analysis classes, for the #91 findings table.

Orphan classes ("file not in index"):
  archive-indexed - linked from project_archive_index.md, cerebrum's one-hop
                    archive pattern: MEMORY.md -> archive index -> file. The
                    flat index check can't see the hop; not memory rot.
  dated-artifact  - digest_* / cerebrum_meta_audit_* routine outputs, which
                    by convention were never index entries.
  unindexed       - a real orphan under the store's own conventions.

Wikilink classes ("broken wikilink"):
  non-memory-reference - names a skill/tool/primitive, not a memory file
                         (contains ':' or whitespace or an uppercase letter,
                         or is in the curated KNOWN_NON_MEMORY set).
  slug-style-mismatch  - resolves once dashes/underscores are normalized
                         (kebab-case link vs snake_case filename drift).
  extension-suffixed   - resolves once a trailing .md is stripped.
  dangling             - resolves under no rule; either genuinely stale or a
                         deliberate forward reference (cerebrum convention:
                         a [[name]] may mark a memory worth writing later).

Usage: python3 classify_findings.py --store PATH
"""
from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from structural_audit import audit  # noqa: E402

ARCHIVE_INDEX = "project_archive_index.md"
DATED_ARTIFACT_RE = re.compile(r"^(digest_|cerebrum_meta_audit_)")
ARCHIVE_LINK_RE = re.compile(r"\]\(([^)]+\.md)\)")
# Known non-memory names referenced with [[...]] from memory files: skills and
# harness primitives (curated; extend as the corpus does).
KNOWN_NON_MEMORY = {"spin-off-project", "cerebrum-memory-check", "memory-check",
                    "load-persona-memory", "deep-research"}


def _files(store: str) -> set[str]:
    return {f for f in os.listdir(store) if f.endswith(".md")}


def classify_orphan(store: str, fname: str) -> str:
    archive = os.path.join(store, ARCHIVE_INDEX)
    if os.path.isfile(archive):
        with open(archive, encoding="utf-8") as f:
            if fname in set(ARCHIVE_LINK_RE.findall(f.read())):
                return "archive-indexed"
    if DATED_ARTIFACT_RE.match(fname):
        return "dated-artifact"
    return "unindexed"


def classify_wikilink(store: str, target: str) -> str:
    if (":" in target or any(c.isspace() for c in target)
            or any(c.isupper() for c in target) or target in KNOWN_NON_MEMORY):
        return "non-memory-reference"
    on_disk = _files(store)
    normalized = target.replace("-", "_")
    if f"{normalized}.md" in on_disk or f"{target.replace('_', '-')}.md" in on_disk:
        return "slug-style-mismatch"
    if target.endswith(".md") and (
            target in on_disk or target.replace("-", "_") in on_disk):
        return "extension-suffixed"
    return "dangling"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Classify structural_audit findings for the #91 table.")
    parser.add_argument("--store", required=True)
    parser.add_argument(
        "--summary", action="store_true",
        help="aggregate class counts only - no filenames or link targets, "
             "publishable from a private store (data minimization)")
    args = parser.parse_args(argv)
    findings = audit(args.store)
    classes: dict[str, list[str]] = {}
    for finding in findings:
        if finding.startswith("file not in index: "):
            cls = "orphan/" + classify_orphan(
                args.store, finding.split(": ", 1)[1])
        elif finding.startswith("broken wikilink: "):
            target = finding.rsplit("[[", 1)[1].rstrip("]")
            cls = "wikilink/" + classify_wikilink(args.store, target)
        else:
            cls = "index-ghost"
        classes.setdefault(cls, []).append(finding)
    if not args.summary:
        for cls in sorted(classes):
            print(f"== {cls} ({len(classes[cls])}) ==")
            for finding in classes[cls]:
                print(f"  {finding}")
    total = sum(len(v) for v in classes.values())
    print(f"\n{total} finding(s): " + ", ".join(
        f"{cls}={len(classes[cls])}" for cls in sorted(classes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
