---
name: starhunt-testing
description: Everything about verifying a change to StarHunt — the five checks in order with their exact commands and recorded baselines, the two expected false positives, the mutation sweep, and test/live/run.sh, the harness that runs the mod inside real headless sm64coopdx processes. **CLAUDE.md deliberately no longer carries any of this, so this skill is the only place the commands and baselines exist** — load it rather than guessing a command or a number. Use it whenever a change to StarHunt has to be verified, before opening a pull request, when asked to run the tests, the suite, luacheck, lua-language-server, a mutation sweep or "check this works in the real game", when any check reports different numbers from the baselines, and when adding a case to the offline suite or the live harness. Use it even when testing was never mentioned, because every edit under StarHunt/ or test/ ends in these checks, and it is step 5 of the process in DEVELOPMENT_CHECKLIST.md. Also use it whenever the live harness fails, times out, hangs or reports numbers that look wrong, because nearly all of its failure modes are sm64coopdx behaviour rather than bugs in the mod, and the dead ends it records have each already cost a session.
---

# Testing StarHunt

Five checks, cheapest first. A change is verified when the four static ones hold their recorded
baselines and, for anything that touches players meeting each other, the live harness is green.

Run everything from the repository root, `/home/dfg/src/StarHunt_v1.1`.

## The baselines

**A rise in any of these is a regression.** Quote them in the pull request.

| check | expected | takes |
|---|---|---|
| `lua5.4 test/run.lua` | 785 passed, 0 failed | ~46s |
| `luacheck StarHunt/ test/` | 2 warnings / 0 errors in 47 files | ~2s |
| `lua-language-server --check` | 10 problems in 2 files | ~40s |
| `test/live/run.sh` | PASSED, 6 `PROBE verdict` lines | ~2.5 min |

The two luacheck warnings are `hud.lua:93` shadowing the upvalue `alpha`, and an empty `if`
branch in `modifiers.lua`. The ten type problems are in `save.lua` (2) and `test/harness.lua` (8).

## 1. Syntax, and why it must be lua5.4

```bash
lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"
```

`lua` on this machine is the 5.1 alternative and cannot parse the `|`, `&` and `~` operators in
`hud.lua` and `save.lua`. Always `lua5.4`. This checks `main.lua` alone; the modules are checked
by the suite below.

## 2. The offline suite

```bash
lua5.4 test/run.lua                      # 785 tests
lua5.4 test/run.lua audit difficulty     # only matching suites
```

It loads the mod outside the game against a generated stub of exactly the engine surface the mod
uses, and drives it through `STARHUNT_TEST_API`. `test/README.md` has the layout and what each
suite guards. The suite was mutation-checked, so a green run means something.

A new test needs its function exported from its own module **and** added to `STARHUNT_TEST_API`
in `main.lua`. The harness references functions by name there, so reordering hooks cannot
silently test the wrong one. **Being in that table does not mean a function is tested** — eight
times now a published function turned out to be called by no test at all. `grep` for the key
before assuming coverage.

`work/starhunt_v11_load_test.lua`, the harness named in `DEVELOPMENT_CHECKLIST.md`, was never in
this repository and is not on this machine. `test/` is a fresh implementation; do not go looking
for the old one.

## 3. The two static checkers

```bash
luacheck StarHunt/ test/
lua-language-server --check /home/dfg/src/StarHunt_v1.1 --checklevel=Warning --logpath=/tmp/lls-log
```

Pass lua-language-server the **directory**. Given a file path it silently reports "no problems
found" whatever the code contains.

lua-language-server reports no undefined global, undefined field or arity problem, which also
confirms every engine symbol the mod uses still exists in current sm64coopdx. `.luarc.json`
disables `different-requires`, because the engine's own definitions and the mod both define names
the checker would otherwise pair up.

### Two reports that are expected and are not bugs

Both were confirmed against the engine's binding code, not just its annotations.

- `save_file_do_save(file, true)` — "cannot assign `boolean` to parameter `integer`". The
  annotation says `integer`, but `smlua_to_integer` explicitly converts booleans (`true` → 1).
- `spawn_non_sync_object(..., nil)` — "cannot assign `nil` to parameter `function`".
  `smlua_to_lua_function` special-cases `LUA_TNIL` and returns 0; `nil` is the intended way to
  pass no setup function.

