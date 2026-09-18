# test/live — running StarHunt inside the real game

`test/run.lua` loads the mod outside sm64coopdx against a generated stub of the engine. That
suite is fast and it is where almost every case belongs, but it cannot reach the things the
mod shares with the game: whether the mod loads at all, whether the folder-relative `require`
resolves, warping, networking, and whether two Marios actually touch.

This directory runs the mod inside real sm64coopdx processes and reads back what happened.

```bash
test/live/run.sh --load-only        # one instance: does the mod load, do the modules resolve
test/live/run.sh                    # a referee and two players: the collision cases
test/live/run.sh --without crossact # the same, with the mod's cross-act request taken out
                                    # of each instance's COPY: its case must go red
```

`run.sh` exits 0 on a pass, 1 on a failure and 2 when it cannot find the game or the ROM. It
prints every `PROBE` line it collected and leaves the full logs behind, whose path it prints.
A full run takes about two and a half minutes.

## What it needs

**A built sm64coopdx carrying `gLevelValues.crossActPlayers`**, which takes a clone and a
`make` — no ROM is needed for that step:

```bash
git clone -b feature/cross-act-players https://github.com/dgutson/sm64coopdx ~/src/sm64coopdx
sudo apt install build-essential python3 libglew-dev libsdl2-dev libz-dev libcurl4-openssl-dev
make -C ~/src/sm64coopdx -j"$(nproc)"
```

That branch adds one `LevelValues` field and leaves the act out of the engine's
player-to-player tests while it is set, which is what lets two players hunting different stars
in one course meet. Against a build without it the `split` case is red by nature and the probe
stops at `is_player_active_cross_act`, which does not exist there.

**A vanilla US Super Mario 64 ROM**, which nobody can supply for you. Co-op DX does not bundle
the game's assets: it reads them out of the ROM the first time it runs. `main_rom_handler`
(`src/pc/rom_checker.cpp`) scans the instance's own folder for any `.z64` whose MD5 it
recognises, and without one the game stops at the ROM setup screen before it loads a single
mod. Put your own copy at `~/.local/share/sm64coopdx/baserom.us.z64`, or pass `ROM=/path/to.z64`.

`run.sh` looks for `~/src/sm64coopdx/build/us_pc/sm64coopdx`; `COOPDX=/path/to/binary` overrides
it. `PORT`, `TIMEOUT`, `JOIN_DELAY`, `PAIR_DELAY` and `WORK` override the port, the deadline, how
long the first player waits before dialling the server, the gap before the second player joins,
and the scratch directory. Three game processes need about 1.2 GB between them.

`--hide-loading-screen` is passed on purpose: without it, an instance with no usable ROM waits
at the setup screen for a person who is never coming, and the run dies of its timeout with no
explanation. With it the game prints `could not find valid vanilla us sm64 rom` and exits.

## Three processes, and why a headless host cannot be one of the two players

The obvious arrangement is a headless host and one client bumping into each other. It cannot
work. A process started with `--headless --server` sets `gServerSettings.headlessServer`
(`gCLIOpts.headless && inNetworkType == NT_SERVER`, `src/pc/network/network.c:140`), and that
one flag makes its own player inert in two separate places:

- `network_update_player` (`src/pc/network/packets/packet_player.c:430`) returns before sending
  anything, so the host's position is never transmitted and every client sees its body frozen
  wherever it first appeared;
- `is_player_active` (`src/game/obj_behaviors.c:547`) returns **false** for the server's player
  on every instance, including the server's own — and `interact_player` asks that question
  about both bodies before it can reach `resolve_player_collision`.

So a headless host can referee a round but can never touch anybody. `run.sh` therefore starts a
dedicated headless server and **two** headless clients, and the collision it measures is between
the two clients. The server still runs StarHunt as the host: it picks the goals, owns
`gGlobalSyncTable` and drives the round.

## How it works, and the engine facts it rests on

Each instance gets its own `--savepath`, so its config, its save file and its `mods/` folder are
disposable and no instance can see another's. `run.sh` copies `StarHunt/` and
`test/live/mods/starhunt_probe/` into each, launches them, and greps the probe's output out of
their stdout.

- **Headless is real.** `--headless` leaves `gWindowApi` as `gfx_dummy_wm_api` and `gAudioApi`
  as `audio_null` (`src/pc/pc_main.c`), so the whole game loop runs — physics, Lua, networking
  — with no window, no audio and no display.
- **Every mod shares one Lua state, but not one environment.** `smlua_init` calls
  `luaL_newstate` exactly once, and each mod then runs with its own `_ENV` whose metatable reads
  through to the real globals (`src/pc/lua/smlua.c`). Reads fall through; **writes do not**, so
  the probe sets `_G.STARHUNT_TEST_MODE` and StarHunt publishes `_G.STARHUNT_TEST_API`.
