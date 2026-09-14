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

    -- the Boss data itself ---------------------------------------------------
    -- Three rules in modules/boss.lua are written down in comments and were
    -- enforced by nothing. Each is the kind that fails quietly: the round still
    -- runs, it is just no longer winnable, or fair, or reliable.

    s.test("no Boss player modifier can take the B button away", function()
        -- Bowser is beaten by grabbing his tail, which is B. A modifier that
        -- removes B leaves the round unwinnable for whoever draws it, and
        -- nothing else in the mod would report a problem.
        local api = harness.load()
        for i, m in ipairs(api.boss_player_modifiers) do
            t.ne(m.kind, "no_b", "Boss player modifier " .. i .. " locks B")
            t.ne(m.kind, "swap_ab", "Boss player modifier " .. i .. " moves B elsewhere")
        end
    end)

    s.test("every Boss modifier draw contains an attack of its own", function()
        -- Rage and Desperate only accelerate other attacks and Instakill only
        -- changes damage, so a draw of those three produces a Bowser who never
        -- attacks at all. BOSS_ACTIVE_ATTACK_LOOKUP is what prevents it.
        local api = harness.load()
        local active, passive = 0, 0
        for index, m in ipairs(api.boss_modifiers) do
            if api.boss_active_attack_lookup[index] then
                active = active + 1
                t.ne(m.kind, "rage", "rage counted as an attack")
                t.ne(m.kind, "desperate", "desperate counted as an attack")
                t.ne(m.kind, "instakill", "instakill counted as an attack")
            else
                passive = passive + 1
            end
        end
        t.ok(active > 0, "no modifier counts as creating an attack")
        t.ok(passive > 0, "every modifier counts as creating an attack, so the "
            .. "check cannot reject anything")
        -- Three drawn from twelve, so a draw of three passives must be possible
        -- to be worth guarding against.
        t.ok(passive >= 3, "fewer than three passive modifiers: " .. passive)
    end)

    s.test("Bowser's attacks queue across eight slots, not one", function()
        -- CHANGELOG.md records a single "latest attack" field losing attacks
        -- under lag. The queue is what replaced it, and its size has to match
        -- the sh5_boss_attack_queue_N fields the host actually writes.
        local api = harness.load()
        t.eq(api.boss_attack_queue_size, 8)
        for slot = 1, api.boss_attack_queue_size do
            t.ne(gGlobalSyncTable["sh5_boss_attack_queue_" .. slot], nil,
                "slot " .. slot .. " has no synchronized field")
        end
    end)

    s.test("every Boss modifier is named in both languages", function()
        local api = harness.load()
        t.eq(#api.boss_modifiers, 12, "the Boss modifier list changed size")
        local seen = {}
        for i, m in ipairs(api.boss_modifiers) do
            t.ok(not seen[m.kind], "duplicate Boss modifier " .. tostring(m.kind))
            seen[m.kind] = true
            for _, field in ipairs({ "label", "label_es" }) do
                t.ok(type(m[field]) == "string" and #m[field] > 0,
                    "Boss modifier " .. i .. " is missing " .. field)
            end
        end
    end)

    s.test("Bowser always has at least one hit point left to take", function()
        -- sh5_boss_max_health is synchronized, so a client can read it before
        -- the host has written it. Zero would mean a Bowser already dead, and
        -- the health bar divides by it.
        local api = harness.load()
        for _, value in ipairs({ 0, -1 }) do
            gGlobalSyncTable.sh5_boss_max_health = value
            t.ok(api.boss_max_health() >= 1,
                "max health " .. value .. " resolved to " .. tostring(api.boss_max_health()))
        end
        gGlobalSyncTable.sh5_boss_max_health = 7
        t.eq(api.boss_max_health(), 7, "a real value should be used as-is")
    end)

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
