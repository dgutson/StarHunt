-- StarHunt v1.1 - the round, client side.
--
-- Everything here runs on every player's own machine and only reads the round
-- state the host publishes.  Nothing in this file decides anything: the host
-- writes sh5_return_seq, sh5_forfeit and the rest, and these functions react.
--
-- Four things happen on a client during and after a round: it warps back to
-- the castle grounds when the host ends the round, it hides players hunting a
-- private variant of the same star, it refuses to let the pause menu quit
-- mid-round, and it cancels vanilla's death sequence so StarHunt can hand out
-- a replacement goal instead of a game over.
--
-- The host side of the round -- host_start_round, host_end_round,
-- host_update_round and the player records they rebind -- is still in main.lua.
-- It cannot move yet: it calls four Boss helpers (boss_time_range_for_players,
-- boss_has_modifier, boss_is_desperate, host_read_boss_health_report) that are
-- waiting for boss.lua's second pass.
--
-- Every function below is registered as a hook in main.lua.  The hook block
-- stays there because order within a hook type matters.

local core = require("core")
local Team = core.Team
local local_runtime = core.local_runtime
local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND
local is_round_active = core.is_round_active
local is_boss_mode = core.is_boss_mode
local translated = require("i18n").translated
local flush_starhunt_save_removals = require("save").flush_starhunt_save_removals
local goals = require("goals")
local get_local_goal = goals.get_local_goal
local players_have_private_variant = goals.players_have_private_variant
local grant_infinite_lives = require("modifiers").grant_infinite_lives

local local_seen_return_seq = 0
local local_return_warp_pending = false
local local_return_warp_retry_at = 0

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

local function on_pause_exit(_)
    if is_round_active() then
        djui_popup_create(translated("FINISH THE ROUND OR ASK THE HOST TO STOP IT.", "TERMINA LA RONDA O PIDE AL HOST QUE LA DETENGA."), 1)
        return false
    end
    return true
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

-- main.lua registers every one of these as a hook and publishes four of them
-- through STARHUNT_TEST_API.  STARHUNT_DEATH_ACTIONS and the three
-- local_return_warp_* variables are read nowhere else and stay private.
return {
    force_return_to_lobby = force_return_to_lobby,
    on_nametags_render = on_nametags_render,
    update_private_player_visibility = update_private_player_visibility,
    on_pause_exit = on_pause_exit,
    on_death = on_death,
    on_before_death_action = on_before_death_action,
    on_dialog = on_dialog,
}
