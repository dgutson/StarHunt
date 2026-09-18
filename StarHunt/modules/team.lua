-- StarHunt v1.1.2 - what Team mode adds on top of the star race.
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
-- The module is complete. Two of its functions reach code in other modules
-- without importing them: update_manual_reroll_menu calls a label built in
-- modifiers.lua, and both of them are fields on the shared SH table, so they
-- are reached by reference. That matters here, because team.lua cannot import
-- modifiers.lua or round.lua at all -- modifiers.lua requires this module for
-- on_allow_pvp_attack, and round.lua requires modifiers.lua, so either import
-- would close a require cycle.

local core = require("core")
local SH = core.SH
local Team = core.Team
local is_round_active = core.is_round_active
local is_boss_mode = core.is_boss_mode
local player_record_key = core.player_record_key
local players_can_share_world = require("goals").players_can_share_world

-- How far one team's score must trail before pick_late, its only caller, puts
-- a new player on that team. Two points rather than one, so that a tie does
-- not shuffle players between teams on every star.
local TEAM_SCORE_PRIORITY_GAP = 2

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
            team = Team.Color.BLUE
        elseif blue_count >= blue_cap then
            team = Team.Color.RED
        elseif red_skill < blue_skill then
            team = Team.Color.RED
        elseif blue_skill < red_skill then
            team = Team.Color.BLUE
        elseif red_count < blue_count then
            team = Team.Color.RED
        elseif blue_count < red_count then
            team = Team.Color.BLUE
        else
            team = math.random(2) == 1 and Team.Color.RED or Team.Color.BLUE
        end
        Team.initial[player.index] = team
        if team == Team.Color.RED then
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
        [Team.Color.RED] = { count = 0, skill = 0, score = 0 },
        [Team.Color.BLUE] = { count = 0, skill = 0, score = 0 },
    }
    local connected_keys = {}
    for i = 0, MAX_PLAYERS - 1 do
        local sync = gPlayerSyncTable[i]
        if gNetworkPlayers[i].connected and (sync.sh5_enrolled or 0) == 1 then
            local team = sync.sh5_team or Team.Color.NONE
            if stats[team] ~= nil then
                stats[team].count = stats[team].count + 1
                stats[team].skill = stats[team].skill + math.max(0, sync.sh5_lifetime_stars or 0)
                stats[team].score = stats[team].score + math.max(0, sync.sh5_score or 0)
            end
            local key = player_record_key(i)
            if key ~= nil then connected_keys[key] = true end
        end
    end
    for key, record in pairs(SH.host_player_records) do
        local team = record.team or Team.Color.NONE
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
    if stats[Team.Color.RED].count < stats[Team.Color.BLUE].count then return Team.Color.RED end
    if stats[Team.Color.BLUE].count < stats[Team.Color.RED].count then return Team.Color.BLUE end

    -- With equal rosters, help a team that trails by at least two points.
    -- A one-point gap is intentionally too small to override reconnection or
    -- experience balance, preventing constant team changes around a tie.
    if stats[Team.Color.RED].score - stats[Team.Color.BLUE].score >= TEAM_SCORE_PRIORITY_GAP then
        return Team.Color.BLUE
    end
    if stats[Team.Color.BLUE].score - stats[Team.Color.RED].score >= TEAM_SCORE_PRIORITY_GAP then
        return Team.Color.RED
    end

    -- Preserve a reconnect's previous team whenever the two stronger rules
    -- above do not require a different assignment.
    if preferred_team == Team.Color.RED or preferred_team == Team.Color.BLUE then return preferred_team end

    if stats[Team.Color.RED].skill < stats[Team.Color.BLUE].skill then return Team.Color.RED end
    if stats[Team.Color.BLUE].skill < stats[Team.Color.RED].skill then return Team.Color.BLUE end
    return math.random(2) == 1 and Team.Color.RED or Team.Color.BLUE
end

Team.update_scores = function()
    if not network_is_server() or not SH.is_team_mode() then return end
    local stats = Team.participant_stats()
    gGlobalSyncTable.sh5_red_score = stats[Team.Color.RED].score
    gGlobalSyncTable.sh5_blue_score = stats[Team.Color.BLUE].score
end

Team.color_rgb = {
    [Team.Color.RED] = { r = 225, g = 42, b = 48 },
    [Team.Color.BLUE] = { r = 45, g = 104, b = 235 },
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
    if not is_round_active() or not SH.is_team_mode() then
        Team.restore_palettes()
        return
    end
    Team.paletteActive = true
    if get_global_timer() < Team.paletteRefreshAt then return end
    Team.paletteRefreshAt = get_global_timer() + 15
    for i = 0, MAX_PLAYERS - 1 do
        local player = gNetworkPlayers[i]
        local team = gPlayerSyncTable[i].sh5_team or Team.Color.NONE
        local color = Team.color_rgb[team]
        if player ~= nil and player.connected and color ~= nil then
            Team.capture_palette(player, i, color)
            for part = PANTS, EMBLEM do
                network_player_set_override_palette_color(player, part, color)
            end
        end
    end
end

SH.update_manual_reroll_menu = function()
    if SH.rerollMenuIndex == nil or type(update_mod_menu_element_name) ~= "function" then
        return
    end
    local label = SH.manual_reroll_label()
    if label ~= SH.rerollMenuLabel then
        SH.rerollMenuLabel = label
        update_mod_menu_element_name(SH.rerollMenuIndex, label)
    end
end

-- Who may damage whom. Every mode answers differently: Chaos excludes players
-- already eliminated, Team allows only opposing colours, Boss allows none at
-- all, and Normal allows anyone who is genuinely in the same place. The
-- same-place question is players_can_share_world: two players racing different
-- stars in one course fight, whichever acts they were sent to, and two whose
-- stars are in different courses never meet at all.
local function on_allow_pvp_attack(attacker, victim, _)
    local attacker_index = attacker.playerIndex
    local victim_index = victim.playerIndex
    if SH.is_chaos_mode()
        and ((gPlayerSyncTable[attacker_index].sh5_chaos_eliminated or 0) == 1
            or (gPlayerSyncTable[victim_index].sh5_chaos_eliminated or 0) == 1) then
        return false
    end
    if not players_can_share_world(attacker_index, victim_index) then return false end
    if SH.is_team_mode() then
        local attacker_team = gPlayerSyncTable[attacker_index].sh5_team or Team.Color.NONE
        local victim_team = gPlayerSyncTable[victim_index].sh5_team or Team.Color.NONE
        return attacker_team ~= Team.Color.NONE and victim_team ~= Team.Color.NONE
            and attacker_team ~= victim_team
    end
    return not is_boss_mode()
end

-- The roster and palette functions above attach to the shared Team table, and
-- update_manual_reroll_menu to the mod-wide SH table.
return {
    on_allow_pvp_attack = on_allow_pvp_attack,
}
