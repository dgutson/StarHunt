-- name: \\#FFE05A\\Star\\#58D6FF\\Hunt \\#FFFFFF\\v1.1\\#DCDCDC\\
-- description: \\#FFE05A\\STARHUNT v1.1\\#FFFFFF\\ - Normal, Team, Boss and Chaos!\n\\#58D6FF\\93 goals, 32 audited modifiers and four difficulty levels.\n\\#FF7792\\Six languages, balanced teams, OMM and Character Select support.\n\\#C78CFF\\Menu: /starhunt | Updates: /starhunt updates
-- incompatible: romhack
--
-- StarHunt v1.1
-- Normal: all fifteen main worlds plus Wing, Metal and Vanish Cap courses.
-- Team: the same star race split into balanced Red and Blue teams.
-- Boss: every player fights Bowser in the Sky under three global modifiers.
-- Chaos: last-player-standing PvP on one random main-course map. Every player
-- gets an independent modifier rerolled every 15 seconds; Nightmare gives two.

local core = require("modules/core")
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local START_BANNER_FRAMES = 105
local NEXT_GOAL_DELAY = core.NEXT_GOAL_DELAY

-- Co-op DX reads this setting before starting the Peach/Lakitu opening scene.
-- Keep it enabled while StarHunt is installed so the game reaches the lobby
-- immediately after launching.
gServerSettings.skipIntro = 1

local Team = core.Team
local local_runtime = core.local_runtime
local clamp = core.clamp
local translated = require("modules/i18n").translated
local is_round_active = core.is_round_active
local selected_mode = core.selected_mode
local is_boss_mode = core.is_boss_mode
local player_record_key = core.player_record_key
local is_local_player_on_floor = core.is_local_player_on_floor
local save = require("modules/save")
local remove_starhunt_save_flag = save.remove_starhunt_save_flag
local flush_starhunt_save_removals = save.flush_starhunt_save_removals
local flush_starhunt_save_on_warp = save.flush_starhunt_save_on_warp
local flush_starhunt_save_on_exit = save.flush_starhunt_save_on_exit
local goal_already_collected = save.goal_already_collected
local goals = require("modules/goals")
local GOALS = goals.GOALS
local get_goal = goals.get_goal
local get_local_goal = goals.get_local_goal
local goal_world_text = goals.goal_world_text
local goal_title_text = goals.goal_title_text
local goal_matches_player_area = goals.goal_matches_player_area
local goal_matches_star_object = goals.goal_matches_star_object
local apply_goal_power = goals.apply_goal_power
local on_allow_interact = goals.on_allow_interact
local on_interact = goals.on_interact
local reset_hidden_object_tracking = goals.reset_hidden_object_tracking
local update_star_visibility = goals.update_star_visibility
local players_have_private_variant = goals.players_have_private_variant
local players_can_share_world = goals.players_can_share_world
local audit = require("modules/audit")
local NORMAL_MODIFIER_CATALOG = audit.NORMAL_MODIFIER_CATALOG
-- Attaches the difficulty scaling to Team; nothing to bind here.
require("modules/difficulty")
local on_allow_pvp_attack = require("modules/team").on_allow_pvp_attack
local boss = require("modules/boss")
local BOSS_HEALTH = boss.BOSS_HEALTH
local BOSS_LEVELS = boss.BOSS_LEVELS
local BOSS_PLAYER_MODIFIERS = boss.BOSS_PLAYER_MODIFIERS
local BOSS_MODIFIERS = boss.BOSS_MODIFIERS
local BOSS_MODIFIER_FIELDS = boss.BOSS_MODIFIER_FIELDS
local BOSS_ATTACK_QUEUE_SIZE = boss.BOSS_ATTACK_QUEUE_SIZE
local BOSS_ACTIVE_ATTACK_LOOKUP = boss.BOSS_ACTIVE_ATTACK_LOOKUP
local boss_has_modifier = boss.boss_has_modifier
local boss_is_desperate = boss.boss_is_desperate
local boss_modifier_text = boss.boss_modifier_text
local host_read_boss_health_report = boss.host_read_boss_health_report
local local_modifiers = require("modules/modifiers")
local reset_local_modifier_state = local_modifiers.reset_local_modifier_state
local capped_horizontal_velocity = local_modifiers.capped_horizontal_velocity
local grant_infinite_lives = local_modifiers.grant_infinite_lives
local keep_moat_lowered = local_modifiers.keep_moat_lowered
local run_static_modifier_checks = local_modifiers.run_static_modifier_checks
local CHAOS_REROLL_FRAMES = require("modules/chaos").CHAOS_REROLL_FRAMES
local local_round = require("modules/round")
local force_return_to_lobby = local_round.force_return_to_lobby
local on_nametags_render = local_round.on_nametags_render
local update_private_player_visibility = local_round.update_private_player_visibility
local on_pause_exit = local_round.on_pause_exit
local on_death = local_round.on_death
local on_before_death_action = local_round.on_before_death_action
local on_dialog = local_round.on_dialog
local configured_time_range = local_round.configured_time_range
local connected_player_count = local_round.connected_player_count
local host_start_round = local_round.host_start_round
local host_end_round = local_round.host_end_round
local host_update_round = local_round.host_update_round
local host_reset_scores_after_result = local_round.host_reset_scores_after_result
local host_add_late_joiner = local_round.host_add_late_joiner
local remember_player_index = local_round.remember_player_index
local remember_disconnected_player = local_round.remember_disconnected_player
local mark_connected_player_unenrolled = local_round.mark_connected_player_unenrolled

local local_seen_round = nil
local local_seen_result = nil
local local_start_banner_until = -1
local local_hud_flags_before_round = nil
local local_counter_round_active = false
local local_lakitu_scan_at = 0
Team.lifetime = math.max(0, math.floor(tonumber(
    mod_storage_load("starhunt_lifetime_stars")) or 0))
local config_selection = 1
local config_button_latch = 0
local config_stick_latched = false
local local_boss_health_object = nil
local local_boss_health_initialized = false
local local_boss_health_last_value = nil
local local_boss_health_report_at = 0


Team.update_lifetime_sync = function()
    gPlayerSyncTable[0].sh5_lifetime_stars = Team.lifetime
end

Team.darkness_active = function(modifier_data)
    if modifier_data == nil or modifier_data.kind ~= "darkness_pulse" then return false end
    local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
    local phase = elapsed % (10 * FRAMES_PER_SECOND)
    return phase >= 10 * FRAMES_PER_SECOND - modifier_data.value
end

local function modifier_text(modifier_data)
    if Team.language == 0 then return modifier_data.label end
    if Team.language >= 2 then
        local code = Team.language_codes[Team.language + 1]
        local label = Team.modifier_translations[code] and Team.modifier_translations[code][modifier_data.kind]
        if label == nil then return modifier_data.label end
        if modifier_data.kind == "floor_doom" or modifier_data.kind == "periodic_freeze"
            or modifier_data.kind == "lava_clock" or modifier_data.kind == "keep_moving"
            or modifier_data.kind == "coin_leak" then
            return label .. ": " .. tostring(modifier_data.value) .. " SEC"
        end
        if modifier_data.kind == "jump_limit" or modifier_data.kind == "coin_toll" then
            return tostring(modifier_data.value) .. " " .. label
        end
        if modifier_data.kind == "jump_cooldown" then
            return label .. ": " .. string.format("%.1f SEC", modifier_data.value / FRAMES_PER_SECOND)
        end
        return label
    end
    if modifier_data.kind == "no_b" then return "BOTON B BLOQUEADO" end
    if modifier_data.kind == "floor_doom" then return "PISO MALDITO: " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "speed_cap" then return "PIES PESADOS" end
    if modifier_data.kind == "low_jump" then return "SALTOS BAJOS" end
    if modifier_data.kind == "water_cap" then return "NADO PESADO" end
    if modifier_data.kind == "jump_limit" then return tostring(modifier_data.value) .. " SALTOS" end
    if modifier_data.kind == "reverse_controls" then return "CONTROLES INVERTIDOS" end
    if modifier_data.kind == "periodic_freeze" then return "TIEMPO CONGELADO CADA " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "fragile" then return "FRAGIL: 4 DE VIDA" end
    if modifier_data.kind == "high_gravity" then return "GRAVEDAD ALTA" end
    if modifier_data.kind == "wind_gust" then return "RAFAGAS DE VIENTO" end
    if modifier_data.kind == "no_z" then return "BOTON Z BLOQUEADO" end
    if modifier_data.kind == "air_brake" then return "POCO CONTROL AEREO" end
    if modifier_data.kind == "lava_clock" then return "DANO CADA " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "turbo" then return "MODO TURBO" end
    if modifier_data.kind == "slippery" then return "ZAPATOS RESBALADIZOS" end
    if modifier_data.kind == "swap_ab" then return "BOTONES A/B INTERCAMBIADOS" end
    if modifier_data.kind == "keep_moving" then return "SIGUE MOVIENDOTE: " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "jump_cooldown" then
        return string.format("ESPERA ENTRE SALTOS: %.1f SEG", modifier_data.value / FRAMES_PER_SECOND)
    end
    if modifier_data.kind == "coin_surge" then return "IMPULSO DE MONEDA" end
    if modifier_data.kind == "control_drift" then return "CONTROLES ONDULANTES" end
    if modifier_data.kind == "coin_toll" then
        return "PEAJE DE MONEDAS: " .. tostring(modifier_data.value)
    end
    if modifier_data.kind == "darkness_pulse" then return "PULSO DE OSCURIDAD" end
    if modifier_data.kind == "mirrored_steering" then return "DIRECCION ESPEJO" end
    if modifier_data.kind == "coin_leak" then
        return "FUGA DE MONEDAS CADA " .. tostring(modifier_data.value) .. " SEG"
    end
    if modifier_data.kind == "slow_pulse" then return "PULSO LENTO" end
    if modifier_data.kind == "air_mirror" then return "ESPEJO AEREO" end
    if modifier_data.kind == "momentum_burst" then return "IMPULSO PERIODICO" end
    if modifier_data.kind == "control_pulse" then return "PULSO DE CONTROLES" end
    if modifier_data.kind == "coin_weight" then return "PESO DE MONEDAS" end
    if modifier_data.kind == "gravity_wave" then return "GRAVEDAD ONDULANTE" end
    if modifier_data.kind == "overheat" then return "SOBRECALENTAMIENTO: FRENA" end
    return modifier_data.label
