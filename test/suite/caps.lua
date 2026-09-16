-- modules/goals.lua: the required cap a goal asks for.
--
-- Twelve of the 93 goals name a `power`, and StarHunt hands the player that cap
-- while they stand in the goal's own level and act.  The hard part is not
-- granting it but giving the cap state back: DEVELOPMENT_CHECKLIST.md lists
-- "gorras desaparecían o quedaban permanentes" as a fixed bug whose fix must not
-- be undone, and the fix is that StarHunt removes only the flags it added
-- itself, keeps a cap another mod refreshed underneath it, and restores the cap
-- timer and the cap-on-head flag to the values it found.
--
-- None of that was covered before this suite existed.  `apply_goal_power` was
-- published in STARHUNT_TEST_API as `power` and called by no test at all, so
-- every one of those guarantees could be deleted with a green run.
--
-- Three writes in `restore_starhunt_power` are unreachable rather than
-- untested, and are recorded here instead of being faked into a test: resetting
-- `local_starhunt_added_flags`, `local_runtime.power_external_timer` and
-- `local_runtime.power_original_head`.  All three are written again by
-- `apply_goal_power` on the only path that can reach the next restore -- the
-- `desired ~= nil` branch -- so their stale value is never read.  A fourth is
-- the `return 0` fallback in `power_flags`, which no goal can reach because
-- run_static_modifier_checks() rejects any goal whose power is not one of the
-- four names; the last test here reaches it by staging a goal the catalog
-- would never ship.

