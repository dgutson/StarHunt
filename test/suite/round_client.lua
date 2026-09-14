-- The round as every client sees it: modules/round.lua.
--
-- Nothing here decides anything. The host publishes sh5_return_seq, sh5_active
-- and the rest; these functions only react to them on each player's own
-- machine. That made the whole area invisible to the suite until now -- all 26
-- mutations tried against this code survived a green 154-test run, so the mod
-- could have failed to warp anyone home at the end of a round, let a player
-- quit mid-round from the pause menu, or counted one death as two forfeits
-- without a single test noticing.
--
-- Values are pinned as literals rather than read back from the mod: the retry
-- delay below is 30 frames because FRAMES_PER_SECOND is 30, not because the
-- code says so.

return function(t, harness)
    local s = t.suite("round_client")

    -- LEVEL_* and ACT_* are installed by the engine stub at harness.load()
    -- time, so they can only be read inside a test, never at suite scope.
    local RETRY_FRAMES = 30            -- one second at FRAMES_PER_SECOND = 30
    local FULL_HEALTH = 0x880

    -- A round that has just ended: the host has published a return sequence
    -- and cleared the active flag, and the player is still out on a course.
    local function ended_round(level)
        local api, ctl = harness.load()
        gGlobalSyncTable.sh5_active = 0
        gGlobalSyncTable.sh5_mode = 0
        gGlobalSyncTable.sh5_difficulty = api.medium
        gNetworkPlayers[0].currLevelNum = level or LEVEL_BOB
        gPlayerSyncTable[0].sh5_return_seq = 1
        ctl.timer = 1000
        return api, ctl
    end

    -- ---------------------------------------------------------------------
    -- force_return_to_lobby
    -- ---------------------------------------------------------------------

    s.test("the end of a round warps the local player back to the castle", function()
        local api, ctl = ended_round()
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the player was not sent home when the round ended")
        t.eq(ctl.warps[1].level, LEVEL_CASTLE_GROUNDS,
            "the player was sent somewhere other than the lobby")
    end)

    s.test("the host's own return sequence also sends players home", function()
        -- The order arrives in either table; a client that reads only one of
        -- them strands everybody whose per-player copy was the one written.
        local api, ctl = ended_round()
        gPlayerSyncTable[0].sh5_return_seq = 0
        gGlobalSyncTable.sh5_return_seq = 1
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "a global return order did not send the player home")
    end)

    s.test("only the local player is warped", function()
        local api, ctl = ended_round()
        api.return_to_lobby(gMarioStates[1])
        t.eq(#ctl.warps, 0, "a remote player's Mario triggered a local warp")
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the local player was not warped")
    end)

    s.test("a return order left over from an earlier round is consumed, not acted on", function()
        -- A player who joins late can still be holding the previous round's
        -- order. Acting on it would warp them out of the round they just
        -- joined.
        local api, ctl = ended_round()
        gGlobalSyncTable.sh5_active = 1
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 0, "a stale return order warped a player out of a live round")

        gGlobalSyncTable.sh5_active = 0
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 0, "the stale order was not consumed and fired after the round")
    end)

    s.test("a return sequence of zero is not an order to go home", function()
        local api, ctl = ended_round()
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the first order did not warp")

        -- The host clearing the field back to zero must not read as a new order.
        gPlayerSyncTable[0].sh5_return_seq = 0
        gGlobalSyncTable.sh5_return_seq = 0
        ctl.timer = ctl.timer + RETRY_FRAMES
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "clearing the return sequence warped the player again")
    end)

    s.test("the warp waits for the level transition to finish", function()
        local api, ctl = ended_round()
        ctl.transition = true
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 0, "a warp was issued while a transition was playing")

        ctl.transition = false
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the warp was not retried once the transition ended")
    end)

    s.test("a warp that does not take is retried once a second, not every frame", function()
        local api, ctl = ended_round()
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1)

        -- Still on the course: the warp did not take.
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the warp was retried on the very next frame")

        ctl.timer = ctl.timer + RETRY_FRAMES - 1
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the warp was retried before a full second had passed")

        ctl.timer = ctl.timer + 1
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 2, "the warp was never retried")
    end)

    s.test("arriving on the castle grounds stops the warping", function()
        local api, ctl = ended_round(LEVEL_CASTLE_GROUNDS)
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 0, "a player already in the lobby was warped to it")

        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        ctl.timer = ctl.timer + RETRY_FRAMES
        api.return_to_lobby(gMarioStates[0])
        t.eq(#ctl.warps, 0, "the order was not cleared on arrival and fired later")
    end)

    s.test("the client clears its pending StarHunt stars before it warps", function()
        -- Every client owns its own save file. If the flags are still pending
        -- when the warp or an F12 exit happens, vanilla saves the star the
        -- player only collected for StarHunt.
        local api, ctl = ended_round()
        api.remove_save_flag(api.goals[1])
        local written = #ctl.save.removed

        api.return_to_lobby(gMarioStates[0])
        t.ok(#ctl.save.removed > written,
            "the pending star flags were not cleared when the round ended")
    end)

    -- ---------------------------------------------------------------------
    -- on_nametags_render and update_private_player_visibility
    -- ---------------------------------------------------------------------

    -- Two players in a live Normal round, hunting stars in different areas of
    -- the world, which is what makes their variants private.
    local function private_pair(same_area)
        local api, ctl = harness.load()
        ctl.begin_round(api, 0, api.medium, LEVEL_BOB)
        gPlayerSyncTable[0].sh5_goal = 1
        gPlayerSyncTable[1].sh5_goal = 2
        gNetworkPlayers[0].currAreaIndex = 1
        gNetworkPlayers[1].currAreaIndex = same_area and 1 or 2
        return api, ctl
    end

    local function give_object(index, invisible)
        local flags = invisible and GRAPH_RENDER_INVISIBLE or 0
        local object = { header = { gfx = { node = { flags = flags } } } }
        gMarioStates[index].marioObj = object
        return object
    end

    local function is_invisible(object)
        return (object.header.gfx.node.flags & GRAPH_RENDER_INVISIBLE) ~= 0
    end

    s.test("a player hunting a private variant loses their nametag", function()
        local api = private_pair(false)
        local hidden = api.nametags_render(1, { x = 1, y = 2 })
        t.ok(hidden ~= nil, "a private player's nametag was drawn")
        t.eq(hidden.name, "", "the nametag was not blanked")
    end)

    s.test("a player in the same place keeps their nametag", function()
        local api = private_pair(true)
        t.is_nil(api.nametags_render(1, { x = 1, y = 2 }),
            "a player standing in the same area was hidden from the nametag pass")
    end)

    s.test("the local player's own nametag is never blanked", function()
        -- This one pins the contract rather than guarding the code that meets
        -- it. Deleting the `index ~= 0` check does not change the answer:
        -- players_have_private_variant compares its two players symmetrically,
        -- so asked about player 0 twice it returns false down every branch.
        -- The check is there so the intent survives a change to that function.
        local api = private_pair(false)
        t.is_nil(api.nametags_render(0, { x = 1, y = 2 }),
            "the local player blanked their own nametag")
    end)

    s.test("nametags come back when no round is running", function()
        local api = private_pair(false)
        gGlobalSyncTable.sh5_active = 0
        t.is_nil(api.nametags_render(1, { x = 1, y = 2 }),
            "a nametag was still hidden after the round ended")
    end)

    s.test("a player hunting a private variant is hidden and shown again", function()
        local api = private_pair(false)
        local object = give_object(1, false)

        api.private_player_visibility()
        t.ok(is_invisible(object), "a private player stayed visible")

        gNetworkPlayers[1].currAreaIndex = 1     -- they met
        api.private_player_visibility()
        t.ok(not is_invisible(object), "the player was not made visible again")
    end)

    s.test("players sharing the world are never hidden", function()
        local api = private_pair(true)
        local object = give_object(1, false)
        api.private_player_visibility()
        t.ok(not is_invisible(object), "a player standing in the same area was hidden")
    end)

    s.test("a player who was already invisible stays invisible", function()
        -- Another mod, or vanilla, may have hidden this player for its own
        -- reasons. Restoring it to visible would override that mod silently.
        local api = private_pair(false)
        local object = give_object(1, true)

        api.private_player_visibility()
        t.ok(is_invisible(object), "the player should still be invisible")

        gNetworkPlayers[1].currAreaIndex = 1
        api.private_player_visibility()
        t.ok(is_invisible(object), "a player who started invisible was revealed")
    end)

    s.test("a respawned player object is tracked from scratch", function()
        -- marioObj is replaced when a player respawns or changes area. The
        -- record of what the OLD object looked like says nothing about the new
        -- one, so keeping it reveals a player who was invisible all along.
        local api = private_pair(false)
        give_object(1, false)
        api.private_player_visibility()

        local replacement = give_object(1, true)
        api.private_player_visibility()
        t.ok(is_invisible(replacement), "the replacement object was not hidden")

        gNetworkPlayers[1].currAreaIndex = 1
        api.private_player_visibility()
        t.ok(is_invisible(replacement),
            "the stale record from the previous object revealed the new one")
    end)

    s.test("a disconnected player is dropped from the hidden list", function()
        local api = private_pair(false)
        give_object(1, false)
        api.private_player_visibility()
        t.ok(api.runtime.hidden_players[1] ~= nil, "the hidden player was not tracked")

        gNetworkPlayers[1].connected = false
        gMarioStates[1].marioObj = nil
        api.private_player_visibility()
        t.is_nil(api.runtime.hidden_players[1], "a disconnected player stayed on the list")
    end)

    -- ---------------------------------------------------------------------
    -- on_pause_exit
    -- ---------------------------------------------------------------------

    s.test("quitting from the pause menu is refused during a round", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, 0, api.medium, LEVEL_BOB)
        t.eq(api.pause_exit(gMarioStates[0]), false, "a player quit mid-round")
        t.ok(#ctl.popups > 0, "nothing told the player why quitting was refused")
    end)

    s.test("quitting is allowed once the round is over", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, 0, api.medium, LEVEL_BOB)
        gGlobalSyncTable.sh5_active = 0
        t.eq(api.pause_exit(gMarioStates[0]), true, "quitting stayed blocked after the round")
    end)

    -- ---------------------------------------------------------------------
    -- on_death
    -- ---------------------------------------------------------------------

    local function in_round(mode)
        local api, ctl = harness.load()
        ctl.begin_round(api, mode, api.medium, LEVEL_BOB)
        gPlayerSyncTable[0].sh5_goal = 1
        gPlayerSyncTable[0].sh5_forfeit = 0
        gMarioStates[0].numLives = 4
        gMarioStates[0].health = 1
        return api, ctl
    end

    s.test("a death in a Normal round is cancelled and costs one forfeit", function()
        local api = in_round(0)
        local m = gMarioStates[0]
        t.eq(api.death(m), false, "vanilla's death sequence was allowed to play")
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 1, "the death did not cost a forfeit")
        t.eq(m.health, FULL_HEALTH, "health was not restored, so the death can fire again")
        t.eq(m.invincTimer, 90, "the player was not made briefly invincible")
        t.ok(api.runtime.death_warp_pending, "no replacement warp was queued")
    end)

    s.test("dying tops the player's lives back up", function()
        -- StarHunt hands out a new goal instead of a game over, so the life
        -- count must not run down across a round.
        local api = in_round(0)
        api.death(gMarioStates[0])
        t.eq(gMarioStates[0].numLives, 99, "the player's lives were not topped up")
    end)

    s.test("a second death before the new goal arrives costs nothing more", function()
        local api = in_round(0)
        api.death(gMarioStates[0])
        api.death(gMarioStates[0])
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 1, "one death was counted twice")
    end)

    s.test("a player who already finished their goal does not forfeit on death", function()
        local api = in_round(0)
        api.runtime.done_lock = true
        t.eq(api.death(gMarioStates[0]), false)
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 0,
            "a player who had already collected their star was charged a forfeit")
    end)

    s.test("death outside a round is left to vanilla", function()
        local api = in_round(0)
        gGlobalSyncTable.sh5_active = 0
        t.eq(api.death(gMarioStates[0]), true, "StarHunt cancelled a death outside a round")
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 0, "a forfeit was charged outside a round")
    end)

    s.test("Boss mode sends the player back to the fight instead of forfeiting", function()
        local api, ctl = in_round(0)
        gGlobalSyncTable.sh5_mode = api.boss_mode
        t.eq(api.death(gMarioStates[0]), false, "vanilla's death sequence played in Boss mode")
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 0, "a Boss death was charged as a forfeit")
        t.ok(api.runtime.death_warp_pending, "the player was not sent back to the arena")
        t.eq(#ctl.popups, 1, "the player was not told they were going back")

        -- Already knocked out: the return must not be re-armed every frame.
        ctl.timer = ctl.timer + 100
        local armed_at = api.runtime.boss_warp_at
        api.death(gMarioStates[0])
        t.eq(#ctl.popups, 1, "a second popup fired for the same death")
        t.eq(api.runtime.boss_warp_at, armed_at, "the return warp was re-armed mid-fall")
    end)

    s.test("a Chaos death eliminates the player exactly once", function()
        local api, ctl = in_round(0)
        gGlobalSyncTable.sh5_mode = api.chaos_mode
        t.eq(api.death(gMarioStates[0]), false, "vanilla's death sequence played in Chaos")
        t.eq(gPlayerSyncTable[0].sh5_chaos_eliminated, 1, "the player was not eliminated")
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 0, "a Chaos death was charged as a forfeit")
        t.eq(#ctl.popups, 1, "the player was not told they were out")

        -- A spectator who dies again must not be dragged back to the arena.
        api.runtime.chaos_spectator_warped = true
        api.death(gMarioStates[0])
        t.eq(#ctl.popups, 1, "an eliminated player was eliminated a second time")
        t.ok(api.runtime.chaos_spectator_warped,
            "a second death warped an eliminated player back into the arena")
    end)

    -- ---------------------------------------------------------------------
    -- on_before_death_action
    -- ---------------------------------------------------------------------

    s.test("a drowning is intercepted before vanilla animates it", function()
        local api = in_round(0)
        t.eq(api.before_death_action(gMarioStates[0], ACT_DROWNING, 0), 1,
            "the drowning animation was allowed to start")
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 1, "the intercepted death cost no forfeit")
    end)

    s.test("an ordinary action is not intercepted", function()
        local api = in_round(0)
        t.is_nil(api.before_death_action(gMarioStates[0], ACT_IDLE, 0),
            "standing still was treated as a death")
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 0, "standing still cost a forfeit")
    end)

    s.test("death actions are left alone when no round is running", function()
        local api = in_round(0)
        gGlobalSyncTable.sh5_active = 0
        t.is_nil(api.before_death_action(gMarioStates[0], ACT_DROWNING, 0),
            "a drowning outside a round was intercepted")
        t.eq(gPlayerSyncTable[0].sh5_forfeit, 0, "a forfeit was charged outside a round")
    end)

    -- ---------------------------------------------------------------------
    -- on_dialog
    -- ---------------------------------------------------------------------

    local function boss_round_at(level)
        local api, ctl = harness.load()
        ctl.begin_round(api, api.boss_mode, api.medium, level)
        return api
    end

    s.test("Bowser's intro textbox is cancelled during a Boss round", function()
        -- It blocks Mario while StarHunt's shared timer is already running.
        local api = boss_round_at(LEVEL_BOWSER_3)
        t.eq(api.dialog(DIALOG_093), false, "the Bowser 3 intro dialog was allowed to open")
    end)

    s.test("every other dialog in the fight is left alone", function()
        local api = boss_round_at(LEVEL_BOWSER_3)
        t.eq(api.dialog(DIALOG_093 + 1), true, "an unrelated dialog was cancelled")
    end)

    s.test("the same dialog elsewhere is left alone", function()
        local api = boss_round_at(LEVEL_BOB)
        t.eq(api.dialog(DIALOG_093), true,
            "a dialog was cancelled outside Bowser's level")
    end)

    s.test("dialogs are left alone outside a Boss round", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, 0, api.medium, LEVEL_BOWSER_3)
        t.eq(api.dialog(DIALOG_093), true, "a Normal round cancelled Bowser's dialog")
    end)
end
