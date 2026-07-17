#!/usr/bin/env python3
"""structural_audit.py - deterministic structural audit of one memory store,
the baseline half of the #91 side-by-side experiment (consolidation pass vs
deterministic audit over the same corpus).

Checks, all read-only and stdlib-only:
  1. index/file divergence + orphans - REUSED from the framework's
     consolidate_pass.index_sync_errors (same-directory links only, so
     cross-store refs like shared/MEMORY.md are legitimately skipped).
  2. [[name]] wiki-link integrity - new here; nothing else in either repo
     validates these. A target resolves if <target>.md exists top-level in
     the store OR some store file's frontmatter `name:` equals it. Matches
     inside fenced code blocks or inline backtick spans are ignored (memory
     files about the convention mention [[name]] in prose).

Scope limitation, shared with index_sync_errors: top-level *.md only -
subdirectories (drafts/, etc.) are outside the audited store surface.

Usage: python3 structural_audit.py --store PATH   # dir containing MEMORY.md
Exit: 0 clean, 1 findings, 2 unreadable store.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

# Reuse the framework's tested index<->file sync check rather than
# re-implementing it; the experiment dir sits 4 levels below the repo root
# (docs/superpowers/experiments/<name>/).
_EXPERIMENT_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(_EXPERIMENT_DIR))))
sys.path.insert(0, os.path.join(_REPO_ROOT, "framework", "tools"))
from consolidate_pass import index_sync_errors  # noqa: E402

WIKILINK_RE = re.compile(r"\[\[([^\[\]]+)\]\]")
FENCE_RE = re.compile(r"^(```|~~~).*?^\1", re.DOTALL | re.MULTILINE)
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
FRONTMATTER_NAME_RE = re.compile(r"^\s*name:\s*[\"']?([^\"'\n]+?)[\"']?\s*$",
                                 re.MULTILINE)


def _strip_code(text: str) -> str:
    """Drop fenced blocks and inline code spans so a [[name]] shown as an
    example is not treated as a live link."""
    return INLINE_CODE_RE.sub("", FENCE_RE.sub("", text))


def _frontmatter_name(text: str) -> str | None:
    """The `name:` slug from a leading YAML frontmatter block, or None."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    m = FRONTMATTER_NAME_RE.search(text[3:end])
    return m.group(1).strip() if m else None


def wikilink_errors(storedir: str) -> list[str]:
    """One finding per unresolvable [[target]] across the store's top-level
    *.md files (MEMORY.md included - links appear there too)."""
    files = sorted(f for f in os.listdir(storedir) if f.endswith(".md"))
    texts = {}
    for fname in files:
        with open(os.path.join(storedir, fname), encoding="utf-8-sig") as f:
            texts[fname] = f.read()
    resolvable = {f[:-3] for f in files}
    resolvable |= {n for n in (_frontmatter_name(t) for t in texts.values()) if n}
    errors = []
    for fname in files:
        for target in WIKILINK_RE.findall(_strip_code(texts[fname])):
            if target.strip() not in resolvable:
                errors.append(f"broken wikilink: {fname} -> [[{target.strip()}]]")
    return errors


def audit(storedir: str) -> list[str]:
    """All findings for one store, index-sync first then wikilinks."""
    root, store = os.path.split(os.path.abspath(storedir))
    return index_sync_errors(root, store) + wikilink_errors(storedir)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Deterministic structural audit of one memory store.")
    parser.add_argument("--store", required=True,
                        help="store directory (must contain MEMORY.md)")
    args = parser.parse_args(argv)
    try:
        findings = audit(args.store)
    except OSError as exc:
        print(f"structural_audit: error reading store: {exc}", file=sys.stderr)
        return 2
    for finding in findings:
        print(finding)
    print(f"\n{len(findings)} finding(s) in {args.store}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
