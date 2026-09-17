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

-- Asked once the game is running, not at load time: a client loads its mods
-- while joining, so the network type is not settled yet when this file runs.
local ROLE = nil

-- Frames to let an area settle before touching anything. interact_player
-- refuses every contact while gCurrentArea->localAreaTimer < 60, so a shorter
-- wait would read as "they passed through each other" for the wrong reason.
local AREA_SETTLE_FRAMES = 120

-- What counts as "the engine pushed them apart". resolve_player_collision
-- separates two players to 2 * hitboxRadius, and Mario's radius is 37, so a
-- push parks them at about 74 and holds them there.
--
-- The question is whether they stayed closer than that, not whether they stayed
-- exactly on top of each other. Each instance owns its own player and receives
-- the other's position over the network, so a clean pass-through settles at a
-- small steady offset rather than at zero: the first real run measured 46.5 on
-- the host while the client, which had done the placing, measured 0.
local PUSH_DISTANCE = 74.0
local SEPARATED = PUSH_DISTANCE - 4.0

-- Two cases per run, and the second is what makes the first mean anything.
--
--  1. isolated -- two players on TTC acts 6 and 1. players_have_private_variant
--                 is true for that pair, so R-030 says they pass through.
--  2. shared   -- both players on the same act, so the same predicate is false
--                 and the mod leaves the contact alone. These two have to be
--                 pushed apart. Without this case the run proves nothing: a
--                 setup where the bodies never touch at all reports the first
--                 case as a pass even with the fix taken out, which is exactly
--                 what the first version of this probe did.
local CASE = { "isolated", "shared" }

local state = "wait_api"
local since = 0
local phase = 1
local api = nil
local ttc = { act_6 = nil, act_other = nil }
local overlap = { min = nil, max = nil, samples = 0 }
local watched_goal = nil

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

local function both_in_ttc()
    for i = 0, 1 do
        local np = gNetworkPlayers[i]
        if not np.connected or np.currLevelNum ~= LEVEL_TTC then return false end
    end
    return (gNetworkPlayers[0].currAreaIndex or 0) == (gNetworkPlayers[1].currAreaIndex or 0)
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
    local dx = a.pos.x - b.pos.x
    local dz = a.pos.z - b.pos.z
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
end

local function enter(next_state)
    state = next_state
    since = 0
end

--- Give the two players the goals a case needs, and tell the clients.
-- Each client warps itself from its own sh5_goal and only acts on a goal it has
-- not seen, so the sequence counter has to move as well.
local function assign(first, second)
    for i = 0, 1 do
        local sync = api.player_sync[i]
        sync.sh5_goal = (i == 0) and first or second
        sync.sh5_goal_seq = (sync.sh5_goal_seq or 0) + 1
        sync.sh5_modifier = 0
        sync.sh5_modifier_2 = 0
    end
end

local function begin_case()
    overlap = { min = nil, max = nil, samples = 0 }
    gPlayerSyncTable[0].sh_probe_overlap = 0
    gPlayerSyncTable[0].sh_probe_ready = 0
    watched_goal = api.player_sync[0].sh5_goal
    enter("observe")
end

