---
name: starhunt-testing
description: >-
  How to verify any change to StarHunt. Holds the five checks in order with their exact
  commands, what each one is expected to report, which of those reports are correct code
  rather than bugs, the mutation sweep, and test/live/run.sh, which runs the mod inside real
  headless sm64coopdx processes. These commands exist nowhere else in the repository —
  CLAUDE.md and DEVELOPMENT_CHECKLIST.md both point here — so load this skill instead of
  guessing a command, a flag or what a clean run looks like. Use it whenever a change to StarHunt has to be verified,
  before opening a pull request, when asked to run the tests, the suite, luacheck,
  lua-language-server, a mutation sweep, or to check that something works in the real game,
  and when adding a case to the offline suite or the live harness. Use it even when testing
  was never mentioned, because every edit under StarHunt/ or test/ ends in these checks. Use
  it too whenever a check reports numbers that differ from the baselines, or the live
  harness fails, times out or hangs, because nearly every failure mode there is sm64coopdx
  behaviour rather than a bug in the mod, and this skill names those with the engine source
  lines that settle them.
---

# Testing StarHunt

Run every command from the repository root, `/home/dfg/src/StarHunt_v1.1`.

Five checks, cheapest first. The four static ones apply to every change. The live harness
applies when a change touches what two players share — collision, warping, the sync tables,
loading, the module `require` graph. A change is verified when each check holds its number.

| # | check | command | expected | takes |
|---|---|---|---|---|
| 1 | syntax | `lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"` | no output | instant |
| 2 | suite | `lua5.4 test/run.lua` | `0 failed`, every suite in the list run | ~1 min |
| 3 | lint | `luacheck StarHunt/ test/` | `0 errors`, and only the two warnings named below | seconds |
| 4 | types | `lua-language-server --check /home/dfg/src/StarHunt_v1.1 --checklevel=Warning --logpath=/tmp/lls-log` | only the reports named below, all in two files | ~15s |
| 5 | live | `test/live/run.sh` | `PASSED`, and a verdict from both players for every case | ~1 min |

**Anything a run reports that this file does not account for is a regression**, and so is a
check that reports less than it should — a suite that stops loading, a live case that prints
no verdict. Quote what the run printed in the pull request. A change that adds or moves code
also needs the mutation sweep, below — a green suite says nothing about lines no test
reaches.

## 1. Syntax, with lua5.4 and never lua

```bash
lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"
```

`lua` on this machine is the 5.1 alternative. It cannot parse the `|`, `&` and `~` operators
`hud.lua` and `save.lua` use, so it reports a syntax error in correct code. This loads
`main.lua` alone; the modules are parsed by the suite.

## 2. The offline suite

```bash
lua5.4 test/run.lua                    # every suite
lua5.4 test/run.lua audit difficulty   # only matching suites, for a quick loop
```

It loads the mod outside the game against `test/engine_stub.lua` — a generated stand-in for
exactly the engine surface the mod uses, with the constants' real in-game values — and drives
it through `STARHUNT_TEST_API`. `test/README.md` lists what each suite guards and how the
harness reproduces the game's `require`.

**A function a test calls must be exported from its own module and added to
`STARHUNT_TEST_API` in `main.lua`.** The harness reaches functions by name in that table, so
reordering hooks cannot silently move a test onto a different function.

**Publication in that table is not coverage.** `grep` the key across `test/suite/` before
believing a function is tested; a function can be published and called by nothing.

**A stub that answers `nil`, `0` or `false` where the real engine answers something
meaningful hides everything that depends on it.** `dist_between_objects` answering 0 for
every pair makes every distance test pass. When a mutation survives, check whether the stub
made the branch unreachable before concluding the test is wrong.

Regenerate the stub when the game's API moves, after the refresh in check 4:

```bash
python3 tools/gen_engine_stub.py
```

## 3. luacheck

```bash
luacheck StarHunt/ test/
```

