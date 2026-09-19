-- Chaos mode: the map pool, the modifier churn, and the warp.
--
-- Chaos is the one mode with no star to collect, so nothing else in the suite
-- reaches it. Before this file, all 17 mutations tried against modules/chaos.lua
-- survived a full green run -- including deleting a level from the map pool,
-- handing every player the same modifier forever, and warping eliminated
-- players into the arena they were just knocked out of. SH.update_chaos_warp
-- was even published in STARHUNT_TEST_API and called by no test at all.
--
-- The numbers here (15 courses, a 15-second reroll, a 90-frame warp delay) are
-- written as literals rather than read back from the mod. A test that asks the
-- code what it does agrees with the code whatever the code says.

return function(t, harness)
    local s = t.suite("chaos")

    --- Load the mod into a running Chaos round on `level`, as the host.
    local function chaos_round(difficulty, level)
        local api, ctl = harness.load()
        ctl.begin_round(api, api.chaos_mode, difficulty or api.medium,
            level or LEVEL_BOB)
        gGlobalSyncTable.sh5_chaos_level = level or LEVEL_BOB
        gGlobalSyncTable.sh5_chaos_act = 1
        ctl.timer = 1000
        return api, ctl
    end

    --- Enrol `count` players as living Chaos contestants.
    local function enrol(count)
        for i = 0, count - 1 do
            gNetworkPlayers[i].connected = true
            gPlayerSyncTable[i].sh5_enrolled = 1
            gPlayerSyncTable[i].sh5_chaos_eliminated = 0
            gPlayerSyncTable[i].sh5_modifier = 0
            gPlayerSyncTable[i].sh5_modifier_2 = 0
        end
        for i = count, 15 do gNetworkPlayers[i].connected = false end
    end

    -- the map pool -----------------------------------------------------------

    s.test("the Chaos map pool is the fifteen main courses and nothing else", function()
        -- Chaos drops everyone into one of these and eliminates whoever dies,
        -- so the pool has to be levels a player can actually die in and finish
        -- a round in. A castle or secret level in here would produce a round
        -- with no hazard; a missing course silently shrinks the variety that is
        -- the entire point of the mode.
        local api, ctl = harness.load()
        t.eq(#api.chaos_maps, 15, "Chaos map pool size")

        local seen = {}
        for _, level in ipairs(api.chaos_maps) do
            t.ok(not seen[level], "level " .. tostring(level) .. " appears twice in the pool")
            seen[level] = true
            local course = ctl.course_of[level]
            t.ok(course ~= nil and course >= 1 and course <= 15,
                "level " .. tostring(level) .. " is not one of courses 1-15")
        end

        -- Every main course, not merely fifteen of something.
        for course = 1, 15 do
            local found = false
            for _, level in ipairs(api.chaos_maps) do
                if ctl.course_of[level] == course then found = true end
            end
            t.ok(found, "course " .. course .. " is missing from the Chaos map pool")
        end
    end)

    -- which modifiers Chaos may draw -----------------------------------------

    s.test("Chaos never draws Coin Toll, which needs a star it does not have", function()
        -- Coin Toll only gates the target star. Chaos has no target star, so a
        -- player who drew it would carry a restriction that does nothing --
        -- effectively a free round while everyone else fights their modifier.
        local api = harness.load()
        local saw_other = 0
        for _, m in ipairs(api.normal_modifier_catalog) do
            if m.kind == "coin_toll" then
                t.ok(not api.chaos_modifier_allowed(m), "coin_toll was allowed in Chaos")
            else
                t.ok(api.chaos_modifier_allowed(m), m.kind .. " was rejected from Chaos")
                saw_other = saw_other + 1
            end
        end
        t.eq(saw_other, #api.normal_modifier_catalog - 1, "exactly one modifier is barred")
        t.ok(not api.chaos_modifier_allowed(nil), "nil was allowed in Chaos")
    end)

    s.test("a draw never returns the modifier the player already had", function()
        -- A reroll that can hand back the same modifier is a reroll that
        -- sometimes does nothing, and the whole mode is built on the churn.
        local api = harness.load()
        math.randomseed(20260914)
        for previous = 1, #api.normal_modifier_catalog do
            for _ = 1, 40 do
                local first = api.pick_chaos_pair(previous)
                t.ne(first, previous, "draw repeated modifier index " .. previous)
            end
        end
    end)

    s.test("only Nightmare hands out a second modifier", function()
        local api = harness.load()
        math.randomseed(20260914)
        local single = { api.easy, api.medium, api.hard }
        for _, difficulty in ipairs(single) do
            gGlobalSyncTable.sh5_difficulty = difficulty
            for _ = 1, 40 do
                local first, second = api.pick_chaos_pair(0)
                t.ne(first, 0, "no first modifier was drawn")
                t.eq(second, 0, "a second modifier was drawn below Nightmare")
            end
        end

        gGlobalSyncTable.sh5_difficulty = api.nightmare
        for _ = 1, 40 do
            local first, second = api.pick_chaos_pair(0)
            t.ne(first, 0, "no first modifier was drawn on Nightmare")
            t.ne(second, 0, "Nightmare drew no second modifier")
        end
    end)

    s.test("the Nightmare pair obeys the conflict rules in both directions", function()
        -- Chaos draws from the whole catalog rather than from one star's
        -- audited list, so these rules are the only thing standing between a
        -- player and, say, reversed controls plus mirrored steering.
        local api = harness.load()
        math.randomseed(20260914)
        gGlobalSyncTable.sh5_difficulty = api.nightmare
        local catalog = api.normal_modifier_catalog
        for _ = 1, 300 do
            local first, second = api.pick_chaos_pair(0)
            t.ne(first, second, "Nightmare drew the same modifier twice")
            t.ok(catalog[first] ~= nil and catalog[second] ~= nil,
                "Nightmare drew an empty slot: " .. first .. ", " .. second)
            t.ok(api.chaos_pair_allowed(catalog[first], catalog[second]),
                "drew forbidden pair " .. catalog[first].kind .. " + " .. catalog[second].kind)
            t.ok(api.chaos_pair_allowed(catalog[second], catalog[first]),
                "drew forbidden pair reversed: " .. catalog[second].kind
                    .. " + " .. catalog[first].kind)
            t.ok(api.chaos_modifier_allowed(catalog[second]),
                catalog[second].kind .. " was drawn as a second modifier but is barred")
        end
    end)

    -- the host's reroll ------------------------------------------------------

    s.test("modifiers are rerolled every fifteen seconds, not sooner", function()
        -- The interval is what makes Chaos playable: long enough to adapt to
        -- the modifier, short enough that nobody settles in. A reroll that
        -- ignored its deadline would rewrite everyone's modifier every frame.
        local api, ctl = chaos_round()
        t.eq(api.chaos_reroll_seconds, 15, "reroll interval in seconds")
        enrol(4)

        gPlayerSyncTable[0].sh5_modifier = 7
        ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds - 1
        api.chaos_reroll()
        t.eq(gPlayerSyncTable[0].sh5_modifier, 7, "rerolled a second early")

        ctl.elapsed = ctl.elapsed + 1
        api.chaos_reroll()
        t.ne(gPlayerSyncTable[0].sh5_modifier, 7, "did not reroll on the interval")

        -- and the interval starts again from here
        local rerolled = gPlayerSyncTable[0].sh5_modifier
        ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds - 1
        api.chaos_reroll()
        t.eq(gPlayerSyncTable[0].sh5_modifier, rerolled, "the interval was not rearmed")
    end)

    s.test("an eliminated player is left out of the reroll", function()
        -- Eliminated players are spectators in the castle lobby. Rerolling them
        -- would keep applying modifier effects to someone with nothing to do,
        -- and their stale modifier index is what the HUD still reads.
        local api, ctl = chaos_round()
        enrol(4)
        gPlayerSyncTable[1].sh5_chaos_eliminated = 1
        gPlayerSyncTable[1].sh5_modifier = 11
        gPlayerSyncTable[1].sh5_modifier_2 = 3

        ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds
        api.chaos_reroll()
        t.eq(gPlayerSyncTable[1].sh5_modifier, 11, "an eliminated player was rerolled")
        t.eq(gPlayerSyncTable[1].sh5_modifier_2, 3, "an eliminated player's pair was rerolled")
        t.ne(gPlayerSyncTable[0].sh5_modifier, 0, "a living player was not rerolled")

        -- A player who never enrolled is not a contestant either.
        gNetworkPlayers[5].connected = true
        gPlayerSyncTable[5].sh5_enrolled = 0
        gPlayerSyncTable[5].sh5_modifier = 0
        ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds
        api.chaos_reroll()
        t.eq(gPlayerSyncTable[5].sh5_modifier, 0, "an unenrolled player was rerolled")
    end)

    s.test("each reroll bumps the sequence clients watch", function()
        -- modules/modifiers.lua keys its local state off sh5_chaos_modifier_seq.
        -- If the sequence never moved, a client would go on applying the
        -- modifier it had before the reroll -- silently, and only for clients.
        local api, ctl = chaos_round()
        enrol(3)
        local seen = {}
        for i = 1, 5 do
            ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds
            api.chaos_reroll()
            seen[i] = gGlobalSyncTable.sh5_chaos_modifier_seq
            if i > 1 then
                t.eq(seen[i], seen[i - 1] + 1, "sequence did not advance on reroll " .. i)
            end
        end
    end)

    s.test("the jump budget follows whichever modifier is the jump limit", function()
        -- sh5_jump_count is the player's remaining jumps. On Nightmare the jump
        -- limit can land in either slot of the pair, and reading only the first
        -- leaves a jump-limited player with -1, meaning unlimited.
        local api, ctl = chaos_round(nil, LEVEL_BOB)
        gGlobalSyncTable.sh5_difficulty = api.nightmare
        enrol(4)
        math.randomseed(20260914)

        local catalog = api.normal_modifier_catalog
        local second_slot_cases = 0
        for _ = 1, 120 do
            ctl.elapsed = ctl.elapsed + api.chaos_reroll_seconds
            api.chaos_reroll()
            for i = 0, 3 do
                local sync = gPlayerSyncTable[i]
                local first = api.effective_modifier(catalog[sync.sh5_modifier])
                local second = api.effective_modifier(catalog[sync.sh5_modifier_2])
                local expected = -1
                if first ~= nil and first.kind == "jump_limit" then
                    expected = first.value
                elseif second ~= nil and second.kind == "jump_limit" then
                    expected = second.value
                    second_slot_cases = second_slot_cases + 1
                end
                t.eq(sync.sh5_jump_count, expected,
                    "jump budget for player " .. i .. " does not match its modifier")
            end
        end
        t.ok(second_slot_cases > 0,
            "the jump limit never landed in the second slot, so this test proved nothing")
    end)

    -- the local warp ---------------------------------------------------------

    --- Put the local player at the start of a Chaos round and settle the warp.
    local function warp_round(level)
        local api, ctl = chaos_round(nil, level or LEVEL_LLL)
        local m = gMarioStates[0]
        m.playerIndex = 0
        api.chaos_warp(m)                       -- sees the new round, arms the delay
        return api, ctl, m
    end

    s.test("the warp runs for the local player only", function()
        -- HOOK_BEFORE_MARIO_UPDATE fires once per player on this machine. Acting
        -- on a remote player's Mario would warp this client every time any
        -- other player's state was updated.
        local api, ctl = chaos_round(nil, LEVEL_LLL)
        local other = gMarioStates[1]
        other.playerIndex = 1
        api.chaos_warp(other)
        t.eq(api.runtime.chaos_round_seen, -1, "a remote player's update armed the warp")
        t.eq(#ctl.warps, 0, "a remote player's update caused a warp")
    end)

    s.test("the warp waits ninety frames before firing", function()
        -- The delay gives the round-start banner time to read and keeps every
        -- player from warping on the same frame the round flips active.
        local api, ctl, m = warp_round(LEVEL_LLL)
        t.eq(api.next_goal_delay, 90, "the warp delay in frames")
        t.eq(api.runtime.chaos_warp_at, ctl.timer + 90, "warp deadline")

        ctl.timer = ctl.timer + 89
        api.chaos_warp(m)
        t.eq(#ctl.warps, 0, "warped one frame early")

        ctl.timer = ctl.timer + 1
        api.chaos_warp(m)
        t.eq(#ctl.warps, 1, "did not warp on the deadline")
        t.eq(ctl.warps[1].level, LEVEL_LLL, "warped to the wrong level")
        t.eq(api.runtime.chaos_warp_at, -1, "the warp did not disarm itself")

        ctl.timer = ctl.timer + 100
        api.chaos_warp(m)
        t.eq(#ctl.warps, 1, "warped a second time")
    end)

    s.test("the warp holds off while a level transition is playing", function()
        -- warp_to_level during a transition is dropped by the engine, and the
        -- deadline would be cleared anyway -- so the player would be left in
        -- the lobby for the whole round with no second attempt.
        local api, ctl, m = warp_round(LEVEL_SSL)
        ctl.transition = true
        ctl.timer = ctl.timer + 90
        api.chaos_warp(m)
        t.eq(#ctl.warps, 0, "warped during a transition")
        t.eq(api.runtime.chaos_warp_at, ctl.timer, "the warp disarmed itself during a transition")

        ctl.transition = false
        api.chaos_warp(m)
        t.eq(#ctl.warps, 1, "did not warp once the transition ended")
    end)

    s.test("the warp defaults to act 1 when the round names no act", function()
        local api, ctl, m = warp_round(LEVEL_THI)
        gGlobalSyncTable.sh5_chaos_act = nil
        ctl.timer = ctl.timer + 90
        api.chaos_warp(m)
        t.eq(#ctl.warps, 1, "did not warp")
        t.eq(ctl.warps[1].act, 1, "warped to act 0, which is not a real act")
    end)

    s.test("an eliminated player is sent to the castle lobby, once", function()
        -- Elimination is the whole scoring mechanism, so a player who is out
        -- must leave the arena -- and must not be re-warped every frame, which
        -- would restart the transition endlessly.
        local api, ctl, m = warp_round(LEVEL_DDD)
        gPlayerSyncTable[0].sh5_chaos_eliminated = 1
        ctl.timer = ctl.timer + 90
        api.chaos_warp(m)
        t.eq(#ctl.warps, 1, "an eliminated player was not sent to the lobby")
        t.eq(ctl.warps[1].level, LEVEL_CASTLE_GROUNDS, "eliminated player went somewhere else")

        api.chaos_warp(m)
        api.chaos_warp(m)
        t.eq(#ctl.warps, 1, "an eliminated player was warped repeatedly")
    end)

    s.test("a new Chaos round clears the modifier state of the previous one", function()
        -- Each round is a fresh draw. Carrying modifier_ready_key across means
        -- the local player keeps applying the previous round's modifier until
        -- something else happens to change the key.
        local api, ctl, m = warp_round(LEVEL_WDW)
        api.runtime.modifier_ready_key = 12345
        api.runtime.slip_speed = 40

        ctl.begin_round(api, api.chaos_mode, api.medium, LEVEL_WDW)
        api.chaos_warp(m)
        t.is_nil(api.runtime.modifier_ready_key, "the previous round's modifier key survived")
        t.eq(api.runtime.slip_speed, 0, "the previous round's modifier state survived")
        t.eq(api.runtime.chaos_warp_at, ctl.timer + 90, "the new round did not arm its warp")
    end)

    s.test("leaving Chaos clears the warp state", function()
        local api, ctl, m = warp_round(LEVEL_RR)
        gGlobalSyncTable.sh5_active = 0
        api.chaos_warp(m)
        t.eq(api.runtime.chaos_round_seen, -1, "round number survived the round ending")
        t.eq(api.runtime.chaos_warp_at, -1, "warp deadline survived the round ending")
        t.eq(api.runtime.chaos_spectator_warped, false, "spectator flag survived the round ending")
        t.eq(#ctl.warps, 0, "warped after the round ended")
    end)
end
