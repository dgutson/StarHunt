-- StarHunt v1.1 - what the Boss round is made of.
--
-- Three passes: the static data and the functions that read Bowser's health
-- pool out of it; the readers the rest of the mod uses to ask about a Boss
-- round -- its time range, which Boss modifiers are active, whether Bowser is
-- down to his last two wedges, and the lowest health any client has reported;
-- and now the attack queue and the hazards, which is everything a client does
-- with an attack once the host has sent it.
--
-- The round loop is NOT here and cannot be. It calls host_end_round,
-- host_prepare_player and remember_player_index, which are round's host half,
-- and round.lua already requires this module for the time range, the modifier
-- slots and the health report; importing it back would be a cycle. It lives in
-- round.lua instead.
--
-- The hazards were held back for a cycle of their own until R-002: they ask
-- is_local_player_on_floor before letting a shockwave stun the local player,
-- that predicate lived in modifiers.lua, and modifiers.lua requires this module
-- for BOSS_PLAYER_MODIFIERS. It moved into core.lua, which everything may
-- import, and the hazards followed.
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
local local_runtime = core.local_runtime
local modifier = core.modifier
local clamp = core.clamp
local is_round_active = core.is_round_active
local is_boss_mode = core.is_boss_mode
local is_local_player_on_floor = core.is_local_player_on_floor

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

local function boss_time_range_for_players(count)
    if count <= 1 then return 5, 10 end
    if count <= 3 then return 4, 9 end
    if count <= 8 then return 4, 8 end
    return 3, 7
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

-- Everything below is what a client does with an attack. The host only writes a
-- sequence number and a queue slot into gGlobalSyncTable; each player replays
-- the ring locally and spawns its own flames, waves and meteors, which is why
-- none of this is synchronized and all of it runs on gMarioStates[0] alone.

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
        if not local_runtime.config_open then
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

return {
    BOSS_HEALTH = BOSS_HEALTH,
    BOSS_LEVELS = BOSS_LEVELS,
    BOSS_PLAYER_MODIFIERS = BOSS_PLAYER_MODIFIERS,
    BOSS_MODIFIERS = BOSS_MODIFIERS,
    BOSS_MODIFIER_FIELDS = BOSS_MODIFIER_FIELDS,
    BOSS_ATTACK_QUEUE_SIZE = BOSS_ATTACK_QUEUE_SIZE,
    BOSS_ACTIVE_ATTACK_MODIFIERS = BOSS_ACTIVE_ATTACK_MODIFIERS,
    BOSS_ACTIVE_ATTACK_LOOKUP = BOSS_ACTIVE_ATTACK_LOOKUP,
    boss_time_range_for_players = boss_time_range_for_players,
    boss_has_modifier = boss_has_modifier,
    boss_is_desperate = boss_is_desperate,
    boss_modifier_text = boss_modifier_text,
    host_read_boss_health_report = host_read_boss_health_report,
    apply_boss_hazards = apply_boss_hazards,
}
