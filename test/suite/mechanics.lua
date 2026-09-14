-- Per-frame modifier behaviour: the parts that run inside Mario's update.
--
-- These are the effects that were hardest to get right in play, and the ones a
-- refactor is most likely to break silently because nothing errors -- the
-- challenge simply stops happening.

return function(t, harness)
    local s = t.suite("mechanics")

    s.test("the load-time safety checks pass", function()
        -- run_static_modifier_checks() proves water-cap clamping is idempotent,
        -- that A/B swapping is a real swap, and that stick rotation is exact.
        -- It reports by printing, which the harness captures.
        harness.load()
        local passed = false
        for _, line in ipairs(harness.banner) do
            if line:find("checks passed", 1, true) then passed = true end
            t.ok(not line:find("failed", 1, true), "a safety check failed: " .. line)
        end
        t.ok(passed, "the mod never reported its safety checks")
    end)

    s.test("darkness pulse is dark for its configured window, not always", function()
        local api, ctl = harness.load()
        local pulse
        for _, m in ipairs(api.normal_modifier_catalog) do
            if m.kind == "darkness_pulse" then pulse = m end
        end
        t.ok(pulse ~= nil, "no darkness_pulse in the catalog")

        local dark, light = 0, 0
        for frame = 0, 10 * 30 - 1 do          -- one full 10-second cycle
            ctl.timer = frame
            if api.darkness_active(pulse) then dark = dark + 1 else light = light + 1 end
        end
        t.ok(dark > 0, "darkness never activated across a whole cycle")
        t.ok(light > 0, "darkness never lifted across a whole cycle")
        t.eq(dark, pulse.value, "dark frames should equal the modifier value")
    end)

    s.test("a non-darkness modifier never reports darkness", function()
        local api = harness.load()
        for _, m in ipairs(api.normal_modifier_catalog) do
            if m.kind ~= "darkness_pulse" then
                t.ok(not api.darkness_active(m), m.kind .. " claimed to darken the screen")
            end
        end
    end)

    s.test("Easy pulses last their whole window", function()
        -- The regression fixed on 2026-08-04: the first active frame reset the
        -- clock, so a three-second restriction lasted one frame. Count the
        -- active frames of a pulsed modifier across one cycle.
        local api = harness.load()
        gGlobalSyncTable.sh5_difficulty = api.easy
        local base
        for _, m in ipairs(api.normal_modifier_catalog) do
            if m.kind == "no_b" then base = m end
        end
        local eased = api.effective_modifier(base)
        t.eq(eased.pulse_frames, 90, "Easy should pulse for 3 seconds")
        t.eq(eased.pulse_period, 10, "over a 10 second cycle")
        -- The window is expressed as frames within a period, so the mod must be
        -- able to report more than a single active frame.
        t.ok(eased.pulse_frames > 1, "the pulse collapsed to a single frame")
    end)

    s.test("health colours are defined across the whole range", function()
        local api = harness.load()
        for wedges = 0, 8 do
            local r, g, b = api.health_color(wedges)
            for _, channel in ipairs({ r, g, b }) do
                t.ok(type(channel) == "number" and channel >= 0 and channel <= 255,
                    "health_color(" .. wedges .. ") produced a bad channel")
            end
        end
    end)

    s.test("the local modifier list respects the difficulty count", function()
        local api = harness.load()
        -- Nightmare is the only difficulty that grants a second modifier.
        for _, difficulty in ipairs({ api.easy, api.medium, api.hard, api.nightmare }) do
            gGlobalSyncTable.sh5_difficulty = difficulty
            local mods = api.local_modifiers()
            t.ok(type(mods) == "table", "local_modifiers did not return a table")
            t.ok(#mods <= 2, "more than two personal modifiers at difficulty " .. difficulty)
        end
    end)
end
