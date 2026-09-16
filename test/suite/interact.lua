-- modules/goals.lua: claiming a star, and hiding the ones that are not it.
--
-- on_allow_interact answers two unrelated questions in one function.  Outside a
-- round it is the lobby lock: doors, warp doors, the cannon and the HMC Metal
-- Cap portal are refused so a player cannot leave the castle or pick up a cap
-- StarHunt did not hand them.  Inside a round it is the star gate: only the
-- assigned star of the assigned act, in the right level and area, with every
-- coin toll paid.
--
-- on_interact is what happens when that gate lets a star through, and
-- update_star_visibility hides every star that would not.
--
-- None of it was covered before this suite existed.  `allow_interact` and
-- `interact` were published in STARHUNT_TEST_API and called by no test at all,
-- and `update_star_visibility` and `reset_hidden_object_tracking` were not
-- published, so the whole area could be deleted with a green run.
--
-- Two engine stubs had to be made real before any of this was reachable, and
-- both are the trap REFACTOR_PLAN.md already records.  `obj_has_behavior_id`
-- returned `false`, so `obj_has_behavior_id(o, id) == 0` was never true and the
-- HMC portal guard could not fire; `obj_get_first` returned nil, so the walk
-- inside update_star_visibility never ran a single iteration.
--
-- The rejection memory is the subtle part.  A star object that has already been
-- refused stays refused for that player, goal and round even if the object
-- itself later changes: a spawned star receives object-sync updates, and
-- without the memory an act value arriving late would turn a star the player
-- already tried into a valid target.  Three tests below pin that, one for each
-- field the memory is keyed on.

