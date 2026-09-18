-- StarHunt v1.1.2 - the two shared name spaces every other module builds on.
--
-- `SH` is the mod's general name space: the mode and difficulty axes, the
-- language, the HUD helpers, Bowser's health, the modifier readers, Chaos, the
-- menu and third-party compatibility. All of it applies in every mode.
--
-- `Team` is what is genuinely about Team mode: the colour axis, the rosters,
-- the palettes, the per-team scores and the balancing. Until these were split
-- apart there was one table called `Team` carrying both, and a comment here had
-- to warn the reader that `Team` was not a Team-mode table.
--
-- Both live here so each module can reach the same tables with
-- `local core = require("core")`. That is safe because neither is ever mutated
-- except by field assignment, and neither is ever rebound: every file gets the
-- same table by reference. A variable that IS rebound cannot be shared this way
-- -- Lua copies the value on `local x = other.x`, so a write in one module
-- would be invisible to the rest. That is why the per-player mutable state
-- lives on the `local_runtime` table instead of in top-level locals.
--
-- The team side is declared here rather than in team.lua because core requires
-- nothing, so every module can reach either table without a new require edge.
-- Declaring it in team.lua would force round.lua and hud.lua to require that
-- module for the colour axis alone.

local FRAMES_PER_SECOND = 30

-- Frames a player waits, after the round tells them where to go, before the
-- warp actually fires. The same delay covers all three destinations -- the next
-- star in a race, the Chaos map, the Boss arena -- so it sits here rather than
-- in any one of chaos.lua, round.lua or boss.lua.
local NEXT_GOAL_DELAY = 90

local SH = { manualRerollCooldown = 120 * FRAMES_PER_SECOND,
    rerollMenuIndex = nil, rerollMenuLabel = nil }

local Team = { initial = {},
    palettes = {}, paletteActive = false, paletteRefreshAt = 0 }

-- The mod has three unrelated axes -- which mode is being played, how hard it
-- is, and which team a player is on -- and all three are small integers that
-- start at 0. They used to be eleven flat fields on one table, so the mode,
-- the difficulty and the team colour each had a member equal to 0, and
-- the mode and the difficulty each had one equal to 3. Handing one axis to code
-- that expected another was therefore not an error anywhere: it matched a real
-- member of the wrong axis, and no test, luacheck run or lua-language-server
-- run in this project can see that. The three are adjacent in the code most
-- likely to make the mistake -- configured_time_range dispatches on the mode,
-- effective_modifier scales on the difficulty, and host_update_round reads
-- both.
--
-- Splitting them into three tables is the whole fix. A name off the wrong axis
-- now reads as nil, so the comparison that reads it is simply false rather than
-- true for the wrong reason, and `SH.Mode.NIGHTMARE` reads wrong where it is
-- written. Keep them three tables: putting any of these names back on `SH` or
-- on `Team` restores the collision, and test/suite/core.lua is what notices.
--
-- Every number is exactly what v1.1 shipped, because sh5_mode and
-- sh5_difficulty are synchronized: renumbering would make a released client and
-- a patched one disagree about what mode a lobby is in. The values are also
-- used arithmetically -- `% 4` when the menu cycles, `+ 1` as a table index,
-- `clamp(..., 0, 3)` -- which the same numbers keep working.
SH.Mode = { NORMAL = 0, BOSS = 1, TEAM = 2, CHAOS = 3 }
SH.Difficulty = { EASY = 0, MEDIUM = 1, HARD = 2, NIGHTMARE = 3 }
Team.Color = { NONE = 0, RED = 1, BLUE = 2 }

-- The host's record of every player it has seen this round, keyed by a stable
-- player key so a reconnecting player finds their own entry again.
--
-- It sits on `SH` rather than in a top-level local because `host_start_round`
-- REPLACES the whole table at the start of every round. Lua copies a value on
-- `local x = other.x`, so a module that re-localized it would go on reading the
-- previous round's table forever. As a field on the shared `SH` table the
-- replacement is visible to everyone. Round mode writes it; Team mode reads it
-- to total the scores of players who have disconnected.
SH.host_player_records = {}

-- The stable key that names a player's entry in the table above. The global
-- index survives a reconnect and a slot change, so it is preferred; the slot
-- is only a fallback for a player the network has not given one to yet.
--
-- It sits here with the table it keys rather than in round.lua, where it used
-- to live, because Team mode's score totals need it too and team.lua cannot
-- require round.lua: modifiers.lua already requires team.lua for
-- on_allow_pvp_attack, and round.lua requires modifiers.lua, so the import
-- would close a cycle.
local function player_record_key(player_index)
    local player = gNetworkPlayers[player_index]
    if player == nil then return nil end
    if player.globalIndex ~= nil then return "g:" .. tostring(player.globalIndex) end
    return "slot:" .. tostring(player_index)
end

