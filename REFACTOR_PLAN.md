# Refactor plan: splitting `main.lua` into modules

Branch `refactor/modularize`. Written before any code was moved, from a parse of the released
v1.1 file (sha256 `ebc76dbe…a906b883`, 5,171 lines, 271 top-level declarations). Baseline at
the time of writing: 72 tests pass, luacheck 0 errors, lua-language-server 4 known false
positives.

**Progress.** Six modules are out — core, i18n, save, goals, audit, difficulty — and
`main.lua` is down from 5,171 to 4,056 lines. The suite has grown from 72 tests to 93.
Current baseline, which must hold after every commit:

```bash
lua5.4 test/run.lua                       # 93 passed, 0 failed
luacheck StarHunt/ test/                  # 2 warnings / 0 errors
lua-language-server --check . --checklevel=Warning --logpath=/tmp/lls-log   # 10 problems
```

The 2 luacheck warnings (`empty if branch`, `shadowing upvalue alpha`) and the 10
type-checker problems (3 × `save_file_do_save`, 7 × partial engine stubs in
`test/harness.lua`) are all pre-existing. luacheck fell from 26 to 2 as modules left,
because the `shadowing upvalue goal` warnings went with the `goal()` constructor. A
further fall is expected; **a rise is a regression.**

The measurements below come from a tree-sitter parse of `main.lua` plus the code graph in
codebase-memory-mcp. The scripts live in the session scratchpad and are disposable; every
number here can be re-derived by re-running them.

## The one decision that makes the split safe

Lua copies a value on `local x = other.x`. So a top-level variable that gets **rebound**
(`x = ...`) cannot be re-localized per module — a write in one module would be invisible to
another, silently. A variable that is only **field-mutated** (`x.f = ...`) is shared safely by
reference and needs nothing.

Measured on the released file:

- 53 of the 78 top-level locals are rebound at least once; **33 of those from two or more
  top-level scopes**.
- Exactly **5** top-level locals are mutated only by field assignment, and are therefore
  already safe to share across modules: `Team` (66 scopes), `local_runtime` (14 scopes),
  `MODIFIER_AUDIT`, `MODIFIER_AUDIT_COUNTS`, `BOSS_ACTIVE_ATTACK_LOOKUP`. Neither `Team` nor
  `local_runtime` is ever rebound, so `local Team = require("team")` works unchanged in every
  module.

Treating each variable and the scopes that rebind it as one bipartite graph gives **12
independent state clusters**. Eleven are self-contained — they travel with their module and
need no shared table at all:

| vars | writing scopes | module |
|---|---|---|
| 6 | `host_assign_goal`, `host_end_round`, `host_prepare_player`, `host_start_round`, `host_update_round`, `remember_player_index` | round |
| 4 | `Team.set_config_menu_open`, `update_config_input` | menu |
| 4 | `ensure_boss_health_owner` | boss |
| 3 | `apply_goal_power`, `restore_starhunt_power` | goals |
| 3 | `force_return_to_lobby` | round |
| 3 | `local_round_notifications` | hud |
| 2 | `flush_starhunt_save_removals`, `remove_starhunt_save_flag` | save |
| 2 | `apply_counter_visibility` | hud |
| 1 each | `keep_moat_lowered`, `update_native_hud_visibility`, `remove_existing_castle_lakitu` | — |

The twelfth cluster is the whole problem: **23 variables written from 14 scopes**, spanning
boss hazards, chaos, death, warping, interaction and star visibility.

**Decision: migrate those 23 onto `local_runtime`**, the per-local-player runtime table already
declared at `main.lua:928` and already field-mutated from 14 scopes across the file's entire
span. This follows a pattern the shipped code already proves, it is a mechanical rename, and it
needs no new sharing mechanism.

