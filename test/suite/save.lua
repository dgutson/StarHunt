-- StarHunt scores its own stars and must never leave them in the player's real
-- save file.
--
-- DEVELOPMENT_CHECKLIST.md records the original bug: the game's course numbers
-- are one-based and the save API's are zero-based, so stars were being cleared
-- from the wrong course. save_course_index_for() is the single place that
-- bridges the two, and it is easy to lose in a refactor.

return function(t, harness)
    local s = t.suite("save")

    local function fresh()
        local api, ctl = harness.load()
        ctl.save.removed = {}
        ctl.save.saves = 0
        return api, ctl
    end

    s.test("a cleared star targets the zero-based course slot", function()
        local api, ctl = fresh()
        for _, goal in ipairs(api.goals) do
            ctl.save.removed = {}
            api.remove_save_flag(goal)
            t.eq(#ctl.save.removed, 1, "expected exactly one removal per goal")
            local got = ctl.save.removed[1]
            t.eq(got.course, ctl.course_of[goal.level] - 1, string.format(
                "%s (%s act %d): course index", goal.title, tostring(goal.level), goal.act))
        end
    end)

    s.test("the star flag is a bit shifted by the act number", function()
        local api, ctl = fresh()
        for _, goal in ipairs(api.goals) do
            ctl.save.removed = {}
            api.remove_save_flag(goal)
            t.eq(ctl.save.removed[1].flags, 1 << (goal.act - 1),
                goal.title .. " act " .. goal.act .. ": star flag")
        end
    end)

    s.test("the save file index is zero-based too", function()
        local api, ctl = fresh()
        -- get_current_save_file_num() returns 1 for the first file; the save API
        -- wants 0.
        api.remove_save_flag(api.goals[1])
        t.eq(ctl.save.removed[1].file, 0)
    end)

    s.test("clearing a star writes the save out", function()
        local api, ctl = fresh()
        api.remove_save_flag(api.goals[1])
        t.ok(ctl.save.saves > 0, "the save was never flushed to disk")
    end)

    s.test("act numbers map to distinct bits within a course", function()
        -- Two stars of the same course must not clear each other's flag.
        local api, ctl = fresh()
        local per_course = {}
        for _, goal in ipairs(api.goals) do
            ctl.save.removed = {}
            api.remove_save_flag(goal)
            local rec = ctl.save.removed[1]
            per_course[rec.course] = per_course[rec.course] or {}
            local seen = per_course[rec.course]
            t.ok(not seen[rec.flags], string.format(
                "course %d has two goals sharing star flag 0x%x", rec.course, rec.flags))
            seen[rec.flags] = true
        end
    end)

    s.test("exiting flushes pending removals", function()
        local api, ctl = fresh()
        api.remove_save_flag(api.goals[1])
        local before = ctl.save.saves
        api.flush_save_on_exit()
        t.ok(ctl.save.saves >= before, "exit path lost the pending removal")
    end)
end
