-- StarHunt v1.1 - what the Boss round is made of.
--
-- First pass: the static data, plus the two functions that read Bowser's
-- health pool out of it. The round loop, the attack queue and the hazards
-- themselves are still in main.lua and join this module once their own
-- dependencies are extracted.
--
-- Two details in here are deliberate and easy to undo by accident. Boss player
-- modifiers never include one that removes B, because every player has to stay
-- able to grab Bowser by the tail. And the attack queue is eight slots rather
-- than a single "latest attack" field, because a single field lost attacks
-- under lag -- BOSS_ACTIVE_ATTACK_MODIFIERS lists the ones that create an
-- attack of their own, so that a draw cannot consist entirely of modifiers
-- that only accelerate or amplify attacks that never come.

local core = require("core")
local Team = core.Team
local modifier = core.modifier

local BOSS_HEALTH = 5

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

Team.boss_health_for_difficulty = function()
    local values = { 3, BOSS_HEALTH, 7, 9 }
    return values[Team.selected_difficulty() + 1] or BOSS_HEALTH
end

Team.boss_max_health = function()
    return math.max(1, gGlobalSyncTable.sh5_boss_max_health or Team.boss_health_for_difficulty())
end

return {
    BOSS_HEALTH = BOSS_HEALTH,
    BOSS_LEVELS = BOSS_LEVELS,
    BOSS_PLAYER_MODIFIERS = BOSS_PLAYER_MODIFIERS,
    BOSS_MODIFIERS = BOSS_MODIFIERS,
    BOSS_MODIFIER_FIELDS = BOSS_MODIFIER_FIELDS,
    BOSS_ATTACK_QUEUE_SIZE = BOSS_ATTACK_QUEUE_SIZE,
    BOSS_ACTIVE_ATTACK_MODIFIERS = BOSS_ACTIVE_ATTACK_MODIFIERS,
    BOSS_ACTIVE_ATTACK_LOOKUP = BOSS_ACTIVE_ATTACK_LOOKUP,
}