```
local_boss_damage_lock       -> local_runtime.boss_damage_lock
local_boss_hazard_seq        -> local_runtime.boss_hazard_seq
local_boss_round_seen        -> local_runtime.boss_round_seen
local_boss_stun_frames       -> local_runtime.boss_stun_frames
local_boss_warp_at           -> local_runtime.boss_warp_at
local_death_lock             -> local_runtime.death_lock
local_death_warp_pending     -> local_runtime.death_warp_pending
local_done_lock              -> local_runtime.done_lock
local_floor_frames           -> local_runtime.floor_frames
local_goal_id                -> local_runtime.goal_id
local_goal_warp_at           -> local_runtime.goal_warp_at
local_idle_frames            -> local_runtime.idle_frames
local_jump_cooldown_frames   -> local_runtime.jump_cooldown_frames
local_modifier_ready_key     -> local_runtime.modifier_ready_key
local_modifier_start_frame   -> local_runtime.modifier_start_frame
local_modifier_tick          -> local_runtime.modifier_tick
local_pending_double_waves   -> local_runtime.pending_double_waves
local_pending_meteors        -> local_runtime.pending_meteors
local_slip_speed             -> local_runtime.slip_speed
local_star_visibility_next   -> local_runtime.star_visibility_next
starhunt_hidden_players      -> local_runtime.hidden_players
starhunt_hidden_stars        -> local_runtime.hidden_stars
starhunt_rejected_stars      -> local_runtime.rejected_stars
```

**Status: done.** Landed as four commits (`d532e86`, `2fec87b`, `d77bfe2`, `8841aa9`) with no
files moved — `main.lua` is still one file. 135 references rewritten via tree-sitter identifier
nodes, so strings and comments could not be touched. 72 tests green and luacheck at 26 warnings
/ 0 errors after every batch; lua-language-server output is byte-identical to the pre-migration
commit (10 problems: 3 known `save_file_do_save` false positives in `main.lua`, 7 pre-existing
partial engine stubs in `test/harness.lua`).

Measured afterwards: top-level `local` variables 78 → 55, locals rebound from two or more scopes
33 → 14, state clusters 12 → 11, and the largest cluster 23 vars / 14 scopes → 6 vars / 6 scopes
(the host round group, which sits entirely inside `round.lua`). The knot is gone.

Rejected alternative: a new `modules/state.lua` holding all 33 mutable locals. It duplicates
what `local_runtime` already does and forces the eleven self-contained clusters into a shared
module they do not need.

### Why it matters, measured

Without the migration, the 23-variable cluster drags all 14 of its writing functions into one
module: `boss.lua` comes out at 66 declarations / ~1,100 lines and the boss→modifiers coupling
is 100 references. With it, no module exceeds 45 declarations and the heaviest cross-module
coupling is hud→i18n at 51, which is just `translated()`.

## Module boundaries

`main.lua` has no section-separator comments, so the boundaries come from the reference graph
(660 symbol-to-symbol edges among top-level declarations), cross-checked against Leiden
community detection in the code graph. The communities the graph finds on its own match the
planned layout closely: a round loop, a HUD/translation group, a local-modifier group, a
config-menu group, a goal-assignment/audit group, a boss group, a boss-attack group and a
palette group.

| module | decls | ~lines |
|---|---|---|
| round | 45 | 796 |
| boss | 41 | 550 |
| modifiers | 39 | 664 |
| goals | 36 | 888 |
| hud | 31 | 601 |
| menu | 18 | 250 |
| team | 16 | 231 |
| chaos | 10 | 135 |
| save | 10 | 48 |
| audit | 7 | 227 |
| i18n | 7 | 193 |
| difficulty | 6 | 77 |

Heaviest cross-module references, after the migration:

```
hud   -> i18n       51      round -> goals      23
round -> team       29      menu  -> i18n       23
round -> boss       28      menu  -> modifiers  23
hud   -> team       26      hud   -> modifiers  22
```

`main.lua` keeps: the three-line Co-op DX metadata header, the `require()` wiring, the flat
hook-registration block (order within a hook type matters), and the `STARHUNT_TEST_API` table.

## Extraction order

Leaf-first, running `lua5.4 test/run.lua` after **each** module, one commit each:

1. ~~`local_runtime` migration (no files moved)~~ — **done**
1b. ~~`modules/core.lua`~~ — **done**. Not in the original layout, and a prerequisite
   for everything else: `Team` was a `local` in main.lua, so no required module could
   see it. core.lua now holds `Team`, `local_runtime`, `FRAMES_PER_SECOND`,
   `modifier()`, `clamp()` and `is_round_active()`.
2. ~~i18n~~ — **done** → 3. ~~save~~ — **done** → 4. ~~goals (the catalog only)~~ —
   **done** → 5. ~~audit~~ — **done** → 6. ~~difficulty~~ — **done**
7. team → 8. modifiers → 9. chaos → 10. boss → 11. round → 12. hud → 13. menu

