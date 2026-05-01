---
name: Test before opening PR
description: Always run relevant tests before opening a PR — match test scope to change scope
type: feedback
---
Always run tests before opening a PR. Match the scope of the test to the scope of the change — don't default to a full end-to-end run when a targeted test suffices.

**Why:** Opening a PR with untested changes wastes review cycles. But a full end-to-end run for a single-module change is overkill — it's expensive, slow, and tests far more than what changed.

**How to apply:**
- Code changes → run your test suite before `gh pr create`
- Single-module change → test just that module on a cheap environment
- Full infrastructure/deployment changes → wait for a successful end-to-end run before opening PR
- Never batch push + PR create in one command for infrastructure changes
