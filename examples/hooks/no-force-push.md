---
name: Block git push --force
description: PreToolUse hook on Bash that rejects any command containing `git push --force` or `git push -f`
type: hook
---

## What it does

Blocks any Bash invocation that force-pushes via any of three forms:

1. `git push --force [args]`
2. `git push -f [args]` — including combined short flags (`-fv`, `-fu`, `-vf`, etc.)
3. `git push <remote> +<ref>:<ref>` — the refspec force form (a leading `+` in a refspec means force)

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
            "command": "jq -r '.tool_input.command // \"\"' | grep -qE 'git[[:space:]]+push[^&|;]*[[:space:]]+(--force([[:space:]]|=|$)|-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|=|$)|\\+[^[:space:]:]+:[^[:space:]]+)' && { echo 'Blocked: force-push is destructive. Use --force-with-lease if you genuinely need to rewrite, or sync via fetch + rebase.' >&2; exit 2; } || exit 0"
          }
        ]
      }
    ]
  }
}
```

The command pipeline:
1. `jq -r '.tool_input.command // ""'` extracts the Bash command string from the hook event.
2. `grep -qE` matches `git push ... --force` OR `git push ... -[anything-with-f]` OR `git push ... +ref:ref`, scoped to a single shell command (the `[^&|;]*` prefix prevents matching across shell separators).
3. On match: exit 2 (block) with a message routed to the user. On no match: exit 0 (allow).

### Regex anatomy (why each alternation matters)

- `--force([[:space:]]|=|$)` — the long-form flag, terminated by space, `=`, or end-of-line. The trailing class is what stops `--force-with-lease` from matching (next char is `-`, not in the class).
- `-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|=|$)` — short-flag clusters containing `f`, in any position. Catches `-f`, `-fv`, `-fu`, `-fvu`, `-vf`, `-vfu`. The `[a-zA-Z]*` on both sides handles `f` not being at the start (e.g., `-vf`).
- `\+[^[:space:]:]+:[^[:space:]]+` — the refspec force form `+<src>:<dst>`. The `+` is a literal force marker, the `:` separates the refnames.

## How to test

After installing, try:

```bash
git push --force origin main
git push -f origin main
git push -fv origin main
git push origin +main:main
```

You should see the hook's error message for each, and the commands should not execute.

A whitelisted form Claude can still use when force-push is genuinely intended:

```bash
git push --force-with-lease origin my-branch
```

(The hook intentionally allows `--force-with-lease`, which is the safer alternative — it only rewrites if the remote ref matches the local view of it.)

## Caveats

- Does **not** block force-pushes wrapped in subshells or eval (`bash -c 'git push -f'`, `eval "git push -f"`). The matcher operates on the literal command string. For high-security setups, restrict subshell tool access at the harness level.
- Does **not** block `git push --force-if-includes=...` (another safer variant, intentionally allowed). If your project policy disallows even that, add a fourth alternation.
- The combined short-flag matcher catches non-flag substrings if they happen to contain `f` (e.g., `git push -info` would match). Since these aren't valid git push flags they'd fail anyway — the hook just fails them slightly earlier.
- Pair with a `feedback_*.md` memory rule explaining the broader principle (force-push semantics, when `--force-with-lease` is appropriate) for cases the regex misses.
