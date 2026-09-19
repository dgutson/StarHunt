-- Every countdown StarHunt shows is counted on the machine showing it.
--
-- The rule these tests hold down: a countdown is measured in real seconds from
-- a mark this machine set, never in frames and never against a number another
-- machine wrote. `get_global_timer()` counts frames this process has drawn, so
-- it runs at 60 a second on the loading screen and below 30 whenever the
-- machine stutters, and it starts at zero when that copy of the game opens.
-- A countdown that read it was wrong by the difference.

return function(t, harness)
    local s = t.suite("clock")

    local function fresh()
        local api, ctl = harness.load()
        api.set_language(0)                      -- English, so the labels read
        return api, ctl
    end

    --- A round of `minutes`, already begun, with the local marks placed.
    local function round(api, ctl, minutes)
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_round = (gGlobalSyncTable.sh5_round or 0) + 1
        gGlobalSyncTable.sh5_config_minutes = minutes
        api.update_local_clocks()
        return api, ctl
    end

    -- the countdown itself ----------------------------------------------------

    s.test("a countdown runs from its mark to zero and stops there", function()
        local api, ctl = fresh()
        ctl.elapsed = 500
        t.eq(api.seconds_left(500, 120), 120, "a countdown just started is its whole length")
        ctl.elapsed = 560
        t.eq(api.seconds_left(500, 120), 60, "a minute in, a minute is left")
        ctl.elapsed = 620
        t.eq(api.seconds_left(500, 120), 0, "the countdown did not reach zero")
        ctl.elapsed = 9000
        t.eq(api.seconds_left(500, 120), 0, "an expired countdown went negative")
    end)

    s.test("a part second still counts as a second left", function()
        -- The player is shown whole seconds, and a countdown with any time on
        -- it must not read 0:00 while it is still running.
        local api, ctl = fresh()
        ctl.elapsed = 100.5
        t.eq(api.seconds_left(100, 10), 10, "half a second in dropped a whole second")
        ctl.elapsed = 109.5
        t.eq(api.seconds_left(100, 10), 1, "the last part-second read as none left")
        ctl.elapsed = 110
        t.eq(api.seconds_left(100, 10), 0, "the countdown outlived its length")
    end)

    s.test("a machine that has not seen the countdown start counts zero", function()
        local api = fresh()
        t.eq(api.seconds_left(nil, 120), 0, "an unset mark invented a countdown")
    end)

    -- the frame counter must not reach any of it -------------------------------

    s.test("no countdown moves when only the frame counter does", function()
        -- This is the defect. The frame counter starts at zero when a copy of
        -- the game opens and runs at a rate the machine decides, so a player
        -- who joined later, or whose machine stutters, or who has just sat
        -- through a loading screen, had every countdown wrong by that much.
        local api, ctl = fresh()
        round(api, ctl, 10)
        gPlayerSyncTable[0].sh5_goal = 1
        gGlobalSyncTable.sh5_mode = api.normal_mode

        local round_left = api.round_seconds_left()
        local reroll_left = api.manual_reroll_remaining()
        local chaos_left = api.chaos_reroll_seconds_left()

        ctl.timer = ctl.timer + 19000       -- ten minutes of frames, and more
        api.update_local_clocks()

        t.eq(api.round_seconds_left(), round_left,
            "the round clock followed this machine's frame counter")
        t.eq(api.manual_reroll_remaining(), reroll_left,
            "the ANOTHER LEVEL countdown followed this machine's frame counter")
        t.eq(api.chaos_reroll_seconds_left(), chaos_left,
            "the Chaos countdown followed this machine's frame counter")
    end)

    s.test("the countdowns move when the seconds do", function()
        local api, ctl = fresh()
        round(api, ctl, 10)
        gPlayerSyncTable[0].sh5_goal = 1
        gGlobalSyncTable.sh5_mode = api.normal_mode

        ctl.elapsed = ctl.elapsed + 90
        api.update_local_clocks()
        t.eq(api.round_seconds_left(), 10 * 60 - 90, "the round clock stood still")
        t.eq(api.manual_reroll_remaining(),
            api.manual_reroll_cooldown_seconds - 90, "the cooldown stood still")
    end)

    -- what starts each countdown on this machine --------------------------------

    s.test("a new round starts all three countdowns", function()
        local api, ctl = fresh()
        round(api, ctl, 10)
        ctl.elapsed = ctl.elapsed + 300
        api.update_local_clocks()
        t.eq(api.round_seconds_left(), 10 * 60 - 300, "the mark moved without a new round")

        round(api, ctl, 10)
        t.eq(api.round_seconds_left(), 10 * 60, "a new round did not restart the round clock")
        t.eq(api.chaos_reroll_seconds_left(), api.chaos_reroll_seconds,
            "a new round did not restart the Chaos countdown")
    end)

    s.test("a granted ANOTHER LEVEL restarts only that countdown", function()
        -- The host bumps sh5_manual_reroll_seq when, and only when, a level
        -- actually came back. That counter is what tells this machine to start
        -- counting again; it is an event, not a time, so nothing here reads
        -- another machine's clock.
        local api, ctl = fresh()
        round(api, ctl, 10)
        gPlayerSyncTable[0].sh5_goal = 1
        gGlobalSyncTable.sh5_mode = api.normal_mode
        ctl.elapsed = ctl.elapsed + 100
        api.update_local_clocks()

        gPlayerSyncTable[0].sh5_manual_reroll_seq = 1
        api.update_local_clocks()
        t.eq(api.manual_reroll_remaining(), api.manual_reroll_cooldown_seconds,
            "a granted reroll did not restart the cooldown")
        t.eq(api.round_seconds_left(), 10 * 60 - 100,
            "a granted reroll restarted the round clock as well")

        -- and again, because a counter compared against the wrong default
        -- answers the first grant correctly and every one after it wrongly
        ctl.elapsed = ctl.elapsed + 30
        api.update_local_clocks()
        gPlayerSyncTable[0].sh5_manual_reroll_seq = 2
        api.update_local_clocks()
        t.eq(api.manual_reroll_remaining(), api.manual_reroll_cooldown_seconds,
            "the second granted reroll did not restart the cooldown")
    end)

    s.test("a new goal that is not a granted reroll leaves the cooldown alone", function()
        -- Dying and finishing a star both hand out a new goal. Neither touches
        -- sh5_manual_reroll_seq, so neither restarts the wait.
        local api, ctl = fresh()
        round(api, ctl, 10)
        gPlayerSyncTable[0].sh5_goal = 1
        gGlobalSyncTable.sh5_mode = api.normal_mode
        ctl.elapsed = ctl.elapsed + 100
        api.update_local_clocks()
        local left = api.manual_reroll_remaining()

        gPlayerSyncTable[0].sh5_goal_seq = (gPlayerSyncTable[0].sh5_goal_seq or 0) + 1
        gPlayerSyncTable[0].sh5_goal = 2
        api.update_local_clocks()

        t.eq(api.manual_reroll_remaining(), left,
            "a goal handed out by a death or a star restarted the cooldown")
    end)

    s.test("a Chaos reroll restarts the Chaos countdown", function()
        local api, ctl = fresh()
        round(api, ctl, 10)
        ctl.elapsed = ctl.elapsed + 10
        api.update_local_clocks()
        t.eq(api.chaos_reroll_seconds_left(), api.chaos_reroll_seconds - 10,
            "the Chaos countdown stood still")

        gGlobalSyncTable.sh5_chaos_modifier_seq =
            (gGlobalSyncTable.sh5_chaos_modifier_seq or 0) + 1
        api.update_local_clocks()
        t.eq(api.chaos_reroll_seconds_left(), api.chaos_reroll_seconds,
            "a reroll did not restart the countdown to the next one")
    end)

    -- a machine that has been told nothing yet ---------------------------------

    s.test("a machine that has received nothing still starts its countdowns", function()
        -- A client that has not yet had a single sync field delivered must not
        -- read the button as instantly ready, and must not invent a round.
        local api = fresh()
        gGlobalSyncTable.sh5_round = nil
        gGlobalSyncTable.sh5_config_minutes = 10
        gGlobalSyncTable.sh5_chaos_modifier_seq = nil
        gPlayerSyncTable[0].sh5_manual_reroll_seq = nil
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_mode = api.normal_mode
        gPlayerSyncTable[0].sh5_goal = 1

        api.update_local_clocks()
        t.eq(api.manual_reroll_remaining(), api.manual_reroll_cooldown_seconds,
            "the button was ready before the round had said anything")
        t.eq(api.round_seconds_left(), 10 * 60,
            "a round whose number has not arrived yet never started counting")
    end)

    s.test("a round whose length has not arrived counts nothing", function()
        local api = fresh()
        gGlobalSyncTable.sh5_config_minutes = nil
        gGlobalSyncTable.sh5_active = 1
        api.update_local_clocks()
        t.eq(api.round_seconds_left(), 0, "a round with no length counted down anyway")
    end)

    s.test("a countdown keeps running while the fields it watches stay unset",
    function()
        -- The counters are read with a default, and that default has to differ
        -- from the "not seen yet" value, or every frame looks like a fresh
        -- event and restarts the countdown that should be running down.
        local api, ctl = fresh()
        round(api, ctl, 10)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        gPlayerSyncTable[0].sh5_goal = 1
        gPlayerSyncTable[0].sh5_manual_reroll_seq = nil
        gGlobalSyncTable.sh5_chaos_modifier_seq = nil

        api.update_local_clocks()
        ctl.elapsed = ctl.elapsed + 10
        api.update_local_clocks()

        t.eq(api.manual_reroll_remaining(), api.manual_reroll_cooldown_seconds - 10,
            "the cooldown restarted itself on a frame where nothing happened")
        t.eq(api.chaos_reroll_seconds_left(), api.chaos_reroll_seconds - 10,
            "the Chaos countdown restarted itself on a frame where nothing happened")
    end)

    -- what a player reads -------------------------------------------------------

    s.test("the drawn clock and the menu row agree with each other", function()
        local api, ctl = fresh()
        round(api, ctl, 5)
        ctl.elapsed = ctl.elapsed + 210          -- 3:30 gone, 1:30 left
        api.update_local_clocks()
        t.eq(api.format_remaining_time(api.round_seconds_left()), "1:30",
            "the HUD clock read the wrong time")

        gPlayerSyncTable[0].sh5_goal = 1
        gGlobalSyncTable.sh5_mode = api.normal_mode
        t.eq(api.manual_reroll_label(), "ANOTHER LEVEL - READY",
            "the ANOTHER LEVEL row did not go ready after its two minutes")

        -- and half a minute in, it reads the time it has left
        round(api, ctl, 5)
        ctl.elapsed = ctl.elapsed + 30
        api.update_local_clocks()
        t.eq(api.manual_reroll_label(), "ANOTHER LEVEL - 1:30",
            "the ANOTHER LEVEL row counted the wrong time")
    end)
end
