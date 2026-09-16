# Refactor method: splitting `main.lua` into modules

Branch `refactor/modularize`. This document holds **how** to do the split correctly — the
rules, the verification discipline, and the traps that have already cost a session. It does
not track progress.

- **What is left, and in what order:** `ROADMAP.md` (item R-013).
- **What has already been done, and what it cost:** `HISTORY.md`.
- **What must not be broken while doing it:** `DEVELOPMENT_CHECKLIST.md`.

All thirteen modules now exist and **every one of them is finished.** `hud.lua` was the last,
and it came out in three passes: its text layer and the native HUD's visibility first, then
its picture layer -- `modifier_text`, the panel every card is built from, the health bar, the
score/timer strip, the objective panel and the Gun Mod repaint -- and finally its frame: the
start banner, the config menu's drawing, `draw_hud` itself and the round notifications.
`round.lua` is finished: its client half
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

Every module being finished is **not** the same as `main.lua` being empty of them. R-004's
audit found eight declarations that the `boss` and `goals` passes were meant to take and left
behind, and they are R-013; the appendix at the end of this document now lists them alongside
the five that were never assigned to a module at all. What stays in `main.lua` permanently is
the header, the require wiring, the hook block, the synchronized-table seed and
`STARHUNT_TEST_API`, plus the castle-grounds lobby cleanup the appendix explains.

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

**`menu.lua` came out before `hud.lua`, and the planned order was backwards.** `ROADMAP.md`
had `hud` first with `menu` blocked behind it. The scan said the opposite: the HUD block's only
dependencies still in `main.lua` were four menu declarations -- `config_option_count`,
`config_option_kind`, `config_status_text` and the selection -- while the menu block depended
on nothing outside the modules that already existed. Menu was the leaf, so menu went first.
**Run the scan before trusting the order in the roadmap**; the order past the modules already
extracted was planned from a reference graph, not measured.

`draw_config_menu` stays with the HUD, and that is now settled rather than open. It draws
through `draw_hud_text` and `measure_hud_text`, and the HUD's `draw_hud` calls it back, so a
`menu.lua` that owned it would be half of a require cycle. It reads `menu.lua`'s three option
functions instead, so the `hud -> menu` edge appears in the pass that moves it -- it does not
exist yet, because `draw_config_menu` has not moved.

The selection needed the migration step first, in its own commit: `config_selection` is
**rebound** on every press and `draw_config_menu` reads it, so it joined `config_open` on
`local_runtime`. `config_button_latch` and `config_stick_latched` are rebound too and were
left alone, because nothing outside the menu reads them -- migrate what crosses a boundary,
not every rebound local in the block.

**`hud.lua` came out in two ranges and needs only `core`.** The first pass took the text
layer -- `format_remaining_time`, `measure_hud_text`, `draw_hud_text`,
`draw_centered_hud_text`, `Team.objective_text_max_width` and
`Team.draw_scaled_centered_text` -- together with `apply_counter_visibility`,
`update_native_hud_visibility`, `Team.draw_darkness_behind` and
`hide_native_hud_before_render` -- eleven declarations in one contiguous block -- plus the two state locals
`local_hud_flags_before_round` and `local_counter_round_active`, which sat with the other
`local_*` declarations at the top of the file and are read nowhere but
`apply_counter_visibility`. The scan named five dependencies and all five are in `core`, so
the new file's only import is `core` -- no `i18n`, no `menu`, no `round`. Nothing requires
`hud`, so it can import anything later.

**The second pass took the picture layer and gave `hud.lua` its first imports.**
`Team.darkness_active` and `modifier_text` came out together, and the panels --
`Team.draw_hud_panel`, `Team.health_wedges`, `Team.health_color`, `draw_player_health_bar`,
`Team.draw_round_status_panels`, `Team.draw_objective_panel` and
`Team.draw_gun_mod_hud_compatibility` -- as one contiguous block below them. The scan named
ten dependencies and every one was already imported by `main.lua` from a module that exists,
so the file gained `i18n`, `goals` and `boss` alongside `core`, and no cycle: nothing
requires `hud`. `main.lua`'s `local BOSS_MODIFIER_FIELDS` had no reader left afterwards and
went with it.

