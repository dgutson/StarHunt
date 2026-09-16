# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

StarHunt v1.1 is a Lua mod for **sm64coopdx**. There is no build system and no package manager.

    StarHunt/        <- the mod itself; this folder is what goes into sm64coopdx/mods/
      main.lua       <- 420 lines: header, requires, hook block, sync-table seed, test API
      modules/       <- the thirteen modules the mod is actually made of
    test/            <- test suite, deliberately OUTSIDE the mod folder
    tools/           <- engine-stub and linter-data generators, the mutation-testing
                        pair (gen_mutations.py, sweep_mutations.py), and module_deps.py

**Installing means copying the whole `StarHunt/` folder**, not `main.lua` alone: the game
walks a mod's folder and `main.lua` resolves `modules/...` through a folder-relative
`require`.

The mod folder is a strict boundary: sm64coopdx scans a mod's root **recursively** for `.lua`
and loads every file it finds, so anything with a `.lua` extension placed inside `StarHunt/`
becomes part of the shipped mod. Tests and tooling must stay outside it.

The project is closed. `PROJECT_STATUS.md` declares v1.1 final (2026-07-30) and says only
corrective maintenance is accepted — no new features, modes, goals, modifiers or scoring
changes. Treat a request for a new feature as a question worth raising before implementing it.

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

`PROJECT_STATUS.md` keeps the SHA-256 of the released single-file `main.lua`
(`EBC76DBE…A906B883`) as a historical fact of what shipped as v1.1, and records the modular
layout separately. **A single file's hash no longer identifies the mod**, so the recorded
identifier is now the SHA-256 of the sorted list of every shipped file's hash:

```bash
(cd StarHunt && find . -name '*.lua' | sort | xargs sha256sum | sha256sum)
```

Tags `v1.1-monolithic` and `v1.1-modular` mark the commit before and after the split.

## Commands

```bash
# Syntax/load check. MUST be lua5.4: the mod uses 5.3+ bitwise operators (`|`, `&`, `~`)
# in hud.lua and save.lua, and on this machine `lua` is the 5.1 alternative, which cannot
# parse them. This checks main.lua only; the modules are checked by the test run below.
lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"

# Tests (767 of them, ~45s). Needs lua5.4 for the same reason.
lua5.4 test/run.lua
lua5.4 test/run.lua audit difficulty     # only matching suites

# Lint: scope, shadowing, unused values. Uses .luacheckrc.
luacheck StarHunt/ test/

# Type-aware check against the real sm64coopdx API (undefined globals and fields,
# wrong arity, type mismatches). Pass the DIRECTORY, never the file: given a file
# path this tool silently reports "no problems found" whatever the code contains.
lua-language-server --check /home/dfg/src/StarHunt_v1.1 --checklevel=Warning \
  --logpath=/tmp/lls-log

# Recompute the recorded hash after any edit. The mod is fourteen files, so this is
# the hash of all of them, not of main.lua alone.
(cd StarHunt && find . -name '*.lua' | sort | xargs sha256sum | sha256sum)

# Mutation-check a change: generate candidates for a line range, then run the suite
# against each one in a throwaway copy of the tree. Run the sweep in the FOREGROUND
# with WORKERS=2 -- background sweeps have been killed here for low memory. Derive the
# line range AFTER your last edit to the file, or it will be off by the lines you added.
python3 tools/gen_mutations.py StarHunt/modules/round.lua 787,885
WORKERS=2 python3 tools/sweep_mutations.py round_client   # one suite: fast
ONLY=2,5,6-8 WORKERS=2 python3 tools/sweep_mutations.py   # re-run named survivors
```

### How the checkers know the engine API

`StarHunt/main.lua` calls about 59 engine functions and reads roughly 1,090 engine constants. Without
the game's API these are all undefined globals and the linters are useless, so the API list is
generated from sm64coopdx's own `autogen/lua_definitions` (6,337 globals: 2,008 functions,
4,307 constants, 22 mutable engine tables) and stored **outside this folder**, because the game
loads every `.lua` file it finds in a mod directory:

| Path | Contents |
|---|---|
| `~/.local/share/sm64coopdx/definitions/` | `functions.lua`, `constants.lua`, `structs.lua`, `manual.lua` from the game repo |
| `~/.local/share/sm64coopdx/luacheck_globals.lua` | generated read/write global lists, loaded by `.luacheckrc` |
| `~/.local/share/sm64coopdx/refresh.sh` | re-downloads the definitions and regenerates the above |

