-- VoidMark Healer - small self-contained widget kit (no Blizzard templates)
local _, VMH = ...
local W = {}
VMH.Widgets = W

W.COLORS = {
    bg = { 0.055, 0.04, 0.09, 0.97 },
    panel = { 0.09, 0.065, 0.14, 1 },
    border = { 0.36, 0.2, 0.6, 1 },
    accent = { 0.62, 0.36, 1, 1 },
    text = { 0.9, 0.88, 0.95, 1 },
    dim = { 0.6, 0.56, 0.7, 1 },
    hover = { 0.22, 0.13, 0.36, 1 },
}
local C = W.COLORS
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

function W.SetFont(obj, size, flags)
    obj:SetFont(FONT, size or 12, flags or "")
    if not obj:GetFont() then obj:SetFontObject(_G.GameFontHighlight) end
end

function W.Font(fs, size, color, flags)
    W.SetFont(fs, size, flags)
    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

function W.Fill(frame, color, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end

function W.Border(frame, color, size)
    size = size or 1
    color = color or C.border
    local edges = {}
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        edges[#edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, size)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, size)
    edge("TOPLEFT", "BOTTOMLEFT", size, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", size, nil)
    return edges
end

function W.Label(parent, text, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    W.Font(fs, size or 12, color)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- Own tooltip frame: Blizzard's shared GameTooltip is never touched (taint safety).
local tipFrame
local function showTip(owner, text)
    if not tipFrame then
        tipFrame = CreateFrame("Frame", "VoidMarkHealerTooltip", UIParent)
        tipFrame:SetFrameStrata("TOOLTIP")
        tipFrame:SetClampedToScreen(true)
        W.Fill(tipFrame, C.bg)
        W.Border(tipFrame, C.accent)
        tipFrame.text = tipFrame:CreateFontString(nil, "OVERLAY")
        W.Font(tipFrame.text, 11)
        tipFrame.text:SetPoint("TOPLEFT", 8, -6)
        tipFrame.text:SetWidth(240)
        tipFrame.text:SetJustifyH("LEFT")
        tipFrame:Hide()
    end
    tipFrame.text:SetText(text)
    local h = (tipFrame.text.GetStringHeight and tipFrame.text:GetStringHeight()) or 14
    tipFrame:SetSize(256, math.max(20, (h or 14) + 12))
    tipFrame:ClearAllPoints()
    tipFrame:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 4)
    tipFrame:Show()
end
local function hideTip() if tipFrame then tipFrame:Hide() end end

local function tooltip(frame, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self) showTip(self, text) end)
    frame:HookScript("OnLeave", hideTip)
end
W.Tooltip = tooltip

------------------------------------------------------------------------
-- Button
------------------------------------------------------------------------
function W.Button(parent, text, width, height, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 90, height or 22)
    b.bg = W.Fill(b, C.panel)
    W.Border(b, C.border)
    b.text = b:CreateFontString(nil, "OVERLAY")
    W.Font(b.text, 11)
    b.text:SetPoint("CENTER")
    b.text:SetText(text or "")
    b:SetScript("OnEnter", function(s) s.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1) end)
    b:SetScript("OnLeave", function(s)
        if s.selected then s.bg:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        else s.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1) end
    end)
    b:SetScript("OnClick", function(s, ...) if onClick then onClick(s, ...) end end)
    function b:SetSelected(on)
        self.selected = on
        local c = on and C.border or C.panel
        self.bg:SetColorTexture(c[1], c[2], c[3], 1)
    end
    function b:SetLabel(t) self.text:SetText(t) end
    tooltip(b, tip)
    return b
end

