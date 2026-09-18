# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

StarHunt v1.1 is a Lua mod for **sm64coopdx**. There is no build system and no package manager.

    StarHunt/        <- the mod itself; this folder is what goes into sm64coopdx/mods/
      main.lua       <- 449 lines: header, requires, hook block, sync-table seed, test API
      modules/       <- the thirteen modules the mod is actually made of
    test/            <- test suite, deliberately OUTSIDE the mod folder
    tools/           <- engine-stub and linter-data generators, the mutation-testing
                        pair (gen_mutations.py, sweep_mutations.py), and module_deps.py

**Installing means copying the whole `StarHunt/` folder**, not `main.lua` alone: the game
walks a mod's folder and `main.lua` resolves `modules/...` through a folder-relative
`require`.

The mod folder is a strict boundary. Verified against the engine's own source, not its
documentation (`src/pc/mods/mod.c` and `src/pc/lua/smlua.c` in `coop-deluxe/sm64coopdx`):

- `mod_load_files_dir(..., recursive = true)` registers **every** `.lua` and `.luac` under the
  mod's root, at any depth, as a file of that mod.
- The load loop in `smlua.c` then **runs only the root-level ones**: it skips any file whose
  relative path contains a path separator, with the comment "skip loading scripts in
  subdirectories". So `modules/*.lua` are never executed on their own.
- They run only when `require` reaches them. `require` is the game's own implementation
  (`smlua_require.c`), not Lua's: it resolves the name relative to the folder of the file
  doing the requiring, matches it against that mod's registered files, caches the result per
  mod, and refuses to require a directory. A cycle is caught by a sentinel and reported as
  "loop or previous error loading module", which is why the no-cycles rule below is real.
- `main.lua` at the root is mandatory: `mod_extract_fields` looks for exactly that name to
  read the `-- name:` / `-- description:` header.

So a stray `.lua` **at the root of `StarHunt/`** would be executed as part of the mod; one
inside `modules/` would be registered but not run unless something required it. Tests and
tooling stay outside the folder either way.

## Working process required by this project

`DEVELOPMENT_CHECKLIST.md` defines a process that is mandatory before editing `main.lua`, and
past sessions have followed it. In short:

1. Write the requested change as a `ROADMAP.md` item, with What / Why / Outcome.
2. Find the affected system in the `Mapa del código` table in `DEVELOPMENT_CHECKLIST.md`.
   It names the module, so a fix usually means reading one module and one or two test
   suites rather than the whole mod.
3. Read `Errores ya encontrados y solución que no se debe deshacer` first — that table lists
   bugs already fixed and the fix that must not be undone. Several look like redundant code and
   are not.
4. Add or change a case in `test/` **before** installing.
5. Run the syntax check and the full test.
6. Record the outcome: delete the item from `ROADMAP.md`, add what actually happened to
   `HISTORY.md`, and update `CHANGELOG.md` if the change is user-facing.

A change that only **moves** code carries three extra obligations — byte-identity proven in
both directions, a mutation check on the moved code, and a re-diff against the original
immediately before committing. `DEVELOPMENT_CHECKLIST.md` states them; `REFACTOR_PLAN.md`
explains how.

**A single file's hash no longer identifies the mod**, so its identifier is the SHA-256 of the
sorted list of every shipped file's hash. `HISTORY.md` records the value of each published
build:

```bash
(cd StarHunt && find . -name '*.lua' | sort | xargs sha256sum | sha256sum)
```

Tags `v1.1-monolithic` and `v1.1-modular` mark the commit before and after the split.

## Verifying a change

Every command, baseline and caveat for checking this mod — the syntax check, the offline
suite, luacheck, lua-language-server, the mutation sweep, and the live harness that runs the mod
inside real headless sm64coopdx processes — is in the **`starhunt-testing` skill**
(`.claude/skills/starhunt-testing/SKILL.md`). Load it before verifying anything; step 5 of the
process above means that skill.

It is kept out of this file on purpose. This file is read at the start of every session, so
knowledge that only matters while testing costs context in every session that is not testing.
Add to the skill rather than to this file.

