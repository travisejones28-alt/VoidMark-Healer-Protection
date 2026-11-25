-- VoidMark Healer - mana and drinking
-- Readable mana: real percentage with hysteresis.
-- Hidden mana (secret values in combat): falls back to whether your own
-- spells are castable. Spell costs are learned out of combat and matched to
-- the thresholds, so alerts still fire - without a percentage in the text.
local _, VMH = ...
local M = VMH:NewModule("Mana")
local D = VMH.SpellData

M.state = "ok"          -- ok | low | oom
M.peakMax = 0
M.costs = {}            -- sorted { {id, cost} }
M.costsDirty = true
M.drinking = false
M.pending = false

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local function usesMana()
    local ptype = VMH.Number(VMH.Safe(_G.UnitPowerType, "player"))
    return ptype == nil or ptype == MANA
end

function M:Percent()
    local cur = VMH.Number(VMH.Safe(_G.UnitPower, "player", MANA))
    local max = VMH.Number(VMH.Safe(_G.UnitPowerMax, "player", MANA))
    if max and max > 0 then
        if max > self.peakMax or not (VMH.Safe(_G.InCombatLockdown) == true) then self.peakMax = max end
    end
    if not cur or not max or max <= 0 then return nil end
    return math.floor(cur / max * 100 + 0.5)
end

------------------------------------------------------------------------
-- Spell-cost fallback
------------------------------------------------------------------------
local function manaCost(spellID)
    local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
    local costs = VMH.Safe(getCost, spellID)
    if type(costs) ~= "table" then return nil end
    for _, c in ipairs(costs) do
        local t, cost = VMH.Readable(c.type), VMH.Number(c.cost)
        if t == MANA and cost and cost > 0 then return cost end
    end
    return nil
end

local function eachSpell(fn)
    if C_SpellBook and type(C_SpellBook.GetNumSpellBookSkillLines) == "function" and Enum and Enum.SpellBookSpellBank then
        local lines = VMH.Number(VMH.Safe(C_SpellBook.GetNumSpellBookSkillLines)) or 0
        for i = 1, lines do
            local line = VMH.Safe(C_SpellBook.GetSpellBookSkillLineInfo, i)
            if type(line) == "table" and line.itemIndexOffset and line.numSpellBookItems then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local item = VMH.Safe(C_SpellBook.GetSpellBookItemInfo, slot, Enum.SpellBookSpellBank.Player)
                    if type(item) == "table" and item.spellID and not item.isPassive then fn(item.spellID) end
                end
            end
        end
    elseif type(_G.GetNumSpellTabs) == "function" then
        for tab = 1, (VMH.Number(VMH.Safe(_G.GetNumSpellTabs)) or 0) do
            local _, _, offset, count = VMH.Safe(_G.GetSpellTabInfo, tab)
            for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
                local kind, id = VMH.Safe(_G.GetSpellBookItemInfo, slot, "spell")
                if kind == "SPELL" and id then fn(id) end
            end
        end
    end
end

