-- The HUD's picture layer: what is actually on screen.
--
-- The second pass of modules/hud.lua moved modifier_text, draw_hud_panel, the
-- health bar, the score/timer strip, the objective panel and the Gun Mod
-- repaint out of main.lua. The mutation sweep that followed found the whole
-- area untested: 500 of 507 mutations survived a green 534-test run, and the
-- seven that were caught were caught by the darkness and health-colour tests
-- written for the first pass. Every panel could be moved, resized, recoloured
-- or deleted outright with nothing noticing.
--
-- Three engine stubs were hiding part of it as well. djui_hud_render_rect kept
-- only the last rectangle and djui_hud_render_texture only a count, so a panel
-- is a stack of shapes the suite could not see; and gTextures was empty, which
-- put the star and the coin icons behind a guard no test could satisfy.
--
-- Everything below is pinned as a literal. Two numbers from the harness run
-- through all of it: djui_hud_measure_text is eight pixels per character, and
-- the screen is 1920 x 1009.

return function(t, harness)
    local s = t.suite("hud_panels")

    local function fresh()
        local api, ctl = harness.load()
        -- The mod starts in Spanish, and every string pinned below is the
        -- English one, so the language is part of the fixture.
        api.set_language(0)
        ctl.hud.text = {}
        ctl.hud.colors = {}
        ctl.hud.rect_calls = {}
        ctl.hud.texture_calls = {}
        ctl.hud.color = nil
        return api, ctl
    end

    --- Everything the colour layer printed, with a colon's two dots folded back
    -- into the ":" they stand for. draw_hud_text paints a black shadow at alpha
    -- 220 first and the caller's colour at alpha 255 second, so the colour
    -- layer is exactly the calls at full alpha; it splits at every colon, so
    -- "TIME 1:30" reaches the font as "TIME 1", ".", "." and "30".
    local function printed(ctl)
        local calls = {}
        for _, call in ipairs(ctl.hud.text) do
            if call.a == 255 then calls[#calls + 1] = call end
        end
        local out, i = {}, 1
        while i <= #calls do
            local call = calls[i]
            if call.text == "." and calls[i + 1] ~= nil and calls[i + 1].text == "."
                and calls[i + 1].x == call.x and #out > 0 then
                out[#out].text = out[#out].text .. ":"
                i = i + 2
                if calls[i] ~= nil and calls[i].text ~= "." then
                    out[#out].text = out[#out].text .. calls[i].text
                    i = i + 1
                end
            else
                out[#out + 1] = { text = call.text, x = call.x, y = call.y,
                    scale = call.scale, r = call.r, g = call.g, b = call.b }
                i = i + 1
            end
        end
        return out
    end

    --- The one string on screen reading `text`, or a failure naming everything
    -- that was drawn instead.
    local function line(ctl, text)
        local found, seen = nil, {}
        for _, call in ipairs(printed(ctl)) do
            seen[#seen + 1] = call.text
            if call.text == text then
                if found ~= nil then t.fail("'" .. text .. "' was drawn twice") end
                found = call
            end
        end
        if found == nil then
            t.fail("'" .. text .. "' was never drawn; on screen: "
                .. table.concat(seen, " | "))
        end
        -- t.fail always raises, so the fallback is only there to tell the type
        -- checker that what comes back is never nil.
        return found or {}
    end

    local function absent(ctl, text)
        for _, call in ipairs(printed(ctl)) do
            if call.text == text then t.fail("'" .. text .. "' should not be on screen") end
        end
    end

    --- A string's position, scale and colour in one assertion.
    local function at(ctl, text, x, y, scale, r, g, b)
        local call = line(ctl, text)
        t.near(call.x, x, 0.001, text .. " x")
        t.eq(call.y, y, text .. " y")
        t.near(call.scale, scale, 0.000001, text .. " scale")
        t.eq(call.r, r, text .. " red")
        t.eq(call.g, g, text .. " green")
        t.eq(call.b, b, text .. " blue")
        return call
    end

    --- Where draw_centered_hud_text puts a string `width` pixels wide.
    local function centered_x(width, scale)
        return (1920 - width * scale) * 0.5
    end

    local function rect_at(ctl, index)
        local got = ctl.hud.rect_calls[index]
        if got == nil then
            t.fail("only " .. #ctl.hud.rect_calls .. " rectangles were drawn, wanted "
                .. index)
        end
        return got or {}
    end

    local function rect_is(ctl, index, x, y, w, h, r, g, b, a)
        local got = rect_at(ctl, index)
        local label = "rectangle " .. index
        t.eq(got.x, x, label .. " x")
        t.eq(got.y, y, label .. " y")
        t.eq(got.w, w, label .. " width")
        t.eq(got.h, h, label .. " height")
        t.eq(got.r, r, label .. " red")
        t.eq(got.g, g, label .. " green")
        t.eq(got.b, b, label .. " blue")
        t.eq(got.a, a, label .. " alpha")
    end

    local function texture_at(ctl, index)
        local got = ctl.hud.texture_calls[index]
        if got == nil then
            t.fail("only " .. #ctl.hud.texture_calls .. " textures were drawn, wanted "
                .. index)
        end
        return got or {}
    end

    local function texture_is(ctl, index, texture, x, y, scale_x, scale_y, r, g, b, a)
        local got = texture_at(ctl, index)
        local label = "texture " .. index
        t.eq(got.texture, texture, label .. " image")
        t.near(got.x, x, 0.001, label .. " x")
        t.near(got.y, y, 0.001, label .. " y")
        t.near(got.scale_x, scale_x, 0.000001, label .. " x scale")
        t.near(got.scale_y, scale_y, 0.000001, label .. " y scale")
        t.eq(got.r, r, label .. " red")
        t.eq(got.g, g, label .. " green")
        t.eq(got.b, b, label .. " blue")
        t.eq(got.a, a, label .. " alpha")
    end

    -- modifier_text ----------------------------------------------------------

    -- kind, value, and the Spanish string the mod owes it.
    local SPANISH = {
        { "no_b",              0,  "BOTON B BLOQUEADO" },
        { "floor_doom",        7,  "PISO MALDITO: 7 SEG" },
        { "speed_cap",        20,  "PIES PESADOS" },
        { "low_jump",         20,  "SALTOS BAJOS" },
        { "water_cap",        20,  "NADO PESADO" },
        { "jump_limit",        3,  "3 SALTOS" },
        { "reverse_controls",  0,  "CONTROLES INVERTIDOS" },
        { "periodic_freeze",   4,  "TIEMPO CONGELADO CADA 4 SEG" },
        { "fragile",           0,  "FRAGIL: 4 DE VIDA" },
        { "high_gravity",      0,  "GRAVEDAD ALTA" },
        { "wind_gust",         0,  "RAFAGAS DE VIENTO" },
        { "no_z",              0,  "BOTON Z BLOQUEADO" },
        { "air_brake",         0,  "POCO CONTROL AEREO" },
        { "lava_clock",        6,  "DANO CADA 6 SEG" },
        { "turbo",             0,  "MODO TURBO" },
        { "slippery",          0,  "ZAPATOS RESBALADIZOS" },
        { "swap_ab",           0,  "BOTONES A/B INTERCAMBIADOS" },
        { "keep_moving",       3,  "SIGUE MOVIENDOTE: 3 SEG" },
        { "jump_cooldown",    45,  "ESPERA ENTRE SALTOS: 1.5 SEG" },
        { "coin_surge",        0,  "IMPULSO DE MONEDA" },
        { "control_drift",     0,  "CONTROLES ONDULANTES" },
        { "coin_toll",         5,  "PEAJE DE MONEDAS: 5" },
        { "darkness_pulse",  150,  "PULSO DE OSCURIDAD" },
        { "mirrored_steering", 0,  "DIRECCION ESPEJO" },
        { "coin_leak",         8,  "FUGA DE MONEDAS CADA 8 SEG" },
        { "slow_pulse",        0,  "PULSO LENTO" },
        { "air_mirror",        0,  "ESPEJO AEREO" },
        { "momentum_burst",    0,  "IMPULSO PERIODICO" },
        { "control_pulse",     0,  "PULSO DE CONTROLES" },
        { "coin_weight",       0,  "PESO DE MONEDAS" },
        { "gravity_wave",      0,  "GRAVEDAD ONDULANTE" },
        { "overheat",          0,  "SOBRECALENTAMIENTO: FRENA" },
    }

    s.test("Spanish names every modifier kind", function()
        local api = harness.load()
        api.set_language(1)
        for _, case in ipairs(SPANISH) do
            t.eq(api.modifier_text({ kind = case[1], value = case[2], label = "ENGLISH LABEL" }),
                case[3], case[1])
        end
    end)

    s.test("the Spanish table above covers the whole catalog", function()
        -- Not an assertion about the drawing: it is what makes the test above
        -- fail when a new modifier kind is added and left unnamed in Spanish.
        local api = harness.load()
        local named = {}
        for _, case in ipairs(SPANISH) do named[case[1]] = true end
        for _, modifier_data in ipairs(api.normal_modifier_catalog) do
            t.ok(named[modifier_data.kind],
                "no Spanish case for the catalog's '" .. tostring(modifier_data.kind) .. "'")
        end
    end)

    s.test("a Spanish name the mod has never heard of falls back to the label", function()
        local api = harness.load()
        api.set_language(1)
        t.eq(api.modifier_text({ kind = "not_a_real_kind", value = 1, label = "PLAIN LABEL" }),
            "PLAIN LABEL")
    end)

    s.test("English uses the label carried on the modifier itself", function()
        local api = harness.load()
        api.set_language(0)
        t.eq(api.modifier_text({ kind = "floor_doom", value = 7,
            label = "CURSED FLOOR: 7 SEC" }), "CURSED FLOOR: 7 SEC")
    end)

    s.test("Portuguese reads its own dictionary, not the Spanish branch", function()
        local api = harness.load()
        api.set_language(2)
        t.eq(api.modifier_text({ kind = "no_b", value = 0, label = "B BUTTON LOCKED" }),
            "BOTÃO B BLOQUEADO")
    end)

    s.test("Portuguese spells out the five kinds that carry seconds", function()
        local api = harness.load()
        api.set_language(2)
        t.eq(api.modifier_text({ kind = "floor_doom", value = 7, label = "L" }),
            "CHÃO AMALDIÇOADO: 7 SEC", "floor_doom")
        t.eq(api.modifier_text({ kind = "periodic_freeze", value = 4, label = "L" }),
            "CONGELAMENTO PERIÓDICO: 4 SEC", "periodic_freeze")
        t.eq(api.modifier_text({ kind = "lava_clock", value = 6, label = "L" }),
            "DANO PERIÓDICO: 6 SEC", "lava_clock")
        t.eq(api.modifier_text({ kind = "keep_moving", value = 3, label = "L" }),
            "CONTINUE EM MOVIMENTO: 3 SEC", "keep_moving")
        t.eq(api.modifier_text({ kind = "coin_leak", value = 8, label = "L" }),
            "VAZAMENTO DE MOEDAS: 8 SEC", "coin_leak")
    end)

    s.test("Portuguese puts the count in front for the two kinds that count", function()
        local api = harness.load()
        api.set_language(2)
        t.eq(api.modifier_text({ kind = "jump_limit", value = 3, label = "L" }),
            "3 PULOS", "jump_limit")
        t.eq(api.modifier_text({ kind = "coin_toll", value = 5, label = "L" }),
            "5 PEDÁGIO DE MOEDAS", "coin_toll")
    end)

    s.test("Portuguese spells the jump cooldown in seconds to one decimal", function()
        local api = harness.load()
        api.set_language(2)
        t.eq(api.modifier_text({ kind = "jump_cooldown", value = 45, label = "L" }),
            "ESPERA ENTRE PULOS: 1.5 SEC")
    end)

    s.test("a later language with no entry for the kind falls back to the label", function()
        local api = harness.load()
        api.set_language(2)
        t.eq(api.modifier_text({ kind = "not_a_real_kind", value = 1, label = "PLAIN LABEL" }),
            "PLAIN LABEL")
    end)

    -- the darkness pulse's clock -------------------------------------------

    s.test("no modifier at all is not a dark pulse", function()
        local api = harness.load()
        t.eq(api.darkness_active(nil), false, "nil claimed to darken the screen")
    end)

    s.test("the pulse cycle starts bright", function()
        -- elapsed is floored at zero, so the first frame of a cycle is phase 0
        -- and only a pulse that covers the whole ten seconds is dark on it.
        local api, ctl = fresh()
        api.runtime.modifier_start_frame = 0
        ctl.timer = 0
        t.eq(api.darkness_active({ kind = "darkness_pulse", value = 299 }), false,
            "a pulse one frame short of the cycle darkened its first frame")
        t.eq(api.darkness_active({ kind = "darkness_pulse", value = 300 }), true,
            "a pulse covering the whole cycle should be dark throughout")
    end)

    s.test("the pulse cycle is ten seconds long", function()
        local api, ctl = fresh()
        api.runtime.modifier_start_frame = 0
        local pulse = { kind = "darkness_pulse", value = 30 }
        ctl.timer = 269
        t.eq(api.darkness_active(pulse), false, "dark a frame early")
        ctl.timer = 270
        t.eq(api.darkness_active(pulse), true, "not dark for the last second")
        ctl.timer = 570
        t.eq(api.darkness_active(pulse), true, "the second cycle darkened elsewhere")
    end)

    -- the panel every card is built from -------------------------------------

    s.test("a panel is a dark box, a coloured left edge and a highlight", function()
        local api, ctl = fresh()
        api.draw_hud_panel(40, 60, 100, 20, 11, 22, 33)
        t.eq(#ctl.hud.rect_calls, 3, "a panel is exactly three rectangles")
        rect_is(ctl, 1, 40, 60, 100, 20, 5, 11, 24, 205)
        rect_is(ctl, 2, 40, 60, 3, 20, 11, 22, 33, 235)
        rect_is(ctl, 3, 43, 60, 97, 1, 255, 255, 255, 28)
    end)

    -- health -----------------------------------------------------------------

    s.test("health is read as eight wedges of 0x100", function()
        local api = harness.load()
        t.eq(api.health_wedges(0), 0, "no health")
        t.eq(api.health_wedges(0x100), 1, "one wedge")
        t.eq(api.health_wedges(0x1FF), 1, "a part-filled wedge does not count")
        t.eq(api.health_wedges(0x400), 4, "four wedges")
        t.eq(api.health_wedges(0x880), 8, "full health")
    end)

    s.test("health outside the range is clamped rather than scaled", function()
        local api = harness.load()
        t.eq(api.health_wedges(nil), 8, "unknown health reads as full")
        t.eq(api.health_wedges(-500), 0, "negative health")
        t.eq(api.health_wedges(0x9999), 8, "more than full health")
    end)

    s.test("the health colour changes at six wedges and at three", function()
        local api = harness.load()
        local function color(wedges)
            local r, g, b = api.health_color(wedges)
            return string.format("%d,%d,%d", r, g, b)
        end
        t.eq(color(8), "74,218,128", "eight wedges")
        t.eq(color(6), "74,218,128", "six wedges is still green")
        t.eq(color(5), "255,190,54", "five wedges")
        t.eq(color(3), "255,190,54", "three wedges is still amber")
        t.eq(color(2), "255,76,82", "two wedges")
        t.eq(color(0), "255,76,82", "no wedges")
    end)

    s.test("the health bar is a panel, a label and eight wedge slots", function()
        local api, ctl = fresh()
        gMarioStates[0].health = 0x880
        api.draw_player_health_bar(nil)

        -- The panel, then three rectangles per filled slot and one per empty.
        rect_is(ctl, 1, 10, 42, 101, 19, 5, 11, 24, 205)
        rect_is(ctl, 2, 10, 42, 3, 19, 74, 218, 128, 235)
        rect_is(ctl, 3, 13, 42, 98, 1, 255, 255, 255, 28)
        at(ctl, "HP", 17, 47, 0.38, 74, 218, 128)

        t.eq(#ctl.hud.rect_calls, 27, "three panel rectangles and three per full slot")
        for slot = 1, 8 do
            local sx = 39 + (slot - 1) * 8
            local first = 3 + (slot - 1) * 3 + 1
            rect_is(ctl, first, sx, 47, 6, 10, 33, 43, 61, 255)
            rect_is(ctl, first + 1, sx, 47, 6, 10, 74, 218, 128, 255)
            rect_is(ctl, first + 2, sx, 47, 6, 1, 255, 255, 255, 70)
        end
    end)

    s.test("an empty wedge is drawn as its socket alone", function()
        local api, ctl = fresh()
        gMarioStates[0].health = 0x400
        api.draw_player_health_bar(nil)

        t.eq(#ctl.hud.rect_calls, 19, "three panel, three per full slot, one per empty")
        at(ctl, "HP", 17, 47, 0.38, 255, 190, 54)
        -- slot 4 is the last filled one, slot 5 the first empty one
        rect_is(ctl, 3 + 3 * 3 + 2, 63, 47, 6, 10, 255, 190, 54, 255)
        rect_is(ctl, 3 + 4 * 3 + 1, 71, 47, 6, 10, 33, 43, 61, 255)
    end)

    s.test("the health bar follows the y it is given", function()
        local api, ctl = fresh()
        gMarioStates[0].health = 0x880
        api.draw_player_health_bar(51)
        rect_is(ctl, 1, 10, 51, 101, 19, 5, 11, 24, 205)
        at(ctl, "HP", 17, 56, 0.38, 74, 218, 128)
        rect_is(ctl, 4, 39, 56, 6, 10, 33, 43, 61, 255)
    end)

    s.test("the health bar is skipped when there is no local Mario", function()
        local api, ctl = fresh()
        gMarioStates[0] = nil
        api.draw_player_health_bar(nil)
        t.eq(#ctl.hud.rect_calls, 0, "nothing should have been drawn")
        t.eq(#ctl.hud.text, 0, "nothing should have been written")
    end)

    -- the status strip -------------------------------------------------------

    --- Every branch of the strip ends with the same timer card and the same
    -- health bar, so each test only pins the card the mode owns and then the
    -- shared right-hand card once.
    local function timer_card(ctl, first_rect)
        rect_is(ctl, first_rect, 1816, 8, 94, 43, 5, 11, 24, 205)
        rect_is(ctl, first_rect + 1, 1816, 8, 3, 43, 255, 210, 72, 235)
        rect_is(ctl, first_rect + 2, 1819, 8, 91, 1, 255, 255, 255, 28)
        at(ctl, "TIME 1:00", 1824, 14, 0.48, 255, 220, 96)
        at(ctl, "x 12", 1840, 32, 0.52, 255, 238, 156)
    end

    local function strip(api, ctl, mode, score)
        gGlobalSyncTable.sh5_mode = mode
        gMarioStates[0].health = 0x880
        ctl.hud.values[HUD_DISPLAY_COINS] = 12
        ctl.hud.text = {}
        ctl.hud.colors = {}
        ctl.hud.rect_calls = {}
        ctl.hud.texture_calls = {}
        ctl.hud.color = nil
        api.draw_round_status_panels(60, score)
    end

    s.test("a star race shows the star, the score and the timer", function()
        local api, ctl = fresh()
        strip(api, ctl, api.normal_mode, 3)
        rect_is(ctl, 1, 10, 8, 72, 29, 5, 11, 24, 205)
        rect_is(ctl, 2, 10, 8, 3, 29, 255, 210, 72, 235)
        rect_is(ctl, 3, 13, 8, 69, 1, 255, 255, 255, 28)
        texture_is(ctl, 1, "TEX_STAR", 18, 14, 0.72, 0.72, 255, 255, 255, 255)
        at(ctl, "x 3", 38, 15, 0.64, 255, 255, 255)
        timer_card(ctl, 4)
        texture_is(ctl, 2, "TEX_COIN", 1825, 30, 0.65, 0.65, 255, 255, 255, 255)
        -- the health bar follows the timer card at the default y
        rect_is(ctl, 7, 10, 42, 101, 19, 5, 11, 24, 205)
    end)

    s.test("a star race with no star texture still shows the score", function()
        local api, ctl = fresh()
        gTextures.star = nil
        strip(api, ctl, api.normal_mode, 3)
        t.eq(#ctl.hud.texture_calls, 1, "only the coin should have been drawn")
        texture_is(ctl, 1, "TEX_COIN", 1825, 30, 0.65, 0.65, 255, 255, 255, 255)
        at(ctl, "x 3", 38, 15, 0.64, 255, 255, 255)
    end)

    s.test("Team mode shows both scores and marks the player's own", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_team = api.team_red
        gGlobalSyncTable.sh5_red_score = 2
        gGlobalSyncTable.sh5_blue_score = 5
        strip(api, ctl, api.team_mode, 0)
        rect_is(ctl, 1, 10, 8, 101, 38, 5, 11, 24, 205)
        rect_is(ctl, 2, 10, 8, 3, 38, 232, 68, 72, 235)
        at(ctl, "> RED  x 2", 17, 14, 0.48, 255, 78, 78)
        at(ctl, "  BLUE x 5", 17, 28, 0.48, 92, 154, 255)
        timer_card(ctl, 4)
        -- the taller card pushes the health bar down
        rect_is(ctl, 7, 10, 51, 101, 19, 5, 11, 24, 205)
    end)

    s.test("the blue team gets the blue card and the blue marker", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_team = api.team_blue
        gGlobalSyncTable.sh5_red_score = 2
        gGlobalSyncTable.sh5_blue_score = 5
        strip(api, ctl, api.team_mode, 0)
        rect_is(ctl, 2, 10, 8, 3, 38, 64, 132, 255, 235)
        at(ctl, "  RED  x 2", 17, 14, 0.48, 255, 78, 78)
        at(ctl, "> BLUE x 5", 17, 28, 0.48, 92, 154, 255)
    end)

    s.test("a player on no team gets the red card and no marker", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_team = nil
        strip(api, ctl, api.team_mode, 0)
        rect_is(ctl, 2, 10, 8, 3, 38, 232, 68, 72, 235)
        at(ctl, "  RED  x 0", 17, 14, 0.48, 255, 78, 78)
        at(ctl, "  BLUE x 0", 17, 28, 0.48, 92, 154, 255)
    end)

    s.test("Chaos counts the players still alive", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_chaos_alive = 4
        strip(api, ctl, api.chaos_mode, 0)
        rect_is(ctl, 1, 10, 8, 101, 29, 5, 11, 24, 205)
        rect_is(ctl, 2, 10, 8, 3, 29, 196, 78, 255, 235)
        at(ctl, "ALIVE 4", 17, 15, 0.58, 235, 165, 255)
        timer_card(ctl, 4)
        rect_is(ctl, 7, 10, 42, 101, 19, 5, 11, 24, 205)
    end)

    s.test("Boss draws one wedge per point of Bowser's health", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = 3
        strip(api, ctl, api.boss_mode, 0)
        rect_is(ctl, 1, 10, 8, 101, 29, 5, 11, 24, 205)
        rect_is(ctl, 2, 10, 8, 3, 29, 236, 66, 82, 235)
        at(ctl, "BOWSER", 17, 13, 0.42, 255, 112, 94)
        for slot = 1, 3 do
            local sx = 61 + (slot - 1) * 9
            local first = 3 + (slot - 1) * 3 + 1
            rect_is(ctl, first, sx, 14, 7, 12, 48, 38, 49, 255)
            rect_is(ctl, first + 1, sx, 14, 7, 12, 238, 67, 82, 255)
            rect_is(ctl, first + 2, sx, 14, 7, 1, 255, 220, 190, 80)
        end
        rect_is(ctl, 13, 88, 14, 7, 12, 48, 38, 49, 255)
        rect_is(ctl, 14, 97, 14, 7, 12, 48, 38, 49, 255)
        timer_card(ctl, 15)
        rect_is(ctl, 18, 10, 42, 101, 19, 5, 11, 24, 205)
    end)

    s.test("Bowser's health bar is clamped to the pool, not scaled to it", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = 99
        strip(api, ctl, api.boss_mode, 0)
        -- five full wedges and nothing beyond them
        rect_is(ctl, 3 + 4 * 3 + 2, 97, 14, 7, 12, 238, 67, 82, 255)
        timer_card(ctl, 19)
    end)

    s.test("an unsynced Bowser reads as a full health bar", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = nil
        strip(api, ctl, api.boss_mode, 0)
        rect_is(ctl, 3 + 4 * 3 + 2, 97, 14, 7, 12, 238, 67, 82, 255)
    end)

    s.test("a client that has not received the scores yet sees zero", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_team = api.team_red
        gGlobalSyncTable.sh5_red_score = nil
        gGlobalSyncTable.sh5_blue_score = nil
        strip(api, ctl, api.team_mode, 0)
        at(ctl, "> RED  x 0", 17, 14, 0.48, 255, 78, 78)
        at(ctl, "  BLUE x 0", 17, 28, 0.48, 92, 154, 255)
    end)

    s.test("a client that has not received the survivor count yet sees zero", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_chaos_alive = nil
        strip(api, ctl, api.chaos_mode, 0)
        at(ctl, "ALIVE 0", 17, 15, 0.58, 235, 165, 255)
    end)

    s.test("a negative Bowser health draws an empty bar, not a full one", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = -3
        strip(api, ctl, api.boss_mode, 0)
        -- One socket per slot and nothing on top of it, so slot 2's socket is
        -- the rectangle straight after slot 1's.
        rect_is(ctl, 4, 61, 14, 7, 12, 48, 38, 49, 255)
        rect_is(ctl, 5, 70, 14, 7, 12, 48, 38, 49, 255)
        timer_card(ctl, 9)
    end)

    s.test("an engine that reports no coin count at all shows zero coins", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.normal_mode
        gMarioStates[0].health = 0x880
        -- The stub always answers with a number.  The real engine can answer
        -- nil, which is what the fallback behind the coin counter is for.
        _G.hud_get_value = function() return nil end
        ctl.hud.text = {}
        api.draw_round_status_panels(60, 3)
        at(ctl, "x 0", 1840, 32, 0.52, 255, 238, 156)
    end)

    s.test("the timer card reads the clock and the game's own coin counter", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.normal_mode
        gMarioStates[0].health = 0x880
        ctl.hud.values[HUD_DISPLAY_COINS] = 7
        ctl.hud.text = {}
        api.draw_round_status_panels(95, 0)
        at(ctl, "TIME 1:35", 1824, 14, 0.48, 255, 220, 96)
        at(ctl, "x 7", 1840, 32, 0.52, 255, 238, 156)
    end)

    -- the objective panel ----------------------------------------------------

    local GOAL = { world = "WORLD", world_es = "MUNDO",
                   title = "TITLE", title_es = "TITULO" }
    local LOCKED = { kind = "no_b", value = 0, label = "B LOCKED" }
    local GRAVITY = { kind = "high_gravity", value = 0, label = "HIGH GRAVITY" }

    s.test("a star race shows the world, the star and the modifier", function()
        local api, ctl = fresh()
        api.draw_objective_panel(GOAL, LOCKED, nil)
        at(ctl, "WORLD", centered_x(40, 0.56), 3, 0.56, 104, 218, 255)
        at(ctl, "TITLE", centered_x(40, 0.70), 15, 0.70, 255, 255, 255)
        at(ctl, "B LOCKED", centered_x(64, 0.55), 28, 0.55, 255, 215, 73)
    end)

    s.test("a second modifier gets its own line below the first", function()
        local api, ctl = fresh()
        api.draw_objective_panel(GOAL, LOCKED, GRAVITY)
        at(ctl, "B LOCKED", centered_x(64, 0.55), 28, 0.55, 255, 215, 73)
        at(ctl, "HIGH GRAVITY", centered_x(96, 0.50), 39, 0.50, 255, 145, 80)
        -- Neither counter belongs to either of these two modifiers. Both
        -- searches read the second slot through a three-term `and` chain that
        -- returns the modifier itself, so a loosened term there hands the
        -- counter a modifier that has nothing to count.
        absent(ctl, "JUMPS: 0")
        absent(ctl, "COINS: 0/0")
    end)

    s.test("with no goal yet the panel says so and nothing else", function()
        local api, ctl = fresh()
        api.draw_objective_panel(nil, LOCKED, nil)
        at(ctl, "CHOOSING YOUR NEXT GOAL...", centered_x(208, 0.66), 15, 0.66,
            255, 255, 255)
        absent(ctl, "B LOCKED")
    end)

    s.test("a goal with no modifier yet is not a goal on screen", function()
        local api, ctl = fresh()
        api.draw_objective_panel(GOAL, nil, nil)
        at(ctl, "CHOOSING YOUR NEXT GOAL...", centered_x(208, 0.66), 15, 0.66,
            255, 255, 255)
        absent(ctl, "WORLD")
    end)

    s.test("a jump limit shows the jumps the player has left", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_jump_count = 2
        api.draw_objective_panel(GOAL, { kind = "jump_limit", value = 3, label = "3 JUMPS" },
            nil)
        at(ctl, "JUMPS: 2", centered_x(61, 0.48), 40, 0.48, 255, 145, 80)
    end)

    s.test("before the first jump the counter shows the whole allowance", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_jump_count = nil
        api.draw_objective_panel(GOAL, { kind = "jump_limit", value = 3, label = "3 JUMPS" },
            nil)
        at(ctl, "JUMPS: 3", centered_x(61, 0.48), 40, 0.48, 255, 145, 80)
    end)

    s.test("a second line pushes the counter down a row", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_jump_count = 2
        api.draw_objective_panel(GOAL, GRAVITY,
            { kind = "jump_limit", value = 3, label = "3 JUMPS" })
        at(ctl, "JUMPS: 2", centered_x(61, 0.48), 50, 0.48, 255, 145, 80)
    end)

    s.test("a coin toll shows the coins paid out of the coins owed", function()
        local api, ctl = fresh()
        gMarioStates[0].numCoins = 2
        api.draw_objective_panel(GOAL, { kind = "coin_toll", value = 5, label = "TOLL" },
            nil)
        at(ctl, "COINS: 2/5", centered_x(77, 0.48), 40, 0.48, 255, 145, 80)
    end)

    s.test("the coin toll counter stops at the toll it is paying", function()
        local api, ctl = fresh()
        gMarioStates[0].numCoins = 40
        api.draw_objective_panel(GOAL, { kind = "coin_toll", value = 5, label = "TOLL" },
            nil)
        at(ctl, "COINS: 5/5", centered_x(77, 0.48), 40, 0.48, 255, 145, 80)
    end)

    s.test("the jump counter wins when a round carries both counters", function()
        local api, ctl = fresh()
        gPlayerSyncTable[0].sh5_jump_count = 2
        gMarioStates[0].numCoins = 2
        api.draw_objective_panel(GOAL, { kind = "jump_limit", value = 3, label = "3 JUMPS" },
            { kind = "coin_toll", value = 5, label = "TOLL" })
        at(ctl, "JUMPS: 2", centered_x(61, 0.48), 50, 0.48, 255, 145, 80)
        absent(ctl, "COINS: 2/5")
    end)

    s.test("Chaos names the objective and counts down to the reroll", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        gGlobalSyncTable.sh5_chaos_modifier_seq = 1     -- starts the interval
        ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds - 5
        ctl.hud.text = {}
        api.draw_objective_panel(GOAL, LOCKED, GRAVITY)
        at(ctl, "LAST PLAYER STANDING", centered_x(160, 0.64), 3, 0.64, 255, 255, 255)
        at(ctl, "B LOCKED", centered_x(64, 0.52), 17, 0.52, 255, 215, 73)
        at(ctl, "HIGH GRAVITY", centered_x(96, 0.48), 29, 0.48, 255, 145, 80)
        at(ctl, "NEW MODIFIERS IN: 5", centered_x(149, 0.40), 41, 0.40, 200, 210, 230)
        absent(ctl, "WORLD")
    end)

    s.test("a reroll already due counts down to zero rather than past it", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        gGlobalSyncTable.sh5_chaos_modifier_seq = 1
        ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds * 4
        ctl.hud.text = {}
        api.draw_objective_panel(GOAL, LOCKED, nil)
        at(ctl, "NEW MODIFIERS IN: 0", centered_x(149, 0.40), 41, 0.40, 200, 210, 230)
    end)

    s.test("a machine that has not seen a reroll yet counts the whole interval",
    function()
        -- Zero would read as a reroll that is already due. A machine that has
        -- not been told one happened shows the interval it is waiting out.
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        ctl.hud.text = {}
        api.draw_objective_panel(GOAL, LOCKED, nil)
        at(ctl, "NEW MODIFIERS IN: 15", centered_x(157, 0.40), 41, 0.40, 200, 210, 230)
    end)

    s.test("an eliminated player is told so and shown nothing else", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        gPlayerSyncTable[0].sh5_chaos_eliminated = 1
        ctl.hud.text = {}
        api.draw_objective_panel(GOAL, LOCKED, GRAVITY)
        at(ctl, "LAST PLAYER STANDING", centered_x(160, 0.64), 3, 0.64, 255, 255, 255)
        at(ctl, "ELIMINATED - SPECTATING", centered_x(184, 0.50), 17, 0.50, 255, 100, 110)
        absent(ctl, "B LOCKED")
        absent(ctl, "NEW MODIFIERS IN: 5")
    end)

    s.test("Boss lists Bowser's three modifiers in their own colours", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.boss_mode
        api.set_language(0)
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        gGlobalSyncTable.sh5_boss_modifier_2 = 2
        gGlobalSyncTable.sh5_boss_modifier_3 = 3
        ctl.hud.text = {}
        api.draw_objective_panel(GOAL, LOCKED, GRAVITY)
        at(ctl, "BOWSER MODIFIERS", centered_x(128, 0.30), 3, 0.30, 200, 210, 230)
        at(ctl, "BOWSER: INSTANT KNOCKOUT", centered_x(189, 0.38), 14, 0.38, 255, 145, 80)
        at(ctl, "BOWSER: PARALYZING WAVES", centered_x(189, 0.38), 25, 0.38, 220, 95, 255)
        at(ctl, "BOWSER: VIOLET SPLITFIRE", centered_x(189, 0.38), 36, 0.38, 255, 220, 75)
        at(ctl, "B LOCKED", centered_x(64, 0.38), 48, 0.38, 104, 218, 255)
        at(ctl, "HIGH GRAVITY", centered_x(96, 0.36), 59, 0.36, 255, 145, 80)
        absent(ctl, "WORLD")
    end)

    s.test("Boss with no player modifier lists only Bowser's", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = api.boss_mode
        api.set_language(0)
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        ctl.hud.text = {}
        api.draw_objective_panel(GOAL, nil, nil)
        at(ctl, "BOWSER: INSTANT KNOCKOUT", centered_x(189, 0.38), 14, 0.38, 255, 145, 80)
        absent(ctl, "B LOCKED")
        absent(ctl, "CHOOSING YOUR NEXT GOAL...")
    end)

    -- the Gun Mod repaint ----------------------------------------------------

    --- Install a fake Gun Mod and put the darkness pulse on this very frame,
    -- which is the only condition under which StarHunt repaints anything of
    -- another mod's. Returns the api and ctl.
    local function gun_mod(weapon, second)
        local api, ctl = fresh()
        api.runtime.darkness_draw_frame = ctl.timer
        gGlobalSyncTable.gunModEnabled = true
        gNetworkPlayers[0].currActNum = 1
        _G.gunModApi = {
            cur_weapon = function() return weapon end,
            cur_dual_wield_weapon = function() return second end,
            get_render_hud = function() return true end,
        }
        return api, ctl
    end

    s.test("the repaint draws the weapon's ammo in the HUD font", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        api.draw_gun_mod_hud_compatibility()
        t.eq(ctl.hud.resolution, RESOLUTION_N64, "the N64 resolution was not selected")
        t.eq(ctl.hud.font, FONT_HUD, "the HUD font was not selected")
        at(ctl, "7/10", 1792, 974, 1, 255, 255, 255)
    end)

    s.test("a second weapon is drawn on the other side of the screen", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, { ammo = 2, maxAmmo = 6 })
        api.draw_gun_mod_hud_compatibility()
        at(ctl, "7/10", 1792, 974, 1, 255, 255, 255)
        at(ctl, "2/6", 16, 974, 1, 255, 255, 255)
    end)

    s.test("a weapon with no magazine has no ammo to show", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 0 }, { maxAmmo = nil })
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "nothing should have been written")
        t.eq(ctl.hud.resolution, RESOLUTION_N64, "the repaint still ran")
    end)

    s.test("a weapon that reports no ammo count shows an empty magazine", function()
        local api, ctl = gun_mod({ maxAmmo = 10 }, { maxAmmo = 6 })
        api.draw_gun_mod_hud_compatibility()
        at(ctl, "0/10", 1792, 974, 1, 255, 255, 255)
        at(ctl, "0/6", 16, 974, 1, 255, 255, 255)
    end)

    s.test("a second weapon with an empty magazine is not drawn", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, { ammo = 2, maxAmmo = 0 })
        api.draw_gun_mod_hud_compatibility()
        at(ctl, "7/10", 1792, 974, 1, 255, 255, 255)
        absent(ctl, "2/0")
    end)

    s.test("the crosshair is repainted in first person", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        _G.get_first_person_enabled = function() return true end
        _G.TEX_CROSSHAIR = "TEX_CROSSHAIR"
        api.draw_gun_mod_hud_compatibility()
        texture_is(ctl, 1, "TEX_CROSSHAIR", 956, 500.5, 0.5, 0.5, 255, 255, 0, 127)
    end)

    s.test("the crosshair is left off while the game is paused", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        _G.get_first_person_enabled = function() return true end
        _G.TEX_CROSSHAIR = "TEX_CROSSHAIR"
        _G.is_game_paused = function() return true end
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.texture_calls, 0, "the crosshair was drawn over the pause menu")
        at(ctl, "7/10", 1792, 974, 1, 255, 255, 255)
    end)

    s.test("outside first person there is no crosshair", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        _G.get_first_person_enabled = function() return false end
        _G.TEX_CROSSHAIR = "TEX_CROSSHAIR"
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.texture_calls, 0, "a crosshair was drawn in third person")
    end)

    s.test("without a dark pulse on this frame nothing is repainted", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        api.runtime.darkness_draw_frame = ctl.timer - 1
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "StarHunt repainted Gun Mod outside a pulse")
        t.is_nil(ctl.hud.resolution, "the resolution was changed anyway")
    end)

    s.test("a Gun Mod that is switched off is not repainted", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        gGlobalSyncTable.gunModEnabled = false
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "a disabled Gun Mod was repainted")
    end)

    s.test("a Gun Mod that is not rendering its own HUD is not repainted", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        _G.gunModApi.get_render_hud = function() return false end
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "a hidden Gun Mod HUD was repainted")
    end)

    s.test("a missing Gun Mod is not an error", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        _G.gunModApi = nil
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "something was drawn for a mod that is not there")
    end)

    s.test("half a Gun Mod is not enough to call into", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        _G.gunModApi.cur_dual_wield_weapon = nil
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "an incomplete Gun Mod API was called anyway")
    end)

    s.test("nothing is repainted over the act selector", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        _G.id_bhvActSelector = 4242
        ctl.objects[4242] = { oHealth = 0 }
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "the ammo was drawn over the star select screen")
    end)

    s.test("an act selector that is not on screen does not stop the repaint", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        -- The behavior id exists in every build; what stops the repaint is an
        -- act selector actually in the level, not the id being defined.
        _G.id_bhvActSelector = 4242
        api.draw_gun_mod_hud_compatibility()
        at(ctl, "7/10", 1792, 974, 1, 255, 255, 255)
    end)

    s.test("nothing is repainted on the act selector's own act number", function()
        local api, ctl = gun_mod({ ammo = 7, maxAmmo = 10 }, nil)
        gNetworkPlayers[0].currActNum = 99
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "the ammo was drawn on act 99")
    end)

    s.test("a Gun Mod holding no weapon has nothing to repaint", function()
        local api, ctl = gun_mod(nil, nil)
        api.draw_gun_mod_hud_compatibility()
        t.eq(#ctl.hud.text, 0, "ammo was drawn for no weapon")
        t.is_nil(ctl.hud.resolution, "the resolution was changed anyway")
    end)
end
