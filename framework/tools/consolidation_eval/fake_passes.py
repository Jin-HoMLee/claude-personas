#!/usr/bin/env python3
"""fake_passes.py - scripted consolidation passes for eval self-testing (#88).

Deterministic, zero-token stand-ins for the real consolidation pass:
  - noop: changes nothing. Must score full canary survival and zero cleanup.
  - naive_summarize: the smoothing failure mode made flesh. Collapses every
    file group into one summary of description lines, discarding bodies
    (where the atoms live). Must fail canary survival.
  - fix_cross_tier: the #102 boundary violation made flesh. "Dedupes"
    through the store's `shared` symlink by rewriting adjacent-tier copies.
    Must fail the cross_tier gate item.

If check.py cannot discriminate these, the eval itself is broken.

Usage:
    python3 fake_passes.py --mode {noop,summarize,fix_cross_tier} STORE_DIR
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


def fix_cross_tier(store_dir: str) -> None:
    """The cross-tier 'fixer' the contract forbids: walks the store's
    `shared` symlink and rewrites every adjacent fact file to defer to the
    store's copy - a plausible-looking dedupe that mutates a tier the pass
    does not own. The eval must catch this via the adjacent hash check."""
    shared = os.path.join(store_dir, "shared")
    if not os.path.isdir(shared):
        return
    for fn in sorted(os.listdir(shared)):
        if fn.endswith(".md") and fn != "MEMORY.md":
            with open(os.path.join(shared, fn), "a", encoding="utf-8") as f:
                f.write("\n(Deduplicated: the canonical copy now lives "
                        "in the project store.)\n")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=("noop", "summarize", "fix_cross_tier"),
                   required=True)
    p.add_argument("store", help="store directory to run the fake pass on")
    args = p.parse_args(argv)
    if args.mode == "noop":
        noop(args.store)
    elif args.mode == "summarize":
        naive_summarize(args.store)
    else:
        fix_cross_tier(args.store)
    return 0


if __name__ == "__main__":
    sys.exit(main())