end

Team.pick_second_modifier = function(goal, first_index)
    local choices = {}
    local first = goal.mods[first_index]
    for index, candidate in ipairs(goal.mods) do
        if index ~= first_index and Team.chaos_pair_allowed(first, candidate)
            and Team.difficulty_modifier_allowed(goal, candidate) then
            table.insert(choices, index)
        end
    end
    if #choices == 0 then return 0 end
    return choices[math.random(#choices)]
end

Team.boss_reserve_bomb_count = function()
    local difficulty = Team.selected_difficulty()
    if difficulty == Team.HARD then return 2 end
    if difficulty == Team.NIGHTMARE then return 4 end
    return 0
end

-- Only the current host observes the native bomb supply and creates the
-- reserve. The synchronized flags make this one-shot survive a host change:
-- a replacement host cannot mistake its own level load for a new wave.
Team.host_update_boss_bomb_supply = function()
    if not network_is_server() or not is_round_active() or not is_boss_mode()
        or gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then
        return
    end

    local round = gGlobalSyncTable.sh5_round or 0
    if Team.bossBombSupplyRound ~= round then
        Team.bossBombSupplyRound = round
        Team.bossBombZeroSince = nil
    end

    local reserve_count = Team.boss_reserve_bomb_count()
    local already_spawned = gGlobalSyncTable.sh5_boss_extra_bombs_spawned or 0
    if reserve_count == 0 or already_spawned >= reserve_count then return end

    local behavior = get_behavior_from_id(id_bhvBowserBomb)
    local active_bombs = count_objects_with_behavior(behavior)
    if (gGlobalSyncTable.sh5_boss_original_bombs_seen or 0) == 0 then
        -- A zero during the level-loading frames is not an exhausted arena.
        -- Arm the reserve only after this host has observed the native set.
        if active_bombs >= #Team.bossBombPositions then
            gGlobalSyncTable.sh5_boss_original_bombs_seen = 1
            Team.bossBombZeroSince = nil
        end
        return
    end
    if active_bombs > 0 then
        Team.bossBombZeroSince = nil
        return
    end

    -- Require one continuous second at zero. Besides filtering the native
    -- explosion transition, this gives a newly promoted host time to receive
    -- synchronized objects before it decides that the arena is empty.
    if Team.bossBombZeroSince == nil then
        Team.bossBombZeroSince = get_global_timer()
        return
    end
    if get_global_timer() - Team.bossBombZeroSince < FRAMES_PER_SECOND then return end

    local available = {}
    for index = 1, #Team.bossBombPositions do available[index] = index end
    local spawned = 0
    for _ = 1, reserve_count - already_spawned do
        local choice = math.random(#available)
        local position = Team.bossBombPositions[available[choice]]
        table.remove(available, choice)
        local bomb = spawn_sync_object(
            id_bhvBowserBomb, E_MODEL_BOWSER_BOMB,
            position.x, position.y, position.z,
            function(object)
                object.oHomeX = position.x
                object.oHomeY = position.y
                object.oHomeZ = position.z
            end)
        if bomb ~= nil then spawned = spawned + 1 end
    end
    -- spawn_sync_object is synchronous. Publish only completed creations; if
    -- one fails, the host may supply only the missing amount after the arena
    -- is empty again instead of duplicating the successful objects.
    gGlobalSyncTable.sh5_boss_extra_bombs_spawned = already_spawned + spawned
    Team.bossBombZeroSince = nil
end

-- Bowser uses dynamic object ownership. Only the client that currently owns
-- the synchronized object may initialize his five health points; otherwise a
-- later full-object packet can silently restore the vanilla value.
local function ensure_boss_health_owner()
    if not is_round_active() or not is_boss_mode()
        or gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then
        local_boss_health_object = nil
        local_boss_health_initialized = false
        local_boss_health_last_value = nil
        local_boss_health_report_at = 0
        return
    end

    local bowser = obj_get_first_with_behavior_id(id_bhvBowser)
    if bowser ~= local_boss_health_object then
        local_boss_health_object = bowser
        local_boss_health_initialized = false
        local_boss_health_last_value = nil
    end
    if bowser == nil then return end

    local round = gGlobalSyncTable.sh5_round or 0
    local health_was_initialized = false
    for i = 0, MAX_PLAYERS - 1 do
        if (gPlayerSyncTable[i].sh5_boss_health_ready_round or 0) == round then
            health_was_initialized = true
            break
        end
    end

    local sync_id = bowser.oSyncID
    if sync_id == nil or sync_id == 0 or not sync_object_is_owned_locally(sync_id) then return end

    if not local_boss_health_initialized then
        local authoritative = clamp(gGlobalSyncTable.sh5_boss_health or Team.boss_max_health(), 0, Team.boss_max_health())
        if health_was_initialized then
            -- Never increase a synchronized object's already lower value.
            bowser.oHealth = math.min(clamp(bowser.oHealth or authoritative, 0, Team.boss_max_health()), authoritative)
        else
            bowser.oHealth = Team.boss_max_health()
        end
        network_send_object(bowser, true)
        gPlayerSyncTable[0].sh5_boss_health_ready_round = round
        local_boss_health_initialized = true
    end

    -- The current owner publishes the authoritative remaining health. If
    -- ownership or the object changes, the next owner restores this value
    -- instead of healing Bowser or reverting him to vanilla health.
    if bowser.oHealth ~= local_boss_health_last_value
        or get_global_timer() >= local_boss_health_report_at then
        local_boss_health_last_value = bowser.oHealth
        local_boss_health_report_at = get_global_timer() + 5
        gPlayerSyncTable[0].sh5_boss_health_ready_round = round
        gPlayerSyncTable[0].sh5_boss_health_value = clamp(bowser.oHealth, 0, Team.boss_max_health())
        gPlayerSyncTable[0].sh5_boss_health_tick = get_global_timer()
    end
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

Team.host_update_chaos_round = function()
    Team.host_reroll_chaos_modifiers()
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

local function local_goal_warp_update(m)
    if m.playerIndex ~= 0 then return end
    if is_boss_mode() or Team.is_chaos_mode() then return end

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

local function spawn_violet_split_fire(bowser)
    if bowser == nil then return end
    local function spawn_flame(model, yaw, scale, speed)
        spawn_non_sync_object(id_bhvFlameMovingForwardGrowing, model,
            bowser.oPosX, bowser.oPosY + 180, bowser.oPosZ, function(flame)
                flame.oMoveAngleYaw = yaw
                flame.oFaceAngleYaw = yaw
                flame.oForwardVel = speed
                flame.oVelY = 8
                flame.oDamageOrCoinValue = 4
                obj_scale(flame, scale)
            end)
    end

    -- Red and blue overlap for the violet-looking core. Three branches keep
    -- the attack readable without flooding every client with short-lived
    -- objects.
    spawn_flame(E_MODEL_RED_FLAME, 0, 2.2, 0)
    spawn_flame(E_MODEL_BLUE_FLAME, 0, 1.9, 0)
    for branch = 0, 2 do
        local base = branch * 0x5555
        spawn_flame(E_MODEL_BLUE_FLAME, base, 1.15, 34)
    end
end

local function spawn_boss_flame(bowser, model, yaw, scale, speed)
    if bowser == nil then return end
    spawn_non_sync_object(id_bhvFlameMovingForwardGrowing, model,
        bowser.oPosX, bowser.oPosY + 160, bowser.oPosZ, function(flame)
            flame.oMoveAngleYaw = yaw
            flame.oFaceAngleYaw = yaw
            flame.oForwardVel = speed
            flame.oVelY = 5
            flame.oDamageOrCoinValue = 4
            obj_scale(flame, scale)
        end)
end

local function trigger_boss_wave(m, bowser, stun_frames)
    if bowser == nil then return end
    spawn_non_sync_object(id_bhvBowserShockWave, E_MODEL_BOWSER_WAVE,
        bowser.oPosX, bowser.oFloorHeight, bowser.oPosZ, nil)
    local distance = m.marioObj ~= nil and dist_between_objects(bowser, m.marioObj) or nil
    if distance ~= nil and distance < 4800 and is_local_player_on_floor(m) then
        local_runtime.boss_stun_frames = math.max(local_runtime.boss_stun_frames, stun_frames)
    end
end

local function resolve_meteor_rain(m, pending)
    for meteor = 0, 3 do
        local angle = pending.seed + meteor * (math.pi * 2 / 4)
        local x = pending.x + math.sin(angle) * 1250
        local z = pending.z + math.cos(angle) * 1250
        spawn_non_sync_object(id_bhvExplosion, E_MODEL_EXPLOSION, x, pending.y, z, nil)
        local dx, dz = m.pos.x - x, m.pos.z - z
        if dx * dx + dz * dz < 580 * 580 then m.health = 0 end
    end
end

local function execute_boss_attack(m, bowser, attack, attack_seq)
    if attack == 2 then
        trigger_boss_wave(m, bowser, 30)
    elseif attack == 3 then
        spawn_violet_split_fire(bowser)
    elseif attack == 5 then
        table.insert(local_runtime.pending_meteors, {
            at = get_global_timer() + 45,
            x = bowser.oPosX,
            y = bowser.oFloorHeight,
            z = bowser.oPosZ,
            seed = (attack_seq * 1.71) % (math.pi * 2),
        })
    elseif attack == 6 then
        for flame = 0, 7 do
            spawn_boss_flame(bowser, E_MODEL_BLUE_FLAME, flame * 0x2000, 0.9, 38)
        end
    elseif attack == 7 then
        -- The five real bombs in the final arena remain the only throwable
        -- bombs. This attack is a safe fire volley, not a spawned bomb.
        for flame = 0, 4 do
            spawn_boss_flame(bowser, E_MODEL_RED_FLAME, flame * 0x3333, 1.05, 45)
        end
    elseif attack == 8 then
        local angle = attack_seq * 1.37
        m.vel.x = m.vel.x + math.sin(angle) * 55
        m.vel.z = m.vel.z + math.cos(angle) * 55
        local_runtime.boss_stun_frames = math.max(local_runtime.boss_stun_frames, 12)
    elseif attack == 9 then
        -- A distortion wave replaces the old physical teleport. Moving a
        -- held or network-owned Bowser could make his tail impossible to grab.
        trigger_boss_wave(m, bowser, 16)
    elseif attack == 10 then
        trigger_boss_wave(m, bowser, 24)
        table.insert(local_runtime.pending_double_waves, get_global_timer() + 24)
    elseif attack == 11 and m.marioObj ~= nil then
        local yaw = atan2s(m.pos.x - bowser.oPosX, m.pos.z - bowser.oPosZ)
        spawn_boss_flame(bowser, E_MODEL_RED_FLAME, yaw, 1.25, 50)
        spawn_boss_flame(bowser, E_MODEL_BLUE_FLAME, yaw + 0x0800, 0.8, 44)
        spawn_boss_flame(bowser, E_MODEL_BLUE_FLAME, yaw - 0x0800, 0.8, 44)
    end
end

local function apply_boss_hazards(m)
    if m.playerIndex ~= 0 or not is_round_active() or not is_boss_mode() then return end
    local level = BOSS_LEVELS[gGlobalSyncTable.sh5_boss_level_index or 0]
    if level == nil or gNetworkPlayers[0].currLevelNum ~= level then return end

    if boss_has_modifier(1) then
        if m.hurtCounter > 0 and local_runtime.boss_damage_lock == 0 then
            local_runtime.boss_damage_lock = 1
            m.health = 0
        elseif m.hurtCounter == 0 then
            local_runtime.boss_damage_lock = 0
        end
    end

    if local_runtime.boss_stun_frames > 0 then
        local_runtime.boss_stun_frames = local_runtime.boss_stun_frames - 1
        if not local_runtime.config_open then
            m.controller.buttonDown = 0
            m.controller.buttonPressed = 0
            m.controller.stickX = 0
            m.controller.stickY = 0
            m.controller.rawStickX = 0
            m.controller.rawStickY = 0
            m.intendedMag = 0
            m.forwardVel = 0
        end
    end

    local bowser = obj_get_first_with_behavior_id(id_bhvBowser)
    -- A brief ownership transfer can temporarily remove Bowser locally. Keep
    -- queued attacks intact until the object returns instead of silently
    -- consuming them.
    if bowser == nil then return end
    -- During Bowser's intro, consume the current sequence without executing
    -- it. This also protects players who joined after an attack was sent.
    if bowser.oAction == 5 or bowser.oAction == 6 or bowser.oAction == 20 then
        local_runtime.boss_hazard_seq = gGlobalSyncTable.sh5_boss_attack_seq or 0
        local_runtime.pending_double_waves = {}
        local_runtime.pending_meteors = {}
        return
    end
    for index = #local_runtime.pending_double_waves, 1, -1 do
        if get_global_timer() >= local_runtime.pending_double_waves[index] then
            table.remove(local_runtime.pending_double_waves, index)
            trigger_boss_wave(m, bowser, 24)
        end
    end
    for index = #local_runtime.pending_meteors, 1, -1 do
        local meteor = local_runtime.pending_meteors[index]
        if get_global_timer() >= meteor.at then
            table.remove(local_runtime.pending_meteors, index)
            resolve_meteor_rain(m, meteor)
        end
    end

    local attack_seq = gGlobalSyncTable.sh5_boss_attack_seq or 0
    if attack_seq == local_runtime.boss_hazard_seq then return end
    -- Global sync updates can coalesce during lag. Replay every attack still
    -- present in the ring instead of applying only the newest sequence.
    local first_seq = math.max(local_runtime.boss_hazard_seq + 1, attack_seq - BOSS_ATTACK_QUEUE_SIZE + 1)
    for sequence = first_seq, attack_seq do
        local queue_slot = ((sequence - 1) % BOSS_ATTACK_QUEUE_SIZE) + 1
        local attack = gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(queue_slot)] or 0
        if sequence == attack_seq and attack == 0 then
            attack = gGlobalSyncTable.sh5_boss_attack_kind or 0
        end
        execute_boss_attack(m, bowser, attack, sequence)
    end
    local_runtime.boss_hazard_seq = attack_seq
end

-- Remove the camera Lakitu itself on the castle grounds.  This prevents the
-- scene instead of merely skipping it after the camera has already appeared.
local function remove_castle_lakitu(obj)
    local level = gNetworkPlayers[0].currLevelNum
    if level ~= LEVEL_CASTLE_GROUNDS then return end

    -- Lua exposes the stable behavior ID, not the C behavior-script symbols.
    -- Camera Lakitu covers both the opening cameraman and the intro sequence.
    if obj_has_behavior_id(obj, id_bhvCameraLakitu) ~= 0 then
        obj_mark_for_deletion(obj)
    end
end

-- HOOK_ON_OBJECT_LOAD does not run retroactively when StarHunt is enabled
-- after the grounds have already loaded. Scan briefly and repeatedly so the
-- pre-existing camera Lakitu is removed as well.
local function remove_existing_castle_lakitu()
    if gNetworkPlayers[0].currLevelNum ~= LEVEL_CASTLE_GROUNDS then return end
    if get_global_timer() < local_lakitu_scan_at then return end
    local_lakitu_scan_at = get_global_timer() + 15
    local object = obj_get_first_with_behavior_id(id_bhvCameraLakitu)
    if object ~= nil then obj_mark_for_deletion(object) end
end

local function on_find_water_level(_, _, water_level)
    -- set_water_level() already updates the two real moat/lake regions.
    -- Returning a fixed height here would create water under every coordinate
    -- on the castle grounds, including places outside those water boxes.
    return water_level
end

local function config_option_count()
    return network_is_server() and 6 or 2
end

local function config_option_kind(index)
    if network_is_server() then
        if index == 1 then return "language" end
        if index == 2 then return "mode" end
        if index == 3 then return "difficulty" end
        if index == 4 then return "time" end
        if index == 5 then return "status" end
        -- Keep the primary round action at the bottom of the full menu.
        return is_round_active() and "stop" or "start"
    end
    if index == 1 then return "language" end
    return "status"
end

local function config_status_text()
    if not is_round_active() then return translated("WAITING", "ESPERANDO") end
    local remaining = math.max(0, (gGlobalSyncTable.sh5_end_frame or 0) - get_global_timer())
    local minutes = math.floor(remaining / (60 * FRAMES_PER_SECOND))
    local seconds = math.floor((remaining / FRAMES_PER_SECOND) % 60)
    return translated("ACTIVE ", "ACTIVA ") .. string.format("%d:%02d", minutes, seconds)
end

Team.close_widdlepets_menu = function()
    local pets = rawget(_G, "wpets")
    if type(pets) == "table" and type(pets.is_menu_opened) == "function"
        and type(pets.close_menu) == "function" and pets.is_menu_opened() then
        pets.close_menu()
    end
end

Team.set_config_menu_open = function(opening)
    opening = opening and true or false
    local changed = local_runtime.config_open ~= opening
    if opening and changed then Team.close_widdlepets_menu() end
    local_runtime.config_open = opening
    if opening and changed then
        config_selection = clamp(config_selection, 1, config_option_count())
        config_button_latch = 0
        config_stick_latched = false
        local_runtime.menu_freeze_x = nil
        local_runtime.menu_freeze_y = nil
        local_runtime.menu_freeze_z = nil
    end
end

local function open_config_menu()
    if local_runtime.config_open and not is_round_active() then
        Team.close_widdlepets_menu()
        return
    end
    Team.set_config_menu_open(not local_runtime.config_open)
end

Team.update_config_menu_lock = function()
    local active = is_round_active()
    if local_runtime.config_round_was_active == nil then
        Team.set_config_menu_open(not active)
    elseif not active then
        Team.set_config_menu_open(true)
    elseif not local_runtime.config_round_was_active then
        Team.set_config_menu_open(false)
    end
    local_runtime.config_round_was_active = active
end

Team.cycle_mode = function(delta)
    local next_mode = (selected_mode() + delta) % 4
    if next_mode < 0 then next_mode = next_mode + 4 end
    gGlobalSyncTable.sh5_mode = next_mode
    local minimum, maximum = configured_time_range(connected_player_count())
    gGlobalSyncTable.sh5_config_minutes =
        clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)
end

Team.cycle_difficulty = function(delta)
    local next_difficulty = (Team.selected_difficulty() + delta) % 4
    if next_difficulty < 0 then next_difficulty = next_difficulty + 4 end
    gGlobalSyncTable.sh5_difficulty = next_difficulty
end

Team.freeze_menu_mario = function(m)
    if m.playerIndex ~= 0 then return end
    if not local_runtime.config_open then
        local_runtime.menu_freeze_x = nil
        local_runtime.menu_freeze_y = nil
        local_runtime.menu_freeze_z = nil
        return
    end
    if local_runtime.menu_freeze_x == nil then
        local_runtime.menu_freeze_x = m.pos.x
        local_runtime.menu_freeze_y = m.pos.y
        local_runtime.menu_freeze_z = m.pos.z
    end
    m.pos.x = local_runtime.menu_freeze_x
    m.pos.y = local_runtime.menu_freeze_y
    m.pos.z = local_runtime.menu_freeze_z
    m.vel.x, m.vel.y, m.vel.z = 0, 0, 0
    m.forwardVel = 0
    m.slideVelX = 0
    m.slideVelZ = 0
    m.intendedMag = 0
    m.controller.buttonPressed = 0
    m.controller.buttonDown = 0
    m.controller.stickX = 0
    m.controller.stickY = 0
    m.controller.rawStickX = 0
    m.controller.rawStickY = 0
    if m.marioObj ~= nil then
        m.marioObj.oPosX = m.pos.x
        m.marioObj.oPosY = m.pos.y
        m.marioObj.oPosZ = m.pos.z
    end
    if (m.action & ACT_FLAG_AIR) == 0 then set_mario_action(m, ACT_IDLE, 0) end
end

local function update_config_input(m)
    if m.playerIndex ~= 0 or not local_runtime.config_open then return end
    local held = m.controller.buttonDown
    local pressed = held & ~config_button_latch
    config_button_latch = held
    local count = config_option_count()
    local stick_x = m.controller.stickX
    local stick_y = m.controller.stickY

    if math.abs(stick_x) < 18 and math.abs(stick_y) < 18 then
        config_stick_latched = false
    end
    local stick_ready = not config_stick_latched
    local stick_up = stick_ready and stick_y > 24
    local stick_down = stick_ready and stick_y < -24
    local stick_left = stick_ready and stick_x < -24
    local stick_right = stick_ready and stick_x > 24
    if stick_up or stick_down or stick_left or stick_right then
        config_stick_latched = true
    end

    if (pressed & (B_BUTTON | START_BUTTON)) ~= 0 then
        if is_round_active() then Team.set_config_menu_open(false) end
    elseif (pressed & U_JPAD) ~= 0 or stick_up then
        config_selection = config_selection - 1
        if config_selection < 1 then config_selection = count end
    elseif (pressed & D_JPAD) ~= 0 or stick_down then
        config_selection = config_selection + 1
        if config_selection > count then config_selection = 1 end
    elseif (pressed & (L_JPAD | R_JPAD)) ~= 0 or stick_left or stick_right then
        local option = config_option_kind(config_selection)
        if option == "language" then
            local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
            Team.language = (Team.language + delta) % #Team.language_codes
            if Team.language < 0 then Team.language = Team.language + #Team.language_codes end
            mod_storage_save("starhunt_v11_language", tostring(Team.language))
        elseif option == "mode" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("MODE IS LOCKED DURING A ROUND", "EL MODO ESTA BLOQUEADO DURANTE LA RONDA"), 1)
            else
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                Team.cycle_mode(delta)
            end
        elseif option == "difficulty" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("DIFFICULTY IS LOCKED DURING A ROUND",
                    "LA DIFICULTAD ESTA BLOQUEADA DURANTE LA RONDA"), 1)
            else
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                Team.cycle_difficulty(delta)
            end
        elseif option == "time" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("TIME IS LOCKED DURING A ROUND", "EL TIEMPO ESTA BLOQUEADO DURANTE LA RONDA"), 1)
            else
                local minimum, maximum = configured_time_range(connected_player_count())
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                local current = clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)
                gGlobalSyncTable.sh5_config_minutes = clamp(current + delta, minimum, maximum)
            end
        end
    elseif (pressed & A_BUTTON) ~= 0 then
        local option = config_option_kind(config_selection)
        if option == "start" then
            local minimum, maximum = configured_time_range(connected_player_count())
            if host_start_round(clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)) then
                Team.set_config_menu_open(false)
            end
        elseif option == "stop" then
            host_end_round("stopped by host")
            Team.set_config_menu_open(true)
        elseif option == "language" then
            Team.language = (Team.language + 1) % #Team.language_codes
            mod_storage_save("starhunt_v11_language", tostring(Team.language))
        elseif option == "mode" and network_is_server() then
            if not is_round_active() then
                Team.cycle_mode(1)
            end
        elseif option == "difficulty" and network_is_server() then
            if not is_round_active() then Team.cycle_difficulty(1) end
        elseif option == "status" then
            djui_popup_create(config_status_text(), 1)
        end
    end

    -- The menu owns all movement. The analog stick navigates it and is then
    -- neutralized before Mario's movement logic can see it.
    m.controller.buttonPressed = 0
    m.controller.buttonDown = 0
    m.controller.stickX = 0
    m.controller.stickY = 0
    m.controller.rawStickX = 0
    m.controller.rawStickY = 0
    m.intendedMag = 0
    m.forwardVel = 0
    m.slideVelX = 0
    m.slideVelZ = 0
    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    if (m.action & ACT_FLAG_AIR) == 0 then set_mario_action(m, ACT_IDLE, 0) end
    if local_runtime.config_open then Team.freeze_menu_mario(m) end
