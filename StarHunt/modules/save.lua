-- StarHunt v1.1.1 - keeping StarHunt's stars out of the player's real save file.
--
-- StarHunt scores its own stars, so a star collected during a round must never
-- be left in the player's normal save. The removal is retried throughout the
-- round rather than done once: vanilla may write its star flag after the
-- interaction callback has run, and the player can close the game at any point.
--
-- The one thing in here that is easy to get wrong, and was wrong once, is the
-- course numbering. get_level_course_num() is one-based and the save API's
-- slots are zero-based. save_course_index_for() is the single place that
-- bridges the two; DEVELOPMENT_CHECKLIST.md lists the original bug.
--
-- star_flag_for, save_course_index_for and the pending-removal state are
-- private to this module: nothing outside it used them.

local is_round_active = require("core").is_round_active

local function star_flag_for(goal)
    return 1 << (goal.act - 1)
end

local function save_course_index_for(goal)
    -- get_level_course_num is one-based (BOB = 1), while the save API uses
    -- zero-based course slots (BOB = 0).
    return get_level_course_num(goal.level) - 1
end

-- StarHunt scores stars itself. Never leave its collected stars in the
-- player's normal save file, even if the game is closed mid-round with F12.
local pending_star_removals = {}
local next_star_cleanup_at = 0
local function remove_starhunt_save_flag(goal)
    local file = get_current_save_file_num() - 1
    local course = save_course_index_for(goal)
    local flag = star_flag_for(goal)
    save_file_remove_star_flags(file, course, flag)
    pending_star_removals[course] = (pending_star_removals[course] or 0) | flag
    next_star_cleanup_at = 0
    save_file_do_save(file, true)
    update_all_mario_stars()
end

local function flush_starhunt_save_removals(force, keep_pending)
    if next(pending_star_removals) == nil then return end
    if not force and is_round_active() and get_global_timer() < next_star_cleanup_at then return end
    local file = get_current_save_file_num() - 1
    for course, flags in pairs(pending_star_removals) do
        -- Keep removing throughout the active round. Vanilla may write its
        -- star flag after the interaction callback, and a player can close
        -- the game before a one-frame cleanup would have run.
        save_file_remove_star_flags(file, course, flags)
    end
    if force or not is_round_active() then save_file_do_save(file, true) end
    update_all_mario_stars()
    next_star_cleanup_at = get_global_timer() + 15
    if (force and not keep_pending) or not is_round_active() then pending_star_removals = {} end
end

local function flush_starhunt_save_on_warp()
    flush_starhunt_save_removals(true, true)
end

local function flush_starhunt_save_on_exit()
    flush_starhunt_save_removals(true, false)
end

local function goal_already_collected(goal)
    local file = get_current_save_file_num() - 1
    local course = save_course_index_for(goal)
    local flags = save_file_get_star_flags(file, course)
    return (flags & star_flag_for(goal)) ~= 0
end

return {
    remove_starhunt_save_flag = remove_starhunt_save_flag,
    flush_starhunt_save_removals = flush_starhunt_save_removals,
    flush_starhunt_save_on_warp = flush_starhunt_save_on_warp,
    flush_starhunt_save_on_exit = flush_starhunt_save_on_exit,
    goal_already_collected = goal_already_collected,
}
