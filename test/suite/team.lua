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
end
