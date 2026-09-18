# Act geometry

How two players whose goals name different acts of one course end up in one fight while
each keeps their own act's world.

This is method and engine reference for the act question. Every engine claim below carries a
file and line in `~/src/sm64coopdx` so nothing here has to be re-derived.

**The route taken is section 13: the engine change, which is built** — `dgutson/sm64coopdx`,
branch `feature/cross-act-players`. Sections 4 through 12 describe the design that reaches the
same result on the published game, by spawning every act's objects and suppressing the ones
outside the local act per client. They are kept because that is the route to take if the engine
change is never available, and nothing in them is installed today.

---

## 1. What this builds

A player hunting the Jolly Roger Bay act-1 star and a player hunting an act-3 star stand in
the same level and area. They see each other at full opacity, with nametags and palettes.
They collide. They damage each other through `interact_player_pvp`, the engine's own PvP
path, with the engine's knockback.

At the same time, the act-1 player has no raised hull: they swim straight through the space
it occupies and cannot see it. The act-3 player has no sunken hull. Each one stands on, and
sees, exactly the objects their own goal's act puts in the course.

The mod does not simulate any of the fight. It changes which objects exist for whom, and
the engine does the rest.

**Sections 4 through 12 are the published-game design, and it is not what is installed.**
Section 13's engine change reaches the same result with none of it, and is what the mod
targets. Read this design only if a patched game stops being available: it needs no change to
sm64coopdx at all.

---

## 2. The constraint that shapes everything

**Two players whose `currActNum` differ cannot interact at all, and no mod can change
that.** Every gate is upstream of every hook:

| what | where | what it does |
|---|---|---|
| `is_player_active` | `src/game/obj_behaviors.c:552-557` | returns FALSE when `np->currActNum != gNetworkPlayerLocal->currActNum` |
| `interact_player` | `src/game/interaction.c:1447` and `:1454` | the only path to `resolve_player_collision`; calls `is_player_active` on both bodies first |
| `interact_player_pvp` | `src/game/interaction.c:1481-1482` | calls it on attacker and victim before anything else |
| `HOOK_ALLOW_PVP_ATTACK` | `src/game/interaction.c:1528` | fires only after those checks, so a mod can refuse an attack but never permit one |
| `network_receive_player` | `src/pc/network/packets/packet_player.c:265-270` | sets `currPositionValid = false` and returns, so the remote position is never applied |
| `execute_mario_action` | `src/game/mario.c:2010-2052` | fades the remote player out over sixteen frames, then sets `GRAPH_RENDER_INVISIBLE`, `oIntangibleTimer = -1` and returns 0 |

And the act cannot be falsified:

- `currActNum` is bound read-only: `src/pc/lua/smlua_cobject_autogen.c:1573`, immutable flag
  `true`; `docs/lua/structs.md:1873` prints it as read-only.
- `gCurrActNum` and `gCurrActStarNum` have no Lua binding at all.
- `fadeOpacity` is read-only (`smlua_cobject_autogen.c:1586`), so the fade cannot be held open.
- `struct ServerSettings` (`src/pc/network/network.h`) has no field that relaxes any of this.
- `network_player_set_override_location` sets `overrideLocation`, a display string used only
  by `src/pc/djui/djui_panel_playerlist.c:79-81`. It has no effect on matching.

What is published is `gCurrActStarNum`, not `gCurrActNum`: `src/game/level_update.c:558` calls
`network_player_update_course_level(gNetworkPlayerLocal, gCurrCourseNum, gCurrActStarNum, ...)`.
`DynOS_Warp_ToLevel` (`data/dynos_warps.cpp:186-189`) sets both from the act passed to
`warp_to_level`, so they agree in practice.

**Therefore every player in one course must load the same act number.** That is not a
preference; it is the price of admission. Everything else in this document is about giving
each player their own world anyway.

---

## 3. What an act actually changes in a course

Very little, and all of it is objects.

- `src/engine/level_script.c:534` (`level_cmd_place_object`) and `:959`
  (`level_cmd_place_object_ext_lua_params`) are the **only** two places any level-script
  command consults the act mask. Both are object placement.
- The one other act-conditional command is `level_cmd_create_whirlpool`
  (`src/engine/level_script.c:686`, the `CMD_GET(u8, 3) == 3 && gCurrActNum >= 2` branch),
  which gates Jolly Roger Bay's whirlpool. It is a current, not a surface.
- `MACRO_OBJECT` (`include/level_misc_macros.h:4-8`) carries no acts field, so macro objects
  are the same in every act.
- `JUMP_IF` appears only in `levels/menu/script.c` and `levels/intro/script.c`. No course
  script branches on anything.
- Terrain, areas, geo layouts, water boxes and collision meshes are identical across acts.

So: **reproduce the act-gated object set per client and you have reproduced the act.**

Two behaviours read `gCurrActNum` at runtime and are worth knowing about:

- `src/game/behaviors/snowman.inc.c:191` — the CCM snowman's body, `gCurrActNum != sp36 + 1`.
- `src/game/camera.c:6987` — `SURFACE_BOSS_FIGHT_CAMERA` gives the boss-fight camera when
  `gCurrActNum == 1` and a radial camera otherwise.

