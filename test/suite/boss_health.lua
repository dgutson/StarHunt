-- Bowser's health under dynamic object ownership.
--
-- Bowser is a synchronized object whose owner moves between clients. Only the
-- current owner may write his health, because a later full-object packet from
-- the owner overwrites whatever anyone else wrote -- including a fresh vanilla
-- health pool, which would silently undo the difficulty. ensure_boss_health_owner
-- is the function that enforces that, and until R-013 moved it into
-- modules/boss.lua it was published in STARHUNT_TEST_API and called by no test
-- at all: a 61-mutation sweep of it caught nothing.
--
-- Two engine functions had to become observable before any of this could be
-- tested. The generated stub returns nil from sync_object_is_owned_locally, so
-- no client ever owned anything and the whole second half of the function was
-- unreachable; and network_send_object was inert, so a publication left no
-- trace. test/harness.lua now drives the first from ctl.owned_sync_ids and
-- records the second in ctl.sent_objects.

return function(t, harness)
    local s = t.suite("boss_health")

    local BOWSER_SYNC_ID = 7

    --- A Boss round in the final arena with a Bowser the local player owns.
    -- opts.owned = false leaves the object unowned; opts.sync_id overrides the
    -- id; opts.health is Bowser's starting oHealth; opts.max is the synced
    -- health pool, which defaults to Medium's five.
    local function arena(opts)
        opts = opts or {}
        local api, ctl = harness.load(opts.setup)
        ctl.timer = 1000
        ctl.begin_round(api, api.boss_mode, opts.difficulty or api.medium, LEVEL_BOWSER_3)
        gGlobalSyncTable.sh5_boss_max_health = opts.max or 5
        local sync_id = opts.sync_id
        if sync_id == nil then sync_id = BOWSER_SYNC_ID end
        local bowser = { oSyncID = sync_id, oHealth = opts.health }
        ctl.objects[id_bhvBowser] = bowser
        if opts.owned ~= false and sync_id ~= nil and sync_id ~= 0 then
            ctl.owned_sync_ids[sync_id] = true
        end
        return api, ctl, bowser
    end

    --- Say that player `index` has already reported health for the live round.
    local function reported(index)
        gPlayerSyncTable[index].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round
    end

    -- who is allowed to write ------------------------------------------------

    s.test("the owner initializes Bowser to the full health pool", function()
        local api, ctl, bowser = arena({ health = 3 })
        api.boss_health_owner()
        t.eq(bowser.oHealth, 5, "owner did not raise Bowser to the pool")
        t.eq(#ctl.sent_objects, 1, "owner did not publish the object")
        t.eq(ctl.sent_objects[1].object, bowser, "published the wrong object")
        t.eq(ctl.sent_objects[1].reliable, true, "the initialization must be reliable")
        t.eq(gPlayerSyncTable[0].sh5_boss_health_ready_round, gGlobalSyncTable.sh5_round,
            "owner did not claim the round")
    end)

    s.test("a player who does not own Bowser writes nothing", function()
        local api, ctl, bowser = arena({ health = 3, owned = false })
        api.boss_health_owner()
        t.eq(bowser.oHealth, 3, "a non-owner changed Bowser's health")
        t.eq(#ctl.sent_objects, 0, "a non-owner published the object")
        t.is_nil(gPlayerSyncTable[0].sh5_boss_health_value, "a non-owner published health")
        t.is_nil(gPlayerSyncTable[0].sh5_boss_health_ready_round, "a non-owner claimed the round")
    end)

    s.test("a Bowser with no sync id is left alone", function()
        -- An object that has not been assigned a sync id yet is mid-spawn.
        local api, ctl, bowser = arena({ health = 3, sync_id = nil, owned = false })
        bowser.oSyncID = nil
        api.boss_health_owner()
        t.eq(bowser.oHealth, 3, "Bowser was written before he had a sync id")
        t.eq(#ctl.sent_objects, 0, "published an object with no sync id")
    end)

    s.test("a Bowser whose sync id is still zero is left alone", function()
        -- Zero is the unassigned value, and sync_object_is_owned_locally would
        -- happily answer for it.
        local api, ctl, bowser = arena({ health = 3, sync_id = 0 })
        ctl.owned_sync_ids[0] = true
        api.boss_health_owner()
        t.eq(bowser.oHealth, 3, "Bowser was written on sync id zero")
        t.eq(#ctl.sent_objects, 0, "published an object whose sync id is zero")
    end)

    s.test("with no Bowser in the arena nothing is published", function()
        local api, ctl = arena()
        ctl.objects[id_bhvBowser] = nil
        api.boss_health_owner()
        t.eq(#ctl.sent_objects, 0, "published without a Bowser")
        t.is_nil(gPlayerSyncTable[0].sh5_boss_health_value, "published health without a Bowser")
    end)

    -- when the function must not run at all -----------------------------------

    s.test("nothing is written outside an active round", function()
        local api, ctl, bowser = arena({ health = 3 })
        gGlobalSyncTable.sh5_active = 0
        api.boss_health_owner()
        t.eq(bowser.oHealth, 3, "wrote Bowser's health outside a round")
        t.eq(#ctl.sent_objects, 0, "published outside a round")
    end)

    s.test("nothing is written outside Boss mode", function()
        local api, ctl, bowser = arena({ health = 3 })
        gGlobalSyncTable.sh5_mode = api.normal_mode
        api.boss_health_owner()
        t.eq(bowser.oHealth, 3, "wrote Bowser's health in a star race")
        t.eq(#ctl.sent_objects, 0, "published in a star race")
    end)

    s.test("nothing is written away from the final arena", function()
        local api, ctl, bowser = arena({ health = 3 })
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        api.boss_health_owner()
        t.eq(bowser.oHealth, 3, "wrote Bowser's health from another level")
        t.eq(#ctl.sent_objects, 0, "published from another level")
    end)

    s.test("leaving the arena forgets that Bowser was initialized", function()
        -- Coming back has to run the initialization again, because the object
        -- may return carrying vanilla health. The round has been claimed by
        -- then, so the authoritative synced value is what Bowser is set to --
        -- not the full pool, which would undo every hit landed so far.
        local api, ctl, bowser = arena({ health = 3 })
        api.boss_health_owner()
        t.eq(#ctl.sent_objects, 1, "setup did not initialize")
        gGlobalSyncTable.sh5_boss_health = 4
        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        api.boss_health_owner()
        gNetworkPlayers[0].currLevelNum = LEVEL_BOWSER_3
        bowser.oHealth = 9
        api.boss_health_owner()
        t.eq(bowser.oHealth, 4, "returning to the arena did not re-initialize")
        t.eq(#ctl.sent_objects, 2, "returning to the arena did not publish again")
    end)

    s.test("a fresh round starts from the full pool again", function()
        -- Nobody has claimed the new round, so the previous round's remaining
        -- health must not hold Bowser down. The round has to end first: the
        -- hook runs every frame and the reset is what clears the initialized
        -- flag, so a new round that nobody left is still the old fight.
        local api, ctl, bowser = arena({ health = 3 })
        api.boss_health_owner()
        gGlobalSyncTable.sh5_boss_health = 1
        gGlobalSyncTable.sh5_active = 0
        api.boss_health_owner()
        ctl.begin_round(api, api.boss_mode, api.medium, LEVEL_BOWSER_3)
        gGlobalSyncTable.sh5_boss_max_health = 5
        bowser.oHealth = 1
        api.boss_health_owner()
        t.eq(bowser.oHealth, 5, "a fresh round did not restore the full pool")
    end)

    -- the pool itself ---------------------------------------------------------

    s.test("the synchronized pool is what Bowser is raised to", function()
        local api, _, bowser = arena({ max = 9, health = 1 })
        api.boss_health_owner()
        t.eq(bowser.oHealth, 9, "Bowser was not raised to the synchronized pool")
    end)

    s.test("with no synchronized pool the difficulty decides", function()
        -- Easy 3, Medium 5, Hard 7, Nightmare 9.
        local cases = { { "easy", 3 }, { "medium", 5 }, { "hard", 7 }, { "nightmare", 9 } }
        for _, case in ipairs(cases) do
            local api, _, bowser = arena({ health = 1 })
            gGlobalSyncTable.sh5_difficulty = api[case[1]]
            gGlobalSyncTable.sh5_boss_max_health = nil
            api.boss_health_owner()
            t.eq(bowser.oHealth, case[2], case[1] .. " gave Bowser the wrong pool")
        end
    end)

    -- never heal a fight that is already under way ----------------------------

    s.test("a round another player already claimed is never healed", function()
        -- This is the whole reason the function exists: a new owner taking
        -- over mid-fight must keep the damage already done.
        local api, _, bowser = arena({ health = 2 })
        gGlobalSyncTable.sh5_boss_health = 5
        reported(1)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 2, "a new owner healed Bowser back to the pool")
    end)

    s.test("a claimed round is also never left above the authoritative value", function()
        -- A freshly synchronized object can arrive carrying vanilla health.
        local api, _, bowser = arena({ health = 9 })
        gGlobalSyncTable.sh5_boss_health = 3
        reported(1)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 3, "vanilla health survived a claimed round")
    end)

    s.test("a claimed round with no health on the object uses the synced value", function()
        local api, _, bowser = arena({ health = nil })
        gGlobalSyncTable.sh5_boss_health = 4
        reported(1)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 4, "a Bowser with no health was not given the synced value")
    end)

    s.test("a claimed round clamps a negative health to zero", function()
        local api, _, bowser = arena({ health = -3 })
        gGlobalSyncTable.sh5_boss_health = 5
        reported(1)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 0, "a negative health was not clamped")
    end)

    s.test("a claimed round clamps the authoritative value to the pool", function()
        local api, _, bowser = arena({ health = 9, max = 5 })
        gGlobalSyncTable.sh5_boss_health = 99
        reported(1)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 5, "an out-of-range synced health was not clamped")
    end)

    s.test("a claim from the last player slot counts", function()
        -- The scan runs to MAX_PLAYERS - 1. A claim from the highest index is
        -- what proves it reaches the end of the table.
        local api, _, bowser = arena({ health = 2 })
        gGlobalSyncTable.sh5_boss_health = 5
        reported(MAX_PLAYERS - 1)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 2, "a claim from the last player slot was missed")
    end)

    s.test("a claim from the local player counts", function()
        -- And the scan starts at zero, not at one.
        local api, _, bowser = arena({ health = 2 })
        gGlobalSyncTable.sh5_boss_health = 5
        reported(0)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 2, "a claim from player zero was missed")
    end)

    s.test("a claim from a previous round does not count", function()
        local api, _, bowser = arena({ health = 2 })
        gGlobalSyncTable.sh5_boss_health = 5
        gPlayerSyncTable[1].sh5_boss_health_ready_round = gGlobalSyncTable.sh5_round - 1
        api.boss_health_owner()
        t.eq(bowser.oHealth, 5, "a stale claim held the pool down")
    end)

    -- initialization happens once ---------------------------------------------

    s.test("the same Bowser is initialized only once", function()
        local api, ctl, bowser = arena({ health = 1 })
        api.boss_health_owner()
        bowser.oHealth = 2
        api.boss_health_owner()
        t.eq(bowser.oHealth, 2, "a second pass healed Bowser")
        t.eq(#ctl.sent_objects, 1, "a second pass published the object again")
    end)

    s.test("a replacement Bowser object is initialized again", function()
        local api, ctl = arena({ health = 1 })
        api.boss_health_owner()
        gGlobalSyncTable.sh5_boss_health = 4
        local replacement = { oSyncID = BOWSER_SYNC_ID, oHealth = 9 }
        ctl.objects[id_bhvBowser] = replacement
        api.boss_health_owner()
        t.eq(replacement.oHealth, 4, "a replacement Bowser was not initialized")
        t.eq(#ctl.sent_objects, 2, "a replacement Bowser was not published")
    end)

    -- publishing the remaining health -----------------------------------------

    s.test("the owner publishes the remaining health", function()
        local api, ctl = arena({ health = 5 })
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_value, 5, "wrong published health")
        t.eq(gPlayerSyncTable[0].sh5_boss_health_tick, ctl.timer, "wrong published tick")
        t.eq(gPlayerSyncTable[0].sh5_boss_health_ready_round, gGlobalSyncTable.sh5_round,
            "the publication did not claim the round")
    end)

    s.test("a change in health is published straight away", function()
        local api, ctl, bowser = arena({ health = 5 })
        api.boss_health_owner()
        ctl.timer = ctl.timer + 1
        bowser.oHealth = 4
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_value, 4, "a hit was not published")
        t.eq(gPlayerSyncTable[0].sh5_boss_health_tick, ctl.timer, "the tick did not advance")
    end)

    s.test("an unchanged health is republished every five frames, not sooner", function()
        -- The heartbeat is what lets a new owner recover the value; sending it
        -- every frame would spend bandwidth on a number nobody changed.
        local api, ctl, bowser = arena({ health = 5 })
        api.boss_health_owner()
        local first_tick = gPlayerSyncTable[0].sh5_boss_health_tick
        ctl.timer = ctl.timer + 4
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_tick, first_tick,
            "republished before the five-frame heartbeat")
        ctl.timer = ctl.timer + 1
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_tick, first_tick + 5,
            "did not republish on the five-frame heartbeat")
        t.eq(bowser.oHealth, 5, "the heartbeat changed Bowser's health")
    end)

    s.test("the published health is clamped to the pool", function()
        local api, ctl, bowser = arena({ health = 5 })
        api.boss_health_owner()
        ctl.timer = ctl.timer + 1
        bowser.oHealth = 99
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_value, 5, "published above the pool")
        ctl.timer = ctl.timer + 1
        bowser.oHealth = -4
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_value, 0, "published below zero")
    end)

    s.test("a claimed round with no health left leaves Bowser at zero", function()
        -- Zero is a real authoritative value, not a missing one: the fight is
        -- over. Raising it to one would give Bowser a wedge back.
        local api, _, bowser = arena({ health = 3 })
        gGlobalSyncTable.sh5_boss_health = 0
        reported(1)
        api.boss_health_owner()
        t.eq(bowser.oHealth, 0, "a defeated Bowser was given health back")
    end)

    s.test("the owner claims its own slot and nobody else's", function()
        -- Every player's slot is read back by host_read_boss_health_report, so
        -- writing the wrong one reports health on behalf of someone who never
        -- owned the object.
        local api = arena({ health = 3 })
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_ready_round, gGlobalSyncTable.sh5_round,
            "the local slot was not claimed")
        for i = 1, MAX_PLAYERS - 1 do
            t.is_nil(gPlayerSyncTable[i].sh5_boss_health_ready_round,
                "player " .. i .. "'s round was claimed")
            t.is_nil(gPlayerSyncTable[i].sh5_boss_health_value,
                "player " .. i .. "'s health was published")
            t.is_nil(gPlayerSyncTable[i].sh5_boss_health_tick,
                "player " .. i .. "'s tick was published")
        end
    end)

    s.test("a replacement Bowser forgets the health last published", function()
        -- Otherwise a replacement whose health happens to match the old
        -- object's is never published, and the value sits unreported until the
        -- five-frame heartbeat comes round.
        local api, ctl = arena({ health = 5 })
        api.boss_health_owner()
        gGlobalSyncTable.sh5_boss_health = 5
        ctl.timer = ctl.timer + 2                 -- short of the heartbeat
        ctl.objects[id_bhvBowser] = { oSyncID = BOWSER_SYNC_ID, oHealth = 5 }
        api.boss_health_owner()
        t.eq(gPlayerSyncTable[0].sh5_boss_health_tick, ctl.timer,
            "a replacement Bowser did not republish the health")
    end)

    s.test("the publication follows the round number", function()
        -- A round can change under an owner who never leaves the arena, and
        -- the claim has to move with it or host_read_boss_health_report reads
        -- the slot as stale and falls back to the full pool.
        local api, ctl, bowser = arena({ health = 5 })
        api.boss_health_owner()
        local first = gGlobalSyncTable.sh5_round
        ctl.begin_round(api, api.boss_mode, api.medium, LEVEL_BOWSER_3)
        gGlobalSyncTable.sh5_boss_max_health = 5
        ctl.timer = ctl.timer + 10
        bowser.oHealth = 4
        api.boss_health_owner()
        t.ne(gGlobalSyncTable.sh5_round, first, "the fixture did not start a new round")
        t.eq(gPlayerSyncTable[0].sh5_boss_health_ready_round, gGlobalSyncTable.sh5_round,
            "the claim did not follow the round")
    end)

    -- the client's own view ----------------------------------------------------

    s.test("a client with no round number yet treats the round as zero", function()
        -- On a host the load-time block fills sh5_round in with zero, so the
        -- `or 0` default can never fire there. A client joining before the
        -- first synchronization is where it does.
        local api, ctl = harness.load(function(c) c.is_server = false end)
        ctl.timer = 1000
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_mode = api.boss_mode
        gGlobalSyncTable.sh5_boss_max_health = 5
        gGlobalSyncTable.sh5_boss_health = 5
        for i = 0, 15 do gNetworkPlayers[i].currLevelNum = LEVEL_BOWSER_3 end
        local bowser = { oSyncID = BOWSER_SYNC_ID, oHealth = 2 }
        ctl.objects[id_bhvBowser] = bowser
        ctl.owned_sync_ids[BOWSER_SYNC_ID] = true
        -- Nobody has reported, and nobody has a round number either, so every
        -- unset sh5_boss_health_ready_round reads as the same round zero and
        -- the fight counts as already under way.
        api.boss_health_owner()
        t.eq(bowser.oHealth, 2, "a client healed a fight already under way")
        t.eq(gPlayerSyncTable[0].sh5_boss_health_ready_round, 0, "wrong round claimed")
    end)
end
