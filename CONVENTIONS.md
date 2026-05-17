# Conventions

Read this once to understand the system. Then close it and start writing rules.

## The mental model in one paragraph

`claude-personas` is a **memory-only repo** — you fork it once per project (`claude-personas-<my-app>`) and never use it as your project codebase. Inside it, each role (`developer/`, `pm/`, `designer/`, `scientist/`) is just a folder of memory files.

Your **project repo** (the codebase you actually work on) is separate. For each role you want to use, you create one **independent project clone** at a sibling path (`my-app/`, `my-app-pm/`, etc.). Each project clone has a single `memory/` symlink pointing into the matching role folder of the memory repo. Claude Code auto-loads the right `MEMORY.md` based on which clone you're working in.

Each role's clone is a real `git clone` of the project — `git fetch origin` between clones is exactly how human team members sync via GitHub.

## The two-system split

Claude Code offers two places to give Claude persistent instructions:

| Layer | File | What goes here | Committed? |
|---|---|---|---|
| **Project facts** | `CLAUDE.md` (in your project repo) | Non-obvious codebase decisions, known gotchas, infra quirks, API behavior | Yes |
| **AI behavior rules** | Memory files (`MEMORY.md` + `feedback_*.md`, in the memory repo) | How Claude should behave: tone, habits, workflow rules, role-specific conventions | Yes (in the memory repo) |

Keeping these separate prevents a common failure mode: mixing codebase facts with AI behavior rules, which makes both harder to maintain and share.

## Why role-specific memory directories?

When you play multiple roles on a project (Developer on Monday, PM on Tuesday, Designer on Wednesday, Scientist on Thursday), you want Claude to behave differently in each context. The Developer should know your test conventions; the PM should know your milestone format; neither should wade through the other's rules.

Each role gets its own project clone (and so its own Claude Code auto-memory hash dir). The `memory/` symlink in that clone resolves to the role-specific folder in the memory repo. Claude context-switches automatically when you open a different clone — no settings to configure inside the clone, no per-session flags.

## The MEMORY.md two-tier structure

Each role's `MEMORY.md` has two sections:

### Always in effect

Rules inlined directly in the index file. Claude reads these without opening any file — they're in `MEMORY.md` itself, which is auto-loaded every session.

**Use this tier for:** rules that must be applied on every turn regardless of context. Examples: "never commit to main", "always add a role label to issues", "use Read not cat".

**Drift annotations:** when you promote a rule from a reference file into "Always in effect", add a comment showing where it came from:

```text
- **My rule:** Don't do X, do Y instead. <!-- src: shared/feedback_my_rule.md -->
```

This lets you find and update the source file if the rule ever changes, and prevents duplicate edits.

### Reference

Links to separate `feedback_*.md` files. Claude reads these only when the linked topic is relevant to the current task.

**Use this tier for:** rules that apply in specific situations (git workflow, PR process, testing conventions), detailed explanations with examples, rules that are rarely needed.

## The escalation pattern

When Claude repeats a mistake you've already corrected:

1. Search for an existing memory on that topic across all memory files.
   - Found in "Always in effect" → rule already fires at session start; rewrite it to be more specific or actionable.
   - Found only behind a link → **promote it**: copy the rule inline into the role's `MEMORY.md` under "Always in effect", add a drift annotation.
   - Not found anywhere → create a new `feedback_<topic>.md` **and** add it inline to `MEMORY.md` immediately.
2. Never create a duplicate — find and update the existing rule first.

The pattern: rules start as reference, get promoted when they're repeatedly needed inline. Browse `examples/shared/feedback_memory_escalation.md` for the full decision tree.

## Role boundaries

Ask: "Would this rule apply to every role I play on this project?"

- Yes → `shared/`
- No → the specific role's directory

Examples:
- "Never create a PR without running tests first" → `developer/` (only Developer opens PRs)
- "Always add a Created-by line to issue bodies" → `shared/` (all roles create issues)
- "Milestone names must follow the `i<N> - S<N> - <Name>` format" → `pm/` (only PM manages milestones)

## Symlinks

The `shared/` symlink inside each role folder (`developer/shared -> ../shared`) lets you reference shared memory files with a consistent relative path (`shared/feedback_X.md`) regardless of which role you're in. This path appears in drift annotations.

The `memory/` symlink in each project clone (`<project-clone>/memory -> ../claude-personas-<app>/<role>`) is what Claude Code reads at session start. It's created by `init-clone.sh`.

**Windows:** Symlink creation requires Developer Mode on Windows (Settings → Privacy & Security → Developer Mode). If you're on Windows without Developer Mode, use WSL.

## Getting started

See the [Quick start in README.md](README.md#quick-start-10-minutes-per-project) — `scripts/init-clone.sh` automates the clone creation + symlink wiring. Once a role is wired, open Claude Code in the role's clone and it auto-loads the matching `MEMORY.md`.

Then: browse `examples/` for patterns to adopt, and start writing rules into your role's `MEMORY.md` (in your memory repo, then commit and push).
