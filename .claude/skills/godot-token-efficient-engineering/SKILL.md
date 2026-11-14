---
name: godot-token-efficient-engineering
description: Use for any Short Fights (Godot) task — gameplay, combat, bots, netcode, UI/HUD/touch, maps, bugs, perf, tests, export. Minimal-context protocol plus an orchestrator/worker method that delegates file-scoped work to smaller models.
---

# Godot token-efficient engineering

`CLAUDE.md` is the index + contract (already in context). Do not re-read it; do not dump directories.

## 1. Protocol
1. CLASSIFY: trivial (1 file, obvious) / normal (1-3 files) / complex (contract or several systems) / critical (netcode authority, damage validation, data loss).
2. LOCATE: use the Files table; open only the owning file and the contract section it implements. Grep a symbol before opening a second file.
3. DECIDE: smallest change inside existing files; keep signatures, node names, groups, RPC modes, layers.
4. EXECUTE: Edit in place; never rewrite a whole file for a local change.
5. VERIFY (proportional, never repeat a pass on unchanged code):
   - L0 reread your diff · L1/L2 `tools/check.sh` (~20 s, all maps/modes headless) · L3 `tools/check.sh net` (LAN) · visual: movie-writer frame (CLAUDE.md › Verify).
   - Netcode/lobby change => `net` is mandatory. Anything visible (spawn, camera, HUD, map) => look at one frame. Failure: read the first error + `at:` line, fix the cause, rerun once.
   - A silent pass is suspect: check the expected lines (`spawned`, kills > 0) are there.
6. CLOSE: changed files, real check output, risks. No recap of code.

## 2. Orchestrate or not
Delegate only when ALL hold: >= 2 independent units, each owns disjoint files, each > ~100 lines or > ~5 tool calls, and the contract for them is already written. Otherwise do it yourself — a cold worker re-reads context, which costs more than a small edit.

| Role | Model | Does |
|---|---|---|
| Orchestrator | strongest (session model) | contract in CLAUDE.md, briefs, integration, L2/L3 verify, final review |
| Logic worker | `sonnet` | netcode, combat, AI, input, UI logic |
| Mechanical worker | `haiku` | data tables, map layouts, renames, boilerplate from a precise spec |

Steps: (1) write/extend the contract section first (signatures, owners, RPC modes) · (2) launch workers in ONE message, in background, `subagent_type: general-purpose`, `model` per table, brief = template below · (3) meanwhile do orchestrator-owned files · (4) when all report: `tools/check.sh`, fix integration seams yourself (they are small), or SendMessage the same worker for its own file · (5) update CLAUDE.md only if the contract changed.

Brief template (keep under ~25 lines):
```
Project: <path>. First read .claude/agents/godot-worker.md and CLAUDE.md, then follow them.
Your files ONLY: <list>. Implement contract section(s): <names>.
Details the contract leaves open: <bullets: numbers, behavior, edge cases>.
Run `bash tools/check.sh <files>`. Reply per your rules.
```
Never give two workers the same file. Never let a worker edit the contract files (project.godot, *.tscn, fighter/weapons.gd, CLAUDE.md).

## 3. Memory hygiene
CLAUDE.md holds only: verified facts, file ownership, contracts, commands, known limits. No code copies, no session logs. Remove stale lines when you change behavior. Hypotheses go in "Known limits" marked as such.

## 4. Measuring
Run representative tasks (e.g. "add a 3rd primary weapon", "bots throw grenades more", "fix X") once with this skill and once without, in fresh sessions; compare `/cost` or the app's usage view (real numbers) and count tool calls + check reruns. Report only measured values.
