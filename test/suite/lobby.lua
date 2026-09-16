-- The castle grounds themselves, which belong to no StarHunt system: the
-- camera Lakitu that plays the opening scene, and the water level under the
-- moat.  Both run whether or not a round is active.
--
-- DEVELOPMENT_CHECKLIST.md records the original bug and has carried "Sin
-- prueba" against it ever since: Lakitu kept reappearing because the code
-- compared C behavior-script symbols, which Lua does not have.  The fix is to
-- compare the stable behavior id `id_bhvCameraLakitu` instead.  This suite is
-- the check that row names.
--
-- Values are pinned as literals on purpose.  Reading the behavior id back from
-- the engine stub would agree with the mod whatever id the mod actually asked
-- for, which is exactly the bug.

return function(t, harness)
    local s = t.suite("lobby")

    -- id_bhvCameraLakitu, id_bhvBowserBomb and LEVEL_CASTLE_GROUNDS /
    -- LEVEL_CASTLE / LEVEL_BOB as sm64coopdx numbers them.
    local LAKITU, OTHER_BEHAVIOR = 99, 74
    local GROUNDS, INSIDE_CASTLE, COURSE = 16, 6, 9

    local function fresh(level)
        local api, ctl = harness.load()
        gNetworkPlayers[0].currLevelNum = level
        ctl.deleted = {}
        return api, ctl
    end

    local function lakitu() return { behavior_id = LAKITU } end

    -- Load time ---------------------------------------------------------------

    s.test("loading the mod turns the opening scene off", function()
        -- The harness sets skipIntro to 0 before main.lua runs, so this really
        -- observes the mod writing it.  Deleting the write leaves the
        -- Peach/Lakitu scene playing every launch, which the two hooks below
        -- then have to clean up after.
        local api = fresh(GROUNDS)
        t.ok(api ~= nil, "the mod did not load")
        t.eq(gServerSettings.skipIntro, 1, "skipIntro was not enabled at load")
    end)

    -- HOOK_ON_OBJECT_LOAD: the Lakitu that loads while StarHunt is running ----

    s.test("a camera Lakitu loading on the castle grounds is deleted", function()
        local api, ctl = fresh(GROUNDS)
        local obj = lakitu()
        api.remove_castle_lakitu(obj)
        t.eq(#ctl.deleted, 1, "the camera Lakitu was not marked for deletion")
        t.eq(ctl.deleted[1], obj, "some other object was deleted instead")
    end)

    s.test("the behavior id decides, not merely that an object loaded", function()
        -- Deleting every object that loads on the grounds would empty the lobby.
        local api, ctl = fresh(GROUNDS)
        api.remove_castle_lakitu({ behavior_id = OTHER_BEHAVIOR })
        t.eq(#ctl.deleted, 0, "an object of another behavior was deleted")
    end)

    s.test("a camera Lakitu inside the castle is left alone", function()
        local api, ctl = fresh(INSIDE_CASTLE)
        api.remove_castle_lakitu(lakitu())
        t.eq(#ctl.deleted, 0, "Lakitu was deleted away from the castle grounds")
    end)

    s.test("a camera Lakitu inside a course is left alone", function()
        local api, ctl = fresh(COURSE)
        api.remove_castle_lakitu(lakitu())
        t.eq(#ctl.deleted, 0, "Lakitu was deleted inside a course")
    end)

    -- HOOK_UPDATE: the Lakitu that was already there when StarHunt started ----

    s.test("a Lakitu already on the grounds is found by the retroactive scan", function()
        -- HOOK_ON_OBJECT_LOAD does not run for objects that loaded before the
        -- mod was enabled, which is why this second path exists at all.
        local api, ctl = fresh(GROUNDS)
        local obj = lakitu()
        ctl.objects[LAKITU] = obj
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 1, "the pre-existing camera Lakitu survived the scan")
        t.eq(ctl.deleted[1], obj, "the scan deleted some other object")
    end)

    s.test("the scan asks for the camera Lakitu specifically", function()
        local api, ctl = fresh(GROUNDS)
        ctl.objects[OTHER_BEHAVIOR] = { behavior_id = OTHER_BEHAVIOR }
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 0, "the scan deleted an object of another behavior")
    end)

    s.test("the scan does nothing away from the castle grounds", function()
        local api, ctl = fresh(INSIDE_CASTLE)
        ctl.objects[LAKITU] = lakitu()
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 0, "the scan ran inside the castle")
    end)

    s.test("the scan survives an empty castle grounds", function()
        local api, ctl = fresh(GROUNDS)
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 0, "something was deleted with no Lakitu present")
    end)

    s.test("the scan holds off for fifteen frames between passes", function()
        -- It runs under HOOK_UPDATE, so without the interval it would search
        -- the object list every frame for as long as a player stands outside.
        local api, ctl = fresh(GROUNDS)
        ctl.timer = 1000
        ctl.objects[LAKITU] = lakitu()
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 1, "the first scan did nothing")

        ctl.deleted = {}
        ctl.objects[LAKITU] = lakitu()
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 0, "a second scan on the same frame was not held off")

        ctl.timer = 1014
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 0, "the scan came back one frame early")

        ctl.timer = 1015
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 1, "the scan never came back after fifteen frames")
    end)

    s.test("time spent off the grounds does not consume the interval", function()
        -- The level is checked before the timer, so a scan is never "spent"
        -- somewhere it could not have run.
        local api, ctl = fresh(INSIDE_CASTLE)
        ctl.timer = 1000
        api.remove_existing_castle_lakitu()

        gNetworkPlayers[0].currLevelNum = GROUNDS
        ctl.objects[LAKITU] = lakitu()
        api.remove_existing_castle_lakitu()
        t.eq(#ctl.deleted, 1, "a scan away from the grounds armed the interval")
    end)

    -- HOOK_ON_FIND_WATER_LEVEL ------------------------------------------------

    s.test("the water level hook returns the height it was given", function()
        -- set_water_level() already moves the two real moat/lake regions.
        -- Returning a fixed height here would put water under every coordinate
        -- on the castle grounds, including the ground outside those boxes.
        local api = fresh(GROUNDS)
        for _, height in ipairs({ -32768, -1, 0, 260, 1234 }) do
            t.eq(api.water_level(0, 0, height), height,
                "water height " .. height .. " was rewritten")
        end
    end)
end
