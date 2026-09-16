-- The host side of the round: the clock, the goal pool, the winner tally, the
-- player records that survive a disconnect, and the per-frame loop.
--
-- Everything here runs only on the server. The suite drives it the way the game
-- does -- set the synchronized state, call the host function, read the
-- synchronized result -- because that is the only contract a client ever sees.
--
-- Values are pinned as literals on purpose. A test that asks the code what it
-- does agrees with the code whatever the code says, so the numbers below come
-- from the released v1.1 file and from CHANGELOG.md, not from running the mod.
--
-- Two changes to the host half are deliberately NOT guarded here, because no
-- reachable state tells them apart from the released behaviour:
--
--   * `goal_is_active_for_anyone` starting its scan at player 1 instead of
--     player 0. It is a second, independent check on top of `host_used_goals`,
--     and within a round every connected player's goal is already in that
--     table -- the only writer of a player's goal that skips it, the reconnect
--     restore, can only return a goal this round already assigned.
--   * `winner_text_and_score` seeding its best score at -2 rather than -1.
--     Scores are never negative, so both seeds lose to every real score.
--
-- Two more branches of the host half are unreachable rather than untested, and
-- no test can honestly cover them:
--
--   * the reason `host_start_round` gives when preparing a player fails
--     ("not enough unused goals"). The player count is checked against the pool
--     before the roster loop runs, and each player prepared releases the goal
--     they were holding, so the loop cannot run dry after that check passes.
--   * the `or 8` default interval in the Boss loop. Every index that can be
--     chosen as an attack -- 2, 3, 5 through 11 -- has its own entry in the
--     interval table, so the default is never read.