local function update()
    since = since + 1
    if ROLE == nil then ROLE = network_is_server() and "host" or "client" end

    if state == "wait_api" then
        -- StarHunt publishes this on _G only when it saw the flag above.
        api = rawget(_G, "STARHUNT_TEST_API")
        if api == nil then
            if since == 300 then say("fail", "reason=no_test_api role=" .. ROLE) end
            return
        end
        say("load", "role=" .. ROLE .. " goals=" .. #api.goals)
        enter("wait_players")

    elseif state == "wait_players" then
        if connected_count() < 2 then
            if since % 600 == 0 then say("waiting", "role=" .. ROLE .. " players=" .. connected_count()) end
            return
        end
        say("players", "role=" .. ROLE .. " count=" .. connected_count())
        enter(ROLE == "host" and "start_round" or "await_case")

    elseif state == "start_round" then
        -- A moment for the second player to be enrolled: host_start_round takes
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
        if (api.player_sync[0].sh5_goal or 0) == 0 or (api.player_sync[1].sh5_goal or 0) == 0 then
            if since % 600 == 0 then say("waiting", "role=host reason=no_goals_yet") end
            return
        end
        assign(ttc.act_6, ttc.act_other)
        say("case", "name=" .. CASE[phase] .. " goals=" .. ttc.act_6 .. "," .. ttc.act_other)
        begin_case()

    elseif state == "await_case" then
        -- A client learns that a new case has started from its own goal
        -- changing, which is the one piece of state the host is already sending
        -- it. Nothing else has to be arranged between the two probes.
        local goal = api.player_sync[0].sh5_goal or 0
        if goal == 0 or goal == watched_goal then
            if since % 600 == 0 then say("waiting", "role=client reason=no_new_case") end
            return
        end
        begin_case()

    elseif state == "observe" then
        if not both_in_ttc() then
            if since % 600 == 0 then
                say("waiting", "role=" .. ROLE .. " reason=not_in_ttc"
                    .. " lvl=" .. tostring(gNetworkPlayers[0].currLevelNum)
                    .. "," .. tostring(gNetworkPlayers[1].currLevelNum))
            end
            return
        end
        if since < AREA_SETTLE_FRAMES then return end
        local private = api.players_have_private_variant(0, 1)
        local want = (CASE[phase] == "isolated")
        say("pair", "role=" .. ROLE .. " case=" .. CASE[phase]
            .. " private=" .. tostring(private)
            .. " interactions=" .. server_interactions())
        if private ~= want then
            say("fail", "reason=wrong_pair_state role=" .. ROLE .. " case=" .. CASE[phase])
            enter("done")
            return
        end
        enter("overlap")

    elseif state == "overlap" then
        -- Put the two players in one place, once, and then leave the engine
        -- alone. resolve_player_collision moves whichever player it is
        -- processing, so a pair the engine still collides separates within a
        -- frame or two and stays at the push distance.
        --
        -- **Only the client moves.** A player can only be placed by the
        -- instance that owns it — a remote Mario's position is overwritten by
        -- the next packet — and if both sides moved onto each other's position
        -- they would swap places and never touch at all.
        local me, them = gMarioStates[0], gMarioStates[1]
        if ROLE == "host" then
            -- The host stands itself on ground with room first, and only then
            -- invites the client over. Each side writes its own row of the
            -- player sync table, which is the one row a player may write.
            if since == 1 then
                local x, y, z = open_ground_near(me)
                if x == nil then
                    say("fail", "reason=no_open_ground case=" .. CASE[phase])
                    enter("done")
                    return
                end
                place_at(me, x, y, z)
                gPlayerSyncTable[0].sh_probe_ready = 1
                say("ground", "role=host case=" .. CASE[phase]
                    .. " x=" .. string.format("%.0f", x)
                    .. " y=" .. string.format("%.0f", y)
                    .. " z=" .. string.format("%.0f", z))
                return
            end
            if (gPlayerSyncTable[1].sh_probe_overlap or 0) ~= 1 then
                if since % 600 == 0 then say("waiting", "role=host reason=client_not_placed") end
                since = 1
                return
            end
        else
            if (gPlayerSyncTable[1].sh_probe_ready or 0) ~= 1 then
                if since % 600 == 0 then say("waiting", "role=client reason=host_not_ready") end
                since = 1
                return
            end
            if since == 2 then
                place_at(me, them.pos.x, them.pos.y, them.pos.z)
                gPlayerSyncTable[0].sh_probe_overlap = 1
                return
            end
            if since < 2 then return end
        end
        local distance = horizontal_distance(me, them)
        if overlap.samples == 30 then
            -- Which gate is shut, when a pair that should collide does not.
            -- interact_player walks: playerInteractions, ACT_FLAG_INTANGIBLE,
            -- the vanish cap, then resolve_player_collision, which additionally
            -- refuses while either invincTimer is above zero. The interaction
            -- is only reached at all when the engine put INTERACT_PLAYER in the
            -- player's collidedObjInteractTypes.
            local mine = me.marioObj ~= nil and me.marioObj.collidedObjInteractTypes or 0
            say("gates", "role=" .. ROLE .. " case=" .. CASE[phase]
                .. " dist=" .. string.format("%.1f", distance)
                .. " collided=" .. tostring((mine & INTERACT_PLAYER) ~= 0)
                .. " my_act=" .. string.format("%08X", me.action or 0)
                .. " their_act=" .. string.format("%08X", them.action or 0)
                .. " invinc=" .. tostring(me.invincTimer) .. "," .. tostring(them.invincTimer)
                .. " my_flags=" .. string.format("%X", me.flags or 0)
                -- resolve_player_collision refuses outright when the two torsos
                -- are further apart vertically than one hitbox height (160), so
                -- a stale or falling remote body never touches anything.
                .. " dy=" .. string.format("%.1f", math.abs(me.pos.y - them.pos.y))
                .. " my_y=" .. string.format("%.0f", me.pos.y)
                .. " their_y=" .. string.format("%.0f", them.pos.y)
                .. " their_xz=" .. string.format("%.0f,%.0f", them.pos.x, them.pos.z))
        end
        overlap.samples = overlap.samples + 1
        if overlap.min == nil or distance < overlap.min then overlap.min = distance end
        if overlap.max == nil or distance > overlap.max then overlap.max = distance end
        if overlap.samples >= 60 then
            say("overlap", "role=" .. ROLE .. " case=" .. CASE[phase]
                .. " min=" .. string.format("%.1f", overlap.min)
                .. " max=" .. string.format("%.1f", overlap.max)
                .. " samples=" .. overlap.samples)
            say("verdict", "role=" .. ROLE .. " case=" .. CASE[phase]
                .. " passed_through=" .. tostring(overlap.max < SEPARATED))
            if phase >= #CASE then
                enter("done")
            else
                phase = phase + 1
                enter(ROLE == "host" and "next_case" or "await_case")
            end
        end

    elseif state == "next_case" then
        if since < 30 then return end
        -- The shared case: both players on the same act, so the mod has no
        -- reason to isolate them and the engine's collision must stand. Act 6
        -- for both, not act 1: the client is the side that watches its own goal
        -- for the change, and it already holds the act 1 goal.
        assign(ttc.act_6, ttc.act_6)
        say("case", "name=" .. CASE[phase] .. " goals=" .. ttc.act_6 .. "," .. ttc.act_6)
        begin_case()

    elseif state == "done" then
        if since == 1 then say("end", "role=" .. ROLE) end
    end
end

hook_event(HOOK_UPDATE, update)
