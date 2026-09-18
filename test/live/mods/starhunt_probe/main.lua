-- name: AAA StarHunt Probe
-- description: Drives StarHunt inside a headless sm64coopdx for test/live. Not a mod for players.

-- This mod exists only for test/live/run.sh. It is never installed alongside a
-- real game: it starts rounds by itself, teleports players and prints machine
-- readable lines to stdout, which run.sh reads back.
--
-- **The name has to sort before StarHunt's, and the flag has to go on _G.**
-- sm64coopdx loads mods in alphabetical order of the uncoloured `-- name:`
-- header (`mods_sort` in src/pc/mods/mods.c), so "AAA ..." runs before
-- StarHunt, which reads the flag once at load time. There is one Lua state for
-- every mod, but each mod runs with its own _ENV table whose metatable reads
-- through to the real globals (`smlua_load_script`), so a bare assignment would
-- land in this mod's environment where nothing else can see it. Writing the
-- field on _G reaches the table StarHunt's rawget actually looks in.
_G.STARHUNT_TEST_MODE = true

-- What this probe drives, one line per case. run.sh matches on these exact
-- prefixes, so they are an interface: PROBE <key> <field>=<value> ...
local PROBE = "PROBE"

-- sm64coopdx opens luaopen_base, so print() exists and goes to the process's
-- stdout, which is what run.sh reads. log_to_console is the fallback in case a
-- build trims the base library.
local function say(key, text)
    local line = PROBE .. " " .. key .. " " .. text
    local out = rawget(_G, "print")
    if type(out) == "function" then out(line) else log_to_console(line) end
end

-- **Three instances, and the two that collide are both clients.**
--
-- The obvious arrangement -- a headless host and one client, bumping into each
-- other -- cannot work. A process started with `--headless --server` sets
-- `gServerSettings.headlessServer` (src/pc/network/network.c:140), and that one
-- flag makes its own player inert in two separate places:
--
--   * `network_update_player` (packets/packet_player.c:430) returns before
--     sending anything, so the host's position is never transmitted and every
--     client sees it frozen wherever it first appeared;
--   * `is_player_active` (src/game/obj_behaviors.c:547) returns FALSE for the
--     server's player on **every** instance, and `interact_player` asks that
--     question about both bodies before it reaches `resolve_player_collision`.
--
-- So a headless host can referee but can never touch anybody. The harness
-- therefore runs a dedicated headless server plus two headless clients, and the
-- collision it measures is between the two clients.
local ROLE = nil            -- "server" | "player"
local MY_GLOBAL = nil
local OTHER = nil           -- the other client's local index, on a client
local IS_ANCHOR = false     -- lower global index stands still; the other walks in

-- Frames to let an area settle before touching anything. interact_player
-- refuses every contact while gCurrentArea->localAreaTimer < 60, so a shorter
-- wait would read as "they passed through each other" for the wrong reason.
local AREA_SETTLE_FRAMES = 120

-- What counts as "the engine pushed them apart". resolve_player_collision
-- separates two players to 2 * hitboxRadius, and Mario's radius is 37, so a
-- push parks them at about 74.
local PUSH_DISTANCE = 74.0
local SEPARATED = PUSH_DISTANCE - 4.0

-- **How far apart the two are placed, and why it is not zero.**
-- resolve_player_collision pushes along the vector between the two torsos:
--
--     posX = m->pos[0] + (radius - marioDist) / radius * marioRelX
--
-- Placed exactly on top of each other, marioRelX and marioRelZ are both 0, the
-- whole term is 0 and nobody moves however hard the engine tries. A pair that
-- overlaps perfectly is therefore indistinguishable from a pair the engine
-- refused, so the pair is never placed at a single point.
local PLACE_OFFSET = 20.0

-- Samples thrown away at the start of each measurement, before the
-- disagreement between the two clients is believed. Both players teleport into
-- place, and for the few frames before the first position packet lands each
-- holds the other's body wherever it was standing beforehand -- which is a real
-- disagreement, but about the teleport rather than about the ground.
local SETTLE_SAMPLES = 10

-- How far a player has to have moved from where it was put down for that to
-- count as a push. An idle Mario on flat ground with zero velocity does not
-- drift, so anything above a few units is the engine.
local PUSHED_DRIFT = 20.0

