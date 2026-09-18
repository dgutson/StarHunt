-- Who shares a world with whom.
--
-- Two players in one course are sent to different stars, so they load different
-- acts. The engine decides whether they can see, collide with and damage each
-- other; the mod's part is to ask sm64coopdx to leave the act out of that
-- decision, and then to leave the pair alone. What is left here is the rest of
-- the same-place question -- the round, the level, the area -- and the proof
-- that no act is treated as a reason to separate two players.

return function(t, harness)
    local s = t.suite("world")

    local function fresh()
        local api, ctl = harness.load()
        ctl.player_count = 2
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 2 end
        return api, ctl
    end

    --- Put players 0 and 1 in `level`, on the given acts, in the same area.
    local function place(api, ctl, level, act_a, act_b, mode)
        local ids = {}
        for id, goal in ipairs(api.goals) do
            if goal.level == level then ids[goal.act] = id end
        end
        gPlayerSyncTable[0].sh5_goal = ids[act_a]
        gPlayerSyncTable[1].sh5_goal = ids[act_b]
        for i = 0, 1 do
            gNetworkPlayers[i].currLevelNum = level
            gNetworkPlayers[i].currAreaIndex = 1
            gNetworkPlayers[i].currActNum = i == 0 and act_a or act_b
            gMarioStates[i].pos = { x = 0, y = 0, z = 0 }
        end
        ctl.begin_round(api, mode or api.normal_mode, api.medium)
    end

    -- -----------------------------------------------------------------------
    -- Asking the engine to ignore the act
    -- -----------------------------------------------------------------------

    s.test("the mod asks the engine to let acts meet", function()
        harness.load()
        t.eq(gLevelValues.crossActPlayers, 1,
            "the mod did not set crossActPlayers on a build that has it")
    end)

    s.test("a build without the field is left alone", function()
        local api = harness.load()
        local plain = {}
        api.enable_cross_act_players(plain)
        t.is_nil(next(plain), "wrote a field the engine does not have")
    end)

    -- -----------------------------------------------------------------------
    -- The same-place question
    -- -----------------------------------------------------------------------

    s.test("nobody shares a world outside a round", function()
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        t.ok(api.players_can_share_world(0, 1), "same act in a round should share")
        gGlobalSyncTable.sh5_active = 0
        t.ok(not api.players_can_share_world(0, 1), "shared a world with no round running")
    end)

    s.test("a player never shares a world with themselves", function()
        -- Self-comparison makes every caller loop over itself, and a player who
        -- shares a world with themselves can be refused their own contact.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        t.ok(not api.players_can_share_world(0, 0), "player 0 shared a world with player 0")
    end)

    s.test("the same star in the same place is shared", function()
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        t.ok(api.players_can_share_world(0, 1), "two players on one star did not share")
    end)

    s.test("a different level or a different area is never shared", function()
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        gNetworkPlayers[1].currLevelNum = LEVEL_CCM
        t.ok(not api.players_can_share_world(0, 1), "shared across two levels")

        place(api, ctl, LEVEL_BOB, 1, 1)
        gNetworkPlayers[1].currAreaIndex = 2
        t.ok(not api.players_can_share_world(0, 1), "shared across two areas")
    end)

    s.test("two players each in their own course do not share a world", function()
        -- The ordinary Normal-mode case: every player is sent to a different
        -- star, so each is standing in the level their own goal names. Nothing
        -- downstream re-checks that the two levels match, so dropping that
        -- comparison lets players in different courses damage each other.
        local api, ctl = fresh()
        local bob, ccm
        for id, goal in ipairs(api.goals) do
            if goal.level == LEVEL_BOB and goal.act == 1 then bob = id end
            if goal.level == LEVEL_CCM and goal.act == 1 then ccm = id end
        end
        gPlayerSyncTable[0].sh5_goal = bob
        gPlayerSyncTable[1].sh5_goal = ccm
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        gNetworkPlayers[1].currLevelNum = LEVEL_CCM
        for i = 0, 1 do
            gNetworkPlayers[i].currAreaIndex = 1
            gMarioStates[i].pos = { x = 0, y = 0, z = 0 }
        end
        ctl.begin_round(api, api.normal_mode, api.medium)

        t.ok(not api.players_can_share_world(0, 1),
            "a player in Bob-omb Battlefield shared a world with one in Cool, Cool Mountain")
    end)

    -- -----------------------------------------------------------------------
    -- The act is not a reason to separate anybody
    -- -----------------------------------------------------------------------

    s.test("two players in one course share a world whatever acts they hold", function()
        -- Each course here was once isolated by a rule of its own, and each
        -- rule is now the engine's job: the two players load different acts,
        -- keep their own act's objects, and meet anyway.
        --
        --   TTC -- act 6 stops the clock while the other acts run it.
        --   JRB -- the sunken hull sits at y = -5520 in act 1 and the raised
        --          one at y = +820 in acts 2-6.
        --   WF  -- the tower and its platforms exist from act 2 onward.
        --   BBH -- the hidden staircase steps exist from act 2 onward.
        --   DDD -- only the manta ray is act-gated. The submarine, its door and
        --          the nine poles read SAVE_FLAG_HAVE_KEY_2 |
        --          SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR (ddd_sub.inc.c:4,
        --          ddd_pole.inc.c:3) out of a save file every client is handed.
        --   WDW -- every object in both areas of levels/wdw/script.c is
        --          ALL_ACTS, and the water level is not derived from the act.
        local api, ctl = fresh()
        for _, course in ipairs({
            { level = LEVEL_TTC, acts = { 6, 1 } },
            { level = LEVEL_JRB, acts = { 1, 4 } },
            { level = LEVEL_WF,  acts = { 1, 2 } },
            { level = LEVEL_BBH, acts = { 1, 2 } },
            { level = LEVEL_DDD, acts = { 1, 3 } },
            { level = LEVEL_WDW, acts = { 1, 4 } },
        }) do
            place(api, ctl, course.level, course.acts[1], course.acts[2])
            t.ok(api.players_can_share_world(0, 1),
                "level " .. course.level .. " separated acts "
                .. course.acts[1] .. " and " .. course.acts[2])
        end
    end)

    s.test("where the two players stand makes no difference", function()
        -- The separation that used to exist was decided by position: boxes
        -- around Whomp's tower and the Jolly Roger Bay ship, and any interior
        -- room in Big Boo's Haunt. Nothing reads a player's position to answer
        -- this question any more, and these are the places it used to.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_JRB, 1, 4)
        for _, spot in ipairs({
            { x = 5385, y = -5520, z = 2428 },   -- the sunken hull, act 1
            { x = 4880, y = 820,   z = 2375 },   -- the raised hull, acts 2-6
            { x = 0,    y = 2000,  z = 0 },      -- above Whomp's tower height
            { x = 0,    y = 0,     z = -2000 },
        }) do
            for i = 0, 1 do gMarioStates[i].pos = spot end
            t.ok(api.players_can_share_world(0, 1),
                "two acts were separated at " .. spot.x .. "," .. spot.y .. "," .. spot.z)
        end

        place(api, ctl, LEVEL_BBH, 1, 2)
        for i = 0, 1 do gMarioStates[i].currentRoom = 3 end
        t.ok(api.players_can_share_world(0, 1),
            "two acts were separated inside Big Boo's Haunt")
    end)

    s.test("Team and Chaos ask where the players are, not what they were sent to get", function()
        -- Both are PvP races rather than parallel runs: if two players are
        -- standing in the same place they fight, whatever they were sent to
        -- collect. That is a branch of its own, and the goal a player holds is
        -- what tells it apart from the Normal-mode answer below it -- these two
        -- hold stars in different courses, which Normal mode refuses.
        local api, ctl = fresh()
        local ccm
        for id, goal in ipairs(api.goals) do
            if goal.level == LEVEL_CCM and goal.act == 1 then ccm = id end
        end
        for _, mode in ipairs({ api.team_mode, api.chaos_mode }) do
            place(api, ctl, LEVEL_TTC, 6, 1, mode)
            t.ok(api.players_can_share_world(0, 1),
                "mode " .. mode .. " separated two players in the same place")

            gPlayerSyncTable[1].sh5_goal = ccm
            t.ok(api.players_can_share_world(0, 1),
                "mode " .. mode .. " read the goals instead of where the players stand")

            gNetworkPlayers[1].currLevelNum = LEVEL_CCM
            t.ok(not api.players_can_share_world(0, 1),
                "mode " .. mode .. " shared a world across two levels")

            place(api, ctl, LEVEL_TTC, 6, 1, mode)
            gNetworkPlayers[1].currAreaIndex = 2
            t.ok(not api.players_can_share_world(0, 1),
                "mode " .. mode .. " shared a world across two areas")

            place(api, ctl, LEVEL_TTC, 6, 1, mode)
            gNetworkPlayers[1].connected = false
            t.ok(not api.players_can_share_world(0, 1),
                "mode " .. mode .. " shared a world with a player who had left")
            gNetworkPlayers[1].connected = true
        end
    end)

    s.test("a player with no goal yet shares a world with nobody", function()
        -- A player who joins mid-round holds no goal until the host deals one,
        -- and the absent goal reads as goal 0, which is not a star.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        gPlayerSyncTable[1].sh5_goal = nil
        t.ok(not api.players_can_share_world(0, 1),
            "the other player having no goal was not enough to separate them")

        -- Each side on its own: whichever of the two is missing a goal, the
        -- answer is no, and a fixture that drops both at once cannot tell the
        -- two reads apart.
        place(api, ctl, LEVEL_BOB, 1, 1)
        gPlayerSyncTable[0].sh5_goal = nil
        t.ok(not api.players_can_share_world(0, 1),
            "this player having no goal was not enough to separate them")
    end)

    -- -----------------------------------------------------------------------
    -- Damage
    -- -----------------------------------------------------------------------

    s.test("two players on different acts may hit each other", function()
        -- The engine asks this hook before it lets one player's attack land on
        -- another. Both directions: either of them may be the attacker.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_TTC, 6, 1)
        t.ok(api.allow_pvp_attack(gMarioStates[0], gMarioStates[1], 0),
            "an attack on a player from another act was refused")
        t.ok(api.allow_pvp_attack(gMarioStates[1], gMarioStates[0], 0),
            "an attack by a player from another act was refused")
    end)

    s.test("two players in different courses still may not hit each other", function()
        -- Each of them is standing in their own goal's course, which is the
        -- ordinary shape of a round. Whatever the engine now allows between
        -- acts, two players who are not in one place do not fight.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_TTC, 6, 1)
        gNetworkPlayers[1].currAreaIndex = 2
        t.ok(not api.allow_pvp_attack(gMarioStates[0], gMarioStates[1], 0),
            "an attack landed across two areas")
    end)
end
