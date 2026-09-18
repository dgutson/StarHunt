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
| `engine_stub.lua` | **Generated.** Exactly the 118 constants, 7 tables and 55 functions StarHunt uses, with the constants' real in-game values. |
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
| `lobby` | the castle grounds, which belong to no StarHunt system: the opening scene switched off at load, the camera Lakitu deleted as it loads and the retroactive scan that catches the one already there, both refusing to act away from the grounds or on another behavior, the fifteen-frame gap between scans, and the water-level hook handing back the height it was given rather than a fixed one |
| `lifetime` | the lifetime star count: the stored total read at load and published into the local player's slot only, a first run with nothing stored, a stored value that is not a number, a negative one clamped and a fractional one floored, the republish that puts the total back when the synchronized value is lost, and claiming a star raising, saving and republishing it while a star that is not the goal leaves it alone |
| `hud` | no colon ever reaching `FONT_HUD`, which renders it as an X; where a colon's two dots land and how they scale; what a string measures so it can be centered on it; the objective panel's width between the score and timer cards; shrinking text to its box; the clock; the star and coin counters saved before a round and restored after it, including one the player already had off; the native HUD hidden for the round and left alone outside it; and the DARKNESS PULSE rectangle, drawn once a frame and only while the pulse is dark |
| `hud_panels` | the HUD's picture layer: every modifier's name in English, Spanish and Portuguese including the four families the later languages build by rule; the three rectangles a panel is made of; the health bar's wedges, its colours and its two thresholds; the score, Team, Chaos and Bowser cards and the timer and coin card they all share; the objective panel in each mode, its two modifier lines, the jump and coin-toll counters and the row they move to; the Chaos reroll countdown and the eliminated notice; and the Gun Mod repaint with each of the eight conditions that stop it |
| `hud_frame` | the HUD's frame: the start banner, its three layers and its 105-frame window; the config menu's picture, its box on a host and on a client, its rows and their spacing, the selected row's bar, the locked and dimmed rows, the range hint and the footer; the winner announcement in each of the four modes and each of Boss's and Chaos's reasons; and what `draw_hud` assembles in each case, including the menu drawn over the round's panels rather than instead of them |
| `menu` | the /starhunt config menu: six options for the host and two for everyone else, the selection and both its wrap points, the stick's two thresholds and its latch, the language, mode, difficulty and round length each option edits, the three that are locked during a round, starting and stopping from the bottom row, the controller the menu takes from Mario and the position it pins him at, and the three arguments of the chat command |
| `mechanics` | the load-time banner reporting success at all, darkness timing, Easy pulse width |
| `boss` | the reserve bomb wave: 0/0/2/4 by difficulty, distinct original positions, not armed before the native five are seen, one wave per round even a second later, host only, the host's own level rather than a straggler's, a wait that does not carry between rounds or across a fresh sighting, one bomb on the field not counting as an empty arena, what each reserve bomb is and where its home is, and a failed spawn being left unpublished so the missing bombs can be supplied later |
| `boss_health` | Bowser's health under dynamic object ownership: who may write it and who may not, a sync id that is missing or still zero, the pool per difficulty and the synchronized override, a round another player has already claimed never being healed back and never left above the authoritative value, the scan across every player slot and the round it is keyed to, initialization happening once per object, and the publication -- its clamp, its round number, its own slot only, and the five-frame heartbeat |
| `boss_readers` | what the rest of the mod asks about a Boss round: the fight's own time range and its four player-count boundaries, which of Bowser's three modifier slots hold a given draw, the two conditions Desperate needs, the modifier name in each language, and the host reading back the lowest health any client reported |
| `boss_hazards` | Bowser's attacks as every client plays them: the four gates, Instant Knockout's one-kill-per-hit lock, the stun and the config menu it spares, an attack waiting through Bowser's absence rather than being consumed, the intro consuming one, the delayed second wave and the meteor fall, the ring's replay window and its wrap and its newest-slot fallback, both halves of a grab -- the spin and the throw -- consuming an attack and dropping what was in flight, and the actions either side of the throw still attacking, and each of the nine attacks that create a hazard of their own |
| `round` | all sixteen mode/difficulty combinations, Bowser's 3/5/7/9 health, round length by lobby size, the waiting-room menu lock |
| `round_host` | what only the server decides: round length by lobby size, the goal pool and which star each player is handed, the winner tally and the records that survive a disconnect, reconnects and late joiners, the per-frame loop in each mode, Bowser's attack choice and the gaps between his attacks, the attacks held back while a player has hold of him and through the throw that ends the grab, and resumed when he lands, and Chaos's survivor count, its roster lock and the last player standing |
| `round_client` | what a round does on each player's own machine: the warp home when it ends and the retry behind it, hiding players hunting a private variant of the same star, the pause menu refusing to quit mid-round, death costing exactly one forfeit in Normal and none in Boss or Chaos, Bowser's intro textbox being cancelled, the warp to each new star and into Bowser's arena with the three-second pause before it, Tick Tock Clock's speed being set for the star that was drawn, the in-place respawn that revives a dead player without reloading the arena around the others, and the fallback that reports a Bowser beaten by some other mod's rules |

## What is not covered

Everything that needs the real engine: rendering, networking between real
clients, warping, collision, palettes, and interaction with other mods. The
project documents are explicit that automated checks do not replace a real
multiplayer session in sm64coopdx, and that is still true.

The suite is mutation-checked: breaking the save conversion, the Easy pulse
width, the symmetric pair check, the Hard bomb count or the HUD colon rule each
makes it fail, with the failure naming the right thing.

The table above is **not complete**: `core`, `i18n`, `team`, `world` and
`modifiers` run in `test/run.lua` and have no row here.

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
meaningful can hide a whole area: a `dist_between_objects` that answers 0 for
every pair lets a shockwave stun the player from any distance, an `obj_scale`
that discards its arguments makes every flame the same size, and an `atan2s`
that answers `nil` crashes hunter fire rather than merely disabling it. When a
mutation
survives, check whether a stub made the branch unreachable before concluding the
test is wrong.