**The third pass took the frame and finished the module.** `draw_start_banner`,
`draw_config_menu`, `draw_hud` and `local_round_notifications` were one contiguous range in
`main.lua` and moved as one piece, with `START_BANNER_FRAMES` and the three state locals
`local_seen_round`, `local_seen_result` and `local_start_banner_until`. They had to travel
together: `draw_hud` calls the banner and the menu, and the notifications rebind the frame
the banner reads, so the alternative was migrating that local onto `local_runtime` first in
its own commit, the way `config_selection` was. The scan named five new dependencies and they
added the two edges the plan had predicted -- `configured_time_range` and
`connected_player_count` from `round`, and the three option functions from `menu` -- so
`hud.lua` requires `core`, `i18n`, `goals`, `boss`, `round` and `menu`, and there is still no
cycle because nothing requires `hud`. It also reported `boss` as a dependency, which was a
false positive: `module_deps.py` matched the word inside the string literal
`"boss defeated"`. `main.lua`'s three `menu` option bindings had no reader left afterwards
and went with the move.

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
   menu      -> core, i18n, round  so round may not require menu
   hud       -> core, i18n, goals, boss, round, menu
   ```

   Nothing requires `hud`, which is why it could take the two edges above without a cycle
   and why it is the only module that may import anything.

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
   coverage gap in **eighteen of the twenty** passes so far. The HUD's frame was the last of
   them: a ten-mutation spot check caught nothing at all, because `test/suite/hud.lua` reached
   `draw_hud` exactly once inside a `pcall` that only checked no colon had gone to the font,
   `test/suite/menu.lua` tests what the menu does when a button is pressed rather than what it
   draws, and nothing tested the banner or the winner announcements. **Four of the gaps it
   found were reachable only on a client**, which is worth carrying forward: the host fills
   `sh5_round`, `sh5_result_seq` and both team scores in with zero in its load-time block, so
   on a host the `or 0` defaults applied to those fields can never fire.
   `harness.load(function(c) c.is_server = false end)` is the fixture that reaches them.
   The HUD's picture layer is
   the worst of them by a wide margin: **500 of 507 mutations survived**, and the only seven
   the suite caught were caught by the darkness and health-colour tests written for the pass
   before it. Three more engine stubs were hiding it: `djui_hud_render_rect` kept only the
   last rectangle and `djui_hud_render_texture` only a count, so a panel -- which is a stack
   of rectangles -- could be moved, resized or recoloured unobserved, and `gTextures` was
   empty, which put the star and the coin icons behind a guard no test could satisfy. Before
   that its text layer: **77 of 80 mutations survived**, and the only three the
   suite caught were caught by the colon tests. Four of its functions --
   `counter_visibility`, `native_hud_visibility`, `hide_native_hud_before_render` and
   `draw_darkness_behind` -- were published in `STARHUNT_TEST_API` and called by no test at
   all, and five engine stubs made them unobservable even in principle. Before that the
   config menu: `update_config_input` -- every key a player can press -- was published in
   `STARHUNT_TEST_API` and called by no test at all, and of 67 mutations 18 survived the first
   green run. Before that the Chaos round
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
  The config menu produced four more out of 67, and three of them are clauses that a second,
  outer check has already settled. `if Team.language < 0 then ... end` after
  `(Team.language + delta) % #Team.language_codes` is unreachable, because Lua's `%` follows
  the sign of the divisor and never returns a negative for a positive one -- the same is true
  of the identical guards in `Team.cycle_mode` and `Team.cycle_difficulty`. The
  `and network_is_server()` on the mode, difficulty and time branches cannot change the
  outcome, because `config_option_kind` only ever names those three rows inside its own
  `network_is_server()` branch, so a client's `option` is never one of them. And the `clamp`
  the menu applies before calling `host_start_round` is redundant, because `host_start_round`
  clamps its own argument against the same range on its second line. The fourth,
  `Team.set_config_menu_open(true)` after `host_end_round`, is a no-op: nothing outside
  menu.lua writes `config_open`, and the branch it sits in only runs while the menu is open.
  **Leave all four exactly as they are.** A redundant clause found during a move is still not
  a move's business to delete, and three of these are the cheap outer half of a
  belt-and-braces pair that would be expensive to get wrong later.
  Chaos's round loop produced four more out of 31, and all four are the same shape -- a
  default or a seed that no reachable state can reach. `alive_name`'s seed is never read,
  because the only expression that reads it, `alive_count == 1 and alive_name or "Nobody"`,
  uses it only when the loop has already assigned it; that also makes reducing that whole
  expression to `alive_name` equivalent. The `or 0` on `sh5_chaos_eliminated` is unreachable
  because `and` short-circuits and the only two writers of `sh5_enrolled = 1`, both inside
  `host_prepare_player`, each write `sh5_chaos_eliminated` in the same breath. The `or 0` on
  `sh5_chaos_roster_locked` is unreachable because `host_start_round` writes it before any
  round can be active, and the loop runs only inside an active round.
  The HUD's picture layer produced four more out of 507, and all four are in one line:
  `Team.health_wedges` is `clamp(math.floor(clamp(health or 0x880, 0, 0x880) / 0x100), 0, 8)`,
  and the outer clamp, the inner clamp's own bounds and the `or 0x880` default overlap so
  completely that raising any one of them changes nothing. Checked exhaustively rather than
  argued: each of the four mutants agrees with the original on `nil` and on every integer
  from -5,000 to 20,000. The redundancy is deliberate belt and braces around a health value
  that arrives from the engine, so **leave all four exactly as they are**.
  The HUD's frame produced six more out of 238, and they fall into three shapes. Four are
  bare `local` declarations with no initializer -- `local text` and `local mode_value` in
  `draw_config_menu`, `local controls` below them, and `local winner_message` in
  `local_round_notifications`. Deleting one turns the name into a global, but every branch of
  the chain beneath it assigns the variable before anything reads it (each chain ends in an
  `else`), so no reachable state can tell the difference. The fifth is the fallback index in
  `Team.menu_lock_labels[Team.language + 1] or Team.menu_lock_labels[1]`: all three writers of
  `Team.language` keep it inside 0 to 5 -- `i18n.lua` clamps with `math.max`/`math.min`, the
  menu uses `% #Team.language_codes`, and the test API's `set_language` clamps -- and
  `menu_lock_labels` has six entries, so the lookup never misses and the fallback is
  unreachable. The sixth is the floor of `math.max(0, ...)` on the frames remaining in
  `draw_hud`: the value reaches nothing but `format_remaining_time`, and that returns `"0:00"`
  for both 0 and 1, so raising the floor changes nothing on screen. **Leave all six exactly as
  they are.**
  The HUD's text layer produced three more out of 80, and all three are guards or seeds that
  no reachable state reaches. `local_hud_flags_before_round` starts as `nil` and is released
  back to `nil`, and the only expression that reads it,
  `local_hud_flags_before_round or flags`, runs inside the `elseif local_counter_round_active`
  branch -- and `local_counter_round_active` is only ever set true on the line straight after
  the save, so neither the initial value nor the released one can be read. The `text_width > 0`
  guard in `Team.draw_scaled_centered_text` protects a division by zero that needs a negative
  `maximum_width` to reach, and every caller passes either a positive literal or
  `Team.objective_text_max_width()`, which has a floor of 24. **Leave all three as they are**,
  and note that the two `nil`s are the kind of clause worth keeping: they are cheap, and they
  are what makes the read at the bottom safe if a later pass ever reorders those branches.

