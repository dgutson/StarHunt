-- The modifiers as the local player feels them.
--
-- Everything here runs locally every frame: what is synchronized is only WHICH
-- modifier a player has, never how it feels. Extracting modules/modifiers.lua
-- found the entry points untested -- SH.apply_local_modifier was published to
-- STARHUNT_TEST_API and never called, so an early return that switched every
-- modifier in the mod off left the suite green.

return function(t, harness)
    local s = t.suite("modifiers")

    --- Give the local player the goal and modifier slot that carry `kind`.
    -- Returns the effective modifier the mod will act on.
    local function arm(api, ctl, kind, difficulty)
        for goal_id, goal in ipairs(api.goals) do
            for index, m in ipairs(goal.mods) do
                if m.kind == kind then
                    gPlayerSyncTable[0].sh5_goal = goal_id
                    gPlayerSyncTable[0].sh5_modifier = index
                    gPlayerSyncTable[0].sh5_modifier_2 = 0
                    ctl.begin_round(api, api.normal_mode, difficulty or api.medium,
                        goal.level)
                    gNetworkPlayers[0].currActNum = goal.act
                    local list = api.local_modifiers()
                    return list[1]
                end
            end
        end
        t.fail("no goal in the catalog allows " .. kind)
    end

    local function mario()
        local m = gMarioStates[0]
        m.playerIndex = 0
        m.forwardVel = 0
        m.intendedMag = 0
        m.vel = { x = 0, y = 0, z = 0 }
        m.action = 0
        m.controller.buttonDown = 0
        m.controller.buttonPressed = 0
        return m
    end

    s.test("a capped runner is actually slowed down", function()
        local api, ctl = harness.load()
        local cap = arm(api, ctl, "speed_cap")
        local m = mario()

        m.forwardVel = cap.value + 40
        m.intendedMag = cap.value + 40
        api.modifier(m)
        t.eq(m.forwardVel, cap.value, "forward speed was not capped")
        t.eq(m.intendedMag, cap.value, "intended speed was not capped")

        m.forwardVel = -(cap.value + 40)
        api.modifier(m)
        t.eq(m.forwardVel, -cap.value, "backward speed was not capped")

        m.forwardVel = cap.value - 5
        api.modifier(m)
        t.eq(m.forwardVel, cap.value - 5, "a legal speed was changed")
    end)

    s.test("a locked B button is taken out of the controller", function()
        local api, ctl = harness.load()
        arm(api, ctl, "no_b")
        local m = mario()
        m.controller.buttonDown = B_BUTTON | A_BUTTON
        m.controller.buttonPressed = B_BUTTON | A_BUTTON
        api.modifier(m)
        t.eq(m.controller.buttonDown & B_BUTTON, 0, "B was still held")
        t.eq(m.controller.buttonPressed & B_BUTTON, 0, "B was still pressed")
        t.ne(m.controller.buttonDown & A_BUTTON, 0, "A was taken away too")
    end)

    s.test("nothing is applied outside a round or behind the config menu", function()
        -- The menu freezes the player; running the challenge underneath it
        -- would damage or slow someone who cannot see the game.
        local api, ctl = harness.load()
        local cap = arm(api, ctl, "speed_cap")
        local m = mario()
        local fast = cap.value + 40

        gGlobalSyncTable.sh5_active = 0
        m.forwardVel = fast
        api.modifier(m)
        t.eq(m.forwardVel, fast, "a modifier applied with no round running")

        gGlobalSyncTable.sh5_active = 1
        api.runtime.config_open = true
        m.forwardVel = fast
        api.modifier(m)
        t.eq(m.forwardVel, fast, "a modifier applied while the menu was open")

        api.runtime.config_open = false
        m.forwardVel = fast
        api.modifier(m)
        t.eq(m.forwardVel, cap.value, "the modifier stopped applying altogether")
    end)

    s.test("the second pass is gated on the round and the menu too", function()
        -- apply_post_moveset_limits carries its own copy of the guard, because
        -- it runs from a different hook. Checking only the first pass leaves
        -- this one free to clamp a player who is standing in the lobby or
        -- reading the menu.
        local api, ctl = harness.load()
        local cap = arm(api, ctl, "speed_cap")
        local m = mario()
        local fast = cap.value + 60

        gGlobalSyncTable.sh5_active = 0
        m.forwardVel = fast
        api.post_moveset_limits(m)
        t.eq(m.forwardVel, fast, "the second pass clamped with no round running")

        gGlobalSyncTable.sh5_active = 1
        api.runtime.config_open = true
        m.forwardVel = fast
        api.post_moveset_limits(m)
        t.eq(m.forwardVel, fast, "the second pass clamped while the menu was open")

        api.runtime.config_open = false
        m.forwardVel = fast
        api.post_moveset_limits(m)
        t.eq(m.forwardVel, cap.value, "the second pass stopped clamping altogether")
    end)

    s.test("an eliminated Chaos player is left alone", function()
        -- Elimination makes a player a spectator. Still running the challenge
        -- on them would damage or slow someone with nothing left to play for.
        local api, ctl = harness.load()
        gPlayerSyncTable[0].sh5_goal = 1
        gPlayerSyncTable[0].sh5_modifier = 3
        ctl.begin_round(api, api.chaos_mode, api.medium)
        gGlobalSyncTable.sh5_chaos_level = gNetworkPlayers[0].currLevelNum
        local m = mario()

        local base = api.get_local_modifier_base(1)
        t.ok(base ~= nil, "Chaos gave the player no modifier to test with")

        gPlayerSyncTable[0].sh5_chaos_eliminated = 1
        m.controller.buttonDown = B_BUTTON
        m.forwardVel = 200
        api.modifier(m)
        t.eq(m.forwardVel, 200, "an eliminated player was still being slowed")
    end)

    s.test("the limits are re-clamped after other mods have had their turn", function()
        -- Character and moveset mods such as OMM run their own
        -- HOOK_MARIO_UPDATE callbacks and replace velocities after StarHunt's
        -- before-update pass. Without the second pass the challenge is simply
        -- undone for anyone running one.
        local api, ctl = harness.load()
        local cap = arm(api, ctl, "speed_cap")
        local m = mario()
        api.modifier(m)
        m.forwardVel = cap.value + 60          -- a moveset mod overwrites it
        api.post_moveset_limits(m)
        t.eq(m.forwardVel, cap.value, "the speed cap was not reapplied")
    end)

    s.test("only Nightmare hands out a second modifier", function()
        -- Below Nightmare a second slot may be set and must still be ignored.
        -- Nightmare uses it -- but only where the audit still approves the pair
        -- at Nightmare's scaling, so the test looks for a combination that
        -- survives rather than assuming any two slots will.
        local api, ctl = harness.load()

        for _, difficulty in ipairs({ api.easy, api.medium, api.hard }) do
            for goal_id = 1, 10 do
                gPlayerSyncTable[0].sh5_goal = goal_id
                gPlayerSyncTable[0].sh5_modifier = 1
                gPlayerSyncTable[0].sh5_modifier_2 = 2
                ctl.begin_round(api, api.normal_mode, difficulty)
                t.ok(#api.local_modifiers() <= 1, "difficulty " .. difficulty
                    .. " granted two modifiers on goal " .. goal_id)
            end
        end

        local paired = false
        for goal_id = 1, #api.goals do
            for slot = 2, #api.goals[goal_id].mods do
                gPlayerSyncTable[0].sh5_goal = goal_id
                gPlayerSyncTable[0].sh5_modifier = 1
                gPlayerSyncTable[0].sh5_modifier_2 = slot
                ctl.begin_round(api, api.normal_mode, api.nightmare)
                if #api.local_modifiers() == 2 then paired = true end
            end
        end
        t.ok(paired, "Nightmare never granted a second modifier on any star")
    end)

    s.test("the second modifier is never a repeat of the first", function()
        -- Two copies of one modifier is not a harder round, it is the same
        -- round with a wasted slot -- and for the counted ones it silently
        -- doubles the count.
        local api, ctl = harness.load()
        gPlayerSyncTable[0].sh5_goal = 1
        gPlayerSyncTable[0].sh5_modifier = 1
        gPlayerSyncTable[0].sh5_modifier_2 = 1        -- deliberately the same slot
        ctl.begin_round(api, api.normal_mode, api.nightmare)
        local list = api.local_modifiers()
        t.eq(#list, 1, "the same modifier was handed out twice")
    end)

    s.test("each mode draws its modifiers from its own catalog", function()
        local api, ctl = harness.load()

        ctl.begin_round(api, api.boss_mode, api.medium)
        gGlobalSyncTable.sh5_boss_player_modifier = 2
        t.eq(api.get_local_modifier_base(1), api.boss_player_modifiers[2],
            "Boss mode did not draw from the Boss player catalog")

        ctl.begin_round(api, api.chaos_mode, api.medium)
        gPlayerSyncTable[0].sh5_modifier = 3
        t.eq(api.get_local_modifier_base(1), api.normal_modifier_catalog[3],
            "Chaos did not draw from the full audited catalog")

        gPlayerSyncTable[0].sh5_goal = 5
        gPlayerSyncTable[0].sh5_modifier = 2
        ctl.begin_round(api, api.normal_mode, api.medium)
        t.eq(api.get_local_modifier_base(1), api.goals[5].mods[2],
            "a star race did not draw from what the audit approved for that star")
    end)

    s.test("capping a vector keeps its direction and its length", function()
        -- Used for swimming, where capping each axis separately would make
        -- diagonal movement faster than straight movement.
        local api = harness.load()
        local x, z = api.capped_horizontal_velocity(30, 40, 10)   -- length 50
        t.near(math.sqrt(x * x + z * z), 10, 0.001, "the vector was not capped to 10")
        t.near(x / z, 30 / 40, 0.001, "the direction changed")

        local sx, sz = api.capped_horizontal_velocity(3, 4, 10)    -- already short
        t.eq(sx, 3, "a vector inside the cap was changed")
        t.eq(sz, 4, "a vector inside the cap was changed")
    end)

    -- Whether the local player counts as standing on the ground.
    --
    -- Seven modifiers ask this before doing anything at all -- the cursed
    -- floor, the jump limit, Slippery, Keep Moving, the jump cooldown, the
    -- momentum burst and Overheat -- and so do Bowser's shockwaves. Nothing
    -- tested it: the suite's Mario has no floor at all, so the answer was
    -- always false and every one of those effects was being skipped. The
    -- predicate could be replaced by `return true` with the suite still green.
    --
    -- The cursed floor is what these drive it through, because it is the one
    -- caller that keeps a visible running count of the frames it accepted.

    --- Place Mario `height` units above a floor, optionally swimming.
    local function stand(m, height, swimming)
        m.floor = {}
        m.floorHeight = 0
        m.pos.y = height
        m.action = swimming and ACT_FLAG_SWIMMING or 0
        m.health = 0x880
    end

    --- Run the cursed floor for a whole `seconds` worth of frames.
    local function endure(api, m, seconds)
        for _ = 1, seconds * 30 do api.modifier(m) end
    end

    s.test("standing on the ground is what the cursed floor counts", function()
        local api, ctl = harness.load()
        local doom = arm(api, ctl, "floor_doom")
        local m = mario()
        stand(m, 0, false)
        endure(api, m, doom.value)
        t.eq(m.health, 0, "the cursed floor never fired on a player stood on it")
    end)

    s.test("a player with no floor under them is not on the ground", function()
        local api, ctl = harness.load()
        local doom = arm(api, ctl, "floor_doom")
        local m = mario()
        m.health = 0x880
        m.floor = nil          -- mid-air: the height below would say "on the floor"
        m.floorHeight = 0
        m.pos.y = 0
        endure(api, m, doom.value * 2)
        t.eq(m.health, 0x880, "the cursed floor fired on a player who was not on a floor")
    end)

    s.test("a swimming player is not on the ground", function()
        local api, ctl = harness.load()
        local doom = arm(api, ctl, "floor_doom")
        local m = mario()
        stand(m, 0, true)      -- standing on the sea bed is still swimming
        endure(api, m, doom.value * 2)
        t.eq(m.health, 0x880, "the cursed floor fired on a swimming player")
    end)

    s.test("the ground reaches 22 units up and no further", function()
        -- The boundary is pinned at exactly 22, one unit either side. Reading
        -- the tolerance back out of the mod would agree with whatever the mod
        -- said it was.
        local api, ctl = harness.load()
        local doom = arm(api, ctl, "floor_doom")
        local near = mario()
        stand(near, 21, false)
        endure(api, near, doom.value)
        t.eq(near.health, 0, "21 units above the floor did not count as on it")

        local api2, ctl2 = harness.load()
        local doom2 = arm(api2, ctl2, "floor_doom")
        local far = mario()
        stand(far, 22, false)
        endure(api2, far, doom2.value * 2)
        t.eq(far.health, 0x880, "22 units above the floor counted as on it")
    end)

    s.test("a player below the floor is not standing on it", function()
        -- The distance is an absolute one. Without that, everything under the
        -- floor -- at any depth at all -- reads as standing on it.
        local api, ctl = harness.load()
        local doom = arm(api, ctl, "floor_doom")
        local m = mario()
        stand(m, -100, false)
        endure(api, m, doom.value * 2)
        t.eq(m.health, 0x880, "100 units below the floor counted as on it")
    end)
end
