-- VoidMark Healer - aggro, threat and enemy focus
-- Threat status comes from the threat API when readable. Enemies attacking
-- the healer are counted from visible enemy units (nameplates, target, focus,
-- arena) whose target is the player - enemy nameplates must be on to see
-- more than your target/focus.
local _, VMH = ...
local T = VMH:NewModule("Threat")

T.attackers = 0
T.playerAttackers = 0
T.aggro = false
T.threatHigh = false
T.multi = false
T.pending = false
T.calmSince = nil

local EXTRA_UNITS = { "target", "focus", "arena1", "arena2", "arena3", "arena4", "arena5", "boss1", "boss2", "boss3", "boss4", "boss5" }

local function hostileOnMe(unit)
    if VMH.Safe(_G.UnitExists, unit) ~= true then return false end
    if VMH.Safe(_G.UnitCanAttack, "player", unit) ~= true then return false end
    if VMH.Safe(_G.UnitIsDeadOrGhost, unit) == true then return false end
    return VMH.Safe(_G.UnitIsUnit, unit .. "target", "player") == true
end

function T:Count()
    local seen, count, players, firstNpc = {}, 0, 0, nil
    local function consider(unit)
        if not hostileOnMe(unit) then return end
        local guid = VMH.Safe(_G.UnitGUID, unit)
        if guid then
            if seen[guid] then return end
            seen[guid] = true
        else
            -- without a readable GUID only count nameplates (each is a distinct unit)
            if not unit:find("^nameplate") then return end
        end
        count = count + 1
        if VMH.Safe(_G.UnitIsPlayer, unit) == true then players = players + 1
        elseif not firstNpc then firstNpc = VMH.UnitFullName(unit) end
    end
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        local plates = VMH.Safe(C_NamePlate.GetNamePlates)
        if type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local token = VMH.Readable(plate.namePlateUnitToken) or (plate.UnitFrame and VMH.Readable(plate.UnitFrame.unit))
                if type(token) == "string" then consider(token) end
            end
        end
    end
    for _, u in ipairs(EXTRA_UNITS) do consider(u) end
    return count, players, firstNpc
end

local function threatStatus()
    return VMH.Number(VMH.Safe(_G.UnitThreatSituation, "player"))
end

local function threatPercent()
    for _, unit in ipairs({ "target", "focus", "boss1" }) do
        if VMH.Safe(_G.UnitCanAttack, "player", unit) == true then
            local isTanking, _, scaled = VMH.Safe(_G.UnitDetailedThreatSituation, "player", unit)
            scaled = VMH.Number(scaled)
            if scaled then return scaled, isTanking == true end
        end
    end
    return nil
end

function T:Evaluate()
    self.pending = false
    if not VMH.loaded then return end
    local now = VMH.Now()
    local count, players, npcName = self:Count()
    self.attackers, self.playerAttackers = count, players
    local a = VMH.db.alerts
    local inCombat = VMH.Safe(_G.UnitAffectingCombat, "player") == true

    -- Aggro (PvE): threat API first, visible NPC targeting as fallback.
    local status = threatStatus()
    local hasAggro
    if status then hasAggro = status >= 2 else hasAggro = inCombat and (count - players) > 0 end
    if hasAggro then
        self.calmSince = nil
        if not self.aggro then
            self.aggro = true
            VMH.Announce:Alert("aggro", { name = npcName })
        end
    elseif self.aggro then
        self.calmSince = self.calmSince or now
        if now - self.calmSince >= 3 then self.aggro = false; self.calmSince = nil end
    end

    -- Excessive threat (not tanking yet, but close to pulling).
    local pct, tanking = threatPercent()
    if pct and not tanking then
        local thr = a.threat.threshold
        if pct >= thr and not self.threatHigh then
            self.threatHigh = true
            VMH.Announce:Alert("threat", { pct = math.floor(pct) })
        elseif pct < thr - (VMH.db.announce.hysteresis or 10) then
            self.threatHigh = false
        end
    elseif not pct and status == 1 and not self.threatHigh then
        self.threatHigh = true
        VMH.Announce:Alert("threat", {})
    elseif status == 0 then
        self.threatHigh = false
    end

    -- Several enemies on the healer.
    local need = a.multiEnemy.threshold or 2
    if count >= need then
        if not self.multi then
            self.multi = true
            VMH.Announce:Alert("multiEnemy", { count = count })
        end
    elseif self.multi then
        self.multi = false
    end

    if self.aggro and not hasAggro then self:Queue(1) end
end

function T:Queue(delay)
    if self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then C_Timer.After(delay or 0.3, function() T:Evaluate() end) else self:Evaluate() end
end

local function watchedUnit(unit)
    return type(unit) == "string" and (unit:find("^nameplate") or unit == "target" or unit == "focus" or unit:find("^arena") or unit:find("^boss"))
end

function T:Init()
    VMH:On("NAME_PLATE_UNIT_ADDED", function() T:Queue() end)
    VMH:On("NAME_PLATE_UNIT_REMOVED", function() T:Queue() end)
    VMH:On("PLAYER_TARGET_CHANGED", function() T:Queue() end)
    VMH:On("PLAYER_REGEN_DISABLED", function() T:Queue() end)
    VMH:On("PLAYER_REGEN_ENABLED", function() T:Queue() end)
    VMH:On("UNIT_TARGET", function(_, unit) if watchedUnit(unit) then T:Queue() end end)
    VMH:On("UNIT_THREAT_SITUATION_UPDATE", function() T:Queue() end)
    VMH:On("UNIT_THREAT_LIST_UPDATE", function() T:Queue() end)
end

function T:OnEnterWorld()
    self.aggro, self.threatHigh, self.multi = false, false, false
    self:Queue()
end
