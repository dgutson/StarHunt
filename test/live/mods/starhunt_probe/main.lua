-- name: AAA StarHunt Probe
-- description: Drives StarHunt inside a headless sm64coopdx for test/live. Not a mod for players.

-- This mod exists only for test/live/run.sh. It is never installed alongside a
-- real game: it starts rounds by itself, teleports players and prints machine
-- readable lines to stdout, which run.sh reads back.
--
-- **The name has to sort before StarHunt's.** sm64coopdx loads mods in
-- alphabetical order of the uncoloured `-- name:` header (`mods_sort` in
-- src/pc/mods/mods.c), every mod shares one Lua state (`gLuaState`, one
-- `luaL_newstate` in src/pc/lua/smlua.c), and StarHunt reads
-- STARHUNT_TEST_MODE once, at load time, to decide whether to publish
-- STARHUNT_TEST_API. Setting the flag here only works because "AAA ..." loads
-- first.
STARHUNT_TEST_MODE = true

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

local state = "wait_api"
local since = 0
local api = nil
local ttc = { act_a = nil, act_b = nil }
local overlap = { min = nil, max = nil, samples = 0 }

-- Two Mario hitboxes are 37 units of radius each and
-- resolve_player_collision pushes to twice that, so a push lands at about
-- 74. Nothing pushes them at all when the fix holds, so they stay near 0;
-- the line between the two outcomes is drawn in the middle rather than at
-- 74, to leave room for a player drifting on a moving floor.
local SEPARATED = 40.0

--- The two TTC goals the case needs: act 6 against any other act.
-- players_have_private_variant isolates those two anywhere in the course,
-- because act 6 stops the clock and the others run it. Goals that require a
-- cap are skipped: a vanish cap makes interact_player return before it can
-- reach resolve_player_collision, which would pass the test without the fix.
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

local function enter(next_state)
    state = next_state
    since = 0
end

local function update()
    since = since + 1
    if ROLE == nil then ROLE = network_is_server() and "host" or "client" end

    if state == "wait_api" then
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
        enter(ROLE == "host" and "start_round" or "observe")

    elseif state == "start_round" then
        -- One frame of settling after the second player appears: host_start_round
        -- enrols whoever is connected when it runs.
        if since < 60 then return end
        ttc.act_a, ttc.act_b = pick_ttc_goals()
        if ttc.act_a == nil or ttc.act_b == nil then
            say("fail", "reason=no_ttc_goal_pair")
            enter("done")
            return
        end
        gGlobalSyncTable.sh5_mode = 0        -- SH.Mode.NORMAL
        gGlobalSyncTable.sh5_difficulty = 1  -- SH.Difficulty.MEDIUM
        if not api.host_start(10) then
            say("fail", "reason=host_start_refused")
            enter("done")
            return
        end
        -- Replace the goals the host picked at random with the pair the case is
        -- about. Each client warps itself from its own sh5_goal, and only acts
        -- on a goal it has not seen, so the sequence counter has to move too.
        for i = 0, 1 do
            local sync = gPlayerSyncTable[i]
            sync.sh5_goal = (i == 0) and ttc.act_a or ttc.act_b
            sync.sh5_goal_seq = (sync.sh5_goal_seq or 0) + 1
            sync.sh5_modifier = 0
            sync.sh5_modifier_2 = 0
        end
        say("round", "goals=" .. ttc.act_a .. "," .. ttc.act_b
            .. " acts=" .. api.goals[ttc.act_a].act .. "," .. api.goals[ttc.act_b].act)
        enter("observe")

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
        say("pair", "role=" .. ROLE
            .. " private=" .. tostring(private)
            .. " interactions=" .. server_interactions())
        if not private then
            say("fail", "reason=pair_not_private role=" .. ROLE)
            enter("done")
            return
        end
        enter("overlap")

    elseif state == "overlap" then
        -- Put the two players in one place, once, and then leave the engine
        -- alone. resolve_player_collision moves whichever player it is
        -- processing, so without the fix the two separate within a frame or
        -- two; with it they stay on top of each other.
        --
        -- **Only the client moves.** A player can only be placed by the
        -- instance that owns it — a remote Mario's position is overwritten by
        -- the next packet — and if both sides moved onto each other's position
        -- they would swap places and never touch at all.
        local me, them = gMarioStates[0], gMarioStates[1]
        if ROLE == "client" then
            if since == 1 then
                me.pos.x = them.pos.x
                me.pos.z = them.pos.z
                me.pos.y = them.pos.y
                me.vel.x, me.vel.y, me.vel.z = 0, 0, 0
                me.forwardVel = 0
                -- A player may write their own row of the player sync table, so
                -- this is how the client tells the host that the two bodies are
                -- now in one place. Without it the host could spend its whole
                -- sample window measuring a gap that simply had not closed yet.
                gPlayerSyncTable[0].sh_probe_overlap = 1
                return
            end
        elseif (gPlayerSyncTable[1].sh_probe_overlap or 0) ~= 1 then
            if since % 600 == 0 then say("waiting", "role=host reason=client_not_placed") end
            since = 1
            return
        end
        local distance = horizontal_distance(me, them)
        overlap.samples = overlap.samples + 1
        if overlap.min == nil or distance < overlap.min then overlap.min = distance end
        if overlap.max == nil or distance > overlap.max then overlap.max = distance end
        if overlap.samples >= 60 then
            say("overlap", "role=" .. ROLE
                .. " min=" .. string.format("%.1f", overlap.min)
                .. " max=" .. string.format("%.1f", overlap.max)
                .. " samples=" .. overlap.samples)
            say("verdict", "role=" .. ROLE .. " passed_through="
                .. tostring(overlap.max < SEPARATED))
            enter("done")
        end

    elseif state == "done" then
        if since == 1 then say("end", "role=" .. ROLE) end
    end
end

hook_event(HOOK_UPDATE, update)