The two expected warnings are an inner `draw_layer` in `hud.lua` shadowing its enclosing
`draw_hud_text`'s `alpha` argument, and the empty `if` branch in `modifiers.lua` for
`coin_toll` and `darkness_pulse`, whose effects are applied in star interaction and the HUD
rather than in `apply_local_modifier`.

Inside `goals.lua`, local variables named `goal` shadow the file-local `goal()` constructor,
so a mistyped `goal(...)` call in such a scope is a runtime error rather than a lint error.
Luacheck will not catch it.

## 4. lua-language-server

```bash
lua-language-server --check /home/dfg/src/StarHunt_v1.1 --checklevel=Warning --logpath=/tmp/lls-log
```

**Pass the directory.** Given a file path it reports "no problems found" whatever the code
contains, which reads exactly like a pass.

The expected problems are in `StarHunt/modules/save.lua` and `test/harness.lua`, and in no
other file. `.luarc.json` disables `different-requires`, because the engine's definitions and
the mod both define names the checker would otherwise pair up.

A clean run also confirms something the suite cannot: every engine symbol the mod uses still
exists in the sm64coopdx being targeted, because both checkers read a generated copy of the
engine's own API.

### Judging a type report against the engine, not the annotation

Every `save.lua` report is `save_file_do_save(file, true)` — "cannot assign `boolean` to
parameter `integer`". The annotation says `integer`, but `smlua_to_integer` converts a
boolean itself, `true` to 1 (`src/pc/lua/smlua_utils.c:95-98`). The call is correct.

Those in `test/harness.lua` are the stub's partial `MarioState`, `Area`, `Controller`,
`MarioBodyState`, `PlayerCameraState` and `Camera` tables, plus `marioObj = nil`. The stub
supplies the fields the mod reads, not the whole struct, so completing them would be work
with no test behind it.

Read the binding code before treating a new report as a bug, since the annotations are
narrower than the conversions. `smlua_to_lua_function` returns 0 for `LUA_TNIL`
(`src/pc/lua/smlua_utils.c:144-147`), so passing `nil` where a `function` is annotated — as
`boss.lua` does for a setup callback — is the intended way to pass none.

### An undefined global means stale definitions, not a broken mod

```bash
~/.local/share/sm64coopdx/refresh.sh
```

Both checkers read the generated API under `~/.local/share/sm64coopdx/`, so a game rebuilt
from a newer upstream needs this before either check means anything. Read
`references/engine-api.md` only if the refresh does not settle it.

`selene` is installed and cannot be used here: its 0.31.0 Linux release compiles only the
`lua51` and `luau` grammars, so it cannot parse this project's 5.4 syntax. Do not add a
`selene.toml`.

## 5. The live harness

```bash
test/live/run.sh --load-only     # one instance: does the mod load, do the modules resolve (~40s)
test/live/run.sh                 # a referee and two players: the collision cases (~1 min)
test/live/run.sh --without r030  # prove the run can go red; must exit 0
```

Exit 0 is a pass, 1 a failure, 2 a missing game or ROM. It prints every `PROBE` line and
names the directory holding the full logs. `COOPDX`, `ROM`, `PORT`, `TIMEOUT`, `JOIN_DELAY`,
`PAIR_DELAY` and `WORK` override the binary, the ROM, the port, the deadline, the two join
delays and the scratch directory; on this machine the defaults are already right.

A full run ends with `PASSED:` and one `PROBE verdict` line per player per case:
`split passed_through=true`, `hidden passed_through=true`, `shared passed_through=false`,
`ddd passed_through=false` and `wdw passed_through=false`. Both players also print a
`PROBE saveflags` line, and the two must carry the same `ddd_gate` value. `run.sh` waits for
the referee's `PROBE end role=server`, which it prints once every player has reported every
case, and then checks each case by name — so a case added to the probe and not to the verdict
block in `run.sh` runs, prints its verdict and is never judged.

### Before citing a green run as evidence

```bash
test/live/run.sh --without r030
```

