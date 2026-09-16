-- StarHunt v1.1 - which of the 32 modifiers each of the 93 stars can survive.
--
-- BALANCE_AUDIT.md describes the four stages audit_modifier() runs, in order:
-- a button or ability the star requires may never be removed; a route that is
-- too precise or contains forced waiting rejects what would make it unfair;
-- per-star tuning softens a few values instead of rejecting them; and finally
-- numeric limits reject anything past a safe margin.
--
-- Requiring this module is what builds the matrix. rebuild_audited_modifiers()
-- runs at the bottom of the file and REWRITES every goal's `mods`: the goal
-- catalog's entries are hand-tuned value overrides, and the rebuild replaces
-- them with the full 32-entry catalog carrying those values where they exist,
-- minus whatever the audit rejects. Anything reading goal.mods therefore needs
-- this module to have been required first, which main.lua does.
--
-- act_is and goal_traits are private: the traits exist only to be audited, and
-- adding one changes the whole 93 x 32 matrix, so BALANCE_AUDIT.md's counts
-- have to be re-derived when they change.

local modifier = require("core").modifier
local GOALS = require("goals").GOALS

-- v1.1 checks every modifier against every goal. These are conservative
-- compatibility rules, not simulated playthroughs: 1) obvious mechanical
-- impossibilities, 2) route-specific risk, 3) per-star/fallback tuning, and
-- 4) numeric safety limits.
local NORMAL_MODIFIER_CATALOG = {
    modifier("no_b", 0, "B BUTTON LOCKED"),
    modifier("floor_doom", 5, "CURSED FLOOR: 5 SEC"),
    modifier("speed_cap", 34, "HEAVY FEET"),
    modifier("low_jump", 40, "LOW JUMPS"),
    modifier("water_cap", 34, "HEAVY SWIM"),
    modifier("jump_limit", 18, "18 JUMPS"),
    modifier("reverse_controls", 0, "REVERSED CONTROLS"),
    modifier("periodic_freeze", 7, "TIME FREEZE: EVERY 7 SEC"),
    modifier("fragile", 0, "FRAGILE: 4 HEALTH"),
    modifier("high_gravity", 1.0, "HIGH GRAVITY"),
    modifier("wind_gust", 7, "WIND GUSTS"),
    modifier("no_z", 0, "Z BUTTON LOCKED"),
    modifier("air_brake", 65, "WEAK AIR CONTROL"),
    modifier("lava_clock", 6, "DAMAGE EVERY 6 SEC"),
    modifier("turbo", 58, "TURBO MODE"),
    modifier("slippery", 0, "SLIPPERY SHOES"),
    modifier("swap_ab", 0, "A/B BUTTONS SWAPPED"),
    modifier("keep_moving", 3, "KEEP MOVING: 3 SEC"),
    modifier("jump_cooldown", 24, "JUMP COOLDOWN: 0.8 SEC"),
    modifier("coin_surge", 12, "COIN SURGE"),
    modifier("control_drift", 20, "WAVY CONTROLS"),
    modifier("coin_toll", 20, "COIN TOLL: 20 COINS"),
    modifier("darkness_pulse", 36, "DARKNESS PULSE"),
    modifier("mirrored_steering", 0, "MIRRORED STEERING"),
    modifier("coin_leak", 5, "COIN LEAK: EVERY 5 SEC"),
    modifier("slow_pulse", 32, "SLOW PULSE"),
    modifier("air_mirror", 0, "AIR MIRROR"),
    modifier("momentum_burst", 12, "MOMENTUM BURST"),
    modifier("control_pulse", 36, "CONTROL PULSE"),
    modifier("coin_weight", 55, "COIN WEIGHT"),
    modifier("gravity_wave", 0.45, "GRAVITY WAVE"),
    modifier("overheat", 2, "OVERHEAT: SLOW DOWN"),
}

local function act_is(goal_data, ...)
    for _, act in ipairs({ ... }) do
        if goal_data.act == act then return true end
    end
    return false
end