-- What each case asks, keyed by the name CASE lists it under. `split` records
-- what the engine does without the mod and `shared` is the control; the rest
-- are about StarHunt. CASE also fixes the order they run in.
--
--  split  -- the two players hold TTC goals for acts 6 and 1 and are each
--            standing in their own act, which is what an ordinary StarHunt
--            round produces. They must collide. Stock sm64coopdx refuses this
--            contact before any hook -- is_player_active compares the two
--            players' currActNum -- so what this case measures is the engine
--            being asked to leave the act out of that comparison, which the mod
--            does at load with gLevelValues.crossActPlayers. **This is the case
--            that fails when that request is removed.**
--
--  hull   -- the case that measures the disagreement rather than the contact.
--            One player holds a Jolly Roger Bay goal for act 4 and stands on
--            the deck of the ship that exists only in acts 2-6; the other holds
--            the act 1 goal, where that ship is not there at all and the sea
--            floor is thousands of units below. Neither re-warps. **It reports
--            no push**: the body with no deck under it falls, and falling is not
--            being pushed. What it reports is how far apart the two clients'
--            idea of the ground under a body is, and the jitter that comes of
--            it -- each client simulates the other's Mario against its own
--            collision between packets, and every arriving packet snaps it back.
--
--  shared -- both players hold the act 6 goal, so the predicate is false and
--            the mod leaves the contact alone. The engine must push these two
--            apart. Without this control a run where the bodies never touch at
--            all reports every other case as a pass.
--
--  ddd    -- two Dire Dire Docks goals on different acts, with the second
--            player walking back into the first's act the way "hidden" does.
--            Here the predicate must answer **false**: the only act-gated
--            object in that course is the manta ray, and the submarine, its
--            door and the nine poles read SAVE_FLAG_HAVE_KEY_2 |
--            SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR out of a save file every client
--            receives from the host. So the engine has to push these two apart,
--            and each client reports the flags it reads for the run to check
--            that they agree. **This is the case that fails if DDD is isolated
--            by act again.**
--
--  wdw    -- two Wet-Dry World goals on different acts, played exactly the way
--            "ddd" is. The predicate must answer **false** here too: every
--            object in both areas of levels/wdw/script.c is ALL_ACTS, and the
--            water level -- the one state two clients can disagree on -- is not
--            derived from the act and reaches every player who can meet
--            another, because the engine's area sync matches on the same four
--            fields is_player_active does (packet_area.c:52, :155-157;
--            network_player.c:129-142). **This is the case that fails if WDW is
--            isolated by act again.**
local CASE = { "split", "shared", "hull", "ddd", "wdw" }

-- Which cases the two players are in different acts for. A case whose acts
-- quietly stopped differing -- or started -- would report a pass for the wrong
-- reason, so each client checks its own pair against this before measuring.
local WANT_CROSS_ACT = { split = true, shared = false, hull = true, ddd = false, wdw = false }

-- The save flags the submarine, its door and the nine poles read:
-- bhv_bowsers_sub_loop (src/game/behaviors/ddd_sub.inc.c:4) deletes the
-- submarine once either is set, bhv_ddd_pole_init (ddd_pole.inc.c:3) deletes
-- each pole until one is. Every client is given the host's save file, so both
-- must report the same value.
local DDD_SAVE_GATE = SAVE_FLAG_HAVE_KEY_2 | SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR

local state = "wait_api"
local since = 0
local phase = 0
-- STARHUNT_TEST_API is a table the mod builds at run time, so nothing the type
-- checker can read describes its shape. Saying so here keeps the annotation to
-- one line instead of a nil check at every use.
---@type any
local api = nil
local ttc = { act_6 = nil, act_other = nil }
-- The goal pair each shared-course case hands out, keyed by case name.
local pair_for = {}
local placed_at = nil
local drift = 0
local reach = 0
local samples = 0
local rewarped = false
local moved = false
local landed = false
local deck_at = nil
-- What this client's simulation of the other player's body disagrees with.
-- `sim_*` describe the body as this client moves it; `error_*` compare that
-- against where its owner says it is, published through the sync table, which
-- crosses acts because Lua sync tables are PLMT_NONE.
local last_sim_y = nil
local sim_dir = 0
local sim_step_max = 0
local sim_flips = 0
local error_max = 0
local error_sum = 0
local error_n = 0
local floor_gap = 0
local rtt_max = 0

--- The two TTC goals the cases need: act 6, and any other act.
-- Act 6 stops the clock while the others run it, so the two players do not even
-- agree on where the course's moving platforms are -- the hardest case for a
-- fight between two acts, which is why it is the one measured. Goals that
-- require a cap are skipped: a vanish cap makes interact_player return before
-- it can reach resolve_player_collision, which would pass for the wrong reason.
local function pick_ttc_goals()
    local a, b
    for id, goal in ipairs(api.goals) do
        if goal.level == LEVEL_TTC and (goal.power == nil or goal.power == 0) then
            if goal.act == 6 then a = id elseif b == nil then b = id end
        end
    end
    return a, b
end

--- The two goals a shared-course case needs: its `act` and its `other_act`.
-- Cap-free for the same reason as the TTC pair: a vanish cap makes
-- interact_player return before it reaches resolve_player_collision, which
-- would report a pass for the wrong reason.
local function pick_act_pair(course)
    local a, b
    for id, goal in ipairs(api.goals) do
        if goal.level == course.level and (goal.power == nil or goal.power == 0) then
            if goal.act == course.act then a = id
            elseif goal.act == course.other_act then b = id end
        end
    end
    return a, b
end

local function connected_count()
    local n = 0
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then n = n + 1 end
    end
    return n
end

--- The other client, as this instance indexes it.
-- `type` is what separates the three: NPT_LOCAL is this process's own player,
-- NPT_SERVER is the referee (whose body cannot collide with anything), and
-- NPT_CLIENT is the player this one is meant to bump into.
local function find_other_client()
    for i = 1, MAX_PLAYERS - 1 do
        local np = gNetworkPlayers[i]
        if np ~= nil and np.connected and np.type == NPT_CLIENT then return i end
    end
    return nil