end

local function format_remaining_time(frames)
    local minutes = math.floor(frames / (60 * FRAMES_PER_SECOND))
    local seconds = math.floor((frames / FRAMES_PER_SECOND) % 60)
    return string.format("%d:%02d", minutes, seconds)
end

local function measure_hud_text(text)
    local width = 0
    local start_at = 1
    while true do
        local colon_at = string.find(text, ":", start_at, true)
        local chunk = colon_at ~= nil and string.sub(text, start_at, colon_at - 1)
            or string.sub(text, start_at)
        width = width + djui_hud_measure_text(chunk)
        if colon_at == nil then break end
        width = width + 5
        start_at = colon_at + 1
    end
    return width
end

local function draw_hud_text(text, x, y, scale, r, g, b, alpha)
    alpha = alpha or 255
    local function draw_layer(offset_x, offset_y, red, green, blue, alpha)
        local cursor = x + offset_x
        local start_at = 1
        djui_hud_set_color(red, green, blue, alpha)
        while true do
            local colon_at = string.find(text, ":", start_at, true)
            local chunk = colon_at ~= nil and string.sub(text, start_at, colon_at - 1)
                or string.sub(text, start_at)
            if chunk ~= "" then djui_hud_print_text(chunk, cursor, y + offset_y, scale) end
            cursor = cursor + djui_hud_measure_text(chunk) * scale
            if colon_at == nil then break end
            -- FONT_HUD maps ':' to an X. Draw a compact colon from two dots.
            djui_hud_print_text(".", cursor + scale, y + offset_y - 4 * scale, scale * 0.64)
            djui_hud_print_text(".", cursor + scale, y + offset_y + 6 * scale, scale * 0.64)
            cursor = cursor + 5 * scale
            start_at = colon_at + 1
        end
    end
    draw_layer(1, 1, 0, 0, 0, math.floor(220 * alpha / 255))
    draw_layer(0, 0, r, g, b, alpha)
