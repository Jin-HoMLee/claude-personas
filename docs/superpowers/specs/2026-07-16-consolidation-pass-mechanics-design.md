# Consolidation pass mechanics + contract docs - design

**Date:** 2026-07-16
**Status:** Approved design, pre-implementation
**Tracking:** [claude-personas#89](https://github.com/Jin-HoMLee/claude-personas/issues/89), sub-issue (AC2 + AC5) of [#87](https://github.com/Jin-HoMLee/claude-personas/issues/87)

Companion spec: [2026-07-15-consolidation-canary-eval-design.md](2026-07-15-consolidation-canary-eval-design.md) (AC1, merged as #92).
The eval is the kill gate for what this spec builds: nothing here ships to users until the pass survives the 10-run canary gate.

## Problem

#87's consolidation pass needs mechanics: something a human can invoke explicitly that reads one memory store and delivers a tidied reorganization as a reviewable PR.
The acceptance criteria demand guarantees, not intentions: zero writes to `main`, single-store scope, typed one-operation-per-commit history, no tier demotion, no auto-run.
Prompt-level rules cannot carry guarantees of this kind.
Current practice is unambiguous that such policies belong in the tool layer: prompt guardrails are "suggestions, not enforcement", and least-privilege enforcement "should be mechanical and provide rigorous guarantees" rather than prompted (see Decision log).

## Design summary

Split the pass along the enforcement boundary:

- A deterministic wrapper, `framework/tools/consolidate_pass.py`, owns the entire git surface.
It is the only sanctioned write path, and every AC-level guarantee is a property of its code.
- A skill, `framework/skills/consolidate-memory/SKILL.md`, owns the semantics: what to dedupe, what to retire, how to redistribute - applied only through the wrapper.
- The existing human/MM merge gate reviews the resulting PR; the typed commit log is the unit of review.

A gate failure therefore always means the proposals were bad, never that the agent fumbled git.

## Scope decisions (brainstorm 2026-07-16)

- **Store-only v1.**
The pass reads only the memory store; session-transcript input is deferred to a follow-up issue.
Transcript locations are harness-specific, the eval fixture has no transcripts, and dedupe/retire/redistribute need none.
This trims the letter of #89's task text; noted on the issue at PR time.
- **PR delivery: automatic when a remote exists.**
`finish` pushes and opens the PR when the repo has a remote and `gh` is authed; in the eval's remoteless fixture it naturally stops at the branch.
One code path satisfies the "branch + PR" AC in real use and the eval contract in fixtures.

## Component 1 - `framework/tools/consolidate_pass.py`

Stdlib-only Python in the style of `memory_cliff.py`.
Pass state (store path, base commit) lives in local git config keys under `consolidate.*`, following git-flow's config-namespace precedent - no state files in the tree.

Subcommands:

### `begin --store <dir>`

Preflight, then branch creation.
Refuses (non-zero exit, nothing created) when: not a git repo; working tree dirty; `<dir>` is not a store (no `MEMORY.md`); leftover `consolidate.*` state or an existing `consolidate/<store>-<date>` branch for today.
On success: creates and checks out `consolidate/<store-slug>-<YYYY-MM-DD>` from current HEAD and records the config keys.

### `commit --op <dedupe|redistribute|retire> -m "<msg>"`

The only sanctioned write path.
Refuses unless the current branch is the recorded pass branch (this alone makes "zero writes to `main`" structural).
Collects all working-tree changes; if any changed path lies outside the recorded store, it lists the offenders and stages nothing - `begin`'s clean-tree requirement means any out-of-store diff mid-pass is the agent's stray edit.
On success: stages exactly the in-store changes and commits as `consolidate(<op>): <msg>`.
One wrapper call = one commit = one logical operation; the skill is responsible for making the operation logical (merge + delete + index-line update together), the wrapper for making it a single typed commit.

### `finish`

Verifies: clean tree; at least the shape invariants hold - every store file has an index line and every index line points at an existing file (index<->file sync, the mechanical share of the no-demotion guard).
**Amended by #97 (2026-07-17, evidenced by the #91 live run):** the sync check is a DELTA gate - `begin` snapshots the store's pre-existing sync findings (git-dir file, removed on every terminal path), and `finish` blocks only on findings the pass introduced, warning verbatim about surviving pre-existing ones; format examples in inline code or fenced blocks are stripped before link-matching. The enforced contract is "leave the store no worse" - pre-existing rot (e.g. a one-hop archive index the flat check can't see) never blocks delivery, and the gate stays deterministic and in code.
Zero typed commits is not an error: a genuinely clean store yields "nothing to consolidate", branch deleted, config cleared, exit 0.
With commits: if a remote exists and `gh` is authed, push first, then `gh pr create` with explicit `--title` and `--body` generated from the typed commit log - never `--fill` and never prompt-dependent, because non-interactive `gh pr create` fails without explicit values and requires the branch already pushed (web-checked 2026-07-16, see Decision log).
On push/PR delivery failure, exit non-zero with the manual commands printed - the branch and commits stay intact.
Remoteless is the expected fixture path, not an error: print the branch name and exit 0.

### `abort`

Returns to the base branch, deletes the pass branch, clears `consolidate.*` config.
Recovery path for crashes and timeouts; the eval already contains those as failed runs.

## Component 2 - `framework/skills/consolidate-memory/SKILL.md`

Invocation: explicit only - `/consolidate-memory <store>` in-session, or headless via `claude -p`.
The skill must be **self-contained**: it works identically when invoked as a skill and when injected via `--append-system-prompt-file`, because skill discovery does not reach the eval's fixture tempdir (see Decision log).

Contents:

1. **Store resolution:** the argument must be a directory containing `MEMORY.md`; anything else is a refusal, never a guess.
2. **The preservation stance** (the anti-smoothing rules, derived from the canary taxonomy):
exceptions never merge into the general rule they except; a fact referenced by nothing else is not therefore disposable; an old date is not evidence of staleness - only a contradicting newer fact is; when in doubt, keep.
3. **Operation discipline:** read the whole store before proposing anything; one logical operation per wrapper `commit` call; every retire must cite the newer contradicting fact in its commit message.
4. **Mechanics:** all writes go through `consolidate_pass.py` (`begin` -> edit + `commit` per op -> `finish`); the skill never runs raw `git commit`/`push`/`checkout`.

## Data flow

1. Explicit invocation with a store argument.
2. `begin` preflights and creates the pass branch.
3. The agent reads the whole store and builds its operation list under the preservation stance.
4. Per operation: edit files, then `commit --op <type> -m "<what and why>"`.
5. `finish` verifies, then delivers (PR when remote, branch when not).

The gate run (recorded on #88 after this PR merges):

```bash
python3 framework/tools/consolidation_eval/run_eval.py --runs 10 --model <pinned> \
    --pass-cmd 'claude -p "You are running a consolidation pass. Consolidate the memory store in the current directory. The consolidation wrapper is at <personas-repo>/framework/tools/consolidate_pass.py." --model <pinned> \
        --append-system-prompt-file <personas-repo>/framework/skills/consolidate-memory/SKILL.md \
        --permission-mode acceptEdits --allowedTools "Bash(python3 *),Bash(git *)"'
```

The exact flag set is finalized by the live smoke probe (first implementation task); the spec commits to the `--append-system-prompt-file` mechanism, not the final flag string.
The probe also decides whether the SKILL.md frontmatter is stripped before injection (it is catalog metadata, inert as system-prompt text).

## Error handling

| Failure | Behavior |
|---|---|
| `begin` preflight fails | Clear message, non-zero exit, nothing created (eval counts a FAILED run) |
| `commit` finds out-of-store paths | Lists offenders, stages nothing, agent reverts and retries |
| Zero-op `finish` | "Nothing to consolidate", branch deleted, exit 0 |
| Push/PR delivery fails | Non-zero exit, manual commands printed, branch + commits intact |
| Crash/timeout mid-pass | Partial branch remains; `abort` restores base + clears state |

## Testing

All zero-token, wired into `run_all.sh` CI:

- `framework/tools/tests/test_consolidate_pass.py` (+ `.sh` shim, the `test_memory_cliff` split): unittest for guard logic, subprocess-level checks for the CLI surface.
Every guard above gets a test, including "out-of-store reject stages nothing" and "zero-op finish leaves no branch or config behind".
- Regression: the eval's fake-pass discrimination tests must pass untouched.
- Live probes (implementation plan, not CI): first task is an end-to-end smoke of the headless invocation on a seeded fixture; the full 10-run gate record on #88 comes after merge.

## Contract docs (AC5) - CONVENTIONS.md section

A "The consolidation pass" section stating:

- **May:** dedupe, redistribute, retire - within one store per pass.
- **May not:** write to `main` (wrapper-enforced); cross stores or tiers; demote a rule out of a tier (the promotion ladder's job); run unattended (no cron - `memory_cliff` near-cliff output may only *suggest* a pass, which is #90's scope).
- **Review requirement:** delivery is always a PR to the human/MM merge gate; the typed one-op-per-commit log is the unit of review.
- **Enforcement split, stated explicitly:** mechanical guarantees (branch isolation, path scope, typed commits, index<->file sync) live in the wrapper; semantic obligations (preservation stance, operation atomicity, retire citations) live in the skill and the review.
A reader must be able to tell which guarantees are code and which are convention.

Adapt-not-copy: any instance learnings pulled into the section are rewritten against framework vocabulary, not pasted.

## Registration

`consolidate_pass.py` and the skill are shippable payload: both are added to `framework/FILES`.
The eval package deliberately stays out of `FILES` (dev tooling); this PR does not change that.

## Not in scope

- Session-transcript input (follow-up issue; store-only v1).
- `memory_cliff.py` threshold prompts (#90) and the side-by-side structural-audit comparison (#91).
- The 10-run gate record itself (post-merge activity on #88).
- Any consolidation of content across stores or tiers.

## Decision log

| Decision | Alternatives rejected | Why |
|---|---|---|
| Deterministic wrapper owns the git surface; skill owns semantics | Pure-skill (instructions carry the guarantees); fully scripted pass with LLM plan step | Web-checked 2026-07-16: prompt guardrails are "suggestions, not enforcement"; least-privilege enforcement "should be mechanical" ([MiniScope](https://arxiv.org/pdf/2512.11147), [enforcement-layer posts](https://dev.to/brianrhall/your-agents-guardrails-are-suggestions-not-enforcement-2c8k)); plan-then-execute rejected because `redistribute` needs free-form rewrites that do not reduce to a plan schema |
| Store-only v1, transcripts deferred | Optional or required transcript input per issue text | Harness-specific paths in a vendor-neutral skill; the eval cannot exercise them; the three ops need none |
| Auto-PR when remote exists | Never-PR (human runs `gh pr create`); flag-controlled | One code path serves both the AC ("branch + PR") and the eval contract (remoteless fixture) |
| Pass state in `consolidate.*` git config | State file in `.git/` or the tree | git-flow precedent stores lifecycle state in config namespaces; nothing eval-visible lands in the tree |
| Self-contained SKILL.md + `--append-system-prompt-file` gate invocation | Rely on `/consolidate-memory` expansion inside the fixture | Headless skill expansion is confirmed ([docs](https://code.claude.com/docs/en/headless)) but discovery is cwd-scoped - the fixture tempdir has no skills; `--bare` additionally skips skill discovery |
| Zero-op finish exits 0 | Treat empty pass as failure | A genuinely clean store is a legitimate outcome; the eval's cleanup score (0/6) already exposes a lazy no-op |
| Wrapper generates + review/eval validate | Wrapper-only trust | Layered enforcement is the conventional-commits norm (commitizen generates, commitlint/CI validates) |
| `finish` pushes first, then `gh pr create` with explicit `--title`/`--body` | `--fill`; interactive prompting | Non-interactive `gh pr create` [fails without explicit `--body`](https://github.com/cli/cli/issues/5670) and [requires a pushed branch](https://github.com/cli/cli/issues/6468); [`--fill` breaks in CI contexts](https://github.com/cli/cli/issues/5896) (web-checked 2026-07-16) |
| Custom pass survives despite "native consolidation" chatter | Wait for Claude Code to ship it | Official memory docs (fetched 2026-07-16) ship no consolidation pipeline; "AutoDream" remains third-party myth; and our wedge (mandatory line-level PR review, vendor-neutral) is absent from every shipping design regardless |

## References

- [#87](https://github.com/Jin-HoMLee/claude-personas/issues/87) design + field evidence; [#89](https://github.com/Jin-HoMLee/claude-personas/issues/89) task + ACs.
- Eval contract this design must satisfy: `framework/tools/consolidation_eval/run_eval.py` docstring (exit 0; `consolidate/*` branch detection).
- Guardrail placement: [MiniScope](https://arxiv.org/pdf/2512.11147), [Least-Privilege Language Models](https://www.emergentmind.com/topics/least-privilege-language-models), [Scott Logic 2026-07-15](https://blog.scottlogic.com/2026/07/15/choosing-the-right-tool-safety-approach-for-coding-agents.html), [Arthur guardrails](https://www.arthur.ai/blog/best-practices-for-building-agents-guardrails).
- Headless invocation: [Claude Code headless docs](https://code.claude.com/docs/en/headless).
- Lifecycle CLI precedent: [git-flow commands](https://git-flow.sh/docs/commands/).
