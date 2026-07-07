# Example Skills

Skills are tier-3 guidance in the visibility ladder.
They are useful when a remembered preference has become an operational ritual with steps, trigger conditions, and verification.

Memory documents why the rule exists.
A skill carries how to run the workflow.
Keep both when the rationale matters: the memory gives the agent judgment, and the skill gives the agent procedure.

These examples are copy-once starter content.
They are not listed in `framework/FILES`, are not installed by `framework/tools/install.sh`, and are never synced by the framework updater.
Once copied into an instance, the instance owns them.

## Discovery By Tool

Claude Code discovers project skills from `.claude/skills/`.
In framework-managed instances, the doctor wires `.claude/skills` to the vendor-neutral `.agents/skills` directory when `skills_mount=true`.
Claude Code also supports project-scoped plugins as an optional side door, but plugins are Claude Code-only and do not carry the vendor-neutral framework payload.

Codex discovers skills from `.agents/skills/`.
The live probe in the framework distribution spec showed Codex can double-load same-name skills across tiers, so do not rely on tool precedence for collision handling.
The installer refuses framework skill collisions instead.

OpenCode discovers skills from `.agents/skills/` and also scans `.claude/skills/`.
The live probe showed OpenCode's same-name shadowing behavior differs from Claude Code and Codex.
Treat install-time collision refusal as the durable enforcement point.

## Included Examples

- `morning-routine/` - a PM warm-up skill triggered by a morning greeting.

## Production Reference

Use `framework/skills/load-persona-memory` as the production-grade reference.
It demonstrates a real framework-owned skill with role resolution, validation, read order, path rules, and governance.
The examples here are intentionally smaller and easier to copy.
