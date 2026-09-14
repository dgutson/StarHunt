-- StarHunt static-analysis config.
-- The engine API list is generated from sm64coopdx's own autogen/lua_definitions
-- and lives outside this folder, because every .lua file inside a mod folder is
-- loaded by the game. See CLAUDE.md for the regeneration command.
local api = dofile(os.getenv("HOME") .. "/.local/share/sm64coopdx/luacheck_globals.lua")

std = "lua54"
read_globals = api.read
globals = api.write
max_line_length = false

-- STARHUNT_TEST_MODE is set by the harness; STARHUNT_TEST_API is published for it.
globals[#globals + 1] = "STARHUNT_TEST_API"
read_globals[#read_globals + 1] = "STARHUNT_TEST_MODE"
