-- StarHunt v1.1 - what Team mode adds on top of the star race.
--
-- Team mode runs the same round as Normal. The only things it adds are these:
-- players are split into two balanced rosters, and each player is painted
-- their team's colour.
--
-- The painting is the delicate half, because the colours are not StarHunt's to
-- keep. Every player's own palette is snapshotted before it is overwritten and
-- put back when the round ends, and the snapshot records which model it came
-- from -- so if Character Select swaps a player's model mid-round, the stale
-- snapshot is discarded rather than repainted onto the new model. Palette mods
-- that recolour a player without changing the model are handled the other way
-- round, by keeping only the parts they actually changed.
--
-- Not here yet, because each needs a module that has not been extracted:
-- participant_stats, pick_late and update_scores read round's host-side player
-- records, on_allow_pvp_attack needs players_can_share_world from goals, and
-- update_manual_reroll_menu needs manual_reroll_label from modifiers. They
-- join this module as those come out.

local core = require("core")
local Team = core.Team
local is_round_active = core.is_round_active
local is_boss_mode = core.is_boss_mode
local players_can_share_world = require("goals").players_can_share_world

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

-- Who may damage whom. Every mode answers differently: Chaos excludes players
-- already eliminated, Team allows only opposing colours, Boss allows none at
-- all, and Normal allows anyone who is genuinely in the same place. The
-- same-place question is players_can_share_world, so two players racing
-- different stars in one course cannot hit each other.
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

-- The roster and palette functions above attach to the shared Team table.
return {
    on_allow_pvp_attack = on_allow_pvp_attack,
}
