# Examples

Real-world patterns from a production claude-personas setup, sanitized for general use.

Browse freely — these are opt-in. You don't need any of them to use the scaffold;
the stub `MEMORY.md` files in `developer/`, `pm/`, and `designer/` are enough to get
started. Come back here when you want proven patterns to copy.

## How to adopt a pattern

1. Read the file — each `feedback_*.md` has a **Why:** line and a **How to apply:** line
2. If it fits, copy it into the right place:
   - Applies to all roles → `shared/feedback_<topic>.md`, link from `shared/MEMORY.md`
   - Applies to one role → `<role>/feedback_<topic>.md`, link from `<role>/MEMORY.md`
3. If you want Claude to apply the rule on every turn without a file read, also add an
   inline version to the "Always in effect" section of the role's `MEMORY.md`

## What's here

### shared/ — universal patterns (apply to any role)

**Claude behavior:**
- `feedback_explain_changes.md` — briefly explain why before each edit
- `feedback_communicate_next_steps.md` — always state what comes next
- `feedback_ask_user_question.md` — use AskUserQuestion for structured choices
- `feedback_no_planning_mode.md` — skip plan mode; use inline proposals instead
- `feedback_todo_list.md` — maintain a visible todo list for multi-step work
- `feedback_chat_pacing.md` — pause for the user to read before permission prompts
- `feedback_compact_reminders.md` — suggest /compact at session boundaries
- `feedback_read_over_awk.md` — prefer the Read tool over awk/sed/cat
- `feedback_cli_style.md` — prefer gh + jq over python -c one-liners

**Memory architecture:**
- `feedback_role_memory_boundary.md` — role-path only; reach shared via symlink
- `feedback_memory_escalation.md` — how to escalate rules that keep being missed
- `feedback_no_cd.md` — never cd out of the project; use absolute paths

**Project hygiene:**
- `feedback_lab_notebook.md` — work log: newest-first, timestamp, entry before shipping
- `feedback_scope_discipline.md` — no silent scope expansion mid-issue
- `feedback_team_structure.md` — role definitions template + worktree layout
- `feedback_team_standup.md` — async standup: FYI = done immediately, Pending = waiting
- `team_standup.md` — blank standup template

**GitHub workflow:**
- `feedback_github_workflow.md` — PR/issue conventions, force-push rules, draft formatting
- `feedback_branch_names.md` — alphanumeric + hyphen only, rename API for existing PRs

### developer/ — Developer role patterns

- `feedback_multi_file_workflow.md` — plan → docs → TodoWrite → one-file-per-commit
- `feedback_test_before_pr.md` — always run tests before opening a PR
- `feedback_collaboration.md` — verify before claiming, defer to domain terminology
- `feedback_role_scope.md` — what Developer owns vs. what the domain role owns

### pm/ — PM role patterns

- `feedback_milestones.md` — iteration-first naming, Arc concept, assignment decision tree
- `feedback_check_board.md` — query live board at session start, not memory snapshots
- `feedback_morning_routine.md` — morning warm-up: recap → standup → triage

### designer/ — Designer role patterns (illustrative)

- `feedback_design_system.md` — token naming, component naming conventions
- `feedback_design_handoff.md` — handoff spec and standup protocol
