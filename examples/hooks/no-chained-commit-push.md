---
name: Block chained git commit && push or push && merge
description: PreToolUse hook on Bash that rejects compound commands chaining git commit, push, and merge in a single shell call
type: hook
---

## What it does

Blocks any Bash invocation that chains two of `git commit`, `git push`, and `gh pr merge` in a single shell call (via `&&`, `;`, or `|`). The principle: each of these is a checkpoint the user (or you on review) should see between, not collapse into one atomic step.

## Why

A `git commit -m "X" && git push` looks efficient but loses the opportunity to inspect what's about to be pushed before it lands on the remote. A `git push && gh pr merge` is worse — pushes a change and immediately merges it without giving review a chance to fire. Both patterns mask intent in a way that's hard to reverse if the commit message was wrong, the diff included something it shouldn't, or the merge bypassed a check that hadn't run yet.

A memory rule equivalent is "never chain commit/push/merge in one bash call". The hook removes the temptation entirely.

## The JSON snippet

Add to `~/.claude/settings.json` under the `hooks` key.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command // \"\"' | grep -qE 'git[[:space:]]+(commit|push)[^&|;]*[&|;]+[[:space:]]*(git[[:space:]]+(push|merge)|gh[[:space:]]+pr[[:space:]]+merge)' && { echo 'Blocked: do not chain git commit/push/merge in one call. Split into separate Bash invocations so you (and the user) can see the state between each step.' >&2; exit 2; } || exit 0"
          }
        ]
      }
    ]
  }
}
```

The regex matches: `git (commit|push) ... (&&|;|||) ... (git (push|merge) | gh pr merge)`.

## How to test

After installing, try:

```bash
git commit -m "test" && git push
```

You should see the hook's error message. Run them as separate calls instead:

```bash
git commit -m "test"
git push
```

## Caveats

- Does **not** block chains involving `git rebase`, `git cherry-pick`, etc. — only the commit→push→merge pipeline. Extend the regex if your workflow has other dangerous chains.
- The matcher allows `git push` alone (no chain), which is the common case. The hook only fires when push is preceded or followed by another change-state operation.
- Compatible with `git commit; git push` (semicolon-chained) and `git push|tee log.txt && gh pr merge` (mixed operators).
- If you genuinely need an atomic operation (e.g., a release script that ships a tagged commit), invoke that script as a single command — the regex won't match.
