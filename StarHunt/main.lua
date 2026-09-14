-- name: \\#FFE05A\\Star\\#58D6FF\\Hunt \\#FFFFFF\\v1.1\\#DCDCDC\\
-- description: \\#FFE05A\\STARHUNT v1.1\\#FFFFFF\\ - Normal, Team, Boss and Chaos!\n\\#58D6FF\\93 goals, 32 audited modifiers and four difficulty levels.\n\\#FF7792\\Six languages, balanced teams, OMM and Character Select support.\n\\#C78CFF\\Menu: /starhunt | Updates: /starhunt updates
-- incompatible: romhack
--
-- StarHunt v1.1
-- Normal: all fifteen main worlds plus Wing, Metal and Vanish Cap courses.
-- Team: the same star race split into balanced Red and Blue teams.
-- Boss: every player fights Bowser in the Sky under three global modifiers.
-- Chaos: last-player-standing PvP on one random main-course map. Every player
-- gets an independent modifier rerolled every 15 seconds; Nightmare gives two.

local core = require("modules/core")
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local START_BANNER_FRAMES = 105
local NEXT_GOAL_DELAY = 90
-- Announce the winner first, then reset scores on the following frame.
-- This makes the handoff immediate without clearing the result beforehand.
local RESULT_DISPLAY_FRAMES = 1

-- Co-op DX reads this setting before starting the Peach/Lakitu opening scene.
-- Keep it enabled while StarHunt is installed so the game reaches the lobby
-- immediately after launching.
gServerSettings.skipIntro = 1

-- This is the shallow, post-Vanish-Cap moat height. It keeps the water
-- visible and usable instead of deleting it below the map.
local CASTLE_LOWERED_MOAT = -450

local Team = core.Team
local translated = require("modules/i18n").translated
local is_round_active = core.is_round_active
local save = require("modules/save")
local remove_starhunt_save_flag = save.remove_starhunt_save_flag
local flush_starhunt_save_removals = save.flush_starhunt_save_removals
local flush_starhunt_save_on_warp = save.flush_starhunt_save_on_warp
local flush_starhunt_save_on_exit = save.flush_starhunt_save_on_exit
local goal_already_collected = save.goal_already_collected
local TEAM_SCORE_PRIORITY_GAP = 2
local BOSS_HEALTH = 5
local CHAOS_REROLL_FRAMES = 15 * FRAMES_PER_SECOND
Team.chaos_maps = {
    LEVEL_BOB, LEVEL_WF, LEVEL_JRB, LEVEL_CCM, LEVEL_BBH,
    LEVEL_HMC, LEVEL_LLL, LEVEL_SSL, LEVEL_DDD, LEVEL_SL,
    LEVEL_WDW, LEVEL_TTM, LEVEL_THI, LEVEL_TTC, LEVEL_RR,
}

-- The final arena contains the full five-bomb layout used by Medium. Hard and
-- Nightmare can request one synchronized reserve wave after all five native
-- bombs are gone.
local BOSS_LEVELS = { LEVEL_BOWSER_3 }
Team.bossBombPositions = {
    { x = -2122, y = 512, z = -2912 },
    { x = -3362, y = 512, z = 1121 },
    { x = 0, y = 512, z = 3584 },
    { x = 3363, y = 512, z = 1121 },
    { x = 2123, y = 512, z = -2912 },
}

local MODIFIER_KINDS = {
    no_b = true,
    floor_doom = true,
    speed_cap = true,
    low_jump = true,
    water_cap = true,
    jump_limit = true,
    reverse_controls = true,
    periodic_freeze = true,
    fragile = true,
    high_gravity = true,
    wind_gust = true,
    no_z = true,
    air_brake = true,
    lava_clock = true,
    turbo = true,
    slippery = true,
    swap_ab = true,
    keep_moving = true,
    jump_cooldown = true,
    coin_surge = true,
    control_drift = true,
    coin_toll = true,
    darkness_pulse = true,
    mirrored_steering = true,
    coin_leak = true,
    slow_pulse = true,
    air_mirror = true,
    momentum_burst = true,
    control_pulse = true,
    coin_weight = true,
    gravity_wave = true,
    overheat = true,
}

local function modifier(kind, value, label)
    return { kind = kind, value = value, label = label }
end

-- Boss player modifiers never remove B: every Bowser must remain grabbable.
local BOSS_PLAYER_MODIFIERS = {
    modifier("reverse_controls", 0, "REVERSED CONTROLS"),
    modifier("periodic_freeze", 7, "TIME FREEZE: EVERY 7 SEC"),
    modifier("fragile", 0, "FRAGILE: 4 HEALTH"),
    modifier("high_gravity", 1.1, "HIGH GRAVITY"),
    modifier("wind_gust", 6, "WIND GUSTS"),
    modifier("floor_doom", 8, "CURSED FLOOR: 8 SEC"),
    modifier("turbo", 70, "TURBO MODE"),
}

local BOSS_MODIFIERS = {
    { kind = "instakill", label = "BOWSER: INSTANT KNOCKOUT", label_es = "BOWSER: GOLPE MORTAL" },
    { kind = "shockwaves", label = "BOWSER: PARALYZING WAVES", label_es = "BOWSER: ONDAS PARALIZANTES" },
    { kind = "violet_fire", label = "BOWSER: VIOLET SPLITFIRE", label_es = "BOWSER: FUEGO VIOLETA DIVIDIDO" },
    { kind = "rage", label = "BOWSER: RAGE", label_es = "BOWSER: FURIA" },
    { kind = "meteor_rain", label = "BOWSER: METEOR RAIN", label_es = "BOWSER: LLUVIA DE METEORITOS" },
    { kind = "fire_ring", label = "BOWSER: FLAME RING", label_es = "BOWSER: ANILLO DE FUEGO" },
    { kind = "bomb_barrage", label = "BOWSER: BOMB BARRAGE", label_es = "BOWSER: BOMBARDEO DE BOMBAS" },
    { kind = "arena_quake", label = "BOWSER: ARENA QUAKE", label_es = "BOWSER: TERREMOTO DE ARENA" },
    { kind = "teleport", label = "BOWSER: WARP WAVE", label_es = "BOWSER: ONDA DE DISTORSION" },
    { kind = "double_wave", label = "BOWSER: DOUBLE WAVE", label_es = "BOWSER: DOBLE ONDA" },
    { kind = "hunter_fire", label = "BOWSER: HUNTER FIRE", label_es = "BOWSER: FUEGO PERSEGUIDOR" },
    { kind = "desperate", label = "BOWSER: DESPERATE PHASE", label_es = "BOWSER: FASE DESESPERADA" },
}

local BOSS_MODIFIER_FIELDS = {
    "sh5_boss_modifier_1",
    "sh5_boss_modifier_2",
    "sh5_boss_modifier_3",
}
local BOSS_ATTACK_QUEUE_SIZE = 8

-- Rage and Desperate only accelerate other attacks, while Instakill changes
-- damage. Every draw must therefore include at least one modifier that creates
-- an attack of its own.
local BOSS_ACTIVE_ATTACK_MODIFIERS = { 2, 3, 5, 6, 7, 8, 9, 10, 11 }
local BOSS_ACTIVE_ATTACK_LOOKUP = {}
for _, index in ipairs(BOSS_ACTIVE_ATTACK_MODIFIERS) do
    BOSS_ACTIVE_ATTACK_LOOKUP[index] = true
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

-- v1.1 checks every modifier against every goal. These are conservative
-- compatibility rules, not simulated playthroughs: 1) obvious mechanical
-- impossibilities, 2) route-specific risk, 3) per-star/fallback tuning, and
-- 4) numeric safety limits.
local NORMAL_MODIFIER_CATALOG = {
    modifier("no_b", 0, "B BUTTON LOCKED"),
    modifier("floor_doom", 5, "CURSED FLOOR: 5 SEC"),
    modifier("speed_cap", 34, "HEAVY FEET"),
    modifier("low_jump", 40, "LOW JUMPS"),
    modifier("water_cap", 34, "HEAVY SWIM"),
    modifier("jump_limit", 18, "18 JUMPS"),
    modifier("reverse_controls", 0, "REVERSED CONTROLS"),
    modifier("periodic_freeze", 7, "TIME FREEZE: EVERY 7 SEC"),
    modifier("fragile", 0, "FRAGILE: 4 HEALTH"),
    modifier("high_gravity", 1.0, "HIGH GRAVITY"),
    modifier("wind_gust", 7, "WIND GUSTS"),
    modifier("no_z", 0, "Z BUTTON LOCKED"),
    modifier("air_brake", 65, "WEAK AIR CONTROL"),
    modifier("lava_clock", 6, "DAMAGE EVERY 6 SEC"),
    modifier("turbo", 58, "TURBO MODE"),
    modifier("slippery", 0, "SLIPPERY SHOES"),
    modifier("swap_ab", 0, "A/B BUTTONS SWAPPED"),
    modifier("keep_moving", 3, "KEEP MOVING: 3 SEC"),
    modifier("jump_cooldown", 24, "JUMP COOLDOWN: 0.8 SEC"),
    modifier("coin_surge", 12, "COIN SURGE"),
    modifier("control_drift", 20, "WAVY CONTROLS"),
    modifier("coin_toll", 20, "COIN TOLL: 20 COINS"),
    modifier("darkness_pulse", 36, "DARKNESS PULSE"),
    modifier("mirrored_steering", 0, "MIRRORED STEERING"),
    modifier("coin_leak", 5, "COIN LEAK: EVERY 5 SEC"),
    modifier("slow_pulse", 32, "SLOW PULSE"),
    modifier("air_mirror", 0, "AIR MIRROR"),
    modifier("momentum_burst", 12, "MOMENTUM BURST"),
    modifier("control_pulse", 36, "CONTROL PULSE"),
    modifier("coin_weight", 55, "COIN WEIGHT"),
    modifier("gravity_wave", 0.45, "GRAVITY WAVE"),
    modifier("overheat", 2, "OVERHEAT: SLOW DOWN"),
}

local function act_is(goal_data, ...)
    for _, act in ipairs({ ... }) do
        if goal_data.act == act then return true end
    end
    return false
end

local function goal_traits(goal_data)
    local traits = {}
    traits.main_course = goal_data.level ~= LEVEL_TOTWC
        and goal_data.level ~= LEVEL_COTMC and goal_data.level ~= LEVEL_VCUTM
    traits.flight = goal_data.power == "wing" or goal_data.level == LEVEL_TOTWC
    traits.water = (goal_data.level == LEVEL_JRB and act_is(goal_data, 1, 2, 3, 4, 6))
        or (goal_data.level == LEVEL_DDD and act_is(goal_data, 2, 3, 4, 5, 6))
    traits.race = (goal_data.level == LEVEL_BOB and goal_data.act == 2)
        or (goal_data.level == LEVEL_CCM and goal_data.act == 3)
        or (goal_data.level == LEVEL_THI and goal_data.act == 3)
    traits.slide = (goal_data.level == LEVEL_CCM and act_is(goal_data, 1, 3))
        or (goal_data.level == LEVEL_TTM and goal_data.act == 4)
    traits.cannon = (goal_data.level == LEVEL_BOB and goal_data.act == 3)
        or (goal_data.level == LEVEL_WF and act_is(goal_data, 3, 6))
        or (goal_data.level == LEVEL_JRB and goal_data.act == 5)
        or (goal_data.level == LEVEL_WDW and goal_data.act == 5)
        or (goal_data.level == LEVEL_TTM and goal_data.act == 6)
        or (goal_data.level == LEVEL_RR and goal_data.act == 6)
    traits.needs_b = (goal_data.level == LEVEL_BOB and goal_data.act == 1)
        or (goal_data.level == LEVEL_BBH and act_is(goal_data, 1, 2, 5))
        or (goal_data.level == LEVEL_CCM and goal_data.act == 2)
        or (goal_data.level == LEVEL_CCM and goal_data.act == 6)
        or (goal_data.level == LEVEL_LLL and act_is(goal_data, 1, 2))
        or (goal_data.level == LEVEL_SSL and goal_data.act == 1)
        or (goal_data.level == LEVEL_SL and goal_data.act == 2)
        or (goal_data.level == LEVEL_SL and goal_data.act == 5)
        or (goal_data.level == LEVEL_TTM and goal_data.act == 2)
    traits.needs_z = (goal_data.level == LEVEL_BOB and goal_data.act == 6)
        or (goal_data.level == LEVEL_WF and goal_data.act == 1)
        or (goal_data.level == LEVEL_SSL and goal_data.act == 4)
        or (goal_data.level == LEVEL_THI and goal_data.act == 6)
    traits.precision = (goal_data.level == LEVEL_WF and goal_data.act == 5)
        or (goal_data.level == LEVEL_BBH and act_is(goal_data, 3, 5, 6))
        or (goal_data.level == LEVEL_CCM and goal_data.act == 6)
        or (goal_data.level == LEVEL_LLL and goal_data.act == 4)
        or (goal_data.level == LEVEL_DDD and goal_data.act == 3)
        or (goal_data.level == LEVEL_SL and goal_data.act == 5)
        or (goal_data.level == LEVEL_WDW and act_is(goal_data, 4, 5, 6))
        or (goal_data.level == LEVEL_TTM and act_is(goal_data, 1, 3, 5, 6))
        or (goal_data.level == LEVEL_THI and act_is(goal_data, 2, 3, 5, 6))
        or goal_data.level == LEVEL_TTC
        or goal_data.level == LEVEL_RR
        or traits.flight
    traits.platform_wait = (goal_data.level == LEVEL_HMC and goal_data.act == 2)
        or (goal_data.level == LEVEL_LLL and goal_data.act == 6)
        or (goal_data.level == LEVEL_WDW and act_is(goal_data, 4, 5))
        or (goal_data.level == LEVEL_TTC and act_is(goal_data, 1, 2, 3, 4, 5))
        or (goal_data.level == LEVEL_RR and act_is(goal_data, 1, 2))
    traits.waiting = traits.cannon or traits.race
        or traits.platform_wait
        or (goal_data.level == LEVEL_BOB and goal_data.act == 1)
        or (goal_data.level == LEVEL_HMC and goal_data.act == 1)
        or (goal_data.level == LEVEL_CCM and act_is(goal_data, 2, 5))
        or (goal_data.level == LEVEL_TTM and goal_data.act == 2)
    traits.long_route = goal_data.act == 4 or goal_data.act == 5 or goal_data.act == 6
        or goal_data.level == LEVEL_TTM or goal_data.level == LEVEL_THI
        or goal_data.level == LEVEL_TTC or goal_data.level == LEVEL_RR
    traits.dynamic_precision = goal_data.level == LEVEL_TTC or goal_data.level == LEVEL_RR
    traits.ghost_house = goal_data.level == LEVEL_BBH
    return traits
end

local function audit_modifier(goal_data, modifier_data)
    local traits = goal_traits(goal_data)
    local kind = modifier_data.kind

    -- Stage 1: an input or movement ability required by the star may never be removed.
    if kind == "no_b" and traits.needs_b then return false, 1, "B is required" end
    if kind == "no_z" and traits.needs_z then return false, 1, "Z is required" end
    if kind == "water_cap" and not traits.water then return false, 1, "no meaningful swim route" end
    if kind == "coin_toll" and not traits.main_course then
        return false, 1, "special course has no safe 20-coin margin"
    end
    if (kind == "coin_leak" or kind == "coin_surge") and not traits.main_course then
        return false, 1, "special course has no reliable coin supply"
    end
    if traits.flight and (kind == "low_jump" or kind == "high_gravity" or kind == "air_brake"
        or kind == "wind_gust" or kind == "jump_cooldown" or kind == "coin_surge"
        or kind == "air_mirror" or kind == "control_pulse" or kind == "gravity_wave") then
        return false, 1, "flight route loses reliable altitude"
    end

    -- Stage 2: reject combinations whose normal human route is too precise or must wait.
    if traits.precision and (kind == "low_jump" or kind == "high_gravity" or kind == "wind_gust"
        or kind == "air_brake" or kind == "turbo" or kind == "slippery"
        or kind == "control_drift" or kind == "coin_surge" or kind == "jump_cooldown"
        or kind == "slow_pulse" or kind == "air_mirror" or kind == "momentum_burst"
        or kind == "control_pulse" or kind == "gravity_wave") then
        return false, 2, "precision route lacks a fair recovery margin"
    end
    if traits.dynamic_precision and kind == "periodic_freeze" then
        return false, 2, "moving-platform route cannot safely freeze input"
    end
    if traits.ghost_house and (kind == "wind_gust" or kind == "turbo"
        or kind == "slippery" or kind == "control_drift") then
        return false, 2, "haunted-house route loses a reliable recovery margin"
    end
    if traits.race and (kind == "speed_cap" or kind == "periodic_freeze" or kind == "keep_moving"
        or kind == "slow_pulse" or kind == "air_mirror" or kind == "momentum_burst"
        or kind == "control_pulse" or kind == "coin_weight" or kind == "coin_surge"
        or kind == "overheat") then
        return false, 2, "race timing would depend on modifier luck"
    end
    if traits.waiting and kind == "keep_moving" then
        return false, 2, "route contains forced waiting"
    end
    if traits.slide and (kind == "control_drift" or kind == "coin_surge"
        or kind == "slow_pulse" or kind == "air_mirror" or kind == "momentum_burst"
        or kind == "control_pulse" or kind == "overheat") then
        return false, 2, "forced slide steering becomes inconsistent"
    end
    if kind == "darkness_pulse" and (traits.flight or traits.race
        or traits.dynamic_precision or traits.platform_wait) then
        return false, 2, "blind interval has no safe recovery window"
    end
    if kind == "mirrored_steering" and (traits.flight or traits.race
        or traits.slide or traits.precision) then
        return false, 2, "mirrored steering removes the route's recovery margin"
    end
    if kind == "control_pulse" and (traits.cannon or traits.platform_wait) then
        return false, 2, "timed control reversal conflicts with forced waiting"
    end
    if kind == "momentum_burst" and (traits.cannon or traits.platform_wait) then
        return false, 2, "automatic acceleration is unsafe near forced waiting"
    end

    -- Stage 3: conservative values leave reaction time and alternate routes.
    if kind == "jump_limit" and traits.long_route and not modifier_data.hand_tuned then modifier_data.value = 26 end
    if kind == "floor_doom" and (traits.precision or traits.waiting) and not modifier_data.hand_tuned then
        modifier_data.value = 7
    end
    if kind == "floor_doom" and traits.platform_wait then
        -- These routes contain elevators or slow moving platforms. Nine
        -- seconds still requires regular jumps without turning the ride into
        -- an unavoidable death.
        modifier_data.value = 9
    end
    if kind == "keep_moving" and traits.water then return false, 3, "water speed is not a fair idle test" end
    if kind == "swap_ab" and traits.slide then return false, 3, "slide recovery uses both buttons rapidly" end

    -- Stage 4: numeric emergency limits.  These values deliberately keep a
    -- visible margin instead of accepting frame-perfect or pixel-perfect play.
    if kind == "speed_cap" and modifier_data.value < 32 then return false, 4, "speed margin below 32" end
    if kind == "low_jump" and modifier_data.value < 38 then return false, 4, "jump-height margin below 38" end
    if kind == "high_gravity" and modifier_data.value > 1.1 then return false, 4, "gravity penalty above safe margin" end
    if kind == "air_brake" and modifier_data.value < 60 then return false, 4, "air control below 60 percent" end
    if kind == "jump_cooldown" and modifier_data.value > 26 then return false, 4, "jump delay above safe margin" end
    if kind == "slow_pulse" and modifier_data.value < 32 then return false, 4, "slow pulse below safe speed" end
    if kind == "momentum_burst" and modifier_data.value > 14 then return false, 4, "momentum burst above safe margin" end
    if kind == "control_pulse" and modifier_data.value > 45 then return false, 4, "control pulse lasts too long" end
    if kind == "coin_weight" and modifier_data.value < 54 then return false, 4, "coin-weight base speed too low" end
    if kind == "gravity_wave" and modifier_data.value > 0.6 then return false, 4, "gravity wave above safe margin" end
    if kind == "overheat" and modifier_data.value < 2 then return false, 4, "overheat warning window too short" end
    if kind == "coin_surge" and modifier_data.value > 20 then return false, 4, "coin surge above safe margin" end
    return true, 3, "approved with conservative tuning"
end

local MODIFIER_AUDIT = {}
local MODIFIER_AUDIT_COUNTS = { checked = 0, approved = 0, rejected = 0 }

local function rebuild_audited_modifiers()
    for goal_id, goal_data in ipairs(GOALS) do
        -- The goal definitions contain the deliberately hand-tuned values for
        -- their most important modifiers. Keep those values as overrides; the
        -- audit may reject an unsafe combination, but must never erase the
        -- per-star balancing work.
        local tuned_by_kind = {}
        for _, tuned in ipairs(goal_data.mods or {}) do
            tuned_by_kind[tuned.kind] = tuned
        end
        goal_data.mods = {}
        MODIFIER_AUDIT[goal_id] = {}
        for _, template in ipairs(NORMAL_MODIFIER_CATALOG) do
            local tuned = tuned_by_kind[template.kind]
            local candidate = modifier(template.kind,
                tuned ~= nil and tuned.value or template.value,
                tuned ~= nil and tuned.label or template.label)
            candidate.hand_tuned = tuned ~= nil
            local approved, stage, reason = audit_modifier(goal_data, candidate)
            MODIFIER_AUDIT[goal_id][candidate.kind] = { approved = approved, stage = stage, reason = reason }
            MODIFIER_AUDIT_COUNTS.checked = MODIFIER_AUDIT_COUNTS.checked + 1
            if approved then
                table.insert(goal_data.mods, candidate)
                MODIFIER_AUDIT_COUNTS.approved = MODIFIER_AUDIT_COUNTS.approved + 1
            else
                MODIFIER_AUDIT_COUNTS.rejected = MODIFIER_AUDIT_COUNTS.rejected + 1
            end
        end
    end
end

rebuild_audited_modifiers()

-- The goal pool has 93 stars. Large lobbies still get shorter rounds, but
-- now have enough distinct goals for every player to receive several.
local function time_range_for_players(count)
    if count <= 1 then return 13, 22 end
    if count == 2 then return 11, 20 end
    if count == 3 then return 10, 18 end
    if count == 4 then return 9, 16 end
    if count <= 6 then return 8, 14 end
    if count <= 8 then return 7, 11 end
    if count <= 10 then return 6, 9 end
    if count <= 12 then return 5, 7 end
    if count <= 14 then return 5, 6 end
    return 4, 5
end

local function boss_time_range_for_players(count)
    if count <= 1 then return 5, 10 end
    if count <= 3 then return 4, 9 end
    if count <= 8 then return 4, 8 end
    return 3, 7
end

local function configured_time_range(count)
    if gGlobalSyncTable.sh5_mode == Team.BOSS then return boss_time_range_for_players(count) end
    return time_range_for_players(count)
end

