-- Loads StarHunt outside sm64coopdx.
--
-- The mod is loaded with a stubbed engine (test/engine_stub.lua) and driven
-- through STARHUNT_TEST_API, the table main.lua publishes when the global
-- STARHUNT_TEST_MODE is set.  Nothing here knows how the mod is split into
-- files: the same harness works for one main.lua or for main.lua plus modules.

local harness = {}

-- Resolve paths from this file's own location, so the suite runs the same way
-- from any working directory.
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
if not here:match("^[/\\]") then
    here = (os.getenv("PWD") or ".") .. "/" .. here
end
local root = here:gsub("[/\\][^/\\]+$", "")   -- strip the trailing "test"
harness.root = root
harness.mod_root = root .. "/StarHunt"

-- ---------------------------------------------------------------------------
-- require(), matching sm64coopdx
-- ---------------------------------------------------------------------------
-- The game resolves a module name as a path relative to the folder of the file
-- doing the requiring, appends ".lua", and caches the result per mod.  Standard
-- Lua's dotted package.path lookup would accept module names the game rejects,
-- so we reproduce the game's rule instead and keep the tests honest.

local function normalize(path)
    local parts = {}
    for piece in path:gmatch("[^/]+") do
        if piece == ".." then
            table.remove(parts)
        elseif piece ~= "." then
            parts[#parts + 1] = piece
        end
    end
    return table.concat(parts, "/")
end

local function install_require()
    local cache = {}
    local folder_stack = { "" }          -- folder of the file currently running

    local function coopdx_require(name)
        if type(name) ~= "string" then
            error("require() expects a string, got " .. type(name), 2)
        end
        if name:sub(-1) == "/" then
            error("cannot require a directory: " .. name, 2)
        end
        local base = folder_stack[#folder_stack]
        local rel = normalize((base ~= "" and (base .. "/") or "") .. name)
        if cache[rel] ~= nil then return cache[rel] end

        local path = harness.mod_root .. "/" .. rel .. ".lua"
        local chunk, err = loadfile(path)
        if not chunk then
            error(("module '%s' not found in mod files (looked for %s)\n%s")
                :format(name, rel .. ".lua", tostring(err)), 2)
        end
        cache[rel] = true                -- mark loading, so cycles fail loudly
        folder_stack[#folder_stack + 1] = rel:match("^(.*)/[^/]*$") or ""
        local ok, result = pcall(chunk)
        table.remove(folder_stack)
        if not ok then
            cache[rel] = nil
            error(result, 0)
        end
        if result == nil then result = true end
        cache[rel] = result
        return result
    end

    _G.require = coopdx_require
    return cache
end

-- ---------------------------------------------------------------------------
-- engine doubles
-- ---------------------------------------------------------------------------

local function install_engine()
    local stub = dofile(root .. "/test/engine_stub.lua")

    local ctl = {
        is_server = true,
        timer = 0,
        storage = {},
        hooks = {},              -- hook type -> list of functions
        chat_commands = {},
        menu_buttons = {},
        menu_renames = {},     -- every update_mod_menu_element_name call
        -- values: the game's HUD display values, keyed by HUD_DISPLAY_*.
        -- hidden: whether the native HUD is hidden, as hud_is_hidden reports it.
        -- rect_calls and texture_calls keep every shape with the colour that
        -- was in force when it was drawn, and each text call carries the same
        -- colour, which is how a panel's layout can be pinned at all.
        hud = { text = {}, rects = 0, textures = 0, colors = {},
                rect_calls = {}, texture_calls = {}, color = nil, font = nil,
                values = {}, hidden = false },
        popups = {},
        chat = {},
        save = { removed = {}, saves = 0, star_flags = {} },
        spawned = {},
        objects = {},            -- behavior id -> obj_get_first_with_behavior_id result
        level_objects = {},      -- what obj_get_first/obj_get_next walk
        deleted = {},            -- every obj_mark_for_deletion call
        warps = {},
        screen = { w = 1920, h = 1009 },
        player_count = 2,
        bomb_count = 0,          -- what count_objects_with_behavior reports
        spawn_failures = 0,      -- how many of the next spawn_sync_object calls fail
        owned_sync_ids = {},     -- sync id -> true; drives sync_object_is_owned_locally
        sent_objects = {},       -- every network_send_object call
        transition = false,      -- what is_transition_playing reports
        paused = false,          -- whether the game is on the pause screen
        pause_menu_hidden = false,  -- whether the game draws its own pause rows
        unpauses = 0,            -- every game_unpause call
        ttc_speed = TTC_SPEED_SLOW,  -- what get_ttc_speed_setting reports
        ttc_speed_writes = 0,    -- how many times set_ttc_speed_setting was called
        mario_actions = {},      -- every set_mario_action call
        camera_resets = 0,       -- every soft_reset_camera call
    }
    harness.ctl = ctl

    -- SM64 course numbers for the levels StarHunt uses.  get_level_course_num is
    -- one-based (BOB = 1); the save API is zero-based, and the mod's
    -- save_course_index_for() is what bridges the two.
    local COURSE_OF = {
        [LEVEL_BOB] = 1,  [LEVEL_WF] = 2,  [LEVEL_JRB] = 3,  [LEVEL_CCM] = 4,
        [LEVEL_BBH] = 5,  [LEVEL_HMC] = 6, [LEVEL_LLL] = 7,  [LEVEL_SSL] = 8,
        [LEVEL_DDD] = 9,  [LEVEL_SL] = 10, [LEVEL_WDW] = 11, [LEVEL_TTM] = 12,
        [LEVEL_THI] = 13, [LEVEL_TTC] = 14, [LEVEL_RR] = 15,
        [LEVEL_TOTWC] = 19, [LEVEL_COTMC] = 20, [LEVEL_VCUTM] = 21,
    }
    ctl.course_of = COURSE_OF
    function get_level_course_num(level) return COURSE_OF[level] or 0 end

    -- players ----------------------------------------------------------------
    for i = 0, 15 do
        gPlayerSyncTable[i] = {}
        gNetworkPlayers[i] = {
            connected = i < ctl.player_count, globalIndex = i, localIndex = i,
            name = "P" .. i, modelIndex = 0, currLevelNum = 0, currAreaIndex = 0,
            currActNum = 1, currLevelArea = 0, overrideModelIndex = 0,
        }
        gMarioStates[i] = {
            playerIndex = i, health = 0x880, numLives = 4, action = 0, forwardVel = 0,
            vel = { x = 0, y = 0, z = 0 }, pos = { x = 0, y = 0, z = 0 },
            faceAngle = { x = 0, y = 0, z = 0 }, area = { camera = {} },
            controller = { buttonDown = 0, buttonPressed = 0, stickX = 0, stickY = 0,
                           stickMag = 0, extStickX = 0, extStickY = 0 },
            marioObj = nil, flags = 0, capTimer = 0, invincTimer = 0, hurtCounter = 0,
            squishTimer = 0, peakHeight = 0, waterLevel = 0, floorHeight = 0,
            marioBodyState = {}, statusForCamera = {},
        }
    end
    -- Team mode overwrites every player's palette and has to put the original
    -- back when the round ends, so the stub keeps a real per-player store
    -- instead of discarding the writes. Each player starts with a palette of
    -- their own, so a restore that returns the WRONG original is still wrong.
    ctl.palettes = {}
    for i = 0, 15 do
        ctl.palettes[i] = {}
        for part = PANTS, EMBLEM do
            ctl.palettes[i][part] = { r = 10 + i, g = 20 + part, b = 30 + i }
        end
    end
    function network_player_get_override_palette_color(player, part)
        local c = ctl.palettes[player.globalIndex][part]
        return { r = c.r, g = c.g, b = c.b }
    end
    function network_player_set_override_palette_color(player, part, color)
        ctl.palettes[player.globalIndex][part] = { r = color.r, g = color.g, b = color.b }
    end

    gServerSettings.skipIntro = 0
    -- The engine's own default for the field the mod asks about at load.
    gLevelValues.crossActPlayers = 0
    gServerSettings.playerInteractions = 1

    -- functions the tests observe or steer ------------------------------------
    function network_is_server() return ctl.is_server end
    function get_global_timer() return ctl.timer end
    function get_current_save_file_num() return 1 end
    function network_local_index_from_global(i) return i end

    function mod_storage_load(key) return ctl.storage[key] end
    function mod_storage_save(key, value) ctl.storage[key] = value; return true end

    function hook_event(kind, fn)
        ctl.hooks[kind] = ctl.hooks[kind] or {}
        table.insert(ctl.hooks[kind], fn)
    end
    function hook_chat_command(name, desc, fn)
        table.insert(ctl.chat_commands, { name = name, description = desc, fn = fn })
    end
    function hook_mod_menu_button(label, fn)
        table.insert(ctl.menu_buttons, { label = label, fn = fn })
        return #ctl.menu_buttons
    end
    -- Every rename is recorded, including one aimed at an index that does not
    -- exist. update_manual_reroll_menu is guarded against an engine with no mod
    -- menu, and a test can only see that guard hold if the call it must not
    -- make leaves a trace.
    function update_mod_menu_element_name(index, label)
        table.insert(ctl.menu_renames, { index = index, label = label })
        if ctl.menu_buttons[index] then ctl.menu_buttons[index].label = label end
    end

    function djui_hud_get_screen_width() return ctl.screen.w end
    function djui_hud_get_screen_height() return ctl.screen.h end
    function djui_hud_measure_text(text) return #tostring(text) * 8 end
    local function current_color()
        local c = ctl.hud.color or {}
        return c.r, c.g, c.b, c.a
    end
    function djui_hud_print_text(text, x, y, scale)
        local r, g, b, a = current_color()
        table.insert(ctl.hud.text,
            { text = text, x = x, y = y, scale = scale, r = r, g = g, b = b, a = a })
    end
    function djui_hud_set_color(r, g, b, a)
        ctl.hud.colors[#ctl.hud.colors + 1] = { r = r, g = g, b = b, a = a }
        ctl.hud.color = { r = r, g = g, b = b, a = a }
    end
    -- The generated stub discarded the rectangle's position and size, so a
    -- darkness rectangle ten pixels wide looked exactly like one covering the
    -- screen.  Same for the resolution it is drawn in.  It also discarded the
    -- texture's position and scale, and every panel in the HUD is a stack of
    -- rectangles, so a panel could be moved or resized with nothing noticing.
    function djui_hud_render_rect(x, y, w, h)
        ctl.hud.rects = ctl.hud.rects + 1
        ctl.hud.last_rect = { x = x, y = y, w = w, h = h }
        local r, g, b, a = current_color()
        ctl.hud.rect_calls[#ctl.hud.rect_calls + 1] =
            { x = x, y = y, w = w, h = h, r = r, g = g, b = b, a = a }
    end
    function djui_hud_set_resolution(resolution) ctl.hud.resolution = resolution end
    function djui_hud_set_font(font) ctl.hud.font = font end
    function djui_hud_render_texture(texture, x, y, scale_x, scale_y)
        ctl.hud.textures = ctl.hud.textures + 1
        local r, g, b, a = current_color()
        ctl.hud.texture_calls[#ctl.hud.texture_calls + 1] =
            { texture = texture, x = x, y = y, scale_x = scale_x, scale_y = scale_y,
              r = r, g = g, b = b, a = a }
    end
    -- The generated stub leaves gTextures empty, and the star and the coin the
    -- status panel draws are both behind an `if gTextures.x ~= nil` guard, so
    -- neither icon was reachable from a test at all.
    gTextures.star = "TEX_STAR"
    gTextures.coin = "TEX_COIN"

    -- The popup's second argument is its height in lines.  Recording it keeps
    -- a wrong value from being invisible to the suite.
    function djui_popup_create(msg, lines)
        table.insert(ctl.popups, { text = msg, lines = lines })
    end
    djui_popup_create_global = djui_popup_create
    function djui_chat_message_create(msg) table.insert(ctl.chat, msg) end

    function save_file_get_star_flags(file, course)
        return (ctl.save.star_flags[file] or {})[course] or 0
    end
    function save_file_remove_star_flags(file, course, flags)
        ctl.save.removed[#ctl.save.removed + 1] = { file = file, course = course, flags = flags }
    end
    function save_file_do_save() ctl.save.saves = ctl.save.saves + 1 end

    function spawn_non_sync_object(bhv, model, x, y, z, setup)
        local obj = { behavior = bhv, model = model, oPosX = x, oPosY = y, oPosZ = z }
        table.insert(ctl.spawned, obj)
        if setup ~= nil then setup(obj) end
        return obj
    end
    -- A synchronized spawn can fail in a real session, and the reserve bomb
    -- wave publishes only the creations that succeeded so it can supply the
    -- rest later.  ctl.spawn_failures is how many of the next calls return nil.
    function spawn_sync_object(bhv, model, x, y, z, setup)
        if ctl.spawn_failures > 0 then
            ctl.spawn_failures = ctl.spawn_failures - 1
            return nil
        end
        return spawn_non_sync_object(bhv, model, x, y, z, setup)
    end

    function warp_to_level(level, area, act)
        table.insert(ctl.warps, { level = level, area = area, act = act })
    end

    -- The generated stub returns nil for this, so a guard that holds a warp back
    -- during a level transition could be deleted without any test noticing.
    function is_transition_playing() return ctl.transition end

    -- The pause screen, as far as the mod can reach it.  ctl.paused is whether
    -- the game is on the pause screen at all, ctl.pause_menu_hidden is the flag
    -- that decides whether the game draws its own rows and reads A and START,
    -- and ctl.unpauses counts the mod's own way out of the pause.  game_unpause
    -- clears ctl.paused because the engine's next frame does: play_mode_paused
    -- returns to PLAY_MODE_NORMAL from gPauseScreenMode = 1.
    function is_game_paused() return ctl.paused end
    function set_pause_menu_hidden(hidden) ctl.pause_menu_hidden = hidden and true or false end
    function is_pause_menu_hidden() return ctl.pause_menu_hidden end
    function game_unpause()
        ctl.unpauses = ctl.unpauses + 1
        ctl.paused = false
    end

    -- TTC's clock runs at whatever speed the castle clock face was entered at,
    -- and StarHunt warps straight in, so it sets the speed itself.  The
    -- generated stub returned nil from the reader and discarded the write, so
    -- the reader never matched and the `~=` guard was dead either way: both the
    -- guard and the choice of speed could be deleted with the suite still green.
    -- ctl.ttc_speed is what the setting currently is and ctl.ttc_speed_writes
    -- counts the writes, so a test can tell "set it" from "left it alone".
    --- @return integer
    function get_ttc_speed_setting() return ctl.ttc_speed end
    function set_ttc_speed_setting(speed)
        ctl.ttc_speed = speed
        ctl.ttc_speed_writes = ctl.ttc_speed_writes + 1
    end

    -- Both were no-ops.  Boss mode's death respawn puts Mario back in the arena
    -- by hand rather than reloading the level, and the two calls that finish it
    -- -- dropping him into a freefall and pointing the camera back at him --
    -- were the half of that the suite could not see.
    function set_mario_action(m, action, arg)
        table.insert(ctl.mario_actions,
            { index = m.playerIndex, action = action, arg = arg })
    end
    function soft_reset_camera(_) ctl.camera_resets = ctl.camera_resets + 1 end

    -- All five of these were no-ops: the generated stub threw away every write
    -- and the two hand-written readers answered with a constant.  That made the
    -- whole of apply_counter_visibility and update_native_hud_visibility
    -- unobservable -- the star/coin flags StarHunt saves before a round and
    -- restores after it could be deleted with the suite still green.  A test
    -- puts the player's starting HUD in ctl.hud.values and ctl.hud.hidden and
    -- reads the same two back afterwards.
    --- @return boolean
    function hud_is_hidden() return ctl.hud.hidden end
    --- @return integer
    function hud_get_value(kind)
        --- @diagnostic disable-next-line: return-type-mismatch
        return ctl.hud.values[kind] or 0
    end
    function hud_set_value(kind, value) ctl.hud.values[kind] = value end
    function hud_hide() ctl.hud.hidden = true end
    function hud_show() ctl.hud.hidden = false end

    function get_behavior_from_id(id) return { id = id } end
    -- The generated stub returns nil here, which silently made the whole Boss
    -- attack queue unreachable: with no Bowser object the host loop decides he
    -- is not ready and returns before ever choosing an attack.  Tests put the
    -- object they want in ctl.objects, keyed by behavior id.
    function obj_get_first_with_behavior_id(id) return ctl.objects[id] end
    -- The first stub ignored its argument and answered ctl.bomb_count for
    -- anything, so asking the engine to count the wrong behavior was invisible.
    -- get_behavior_from_id above returns { id = <behavior id> }; the mod counts
    -- only Bowser's bombs, and every other behavior reports none.
    function count_objects_with_behavior(behavior)
        if behavior == nil or behavior.id ~= id_bhvBowserBomb then return 0 end
        return ctl.bomb_count
    end
    -- The generated stub returns nil for both of these, which makes the whole
    -- second half of ensure_boss_health_owner unreachable: nothing is ever
    -- owned locally, so the function returns before it can initialize or
    -- publish Bowser's health.  A test marks the sync ids it owns in
    -- ctl.owned_sync_ids and reads the publications back from ctl.sent_objects.
    function sync_object_is_owned_locally(sync_id)
        return ctl.owned_sync_ids[sync_id] == true
    end
    function network_send_object(object, reliable)
        table.insert(ctl.sent_objects, { object = object, reliable = reliable })
    end
    -- The generated stub returns nil here and the first hand-written
    -- replacement returned `false`, so `obj_has_behavior_id(o, id) == 0` was
    -- never true and the HMC Metal Cap portal guard in goals.lua could not be
    -- tested at all.  Objects carry their behavior in `behavior_id`.
    function obj_has_behavior_id(object, id)
        if object ~= nil and object.behavior_id == id then return 1 end
        return 0
    end
    function obj_mark_for_deletion(object) table.insert(ctl.deleted, object) end
    -- obj_get_first returns nil from the generated stub, which makes the whole
    -- body of update_star_visibility unreachable: the walk over the level's
    -- object list never runs one iteration.  Tests put the objects they want
    -- the level to contain in ctl.level_objects, in order.
    --
    -- The two annotations below, and the suppressions under them, are not
    -- decoration.  lua-language-server merges a global defined here with the
    -- engine definition of the same name, so a stub it reads as returning
    -- `unknown|nil` turns the `object = obj_get_next(object)` walk in goals.lua
    -- into a type error.  sm64coopdx declares `@return Object` for both of these
    -- and returns NULL at the end of the list anyway; the stub matches the
    -- declaration and suppresses the same inaccuracy, exactly as is already
    -- recorded for `save_file_do_save(file, true)`.
    --- @return Object
    function obj_get_first(list)
        --- @diagnostic disable-next-line: return-type-mismatch
        if list ~= OBJ_LIST_LEVEL then return nil end
        return ctl.level_objects[1]
    end
    --- @return Object
    function obj_get_next(object)
        for i, o in ipairs(ctl.level_objects) do
            if o == object then return ctl.level_objects[i + 1] end
        end
        --- @diagnostic disable-next-line: return-type-mismatch
        return nil
    end
    -- The generated stub returns nil and the first hand-written replacement
    -- returned 0 for every pair, so `distance < 4800` in Bowser's shockwave was
    -- true whatever the two objects' positions were and the range that decides
    -- whether a wave stuns the local player could not be tested at all.
    function dist_between_objects(a, b)
        if a == nil or b == nil then return 0 end
        local dx = (a.oPosX or 0) - (b.oPosX or 0)
        local dy = (a.oPosY or 0) - (b.oPosY or 0)
        local dz = (a.oPosZ or 0) - (b.oPosZ or 0)
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    -- The generated stub returns nil, which does not merely disable Bowser's
    -- hunter fire but crashes it: the attack reads the yaw towards Mario and
    -- then adds and subtracts 0x0800 from it. sm64coopdx declares
    -- `s16 atan2s(f32 y, f32 x)` and its callers read the result as a yaw, so
    -- the stub answers with the same angle on the same 0x10000-unit circle.
    function atan2s(y, x)
        return math.floor(math.atan(y, x) * 0x8000 / math.pi) % 0x10000
    end

    -- The generated stub discards its arguments, so every flame Bowser spawns
    -- had an unobservable size and the three attacks that scale their flames
    -- differently were indistinguishable.
    function obj_scale(object, scale)
        if object ~= nil then object.scale = scale end
    end

    --- Put the mod into an active round of `mode` at `difficulty`.
    -- Round state is synchronized, so tests that exercise host logic have to
    -- set it the way the host would rather than calling into private state.
    function ctl.begin_round(api, mode, difficulty, level)
        gGlobalSyncTable.sh5_active = 1
        gGlobalSyncTable.sh5_round = (gGlobalSyncTable.sh5_round or 0) + 1
        gGlobalSyncTable.sh5_mode = mode
        gGlobalSyncTable.sh5_difficulty = difficulty
        gGlobalSyncTable.sh5_start_frame = ctl.timer
        gGlobalSyncTable.sh5_end_frame = ctl.timer + 60 * 60
        if level ~= nil then
            for i = 0, 15 do gNetworkPlayers[i].currLevelNum = level end
        end
        return api
    end

    return stub
end

-- ---------------------------------------------------------------------------

--- Run `fn` with print() captured, and return the lines it wrote.
-- The mod reports a failed self-check by printing rather than by raising, so a
-- test that wants to see one has to read what it wrote. Returns the captured
-- lines, then the pcall status and error, so the caller decides what a throw
-- means; the real print is restored either way.
-- harness.capture_print(fn) -> lines, ok, err
function harness.capture_print(fn)
    local real_print = print
    local lines = {}
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, "\t")
    end
    local ok, err = pcall(fn)
    _G.print = real_print
    return lines, ok, err
end

--- Load the mod fresh and return its test API.
-- Every call re-executes the mod from disk with a clean engine, so a test that
-- changes synchronized state cannot leak into the next one.
-- harness.load(setup)
--
-- `setup` is optional and runs after the engine stub is installed but before
-- main.lua executes, which is the only window in which a test can stage what
-- the mod reads AT LOAD TIME -- stored settings, most importantly. Anything
-- that can be set afterwards should be, through the returned control table.
function harness.load(setup)
    -- wipe anything a previous load left behind
    STARHUNT_TEST_API = nil
    for _, name in ipairs({ "gGlobalSyncTable", "gPlayerSyncTable", "gNetworkPlayers",
                            "gMarioStates", "gServerSettings", "gBehaviorValues", "gTextures" }) do
        _G[name] = nil
    end
    -- StarHunt reaches other mods through rawget(_G, ...), so a test fakes one
    -- by installing the global itself.  None of these is part of the engine
    -- stub, so nothing else would ever clear them and a faked Gun Mod would
    -- still be installed in every suite that ran afterwards.
    for _, name in ipairs({ "gunModApi", "TEX_CROSSHAIR", "get_first_person_enabled",
                            "is_game_paused", "id_bhvActSelector" }) do
        _G[name] = nil
    end

    install_engine()
    install_require()
    STARHUNT_TEST_MODE = true

    if setup ~= nil then
        if type(setup) ~= "function" then
            error("harness.load: setup must be a function, got " .. type(setup), 2)
        end
        setup(harness.ctl)
    end

    local entry = harness.mod_root .. "/main.lua"
    local chunk, err = loadfile(entry)
    if not chunk then error("cannot load " .. entry .. ": " .. tostring(err), 0) end

    -- the mod prints its self-check banner on load; keep test output readable
    local banner, ok, loaderr = harness.capture_print(chunk)

    if not ok then error("mod failed to load: " .. tostring(loaderr), 0) end
    if STARHUNT_TEST_API == nil then
        error("mod loaded but published no STARHUNT_TEST_API", 0)
    end
    harness.banner = banner
    return STARHUNT_TEST_API, harness.ctl
end

return harness
