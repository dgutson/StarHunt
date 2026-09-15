-- The /starhunt config menu: the option list, the selection, the values each
-- option edits, and the two ways the menu opens and closes.
--
-- The suite drives the menu the way a player does -- set the controller, call
-- the per-frame input function, read the result -- rather than calling the
-- option handlers directly, because the input function is the only caller any
-- of them has in the game.
--
-- The selection itself is read back through `api.runtime`, which is core.lua's
-- shared table. That is deliberate: the selection is REBOUND on every press, so
-- if it were still a top-level local each module would get its own copy and the
-- menu would draw one row while the input moved another. Reading it from core
-- is what proves the two sides agree.
--
-- Values are pinned as literals. Six host options and two client ones, the
-- 18/24 stick thresholds and the six language codes come from the released v1.1
-- file, not from asking the code what it currently does.

return function(t, harness)
    local s = t.suite("menu")

    -- A player sitting in the menu with no round running, which is where
    -- update_config_menu_lock leaves everyone. `server` false makes this
    -- machine a client, which has a shorter menu.
    local function menu(server)
        local api, ctl = harness.load()
        ctl.is_server = server ~= false
        for i = 0, 15 do gNetworkPlayers[i].connected = i < 2 end
        api.set_language(0)            -- the harness default is Spanish
        api.update_config_menu_lock()
        local m = gMarioStates[0]
        m.controller.buttonDown = 0
        m.controller.stickX = 0
        m.controller.stickY = 0
        return api, ctl, m
    end

    -- One button press. The menu latches on what was held last frame, so a
    -- press is a frame with the button down after a frame without it.
    local function press(api, m, button)
        m.controller.buttonDown = button
        api.menu_input(m)
        m.controller.buttonDown = 0
        api.menu_input(m)
    end

    -- One stick push and release, which is what the latch expects.
    local function push(api, m, x, y)
        m.controller.stickX = x
        m.controller.stickY = y
        api.menu_input(m)
        m.controller.stickX = 0
        m.controller.stickY = 0
        api.menu_input(m)
    end

    -- ---------------------------------------------------------------------
    -- The menu opens and closes
    -- ---------------------------------------------------------------------

    s.test("the menu is open while the lobby waits for a round", function()
        local api = menu()
        t.ok(api.is_menu_open(), "the waiting lobby had no menu")
    end)

    s.test("the round lock closes the menu on start and reopens it on the end", function()
        local api = menu()
        gGlobalSyncTable.sh5_active = 1
        api.update_config_menu_lock()
        t.ok(not api.is_menu_open(), "the menu stayed open into the round")
        gGlobalSyncTable.sh5_active = 0
        api.update_config_menu_lock()
        t.ok(api.is_menu_open(), "the menu did not come back when the round ended")
    end)

    s.test("B and Start close the menu during a round and not outside one", function()
        for _, button in ipairs({ B_BUTTON, START_BUTTON }) do
            local api, _, m = menu()
            press(api, m, button)
            t.ok(api.is_menu_open(), "the lobby menu was closed with nothing to return to")

            gGlobalSyncTable.sh5_active = 1
            press(api, m, button)
            t.ok(not api.is_menu_open(), "the menu would not close during a round")
        end
    end)

    s.test("the chat command toggles the menu during a round", function()
        local api = menu()
        gGlobalSyncTable.sh5_active = 1
        api.chat_command("")
        t.ok(not api.is_menu_open(), "/starhunt did not close an open menu")
        api.chat_command("")
        t.ok(api.is_menu_open(), "/starhunt did not reopen the menu")
    end)

    s.test("an open lobby menu cannot be toggled shut by the chat command", function()
        -- Outside a round the menu is the only thing on screen, so /starhunt
        -- must not leave the player with nothing. It shuts a third-party menu
        -- instead and leaves StarHunt's own open.
        local api = menu()
        api.toggle_menu()
        t.ok(api.is_menu_open(), "the waiting lobby was left with no menu at all")
    end)

    -- ---------------------------------------------------------------------
    -- The selection
    -- ---------------------------------------------------------------------

    s.test("the D-pad moves the selection, and core.lua is where it lives", function()
        local api, _, m = menu()
        api.runtime.config_selection = 1
        press(api, m, D_JPAD)
        t.eq(api.runtime.config_selection, 2, "down did not move the selection")
        press(api, m, U_JPAD)
        t.eq(api.runtime.config_selection, 1, "up did not move the selection back")
    end)

    s.test("the selection wraps at both ends of the host's six options", function()
        local api, _, m = menu()
        api.runtime.config_selection = 1
        press(api, m, U_JPAD)
        t.eq(api.runtime.config_selection, 6, "up from the top did not wrap to the last option")
        press(api, m, D_JPAD)
        t.eq(api.runtime.config_selection, 1, "down from the bottom did not wrap to the first")
    end)

    s.test("a client's menu is two options long", function()
        local api, _, m = menu(false)
        api.runtime.config_selection = 1
        press(api, m, U_JPAD)
        t.eq(api.runtime.config_selection, 2, "a client's menu is not two options long")
        press(api, m, D_JPAD)
        t.eq(api.runtime.config_selection, 1, "the client selection did not wrap")
    end)

    s.test("reopening clamps a selection left past the end of a shorter menu", function()
        local api, ctl, m = menu()
        api.runtime.config_selection = 6
        gGlobalSyncTable.sh5_active = 1
        press(api, m, B_BUTTON)                 -- close
        ctl.is_server = false                   -- and come back as a client
        gGlobalSyncTable.sh5_active = 0
        api.update_config_menu_lock()
        t.eq(api.runtime.config_selection, 2,
            "the selection stayed past the end of the client's menu")
    end)

    s.test("the selection is clamped when the menu opens, not when it closes", function()
        -- The clamp exists to fit the menu the player is about to see. Running
        -- it on the way out would cut the selection down against the menu being
        -- left, and a host migration can change the length between the two.
        local api, ctl, m = menu()
        api.runtime.config_selection = 6
        gGlobalSyncTable.sh5_active = 1
        ctl.is_server = false                    -- this machine loses the host role
        press(api, m, B_BUTTON)                  -- and then the menu closes
        t.eq(api.runtime.config_selection, 6,
            "the selection was cut down against the menu it was leaving")
    end)

    s.test("the stick moves the selection once per push, not once per frame", function()
        local api, _, m = menu()
        api.runtime.config_selection = 1
        m.controller.stickY = -40
        api.menu_input(m)
        api.menu_input(m)
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 2, "a held stick scrolled the menu")
    end)

    s.test("the stick unlatches only once it comes back near the centre", function()
        -- Two different thresholds: a push moves the selection past 24, and the
        -- latch is released only below 18. A stick resting between them is
        -- still latched, so easing off and pushing again does not scroll twice.
        local api, _, m = menu()
        api.runtime.config_selection = 1
        push(api, m, 0, -40)
        t.eq(api.runtime.config_selection, 2, "the first push did nothing")
        push(api, m, 0, -40)
        t.eq(api.runtime.config_selection, 3, "a released stick never unlatched")

        m.controller.stickY = -40                -- pushed: moves and latches
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 4, "a fresh push did nothing")
        m.controller.stickY = -20                -- below 24, still above 18
        api.menu_input(m)
        m.controller.stickY = -40
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 4,
            "a stick that never came back near centre was allowed to move again")
    end)

    -- ---------------------------------------------------------------------
    -- What each option edits
    -- ---------------------------------------------------------------------

    -- The language index is read back out of mod storage, which the menu
    -- writes on every change: that is also the only record that survives a
    -- restart, so a change the player cannot keep is a change that failed.
    s.test("left and right cycle the language and save it", function()
        local api, ctl, m = menu()
        api.set_language(0)
        api.runtime.config_selection = 1         -- language
        press(api, m, R_JPAD)
        t.eq(ctl.storage["starhunt_v11_language"], "1", "right did not advance the language")
        press(api, m, L_JPAD)
        t.eq(ctl.storage["starhunt_v11_language"], "0", "left did not go back")
    end)

    s.test("the language wraps around all six codes", function()
        local api, ctl, m = menu()
        api.set_language(0)
        api.runtime.config_selection = 1
        press(api, m, L_JPAD)
        t.eq(ctl.storage["starhunt_v11_language"], "5",
            "left from the first language did not wrap to the last")
        press(api, m, R_JPAD)
        t.eq(ctl.storage["starhunt_v11_language"], "0",
            "right from the last language did not wrap round")
    end)

    s.test("A on the language option advances it", function()
        local api, ctl, m = menu()
        api.set_language(0)
        api.runtime.config_selection = 1
        press(api, m, A_BUTTON)
        t.eq(ctl.storage["starhunt_v11_language"], "1", "A did not advance the language")
    end)

    s.test("the mode cycles through all four and wraps both ways", function()
        local api, _, m = menu()
        api.runtime.config_selection = 2         -- mode
        gGlobalSyncTable.sh5_mode = api.normal_mode
        local seen = {}
        for _ = 1, 4 do
            press(api, m, R_JPAD)
            seen[gGlobalSyncTable.sh5_mode] = true
        end
        for _, mode in ipairs({ api.normal_mode, api.team_mode, api.boss_mode, api.chaos_mode }) do
            t.ok(seen[mode], "mode " .. mode .. " was never reachable from the menu")
        end
        t.eq(gGlobalSyncTable.sh5_mode, api.normal_mode, "four steps did not come back round")
        press(api, m, L_JPAD)
        t.eq(gGlobalSyncTable.sh5_mode, api.chaos_mode, "left from Normal did not wrap")
    end)

    s.test("the difficulty cycles through all four and wraps both ways", function()
        local api, _, m = menu()
        api.runtime.config_selection = 3         -- difficulty
        gGlobalSyncTable.sh5_difficulty = api.easy
        press(api, m, L_JPAD)
        t.eq(gGlobalSyncTable.sh5_difficulty, api.nightmare, "left from Easy did not wrap")
        press(api, m, R_JPAD)
        t.eq(gGlobalSyncTable.sh5_difficulty, api.easy, "right did not come back")
        for _ = 1, 3 do press(api, m, R_JPAD) end
        t.eq(gGlobalSyncTable.sh5_difficulty, api.nightmare, "three steps did not reach Nightmare")
    end)

    s.test("mode, difficulty and time are locked during a round, and say so", function()
        local cases = {
            { 2, "sh5_mode" },
            { 3, "sh5_difficulty" },
            { 4, "sh5_config_minutes" },
        }
        for _, case in ipairs(cases) do
            local api, ctl, m = menu()
            gGlobalSyncTable.sh5_active = 1
            api.runtime.config_selection = case[1]
            local before = gGlobalSyncTable[case[2]]
            press(api, m, R_JPAD)
            t.eq(gGlobalSyncTable[case[2]], before,
                case[2] .. " was changed in the middle of a round")
            t.eq(#ctl.popups, 1, case[2] .. ": the refusal was not explained")
        end
    end)

    s.test("the round time is clamped to the lobby's own range", function()
        -- Two players: 11 to 20 minutes, pinned from the released file.
        local api, _, m = menu()
        api.runtime.config_selection = 4         -- time
        gGlobalSyncTable.sh5_config_minutes = 11
        press(api, m, L_JPAD)
        t.eq(gGlobalSyncTable.sh5_config_minutes, 11, "the minimum was pushed below 11")
        for _ = 1, 12 do press(api, m, R_JPAD) end
        t.eq(gGlobalSyncTable.sh5_config_minutes, 20, "the maximum was pushed past 20")
    end)

    s.test("the status option reports waiting, then the time left", function()
        local api, ctl, m = menu()
        api.runtime.config_selection = 5         -- status
        press(api, m, A_BUTTON)
        t.eq(ctl.popups[1].text, "WAITING", "a waiting lobby did not say so")

        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_end_frame = 120 * 30            -- two minutes at 30fps
        ctl.timer = 0
        press(api, m, A_BUTTON)
        t.eq(ctl.popups[2].text, "ACTIVE 2:00", "the remaining time was reported wrong")
    end)

    s.test("the last option starts a round, and stops one that is running", function()
        local api, _, m = menu()
        api.runtime.config_selection = 6
        press(api, m, A_BUTTON)
        t.eq(gGlobalSyncTable.sh5_active, 1, "the menu did not start the round")
        t.ok(not api.is_menu_open(), "the menu stayed up over the round it started")

        api.toggle_menu()
        api.runtime.config_selection = 6
        press(api, m, A_BUTTON)
        t.eq(gGlobalSyncTable.sh5_active, 0, "the menu did not stop the round")
        t.eq(gGlobalSyncTable.sh5_result_reason, "stopped by host", "wrong reason recorded")
        t.ok(api.is_menu_open(), "the menu did not come back after stopping the round")
    end)

    s.test("a client cannot change the mode or start a round", function()
        local api, _, m = menu(false)
        gGlobalSyncTable.sh5_mode = api.normal_mode
        for index = 1, 2 do
            api.runtime.config_selection = index
            press(api, m, R_JPAD)
            press(api, m, A_BUTTON)
        end
        t.eq(gGlobalSyncTable.sh5_mode, api.normal_mode, "a client changed the mode")
        t.eq(gGlobalSyncTable.sh5_active or 0, 0, "a client started a round")
    end)


    s.test("a client's two rows are the language and the status", function()
        local api, ctl, m = menu(false)
        api.set_language(0)
        api.runtime.config_selection = 1
        press(api, m, R_JPAD)
        t.eq(ctl.storage["starhunt_v11_language"], "1", "row 1 is not the language")

        api.runtime.config_selection = 2
        press(api, m, A_BUTTON)
        t.eq(#ctl.popups, 1, "row 2 did not report the status")
        t.eq(ctl.storage["starhunt_v11_language"], "1", "row 2 changed the language instead")
    end)

    s.test("the status counts seconds up to sixty, not thirty", function()
        local api, ctl, m = menu()
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_end_frame = 45 * 30      -- forty-five seconds at 30fps
        ctl.timer = 0
        api.runtime.config_selection = 5
        press(api, m, A_BUTTON)
        t.eq(ctl.popups[1].text, "ACTIVE 0:45", "the seconds were counted on the wrong base")
    end)

    s.test("a status read after the clock ran out says zero, not a negative", function()
        local api, ctl, m = menu()
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_end_frame = 0
        ctl.timer = 600                          -- twenty seconds past the end
        api.runtime.config_selection = 5
        press(api, m, A_BUTTON)
        t.eq(ctl.popups[1].text, "ACTIVE 0:00", "an expired clock reported a negative time")
    end)

    s.test("the per-frame lock does not unlatch a stick that is still pushed", function()
        -- update_config_menu_lock runs on HOOK_UPDATE and calls
        -- set_config_menu_open(true) on every frame the lobby is waiting. Only
        -- the `changed` guard stops that from resetting the menu each frame,
        -- which would let one held stick scroll the whole list.
        local api, _, m = menu()
        api.runtime.config_selection = 1
        m.controller.stickY = -40
        api.menu_input(m)                        -- moves once and latches
        t.eq(api.runtime.config_selection, 2, "the first push did nothing")

        api.update_config_menu_lock()            -- the frame the waiting lobby repeats
        m.controller.stickY = -40                -- the engine refills the stick
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 2, "the per-frame lock unlatched the stick")
    end)

    s.test("the per-frame lock does not re-pin Mario where he drifted to", function()
        local api, _, m = menu()
        m.pos.x = 100
        api.freeze_menu_mario(m)                 -- pinned at 100
        m.pos.x = 500                            -- a drift the pin has to undo
        api.update_config_menu_lock()
        t.eq(api.runtime.menu_freeze_x, 100, "the per-frame lock adopted the new position")
        api.freeze_menu_mario(m)
        t.eq(m.pos.x, 100, "Mario was left where he had drifted to")
    end)

    s.test("the button latch is cleared when the menu reopens", function()
        -- The menu zeroes the controller on its way out, so a test that holds a
        -- button has to set it again every frame, exactly as the engine does.
        local api, _, m = menu()
        gGlobalSyncTable.sh5_active = 1
        api.runtime.config_selection = 1
        m.controller.buttonDown = D_JPAD
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 2, "the first press did nothing")
        api.toggle_menu()                        -- close, with D still held
        api.toggle_menu()                        -- and reopen, still held
        m.controller.buttonDown = D_JPAD
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 3,
            "a stale latch swallowed the first press after the menu reopened")
    end)

    s.test("a button held down acts once, not once per frame", function()
        local api, _, m = menu()
        api.runtime.config_selection = 1
        for _ = 1, 3 do
            m.controller.buttonDown = D_JPAD     -- the engine refills it each frame
            api.menu_input(m)
        end
        t.eq(api.runtime.config_selection, 2, "a held button scrolled the menu")
    end)

    s.test("a stick short of the threshold does not move the selection", function()
        -- The push threshold is strictly past 24, in both directions.
        local api, _, m = menu()
        api.runtime.config_selection = 3
        m.controller.stickY = -24
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 3, "a stick at exactly 24 moved down")
        m.controller.stickY = 0
        api.menu_input(m)
        m.controller.stickY = 24
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 3, "a stick at exactly 24 moved up")
    end)

    s.test("a closed menu leaves the controller alone", function()
        local api, _, m = menu()
        gGlobalSyncTable.sh5_active = 1
        press(api, m, B_BUTTON)                  -- close it
        api.runtime.config_selection = 1
        m.controller.buttonDown = D_JPAD
        m.controller.stickX = 60
        api.menu_input(m)
        t.eq(api.runtime.config_selection, 1, "a closed menu still moved its selection")
        t.eq(m.controller.buttonDown, D_JPAD, "a closed menu took Mario's buttons")
        t.eq(m.controller.stickX, 60, "a closed menu took Mario's stick")
    end)

    s.test("changing the mode pulls the round length into the new mode's range", function()
        -- Mode 1 is Boss, which has a time table of its own: 7 to 9 minutes for
        -- two players, against 11 to 20 for a star race. Cycling into it has to
        -- re-clamp the length or the fight would start with a star race clock.
        local api, _, m = menu()
        api.runtime.config_selection = 2         -- mode
        gGlobalSyncTable.sh5_config_minutes = 99
        press(api, m, R_JPAD)
        t.eq(gGlobalSyncTable.sh5_mode, api.boss_mode, "right did not reach Boss")
        t.eq(gGlobalSyncTable.sh5_config_minutes, 9,
            "a star-race length survived the change into a Boss round")
    end)

    s.test("an out-of-range length is clamped before the round is started", function()
        local api, _, m = menu()
        api.runtime.config_selection = 6
        gGlobalSyncTable.sh5_config_minutes = 999
        press(api, m, A_BUTTON)
        t.eq(gGlobalSyncTable.sh5_end_frame - gGlobalSyncTable.sh5_start_frame,
            20 * 60 * 30, "999 minutes reached the round")
    end)

    -- ---------------------------------------------------------------------
    -- Mario while the menu is up
    -- ---------------------------------------------------------------------

    s.test("the menu takes the controller away from Mario", function()
        local api, _, m = menu()
        m.controller.buttonDown = A_BUTTON
        m.controller.stickX = 60
        m.controller.stickY = 60
        m.forwardVel = 20
        m.vel.x = 5
        api.menu_input(m)
        t.eq(m.controller.buttonDown, 0, "Mario still had the buttons")
        t.eq(m.controller.stickX, 0, "Mario still had the stick")
        t.eq(m.controller.stickY, 0, "Mario still had the stick")
        t.eq(m.forwardVel, 0, "Mario kept moving")
        t.eq(m.vel.x, 0, "Mario kept his velocity")
    end)

    s.test("a remote player's frame is left alone", function()
        local api = menu()
        local other = gMarioStates[1]
        other.controller.buttonDown = A_BUTTON
        other.forwardVel = 20
        api.menu_input(other)
        t.eq(other.controller.buttonDown, A_BUTTON, "another player lost their buttons")
        t.eq(other.forwardVel, 20, "another player was stopped by this machine's menu")
    end)

    s.test("Mario is pinned where he stood when the menu opened", function()
        local api, _, m = menu()
        m.pos.x, m.pos.y, m.pos.z = 100, 200, 300
        api.freeze_menu_mario(m)
        m.pos.x, m.pos.y, m.pos.z = 999, 999, 999
        api.freeze_menu_mario(m)
        t.eq(m.pos.x, 100, "Mario drifted in x")
        t.eq(m.pos.y, 200, "Mario drifted in y")
        t.eq(m.pos.z, 300, "Mario drifted in z")
    end)

    s.test("closing the menu forgets where Mario was pinned", function()
        local api, _, m = menu()
        m.pos.x = 100
        api.freeze_menu_mario(m)
        gGlobalSyncTable.sh5_active = 1
        press(api, m, B_BUTTON)
        api.freeze_menu_mario(m)
        t.is_nil(api.runtime.menu_freeze_x, "the old pin outlived the menu")
        m.pos.x = 500
        api.freeze_menu_mario(m)
        t.eq(m.pos.x, 500, "Mario was dragged back to where a closed menu had pinned him")
    end)

    -- ---------------------------------------------------------------------
    -- The chat command
    -- ---------------------------------------------------------------------

    s.test("/starhunt updates prints the version notes", function()
        local api, ctl = menu()
        api.chat_command("updates")
        t.ok(#ctl.chat >= 5, "the update notes were not printed")
        t.ok(ctl.chat[1]:find("v1.1", 1, true) ~= nil, "the version was not named first")
    end)

    s.test("every documented spelling of the updates argument works", function()
        for _, word in ipairs({ "updates", "update", "actualizaciones", "cambios",
                               "  UPDATES  " }) do
            local api, ctl = menu()
            api.chat_command(word)
            t.ok(ctl.chat[1]:find("v1.1", 1, true) ~= nil,
                "'" .. word .. "' did not reach the update notes")
        end
    end)

    s.test("anything else prints the two help lines", function()
        local api, ctl = menu()
        api.chat_command("nonsense")
        t.eq(#ctl.chat, 2, "the help was not two lines")
        t.ok(ctl.chat[1]:find("/starhunt", 1, true) ~= nil, "the help did not name the command")
    end)
end