The castle levels (`castle_inside`, `castle_grounds`, `castle_courtyard`) and all three
Bowser levels contain no `OBJECT_WITH_ACTS` entries at all, so nothing in this document
changes the lobby.

---

## 4. The three mechanisms

### 4.1 One act number for every warp into a course

`StarHunt/modules/round.lua:843` currently reads:

```lua
if goal ~= nil then warp_to_level(goal.level, 1, goal.act) end
```

It becomes act **1** for every goal. Use 1, not 0: `level_cmd_place_object` computes
`u8 val7 = 1 << (gCurrActNum - 1);` at `src/engine/level_script.c:534` **before** the
`disableActs` test, so act 0 evaluates a shift by −1 every time an object is placed. Act 1
also gives the boss-fight camera in the three courses with `SURFACE_BOSS_FIGHT_CAMERA`,
which is the right camera because the boss now spawns whatever the act.

The goal's act keeps every other job it has. It still names the star
(`goal_matches_star_object`, `StarHunt/modules/goals.lua:533-539`, reads the star id out of
`oBehParams`), it still drives the catalog, the audit and the HUD. Only the warp stops using it.

### 4.2 `gLevelValues.disableActs = true`

Set once, at mod load, in `StarHunt/main.lua` beside the existing
`gServerSettings.skipIntro = 1`.

- The field is writable from Lua: `src/pc/lua/smlua_cobject_autogen.c:1299`, immutable flag
  `false`.
- When true, both object-spawning paths skip the act mask entirely
  (`src/engine/level_script.c:538` and `:971`), so every act's objects spawn.
- `hardcoded_reset_default_values` (`src/game/hardcoded.c:351`) is `AT_STARTUP`, so the value
  is never reset and does not need re-applying on level load.
- `mods/hide-and-seek.lua:518` in the game's own bundle sets it the same way, at mod-load
  top level.
- Consequence: `src/game/level_update.c:2002` makes the act-select menu never appear.
  StarHunt warps directly and already refuses castle doors, warps and cannons — the
  `in_castle_lock_level` branch of `on_allow_interact` (`StarHunt/modules/goals.lua:781-790`)
  runs before the `is_round_active()` early return — so no player reaches that menu anyway.

Both clients run the mod, both hold the flag, both load act 1: **the spawned object set and
its sync-id order are identical on every client.** That is what keeps object sync intact.

### 4.3 Per-client suppression

For each object that belongs only to acts other than the local player's goal act, on this
client only:

```lua
object.collisionData = nil
object.header.gfx.node.flags = object.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE
```

- `load_object_collision_model_internal` returns at `src/engine/surface_load.c:979`
  (`if (gCurrentObject->collisionData == NULL) { return; }`), so the object contributes no
  surfaces at all. Nothing to stand on, nothing to bump into.
- `nil` is explicitly accepted for this field type: `src/pc/lua/smlua_cobject.c:454-456`
  (`if (lua_isnil(L, 3)) { *(u8**)p = NULL; break; }`). The field is writable:
  `smlua_cobject_autogen.c:1620`, immutable flag `false`.
- The render flag is the same mechanism `update_star_visibility` already uses
  (`StarHunt/modules/goals.lua:885-910`).

**Suppress, never delete.** The object stays present, keeps its sync id, and keeps running
its behaviour, so the other client's updates still land on something. Only two local
presentation facts change.

**Record and restore, as the mod does everywhere else.** Keep the original `collisionData`
pointer and whether `GRAPH_RENDER_INVISIBLE` was already set, in a table keyed by the object,
and put both back when the round ends or the goal changes. `local_runtime.hidden_stars` is
the pattern to copy.

**Interaction is refused through `HOOK_ALLOW_INTERACT`,** which StarHunt already owns
(`StarHunt/main.lua:380`). Do not write to `oIntangibleTimer`: the engine manages it, and
the hook is the authoritative answer.

**A player with no goal act suppresses everything outside act 1.** That covers the lobby,
Boss mode and Chaos, and it makes Chaos look exactly as it does today, because
`StarHunt/modules/round.lua:892` already warps Chaos players with `warp_to_level(level, 1, 1)`.

---

## 5. The generated table

### 5.1 What it holds

One row per act-gated object placement, keyed by level:

```lua
-- StarHunt/modules/actdata.lua  -- GENERATED by tools/gen_act_objects.py. Do not edit.
return {
    [LEVEL_JRB] = {
        { beh = id_bhvInSunkenShip,  area = 1, x = 5385, y = -5520, z = 2428, acts = 0x01 },
        { beh = id_bhvInSunkenShip3, area = 1, x = 4880, y =   820, z = 2375, acts = 0x3E },
        ...
    },
    ...
}
```

`acts` is the raw mask from the level script. `ACT_1` = `1 << 0` … `ACT_6` = `1 << 5`
(`include/model_ids.h:4-9`).

### 5.2 Which rows are act-gated

