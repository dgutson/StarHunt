# The live harness — what it rests on

Read this when `test/live/run.sh` fails in a way the triage table in `SKILL.md` does not
cover, before changing anything under `test/live/`, and before concluding that a failed run
means the mod is broken. Every claim here is read out of sm64coopdx's own source, which is
checked out at `/home/dfg/src/sm64coopdx`; the citations are what make them checkable when
the game is rebuilt from a newer upstream.

`test/live/README.md` is the same ground at greater length, written for someone reading the
directory rather than running it.

## What it needs

- the game at `~/src/sm64coopdx/build/us_pc/sm64coopdx`, or `COOPDX` pointing at a binary;
- a vanilla US ROM at `~/.local/share/sm64coopdx/baserom.us.z64`, md5
  `20b854b239203baf6c961b850a4a51a2`, or `ROM` pointing at one.

Building the game needs **no** ROM and takes about 20 minutes. `libglew-dev` and `libz-dev`
are the packages most likely to be missing:

```bash
git clone https://github.com/coop-deluxe/sm64coopdx ~/src/sm64coopdx
sudo -A apt install build-essential python3 libglew-dev libsdl2-dev libz-dev libcurl4-openssl-dev
make -C ~/src/sm64coopdx -j"$(nproc)"
```

The **ROM is needed at run time**, not at build time. Co-op DX ships none of the game's
assets and reads them out of the ROM the first time each instance runs: `main_rom_handler`
(`src/pc/rom_checker.cpp`) scans the instance's own folder for a `.z64` whose MD5 it knows,
which is why `run.sh` links a copy into each instance's save path. Nobody can supply a ROM
for the user. Three game processes want about 1.2 GB between them.

`run.sh` passes `--hide-loading-screen` on purpose: without it an instance with no usable ROM
waits at the setup screen for a person who never comes, and the run dies of its timeout with
nothing in the log to say why. With it the game prints `could not find valid vanilla us sm64
rom` and exits.

## Three processes, and why the host cannot be one of the two players

A process started with `--headless --server` sets `gServerSettings.headlessServer`
(`src/pc/network/network.c:140`), and that one flag makes its own player inert in two places:

- `network_update_player` (`src/pc/network/packets/packet_player.c:430`) returns before
  sending anything, so the host's position is never transmitted and every client sees its body
  frozen wherever it first appeared;
- `is_player_active` (`src/game/obj_behaviors.c:547`) returns **false** for the server's player
  on every instance including its own, and that is the first question `interact_player` asks
  about both bodies.

A headless host can referee a round but can never touch anybody. So the harness runs a
dedicated headless server and **two** headless clients, and the collision it measures is
between the two clients. The server still runs StarHunt as the host: it picks the goals, owns
`gGlobalSyncTable` and drives the round.

## What each case measures

`split` and `shared` are played in Tick Tock Clock, `ddd` in Dire Dire Docks and
`wdw` in Wet-Dry World. Every goal used is cap-free deliberately — a vanish cap makes `interact_player` return before it reaches
`resolve_player_collision`, which would pass for the wrong reason.

- **split** — the two players hold goals for different acts and each stands in its own act,
  which is what an ordinary round produces, and the engine must push them apart to about 74. A
  player's goal act becomes its `currActNum`, and the published game's `is_player_active`
  rejects a remote player whose act differs, so this case passes only where the engine has been
  asked to leave the act out of its player-to-player tests — `gLevelValues.crossActPlayers`,
  set by the mod at load. **This is the case that fails when that request is removed**, and the
  gates line shows why: `active_them=0` with `active_them_cross_act=1` is the shape of a pair
  the behaviours still treat as elsewhere while the collision, attack and nametag paths do not.
  It is also the worst arrangement in the course, since act 6 stops the clock while act 1 runs
  it, so the two clients disagree about where every moving platform is.
- **shared** — both players hold the same goal, so they are in one act and the engine pushes
  them apart with or without that request. **This is the control.** If it fails, nothing else
  in the run means anything.
