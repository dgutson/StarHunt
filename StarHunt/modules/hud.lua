-- StarHunt v1.1 - the HUD's text layer and the native HUD's visibility.
--
-- FONT_HUD has no colon: it renders ':' as an 'X'.  So no StarHunt text may
-- reach djui_hud_print_text with a colon in it.  draw_hud_text splits the
-- string at every colon and draws two small dots instead, and
-- measure_hud_text adds the same five pixels for each one, so a centered
-- string is measured the way it is drawn.  Every string the mod puts on
-- screen goes through one of those two functions.  Modifier labels are full
-- of colons ("CURSED FLOOR: 7 SEC"), so this is easy to reintroduce and
-- invisible until someone looks at a screenshot.
--
-- The two visibility functions restore what the player had before the round
-- instead of forcing StarHunt's own defaults, so a mod that had hidden the
-- native HUD, or turned the star counter off, gets its setting back when the
-- round ends.  apply_counter_visibility saves the display flags in
-- local_hud_flags_before_round below; update_native_hud_visibility saves the
-- hidden state in local_runtime.native_hud_was_hidden.  Both read the saved
-- value only while their own "a round was active" flag is set, so a second
-- call inside one round cannot overwrite the saved value with StarHunt's own.
--
-- draw_darkness_behind is on the shared Team table because it runs from the
-- behind-HUD hook and writes local_runtime.darkness_draw_frame, which
-- draw_gun_mod_hud_compatibility reads to decide whether Gun Mod's own HUD
-- has to be repainted above the darkness rectangle.
--
-- The panels further down are the HUD's picture layer: the score and timer
-- strip, the health bar, the objective panel and the Gun Mod repaint.  They
-- only read the synchronized tables and the local player's state and write
-- neither, so nothing drawn here changes what the round is doing.
--
-- The last part to arrive is the start banner, the config menu's drawing,
-- draw_hud itself and the round notifications.  The banner and the
-- notifications had to travel together: local_round_notifications rebinds
-- local_start_banner_until and draw_start_banner reads it.  draw_hud sits
-- last in the file because it calls almost everything above it, and it is
-- what the engine's HUD hook calls.

local core = require("core")
local Team = core.Team
local local_runtime = core.local_runtime
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local is_round_active = core.is_round_active
local selected_mode = core.selected_mode
local is_boss_mode = core.is_boss_mode
local clamp = core.clamp
local translated = require("i18n").translated
local goals = require("goals")
local get_local_goal = goals.get_local_goal
local goal_world_text = goals.goal_world_text
local goal_title_text = goals.goal_title_text
local boss = require("boss")
local BOSS_MODIFIER_FIELDS = boss.BOSS_MODIFIER_FIELDS
local boss_modifier_text = boss.boss_modifier_text
local local_round = require("round")
local configured_time_range = local_round.configured_time_range
local connected_player_count = local_round.connected_player_count
local menu = require("menu")
local config_option_count = menu.config_option_count
local config_option_kind = menu.config_option_kind
local config_status_text = menu.config_status_text

local START_BANNER_FRAMES = 105

local local_hud_flags_before_round = nil
local local_counter_round_active = false
local local_seen_round = nil
local local_seen_result = nil
local local_start_banner_until = -1

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

        if local_runtime.config_selection == index then
            djui_hud_set_color(255, 255, 255, 45)
            djui_hud_render_rect(x + 10, line_y - 2, box_w - 20, 16)
        end
        local disabled = (selected_mode() == Team.MODE or selected_mode() == Team.CHAOS)
            and connected_player_count() < 2
            and (option == "mode" or option == "start")
        draw_hud_text((local_runtime.config_selection == index and "> " or "  ") .. text,
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

-- Team.objective_text_max_width, Team.draw_scaled_centered_text,
-- Team.draw_darkness_behind and the panels that attach to the shared Team
-- table need no export.  measure_hud_text, draw_player_health_bar,
-- modifier_text and draw_start_banner are exported for the test suite
-- only; the drawing code that calls them is in this file.  The rest are
-- named by main.lua's hook block and by STARHUNT_TEST_API.
return {
    format_remaining_time = format_remaining_time,
    measure_hud_text = measure_hud_text,
    modifier_text = modifier_text,
    draw_hud_text = draw_hud_text,
    draw_centered_hud_text = draw_centered_hud_text,
    apply_counter_visibility = apply_counter_visibility,
    update_native_hud_visibility = update_native_hud_visibility,
    draw_player_health_bar = draw_player_health_bar,
    hide_native_hud_before_render = hide_native_hud_before_render,
    draw_start_banner = draw_start_banner,
    draw_config_menu = draw_config_menu,
    draw_hud = draw_hud,
    local_round_notifications = local_round_notifications,
}
