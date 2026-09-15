# Refactor method: splitting `main.lua` into modules

Branch `refactor/modularize`. This document holds **how** to do the split correctly — the
rules, the verification discipline, and the traps that have already cost a session. It does
not track progress.

- **What is left, and in what order:** `ROADMAP.md` (items R-003 and R-004).
- **What has already been done, and what it cost:** `HISTORY.md`.
- **What must not be broken while doing it:** `DEVELOPMENT_CHECKLIST.md`.

Eleven of the thirteen modules are out, and `hud` and `menu` remain. Nothing else in
`main.lua` belongs to a module that exists. `round.lua` is finished: its client half
came out first, and its host half -- the clock, the goal pool, the winner tally, the player
records and the per-frame loop -- followed once Boss's readers had moved. `team.lua` is
finished too: its roster totals, late assignment, score publishing and reroll-button label
came out once `player_record_key` had moved into `core.lua`. `goals.lua` is now finished as
well, in three passes: the catalog and its readers, then the required-cap code, then the
interaction handlers and star visibility. `modifiers.lua` has taken the load-time self-check
and its list of accepted modifier kinds. `boss.lua` is finished too, in three passes: the
static data and the health pool, then the readers, then the attack queue and the hazards --
that last one once `is_local_player_on_floor` had moved into `core.lua`, the second time a
shared helper had to move before a module could follow it.

**R-002 is finished.** Its last function, `Team.host_update_chaos_round`, went into
`round.lua`, and the reason is the one `host_update_boss_round` had before it: a mode's round
loop cannot live in that mode's own module, because `round.lua` requires `boss.lua` and
`chaos.lua` and an edge back the other way would be a cycle. The first of the two options --
move what the caller needs into `core.lua` -- was measured and rejected rather than skipped.
The scan named three dependencies, `host_end_round`, `host_add_late_joiner` and
`remember_player_index`, and all three are the round's own host machinery rather than plain
helpers: `host_end_round` rebinds two of the round's tables, and `host_add_late_joiner` goes
through `host_prepare_player`, which reads three more. Moving those into `core.lua` to satisfy
one caller would have put the round's own decisions outside the round. So the rule this pass
establishes is the narrow one: **a shared helper moves into `core.lua`; a module's own
machinery does not.** The move needed no new `require` edge at all -- all three names were
already file-local in `round.lua`, and `Team.host_reroll_chaos_modifiers` is reached through
the shared `Team` table.

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

**`team.lua` was the worked example of this rule, and of its escape hatch.** Its three missing
functions read `host_player_records`, which `host_start_round` **rebinds**
(`host_player_records = {}`). Waiting for round to be extracted would not have helped: a
rebound local cannot be shared with `team.lua` from `round.lua` either. The table was migrated
onto `Team` instead.

That was necessary and not sufficient, which is the second half of the lesson. The same three
functions also call `player_record_key`, a plain helper that `round.lua` owned and exported --
and `team.lua` can never import `round.lua`, because the graph already runs
`round -> modifiers -> team` (see the next section). So the helper moved into `core.lua` as
well, in its own verified commit. **Check for a cycle before believing an export unblocks
anything.** `ROADMAP.md` recorded these functions as unblocked on the strength of that export
for a whole session, and they were not.