## Architecture

### Where the code lives

Thirteen modules under `StarHunt/modules/`, loaded by folder-relative `require` from
`main.lua`. `DEVELOPMENT_CHECKLIST.md`'s `Mapa del código` maps a system to its module; this
is the same information by size, so you can judge what a file costs to read:

| module | lines | holds |
|---|---|---|
| `round.lua` | 1,096 | the round, both sides: the host half picks goals, counts stars and ends the round; the client half reacts to what the host published |
| `goals.lua` | 927 | the 93-star catalog, its readers, star interaction and visibility |
| `modifiers.lua` | 841 | the local player's modifier effects and the load-time self-check |
| `hud.lua` | 710 | text layer, picture layer and frame; nothing requires it |
| `boss.lua` | 538 | Bowser's data, health pool, attack queue and hazards |
| `menu.lua` | 327 | the `/starhunt` config menu and its input |
| `team.lua` | 273 | rosters, palettes and PvP |
| `audit.lua` | 267 | `goal_traits`, `audit_modifier`, `rebuild_audited_modifiers` |
| `i18n.lua` | 254 | six languages and their persistence |
| `core.lua` | 271 | `SH`, `Team`, `local_runtime` and the cross-cutting helpers |
| `chaos.lua` | 154 | Chaos's map, reroll and elimination |
| `difficulty.lua` | 110 | difficulty scaling; loaded for its side effect only, returns `{}` |
| `save.lua` | 80 | the temporary star flag and its removal |

The `require` graph has no cycles and must not gain one: sm64coopdx fails to load a mod whose
modules require each other in a circle. Re-derive the graph before moving code between modules; `tools/module_deps.py`
does not answer this question and can report a false positive from a string literal:

```bash
for f in StarHunt/modules/*.lua; do echo "-- $(basename $f)"; grep -n '^local .*require(' $f; done
```

```
audit     -> goals                                    boss      -> core ONLY
modifiers -> goals, audit, boss, team, i18n           chaos     -> core, audit, modifiers
round     -> core, i18n, save, goals, audit,          difficulty-> core, audit
             boss, chaos, modifiers                    team      -> core, goals
goals     -> core, i18n, save, boss                   menu      -> core, i18n, round
hud       -> core, i18n, goals, boss, round, menu     (nothing requires hud)
```

### Host authority and synchronized state

Everything that must agree between players lives in `gGlobalSyncTable` (round state, mode,
difficulty, Boss health and attack queue, Chaos state, scores) or in `gPlayerSyncTable[i]`
(per-player goal, modifier indices, score, team, jump count). All fields are prefixed `sh5_`.
Clients never write authoritative values: functions named `host_*` run only under
`network_is_server()`, and clients read the synced result. When adding state that late joiners
or a host migration must survive, it belongs in a sync table, not in a local variable.

**A deadline in a sync table is a frame number on the host's counter.** `get_global_timer()`
counts frames since that process started and never crosses the network, so any machine that
reads one compares it against `SH.host_timer()` (`core.lua`), which the host publishes once a
second and each client offsets by the difference. Host code keeps `get_global_timer()`, which
on the host is that same counter, and so does everything that never leaves one machine — the
warp delays, the modifier clocks, the moat refresh.

Boss attacks use a circular queue of 8 slots (`sh5_boss_attack_queue_1..8`) rather than a single
"latest attack" field, because a single field lost attacks under lag. Timed effects compare
cycle numbers rather than testing for one exact frame, for the same reason.

### `SH` and `Team` — the two shared namespaces

`core.lua` declares **two** tables that the rest of the mod hangs things on. `SH` is the
mod-wide one: the mode and difficulty axes, the language, the HUD helpers, Bowser's health,
the modifier readers, Chaos, the menu and third-party compatibility — 74 members, 443
references. `Team` is what is genuinely about Team mode: the colour axis, the rosters, the
palettes, the per-team scores and the balancing — 15 members, 113 references. Only `main.lua`,
`hud.lua`, `round.lua` and `team.lua` bind both; every other module binds `SH` alone.

