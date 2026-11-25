-- VoidMark Healer - configuration window (/vmh)
local _, VMH = ...
local Cfg = VMH:NewModule("Config")
local W = VMH.Widgets
local C = W.COLORS

Cfg.pages = {}
Cfg.tabs = {}

local TABS = {
    { key = "general", label = "General" },
    { key = "mana", label = "Mana & Health" },
    { key = "cc", label = "Crowd Control" },
    { key = "countdown", label = "Countdown" },
    { key = "aggro", label = "Aggro & Threat" },
    { key = "announce", label = "Announcements" },
    { key = "visuals", label = "Visuals & Sounds" },
    { key = "profiles", label = "Profiles" },
    { key = "history", label = "History" },
}

local SAMPLE = { pct = 25, dur = "8s", spell = "Polymorph", school = "Holy", name = "Testname", count = 3, source = "Testname" }

local function db() return VMH.db end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function Cfg:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "VoidMarkHealerConfig", UIParent)
    f:SetSize(800, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    W.Fill(f, C.bg)
    W.Border(f, C.accent)
    f:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "VoidMarkHealerConfig") end

    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT", 1, -1)
    title:SetPoint("TOPRIGHT", -1, -1)
    title:SetHeight(30)
    W.Fill(title, C.panel)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local t = W.Label(title, "|cff9d5cffVoidMark|r Healer", 15)
    t:SetPoint("LEFT", 12, 0)
    self.profileLabel = W.Label(title, "", 11, C.dim)
    self.profileLabel:SetPoint("LEFT", t, "RIGHT", 14, 0)
    local close = W.Button(title, "X", 24, 22, function() f:Hide() end)
    close:SetPoint("RIGHT", -4, 0)

    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", 1, -31)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(150)
    W.Fill(side, C.panel)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT", 6, -4)
    content:SetPoint("BOTTOMRIGHT", -6, 6)
    content:SetSize(636, 518)
    self.content = content

    for i, tab in ipairs(TABS) do
        local b = W.Button(side, tab.label, 138, 26, function() Cfg:Show(tab.key) end)
        b:SetPoint("TOPLEFT", 6, -8 - (i - 1) * 30)
        self.tabs[tab.key] = b
    end
    local ver = W.Label(side, "v" .. VMH.version, 10, C.dim)
    ver:SetPoint("BOTTOMLEFT", 8, 8)

    f:SetScript("OnHide", function() W.CloseDropdown() end)
    self.frame = f
end

function Cfg:Page(key)
    local page = self.pages[key]
    if page then return page end
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetAllPoints()
    holder:SetSize(636, 518)
    page = W.Page(holder)
    page.holder = holder
    self.pages[key] = page
    local builder = self["Build_" .. key]
    if builder then builder(self, page) end
    return page
end

function Cfg:Show(key)
    self:Build()
    key = key or self.current or "general"
    W.CloseDropdown()
    for k, p in pairs(self.pages) do p.holder:Hide() end
    local page = self:Page(key)
    page.holder:Show()
    page:Refresh()
    for k, b in pairs(self.tabs) do b:SetSelected(k == key) end
    self.current = key
    self.profileLabel:SetText("Profile: " .. (VMH.Profiles:Current() or "?"))
    self.frame:Show()
end

function Cfg:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function Cfg:OnSettingsChanged()
    if self.frame and self.frame:IsShown() then self:Show(self.current) end
end

local function check(page, x, label, get, set, tip, keep)
    local w = W.Check(page.frame, label, get, set, tip)
    w:SetWidth(560 - (x or 12))
    page:Place(w, x, 24, keep)
    return w
end

local function slider(page, x, label, minV, maxV, step, get, set, fmt, keep)
    local w = W.Slider(page.frame, label, minV, maxV, step, get, set, fmt)
    page:Place(w, x, 46, keep)
    return w
end

