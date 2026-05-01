---
name: GitHub workflow conventions
description: PR review, branch discipline, issue drafts — rules for all GitHub interactions
type: feedback
---
## Branch discipline

Never push directly to main. All changes go through a PR, even small hotfixes.

See [Branch names](feedback_branch_names.md) for the required `gh issue develop` command and branch naming convention.

## Stacked PRs

When a PR B is stacked on PR A (B targets A's branch, not main): retarget B to main with `gh pr edit <B> --base main` **before** merging A. Then merge A with `--delete-branch`. If A is merged first with `--delete-branch`, GitHub auto-closes B because its base branch no longer exists.

## Reference format — always prefix + keyword

Canonical form for any PR or issue reference in chat:

| Kind | Prefix | Example |
|---|---|---|
| Pull request | `PR #NNN` | `[PR #185](url) (short keyword description)` |
| Plain issue | `Issue #NNN` | `[Issue #172](url) (short keyword description)` |

Every reference: spelled-out prefix, Markdown-linked number, short keyword description in parens.

When PR closes issue, draw the relationship in **one phrase**:
- ✓ `PR #185 closes Issue #161 (short keyword)`
- ✗ "PR #185 is open" then later "Issue #161 done" — reads as two unrelated items
- ✗ `PR #185 closes #161` — missing prefix and keyword

**Why:** Bare `#NNN` forces mental lookup. Adjacent sentences mentioning a paired PR + issue without the link read as if they're independent.

**How to apply:** Always use the prefix that matches the role of the reference in context. If your project uses parent/sub-issue hierarchies, extend this table with `parent Issue` / `Sub-Issue` rows so the hierarchy is visible at a glance.

## Commit message scope

Use the **topic/module** as scope — never the role. The role is already captured in the branch name.

- ✓ `feat(auth):`, `fix(parser):`, `docs(readme):`, `chore(deps):`
- ✗ `feat(developer):`, `chore(pm):`

**Why:** Conventional commits spec defines scope as *what* changed, not *who* changed it. Role traceability lives in the branch name, git authorship, and lab notebook.

## Conventional Commits ↔ label mapping

Map your CC scopes to your project's labels — the convention is: `feat:` → `enhancement`, `fix:` → `bug`, `docs:` → `documentation`, `refactor:` → `refactor`, `perf:` → `performance`, `chore:` → no label (rare). Customize per project.

## PR review workflow

When addressing review comments: fix → commit → push → reply to the comment with the commit SHA. One commit per comment. Never batch.

**How to apply:** Do NOT resolve the comment after replying — user resolves manually. Always reply using `gh pr comment <number> --body "..."`, never `gh pr review`. The latter submits a formal GitHub review event which can trigger spurious CI checks.

**Before merge checklist (run through this before the user merges):**

1. Lab notebook entry added
2. Docs reviewed for staleness

## Merging PRs

**Push and merge are always two separate steps.** Push first, wait for CI to finish, then merge. Never chain `git push && gh pr merge` — checks will block the merge anyway, and the pattern skips the pre-merge checklist.

Never use `--admin` to force-merge. If checks are still running, use `--auto` so the merge happens automatically once they pass. Only merge when all required checks are green.

**Why:** `--admin` bypasses branch protection and can merge on a failing or still-running check — caught in practice when a test was still running at merge time.

## Never force-push without explicit user confirmation

**`git push --force` AND `git push --force-with-lease` are both off-limits without asking first** — even when the operation looks "safe" (e.g. rebasing your own branch onto newer main to make a PR mergeable). Force-push falls under hard-to-reverse operations: it overwrites the remote branch history and any open review threads pinned to specific commit SHAs.

**Why:** Two reasons.
1. The user may have local commits on the branch that aren't on the remote, or be reviewing the PR in a window that pins to specific SHAs — force-push silently invalidates both.
2. Even `--force-with-lease` only protects against the *remote* having moved; it doesn't protect against the user's local state or in-flight reviews.

**How to apply:**
- If a PR is "behind base", surface the situation, propose the fix (rebase or merge-from-main), and **wait for confirmation** before pushing
- "GitHub said the branch is behind" is not authorisation — the user must explicitly approve the rewrite
- For first-time push of a new branch, plain `git push` (or `git push -u`) is fine — that's not a force-push
- Same rule applies to other history-rewriting operations: `git reset --hard origin/...`, `git rebase -i`, `git commit --amend` on already-pushed commits

## Always include URLs when referencing issues or PRs

When mentioning an issue or PR by number, always include the full GitHub URL alongside it so the user can click directly. Prefer the markdown-link form so the reference is one clickable token: `[#N (keyword)](url)`.

**Why:** User explicitly requested this for direct access without having to navigate manually.

**How to apply:** e.g. `[#118 (short keyword)](https://github.com/<your-github-username>/<your-project>/issues/118)`. Bare `#N` is acceptable only inside fenced code blocks or commit messages.

## Role labels — `role:<role>`

Every open issue must carry one or more `role:<role>` labels indicating which role(s) are **implementing** the work (not who consumes the output).

**Why:** GitHub assignees only carry a username, which is just one person here — useless for filtering by role. Role labels give each role a self-service "issues I'm involved in" view via `gh issue list --label role:<role>`.

**How to apply:**
- Add at triage time, alongside milestone/priority/size. Multi-label is fine when implementation crosses roles.
- Use `role:pm` only for meta-PM tasks (board structure, milestone reorgs, process changes) — most code/research issues will not have `role:pm`.
- Tag the *implementer*, not the consumer.

**Per-role overview commands:**
```bash
gh issue list --repo <your-github-username>/<your-project> --state open --label role:developer
gh issue list --repo <your-github-username>/<your-project> --state open --label role:pm
```

## Issue and PR draft formatting

**Always write issue/PR body drafts as standalone `.md` files** under `/tmp/issue-drafts/<short-name>.md` (one file per draft) and link the path back in chat. The user opens them in VS Code and hits `Cmd+Shift+V` for rendered preview.

**Why:** Inline fenced code blocks render the markdown as raw text in the chat panel — tables, links, headings are unreadable. AskUserQuestion previews don't reliably appear either. A standalone `.md` file gives full rendered preview plus the same copy-paste affordance.

**How to apply:**
- Title goes as the first H1 line in the file
- Optional metadata line below the H1 in a `> blockquote`: labels, milestone, size, blockers
- Body is regular Markdown — no outer fenced wrapping
- One file per issue draft (not all bundled)
- After approval, pass to `gh issue create --body-file <path>` (cleaner than `--body "$(cat ...)"`)
- Don't bother cleaning up `/tmp/issue-drafts/` — `/tmp` is volatile

Always include a `**Created by:** <Role>` line in the issue body to indicate which role created the issue.

**Why:** Makes it easy to trace the origin of an issue when multiple roles are active.

Always link a new PR to its corresponding issue by including `Closes #XXX` in the PR body. This shows PR #XXX as "1 linked pull request" in the issue's Development panel (right sidebar). There is no CLI way to retroactively link an existing branch — `gh issue develop` only creates new branches.

**Why:** GitHub parses the `Closes` keyword and creates the Development link automatically; no extra API call needed.
