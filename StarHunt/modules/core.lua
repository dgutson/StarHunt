-- StarHunt v1.1 - the shared namespace every other module builds on.
--
-- `Team` is the mod's general namespace, not a Team-mode table. Its name is
-- historical: it carries the mode, difficulty and team constants alongside most
-- cross-cutting functions and mutable state, in every mode.
--
-- It lives here so each module can reach the same table with
-- `local Team = require("core")`. That is safe because `Team` is only ever
-- mutated by field assignment and is never rebound: every file gets the same
-- table by reference. A variable that IS rebound cannot be shared this way --
-- Lua copies the value on `local x = other.x`, so a write in one module would
-- be invisible to the rest. That is why the per-player mutable state lives on
-- the `local_runtime` table instead of in top-level locals.

local FRAMES_PER_SECOND = 30

local Team = { NORMAL = 0, BOSS = 1, MODE = 2, CHAOS = 3,
    EASY = 0, MEDIUM = 1, HARD = 2, NIGHTMARE = 3,
    NONE = 0, RED = 1, BLUE = 2, initial = {},
    palettes = {}, paletteActive = false, paletteRefreshAt = 0,
    manualRerollCooldown = 120 * FRAMES_PER_SECOND,
    rerollMenuIndex = nil, rerollMenuLabel = nil }

-- Every modifier in the mod is this shape: a kind that selects the effect, a
-- value the effect reads, and the label shown on the HUD. The constructor is
-- here rather than with the modifier code because the goal catalog, the audit
-- catalog and the Boss catalogs all build modifiers, and they end up in three
-- different modules.
local function modifier(kind, value, label)
    return { kind = kind, value = value, label = label }
end

-- Whether a StarHunt round is running. This is a read of synchronized state, so
-- it gives the same answer on the host and on every client. It lives here
-- because almost every module asks it: it is the most referenced function in
-- the mod.
local function is_round_active()
    return gGlobalSyncTable.sh5_active == 1
end

return {
    Team = Team,
    FRAMES_PER_SECOND = FRAMES_PER_SECOND,
    modifier = modifier,
    is_round_active = is_round_active,
}
