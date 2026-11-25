-- VoidMark Healer - healing-blocked countdown
-- Tracks one "healing blocked" window across every overlapping effect:
-- it ends when the LAST healing-preventing effect ends. Recovery is never
-- announced while any other effect still prevents healing. Roots never block.
-- The update loop only runs while effects are active.
local _, VMH = ...
local CD = VMH:NewModule("Countdown")

CD.block = nil
CD.seq = 0
local THRESHOLDS = { 10, 5, 3, 2, 1 }

local function now() return VMH.Now() end

local function isDead()
    return VMH.Safe(_G.UnitIsDeadOrGhost, "player") == true
end

-- Which warning times apply to a block whose planned length is `plan` seconds.
function CD:Plan(plan)
    local c = VMH.db.countdown
    local out = {}
    if not c.enabled or type(plan) ~= "number" or plan < (c.minDuration or 0) then return out end
    for _, t in ipairs(THRESHOLDS) do
        if c["warn" .. t] then
            local ok
            if c.smart then
                ok = (t == 10 and plan >= 15) or (t == 5 and plan >= 10) or (t == 3 and plan >= 5) or (t <= 2 and plan >= 4)
            else
                ok = plan > t + 1
            end
            if ok then out[#out + 1] = t end
        end
    end
    return out
end

local function rearm(block, remaining)
    block.warned = {}
    for _, t in ipairs(THRESHOLDS) do
        if remaining == nil or t >= remaining - 0.25 then block.warned[t] = true end
    end
    block.plan = remaining
    block.thresholds = remaining and CD:Plan(remaining) or {}
end

function CD:Refresh(active)
    local t = now()
    local blocking, allSim, unknown, endTime = 0, true, false, nil
    for _, e in pairs(active) do
        if e.blocks and not (e.expires and e.expires < t - 0.5) then
            blocking = blocking + 1
            if not e.simulated then allSim = false end
            if e.expires then
                if not endTime or e.expires > endTime then endTime = e.expires end
            else
                unknown = true
            end
        end
    end
    if unknown then endTime = nil end
    local dead = isDead()

    if blocking == 0 or dead then
        if self.block then self:Finish(dead) end
    elseif not self.block then
        self.seq = self.seq + 1
        self.block = { id = self.seq, startedAt = t, endTime = endTime, simulated = allSim,
            initial = endTime and (endTime - t) or nil }
        rearm(self.block, self.block.initial)
    else
        local b = self.block
        b.simulated = allSim
        local old = b.endTime
        if endTime ~= old then
            b.endTime = endTime
            local remaining = endTime and (endTime - t) or nil
            if endTime and (old == nil or endTime > old + 0.5) then
                -- A new or longer effect extended the block: plan again from here.
                b.initial = endTime - b.startedAt
                rearm(b, remaining)
            elseif remaining then
                -- Shortened (dispel/trinket on the longest effect): skip times already passed.
                for _, th in ipairs(THRESHOLDS) do if th >= remaining - 0.25 then b.warned[th] = true end end
            else
                rearm(b, nil)
            end
        end
    end
    self:UpdateTicker()
end

function CD:Finish(dead)
    local b = self.block
    self.block = nil
    local held = now() - b.startedAt
    VMH.History:RecordBlocked(held, b.simulated)
    local c = VMH.db.countdown
    if dead or not c.recovery then return end
    local short = b.initial ~= nil and b.initial < 5
    if short and not c.recoveryShort then return end
    local rooted = VMH.CrowdControl:HasType("ROOT")
    VMH.Announce:Alert("recovered", { note = rooted and "(still rooted)" or nil },
        { sim = b.simulated, dedupe = "rec:" .. b.id, ignoreCooldown = true })
end

function CD:Reset()
    self.block = nil
    self:UpdateTicker()
end

function CD:Remaining()
    local b = self.block
    if not b then return nil end
    if not b.endTime then return nil end
    return math.max(0, b.endTime - now())
end

function CD:CheckWarnings()
    local b = self.block
    if not b or not b.endTime then return end
    local remaining = b.endTime - now()
    for _, th in ipairs(b.thresholds or {}) do
        if not b.warned[th] and remaining <= th + 0.05 then
            b.warned[th] = true
            if remaining > th - 0.9 then
                local c = VMH.db.countdown
                if c.sound then VMH.Announce:PlaySound("ping") end
                if c.chat then
                    VMH.Announce:Alert("countdown", { dur = th .. "s" },
                        { sim = b.simulated, expires = now() + 0.9, dedupe = "cd:" .. b.id .. ":" .. th, ignoreCooldown = true })
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Ticker: one frame, ~10 updates per second, only while something is active.
------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
ticker:Hide()
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.1 then return end
    acc = 0
    CD:Tick()
end)
CD.tickerFrame = ticker

function CD:Tick()
    self:CheckWarnings()
    VMH.CrowdControl:PruneExpired()
    VMH.Display:Tick()
    self:UpdateTicker()
end

function CD:UpdateTicker()
    local need = self.block ~= nil or next(VMH.CrowdControl.active) ~= nil or VMH.Display:NeedsTicks()
    if need and not ticker:IsShown() then ticker:Show() elseif not need and ticker:IsShown() then ticker:Hide() end
end

function CD:Init()
    VMH:On("PLAYER_DEAD", function() CD:Reset() end)
end
