-- The goal catalog: the 93 hand-picked stars and the 32-modifier catalog.
-- These numbers are published in CHANGELOG.md and BALANCE_AUDIT.md, so a
-- refactor that quietly drops or duplicates an entry has to fail here.

return function(t, harness)
    local s = t.suite("catalog")
    local api = harness.load()

    local MAIN_COURSES = {
        "LEVEL_BOB", "LEVEL_WF", "LEVEL_JRB", "LEVEL_CCM", "LEVEL_BBH",
        "LEVEL_HMC", "LEVEL_LLL", "LEVEL_SSL", "LEVEL_DDD", "LEVEL_SL",
        "LEVEL_WDW", "LEVEL_TTM", "LEVEL_THI", "LEVEL_TTC", "LEVEL_RR",
    }
    local CAP_COURSES = { "LEVEL_TOTWC", "LEVEL_COTMC", "LEVEL_VCUTM" }

    local function is_main_course(level)
        for _, name in ipairs(MAIN_COURSES) do
            if _G[name] == level then return true end
        end
        return false
    end

    s.test("has exactly 93 goals", function()
        t.eq(#api.goals, 93)
    end)

    s.test("catalog has exactly 32 modifiers, all of distinct kinds", function()
        t.eq(#api.normal_modifier_catalog, 32)
        local seen = {}
        for _, m in ipairs(api.normal_modifier_catalog) do
            t.ok(not seen[m.kind], "duplicate modifier kind: " .. tostring(m.kind))
            seen[m.kind] = true
        end
    end)

    s.test("every goal is fully described in both languages", function()
        for i, goal in ipairs(api.goals) do
            local where = "goal " .. i
            t.ok(type(goal.level) == "number", where .. " has no level")
            t.ok(type(goal.act) == "number" and goal.act >= 1 and goal.act <= 7,
                where .. " has a bad act: " .. tostring(goal.act))
            for _, field in ipairs({ "world", "world_es", "title", "title_es" }) do
                t.ok(type(goal[field]) == "string" and #goal[field] > 0,
                    where .. " is missing " .. field)
            end
        end
    end)

    s.test("no 100-coin star reached the catalog", function()
        -- Act 7 on a main course is that course's 100-coin star. BALANCE_AUDIT.md
        -- states all fifteen stay excluded.
        for i, goal in ipairs(api.goals) do
            if is_main_course(goal.level) then
                t.ne(goal.act, 7, "goal " .. i .. " is a 100-coin star")
            end
        end
    end)

    s.test("every level/act pair appears at most once", function()
        local seen = {}
        for i, goal in ipairs(api.goals) do
            local key = tostring(goal.level) .. "/" .. tostring(goal.act)
            t.ok(not seen[key], "goal " .. i .. " repeats level/act " .. key
                .. " (first seen at goal " .. tostring(seen[key]) .. ")")
            seen[key] = i
        end
    end)

    s.test("covers all fifteen main courses and the three cap courses", function()
        local present = {}
        for _, goal in ipairs(api.goals) do present[goal.level] = true end
        for _, name in ipairs(MAIN_COURSES) do
            t.ok(present[_G[name]], "no goal in " .. name)
        end
        for _, name in ipairs(CAP_COURSES) do
            t.ok(present[_G[name]], "no goal in " .. name)
        end
    end)

    s.test("required powers are ones the mod can actually grant", function()
        local allowed = { wing = true, metal = true, vanish = true, metal_vanish = true }
        for i, goal in ipairs(api.goals) do
            if goal.power ~= nil then
                t.ok(allowed[goal.power], "goal " .. i .. " needs unknown power "
                    .. tostring(goal.power))
            end
        end
    end)

    s.test("every goal keeps at least one usable modifier", function()
        -- A goal whose modifiers were all rejected would hand the player an
        -- objective with no challenge at all.
        for i, goal in ipairs(api.goals) do
            t.ok(type(goal.mods) == "table" and #goal.mods > 0,
                "goal " .. i .. " has no approved modifier")
        end
    end)

    s.test("approved modifiers are catalog kinds, never duplicated per goal", function()
        local known = {}
        for _, m in ipairs(api.normal_modifier_catalog) do known[m.kind] = true end
        for i, goal in ipairs(api.goals) do
            local seen = {}
            for _, m in ipairs(goal.mods) do
                t.ok(known[m.kind], "goal " .. i .. " has non-catalog modifier " .. tostring(m.kind))
                t.ok(not seen[m.kind], "goal " .. i .. " repeats modifier " .. tostring(m.kind))
                seen[m.kind] = true
            end
        end
    end)

    s.test("cursed floor stays inside its 4..9 second band", function()
        -- Shorter than 4s is unreachable; longer than 9s stops being a threat.
        -- 9s is the documented allowance for slow platform routes.
        for i, goal in ipairs(api.goals) do
            for _, m in ipairs(goal.mods) do
                if m.kind == "floor_doom" then
                    t.ok(m.value >= 4 and m.value <= 9,
                        "goal " .. i .. " cursed floor is " .. tostring(m.value) .. "s")
                end
            end
        end
    end)

    s.test("the eighteen world names are the ones the mod ships", function()
        -- Catches the two columns being swapped, which nothing else does: every
        -- goal carries both an English and a Spanish world name, and both are
        -- non-empty either way round.
        local expected = {
            LEVEL_BOB = { "BOB-OMB BATTLEFIELD", "CAMPO DE BATALLA BOB-OMB" },
            LEVEL_WF = { "WHOMP'S FORTRESS", "FORTALEZA DE WHOMP" },
            LEVEL_JRB = { "JOLLY ROGER BAY", "BAHIA DEL PIRATA" },
            LEVEL_CCM = { "COOL, COOL MOUNTAIN", "MONTANA ESCALOFRIANTE" },
            LEVEL_BBH = { "BIG BOO'S HAUNT", "MANSION DE BIG BOO" },
            LEVEL_HMC = { "HAZY MAZE CAVE", "CUEVA DEL LABERINTO" },
            LEVEL_LLL = { "LETHAL LAVA LAND", "FOSO DE LAVA LETAL" },
            LEVEL_SSL = { "SHIFTING SAND LAND", "ARENAS MOVEDIZAS" },
            LEVEL_DDD = { "DIRE, DIRE DOCKS", "MUELLE DIRE, DIRE" },
            LEVEL_SL = { "SNOWMAN'S LAND", "TIERRA DEL HOMBRE DE NIEVE" },
            LEVEL_WDW = { "WET-DRY WORLD", "MUNDO MOJADO-SECO" },
            LEVEL_TTM = { "TALL, TALL MOUNTAIN", "MONTANA ALTA, ALTA" },
            LEVEL_THI = { "TINY-HUGE ISLAND", "ISLA PEQUENA-GIGANTE" },
            LEVEL_TTC = { "TICK TOCK CLOCK", "RELOJ TIC TAC" },
            LEVEL_RR = { "RAINBOW RIDE", "PASEO POR EL ARCOIRIS" },
            LEVEL_TOTWC = { "TOWER OF THE WING CAP", "TORRE DE LA GORRA ALADA" },
            LEVEL_COTMC = { "CAVERN OF THE METAL CAP", "CUEVA DE LA GORRA METALICA" },
            LEVEL_VCUTM = { "VANISH CAP UNDER THE MOAT", "GORRA INVISIBLE BAJO EL FOSO" },
        }
        local by_level = {}
        for name, pair in pairs(expected) do by_level[_G[name]] = pair end

        local seen = {}
        for i, goal in ipairs(api.goals) do
            local pair = by_level[goal.level]
            t.ok(pair ~= nil, "goal " .. i .. " is in an unknown level")
            t.eq(goal.world, pair[1], "goal " .. i .. " world name")
            t.eq(goal.world_es, pair[2], "goal " .. i .. " Spanish world name")
            seen[goal.level] = true
        end
        for name in pairs(expected) do
            t.ok(seen[_G[name]], "no goal in " .. name)
        end
    end)

    s.test("the catalog data is byte-for-byte what v1.1 shipped", function()
        -- v1.1 shipped this star list, and no maintenance update since has
        -- changed a title, an order or a hand-tuned modifier value, so it is
        -- fixed data. This digest is
        -- the one check that notices a star being silently retitled, reordered or
        -- retuned -- including an English and Spanish column swapped over.
        --
        -- If you changed the catalog ON PURPOSE, the run prints the new digest:
        -- read the diff first, then paste the number in below.
        local function fnv1a(text)
            local h = 0xcbf29ce484222325
            for i = 1, #text do
                h = (h ~ text:byte(i)) * 0x100000001b3
            end
            return h
        end

        local parts = {}
        for _, goal in ipairs(api.goals) do
            parts[#parts + 1] = table.concat({
                goal.level, goal.act, goal.world, goal.world_es,
                goal.title, goal.title_es, goal.power or "-",
            }, "|")
            for _, m in ipairs(goal.mods) do
                -- Only the hand-tuned entries are catalog data. The rest are
                -- catalog defaults that modules/audit.lua fills in.
                if m.hand_tuned then
                    parts[#parts + 1] = "  " .. m.kind .. "=" .. tostring(m.value)
                end
            end
        end
        local actual = string.format("%016x", fnv1a(table.concat(parts, "\n")))
        t.eq(actual, "e5cd39707be1e49f", "the goal catalog changed")
    end)

    -- reading a goal ---------------------------------------------------------
    -- These four decide whether the star a player just touched is the one they
    -- were sent for. Extracting them into modules/goals.lua found the lot
    -- uncovered: shifting the star-ID field, dropping the act comparison and
    -- matching any star at all all left the suite green.

    s.test("a goal is looked up by its position in the catalog", function()
        for _, id in ipairs({ 1, 2, 47, 93 }) do
            t.eq(api.get_goal(id), api.goals[id], "goal " .. id)
        end
        t.eq(api.get_goal(0), nil, "slot 0 is not a goal")
        t.eq(api.get_goal(94), nil, "past the end of the catalog")
    end)

    s.test("the local player's goal follows their synchronized slot", function()
        local live = harness.load()
        gPlayerSyncTable[0].sh5_goal = 12
        t.eq(live.get_local_goal(), live.goals[12], "slot 12")
        gPlayerSyncTable[0].sh5_goal = 1
        t.eq(live.get_local_goal(), live.goals[1], "slot 1")
        gPlayerSyncTable[0].sh5_goal = 0
        t.eq(live.get_local_goal(), nil, "no goal assigned yet")
    end)

    s.test("a star object matches only its own act", function()
        -- SM64 keeps the star's zero-based ID in the top byte of oBehParams,
        -- so Act 1 is object ID 0. An off-by-one here credits the player for
        -- the star next to the one they were sent for.
        local function star_object(act)
            return { oBehParams = (act - 1) << 24 }
        end
        for _, act in ipairs({ 1, 3, 6 }) do
            local goal = { act = act }
            t.ok(api.goal_matches_star_object(goal, star_object(act)),
                "act " .. act .. " did not match its own star")
            for _, other in ipairs({ 1, 2, 3, 4, 5, 6 }) do
                if other ~= act then
                    t.ok(not api.goal_matches_star_object(goal, star_object(other)),
                        "act " .. act .. " matched the act " .. other .. " star")
                end
            end
        end
        t.ok(not api.goal_matches_star_object({ act = 1 }, nil), "nil object matched")
    end)

    s.test("a player is in the goal's area only in the right level AND act", function()
        local live, ctl = harness.load()
        ctl.player_count = 1
        local goal = { level = LEVEL_CCM, act = 3 }

        gNetworkPlayers[0].currLevelNum = LEVEL_CCM
        gNetworkPlayers[0].currActNum = 3
        t.ok(live.goal_matches_player_area(goal, 0), "the right level and act did not match")

        gNetworkPlayers[0].currActNum = 4
        t.ok(not live.goal_matches_player_area(goal, 0), "the wrong act still matched")

        gNetworkPlayers[0].currLevelNum = LEVEL_BOB
        gNetworkPlayers[0].currActNum = 3
        t.ok(not live.goal_matches_player_area(goal, 0), "the wrong level still matched")
    end)

    s.test("a goal names its world and star in the chosen language", function()
        -- Catches the two arguments being handed over the wrong way round,
        -- which would show Spanish to English players and English to everyone
        -- else -- translated() itself would look perfectly healthy.
        local live = harness.load()
        local goal = live.goals[1]
        live.set_language(0)
        t.eq(live.goal_world_text(goal), goal.world, "English world name")
        t.eq(live.goal_title_text(goal), goal.title, "English star name")
        live.set_language(1)
        t.eq(live.goal_world_text(goal), goal.world_es, "Spanish world name")
        t.eq(live.goal_title_text(goal), goal.title_es, "Spanish star name")
        live.set_language(0)
    end)

    s.test("the mod registers one chat command and one pause-menu button", function()
        local _, ctl = harness.load()
        t.eq(#ctl.chat_commands, 1, "exactly one /help entry")
        t.eq(ctl.chat_commands[1].name, "starhunt")
        t.eq(#ctl.menu_buttons, 1, "exactly one Another Level button")
    end)
end