local function goal_traits(goal_data)
    local traits = {}
    traits.main_course = goal_data.level ~= LEVEL_TOTWC
        and goal_data.level ~= LEVEL_COTMC and goal_data.level ~= LEVEL_VCUTM
    traits.flight = goal_data.power == "wing" or goal_data.level == LEVEL_TOTWC
    traits.water = (goal_data.level == LEVEL_JRB and act_is(goal_data, 1, 2, 3, 4, 6))
        or (goal_data.level == LEVEL_DDD and act_is(goal_data, 2, 3, 4, 5, 6))
    traits.race = (goal_data.level == LEVEL_BOB and goal_data.act == 2)
        or (goal_data.level == LEVEL_CCM and goal_data.act == 3)
        or (goal_data.level == LEVEL_THI and goal_data.act == 3)
    traits.slide = (goal_data.level == LEVEL_CCM and act_is(goal_data, 1, 3))
        or (goal_data.level == LEVEL_TTM and goal_data.act == 4)
    traits.cannon = (goal_data.level == LEVEL_BOB and goal_data.act == 3)
        or (goal_data.level == LEVEL_WF and act_is(goal_data, 3, 6))
        or (goal_data.level == LEVEL_JRB and goal_data.act == 5)
        or (goal_data.level == LEVEL_WDW and goal_data.act == 5)
        or (goal_data.level == LEVEL_TTM and goal_data.act == 6)
        or (goal_data.level == LEVEL_RR and goal_data.act == 6)
    traits.needs_b = (goal_data.level == LEVEL_BOB and goal_data.act == 1)
        or (goal_data.level == LEVEL_BBH and act_is(goal_data, 1, 2, 5))
        or (goal_data.level == LEVEL_CCM and goal_data.act == 2)
        or (goal_data.level == LEVEL_CCM and goal_data.act == 6)
        or (goal_data.level == LEVEL_LLL and act_is(goal_data, 1, 2))
        or (goal_data.level == LEVEL_SSL and goal_data.act == 1)
        or (goal_data.level == LEVEL_SL and goal_data.act == 2)
        or (goal_data.level == LEVEL_SL and goal_data.act == 5)
        or (goal_data.level == LEVEL_TTM and goal_data.act == 2)
    traits.needs_z = (goal_data.level == LEVEL_BOB and goal_data.act == 6)
        or (goal_data.level == LEVEL_WF and goal_data.act == 1)
        or (goal_data.level == LEVEL_SSL and goal_data.act == 4)
        or (goal_data.level == LEVEL_THI and goal_data.act == 6)
    traits.precision = (goal_data.level == LEVEL_WF and goal_data.act == 5)
        or (goal_data.level == LEVEL_BBH and act_is(goal_data, 3, 5, 6))
        or (goal_data.level == LEVEL_CCM and goal_data.act == 6)
        or (goal_data.level == LEVEL_LLL and goal_data.act == 4)
        or (goal_data.level == LEVEL_DDD and goal_data.act == 3)
        or (goal_data.level == LEVEL_SL and goal_data.act == 5)
        or (goal_data.level == LEVEL_WDW and act_is(goal_data, 4, 5, 6))
        or (goal_data.level == LEVEL_TTM and act_is(goal_data, 1, 3, 5, 6))
        or (goal_data.level == LEVEL_THI and act_is(goal_data, 2, 3, 5, 6))
        or goal_data.level == LEVEL_TTC
        or goal_data.level == LEVEL_RR
        or traits.flight
    traits.platform_wait = (goal_data.level == LEVEL_HMC and goal_data.act == 2)
        or (goal_data.level == LEVEL_LLL and goal_data.act == 6)
        or (goal_data.level == LEVEL_WDW and act_is(goal_data, 4, 5))
        or (goal_data.level == LEVEL_TTC and act_is(goal_data, 1, 2, 3, 4, 5))
        or (goal_data.level == LEVEL_RR and act_is(goal_data, 1, 2))
    traits.waiting = traits.cannon or traits.race
        or traits.platform_wait
        or (goal_data.level == LEVEL_BOB and goal_data.act == 1)
        or (goal_data.level == LEVEL_HMC and goal_data.act == 1)
        or (goal_data.level == LEVEL_CCM and act_is(goal_data, 2, 5))
        or (goal_data.level == LEVEL_TTM and goal_data.act == 2)
    traits.long_route = goal_data.act == 4 or goal_data.act == 5 or goal_data.act == 6
        or goal_data.level == LEVEL_TTM or goal_data.level == LEVEL_THI
        or goal_data.level == LEVEL_TTC or goal_data.level == LEVEL_RR
    traits.dynamic_precision = goal_data.level == LEVEL_TTC or goal_data.level == LEVEL_RR
    traits.ghost_house = goal_data.level == LEVEL_BBH
    return traits
