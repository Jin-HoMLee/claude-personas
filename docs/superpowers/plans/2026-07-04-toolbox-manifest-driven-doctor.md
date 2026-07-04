# Toolbox: Manifest-Driven Doctor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One manifest-driven `scripts/doctor.sh` covering the three substrate topologies (role-clone constellation, embedded, user tier), plus `memory_cliff.py` flat-layout support, per the approved spec `docs/superpowers/specs/2026-07-04-toolbox-manifest-driven-doctor-design.md` (issue #42, spec sub-issue #45 closed by PR #44).

**Architecture:** Each instance declares what it has in a committed `.agents/manifest` (flat `key=value`, never sourced, unknown key = hard error); `doctor.sh` reads it and dispatches to a per-topology check catalog built on a shared `need_link` core. Fix mode is the default and repairs only what is derivable (symlinks, generated `.codex/hooks.json` / per-clone `opencode.json`, dangling external-hop orphans); everything owned (`settings.json`, global OpenCode config, real files at link paths) is report-only with exact guidance. `--check` reports without changing anything; `--init <topology>` writes a starter manifest; a missing or invalid manifest refuses with exit 2 and no shape guessing.

**Tech Stack:** bash (macOS bash 3.2 compatible - no associative arrays), jq (check-time dependency only, degraded loudly when absent), Python 3 stdlib (`memory_cliff.py`), the existing `scripts/tests/` bash harness (`test_helpers.sh`, `run_all.sh`, pytest for `test_memory_cliff.py`, CI via `.github/workflows/validate.yml`).

## Global Constraints

- Spec is the contract: `docs/superpowers/specs/2026-07-04-toolbox-manifest-driven-doctor-design.md`. Deviations must be surfaced in the PR description.
- Output vocabulary is exactly `DRIFT:` / `FIXED:` / `ERROR:` / final `OK:` (grep-compatible with the two proven sync.sh scripts). Exit codes: 0 clean, 1 drift or error, 2 missing/invalid manifest.
- The doctor never touches a real (non-symlink) file or directory: DRIFT, skip, continue - one refusal must not hide others (`set -u`, no `set -e`).
- The orphan sweep removes DANGLING symlinks only; live symlinks and real directories under `~/.claude/projects/` are never modified.
- Every `$HOME`-relative path goes through `$HOME` so tests can override it; no test may touch the real home (grep every doctor invocation in tests for a `HOME=` override).
- No changes to the splice instance; adoption swaps for cerebrum and user-memory are follow-ups, not part of this PR.
- Skills distribution is #43's concern: the doctor checks the `.claude/skills` symlink only when `skills_mount=true` is declared, nothing more.
- Commit prefix `claude-personas: ...`, one commit per task, never chain commit and push, no agent co-author line.
- All new/changed scripts stay executable (CI checks `-x`) and `bash scripts/tests/run_all.sh` is green at every commit.
- Long Markdown files: one sentence per physical line; plain dash, never an em dash.

## File Structure

- `scripts/doctor.sh` - NEW. The manifest-driven doctor (arg parsing, manifest parser, shared core, three topology catalogs, orphan sweep).
- `scripts/memory_cliff.py` - MODIFY. `--layout roles|flat` flag, manifest read, flat-layout corpus.
- `scripts/tests/test_helpers.sh` - MODIFY. New fixtures `make_embedded_fixture`, `make_user_tier_fixture` (constellation reuses `make_clone_test_fixture` + `init-clone.sh`).
- `scripts/tests/test_doctor_manifest.sh` - NEW. Refusal, `--init`, parser strictness.
- `scripts/tests/test_doctor_user_tier.sh` - NEW.
- `scripts/tests/test_doctor_embedded.sh` - NEW.
- `scripts/tests/test_doctor_role_clones.sh` - NEW. Includes multi-candidate flag and orphan sweep.
- `scripts/tests/test_memory_cliff.sh` / `test_memory_cliff.py` - MODIFY. Flat-layout coverage.
- `README.md` - MODIFY. "Doctor" section (manifest convention, per-topology usage, fix-vs-report principle).
- `.github/workflows/validate.yml` - MODIFY. Add `scripts/doctor.sh` + new test files to the executable check.

