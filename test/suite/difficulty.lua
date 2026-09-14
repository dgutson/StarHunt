-- Difficulty is an axis of its own, applied on top of the audited catalog.
--
-- The rule that matters most: a difficulty may make a modifier harsher, but it
-- may never push one past the audit. effective_modifier_for_goal() re-runs the
-- scaled value through the audit and returns nil when it no longer fits.

return function(t, harness)
    local s = t.suite("difficulty")
    local api = harness.load()

    local D = { easy = api.easy, medium = api.medium, hard = api.hard, nightmare = api.nightmare }

    local function at(difficulty, fn)
        gGlobalSyncTable.sh5_difficulty = difficulty
        return fn()
    end

    -- The numeric emergency limits of audit stage 4, which no difficulty may
    -- cross. Each entry is {comparison, bound}.
    local LIMITS = {
        speed_cap      = { "min", 32 },
        low_jump       = { "min", 38 },
        high_gravity   = { "max", 1.1 },
        air_brake      = { "min", 60 },
        jump_cooldown  = { "max", 26 },
        slow_pulse     = { "min", 32 },
        momentum_burst = { "max", 14 },
        control_pulse  = { "max", 45 },
        coin_weight    = { "min", 54 },
        gravity_wave   = { "max", 0.6 },
        overheat       = { "min", 2 },
        coin_surge     = { "max", 20 },
    }

    s.test("difficulty selection clamps to the four known levels", function()
        for _, value in ipairs({ -5, 0, 1, 2, 3, 99 }) do
            gGlobalSyncTable.sh5_difficulty = value
            local got = api.selected_difficulty()
            t.ok(got >= D.easy and got <= D.nightmare,
                "difficulty " .. value .. " resolved to " .. tostring(got))
        end
    end)

    s.test("Normal preserves the catalog values exactly", function()
        -- BALANCE_AUDIT.md: "Normal exactly preserves v0.9 modifier values".
        at(D.medium, function()
            for _, base in ipairs(api.normal_modifier_catalog) do
                local got = api.effective_modifier(base)
                t.eq(got.value, base.value, "Normal changed " .. base.kind)
                t.eq(got.kind, base.kind)
                t.is_nil(got.pulse_frames, base.kind .. " gained a pulse on Normal")
            end
        end)
    end)

    s.test("Easy turns permanent binary restrictions into 3-second pulses", function()
        at(D.easy, function()
            local pulsed = { no_b = true, no_z = true, reverse_controls = true,
                             swap_ab = true, mirrored_steering = true }
            local found = 0
            for _, base in ipairs(api.normal_modifier_catalog) do
                if pulsed[base.kind] then
                    local got = api.effective_modifier(base)
                    t.eq(got.pulse_period, 10, base.kind .. " pulse period")
                    t.eq(got.pulse_frames, 90, base.kind .. " pulse length (3s at 30fps)")
                    found = found + 1
                end
            end
            t.eq(found, 5, "expected five binary restrictions in the catalog")
        end)
    end)

    s.test("Easy gives slippery and air mirror a 4-second pulse", function()
        at(D.easy, function()
            for _, base in ipairs(api.normal_modifier_catalog) do
                if base.kind == "slippery" or base.kind == "air_mirror" then
                    local got = api.effective_modifier(base)
                    t.eq(got.pulse_period, 10, base.kind .. " pulse period")
                    t.eq(got.pulse_frames, 120, base.kind .. " pulse length (4s at 30fps)")
                end
            end
        end)
    end)

    s.test("fragile health scales with difficulty", function()
        local caps = { [D.easy] = 0x600, [D.hard] = 0x300, [D.nightmare] = 0x200 }
        for _, base in ipairs(api.normal_modifier_catalog) do
            if base.kind == "fragile" then
                for difficulty, expected in pairs(caps) do
                    at(difficulty, function()
                        t.eq(api.effective_modifier(base).health_cap, expected)
                    end)
                end
            end
        end
    end)

    s.test("freeze length and damage step up with difficulty", function()
        local base = api.normal_modifier_catalog[1]
        local freeze = { [D.easy] = 15, [D.hard] = 36, [D.nightmare] = 54 }
        local damage = { [D.easy] = 0x80, [D.hard] = 0x180, [D.nightmare] = 0x200 }
        for difficulty, expected in pairs(freeze) do
            at(difficulty, function()
                t.eq(api.effective_modifier(base).freeze_frames, expected, "freeze frames")
                t.eq(api.effective_modifier(base).damage_amount, damage[difficulty], "damage")
            end)
        end
    end)

    s.test("values stay integral except for the two gravity multipliers", function()
        for _, difficulty in pairs(D) do
            at(difficulty, function()
                for _, base in ipairs(api.normal_modifier_catalog) do
                    local got = api.effective_modifier(base)
                    if base.kind ~= "high_gravity" and base.kind ~= "gravity_wave" then
                        t.eq(got.value, math.floor(got.value),
                            base.kind .. " is fractional at difficulty " .. tostring(difficulty))
                    end
                end
            end)
        end
    end)

    s.test("difficulty is monotonic for every modifier", function()
        -- Whatever direction "harder" runs in for a given modifier, the four
        -- levels must move that way consistently. A modifier that got easier
        -- from Hard to Nightmare would be a balance inversion.
        for _, base in ipairs(api.normal_modifier_catalog) do
            local v = {}
            for name, difficulty in pairs(D) do
                v[name] = at(difficulty, function() return api.effective_modifier(base).value end)
            end
            -- A binary restriction (B locked, controls reversed, ...) carries no
            -- magnitude: its catalog value is 0 and difficulty expresses itself
            -- through pulse_frames instead. Only graded modifiers can be ordered.
            if base.value ~= 0 and v.medium ~= v.nightmare then
                local harder_is_higher = v.nightmare > v.medium
                local order = { v.easy, v.medium, v.hard, v.nightmare }
                for i = 1, #order - 1 do
                    if harder_is_higher then
                        t.ok(order[i] <= order[i + 1], base.kind ..
                            " is not monotonic: " .. table.concat({ tostring(order[1]),
                            tostring(order[2]), tostring(order[3]), tostring(order[4]) }, " -> "))
                    else
                        t.ok(order[i] >= order[i + 1], base.kind ..
                            " is not monotonic: " .. table.concat({ tostring(order[1]),
                            tostring(order[2]), tostring(order[3]), tostring(order[4]) }, " -> "))
                    end
                end
            end
        end
    end)

    s.test("no difficulty pushes a modifier past the stage-4 safety limits", function()
        -- The property the whole audit exists to guarantee, checked across
        -- every goal, every approved modifier and all four difficulties.
        local checked, rejected = 0, 0
        for _, difficulty in pairs(D) do
            at(difficulty, function()
                for _, goal in ipairs(api.goals) do
                    for _, base in ipairs(goal.mods) do
                        local got = api.effective_modifier_for_goal(goal, base)
                        if got == nil then
                            rejected = rejected + 1
                        else
                            checked = checked + 1
                            local limit = LIMITS[got.kind]
                            if limit then
                                if limit[1] == "min" then
                                    t.ok(got.value >= limit[2], string.format(
                                        "%s on %s at difficulty %d is %s, below the %s floor",
                                        got.kind, goal.title, difficulty, tostring(got.value),
                                        tostring(limit[2])))
                                else
                                    t.ok(got.value <= limit[2], string.format(
                                        "%s on %s at difficulty %d is %s, above the %s ceiling",
                                        got.kind, goal.title, difficulty, tostring(got.value),
                                        tostring(limit[2])))
                                end
                            end
                        end
                    end
                end
            end)
        end
        t.ok(checked > 0, "nothing was checked")
        t.ok(rejected > 0, "no scaled modifier was ever rejected, so "
            .. "effective_modifier_for_goal is not re-running the audit")
    end)

    s.test("a rejected scaling returns nil rather than an unsafe value", function()
        -- Proves the re-audit is wired to the goal, not just to the catalog.
        local found = false
        at(D.nightmare, function()
            for _, goal in ipairs(api.goals) do
                for _, base in ipairs(goal.mods) do
                    if api.effective_modifier_for_goal(goal, base) == nil then found = true end
                end
            end
        end)
        t.ok(found, "Nightmare never rejected a scaled modifier on any goal")
    end)
end