**The order changed at step 4, and the leaf-first order past here is still not
validated against real dependencies.** audit was meant to be next, but
`rebuild_audited_modifiers()` walks `GOALS`, so the goal catalog had to leave first.
The alternative was passing `GOALS` into audit as a parameter; that hides a real
dependency in order to preserve an arbitrary sequence, so the sequence moved instead.
Expect the same question at each remaining step and answer it the same way: follow the
real dependency, do not fake a leaf.

`modules/goals.lua` deliberately holds **only the catalog** — `WORLD_NAMES`, `goal()`
and the 93 `GOALS` entries, which depend on nothing but `modifier()` and the engine's
`LEVEL_` constants. The goal-related runtime code the appendix also assigns to goals
(`on_allow_interact`, `on_interact`, `update_star_visibility`, `apply_goal_power`,
`players_have_private_variant`, …) is still in main.lua and joins the module when its
own dependencies come out. A module growing in two passes is fine; dragging its
dependencies out early is not.

Three shared helpers moved into `core.lua` as the module that needed them was reached,
each in its own commit:

| helper | moved for | why core |
|---|---|---|
| `modifier()` | audit's 32-entry catalog | 3 lines, no dependencies, and the goal, audit and two Boss catalogs all build modifiers from three different modules |
| `local_runtime` | difficulty's `periodic_window` | the second of the two field-only tables the whole split rests on; core already existed to hold the first |
| `clamp()` | difficulty's `selected_difficulty` | 5 lines, no dependencies, 24 callers spread across most modules |

The test harness reimplements the engine's folder-relative `require()`, so a wrong require path
fails in tests exactly as it would in the game. Require paths are folder-relative: from
`main.lua` it is `require("modules/audit")`; from inside `modules/round.lua` a sibling is
`require("audit")`, **not** `require("modules/audit")`.

## Open items

- Five declarations have no natural home and need a decision during extraction:
  `remove_castle_lakitu`, `remove_existing_castle_lakitu`, `local_lakitu_scan_at`,
  `on_find_water_level`, `gServerSettings.skipIntro`.
- `STARHUNT_TEST_API` must keep the same keys or the suite stops compiling. It already
  contains a `set_language` that clamps to the valid range; do not add a second one.
- **The suite does not cover everything being moved.** Extracting i18n left the run green
  even with `translated()` rewired to always return English, so a green run proves the
  module loads, not that the moved code is right. Two habits close that: verify each
  extraction is a pure relocation by diffing the moved lines against the removed ones, and
  add a suite for any area the mutation check shows is uncovered. i18n now has 9 tests that
  catch all 8 mutations tried against it; save had 6 tests that caught only 3 of 9 mutations
  (the course-index conversion was well covered, the flush and retry logic not at all) and
  now has 10 that catch all 9.
- Shared helpers move into `core.lua` when the first module needs them, rather than being
  moved there speculatively. `is_round_active` went in for save, which calls it three times;
  it is also the highest fan-in function in the mod, so most later modules will want it.

- **What the mutation checks have found so far.** Every extraction is verified twice: the
  moved lines are diffed against the removed lines and asserted byte-identical, and the moved
  code is then mutated to see whether the suite notices. The second check has found a real
  coverage gap in four of the six modules, which is the reason to keep doing it:

  | module | what was uncovered | what closed it |
  |---|---|---|
  | i18n | everything — `translated()` could return English always | 9 tests |
  | save | the flush and retry logic; one assertion could never fail | 10 tests |
  | goals | all catalog data — swapped English/Spanish columns, a retuned value, a typo'd world name | 18 pinned world names, and a digest over the whole catalog |
  | core | every `local_runtime` initial value — a sentinel starting at 0, a dropped queue, a lock starting engaged | 4 invariants in `test/suite/core.lua` |
  | difficulty | which direction "harder" runs per modifier | a per-kind direction table stated in the test |

  Two of those are worth understanding rather than just noting, because both were tests that
  looked like they covered the thing and did not:

  - *"difficulty is monotonic for every modifier"* derives the direction from the values it
    observes, so a wrong entry in `Team.lower_is_harder` inverts the whole scale for that
    modifier and the sequence is still perfectly monotonic — Nightmare would be **kinder**
    than Medium. A test can only catch that by stating the direction independently of the
    code, which the new one does, with the reason for each of the 24 graded kinds.
  - The first attempt at a runtime-table liveness test drove `Team.darkness_active`, which
    still lived in main.lua. main.lua and the test both read the table through
    `STARHUNT_TEST_API`, so it passed whether or not core's table was the shared one. It only
    became a real test once `periodic_window` moved into `difficulty.lua` and the two files
    reached the table through separate `require()` calls. **A liveness test has to cross a
    module boundary that actually exists.**