Task order: the manifest layer first (everything dispatches off it), then topologies simplest-to-hardest (user tier -> embedded -> constellation), then the two backlog checks that live inside the constellation walk, then `memory_cliff.py`, docs, live smoke.

---

### Task 1: `doctor.sh` skeleton - CLI, manifest parser, refusal, `--init`

**Files:**
- Create: `scripts/doctor.sh`
- Create: `scripts/tests/test_doctor_manifest.sh`
- Modify: `.github/workflows/validate.yml` (executable list)

**Interfaces:**
- Consumes: `$1..$n` (`--check`, `--root PATH`, `--init <topology>`), `$root/.agents/manifest`.
- Produces: globals `CHECK`, `ROOT`, `TOPOLOGY`, `MEMORY_LAYOUT`, `ADAPTERS`, `CLAUDE_HOOKS`, `CODEX_HOOKS`, `SKILLS_MOUNT`, `OPENCODE_MODE` for Tasks 2-8; `manifest_get <key>` / `manifest_get_all <key>` line-oriented readers (grep/cut, never `source`).

- [ ] **Step 1: Write the failing test** (`test_doctor_manifest.sh`, chmod +x): no manifest -> stderr names all three topologies + `--init`, exit 2; `--init embedded` writes `.agents/manifest` that immediately re-parses (`--check` proceeds past manifest stage); `--init` onto an existing manifest refuses (exit 2, file unchanged); unknown `topology=`, unknown key `frobnicate=1`, `manifest_version=99`, and a missing required key each refuse with exit 2 naming the offender; `key = value` with spaces around `=` is invalid (strict `key=value`); `#` comments and blank lines are ignored.
- [ ] **Step 2: Run to verify it fails** (script does not exist).
- [ ] **Step 3: Implement** the skeleton: arg parse; `--init` writes a commented starter per topology (required keys filled, optional keys commented out); manifest reader = `grep -v '^[[:space:]]*#' | grep .` line loop validating each line against `^[a-z_]+=[^[:space:]]` and a per-key whitelist (values validated per key: enumerations for `topology`/`memory_layout`/`opencode`/`skills_mount`, `1` for `manifest_version`, path-shaped for hooks); collect into globals; refusal text is static (never inspects repo shape). Topology dispatch stubs call `topology_<name>_checks` (empty for now) then print `OK:` and exit 0.
- [ ] **Step 4: Run to verify it passes**; `bash scripts/tests/run_all.sh` green.
- [ ] **Step 5: Add `scripts/doctor.sh` + test file to CI's executable check; commit** `claude-personas: doctor.sh skeleton - manifest parser, refusal, --init starters`.

---

### Task 2: Shared check core

**Files:**
- Modify: `scripts/doctor.sh`

**Interfaces:**
- Produces: `need_link <path> <target> <label>` (the user-memory variant: `mkdir -p` parent in fix mode; never touches a real file); `drift`/`fixed` counters; `report_drift <msg>` / `report_fixed <msg>` / `report_error <msg>`; `require_jq <what-for>` (DRIFT + skip-loudly when absent); payload sanity `check_payload` (flat: `$ROOT/.agents/memory/MEMORY.md` exists; roles: every role dir has `MEMORY.md`, `shared/MEMORY.md` exists); `check_hook_scripts` (each declared hook exists + executable).

- [ ] **Step 1: Failing tests** - fold into `test_doctor_manifest.sh` a minimal-fixture block: a valid manifest whose payload is missing -> `DRIFT:` + exit 1 in `--check`; jq PATH-masked run (`PATH` without jq) -> named DRIFT, other checks still run.
- [ ] **Step 2: Verify RED.**
- [ ] **Step 3: Implement** (lift `need_link` from `user-memory/tools/sync.sh`, superset semantics per spec).
- [ ] **Step 4: Verify GREEN + suite; commit** `claude-personas: doctor.sh shared check core (need_link, payload sanity, loud jq degradation)`.

