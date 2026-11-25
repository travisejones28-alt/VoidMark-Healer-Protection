-- VoidMark Healer - interrupts and cast failures
-- Forever has no combat log, so:
--  * Interrupt lockouts come from Loss of Control data (CrowdControl.lua).
--  * If that data is missing or hidden, an interrupted cast is probed: a real
--    lockout puts the spell on a cooldown longer than its own. Only that proven
--    lockout is reported, with the real remaining time.
--  * The interrupter is named when a visible enemy (target, focus, nameplate,
--    arena) casts a known interrupt at the player just before the lockout.
--  * Line-of-sight and range failures come from the client's error messages.
local _, VMH = ...
local I = VMH:NewModule("Interrupts")
local D = VMH.SpellData

I.recent = nil

local WATCH_PREFIX = { "nameplate", "target", "focus", "arena", "boss", "mouseover" }
local function watched(unit)
    if type(unit) ~= "string" then return false end
    for _, p in ipairs(WATCH_PREFIX) do
        if unit:sub(1, #p) == p then return true end
    end
    return false
end

function I:RecentInterrupter()
    local r = self.recent
    if r and VMH.Now() - r.time <= 1.5 then return r.name end
    return nil
end

local function onEnemyCast(_, unit, _, spellID)
    if not watched(unit) then return end
    spellID = VMH.Number(spellID)
    if not spellID or not D.INTERRUPTS[spellID] then return end
    if VMH.Safe(_G.UnitIsUnit, unit .. "target", "player") ~= true then return end
    if VMH.Safe(_G.UnitCanAttack, "player", unit) ~= true then return end
    I.recent = { name = VMH.UnitFullName(unit), spellID = spellID, time = VMH.Now() }
    VMH:Debug("interrupt cast at player by " .. tostring(I.recent.name))
end

local function schoolFor(spellID)
    local class = VMH.PlayerClass()
    if class == "PRIEST" then return D.SHADOW_SPELLS[spellID] and 32 or 2 end
    return D.HEAL_SCHOOL[class or ""]
end

local function cooldown(spellID)
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local info = VMH.Safe(C_Spell.GetSpellCooldown, spellID)
        if type(info) ~= "table" then return nil end
        return VMH.Number(info.startTime), VMH.Number(info.duration)
    end
    local start, duration = VMH.Safe(_G.GetSpellCooldown, spellID)
    return VMH.Number(start), VMH.Number(duration)
end

local function baseCooldown(spellID)
    local ms = VMH.Number(VMH.Safe(_G.GetSpellBaseCooldown, spellID))
    return ms and (ms / 1000) or 0
end

-- Returns lockout expiry if the interrupted spell is locked beyond its own cooldown.
function I:ProbeLockout(spellID)
    local start, duration = cooldown(spellID)
    if not start or not duration or start <= 0 or duration <= 1.6 then return nil end
    if duration <= baseCooldown(spellID) + 1 then return nil end
    local expires = start + duration
    if expires - VMH.Now() <= 0.2 then return nil end
    return expires, duration
end

function I:OnPlayerInterrupted(spellID)
    spellID = VMH.Number(spellID)
    if not spellID then return end
    local at = VMH.Now()
    local function check()
        -- Loss of Control already reported a lockout: nothing to add.
        for _, e in pairs(VMH.CrowdControl.active) do
            if e.type == "LOCKOUT" and e.via ~= "cooldown" and (e.addedAt or 0) >= at - 1 then return end
        end
        local expires, duration = I:ProbeLockout(spellID)
        if not expires then return end
        local school = schoolFor(spellID)
        local r = I.recent
        local name = (r and at - r.time <= 1.5 and D.SpellName(r.spellID)) or "Interrupted"
        VMH.CrowdControl:AddExternal({ key = "lock:" .. tostring(school or 0), type = "LOCKOUT", name = name,
            school = school, expires = expires, duration = duration, source = I:RecentInterrupter(), via = "cooldown" })
        VMH:Debug("lockout proven by cooldown probe: " .. string.format("%.1fs", expires - VMH.Now()))
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, check) else check() end
end

------------------------------------------------------------------------
-- Line of sight / range
------------------------------------------------------------------------
local function healTargetName()
    for _, unit in ipairs({ "mouseover", "target" }) do
        if VMH.Safe(_G.UnitExists, unit) == true and VMH.Safe(_G.UnitIsFriend, "player", unit) == true then
            return VMH.UnitFullName(unit)
        end
    end
    return nil
end

function I:OnUIError(a, b)
    local message = type(a) == "string" and a or b
    message = VMH.Readable(message)
    if type(message) ~= "string" then return end
    if message == _G.SPELL_FAILED_LINE_OF_SIGHT then
        VMH.Announce:Alert("los", { name = healTargetName() })
    elseif message == _G.SPELL_FAILED_OUT_OF_RANGE or message == _G.ERR_SPELL_OUT_OF_RANGE or message == _G.ERR_OUT_OF_RANGE then
        VMH.Announce:Alert("range", { name = healTargetName() })
    end
end

function I:Init()
    VMH:On("UNIT_SPELLCAST_SUCCEEDED", onEnemyCast)
    VMH:OnUnit("UNIT_SPELLCAST_INTERRUPTED", "player", function(_, _, _, spellID) I:OnPlayerInterrupted(spellID) end)
    VMH:On("UI_ERROR_MESSAGE", function(_, a, b) I:OnUIError(a, b) end)
end
