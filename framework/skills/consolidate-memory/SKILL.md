---
name: consolidate-memory
description: Explicit-only consolidation pass over ONE memory store - proposes dedupe/redistribute/retire operations on a consolidate/* branch via consolidate_pass.py, delivered as a PR to the human/MM merge gate. Never auto-run; never mutates main.
---

# Consolidate Memory

## Purpose

Propose a tidied reorganization of one memory store as a reviewable branch/PR.
You are the semantic half of a two-part design: all git writes go through `consolidate_pass.py` (the deterministic half), which enforces branch isolation, store scope, and typed commits.
This skill is self-contained: follow it identically whether it was invoked as a skill or injected as a system prompt.

## Hard rules

- Explicit invocation only: never start a pass on your own initiative.
- One store per pass: the store is the directory you were pointed at; it must contain a `MEMORY.md`.
  If it does not, refuse and report - never guess a different directory.
- Never run `git commit`, `git push`, `git checkout`, or `gh pr create` yourself: the wrapper is the only write path.
- Never demote content out of its tier or move content to another store: you clean WITHIN the store only.

## The preservation stance (anti-smoothing)

LLM consolidation is documented to smooth away rare-but-valid facts.
These rules are the countermeasure; they outrank tidiness:

- An exception NEVER merges into the rule it excepts.
  "Always X" + "except in S, do Y" stay distinct facts (merging them into one file is allowed only if both assertions survive verbatim in meaning).
- A fact referenced by nothing else is not therefore disposable.
- An old date is not staleness.
  Retire a fact ONLY when a newer fact in this store contradicts it, and cite that newer fact in the commit message.
- When in doubt, keep.
  A missed cleanup costs a little; a destroyed fact costs the store its trustworthiness.

## Operations

Exactly three operation types, one logical operation per commit:

- `dedupe`: two files assert the same fact -> merge into one, delete the other, update the index line(s).
- `redistribute`: one file has grown to cover several facts -> split it, add index lines for the new files.
- `retire`: a fact is contradicted by a newer fact in this store -> delete the file (or fold a one-line retirement note into the newer file), remove its index line, cite the contradicting fact in the commit message.

Every operation updates `MEMORY.md` in the same commit: after every operation, every store file has exactly one index line and every index line points at an existing file.

## Procedure

1. `python3 <tools-dir>/consolidate_pass.py begin --store <store>` (resolve `<tools-dir>`: `.agents/tools/` in an installed instance, `framework/tools/` in the framework repo).
   If begin fails, report its message and stop - do not work around it.
2. Read the ENTIRE store: `MEMORY.md` plus every linked file. Build the full operation list BEFORE editing anything, applying the preservation stance.
3. Per operation: edit the files (all pieces of the logical op together, including the index update), then
   `python3 <tools-dir>/consolidate_pass.py commit --op <dedupe|redistribute|retire> -m "<what merged/split/retired and why>"`.
   If commit rejects out-of-store paths, revert the stray edit and retry the operation.
4. `python3 <tools-dir>/consolidate_pass.py finish`.
   Report its output verbatim (PR URL, branch name, or "nothing to consolidate").
   If finish fails with a "branch intact - deliver manually" message (gh missing, push failed, or `gh pr create` failed), do NOT abort: these are deliberately retryable, and the wrapper has kept the pass branch and its commits intact.
   Report the wrapper's manual-delivery instructions verbatim to the human and stop.
5. `abort` is for abandoning the pass itself, not for a retryable finish failure: use it only for a `begin`/`commit` failure you cannot resolve, or a pass you conclude should not be delivered.
   Run `python3 <tools-dir>/consolidate_pass.py abort` and report what failed.

## What a good pass looks like

A handful of well-argued operations, each auditable from its commit message alone, with zero canary-type facts (exceptions, rare-but-critical, old-but-true) touched.
An empty pass on a clean store is a correct outcome, not a failure.
