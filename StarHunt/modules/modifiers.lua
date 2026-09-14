-- StarHunt v1.1 - the modifiers, as the local player actually experiences them.
--
-- Everything here runs on the local player's own machine and is never
-- synchronized: what is agreed between players is only WHICH modifier each
-- player has, and that lives in the sync tables. How it feels -- the capped
-- speed, the locked button, the cursed floor -- is recomputed locally every
-- frame from local_runtime.
--
-- Two hooks rather than one, and the order matters. apply_local_modifier runs
-- under HOOK_BEFORE_MARIO_UPDATE and apply_post_moveset_limits re-clamps the
-- same limits under HOOK_MARIO_UPDATE, because character and moveset mods such
-- as OMM run their own HOOK_MARIO_UPDATE callbacks and would otherwise undo
-- everything applied before them.
--
-- Which modifier is in force is asked of Team.get_local_modifier_base, and the
-- answer depends on the mode: Boss draws from its own player catalog, Chaos
-- from the full audited catalog, and a star race from what the audit approved
-- for that particular star.

local core = require("core")
local Team = core.Team
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local local_runtime = core.local_runtime
local clamp = core.clamp
local is_round_active = core.is_round_active
local selected_mode = core.selected_mode
local is_boss_mode = core.is_boss_mode
local translated = require("i18n").translated
local goals = require("goals")
local get_local_goal = goals.get_local_goal
local goal_matches_player_area = goals.goal_matches_player_area
local NORMAL_MODIFIER_CATALOG = require("audit").NORMAL_MODIFIER_CATALOG
local BOSS_PLAYER_MODIFIERS = require("boss").BOSS_PLAYER_MODIFIERS
local on_allow_pvp_attack = require("team").on_allow_pvp_attack

-- This is the shallow, post-Vanish-Cap moat height. It keeps the water
-- visible and usable instead of deleting it below the map.
local CASTLE_LOWERED_MOAT = -450

local local_moat_refresh_at = 0

Team.modifier_override = nil

Team.get_local_modifier_base = function(slot)
    if is_boss_mode() then
        local field = slot == 2 and "sh5_boss_player_modifier_2" or "sh5_boss_player_modifier"
        return BOSS_PLAYER_MODIFIERS[gGlobalSyncTable[field] or 0]
    end
    if Team.is_chaos_mode() then
        local field = slot == 2 and "sh5_modifier_2" or "sh5_modifier"
        return NORMAL_MODIFIER_CATALOG[gPlayerSyncTable[0][field] or 0]
    end
    local goal_data = get_local_goal()
    if goal_data == nil then return nil end
    local field = slot == 2 and "sh5_modifier_2" or "sh5_modifier"
    return goal_data.mods[gPlayerSyncTable[0][field] or 0]
end

local function get_local_modifier()
    return Team.effective_modifier(Team.get_local_modifier_base(1))
end

Team.get_local_modifiers = function()
    local result = {}
    local goal = get_local_goal()
    local first = Team.get_local_modifier_base(1)
    if first ~= nil then
        local effective = (is_boss_mode() or Team.is_chaos_mode()) and Team.effective_modifier(first)
            or Team.effective_modifier_for_goal(goal, first)
        if effective ~= nil then table.insert(result, effective) end
    end
    if Team.is_chaos_mode() or Team.selected_difficulty() == Team.NIGHTMARE then
        local second = Team.get_local_modifier_base(2)
        if second ~= nil and (first == nil or second.kind ~= first.kind) then
            local effective = (is_boss_mode() or Team.is_chaos_mode())
                and Team.effective_modifier(second)
                or Team.effective_modifier_for_goal(goal, second)
            if effective ~= nil then table.insert(result, effective) end
        end
    end
    return result
end

Team.coin_count = function(m)
    if m ~= nil and m.numCoins ~= nil then return math.max(0, m.numCoins) end
    return math.max(0, hud_get_value(HUD_DISPLAY_COINS) or 0)
end