- **The catalog digest.** `test/suite/catalog.lua` pins an FNV-1a digest over every goal's
  level, act, world names, titles, power and hand-tuned modifier values. It was computed from
  the release commit `2111c0b`, and the catalog in `modules/goals.lua` was confirmed
  byte-identical to the released file, so the digest asserts what shipped rather than what
  merely happens to be here. `PROJECT_STATUS.md` closes v1.1 to balance changes, so this is
  fixed data; if a change is ever deliberate, the failure prints the new digest to paste in.
- `different-requires` is disabled in `.luarc.json`. sm64coopdx resolves a require path
  relative to the folder of the requiring file, so main.lua's `require("modules/core")` and
  a sibling module's `require("core")` are the same file spelled correctly in both places.
  lua-language-server reads that as an inconsistency; it is not one, and it would otherwise
  recur once per module.
- Docs to update when the refactor lands: `PROJECT_STATUS.md` and `DEVELOPMENT_CHECKLIST.md`
  both record the single-file SHA-256, which the split invalidates; install instructions change
  from "copy main.lua" to "copy the StarHunt/ folder".

  Those two documents still carry the released v1.1 hash `EBC76DBE…A906B883`, and that is
  deliberate: the line in `PROJECT_STATUS.md` reads "SHA-256 final de `main.lua`" and describes
  what shipped, not what this branch contains. Overwriting it per commit would misstate the
  release. As of the `local_runtime` migration the branch file hashes
  `a41bc569e57001188cc0715f7348c71281ed8ef5a76e6d9c926b5f44c2997ee9`; the recorded hashes get
  reconciled once, when the refactor merges.
- Verify once in a real sm64coopdx multiplayer session. No automated check covers rendering,
  networking, warping or other-mod interaction.

## Appendix: per-symbol assignment

The table below is **machine-derived**, not hand-verified: seeded label propagation over the
reference graph, constrained so each state cluster stays whole. Treat it as the starting point
for each extraction commit, not as settled.

Two things to know when reading it:

- **High-fan-in predicates look misplaced and are not.** `translated`, `is_round_active`,
  `is_boss_mode`, `Team.is_chaos_mode`, `Team.selected_difficulty` and `Team.periodic_window`
  each have most of their graph neighbours outside their own module, because they are used
  everywhere. They belong where they are semantically. 46 declarations show this pattern; the
  large majority are this, not an error.
- **Known seed artifacts to correct during extraction:**
  `Team.saved_language` matched the `save` pattern by name but is language persistence and
  belongs in `i18n`. `on_joined_game` landed in `i18n` because it calls `translated`, but it is
  a hook callback and belongs with the hook block in `main.lua`. `draw_config_menu` landed in
  `hud` with the other `draw_*` functions; it may sit better in `menu` next to the rest of the
  config code. `Team.freeze_menu_mario` and `Team.update_chaos_warp` both do most of their work
  against local modifier state and are worth reconsidering against `modifiers`.

### `modules/i18n.lua` — 7 declarations, ~193 lines

```
  909-909   table_field     Team.language
 1156-1156  table_field     Team.language_codes
 1165-1165  table_field     Team.language_names
 1166-1283  table_field     Team.ui_translations
 1284-1337  table_field     Team.modifier_translations
 1373-1378  local_function  translated
 4837-4848  local_function  on_joined_game
```

### `modules/save.lua` — 10 declarations, ~48 lines

```
  910-910   table_field     Team.saved_language
 1476-1478  local_function  star_flag_for
 1480-1484  local_function  save_course_index_for
 1488-1488  local_var       pending_star_removals
 1489-1489  local_var       next_star_cleanup_at
 1490-1499  local_function  remove_starhunt_save_flag
 1501-1515  local_function  flush_starhunt_save_removals
 1517-1519  local_function  flush_starhunt_save_on_warp
 1521-1523  local_function  flush_starhunt_save_on_exit
 1525-1530  local_function  goal_already_collected
```

