-- Bowser's attacks, as every client plays them.
--
-- The host decides nothing here beyond a sequence number and a queue slot. Each
-- player reads the ring out of gGlobalSyncTable and spawns its own flames,
-- waves and meteors locally, which is why all of this runs on gMarioStates[0]
-- and none of it is synchronized.
--
-- Extracting modules/boss.lua's third pass found the whole area untested:
-- apply_boss_hazards was published to STARHUNT_TEST_API and called by no test
-- at all, and three engine stubs kept it that way. dist_between_objects
-- answered 0 for every pair, so a shockwave stunned the player from any
-- distance; obj_scale discarded its arguments, so every flame was the same
-- size; and atan2s answered nil, so hunter fire did not merely do nothing but
-- crashed. All three now have real bodies in test/harness.lua.
--
-- Two rules the code states in its own comments and nothing enforced: attacks
-- must survive Bowser briefly leaving the level rather than being consumed, and
-- the bomb barrage must stay a fire volley, because the five real bombs in the
-- arena are the only throwable ones.

return function(t, harness)
    local s = t.suite("boss_hazards")

    --- An active Boss round in the final arena, with Bowser in front of the
    -- local player and the player stood on the ground.
    local function arena(opts)
        opts = opts or {}
        local api, ctl = harness.load()
        ctl.begin_round(api, api.boss_mode, api.medium, LEVEL_BOWSER_3)
        gGlobalSyncTable.sh5_boss_level_index = 1
        ctl.timer = 1000

        local bowser = { oPosX = 100, oPosY = 200, oPosZ = 300,
                         oFloorHeight = 150, oAction = 0 }
        if not opts.no_bowser then ctl.objects[id_bhvBowser] = bowser end

        local m = gMarioStates[0]
        m.playerIndex = 0
        m.health = 0x880
        m.hurtCounter = 0
        m.pos.x, m.pos.y, m.pos.z = 0, 0, 0
        m.vel.x, m.vel.y, m.vel.z = 0, 0, 0
        m.action = 0
        m.floor = {}
        m.floorHeight = 0
        m.intendedMag = 0
        m.forwardVel = 0
        m.marioObj = { oPosX = 0, oPosY = 0, oPosZ = 0 }
        m.controller.buttonDown = 0
        m.controller.buttonPressed = 0
        m.controller.stickX, m.controller.stickY = 0, 0
        m.controller.rawStickX, m.controller.rawStickY = 0, 0
        return api, ctl, m, bowser
    end

    --- Put attack `kind` in the ring as sequence `seq` and run one frame.
    local function send(api, m, kind, seq)
        local slot = ((seq - 1) % api.boss_attack_queue_size) + 1
        gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)] = kind
        gGlobalSyncTable.sh5_boss_attack_seq = seq
        api.boss_hazards(m)
    end

    --- Everything spawned this round with the given behavior, in order.
    local function spawned_of(ctl, behavior)
        local found = {}
        for _, object in ipairs(ctl.spawned) do
            if object.behavior == behavior then found[#found + 1] = object end
        end
        return found
    end

    -- the gates ---------------------------------------------------------------

    s.test("another player's Mario is never touched", function()
        -- The hazards run under HOOK_BEFORE_MARIO_UPDATE, which fires for every
        -- player in the lobby, not only the local one.
        local api, ctl, m = arena()
        m.playerIndex = 1
        send(api, m, 2, 1)
        t.eq(#ctl.spawned, 0, "an attack was played for a remote player's Mario")
    end)

    s.test("nothing is played outside an active round", function()
        local api, ctl, m = arena()
        gGlobalSyncTable.sh5_active = 0
        send(api, m, 2, 1)
        t.eq(#ctl.spawned, 0, "an attack was played with no round running")
    end)

    s.test("nothing is played outside Boss mode", function()
        local api, ctl, m = arena()
        gGlobalSyncTable.sh5_mode = api.normal_mode
        send(api, m, 2, 1)
        t.eq(#ctl.spawned, 0, "an attack was played during a star race")
    end)

    s.test("nothing is played away from Bowser's arena", function()
        local api, ctl, m = arena()
        gNetworkPlayers[0].currLevelNum = LEVEL_CASTLE_GROUNDS
        send(api, m, 2, 1)
        t.eq(#ctl.spawned, 0, "an attack reached a player outside the arena")
    end)

    s.test("a client not yet told which arena plays nothing", function()
        -- BOSS_LEVELS is 1-based, so the fallback the client reads when the
        -- field has never arrived has to be a number that indexes no arena.
        -- Falling back to 1 would run the hazards on a client that has been
        -- told nothing.
        local api, ctl, m = arena()
        gGlobalSyncTable.sh5_boss_level_index = nil
        send(api, m, 2, 1)
        t.eq(#ctl.spawned, 0, "an arena index that never arrived picked an arena")

        local api2, ctl2, m2 = arena()
        gGlobalSyncTable.sh5_boss_level_index = 0
        send(api2, m2, 2, 1)
        t.eq(#ctl2.spawned, 0, "arena index 0 was treated as the first arena")
    end)

    -- Instant Knockout ---------------------------------------------------------

    s.test("Instant Knockout kills on the frame the hit lands", function()
        local api, _, m = arena()
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        m.hurtCounter = 4
        api.boss_hazards(m)
        t.eq(m.health, 0, "a hit did not kill under Instant Knockout")
        t.eq(api.runtime.boss_damage_lock, 1, "the damage lock did not close")
    end)

    s.test("one hit kills once, not on every frame it is still counting down", function()
        local api, _, m = arena()
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        m.hurtCounter = 4
        api.boss_hazards(m)
        m.health = 0x880              -- as respawning would leave it
        api.boss_hazards(m)           -- the same hit is still counting down
        t.eq(m.health, 0x880, "the same hit killed a second time")
    end)

    s.test("the lock reopens once the hit has worn off", function()
        local api, _, m = arena()
        gGlobalSyncTable.sh5_boss_modifier_1 = 1
        m.hurtCounter = 4
        api.boss_hazards(m)
        m.hurtCounter = 0
        api.boss_hazards(m)
        t.eq(api.runtime.boss_damage_lock, 0, "the lock stayed shut after the hit ended")
        m.health = 0x880
        m.hurtCounter = 4
        api.boss_hazards(m)
        t.eq(m.health, 0, "the next hit did not kill")
    end)

    s.test("without Instant Knockout a hit is left to the game", function()
        local api, _, m = arena()
        m.hurtCounter = 4
        api.boss_hazards(m)
        t.eq(m.health, 0x880, "a hit killed with Instant Knockout not drawn")
        t.eq(api.runtime.boss_damage_lock, 0, "the lock closed with Instant Knockout not drawn")
    end)

    -- being stunned -------------------------------------------------------------

    s.test("a stunned player's controller is emptied while the stun runs down", function()
        local api, _, m = arena()
        api.runtime.boss_stun_frames = 3
        m.controller.buttonDown = A_BUTTON
        m.controller.buttonPressed = A_BUTTON
        m.controller.stickX, m.controller.stickY = 40, -40
        m.controller.rawStickX, m.controller.rawStickY = 40, -40
        m.intendedMag = 32
        m.forwardVel = 20
        api.boss_hazards(m)
        t.eq(api.runtime.boss_stun_frames, 2, "the stun did not count down")
        t.eq(m.controller.buttonDown, 0, "buttons were still held")
        t.eq(m.controller.buttonPressed, 0, "buttons were still pressed")
        t.eq(m.controller.stickX, 0, "the stick was still pushed")
        t.eq(m.controller.stickY, 0, "the stick was still pushed")
        t.eq(m.controller.rawStickX, 0, "the raw stick was still pushed")
        t.eq(m.controller.rawStickY, 0, "the raw stick was still pushed")
        t.eq(m.intendedMag, 0, "the player was still trying to move")
        t.eq(m.forwardVel, 0, "the player was still moving")
    end)

    s.test("the config menu keeps its input while the stun runs down under it", function()
        -- The menu freezes Mario itself and reads the same controller. Emptying
        -- it here would make the menu unusable for the length of the stun.
        local api, _, m = arena()
        api.runtime.boss_stun_frames = 3
        api.runtime.config_open = true
        m.controller.buttonDown = A_BUTTON
        m.controller.stickX = 40
        api.boss_hazards(m)
        t.eq(api.runtime.boss_stun_frames, 2, "the stun did not count down behind the menu")
        t.eq(m.controller.buttonDown, A_BUTTON, "the menu lost its buttons")
        t.eq(m.controller.stickX, 40, "the menu lost its stick")
        api.runtime.config_open = false
    end)

    s.test("an unstunned player keeps their input", function()
        local api, _, m = arena()
        api.runtime.boss_stun_frames = 0
        m.controller.buttonDown = A_BUTTON
        m.forwardVel = 20
        api.boss_hazards(m)
        t.eq(m.controller.buttonDown, A_BUTTON, "an unstunned player lost their buttons")
        t.eq(m.forwardVel, 20, "an unstunned player was stopped")
        t.eq(api.runtime.boss_stun_frames, 0, "the stun counter went negative")
    end)

    -- Bowser coming and going ---------------------------------------------------

    s.test("an attack waits for Bowser instead of being consumed without him", function()
        -- A brief ownership transfer removes the object locally. Consuming the
        -- sequence then would silently drop the attack for that player.
        local api, ctl, m = arena({ no_bowser = true })
        send(api, m, 2, 1)
        t.eq(#ctl.spawned, 0, "an attack played with no Bowser in the level")
        t.eq(api.runtime.boss_hazard_seq, 0, "the sequence was consumed while Bowser was away")

        ctl.objects[id_bhvBowser] = { oPosX = 0, oPosY = 0, oPosZ = 0,
                                      oFloorHeight = 0, oAction = 0 }
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the waiting attack never played")
        t.eq(api.runtime.boss_hazard_seq, 1, "the sequence was not consumed once he returned")
    end)

    s.test("attacks sent during Bowser's intro are consumed, not played", function()
        for _, action in ipairs({ 5, 6, 20 }) do
            local api, ctl, m, bowser = arena()
            bowser.oAction = action
            api.runtime.pending_double_waves = { ctl.timer }
            api.runtime.pending_meteors = { { at = ctl.timer, x = 0, y = 0, z = 0, seed = 0 } }
            send(api, m, 2, 1)
            t.eq(#ctl.spawned, 0, "action " .. action .. " played an attack during the intro")
            t.eq(api.runtime.boss_hazard_seq, 1, "action " .. action .. " left the sequence queued")
            t.eq(#api.runtime.pending_double_waves, 0,
                "action " .. action .. " left a delayed wave queued")
            t.eq(#api.runtime.pending_meteors, 0,
                "action " .. action .. " left a meteor queued")
        end
    end)

    s.test("a Bowser in any other action plays the attack", function()
        local api, ctl, m, bowser = arena()
        bowser.oAction = 7
        send(api, m, 2, 1)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "action 7 was treated as the intro")
    end)

    -- delayed hazards -----------------------------------------------------------

    s.test("a delayed second wave arrives on its own frame and not before", function()
        local api, ctl, m = arena()
        api.runtime.pending_double_waves = { ctl.timer + 10 }
        api.boss_hazards(m)
        t.eq(#ctl.spawned, 0, "the second wave arrived early")
        t.eq(#api.runtime.pending_double_waves, 1, "it left the queue early")

        ctl.timer = ctl.timer + 10
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the second wave never arrived")
        t.eq(#api.runtime.pending_double_waves, 0, "it stayed queued after arriving")
    end)

    s.test("meteor rain lands in four places a quarter circle apart", function()
        local api, ctl, m = arena()
        api.runtime.pending_meteors = { { at = ctl.timer, x = 0, y = 512, z = 0, seed = 0 } }
        m.pos.x, m.pos.z = 9000, 9000            -- well clear of all four
        api.boss_hazards(m)

        local booms = spawned_of(ctl, id_bhvExplosion)
        t.eq(#booms, 4, "meteor rain did not land in four places")
        -- Seed zero puts the first meteor straight ahead at radius 1250, and the
        -- other three at the quarter turns from it.
        local want = { { 0, 1250 }, { 1250, 0 }, { 0, -1250 }, { -1250, 0 } }
        for index, boom in ipairs(booms) do
            t.near(boom.oPosX, want[index][1], 0.001, "meteor " .. index .. " landed off its angle")
            t.near(boom.oPosZ, want[index][2], 0.001, "meteor " .. index .. " landed off its angle")
            t.eq(boom.oPosY, 512, "meteor " .. index .. " landed at the wrong height")
            t.eq(boom.model, E_MODEL_EXPLOSION, "meteor " .. index .. " was not an explosion")
        end
        t.eq(#api.runtime.pending_meteors, 0, "the meteor stayed queued after landing")
    end)

    s.test("the seed turns the whole pattern rather than being ignored", function()
        -- Without it every meteor rain in the round lands in the same four
        -- places and the attack becomes trivial to stand clear of.
        local api, ctl, m = arena()
        api.runtime.pending_meteors = {
            { at = ctl.timer, x = 0, y = 0, z = 0, seed = math.pi * 0.5 },
        }
        m.pos.x, m.pos.z = 9000, 9000
        api.boss_hazards(m)
        local booms = spawned_of(ctl, id_bhvExplosion)
        t.eq(#booms, 4, "the seeded rain did not land in four places")
        -- A quarter turn of seed moves the first meteor onto the second's place.
        t.near(booms[1].oPosX, 1250, 0.001, "the seed did not turn the pattern")
        t.near(booms[1].oPosZ, 0, 0.001, "the seed did not turn the pattern")
    end)

    s.test("a meteor kills whoever is under it and spares whoever is not", function()
        local api, ctl, m = arena()
        api.runtime.pending_meteors = { { at = ctl.timer, x = 0, y = 0, z = 0, seed = 0 } }
        m.pos.x, m.pos.z = 0, 1250               -- directly under the first meteor
        api.boss_hazards(m)
        t.eq(m.health, 0, "a direct hit did not kill")

        local api2, ctl2, m2 = arena()
        api2.runtime.pending_meteors = { { at = ctl2.timer, x = 0, y = 0, z = 0, seed = 0 } }
        m2.pos.x, m2.pos.z = 600, 1250           -- 600 units off, outside the 580 blast
        api2.boss_hazards(m2)
        t.eq(#spawned_of(ctl2, id_bhvExplosion), 4, "the meteors did not land at all")
        t.eq(m2.health, 0x880, "a miss by 600 units killed")

        local api3, ctl3, m3 = arena()
        api3.runtime.pending_meteors = { { at = ctl3.timer, x = 0, y = 0, z = 0, seed = 0 } }
        m3.pos.x, m3.pos.z = 500, 1250           -- 500 units off, inside the blast
        api3.boss_hazards(m3)
        t.eq(m3.health, 0, "a hit 500 units away did not kill")
    end)

    -- replaying the ring ---------------------------------------------------------

    s.test("an unchanged sequence number replays nothing", function()
        local api, ctl, m = arena()
        gGlobalSyncTable.sh5_boss_attack_queue_1 = 2
        gGlobalSyncTable.sh5_boss_attack_seq = 0
        api.boss_hazards(m)
        t.eq(#ctl.spawned, 0, "an attack was replayed with no new sequence")
    end)

    s.test("attacks that arrived in one update are all replayed", function()
        -- The reason the queue is eight slots rather than one field: sync
        -- updates coalesce under lag and a single field loses everything but
        -- the newest.
        local api, ctl, m = arena()
        for slot = 1, 3 do
            gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)] = 2
        end
        gGlobalSyncTable.sh5_boss_attack_seq = 3
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 3, "coalesced attacks were not all replayed")
        t.eq(api.runtime.boss_hazard_seq, 3, "the sequence was not caught up")
    end)

    s.test("no more than the ring's eight slots are replayed", function()
        local api, ctl, m = arena()
        for slot = 1, 8 do
            gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)] = 2
        end
        gGlobalSyncTable.sh5_boss_attack_seq = 20      -- twelve sequences were missed
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 8,
            "the ring replayed a different number of attacks than it can hold")
    end)

    s.test("the ring wraps rather than running off its end", function()
        -- Sequence 9 is slot 1 again. Reading slot 9 would find nothing.
        local api, ctl, m = arena()
        api.runtime.boss_hazard_seq = 8
        gGlobalSyncTable.sh5_boss_attack_queue_1 = 6
        gGlobalSyncTable.sh5_boss_attack_seq = 9
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvFlameMovingForwardGrowing), 8,
            "sequence 9 did not read slot 1")
    end)

    s.test("an attack already played is not played a second time", function()
        -- The replay starts one past what this client has seen. Starting AT it
        -- would replay the newest attack again on every later update.
        local api, ctl, m = arena()
        api.runtime.boss_hazard_seq = 8
        gGlobalSyncTable.sh5_boss_attack_queue_8 = 2    -- played on sequence 8
        gGlobalSyncTable.sh5_boss_attack_queue_1 = 6    -- the new one, sequence 9
        gGlobalSyncTable.sh5_boss_attack_seq = 9
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvFlameMovingForwardGrowing), 8, "the new attack did not play")
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 0, "the previous attack played again")
    end)

    s.test("each replayed attack carries its own sequence number", function()
        -- The quake takes its direction from the sequence. Replaying a run of
        -- them under the newest number throws the player the same way every
        -- time, which is what the varying direction exists to avoid.
        local api, _, m = arena()
        gGlobalSyncTable.sh5_boss_attack_queue_1 = 8
        gGlobalSyncTable.sh5_boss_attack_queue_2 = 8
        gGlobalSyncTable.sh5_boss_attack_seq = 2
        api.boss_hazards(m)
        t.near(m.vel.x, (math.sin(1 * 1.37) + math.sin(2 * 1.37)) * 55, 0.001,
            "the two quakes were not thrown by their own sequence numbers")
    end)

    s.test("an empty newest slot falls back to the single attack field", function()
        -- A host that wrote only the old single field must still be understood.
        local api, ctl, m = arena()
        gGlobalSyncTable.sh5_boss_attack_queue_1 = 0
        gGlobalSyncTable.sh5_boss_attack_kind = 2
        gGlobalSyncTable.sh5_boss_attack_seq = 1
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the newest attack was lost")
    end)

    s.test("the fallback is for the newest sequence only", function()
        -- An older empty slot means nothing was sent then. Reading the single
        -- field for it would replay the newest attack once per missed sequence.
        local api, ctl, m = arena()
        gGlobalSyncTable.sh5_boss_attack_queue_1 = 0
        gGlobalSyncTable.sh5_boss_attack_queue_2 = 6
        gGlobalSyncTable.sh5_boss_attack_kind = 2
        gGlobalSyncTable.sh5_boss_attack_seq = 2
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 0,
            "an old empty slot replayed the newest attack")
        t.eq(#spawned_of(ctl, id_bhvFlameMovingForwardGrowing), 8,
            "the attack that was really in the ring did not play")
    end)

    -- the attacks themselves -------------------------------------------------------

    s.test("a paralyzing wave starts at Bowser's feet and stuns for 30", function()
        local api, ctl, m, bowser = arena()
        send(api, m, 2, 1)
        local waves = spawned_of(ctl, id_bhvBowserShockWave)
        t.eq(#waves, 1, "the wave was not spawned")
        t.eq(waves[1].model, E_MODEL_BOWSER_WAVE, "the wave used the wrong model")
        t.eq(waves[1].oPosX, bowser.oPosX, "the wave was off Bowser in x")
        t.eq(waves[1].oPosY, bowser.oFloorHeight, "the wave did not start at the floor")
        t.eq(waves[1].oPosZ, bowser.oPosZ, "the wave was off Bowser in z")
        t.eq(api.runtime.boss_stun_frames, 30, "the wave did not stun for 30 frames")
    end)

    s.test("a wave further than 4800 units away spawns but does not stun", function()
        local api, ctl, m, bowser = arena()
        m.marioObj = { oPosX = bowser.oPosX + 5000, oPosY = bowser.oPosY, oPosZ = bowser.oPosZ }
        send(api, m, 2, 1)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the wave was not spawned")
        t.eq(api.runtime.boss_stun_frames, 0, "a wave 5000 units away stunned the player")

        local api2, _, m2, bowser2 = arena()
        m2.marioObj = { oPosX = bowser2.oPosX + 4000, oPosY = bowser2.oPosY, oPosZ = bowser2.oPosZ }
        send(api2, m2, 2, 1)
        t.eq(api2.runtime.boss_stun_frames, 30, "a wave 4000 units away did not stun")
    end)

    s.test("a new wave never shortens a stun already running", function()
        -- Two attacks can overlap. A 30-frame wave landing on top of a longer
        -- stun has to leave the longer one alone.
        local api, _, m = arena()
        api.runtime.boss_stun_frames = 40
        send(api, m, 2, 1)        -- the frame counts 40 down to 39 first
        t.eq(api.runtime.boss_stun_frames, 39, "a 30-frame wave cut a 40-frame stun short")
    end)

    s.test("a wave does not stun a player who is off the ground", function()
        local api, ctl, m = arena()
        m.floor = nil
        send(api, m, 2, 1)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the wave was not spawned")
        t.eq(api.runtime.boss_stun_frames, 0, "a jumping player was paralyzed")
    end)

    s.test("a wave does not stun a player with no Mario object yet", function()
        local api, ctl, m = arena()
        m.marioObj = nil
        send(api, m, 2, 1)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the wave was not spawned")
        t.eq(api.runtime.boss_stun_frames, 0, "a player with no object was paralyzed")
    end)

    s.test("the violet splitfire is a two-flame core and three branches", function()
        local api, ctl, m, bowser = arena()
        send(api, m, 3, 1)
        local flames = spawned_of(ctl, id_bhvFlameMovingForwardGrowing)
        t.eq(#flames, 5, "the splitfire was not five flames")
        for index, flame in ipairs(flames) do
            t.eq(flame.oPosY, bowser.oPosY + 180,
                "splitfire flame " .. index .. " was not raised above Bowser")
            t.eq(flame.oDamageOrCoinValue, 4, "splitfire flame " .. index .. " was harmless")
            t.eq(flame.oVelY, 8, "splitfire flame " .. index .. " did not rise")
        end
        -- The red and blue core overlap and stay put; the branches move.
        t.eq(flames[1].model, E_MODEL_RED_FLAME, "the core was not red first")
        t.eq(flames[1].oForwardVel, 0, "the red core moved off")
        t.eq(flames[1].scale, 2.2, "the red core was the wrong size")
        t.eq(flames[2].model, E_MODEL_BLUE_FLAME, "the core was not blue second")
        t.eq(flames[2].oForwardVel, 0, "the blue core moved off")
        t.eq(flames[2].scale, 1.9, "the blue core was the wrong size")
        local yaws = { 0, 0x5555, 0xAAAA }
        for branch = 1, 3 do
            local flame = flames[branch + 2]
            t.eq(flame.model, E_MODEL_BLUE_FLAME, "branch " .. branch .. " was not blue")
            t.eq(flame.oForwardVel, 34, "branch " .. branch .. " moved at the wrong speed")
            t.eq(flame.scale, 1.15, "branch " .. branch .. " was the wrong size")
            t.eq(flame.oMoveAngleYaw, yaws[branch], "branch " .. branch .. " went the wrong way")
            t.eq(flame.oFaceAngleYaw, yaws[branch], "branch " .. branch .. " faced the wrong way")
        end
    end)

    s.test("the flame ring is eight blue flames evenly around Bowser", function()
        local api, ctl, m, bowser = arena()
        send(api, m, 6, 1)
        local flames = spawned_of(ctl, id_bhvFlameMovingForwardGrowing)
        t.eq(#flames, 8, "the ring was not eight flames")
        for index, flame in ipairs(flames) do
            t.eq(flame.model, E_MODEL_BLUE_FLAME, "ring flame " .. index .. " was not blue")
            t.eq(flame.oMoveAngleYaw, (index - 1) * 0x2000,
                "ring flame " .. index .. " was not an eighth of a turn round")
            t.eq(flame.oForwardVel, 38, "ring flame " .. index .. " moved at the wrong speed")
            t.eq(flame.scale, 0.9, "ring flame " .. index .. " was the wrong size")
            t.eq(flame.oPosY, bowser.oPosY + 160,
                "ring flame " .. index .. " was at the wrong height")
            t.eq(flame.oVelY, 5, "ring flame " .. index .. " did not rise")
            t.eq(flame.oDamageOrCoinValue, 4, "ring flame " .. index .. " was harmless")
            t.eq(flame.oFaceAngleYaw, (index - 1) * 0x2000,
                "ring flame " .. index .. " faced away from where it was going")
        end
    end)

    s.test("the bomb barrage is a fire volley and spawns no bombs", function()
        -- The five real bombs in the arena are the only throwable ones. A
        -- barrage that spawned more would change how the fight is won.
        local api, ctl, m = arena()
        send(api, m, 7, 1)
        local flames = spawned_of(ctl, id_bhvFlameMovingForwardGrowing)
        t.eq(#flames, 5, "the barrage was not five flames")
        t.eq(#spawned_of(ctl, id_bhvBowserBomb), 0, "the barrage spawned real bombs")
        for index, flame in ipairs(flames) do
            t.eq(flame.model, E_MODEL_RED_FLAME, "barrage flame " .. index .. " was not red")
            t.eq(flame.oMoveAngleYaw, (index - 1) * 0x3333,
                "barrage flame " .. index .. " went the wrong way")
            t.eq(flame.oForwardVel, 45, "barrage flame " .. index .. " moved at the wrong speed")
            t.eq(flame.scale, 1.05, "barrage flame " .. index .. " was the wrong size")
        end
    end)

    s.test("the arena quake throws the player and stuns them briefly", function()
        local api, ctl, m = arena()
        send(api, m, 8, 1)
        local angle = 1 * 1.37
        t.near(m.vel.x, math.sin(angle) * 55, 0.001, "the quake threw the player wrongly in x")
        t.near(m.vel.z, math.cos(angle) * 55, 0.001, "the quake threw the player wrongly in z")
        t.eq(api.runtime.boss_stun_frames, 12, "the quake did not stun for 12 frames")
        t.eq(#ctl.spawned, 0, "the quake spawned an object")
    end)

    s.test("the quake's direction follows the sequence number", function()
        -- Two quakes in a row must not throw the player the same way, or a
        -- player pinned against a wall stays pinned.
        local first, second
        local api, _, m = arena()
        send(api, m, 8, 1)
        first = m.vel.x
        local api2, _, m2 = arena()
        send(api2, m2, 8, 2)
        second = m2.vel.x
        t.ne(first, second, "two sequences threw the player in the same direction")
    end)

    s.test("the warp wave is a wave and moves Bowser nowhere", function()
        -- It replaced a physical teleport: moving a held or network-owned
        -- Bowser could leave his tail impossible to grab.
        local api, ctl, m, bowser = arena()
        send(api, m, 9, 1)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the warp wave was not a wave")
        t.eq(api.runtime.boss_stun_frames, 16, "the warp wave did not stun for 16 frames")
        t.eq(bowser.oPosX, 100, "Bowser was moved in x")
        t.eq(bowser.oPosZ, 300, "Bowser was moved in z")
    end)

    s.test("the double wave arrives twice, 24 frames apart", function()
        local api, ctl, m = arena()
        send(api, m, 10, 1)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the first wave did not arrive")
        t.eq(api.runtime.boss_stun_frames, 24, "the first wave did not stun for 24 frames")
        t.eq(#api.runtime.pending_double_waves, 1, "the second wave was not queued")

        ctl.timer = ctl.timer + 23
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 1, "the second wave arrived a frame early")
        ctl.timer = ctl.timer + 1
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvBowserShockWave), 2, "the second wave never arrived")
        -- Two frames of the first stun have run off, and the second wave is
        -- the same 24 frames as the first rather than a longer one.
        t.eq(api.runtime.boss_stun_frames, 24, "the second wave stunned for a different length")
    end)

    s.test("meteor rain is queued to fall rather than exploding at once", function()
        local api, ctl, m, bowser = arena()
        send(api, m, 5, 1)
        t.eq(#ctl.spawned, 0, "meteor rain exploded on the frame it was sent")
        t.eq(#api.runtime.pending_meteors, 1, "no meteor was queued")
        local pending = api.runtime.pending_meteors[1]
        t.eq(pending.at, ctl.timer + 45, "the meteor was not queued 45 frames out")
        t.eq(pending.x, bowser.oPosX, "the meteor was not aimed at Bowser in x")
        t.eq(pending.y, bowser.oFloorHeight, "the meteor was not aimed at the floor")
        t.eq(pending.z, bowser.oPosZ, "the meteor was not aimed at Bowser in z")
        t.near(pending.seed, 1.71, 0.001, "sequence 1 did not seed the rain at 1.71")

        ctl.timer = ctl.timer + 45
        api.boss_hazards(m)
        t.eq(#spawned_of(ctl, id_bhvExplosion), 4, "the meteors never fell")
    end)

    s.test("the rain's seed follows the sequence number", function()
        -- Two rains in one round must not land in the same four places.
        local api, _, m = arena()
        send(api, m, 5, 2)
        t.near(api.runtime.pending_meteors[1].seed, 3.42, 0.001,
            "sequence 2 seeded the rain the same way as sequence 1")
    end)

    s.test("hunter fire sends three flames the way the player is", function()
        local api, ctl, m, bowser = arena()
        m.pos.x, m.pos.z = bowser.oPosX + 1000, bowser.oPosZ
        send(api, m, 11, 1)
        local flames = spawned_of(ctl, id_bhvFlameMovingForwardGrowing)
        t.eq(#flames, 3, "hunter fire was not three flames")
        t.eq(flames[1].model, E_MODEL_RED_FLAME, "the aimed flame was not red")
        t.eq(flames[1].oForwardVel, 50, "the aimed flame moved at the wrong speed")
        t.eq(flames[1].scale, 1.25, "the aimed flame was the wrong size")
        for _, index in ipairs({ 2, 3 }) do
            t.eq(flames[index].model, E_MODEL_BLUE_FLAME, "escort " .. index .. " was not blue")
            t.eq(flames[index].oForwardVel, 44, "escort " .. index .. " moved at the wrong speed")
            t.eq(flames[index].scale, 0.8, "escort " .. index .. " was the wrong size")
        end
        -- The escorts sit one sixteenth of a turn either side of the aimed one.
        t.eq(flames[2].oMoveAngleYaw - flames[1].oMoveAngleYaw, 0x0800,
            "the first escort was not a sixteenth of a turn off")
        t.eq(flames[1].oMoveAngleYaw - flames[3].oMoveAngleYaw, 0x0800,
            "the second escort was not a sixteenth of a turn off")

        -- The aim runs from Bowser towards the player. Taken the other way
        -- round it is exactly half a turn out, so the flames leave in the
        -- opposite direction and the attack can never hit anyone. A player
        -- 1000 units along x is a quarter turn round the circle, and the same
        -- player 1000 units back along it is three quarters.
        t.eq(flames[1].oMoveAngleYaw, 0x4000, "the flames were not aimed at the player")

        local api2, ctl2, m2, bowser2 = arena()
        m2.pos.x, m2.pos.z = bowser2.oPosX - 1000, bowser2.oPosZ
        send(api2, m2, 11, 1)
        local other = spawned_of(ctl2, id_bhvFlameMovingForwardGrowing)
        t.eq(other[1].oMoveAngleYaw, 0xC000,
            "the flames were not aimed at a player on Bowser's other side")
    end)

    s.test("hunter fire with no Mario object spawns nothing", function()
        local api, ctl, m = arena()
        m.marioObj = nil
        send(api, m, 11, 1)
        t.eq(#ctl.spawned, 0, "hunter fire aimed at a player with no object")
    end)

    s.test("modifiers that create no attack of their own spawn nothing", function()
        -- Instakill, Rage and Desperate change how the fight goes rather than
        -- producing a hazard, and slot 0 means nothing was ever sent.
        for _, kind in ipairs({ 0, 1, 4, 12 }) do
            local api, ctl, m = arena()
            send(api, m, kind, 1)
            t.eq(#ctl.spawned, 0, "attack kind " .. kind .. " spawned a hazard")
            t.eq(api.runtime.boss_stun_frames, 0, "attack kind " .. kind .. " stunned the player")
        end
    end)
end