end

local function draw_centered_hud_text(text, y, scale, r, g, b)
    local x = (djui_hud_get_screen_width() - measure_hud_text(text) * scale) * 0.5
    draw_hud_text(text, x, y, scale, r, g, b)
end

Team.objective_text_max_width = function()
    local width = djui_hud_get_screen_width()
    local center = width * 0.5
    -- Keep the centered objective between the left score/health card and the
    -- right timer card. Widescreen gains space naturally without turning the
    -- objective into a screen-wide banner.
    local left_guard = (Team.is_mode() or is_boss_mode()) and 119 or 90
    local right_guard = width - 112
    return math.max(24, 2 * math.min(center - left_guard, right_guard - center))
end

Team.draw_scaled_centered_text = function(text, y, desired_scale, maximum_width, r, g, b)
    local text_width = measure_hud_text(text)
    local scale = desired_scale
    if text_width > 0 and text_width * scale > maximum_width then
        scale = maximum_width / text_width
    end
    draw_centered_hud_text(text, y, scale, r, g, b)
end

local function apply_counter_visibility()
    local flags = hud_get_value(HUD_DISPLAY_FLAGS)
    if is_round_active() then
        if not local_counter_round_active then
            local_hud_flags_before_round = flags
            local_counter_round_active = true
        end
        flags = flags & ~HUD_DISPLAY_FLAG_STAR_COUNT
        if HUD_DISPLAY_FLAG_COIN_COUNT ~= nil then
            flags = flags & ~HUD_DISPLAY_FLAG_COIN_COUNT
        end
        hud_set_value(HUD_DISPLAY_FLAGS, flags)
    elseif local_counter_round_active then
        local restore_mask = HUD_DISPLAY_FLAG_STAR_COUNT
        if HUD_DISPLAY_FLAG_COIN_COUNT ~= nil then
            restore_mask = restore_mask | HUD_DISPLAY_FLAG_COIN_COUNT
        end
        local saved = local_hud_flags_before_round or flags
        flags = (flags & ~restore_mask) | (saved & restore_mask)
        hud_set_value(HUD_DISPLAY_FLAGS, flags)
        local_counter_round_active = false
        local_hud_flags_before_round = nil
    end
