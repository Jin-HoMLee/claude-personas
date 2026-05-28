# Hooks

Hook configurations that prevent specific failure modes deterministically — the harness enforces them, so Claude can't drift.

## Why hooks belong in this template

`claude-personas` is mostly about *memory* — rules Claude reads and applies. But a memory rule is a *probabilistic* enforcement: Claude reads it and chooses whether to follow. For rules with a **deterministic trigger** (a specific Bash invocation, a specific file edit), a hook gives **guaranteed firing** at zero token cost.

Roughly half the rules in a mature memory directory have deterministic triggers and are better expressed as hooks. Examples:

- "Never force-push" → fires only when you actually run `git push --force`
- "Never `cd` out of the repo" → fires only when you actually run `cd <path>`
- "Always run tests before opening a PR" → fires only when you actually run `gh pr create`

A memory rule for these patterns burns context every turn even when the situation isn't relevant. A hook costs nothing until it fires, and when it fires it cannot be ignored.

## When to prefer a hook over a memory rule

| Use a **hook** when… | Use a **memory rule** when… |
|---|---|
| The rule has a discrete trigger (specific Bash command, specific file edit) | The rule shapes behavior across many situations (tone, style, what to prioritize) |
| The cost of violation is high (data loss, broken state) | The cost of violation is low (style drift, slightly worse output) |
| You'd phrase the rule as "**never** do X" or "**always** do Y before Z" | You'd phrase the rule as "**prefer** X" or "**when** Y, **consider** Z" |
| The check fits in a shell one-liner | The check requires LLM judgment |

## How to install a hook

Each example file in this directory contains:

1. **What it does** — the failure mode the hook catches
2. **Why** — the incident or pain point that motivates the rule
3. **The JSON snippet** — paste into your `~/.claude/settings.json` (or your project's `.claude/settings.json`) under `hooks`
4. **How to test** — a command you can run to verify the hook blocks correctly

To install: open `~/.claude/settings.json`, locate (or create) the `"hooks"` key, and merge the snippet from each example file. If you want a starter file, see [`settings.example.json`](settings.example.json) for all three example hooks combined.

## Available examples

- [`no-force-push.md`](no-force-push.md) — block `git push --force` and `git push -f`
- [`no-cd-out-of-repo.md`](no-cd-out-of-repo.md) — block `cd` to outside the project worktree
- [`no-chained-commit-push.md`](no-chained-commit-push.md) — block `git commit && git push` / `git push && gh pr merge` in one shell call

## Caveats

- **Hook commands run with your shell privileges.** Review what you paste before adding it to settings.json.
- **Hooks aren't a substitute for review.** They catch one specific shape of mistake — they don't catch the broader category. The "no force-push" hook blocks the literal command but doesn't catch `git push origin +main:main` (which is also a force-push via refspec). For full coverage, pair the hook with a memory rule that explains the broader principle.
- **Hook configs are per-user / per-project, not per-role.** They live in `settings.json`, not in the memory repo. Every Claude Code session you open in the relevant scope is affected.

## See also

- The `CONVENTIONS.md` four-tier section (root of the repo) frames hooks as one of four visibility tiers Claude Code supports.
- The [`feedback_memory_escalation.md`](../shared/feedback_memory_escalation.md) escalation rule asks "hookable? skillable?" before promoting a memory rule inline.
