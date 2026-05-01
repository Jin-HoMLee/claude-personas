# Conventions

Read this once to understand the system. Then close it and start writing rules.

## The mental model in one paragraph

`claude-personas` is a **memory-only repo** — you clone it once and never use
it as your project codebase. Inside it, each role (`developer/`, `pm/`,
`designer/`) is just a folder of memory files. Your **project repo** (the
codebase you actually work on) is separate. For each role you want to use, you
create one **project worktree** (e.g. `my-app/`, `my-app-pm/`) and configure
its `.claude/settings.local.json` to point `autoMemoryDirectory` at the
matching role folder inside your `claude-personas` clone. Claude then loads
the right `MEMORY.md` automatically depending on which project worktree you're
working in.

This separation is deliberate: you can use the same `claude-personas` clone
across many different project repos. Memory rules are about how *you* work,
not about any one codebase.

## The three-system split

Claude Code offers three places to give Claude persistent instructions:

| Layer | File | What goes here | Committed? |
|---|---|---|---|
| **Project facts** | `CLAUDE.md` (in your project repo) | Non-obvious codebase decisions, known gotchas, infra quirks, API behavior | Yes |
| **AI behavior rules** | Memory files (`MEMORY.md` + `feedback_*.md`, in this repo) | How Claude should behave: tone, habits, workflow rules, role-specific conventions | Yes (in this repo) |
| **Machine-specific** | `CLAUDE.local.md` (in each project worktree) | Absolute paths to memory directories, personal shortcuts, anything that differs per machine | No (gitignored) |

Keeping these separate prevents a common failure mode: hardcoding
machine-specific paths in your committed files, which breaks on other
machines or when the repo is shared.

## Why role-specific memory directories?

When you play multiple roles on a project (Developer on Monday, PM on
Tuesday, Designer on Wednesday), you want Claude to behave differently in
each context. The Developer should know your test conventions; the PM should
know your milestone format; neither should wade through the other's rules.

`autoMemoryDirectory` (a Claude Code setting) points Claude at a single
directory to load `MEMORY.md` from at session start. By giving each role its
own directory inside `claude-personas` — and giving each *project worktree*
its own `.claude/settings.local.json` pointing at the matching role folder —
Claude context-switches automatically when you switch project worktrees.

## The MEMORY.md two-tier structure

Each role's `MEMORY.md` has two sections:

### Always in effect

Rules inlined directly in the index file. Claude reads these without opening
any file — they're in `MEMORY.md` itself, which is auto-loaded every session.

**Use this tier for:** rules that must be applied on every turn regardless of
context. Examples: "never commit to main", "always add a role label to
issues", "use Read not cat".

**Drift annotations:** when you promote a rule from a reference file into
"Always in effect", add a comment showing where it came from:

```
- **My rule:** Don't do X, do Y instead. <!-- src: shared/feedback_my_rule.md -->
```

This lets you find and update the source file if the rule ever changes, and
prevents duplicate edits.

### Reference

Links to separate `feedback_*.md` files. Claude reads these only when the
linked topic is relevant to the current task.

**Use this tier for:** rules that apply in specific situations (git workflow,
PR process, testing conventions), detailed explanations with examples, rules
that are rarely needed.

## The escalation pattern

When Claude repeats a mistake you've already corrected:

1. Search for an existing memory on that topic across all memory files.
   - Found in "Always in effect" → rule already fires at session start;
     rewrite it to be more specific or actionable.
   - Found only behind a link → **promote it**: copy the rule inline into the
     role's `MEMORY.md` under "Always in effect", add a drift annotation.
   - Not found anywhere → create a new `feedback_<topic>.md` **and** add it
     inline to `MEMORY.md` immediately.
2. Never create a duplicate — find and update the existing rule first.

The pattern: rules start as reference, get promoted when they're repeatedly
needed inline. Browse `examples/shared/feedback_memory_escalation.md` for the
full decision tree.

## Role boundaries

Ask: "Would this rule apply to every role I play on this project?"

- Yes → `shared/`
- No → the specific role's directory

Examples:
- "Never create a PR without running tests first" → `developer/` (only Developer opens PRs)
- "Always add a Created-by line to issue bodies" → `shared/` (all roles create issues)
- "Milestone names must follow the `i<N> - S<N> - <Name>` format" → `pm/` (only PM manages milestones)

## Symlinks

The `shared/` symlink inside each role folder (`developer/shared → ../shared`)
lets you reference shared memory files with a consistent relative path
(`shared/feedback_X.md`) regardless of which role directory you're in. This
path appears in drift annotations.

**Windows:** Git symlinks require Developer Mode on Windows (Settings →
Privacy & Security → Developer Mode). If you're on Windows without Developer
Mode, create a `shared/` folder inside each role directory and copy files
there instead of symlinking. The rest of the system works identically.

## CLAUDE.local.md per project worktree

Each project worktree has its own `CLAUDE.local.md` (gitignored in your
project repo) that stores the absolute path to the role's memory directory
inside `claude-personas`. This solves a chicken-and-egg problem: the role's
`MEMORY.md` can reference `shared/MEMORY.md` by relative path, but to *read
the role's MEMORY.md itself*, Claude needs an absolute path — and that path
is machine-specific.

Example `CLAUDE.local.md` for the Developer project worktree:

```markdown
# Local context — not committed

Memory directory for this session:
/Users/you/projects/claude-personas/developer/
```

The role's `MEMORY.md` "Always in effect" section instructs Claude to read
this file for the absolute path before doing anything else.

## Getting started

1. Click **Use this template** on GitHub → create your `claude-personas` repo
   and clone it once to your machine
2. Read this file once
3. For each project worktree where you want a role active:
   - Copy `settings.local.json.example` → `.claude/settings.local.json` in
     that *project worktree* (not inside claude-personas), and update
     `autoMemoryDirectory` to the absolute path of the matching role folder
     inside your claude-personas clone
   - Create a `CLAUDE.local.md` in the same project worktree (gitignored)
     with the same absolute path
4. Open Claude Code in that project worktree → it auto-loads the right
   `MEMORY.md`
5. Browse `examples/` for patterns to adopt into your `feedback_*.md` files
6. Start writing rules into your role's `MEMORY.md` (in your claude-personas
   clone, then commit and push)