end

local function audit_modifier(goal_data, modifier_data)
    local traits = goal_traits(goal_data)
    local kind = modifier_data.kind

    -- Stage 1: an input or movement ability required by the star may never be removed.
    if kind == "no_b" and traits.needs_b then return false, 1, "B is required" end
    if kind == "no_z" and traits.needs_z then return false, 1, "Z is required" end
    if kind == "water_cap" and not traits.water then return false, 1, "no meaningful swim route" end
    if kind == "coin_toll" and not traits.main_course then
        return false, 1, "special course has no safe 20-coin margin"
    end
    if (kind == "coin_leak" or kind == "coin_surge") and not traits.main_course then
        return false, 1, "special course has no reliable coin supply"
    end
    if traits.flight and (kind == "low_jump" or kind == "high_gravity" or kind == "air_brake"
        or kind == "wind_gust" or kind == "jump_cooldown" or kind == "coin_surge"
        or kind == "air_mirror" or kind == "control_pulse" or kind == "gravity_wave") then
        return false, 1, "flight route loses reliable altitude"
    end

    -- Stage 2: reject combinations whose normal human route is too precise or must wait.
    if traits.precision and (kind == "low_jump" or kind == "high_gravity" or kind == "wind_gust"
        or kind == "air_brake" or kind == "turbo" or kind == "slippery"
        or kind == "control_drift" or kind == "coin_surge" or kind == "jump_cooldown"
        or kind == "slow_pulse" or kind == "air_mirror" or kind == "momentum_burst"
        or kind == "control_pulse" or kind == "gravity_wave") then
        return false, 2, "precision route lacks a fair recovery margin"
    end
    if traits.dynamic_precision and kind == "periodic_freeze" then
        return false, 2, "moving-platform route cannot safely freeze input"
    end
    if traits.ghost_house and (kind == "wind_gust" or kind == "turbo"
        or kind == "slippery" or kind == "control_drift") then
        return false, 2, "haunted-house route loses a reliable recovery margin"
    end
    if traits.race and (kind == "speed_cap" or kind == "periodic_freeze" or kind == "keep_moving"
        or kind == "slow_pulse" or kind == "air_mirror" or kind == "momentum_burst"
        or kind == "control_pulse" or kind == "coin_weight" or kind == "coin_surge"
        or kind == "overheat") then
        return false, 2, "race timing would depend on modifier luck"
    end
    if traits.waiting and kind == "keep_moving" then
        return false, 2, "route contains forced waiting"
    end
    if traits.slide and (kind == "control_drift" or kind == "coin_surge"
        or kind == "slow_pulse" or kind == "air_mirror" or kind == "momentum_burst"
        or kind == "control_pulse" or kind == "overheat") then
        return false, 2, "forced slide steering becomes inconsistent"
    end
    if kind == "darkness_pulse" and (traits.flight or traits.race
        or traits.dynamic_precision or traits.platform_wait) then
        return false, 2, "blind interval has no safe recovery window"
    end
    if kind == "mirrored_steering" and (traits.flight or traits.race
        or traits.slide or traits.precision) then
        return false, 2, "mirrored steering removes the route's recovery margin"
    end
    if kind == "control_pulse" and (traits.cannon or traits.platform_wait) then
        return false, 2, "timed control reversal conflicts with forced waiting"
    end
    if kind == "momentum_burst" and (traits.cannon or traits.platform_wait) then
        return false, 2, "automatic acceleration is unsafe near forced waiting"
    end

    -- Stage 3: conservative values leave reaction time and alternate routes.
    if kind == "jump_limit" and traits.long_route and not modifier_data.hand_tuned then modifier_data.value = 26 end
    if kind == "floor_doom" and (traits.precision or traits.waiting) and not modifier_data.hand_tuned then
        modifier_data.value = 7
    end
    if kind == "floor_doom" and traits.platform_wait then
        -- These routes contain elevators or slow moving platforms. Nine
        -- seconds still requires regular jumps without turning the ride into
        -- an unavoidable death.
        modifier_data.value = 9
    end
    if kind == "keep_moving" and traits.water then return false, 3, "water speed is not a fair idle test" end
    if kind == "swap_ab" and traits.slide then return false, 3, "slide recovery uses both buttons rapidly" end

    -- Stage 4: numeric emergency limits.  These values deliberately keep a
    -- visible margin instead of accepting frame-perfect or pixel-perfect play.
    if kind == "speed_cap" and modifier_data.value < 32 then return false, 4, "speed margin below 32" end
    if kind == "low_jump" and modifier_data.value < 38 then return false, 4, "jump-height margin below 38" end
    if kind == "high_gravity" and modifier_data.value > 1.1 then return false, 4, "gravity penalty above safe margin" end
    if kind == "air_brake" and modifier_data.value < 60 then return false, 4, "air control below 60 percent" end
    if kind == "jump_cooldown" and modifier_data.value > 26 then return false, 4, "jump delay above safe margin" end
    if kind == "slow_pulse" and modifier_data.value < 32 then return false, 4, "slow pulse below safe speed" end
    if kind == "momentum_burst" and modifier_data.value > 14 then return false, 4, "momentum burst above safe margin" end
    if kind == "control_pulse" and modifier_data.value > 45 then return false, 4, "control pulse lasts too long" end
    if kind == "coin_weight" and modifier_data.value < 54 then return false, 4, "coin-weight base speed too low" end
    if kind == "gravity_wave" and modifier_data.value > 0.6 then return false, 4, "gravity wave above safe margin" end
    if kind == "overheat" and modifier_data.value < 2 then return false, 4, "overheat warning window too short" end
    if kind == "coin_surge" and modifier_data.value > 20 then return false, 4, "coin surge above safe margin" end
    return true, 3, "approved with conservative tuning"
