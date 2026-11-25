-- VoidMark Healer - on-screen crowd-control display
-- Movable panel: icon, type, spell, school, remaining time and bar for every
-- active effect, plus a "HEALING BLOCKED" countdown header.
-- Bars update from the countdown ticker, which only runs while effects exist.
local _, VMH = ...
local Disp = VMH:NewModule("Display")
local D = VMH.SpellData

Disp.rows = {}
Disp.preview = false
Disp.list = {}

local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TEX_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local TEX_QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function cfg() return VMH.db.display end

local function setFont(fs, size, flags)
    fs:SetFont(FONT, size, flags or "OUTLINE")
    if not fs:GetFont() then fs:SetFontObject(_G.GameFontNormal) end
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------
function Disp:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "VoidMarkHealerDisplay", UIParent)
    f:SetSize(260, 40)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not cfg().locked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local point, _, relPoint, x, y = s:GetPoint(1)
        local c = cfg()
        c.point, c.relPoint, c.x, c.y = point or "CENTER", relPoint or "CENTER", math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
    end)
    f:SetFrameStrata("HIGH")
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    f.bg = bg

    local header = f:CreateFontString(nil, "OVERLAY")
    header:SetPoint("TOP", f, "TOP", 0, -4)
    f.header = header

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    hint:SetTextColor(0.7, 0.6, 0.9)
    f.hint = hint

    self.frame = f
    self:ApplyLayout()
end

function Disp:Row(i)
    local row = self.rows[i]
    if row then return row end
    local f = self.frame
    row = CreateFrame("Frame", nil, f)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetStatusBarTexture(TEX_BAR)
    row.bar:SetMinMaxValues(0, 1)
    row.barBg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.barBg:SetAllPoints()
    row.barBg:SetColorTexture(0, 0, 0, 0.5)
    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetJustifyH("LEFT")
    row.time = row:CreateFontString(nil, "OVERLAY")
    row.time:SetJustifyH("RIGHT")
    row.barText = row.bar:CreateFontString(nil, "OVERLAY")
    row.barText:SetJustifyH("LEFT")
    self.rows[i] = row
    self:LayoutRow(row, i)
    return row
end

function Disp:LayoutRow(row, i)
    local c = cfg()
    local icon, bw, bh, fs = c.iconSize, c.barWidth, c.barHeight, c.fontSize
    local rowH = math.max(icon, fs + bh + 4)
    local top = self.headerHeight + (i - 1) * (rowH + 4)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 6, -top)
    row:SetSize(icon + 6 + bw, rowH)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetSize(icon, icon)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.label:SetWidth(bw - 40)
    setFont(row.label, fs)
    row.time:ClearAllPoints()
    row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    setFont(row.time, fs)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.bar:SetSize(bw, bh)
    row.barText:ClearAllPoints()
    row.barText:SetPoint("LEFT", row.bar, "LEFT", 3, 0)
    setFont(row.barText, math.max(8, fs - 2))
    row.rowHeight = rowH
end

function Disp:ApplyLayout()
    local f = self.frame
    if not f then return end
    local c = cfg()
    f:SetScale(math.max(0.5, math.min(2, c.scale or 1)))
    f:SetAlpha(math.max(0.2, math.min(1, c.alpha or 1)))
    f:ClearAllPoints()
    f:SetPoint(c.point or "CENTER", UIParent, c.relPoint or "CENTER", c.x or 0, c.y or 0)
    local b = c.colorBackground or { 0, 0, 0, 0.8 }
    f.bg:SetColorTexture(b[1], b[2], b[3], b[4] or 0.85)
    setFont(f.header, c.fontSize + 4)
    setFont(f.hint, math.max(8, c.fontSize - 2))
    self.headerHeight = c.fontSize + 12
    for i, row in ipairs(self.rows) do self:LayoutRow(row, i) end
    f:EnableMouse(not c.locked)
    self:Refresh()
end

------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------
local PREVIEW = {
    { type = "SILENCE", name = "Silence", spellID = 15487, duration = 5 },
    { type = "LOCKOUT", name = "Kick", spellID = 1766, duration = 5, school = 2 },
    { type = "STUN", name = "Kidney Shot", spellID = 408, duration = 6 },
    { type = "ROOT", name = "Frost Nova", spellID = 122, duration = 8 },
}

function Disp:SetPreview(on)
    self.preview = on and true or false
    if self.preview then
        self.previewStart = VMH.Now()
        self:Build()
    end
    self:Refresh()
    VMH.Countdown:UpdateTicker()
end