`OBJECT(...)` expands to `OBJECT_WITH_ACTS(..., 0x1F)` (`include/level_commands.h:224-225`),
and `ALL_ACTS` is `0x3F` (`include/model_ids.h:15`). The engine treats `0x1F` as always
(`src/engine/level_script.c:538`, `CMD_GET(u8, 2) == 0x1F`). So:

> A placement is act-gated when its mask is neither `0x1F` nor `0x3F`. Every other
> placement is in every act and must not appear in the table.

The generator prints how many rows it emitted, per course and in total. Do not copy that
number into any document — read it from a run.

### 5.3 The generator

`tools/gen_act_objects.py`, alongside the existing `tools/gen_engine_stub.py` and
`tools/gen_linter_data.py`. It reads `~/src/sm64coopdx/levels/*/script.c` and writes
`StarHunt/modules/actdata.lua`.

Parsing rules it must get right:

- **Track the current area.** Object placements sit inside `AREA(n, ...)` … `END_AREA()`
  blocks. The area index belongs in the row; two acts can put different objects at the same
  coordinates in different areas.
- Handle `OBJECT_WITH_ACTS`, `OBJECT_WITH_ACTS_EXT` (`include/level_commands.h:327`) and
  `OBJECT_WITH_ACTS_EXT2` (`:333`). The last one takes a model pointer rather than a model id,
  so the argument positions differ.
- The arguments carry `/*comment*/` markers; strip them before splitting.
- The acts argument is a `|` expression of `ACT_n` names, or `ALL_ACTS`, or a literal.
- Map the level directory name to its `LEVEL_*` constant. The fifteen main courses plus the
  three cap courses are what matter; emit whatever is act-gated and let the runtime ignore
  levels it never visits.

The generated file requires nothing and is required by `world.lua` alone, so it adds no edge
to the module graph.

---

## 6. Runtime: `StarHunt/modules/world.lua`

A new module. `world` requires `core`, `goals` and `actdata`. Nothing requires `world`
except `main.lua`; every other module reaches it through `SH`, which is the mechanism
`CLAUDE.md` describes for crossing modules without a `require` edge. Check the graph before
committing:

```bash
for f in StarHunt/modules/*.lua; do echo "-- $(basename $f)"; grep -n '^local .*require(' $f; done
```

`world` → `core`, `goals`, `actdata`; `goals` → `core`, `i18n`, `save`, `boss`. No cycle.

### 6.1 Classification at spawn

Hook `HOOK_ON_OBJECT_LOAD`. `StarHunt/main.lua:374` already registers
`remove_castle_lakitu` on it, so the shape exists.

For each object: look up the current level in the table, and match a row by behaviour id and
spawn position.

```lua
local function row_for(object)
    local rows = ACT_OBJECTS[gNetworkPlayers[0].currLevelNum]
    if rows == nil then return nil end
    for _, row in ipairs(rows) do
        if obj_has_behavior_id(object, row.beh) ~= 0
            and math.abs((object.oPosX or 0) - row.x) < 2
            and math.abs((object.oPosY or 0) - row.y) < 2
            and math.abs((object.oPosZ or 0) - row.z) < 2 then
            return row
        end
    end
    return nil
end
```

The position is the script's spawn position at this moment: `create_object`
(`src/game/spawn_object.c:374`) fires `HOOK_ON_OBJECT_LOAD` at `:417`, and the caller writes
`oPosX/Y/Z` from the spawn info. A tolerance of a couple of units absorbs
`snap_object_to_floor`, which `create_object` applies to `OBJ_LIST_GENACTOR`,
`OBJ_LIST_PUSHABLE` and `OBJ_LIST_POLELIKE` before the hook fires
(`src/game/spawn_object.c:407-414`) — for those lists the **y** may differ from the script's
value, so match on x and z and treat y as advisory.

`obj_has_behavior_id` and `get_id_from_behavior` are both exposed, and every `id_bhv*`
constant exists (`autogen/lua_definitions/constants.lua`).

### 6.2 Children of a suppressed object

**Children cannot be classified at load time.** `create_object` sets `obj->parentObj = obj`
at `src/game/spawn_object.c:289` and fires the hook at `:417`; the real parent is written
afterwards, by `spawn_object_at_origin` at `src/game/object_helpers.c:719`. At hook time a
child is its own parent.

This is not hypothetical. `bhvTowerPlatformGroup` is act-gated in Whomp's Fortress and spawns
`bhvWfSolidTowerPlatform`, `bhvWfSlidingTowerPlatform` and `bhvWfElevatorTowerPlatform`
children (`src/game/behaviors/tower_platform.inc.c:125-132`) which carry no act mask of their
own. Suppressing only the group leaves the platforms solid.

So a second pass walks the object lists and suppresses any object whose `parentObj` is
suppressed and which is not itself in the table. `parentObj` is readable
(`smlua_cobject_autogen.c:2375`).

The pass must cover the lists platforms and actors actually live in, not only
`OBJ_LIST_LEVEL`: `OBJ_LIST_SURFACE`, `OBJ_LIST_GENACTOR`, `OBJ_LIST_PUSHABLE`,
`OBJ_LIST_DESTRUCTIVE`, `OBJ_LIST_POLELIKE`, `OBJ_LIST_LEVEL`, `OBJ_LIST_DEFAULT`.

