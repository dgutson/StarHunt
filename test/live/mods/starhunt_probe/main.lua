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

-- How far a player has to have moved from where it was put down for that to
-- count as a push. An idle Mario on flat ground with zero velocity does not
-- drift, so anything above a few units is the engine.
local PUSHED_DRIFT = 20.0

-- Three cases per run, and only the middle one is about StarHunt at all.
--
--  1. split  -- the two players hold TTC goals for acts 6 and 1 and are each
--               standing in their own act. This is what an ordinary StarHunt
--               round produces, and it is **not** a test of anything the mod
--               does: the engine refuses the contact by itself, because
--               is_player_active compares the two players' currActNum and a
--               remote player on another act is not active. The case is kept
--               because it records that rather than claiming credit for it.
--
--  2. hidden -- the same two goals, but this player walks back into the act the
--               other one is standing in, so both currActNum agree and the
--               engine is willing. players_have_private_variant still says the
--               pair is private, because it reads the assigned goals rather
--               than the loaded act. R-030's refusal in on_allow_interact is
--               now the only thing between the two bodies. **This is the case
--               that fails when that branch is deleted.**
--
--  3. shared -- both players hold the act 6 goal, so the predicate is false and
--               the mod leaves the contact alone. The engine must push these
--               two apart. Without this control a run where the bodies never
--               touch at all reports every other case as a pass.
local CASE = { "split", "hidden", "shared" }

-- Which cases players_have_private_variant has to answer true for.
local WANT_PRIVATE = { split = true, hidden = true, shared = false }

-- The act both players stand in for "hidden" and "shared". Act 6 is the one
-- that stops the clock, so it is the side of the TTC divergence the predicate
-- keys on; the other player's goal keeps whatever act pick_ttc_goals found.
local SHARED_ACT = 6

local state = "wait_api"
local since = 0
local phase = 0
-- STARHUNT_TEST_API is a table the mod builds at run time, so nothing the type
-- checker can read describes its shape. Saying so here keeps the annotation to
-- one line instead of a nil check at every use.
---@type any
local api = nil
local ttc = { act_6 = nil, act_other = nil }
local placed_at = nil
local drift = 0
local reach = 0
local samples = 0
local rewarped = false

--- The two TTC goals the cases need: act 6, and any other act.
-- Act 6 stops the clock while the others run it, which is the divergence
-- players_have_private_variant isolates anywhere in the course. Goals that
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

local function place_at(m, x, y, z)
    m.pos.x, m.pos.y, m.pos.z = x, y, z
    m.vel.x, m.vel.y, m.vel.z = 0, 0, 0
    m.forwardVel = 0
    placed_at = { x = x, y = y, z = z }
    drift = 0
    reach = 0
    samples = 0
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
        -- "hidden" reuses the goals "split" handed out, untouched: reassigning
        -- them would change sh5_goal, and a client re-warps to its goal's act
        -- the moment that value changes, which is exactly the warp this case
        -- exists to avoid. The second player moves itself instead.
        local first = ttc.act_6
        local second = (CASE[phase] == "shared") and ttc.act_6 or ttc.act_other
        if CASE[phase] ~= "hidden" and not assign(first, second) then
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
        gPlayerSyncTable[0].sh_probe_ready = 0
        gPlayerSyncTable[0].sh_probe_placed = 0
        enter("settle")

    elseif state == "settle" then
        local mine, theirs = gNetworkPlayers[0], gNetworkPlayers[OTHER]
        -- **The "hidden" case is made here, and it is made by moving rather
        -- than by reassigning.** This player keeps the goal StarHunt gave it --
        -- so players_have_private_variant still calls the pair private -- but
        -- walks back into the act the other one is standing in, so the engine's
        -- own act comparison stops refusing the contact. That leaves R-030's
        -- branch in on_allow_interact as the only thing that can keep the two
        -- bodies apart, which is what makes this case able to fail.
        if CASE[phase] == "hidden" and not IS_ANCHOR then
            if not rewarped then
                rewarped = true
                warp_to_level(LEVEL_TTC, 1, SHARED_ACT)
                say("rewarp", "role=player" .. MY_GLOBAL .. " act=" .. SHARED_ACT
                    .. " goal=" .. tostring(api.player_sync[0].sh5_goal))
                since = 0
                return
            end
            if mine.currActNum ~= SHARED_ACT then
                if since % 900 == 0 then
                    say("waiting", "role=player" .. MY_GLOBAL .. " reason=rewarp act=" .. tostring(mine.currActNum))
                end
                since = 0
                return
            end
        end
        -- Both warps have to have landed. Level and area are exchanged even
        -- between players the engine will not let interact, so this is readable
        -- in every case.
        if mine.currLevelNum ~= LEVEL_TTC or theirs.currLevelNum ~= LEVEL_TTC then
            if since % 900 == 0 then
                say("waiting", "role=player" .. MY_GLOBAL .. " reason=not_in_ttc"
                    .. " lvl=" .. tostring(mine.currLevelNum) .. "," .. tostring(theirs.currLevelNum))
            end
            since = 0
            return
        end
        if since < AREA_SETTLE_FRAMES then return end
        local private = api.players_have_private_variant(0, OTHER)
        local want = WANT_PRIVATE[CASE[phase]]
        say("pair", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
            .. " private=" .. tostring(private)
            .. " my_act=" .. tostring(mine.currActNum) .. " their_act=" .. tostring(theirs.currActNum)
            .. " interactions=" .. server_interactions())
        if private ~= want then
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
            if since == 1 then
                local x, y, z = open_ground_near(me)
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
        if samples == 30 then gates(them, horizontal_distance(me.pos, them.pos)) end
        if samples >= 60 then
            local pushed = drift >= PUSHED_DRIFT or reach >= SEPARATED
            say("overlap", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                .. " drift=" .. string.format("%.1f", drift)
                .. " reach=" .. string.format("%.1f", reach)
                .. " samples=" .. samples)
            say("verdict", "role=player" .. MY_GLOBAL .. " case=" .. CASE[phase]
                .. " passed_through=" .. tostring(not pushed))
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
