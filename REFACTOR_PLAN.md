# Refactor method: splitting `main.lua` into modules

Branch `refactor/modularize`. This document holds **how** to do the split correctly — the
rules, the verification discipline, and the traps that have already cost a session. It does
not track progress.

- **What is left, and in what order:** `ROADMAP.md` (items R-001 to R-004).
- **What has already been done, and what it cost:** `HISTORY.md`.
- **What must not be broken while doing it:** `DEVELOPMENT_CHECKLIST.md`.

Ten of the thirteen modules are out. `round`, `hud` and `menu` remain, plus the parts four
modules left behind because they call into the round loop.

## The rule that makes the split safe

Lua copies a value on `local x = other.x`. So a top-level variable that gets **rebound**
(`x = ...`) cannot be re-localized per module — a write in one module would be invisible to
another, silently. A variable that is only **field-mutated** (`x.f = ...`) is shared safely by
reference and needs nothing.

Two tables are field-only and never rebound, so `local Team = require("core")` works unchanged
in every module: **`Team`** (the mod's general namespace, not a Team-mode table) and
**`local_runtime`** (the local player's per-frame state). Both live in `modules/core.lua`.

A rebound top-level local that several modules need gets **migrated onto `local_runtime`**
rather than shared some other way. This was done for 23 variables before any file moved, and
again for `config_open`. It follows a pattern the shipped code already proved, it is a
mechanical rename, and it needs no new sharing mechanism.

A rejected alternative, recorded so it is not re-proposed: a `modules/state.lua` holding every
mutable local. It duplicates what `local_runtime` already does, and forces the state clusters
that are entirely self-contained into a shared module they do not need.

**`team.lua` is the live example of why this rule decides the order.** Its three missing
functions read `host_player_records`, which round **rebinds** (`host_player_records = {}`), so
they cannot be shared by re-localizing and must wait for round to be extracted.

## Engine facts, verified against sm64coopdx source and in practice

1. `require()` resolves relative to the **folder of the requiring file**. From `main.lua`:
   `require("modules/core")`. From inside a module: `require("core")`. Both spellings are in
   the tree and both are correct.
2. `different-requires` is disabled in `.luarc.json` for exactly that reason.
   lua-language-server reads the two spellings as an inconsistency; it is not one, and it
   would otherwise recur once per module.
3. The auto-loader skips already-required files, so a module is not executed twice.
4. Load order is alphabetical on relative path, so `main.lua` precedes `modules/`.
5. The mod root is scanned **recursively** for `.lua`, so anything with that extension inside
   `StarHunt/` ships as part of the mod. Tests and tooling stay outside it.
6. All files of one mod share one `_ENV` whose metatable points at `_G`. Globals are shared;
   **locals are not**, which is the whole reason `core.lua` exists.
7. No require cycles so far. `test/harness.lua` reimplements the game's require and marks a
   module "loading" before executing it, so a cycle fails loudly rather than silently.

`main.lua` keeps, permanently: the three-line Co-op DX metadata header, the `require()` wiring,
the flat hook-registration block (**order within a hook type matters**), and the
`STARHUNT_TEST_API` table.

## How to verify an extraction

A green test run is not evidence an extraction is correct. Three checks, in this order:

1. **Byte-identity, in both directions.** Diff the module body against the lines sliced out of
   the previous commit (`git show HEAD:StarHunt/main.lua | sed -n 'A,Bp'`), *and* reconstruct
   `main.lua` from that commit minus the deleted ranges plus the added `require` line, and
   assert it equals the new file. The second direction is what proves nothing else moved.
2. **Mutation.** Mutate the moved code and check the suite notices. This has found a real
   coverage gap in **eight of the ten** modules extracted so far. Write tests until every
   mutation is caught, and check *which* test catches each one — a mutation caught by the
   wrong test, or showing up as a nil-index error rather than a readable assertion, means the
   intended test is not doing its job.
3. **Re-diff the module against its original immediately before committing**, not only after
   the move. A mutation was once left applied to `modules/modifiers.lua` and the full suite
   still passed; only this check caught it.

Do not use `git diff | grep '^-' | grep -v '^---'` to verify a relocation. A removed
`-- comment` appears in the diff as `--- comment`, which the header filter eats, so removed
comment lines vanish from the count. It produced a false "3 lines missing" alarm once.

## How to find out what a module still needs

```bash
grep -n "^Team.host_update_chaos_round" StarHunt/main.lua   # re-derive the range FIRST
python3 tools/module_deps.py 1084,1103
```

`tools/module_deps.py` prints every top-level name in `main.lua` that the given line ranges
reference, marked DEP or SELF, and flags the ones that are already `require()` imports. Any
other DEP is a real blocker.

`Team.x` fields never appear and never block anything: every module reaches the same `Team`
table by reference, so a function assigned onto `Team` in one module is visible from all of
them. Only top-level `local`s block.

**Do not guess from the appendix below.** It is machine-derived and has been wrong about real
dependencies more than once. The scan showed `modifiers` was blocked on three names rather
than the dozen the appendix implied, and `chaos` on one function rather than on all of round.

## Working rules

- **At most one module per chat session — a ceiling, not a target.** When a module is large,
  or only part of it can move, take the smaller piece and stop. Each extraction carries a lot
  of supporting work, and several in one session fills the context window and invites the
  kind of mistake that left a mutation applied to `modifiers.lua`. Finish deliberately:
  commit, update `ROADMAP.md` and `HISTORY.md`, say what is left, and stop. Do not start
  investigating the next module "while the context is still warm".
- **Follow the real dependency, do not fake a leaf.** `audit` was meant to precede `goals`,
  but `rebuild_audited_modifiers()` walks `GOALS`, so the order moved instead of passing
  `GOALS` in as a parameter — that would hide a real dependency to preserve an arbitrary
  sequence. Applied again to `chaos`: `host_update_chaos_round` stayed in `main.lua` rather
  than taking round's three functions as arguments.
- **A module may come out in two or three passes.** Take the part whose dependencies are
  satisfied, usually the static data, and leave the runtime for when its own dependencies
  land. Done for `goals`, `team`, `boss` and `chaos`.
- **Shared helpers move into `core.lua` when the first module actually needs one**, never
  speculatively. That is how `is_round_active`, `modifier()`, `clamp()`, `local_runtime`, the
  four mode predicates and `NEXT_GOAL_DELAY` got there. `NEXT_GOAL_DELAY` is the case worth
  remembering: the appendix assigned it to `chaos` on the strength of one caller, and it has
  three — one each in chaos, round and boss.
- **Pin values as literals in tests, never read them back from the mod.** A test that asks the
  code what it does agrees with the code whatever the code says. Two tests were already
  written that way and proved nothing: the difficulty-monotonicity test derived the direction
  from the values it observed, so a wrong entry in `Team.lower_is_harder` would invert the
  whole scale and still look monotonic; and a `local_runtime` liveness test drove a function
  that had not moved yet, so it passed whether or not core's table was the shared one. **A
  liveness test has to cross a module boundary that actually exists.**

## Traps that have already cost time

- **Guessing line numbers after an edit fails.** Always re-derive ranges with grep or awk.
  It has happened more than once, most recently feeding a stale range to `module_deps.py`,
  which returned a confident and entirely wrong answer about a different function.
- **Deleting a block plus its trailing blank line ate a non-blank neighbour.** Absorbing the
  following line is only safe after checking it is actually blank (`sed -n 'N,Np' … | cat -A`).
- **An import can shadow an existing local.** `local modifiers = require("modules/modifiers")`
  shadowed a local named `modifiers` inside `draw_hud`; renamed to `local_modifiers`. Run
  luacheck after adding imports.
- **Naming a module parameter `goal` reintroduces the shadowing warnings** once the function
  sits in the same file as the `goal()` constructor. Use `goal_data`, as `audit.lua` does.
  This is the one place a move was deliberately not byte-identical.
- **`awk` word boundaries (`\<`, `\>`) silently match nothing here.** Use
  `grep -n "\bname\b" | awk -F: '$1<A || $1>B'`.
- **`selene` 0.31.0 is unusable — do not retry.** The Linux release only compiles the `lua51`
  and `luau` grammars and cannot parse this file's 5.4 syntax. Do not add a `selene.toml`.
- **A generated engine stub can silently disable a guard.** `test/engine_stub.lua` returns
  `nil` from most engine functions, which is right for a function whose return value nothing
  reads and wrong for a predicate. `is_transition_playing()` returning `nil` meant every
  "hold this warp back while the level loads" guard could be deleted with no test noticing;
  it is now driven by `ctl.transition`. That is the second stub to need a real implementation
  after `ctl.palettes`. **When a mutation survives, check whether the stub made the branch
  unreachable before concluding the test is wrong.**
- **`STARHUNT_TEST_API` must keep its existing keys** or the suite stops compiling, and
  duplicate keys are reported by lua-language-server as `duplicate-index`. It already contains
  a `set_language` that clamps to the valid range; do not add a second one. Being in that
  table is **not** evidence of coverage: `Team.update_chaos_warp` was published there and
  called by no test at all.

## What the boundaries were derived from

`main.lua` has no section-separator comments, so the module boundaries come from the reference
graph (660 symbol-to-symbol edges among top-level declarations), cross-checked against Leiden
community detection in the code graph. The communities the graph found on its own matched the
planned layout closely.

The three modules left, as measured on the released file:

| module | decls | ~lines |
|---|---|---|
| round | 45 | 796 |
| hud | 31 | 601 |
| menu | 18 | 250 |

Their heaviest references to modules that are already out:

```
hud   -> i18n       51      round -> goals      23
round -> team       29      menu  -> i18n       23
round -> boss       28      menu  -> modifiers  23
hud   -> team       26      hud   -> modifiers  22
```

## Appendix: per-symbol assignment for the three remaining modules

**Machine-derived, not hand-verified**: seeded label propagation over the reference graph,
constrained so each state cluster stays whole. Line numbers refer to the **released** v1.1
file and are stale — re-derive every range with grep. Treat this as a starting point, never as
settled; `tools/module_deps.py` is what actually decides.

The appendix sections for the ten extracted modules were deleted once those modules existed.
They are in git history if ever needed.

Two things to know when reading it:

- **High-fan-in predicates look misplaced and are not.** `translated`, `is_round_active`,
  `is_boss_mode`, `Team.is_chaos_mode`, `Team.selected_difficulty` and `Team.periodic_window`
  each have most of their graph neighbours outside their own module, because they are used
  everywhere. They belong where they are semantically. 46 declarations show this pattern.
- **Known seed artifacts still to correct:** `on_joined_game` landed in `i18n` because it
  calls `translated`, but it is a hook callback and belongs with the hook block in `main.lua`.
  `draw_config_menu` landed in `hud` with the other `draw_*` functions; it may sit better in
  `menu` next to the rest of the config code. `Team.freeze_menu_mario` does most of its work
  against local modifier state and is worth reconsidering against `modifiers`.

### `modules/round.lua` — 45 declarations, ~796 lines

```
   17-17    local_var       RESULT_DISPLAY_FRAMES
   36-36    local_var       CHAOS_REROLL_FRAMES
   46-46    local_var       BOSS_LEVELS
   95-103   local_var       BOSS_PLAYER_MODIFIERS
  120-124   local_var       BOSS_MODIFIER_FIELDS
  125-125   local_var       BOSS_ATTACK_QUEUE_SIZE
  130-130   local_var       BOSS_ACTIVE_ATTACK_MODIFIERS
  131-131   local_var       BOSS_ACTIVE_ATTACK_LOOKUP
  845-856   local_function  time_range_for_players
  865-868   local_function  configured_time_range
  870-870   local_var       host_used_goals
  871-871   local_var       host_seen_done
  872-872   local_var       host_seen_forfeit
  873-873   local_var       host_player_records
  895-895   local_var       local_seen_return_seq
  896-896   local_var       local_return_warp_pending
  897-897   local_var       local_return_warp_retry_at
  926-926   local_var       host_previous_player_interactions
  927-927   local_var       host_previous_pvp_type
  962-964   local_function  is_round_active
 1532-1538  local_function  connected_player_count
 1540-1547  local_function  goal_is_active_for_anyone
 1591-1602  local_function  host_pick_goal
 1669-1705  local_function  host_assign_goal
 1707-1712  local_function  player_record_key
 1828-1834  local_function  update_winner_candidate
 1836-1860  local_function  winner_text_and_score
 1862-1935  local_function  host_end_round
 1937-1953  local_function  host_reset_scores_after_result
 1955-2049  local_function  host_prepare_player
 2051-2193  local_function  host_start_round
 2195-2222  local_function  remember_player_index
 2224-2226  local_function  remember_disconnected_player
 2228-2234  local_function  mark_connected_player_unenrolled
 2236-2248  local_function  host_add_late_joiner
 2341-2421  local_function  host_update_boss_round
 2546-2624  local_function  host_update_round
 3419-3450  local_function  force_return_to_lobby
 3587-3587  local_var       starhunt_hidden_players
 3780-3785  local_function  on_nametags_render
 3787-3816  local_function  update_private_player_visibility
 3920-3926  local_function  on_pause_exit
 4250-4260  local_var       STARHUNT_DEATH_ACTIONS
 4262-4269  local_function  on_before_death_action
 4274-4284  local_function  on_dialog
```

### `modules/hud.lua` — 31 declarations, ~601 lines

```
   13-13    local_var       START_BANNER_FRAMES
  893-893   local_var       local_seen_round
  894-894   local_var       local_seen_result
  898-898   local_var       local_start_banner_until
  899-899   local_var       local_hud_flags_before_round
  900-900   local_var       local_counter_round_active
 1143-1148  table_function  Team.darkness_active
 1157-1164  table_field     Team.menu_lock_labels
 1388-1446  local_function  modifier_text
 4286-4290  local_function  format_remaining_time
 4292-4305  local_function  measure_hud_text
 4307-4329  local_function  draw_hud_text
 4331-4334  local_function  draw_centered_hud_text
 4336-4345  table_function  Team.objective_text_max_width
 4347-4354  table_function  Team.draw_scaled_centered_text
 4356-4379  local_function  apply_counter_visibility
 4384-4384  local_var       native_hud_hidden
 4385-4397  local_function  update_native_hud_visibility
 4401-4411  table_function  Team.draw_darkness_behind
 4413-4416  local_function  hide_native_hud_before_render
 4418-4429  local_function  draw_start_banner
 4431-4518  local_function  draw_config_menu
 4520-4527  table_function  Team.draw_hud_panel
 4529-4531  table_function  Team.health_wedges
 4533-4537  table_function  Team.health_color
 4539-4561  local_function  draw_player_health_bar
 4563-4620  table_function  Team.draw_round_status_panels
 4622-4713  table_function  Team.draw_objective_panel
 4718-4759  table_function  Team.draw_gun_mod_hud_compatibility
 4761-4780  local_function  draw_hud
 4782-4835  local_function  local_round_notifications
```

### `modules/menu.lua` — 18 declarations, ~250 lines

```
  913-913   local_var       config_open
  914-914   local_var       config_selection
  915-915   local_var       config_button_latch
  916-916   local_var       config_stick_latched
 3988-3990  local_function  config_option_count
 3992-4004  local_function  config_option_kind
 4006-4012  local_function  config_status_text
 4014-4020  table_function  Team.close_widdlepets_menu
 4022-4035  table_function  Team.set_config_menu_open
 4037-4043  local_function  open_config_menu
 4045-4055  table_function  Team.update_config_menu_lock
 4057-4064  table_function  Team.cycle_mode
 4066-4070  table_function  Team.cycle_difficulty
 4072-4105  table_function  Team.freeze_menu_mario
 4107-4209  local_function  update_config_input
 4874-4878  local_function  show_help
 4880-4894  table_function  Team.show_updates
 4896-4909  local_function  starhunt_command
```

### Unassigned — 5 declarations, need a decision during extraction

```
   22-22    table_field     gServerSettings.skipIntro
  902-902   local_var       local_lakitu_scan_at
 3454-3463  local_function  remove_castle_lakitu
 3468-3474  local_function  remove_existing_castle_lakitu
 3913-3918  local_function  on_find_water_level
```
