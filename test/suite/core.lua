-- modules/core.lua: the two tables every other module shares.
--
-- local_runtime is the local player's own frame-by-frame memory. Nothing in it
-- is synchronized, and the whole module split depends on it being ONE table
-- shared by reference rather than a set of top-level locals, so the values it
-- starts life with are worth pinning: they are what the first frame of the
-- first round reads, before anything has reset them.

return function(t, harness)
    local s = t.suite("core")
    local api = harness.load()
    local rt = api.runtime

    s.test("exactly one mode predicate answers true in each mode", function()
        -- Four one-line predicates over selected_mode(). Nothing else in the
        -- suite tells them apart, so is_mode() answering for Chaos -- or
        -- is_chaos_mode() answering always -- went unnoticed: the gates that
        -- read them (team scoring, palettes, PvP rules, the Chaos round loop)
        -- are each exercised in only one mode.
        local by_mode = {
            [api.normal_mode] = "normal",
            [api.boss_mode] = "boss",
            [api.team_mode] = "team",
            [api.chaos_mode] = "chaos",
        }
        for mode, name in pairs(by_mode) do
            gGlobalSyncTable.sh5_mode = mode
            t.eq(api.selected_mode(), mode, name .. " mode was not kept")
            t.eq(api.is_boss_mode(), name == "boss", "is_boss_mode in " .. name)
            t.eq(api.is_team_mode(), name == "team", "is_mode in " .. name)
            t.eq(api.is_chaos_mode(), name == "chaos", "is_chaos_mode in " .. name)
        end
    end)

    s.test("an unrecognised mode falls back to Normal", function()
        for _, bogus in ipairs({ -1, 4, 99 }) do
            gGlobalSyncTable.sh5_mode = bogus
            t.eq(api.selected_mode(), api.normal_mode,
                "mode " .. bogus .. " should have fallen back to Normal")
        end
        gGlobalSyncTable.sh5_mode = api.normal_mode
    end)

    s.test("another module sees the same runtime table, not a copy of it", function()
        -- The whole split rests on this. `local x = other.x` copies the value,
        -- so a module that took a copy of a table would keep writing into its
        -- own -- and nothing would error; the writes would simply never meet.
        --
        -- Team.periodic_window lives in modules/difficulty.lua and measures
        -- from local_runtime.modifier_start_frame. Writing that field here and
        -- watching difficulty.lua change its answer is the proof, because the
        -- two files reached the table by separate require() calls.
        local live, ctl = harness.load()
        ctl.timer = 1000

        live.runtime.modifier_start_frame = 1000
        t.eq(live.periodic_window(10, 90), false,
            "the cycle should have only just begun")

        live.runtime.modifier_start_frame = 1000 - 250
        t.eq(live.periodic_window(10, 90), true,
            "writing modifier_start_frame never reached modules/difficulty.lua, "
            .. "so the two files are holding different tables")
    end)

    s.test("timing sentinels start before frame zero", function()
        -- Each of these is compared against get_global_timer() or a round
        -- sequence number, and both of those start at 0. Starting one AT 0
        -- claims the event already happened on the very first frame, which
        -- silently swallows the first gust, freeze, coin leak, darkness pulse
        -- or warp of the first round after the game launches -- and a round or
        -- two later everything looks correct again, so it is easy to miss.
        for _, field in ipairs({
            "wind_tick", "freeze_tick", "coin_leak_tick", "momentum_tick",
            "modifier_tick", "darkness_draw_frame", "chaos_round_seen",
            "chaos_warp_at", "boss_warp_at", "goal_warp_at",
        }) do
            t.ok(type(rt[field]) == "number" and rt[field] < 0,
                field .. " starts at " .. tostring(rt[field]) .. ", not below zero")
        end
    end)

    s.test("frame counters and sequence numbers start at zero", function()
        for _, field in ipairs({
            "freeze_frames", "overheat_frames", "floor_frames", "slip_speed",
            "idle_frames", "jump_cooldown_frames", "boss_hazard_seq",
            "boss_stun_frames", "boss_damage_lock", "boss_round_seen",
            "modifier_start_frame", "power_external_timer", "goal_id",
            "star_visibility_next",
        }) do
            t.eq(rt[field], 0, field)
        end
    end)

    s.test("the queues and tracking sets start empty rather than nil", function()
        -- These are indexed and inserted into without being created first, so a
        -- missing one is a nil-index crash in the middle of a round.
        for _, field in ipairs({
            "pending_double_waves", "pending_meteors", "rejected_stars",
            "hidden_stars", "hidden_players",
        }) do
            t.eq(type(rt[field]), "table", field .. " is not a table")
            t.eq(next(rt[field]), nil, field .. " does not start empty")
        end
    end)

    s.test("every lock and latch starts released", function()
        -- A lock that starts engaged blocks the thing it guards for the whole
        -- first round: done_lock stops the goal being completed, death_lock
        -- stops the death warp.
        for _, field in ipairs({
            "done_lock", "death_lock", "death_warp_pending", "config_open",
            "chaos_spectator_warped", "power_original_head",
            "dnc_compat_registered", "widdlepets_compat_registered",
        }) do
            t.eq(rt[field], false, field)
        end
    end)

    -- The mode, the difficulty and the team colour used to be eleven flat
    -- fields on one table, so Team.NORMAL, Team.EASY and Team.NONE were all 0
    -- and Team.CHAOS, Team.NIGHTMARE were both 3. Passing one axis where
    -- another was meant matched a real value instead of failing, and no test,
    -- lint or type check in this project could see it. The numbers are
    -- unchanged -- two of them are on the wire -- but the names now live on
    -- three separate tables, each of which rejects a name from another axis.

    s.test("the three axes are three separate name spaces", function()
        local axes = {
            mode = api.mode_axis,
            difficulty = api.difficulty_axis,
            team_color = api.team_color_axis,
        }
        for name, axis in pairs(axes) do
            t.eq(type(axis), "table", name .. " axis is not a table")
        end
        t.ne(axes.mode, axes.difficulty, "mode and difficulty share one table")
        t.ne(axes.mode, axes.team_color, "mode and team colour share one table")
        t.ne(axes.difficulty, axes.team_color,
            "difficulty and team colour share one table")

        local owner = {}
        for name, axis in pairs(axes) do
            for key in pairs(axis) do
                t.is_nil(owner[key], key .. " is on the " .. name
                    .. " axis and on the " .. tostring(owner[key]) .. " axis")
                owner[key] = name
            end
        end
    end)

    s.test("a name from another axis reads as nil, not as a number", function()
        -- This is what the split buys. Before it, Team.NIGHTMARE read where a
        -- mode was expected gave 3, which IS Chaos mode: a valid and completely
        -- wrong answer that every check in this project accepted. Now the
        -- comparison that reads it is false, which is the safe direction.
        for _, case in ipairs({
            { "mode_axis", "NIGHTMARE" }, { "mode_axis", "RED" },
            { "difficulty_axis", "CHAOS" }, { "difficulty_axis", "BLUE" },
            { "team_color_axis", "BOSS" }, { "team_color_axis", "HARD" },
        }) do
            local axis, key = api[case[1]], case[2]
            t.eq(type(axis), "table", case[1] .. " is not a table")
            t.is_nil(axis[key], case[1] .. "." .. key .. " answered a number")
        end
    end)

    s.test("the axis numbers are the ones v1.1 put on the wire", function()
        -- sh5_mode and sh5_difficulty are synchronized, so renumbering makes a
        -- released client and a patched one disagree about what mode a lobby
        -- is in. Splitting the name spaces deliberately changed no number.
        for axis, expected in pairs({
            mode_axis = { NORMAL = 0, BOSS = 1, TEAM = 2, CHAOS = 3 },
            difficulty_axis = { EASY = 0, MEDIUM = 1, HARD = 2, NIGHTMARE = 3 },
            team_color_axis = { NONE = 0, RED = 1, BLUE = 2 },
        }) do
            for key, value in pairs(expected) do
                t.eq(api[axis][key], value, axis .. "." .. key)
            end
        end
    end)

    s.test("the flat axis names are gone from the shared table", function()
        -- Putting any of them back restores the collision, and nothing else in
        -- the suite would notice, because the value would simply be right
        -- again. Only this test stands between the fix and its own undoing.
        for _, name in ipairs({
            "NORMAL", "BOSS", "MODE", "CHAOS",
            "EASY", "MEDIUM", "HARD", "NIGHTMARE",
            "NONE", "RED", "BLUE",
        }) do
            t.is_nil(rawget(api.shared_namespace, name),
                "Team." .. name .. " is back on the shared table")
        end
    end)
end
