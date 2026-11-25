-- VoidMark Healer - health, death and resurrection
-- Health alerts need a readable health value. When Forever hides health in
-- combat, these two alerts pause (nothing is guessed); death and resurrection
-- alerts come from events and always work.
local _, VMH = ...
local Hm = VMH:NewModule("Health")

Hm.state = "ok"     -- ok | low | critical
Hm.dead = false
Hm.pending = false

function Hm:Percent()
    local cur = VMH.Number(VMH.Safe(_G.UnitHealth, "player"))
    local max = VMH.Number(VMH.Safe(_G.UnitHealthMax, "player"))
    if not cur or not max or max <= 0 then return nil end
    return math.floor(cur / max * 100 + 0.5)
end

function Hm:Evaluate()
    self.pending = false
    if not VMH.loaded then return end
    if self.dead then
        if VMH.Safe(_G.UnitIsDeadOrGhost, "player") == false then self:OnAlive() end
        return
    end
    local pct = self:Percent()
    if not pct then return end
    local a = VMH.db.alerts
    -- Out of combat, low health is just regen time: only re-arm, never announce.
    if VMH.Safe(_G.UnitAffectingCombat, "player") ~= true then
        local hyst = VMH.db.announce.hysteresis or 10
        if self.state ~= "ok" and pct > a.lowHealth.threshold + hyst then self.state = "ok" end
        return
    end
    local hyst = VMH.db.announce.hysteresis or 10
    local lowT, critT = a.lowHealth.threshold, a.criticalHealth.threshold
    if pct <= critT and self.state ~= "critical" then
        self.state = "critical"
        VMH.Announce:Alert("criticalHealth", { pct = pct })
    elseif pct <= lowT and self.state == "ok" then
        self.state = "low"
        VMH.Announce:Alert("lowHealth", { pct = pct })
    elseif self.state == "critical" and pct > critT + hyst then
        self.state = (pct <= lowT) and "low" or "ok"
    elseif self.state == "low" and pct > lowT + hyst then
        self.state = "ok"
    end
end

function Hm:Queue()
    if self.pending then return end
    self.pending = true
    VMH.After(0.2, function() Hm:Evaluate() end)
end

local function selfResOption()
    local fn = _G.HasSoulstone
    if type(fn) ~= "function" then return nil end
    local text = VMH.Safe(fn)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

function Hm:OnDeath()
    if self.dead then return end
    self.dead = true
    self.state = "ok"
    VMH.History:RecordDeath()
    VMH.Announce:Alert("death")
    local res = selfResOption()
    if res then
        -- give the death message the first slot in the queue
        VMH.After(1.5, function() if Hm.dead then VMH.Announce:Alert("selfRes", { spell = res }) end end)
    end
end

function Hm:OnAlive()
    if not self.dead then return end
    if VMH.Safe(_G.UnitIsDeadOrGhost, "player") == true then return end
    self.dead = false
    VMH.Announce:Alert("revived")
    self:Queue()
end

function Hm:Init()
    VMH:OnUnit("UNIT_HEALTH", "player", function() Hm:Queue() end)
    VMH:OnUnit("UNIT_MAXHEALTH", "player", function() Hm:Queue() end)
    VMH:On("PLAYER_DEAD", function() Hm:OnDeath() end)
    VMH:On("PLAYER_ALIVE", function() Hm:OnAlive() end)
    VMH:On("PLAYER_UNGHOST", function() Hm:OnAlive() end)
end

function Hm:OnEnterWorld()
    -- zoning/reloading while dead must not re-announce the death
    self.dead = VMH.Safe(_G.UnitIsDeadOrGhost, "player") == true
    self:Queue()
end