return function(t, harness)
    local s = t.suite("caps")

    -- Pinned as literals.  If a goal is ever renumbered these stop naming the
    -- star they were written for, and the fixture test below says so loudly
    -- rather than letting the rest of the suite test the wrong star.
    local WING = 5           -- BOB act 5, MARIO WINGS TO THE SKY
    local METAL = 33         -- HMC act 3, METAL-HEAD MARIO CAN MOVE!
    local VANISH = 30        -- BBH act 6, EYE TO EYE IN THE SECRET ROOM
    local BOTH = 54          -- DDD act 6, COLLECT THE CAPS...
    local NO_POWER = 1       -- BOB act 1, KING BOB-OMB

    --- Put the local player in an active Normal round, standing on `goal_id`.
    local function enter(api, ctl, goal_id, level, act)
        ctl.begin_round(api, api.normal_mode, api.medium)
        gPlayerSyncTable[0].sh5_goal = goal_id
        gNetworkPlayers[0].currLevelNum = level
        gNetworkPlayers[0].currActNum = act
    end

    s.test("the goals these tests are written against still carry those powers", function()
        -- The LEVEL_* constants come from the engine stub, so nothing may read
        -- them until harness.load() has installed it.
        local api = harness.load()
        local expected = {
            [WING] = { LEVEL_BOB, 5, "wing" },
            [METAL] = { LEVEL_HMC, 3, "metal" },
            [VANISH] = { LEVEL_BBH, 6, "vanish" },
            [BOTH] = { LEVEL_DDD, 6, "metal_vanish" },
        }
        for id, want in pairs(expected) do
            local goal = api.goals[id]
            t.eq(goal.level, want[1], "goal " .. id .. " changed level")
            t.eq(goal.act, want[2], "goal " .. id .. " changed act")
            t.eq(goal.power, want[3], "goal " .. id .. " changed power")
        end
        t.is_nil(api.goals[NO_POWER].power, "goal " .. NO_POWER .. " was supposed to need no cap")
    end)

    s.test("each required power grants exactly its own cap flags", function()
        local cases = {
            { id = WING, level = LEVEL_BOB, act = 5, flags = MARIO_WING_CAP, name = "wing" },
            { id = METAL, level = LEVEL_HMC, act = 3, flags = MARIO_METAL_CAP, name = "metal" },
            { id = VANISH, level = LEVEL_BBH, act = 6, flags = MARIO_VANISH_CAP, name = "vanish" },
            { id = BOTH, level = LEVEL_DDD, act = 6, name = "metal_vanish",
              flags = MARIO_METAL_CAP | MARIO_VANISH_CAP },
        }
        for _, case in ipairs(cases) do
            local api, ctl = harness.load()
            local m = gMarioStates[0]
            m.flags, m.capTimer = 0, 0
            enter(api, ctl, case.id, case.level, case.act)
            api.power(m)
            t.eq(m.flags, case.flags | MARIO_CAP_ON_HEAD, case.name .. " granted the wrong flags")
            t.eq(m.capTimer, 0x7FFF, case.name .. " should not be on a countdown")
        end
    end)

    s.test("no cap is granted where the goal does not ask for one", function()
        -- Four separate reasons to grant nothing.  Each one is a single
        -- condition in apply_goal_power, and dropping any of them hands out a
        -- cap in a level or a mode that never asked for it.
        local cases = {
            { why = "outside a round", setup = function(_) gGlobalSyncTable.sh5_active = 0 end },
            { why = "in Boss mode", setup = function(api)
                gGlobalSyncTable.sh5_mode = api.boss_mode
            end },
            { why = "in the wrong level", setup = function(_)
                gNetworkPlayers[0].currLevelNum = LEVEL_CCM
            end },
            { why = "in the wrong act", setup = function(_)
                gNetworkPlayers[0].currActNum = 4
            end },
            { why = "on a goal with no required cap", setup = function(_)
                gPlayerSyncTable[0].sh5_goal = NO_POWER
                gNetworkPlayers[0].currActNum = 1
            end },
        }
        for _, case in ipairs(cases) do
            local api, ctl = harness.load()
            local m = gMarioStates[0]
            m.flags, m.capTimer = 0, 0
            enter(api, ctl, WING, LEVEL_BOB, 5)
            case.setup(api)
            api.power(m)
            t.eq(m.flags, 0, "a cap was granted " .. case.why)
            t.eq(m.capTimer, 0, "the cap timer was touched " .. case.why)
        end
    end)

    s.test("only the local player is given the cap", function()
        -- Every Mario state passes through HOOK_BEFORE_MARIO_UPDATE, remote
        -- players included.  Writing another player's flags locally desyncs them.
        local api, ctl = harness.load()
        enter(api, ctl, WING, LEVEL_BOB, 5)
        for i = 0, 3 do
            gNetworkPlayers[i].currLevelNum = LEVEL_BOB
            gNetworkPlayers[i].currActNum = 5
            gPlayerSyncTable[i].sh5_goal = WING
            gMarioStates[i].flags, gMarioStates[i].capTimer = 0, 0
        end
        for i = 0, 3 do api.power(gMarioStates[i]) end
        t.eq(gMarioStates[0].flags, MARIO_WING_CAP | MARIO_CAP_ON_HEAD, "the local player")
        for i = 1, 3 do
            t.eq(gMarioStates[i].flags, 0, "remote player " .. i .. " was given a cap")
            t.eq(gMarioStates[i].capTimer, 0, "remote player " .. i .. "'s cap timer")
        end
    end)

    s.test("a cap another mod already granted survives the round", function()
        -- The do-not-undo fix.  StarHunt adds Wing on top of a Metal cap it did
        -- not grant, and when the round ends it takes back Wing and nothing else.
        local api, ctl = harness.load()
        local m = gMarioStates[0]
        m.flags = MARIO_METAL_CAP | MARIO_CAP_ON_HEAD
        m.capTimer = 300
        enter(api, ctl, WING, LEVEL_BOB, 5)

        api.power(m)
        t.eq(m.flags, MARIO_METAL_CAP | MARIO_WING_CAP | MARIO_CAP_ON_HEAD,
            "the external Metal cap should still be there alongside Wing")

        gGlobalSyncTable.sh5_active = 0
        api.power(m)
        t.eq(m.flags, MARIO_METAL_CAP | MARIO_CAP_ON_HEAD,
            "only StarHunt's own Wing flag should have been removed")
        t.eq(m.capTimer, 300, "the external cap's own timer should have come back")
    end)

    s.test("a cap the player already had is not claimed just because the goal wants it", function()
        -- The player walks into a Wing-cap star already wearing a Wing cap
        -- another mod gave them.  StarHunt adds nothing, so it must take nothing
        -- away at the end -- the flag was never its own.  Recording the whole
        -- required cap as "added" instead of only the missing part is what makes
        -- StarHunt steal a cap it did not grant.
        local api, ctl = harness.load()
        local m = gMarioStates[0]
        m.flags = MARIO_WING_CAP | MARIO_CAP_ON_HEAD
        m.capTimer = 300
        enter(api, ctl, WING, LEVEL_BOB, 5)
        api.power(m)

        gGlobalSyncTable.sh5_active = 0
        api.power(m)
        t.eq(m.flags & MARIO_WING_CAP, MARIO_WING_CAP,
            "the player's own Wing cap was taken away with StarHunt's")
        t.eq(m.flags & MARIO_CAP_ON_HEAD, MARIO_CAP_ON_HEAD, "the cap came off the head")
        t.eq(m.capTimer, 300, "the player's own cap timer should have come back")
    end)

    s.test("a cap refreshed underneath StarHunt is left where it is", function()
        -- Another mod re-granted the same cap with a finite timer while
        -- StarHunt held it.  The flag is no longer StarHunt's to remove, so the
        -- round ending must leave both the flag and the mod's timer alone.
        local api, ctl = harness.load()
        local m = gMarioStates[0]
        m.flags, m.capTimer = 0, 0
        enter(api, ctl, WING, LEVEL_BOB, 5)
        api.power(m)

        m.capTimer = 600                  -- the other mod's refresh
        api.power(m)
        t.eq(m.capTimer, 0x7FFF, "StarHunt still holds the cap while the round runs")

        gGlobalSyncTable.sh5_active = 0
        api.power(m)
        t.eq(m.flags & MARIO_WING_CAP, MARIO_WING_CAP,
            "the refreshed Wing cap belongs to the other mod now and must stay")
        t.eq(m.capTimer, 600, "the other mod's timer should have come back")
    end)

    s.test("a refresh does not protect the cap when a different one is also present", function()
        -- Same refresh, but the player is carrying a special cap StarHunt never
        -- granted.  That makes the refresh ambiguous, so StarHunt falls back to
        -- removing its own flag rather than keeping a cap it does own.
        local api, ctl = harness.load()
        local m = gMarioStates[0]
        m.flags = MARIO_METAL_CAP
        m.capTimer = 200
        enter(api, ctl, WING, LEVEL_BOB, 5)
        api.power(m)

        m.capTimer = 600
        api.power(m)

        gGlobalSyncTable.sh5_active = 0
        api.power(m)
        t.eq(m.flags & MARIO_WING_CAP, 0, "StarHunt's own Wing flag should have gone")
        t.eq(m.flags & MARIO_METAL_CAP, MARIO_METAL_CAP, "the other cap should have stayed")
    end)

    s.test("the cap-on-head flag is put back the way it was found", function()
        for _, had_cap in ipairs({ true, false }) do
            local api, ctl = harness.load()
            local m = gMarioStates[0]
            m.flags = had_cap and MARIO_CAP_ON_HEAD or 0
            m.capTimer = 0
            enter(api, ctl, VANISH, LEVEL_BBH, 6)

            api.power(m)
            t.eq(m.flags & MARIO_CAP_ON_HEAD, MARIO_CAP_ON_HEAD,
                "the cap has to be on the head while StarHunt holds it")

            gGlobalSyncTable.sh5_active = 0
            api.power(m)
            t.eq(m.flags & MARIO_CAP_ON_HEAD, had_cap and MARIO_CAP_ON_HEAD or 0,
                had_cap and "a cap that was already on the head was taken off"
                    or "a cap was left on a head that had none")
            t.eq(m.flags & MARIO_VANISH_CAP, 0, "the Vanish cap should have gone either way")
        end
    end)

    s.test("moving to a goal with a different cap swaps the cap rather than stacking it", function()
        local api, ctl = harness.load()
        local m = gMarioStates[0]
        m.flags, m.capTimer = 0, 0
        enter(api, ctl, WING, LEVEL_BOB, 5)
        api.power(m)
        t.eq(m.flags, MARIO_WING_CAP | MARIO_CAP_ON_HEAD, "the first goal's cap")

        gPlayerSyncTable[0].sh5_goal = METAL
        gNetworkPlayers[0].currLevelNum = LEVEL_HMC
        gNetworkPlayers[0].currActNum = 3
        api.power(m)
        t.eq(m.flags, MARIO_METAL_CAP | MARIO_CAP_ON_HEAD,
            "the previous goal's Wing cap should not have carried over")
    end)

    s.test("holding the same cap across frames does not accumulate anything", function()
        -- apply_goal_power runs twice per frame, under BEFORE_MARIO_UPDATE and
        -- again under MARIO_UPDATE.  Repeating it must be a no-op, and the timer
        -- the round started with must still be what comes back at the end.
        local api, ctl = harness.load()
        local m = gMarioStates[0]
        m.flags, m.capTimer = 0, 90
        enter(api, ctl, BOTH, LEVEL_DDD, 6)
        for _ = 1, 10 do api.power(m) end
        t.eq(m.flags, MARIO_METAL_CAP | MARIO_VANISH_CAP | MARIO_CAP_ON_HEAD,
            "ten frames of the same goal")
        t.eq(m.capTimer, 0x7FFF, "the cap should still be held open")

        gGlobalSyncTable.sh5_active = 0
        api.power(m)
        api.power(m)
        t.eq(m.flags, 0, "both flags and the cap-on-head should have gone")
        t.eq(m.capTimer, 90, "the timer the round started with")
    end)

    s.test("an unrecognised power name grants nothing at all", function()
        -- run_static_modifier_checks() refuses to let a goal ship with a power
        -- outside the four known names, so this is the fallback nobody can reach
        -- through the catalog.  Staging it here is what keeps `return 0` from
        -- becoming `return MARIO_WING_CAP` unnoticed.
        local api, ctl = harness.load()
        local m = gMarioStates[0]
        m.flags, m.capTimer = 0, 0
        api.goals[WING].power = "rainbow"
        enter(api, ctl, WING, LEVEL_BOB, 5)
        api.power(m)
        t.eq(m.flags & (MARIO_WING_CAP | MARIO_METAL_CAP | MARIO_VANISH_CAP), 0,
            "an unknown power name must not fall back to a real cap")
    end)
end