------------------------------------------------------------------------
-- Alert list + editor (shared by Mana & Health, Crowd Control, Aggro)
------------------------------------------------------------------------
function Cfg:AlertSection(page, tab)
    page:Header("Alerts  (click > to edit)")
    local startY = page.y
    local alerts = {}
    for _, a in ipairs(VMH.ALERTS) do if a.tab == tab then alerts[#alerts + 1] = a end end
    local selectButtons = {}
    local editor = self:AlertEditor(page, startY, alerts[1].key)

    for _, a in ipairs(alerts) do
        local key = a.key
        local cb = W.Check(page.frame, a.label, function() return db().alerts[key].enabled end,
            function(v) db().alerts[key].enabled = v end, a.label .. "\nTurn this alert on or off.")
        cb:SetWidth(200)
        page:Place(cb, 12, 0, true)
        local test = W.Button(page.frame, "Test", 40, 20, function()
            VMH.Announce:Alert(key, SAMPLE, { test = true })
        end, "Shows this alert locally (enable 'Test buttons send real chat' to post it).")
        page:Place(test, 214, 0, true)
        local sel = W.Button(page.frame, ">", 24, 20, function() editor:Select(key) end, "Edit this alert")
        page:Place(sel, 258, 25)
        selectButtons[key] = sel
    end
    editor.selectButtons = selectButtons
    page:Track(editor)
    page.y = math.max(page.y, startY + editor.height) + 6
    editor:Select(alerts[1].key)
    return editor
end

function Cfg:AlertEditor(page, startY, firstKey)
    local ed = CreateFrame("Frame", nil, page.frame)
    ed:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 296, -startY + 4)
    ed:SetSize(320, 448)
    W.Fill(ed, { 0.08, 0.055, 0.13, 1 })
    W.Border(ed, C.border)
    ed.height = 454
    ed.key = firstKey -- widgets read their value as soon as they are created
    local function cfg() return db().alerts[ed.key] end
    local y = 8
    local function put(w, h, x)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", ed, "TOPLEFT", x or 10, -y)
        y = y + (h or 24)
        return w
    end
    local widgets = {}
    local function track(w) widgets[#widgets + 1] = w; return w end

    ed.title = put(W.Label(ed, "", 13, C.accent), 22)
    local text = track(W.EditBox(ed, "Announcement text", 300, function() return cfg().text end,
        function(v) if v == "" then v = VMH.ALERT_BY_KEY[ed.key].text end cfg().text = v end))
    local reset = W.Button(ed, "Default text", 90, 16, function()
        cfg().text = VMH.ALERT_BY_KEY[ed.key].text
        text:Refresh()
    end)
    reset:SetPoint("TOPLEFT", ed, "TOPLEFT", 220, -y)
    put(text, 44)
    local note = W.Label(ed, "Tokens: {pct} {dur} {spell} {school} {name} {count}. Unknown values are left out, never guessed.", 10, C.dim)
    note:SetWidth(300)
    put(note, 26)
    put(W.Label(ed, "Channels", 12), 18)
    local col = 0
    for i, ch in ipairs(VMH.CHANNELS) do
        local cb = track(W.Check(ed, ch.label, function() return cfg().channels[ch.key] == true end,
            function(v) cfg().channels[ch.key] = v or nil end))
        cb:SetWidth(140)
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", ed, "TOPLEFT", 10 + col * 150, -y)
        col = col + 1
        if col == 2 or i == #VMH.CHANNELS then col = 0; y = y + 20 end
    end
    y = y + 4
    put(track(W.Slider(ed, "Repeat cooldown", 0, 120, 1, function() return cfg().cooldown end,
        function(v) cfg().cooldown = v end, function(v) return v == 0 and "off" or (v .. "s") end)), 44)
    local soundOpts = {}
    for _, s in ipairs(VMH.SOUNDS) do soundOpts[#soundOpts + 1] = { value = s.key, label = s.label } end
    put(track(W.Dropdown(ed, "Sound", 200, soundOpts, function() return cfg().sound end, function(v) cfg().sound = v end)), 0)
    local play = W.Button(ed, "Play", 50, 20, function() VMH.Announce:PlaySound(cfg().sound) end)
    play:SetPoint("TOPLEFT", ed, "TOPLEFT", 216, -y - 20)
    y = y + 44
    local onscreen = track(W.Check(ed, "On-screen warning", function() return cfg().onscreen end, function(v) cfg().onscreen = v end))
    onscreen:SetWidth(280)
    put(onscreen, 24)
    put(track(W.Dropdown(ed, "Use in", 200, {
        { value = "any", label = "PvE and PvP" }, { value = "pve", label = "PvE only" }, { value = "pvp", label = "PvP only" },
    }, function() return cfg().context end, function(v) cfg().context = v end)), 44)

    -- one threshold slider per alert that has one; only the selected one is shown
    ed.thresholds = {}
    for _, a in ipairs(VMH.ALERTS) do
        if a.threshold then
            local key = a.key
            local s = W.Slider(ed, a.threshold[4], a.threshold[2], a.threshold[3], 1,
                function() return db().alerts[key].threshold end, function(v) db().alerts[key].threshold = v end)
            s:SetPoint("TOPLEFT", ed, "TOPLEFT", 10, -y)
            s:Hide()
            ed.thresholds[key] = s
        end
    end
    y = y + 46
    local test = W.Button(ed, "Test this alert", 120, 22, function()
        VMH.Announce:Alert(ed.key, SAMPLE, { test = true })
    end)
    put(test, 26)

    function ed:Select(key)
        self.key = key
        self.title:SetText(VMH.ALERT_BY_KEY[key].label)
        for k, b in pairs(self.selectButtons or {}) do b:SetSelected(k == key) end
        for k, s in pairs(self.thresholds) do
            if k == key then s:Show(); s:Refresh() else s:Hide() end
        end
        self:Refresh()
    end
    function ed:Refresh()
        if not self.key then return end
        for _, w in ipairs(widgets) do w:Refresh() end
        local s = self.thresholds[self.key]
        if s then s:Refresh() end
    end
    return ed
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
function Cfg:Build_general(page)
    page:Header("General")
    check(page, 12, "Enable VoidMark Healer", function() return db().general.enabled end,
        function(v) db().general.enabled = v end, "Master switch for every alert.")
    page:Place(W.Dropdown(page.frame, "Announce when", 260, {
        { value = "class", label = "I'm a healing class (or healer role)" },
        { value = "role", label = "My group role is Healer" },
        { value = "always", label = "Always" },
    }, function() return db().general.healerOnly end, function(v) db().general.healerOnly = v end), 12, 48)
    check(page, 12, "Debug messages (local only, this session)", function() return VMH.debugMode end,
        function(v) VMH.debugMode = v end)

    page:Header("Testing")
    page:Note("Simulations run through the real detection, countdown and display. Their messages print only in your chat frame.", 30)
    local x = 12
    for _, s in ipairs({ { "Silence", "silence" }, { "Stun", "stun" }, { "Interrupt", "interrupt" },
        { "Overlap", "overlap" }, { "Early removal", "early" }, { "Mana", "mana" } }) do
        local b = W.Button(page.frame, s[1], 92, 22, function() VMH.Commands:Simulate(s[2]) end)
        page:Place(b, x, 0, true)
        x = x + 98
    end
    page:Gap(30)
    local stop = W.Button(page.frame, "Stop simulations", 130, 22, function() VMH.CrowdControl:EndSimulation() end)
    page:Place(stop, 12, 0, true)
    local prev = W.Button(page.frame, "Toggle display preview", 170, 22, function() VMH.Display:SetPreview(not VMH.Display.preview) end)
    page:Place(prev, 150, 32)

    page:Header("Status")
    local summary = W.Label(page.frame, "", 12)
    summary:SetWidth(560)
    page:Place(summary, 12, 22)
    local full = W.Button(page.frame, "Full status in chat", 150, 22, function() VMH.Commands:Handle("status") end,
        "Prints what the game is letting the addon read right now.")
    page:Place(full, 12, 30)
    page.onRefresh = function() summary:SetText(VMH.Commands:ShortStatus()) end

    page:Header("Reset")
    local armed = false
    local resetBtn
    resetBtn = W.Button(page.frame, "Reset all settings", 150, 22, function()
        if not armed then
            armed = true
            resetBtn:SetLabel("Click again to confirm")
            VMH.After(4, function() armed = false; resetBtn:SetLabel("Reset all settings") end)
            return
        end
        armed = false
        resetBtn:SetLabel("Reset all settings")
        VMH.Profiles:ResetAll(false)
        VMH:Print("All settings reset. History kept.")
    end, "Restores every profile to its preset. Statistics are kept.")
    page:Place(resetBtn, 12, 30)
end

function Cfg:Build_mana(page)
    self:AlertSection(page, "mana")
    page:Note("When Forever hides your mana in combat, mana alerts use whether your own spells are castable, and the text leaves the percentage out. Health alerts pause while health is hidden.", 44)
end

function Cfg:Build_aggro(page)
    self:AlertSection(page, "aggro")
    page:Note("Enemy counts use visible enemies: turn enemy nameplates on to see more than your target and focus. Line-of-sight and range names use your mouseover or friendly target.", 44)
end

function Cfg:Build_cc(page)
    self:AlertSection(page, "cc")
    page:Note("Roots are announced but never count as \"healing blocked\". Countdown timing is on the Countdown tab.", 18)
end

function Cfg:Build_countdown(page)
    local cd = function() return db().countdown end
    page:Header("Countdown to healing")
    check(page, 12, "Countdown warnings", function() return cd().enabled end, function(v) cd().enabled = v end)
    check(page, 12, "Smart plan", function() return cd().smart end, function(v) cd().smart = v end,
        "On: 5s warning only for effects of 10s or more, 3s warning for 5s or more.\nOff: every ticked warning that fits inside the effect is used.")
    slider(page, 12, "Shortest effect that gets a countdown", 0, 15, 1, function() return cd().minDuration end,
        function(v) cd().minDuration = v end, function(v) return v .. "s" end)
    page:Note("Warnings to use", 18)
    local x = 12
    for _, t in ipairs({ 10, 5, 3, 2, 1 }) do
        local w = W.Check(page.frame, t .. "s", function() return cd()["warn" .. t] end, function(v) cd()["warn" .. t] = v end)
        w:SetWidth(70)
        page:Place(w, x, 0, true)
        x = x + 80
    end
    page:Gap(28)
    page:Header("Where the countdown shows")
    check(page, 12, "In chat (uses the Countdown warnings alert's channels)", function() return cd().chat end, function(v) cd().chat = v end)
    check(page, 12, "On screen (display header)", function() return cd().onscreen end, function(v) cd().onscreen = v end)
    check(page, 12, "Sound at each warning", function() return cd().sound end, function(v) cd().sound = v end)
    page:Header("Recovery")
    check(page, 12, "Announce when healing resumes", function() return cd().recovery end, function(v) cd().recovery = v end)
    check(page, 12, "Also for effects under 5 seconds", function() return cd().recoveryShort end, function(v) cd().recoveryShort = v end)
    page:Note("Times come from the game and already include diminishing returns, dispels and trinkets. If the game hides a duration, no number is shown and the countdown waits for the effect to end.", 44)
    local b = W.Button(page.frame, "Simulate a 12s fear", 150, 22, function() VMH.Commands:Simulate("countdown") end,
        "Runs locally: chat output is printed only to you.")
    page:Place(b, 12, 30)
end

function Cfg:Build_announce(page)
    local an = function() return db().announce end
    page:Header("Announcements")
    check(page, 12, "Send announcements to group chat", function() return an().outgoing end, function(v) an().outgoing = v end,
        "Off: nothing leaves your client. Self-only and on-screen alerts still work.")
    check(page, 12, "Test buttons send real chat", function() return db().general.testsSendChat end,
        function(v) db().general.testsSendChat = v end)
    page:Place(W.EditBox(page.frame, "Message prefix (optional)", 200, function() return an().prefix end,
        function(v) an().prefix = v end), 12, 48)
    slider(page, 12, "Minimum time between messages", 0.5, 5, 0.5, function() return an().throttle end,
        function(v) an().throttle = v end, function(v) return v .. "s" end)
    slider(page, 12, "Drop identical messages within", 0, 30, 1, function() return an().duplicateWindow end,
        function(v) an().duplicateWindow = v end, function(v) return v .. "s" end)
    slider(page, 12, "Mana/health re-arm margin", 2, 30, 1, function() return an().hysteresis end,
        function(v) an().hysteresis = v end, function(v) return v .. "%" end)

    page:Header("Set channels for every alert")
    local function setAll(channels, keys)
        for key, a in pairs(db().alerts) do
            local ok = true
            if keys then ok = false; for _, k in ipairs(keys) do if k == key then ok = true end end end
            if ok then
                a.channels = {}
                for _, c in ipairs(channels) do a.channels[c] = true end
            end
        end
        VMH:Print("Channels updated.")
    end
    local b1 = W.Button(page.frame, "All: Auto group", 130, 22, function() setAll({ "auto" }) end)
    page:Place(b1, 12, 0, true)
    local b2 = W.Button(page.frame, "All: Self only", 130, 22, function() setAll({ "self" }) end)
    page:Place(b2, 150, 0, true)
    local b3 = W.Button(page.frame, "CC: Party + Raid", 130, 22, function() setAll({ "party", "raid" }, VMH.CC_KEYS) end)
    page:Place(b3, 288, 30)
    page:Note("Messages go only to Party, Raid, Instance/Battleground, Say or Yell. Never General, Trade or guild.", 18)
    page:Note("The game only allows addon Say/Yell inside instances; outside, those channels are skipped.", 18)
    page:Note("If several channels reach the same people (Raid + Party, Instance + Party), only one message is sent.", 18)
    page:Note("Crowd control and recovery always go ahead of routine mana/health messages.", 18)
end

function Cfg:Build_visuals(page)
    local d = function() return db().display end
    local function relayout() VMH.Display:ApplyLayout() end
    page:Header("Warnings & sounds")
    check(page, 12, "On-screen warnings", function() return db().visuals.onscreen end, function(v) db().visuals.onscreen = v end)
    check(page, 12, "Sounds", function() return db().visuals.sound end, function(v) db().visuals.sound = v end)
    page:Place(W.Dropdown(page.frame, "Sound channel", 160, {
        { value = "Master", label = "Master" }, { value = "SFX", label = "Effects" }, { value = "Dialog", label = "Dialog" },
    }, function() return db().visuals.soundChannel end, function(v) db().visuals.soundChannel = v end), 12, 48)

    page:Header("Crowd-control display")
    local w
    w = check(page, 12, "Show display", function() return d().enabled end, function(v) d().enabled = v end); w.onChange = relayout
    w = check(page, 12, "Lock position", function() return d().locked end, function(v) d().locked = v end); w.onChange = relayout
    w = check(page, 12, "Show outside combat", function() return d().showOutOfCombat end, function(v) d().showOutOfCombat = v end); w.onChange = relayout
    local pv = W.Button(page.frame, "Toggle preview", 120, 22, function() VMH.Display:SetPreview(not VMH.Display.preview) end)
    page:Place(pv, 12, 0, true)
    local rp = W.Button(page.frame, "Reset position", 120, 22, function()
        d().point, d().relPoint, d().x, d().y = "CENTER", "CENTER", 0, 180
        relayout()
    end)
    page:Place(rp, 140, 30)
    local sliders = {
        { "Scale", 0.5, 2, 0.05, "scale" }, { "Opacity", 0.2, 1, 0.05, "alpha" }, { "Font size", 8, 20, 1, "fontSize" },
        { "Icon size", 16, 48, 1, "iconSize" }, { "Bar width", 100, 400, 5, "barWidth" }, { "Bar height", 6, 30, 1, "barHeight" },
        { "Rows shown", 1, 8, 1, "maxRows" },
    }
    for i, s in ipairs(sliders) do
        local key = s[5]
        local sl = W.Slider(page.frame, s[1], s[2], s[3], s[4], function() return d()[key] end, function(v) d()[key] = v end)
        sl.onChange = relayout
        page:Place(sl, (i % 2 == 1) and 12 or 300, 46, i % 2 == 1 and i ~= #sliders)
    end
    page:Gap(4)
    local colors = { { "Healing blocked", "colorBlocked" }, { "School lockout", "colorLockout" },
        { "Movement only", "colorMovement" }, { "Background", "colorBackground" } }
    for i, c in ipairs(colors) do
        local key = c[2]
        local cw = W.Color(page.frame, c[1], function() return d()[key] end, function(v) d()[key] = v end)
        cw.onChange = relayout
        page:Place(cw, (i % 2 == 1) and 12 or 300, 26, i % 2 == 1)
    end
end

function Cfg:Build_profiles(page)
    local P = VMH.Profiles
    local function names()
        local out = {}
        for _, n in ipairs(P:List()) do out[#out + 1] = { value = n, label = n } end
        return out
    end
    page:Header("Active profile")
    page:Place(W.Dropdown(page.frame, "Profile for this character", 240, names, function() return P:Current() end,
        function(v) P:Select(v) end), 12, 48)
    page:Note("Profiles are shared by all characters on this account. Each character picks its own.", 18)
    local reset = W.Button(page.frame, "Reset to defaults", 140, 22, function()
        P:ResetProfile()
        VMH:Print("Profile reset: " .. P:Current())
    end)
    page:Place(reset, 12, 0, true)
    local charBtn = W.Button(page.frame, "Make character profile", 170, 22, function()
        VMH:Print("Using profile: " .. P:MakeCharacterProfile())
    end, "Copies the current settings into a profile only this character uses (turns auto-switch off).")
    page:Place(charBtn, 160, 0, true)
    local del = W.Button(page.frame, "Delete profile", 120, 22, function()
        local name = P:Current()
        if P:Delete(name) then VMH:Print("Deleted profile " .. name) else VMH:Print("Preset profiles can't be deleted (use Reset).") end
    end)
    page:Place(del, 338, 32)

    local copyFrom = "Dungeon"
    page:Place(W.Dropdown(page.frame, "Copy settings from", 180, names, function() return copyFrom end,
        function(v) copyFrom = v end), 12, 0, true)
    local copy = W.Button(page.frame, "Copy into current", 140, 20, function()
        if P:Copy(copyFrom) then VMH:Print("Copied " .. copyFrom .. " into " .. P:Current()) end
    end)
    page:Place(copy, 200, 0, true, 20)
    page:Gap(48)
    local newName = ""
    page:Place(W.EditBox(page.frame, "New profile name", 180, function() return newName end, function(v) newName = v end), 12, 0, true)
    local create = W.Button(page.frame, "Create", 80, 20, function()
        if P:Create(newName) then P:Select(newName) else VMH:Print("Enter a new, unused name.") end
    end)
    page:Place(create, 200, 0, true, 20)
    page:Gap(48)

    page:Header("Automatic switching")
    check(page, 12, "Switch profile by location", function() return VMH.csv.autoSwitch end, function(v) VMH.csv.autoSwitch = v end)
    local map = { { "party", "Dungeon / 5-man" }, { "raid", "Raid" }, { "pvp", "Battleground" }, { "arena", "Arena" },
        { "worldGroup", "World, in a group" }, { "world", "World, solo" } }
    for i, m in ipairs(map) do
        local key = m[1]
        local dd = W.Dropdown(page.frame, m[2], 180, names, function() return VMH.csv.autoMap[key] end,
            function(v) VMH.csv.autoMap[key] = v end)
        page:Place(dd, (i % 2 == 1) and 12 or 300, 48, i % 2 == 1)
    end
end

function Cfg:Build_history(page)
    local H = VMH.History
    page:Header("Statistics")
    check(page, 12, "Track statistics", function() return db().history.enabled end, function(v) db().history.enabled = v end)
    page:Header("This session")
    local session = W.Label(page.frame, "", 12)
    session:SetWidth(580)
    session:SetJustifyV("TOP")
    page:Place(session, 12, 120)
    page:Header("Lifetime (this account)")
    local life = W.Label(page.frame, "", 12)
    life:SetWidth(580)
    life:SetJustifyV("TOP")
    page:Place(life, 12, 120)
    local r1 = W.Button(page.frame, "Reset session", 120, 22, function() H:Reset("session"); page:Refresh() end)
    page:Place(r1, 12, 0, true)
    local armed = false
    local r2
    r2 = W.Button(page.frame, "Reset lifetime", 140, 22, function()
        if not armed then
            armed = true
            r2:SetLabel("Click again to confirm")
            VMH.After(4, function() armed = false; r2:SetLabel("Reset lifetime") end)
            return
        end
        armed = false
        r2:SetLabel("Reset lifetime")
        H:Reset("lifetime")
        page:Refresh()
    end)
    page:Place(r2, 140, 30)
    page:Note("Interrupters and crowd-control casters are named only when the game shows them (visible enemy or aura caster).", 18)
    page.onRefresh = function()
        session:SetText(H:Summary(H.session))
        life:SetText(H:Summary(VMH.sv.history.lifetime))
    end
end