Until R-019 there was one table called `Team` holding both, which is why older comments warn
that `Team` is "not a Team-mode table".

**This is also how modules reach each other without a `require` edge** — a function hung on
`SH` in one module is callable from any module that has `core`, which is how several moves
during the refactor avoided creating a cycle. Local `function` definitions and `SH.x =
function` definitions are used interchangeably; the difference is only whether another module
or the test API needs the name. Both tables are declared in `core.lua`, which requires
nothing, so either is reachable everywhere; putting the team side in `team.lua` would force
`round.lua` and `hud.lua` to require that module for the colour axis alone.

The three axes sit on **three separate tables**, because until R-019 they were eleven flat
fields and shared their numbers — `Team.NORMAL`, `Team.EASY` and `Team.NONE` were all 0. They
are now `SH.Mode` (`NORMAL`, `BOSS`, `TEAM`, `CHAOS`), `SH.Difficulty` (`EASY`, `MEDIUM`,
`HARD`, `NIGHTMARE`) and `Team.Color` (`NONE`, `RED`, `BLUE`). They are plain tables: a name
off the wrong axis reads as `nil`, so the comparison that reads it is false rather than true
for the wrong reason. **The numbers are unchanged and must stay so:** `sh5_mode` and
`sh5_difficulty` are synchronized, and the menu cycles them with `% 4`, indexes tables with
`+ 1` and clamps to `0, 3`. Five tests in `test/suite/core.lua` are all that keeps the axes
apart and the namespaces from merging back.

### Goals and the modifier audit

`GOALS` holds 93 hand-picked stars built by `goal(level, act, title, title_es, mods, power)`.
The 15 100-coin stars are deliberately excluded. The `mods` written in a goal definition are
**hand-tuned value overrides**, not the list of allowed modifiers.

At load time `rebuild_audited_modifiers()` replaces every goal's `mods` with the full 32-entry
`NORMAL_MODIFIER_CATALOG`, applying the hand-tuned value where one exists, and filters it
through `audit_modifier()`. That gives the 93 × 32 = 2,976 pair matrix (2,222 approved) that
the documents refer to. `audit_modifier()` runs four stages, described in `BALANCE_AUDIT.md`:
required button or ability, unfair route, per-star tuning, then numeric safety limits.

`goal_traits()` derives the traits the audit tests (`needs_b`, `flight`, `precision`, `race`,
`waiting`, `slide`, `water`, `ghost_house`, …) from the level and act. Adding a trait there
changes the whole matrix, so the counts in `BALANCE_AUDIT.md` must be re-derived.

### Difficulty is a separate axis from mode

`SH.effective_modifier(base)` copies a modifier and scales it for the active difficulty:
Medium returns v0.9 values untouched; Easy converts permanent binary restrictions into pulses
(`pulse_period`/`pulse_frames`, read through `SH.periodic_window`) and softens numbers; Hard
and Nightmare strengthen them. `SH.lower_is_harder` says which direction "harder" scales.

**`SH.effective_modifier_for_goal(goal, base)` is the function to call**, never
`effective_modifier` alone, when a goal is involved: it re-runs the scaled result through
`audit_modifier()` and returns `nil` if difficulty pushed a modifier past what that star can
safely take. A difficulty must never bypass the audit.

Nightmare adds a second modifier in every mode. Pair compatibility
(`SH.chaos_pair_allowed`, `SH.pick_second_modifier`) is checked **in both orders** — an
earlier bug let a conflicting pair through by reversing it.

### The four modes

Normal and Team share the star-race code; Team only sums scores per team, balances rosters and
paints palettes. Boss replaces the round loop with `host_update_boss_round` and synchronized
Bowser health/attacks. Chaos has no star objective at all: everyone warps to one random main
course and act, each player gets independent personal modifiers rerolled every 15 seconds, and
death eliminates instead of reassigning. Difficulty applies to all four independently.

### Effects, hooks and other mods

