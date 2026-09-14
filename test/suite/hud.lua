-- The HUD font has no colon.
--
-- FONT_HUD renders ':' as an 'X'. DEVELOPMENT_CHECKLIST.md makes this a
-- standing rule: no HUD text may reach djui_hud_print_text with a colon in it;
-- draw_hud_text splits the string and draws two small dots instead. Modifier
-- labels are full of colons ("CURSED FLOOR: 7 SEC"), so this is easy to
-- reintroduce and invisible until someone looks at a screenshot.

return function(t, harness)
    local s = t.suite("hud")

    local function fresh()
        local api, ctl = harness.load()
        ctl.hud.text = {}
        return api, ctl
    end

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
end