- **`selene` 0.31.0 is unusable — do not retry.** The Linux release only compiles the `lua51`
  and `luau` grammars and cannot parse this file's 5.4 syntax. Do not add a `selene.toml`.
- **A mutation sweep must restore the file after every single run.** A sweep that only
  restores at the end left `RESULT_DISPLAY_FRAMES = 2` applied to `round.lua` when the process
  was killed for memory. Restore immediately after each run and from a signal handler, and
  keep a pristine copy beside the sweep so `diff` can answer "is the file clean" in one
  command. Never read the target file while a sweep is running: it will show you a mutant and
  you will believe it.

- **A generated engine stub can silently disable a guard. Seventeen now.** `test/engine_stub.lua`
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
  Seven more came with the HUD, and together they are the largest single case of this so far:
  `hud_get_value` answered 0 for every display value, `hud_set_value` threw the write away,
  and `hud_hide`, `hud_show` and `hud_is_hidden` were a no-op, a no-op and a constant `false`.
  Between them they made the whole of `apply_counter_visibility` and
  `update_native_hud_visibility` unobservable -- the star and coin counters StarHunt saves
  before a round and restores after it could have been deleted outright, and so could the
  code that gives the player back a native HUD they had hidden themselves. Tests now set
  `ctl.hud.values` and `ctl.hud.hidden` and read the same two back. `djui_hud_render_rect`
  discarded the rectangle's position and size, so a darkness rectangle ten pixels wide looked
  exactly like one covering the screen, and `djui_hud_set_resolution` discarded the
  resolution; both now record what they were given.
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