return function(t, harness)
    local s = t.suite("round_host")

    -- Connect exactly `n` player slots, starting at slot 0. The stub builds
    -- gNetworkPlayers when the engine is installed, so the flags have to be set
    -- afterwards rather than through ctl.player_count.
    local function connect(n)
        for i = 0, 15 do gNetworkPlayers[i].connected = i < n end
    end

    -- Mark every star in the save file as already collected except the goals
    -- whose ids are listed, which shrinks the pool the host draws from to
    -- something a test can reason about.
    local function only_goals(api, ctl, keep)
        local flags = {}
        for _, goal in ipairs(api.goals) do
            local course = ctl.course_of[goal.level] - 1
            flags[course] = (flags[course] or 0) | (1 << (goal.act - 1))
        end
        for _, id in ipairs(keep) do
            local goal = api.goals[id]
            local course = ctl.course_of[goal.level] - 1
            flags[course] = flags[course] & ~(1 << (goal.act - 1))
        end
        ctl.save.star_flags[0] = flags
    end

    local function chat_text(ctl)
        local out = {}
        for _, m in ipairs(ctl.chat) do out[#out + 1] = tostring(m) end
        return table.concat(out, " | ")
    end

    -- ---------------------------------------------------------------------
    -- Round length
    -- ---------------------------------------------------------------------

    -- Minutes by connected player count, pinned from the released file. A
    -- bigger lobby gets a shorter round, because every player is handed their
    -- own goal out of the same 93-star pool.
    local TIME_RANGE = {
        [1] = { 13, 22 }, [2] = { 11, 20 }, [3] = { 10, 18 }, [4] = { 9, 16 },
        [5] = { 8, 14 },  [6] = { 8, 14 },  [7] = { 7, 11 },  [8] = { 7, 11 },
        [9] = { 6, 9 },   [10] = { 6, 9 },  [11] = { 5, 7 },  [12] = { 5, 7 },
        [13] = { 5, 6 },  [14] = { 5, 6 },  [15] = { 4, 5 },  [16] = { 4, 5 },
    }

    s.test("every lobby size gets its own round length", function()
        local api = harness.load()
        gGlobalSyncTable.sh5_mode = 0          -- not Boss: Boss has its own table
        for count = 1, 16 do
            local low, high = api.time_range(count)
            t.eq(low, TIME_RANGE[count][1], count .. " players: wrong minimum")
            t.eq(high, TIME_RANGE[count][2], count .. " players: wrong maximum")
        end
    end)

    s.test("an empty lobby falls into the one-player band", function()
        local api = harness.load()
        gGlobalSyncTable.sh5_mode = 0
        local low, high = api.time_range(0)
        t.eq(low, 13, "an empty lobby should get the longest minimum")
        t.eq(high, 22, "an empty lobby should get the longest maximum")
    end)

    -- ---------------------------------------------------------------------
    -- Counting players, and naming them
    -- ---------------------------------------------------------------------

    s.test("the player count includes slot zero and stops at the last connection", function()
        local api = harness.load()
        for _, n in ipairs({ 0, 1, 2, 3, 7, 16 }) do
            connect(n)
            t.eq(api.player_count(), n, "wrong count for " .. n .. " connected players")
        end
    end)

    s.test("a player is recorded under their global index", function()
        local api = harness.load()
        connect(3)
        gNetworkPlayers[2].globalIndex = 9
        t.eq(api.record_key(2), "g:9", "the global index should name the record")
    end)

    s.test("a player with no global index falls back to their slot", function()
        local api = harness.load()
        connect(3)
        gNetworkPlayers[2].globalIndex = nil
        t.eq(api.record_key(2), "slot:2", "the slot should name the record")
    end)

    s.test("a slot with no player at all has no record key", function()
        local api = harness.load()
        gNetworkPlayers[5] = nil
        t.is_nil(api.record_key(5), "an absent player should have no key")
    end)

    -- ---------------------------------------------------------------------
    -- Starting a round
    -- ---------------------------------------------------------------------

    s.test("a round needs somebody to play it", function()
        local api, ctl = harness.load()
        connect(0)
        t.eq(api.host_start(15), false, "a round started with nobody connected")
        t.eq(gGlobalSyncTable.sh5_active, 0, "an empty lobby went active")
        t.ok(chat_text(ctl):find("No connected players", 1, true) ~= nil,
            "nothing explained the refusal: " .. chat_text(ctl))
    end)

    s.test("Normal mode is happy with a single player", function()
        local api = harness.load()
        connect(1)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        t.eq(api.host_start(15), true, "a solo Normal round was refused")
        t.eq(gGlobalSyncTable.sh5_active, 1, "the round did not become active")
    end)

    s.test("Team mode refuses a single player, and says so", function()
        local api, ctl = harness.load()
        connect(1)
        gGlobalSyncTable.sh5_mode = api.team_mode
        t.eq(api.host_start(15), false, "a solo Team round was allowed")
        t.eq(chat_text(ctl), "Team Mode needs at least two connected players.",
            "Team mode gave the wrong refusal")
    end)

    s.test("Chaos mode refuses a single player, and names Chaos", function()
        local api, ctl = harness.load()
        connect(1)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        t.eq(api.host_start(15), false, "a solo Chaos round was allowed")
        t.eq(chat_text(ctl), "Chaos Mode needs at least two connected players.",
            "Chaos mode gave the wrong refusal")
    end)

    s.test("the requested length is clamped into the lobby's band", function()
        -- Two players: 11 to 20 minutes.
        for _, case in ipairs({ { 99, 20 }, { 1, 11 }, { 15, 15 } }) do
            local api = harness.load()
            connect(2)
            gGlobalSyncTable.sh5_mode = api.normal_mode
            api.host_start(case[1])
            t.eq(gGlobalSyncTable.sh5_config_minutes, case[2],
                case[1] .. " minutes should have become " .. case[2])
        end
    end)

    s.test("a fractional length is rounded down, never up", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(12.7)
        t.eq(gGlobalSyncTable.sh5_config_minutes, 12,
            "12.7 minutes should have become 12")
    end)

    s.test("the end frame is the start frame plus the round length", function()
        local api, ctl = harness.load()
        connect(2)
        ctl.timer = 500
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        t.eq(gGlobalSyncTable.sh5_start_frame, 500, "the round started at the wrong frame")
        t.eq(gGlobalSyncTable.sh5_end_frame, 500 + 15 * 60 * 30,
            "15 minutes is 15 * 60 seconds at 30 frames per second")
    end)

    s.test("a star race needs one unused goal per player", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        only_goals(api, ctl, { 1 })            -- one goal, two players
        t.eq(api.host_start(15), false, "a round started with too few goals")
        -- The count has to be refused up front. A round that starts, runs out
        -- of goals half way through the roster and ends itself also returns
        -- false and says the same thing in chat, so the round counter is what
        -- separates the two: it is only bumped once a round really begins.
        t.eq(gGlobalSyncTable.sh5_round, 0, "the round was started before being refused")
        t.ok(chat_text(ctl):find("Not enough unused goals", 1, true) ~= nil,
            "nothing explained the refusal: " .. chat_text(ctl))
    end)

    s.test("exactly one unused goal per player is enough", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        only_goals(api, ctl, { 1, 2 })         -- two goals, two players
        t.eq(api.host_start(15), true, "a round with exactly enough goals was refused")
    end)

    s.test("Boss mode does not care that every star is already collected", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        only_goals(api, ctl, {})               -- nothing left to collect
        t.eq(api.host_start(15), true, "Boss mode was blocked by the star pool")
    end)

    s.test("Chaos mode does not care either", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        only_goals(api, ctl, {})
        t.eq(api.host_start(15), true, "Chaos mode was blocked by the star pool")
    end)

    s.test("every connected player is enrolled, slot zero included", function()
        local api = harness.load()
        connect(3)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        for i = 0, 2 do
            t.eq(gPlayerSyncTable[i].sh5_enrolled, 1, "player " .. i .. " was not enrolled")
            t.ne(gPlayerSyncTable[i].sh5_goal, 0, "player " .. i .. " got no goal")
        end
    end)

    s.test("the banner names the mode and the length", function()
        -- Two players: a star hunt runs 11 to 20 minutes, Bowser 4 to 9, so the
        -- Boss row asks for a length that is inside its own, shorter band.
        for _, case in ipairs({ { "normal_mode", "NORMAL", 15 }, { "team_mode", "TEAM", 15 },
                                { "chaos_mode", "CHAOS", 15 }, { "boss_mode", "BOSS", 7 } }) do
            local api, ctl = harness.load()
            connect(2)
            gGlobalSyncTable.sh5_mode = api[case[1]]
            api.host_start(case[3])
            t.eq(#ctl.popups, 1, case[2] .. ": expected exactly one banner")
            t.eq(ctl.popups[1].text,
                "STARHUNT " .. case[2] .. ": " .. case[3] .. " MINUTES",
                case[2] .. ": wrong banner text")
            t.eq(ctl.popups[1].lines, 1, case[2] .. ": the banner is one line tall")
        end
    end)

    s.test("each round gets the next round number", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        local first = gGlobalSyncTable.sh5_round
        api.host_end("stopped")
        api.host_start(15)
        t.eq(gGlobalSyncTable.sh5_round, first + 1, "the round number did not advance")
    end)

    -- ---------------------------------------------------------------------
    -- Ending a round, and who won it
    -- ---------------------------------------------------------------------

    -- Start a Normal round with `n` players and give player `i` a score.
    local function race(n, scores)
        local api, ctl = harness.load()
        connect(n)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        for i, score in pairs(scores or {}) do gPlayerSyncTable[i].sh5_score = score end
        return api, ctl
    end

    s.test("ending a round twice publishes one result, not two", function()
        local api = race(2, { [0] = 3 })
        api.host_end("stopped")
        local seq = gGlobalSyncTable.sh5_result_seq
        t.eq(seq, 1, "the first ending did not publish a result")
        gPlayerSyncTable[0].sh5_score = 99
        api.host_end("stopped again")
        t.eq(gGlobalSyncTable.sh5_result_seq, seq,
            "a second ending overwrote the result of a round that was already over")
        t.eq(gGlobalSyncTable.sh5_result_reason, "stopped",
            "the stale ending rewrote the reason")
    end)

    s.test("the highest score wins, slot zero included", function()
        local api = race(3, { [0] = 5, [1] = 2, [2] = 1 })
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P0", "the leader did not win")
        t.eq(gGlobalSyncTable.sh5_result_score, 5, "the winning score is wrong")
    end)

    s.test("a tie names everybody who tied", function()
        local api = race(3, { [0] = 4, [1] = 4, [2] = 1 })
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P0 and P1", "a tie was not reported as one")
        t.eq(gGlobalSyncTable.sh5_result_score, 4, "the tied score is wrong")
    end)

    s.test("a player who is not enrolled cannot win", function()
        local api = race(2, { [0] = 1, [1] = 9 })
        gPlayerSyncTable[1].sh5_enrolled = 0
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P0",
            "an unenrolled player took the win")
        t.eq(gGlobalSyncTable.sh5_result_score, 1, "the winning score is wrong")
    end)

    s.test("with nobody enrolled the round has no winner", function()
        local api = race(2, {})
        for i = 0, 1 do gPlayerSyncTable[i].sh5_enrolled = 0 end
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "Nobody", "somebody won an empty round")
        t.eq(gGlobalSyncTable.sh5_result_score, 0, "an empty round scored")
    end)

    s.test("a player who drops out at the last second still places", function()
        local api = race(2, { [0] = 1, [1] = 7 })
        api.remember_player(1)                 -- the host's snapshot of player 1
        gNetworkPlayers[1].connected = false   -- and then they drop
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P1",
            "a disconnected leader was erased from the result")
        t.eq(gGlobalSyncTable.sh5_result_score, 7, "the disconnected score was lost")
    end)

    s.test("a player who is still connected is counted once, not twice", function()
        local api = race(2, { [0] = 3, [1] = 3 })
        api.remember_player(0)                 -- a snapshot of somebody still here
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P0 and P1",
            "the snapshot was counted as a second player")
    end)

    s.test("Bowser wins when the clock beats the players", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        api.host_start(7)
        api.host_end("boss time expired")
        t.eq(gGlobalSyncTable.sh5_result_winner, "BOWSER", "Bowser did not win the timeout")
        t.eq(gGlobalSyncTable.sh5_result_score, 0, "a lost Boss round scored")
    end)

    s.test("the players win when Bowser is defeated", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        api.host_start(7)
        gPlayerSyncTable[0].sh5_score = 99     -- star scores are irrelevant here
        api.host_end("boss defeated")
        t.eq(gGlobalSyncTable.sh5_result_winner, "TEAM STARHUNT", "nobody beat Bowser")
        t.eq(gGlobalSyncTable.sh5_result_score, 1, "a won Boss round scored wrong")
    end)

    s.test("Chaos names its last player standing, and only then", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        api.host_start(15)
        gGlobalSyncTable.sh5_chaos_winner = "P1"
        api.host_end("chaos last standing")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P1", "the survivor was not named")
        t.eq(gGlobalSyncTable.sh5_result_score, 1, "the survivor did not score")

        local api2 = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api2.chaos_mode
        api2.host_start(15)
        gGlobalSyncTable.sh5_chaos_winner = "P1"
        api2.host_end("time expired")
        t.eq(gGlobalSyncTable.sh5_result_winner, "Nobody",
            "a Chaos round that ran out of time should have no survivor")
        t.eq(gGlobalSyncTable.sh5_result_score, 0, "a timed-out Chaos round scored")
    end)

    s.test("Team mode reports the leading team and both totals", function()
        for _, case in ipairs({ { 5, 2, "RED TEAM", 5 }, { 2, 5, "BLUE TEAM", 5 },
                                { 3, 3, "TIE", 3 } }) do
            local api = harness.load()
            connect(2)
            gGlobalSyncTable.sh5_mode = api.team_mode
            api.host_start(15)
            gPlayerSyncTable[0].sh5_team = api.team_red
            gPlayerSyncTable[1].sh5_team = api.team_blue
            gPlayerSyncTable[0].sh5_score = case[1]
            gPlayerSyncTable[1].sh5_score = case[2]
            api.host_end("stopped")
            t.eq(gGlobalSyncTable.sh5_result_winner, case[3],
                case[1] .. "-" .. case[2] .. ": wrong team won")
            t.eq(gGlobalSyncTable.sh5_result_score, case[4],
                case[1] .. "-" .. case[2] .. ": wrong winning score")
            t.eq(gGlobalSyncTable.sh5_result_red_score, case[1], "red total is wrong")
            t.eq(gGlobalSyncTable.sh5_result_blue_score, case[2], "blue total is wrong")
        end
    end)

    s.test("ending a round clears every player, slot zero included", function()
        local api = race(3, { [0] = 1, [1] = 2, [2] = 3 })
        api.host_end("stopped")
        for i = 0, 2 do
            t.eq(gPlayerSyncTable[i].sh5_goal, 0, "player " .. i .. " kept their goal")
            t.eq(gPlayerSyncTable[i].sh5_enrolled, 0, "player " .. i .. " is still enrolled")
            t.eq(gPlayerSyncTable[i].sh5_jump_count, -1, "player " .. i .. " kept a jump limit")
            t.eq(gPlayerSyncTable[i].sh5_return_seq, gGlobalSyncTable.sh5_return_seq,
                "player " .. i .. " was not told to go back to the lobby")
        end
        t.eq(gGlobalSyncTable.sh5_active, 0, "the round is still active")
    end)

    s.test("the server's own PvP settings are put back", function()
        local api = harness.load()
        connect(2)
        gServerSettings.playerInteractions = 42
        gServerSettings.pvpType = 7
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        t.ne(gServerSettings.playerInteractions, 42,
            "StarHunt did not take over player interactions")
        api.host_end("stopped")
        t.eq(gServerSettings.playerInteractions, 42, "the host's own setting was not restored")
        t.eq(gServerSettings.pvpType, 7, "the host's own PvP type was not restored")
    end)

    s.test("scores survive one frame past the result, then reset", function()
        local api, ctl = harness.load()
        connect(2)
        ctl.timer = 100
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        gPlayerSyncTable[0].sh5_score = 4
        api.host_end("stopped")
        -- RESULT_DISPLAY_FRAMES is 1: the winner is announced first, and the
        -- scores clear on the following frame.
        t.eq(gGlobalSyncTable.sh5_reset_scores_at, 101, "the reset was scheduled wrong")

        api.host_reset_scores()
        t.eq(gPlayerSyncTable[0].sh5_score, 4, "the score cleared on the result frame itself")
        ctl.timer = 101
        api.host_reset_scores()
        t.eq(gPlayerSyncTable[0].sh5_score, 0, "the score never cleared")
        t.eq(gGlobalSyncTable.sh5_reset_scores_at, 0, "the reset did not disarm itself")
    end)

    s.test("a client never resets anybody's score", function()
        local api, ctl = harness.load()
        connect(2)
        ctl.timer = 100
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        gPlayerSyncTable[0].sh5_score = 4
        api.host_end("stopped")
        ctl.timer = 500
        ctl.is_server = false
        api.host_reset_scores()
        t.eq(gPlayerSyncTable[0].sh5_score, 4, "a client cleared the scores")
    end)

    s.test("a new round starting cancels a pending score reset", function()
        local api, ctl = harness.load()
        connect(2)
        ctl.timer = 100
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        gPlayerSyncTable[0].sh5_score = 4
        api.host_end("stopped")
        api.host_start(15)                     -- the next round begins first
        gPlayerSyncTable[0].sh5_score = 6
        ctl.timer = 500
        api.host_reset_scores()
        t.eq(gPlayerSyncTable[0].sh5_score, 6, "the new round's score was wiped")
        t.eq(gGlobalSyncTable.sh5_reset_scores_at, 0, "the stale reset is still armed")
    end)

    -- ---------------------------------------------------------------------
    -- Player records: what the host remembers across a disconnect
    -- ---------------------------------------------------------------------

    -- Player 1 leads on 7 points, the host snapshots them, and they drop. If
    -- the snapshot was taken, they still win; if it was refused, player 0 does.
    local function leader_after_drop(before_snapshot)
        local api, ctl = race(2, { [0] = 1, [1] = 7 })
        if before_snapshot ~= nil then before_snapshot(api, ctl) end
        api.remember_player(1)
        gGlobalSyncTable.sh5_active = 1
        ctl.is_server = true
        gNetworkPlayers[1].connected = false
        api.host_end("stopped")
        return gGlobalSyncTable.sh5_result_winner
    end

    s.test("the host snapshots a player while the round runs", function()
        t.eq(leader_after_drop(nil), "P1", "the snapshot was never taken")
    end)

    s.test("a client takes no snapshot", function()
        t.eq(leader_after_drop(function(_, ctl) ctl.is_server = false end), "P0",
            "a client wrote into the host's records")
    end)

    s.test("no snapshot is taken outside a round", function()
        t.eq(leader_after_drop(function() gGlobalSyncTable.sh5_active = 0 end), "P0",
            "a player was recorded with no round running")
    end)

    s.test("an unenrolled player is not snapshotted", function()
        t.eq(leader_after_drop(function() gPlayerSyncTable[1].sh5_enrolled = 0 end), "P0",
            "somebody who was not playing was recorded")
    end)

    s.test("a nameless player is not snapshotted", function()
        t.eq(leader_after_drop(function() gNetworkPlayers[1].name = "" end), "P0",
            "a player with no name was recorded")
    end)

    s.test("a disconnect hook with no player is harmless", function()
        local api = race(2, { [0] = 1 })
        api.disconnected(nil)                  -- must not raise
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P0", "the round ended wrong")
    end)

    s.test("the disconnect hook records the player who left", function()
        local api = race(2, { [0] = 1, [1] = 7 })
        api.disconnected({ playerIndex = 1 })
        gNetworkPlayers[1].connected = false
        api.host_end("stopped")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P1",
            "the leaving player's score was lost")
    end)

    s.test("a joining player is pushed through the host's preparation", function()
        local api = race(2, {})
        gPlayerSyncTable[1].sh5_enrolled = 1
        api.connected({ playerIndex = 1 })
        t.eq(gPlayerSyncTable[1].sh5_enrolled, 0,
            "the arriving player kept the previous occupant's enrolment")
    end)

    s.test("the host is never unenrolled by the join hook", function()
        local api = race(2, {})
        api.connected({ playerIndex = 0 })
        t.eq(gPlayerSyncTable[0].sh5_enrolled, 1, "the host unenrolled itself")
    end)

    s.test("the join hook does nothing outside a round", function()
        local api = race(2, {})
        api.host_end("stopped")
        gPlayerSyncTable[1].sh5_enrolled = 1
        api.connected({ playerIndex = 1 })
        t.eq(gPlayerSyncTable[1].sh5_enrolled, 1, "a player was unenrolled with no round")
    end)

    -- ---------------------------------------------------------------------
    -- Reconnecting
    -- ---------------------------------------------------------------------

    -- Player 1 plays, is snapshotted, drops, and comes back. `between` runs
    -- while they are away, which is where a test changes their identity.
    local function reconnect(between)
        local api, ctl = race(2, { [0] = 1, [1] = 5 })
        gPlayerSyncTable[1].sh5_lifetime_stars = 30
        local goal = gPlayerSyncTable[1].sh5_goal
        api.remember_player(1)
        gNetworkPlayers[1].connected = false
        if between ~= nil then between(api, ctl) end
        gNetworkPlayers[1].connected = true
        gPlayerSyncTable[1].sh5_enrolled = 0
        gPlayerSyncTable[1].sh5_score = 0
        gPlayerSyncTable[1].sh5_goal = 0
        gPlayerSyncTable[1].sh5_lifetime_stars = 0
        api.host_late_joiner(1)
        return api, ctl, goal
    end

    s.test("a reconnecting player gets their score and their goal back", function()
        local _, ctl, goal = reconnect(nil)
        t.eq(gPlayerSyncTable[1].sh5_score, 5, "the score was not restored")
        t.eq(gPlayerSyncTable[1].sh5_goal, goal, "a different goal was handed out")
        t.eq(gPlayerSyncTable[1].sh5_enrolled, 1, "the returning player is not enrolled")
        t.eq(gPlayerSyncTable[1].sh5_lifetime_stars, 30,
            "the lifetime star total was not restored")
        t.eq(chat_text(ctl), "P1 joined StarHunt and received a goal!",
            "the wrong welcome was sent")
    end)

    s.test("a returning player keeps the larger lifetime star total", function()
        -- The record holds what the host last saw. A client that comes back
        -- advertising a bigger total has earned stars elsewhere since, so the
        -- larger of the two is the one that survives the reconnect.
        local api = race(2, { [0] = 1, [1] = 5 })
        gPlayerSyncTable[1].sh5_lifetime_stars = 30
        api.remember_player(1)
        gNetworkPlayers[1].connected = false
        gNetworkPlayers[1].connected = true
        gPlayerSyncTable[1].sh5_enrolled = 0
        gPlayerSyncTable[1].sh5_lifetime_stars = 50
        api.host_late_joiner(1)
        t.eq(gPlayerSyncTable[1].sh5_lifetime_stars, 50,
            "the host's older, smaller total overwrote the client's")
    end)

    s.test("a different player in the same slot inherits nothing", function()
        reconnect(function()
            gNetworkPlayers[1].name = "SOMEONE ELSE"
        end)
        t.eq(gPlayerSyncTable[1].sh5_score, 0,
            "a new arrival inherited the previous occupant's score")
    end)

    s.test("a reconnect under a new global index is matched by name", function()
        local _, _, goal = reconnect(function()
            -- Co-op DX can hand the returning player a different global index.
            gNetworkPlayers[1].globalIndex = 11
        end)
        t.eq(gPlayerSyncTable[1].sh5_score, 5,
            "the returning player was not recognized by name")
        t.eq(gPlayerSyncTable[1].sh5_goal, goal, "their goal was not restored")
    end)

    s.test("two records with the same name match neither", function()
        local api = race(3, { [0] = 1, [1] = 5, [2] = 5 })
        gNetworkPlayers[1].name = "TWIN"
        gNetworkPlayers[2].name = "TWIN"
        api.remember_player(1)
        api.remember_player(2)
        gNetworkPlayers[1].connected = false
        gNetworkPlayers[2].connected = false

        gNetworkPlayers[1].connected = true
        gNetworkPlayers[1].globalIndex = 12    -- neither record can be keyed
        gPlayerSyncTable[1].sh5_enrolled = 0
        gPlayerSyncTable[1].sh5_score = 0
        api.host_late_joiner(1)
        t.eq(gPlayerSyncTable[1].sh5_score, 0,
            "an ambiguous name was allowed to claim somebody's score")
    end)

    s.test("a name that matches a player who is still here is not a reconnect", function()
        -- The holder is the host's own slot deliberately: the scan that works
        -- out which records belong to somebody still connected has to start at
        -- player 0, and starting it at 1 would let their record be claimed.
        local api = race(3, { [0] = 5, [1] = 0, [2] = 0 })
        gNetworkPlayers[0].name = "TWIN"
        gNetworkPlayers[2].name = "TWIN"
        api.remember_player(0)                 -- P0 is recorded and stays connected
        gPlayerSyncTable[2].sh5_enrolled = 0
        gPlayerSyncTable[2].sh5_score = 0
        gNetworkPlayers[2].globalIndex = 13
        api.host_late_joiner(2)
        t.eq(gPlayerSyncTable[2].sh5_score, 0,
            "a connected player's record was handed to somebody else")
    end)

    s.test("a player's own record beats a stranger who shares their name", function()
        -- Matching on the key is what makes this work. Falling back to the name
        -- would find two records called TWIN, give up as ambiguous, and hand
        -- the returning player nothing.
        local api = race(3, { [0] = 1, [1] = 5, [2] = 9 })
        gNetworkPlayers[1].name = "TWIN"
        gNetworkPlayers[2].name = "TWIN"
        api.remember_player(1)
        api.remember_player(2)
        gNetworkPlayers[1].connected = false
        gNetworkPlayers[2].connected = false

        gNetworkPlayers[2].connected = true    -- P2 comes back under their own key
        gPlayerSyncTable[2].sh5_enrolled = 0
        gPlayerSyncTable[2].sh5_score = 0
        api.host_late_joiner(2)
        t.eq(gPlayerSyncTable[2].sh5_score, 9,
            "the returning player was not matched by their own record key")
    end)

    s.test("a reconnecting player is put back on a real team", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.team_mode
        api.host_start(15)
        gPlayerSyncTable[1].sh5_score = 4
        api.remember_player(1)
        gNetworkPlayers[1].connected = false
        gNetworkPlayers[1].connected = true
        gPlayerSyncTable[1].sh5_enrolled = 0
        gPlayerSyncTable[1].sh5_team = 0
        api.host_late_joiner(1)
        local team = gPlayerSyncTable[1].sh5_team
        t.ok(team == api.team_red or team == api.team_blue,
            "the returning player came back on no team at all: " .. tostring(team))
    end)

    -- ---------------------------------------------------------------------
    -- Late joiners
    -- ---------------------------------------------------------------------

    s.test("a player who is already enrolled is left alone", function()
        local api, ctl = race(2, { [0] = 1, [1] = 2 })
        local goal = gPlayerSyncTable[1].sh5_goal
        t.eq(api.host_late_joiner(1), true, "an enrolled player was refused")
        t.eq(gPlayerSyncTable[1].sh5_goal, goal, "an enrolled player was given a new goal")
        t.eq(chat_text(ctl), "", "an enrolled player was welcomed again")
    end)

    s.test("a Chaos latecomer is told they are a spectator", function()
        local api, ctl = harness.load()
        connect(3)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        api.host_start(15)
        gPlayerSyncTable[2].sh5_enrolled = 0
        ctl.chat = {}
        api.host_late_joiner(2)
        t.eq(chat_text(ctl), "P2 joined Chaos as a spectator.",
            "the Chaos latecomer got the star-hunt welcome")
    end)

    s.test("a latecomer with no goal left is refused and told why", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        only_goals(api, ctl, { 1, 2 })         -- exactly two goals for two players
        api.host_start(15)
        connect(3)                             -- a third player arrives
        gPlayerSyncTable[2].sh5_enrolled = 0
        ctl.chat = {}
        t.eq(api.host_late_joiner(2), false, "a goalless latecomer was accepted")
        t.eq(gPlayerSyncTable[2].sh5_enrolled, -1,
            "the refused player was not marked as a spectator")
        t.eq(chat_text(ctl), "No unclaimed goal is left for P2.",
            "the refusal was not explained")
    end)

    -- ---------------------------------------------------------------------
    -- The per-frame host loop
    -- ---------------------------------------------------------------------

    s.test("a client never runs the host loop", function()
        local api, ctl = race(2, {})
        gPlayerSyncTable[0].sh5_done = 1
        ctl.is_server = false
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_score or 0, 0, "a client scored a star for somebody")
    end)

    s.test("the loop does nothing once the round is over", function()
        local api = race(2, {})
        api.host_end("stopped")
        local seq = gGlobalSyncTable.sh5_result_seq
        gPlayerSyncTable[0].sh5_done = 1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_result_seq, seq, "the loop restarted a finished round")
    end)

    s.test("the round ends on the end frame itself, not a frame later", function()
        local api, ctl = race(2, {})
        local ends_at = gGlobalSyncTable.sh5_end_frame
        ctl.timer = ends_at - 1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 1, "the round ended a frame early")
        ctl.timer = ends_at
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 0, "the round outlived its clock")
        t.eq(gGlobalSyncTable.sh5_result_reason, "time expired", "wrong ending reason")
    end)

    s.test("a Boss round that runs out of time says so", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        api.host_start(7)
        ctl.timer = gGlobalSyncTable.sh5_end_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_result_reason, "boss time expired",
            "a Boss timeout was reported as a star hunt timeout")
        t.eq(gGlobalSyncTable.sh5_result_winner, "BOWSER", "Bowser did not take the timeout")
    end)

    s.test("collecting a star scores a point and hands out a new goal", function()
        local api = race(2, {})
        local before = gPlayerSyncTable[0].sh5_goal
        gPlayerSyncTable[0].sh5_done = 1
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_score, 1, "the star did not score")
        t.ne(gPlayerSyncTable[0].sh5_goal, before, "the same goal was handed back")
        t.ne(gPlayerSyncTable[0].sh5_goal, 0, "no replacement goal was handed out")
    end)

    s.test("the same star never scores twice", function()
        local api = race(2, {})
        gPlayerSyncTable[0].sh5_done = 1
        api.host_update()
        api.host_update()
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_score, 1, "one star scored more than once")
    end)

    s.test("a player with no goal is not scored for finishing it", function()
        local api = race(2, {})
        gPlayerSyncTable[0].sh5_goal = 0
        gPlayerSyncTable[0].sh5_done = 1
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_score or 0, 0, "a star was scored with no goal set")
    end)

    s.test("the loop enrols a player who arrived without one", function()
        local api = race(2, {})
        gPlayerSyncTable[1].sh5_enrolled = 0
        api.host_update()
        t.eq(gPlayerSyncTable[1].sh5_enrolled, 1, "the arriving player was never enrolled")
        t.ne(gPlayerSyncTable[1].sh5_goal, 0, "the arriving player got no goal")
    end)

    s.test("a spectator is left as a spectator", function()
        local api = race(2, {})
        gPlayerSyncTable[1].sh5_enrolled = -1
        local score = gPlayerSyncTable[1].sh5_score
        gPlayerSyncTable[1].sh5_done = 1
        api.host_update()
        t.eq(gPlayerSyncTable[1].sh5_enrolled, -1, "a spectator was dragged into the round")
        t.eq(gPlayerSyncTable[1].sh5_score, score, "a spectator scored")
    end)

    s.test("forfeiting swaps the goal without scoring", function()
        local api = race(2, {})
        local before = gPlayerSyncTable[0].sh5_goal
        gPlayerSyncTable[0].sh5_forfeit = 1
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_score or 0, 0, "a forfeit scored a point")
        t.ne(gPlayerSyncTable[0].sh5_goal, before, "the forfeited goal came back")
        t.ne(gPlayerSyncTable[0].sh5_goal, 0, "no replacement goal was handed out")
    end)

    s.test("a forfeit is honoured once per press", function()
        local api = race(2, {})
        gPlayerSyncTable[0].sh5_forfeit = 1
        api.host_update()
        local after_first = gPlayerSyncTable[0].sh5_goal
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_goal, after_first,
            "one forfeit kept rerolling the goal")
    end)

    s.test("a forfeit does not hand back the same kind of modifier", function()
        local api = race(2, {})
        local old_goal = api.get_goal(gPlayerSyncTable[0].sh5_goal)
        local old_kind = old_goal.mods[gPlayerSyncTable[0].sh5_modifier].kind
        gPlayerSyncTable[0].sh5_forfeit = 1
        api.host_update()
        local new_goal = api.get_goal(gPlayerSyncTable[0].sh5_goal)
        local new_kind = new_goal.mods[gPlayerSyncTable[0].sh5_modifier].kind
        t.ne(new_kind, old_kind, "the forfeited challenge came straight back")
    end)

    s.test("running out of goals ends the round", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        only_goals(api, ctl, { 1, 2 })         -- exactly two, one each
        api.host_start(15)
        gPlayerSyncTable[0].sh5_done = 1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 0, "the round continued with no goals left")
        t.eq(gGlobalSyncTable.sh5_result_reason, "all available goals were assigned",
            "the round ended for the wrong reason")
    end)

    -- manual reroll ---------------------------------------------------------
    -- host_prepare_player puts the cooldown 120 seconds ahead, so a reroll only
    -- lands once the clock has passed it.

    s.test("a manual reroll after the cooldown hands out a new goal", function()
        local api, ctl = race(2, {})
        local before = gPlayerSyncTable[0].sh5_goal
        gPlayerSyncTable[0].sh5_manual_reroll_request = 1
        ctl.timer = 4000                       -- past 120 * 30 frames
        api.host_update()
        t.ne(gPlayerSyncTable[0].sh5_goal, before, "the reroll did nothing")
        t.eq(gPlayerSyncTable[0].sh5_manual_reroll_ack, 1, "the request was not acknowledged")
    end)

    s.test("a manual reroll before the cooldown is acknowledged but ignored", function()
        local api, ctl = race(2, {})
        local before = gPlayerSyncTable[0].sh5_goal
        gPlayerSyncTable[0].sh5_manual_reroll_request = 1
        ctl.timer = 100                        -- still inside the cooldown
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_goal, before, "the cooldown did not hold the reroll back")
        t.eq(gPlayerSyncTable[0].sh5_manual_reroll_ack, 1,
            "an ignored request must still be acknowledged, or it repeats forever")
    end)

    s.test("the reroll cooldown ends on its own frame, not the one after", function()
        local api, ctl = race(2, {})
        local before = gPlayerSyncTable[0].sh5_goal
        local ready_at = gPlayerSyncTable[0].sh5_manual_reroll_ready_frame
        ctl.timer = ready_at - 1
        gPlayerSyncTable[0].sh5_manual_reroll_request = 1
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_goal, before, "the reroll landed a frame early")

        gPlayerSyncTable[0].sh5_manual_reroll_request = 2
        ctl.timer = ready_at
        api.host_update()
        t.ne(gPlayerSyncTable[0].sh5_goal, before,
            "the reroll did not land on the frame the cooldown expired")
    end)

    s.test("a manual reroll always sends the player to a different world", function()
        -- One draw proves little: eighteen worlds means a reroll that ignored
        -- the old level entirely would still usually land somewhere else. The
        -- cooldown is cleared by hand each time so the clock stays put.
        local api = harness.load()
        connect(1)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        local draws = 0
        for n = 1, 60 do
            local sync = gPlayerSyncTable[0]
            local old_goal = api.get_goal(sync.sh5_goal or 0)
            if old_goal == nil then break end
            sync.sh5_manual_reroll_ready_frame = 0
            sync.sh5_manual_reroll_request = n
            api.host_update()
            if gGlobalSyncTable.sh5_active ~= 1 then break end
            local new_goal = api.get_goal(sync.sh5_goal or 0)
            if new_goal == nil or new_goal == old_goal then break end
            t.ne(new_goal.level, old_goal.level,
                "draw " .. n .. ": the reroll stayed in the same world")
            draws = draws + 1
        end
        t.ok(draws >= 40, "only " .. draws .. " draws were taken; the test proves little")
    end)

    s.test("a manual reroll with no goal in hand does nothing", function()
        local api, ctl = race(2, {})
        gPlayerSyncTable[0].sh5_goal = 0
        gPlayerSyncTable[0].sh5_manual_reroll_request = 1
        ctl.timer = 4000
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_goal, 0, "a player with no goal was given one by a reroll")
    end)

    s.test("a manual reroll avoids the same world and the same challenge", function()
        local api, ctl = race(2, {})
        local old_goal = api.get_goal(gPlayerSyncTable[0].sh5_goal)
        local old_kind = old_goal.mods[gPlayerSyncTable[0].sh5_modifier].kind
        gPlayerSyncTable[0].sh5_manual_reroll_request = 1
        ctl.timer = 4000
        api.host_update()
        local new_goal = api.get_goal(gPlayerSyncTable[0].sh5_goal)
        t.ne(new_goal.level, old_goal.level, "the reroll stayed in the same world")
        t.ne(new_goal.mods[gPlayerSyncTable[0].sh5_modifier].kind, old_kind,
            "the reroll handed back the same kind of challenge")
    end)

    s.test("a reroll is honoured once per request", function()
        local api, ctl = race(2, {})
        gPlayerSyncTable[0].sh5_manual_reroll_request = 1
        ctl.timer = 4000
        api.host_update()
        local after_first = gPlayerSyncTable[0].sh5_goal
        api.host_update()
        t.eq(gPlayerSyncTable[0].sh5_goal, after_first, "one request kept rerolling")
    end)

    -- ---------------------------------------------------------------------
    -- The Boss round loop
    -- ---------------------------------------------------------------------

    -- A Bowser fight with everyone in the arena, Bowser present and idle, and
    -- none of his modifiers drawn, so each test names the ones it wants.
    local function bowser_fight(difficulty)
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        gGlobalSyncTable.sh5_difficulty = difficulty or api.medium
        api.host_start(7)
        for i = 0, MAX_PLAYERS - 1 do gNetworkPlayers[i].currLevelNum = LEVEL_BOWSER_3 end
        ctl.objects[id_bhvBowser] = { oAction = 0 }
        gGlobalSyncTable.sh5_boss_modifier_1 = 0
        gGlobalSyncTable.sh5_boss_modifier_2 = 0
        gGlobalSyncTable.sh5_boss_modifier_3 = 0
        return api, ctl
    end

    s.test("an ordinary frame of the fight ends nothing", function()
        local api = bowser_fight()
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 1, "the fight ended with nobody winning")
    end)

    s.test("any player's victory ends the fight", function()
        for _, index in ipairs({ 0, 1 }) do
            local api = bowser_fight()
            gPlayerSyncTable[index].sh5_boss_victory = 1
            api.host_update()
            t.eq(gGlobalSyncTable.sh5_active, 0,
                "player " .. index .. "'s victory did not end the fight")
            t.eq(gGlobalSyncTable.sh5_result_winner, "TEAM STARHUNT",
                "player " .. index .. "'s victory was not a win")
        end
    end)

    s.test("a latecomer to the fight is enrolled and announced", function()
        local api, ctl = bowser_fight()
        gPlayerSyncTable[1].sh5_enrolled = 0
        ctl.chat = {}
        api.host_update()
        t.eq(gPlayerSyncTable[1].sh5_enrolled, 1, "the latecomer never joined the fight")
        t.eq(chat_text(ctl), "P1 joined the Bowser battle!", "the wrong welcome was sent")
    end)

    s.test("a fighter who is already in is left alone", function()
        local api, ctl = bowser_fight()
        gPlayerSyncTable[1].sh5_score = 5
        ctl.chat = {}
        api.host_update()
        t.eq(gPlayerSyncTable[1].sh5_score, 5, "an enrolled fighter was prepared again")
        t.eq(chat_text(ctl), "", "an enrolled fighter was welcomed again")
    end)

    s.test("the host keeps the lower of its own health figure and the report", function()
        local api = bowser_fight()
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = 2          -- what the host believes
        gPlayerSyncTable[0].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round
        gPlayerSyncTable[0].sh5_boss_health_value = 4 -- a stale, higher report
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_health, 2, "a stale report healed Bowser")
    end)

    s.test("a report of no health left ends the fight", function()
        local api = bowser_fight()
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = 5
        gPlayerSyncTable[0].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round
        gPlayerSyncTable[0].sh5_boss_health_value = 0
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 0, "Bowser survived with no health")
        t.eq(gGlobalSyncTable.sh5_result_winner, "TEAM STARHUNT", "nobody was credited")
    end)

    s.test("Bowser's death animation ends the fight before his cutscene", function()
        local api, ctl = bowser_fight()
        ctl.objects[id_bhvBowser].oAction = 4
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 0, "Bowser died and the round continued")
        t.eq(gGlobalSyncTable.sh5_result_reason, "boss defeated", "wrong ending reason")
    end)

    -- Attacks ---------------------------------------------------------------
    -- host_start_round puts the first attack five seconds out, so every test
    -- below moves the clock to that frame first.

    local function attack_at(api, ctl, modifier)
        gGlobalSyncTable.sh5_boss_modifier_1 = modifier
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        return gGlobalSyncTable.sh5_boss_attack_kind
    end

    s.test("Bowser attacks with the modifiers he actually drew", function()
        for _, index in ipairs({ 2, 3, 5, 6, 7, 8, 9, 10, 11 }) do
            local api, ctl = bowser_fight()
            t.eq(attack_at(api, ctl, index), index,
                "modifier " .. index .. " did not produce its own attack")
        end
    end)

    s.test("Bowser does not attack with a modifier he does not have", function()
        local api, ctl = bowser_fight()
        gGlobalSyncTable.sh5_boss_modifier_1 = 1      -- a passive modifier
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 0, "an attack was queued out of nothing")
    end)

    s.test("the attack lands on the frame it is due, not the one after", function()
        local api, ctl = bowser_fight()
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame - 1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 0, "the attack came a frame early")
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 2, "the attack never came")
    end)

    s.test("Bowser holds still through his own intro", function()
        for _, action in ipairs({ 5, 6, 20 }) do
            local api, ctl = bowser_fight()
            ctl.objects[id_bhvBowser].oAction = action
            gGlobalSyncTable.sh5_boss_modifier_1 = 2
            ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
            api.host_update()
            t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 0,
                "action " .. action .. " (the intro) did not hold the attack back")
            t.eq(gGlobalSyncTable.sh5_boss_attack_frame, ctl.timer + 30,
                "action " .. action .. " did not push the next attack a second out")
        end
    end)

    s.test("Bowser queues nothing while a player is holding him", function()
        -- Grabbing him by the tail and spinning him is how the fight is won.
        -- The attacks all spawn at his position, so queueing one now aims it
        -- at the player holding him -- and a shockwave's stun empties that
        -- player's controller, which releases B and drops Bowser.
        local api, ctl = bowser_fight()
        ctl.objects[id_bhvBowser].oHeldState = HELD_HELD
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 0, "a held Bowser attacked")
        t.eq(gGlobalSyncTable.sh5_boss_attack_frame, ctl.timer + 30,
            "a held Bowser did not push the next attack a second out")
    end)

    s.test("Bowser queues nothing while the throw is still in the air", function()
        -- Action 1 is the vanilla thrown update, the flight to the mine. The
        -- player who threw him cannot act until he lands, so an attack aimed
        -- at them now cannot be dodged.
        local api, ctl = bowser_fight()
        ctl.objects[id_bhvBowser].oAction = 1
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 0, "a Bowser in mid-throw attacked")
        t.eq(gGlobalSyncTable.sh5_boss_attack_frame, ctl.timer + 30,
            "the throw did not push the next attack a second out")
    end)

    s.test("Bowser attacks again once he is put down", function()
        local api, ctl = bowser_fight()
        ctl.objects[id_bhvBowser].oHeldState = HELD_HELD
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        ctl.objects[id_bhvBowser].oHeldState = 0   -- HELD_FREE; the stub carries
                                                   -- only the constants the mod names
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 2, "the fight never resumed after the grab")
    end)

    s.test("no Bowser in the arena means no attacks", function()
        local api, ctl = bowser_fight()
        ctl.objects[id_bhvBowser] = nil
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 0, "a missing Bowser attacked")
        t.eq(gGlobalSyncTable.sh5_active, 1, "a missing Bowser was read as a victory")
    end)

    s.test("players outside the arena get no attacks either", function()
        local api, ctl = bowser_fight()
        for i = 0, MAX_PLAYERS - 1 do gNetworkPlayers[i].currLevelNum = LEVEL_BOB end
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_boss_attack_kind, 0,
            "Bowser attacked players who were not in his arena")
    end)

    s.test("the attack queue is eight slots wide and wraps", function()
        local api, ctl = bowser_fight()
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        for _ = 1, 9 do
            ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
            api.host_update()
        end
        t.eq(gGlobalSyncTable.sh5_boss_attack_seq, 9, "nine attacks were not queued")
        -- Attack 9 wraps back onto slot 1: ((9 - 1) % 8) + 1.
        t.eq(gGlobalSyncTable.sh5_boss_attack_queue_1, 2, "the ninth attack missed slot one")
    end)

    -- How long until the next attack.  Every number here is pinned from the
    -- released file: the per-attack interval, then the difficulty factor.
    s.test("each attack sets its own interval", function()
        local INTERVAL = { [2] = 7, [3] = 6, [5] = 9, [6] = 8,
                           [7] = 10, [8] = 9, [9] = 11, [10] = 8, [11] = 7 }
        for index, seconds in pairs(INTERVAL) do
            local api, ctl = bowser_fight()
            local due = gGlobalSyncTable.sh5_boss_attack_frame
            attack_at(api, ctl, index)
            t.eq(gGlobalSyncTable.sh5_boss_attack_frame, due + seconds * 30,
                "attack " .. index .. " scheduled the next one wrong")
        end
    end)

    s.test("difficulty stretches and squeezes the interval", function()
        -- Attack 2 is a seven second attack on Normal. Easy multiplies by 1.35,
        -- Hard by 0.78 and Nightmare by 0.55, rounding to the nearest second.
        local EXPECTED = { easy = 9, medium = 7, hard = 5, nightmare = 4 }
        for name, seconds in pairs(EXPECTED) do
            local api, ctl = harness.load()
            connect(2)
            gGlobalSyncTable.sh5_mode = api.boss_mode
            gGlobalSyncTable.sh5_difficulty = api[name]
            api.host_start(7)
            for i = 0, MAX_PLAYERS - 1 do gNetworkPlayers[i].currLevelNum = LEVEL_BOWSER_3 end
            ctl.objects[id_bhvBowser] = { oAction = 0 }
            gGlobalSyncTable.sh5_boss_modifier_1 = 2
            gGlobalSyncTable.sh5_boss_modifier_2 = 0
            gGlobalSyncTable.sh5_boss_modifier_3 = 0
            local due = gGlobalSyncTable.sh5_boss_attack_frame
            ctl.timer = due
            api.host_update()
            t.eq(gGlobalSyncTable.sh5_boss_attack_frame, due + seconds * 30,
                name .. ": wrong gap before the next attack")
        end
    end)

    s.test("rage shortens the gap, but never below four seconds", function()
        local api, ctl = bowser_fight()
        gGlobalSyncTable.sh5_boss_modifier_2 = 4      -- rage
        local due = gGlobalSyncTable.sh5_boss_attack_frame
        attack_at(api, ctl, 2)
        -- Seven seconds, times 0.8, floored, is five -- and five is above the
        -- four second floor, so five is what it stays.
        t.eq(gGlobalSyncTable.sh5_boss_attack_frame, due + 5 * 30,
            "rage did not shorten the gap correctly")
    end)

    s.test("the desperate phase shortens it further", function()
        local api, ctl = bowser_fight()
        gGlobalSyncTable.sh5_boss_modifier_2 = 12     -- the desperate modifier
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = 2          -- the last two wedges
        local due = gGlobalSyncTable.sh5_boss_attack_frame
        attack_at(api, ctl, 9)                        -- an eleven second attack
        -- Eleven times 0.65, floored, is seven.
        t.eq(gGlobalSyncTable.sh5_boss_attack_frame, due + 7 * 30,
            "the desperate phase did not shorten the gap correctly")
    end)

    s.test("Nightmare may drop the gap to two seconds, where Normal stops at three", function()
        -- Both floors are reached the same way: a six second attack, with rage
        -- and the desperate phase already down at the four second floor, then
        -- scaled by the difficulty factor.
        for _, case in ipairs({ { "nightmare", 2 }, { "hard", 3 } }) do
            local api, ctl = harness.load()
            connect(2)
            gGlobalSyncTable.sh5_mode = api.boss_mode
            gGlobalSyncTable.sh5_difficulty = api[case[1]]
            api.host_start(7)
            for i = 0, MAX_PLAYERS - 1 do gNetworkPlayers[i].currLevelNum = LEVEL_BOWSER_3 end
            ctl.objects[id_bhvBowser] = { oAction = 0 }
            gGlobalSyncTable.sh5_boss_modifier_1 = 3   -- six seconds
            gGlobalSyncTable.sh5_boss_modifier_2 = 4   -- rage
            gGlobalSyncTable.sh5_boss_modifier_3 = 12  -- desperate
            gGlobalSyncTable.sh5_boss_max_health = 5
            gGlobalSyncTable.sh5_boss_health = 2
            local due = gGlobalSyncTable.sh5_boss_attack_frame
            ctl.timer = due
            api.host_update()
            t.eq(gGlobalSyncTable.sh5_boss_attack_frame, due + case[2] * 30,
                case[1] .. ": wrong floor on the gap between attacks")
        end
    end)

    -- ---------------------------------------------------------------------
    -- The Chaos round loop
    -- ---------------------------------------------------------------------

    -- Chaos has no star objective, so its round loop does only three things:
    -- reroll everybody's modifiers, count who is still in, and end the round
    -- when the roster is locked and at most one player is left. It lives here
    -- rather than in chaos.lua because it calls the round's own host
    -- functions, and this file already requires chaos.lua.
    --
    -- A Chaos round with `n` players connected, all enrolled, all alive and the
    -- roster locked -- which is the state host_start_round leaves behind.
    local function chaos_round(n)
        local api, ctl = harness.load()
        connect(n)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        api.host_start(15)
        return api, ctl
    end

    -- host_start_round already seeds sh5_chaos_alive with the connected player
    -- count, so a test where nobody has dropped out agrees with the loop even
    -- when the loop never publishes anything. The tests that change the count
    -- are the ones that prove it is published.
    s.test("the loop counts every enrolled player who is still in", function()
        local api = chaos_round(3)
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_chaos_alive, 3, "wrong number of survivors")
        t.eq(gGlobalSyncTable.sh5_active, 1, "a round with three players left ended")
    end)

    s.test("the count reaches the very last player slot", function()
        -- A full lobby. Slot 15 is the one a loop that stops a slot early
        -- would drop, and slot 0 the one a loop starting at 1 would drop.
        local api = chaos_round(16)
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_chaos_alive, 16, "the loop missed a player slot")
    end)

    s.test("an eliminated player is not counted as a survivor", function()
        local api = chaos_round(3)
        gPlayerSyncTable[1].sh5_chaos_eliminated = 1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_chaos_alive, 2, "a dead player was still counted")
    end)

    s.test("a spectator is not counted as a survivor", function()
        local api = chaos_round(3)
        gPlayerSyncTable[1].sh5_enrolled = -1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_chaos_alive, 2, "an unenrolled player was counted")
    end)

    s.test("a disconnected slot is not counted as a survivor", function()
        local api = chaos_round(3)
        gNetworkPlayers[2].connected = false
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_chaos_alive, 2, "a player who left was still counted")
    end)

    s.test("the loop enrols a player who arrives mid-round, as a spectator", function()
        -- sh5_enrolled is deliberately left unset on the new slot: the loop
        -- reads it through `or 0`, and a test that writes 0 by hand would
        -- never exercise that default.
        local api, ctl = chaos_round(2)
        connect(3)
        api.host_update()
        t.eq(gPlayerSyncTable[2].sh5_enrolled, 1, "the latecomer was never enrolled")
        t.eq(gPlayerSyncTable[2].sh5_chaos_eliminated, 1,
            "a player who arrived after the lock was allowed to fight")
        t.eq(gGlobalSyncTable.sh5_chaos_alive, 2,
            "the new spectator was counted as a survivor")
        t.eq(chat_text(ctl), "P2 joined Chaos as a spectator.",
            "the latecomer did not go through the round's own late-joiner")
    end)

    s.test("the loop remembers players, so a reconnect is not a late arrival", function()
        -- The only visible trace of the loop's snapshot: a player it recorded
        -- gets their Chaos modifier and their alive status back on return,
        -- while an unrecorded one is treated as a post-lock latecomer and
        -- starts eliminated.
        local api = chaos_round(2)
        api.host_update()
        local modifier = gPlayerSyncTable[1].sh5_modifier
        gNetworkPlayers[1].connected = false
        gNetworkPlayers[1].connected = true
        gPlayerSyncTable[1].sh5_enrolled = 0
        gPlayerSyncTable[1].sh5_modifier = 0
        api.host_update()
        t.eq(gPlayerSyncTable[1].sh5_chaos_eliminated, 0,
            "a returning player was treated as somebody who arrived after the lock")
        t.eq(gPlayerSyncTable[1].sh5_modifier, modifier,
            "the returning player's Chaos modifier was not restored")
    end)

    s.test("the loop rerolls the Chaos modifiers", function()
        -- 15 seconds at 30 frames per second, pinned from CHANGELOG.md.
        local api, ctl = chaos_round(2)
        local due = gGlobalSyncTable.sh5_chaos_next_reroll
        local seq = gGlobalSyncTable.sh5_chaos_modifier_seq or 0
        ctl.timer = due
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_chaos_modifier_seq, seq + 1,
            "the loop never asked for a reroll")
        t.eq(gGlobalSyncTable.sh5_chaos_next_reroll, due + 450,
            "the next reroll was not scheduled 15 seconds out")
    end)

    s.test("the last player standing wins the round", function()
        local api = chaos_round(3)
        gPlayerSyncTable[0].sh5_chaos_eliminated = 1
        gPlayerSyncTable[2].sh5_chaos_eliminated = 1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 0, "the round outlived its last two players")
        t.eq(gGlobalSyncTable.sh5_result_reason, "chaos last standing",
            "the round ended for the wrong reason")
        t.eq(gGlobalSyncTable.sh5_chaos_winner, "P1", "the wrong survivor was named")
        t.eq(gGlobalSyncTable.sh5_result_winner, "P1", "the survivor did not win")
    end)

    s.test("two survivors keep the round running", function()
        local api = chaos_round(3)
        gPlayerSyncTable[0].sh5_chaos_eliminated = 1
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 1, "the round ended with two players still in")
        t.eq(gGlobalSyncTable.sh5_chaos_alive, 2, "wrong number of survivors")
    end)

    s.test("with everybody eliminated the round ends with no winner", function()
        local api = chaos_round(2)
        for i = 0, 1 do gPlayerSyncTable[i].sh5_chaos_eliminated = 1 end
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 0, "an empty Chaos round kept running")
        t.eq(gGlobalSyncTable.sh5_chaos_winner, "Nobody", "an eliminated player won")
        t.eq(gGlobalSyncTable.sh5_result_winner, "Nobody", "an empty round had a winner")
    end)

    s.test("an unlocked roster never ends the round", function()
        -- The lock is what says the roster is final. Before it, an empty
        -- lobby is a round that has not started filling up, not a finished one.
        local api = chaos_round(2)
        gGlobalSyncTable.sh5_chaos_roster_locked = 0
        for i = 0, 1 do gPlayerSyncTable[i].sh5_chaos_eliminated = 1 end
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_active, 1, "the round ended before the roster was locked")
        t.eq(gGlobalSyncTable.sh5_result_reason or "", "",
            "an unlocked round reported a result")
    end)

    s.test("a survivor whose name has not arrived yet is still named", function()
        local api = chaos_round(2)
        gPlayerSyncTable[0].sh5_chaos_eliminated = 1
        gNetworkPlayers[1].name = nil
        api.host_update()
        t.eq(gGlobalSyncTable.sh5_chaos_winner, "Player",
            "a nameless survivor won as somebody else")
    end)

    -- ---------------------------------------------------------------------
    -- Which goal a player is given
    -- ---------------------------------------------------------------------

    s.test("the pool skips stars that are already in the save file", function()
        local api, ctl = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        only_goals(api, ctl, { 4, 9 })         -- everything else is collected
        api.host_start(15)
        local handed = { gPlayerSyncTable[0].sh5_goal, gPlayerSyncTable[1].sh5_goal }
        table.sort(handed)
        t.eq(handed[1], 4, "a collected star was handed out")
        t.eq(handed[2], 9, "a collected star was handed out")
    end)

    s.test("two players are never hunting the same star", function()
        local api = harness.load()
        connect(8)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        local seen = {}
        for i = 0, 7 do
            local goal = gPlayerSyncTable[i].sh5_goal
            t.ok(not seen[goal], "goal " .. tostring(goal) .. " was handed out twice")
            seen[goal] = true
        end
    end)

    s.test("only Nightmare hands out a second modifier", function()
        for _, name in ipairs({ "easy", "medium", "hard" }) do
            local api = harness.load()
            connect(2)
            gGlobalSyncTable.sh5_mode = api.normal_mode
            gGlobalSyncTable.sh5_difficulty = api[name]
            api.host_start(15)
            t.eq(gPlayerSyncTable[0].sh5_modifier_2, 0,
                name .. " handed out a second modifier")
        end
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        gGlobalSyncTable.sh5_difficulty = api.nightmare
        api.host_start(15)
        local second = gPlayerSyncTable[0].sh5_modifier_2
        t.eq(type(second), "number", "Nightmare's second modifier is not an index")
        t.ne(second, 0, "Nightmare handed out no second modifier")
        t.ne(second, gPlayerSyncTable[0].sh5_modifier,
            "Nightmare handed out the same modifier twice")
    end)

    s.test("only a jump limit sets a jump count", function()
        local api = harness.load()
        connect(8)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        for i = 0, 7 do
            local sync = gPlayerSyncTable[i]
            local goal = api.get_goal(sync.sh5_goal)
            local kind = goal.mods[sync.sh5_modifier].kind
            if kind ~= "jump_limit" then
                t.eq(sync.sh5_jump_count, -1,
                    "player " .. i .. " got a jump count from a " .. kind .. " modifier")
            else
                t.ok(sync.sh5_jump_count >= 0,
                    "player " .. i .. " has a jump limit but no jump count")
            end
        end
    end)

    -- ---------------------------------------------------------------------
    -- Teams, Chaos and Bowser at the moment a round starts
    -- ---------------------------------------------------------------------

    s.test("teams are handed out in Team mode and nowhere else", function()
        local api = harness.load()
        connect(4)
        gGlobalSyncTable.sh5_mode = api.team_mode
        api.host_start(15)
        for i = 0, 3 do
            local team = gPlayerSyncTable[i].sh5_team
            t.ok(team == api.team_red or team == api.team_blue,
                "player " .. i .. " is on neither team: " .. tostring(team))
        end

        local api2 = harness.load()
        connect(4)
        gGlobalSyncTable.sh5_mode = api2.normal_mode
        api2.host_start(15)
        for i = 0, 3 do
            t.eq(gPlayerSyncTable[i].sh5_team, 0, "a star race handed out a team")
        end
    end)

    s.test("a fresh round scores nobody on its first frame", function()
        -- The host's "already seen" marks start level with every player, so the
        -- first pass of the loop must find nothing to score or reroll.
        local api = harness.load()
        connect(3)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        local goals = {}
        for i = 0, 2 do goals[i] = gPlayerSyncTable[i].sh5_goal end
        api.host_update()
        for i = 0, 2 do
            t.eq(gPlayerSyncTable[i].sh5_score, 0, "player " .. i .. " scored for nothing")
            t.eq(gPlayerSyncTable[i].sh5_goal, goals[i], "player " .. i .. " lost their goal")
        end
    end)

    s.test("Chaos locks its roster, and latecomers start eliminated", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        api.host_start(15)
        t.eq(gGlobalSyncTable.sh5_chaos_roster_locked, 1, "the roster was not locked")
        for i = 0, 1 do
            t.eq(gPlayerSyncTable[i].sh5_chaos_eliminated, 0,
                "player " .. i .. " started the round already out")
        end

        connect(3)
        gPlayerSyncTable[2].sh5_enrolled = 0
        api.host_late_joiner(2)
        t.eq(gPlayerSyncTable[2].sh5_chaos_eliminated, 1,
            "a player who arrived after the lock was allowed to fight")
    end)

    s.test("Chaos draws from the whole catalogue, and only a jump limit sets a jump count", function()
        -- host_prepare_player asks for a pair with nothing excluded, passing 0
        -- because no index is 0. Passing a real index instead would quietly make
        -- that one modifier unreachable at the start of a round while leaving it
        -- reachable on a reroll -- so this draws a full lobby across many seeds
        -- and checks the first entry turns up. Thirty-one modifiers are allowed
        -- in Chaos, so 240 draws make missing one by luck about one run in 2500.
        -- The same sweep also checks the jump count, which is read off the
        -- pair: a jump limit in either slot sets it, and nothing else may.
        local seen, draws, jump_limited = {}, 0, 0
        for seed = 0, 29 do
            local api, ctl = harness.load()
            connect(8)
            ctl.timer = seed * 19
            gGlobalSyncTable.sh5_mode = api.chaos_mode
            api.host_start(15)
            for i = 0, 7 do
                local sync = gPlayerSyncTable[i]
                seen[sync.sh5_modifier] = true
                draws = draws + 1

                local first = api.normal_modifier_catalog[sync.sh5_modifier]
                local second = api.normal_modifier_catalog[sync.sh5_modifier_2 or 0]
                local limited = (first ~= nil and first.kind == "jump_limit")
                    or (second ~= nil and second.kind == "jump_limit")
                if limited then
                    jump_limited = jump_limited + 1
                    t.ok(sync.sh5_jump_count >= 0,
                        "seed " .. seed .. ": a jump limit set no jump count")
                else
                    t.eq(sync.sh5_jump_count, -1,
                        "seed " .. seed .. ": a jump count appeared without a jump limit")
                end
            end
        end
        t.eq(draws, 240, "the sample was smaller than the test assumes")
        t.ok(seen[1], "the first modifier in the catalogue was never drawn")
        t.ok(jump_limited > 0,
            "no player ever drew a jump limit, so the jump count was never tested")
    end)

    s.test("Chaos gives every player a modifier pair", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        api.host_start(15)
        for i = 0, 1 do
            t.ne(gPlayerSyncTable[i].sh5_modifier, 0,
                "player " .. i .. " got no Chaos modifier")
        end
    end)

    s.test("a star race clears Bowser's modifiers", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        for _, field in ipairs({ "sh5_boss_modifier_1", "sh5_boss_modifier_2",
                                 "sh5_boss_modifier_3" }) do
            t.eq(gGlobalSyncTable[field], 0, field .. " survived into a star race")
        end
    end)

    s.test("Bowser draws three different modifiers", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        api.host_start(7)
        local drawn = {}
        for _, field in ipairs({ "sh5_boss_modifier_1", "sh5_boss_modifier_2",
                                 "sh5_boss_modifier_3" }) do
            local value = gGlobalSyncTable[field]
            t.ne(value, 0, field .. " was left empty")
            t.ok(not drawn[value], "Bowser drew modifier " .. tostring(value) .. " twice")
            drawn[value] = true
        end
    end)

    s.test("every Bowser fight has at least one attack in it", function()
        -- The draw is random, so this walks a range of seeds. Three passive
        -- modifiers would leave Bowser unable to do anything at all, which is
        -- why the last slot is replaced when that happens.
        for seed = 0, 25 do
            local api, ctl = harness.load()
            connect(2)
            ctl.timer = seed * 37
            gGlobalSyncTable.sh5_mode = api.boss_mode
            api.host_start(7)
            local has_attack, drawn = false, {}
            for _, field in ipairs({ "sh5_boss_modifier_1", "sh5_boss_modifier_2",
                                     "sh5_boss_modifier_3" }) do
                local value = gGlobalSyncTable[field]
                if api.boss_active_attack_lookup[value] then has_attack = true end
                -- Forcing an attack into the last slot must not duplicate one of
                -- the other two, which is the failure mode if it is forced in
                -- when an attack had already been drawn.
                t.ok(not drawn[value],
                    "seed " .. seed .. ": Bowser drew modifier " .. tostring(value) .. " twice")
                drawn[value] = true
            end
            t.ok(has_attack, "seed " .. seed .. ": Bowser drew nothing he could attack with")
        end
    end)

    s.test("every one of Bowser's modifiers can be drawn", function()
        -- The draw walks the whole catalogue, so over enough seeds both ends of
        -- it have to turn up. Missing the first entry is the classic way to get
        -- a loop bound wrong.
        local seen = {}
        local count = 0
        for seed = 0, 25 do
            local api, ctl = harness.load()
            connect(2)
            ctl.timer = seed * 37
            gGlobalSyncTable.sh5_mode = api.boss_mode
            api.host_start(7)
            count = #api.boss_modifiers
            for _, field in ipairs({ "sh5_boss_modifier_1", "sh5_boss_modifier_2",
                                     "sh5_boss_modifier_3" }) do
                seen[gGlobalSyncTable[field]] = true
            end
        end
        t.ok(seen[1], "modifier 1 was never drawn, so the draw skips its first entry")
        t.ok(seen[count], "modifier " .. count .. " was never drawn, so the draw stops short")
    end)

    s.test("every player Boss modifier can be drawn as the second one", function()
        local seen = {}
        local count = 0
        for seed = 0, 25 do
            local api, ctl = harness.load()
            connect(2)
            ctl.timer = seed * 29
            gGlobalSyncTable.sh5_mode = api.boss_mode
            gGlobalSyncTable.sh5_difficulty = api.nightmare
            api.host_start(7)
            count = #api.boss_player_modifiers
            seen[gGlobalSyncTable.sh5_boss_player_modifier_2] = true
        end
        t.ok(seen[1], "the first player modifier was never the second draw")
        t.ok(seen[count], "the last player modifier was never the second draw")
    end)

    s.test("only Nightmare gives the players a second Boss modifier", function()
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        gGlobalSyncTable.sh5_difficulty = api.medium
        api.host_start(7)
        t.eq(gGlobalSyncTable.sh5_boss_player_modifier_2, 0,
            "Normal handed out a second Boss modifier")

        for seed = 0, 15 do
            local api2, ctl = harness.load()
            connect(2)
            ctl.timer = seed * 53
            gGlobalSyncTable.sh5_mode = api2.boss_mode
            gGlobalSyncTable.sh5_difficulty = api2.nightmare
            api2.host_start(7)
            local first = gGlobalSyncTable.sh5_boss_player_modifier
            local second = gGlobalSyncTable.sh5_boss_player_modifier_2
            t.eq(type(second), "number", "seed " .. seed .. ": the second slot is not an index")
            t.ne(second, 0, "seed " .. seed .. ": Nightmare left the second slot empty")
            t.ne(second, first, "seed " .. seed .. ": the same modifier was drawn twice")
        end
    end)

    s.test("a new fight starts with an empty attack queue", function()
        local api, ctl = bowser_fight()
        gGlobalSyncTable.sh5_boss_modifier_1 = 2
        ctl.timer = gGlobalSyncTable.sh5_boss_attack_frame
        api.host_update()
        t.ne(gGlobalSyncTable.sh5_boss_attack_queue_1, 0, "no attack was queued to clear")

        api.host_end("stopped")
        api.host_start(7)
        for slot = 1, api.boss_attack_queue_size do
            t.eq(gGlobalSyncTable["sh5_boss_attack_queue_" .. slot], 0,
                "queue slot " .. slot .. " carried over from the previous fight")
        end
        t.eq(gGlobalSyncTable.sh5_boss_attack_seq, 0, "the attack counter carried over")
    end)

    s.test("a forfeited challenge is never handed straight back", function()
        -- host_assign_goal filters a goal's allowed modifiers down to the ones
        -- that are not the kind just forfeited, and falls back to the unfiltered
        -- list if that leaves nothing. The fallback never runs in practice:
        -- every goal in the catalogue has at least ten allowed modifiers, so
        -- removing one kind cannot empty the list. Drawing many times is
        -- therefore the only way to see the filter working at all.
        local api = harness.load()
        connect(2)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.host_start(15)
        local draws = 0
        for n = 1, 80 do
            local sync = gPlayerSyncTable[0]
            local old_goal = api.get_goal(sync.sh5_goal or 0)
            if old_goal == nil then break end
            local old_kind = old_goal.mods[sync.sh5_modifier].kind
            sync.sh5_forfeit = n
            api.host_update()
            if gGlobalSyncTable.sh5_active ~= 1 then break end
            local new_goal = api.get_goal(sync.sh5_goal or 0)
            if new_goal == nil then break end
            t.ne(new_goal.mods[sync.sh5_modifier].kind, old_kind,
                "draw " .. n .. ": the forfeited challenge came straight back")
            draws = draws + 1
        end
        t.ok(draws >= 40, "only " .. draws .. " draws were taken; the test proves little")
    end)
end
