-- Nightmare and Chaos hand out two modifiers at once, so pairs must not
-- cancel each other or combine into an unwinnable lock.
--
-- DEVELOPMENT_CHECKLIST.md records the bug this guards: pair validation used to
-- depend on argument order, so reversing first and second let a forbidden
-- combination through. All 496 unordered pairs are checked both ways.

return function(t, harness)
    local s = t.suite("pairing")
    local api = harness.load()

    local catalog = api.normal_modifier_catalog

    local function by_kind(kind)
        for _, m in ipairs(catalog) do
            if m.kind == kind then return m end
        end
        t.fail("no such modifier in the catalog: " .. kind)
    end

    s.test("pair validation is symmetric across all 496 pairs", function()
        local pairs_checked = 0
        for i = 1, #catalog do
            for j = i + 1, #catalog do
                local a, b = catalog[i], catalog[j]
                local forward = api.chaos_pair_allowed(a, b) and true or false
                local backward = api.chaos_pair_allowed(b, a) and true or false
                t.eq(backward, forward, string.format(
                    "%s + %s is allowed=%s but %s + %s is allowed=%s",
                    a.kind, b.kind, tostring(forward), b.kind, a.kind, tostring(backward)))
                pairs_checked = pairs_checked + 1
            end
        end
        t.eq(pairs_checked, 496, "expected 32 choose 2 = 496 pairs")
    end)

    s.test("a modifier is never paired with itself", function()
        for _, m in ipairs(catalog) do
            t.ok(not api.chaos_pair_allowed(m, m), m.kind .. " was allowed to pair with itself")
        end
    end)

    s.test("documented conflicting pairs stay forbidden", function()
        -- Each of these was found in play and written into the changelog.
        local forbidden = {
            -- a challenge that forces you to stop, against one that punishes stopping
            { "periodic_freeze", "keep_moving" },
            { "periodic_freeze", "floor_doom" },
            -- control reversals that cancel each other out
            { "control_pulse", "mirrored_steering" },
            { "control_pulse", "air_mirror" },
            -- a coin boost against modifiers that would erase or invert it
            { "coin_surge", "speed_cap" },
            { "coin_surge", "slow_pulse" },
            { "coin_surge", "coin_weight" },
        }
        for _, combo in ipairs(forbidden) do
            local a, b = by_kind(combo[1]), by_kind(combo[2])
            t.ok(not api.chaos_pair_allowed(a, b),
                combo[1] .. " + " .. combo[2] .. " should be rejected")
            t.ok(not api.chaos_pair_allowed(b, a),
                combo[2] .. " + " .. combo[1] .. " should be rejected (reversed)")
        end
    end)

    s.test("Nightmare can find a legal second modifier for every goal", function()
        -- If any star had no compatible pair, Nightmare would either hand out a
        -- broken combination or silently fall back to one modifier.
        -- pick_second_modifier returns an index into goal.mods, and 0 for
        -- "nothing compatible" -- not nil.
        gGlobalSyncTable.sh5_difficulty = api.nightmare
        for index, goal in ipairs(api.goals) do
            local found = false
            for first = 1, #goal.mods do
                if api.pick_second_modifier(goal, first) ~= 0 then
                    found = true
                    break
                end
            end
            t.ok(found, "goal " .. index .. " (" .. goal.title
                .. ") has no compatible Nightmare pair")
        end
    end)

    s.test("the second modifier is always distinct and audited", function()
        gGlobalSyncTable.sh5_difficulty = api.nightmare
        local paired = 0
        for index, goal in ipairs(api.goals) do
            for first = 1, #goal.mods do
                local slot = api.pick_second_modifier(goal, first)
                if slot ~= 0 then
                    local second = goal.mods[slot]
                    t.ok(second ~= nil, "goal " .. index .. " returned slot " .. slot
                        .. ", which is not a modifier")
                    t.ne(slot, first, "goal " .. index .. " paired a modifier with itself")
                    t.ne(second.kind, goal.mods[first].kind, "goal " .. index
                        .. " paired " .. second.kind .. " with itself")
                    t.ok(api.effective_modifier_for_goal(goal, second) ~= nil,
                        "goal " .. index .. " picked " .. second.kind
                        .. ", which the audit rejects at Nightmare")
                    paired = paired + 1
                end
            end
        end
        t.ok(paired > 0, "no pair was ever formed, so nothing was checked")
    end)

    s.test("pairs allowed at Nightmare are allowed in both orders on real goals", function()
        gGlobalSyncTable.sh5_difficulty = api.nightmare
        for index, goal in ipairs(api.goals) do
            for first = 1, #goal.mods do
                local slot = api.pick_second_modifier(goal, first)
                if slot ~= 0 then
                    local second = goal.mods[slot]
                    t.ok(api.chaos_pair_allowed(second, goal.mods[first]),
                        "goal " .. index .. ": " .. goal.mods[first].kind .. " + "
                        .. second.kind .. " passes one way but not the other")
                end
            end
        end
    end)
end
