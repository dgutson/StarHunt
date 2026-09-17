---
name: starhunt-testing
description: How to test StarHunt — the offline suite, the three static checks, the mutation sweep, and the live harness that runs the mod inside real headless sm64coopdx processes. Use whenever a change to StarHunt has to be verified, whenever a run reports different numbers from the recorded baselines, when asked to run the tests or "check this works in the real game", and before opening a pull request. Also use when the live harness fails, times out, or reports numbers that look wrong, because most of its failure modes are engine behaviour rather than bugs in the mod.
---

# Testing StarHunt

Five checks, cheapest first. A change is verified when the four static ones hold their recorded
baselines and, for anything that touches players meeting each other, the live harness is green.

Run everything from the repository root, `/home/dfg/src/StarHunt_v1.1`.

## 1. Syntax, and why it must be lua5.4

```bash
lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"
```

`lua` on this machine is the 5.1 alternative and cannot parse the `|`, `&` and `~` operators in
`hud.lua` and `save.lua`. Always `lua5.4`. This checks `main.lua` alone; the modules are checked
by the suite below.

## 2. The offline suite

```bash
lua5.4 test/run.lua                      # 785 tests, ~46s
lua5.4 test/run.lua audit difficulty     # only matching suites
```

It loads the mod outside the game against a generated stub of exactly the engine surface the mod
uses, and drives it through `STARHUNT_TEST_API`. **Expected: 785 passed, 0 failed.** A new test
needs its function exported from its module and added to `STARHUNT_TEST_API` in `main.lua`; being
in that table does not mean anything calls it, so `grep` for the key before assuming coverage.

## 3. The two static checkers

```bash
luacheck StarHunt/ test/
lua-language-server --check /home/dfg/src/StarHunt_v1.1 --checklevel=Warning --logpath=/tmp/lls-log
```

**Expected: 2 warnings / 0 errors in 47 files**, and **10 problems in 2 files**. A rise in either
is a regression. The two luacheck warnings are `hud.lua:93` shadowing `alpha` and an empty `if`
branch in `modifiers.lua`; the ten type problems are in `save.lua` (2) and `test/harness.lua` (8),
and two of the reports there are expected rather than bugs — `CLAUDE.md` says which and why.

Pass lua-language-server the **directory**. Given a file path it silently reports "no problems
found" whatever the code contains.

`selene` is installed and unusable: its 0.31.0 Linux release has no 5.4 grammar. Do not add a
`selene.toml`.

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
scratch directory. On this machine the game is at `~/src/sm64coopdx/build/us_pc/sm64coopdx` and the
ROM at `~/.local/share/sm64coopdx/baserom.us.z64`; both are the defaults, so no variables are
normally needed. Three game processes want about 1.2 GB between them.

A full run should end with four lines beginning `PASSED:` and six `PROBE verdict` lines:
`split passed_through=true`, `hidden passed_through=true`, `shared passed_through=false`, twice.

`test/live/README.md` is the long version. What follows is what a session needs in its head.

### Three processes, and why not two

A process started with `--headless --server` sets `gServerSettings.headlessServer`, and that one
flag makes its own player inert: it never sends its position
(`network_update_player`, `src/pc/network/packets/packet_player.c:430`) and `is_player_active`
returns false for it on every instance (`src/game/obj_behaviors.c:547`), which is the first
question `interact_player` asks about both bodies. A headless host can referee but can never touch
anybody. So the harness runs a dedicated headless server and **two** headless clients, and the
collision it measures is between the two clients.

### What the three cases mean

- **split** — the two players hold goals for different acts of Tick Tock Clock and each stands in
  its own act. It **tests nothing the mod does**: the engine refuses the contact by itself,
  because a player's goal act becomes its `currActNum` and `is_player_active` rejects a remote
  player whose act differs. It is kept as a record, and because an earlier version of the harness
  mistook exactly this for a passing test.
- **hidden** — the same goals, but one player warps itself back into the other's act without its
  goal changing. Both acts now agree so the engine is willing, while the mod still calls the pair
  private. **This is the only case that says anything about StarHunt**, and the only one that can
  fail.
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
| `active_them=0` | the engine refused before StarHunt was asked — check `my_act` against `their_act` and `my_area` against `their_area` |
| `collided=false` with `active_them=1` | the bodies never touched; check `dist` and whether the placement worked |
| `their_pos_valid=false` | positions are not being exchanged at all, so `their_xz` is stale and any distance to that body is meaningless |
| `dy` above 160 | one hitbox height apart vertically, which `resolve_player_collision` refuses outright |
| `drift=0.0` in `shared` | the control did not collide; the run proves nothing |
| everything open but no push | look at where they are standing: a push whose landing point has no floor is abandoned, and the Tick Tock Clock entrance platform is too small |

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
- **`pkill -f sm64coopdx` matches the shell running it** and kills the session. Use `pkill -x`.
- **`host_start_round` does not assign goals.** It ends at `sh5_active = 1`; `host_update_round`
  hands them out a frame or two later, so an override written any earlier is undone.

### When the engine itself may have changed

Every fact above was read out of `/home/dfg/src/sm64coopdx`, not out of its documentation. If the
game is rebuilt from a newer upstream and the harness starts behaving differently, re-read the
cited lines before changing the probe — and run `~/.local/share/sm64coopdx/refresh.sh` so the two
static checkers match the engine being targeted.

## What none of this reaches

Rendering, the HUD, anything a person has to look at, real latency, packet loss, and any
third-party mod. A real multiplayer session with real people remains the last check before a
release, and every pull request should say so rather than implying the checks covered it.