The same rule split `round` itself in two. `host_start_round` rebinds `host_used_goals`,
`host_seen_done`, `host_seen_forfeit` and `host_player_records`; `host_end_round` rebinds
`host_previous_player_interactions` and `host_previous_pvp_type`. None of those six can leave
without the functions that rebind them, so the host half of the round has to move as one piece.
The client half depends on none of that and went first. The four Boss helpers that also blocked
it — `boss_time_range_for_players`, `boss_has_modifier`, `boss_is_desperate` and
`host_read_boss_health_report` — have since moved into `boss.lua`, so that half of the blockage
is gone.

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
   module "loading" before executing it, so a cycle fails loudly rather than silently. Three
   edges already exist that forbid the reverse import, and they are why three functions could
   not go where the plan first put them:

   ```
   modifiers -> boss    (BOSS_PLAYER_MODIFIERS)   so boss may not require modifiers
   modifiers -> team    (on_allow_pvp_attack)     so team may not require modifiers OR round
   round     -> boss, chaos, modifiers            so none of those may require round
   ```

   The middle one reaches further than it looks: `team.lua` cannot import `round.lua` either,
   because `round.lua` imports `modifiers.lua`, which imports `team.lua`. Two more edges out
   of `goals.lua` forbid the reverse import and settled where one function goes:

   ```
   audit     -> goals    (GOALS)   so goals may not require audit
   modifiers -> goals              so goals may not require modifiers
   goals     -> core, i18n, save, boss
   ```

   That is why `run_static_modifier_checks` could not live in `goals.lua` even though it walks
   `GOALS`: it also reads `NORMAL_MODIFIER_CATALOG`, `MODIFIER_AUDIT` and
   `MODIFIER_AUDIT_COUNTS` from `audit.lua` and `capped_horizontal_velocity`,
   `swap_button_bits` and `rotate_stick` from `modifiers.lua`, and goals may import neither.
   `modifiers.lua` already imported both, so that is where it went, along with
   `MODIFIER_KINDS`. The move needed no new edge at all: the two names it added,
   `goals.GOALS` and the two audit tables, come from modules `modifiers.lua` already
   required. Print the whole
   graph before every move -- `tools/module_deps.py` does not answer this question:

   ```bash
   for f in StarHunt/modules/*.lua; do echo "-- $(basename $f)"; grep -n '^local .*require(' $f; done
   ```

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
   coverage gap in **fourteen of the sixteen** passes so far, most recently the Chaos round
   loop, which could be replaced with an empty body and 456 tests stayed green. Before that, the interaction
   handlers and star visibility, where the whole area was untested: `allow_interact` and
   `interact` were published in `STARHUNT_TEST_API` and called by no test at all, and
   `update_star_visibility` and `reset_hidden_object_tracking` were not published at all.
   Write tests until every
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
grep -n "^local function draw_hud" StarHunt/main.lua   # re-derive the range FIRST
python3 tools/module_deps.py 1200,1219
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
  sequence. Applied again to `chaos`: `host_update_chaos_round` was never given round's three
  functions as arguments to let it sit in `chaos.lua`; it went to `round.lua`, where the
  functions already are.
- **A module may come out in two or three passes.** Take the part whose dependencies are
  satisfied, usually the static data, and leave the runtime for when its own dependencies
  land. Done for `goals`, `team`, `boss`, `chaos` and `round`. `boss` took three and is now
  complete. `team` took three passes and is now complete. `round` split along a line the
  code names itself: the `local_*` half that only reacts to synchronized state came out first,
  and the `host_*` half that writes it followed once Boss's readers had moved. Both halves are
  now in `round.lua`, and the file says in its header that the split between them is the mod's
  host-authority rule made visible.
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
  shadowed a local named `modifiers` inside `draw_hud`; renamed to `local_modifiers`. It has
  happened twice: a handle named `round` would have been shadowed by the five functions that
  declare `local round = gGlobalSyncTable.sh5_round or 0`, so that one is `local_round` too.
  Grep for the intended handle name before adding the import, and run luacheck after.
- **Naming a module parameter or local `goal` reintroduces the shadowing warnings** once the
  function sits in the same file as the `goal()` constructor. Use `goal_data`, as `audit.lua`
  does. This has now happened three times -- `audit.lua`'s parameter, `apply_goal_power`'s
  `local goal`, and three more in the interaction handlers -- and it is the only kind of change
  a move is allowed to make that is not byte-identical. Say so in the commit message and show
  the diff, so the exception stays visible rather than looking like drift. Rename only the
  variable: `rejection.goal` and the `goal = goal_id` table key in `on_allow_interact` look
  identical to a careless `\bgoal\b` substitution and are not variables at all.