end

local MODIFIER_AUDIT = {}
local MODIFIER_AUDIT_COUNTS = { checked = 0, approved = 0, rejected = 0 }

local function rebuild_audited_modifiers()
    for goal_id, goal_data in ipairs(GOALS) do
        -- The goal definitions contain the deliberately hand-tuned values for
        -- their most important modifiers. Keep those values as overrides; the
        -- audit may reject an unsafe combination, but must never erase the
        -- per-star balancing work.
        local tuned_by_kind = {}
        for _, tuned in ipairs(goal_data.mods or {}) do
            tuned_by_kind[tuned.kind] = tuned
        end
        goal_data.mods = {}
        MODIFIER_AUDIT[goal_id] = {}
        for _, template in ipairs(NORMAL_MODIFIER_CATALOG) do
            local tuned = tuned_by_kind[template.kind]
            local candidate = modifier(template.kind,
                tuned ~= nil and tuned.value or template.value,
                tuned ~= nil and tuned.label or template.label)
            candidate.hand_tuned = tuned ~= nil
            local approved, stage, reason = audit_modifier(goal_data, candidate)
            MODIFIER_AUDIT[goal_id][candidate.kind] = { approved = approved, stage = stage, reason = reason }
            MODIFIER_AUDIT_COUNTS.checked = MODIFIER_AUDIT_COUNTS.checked + 1
            if approved then
                table.insert(goal_data.mods, candidate)
                MODIFIER_AUDIT_COUNTS.approved = MODIFIER_AUDIT_COUNTS.approved + 1
            else
                MODIFIER_AUDIT_COUNTS.rejected = MODIFIER_AUDIT_COUNTS.rejected + 1
            end
        end
    end
end

rebuild_audited_modifiers()

return {
    NORMAL_MODIFIER_CATALOG = NORMAL_MODIFIER_CATALOG,
    audit_modifier = audit_modifier,
    MODIFIER_AUDIT = MODIFIER_AUDIT,
    MODIFIER_AUDIT_COUNTS = MODIFIER_AUDIT_COUNTS,
}
