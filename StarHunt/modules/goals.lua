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

return {
    GOALS = GOALS,
}