Team.coin_toll_paid = function(m, modifier_data)
    return modifier_data == nil or modifier_data.kind ~= "coin_toll"
        or Team.coin_count(m) >= modifier_data.value
end

Team.all_coin_tolls_paid = function(m)
    for _, modifier_data in ipairs(Team.get_local_modifiers()) do
        if not Team.coin_toll_paid(m, modifier_data) then return false end
    end
    return true
end

Team.local_modifier_of_kind = function(kind)
    for _, modifier_data in ipairs(Team.get_local_modifiers()) do
        if modifier_data.kind == kind then return modifier_data end
    end
    return nil
end

local function is_local_player_on_floor(m)
    if m.floor == nil or (m.action & ACT_FLAG_SWIMMING) ~= 0 then return false end
    return math.abs(m.pos.y - m.floorHeight) < 22
end

local function reset_local_modifier_state()
    local_runtime.floor_frames = 0
    local_runtime.slip_speed = 0
    local_runtime.modifier_tick = -1
    local_runtime.modifier_start_frame = get_global_timer()
    local_runtime.boss_stun_frames = 0
    local_runtime.boss_damage_lock = 0
    local_runtime.pending_double_waves = {}
    local_runtime.pending_meteors = {}
    local_runtime.idle_frames = 0
    local_runtime.last_move_x = nil
    local_runtime.last_move_z = nil
    local_runtime.wind_tick = -1
    local_runtime.freeze_tick = -1
    local_runtime.freeze_frames = 0
    local_runtime.freeze_yaw = nil
    local_runtime.last_coin_count = nil
    local_runtime.coin_leak_tick = -1
    local_runtime.momentum_tick = -1
    local_runtime.overheat_frames = 0
    local_runtime.jump_cooldown_frames = 0
    local_runtime.done_lock = false
end

-- Capping a vector, rather than multiplying it every frame, is stable and
-- avoids the progressive swim slowdown from the first version.
local function capped_horizontal_velocity(x, z, cap)
    local length = math.sqrt(x * x + z * z)
    if length > cap and length > 0 then
        local scale = cap / length
        return x * scale, z * scale
    end
    return x, z
end

local function swap_button_bits(bits, first, second)
    local has_first = (bits & first) ~= 0
    local has_second = (bits & second) ~= 0
    bits = bits & ~(first | second)
    if has_first then bits = bits | second end
    if has_second then bits = bits | first end
    return bits
end

local function rotate_stick(x, y, angle)
    local cosine, sine = math.cos(angle), math.sin(angle)
    return x * cosine - y * sine, x * sine + y * cosine
end

local function suppress_local_input(m)
    m.controller.buttonDown = 0
    m.controller.buttonPressed = 0
    m.controller.stickX = 0
    m.controller.stickY = 0
    m.controller.rawStickX = 0
    m.controller.rawStickY = 0
    m.intendedMag = 0
    if (m.action & ACT_FLAG_AIR) == 0 then m.forwardVel = 0 end
end

