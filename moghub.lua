--[[----------------------------------------------------------------------------
    FFR_EnemyScaling -- MogHub plugin (settings page in the Mods menu)

    Every enemy below the party's level is raised to it; enemies at or above it stay as they are. Party level =
    highest, average or lowest level of the current party, plus an offset. Normal enemies and bosses can be
    switched separately. A raised enemy's stats (and EXP / Gil, if chosen) are multiplied by curve[new] /
    curve[old], the typical stat of a vanilla enemy at that level (curves.lua, separate for normal enemies and
    bosses), so an enemy that was tough for its level stays tough for its new one.

    HOW
      rows     : DT_UnitParameter (row struct UNIT_PARAMETER) is rewritten in memory on the map, never during an
                 encounter or a battle; a battle copies the rows of its enemies when it starts. The originals are
                 kept (kit.tables.patcher), so a lower party level, a setting or switching the plugin off writes the
                 game's own values back. Nothing goes into the save.
      enemies  : Category 2 (enemy) and 3 (boss); boss = Category 3 or IsBoss (story and side bosses, strong foes,
                 summons, the 12 Arms, Gilgamesh, Sephiroth, Ultima Weapon). Category 1 (playable), 4 (guests) and
                 5 (summoned visions) are never touched.
      excluded : battle groups (DT_BattleGroup) 700..799 (700 years ago), 9700..9799 (Colosseum ranks), the
                 Colosseum's boss events, scripted losses (lose event = win event), and any fight on a Colosseum
                 map. Rows used only by such groups are never scaled; when an excluded fight starts with rows it
                 shares with other fights, all rows go back to the game's values for that battle
                 (CPP_BFL_Battle.GetEncountBattleGroupdId at the start of the encounter).
      party    : CPP_BFL_SaveDataParty GetPartyMax / GetPartyUnitIdFromIndex, CPP_BFL_Unit GetPlayableUnitLevel
    ----------------------------------------------------------------------------]]
local mod, kit = ...
local CURVES = require("curves")

local HIGHEST, AVERAGE, LOWEST = 1, 2, 3

local cfg = mod:settings{
    { key = "Normal", label = "Scale normal enemies", type = "toggle", default = true,
      help = "Normal enemies below the party level are raised to it." },
    { key = "Bosses", label = "Scale bosses", type = "toggle", default = true,
      help = "Bosses below the party level are raised to it: story and side bosses, strong foes, summons, the 12 Arms and other superbosses." },
    { key = "Basis", label = "Party level", type = "choice", default = HIGHEST,
      choices = { { HIGHEST, "Highest" }, { AVERAGE, "Average" }, { LOWEST, "Lowest" } },
      help = "Which level of the current party the enemies are raised to." },
    { key = "Offset", label = "Level offset", type = "number", min = -5, max = 10, step = 1, default = 0, format = "%+g",
      help = "Added to the party level: +3 keeps every enemy at least 3 levels above you." },
    { key = "Rewards", label = "Scale EXP and Gil", type = "toggle", default = true,
      help = "A raised enemy also gives the EXP and Gil of its new level. Item drops stay the same." },
}

local STRUCT = "UNIT_PARAMETER"
local STATS = { "MaxHitPoint", "MaxBreakPoint", "Attack", "Defence", "Intelligence", "Mind", "Agility" }
local REWARDS = { "Experience", "Money" }
local ENEMY, BOSS = 2, 3            -- eUnitCategory
local MAX_LEVEL = 99
local COLOSSEUM_MAP = { "Arena", "Colosseum", "Coliseum" }

local logged = {}
local function logOnce(key, fmt, ...)
    if logged[key] then return end
    logged[key] = true
    mod:log(fmt, ...)
end

local function call(libName, fn, ...)
    local o = kit.game.lib(libName)
    if not o then
        logOnce("nolib:" .. libName, "%s not found", libName)
        return nil
    end
    local args = { ... }
    local ok, r = pcall(function() return o[fn](o, table.unpack(args)) end)
    if not ok then
        logOnce("fail:" .. fn, "%s.%s failed: %s", libName, fn, tostring(r))
        return nil
    end
    return r
end

local function text(v)
    local ok, s = pcall(function() return v:ToString() end)
    return ok and s or tostring(v)
end

---------------------------------------------------------------------------------------------------
-- Which fights are left alone
---------------------------------------------------------------------------------------------------
local groups = nil      -- { excluded = { [group] = true }, fixed = { [unit] = true }, names = { [group] = name } }

