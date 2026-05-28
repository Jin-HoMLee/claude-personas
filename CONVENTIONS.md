# Conventions

Read this once to understand the system. Then close it and start writing rules.

## The mental model in one paragraph

`claude-personas` is a **memory-only repo** — you fork it once per project (`claude-personas-<my-app>`) and never use it as your project codebase. Inside it, each role (`developer/`, `pm/`, `designer/`, `scientist/`) is just a folder of memory files.

Your **project repo** (the codebase you actually work on) is separate. For each role you want to use, you create one **independent project clone** at a sibling path (`my-app/`, `my-app-pm/`, etc.). Each project clone has a single `.claude/memory/` symlink pointing into the matching role folder of the memory repo. Claude Code auto-loads the right `MEMORY.md` based on which clone you're working in.

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

Each role gets its own project clone (and so its own Claude Code auto-memory hash dir). The `.claude/memory/` symlink in that clone resolves to the role-specific folder in the memory repo. Claude context-switches automatically when you open a different clone — no settings to configure inside the clone, no per-session flags.

## The visibility ladder — four tiers, not two

Claude Code offers four mechanisms for delivering persistent instructions to Claude. Each has a different cost / firing semantics / attribution profile. Pick the right tier for the rule's shape.

| Tier | Mechanism | Loaded when… | Cost | Fires |
|---|---|---|---|---|
| **1. Always-loaded** | Inline rules in `MEMORY.md` "Always in effect" | Every session, every turn | Tokens on every turn | Probabilistic (Claude reads + decides) |
| **2. Index + lazy** | Links from `MEMORY.md` "Reference" → `feedback_*.md` files | Only when Claude opens the linked file | Tokens only when topic surfaces | Probabilistic |
| **3. On-demand** | Skills + slash commands (invoked by trigger phrase or user action) | Only when invoked | Tokens only when invoked | Free invocation telemetry (you can grep JSONL to see when it fired) |
| **4. Harness-deterministic** | Hooks (PreToolUse, PostToolUse, SessionStart, …) in `settings.json` | On every matched harness event | Zero tokens | **Guaranteed** firing — harness enforces, Claude cannot ignore |

The asymmetric cost is the key insight: **tier 1 burns tokens every turn even when the rule isn't relevant**. Tiers 2–4 are cost-only-when-firing. The smaller you keep tier 1, the more reliably Claude follows the rules that genuinely belong there.

### Size budgets for tier 1 (Always in effect)

Compliance starts to degrade past these thresholds — Claude reads later rules less reliably, mixes related rules together, and over-applies generic ones. Rough cliffs from internal audit:

- ≤ **14 inline rules** in a given session's combined load (role + shared)
- ≤ **200 lines** total for "Always in effect"
- ≤ **4000 tokens** of always-loaded rules

These are **binding past first cliff**, not from session zero. Growing a memory directory organically over weeks naturally hits the first cliff before you've built enough material to need a four-tier structure. When you do hit it: audit, demote where possible, then re-grow.

### Tier 1 — Always in effect

Inline rules in `MEMORY.md`. Auto-loaded every session, no file read needed.

**Use for:** ambient defaults (tone, style), identity priors ("you're the PM, not the developer"), cross-cutting rules with no specific trigger ("link to file path:line when referencing code"), and the index function itself (one-line pointers to deeper material).

**Drift annotations:** when you promote a rule from a reference file into "Always in effect", add a comment showing where it came from:

```text
- **My rule:** Don't do X, do Y instead. <!-- src: shared/feedback_my_rule.md -->
```

This lets you find and update the source file if the rule ever changes, and prevents duplicate edits.

### Tier 2 — Reference (index + lazy)

Links from `MEMORY.md` to separate `feedback_*.md` files. Claude reads these only when the linked topic surfaces.

**Use for:** rules that apply in specific situations (git workflow, PR process, testing conventions), detailed explanations with examples, rules that are rarely needed.

### Tier 3 — Skills + slash commands (on-demand)

Trigger-phrase-invoked rules. The user (or Claude on their own initiative) types `/<skill>` or says a registered phrase ("good morning", "consolidate my memory"); the skill loads and runs.

**Use for:** session-mode workflows (morning routine, end-of-day handoff), multi-step procedures with branching ("triage these PRs", "write a code review"), and recurring rituals that benefit from a checklist rather than always-loaded context.

Skills give **free invocation telemetry**: you can grep JSONL to see when each fired, which makes audit cheap. See [Claude Code's skill docs](https://docs.claude.com/en/docs/claude-code/skills) for the registration format.

### Tier 4 — Hooks (harness-deterministic)

`settings.json` config. The harness runs your shell command on every matched event (e.g., every Bash invocation, every Edit on a path matching a pattern). Your script decides allow/block based on the input.

**Use for:** rules with a **discrete trigger** and **high cost of violation**:

- "Never `git push --force`" → PreToolUse Bash matcher on `git push.*--force`
- "Never `cd` out of the repo" → PreToolUse Bash matcher on `cd <path>`
- "Lab notebook entries are immutable once dated" → PreToolUse Edit matcher on `lab_notebook.md`

Hooks fire deterministically — Claude cannot drift past them. They cost zero tokens until they fire. See [`examples/hooks/`](examples/hooks/) for starter configs.

### Deciding which tier

Ask, in order:

1. **Does the rule have a discrete trigger** (a specific Bash command, a specific file edit)?
   - Yes → **tier 4 (hook)** — harness enforces it for free, even when context isn't loaded
2. **Does the rule belong to a session-mode workflow** ("good morning", "triage", "handoff")?
   - Yes → **tier 3 (skill)** — invoked when the mode starts, doesn't burn tokens between
3. **Does the rule apply in specific situations only** (only on PRs, only when writing tests)?
   - Yes → **tier 2 (reference)** — Claude opens it when the situation surfaces
4. **Does the rule apply on every turn regardless of context** (style, identity, cross-cutting defaults)?
   - Yes → **tier 1 (always-loaded)** — but budget carefully; this is the most expensive tier

The default answer should be tier 2 or 3, not tier 1. Tier 1 is for rules that genuinely need to fire even when nothing in the conversation has surfaced them yet.

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

The `.claude/memory/` symlink in each project clone (`<project-clone>/.claude/memory -> ../../claude-personas-<app>/<role>`) is what Claude Code reads at session start. It's created by `init-clone.sh`.

**Windows:** Symlink creation requires Developer Mode on Windows (Settings → Privacy & Security → Developer Mode). If you're on Windows without Developer Mode, use WSL.

## Getting started

See the [Quick start in README.md](README.md#quick-start-10-minutes-per-project) — `scripts/init-clone.sh` automates the clone creation + symlink wiring. Once a role is wired, open Claude Code in the role's clone and it auto-loads the matching `MEMORY.md`.

Then: browse `examples/` for patterns to adopt, and start writing rules into your role's `MEMORY.md` (in your memory repo, then commit and push).