---

### Task 3: User-tier topology

**Files:**
- Modify: `scripts/doctor.sh` (`topology_user_tier_checks`)
- Modify: `scripts/tests/test_helpers.sh` (`make_user_tier_fixture <tmp>`: repo dir with `AGENTS.md` + `.agents/memory/MEMORY.md` + manifest, plus a fixture `$tmp/home`)
- Create: `scripts/tests/test_doctor_user_tier.sh`

**Checks (each gated on its `adapter=` declaration):** `~/AGENTS.md -> $ROOT/AGENTS.md`; `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md` each `-> $HOME/AGENTS.md`; payload sanity.

- [ ] **Step 1: Failing tests** - clean fixture `--check` exits 0; drift injections one at a time (missing home hop, wrong-target adapter link, REAL file at `~/.claude/CLAUDE.md`): each named + exit 1; fix mode repairs the first two (`FIXED:`), refuses the real file (still DRIFT); re-`--check` after fix = clean except the real-file DRIFT; an undeclared adapter (manifest without `adapter=codex`) is not checked.
- [ ] **Step 2-4: RED, implement, GREEN + suite; commit** `claude-personas: doctor.sh user-tier topology checks with fixture tests`.

---

### Task 4: Embedded topology

**Files:**
- Modify: `scripts/doctor.sh` (`topology_embedded_checks`)
- Modify: `scripts/tests/test_helpers.sh` (`make_embedded_fixture <tmp>`: repo with `.agents/memory/MEMORY.md`, `.agents/hooks/*.sh`, `AGENTS.md`, adapter files, manifest; fixture `$tmp/home`)
- Create: `scripts/tests/test_doctor_embedded.sh`

**Checks (generalizing cerebrum's `sync.sh`):** in-repo links `.claude/memory -> ../.agents/memory`, `CLAUDE.md -> AGENTS.md`, `.claude/skills -> ../.agents/skills` iff `skills_mount=true` (all fixable); every `claude_hook` wired in `.claude/settings.json` via the exact `"$CLAUDE_PROJECT_DIR/<hook>"` string (report-only, jq); `.codex/hooks.json` wires every `codex_hook` with `'$ROOT/<hook>'` absolute exact-match, regenerated wholesale in fix mode (same JSON shape as cerebrum's, one entry per declared hook, order = manifest order); root `opencode.json` `instructions` contains `.agents/memory/MEMORY.md` (report-only, exact guidance line); external CC hop `$HOME/.claude/projects/<slug>/memory` resolving to `$ROOT/.agents/memory` (slug = `printf '%s' "$root_abs" | tr '/.' '-'`... verify against `compute_hash` in `test_helpers.sh` and reuse its rule; fixable; real directory = report-only reconcile-by-hand).

