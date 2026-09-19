-- StarHunt v1.1.2 - Chaos mode.
--
-- Chaos has no star to hunt. Everyone warps to the same randomly chosen main
-- course and act, and the only thing that matters is outliving the others:
-- dying eliminates a player instead of handing them a new goal.
--
-- What it does instead of a goal is churn the modifiers. Each player carries
-- their own independent modifier, rerolled for everyone every CHAOS_REROLL_SECONDS,
-- and on Nightmare a compatible second one alongside it. Because Chaos draws
-- from the whole catalog rather than from one star's audited list, the pair
-- rules here are the only thing keeping two modifiers from cancelling each
-- other out or stacking into something unplayable -- see SH.chaos_conflicts.
--
-- The host side of the round loop, SH.host_update_chaos_round, lives in
-- round.lua and cannot come here. It counts survivors and ends the round, so it
-- calls round's host_end_round, host_add_late_joiner and remember_player_index,
-- and round.lua already requires this module for CHAOS_REROLL_SECONDS -- an edge
-- back the other way would be a require cycle. Boss's round loop is elsewhere
-- for the same reason.

local core = require("core")
local SH = core.SH
local local_runtime = core.local_runtime
local NEXT_GOAL_DELAY = core.NEXT_GOAL_DELAY
local is_round_active = core.is_round_active
local NORMAL_MODIFIER_CATALOG = require("audit").NORMAL_MODIFIER_CATALOG
local reset_local_modifier_state = require("modifiers").reset_local_modifier_state

local CHAOS_REROLL_SECONDS = 15

-- When the host last rerolled, in its own `clock_elapsed()` seconds. It is the
-- host's own countdown and never leaves this machine; each client runs the same
-- countdown from when it saw sh5_chaos_modifier_seq change.
local host_chaos_mark = nil

-- Starts that countdown. host_start_round calls it so the first reroll comes a
-- full interval after the round begins rather than on its first frame.
SH.arm_chaos_reroll = function()
    host_chaos_mark = clock_elapsed()
end
SH.chaos_maps = {
    LEVEL_BOB, LEVEL_WF, LEVEL_JRB, LEVEL_CCM, LEVEL_BBH,
    LEVEL_HMC, LEVEL_LLL, LEVEL_SSL, LEVEL_DDD, LEVEL_SL,
    LEVEL_WDW, LEVEL_TTM, LEVEL_THI, LEVEL_TTC, LEVEL_RR,
}

SH.chaos_conflicts = {
    no_b={ swap_ab=true }, swap_ab={ no_b=true },
    reverse_controls={ mirrored_steering=true, control_pulse=true, air_mirror=true },
    mirrored_steering={ reverse_controls=true, air_mirror=true },
    air_mirror={ reverse_controls=true, mirrored_steering=true },
    control_pulse={ reverse_controls=true, mirrored_steering=true, air_mirror=true },
    low_jump={ high_gravity=true }, high_gravity={ low_jump=true },
    coin_toll={ coin_leak=true }, coin_leak={ coin_toll=true },
    coin_surge={ speed_cap=true, slow_pulse=true, coin_weight=true },
    speed_cap={ coin_surge=true }, slow_pulse={ coin_surge=true }, coin_weight={ coin_surge=true },
    periodic_freeze={ keep_moving=true, floor_doom=true },
}

SH.chaos_pair_allowed = function(first, second)
    if first == nil or second == nil or first.kind == second.kind then return false end
    local first_conflicts = SH.chaos_conflicts[first.kind]
    local second_conflicts = SH.chaos_conflicts[second.kind]
    return not ((first_conflicts ~= nil and first_conflicts[second.kind])
        or (second_conflicts ~= nil and second_conflicts[first.kind]))
end

SH.chaos_modifier_allowed = function(candidate)
    -- Coin Toll only gates a target star, and Chaos deliberately has none.
    return candidate ~= nil and candidate.kind ~= "coin_toll"
end