local host_used_goals = {}
local host_seen_done = {}
local host_seen_forfeit = {}
local host_player_records = {}
local local_seen_round = nil
local local_seen_result = nil
local local_seen_return_seq = 0
local local_return_warp_pending = false
local local_return_warp_retry_at = 0
local local_start_banner_until = -1
local local_hud_flags_before_round = nil
local local_counter_round_active = false
local local_moat_refresh_at = 0
local local_lakitu_scan_at = 0
Team.lifetime = math.max(0, math.floor(tonumber(
    mod_storage_load("starhunt_lifetime_stars")) or 0))
local config_open = false
local config_selection = 1
local config_button_latch = 0
local config_stick_latched = false
local local_boss_health_object = nil
local local_boss_health_initialized = false
local local_boss_health_last_value = nil
local local_boss_health_report_at = 0
local STARHUNT_SPECIAL_CAP_MASK = MARIO_WING_CAP | MARIO_METAL_CAP | MARIO_VANISH_CAP
local local_starhunt_power = nil
local local_starhunt_added_flags = 0
local local_power_original_timer = 0
local host_previous_player_interactions = nil
local host_previous_pvp_type = nil
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

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end


local function selected_mode()
    local mode = gGlobalSyncTable.sh5_mode
    if mode == Team.BOSS or mode == Team.MODE or mode == Team.CHAOS then return mode end
    return Team.NORMAL
end

local function is_boss_mode()
    return selected_mode() == Team.BOSS
end

Team.is_mode = function()
    return selected_mode() == Team.MODE
end

Team.is_chaos_mode = function()
    return selected_mode() == Team.CHAOS
end

Team.selected_difficulty = function()
    return clamp(math.floor(gGlobalSyncTable.sh5_difficulty or Team.MEDIUM),
        Team.EASY, Team.NIGHTMARE)
end

Team.boss_health_for_difficulty = function()
    local values = { 3, BOSS_HEALTH, 7, 9 }
    return values[Team.selected_difficulty() + 1] or BOSS_HEALTH
end

Team.boss_max_health = function()
    return math.max(1, gGlobalSyncTable.sh5_boss_max_health or Team.boss_health_for_difficulty())
end

Team.lower_is_harder = {
    floor_doom=true, speed_cap=true, low_jump=true, water_cap=true, jump_limit=true,
    periodic_freeze=true, wind_gust=true, air_brake=true, lava_clock=true,
    keep_moving=true, coin_leak=true, slow_pulse=true, coin_weight=true, overheat=true,
}

Team.effective_modifier = function(base)
    if base == nil then return nil end
    local result = {}
    for key, value in pairs(base) do result[key] = value end
    local difficulty = Team.selected_difficulty()
    if difficulty == Team.MEDIUM then return result end

    local kind, value = result.kind, result.value
    if difficulty == Team.EASY then
        if kind == "no_b" or kind == "no_z" or kind == "reverse_controls"
            or kind == "swap_ab" or kind == "mirrored_steering" then
            result.pulse_period, result.pulse_frames = 10, 3 * FRAMES_PER_SECOND
        elseif kind == "fragile" then
            result.health_cap = 0x600
        elseif kind == "slippery" or kind == "air_mirror" then
            result.pulse_period, result.pulse_frames = 10, 4 * FRAMES_PER_SECOND
        elseif Team.lower_is_harder[kind] then
            result.value = math.max(1, value * 1.35)
        else
            result.value = value * 0.75
        end
        result.freeze_frames = 15
        result.damage_amount = 0x80
    elseif difficulty == Team.HARD then
        if kind == "fragile" then
            result.health_cap = 0x300
        elseif Team.lower_is_harder[kind] then
            result.value = math.max(1, value * 0.82)
        else
            result.value = value * 1.25
        end
        result.freeze_frames = 36
        result.damage_amount = 0x180
    else
        if kind == "fragile" then
            result.health_cap = 0x200
        elseif Team.lower_is_harder[kind] then
            result.value = math.max(1, value * 0.65)
        else
            result.value = value * 1.6
        end
        result.freeze_frames = 54
        result.damage_amount = 0x200
    end

    -- Preserve integer semantics where the modifier is measured in frames,
    -- seconds, coins or jumps.
    if kind ~= "high_gravity" and kind ~= "gravity_wave" then
        result.value = math.max(1, math.floor(result.value + 0.5))
    end
    return result
end

Team.effective_modifier_for_goal = function(goal, base)
    local result = Team.effective_modifier(base)
    if goal == nil or result == nil then return result end
    local approved = audit_modifier(goal, result)
    if not approved then return nil end
    return result
end

local function get_goal(id)
    return GOALS[id]
end

local function get_local_goal()
    return get_goal(gPlayerSyncTable[0].sh5_goal or 0)
end

Team.modifier_override = nil

Team.get_local_modifier_base = function(slot)
    if is_boss_mode() then
        local field = slot == 2 and "sh5_boss_player_modifier_2" or "sh5_boss_player_modifier"
        return BOSS_PLAYER_MODIFIERS[gGlobalSyncTable[field] or 0]
    end
    if Team.is_chaos_mode() then
        local field = slot == 2 and "sh5_modifier_2" or "sh5_modifier"
        return NORMAL_MODIFIER_CATALOG[gPlayerSyncTable[0][field] or 0]
    end
    local goal_data = get_local_goal()
    if goal_data == nil then return nil end
    local field = slot == 2 and "sh5_modifier_2" or "sh5_modifier"
    return goal_data.mods[gPlayerSyncTable[0][field] or 0]
end

local function get_local_modifier()
    return Team.effective_modifier(Team.get_local_modifier_base(1))
end

Team.get_local_modifiers = function()
    local result = {}
    local goal = get_local_goal()
    local first = Team.get_local_modifier_base(1)
    if first ~= nil then
        local effective = (is_boss_mode() or Team.is_chaos_mode()) and Team.effective_modifier(first)
            or Team.effective_modifier_for_goal(goal, first)
        if effective ~= nil then table.insert(result, effective) end
    end
    if Team.is_chaos_mode() or Team.selected_difficulty() == Team.NIGHTMARE then
        local second = Team.get_local_modifier_base(2)
        if second ~= nil and (first == nil or second.kind ~= first.kind) then
            local effective = (is_boss_mode() or Team.is_chaos_mode())
                and Team.effective_modifier(second)
                or Team.effective_modifier_for_goal(goal, second)
            if effective ~= nil then table.insert(result, effective) end
        end
    end
    return result
end

Team.update_lifetime_sync = function()
    gPlayerSyncTable[0].sh5_lifetime_stars = Team.lifetime
end

Team.coin_count = function(m)
    if m ~= nil and m.numCoins ~= nil then return math.max(0, m.numCoins) end
    return math.max(0, hud_get_value(HUD_DISPLAY_COINS) or 0)
end

Team.coin_toll_paid = function(m, modifier_data)
    return modifier_data == nil or modifier_data.kind ~= "coin_toll"
        or Team.coin_count(m) >= modifier_data.value
end

Team.all_coin_tolls_paid = function(m)
    for _, modifier_data in ipairs(Team.get_local_modifiers()) do
        if not Team.coin_toll_paid(m, modifier_data) then return false end
    end
    return true
end

Team.local_modifier_of_kind = function(kind)
    for _, modifier_data in ipairs(Team.get_local_modifiers()) do
        if modifier_data.kind == kind then return modifier_data end
    end
    return nil
end

Team.darkness_active = function(modifier_data)
    if modifier_data == nil or modifier_data.kind ~= "darkness_pulse" then return false end
    local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
    local phase = elapsed % (10 * FRAMES_PER_SECOND)
    return phase >= 10 * FRAMES_PER_SECOND - modifier_data.value
end

Team.periodic_window = function(period_seconds, duration_frames)
    local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
    local period = math.max(1, period_seconds) * FRAMES_PER_SECOND
    return elapsed % period >= period - duration_frames
end

local function goal_world_text(goal)
    return translated(goal.world, goal.world_es)
end

local function goal_title_text(goal)
    return translated(goal.title, goal.title_es)
end

local function modifier_text(modifier_data)
    if Team.language == 0 then return modifier_data.label end
    if Team.language >= 2 then
        local code = Team.language_codes[Team.language + 1]
        local label = Team.modifier_translations[code] and Team.modifier_translations[code][modifier_data.kind]
        if label == nil then return modifier_data.label end
        if modifier_data.kind == "floor_doom" or modifier_data.kind == "periodic_freeze"
            or modifier_data.kind == "lava_clock" or modifier_data.kind == "keep_moving"
            or modifier_data.kind == "coin_leak" then
            return label .. ": " .. tostring(modifier_data.value) .. " SEC"
        end
        if modifier_data.kind == "jump_limit" or modifier_data.kind == "coin_toll" then
            return tostring(modifier_data.value) .. " " .. label
        end
        if modifier_data.kind == "jump_cooldown" then
            return label .. ": " .. string.format("%.1f SEC", modifier_data.value / FRAMES_PER_SECOND)
        end
        return label
    end
    if modifier_data.kind == "no_b" then return "BOTON B BLOQUEADO" end
    if modifier_data.kind == "floor_doom" then return "PISO MALDITO: " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "speed_cap" then return "PIES PESADOS" end
    if modifier_data.kind == "low_jump" then return "SALTOS BAJOS" end
    if modifier_data.kind == "water_cap" then return "NADO PESADO" end
    if modifier_data.kind == "jump_limit" then return tostring(modifier_data.value) .. " SALTOS" end
    if modifier_data.kind == "reverse_controls" then return "CONTROLES INVERTIDOS" end
    if modifier_data.kind == "periodic_freeze" then return "TIEMPO CONGELADO CADA " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "fragile" then return "FRAGIL: 4 DE VIDA" end
    if modifier_data.kind == "high_gravity" then return "GRAVEDAD ALTA" end
    if modifier_data.kind == "wind_gust" then return "RAFAGAS DE VIENTO" end
    if modifier_data.kind == "no_z" then return "BOTON Z BLOQUEADO" end
    if modifier_data.kind == "air_brake" then return "POCO CONTROL AEREO" end
    if modifier_data.kind == "lava_clock" then return "DANO CADA " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "turbo" then return "MODO TURBO" end
    if modifier_data.kind == "slippery" then return "ZAPATOS RESBALADIZOS" end
    if modifier_data.kind == "swap_ab" then return "BOTONES A/B INTERCAMBIADOS" end
    if modifier_data.kind == "keep_moving" then return "SIGUE MOVIENDOTE: " .. tostring(modifier_data.value) .. " SEG" end
    if modifier_data.kind == "jump_cooldown" then
        return string.format("ESPERA ENTRE SALTOS: %.1f SEG", modifier_data.value / FRAMES_PER_SECOND)
    end
    if modifier_data.kind == "coin_surge" then return "IMPULSO DE MONEDA" end
    if modifier_data.kind == "control_drift" then return "CONTROLES ONDULANTES" end
    if modifier_data.kind == "coin_toll" then
        return "PEAJE DE MONEDAS: " .. tostring(modifier_data.value)
    end
    if modifier_data.kind == "darkness_pulse" then return "PULSO DE OSCURIDAD" end
    if modifier_data.kind == "mirrored_steering" then return "DIRECCION ESPEJO" end
    if modifier_data.kind == "coin_leak" then
        return "FUGA DE MONEDAS CADA " .. tostring(modifier_data.value) .. " SEG"
    end
    if modifier_data.kind == "slow_pulse" then return "PULSO LENTO" end
    if modifier_data.kind == "air_mirror" then return "ESPEJO AEREO" end
    if modifier_data.kind == "momentum_burst" then return "IMPULSO PERIODICO" end
    if modifier_data.kind == "control_pulse" then return "PULSO DE CONTROLES" end
    if modifier_data.kind == "coin_weight" then return "PESO DE MONEDAS" end
    if modifier_data.kind == "gravity_wave" then return "GRAVEDAD ONDULANTE" end
    if modifier_data.kind == "overheat" then return "SOBRECALENTAMIENTO: FRENA" end
    return modifier_data.label
end

local function boss_modifier_at(slot)
    local field = BOSS_MODIFIER_FIELDS[slot]
    return field ~= nil and BOSS_MODIFIERS[gGlobalSyncTable[field] or 0] or nil
end

local function boss_has_modifier(index)
    for slot = 1, #BOSS_MODIFIER_FIELDS do
        if gGlobalSyncTable[BOSS_MODIFIER_FIELDS[slot]] == index then return true end
    end
    return false
end

local function boss_is_desperate()
    return boss_has_modifier(12) and (gGlobalSyncTable.sh5_boss_health or Team.boss_max_health()) <= 2
end

local function boss_modifier_text(slot)
    local data = boss_modifier_at(slot)
    if data == nil then return "" end
    if Team.language == 1 then return data.label_es end
    if Team.language >= 2 then
        local code = Team.language_codes[Team.language + 1]
        local dictionary = Team.boss_modifier_translations[code]
        if dictionary ~= nil and dictionary[data.kind] ~= nil then return dictionary[data.kind] end
    end
    return data.label
end

local function connected_player_count()
    local count = 0
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then count = count + 1 end
    end
    return count
end

local function goal_is_active_for_anyone(goal_id)
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_goal or 0) == goal_id then
            return true
        end
    end
    return false
end

local function goal_matches_player_area(goal, player_index)
    local player = gNetworkPlayers[player_index]
    return player ~= nil and player.currLevelNum == goal.level and player.currActNum == goal.act
end

local function goal_matches_star_object(goal, object)
    if object == nil then return false end
    -- SM64 stores the zero-based star ID in the top byte of the star object.
    -- An act value is one-based, so Act 1 must match object ID 0, and so on.
    local star_id = (object.oBehParams >> 24) & 0x1F
    return star_id == goal.act - 1
end

local function is_local_player_on_floor(m)
    if m.floor == nil or (m.action & ACT_FLAG_SWIMMING) ~= 0 then return false end
    return math.abs(m.pos.y - m.floorHeight) < 22
end

local function reset_local_modifier_state()
    local_runtime.floor_frames = 0
    local_runtime.slip_speed = 0
    local_runtime.modifier_tick = -1
    local_runtime.modifier_start_frame = get_global_timer()
    local_runtime.boss_stun_frames = 0
    local_runtime.boss_damage_lock = 0
    local_runtime.pending_double_waves = {}
    local_runtime.pending_meteors = {}
    local_runtime.idle_frames = 0
    local_runtime.last_move_x = nil
    local_runtime.last_move_z = nil
    local_runtime.wind_tick = -1
    local_runtime.freeze_tick = -1
    local_runtime.freeze_frames = 0
    local_runtime.freeze_yaw = nil
    local_runtime.last_coin_count = nil
    local_runtime.coin_leak_tick = -1
    local_runtime.momentum_tick = -1
    local_runtime.overheat_frames = 0
    local_runtime.jump_cooldown_frames = 0
    local_runtime.done_lock = false
end

