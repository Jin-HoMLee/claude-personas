---
name: Branch name sanitization
description: Branch names must be alphanumeric + hyphens/underscores only — no Unicode or special characters
type: feedback
---
Branch names must contain only alphanumeric characters, hyphens, and underscores. Never use Unicode symbols (e.g. `→`, `–`, `…`) even if they appear in the issue title.

**Why:** Non-alphanumeric characters in branch names break CI and GitHub review workflows. A branch name like `42-refactor-config-→-newconfig-...` (with a Unicode arrow) caused PR review failures in practice.

**How to apply:** When using `gh issue develop`, check the generated branch name before checking out. If the issue title contains any non-ASCII or special characters, pass an explicit `--name` flag with a sanitized name:
```bash
gh issue develop 42 --name "42-add-user-auth-endpoint" --checkout
```
Replace arrows, dashes, slashes, and any Unicode with plain hyphens or drop them entirely.

---

## Renaming a branch that already has an open PR

Git branches have no unique identifier — they are named pointers to a commit SHA. Pushing a new branch name and deleting the old one leaves the PR orphaned ("branch deleted"). GitHub only updates open PRs if you use **GitHub's rename API endpoint**, which patches the PR's head branch reference in GitHub's database.

```bash
# 1. Rename on GitHub (updates open PRs automatically)
gh api repos/<your-github-username>/<your-project>/branches/<old-name>/rename \
  -X POST -f new_name="<new-name>"

# 2. Sync locally
git fetch origin
git branch -m "<old-name>" "<new-name>"
git branch -u origin/<new-name>
```

Do NOT use `git push origin new-name` + `git push origin --delete old-name` — that orphans the PR.

**Warning:** The GitHub rename API has been observed to close PRs despite being the documented approach. If the PR closes after renaming, it cannot be reopened (GitHub rejects it because the old head branch no longer exists). Recovery: create a new PR from the new branch with the same title/body, then close the old one. The new PR loses review history but retains the commit history.