- **Sync tables are per-mod too.** The probe's `gGlobalSyncTable` is not StarHunt's, which is why
  the mod's own state is reached through `api.global_sync` and `api.player_sync`. The probe's own
  tables are what the three instances use to talk to each other.
- **Mods in a fresh instance are switched off.** A save path the game has never seen has no
  config, and a mod the config does not list stays disabled; `mods_enable`
  (`src/pc/mods/mods.c`) is what turns one on and `--enable-mod` is the only way to reach it
  without the menu. It matches the mod's folder name, not its `-- name:` header. On a *first*
  run even that is lost — `configfile_load_internal` creates the missing file and returns above
  the loop that queues the enables — so `run.sh` writes `config.txt` itself.
- **Load order is alphabetical on the mod's name.** `mods_sort` (`src/pc/mods/mods.c`) orders by
  the uncoloured `-- name:` header, which is why the probe is called `AAA StarHunt Probe`: the
  flag is only read once, as StarHunt loads, so the probe has to be first. **Renaming the probe
  breaks the harness silently** — it would still load, just too late to matter.
- **`--client <ip> <port>` drops the port when it is the last argument.** The parser checks
  `(i + 2) < argc` after consuming the IP (`src/pc/cliopts.c`), so a client whose port ends the
  command line quietly dials 7777. `run.sh` puts `--playername` after the caller's arguments.
- **Stdout is block-buffered and the game never flushes it**, so a killed process loses its
  output. `run.sh` runs each instance under `stdbuf -oL -eL`.

## What each case does

The server starts a Normal round and waits for the mod to hand out goals — `host_start_round`
only opens the round and leaves every goal at 0; `host_update_round` assigns them a frame or two
later, so an override written any earlier is simply undone. It then replaces the two players'
goals with a chosen pair — Tick Tock Clock for the collision cases, Dire Dire Docks for `ddd`
and Wet-Dry World for `wdw` — and each client warps itself. Every goal used is cap-free deliberately: a vanish cap
makes `interact_player` return before it reaches `resolve_player_collision`.

- **split** — the two players hold the act 6 and act 1 goals and each stands in its own act,
  which is what an ordinary StarHunt round produces, and they must be pushed apart.
  `warp_to_level(level, 1, act)` sets `gCurrActStarNum`, which becomes the player's `currActNum`,
  and on stock sm64coopdx `is_player_active` refuses a remote player whose act does not match —
  no position, no collision, no attack, no nametag. So what this case measures is the engine
  being asked to leave the act out of that comparison, which the mod does once at load through
  `gLevelValues.crossActPlayers`. **This is the case that fails when that request is removed.**
  It is also the hardest arrangement in the course: act 6 stops the clock while act 1 runs it,
  so the two clients do not even agree on where Tick Tock Clock's moving platforms are.
- **shared** — both players hold the act 6 goal, so they are in one act and the engine would
  push them apart with or without that request. **This case is the control**; without it a
  setup where the bodies never touch reports the other cases as passes, fix or no fix.
- **ddd** — two Dire Dire Docks goals on different acts, with the second player walking back into
  the first's act, so the pair is in one act. Nothing may keep them apart: the only
  act-gated object in that course is the manta ray (`levels/ddd/script.c:31`), and the submarine,
  its door and the nine poles read `SAVE_FLAG_HAVE_KEY_2 | SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR` out
  of a save file every client is given by the host. So the two must be pushed apart, and both
  report the flags they read for `run.sh` to check that they agree. **This is the case that fails
  if Dire Dire Docks is isolated by act again.**
- **wdw** — two Wet-Dry World goals on different acts, played the same way, and nothing may
  keep this pair apart either: every object in both of that course's areas is `ALL_ACTS`, and its
  water level does not come from the act — `geo_wdw_set_initial_water_level`
  (`src/game/moving_texture.c:305`) derives it from `gPaintingMarioYEntry`. Every pair that can
  meet holds the same level: the engine's area sync matches on the same four fields
  `is_player_active` does (`network_player.c:129-142`) and the area packet carries
  `gEnvironmentLevels[0]`, copied into `gEnvironmentRegions[6]` for this course
  (`packet_area.c:52`, `:155-157`). **This is the case that fails if Wet-Dry World is isolated
  by act again.**

Each client also checks its own pair before measuring it: the two acts must differ in `split`
and must agree in every other case (`cross_act` on the `pair` line). A case whose arrangement
quietly drifts — a rewarp that did not land, a goal that was reassigned — would otherwise report
a pass for the wrong reason, and the probe stops with `fail reason=wrong_pair_state` instead.

