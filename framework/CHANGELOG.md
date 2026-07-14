# framework payload changelog

One entry per `framework/v*` tag: what breaks / what to do.
The payload = the file set declared in [FILES](FILES); instances consume it via `install.sh` against the recorded `framework_ref` pin.

## framework/v1.1.1 - 2026-07-14

Patch: role-tier hardening from the #71 whole-branch review (claude-personas#72, PR #74), plus the post-#71 executable-bit CI fix that the v1.1 tag predates.
doctor.sh: `role_source` git check accepts worktree/submodule checkouts (`.git` as a file); ALL trailing slashes stripped from `role_source` (double-slash symlink text permanently mismatched a clean link); per-role `<role>/user` discovery gated on the consumer's own `memory_layout=roles` with an `INFO:` line (on a flat consumer, root-level dirs are code - fix mode could materialize `user` symlinks into a stray dir carrying a MEMORY.md); target checks still run.
inject-subagent-role-pointer.sh: `shared`/`examples` agent types excluded, case-folded (APFS case-insensitivity resolved `Shared/MEMORY.md` to the top-level shared index).
Breaks: nothing.
Do: bump `framework_ref=framework/v1.1.1` and run `install.sh --sync`, then `doctor.sh`.

## framework/v1.1 - 2026-07-14

Adds the role@user tier (cross-project role memory, claude-personas#49, PR #71): optional `role_source` manifest key with validation + scoping, doctor "Role-tier readiness" checks, lazy fix-mode materialization of the `<role>/user` symlink, a conditional role@user pointer line in `inject-role-index.sh`, the NEW `inject-subagent-role-pointer.sh` SubagentStart hook (added to FILES), the load-persona-memory user hop, and the two-axis precedence chain in README.
Breaks: nothing - `role_source` is optional and the default is lazy; an instance without the key sees zero new findings and unchanged behavior.
Do: bump `framework_ref=framework/v1.1` and run `install.sh --sync`, then `doctor.sh`; add `role_source=../user-memory` only when wiring the role@user tier (the target must be a git repo with `memory_layout=roles`, so wire it after the user-memory migration).

## framework/v1 - 2026-07-07

First versioned payload: doctor.sh, memory_cliff.py, init-clone.sh, list-roles.sh, install.sh, inject-role-index.sh, the load-persona-memory skill.
Breaks: the payload moved out of `scripts/` and root `skills/` into `framework/`, and the wiring now expects the inject hook at `<instance>/.agents/hooks/lib/inject-role-index.sh`.
`install.sh` also maintains an install-owned state file, `.agents/framework-receipt` (landing path + blob oid per installed file, the dpkg `.list` / pip `RECORD` pattern), used for modified-detection and orphan tracking; commit it alongside the payload.
Do: run `install.sh --into <instance>` once (then `install.sh --sync` on updates), then `doctor.sh`; existing instances see MIGRATION.md "scripts/ -> framework/ layout".
