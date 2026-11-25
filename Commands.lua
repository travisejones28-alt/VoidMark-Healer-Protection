-- VoidMark Healer - slash commands, simulations and status
-- Simulations feed the real crowd-control pipeline (detection merge,
-- countdown, display, history exclusion). Their messages are printed locally
-- with a [SIM] tag and are never sent to any group channel.
local _, VMH = ...
local Cmd = VMH:NewModule("Commands")

local after = VMH.After

local SIMS = {
    silence = function()
        VMH.CrowdControl:Simulate({ type = "SILENCE", spellID = 15487, duration = 8 })
    end,
    stun = function()
        VMH.CrowdControl:Simulate({ type = "STUN", spellID = 408, duration = 6, source = "Simulated Rogue" })
    end,
    interrupt = function()
        VMH.CrowdControl:Simulate({ type = "LOCKOUT", spellID = 1766, name = "Kick", school = 2, duration = 5, source = "Simulated Rogue" })
    end,
    countdown = function()
        VMH.CrowdControl:Simulate({ type = "FEAR", spellID = 8122, duration = 12 })
    end,
    overlap = function()
        VMH.CrowdControl:Simulate({ type = "STUN", spellID = 408, duration = 4 })
        after(1, function() VMH.CrowdControl:Simulate({ type = "SILENCE", spellID = 15487, duration = 8 }) end)
        after(1.5, function() VMH.CrowdControl:Simulate({ type = "ROOT", spellID = 122, duration = 12 }) end)
    end,
    early = function()
        local key = VMH.CrowdControl:Simulate({ type = "POLYMORPH", spellID = 118, duration = 10 })
        after(3, function()
            VMH:Print("|cffffd200[SIM]|r Polymorph dispelled early.")
            VMH.CrowdControl:EndSimulation(key)
        end)
    end,
    unknown = function()
        local key = VMH.CrowdControl:Simulate({ type = "STUN", spellID = 853, duration = nil })
        after(4, function() VMH.CrowdControl:EndSimulation(key) end)
    end,
    mana = function()
        local A = VMH.Announce
        A:Alert("lowMana", { pct = 28 }, { sim = true })
        after(1.5, function() A:Alert("oom", { pct = 8 }, { sim = true }) end)
        after(3, function() A:Alert("drinking", { pct = 8 }, { sim = true }) end)
        after(4.5, function() A:Alert("drinkDone", { pct = 100 }, { sim = true }) end)
        after(5, function() A:Alert("manaRecovered", { pct = 100 }, { sim = true }) end)
    end,
}
SIMS.cc = SIMS.overlap

function Cmd:Simulate(name)
    local fn = SIMS[name]
    if not fn then
        VMH:Print("Simulations: silence, stun, interrupt, countdown, overlap, early, unknown, mana, all")
        return
    end
    VMH:Print("|cffffd200Simulation:|r " .. name .. " (local only)")
    fn()
end

function Cmd:SimulateAll()
    local order = { "silence", "interrupt", "overlap", "early", "mana" }
    local t = 0
    for _, n in ipairs(order) do
        after(t, function() Cmd:Simulate(n) end)
        t = t + 13
    end
end

local function yesno(v) return v and "|cff40ff40yes|r" or "|cffff5050no|r" end

function Cmd:StatusText()
    local cc = VMH.CrowdControl.capability
    local ctx = VMH:GetContext()
    local mana = VMH.Mana:Percent()
    local hp = VMH.Health:Percent()
    local lines = {
        "Version " .. VMH.version .. "   Profile: " .. tostring(VMH.Profiles:Current()) .. "   Enabled: " .. yesno(VMH.db.general.enabled),
        "Running here: " .. yesno(VMH:IsActiveHere()) .. "   Healer alerts active: " .. yesno(VMH:IsHealerActive()) .. "   Location: " .. ctx.instanceType .. (ctx.pvp and " (PvP)" or "") ..
            "   Group: " .. (ctx.raid and "raid" or (ctx.grouped and "party" or "none")),
        "Loss of Control data readable: " .. yesno(cc.loc) .. "   Auras readable: " .. yesno(not VMH.AurasHidden()),
        "Mana readable: " .. (mana and (mana .. "%") or "|cffff5050hidden - spell fallback|r") ..
            "   Health readable: " .. (hp and (hp .. "%") or "|cffff5050hidden|r"),
        "Group chat locked by the game: " .. yesno(VMH.Announce.ChatLocked()) .. "   Visible enemies on you: " .. VMH.Threat.attackers,
        "Active effects: " .. (function() local n = 0 for _ in pairs(VMH.CrowdControl.active) do n = n + 1 end return n end)() ..
            "   Healing blocked: " .. yesno(VMH.Countdown.block ~= nil),
    }
    return table.concat(lines, "\n")