Run `~/.local/share/sm64coopdx/refresh.sh` after the game updates, so the checkers match the
engine version being targeted. The two config files that stay in this folder, `.luarc.json`
and `.luacheckrc`, have no `.lua` extension, so the game ignores them if the folder is copied
into `mods/`.

### Known-clean baseline and false positives

The whole mod is clean. **These are the baselines; a rise in either is a regression:**

| check | expected |
|---|---|
| `lua5.4 test/run.lua` | 767 passed, 0 failed |
| `luacheck StarHunt/ test/` | 2 warnings / 0 errors in 46 files |
| `lua-language-server --check` | Found 10 problems in 2 files |

The 2 luacheck warnings are `hud.lua:93` shadowing the upvalue `alpha` and an empty `if`
branch in `modifiers.lua`. The 10 type-checker problems are in `save.lua` (2) and
`test/harness.lua` (8). lua-language-server reports no undefined global, undefined field or
arity problem, which also confirms every engine symbol the mod uses still exists in current
sm64coopdx. `.luarc.json` disables `different-requires`, because the engine's own definitions
and the mod both define names the checker would otherwise pair up.

Two categories of report are expected and are **not** bugs. Confirmed against the engine's
binding code, not just its annotations:

- `save_file_do_save(file, true)` — "cannot assign `boolean` to parameter `integer`". The
  annotation says `integer`, but `smlua_to_integer` explicitly converts booleans (`true` → 1).
- `spawn_non_sync_object(..., nil)` — "cannot assign `nil` to parameter `function`".
  `smlua_to_lua_function` special-cases `LUA_TNIL` and returns 0; `nil` is the intended way to
  pass no setup function.

The 24 "shadowing upvalue `goal`" warnings are **gone**: the `goal()` constructor is now
`modules/goals.lua:61` and file-local to it, so the local variables named `goal` elsewhere no
longer shadow anything. Inside `goals.lua` itself they still do, which still means a typo'd
`goal(...)` call in such a scope is a runtime error rather than a lint error.

`selene` is installed but **unusable here**: the 0.31.0 Linux release only compiles in the
`lua51` and `luau` grammars, so it cannot parse this file's 5.4 syntax. Do not add a
`selene.toml`; use luacheck and lua-language-server instead.

### The test suite

`test/` loads the mod outside the game against a generated stub of exactly the engine surface
it uses, and drives it through `STARHUNT_TEST_API`. See `test/README.md` for the layout and for
what each suite guards. The suite was mutation-checked, so a green run means something.

It does not replace a real multiplayer session in sm64coopdx, and the project documents are
explicit about that. Rendering, networking, warping, collision and other-mod interaction are
all outside its reach.

The original harness named in DEVELOPMENT_CHECKLIST.md, `work/starhunt_v11_load_test.lua`, was
never in this repository and is not on this machine; `test/` is a fresh implementation.

## Architecture

### Where the code lives

Thirteen modules under `StarHunt/modules/`, loaded by folder-relative `require` from
`main.lua`. `DEVELOPMENT_CHECKLIST.md`'s `Mapa del código` maps a system to its module; this
is the same information by size, so you can judge what a file costs to read:

| module | lines | holds |
|---|---|---|
| `round.lua` | 1,079 | the round, both sides: the host half picks goals, counts stars and ends the round; the client half reacts to what the host published |
| `goals.lua` | 890 | the 93-star catalog, its readers, star interaction and visibility |
| `modifiers.lua` | 841 | the local player's modifier effects and the load-time self-check |
| `hud.lua` | 708 | text layer, picture layer and frame; nothing requires it |
| `boss.lua` | 493 | Bowser's data, health pool, attack queue and hazards |
| `menu.lua` | 321 | the `/starhunt` config menu and its input |
| `team.lua` | 271 | rosters, palettes and PvP |
| `audit.lua` | 267 | `goal_traits`, `audit_modifier`, `rebuild_audited_modifiers` |
| `i18n.lua` | 246 | six languages and their persistence |
| `core.lua` | 193 | `Team`, `local_runtime` and the cross-cutting helpers |
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