------------------------------------------------------------------------
-- Checkbox
------------------------------------------------------------------------
function W.Check(parent, label, get, set, tip)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(220, 20)
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", f, "LEFT", 0, 0)
    W.Fill(box, { 0, 0, 0, 0.6 })
    W.Border(box, C.border)
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", 2, -2)
    mark:SetPoint("BOTTOMRIGHT", -2, 2)
    mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    f.mark = mark
    f.label = W.Label(f, label, 12)
    f.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    f.label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    if f.label.SetWordWrap then f.label:SetWordWrap(false) end
    -- long labels are cut short instead of running into the next control
    function f:Refresh()
        local v = get()
        self.mark:SetShown(v and true or false)
    end
    f:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
        if self.onChange then self.onChange() end
    end)
    f:SetScript("OnEnter", function(s) s.label:SetTextColor(1, 1, 1) end)
    f:SetScript("OnLeave", function(s) s.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    tooltip(f, tip)
    f:Refresh()
    return f
end

------------------------------------------------------------------------
-- Slider with -/+ buttons
------------------------------------------------------------------------
function W.Slider(parent, label, minV, maxV, step, get, set, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(260, 40)
    f.title = W.Label(f, label, 12)
    f.title:SetPoint("TOPLEFT", 0, 0)
    f.value = W.Label(f, "", 12, C.accent)
    f.value:SetPoint("TOPRIGHT", 0, 0)
    f.value:SetJustifyH("RIGHT")
    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 22, -20)
    s:SetPoint("TOPRIGHT", -22, -20)
    s:SetHeight(14)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 14)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    s:SetThumbTexture(thumb)
    -- no mouse wheel: scrolling the page over a slider must never change a setting
    f.slider = s
    local function round(v)
        v = math.floor(v / step + 0.5) * step
        if v < minV then v = minV elseif v > maxV then v = maxV end
        if step < 1 then v = tonumber(string.format("%.2f", v)) end
        return v
    end
    local function show(v)
        f.value:SetText(fmt and fmt(v) or tostring(v))
    end
    f.updating = false
    s:SetScript("OnValueChanged", function(_, v)
        if f.updating then return end
        v = round(v)
        set(v)
        show(v)
        if f.onChange then f.onChange(v) end
    end)
    local minus = W.Button(f, "-", 18, 16, function() s:SetValue(round((s:GetValue() or minV) - step)) end)
    minus:SetPoint("RIGHT", s, "LEFT", -3, 0)
    local plus = W.Button(f, "+", 18, 16, function() s:SetValue(round((s:GetValue() or minV) + step)) end)
    plus:SetPoint("LEFT", s, "RIGHT", 3, 0)
    function f:Refresh()
        local v = get() or minV
        self.updating = true
        s:SetValue(v)
        self.updating = false
        show(v)
    end
    f:Refresh()
    return f
end

------------------------------------------------------------------------
-- Dropdown (own popup list)
------------------------------------------------------------------------
local popup
local function getPopup()
    if popup then return popup end
    popup = CreateFrame("Frame", "VoidMarkHealerDropdownList", UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    W.Fill(popup, C.bg)
    W.Border(popup, C.accent)
    popup.buttons = {}
    popup:Hide()
    return popup
end

function W.CloseDropdown()
    if popup then popup:Hide() end
    if W.CloseColorChooser then W.CloseColorChooser() end
end

function W.Dropdown(parent, label, width, options, get, set)
    local f = CreateFrame("Frame", nil, parent)
    width = width or 180
    f:SetSize(width, label and 40 or 22)
    if label then
        f.title = W.Label(f, label, 12)
        f.title:SetPoint("TOPLEFT", 0, 0)
    end
    local b = W.Button(f, "", width, 20)
    b:SetPoint("BOTTOMLEFT", 0, 0)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -16, 0)
    b.text:SetJustifyH("LEFT")
    local arrow = W.Label(b, "v", 11, C.accent)
    arrow:SetPoint("RIGHT", -5, 0)
    f.button = b
    local function opts() return type(options) == "function" and options() or options end
    function f:Refresh()
        local v = get()
        local text = tostring(v or "")
        for _, o in ipairs(opts()) do if o.value == v then text = o.label end end
        b:SetLabel(text)
    end
    b:SetScript("OnClick", function()
        local p = getPopup()
        if p:IsShown() and p.owner == f then p:Hide(); return end
        p.owner = f
        local list = opts()
        for i, o in ipairs(list) do
            local item = p.buttons[i]
            if not item then
                item = W.Button(p, "", width, 20)
                item.text:ClearAllPoints()
                item.text:SetPoint("LEFT", 6, 0)
                item.text:SetJustifyH("LEFT")
                p.buttons[i] = item
            end
            item:SetSize(width, 20)
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1 - (i - 1) * 20)
            item:SetLabel(o.label)
            item:SetSelected(o.value == get())
            item:SetScript("OnClick", function()
                set(o.value)
                p:Hide()
                f:Refresh()
                if f.onChange then f.onChange(o.value) end
            end)
            item:Show()
        end
        for i = #list + 1, #p.buttons do p.buttons[i]:Hide() end
        p:SetSize(width + 2, #list * 20 + 2)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", b, "BOTTOMLEFT", -1, -1)
        p:Show()
    end)
    f:Refresh()
    return f
