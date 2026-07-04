# Embedded-topology substrate (copy-and-adapt)

This directory carries the adapter set for the EMBEDDED topology: memory lives inside the same repo under `.agents/memory/`, and three thin vendor adapters point at it.
It is the pattern proven on the cerebrum instance (see the per-vendor caveats doc: `../../docs/vendor-caveats.md`).

## Which topology am I?

Boundary test: does a decision recorded in repo A change what an agent does in repo B?

- No - single-repo project: use THIS embedded layout (`.agents/` in the repo).
- Yes - multi-repo endeavor, or multiple concurrent role sessions: use the role-clones topology (`scripts/init-clone.sh` and a separate memory repo) instead.

## Files here

- `opencode.json` - copy to the repo root as-is (OpenCode adapter).
- `.codex/hooks.json` - copy, then replace `<ABSOLUTE-REPO-PATH>` with this clone's absolute path.
  Absolute paths make the file per-clone; regeneration tooling is sub-project 3.
  The `inject-memory-index.sh` script the placeholder command points at is the cerebrum instance's own embedded-topology script and is NOT shipped in this template.
  Either write your own SessionStart script that prints a `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}` envelope with your index content, or reuse this template's `scripts/inject-role-index.sh` pointed at your repo's `.agents/memory` directory (its shared-index half no-ops when `shared/MEMORY.md` is absent).
- `.claude/settings.json` - copy the `permissions.ask` stanza if you want write-prompts on executing artifacts.
  The spec's hook stanza is deliberately omitted here, same treatment as the symlinks below - hooks are instance-specific, and a committed hook path copied verbatim from another repo would silently point nowhere.

## Symlinks to create (not committed here - create them in YOUR repo)

Committed dangling symlinks confuse copiers and trip OpenCode's snapshot bug, so create these by hand or with your instance's sync script:

```bash
ln -s ../.agents/memory .claude/memory
ln -s ../.agents/skills .claude/skills   # only if you keep skills in .agents/skills/
ln -s AGENTS.md CLAUDE.md                # Claude Code does not read AGENTS.md natively
```

Payload layout expected by the adapters:

```text
.agents/memory/MEMORY.md      # always-loaded index
.agents/memory/<topic>.md     # one fact per file
.agents/hooks/                # hook scripts called by the adapters (single copy)
```