-- Everything the local player's own frame-by-frame code needs to remember
-- between frames. It is per-player and never synchronized: the host's copy says
-- nothing about anyone else.
--
-- It is a table for the reason the header above gives. Most of these started as
-- separate top-level locals, and a local that gets REBOUND cannot be shared
-- across modules at all -- every module would get its own copy and the writes
-- would not meet. Collected here they are field assignments on one table that
-- every module reaches by reference, which is what made the split possible.
local local_runtime = {
    last_move_x = nil,
    last_move_z = nil,
    wind_tick = -1,
    freeze_tick = -1,
    freeze_frames = 0,
    freeze_yaw = nil,
    last_coin_count = nil,
    coin_leak_tick = -1,
    momentum_tick = -1,
    overheat_frames = 0,
    config_open = false,
    config_selection = 1,
    pause_menu_hidden = false,
    pause_selection = 1,
    menu_freeze_x = nil,
    menu_freeze_y = nil,
    menu_freeze_z = nil,
    power_external_timer = 0,
    power_original_head = false,
    lives_before_round = nil,
    native_hud_was_hidden = nil,
    dnc_compat_registered = false,
    widdlepets_compat_registered = false,
    gun_mod_compat_original = nil,
    gun_mod_compat_wrapper = nil,
    darkness_draw_frame = -1,
    chaos_round_seen = -1,
    chaos_warp_at = -1,
    chaos_spectator_warped = false,
    floor_frames = 0,
    slip_speed = 0,
    modifier_tick = -1,
    modifier_start_frame = 0,
    modifier_ready_key = nil,
    idle_frames = 0,
    jump_cooldown_frames = 0,
    done_lock = false,
    boss_round_seen = 0,
    boss_warp_at = -1,
    boss_hazard_seq = 0,
    boss_stun_frames = 0,
    boss_damage_lock = 0,
    pending_double_waves = {},
    pending_meteors = {},
    goal_id = 0,
    goal_warp_at = -1,
    death_lock = false,
    death_warp_pending = false,
    star_visibility_next = 0,
    rejected_stars = {},
    hidden_stars = {},
    hidden_players = {},
}

-- Bounds a value, used wherever a synchronized field or a menu index has to be
-- trusted from elsewhere. In core because it has no dependencies and callers
-- end up in most modules.
local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Whether the local player is standing on the ground. It is a plain read of
-- Mario's state with no modifier meaning of its own, and it sits here for the
-- same reason player_record_key does: the Boss hazards need it and boss.lua
-- cannot require modifiers.lua, where it used to live, because modifiers.lua
-- already requires boss.lua for BOSS_PLAYER_MODIFIERS.
local function is_local_player_on_floor(m)
    if m.floor == nil or (m.action & ACT_FLAG_SWIMMING) ~= 0 then return false end
    return math.abs(m.pos.y - m.floorHeight) < 22
end

-- Every modifier in the mod is this shape: a kind that selects the effect, a
-- value the effect reads, and the label shown on the HUD. The constructor is
-- here rather than with the modifier code because the goal catalog, the audit
-- catalog and the Boss catalogs all build modifiers, and they end up in three
-- different modules.
local function modifier(kind, value, label)
    return { kind = kind, value = value, label = label }
end

-- Which of the four modes is selected, and the three predicates over it.
--
-- The plan's appendix scattered these across team, boss and chaos, one
-- one-line predicate each. They sit here together instead: they are read from
-- almost every module (29 and 31 uses for the Boss and Chaos ones alone),
-- splitting four one-liners across three modules buys nothing, and
-- selected_mode falls back to Normal for any unrecognised value, which is the
-- behaviour all three inherit.
local function selected_mode()
    local mode = gGlobalSyncTable.sh5_mode
    if mode == SH.Mode.BOSS or mode == SH.Mode.TEAM or mode == SH.Mode.CHAOS then return mode end
    return SH.Mode.NORMAL
end

local function is_boss_mode()
    return selected_mode() == SH.Mode.BOSS
end

SH.is_team_mode = function()
    return selected_mode() == SH.Mode.TEAM
end

SH.is_chaos_mode = function()
    return selected_mode() == SH.Mode.CHAOS
end

-- Whether a StarHunt round is running. This is a read of synchronized state, so
-- it gives the same answer on the host and on every client. It lives here
-- because almost every module asks it: it is the most referenced function in
-- the mod.
local function is_round_active()
    return gGlobalSyncTable.sh5_active == 1
end

return {
    SH = SH,
    Team = Team,
    local_runtime = local_runtime,
    clamp = clamp,
    is_local_player_on_floor = is_local_player_on_floor,
    FRAMES_PER_SECOND = FRAMES_PER_SECOND,
    NEXT_GOAL_DELAY = NEXT_GOAL_DELAY,
    modifier = modifier,
    is_round_active = is_round_active,
    player_record_key = player_record_key,
    selected_mode = selected_mode,
    is_boss_mode = is_boss_mode,
}
