# StarHunt test suite

    lua5.4 test/run.lua                  # everything
    lua5.4 test/run.lua audit difficulty # only matching suites

Requires `lua5.4`. The mod uses 5.3+ bitwise operators, so Lua 5.1 cannot even
parse it.

## How it works

The mod is written for sm64coopdx and cannot be loaded outside the game as-is,
so the suite supplies the engine instead:

| File | Role |
|---|---|
| `engine_stub.lua` | **Generated.** Exactly the 117 constants, 7 tables and 55 functions StarHunt uses, with the constants' real in-game values. |
| `harness.lua` | Replaces the inert stubs with doubles that record what the mod did, then loads the mod and returns `STARHUNT_TEST_API`. |
| `runner.lua` | Suites, assertions, reporting, exit status. |
| `suite/*.lua` | The tests. |

`harness.load()` re-executes the mod from disk every time, so one test cannot
leak synchronized state into the next.

The harness reproduces the game's `require()` rather than using Lua's: sm64coopdx
resolves a module name as a *path* relative to the folder of the file doing the
requiring, appends `.lua`, and caches per mod. A require path that would fail in
the game therefore fails here too.

### Regenerating the engine stub

    python3 tools/gen_engine_stub.py

It finds the engine surface by running luacheck over `StarHunt/` with no engine
globals configured and collecting every undefined variable, then resolves each
against sm64coopdx's `autogen/lua_definitions`. If the game adds or renames
something the mod uses, this is what picks it up. Run
`~/.local/share/sm64coopdx/refresh.sh` first to update the definitions.

## What is covered

| Suite | Guards |
|---|---|
| `catalog` | 93 goals, 32 modifiers, no 100-coin star, unique level/act, valid powers |
| `audit` | the 2,976-pair matrix and its 2,222/754 split, stage-1 and stage-2 rules, hand-tuned values surviving the rebuild |
| `selfcheck` | what `run_static_modifier_checks` refuses to let ship, checked one refusal at a time: a required power outside the four, a 100-coin star in any of the fifteen main courses, a goal with no modifiers, a kind outside the accepted 32, a cursed floor shorter than 4 or longer than 9 seconds, a hole anywhere in the 93 x 32 audit matrix, and a tally that does not add up. Every case also asserts the success banner is gone, which is what catches a branch that complains but forgets to fail |
| `difficulty` | Normal preserving v0.9 values, Easy pulses, monotonicity, and that no difficulty pushes a modifier past a stage-4 safety limit on any goal |
| `pairing` | all 496 pairs validated in both orders, the documented forbidden combinations, Nightmare finding a legal pair for every goal |
| `save` | the one-based to zero-based course conversion, per-act star bits, flushing |
| `caps` | the Wing/Metal/Vanish cap a goal requires: the right flags per power, none outside the goal's own level, act, round and mode, none for remote players, and the handing-back that DEVELOPMENT_CHECKLIST forbids undoing — a cap another mod granted, a cap it refreshed underneath StarHunt, the player's own cap timer and cap-on-head flag |
| `interact` | claiming a star and hiding the ones that are not it: the castle lock on doors, warp doors, the cannon and warps, the HMC Metal Cap portal and the three things that distinguish it from any other HMC warp, the star gate in each of the four modes, the coin toll in both a local and a remote player's slots, the rejection memory keyed on player, goal and round, Boss's one-hit-death modifier, and restoring only the invisibility flags StarHunt itself set |
| `hud` | no colon ever reaching `FONT_HUD`, which renders it as an X |
| `mechanics` | the load-time banner reporting success at all, darkness timing, Easy pulse width |
| `boss` | the reserve bomb wave: 0/0/2/4 by difficulty, distinct original positions, not armed before the native five are seen, one wave per round, host only |
| `boss_readers` | what the rest of the mod asks about a Boss round: the fight's own time range and its four player-count boundaries, which of Bowser's three modifier slots hold a given draw, the two conditions Desperate needs, the modifier name in each language, and the host reading back the lowest health any client reported |
| `boss_hazards` | Bowser's attacks as every client plays them: the four gates, Instant Knockout's one-kill-per-hit lock, the stun and the config menu it spares, an attack waiting through Bowser's absence rather than being consumed, the intro consuming one, the delayed second wave and the meteor fall, the ring's replay window and its wrap and its newest-slot fallback, and each of the nine attacks that create a hazard of their own |
| `round` | all sixteen mode/difficulty combinations, Bowser's 3/5/7/9 health, round length by lobby size, the waiting-room menu lock |
| `round_host` | what only the server decides: round length by lobby size, the goal pool and which star each player is handed, the winner tally and the records that survive a disconnect, reconnects and late joiners, the per-frame loop in each mode, Bowser's attack choice and the gaps between his attacks, and Chaos's survivor count, its roster lock and the last player standing |
| `round_client` | what a round does on each player's own machine: the warp home when it ends and the retry behind it, hiding players hunting a private variant of the same star, the pause menu refusing to quit mid-round, death costing exactly one forfeit in Normal and none in Boss or Chaos, and Bowser's intro textbox being cancelled |

## What is not covered

Everything that needs the real engine: rendering, networking between real
clients, warping, collision, palettes, and interaction with other mods. The
project documents are explicit that automated checks do not replace a real
multiplayer session in sm64coopdx, and that is still true.

The suite was mutation-checked: breaking the save conversion, the Easy pulse
width, the symmetric pair check, the Hard bomb count, and the HUD colon rule
each made it fail, with the failure naming the right thing.

Three lines of `run_static_modifier_checks` are the known exception, recorded in
`HISTORY.md`: its water-cap, A/B-swap and control-drift checks call helpers that
are file-local to `modules/modifiers.lua`, so no test can replace them with a
broken one. Only the shipped helpers are ever exercised there.

Five lines of Bowser's hazards are the other known exception, for the same kind
of reason: three `if bowser == nil then return end` guards sit in helpers that
only ever run after `apply_boss_hazards` has already returned on a nil Bowser,
and two early returns are equivalent to falling through to the check below them.
`REFACTOR_PLAN.md` carries the reasoning for each, so the next sweep does not
re-investigate them.

A stub that answers `nil`, `0` or `false` where the real engine answers something
meaningful can hide a whole area. Ten have been found so far. The most recent
three came with Bowser's hazards: `dist_between_objects` answered 0 for every
pair, so a shockwave stunned the player from any distance; `obj_scale` discarded
its arguments, so every flame was the same size; and `atan2s` answered `nil`,
which crashed hunter fire rather than merely disabling it. When a mutation
survives, check whether a stub made the branch unreachable before concluding the
test is wrong.