- [ ] **Step 1: Failing tests** - clean fixture 0; drifts one at a time: deleted `.claude/memory`, wrong `CLAUDE.md` target, stale absolute path in `.codex/hooks.json` (another machine's prefix - the substring-accept trap must FAIL it), settings.json missing a declared `claude_hook`, `opencode.json` without the entry, missing external hop, REAL dir at the external hop with content; each named + exit 1; fix repairs links + regenerates `.codex/hooks.json` + creates the hop; re-`--check` leaves only the report-only DRIFTs (settings, opencode, real dir); real-dir content untouched.
- [ ] **Step 2-4: RED, implement, GREEN + suite; commit** `claude-personas: doctor.sh embedded topology checks (cerebrum sync.sh generalized)`.

---

### Task 5: Constellation topology - role walk + mounts

**Files:**
- Modify: `scripts/doctor.sh` (`topology_role_clones_checks`: role discovery + candidate walk + per-workspace mount checks)
- Create: `scripts/tests/test_doctor_role_clones.sh` (fixture = `make_clone_test_fixture` + real `init-clone.sh` wiring incl. `--self`, `HOME` overridden)

**Checks per role dir (role dirs = template rule: `MEMORY.md` present, not `shared`/`examples`):** candidate walk in `list-roles.sh` order (memory repo self-mount, no-suffix clone, suffixed clone); for each workspace claiming the role: `.agents/memory` mount target correct (`../<role>` self-mount, `../../<memory-repo>/<role>` clones; fixable), `.claude/memory -> ../.agents/memory` hop (fixable), `.git/info/exclude` carries the init-clone-owned entries (fixable: append missing); a role with zero workspaces is informative (`no workspace wired`), not DRIFT - an unwired role is a valid state, matching `list-roles.sh` "missing".

- [ ] **Step 1: Failing tests** - wire developer (no-suffix) + pm (suffix) + `--self` MM via `init-clone.sh`; add manifest to the memory repo; clean `--check` = 0; drifts: deleted mount in the pm clone, repointed hop in the developer clone, stripped exclude line; each named + exit 1; fix repairs all three; re-`--check` clean.
- [ ] **Step 2-4: RED, implement, GREEN + suite; commit** `claude-personas: doctor.sh constellation role walk + mount checks`.

---

### Task 6: Constellation vendor wiring - external hops, Codex, OpenCode

**Files:**
- Modify: `scripts/doctor.sh`
- Modify: `scripts/tests/test_doctor_role_clones.sh`

**Checks per wired workspace:** external CC hop for that clone's slug resolving through its `.claude/memory` (fixable; real-dir = report-only); `.codex/hooks.json` command is exactly `'<memory-repo-abs>/scripts/inject-role-index.sh' '<role-dir-abs>'` (regenerable in fix mode, reusing `init-clone.sh`'s generation shape); OpenCode per declared mode: `per-clone` = generated `opencode.json` absolute path correct (regenerable), `global` = `~/.config/opencode/opencode.json` `instructions` contains the relative entry (report-only, exact line printed; jq-gated).

- [ ] **Step 1: Failing tests** - drifts: dangling external hop for the developer clone, `.codex/hooks.json` pointing at a copied-from-elsewhere memory repo path, `opencode=global` with a fixture `$HOME/.config/opencode/opencode.json` lacking the entry; each named; fix repairs hop + regenerates hooks.json; the global OpenCode DRIFT survives as report-only with the exact `instructions` line in the message.
- [ ] **Step 2-4: RED, implement, GREEN + suite; commit** `claude-personas: doctor.sh constellation vendor wiring checks`.

---

### Task 7: Multi-candidate role workspace flag

**Files:**
- Modify: `scripts/doctor.sh`, `scripts/tests/test_doctor_role_clones.sh`

The walk in Task 5 stops at the first candidate (list-roles behavior); this task makes it exhaustive: collect ALL candidates whose mount (either hop generation) resolves to the role, and DRIFT when more than one claims it, naming every path (report-only in both modes; the doctor never auto-picks - retiring a workspace is a human decision, spec decision log).

- [ ] **Step 1: Failing test** - wire MM via `--self`, then plant a stale pre-#40-style suffixed `<project>-memory_manager` clone with a direct v3.1 symlink to `memory_manager/`; `--check` names BOTH paths under one DRIFT; fix mode changes nothing about it; exit stays 1.
- [ ] **Step 2-4: RED, implement, GREEN + suite; commit** `claude-personas: doctor.sh flags multi-candidate role workspaces (report-only)`.

---

### Task 8: External-hop orphan sweep

**Files:**
- Modify: `scripts/doctor.sh`, `scripts/tests/test_doctor_role_clones.sh`

Scan `$HOME/.claude/projects/*/memory`: a symlink whose resolved target does not exist is an orphan -> DRIFT naming slug + dead target; fix mode `rm`s the symlink only (`FIXED:`), never the slug dir's other content. Live symlinks (target exists, wherever they point) and real directories are never modified. Runs for the constellation topology (where clone moves produce them); embedded gets the same sweep for its single hop's stale siblings.

