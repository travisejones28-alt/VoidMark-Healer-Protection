-- Minimal WoW Forever client mock for offline regression tests.
-- Secret values: SECRET is reported by issecretvalue(); any comparison or
-- concatenation of it raises an error, just like the real client.
SECRET = setmetatable({}, {
    __eq = function() error("compared a secret value") end,
    __lt = function() error("compared a secret value") end,
    __le = function() error("compared a secret value") end,
    __concat = function() error("concatenated a secret value") end,
    __tostring = function() error("stringified a secret value") end,
    __index = function() error("indexed a secret value") end,
})
function issecretvalue(v) return rawequal(v, SECRET) end
unpack = unpack or table.unpack

NOW = 1000
function GetTime() return NOW end
function GetBuildInfo() return "1.60.1", "69913", "", 16001 end
function GetRealmName() return "Forever" end
function GetLocale() return "enUS" end

---------------------------------------------------------------- state
S = {}
function ResetState()
    S = {
        class = "PRIEST", role = "NONE",
        hp = 5000, hpMax = 5000, mana = 5000, manaMax = 5000, powerType = 0,
        dead = false, inCombat = false,
        instance = false, instanceType = "none",
        homeGroup = true, instanceGroup = false, raid = false,
        loc = {}, locSecret = false,
        auras = { HARMFUL = {}, HELPFUL = {} }, aurasHidden = false,
        units = {}, plates = {}, threat = 0,
        chat = {}, prints = {}, warnings = {}, sounds = {},
        chatLocked = false,
        cooldowns = {}, baseCooldown = {}, usable = {},
        spellbook = {}, costs = {},
        soulstone = nil,
    }
end
ResetState()

---------------------------------------------------------------- frames
FRAMES = {}
local function obj(kind, name)
    local o = { kind = kind, name = name, shown = (kind ~= "Frame" and kind ~= "Button" and kind ~= "ScrollFrame"),
        scripts = {}, events = {}, unitEvents = {}, points = {}, w = 100, h = 20, text = "", value = 0,
        min = 0, max = 1, children = {} }
    if kind == "Texture" or kind == "FontString" then o.shown = true end
    if kind ~= "Texture" and kind ~= "FontString" then o.shown = true end
    return setmetatable(o, { __index = function(self, k)
        local m = FrameMethods[k]
        if m then return m end
        -- unknown Capitalized keys behave like harmless widget methods
        if type(k) == "string" and k:match("^%u") then return function() return nil end end
        return nil
    end })