### `modules/audit.lua` — 7 declarations, ~227 lines

```
  608-641   local_var       NORMAL_MODIFIER_CATALOG
  643-648   local_function  act_is
  650-710   local_function  goal_traits
  712-805   local_function  audit_modifier
  807-807   local_var       MODIFIER_AUDIT
  808-808   local_var       MODIFIER_AUDIT_COUNTS
  810-839   local_function  rebuild_audited_modifiers
```

### `modules/difficulty.lua` — 6 declarations, ~77 lines

```
  984-987   table_function  Team.selected_difficulty
  998-1002  table_field     Team.lower_is_harder
 1004-1055  table_function  Team.effective_modifier
 1057-1063  table_function  Team.effective_modifier_for_goal
 1150-1154  table_function  Team.periodic_window
 1651-1654  table_function  Team.difficulty_modifier_allowed
```

### `modules/goals.lua` — 36 declarations, ~888 lines

```
   55-88    local_var       MODIFIER_KINDS
  136-155   local_var       WORLD_NAMES
  157-169   local_function  goal
  173-602   local_var       GOALS
  911-912   table_field     Team.lifetime
  921-921   local_var       STARHUNT_SPECIAL_CAP_MASK
  922-922   local_var       local_starhunt_power
  923-923   local_var       local_starhunt_added_flags
  924-924   local_var       local_power_original_timer
  925-925   local_var       local_star_visibility_next
 1065-1067  local_function  get_goal
 1069-1071  local_function  get_local_goal
 1115-1117  table_function  Team.update_lifetime_sync
 1380-1382  local_function  goal_world_text
 1384-1386  local_function  goal_title_text
 1549-1552  local_function  goal_matches_player_area
 1554-1560  local_function  goal_matches_star_object
 1656-1667  table_function  Team.pick_second_modifier
 3063-3069  local_function  power_flags
 3071-3092  local_function  restore_starhunt_power
 3094-3119  local_function  apply_goal_power
 3476-3484  local_function  is_hmc_metal_portal
 3486-3489  local_function  in_castle_lock_level
 3491-3493  local_function  has_interaction
 3498-3498  local_var       starhunt_rejected_stars
 3500-3554  local_function  on_allow_interact
 3556-3581  local_function  on_interact
 3586-3586  local_var       starhunt_hidden_stars
 3588-3593  local_function  reset_hidden_object_tracking
 3595-3620  local_function  update_star_visibility
 3625-3630  local_function  is_jrb_ship_zone
 3632-3642  local_function  is_ddd_sub_zone
 3644-3647  local_function  is_wf_tower_zone
 3649-3698  local_function  players_have_private_variant
 3700-3720  local_function  players_can_share_world
 4911-4978  local_function  run_static_modifier_checks
```

### `modules/team.lua` — 16 declarations, ~231 lines

```
   28-33    local_var       Team
   34-34    local_var       TEAM_SCORE_PRIORITY_GAP
  966-970   local_function  selected_mode
  976-978   table_function  Team.is_mode
 1714-1763  table_function  Team.build_balanced
 1765-1793  table_function  Team.participant_stats
 1795-1819  table_function  Team.pick_late
 1821-1826  table_function  Team.update_scores
 3722-3738  local_function  on_allow_pvp_attack
 3818-3821  table_field     Team.colors
 3823-3828  table_function  Team.palette_key
 3830-3834  table_function  Team.palette_identity
 3836-3859  table_function  Team.capture_palette
 3861-3880  table_function  Team.restore_palettes
 3882-3901  table_function  Team.update_palettes
 3977-3986  table_function  Team.update_manual_reroll_menu
```

### `modules/modifiers.lua` — 39 declarations, ~664 lines

