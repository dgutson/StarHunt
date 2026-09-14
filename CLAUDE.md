# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

StarHunt v1.1 is a single-file Lua mod for **SM64CoopDX** (`main.lua`, ~5,200 lines). There is
no build system, no package manager and no directory structure: the whole mod is one file plus
four Markdown documents. The mod is installed by copying `main.lua` into the game's mods folder.

The project is closed. `PROJECT_STATUS.md` declares v1.1 final (2026-07-30) and says only
corrective maintenance is accepted — no new features, modes, goals, modifiers or scoring
changes. Treat a request for a new feature as a question worth raising before implementing it.

## Working process required by this project

`DEVELOPMENT_CHECKLIST.md` defines a process that is mandatory before editing `main.lua`, and
past sessions have followed it. In short:

1. Write the requested change under `Cambios pendientes` in `DEVELOPMENT_CHECKLIST.md`.
2. Find the affected system in the `Mapa del código` table there.
3. Read `Errores ya encontrados y solución que no se debe deshacer` first — that table lists
   bugs already fixed and the fix that must not be undone. Several look like redundant code and
   are not.
4. Add or change a case in the load test **before** installing.
5. Run the syntax check and the full test.
6. Record the outcome in `CHANGELOG.md`, `PROJECT_STATUS.md` and the checklist's history tables.

`PROJECT_STATUS.md` and `DEVELOPMENT_CHECKLIST.md` both record the SHA-256 of `main.lua`
(currently `EBC76DBE…A906B883`, and it matches). Any edit invalidates it; recompute with
`sha256sum main.lua` and update both documents.

## Commands

```bash
# Syntax/load check. MUST be lua5.4: main.lua uses 5.3+ bitwise operators (`|`),
# and on this machine `lua` is the 5.1 alternative, which fails at main.lua:921.
lua5.4 -e "assert(loadfile('main.lua'))"

# Lint: scope, shadowing, unused values. Uses .luacheckrc.
luacheck main.lua

# Type-aware check against the real sm64coopdx API (undefined globals and fields,
# wrong arity, type mismatches). Pass the DIRECTORY, never the file: given a file
# path this tool silently reports "no problems found" whatever the code contains.
lua-language-server --check /home/dfg/src/StarHunt_v1.1 --checklevel=Warning \
  --logpath=/tmp/lls-log

# Recompute the recorded hash after any edit
sha256sum main.lua
```

### How the checkers know the engine API

`main.lua` calls about 59 engine functions and reads roughly 1,090 engine constants. Without
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

As of the v1.1 hash below, `main.lua` is clean: luacheck reports 0 errors, and
lua-language-server reports no undefined global, undefined field or arity problem — which also
confirms every engine symbol the mod uses still exists in current sm64coopdx.

Two categories of report are expected and are **not** bugs. Confirmed against the engine's
binding code, not just its annotations:

- `save_file_do_save(file, true)` — "cannot assign `boolean` to parameter `integer`". The
  annotation says `integer`, but `smlua_to_integer` explicitly converts booleans (`true` → 1).
- `spawn_non_sync_object(..., nil)` — "cannot assign `nil` to parameter `function`".
  `smlua_to_lua_function` special-cases `LUA_TNIL` and returns 0; `nil` is the intended way to
  pass no setup function.

The 24 "shadowing upvalue `goal`" warnings come from local variables named `goal` shadowing the
`goal()` constructor at line 157. Deliberate and harmless, but it does mean a typo'd `goal(...)`
call inside such a scope would be a runtime error rather than a lint error.

`selene` is installed but **unusable here**: the 0.31.0 Linux release only compiles in the
`lua51` and `luau` grammars, so it cannot parse this file's 5.4 syntax. Do not add a
`selene.toml`; use luacheck and lua-language-server instead.

### The regression suite

The full suite the checklist names, `work/starhunt_v11_load_test.lua`, is **not in this
directory** and is not elsewhere on this machine. If a change needs testing, the harness has to
be located or rewritten; it drives the mod through `STARHUNT_TEST_API` (below). The static
checks above are not a substitute for it, and neither is a substitute for a real multiplayer
game session, which the project documents insist on.

## Architecture

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

`Team` is one table declared near the top of the file that holds mode/difficulty/team constants
(`Team.NORMAL`, `Team.BOSS`, `Team.MODE`, `Team.CHAOS`; `Team.EASY`…`Team.NIGHTMARE`;
`Team.RED`/`Team.BLUE`) alongside most cross-cutting functions and mutable state. Its name is
historical: it is not limited to Team mode. Local `function` definitions and `Team.x = function`
definitions are used interchangeably; the difference is only whether the test API or a later
part of the file needs the name.

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
- **Test export.** New functions that a test needs must be added to `STARHUNT_TEST_API`, the
  table published when the global `STARHUNT_TEST_MODE` is set. The harness references functions
  by name there so reordering hooks cannot silently test the wrong one.
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
- `BALANCE_AUDIT.md` — the audit's four stages, per-difficulty guarantees and numeric limits
  (English).
