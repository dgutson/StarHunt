-- The host's clock, and the four countdowns read against it.
--
-- Every deadline that crosses the network -- the ANOTHER LEVEL cooldown, the
-- round clock, the Chaos reroll -- is a frame number on the host's counter.
-- `get_global_timer()` counts frames since that process started, so a joined
-- client's counter is smaller than the host's by the head start the host's game
-- had, and a client that subtracts its own number counts the wrong time. The
-- host publishes its counter, each client carries the difference, and
-- `SH.host_timer()` answers the same number on every machine.
--
-- Every number below is a literal: a 3600-frame cooldown, a 30-frame publish
-- interval, 19000 frames of head start. A test that asks the code what it does
-- agrees with the code whatever the code says.

return function(t, harness)
    local s = t.suite("clock")

    local COOLDOWN = 120 * 30              -- SH.manualRerollCooldown, pinned
    local PUBLISH_EVERY = 30               -- one second at thirty frames a second

    --- The host, whose own frame counter is the clock.
    local function host(frames)
        local api, ctl = harness.load()
        api.set_language(0)
        ctl.timer = frames
        api.update_host_timer()
        return api, ctl
    end

    --- A joined client `head_start` frames behind the host, which has received
    -- one published sample.
    local function client(host_frames, head_start)
        local api, ctl = harness.load(function(c) c.is_server = false end)
        api.set_language(0)
        ctl.timer = host_frames - head_start
        gGlobalSyncTable.sh5_host_timer = host_frames
        api.update_host_timer()
        return api, ctl
    end

    --- A round the host opened at `host_frames`, as a client receives it: the
    -- round state and this player's goal carry host numbers, whatever the local
    -- counter says.
    local function round_from_the_host(api, host_frames, minutes)
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_mode = api.normal_mode
        gGlobalSyncTable.sh5_difficulty = api.medium
        gGlobalSyncTable.sh5_start_frame = host_frames
        gGlobalSyncTable.sh5_end_frame = host_frames + minutes * 60 * 30
        gPlayerSyncTable[0].sh5_goal = 1
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame = host_frames + COOLDOWN
    end

    --- The line drawn in the caller's own colour that starts with `prefix`,
    -- with the two dots FONT_HUD draws for a colon folded back into the colon.
    local function line_starting(ctl, prefix)
        local pieces = {}
        for _, call in ipairs(ctl.hud.text) do
            if call.a == 255 then pieces[#pieces + 1] = call.text end
        end
        local i = 1
        while i <= #pieces do
            if pieces[i]:sub(1, #prefix) == prefix then
                local text = pieces[i]
                i = i + 1
                while pieces[i] == "." and pieces[i + 1] == "." do
                    text = text .. ":" .. tostring(pieces[i + 2])
                    i = i + 3
                end
                return text
            end
            i = i + 1
        end
        return nil
    end

    -- the clock itself -------------------------------------------------------

    s.test("the host reads its own frame counter, published or not", function()
        local api = host(5000)
        t.eq(api.host_timer(), 5000, "the host is not reading its own frame counter")
        -- The field carries the host's own last publish, and a client could
        -- write it too. Neither moves the machine that owns the clock.
        gGlobalSyncTable.sh5_host_timer = 99999
        api.update_host_timer()
        t.eq(api.host_timer(), 5000, "the host followed a published clock instead of its own")
    end)

    s.test("the host publishes its counter once a second, not every frame", function()
        local api, ctl = host(1000)
        t.eq(gGlobalSyncTable.sh5_host_timer, 1000, "nothing was published at all")
        ctl.timer = 1000 + PUBLISH_EVERY - 1
        api.update_host_timer()
        t.eq(gGlobalSyncTable.sh5_host_timer, 1000,
            "a packet went out before the second was up")
        ctl.timer = 1000 + PUBLISH_EVERY
        api.update_host_timer()
        t.eq(gGlobalSyncTable.sh5_host_timer, 1000 + PUBLISH_EVERY,
            "the second passed and nothing was published")
    end)

    s.test("a client answers the host's frame number, not its own", function()
        local api, ctl = client(20000, 19000)
        t.eq(ctl.timer, 1000, "the fixture is wrong")
        t.eq(api.host_timer(), 20000, "the client is counting its own frames")
        -- Between samples the client's own frames still move the clock. The
        -- hook runs every frame, so the test does too.
        ctl.timer = 1030
        api.update_host_timer()
        t.eq(api.host_timer(), 20030, "the clock stopped between two samples")
    end)

    s.test("a client that has received nothing reads its own counter", function()
        local api, ctl = harness.load(function(c) c.is_server = false end)
        ctl.timer = 777
        gGlobalSyncTable.sh5_host_timer = nil
        api.update_host_timer()
        t.eq(api.host_timer(), 777, "an unheard-from host left the clock somewhere else")
    end)

    s.test("a later sample replaces the difference the client carries", function()
        local api, ctl = client(20000, 19000)
        -- The client's game stalls: the host moves ninety frames while it moves
        -- thirty, so the head start grows by sixty.
        ctl.timer = 1030
        gGlobalSyncTable.sh5_host_timer = 20090
        api.update_host_timer()
        t.eq(api.host_timer(), 20090, "the client kept the head start it measured first")
    end)

    -- ANOTHER LEVEL ----------------------------------------------------------

    s.test("the ANOTHER LEVEL countdown on a client is the cooldown itself", function()
        local api = client(20000, 19000)
        round_from_the_host(api, 20000, 15)
        t.eq(api.manual_reroll_remaining(), COOLDOWN,
            "the client added the host's head start to the cooldown")
        t.eq(api.manual_reroll_label(), "ANOTHER LEVEL - 2:00",
            "the client shows a cooldown the host never set")
    end)

    s.test("the countdown on a client reaches zero two minutes later", function()
        local api, ctl = client(20000, 19000)
        round_from_the_host(api, 20000, 15)
        ctl.timer = 1000 + COOLDOWN - 1
        t.eq(api.manual_reroll_remaining(), 1, "the client is a frame ahead of the host")
        ctl.timer = 1000 + COOLDOWN
        t.eq(api.manual_reroll_remaining(), 0, "the button never becomes available")
        t.eq(api.manual_reroll_label(), "ANOTHER LEVEL - READY",
            "the label does not say the button is ready")
        ctl.timer = 1000 + COOLDOWN + 1
        t.eq(api.manual_reroll_remaining(), 0, "a deadline already passed counted a negative")
    end)

    s.test("a client with no sample yet still counts down", function()
        -- The first frames of a round can arrive before the first published
        -- sample. The answer is then no better than it was, but it must not be
        -- a negative, a nil or a crash.
        local api, ctl = harness.load(function(c) c.is_server = false end)
        api.set_language(0)
        ctl.timer = 1000
        round_from_the_host(api, 20000, 15)
        t.ok(api.manual_reroll_remaining() > 0,
            "a client with no sample should still count something down")
    end)

    -- the round clock and the Chaos countdown --------------------------------

    s.test("the round clock on a client counts the host's round down", function()
        local api, ctl = client(20000, 19000)
        round_from_the_host(api, 20000, 15)
        -- Thirteen minutes into a fifteen-minute round, two are left.
        ctl.timer = 1000 + 13 * 60 * 30
        local seen
        api.mod_namespace.draw_round_status_panels = function(remaining) seen = remaining end
        api.draw_hud()
        t.eq(seen, 2 * 60 * 30, "the HUD clock is counting from the client's own counter")
    end)

    s.test("a round clock past its end draws zero, not a negative", function()
        local api, ctl = client(20000, 19000)
        round_from_the_host(api, 20000, 15)
        ctl.timer = 1000 + 16 * 60 * 30                 -- a minute past the end
        local seen
        api.mod_namespace.draw_round_status_panels = function(remaining) seen = remaining end
        api.draw_hud()
        t.eq(seen, 0, "the HUD counted past the end of the round")
    end)

    s.test("the menu's status row counts the host's round down", function()
        local api, ctl = client(20000, 19000)
        round_from_the_host(api, 20000, 15)
        ctl.timer = 1000 + 14 * 60 * 30 + 30 * 30      -- thirty seconds left
        api.runtime.config_open = true
        ctl.hud.text = {}
        api.draw_config_menu()
        t.eq(line_starting(ctl, "  STATUS - ACTIVE"), "  STATUS - ACTIVE 0:30",
            "the status row is counting from the client's own counter")
    end)

    s.test("the Chaos reroll countdown on a client is the host's", function()
        local api, ctl = client(20000, 19000)
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        gGlobalSyncTable.sh5_chaos_next_reroll = 20000 + 150
        ctl.hud.text = {}
        api.draw_objective_panel(api.get_goal(1), nil, nil)
        t.eq(line_starting(ctl, "NEW MODIFIERS IN"), "NEW MODIFIERS IN: 5",
            "the Chaos countdown is counting from the client's own counter")
    end)
end