end

--- PLAYER_INTERACTIONS_PVP is what makes the bodies touch at all, so it is
-- worth printing; it is read through pcall because a server setting the build
-- does not expose would otherwise take the whole probe down with it.
local function server_interactions()
    local ok, value = pcall(function() return gServerSettings.playerInteractions end)
    if not ok then return "unreadable" end
    return tostring(value)
end

local function horizontal_distance(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

--- A patch of floor with room for two players to be pushed apart on.
-- resolve_player_collision computes where the push would land and abandons it
-- when find_floor_height comes back with the lower limit -- "Prevent a push
-- into out of bounds" -- so two players standing near the edge of a small
-- platform are never separated at all. The entrance platform in Tick Tock Clock
-- is exactly that small, which is why the first runs measured no push for a
-- pair the engine should have collided.
--
-- Returns a point whose own floor and whose neighbours a push-distance away in
-- eight directions all sit at about the same height, or nil.
local function open_ground_near(m)
    local probe_y = m.pos.y + 200
    local base = find_floor_height(m.pos.x, probe_y, m.pos.z)
    local function level_floor(x, z, want)
        local h = find_floor_height(x, probe_y, z)
        return (h > want - 60 and h < want + 60), h
    end
    for _, radius in ipairs({ 0, 150, 300, 450, 600 }) do
        for step = 0, 7 do
            local angle = step * math.pi / 4
            local x = m.pos.x + math.cos(angle) * radius
            local z = m.pos.z + math.sin(angle) * radius
            local flat, height = level_floor(x, z, base)
            if flat then
                local room = true
                for nstep = 0, 7 do
                    local nangle = nstep * math.pi / 4
                    local ok = level_floor(x + math.cos(nangle) * (PUSH_DISTANCE + 30),
                                           z + math.sin(nangle) * (PUSH_DISTANCE + 30), height)
                    if not ok then room = false break end
                end
                if room then return x, height, z end
            end
        end
    end
    return nil
end

--- A patch of deck belonging to an object only some acts spawn.
--
-- The ship's collision comes out of the ROM (`ROM_ASSET_LOAD_COLLISION`,
-- levels/jrb/wooden_ship/collision.inc.c), so its extent is not something this
-- file can know, and the column above the object's own spawn point turns out to
-- hold no surface at all. So the deck is searched for rather than assumed, and
-- `collision_find_floor` answers with the surface itself, which lets the search
-- require that the floor belongs to the behaviour carrying that collision.
--
-- The search starts well above the deck: `collision_find_floor` answers with the
-- highest floor below the y it is given.
local function deck_near(cross)
    local x0, _, z0 = cross.stand()
    local probe_y = cross.deck_search_y
    for _, radius in ipairs({ 0, 120, 240, 360, 480, 600, 720, 840, 960, 1080, 1200 }) do
        for step = 0, 11 do
            local angle = step * math.pi / 6
            local x = x0 + math.cos(angle) * radius
            local z = z0 + math.sin(angle) * radius
            local surface = collision_find_floor(x, probe_y, z)
            if surface ~= nil and surface.object ~= nil
                and obj_has_behavior_id(surface.object, cross.floor_beh) ~= 0 then
                return x, find_floor_height(x, probe_y, z), z
            end
        end
    end
    return nil
end

--- Where the "ddd" pair meets, in Dire Dire Docks area 1.
-- Fixed rather than searched, for two reasons. The shaft the players drop into
-- ends in a whirlpool -- hitbox radius 200, height 500 at -3174, -4915, 102
-- (`sWhirlpoolHitbox`, src/game/behaviors/whirlpool.inc.c) -- and a pair placed
-- on the floor beside it is carried apart by the current, which reads exactly
-- like a push. And the point has to sit where a rule isolating DDD by act would
-- have fired, or the case cannot go red when one comes back.
--
-- x and z are the column the level's own MARIO_POS drops Mario down
-- (levels/ddd/script.c, `MARIO_POS(1, 180, -3071, 3000, 500)`), so it is open
-- water from the surface to the floor. The depth is taken from the water
-- surface, so two players sink together at the same rate instead of falling.
local DDD_SPOT_X = -3071.0
local DDD_SPOT_Z = 500.0
local DDD_SPOT_DEPTH = 300.0

local function ddd_meeting_point()
    return DDD_SPOT_X, find_water_level(DDD_SPOT_X, DDD_SPOT_Z) - DDD_SPOT_DEPTH, DDD_SPOT_Z
end

-- The courses whose acts must not be private, one case each. `act` is the act
-- both bodies end up standing in and `other_act` the one the second player's
-- goal names; a case with no `meet` is played wherever open_ground_near finds
-- room, the way the Tick Tock Clock cases are.
--
-- Both acts in each pair are cap-free, for the same reason the TTC pair is:
-- DDD acts 4 and 6 carry Metal and Metal+Vanish, and WDW act 6 carries Vanish.
--
-- Wet-Dry World needs no meeting point of its own. Its water comes from
-- geo_wdw_set_initial_water_level (moving_texture.c:305) reading
-- gPaintingMarioYEntry, which no instance here ever writes -- nobody enters a
-- painting -- so it stays at its initial 0.0 (moving_texture.c:119) and the
-- course is drained to 31 units for every player. The ground by the entrance is
-- dry floor in every run.
local SHARED_COURSE = {
    ddd = { level = LEVEL_DDD, act = 1, other_act = 3, meet = ddd_meeting_point },
    wdw = { level = LEVEL_WDW, act = 1, other_act = 3 },
}