- **ddd** — two Dire Dire Docks goals on different acts, with the second player warping
  itself into the first's act so the pair is in one act. Nothing may keep these two apart:
  only the manta ray is
  act-gated in that course, and the submarine, its door and the nine poles read
  `SAVE_FLAG_HAVE_KEY_2 | SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR` out of the save file every client
  receives from the host. The two must be pushed apart, and both clients report the flags they
  read so the run can check they agree. **This is the case that fails if that course is
  isolated by act again**, with `fail reason=wrong_pair_state`.
  The pair meets at a fixed point rather than on searched-for floor: the course is flooded end
  to end, and the shaft the players drop into ends in a whirlpool (hitbox radius 200, height
  500, `src/game/behaviors/whirlpool.inc.c`) whose current separates a pair placed beside it by
  190 units and more — a false push. The point used is the column the level's `MARIO_POS`
  drops Mario down, 300 units under the water surface, which is still water and also inside
  the region such a rule would have covered.
- **wdw** — the same claim for Wet-Dry World, set up the same way. Every object in both of its
  areas is `ALL_ACTS`, and its water level does not come from the act:
  `geo_wdw_set_initial_water_level` (`src/game/moving_texture.c:305`) derives it from
  `gPaintingMarioYEntry`. Every pair that can meet holds the same level, because the engine's
  area sync matches on the same four fields `is_player_active` does and the area packet carries
  it (`packet_area.c:52`, `:155-157`; `network_player.c:129-142`). **This is the case that fails
  if that course is isolated by act again**, with `fail reason=wrong_pair_state`.
  No instance in the harness ever enters a painting, so `gPaintingMarioYEntry` stays at its
  initial `0.0` (`src/game/moving_texture.c:119`) and the course is drained to 31 units in
  every run. The pair therefore meets on searched-for floor like the Tick Tock Clock cases,
  with no meeting point of its own.

## How the pair is placed

The player with the lower global index stands still; the other walks in. The one standing
still looks for a patch of floor with room in eight directions first, because
`resolve_player_collision` works out where a push would land and abandons it when there is no
floor there — and the Tick Tock Clock entrance platform is small enough for that to happen.

The measurement is each instance's own player's drift from where the probe put it down.
Nothing moves an idle Mario with no input and no velocity, so a drift is a push. The distance
to the other body is printed too, but it only means something while the engine is exchanging
positions.

## Engine constraints the harness is built around

Each of these is already handled in `run.sh` or the probe. They are listed so a change does
not undo one.

- **A perfect overlap produces no push at all.** `resolve_player_collision` moves along the
  vector between the two torsos, so at distance zero the term is zero and nobody moves however
  willing the engine is. The pair is placed 20 units apart, because an exact overlap is
  indistinguishable from a refusal.
- **Two players on different acts never exchange positions.** `network_receive_player` drops a
  packet whose course, act, level or area does not match and marks the sender's position
  invalid, so neither side can aim at where it sees the other. The meeting point travels
  through the probe's sync table as plain coordinates instead.
- **Every mod gets its own `_ENV`, and reads fall through while writes do not.** `smlua_init`
  calls `luaL_newstate` once and gives each mod an environment whose metatable reads through to
  the real globals (`src/pc/lua/smlua.c`). The probe writes `_G.STARHUNT_TEST_MODE`; StarHunt
  publishes `_G.STARHUNT_TEST_API`.
- **Every mod gets its own sync tables.** StarHunt's are reached through `api.global_sync` and
  `api.player_sync`, never through the probe's own `gGlobalSyncTable`. The probe's tables are
  what the three instances use to talk to each other.
- **Mods load in alphabetical order of the uncoloured `-- name:` header** (`mods_sort`,
  `src/pc/mods/mods.c`). The probe is called `AAA StarHunt Probe` so it runs before StarHunt,
  which reads the test flag once at load time. **Renaming the probe breaks the harness
  silently** — it would still load, just too late to matter.
- **A mod the config has never seen is disabled**, and `--enable-mod` matches the folder name
  under `mods/`, not the `-- name:` header. On a *first* run even that is lost:
  `configfile_load_internal` creates the missing config and returns above the loop that queues
  the enables, so `run.sh` writes `config.txt` itself.
- **`--client <ip> <port>` drops the port when it ends the command line.** The parser checks
  `(i + 2) < argc` after consuming the IP (`src/pc/cliopts.c`), and the client quietly dials
  7777. `run.sh` puts `--playername` after the caller's arguments.