Team.apply_one_local_modifier = function(m)
    if m.playerIndex ~= 0 or not is_round_active() then return end
    if Team.is_chaos_mode() and (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1 then return end
    -- The configuration menu owns the controller completely. No challenge
    -- may remap or consume A/B, the stick, or the close button before it.
    if local_runtime.config_open then return end
    local modifier_data = Team.modifier_override or get_local_modifier()
    if modifier_data == nil then return end
    local ready_key
    if is_boss_mode() then
        if gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then return end
        ready_key = -(gGlobalSyncTable.sh5_round or 0)
    elseif Team.is_chaos_mode() then
        if gNetworkPlayers[0].currLevelNum ~= (gGlobalSyncTable.sh5_chaos_level or -1) then return end
        ready_key = 1000000 + (gGlobalSyncTable.sh5_chaos_modifier_seq or 0)
    else
        local goal = get_local_goal()
        if goal == nil or not goal_matches_player_area(goal, 0) then return end
        ready_key = gPlayerSyncTable[0].sh5_goal_seq or (gPlayerSyncTable[0].sh5_goal or 0)
    end
    if local_runtime.modifier_ready_key ~= ready_key then
        reset_local_modifier_state()
        local_runtime.modifier_ready_key = ready_key
    end

    -- Initialize the modifier clock before testing a pulsed Easy effect.
    -- Otherwise the first active frame resets the clock and collapses the
    -- intended multi-second window to a single frame.
    if modifier_data.pulse_period ~= nil
        and not Team.periodic_window(modifier_data.pulse_period, modifier_data.pulse_frames) then
        if modifier_data.kind == "periodic_freeze" then
            local_runtime.freeze_frames = 0
            local_runtime.freeze_yaw = nil
        elseif modifier_data.kind == "slippery" then
            -- Easy leaves Slippery inactive for six seconds. A new pulse must
            -- start from the current movement, not revive its previous speed.
            local_runtime.slip_speed = 0
        end
        return
    end

    if modifier_data.kind == "no_b" then
        m.controller.buttonDown = m.controller.buttonDown & ~B_BUTTON
        m.controller.buttonPressed = m.controller.buttonPressed & ~B_BUTTON

    elseif modifier_data.kind == "floor_doom" then
        if is_local_player_on_floor(m) then
            local_runtime.floor_frames = local_runtime.floor_frames + 1
            if local_runtime.floor_frames >= modifier_data.value * FRAMES_PER_SECOND then
                m.health = 0
                local_runtime.floor_frames = 0
                djui_popup_create(translated("THE CURSED FLOOR GOT YOU!", "EL PISO MALDITO TE ATRAPO!"), 1)
            end
        else
            local_runtime.floor_frames = 0
        end

    elseif modifier_data.kind == "speed_cap" then
        if m.forwardVel > modifier_data.value then m.forwardVel = modifier_data.value end
        if m.forwardVel < -modifier_data.value then m.forwardVel = -modifier_data.value end
        if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end

    elseif modifier_data.kind == "low_jump" then
        if (m.action & ACT_FLAG_AIR) ~= 0 and m.vel.y > modifier_data.value then
            m.vel.y = modifier_data.value
        end

    elseif modifier_data.kind == "water_cap" then
        if (m.action & ACT_FLAG_SWIMMING) ~= 0 then
            m.vel.x, m.vel.z = capped_horizontal_velocity(m.vel.x, m.vel.z, modifier_data.value)
            if m.vel.y > modifier_data.value then m.vel.y = modifier_data.value end
            if m.vel.y < -modifier_data.value then m.vel.y = -modifier_data.value end
            if m.forwardVel > modifier_data.value then m.forwardVel = modifier_data.value end
            if m.forwardVel < -modifier_data.value then m.forwardVel = -modifier_data.value end
        end

    elseif modifier_data.kind == "jump_limit" then
        if is_local_player_on_floor(m) and (m.controller.buttonPressed & A_BUTTON) ~= 0 then
            local left = gPlayerSyncTable[0].sh5_jump_count
            if left == nil then left = modifier_data.value end
            if left > 0 then
                local remaining = left - 1
                gPlayerSyncTable[0].sh5_jump_count = remaining
                if remaining == 0 then
                    m.health = 0
                    djui_popup_create(translated("NO JUMPS LEFT!", "NO QUEDAN SALTOS!"), 1)
                end
            else
                m.controller.buttonPressed = m.controller.buttonPressed & ~A_BUTTON
                m.controller.buttonDown = m.controller.buttonDown & ~A_BUTTON
                m.health = 0
                djui_popup_create(translated("NO JUMPS LEFT!", "NO QUEDAN SALTOS!"), 1)
            end
        end

    elseif modifier_data.kind == "reverse_controls" then
        m.controller.stickX = -m.controller.stickX
        m.controller.stickY = -m.controller.stickY
        m.controller.rawStickX = -m.controller.rawStickX
        m.controller.rawStickY = -m.controller.rawStickY

    elseif modifier_data.kind == "periodic_freeze" then
        local period = math.max(3, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / period)
        if tick > 0 and tick ~= local_runtime.freeze_tick then
            local_runtime.freeze_tick = tick
            local_runtime.freeze_frames = modifier_data.freeze_frames or 24
            local_runtime.freeze_yaw = nil
        end
        if local_runtime.freeze_frames > 0 then
            if local_runtime.freeze_yaw == nil then
                local_runtime.freeze_yaw = m.faceAngle ~= nil and m.faceAngle.y or m.intendedYaw
            end
            suppress_local_input(m)
            if local_runtime.freeze_yaw ~= nil then
                if m.faceAngle ~= nil then m.faceAngle.y = local_runtime.freeze_yaw end
                m.intendedYaw = local_runtime.freeze_yaw
            end
            local_runtime.freeze_frames = local_runtime.freeze_frames - 1
        else
            local_runtime.freeze_yaw = nil
        end

    elseif modifier_data.kind == "fragile" then
        local health_cap = modifier_data.health_cap or 0x400
        if m.health > health_cap then m.health = health_cap end

    elseif modifier_data.kind == "high_gravity" then
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            m.vel.y = math.max(-75, m.vel.y - modifier_data.value)
        end

    elseif modifier_data.kind == "wind_gust" then
        local period = math.max(4, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = get_global_timer() - local_runtime.modifier_start_frame
        local tick = math.floor(math.max(0, elapsed) / period)
        if tick > 0 and tick ~= local_runtime.wind_tick then
            local_runtime.wind_tick = tick
            local seed = (gPlayerSyncTable[0].sh5_goal_seq or 1) * 1.73 + elapsed * 0.013
            m.vel.x = m.vel.x + math.sin(seed) * 38
            m.vel.z = m.vel.z + math.cos(seed) * 38
        end

    elseif modifier_data.kind == "no_z" then
        m.controller.buttonDown = m.controller.buttonDown & ~Z_TRIG
        m.controller.buttonPressed = m.controller.buttonPressed & ~Z_TRIG

    elseif modifier_data.kind == "air_brake" then
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            -- intendedMag is recalculated by the engine after
            -- HOOK_BEFORE_MARIO_UPDATE, so scale the actual controller input.
            local scale = modifier_data.value / 100
            m.controller.stickX = m.controller.stickX * scale
            m.controller.stickY = m.controller.stickY * scale
            m.controller.rawStickX = m.controller.rawStickX * scale
            m.controller.rawStickY = m.controller.rawStickY * scale
            m.intendedMag = m.intendedMag * scale
        end

    elseif modifier_data.kind == "lava_clock" then
        local period = math.max(6, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / period)
        if tick > 0 and tick ~= local_runtime.modifier_tick then
            local_runtime.modifier_tick = tick
            local damage = modifier_data.damage_amount or 0x100
            if m.health <= damage + 0x80 then m.health = 0 else m.health = m.health - damage end
        end

    elseif modifier_data.kind == "turbo" then
        if m.intendedMag > 10 and math.abs(m.forwardVel) > 2 then
            local sign = m.forwardVel < 0 and -1 or 1
            m.forwardVel = sign * math.min(modifier_data.value, math.abs(m.forwardVel) * 1.035 + 0.35)
        end

    elseif modifier_data.kind == "slippery" then
        if is_local_player_on_floor(m) then
            if math.abs(m.forwardVel) > math.abs(local_runtime.slip_speed) then
                local_runtime.slip_speed = m.forwardVel
            elseif math.abs(local_runtime.slip_speed) > math.abs(m.forwardVel) then
                m.forwardVel = local_runtime.slip_speed
            end
            if local_runtime.slip_speed > 0 then
                local_runtime.slip_speed = math.max(0, local_runtime.slip_speed - 0.35)
            else
                local_runtime.slip_speed = math.min(0, local_runtime.slip_speed + 0.35)
            end
        else
            local_runtime.slip_speed = m.forwardVel
        end

    elseif modifier_data.kind == "swap_ab" then
        m.controller.buttonDown = swap_button_bits(m.controller.buttonDown, A_BUTTON, B_BUTTON)
        m.controller.buttonPressed = swap_button_bits(m.controller.buttonPressed, A_BUTTON, B_BUTTON)

    elseif modifier_data.kind == "keep_moving" then
        local moved = true
        if local_runtime.last_move_x ~= nil and local_runtime.last_move_z ~= nil then
            local dx = m.pos.x - local_runtime.last_move_x
            local dz = m.pos.z - local_runtime.last_move_z
            moved = dx * dx + dz * dz >= 1
        end
        local_runtime.last_move_x = m.pos.x
        local_runtime.last_move_z = m.pos.z
        if is_local_player_on_floor(m) then
            if moved then
                local_runtime.idle_frames = 0
            else
                local_runtime.idle_frames = local_runtime.idle_frames + 1
                if local_runtime.idle_frames >= modifier_data.value * FRAMES_PER_SECOND then
                    m.health = 0
                    local_runtime.idle_frames = 0
                    djui_popup_create(translated("KEEP MOVING!", "SIGUE MOVIENDOTE!"), 1)
                end
            end
        else
            local_runtime.idle_frames = 0
        end

    elseif modifier_data.kind == "jump_cooldown" then
        if local_runtime.jump_cooldown_frames > 0 then
            local_runtime.jump_cooldown_frames = local_runtime.jump_cooldown_frames - 1
            if (m.controller.buttonPressed & A_BUTTON) ~= 0 then
                m.controller.buttonPressed = m.controller.buttonPressed & ~A_BUTTON
                m.controller.buttonDown = m.controller.buttonDown & ~A_BUTTON
            end
        elseif is_local_player_on_floor(m) and (m.controller.buttonPressed & A_BUTTON) ~= 0 then
            local_runtime.jump_cooldown_frames = modifier_data.value
        end

    elseif modifier_data.kind == "coin_surge" then
        local coins = Team.coin_count(m)
        if local_runtime.last_coin_count ~= nil and coins > local_runtime.last_coin_count then
            local gained = math.min(2, coins - local_runtime.last_coin_count)
            m.forwardVel = math.min(64, math.max(0, m.forwardVel) + modifier_data.value * gained)
        end
        local_runtime.last_coin_count = coins

    elseif modifier_data.kind == "control_drift" then
        local elapsed = get_global_timer() - local_runtime.modifier_start_frame
        local max_angle = math.rad(modifier_data.value)
        local angle = math.sin(elapsed / 24) * max_angle
        m.controller.stickX, m.controller.stickY = rotate_stick(m.controller.stickX, m.controller.stickY, angle)
        m.controller.rawStickX, m.controller.rawStickY = rotate_stick(
            m.controller.rawStickX, m.controller.rawStickY, angle)

    elseif modifier_data.kind == "mirrored_steering" then
        m.controller.stickX = -m.controller.stickX
        m.controller.rawStickX = -m.controller.rawStickX

    elseif modifier_data.kind == "coin_leak" then
        local period = math.max(3, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / period)
        if tick > 0 and tick ~= local_runtime.coin_leak_tick then
            local_runtime.coin_leak_tick = tick
            m.numCoins = math.max(0, (m.numCoins or 0) - 1)
        end

    elseif modifier_data.kind == "slow_pulse" then
        if Team.periodic_window(8, 45) then
            m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
            if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end
        end

    elseif modifier_data.kind == "air_mirror" then
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            m.controller.stickX = -m.controller.stickX
            m.controller.rawStickX = -m.controller.rawStickX
        end

    elseif modifier_data.kind == "momentum_burst" then
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / (8 * FRAMES_PER_SECOND))
        if tick > 0 and tick ~= local_runtime.momentum_tick then
            local_runtime.momentum_tick = tick
            if is_local_player_on_floor(m) and m.intendedMag > 10 then
                local sign = m.forwardVel < 0 and -1 or 1
                m.forwardVel = sign * math.min(60, math.abs(m.forwardVel) + modifier_data.value)
            end
        end

    elseif modifier_data.kind == "control_pulse" then
        if Team.periodic_window(9, modifier_data.value) then
            m.controller.stickX = -m.controller.stickX
            m.controller.stickY = -m.controller.stickY
            m.controller.rawStickX = -m.controller.rawStickX
            m.controller.rawStickY = -m.controller.rawStickY
        end

    elseif modifier_data.kind == "coin_weight" then
        local speed = math.max(35, modifier_data.value - math.floor(Team.coin_count(m) / 5))
        m.forwardVel = clamp(m.forwardVel, -speed, speed)
        if m.intendedMag > speed then m.intendedMag = speed end

    elseif modifier_data.kind == "gravity_wave" then
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        if math.floor(elapsed / (3 * FRAMES_PER_SECOND)) % 2 == 1
            and (m.action & ACT_FLAG_AIR) ~= 0 then
            m.vel.y = math.max(-75, m.vel.y - modifier_data.value)
        end

    elseif modifier_data.kind == "overheat" then
        if is_local_player_on_floor(m) and math.abs(m.forwardVel) > 48 then
            local_runtime.overheat_frames = local_runtime.overheat_frames + 1
            if local_runtime.overheat_frames >= modifier_data.value * FRAMES_PER_SECOND then
                local_runtime.overheat_frames = 0
                local damage = modifier_data.damage_amount or 0x100
                if m.health <= damage + 0x80 then m.health = 0 else m.health = m.health - damage end
                djui_popup_create(translated("OVERHEATED! SLOW DOWN!", "SOBRECALENTADO! FRENA!"), 1)
            end
        else
            local_runtime.overheat_frames = math.max(0, local_runtime.overheat_frames - 2)
        end

    elseif modifier_data.kind == "coin_toll" or modifier_data.kind == "darkness_pulse" then
        -- These modifiers are enforced by star interaction/HUD rendering.
    end
end

Team.apply_local_modifier = function(m)
    local modifiers = Team.get_local_modifiers()
    for _, modifier_data in ipairs(modifiers) do
        Team.modifier_override = modifier_data
        Team.apply_one_local_modifier(m)
    end
    Team.modifier_override = nil
end

-- Character/moveset mods run their own HOOK_MARIO_UPDATE callbacks and may
-- replace velocities after StarHunt's before-update challenge pass. Reapply
-- only idempotent limits here: effects such as gravity, turbo, slippery
-- movement and remapped controls must never be applied twice in one frame.
Team.apply_post_moveset_limits = function(m)
    if m.playerIndex ~= 0 or local_runtime.config_open or not is_round_active() then return end
    if is_boss_mode() then
        if gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then return end
    elseif Team.is_chaos_mode() then
        if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1
            or gNetworkPlayers[0].currLevelNum ~= (gGlobalSyncTable.sh5_chaos_level or -1) then
            return
        end
    else
        local goal = get_local_goal()
        if goal == nil or not goal_matches_player_area(goal, 0) then return end
    end

    -- Mario actions and custom movesets may rotate the model after the
    -- before-update input lock. Reapply the captured yaw on the same frame so
    -- a freeze is visually stable as well as mechanically stable.
    if local_runtime.freeze_yaw ~= nil then
        if m.faceAngle ~= nil then m.faceAngle.y = local_runtime.freeze_yaw end
        m.intendedYaw = local_runtime.freeze_yaw
    end

    for _, modifier_data in ipairs(Team.get_local_modifiers()) do
        local pulse_active = modifier_data.pulse_period == nil
            or Team.periodic_window(modifier_data.pulse_period, modifier_data.pulse_frames)
        if pulse_active and modifier_data.kind == "speed_cap" then
            m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
            if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end
        elseif pulse_active and modifier_data.kind == "low_jump" then
            if (m.action & ACT_FLAG_AIR) ~= 0 and m.vel.y > modifier_data.value then
                m.vel.y = modifier_data.value
            end
        elseif pulse_active and modifier_data.kind == "water_cap" then
            if (m.action & ACT_FLAG_SWIMMING) ~= 0 then
                m.vel.x, m.vel.z = capped_horizontal_velocity(m.vel.x, m.vel.z, modifier_data.value)
                m.vel.y = clamp(m.vel.y, -modifier_data.value, modifier_data.value)
                m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
            end
        elseif pulse_active and modifier_data.kind == "fragile" then
            local health_cap = modifier_data.health_cap or 0x400
            if m.health > health_cap then m.health = health_cap end
        elseif pulse_active and modifier_data.kind == "slow_pulse" then
            if Team.periodic_window(8, 45) then
                m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
                if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end
            end
        elseif pulse_active and modifier_data.kind == "coin_weight" then
            local speed = math.max(35, modifier_data.value - math.floor(Team.coin_count(m) / 5))
            m.forwardVel = clamp(m.forwardVel, -speed, speed)
            if m.intendedMag > speed then m.intendedMag = speed end
        end
    end
end

-- StarHunt has no game-over state: deaths only lead to a new challenge.
-- Keep a high life count every frame, including the frame in which Mario dies.
local function grant_infinite_lives(m)
    if m.playerIndex ~= 0 then return end
    if is_round_active() then
        if local_runtime.lives_before_round == nil then local_runtime.lives_before_round = m.numLives end
        m.numLives = 99
    elseif local_runtime.lives_before_round ~= nil then
        m.numLives = local_runtime.lives_before_round
        local_runtime.lives_before_round = nil
    end
end

Team.local_index_from_global = function(global_index)
    if global_index == nil or type(network_local_index_from_global) ~= "function" then return nil end
    local index = network_local_index_from_global(global_index)
    if type(index) ~= "number" or index < 0 or index >= MAX_PLAYERS then return nil end
    if gNetworkPlayers[index] == nil or not gNetworkPlayers[index].connected then return nil end
    return index
end

-- Gun Mod bullets call their registered Mario hitbox directly, bypassing
-- HOOK_ALLOW_PVP_ATTACK. Wrap only that public hitbox entry so Gun Mod keeps
-- all of its normal damage, metal-cap and invincibility behaviour while
-- respecting the same Normal/Boss/TEAM PvP rules as direct attacks.
Team.install_gun_mod_compatibility = function()
    if local_runtime.gun_mod_compat_wrapper ~= nil then return true end
    local api = rawget(_G, "gunModApi")
    local hitboxes = rawget(_G, "gShootableHitboxes")
    local mario_behavior = rawget(_G, "id_bhvMario")
    if type(api) ~= "table" or type(api.obj_get_weapon_owner) ~= "function"
        or type(hitboxes) ~= "table" or mario_behavior == nil
        or type(hitboxes[mario_behavior]) ~= "function" then
        return false
    end

    local_runtime.gun_mod_compat_original = hitboxes[mario_behavior]
    local_runtime.gun_mod_compat_wrapper = function(target_object, bullet_object)
        if is_round_active() and target_object ~= nil and bullet_object ~= nil then
            local attacker_index = Team.local_index_from_global(api.obj_get_weapon_owner(bullet_object))
            local victim_index = Team.local_index_from_global(target_object.globalPlayerIndex)
            if attacker_index ~= nil and victim_index ~= nil
                and not on_allow_pvp_attack(
                    { playerIndex = attacker_index }, { playerIndex = victim_index }, nil) then
                return true
            end
        end
        return local_runtime.gun_mod_compat_original(target_object, bullet_object)
    end
    hitboxes[mario_behavior] = local_runtime.gun_mod_compat_wrapper
    return true
end

local function keep_moat_lowered()
    if get_global_timer() < local_moat_refresh_at then return end
    if gNetworkPlayers[0].currLevelNum ~= LEVEL_CASTLE_GROUNDS then return end
    local_moat_refresh_at = get_global_timer() + FRAMES_PER_SECOND

    -- Every local game gets the visual height; the host also synchronizes it.
    set_water_level(0, CASTLE_LOWERED_MOAT, network_is_server())
    set_water_level(1, CASTLE_LOWERED_MOAT, network_is_server())
end

Team.manual_reroll_remaining = function()
    if not is_round_active() or (selected_mode() ~= Team.NORMAL and not Team.is_mode())
        or get_local_goal() == nil then
        return nil
    end
    return math.max(0, (gPlayerSyncTable[0].sh5_manual_reroll_ready_frame or 0)
        - get_global_timer())
end

Team.manual_reroll_label = function()
    local base = translated("ANOTHER LEVEL", "OTRO NIVEL")
    local remaining = Team.manual_reroll_remaining()
    if remaining == nil then
        return base .. " - " .. translated("NORMAL/TEAM ONLY", "SOLO NORMAL/TEAM")
    end
    if remaining <= 0 then
        return base .. " - " .. translated("READY", "LISTO")
    end
    local seconds = math.ceil(remaining / FRAMES_PER_SECOND)
    return base .. " - " .. string.format("%d:%02d",
        math.floor(seconds / 60), seconds % 60)
end

Team.request_manual_reroll = function(_)
    local remaining = Team.manual_reroll_remaining()
    if remaining == nil then
        djui_popup_create(translated(
            "ANOTHER LEVEL IS ONLY AVAILABLE IN NORMAL OR TEAM.",
            "OTRO NIVEL SOLO ESTA DISPONIBLE EN NORMAL O TEAM."), 2)
        return
    end
    if remaining > 0 then
        local seconds = math.ceil(remaining / FRAMES_PER_SECOND)
        djui_popup_create(translated("ANOTHER LEVEL AVAILABLE IN ",
            "OTRO NIVEL DISPONIBLE EN ")
                .. string.format("%d:%02d", math.floor(seconds / 60), seconds % 60), 2)
        return
    end
    local sync = gPlayerSyncTable[0]
    if (sync.sh5_manual_reroll_request or 0) ~= (sync.sh5_manual_reroll_ack or 0) then
        djui_popup_create(translated("A LEVEL CHANGE IS ALREADY PENDING.",
            "YA HAY UN CAMBIO DE NIVEL PENDIENTE."), 1)
        return
    end
    sync.sh5_manual_reroll_request = (sync.sh5_manual_reroll_request or 0) + 1
    djui_popup_create(translated("NEW LEVEL REQUESTED.",
        "NUEVO NIVEL SOLICITADO."), 1)
end

Team.register_mod_compatibility = function()
    Team.install_gun_mod_compatibility()

    if not local_runtime.dnc_compat_registered then
        local api = rawget(_G, "dayNightCycleApi")
        local hook_id = type(api) == "table" and type(api.constants) == "table"
            and api.constants.DNC_HOOK_ON_HUD_RENDER_BEHIND or nil
        if type(api) == "table" and type(api.dnc_hook_event) == "function" and hook_id ~= nil then
            -- Day/Night invokes this before drawing its clock. The frame guard
            -- keeps the regular fallback hook from drawing over that clock.
            api.dnc_hook_event(hook_id, Team.draw_darkness_behind)
            local_runtime.dnc_compat_registered = true
        end
    end

    if not local_runtime.widdlepets_compat_registered then
        local pets = rawget(_G, "wpets")
        if type(pets) == "table" and type(pets.hook_allow_menu) == "function" then
            pets.hook_allow_menu(function() return not local_runtime.config_open end)
            local_runtime.widdlepets_compat_registered = true
        end
    end
end

-- The Team.* functions above attach to the shared Team table. These are the
-- file-local ones main.lua still calls, from its hook block and its load-time
-- self-check.
return {
    is_local_player_on_floor = is_local_player_on_floor,
    reset_local_modifier_state = reset_local_modifier_state,
    capped_horizontal_velocity = capped_horizontal_velocity,
    swap_button_bits = swap_button_bits,
    rotate_stick = rotate_stick,
    grant_infinite_lives = grant_infinite_lives,
    keep_moat_lowered = keep_moat_lowered,
}