end

-- One plain line for the General tab.
function Cmd:ShortStatus()
    if not VMH.db.general.enabled then return "|cffff5050Turned off|r (Enable VoidMark Healer above)." end
    if not VMH:IsActiveHere() then
        local label = VMH.sv.runIn
        for _, o in ipairs(VMH.RUN_IN) do if o.value == VMH.sv.runIn then label = o.label end end
        return "|cffffd200Paused here|r - set to run in: " .. label .. "."
    end
    if not VMH:IsHealerActive() then
        return "|cffffd200Waiting|r - alerts start when you're healing (see \"Announce when\")."
    end
    local cc = VMH.CrowdControl.capability
    if not cc.loc and VMH.AurasHidden() then
        return "|cffffd200Limited|r - the game is hiding crowd-control data right now."
    end
    return "|cff40ff40Ready|r - profile " .. tostring(VMH.Profiles:Current()) .. "."
end

local HELP = {
    "/vmh - open settings",
    "/vmh test [silence|stun|interrupt|countdown|overlap|early|unknown|mana|all] - simulate (local only)",
    "/vmh stop - end simulations",
    "/vmh preview - toggle the display preview",
    "/vmh status - detection and API status",
    "/vmh world - toggle open-world use on/off",
    "/vmh debug - toggle local debug messages   /vmh debug log - show recent debug lines",
    "/vmh reset confirm - reset all settings (statistics kept)",
}

function Cmd:Handle(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "config" or cmd == "options" then
        VMH.Config:Toggle()
    elseif cmd == "help" then
        for _, l in ipairs(HELP) do VMH:Print(l) end
    elseif cmd == "test" or cmd == "sim" then
        if rest == "all" then self:SimulateAll()
        elseif rest == "" then
            VMH:Print("Try: /vmh test silence | stun | interrupt | countdown | overlap | early | unknown | mana | all")
            self:Simulate("silence")
        else self:Simulate(rest) end
    elseif cmd == "stop" then
        VMH.CrowdControl:EndSimulation()
        VMH:Print("Simulations stopped.")
    elseif cmd == "preview" then
        VMH.Display:SetPreview(not VMH.Display.preview)
        VMH:Print("Display preview " .. (VMH.Display.preview and "on" or "off"))
    elseif cmd == "world" then
        VMH.sv.runIn = (VMH.sv.runIn == "everywhere") and "dungeonraid" or "everywhere"
        VMH:Print(VMH.sv.runIn == "everywhere" and "Now running everywhere, open world included."
            or "Now running in dungeons and raids only.")
        VMH:QueueAuraScan()
    elseif cmd == "status" then
        for line in self:StatusText():gmatch("[^\n]+") do VMH:Print(line) end
    elseif cmd == "debug" then
        if rest == "log" then
            local log = VMH.debugLog
            VMH:Print("Last " .. math.min(25, #log) .. " lines (saved across /reload):")
            for i = math.max(1, #log - 24), #log do VMH:Print("|cff888888" .. log[i] .. "|r") end
        elseif rest == "clear" then
            for i = #VMH.debugLog, 1, -1 do VMH.debugLog[i] = nil end
            VMH:Print("Debug trail cleared.")
        else
            VMH.debugMode = not VMH.debugMode
            VMH:Print("Debug " .. (VMH.debugMode and "on (local only)" or "off"))
        end
    elseif cmd == "reset" then
        if rest == "confirm" then
            VMH.CrowdControl:EndSimulation()
            VMH.Profiles:ResetAll(false)
            VMH:Print("All settings reset to defaults. Statistics kept.")
        else
            VMH:Print("Type /vmh reset confirm to reset every setting.")
        end
    else
        for _, l in ipairs(HELP) do VMH:Print(l) end
    end
end

function Cmd:Init()
    _G.SLASH_VOIDMARKHEALER1 = "/vmh"
    _G.SLASH_VOIDMARKHEALER2 = "/voidmarkhealer"
    _G.SlashCmdList = _G.SlashCmdList or {}
    _G.SlashCmdList.VOIDMARKHEALER = function(msg) Cmd:Handle(msg) end
end
