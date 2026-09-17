# test/live — running StarHunt inside the real game

`test/run.lua` loads the mod outside sm64coopdx against a generated stub of the engine. That
suite is fast and it is where almost every case belongs, but it cannot reach the things the
mod shares with the game: whether the mod loads at all, whether the folder-relative `require`
resolves, warping, networking, and whether two Marios actually touch.

This directory runs the mod inside two real sm64coopdx processes and reads back what happened.

```bash
test/live/run.sh --load-only    # one instance: does the mod load, do the modules resolve
test/live/run.sh                # host + client: the R-030 pass-through case
```

`run.sh` exits 0 on a pass, 1 on a failure and 2 when it cannot find the game or the ROM. It prints every
`PROBE` line it collected and leaves the two full logs behind, whose path it prints.

## What it needs

**A built sm64coopdx**, which takes a clone and a `make` — no ROM is needed for that step, and
the project's own CI does no more than this:

```bash
git clone https://github.com/coop-deluxe/sm64coopdx ~/src/sm64coopdx
sudo apt install build-essential python3 libglew-dev libsdl2-dev libz-dev libcurl4-openssl-dev
make -C ~/src/sm64coopdx -j"$(nproc)"
```

**A vanilla US Super Mario 64 ROM**, which nobody can supply for you. Co-op DX does not bundle
the game's assets: it reads them out of the ROM the first time it runs. `main_rom_handler`
(`src/pc/rom_checker.cpp`) scans the instance's own folder for any `.z64` whose MD5 it
recognises, and without one the game stops at the ROM setup screen before it loads a single
mod. Put your own copy at `~/.local/share/sm64coopdx/baserom.us.z64`, or pass `ROM=/path/to.z64`.

`run.sh` looks for `~/src/sm64coopdx/build/us_pc/sm64coopdx`; `COOPDX=/path/to/binary` overrides
it. `PORT`, `TIMEOUT`, `JOIN_DELAY` and `WORK` override the port, the deadline, how long the
client waits before dialling the host, and the scratch directory.

`--hide-loading-screen` is passed on purpose: without it, an instance with no usable ROM waits
at the setup screen for a person who is never coming, and the run dies of its timeout with no
explanation. With it the game prints `could not find valid vanilla us sm64 rom` and exits.

## How it works, and the four engine facts it rests on

Each instance gets its own `--savepath`, so its config, its save file and its `mods/` folder
are disposable and neither instance can see the other's. `run.sh` copies `StarHunt/` and
`test/live/mods/starhunt_probe/` into each, launches the host with `--headless --server` and
the client with `--headless --client`, and greps the probe's output out of their stdout.

- **Headless is real.** `--headless` leaves `gWindowApi` as `gfx_dummy_wm_api` and `gAudioApi`
  as `audio_null` (`src/pc/pc_main.c`), so the whole game loop runs — physics, Lua, networking
  — with no window, no audio and no display.
- **Every mod shares one Lua state.** `smlua_init` calls `luaL_newstate` exactly once
  (`src/pc/lua/smlua.c`), so the probe sets the global `STARHUNT_TEST_MODE` and StarHunt, which
  reads it at load time, publishes `STARHUNT_TEST_API` for the probe to drive.
- **Mods in a fresh instance are switched off.** A save path the game has never seen has no
  config, and a mod the config does not list stays disabled; `mods_enable`
  (`src/pc/mods/mods.c`) is what turns one on and `--enable-mod` is the only way to reach it
  without the menu. It matches the mod's folder name, not its `-- name:` header.
- **Load order is alphabetical on the mod's name.** `mods_sort` (`src/pc/mods/mods.c`) orders
  by the uncoloured `-- name:` header, which is why the probe is called `AAA StarHunt Probe`:
  the flag is only read once, as StarHunt loads, so the probe has to be first. **Renaming the
  probe breaks the harness silently** — it would still load, just too late to matter.

## What the R-030 case actually does

The host starts a Normal round, then replaces both players' goals with two Tick Tock Clock
stars whose acts are 6 and 1. Act 6 stops the clock and the others run it, so
`players_have_private_variant` isolates that pair anywhere in the course, and each client warps
itself to its own goal. Both goals are cap-free on purpose: a vanish cap makes `interact_player`
return before it reaches `resolve_player_collision`, which would pass the test for the wrong
reason.

Once both players are in the same area and the area has been alive for 120 frames — the engine
refuses every player contact while `gCurrentArea->localAreaTimer < 60` — the **client** puts its
own Mario exactly on the host's, once, and then both sides leave the engine alone for 60 frames
and record the horizontal distance each frame.

Only the client moves, for two reasons: a player can only be placed by the instance that owns
it, because a remote Mario's position is overwritten by the next packet, and if both sides moved
onto each other's position they would swap places and never touch at all. The client says it has
arrived by writing its own row of the player sync table, which is the one channel a client may
write, so the host does not spend its whole sample window measuring a gap that had not closed.

Two Mario hitboxes have a radius of 37 and `resolve_player_collision` pushes to twice that, so a
push lands at about 74 while no push leaves them near 0; the verdict is drawn at 40, between the
two. Both instances have to report `passed_through=true`.

## What it still does not cover

Rendering, the HUD, anything a human has to look at, and any mod interaction — the probe plays
both parts and neither is a person. It is two processes on one machine over the loopback, so it
says nothing about latency or packet loss, and a real session with real players remains the
last check before a release.
