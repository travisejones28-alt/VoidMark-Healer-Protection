-- VoidMark Healer - crowd-control detection
-- Sources, merged per scan:
--   1. Loss of Control data (type, real remaining time, locked school)
--   2. Harmful auras on the player (spell ID, real duration, caster when visible)
--   3. External effects proven by other modules (interrupt cooldown probe)
--   4. Simulations from /vmh test (always flagged, never recorded or sent to group)
-- Scans are event-driven (Loss of Control events + UNIT_AURA), coalesced to one per frame.
local _, VMH = ...
local CC = VMH:NewModule("CrowdControl")
local D = VMH.SpellData
local R = VMH.Readable

CC.active = {}
CC.noted = {}
local function note(key, msg)
    local t = VMH.Now()
    if CC.noted[key] and t - CC.noted[key] < 15 then return end
    CC.noted[key] = t
    VMH:Debug(msg)
end
CC.external = {}
CC.sims = {}
CC.capability = { loc = false, auras = false }

local function now() return VMH.Now() end

------------------------------------------------------------------------
-- Loss of Control readers (modern and older API shapes)
------------------------------------------------------------------------
local function locCount()
    local L = C_LossOfControl
    if not L then return nil end
    if type(L.GetActiveLossOfControlDataCount) == "function" then return VMH.Number(VMH.Safe(L.GetActiveLossOfControlDataCount)) end
    if type(L.GetNumEvents) == "function" then return VMH.Number(VMH.Safe(L.GetNumEvents)) end
    return nil
end

local function locEntry(i)
    local L = C_LossOfControl
    if type(L.GetActiveLossOfControlData) == "function" then
        local ok, d = pcall(L.GetActiveLossOfControlData, i)
        if not ok or d == nil or R(d) == nil or type(d) ~= "table" then return nil end
        return { locType = R(d.locType), spellID = R(d.spellID), text = R(d.displayText), icon = R(d.iconTexture),
            start = R(d.startTime), remaining = R(d.timeRemaining), duration = R(d.duration), school = R(d.lockoutSchool) }
    end
    if type(L.GetEventInfo) == "function" then
        local locType, spellID, text, icon, start, remaining, duration, school = VMH.Safe(L.GetEventInfo, i)
        return { locType = locType, spellID = spellID, text = text, icon = icon, start = start,
            remaining = remaining, duration = duration, school = school }
    end
    return nil
end

local function classify(spellID, locType, text)
    if locType == "SCHOOL_INTERRUPT" then return "LOCKOUT" end
    local kind = spellID and D.CC[spellID]
    if kind then return kind end
    kind = locType and D.LOC_TYPES[locType]
    if (kind == "DISORIENT" or kind == "FEAR" or kind == nil) and type(text) == "string" then
        local lower = text:lower()
        for _, hint in ipairs(D.TEXT_HINTS) do
            if lower:find(hint[1], 1, true) then return hint[2] end
        end
    end
    return kind
end
CC.Classify = classify