- **`awk` word boundaries (`\<`, `\>`) silently match nothing here.** Use
  `grep -n "\bname\b" | awk -F: '$1<A || $1>B'`.
- **Check the require graph before assuming a dependency is satisfied.**
  `tools/module_deps.py` answers "what top-level names does this code still need", which is
  necessary but not sufficient: a name can be satisfied by a module that already requires the
  one you are moving into, and importing it back is a cycle. That is what kept Boss's hazards
  and attacks in `main.lua` for three passes even though every name they needed was extracted —
  `apply_boss_hazards` needs `is_local_player_on_floor` from `modifiers`, and `modifiers`
  requires `boss`. Two ways out: move the shared helper into `core.lua`,
  or move `BOSS_PLAYER_MODIFIERS` so the `modifiers → boss` edge disappears. **The first was
  taken.** The second would have put Boss's own player catalog outside `boss.lua` to satisfy a
  four-line predicate, and that predicate is a plain read of Mario's state with no modifier
  meaning of its own — the same shape as `player_record_key`, which moved into `core.lua` for
  the same reason in R-001. With the helper in `core.lua` the hazards moved with no new require
  edge at all: `boss.lua` still requires only `core`.
- **Not every surviving mutation is a coverage gap; some are equivalent mutants.** Six of the
  66 mutations of the load-time self-check survived and none of them was a missing test. One
  clause of the check is redundant: `or modifier_data.kind == "auto_crouch"` cannot change the
  outcome, because `MODIFIER_KINDS` has no such key. The other five sit in three checks that
  call helpers file-local to the module they moved into, so a test cannot hand them a broken
  one and their failure branches are unreachable from the suite. Before writing a test to catch
  a survivor, work out whether the mutation changes behaviour at all — and record the ones that
  cannot, so the next sweep does not re-investigate them. Leave the code exactly as it is: a
  redundant clause discovered during a move is still not a move's business to delete.
  Bowser's hazards produced five more out of 97, and the reasoning for each is worth keeping so
  the next sweep does not redo it: three `if bowser == nil then return end` guards sit in
  helpers that only ever run after `apply_boss_hazards` has already returned on a nil Bowser,
  so no test can reach them; the `return` ending the intro branch is equivalent, because the
  branch sets `boss_hazard_seq = attack_seq` first and the sequence check below therefore
  returns anyway with both pending queues already emptied; and the fast-path
  `if attack_seq == local_runtime.boss_hazard_seq then return end` is equivalent, because
  `first_seq` then lands one past `attack_seq` and the replay loop runs zero times.
  Chaos's round loop produced four more out of 31, and all four are the same shape -- a
  default or a seed that no reachable state can reach. `alive_name`'s seed is never read,
  because the only expression that reads it, `alive_count == 1 and alive_name or "Nobody"`,
  uses it only when the loop has already assigned it; that also makes reducing that whole
  expression to `alive_name` equivalent. The `or 0` on `sh5_chaos_eliminated` is unreachable
  because `and` short-circuits and the only two writers of `sh5_enrolled = 1`, both inside
  `host_prepare_player`, each write `sh5_chaos_eliminated` in the same breath. The `or 0` on
  `sh5_chaos_roster_locked` is unreachable because `host_start_round` writes it before any
  round can be active, and the loop runs only inside an active round.

- **`selene` 0.31.0 is unusable — do not retry.** The Linux release only compiles the `lua51`
  and `luau` grammars and cannot parse this file's 5.4 syntax. Do not add a `selene.toml`.
- **A mutation sweep must restore the file after every single run.** A sweep that only
  restores at the end left `RESULT_DISPLAY_FRAMES = 2` applied to `round.lua` when the process
  was killed for memory. Restore immediately after each run and from a signal handler, and
  keep a pristine copy beside the sweep so `diff` can answer "is the file clean" in one
  command. Never read the target file while a sweep is running: it will show you a mutant and
  you will believe it.

