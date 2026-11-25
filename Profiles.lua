-- VoidMark Healer - profiles and SavedVariables
-- Account-wide: VoidMarkHealerDB.profiles (all profiles), lifetime history.
-- Per-character: VoidMarkHealerCharDB.profile (active profile), auto-switch map.
local _, VMH = ...
local P = VMH:NewModule("Profiles")

local DB_VERSION = 1

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
VMH.DeepCopy = deepCopy

-- Adds keys missing from target without touching saved values.
-- Channel sets are user choices, so an existing set is never merged with defaults.
local function fillMissing(target, defaults, path)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = deepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" and k ~= "channels" then
            fillMissing(target[k], v)
        end
    end
end

function P:Load()
    VoidMarkHealerDB = type(VoidMarkHealerDB) == "table" and VoidMarkHealerDB or {}
    VoidMarkHealerCharDB = type(VoidMarkHealerCharDB) == "table" and VoidMarkHealerCharDB or {}
    local db, cdb = VoidMarkHealerDB, VoidMarkHealerCharDB
    db.version = db.version or DB_VERSION
    db.profiles = type(db.profiles) == "table" and db.profiles or {}
    db.history = type(db.history) == "table" and db.history or {}
    for _, name in ipairs(VMH.PRESET_ORDER) do
        if type(db.profiles[name]) ~= "table" then db.profiles[name] = VMH.BuildPreset(name) end
    end
    local base = VMH.BaseProfile()
    for _, prof in pairs(db.profiles) do
        if type(prof) == "table" then fillMissing(prof, base) end
    end
    cdb.profile = cdb.profile or "Dungeon"
    if cdb.autoSwitch == nil then cdb.autoSwitch = true end
    cdb.autoMap = type(cdb.autoMap) == "table" and cdb.autoMap or {}
    if db.runIn == nil then db.runIn = "dungeonraid" end
    -- 1.0.7: the out-of-range alert was removed; drop its saved settings
    for _, prof in pairs(db.profiles) do
        if type(prof) == "table" and type(prof.alerts) == "table" then prof.alerts.range = nil end
    end
    db.rangeWhisperSet = nil
    -- 1.1.3: Dungeon profile quieter (once, only where still on the old defaults)
    if not db.dungeonQuietSet then
        db.dungeonQuietSet = true
        local d = db.profiles.Dungeon
        if type(d) == "table" and type(d.alerts) == "table" and type(d.countdown) == "table" then
            if d.alerts.multiEnemy and d.alerts.multiEnemy.threshold == 2 then d.alerts.multiEnemy.threshold = 3 end
            if d.countdown.minDuration == 5 then d.countdown.minDuration = 8 end
        end
    end
    -- 1.1.1: sounds off by default (once; turning them back on later sticks)
    if not db.soundsOffSet then
        db.soundsOffSet = true
        for _, prof in pairs(db.profiles) do
            if type(prof) == "table" then
                if type(prof.visuals) == "table" then prof.visuals.sound = false end
                if type(prof.countdown) == "table" then prof.countdown.sound = false end
            end
        end
    end
    -- 1.0.3: group messages start with the skull marker (once; a prefix you set is kept)
    if not db.skullPrefixSet then
        db.skullPrefixSet = true
        for _, prof in pairs(db.profiles) do
            if type(prof) == "table" and type(prof.announce) == "table" and (prof.announce.prefix == nil or prof.announce.prefix == "") then
                prof.announce.prefix = "{skull}"
            end
        end
    end
    fillMissing(cdb.autoMap, { party = "Dungeon", raid = "Raid", pvp = "PvP", arena = "PvP", world = "Solo", worldGroup = "Dungeon" })
    if not db.profiles[cdb.profile] then cdb.profile = "Dungeon" end
    VMH.db = db.profiles[cdb.profile]
    VMH.sv, VMH.csv = db, cdb
    -- persistent debug trail: keep lines written before saved data loaded
    db.log = type(db.log) == "table" and db.log or {}
    if VMH.debugLog ~= db.log then
        for _, l in ipairs(VMH.debugLog or {}) do db.log[#db.log + 1] = l end
        VMH.debugLog = db.log
    end
    VMH:Debug("---- loaded v" .. VMH.version .. ", profile " .. tostring(cdb.profile))
    self.lastKey = nil
end

function P:Current() return VMH.csv and VMH.csv.profile end

function P:List()
    local names = {}
    for name in pairs(VMH.sv.profiles) do names[#names + 1] = name end
    local order = {}
    for i, n in ipairs(VMH.PRESET_ORDER) do order[n] = i end
    table.sort(names, function(a, b)
        local oa, ob = order[a] or 99, order[b] or 99
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return names
end

function P:Select(name, silent)
    if not VMH.sv.profiles[name] then return false end
    if VMH.csv.profile == name then return true end
    VMH.csv.profile = name
    VMH.db = VMH.sv.profiles[name]
    VMH:ApplySettings()
    if not silent then VMH:Print("Profile: " .. name) end
    return true
end

function P:ContextKey()
    local inInstance, itype = VMH.Safe(_G.IsInInstance)
    if inInstance and itype and itype ~= "none" then
        if itype == "scenario" then return "party" end
        return itype
    end
    return (VMH.Safe(_G.IsInGroup) == true) and "worldGroup" or "world"
end

-- Switches only when the location type changes, so a profile picked by hand
-- stays until you move to a different kind of content.
function P:AutoSwitch()
    if not VMH.csv or not VMH.csv.autoSwitch then return end
    local key = self:ContextKey()
    if key == self.lastKey then return end
    self.lastKey = key
    local target = VMH.csv.autoMap[key]
    if target and VMH.sv.profiles[target] and target ~= VMH.csv.profile then
        self:Select(target, false)
    end
end

function P:IsPreset(name) return VMH.PRESETS[name] ~= nil end

function P:ResetProfile(name)
    name = name or VMH.csv.profile
    local fresh = self:IsPreset(name) and VMH.BuildPreset(name) or VMH.BaseProfile()
    VMH.sv.profiles[name] = fresh
    if name == VMH.csv.profile then
        VMH.db = fresh
        VMH:ApplySettings()
    end
end

function P:Copy(from, to)
    to = to or VMH.csv.profile
    if not VMH.sv.profiles[from] or from == to then return false end
    VMH.sv.profiles[to] = deepCopy(VMH.sv.profiles[from])
    if to == VMH.csv.profile then
        VMH.db = VMH.sv.profiles[to]
        VMH:ApplySettings()
    end
    return true
end

function P:Create(name, from)
    if type(name) ~= "string" then return false end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or VMH.sv.profiles[name] then return false end
    VMH.sv.profiles[name] = deepCopy(VMH.sv.profiles[from or VMH.csv.profile] or VMH.BaseProfile())
    return true
end

function P:Delete(name)
    if self:IsPreset(name) or not VMH.sv.profiles[name] then return false end
    VMH.sv.profiles[name] = nil
    for k, v in pairs(VMH.csv.autoMap) do if v == name then VMH.csv.autoMap[k] = "Custom" end end
    if VMH.csv.profile == name then self:Select("Custom") end
    return true
end

-- Character profile: a copy of the current settings named after this character.
function P:MakeCharacterProfile()
    local name = VMH.UnitFullName("player") or "Character"
    local realm = VMH.Safe(_G.GetRealmName)
    local pname = "Char: " .. name .. (realm and (" - " .. realm) or "")
    if not VMH.sv.profiles[pname] then self:Create(pname) end
    VMH.csv.autoSwitch = false
    self:Select(pname)
    return pname
end

-- Wipes every setting and profile (history is kept unless asked).
function P:ResetAll(includeHistory)
    VMH.sv.profiles = {}
    if includeHistory then VMH.sv.history = {} end
    VMH.csv.profile = "Dungeon"
    VMH.csv.autoSwitch = true
    VMH.csv.autoMap = {}
    self:Load()
    VMH:ApplySettings()
end
