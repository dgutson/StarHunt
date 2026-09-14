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

return { Team = Team, FRAMES_PER_SECOND = FRAMES_PER_SECOND }
