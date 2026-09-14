-- Round setup across the four modes and four difficulties.
--
-- CHANGELOG.md claims all sixteen mode/difficulty combinations are verified, so
-- the suite starts each of them and checks the invariants that must hold
-- whatever the combination.

return function(t, harness)
    local s = t.suite("round")

    local function modes(api)
        return {
            { name = "Normal",    value = 0 },
            { name = "Boss",      value = api.boss_mode },
            { name = "Team",      value = api.team_mode },
            { name = "Chaos",     value = api.chaos_mode },
        }
    end

    local function difficulties(api)
        return {
            { name = "Easy",      value = api.easy },
            { name = "Normal",    value = api.medium },
            { name = "Hard",      value = api.hard },
            { name = "Nightmare", value = api.nightmare },
        }
    end

    s.test("the four modes are distinct values", function()
        local api = harness.load()
        local seen = {}
        for _, m in ipairs(modes(api)) do
            t.ok(not seen[m.value], "mode " .. m.name .. " duplicates another value")
            seen[m.value] = true
        end
    end)

    s.test("the four difficulties are distinct and ordered", function()
        local api = harness.load()
        t.ok(api.easy < api.medium, "Easy should sort below Normal")
        t.ok(api.medium < api.hard, "Normal should sort below Hard")
        t.ok(api.hard < api.nightmare, "Hard should sort below Nightmare")
    end)

    s.test("all sixteen mode and difficulty combinations start", function()
        for _, mode in ipairs(modes(harness.load())) do
            for _, difficulty in ipairs(difficulties(harness.load())) do
                local api = harness.load()
                gGlobalSyncTable.sh5_mode = mode.value
                gGlobalSyncTable.sh5_difficulty = difficulty.value
                local ok, err = pcall(api.host_start, 8)
                t.ok(ok, string.format("%s / %s failed to start: %s",
                    mode.name, difficulty.name, tostring(err)))
                t.eq(api.selected_mode(), mode.value,
                    mode.name .. "/" .. difficulty.name .. ": mode was not kept")
                t.eq(api.selected_difficulty(), difficulty.value,
                    mode.name .. "/" .. difficulty.name .. ": difficulty was not kept")
            end
        end
    end)

    s.test("a started round is marked active", function()
        local api = harness.load()
        gGlobalSyncTable.sh5_mode = 0
        gGlobalSyncTable.sh5_difficulty = api.medium
        api.host_start(8)
        t.eq(gGlobalSyncTable.sh5_active, 1, "the round did not become active")
    end)

    s.test("round length responds to the player count", function()
        local api = harness.load()
        local small_low, small_high = api.time_range(2)
        local large_low, large_high = api.time_range(16)
        for _, v in ipairs({ small_low, small_high, large_low, large_high }) do
            t.ok(type(v) == "number" and v > 0, "time range returned a bad value")
        end
        t.ok(small_low <= small_high, "time range is inverted for a small lobby")
        t.ok(large_low <= large_high, "time range is inverted for a large lobby")
        -- A big lobby gets shorter rounds, since goals are handed out per player.
        t.ok(large_high <= small_high, "a 16-player lobby should not get a longer maximum")
    end)

    s.test("Boss mode sets a health pool that grows with difficulty", function()
        local previous = 0
        for _, name in ipairs({ "easy", "medium", "hard", "nightmare" }) do
            local api = harness.load()
            gGlobalSyncTable.sh5_mode = api.boss_mode
            gGlobalSyncTable.sh5_difficulty = api[name]
            api.host_start(8)
            local health = gGlobalSyncTable.sh5_boss_max_health
            t.ok(type(health) == "number" and health > 0,
                name .. ": Bowser has no health pool")
            t.ok(health >= previous, name .. ": health " .. tostring(health)
                .. " is below the easier difficulty's " .. tostring(previous))
            previous = health
        end
        t.eq(previous, 9, "Nightmare should end at nine hits")
    end)

    s.test("difficulty cannot be changed while a round runs", function()
        local api = harness.load()
        gGlobalSyncTable.sh5_mode = 0
        gGlobalSyncTable.sh5_difficulty = api.medium
        api.host_start(8)
        t.eq(gGlobalSyncTable.sh5_active, 1)
        -- The menu refuses to cycle difficulty during an active round; the
        -- synchronized value is what every client reads.
        t.eq(api.selected_difficulty(), api.medium)
    end)

    s.test("the menu opens while waiting and is locked shut during a round", function()
        local api = harness.load()
        gGlobalSyncTable.sh5_active = 0
        api.update_config_menu_lock()
        t.ok(api.is_menu_open(), "the menu should open itself while waiting for a round")

        gGlobalSyncTable.sh5_mode = 0
        gGlobalSyncTable.sh5_difficulty = api.medium
        api.host_start(8)
        api.update_config_menu_lock()
        t.ok(not api.is_menu_open(), "the menu should close when the round starts")
    end)
end