Boss attacks use a circular queue of 8 slots (`sh5_boss_attack_queue_1..8`) rather than a single
"latest attack" field, because a single field lost attacks under lag. Timed effects compare
cycle numbers rather than testing for one exact frame, for the same reason.

### `Team` — the shared namespace

`Team` is one table declared in `core.lua` that holds mode/difficulty/team constants
(`Team.NORMAL`, `Team.BOSS`, `Team.MODE`, `Team.CHAOS`; `Team.EASY`…`Team.NIGHTMARE`;
`Team.RED`/`Team.BLUE`) alongside most cross-cutting functions and mutable state. Its name is
historical: it is not limited to Team mode. **It is also how modules reach each other without a
`require` edge** — a function hung on `Team` in one module is callable from any module that has
`core`, which is how several moves avoided creating a cycle. Local `function` definitions and
`Team.x = function` definitions are used interchangeably; the difference is only whether
another module or the test API needs the name.

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

`Team.effective_modifier(base)` copies a modifier and scales it for the active difficulty:
Medium returns v0.9 values untouched; Easy converts permanent binary restrictions into pulses
(`pulse_period`/`pulse_frames`, read through `Team.periodic_window`) and softens numbers; Hard
and Nightmare strengthen them. `Team.lower_is_harder` says which direction "harder" scales.

**`Team.effective_modifier_for_goal(goal, base)` is the function to call**, never
`effective_modifier` alone, when a goal is involved: it re-runs the scaled result through
`audit_modifier()` and returns `nil` if difficulty pushed a modifier past what that star can
safely take. A difficulty must never bypass the audit.

Nightmare adds a second modifier in every mode. Pair compatibility
(`Team.chaos_pair_allowed`, `Team.pick_second_modifier`) is checked **in both orders** — an
earlier bug let a conflicting pair through by reversing it.

### The four modes

Normal and Team share the star-race code; Team only sums scores per team, balances rosters and
paints palettes. Boss replaces the round loop with `host_update_boss_round` and synchronized
Bowser health/attacks. Chaos has no star objective at all: everyone warps to one random main
course and act, each player gets independent personal modifiers rerolled every 15 seconds, and
death eliminates instead of reassigning. Difficulty applies to all four independently.

### Effects, hooks and other mods

Player-facing effects are applied every frame in `Team.apply_local_modifier` (under
`HOOK_BEFORE_MARIO_UPDATE`) and re-clamped in `Team.apply_post_moveset_limits` (under
`HOOK_MARIO_UPDATE`) — character and moveset mods such as OMM run their own
`HOOK_MARIO_UPDATE` callbacks and would otherwise undo the limits. Hook registration is a flat
block at the end of the file; order within a hook matters.

Compatibility with third-party mods is handled explicitly in `Team.register_mod_compatibility`
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
- **Test export.** New functions that a test needs must be added to `STARHUNT_TEST_API` in
  `main.lua`, the table published when the global `STARHUNT_TEST_MODE` is set, and exported
  from their own module first. The harness references functions by name there so reordering
  hooks cannot silently test the wrong one. **Being in `STARHUNT_TEST_API` does not mean a
  function is tested** — eight times now a published function turned out to be called by no
  test at all. `grep` for the key before assuming coverage.
- **Mod header.** The first three comment lines of `main.lua` are Co-op DX metadata (`-- name:`,
  `-- description:`, `-- incompatible: romhack`), with color escapes the checklist treats as
  verified. They are not ordinary comments.

## Languages

Six UI languages (`en, es, pt, fr, de, it`) via `Team.language`, an index into
`Team.language_codes`, persisted with `mod_storage_save("starhunt_v11_language", …)` and
migrated from the v1.0…v0.6 keys on first load. Goal and world names carry `title`/`title_es`
fields on the goal itself and go through `translated()`; other languages fall back to English
for star names, which is deliberate — only text with a safe translation is localized. Menu,
modifier and Boss strings live in `Team.ui_translations`, `Team.modifier_translations` and the
`label_es`/per-code tables near `BOSS_MODIFIERS`.

## Documents

- `CHANGELOG.md` — user-facing description of v1.1 and its maintenance updates (Spanish).
- `PROJECT_STATUS.md` — closure statement, final hash, what validation does *not* cover.
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