```
   12-12    local_var       FRAMES_PER_SECOND
   26-26    local_var       CASTLE_LOWERED_MOAT
   90-92    local_function  modifier
  876-876   local_var       local_floor_frames
  877-877   local_var       local_slip_speed
  878-878   local_var       local_modifier_tick
  879-879   local_var       local_modifier_start_frame
  880-880   local_var       local_modifier_ready_key
  888-888   local_var       local_idle_frames
  889-889   local_var       local_jump_cooldown_frames
  890-890   local_var       local_done_lock
  901-901   local_var       local_moat_refresh_at
  928-954   local_var       local_runtime
  956-960   local_function  clamp
 1073-1073  table_field     Team.modifier_override
 1075-1088  table_function  Team.get_local_modifier_base
 1090-1092  local_function  get_local_modifier
 1094-1113  table_function  Team.get_local_modifiers
 1119-1122  table_function  Team.coin_count
 1124-1127  table_function  Team.coin_toll_paid
 1129-1134  table_function  Team.all_coin_tolls_paid
 1136-1141  table_function  Team.local_modifier_of_kind
 1562-1565  local_function  is_local_player_on_floor
 1567-1589  local_function  reset_local_modifier_state
 2628-2635  local_function  capped_horizontal_velocity
 2637-2644  local_function  swap_button_bits
 2646-2649  local_function  rotate_stick
 2651-2660  local_function  suppress_local_input
 2662-2981  table_function  Team.apply_one_local_modifier
 2983-2990  table_function  Team.apply_local_modifier
 2996-3048  table_function  Team.apply_post_moveset_limits
 3052-3061  local_function  grant_infinite_lives
 3740-3746  table_function  Team.local_index_from_global
 3752-3778  table_function  Team.install_gun_mod_compatibility
 3903-3911  local_function  keep_moat_lowered
 3928-3935  table_function  Team.manual_reroll_remaining
 3937-3949  table_function  Team.manual_reroll_label
 3951-3975  table_function  Team.request_manual_reroll
 4850-4872  table_function  Team.register_mod_compatibility
```

### `modules/chaos.lua` — 10 declarations, ~135 lines

```
   14-14    local_var       NEXT_GOAL_DELAY
   37-41    table_field     Team.chaos_maps
  980-982   table_function  Team.is_chaos_mode
 1604-1615  table_field     Team.chaos_conflicts
 1617-1623  table_function  Team.chaos_pair_allowed
 1625-1628  table_function  Team.chaos_modifier_allowed
 1630-1649  table_function  Team.pick_chaos_pair
 2496-2523  table_function  Team.host_reroll_chaos_modifiers
 2525-2544  table_function  Team.host_update_chaos_round
 3158-3192  table_function  Team.update_chaos_warp
```

### `modules/boss.lua` — 41 declarations, ~550 lines

```
   35-35    local_var       BOSS_HEALTH
   47-53    table_field     Team.bossBombPositions
  105-118   local_var       BOSS_MODIFIERS
  858-863   local_function  boss_time_range_for_players
  874-874   local_var       local_goal_id
  875-875   local_var       local_goal_warp_at
  881-881   local_var       local_boss_round_seen
  882-882   local_var       local_boss_warp_at
  883-883   local_var       local_boss_hazard_seq
  884-884   local_var       local_boss_stun_frames
  885-885   local_var       local_boss_damage_lock
  886-886   local_var       local_pending_double_waves
  887-887   local_var       local_pending_meteors
  891-891   local_var       local_death_lock
  892-892   local_var       local_death_warp_pending
  917-917   local_var       local_boss_health_object
  918-918   local_var       local_boss_health_initialized
  919-919   local_var       local_boss_health_last_value
  920-920   local_var       local_boss_health_report_at
  972-974   local_function  is_boss_mode
  989-992   table_function  Team.boss_health_for_difficulty
  994-996   table_function  Team.boss_max_health
 1338-1371  table_field     Team.boss_modifier_translations
 1448-1451  local_function  boss_modifier_at
 1453-1458  local_function  boss_has_modifier
 1460-1462  local_function  boss_is_desperate
 1464-1474  local_function  boss_modifier_text
 2250-2264  local_function  host_read_boss_health_report
 2266-2271  table_function  Team.boss_reserve_bomb_count
 2276-2339  table_function  Team.host_update_boss_bomb_supply
 2426-2480  local_function  ensure_boss_health_owner
 2482-2494  local_function  on_before_boss_cutscene
 3121-3156  local_function  local_goal_warp_update
 3194-3241  local_function  local_boss_warp_update
 3243-3266  local_function  spawn_violet_split_fire
 3268-3279  local_function  spawn_boss_flame
 3281-3289  local_function  trigger_boss_wave
 3291-3300  local_function  resolve_meteor_rain
 3302-3343  local_function  execute_boss_attack
 3345-3414  local_function  apply_boss_hazards
 4211-4245  local_function  on_death
```

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
