-- The HUD's frame: the start banner, the config menu's picture, draw_hud
-- itself and the round notifications.
--
-- This is the last part of modules/hud.lua to leave main.lua, and it was the
-- least observed. test/suite/hud.lua reached draw_hud exactly once, inside a
-- pcall that only checked no colon had gone to the font, and test/suite/menu.lua
-- tests what the menu does when a button is pressed, never what it puts on
-- screen. Nothing tested the banner or the winner announcements at all, so the
-- whole area could be deleted with a green run.
--
-- Everything below is pinned as a literal. Three numbers from the harness run
-- through all of it: djui_hud_measure_text is eight pixels per character, the
-- screen is 1920 x 1009, and measure_hud_text adds five more pixels per colon.
--
-- draw_hud_text paints a black shadow at offset (1,1) first and the caller's
-- colour second, so the colour layer is the second of each pair. The banner is
-- the exception: it calls djui_hud_print_text directly, three times, and its
-- own three colours are what a test reads.

return function(t, harness)
    local s = t.suite("hud_frame")

    -- Mode and difficulty numbers, pinned rather than read back from SH.
    local NORMAL, BOSS, TEAM_MODE, CHAOS = 0, 1, 2, 3
    local MEDIUM = 1

    local function fresh()
        local api, ctl = harness.load()
        -- The mod starts in Spanish, and every string pinned below is the
        -- English one, so the language is part of the fixture.
        api.set_language(0)
        ctl.hud.text = {}
        ctl.hud.colors = {}
        ctl.hud.rect_calls = {}
        ctl.hud.texture_calls = {}
        ctl.hud.color = nil
        return api, ctl
    end

    --- The same fixture as a client.
    -- The host fills sh5_round, sh5_result_seq and both team scores in with
    -- zero at load time, so on a host the defaults the notifications apply to
    -- those fields can never be reached. A client runs none of that block and
    -- sees nothing at all until the host's first sync, which is exactly what
    -- those defaults are for.
    local function fresh_client()
        local api, ctl = harness.load(function(c) c.is_server = false end)
        api.set_language(0)
        ctl.hud.text = {}
        ctl.hud.colors = {}
        ctl.hud.rect_calls = {}
        ctl.hud.texture_calls = {}
        ctl.hud.color = nil
        return api, ctl
    end

    --- Everything draw_hud_text drew in the caller's own colour, with a colon's
    -- two dots folded back into the ":" they stand for. The shadow layer is
    -- offset by (1,1) from the colour layer and always black, so dropping every
    -- call whose colour is black at the shadow's alpha leaves the colour layer.
    local function printed(ctl, alpha)
        alpha = alpha or 255
        local shadow = math.floor(220 * alpha / 255)
        local calls = {}
        for _, call in ipairs(ctl.hud.text) do
            local is_shadow = call.r == 0 and call.g == 0 and call.b == 0
                and call.a == shadow
            if not is_shadow and call.a == alpha then calls[#calls + 1] = call end
        end
        local out, i = {}, 1
        while i <= #calls do
            local call = calls[i]
            if call.text == "." and calls[i + 1] ~= nil and calls[i + 1].text == "."
                and calls[i + 1].x == call.x and #out > 0 then
                out[#out].text = out[#out].text .. ":"
                i = i + 2
                if calls[i] ~= nil and calls[i].text ~= "." then
                    out[#out].text = out[#out].text .. calls[i].text
                    i = i + 1
                end
            else
                out[#out + 1] = { text = call.text, x = call.x, y = call.y,
                    scale = call.scale, r = call.r, g = call.g, b = call.b,
                    a = call.a }
                i = i + 1
            end
        end
        return out
    end

    --- The one string on screen reading `text`, or a failure naming everything
    -- that was drawn instead.
    local function line(ctl, text, alpha)
        local found, seen = nil, {}
        for _, call in ipairs(printed(ctl, alpha)) do
            seen[#seen + 1] = call.text
            if call.text == text then
                if found ~= nil then t.fail("'" .. text .. "' was drawn twice") end
                found = call
            end
        end
        if found == nil then
            t.fail("'" .. text .. "' was never drawn; on screen: "
                .. table.concat(seen, " | "))
        end
        -- t.fail always raises, so the fallback is only there to tell the type
        -- checker that what comes back is never nil.
        return found or {}
    end

    local function absent(ctl, text)
        for _, call in ipairs(ctl.hud.text) do
            if call.text == text then
                t.fail("'" .. text .. "' should not be on screen")
            end
        end
    end

    --- A string's position, scale and colour in one assertion.
    local function at(ctl, text, x, y, scale, r, g, b, alpha)
        local call = line(ctl, text, alpha)
        t.near(call.x, x, 0.001, text .. " x")
        t.near(call.y, y, 0.001, text .. " y")
        t.near(call.scale, scale, 0.000001, text .. " scale")
        t.eq(call.r, r, text .. " red")
        t.eq(call.g, g, text .. " green")
        t.eq(call.b, b, text .. " blue")
        return call
    end

    --- Where draw_centered_hud_text puts a colon-free string.
    local function centered_x(text, scale)
        return (1920 - #text * 8 * scale) * 0.5
    end

    local function rect_is(ctl, index, x, y, w, h, r, g, b, a)
        local got = ctl.hud.rect_calls[index]
        if got == nil then
            t.fail("only " .. #ctl.hud.rect_calls
                .. " rectangles were drawn, wanted " .. index)
        end
        got = got or {}
        local label = "rectangle " .. index
        t.near(got.x, x, 0.001, label .. " x")
        t.near(got.y, y, 0.001, label .. " y")
        t.near(got.w, w, 0.001, label .. " width")
        t.near(got.h, h, 0.001, label .. " height")
        t.eq(got.r, r, label .. " red")
        t.eq(got.g, g, label .. " green")
        t.eq(got.b, b, label .. " blue")
        t.eq(got.a, a, label .. " alpha")
    end

    -- -----------------------------------------------------------------------
    -- The start banner
    --
    -- local_start_banner_until starts at -1 and only local_round_notifications
    -- ever moves it, so arming the banner means letting the notifications see
    -- the round number change. get_global_timer() > local_start_banner_until is
    -- the guard, so the banner's last frame is the 105th and not the 106th.
    -- -----------------------------------------------------------------------

    --- Arm the banner by showing the notifications a new round number.
    local function arm_banner(api, ctl)
        gGlobalSyncTable.sh5_round = 1
        api.round_notifications()          -- first sight only records the number
        gGlobalSyncTable.sh5_round = 2
        api.round_notifications()          -- the change is what arms the banner
        ctl.hud.text = {}
        ctl.hud.colors = {}
        ctl.hud.color = nil
    end

    s.test("no banner is drawn before any round has started", function()
        local api, ctl = fresh()
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 0, "the banner drew with nothing to announce")
    end)

    s.test("seeing a round number for the first time does not arm the banner",
    function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_round = 7
        api.round_notifications()
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 0, "a late joiner was shown START!")
    end)

    s.test("a new round draws START! in three layers", function()
        local api, ctl = fresh()
        arm_banner(api, ctl)
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 3, "the banner is three print calls")
        -- floor(1009 * 0.62) = 625, and "START!" is six characters at 2.4.
        local x, y = (1920 - 48 * 2.4) * 0.5, 625
        local shadow, back, front = ctl.hud.text[1], ctl.hud.text[2], ctl.hud.text[3]
        t.eq(shadow.text, "START!", "shadow text")
        t.near(shadow.x, x + 3, 0.001, "shadow x")
        t.eq(shadow.y, y + 3, "shadow y")
        t.near(shadow.scale, 2.4, 0.000001, "shadow scale")
        t.eq(shadow.r .. "," .. shadow.g .. "," .. shadow.b .. "," .. shadow.a,
            "0,0,0,230", "shadow colour")
        t.near(back.x, x - 1, 0.001, "outline x")
        t.eq(back.y, y - 1, "outline y")
        t.eq(back.r .. "," .. back.g .. "," .. back.b .. "," .. back.a,
            "214,42,31,255", "outline colour")
        t.near(front.x, x, 0.001, "face x")
        t.eq(front.y, y, "face y")
        t.eq(front.r .. "," .. front.g .. "," .. front.b .. "," .. front.a,
            "255,222,60,255", "face colour")
    end)

    s.test("the banner is centred on its own width in Spanish", function()
        local api, ctl = fresh()
        api.set_language(1)
        arm_banner(api, ctl)
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 3, "the banner is three print calls")
        -- "EMPIEZA!" is eight characters, so it starts further left.
        t.eq(ctl.hud.text[3].text, "EMPIEZA!", "Spanish banner text")
        t.near(ctl.hud.text[3].x, (1920 - 64 * 2.4) * 0.5, 0.001, "Spanish banner x")
    end)

    s.test("the banner lasts 105 frames and not one more", function()
        local api, ctl = fresh()
        arm_banner(api, ctl)
        ctl.timer = 105
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 3, "the banner stopped before its last frame")
        ctl.hud.text = {}
        ctl.timer = 106
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 0, "the banner outlasted its window")
    end)

    s.test("the banner window is measured from the frame the round changed",
    function()
        local api, ctl = fresh()
        ctl.timer = 500
        arm_banner(api, ctl)
        ctl.timer = 605
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 3, "the window did not start at the round change")
        ctl.hud.text = {}
        ctl.timer = 606
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 0, "the window did not end 105 frames later")
    end)

    s.test("a second round change re-arms the banner", function()
        local api, ctl = fresh()
        arm_banner(api, ctl)
        ctl.timer = 200                     -- the first banner has expired
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 0, "the first banner is still up")
        gGlobalSyncTable.sh5_round = 3
        api.round_notifications()
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 3, "the second round drew no banner")
    end)

    s.test("a client sees the banner for the first round it is told about",
    function()
        local api, ctl = fresh_client()
        t.is_nil(gGlobalSyncTable.sh5_round, "the fixture is not a fresh client")
        -- Nothing has been synced yet, so the number recorded on this frame is
        -- the default the notifications apply, not a round the client saw.
        api.round_notifications()
        gGlobalSyncTable.sh5_round = 1
        api.round_notifications()
        ctl.hud.text = {}
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 3, "the first round a client saw drew no banner")
    end)

    s.test("a frame where nothing changed does not extend the banner", function()
        local api, ctl = fresh()
        arm_banner(api, ctl)
        ctl.timer = 50
        api.round_notifications()       -- same round number, nothing to re-arm
        ctl.timer = 106
        api.draw_start_banner()
        t.eq(#ctl.hud.text, 0, "a quiet frame re-armed the banner")
    end)

    -- -----------------------------------------------------------------------
    -- The round notifications
    --
    -- A result is announced when sh5_result_seq changes, once, in chat and in a
    -- two-line popup. The wording is the round's own: each mode reads different
    -- synchronized fields, and Boss and Chaos read a reason as well.
    -- -----------------------------------------------------------------------

    --- Announce one result and return what reached chat.
    local function announce(api, fields)
        gGlobalSyncTable.sh5_result_seq = 1
        api.round_notifications()           -- first sight only records the number
        for key, value in pairs(fields) do gGlobalSyncTable[key] = value end
        gGlobalSyncTable.sh5_result_seq = 2
        api.round_notifications()
    end

    local result_cases = {
        { name = "a star race names the winner and the star count",
          fields = { sh5_result_mode = NORMAL, sh5_result_winner = "MARIO",
                     sh5_result_score = 6 },
          text = "STARHUNT WINNER: MARIO - 6 STAR(S)!" },
        { name = "a star race with no winner still announces",
          fields = { sh5_result_mode = NORMAL },
          text = "STARHUNT WINNER: Nobody - 0 STAR(S)!" },
        { name = "Bowser going down is the players' win",
          fields = { sh5_result_mode = BOSS, sh5_result_reason = "boss defeated" },
          text = "BOWSER DEFEATED! TEAM STARHUNT WINS!" },
        { name = "a Boss round the host stopped says so",
          fields = { sh5_result_mode = BOSS, sh5_result_reason = "stopped by host" },
          text = "BOSS ROUND STOPPED BY THE HOST." },
        { name = "a Boss round that ran out of time is Bowser's win",
          fields = { sh5_result_mode = BOSS, sh5_result_reason = "time up" },
          text = "TIME UP! BOWSER WINS!" },
        { name = "Team mode reports both scores behind the winning team",
          fields = { sh5_result_mode = TEAM_MODE, sh5_result_winner = "RED TEAM",
                     sh5_result_red_score = 9, sh5_result_blue_score = 4 },
          text = "RED TEAM WINS! RED 9 - BLUE 4" },
        { name = "Team mode announces a blue win",
          fields = { sh5_result_mode = TEAM_MODE, sh5_result_winner = "BLUE TEAM",
                     sh5_result_red_score = 2, sh5_result_blue_score = 5 },
          text = "BLUE TEAM WINS! RED 2 - BLUE 5" },
        { name = "Team mode announces a tie with the same scores",
          fields = { sh5_result_mode = TEAM_MODE, sh5_result_winner = "Nobody",
                     sh5_result_red_score = 3, sh5_result_blue_score = 3 },
          text = "TEAM TIE! RED 3 - BLUE 3" },
        { name = "Chaos names the last player standing",
          fields = { sh5_result_mode = CHAOS, sh5_result_winner = "LUIGI",
                     sh5_result_reason = "chaos last standing" },
          text = "CHAOS WINNER: LUIGI" },
        { name = "Chaos that ended some other way names nobody",
          fields = { sh5_result_mode = CHAOS, sh5_result_winner = "LUIGI",
                     sh5_result_reason = "stopped by host" },
          text = "CHAOS ENDED WITHOUT A WINNER." },
    }

    for _, case in ipairs(result_cases) do
        s.test(case.name, function()
            local api, ctl = fresh()
            announce(api, case.fields)
            t.eq(#ctl.chat, 1, "the result was announced " .. #ctl.chat .. " times")
            t.eq(ctl.chat[1], case.text, "chat message")
            t.eq(#ctl.popups, 1, "the popup was created " .. #ctl.popups .. " times")
            t.eq(ctl.popups[1].text, case.text, "popup message")
            t.eq(ctl.popups[1].lines, 2, "popup line count")
        end)
    end

    s.test("a result is announced in the player's own language", function()
        local api, ctl = fresh()
        api.set_language(1)
        announce(api, { sh5_result_mode = NORMAL, sh5_result_winner = "MARIO",
            sh5_result_score = 6 })
        t.eq(ctl.chat[1], "GANADOR DE STARHUNT: MARIO - 6 ESTRELLA(S)!",
            "Spanish chat message")
    end)

    s.test("seeing a result sequence for the first time announces nothing",
    function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_result_seq = 4
        api.round_notifications()
        t.eq(#ctl.chat, 0, "a late joiner was told about a finished round")
        t.eq(#ctl.popups, 0, "a late joiner got the result popup")
    end)

    s.test("the same result is announced once, not on every frame", function()
        local api, ctl = fresh()
        announce(api, { sh5_result_mode = NORMAL, sh5_result_winner = "MARIO" })
        api.round_notifications()
        api.round_notifications()
        t.eq(#ctl.chat, 1, "the result was repeated " .. #ctl.chat .. " times")
    end)

    s.test("a round change alone announces no result", function()
        local api, ctl = fresh()
        arm_banner(api, ctl)
        t.eq(#ctl.chat, 0, "starting a round announced a result")
    end)

    s.test("a client hears the first result it is told about", function()
        local api, ctl = fresh_client()
        t.is_nil(gGlobalSyncTable.sh5_result_seq,
            "the fixture is not a fresh client")
        api.round_notifications()
        gGlobalSyncTable.sh5_result_mode = NORMAL
        gGlobalSyncTable.sh5_result_winner = "MARIO"
        gGlobalSyncTable.sh5_result_seq = 1
        api.round_notifications()
        t.eq(#ctl.chat, 1, "the first result a client saw was swallowed")
    end)

    s.test("a Team result a client has no scores for reads zero to zero",
    function()
        local api, ctl = fresh_client()
        announce(api, { sh5_result_mode = TEAM_MODE, sh5_result_winner = "Nobody" })
        t.eq(ctl.chat[1], "TEAM TIE! RED 0 - BLUE 0", "chat message")
    end)

    -- -----------------------------------------------------------------------
    -- The config menu's picture
    --
    -- The host's box is 270 x 192 and the client's 270 x 108, both centred, and
    -- both are three rectangles: the screen dimmed, the box, and the gold rule
    -- across its top. Rows start 34 pixels down and repeat every 21.
    -- -----------------------------------------------------------------------

    local BOX_X = (1920 - 270) * 0.5                 -- 825
    local HOST_Y = (1009 - 192) * 0.5                -- 408.5
    local CLIENT_Y = (1009 - 108) * 0.5              -- 450.5

    local function open_menu(api, ctl)
        api.runtime.config_open = true
        ctl.hud.text = {}
        ctl.hud.colors = {}
        ctl.hud.rect_calls = {}
        ctl.hud.color = nil
        return api, ctl
    end

    s.test("a closed menu draws nothing at all", function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        api.draw_config_menu()
        t.eq(#ctl.hud.text, 0, "the closed menu printed text")
        t.eq(#ctl.hud.rect_calls, 0, "the closed menu drew rectangles")
    end)

    s.test("the host's box dims the screen and sits centred under a gold rule",
    function()
        local api, ctl = fresh()
        open_menu(api, ctl)
        api.draw_config_menu()
        rect_is(ctl, 1, 0, 0, 1920, 1009, 0, 0, 0, 180)
        rect_is(ctl, 2, BOX_X, HOST_Y, 270, 192, 16, 36, 92, 245)
        rect_is(ctl, 3, BOX_X, HOST_Y, 270, 3, 255, 215, 73, 255)
    end)

    s.test("a client's box is shorter because it has four fewer rows", function()
        local api, ctl = fresh()
        ctl.is_server = false
        open_menu(api, ctl)
        api.draw_config_menu()
        rect_is(ctl, 2, BOX_X, CLIENT_Y, 270, 108, 16, 36, 92, 245)
        rect_is(ctl, 3, BOX_X, CLIENT_Y, 270, 3, 255, 215, 73, 255)
    end)

    s.test("the title sits ten pixels inside the top of the box", function()
        local api, ctl = fresh()
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "STARHUNT", centered_x("STARHUNT", 0.82), HOST_Y + 10, 0.82,
            255, 215, 73)
    end)

    s.test("the host sees all six rows, 21 pixels apart", function()
        local api, ctl = fresh()
        open_menu(api, ctl)
        api.draw_config_menu()
        local rows = {
            "> LANGUAGE - ENGLISH",
            "  GAME MODE - NORMAL",
            "  DIFFICULTY - NORMAL",
            "  TIME - 11 MIN",
            "  STATUS - WAITING",
            "  START ROUND",
        }
        for index, text in ipairs(rows) do
            at(ctl, text, BOX_X + 16, HOST_Y + 34 + 21 * (index - 1), 0.62,
                255, 255, 255)
        end
    end)

    s.test("a client sees only the two rows it is allowed to touch", function()
        local api, ctl = fresh()
        ctl.is_server = false
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "> LANGUAGE - ENGLISH", BOX_X + 16, CLIENT_Y + 34, 0.62,
            255, 255, 255)
        at(ctl, "  STATUS - WAITING", BOX_X + 16, CLIENT_Y + 55, 0.62,
            255, 255, 255)
        absent(ctl, "  GAME MODE - NORMAL")
        absent(ctl, "  START ROUND")
    end)

    s.test("the selected row is marked with an arrow and a translucent bar",
    function()
        local api, ctl = fresh()
        open_menu(api, ctl)
        api.runtime.config_selection = 3
        ctl.hud.rect_calls = {}
        api.draw_config_menu()
        -- The three box rectangles first, then the highlight behind row three.
        rect_is(ctl, 4, BOX_X + 10, HOST_Y + 34 + 42 - 2, 270 - 20, 16,
            255, 255, 255, 45)
        at(ctl, "> DIFFICULTY - NORMAL", BOX_X + 16, HOST_Y + 76, 0.62,
            255, 255, 255)
        at(ctl, "  LANGUAGE - ENGLISH", BOX_X + 16, HOST_Y + 34, 0.62,
            255, 255, 255)
    end)

    s.test("an active round turns the start row into a stop row", function()
        local api, ctl = fresh()
        ctl.begin_round(api, NORMAL, MEDIUM)
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "  STOP ROUND", BOX_X + 16, HOST_Y + 34 + 21 * 5, 0.62,
            255, 255, 255)
        absent(ctl, "  START ROUND")
    end)

    s.test("mode and difficulty are marked locked while a round runs", function()
        local api, ctl = fresh()
        ctl.begin_round(api, NORMAL, MEDIUM)
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "  GAME MODE - NORMAL (LOCKED)", BOX_X + 16, HOST_Y + 55, 0.62,
            255, 255, 255)
        at(ctl, "  DIFFICULTY - NORMAL (LOCKED)", BOX_X + 16, HOST_Y + 76, 0.62,
            255, 255, 255)
        at(ctl, "  TIME - LOCKED", BOX_X + 16, HOST_Y + 97, 0.62, 255, 255, 255)
    end)

    s.test("each mode names itself on the mode row", function()
        local cases = { [BOSS] = "  GAME MODE - BOSS",
                        [TEAM_MODE] = "  GAME MODE - TEAM",
                        [CHAOS] = "  GAME MODE - CHAOS" }
        for mode, text in pairs(cases) do
            local api, ctl = fresh()
            gGlobalSyncTable.sh5_mode = mode
            open_menu(api, ctl)
            api.draw_config_menu()
            at(ctl, text, BOX_X + 16, HOST_Y + 55, 0.62, 255, 255, 255)
        end
    end)

    s.test("a two-player mode with one player warns and dims its own rows",
    function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = TEAM_MODE
        for i = 1, 15 do gNetworkPlayers[i].connected = false end
        open_menu(api, ctl)
        api.draw_config_menu()
        -- Disabled rows are drawn at alpha 105 rather than 255.
        at(ctl, "  GAME MODE - TEAM - NEEDS 2 PLAYERS", BOX_X + 16, HOST_Y + 55,
            0.62, 255, 255, 255, 105)
        at(ctl, "  START ROUND", BOX_X + 16, HOST_Y + 139, 0.62,
            255, 255, 255, 105)
        -- The rows that are still usable keep full alpha.
        at(ctl, "> LANGUAGE - ENGLISH", BOX_X + 16, HOST_Y + 34, 0.62,
            255, 255, 255)
    end)

    s.test("the difficulty row names the difficulty in force", function()
        local names = { [0] = "EASY", [1] = "NORMAL", [2] = "HARD",
                        [3] = "NIGHTMARE" }
        for difficulty, name in pairs(names) do
            local api, ctl = fresh()
            gGlobalSyncTable.sh5_difficulty = difficulty
            open_menu(api, ctl)
            api.draw_config_menu()
            at(ctl, "  DIFFICULTY - " .. name, BOX_X + 16, HOST_Y + 76, 0.62,
                255, 255, 255)
        end
    end)

    s.test("the time row is clamped to the range for the players present",
    function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_config_minutes = 99
        open_menu(api, ctl)
        api.draw_config_menu()
        -- Two players connected: the star race allows 11 to 20 minutes.
        at(ctl, "  TIME - 20 MIN", BOX_X + 16, HOST_Y + 97, 0.62, 255, 255, 255)
    end)

    s.test("the minutes hint under the box names the same range", function()
        local api, ctl = fresh()
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "11-20 MINUTES", centered_x("11-20 MINUTES", 0.38),
            HOST_Y + 192 - 29, 0.38, 190, 190, 190)
    end)

    s.test("Boss mode has its own shorter range", function()
        local api, ctl = fresh()
        gGlobalSyncTable.sh5_mode = BOSS
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "4-9 MINUTES", centered_x("4-9 MINUTES", 0.38),
            HOST_Y + 192 - 29, 0.38, 190, 190, 190)
    end)

    s.test("the minutes hint is the host's alone, and only before a round",
    function()
        local api, ctl = fresh()
        ctl.is_server = false
        open_menu(api, ctl)
        api.draw_config_menu()
        absent(ctl, "11-20 MINUTES")

        api, ctl = fresh()
        ctl.begin_round(api, NORMAL, MEDIUM)
        open_menu(api, ctl)
        api.draw_config_menu()
        absent(ctl, "11-20 MINUTES")
    end)

    s.test("the footer explains the controls only once a round is running",
    function()
        local api, ctl = fresh()
        open_menu(api, ctl)
        api.draw_config_menu()
        local locked = "MENU LOCKED UNTIL ROUND STARTS"
        at(ctl, locked, centered_x(locked, 0.32), HOST_Y + 192 - 16, 0.32,
            160, 210, 255)

        api, ctl = fresh()
        ctl.begin_round(api, NORMAL, MEDIUM)
        open_menu(api, ctl)
        api.draw_config_menu()
        local controls = "UP/DOWN SELECT  A USE  LEFT/RIGHT CHANGE  B CLOSE"
        at(ctl, controls, centered_x(controls, 0.32), HOST_Y + 192 - 16, 0.32,
            160, 210, 255)
    end)

    s.test("the footer is translated with the rest of the menu", function()
        local api, ctl = fresh()
        api.set_language(1)
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "MENU BLOQUEADO HASTA INICIAR LA RONDA",
            centered_x("MENU BLOQUEADO HASTA INICIAR LA RONDA", 0.32),
            HOST_Y + 192 - 16, 0.32, 160, 210, 255)
    end)

    s.test("the language row names the language the player picked", function()
        local api, ctl = fresh()
        api.set_language(1)
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "> IDIOMA - ESPAÑOL", BOX_X + 16, HOST_Y + 34, 0.62,
            255, 255, 255)
    end)

    s.test("a star race with one player is neither warned nor dimmed", function()
        local api, ctl = fresh()
        for i = 1, 15 do gNetworkPlayers[i].connected = false end
        open_menu(api, ctl)
        api.draw_config_menu()
        -- Only Team and Chaos need a second player; a star race is playable
        -- alone, so its rows stay plain and at full alpha.
        at(ctl, "  GAME MODE - NORMAL", BOX_X + 16, HOST_Y + 55, 0.62,
            255, 255, 255)
        at(ctl, "  START ROUND", BOX_X + 16, HOST_Y + 139, 0.62, 255, 255, 255)
    end)

    s.test("the status row counts the round down", function()
        local api, ctl = fresh()
        ctl.begin_round(api, NORMAL, MEDIUM)
        -- begin_round gives the round 3600 frames, which is two minutes at
        -- thirty frames a second. Spend 2700 of them and 0:30 is left.
        ctl.timer = ctl.timer + 2700
        open_menu(api, ctl)
        api.draw_config_menu()
        at(ctl, "  STATUS - ACTIVE 0:30", BOX_X + 16, HOST_Y + 118, 0.62,
            255, 255, 255)
    end)

    -- -----------------------------------------------------------------------
    -- draw_hud, which assembles the frame
    -- -----------------------------------------------------------------------

    s.test("the HUD is drawn at N64 resolution in the HUD font", function()
        local api, ctl = fresh()
        api.draw_hud()
        t.eq(ctl.hud.resolution, RESOLUTION_N64, "resolution")
        t.eq(ctl.hud.font, FONT_HUD, "font")
    end)

    s.test("outside a round the HUD is the config menu and nothing else",
    function()
        local api, ctl = fresh()
        open_menu(api, ctl)
        api.draw_hud()
        rect_is(ctl, 1, 0, 0, 1920, 1009, 0, 0, 0, 180)
        at(ctl, "STARHUNT", centered_x("STARHUNT", 0.82), HOST_Y + 10, 0.82,
            255, 215, 73)
        -- No round means no score, no timer and no objective.
        t.eq(#ctl.hud.texture_calls, 0, "the star and coin icons were drawn")
    end)

    s.test("outside a round with the menu closed the HUD draws nothing",
    function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        ctl.hud.text = {}
        ctl.hud.rect_calls = {}
        api.draw_hud()
        t.eq(#ctl.hud.text, 0, "text was drawn with no round and no menu")
        t.eq(#ctl.hud.rect_calls, 0, "rectangles were drawn with no round and no menu")
    end)

    s.test("a running round puts the score, the timer and the objective up",
    function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        ctl.begin_round(api, NORMAL, MEDIUM)
        gPlayerSyncTable[0].sh5_score = 4
        ctl.hud.text = {}
        ctl.hud.rect_calls = {}
        api.draw_hud()
        line(ctl, "x 4")                     -- the score card, star icon and all
        line(ctl, "TIME 2:00")               -- begin_round's 3600 frames
        line(ctl, "CHOOSING YOUR NEXT GOAL...")
        t.ne(#ctl.hud.rect_calls, 0, "the round drew no panels")
    end)

    s.test("the config menu is drawn over the round's panels, not instead of them",
    function()
        local api, ctl = fresh()
        ctl.begin_round(api, NORMAL, MEDIUM)
        open_menu(api, ctl)
        api.draw_hud()
        -- The menu's full-screen dim is the one rectangle covering the screen,
        -- and every panel rectangle was drawn before it.
        local dim_at = nil
        for index, rect in ipairs(ctl.hud.rect_calls) do
            if rect.w == 1920 and rect.h == 1009 and rect.a == 180 then
                dim_at = index
            end
        end
        if dim_at == nil then t.fail("the menu did not dim the screen") end
        t.ne(dim_at, 1, "the panels were not drawn under the menu")
        t.eq(#ctl.hud.rect_calls > (dim_at or 0), true,
            "the menu's own box was not drawn over the dim")
        line(ctl, "STARHUNT")
    end)

    s.test("a round that has just started shows the banner through draw_hud",
    function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        ctl.begin_round(api, NORMAL, MEDIUM)
        api.round_notifications()
        gGlobalSyncTable.sh5_round = (gGlobalSyncTable.sh5_round or 0) + 1
        api.round_notifications()
        ctl.hud.text = {}
        api.draw_hud()
        -- The banner is three print calls of its own, not one through
        -- draw_hud_text, so count them rather than asking for the one string.
        local banner = 0
        for _, call in ipairs(ctl.hud.text) do
            if call.text == "START!" then banner = banner + 1 end
        end
        t.eq(banner, 3, "draw_hud drew the banner " .. banner .. " times")
    end)

    s.test("the objective panel names the star the player is chasing", function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        ctl.begin_round(api, NORMAL, MEDIUM)
        gPlayerSyncTable[0].sh5_goal = 1
        gPlayerSyncTable[0].sh5_modifier = 1
        ctl.hud.text = {}
        api.draw_hud()
        line(ctl, "BOB-OMB BATTLEFIELD")
        line(ctl, "KING BOB-OMB")
        line(ctl, "CURSED FLOOR: 7 SEC")
        absent(ctl, "CHOOSING YOUR NEXT GOAL...")
    end)

    s.test("a second modifier reaches the objective panel as well", function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        -- Chaos gives every player two independent modifiers on Nightmare, and
        -- reads both straight from the player's own synchronized slots.
        ctl.begin_round(api, CHAOS, 3)
        gPlayerSyncTable[0].sh5_modifier = 1
        gPlayerSyncTable[0].sh5_modifier_2 = 2
        ctl.hud.text = {}
        api.draw_hud()
        line(ctl, "B BUTTON LOCKED")
        line(ctl, "CURSED FLOOR: 5 SEC")
    end)

    s.test("a player with no score yet is shown a zero", function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        ctl.begin_round(api, NORMAL, MEDIUM)
        ctl.hud.text = {}
        api.draw_hud()
        -- Two cards read "x 0": the star score on the left and the coin count
        -- on the right. The left one is the score's own default.
        local zeros = {}
        for _, call in ipairs(printed(ctl)) do
            if call.text == "x 0" then zeros[#zeros + 1] = call.x end
        end
        table.sort(zeros)
        t.eq(#zeros, 2, "the score and the coin count were not both zero")
        t.eq(zeros[1], 38, "the score card is not where it belongs")
    end)

    s.test("draw_hud repaints the Gun Mod HUD above the darkness", function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        ctl.begin_round(api, NORMAL, MEDIUM)
        api.runtime.darkness_draw_frame = ctl.timer
        gGlobalSyncTable.gunModEnabled = true
        gNetworkPlayers[0].currActNum = 1
        _G.gunModApi = {
            cur_weapon = function() return { ammo = 7, maxAmmo = 10 } end,
            cur_dual_wield_weapon = function() return nil end,
            get_render_hud = function() return true end,
        }
        ctl.hud.text = {}
        api.draw_hud()
        line(ctl, "7/10")
    end)

    s.test("draw_hud restores the native counters whether or not a round runs",
    function()
        local api, ctl = fresh()
        api.runtime.config_open = false
        ctl.hud.values[HUD_DISPLAY_FLAGS] = HUD_DISPLAY_FLAG_STAR_COUNT
        ctl.begin_round(api, NORMAL, MEDIUM)
        api.draw_hud()
        t.eq(ctl.hud.values[HUD_DISPLAY_FLAGS], 0,
            "the star counter was left on during a round")
        gGlobalSyncTable.sh5_active = 0
        api.draw_hud()
        t.eq(ctl.hud.values[HUD_DISPLAY_FLAGS], HUD_DISPLAY_FLAG_STAR_COUNT,
            "the player's own counter setting was not given back")
    end)
end