SH.pick_chaos_pair = function(previous_first)
    local first_choices = {}
    for index, candidate in ipairs(NORMAL_MODIFIER_CATALOG) do
        if SH.chaos_modifier_allowed(candidate) and index ~= previous_first then
            table.insert(first_choices, index)
        end
    end
    if #first_choices == 0 then return 0, 0 end
    local first_index = first_choices[math.random(#first_choices)]
    if SH.selected_difficulty() ~= SH.Difficulty.NIGHTMARE then return first_index, 0 end
    local second_choices = {}
    for index, candidate in ipairs(NORMAL_MODIFIER_CATALOG) do
        if SH.chaos_modifier_allowed(candidate)
            and SH.chaos_pair_allowed(NORMAL_MODIFIER_CATALOG[first_index], candidate) then
            table.insert(second_choices, index)
        end
    end
    if #second_choices == 0 then return 0, 0 end
    return first_index, second_choices[math.random(#second_choices)]
end

-- How long until the modifiers change, on this machine. hud.lua asks through
-- SH rather than requiring this module, which would add a require edge.
SH.chaos_reroll_seconds_left = function()
    return SH.seconds_left(local_runtime.chaos_mark, CHAOS_REROLL_SECONDS)
end

SH.host_reroll_chaos_modifiers = function()
    if not SH.is_chaos_mode() then return end
    local now = clock_elapsed()
    if host_chaos_mark ~= nil and now - host_chaos_mark < CHAOS_REROLL_SECONDS then return end
    local assigned = false
    for i = 0, MAX_PLAYERS - 1 do
        local sync = gPlayerSyncTable[i]
        if gNetworkPlayers[i].connected and (sync.sh5_enrolled or 0) == 1
            and (sync.sh5_chaos_eliminated or 0) == 0 then
            local first, second
            first, second = SH.pick_chaos_pair(sync.sh5_modifier or 0)
            if first ~= 0 then
                sync.sh5_modifier = first
                sync.sh5_modifier_2 = second
                assigned = true
            end
            local first_data = SH.effective_modifier(NORMAL_MODIFIER_CATALOG[first])
            local second_data = SH.effective_modifier(NORMAL_MODIFIER_CATALOG[second])
            sync.sh5_jump_count = first_data ~= nil and first_data.kind == "jump_limit" and first_data.value
                or (second_data ~= nil and second_data.kind == "jump_limit" and second_data.value or -1)
        end
    end
    if assigned then
        gGlobalSyncTable.sh5_chaos_modifier_seq =
            (gGlobalSyncTable.sh5_chaos_modifier_seq or 0) + 1
    end
    host_chaos_mark = now
end

SH.update_chaos_warp = function(m)
    if m.playerIndex ~= 0 then return end
    if not is_round_active() or not SH.is_chaos_mode() then
        local_runtime.chaos_round_seen = -1
        local_runtime.chaos_warp_at = -1
        local_runtime.chaos_spectator_warped = false
        return
    end

    local round = gGlobalSyncTable.sh5_round or 0
    if local_runtime.chaos_round_seen ~= round then
        local_runtime.chaos_round_seen = round
        local_runtime.chaos_warp_at = get_global_timer() + NEXT_GOAL_DELAY
        local_runtime.chaos_spectator_warped = false
        local_runtime.modifier_ready_key = nil
        reset_local_modifier_state()
    end

    if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1 then
        if not local_runtime.chaos_spectator_warped and not is_transition_playing() then
            warp_to_level(LEVEL_CASTLE_GROUNDS, 1, 1)
            local_runtime.chaos_spectator_warped = true
        end
        return
    end

    if local_runtime.chaos_warp_at >= 0
        and get_global_timer() >= local_runtime.chaos_warp_at
        and not is_transition_playing() then
        local level = gGlobalSyncTable.sh5_chaos_level
        local act = gGlobalSyncTable.sh5_chaos_act or 1
        if level ~= nil and level ~= 0 then warp_to_level(level, 1, act) end
        local_runtime.chaos_warp_at = -1
    end
end

-- The SH.* functions above attach to the shared SH table and need no
-- export. CHAOS_REROLL_SECONDS does: the HUD counts down to the next reroll.
return {
    CHAOS_REROLL_SECONDS = CHAOS_REROLL_SECONDS,
}