The `ddd` pair does not stand where the others do. Dire Dire Docks is flooded from end to
end, so there is no patch of floor to look for, and the shaft the players drop into ends in a
whirlpool — hitbox radius 200, height 500 at `-3174, -4915, 102`
(`sWhirlpoolHitbox`, `src/game/behaviors/whirlpool.inc.c`) — whose current carries a pair placed
beside it apart at 190 units and more, which reads exactly like a push. The case therefore uses a
fixed meeting point: the column the level's own `MARIO_POS` drops Mario down, 300 units below the
water surface, where the water is still and two players sink together instead of falling. That
point is also inside the region a rule isolating the course by act would have covered, which is
what lets the case go red when one comes back.

The `wdw` pair needs none of that. No instance in the harness ever enters a painting, so
`gPaintingMarioYEntry` stays at the `0.0` it is defined with (`src/game/moving_texture.c:119`)
and the course is drained to 31 units in every run, which leaves the ground by the entrance dry
floor. The pair meets there, on searched-for floor like the Tick Tock Clock cases.

## How the pair is placed, and two traps in doing it

The player with the lower global index stands still; the other walks in. The one standing still
looks for a patch of floor with room in eight directions first, because `resolve_player_collision`
works out where a push would land and abandons it when there is no floor there — two players near
the edge of a small platform are never separated at all, and the Tick Tock Clock entrance
platform is exactly that small.

- **The meeting point travels through the sync table, not through the other player's body.** Two
  players on different acts never exchange positions at all: `network_receive_player` drops a
  packet whose course, act, level or area does not match and marks the sender's position invalid.
  Both sides agree on plain coordinates instead.
- **They are placed 20 units apart, not on top of each other.** `resolve_player_collision` pushes
  along the vector between the two torsos, so at a perfect overlap the whole term is zero and
  nobody moves however willing the engine is. A pair that overlaps exactly is indistinguishable
  from a pair the engine refused.

The measurement is each instance's own player's drift from where the probe put it down. Nothing
moves an idle Mario with no input and no velocity, so a drift is a push; the distance to the
other body is printed too, but it only means anything when the engine is exchanging positions.

## Reading the output

Every line is `PROBE <key> <field>=<value> ...`, and `run.sh` matches on the keys, so treat them
as an interface. The one worth knowing is `gates`, printed halfway through each measurement:

```
PROBE gates role=player1 case=split dist=20.0 drift=0.0 active_me=1 active_them=0
      active_them_cross_act=1 collided=true interactions=1 headless_server=1 my_act=1
      their_act=6 my_area=1 their_area=1 their_pos_valid=true my_action=0C400201
      invinc=0,0 dy=0.0 their_xz=1405,-515
```

It names every gate in `interact_player` and `resolve_player_collision` that can be read from
Lua. `collided=false` means the bodies never touched and `their_pos_valid=false` means the
positions are not being exchanged at all. The two `active_them` fields are the ones to read
first: `is_player_active` keeps comparing the act, so it is `0` for a cross-act pair and stays
that way — that is deliberate, because forty-odd behaviours choose their target through it.
`active_them_cross_act` is the one the player-to-player paths ask, and **that** is what has to
be `1` for the two to meet. Read the line before forming a theory, and add to it rather than
removing from it.

## Verifying the harness still measures something

A green run is only worth what its ability to go red is worth, so that is one command:

```bash
test/live/run.sh --without crossact
```

It takes `core.enable_cross_act_players(gLevelValues)` out of `main.lua` and requires the
`split` case to fail while the control still holds — exit 0 means the harness can fail, and a
green ordinary run therefore means something. **The working tree is never edited.** `run.sh` already copies
`StarHunt/` into each instance's own `mods/` folder, so the removal is applied to those copies
after the copy and before the game starts; the tree hash is the same before and after.
`tools/sweep_mutations.py` follows the same rule for the same reason — a run killed halfway
through leaves a half-applied edit behind when it edits in place.

`test/live/without/README.md` says how to add another one, and why `run.sh` dies rather than
continues when the block it means to remove is no longer there.

## What it still does not cover

Rendering, the HUD, anything a person has to look at, and any interaction with a third-party
mod — the probe plays every part and none of them is a person. It is three processes on one
machine over the loopback, so it says nothing about latency or packet loss, and a real session
with real players remains the last check before a release.

`gServerSettings.playerInteractions` reads 2 on the server and 1 on each client, so it is not
synchronised. Neither value is `NONE`, so the contact still
happens, but the mod's PvP setting is host-only.
