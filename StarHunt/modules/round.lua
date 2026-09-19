-- StarHunt v1.1.2 - the round, both sides of it.
--
-- The file has two halves, and the split is the mod's authority rule made
-- visible.  The `host_*` half below runs only on the server: it picks the
-- goals, hands them out, counts the stars, decides when the round is over and
-- writes all of that into gGlobalSyncTable and gPlayerSyncTable.  The
-- `local_*` and `on_*` half that follows it runs on every player's own machine
-- and only reads what the host published.  Nothing in the second half decides
-- anything.
--
-- The two halves meet through the synchronized tables and, with one exception,
-- nowhere else.  That is what lets a client join late, or a host migrate,
-- without either side holding a stale local answer.
--
-- The exception is `on_before_boss_cutscene`, which calls `host_end_round`
-- behind a `network_is_server()` check.  It is the fallback for a Bowser whose
-- defeat some other mod handles its own way: the player who beat him cancels
-- the victory cinematic locally and, if that player happens to be the host,
-- ends the round in the same breath.  It is the only call from the second half
-- into the first, and anything that splits this file has to carry it.
--
-- Host state that must survive a whole round lives in four tables near the top
-- of the host half.  `host_start_round` REPLACES three of them outright, so
-- they cannot be shared with another module by re-localizing -- Lua copies the
-- value on `local x = other.x`.  The fourth, the per-player records, is needed
-- by Team mode's scoring as well, so it lives on the shared `SH` table in
-- core.lua rather than here.
--
-- Two things that look like they belong elsewhere and do not:
--
--   * `host_update_boss_round` is Boss's round loop and
--     `SH.host_update_chaos_round` is Chaos's, yet neither can live in the
--     module of the mode it belongs to.  This file requires boss.lua for the
--     time range, the modifier slots and the health report, and chaos.lua for
--     the map list and the modifier pair picker, so an edge back the other way
--     would be a require cycle.  Chaos's loop also calls host_end_round,
--     host_add_late_joiner and
--     remember_player_index, which are this file's own host machinery rather
--     than shared helpers, so moving them to core.lua was not a way out.
--   * `configured_time_range` reads the mode and dispatches to Boss's own
--     table.  It is the round's question -- how long is this round -- so it is
--     answered here.
--
-- Every function in the second half is registered as a hook in main.lua.  The
-- hook block stays there because order within a hook type matters.

local core = require("core")
local SH = core.SH
local Team = core.Team
local local_runtime = core.local_runtime
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local NEXT_GOAL_DELAY = core.NEXT_GOAL_DELAY
local clamp = core.clamp
local is_round_active = core.is_round_active
local selected_mode = core.selected_mode
local is_boss_mode = core.is_boss_mode
local player_record_key = core.player_record_key
local translated = require("i18n").translated
local save = require("save")
local flush_starhunt_save_removals = save.flush_starhunt_save_removals
local goal_already_collected = save.goal_already_collected
local goals = require("goals")
local GOALS = goals.GOALS
local get_goal = goals.get_goal
local get_local_goal = goals.get_local_goal
local players_have_private_variant = goals.players_have_private_variant
local NORMAL_MODIFIER_CATALOG = require("audit").NORMAL_MODIFIER_CATALOG
local boss = require("boss")
local BOSS_LEVELS = boss.BOSS_LEVELS
local BOWSER_ACT = boss.BOWSER_ACT
local BOSS_PLAYER_MODIFIERS = boss.BOSS_PLAYER_MODIFIERS
local BOSS_MODIFIERS = boss.BOSS_MODIFIERS
local BOSS_MODIFIER_FIELDS = boss.BOSS_MODIFIER_FIELDS
local BOSS_ATTACK_QUEUE_SIZE = boss.BOSS_ATTACK_QUEUE_SIZE
local BOSS_ACTIVE_ATTACK_MODIFIERS = boss.BOSS_ACTIVE_ATTACK_MODIFIERS
local BOSS_ACTIVE_ATTACK_LOOKUP = boss.BOSS_ACTIVE_ATTACK_LOOKUP
local boss_time_range_for_players = boss.boss_time_range_for_players
local boss_has_modifier = boss.boss_has_modifier
local boss_is_desperate = boss.boss_is_desperate
local boss_is_held = boss.boss_is_held
local host_read_boss_health_report = boss.host_read_boss_health_report
require("chaos")
local local_modifiers = require("modifiers")
local grant_infinite_lives = local_modifiers.grant_infinite_lives
local reset_local_modifier_state = local_modifiers.reset_local_modifier_state

-- Announce the winner first, then reset scores on the following frame.
-- This makes the handoff immediate without clearing the result beforehand.
local RESULT_DISPLAY_FRAMES = 1

-- The goal pool has 93 stars. Large lobbies still get shorter rounds, but
-- now have enough distinct goals for every player to receive several.
local function time_range_for_players(count)
    if count <= 1 then return 13, 22 end
    if count == 2 then return 11, 20 end
    if count == 3 then return 10, 18 end
    if count == 4 then return 9, 16 end
    if count <= 6 then return 8, 14 end
    if count <= 8 then return 7, 11 end
    if count <= 10 then return 6, 9 end
    if count <= 12 then return 5, 7 end
    if count <= 14 then return 5, 6 end
    return 4, 5
end

local function configured_time_range(count)
    if gGlobalSyncTable.sh5_mode == SH.Mode.BOSS then return boss_time_range_for_players(count) end
    return time_range_for_players(count)
end

local host_used_goals = {}
local host_seen_done = {}
local host_seen_forfeit = {}

local host_previous_player_interactions = nil
local host_previous_pvp_type = nil

local function connected_player_count()
    local count = 0
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then count = count + 1 end
    end
    return count
end

local function goal_is_active_for_anyone(goal_id)
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_goal or 0) == goal_id then
            return true
        end
    end
    return false
end