- **A generated engine stub can silently disable a guard. Ten now.** `test/engine_stub.lua`
  returns `nil` from most engine functions, which is right for a function whose return value
  nothing reads and wrong for a predicate. `is_transition_playing()` returning `nil` meant every
  "hold this warp back while the level loads" guard could be deleted with no test noticing;
  it is now driven by `ctl.transition`. The same thing was true of
  `obj_get_first_with_behavior_id`, which returned `nil` and so made **the entire Boss attack
  queue unreachable**: with no Bowser object the host loop always decided he was not ready and
  returned before choosing an attack. Tests now supply the object through `ctl.objects`.
  `djui_popup_create_global` was discarding its second argument for the same reason, and
  `update_mod_menu_element_name` only recorded a rename that landed on a button that exists,
  so a call aimed at a nil index left no trace at all and the guard protecting engines with no
  mod menu could be deleted with the suite still green. Two more turned up with the interaction
  handlers: `obj_has_behavior_id` returned `false`, so `obj_has_behavior_id(o, id) == 0` was
  never true and the HMC Metal Cap portal guard could not fire, and `obj_get_first` returned
  nil, so the object walk inside `update_star_visibility` never ran a single iteration. Objects
  now carry `behavior_id`, and tests supply the level's contents through `ctl.level_objects`.
  Three more came with Bowser's hazards, and one is worse than an unreachable branch:
  `dist_between_objects` returned 0 for every pair, so `distance < 4800` was true whatever the
  two objects' positions were; `obj_scale` discarded its arguments, so every flame Bowser
  spawns was the same size and the three attacks that scale theirs differently could not be
  told apart; and `atan2s` returned `nil`, which does not disable hunter fire but **crashes**
  it, because the attack adds `0x0800` to the yaw it reads. All three now have real bodies.
  **When a mutation survives, check whether the stub made the branch unreachable before
  concluding the test is wrong.**

- **A harness stub of an engine function is a global, and lua-language-server merges it with
  the engine's own definition.** Giving `obj_get_first` and `obj_get_next` real bodies made the
  type checker read them as returning `unknown|nil`, which turned the untouched
  `object = obj_get_next(object)` walk in `goals.lua` into an `assign-type-mismatch` and raised
  the baseline from 10 problems in 2 files to 11 in 3. The fix is to annotate the stub with the
  engine's own `@return` type and suppress the mismatch inside the stub, not to touch the code
  that moved: sm64coopdx declares `@return Object` for both and returns NULL at the end of a
  list anyway, the same inaccuracy already recorded for `save_file_do_save(file, true)`.
- **A table of test callbacks must have uniform arity**, or lua-language-server reports
  `redundant-parameter` at the call site and the type-checker baseline rises -- which counts
  as a regression exactly like a new luacheck warning. A `cases` table whose `setup` entries
  were a mix of `function()` and `function(api)` did this; writing the unused ones as
  `function(_)` fixes it and luacheck accepts `_`. The type checker only sees it when the
  whole repository directory is passed, so run it before committing a new test suite, not
  only after moving code.
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

The two modules left, as measured on the released file:

| module | decls | ~lines |
|---|---|---|
| hud | 31 | 601 |
| menu | 18 | 250 |

Their heaviest references to modules that are already out:

```
hud   -> i18n       51      menu  -> i18n       23
hud   -> team       26      menu  -> modifiers  23
hud   -> modifiers  22
```

## Appendix: per-symbol assignment for the two remaining modules

**Machine-derived, not hand-verified**: seeded label propagation over the reference graph,
constrained so each state cluster stays whole. Line numbers refer to the **released** v1.1
file and are stale — re-derive every range with grep. Treat this as a starting point, never as
settled; `tools/module_deps.py` is what actually decides.

The appendix sections for the eleven extracted modules were deleted once those modules existed.
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