The HUD, as measured on the released file, was 31 declarations and about 601 lines -- 30 of
them really, since one of the 31 turned out to be a translation table that had gone to
`i18n.lua` passes earlier. All 30 are now in `modules/hud.lua`, which came out in three
passes:

| part of hud | decls | ~lines |
|---|---|---|
| text layer and native-HUD visibility | 13 | 131 |
| panels: health bar, status strip, objective, Gun Mod repaint | 9 | ~306 |
| frame: banner, config menu, `draw_hud`, notifications | 8 | ~181 |

The heavy couplings the graph predicted were all in the last two passes, and none of them
needed a new mechanism -- `i18n`, `goals` and `boss` arrived with the panels, and `round` and
`menu` with the frame:

```
hud   -> i18n       51
hud   -> team       26
hud   -> modifiers  22
```

`team` and `modifiers` never became require edges at all: everything the HUD reads from them
is a field on the shared `Team` table, which every module reaches by reference.

## Appendix: what is left in `main.lua`

The original appendix was **machine-derived, not hand-verified**: seeded label propagation
over the reference graph, constrained so each state cluster stays whole. Its per-module
sections were deleted as those modules came out and are in git history if ever needed. Treat
anything left of it as a starting point, never as settled; `tools/module_deps.py` is what
actually decides.

What follows is no longer a plan. It is the record R-004 produced: a decision, with a reason,
for every top-level declaration still in `main.lua`.

Two things to know when reading it:

- **High-fan-in predicates look misplaced and are not.** `translated`, `is_round_active`,
  `is_boss_mode`, `Team.is_chaos_mode`, `Team.selected_difficulty` and `Team.periodic_window`
  each have most of their graph neighbours outside their own module, because they are used
  everywhere. They belong where they are semantically. 46 declarations show this pattern.
- **The seed artifacts are all settled now.** `on_joined_game` landed in `i18n` because it
  calls `translated`, but it is a hook callback and stayed with the hook block in `main.lua`.
  `draw_config_menu` stayed in `hud`, because the HUD's own text helpers and its `draw_hud`
  are on both sides of it. And `Team.freeze_menu_mario`, which the appendix suggested
  reconsidering against `modifiers`, went to `menu` -- it pins Mario only while the config
  menu is open, reads nothing from `modifiers`, and has no caller but the menu and the hook
  block.

### What is still in `main.lua`, and why — settled by R-004

R-004 audited every top-level declaration left in `main.lua` and recorded a decision for each.
The audit found two separate groups, not one. Lines below are in the **current** file.

**Group one: the five the appendix never assigned. All five stay, and that is the decision.**