end

-- Entering a course recreates the game's built-in HUD, including its own
-- star/coin counter.  Hide the native HUD itself while a round is active and
-- render only StarHunt's custom HUD below.
local native_hud_hidden = false
local function update_native_hud_visibility()
    if is_round_active() then
        if local_runtime.native_hud_was_hidden == nil then
            local_runtime.native_hud_was_hidden = hud_is_hidden()
        end
        hud_hide()
        native_hud_hidden = true
    elseif native_hud_hidden then
        if local_runtime.native_hud_was_hidden then hud_hide() else hud_show() end
        native_hud_hidden = false
        local_runtime.native_hud_was_hidden = nil
    end
end

-- DARKNESS PULSE belongs behind every HUD. Drawing it from the regular HUD
-- hook covered clocks, chat and weapon information from compatible mods.
Team.draw_darkness_behind = function()
    if not is_round_active()
        or not Team.darkness_active(Team.local_modifier_of_kind("darkness_pulse")) then return false end
    local frame = get_global_timer()
    if local_runtime.darkness_draw_frame == frame then return true end
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_color(0, 0, 0, 248)
    djui_hud_render_rect(0, 0, djui_hud_get_screen_width(), djui_hud_get_screen_height())
    local_runtime.darkness_draw_frame = frame
    return true
end

local function hide_native_hud_before_render()
    Team.draw_darkness_behind()
    if is_round_active() then hud_hide() end
end

local function draw_start_banner()
    if get_global_timer() > local_start_banner_until then return end
    local text, scale = translated("START!", "EMPIEZA!"), 2.4
    local y = math.floor(djui_hud_get_screen_height() * 0.62)
    local x = (djui_hud_get_screen_width() - djui_hud_measure_text(text) * scale) * 0.5
    djui_hud_set_color(0, 0, 0, 230)
    djui_hud_print_text(text, x + 3, y + 3, scale)
    djui_hud_set_color(214, 42, 31, 255)
    djui_hud_print_text(text, x - 1, y - 1, scale)
    djui_hud_set_color(255, 222, 60, 255)
    djui_hud_print_text(text, x, y, scale)
end

local function draw_config_menu()
    if not local_runtime.config_open then return end
    local width = djui_hud_get_screen_width()
    local height = djui_hud_get_screen_height()
    local box_w, box_h = 270, network_is_server() and 192 or 108
    local x = (width - box_w) * 0.5
    local y = (height - box_h) * 0.5
    local minimum, maximum = configured_time_range(connected_player_count())

    djui_hud_set_color(0, 0, 0, 180)
    djui_hud_render_rect(0, 0, width, height)
    djui_hud_set_color(16, 36, 92, 245)
    djui_hud_render_rect(x, y, box_w, box_h)
    djui_hud_set_color(255, 215, 73, 255)
    djui_hud_render_rect(x, y, box_w, 3)

    draw_centered_hud_text("STARHUNT", y + 10, 0.82, 255, 215, 73)
    local language_value = Team.language_names[Team.language + 1] or "ENGLISH"
    local line_y = y + 34

    for index = 1, config_option_count() do
        local option = config_option_kind(index)
        local text
        if option == "start" then
            text = translated("START ROUND", "INICIAR RONDA")
        elseif option == "stop" then
            text = translated("STOP ROUND", "DETENER RONDA")
        elseif option == "language" then
            text = translated("LANGUAGE", "IDIOMA") .. " - " .. language_value
        elseif option == "mode" then
            local mode_value
            if selected_mode() == Team.BOSS then
                mode_value = translated("BOSS", "JEFE")
            elseif selected_mode() == Team.MODE then
                mode_value = translated("TEAM", "EQUIPOS")
            elseif selected_mode() == Team.CHAOS then
                mode_value = translated("CHAOS", "CAOS")
            else
                mode_value = "NORMAL"
            end
            if (selected_mode() == Team.MODE or selected_mode() == Team.CHAOS)
                and connected_player_count() < 2 then
                mode_value = mode_value .. " - " .. translated("NEEDS 2 PLAYERS", "NECESITA 2 JUGADORES")
            end
            text = translated("GAME MODE", "MODO DE JUEGO") .. " - " .. mode_value
            if is_round_active() then text = text .. " " .. translated("(LOCKED)", "(BLOQUEADO)") end
        elseif option == "difficulty" then
            local names = {
                translated("EASY", "FACIL"), translated("NORMAL", "NORMAL"),
                translated("HARD", "DIFICIL"), translated("NIGHTMARE", "PESADILLA"),
            }
            local difficulty_value = names[Team.selected_difficulty() + 1]
            if is_round_active() then difficulty_value = difficulty_value .. " " .. translated("(LOCKED)", "(BLOQUEADO)") end
            text = translated("DIFFICULTY", "DIFICULTAD") .. " - " .. difficulty_value
        elseif option == "time" then
            local minutes = clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)
            local time_value = tostring(minutes) .. " " .. translated("MIN", "MIN")
            if is_round_active() then time_value = translated("LOCKED", "BLOQUEADO") end
            text = translated("TIME", "TIEMPO") .. " - " .. time_value
        else
            text = translated("STATUS", "ESTADO") .. " - " .. config_status_text()
        end

        if config_selection == index then
            djui_hud_set_color(255, 255, 255, 45)
            djui_hud_render_rect(x + 10, line_y - 2, box_w - 20, 16)
        end
        local disabled = (selected_mode() == Team.MODE or selected_mode() == Team.CHAOS)
            and connected_player_count() < 2
            and (option == "mode" or option == "start")
        draw_hud_text((config_selection == index and "> " or "  ") .. text,
            x + 16, line_y, 0.62, 255, 255, 255, disabled and 105 or 255)
        line_y = line_y + 21
    end

    local controls
    if not is_round_active() then
        controls = Team.menu_lock_labels[Team.language + 1] or Team.menu_lock_labels[1]
    else
        controls = translated("UP/DOWN SELECT  A USE  LEFT/RIGHT CHANGE  B CLOSE",
            "ARRIBA/ABAJO ELEGIR  A USAR  IZQ/DER CAMBIAR  B CERRAR")
    end
    draw_centered_hud_text(controls, y + box_h - 16, 0.32, 160, 210, 255)
    if network_is_server() and not is_round_active() then
        draw_centered_hud_text(tostring(minimum) .. "-" .. tostring(maximum) .. " " .. translated("MINUTES", "MINUTOS"),
            y + box_h - 29, 0.38, 190, 190, 190)
    end
end

Team.draw_hud_panel = function(x, y, width, height, r, g, b)
    djui_hud_set_color(5, 11, 24, 205)
    djui_hud_render_rect(x, y, width, height)
    djui_hud_set_color(r, g, b, 235)
    djui_hud_render_rect(x, y, 3, height)
    djui_hud_set_color(255, 255, 255, 28)
    djui_hud_render_rect(x + 3, y, width - 3, 1)
end

Team.health_wedges = function(health)
    return clamp(math.floor(clamp(health or 0x880, 0, 0x880) / 0x100), 0, 8)
end

Team.health_color = function(wedges)
    if wedges >= 6 then return 74, 218, 128 end
    if wedges >= 3 then return 255, 190, 54 end
    return 255, 76, 82
end

local function draw_player_health_bar(y)
    local mario = gMarioStates[0]
    if mario == nil then return end
    local wedges = Team.health_wedges(mario.health)
    local r, g, b = Team.health_color(wedges)
    local x = 10
    y = y or 42
    Team.draw_hud_panel(x, y, 101, 19, r, g, b)
    draw_hud_text(translated("HP", "VIDA"), x + 7, y + 5, 0.38, r, g, b)

    local segment_x = x + 29
    for slot = 1, 8 do
        local sx = segment_x + (slot - 1) * 8
        djui_hud_set_color(33, 43, 61, 255)
        djui_hud_render_rect(sx, y + 5, 6, 10)
        if slot <= wedges then
            djui_hud_set_color(r, g, b, 255)
            djui_hud_render_rect(sx, y + 5, 6, 10)
            djui_hud_set_color(255, 255, 255, 70)
            djui_hud_render_rect(sx, y + 5, 6, 1)
        end
    end
end