local function readGroups()
    local excluded, inExcluded, inOther, names, n = {}, {}, {}, {}, 0
    for _, t in ipairs(kit.tables.find("Colosseum_BossEventData")) do
        t.dt:ForEachRow(function(_, r) pcall(function() excluded[r.BattleGroupID] = true end) end)
    end
    kit.tables.rows("BATTLE_GROUP_DATA", function(row, rowName)
        local id = row.ID
        n = n + 1
        names[id] = tostring(rowName)
        local win, lose = text(row.battleFinishEventId), text(row.battleFinishLoseEventId)
        if (id >= 700 and id <= 799) or (id >= 9700 and id <= 9799) or (lose ~= "None" and lose == win) then
            excluded[id] = true
        end
        local into = excluded[id] and inExcluded or inOther
        local list = row.unitIdList
        for i = 1, #list do into[list[i]] = true end
    end)
    if n == 0 then return nil end
    local fixed, nFixed, nExcluded = {}, 0, 0
    for id in pairs(inExcluded) do
        if not inOther[id] then fixed[id], nFixed = true, nFixed + 1 end
    end
    for _ in pairs(excluded) do nExcluded = nExcluded + 1 end
    mod:log("%d battle groups, %d left alone, %d enemies only fought there", n, nExcluded, nFixed)
    return { excluded = excluded, fixed = fixed, names = names }
end

local function mapName()
    local unit = call("CPP_BFL_Map", "GetPlayerMapUnit")
    if not kit.valid(unit) then return nil end
    local ok, name = pcall(function() return unit:GetFullName() end)
    return ok and name:match("(/Game/Map/[^%.]+)") or nil
end

