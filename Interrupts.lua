-- VoidMark Healer - interrupts and cast failures
-- Forever has no combat log, so:
--  * Interrupt lockouts come from Loss of Control data (CrowdControl.lua).
--  * If that data is missing or hidden, an interrupted cast is probed: a real
--    lockout puts the spell on a cooldown longer than its own. Only that proven
--    lockout is reported, with the real remaining time.
--  * The interrupter is named when a visible enemy (target, focus, nameplate,
--    arena) casts a known interrupt at the player just before the lockout.
--  * Line-of-sight failures come from the client's error messages.
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
    VMH.After(0.15, check)
end

------------------------------------------------------------------------
-- Line of sight
-- The error message alone doesn't say which spell failed, so a damage spell
-- (Mind Blast out of sight) must not count as "can't heal". The failed spell
-- is taken from UNIT_SPELLCAST_FAILED / _SENT when the game reports it; with
-- no spell to check, the alert needs a friendly mouseover or friendly target
-- and no hostile target.
------------------------------------------------------------------------
I.lastSpell = nil

local function isHelpful(spellID)
    if not spellID then return nil end
    if C_Spell and type(C_Spell.IsSpellHelpful) == "function" then
        local v = VMH.Safe(C_Spell.IsSpellHelpful, spellID)
        if v ~= nil then return v == true end
    end
    if C_Spell and type(C_Spell.IsSpellHarmful) == "function" then
        local v = VMH.Safe(C_Spell.IsSpellHarmful, spellID)
        if v ~= nil then return v ~= true end
    end
    local name = D.SpellName(spellID)
    if name and type(_G.IsHelpfulSpell) == "function" then
        local v = VMH.Safe(_G.IsHelpfulSpell, name)
        if v ~= nil then return v == true or v == 1 end
    end
    return nil
end
I.IsHelpful = isHelpful

local function friendly(unit)
    return VMH.Safe(_G.UnitExists, unit) == true and VMH.Safe(_G.UnitIsFriend, "player", unit) == true
end

-- Returns display name, whether a friendly heal target was found, and the
-- name to whisper (players only, never yourself).
local function healTargetName()
    for _, unit in ipairs({ "mouseover", "target" }) do
        if friendly(unit) then
            local whisper
            if VMH.Safe(_G.UnitIsPlayer, unit) == true and VMH.Safe(_G.UnitIsUnit, unit, "player") ~= true then
                whisper = VMH.Safe(_G.GetUnitName, unit, true)
                if type(whisper) ~= "string" or whisper == "" then whisper = (VMH.Safe(_G.UnitName, unit)) end
            end
            return VMH.UnitFullName(unit), true, whisper, unit
        end
    end
    return nil, false, nil, nil
end

-- Health of the player you were healing, or nil when the game hides it.
local function healthPercent(unit)
    if not unit then return nil end
    local cur = VMH.Number(VMH.Safe(_G.UnitHealth, unit))
    local max = VMH.Number(VMH.Safe(_G.UnitHealthMax, unit))
    if not cur or not max or max <= 0 then return nil end
    return cur / max * 100
end
I.HealthPercent = healthPercent
I.lastByPlayer = {}

function I:NoteSpell(spellID)
    spellID = VMH.Number(spellID)
    if spellID then self.lastSpell = { id = spellID, time = VMH.Now() } end
end

function I:OnUIError(a, b)
    local message = type(a) == "string" and a or b
    message = VMH.Readable(message)
    if type(message) ~= "string" then return end
    local key
    if message == _G.SPELL_FAILED_LINE_OF_SIGHT then key = "los" end
    if not key then return end
    local at = VMH.Now()
    -- Only worth saying in a fight, for someone who actually needs the heal.
    if VMH.Safe(_G.UnitAffectingCombat, "player") ~= true then return end
    -- the failed-cast event can arrive just after the error text
    VMH.After(0.1, function()
        local name, hasFriend, whisperTo, unit = healTargetName()
        local r = I.lastSpell
        local helpful = nil
        if r and math.abs(at - r.time) <= 0.5 then helpful = isHelpful(r.id) end
        if helpful == false then return end
        if helpful == nil then
            if not hasFriend then return end
            if not friendly("mouseover") and VMH.Safe(_G.UnitCanAttack, "player", "target") == true then return end
        end
        local cfg = VMH.db.alerts[key]
        local hp = healthPercent(unit)
        local limit = cfg.threshold or 50
        if not hp or hp >= limit then
            VMH:Debug("los not announced: " .. tostring(name) .. " health " ..
                (hp and string.format("%d%%", hp) or "hidden") .. " (limit " .. limit .. "%)")
            return
        end
        -- cooldown per player, so two different players out of sight both hear about it
        local who = key .. ":" .. tostring(name)
        local last = I.lastByPlayer[who]
        local t = VMH.Now()
        if last and t - last < (cfg.cooldown or 0) then return end
        I.lastByPlayer[who] = t
        VMH.Announce:Alert(key, { name = name, whisperTo = whisperTo }, { ignoreCooldown = true, dedupe = who })
    end)
end

function I:Init()
    VMH:On("UNIT_SPELLCAST_SUCCEEDED", onEnemyCast)
    VMH:OnUnit("UNIT_SPELLCAST_INTERRUPTED", "player", function(_, _, _, spellID) I:OnPlayerInterrupted(spellID) end)
    VMH:On("UI_ERROR_MESSAGE", function(_, a, b) I:OnUIError(a, b) end)
    VMH:OnUnit("UNIT_SPELLCAST_FAILED", "player", function(_, _, _, spellID) I:NoteSpell(spellID) end)
    VMH:OnUnit("UNIT_SPELLCAST_SENT", "player", function(_, _, _, _, spellID) I:NoteSpell(spellID) end)
end