Team.draw_round_status_panels = function(remaining, score)
    local width = djui_hud_get_screen_width()
    local health_y = 42

    if Team.is_mode() then
        local local_team = gPlayerSyncTable[0].sh5_team or Team.NONE
        Team.draw_hud_panel(10, 8, 101, 38,
            local_team == Team.BLUE and 64 or 232,
            local_team == Team.BLUE and 132 or 68,
            local_team == Team.BLUE and 255 or 72)
        draw_hud_text((local_team == Team.RED and "> " or "  ")
                .. "RED  x " .. tostring(gGlobalSyncTable.sh5_red_score or 0),
            17, 14, 0.48, 255, 78, 78)
        draw_hud_text((local_team == Team.BLUE and "> " or "  ")
                .. "BLUE x " .. tostring(gGlobalSyncTable.sh5_blue_score or 0),
            17, 28, 0.48, 92, 154, 255)
        health_y = 51
    elseif Team.is_chaos_mode() then
        Team.draw_hud_panel(10, 8, 101, 29, 196, 78, 255)
        draw_hud_text(translated("ALIVE ", "VIVOS ")
                .. tostring(gGlobalSyncTable.sh5_chaos_alive or 0),
            17, 15, 0.58, 235, 165, 255)
    elseif is_boss_mode() then
        local boss_health = clamp(gGlobalSyncTable.sh5_boss_health or Team.boss_max_health(), 0, Team.boss_max_health())
        Team.draw_hud_panel(10, 8, 101, 29, 236, 66, 82)
        draw_hud_text("BOWSER", 17, 13, 0.42, 255, 112, 94)
        for slot = 1, Team.boss_max_health() do
            local sx = 61 + (slot - 1) * 9
            djui_hud_set_color(48, 38, 49, 255)
            djui_hud_render_rect(sx, 14, 7, 12)
            if slot <= boss_health then
                djui_hud_set_color(238, 67, 82, 255)
                djui_hud_render_rect(sx, 14, 7, 12)
                djui_hud_set_color(255, 220, 190, 80)
                djui_hud_render_rect(sx, 14, 7, 1)
            end
        end
    else
        Team.draw_hud_panel(10, 8, 72, 29, 255, 210, 72)
        if gTextures.star ~= nil then
            djui_hud_set_color(255, 255, 255, 255)
            djui_hud_render_texture(gTextures.star, 18, 14, 0.72, 0.72)
        end
        draw_hud_text("x " .. tostring(score), 38, 15, 0.64, 255, 255, 255)
    end

    local timer_x = width - 104
    Team.draw_hud_panel(timer_x, 8, 94, 43, 255, 210, 72)
    draw_hud_text(translated("TIME ", "TIEMPO ") .. format_remaining_time(remaining),
        timer_x + 8, 14, 0.48, 255, 220, 96)
    local coins = hud_get_value(HUD_DISPLAY_COINS) or 0
    if gTextures.coin ~= nil then
        djui_hud_set_color(255, 255, 255, 255)
        djui_hud_render_texture(gTextures.coin, timer_x + 9, 30, 0.65, 0.65)
    end
    draw_hud_text("x " .. tostring(coins), timer_x + 24, 32, 0.52, 255, 238, 156)
    draw_player_health_bar(health_y)
end

Team.draw_objective_panel = function(goal, modifier_data, modifier_data_2)
    local maximum_width = Team.objective_text_max_width()

    if is_boss_mode() then
        Team.draw_scaled_centered_text(
            translated("BOWSER MODIFIERS", "MODIFICADORES DE BOWSER"),
            3, 0.30, maximum_width, 200, 210, 230)
        local colors = {
            { 255, 145, 80 },
            { 220, 95, 255 },
            { 255, 220, 75 },
        }
        for slot = 1, #BOSS_MODIFIER_FIELDS do
            local color = colors[slot]
            Team.draw_scaled_centered_text(boss_modifier_text(slot),
                14 + (slot - 1) * 11,
                0.38, maximum_width, color[1], color[2], color[3])
        end
        if modifier_data ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data),
                48, 0.38, maximum_width, 104, 218, 255)
        end
        if modifier_data_2 ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data_2),
                59, 0.36, maximum_width, 255, 145, 80)
        end
        return
    end

    if Team.is_chaos_mode() then
        Team.draw_scaled_centered_text(
            translated("LAST PLAYER STANDING", "ULTIMO JUGADOR EN PIE"),
            3, 0.64, maximum_width, 255, 255, 255)
        if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1 then
            Team.draw_scaled_centered_text(
                translated("ELIMINATED - SPECTATING", "ELIMINADO - OBSERVANDO"),
                17, 0.50, maximum_width, 255, 100, 110)
            return
        end
        if modifier_data ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data),
                17, 0.52, maximum_width, 255, 215, 73)
        end
        if modifier_data_2 ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data_2),
                29, 0.48, maximum_width, 255, 145, 80)
        end
        local reroll = math.max(0,
            (gGlobalSyncTable.sh5_chaos_next_reroll or 0) - get_global_timer())
        Team.draw_scaled_centered_text(
            translated("NEW MODIFIERS IN: ", "NUEVOS MODIFICADORES EN: ")
                .. tostring(math.ceil(reroll / FRAMES_PER_SECOND)),
            41, 0.40, maximum_width, 200, 210, 230)
        return
    end

    if goal ~= nil and modifier_data ~= nil then
        Team.draw_scaled_centered_text(goal_world_text(goal),
            3, 0.56, maximum_width, 104, 218, 255)
        Team.draw_scaled_centered_text(goal_title_text(goal),
            15, 0.70, maximum_width, 255, 255, 255)
        Team.draw_scaled_centered_text(modifier_text(modifier_data),
            28, 0.55, maximum_width, 255, 215, 73)
        local counter_y = 40
        if modifier_data_2 ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data_2),
                39, 0.50, maximum_width, 255, 145, 80)
            counter_y = 50
        end
        local jump_data = modifier_data.kind == "jump_limit" and modifier_data
            or (modifier_data_2 ~= nil and modifier_data_2.kind == "jump_limit" and modifier_data_2 or nil)
        local toll_data = modifier_data.kind == "coin_toll" and modifier_data
            or (modifier_data_2 ~= nil and modifier_data_2.kind == "coin_toll" and modifier_data_2 or nil)
        if jump_data ~= nil then
            local left = gPlayerSyncTable[0].sh5_jump_count
            if left == nil then left = jump_data.value end
            Team.draw_scaled_centered_text(
                translated("JUMPS: ", "SALTOS: ") .. tostring(left),
                counter_y, 0.48, maximum_width, 255, 145, 80)
        elseif toll_data ~= nil then
            Team.draw_scaled_centered_text(
                translated("COINS: ", "MONEDAS: ")
                .. tostring(math.min(toll_data.value, Team.coin_count(gMarioStates[0])))
                .. "/" .. tostring(toll_data.value),
                counter_y, 0.48, maximum_width, 255, 145, 80)
        end
    else
        Team.draw_scaled_centered_text(
            translated("CHOOSING YOUR NEXT GOAL...", "ELIGIENDO TU PROXIMO RETO..."),
            15, 0.66, maximum_width, 255, 255, 255)
    end
end

-- Gun Mod normally renders in the same behind-HUD layer as the darkness
-- rectangle. Repeat its compact public-API HUD above the pulse so ammo and
-- crosshair remain usable. Outside a pulse StarHunt leaves Gun Mod untouched.
Team.draw_gun_mod_hud_compatibility = function()
    if local_runtime.darkness_draw_frame ~= get_global_timer() then return end
    local api = rawget(_G, "gunModApi")
    if type(api) ~= "table" or type(api.cur_weapon) ~= "function"
        or type(api.cur_dual_wield_weapon) ~= "function"
        or type(api.get_render_hud) ~= "function"
        or not api.get_render_hud() or not gGlobalSyncTable.gunModEnabled then
        return
    end
    local network = gNetworkPlayers[0]
    local act_selector = rawget(_G, "id_bhvActSelector")
    if network == nil or network.currActNum == 99
        or (act_selector ~= nil and obj_get_first_with_behavior_id(act_selector) ~= nil) then
        return
    end
    local weapon = api.cur_weapon()
    if weapon == nil then return end

    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_HUD)
    local width = djui_hud_get_screen_width()
    local height = djui_hud_get_screen_height()
    local first_person = rawget(_G, "get_first_person_enabled")
    local paused = rawget(_G, "is_game_paused")
    local crosshair = rawget(_G, "TEX_CROSSHAIR")
    if type(first_person) == "function" and first_person() and crosshair ~= nil
        and (type(paused) ~= "function" or not paused()) then
        djui_hud_set_color(255, 255, 0, 127)
        djui_hud_render_texture(crosshair, width * 0.5 - 4, height * 0.5 - 4, 0.5, 0.5)
    end

    local y = height - 35
    djui_hud_set_color(255, 255, 255, 255)
    if weapon.maxAmmo ~= nil and weapon.maxAmmo ~= 0 then
        djui_hud_print_text(tostring(weapon.ammo or 0) .. "/" .. tostring(weapon.maxAmmo),
            width - 128, y, 1)
    end
    local second = api.cur_dual_wield_weapon()
    if second ~= nil and second.maxAmmo ~= nil and second.maxAmmo ~= 0 then
        djui_hud_print_text(tostring(second.ammo or 0) .. "/" .. tostring(second.maxAmmo), 16, y, 1)
    end
end

local function draw_hud()
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_HUD)

    apply_counter_visibility()
    if not is_round_active() then
        draw_config_menu()
        return
    end
    local goal = get_local_goal()
    local modifiers = Team.get_local_modifiers()
    local modifier_data = modifiers[1]
    local remaining = math.max(0, (gGlobalSyncTable.sh5_end_frame or get_global_timer()) - get_global_timer())
    local score = gPlayerSyncTable[0].sh5_score or 0
    Team.draw_gun_mod_hud_compatibility()
    Team.draw_round_status_panels(remaining, score)
    Team.draw_objective_panel(goal, modifier_data, modifiers[2])
    draw_start_banner()
    draw_config_menu()
end