- **Stdout is block-buffered and never flushed**, so a killed process loses its output. Every
  instance runs under `stdbuf -oL -eL`.
- **`host_start_round` does not assign goals.** It ends at `sh5_active = 1`; `host_update_round`
  hands them out a frame or two later, so an override written any earlier is undone.
- **`gServerSettings.playerInteractions` is not synchronised** — 2 on the server, 1 on each
  client. Neither is `NONE`, so contact still happens, but the mod's PvP setting is host-only.

## Four explanations the source rules out

- **`torsoPos` is filled in without the render path.** `resolve_player_collision` compares
  torso positions and the render path is what normally fills them, but `bhv_mario_update`
  copies `pos` into `torsoPos` whenever the render path did not run that frame
  (`src/game/object_list_processor.c:259-263`, `src/game/mario_misc.c:494`). Headless is fine
  here.
- **A Lua teleport is transmitted.** `network_update_player` sends whatever moved a player at
  least every third tick (`sTicksSinceSend > 2`), so writing `m.pos` is not why a remote body
  looks frozen. A frozen remote body means the headless-server flag or a level/act mismatch.
- **Vertical separation, invincibility, intangible actions and the vanish cap** are each
  visible in the `gates` line. Read it rather than theorising about them.
- **The no-floor guard is real and is not usually the cause.** It is why the probe searches for
  open ground, and fixing it alone changes nothing when a pair is refused for another reason.

If a future case needs contact to come from real movement rather than placement, the
controller fields (`buttonDown`, `stickX`, `stickY`, `stickMag`) are writable from Lua
(`src/pc/lua/smlua_cobject_autogen.c:690-701`). Nothing needs them today.

## Adding a case

The `say()` prefixes are an interface `run.sh` greps; treat them as fixed. In this order,
in `test/live/mods/starhunt_probe/main.lua`:

1. `CASE` — add the name. The order of that list is the run order, and `run.sh` waits for
   the referee's `end` line rather than for a verdict count, so nothing there needs changing
   to match its length.
2. `WANT_CROSS_ACT` — whether the two players are in different acts for this case. The probe
   fails the run when the pair disagrees with that, which catches a case that is not set up the
   way it reads: a rewarp that never landed, or a goal that was reassigned behind its back.
3. the `open_case` state in `update_server` — which goals the two players get. A case whose
   claim is that a course is *not* private by act needs nothing written here: add it to
   `SHARED_COURSE` with its level, the act both bodies stand in and the act the other goal
   names, and `pick_act_pair` finds the two goals. A case in a course that needs neither, like
   Tick Tock Clock's, needs its own picker — `pick_ttc_goals` is that. **A case that must not
   re-warp a player must not reassign its goal**, because a client re-warps whenever
   `sh5_goal` changes.
4. the `settle` state in `update_player` — any per-case setup before the pair is placed, such as
   the self-warp that puts both bodies in one act. A `SHARED_COURSE` entry already gets that
   self-warp, and an optional `meet` function on it replaces the floor search with a fixed
   point.
5. `run.sh` — the verdict block needs a `grep -c` line for the new case and a failure message
   naming what its being red means. That block is the only place outside the probe that has to
   learn the case exists.

## Adding a `--without` removal

Each `test/live/without/<name>.txt` is one named removal: the **first line** is the path inside
`StarHunt/`, and everything after it is the exact block of Lua to delete, indentation included.
Name the case it must turn red in the `WITHOUT_CASE` table beside the verdict block in
`run.sh`; a removal with no entry there would report a pass for doing nothing.

`run.sh` aborts when the block is not found in the file exactly once. That matters more than it
looks: a removal that silently does nothing turns the falsification check into a tautology,
which is the one failure this mechanism exists to prevent.

## Running one instance by hand

`run.sh` does this; it matters only when debugging a single process. The build links
`libdiscord_game_sdk.so` and ships it beside the binary rather than installing it, so the
loader has to be told where it is:

```bash
LD_LIBRARY_PATH="$(dirname "$COOPDX")" "$COOPDX" --headless --savepath ...
```