Run it on `HOOK_ON_LEVEL_INIT` and then every thirty frames while a round is active. It does
not need to run every frame: a child appears once, when its parent spawns.

### 6.3 What `world.lua` publishes on `SH`

- `SH.local_act()` — the act whose world this client should have: the local goal's act, or
  `1` when there is no goal.
- `SH.object_allowed_for_local_act(object)` — false for a suppressed object. `goals.lua`
  calls this from `on_allow_interact` so another act's enemies and items cannot touch you.
- `SH.restore_act_geometry()` — puts every recorded `collisionData` and render flag back.
  Called on round end and on level change.

---

## 7. What each player may do to the other

Under this design the pair interacts fully, so the only question left is whether an
interaction should be refused because of geometry only one of them has. **This is a design
decision, not an implementation one.** Build (a); (b) is specified so it can be added without
rework.

**(a) Nothing is refused.** He is standing on a platform you do not have; you see him in
mid-air; you can hit him and he can hit you. This is the literal reading of "someone from
another act may come and hit you", it needs no new synchronized state, and it costs nothing
per frame.

**(b) Refuse when the other player is standing on a surface you suppressed.** Each client
can answer this for itself and publish the answer: `gMarioStates[0].floor` is a `Surface`
pointer (`smlua_cobject_autogen.c:1418`) and `Surface.object` gives the object that surface
belongs to (`:2610`). So the local client reads its own floor, asks whether that object is in
the table and with which mask, and writes the mask into `gPlayerSyncTable[0]`. Any other
client compares that mask against its own act and refuses `INTERACT_PLAYER` and
`HOOK_ALLOW_PVP_ATTACK` for the pair. One field, one comparison per pair.

**(c) (b) plus occlusion** — refusing when the straight segment between the two Marios
crosses a suppressed object. This is what R-028 described. It needs the extent of each
suppressed object, which the generated table does not carry, so it is the expensive one and
should not be built until someone asks for it.

---

## 8. Changes to StarHunt, file by file

Line numbers are as of the commit this document is written against; re-check them before
editing.

### `StarHunt/main.lua`

- Add `gLevelValues.disableActs = true` beside `gServerSettings.skipIntro = 1` (line 17).
- `require("modules/world")` and bind what it exports.
- Register `HOOK_ON_OBJECT_LOAD` and the sweep.
- Drop `players_have_private_variant` from the imports (line 48) and from
  `STARHUNT_TEST_API` (line 234).
- Add the new world functions to `STARHUNT_TEST_API`. A function a test calls must be in
  that table.

### `StarHunt/modules/round.lua`

- `:843` — warp to act 1 instead of `goal.act`.
- `:939-944` `on_nametags_render` — delete; it only blanked the nametag of a private player.
  Remove its `hook_event(HOOK_ON_NAMETAGS_RENDER, ...)` registration (`main.lua:388`).
- `:946-974` `update_private_player_visibility` — delete, with
  `local_runtime.hidden_players` (`core.lua:152`).
- `:819-823` — the TTC speed rule; see the traps below.

### `StarHunt/modules/goals.lua`

- `:527-531` `goal_matches_player_area` — delete the `and player.currActNum == goal_data.act`
  clause. The level test stays; `goal_matches_star_object` already identifies the star by its
  behaviour params, which is act-agnostic.
- `:541-588` — the comment block about private variants; delete. Keep the Wet-Dry World water
  paragraph and the Dire Dire Docks save-file paragraph somewhere: both are facts about the
  engine that this design does not change.
- `:590-594` `is_jrb_ship_zone` and `:597-600` `is_wf_tower_zone` — delete.
- `:602-641` `players_have_private_variant` — delete.
- `:643-664` `players_can_share_world` — keep. It answers "are these two genuinely in the
  same place", which `team.lua:259` still needs for PvP. Delete only its final
  `return not players_have_private_variant(a, b)`.
- `:768-777` `player_index_of_body` — keep only if rule (b) is built; it is the only caller.
- `:805-809` — the `INTERACT_PLAYER` branch of `on_allow_interact`; delete under rule (a),
  rewrite under rule (b).
- `on_allow_interact` — add a refusal for objects `SH.object_allowed_for_local_act` rejects.
- `:885-910` `update_star_visibility` — no change needed. It already hides every star that is
  not the local goal's, which is what a course full of every act's stars requires.

### `DEVELOPMENT_CHECKLIST.md`

- The `Privacidad/PvP` row of the code map (line 72) describes a system that no longer
  exists. Replace it with the act-geometry row.
- The do-not-undo entry at line 92, "Un jugador oculto seguía siendo sólido", is R-030's
  `INTERACT_PLAYER` refusal. Under rule (a) it goes; under rule (b) it changes shape. Either
  way the table must say what replaced it. **Removing an entry from that table needs the
  user's agreement, not just a passing test.**

### `test/`

- `test/suite/world.lua` — rewritten. Most of its cases assert the old isolation.
- New offline cases: the table matches the right objects; suppression records and restores;
  a player with no goal gets act 1; star matching no longer depends on the loaded act.