local function local_round_notifications()
    local round = gGlobalSyncTable.sh5_round or 0
    if local_seen_round == nil then
        local_seen_round = round
    elseif round ~= local_seen_round then
        local_seen_round = round
        local_start_banner_until = get_global_timer() + START_BANNER_FRAMES
    end

    local result = gGlobalSyncTable.sh5_result_seq or 0
    if local_seen_result == nil then
        local_seen_result = result
    elseif result ~= local_seen_result then
        local_seen_result = result
        local winner = gGlobalSyncTable.sh5_result_winner or "Nobody"
        local score = gGlobalSyncTable.sh5_result_score or 0
        local winner_message
        local result_mode = gGlobalSyncTable.sh5_result_mode or Team.NORMAL
        if result_mode == Team.BOSS then
            local reason = gGlobalSyncTable.sh5_result_reason or ""
            if reason == "boss defeated" then
                winner_message = translated("BOWSER DEFEATED! TEAM STARHUNT WINS!", "BOWSER DERROTADO! EL EQUIPO STARHUNT GANA!")
            elseif reason == "stopped by host" then
                winner_message = translated("BOSS ROUND STOPPED BY THE HOST.", "RONDA BOSS DETENIDA POR EL HOST.")
            else
                winner_message = translated("TIME UP! BOWSER WINS!", "TIEMPO AGOTADO! BOWSER GANA!")
            end
        elseif result_mode == Team.MODE then
            local red_score = gGlobalSyncTable.sh5_result_red_score or 0
            local blue_score = gGlobalSyncTable.sh5_result_blue_score or 0
            if winner == "RED TEAM" then
                winner_message = translated("RED TEAM WINS! ", "GANA EL EQUIPO ROJO! ")
            elseif winner == "BLUE TEAM" then
                winner_message = translated("BLUE TEAM WINS! ", "GANA EL EQUIPO AZUL! ")
            else
                winner_message = translated("TEAM TIE! ", "EMPATE DE EQUIPOS! ")
            end
            winner_message = winner_message .. "RED " .. tostring(red_score)
                .. " - BLUE " .. tostring(blue_score)
        elseif result_mode == Team.CHAOS then
            if (gGlobalSyncTable.sh5_result_reason or "") == "chaos last standing" then
                winner_message = translated("CHAOS WINNER: ", "GANADOR DE CAOS: ") .. winner
            else
                winner_message = translated("CHAOS ENDED WITHOUT A WINNER.",
                    "CAOS TERMINO SIN GANADOR.")
            end
        else
            winner_message = translated("STARHUNT WINNER: ", "GANADOR DE STARHUNT: ")
                .. winner .. " - " .. tostring(score) .. translated(" STAR(S)!", " ESTRELLA(S)!")
        end
        djui_chat_message_create(winner_message)
        djui_popup_create(winner_message, 2)
    end
end

local function on_joined_game()
    Team.update_config_menu_lock()
    if is_round_active() then
        if Team.is_chaos_mode() then
            djui_popup_create(translated("CHAOS IS ACTIVE: YOU WILL SPECTATE.",
                "CAOS ESTA ACTIVO: SERAS ESPECTADOR."), 1)
        else
            djui_popup_create(translated("STARHUNT IS ACTIVE: A GOAL WILL BE ASSIGNED.",
                "STARHUNT ESTA ACTIVO: RECIBIRAS UN RETO."), 1)
        end
    end
end

local function show_help()
    djui_chat_message_create("/starhunt - " .. translated("open the StarHunt menu", "abre el menu de StarHunt"))
    djui_chat_message_create("/starhunt updates - "
        .. translated("show what StarHunt is and what changed", "muestra de que trata StarHunt y que cambio"))
end

Team.show_updates = function()
    djui_chat_message_create("\\#FFE05A\\STAR\\#58D6FF\\HUNT \\#FFFFFF\\v1.1")
    djui_chat_message_create(translated(
        "ABOUT: A multiplayer challenge mod with four game modes.",
        "DE QUE TRATA: Un mod multijugador de desafios con cuatro modos."))
    djui_chat_message_create(translated(
        "MODES: Normal star race, team competition, cooperative Boss and last-player-standing Chaos.",
        "MODOS: Carrera Normal, competencia por equipos, Boss cooperativo y Chaos de ultimo jugador vivo."))
    djui_chat_message_create(translated(
        "DIFFICULTY: Easy, Normal, Hard or Nightmare applies independently to every mode.",
        "DIFICULTAD: Facil, Normal, Dificil o Pesadilla se aplica independientemente a cada modo."))
    djui_chat_message_create(translated(
        "V1.1: Personal Chaos modifiers, Nightmare extras and an in-game Another Level button with a two-minute cooldown.",
        "V1.1: Modificadores personales en Chaos, extras en Pesadilla y boton Otro nivel dentro del juego con espera de dos minutos."))
end

local function starhunt_command(message)
    local text = string.lower(message or ""):match("^%s*(.-)%s*$")
    if text == "" then
        open_config_menu()
        return true
    end
    if text == "updates" or text == "update" or text == "actualizaciones"
        or text == "cambios" then
        Team.show_updates()
        return true
    end
    show_help()
    return true
end