-- Where the anchor stands for "hull", and what its floor has to be.
--
-- Jolly Roger Bay puts a second ship at 4880, 820, 2375 in acts 2 to 6
-- (levels/jrb/script.c:25-29) and nothing there in act 1, whose ship is sunk at
-- 5385, -5520, 2428. The deck's collision belongs to `bhvInSunkenShip3`, the one
-- object of that group carrying LOAD_COLLISION_DATA
-- (`jrb_seg7_collision_in_sunken_ship_3`, data/behavior_data.c:2718-2728); the
-- four `bhvShipPart3` objects beside it are models only. So the drop starts above
-- the deck and the landing is checked against that behaviour: the case must not
-- be able to pass by landing on the sea floor instead.
--
-- The ship rocks -- `bhv_ship_part_3_loop` drives its pitch and roll from a sine
-- (src/game/behaviors/ship_part.inc.c) -- which is why this case reads a
-- disagreement rather than a drift.
local HULL_X, HULL_Y, HULL_Z = 4880.0, 820.0, 2375.0
local HULL_DROP = 500.0

-- Courses where the two players stay in their own acts, so the pair is
-- genuinely cross-act and the clients disagree about the ground. `act` is the
-- anchor's goal act, `other_act` the other player's; both are cap-free, since
-- only Jolly Roger Bay act 6 carries one.
local CROSS_COURSE = {
    hull = { level = LEVEL_JRB, act = 4, other_act = 1,
             stand = function() return HULL_X, HULL_Y + HULL_DROP, HULL_Z end,
             deck_search_y = HULL_Y + 2000.0,
             floor_beh = id_bhvInSunkenShip3 },
}


local function place_at(m, x, y, z)
    m.pos.x, m.pos.y, m.pos.z = x, y, z
    m.vel.x, m.vel.y, m.vel.z = 0, 0, 0
    m.forwardVel = 0
    placed_at = { x = x, y = y, z = z }
    drift = 0
    reach = 0
    samples = 0
    last_sim_y = nil
    sim_dir = 0
    sim_step_max = 0
    sim_flips = 0
    error_max = 0
    error_sum = 0
    error_n = 0
    floor_gap = 0
    rtt_max = 0
end

local function fmt(value)
    return string.format("%.1f", value)
end

--- Publish where this player actually is, for the other client to check its own
-- simulation against. One write per frame per field while a case is being
-- measured; the sync table is the only channel between two players in different
-- acts, since PACKET_PLAYER is the thing under test.
local function publish_truth(m)
    local mine = gPlayerSyncTable[0]
    mine.sh_probe_tx = m.pos.x
    mine.sh_probe_ty = m.pos.y
    mine.sh_probe_tz = m.pos.z
    mine.sh_probe_tf = m.floorHeight
    mine.sh_probe_tick = samples
    -- **Stamped with the case.** These fields carry on holding the last case's
    -- numbers until the next one starts publishing, and a floor height from the
    -- previous course compared against a position in this one reads as a
    -- disagreement of thousands of units.
    mine.sh_probe_tcase = phase
end

--- How far this client's idea of the other player's body is from its owner's,
-- and how the ground under it compares.
--
-- Between packets each client runs the remote Mario's action against its own
-- collision, and `network_receive_player` snaps it back when a packet arrives
-- (src/pc/network/packets/packet_player.c). Where the two clients hold the same
-- geometry that costs a unit or two; where they do not -- a deck one of them
-- has never spawned -- the body falls locally and is pulled back thirty times a
-- second, which is the jitter this measures.
--
-- `flips` counts direction changes in the body's vertical motion as this client
-- sees it, which is the sawtooth itself rather than its size. `rtt_frames` is a
-- round trip through the mod's sync table in this client's own frames: the
-- other client echoes the tick it last saw, so the comparison never needs the
-- two frame counters to agree.
local function sample_disagreement(them)
    local truth = gPlayerSyncTable[OTHER]
    local sim_y = them.pos.y
    if samples <= SETTLE_SAMPLES then
        last_sim_y = sim_y
        return
    end
    if (truth.sh_probe_tcase or -1) ~= phase then
        last_sim_y = sim_y
        return
    end
    if last_sim_y ~= nil then
        local step = sim_y - last_sim_y
        if math.abs(step) > sim_step_max then sim_step_max = math.abs(step) end
        if step > 0.5 then
            if sim_dir < 0 then sim_flips = sim_flips + 1 end
            sim_dir = 1
        elseif step < -0.5 then
            if sim_dir > 0 then sim_flips = sim_flips + 1 end
            sim_dir = -1
        end
    end
    last_sim_y = sim_y

    local ty = truth.sh_probe_ty
    if ty ~= nil then
        local err = math.abs(sim_y - ty)
        if err > error_max then error_max = err end
        error_sum = error_sum + err
        error_n = error_n + 1
        local tx, tz, tf = truth.sh_probe_tx, truth.sh_probe_tz, truth.sh_probe_tf
        if tx ~= nil and tz ~= nil and tf ~= nil then
            local gap = math.abs(find_floor_height(tx, ty + 100, tz) - tf)
            if gap > floor_gap then floor_gap = gap end
        end
    end

    local tick = truth.sh_probe_tick
    if tick ~= nil then gPlayerSyncTable[0].sh_probe_echo = tick end
    local echo = truth.sh_probe_echo
    if echo ~= nil and echo > 0 then
        local rtt = samples - echo
        if rtt >= 0 and rtt > rtt_max then rtt_max = rtt end
    end