end
FrameMethods = {
    SetScript = function(s, k, fn) s.scripts[k] = fn end,
    GetScript = function(s, k) return s.scripts[k] end,
    HookScript = function(s, k, fn)
        local old = s.scripts[k]
        s.scripts[k] = function(...) if old then old(...) end fn(...) end
    end,
    RegisterEvent = function(s, e) s.events[e] = true end,
    RegisterUnitEvent = function(s, e, u) s.unitEvents[e] = u end,
    UnregisterEvent = function(s, e) s.events[e] = nil end,
    Show = function(s) s.shown = true; if s.scripts.OnShow then s.scripts.OnShow(s) end end,
    Hide = function(s) local was = s.shown; s.shown = false; if was and s.scripts.OnHide then s.scripts.OnHide(s) end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) return s.shown end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end,
    SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end,
    GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
    ClearAllPoints = function(s) s.points = {} end,
    GetPoint = function(s) local p = s.points[1] or { "CENTER" }; return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end,
    SetText = function(s, t) s.text = t end,
    GetText = function(s) return s.text end,
    SetFont = function(s, f) s.font = f; return true end,
    GetFont = function(s) return s.font end,
    CreateTexture = function(s) local t = obj("Texture"); s.children[#s.children + 1] = t; return t end,
    CreateFontString = function(s) local t = obj("FontString"); s.children[#s.children + 1] = t; return t end,
    SetMinMaxValues = function(s, a, b) s.min, s.max = a, b end,
    GetMinMaxValues = function(s) return s.min, s.max end,
    SetValue = function(s, v)
        if v < s.min then v = s.min elseif v > s.max then v = s.max end
        local changed = v ~= s.value
        s.value = v
        if changed and s.scripts.OnValueChanged then s.scripts.OnValueChanged(s, v) end
    end,
    GetValue = function(s) return s.value end,
    GetVerticalScroll = function(s) return s.vscroll or 0 end,
    SetVerticalScroll = function(s, v) s.vscroll = v end,
    Click = function(s, ...) if s.scripts.OnClick then s.scripts.OnClick(s, ...) end end,
    GetName = function(s) return s.name end,
    GetParent = function(s) return s.parent end,
}
function CreateFrame(kind, name, parent)
    local f = obj(kind, name)
    f.parent = parent
    FRAMES[#FRAMES + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame("Frame", "UIParent")
WorldFrame = CreateFrame("Frame", "WorldFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) S.prints[#S.prints + 1] = m end }
-- Blizzard-owned UI objects: the addon must never touch these (taint safety).
local function forbidden(name)
    return setmetatable({}, {
        __index = function(_, k) error("TAINT: addon touched " .. name .. "." .. tostring(k)) end,
        __newindex = function(_, k) error("TAINT: addon wrote " .. name .. "." .. tostring(k)) end,
    })
end
RaidWarningFrame = forbidden("RaidWarningFrame")
function RaidNotice_AddMessage() error("TAINT: addon called RaidNotice_AddMessage") end
UISpecialFrames = forbidden("UISpecialFrames")
SlashCmdList = {}
GameTooltip = forbidden("GameTooltip")
GameFontNormal, GameFontHighlight, ChatFontNormal = {}, {}, {}
ColorPickerFrame = forbidden("ColorPickerFrame")
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight"
SPELL_FAILED_OUT_OF_RANGE = "Out of range"
ERR_SPELL_OUT_OF_RANGE = "Out of range."
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
Enum = { PowerType = { Mana = 0 } }

---------------------------------------------------------------- timers
TIMERS = {}
C_Timer = { After = function(sec, fn) TIMERS[#TIMERS + 1] = { at = NOW + sec, fn = fn } end }
function RunTimers()
    local guard = 0
    while true do
        guard = guard + 1
        assert(guard < 10000, "timer loop")
        local idx, best
        for i, t in ipairs(TIMERS) do
            if t.at <= NOW and (not best or t.at < best.at) then idx, best = i, t end
        end
        if not idx then break end
        table.remove(TIMERS, idx)
        best.fn()
    end
end
function Advance(sec, step)
    step = step or 0.05
    local target = NOW + sec
    while NOW < target - 1e-9 do
        local dt = math.min(step, target - NOW)
        NOW = NOW + dt
        RunTimers()
        for _, f in ipairs(FRAMES) do
            if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
        end
    end
    RunTimers()
end

---------------------------------------------------------------- events
function Emit(event, ...)
    for _, f in ipairs(FRAMES) do
        local handler = f.scripts.OnEvent
        if handler then
            if f.events[event] then handler(f, event, ...)
            elseif f.unitEvents[event] and f.unitEvents[event] == (select(1, ...)) then handler(f, event, ...) end
        end
    end
end

---------------------------------------------------------------- API
local function maybe(v) return v end
function UnitName(u)
    if u == "player" then return "Voidmark", "Soulreaver" end
    local d = S.units[u]
    if d then return d.name, d.surname end
end
function GetUnitName(u, showServer)
    local d = S.units[u]
    if not d then return nil end
    return d.name .. ((showServer and d.surname) and ("-" .. d.surname) or "")
end
function UnitClass(u) if u == "player" then return "Priest", S.class end end
function UnitGroupRolesAssigned() return S.role end
function UnitHealth(u)
    if u and u ~= "player" then local d = S.units[u]; if d and d.hpSecret then return SECRET end return d and (d.hp or 100) or nil end
    return S.hpSecret and SECRET or S.hp
end
function UnitHealthMax(u)
    if u and u ~= "player" then local d = S.units[u]; if d and d.hpSecret then return SECRET end return d and 100 or nil end
    return S.hpSecret and SECRET or S.hpMax
end
function UnitPower() return S.manaSecret and SECRET or S.mana end
function UnitPowerMax() return S.manaSecret and SECRET or S.manaMax end
function UnitPowerType() return S.powerType, "MANA" end
function UnitIsDeadOrGhost(u) if u == "player" then return S.dead end local d = S.units[u]; return d and d.dead or false end
function UnitAffectingCombat() return S.inCombat end
function InCombatLockdown() return S.inCombat end
function IsInInstance() return S.instance, S.instanceType end
function IsInGroup(cat)
    if cat == LE_PARTY_CATEGORY_INSTANCE then return S.instanceGroup end
    if cat == LE_PARTY_CATEGORY_HOME then return S.homeGroup end
    return S.homeGroup or S.instanceGroup
end
function IsInRaid() return S.raid end
function HasSoulstone() return S.soulstone end
function UnitExists(u) return S.units[u] ~= nil or u == "player" end
function UnitGUID(u) local d = S.units[u]; return d and d.guid end
function UnitClassification(u) local d = S.units[u]; if not d then return nil end if d.classSecret then return SECRET end return d.class or "normal" end
function UnitIsPlayer(u) local d = S.units[u]; return d and d.isPlayer or false end
function UnitCanAttack(_, u) local d = S.units[u]; return d and d.hostile or false end
function UnitIsFriend(_, u) local d = S.units[u]; return d and not d.hostile or false end
function UnitIsUnit(a, b)
    if b == "player" then
        local base = a:match("^(.-)target$")
        if base then local d = S.units[base]; return d and d.targetsPlayer or false end
        return a == "player"
    end
    return a == b
end
function UnitThreatSituation() return S.threat end
function UnitDetailedThreatSituation() return nil end
C_NamePlate = { GetNamePlates = function()
    local out = {}
    for _, t in ipairs(S.plates) do out[#out + 1] = { namePlateUnitToken = t } end
    return out
end }
TIP_CALLS = 0
C_TooltipInfo = { GetUnitDebuff = function(unit, i)
    TIP_CALLS = TIP_CALLS + 1
    local a = S.auras.HARMFUL[i]
    if not a or not a.tip then return nil end
    if S.tipSecret then return { lines = { { leftText = SECRET }, { leftText = SECRET } } } end
    return { lines = { { leftText = a.name }, { leftText = a.tip } } }
end }
C_Secrets = { ShouldAurasBeSecret = function() return S.aurasHidden end }
C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
    if unit ~= "player" then return nil end
    local a = S.auras[filter][i]
    if not a then return nil end
    return a
end }
C_LossOfControl = {
    GetActiveLossOfControlDataCount = function() if S.locSecret then return SECRET end return #S.loc end,
    GetActiveLossOfControlData = function(i)
        local d = S.loc[i]
        if not d then return nil end
        local r = {}
        for k, v in pairs(d) do r[k] = v end
        if d.startTime and d.duration and d.duration ~= SECRET then r.timeRemaining = math.max(0, d.startTime + d.duration - NOW) end
        return r
    end,
}
C_ChatInfo = {
    SendChatMessage = function(msg, chatType, _, target)
        assert(chatType ~= "GUILD" and chatType ~= "CHANNEL" and chatType ~= "OFFICER", "forbidden channel " .. tostring(chatType))
        if (chatType == "SAY" or chatType == "YELL") and not S.instance then error("ADDON_ACTION_BLOCKED say outside instance") end
        if chatType == "WHISPER" then assert(type(target) == "string" and target ~= "", "whisper without target") end
        S.chat[#S.chat + 1] = { msg = msg, type = chatType, target = target, t = NOW }
    end,
    InChatMessagingLockdown = function() return S.chatLocked end,
}
function SendChatMessage() error("legacy SendChatMessage should not be used when C_ChatInfo exists") end
function PlaySound(id) S.sounds[#S.sounds + 1] = id end
local NAMES = { [15487] = "Silence", [408] = "Kidney Shot", [118] = "Polymorph", [1766] = "Kick", [8122] = "Psychic Scream",
    [122] = "Frost Nova", [853] = "Hammer of Justice", [430] = "Drink", [431] = "Drink", [2061] = "Flash Heal",
    [2050] = "Lesser Heal", [2060] = "Greater Heal", [1776] = "Gouge" }
C_Spell = {
    GetSpellName = function(id) return NAMES[id] end,
    GetSpellTexture = function(id) return 100000 + id end,
    GetSpellCooldown = function(id)
        local c = S.cooldowns[id]
        if not c then return { startTime = 0, duration = 0, isEnabled = true } end
        return { startTime = c[1], duration = c[2], isEnabled = true }
    end,
    GetSpellPowerCost = function(id) local c = S.costs[id]; if c then return { { type = 0, cost = c } } end return {} end,
    IsSpellHelpful = function(id) return id == 2061 or id == 2050 or id == 2060 end,
    IsSpellUsable = function(id)
        local u = S.usable[id]
        if u == nil then return true, false end
        return u.usable, u.noMana
    end,
}
function GetSpellBaseCooldown(id) return (S.baseCooldown[id] or 0) * 1000, 1500 end
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", nil, 0, #S.spellbook end
function GetSpellBookItemInfo(slot) local id = S.spellbook[slot]; if id then return "SPELL", id end end