local function host_pick_goal(avoid_level)
    local choices = {}
    for id, goal in ipairs(GOALS) do
        if (avoid_level == nil or goal.level ~= avoid_level)
            and not host_used_goals[id] and not goal_is_active_for_anyone(id)
            and not goal_already_collected(goal) then
            table.insert(choices, id)
        end
    end
    if #choices == 0 then return 0 end
    return choices[math.random(#choices)]
end

Team.chaos_conflicts = {
    no_b={ swap_ab=true }, swap_ab={ no_b=true },
    reverse_controls={ mirrored_steering=true, control_pulse=true, air_mirror=true },
    mirrored_steering={ reverse_controls=true, air_mirror=true },
    air_mirror={ reverse_controls=true, mirrored_steering=true },
    control_pulse={ reverse_controls=true, mirrored_steering=true, air_mirror=true },
    low_jump={ high_gravity=true }, high_gravity={ low_jump=true },
    coin_toll={ coin_leak=true }, coin_leak={ coin_toll=true },
    coin_surge={ speed_cap=true, slow_pulse=true, coin_weight=true },
    speed_cap={ coin_surge=true }, slow_pulse={ coin_surge=true }, coin_weight={ coin_surge=true },
    periodic_freeze={ keep_moving=true, floor_doom=true },
}

Team.chaos_pair_allowed = function(first, second)
    if first == nil or second == nil or first.kind == second.kind then return false end
    local first_conflicts = Team.chaos_conflicts[first.kind]
    local second_conflicts = Team.chaos_conflicts[second.kind]
    return not ((first_conflicts ~= nil and first_conflicts[second.kind])
        or (second_conflicts ~= nil and second_conflicts[first.kind]))
end

Team.chaos_modifier_allowed = function(candidate)
    -- Coin Toll only gates a target star, and Chaos deliberately has none.
    return candidate ~= nil and candidate.kind ~= "coin_toll"
end

Team.pick_chaos_pair = function(previous_first)
    local first_choices = {}
    for index, candidate in ipairs(NORMAL_MODIFIER_CATALOG) do
        if Team.chaos_modifier_allowed(candidate) and index ~= previous_first then
            table.insert(first_choices, index)
        end
    end
    if #first_choices == 0 then return 0, 0 end
    local first_index = first_choices[math.random(#first_choices)]
    if Team.selected_difficulty() ~= Team.NIGHTMARE then return first_index, 0 end
    local second_choices = {}
    for index, candidate in ipairs(NORMAL_MODIFIER_CATALOG) do
        if Team.chaos_modifier_allowed(candidate)
            and Team.chaos_pair_allowed(NORMAL_MODIFIER_CATALOG[first_index], candidate) then
            table.insert(second_choices, index)
        end
    end
    if #second_choices == 0 then return 0, 0 end
    return first_index, second_choices[math.random(#second_choices)]
end

Team.difficulty_modifier_allowed = function(goal, candidate)
    if candidate == nil then return false end
    return Team.effective_modifier_for_goal(goal, candidate) ~= nil
end

Team.pick_second_modifier = function(goal, first_index)
    local choices = {}
    local first = goal.mods[first_index]
    for index, candidate in ipairs(goal.mods) do
        if index ~= first_index and Team.chaos_pair_allowed(first, candidate)
            and Team.difficulty_modifier_allowed(goal, candidate) then
            table.insert(choices, index)
        end
    end
    if #choices == 0 then return 0 end
    return choices[math.random(#choices)]
end

local function host_assign_goal(player_index, avoid_modifier_kind, avoid_level)
    local goal_id = host_pick_goal(avoid_level)
    if goal_id == 0 then return false end

    local goal = get_goal(goal_id)
    local alternatives = {}
    for index, modifier_data in ipairs(goal.mods) do
        if Team.difficulty_modifier_allowed(goal, modifier_data)
            and (avoid_modifier_kind == nil or modifier_data.kind ~= avoid_modifier_kind) then
            table.insert(alternatives, index)
        end
    end
    if #alternatives == 0 then
        for index, modifier_data in ipairs(goal.mods) do
            if Team.difficulty_modifier_allowed(goal, modifier_data) then table.insert(alternatives, index) end
        end
    end
    if #alternatives == 0 then return false end
    local modifier_index = alternatives[math.random(#alternatives)]
    local modifier_data = goal.mods[modifier_index]
    host_used_goals[goal_id] = true

    local sync = gPlayerSyncTable[player_index]
    sync.sh5_goal = goal_id
    sync.sh5_modifier = modifier_index
    sync.sh5_modifier_2 = Team.selected_difficulty() == Team.NIGHTMARE
        and Team.pick_second_modifier(goal, modifier_index) or 0
    local second = goal.mods[sync.sh5_modifier_2 or 0]
    local jump_modifier = modifier_data.kind == "jump_limit" and modifier_data
        or (second ~= nil and second.kind == "jump_limit" and second or nil)
    jump_modifier = Team.effective_modifier_for_goal(goal, jump_modifier)
    sync.sh5_jump_count = jump_modifier ~= nil and jump_modifier.value or -1
    sync.sh5_goal_seq = (sync.sh5_goal_seq or 0) + 1
    sync.sh5_manual_reroll_ready_frame =
        get_global_timer() + Team.manualRerollCooldown
    return true
end

local function player_record_key(player_index)
    local player = gNetworkPlayers[player_index]
    if player == nil then return nil end
    if player.globalIndex ~= nil then return "g:" .. tostring(player.globalIndex) end
    return "slot:" .. tostring(player_index)
end

Team.build_balanced = function()
    Team.initial = {}
    local players = {}
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            table.insert(players, {
                index = i,
                skill = math.max(0, math.floor(gPlayerSyncTable[i].sh5_lifetime_stars or 0)),
                tie = math.random(),
            })
        end
    end
    table.sort(players, function(a, b)
        if a.skill ~= b.skill then return a.skill > b.skill end
        return a.tie < b.tie
    end)

    local red_cap = math.floor(#players / 2)
    local blue_cap = math.floor(#players / 2)
    if #players % 2 == 1 then
        if math.random(2) == 1 then red_cap = red_cap + 1 else blue_cap = blue_cap + 1 end
    end
    local red_count, blue_count, red_skill, blue_skill = 0, 0, 0, 0
    for _, player in ipairs(players) do
        local team
        if red_count >= red_cap then
            team = Team.BLUE
        elseif blue_count >= blue_cap then
            team = Team.RED
        elseif red_skill < blue_skill then
            team = Team.RED
        elseif blue_skill < red_skill then
            team = Team.BLUE
        elseif red_count < blue_count then
            team = Team.RED
        elseif blue_count < red_count then
            team = Team.BLUE
        else
            team = math.random(2) == 1 and Team.RED or Team.BLUE
        end
        Team.initial[player.index] = team
        if team == Team.RED then
            red_count = red_count + 1
            red_skill = red_skill + player.skill
        else
            blue_count = blue_count + 1
            blue_skill = blue_skill + player.skill
        end
    end
end

Team.participant_stats = function()
    local stats = {
        [Team.RED] = { count = 0, skill = 0, score = 0 },
        [Team.BLUE] = { count = 0, skill = 0, score = 0 },
    }
    local connected_keys = {}
    for i = 0, MAX_PLAYERS - 1 do
        local sync = gPlayerSyncTable[i]
        if gNetworkPlayers[i].connected and (sync.sh5_enrolled or 0) == 1 then
            local team = sync.sh5_team or Team.NONE
            if stats[team] ~= nil then
                stats[team].count = stats[team].count + 1
                stats[team].skill = stats[team].skill + math.max(0, sync.sh5_lifetime_stars or 0)
                stats[team].score = stats[team].score + math.max(0, sync.sh5_score or 0)
            end
            local key = player_record_key(i)
            if key ~= nil then connected_keys[key] = true end
        end
    end
    for key, record in pairs(host_player_records) do
        local team = record.team or Team.NONE
        if not connected_keys[key] and record.enrolled == 1 and stats[team] ~= nil then
            -- Preserve disconnected players' earned points, but do not count
            -- them as active roster slots when assigning a new participant.
            stats[team].score = stats[team].score + math.max(0, record.score or 0)
        end
    end
    return stats
end

Team.pick_late = function(preferred_team)
    local stats = Team.participant_stats()
    -- Player count is the hard constraint. A new or returning participant
    -- always fills the smaller active roster before any other consideration.
    if stats[Team.RED].count < stats[Team.BLUE].count then return Team.RED end
    if stats[Team.BLUE].count < stats[Team.RED].count then return Team.BLUE end

    -- With equal rosters, help a team that trails by at least two points.
    -- A one-point gap is intentionally too small to override reconnection or
    -- experience balance, preventing constant team changes around a tie.
    if stats[Team.RED].score - stats[Team.BLUE].score >= TEAM_SCORE_PRIORITY_GAP then
        return Team.BLUE
    end
    if stats[Team.BLUE].score - stats[Team.RED].score >= TEAM_SCORE_PRIORITY_GAP then
        return Team.RED
    end

    -- Preserve a reconnect's previous team whenever the two stronger rules
    -- above do not require a different assignment.
    if preferred_team == Team.RED or preferred_team == Team.BLUE then return preferred_team end

    if stats[Team.RED].skill < stats[Team.BLUE].skill then return Team.RED end
    if stats[Team.BLUE].skill < stats[Team.RED].skill then return Team.BLUE end
    return math.random(2) == 1 and Team.RED or Team.BLUE
end

Team.update_scores = function()
    if not network_is_server() or not Team.is_mode() then return end
    local stats = Team.participant_stats()
    gGlobalSyncTable.sh5_red_score = stats[Team.RED].score
    gGlobalSyncTable.sh5_blue_score = stats[Team.BLUE].score
end

local function update_winner_candidate(name, score, best_score, winners)
    if score > best_score then
        return score, { name }
    end
    if score == best_score then table.insert(winners, name) end
    return best_score, winners
end

local function winner_text_and_score()
    local best_score = -1
    local winners = {}
    local connected_keys = {}
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_enrolled or 0) == 1 then
            local score = gPlayerSyncTable[i].sh5_score or 0
            local key = player_record_key(i)
            if key ~= nil then connected_keys[key] = true end
            best_score, winners = update_winner_candidate(
                gNetworkPlayers[i].name, score, best_score, winners)
        end
    end
    -- A brief disconnect at the final second must not erase a participant
    -- from the results. The host keeps the latest authoritative snapshot.
    for key, record in pairs(host_player_records) do
        if not connected_keys[key] and record.enrolled == 1 then
            best_score, winners = update_winner_candidate(
                record.name, record.score, best_score, winners)
        end
    end
    if #winners == 0 then return "Nobody", 0 end
    if #winners == 1 then return winners[1], best_score end
    return table.concat(winners, " and "), best_score
end

local function host_end_round(reason)
    if not is_round_active() then return end

    local result_mode = selected_mode()
    local boss_round = result_mode == Team.BOSS
    local winner, score = winner_text_and_score()
    if boss_round then
        winner = reason == "boss defeated" and "TEAM STARHUNT" or "BOWSER"
        score = reason == "boss defeated" and 1 or 0
    elseif result_mode == Team.CHAOS then
        winner = reason == "chaos last standing"
            and (gGlobalSyncTable.sh5_chaos_winner or "Nobody") or "Nobody"
        score = reason == "chaos last standing" and 1 or 0
    elseif result_mode == Team.MODE then
        Team.update_scores()
        local red_score = gGlobalSyncTable.sh5_red_score or 0
        local blue_score = gGlobalSyncTable.sh5_blue_score or 0
        if red_score > blue_score then
            winner, score = "RED TEAM", red_score
        elseif blue_score > red_score then
            winner, score = "BLUE TEAM", blue_score
        else
            winner, score = "TIE", red_score
        end
        gGlobalSyncTable.sh5_result_red_score = red_score
        gGlobalSyncTable.sh5_result_blue_score = blue_score
    end
    gGlobalSyncTable.sh5_active = 0
    -- The host may close the game immediately after stopping the round.
    -- Flush its own pending star removals before sending the lobby warp.
    flush_starhunt_save_removals(true, false)
    gGlobalSyncTable.sh5_result_mode = result_mode
    gGlobalSyncTable.sh5_result_winner = winner
    gGlobalSyncTable.sh5_result_score = score
    gGlobalSyncTable.sh5_result_reason = reason
    gGlobalSyncTable.sh5_chaos_roster_locked = 0
    gGlobalSyncTable.sh5_chaos_alive = 0
    gGlobalSyncTable.sh5_result_seq = (gGlobalSyncTable.sh5_result_seq or 0) + 1
    -- Unlike the winner popup, returning to the lobby must not be a one-frame
    -- local action. Give every connected player a durable, personal return
    -- order so delayed clients keep retrying until the warp succeeds.
    gGlobalSyncTable.sh5_return_seq = (gGlobalSyncTable.sh5_return_seq or 0) + 1
    -- The result sequence is sent first.  Scores remain intact long enough
    -- for every client to display the winner, then reset for the next round.
    -- This same route is used when the clock ends and when the host stops.
    gGlobalSyncTable.sh5_reset_scores_at = get_global_timer() + RESULT_DISPLAY_FRAMES

    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            local sync = gPlayerSyncTable[i]
            sync.sh5_goal = 0
            sync.sh5_modifier = 0
            sync.sh5_modifier_2 = 0
            sync.sh5_jump_count = -1
            sync.sh5_manual_reroll_request = 0
            sync.sh5_manual_reroll_ack = 0
            sync.sh5_manual_reroll_ready_frame = 0
            sync.sh5_enrolled = 0
            sync.sh5_team = Team.NONE
            sync.sh5_chaos_eliminated = 0
            sync.sh5_return_seq = gGlobalSyncTable.sh5_return_seq
        end
    end


    if host_previous_player_interactions ~= nil then
        gServerSettings.playerInteractions = host_previous_player_interactions
        host_previous_player_interactions = nil
    end
    if host_previous_pvp_type ~= nil then
        gServerSettings.pvpType = host_previous_pvp_type
        host_previous_pvp_type = nil
    end
end

local function host_reset_scores_after_result()
    if not network_is_server() then return end
    local reset_at = gGlobalSyncTable.sh5_reset_scores_at or 0
    if reset_at == 0 or get_global_timer() < reset_at then return end
    if is_round_active() then
        gGlobalSyncTable.sh5_reset_scores_at = 0
        return
    end
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            gPlayerSyncTable[i].sh5_score = 0
            gPlayerSyncTable[i].sh5_done = 0
            gPlayerSyncTable[i].sh5_forfeit = 0
        end
    end
    gGlobalSyncTable.sh5_reset_scores_at = 0
end

local function host_prepare_player(player_index)
    local sync = gPlayerSyncTable[player_index]
    local name = gNetworkPlayers[player_index].name or ""
    local key = player_record_key(player_index)
    local record = key ~= nil and host_player_records[key] or nil
    -- Co-op DX reuses global player indices after a disconnect. A direct key
    -- match is a reconnect only when the identity also matches; otherwise a
    -- new player could inherit somebody else's score and challenge.
    if record ~= nil and record.name ~= name then record = nil end
    if record == nil and name ~= "" then
        -- globalIndex normally survives the session. If it changed during a
        -- reconnect, use the name only when exactly one disconnected record
        -- matches, preventing same-name players from stealing each other.
        local connected_record_keys = {}
        for i = 0, MAX_PLAYERS - 1 do
            if i ~= player_index and gNetworkPlayers[i].connected then
                local connected_key = player_record_key(i)
                if connected_key ~= nil then connected_record_keys[connected_key] = true end
            end
        end
        local candidate = nil
        for record_key, saved in pairs(host_player_records) do
            if saved.name == name and not connected_record_keys[record_key] then
                if candidate ~= nil then
                    candidate = false
                    break
                end
                candidate = saved
            end
        end
        if candidate ~= false then record = candidate end
    end
    if record ~= nil then
        local restored_team = Team.is_mode() and Team.pick_late(record.team) or Team.NONE
        sync.sh5_score = record.score
        sync.sh5_goal = record.goal
        sync.sh5_modifier = record.modifier
        sync.sh5_modifier_2 = record.modifier_2 or 0
        sync.sh5_done = record.done
        sync.sh5_forfeit = record.forfeit
        sync.sh5_manual_reroll_request = record.manual_reroll_request or 0
        sync.sh5_manual_reroll_ack = record.manual_reroll_ack
            or sync.sh5_manual_reroll_request
        sync.sh5_manual_reroll_ready_frame =
            record.manual_reroll_ready_frame or get_global_timer()
        sync.sh5_jump_count = record.jump_count
        sync.sh5_boss_victory = record.boss_victory
        sync.sh5_chaos_eliminated = record.chaos_eliminated or 0
        sync.sh5_team = restored_team
        sync.sh5_enrolled = 1
        sync.sh5_lifetime_stars = math.max(sync.sh5_lifetime_stars or 0, record.lifetime_stars or 0)
        host_seen_done[player_index] = record.done
        host_seen_forfeit[player_index] = record.forfeit
        host_player_records[record.key] = nil
        if is_boss_mode() or Team.is_chaos_mode() or record.goal ~= 0 then return true end
        return host_assign_goal(player_index)
    end

    sync.sh5_score = 0
    sync.sh5_goal = 0
    sync.sh5_modifier = 0
    sync.sh5_modifier_2 = 0
    sync.sh5_done = 0
    sync.sh5_forfeit = 0
    sync.sh5_manual_reroll_request = 0
    sync.sh5_manual_reroll_ack = 0
    sync.sh5_manual_reroll_ready_frame = 0
    sync.sh5_jump_count = -1
    sync.sh5_enrolled = 1
    sync.sh5_boss_victory = 0
    sync.sh5_chaos_eliminated = Team.is_chaos_mode()
        and ((gGlobalSyncTable.sh5_chaos_roster_locked or 0) == 1 and 1 or 0) or 0
    sync.sh5_boss_health_ready_round = 0
    sync.sh5_boss_health_value = Team.boss_max_health()
    sync.sh5_boss_health_tick = 0
    local initial_team = Team.initial[player_index]
    Team.initial[player_index] = nil
    sync.sh5_team = Team.is_mode()
        and (initial_team or Team.pick_late()) or Team.NONE
    host_seen_done[player_index] = 0
    host_seen_forfeit[player_index] = 0
    if Team.is_chaos_mode() then
        local first_index, second_index = Team.pick_chaos_pair(0)
        if first_index == 0 then return false end
        sync.sh5_modifier = first_index
        sync.sh5_modifier_2 = second_index
        local first = Team.effective_modifier(NORMAL_MODIFIER_CATALOG[first_index])
        local second = Team.effective_modifier(NORMAL_MODIFIER_CATALOG[second_index])
        sync.sh5_jump_count = first ~= nil and first.kind == "jump_limit" and first.value
            or (second ~= nil and second.kind == "jump_limit" and second.value or -1)
        return true
    end
    if is_boss_mode() then return true end
    return host_assign_goal(player_index)
end

local function host_start_round(minutes)
    local players = connected_player_count()
    if players == 0 then
        djui_chat_message_create("No connected players were found.")
        return false
    end
    if (Team.is_mode() or Team.is_chaos_mode()) and players < 2 then
        djui_chat_message_create(Team.is_chaos_mode()
            and "Chaos Mode needs at least two connected players."
            or "Team Mode needs at least two connected players.")
        return false
    end

    local minimum, maximum = configured_time_range(players)
    minutes = clamp(math.floor(minutes), minimum, maximum)

    if not is_boss_mode() and not Team.is_chaos_mode() then
        local available = 0
        for _, goal_data in ipairs(GOALS) do
            if not goal_already_collected(goal_data) then available = available + 1 end
        end
        if available < players then
            djui_chat_message_create("Not enough unused goals. Use a fresh save file.")
            return false
        end
    end

    host_used_goals = {}
    host_seen_done = {}
    host_seen_forfeit = {}
    host_player_records = {}
    math.randomseed(get_global_timer())
    if Team.is_mode() then Team.build_balanced() else Team.initial = {} end
    gGlobalSyncTable.sh5_chaos_roster_locked = 0
    if Team.is_chaos_mode() then
        gGlobalSyncTable.sh5_chaos_level =
            Team.chaos_maps[math.random(#Team.chaos_maps)]
        gGlobalSyncTable.sh5_chaos_act = math.random(6)
        gGlobalSyncTable.sh5_chaos_modifier_1 = 0
        gGlobalSyncTable.sh5_chaos_modifier_2 = 0
        gGlobalSyncTable.sh5_chaos_modifier_seq = 0
        gGlobalSyncTable.sh5_chaos_winner = ""
        gGlobalSyncTable.sh5_chaos_alive = players
    end

    if host_previous_player_interactions == nil then
        host_previous_player_interactions = gServerSettings.playerInteractions
        host_previous_pvp_type = gServerSettings.pvpType
    end
    if is_boss_mode() then
        gServerSettings.playerInteractions = PLAYER_INTERACTIONS_SOLID
        gGlobalSyncTable.sh5_boss_level_index = math.random(#BOSS_LEVELS)
        gGlobalSyncTable.sh5_boss_player_modifier = math.random(#BOSS_PLAYER_MODIFIERS)
        if Team.selected_difficulty() == Team.NIGHTMARE then
            local second_choices = {}
            local first_modifier = BOSS_PLAYER_MODIFIERS[
                gGlobalSyncTable.sh5_boss_player_modifier]
            for index = 1, #BOSS_PLAYER_MODIFIERS do
                if index ~= gGlobalSyncTable.sh5_boss_player_modifier then
                    local candidate = BOSS_PLAYER_MODIFIERS[index]
                    if Team.chaos_pair_allowed(first_modifier, candidate) then
                        table.insert(second_choices, index)
                    end
                end
            end
            gGlobalSyncTable.sh5_boss_player_modifier_2 =
                second_choices[math.random(#second_choices)]
        else
            gGlobalSyncTable.sh5_boss_player_modifier_2 = 0
        end
        -- Three different advantages are drawn for Bowser every battle.
        -- Drawing without replacement prevents duplicate labels/effects.
        local boss_choices = {}
        for index = 1, #BOSS_MODIFIERS do table.insert(boss_choices, index) end
        for slot = 1, #BOSS_MODIFIER_FIELDS do
            local choice = math.random(#boss_choices)
            gGlobalSyncTable[BOSS_MODIFIER_FIELDS[slot]] = boss_choices[choice]
            table.remove(boss_choices, choice)
        end
        local has_active_attack = false
        for _, field in ipairs(BOSS_MODIFIER_FIELDS) do
            if BOSS_ACTIVE_ATTACK_LOOKUP[gGlobalSyncTable[field]] then
                has_active_attack = true
                break
            end
        end
        if not has_active_attack then
            -- All three selected entries are passive, so none of the active
            -- choices can be a duplicate of them.
            gGlobalSyncTable[BOSS_MODIFIER_FIELDS[#BOSS_MODIFIER_FIELDS]] =
                BOSS_ACTIVE_ATTACK_MODIFIERS[math.random(#BOSS_ACTIVE_ATTACK_MODIFIERS)]
        end
        gGlobalSyncTable.sh5_boss_attack_seq = 0
        gGlobalSyncTable.sh5_boss_attack_kind = 0
        for slot = 1, BOSS_ATTACK_QUEUE_SIZE do
            gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)] = 0
        end
        gGlobalSyncTable.sh5_boss_max_health = Team.boss_health_for_difficulty()
        gGlobalSyncTable.sh5_boss_health = gGlobalSyncTable.sh5_boss_max_health
        gGlobalSyncTable.sh5_boss_original_bombs_seen = 0
        gGlobalSyncTable.sh5_boss_extra_bombs_spawned = 0
        gGlobalSyncTable.sh5_boss_attack_frame = get_global_timer() + 5 * FRAMES_PER_SECOND
    else
        gServerSettings.playerInteractions = PLAYER_INTERACTIONS_PVP
        gServerSettings.pvpType = PLAYER_PVP_REVAMPED
        gGlobalSyncTable.sh5_boss_level_index = 0
        gGlobalSyncTable.sh5_boss_player_modifier = 0
        gGlobalSyncTable.sh5_boss_player_modifier_2 = 0
        for _, field in ipairs(BOSS_MODIFIER_FIELDS) do gGlobalSyncTable[field] = 0 end
        gGlobalSyncTable.sh5_boss_attack_kind = 0
        gGlobalSyncTable.sh5_boss_health = 0
        gGlobalSyncTable.sh5_boss_original_bombs_seen = 0
        gGlobalSyncTable.sh5_boss_extra_bombs_spawned = 0
    end

    gGlobalSyncTable.sh5_config_minutes = minutes
    gGlobalSyncTable.sh5_start_frame = get_global_timer()
    gGlobalSyncTable.sh5_end_frame = get_global_timer() + minutes * 60 * FRAMES_PER_SECOND
    gGlobalSyncTable.sh5_chaos_next_reroll = get_global_timer() + CHAOS_REROLL_FRAMES
    gGlobalSyncTable.sh5_result_winner = ""
    gGlobalSyncTable.sh5_result_score = 0
    gGlobalSyncTable.sh5_result_reason = ""
    gGlobalSyncTable.sh5_red_score = 0
    gGlobalSyncTable.sh5_blue_score = 0
    gGlobalSyncTable.sh5_result_red_score = 0
    gGlobalSyncTable.sh5_result_blue_score = 0
    gGlobalSyncTable.sh5_round = (gGlobalSyncTable.sh5_round or 0) + 1
    gGlobalSyncTable.sh5_active = 1
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and not host_prepare_player(i) then
            host_end_round("not enough unused goals")
            djui_chat_message_create("Not enough unused goals. Use a fresh save file.")
            return false
        end
    end
    if Team.is_chaos_mode() then gGlobalSyncTable.sh5_chaos_roster_locked = 1 end

    local mode_name = is_boss_mode() and "BOSS"
        or (Team.is_mode() and "TEAM" or (Team.is_chaos_mode() and "CHAOS" or "NORMAL"))
    if Team.is_mode() then Team.update_scores() end
    djui_popup_create_global("STARHUNT " .. mode_name .. ": " .. tostring(minutes) .. " MINUTES", 1)
    return true
end

local function remember_player_index(index)
    if not network_is_server() or not is_round_active() then return end
    local sync = gPlayerSyncTable[index]
    local network_player = gNetworkPlayers[index]
    if sync == nil or network_player == nil or (sync.sh5_enrolled or 0) ~= 1 then return end
    local name = network_player.name or ""
    local key = player_record_key(index)
    if name == "" or key == nil then return end
    host_player_records[key] = {
        key = key,
        name = name,
        enrolled = 1,
        score = sync.sh5_score or 0,
        goal = sync.sh5_goal or 0,
        modifier = sync.sh5_modifier or 0,
        modifier_2 = sync.sh5_modifier_2 or 0,
        done = sync.sh5_done or 0,
        forfeit = sync.sh5_forfeit or 0,
        manual_reroll_request = sync.sh5_manual_reroll_request or 0,
        manual_reroll_ack = sync.sh5_manual_reroll_ack or 0,
        manual_reroll_ready_frame = sync.sh5_manual_reroll_ready_frame or 0,
        jump_count = sync.sh5_jump_count or -1,
        boss_victory = sync.sh5_boss_victory or 0,
        chaos_eliminated = sync.sh5_chaos_eliminated or 0,
        team = sync.sh5_team or Team.NONE,
        lifetime_stars = sync.sh5_lifetime_stars or 0,
    }
end

local function remember_disconnected_player(m)
    if m ~= nil then remember_player_index(m.playerIndex) end
end

local function mark_connected_player_unenrolled(m)
    if not network_is_server() or not is_round_active() or m == nil or m.playerIndex == 0 then return end
    -- Player sync slots can still contain the previous occupant's values.
    -- Force the host preparation route, which safely restores a matching
    -- reconnect or creates a clean record for a genuinely new participant.
    gPlayerSyncTable[m.playerIndex].sh5_enrolled = 0
end

local function host_add_late_joiner(player_index)
    local sync = gPlayerSyncTable[player_index]
    if (sync.sh5_enrolled or 0) == 1 then return true end
    if host_prepare_player(player_index) then
        djui_chat_message_create(gNetworkPlayers[player_index].name
            .. (Team.is_chaos_mode() and " joined Chaos as a spectator."
                or " joined StarHunt and received a goal!"))
        return true
    end
    sync.sh5_enrolled = -1
    djui_chat_message_create("No unclaimed goal is left for " .. gNetworkPlayers[player_index].name .. ".")
    return false
end

local function host_read_boss_health_report()
    local round = gGlobalSyncTable.sh5_round or 0
    local lowest_health = nil
    for i = 0, MAX_PLAYERS - 1 do
        local sync = gPlayerSyncTable[i]
        if (sync.sh5_boss_health_ready_round or 0) == round then
            local health = clamp(sync.sh5_boss_health_value or Team.boss_max_health(), 0, Team.boss_max_health())
            -- Bowser's health can only decrease inside one round. Keeping the
            -- lowest valid report prevents a newer, stale owner packet from
            -- healing him during lag or an ownership transfer.
            if lowest_health == nil or health < lowest_health then lowest_health = health end
        end
    end
    return lowest_health
end

Team.boss_reserve_bomb_count = function()
    local difficulty = Team.selected_difficulty()
    if difficulty == Team.HARD then return 2 end
    if difficulty == Team.NIGHTMARE then return 4 end
    return 0
end

-- Only the current host observes the native bomb supply and creates the
-- reserve. The synchronized flags make this one-shot survive a host change:
-- a replacement host cannot mistake its own level load for a new wave.
Team.host_update_boss_bomb_supply = function()
    if not network_is_server() or not is_round_active() or not is_boss_mode()
        or gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then
        return
    end

    local round = gGlobalSyncTable.sh5_round or 0
    if Team.bossBombSupplyRound ~= round then
        Team.bossBombSupplyRound = round
        Team.bossBombZeroSince = nil
    end

    local reserve_count = Team.boss_reserve_bomb_count()
    local already_spawned = gGlobalSyncTable.sh5_boss_extra_bombs_spawned or 0
    if reserve_count == 0 or already_spawned >= reserve_count then return end

    local behavior = get_behavior_from_id(id_bhvBowserBomb)
    local active_bombs = count_objects_with_behavior(behavior)
    if (gGlobalSyncTable.sh5_boss_original_bombs_seen or 0) == 0 then
        -- A zero during the level-loading frames is not an exhausted arena.
        -- Arm the reserve only after this host has observed the native set.
        if active_bombs >= #Team.bossBombPositions then
            gGlobalSyncTable.sh5_boss_original_bombs_seen = 1
            Team.bossBombZeroSince = nil
        end
        return
    end
    if active_bombs > 0 then
        Team.bossBombZeroSince = nil
        return
    end

    -- Require one continuous second at zero. Besides filtering the native
    -- explosion transition, this gives a newly promoted host time to receive
    -- synchronized objects before it decides that the arena is empty.
    if Team.bossBombZeroSince == nil then
        Team.bossBombZeroSince = get_global_timer()
        return
    end
    if get_global_timer() - Team.bossBombZeroSince < FRAMES_PER_SECOND then return end

    local available = {}
    for index = 1, #Team.bossBombPositions do available[index] = index end
    local spawned = 0
    for _ = 1, reserve_count - already_spawned do
        local choice = math.random(#available)
        local position = Team.bossBombPositions[available[choice]]
        table.remove(available, choice)
        local bomb = spawn_sync_object(
            id_bhvBowserBomb, E_MODEL_BOWSER_BOMB,
            position.x, position.y, position.z,
            function(object)
                object.oHomeX = position.x
                object.oHomeY = position.y
                object.oHomeZ = position.z
            end)
        if bomb ~= nil then spawned = spawned + 1 end
    end
    -- spawn_sync_object is synchronous. Publish only completed creations; if
    -- one fails, the host may supply only the missing amount after the arena
    -- is empty again instead of duplicating the successful objects.
    gGlobalSyncTable.sh5_boss_extra_bombs_spawned = already_spawned + spawned
    Team.bossBombZeroSince = nil
end

local function host_update_boss_round()
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_boss_victory or 0) > 0 then
            host_end_round("boss defeated")
            return
        end
        if gNetworkPlayers[i].connected and (gPlayerSyncTable[i].sh5_enrolled or 0) == 0 then
            host_prepare_player(i)
            djui_chat_message_create(gNetworkPlayers[i].name .. " joined the Bowser battle!")
        end
        if gNetworkPlayers[i].connected then remember_player_index(i) end
    end

    local level_index = gGlobalSyncTable.sh5_boss_level_index or 0
    local boss_level = BOSS_LEVELS[level_index]
    local boss_ready = false
    local reported_health = host_read_boss_health_report()
    if reported_health ~= nil then
        local authoritative = clamp(gGlobalSyncTable.sh5_boss_health or Team.boss_max_health(), 0, Team.boss_max_health())
        gGlobalSyncTable.sh5_boss_health = math.min(authoritative, reported_health)
        reported_health = gGlobalSyncTable.sh5_boss_health
        if reported_health <= 0 then
            host_end_round("boss defeated")
            return
        end
    end
    if boss_level ~= nil and gNetworkPlayers[0].currLevelNum == boss_level then
        local bowser = obj_get_first_with_behavior_id(id_bhvBowser)
        if bowser ~= nil then
            -- Action 4 is Bowser's vanilla death sequence. End immediately,
            -- before he can open a dialog, create a key cutscene or trigger
            -- the final-star cinematic.
            if bowser.oAction == 4 then
                host_end_round("boss defeated")
                return
            end
            -- Actions 5, 6 and 20 belong to Bowser's multiplayer intro.
            -- Hazards must not begin while a player is still trapped in it.
            boss_ready = bowser.oAction ~= 5 and bowser.oAction ~= 6 and bowser.oAction ~= 20
        end
    end

    Team.host_update_boss_bomb_supply()

    -- A temporarily missing Bowser can be caused by lag, ownership transfer or
    -- a player respawning. Never interpret that as a victory and never queue
    -- attacks without a valid, active boss.
    if not boss_ready then
        gGlobalSyncTable.sh5_boss_attack_frame = get_global_timer() + FRAMES_PER_SECOND
        return
    end

    local attack_choices = {}
    if boss_has_modifier(2) then table.insert(attack_choices, 2) end
    if boss_has_modifier(3) then table.insert(attack_choices, 3) end
    if boss_has_modifier(5) then table.insert(attack_choices, 5) end
    if boss_has_modifier(6) then table.insert(attack_choices, 6) end
    if boss_has_modifier(7) then table.insert(attack_choices, 7) end
    if boss_has_modifier(8) then table.insert(attack_choices, 8) end
    if boss_has_modifier(9) then table.insert(attack_choices, 9) end
    if boss_has_modifier(10) then table.insert(attack_choices, 10) end
    if boss_has_modifier(11) then table.insert(attack_choices, 11) end
    if #attack_choices > 0 and get_global_timer() >= (gGlobalSyncTable.sh5_boss_attack_frame or 0) then
        local attack_index = attack_choices[math.random(#attack_choices)]
        local attack_seq = (gGlobalSyncTable.sh5_boss_attack_seq or 0) + 1
        local queue_slot = ((attack_seq - 1) % BOSS_ATTACK_QUEUE_SIZE) + 1
        gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(queue_slot)] = attack_index
        gGlobalSyncTable.sh5_boss_attack_seq = attack_seq
        gGlobalSyncTable.sh5_boss_attack_kind = attack_index
        local attack_intervals = { [2] = 7, [3] = 6, [5] = 9, [6] = 8, [7] = 10, [8] = 9, [9] = 11, [10] = 8, [11] = 7 }
        local interval = attack_intervals[attack_index] or 8
        -- Rage and the desperate phase speed up only StarHunt's separate
        -- hazards. They never alter Bowser's action, movement or held state.
        if boss_has_modifier(4) then interval = math.max(4, math.floor(interval * 0.8)) end
        if boss_is_desperate() then interval = math.max(4, math.floor(interval * 0.65)) end
        local difficulty_factors = { 1.35, 1.0, 0.78, 0.55 }
        interval = math.max(Team.selected_difficulty() == Team.NIGHTMARE and 2 or 3,
            math.floor(interval * difficulty_factors[Team.selected_difficulty() + 1] + 0.5))
        gGlobalSyncTable.sh5_boss_attack_frame = get_global_timer() + interval * FRAMES_PER_SECOND
    end
end

-- Bowser uses dynamic object ownership. Only the client that currently owns
-- the synchronized object may initialize his five health points; otherwise a
-- later full-object packet can silently restore the vanilla value.
local function ensure_boss_health_owner()
    if not is_round_active() or not is_boss_mode()
        or gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then
        local_boss_health_object = nil
        local_boss_health_initialized = false
        local_boss_health_last_value = nil
        local_boss_health_report_at = 0
        return
    end

    local bowser = obj_get_first_with_behavior_id(id_bhvBowser)
    if bowser ~= local_boss_health_object then
        local_boss_health_object = bowser
        local_boss_health_initialized = false
        local_boss_health_last_value = nil
    end
    if bowser == nil then return end

    local round = gGlobalSyncTable.sh5_round or 0
    local health_was_initialized = false
    for i = 0, MAX_PLAYERS - 1 do
        if (gPlayerSyncTable[i].sh5_boss_health_ready_round or 0) == round then
            health_was_initialized = true
            break
        end
    end

    local sync_id = bowser.oSyncID
    if sync_id == nil or sync_id == 0 or not sync_object_is_owned_locally(sync_id) then return end

    if not local_boss_health_initialized then
        local authoritative = clamp(gGlobalSyncTable.sh5_boss_health or Team.boss_max_health(), 0, Team.boss_max_health())
        if health_was_initialized then
            -- Never increase a synchronized object's already lower value.
            bowser.oHealth = math.min(clamp(bowser.oHealth or authoritative, 0, Team.boss_max_health()), authoritative)
        else
            bowser.oHealth = Team.boss_max_health()
        end
        network_send_object(bowser, true)
        gPlayerSyncTable[0].sh5_boss_health_ready_round = round
        local_boss_health_initialized = true
    end

    -- The current owner publishes the authoritative remaining health. If
    -- ownership or the object changes, the next owner restores this value
    -- instead of healing Bowser or reverting him to vanilla health.
    if bowser.oHealth ~= local_boss_health_last_value
        or get_global_timer() >= local_boss_health_report_at then
        local_boss_health_last_value = bowser.oHealth
        local_boss_health_report_at = get_global_timer() + 5
        gPlayerSyncTable[0].sh5_boss_health_ready_round = round
        gPlayerSyncTable[0].sh5_boss_health_value = clamp(bowser.oHealth, 0, Team.boss_max_health())
        gPlayerSyncTable[0].sh5_boss_health_tick = get_global_timer()
    end
end

local function on_before_boss_cutscene(m, incoming_action, _)
    if m.playerIndex ~= 0 or not is_round_active() or not is_boss_mode() then return end
    if incoming_action ~= ACT_STAR_DANCE_EXIT and incoming_action ~= ACT_STAR_DANCE_WATER
        and incoming_action ~= ACT_STAR_DANCE_NO_EXIT and incoming_action ~= ACT_JUMBO_STAR_CUTSCENE then
        return
    end

    -- Fallback for unusual Bowser behavior mods: the winning player reports
    -- the victory and cancels the cinematic on its very first frame.
    gPlayerSyncTable[0].sh5_boss_victory = (gPlayerSyncTable[0].sh5_boss_victory or 0) + 1
    if network_is_server() then host_end_round("boss defeated") end
    return 1
end

Team.host_reroll_chaos_modifiers = function()
    if not Team.is_chaos_mode() then return end
    local now = get_global_timer()
    if now < (gGlobalSyncTable.sh5_chaos_next_reroll or 0) then return end
    local assigned = false
    for i = 0, MAX_PLAYERS - 1 do
        local sync = gPlayerSyncTable[i]
        if gNetworkPlayers[i].connected and (sync.sh5_enrolled or 0) == 1
            and (sync.sh5_chaos_eliminated or 0) == 0 then
            local first, second
            first, second = Team.pick_chaos_pair(sync.sh5_modifier or 0)
            if first ~= 0 then
                sync.sh5_modifier = first
                sync.sh5_modifier_2 = second
                assigned = true
            end
            local first_data = Team.effective_modifier(NORMAL_MODIFIER_CATALOG[first])
            local second_data = Team.effective_modifier(NORMAL_MODIFIER_CATALOG[second])
            sync.sh5_jump_count = first_data ~= nil and first_data.kind == "jump_limit" and first_data.value
                or (second_data ~= nil and second_data.kind == "jump_limit" and second_data.value or -1)
        end
    end
    if assigned then
        gGlobalSyncTable.sh5_chaos_modifier_seq =
            (gGlobalSyncTable.sh5_chaos_modifier_seq or 0) + 1
    end
    gGlobalSyncTable.sh5_chaos_next_reroll = now + CHAOS_REROLL_FRAMES
end

Team.host_update_chaos_round = function()
    Team.host_reroll_chaos_modifiers()
    local alive_count, alive_name = 0, "Nobody"
    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            local sync = gPlayerSyncTable[i]
            if (sync.sh5_enrolled or 0) == 0 then host_add_late_joiner(i) end
            if (sync.sh5_enrolled or 0) == 1 and (sync.sh5_chaos_eliminated or 0) == 0 then
                alive_count = alive_count + 1
                alive_name = gNetworkPlayers[i].name or "Player"
            end
            remember_player_index(i)
        end
    end
    gGlobalSyncTable.sh5_chaos_alive = alive_count
    if (gGlobalSyncTable.sh5_chaos_roster_locked or 0) == 1 and alive_count <= 1 then
        gGlobalSyncTable.sh5_chaos_winner = alive_count == 1 and alive_name or "Nobody"
        host_end_round("chaos last standing")
    end
end

local function host_update_round()
    if not network_is_server() or not is_round_active() then return end

    if get_global_timer() >= (gGlobalSyncTable.sh5_end_frame or 0) then
        host_end_round(is_boss_mode() and "boss time expired" or "time expired")
        return
    end


    if is_boss_mode() then
        host_update_boss_round()
        return
    end

    if Team.is_chaos_mode() then
        Team.host_update_chaos_round()
        return
    end

    for i = 0, MAX_PLAYERS - 1 do
        if gNetworkPlayers[i].connected then
            local sync = gPlayerSyncTable[i]
            if (sync.sh5_enrolled or 0) == 0 then
                host_add_late_joiner(i)
            end

            if (sync.sh5_enrolled or 0) == 1 then
                local manual_request = sync.sh5_manual_reroll_request or 0
                local manual_ack = sync.sh5_manual_reroll_ack or 0
                if manual_request ~= manual_ack then
                    sync.sh5_manual_reroll_ack = manual_request
                    if get_global_timer() >= (sync.sh5_manual_reroll_ready_frame or 0)
                        and (sync.sh5_goal or 0) ~= 0 then
                        local old_goal = get_goal(sync.sh5_goal or 0)
                        local old_modifier = old_goal
                            and old_goal.mods[sync.sh5_modifier or 0] or nil
                        host_assign_goal(i, old_modifier and old_modifier.kind or nil,
                            old_goal and old_goal.level or nil)
                    end
                end

                local forfeits = sync.sh5_forfeit or 0
                if host_seen_forfeit[i] == nil then host_seen_forfeit[i] = forfeits end
                if forfeits ~= host_seen_forfeit[i] then
                    host_seen_forfeit[i] = forfeits
                    local old_goal = get_goal(sync.sh5_goal or 0)
                    local old_modifier = old_goal and old_goal.mods[sync.sh5_modifier or 0]
                    sync.sh5_goal = 0
                    sync.sh5_modifier = 0
                    sync.sh5_modifier_2 = 0
                    sync.sh5_jump_count = -1
                    if not host_assign_goal(i, old_modifier and old_modifier.kind or nil) then
                        host_end_round("all available goals were assigned")
                        return
                    end
                end

                local done = sync.sh5_done or 0
                if host_seen_done[i] == nil then host_seen_done[i] = done end
                if done ~= host_seen_done[i] then
                    host_seen_done[i] = done
                    if (sync.sh5_goal or 0) ~= 0 then
                        sync.sh5_score = (sync.sh5_score or 0) + 1
                        sync.sh5_goal = 0
                        sync.sh5_modifier = 0
                        sync.sh5_modifier_2 = 0
                        sync.sh5_jump_count = -1
                        if not host_assign_goal(i) then
                            host_end_round("all available goals were assigned")
                            return
                        end
                    end
                end
            end
            remember_player_index(i)
        end
    end
    if Team.is_mode() then Team.update_scores() end
end

-- Capping a vector, rather than multiplying it every frame, is stable and
-- avoids the progressive swim slowdown from the first version.
local function capped_horizontal_velocity(x, z, cap)
    local length = math.sqrt(x * x + z * z)
    if length > cap and length > 0 then
        local scale = cap / length
        return x * scale, z * scale
    end
    return x, z
end

local function swap_button_bits(bits, first, second)
    local has_first = (bits & first) ~= 0
    local has_second = (bits & second) ~= 0
    bits = bits & ~(first | second)
    if has_first then bits = bits | second end
    if has_second then bits = bits | first end
    return bits
end

local function rotate_stick(x, y, angle)
    local cosine, sine = math.cos(angle), math.sin(angle)
    return x * cosine - y * sine, x * sine + y * cosine
end

local function suppress_local_input(m)
    m.controller.buttonDown = 0
    m.controller.buttonPressed = 0
    m.controller.stickX = 0
    m.controller.stickY = 0
    m.controller.rawStickX = 0
    m.controller.rawStickY = 0
    m.intendedMag = 0
    if (m.action & ACT_FLAG_AIR) == 0 then m.forwardVel = 0 end
end

Team.apply_one_local_modifier = function(m)
    if m.playerIndex ~= 0 or not is_round_active() then return end
    if Team.is_chaos_mode() and (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1 then return end
    -- The configuration menu owns the controller completely. No challenge
    -- may remap or consume A/B, the stick, or the close button before it.
    if config_open then return end
    local modifier_data = Team.modifier_override or get_local_modifier()
    if modifier_data == nil then return end
    local ready_key
    if is_boss_mode() then
        if gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then return end
        ready_key = -(gGlobalSyncTable.sh5_round or 0)
    elseif Team.is_chaos_mode() then
        if gNetworkPlayers[0].currLevelNum ~= (gGlobalSyncTable.sh5_chaos_level or -1) then return end
        ready_key = 1000000 + (gGlobalSyncTable.sh5_chaos_modifier_seq or 0)
    else
        local goal = get_local_goal()
        if goal == nil or not goal_matches_player_area(goal, 0) then return end
        ready_key = gPlayerSyncTable[0].sh5_goal_seq or (gPlayerSyncTable[0].sh5_goal or 0)
    end
    if local_runtime.modifier_ready_key ~= ready_key then
        reset_local_modifier_state()
        local_runtime.modifier_ready_key = ready_key
    end

    -- Initialize the modifier clock before testing a pulsed Easy effect.
    -- Otherwise the first active frame resets the clock and collapses the
    -- intended multi-second window to a single frame.
    if modifier_data.pulse_period ~= nil
        and not Team.periodic_window(modifier_data.pulse_period, modifier_data.pulse_frames) then
        if modifier_data.kind == "periodic_freeze" then
            local_runtime.freeze_frames = 0
            local_runtime.freeze_yaw = nil
        elseif modifier_data.kind == "slippery" then
            -- Easy leaves Slippery inactive for six seconds. A new pulse must
            -- start from the current movement, not revive its previous speed.
            local_runtime.slip_speed = 0
        end
        return
    end

    if modifier_data.kind == "no_b" then
        m.controller.buttonDown = m.controller.buttonDown & ~B_BUTTON
        m.controller.buttonPressed = m.controller.buttonPressed & ~B_BUTTON

    elseif modifier_data.kind == "floor_doom" then
        if is_local_player_on_floor(m) then
            local_runtime.floor_frames = local_runtime.floor_frames + 1
            if local_runtime.floor_frames >= modifier_data.value * FRAMES_PER_SECOND then
                m.health = 0
                local_runtime.floor_frames = 0
                djui_popup_create(translated("THE CURSED FLOOR GOT YOU!", "EL PISO MALDITO TE ATRAPO!"), 1)
            end
        else
            local_runtime.floor_frames = 0
        end

    elseif modifier_data.kind == "speed_cap" then
        if m.forwardVel > modifier_data.value then m.forwardVel = modifier_data.value end
        if m.forwardVel < -modifier_data.value then m.forwardVel = -modifier_data.value end
        if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end

    elseif modifier_data.kind == "low_jump" then
        if (m.action & ACT_FLAG_AIR) ~= 0 and m.vel.y > modifier_data.value then
            m.vel.y = modifier_data.value
        end

    elseif modifier_data.kind == "water_cap" then
        if (m.action & ACT_FLAG_SWIMMING) ~= 0 then
            m.vel.x, m.vel.z = capped_horizontal_velocity(m.vel.x, m.vel.z, modifier_data.value)
            if m.vel.y > modifier_data.value then m.vel.y = modifier_data.value end
            if m.vel.y < -modifier_data.value then m.vel.y = -modifier_data.value end
            if m.forwardVel > modifier_data.value then m.forwardVel = modifier_data.value end
            if m.forwardVel < -modifier_data.value then m.forwardVel = -modifier_data.value end
        end

    elseif modifier_data.kind == "jump_limit" then
        if is_local_player_on_floor(m) and (m.controller.buttonPressed & A_BUTTON) ~= 0 then
            local left = gPlayerSyncTable[0].sh5_jump_count
            if left == nil then left = modifier_data.value end
            if left > 0 then
                local remaining = left - 1
                gPlayerSyncTable[0].sh5_jump_count = remaining
                if remaining == 0 then
                    m.health = 0
                    djui_popup_create(translated("NO JUMPS LEFT!", "NO QUEDAN SALTOS!"), 1)
                end
            else
                m.controller.buttonPressed = m.controller.buttonPressed & ~A_BUTTON
                m.controller.buttonDown = m.controller.buttonDown & ~A_BUTTON
                m.health = 0
                djui_popup_create(translated("NO JUMPS LEFT!", "NO QUEDAN SALTOS!"), 1)
            end
        end

    elseif modifier_data.kind == "reverse_controls" then
        m.controller.stickX = -m.controller.stickX
        m.controller.stickY = -m.controller.stickY
        m.controller.rawStickX = -m.controller.rawStickX
        m.controller.rawStickY = -m.controller.rawStickY

    elseif modifier_data.kind == "periodic_freeze" then
        local period = math.max(3, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / period)
        if tick > 0 and tick ~= local_runtime.freeze_tick then
            local_runtime.freeze_tick = tick
            local_runtime.freeze_frames = modifier_data.freeze_frames or 24
            local_runtime.freeze_yaw = nil
        end
        if local_runtime.freeze_frames > 0 then
            if local_runtime.freeze_yaw == nil then
                local_runtime.freeze_yaw = m.faceAngle ~= nil and m.faceAngle.y or m.intendedYaw
            end
            suppress_local_input(m)
            if local_runtime.freeze_yaw ~= nil then
                if m.faceAngle ~= nil then m.faceAngle.y = local_runtime.freeze_yaw end
                m.intendedYaw = local_runtime.freeze_yaw
            end
            local_runtime.freeze_frames = local_runtime.freeze_frames - 1
        else
            local_runtime.freeze_yaw = nil
        end

    elseif modifier_data.kind == "fragile" then
        local health_cap = modifier_data.health_cap or 0x400
        if m.health > health_cap then m.health = health_cap end

    elseif modifier_data.kind == "high_gravity" then
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            m.vel.y = math.max(-75, m.vel.y - modifier_data.value)
        end

    elseif modifier_data.kind == "wind_gust" then
        local period = math.max(4, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = get_global_timer() - local_runtime.modifier_start_frame
        local tick = math.floor(math.max(0, elapsed) / period)
        if tick > 0 and tick ~= local_runtime.wind_tick then
            local_runtime.wind_tick = tick
            local seed = (gPlayerSyncTable[0].sh5_goal_seq or 1) * 1.73 + elapsed * 0.013
            m.vel.x = m.vel.x + math.sin(seed) * 38
            m.vel.z = m.vel.z + math.cos(seed) * 38
        end

    elseif modifier_data.kind == "no_z" then
        m.controller.buttonDown = m.controller.buttonDown & ~Z_TRIG
        m.controller.buttonPressed = m.controller.buttonPressed & ~Z_TRIG

    elseif modifier_data.kind == "air_brake" then
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            -- intendedMag is recalculated by the engine after
            -- HOOK_BEFORE_MARIO_UPDATE, so scale the actual controller input.
            local scale = modifier_data.value / 100
            m.controller.stickX = m.controller.stickX * scale
            m.controller.stickY = m.controller.stickY * scale
            m.controller.rawStickX = m.controller.rawStickX * scale
            m.controller.rawStickY = m.controller.rawStickY * scale
            m.intendedMag = m.intendedMag * scale
        end

    elseif modifier_data.kind == "lava_clock" then
        local period = math.max(6, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / period)
        if tick > 0 and tick ~= local_runtime.modifier_tick then
            local_runtime.modifier_tick = tick
            local damage = modifier_data.damage_amount or 0x100
            if m.health <= damage + 0x80 then m.health = 0 else m.health = m.health - damage end
        end

    elseif modifier_data.kind == "turbo" then
        if m.intendedMag > 10 and math.abs(m.forwardVel) > 2 then
            local sign = m.forwardVel < 0 and -1 or 1
            m.forwardVel = sign * math.min(modifier_data.value, math.abs(m.forwardVel) * 1.035 + 0.35)
        end

    elseif modifier_data.kind == "slippery" then
        if is_local_player_on_floor(m) then
            if math.abs(m.forwardVel) > math.abs(local_runtime.slip_speed) then
                local_runtime.slip_speed = m.forwardVel
            elseif math.abs(local_runtime.slip_speed) > math.abs(m.forwardVel) then
                m.forwardVel = local_runtime.slip_speed
            end
            if local_runtime.slip_speed > 0 then
                local_runtime.slip_speed = math.max(0, local_runtime.slip_speed - 0.35)
            else
                local_runtime.slip_speed = math.min(0, local_runtime.slip_speed + 0.35)
            end
        else
            local_runtime.slip_speed = m.forwardVel
        end

    elseif modifier_data.kind == "swap_ab" then
        m.controller.buttonDown = swap_button_bits(m.controller.buttonDown, A_BUTTON, B_BUTTON)
        m.controller.buttonPressed = swap_button_bits(m.controller.buttonPressed, A_BUTTON, B_BUTTON)

    elseif modifier_data.kind == "keep_moving" then
        local moved = true
        if local_runtime.last_move_x ~= nil and local_runtime.last_move_z ~= nil then
            local dx = m.pos.x - local_runtime.last_move_x
            local dz = m.pos.z - local_runtime.last_move_z
            moved = dx * dx + dz * dz >= 1
        end
        local_runtime.last_move_x = m.pos.x
        local_runtime.last_move_z = m.pos.z
        if is_local_player_on_floor(m) then
            if moved then
                local_runtime.idle_frames = 0
            else
                local_runtime.idle_frames = local_runtime.idle_frames + 1
                if local_runtime.idle_frames >= modifier_data.value * FRAMES_PER_SECOND then
                    m.health = 0
                    local_runtime.idle_frames = 0
                    djui_popup_create(translated("KEEP MOVING!", "SIGUE MOVIENDOTE!"), 1)
                end
            end
        else
            local_runtime.idle_frames = 0
        end

    elseif modifier_data.kind == "jump_cooldown" then
        if local_runtime.jump_cooldown_frames > 0 then
            local_runtime.jump_cooldown_frames = local_runtime.jump_cooldown_frames - 1
            if (m.controller.buttonPressed & A_BUTTON) ~= 0 then
                m.controller.buttonPressed = m.controller.buttonPressed & ~A_BUTTON
                m.controller.buttonDown = m.controller.buttonDown & ~A_BUTTON
            end
        elseif is_local_player_on_floor(m) and (m.controller.buttonPressed & A_BUTTON) ~= 0 then
            local_runtime.jump_cooldown_frames = modifier_data.value
        end

    elseif modifier_data.kind == "coin_surge" then
        local coins = Team.coin_count(m)
        if local_runtime.last_coin_count ~= nil and coins > local_runtime.last_coin_count then
            local gained = math.min(2, coins - local_runtime.last_coin_count)
            m.forwardVel = math.min(64, math.max(0, m.forwardVel) + modifier_data.value * gained)
        end
        local_runtime.last_coin_count = coins

    elseif modifier_data.kind == "control_drift" then
        local elapsed = get_global_timer() - local_runtime.modifier_start_frame
        local max_angle = math.rad(modifier_data.value)
        local angle = math.sin(elapsed / 24) * max_angle
        m.controller.stickX, m.controller.stickY = rotate_stick(m.controller.stickX, m.controller.stickY, angle)
        m.controller.rawStickX, m.controller.rawStickY = rotate_stick(
            m.controller.rawStickX, m.controller.rawStickY, angle)

    elseif modifier_data.kind == "mirrored_steering" then
        m.controller.stickX = -m.controller.stickX
        m.controller.rawStickX = -m.controller.rawStickX

    elseif modifier_data.kind == "coin_leak" then
        local period = math.max(3, modifier_data.value) * FRAMES_PER_SECOND
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / period)
        if tick > 0 and tick ~= local_runtime.coin_leak_tick then
            local_runtime.coin_leak_tick = tick
            m.numCoins = math.max(0, (m.numCoins or 0) - 1)
        end

    elseif modifier_data.kind == "slow_pulse" then
        if Team.periodic_window(8, 45) then
            m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
            if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end
        end

    elseif modifier_data.kind == "air_mirror" then
        if (m.action & ACT_FLAG_AIR) ~= 0 then
            m.controller.stickX = -m.controller.stickX
            m.controller.rawStickX = -m.controller.rawStickX
        end

    elseif modifier_data.kind == "momentum_burst" then
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        local tick = math.floor(elapsed / (8 * FRAMES_PER_SECOND))
        if tick > 0 and tick ~= local_runtime.momentum_tick then
            local_runtime.momentum_tick = tick
            if is_local_player_on_floor(m) and m.intendedMag > 10 then
                local sign = m.forwardVel < 0 and -1 or 1
                m.forwardVel = sign * math.min(60, math.abs(m.forwardVel) + modifier_data.value)
            end
        end

    elseif modifier_data.kind == "control_pulse" then
        if Team.periodic_window(9, modifier_data.value) then
            m.controller.stickX = -m.controller.stickX
            m.controller.stickY = -m.controller.stickY
            m.controller.rawStickX = -m.controller.rawStickX
            m.controller.rawStickY = -m.controller.rawStickY
        end

    elseif modifier_data.kind == "coin_weight" then
        local speed = math.max(35, modifier_data.value - math.floor(Team.coin_count(m) / 5))
        m.forwardVel = clamp(m.forwardVel, -speed, speed)
        if m.intendedMag > speed then m.intendedMag = speed end

    elseif modifier_data.kind == "gravity_wave" then
        local elapsed = math.max(0, get_global_timer() - local_runtime.modifier_start_frame)
        if math.floor(elapsed / (3 * FRAMES_PER_SECOND)) % 2 == 1
            and (m.action & ACT_FLAG_AIR) ~= 0 then
            m.vel.y = math.max(-75, m.vel.y - modifier_data.value)
        end

    elseif modifier_data.kind == "overheat" then
        if is_local_player_on_floor(m) and math.abs(m.forwardVel) > 48 then
            local_runtime.overheat_frames = local_runtime.overheat_frames + 1
            if local_runtime.overheat_frames >= modifier_data.value * FRAMES_PER_SECOND then
                local_runtime.overheat_frames = 0
                local damage = modifier_data.damage_amount or 0x100
                if m.health <= damage + 0x80 then m.health = 0 else m.health = m.health - damage end
                djui_popup_create(translated("OVERHEATED! SLOW DOWN!", "SOBRECALENTADO! FRENA!"), 1)
            end
        else
            local_runtime.overheat_frames = math.max(0, local_runtime.overheat_frames - 2)
        end

    elseif modifier_data.kind == "coin_toll" or modifier_data.kind == "darkness_pulse" then
        -- These modifiers are enforced by star interaction/HUD rendering.
    end
end

Team.apply_local_modifier = function(m)
    local modifiers = Team.get_local_modifiers()
    for _, modifier_data in ipairs(modifiers) do
        Team.modifier_override = modifier_data
        Team.apply_one_local_modifier(m)
    end
    Team.modifier_override = nil
end

-- Character/moveset mods run their own HOOK_MARIO_UPDATE callbacks and may
-- replace velocities after StarHunt's before-update challenge pass. Reapply
-- only idempotent limits here: effects such as gravity, turbo, slippery
-- movement and remapped controls must never be applied twice in one frame.
Team.apply_post_moveset_limits = function(m)
    if m.playerIndex ~= 0 or config_open or not is_round_active() then return end
    if is_boss_mode() then
        if gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then return end
    elseif Team.is_chaos_mode() then
        if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1
            or gNetworkPlayers[0].currLevelNum ~= (gGlobalSyncTable.sh5_chaos_level or -1) then
            return
        end
    else
        local goal = get_local_goal()
        if goal == nil or not goal_matches_player_area(goal, 0) then return end
    end

    -- Mario actions and custom movesets may rotate the model after the
    -- before-update input lock. Reapply the captured yaw on the same frame so
    -- a freeze is visually stable as well as mechanically stable.
    if local_runtime.freeze_yaw ~= nil then
        if m.faceAngle ~= nil then m.faceAngle.y = local_runtime.freeze_yaw end
        m.intendedYaw = local_runtime.freeze_yaw
    end

    for _, modifier_data in ipairs(Team.get_local_modifiers()) do
        local pulse_active = modifier_data.pulse_period == nil
            or Team.periodic_window(modifier_data.pulse_period, modifier_data.pulse_frames)
        if pulse_active and modifier_data.kind == "speed_cap" then
            m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
            if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end
        elseif pulse_active and modifier_data.kind == "low_jump" then
            if (m.action & ACT_FLAG_AIR) ~= 0 and m.vel.y > modifier_data.value then
                m.vel.y = modifier_data.value
            end
        elseif pulse_active and modifier_data.kind == "water_cap" then
            if (m.action & ACT_FLAG_SWIMMING) ~= 0 then
                m.vel.x, m.vel.z = capped_horizontal_velocity(m.vel.x, m.vel.z, modifier_data.value)
                m.vel.y = clamp(m.vel.y, -modifier_data.value, modifier_data.value)
                m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
            end
        elseif pulse_active and modifier_data.kind == "fragile" then
            local health_cap = modifier_data.health_cap or 0x400
            if m.health > health_cap then m.health = health_cap end
        elseif pulse_active and modifier_data.kind == "slow_pulse" then
            if Team.periodic_window(8, 45) then
                m.forwardVel = clamp(m.forwardVel, -modifier_data.value, modifier_data.value)
                if m.intendedMag > modifier_data.value then m.intendedMag = modifier_data.value end
            end
        elseif pulse_active and modifier_data.kind == "coin_weight" then
            local speed = math.max(35, modifier_data.value - math.floor(Team.coin_count(m) / 5))
            m.forwardVel = clamp(m.forwardVel, -speed, speed)
            if m.intendedMag > speed then m.intendedMag = speed end
        end
    end
end

-- StarHunt has no game-over state: deaths only lead to a new challenge.
-- Keep a high life count every frame, including the frame in which Mario dies.
local function grant_infinite_lives(m)
    if m.playerIndex ~= 0 then return end
    if is_round_active() then
        if local_runtime.lives_before_round == nil then local_runtime.lives_before_round = m.numLives end
        m.numLives = 99
    elseif local_runtime.lives_before_round ~= nil then
        m.numLives = local_runtime.lives_before_round
        local_runtime.lives_before_round = nil
    end
end

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
    local goal = is_round_active() and not is_boss_mode() and get_local_goal() or nil
    if goal ~= nil and not goal_matches_player_area(goal, 0) then goal = nil end
    local desired = goal ~= nil and goal.power or nil

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

local function local_goal_warp_update(m)
    if m.playerIndex ~= 0 then return end
    if is_boss_mode() or Team.is_chaos_mode() then return end

    local current_goal_id = gPlayerSyncTable[0].sh5_goal or 0
    local current_goal = get_goal(current_goal_id)
    if is_round_active() and current_goal ~= nil and current_goal.level == LEVEL_TTC then
        -- Direct warps do not pass through the castle clock face. Keep TTC
        -- deterministic: slow for traversal stars and stopped for red coins.
        local desired_speed = current_goal.act == 6 and TTC_SPEED_STOPPED or TTC_SPEED_SLOW
        if get_ttc_speed_setting() ~= desired_speed then set_ttc_speed_setting(desired_speed) end
    end
    if is_round_active() and current_goal_id ~= local_runtime.goal_id then
        local_runtime.goal_id = current_goal_id
        local_runtime.goal_warp_at = get_global_timer() + (local_runtime.death_warp_pending and 0 or NEXT_GOAL_DELAY)
        local_runtime.star_visibility_next = 0
        local_runtime.modifier_ready_key = nil
        reset_local_modifier_state()
    elseif not is_round_active() then
        local_runtime.goal_id = 0
        local_runtime.goal_warp_at = -1
        local_runtime.modifier_ready_key = nil
        local_runtime.death_lock = false
        local_runtime.death_warp_pending = false
        reset_local_modifier_state()
    end

    if is_round_active() and current_goal_id ~= 0 and local_runtime.goal_warp_at >= 0
        and get_global_timer() >= local_runtime.goal_warp_at and not is_transition_playing() then
        local goal = get_goal(current_goal_id)
        if goal ~= nil then warp_to_level(goal.level, 1, goal.act) end
        local_runtime.goal_warp_at = -1
        local_runtime.death_lock = false
        local_runtime.death_warp_pending = false
    end
end

Team.update_chaos_warp = function(m)
    if m.playerIndex ~= 0 then return end
    if not is_round_active() or not Team.is_chaos_mode() then
        local_runtime.chaos_round_seen = -1
        local_runtime.chaos_warp_at = -1
        local_runtime.chaos_spectator_warped = false
        return
    end

    local round = gGlobalSyncTable.sh5_round or 0
    if local_runtime.chaos_round_seen ~= round then
        local_runtime.chaos_round_seen = round
        local_runtime.chaos_warp_at = get_global_timer() + NEXT_GOAL_DELAY
        local_runtime.chaos_spectator_warped = false
        local_runtime.modifier_ready_key = nil
        reset_local_modifier_state()
    end

    if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1 then
        if not local_runtime.chaos_spectator_warped and not is_transition_playing() then
            warp_to_level(LEVEL_CASTLE_GROUNDS, 1, 1)
            local_runtime.chaos_spectator_warped = true
        end
        return
    end

    if local_runtime.chaos_warp_at >= 0
        and get_global_timer() >= local_runtime.chaos_warp_at
        and not is_transition_playing() then
        local level = gGlobalSyncTable.sh5_chaos_level
        local act = gGlobalSyncTable.sh5_chaos_act or 1
        if level ~= nil and level ~= 0 then warp_to_level(level, 1, act) end
        local_runtime.chaos_warp_at = -1
    end
end

local function local_boss_warp_update(m)
    if m.playerIndex ~= 0 then return end
    if not is_round_active() or not is_boss_mode() then
        local_runtime.boss_warp_at = -1
        return
    end

    local round = gGlobalSyncTable.sh5_round or 0
    if round ~= local_runtime.boss_round_seen then
        local_runtime.boss_round_seen = round
        local_runtime.boss_warp_at = get_global_timer() + NEXT_GOAL_DELAY
        -- A late joiner starts from the current attack sequence. Old attacks
        -- must not all replay while that player is entering the arena.
        local_runtime.boss_hazard_seq = gGlobalSyncTable.sh5_boss_attack_seq or 0
        local_runtime.modifier_ready_key = nil
        reset_local_modifier_state()
    end
    if local_runtime.death_warp_pending then
        -- Respawn only Mario. Reloading the whole level here can recreate or
        -- transfer ownership of Bowser while the other players are fighting.
        if gNetworkPlayers[0].currLevelNum == LEVEL_BOWSER_3 then
            m.pos.x, m.pos.y, m.pos.z = 0, 1307, 0
            m.vel.x, m.vel.y, m.vel.z = 0, 0, 0
            m.forwardVel = 0
            m.health = 0x880
            m.hurtCounter = 0
            m.healCounter = 0
            m.invincTimer = 90
            set_mario_action(m, ACT_FREEFALL, 0)
            if m.area ~= nil and m.area.camera ~= nil then soft_reset_camera(m.area.camera) end
            local_runtime.boss_warp_at = -1
            local_runtime.death_lock = false
            local_runtime.death_warp_pending = false
            reset_local_modifier_state()
            return
        end
        local_runtime.boss_warp_at = get_global_timer()
    end

    local level = BOSS_LEVELS[gGlobalSyncTable.sh5_boss_level_index or 0]
    if level ~= nil and local_runtime.boss_warp_at >= 0 and get_global_timer() >= local_runtime.boss_warp_at
        and not is_transition_playing() then
        warp_to_level(level, 1, 1)
        local_runtime.boss_warp_at = -1
        local_runtime.death_lock = false
        local_runtime.death_warp_pending = false
    end
end

local function spawn_violet_split_fire(bowser)
    if bowser == nil then return end
    local function spawn_flame(model, yaw, scale, speed)
        spawn_non_sync_object(id_bhvFlameMovingForwardGrowing, model,
            bowser.oPosX, bowser.oPosY + 180, bowser.oPosZ, function(flame)
                flame.oMoveAngleYaw = yaw
                flame.oFaceAngleYaw = yaw
                flame.oForwardVel = speed
                flame.oVelY = 8
                flame.oDamageOrCoinValue = 4
                obj_scale(flame, scale)
            end)
    end

    -- Red and blue overlap for the violet-looking core. Three branches keep
    -- the attack readable without flooding every client with short-lived
    -- objects.
    spawn_flame(E_MODEL_RED_FLAME, 0, 2.2, 0)
    spawn_flame(E_MODEL_BLUE_FLAME, 0, 1.9, 0)
    for branch = 0, 2 do
        local base = branch * 0x5555
        spawn_flame(E_MODEL_BLUE_FLAME, base, 1.15, 34)
    end
end

local function spawn_boss_flame(bowser, model, yaw, scale, speed)
    if bowser == nil then return end
    spawn_non_sync_object(id_bhvFlameMovingForwardGrowing, model,
        bowser.oPosX, bowser.oPosY + 160, bowser.oPosZ, function(flame)
            flame.oMoveAngleYaw = yaw
            flame.oFaceAngleYaw = yaw
            flame.oForwardVel = speed
            flame.oVelY = 5
            flame.oDamageOrCoinValue = 4
            obj_scale(flame, scale)
        end)
end

local function trigger_boss_wave(m, bowser, stun_frames)
    if bowser == nil then return end
    spawn_non_sync_object(id_bhvBowserShockWave, E_MODEL_BOWSER_WAVE,
        bowser.oPosX, bowser.oFloorHeight, bowser.oPosZ, nil)
    local distance = m.marioObj ~= nil and dist_between_objects(bowser, m.marioObj) or nil
    if distance ~= nil and distance < 4800 and is_local_player_on_floor(m) then
        local_runtime.boss_stun_frames = math.max(local_runtime.boss_stun_frames, stun_frames)
    end
end

local function resolve_meteor_rain(m, pending)
    for meteor = 0, 3 do
        local angle = pending.seed + meteor * (math.pi * 2 / 4)
        local x = pending.x + math.sin(angle) * 1250
        local z = pending.z + math.cos(angle) * 1250
        spawn_non_sync_object(id_bhvExplosion, E_MODEL_EXPLOSION, x, pending.y, z, nil)
        local dx, dz = m.pos.x - x, m.pos.z - z
        if dx * dx + dz * dz < 580 * 580 then m.health = 0 end
    end
end

local function execute_boss_attack(m, bowser, attack, attack_seq)
    if attack == 2 then
        trigger_boss_wave(m, bowser, 30)
    elseif attack == 3 then
        spawn_violet_split_fire(bowser)
    elseif attack == 5 then
        table.insert(local_runtime.pending_meteors, {
            at = get_global_timer() + 45,
            x = bowser.oPosX,
            y = bowser.oFloorHeight,
            z = bowser.oPosZ,
            seed = (attack_seq * 1.71) % (math.pi * 2),
        })
    elseif attack == 6 then
        for flame = 0, 7 do
            spawn_boss_flame(bowser, E_MODEL_BLUE_FLAME, flame * 0x2000, 0.9, 38)
        end
    elseif attack == 7 then
        -- The five real bombs in the final arena remain the only throwable
        -- bombs. This attack is a safe fire volley, not a spawned bomb.
        for flame = 0, 4 do
            spawn_boss_flame(bowser, E_MODEL_RED_FLAME, flame * 0x3333, 1.05, 45)
        end
    elseif attack == 8 then
        local angle = attack_seq * 1.37
        m.vel.x = m.vel.x + math.sin(angle) * 55
        m.vel.z = m.vel.z + math.cos(angle) * 55
        local_runtime.boss_stun_frames = math.max(local_runtime.boss_stun_frames, 12)
    elseif attack == 9 then
        -- A distortion wave replaces the old physical teleport. Moving a
        -- held or network-owned Bowser could make his tail impossible to grab.
        trigger_boss_wave(m, bowser, 16)
    elseif attack == 10 then
        trigger_boss_wave(m, bowser, 24)
        table.insert(local_runtime.pending_double_waves, get_global_timer() + 24)
    elseif attack == 11 and m.marioObj ~= nil then
        local yaw = atan2s(m.pos.x - bowser.oPosX, m.pos.z - bowser.oPosZ)
        spawn_boss_flame(bowser, E_MODEL_RED_FLAME, yaw, 1.25, 50)
        spawn_boss_flame(bowser, E_MODEL_BLUE_FLAME, yaw + 0x0800, 0.8, 44)
        spawn_boss_flame(bowser, E_MODEL_BLUE_FLAME, yaw - 0x0800, 0.8, 44)
    end
end

local function apply_boss_hazards(m)
    if m.playerIndex ~= 0 or not is_round_active() or not is_boss_mode() then return end
    local level = BOSS_LEVELS[gGlobalSyncTable.sh5_boss_level_index or 0]
    if level == nil or gNetworkPlayers[0].currLevelNum ~= level then return end

    if boss_has_modifier(1) then
        if m.hurtCounter > 0 and local_runtime.boss_damage_lock == 0 then
            local_runtime.boss_damage_lock = 1
            m.health = 0
        elseif m.hurtCounter == 0 then
            local_runtime.boss_damage_lock = 0
        end
    end

    if local_runtime.boss_stun_frames > 0 then
        local_runtime.boss_stun_frames = local_runtime.boss_stun_frames - 1
        if not config_open then
            m.controller.buttonDown = 0
            m.controller.buttonPressed = 0
            m.controller.stickX = 0
            m.controller.stickY = 0
            m.controller.rawStickX = 0
            m.controller.rawStickY = 0
            m.intendedMag = 0
            m.forwardVel = 0
        end
    end

    local bowser = obj_get_first_with_behavior_id(id_bhvBowser)
    -- A brief ownership transfer can temporarily remove Bowser locally. Keep
    -- queued attacks intact until the object returns instead of silently
    -- consuming them.
    if bowser == nil then return end
    -- During Bowser's intro, consume the current sequence without executing
    -- it. This also protects players who joined after an attack was sent.
    if bowser.oAction == 5 or bowser.oAction == 6 or bowser.oAction == 20 then
        local_runtime.boss_hazard_seq = gGlobalSyncTable.sh5_boss_attack_seq or 0
        local_runtime.pending_double_waves = {}
        local_runtime.pending_meteors = {}
        return
    end
    for index = #local_runtime.pending_double_waves, 1, -1 do
        if get_global_timer() >= local_runtime.pending_double_waves[index] then
            table.remove(local_runtime.pending_double_waves, index)
            trigger_boss_wave(m, bowser, 24)
        end
    end
    for index = #local_runtime.pending_meteors, 1, -1 do
        local meteor = local_runtime.pending_meteors[index]
        if get_global_timer() >= meteor.at then
            table.remove(local_runtime.pending_meteors, index)
            resolve_meteor_rain(m, meteor)
        end
    end

    local attack_seq = gGlobalSyncTable.sh5_boss_attack_seq or 0
    if attack_seq == local_runtime.boss_hazard_seq then return end
    -- Global sync updates can coalesce during lag. Replay every attack still
    -- present in the ring instead of applying only the newest sequence.
    local first_seq = math.max(local_runtime.boss_hazard_seq + 1, attack_seq - BOSS_ATTACK_QUEUE_SIZE + 1)
    for sequence = first_seq, attack_seq do
        local queue_slot = ((sequence - 1) % BOSS_ATTACK_QUEUE_SIZE) + 1
        local attack = gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(queue_slot)] or 0
        if sequence == attack_seq and attack == 0 then
            attack = gGlobalSyncTable.sh5_boss_attack_kind or 0
        end
        execute_boss_attack(m, bowser, attack, sequence)
    end
    local_runtime.boss_hazard_seq = attack_seq
end

-- The host writes a per-player sequence number when the round ends.  It stays
-- in that player's sync table until the next ending, which makes this robust
-- against a delayed result packet or a warp that was busy on the first frame.
local function force_return_to_lobby(m)
    if m.playerIndex ~= 0 then return end

    local return_seq = math.max(gPlayerSyncTable[0].sh5_return_seq or 0,
        gGlobalSyncTable.sh5_return_seq or 0)
    -- A return order from an older round may still be present when a delayed
    -- player joins the next one. Consume it while play is active.
    if is_round_active() then
        local_seen_return_seq = return_seq
        local_return_warp_pending = false
        return
    end
    if return_seq ~= local_seen_return_seq then
        local_seen_return_seq = return_seq
        local_return_warp_pending = return_seq ~= 0
        local_return_warp_retry_at = 0
        -- Every client owns its own save file. Clear its pending StarHunt
        -- stars as soon as the end-of-round packet arrives, before a warp or
        -- an immediate F12 exit can let vanilla save them again.
        flush_starhunt_save_removals(true, false)
    end

    if not local_return_warp_pending then return end
    if gNetworkPlayers[0].currLevelNum == LEVEL_CASTLE_GROUNDS then
        local_return_warp_pending = false
        return
    end
    if get_global_timer() >= local_return_warp_retry_at and not is_transition_playing() then
        warp_to_level(LEVEL_CASTLE_GROUNDS, 1, 0)
        local_return_warp_retry_at = get_global_timer() + FRAMES_PER_SECOND
    end
end

-- Remove the camera Lakitu itself on the castle grounds.  This prevents the
-- scene instead of merely skipping it after the camera has already appeared.
local function remove_castle_lakitu(obj)
    local level = gNetworkPlayers[0].currLevelNum
    if level ~= LEVEL_CASTLE_GROUNDS then return end

    -- Lua exposes the stable behavior ID, not the C behavior-script symbols.
    -- Camera Lakitu covers both the opening cameraman and the intro sequence.
    if obj_has_behavior_id(obj, id_bhvCameraLakitu) ~= 0 then
        obj_mark_for_deletion(obj)
    end
end

-- HOOK_ON_OBJECT_LOAD does not run retroactively when StarHunt is enabled
-- after the grounds have already loaded. Scan briefly and repeatedly so the
-- pre-existing camera Lakitu is removed as well.
local function remove_existing_castle_lakitu()
    if gNetworkPlayers[0].currLevelNum ~= LEVEL_CASTLE_GROUNDS then return end
    if get_global_timer() < local_lakitu_scan_at then return end
    local_lakitu_scan_at = get_global_timer() + 15
    local object = obj_get_first_with_behavior_id(id_bhvCameraLakitu)
    if object ~= nil then obj_mark_for_deletion(object) end
end

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
    local goal = get_goal(goal_id)
    if goal == nil or object == nil then return false end
    local rejected_by_player = local_runtime.rejected_stars[object]
    local rejection = rejected_by_player ~= nil and rejected_by_player[m.playerIndex] or nil
    if rejection ~= nil and rejection.goal == goal_id and rejection.round == round_id then
        return false
    end
    if not goal_matches_star_object(goal, object) then
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
    if not goal_matches_player_area(goal, m.playerIndex) then return false end
    if m.playerIndex == 0 then return Team.all_coin_tolls_paid(m) end
    local first = Team.effective_modifier_for_goal(goal,
        goal.mods[gPlayerSyncTable[m.playerIndex].sh5_modifier or 0])
    local second = Team.effective_modifier_for_goal(goal,
        goal.mods[gPlayerSyncTable[m.playerIndex].sh5_modifier_2 or 0])
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

    local goal = get_local_goal()
    if goal ~= nil and goal_matches_player_area(goal, 0) and goal_matches_star_object(goal, object) then
        if not Team.all_coin_tolls_paid(m) then return end
        remove_starhunt_save_flag(goal)
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
    local goal = is_round_active() and not is_boss_mode() and get_local_goal() or nil
    local object = obj_get_first(OBJ_LIST_LEVEL)
    while object ~= nil do
        if has_interaction(object.oInteractType, INTERACT_STAR_OR_KEY) then
            local correct = goal ~= nil and goal_matches_player_area(goal, 0)
                and goal_matches_star_object(goal, object)
                and Team.all_coin_tolls_paid(gMarioStates[0])
            if goal ~= nil and not correct then
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

local function on_allow_pvp_attack(attacker, victim, _)
    local attacker_index = attacker.playerIndex
    local victim_index = victim.playerIndex
    if Team.is_chaos_mode()
        and ((gPlayerSyncTable[attacker_index].sh5_chaos_eliminated or 0) == 1
            or (gPlayerSyncTable[victim_index].sh5_chaos_eliminated or 0) == 1) then
        return false
    end
    if not players_can_share_world(attacker_index, victim_index) then return false end
    if Team.is_mode() then
        local attacker_team = gPlayerSyncTable[attacker_index].sh5_team or Team.NONE
        local victim_team = gPlayerSyncTable[victim_index].sh5_team or Team.NONE
        return attacker_team ~= Team.NONE and victim_team ~= Team.NONE
            and attacker_team ~= victim_team
    end
    return not is_boss_mode()
end

Team.local_index_from_global = function(global_index)
    if global_index == nil or type(network_local_index_from_global) ~= "function" then return nil end
    local index = network_local_index_from_global(global_index)
    if type(index) ~= "number" or index < 0 or index >= MAX_PLAYERS then return nil end
    if gNetworkPlayers[index] == nil or not gNetworkPlayers[index].connected then return nil end
    return index
end

-- Gun Mod bullets call their registered Mario hitbox directly, bypassing
-- HOOK_ALLOW_PVP_ATTACK. Wrap only that public hitbox entry so Gun Mod keeps
-- all of its normal damage, metal-cap and invincibility behaviour while
-- respecting the same Normal/Boss/TEAM PvP rules as direct attacks.
Team.install_gun_mod_compatibility = function()
    if local_runtime.gun_mod_compat_wrapper ~= nil then return true end
    local api = rawget(_G, "gunModApi")
    local hitboxes = rawget(_G, "gShootableHitboxes")
    local mario_behavior = rawget(_G, "id_bhvMario")
    if type(api) ~= "table" or type(api.obj_get_weapon_owner) ~= "function"
        or type(hitboxes) ~= "table" or mario_behavior == nil
        or type(hitboxes[mario_behavior]) ~= "function" then
        return false
    end

    local_runtime.gun_mod_compat_original = hitboxes[mario_behavior]
    local_runtime.gun_mod_compat_wrapper = function(target_object, bullet_object)
        if is_round_active() and target_object ~= nil and bullet_object ~= nil then
            local attacker_index = Team.local_index_from_global(api.obj_get_weapon_owner(bullet_object))
            local victim_index = Team.local_index_from_global(target_object.globalPlayerIndex)
            if attacker_index ~= nil and victim_index ~= nil
                and not on_allow_pvp_attack(
                    { playerIndex = attacker_index }, { playerIndex = victim_index }, nil) then
                return true
            end
        end
        return local_runtime.gun_mod_compat_original(target_object, bullet_object)
    end
    hitboxes[mario_behavior] = local_runtime.gun_mod_compat_wrapper
    return true
end

local function on_nametags_render(player_index, pos)
    local index = tonumber(player_index)
    if index ~= nil and index ~= 0 and is_round_active() and players_have_private_variant(0, index) then
        return { name = "", pos = pos }
    end
end

local function update_private_player_visibility()
    for i = 1, MAX_PLAYERS - 1 do
        local mario = gMarioStates[i]
        local object = mario ~= nil and mario.marioObj or nil
        local hide = gNetworkPlayers[i].connected and is_round_active()
            and players_have_private_variant(0, i)
        local tracked = local_runtime.hidden_players[i]
        if tracked ~= nil and tracked.object ~= object then
            local_runtime.hidden_players[i] = nil
            tracked = nil
        end
        if object ~= nil and hide then
            if tracked == nil then
                tracked = {
                    object = object,
                    was_invisible = (object.header.gfx.node.flags & GRAPH_RENDER_INVISIBLE) ~= 0,
                }
                local_runtime.hidden_players[i] = tracked
            end
            object.header.gfx.node.flags = object.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE
        elseif object ~= nil and tracked ~= nil then
            if not tracked.was_invisible then
                object.header.gfx.node.flags = object.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE
            end
            local_runtime.hidden_players[i] = nil
        elseif not gNetworkPlayers[i].connected then
            local_runtime.hidden_players[i] = nil
        end
    end
end

Team.colors = {
    [Team.RED] = { r = 225, g = 42, b = 48 },
    [Team.BLUE] = { r = 45, g = 104, b = 235 },
}

Team.palette_key = function(player, index)
    if player ~= nil and player.globalIndex ~= nil then
        return "g:" .. tostring(player.globalIndex)
    end
    return "slot:" .. tostring(index)
end

Team.palette_identity = function(player)
    return tostring(player.modelIndex or -1) .. "|"
        .. tostring(player.overrideModelIndex or -1) .. "|"
        .. tostring(player.overrideLocation or "")
end

Team.capture_palette = function(player, index, team_color)
    local key = Team.palette_key(player, index)
    local identity = Team.palette_identity(player)
    local snapshot = Team.palettes[key]
    if snapshot == nil or snapshot.identity ~= identity then
        snapshot = { identity = identity }
        for part = PANTS, EMBLEM do
            local color = network_player_get_override_palette_color(player, part)
            snapshot[part] = { r = color.r, g = color.g, b = color.b }
        end
        Team.palettes[key] = snapshot
    elseif team_color ~= nil then
        -- Character/palette mods can update colors without changing the model
        -- identity. Preserve only the parts they actually changed while TEAM
        -- was active; untouched team-colored parts keep their original value.
        for part = PANTS, EMBLEM do
            local color = network_player_get_override_palette_color(player, part)
            if color.r ~= team_color.r or color.g ~= team_color.g or color.b ~= team_color.b then
                snapshot[part] = { r = color.r, g = color.g, b = color.b }
            end
        end
    end
    return key
end

Team.restore_palettes = function()
    if not Team.paletteActive and next(Team.palettes) == nil then return end
    for i = 0, MAX_PLAYERS - 1 do
        local player = gNetworkPlayers[i]
        if player ~= nil then
            local snapshot = Team.palettes[Team.palette_key(player, i)]
            -- If Character Select changed the model after StarHunt's last
            -- refresh, its current palette already belongs to the new model.
            -- Never overwrite it with a snapshot captured from the old one.
            if snapshot ~= nil and snapshot.identity == Team.palette_identity(player) then
                for part = PANTS, EMBLEM do
                    network_player_set_override_palette_color(player, part, snapshot[part])
                end
            end
        end
    end
    Team.palettes = {}
    Team.paletteActive = false
    Team.paletteRefreshAt = 0
end

Team.update_palettes = function()
    if not is_round_active() or not Team.is_mode() then
        Team.restore_palettes()
        return
    end
    Team.paletteActive = true
    if get_global_timer() < Team.paletteRefreshAt then return end
    Team.paletteRefreshAt = get_global_timer() + 15
    for i = 0, MAX_PLAYERS - 1 do
        local player = gNetworkPlayers[i]
        local team = gPlayerSyncTable[i].sh5_team or Team.NONE
        local color = Team.colors[team]
        if player ~= nil and player.connected and color ~= nil then
            Team.capture_palette(player, i, color)
            for part = PANTS, EMBLEM do
                network_player_set_override_palette_color(player, part, color)
            end
        end
    end
end

local function keep_moat_lowered()
    if get_global_timer() < local_moat_refresh_at then return end
    if gNetworkPlayers[0].currLevelNum ~= LEVEL_CASTLE_GROUNDS then return end
    local_moat_refresh_at = get_global_timer() + FRAMES_PER_SECOND

    -- Every local game gets the visual height; the host also synchronizes it.
    set_water_level(0, CASTLE_LOWERED_MOAT, network_is_server())
    set_water_level(1, CASTLE_LOWERED_MOAT, network_is_server())
end

local function on_find_water_level(_, _, water_level)
    -- set_water_level() already updates the two real moat/lake regions.
    -- Returning a fixed height here would create water under every coordinate
    -- on the castle grounds, including places outside those water boxes.
    return water_level
end

local function on_pause_exit(_)
    if is_round_active() then
        djui_popup_create(translated("FINISH THE ROUND OR ASK THE HOST TO STOP IT.", "TERMINA LA RONDA O PIDE AL HOST QUE LA DETENGA."), 1)
        return false
    end
    return true
end

Team.manual_reroll_remaining = function()
    if not is_round_active() or (selected_mode() ~= Team.NORMAL and not Team.is_mode())
        or get_local_goal() == nil then
        return nil
    end
    return math.max(0, (gPlayerSyncTable[0].sh5_manual_reroll_ready_frame or 0)
        - get_global_timer())
end

Team.manual_reroll_label = function()
    local base = translated("ANOTHER LEVEL", "OTRO NIVEL")
    local remaining = Team.manual_reroll_remaining()
    if remaining == nil then
        return base .. " - " .. translated("NORMAL/TEAM ONLY", "SOLO NORMAL/TEAM")
    end
    if remaining <= 0 then
        return base .. " - " .. translated("READY", "LISTO")
    end
    local seconds = math.ceil(remaining / FRAMES_PER_SECOND)
    return base .. " - " .. string.format("%d:%02d",
        math.floor(seconds / 60), seconds % 60)
end

Team.request_manual_reroll = function(_)
    local remaining = Team.manual_reroll_remaining()
    if remaining == nil then
        djui_popup_create(translated(
            "ANOTHER LEVEL IS ONLY AVAILABLE IN NORMAL OR TEAM.",
            "OTRO NIVEL SOLO ESTA DISPONIBLE EN NORMAL O TEAM."), 2)
        return
    end
    if remaining > 0 then
        local seconds = math.ceil(remaining / FRAMES_PER_SECOND)
        djui_popup_create(translated("ANOTHER LEVEL AVAILABLE IN ",
            "OTRO NIVEL DISPONIBLE EN ")
                .. string.format("%d:%02d", math.floor(seconds / 60), seconds % 60), 2)
        return
    end
    local sync = gPlayerSyncTable[0]
    if (sync.sh5_manual_reroll_request or 0) ~= (sync.sh5_manual_reroll_ack or 0) then
        djui_popup_create(translated("A LEVEL CHANGE IS ALREADY PENDING.",
            "YA HAY UN CAMBIO DE NIVEL PENDIENTE."), 1)
        return
    end
    sync.sh5_manual_reroll_request = (sync.sh5_manual_reroll_request or 0) + 1
    djui_popup_create(translated("NEW LEVEL REQUESTED.",
        "NUEVO NIVEL SOLICITADO."), 1)
end

Team.update_manual_reroll_menu = function()
    if Team.rerollMenuIndex == nil or type(update_mod_menu_element_name) ~= "function" then
        return
    end
    local label = Team.manual_reroll_label()
    if label ~= Team.rerollMenuLabel then
        Team.rerollMenuLabel = label
        update_mod_menu_element_name(Team.rerollMenuIndex, label)
    end
end

local function config_option_count()
    return network_is_server() and 6 or 2
end

local function config_option_kind(index)
    if network_is_server() then
        if index == 1 then return "language" end
        if index == 2 then return "mode" end
        if index == 3 then return "difficulty" end
        if index == 4 then return "time" end
        if index == 5 then return "status" end
        -- Keep the primary round action at the bottom of the full menu.
        return is_round_active() and "stop" or "start"
    end
    if index == 1 then return "language" end
    return "status"
end

local function config_status_text()
    if not is_round_active() then return translated("WAITING", "ESPERANDO") end
    local remaining = math.max(0, (gGlobalSyncTable.sh5_end_frame or 0) - get_global_timer())
    local minutes = math.floor(remaining / (60 * FRAMES_PER_SECOND))
    local seconds = math.floor((remaining / FRAMES_PER_SECOND) % 60)
    return translated("ACTIVE ", "ACTIVA ") .. string.format("%d:%02d", minutes, seconds)
end

Team.close_widdlepets_menu = function()
    local pets = rawget(_G, "wpets")
    if type(pets) == "table" and type(pets.is_menu_opened) == "function"
        and type(pets.close_menu) == "function" and pets.is_menu_opened() then
        pets.close_menu()
    end
end

Team.set_config_menu_open = function(opening)
    opening = opening and true or false
    local changed = config_open ~= opening
    if opening and changed then Team.close_widdlepets_menu() end
    config_open = opening
    if opening and changed then
        config_selection = clamp(config_selection, 1, config_option_count())
        config_button_latch = 0
        config_stick_latched = false
        local_runtime.menu_freeze_x = nil
        local_runtime.menu_freeze_y = nil
        local_runtime.menu_freeze_z = nil
    end
end

local function open_config_menu()
    if config_open and not is_round_active() then
        Team.close_widdlepets_menu()
        return
    end
    Team.set_config_menu_open(not config_open)
end

Team.update_config_menu_lock = function()
    local active = is_round_active()
    if local_runtime.config_round_was_active == nil then
        Team.set_config_menu_open(not active)
    elseif not active then
        Team.set_config_menu_open(true)
    elseif not local_runtime.config_round_was_active then
        Team.set_config_menu_open(false)
    end
    local_runtime.config_round_was_active = active
end

Team.cycle_mode = function(delta)
    local next_mode = (selected_mode() + delta) % 4
    if next_mode < 0 then next_mode = next_mode + 4 end
    gGlobalSyncTable.sh5_mode = next_mode
    local minimum, maximum = configured_time_range(connected_player_count())
    gGlobalSyncTable.sh5_config_minutes =
        clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)
end

Team.cycle_difficulty = function(delta)
    local next_difficulty = (Team.selected_difficulty() + delta) % 4
    if next_difficulty < 0 then next_difficulty = next_difficulty + 4 end
    gGlobalSyncTable.sh5_difficulty = next_difficulty
end

Team.freeze_menu_mario = function(m)
    if m.playerIndex ~= 0 then return end
    if not config_open then
        local_runtime.menu_freeze_x = nil
        local_runtime.menu_freeze_y = nil
        local_runtime.menu_freeze_z = nil
        return
    end
    if local_runtime.menu_freeze_x == nil then
        local_runtime.menu_freeze_x = m.pos.x
        local_runtime.menu_freeze_y = m.pos.y
        local_runtime.menu_freeze_z = m.pos.z
    end
    m.pos.x = local_runtime.menu_freeze_x
    m.pos.y = local_runtime.menu_freeze_y
    m.pos.z = local_runtime.menu_freeze_z
    m.vel.x, m.vel.y, m.vel.z = 0, 0, 0
    m.forwardVel = 0
    m.slideVelX = 0
    m.slideVelZ = 0
    m.intendedMag = 0
    m.controller.buttonPressed = 0
    m.controller.buttonDown = 0
    m.controller.stickX = 0
    m.controller.stickY = 0
    m.controller.rawStickX = 0
    m.controller.rawStickY = 0
    if m.marioObj ~= nil then
        m.marioObj.oPosX = m.pos.x
        m.marioObj.oPosY = m.pos.y
        m.marioObj.oPosZ = m.pos.z
    end
    if (m.action & ACT_FLAG_AIR) == 0 then set_mario_action(m, ACT_IDLE, 0) end
end

local function update_config_input(m)
    if m.playerIndex ~= 0 or not config_open then return end
    local held = m.controller.buttonDown
    local pressed = held & ~config_button_latch
    config_button_latch = held
    local count = config_option_count()
    local stick_x = m.controller.stickX
    local stick_y = m.controller.stickY

    if math.abs(stick_x) < 18 and math.abs(stick_y) < 18 then
        config_stick_latched = false
    end
    local stick_ready = not config_stick_latched
    local stick_up = stick_ready and stick_y > 24
    local stick_down = stick_ready and stick_y < -24
    local stick_left = stick_ready and stick_x < -24
    local stick_right = stick_ready and stick_x > 24
    if stick_up or stick_down or stick_left or stick_right then
        config_stick_latched = true
    end

    if (pressed & (B_BUTTON | START_BUTTON)) ~= 0 then
        if is_round_active() then Team.set_config_menu_open(false) end
    elseif (pressed & U_JPAD) ~= 0 or stick_up then
        config_selection = config_selection - 1
        if config_selection < 1 then config_selection = count end
    elseif (pressed & D_JPAD) ~= 0 or stick_down then
        config_selection = config_selection + 1
        if config_selection > count then config_selection = 1 end
    elseif (pressed & (L_JPAD | R_JPAD)) ~= 0 or stick_left or stick_right then
        local option = config_option_kind(config_selection)
        if option == "language" then
            local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
            Team.language = (Team.language + delta) % #Team.language_codes
            if Team.language < 0 then Team.language = Team.language + #Team.language_codes end
            mod_storage_save("starhunt_v11_language", tostring(Team.language))
        elseif option == "mode" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("MODE IS LOCKED DURING A ROUND", "EL MODO ESTA BLOQUEADO DURANTE LA RONDA"), 1)
            else
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                Team.cycle_mode(delta)
            end
        elseif option == "difficulty" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("DIFFICULTY IS LOCKED DURING A ROUND",
                    "LA DIFICULTAD ESTA BLOQUEADA DURANTE LA RONDA"), 1)
            else
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                Team.cycle_difficulty(delta)
            end
        elseif option == "time" and network_is_server() then
            if is_round_active() then
                djui_popup_create(translated("TIME IS LOCKED DURING A ROUND", "EL TIEMPO ESTA BLOQUEADO DURANTE LA RONDA"), 1)
            else
                local minimum, maximum = configured_time_range(connected_player_count())
                local delta = ((pressed & L_JPAD) ~= 0 or stick_left) and -1 or 1
                local current = clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)
                gGlobalSyncTable.sh5_config_minutes = clamp(current + delta, minimum, maximum)
            end
        end
    elseif (pressed & A_BUTTON) ~= 0 then
        local option = config_option_kind(config_selection)
        if option == "start" then
            local minimum, maximum = configured_time_range(connected_player_count())
            if host_start_round(clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)) then
                Team.set_config_menu_open(false)
            end
        elseif option == "stop" then
            host_end_round("stopped by host")
            Team.set_config_menu_open(true)
        elseif option == "language" then
            Team.language = (Team.language + 1) % #Team.language_codes
            mod_storage_save("starhunt_v11_language", tostring(Team.language))
        elseif option == "mode" and network_is_server() then
            if not is_round_active() then
                Team.cycle_mode(1)
            end
        elseif option == "difficulty" and network_is_server() then
            if not is_round_active() then Team.cycle_difficulty(1) end
        elseif option == "status" then
            djui_popup_create(config_status_text(), 1)
        end
    end

    -- The menu owns all movement. The analog stick navigates it and is then
    -- neutralized before Mario's movement logic can see it.
    m.controller.buttonPressed = 0
    m.controller.buttonDown = 0
    m.controller.stickX = 0
    m.controller.stickY = 0
    m.controller.rawStickX = 0
    m.controller.rawStickY = 0
    m.intendedMag = 0
    m.forwardVel = 0
    m.slideVelX = 0
    m.slideVelZ = 0
    m.vel.x = 0
    m.vel.y = 0
    m.vel.z = 0
    if (m.action & ACT_FLAG_AIR) == 0 then set_mario_action(m, ACT_IDLE, 0) end
    if config_open then Team.freeze_menu_mario(m) end
end

local function on_death(m)
    grant_infinite_lives(m)
    if m.playerIndex ~= 0 or not is_round_active() then return true end
    -- Restore health immediately so the cancelled death cannot trigger again
    -- while the replacement goal is arriving from the host.
    m.health = 0x880
    m.hurtCounter = 0
    m.healCounter = 0
    m.invincTimer = 90
    -- Returning false cancels SM64's flying/death animation entirely.
    if is_boss_mode() then
        if not local_runtime.death_lock then
            local_runtime.death_lock = true
            local_runtime.death_warp_pending = true
            local_runtime.boss_warp_at = get_global_timer()
            djui_popup_create(translated("BACK TO THE BATTLE!", "DE VUELTA A LA BATALLA!"), 1)
        end
        return false
    end
    if Team.is_chaos_mode() then
        if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 0 then
            gPlayerSyncTable[0].sh5_chaos_eliminated = 1
            local_runtime.chaos_spectator_warped = false
            djui_popup_create(translated("ELIMINATED! SPECTATING...",
                "ELIMINADO! OBSERVANDO..."), 2)
        end
        return false
    end
    if local_runtime.done_lock or local_runtime.death_lock or get_local_goal() == nil then return false end
    local_runtime.death_lock = true
    local_runtime.death_warp_pending = true
    gPlayerSyncTable[0].sh5_forfeit = (gPlayerSyncTable[0].sh5_forfeit or 0) + 1
    djui_popup_create(translated("NEW GOAL INCOMING...", "NUEVO RETO..."), 1)
    return false
end

-- Cancel death actions before vanilla can show even one frame of the flying,
-- drowning or collapse animation. HOOK_ON_DEATH remains as a fallback for
-- void/death-plane deaths that do not pass through one of these actions.
local STARHUNT_DEATH_ACTIONS = {
    [ACT_DROWNING] = true,
    [ACT_WATER_DEATH] = true,
    [ACT_STANDING_DEATH] = true,
    [ACT_QUICKSAND_DEATH] = true,
    [ACT_ELECTROCUTION] = true,
    [ACT_SUFFOCATION] = true,
    [ACT_DEATH_ON_STOMACH] = true,
    [ACT_DEATH_ON_BACK] = true,
    [ACT_EATEN_BY_BUBBA] = true,
}

local function on_before_death_action(m, incoming_action, _)
    if m.playerIndex ~= 0 or not is_round_active()
        or not STARHUNT_DEATH_ACTIONS[incoming_action] then
        return
    end
    on_death(m)
    return 1
end

-- The vanilla Bowser 3 textbox blocks Mario while StarHunt's shared timer is
-- already running. Cancelling this dialog also lets the native camera leave
-- its looping dialog state immediately.
local function on_dialog(dialog_id)
    if not is_round_active() or not is_boss_mode() then return true end
    if gNetworkPlayers[0].currLevelNum ~= LEVEL_BOWSER_3 then return true end
    local intro_dialog = DIALOG_093
    if gBehaviorValues ~= nil and gBehaviorValues.dialogs ~= nil
        and gBehaviorValues.dialogs.Bowser3Dialog ~= nil then
        intro_dialog = gBehaviorValues.dialogs.Bowser3Dialog
    end
    if dialog_id == intro_dialog then return false end
    return true
end

local function format_remaining_time(frames)
    local minutes = math.floor(frames / (60 * FRAMES_PER_SECOND))
    local seconds = math.floor((frames / FRAMES_PER_SECOND) % 60)
    return string.format("%d:%02d", minutes, seconds)
end

local function measure_hud_text(text)
    local width = 0
    local start_at = 1
    while true do
        local colon_at = string.find(text, ":", start_at, true)
        local chunk = colon_at ~= nil and string.sub(text, start_at, colon_at - 1)
            or string.sub(text, start_at)
        width = width + djui_hud_measure_text(chunk)
        if colon_at == nil then break end
        width = width + 5
        start_at = colon_at + 1
    end
    return width
end

local function draw_hud_text(text, x, y, scale, r, g, b, alpha)
    alpha = alpha or 255
    local function draw_layer(offset_x, offset_y, red, green, blue, alpha)
        local cursor = x + offset_x
        local start_at = 1
        djui_hud_set_color(red, green, blue, alpha)
        while true do
            local colon_at = string.find(text, ":", start_at, true)
            local chunk = colon_at ~= nil and string.sub(text, start_at, colon_at - 1)
                or string.sub(text, start_at)
            if chunk ~= "" then djui_hud_print_text(chunk, cursor, y + offset_y, scale) end
            cursor = cursor + djui_hud_measure_text(chunk) * scale
            if colon_at == nil then break end
            -- FONT_HUD maps ':' to an X. Draw a compact colon from two dots.
            djui_hud_print_text(".", cursor + scale, y + offset_y - 4 * scale, scale * 0.64)
            djui_hud_print_text(".", cursor + scale, y + offset_y + 6 * scale, scale * 0.64)
            cursor = cursor + 5 * scale
            start_at = colon_at + 1
        end
    end
    draw_layer(1, 1, 0, 0, 0, math.floor(220 * alpha / 255))
    draw_layer(0, 0, r, g, b, alpha)
end

local function draw_centered_hud_text(text, y, scale, r, g, b)
    local x = (djui_hud_get_screen_width() - measure_hud_text(text) * scale) * 0.5
    draw_hud_text(text, x, y, scale, r, g, b)
end

Team.objective_text_max_width = function()
    local width = djui_hud_get_screen_width()
    local center = width * 0.5
    -- Keep the centered objective between the left score/health card and the
    -- right timer card. Widescreen gains space naturally without turning the
    -- objective into a screen-wide banner.
    local left_guard = (Team.is_mode() or is_boss_mode()) and 119 or 90
    local right_guard = width - 112
    return math.max(24, 2 * math.min(center - left_guard, right_guard - center))
end

Team.draw_scaled_centered_text = function(text, y, desired_scale, maximum_width, r, g, b)
    local text_width = measure_hud_text(text)
    local scale = desired_scale
    if text_width > 0 and text_width * scale > maximum_width then
        scale = maximum_width / text_width
    end
    draw_centered_hud_text(text, y, scale, r, g, b)
end

local function apply_counter_visibility()
    local flags = hud_get_value(HUD_DISPLAY_FLAGS)
    if is_round_active() then
        if not local_counter_round_active then
            local_hud_flags_before_round = flags
            local_counter_round_active = true
        end
        flags = flags & ~HUD_DISPLAY_FLAG_STAR_COUNT
        if HUD_DISPLAY_FLAG_COIN_COUNT ~= nil then
            flags = flags & ~HUD_DISPLAY_FLAG_COIN_COUNT
        end
        hud_set_value(HUD_DISPLAY_FLAGS, flags)
    elseif local_counter_round_active then
        local restore_mask = HUD_DISPLAY_FLAG_STAR_COUNT
        if HUD_DISPLAY_FLAG_COIN_COUNT ~= nil then
            restore_mask = restore_mask | HUD_DISPLAY_FLAG_COIN_COUNT
        end
        local saved = local_hud_flags_before_round or flags
        flags = (flags & ~restore_mask) | (saved & restore_mask)
        hud_set_value(HUD_DISPLAY_FLAGS, flags)
        local_counter_round_active = false
        local_hud_flags_before_round = nil
    end
end

-- Entering a course recreates the game's built-in HUD, including its own
-- star/coin counter.  Hide the native HUD itself while a round is active and
-- render only StarHunt's custom HUD below.
local native_hud_hidden = false
local function update_native_hud_visibility()
    if is_round_active() then
        if local_runtime.native_hud_was_hidden == nil then
            local_runtime.native_hud_was_hidden = hud_is_hidden()
        end
        hud_hide()
        native_hud_hidden = true
    elseif native_hud_hidden then
        if local_runtime.native_hud_was_hidden then hud_hide() else hud_show() end
        native_hud_hidden = false
        local_runtime.native_hud_was_hidden = nil
    end
end

-- DARKNESS PULSE belongs behind every HUD. Drawing it from the regular HUD
-- hook covered clocks, chat and weapon information from compatible mods.
Team.draw_darkness_behind = function()
    if not is_round_active()
        or not Team.darkness_active(Team.local_modifier_of_kind("darkness_pulse")) then return false end
    local frame = get_global_timer()
    if local_runtime.darkness_draw_frame == frame then return true end
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_color(0, 0, 0, 248)
    djui_hud_render_rect(0, 0, djui_hud_get_screen_width(), djui_hud_get_screen_height())
    local_runtime.darkness_draw_frame = frame
    return true
end

local function hide_native_hud_before_render()
    Team.draw_darkness_behind()
    if is_round_active() then hud_hide() end
end

local function draw_start_banner()
    if get_global_timer() > local_start_banner_until then return end
    local text, scale = translated("START!", "EMPIEZA!"), 2.4
    local y = math.floor(djui_hud_get_screen_height() * 0.62)
    local x = (djui_hud_get_screen_width() - djui_hud_measure_text(text) * scale) * 0.5
    djui_hud_set_color(0, 0, 0, 230)
    djui_hud_print_text(text, x + 3, y + 3, scale)
    djui_hud_set_color(214, 42, 31, 255)
    djui_hud_print_text(text, x - 1, y - 1, scale)
    djui_hud_set_color(255, 222, 60, 255)
    djui_hud_print_text(text, x, y, scale)
end

local function draw_config_menu()
    if not config_open then return end
    local width = djui_hud_get_screen_width()
    local height = djui_hud_get_screen_height()
    local box_w, box_h = 270, network_is_server() and 192 or 108
    local x = (width - box_w) * 0.5
    local y = (height - box_h) * 0.5
    local minimum, maximum = configured_time_range(connected_player_count())

    djui_hud_set_color(0, 0, 0, 180)
    djui_hud_render_rect(0, 0, width, height)
    djui_hud_set_color(16, 36, 92, 245)
    djui_hud_render_rect(x, y, box_w, box_h)
    djui_hud_set_color(255, 215, 73, 255)
    djui_hud_render_rect(x, y, box_w, 3)

    draw_centered_hud_text("STARHUNT", y + 10, 0.82, 255, 215, 73)
    local language_value = Team.language_names[Team.language + 1] or "ENGLISH"
    local line_y = y + 34

    for index = 1, config_option_count() do
        local option = config_option_kind(index)
        local text
        if option == "start" then
            text = translated("START ROUND", "INICIAR RONDA")
        elseif option == "stop" then
            text = translated("STOP ROUND", "DETENER RONDA")
        elseif option == "language" then
            text = translated("LANGUAGE", "IDIOMA") .. " - " .. language_value
        elseif option == "mode" then
            local mode_value
            if selected_mode() == Team.BOSS then
                mode_value = translated("BOSS", "JEFE")
            elseif selected_mode() == Team.MODE then
                mode_value = translated("TEAM", "EQUIPOS")
            elseif selected_mode() == Team.CHAOS then
                mode_value = translated("CHAOS", "CAOS")
            else
                mode_value = "NORMAL"
            end
            if (selected_mode() == Team.MODE or selected_mode() == Team.CHAOS)
                and connected_player_count() < 2 then
                mode_value = mode_value .. " - " .. translated("NEEDS 2 PLAYERS", "NECESITA 2 JUGADORES")
            end
            text = translated("GAME MODE", "MODO DE JUEGO") .. " - " .. mode_value
            if is_round_active() then text = text .. " " .. translated("(LOCKED)", "(BLOQUEADO)") end
        elseif option == "difficulty" then
            local names = {
                translated("EASY", "FACIL"), translated("NORMAL", "NORMAL"),
                translated("HARD", "DIFICIL"), translated("NIGHTMARE", "PESADILLA"),
            }
            local difficulty_value = names[Team.selected_difficulty() + 1]
            if is_round_active() then difficulty_value = difficulty_value .. " " .. translated("(LOCKED)", "(BLOQUEADO)") end
            text = translated("DIFFICULTY", "DIFICULTAD") .. " - " .. difficulty_value
        elseif option == "time" then
            local minutes = clamp(gGlobalSyncTable.sh5_config_minutes or minimum, minimum, maximum)
            local time_value = tostring(minutes) .. " " .. translated("MIN", "MIN")
            if is_round_active() then time_value = translated("LOCKED", "BLOQUEADO") end
            text = translated("TIME", "TIEMPO") .. " - " .. time_value
        else
            text = translated("STATUS", "ESTADO") .. " - " .. config_status_text()
        end

        if config_selection == index then
            djui_hud_set_color(255, 255, 255, 45)
            djui_hud_render_rect(x + 10, line_y - 2, box_w - 20, 16)
        end
        local disabled = (selected_mode() == Team.MODE or selected_mode() == Team.CHAOS)
            and connected_player_count() < 2
            and (option == "mode" or option == "start")
        draw_hud_text((config_selection == index and "> " or "  ") .. text,
            x + 16, line_y, 0.62, 255, 255, 255, disabled and 105 or 255)
        line_y = line_y + 21
    end

    local controls
    if not is_round_active() then
        controls = Team.menu_lock_labels[Team.language + 1] or Team.menu_lock_labels[1]
    else
        controls = translated("UP/DOWN SELECT  A USE  LEFT/RIGHT CHANGE  B CLOSE",
            "ARRIBA/ABAJO ELEGIR  A USAR  IZQ/DER CAMBIAR  B CERRAR")
    end
    draw_centered_hud_text(controls, y + box_h - 16, 0.32, 160, 210, 255)
    if network_is_server() and not is_round_active() then
        draw_centered_hud_text(tostring(minimum) .. "-" .. tostring(maximum) .. " " .. translated("MINUTES", "MINUTOS"),
            y + box_h - 29, 0.38, 190, 190, 190)
    end
end

Team.draw_hud_panel = function(x, y, width, height, r, g, b)
    djui_hud_set_color(5, 11, 24, 205)
    djui_hud_render_rect(x, y, width, height)
    djui_hud_set_color(r, g, b, 235)
    djui_hud_render_rect(x, y, 3, height)
    djui_hud_set_color(255, 255, 255, 28)
    djui_hud_render_rect(x + 3, y, width - 3, 1)
end

Team.health_wedges = function(health)
    return clamp(math.floor(clamp(health or 0x880, 0, 0x880) / 0x100), 0, 8)
end

Team.health_color = function(wedges)
    if wedges >= 6 then return 74, 218, 128 end
    if wedges >= 3 then return 255, 190, 54 end
    return 255, 76, 82
end

local function draw_player_health_bar(y)
    local mario = gMarioStates[0]
    if mario == nil then return end
    local wedges = Team.health_wedges(mario.health)
    local r, g, b = Team.health_color(wedges)
    local x = 10
    y = y or 42
    Team.draw_hud_panel(x, y, 101, 19, r, g, b)
    draw_hud_text(translated("HP", "VIDA"), x + 7, y + 5, 0.38, r, g, b)

    local segment_x = x + 29
    for slot = 1, 8 do
        local sx = segment_x + (slot - 1) * 8
        djui_hud_set_color(33, 43, 61, 255)
        djui_hud_render_rect(sx, y + 5, 6, 10)
        if slot <= wedges then
            djui_hud_set_color(r, g, b, 255)
            djui_hud_render_rect(sx, y + 5, 6, 10)
            djui_hud_set_color(255, 255, 255, 70)
            djui_hud_render_rect(sx, y + 5, 6, 1)
        end
    end
end

Team.draw_round_status_panels = function(remaining, score)
    local width = djui_hud_get_screen_width()
    local health_y = 42

    if Team.is_mode() then
        local local_team = gPlayerSyncTable[0].sh5_team or Team.NONE
        Team.draw_hud_panel(10, 8, 101, 38,
            local_team == Team.BLUE and 64 or 232,
            local_team == Team.BLUE and 132 or 68,
            local_team == Team.BLUE and 255 or 72)
        draw_hud_text((local_team == Team.RED and "> " or "  ")
                .. "RED  x " .. tostring(gGlobalSyncTable.sh5_red_score or 0),
            17, 14, 0.48, 255, 78, 78)
        draw_hud_text((local_team == Team.BLUE and "> " or "  ")
                .. "BLUE x " .. tostring(gGlobalSyncTable.sh5_blue_score or 0),
            17, 28, 0.48, 92, 154, 255)
        health_y = 51
    elseif Team.is_chaos_mode() then
        Team.draw_hud_panel(10, 8, 101, 29, 196, 78, 255)
        draw_hud_text(translated("ALIVE ", "VIVOS ")
                .. tostring(gGlobalSyncTable.sh5_chaos_alive or 0),
            17, 15, 0.58, 235, 165, 255)
    elseif is_boss_mode() then
        local boss_health = clamp(gGlobalSyncTable.sh5_boss_health or Team.boss_max_health(), 0, Team.boss_max_health())
        Team.draw_hud_panel(10, 8, 101, 29, 236, 66, 82)
        draw_hud_text("BOWSER", 17, 13, 0.42, 255, 112, 94)
        for slot = 1, Team.boss_max_health() do
            local sx = 61 + (slot - 1) * 9
            djui_hud_set_color(48, 38, 49, 255)
            djui_hud_render_rect(sx, 14, 7, 12)
            if slot <= boss_health then
                djui_hud_set_color(238, 67, 82, 255)
                djui_hud_render_rect(sx, 14, 7, 12)
                djui_hud_set_color(255, 220, 190, 80)
                djui_hud_render_rect(sx, 14, 7, 1)
            end
        end
    else
        Team.draw_hud_panel(10, 8, 72, 29, 255, 210, 72)
        if gTextures.star ~= nil then
            djui_hud_set_color(255, 255, 255, 255)
            djui_hud_render_texture(gTextures.star, 18, 14, 0.72, 0.72)
        end
        draw_hud_text("x " .. tostring(score), 38, 15, 0.64, 255, 255, 255)
    end

    local timer_x = width - 104
    Team.draw_hud_panel(timer_x, 8, 94, 43, 255, 210, 72)
    draw_hud_text(translated("TIME ", "TIEMPO ") .. format_remaining_time(remaining),
        timer_x + 8, 14, 0.48, 255, 220, 96)
    local coins = hud_get_value(HUD_DISPLAY_COINS) or 0
    if gTextures.coin ~= nil then
        djui_hud_set_color(255, 255, 255, 255)
        djui_hud_render_texture(gTextures.coin, timer_x + 9, 30, 0.65, 0.65)
    end
    draw_hud_text("x " .. tostring(coins), timer_x + 24, 32, 0.52, 255, 238, 156)
    draw_player_health_bar(health_y)
end

Team.draw_objective_panel = function(goal, modifier_data, modifier_data_2)
    local maximum_width = Team.objective_text_max_width()

    if is_boss_mode() then
        Team.draw_scaled_centered_text(
            translated("BOWSER MODIFIERS", "MODIFICADORES DE BOWSER"),
            3, 0.30, maximum_width, 200, 210, 230)
        local colors = {
            { 255, 145, 80 },
            { 220, 95, 255 },
            { 255, 220, 75 },
        }
        for slot = 1, #BOSS_MODIFIER_FIELDS do
            local color = colors[slot]
            Team.draw_scaled_centered_text(boss_modifier_text(slot),
                14 + (slot - 1) * 11,
                0.38, maximum_width, color[1], color[2], color[3])
        end
        if modifier_data ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data),
                48, 0.38, maximum_width, 104, 218, 255)
        end
        if modifier_data_2 ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data_2),
                59, 0.36, maximum_width, 255, 145, 80)
        end
        return
    end

    if Team.is_chaos_mode() then
        Team.draw_scaled_centered_text(
            translated("LAST PLAYER STANDING", "ULTIMO JUGADOR EN PIE"),
            3, 0.64, maximum_width, 255, 255, 255)
        if (gPlayerSyncTable[0].sh5_chaos_eliminated or 0) == 1 then
            Team.draw_scaled_centered_text(
                translated("ELIMINATED - SPECTATING", "ELIMINADO - OBSERVANDO"),
                17, 0.50, maximum_width, 255, 100, 110)
            return
        end
        if modifier_data ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data),
                17, 0.52, maximum_width, 255, 215, 73)
        end
        if modifier_data_2 ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data_2),
                29, 0.48, maximum_width, 255, 145, 80)
        end
        local reroll = math.max(0,
            (gGlobalSyncTable.sh5_chaos_next_reroll or 0) - get_global_timer())
        Team.draw_scaled_centered_text(
            translated("NEW MODIFIERS IN: ", "NUEVOS MODIFICADORES EN: ")
                .. tostring(math.ceil(reroll / FRAMES_PER_SECOND)),
            41, 0.40, maximum_width, 200, 210, 230)
        return
    end

    if goal ~= nil and modifier_data ~= nil then
        Team.draw_scaled_centered_text(goal_world_text(goal),
            3, 0.56, maximum_width, 104, 218, 255)
        Team.draw_scaled_centered_text(goal_title_text(goal),
            15, 0.70, maximum_width, 255, 255, 255)
        Team.draw_scaled_centered_text(modifier_text(modifier_data),
            28, 0.55, maximum_width, 255, 215, 73)
        local counter_y = 40
        if modifier_data_2 ~= nil then
            Team.draw_scaled_centered_text(modifier_text(modifier_data_2),
                39, 0.50, maximum_width, 255, 145, 80)
            counter_y = 50
        end
        local jump_data = modifier_data.kind == "jump_limit" and modifier_data
            or (modifier_data_2 ~= nil and modifier_data_2.kind == "jump_limit" and modifier_data_2 or nil)
        local toll_data = modifier_data.kind == "coin_toll" and modifier_data
            or (modifier_data_2 ~= nil and modifier_data_2.kind == "coin_toll" and modifier_data_2 or nil)
        if jump_data ~= nil then
            local left = gPlayerSyncTable[0].sh5_jump_count
            if left == nil then left = jump_data.value end
            Team.draw_scaled_centered_text(
                translated("JUMPS: ", "SALTOS: ") .. tostring(left),
                counter_y, 0.48, maximum_width, 255, 145, 80)
        elseif toll_data ~= nil then
            Team.draw_scaled_centered_text(
                translated("COINS: ", "MONEDAS: ")
                .. tostring(math.min(toll_data.value, Team.coin_count(gMarioStates[0])))
                .. "/" .. tostring(toll_data.value),
                counter_y, 0.48, maximum_width, 255, 145, 80)
        end
    else
        Team.draw_scaled_centered_text(
            translated("CHOOSING YOUR NEXT GOAL...", "ELIGIENDO TU PROXIMO RETO..."),
            15, 0.66, maximum_width, 255, 255, 255)
    end
end

-- Gun Mod normally renders in the same behind-HUD layer as the darkness
-- rectangle. Repeat its compact public-API HUD above the pulse so ammo and
-- crosshair remain usable. Outside a pulse StarHunt leaves Gun Mod untouched.
Team.draw_gun_mod_hud_compatibility = function()
    if local_runtime.darkness_draw_frame ~= get_global_timer() then return end
    local api = rawget(_G, "gunModApi")
    if type(api) ~= "table" or type(api.cur_weapon) ~= "function"
        or type(api.cur_dual_wield_weapon) ~= "function"
        or type(api.get_render_hud) ~= "function"
        or not api.get_render_hud() or not gGlobalSyncTable.gunModEnabled then
        return
    end
    local network = gNetworkPlayers[0]
    local act_selector = rawget(_G, "id_bhvActSelector")
    if network == nil or network.currActNum == 99
        or (act_selector ~= nil and obj_get_first_with_behavior_id(act_selector) ~= nil) then
        return
    end
    local weapon = api.cur_weapon()
    if weapon == nil then return end

    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_HUD)
    local width = djui_hud_get_screen_width()
    local height = djui_hud_get_screen_height()
    local first_person = rawget(_G, "get_first_person_enabled")
    local paused = rawget(_G, "is_game_paused")
    local crosshair = rawget(_G, "TEX_CROSSHAIR")
    if type(first_person) == "function" and first_person() and crosshair ~= nil
        and (type(paused) ~= "function" or not paused()) then
        djui_hud_set_color(255, 255, 0, 127)
        djui_hud_render_texture(crosshair, width * 0.5 - 4, height * 0.5 - 4, 0.5, 0.5)
    end

    local y = height - 35
    djui_hud_set_color(255, 255, 255, 255)
    if weapon.maxAmmo ~= nil and weapon.maxAmmo ~= 0 then
        djui_hud_print_text(tostring(weapon.ammo or 0) .. "/" .. tostring(weapon.maxAmmo),
            width - 128, y, 1)
    end
    local second = api.cur_dual_wield_weapon()
    if second ~= nil and second.maxAmmo ~= nil and second.maxAmmo ~= 0 then
        djui_hud_print_text(tostring(second.ammo or 0) .. "/" .. tostring(second.maxAmmo), 16, y, 1)
    end
end

local function draw_hud()
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_HUD)

    apply_counter_visibility()
    if not is_round_active() then
        draw_config_menu()
        return
    end
    local goal = get_local_goal()
    local modifiers = Team.get_local_modifiers()
    local modifier_data = modifiers[1]
    local remaining = math.max(0, (gGlobalSyncTable.sh5_end_frame or get_global_timer()) - get_global_timer())
    local score = gPlayerSyncTable[0].sh5_score or 0
    Team.draw_gun_mod_hud_compatibility()
    Team.draw_round_status_panels(remaining, score)
    Team.draw_objective_panel(goal, modifier_data, modifiers[2])
    draw_start_banner()
    draw_config_menu()
end

local function local_round_notifications()
    local round = gGlobalSyncTable.sh5_round or 0
    if local_seen_round == nil then
        local_seen_round = round
    elseif round ~= local_seen_round then
        local_seen_round = round
        local_start_banner_until = get_global_timer() + START_BANNER_FRAMES
    end

    local result = gGlobalSyncTable.sh5_result_seq or 0
    if local_seen_result == nil then
        local_seen_result = result
    elseif result ~= local_seen_result then
        local_seen_result = result
        local winner = gGlobalSyncTable.sh5_result_winner or "Nobody"
        local score = gGlobalSyncTable.sh5_result_score or 0
        local winner_message
        local result_mode = gGlobalSyncTable.sh5_result_mode or Team.NORMAL
        if result_mode == Team.BOSS then
            local reason = gGlobalSyncTable.sh5_result_reason or ""
            if reason == "boss defeated" then
                winner_message = translated("BOWSER DEFEATED! TEAM STARHUNT WINS!", "BOWSER DERROTADO! EL EQUIPO STARHUNT GANA!")
            elseif reason == "stopped by host" then
                winner_message = translated("BOSS ROUND STOPPED BY THE HOST.", "RONDA BOSS DETENIDA POR EL HOST.")
            else
                winner_message = translated("TIME UP! BOWSER WINS!", "TIEMPO AGOTADO! BOWSER GANA!")
            end
        elseif result_mode == Team.MODE then
            local red_score = gGlobalSyncTable.sh5_result_red_score or 0
            local blue_score = gGlobalSyncTable.sh5_result_blue_score or 0
            if winner == "RED TEAM" then
                winner_message = translated("RED TEAM WINS! ", "GANA EL EQUIPO ROJO! ")
            elseif winner == "BLUE TEAM" then
                winner_message = translated("BLUE TEAM WINS! ", "GANA EL EQUIPO AZUL! ")
            else
                winner_message = translated("TEAM TIE! ", "EMPATE DE EQUIPOS! ")
            end
            winner_message = winner_message .. "RED " .. tostring(red_score)
                .. " - BLUE " .. tostring(blue_score)
        elseif result_mode == Team.CHAOS then
            if (gGlobalSyncTable.sh5_result_reason or "") == "chaos last standing" then
                winner_message = translated("CHAOS WINNER: ", "GANADOR DE CAOS: ") .. winner
            else
                winner_message = translated("CHAOS ENDED WITHOUT A WINNER.",
                    "CAOS TERMINO SIN GANADOR.")
            end
        else
            winner_message = translated("STARHUNT WINNER: ", "GANADOR DE STARHUNT: ")
                .. winner .. " - " .. tostring(score) .. translated(" STAR(S)!", " ESTRELLA(S)!")
        end
        djui_chat_message_create(winner_message)
        djui_popup_create(winner_message, 2)
    end
end

local function on_joined_game()
    Team.update_config_menu_lock()
    if is_round_active() then
        if Team.is_chaos_mode() then
            djui_popup_create(translated("CHAOS IS ACTIVE: YOU WILL SPECTATE.",
                "CAOS ESTA ACTIVO: SERAS ESPECTADOR."), 1)
        else
            djui_popup_create(translated("STARHUNT IS ACTIVE: A GOAL WILL BE ASSIGNED.",
                "STARHUNT ESTA ACTIVO: RECIBIRAS UN RETO."), 1)
        end
    end
end

Team.register_mod_compatibility = function()
    Team.install_gun_mod_compatibility()

    if not local_runtime.dnc_compat_registered then
        local api = rawget(_G, "dayNightCycleApi")
        local hook_id = type(api) == "table" and type(api.constants) == "table"
            and api.constants.DNC_HOOK_ON_HUD_RENDER_BEHIND or nil
        if type(api) == "table" and type(api.dnc_hook_event) == "function" and hook_id ~= nil then
            -- Day/Night invokes this before drawing its clock. The frame guard
            -- keeps the regular fallback hook from drawing over that clock.
            api.dnc_hook_event(hook_id, Team.draw_darkness_behind)
            local_runtime.dnc_compat_registered = true
        end
    end

    if not local_runtime.widdlepets_compat_registered then
        local pets = rawget(_G, "wpets")
        if type(pets) == "table" and type(pets.hook_allow_menu) == "function" then
            pets.hook_allow_menu(function() return not config_open end)
            local_runtime.widdlepets_compat_registered = true
        end
    end
end

local function show_help()
    djui_chat_message_create("/starhunt - " .. translated("open the StarHunt menu", "abre el menu de StarHunt"))
    djui_chat_message_create("/starhunt updates - "
        .. translated("show what StarHunt is and what changed", "muestra de que trata StarHunt y que cambio"))
end

Team.show_updates = function()
    djui_chat_message_create("\\#FFE05A\\STAR\\#58D6FF\\HUNT \\#FFFFFF\\v1.1")
    djui_chat_message_create(translated(
        "ABOUT: A multiplayer challenge mod with four game modes.",
        "DE QUE TRATA: Un mod multijugador de desafios con cuatro modos."))
    djui_chat_message_create(translated(
        "MODES: Normal star race, team competition, cooperative Boss and last-player-standing Chaos.",
        "MODOS: Carrera Normal, competencia por equipos, Boss cooperativo y Chaos de ultimo jugador vivo."))
    djui_chat_message_create(translated(
        "DIFFICULTY: Easy, Normal, Hard or Nightmare applies independently to every mode.",
        "DIFICULTAD: Facil, Normal, Dificil o Pesadilla se aplica independientemente a cada modo."))
    djui_chat_message_create(translated(
        "V1.1: Personal Chaos modifiers, Nightmare extras and an in-game Another Level button with a two-minute cooldown.",
        "V1.1: Modificadores personales en Chaos, extras en Pesadilla y boton Otro nivel dentro del juego con espera de dos minutos."))
end

local function starhunt_command(message)
    local text = string.lower(message or ""):match("^%s*(.-)%s*$")
    if text == "" then
        open_config_menu()
        return true
    end
    if text == "updates" or text == "update" or text == "actualizaciones"
        or text == "cambios" then
        Team.show_updates()
        return true
    end
    show_help()
    return true
end

local function run_static_modifier_checks()
    local valid = #GOALS == 93
    for index, goal in ipairs(GOALS) do
        if goal.power ~= nil and goal.power ~= "wing" and goal.power ~= "metal"
            and goal.power ~= "vanish" and goal.power ~= "metal_vanish" then
            print("[StarHunt v1.1] Invalid required power in slot " .. index .. ".")
            valid = false
        end
        if goal.act == 7 and (goal.level == LEVEL_BOB or goal.level == LEVEL_WF or goal.level == LEVEL_JRB
            or goal.level == LEVEL_CCM or goal.level == LEVEL_BBH or goal.level == LEVEL_HMC or goal.level == LEVEL_LLL
            or goal.level == LEVEL_SSL or goal.level == LEVEL_DDD or goal.level == LEVEL_SL
            or goal.level == LEVEL_WDW or goal.level == LEVEL_TTM or goal.level == LEVEL_THI
            or goal.level == LEVEL_TTC or goal.level == LEVEL_RR) then
            print("[StarHunt v1.1] 100-coin goal slipped into slot " .. index .. ".")
            valid = false
        end
        if goal.mods == nil or #goal.mods == 0 then
            print("[StarHunt v1.1] Goal " .. index .. " has no modifier choices.")
            valid = false
        else
            for _, modifier_data in ipairs(goal.mods) do
                if not MODIFIER_KINDS[modifier_data.kind] or modifier_data.kind == "auto_crouch" then
                    print("[StarHunt v1.1] Invalid modifier: " .. tostring(modifier_data.kind))
                    valid = false
                end
                if modifier_data.kind == "floor_doom" and (modifier_data.value < 4 or modifier_data.value > 9) then
                    print("[StarHunt v1.1] Invalid cursed-floor duration: " .. tostring(modifier_data.value))
                    valid = false
                end
            end
        end
    end
    local x1, z1 = capped_horizontal_velocity(80, 60, 20)
    local x2, z2 = capped_horizontal_velocity(x1, z1, 20)
    if math.abs(x1 - x2) > 0.001 or math.abs(z1 - z2) > 0.001 then
        print("[StarHunt v1.1] Water-cap safety test failed.")
        valid = false
    end
    local expected_audits = #GOALS * #NORMAL_MODIFIER_CATALOG
    if MODIFIER_AUDIT_COUNTS.checked ~= expected_audits
        or MODIFIER_AUDIT_COUNTS.approved + MODIFIER_AUDIT_COUNTS.rejected ~= expected_audits then
        print("[StarHunt v1.1] Modifier audit matrix is incomplete.")
        valid = false
    end
    for goal_id = 1, #GOALS do
        for _, template in ipairs(NORMAL_MODIFIER_CATALOG) do
            if MODIFIER_AUDIT[goal_id] == nil or MODIFIER_AUDIT[goal_id][template.kind] == nil then
                print("[StarHunt v1.1] Missing audit entry at goal " .. goal_id .. ": " .. template.kind)
                valid = false
            end
        end
    end
    local swapped = swap_button_bits(A_BUTTON, A_BUTTON, B_BUTTON)
    if swapped ~= B_BUTTON then
        print("[StarHunt v1.1] A/B swap safety test failed.")
        valid = false
    end
    local drift_x, drift_y = rotate_stick(32, 0, math.pi * 0.5)
    if math.abs(drift_x) > 0.01 or math.abs(drift_y - 32) > 0.01 then
        print("[StarHunt v1.1] Control-drift rotation test failed.")
        valid = false
    end
    if valid then
        print("[StarHunt v1.1] 93 goals, 32 modifiers, " .. MODIFIER_AUDIT_COUNTS.checked
            .. " audited pairs (" .. MODIFIER_AUDIT_COUNTS.approved .. " approved, "
            .. MODIFIER_AUDIT_COUNTS.rejected .. " rejected), and checks passed.")
    end
end

-- The engine never sets this flag. The standalone test harness uses named
-- references so adding or reordering hooks cannot silently test the wrong
-- function.
if rawget(_G, "STARHUNT_TEST_MODE") then
    STARHUNT_TEST_API = {
        goals = GOALS,
        translated = translated,
        language_codes = Team.language_codes,
        language_names = Team.language_names,
        ui_translations = Team.ui_translations,
        modifier_translations = Team.modifier_translations,
        boss_modifier_translations = Team.boss_modifier_translations,
        menu_lock_labels = Team.menu_lock_labels,
        normal_modifier_catalog = NORMAL_MODIFIER_CATALOG,
        boss_player_modifiers = BOSS_PLAYER_MODIFIERS,
        menu_input = update_config_input,
        freeze_menu_mario = Team.freeze_menu_mario,
        goal_warp = local_goal_warp_update,
        chaos_warp = Team.update_chaos_warp,
        boss_warp = local_boss_warp_update,
        return_to_lobby = force_return_to_lobby,
        modifier = Team.apply_local_modifier,
        post_moveset_limits = Team.apply_post_moveset_limits,
        boss_hazards = apply_boss_hazards,
        power = apply_goal_power,
        host_update = host_update_round,
        host_start = host_start_round,
        boss_health_owner = ensure_boss_health_owner,
        boss_bomb_supply = Team.host_update_boss_bomb_supply,
        boss_bomb_positions = Team.bossBombPositions,
        disconnected = remember_disconnected_player,
        connected = mark_connected_player_unenrolled,
        dialog = on_dialog,
        death = on_death,
        before_death_action = on_before_death_action,
        allow_interact = on_allow_interact,
        interact = on_interact,
        players_have_private_variant = players_have_private_variant,
        players_can_share_world = players_can_share_world,
        allow_pvp_attack = on_allow_pvp_attack,
        remove_castle_lakitu = remove_castle_lakitu,
        remove_existing_castle_lakitu = remove_existing_castle_lakitu,
        grant_infinite_lives = grant_infinite_lives,
        native_hud_visibility = update_native_hud_visibility,
        hide_native_hud_before_render = hide_native_hud_before_render,
        counter_visibility = apply_counter_visibility,
        water_level = on_find_water_level,
        time_range = configured_time_range,
        draw_player_health_bar = draw_player_health_bar,
        draw_config_menu = draw_config_menu,
        health_wedges = Team.health_wedges,
        health_color = Team.health_color,
        draw_round_status_panels = Team.draw_round_status_panels,
        draw_objective_panel = Team.draw_objective_panel,
        draw_hud = draw_hud,
        draw_hud_text = draw_hud_text,
        remove_save_flag = remove_starhunt_save_flag,
        flush_save_on_exit = flush_starhunt_save_on_exit,
        flush_save_on_warp = flush_starhunt_save_on_warp,
        flush_save_removals = flush_starhunt_save_removals,
        goal_already_collected = goal_already_collected,
        selected_mode = selected_mode,
        selected_difficulty = Team.selected_difficulty,
        effective_modifier = Team.effective_modifier,
        effective_modifier_for_goal = Team.effective_modifier_for_goal,
        boss_mode = Team.BOSS,
        team_mode = Team.MODE,
        chaos_mode = Team.CHAOS,
        easy = Team.EASY,
        medium = Team.MEDIUM,
        hard = Team.HARD,
        nightmare = Team.NIGHTMARE,
        team_red = Team.RED,
        team_blue = Team.BLUE,
        team_update_scores = Team.update_scores,
        team_pick_late = Team.pick_late,
        team_update_palettes = Team.update_palettes,
        team_restore_palettes = Team.restore_palettes,
        lifetime_sync = Team.update_lifetime_sync,
        darkness_active = Team.darkness_active,
        local_modifiers = Team.get_local_modifiers,
        chaos_pair_allowed = Team.chaos_pair_allowed,
        pick_second_modifier = Team.pick_second_modifier,
        draw_darkness_behind = Team.draw_darkness_behind,
        draw_gun_mod_hud_compatibility = Team.draw_gun_mod_hud_compatibility,
        register_mod_compatibility = Team.register_mod_compatibility,
        manual_reroll_request = Team.request_manual_reroll,
        manual_reroll_remaining = Team.manual_reroll_remaining,
        manual_reroll_label = Team.manual_reroll_label,
        update_manual_reroll_menu = Team.update_manual_reroll_menu,
        update_config_menu_lock = Team.update_config_menu_lock,
        manual_reroll_cooldown = Team.manualRerollCooldown,
        toggle_menu = open_config_menu,
        is_menu_open = function() return config_open end,
        set_language = function(value)
            Team.language = clamp(math.floor(value or 0), 0, #Team.language_codes - 1)
        end,
    }
end

-- The built-in HUD is rendered before HOOK_ON_HUD_RENDER on some clients.
-- Keep its star/coin flags disabled during the update, before it can draw.
hook_event(HOOK_UPDATE, update_native_hud_visibility)
hook_event(HOOK_UPDATE, apply_counter_visibility)
hook_event(HOOK_UPDATE, Team.update_lifetime_sync)
hook_event(HOOK_UPDATE, Team.update_palettes)
hook_event(HOOK_UPDATE, host_update_round)
hook_event(HOOK_UPDATE, Team.update_config_menu_lock)
hook_event(HOOK_UPDATE, Team.update_manual_reroll_menu)
hook_event(HOOK_UPDATE, ensure_boss_health_owner)
hook_event(HOOK_UPDATE, host_reset_scores_after_result)
hook_event(HOOK_UPDATE, keep_moat_lowered)
hook_event(HOOK_UPDATE, remove_existing_castle_lakitu)
hook_event(HOOK_UPDATE, local_round_notifications)
hook_event(HOOK_UPDATE, update_star_visibility)
hook_event(HOOK_UPDATE, update_private_player_visibility)
hook_event(HOOK_UPDATE, flush_starhunt_save_removals)
hook_event(HOOK_BEFORE_MARIO_UPDATE, local_goal_warp_update)
hook_event(HOOK_BEFORE_MARIO_UPDATE, Team.update_chaos_warp)
hook_event(HOOK_BEFORE_MARIO_UPDATE, local_boss_warp_update)
hook_event(HOOK_BEFORE_MARIO_UPDATE, force_return_to_lobby)
hook_event(HOOK_BEFORE_MARIO_UPDATE, Team.apply_local_modifier)
hook_event(HOOK_BEFORE_MARIO_UPDATE, apply_boss_hazards)
hook_event(HOOK_BEFORE_MARIO_UPDATE, apply_goal_power)
hook_event(HOOK_BEFORE_MARIO_UPDATE, grant_infinite_lives)
hook_event(HOOK_BEFORE_MARIO_UPDATE, update_config_input)
-- Reapply after character/moveset hooks as well, so custom characters cannot
-- accidentally remove a cap required by the current StarHunt goal.
hook_event(HOOK_MARIO_UPDATE, apply_goal_power)
hook_event(HOOK_MARIO_UPDATE, Team.apply_post_moveset_limits)
hook_event(HOOK_MARIO_UPDATE, Team.freeze_menu_mario)
hook_event(HOOK_ON_OBJECT_LOAD, remove_castle_lakitu)
hook_event(HOOK_ON_LEVEL_INIT, reset_hidden_object_tracking)
hook_event(HOOK_ON_WARP, flush_starhunt_save_on_warp)
hook_event(HOOK_ON_EXIT, flush_starhunt_save_on_exit)
hook_event(HOOK_ON_EXIT, Team.restore_palettes)
hook_event(HOOK_ON_FIND_WATER_LEVEL, on_find_water_level)
hook_event(HOOK_ALLOW_INTERACT, on_allow_interact)
hook_event(HOOK_ON_INTERACT, on_interact)
hook_event(HOOK_ALLOW_PVP_ATTACK, on_allow_pvp_attack)
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, on_before_boss_cutscene)
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, on_before_death_action)
hook_event(HOOK_ON_DIALOG, on_dialog)
hook_event(HOOK_ON_PAUSE_EXIT, on_pause_exit)
hook_event(HOOK_ON_DEATH, on_death)
hook_event(HOOK_ON_NAMETAGS_RENDER, on_nametags_render)
hook_event(HOOK_ON_PLAYER_DISCONNECTED, remember_disconnected_player)
hook_event(HOOK_ON_PLAYER_CONNECTED, mark_connected_player_unenrolled)
hook_event(HOOK_JOINED_GAME, on_joined_game)
hook_event(HOOK_ON_HUD_RENDER_BEHIND, hide_native_hud_before_render)
hook_event(HOOK_ON_HUD_RENDER, draw_hud)
if HOOK_ON_MODS_LOADED ~= nil then
    hook_event(HOOK_ON_MODS_LOADED, Team.register_mod_compatibility)
else
    Team.register_mod_compatibility()
end
hook_chat_command("starhunt", "Open menu; use /starhunt updates for changes", starhunt_command)
if type(hook_mod_menu_button) == "function" then
    Team.rerollMenuIndex = hook_mod_menu_button(
        translated("ANOTHER LEVEL", "OTRO NIVEL"), Team.request_manual_reroll)
end

if network_is_server() and gGlobalSyncTable.sh5_active == nil then
    gGlobalSyncTable.sh5_active = 0
    gGlobalSyncTable.sh5_round = 0
    gGlobalSyncTable.sh5_result_seq = 0
    gGlobalSyncTable.sh5_return_seq = 0
    gGlobalSyncTable.sh5_mode = Team.NORMAL
    gGlobalSyncTable.sh5_difficulty = Team.MEDIUM
    gGlobalSyncTable.sh5_chaos_next_reroll = 0
    gGlobalSyncTable.sh5_chaos_level = 0
    gGlobalSyncTable.sh5_chaos_act = 1
    gGlobalSyncTable.sh5_chaos_modifier_1 = 0
    gGlobalSyncTable.sh5_chaos_modifier_2 = 0
    gGlobalSyncTable.sh5_chaos_modifier_seq = 0
    gGlobalSyncTable.sh5_chaos_alive = 0
    gGlobalSyncTable.sh5_chaos_winner = ""
    gGlobalSyncTable.sh5_chaos_roster_locked = 0
    gGlobalSyncTable.sh5_boss_level_index = 0
    gGlobalSyncTable.sh5_boss_player_modifier = 0
    gGlobalSyncTable.sh5_boss_player_modifier_2 = 0
    gGlobalSyncTable.sh5_boss_modifier_1 = 0
    gGlobalSyncTable.sh5_boss_modifier_2 = 0
    gGlobalSyncTable.sh5_boss_modifier_3 = 0
    gGlobalSyncTable.sh5_boss_attack_seq = 0
    gGlobalSyncTable.sh5_boss_attack_kind = 0
    for slot = 1, BOSS_ATTACK_QUEUE_SIZE do
        gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)] = 0
    end
    gGlobalSyncTable.sh5_boss_health = 0
    gGlobalSyncTable.sh5_boss_max_health = BOSS_HEALTH
    gGlobalSyncTable.sh5_boss_original_bombs_seen = 0
    gGlobalSyncTable.sh5_boss_extra_bombs_spawned = 0
    gGlobalSyncTable.sh5_red_score = 0
    gGlobalSyncTable.sh5_blue_score = 0
    gGlobalSyncTable.sh5_result_red_score = 0
    gGlobalSyncTable.sh5_result_blue_score = 0
    gGlobalSyncTable.sh5_config_minutes = 8
end

Team.update_lifetime_sync()
run_static_modifier_checks()
