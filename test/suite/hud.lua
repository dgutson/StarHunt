-- The HUD font has no colon.
--
-- FONT_HUD renders ':' as an 'X'. DEVELOPMENT_CHECKLIST.md makes this a
-- standing rule: no HUD text may reach djui_hud_print_text with a colon in it;
-- draw_hud_text splits the string and draws two small dots instead. Modifier
-- labels are full of colons ("CURSED FLOOR: 7 SEC"), so this is easy to
-- reintroduce and invisible until someone looks at a screenshot.
--
-- Everything below the colon tests was written when modules/hud.lua was
-- extracted. The text layer had four tests and the rest of the file had none:
-- counter_visibility, native_hud_visibility, hide_native_hud_before_render and
-- draw_darkness_behind were all published in STARHUNT_TEST_API and called by
-- no test at all, and four engine stubs made them unobservable anyway --
-- hud_get_value answered 0 for everything, hud_set_value threw the write away,
-- and hud_hide/hud_show did nothing, so the star and coin counters StarHunt
-- saves before a round and restores after it could have been deleted outright.
--
-- Two numbers from the harness are used throughout: djui_hud_measure_text is
-- eight pixels per character, and the screen is 1920 x 1009.

return function(t, harness)
    local s = t.suite("hud")

    local function fresh()
        local api, ctl = harness.load()
        ctl.hud.text = {}
        ctl.hud.colors = {}
        return api, ctl
    end

    --- Give the local player the goal and modifier slot that carry DARKNESS
    -- PULSE, and start a round on that goal's level. Returns the effective
    -- modifier, so a test can ask darkness_active about the same table the
    -- drawing code will read.
    local function arm_darkness(api, ctl)
        for goal_id, goal in ipairs(api.goals) do
            for index, m in ipairs(goal.mods) do
                if m.kind == "darkness_pulse" then
                    gPlayerSyncTable[0].sh5_goal = goal_id
                    gPlayerSyncTable[0].sh5_modifier = index
                    gPlayerSyncTable[0].sh5_modifier_2 = 0
                    ctl.begin_round(api, api.normal_mode, api.medium, goal.level)
                    gNetworkPlayers[0].currActNum = goal.act
                    return api.local_modifiers()[1]
                end
            end
        end
        t.fail("no goal in the catalog allows darkness_pulse")
    end

    -- the colon rule ---------------------------------------------------------

    s.test("no colon ever reaches the HUD font", function()
        local api, ctl = fresh()
        api.draw_hud_text("SCORE: 12", 10, 10, 1, 255, 255, 255)
        t.ok(#ctl.hud.text > 0, "nothing was drawn at all")
        for _, call in ipairs(ctl.hud.text) do
            t.ok(not tostring(call.text):find(":", 1, true),
                "a colon was printed with the HUD font: " .. tostring(call.text))
        end
    end)

    s.test("the colon is drawn as two dots", function()
        local api, ctl = fresh()
        api.draw_hud_text("A:B", 0, 0, 1, 255, 255, 255)
        local dots = 0
        for _, call in ipairs(ctl.hud.text) do
            if call.text == "." then dots = dots + 1 end
        end
        -- draw_hud_text paints a shadow layer and a colour layer, two dots each.
        t.eq(dots, 4, "expected two dots per layer over two layers")
    end)

    s.test("every modifier label survives the colon rule", function()
        -- Labels are the main source of colons on screen.
        local api, ctl = fresh()
        for _, m in ipairs(api.normal_modifier_catalog) do
            ctl.hud.text = {}
            api.draw_hud_text(m.label, 0, 0, 1, 255, 255, 255)
            for _, call in ipairs(ctl.hud.text) do
                t.ok(not tostring(call.text):find(":", 1, true),
                    "label '" .. m.label .. "' leaked a colon to the HUD font")
            end
        end
    end)

    s.test("text without a colon is drawn in one piece per layer", function()
        local api, ctl = fresh()
        api.draw_hud_text("PLAIN", 0, 0, 1, 255, 255, 255)
        local plain = 0
        for _, call in ipairs(ctl.hud.text) do
            if call.text == "PLAIN" then plain = plain + 1 end
        end
        t.eq(plain, 2, "expected the shadow layer and the colour layer")
    end)

    s.test("drawing the full HUD never leaks a colon", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, api.selected_mode(), api.medium)
        ctl.hud.text = {}
        pcall(api.draw_hud)
        for _, call in ipairs(ctl.hud.text) do
            t.ok(not tostring(call.text):find(":", 1, true),
                "draw_hud printed a colon: " .. tostring(call.text))
        end
    end)

    s.test("health bar renders for every health value", function()
        local api = harness.load()
        for wedges = 0, 8 do
            local got = api.health_wedges(wedges * 0x100)
            t.ok(type(got) == "number" and got >= 0 and got <= 8,
                "health_wedges out of range for " .. wedges)
        end
    end)

    -- where the dots land ----------------------------------------------------

    s.test("a colon's dots are drawn between the two chunks, not over them", function()
        local api, ctl = fresh()
        api.draw_hud_text("A:B", 0, 0, 1, 10, 20, 30)
        local c = ctl.hud.text
        t.eq(#c, 8, "two layers of one letter, two dots and one letter")
        -- The shadow layer comes first, one pixel down and to the right.
        t.eq(c[1].text, "A")  t.eq(c[1].x, 1)   t.eq(c[1].y, 1)
        t.eq(c[2].text, ".")  t.eq(c[2].x, 10)  t.eq(c[2].y, -3)
        t.eq(c[3].text, ".")  t.eq(c[3].x, 10)  t.eq(c[3].y, 7)
        t.eq(c[4].text, "B")  t.eq(c[4].x, 14)  t.eq(c[4].y, 1)
        -- Then the colour layer at the position the caller asked for.
        t.eq(c[5].text, "A")  t.eq(c[5].x, 0)   t.eq(c[5].y, 0)
        t.eq(c[6].text, ".")  t.eq(c[6].x, 9)   t.eq(c[6].y, -4)
        t.eq(c[7].text, ".")  t.eq(c[7].x, 9)   t.eq(c[7].y, 6)
        t.eq(c[8].text, "B")  t.eq(c[8].x, 13)  t.eq(c[8].y, 0)
    end)

    s.test("the dots and the text after them scale with the text", function()
        local api, ctl = fresh()
        api.draw_hud_text("A:B", 100, 50, 2, 255, 255, 255)
        -- The colour layer is the second half of the calls.
        local c = ctl.hud.text
        t.eq(c[5].x, 100, "the first chunk moved")
        t.eq(c[6].x, 118, "one character at scale 2, then a scale-wide gap")
        t.eq(c[6].y, 42, "the upper dot sits four scaled pixels high")
        t.eq(c[7].y, 62, "the lower dot sits six scaled pixels low")
        t.eq(c[8].x, 126, "the second chunk clears the five-pixel colon at scale 2")
        t.near(c[6].scale, 1.28, 1e-9, "the upper dot is printed smaller than the text")
        t.near(c[7].scale, 1.28, 1e-9, "the lower dot is printed smaller than the text")
    end)

    s.test("an empty chunk beside a colon is not printed at all", function()
        local api, ctl = fresh()
        api.draw_hud_text(":A", 0, 0, 1, 255, 255, 255)
        for _, call in ipairs(ctl.hud.text) do
            t.ne(call.text, "", "an empty string was printed")
        end
        t.eq(#ctl.hud.text, 6, "expected two dots and one letter per layer")
    end)

    s.test("the shadow layer is drawn black and slightly transparent", function()
        local api, ctl = fresh()
        api.draw_hud_text("PLAIN", 0, 0, 1, 10, 20, 30)
        t.eq(#ctl.hud.colors, 2, "one colour per layer")
        local shadow, colour = ctl.hud.colors[1], ctl.hud.colors[2]
        t.eq(shadow.r, 0)  t.eq(shadow.g, 0)  t.eq(shadow.b, 0)
        t.eq(shadow.a, 220, "the shadow's alpha at full opacity")
        t.eq(colour.r, 10) t.eq(colour.g, 20) t.eq(colour.b, 30)
        t.eq(colour.a, 255, "text with no alpha given is opaque")
    end)

    s.test("a caller's alpha reaches both layers", function()
        local api, ctl = fresh()
        api.draw_hud_text("PLAIN", 0, 0, 1, 10, 20, 30, 100)
        t.eq(ctl.hud.colors[1].a, 86, "the shadow keeps its share of the alpha")
        t.eq(ctl.hud.colors[2].a, 100, "the text's own alpha")
    end)

    -- measuring and centering ------------------------------------------------

    s.test("a colon is measured as the five pixels it is drawn in", function()
        local api = harness.load()
        t.eq(api.measure_hud_text("AB"), 16, "two plain characters")
        t.eq(api.measure_hud_text(""), 0, "the empty string")
        t.eq(api.measure_hud_text("A:B"), 21, "8 + 5 + 8")
        t.eq(api.measure_hud_text(":"), 5, "a colon on its own")
        t.eq(api.measure_hud_text("A::B"), 26, "each colon costs five")
        t.eq(api.measure_hud_text("AB:"), 21, "a trailing colon still costs five")
    end)

    s.test("centered text is centered on what it measures", function()
        local api, ctl = fresh()
        api.draw_centered_hud_text("A:B", 40, 1, 255, 255, 255)
        local colour = ctl.hud.text[5]
        t.eq(colour.text, "A", "the colour layer starts with the first chunk")
        t.eq(colour.x, (1920 - 21) * 0.5, "the string was not centered on 21 pixels")
        t.eq(colour.y, 40, "the caller's y was not used")
    end)

    s.test("the objective panel is kept between the score and timer cards", function()
        local api, ctl = harness.load()
        -- 1920 wide: centre 960, right card 112 in from the edge, left card 90.
        t.eq(api.objective_text_max_width(), 1696, "a star race")
        ctl.begin_round(api, api.team_mode, api.medium)
        t.eq(api.objective_text_max_width(), 1682, "Team mode's wider left card")
        ctl.begin_round(api, api.boss_mode, api.medium)
        t.eq(api.objective_text_max_width(), 1682, "Boss mode's wider left card")
    end)

    s.test("a screen too narrow for both cards still leaves a minimum width", function()
        local api, ctl = harness.load()
        ctl.screen.w = 100
        t.eq(api.objective_text_max_width(), 24,
            "the two guards overlap and the width went negative")
    end)

    s.test("text too wide for its box is shrunk to fit it", function()
        local api, ctl = fresh()
        -- "ABCD" measures 32, so scale 2 would need 64 pixels.
        api.draw_scaled_centered_text("ABCD", 60, 2, 32, 255, 255, 255)
        local colour = ctl.hud.text[2]
        t.eq(colour.scale, 1, "the text was not shrunk to its box")
        t.eq(colour.x, (1920 - 32) * 0.5, "the shrunken text was not re-centered")
    end)

    s.test("text that fits keeps the scale it asked for", function()
        local api, ctl = fresh()
        api.draw_scaled_centered_text("ABCD", 60, 2, 1000, 255, 255, 255)
        local colour = ctl.hud.text[2]
        t.eq(colour.scale, 2, "a string that fits was shrunk anyway")
        t.eq(colour.x, (1920 - 64) * 0.5, "centered on the wrong width")
    end)

    s.test("the clock reads minutes and zero-padded seconds", function()
        local api = harness.load()
        t.eq(api.format_remaining_time(0), "0:00", "an expired clock")
        t.eq(api.format_remaining_time(5), "0:05", "the leading zero")
        t.eq(api.format_remaining_time(59), "0:59", "one second before the minute")
        t.eq(api.format_remaining_time(60), "1:00", "exactly one minute")
        t.eq(api.format_remaining_time(65), "1:05", "a minute and five seconds")
        t.eq(api.format_remaining_time(754), "12:34", "a long round")
    end)

    -- the native star and coin counters --------------------------------------

    s.test("the native counters are hidden for the round and then put back", function()
        local api, ctl = harness.load()
        -- The player arrives with both counters on and one unrelated flag set.
        local before = HUD_DISPLAY_FLAG_STAR_COUNT | HUD_DISPLAY_FLAG_COIN_COUNT | 0x0001
        ctl.hud.values[HUD_DISPLAY_FLAGS] = before
        ctl.begin_round(api, api.normal_mode, api.medium)

        api.counter_visibility()
        local during = ctl.hud.values[HUD_DISPLAY_FLAGS]
        t.eq(during & HUD_DISPLAY_FLAG_STAR_COUNT, 0, "the star counter was left on")
        t.eq(during & HUD_DISPLAY_FLAG_COIN_COUNT, 0, "the coin counter was left on")
        t.eq(during & 0x0001, 0x0001, "an unrelated HUD flag was cleared as well")

        -- Later frames of the same round must not re-save the cleared flags.
        api.counter_visibility()
        api.counter_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.counter_visibility()
        t.eq(ctl.hud.values[HUD_DISPLAY_FLAGS], before,
            "the counters the player had before the round were not restored")
    end)

    s.test("a counter the player had already turned off stays off", function()
        local api, ctl = harness.load()
        ctl.hud.values[HUD_DISPLAY_FLAGS] = HUD_DISPLAY_FLAG_COIN_COUNT
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.counter_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.counter_visibility()
        t.eq(ctl.hud.values[HUD_DISPLAY_FLAGS], HUD_DISPLAY_FLAG_COIN_COUNT,
            "StarHunt turned on a counter the player had off")
    end)

    s.test("outside a round the counters are left alone", function()
        local api, ctl = harness.load()
        api.counter_visibility()
        t.is_nil(ctl.hud.values[HUD_DISPLAY_FLAGS],
            "the display flags were written with no round running")
    end)

    s.test("a second round saves the flags it actually starts from", function()
        local api, ctl = harness.load()
        ctl.hud.values[HUD_DISPLAY_FLAGS] =
            HUD_DISPLAY_FLAG_STAR_COUNT | HUD_DISPLAY_FLAG_COIN_COUNT
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.counter_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.counter_visibility()

        -- Between the rounds the player turns the coin counter off.
        ctl.hud.values[HUD_DISPLAY_FLAGS] = HUD_DISPLAY_FLAG_STAR_COUNT
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.counter_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.counter_visibility()
        t.eq(ctl.hud.values[HUD_DISPLAY_FLAGS], HUD_DISPLAY_FLAG_STAR_COUNT,
            "the second round restored the first round's flags")
    end)

    -- the native HUD itself --------------------------------------------------

    s.test("the native HUD is hidden for the round and shown again after it", function()
        local api, ctl = harness.load()
        t.eq(ctl.hud.hidden, false, "the harness starts with a visible HUD")
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.native_hud_visibility()
        t.eq(ctl.hud.hidden, true, "the native HUD was left visible during a round")
        api.native_hud_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.native_hud_visibility()
        t.eq(ctl.hud.hidden, false, "the native HUD was not shown again after the round")
    end)

    s.test("a HUD that was already hidden stays hidden after the round", function()
        local api, ctl = harness.load()
        ctl.hud.hidden = true          -- another mod, or the player, hid it first
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.native_hud_visibility()
        t.eq(ctl.hud.hidden, true, "it should still be hidden during the round")
        gGlobalSyncTable.sh5_active = 0
        api.native_hud_visibility()
        t.eq(ctl.hud.hidden, true, "StarHunt showed a HUD the player had hidden")
    end)

    s.test("outside a round StarHunt does not touch the native HUD", function()
        local api, ctl = harness.load()
        ctl.hud.hidden = true
        api.native_hud_visibility()
        t.eq(ctl.hud.hidden, true,
            "a HUD hidden by someone else was shown with no round running")
    end)

    s.test("once the round is over StarHunt stops deciding the HUD's visibility", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.native_hud_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.native_hud_visibility()
        ctl.hud.hidden = true          -- the player hides it again afterwards
        api.native_hud_visibility()
        t.eq(ctl.hud.hidden, true, "the HUD was shown again after the round had ended")
    end)

    s.test("a second round reads the HUD state it actually starts from", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.native_hud_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.native_hud_visibility()

        ctl.hud.hidden = true          -- hidden between the two rounds
        ctl.begin_round(api, api.normal_mode, api.medium)
        api.native_hud_visibility()
        gGlobalSyncTable.sh5_active = 0
        api.native_hud_visibility()
        t.eq(ctl.hud.hidden, true, "the second round restored the first round's state")
    end)

    -- DARKNESS PULSE, behind every HUD ---------------------------------------

    s.test("the darkness covers the screen once per frame while the pulse is dark", function()
        local api, ctl = harness.load()
        local m = arm_darkness(api, ctl)
        api.runtime.modifier_start_frame = 0
        ctl.timer = 299                -- the last frame of the ten-second cycle
        t.ok(api.darkness_active(m), "the pulse should be dark on this frame")

        ctl.hud.rects = 0
        ctl.hud.colors = {}
        t.eq(api.draw_darkness_behind(), true, "it did not report having drawn")
        t.eq(ctl.hud.rects, 1, "the rectangle was not drawn")
        t.eq(ctl.hud.resolution, RESOLUTION_N64, "drawn in the wrong resolution")
        t.eq(ctl.hud.colors[1].a, 248, "the darkness is nearly opaque")
        t.eq(ctl.hud.last_rect.x, 0, "the rectangle does not start at the left edge")
        t.eq(ctl.hud.last_rect.y, 0, "the rectangle does not start at the top edge")
        t.eq(ctl.hud.last_rect.w, ctl.screen.w, "it does not cover the screen width")
        t.eq(ctl.hud.last_rect.h, ctl.screen.h, "it does not cover the screen height")
        t.eq(api.runtime.darkness_draw_frame, 299, "the drawn frame was not recorded")

        t.eq(api.draw_darkness_behind(), true, "a repeat call must still report drawn")
        t.eq(ctl.hud.rects, 1, "the rectangle was drawn twice in one frame")

        ctl.timer = 599                -- one cycle later, dark again
        t.eq(api.draw_darkness_behind(), true, "the next dark frame did not draw")
        t.eq(ctl.hud.rects, 2, "the rectangle was not redrawn on a new frame")
    end)

    s.test("nothing is drawn behind the HUD without an active dark pulse", function()
        local api, ctl = harness.load()
        ctl.hud.rects = 0
        t.eq(api.draw_darkness_behind(), false, "reported drawing with no round at all")

        local m = arm_darkness(api, ctl)
        api.runtime.modifier_start_frame = 0
        ctl.timer = 0                  -- the bright part of the cycle
        t.eq(api.darkness_active(m), false, "the pulse should be bright on this frame")
        t.eq(api.draw_darkness_behind(), false, "reported drawing while bright")

        ctl.timer = 299                -- dark, but the round is over
        gGlobalSyncTable.sh5_active = 0
        t.eq(api.draw_darkness_behind(), false, "drew the darkness outside a round")
        t.eq(ctl.hud.rects, 0, "a rectangle was drawn")
    end)

    s.test("the behind-HUD pass draws the darkness and hides the native HUD", function()
        local api, ctl = harness.load()
        arm_darkness(api, ctl)
        api.runtime.modifier_start_frame = 0
        ctl.timer = 299
        ctl.hud.rects = 0
        api.hide_native_hud_before_render()
        t.eq(ctl.hud.rects, 1, "the darkness was not drawn from the behind-HUD hook")
        t.eq(ctl.hud.hidden, true, "the native HUD was not hidden")
    end)

    s.test("the behind-HUD pass leaves the HUD alone outside a round", function()
        local api, ctl = harness.load()
        api.hide_native_hud_before_render()
        t.eq(ctl.hud.hidden, false, "the native HUD was hidden with no round running")
    end)
end
