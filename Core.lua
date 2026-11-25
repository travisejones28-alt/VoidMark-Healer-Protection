-- VoidMark Healer - Core
-- Client boundary, event dispatch, module lifecycle.
-- Forever can hand addons "secret" values in combat. Every value read from the
-- client goes through VMH.Readable/VMH.Safe; secret values become nil and are
-- never compared, concatenated or sent to chat.
local ADDON, VMH = ...
VoidMarkHealer = VMH
VMH.name = ADDON
VMH.version = "1.1.0"
VMH.modules = {}
VMH.debugLog = {}
VMH.session = { started = nil }

local pcall, type, select, unpack = pcall, type, select, unpack or table.unpack

------------------------------------------------------------------------
-- Secret-safe readers
------------------------------------------------------------------------
function VMH.Readable(value)
    if value == nil then return nil end
    local check = _G.issecretvalue
    if type(check) == "function" then
        local ok, secret = pcall(check, value)
        if not ok or secret then return nil end
    end
    return value
end
local Readable = VMH.Readable

local function pack(...) return { n = select("#", ...), ... } end

-- Calls fn safely; any error or secret return value becomes nil.
function VMH.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = pack(pcall(fn, ...))
    if not r[1] then return nil end
    for i = 2, r.n do r[i] = Readable(r[i]) end
    return unpack(r, 2, r.n)
end
local Safe = VMH.Safe

function VMH.Number(value)
    value = Readable(value)
    if type(value) == "number" then return value end
    return nil
end

function VMH.Now()
    return GetTime and GetTime() or 0
end

-- Timers: every callback is protected so a bad value can never raise a Lua error popup.
function VMH.After(sec, fn)
    local function run()
        local ok, err = pcall(fn)
        if not ok then VMH:Debug("timer error: " .. tostring(err)) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(math.max(0, sec or 0), run) else run() end
end

-- Forever characters carry a first name and a surname. Identity always uses both.
function VMH.UnitFullName(unit)
    local name, second = Safe(_G.UnitName, unit)
    if type(name) ~= "string" or name == "" then return nil end
    if type(second) == "string" and second ~= "" then return name .. " " .. second end
    return name
end

function VMH.PlayerClass()
    local _, token = Safe(_G.UnitClass, "player")
    return token
end

------------------------------------------------------------------------
-- Output (always local)
------------------------------------------------------------------------
local PREFIX = "|cff9d5cffVoidMark Healer|r: "
function VMH:Print(msg)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then frame:AddMessage(PREFIX .. tostring(msg)) end
end

