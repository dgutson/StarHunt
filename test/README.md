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
| `difficulty` | Normal preserving v0.9 values, Easy pulses, monotonicity, and that no difficulty pushes a modifier past a stage-4 safety limit on any goal |
| `pairing` | all 496 pairs validated in both orders, the documented forbidden combinations, Nightmare finding a legal pair for every goal |
| `save` | the one-based to zero-based course conversion, per-act star bits, flushing |
| `hud` | no colon ever reaching `FONT_HUD`, which renders it as an X |
| `mechanics` | the load-time self-checks, darkness timing, Easy pulse width |
| `boss` | the reserve bomb wave: 0/0/2/4 by difficulty, distinct original positions, not armed before the native five are seen, one wave per round, host only |
| `round` | all sixteen mode/difficulty combinations, Bowser's 3/5/7/9 health, round length by lobby size, the waiting-room menu lock |
| `round_client` | what a round does on each player's own machine: the warp home when it ends and the retry behind it, hiding players hunting a private variant of the same star, the pause menu refusing to quit mid-round, death costing exactly one forfeit in Normal and none in Boss or Chaos, and Bowser's intro textbox being cancelled |

## What is not covered

Everything that needs the real engine: rendering, networking between real
clients, warping, collision, palettes, and interaction with other mods. The
project documents are explicit that automated checks do not replace a real
multiplayer session in sm64coopdx, and that is still true.

The suite was mutation-checked: breaking the save conversion, the Easy pulse
width, the symmetric pair check, the Hard bomb count, and the HUD colon rule
each made it fail, with the failure naming the right thing.
