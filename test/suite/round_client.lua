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
-- The warps below arrived later and were worse: all 210 mutations of them
-- survived a green 721-test run. goal_warp and boss_warp were published in
-- STARHUNT_TEST_API and called by nothing, on_before_boss_cutscene was not
-- published at all, and the harness records a hook without ever running it --
-- so the mod could have failed to send anyone to their star, thrown a whole
-- fight's worth of Bowser attacks at a late joiner, or revived a dead player
-- with no health, and nothing here would have gone red.
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

    -- ---------------------------------------------------------------------
    -- on_before_boss_cutscene
    -- ---------------------------------------------------------------------
    --
    -- Beating Bowser normally plays the grab-the-star cinematic. StarHunt's
    -- round is already over at that point, so this cancels the cinematic and
    -- reports the win. It is a fallback: the host's own health report ends the
    -- fight first in an unmodified game, and this is what catches a Bowser
    -- whose defeat some other mod handles differently.

    local function boss_fight(setup)
        local api, ctl = harness.load(setup)
        ctl.begin_round(api, api.boss_mode, api.medium, LEVEL_BOWSER_3)
        return api, ctl
    end

    s.test("the winning player reports the victory and cancels the cinematic", function()
        local api = boss_fight()
        t.eq(api.boss_cutscene(gMarioStates[0], ACT_STAR_DANCE_EXIT, 0), 1,
            "the star cinematic was allowed to play after Bowser was beaten")
        t.eq(gPlayerSyncTable[0].sh5_boss_victory, 1, "the victory was not reported")
    end)

    s.test("every ending Bowser can use counts as the same victory", function()
        -- Which star dance the game picks depends on where Mario is standing
        -- and on which Bowser was beaten. Recognizing only one of them would
        -- leave the fight running in the other three cases.
        for _, action in ipairs({ ACT_STAR_DANCE_EXIT, ACT_STAR_DANCE_WATER,
                                  ACT_STAR_DANCE_NO_EXIT, ACT_JUMBO_STAR_CUTSCENE }) do
            local api = boss_fight()
            t.eq(api.boss_cutscene(gMarioStates[0], action, 0), 1,
                "a Bowser victory cinematic was not recognized")
            t.eq(gPlayerSyncTable[0].sh5_boss_victory, 1,
                "a Bowser victory cinematic did not report the win")
        end
    end)

    s.test("the host ends the round when it sees the victory", function()
        local api = boss_fight()
        api.boss_cutscene(gMarioStates[0], ACT_STAR_DANCE_EXIT, 0)
        t.eq(gGlobalSyncTable.sh5_active, 0, "the Boss round kept running after Bowser fell")
        t.eq(gGlobalSyncTable.sh5_result_reason, "boss defeated",
            "the round ended for the wrong reason")
        t.eq(gGlobalSyncTable.sh5_result_winner, "TEAM STARHUNT",
            "beating Bowser did not credit the players")
    end)

    s.test("a client reports the victory but does not end the round itself", function()
        -- Only the host may write the result. A client that ended its own copy
        -- of the round would show a winner nobody else has.
        local api = boss_fight(function(c) c.is_server = false end)
        t.eq(api.boss_cutscene(gMarioStates[0], ACT_STAR_DANCE_EXIT, 0), 1,
            "a client let the cinematic play")
        t.eq(gPlayerSyncTable[0].sh5_boss_victory, 1, "a client did not report its win")
        t.eq(gGlobalSyncTable.sh5_active, 1, "a client ended the round on its own")
    end)

    s.test("an ordinary action during the fight is left alone", function()
        local api = boss_fight()
        t.is_nil(api.boss_cutscene(gMarioStates[0], ACT_IDLE, 0),
            "standing still was treated as beating Bowser")
        t.eq(gPlayerSyncTable[0].sh5_boss_victory or 0, 0,
            "standing still reported a victory")
    end)

    s.test("another player's cinematic is not the local player's win", function()
        local api = boss_fight()
        t.is_nil(api.boss_cutscene(gMarioStates[1], ACT_STAR_DANCE_EXIT, 0),
            "a remote player's cinematic was cancelled locally")
        t.eq(gPlayerSyncTable[0].sh5_boss_victory or 0, 0,
            "a remote player's star dance was reported as the local win")
    end)

    s.test("a star dance in a Normal round is left alone", function()
        local api, ctl = harness.load()
        ctl.begin_round(api, 0, api.medium, LEVEL_BOB)
        t.is_nil(api.boss_cutscene(gMarioStates[0], ACT_STAR_DANCE_EXIT, 0),
            "collecting a star in a Normal round cancelled the cinematic")
        t.eq(gGlobalSyncTable.sh5_active, 1, "a Normal round ended on a star dance")
    end)

    s.test("a star dance outside a round is left alone", function()
        local api = boss_fight()
        gGlobalSyncTable.sh5_active = 0
        t.is_nil(api.boss_cutscene(gMarioStates[0], ACT_STAR_DANCE_EXIT, 0),
            "a star dance outside a round cancelled the cinematic")
        t.eq(gPlayerSyncTable[0].sh5_boss_victory or 0, 0,
            "a star dance outside a round reported a victory")
    end)

    -- ---------------------------------------------------------------------
    -- local_goal_warp_update
    -- ---------------------------------------------------------------------
    --
    -- The host writes the player's goal into sh5_goal; this is the half that
    -- notices the new number and sends that player to the star. The delay is
    -- 90 frames -- three seconds at FRAMES_PER_SECOND = 30 -- so the previous
    -- result is readable before the screen changes.

    local NEXT_GOAL_DELAY = 90

    --- An active Normal round with `goal_id` handed to the local player.
    local function goal_round(goal_id)
        local api, ctl = harness.load()
        ctl.timer = 500
        ctl.begin_round(api, 0, api.medium, LEVEL_CASTLE_GROUNDS)
        gPlayerSyncTable[0].sh5_goal = goal_id
        return api, ctl
    end

    --- The id of the first goal in `level` whose act is `act`, or nil.
    -- Searched rather than pinned: renumbering the goal pool must not quietly
    -- turn these tests into no-ops against some other star.
    local function goal_id_in(api, level, act)
        for id, goal in ipairs(api.goals) do
            if goal.level == level and goal.act == act then return id end
        end
        return nil
    end

    s.test("a new goal schedules the warp one delay ahead", function()
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.goal_id, 1, "the new goal was not picked up")
        t.eq(api.runtime.goal_warp_at, ctl.timer + NEXT_GOAL_DELAY,
            "the warp to the new star was not scheduled three seconds out")
        t.eq(#ctl.warps, 0, "the player was warped before the result could be read")
    end)

    s.test("the player is warped to the star once the delay is up", function()
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[0])
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        api.goal_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the player was never sent to the star")
        t.eq(ctl.warps[1].level, api.goals[1].level, "the player was sent to the wrong level")
        t.eq(ctl.warps[1].area, 1, "the player was sent to the wrong area")
        t.eq(ctl.warps[1].act, api.goals[1].act, "the player was sent to the wrong act")
        t.eq(api.runtime.goal_warp_at, -1, "the warp stayed pending and will fire again")
    end)

    s.test("the warp releases the death lock it was holding", function()
        -- The lock stops the death handler running twice while the player is
        -- on the way to the next star. Leaving it set outlives the warp.
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[0])
        api.runtime.death_lock = true
        api.runtime.death_warp_pending = true
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.death_lock, false, "the death lock was still held after the warp")
        t.eq(api.runtime.death_warp_pending, false,
            "the pending death warp was not consumed")
    end)

    s.test("a death sends the player back to the star with no delay", function()
        -- The three-second pause exists to let a result be read. After a death
        -- there is nothing to read, and the wait is just lost time.
        local api, ctl = goal_round(1)
        api.runtime.death_warp_pending = true
        api.goal_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "a death still cost the full next-goal delay")
        t.eq(ctl.warps[1].level, api.goals[1].level,
            "the player was sent to the wrong level")
        t.eq(api.runtime.death_warp_pending, false,
            "the pending death warp was not consumed")
    end)

    s.test("a level transition holds the warp back", function()
        -- Warping during the game's own fade can leave the player in a level
        -- that is still being torn down.
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[0])
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        ctl.transition = true
        api.goal_warp(gMarioStates[0])
        t.eq(#ctl.warps, 0, "the player was warped in the middle of a transition")
        t.eq(api.runtime.goal_warp_at, ctl.timer, "the held warp was thrown away")
    end)

    s.test("the end of the round clears the pending warp", function()
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[0])
        gGlobalSyncTable.sh5_active = 0
        api.runtime.death_lock = true
        api.runtime.death_warp_pending = true
        api.runtime.modifier_ready_key = "the last star of the round"
        api.runtime.floor_frames = 9
        api.runtime.done_lock = true
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.goal_id, 0, "the finished round's goal was still remembered")
        t.is_nil(api.runtime.modifier_ready_key,
            "a finished round's modifier was still considered ready")
        t.eq(api.runtime.floor_frames, 0, "a finished round's modifier state was kept")
        t.eq(api.runtime.done_lock, false, "a finished round's done lock was kept")
        t.eq(api.runtime.goal_warp_at, -1,
            "a warp from the finished round was still pending")
        t.eq(api.runtime.death_lock, false, "the death lock survived the round")
        t.eq(api.runtime.death_warp_pending, false,
            "a death warp from the finished round was still pending")
        t.eq(#ctl.warps, 0, "the player was sent to a star after the round ended")
    end)

    s.test("a fresh star hides the stars that are not the goal", function()
        -- star_visibility_next is the next frame the visibility sweep runs.
        -- Zeroing it makes the sweep run immediately rather than up to its
        -- whole interval later, which is when the wrong stars are on screen.
        local api, ctl = goal_round(1)
        api.runtime.star_visibility_next = ctl.timer + 999
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.star_visibility_next, 0,
            "the star visibility sweep was not rerun for the new goal")
    end)

    s.test("a new goal clears the previous star's modifier state", function()
        -- The modifier is chosen per star and its counters tick per frame.
        -- Carrying them into the next star applies half of a challenge that
        -- was audited against a different level.  Every field below starts
        -- dirty, or deleting the code that clears it changes nothing.
        local api = goal_round(1)
        api.runtime.modifier_ready_key = "the previous star"
        api.runtime.floor_frames = 9
        api.runtime.done_lock = true
        api.goal_warp(gMarioStates[0])
        t.is_nil(api.runtime.modifier_ready_key,
            "the previous star's modifier was still considered ready")
        t.eq(api.runtime.floor_frames, 0, "the previous star's modifier state was kept")
        t.eq(api.runtime.done_lock, false, "the previous star's done lock was kept")
    end)

    s.test("two cinematics in a row are counted as two", function()
        -- It is a counter and not a flag because the host may not have acted
        -- on the first frame yet. A client keeps counting until it does.
        local api = boss_fight(function(c) c.is_server = false end)
        api.boss_cutscene(gMarioStates[0], ACT_STAR_DANCE_EXIT, 0)
        api.boss_cutscene(gMarioStates[0], ACT_STAR_DANCE_EXIT, 0)
        t.eq(gPlayerSyncTable[0].sh5_boss_victory, 2,
            "the second report replaced the first instead of adding to it")
    end)

    s.test("a player the host has not given a goal to is left alone", function()
        -- sh5_goal is unset until the host assigns one, which is where a late
        -- joiner sits for a frame or two. Reading that as anything but "no
        -- goal" sends the player to a star nobody picked for them.
        local api, ctl = harness.load()
        ctl.timer = 500
        ctl.begin_round(api, 0, api.medium, LEVEL_CASTLE_GROUNDS)
        api.runtime.death_lock = true
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.goal_id, 0, "a player with no goal was given one")
        t.eq(#ctl.warps, 0, "a player with no goal was warped somewhere")
        t.eq(api.runtime.death_lock, true, "a player with no goal lost their death lock")
    end)

    s.test("a goal withdrawn mid-round cancels the warp rather than firing it", function()
        -- The host clears sh5_goal when it unenrolls a player. The warp that
        -- was already scheduled must not go off against goal zero.
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[0])
        gPlayerSyncTable[0].sh5_goal = 0
        api.goal_warp(gMarioStates[0])
        local scheduled = api.runtime.goal_warp_at
        ctl.timer = scheduled
        api.runtime.death_lock = true
        api.goal_warp(gMarioStates[0])
        t.eq(#ctl.warps, 0, "a withdrawn goal still warped the player")
        t.eq(api.runtime.goal_warp_at, scheduled,
            "a withdrawn goal's warp was consumed as though it had fired")
        t.eq(api.runtime.death_lock, true,
            "a withdrawn goal released a death lock it never used")
    end)

    s.test("a death during a transition loses the delay, not a frame more", function()
        local api, ctl = goal_round(1)
        ctl.transition = true
        api.runtime.death_warp_pending = true
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.goal_warp_at, ctl.timer,
            "the warp after a death was not scheduled for this very frame")
        t.eq(#ctl.warps, 0, "the player was warped in the middle of a transition")
    end)

    s.test("a death on the very first frame still sends the player back", function()
        -- get_global_timer() is zero when the game has just loaded, and a warp
        -- scheduled for frame zero is due, not absent.
        local api, ctl = goal_round(1)
        ctl.timer = 0
        api.runtime.death_warp_pending = true
        api.goal_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "a death on frame zero left the player where they fell")
    end)

    s.test("a player who has already been warped is not warped again", function()
        -- Nothing reschedules until the host hands out the next goal, so a
        -- spent warp has to stay spent or the player never stops arriving.
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[0])
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        api.goal_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the first warp did not fire")
        ctl.timer = ctl.timer + 1
        api.goal_warp(gMarioStates[0])
        api.goal_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the player was warped again after arriving")
    end)

    s.test("another player's update is ignored", function()
        local api, ctl = goal_round(1)
        api.goal_warp(gMarioStates[1])
        t.eq(api.runtime.goal_id, 0, "a remote player's update moved the local player")
        t.eq(#ctl.warps, 0, "a remote player's update warped the local player")
    end)

    s.test("Boss mode leaves the star warp alone", function()
        -- Boss has its own warp, into the arena. Running both sends the player
        -- to a star in the middle of the fight.
        local api, ctl = harness.load()
        ctl.timer = 500
        ctl.begin_round(api, api.boss_mode, api.medium, LEVEL_BOWSER_3)
        gPlayerSyncTable[0].sh5_goal = 1
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.goal_id, 0, "the star warp ran during a Boss round")
        t.eq(#ctl.warps, 0, "a Boss round warped the player to a star")
    end)

    s.test("Chaos mode leaves the star warp alone", function()
        -- Chaos has no star objective at all and its own warp to one course.
        local api, ctl = harness.load()
        ctl.timer = 500
        ctl.begin_round(api, api.chaos_mode, api.medium, LEVEL_BOB)
        gPlayerSyncTable[0].sh5_goal = 1
        api.goal_warp(gMarioStates[0])
        t.eq(api.runtime.goal_id, 0, "the star warp ran during a Chaos round")
        t.eq(#ctl.warps, 0, "a Chaos round warped the player to a star")
    end)

    -- Tick Tock Clock's speed is chosen at the castle clock face, which a
    -- direct warp never passes through. Whatever the last player to enter
    -- picked would otherwise decide how hard the star is.

    s.test("a red-coin star in Tick Tock Clock stops the clock", function()
        local api, ctl = harness.load()
        local red_coins = goal_id_in(api, LEVEL_TTC, 6)
        if red_coins == nil then t.fail("no red-coin star in Tick Tock Clock") return end
        ctl.timer = 500
        ctl.begin_round(api, 0, api.medium, LEVEL_CASTLE_GROUNDS)
        gPlayerSyncTable[0].sh5_goal = red_coins
        api.goal_warp(gMarioStates[0])
        t.eq(ctl.ttc_speed, TTC_SPEED_STOPPED,
            "the clock kept running during the red-coin star")
        t.eq(ctl.ttc_speed_writes, 1, "the clock speed was not set")
    end)

    s.test("any other Tick Tock Clock star runs the clock slow", function()
        local api, ctl = harness.load()
        local traversal = goal_id_in(api, LEVEL_TTC, 1)
        if traversal == nil then t.fail("no act 1 star in Tick Tock Clock") return end
        ctl.timer = 500
        ctl.begin_round(api, 0, api.medium, LEVEL_CASTLE_GROUNDS)
        ctl.ttc_speed = TTC_SPEED_STOPPED
        gPlayerSyncTable[0].sh5_goal = traversal
        api.goal_warp(gMarioStates[0])
        t.eq(ctl.ttc_speed, TTC_SPEED_SLOW,
            "a traversal star was run with the clock stopped")
        t.eq(ctl.ttc_speed_writes, 1, "the clock speed was not set")
    end)

    s.test("a clock already at the right speed is left alone", function()
        local api, ctl = harness.load()
        local traversal = goal_id_in(api, LEVEL_TTC, 1)
        if traversal == nil then t.fail("no act 1 star in Tick Tock Clock") return end
        ctl.timer = 500
        ctl.begin_round(api, 0, api.medium, LEVEL_CASTLE_GROUNDS)
        ctl.ttc_speed = TTC_SPEED_SLOW
        gPlayerSyncTable[0].sh5_goal = traversal
        api.goal_warp(gMarioStates[0])
        t.eq(ctl.ttc_speed_writes, 0, "the clock speed was rewritten needlessly")
    end)

    s.test("a star outside Tick Tock Clock does not touch the clock", function()
        local api, ctl = goal_round(1)
        t.ne(api.goals[1].level, LEVEL_TTC, "goal 1 is unexpectedly in Tick Tock Clock")
        api.goal_warp(gMarioStates[0])
        t.eq(ctl.ttc_speed_writes, 0, "a star elsewhere reset Tick Tock Clock's speed")
    end)

    s.test("the clock is left alone once the round is over", function()
        local api, ctl = harness.load()
        local red_coins = goal_id_in(api, LEVEL_TTC, 6)
        if red_coins == nil then t.fail("no red-coin star in Tick Tock Clock") return end
        ctl.timer = 500
        gGlobalSyncTable.sh5_active = 0
        gPlayerSyncTable[0].sh5_goal = red_coins
        api.goal_warp(gMarioStates[0])
        t.eq(ctl.ttc_speed_writes, 0, "the clock was set outside a round")
    end)

    -- ---------------------------------------------------------------------
    -- local_boss_warp_update
    -- ---------------------------------------------------------------------

    --- A Boss round the local player has not yet been warped into.
    local function boss_round_pending(level)
        local api, ctl = harness.load()
        ctl.timer = 500
        ctl.begin_round(api, api.boss_mode, api.medium, level or LEVEL_CASTLE_GROUNDS)
        gGlobalSyncTable.sh5_boss_level_index = 1
        return api, ctl
    end

    s.test("a new Boss round schedules the warp into the arena", function()
        local api, ctl = boss_round_pending()
        api.runtime.modifier_ready_key = "the star before the fight"
        api.runtime.floor_frames = 9
        api.runtime.done_lock = true
        api.boss_warp(gMarioStates[0])
        t.eq(api.runtime.boss_warp_at, ctl.timer + NEXT_GOAL_DELAY,
            "the warp into the arena was not scheduled three seconds out")
        t.eq(#ctl.warps, 0, "the player was thrown into the arena immediately")
        t.is_nil(api.runtime.modifier_ready_key,
            "the star before the fight was still considered ready")
        t.eq(api.runtime.floor_frames, 0, "the modifier state from before the fight was kept")
        t.eq(api.runtime.done_lock, false, "the done lock from before the fight was kept")
    end)

    s.test("the player reaches the arena once the delay is up", function()
        local api, ctl = boss_round_pending()
        api.boss_warp(gMarioStates[0])
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        api.boss_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the player never reached the arena")
        t.eq(ctl.warps[1].level, LEVEL_BOWSER_3, "the player was sent to the wrong level")
        t.eq(ctl.warps[1].area, 1, "the player was sent to the wrong area")
        t.eq(ctl.warps[1].act, 1, "the player was sent to the wrong act")
        t.eq(api.runtime.boss_warp_at, -1, "the arena warp stayed pending")
    end)

    s.test("a late joiner does not replay the attacks it missed", function()
        -- Every attack the host has ever queued is still in the queue. A
        -- player entering now must start from the current sequence number, or
        -- the whole fight's worth of hazards lands on them at once.
        local api = boss_round_pending()
        gGlobalSyncTable.sh5_boss_attack_seq = 7
        api.boss_warp(gMarioStates[0])
        t.eq(api.runtime.boss_hazard_seq, 7,
            "a player entering the arena replayed the attacks from before they arrived")
    end)

    s.test("a second Boss round warps the players in again", function()
        -- The round number is what tells a player this is a new fight. Losing
        -- it leaves everybody in the lobby for the whole of the second round.
        local api, ctl = boss_round_pending()
        api.boss_warp(gMarioStates[0])
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        api.boss_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the first Boss round did not warp the player in")
        ctl.begin_round(api, api.boss_mode, api.medium, LEVEL_CASTLE_GROUNDS)
        gGlobalSyncTable.sh5_boss_level_index = 1
        api.boss_warp(gMarioStates[0])
        t.eq(api.runtime.boss_warp_at, ctl.timer + NEXT_GOAL_DELAY,
            "the second Boss round did not schedule a warp into the arena")
    end)

    s.test("a client with no round number yet stays where it is", function()
        -- sh5_round is seeded on the host and reaches a client over the
        -- network. Reading a missing one as anything but "no round yet" warps
        -- that player in on the strength of a packet that has not arrived.
        local api, ctl = harness.load(function(c) c.is_server = false end)
        ctl.timer = 500
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_mode = api.boss_mode
        gGlobalSyncTable.sh5_boss_level_index = 1
        api.boss_warp(gMarioStates[0])
        t.eq(api.runtime.boss_warp_at, -1,
            "a client scheduled an arena warp before it knew the round number")
        t.eq(#ctl.warps, 0, "a client warped into the arena before the round reached it")
    end)

    s.test("a fight that has not attacked yet starts at sequence zero", function()
        local api = boss_round_pending()
        api.runtime.boss_hazard_seq = 5
        gGlobalSyncTable.sh5_boss_attack_seq = nil
        api.boss_warp(gMarioStates[0])
        t.eq(api.runtime.boss_hazard_seq, 0,
            "a player entering a fight with no attacks yet kept a stale sequence")
    end)

    s.test("a level transition holds the arena warp back", function()
        local api, ctl = boss_round_pending()
        api.boss_warp(gMarioStates[0])
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        ctl.transition = true
        api.boss_warp(gMarioStates[0])
        t.eq(#ctl.warps, 0, "the player was warped in the middle of a transition")
        t.eq(api.runtime.boss_warp_at, ctl.timer, "the held arena warp was thrown away")
    end)

    s.test("an unset arena leaves the player where they are", function()
        -- sh5_boss_level_index is seeded to 0 at load time and the host picks a
        -- real index when the round starts. BOSS_LEVELS has nothing at 0, and
        -- nothing at all until the host's choice reaches this player.
        for _, index in ipairs({ 0, "unset" }) do
            local api, ctl = boss_round_pending()
            gGlobalSyncTable.sh5_boss_level_index = index ~= "unset" and index or nil
            api.boss_warp(gMarioStates[0])
            ctl.timer = ctl.timer + NEXT_GOAL_DELAY
            api.boss_warp(gMarioStates[0])
            t.eq(#ctl.warps, 0, "the player was warped to a level the host never chose")
        end
    end)

    s.test("no Boss round clears the pending arena warp", function()
        local api, ctl = harness.load()
        ctl.timer = 500
        ctl.begin_round(api, 0, api.medium, LEVEL_BOB)
        api.runtime.boss_warp_at = ctl.timer
        api.boss_warp(gMarioStates[0])
        t.eq(api.runtime.boss_warp_at, -1,
            "a Normal round kept a pending warp into Bowser's arena")
        t.eq(#ctl.warps, 0, "a Normal round warped the player into the arena")
    end)

    s.test("the end of the round clears the pending arena warp", function()
        local api = boss_round_pending()
        api.boss_warp(gMarioStates[0])
        gGlobalSyncTable.sh5_active = 0
        api.boss_warp(gMarioStates[0])
        t.eq(api.runtime.boss_warp_at, -1, "a warp into the arena outlived the round")
    end)

    s.test("another player's update is ignored", function()
        local api, ctl = boss_round_pending()
        api.boss_warp(gMarioStates[1])
        t.eq(api.runtime.boss_warp_at, -1,
            "a remote player's update scheduled the local player's arena warp")
        t.eq(#ctl.warps, 0, "a remote player's update warped the local player")
    end)

    s.test("dying inside the arena puts Mario back without reloading it", function()
        -- Reloading Bowser's level can recreate him, or move who owns him,
        -- while the other players are still fighting the one that is there.
        --
        -- Every field checked below is dirtied first. Reviving Mario into a
        -- state he was already in proves nothing about the code that revives
        -- him, and only the local player's level decides which branch runs --
        -- so the other player stays outside, where a test that put everybody
        -- in the arena could not tell the two apart.
        local api, ctl = boss_round_pending(LEVEL_CASTLE_GROUNDS)
        gNetworkPlayers[0].currLevelNum = LEVEL_BOWSER_3
        api.boss_warp(gMarioStates[0])
        local m = gMarioStates[0]
        m.pos.x, m.pos.y, m.pos.z = 111, 222, 333
        m.vel.x, m.vel.y, m.vel.z = 11, 22, 33
        m.forwardVel = 40
        m.health = 0
        m.hurtCounter = 12
        m.healCounter = 7
        m.invincTimer = 0
        api.runtime.death_warp_pending = true
        api.runtime.death_lock = true
        api.runtime.floor_frames = 9
        api.runtime.done_lock = true
        api.boss_warp(m)
        t.eq(#ctl.warps, 0, "a death reloaded the arena around the other players")
        t.eq(m.pos.x, 0, "Mario was not put back over the middle of the arena")
        t.eq(m.pos.y, 1307, "Mario was not put back above the arena floor")
        t.eq(m.pos.z, 0, "Mario was not put back over the middle of the arena")
        t.eq(m.vel.x, 0, "Mario kept the sideways speed he died with")
        t.eq(m.vel.y, 0, "Mario kept the falling speed he died with")
        t.eq(m.vel.z, 0, "Mario kept the sideways speed he died with")
        t.eq(m.forwardVel, 0, "Mario kept the running speed he died with")
        t.eq(m.health, FULL_HEALTH, "Mario was revived without his health")
        t.eq(m.hurtCounter, 0, "Mario was revived still taking the damage that killed him")
        t.eq(m.healCounter, 0, "Mario was revived still healing from before he died")
        t.eq(m.invincTimer, 90, "Mario was revived with the wrong mercy invincibility")
        t.eq(#ctl.mario_actions, 1, "Mario was not dropped back into the arena")
        t.eq(ctl.mario_actions[1].action, ACT_FREEFALL,
            "Mario was revived into the wrong action")
        t.eq(ctl.mario_actions[1].arg, 0, "Mario's revival action was given an argument")
        t.eq(ctl.camera_resets, 1, "the camera was not pointed back at Mario")
        t.eq(api.runtime.death_lock, false, "the death lock survived the respawn")
        t.eq(api.runtime.death_warp_pending, false, "the respawn was left pending")
        t.eq(api.runtime.boss_warp_at, -1, "a warp was left pending after the respawn")
        t.eq(api.runtime.floor_frames, 0, "the modifier state survived the respawn")
        t.eq(api.runtime.done_lock, false, "the done lock survived the respawn")
    end)

    s.test("a player with no camera is revived without one", function()
        -- Both halves of the guard have to hold: an area whose camera has not
        -- been built yet would otherwise be reset through a nil.
        local api, ctl = boss_round_pending(LEVEL_BOWSER_3)
        api.boss_warp(gMarioStates[0])
        local m = gMarioStates[0]
        m.area.camera = nil
        api.runtime.death_warp_pending = true
        api.boss_warp(m)
        t.eq(ctl.camera_resets, 0, "a camera that does not exist was reset")
        t.eq(#ctl.mario_actions, 1, "Mario was not revived when he had no camera")
    end)

    s.test("dying outside the arena warps back in with no delay", function()
        local api, ctl = boss_round_pending(LEVEL_CASTLE_GROUNDS)
        api.boss_warp(gMarioStates[0])
        api.runtime.death_warp_pending = true
        api.runtime.death_lock = true
        api.boss_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "a player who died outside the arena was not sent back in")
        t.eq(ctl.warps[1].level, LEVEL_BOWSER_3, "the player was sent to the wrong level")
        t.eq(#ctl.mario_actions, 0,
            "a player outside the arena was respawned in place instead of warped")
        t.eq(api.runtime.death_lock, false,
            "the death lock survived the warp back into the arena")
        t.eq(api.runtime.death_warp_pending, false,
            "the warp back into the arena was left pending")
    end)

    s.test("a Boss death on the very first frame still sends the player back", function()
        -- The warp is scheduled for get_global_timer() itself, which is zero
        -- when the game has just loaded. Frame zero is due, not absent.
        local api, ctl = boss_round_pending(LEVEL_CASTLE_GROUNDS)
        api.boss_warp(gMarioStates[0])
        ctl.timer = 0
        api.runtime.death_warp_pending = true
        api.boss_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "a death on frame zero left the player outside the arena")
    end)

    s.test("a player already in the arena is not warped in again", function()
        -- A spent warp has to stay spent. Repeating it drops the player back
        -- at the entrance every frame for the rest of the fight.
        local api, ctl = boss_round_pending()
        api.boss_warp(gMarioStates[0])
        ctl.timer = ctl.timer + NEXT_GOAL_DELAY
        api.boss_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the player never reached the arena")
        ctl.timer = ctl.timer + 1
        api.boss_warp(gMarioStates[0])
        api.boss_warp(gMarioStates[0])
        t.eq(#ctl.warps, 1, "the player was warped into the arena again after arriving")
    end)
end
