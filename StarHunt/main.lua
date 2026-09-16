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
local BOSS_PLAYER_MODIFIERS = boss.BOSS_PLAYER_MODIFIERS
local BOSS_MODIFIERS = boss.BOSS_MODIFIERS
local BOSS_ATTACK_QUEUE_SIZE = boss.BOSS_ATTACK_QUEUE_SIZE
local BOSS_ACTIVE_ATTACK_LOOKUP = boss.BOSS_ACTIVE_ATTACK_LOOKUP
local boss_has_modifier = boss.boss_has_modifier
local boss_is_desperate = boss.boss_is_desperate
local boss_modifier_text = boss.boss_modifier_text
local host_read_boss_health_report = boss.host_read_boss_health_report
local apply_boss_hazards = boss.apply_boss_hazards
local ensure_boss_health_owner = boss.ensure_boss_health_owner
local local_modifiers = require("modules/modifiers")
local capped_horizontal_velocity = local_modifiers.capped_horizontal_velocity
local grant_infinite_lives = local_modifiers.grant_infinite_lives
local keep_moat_lowered = local_modifiers.keep_moat_lowered
local run_static_modifier_checks = local_modifiers.run_static_modifier_checks
local CHAOS_REROLL_FRAMES = require("modules/chaos").CHAOS_REROLL_FRAMES
local local_round = require("modules/round")
local on_before_boss_cutscene = local_round.on_before_boss_cutscene
local local_goal_warp_update = local_round.local_goal_warp_update
local local_boss_warp_update = local_round.local_boss_warp_update
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
local menu = require("modules/menu")
local open_config_menu = menu.open_config_menu
local update_config_input = menu.update_config_input
local starhunt_command = menu.starhunt_command
local hud = require("modules/hud")
local format_remaining_time = hud.format_remaining_time
local draw_hud_text = hud.draw_hud_text
local draw_centered_hud_text = hud.draw_centered_hud_text
local apply_counter_visibility = hud.apply_counter_visibility
local update_native_hud_visibility = hud.update_native_hud_visibility
local hide_native_hud_before_render = hud.hide_native_hud_before_render
local draw_hud = hud.draw_hud
local local_round_notifications = hud.local_round_notifications

local local_lakitu_scan_at = 0

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
        boss_cutscene = on_before_boss_cutscene,
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
        draw_player_health_bar = hud.draw_player_health_bar,
        modifier_text = hud.modifier_text,
        draw_hud_panel = Team.draw_hud_panel,
        draw_start_banner = hud.draw_start_banner,
        draw_config_menu = hud.draw_config_menu,
        round_notifications = local_round_notifications,
        health_wedges = Team.health_wedges,
        health_color = Team.health_color,
        draw_round_status_panels = Team.draw_round_status_panels,
        draw_objective_panel = Team.draw_objective_panel,
        draw_hud = draw_hud,
        draw_hud_text = draw_hud_text,
        measure_hud_text = hud.measure_hud_text,
        draw_centered_hud_text = draw_centered_hud_text,
        format_remaining_time = format_remaining_time,
        objective_text_max_width = Team.objective_text_max_width,
        draw_scaled_centered_text = Team.draw_scaled_centered_text,
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
        chat_command = starhunt_command,
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