-- The trail is saved with your settings, so it survives /reload and logout
-- (see /vmh debug log). Kept short: last 150 lines.
function VMH:Debug(msg)
    local stamp = (type(date) == "function" and date("%H:%M:%S")) or string.format("%.1f", VMH.Now())
    local line = stamp .. " " .. tostring(msg)
    local log = self.debugLog
    log[#log + 1] = line
    while #log > 150 do table.remove(log, 1) end
    if self.debugMode then
        local frame = _G.DEFAULT_CHAT_FRAME
        if frame and frame.AddMessage then frame:AddMessage("|cff777777[VMH debug]|r " .. tostring(msg)) end
    end
end

------------------------------------------------------------------------
-- Events: one frame, many handlers. Handlers are protected so one module
-- failing cannot stop the others.
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
VMH.eventFrame = eventFrame
local handlers = {}

local function dispatch(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then VMH:Debug("error in " .. event .. ": " .. tostring(err)) end
    end
end
eventFrame:SetScript("OnEvent", dispatch)

function VMH:On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    list[#list + 1] = fn
end

-- Unit events get their own frame so RegisterUnitEvent filtering works.
local unitFrames = {}
function VMH:OnUnit(event, unit, fn)
    local key = event .. ":" .. unit
    local f = unitFrames[key]
    if not f then
        f = CreateFrame("Frame")
        f.list = {}
        local ok = false
        if f.RegisterUnitEvent then ok = pcall(f.RegisterUnitEvent, f, event, unit) end
        if not ok then
            pcall(f.RegisterEvent, f, event)
            f.filter = unit
        end
        f:SetScript("OnEvent", function(_, ev, u, ...)
            if f.filter and u ~= f.filter then return end
            for i = 1, #f.list do
                local okc, err = pcall(f.list[i], ev, u, ...)
                if not okc then VMH:Debug("error in " .. ev .. ": " .. tostring(err)) end
            end
        end)
        unitFrames[key] = f
    end
    f.list[#f.list + 1] = fn
end

-- Fire handlers directly (used by tests and simulations).
function VMH:Fire(event, ...) dispatch(nil, event, ...) end

------------------------------------------------------------------------
-- Coalesced player aura scanning: UNIT_AURA can fire many times per frame;
-- subscribers run once on the next frame.
------------------------------------------------------------------------
local auraSubscribers = {}
local auraPending = false
function VMH:OnPlayerAura(fn) auraSubscribers[#auraSubscribers + 1] = fn end

function VMH:RunAuraScan()
    auraPending = false
    for i = 1, #auraSubscribers do
        local ok, err = pcall(auraSubscribers[i])
        if not ok then VMH:Debug("aura scan error: " .. tostring(err)) end
    end
end

function VMH:QueueAuraScan()
    if auraPending then return end
    auraPending = true
    VMH.After(0, function() VMH:RunAuraScan() end)
end

function VMH.AurasHidden()
    if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok then return true end
        return Readable(secret) == true
    end
    return false
end

-- Reads one aura as a plain table with only readable fields.
function VMH.GetAura(unit, index, filter)
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if not ok or a == nil then return nil end
        if Readable(a) == nil or type(a) ~= "table" then return {}, true end
        return {
            name = Readable(a.name), icon = Readable(a.icon), spellId = Readable(a.spellId),
            duration = Readable(a.duration), expirationTime = Readable(a.expirationTime),
            sourceUnit = Readable(a.sourceUnit), auraInstanceID = Readable(a.auraInstanceID),
            dispelName = Readable(a.dispelName),
        }, true
    end
    local fn = (filter == "HARMFUL") and _G.UnitDebuff or _G.UnitBuff
    if type(fn) ~= "function" then return nil end
    local name, icon, _, dispel, duration, expiration, source, _, _, spellId = Safe(fn, unit, index)
    if name == nil and spellId == nil then
        -- distinguish "end of list" from "hidden": a hidden entry still has a raw return
        local ok, raw = pcall(fn, unit, index)
        if ok and raw ~= nil then return {}, true end
        return nil
    end
    return { name = name, icon = icon, spellId = spellId, duration = duration,
        expirationTime = expiration, sourceUnit = source, dispelName = dispel }, true
end

------------------------------------------------------------------------
-- Context
------------------------------------------------------------------------
function VMH:GetContext()
    local inInstance, instanceType = Safe(_G.IsInInstance)
    instanceType = instanceType or "none"
    local grouped = Safe(_G.IsInGroup) == true
    local raid = Safe(_G.IsInRaid) == true
    local pvp = instanceType == "pvp" or instanceType == "arena"
    if not pvp and not inInstance then
        -- world PvP: flagged and fighting players counts as PvP context
        pvp = (self.Threat and self.Threat.playerAttackers or 0) > 0
    end
    return { inInstance = inInstance == true, instanceType = instanceType, grouped = grouped, raid = raid, pvp = pvp }
end

local HEAL_CLASSES = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true }
function VMH:IsHealerActive()
    local mode = self.db and self.db.general.healerOnly or "class"
    if mode == "always" then return true end
    local role = Safe(_G.UnitGroupRolesAssigned, "player")
    if role == "HEALER" then return true end
    if mode == "role" then return false end
    if role == "DAMAGER" or role == "TANK" then return false end
    local class = VMH.PlayerClass() or ""
    if not HEAL_CLASSES[class] then return false end
    -- A priest in Shadowform is not healing; stay quiet unless set to "always".
    if class == "PRIEST" and VMH.HasPlayerBuff(15473) then return false end
    return true
end

function VMH.HasPlayerBuff(spellID)
    if VMH.AurasHidden() then return false end
    for i = 1, 40 do
        local a = VMH.GetAura("player", i, "HELPFUL")
        if not a then return false end
        if a.spellId == spellID then return true end
    end
    return false
end

function VMH:IsEnabled()
    return self.db ~= nil and self.db.general.enabled == true
end

-- Account-wide "Run in" setting:
--   dungeonraid = dungeons, raids and scenarios only (default)
--   instances   = also battlegrounds and arenas
--   everywhere  = open world too
-- Outside the chosen places nothing is detected, shown, announced or counted.
-- Simulations and Test buttons still work so setup can be checked anywhere.
VMH.RUN_IN = {
    { value = "dungeonraid", label = "Dungeons and raids only" },
    { value = "instances", label = "Dungeons, raids, battlegrounds, arenas" },
    { value = "everywhere", label = "Everywhere (open world too)" },
}
function VMH:IsActiveHere()
    local mode = (self.sv and self.sv.runIn) or "dungeonraid"
    if mode == "everywhere" then return true end
    local inInstance, itype = VMH.Safe(_G.IsInInstance)
    if not inInstance then return false end
    if itype == "party" or itype == "raid" or itype == "scenario" then return true end
    if mode == "instances" and (itype == "pvp" or itype == "arena") then return true end
    return false
end

------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------
function VMH:NewModule(name)
    local m = { name = name }
    self[name] = m
    self.modules[#self.modules + 1] = m
    return m
end

local function each(method, ...)
    for _, m in ipairs(VMH.modules) do
        if type(m[method]) == "function" then
            local ok, err = pcall(m[method], m, ...)
            if not ok then VMH:Debug(m.name .. ":" .. method .. " failed: " .. tostring(err)) end
        end
    end
end
VMH.EachModule = each

-- Called after a profile change so modules re-read settings.
function VMH:ApplySettings()
    each("OnSettingsChanged")
end

VMH:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    VMH.session.started = VMH.Now()
    VMH.Profiles:Load()
    each("Init")
    VMH.loaded = true
end)

VMH:On("PLAYER_ENTERING_WORLD", function()
    if not VMH.loaded then return end
    if not VMH.sv.welcomed then
        VMH.sv.welcomed = true
        VMH:Print("loaded. Type /vmh for settings, /vmh preview to place the crowd-control display.")
    end
    VMH.Profiles:AutoSwitch()
    each("OnEnterWorld")
    VMH:QueueAuraScan()
end)

VMH:On("ZONE_CHANGED_NEW_AREA", function()
    if VMH.loaded then VMH.Profiles:AutoSwitch() end
end)

VMH:On("GROUP_ROSTER_UPDATE", function()
    if VMH.loaded then VMH.Profiles:AutoSwitch() end
end)