end

local function enter(next_state)
    state = next_state
    since = 0
end

--- Give the two client players the goals a case needs.
-- Each client warps itself from its own sh5_goal and only acts on a goal it has
-- not seen, so the sequence counter has to move as well. The referee's own
-- player keeps whatever goal the mod gave it; its body takes part in nothing.
local function assign(first, second)
    local a, b = 1, 2   -- on the server the local index IS the global index
    if not gNetworkPlayers[a].connected or not gNetworkPlayers[b].connected then return false end
    for _, pair in ipairs({ { a, first }, { b, second } }) do
        local sync = api.player_sync[pair[1]]
        sync.sh5_goal = pair[2]
        sync.sh5_goal_seq = (sync.sh5_goal_seq or 0) + 1
        sync.sh5_modifier = 0
        sync.sh5_modifier_2 = 0
    end
    return true
end

--- Everything a pair that refuses to collide could be refusing over.
-- `is_player_active` is the decisive one: interact_player asks it about both
-- bodies, and it is false for a headless server's player and for any remote
-- player whose course, act, level or area does not match the local one.
local function gates(other_mario, distance)
    local me = gMarioStates[0]
    local mine = me.marioObj ~= nil and me.marioObj.collidedObjInteractTypes or 0
    local my_np, their_np = gNetworkPlayers[0], gNetworkPlayers[OTHER]
    say("gates", "role=" .. ROLE .. MY_GLOBAL .. " case=" .. CASE[phase]
        .. " dist=" .. string.format("%.1f", distance)
        .. " drift=" .. string.format("%.1f", drift)
        .. " active_me=" .. tostring(is_player_active(me))
        .. " active_them=" .. tostring(is_player_active(other_mario))
        .. " active_them_cross_act=" .. tostring(is_player_active_cross_act(other_mario))
        .. " collided=" .. tostring((mine & INTERACT_PLAYER) ~= 0)
        .. " interactions=" .. server_interactions()
        .. " headless_server=" .. tostring(gServerSettings.headlessServer)
        .. " my_act=" .. tostring(my_np.currActNum) .. " their_act=" .. tostring(their_np.currActNum)
        .. " my_area=" .. tostring(my_np.currAreaIndex) .. " their_area=" .. tostring(their_np.currAreaIndex)
        .. " their_pos_valid=" .. tostring(their_np.currPositionValid)
        .. " my_action=" .. string.format("%08X", me.action or 0)
        .. " invinc=" .. tostring(me.invincTimer) .. "," .. tostring(other_mario.invincTimer)
        -- resolve_player_collision refuses outright when the two torsos are
        -- further apart vertically than one hitbox height (160).
        .. " dy=" .. string.format("%.1f", math.abs(me.pos.y - other_mario.pos.y))
        .. " their_xz=" .. string.format("%.0f,%.0f", other_mario.pos.x, other_mario.pos.z))
end

