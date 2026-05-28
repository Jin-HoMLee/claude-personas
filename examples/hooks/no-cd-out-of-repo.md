---
name: Block cd out of the project worktree
description: PreToolUse hook on Bash that rejects `cd <path>` commands targeting a path outside the project repo
type: hook
---

## What it does

Blocks any Bash invocation starting with `cd ` (excluding `cd -` and `cd ~`/`cd $HOME` cases) before the command runs. The principle: stay in the worktree; use `git -C <path>` and absolute paths for cross-repo work.

## Why

The Bash tool's working directory persists across calls within a session. A `cd ~/other-repo` in one call silently changes the context for every later Bash call until the shell happens to reset. A misfired command in the wrong cwd can edit, commit, or push to the wrong repo — especially dangerous with adjacent repos that look similar (e.g., sibling clones of the same project).

The memory rule equivalent is [`examples/shared/feedback_no_cd.md`](../shared/feedback_no_cd.md). The hook makes the rule unmissable.

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
            "command": "jq -r '.tool_input.command // \"\"' | grep -qE '^[[:space:]]*cd[[:space:]]+[^-]' && { echo 'Blocked: cd persists across Bash calls and risks operating in the wrong repo. Use `git -C <abs-path>` for cross-repo git ops, or absolute paths with Read/Write/Edit tools. For one-off subshells where cd is genuinely needed: `(cd /path && cmd)`.' >&2; exit 2; } || exit 0"
          }
        ]
      }
    ]
  }
}
```

The regex matches `cd <something>` where `<something>` is not a leading `-` (preserving `cd -` as the "go back" form). It deliberately catches `cd /abs/path`, `cd ~/repo`, `cd ../sibling`, and `cd $HOME/foo`, all of which would escape the worktree.

## How to test

After installing, try:

```bash
cd ~/other-project
```

You should see the hook's error message and the command should not execute.

Allowed forms:

```bash
(cd /tmp && ls)          # subshell — cd is scoped
git -C /abs/path status  # operates on a path without changing cwd
```

## Caveats

- Does **not** block cd embedded in compound commands (`make build && cd dist && ./run`). For full coverage, add `&&[[:space:]]*cd[[:space:]]` to the regex.
- Some legitimate workflows (running an installer script in a temp dir) genuinely want a session-scoped cd. If you hit this often, narrow the regex to only block cd to paths *outside* a specific allowlist (e.g., excluding `~/dev/`).
- The `cd -` form is allowed (return to previous dir) because it can only get you back where you already were; not a cross-repo escape vector.
