-- run_static_modifier_checks: the self-check main.lua runs once at load time,
-- after every module has been required.
--
-- It reports by printing, not by raising, so these tests read what it wrote.
-- A clean load is expected to print exactly one line -- the success banner --
-- and every failure test asserts two things: that the right complaint appears,
-- and that the success banner does NOT. The second half is what catches a
-- branch that prints a complaint but forgets to set `valid = false`.
--
-- Three of the checks cannot be driven from here at all: the water-cap
-- idempotence test, the A/B swap and the control-drift rotation call
-- capped_horizontal_velocity, swap_button_bits and rotate_stick, which are
-- file-local to modules/modifiers.lua and cannot be replaced by a test. All
-- three are covered only in the sense that the clean-load banner proves they
-- passed with the shipped helpers.

return function(t, harness)
    local s = t.suite("selfcheck")

    -- Pinned rather than read back from the mod. A test that asks the catalog
    -- what the catalog contains agrees with it whatever it says.
    local SUCCESS_LINE =
        "[StarHunt v1.1.1] 93 goals, 32 modifiers, 2976 audited pairs "
        .. "(2222 approved, 754 rejected), and checks passed."

    -- The 32 kinds MODIFIER_KINDS accepts, written out so that dropping one
    -- from the mod fails here rather than silently widening what ships.
    local ACCEPTED_KINDS = {
        "no_b", "floor_doom", "speed_cap", "low_jump", "water_cap",
        "jump_limit", "reverse_controls", "periodic_freeze", "fragile",
        "high_gravity", "wind_gust", "no_z", "air_brake", "lava_clock",
        "turbo", "slippery", "swap_ab", "keep_moving", "jump_cooldown",
        "coin_surge", "control_drift", "coin_toll", "darkness_pulse",
        "mirrored_steering", "coin_leak", "slow_pulse", "air_mirror",
        "momentum_burst", "control_pulse", "coin_weight", "gravity_wave",
        "overheat",
    }

    -- The fifteen main courses. Act 7 on any of them is that course's
    -- 100-coin star, which BALANCE_AUDIT.md says never reaches the catalog.
    local MAIN_COURSE_NAMES = {
        "LEVEL_BOB", "LEVEL_WF", "LEVEL_JRB", "LEVEL_CCM", "LEVEL_BBH",
        "LEVEL_HMC", "LEVEL_LLL", "LEVEL_SSL", "LEVEL_DDD", "LEVEL_SL",
        "LEVEL_WDW", "LEVEL_TTM", "LEVEL_THI", "LEVEL_TTC", "LEVEL_RR",
    }

    --- Run the self-check and return everything it printed.
    local function run(api)
        local lines, ok, err = harness.capture_print(api.static_checks)
        if not ok then t.fail("the self-check raised: " .. tostring(err)) end
        return lines
    end

    local function found(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return line end
        end
        return nil
    end

    local function count(lines, needle)
        local n = 0
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then n = n + 1 end
        end
        return n
    end

    --- Assert that `lines` carries `needle` and no success banner.
    local function complains(lines, needle)
        t.ok(found(lines, needle) ~= nil,
            "expected a complaint containing: " .. needle
            .. "\n  got: " .. table.concat(lines, "\n  "))
        t.is_nil(found(lines, "checks passed"),
            "the check still reported success after " .. needle)
    end

    --- Assert that `lines` is a clean pass.
    local function passes(lines)
        t.is_nil(found(lines, "Invalid"), "unexpected complaint")
        t.is_nil(found(lines, "Missing"), "unexpected complaint")
        t.is_nil(found(lines, "slipped"), "unexpected complaint")
        t.ok(found(lines, "checks passed") ~= nil,
            "expected the success banner\n  got: " .. table.concat(lines, "\n  "))
    end

    -- -----------------------------------------------------------------------
    -- the shipped catalog

    s.test("loading the mod prints the success banner and nothing else", function()
        harness.load()
        t.eq(#harness.banner, 1)
        t.eq(harness.banner[1], SUCCESS_LINE)
    end)

    s.test("running the check again on an untouched catalog says the same thing", function()
        local api = harness.load()
        local lines = run(api)
        t.eq(#lines, 1)
        t.eq(lines[1], SUCCESS_LINE)
    end)

    s.test("the accepted kinds are exactly the kinds the catalog ships", function()
        local api = harness.load()
        t.eq(#api.normal_modifier_catalog, #ACCEPTED_KINDS)
        local shipped = {}
        for _, template in ipairs(api.normal_modifier_catalog) do
            shipped[template.kind] = true
        end
        for _, kind in ipairs(ACCEPTED_KINDS) do
            t.ok(shipped[kind], "the catalog no longer ships the kind " .. kind)
        end
    end)

    -- -----------------------------------------------------------------------
    -- the required power

    s.test("a goal whose required power is not one of the four is named by slot", function()
        local api = harness.load()
        api.goals[7].power = "invisible"
        complains(run(api), "Invalid required power in slot 7.")
    end)

    s.test("no power, wing, metal, vanish and metal_vanish are all accepted", function()
        local api = harness.load()
        for _, power in ipairs({ "wing", "metal", "vanish", "metal_vanish" }) do
            api.goals[1].power = power
            passes(run(api))
        end
        api.goals[1].power = nil
        passes(run(api))
    end)

    -- -----------------------------------------------------------------------
    -- the 100-coin stars

    s.test("an act-7 star in any of the fifteen main courses is refused", function()
        -- Slot 9 rather than slot 1, so a message that hard-coded the slot
        -- number would fail here.
        local api = harness.load()
        local original_level, original_act = api.goals[9].level, api.goals[9].act
        for _, name in ipairs(MAIN_COURSE_NAMES) do
            api.goals[9].level = _G[name]
            api.goals[9].act = 7
            complains(run(api), "100-coin goal slipped into slot 9.")
        end
        api.goals[9].level, api.goals[9].act = original_level, original_act
        passes(run(api))
    end)

    s.test("act 6 on a main course is an ordinary star", function()
        local api = harness.load()
        api.goals[1].level = LEVEL_BOB
        api.goals[1].act = 6
        passes(run(api))
    end)

    s.test("act 7 outside the fifteen main courses is not a 100-coin star", function()
        -- The cap courses have a single star each and no 100-coin star, so the
        -- act number alone must not be enough to refuse a goal.
        local api = harness.load()
        api.goals[1].level = LEVEL_TOTWC
        api.goals[1].act = 7
        passes(run(api))
    end)

    -- -----------------------------------------------------------------------
    -- the modifier list

    s.test("a goal with no modifier list is named by slot", function()
        local api = harness.load()
        api.goals[3].mods = nil
        complains(run(api), "Goal 3 has no modifier choices.")
    end)

    s.test("a goal with an empty modifier list is named by slot", function()
        local api = harness.load()
        api.goals[3].mods = {}
        complains(run(api), "Goal 3 has no modifier choices.")
    end)

    s.test("a modifier kind outside the accepted list is named", function()
        local api = harness.load()
        api.goals[1].mods = { { kind = "teleport", value = 0 } }
        complains(run(api), "Invalid modifier: teleport")
    end)

    s.test("each of the 32 accepted kinds passes on its own", function()
        local api = harness.load()
        for _, kind in ipairs(ACCEPTED_KINDS) do
            -- 5 is inside the cursed-floor range, so it is safe for every kind.
            api.goals[1].mods = { { kind = kind, value = 5 } }
            passes(run(api))
        end
    end)

    s.test("auto_crouch is refused", function()
        -- auto_crouch is a kind that no longer exists anywhere in the mod.
        -- run_static_modifier_checks names it explicitly as well as leaving it
        -- out of MODIFIER_KINDS, so this test passes either way -- it pins the
        -- behaviour rather than proving the explicit clause is doing work.
        local api = harness.load()
        api.goals[1].mods = { { kind = "auto_crouch", value = 0 } }
        complains(run(api), "Invalid modifier: auto_crouch")
    end)

    -- -----------------------------------------------------------------------
    -- the cursed-floor duration

    s.test("a cursed floor shorter than 4 seconds is refused", function()
        local api = harness.load()
        api.goals[1].mods = { { kind = "floor_doom", value = 3 } }
        complains(run(api), "Invalid cursed-floor duration: 3")
    end)

    s.test("a cursed floor longer than 9 seconds is refused", function()
        local api = harness.load()
        api.goals[1].mods = { { kind = "floor_doom", value = 10 } }
        complains(run(api), "Invalid cursed-floor duration: 10")
    end)

    s.test("4 and 9 seconds are both inside the cursed-floor range", function()
        local api = harness.load()
        api.goals[1].mods = { { kind = "floor_doom", value = 4 } }
        passes(run(api))
        api.goals[1].mods = { { kind = "floor_doom", value = 9 } }
        passes(run(api))
    end)

    s.test("the duration limits apply to the cursed floor and to nothing else", function()
        local api = harness.load()
        api.goals[1].mods = { { kind = "speed_cap", value = 3 } }
        passes(run(api))
    end)

    -- -----------------------------------------------------------------------
    -- the audit matrix

    s.test("a goal missing from the audit matrix is named", function()
        local api = harness.load()
        api.modifier_audit[5] = nil
        local lines = run(api)
        complains(lines, "Missing audit entry at goal 5: ")
        t.eq(count(lines, "Missing audit entry at goal 5: "), 32)
    end)

    s.test("a single modifier missing from one goal's audit row is named", function()
        local api = harness.load()
        api.modifier_audit[5].turbo = nil
        local lines = run(api)
        complains(lines, "Missing audit entry at goal 5: turbo")
        t.eq(count(lines, "Missing audit entry"), 1)
    end)

    s.test("the first and last goal rows are inspected too", function()
        -- The matrix walk runs 1..#GOALS. A range that started at 2 or stopped
        -- one short would leave the catalog's ends unchecked.
        local api = harness.load()
        api.modifier_audit[1].turbo = nil
        api.modifier_audit[93].turbo = nil
        local lines = run(api)
        complains(lines, "Missing audit entry at goal 1: turbo")
        t.ok(found(lines, "Missing audit entry at goal 93: turbo") ~= nil,
            "the last goal's audit row was never inspected")
        t.eq(count(lines, "Missing audit entry"), 2)
    end)

    s.test("an audited-pair tally short of 93 by 32 is refused", function()
        local api = harness.load()
        api.modifier_audit_counts.checked = 2975
        complains(run(api), "Modifier audit matrix is incomplete.")
    end)

    s.test("approved and rejected must add up to the pairs checked", function()
        local api = harness.load()
        api.modifier_audit_counts.approved = api.modifier_audit_counts.approved - 1
        complains(run(api), "Modifier audit matrix is incomplete.")
    end)

    s.test("the banner reports the pair count it was given, not a constant", function()
        -- Moving the audited-pair count without tripping the guard above the
        -- banner means changing the size of the catalog: expected_audits is
        -- #GOALS * #NORMAL_MODIFIER_CATALOG and #GOALS is pinned at 93. A
        -- thirty-third template repeating a kind the matrix already holds
        -- leaves every other check satisfied, so only the number moves.
        --
        -- It also shows what the self-check does not do: nothing in it asserts
        -- the catalog is 32 entries long. The "32 modifiers" in the banner is a
        -- literal string. test/suite/catalog.lua is what pins the real size.
        local api = harness.load()
        api.normal_modifier_catalog[33] = { kind = "turbo", value = 5, label = "TURBO" }
        api.modifier_audit_counts.checked = 93 * 33
        api.modifier_audit_counts.approved = 2222
        api.modifier_audit_counts.rejected = 93 * 33 - 2222
        local lines = run(api)
        t.eq(lines[1],
            "[StarHunt v1.1.1] 93 goals, 32 modifiers, 3069 audited pairs "
            .. "(2222 approved, 847 rejected), and checks passed.")
    end)

    s.test("the banner reports the tallies it was given, not constants", function()
        -- The counts in the banner have to come from MODIFIER_AUDIT_COUNTS. If
        -- they were hard-coded the check could report 2222 approved while the
        -- audit had approved something else entirely.
        local api = harness.load()
        api.modifier_audit_counts.checked = 2976
        api.modifier_audit_counts.approved = 2223
        api.modifier_audit_counts.rejected = 753
        local lines = run(api)
        t.eq(lines[1],
            "[StarHunt v1.1.1] 93 goals, 32 modifiers, 2976 audited pairs "
            .. "(2223 approved, 753 rejected), and checks passed.")
    end)

    -- -----------------------------------------------------------------------
    -- the goal count

    s.test("a catalog that is not 93 goals long is refused", function()
        local api = harness.load()
        local removed = table.remove(api.goals)
        -- Every other check still passes; only the count is wrong, and the
        -- audit tally is recomputed from the shortened catalog.
        api.modifier_audit_counts.checked = 92 * 32
        api.modifier_audit_counts.approved = 2222
        api.modifier_audit_counts.rejected = 92 * 32 - 2222
        local lines = run(api)
        t.is_nil(found(lines, "checks passed"),
            "a 92-goal catalog still reported success")
        api.goals[#api.goals + 1] = removed
    end)
end
