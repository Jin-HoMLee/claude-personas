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