The 24 old "shadowing upvalue `goal`" warnings are **gone**: the `goal()` constructor is now
`modules/goals.lua:61` and file-local to it. Inside `goals.lua` itself the locals still shadow it,
which means a typo'd `goal(...)` call in such a scope is a runtime error rather than a lint error.

### How the checkers know the engine API

`StarHunt/main.lua` calls about 59 engine functions and reads roughly 1,090 engine constants.
Without the game's API these are all undefined globals and the linters are useless, so the API
list is generated from sm64coopdx's own `autogen/lua_definitions` (6,337 globals: 2,008 functions,
4,307 constants, 22 mutable engine tables) and stored **outside this folder**, because the game
loads every `.lua` file it finds in a mod directory:

| path | contents |
|---|---|
| `~/.local/share/sm64coopdx/definitions/` | `functions.lua`, `constants.lua`, `structs.lua`, `manual.lua` from the game repo |
| `~/.local/share/sm64coopdx/luacheck_globals.lua` | generated read/write global lists, loaded by `.luacheckrc` |
| `~/.local/share/sm64coopdx/refresh.sh` | re-downloads the definitions and regenerates the above |

Run `~/.local/share/sm64coopdx/refresh.sh` after the game updates, so the checkers match the
engine version being targeted. The two config files that stay in the repository, `.luarc.json`
and `.luacheckrc`, have no `.lua` extension, so the game ignores them if the folder is ever
copied into `mods/`.

`selene` is installed and **unusable**: its 0.31.0 Linux release only compiles the `lua51` and
`luau` grammars, so it cannot parse this project's 5.4 syntax. Do not add a `selene.toml`.

## 4. The mutation sweep

Run this over the lines a change touched, or the change is unverified however green the suite is.

```bash
python3 tools/gen_mutations.py StarHunt/modules/round.lua 787,885
WORKERS=2 python3 tools/sweep_mutations.py round_client     # one suite, fast
ONLY=2,5,6-8 WORKERS=2 python3 tools/sweep_mutations.py     # re-run named survivors
```

Run the sweep in the **foreground** with `WORKERS=2`: background sweeps have been killed here for
low memory. Derive the line range **after** the last edit to the file, or it is off by the lines
that were added.

## 5. The live harness

```bash
test/live/run.sh --load-only    # one process: does the mod load, do the modules resolve (~40s)
test/live/run.sh                # a referee and two players: the collision cases (~2.5 min)
```

Exit 0 pass, 1 fail, 2 the game or the ROM is missing. It prints every `PROBE` line and leaves the
full logs in the directory it names. `COOPDX`, `ROM`, `PORT`, `TIMEOUT`, `JOIN_DELAY`, `PAIR_DELAY`
and `WORK` override the binary, the ROM, the port, the deadline, the two join delays and the
scratch directory.

A full run should end with `PASSED:` and six `PROBE verdict` lines: `split passed_through=true`,
`hidden passed_through=true`, `shared passed_through=false`, once for each of the two players.

`test/live/README.md` is the long version. What follows is what a session needs in its head.

### What it needs, and how to rebuild it if it is gone

On this machine both are already in place and are the script's defaults, so no variables are
normally needed:

- the game at `~/src/sm64coopdx/build/us_pc/sm64coopdx`,
- the ROM at `~/.local/share/sm64coopdx/baserom.us.z64`, md5 `20b854b239203baf6c961b850a4a51a2`.

Building the game needs **no** ROM and takes about 20 minutes; `libglew-dev` and `libz-dev` were
the only packages missing here:

```bash
git clone https://github.com/coop-deluxe/sm64coopdx ~/src/sm64coopdx
sudo -A apt install build-essential python3 libglew-dev libsdl2-dev libz-dev libcurl4-openssl-dev
make -C ~/src/sm64coopdx -j"$(nproc)"
```

The **ROM is needed at run time**, not at build time: Co-op DX does not bundle the game's assets,
it reads them out of the ROM the first time each instance runs (`main_rom_handler`,
`src/pc/rom_checker.cpp`), scanning the instance's own folder for a `.z64` whose MD5 it knows.
Nobody can supply one for the user. Three game processes want about 1.2 GB between them.

`/home/dfg/src/sm64coopdx` is also the source to read when a claim about the engine has to be
checked. Every fact in this skill came out of it rather than out of the documentation.

### Three processes, and why not two