Player-facing effects are applied every frame in `SH.apply_local_modifier` (under
`HOOK_BEFORE_MARIO_UPDATE`) and re-clamped in `SH.apply_post_moveset_limits` (under
`HOOK_MARIO_UPDATE`) — character and moveset mods such as OMM run their own
`HOOK_MARIO_UPDATE` callbacks and would otherwise undo the limits. Hook registration is a flat
block at the end of the file; order within a hook matters.

Compatibility with third-party mods is handled explicitly in `SH.register_mod_compatibility`
and the Gun Mod / Day-Night / WiddlePets helpers around it, all guarded by `type(...) ==
"function"` checks so a missing mod is not an error.

### Small rules that are easy to break again

- **HUD colons.** `FONT_HUD` renders `:` as an `X`. Never call `djui_hud_print_text` on text
  containing a colon — go through `draw_hud_text` / `measure_hud_text`, which split at each
  colon and draw two dots instead.
- **Save index.** The game's course numbering is 1-based and the save file's is 0-based;
  `save_course_index_for()` subtracts 1. Removing only StarHunt's own temporary star flag (not
  the player's real save) is the point of `remove_starhunt_save_flag`.
- **Caps and HUD flags.** StarHunt records the player's pre-round cap, lives and HUD visibility
  and restores exactly those, instead of forcing its own defaults, so external mods survive a
  round.
- **Test export.** A function a test needs must be exported from its own module and added to
  `STARHUNT_TEST_API` in `main.lua`, the table published when the global `STARHUNT_TEST_MODE` is
  set. The `starhunt-testing` skill says why, and why being in that table does not mean the
  function is tested.
- **Mod header.** The first three comment lines of `main.lua` are Co-op DX metadata (`-- name:`,
  `-- description:`, `-- incompatible: romhack`), with color escapes the checklist treats as
  verified. They are not ordinary comments.

## Languages

Six UI languages (`en, es, pt, fr, de, it`) via `SH.language`, an index into
`SH.language_codes`, persisted with `mod_storage_save("starhunt_v11_language", …)` and
migrated from the v1.0…v0.6 keys on first load. Goal and world names carry `title`/`title_es`
fields on the goal itself and go through `translated()`; other languages fall back to English
for star names, which is deliberate — only text with a safe translation is localized. Menu,
modifier and Boss strings live in `SH.ui_translations`, `SH.modifier_translations` and the
`label_es`/per-code tables near `BOSS_MODIFIERS`.

## Documents

- `CHANGELOG.md` — user-facing description of v1.1 and its maintenance updates (Spanish).
- `DEVELOPMENT_CHECKLIST.md` — the required process, the code map, and the do-not-undo table.
  Live rules only; its version history was moved to `HISTORY.md`.
- `BALANCE_AUDIT.md` — the audit's four stages, per-difficulty guarantees and numeric limits
  (English).
- `REFACTOR_PLAN.md` — how to split `main.lua` into modules correctly: the shared-state rule,
  the engine's `require` behaviour, the verification discipline and the known traps. Method
  only; progress lives in `ROADMAP.md` and `HISTORY.md`.

These documents are kept small on purpose. Finished work is moved into `HISTORY.md` rather
than accumulating in the document that describes what is still to do — every line of a
document read at the start of a session costs context on every future session.

## Roadmap

This repo is governed by ROADMAP.md (pending work) and HISTORY.md (completed work).

- **Start here for context.** ROADMAP.md is the durable record of work that is established
  but unfinished. Read it rather than reconstructing the state of play from git history,
  old conversations, or a sweep of the code.
- Items are grouped **Now / Next / Later**. To choose what to work on, take the first item
  under the earliest horizon whose **Blocked-by** entries are no longer present in the file.
- When you finish an item: delete it from ROADMAP.md, add a line under today's date at the
  top of HISTORY.md recording the outcome **actually** achieved, and drop its ID from the
  **Blocked-by** list of every item it was blocking.
- When **Now** empties, promote the readiest items from **Next**, so the file keeps
  answering "what should I be doing" rather than going quiet.
- ROADMAP.md holds pending work only. Never mark an item done in place — removal is what
  "done" means here.