- [ ] **Step 1: Failing tests** - fixture `$HOME` with: a dangling `projects/<old-slug>/memory` (the moved-clone signature), a live hop for the developer clone, a real directory with a file under another slug, and an unrelated live symlink; `--check` names exactly the dangling one + exit 1; fix removes it, leaves the other three byte-identical; re-`--check` clean.
- [ ] **Step 2-4: RED, implement, GREEN + suite; commit** `claude-personas: doctor.sh external-hop orphan sweep (dangling-only removal)`.

---

### Task 9: `memory_cliff.py` flat layout

**Files:**
- Modify: `scripts/memory_cliff.py`, `scripts/tests/test_memory_cliff.py`, `scripts/tests/test_memory_cliff.sh`

**Interfaces:**
- Consumes: `--layout roles|flat` (new), `$root/.agents/manifest` `memory_layout` (new, flag wins), existing `--root`/baseline flags.
- Produces: flat corpus = the single file `.agents/memory/MEMORY.md`, whole file counted as tier-1 (flat adapters inject the entire index; there is no always-section split to apply); role math, cliffs (14/200/~4000), baseline/ratchet unchanged. Precedence: `--layout` > manifest > current role discovery (template + splice keep working with zero changes).

- [ ] **Step 1: Failing tests** (pytest + bash): flat fixture via flag -> one "role" row (label `index`), whole-file rule/line/token counts, over-cliff flat file exits 1; manifest-driven flat (no flag) same result; manifest present + `--layout roles` overrides; no manifest + no flag = existing behavior (existing tests must stay green untouched); flat + missing index file = clear error.
- [ ] **Step 2-4: RED, implement, GREEN (pytest + `bash scripts/tests/run_all.sh`); commit** `claude-personas: memory_cliff.py flat-layout support (manifest-aware, --layout override)`.

---

### Task 10: README + starter-manifest docs

**Files:**
- Modify: `README.md`

New "Doctor" section: the manifest convention (location, syntax, key table from the spec), per-topology quickstart (`--init` then `doctor.sh`), fix-vs-report principle, exit codes, what is deliberately NOT checked (Codex trust grants, skills distribution -> #43). One sentence per line.

- [ ] **Step 1: Write; verify all `--init` starter contents shown in the README match what `doctor.sh --init` actually emits (extract-and-diff in `test_doctor_manifest.sh` if drift-prone, else eyeball); commit** `claude-personas: README doctor section (manifest convention, per-topology usage)`.

---

### Task 11: Live smoke (verify by running, read-only)

No repo changes expected; findings feed back into spec/implementation before the PR merges.

- [ ] **Step 1:** Hand-write `.agents/manifest` for the real cerebrum checkout (topology=embedded, its two hooks, skills_mount=true) UNCOMMITTED; run `doctor.sh --check --root ~/dev/GitHub/Jin-HoMLee/cerebrum`; expect clean (cerebrum's own sync.sh --check is the cross-oracle). Delete the manifest afterward (adoption is a follow-up).
- [ ] **Step 2:** Same for user-memory (topology=user-tier); cross-oracle = its `tools/sync.sh --check`.
- [ ] **Step 3:** Scratch constellation (throwaway dirs, real `init-clone.sh`): clean check, then a real drift (move a clone dir) -> orphan sweep + re-wire cycle end-to-end with fix mode.
- [ ] **Step 4:** Record results (PASS/FAIL per run + any surprises) in the PR description; any finding that contradicts the spec gets fixed here and noted as a deviation.

---

### Task 12: Final verify + PR

- [ ] **Step 1:** `bash scripts/tests/run_all.sh` + pytest green; grep audit: every doctor invocation in tests has `HOME=` override; CI executable list complete.
- [ ] **Step 2:** Re-read the #42 acceptance criteria against the delivered behavior, checkbox by checkbox (issue body, not title).
- [ ] **Step 3:** Push branch; PR `Closes #42` (dev-linked branch does this anyway; keyword makes it explicit), body = AC traceability + live-smoke results + deviations; request bot review via `@claude` comment.