A process started with `--headless --server` sets `gServerSettings.headlessServer`, and that one
flag makes its own player inert: it never sends its position (`network_update_player`,
`src/pc/network/packets/packet_player.c:430`) and `is_player_active` returns false for it on every
instance (`src/game/obj_behaviors.c:547`), which is the first question `interact_player` asks
about both bodies. A headless host can referee but can never touch anybody. So the harness runs a
dedicated headless server and **two** headless clients, and the collision it measures is between
the two clients.

### What the three cases mean

- **split** — the two players hold goals for different acts of Tick Tock Clock and each stands in
  its own act. It **tests nothing the mod does**: a player's goal act becomes its `currActNum`,
  and `is_player_active` rejects a remote player whose act differs, so the engine refuses the
  contact by itself. Kept as a record, and because an earlier version of the harness mistook
  exactly this for a passing test of R-030.
- **hidden** — the same goals, but one player warps itself back into the other's act without its
  goal changing. Both acts now agree so the engine is willing, while
  `players_have_private_variant`, which reads the assigned goals rather than the loaded act, still
  calls the pair private. **This is the only case that says anything about StarHunt**, and the
  only one that can fail. It is a real state, not a contrivance: `NEXT_GOAL_DELAY` is 90 frames,
  so a player just given a different act of the level they are standing in sits in it for three
  seconds.
- **shared** — both players hold the same goal, so the mod leaves the contact alone and the engine
  must push them apart to about 74. **This is the control.** If it fails, nothing else in the run
  means anything.

### Before citing a green run as evidence

Delete these four lines from `StarHunt/modules/goals.lua` and run it again:

```lua
    if has_interaction(interaction, INTERACT_PLAYER) then
        local other = player_index_of_body(object)
        return other == nil or not players_have_private_variant(m.playerIndex, other)
    end
```

`hidden` must turn red (`drift=47.3 reach=84.7 passed_through=false`) while `split` and `shared`
do not move. Restore the lines and confirm `git status` is clean. A harness that stays green with
the fix removed is worse than no harness, because it gets quoted.

### Reading a failure

The `gates` line, printed halfway through each measurement, names every gate in `interact_player`
and `resolve_player_collision` that Lua can read. It is what cracked each dead end; add to it
rather than removing from it.

| what you see | what it means |
|---|---|
| `active_them=0` | the engine refused before StarHunt was asked — compare `my_act` with `their_act` and `my_area` with `their_area` |
| `collided=false` with `active_them=1` | the bodies never touched; check `dist` and whether the placement worked |
| `their_pos_valid=false` | positions are not being exchanged at all, so `their_xz` is stale and any distance to that body is meaningless |
| `dy` above 160 | one hitbox height apart vertically, which `resolve_player_collision` refuses outright |
| `drift=0.0` in `shared` | the control did not collide; the run proves nothing |
| every gate open but no push | look at where they are standing: a push whose landing point has no floor is abandoned, and the Tick Tock Clock entrance platform is too small |

**If the run times out with no verdicts at all**, the game did not get as far as the probe. Read
`$WORK/*.log` — the path is printed — rather than the `PROBE` lines:

- `could not find valid vanilla us sm64 rom` — the ROM is missing or is not a vanilla US copy.
- the log stops after three config lines — the mods did not load; check the folder names under
  `$WORK/<name>/mods/` against the `--enable-mod` arguments.
- `PROBE waiting ... reason=...` repeating — the probe is alive and stuck; the reason names where.
- nothing at all after the banner — an instance died. `pkill -x sm64coopdx` cleans up orphans
  (`pkill -f` matches the shell running it and kills your own session).

### Dead ends already ruled out

Each of these cost a session, so do not spend another one on them. All were read out of the
engine's source.

- **`torsoPos` is not a render-path product that headless misses.** `resolve_player_collision`
  compares torso positions, and the render path is what normally fills them in — but
  `bhv_mario_update` copies `pos` into `torsoPos` whenever the render path did not run that frame
  (`src/game/object_list_processor.c:259-263`, `src/game/mario_misc.c:494`). Headless is fine here.
- **A Lua teleport *is* transmitted.** `network_update_player` sends whatever moved a player at
  least every third tick (`sTicksSinceSend > 2`), so writing `m.pos` is not why a remote body
  looks frozen. A frozen remote means either the headless-server flag or a level/act mismatch.
- **Vertical separation, invincibility, intangible actions and the vanish cap** are all visible in
  the `gates` line. Read it before theorising.
