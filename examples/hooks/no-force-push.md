---
name: Block git push --force
description: PreToolUse hook on Bash that rejects any command containing `git push --force` or `git push -f`
type: hook
---

## What it does

Blocks any Bash invocation containing `git push --force` or `git push -f` (where `-f` is a standalone flag) before the command runs.

## Why

A force-push to a shared branch silently rewrites history and can destroy other people's commits. The damage is hard to reverse — once the new ref is on the remote, anyone who pulls before noticing has the rewritten history locally. A memory rule like "never force-push" depends on Claude reading and remembering it on every turn that involves git; a hook removes the dependency.

## The JSON snippet

Add to `~/.claude/settings.json` under the `hooks` key. If a `PreToolUse` array already exists, merge the entry into it rather than replacing.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command // \"\"' | grep -qE 'git[[:space:]]+push([[:space:]]+[^&|;]+)*[[:space:]]+(--force([[:space:]]|=|$)|-f([[:space:]]|$))' && { echo 'Blocked: force-push is destructive. Use --force-with-lease if you genuinely need to rewrite, or sync via fetch + rebase.' >&2; exit 2; } || exit 0"
          }
        ]
      }
    ]
  }
}
```

The command pipeline:
1. `jq -r '.tool_input.command // ""'` extracts the Bash command string from the hook event.
2. `grep -qE` matches `git push ... --force` or `git push ... -f` with reasonable spacing tolerance.
3. On match: exit 2 (block) with a message routed to the user. On no match: exit 0 (allow).

## How to test

After installing, try:

```bash
git push --force origin main
```

You should see the hook's error message and the command should not execute.

A whitelisted form Claude can still use when force-push is genuinely intended:

```bash
git push --force-with-lease origin my-branch
```

(The hook intentionally allows `--force-with-lease`, which is the safer alternative — it only rewrites if the remote ref matches the local view of it.)

## Caveats

- Does **not** block force-pushes via refspec (`git push origin +main:main`). Add a `\+[^[:space:]]+:` clause to the regex if you want that coverage.
- Does **not** block force-pushes wrapped in subshells or eval (`bash -c 'git push -f'`). The matcher operates on the literal command string.
- Pair with a `feedback_*.md` memory rule explaining the broader principle (force-push semantics, when `--force-with-lease` is appropriate) for cases the regex misses.