- `test/live/without/r030.txt` retires with the branch it removes.
- `test/live/mods/starhunt_probe/main.lua` — the `split` case changes meaning; see below.

---

## 9. Milestones

One branch and one pull request each, from an up-to-date `main`.

**M0 — the table, and nothing else.** Write `tools/gen_act_objects.py`, generate
`StarHunt/modules/actdata.lua`, and put a per-course summary in the pull request: for each
course, what each act adds and removes. Nothing under `StarHunt/` is wired up yet. This is
the artifact the game designer needs in order to sanity-check the design against real
content, and it is the step that can still stop the whole thing cheaply.

**M1 — one act instance.** `disableActs`, the act-1 warp, and
`goal_matches_player_area` losing its act clause. No suppression yet, so the world is the
union of all acts — the "one shared world" behaviour. The isolation code still runs, so the
mod still hides cross-act pairs. Live: the probe's `split` case must report equal acts,
`active_them=1` and `their_pos_valid=true` while StarHunt still hides them, which proves the
engine half without changing what a player sees.

**M2 — suppression.** `world.lua`, the load hook, the child sweep, record and restore. Each
player is now back in their own act's world. The isolation code still hides them from each
other, so still no fight. Offline cases for classification and restore; live case that a
player's own act's objects are present and another act's are not.

**M3 — the fight.** Delete the isolation: `players_have_private_variant`, both zone tests,
`update_private_player_visibility`, the nametag blanking, and R-030's `INTERACT_PLAYER`
branch. Live: two players in one course on different goals see each other, collide and
damage each other.

**M4 — Tick Tock Clock and the rest of the traps.** See below.

**M5 — documents.** The code map, the do-not-undo table, `BALANCE_AUDIT.md`, `CLAUDE.md`,
`CHANGELOG.md`, `test/live/README.md`.

---

## 10. Traps