------------------------------------------------------------------------
-- Tooltip fallback for debuffs not in the spell list (mob silences, stuns...).
-- One lookup per distinct debuff; results are cached.
------------------------------------------------------------------------
CC.tipCache = {}
local scanTip
local function tooltipLines(index, auraInstanceID)
    local lines = {}
    if C_TooltipInfo then
        local data
        if auraInstanceID and type(C_TooltipInfo.GetUnitDebuffByAuraInstanceID) == "function" then
            data = VMH.Safe(C_TooltipInfo.GetUnitDebuffByAuraInstanceID, "player", auraInstanceID)
        end
        if not data and type(C_TooltipInfo.GetUnitDebuff) == "function" then
            data = VMH.Safe(C_TooltipInfo.GetUnitDebuff, "player", index)
        end
        if type(data) == "table" and type(data.lines) == "table" then
            for i, line in ipairs(data.lines) do
                local text = type(line) == "table" and R(line.leftText)
                if i > 1 and type(text) == "string" then lines[#lines + 1] = text end
            end
            return lines
        end
    end
    -- older clients: hidden tooltip
    if not scanTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "VoidMarkHealerScanTip", nil, "GameTooltipTemplate")
        if not ok or not tip then return lines end
        scanTip = tip
    end
    local ok = pcall(function()
        scanTip:SetOwner(_G.WorldFrame, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetUnitDebuff("player", index)
    end)
    if not ok then return lines end
    for i = 2, 6 do
        local fs = _G["VoidMarkHealerScanTipTextLeft" .. i]
        local text = fs and R(fs:GetText())
        if type(text) == "string" then lines[#lines + 1] = text end
    end
    return lines
end

function CC:ClassifyByTooltip(index, a)
    local cacheKey = a.spellId or a.name
    if cacheKey and self.tipCache[cacheKey] ~= nil then return self.tipCache[cacheKey] or nil end
    local lines = tooltipLines(index, a.auraInstanceID)
    if #lines == 0 then return nil end -- unreadable now: try again next scan
    local kind = false
    local text = table.concat(lines, " "):lower()
    for _, w in ipairs(D.TOOLTIP_WORDS) do
        if text:find(w[1], 1, true) then kind = w[2]; break end
    end
    if cacheKey then
        self.tipCache[cacheKey] = kind
        VMH:Debug("debuff " .. tostring(a.name) .. " (spell " .. tostring(a.spellId) .. ") read from tooltip: " ..
            (kind or "not crowd control"))
    end
    return kind or nil
end

local function spellInfo(spellID)
    if not spellID then return nil, nil end
    local name = D.SpellName(spellID)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then icon = VMH.Safe(C_Spell.GetSpellTexture, spellID)
    elseif _G.GetSpellTexture then icon = VMH.Safe(_G.GetSpellTexture, spellID) end
    return name, icon
end

local function finalize(e)
    local def = D.TYPES[e.type]
    e.label = def.label
    e.blocks = def.blocks
    if e.type == "LOCKOUT" then
        e.schoolName = D.SchoolName(e.school)
        e.blocks = D.LockoutBlocksHealing(e.school)
    end
    if not e.name or not e.icon then
        local n, ic = spellInfo(e.spellID)
        e.name = e.name or n
        e.icon = e.icon or ic
    end
    if type(e.duration) ~= "number" or e.duration <= 0 then e.duration = nil end
    if type(e.expires) ~= "number" or e.expires <= 0 then e.expires = nil end
    if e.expires and not e.duration then e.duration = e.expires - now() end
    return e
end

------------------------------------------------------------------------
-- Scan
------------------------------------------------------------------------
function CC:Collect()
    local t = now()
    local found = {}
    local bySpell = {}
    local unnamed = {}   -- Loss of Control entries whose spell ID was hidden
    local live = VMH:IsActiveHere()

    local n = live and locCount() or nil
    self.capability.loc = n ~= nil
    if live and n == nil and C_LossOfControl then note("locHidden", "Loss of Control data hidden by the game") end
    for i = 1, (n or 0) do
        local d = locEntry(i)
        if not d or not d.locType then
            note("locEntry" .. i, "Loss of Control entry " .. i .. " unreadable")
        end
        if d and d.locType then
            local kind = classify(d.spellID, d.locType, d.text)
            if not kind then
                note("ign" .. tostring(d.locType) .. tostring(d.spellID), "Loss of Control ignored: " .. tostring(d.locType) ..
                    " spell " .. tostring(d.spellID) .. " (" .. tostring(d.text) .. ")")
            end
            if kind then
                local expires
                if type(d.remaining) == "number" and d.remaining > 0 then expires = t + d.remaining
                elseif type(d.start) == "number" and type(d.duration) == "number" and d.duration > 0 then expires = d.start + d.duration end
                local key
                if kind == "LOCKOUT" then key = "lock:" .. tostring(d.school or 0)
                elseif d.spellID then key = "s:" .. d.spellID
                else key = "t:" .. kind end
                local e = { key = key, spellID = d.spellID, type = kind, icon = d.icon, duration = d.duration,
                    expires = expires, school = d.school, text = d.text, via = "loc" }
                found[key] = e
                if d.spellID and kind ~= "LOCKOUT" then bySpell[d.spellID] = e
                elseif kind ~= "LOCKOUT" then unnamed[#unnamed + 1] = e end
            end
        end
    end

    if live and not VMH.AurasHidden() then
        self.capability.auras = true
        for i = 1, 40 do
            local a = VMH.GetAura("player", i, "HARMFUL")
            if not a then break end
            local kind = (a.spellId and D.CC[a.spellId]) or D.TypeForName(a.name)
            if not kind and (a.spellId or a.name) then kind = self:ClassifyByTooltip(i, a) end
            if kind then
                local source = a.sourceUnit and VMH.UnitFullName(a.sourceUnit) or nil
                local expires = (type(a.expirationTime) == "number" and a.expirationTime > 0) and a.expirationTime or nil
                local existing = a.spellId and bySpell[a.spellId]
                if not existing then
                    -- Same effect seen through Loss of Control without its spell ID:
                    -- match by end time (or by type when times are hidden).
                    for i, e in ipairs(unnamed) do
                        local sameEnd = expires and e.expires and math.abs(e.expires - expires) < 0.6
                        local sameType = e.type == kind or (not expires or not e.expires)
                        if sameEnd or (sameType and D.TYPES[kind].blocks == D.TYPES[e.type].blocks) then
                            existing = e
                            table.remove(unnamed, i)
                            -- the debuff knows the exact spell, so its category is more specific
                            e.type = kind
                            e.spellID = a.spellId
                            break
                        end
                    end
                end
                if existing and existing.key ~= ("s:" .. tostring(a.spellId)) and a.spellId and existing.via == "loc"
                    and existing.key:sub(1, 2) == "t:" then
                    -- keep one stable key whichever source saw it first
                    found[existing.key] = nil
                    existing.key = "s:" .. a.spellId
                    found[existing.key] = existing
                end
                if existing then
                    existing.source = existing.source or source
                    existing.expires = existing.expires or expires
                    existing.duration = existing.duration or a.duration
                    existing.name = existing.name or a.name
                    existing.icon = existing.icon or a.icon
                else
                    local key = a.spellId and ("s:" .. a.spellId) or ("n:" .. a.name)
                    if not found[key] then
                        found[key] = { key = key, spellID = a.spellId, name = a.name, icon = a.icon, type = kind,
                            duration = a.duration, expires = expires, source = source, via = "aura" }
                    end
                end
            end
        end
    elseif live then
        self.capability.auras = false
    end

    for key, e in pairs(self.external) do
        if e.expires and e.expires <= t then self.external[key] = nil
        elseif not found[key] then found[key] = VMH.DeepCopy(e) end
    end
    for key, e in pairs(self.sims) do
        if e.expires and e.expires <= t then self.sims[key] = nil
        else found[key] = VMH.DeepCopy(e) end
    end
    for _, e in pairs(found) do finalize(e) end
    return found
end

function CC:Scan()
    if not VMH.loaded then return end
    local found = self:Collect()
    local old = self.active
    local t = now()
    local added = {}
    for key, e in pairs(found) do
        local prev = old[key]
        if not prev then
            e.addedAt = t
            added[#added + 1] = e
        else
            e.addedAt = prev.addedAt
            e.pruneAsked = (prev.expires == e.expires) and prev.pruneAsked or nil
            -- Same spell landing again (re-applied, not just a refresh tick)
            if e.expires and prev.expires and e.expires > prev.expires + 1.0 and prev.expires - t < 1.5 then
                e.addedAt = t
                added[#added + 1] = e
            end
        end
    end
    self.active = found
    table.sort(added, function(a, b) return D.TYPES[a.type].order < D.TYPES[b.type].order end)
    for _, e in ipairs(added) do self:OnAdded(e) end
    for key, e in pairs(old) do
        if not found[key] then VMH:Debug("CC removed: " .. (e.name or e.type) .. (e.simulated and " (sim)" or "")) end
    end
    VMH.Countdown:Refresh(found)
    VMH.Display:Refresh()
end

function CC:Remaining(e)
    if e.expires then return math.max(0, e.expires - now()) end
    return nil
end

-- Signature of one real effect: type + end time. If the game flips a value
-- between readable and hidden, the effect can reappear under another key;
-- this stops it being announced or counted twice.
CC.seen = {}

function CC:AlreadySeen(e)
    if not e.expires or e.simulated then return false end
    local t = now()
    for i = #self.seen, 1, -1 do
        local x = self.seen[i]
        if t - x.at > 30 then
            table.remove(self.seen, i)
        elseif math.abs(x.expires - e.expires) < 1 and t - x.at < 4 then
            -- two different known spells are two effects; otherwise it's the same one seen twice
            local differentSpells = x.spellID and e.spellID and x.spellID ~= e.spellID
            local sameKind = x.type == e.type
                or (x.blocks and e.blocks and (not x.spellID or not e.spellID) and x.type ~= "LOCKOUT" and e.type ~= "LOCKOUT")
            if sameKind and not differentSpells then return true end
        end
    end
    self.seen[#self.seen + 1] = { type = e.type, blocks = e.blocks, spellID = e.spellID, expires = e.expires, at = t }
    return false
end

function CC:OnAdded(e)
    if self:AlreadySeen(e) then
        VMH:Debug("same effect seen again, not re-announced: " .. e.type)
        return
    end
    if e.type == "LOCKOUT" and not e.source and VMH.Interrupts then
        e.source = VMH.Interrupts:RecentInterrupter()
    end
    VMH:Debug(string.format("CC added: %s (spell %s) [%s] via %s, %s left%s", tostring(e.name), tostring(e.spellID), e.type, tostring(e.via),
        tostring(self:Remaining(e) and string.format("%.1fs", self:Remaining(e)) or "unknown"),
        e.source and (" from " .. e.source) or ""))
    VMH.History:RecordCC(e)
    -- Movement-only and non-healing lockouts are announced but never start the healing countdown.
    local def = D.TYPES[e.type]
    local vars = {
        dur = VMH.FormatDuration(self:Remaining(e)),
        spell = e.name,
        school = e.schoolName or "Spell",
        source = e.source,
        name = e.source,
    }
    VMH.Announce:Alert(def.alert, vars, { sim = e.simulated, dedupe = e.key .. ":" .. tostring(e.expires and math.floor(e.expires) or e.addedAt) })
end

-- Active effects that currently stop healing.
function CC:Blocking()
    local list = {}
    for _, e in pairs(self.active) do if e.blocks then list[#list + 1] = e end end
    return list
end

function CC:HasType(kind)
    for _, e in pairs(self.active) do if e.type == kind then return true end end
    return false
end

-- Called by the countdown ticker when an effect's time is up but no event removed it yet.
function CC:PruneExpired()
    local t = now()
    local need = false
    for _, e in pairs(self.active) do
        if e.expires and e.expires <= t - 0.05 and not e.pruneAsked then
            e.pruneAsked = true
            need = true
        end
    end
    if need then VMH:QueueAuraScan() end
end

------------------------------------------------------------------------
-- External / simulated effects
------------------------------------------------------------------------
function CC:AddExternal(e)
    self.external[e.key] = e
    VMH:QueueAuraScan()
end

function CC:RemoveExternal(key)
    if self.external[key] then
        self.external[key] = nil
        VMH:QueueAuraScan()
    end
end

-- spec: { type=, spellID=, name=, duration= (nil = unknown), school= }
function CC:Simulate(spec)
    local key = "sim:" .. spec.type .. ":" .. (spec.spellID or spec.name or "x")
    self.sims[key] = { key = key, type = spec.type, spellID = spec.spellID, name = spec.name, school = spec.school,
        duration = spec.duration, expires = spec.duration and (now() + spec.duration) or nil,
        source = spec.source, simulated = true, via = "simulation" }
    VMH:QueueAuraScan()
    return key
end

function CC:EndSimulation(key)
    if key then self.sims[key] = nil else self.sims = {} end
    VMH:QueueAuraScan()
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function CC:Init()
    VMH:OnPlayerAura(function() CC:Scan() end)
    VMH:OnUnit("UNIT_AURA", "player", function() VMH:QueueAuraScan() end)
    for _, ev in ipairs({ "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
        VMH:On(ev, function() VMH:QueueAuraScan() end)
    end
    VMH:On("PLAYER_DEAD", function()
        CC.external = {}
        VMH:QueueAuraScan()
    end)
end

function CC:OnEnterWorld()
    self.external = {}
    VMH:QueueAuraScan()
end
