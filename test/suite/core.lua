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
            "done_lock", "death_lock", "death_warp_pending",
            "chaos_spectator_warped", "power_original_head",
            "dnc_compat_registered", "widdlepets_compat_registered",
        }) do
            t.eq(rt[field], false, field)
        end
    end)
end
