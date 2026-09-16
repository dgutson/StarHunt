-- modules/goals.lua: the lifetime star count.
--
-- One number, persisted in mod storage across sessions, read once at load and
-- republished into gPlayerSyncTable[0] so every client can see it.  It is not
-- part of a round: modules/team.lua balances the Red and Blue rosters by
-- reading sh5_lifetime_stars, so a player who has collected more stars is
-- treated as the stronger player when the teams are drawn.
--
-- Nothing tested it.  update_lifetime_sync was published in STARHUNT_TEST_API
-- and called by no test at all -- the seventh time that has been true of an
-- exported function in this project -- and a mutation sweep of the block
-- confirmed it: deleting the whole body of update_lifetime_sync left all 709
-- tests passing, as did writing the total to the wrong player and letting a
-- negative stored total through the clamp.
--
-- The clamp and the floor are the reason the load is not just tonumber().
-- Storage is a plain string the game hands back, so it can be absent on a
-- first run, and nothing stops it holding something that is not a whole
-- non-negative number.

return function(t, harness)
    local s = t.suite("lifetime")

    local KEY = "starhunt_lifetime_stars"
    local BOB1 = 1            -- BOB act 1, the goal the claim test uses

    --- Load the mod with `stored` already in mod storage, as a previous
    --- session would have left it.  nil means a first run.
    local function with_stored(stored)
        return harness.load(function(ctl)
            if stored ~= nil then ctl.storage[KEY] = stored end
        end)
    end

    -- Reading the stored total ------------------------------------------------

    s.test("the stored total is read at load and published for the local player", function()
        with_stored("7")
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 7,
            "the stored lifetime total was not published at load")
    end)

    s.test("only the local player's total is written", function()
        -- The mod publishes what THIS client has collected.  Every other
        -- player's total arrives over the network, so writing to any index but
        -- 0 would overwrite a real value with the local one.
        with_stored("7")
        t.ne(gPlayerSyncTable[1].sh5_lifetime_stars, 7,
            "the local total was written into another player's sync table")
    end)

    s.test("a first run with nothing stored starts at zero", function()
        with_stored(nil)
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 0,
            "a missing stored total did not start at zero")
    end)

    s.test("a stored total that is not a number starts at zero", function()
        with_stored("not a number")
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 0,
            "an unparseable stored total did not start at zero")
    end)

    s.test("a negative stored total is clamped to zero", function()
        -- math.max(0, ...) is what does this.  Without it the total goes
        -- negative and modules/team.lua ranks the player below someone who has
        -- collected nothing.
        with_stored("-5")
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 0,
            "a negative stored total was not clamped")
    end)

    s.test("a fractional stored total is floored", function()
        with_stored("3.9")
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 3,
            "a fractional stored total was not floored to a whole star")
    end)

    -- Republishing ------------------------------------------------------------

    s.test("the sync is restored when the published value is lost", function()
        -- This is why update_lifetime_sync is on HOOK_UPDATE rather than being
        -- called once at load: a late joiner or a host migration can leave the
        -- sync table holding nothing, and the next frame has to put the real
        -- total back.
        local api = with_stored("7")
        gPlayerSyncTable[0].sh5_lifetime_stars = 0
        api.lifetime_sync()
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 7,
            "the lifetime total was not republished")
    end)

    -- Claiming a star ---------------------------------------------------------

    s.test("claiming the assigned star raises the total, saves it and republishes it", function()
        -- The three lines in on_interact are one step: without the save the
        -- star is forgotten at the next launch, and without the republish the
        -- roster balancing keeps using the stale total for the rest of the
        -- session.
        local api, ctl = with_stored("7")
        ctl.begin_round(api, api.normal_mode, api.medium)
        gPlayerSyncTable[0].sh5_goal = BOB1
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        gNetworkPlayers[0].currActNum = 1
        gNetworkPlayers[0].currAreaIndex = 1

        local star = {
            oBehParams = 0 << 24,
            oInteractType = INTERACT_STAR_OR_KEY,
            header = { gfx = { node = { flags = 0 } } },
        }
        api.interact(gMarioStates[0], star, INTERACT_STAR_OR_KEY, true)

        t.eq(ctl.storage[KEY], "8", "the raised lifetime total was not saved")
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 8,
            "the raised lifetime total was not republished")
    end)

    s.test("a star that is not the goal leaves the total alone", function()
        local api, ctl = with_stored("7")
        ctl.begin_round(api, api.normal_mode, api.medium)
        gPlayerSyncTable[0].sh5_goal = BOB1
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        gNetworkPlayers[0].currActNum = 1
        gNetworkPlayers[0].currAreaIndex = 1

        local wrong = {
            oBehParams = 1 << 24,          -- act 2, not the assigned act 1
            oInteractType = INTERACT_STAR_OR_KEY,
            header = { gfx = { node = { flags = 0 } } },
        }
        api.interact(gMarioStates[0], wrong, INTERACT_STAR_OR_KEY, true)

        t.eq(ctl.storage[KEY], "7", "the wrong star changed the saved lifetime total")
        t.eq(gPlayerSyncTable[0].sh5_lifetime_stars, 7,
            "the wrong star changed the published lifetime total")
    end)
end
