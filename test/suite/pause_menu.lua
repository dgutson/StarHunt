-- The list the mod puts on the game's own pause screen during a round.
--
-- Two guarantees are worth more than the rest and are tested first: outside a
-- round the mod must not touch that screen at all, because EXIT COURSE and EXIT
-- TO CASTLE are the only way to leave a course; and while the mod does own it,
-- the flag must come back off the moment the round ends or the player resumes,
-- because the game draws nothing at all while it is set -- no rows, no dim, and
-- no reading of A and START. A pause left hidden with nobody drawing it is a
-- game the player cannot leave.
--
-- The suite drives it the way a player does: set the controller, call the
-- per-frame function, read the result. Labels are pinned in English, which is
-- what set_language(0) selects; the harness default is Spanish.

return function(t, harness)
    local s = t.suite("pause_menu")

    -- A player paused inside a round, on a goal, with the reroll ready.
    local function paused_round()
        local api, ctl = harness.load()
        api.set_language(0)
        local sync = gPlayerSyncTable[0]
        sync.sh5_goal = 1
        sync.sh5_manual_reroll_request = 0
        sync.sh5_manual_reroll_ack = 0
        sync.sh5_manual_reroll_ready_frame = ctl.timer
        ctl.begin_round(api, api.normal_mode, api.medium, api.goals[1].level)
        ctl.paused = true
        api.update_pause_menu()
        return api, ctl
    end

    -- One button press: a frame with the button reported as pressed. This is
    -- the engine's own edge, not a held state, so one frame is one press.
    local function press(api, button)
        gMarioStates[0].controller.buttonPressed = button
        api.update_pause_menu()
        gMarioStates[0].controller.buttonPressed = 0
    end

    -- One frame of the stick at `y`, left where it is. Releasing is a hold at
    -- a smaller value, because that is what a real stick does.
    local function hold(api, y)
        gMarioStates[0].controller.stickY = y
        api.update_pause_menu()
    end

    -- -----------------------------------------------------------------------
    -- When the mod owns the screen, and when it must not
    -- -----------------------------------------------------------------------

    s.test("with no round the game keeps its own pause list", function()
        local api, ctl = harness.load()
        ctl.paused = true
        api.update_pause_menu()
        t.ok(not ctl.pause_menu_hidden,
            "the mod hid EXIT COURSE outside a round")
        t.ok(not api.pause_menu_active(), "the mod claimed a pause it does not own")
    end)

    s.test("with no round the buttons on that screen are not the mod's", function()
        local api, ctl = harness.load()
        ctl.paused = true
        api.update_pause_menu()
        press(api, A_BUTTON)
        t.eq(ctl.unpauses, 0, "the mod took a row on a screen it does not own")
    end)

    s.test("a game missing any of the three pause calls keeps its own list",
        function()
            -- A build without them gets no Lua error and no replacement, the
            -- way the cross-act request does nothing where the field is absent.
            for _, missing in ipairs({ "set_pause_menu_hidden", "game_unpause",
                                       "is_game_paused" }) do
                local api, ctl = harness.load(function() _G[missing] = nil end)
                gPlayerSyncTable[0].sh5_goal = 1
                ctl.begin_round(api, api.normal_mode, api.medium, api.goals[1].level)
                ctl.paused = true
                api.update_pause_menu()
                press(api, A_BUTTON)
                t.ok(not ctl.pause_menu_hidden,
                    "a game with no " .. missing .. " lost its own pause list")
                t.ok(not api.pause_menu_active(),
                    "the mod claimed a pause it cannot run without " .. missing)
            end
        end)

    s.test("a pause during a round is the mod's", function()
        local api, ctl = paused_round()
        t.ok(ctl.pause_menu_hidden, "the game's own rows were left on screen")
        t.ok(api.pause_menu_active(), "the mod did not take the pause")
    end)

    s.test("resuming gives the game its pause screen back", function()
        local api, ctl = paused_round()
        ctl.paused = false
        api.update_pause_menu()
        t.ok(not ctl.pause_menu_hidden, "the pause screen stayed hidden after the pause")
    end)

    s.test("a round ending mid-pause gives the pause screen back", function()
        local api, ctl = paused_round()
        gGlobalSyncTable.sh5_active = 0
        api.update_pause_menu()
        t.ok(not ctl.pause_menu_hidden,
            "the player was left on a pause screen nothing draws")
    end)

    -- -----------------------------------------------------------------------
    -- The rows
    -- -----------------------------------------------------------------------

    s.test("the rows are continue and another level with its countdown", function()
        local api = paused_round()
        local labels = api.pause_menu_labels()
        t.eq(#labels, 2, "the pause list had the wrong number of rows")
        t.eq(labels[1], "CONTINUE", "the first row was not CONTINUE")
        t.eq(labels[2], "ANOTHER LEVEL - READY", "the second row was not the reroll")
    end)

    s.test("the countdown on the row is the one the cooldown has left", function()
        local api, ctl = paused_round()
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame = ctl.timer + 20 * 30
        t.eq(api.pause_menu_labels()[2], "ANOTHER LEVEL - 0:20",
            "the row did not carry the remaining cooldown")
        -- The cooldown is two minutes, so most of it is read across a minute.
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame = ctl.timer + 90 * 30
        t.eq(api.pause_menu_labels()[2], "ANOTHER LEVEL - 1:30",
            "the row did not carry minutes and seconds apart")
        -- What the row reads the moment a goal is assigned.
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame =
            ctl.timer + api.manual_reroll_cooldown
        t.eq(api.pause_menu_labels()[2], "ANOTHER LEVEL - 2:00",
            "a full cooldown did not read as two minutes")
    end)

    s.test("outside Normal and Team the row says where it works", function()
        local api = paused_round()
        gGlobalSyncTable.sh5_mode = api.boss_mode
        t.eq(api.pause_menu_labels()[2], "ANOTHER LEVEL - NORMAL/TEAM ONLY",
            "the row promised a reroll Boss mode does not have")
    end)

    -- -----------------------------------------------------------------------
    -- What reaches the screen
    -- -----------------------------------------------------------------------

    s.test("both rows are drawn while the mod owns the pause", function()
        local api, ctl = paused_round()
        ctl.hud.text = {}
        api.draw_hud()
        local seen = {}
        for _, call in ipairs(ctl.hud.text) do seen[call.text] = true end
        t.ok(seen["CONTINUE"], "CONTINUE was never drawn")
        t.ok(seen["ANOTHER LEVEL - READY"], "the reroll row was never drawn")
    end)

    s.test("the rows are gone the frame the pause ends", function()
        local api, ctl = paused_round()
        ctl.paused = false
        api.update_pause_menu()
        ctl.hud.text = {}
        api.draw_hud()
        for _, call in ipairs(ctl.hud.text) do
            t.ok(call.text ~= "CONTINUE", "the pause list was drawn over the game")
        end
    end)

    -- Everything below is pinned as a literal, the way test/suite/hud_panels.lua
    -- pins the other panels: the harness screen is 1920 x 1009, so the rows sit
    -- at floor(1009 * 0.56) = 565 and 26 below it, and the highlight behind the
    -- selected row spans the middle half, 480 to 1440.
    local function colour_layer(ctl)
        local out = {}
        for _, call in ipairs(ctl.hud.text) do
            if call.a == 255 then out[#out + 1] = call end
        end
        return out
    end

    local function row_named(ctl, text)
        for _, call in ipairs(colour_layer(ctl)) do
            if call.text == text then return call end
        end
        t.fail("the row '" .. text .. "' was never drawn")
        return {}
    end

    -- The selected row is the mod's yellow accent and every other row is white.
    local function accent_is(ctl, text, selected)
        local call = row_named(ctl, text)
        t.eq(call.r .. "," .. call.g .. "," .. call.b,
            selected and "255,215,73" or "255,255,255",
            "'" .. text .. "' was drawn in the wrong colour for its state")
    end

    s.test("the list dims the whole screen and sits where the game's rows do",
        function()
            local api, ctl = paused_round()
            ctl.hud.text = {}
            ctl.hud.rect_calls = {}
            api.draw_hud()

            local dim
            for _, rect in ipairs(ctl.hud.rect_calls) do
                if rect.x == 0 and rect.y == 0 and rect.w == 1920 and rect.h == 1009
                    and rect.a == 150 then
                    dim = rect
                end
            end
            t.ok(dim ~= nil, "nothing dimmed the screen behind the rows")
            dim = dim or {}
            t.eq(dim.r, 0, "the dim was not black")
            t.eq(dim.g, 0, "the dim was not black")
            t.eq(dim.b, 0, "the dim was not black")

            t.eq(row_named(ctl, "CONTINUE").y, 565, "CONTINUE was not where the game's rows are")
            t.eq(row_named(ctl, "ANOTHER LEVEL - READY").y, 591,
                "the second row was not one row below the first")
            t.eq(row_named(ctl, "CONTINUE").scale, 0.72, "the rows changed size")
        end)

    s.test("the highlight and the colour follow the cursor", function()
        local api, ctl = paused_round()
        ctl.hud.text = {}
        ctl.hud.rect_calls = {}
        api.draw_hud()

        local function highlight()
            local found
            for _, rect in ipairs(ctl.hud.rect_calls) do
                if rect.a == 45 then found = rect end
            end
            return found
        end
        local marked = highlight()
        t.ok(marked ~= nil, "the selected row had no highlight")
        marked = marked or {}
        t.eq(marked.x, 480, "the highlight did not start mid-left")
        t.eq(marked.w, 960, "the highlight was not half the screen")
        t.eq(marked.y, 561, "the highlight was not behind CONTINUE")
        t.eq(marked.h, 22, "the highlight was not a row high")
        t.eq(marked.r .. "," .. marked.g .. "," .. marked.b, "255,255,255",
            "the highlight was not white")
        accent_is(ctl, "CONTINUE", true)
        accent_is(ctl, "ANOTHER LEVEL - READY", false)

        press(api, D_JPAD)
        ctl.hud.text = {}
        ctl.hud.rect_calls = {}
        api.draw_hud()
        t.eq(highlight().y, 587, "the highlight did not follow the cursor down")
        accent_is(ctl, "CONTINUE", false)
        accent_is(ctl, "ANOTHER LEVEL - READY", true)
    end)

    s.test("the countdown row keeps its colon out of the HUD font", function()
        -- FONT_HUD draws ':' as an 'X', so "ANOTHER LEVEL - 0:20" has to go
        -- through draw_hud_text like every other line on this HUD.
        local api, ctl = paused_round()
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame = ctl.timer + 20 * 30
        ctl.hud.text = {}
        api.draw_hud()
        for _, call in ipairs(ctl.hud.text) do
            t.ok(not tostring(call.text):find(":", 1, true),
                "a colon reached the HUD font: " .. tostring(call.text))
        end
    end)

    -- -----------------------------------------------------------------------
    -- The cursor
    -- -----------------------------------------------------------------------

    s.test("the cursor starts on continue every time the pause opens", function()
        local api, ctl = paused_round()
        press(api, D_JPAD)
        t.eq(api.pause_selection(), 2, "the cursor did not move")
        ctl.paused = false
        api.update_pause_menu()
        ctl.paused = true
        api.update_pause_menu()
        t.eq(api.pause_selection(), 1, "the cursor kept its place across a pause")
    end)

    s.test("down moves to the reroll and wraps back to continue", function()
        local api = paused_round()
        press(api, D_JPAD)
        t.eq(api.pause_selection(), 2, "down did not reach the reroll")
        press(api, D_JPAD)
        t.eq(api.pause_selection(), 1, "down did not wrap to the top")
    end)

    s.test("up wraps from continue to the reroll and back", function()
        local api = paused_round()
        press(api, U_JPAD)
        t.eq(api.pause_selection(), 2, "up did not wrap to the bottom")
        press(api, U_JPAD)
        t.eq(api.pause_selection(), 1, "up did not come back to the top")
    end)

    s.test("the stick moves the cursor only once it is past 24", function()
        local api = paused_round()
        hold(api, 24)
        t.eq(api.pause_selection(), 1, "a push exactly at the threshold moved the cursor")
        hold(api, -24)
        t.eq(api.pause_selection(), 1, "a pull exactly at the threshold moved the cursor")
        hold(api, 25)
        t.eq(api.pause_selection(), 2, "a push past the threshold moved nothing")
    end)

    s.test("a held stick moves one row and waits for a release under 18", function()
        local api = paused_round()
        hold(api, -25)
        t.eq(api.pause_selection(), 2, "the first push moved nothing")
        hold(api, -25)
        t.eq(api.pause_selection(), 2, "a held stick scrolled a second row")
        hold(api, -18)
        hold(api, -25)
        t.eq(api.pause_selection(), 2, "the stick re-armed without falling under 18")
        hold(api, -17)
        hold(api, -25)
        t.eq(api.pause_selection(), 1, "the stick never moved again after its release")
    end)

    s.test("a stick still held when the pause reopens moves the cursor again",
        function()
            local api, ctl = paused_round()
            hold(api, -25)
            t.eq(api.pause_selection(), 2, "the first push moved nothing")
            ctl.paused = false
            api.update_pause_menu()
            ctl.paused = true
            api.update_pause_menu()
            hold(api, -25)
            t.eq(api.pause_selection(), 2,
                "the cursor was stuck because the stick was never released")
        end)

    -- -----------------------------------------------------------------------
    -- Taking a row
    -- -----------------------------------------------------------------------

    s.test("continue ends the pause and asks for nothing", function()
        local api, ctl = paused_round()
        press(api, A_BUTTON)
        t.eq(ctl.unpauses, 1, "CONTINUE did not end the pause")
        t.ok(not ctl.paused, "the game stayed paused")
        t.eq(gPlayerSyncTable[0].sh5_manual_reroll_request, 0,
            "CONTINUE asked the host for a new level")
    end)

    s.test("the reroll row asks the host and ends the pause", function()
        local api, ctl = paused_round()
        press(api, D_JPAD)
        press(api, A_BUTTON)
        t.eq(gPlayerSyncTable[0].sh5_manual_reroll_request, 1,
            "the host was never asked for a new level")
        t.eq(ctl.unpauses, 1, "the pause outlived the request")
    end)

    s.test("START takes a row the way A does", function()
        local api, ctl = paused_round()
        press(api, START_BUTTON)
        t.eq(ctl.unpauses, 1, "START did not take the row under the cursor")
    end)

    s.test("a reroll still on cooldown leaves the pause open", function()
        local api, ctl = paused_round()
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame = ctl.timer + 20 * 30
        press(api, D_JPAD)
        press(api, A_BUTTON)
        t.eq(gPlayerSyncTable[0].sh5_manual_reroll_request, 0,
            "a reroll on cooldown reached the host")
        t.eq(ctl.unpauses, 0, "the pause closed over a refused row")
        t.ok(ctl.paused, "the player was returned to the game with nothing done")
        local last = ctl.popups[#ctl.popups]
        t.eq(last ~= nil and last.text or "", "ANOTHER LEVEL AVAILABLE IN 0:20",
            "the popup did not say how long is left")
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame = ctl.timer + 90 * 30
        press(api, A_BUTTON)
        last = ctl.popups[#ctl.popups]
        t.eq(last ~= nil and last.text or "", "ANOTHER LEVEL AVAILABLE IN 1:30",
            "the popup did not split minutes from seconds")
    end)

    s.test("the first ask of a round works with nothing recorded yet", function()
        -- A player who has never asked carries no request and no acknowledgement
        -- at all: the host writes those fields, and a joiner reads them only
        -- once they have been sent.
        local api, ctl = paused_round()
        local sync = gPlayerSyncTable[0]
        sync.sh5_manual_reroll_request = nil
        sync.sh5_manual_reroll_ack = nil
        press(api, D_JPAD)
        press(api, A_BUTTON)
        t.eq(sync.sh5_manual_reroll_request, 1, "the first ask of the round never left")
        t.eq(ctl.unpauses, 1, "the pause outlived the first ask")
    end)

    s.test("one frame of cooldown is still a cooldown", function()
        local api, ctl = paused_round()
        gPlayerSyncTable[0].sh5_manual_reroll_ready_frame = ctl.timer + 1
        press(api, D_JPAD)
        press(api, A_BUTTON)
        t.eq(gPlayerSyncTable[0].sh5_manual_reroll_request, 0,
            "a reroll one frame early reached the host")
    end)

    s.test("the reroll row in a mode without one refuses and says which modes have it",
        function()
            local api, ctl = paused_round()
            gGlobalSyncTable.sh5_mode = api.boss_mode
            press(api, D_JPAD)
            press(api, A_BUTTON)
            t.eq(gPlayerSyncTable[0].sh5_manual_reroll_request, 0,
                "Boss mode asked the host for a new level")
            t.ok(ctl.paused, "the pause closed over a row that did nothing")
            local last = ctl.popups[#ctl.popups]
            t.eq(last ~= nil and last.text or "",
                "ANOTHER LEVEL IS ONLY AVAILABLE IN NORMAL OR TEAM.",
                "nothing on screen said why the row did nothing")
        end)

    s.test("a second request while one is pending is refused, not counted twice",
        function()
            local api, ctl = paused_round()
            press(api, D_JPAD)
            press(api, A_BUTTON)
            t.eq(gPlayerSyncTable[0].sh5_manual_reroll_request, 1, "the first ask never left")
            -- The host has not acknowledged it yet, and the player pauses again.
            api.update_pause_menu()
            ctl.paused = true
            api.update_pause_menu()
            press(api, D_JPAD)
            press(api, A_BUTTON)
            t.eq(gPlayerSyncTable[0].sh5_manual_reroll_request, 1,
                "the pending ask was overwritten by a second one")
            t.ok(ctl.paused, "the pause closed over a refused row")
        end)
end