| decl | line | why it stays |
|---|---|---|
| `gServerSettings.skipIntro = 1` | 19 | A load-time engine setting rather than behavior. `main.lua` already owns the mod's engine wiring — the hook block and the synchronized-table seed — and this belongs with it. It is also the first third of one idea: skip the opening scene, delete the Lakitu that plays it, delete the one that is already there. |
| `local_lakitu_scan_at` | 106 | Rebound, but only by the one function that reads it, so the shared-state rule does not force it onto `local_runtime` or anywhere else. |
| `remove_castle_lakitu` | 368 | Castle-grounds cleanup that belongs to no StarHunt system: it runs whether or not a round is active, reads no synchronized field, and has no caller but its hook. |
| `remove_existing_castle_lakitu` | 382 | Same, and it is the retroactive half of the same idea — `HOOK_ON_OBJECT_LOAD` does not fire for objects that loaded before the mod was enabled. |
| `on_find_water_level` | 390 | Five lines that return their own argument, for the same reason: the castle moat is lobby furniture, not a StarHunt system. |

A `modules/lobby.lua` was considered and rejected. It would hold one variable and three short
functions whose only reader is the hook block, so the `require` line would cost about what the
code does, and `DEVELOPMENT_CHECKLIST.md`'s code map already points at `main.lua` for them.
The reason to keep a decision rather than a habit is that these are now **tested**:
`test/suite/lobby.lua` covers all four, and the whole group survived a 29-mutation sweep with
every mutation caught.

**Group two: eight declarations the `boss` and `goals` passes were meant to take and left
behind.** These are *not* a decision to stay — they are an oversight the audit found, and they
are R-013 in `ROADMAP.md`. Each was checked against the real require graph, so none of them
needs a new edge:

| decl | line | goes to | checked |
|---|---|---|---|
| `Team.lifetime` | 107 | `goals.lua` | `goals.lua:817-819` is the only code that increments and persists it |
| `Team.update_lifetime_sync` | 115 | `goals.lua` | its only caller is `goals.lua:819`; needs nothing but `gPlayerSyncTable` |
| `Team.pick_second_modifier` | 119 | `modifiers.lua` | reaches `Team.chaos_pair_allowed` and `Team.difficulty_modifier_allowed` as `Team` fields, so nothing blocks it anywhere; the appendix said `goals`, but the decision it makes is the modifier catalog's, not a star's |
| `Team.boss_reserve_bomb_count` | 132 | `boss.lua` | `Team` fields only |
| `Team.host_update_boss_bomb_supply` | 142 | `boss.lua` | needs `FRAMES_PER_SECOND`, `is_round_active`, `is_boss_mode` from `core`, which `boss.lua` already requires, and `Team.bossBombPositions`, which is already in `boss.lua` |
| `ensure_boss_health_owner` + the four `local_boss_health_*` locals | 109-112, 210 | `boss.lua` | `core` plus `Team.boss_max_health`, already there. The four locals are read nowhere else and travel with it |
| `on_before_boss_cutscene` | 266 | `round.lua`, **not** `boss.lua` | it calls `host_end_round`, and the graph already runs `round -> boss`, so an edge back would be a cycle |
| `local_goal_warp_update`, `local_boss_warp_update` | 280, 317 | `round.lua` | the client half of the round loop. Between them they need `get_goal`, `BOSS_LEVELS` and `reset_local_modifier_state`, and `round.lua` already requires `goals`, `boss` and `modifiers` |

`on_joined_game` (397) is a ninth leftover that was already decided: the note above records
that the appendix put it in `i18n` because it calls `translated`, and that it stayed in
`main.lua` as a hook callback. R-004 confirmed that decision rather than reopening it — it
reaches `Team.update_config_menu_lock` from the menu, `Team.is_chaos_mode` from chaos and
`is_round_active` from core, and belongs to none of the three.

**The lesson for R-013 and for any pass after it.** "The module is finished" was asserted five
times in this document on the strength of the planned block being out, and each time it was
true of the block and not of the file. The check that would have caught it is one grep, and it
is cheap enough to run at the end of every pass:

```bash
grep -n '^local function \|^Team\.[a-z_]* = function\|^local [a-z_]* =' StarHunt/main.lua
```

Anything in that list that is not the header, an import, a hook callback with a recorded
reason, or `STARHUNT_TEST_API` is unfinished work.