function M:ScanCosts()
    local list, seen = {}, {}
    eachSpell(function(id)
        if seen[id] then return end
        seen[id] = true
        local cost = manaCost(id)
        if cost then list[#list + 1] = { id = id, cost = cost } end
    end)
    table.sort(list, function(a, b) return a.cost < b.cost end)
    -- costs can be hidden in combat; keep the last good list and try again later
    if #list == 0 then return end
    self.costs = list
    self.costsDirty = false
    VMH:Debug("mana fallback learned " .. #list .. " spell costs")
end

-- Spell whose cost is closest to pct% of max mana.
function M:SpellAt(pct)
    if #self.costs == 0 or self.peakMax <= 0 then return nil end
    local want = self.peakMax * pct / 100
    local best, diff
    for _, s in ipairs(self.costs) do
        local d = math.abs(s.cost - want)
        if not diff or d < diff then best, diff = s.id, d end
    end
    return best
end

local function lacksMana(spellID)
    if not spellID then return nil end
    local fn = (C_Spell and C_Spell.IsSpellUsable) or _G.IsUsableSpell
    if type(fn) ~= "function" then return nil end
    local ok, _, noMana = pcall(fn, spellID)
    if not ok then return nil end
    noMana = VMH.Readable(noMana)
    if noMana == nil then return nil end
    return noMana == true
end

------------------------------------------------------------------------
-- Evaluation
------------------------------------------------------------------------
function M:Evaluate()
    self.pending = false
    if not VMH.loaded or not usesMana() or not VMH:IsActiveHere() then return end
    if VMH.Safe(_G.UnitIsDeadOrGhost, "player") == true then return end
    local a = VMH.db.alerts
    local hyst = VMH.db.announce.hysteresis or 10
    local lowT, oomT, recT = a.lowMana.threshold, a.oom.threshold, a.manaRecovered.threshold
    local pct = self:Percent()
    local isLow, isOom, isRecovered, rearmLow, rearmOom

    if pct then
        isOom = pct <= oomT
        isLow = pct <= lowT
        isRecovered = pct >= math.max(recT, lowT + 1)
        rearmOom = pct > oomT + hyst
        rearmLow = pct > lowT + hyst
    else
        if self.costsDirty then self:ScanCosts() end
        local oomSpell = self:SpellAt(oomT) or (self.costs[1] and self.costs[1].id)
        local lowSpell = self:SpellAt(lowT)
        -- "recovered" in this mode = your most expensive spell is castable again
        local recSpell = self.costs[#self.costs] and self.costs[#self.costs].id
        isOom = lacksMana(oomSpell) == true
        isLow = lacksMana(lowSpell) == true
        local recOk = lacksMana(recSpell)
        -- if "recovered" would test the same spell as "low", it would fire one regen
        -- tick after the low warning: re-arm quietly instead of announcing
        if recSpell == lowSpell or recSpell == oomSpell then
            self.quietRecover = true
        else
            self.quietRecover = false
        end
        isRecovered = recOk == false
        rearmOom = lacksMana(self:SpellAt(oomT + hyst)) == false
        rearmLow = lacksMana(self:SpellAt(lowT + hyst)) == false
    end

    if isOom and self.state ~= "oom" then
        self.state = "oom"
        self.needRecover = true
        VMH.Announce:Alert("oom", { pct = pct })
        VMH.History:RecordLowMana()
    elseif isLow and self.state == "ok" then
        self.state = "low"
        self.needRecover = true
        VMH.Announce:Alert("lowMana", { pct = pct })
        VMH.History:RecordLowMana()
    elseif self.needRecover and isRecovered then
        self.state = "ok"
        self.needRecover = false
        if pct or not self.quietRecover then VMH.Announce:Alert("manaRecovered", { pct = pct }) end
    elseif self.state == "oom" and rearmOom then
        -- climbed clear of the out-of-mana line: it may fire again later
        self.state = isLow and "low" or "ok"
    elseif self.state == "low" and rearmLow then
        self.state = "ok"
    end
end

function M:Queue()
    if self.pending or not VMH:IsActiveHere() then return end
    self.pending = true
    VMH.After(0.25, function() M:Evaluate() end)
end

------------------------------------------------------------------------
-- Drinking
------------------------------------------------------------------------
function M:IsDrinking()
    if VMH.AurasHidden() then return nil end
    for i = 1, 40 do
        local a = VMH.GetAura("player", i, "HELPFUL")
        if not a then break end
        if D.IsDrinkName(a.name) then return true end
        if a.spellId then
            for _, id in ipairs(D.DRINKS) do if id == a.spellId then return true end end
        end
    end
    return false
end

function M:CheckDrinking()
    local now = self:IsDrinking()
    if now == nil then return end
    if now and not self.drinking then
        self.drinking = true
        local pct = self:Percent()
        if pct == nil or pct < 95 then VMH.Announce:Alert("drinking", { pct = pct }) end
    elseif not now and self.drinking then
        self.drinking = false
        VMH.Announce:Alert("drinkDone", { pct = self:Percent() })
    end
end

function M:Init()
    VMH:OnUnit("UNIT_POWER_UPDATE", "player", function() M:Queue() end)
    VMH:OnUnit("UNIT_MAXPOWER", "player", function() M:Queue() end)
    VMH:On("SPELL_UPDATE_USABLE", function() M:Queue() end)
    VMH:On("SPELLS_CHANGED", function()
        M.costsDirty = true
        if not M.scanQueued then
            M.scanQueued = true
            VMH.After(1, function() M.scanQueued = false; M:ScanCosts() end)
        end
    end)
    VMH:On("PLAYER_REGEN_ENABLED", function() if M.costsDirty then M:ScanCosts() end end)
    VMH:OnPlayerAura(function() M:CheckDrinking() end)
end

function M:OnEnterWorld()
    self.costsDirty = true
    self:ScanCosts()
    self:Percent()
    self:Queue()
end

function M:OnSettingsChanged() self:Queue() end
