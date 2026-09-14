-- StarHunt v1.1 - difficulty, which is a separate axis from the four modes.
--
-- Every mode runs at Easy, Medium, Hard or Nightmare, and difficulty changes
-- the modifiers rather than the objective. Medium is the baseline and returns
-- v0.9's values untouched. Easy turns permanent restrictions into pulses, so a
-- locked B button becomes a few seconds of locked B on a ten-second cycle,
-- read back through Team.periodic_window. Hard and Nightmare scale the numbers
-- up. lower_is_harder is what says which direction "up" runs for each kind:
-- for a cursed-floor timer a smaller number is crueller, for a speed cap a
-- larger one is.
--
-- Team.effective_modifier_for_goal is the function to call whenever a goal is
-- involved -- never effective_modifier alone. It puts the scaled result back
-- through the audit and returns nil if difficulty pushed the modifier past
-- what that particular star can take. Difficulty must never be a way around
-- the audit, and that is the only thing enforcing it.

local core = require("core")
local Team = core.Team
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local local_runtime = core.local_runtime
local clamp = core.clamp
local audit_modifier = require("audit").audit_modifier

Team.selected_difficulty = function()
    return clamp(math.floor(gGlobalSyncTable.sh5_difficulty or Team.MEDIUM),
        Team.EASY, Team.NIGHTMARE)
end

Team.lower_is_harder = {
    floor_doom=true, speed_cap=true, low_jump=true, water_cap=true, jump_limit=true,
    periodic_freeze=true, wind_gust=true, air_brake=true, lava_clock=true,
    keep_moving=true, coin_leak=true, slow_pulse=true, coin_weight=true, overheat=true,
}

Team.effective_modifier = function(base)
    if base == nil then return nil end
    local result = {}
    for key, value in pairs(base) do result[key] = value end
    local difficulty = Team.selected_difficulty()
    if difficulty == Team.MEDIUM then return result end

    local kind, value = result.kind, result.value
    if difficulty == Team.EASY then
        if kind == "no_b" or kind == "no_z" or kind == "reverse_controls"
            or kind == "swap_ab" or kind == "mirrored_steering" then
            result.pulse_period, result.pulse_frames = 10, 3 * FRAMES_PER_SECOND
        elseif kind == "fragile" then
            result.health_cap = 0x600
        elseif kind == "slippery" or kind == "air_mirror" then
            result.pulse_period, result.pulse_frames = 10, 4 * FRAMES_PER_SECOND
        elseif Team.lower_is_harder[kind] then
            result.value = math.max(1, value * 1.35)
        else
            result.value = value * 0.75
        end
        result.freeze_frames = 15
        result.damage_amount = 0x80
    elseif difficulty == Team.HARD then
        if kind == "fragile" then
            result.health_cap = 0x300
        elseif Team.lower_is_harder[kind] then
            result.value = math.max(1, value * 0.82)
        else
            result.value = value * 1.25
        end
        result.freeze_frames = 36
        result.damage_amount = 0x180
    else
        if kind == "fragile" then
            result.health_cap = 0x200
        elseif Team.lower_is_harder[kind] then
            result.value = math.max(1, value * 0.65)
        else
            result.value = value * 1.6
        end
        result.freeze_frames = 54
        result.damage_amount = 0x200
    end

    -- Preserve integer semantics where the modifier is measured in frames,
    -- seconds, coins or jumps.
    if kind ~= "high_gravity" and kind ~= "gravity_wave" then
        result.value = math.max(1, math.floor(result.value + 0.5))
    end
    return result
end

Team.effective_modifier_for_goal = function(goal, base)
    local result = Team.effective_modifier(base)
    if goal == nil or result == nil then return result end
    local approved = audit_modifier(goal, result)
    if not approved then return nil end
    return result
end

Team.periodic_window = function(period_seconds, duration_frames)
    local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
    local period = math.max(1, period_seconds) * FRAMES_PER_SECOND
    return elapsed % period >= period - duration_frames
end

Team.difficulty_modifier_allowed = function(goal, candidate)
    if candidate == nil then return false end
    return Team.effective_modifier_for_goal(goal, candidate) ~= nil
end

-- Everything above attaches to the shared Team table, so requiring this
-- module is all a consumer needs.
return {}
