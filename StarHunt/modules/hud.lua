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
-- The rest of the HUD -- the start banner, the config menu's drawing, the
-- score, health, timer and objective panels, draw_hud itself and the round
-- notifications -- is still in main.lua and follows in a later pass.  The
-- banner and the notifications have to move together: the notifications
-- rebind the frame the banner reads.

local core = require("core")
local Team = core.Team
local local_runtime = core.local_runtime
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local is_round_active = core.is_round_active
local is_boss_mode = core.is_boss_mode

local local_hud_flags_before_round = nil
local local_counter_round_active = false

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

-- Team.objective_text_max_width, Team.draw_scaled_centered_text and
-- Team.draw_darkness_behind attach to the shared Team table and need no
-- export.  measure_hud_text is exported for the test suite only; the drawing
-- code that calls it is in this file.  The other six are named by main.lua's
-- hook block, by STARHUNT_TEST_API, and by the HUD code that has not moved yet.
return {
    format_remaining_time = format_remaining_time,
    measure_hud_text = measure_hud_text,
    draw_hud_text = draw_hud_text,
    draw_centered_hud_text = draw_centered_hud_text,
    apply_counter_visibility = apply_counter_visibility,
    update_native_hud_visibility = update_native_hud_visibility,
    hide_native_hud_before_render = hide_native_hud_before_render,
}
