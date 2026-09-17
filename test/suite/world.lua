-- Who shares a world with whom.
--
-- Two players in one level on different acts can be standing in geometry that
-- does not agree, and the mod hides them from each other and blocks PvP where
-- it does. Both answers feed visibility, nametags and whether damage lands, and
-- extracting them into modules/goals.lua found the whole area untested -- the
-- functions were published to STARHUNT_TEST_API and then never used.

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

    --- The Mario object the engine hands the interaction hook for a body.
    -- The engine stamps the owner onto the object every frame, and the mod
    -- reads that field rather than walking the player list, so the fixture has
    -- to carry it too.
    local function body_of(index)
        if gMarioStates[index].marioObj == nil then
            -- A stub stands in for the engine's Object, as everywhere else in
            -- test/: only the one field the mod reads off it is real.
            --- @diagnostic disable-next-line: missing-fields
            gMarioStates[index].marioObj = { globalPlayerIndex = gNetworkPlayers[index].globalIndex }
        end
        return gMarioStates[index].marioObj
    end

    s.test("nobody shares a world outside a round", function()
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        t.ok(api.players_can_share_world(0, 1), "same act in a round should share")
        gGlobalSyncTable.sh5_active = 0
        t.ok(not api.players_can_share_world(0, 1), "shared a world with no round running")
    end)

    s.test("a player never shares a world with themselves", function()
        -- Self-comparison reaching the geometry rules would let a player block
        -- their own visibility, and makes every caller loop over itself.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        t.ok(not api.players_can_share_world(0, 0), "player 0 shared a world with player 0")
    end)

    s.test("the same star in the same place is shared", function()
        local api, ctl = fresh()
        place(api, ctl, LEVEL_BOB, 1, 1)
        t.ok(api.players_can_share_world(0, 1), "two players on one star did not share")
        t.ok(not api.players_have_private_variant(0, 1), "one star reported a private variant")
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

    s.test("Tick Tock Clock isolates act 6 from the acts that keep running", function()
        -- Act 6 stops the clock; the others run it. Those object states cannot
        -- share one simulation anywhere in the course.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_TTC, 6, 1)
        t.ok(api.players_have_private_variant(0, 1), "act 6 shared a world with act 1")
        t.ok(not api.players_can_share_world(0, 1), "act 6 was visible to act 1")

        place(api, ctl, LEVEL_TTC, 1, 2)
        t.ok(not api.players_have_private_variant(0, 1),
            "two running-clock acts were isolated from each other")
    end)

    s.test("Wet-Dry World isolates every act from every other", function()
        -- The water level is global to the course, so there is no shared
        -- region at all between two different acts.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_WDW, 1, 4)
        t.ok(api.players_have_private_variant(0, 1), "two WDW acts shared a world")
        place(api, ctl, LEVEL_WDW, 3, 3)
        t.ok(not api.players_have_private_variant(0, 1), "one WDW act isolated from itself")
    end)

    s.test("Dire Dire Docks is one world for every act", function()
        -- The manta ray is the only act-gated object in the course
        -- (levels/ddd/script.c:31). The submarine and the nine poles come and go
        -- on SAVE_FLAG_HAVE_KEY_2 | SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR
        -- (ddd_sub.inc.c:4, ddd_pole.inc.c:3), and every client reads the host's
        -- save file, so the geometry is the same for everybody whatever act they
        -- were sent to.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_DDD, 1, 3)
        -- The submarine, its door and the poles are all in area 2.
        for i = 0, 1 do
            gNetworkPlayers[i].currAreaIndex = 2
            body_of(i)
        end
        t.ok(not api.players_have_private_variant(0, 1),
            "two DDD acts were isolated where the submarine sits")
        t.ok(api.players_can_share_world(0, 1),
            "two DDD acts standing together could not see each other")

        for i = 0, 1 do gMarioStates[i].pos = { x = 5760, y = 1005, z = 360 } end
        t.ok(api.players_can_share_world(0, 1),
            "two DDD acts were isolated at the outermost pole")

        -- Deep water in DDD, and also inside the box is_jrb_ship_zone tests.
        -- A zone belongs to the level whose rule names it and must not be
        -- reached from another course.
        for i = 0, 1 do gMarioStates[i].pos = { x = 0, y = -2000, z = -2000 } end
        t.ok(api.players_can_share_world(0, 1),
            "two DDD acts were isolated by another level's zone")
    end)

    s.test("Jolly Roger Bay is private only around the ship", function()
        -- The two ship layouts conflict, but the rest of the bay does not, so
        -- players stay visible until one of them reaches the ship.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_JRB, 1, 4)
        for i = 0, 1 do gMarioStates[i].pos = { x = 0, y = 0, z = 5000 } end
        t.ok(not api.players_have_private_variant(0, 1),
            "two JRB acts were isolated away from the ship")

        gMarioStates[1].pos = { x = 0, y = 0, z = -2000 }   -- inside the ship region
        t.ok(api.players_have_private_variant(0, 1),
            "a player reached the conflicting ship layout and stayed visible")
    end)

    s.test("Team and Chaos share a world wherever the players actually meet", function()
        -- Both are PvP races rather than parallel runs: if two players are
        -- standing in the same place they fight, whatever acts they were sent
        -- for. The per-act geometry rules are skipped entirely.
        local api, ctl = fresh()
        for _, mode in ipairs({ api.team_mode, api.chaos_mode }) do
            place(api, ctl, LEVEL_TTC, 6, 1, mode)
            t.ok(api.players_can_share_world(0, 1),
                "mode " .. mode .. " isolated two players in the same place")
            -- Asked directly, too: visibility and nametags call this one rather
            -- than going through players_can_share_world, so the Team/Chaos
            -- exemption has to live in both or players vanish mid-fight.
            t.ok(not api.players_have_private_variant(0, 1),
                "mode " .. mode .. " reported a private variant for two players "
                .. "standing together")
            gNetworkPlayers[1].currAreaIndex = 2
            t.ok(not api.players_can_share_world(0, 1),
                "mode " .. mode .. " shared a world across two areas")
        end
    end)

    s.test("a player hidden for an incompatible world is not a body to walk into", function()
        -- Hiding the model was only half of it. interact_player is the engine's
        -- one route into resolve_player_collision, so until the interaction was
        -- refused the hidden player stayed an invisible wall to bump into and
        -- stand on.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_TTC, 6, 1)
        t.ok(api.players_have_private_variant(0, 1), "the fixture stopped being a private pair")
        t.ok(api.allow_interact(gMarioStates[0], body_of(1), INTERACT_PLAYER) == false,
            "walked into a player the mod had hidden")
        -- Both directions: the engine moves whichever player it is processing,
        -- and a remote body landing on the local one squishes it, so the same
        -- contact has to be refused when the remote player is the one asking.
        t.ok(api.allow_interact(gMarioStates[1], body_of(0), INTERACT_PLAYER) == false,
            "a hidden player walked into the local one")
    end)

    s.test("players who share a world still touch each other", function()
        -- The refusal is not a blanket one: two players the mod has not hidden
        -- from each other keep the ordinary bumping, standing and PvP contact.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_TTC, 1, 2)
        t.ok(not api.players_have_private_variant(0, 1), "the fixture became a private pair")
        t.ne(api.allow_interact(gMarioStates[0], body_of(1), INTERACT_PLAYER), false,
            "two players on compatible acts were made intangible to each other")
    end)

    s.test("bodies stop passing through each other when the round ends", function()
        local api, ctl = fresh()
        place(api, ctl, LEVEL_TTC, 6, 1)
        gGlobalSyncTable.sh5_active = 0
        t.ne(api.allow_interact(gMarioStates[0], body_of(1), INTERACT_PLAYER), false,
            "the private-world rule outlived the round it belongs to")
    end)

    s.test("an object that is nobody's body is left alone", function()
        -- The hook answers for whatever object carries the flag, and the owner
        -- field it reads is 0 on every ordinary object, so an object that is
        -- not a player's body would otherwise read as the host's and be refused
        -- on the hidden player's behalf.
        local api, ctl = fresh()
        place(api, ctl, LEVEL_TTC, 6, 1)
        body_of(0)
        body_of(1)
        t.ne(api.allow_interact(gMarioStates[1], { globalPlayerIndex = 0 }, INTERACT_PLAYER), false,
            "an object carrying player 0's owner index but not player 0's body was refused")
        t.ne(api.allow_interact(gMarioStates[0], {}, INTERACT_PLAYER), false,
            "an object belonging to no player was refused")
        -- The engine never hands the hook a missing object, but the mod's own
        -- callers do, and reading a field off it would be a crash rather than a
        -- refusal.
        t.ne(api.allow_interact(gMarioStates[0], nil, INTERACT_PLAYER), false,
            "a missing object was refused")
    end)
end