--- The referee half: start a round, hand out the case's goals, wait for both
-- players to report, move on.
local function update_server()
    if state == "wait_players" then
        if connected_count() < 3 then
            if since % 600 == 0 then say("waiting", "role=server players=" .. connected_count()) end
            return
        end
        say("players", "role=server count=" .. connected_count())
        enter("start_round")

    elseif state == "start_round" then
        -- A moment for both players to be enrolled: host_start_round takes
        -- whoever is connected when it runs.
        if since < 60 then return end
        ttc.act_6, ttc.act_other = pick_ttc_goals()
        if ttc.act_6 == nil or ttc.act_other == nil then
            say("fail", "reason=no_ttc_goal_pair")
            enter("done")
            return
        end
        for _, courses in ipairs({ SHARED_COURSE, CROSS_COURSE }) do
            for name, course in pairs(courses) do
                local stay, other = pick_act_pair(course)
                if stay == nil or other == nil then
                    say("fail", "reason=no_goal_pair case=" .. name)
                    enter("done")
                    return
                end
                pair_for[name] = { stay = stay, other = other }
            end
        end
        api.global_sync.sh5_mode = 0        -- SH.Mode.NORMAL
        api.global_sync.sh5_difficulty = 1  -- SH.Difficulty.MEDIUM
        if not api.host_start(10) then
            say("fail", "reason=host_start_refused")
            enter("done")
            return
        end
        say("round", "started goals=" .. ttc.act_6 .. "," .. ttc.act_other)
        enter("await_assignment")

    elseif state == "await_assignment" then
        -- host_start_round only opens the round: it ends at sh5_active = 1 and
        -- leaves every goal at 0. host_update_round hands the goals out on a
        -- later frame, so an override written straight after the start is undone
        -- a frame later and both players warp to whatever the mod rolled.
        local a, b = 1, 2   -- on the server the local index IS the global index
        if (api.player_sync[a].sh5_goal or 0) == 0 or (api.player_sync[b].sh5_goal or 0) == 0 then
            if since % 600 == 0 then say("waiting", "role=server reason=no_goals_yet") end
            return
        end
        phase = 1
        enter("open_case")

    elseif state == "open_case" then
        local first = ttc.act_6
        local second = (CASE[phase] == "shared") and ttc.act_6 or ttc.act_other
        -- A shared-course case hands out a fresh pair, so both clients warp
        -- into that course; the anchor's goal is the act they will both end up
        -- standing in.
        local shared = SHARED_COURSE[CASE[phase]] or CROSS_COURSE[CASE[phase]]
        if shared then first, second = pair_for[CASE[phase]].stay, pair_for[CASE[phase]].other end
        if not assign(first, second) then
            say("fail", "reason=players_left")
            enter("done")
            return
        end
        -- The clients learn a case has started from the global sync table,
        -- which only the server may write.
        gGlobalSyncTable.sh_probe_case = phase
        say("case", "name=" .. CASE[phase] .. " goals=" .. first .. "," .. second)
        enter("await_reports")

    elseif state == "await_reports" then
        local done = 0
        for i = 1, MAX_PLAYERS - 1 do
            if (gPlayerSyncTable[i].sh_probe_done or 0) == phase then done = done + 1 end
        end
        if done < 2 then
            if since % 900 == 0 then say("waiting", "role=server reason=reports done=" .. done) end
            return
        end
        if phase >= #CASE then
            enter("done")
        else
            phase = phase + 1
            enter("open_case")
        end

    elseif state == "done" then
        if since == 1 then say("end", "role=server") end
    end
end