end

------------------------------------------------------------------------
-- Edit box (commits on Enter or when focus leaves)
------------------------------------------------------------------------
function W.EditBox(parent, label, width, get, set)
    local f = CreateFrame("Frame", nil, parent)
    width = width or 240
    f:SetSize(width, label and 40 or 22)
    if label then
        f.title = W.Label(f, label, 12)
        f.title:SetPoint("TOPLEFT", 0, 0)
    end
    local e = CreateFrame("EditBox", nil, f)
    e:SetSize(width, 20)
    e:SetPoint("BOTTOMLEFT", 0, 0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(200)
    e:SetTextInsets(5, 5, 0, 0)
    W.SetFont(e, 12)
    e:SetTextColor(1, 1, 1)
    W.Fill(e, { 0, 0, 0, 0.6 })
    W.Border(e, C.border)
    local function commit(self)
        set(self:GetText() or "")
        if f.onChange then f.onChange() end
    end
    e:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) f:Refresh(); self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) commit(self) end)
    f.edit = e
    function f:Refresh() e:SetText(get() or "") e:SetCursorPosition(0) end
    f:Refresh()
    return f
end

------------------------------------------------------------------------
-- Color swatch
------------------------------------------------------------------------
-- Own color chooser (preset swatches): Blizzard's ColorPickerFrame is never touched.
local PRESETS = {
    { 0.85, 0.15, 0.25 }, { 1, 0.45, 0.1 }, { 0.95, 0.7, 0.1 }, { 0.3, 0.85, 0.35 }, { 0.2, 0.75, 0.9 },
    { 0.25, 0.45, 1 }, { 0.62, 0.36, 1 }, { 0.9, 0.4, 0.8 }, { 0.9, 0.9, 0.9 }, { 0.05, 0.03, 0.09 },
}
local chooser
local function openPicker(owner, onPick)
    if not chooser then
        chooser = CreateFrame("Frame", "VoidMarkHealerColorChooser", UIParent)
        chooser:SetFrameStrata("FULLSCREEN_DIALOG")
        chooser:SetClampedToScreen(true)
        chooser:EnableMouse(true)
        chooser:SetSize(#PRESETS * 22 + 6, 28)
        W.Fill(chooser, C.bg)
        W.Border(chooser, C.accent)
        chooser.swatches = {}
        for i, c in ipairs(PRESETS) do
            local b = CreateFrame("Button", nil, chooser)
            b:SetSize(18, 18)
            b:SetPoint("LEFT", 4 + (i - 1) * 22, 0)
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetColorTexture(c[1], c[2], c[3], 1)
            W.Border(b, C.text)
            b:SetScript("OnClick", function()
                chooser:Hide()
                if chooser.onPick then chooser.onPick(c[1], c[2], c[3]) end
            end)
        end
        chooser:Hide()
    end
    if chooser:IsShown() and chooser.owner == owner then chooser:Hide(); return end
    chooser.owner, chooser.onPick = owner, onPick
    chooser:ClearAllPoints()
    chooser:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    chooser:Show()
end
function W.CloseColorChooser() if chooser then chooser:Hide() end end

function W.Color(parent, label, get, set)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(200, 20)
    local sw = f:CreateTexture(nil, "ARTWORK")
    sw:SetSize(16, 16)
    sw:SetPoint("LEFT")
    f.swatch = sw
    local edge = CreateFrame("Frame", nil, f)
    edge:SetAllPoints(sw)
    W.Border(edge, C.text)
    f.label = W.Label(f, label, 12)
    f.label:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    function f:Refresh()
        local c = get()
        sw:SetColorTexture(c[1], c[2], c[3], 1)
    end
    f:SetScript("OnClick", function()
        local c = get()
        openPicker(f, function(r, g, b)
            set({ r, g, b, c[4] })
            f:Refresh()
            if f.onChange then f.onChange() end
        end)
    end)
    f:Refresh()
    return f
end

------------------------------------------------------------------------
-- Scrolling page with a visible scroll bar and a simple flow layout.
-- The bar only shows when the page is taller than the window.
------------------------------------------------------------------------
local VIEW_HEIGHT = 510

function W.Page(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 0)
    local child = CreateFrame("Frame", nil, scroll)
    local width = (parent:GetWidth() or 0) > 0 and (parent:GetWidth() - 14) or 620
    child:SetSize(width, 400)
    scroll:SetScrollChild(child)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    bar:SetWidth(10)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 40)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:Hide()
    bar:SetScript("OnValueChanged", function(_, v)
        W.CloseDropdown()
        scroll:SetVerticalScroll(v)
    end)

    local page = { scroll = scroll, frame = child, bar = bar, y = 10, widgets = {} }

    local function viewHeight()
        local h = scroll:GetHeight() or 0
        if h <= 0 then h = VIEW_HEIGHT end
        return h
    end
    function page:UpdateScroll()
        child:SetHeight(self.y + 20)
        local range = math.max(0, math.floor(self.y + 20 - viewHeight()))
        bar:SetMinMaxValues(0, range)
        if range > 0 then
            bar:Show()
            local v = bar:GetValue() or 0
            if v > range then bar:SetValue(range) end
        else
            bar:SetValue(0)
            bar:Hide()
            scroll:SetVerticalScroll(0)
        end
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if not bar:IsShown() then return end
        local minV, maxV = bar:GetMinMaxValues()
        local v = (bar:GetValue() or 0) - delta * 40
        if v < minV then v = minV elseif v > maxV then v = maxV end
        bar:SetValue(v)
    end)
    scroll:SetScript("OnSizeChanged", function() page:UpdateScroll() end)

    function page:Place(widget, x, height, keepLine, dy)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", child, "TOPLEFT", x or 12, -(self.y + (dy or 0)))
        if not keepLine then self.y = self.y + (height or 26) end
        if widget.Refresh then self.widgets[#self.widgets + 1] = widget end
        return widget
    end
    function page:Header(text)
        self.y = self.y + 6
        local fs = W.Label(child, text, 14, C.accent)
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 10, -self.y)
        local line = child:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", child, "TOPLEFT", 10, -self.y - 18)
        line:SetPoint("TOPRIGHT", child, "TOPRIGHT", -10, -self.y - 18)
        self.y = self.y + 26
        return fs
    end
    function page:Note(text, height)
        local fs = W.Label(child, text, 11, C.dim)
        fs:SetWidth(width - 30)
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 12, -self.y)
        self.y = self.y + (height or 18)
        return fs
    end
    function page:Gap(h) self.y = self.y + (h or 8) end
    function page:Track(widget) self.widgets[#self.widgets + 1] = widget end
    function page:Refresh()
        for _, w in ipairs(self.widgets) do if w.Refresh then w:Refresh() end end
        if self.onRefresh then self.onRefresh() end
        self:UpdateScroll()
    end
    return page
end
