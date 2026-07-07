# framework payload changelog

One entry per `framework/v*` tag: what breaks / what to do.
The payload = the file set declared in [FILES](FILES); instances consume it via `install.sh` against the recorded `framework_ref` pin.

## framework/v1 - 2026-07-07

First versioned payload: doctor.sh, memory_cliff.py, init-clone.sh, list-roles.sh, install.sh, inject-role-index.sh, the load-persona-memory skill.
Breaks: the payload moved out of `scripts/` and root `skills/` into `framework/`, and the wiring now expects the inject hook at `<instance>/.agents/hooks/lib/inject-role-index.sh`.
`install.sh` also maintains an install-owned state file, `.agents/framework-receipt` (landing path + blob oid per installed file, the dpkg `.list` / pip `RECORD` pattern), used for modified-detection and orphan tracking; commit it alongside the payload.
Do: run `install.sh --into <instance>` once (then `install.sh --sync` on updates), then `doctor.sh`; existing instances see MIGRATION.md "scripts/ -> framework/ layout".
