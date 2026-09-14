-- Boss mode's bomb reserve.
--
-- Bowser in the Sky ships five bombs. Hard needs seven hits and Nightmare nine,
-- so those difficulties would strand the fight once the native five are gone.
-- The fix (2026-08-04) gives the host one synchronized reserve wave, and only
-- after it has actually seen the five native bombs -- an empty arena during
-- level load, or right after a host change, must not trigger it.

return function(t, harness)
    local s = t.suite("boss")

    --- Drive the host through the reserve sequence and return what it spawned.
    local function run_supply(difficulty, opts)
        opts = opts or {}
        local api, ctl = harness.load()
        ctl.begin_round(api, api.boss_mode, difficulty, LEVEL_BOWSER_3)
        ctl.timer = 1000

        if not opts.skip_sighting then
            ctl.bomb_count = #api.boss_bomb_positions   -- the native five, on screen
            api.boss_bomb_supply()
        end

        ctl.bomb_count = 0                              -- arena now empty
        api.boss_bomb_supply()                          -- starts the one-second wait
        ctl.timer = ctl.timer + (opts.wait_frames or 30)
        api.boss_bomb_supply()                          -- spawns, if armed
        return api, ctl
    end

    s.test("Easy and Normal never add bombs", function()
        -- These difficulties need at most five hits, so the native arena is
        -- already enough and must be left exactly as the game built it.
        local api = harness.load()
        for _, name in ipairs({ "easy", "medium" }) do
            local _, c = run_supply(api[name])
            t.eq(#c.spawned, 0, name .. " created a reserve bomb")
        end
    end)

    s.test("Hard supplies exactly two bombs", function()
        local api = harness.load()
        local _, c = run_supply(api.hard)
        t.eq(#c.spawned, 2)
    end)

    s.test("Nightmare supplies exactly four bombs", function()
        local api = harness.load()
        local _, c = run_supply(api.nightmare)
        t.eq(#c.spawned, 4)
    end)

    s.test("reserve bombs land on distinct original positions", function()
        local api = harness.load()
        local a, c = run_supply(api.nightmare)
        local seen = {}
        for _, bomb in ipairs(c.spawned) do
            local key = string.format("%d/%d/%d", bomb.oPosX, bomb.oPosY, bomb.oPosZ)
            t.ok(not seen[key], "two reserve bombs share position " .. key)
            seen[key] = true
            local matched = false
            for _, p in ipairs(a.boss_bomb_positions) do
                if p.x == bomb.oPosX and p.y == bomb.oPosY and p.z == bomb.oPosZ then
                    matched = true
                end
            end
            t.ok(matched, "reserve bomb spawned off the original layout at " .. key)
        end
    end)

    s.test("an arena that was never seen full does not arm the reserve", function()
        -- A host that joins mid-fight, or a level still loading, reports zero
        -- bombs. That must not be read as an exhausted arena.
        local api = harness.load()
        local _, c = run_supply(api.nightmare, { skip_sighting = true })
        t.eq(#c.spawned, 0, "the reserve fired without ever seeing the native bombs")
    end)

    s.test("a momentary zero does not arm the reserve", function()
        -- One continuous second at zero is required; an explosion frame is not.
        local api, ctl = harness.load()
        ctl.begin_round(api, api.boss_mode, api.nightmare, LEVEL_BOWSER_3)
        ctl.timer = 500
        ctl.bomb_count = #api.boss_bomb_positions
        api.boss_bomb_supply()
        ctl.bomb_count = 0
        api.boss_bomb_supply()
        ctl.timer = ctl.timer + 10        -- well short of a second
        api.boss_bomb_supply()
        t.eq(#ctl.spawned, 0, "the reserve fired before the one-second wait elapsed")
    end)

    s.test("the reserve fires only once per round", function()
        local api = harness.load()
        local a, c = run_supply(api.nightmare)
        t.eq(#c.spawned, 4)
        -- the arena empties again; no second wave may appear
        c.bomb_count = 0
        c.timer = c.timer + 600
        a.boss_bomb_supply()
        a.boss_bomb_supply()
        t.eq(#c.spawned, 4, "a second reserve wave was created")
    end)

    s.test("a client never creates bombs", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, api.boss_mode, api.nightmare, LEVEL_BOWSER_3)
        ctl.is_server = false
        ctl.timer = 500
        ctl.bomb_count = #api.boss_bomb_positions
        api.boss_bomb_supply()
        ctl.bomb_count = 0
        api.boss_bomb_supply()
        ctl.timer = ctl.timer + 60
        api.boss_bomb_supply()
        t.eq(#ctl.spawned, 0, "a non-host client spawned reserve bombs")
    end)

    s.test("the reserve stays out of other modes", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, api.chaos_mode, api.nightmare, LEVEL_BOWSER_3)
        ctl.timer = 500
        ctl.bomb_count = #api.boss_bomb_positions
        api.boss_bomb_supply()
        ctl.bomb_count = 0
        api.boss_bomb_supply()
        ctl.timer = ctl.timer + 60
        api.boss_bomb_supply()
        t.eq(#ctl.spawned, 0, "Chaos mode created Boss reserve bombs")
    end)

    s.test("the original layout is five distinct positions", function()
        local api = harness.load()
        t.eq(#api.boss_bomb_positions, 5)
        local seen = {}
        for _, p in ipairs(api.boss_bomb_positions) do
            local key = string.format("%d/%d/%d", p.x, p.y, p.z)
            t.ok(not seen[key], "duplicate bomb position " .. key)
            seen[key] = true
        end
    end)
end
