---
name: Team structure
description: Role definitions for all Claude sessions and triggers for adding new roles
type: feedback
---

The user (Lead) runs multiple Claude sessions with distinct roles.

**Project Manager session** — board maintenance, milestone tracking, issue triage, roadmap
- Manages the project board
- Sets/moves issue status; does NOT touch code or domain deliverables
- Sole owner of milestone assignment — only PM assigns, creates, renames, or closes milestones

**Developer session** — implementation, testing, code
- Edits source code, config, CI
- Updates technical documentation after changes are implemented

**Scientist / Researcher session** (if applicable) — domain analysis, methodology, research output
- Does NOT touch code; documents design decisions and hands off to Developer
- Edits research documents, notebooks, methodology files

**Why:** keeps domain rationale separate from implementation details; allows each session
to have focused context without rule interference from other roles.

**How to apply:** when in a Scientist session, do not edit code even if the design is
fully specified. Document the design and post a standup message asking Developer to implement.

## Memory directory layout

```
<your-memory-repo>/<your-project>/
├── shared/         ← cross-role memories
├── developer/      ← Developer-role memories
│   └── shared → ../shared
├── pm/             ← PM-role memories
│   └── shared → ../shared
└── scientist/      ← Scientist-role memories (optional)
    └── shared → ../shared
```

Each role's worktree sets `autoMemoryDirectory` to its matching role folder.
The `<role>/shared` symlink lets every role read shared memories with a consistent
relative path. Note: `<your-memory-repo>` can be the same repo as your project,
or a separate (often private) memory-only repo — both work.

## Git worktree layout

Each role works in its own git worktree:

| Role | Working directory |
|---|---|
| Developer | `<project>/` (main repo) |
| PM | `<project>-pm/` |
| Scientist | `<project>-scientist/` |

**Setup (run once from the main repo):**
```bash
git worktree add ../<project>-pm -b pm/workspace
git worktree add ../<project>-scientist -b research/workspace
```

## Adding new roles

Create a new folder (`<role>/`), add a `MEMORY.md` stub, and create a symlink:
`(cd <role> && ln -s ../shared shared)`. Then create a new worktree and point its
`autoMemoryDirectory` at the new folder.