-- The engine never sets this flag. The standalone test harness uses named
-- references so adding or reordering hooks cannot silently test the wrong
-- function.
if rawget(_G, "STARHUNT_TEST_MODE") then
    STARHUNT_TEST_API = {
        goals = GOALS,
        runtime = local_runtime,
        translated = translated,
        language_codes = Team.language_codes,
        language_names = Team.language_names,
        ui_translations = Team.ui_translations,
        modifier_translations = Team.modifier_translations,
        boss_modifier_translations = Team.boss_modifier_translations,
        menu_lock_labels = Team.menu_lock_labels,
        normal_modifier_catalog = NORMAL_MODIFIER_CATALOG,
        -- The audit matrix and its tallies are published for the self-check
        -- suite alone: it is the only test that needs to damage them on
        -- purpose to see whether run_static_modifier_checks notices.
        modifier_audit = audit.MODIFIER_AUDIT,
        modifier_audit_counts = audit.MODIFIER_AUDIT_COUNTS,
        boss_player_modifiers = BOSS_PLAYER_MODIFIERS,
        boss_modifiers = BOSS_MODIFIERS,
        boss_attack_queue_size = BOSS_ATTACK_QUEUE_SIZE,
        boss_active_attack_lookup = BOSS_ACTIVE_ATTACK_LOOKUP,
        boss_max_health = Team.boss_max_health,
        boss_health_for_difficulty = Team.boss_health_for_difficulty,
        boss_has_modifier = boss_has_modifier,
        boss_is_desperate = boss_is_desperate,
        boss_modifier_text = boss_modifier_text,
        boss_health_report = host_read_boss_health_report,
        menu_input = update_config_input,
        freeze_menu_mario = Team.freeze_menu_mario,
        goal_warp = local_goal_warp_update,
        chaos_warp = Team.update_chaos_warp,
        boss_warp = local_boss_warp_update,
        return_to_lobby = force_return_to_lobby,
        modifier = Team.apply_local_modifier,
        post_moveset_limits = Team.apply_post_moveset_limits,
        get_local_modifier_base = Team.get_local_modifier_base,
        capped_horizontal_velocity = capped_horizontal_velocity,
        static_checks = run_static_modifier_checks,
        boss_hazards = apply_boss_hazards,
        power = apply_goal_power,
        host_update = host_update_round,
        host_start = host_start_round,
        host_end = host_end_round,
        host_late_joiner = host_add_late_joiner,
        host_reset_scores = host_reset_scores_after_result,
        remember_player = remember_player_index,
        record_key = player_record_key,
        player_count = connected_player_count,
        boss_health_owner = ensure_boss_health_owner,
        boss_bomb_supply = Team.host_update_boss_bomb_supply,
        boss_bomb_positions = Team.bossBombPositions,
        disconnected = remember_disconnected_player,
        connected = mark_connected_player_unenrolled,
        dialog = on_dialog,
        death = on_death,
        before_death_action = on_before_death_action,
        pause_exit = on_pause_exit,
        nametags_render = on_nametags_render,
        private_player_visibility = update_private_player_visibility,
        allow_interact = on_allow_interact,
        interact = on_interact,
        star_visibility = update_star_visibility,
        reset_hidden_objects = reset_hidden_object_tracking,
        players_have_private_variant = players_have_private_variant,
        players_can_share_world = players_can_share_world,
        allow_pvp_attack = on_allow_pvp_attack,
        remove_castle_lakitu = remove_castle_lakitu,
        remove_existing_castle_lakitu = remove_existing_castle_lakitu,
        grant_infinite_lives = grant_infinite_lives,
        native_hud_visibility = update_native_hud_visibility,
        hide_native_hud_before_render = hide_native_hud_before_render,
        counter_visibility = apply_counter_visibility,
        water_level = on_find_water_level,
        time_range = configured_time_range,
        draw_player_health_bar = draw_player_health_bar,
        draw_config_menu = draw_config_menu,
        health_wedges = Team.health_wedges,
        health_color = Team.health_color,
        draw_round_status_panels = Team.draw_round_status_panels,
        draw_objective_panel = Team.draw_objective_panel,
        draw_hud = draw_hud,
        draw_hud_text = draw_hud_text,
        remove_save_flag = remove_starhunt_save_flag,
        flush_save_on_exit = flush_starhunt_save_on_exit,
        flush_save_on_warp = flush_starhunt_save_on_warp,
        flush_save_removals = flush_starhunt_save_removals,
        goal_already_collected = goal_already_collected,
        selected_mode = selected_mode,
        is_boss_mode = is_boss_mode,
        is_team_mode = Team.is_mode,
        is_chaos_mode = Team.is_chaos_mode,
        get_goal = get_goal,
        get_local_goal = get_local_goal,
        goal_world_text = goal_world_text,
        goal_title_text = goal_title_text,
        goal_matches_player_area = goal_matches_player_area,
        goal_matches_star_object = goal_matches_star_object,
        build_balanced = Team.build_balanced,
        -- Team.initial is replaced wholesale by build_balanced, so the suite
        -- needs an accessor rather than a captured reference.
        team_rosters = function() return Team.initial end,
        team_colors = Team.colors,
        palette_key = Team.palette_key,
        update_palettes = Team.update_palettes,
        restore_palettes = Team.restore_palettes,
        selected_difficulty = Team.selected_difficulty,
        effective_modifier = Team.effective_modifier,
        effective_modifier_for_goal = Team.effective_modifier_for_goal,
        periodic_window = Team.periodic_window,
        normal_mode = Team.NORMAL,
        boss_mode = Team.BOSS,
        team_mode = Team.MODE,
        chaos_mode = Team.CHAOS,
        easy = Team.EASY,
        medium = Team.MEDIUM,
        hard = Team.HARD,
        nightmare = Team.NIGHTMARE,
        team_red = Team.RED,
        team_blue = Team.BLUE,
        team_participant_stats = Team.participant_stats,
        team_update_scores = Team.update_scores,
        team_pick_late = Team.pick_late,
        team_update_palettes = Team.update_palettes,
        team_restore_palettes = Team.restore_palettes,
        lifetime_sync = Team.update_lifetime_sync,
        darkness_active = Team.darkness_active,
        local_modifiers = Team.get_local_modifiers,
        chaos_pair_allowed = Team.chaos_pair_allowed,
        chaos_modifier_allowed = Team.chaos_modifier_allowed,
        chaos_maps = Team.chaos_maps,
        pick_chaos_pair = Team.pick_chaos_pair,
        chaos_reroll = Team.host_reroll_chaos_modifiers,
        chaos_reroll_frames = CHAOS_REROLL_FRAMES,
        next_goal_delay = NEXT_GOAL_DELAY,
        pick_second_modifier = Team.pick_second_modifier,
        draw_darkness_behind = Team.draw_darkness_behind,
        draw_gun_mod_hud_compatibility = Team.draw_gun_mod_hud_compatibility,
        register_mod_compatibility = Team.register_mod_compatibility,
        manual_reroll_request = Team.request_manual_reroll,
        manual_reroll_remaining = Team.manual_reroll_remaining,
        manual_reroll_label = Team.manual_reroll_label,
        update_manual_reroll_menu = Team.update_manual_reroll_menu,
        update_config_menu_lock = Team.update_config_menu_lock,
        manual_reroll_cooldown = Team.manualRerollCooldown,
        toggle_menu = open_config_menu,
        is_menu_open = function() return local_runtime.config_open end,
        set_language = function(value)
            Team.language = clamp(math.floor(value or 0), 0, #Team.language_codes - 1)
        end,
    }
end

-- The built-in HUD is rendered before HOOK_ON_HUD_RENDER on some clients.
-- Keep its star/coin flags disabled during the update, before it can draw.
hook_event(HOOK_UPDATE, update_native_hud_visibility)
hook_event(HOOK_UPDATE, apply_counter_visibility)
hook_event(HOOK_UPDATE, Team.update_lifetime_sync)
hook_event(HOOK_UPDATE, Team.update_palettes)
hook_event(HOOK_UPDATE, host_update_round)
hook_event(HOOK_UPDATE, Team.update_config_menu_lock)
hook_event(HOOK_UPDATE, Team.update_manual_reroll_menu)
hook_event(HOOK_UPDATE, ensure_boss_health_owner)
hook_event(HOOK_UPDATE, host_reset_scores_after_result)
hook_event(HOOK_UPDATE, keep_moat_lowered)
hook_event(HOOK_UPDATE, remove_existing_castle_lakitu)
hook_event(HOOK_UPDATE, local_round_notifications)
hook_event(HOOK_UPDATE, update_star_visibility)
hook_event(HOOK_UPDATE, update_private_player_visibility)
hook_event(HOOK_UPDATE, flush_starhunt_save_removals)
hook_event(HOOK_BEFORE_MARIO_UPDATE, local_goal_warp_update)
hook_event(HOOK_BEFORE_MARIO_UPDATE, Team.update_chaos_warp)
hook_event(HOOK_BEFORE_MARIO_UPDATE, local_boss_warp_update)
hook_event(HOOK_BEFORE_MARIO_UPDATE, force_return_to_lobby)
hook_event(HOOK_BEFORE_MARIO_UPDATE, Team.apply_local_modifier)
hook_event(HOOK_BEFORE_MARIO_UPDATE, apply_boss_hazards)
hook_event(HOOK_BEFORE_MARIO_UPDATE, apply_goal_power)
hook_event(HOOK_BEFORE_MARIO_UPDATE, grant_infinite_lives)
hook_event(HOOK_BEFORE_MARIO_UPDATE, update_config_input)
-- Reapply after character/moveset hooks as well, so custom characters cannot
-- accidentally remove a cap required by the current StarHunt goal.
hook_event(HOOK_MARIO_UPDATE, apply_goal_power)
hook_event(HOOK_MARIO_UPDATE, Team.apply_post_moveset_limits)
hook_event(HOOK_MARIO_UPDATE, Team.freeze_menu_mario)
hook_event(HOOK_ON_OBJECT_LOAD, remove_castle_lakitu)
hook_event(HOOK_ON_LEVEL_INIT, reset_hidden_object_tracking)
hook_event(HOOK_ON_WARP, flush_starhunt_save_on_warp)
hook_event(HOOK_ON_EXIT, flush_starhunt_save_on_exit)
hook_event(HOOK_ON_EXIT, Team.restore_palettes)
hook_event(HOOK_ON_FIND_WATER_LEVEL, on_find_water_level)
hook_event(HOOK_ALLOW_INTERACT, on_allow_interact)
hook_event(HOOK_ON_INTERACT, on_interact)
hook_event(HOOK_ALLOW_PVP_ATTACK, on_allow_pvp_attack)
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, on_before_boss_cutscene)
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, on_before_death_action)
hook_event(HOOK_ON_DIALOG, on_dialog)
hook_event(HOOK_ON_PAUSE_EXIT, on_pause_exit)
hook_event(HOOK_ON_DEATH, on_death)
hook_event(HOOK_ON_NAMETAGS_RENDER, on_nametags_render)
hook_event(HOOK_ON_PLAYER_DISCONNECTED, remember_disconnected_player)
hook_event(HOOK_ON_PLAYER_CONNECTED, mark_connected_player_unenrolled)
hook_event(HOOK_JOINED_GAME, on_joined_game)
hook_event(HOOK_ON_HUD_RENDER_BEHIND, hide_native_hud_before_render)
hook_event(HOOK_ON_HUD_RENDER, draw_hud)
if HOOK_ON_MODS_LOADED ~= nil then
    hook_event(HOOK_ON_MODS_LOADED, Team.register_mod_compatibility)
else
    Team.register_mod_compatibility()
end
hook_chat_command("starhunt", "Open menu; use /starhunt updates for changes", starhunt_command)
if type(hook_mod_menu_button) == "function" then
    Team.rerollMenuIndex = hook_mod_menu_button(
        translated("ANOTHER LEVEL", "OTRO NIVEL"), Team.request_manual_reroll)
end

if network_is_server() and gGlobalSyncTable.sh5_active == nil then
    gGlobalSyncTable.sh5_active = 0
    gGlobalSyncTable.sh5_round = 0
    gGlobalSyncTable.sh5_result_seq = 0
    gGlobalSyncTable.sh5_return_seq = 0
    gGlobalSyncTable.sh5_mode = Team.NORMAL
    gGlobalSyncTable.sh5_difficulty = Team.MEDIUM
    gGlobalSyncTable.sh5_chaos_next_reroll = 0
    gGlobalSyncTable.sh5_chaos_level = 0
    gGlobalSyncTable.sh5_chaos_act = 1
    gGlobalSyncTable.sh5_chaos_modifier_1 = 0
    gGlobalSyncTable.sh5_chaos_modifier_2 = 0
    gGlobalSyncTable.sh5_chaos_modifier_seq = 0
    gGlobalSyncTable.sh5_chaos_alive = 0
    gGlobalSyncTable.sh5_chaos_winner = ""
    gGlobalSyncTable.sh5_chaos_roster_locked = 0
    gGlobalSyncTable.sh5_boss_level_index = 0
    gGlobalSyncTable.sh5_boss_player_modifier = 0
    gGlobalSyncTable.sh5_boss_player_modifier_2 = 0
    gGlobalSyncTable.sh5_boss_modifier_1 = 0
    gGlobalSyncTable.sh5_boss_modifier_2 = 0
    gGlobalSyncTable.sh5_boss_modifier_3 = 0
    gGlobalSyncTable.sh5_boss_attack_seq = 0
    gGlobalSyncTable.sh5_boss_attack_kind = 0
    for slot = 1, BOSS_ATTACK_QUEUE_SIZE do
        gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)] = 0
    end
    gGlobalSyncTable.sh5_boss_health = 0
    gGlobalSyncTable.sh5_boss_max_health = BOSS_HEALTH
    gGlobalSyncTable.sh5_boss_original_bombs_seen = 0
    gGlobalSyncTable.sh5_boss_extra_bombs_spawned = 0
    gGlobalSyncTable.sh5_red_score = 0
    gGlobalSyncTable.sh5_blue_score = 0
    gGlobalSyncTable.sh5_result_red_score = 0
    gGlobalSyncTable.sh5_result_blue_score = 0
    gGlobalSyncTable.sh5_config_minutes = 8
end

Team.update_lifetime_sync()
run_static_modifier_checks()