- **The no-floor guard is real but was not the cause.** `resolve_player_collision` abandons a push
  whose landing point has no floor, and the Tick Tock Clock entrance platform really is too small
  — which is why the probe searches for open ground first. Fixing that alone changed nothing.

If a future case needs contact to come from real movement rather than placement, the controller
fields (`buttonDown`, `stickX`, `stickY`, `stickMag`) are writable from Lua
(`src/pc/lua/smlua_cobject_autogen.c:690-701`). Nothing needs them today.

### Running an instance by hand

`run.sh` does this for you; it matters only when debugging one process on its own. The build links
`libdiscord_game_sdk.so` and ships it beside the binary rather than installing it, so the loader
has to be told where it is:

```bash
LD_LIBRARY_PATH="$(dirname "$COOPDX")" "$COOPDX" --headless --savepath ... 
```

### Adding a case

The roadmap items that touch `players_have_private_variant` — the DDD, WDW and cross-act PvP ones
— are exactly the ones that want a new live case. Five places, in this order:

1. `CASE` in `test/live/mods/starhunt_probe/main.lua` — add the name. Order is the run order.
2. `WANT_PRIVATE` — what `players_have_private_variant` must answer for that pair. The probe fails
   the run if the predicate disagrees, which catches a case that is not set up the way it reads.
3. `open_case` in the server half — which goals the two players get. `pick_ttc_goals` is
   Tick Tock Clock specific; a case in another course needs its own picker. **A case that must not
   re-warp a player must not reassign its goal**, because a client re-warps whenever `sh5_goal`
   changes; `hidden` is the worked example.
4. `settle` in the player half — any per-case setup before the pair is placed, such as the
   self-warp that makes `hidden`.
5. `run.sh` — `want=` is the verdict count, two per case, and the verdict block needs a `grep -c`
   line and a failure message for the new case. Both are literal numbers, not derived.

The `say()` prefixes are an interface `run.sh` greps. Treat them as fixed.

### Traps that cost whole sessions, already worked around

Each of these is handled in `run.sh` or the probe. They are listed so a change does not undo one.

- **A perfect overlap produces no push at all.** `resolve_player_collision` moves along the vector
  between the two torsos, so at distance zero the term is zero. The pair is placed 20 units apart.
- **Two players on different acts never exchange positions.** `network_receive_player` drops a
  packet whose course, act, level or area does not match, so a player cannot aim at where it sees
  the other one. The meeting point travels through the probe's sync table as plain coordinates.
- **Every mod gets its own `_ENV`, and reads fall through while writes do not.** The probe writes
  `_G.STARHUNT_TEST_MODE`; StarHunt publishes `_G.STARHUNT_TEST_API`.
- **Every mod gets its own sync tables.** StarHunt's are reached through `api.global_sync` and
  `api.player_sync`, never through the probe's own `gGlobalSyncTable`.
- **Mods load in alphabetical order of the uncoloured `-- name:` header.** The probe is called
  `AAA StarHunt Probe` so it runs before StarHunt, which reads the flag once at load time.
  Renaming it breaks the harness silently.
- **`--enable-mod` is lost on a first run.** `configfile_load_internal` creates the missing config
  and returns above the loop that queues the enables, so `run.sh` writes `config.txt` itself.
- **`--client <ip> <port>` drops the port when it ends the command line**, and the client quietly
  dials 7777. `run.sh` puts `--playername` after the caller's arguments.
- **Stdout is block-buffered and never flushed**, so a killed process loses its output. Every
  instance runs under `stdbuf -oL -eL`.
- **`host_start_round` does not assign goals.** It ends at `sh5_active = 1`; `host_update_round`
  hands them out a frame or two later, so an override written any earlier is undone.
- **`gServerSettings.playerInteractions` is not synchronised** — 2 on the server, 1 on each
  client. Neither is `NONE` so contact still happens, but the mod's PvP setting is host-only.

If the game is rebuilt from a newer upstream and the harness starts behaving differently, re-read
the cited engine lines before changing the probe, and run `refresh.sh` so the static checkers
match the engine being targeted.

## What none of this reaches

Rendering, the HUD, anything a person has to look at, real latency, packet loss, and any
third-party mod. Three processes on one machine over the loopback is not a real session. A real
multiplayer session with real people remains the last check before a release, and every pull
request should say so rather than implying the checks covered it.
