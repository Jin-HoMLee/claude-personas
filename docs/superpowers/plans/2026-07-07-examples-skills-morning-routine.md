# Examples Skills Morning Routine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the copy-once `examples/skills/` content from issue #56 without changing the installable framework payload.

**Architecture:** `examples/skills/` stays example-owned content and is never listed in `framework/FILES`.
The demo skill mirrors the PM morning routine memory as an explicit skill workflow, while `examples/skills/README.md` explains when skills are the right visibility tier and how each supported tool discovers them.

**Tech Stack:** Markdown skill files, bash fixture tests, live tool discovery smoke.

## Global Constraints

- `examples/skills/` is copy-once content and must not be synced by `framework/tools/install.sh`.
- `framework/FILES` must not list anything under `examples/`.
- Skill frontmatter must use `name` and `description`.
- README discovery guidance must match the live probe results in `docs/superpowers/specs/2026-07-06-framework-distribution-design.md` section 9.
- The closing PR must also close #17 and note that `examples/hooks/` was the hooks half.

---

### Task 1: Example Skill Boundary Test

**Files:**
- Create: `framework/tools/tests/test_examples_skills.sh`

**Interfaces:**
- Consumes: `framework/FILES`, `examples/skills/README.md`, `examples/skills/morning-routine/SKILL.md`.
- Produces: a regression test proving the examples skill exists and remains outside the framework payload.

- [x] **Step 1: Write the failing test**

Create `framework/tools/tests/test_examples_skills.sh` with assertions that the README exists, the demo skill exists, the skill frontmatter has `name:` and `description:`, and `framework/FILES` has no `examples/` entries.

- [x] **Step 2: Run test to verify it fails**

Run: `bash framework/tools/tests/test_examples_skills.sh`
Expected: FAIL because `examples/skills/README.md` and `examples/skills/morning-routine/SKILL.md` do not exist yet.

- [x] **Step 3: Commit after green**

Commit together with Task 2 after the implementation passes.

### Task 2: Morning Routine Example Skill

**Files:**
- Create: `examples/skills/morning-routine/SKILL.md`
- Create: `examples/skills/README.md`
- Modify: `examples/README.md`

**Interfaces:**
- Consumes: `examples/pm/feedback_morning_routine.md` and the framework distribution spec section 7.
- Produces: copy-once example content for users who want to promote a memory-backed ritual into an explicit skill.

- [x] **Step 1: Implement the demo skill**

Create `examples/skills/morning-routine/SKILL.md` as a pedagogical workflow triggered by a morning greeting in a PM session.
Keep it intentionally non-production-grade and point readers to `framework/skills/load-persona-memory` as the mature reference pattern.

- [x] **Step 2: Implement the README**

Create `examples/skills/README.md` with tier framing, memory-to-skill guidance, discovery notes for Claude Code, Codex, and OpenCode, and copy-once semantics.

- [x] **Step 3: Link from the examples index**

Add a `skills/` section to `examples/README.md`.

- [x] **Step 4: Verify green**

Run: `bash framework/tools/tests/test_examples_skills.sh`
Expected: PASS.

Run: `bash framework/tools/tests/test_framework_files.sh`
Expected: PASS, including no `examples/` entries in `framework/FILES`.

### Task 3: Live Discovery Smoke and PR

**Files:**
- No additional files expected unless the live smoke exposes a doc correction.

**Interfaces:**
- Consumes: the example skill copied into a temporary real instance skills directory.
- Produces: evidence for #56 acceptance criterion 1.

- [x] **Step 1: Smoke at least one live tool**

Copy the demo skill into a temporary repo-level `.agents/skills/morning-routine/` location and run a live tool skill-discovery probe.
Clean up the temporary copy afterward.

- [x] **Step 2: Run full relevant tests**

Run: `bash framework/tools/tests/run_all.sh`
Run Python tests if the shell harness reports they are not included.

- [x] **Step 3: Open PR**

Open a PR that closes #56 and #17.
In the PR body, note that `examples/hooks/` landed earlier as the hooks half and this PR lands the skills half.
