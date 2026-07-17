# Consolidation pass vs deterministic structural audit (issue #91, #87 AC4)

Side-by-side validation: run the consolidation (synthesis) pass and a deterministic structural audit over the same real memory store, and compare what each catches.
Expected answer per the issue: **no** - the synthesis pass does not subsume deterministic checks; in that case the docs must state the composes-with relationship explicitly.

Corpus: the cerebrum store (`cerebrum/.agents/memory/`, 103 top-level `.md` files at run date), owner-consented.

## Components

- `structural_audit.py` - the deterministic baseline. Reuses the framework's tested `consolidate_pass.index_sync_errors` (index/file divergence + orphans) and adds the corpus's only `[[name]]` wiki-link integrity check (nothing else in either repo validates those). Read-only, stdlib-only. Exit 0 clean / 1 findings / 2 unreadable.
- `classify_findings.py` - deterministic classification of raw findings into analysis classes (archive-indexed vs dated-artifact vs unindexed orphans; slug-style-mismatch vs extension-suffixed vs non-memory-reference vs dangling wikilinks). `--summary` prints aggregate counts only.
- `tests/` - stdlib unittest, run from this dir: `python3 -m unittest discover -s tests`
- `results/` - dated aggregate outputs per phase.

**Data minimization note:** the corpus is a private repo, and filenames are themselves sensitive metadata, so this public record carries **aggregate counts and finding classes only** (`classify_findings.py --summary`). The filename-level detail lives with the corpus owner (reproducible anytime by rerunning the tools against the store); the per-file findings and the pass's full report are recorded privately on the corpus repo's consolidation PR.

## Phase A result (2026-07-17): structural audit over the live cerebrum store

118 raw findings; classified:

| Class | n | Reading |
|---|---|---|
| index-ghost | 1 | FALSE POSITIVE of the reused framework check: the index header's inline-code example `` `- [Title](file.md) - hook` `` parses as a link to `file.md` - `index_sync_errors` strips no inline code. Framework finding, see below. |
| orphan/archive-indexed | 25 | Not rot: cerebrum indexes archived memories one-hop (MEMORY.md -> an archive-index file -> file). A flat index/file check cannot see the hop. |
| orphan/dated-artifact | 7 | Not rot: dated routine outputs (digest / meta-audit artifacts) are by convention never index entries. |
| orphan/unindexed | 0 | No genuine orphans - the store's index discipline is intact. |
| wikilink/slug-style-mismatch | 40 | Real drift, dominant class: kebab-case `[[some-fact-slug]]` links vs snake_case `some_fact_slug.md` files. Mechanical dash/underscore normalization resolves all 40. |
| wikilink/dangling | 35 | Mixed: genuinely stale targets + deliberate forward references (cerebrum convention allows a `[[name]]` that marks a memory worth writing later) - the one class needing per-item judgment. |
| wikilink/extension-suffixed | 4 | Real drift: `[[some_fact_slug.md]]` style, `.md` does not belong in a slug link. |
| wikilink/non-memory-reference | 6 | Not rot: `[[superpowers:brainstorming]]`, `[[AskUserQuestion]]` etc. name skills/harness primitives, not memory files. |

### Framework finding (from Phase A, to file on claude-personas)

`consolidate_pass.index_sync_errors` does not strip inline code or fenced blocks before matching `](x.md)` links, so cerebrum's index HEADER example line is a false-positive "ghost". Consequence beyond cosmetics: `cmd_finish` refuses to deliver when `index_sync_errors` is nonempty, so on any store whose index documents its own convention with an inline example, the consolidation pass is structurally blocked at finish unless the pass rewords the header. To verify empirically in Phase B.

## Phase B result (2026-07-17): consolidation pass over the same store

Headless `claude-sonnet-5` run of the `consolidate-memory` skill (spec Data-flow invocation), wrapper from the #95 fix branch.

- **Run 1 (pre-fix wrapper): `begin` crashed** - the store path `.agents/memory` produced a git-ref-invalid branch component. Framework bug #95, fixed via PR #96, verified live by run 2. The eval (#88) never caught it: fixture stores use non-dotted paths.
- **Run 2: the pass worked as designed and proposed 2 operations**, delivered as a PR on the corpus repo (private) with typed one-op-per-commit history:
  - 1 `retire` - a stale post-cutoff capability claim, explicitly contradicted by a newer reference memory in the same store, cited in the commit message per contract.
  - 1 `redistribute` - a two-facts-one-file split (distinct triggers and mitigations), with index line + two-way cross-links.
- **The `finish` gate refused delivery, as phase A predicted**: ~31 pre-existing `index_sync_errors` findings, none caused by the pass - the inline-code header ghost (1) plus the archive-indexed (25) and dated-artifact (7) files the flat check reads as orphans. Framework bug #97. The pass agent correctly refused to mass-index 30 files to appease the gate and stopped; delivery was completed manually (operator `git push` + PR).

## Phase C: comparison + composition claim

Findings by which method caught them:

| | Caught by lint only | Caught by synthesis only | Caught by both |
|---|---|---|---|
| Count | **85** (40 slug-style + 35 dangling + 4 extension-suffixed + 6 non-memory refs to triage, all mechanically located) | **2** (1 stale-contradicted fact, 1 two-facts-one-file split) | **0** |

Zero overlap, in both directions, on a real 103-file corpus:

- The pass **cannot** catch the lint classes even in principle: its operation contract is dedupe/redistribute/retire - link normalization and index/file divergence are not operations it is allowed to propose, and its own gate *consumes* deterministic lint rather than reproducing it.
- The lint **cannot** catch the synthesis classes even in principle: "this fact is contradicted by that newer fact" and "this file holds two facts" are semantic judgments with no deterministic signature.
- Interaction finding: the deterministic gate *inside* the pass (finish's index-sync check) currently conflicts with legitimate layered-index conventions (#97) - composition is not just complementary but has a real integration surface that needs design.

**Evidenced claim: the consolidation pass COMPOSES WITH deterministic structural lint; it does not replace it (and vice versa).** The expected answer from the issue is confirmed. Docs updated in CONVENTIONS.md alongside this experiment.
