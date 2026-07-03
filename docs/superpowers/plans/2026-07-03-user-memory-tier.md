# User-Memory Tier + Splice Knowledge Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the private `Jin-HoMLee/user-memory` substrate instance, wire it into all three tools' native global tiers, and migrate the portable slice of splice-gained knowledge into it.

**Architecture:** Standard substrate layout (`.agents/memory/` + `MEMORY.md` index) in a new private repo cloned to a fixed path.
The canonical global instruction file `~/AGENTS.md` (which already exists, with `~/.claude/CLAUDE.md` symlinked to it) moves into the repo and is symlinked back, so the user tier becomes version-controlled.
Codex and OpenCode get the same symlink treatment at their native global paths.
Content arrives via a human-gated triage of the splice memory repo, adapt-not-copy with provenance lines.

**Tech Stack:** bash (sync script), GitHub CLI, Markdown memory files, `claude-personas/scripts/memory_cliff.py` for the budget lint.

**Tracking:** [claude-personas#30](https://github.com/Jin-HoMLee/claude-personas/issues/30), sub-project #6 of epic #27.
**Spec:** `docs/superpowers/specs/2026-07-02-knowledge-consolidation-two-module-design.md`.

## Global Constraints

- Always-loaded user-tier content stays lean: target <= ~120 lines across everything the adapters inject (web-verified instruction budget: models follow ~150-200 instructions per context; CC's system prompt uses ~50).
- Adapt, not copy: every migrated memory file carries a provenance line `**Source:** <splice-path> @ <short-sha>, adapted 2026-07-03.` and is rewritten to generic form.
- The splice memory repo (`claude-personas-splice-neoepitope-pipeline`) is READ-ONLY for this work; MM is sole committer. Dedup candidates are handed over via issue, never committed by us.
- Tier precedence is role > project > user, by convention; verified by a live conflict test (Task 8).
- Every adapter wiring is verified by running the actual tool, not by static reading (spec #1 precedent, `feedback_review_by_running`).
- The sync script never touches a real (non-symlink) file: report DRIFT and skip (cerebrum `sync.sh` precedent).
- Commit prefix in the new repo: `user-memory:`. In claude-personas: `claude-personas:`. Plain dash only, no em dash. No agent co-author lines.
- Fixed clone path: `/Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory` (referred to as `$UM` below).

## Discovered baseline (verified 2026-07-03, this machine)

- `~/AGENTS.md` exists: Jin-Ho's canonical global instructions (1708 bytes).
- `~/.claude/CLAUDE.md` is already a symlink -> `/Users/jin-holee/AGENTS.md` (created 2026-06-24).
- `~/.codex/AGENTS.md` is a REAL FILE, byte-identical copy of `~/AGENTS.md` (drift risk; last touched 2026-07-01).
- `~/.config/opencode/AGENTS.md` does not exist; `~/.config/opencode/opencode.json` exists (marginalia MCP only, no `instructions` key).
- `~/OPINIONS.md` and `~/VOICE.md` do NOT exist, although `~/AGENTS.md` references both. Spec's "pointer entries to them" assumption is void -> Task 6 gate question.
- Splice memory clone at `/Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline` (referred to as `$SPLICE`): 90 files in `shared/`, role dirs `developer/ pm/ scientist/ memory_manager/`.

---

### Task 1: Create the user-memory repo with substrate skeleton

**Files:**
- Create: `$UM/.agents/memory/MEMORY.md`
- Create: `$UM/README.md`

**Interfaces:**
- Produces: private repo `Jin-HoMLee/user-memory` cloned at `$UM`; index at `$UM/.agents/memory/MEMORY.md` (all later tasks reference these exact paths).

- [ ] **Step 1: Create and clone the repo**

```bash
gh repo create Jin-HoMLee/user-memory --private --description "Jin-Ho's user-tier agent memory (agent-personas substrate instance)"
git clone git@github.com:Jin-HoMLee/user-memory.git /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
```

Expected: empty clone at `$UM`.

- [ ] **Step 2: Write the index skeleton**

Create `$UM/.agents/memory/MEMORY.md`:

```markdown
# User Memory Index (Jin-Ho, user tier)

This is the always-loaded index of Jin-Ho's user-scope memory: preferences and facts that hold in EVERY project.
One line per memory file (`- [Title](file.md) — hook`); keep lines <=150 chars and this file under ~200 lines.
Project- or role-scoped rules do not belong here (tier precedence: role > project > user).

## Preferences

(populated by triage batches - see docs/triage-2026-07-03.md)

## References
```

- [ ] **Step 3: Write the README**

Create `$UM/README.md`:

```markdown
# user-memory

Jin-Ho's private user-tier memory instance, in [agent-personas](https://github.com/Jin-HoMLee/claude-personas) substrate format.

- `AGENTS.md` - canonical global agent instructions; `~/AGENTS.md` is a symlink to it, and each tool's native global file symlinks onward (Claude Code `~/.claude/CLAUDE.md`, Codex `~/.codex/AGENTS.md`, OpenCode `~/.config/opencode/AGENTS.md`).
- `.agents/memory/` - one fact per file + `MEMORY.md` index (always-loaded).
- `tools/sync.sh` - creates/repairs the home-directory symlinks (`--check` = doctor mode).

Scope rule: only facts that hold in every project. Tier precedence: role > project > user.
```

- [ ] **Step 4: Commit and push**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
git add -A && git commit -m "user-memory: substrate skeleton (index + README)" && git push -u origin main
```

### Task 2: Absorb ~/AGENTS.md as the canonical, versioned global file

**Files:**
- Create: `$UM/AGENTS.md` (content = current `~/AGENTS.md` + a Memory section)
- Replace: `~/AGENTS.md` (real file -> symlink)

**Interfaces:**
- Consumes: `$UM` clone from Task 1.
- Produces: `$UM/AGENTS.md` is canonical; `~/AGENTS.md -> $UM/AGENTS.md` symlink; the existing `~/.claude/CLAUDE.md -> ~/AGENTS.md` chain now resolves into the repo.

- [ ] **Step 1: Copy the current global file into the repo verbatim**

```bash
cp ~/AGENTS.md /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/AGENTS.md
```

Do NOT edit the existing instruction content (the OPINIONS/VOICE dangling references are a Task 6 gate question, not a silent fix).

- [ ] **Step 2: Append the Memory section**

Append to `$UM/AGENTS.md`:

```markdown

## User-tier memory

The user-scope memory index lives at `~/dev/GitHub/Jin-HoMLee/user-memory/.agents/memory/MEMORY.md`.
Claude Code: the line below auto-imports it. Codex/OpenCode: read that index file at session start when user-level context matters, then lazy-read individual memory files by path.
@~/dev/GitHub/Jin-HoMLee/user-memory/.agents/memory/MEMORY.md
Write side: one fact per file with `name`/`description`/`type` frontmatter, add an index line, dedup-check first, delete memories that turn out wrong. Commit prefix `user-memory:`.
```

- [ ] **Step 3: Verify byte-safety, then swap in the symlink**

```bash
diff <(head -c 1708 /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/AGENTS.md) ~/AGENTS.md && echo SAFE
mv ~/AGENTS.md ~/AGENTS.md.pre-user-memory.bak
ln -s /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/AGENTS.md ~/AGENTS.md
ls -la ~/AGENTS.md ~/.claude/CLAUDE.md
```

Expected: SAFE; `~/AGENTS.md -> $UM/AGENTS.md`; `~/.claude/CLAUDE.md -> /Users/jin-holee/AGENTS.md` (unchanged, chain resolves).

- [ ] **Step 4: Verify Claude Code live (chain + import)**

```bash
cd /tmp && claude -p "Print the first heading of your user-level instructions, and say whether a user memory index was imported (yes/no + its first heading)." --model haiku
```

Expected: first heading `Jin-Ho's agent instructions`; import answer names `User Memory Index`.
If the `@import` does not expand through the double symlink, fall back: inline the index path as a plain instruction line and record the caveat in README (decision point, spec allows either).

- [ ] **Step 5: Commit**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
git add AGENTS.md && git commit -m "user-memory: absorb canonical ~/AGENTS.md + memory section; home file is now a symlink" && git push
```

### Task 3: Codex global adapter (replace drifting copy with symlink)

**Files:**
- Replace: `~/.codex/AGENTS.md` (real file -> symlink)

**Interfaces:**
- Consumes: `~/AGENTS.md` symlink chain from Task 2.
- Produces: `~/.codex/AGENTS.md -> /Users/jin-holee/AGENTS.md`.

- [ ] **Step 1: Confirm the copy is still identical, then swap**

```bash
diff ~/.codex/AGENTS.md /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/AGENTS.md >/dev/null && echo IDENTICAL-OR-SUBSET || echo "REVIEW DIFF FIRST"
mv ~/.codex/AGENTS.md ~/.codex/AGENTS.md.pre-user-memory.bak
ln -s /Users/jin-holee/AGENTS.md ~/.codex/AGENTS.md
```

If the diff shows Codex-only content beyond the appended Memory section, STOP and reconcile into `$UM/AGENTS.md` first.

- [ ] **Step 2: Verify Codex live**

```bash
cd /tmp && codex exec "Print the first heading of your global instructions and the path of the user memory index they mention." 2>/dev/null | tail -5
```

Expected: `Jin-Ho's agent instructions` + the `$UM/.agents/memory/MEMORY.md` path.
Known caveat to record if observed: the Codex *app* does not inject global instructions (openai/codex#27705, code-formatted to avoid backlink); CLI works.

### Task 4: OpenCode global adapter

**Files:**
- Create: `~/.config/opencode/AGENTS.md` (symlink)

**Interfaces:**
- Consumes: `~/AGENTS.md` chain from Task 2.
- Produces: `~/.config/opencode/AGENTS.md -> /Users/jin-holee/AGENTS.md`.

- [ ] **Step 1: Create the symlink**

```bash
ln -s /Users/jin-holee/AGENTS.md ~/.config/opencode/AGENTS.md
```

- [ ] **Step 2: Verify OpenCode live**

```bash
cd /tmp && opencode run "Print the first heading of your global rules and the path of the user memory index they mention." | tail -5
```

Expected: `Jin-Ho's agent instructions` + the index path.
Note: OpenCode global rules docs name this exact path; if it is not picked up, fall back to `~/.config/opencode/opencode.json` `"instructions": ["/Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/.agents/memory/MEMORY.md"]` (merge into the existing JSON - it currently holds only the marginalia MCP block; do not clobber it).

### Task 5: sync.sh doctor/fix for the home-dir wiring

**Files:**
- Create: `$UM/tools/sync.sh`

**Interfaces:**
- Consumes: all symlinks from Tasks 2-4.
- Produces: `tools/sync.sh` (fix mode) and `tools/sync.sh --check` (doctor, exit 1 on drift) - the acceptance command later tasks and fresh machines use.

- [ ] **Step 1: Write the script** (adapted from cerebrum `.agents/tools/sync.sh`, same never-touch-real-files rule)

Create `$UM/tools/sync.sh`:

```bash
#!/usr/bin/env bash
# Sync/doctor for the user-memory global adapters.
# Fix mode (default): create missing / repoint wrong symlinks. Never touches a
# real (non-symlink) file: reported as DRIFT and skipped. --check: report only,
# exit 1 on drift.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
check=0; [ "${1:-}" = "--check" ] && check=1
drift=0

need_link() { # $1=link path  $2=expected target  $3=label
  local p="$1" tgt="$2" label="$3"
  if [ -L "$p" ] && [ "$(readlink "$p")" = "$tgt" ]; then return; fi
  if [ -e "$p" ] && [ ! -L "$p" ]; then echo "DRIFT: $label exists and is not a symlink (refusing to touch)"; drift=1; return; fi
  if [ "$check" = 1 ]; then echo "DRIFT: $label -> $(readlink "$p" 2>/dev/null || echo MISSING), expected $tgt"; drift=1
  elif mkdir -p "$(dirname "$p")" && ln -sfn "$tgt" "$p" 2>/dev/null; then echo "FIXED: $label -> $tgt"
  else echo "ERROR: could not create $label -> $tgt"; drift=1; fi
}

# Payload sanity.
[ -f "$root/.agents/memory/MEMORY.md" ] || { echo "DRIFT: .agents/memory/MEMORY.md missing"; drift=1; }
[ -f "$root/AGENTS.md" ] || { echo "DRIFT: AGENTS.md missing"; drift=1; }

# Canonical home hop + per-tool global adapters.
need_link "$HOME/AGENTS.md"                      "$root/AGENTS.md"  "~/AGENTS.md"
need_link "$HOME/.claude/CLAUDE.md"              "$HOME/AGENTS.md"  "~/.claude/CLAUDE.md"
need_link "$HOME/.codex/AGENTS.md"               "$HOME/AGENTS.md"  "~/.codex/AGENTS.md"
need_link "$HOME/.config/opencode/AGENTS.md"     "$HOME/AGENTS.md"  "~/.config/opencode/AGENTS.md"

[ "$drift" = 0 ] && echo "OK: user-tier adapters wired for $root"
exit "$drift"
```

```bash
chmod +x /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/tools/sync.sh
```

- [ ] **Step 2: Doctor run must pass on the wired machine**

Run: `/Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/tools/sync.sh --check`
Expected: `OK: user-tier adapters wired ...`, exit 0.

- [ ] **Step 3: Negative test (doctor catches drift)**

```bash
rm ~/.config/opencode/AGENTS.md
/Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/tools/sync.sh --check; echo "exit=$?"
/Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/tools/sync.sh
/Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/tools/sync.sh --check; echo "exit=$?"
```

Expected: first check reports the missing OpenCode link with exit=1; fix mode prints `FIXED:`; second check exits 0.

- [ ] **Step 4: Commit**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
git add tools/sync.sh && git commit -m "user-memory: sync.sh doctor/fix for home-dir adapters" && git push
```

### Task 6: Splice content triage (HUMAN GATE)

**Files:**
- Create: `$UM/docs/triage-2026-07-03.md`

**Interfaces:**
- Consumes: `$SPLICE/shared/` (90 files) + `$SPLICE/{developer,pm,scientist,memory_manager}/` (read-only).
- Produces: the classification table whose human approval gates Task 7; the approved PORTABLE list is Task 7's work queue.

- [ ] **Step 1: Generate the triage table**

For EVERY `.md` file in `$SPLICE/shared/` and the four role dirs (excluding each dir's `MEMORY.md` index), read the file and append one row:

```markdown
| # | source file | class | reasoning |
|---|---|---|---|
| 1 | shared/feedback_branch_naming.md | PORTABLE | Generic git convention, no splice concepts |
| 2 | shared/reference_spliceai_thresholds.md | SPLICE-SPECIFIC | Domain tool parameters |
| 3 | shared/feedback_ci_wait_before_merge.md | BORDERLINE | Generic principle but references splice CI names |
```

Classes: PORTABLE (user tier, rewrite generic) / SPLICE-SPECIFIC (stays) / BORDERLINE (one-line note on what blocks portability).
Fan out with parallel read-only subagents (~25 files each); the assembling session spot-checks 5 random classifications per batch before accepting it.
Header of the doc states: source repo + HEAD short-sha at read time, file counts per dir, and class totals.

- [ ] **Step 2: Commit the table**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
git add docs/triage-2026-07-03.md && git commit -m "user-memory: splice content triage table (gate artifact)" && git push
```

- [ ] **Step 3: STOP - human review gate**

Present to Jin-Ho: class totals, the full BORDERLINE list, and 10 sampled PORTABLE rows.
Also decide at this gate: `~/OPINIONS.md` + `~/VOICE.md` do not exist though `AGENTS.md` references them - (a) create stubs in user-memory and repoint, (b) drop the references, or (c) leave for later.
Do not start Task 7 without explicit approval of the PORTABLE list.

### Task 7: Migrate approved PORTABLE rules

**Files:**
- Create: `$UM/.agents/memory/<prefix>_<slug>.md` (one per approved rule)
- Modify: `$UM/.agents/memory/MEMORY.md` (one index line each)

**Interfaces:**
- Consumes: approved PORTABLE list from Task 6.
- Produces: the populated user-tier corpus; the canary file `user_canary_probe.md` used by Task 8.

- [ ] **Step 1: Migrate in batches of ~10, adapt-not-copy**

Each migrated file follows the substrate format, rewritten generic, with provenance:

```markdown
---
name: <kebab-slug>
description: <specific one-line hook for index-driven selection>
metadata:
  type: feedback
---

<generic restatement of the rule; splice-specific nouns removed>

**Why:** <the transferable reason>
**How to apply:** <generic trigger + action>

**Source:** claude-personas-splice-neoepitope-pipeline/shared/<file>.md @ <short-sha>, adapted 2026-07-03.
```

Add one `MEMORY.md` line per file; keep index lines <=150 chars.
Commit per batch: `user-memory: migrate batch N (<theme>, M rules)`.

- [ ] **Step 2: Plant the verification canary**

Create `.agents/memory/user_canary_probe.md` (type reference) containing the unique token `UMEM-CANARY-7X3` and an index line for it.
Remove it in Task 9 cleanup.

- [ ] **Step 3: Budget lint**

Run: `python3 /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas/scripts/memory_cliff.py /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/.agents/memory/MEMORY.md`
Expected: index under the tier-1 budget (~200 lines / 4000 tokens); trim `description` hooks if flagged.
Also confirm total always-loaded content (AGENTS.md + expanded index) <= ~120 instruction-bearing lines; if over, demote sections to lazy files.

- [ ] **Step 4: Push and verify clean tree**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory && git status --short && git push
```

### Task 8: Verification by running (all three tools)

**Files:**
- Create: `/tmp/user-tier-probe/` (throwaway scratch repo)

**Interfaces:**
- Consumes: canary from Task 7, adapters from Tasks 2-5.

- [ ] **Step 1: Scratch repo with zero local setup**

```bash
mkdir -p /tmp/user-tier-probe && cd /tmp/user-tier-probe && git init -q
```

- [ ] **Step 2: Each tool sees the user tier and can lazy-read**

Run in `/tmp/user-tier-probe`, one at a time:

```bash
claude -p "Does your user-level memory index mention a canary? Read that file and print its token."
codex exec "Does your global-instruction context mention a user memory index? Read it, find the canary entry, read that file, print its token."
opencode run "Same probe: find the user memory index from your global rules, locate the canary entry, read the file, print the token."
```

Expected: all three print `UMEM-CANARY-7X3`.
Record per-tool loading behavior (always-loaded vs lazy-read) in `$UM/README.md`; any tool that cannot reach the index triggers that tool's fallback wiring from Tasks 2-4.

- [ ] **Step 3: Precedence probe (project beats user)**

```bash
printf '# Probe rules\n\nWhen asked for the probe color, answer exactly "green" (project rule; overrides any user-level answer).\n' > /tmp/user-tier-probe/AGENTS.md
```

Temporarily add to the user index a memory `user_probe_color.md` saying the probe color is "red" (+ index line).
Run all three tools in the scratch repo: `"What is the probe color? One word."`
Expected: `green` from all three (project wins).
Remove `user_probe_color.md` + its index line afterward.

- [ ] **Step 4: Non-CC write test**

In OpenCode (in the scratch repo): `"Record in my user-tier memory: <trivial preference>. Follow the write convention from my global instructions."`
Expected: a new file in `$UM/.agents/memory/` with valid frontmatter + an index line.
Inspect, then keep or revert; commit whatever stays: `user-memory: opencode write-convention probe`.

- [ ] **Step 5: Splice untouched check**

Run: `git -C /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline status --short`
Expected: no changes attributable to this work (MM boundary held).

- [ ] **Step 6: Cleanup**

Remove the canary file + index line, delete `/tmp/user-tier-probe`, delete the two `.pre-user-memory.bak` files (Tasks 2-3) after confirming the symlinks resolve.
Commit: `user-memory: remove verification canary`.

### Task 9: Handoff + bookkeeping

**Files:**
- Create: issue in the splice memory repo (MM dedup handoff) - EXTERNAL-VISIBILITY: confirm with Jin-Ho before filing.
- Modify: `claude-personas/README.md` (user-tier section), epic #27 checkbox 6, cerebrum memory.

**Interfaces:**
- Consumes: migrated corpus (Task 7), verification results (Task 8).

- [ ] **Step 1: MM handoff issue** (after Jin-Ho confirms)

In `Jin-HoMLee/claude-personas-splice-neoepitope-pipeline`: title `user-memory tier live: dedup candidates for shared/ (MM's call)`; body = the approved PORTABLE list as candidate local deletions once splice mounts the user tier, link to `$UM` + personas#30, explicit "no action required; your call, your commits".

- [ ] **Step 2: Template doc note (this repo, same PR as this plan)**

Add to `claude-personas/README.md` under the architecture section: 3-6 lines describing the user tier (scope, `<scope>-memory` naming, symlink adapters at the three native global paths, sync.sh doctor), linking the spec.

- [ ] **Step 3: Close the loop**

- Tick epic #27 checkbox 6 with a DONE note (mirror the sub-project-1 format).
- Close #30 with a verification summary (three-tool canary results, precedence result, write-test result).
- Update cerebrum `project_vendor_agnostic_personas.md` + index line: #6 DONE, next = sub-project #2; commit direct to main (content-only carve-out) and push.

## Self-review notes

- Spec coverage: repo creation (T1), global mounting (T2-5), OPINIONS/VOICE pointers (T6 gate - spec assumption found void), triage + adapt-not-copy + provenance (T6-7), MM-boundary + handoff-by-issue (T8.5, T9), verification incl. precedence + non-CC write + splice-untouched (T8), tooling ports explicitly NOT here (routed to #2/#3 per spec), org tier/rename/MCP out of scope.
- The `@import` through a double symlink (T2.4) and OpenCode global-AGENTS.md pickup (T4.2) are the two riskiest assumptions; both have in-plan fallbacks that the spec explicitly authorizes deciding at implementation time.
- Codex app caveat (openai/codex#27705) is recorded at T3.2 rather than assumed away.