local function host_pick_goal(avoid_level)
    local choices = {}
    for id, goal in ipairs(GOALS) do
        if (avoid_level == nil or goal.level ~= avoid_level)
            and not host_used_goals[id] and not goal_is_active_for_anyone(id)
            and not goal_already_collected(goal) then
            table.insert(choices, id)
        end
    end
    if #choices == 0 then return 0 end
    return choices[math.random(#choices)]
end

local function host_assign_goal(player_index, avoid_modifier_kind, avoid_level)
    local goal_id = host_pick_goal(avoid_level)
    if goal_id == 0 then return false end

    local goal = get_goal(goal_id)
    local alternatives = {}
    for index, modifier_data in ipairs(goal.mods) do
        if SH.difficulty_modifier_allowed(goal, modifier_data)
            and (avoid_modifier_kind == nil or modifier_data.kind ~= avoid_modifier_kind) then
            table.insert(alternatives, index)
        end
    end
    if #alternatives == 0 then
        for index, modifier_data in ipairs(goal.mods) do
            if SH.difficulty_modifier_allowed(goal, modifier_data) then table.insert(alternatives, index) end
        end
    end
    if #alternatives == 0 then return false end
    local modifier_index = alternatives[math.random(#alternatives)]
    local modifier_data = goal.mods[modifier_index]
    host_used_goals[goal_id] = true

    local sync = gPlayerSyncTable[player_index]
    sync.sh5_goal = goal_id
    sync.sh5_modifier = modifier_index
    sync.sh5_modifier_2 = SH.selected_difficulty() == SH.Difficulty.NIGHTMARE
        and SH.pick_second_modifier(goal, modifier_index) or 0
    local second = goal.mods[sync.sh5_modifier_2 or 0]
    local jump_modifier = modifier_data.kind == "jump_limit" and modifier_data
        or (second ~= nil and second.kind == "jump_limit" and second or nil)
    jump_modifier = SH.effective_modifier_for_goal(goal, jump_modifier)
    sync.sh5_jump_count = jump_modifier ~= nil and jump_modifier.value or -1
    sync.sh5_goal_seq = (sync.sh5_goal_seq or 0) + 1
    return true
end

local function update_winner_candidate(name, score, best_score, winners)
    if score > best_score then
        return score, { name }
    end
    if score == best_score then table.insert(winners, name) end
    return best_score, winners
end

local function winner_text_and_score()
    local best_score = -1
    local winners = {}
    local connected_keys = {}
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_enrolled or 0) == 1 then
            local score = gPlayerSyncTable[i].sh5_score or 0
            local key = player_record_key(i)
            if key ~= nil then connected_keys[key] = true end
            best_score, winners = update_winner_candidate(
                gNetworkPlayers[i].name, score, best_score, winners)
        end
    end
    -- A brief disconnect at the final second must not erase a participant
    -- from the results. The host keeps the latest authoritative snapshot.
    for key, record in pairs(SH.host_player_records) do
        if not connected_keys[key] and record.enrolled == 1 then
            best_score, winners = update_winner_candidate(
                record.name, record.score, best_score, winners)
        end
    end
    if #winners == 0 then return "Nobody", 0 end
    if #winners == 1 then return winners[1], best_score end
    return table.concat(winners, " and "), best_score
end

local function host_end_round(reason)
    if not is_round_active() then return end

    local result_mode = selected_mode()
    local boss_round = result_mode == SH.Mode.BOSS
    local winner, score = winner_text_and_score()
    if boss_round then
        winner = reason == "boss defeated" and "TEAM STARHUNT" or "BOWSER"
        score = reason == "boss defeated" and 1 or 0
    elseif result_mode == SH.Mode.CHAOS then
        winner = reason == "chaos last standing"
            and (gGlobalSyncTable.sh5_chaos_winner or "Nobody") or "Nobody"
        score = reason == "chaos last standing" and 1 or 0
    elseif result_mode == SH.Mode.TEAM then
        Team.update_scores()
        local red_score = gGlobalSyncTable.sh5_red_score or 0
        local blue_score = gGlobalSyncTable.sh5_blue_score or 0
        if red_score > blue_score then
            winner, score = "RED TEAM", red_score
        elseif blue_score > red_score then
            winner, score = "BLUE TEAM", blue_score
        else
            winner, score = "TIE", red_score
        end
        gGlobalSyncTable.sh5_result_red_score = red_score
        gGlobalSyncTable.sh5_result_blue_score = blue_score
    end
    gGlobalSyncTable.sh5_active = 0
    -- The host may close the game immediately after stopping the round.
    -- Flush its own pending star removals before sending the lobby warp.
    flush_starhunt_save_removals(true, false)
    gGlobalSyncTable.sh5_result_mode = result_mode
    gGlobalSyncTable.sh5_result_winner = winner
    gGlobalSyncTable.sh5_result_score = score
    gGlobalSyncTable.sh5_result_reason = reason
    gGlobalSyncTable.sh5_chaos_roster_locked = 0
    gGlobalSyncTable.sh5_chaos_alive = 0
    gGlobalSyncTable.sh5_result_seq = (gGlobalSyncTable.sh5_result_seq or 0) + 1
    -- Unlike the winner popup, returning to the lobby must not be a one-frame
    -- local action. Give every connected player a durable, personal return
    -- order so delayed clients keep retrying until the warp succeeds.
    gGlobalSyncTable.sh5_return_seq = (gGlobalSyncTable.sh5_return_seq or 0) + 1
    -- The result sequence is sent first.  Scores remain intact long enough
    -- for every client to display the winner, then reset for the next round.
    -- This same route is used when the clock ends and when the host stops.
    gGlobalSyncTable.sh5_reset_scores_at = get_global_timer() + RESULT_DISPLAY_FRAMES

    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            local sync = gPlayerSyncTable[i]
            sync.sh5_goal = 0
            sync.sh5_modifier = 0
            sync.sh5_modifier_2 = 0
            sync.sh5_jump_count = -1
            sync.sh5_manual_reroll_request = 0
            sync.sh5_manual_reroll_ack = 0
            sync.sh5_enrolled = 0
            sync.sh5_team = Team.Color.NONE
            sync.sh5_chaos_eliminated = 0
            sync.sh5_return_seq = gGlobalSyncTable.sh5_return_seq
        end
    end


    if host_previous_player_interactions ~= nil then
        gServerSettings.playerInteractions = host_previous_player_interactions
        host_previous_player_interactions = nil
    end
    if host_previous_pvp_type ~= nil then
        gServerSettings.pvpType = host_previous_pvp_type
        host_previous_pvp_type = nil
    end
end

local function host_reset_scores_after_result()
    if not network_is_server() then return end
    local reset_at = gGlobalSyncTable.sh5_reset_scores_at or 0
    if reset_at == 0 or get_global_timer() < reset_at then return end
    if is_round_active() then
        gGlobalSyncTable.sh5_reset_scores_at = 0
        return
    end
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            gPlayerSyncTable[i].sh5_score = 0
            gPlayerSyncTable[i].sh5_done = 0
            gPlayerSyncTable[i].sh5_forfeit = 0
        end
    end
    gGlobalSyncTable.sh5_reset_scores_at = 0
end

local function host_prepare_player(player_index)
    local sync = gPlayerSyncTable[player_index]
    local name = gNetworkPlayers[player_index].name or ""
    local key = player_record_key(player_index)
    local record = key ~= nil and SH.host_player_records[key] or nil
    -- Co-op DX reuses global player indices after a disconnect. A direct key
    -- match is a reconnect only when the identity also matches; otherwise a
    -- new player could inherit somebody else's score and challenge.
    if record ~= nil and record.name ~= name then record = nil end
    if record == nil and name ~= "" then
        -- globalIndex normally survives the session. If it changed during a
        -- reconnect, use the name only when exactly one disconnected record
        -- matches, preventing same-name players from stealing each other.
        local connected_record_keys = {}
        for i = 0, MAX_PLAYERS - 1 do
            if i ~= player_index and gNetworkPlayers[i].connected then
                local connected_key = player_record_key(i)
                if connected_key ~= nil then connected_record_keys[connected_key] = true end
            end
        end
        local candidate = nil
        for record_key, saved in pairs(SH.host_player_records) do
            if saved.name == name and not connected_record_keys[record_key] then
                if candidate ~= nil then
                    candidate = false
                    break
                end
                candidate = saved
            end
        end
        if candidate ~= false then record = candidate end
    end
    if record ~= nil then
        local restored_team = SH.is_team_mode() and Team.pick_late(record.team) or Team.Color.NONE
        sync.sh5_score = record.score
        sync.sh5_goal = record.goal
        sync.sh5_modifier = record.modifier
        sync.sh5_modifier_2 = record.modifier_2 or 0
        sync.sh5_done = record.done
        sync.sh5_forfeit = record.forfeit
        sync.sh5_manual_reroll_request = record.manual_reroll_request or 0
        sync.sh5_manual_reroll_ack = record.manual_reroll_ack
            or sync.sh5_manual_reroll_request
        -- A player who dropped resumes the wait they left with, so the mark
        -- is placed as far back as that remainder needs it.
        SH.set_clock_remaining("reroll" .. player_index,
            record.manual_reroll_remaining or 0)
        sync.sh5_jump_count = record.jump_count
        sync.sh5_boss_victory = record.boss_victory
        sync.sh5_chaos_eliminated = record.chaos_eliminated or 0
        sync.sh5_team = restored_team
        sync.sh5_enrolled = 1
        sync.sh5_lifetime_stars = math.max(sync.sh5_lifetime_stars or 0, record.lifetime_stars or 0)
        host_seen_done[player_index] = record.done
        host_seen_forfeit[player_index] = record.forfeit
        SH.host_player_records[record.key] = nil
        if is_boss_mode() or SH.is_chaos_mode() or record.goal ~= 0 then return true end
        return host_assign_goal(player_index)
    end

    sync.sh5_score = 0
    sync.sh5_goal = 0
    sync.sh5_modifier = 0
    sync.sh5_modifier_2 = 0
    sync.sh5_done = 0
    sync.sh5_forfeit = 0
    sync.sh5_manual_reroll_request = 0
    sync.sh5_manual_reroll_ack = 0
    -- The two minutes belong to the button, not to the level: they start when
    -- the player enters the round and only the button itself starts them again.
    -- A goal handed out because they died, or because they finished a star,
    -- leaves the countdown alone.  Writing the counter is what starts the wait,
    -- here and on that player's own machine: a sync write fires the change hook
    -- whether or not the value differs from the one already there.
    sync.sh5_manual_reroll_seq = 0
    sync.sh5_jump_count = -1
    sync.sh5_enrolled = 1
    sync.sh5_boss_victory = 0
    sync.sh5_chaos_eliminated = SH.is_chaos_mode()
        and ((gGlobalSyncTable.sh5_chaos_roster_locked or 0) == 1 and 1 or 0) or 0
    sync.sh5_boss_health_ready_round = 0
    sync.sh5_boss_health_value = SH.boss_max_health()
    sync.sh5_boss_health_tick = 0
    local initial_team = Team.initial[player_index]
    Team.initial[player_index] = nil
    sync.sh5_team = SH.is_team_mode()
        and (initial_team or Team.pick_late()) or Team.Color.NONE
    host_seen_done[player_index] = 0
    host_seen_forfeit[player_index] = 0
    if SH.is_chaos_mode() then
        local first_index, second_index = SH.pick_chaos_pair(0)
        if first_index == 0 then return false end
        sync.sh5_modifier = first_index
        sync.sh5_modifier_2 = second_index
        local first = SH.effective_modifier(NORMAL_MODIFIER_CATALOG[first_index])
        local second = SH.effective_modifier(NORMAL_MODIFIER_CATALOG[second_index])
        sync.sh5_jump_count = first ~= nil and first.kind == "jump_limit" and first.value
            or (second ~= nil and second.kind == "jump_limit" and second.value or -1)
        return true
    end
    if is_boss_mode() then return true end
    return host_assign_goal(player_index)
end

local function host_start_round(minutes)
    local players = connected_player_count()
    if players == 0 then
        djui_chat_message_create("No connected players were found.")
        return false
    end
    if (SH.is_team_mode() or SH.is_chaos_mode()) and players < 2 then
        djui_chat_message_create(SH.is_chaos_mode()
            and "Chaos Mode needs at least two connected players."
            or "Team Mode needs at least two connected players.")
        return false
    end

    local minimum, maximum = configured_time_range(players)
    minutes = clamp(math.floor(minutes), minimum, maximum)

    if not is_boss_mode() and not SH.is_chaos_mode() then
        local available = 0
        for _, goal_data in ipairs(GOALS) do
            if not goal_already_collected(goal_data) then available = available + 1 end
        end
        if available < players then
            djui_chat_message_create("Not enough unused goals. Use a fresh save file.")
            return false
        end
    end

    host_used_goals = {}
    host_seen_done = {}
    host_seen_forfeit = {}
    SH.host_player_records = {}
    math.randomseed(get_global_timer())
    if SH.is_team_mode() then Team.build_balanced() else Team.initial = {} end
    gGlobalSyncTable.sh5_chaos_roster_locked = 0
    if SH.is_chaos_mode() then
        gGlobalSyncTable.sh5_chaos_level =
            SH.chaos_maps[math.random(#SH.chaos_maps)]
        gGlobalSyncTable.sh5_chaos_act = math.random(6)
        gGlobalSyncTable.sh5_chaos_modifier_1 = 0
        gGlobalSyncTable.sh5_chaos_modifier_2 = 0
        gGlobalSyncTable.sh5_chaos_modifier_seq = 0
        gGlobalSyncTable.sh5_chaos_winner = ""
        gGlobalSyncTable.sh5_chaos_alive = players
    end

    if host_previous_player_interactions == nil then
        host_previous_player_interactions = gServerSettings.playerInteractions
        host_previous_pvp_type = gServerSettings.pvpType
    end
    if is_boss_mode() then
        gServerSettings.playerInteractions = PLAYER_INTERACTIONS_SOLID
        gGlobalSyncTable.sh5_boss_level_index = math.random(#BOSS_LEVELS)
        gGlobalSyncTable.sh5_boss_player_modifier = math.random(#BOSS_PLAYER_MODIFIERS)
        if SH.selected_difficulty() == SH.Difficulty.NIGHTMARE then
            local second_choices = {}
            local first_modifier = BOSS_PLAYER_MODIFIERS[
                gGlobalSyncTable.sh5_boss_player_modifier]
            for index = 1, #BOSS_PLAYER_MODIFIERS do
                if index ~= gGlobalSyncTable.sh5_boss_player_modifier then
                    local candidate = BOSS_PLAYER_MODIFIERS[index]
                    if SH.chaos_pair_allowed(first_modifier, candidate) then
                        table.insert(second_choices, index)
                    end
                end
            end
            gGlobalSyncTable.sh5_boss_player_modifier_2 =
                second_choices[math.random(#second_choices)]
        else
            gGlobalSyncTable.sh5_boss_player_modifier_2 = 0
        end
        -- Three different advantages are drawn for Bowser every battle.
        -- Drawing without replacement prevents duplicate labels/effects.
        local boss_choices = {}
        for index = 1, #BOSS_MODIFIERS do table.insert(boss_choices, index) end
        for slot = 1, #BOSS_MODIFIER_FIELDS do
            local choice = math.random(#boss_choices)
            gGlobalSyncTable[BOSS_MODIFIER_FIELDS[slot]] = boss_choices[choice]
            table.remove(boss_choices, choice)
        end
        local has_active_attack = false
        for _, field in ipairs(BOSS_MODIFIER_FIELDS) do
            if BOSS_ACTIVE_ATTACK_LOOKUP[gGlobalSyncTable[field]] then
                has_active_attack = true
                break
            end
        end
        if not has_active_attack then
            -- All three selected entries are passive, so none of the active
            -- choices can be a duplicate of them.
            gGlobalSyncTable[BOSS_MODIFIER_FIELDS[#BOSS_MODIFIER_FIELDS]] =
                BOSS_ACTIVE_ATTACK_MODIFIERS[math.random(#BOSS_ACTIVE_ATTACK_MODIFIERS)]
        end
        gGlobalSyncTable.sh5_boss_attack_seq = 0
        gGlobalSyncTable.sh5_boss_attack_kind = 0
        for slot = 1, BOSS_ATTACK_QUEUE_SIZE do
            gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)] = 0
        end
        gGlobalSyncTable.sh5_boss_max_health = SH.boss_health_for_difficulty()
        gGlobalSyncTable.sh5_boss_health = gGlobalSyncTable.sh5_boss_max_health
        gGlobalSyncTable.sh5_boss_original_bombs_seen = 0
        gGlobalSyncTable.sh5_boss_extra_bombs_spawned = 0
        gGlobalSyncTable.sh5_boss_attack_frame = get_global_timer() + 5 * FRAMES_PER_SECOND
    else
        gServerSettings.playerInteractions = PLAYER_INTERACTIONS_PVP
        gServerSettings.pvpType = PLAYER_PVP_REVAMPED
        gGlobalSyncTable.sh5_boss_level_index = 0
        gGlobalSyncTable.sh5_boss_player_modifier = 0
        gGlobalSyncTable.sh5_boss_player_modifier_2 = 0
        for _, field in ipairs(BOSS_MODIFIER_FIELDS) do gGlobalSyncTable[field] = 0 end
        gGlobalSyncTable.sh5_boss_attack_kind = 0
        gGlobalSyncTable.sh5_boss_health = 0
        gGlobalSyncTable.sh5_boss_original_bombs_seen = 0
        gGlobalSyncTable.sh5_boss_extra_bombs_spawned = 0
    end

    gGlobalSyncTable.sh5_config_minutes = minutes
    gGlobalSyncTable.sh5_start_frame = get_global_timer()
    gGlobalSyncTable.sh5_result_winner = ""
    gGlobalSyncTable.sh5_result_score = 0
    gGlobalSyncTable.sh5_result_reason = ""
    gGlobalSyncTable.sh5_red_score = 0
    gGlobalSyncTable.sh5_blue_score = 0
    gGlobalSyncTable.sh5_result_red_score = 0
    gGlobalSyncTable.sh5_result_blue_score = 0
    gGlobalSyncTable.sh5_round = (gGlobalSyncTable.sh5_round or 0) + 1
    gGlobalSyncTable.sh5_active = 1
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and not host_prepare_player(i) then
            host_end_round("not enough unused goals")
            djui_chat_message_create("Not enough unused goals. Use a fresh save file.")
            return false
        end
    end
    if SH.is_chaos_mode() then gGlobalSyncTable.sh5_chaos_roster_locked = 1 end

    local mode_name = is_boss_mode() and "BOSS"
        or (SH.is_team_mode() and "TEAM" or (SH.is_chaos_mode() and "CHAOS" or "NORMAL"))
    if SH.is_team_mode() then Team.update_scores() end
    djui_popup_create_global("STARHUNT " .. mode_name .. ": " .. tostring(minutes) .. " MINUTES", 1)
    return true
end

local function remember_player_index(index)
    if not network_is_server() or not is_round_active() then return end
    local sync = gPlayerSyncTable[index]
    local network_player = gNetworkPlayers[index]
    if sync == nil or network_player == nil or (sync.sh5_enrolled or 0) ~= 1 then return end
    local name = network_player.name or ""
    local key = player_record_key(index)
    if name == "" or key == nil then return end
    SH.host_player_records[key] = {
        key = key,
        name = name,
        enrolled = 1,
        score = sync.sh5_score or 0,
        goal = sync.sh5_goal or 0,
        modifier = sync.sh5_modifier or 0,
        modifier_2 = sync.sh5_modifier_2 or 0,
        done = sync.sh5_done or 0,
        forfeit = sync.sh5_forfeit or 0,
        manual_reroll_request = sync.sh5_manual_reroll_request or 0,
        manual_reroll_ack = sync.sh5_manual_reroll_ack or 0,
        manual_reroll_remaining = SH.seconds_left("reroll" .. index),
        jump_count = sync.sh5_jump_count or -1,
        boss_victory = sync.sh5_boss_victory or 0,
        chaos_eliminated = sync.sh5_chaos_eliminated or 0,
        team = sync.sh5_team or Team.Color.NONE,
        lifetime_stars = sync.sh5_lifetime_stars or 0,
    }
end

local function remember_disconnected_player(m)
    if m ~= nil then remember_player_index(m.playerIndex) end
end

local function mark_connected_player_unenrolled(m)
    if not network_is_server() or not is_round_active() or m == nil or m.playerIndex == 0 then return end
    -- Player sync slots can still contain the previous occupant's values.
    -- Force the host preparation route, which safely restores a matching
    -- reconnect or creates a clean record for a genuinely new participant.
    gPlayerSyncTable[m.playerIndex].sh5_enrolled = 0
end

local function host_add_late_joiner(player_index)
    local sync = gPlayerSyncTable[player_index]
    if (sync.sh5_enrolled or 0) == 1 then return true end
    if host_prepare_player(player_index) then
        djui_chat_message_create(gNetworkPlayers[player_index].name
            .. (SH.is_chaos_mode() and " joined Chaos as a spectator."
                or " joined StarHunt and received a goal!"))
        return true
    end
    sync.sh5_enrolled = -1
    djui_chat_message_create("No unclaimed goal is left for " .. gNetworkPlayers[player_index].name .. ".")
    return false
end

local function host_update_boss_round()
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_boss_victory or 0) > 0 then
            host_end_round("boss defeated")
            return
        end
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_enrolled or 0) == 0 then
            host_prepare_player(i)
            djui_chat_message_create(gNetworkPlayers[i].name .. " joined the Bowser battle!")
        end
        if gNetworkPlayers[i].connected then remember_player_index(i) end
    end

    local level_index = gGlobalSyncTable.sh5_boss_level_index or 0
    local boss_level = BOSS_LEVELS[level_index]
    local boss_ready = false
    local reported_health = host_read_boss_health_report()
    if reported_health ~= nil then
        local authoritative = clamp(gGlobalSyncTable.sh5_boss_health or SH.boss_max_health(), 0, SH.boss_max_health())
        gGlobalSyncTable.sh5_boss_health = math.min(authoritative, reported_health)
        reported_health = gGlobalSyncTable.sh5_boss_health
        if reported_health <= 0 then
            host_end_round("boss defeated")
            return
        end
    end
    if boss_level ~= nil and gNetworkPlayers[0].currLevelNum == boss_level then
        local bowser = obj_get_first_with_behavior_id(id_bhvBowser)
        if bowser ~= nil then
            -- DEAD is Bowser's vanilla death sequence. End immediately,
            -- before he can open a dialog, create a key cutscene or trigger
            -- the final-star cinematic.
            if bowser.oAction == BOWSER_ACT.DEAD then
                host_end_round("boss defeated")
                return
            end
            -- The same four actions and one held state that stop the
            -- hazards on each client, and apply_boss_hazards in boss.lua
            -- carries the reasoning: TEXT_WAIT, INTRO_WALK and WAIT are his
            -- multiplayer intro, THROWN is the flight at a mine that follows
            -- a grab, and the held state is the grab itself. An attack
            -- queued in any of them is aimed at whoever grabbed him, who
            -- cannot dodge it.
            boss_ready = bowser.oAction ~= BOWSER_ACT.TEXT_WAIT
                and bowser.oAction ~= BOWSER_ACT.INTRO_WALK
                and bowser.oAction ~= BOWSER_ACT.WAIT
                and bowser.oAction ~= BOWSER_ACT.THROWN
                and not boss_is_held(bowser)
        end
    end

    SH.host_update_boss_bomb_supply()

    -- A temporarily missing Bowser can be caused by lag, ownership transfer or
    -- a player respawning. Never interpret that as a victory and never queue
    -- attacks without a valid, active boss.
    if not boss_ready then
        gGlobalSyncTable.sh5_boss_attack_frame = get_global_timer() + FRAMES_PER_SECOND
        return
    end

    local attack_choices = {}
    if boss_has_modifier(2) then table.insert(attack_choices, 2) end
    if boss_has_modifier(3) then table.insert(attack_choices, 3) end
    if boss_has_modifier(5) then table.insert(attack_choices, 5) end
    if boss_has_modifier(6) then table.insert(attack_choices, 6) end
    if boss_has_modifier(7) then table.insert(attack_choices, 7) end
    if boss_has_modifier(8) then table.insert(attack_choices, 8) end
    if boss_has_modifier(9) then table.insert(attack_choices, 9) end
    if boss_has_modifier(10) then table.insert(attack_choices, 10) end
    if boss_has_modifier(11) then table.insert(attack_choices, 11) end
    if #attack_choices > 0 and get_global_timer() >= (gGlobalSyncTable.sh5_boss_attack_frame or 0) then
        local attack_index = attack_choices[math.random(#attack_choices)]
        local attack_seq = (gGlobalSyncTable.sh5_boss_attack_seq or 0) + 1
        local queue_slot = ((attack_seq - 1) % BOSS_ATTACK_QUEUE_SIZE) + 1
        gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(queue_slot)] = attack_index
        gGlobalSyncTable.sh5_boss_attack_seq = attack_seq
        gGlobalSyncTable.sh5_boss_attack_kind = attack_index
        local attack_intervals = { [2] = 7, [3] = 6, [5] = 9, [6] = 8, [7] = 10, [8] = 9, [9] = 11, [10] = 8, [11] = 7 }
        local interval = attack_intervals[attack_index] or 8
        -- Rage and the desperate phase speed up only StarHunt's separate
        -- hazards. They never alter Bowser's action, movement or held state.
        if boss_has_modifier(4) then interval = math.max(4, math.floor(interval * 0.8)) end
        if boss_is_desperate() then interval = math.max(4, math.floor(interval * 0.65)) end
        local difficulty_factors = { 1.35, 1.0, 0.78, 0.55 }
        interval = math.max(SH.selected_difficulty() == SH.Difficulty.NIGHTMARE and 2 or 3,
            math.floor(interval * difficulty_factors[SH.selected_difficulty() + 1] + 0.5))
        gGlobalSyncTable.sh5_boss_attack_frame = get_global_timer() + interval * FRAMES_PER_SECOND
    end
end

SH.host_update_chaos_round = function()
    SH.host_reroll_chaos_modifiers()
    local alive_count, alive_name = 0, "Nobody"
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            local sync = gPlayerSyncTable[i]
            if (sync.sh5_enrolled or 0) == 0 then host_add_late_joiner(i) end
            if (sync.sh5_enrolled or 0) == 1 and (sync.sh5_chaos_eliminated or 0) == 0 then
                alive_count = alive_count + 1
                alive_name = gNetworkPlayers[i].name or "Player"
            end
            remember_player_index(i)
        end
    end
    gGlobalSyncTable.sh5_chaos_alive = alive_count
    if (gGlobalSyncTable.sh5_chaos_roster_locked or 0) == 1 and alive_count <= 1 then
        gGlobalSyncTable.sh5_chaos_winner = alive_count == 1 and alive_name or "Nobody"
        host_end_round("chaos last standing")
    end
end

local function host_update_round()
    if not network_is_server() or not is_round_active() then return end

    if SH.seconds_left("round") <= 0 then
        host_end_round(is_boss_mode() and "boss time expired" or "time expired")
        return
    end


    if is_boss_mode() then
        host_update_boss_round()
        return
    end

    if SH.is_chaos_mode() then
        SH.host_update_chaos_round()
        return
    end

    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            local sync = gPlayerSyncTable[i]
            if (sync.sh5_enrolled or 0) == 0 then
                host_add_late_joiner(i)
            end

            if (sync.sh5_enrolled or 0) == 1 then
                local manual_request = sync.sh5_manual_reroll_request or 0
                local manual_ack = sync.sh5_manual_reroll_ack or 0
                if manual_request ~= manual_ack then
                    sync.sh5_manual_reroll_ack = manual_request
                    if SH.seconds_left("reroll" .. i) <= 0
                        and (sync.sh5_goal or 0) ~= 0 then
                        local old_goal = get_goal(sync.sh5_goal or 0)
                        local old_modifier = old_goal
                            and old_goal.mods[sync.sh5_modifier or 0] or nil
                        if host_assign_goal(i, old_modifier and old_modifier.kind or nil,
                            old_goal and old_goal.level or nil) then
                            -- Only a level that actually came back restarts the
                            -- wait, and the counter is what tells every machine
                            -- to restart its own, this one included.
                            sync.sh5_manual_reroll_seq =
                                (sync.sh5_manual_reroll_seq or 0) + 1
                        end
                    end
                end

                local forfeits = sync.sh5_forfeit or 0
                if host_seen_forfeit[i] == nil then host_seen_forfeit[i] = forfeits end
                if forfeits ~= host_seen_forfeit[i] then
                    host_seen_forfeit[i] = forfeits
                    local old_goal = get_goal(sync.sh5_goal or 0)
                    local old_modifier = old_goal and old_goal.mods[sync.sh5_modifier or 0]
                    sync.sh5_goal = 0
                    sync.sh5_modifier = 0
                    sync.sh5_modifier_2 = 0
                    sync.sh5_jump_count = -1
                    if not host_assign_goal(i, old_modifier and old_modifier.kind or nil) then
                        host_end_round("all available goals were assigned")
                        return
                    end
                end

                local done = sync.sh5_done or 0
                if host_seen_done[i] == nil then host_seen_done[i] = done end
                if done ~= host_seen_done[i] then
                    host_seen_done[i] = done
                    if (sync.sh5_goal or 0) ~= 0 then
                        sync.sh5_score = (sync.sh5_score or 0) + 1
                        sync.sh5_goal = 0
                        sync.sh5_modifier = 0
                        sync.sh5_modifier_2 = 0
                        sync.sh5_jump_count = -1
                        if not host_assign_goal(i) then
                            host_end_round("all available goals were assigned")
                            return
                        end
                    end
                end
            end
            remember_player_index(i)
        end
    end
    if SH.is_team_mode() then Team.update_scores() end
end

local function on_before_boss_cutscene(m, incoming_action, _)
    if m.playerIndex ~= 0 or not is_round_active() or not is_boss_mode() then return end
    if incoming_action ~= ACT_STAR_DANCE_EXIT and incoming_action ~= ACT_STAR_DANCE_WATER
        and incoming_action ~= ACT_STAR_DANCE_NO_EXIT and incoming_action ~= ACT_JUMBO_STAR_CUTSCENE then
        return
    end

    -- Fallback for unusual Bowser behavior mods: the winning player reports
    -- the victory and cancels the cinematic on its very first frame.
    gPlayerSyncTable[0].sh5_boss_victory = (gPlayerSyncTable[0].sh5_boss_victory or 0) + 1
    if network_is_server() then host_end_round("boss defeated") end
    return 1
end

local function local_goal_warp_update(m)
    if m.playerIndex ~= 0 then return end
    if is_boss_mode() or SH.is_chaos_mode() then return end

    local current_goal_id = gPlayerSyncTable[0].sh5_goal or 0
    local current_goal = get_goal(current_goal_id)
    if is_round_active() and current_goal ~= nil and current_goal.level == LEVEL_TTC then
        -- Direct warps do not pass through the castle clock face. Keep TTC
        -- deterministic: slow for traversal stars and stopped for red coins.
        local desired_speed = current_goal.act == 6 and TTC_SPEED_STOPPED or TTC_SPEED_SLOW
        if get_ttc_speed_setting() ~= desired_speed then set_ttc_speed_setting(desired_speed) end
    end
    if is_round_active() and current_goal_id ~= local_runtime.goal_id then
        local_runtime.goal_id = current_goal_id
        local_runtime.goal_warp_at = get_global_timer() + (local_runtime.death_warp_pending and 0 or NEXT_GOAL_DELAY)
        local_runtime.star_visibility_next = 0
        local_runtime.modifier_ready_key = nil
        reset_local_modifier_state()
    elseif not is_round_active() then
        local_runtime.goal_id = 0
        local_runtime.goal_warp_at = -1
        local_runtime.modifier_ready_key = nil
        local_runtime.death_lock = false
        local_runtime.death_warp_pending = false
        reset_local_modifier_state()
    end

    if is_round_active() and current_goal_id ~= 0 and local_runtime.goal_warp_at >= 0
        and get_global_timer() >= local_runtime.goal_warp_at and not is_transition_playing() then
        local goal = get_goal(current_goal_id)
        if goal ~= nil then warp_to_level(goal.level, 1, goal.act) end
        local_runtime.goal_warp_at = -1
        local_runtime.death_lock = false
        local_runtime.death_warp_pending = false
    end
end

local function local_boss_warp_update(m)
    if m.playerIndex ~= 0 then return end
    if not is_round_active() or not is_boss_mode() then
        local_runtime.boss_warp_at = -1
        return
    end

    local round = gGlobalSyncTable.sh5_round or 0
    if round ~= local_runtime.boss_round_seen then
        local_runtime.boss_round_seen = round
        local_runtime.boss_warp_at = get_global_timer() + NEXT_GOAL_DELAY
        -- A late joiner starts from the current attack sequence. Old attacks
        -- must not all replay while that player is entering the arena.
        local_runtime.boss_hazard_seq = gGlobalSyncTable.sh5_boss_attack_seq or 0
        local_runtime.modifier_ready_key = nil
        reset_local_modifier_state()
    end
    if local_runtime.death_warp_pending then
        -- Respawn only Mario. Reloading the whole level here can recreate or
        -- transfer ownership of Bowser while the other players are fighting.
        if gNetworkPlayers[0].currLevelNum == LEVEL_BOWSER_3 then
            m.pos.x, m.pos.y, m.pos.z = 0, 1307, 0
            m.vel.x, m.vel.y, m.vel.z = 0, 0, 0
            m.forwardVel = 0
            m.health = 0x880
            m.hurtCounter = 0
            m.healCounter = 0
            m.invincTimer = 90
            set_mario_action(m, ACT_FREEFALL, 0)
            if m.area ~= nil and m.area.camera ~= nil then soft_reset_camera(m.area.camera) end
            local_runtime.boss_warp_at = -1
            local_runtime.death_lock = false
            local_runtime.death_warp_pending = false
            reset_local_modifier_state()
            return
        end
        local_runtime.boss_warp_at = get_global_timer()
    end

    local level = BOSS_LEVELS[gGlobalSyncTable.sh5_boss_level_index or 0]
    if level ~= nil and local_runtime.boss_warp_at >= 0 and get_global_timer() >= local_runtime.boss_warp_at
        and not is_transition_playing() then
        warp_to_level(level, 1, 1)
        local_runtime.boss_warp_at = -1
        local_runtime.death_lock = false
        local_runtime.death_warp_pending = false
    end
end

local local_seen_return_seq = 0
local local_return_warp_pending = false
local local_return_warp_retry_at = 0

-- The host writes a per-player sequence number when the round ends.  It stays
-- in that player's sync table until the next ending, which makes this robust
-- against a delayed result packet or a warp that was busy on the first frame.
local function force_return_to_lobby(m)
    if m.playerIndex ~= 0 then return end

    local return_seq = math.max(gPlayerSyncTable[0].sh5_return_seq or 0,
        gGlobalSyncTable.sh5_return_seq or 0)
    -- A return order from an older round may still be present when a delayed
    -- player joins the next one. Consume it while play is active.
    if is_round_active() then
        local_seen_return_seq = return_seq
        local_return_warp_pending = false
        return
    end
    if return_seq ~= local_seen_return_seq then
        local_seen_return_seq = return_seq
        local_return_warp_pending = return_seq ~= 0
        local_return_warp_retry_at = 0
        -- Every client owns its own save file. Clear its pending StarHunt
        -- stars as soon as the end-of-round packet arrives, before a warp or
        -- an immediate F12 exit can let vanilla save them again.
        flush_starhunt_save_removals(true, false)
    end

    if not local_return_warp_pending then return end
    if gNetworkPlayers[0].currLevelNum == LEVEL_CASTLE_GROUNDS then
        local_return_warp_pending = false
        return
    end
    if get_global_timer() >= local_return_warp_retry_at and not is_transition_playing() then
        warp_to_level(LEVEL_CASTLE_GROUNDS, 1, 0)
        local_return_warp_retry_at = get_global_timer() + FRAMES_PER_SECOND
    end
end

local function on_nametags_render(player_index, pos)
    local index = tonumber(player_index)
    if index ~= nil and index ~= 0 and is_round_active() and players_have_private_variant(0, index) then
        return { name = "", pos = pos }
    end
end

local function update_private_player_visibility()
    for i = 1, MAX_PLAYERS - 1 do
        local mario = gMarioStates[i]
        local object = mario ~= nil and mario.marioObj or nil
        local hide = gNetworkPlayers[i].connected and is_round_active()
            and players_have_private_variant(0, i)
        local tracked = local_runtime.hidden_players[i]
        if tracked ~= nil and tracked.object ~= object then
            local_runtime.hidden_players[i] = nil
            tracked = nil
        end
        if object ~= nil and hide then
            if tracked == nil then
                tracked = {
                    object = object,
                    was_invisible = (object.header.gfx.node.flags & GRAPH_RENDER_INVISIBLE) ~= 0,
                }
                local_runtime.hidden_players[i] = tracked
            end
            object.header.gfx.node.flags = object.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE
        elseif object ~= nil and tracked ~= nil then
            if not tracked.was_invisible then
                object.header.gfx.node.flags = object.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE
            end
            local_runtime.hidden_players[i] = nil
        elseif not gNetworkPlayers[i].connected then
            local_runtime.hidden_players[i] = nil
        end
    end
end

local function on_pause_exit(_)
    if is_round_active() then
        djui_popup_create(translated("FINISH THE ROUND OR ASK THE HOST TO STOP IT.", "TERMINA LA RONDA O PIDE AL HOST QUE LA DETENGA."), 1)
        return false
    end
    return true
end

local function on_death(m)
    grant_infinite_lives(m)
    if m.playerIndex ~= 0 or not is_round_active() then return true end
    -- Restore health immediately so the cancelled death cannot trigger again
    -- while the replacement goal is arriving from the host.
    m.health = 0x880
    m.hurtCounter = 0
    m.healCounter = 0
    m.invincTimer = 90
    -- Returning false cancels SM64's flying/death animation entirely.
    if is_boss_mode() then
        if not local_runtime.death_lock then
            local_runtime.death_lock = true
            local_runtime.death_warp_pending = true
            local_runtime.boss_warp_at = get_global_timer()
            djui_popup_create(translated("BACK TO THE BATTLE!", "DE VUELTA A LA BATALLA!"), 1)
        end
        return false
    end
    if SH.is_chaos_mode() then
        if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 0 then
            gPlayerSyncTable[0].sh5_chaos_eliminated = 1
            local_runtime.chaos_spectator_warped = false
            djui_popup_create(translated("ELIMINATED! SPECTATING...",
                "ELIMINADO! OBSERVANDO..."), 2)
        end
        return false
    end
    if local_runtime.done_lock or local_runtime.death_lock or get_local_goal() == nil then return false end
    local_runtime.death_lock = true
    local_runtime.death_warp_pending = true
    gPlayerSyncTable[0].sh5_forfeit = (gPlayerSyncTable[0].sh5_forfeit or 0) + 1
    djui_popup_create(translated("NEW GOAL INCOMING...", "NUEVO RETO..."), 1)
    return false
end

-- Cancel death actions before vanilla can show even one frame of the flying,
-- drowning or collapse animation. HOOK_ON_DEATH remains as a fallback for
-- void/death-plane deaths that do not pass through one of these actions.
local STARHUNT_DEATH_ACTIONS = {
    [ACT_DROWNING] = true,
    [ACT_WATER_DEATH] = true,
    [ACT_STANDING_DEATH] = true,
    [ACT_QUICKSAND_DEATH] = true,
    [ACT_ELECTROCUTION] = true,
    [ACT_SUFFOCATION] = true,
    [ACT_DEATH_ON_STOMACH] = true,
    [ACT_DEATH_ON_BACK] = true,
    [ACT_EATEN_BY_BUBBA] = true,
}

local function on_before_death_action(m, incoming_action, _)
    if m.playerIndex ~= 0 or not is_round_active()
        or not STARHUNT_DEATH_ACTIONS[incoming_action] then
        return
    end
    on_death(m)
    return 1
end

-- The vanilla Bowser 3 textbox blocks Mario while StarHunt's shared timer is
-- already running. Cancelling this dialog also lets the native camera leave
-- its looping dialog state immediately.
local function on_dialog(dialog_id)
    if not is_round_active() or not is_boss_mode() then return true end
    if gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then return true end
    local intro_dialog = DIALOG_093
    if gBehaviorValues ~= nil and gBehaviorValues.dialogs ~= nil
        and gBehaviorValues.dialogs.Bowser3Dialog ~= nil then
        intro_dialog = gBehaviorValues.dialogs.Bowser3Dialog
    end
    if dialog_id == intro_dialog then return false end
    return true
end

-- The eleven host functions below are what main.lua still calls: the hook
-- block drives the round loop, the Chaos and Boss loops that have not moved yet
-- call into the ending, and STARHUNT_TEST_API publishes six of them.  The rest
-- of the host half -- the goal pool, the winner tally, the per-player setup and
-- Boss's own loop -- has no caller outside this file and stays private.
--
-- main.lua registers every client function as a hook and publishes all ten of
-- them through STARHUNT_TEST_API.  STARHUNT_DEATH_ACTIONS and the three
-- local_return_warp_* variables are read nowhere else and stay private.
return {
    configured_time_range = configured_time_range,
    connected_player_count = connected_player_count,
    host_start_round = host_start_round,
    host_end_round = host_end_round,
    host_update_round = host_update_round,
    host_reset_scores_after_result = host_reset_scores_after_result,
    host_add_late_joiner = host_add_late_joiner,
    remember_player_index = remember_player_index,
    remember_disconnected_player = remember_disconnected_player,
    mark_connected_player_unenrolled = mark_connected_player_unenrolled,

    on_before_boss_cutscene = on_before_boss_cutscene,
    local_goal_warp_update = local_goal_warp_update,
    local_boss_warp_update = local_boss_warp_update,
    force_return_to_lobby = force_return_to_lobby,
    on_nametags_render = on_nametags_render,
    update_private_player_visibility = update_private_player_visibility,
    on_pause_exit = on_pause_exit,
    on_death = on_death,
    on_before_death_action = on_before_death_action,
    on_dialog = on_dialog,
}