A harness that stays green with the fix removed is worse than none, because it gets quoted.
This removes the `INTERACT_PLAYER` branch of `on_allow_interact` in `modules/goals.lua` and
inverts the run: it requires the `hidden` case to go red while the control still holds, so
exit 0 means the removal was noticed.

**Never edit `StarHunt/` by hand to do this.** `run.sh` applies the removal to each
instance's own copy of the mod, after the copy and before the game starts, so the working
tree and its hash are untouched — the same rule `tools/sweep_mutations.py` follows, because
an interrupted run that edits in place leaves a half-applied change behind.

### Reading a failure

The `gates` line, printed halfway through each measurement, names every gate in
`interact_player` and `resolve_player_collision` that Lua can read. Read it before forming a
theory, and add to it rather than removing from it.

| what you see | what it means |
|---|---|
| `active_them=0` | the engine refused before StarHunt was asked — compare `my_act` with `their_act` and `my_area` with `their_area` |
| `collided=false` with `active_them=1` | the bodies never touched; check `dist` and whether the placement worked |
| `their_pos_valid=false` | positions are not being exchanged, so `their_xz` is stale and any distance to that body is meaningless |
| `dy` above 160 | one hitbox height apart vertically, which `resolve_player_collision` refuses outright |
| `drift=0.0` in `shared` | the control did not collide; the run proves nothing about the other two |
| every gate open but no push | look at where they are standing — a push whose landing point has no floor is abandoned |

**If the run times out with no verdicts at all**, the game never reached the probe. Read
`$WORK/*.log`, whose path `run.sh` prints, rather than the `PROBE` lines:

- `could not find valid vanilla us sm64 rom` — the ROM is missing or is not a vanilla US copy.
- the log stops after three config lines — the mods did not load; check the folder names under
  `$WORK/<name>/mods/` against the `--enable-mod` arguments.
- `PROBE waiting ... reason=...` repeating — the probe is alive and stuck, and the reason names
  where.
- nothing after the banner — an instance died. Clean up orphans with `pkill -x sm64coopdx`;
  `pkill -f` matches the shell running it and would kill your own session.

**Nearly every other way this run misbehaves is sm64coopdx behaviour rather than a bug in the
mod.** `references/live-harness.md` holds those: why the harness needs three processes, what
each case measures, the engine constraints that fix its shape, and the traps already worked
around in `run.sh` and the probe. Read it before changing anything under `test/live/`, and
before concluding the mod is at fault.

## The mutation sweep

Run this over the lines a change touched, or the change is unverified however green the suite
is. A surviving mutation means the line is untested or the mutation cannot change behaviour;
both need a decision.

```bash
python3 tools/gen_mutations.py StarHunt/modules/round.lua 787,885
WORKERS=2 python3 tools/sweep_mutations.py round_client     # one suite, much faster
ONLY=2,5,6-8 WORKERS=2 python3 tools/sweep_mutations.py     # re-run named survivors
```

Derive the line range **after** the last edit to the file, or it is off by the lines that were
added. Run the sweep in the **foreground** with `WORKERS=2`: a background sweep on this machine
gets killed for low memory, and each worker copies the tree, so the working tree is never
mutated.

`REFACTOR_PLAN.md` lists the mutations already judged equivalent, so a sweep does not
re-investigate them.

## Adding a case

To the offline suite: a file in `test/suite/`, the function exported from its module and added
to `STARHUNT_TEST_API`. `test/README.md` has the conventions.

To the live harness: five places in a fixed order, described in `references/live-harness.md`.
A live case is only worth writing for something the stubs cannot reach — two real players
meeting, a warp, the mod loading. Everything else belongs offline, where it costs seconds.

## What none of this reaches

Rendering, the HUD, anything a person looks at, real latency, packet loss, and every
third-party mod. Three processes on one machine over the loopback is not a real session. A
real multiplayer session with real people is still the last check before a release, and a
pull request should say so rather than implying the checks covered it.
