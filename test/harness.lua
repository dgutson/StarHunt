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
        hud = { text = {}, rects = 0, textures = 0, colors = {} },
        popups = {},
        chat = {},
        save = { removed = {}, saves = 0, star_flags = {} },
        spawned = {},
        warps = {},
        screen = { w = 1920, h = 1009 },
        player_count = 2,
        bomb_count = 0,          -- what count_objects_with_behavior reports
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
    gServerSettings.skipIntro = 0
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
    function update_mod_menu_element_name(index, label)
        if ctl.menu_buttons[index] then ctl.menu_buttons[index].label = label end
    end

    function djui_hud_get_screen_width() return ctl.screen.w end
    function djui_hud_get_screen_height() return ctl.screen.h end
    function djui_hud_measure_text(text) return #tostring(text) * 8 end
    function djui_hud_print_text(text, x, y, scale)
        table.insert(ctl.hud.text, { text = text, x = x, y = y, scale = scale })
    end
    function djui_hud_set_color(r, g, b, a)
        ctl.hud.colors[#ctl.hud.colors + 1] = { r = r, g = g, b = b, a = a }
    end
    function djui_hud_render_rect() ctl.hud.rects = ctl.hud.rects + 1 end
    function djui_hud_render_texture() ctl.hud.textures = ctl.hud.textures + 1 end

    function djui_popup_create(msg) table.insert(ctl.popups, msg) end
    function djui_popup_create_global(msg) table.insert(ctl.popups, msg) end
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
    spawn_sync_object = spawn_non_sync_object

    function warp_to_level(level, area, act)
        table.insert(ctl.warps, { level = level, area = area, act = act })
    end

    function hud_is_hidden() return false end
    function hud_get_value() return 0 end

    function get_behavior_from_id(id) return { id = id } end
    function count_objects_with_behavior() return ctl.bomb_count end
    function obj_has_behavior_id() return false end
    function dist_between_objects() return 0 end

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
    local real_print = print
    local banner = {}
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        banner[#banner + 1] = table.concat(parts, "\t")
    end
    local ok, loaderr = pcall(chunk)
    _G.print = real_print

    if not ok then error("mod failed to load: " .. tostring(loaderr), 0) end
    if STARHUNT_TEST_API == nil then
        error("mod loaded but published no STARHUNT_TEST_API", 0)
    end
    harness.banner = banner
    return STARHUNT_TEST_API, harness.ctl
end

return harness
