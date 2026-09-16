-- StarHunt v1.1 - the /starhunt config menu.
--
-- Six options for the host -- language, mode, difficulty, round length, status
-- and the start/stop action -- and two for everyone else, who may change only
-- the language and read the status.  This menu is the mod's whole user
-- interface: there is no other way to pick a mode, a difficulty or a length.
--
-- `update_config_input` owns the controller while the menu is up.  It reads the
-- buttons and the stick, then zeroes both before Mario's movement code can see
-- them, which is why the input function ends by neutralizing the controller on
-- every path rather than returning early.
--
-- The two stick thresholds are not a typo.  A push must pass 24 to move the
-- selection, and the stick must fall back below 18 before it can move again, so
-- easing off and pushing does not scroll two rows.
--
-- The selection itself is NOT here.  It lives on `local_runtime` in core.lua,
-- because it is rebound on every press and the drawing code in another module
-- reads it -- a rebound top-level local would give each module its own copy and
-- the menu would draw one row while the input moved another.
-- `config_button_latch` and `config_stick_latched` are rebound too, but are read
-- only in this file, so they stay.
--
-- `draw_config_menu` is not here either, and cannot be: it draws through the
-- HUD's own `draw_hud_text` and `draw_centered_hud_text`, and the HUD's
-- `draw_hud` calls it back, so a menu that owned it would be half of a require
-- cycle.  It stays with the drawing code and reads this module's three option
-- functions and the selection.
--
-- The hook registrations and the chat command registration stay in main.lua,
-- because order within a hook type matters.  This module exports what they name.

local core = require("core")
local SH = core.SH
local local_runtime = core.local_runtime
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local clamp = core.clamp
local is_round_active = core.is_round_active
local selected_mode = core.selected_mode
local translated = require("i18n").translated
local round = require("round")
local configured_time_range = round.configured_time_range
local connected_player_count = round.connected_player_count
local host_start_round = round.host_start_round
local host_end_round = round.host_end_round

local config_button_latch = 0
local config_stick_latched = false

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

SH.close_widdlepets_menu = function()
    local pets = rawget(_G, "wpets")
    if type(pets) == "table" and type(pets.is_menu_opened) == "function"
        and type(pets.close_menu) == "function" and pets.is_menu_opened() then
        pets.close_menu()
    end
end

SH.set_config_menu_open = function(opening)
    opening = opening and true or false
    local changed = local_runtime.config_open ~= opening
    if opening and changed then SH.close_widdlepets_menu() end
    local_runtime.config_open = opening
    if opening and changed then
        local_runtime.config_selection = clamp(local_runtime.config_selection, 1, config_option_count())
        config_button_latch = 0
        config_stick_latched = false
        local_runtime.menu_freeze_x = nil
        local_runtime.menu_freeze_y = nil
        local_runtime.menu_freeze_z = nil
    end
end

local function open_config_menu()
    if local_runtime.config_open and not is_round_active() then
        SH.close_widdlepets_menu()
        return
    end
    SH.set_config_menu_open(not local_runtime.config_open)
end

SH.update_config_menu_lock = function()
    local active = is_round_active()
    if local_runtime.config_round_was_active == nil then
        SH.set_config_menu_open(not active)
    elseif not active then
        SH.set_config_menu_open(true)
    elseif not local_runtime.config_round_was_active then
        SH.set_config_menu_open(false)
    end
    local_runtime.config_round_was_active = active
end

SH.cycle_mode = function(delta)
    local next_mode = (selected_mode() + delta) % 4
    if next_mode < 0 then next_mode = next_mode + 4 end
    gGlobalSyncTable.sh5_mode = next_mode
    local minimum, maximum = configured_time_range(connected_player_count())
    gGlobalSyncTable.sh5_config_minutes =
        clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)
end

SH.cycle_difficulty = function(delta)
    local next_difficulty = (SH.selected_difficulty() + delta) % 4
    if next_difficulty < 0 then next_difficulty = next_difficulty + 4 end
    gGlobalSyncTable.sh5_difficulty = next_difficulty
end

SH.freeze_menu_mario = function(m)
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
        if is_round_active() then SH.set_config_menu_open(false) end
    elseif (pressed & U_JPAD) ~= 0 or stick_up then
        local_runtime.config_selection = local_runtime.config_selection - 1
        if local_runtime.config_selection < 1 then local_runtime.config_selection = count end
    elseif (pressed & D_JPAD) ~= 0 or stick_down then
        local_runtime.config_selection = local_runtime.config_selection + 1
        if local_runtime.config_selection > count then local_runtime.config_selection = 1 end
    elseif (pressed & (L_JPAD | R_JPAD)) ~= 0 or stick_left or stick_right then
        local option = config_option_kind(local_runtime.config_selection)
        if option == "language" then
            local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
            SH.language = (SH.language + delta) % #SH.language_codes
            if SH.language < 0 then SH.language = SH.language + #SH.language_codes end
            mod_storage_save("starhunt_v11_language", tostring(SH.language))
        elseif option == "mode" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("MODE IS LOCKED DURING A ROUND", "EL MODO ESTA BLOQUEADO DURANTE LA RONDA"), 1)
            else
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                SH.cycle_mode(delta)
            end
        elseif option == "difficulty" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("DIFFICULTY IS LOCKED DURING A ROUND",
                    "LA DIFICULTAD ESTA BLOQUEADA DURANTE LA RONDA"), 1)
            else
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                SH.cycle_difficulty(delta)
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
        local option = config_option_kind(local_runtime.config_selection)
        if option == "start" then
            local minimum, maximum = configured_time_range(connected_player_count())
            if host_start_round(clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)) then
                SH.set_config_menu_open(false)
            end
        elseif option == "stop" then
            host_end_round("stopped by host")
            SH.set_config_menu_open(true)
        elseif option == "language" then
            SH.language = (SH.language + 1) % #SH.language_codes
            mod_storage_save("starhunt_v11_language", tostring(SH.language))
        elseif option == "mode" and network_is_server() then
            if not is_round_active() then
                SH.cycle_mode(1)
            end
        elseif option == "difficulty" and network_is_server() then
            if not is_round_active() then SH.cycle_difficulty(1) end
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
    if local_runtime.config_open then SH.freeze_menu_mario(m) end
end

local function show_help()
    djui_chat_message_create("/starhunt - " .. translated("open the StarHunt menu", "abre el menu de StarHunt"))
    djui_chat_message_create("/starhunt updates - "
        .. translated("show what StarHunt is and what changed", "muestra de que trata StarHunt y que cambio"))
end

SH.show_updates = function()
    djui_chat_message_create("\\#FFE05A\\STAR\\#58D6FF\\HUNT \\#FFFFFF\\v1.1.1")
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
        SH.show_updates()
        return true
    end
    show_help()
    return true
end

-- The SH.* functions above attach to the shared SH table and need no
-- export.  These six do: the three option readers are called by
-- draw_config_menu, which lives with the drawing code, and the other three are
-- named by main.lua's hook block and by STARHUNT_TEST_API.
return {
    config_option_count = config_option_count,
    config_option_kind = config_option_kind,
    config_status_text = config_status_text,
    open_config_menu = open_config_menu,
    update_config_input = update_config_input,
    starhunt_command = starhunt_command,
}
