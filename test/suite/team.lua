-- Team mode: balanced rosters and team palettes.
--
-- Extracting modules/team.lua found this whole area uncovered -- nine mutations
-- against it, including never restoring a palette, painting outside Team mode
-- and putting every player on one team, all left the suite green. These are
-- the guards.

return function(t, harness)
    local s = t.suite("team")

    local function counts(rosters, api)
        local red, blue, none = 0, 0, 0
        for i = 0, 15 do
            if gNetworkPlayers[i].connected then
                local team = rosters[i]
                if team == api.team_red then red = red + 1
                elseif team == api.team_blue then blue = blue + 1
                else none = none + 1 end
            end
        end
        return red, blue, none
    end

    -- rosters -----------------------------------------------------------------

    s.test("every connected player is put on a team, and nobody else is", function()
        local api, ctl = harness.load()
        ctl.player_count = 6
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 6 end
        api.build_balanced()
        local rosters = api.team_rosters()
        local red, blue, none = counts(rosters, api)
        t.eq(none, 0, "a connected player was left without a team")
        t.eq(red + blue, 6, "wrong number of players placed")
        for i = 6, 15 do
            t.eq(rosters[i], nil, "disconnected player " .. i .. " was given a team")
        end
    end)

    s.test("the two rosters never differ by more than one player", function()
        -- Checked across both parities and several draws, because build_balanced
        -- breaks ties at random and an odd lobby gives one team the extra slot.
        local api, ctl = harness.load()
        for _, population in ipairs({ 2, 3, 4, 5, 7, 8, 15 }) do
            ctl.player_count = population
            for i = 0, 15 do gNetworkPlayers[i].connected = i < population end
            for attempt = 1, 20 do
                math.randomseed(population * 100 + attempt)
                api.build_balanced()
                local red, blue = counts(api.team_rosters(), api)
                t.ok(math.abs(red - blue) <= 1, population .. " players split "
                    .. red .. "/" .. blue .. " on attempt " .. attempt)
            end
        end
    end)

    s.test("experience is balanced between the teams, not stacked on one", function()
        -- Four veterans and four newcomers must come out two and two. Stacking
        -- the veterans is the failure this balancing exists to prevent.
        local api, ctl = harness.load()
        ctl.player_count = 8
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 8 end
        -- Descending, all distinct. Four veterans and four newcomers would not
        -- prove anything: filling the smaller roster first already alternates
        -- them two and two without consulting skill at all. This spread can
        -- only come out level if the skill totals are actually compared.
        local SKILL = { [0] = 8, 7, 6, 5, 4, 3, 2, 1 }
        for i = 0, 7 do gPlayerSyncTable[i].sh5_lifetime_stars = SKILL[i] end

        for attempt = 1, 25 do
            math.randomseed(attempt)
            api.build_balanced()
            local rosters = api.team_rosters()
            local red_skill, blue_skill = 0, 0
            for i = 0, 7 do
                local skill = SKILL[i]
                if rosters[i] == api.team_red then red_skill = red_skill + skill
                else blue_skill = blue_skill + skill end
            end
            t.eq(red_skill, blue_skill, "attempt " .. attempt
                .. " did not balance experience: " .. red_skill .. " vs " .. blue_skill)
        end
    end)

    s.test("an odd lobby gives the spare player to either team, not always one", function()
        -- With five players both rosters cap at two, and the code adds the
        -- spare slot to a randomly chosen side. Drop that coin toss and the
        -- fifth player always lands on the same team -- still a legal 2/3
        -- split, so a size check cannot see it, but no longer fair.
        local api, ctl = harness.load()
        ctl.player_count = 5
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 5 end

        local red_got_three, blue_got_three = false, false
        for attempt = 1, 40 do
            math.randomseed(attempt)
            api.build_balanced()
            local red, blue = counts(api.team_rosters(), api)
            if red == 3 then red_got_three = true end
            if blue == 3 then blue_got_three = true end
        end
        t.ok(red_got_three, "across 40 draws the spare player never went to RED")
        t.ok(blue_got_three, "across 40 draws the spare player never went to BLUE")
    end)

    -- who may damage whom ----------------------------------------------------

    --- Put players 0 and 1 on the same star, in the same place, in `mode`.
    local function together(api, ctl, mode)
        ctl.player_count = 2
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 2 end
        for i = 0, 1 do
            gPlayerSyncTable[i].sh5_goal = 1
            gNetworkPlayers[i].currLevelNum = api.goals[1].level
            gNetworkPlayers[i].currAreaIndex = 1
            gNetworkPlayers[i].currActNum = api.goals[1].act
            gPlayerSyncTable[i].sh5_chaos_eliminated = 0
        end
        ctl.begin_round(api, mode, api.medium)
    end

    s.test("Boss mode allows no PvP at all", function()
        -- Every player is fighting Bowser, not each other.
        local api, ctl = harness.load()
        together(api, ctl, api.boss_mode)
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), false,
            "players could attack each other during a Boss round")
    end)

    s.test("Normal mode allows PvP only where the two players actually meet", function()
        local api, ctl = harness.load()
        together(api, ctl, api.normal_mode)
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), true,
            "two players standing together could not attack each other")

        gNetworkPlayers[1].currAreaIndex = 2
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), false,
            "a player was attacked from another area")
    end)

    s.test("Team mode allows attacks across the colours and blocks friendly fire", function()
        local api, ctl = harness.load()
        together(api, ctl, api.team_mode)

        gPlayerSyncTable[0].sh5_team = api.team_red
        gPlayerSyncTable[1].sh5_team = api.team_blue
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), true,
            "red could not attack blue")

        gPlayerSyncTable[1].sh5_team = api.team_red
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), false,
            "friendly fire was allowed between two red players")

        gPlayerSyncTable[1].sh5_team = 0            -- Team.NONE, never enrolled
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), false,
            "a player on no team was attackable")
    end)

    s.test("Chaos leaves eliminated players out of the fight", function()
        -- An eliminated player is a spectator. Attacking them, or being
        -- attacked by them, would keep them in a round they have already lost.
        local api, ctl = harness.load()
        together(api, ctl, api.chaos_mode)
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), true,
            "two surviving players could not fight")

        gPlayerSyncTable[1].sh5_chaos_eliminated = 1
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), false,
            "an eliminated player was still attackable")

        gPlayerSyncTable[1].sh5_chaos_eliminated = 0
        gPlayerSyncTable[0].sh5_chaos_eliminated = 1
        t.eq(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1]), false,
            "an eliminated player could still attack")
    end)

    -- palettes ----------------------------------------------------------------

    local function paint_a_round(api, ctl)
        ctl.player_count = 4
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 4 end
        gPlayerSyncTable[0].sh5_team = api.team_red
        gPlayerSyncTable[1].sh5_team = api.team_red
        gPlayerSyncTable[2].sh5_team = api.team_blue
        gPlayerSyncTable[3].sh5_team = api.team_blue
        ctl.begin_round(api, api.team_mode, api.medium)
        api.update_palettes()
    end

    s.test("each player is painted their own team's colour", function()
        local api, ctl = harness.load()
        local before = {}
        for i = 0, 3 do before[i] = ctl.palettes[i][PANTS] end
        paint_a_round(api, ctl)

        for i = 0, 3 do
            local want = api.team_colors[gPlayerSyncTable[i].sh5_team]
            for part = PANTS, EMBLEM do
                local got = ctl.palettes[i][part]
                t.eq(got.r, want.r, "player " .. i .. " part " .. part .. " red channel")
                t.eq(got.g, want.g, "player " .. i .. " part " .. part .. " green channel")
                t.eq(got.b, want.b, "player " .. i .. " part " .. part .. " blue channel")
            end
            t.ne(ctl.palettes[i][PANTS].r, before[i].r, "player " .. i .. " was never painted")
        end
        -- and the two teams are not painted the same colour
        t.ok(api.team_colors[api.team_red].r ~= api.team_colors[api.team_blue].r
            or api.team_colors[api.team_red].b ~= api.team_colors[api.team_blue].b,
            "both teams share a colour")
    end)

    s.test("red is the red one and blue is the blue one", function()
        -- Swapping the two entries of Team.colors is invisible to every check
        -- that only asks whether a player was painted.
        local api = harness.load()
        local red, blue = api.team_colors[api.team_red], api.team_colors[api.team_blue]
        t.ok(red.r > red.b, "the RED colour is not predominantly red: "
            .. red.r .. "," .. red.g .. "," .. red.b)
        t.ok(blue.b > blue.r, "the BLUE colour is not predominantly blue: "
            .. blue.r .. "," .. blue.g .. "," .. blue.b)
    end)

    s.test("the round gives every player their own palette back", function()
        local api, ctl = harness.load()
        local before = {}
        for i = 0, 3 do
            before[i] = {}
            for part = PANTS, EMBLEM do
                local c = ctl.palettes[i][part]
                before[i][part] = { r = c.r, g = c.g, b = c.b }
            end
        end
        paint_a_round(api, ctl)
        -- Palettes refresh throughout the round, every 15 frames. Each refresh
        -- re-reads the player's CURRENT colours, which are by then the team's,
        -- so a capture that does not recognise its own snapshot overwrites the
        -- original with the team colour and the player never gets it back.
        for _ = 1, 5 do
            ctl.timer = ctl.timer + 20
            api.update_palettes()
        end
        api.restore_palettes()

        for i = 0, 3 do
            for part = PANTS, EMBLEM do
                local got, want = ctl.palettes[i][part], before[i][part]
                t.eq(got.r, want.r, "player " .. i .. " part " .. part .. " red channel")
                t.eq(got.g, want.g, "player " .. i .. " part " .. part .. " green channel")
                t.eq(got.b, want.b, "player " .. i .. " part " .. part .. " blue channel")
            end
        end
    end)

    s.test("nothing is painted outside a Team-mode round", function()
        local api, ctl = harness.load()
        local before = ctl.palettes[0][PANTS].r
        ctl.player_count = 4
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 4 end
        gPlayerSyncTable[0].sh5_team = api.team_red

        api.update_palettes()                                  -- no round at all
        t.eq(ctl.palettes[0][PANTS].r, before, "painted with no round running")

        ctl.begin_round(api, api.normal_mode, api.medium)      -- a round, wrong mode
        api.update_palettes()
        t.eq(ctl.palettes[0][PANTS].r, before, "painted outside Team mode")
    end)

    s.test("a model swap mid-round discards the stale snapshot", function()
        -- Character Select can change a player's model while TEAM is painting.
        -- The snapshot belongs to the old model, and repainting it onto the new
        -- one would hand the player someone else's colours.
        local api, ctl = harness.load()
        paint_a_round(api, ctl)
        local painted = ctl.palettes[0][PANTS].r

        gNetworkPlayers[0].modelIndex = 7          -- a different character
        api.restore_palettes()
        t.eq(ctl.palettes[0][PANTS].r, painted,
            "a snapshot from the old model was repainted onto the new one")
    end)

    s.test("palette snapshots are kept per player, not shared", function()
        local api = harness.load()
        local a = api.palette_key(gNetworkPlayers[1], 1)
        local b = api.palette_key(gNetworkPlayers[2], 2)
        t.ne(a, b, "two players share one palette key, so one would be restored "
            .. "with the other's colours")
    end)

    -- roster totals and late assignment -----------------------------------------
    --
    -- participant_stats is the one place that answers "who is on each team, how
    -- strong are they, and what have they scored". pick_late and update_scores
    -- both read it and nothing else does, so these three are tested together.
    --
    -- One branch of participant_stats is deliberately not guarded below, because
    -- no reachable state produces it: the `record.enrolled == 1` test over the
    -- host's records. Records are written in exactly one place, which always
    -- writes `enrolled = 1`; nothing ever lowers it, and a record is removed
    -- rather than cleared. So the field is always 1 when the record exists.

    -- Connect exactly `n` player slots, starting at slot 0.
    local function connect(n)
        for i = 0, 15 do gNetworkPlayers[i].connected = i < n end
    end

    -- Put player `i` on `team`, enrolled, with the given experience and score.
    local function enroll(i, team, stars, score)
        local sync = gPlayerSyncTable[i]
        sync.sh5_enrolled = 1
        sync.sh5_team = team
        sync.sh5_lifetime_stars = stars
        sync.sh5_score = score
    end

    s.test("a roster slot is filled by a connected, enrolled player and nobody else", function()
        local api = harness.load()
        connect(4)
        enroll(0, api.team_red, 0, 0)
        enroll(1, api.team_blue, 0, 0)
        -- connected but never enrolled: watching, not playing
        gPlayerSyncTable[2].sh5_team = api.team_red
        -- enrolled on paper but not connected: their slot is free again
        enroll(5, api.team_blue, 0, 0)
        local stats = api.team_participant_stats()
        t.eq(stats[api.team_red].count, 1, "red roster counted the wrong players")
        t.eq(stats[api.team_blue].count, 1, "blue roster counted the wrong players")
    end)

    s.test("a player with no team is left out of both totals", function()
        local api = harness.load()
        connect(2)
        enroll(0, api.team_red, 3, 4)
        enroll(1, 0, 7, 9)                 -- Team.NONE
        local stats = api.team_participant_stats()
        t.eq(stats[api.team_red].count, 1, "red counted somebody without a team")
        t.eq(stats[api.team_blue].count, 0, "blue counted somebody without a team")
        t.eq(stats[api.team_red].score, 4, "red total is wrong")
        t.eq(stats[api.team_blue].score, 0, "an unassigned player's score was banked")
    end)

    s.test("experience and score are totalled per team", function()
        local api = harness.load()
        connect(4)
        enroll(0, api.team_red, 3, 2)
        enroll(1, api.team_red, 4, 5)
        enroll(2, api.team_blue, 10, 1)
        enroll(3, api.team_blue, 0, 0)
        local stats = api.team_participant_stats()
        t.eq(stats[api.team_red].count, 2, "red roster size is wrong")
        t.eq(stats[api.team_blue].count, 2, "blue roster size is wrong")
        t.eq(stats[api.team_red].skill, 7, "red experience is wrong")
        t.eq(stats[api.team_blue].skill, 10, "blue experience is wrong")
        t.eq(stats[api.team_red].score, 7, "red score is wrong")
        t.eq(stats[api.team_blue].score, 1, "blue score is wrong")
    end)

    s.test("a negative experience or score counts as zero, never against the team", function()
        -- Both fields arrive over the network, so a negative one is possible
        -- and must not be able to drag a team's total below what it earned.
        local api = harness.load()
        connect(2)
        enroll(0, api.team_red, 6, 6)
        enroll(1, api.team_red, -10, -10)
        local stats = api.team_participant_stats()
        t.eq(stats[api.team_red].skill, 6, "a negative star count was subtracted")
        t.eq(stats[api.team_red].score, 6, "a negative score was subtracted")
    end)

    s.test("a connected player's points are counted once, not once per record", function()
        -- The host keeps a record of everyone it has seen, and totals the
        -- records of players who have since left. Someone still connected must
        -- not be counted from both places.
        local api, ctl = harness.load()
        ctl.is_server = true
        connect(2)
        gGlobalSyncTable.sh5_mode = api.team_mode
        api.host_start(15)
        gPlayerSyncTable[0].sh5_team = api.team_red
        gPlayerSyncTable[1].sh5_team = api.team_blue
        gPlayerSyncTable[0].sh5_score = 5
        gPlayerSyncTable[1].sh5_score = 3
        api.remember_player(0)
        api.remember_player(1)
        local stats = api.team_participant_stats()
        t.eq(stats[api.team_red].score, 5, "red's points were counted twice")
        t.eq(stats[api.team_blue].score, 3, "blue's points were counted twice")
        t.eq(stats[api.team_red].count, 1, "red's roster counted one player twice")
    end)

    s.test("a player who disconnects keeps their points but frees their slot", function()
        local api, ctl = harness.load()
        ctl.is_server = true
        connect(2)
        gGlobalSyncTable.sh5_mode = api.team_mode
        api.host_start(15)
        gPlayerSyncTable[0].sh5_team = api.team_red
        gPlayerSyncTable[1].sh5_team = api.team_blue
        gPlayerSyncTable[0].sh5_score = 5
        gPlayerSyncTable[1].sh5_score = 4
        api.remember_player(0)
        api.remember_player(1)
        gNetworkPlayers[1].connected = false
        local stats = api.team_participant_stats()
        t.eq(stats[api.team_blue].score, 4, "a disconnected player's points were lost")
        t.eq(stats[api.team_blue].count, 0,
            "a disconnected player still holds a roster slot")
        t.eq(stats[api.team_red].score, 5, "the connected player's points changed")
    end)

    -- pick_late ------------------------------------------------------------------
    --
    -- The rules, strongest first: fill the smaller roster; else help a team
    -- trailing by at least two points; else keep a reconnect on their old team;
    -- else give the weaker team the player. Each test below sets every rule
    -- weaker than the one it is checking so the answer is forced, never random.

    s.test("a new player fills the smaller roster before anything else", function()
        local api = harness.load()
        connect(3)
        enroll(0, api.team_red, 0, 0)
        enroll(1, api.team_red, 0, 0)
        enroll(2, api.team_blue, 0, 0)
        t.eq(api.team_pick_late(api.team_red), api.team_blue,
            "two red and one blue should have taken the blue slot")
        gPlayerSyncTable[0].sh5_team = api.team_blue
        gPlayerSyncTable[1].sh5_team = api.team_blue
        gPlayerSyncTable[2].sh5_team = api.team_red
        t.eq(api.team_pick_late(api.team_blue), api.team_red,
            "two blue and one red should have taken the red slot")
    end)

    s.test("with equal rosters, a team trailing by two points gets the player", function()
        local api = harness.load()
        connect(2)
        -- Skill is set so that if the score rule did NOT fire, the weaker-team
        -- rule would answer the other way. The test then proves the score rule
        -- is what decided.
        enroll(0, api.team_red, 0, 5)
        enroll(1, api.team_blue, 5, 3)
        t.eq(api.team_pick_late(), api.team_blue, "blue trails by two and was passed over")
        gPlayerSyncTable[0].sh5_score = 3
        gPlayerSyncTable[1].sh5_score = 5
        gPlayerSyncTable[0].sh5_lifetime_stars = 5
        gPlayerSyncTable[1].sh5_lifetime_stars = 0
        t.eq(api.team_pick_late(), api.team_red, "red trails by two and was passed over")
    end)

    s.test("a one-point gap is too small to move anybody", function()
        -- Two points, not one. A one-point lead changes hands on every star, and
        -- reassigning players that often is worse than a slightly uneven score.
        local api = harness.load()
        connect(2)
        enroll(0, api.team_red, 0, 4)
        enroll(1, api.team_blue, 0, 3)
        t.eq(api.team_pick_late(api.team_red), api.team_red,
            "a one-point gap overrode the returning player's own team")
    end)

    s.test("a reconnecting player goes back to the team they were on", function()
        local api = harness.load()
        connect(2)
        -- Equal counts and equal scores, and the weaker team is red, so a
        -- failure to honour the preference would answer red.
        enroll(0, api.team_red, 0, 4)
        enroll(1, api.team_blue, 5, 4)
        t.eq(api.team_pick_late(api.team_blue), api.team_blue,
            "a reconnecting blue player was moved to red")
    end)

    s.test("with nothing else to separate them, the weaker team gets the player", function()
        local api = harness.load()
        connect(2)
        enroll(0, api.team_red, 0, 4)
        enroll(1, api.team_blue, 5, 4)
        t.eq(api.team_pick_late(), api.team_red, "red is weaker and was passed over")
        gPlayerSyncTable[0].sh5_lifetime_stars = 5
        gPlayerSyncTable[1].sh5_lifetime_stars = 0
        t.eq(api.team_pick_late(), api.team_blue, "blue is weaker and was passed over")
    end)

    -- update_scores --------------------------------------------------------------

    s.test("the host publishes each team's total to everyone", function()
        local api, ctl = harness.load()
        ctl.is_server = true
        connect(3)
        gGlobalSyncTable.sh5_mode = api.team_mode
        enroll(0, api.team_red, 0, 5)
        enroll(1, api.team_red, 0, 2)
        enroll(2, api.team_blue, 0, 4)
        api.team_update_scores()
        t.eq(gGlobalSyncTable.sh5_red_score, 7, "the published red total is wrong")
        t.eq(gGlobalSyncTable.sh5_blue_score, 4, "the published blue total is wrong")
    end)

    s.test("a client never publishes a score, and no mode but Team does", function()
        for _, case in ipairs({ { false, "team" }, { true, "normal" } }) do
            local api, ctl = harness.load()
            ctl.is_server = case[1]
            connect(2)
            gGlobalSyncTable.sh5_mode = case[2] == "team" and api.team_mode or api.normal_mode
            enroll(0, api.team_red, 0, 5)
            enroll(1, api.team_blue, 0, 4)
            gGlobalSyncTable.sh5_red_score = 99
            gGlobalSyncTable.sh5_blue_score = 99
            api.team_update_scores()
            t.eq(gGlobalSyncTable.sh5_red_score, 99,
                case[2] .. " as server=" .. tostring(case[1]) .. " wrote a red total")
            t.eq(gGlobalSyncTable.sh5_blue_score, 99,
                case[2] .. " as server=" .. tostring(case[1]) .. " wrote a blue total")
        end
    end)

    -- the reroll button's label --------------------------------------------------

    s.test("the reroll button is renamed once, and not again until the label changes", function()
        local api, ctl = harness.load()
        api.set_language(0)
        t.eq(#ctl.menu_renames, 0, "the button was renamed before anything asked")
        api.update_manual_reroll_menu()
        t.eq(#ctl.menu_renames, 1, "the button was not renamed")
        t.eq(ctl.menu_buttons[1].label, "ANOTHER LEVEL - NORMAL/TEAM ONLY",
            "the button carries the wrong label outside a round")
        api.update_manual_reroll_menu()
        api.update_manual_reroll_menu()
        t.eq(#ctl.menu_renames, 1,
            "an unchanged label was pushed to the menu again, every frame")
    end)

    s.test("an engine with no mod menu is never called into", function()
        -- Co-op DX versions without the mod menu leave rerollMenuIndex nil.
        -- Renaming element nil would be a call into the engine with a bad
        -- argument, every frame, for the whole session.
        local api, ctl = harness.load(function()
            hook_mod_menu_button = nil
        end)
        api.update_manual_reroll_menu()
        t.eq(#ctl.menu_renames, 0, "a menu that does not exist was renamed anyway")
    end)

    s.test("an engine without the rename function is not called into either", function()
        local api, ctl = harness.load(function()
            update_mod_menu_element_name = nil
        end)
        api.update_manual_reroll_menu()
        t.eq(#ctl.menu_renames, 0, "a rename was recorded by an engine that has none")
    end)
end