function Disp:PreviewEffects()
    local t = VMH.Now()
    local cycle = (t - (self.previewStart or t)) % 10
    local list = {}
    for _, p in ipairs(PREVIEW) do
        local left = p.duration - (cycle % p.duration)
        local def = D.TYPES[p.type]
        local name, icon = p.name, nil
        if C_Spell and C_Spell.GetSpellTexture then icon = VMH.Safe(C_Spell.GetSpellTexture, p.spellID) end
        list[#list + 1] = { type = p.type, label = def.label, name = name, icon = icon, duration = p.duration,
            expires = t + left, blocks = def.blocks, school = p.school, schoolName = D.SchoolName(p.school), preview = true }
    end
    return list
end

function Disp:Collect()
    if self.preview then return self:PreviewEffects() end
    local list = {}
    for _, e in pairs(VMH.CrowdControl.active) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if a.blocks ~= b.blocks then return a.blocks end
        return D.TYPES[a.type].order < D.TYPES[b.type].order
    end)
    return list
end

function Disp:NeedsTicks()
    return self.preview and self.frame ~= nil and self.frame:IsShown()
end

local function inCombat() return VMH.Safe(_G.InCombatLockdown) == true or VMH.Safe(_G.UnitAffectingCombat, "player") == true end

function Disp:Refresh()
    if not VMH.loaded then return end
    local c = cfg()
    if not c.enabled and not self.preview then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Build()
    local f = self.frame
    local list = self:Collect()
    self.list = list
    local unlocked = not c.locked
    local visible = #list > 0 or unlocked or self.preview
    if visible and not self.preview and not unlocked and not c.showOutOfCombat and not inCombat() then visible = false end
    if not visible then
        f:Hide()
        return
    end
    local n = math.min(#list, c.maxRows or 5)
    for i = 1, n do
        local row = self:Row(i)
        local e = list[i]
        row.effect = e
        row.icon:SetTexture(e.icon or TEX_QUESTION)
        local color = e.type == "LOCKOUT" and c.colorLockout or (e.blocks and c.colorBlocked or c.colorMovement)
        row.bar:SetStatusBarColor(color[1], color[2], color[3])
        local label = e.label or D.TYPES[e.type].label
        if e.type == "LOCKOUT" and e.schoolName then label = e.schoolName .. " locked" end
        row.label:SetText(label)
        row.label:SetTextColor(color[1], color[2], color[3])
        local spell = e.name or ""
        if e.source then spell = spell .. " - " .. e.source end
        if e.type ~= "LOCKOUT" and e.schoolName then spell = spell .. " (" .. e.schoolName .. ")" end
        row.barText:SetText(spell)
        row:Show()
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].effect = nil end
    local rowH = (self.rows[1] and self.rows[1].rowHeight) or c.iconSize
    local height = self.headerHeight + n * (rowH + 4) + (unlocked and 16 or 6)
    f:SetSize(c.iconSize + c.barWidth + 18, math.max(height, 40))
    f.hint:SetText(self.preview and "PREVIEW - not real effects" or (unlocked and "VoidMark Healer - drag to move" or ""))
    f:Show()
    self:Tick()
end

function Disp:Tick()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local c = cfg()
    local t = VMH.Now()
    if self.preview then self.list = self:PreviewEffects() end
    for i, row in ipairs(self.rows) do
        local e = self.preview and self.list[i] or row.effect
        if row:IsShown() and e then
            if e.expires and e.duration and e.duration > 0 then
                local left = math.max(0, e.expires - t)
                row.bar:SetValue(left / e.duration)
                row.time:SetText(string.format(left >= 10 and "%.0fs" or "%.1fs", left))
            else
                row.bar:SetValue(1)
                row.time:SetText("")
            end
        end
    end
    -- Header: healing state
    local blockedLeft, blocked
    if self.preview then
        blocked = true
        for _, e in ipairs(self.list) do
            if e.blocks and e.expires then blockedLeft = math.max(blockedLeft or 0, e.expires - t) end
        end
    else
        blocked = VMH.Countdown.block ~= nil
        blockedLeft = VMH.Countdown:Remaining()
    end
    if blocked and VMH.db.countdown.onscreen then
        local bc = c.colorBlocked
        f.header:SetTextColor(bc[1], bc[2], bc[3])
        if blockedLeft then
            f.header:SetText(string.format("HEALING BLOCKED  %.1fs", blockedLeft))
        else
            f.header:SetText("HEALING BLOCKED")
        end
    elseif #self.list > 0 then
        local mc = c.colorMovement
        f.header:SetTextColor(mc[1], mc[2], mc[3])
        f.header:SetText("Can heal")
    else
        f.header:SetTextColor(0.62, 0.36, 1)
        f.header:SetText("No crowd control")
    end
end

function Disp:Init()
    VMH:On("PLAYER_REGEN_DISABLED", function() Disp:Refresh() end)
    VMH:On("PLAYER_REGEN_ENABLED", function() Disp:Refresh() end)
end

function Disp:OnEnterWorld()
    self:Build()
    self:ApplyLayout()
end

function Disp:OnSettingsChanged()
    if self.frame then self:ApplyLayout() end
end
