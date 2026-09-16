-- StarHunt v1.1 - the 93 stars a round can ask for.
--
-- Every goal is chosen by hand. The fifteen 100-coin stars are deliberately
-- left out, and test/suite/catalog.lua fails if one reappears.
--
-- The `mods` written against a goal here are NOT the list of modifiers that
-- goal allows. They are hand-tuned value overrides for the modifiers that
-- matter most on that particular star. At load time modules/audit.lua replaces
-- every goal's `mods` with the full 32-entry catalog, keeps the hand-tuned
-- value wherever one exists, and drops whatever the audit rejects. So the
-- table below is the tuning input, and the table the rest of the mod reads is
-- what the audit leaves behind.
--
-- WORLD_NAMES and goal() are private to this file: nothing outside builds a
-- goal, and the world name a goal was built with travels on the goal itself.

local modifier = require("core").modifier
local translated = require("i18n").translated
local core = require("core")
local Team = core.Team
local is_round_active = core.is_round_active
local is_boss_mode = core.is_boss_mode
local local_runtime = core.local_runtime
local remove_starhunt_save_flag = require("save").remove_starhunt_save_flag
local boss_has_modifier = require("boss").boss_has_modifier

-- The player's lifetime star count, loaded once at startup.  It lives in this
-- module because on_interact below is the only code that increments and saves
-- it.  update_lifetime_sync publishes it for modules/team.lua, which balances
-- the rosters by reading sh5_lifetime_stars rather than this total directly,
-- and main.lua both calls it at load and hooks it to HOOK_UPDATE.
Team.lifetime = math.max(0, math.floor(tonumber(
    mod_storage_load("starhunt_lifetime_stars")) or 0))


Team.update_lifetime_sync = function()
    gPlayerSyncTable[0].sh5_lifetime_stars = Team.lifetime
end

local WORLD_NAMES = {
    [LEVEL_BOB] = { "BOB-OMB BATTLEFIELD", "CAMPO DE BATALLA BOB-OMB" },
    [LEVEL_WF] = { "WHOMP'S FORTRESS", "FORTALEZA DE WHOMP" },
    [LEVEL_JRB] = { "JOLLY ROGER BAY", "BAHIA DEL PIRATA" },
    [LEVEL_CCM] = { "COOL, COOL MOUNTAIN", "MONTANA ESCALOFRIANTE" },
    [LEVEL_BBH] = { "BIG BOO'S HAUNT", "MANSION DE BIG BOO" },
    [LEVEL_HMC] = { "HAZY MAZE CAVE", "CUEVA DEL LABERINTO" },
    [LEVEL_LLL] = { "LETHAL LAVA LAND", "FOSO DE LAVA LETAL" },
    [LEVEL_SSL] = { "SHIFTING SAND LAND", "ARENAS MOVEDIZAS" },
    [LEVEL_DDD] = { "DIRE, DIRE DOCKS", "MUELLE DIRE, DIRE" },
    [LEVEL_SL] = { "SNOWMAN'S LAND", "TIERRA DEL HOMBRE DE NIEVE" },
    [LEVEL_WDW] = { "WET-DRY WORLD", "MUNDO MOJADO-SECO" },
    [LEVEL_TTM] = { "TALL, TALL MOUNTAIN", "MONTANA ALTA, ALTA" },
    [LEVEL_THI] = { "TINY-HUGE ISLAND", "ISLA PEQUENA-GIGANTE" },
    [LEVEL_TTC] = { "TICK TOCK CLOCK", "RELOJ TIC TAC" },
    [LEVEL_RR] = { "RAINBOW RIDE", "PASEO POR EL ARCOIRIS" },
    [LEVEL_TOTWC] = { "TOWER OF THE WING CAP", "TORRE DE LA GORRA ALADA" },
    [LEVEL_COTMC] = { "CAVERN OF THE METAL CAP", "CUEVA DE LA GORRA METALICA" },
    [LEVEL_VCUTM] = { "VANISH CAP UNDER THE MOAT", "GORRA INVISIBLE BAJO EL FOSO" },
}

local function goal(level, act, title, title_es, mods, power)
    local world = WORLD_NAMES[level]
    return {
        level = level,
        act = act,
        world = world[1],
        world_es = world[2],
        title = title,
        title_es = title_es,
        mods = mods,
        power = power,
    }
end

