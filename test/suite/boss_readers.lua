-- The readers the rest of the mod uses to ask about a Boss round.
--
-- These four functions moved into modules/boss.lua and every one of the 28
-- mutations tried against them survived a green 188-test run: nothing in the
-- suite called any of them. They decide how long a Boss round lasts, which of
-- Bowser's modifiers are running, whether he has reached his last two wedges,
-- and which health figure the host believes -- so a silent wrong answer here
-- changes the fight without breaking anything visibly.
--
-- Every expected value below is written as a literal on purpose. A test that
-- asks the code what it does agrees with the code whatever the code says.

return function(t, harness)
    local s = t.suite("boss_readers")

    --- A Boss round on Medium, with Bowser's health pool pinned at five.
    local function boss_round()
        local api, ctl = harness.load()
        ctl.begin_round(api, api.boss_mode, api.medium, LEVEL_BOWSER_3)
        -- Pinned rather than read back: Medium's pool is five wedges.
        gGlobalSyncTable.sh5_boss_max_health = 5
        for i = 0, MAX_PLAYERS - 1 do
            gPlayerSyncTable[i].sh5_boss_health_ready_round = nil
            gPlayerSyncTable[i].sh5_boss_health_value = nil
        end
        gGlobalSyncTable.sh5_boss_modifier_1 = 0
        gGlobalSyncTable.sh5_boss_modifier_2 = 0
        gGlobalSyncTable.sh5_boss_modifier_3 = 0
        return api, ctl
    end

    -- how long a Boss round lasts -------------------------------------------
    -- Bowser's fight is one arena, so it is given far less time than a star
    -- hunt across the castle. The table is short and every row is a cliff: one
    -- player either side of a boundary changes the round length for everyone.

    s.test("the Boss time range is the one written for Bowser, not the star hunt", function()
        local api = boss_round()
        local expected = {
            { players = 1,  min = 5, max = 10 },
            { players = 2,  min = 4, max = 9 },
            { players = 3,  min = 4, max = 9 },
            { players = 4,  min = 4, max = 8 },
            { players = 8,  min = 4, max = 8 },
            { players = 9,  min = 3, max = 7 },
            { players = 16, min = 3, max = 7 },
        }
        for _, row in ipairs(expected) do
            local lo, hi = api.time_range(row.players)
            t.eq(lo, row.min, "shortest Boss round for " .. row.players .. " players")
            t.eq(hi, row.max, "longest Boss round for " .. row.players .. " players")
        end
    end)

    s.test("a Boss round is shorter than a star hunt with the same players", function()
        -- Proves the Boss branch is actually taken. Without it the fight would
        -- silently inherit the star hunt's much longer clock.
        local api, ctl = harness.load()
        ctl.begin_round(api, api.normal_mode, api.medium, LEVEL_BOWSER_3)
        local normal_lo, normal_hi = api.time_range(1)
        t.eq(normal_lo, 13, "a solo star hunt starts at 13 minutes")
        t.eq(normal_hi, 22, "a solo star hunt reaches 22 minutes")

        local boss_api = boss_round()
        local boss_lo, boss_hi = boss_api.time_range(1)
        t.ok(boss_lo < normal_lo, "the Boss round is not shorter at its floor")
        t.ok(boss_hi < normal_hi, "the Boss round is not shorter at its ceiling")
    end)

    -- which of Bowser's modifiers are running --------------------------------

    s.test("a modifier in the first slot is found", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = 5
        t.ok(api.boss_has_modifier(5), "the first slot was not searched")
    end)

    s.test("a modifier in the last slot is found", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_3 = 7
        t.ok(api.boss_has_modifier(7), "the third slot was not searched")
    end)

    s.test("an index in none of the three slots is not found", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        gGlobalSyncTable.sh5_boss_modifier_2 = 2
        gGlobalSyncTable.sh5_boss_modifier_3 = 3
        t.ok(not api.boss_has_modifier(9), "reported a modifier that is not drawn")
    end)

    -- Bowser's last two wedges ------------------------------------------------
    -- Desperate (modifier 12) only changes the fight once he is down to two
    -- wedges. Both halves of that condition matter: the wrong one alone makes
    -- Bowser attack faster from the first hit, or never speed up at all.

    s.test("desperate needs modifier 12 and two wedges or fewer", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = 12
        gGlobalSyncTable.sh5_boss_health = 2
        t.ok(api.boss_is_desperate(), "two wedges with Desperate drawn is not desperate")
    end)

    s.test("three wedges is not yet desperate", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = 12
        gGlobalSyncTable.sh5_boss_health = 3
        t.ok(not api.boss_is_desperate(), "desperate began a wedge too early")
    end)

    s.test("a different modifier at low health is not desperate", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = 11   -- Hunter Fire, not Desperate
        gGlobalSyncTable.sh5_boss_health = 1
        t.ok(not api.boss_is_desperate(), "a modifier other than 12 triggered desperate")
    end)

    s.test("low health without Desperate drawn is not desperate", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_health = 1
        t.ok(not api.boss_is_desperate(), "desperate needs only low health")
    end)

    s.test("before any health is synced Bowser is at full health, not desperate", function()
        -- The fallback is the full pool, not zero. Reading it as zero would put
        -- Bowser in his desperate phase for the whole round from the first frame.
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = 12
        gGlobalSyncTable.sh5_boss_health = nil
        t.ok(not api.boss_is_desperate(), "an unsynced health field read as zero")
    end)

    -- the modifier's name on screen ------------------------------------------

    s.test("English shows the modifier's own label", function()
        local api = boss_round()
        api.set_language(0)
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        t.eq(api.boss_modifier_text(1), "BOWSER: INSTANT KNOCKOUT")
    end)

    s.test("Spanish shows the Spanish label carried on the modifier", function()
        local api = boss_round()
        api.set_language(1)
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        t.eq(api.boss_modifier_text(1), "BOWSER: GOLPE MORTAL")
    end)

    s.test("a later language reads its own dictionary, not the Spanish label", function()
        -- Portuguese is language 2, so it comes out of boss_modifier_translations
        -- rather than the modifier's label_es. Shockwaves is the test case
        -- because its three spellings differ from each other; several other
        -- modifiers share a spelling between Spanish and Portuguese and would
        -- pass whichever branch ran.
        local api = boss_round()
        api.set_language(2)
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        t.eq(api.boss_modifier_text(1), "BOWSER: ONDAS PARALISANTES")
    end)

    s.test("each slot reads its own field", function()
        local api = boss_round()
        api.set_language(0)
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        gGlobalSyncTable.sh5_boss_modifier_2 = 2
        gGlobalSyncTable.sh5_boss_modifier_3 = 3
        t.eq(api.boss_modifier_text(1), "BOWSER: INSTANT KNOCKOUT", "slot 1")
        t.eq(api.boss_modifier_text(2), "BOWSER: PARALYZING WAVES", "slot 2")
        t.eq(api.boss_modifier_text(3), "BOWSER: VIOLET SPLITFIRE", "slot 3")
    end)

    s.test("a slot holding no modifier has no text", function()
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = 0
        t.eq(api.boss_modifier_text(1), "")
    end)

    s.test("a slot whose field was never synced has no text", function()
        -- An absent field reads as modifier zero, which is no modifier. Reading
        -- it as one would put Instant Knockout on screen in every round that
        -- has not synced its draw yet.
        local api = boss_round()
        gGlobalSyncTable.sh5_boss_modifier_1 = nil
        t.eq(api.boss_modifier_text(1), "")
    end)

    s.test("a slot beyond the three fields has no text", function()
        local api = boss_round()
        t.eq(api.boss_modifier_text(4), "")
    end)

    -- the health figure the host believes -------------------------------------
    -- Only the client that owns Bowser can see his health, so it is reported
    -- through the player sync tables and the host reads the reports back. The
    -- lowest valid one wins: his health can only fall inside a round, so a
    -- stale packet arriving late must not heal him.

    s.test("a report for the current round is read back", function()
        local api = boss_round()
        gPlayerSyncTable[0].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round
        gPlayerSyncTable[0].sh5_boss_health_value = 3
        t.eq(api.boss_health_report(), 3)
    end)

    s.test("a report from an earlier round is ignored", function()
        local api = boss_round()
        gPlayerSyncTable[0].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round - 1
        gPlayerSyncTable[0].sh5_boss_health_value = 1
        t.is_nil(api.boss_health_report(), "a stale round's report was believed")
    end)

    s.test("with no reports at all the host has no figure", function()
        local api = boss_round()
        t.is_nil(api.boss_health_report())
    end)

    s.test("the lowest report wins, so a stale packet cannot heal Bowser", function()
        local api = boss_round()
        local round = gGlobalSyncTable.sh5_round
        gPlayerSyncTable[0].sh5_boss_health_ready_round = round
        gPlayerSyncTable[0].sh5_boss_health_value = 4
        gPlayerSyncTable[1].sh5_boss_health_ready_round = round
        gPlayerSyncTable[1].sh5_boss_health_value = 2
        t.eq(api.boss_health_report(), 2, "the higher, older report was taken")
    end)

    s.test("a report of zero survives the clamp", function()
        -- Zero is Bowser defeated. Clamping it up to one would leave the fight
        -- unable to end.
        local api = boss_round()
        gPlayerSyncTable[0].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round
        gPlayerSyncTable[0].sh5_boss_health_value = 0
        t.eq(api.boss_health_report(), 0)
    end)

    s.test("a report above the pool is clamped down to it", function()
        local api = boss_round()
        gPlayerSyncTable[0].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round
        gPlayerSyncTable[0].sh5_boss_health_value = 99
        t.eq(api.boss_health_report(), 5, "Medium's five-wedge pool did not cap the report")
    end)

    s.test("with no round number synced, reports for round zero still count", function()
        -- A round field that has not arrived reads as round zero, which is what
        -- a client that has not started reports against.
        local api = boss_round()
        gGlobalSyncTable.sh5_round = nil
        gPlayerSyncTable[0].sh5_boss_health_ready_round = 0
        gPlayerSyncTable[0].sh5_boss_health_value = 3
        t.eq(api.boss_health_report(), 3)
    end)
end