**Tick Tock Clock cannot be per-client.** `gTTCSpeedSetting` travels in the level packet
(`src/pc/network/packets/packet_level.c:33`, read at `:82`) and is re-applied to every TTC
object at `:91-101`. It is one value per level instance. `StarHunt/modules/round.lua:822`
sets it from the local goal's act (`current_goal.act == 6 and TTC_SPEED_STOPPED or
TTC_SPEED_SLOW`), so two TTC players with different goals fight over it. The proposed rule is
a constraint in `host_pick_goal` (`round.lua:134-143`), stated symmetrically so it has no
hole: **the live TTC goals must either all be act 6 or all not be act 6.** It has to hold on
reassignment as well as on the first deal; `goal_is_active_for_anyone` already reports what
is live.

**Another act's enemies still exist and still act.** They are synced objects; their
behaviours run on every client whatever the local act, and their AI tracks whichever player
is nearest — including a player who cannot see them. `HOOK_ALLOW_INTERACT` stops them
damaging that player. It does not stop them following them around. Each case that turns out
to matter needs its own answer; do not try to solve it generically before one shows up.

**Objectives are shared.** Both players' objective objects are in one synced instance. If he
defeats the boss guarding your star, your star spawns. If he collects red coins that belong
to your goal, they count. This is new, it is mostly cooperative rather than hostile, and it
is a design consequence to put to the designer rather than a bug to fix.

**The CCM snowman.** `src/game/behaviors/snowman.inc.c:191` reads `gCurrActNum` directly.
With every client on act 1, the act-5 snowman body behaves as it does in act 1. Cosmetic;
check it in a live session before deciding it matters.

**Jolly Roger Bay's whirlpool** is created by `level_cmd_create_whirlpool` at level load when
`gCurrActNum >= 2`, not by an object, so it is not in the table and with every client on act 1
it never appears. R-028 excluded it deliberately as a current rather than a surface. If it
turns out to matter it lives in `gAreas[i].whirlpools[index]`, not in the object list.

**`bhvShipPart3`, `bhvSunkenShipPart2` and `bhvTowerPlatformGroup` carry no
`LOAD_COLLISION_DATA`.** Their collision comes from companion objects — `bhvInSunkenShip`,
`bhvInSunkenShip3` and the tower platform children. Nulling `collisionData` on an object that
has none is harmless, but hiding the visual half without suppressing the collision half would
leave an invisible wall. Check both halves of each pair in a live session.

**Restore matters less than it looks, and must still be written.** Every goal change warps,
and a warp reloads the level with fresh objects. Restore covers the round ending without a
warp, and the mod being disabled mid-round. It is the same discipline as the cap and HUD-flag
restores that `DEVELOPMENT_CHECKLIST.md` lists as fixes that must not be undone.

**The balance audit's route stage.** Under M1 alone the world is the union of all acts, so
Bob-omb Battlefield's cannon is open on act 1 and Whomp's tower is already built. Under M2
that reverts, because each player is back in their own act. If M1 is ever shipped without M2,
`BALANCE_AUDIT.md`'s unfair-route stage has to be re-derived; if M2 follows immediately, it
does not.

---

## 11. Verification

Load the **`starhunt-testing` skill** (`.claude/skills/starhunt-testing/SKILL.md`) and run
the five checks in order. It holds the exact commands and the expected reports; they exist
nowhere else in the repository.

This change touches what two players share — warping, collision, the sync tables, loading
and the module `require` graph — so the live harness applies to every milestone, not only the
last.

What the live probe should report, before and after:

| | today | after M1 | after M3 |
|---|---|---|---|
| `my_act` / `their_act` | 1 / 6 | 1 / 1 | 1 / 1 |
| `active_them` | 0 | 1 | 1 |
| `their_pos_valid` | false | true | true |
| StarHunt hides them | yes | yes | no |
| collision lands | no | no | yes |

A change that adds or moves code also needs the mutation sweep. `tools/gen_mutations.py` and
`tools/sweep_mutations.py` are already in the repository; do not write new ones.

The one thing nothing automated reaches is a real multiplayer session, which is the only
place the suppressed objects can be seen to be genuinely absent and the fight can be seen to
be fair.

---

## 12. What this costs, and the rule that keeps it cheap

**The Lua side reproduces nothing the engine does.** It does not compute collision, move a
player, resolve a hit, drive an animation or draw anything. It writes two fields on some
objects, and the C code then behaves differently because of what it reads. Everything the
player experiences runs on the engine's ordinary path.

Where the work actually lands:

- **A suppressed object costs the client less than a live one, not more.**
  `load_object_collision_model_internal` returns at `src/engine/surface_load.c:979` when
  `collisionData` is NULL, so it never reaches `transform_object_vertices` or
  `load_object_surfaces` for that object, on any frame. `GRAPH_RENDER_INVISIBLE` removes its
  draw.
- **The added cost is C, and it comes from `disableActs`,** which spawns every act's objects
  on every client. Each client now ticks the behaviours of objects belonging to acts it
  cannot see, and those objects join object sync. Measure it in the live harness rather than
  guessing at it; a course with the most act-gated placements is the case to measure.
- **Load time.** Classification runs once per object, against the rows for one level. The
  mod already builds the star catalog, the modifier catalog and the full goal-by-modifier
  matrix at load (`rebuild_audited_modifiers`), which is far more work than this.
- **Per frame, the Lua budget goes down.** `update_private_player_visibility`
  (`StarHunt/modules/round.lua:946-974`) loops over every player every frame today and is
  deleted; `players_have_private_variant` runs from three call sites every frame today and is
  deleted. What replaces them is one sweep every thirty frames. `update_star_visibility`
  (`StarHunt/modules/goals.lua:885-910`) already walks an object list every frame and stays as
  it is.
- **The table is data.** Generated, never executed, consulted at object load and not again.

**The rule that keeps it this way: suppression is a state written once, not re-applied every
frame.** For the behaviours known to be act-gated, `LOAD_COLLISION_DATA` sits in the
behaviour script's init section, before `BEGIN_LOOP`, so the pointer is written once. But
several platform behaviours assign `o->collisionData` from C —
`src/game/behaviors/rotating_octagonal_plat.inc.c:12`, `ttc_cog.inc.c:29`,
`sliding_platform_2.inc.c:18`, `seesaw_platform.inc.c:20`,
`platform_on_track.inc.c:97`, `ttc_treadmill.inc.c:28`,
`animated_floor_switch.inc.c:78`. **When the table is generated, check whether any behaviour
in it appears in that list.** If one does, that object's suppression has to be re-asserted by
the sweep; if none does, it must not be, because re-asserting every frame is exactly the cost
this design exists to avoid.

If a later change finds itself doing per-frame work in Lua to hold this design together, that
is the signal to stop and re-read this section rather than to optimise the loop.

## 13. The engine change, which is what the mod targets

Everything above is a workaround for one thing: the published sm64coopdx uses `currActNum` for
two unrelated jobs and does not let a mod separate them.

1. **Which objects exist in my world.** `gCurrActNum`, read by the level script at
   `src/engine/level_script.c:534` and `:959`.
2. **Whether another player counts as being here with me.** `np->currActNum`, compared in the
   player-locality tests.

Job 1 must stay per-player; that is what an act *is*. Job 2 is the only thing standing between
StarHunt and a fair fight. Separate them and this entire document collapses: each client loads
exactly its own act at vanilla cost, with no `disableActs`, no generated table, no suppression,
no sweep and no restore — and the two players can still see, touch and damage each other.

**This requires a patched game**, which is the price of it: the change runs only where the
engine carries it, so it means a fork every player installs until it is upstream. The Lua
design above is the alternative, and needs no patch.

### The patch, as built

**One new field.** `u8 crossActPlayers;` in `struct LevelValues` (`src/game/hardcoded.h:64`,
beside `disableActs`), `FALSE` in `gDefaultLevelValues` (`src/game/hardcoded.c:46`).
`autogen/convert_structs.py` regenerates `smlua_cobject_autogen.c` on the next build, so
`gLevelValues.crossActPlayers` becomes Lua-settable with no binding work.

**One new helper**, replacing four open-coded copies of the same four-field comparison:

```c
bool network_player_location_mismatch(struct NetworkPlayer* np, bool compareAct) {
    if (gNetworkPlayerLocal == NULL) { return true; }
    return np->currCourseNum != gNetworkPlayerLocal->currCourseNum
        || np->currLevelNum  != gNetworkPlayerLocal->currLevelNum
        || np->currAreaIndex != gNetworkPlayerLocal->currAreaIndex
        || (compareAct && np->currActNum != gNetworkPlayerLocal->currActNum);
}
```

Existing callers pass `compareAct = true` and keep today's behaviour: `is_player_active`
(`src/game/obj_behaviors.c:552-557`) and `network_player_update_course_level`
(`src/pc/network/network_player.c:475-478`).

**One new predicate** for the player-to-player path, which passes
`compareAct = !gLevelValues.crossActPlayers` and is otherwise identical to `is_player_active`.

**Five call sites, and only five:**

| where | line |
|---|---|
| `interact_player`, both bodies | `src/game/interaction.c:1447`, `:1454` |
| `interact_player_pvp`, both bodies | `src/game/interaction.c:1481`, `:1482` |
| `execute_mario_action`, the hide block's `levelAreaMismatch` | `src/game/mario.c:2012-2020` |
| `network_receive_player` | `src/pc/network/packets/packet_player.c:265-270` |
| `nametags_render` | `src/pc/nametags.c:70` |

**One packet change.** `PACKET_PLAYER` is sent `PLMT_AREA` (`packet_player.c:234`), so
`packet_process` (`src/pc/network/packets/packet.c:47-55`) drops it on an act mismatch before
`network_receive_player` ever runs. Add a value to the `PacketLevelMatchType` enum
(`packet.h:86-88`) that compares level and area but not act, give `struct Packet` the matching
flag in `packet_init` (`packet_read_write.c`), and send `PACKET_PLAYER` with it when
`gLevelValues.crossActPlayers` is set.

### What must not change, and why the patch is safe because of it

- **`is_player_active` itself keeps the act.** It has 55 callers and about forty are behaviours
  choosing a target — `nearest_mario_state_to_object`, `is_point_within_radius_of_any_player`,
  `cur_obj_is_any_player_on_platform`, `king_bobomb_nearest_mario_state`,
  `eyerok_nearest_targetable_player_to_object` and the rest. Relaxing it globally would let a
  Whomp in your act chase a player who cannot see it, and a platform in your act count a rider
  who is not in its world.
- **`get_network_player_from_area` keeps the act** (`network_player.c:129-142`), so each act
  remains its own object-sync world and no client tries to sync objects the other does not have.
- **Object, area, level and macro packets keep `PLMT_AREA` / `PLMT_LEVEL`.** Only the player
  packet crosses.

Two things already in the engine shrink the patch:

- `mario_process_interactions` (`src/game/interaction.c:2377-2389`) already refuses every object
  interaction for a remote player except `INTERACT_PLAYER` and `INTERACT_POLE`, so a cross-act
  player cannot trigger your act's objects on your machine. No new guard is needed.
- `is_player_active` returns early for `np->type == NPT_LOCAL` before any location test, and
  `interact_player_pvp` is driven from the local player's own `mario_process_interactions`, so
  only the victim's check actually has to be relaxed.

### The second patch: a body in another act is placed by its owner

The first patch leaves one cost, and it is the only one it leaves. A remote Mario is simulated
locally every frame — `bhv_mario_update` (`src/game/object_list_processor.c:245`) calls
`execute_mario_action` for every player, and the action switch runs the body's own action
against **this** client's collision. `network_receive_player` then writes the owner's position
over it whenever a packet arrives, which is every third frame at most
(`network_update_player`, `packet_player.c:426`, called from `src/pc/network/network.c:590`).
Where the two clients hold the same geometry that costs a unit or two. Where they do not, the
body falls locally and is pulled back twenty times a second.

So while `crossActPlayers` is set and the remote player's act differs, the body is not
simulated here at all:

- `execute_mario_action` sets `inLoop = FALSE` for such a body, so the action switch does not
  run, and calls `network_owner_driven_advance` instead. The rest of the function is unchanged:
  interactions, health, hitbox and cap model all still run, which is what keeps the fight
  working.
- `network_receive_player` hands the arriving position to `network_owner_driven_target` rather
  than letting it stand, and restores the position the body is being moved from. Each frame the
  body covers a fraction of that distance, the fraction being one over the number of frames the
  previous packet took to arrive, so it reaches the owner's position about as the next packet
  lands. A target further away than 150 units per frame of that interval is a warp rather than
  motion and is covered in one frame.
- **The pose has to travel, or this cannot work.** Nothing else sets a remote Mario's
  animation: `set_mario_animation` is called from inside the action functions
  (`src/game/mario.c:116`), and `header.gfx.animInfo` is not among the object fields
  `PACKET_PLAYER` already carries (`packet_player.c:95`). So `animID`,
  `animFrameAccelAssist` and `animAccel` are added to `struct PacketPlayerData` and applied on
  arrival. The frame counter then advances in the render path
  (`geo_update_animation_frame`, called from `src/game/rendering_graph_node.c:1240`), so the
  animation keeps running between packets and each packet re-syncs it.

What this costs, stated plainly: such a body no longer produces footstep sounds, landing sounds
or dust, because the action code that produces them does not run for it — `network_receive_player`
resets the sound-played flags at `packet_player.c:308` for exactly that reason, and there is now
nothing to play them. And the body renders about one packet interval behind its owner. A body
that is smooth and slightly behind is the trade this takes over one that vibrates.

**Measured, both ways, by the live harness's `hull` case.** One client stands on the sunken
ship's deck; the other holds the act 1 goal and never spawned it. Fifty counted samples per
case, three processes on one loopback:

| | placed by its owner | simulated locally |
|---|---|---|
| the client with no deck under that body: `error_max` | 0.9 | 24.3 |
| `step_max` | 0.2 | 24.3 |
| `flips` | 0 | 25 |
| the client on the deck, watching a body fall: `error_max` | 295.5 | 219.9 |
| `error_mean` | 98.6 | 8.9 |
| `step_max` | 135.8 | 294.9 |
| `flips` | 2 | 3 |

So the sawtooth is gone where the two clients disagree about the ground, which is what this is
for. The second half of the table is the price: a body placed by its owner is a few frames
behind, and the falling body in that case covers about 75 units a frame, so being three frames
behind reads as hundreds of units. A locally simulated body tracks a fall almost exactly,
because gravity is the same on both machines — it is only geometry the two disagree about. The
same trade shows in `split`, where a player walks in over ground both clients hold:
`error_xz_max` around 30 placed by its owner, 0 simulated locally.

**The alternative not taken**, so it can be: aim at where the owner's own velocity puts the body
by the time it gets there, rather than at the position the packet reported. `vel` is already in
the packet, so it costs nothing on the wire, and it would remove most of that lag — a fall is
the case prediction is best at. It is not done because it puts the body somewhere its owner has
not been yet, so an abrupt stop overshoots and is pulled back, which is a different artefact
rather than none.

**Same-act remote players are untouched.** The predicate is
`network_player_is_cross_act`, which asks only whether the acts differ while the field is set,
so every pair that shares an act keeps today's local simulation — which is correct for them,
holds the same collision, and hides latency.

**The packet body changes, so the version string does too.** `packet_join.c:157-165` compares
version strings exactly and refuses the connection on a mismatch, and the first patch left
`SM64COOPDX_VERSION` at upstream's `v1.5.1`. That was safe while only the flag byte changed: a
stock client does not know bit 4 and simply keeps treating player packets as act-matched. It is
not safe once `struct PacketPlayerData` grows, because a stock client would pass the handshake
and then read every player packet at the wrong offsets. The fork reports
`v1.5.1-crossact`, so the game refuses the pair at the join screen instead.

### What a reviewer will ask

- A remote player in another act is placed by its owner and not simulated locally, so the
  jitter the first patch would have left is gone. What is left to judge is the trade above: no
  footsteps, no dust, and one packet interval of lag on that body.
- `resolve_player_collision` will let a player stand on another who is standing on nothing
  visible.
- `take_damage_and_knock_back` will knock a player into geometry that exists only for them.
- The flag is per-client. Co-op DX enforces a common mod list, so both ends run the same mod,
  but the pull request should say plainly that mismatched flags give one-directional behaviour.

The argument for upstream: four copies of one comparison become one function, the new behaviour
is off by default, and it makes a class of mod possible that cannot be written today.

### What StarHunt is on top of it

`round.lua` warps to `goal.act` as it always did. No `disableActs`, no `actdata.lua`, no
`world.lua`, no sweep, no suppression, no restore. `enable_cross_act_players`
(`modules/core.lua`) sets `gLevelValues.crossActPlayers` once at load, and only where the build
has the field; `players_have_private_variant`, both zone tests,
`update_private_player_visibility`, the nametag blanking and R-030's `INTERACT_PLAYER` refusal
are gone. The fairness rule is (a): nothing is refused between two players, wherever they are
standing. Sections 4 through 12 do not apply to what is installed.

## 14. Deliberately not done

- **No volume table and no measured half-extents.** R-028 proposed axis-aligned boxes whose
  extents had to be measured in game. The generated table carries each object's identity and
  spawn position, and the engine carries its collision, so the boxes are unnecessary unless
  rule (c) is ever wanted.
- **No silhouette.** The other player is a full, ordinary Mario. The translucent fade R-028
  wanted already exists in the engine (`src/game/mario.c:2054-2064`) and applies to players
  who are genuinely elsewhere; this design stops that case arising inside one course.
- **No mod-side combat.** `take_damage_and_knock_back` is exposed to Lua
  (`src/game/interaction.c:856-883`) and does not test `is_player_active`, so a mod could
  apply hits between players the engine has severed. This design does not, because keeping
  the pair in one act instance gets the real engine path, with collision, which a mod-applied
  hit cannot have.
- **No deletion of unused acts' objects.** Every client runs every act's object behaviours,
  including the ones it has suppressed. Deleting them would cut that cost but would leave the
  other client sending updates for objects that no longer exist locally.