-- Each goal is deliberately selected by hand.  The fifteen 100-coin stars are
-- excluded until a future version can balance them as their own category.
local GOALS = {
    -- Bob-omb Battlefield
    goal(LEVEL_BOB, 1, "KING BOB-OMB", "REY BOB-OMB", {
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_BOB, 2, "FOOTRACE WITH KOOPA", "CARRERA CONTRA KOOPA", {
        modifier("jump_limit", 20, "20 JUMPS"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_BOB, 3, "SHOOT TO THE ISLAND", "DISPARO A LA ISLA", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 36, "HEAVY FEET"),
    }),
    goal(LEVEL_BOB, 4, "RED COINS ON THE FIELD", "MONEDAS ROJAS EN EL CAMPO", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_BOB, 5, "MARIO WINGS TO THE SKY", "MARIO VUELA AL CIELO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "wing"),
    goal(LEVEL_BOB, 6, "BEHIND CHAIN CHOMP", "DETRAS DE CHAIN CHOMP", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
        modifier("low_jump", 42, "LOW JUMPS"),
    }),

    -- Whomp's Fortress
    goal(LEVEL_WF, 1, "CHIP OFF WHOMP'S BLOCK", "ROMPE EL BLOQUE DE WHOMP", {
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_WF, 2, "TO THE TOP OF THE FORTRESS", "A LA CIMA DE LA FORTALEZA", {
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_WF, 3, "SHOOT INTO THE WILD BLUE", "DISPARO AL CIELO AZUL", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 36, "HEAVY FEET"),
    }),
    goal(LEVEL_WF, 4, "RED COINS ON THE FORTRESS", "MONEDAS ROJAS EN LA FORTALEZA", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_WF, 5, "FALL ONTO THE CAGED ISLAND", "CAE EN LA ISLA ENJAULADA", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("low_jump", 42, "LOW JUMPS"),
    }),
    goal(LEVEL_WF, 6, "BLAST AWAY THE WALL", "DESTRUYE LA PARED", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),

    -- Water limits stay responsive; the goal is a challenge, not frozen input.
    goal(LEVEL_JRB, 1, "PLUNDER IN THE SUNKEN SHIP", "BOTIN DEL BARCO HUNDIDO", {
        modifier("water_cap", 38, "HEAVY SWIM (GENTLE)"),
        modifier("speed_cap", 36, "HEAVY FEET"),
    }),
    goal(LEVEL_JRB, 2, "CAN THE EEL COME OUT", "SALE LA ANGUILA", {
        modifier("water_cap", 38, "HEAVY SWIM (GENTLE)"),
        modifier("speed_cap", 36, "HEAVY FEET"),
    }),
    goal(LEVEL_JRB, 3, "TREASURE OF THE OCEAN CAVE", "TESORO DE LA CUEVA OCEANICA", {
        modifier("water_cap", 40, "HEAVY SWIM (GENTLE)"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_JRB, 4, "RED COINS ON THE SHIP AFLOAT", "MONEDAS ROJAS DEL BARCO A FLOTE", {
        modifier("water_cap", 40, "HEAVY SWIM (GENTLE)"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_JRB, 5, "BLAST TO THE STONE PILLAR", "DISPARO AL PILAR DE PIEDRA", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_JRB, 6, "THROUGH THE JET STREAM", "A TRAVES DEL CHORRO", {
        modifier("water_cap", 40, "HEAVY SWIM (GENTLE)"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "metal"),

    -- Cool, Cool Mountain
    goal(LEVEL_CCM, 1, "SLIP SLIDIN' AWAY", "RESBALON SIN PARAR", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_CCM, 2, "LI'L PENGUIN LOST", "PINGUINO PERDIDO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_CCM, 3, "BIG PENGUIN RACE", "CARRERA DEL GRAN PINGUINO", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 40, "HEAVY FEET"),
    }),
    goal(LEVEL_CCM, 4, "FROSTY SLIDE FOR 8 RED COINS", "TOBOGAN HELADO DE 8 MONEDAS", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_CCM, 5, "SNOWMAN'S LOST HIS HEAD", "EL HOMBRE DE NIEVE PERDIO LA CABEZA", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_CCM, 6, "WALL KICKS WILL WORK", "LAS PATADAS A LA PARED FUNCIONAN", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
        modifier("low_jump", 44, "LOW JUMPS"),
    }),

    -- Big Boo's Haunt. The boss stars require B, while the balcony and
    -- secret-eye routes get the stricter precision audit below.
    goal(LEVEL_BBH, 1, "GO ON A GHOST HUNT", "CAZA DE FANTASMAS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_BBH, 2, "RIDE BIG BOO'S MERRY-GO-ROUND", "EL CARRUSEL DE BIG BOO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_BBH, 3, "SECRET OF THE HAUNTED BOOKS", "EL SECRETO DE LOS LIBROS EMBRUJADOS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_BBH, 4, "SEEK THE 8 RED COINS", "BUSCA LAS 8 MONEDAS ROJAS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 24, "24 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_BBH, 5, "BIG BOO'S BALCONY", "EL BALCON DE BIG BOO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 24, "24 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_BBH, 6, "EYE TO EYE IN THE SECRET ROOM", "CARA A CARA EN EL CUARTO SECRETO", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }, "vanish"),

    -- Hazy Maze Cave
    goal(LEVEL_HMC, 1, "SWIMMING BEAST IN THE CAVERN", "BESTIA NADADORA EN LA CAVERNA", {
        modifier("water_cap", 38, "HEAVY SWIM (GENTLE)"),
        modifier("speed_cap", 36, "HEAVY FEET"),
    }),
    goal(LEVEL_HMC, 2, "ELEVATE FOR 8 RED COINS", "ELEVA PARA 8 MONEDAS ROJAS", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_HMC, 3, "METAL-HEAD MARIO CAN MOVE!", "MARIO METALICO PUEDE MOVERSE", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "metal"),
    goal(LEVEL_HMC, 4, "NAVIGATING THE TOXIC MAZE", "NAVEGANDO EL LABERINTO TOXICO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("low_jump", 44, "LOW JUMPS"),
    }),
    goal(LEVEL_HMC, 5, "A-MAZE-ING EMERGENCY EXIT", "SALIDA DE EMERGENCIA DEL LABERINTO", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_HMC, 6, "WATCH FOR ROLLING ROCKS", "CUIDADO CON LAS ROCAS", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),

    -- Lethal Lava Land
    goal(LEVEL_LLL, 1, "BOIL THE BIG BULLY", "HIERVE AL GRAN BULLY", {
        modifier("speed_cap", 40, "HEAVY FEET"),
        modifier("floor_doom", 6, "CURSED FLOOR: 6 SEC"),
    }),
    goal(LEVEL_LLL, 2, "BULLY THE BULLIES", "MOLESTA A LOS BULLIES", {
        modifier("speed_cap", 40, "HEAVY FEET"),
        modifier("floor_doom", 6, "CURSED FLOOR: 6 SEC"),
    }),
    goal(LEVEL_LLL, 3, "8-COIN PUZZLE WITH 15 PIECES", "ROMPECABEZAS DE 8 MONEDAS", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_LLL, 4, "RED-HOT LOG ROLLING", "TRONCO ARDIENTE", {
        modifier("low_jump", 44, "LOW JUMPS"),
        modifier("floor_doom", 6, "CURSED FLOOR: 6 SEC"),
    }),
    goal(LEVEL_LLL, 5, "HOT-FOOT-IT INTO THE VOLCANO", "CORRE HACIA EL VOLCAN", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_LLL, 6, "ELEVATOR TOUR IN THE VOLCANO", "RECORRIDO EN ASCENSOR DEL VOLCAN", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),

    -- Shifting Sand Land
    goal(LEVEL_SSL, 1, "IN THE TALONS OF THE BIG BIRD", "EN LAS GARRAS DEL GRAN PAJARO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_SSL, 2, "SHINING ATOP THE PYRAMID", "BRILLANDO SOBRE LA PIRAMIDE", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_SSL, 3, "INSIDE THE ANCIENT PYRAMID", "DENTRO DE LA PIRAMIDE ANTIGUA", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_SSL, 4, "STAND TALL ON THE FOUR PILLARS", "SOBRE LOS CUATRO PILARES", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_SSL, 5, "FREE FLYING FOR 8 RED COINS", "VUELO LIBRE POR 8 MONEDAS ROJAS", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "wing"),
    goal(LEVEL_SSL, 6, "PYRAMID PUZZLE", "ROMPECABEZAS DE LA PIRAMIDE", {
        modifier("low_jump", 44, "LOW JUMPS"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),

    -- Dire, Dire Docks
    goal(LEVEL_DDD, 1, "BOARD BOWSER'S SUB", "SUBE AL SUBMARINO DE BOWSER", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_DDD, 2, "CHESTS IN THE CURRENT", "COFRES EN LA CORRIENTE", {
        modifier("water_cap", 40, "HEAVY SWIM (GENTLE)"),
        modifier("speed_cap", 36, "HEAVY FEET"),
    }),
    goal(LEVEL_DDD, 3, "POLE-JUMPING FOR RED COINS", "SALTO DE POLOS POR MONEDAS ROJAS", {
        modifier("water_cap", 42, "HEAVY SWIM (GENTLE)"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_DDD, 4, "THROUGH THE JET STREAM", "A TRAVES DEL CHORRO", {
        modifier("water_cap", 38, "HEAVY SWIM (GENTLE)"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }, "metal"),
    goal(LEVEL_DDD, 5, "THE MANTA RAY'S REWARD", "RECOMPENSA DE LA MANTA RAYA", {
        modifier("water_cap", 42, "HEAVY SWIM (GENTLE)"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_DDD, 6, "COLLECT THE CAPS...", "RECOGE LAS GORRAS...", {
        modifier("water_cap", 40, "HEAVY SWIM (GENTLE)"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "metal_vanish"),

    -- Snowman's Land
    goal(LEVEL_SL, 1, "SNOWMAN'S BIG HEAD", "LA GRAN CABEZA DEL HOMBRE DE NIEVE", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_SL, 2, "CHILL WITH THE BULLY", "ENFRIA AL BULLY", {
        modifier("speed_cap", 40, "HEAVY FEET"),
        modifier("floor_doom", 6, "CURSED FLOOR: 6 SEC"),
    }),
    goal(LEVEL_SL, 3, "IN THE DEEP FREEZE", "DENTRO DEL HIELO PROFUNDO", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_SL, 4, "WHIRL FROM THE FREEZING POND", "REMOLINO DESDE EL ESTANQUE HELADO", {
        modifier("jump_limit", 20, "20 JUMPS"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_SL, 5, "SHELL SHREDDIN' FOR RED COINS", "CAPARAZON PARA LAS MONEDAS ROJAS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_SL, 6, "INTO THE IGLOO", "DENTRO DEL IGLU", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "vanish"),

    -- Wet-Dry World
    goal(LEVEL_WDW, 1, "SHOCKING ARROW LIFTS", "ASCENSORES DE FLECHAS ELECTRICAS", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_WDW, 2, "TOP O' THE TOWN", "EN LO ALTO DE LA CIUDAD", {
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_WDW, 3, "SECRETS IN THE SHALLOWS AND SKY", "SECRETOS EN EL AGUA Y EL CIELO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_WDW, 4, "EXPRESS ELEVATOR - HURRY UP", "ASCENSOR EXPRES - APURATE", {
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),
    goal(LEVEL_WDW, 5, "GO TO TOWN FOR RED COINS", "VE A LA CIUDAD POR MONEDAS ROJAS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_WDW, 6, "QUICK RACE THROUGH DOWNTOWN", "CARRERA RAPIDA POR LA CIUDAD", {
        modifier("speed_cap", 40, "HEAVY FEET"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }, "vanish"),

    -- Tall, Tall Mountain
    goal(LEVEL_TTM, 1, "SCALE THE MOUNTAIN", "ESCALA LA MONTANA", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_TTM, 2, "MYSTERY OF THE MONKEY CAGE", "MISTERIO DE LA JAULA DEL MONO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_TTM, 3, "SCARY SHROOMS, RED COINS", "HONGOS ATERRADORES, MONEDAS ROJAS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_TTM, 4, "MYSTERIOUS MOUNTAINSIDE", "LADERA MISTERIOSA", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 40, "HEAVY FEET"),
    }),
    goal(LEVEL_TTM, 5, "BREATHTAKING VIEW FROM BRIDGE", "VISTA IMPRESIONANTE DESDE EL PUENTE", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_TTM, 6, "BLAST TO THE LONELY MUSHROOM", "DISPARO AL HONGO SOLITARIO", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("speed_cap", 38, "HEAVY FEET"),
    }),

    -- Tiny-Huge Island
    goal(LEVEL_THI, 1, "PLUCK THE PIRANHA FLOWER", "ARRANCA LA FLOR PIRANA", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_THI, 2, "THE TIP TOP OF THE HUGE ISLAND", "LA CIMA DE LA ISLA GIGANTE", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_THI, 3, "REMATCH WITH KOOPA THE QUICK", "REVANCHA CONTRA KOOPA EL RAPIDO", {
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 7, "CURSED FLOOR: 7 SEC"),
    }),
    goal(LEVEL_THI, 4, "FIVE ITTY BITTY SECRETS", "CINCO SECRETOS DIMINUTOS", {
        modifier("no_b", 0, "B BUTTON LOCKED"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),
    goal(LEVEL_THI, 5, "WIGGLER'S RED COINS", "MONEDAS ROJAS DE WIGGLER", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_THI, 6, "MAKE WIGGLER SQUIRM", "HAZ RETORCERSE A WIGGLER", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),

    -- Tick Tock Clock. Acts 1-5 use the slow clock for consistent routes;
    -- Act 6 uses the stopped clock required by its intended red-coin setup.
    goal(LEVEL_TTC, 1, "ROLL INTO THE CAGE", "ENTRA EN LA JAULA", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_TTC, 2, "THE PIT AND THE PENDULUMS", "EL POZO Y LOS PENDULOS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 24, "24 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_TTC, 3, "GET A HAND", "SUBETE A LA AGUJA", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 22, "22 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_TTC, 4, "STOMP ON THE THWOMP", "SOBRE EL THWOMP", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 26, "26 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_TTC, 5, "TIMED JUMPS ON MOVING BARS", "SALTOS EN BARRAS MOVILES", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 24, "24 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_TTC, 6, "STOP TIME FOR RED COINS", "PARA EL TIEMPO POR MONEDAS ROJAS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 24, "24 JUMPS"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }),

    -- Rainbow Ride
    goal(LEVEL_RR, 1, "CRUISER CROSSING THE RAINBOW", "CRUCERO SOBRE EL ARCOIRIS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 26, "26 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_RR, 2, "THE BIG HOUSE IN THE SKY", "LA GRAN CASA EN EL CIELO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 24, "24 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_RR, 3, "COINS AMASSED IN A MAZE", "MONEDAS EN EL LABERINTO", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 26, "26 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_RR, 4, "SWINGIN' IN THE BREEZE", "BALANCEO EN LA BRISA", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 26, "26 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_RR, 5, "TRICKY TRIANGLES", "TRIANGULOS TRAICIONEROS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 20, "20 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),
    goal(LEVEL_RR, 6, "SOMEWHERE OVER THE RAINBOW", "SOBRE EL ARCOIRIS", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("jump_limit", 26, "26 JUMPS"),
        modifier("floor_doom", 9, "CURSED FLOOR: 9 SEC"),
    }),

    -- Cap courses
    goal(LEVEL_TOTWC, 1, "RED COINS OF THE WING CAP", "MONEDAS ROJAS DE LA GORRA ALADA", {
        modifier("speed_cap", 38, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "wing"),
    goal(LEVEL_COTMC, 1, "RED COINS OF THE METAL CAP", "MONEDAS ROJAS DE LA GORRA METALICA", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("no_b", 0, "B BUTTON LOCKED"),
    }, "metal"),
    goal(LEVEL_VCUTM, 1, "VANISH CAP UNDER THE MOAT", "GORRA INVISIBLE BAJO EL FOSO", {
        modifier("speed_cap", 36, "HEAVY FEET"),
        modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    }, "vanish"),
}

-- Reading a goal. Everything below answers a question ABOUT a goal rather than
-- describing one, which is why it sits here with the catalog: the answer always
-- comes out of the goal's own fields.
local function get_goal(id)
    return GOALS[id]
end

local function get_local_goal()
    return get_goal(gPlayerSyncTable[0].sh5_goal or 0)
end

local function goal_world_text(goal_data)
    return translated(goal_data.world, goal_data.world_es)
end

local function goal_title_text(goal_data)
    return translated(goal_data.title, goal_data.title_es)
end

local function goal_matches_player_area(goal_data, player_index)
    local player = gNetworkPlayers[player_index]
    return player ~= nil and player.currLevelNum == goal_data.level
        and player.currActNum == goal_data.act
end

local function goal_matches_star_object(goal_data, object)
    if object == nil then return false end
    -- SM64 stores the zero-based star ID in the top byte of the star object.
    -- An act value is one-based, so Act 1 must match object ID 0, and so on.
    local star_id = (object.oBehParams >> 24) & 0x1F
    return star_id == goal_data.act - 1
end

-- Whether two players are looking at the same world.
--
-- Two players in the same level on different acts may be standing in geometry
-- that does not agree -- JRB's two ship layouts, DDD's submarine, WDW's water
-- level, BBH's interior rooms, Whomp's tower, TTC's stopped clock. Where the
-- conflict is local to one region, only that region is private and the rest of
-- the course stays shared; where the whole course differs between acts, the
-- whole course is private. Team and Chaos are PvP races rather than parallel
-- runs, so they share a world whenever the players are genuinely in the same
-- place and skip the per-act geometry rules entirely.
--
-- Both answers feed visibility, nametags and whether PvP damage lands.
-- JRB has two incompatible ship layouts. When a player reaches the ship
-- region while another player has a different JRB act, that remote player is
-- locally hidden and PvP is disabled until they leave the conflicting area.
local function is_jrb_ship_zone(m)
    if m == nil then return false end
    return m.pos.x > -2600 and m.pos.x < 2600
        and m.pos.y > -2600 and m.pos.y < 1000
        and m.pos.z > -4200 and m.pos.z < -350
end

local function is_ddd_sub_zone(m)
    if m == nil or m.marioObj == nil then return false end
    local submarine = obj_get_first_with_behavior_id(id_bhvBowsersSub)
    if submarine ~= nil then
        local distance = dist_between_objects(submarine, m.marioObj)
        return distance ~= nil and distance < 4600
    end
    -- The vanilla submarine geometry is centered at the DDD origin. This
    -- fallback covers clients whose selected act has already removed it.
    return math.abs(m.pos.x) < 4200 and math.abs(m.pos.z) < 4200 and m.pos.y > -2600
end

local function is_wf_tower_zone(m)
    if m == nil then return false end
    return m.pos.y > 1050 and math.abs(m.pos.x) < 2600 and math.abs(m.pos.z) < 2600
end

local function players_have_private_variant(a, b)
    local first = get_goal(gPlayerSyncTable[a].sh5_goal or 0)
    local second = get_goal(gPlayerSyncTable[b].sh5_goal or 0)
    if first == nil or second == nil then
        return false
    end
    local first_network = gNetworkPlayers[a]
    local second_network = gNetworkPlayers[b]
    if first_network ~= nil and second_network ~= nil
        and (first_network.currAreaIndex or 1) ~= (second_network.currAreaIndex or 1) then
        return true
    end
    -- TEAM is a PvP race: if two players deliberately meet in the same
    -- loaded level and area, keep both models and nametags visible even when
    -- their assigned star acts differ. Normal mode keeps the conservative
    -- geometry isolation below.
    if Team.is_mode() or Team.is_chaos_mode() then return false end
    -- TTC Act 6 deliberately stops the clock while the other acts run slowly.
    -- Those object states cannot share one visible/PvP simulation.
    if first.level == LEVEL_TTC and second.level == LEVEL_TTC
        and (first.act == 6) ~= (second.act == 6) then
        return true
    end
    -- DDD's submarine is private only near the conflicting geometry. Players
    -- remain visible and can fight throughout the rest of the course.
    if first.level == LEVEL_DDD and second.level == LEVEL_DDD and first.act ~= second.act then
        return is_ddd_sub_zone(gMarioStates[a]) or is_ddd_sub_zone(gMarioStates[b])
    end
    -- Wet-Dry World may load a different global water/geometry state for each
    -- act, so different acts are private throughout that course.
    if first.level == LEVEL_WDW and second.level == LEVEL_WDW and first.act ~= second.act then
        return true
    end
    -- BBH changes several rooms and objects between acts. Keep PvP outside
    -- the mansion, but isolate players once either one enters an interior
    -- room whose geometry may not match the other's act.
    if first.level == LEVEL_BBH and second.level == LEVEL_BBH and first.act ~= second.act then
        local first_room = gMarioStates[a] ~= nil and (gMarioStates[a].currentRoom or 13) or 13
        local second_room = gMarioStates[b] ~= nil and (gMarioStates[b].currentRoom or 13) or 13
        if first_room ~= 13 or second_room ~= 13 then return true end
    end
    -- Whomp's tower changes between Act 1 and later acts. Only hide players
    -- around the conflicting upper structure; the rest of the level stays PvP.
    if first.level == LEVEL_WF and second.level == LEVEL_WF and first.act ~= second.act then
        return is_wf_tower_zone(gMarioStates[a]) or is_wf_tower_zone(gMarioStates[b])
    end
    if first.level ~= LEVEL_JRB or second.level ~= LEVEL_JRB then return false end
    if first.act == second.act then return false end
    return is_jrb_ship_zone(gMarioStates[a]) or is_jrb_ship_zone(gMarioStates[b])
end

local function players_can_share_world(a, b)
    if not is_round_active() or a == b then return false end
    if Team.is_mode() or Team.is_chaos_mode() then
        local first_network = gNetworkPlayers[a]
        local second_network = gNetworkPlayers[b]
        return first_network ~= nil and second_network ~= nil
            and first_network.connected and second_network.connected
            and first_network.currLevelNum == second_network.currLevelNum
            and (first_network.currAreaIndex or 1) == (second_network.currAreaIndex or 1)
    end
    local first = get_goal(gPlayerSyncTable[a].sh5_goal or 0)
    local second = get_goal(gPlayerSyncTable[b].sh5_goal or 0)
    if first == nil or second == nil or first.level ~= second.level then return false end
    if gNetworkPlayers[a].currLevelNum ~= first.level or gNetworkPlayers[b].currLevelNum ~= second.level then
        return false
    end
    if (gNetworkPlayers[a].currAreaIndex or 1) ~= (gNetworkPlayers[b].currAreaIndex or 1) then
        return false
    end
    return not players_have_private_variant(a, b)
end

-- Required caps: the `power` a goal asks for (Wing, Metal, Vanish or both of
-- the last two).  StarHunt grants it while the player is inside that goal's
-- level and area and gives the cap state back exactly as it found it.
--
-- That handing-back is a fix listed in DEVELOPMENT_CHECKLIST.md as one that
-- must not be undone: only the flags StarHunt itself added are ever removed,
-- and if another mod refreshed the same cap while StarHunt held it, the cap is
-- left alone.  Caps from OMM, Character Select or another moveset therefore
-- survive a round instead of being cleared by a blanket reset.
local STARHUNT_SPECIAL_CAP_MASK = MARIO_WING_CAP | MARIO_METAL_CAP | MARIO_VANISH_CAP
local local_starhunt_power = nil
local local_starhunt_added_flags = 0
local local_power_original_timer = 0

local function power_flags(power)
    if power == "wing" then return MARIO_WING_CAP end
    if power == "metal" then return MARIO_METAL_CAP end
    if power == "vanish" then return MARIO_VANISH_CAP end
    if power == "metal_vanish" then return MARIO_METAL_CAP | MARIO_VANISH_CAP end
    return 0
end

local function restore_starhunt_power(m)
    if local_starhunt_power == nil then return end
    local external_special = m.flags & STARHUNT_SPECIAL_CAP_MASK & ~local_starhunt_added_flags
    local flags_to_remove = local_starhunt_added_flags
    -- If another mod refreshed the same cap with a finite timer while
    -- StarHunt owned it, that cap is no longer ours to remove.
    if local_runtime.power_external_timer > local_power_original_timer and external_special == 0 then
        flags_to_remove = 0
    end
    m.flags = m.flags & ~flags_to_remove
    if not local_runtime.power_original_head and (m.flags & STARHUNT_SPECIAL_CAP_MASK) == 0 then
        m.flags = m.flags & ~MARIO_CAP_ON_HEAD
    end
    if m.capTimer == 0x7FFF then
        m.capTimer = math.max(local_power_original_timer, local_runtime.power_external_timer)
    end
    local_starhunt_power = nil
    local_starhunt_added_flags = 0
    local_power_original_timer = 0
    local_runtime.power_external_timer = 0
    local_runtime.power_original_head = false
end

local function apply_goal_power(m)
    if m.playerIndex ~= 0 then return end
    local goal_data = is_round_active() and not is_boss_mode() and get_local_goal() or nil
    if goal_data ~= nil and not goal_matches_player_area(goal_data, 0) then goal_data = nil end
    local desired = goal_data ~= nil and goal_data.power or nil

    if desired ~= local_starhunt_power then
        restore_starhunt_power(m)
        if desired ~= nil then
            local_power_original_timer = m.capTimer
            local_runtime.power_external_timer = m.capTimer
            local_runtime.power_original_head = (m.flags & MARIO_CAP_ON_HEAD) ~= 0
            local_starhunt_added_flags = power_flags(desired) & ~m.flags
            local_starhunt_power = desired
        end
    end
    if local_starhunt_power == nil then return end

    if m.capTimer ~= 0x7FFF and m.capTimer > local_runtime.power_external_timer then
        local_runtime.power_external_timer = m.capTimer
    end
    -- Add the required power without deleting special flags supplied by OMM,
    -- Character Select, or another compatible moveset.
    m.flags = m.flags | power_flags(local_starhunt_power) | MARIO_CAP_ON_HEAD
    m.capTimer = 0x7FFF
end

-- Claiming a star, and hiding the ones that are not it.  Every question these
-- answer comes out of a goal: is this object the assigned star, is the player
-- in its level and area, and have the coin tolls for its modifiers been paid.
--
-- The castle-lock and the HMC Metal Cap portal are the exception.  They run
-- outside a round too and belong to the lobby, not to any goal; they live here
-- because on_allow_interact is one function and answers both questions.
local function is_hmc_metal_portal(object)
    if object == nil or obj_has_behavior_id(object, id_bhvWarp) == 0 then return false end
    -- Vanilla HMC contains the Metal Cap portal at this location. Matching
    -- the actual warp object avoids disabling unrelated/custom HMC warps.
    local dx = (object.oPosX or 0) - 3351
    local dy = (object.oPosY or 0) + 4690
    local dz = (object.oPosZ or 0) - 4773
    return dx * dx + dy * dy + dz * dz < 900 * 900
end

local function in_castle_lock_level(player_index)
    local level = gNetworkPlayers[player_index].currLevelNum
    return level == LEVEL_CASTLE_GROUNDS or level == LEVEL_CASTLE or level == LEVEL_VCUTM
end

local function has_interaction(interaction, interaction_flag)
    return interaction_flag ~= nil and (interaction & interaction_flag) ~= 0
end

-- A spawned star can receive later object-sync updates. Once the player has
-- attempted an object that did not belong to the current goal, paying COIN
-- TOLL must not turn that same rejected object into a valid target.

local function on_allow_interact(m, object, interaction)
    -- Do not delete doors, grates, or the cannon: their collision remains so
    -- players bump into them normally. Only their use/warp interaction stops.
    if in_castle_lock_level(m.playerIndex) then
        if has_interaction(interaction, INTERACT_CANNON_BASE)
            or has_interaction(interaction, INTERACT_DOOR)
            or has_interaction(interaction, INTERACT_WARP_DOOR)
            or has_interaction(interaction, INTERACT_WARP) then
            return false
        end
    end

    if gNetworkPlayers[m.playerIndex].currLevelNum == LEVEL_HMC
        and has_interaction(interaction, INTERACT_WARP)
        and is_hmc_metal_portal(object) then
        return false
    end

    if not is_round_active() then return true end
    if is_boss_mode() then return true end
    if Team.is_chaos_mode() then
        return not has_interaction(interaction, INTERACT_STAR_OR_KEY)
    end
    if not has_interaction(interaction, INTERACT_STAR_OR_KEY) then return true end

    -- A player can only claim the assigned star in its assigned act; another
    -- visible star in that same level can no longer complete the challenge.
    local goal_id = gPlayerSyncTable[m.playerIndex].sh5_goal or 0
    local round_id = gGlobalSyncTable.sh5_round or 0
    local goal_data = get_goal(goal_id)
    if goal_data == nil or object == nil then return false end
    local rejected_by_player = local_runtime.rejected_stars[object]
    local rejection = rejected_by_player ~= nil and rejected_by_player[m.playerIndex] or nil
    if rejection ~= nil and rejection.goal == goal_id and rejection.round == round_id then
        return false
    end
    if not goal_matches_star_object(goal_data, object) then
        if rejected_by_player == nil then
            rejected_by_player = {}
            local_runtime.rejected_stars[object] = rejected_by_player
        end
        rejected_by_player[m.playerIndex] = {
            goal = goal_id,
            round = round_id,
        }
        return false
    end
    if not goal_matches_player_area(goal_data, m.playerIndex) then return false end
    if m.playerIndex == 0 then return Team.all_coin_tolls_paid(m) end
    local first = Team.effective_modifier_for_goal(goal_data,
        goal_data.mods[gPlayerSyncTable[m.playerIndex].sh5_modifier or 0])
    local second = Team.effective_modifier_for_goal(goal_data,
        goal_data.mods[gPlayerSyncTable[m.playerIndex].sh5_modifier_2 or 0])
    return Team.coin_toll_paid(m, first) and Team.coin_toll_paid(m, second)
end

local function on_interact(m, object, interaction, did_interact)
    if m.playerIndex ~= 0 or not is_round_active() then return end
    if is_boss_mode() then
        if did_interact and boss_has_modifier(1)
            and (has_interaction(interaction, INTERACT_DAMAGE)
                or has_interaction(interaction, INTERACT_FLAME)) then
            m.health = 0
        end
        return
    end
    if Team.is_chaos_mode() then return end
    if local_runtime.done_lock then return end
    if not did_interact or not has_interaction(interaction, INTERACT_STAR_OR_KEY) then return end

    local goal_data = get_local_goal()
    if goal_data ~= nil and goal_matches_player_area(goal_data, 0) and goal_matches_star_object(goal_data, object) then
        if not Team.all_coin_tolls_paid(m) then return end
        remove_starhunt_save_flag(goal_data)
        local_runtime.done_lock = true
        Team.lifetime = Team.lifetime + 1
        mod_storage_save("starhunt_lifetime_stars", tostring(Team.lifetime))
        Team.update_lifetime_sync()
        gPlayerSyncTable[0].sh5_done = (gPlayerSyncTable[0].sh5_done or 0) + 1
        djui_popup_create(translated("STAR GET! NEXT GOAL INCOMING...", "ESTRELLA CONSEGUIDA! NUEVO RETO..."), 1)
    end
end

-- A wrong star should not be a visual distraction or a tempting fake goal.
-- Track only flags that StarHunt itself added, so normal SM64 visibility is
-- restored exactly when a round ends or the next goal loads.
local function reset_hidden_object_tracking()
    local_runtime.hidden_stars = {}
    local_runtime.rejected_stars = {}
    local_runtime.hidden_players = {}
    local_runtime.star_visibility_next = 0
end

local function update_star_visibility()
    if get_global_timer() < local_runtime.star_visibility_next then return end
    local_runtime.star_visibility_next = get_global_timer() + 1
    local goal_data = is_round_active() and not is_boss_mode() and get_local_goal() or nil
    local object = obj_get_first(OBJ_LIST_LEVEL)
    while object ~= nil do
        if has_interaction(object.oInteractType, INTERACT_STAR_OR_KEY) then
            local correct = goal_data ~= nil and goal_matches_player_area(goal_data, 0)
                and goal_matches_star_object(goal_data, object)
                and Team.all_coin_tolls_paid(gMarioStates[0])
            if goal_data ~= nil and not correct then
                if local_runtime.hidden_stars[object] == nil then
                    local_runtime.hidden_stars[object] =
                        (object.header.gfx.node.flags & GRAPH_RENDER_INVISIBLE) ~= 0
                end
                object.header.gfx.node.flags = object.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE
            elseif local_runtime.hidden_stars[object] ~= nil then
                if not local_runtime.hidden_stars[object] then
                    object.header.gfx.node.flags = object.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE
                end
                local_runtime.hidden_stars[object] = nil
            end
        end
        object = obj_get_next(object)
    end
end

return {
    GOALS = GOALS,
    players_have_private_variant = players_have_private_variant,
    players_can_share_world = players_can_share_world,
    get_goal = get_goal,
    get_local_goal = get_local_goal,
    goal_world_text = goal_world_text,
    goal_title_text = goal_title_text,
    goal_matches_player_area = goal_matches_player_area,
    goal_matches_star_object = goal_matches_star_object,
    apply_goal_power = apply_goal_power,
    on_allow_interact = on_allow_interact,
    on_interact = on_interact,
    reset_hidden_object_tracking = reset_hidden_object_tracking,
    update_star_visibility = update_star_visibility,
}