local function onColosseumMap(map)
    if not map then return false end
    for _, word in ipairs(COLOSSEUM_MAP) do
        if map:find(word, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- Party level
---------------------------------------------------------------------------------------------------
local function partyLevels()
    local max = tonumber(call("CPP_BFL_SaveDataParty", "GetPartyMax"))
    if not max then return nil end
    local levels, seen = {}, {}
    for i = 0, max - 1 do
        local id = tonumber(call("CPP_BFL_SaveDataParty", "GetPartyUnitIdFromIndex", i))
        if id and id > 0 and not seen[id] then
            seen[id] = true
            local lv = tonumber(call("CPP_BFL_Unit", "GetPlayableUnitLevel", id))
            if lv and lv > 0 then levels[#levels + 1] = lv end
        end
    end
    if #levels == 0 then return nil end
    return levels
end

local function targetLevel(levels)
    local lv
    if cfg.Basis == AVERAGE then
        local sum = 0
        for _, l in ipairs(levels) do sum = sum + l end
        lv = math.floor(sum / #levels + 0.5)
    else
        lv = levels[1]
        for _, l in ipairs(levels) do
            if (cfg.Basis == LOWEST and l < lv) or (cfg.Basis ~= LOWEST and l > lv) then lv = l end
        end
    end
    return math.max(1, math.min(MAX_LEVEL, lv + math.floor(cfg.Offset)))
end

---------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------
local patch = kit.tables.patcher()
local active = true          -- false while the plugin is off
local paused = false         -- true during an excluded fight: every row has the game's values

local function scaled(v, l0, l, curve)
    if type(v) ~= "number" or v <= 0 or l == l0 or not (curve and curve[l0] and curve[l]) then return v end
    return math.max(1, math.min(2147483647, v * curve[l] / curve[l0]))
end

-- target nil: every row back to the game's values
local function apply(target, force)
    local state = target and table.concat({ target, tostring(cfg.Normal), tostring(cfg.Bosses), tostring(cfg.Rewards) }, "|") or "vanilla"
    if force then patch:invalidate() end
    local raised, normal, boss, example = 0, 0, 0, nil
    local ran = patch:apply(STRUCT, state, function(row, orig)
        local cat = orig("Category")
        if cat ~= ENEMY and cat ~= BOSS then return end
        local id, l0 = orig("ID"), orig("Level")
        local isBoss = cat == BOSS or orig("IsBoss") == true
        local l = l0
        if target and l0 < target and not (groups and groups.fixed[id]) and (isBoss and cfg.Bosses or not isBoss and cfg.Normal) then
            l = target
        end
        local curve = CURVES[isBoss and "boss" or "normal"]
        kit.tables.set(row, "Level", l)
        for _, f in ipairs(STATS) do kit.tables.set(row, f, scaled(orig(f), l0, l, curve[f])) end
        for _, f in ipairs(REWARDS) do
            kit.tables.set(row, f, cfg.Rewards and scaled(orig(f), l0, l, curve[f]) or orig(f))
        end
        if l ~= l0 then
            raised = raised + 1
            if isBoss then boss = boss + 1 else normal = normal + 1 end
            if not example or orig("MaxHitPoint") > example[2] then
                example = { id, orig("MaxHitPoint"), l0, l, row.MaxHitPoint }
            end
        end
    end)
    if ran then
        if target then
            mod:log("target Lv %d: %d enemies raised (%d normal, %d bosses)%s", target, raised, normal, boss,
                example and string.format(", e.g. unit %d Lv %d -> %d, HP %d -> %d", example[1], example[3], example[4], example[2], example[5]) or "")
        else
            mod:log("all enemies back to the game's values")
        end
    end
    return true
end

---------------------------------------------------------------------------------------------------
-- When: on a game map, not in an encounter, a battle or behind a loading screen
---------------------------------------------------------------------------------------------------
local NOT_IN_GAME = { Title = true, Boot = true }
local encounter = false

local function onGameMap()
    local map = mapName()
    local category = map and map:match("^/Game/Map/(%w+)")
    return category ~= nil and not NOT_IN_GAME[category]
end

local function ready()
    if encounter or not kit.game.saveData() or kit.loading or kit.events.battle or kit.game.inBattle() then return false end
    return call("CPP_BFL_Map", "IsDuringEncount") == false and onGameMap()
end

local function update(force)
    if not ready() then return false end
    if not groups then groups = readGroups() end
    if not active or paused then return apply(nil, force) end
    if not (cfg.Normal or cfg.Bosses) then return apply(nil, force) end
    local levels = partyLevels()
    if not levels then return false end
    return apply(targetLevel(levels), force)
end

local function updateSoon(delay, force)
    local function try()
        if not update(force) then kit.after(1000, try, "enemy scaling retry") end
    end
    kit.after(delay, try, "enemy scaling")
end

-- the start of an encounter: an excluded fight gets the game's own rows
local function encounterBegins()
    local group = tonumber(call("CPP_BFL_Battle", "GetEncountBattleGroupdId"))
    local map = mapName()
    local excluded = (groups and group and groups.excluded[group]) or onColosseumMap(map)
    mod:log("encounter: battle group %s (%s) on %s%s", tostring(group), groups and group and groups.names[group] or "?",
        tostring(map), excluded and ", left alone" or "")
    if excluded and active then
        paused = true
        apply(nil)
    end
end

-- one line per battle with what its enemies really have
local function logBattle()
    local parts = {}
    for _, e in ipairs(kit.game.battleSide(kit.game.ENEMY)) do
        local lv, hp
        pcall(function() lv = e.param:GetRawParameter().Level end)
        pcall(function() hp = e.param:GetMaxHitPoint() end)
        parts[#parts + 1] = string.format("%s Lv %s HP %s", tostring(e.id), tostring(lv), tostring(hp))
        if #parts >= 8 then break end
    end
    if #parts > 0 then
        mod:log("battle group %s, enemies: %s", tostring(call("CPP_BFL_Battle", "GetEncountBattleGroupdId")), table.concat(parts, ", "))
    end
end

mod:every(100, function()
    local now = call("CPP_BFL_Map", "IsDuringEncount") == true
    if now and not encounter then
        encounter = true
        encounterBegins()
    elseif not now and encounter and not kit.game.inBattle() then
        encounter = false
        if paused then paused = false end
        updateSoon(500)
    end
end, "enemy scaling encounter")

-- also notices the game reloading the table (a new table object), which drops the edits
mod:every(3000, function() update(false) end, "enemy scaling check")
mod:on("saveLoaded", function() updateSoon(2000, true) end)
mod:on("loadingEnd", function() updateSoon(1000, true) end)
mod:on("battleStart", function() mod:after(1500, logBattle, "enemy scaling battle log") end)
cfg:onChange(function() updateSoon(200) end)
mod:onToggle(function(on)
    active = on
    updateSoon(200, true)
end)

mod:log("v%s ready: normal %s, bosses %s, basis %s, offset %+d, rewards %s", mod.version, tostring(cfg.Normal),
    tostring(cfg.Bosses), tostring(cfg.Basis), math.floor(cfg.Offset), tostring(cfg.Rewards))
