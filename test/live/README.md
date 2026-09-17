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

## What the two cases do, and what the run currently proves

The host starts a Normal round and waits for the mod to hand out goals — `host_start_round`
only opens the round and leaves every goal at 0; `host_update_round` assigns them a frame or
two later, so an override written any earlier is simply undone. It then replaces both goals
with a chosen Tick Tock Clock pair and both clients warp themselves.

- **isolated** — acts 6 and 1. Act 6 stops the clock while the others run it, so
  `players_have_private_variant` isolates that pair anywhere in the course. R-030 says these
  two must pass through each other.
- **shared** — both on act 6. The same predicate is false, so the mod leaves the contact alone
  and the engine must push these two apart. **This case is the control**, and without it the
  run proves nothing.

Both goals are cap-free deliberately: a vanish cap makes `interact_player` return before it
reaches `resolve_player_collision`.

The host stands itself on ground with room before inviting the client over, because
`resolve_player_collision` works out where a push would land and abandons it when there is no
floor there — two players near the edge of a small platform are never separated at all, and
the Tick Tock Clock entrance platform is exactly that small. Each side writes its own row of
the player sync table to say when it is ready, that being the one row a player may write.

**The collision measurement does not work yet, and the control is what shows it.** The shared
pair is not pushed apart, the two cases report identical numbers, and the isolated case stayed
green with the R-030 branch deleted from `modules/goals.lua`. The probe's `gates` line names
the cause: each instance sees the *other* player frozen at the position they arrived with, so
the bodies never occupy one place in either instance's own view. Writing `m.pos` from Lua
appears to move a player locally without the engine sending that position on, which would mean
the probe has to move them with controller input instead — those fields are writable. This is
roadmap item R-032, and until it is closed a green `run.sh` says nothing about R-030.

Two smaller findings from the same runs: `gServerSettings.playerInteractions` reads 2 on the
host and 1 on the client, so it is not synchronised; and the mod's own state is reached through
`api.global_sync` / `api.player_sync` rather than the globals, because every mod in sm64coopdx
gets its own pair of sync tables.

## What it still does not cover

Rendering, the HUD, anything a person has to look at, and any interaction with a third-party
mod — the probe plays both parts and neither is a person. It is two processes on one machine
over the loopback, so it says nothing about latency or packet loss, and a real session with
real players remains the last check before a release.
