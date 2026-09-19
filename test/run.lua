#!/usr/bin/env lua5.4
-- StarHunt test suite entry point.
--
--   lua5.4 test/run.lua              run everything
--   lua5.4 test/run.lua audit save   run only suites whose file name matches
--
-- Must be run with lua5.4: the mod uses 5.3+ bitwise operators.

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
if not here:match("^[/\\]") then
    here = (os.getenv("PWD") or ".") .. "/" .. here
end

if _VERSION < "Lua 5.4" then
    io.stderr:write("StarHunt tests need lua5.4 (found " .. _VERSION .. ")\n")
    os.exit(1)
end

local runner = dofile(here .. "/runner.lua")
local harness = dofile(here .. "/harness.lua")

local filters = { ... }
local function wanted(name)
    if #filters == 0 then return true end
    for _, f in ipairs(filters) do
        if name:find(f, 1, true) then return true end
    end
    return false
end

-- Suite order is fixed rather than directory order, so a failure reads the same
-- way on every machine.
local suites = {
    "core", "catalog", "audit", "selfcheck", "difficulty", "pairing", "i18n",
    "clock", "save", "team", "world", "caps", "interact", "lobby", "lifetime", "hud", "hud_panels", "hud_frame", "menu", "mechanics", "modifiers", "boss", "boss_readers",
    "boss_hazards", "boss_health",
    "chaos", "pause_menu",
    "round", "round_host", "round_client",
}

local loaded = 0
for _, name in ipairs(suites) do
    if wanted(name) then
        local path = here .. "/suite/" .. name .. ".lua"
        local chunk, err = loadfile(path)
        if not chunk then
            io.stderr:write("cannot load suite " .. name .. ": " .. tostring(err) .. "\n")
            os.exit(1)
        end
        chunk()(runner, harness)
        loaded = loaded + 1
    end
end

if loaded == 0 then
    io.stderr:write("no suites matched\n")
    os.exit(1)
end

os.exit(runner.run() and 0 or 1)
