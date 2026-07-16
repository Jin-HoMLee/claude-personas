# Consolidation canary eval (kill gate) - design

**Date:** 2026-07-15
**Status:** Approved design, pre-implementation
**Tracking:** [claude-personas#88](https://github.com/Jin-HoMLee/claude-personas/issues/88), sub-issue (AC1) of [#87](https://github.com/Jin-HoMLee/claude-personas/issues/87)

Naming note: this spec is about the *forgetting/dedupe consolidation pass* of #87.
It is unrelated to the 2026-07-02 "knowledge consolidation" spec, which is the cross-tier knowledge *migration* project (epic #27).

## Problem

#87 introduces a consolidation pass: an agent reads one memory store and proposes a tidied reorganization on a branch.
LLM-driven consolidation is documented to be non-monotonic in utility and prone to "information over-smoothing": rare-but-valid facts get majority-voted away during summarization (RGMem, arXiv 2510.16392; arXiv 2605.12978).
A consolidator that destroys outlier facts is worse than manual curation.

AC1 of #87 is therefore a kill gate, and the eval must exist before the feature:
seed known outlier facts into a test store, run the pass, require 100% survival.
If the pass cannot reliably preserve seeded outliers, #87 does not ship.

No existing benchmark tests valid-outlier survival across a consolidation pass (verified 2026-07-15; the nearest prior art, Memora's FAMA metric, penalizes *retaining obsolete* facts - the inverse direction).
The structure below follows the field where the field has converged: deterministic checks in the gate path (layered-eval consensus), repetition + statistics for nondeterminism, and both retention and update directions tested (LongMemEval tests knowledge updates and abstention alongside retention; the needle-in-a-haystack family is the precedent for planting distinctive facts, with U-NIAH's "semantic masking" finding telling us the outvoted-exception canary is the hardest case).

## What gets built

Three pieces under `framework/tools/consolidation_eval/`, stdlib-only Python in the style of `memory_cliff.py`:

1. **`seed.py`** - generates a fixture memory store: a valid substrate instance (`MEMORY.md` index + one-fact-per-file with frontmatter) with canaries and cleanup targets planted at known positions.
   Writes a `manifest.json` recording every planted item and its check patterns.
2. **`check.py`** - reads `manifest.json` plus a consolidated store (the pass's result branch) and emits the verdict: per-canary survival, per-target cleanup, and the aggregate gate result.
3. **A `--run N` driver** - the canonical gate mode: seeds a fresh fixture repo, invokes the consolidation pass headlessly (`claude -p` with the consolidation skill), checks each run, and aggregates.
   The model version is pinned per run and recorded in the results, so a silent provider update shows up as an eval change.
   Manual seed + check remains available for developing and debugging the pass.

## The fixture store

Fully synthetic, generated from templates themed on the public `examples/` content.
Nothing from cerebrum, splice, or user memory ever enters the fixture: this repo is public, and private data must never become a test fixture.
Size: realistic, roughly 40 memory files, so the pass has genuine tidy-up work to do and canaries sit among plausible neighbors.

## Canary taxonomy

Per fixture, nine kill-gate canaries (three of each type):

1. **Outvoted exception** - several notes say "always do X"; the canary says "except in situation S, do Y".
   The semantically-masked needle; the case smoothing kills first.
2. **Rare-but-critical fact** - referenced by nothing else, on a topic nothing else covers, load-bearing content (e.g. a key format).
3. **Stale-looking survivor** - carries an old date but is still true and still needed; kills any retire-by-age heuristic.

Plus six cleanup targets (three of each kind), so a do-nothing pass cannot game the eval:

4. **Genuine duplicate pair** - two notes stating the same fact; the pass should merge them.
5. **Genuinely dead fact** - contradicted by a newer note in the fixture; the pass should retire it.

Every planted item carries a distinctive factual atom - a specific number, format string, or name that appears nowhere else in the fixture.

## The check (deterministic, no LLM judge in the gate path)

Survival is semantic, not verbatim: a rephrase or a legitimate merge that preserves the fact passes; smoothing that loses the fact fails.
The scriptable proxy is two levels per canary, both recorded in `manifest.json` at seed time:

1. **Atom present** - the canary's distinctive atom appears somewhere in the consolidated store.
2. **Assertion intact** - the file containing the atom still asserts the fact, checked by a small set of manifest-recorded regexes.
   Example: "except in S do Y" surviving only as "always do X (see also S)" fails level 2 even though the atom "S" is present.

Cleanup targets are checked the same way in reverse: a duplicate pair must be reduced to one location; a dead fact's atom must be gone or moved to an explicit retirement note.

## Verdict and gate rule

- **Kill gate:** N=10 automated runs; 100% of the 9 canaries survive in all 10 runs.
  Anything less fails the gate and #87 stops.
- **Cleanup score:** x/6 reported per run, but not part of the gate verdict.
  It answers "did the pass actually do its job" and prevents a no-op pass from reading as success; mixing it into the gate would muddy what "fail" means.

## The eval proves itself first

The eval ships with two scripted fake passes and a pytest self-test in `framework/tools/tests/` (zero tokens, runs in CI):

- A **no-op pass** must score survival 9/9 and cleanup 0/6.
- A **naive-summarizer pass** (rewrites everything into merged summaries) must fail survival.

If `check.py` cannot discriminate these two, the eval itself is wrong and must not be used to gate #87.

## Deliverable order

1. `seed.py` + `check.py` + fake passes + self-test (this issue's PR; no dependency on #89).
2. The `--run N` driver lands in the same PR but the real gate run needs #89's consolidation skill to exist.
3. Gate verdict (10 runs, pinned model) recorded on #88; that record is the kill-gate decision for #87.

## Not in scope

- The consolidation pass itself (mechanics + contract docs: #89).
- `memory_cliff.py` threshold prompts (#90) and the side-by-side structural-audit comparison (#91).
- Any LLM-as-judge scoring; if a future canary type genuinely cannot be checked deterministically, that is a design change to bring back here, not a silent addition.

## Decision log

| Decision | Alternatives rejected | Why |
|---|---|---|
| Deterministic seed + check core; automated `--run N` as canonical gate mode | Fully manual protocol; automation-only harness | Layered-eval consensus puts deterministic checks in the gate path; community default is push-button repetition, manual runs kept for debugging only (web-checked 2026-07-15) |
| Gate = survival only, N=10 runs at 100% | Single run; blended survival+cleanup score | Nondeterminism needs repetition to mean anything; a kill gate must have one unambiguous failure meaning |
| Plant cleanup targets alongside canaries | Survival-only fixture | A no-op pass would trivially pass a survival-only eval; LongMemEval tests update/abstention alongside retention |
| Atom + assertion-regex survival proxy | Verbatim string match; LLM-judge semantic match | Verbatim fails legitimate rephrase/merge; a judge in the gate path imports the same failure mode the eval is policing |
| Fully synthetic fixture from public-examples themes | Copy of a real corpus (cerebrum/splice) | Public repo; private data must never become a test fixture (2026-07-11 near-miss rule) |
| Fake-pass self-test ships with the eval | Trust the eval by review | An eval that cannot discriminate no-op from naive-summarizer proves nothing; review-by-running rule |

## References

- [#87](https://github.com/Jin-HoMLee/claude-personas/issues/87) design + field evidence (Dreams contract, Letta, DiffMem, LangChain trigger-policy split).
- Smoothing risk: [RGMem](https://arxiv.org/pdf/2510.16392) (information over-smoothing), [arXiv 2605.12978](https://arxiv.org/pdf/2605.12978) (non-monotonic utility).
- Structure precedents: [LongMemEval](https://arxiv.org/abs/2410.10813), [U-NIAH semantic masking](https://arxiv.org/html/2503.00353v1), [needle-in-a-haystack](https://opencompass.readthedocs.io/en/latest/advanced_guides/needleinahaystack_eval.html).
- Inverse-direction prior art: [Memora FAMA](https://arxiv.org/html/2604.20006v1).
- Deterministic-first / CI layering: [DeepEval](https://deepeval.com/blog/llm-as-a-judge), [Future AGI](https://futureagi.com/blog/deterministic-llm-evaluation-metrics-2026/), [Latitude](https://latitude.so/blog/ultimate-ci-cd-llm-evaluation-guide), [Arize](https://arize.com/blog/how-to-add-llm-evaluations-to-ci-cd-pipelines/).