return function(t, harness)
    local s = t.suite("interact")

    -- Pinned as literals.  The fixture test fails loudly if the catalog is
    -- renumbered, rather than letting the rest of the suite test another star.
    local BOB1 = 1            -- BOB act 1, KING BOB-OMB, no required cap
    local BOB2 = 2            -- BOB act 2, the other act of the same level
    local COIN_TOLL_MOD = 19  -- index into goal 1's audited mods
    local COIN_TOLL_VALUE = 20

    -- The Metal Cap portal in vanilla HMC.
    local PORTAL_X, PORTAL_Y, PORTAL_Z = 3351, -4690, 4773

    --- A level object that reads as the star of `act`.
    local function star_object(act, invisible)
        return {
            oBehParams = (act - 1) << 24,
            oInteractType = INTERACT_STAR_OR_KEY,
            header = { gfx = { node = { flags = invisible and GRAPH_RENDER_INVISIBLE or 0 } } },
        }
    end

    local function invisible(object)
        return (object.header.gfx.node.flags & GRAPH_RENDER_INVISIBLE) ~= 0
    end

    --- Put the local player in an active Normal round standing on BOB act 1.
    local function enter(api, ctl)
        ctl.begin_round(api, api.normal_mode, api.medium)
        gPlayerSyncTable[0].sh5_goal = BOB1
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        gNetworkPlayers[0].currActNum = 1
        gNetworkPlayers[0].currAreaIndex = 1
    end

    s.test("the goal and the modifier these tests are written against are unchanged", function()
        -- LEVEL_* comes from the engine stub, so nothing may read it until
        -- harness.load() has installed it.
        local api = harness.load()
        local goal = api.goals[BOB1]
        t.eq(goal.level, LEVEL_BOB, "goal " .. BOB1 .. " changed level")
        t.eq(goal.act, 1, "goal " .. BOB1 .. " changed act")
        t.eq(api.goals[BOB2].level, LEVEL_BOB, "goal " .. BOB2 .. " is no longer the same level")
        t.eq(api.goals[BOB2].act, 2, "goal " .. BOB2 .. " changed act")
        local mod = goal.mods[COIN_TOLL_MOD]
        t.eq(mod.kind, "coin_toll", "modifier " .. COIN_TOLL_MOD .. " of goal " .. BOB1
            .. " is no longer the coin toll")
        t.eq(mod.value, COIN_TOLL_VALUE, "the coin toll on goal " .. BOB1 .. " changed value")
    end)

    -- -----------------------------------------------------------------------
    -- The lobby lock
    -- -----------------------------------------------------------------------

    s.test("the castle lock refuses every way out of the castle", function()
        -- Collision is deliberately left alone: only the use/warp interaction
        -- is refused, so players still bump into doors and the cannon.
        local cases = {
            { why = "the cannon", flag = INTERACT_CANNON_BASE },
            { why = "a door", flag = INTERACT_DOOR },
            { why = "a warp door", flag = INTERACT_WARP_DOOR },
            { why = "a warp", flag = INTERACT_WARP },
        }
        local levels = { LEVEL_CASTLE_GROUNDS, LEVEL_CASTLE, LEVEL_VCUTM }
        for _, level in ipairs(levels) do
            for _, case in ipairs(cases) do
                local api = harness.load()
                gNetworkPlayers[0].currLevelNum = level
                t.ok(api.allow_interact(gMarioStates[0], {}, case.flag) == false,
                    case.why .. " was allowed in level " .. level)
            end
        end
    end)

    s.test("the castle lock leaves other levels and other interactions alone", function()
        local api = harness.load()
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        t.ne(api.allow_interact(gMarioStates[0], {}, INTERACT_DOOR), false,
            "a door outside the castle was refused")
        gNetworkPlayers[0].currLevelNum = LEVEL_CASTLE_GROUNDS
        t.ne(api.allow_interact(gMarioStates[0], {}, INTERACT_DAMAGE), false,
            "an unrelated interaction in the castle was refused")
    end)

    s.test("the castle lock is read from the interacting player, not from player 0", function()
        -- Every player's interactions pass through this callback locally.
        -- Reading player 0's level would lock a remote player who is elsewhere.
        local api = harness.load()
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        gNetworkPlayers[1].currLevelNum = LEVEL_CASTLE_GROUNDS
        t.ok(api.allow_interact(gMarioStates[1], {}, INTERACT_DOOR) == false,
            "a door was allowed for a player who is in the castle")
    end)

    s.test("the HMC Metal Cap portal is refused", function()
        local api = harness.load()
        gNetworkPlayers[0].currLevelNum = LEVEL_HMC
        local portal = { behavior_id = id_bhvWarp,
                         oPosX = PORTAL_X, oPosY = PORTAL_Y, oPosZ = PORTAL_Z }
        t.ok(api.allow_interact(gMarioStates[0], portal, INTERACT_WARP) == false,
            "the Metal Cap portal was usable")
    end)

    s.test("only the real portal warp in HMC is refused", function()
        -- Each case changes exactly one thing about the refused case above.
        -- Matching the actual warp object is what keeps custom HMC warps working.
        local cases = {
            { why = "an object that is not a warp behavior",
              obj = { behavior_id = 12345, oPosX = PORTAL_X, oPosY = PORTAL_Y, oPosZ = PORTAL_Z },
              flag = INTERACT_WARP, level = LEVEL_HMC },
            { why = "a warp well away from the portal",
              obj = { behavior_id = id_bhvWarp, oPosX = PORTAL_X + 1500,
                      oPosY = PORTAL_Y, oPosZ = PORTAL_Z },
              flag = INTERACT_WARP, level = LEVEL_HMC },
            { why = "the portal in another level",
              obj = { behavior_id = id_bhvWarp, oPosX = PORTAL_X,
                      oPosY = PORTAL_Y, oPosZ = PORTAL_Z },
              flag = INTERACT_WARP, level = LEVEL_BOB },
            { why = "a non-warp interaction at the portal",
              obj = { behavior_id = id_bhvWarp, oPosX = PORTAL_X,
                      oPosY = PORTAL_Y, oPosZ = PORTAL_Z },
              flag = INTERACT_DAMAGE, level = LEVEL_HMC },
        }
        for _, case in ipairs(cases) do
            local api = harness.load()
            gNetworkPlayers[0].currLevelNum = case.level
            t.ne(api.allow_interact(gMarioStates[0], case.obj, case.flag), false,
                case.why .. " was refused")
        end
    end)

    s.test("the portal tolerance is a sphere around it, not an exact position", function()
        -- The warp object does not sit at exactly one coordinate in every
        -- build, so a warp near the portal is still the portal; one far away
        -- is somebody else's.
        local api = harness.load()
        gNetworkPlayers[0].currLevelNum = LEVEL_HMC
        local near = { behavior_id = id_bhvWarp, oPosX = PORTAL_X + 500,
                       oPosY = PORTAL_Y, oPosZ = PORTAL_Z }
        t.ok(api.allow_interact(gMarioStates[0], near, INTERACT_WARP) == false,
            "a warp 500 units from the portal was treated as a different warp")
        local far = { behavior_id = id_bhvWarp, oPosX = PORTAL_X,
                      oPosY = PORTAL_Y + 950, oPosZ = PORTAL_Z }
        t.ne(api.allow_interact(gMarioStates[0], far, INTERACT_WARP), false,
            "a warp 950 units from the portal was treated as the portal")
    end)

    -- -----------------------------------------------------------------------
    -- The star gate
    -- -----------------------------------------------------------------------

    s.test("stars are free outside a round and in Boss mode", function()
        local api, ctl = harness.load()
        t.ne(api.allow_interact(gMarioStates[0], star_object(3), INTERACT_STAR_OR_KEY), false,
            "a star was gated outside a round")
        enter(api, ctl)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        t.ne(api.allow_interact(gMarioStates[0], star_object(3), INTERACT_STAR_OR_KEY), false,
            "a star was gated in Boss mode")
    end)

    s.test("Chaos refuses every star and nothing else", function()
        -- Chaos has no star objective at all; a star collected there would
        -- silently end the level for everyone in it.
        local api, ctl = harness.load()
        enter(api, ctl)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        t.ok(api.allow_interact(gMarioStates[0], star_object(1), INTERACT_STAR_OR_KEY) == false,
            "a star was claimable in Chaos")
        t.ne(api.allow_interact(gMarioStates[0], {}, INTERACT_DAMAGE), false,
            "a non-star interaction was refused in Chaos")
    end)

    s.test("in a star race only the assigned star of the assigned act is allowed", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        t.ne(api.allow_interact(gMarioStates[0], star_object(1), INTERACT_STAR_OR_KEY), false,
            "the assigned star was refused")
        t.ne(api.allow_interact(gMarioStates[0], {}, INTERACT_DAMAGE), false,
            "a non-star interaction was refused during a round")
        t.ok(api.allow_interact(gMarioStates[0], star_object(2), INTERACT_STAR_OR_KEY) == false,
            "another act's star in the same level was allowed")
    end)

    s.test("a star is refused when there is no goal or no object", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        t.ok(api.allow_interact(gMarioStates[0], nil, INTERACT_STAR_OR_KEY) == false,
            "a nil object was allowed")
        gPlayerSyncTable[0].sh5_goal = 0
        t.ok(api.allow_interact(gMarioStates[0], star_object(1), INTERACT_STAR_OR_KEY) == false,
            "a star was allowed with no goal assigned")
    end)

    s.test("the assigned star is refused outside the goal's own level and area", function()
        local cases = {
            { why = "in the wrong level", setup = function()
                gNetworkPlayers[0].currLevelNum = LEVEL_CCM
            end },
            { why = "in the wrong act", setup = function()
                gNetworkPlayers[0].currActNum = 4
            end },
        }
        for _, case in ipairs(cases) do
            local api, ctl = harness.load()
            enter(api, ctl)
            case.setup()
            t.ok(api.allow_interact(gMarioStates[0], star_object(1), INTERACT_STAR_OR_KEY) == false,
                "the star was allowed " .. case.why)
        end
    end)

    s.test("the local player must have paid every coin toll", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        gPlayerSyncTable[0].sh5_modifier = COIN_TOLL_MOD
        local m = gMarioStates[0]
        m.numCoins = COIN_TOLL_VALUE - 1
        t.ok(api.allow_interact(m, star_object(1), INTERACT_STAR_OR_KEY) == false,
            "the star was claimable with the toll unpaid")
        m.numCoins = COIN_TOLL_VALUE
        t.ne(api.allow_interact(m, star_object(1), INTERACT_STAR_OR_KEY), false,
            "the star was refused with the toll paid")
    end)

    s.test("a remote player's coin toll is checked in both modifier slots", function()
        -- Nightmare gives a second modifier, and the local path cannot be
        -- reused for a remote player because get_local_modifiers() only ever
        -- answers for player 0.
        for _, slot in ipairs({ "sh5_modifier", "sh5_modifier_2" }) do
            local api, ctl = harness.load()
            enter(api, ctl)
            gNetworkPlayers[1].currLevelNum = LEVEL_BOB
            gNetworkPlayers[1].currActNum = 1
            gPlayerSyncTable[1].sh5_goal = BOB1
            gPlayerSyncTable[1][slot] = COIN_TOLL_MOD
            local m = gMarioStates[1]
            m.numCoins = COIN_TOLL_VALUE - 1
            t.ok(api.allow_interact(m, star_object(1), INTERACT_STAR_OR_KEY) == false,
                "a remote player claimed the star with " .. slot .. " unpaid")
            m.numCoins = COIN_TOLL_VALUE
            t.ne(api.allow_interact(m, star_object(1), INTERACT_STAR_OR_KEY), false,
                "a remote player was refused with " .. slot .. " paid")
        end
    end)

    -- -----------------------------------------------------------------------
    -- The rejection memory
    -- -----------------------------------------------------------------------

    s.test("a star already refused stays refused when the object itself changes", function()
        -- A spawned star keeps receiving object-sync updates.  Without the
        -- memory, an act arriving late would turn a star the player has
        -- already tried into a valid target.
        local api, ctl = harness.load()
        enter(api, ctl)
        local object = star_object(2)
        t.ok(api.allow_interact(gMarioStates[0], object, INTERACT_STAR_OR_KEY) == false,
            "the wrong star was allowed on the first try")
        object.oBehParams = 0 << 24        -- now reads as act 1, the assigned star
        t.ok(api.allow_interact(gMarioStates[0], object, INTERACT_STAR_OR_KEY) == false,
            "a rejected star became claimable once its act changed")
    end)

    s.test("the rejection is forgotten when the goal changes", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        local object = star_object(2)
        api.allow_interact(gMarioStates[0], object, INTERACT_STAR_OR_KEY)
        gPlayerSyncTable[0].sh5_goal = BOB2
        gNetworkPlayers[0].currActNum = 2
        t.ne(api.allow_interact(gMarioStates[0], object, INTERACT_STAR_OR_KEY), false,
            "the star was still refused after it became the new goal")
    end)

    s.test("the rejection is forgotten when a new round starts", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        local object = star_object(2)
        api.allow_interact(gMarioStates[0], object, INTERACT_STAR_OR_KEY)
        gGlobalSyncTable.sh5_round = (gGlobalSyncTable.sh5_round or 0) + 1
        object.oBehParams = 0 << 24
        t.ne(api.allow_interact(gMarioStates[0], object, INTERACT_STAR_OR_KEY), false,
            "a rejection from the previous round outlived it")
    end)

    s.test("one player's rejection does not reject another player", function()
        -- Both players are on the same goal in the same round, which is the
        -- only arrangement that tells the three keys apart: if the memory were
        -- kept per object instead of per player, player 1 would inherit an
        -- attempt they never made.
        local api, ctl = harness.load()
        enter(api, ctl)
        gNetworkPlayers[1].currLevelNum = LEVEL_BOB
        gNetworkPlayers[1].currActNum = 1
        gPlayerSyncTable[1].sh5_goal = BOB1
        local object = star_object(2)
        t.ok(api.allow_interact(gMarioStates[0], object, INTERACT_STAR_OR_KEY) == false,
            "the wrong star was allowed for player 0")
        object.oBehParams = 0 << 24        -- the late sync update arrives
        t.ne(api.allow_interact(gMarioStates[1], object, INTERACT_STAR_OR_KEY), false,
            "player 1 inherited player 0's rejection of a star they never tried")
    end)

    -- -----------------------------------------------------------------------
    -- Claiming the star
    -- -----------------------------------------------------------------------

    s.test("claiming the assigned star scores it once and removes the save flag", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        local m = gMarioStates[0]
        api.interact(m, star_object(1), INTERACT_STAR_OR_KEY, true)
        t.eq(gPlayerSyncTable[0].sh5_done, 1, "the star was not scored")
        t.ok(api.runtime.done_lock, "the done lock was not taken")
        t.eq(ctl.storage["starhunt_lifetime_stars"], "1", "the lifetime count was not saved")
        t.eq(#ctl.save.removed, 1, "StarHunt's temporary save flag was not removed")
        -- BOB is course 1 in the game and course 0 in the save file, and act 1
        -- is bit 0.
        t.eq(ctl.save.removed[1].course, 0, "the wrong course was cleaned up")
        t.eq(ctl.save.removed[1].flags, 1, "the wrong star flag was cleaned up")
        t.eq(#ctl.popups, 1, "no star-get popup was shown")

        -- The lock is what stops the same star scoring twice.
        api.interact(m, star_object(1), INTERACT_STAR_OR_KEY, true)
        t.eq(gPlayerSyncTable[0].sh5_done, 1, "the same star scored twice")
    end)

    s.test("nothing is claimed when any condition of the claim is missing", function()
        local cases = {
            { why = "for a remote player", index = 1 },
            { why = "outside a round", setup = function() gGlobalSyncTable.sh5_active = 0 end },
            { why = "in Chaos mode", setup = function(api) gGlobalSyncTable.sh5_mode = api.chaos_mode end },
            { why = "when the interaction did not happen", did = false },
            { why = "for a non-star interaction", flag = INTERACT_DAMAGE },
            { why = "in the wrong level", setup = function()
                gNetworkPlayers[0].currLevelNum = LEVEL_CCM
            end },
            { why = "for another act's star", act = 2 },
            { why = "with a coin toll unpaid", setup = function()
                gPlayerSyncTable[0].sh5_modifier = COIN_TOLL_MOD
                gMarioStates[0].numCoins = COIN_TOLL_VALUE - 1
            end },
        }
        for _, case in ipairs(cases) do
            local api, ctl = harness.load()
            enter(api, ctl)
            if case.setup ~= nil then case.setup(api) end
            local index = case.index or 0
            local object = star_object(case.act or 1)
            local flag = case.flag or INTERACT_STAR_OR_KEY
            local did = case.did
            if did == nil then did = true end
            api.interact(gMarioStates[index], object, flag, did)
            t.is_nil(gPlayerSyncTable[0].sh5_done, "a star was scored " .. case.why)
            t.eq(#ctl.save.removed, 0, "a save flag was removed " .. case.why)
        end
    end)

    s.test("Boss modifier 1 makes any damage lethal, and only in Boss mode", function()
        -- The first Boss modifier is one-hit death.  Every case here changes
        -- exactly one thing about the lethal case.
        local cases = {
            { why = "damage", flag = INTERACT_DAMAGE, dead = true },
            { why = "flame", flag = INTERACT_FLAME, dead = true },
            { why = "a star", flag = INTERACT_STAR_OR_KEY, dead = false },
            { why = "damage that did not land", flag = INTERACT_DAMAGE, did = false, dead = false },
            { why = "damage without the modifier", flag = INTERACT_DAMAGE, mod = 2, dead = false },
        }
        for _, case in ipairs(cases) do
            local api, ctl = harness.load()
            ctl.begin_round(api, api.boss_mode, api.medium)
            gGlobalSyncTable.sh5_boss_modifier_1 = case.mod or 1
            local m = gMarioStates[0]
            m.health = 0x880
            local did = case.did
            if did == nil then did = true end
            api.interact(m, {}, case.flag, did)
            if case.dead then
                t.eq(m.health, 0, case.why .. " was not lethal under Boss modifier 1")
            else
                t.eq(m.health, 0x880, case.why .. " killed the player")
            end
        end
    end)

    s.test("a star cannot be scored in Boss mode", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, api.boss_mode, api.medium)
        gPlayerSyncTable[0].sh5_goal = BOB1
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        gNetworkPlayers[0].currActNum = 1
        api.interact(gMarioStates[0], star_object(1), INTERACT_STAR_OR_KEY, true)
        t.is_nil(gPlayerSyncTable[0].sh5_done, "a star was scored during a Boss round")
    end)

    -- -----------------------------------------------------------------------
    -- Hiding the stars that are not the goal
    -- -----------------------------------------------------------------------

    s.test("level init forgets everything the previous level was tracking", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        local rt = api.runtime
        rt.hidden_stars = { [1] = true }
        rt.rejected_stars = { [1] = true }
        rt.hidden_players = { [1] = true }
        rt.star_visibility_next = 500
        api.reset_hidden_objects()
        t.is_nil(next(rt.hidden_stars), "hidden stars survived a level change")
        t.is_nil(next(rt.rejected_stars), "rejected stars survived a level change")
        t.is_nil(next(rt.hidden_players), "hidden players survived a level change")
        t.eq(rt.star_visibility_next, 0, "the visibility throttle was not released")
    end)

    s.test("the wrong stars are hidden and the assigned one is left alone", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        local right, wrong = star_object(1), star_object(2)
        local other = { oInteractType = INTERACT_DAMAGE }
        ctl.level_objects = { right, wrong, other }
        api.star_visibility()
        t.ok(not invisible(right), "the assigned star was hidden")
        t.ok(invisible(wrong), "another act's star was left visible")
        t.is_nil(other.header, "a non-star object was touched")
    end)

    s.test("the walk runs at most once per frame", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        local wrong = star_object(2)
        ctl.level_objects = { wrong }
        api.star_visibility()
        t.ok(invisible(wrong), "the first pass did nothing")
        wrong.header.gfx.node.flags = 0
        api.star_visibility()
        t.ok(not invisible(wrong), "the walk ran twice in the same frame")
        ctl.timer = ctl.timer + 1
        api.star_visibility()
        t.ok(invisible(wrong), "the walk never ran again on a later frame")
    end)

    s.test("nothing is hidden where there is no star objective", function()
        local cases = {
            { why = "outside a round", setup = function(_) gGlobalSyncTable.sh5_active = 0 end },
            { why = "in Boss mode", setup = function(api) gGlobalSyncTable.sh5_mode = api.boss_mode end },
            { why = "with no goal assigned", setup = function(_) gPlayerSyncTable[0].sh5_goal = 0 end },
        }
        for _, case in ipairs(cases) do
            local api, ctl = harness.load()
            enter(api, ctl)
            case.setup(api)
            local wrong = star_object(2)
            ctl.level_objects = { wrong }
            api.star_visibility()
            t.ok(not invisible(wrong), "a star was hidden " .. case.why)
        end
    end)

    s.test("the assigned star is hidden while it cannot be claimed", function()
        -- Showing a star the gate would refuse makes it a tempting fake goal.
        local cases = {
            { why = "the player is in another level", setup = function()
                gNetworkPlayers[0].currLevelNum = LEVEL_CCM
            end },
            { why = "a coin toll is unpaid", setup = function()
                gPlayerSyncTable[0].sh5_modifier = COIN_TOLL_MOD
                gMarioStates[0].numCoins = COIN_TOLL_VALUE - 1
            end },
        }
        for _, case in ipairs(cases) do
            local api, ctl = harness.load()
            enter(api, ctl)
            case.setup()
            local right = star_object(1)
            ctl.level_objects = { right }
            api.star_visibility()
            t.ok(invisible(right), "the assigned star was visible while " .. case.why)
        end
    end)

    s.test("a star that was already invisible is left invisible when the round ends", function()
        -- Only the flags StarHunt itself set are ever cleared, the same rule
        -- the required-cap code follows.
        local api, ctl = harness.load()
        enter(api, ctl)
        local theirs = star_object(2, true)
        local ours = star_object(2)
        ctl.level_objects = { theirs, ours }
        api.star_visibility()
        t.ok(invisible(theirs) and invisible(ours), "the wrong stars were not hidden")

        gGlobalSyncTable.sh5_active = 0
        ctl.timer = ctl.timer + 1
        api.star_visibility()
        t.ok(invisible(theirs), "a star hidden by something else was revealed")
        t.ok(not invisible(ours), "a star StarHunt hid was never revealed")
    end)

    s.test("a revealed star is forgotten, so hiding it again remembers the right original", function()
        local api, ctl = harness.load()
        enter(api, ctl)
        local star = star_object(2)
        ctl.level_objects = { star }
        api.star_visibility()
        gGlobalSyncTable.sh5_active = 0
        ctl.timer = ctl.timer + 1
        api.star_visibility()
        t.is_nil(api.runtime.hidden_stars[star], "the revealed star was still being tracked")
    end)
end
