# Per-vendor caveats

Dated, verified sharp edges of the three supported tools.
Re-verify anything volatile before relying on it; each line carries the date it was last checked.

## Claude Code

- Does NOT read `AGENTS.md` natively (docs explicit; symlink or `@` import required). (2026-07-03)
- Scans only `.claude/skills`, not `.agents/skills`. (2026-07-03)
- Auto-memory reads the EXTERNAL `~/.claude/projects/<slug>/memory` path, not the in-repo `.claude/memory` (latent v3.1 gap: `init-clone.sh` before this sub-project never created the external symlink, and existing instances rode v2-era leftovers). Fixed: `init-clone.sh` now creates or repairs it. Live test 4 below records whether current CC still needs it. (2026-07-03)
- `<slug>` derivation is undocumented: absolute physical path with `/` and `.` each replaced by `-`. Live test 4 re-verifies. (2026-07-03)
- Symlink-hostile setups (e.g. Windows without developer mode): use the documented `autoMemoryDirectory` setting (absolute paths only, any settings scope) instead of the external symlink. (2026-07-03)

## Codex

- Trust is TWO-layer: per-repo trust, then per-hook-definition review via `/hooks`, re-triggered whenever the generated `.codex/hooks.json` changes. Neither is scriptable. (2026-07-03)
- The app does not load global `~/.codex/AGENTS.md` (openai/codex#27705, open); the CLI does. (2026-07-03)
- `additionalContext` ceiling: a ~2.4k-token truncation was observed 2026-07-02 on the cerebrum instance, but matches neither current docs nor current source (hook path uncapped in main; a sibling context path caps at 1k tokens). The inject script self-bounds its payload with a `[TRUNCATED ...]` trailer regardless. Live test 2 below records the current behavior. (2026-07-03)
- Hook timeouts are in seconds. (2026-07-03)
- Observed on macOS with codex-cli 0.142.5: `codex exec` (arg or stdin prompt, untrusted repo) returned the prompt text verbatim as the answer while burning ~12k tokens, alongside an unrelated MCP `HTTP 403` transport error - suspected local proxy/model misconfig (`model: gpt-5.5`, `reasoning effort: none`), not a Codex product behavior; re-test live tests 2-3 once resolved. (2026-07-04)

## OpenCode

- Repo moved orgs: `sst/opencode` -> `anomalyco/opencode`. (2026-07-03)
- Snapshot/undo cannot cover files behind a symlink (anomalyco/opencode#31984, open; the trigger is exactly the `.claude/x -> .agents/x` pattern). Git covers recovery. (2026-07-03)
- No local config variant (`opencode.local.json` does not exist; anomalyco/opencode#17232 open) - the per-clone fallback file is plain `opencode.json`, untracked via `.git/info/exclude`. (2026-07-03)
- Glob-through-symlink for `instructions` entries is gated on `follow: false` upstream behavior - live test 1 below decides the default wiring. (2026-07-03)

## Live-test results

Four named tests from the design spec (`docs/superpowers/specs/2026-07-03-per-vendor-adapters-template-design.md`, Verification).
Run on a throwaway scratch instance; nothing touches any real project.

| # | Question | Result | Date | Consequence |
|---|---|---|---|---|
| 1 | OpenCode glob-through-symlink on a relative global `instructions` entry | PASS (opencode 1.17.13): global relative entry loaded the role index through the `.agents/memory` symlink | 2026-07-04 | global one-time entry stays the default; `--opencode-per-clone` remains the documented fallback |
| 2 | Codex `additionalContext` ceiling | pending (blocked: interactive trust grant needed; `codex exec` also echoed prompts verbatim on this machine - see Codex section) | - | replaces the stale ~2.4k figure |
| 3 | Codex per-hook re-trust flow | pending (interactive-only by design; to be recorded at first real trust grant) | - | documents real onboarding friction |
| 4 | CC fresh-clone auto-load with ONLY the in-repo `.claude/memory` symlink (no external hop) + slug derivation | HOP IS LOAD-BEARING: without it the index did NOT load and CC materialized a real empty `memory/` dir at the slug (the predicted silent divergence); with it the index loaded; slug derivation verified byte-identical to `tr '/.' '-'` on the physical path | 2026-07-04 | `init-clone.sh` keeps creating/repairing the external hop; empty-dir replacement branch also verified live |