--- The player half: wait for a case, stand the pair on top of each other, and
-- measure whether the engine moved this instance's own player away.
local function update_player()
    if state == "wait_players" then
        OTHER = find_other_client()
        if connected_count() < 3 or OTHER == nil then
            if since % 600 == 0 then say("waiting", "role=player players=" .. connected_count()) end
            return
        end
        MY_GLOBAL = gNetworkPlayers[0].globalIndex
        IS_ANCHOR = MY_GLOBAL < gNetworkPlayers[OTHER].globalIndex
        say("players", "role=player" .. MY_GLOBAL .. " count=" .. connected_count()
            .. " other=" .. OTHER .. " anchor=" .. tostring(IS_ANCHOR))
        enter("await_case")

    elseif state == "await_case" then
        local want = gGlobalSyncTable.sh_probe_case or 0
        if want == 0 or want == phase then
            if since % 900 == 0 then say("waiting", "role=player" .. MY_GLOBAL .. " reason=no_new_case") end
            return
        end
        phase = want
        rewarped = false
        moved = false
        landed = false
        deck_at = nil
        gPlayerSyncTable[0].sh_probe_ready = 0
        gPlayerSyncTable[0].sh_probe_placed = 0
        enter("settle")

    elseif state == "settle" then
        local mine, theirs = gNetworkPlayers[0], gNetworkPlayers[OTHER]
        -- The course this case is played in, and the act the second player ends
        -- up standing in.
        local shared = SHARED_COURSE[CASE[phase]]
        local cross = CROSS_COURSE[CASE[phase]]
        local course = (shared and shared.level) or (cross and cross.level) or LEVEL_TTC
        local stand_in = shared and shared.act
        -- Both of StarHunt's own warps have to have landed before anything
        -- moves a player: a case that changes sh5_goal makes the mod warp that
        -- client, and a self-warp issued first is undone when the mod's arrives.
        -- Level and area are exchanged even between players the engine will not
        -- let interact, so this is readable in every case.
        if mine.currLevelNum ~= course or theirs.currLevelNum ~= course then
            if since % 900 == 0 then
                say("waiting", "role=player" .. MY_GLOBAL .. " reason=not_in_course"
                    .. " want=" .. course
                    .. " lvl=" .. tostring(mine.currLevelNum) .. "," .. tostring(theirs.currLevelNum))
            end
            since = 0
            return
        end
        -- **A shared-course case is made here, by moving rather than by
        -- reassigning.** This player keeps the goal StarHunt gave it -- so the
        -- two goals still name different acts -- but walks into the act the
        -- other one is standing in. That is what makes it a case about a course
        -- whose worlds agree: the pair is in one act, and anything that keeps
        -- them apart is the mod isolating a pair it has no reason to.
        if shared and not IS_ANCHOR then
            if not rewarped then
                rewarped = true
                warp_to_level(course, 1, stand_in)
                say("rewarp", "role=player" .. MY_GLOBAL .. " act=" .. stand_in
                    .. " goal=" .. tostring(api.player_sync[0].sh5_goal))
                since = 0
                return
            end
            if mine.currActNum ~= stand_in then
                if since % 900 == 0 then
                    say("waiting", "role=player" .. MY_GLOBAL .. " reason=rewarp act=" .. tostring(mine.currActNum))
                end
                since = 0
                return
            end
        end
        -- Both players stand on the meeting point before anything is asked
        -- about the pair, so the two acts are compared where a rule isolating
        -- this course by act would have fired. They overlap exactly for the
        -- moment: resolve_player_collision moves along the vector between the
        -- two torsos, so a perfect overlap pushes nobody.
        if shared ~= nil and shared.meet ~= nil and not moved then
            moved = true
            local x, y, z = shared.meet()
            place_at(gMarioStates[0], x, y, z)
            say("meet", "role=player" .. MY_GLOBAL
                .. " x=" .. string.format("%.0f", x)
                .. " y=" .. string.format("%.0f", y)
                .. " z=" .. string.format("%.0f", z))
            since = 0
            return
        end
        if since < AREA_SETTLE_FRAMES then return end
        -- What the submarine and the poles actually read. Both clients must
        -- report the same number, or the premise that the course looks the same
        -- from every act is wrong and the "ddd" verdict below means nothing.
        if CASE[phase] == "ddd" then
            say("saveflags", "role=player" .. MY_GLOBAL
                .. " ddd_gate=" .. tostring(save_file_get_flags() & DDD_SAVE_GATE))
        end
        -- The premise, not the verdict: whether the two players are actually
        -- in different acts. `split` needs them to be and every other case
        -- needs them not to be, and a case that drifts either way measures
        -- something other than what it is named for.
        local cross_act = mine.currActNum ~= theirs.currActNum
        local want = WANT_CROSS_ACT[CASE[phase]]
        say("pair", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
            .. " cross_act=" .. tostring(cross_act)
            .. " my_act=" .. tostring(mine.currActNum) .. " their_act=" .. tostring(theirs.currActNum)
            .. " interactions=" .. server_interactions())
        if cross_act ~= want then
            say("fail", "reason=wrong_pair_state role=player" .. MY_GLOBAL .. " case=" .. CASE[phase])
            enter("done")
            return
        end
        enter("place")

    elseif state == "place" then
        -- **The meeting point travels through the sync table, not through the
        -- other player's body.** Two players on different acts never exchange
        -- positions at all -- network_receive_player drops a packet whose
        -- course, act, level or area does not match and marks the sender's
        -- position invalid -- so the walking player cannot aim at where it sees
        -- the standing one. Both sides agree on plain coordinates instead.
        local me = gMarioStates[0]
        if IS_ANCHOR then
            local cross = CROSS_COURSE[CASE[phase]]
            if cross ~= nil and not landed then
                -- **The player is held above the ship while the deck is
                -- searched for, not left to fall.** An object's surfaces reach
                -- the collision grid only from `load_object_collision_model` in
                -- its own behaviour loop, and only while it is within
                -- `oCollisionDistance` -- 4000 for this one
                -- (data/behavior_data.c:2718-2728). A player dropped once and
                -- left alone is out of that range within a second, and then no
                -- amount of waiting will find the deck.
                if deck_at == nil then
                    place_at(me, cross.stand())
                    local dx, dy, dz = deck_near(cross)
                    if dx == nil then
                        if since > 240 then
                            say("fail", "reason=no_deck_found case=" .. CASE[phase]
                                .. " act=" .. tostring(gNetworkPlayers[0].currActNum))
                            enter("done")
                        elseif since % 120 == 0 then
                            say("waiting", "role=player" .. MY_GLOBAL .. " reason=deck_search")
                        end
                        return
                    end
                    deck_at = { x = dx, y = dy, z = dz }
                    place_at(me, dx, dy + 10.0, dz)
                    say("deck", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                        .. " x=" .. fmt(dx) .. " y=" .. fmt(dy) .. " z=" .. fmt(dz)
                        .. " act=" .. tostring(gNetworkPlayers[0].currActNum))
                    return
                end
                local surface = me.floor
                local floor_object = surface ~= nil and surface.object or nil
                local on_deck = floor_object ~= nil
                    and obj_has_behavior_id(floor_object, cross.floor_beh) ~= 0
                    and math.abs(me.pos.y - me.floorHeight) < 40
                if not on_deck then
                    -- Held on the deck it was just put on, for the same reason:
                    -- a player sliding off the rocking ship takes the ship's
                    -- surfaces out of range with it.
                    place_at(me, deck_at.x, deck_at.y + 10.0, deck_at.z)
                    if since > 420 then
                        say("fail", "reason=no_deck_landing case=" .. CASE[phase]
                            .. " y=" .. fmt(me.pos.y) .. " floor=" .. fmt(me.floorHeight)
                            .. " deck=" .. fmt(deck_at.y))
                        enter("done")
                    elseif since % 120 == 0 then
                        say("waiting", "role=player" .. MY_GLOBAL .. " reason=landing"
                            .. " y=" .. fmt(me.pos.y) .. " floor=" .. fmt(me.floorHeight))
                    end
                    return
                end
                landed = true
                place_at(me, me.pos.x, me.pos.y, me.pos.z)
                local mine = gPlayerSyncTable[0]
                mine.sh_probe_x, mine.sh_probe_y, mine.sh_probe_z = me.pos.x, me.pos.y, me.pos.z
                mine.sh_probe_ready = phase
                -- The behaviour is the one the check above required, so it is
                -- printed from the case rather than read back off the object:
                -- `Object.behavior` is a pointer the type checker will not
                -- follow, and the line is only reached when the floor matched.
                say("standing", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                    .. " y=" .. fmt(me.pos.y)
                    .. " beh=" .. tostring(cross.floor_beh)
                    .. " act=" .. tostring(gNetworkPlayers[0].currActNum))
                return
            end
            if since == 1 then
                -- A case with a meeting point of its own meets there rather
                -- than on a patch of floor. Dire Dire Docks is the one that
                -- needs it: the level is flooded from end to end and has no
                -- platform to stand on.
                local x, y, z
                local shared = SHARED_COURSE[CASE[phase]]
                if shared ~= nil and shared.meet ~= nil then
                    x, y, z = shared.meet()
                else
                    x, y, z = open_ground_near(me)
                end
                if x == nil then
                    say("fail", "reason=no_open_ground case=" .. CASE[phase])
                    enter("done")
                    return
                end
                place_at(me, x, y, z)
                local mine = gPlayerSyncTable[0]
                mine.sh_probe_x, mine.sh_probe_y, mine.sh_probe_z = x, y, z
                mine.sh_probe_ready = phase
                say("ground", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                    .. " x=" .. string.format("%.0f", x)
                    .. " y=" .. string.format("%.0f", y)
                    .. " z=" .. string.format("%.0f", z))
                return
            end
            -- Start counting only once the other player has arrived, or the
            -- sixty samples are spent waiting for company.
            if (gPlayerSyncTable[OTHER].sh_probe_placed or 0) ~= phase then
                if since % 900 == 0 then say("waiting", "role=player" .. MY_GLOBAL .. " reason=partner_not_placed") end
                return
            end
            samples = 0
            enter("measure")
        else
            local theirs = gPlayerSyncTable[OTHER]
            if (theirs.sh_probe_ready or 0) ~= phase then
                if since % 900 == 0 then say("waiting", "role=player" .. MY_GLOBAL .. " reason=anchor_not_ready") end
                return
            end
            place_at(me, (theirs.sh_probe_x or 0) + PLACE_OFFSET, theirs.sh_probe_y or 0, theirs.sh_probe_z or 0)
            gPlayerSyncTable[0].sh_probe_placed = phase
            enter("measure")
        end

    elseif state == "measure" then
        local me = gMarioStates[0]
        local them = gMarioStates[OTHER]
        -- Two numbers, and the first is the one that matters. `drift` is how
        -- far this instance's own player has moved from where the probe put it
        -- down: nothing but the engine moves an idle Mario with no input and no
        -- velocity, so a drift is a push. `reach` is the distance to the other
        -- body as this instance sees it, which is only meaningful when the
        -- engine is exchanging their positions at all.
        drift = math.max(drift, horizontal_distance(me.pos, placed_at))
        reach = math.max(reach, horizontal_distance(me.pos, them.pos))
        samples = samples + 1
        publish_truth(me)
        sample_disagreement(them)
        if samples == 30 then gates(them, horizontal_distance(me.pos, them.pos)) end
        if samples >= 60 then
            local pushed = drift >= PUSHED_DRIFT or reach >= SEPARATED
            say("overlap", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                .. " drift=" .. fmt(drift)
                .. " reach=" .. fmt(reach)
                .. " samples=" .. samples)
            say("jitter", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                .. " error_max=" .. fmt(error_max)
                .. " error_mean=" .. fmt(error_n > 0 and error_sum / error_n or 0)
                .. " step_max=" .. fmt(sim_step_max)
                .. " flips=" .. sim_flips
                .. " floor_gap=" .. fmt(floor_gap)
                .. " rtt_frames=" .. rtt_max
                .. " samples=" .. error_n)
            -- A case that stands one player on geometry the other has never
            -- spawned cannot report a push: the body with no floor under it
            -- falls, and falling is not being pushed. It reports the
            -- disagreement instead.
            if CROSS_COURSE[CASE[phase]] ~= nil then
                say("verdict", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                    .. " floor_gap=" .. fmt(floor_gap)
                    .. " error_max=" .. fmt(error_max))
            else
                say("verdict", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                    .. " passed_through=" .. tostring(not pushed))
            end
            gPlayerSyncTable[0].sh_probe_done = phase
            enter("await_case")
        end

    elseif state == "done" then
        if since == 1 then say("end", "role=player" .. tostring(MY_GLOBAL)) end
    end
end

local function update()
    since = since + 1
    if ROLE == nil then ROLE = network_is_server() and "server" or "player" end

    if state == "wait_api" then
        -- StarHunt publishes this on _G only when it saw the flag above.
        api = rawget(_G, "STARHUNT_TEST_API")
        if api == nil then
            if since == 300 then say("fail", "reason=no_test_api role=" .. ROLE) end
            return
        end
        say("load", "role=" .. ROLE .. " goals=" .. #api.goals)
        enter("wait_players")
        return
    end

    if ROLE == "server" then update_server() else update_player() end
end

hook_event(HOOK_UPDATE, update)
