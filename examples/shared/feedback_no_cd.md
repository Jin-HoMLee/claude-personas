---
name: Never `cd` into other repos — use git -C <path> instead
description: cwd persists across Bash calls so leaving the project worktree implicitly changes context for every subsequent command
type: feedback
---
**Rule:** never `cd` out of the project worktree to operate on another repo (sibling repos, clones, etc.). Use absolute paths and `git -C <path> <subcommand>` for git operations elsewhere.

**Why:** the Bash tool's working directory persists across calls. A `cd ~/path/to/other-repo` in one call silently changes the context for every later Bash call, until the shell happens to reset (which is unreliable). A misfired command in the wrong cwd can edit, commit, or push to the wrong repo. The risk is especially bad with adjacent repos that look similar.

**How to apply:**
- For git operations on another repo: `git -C /absolute/path/to/repo <subcommand>` (e.g. `git -C ~/projects/other-repo/ diff --stat`).
- For file reads/writes: use the Read/Write/Edit tools with absolute paths — they never depend on cwd.
- For shell commands that genuinely need a different cwd (e.g. running a build), use `(cd /path && cmd)` in a subshell so the cd doesn't escape, or pass the path as an argument when the tool supports it.
- If a command really requires `cd`, run it as a one-off subshell, never as a persistent state change.
