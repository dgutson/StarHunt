-- The four-stage modifier audit described in BALANCE_AUDIT.md.
--
-- The audit is the mod's balance guarantee: it decides, per star, which of the
-- 32 modifiers are survivable. The published matrix is 93 x 32 = 2,976 pairs,
-- 2,222 approved and 754 rejected.

return function(t, harness)
    local s = t.suite("audit")
    local api = harness.load()

    local function approved_count()
        local n = 0
        for _, goal in ipairs(api.goals) do n = n + #goal.mods end
        return n
    end

    local function kinds_of(goal)
        local set = {}
        for _, m in ipairs(goal.mods) do set[m.kind] = true end
        return set
    end

    local function goals_in(level)
        local out = {}
        for _, goal in ipairs(api.goals) do
            if goal.level == level then out[#out + 1] = goal end
        end
        return out
    end

    s.test("the matrix is 93 x 32 = 2976 pairs", function()
        t.eq(#api.goals * #api.normal_modifier_catalog, 2976)
    end)

    s.test("2222 pairs are approved", function()
        t.eq(approved_count(), 2222)
    end)

    s.test("754 pairs are rejected", function()
        t.eq(2976 - approved_count(), 754)
    end)

    s.test("flight routes never lose altitude control", function()
        -- Stage 1: a Wing Cap route must keep reliable altitude. Tower of the
        -- Wing Cap is the unambiguous flight course.
        local banned = {
            low_jump = true, high_gravity = true, air_brake = true, wind_gust = true,
            jump_cooldown = true, coin_surge = true, air_mirror = true,
            control_pulse = true, gravity_wave = true,
        }
        local flight = goals_in(LEVEL_TOTWC)
        t.ok(#flight > 0, "no Tower of the Wing Cap goals to check")
        for _, goal in ipairs(flight) do
            for kind in pairs(kinds_of(goal)) do
                t.ok(not banned[kind], goal.title .. " kept flight-breaking " .. kind)
            end
        end
    end)

    s.test("special courses get no coin-dependent modifiers", function()
        -- Stage 1: the cap courses have no reliable coin supply and no safe
        -- 20-coin margin for the toll.
        local banned = { coin_toll = true, coin_leak = true, coin_surge = true }
        for _, level in ipairs({ LEVEL_TOTWC, LEVEL_COTMC, LEVEL_VCUTM }) do
            for _, goal in ipairs(goals_in(level)) do
                for kind in pairs(kinds_of(goal)) do
                    t.ok(not banned[kind], goal.title .. " kept coin modifier " .. kind)
                end
            end
        end
    end)

    s.test("every goal rejects something", function()
        -- If a goal approved all 32, the audit is not running for it at all.
        for i, goal in ipairs(api.goals) do
            t.ok(#goal.mods < #api.normal_modifier_catalog,
                "goal " .. i .. " (" .. goal.title .. ") approved every modifier")
        end
    end)

    s.test("hand-tuned values survive the rebuild", function()
        -- rebuild_audited_modifiers() replaces each goal's mods with the whole
        -- catalog; the per-star tuning must be carried over, not reset to the
        -- catalog default. At least some goals must still carry tuned values.
        local tuned = 0
        for _, goal in ipairs(api.goals) do
            for _, m in ipairs(goal.mods) do
                if m.hand_tuned then tuned = tuned + 1 end
            end
        end
        t.ok(tuned > 0, "no hand-tuned modifier survived the audit rebuild")
    end)

    s.test("a tuned value differs from the catalog default somewhere", function()
        local defaults = {}
        for _, m in ipairs(api.normal_modifier_catalog) do defaults[m.kind] = m.value end
        local overridden = 0
        for _, goal in ipairs(api.goals) do
            for _, m in ipairs(goal.mods) do
                if m.hand_tuned and m.value ~= defaults[m.kind] then
                    overridden = overridden + 1
                end
            end
        end
        t.ok(overridden > 0, "every tuned modifier equals the catalog default, "
            .. "so per-star tuning is not being applied")
    end)

    s.test("the load-time self-check reports a complete matrix", function()
        harness.load()
        local said_ok = false
        for _, line in ipairs(harness.banner) do
            if line:find("checks passed", 1, true) then said_ok = true end
            t.ok(not line:find("Invalid", 1, true), "self-check complained: " .. line)
            t.ok(not line:find("incomplete", 1, true), "self-check complained: " .. line)
            t.ok(not line:find("Missing", 1, true), "self-check complained: " .. line)
        end
        t.ok(said_ok, "the mod did not report its checks as passed")
    end)
end
