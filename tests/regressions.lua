-- Offline regressions. Run through tests/validate.py (Lua 5.1 via lupa).
local passed, failed = 0, {}
local function test(name, fn)
    ResetState()
    TIMERS = {}
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed[#failed + 1] = name .. ": " .. tostring(err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end
local function chatTexts()
    local t = {}
    for _, c in ipairs(S.chat) do t[#t + 1] = c.type .. ":" .. c.msg end
    return t
end
local function has(list, needle)
    for _, v in ipairs(list) do if tostring(v):find(needle, 1, true) then return true end end
    return false
end
local function count(list, needle)
    local n = 0
    for _, v in ipairs(list) do if tostring(v):find(needle, 1, true) then n = n + 1 end end
    return n
end
local function noErrors()
    for _, l in ipairs(VMH.debugLog) do
        if l:find("error") or l:find("failed") then error("module error logged: " .. l, 2) end
    end
end

-- Load the addon exactly as the TOC lists it.
VMH = {}
local addonName = "VoidMarkHealer"
for _, file in ipairs(TOC_FILES) do
    local chunk = assert(loadfile(ROOT .. "/" .. file))
    chunk(addonName, VMH)
end
local function boot()
    VoidMarkHealerDB, VoidMarkHealerCharDB = nil, nil
    Emit("ADDON_LOADED", addonName)
    Emit("PLAYER_ENTERING_WORLD", true, false)
    Advance(0.5)
end
local function fresh()
    -- reset runtime state between tests without reloading files
    VMH.loaded = false
    VMH.CrowdControl.active, VMH.CrowdControl.external, VMH.CrowdControl.sims = {}, {}, {}
    VMH.Countdown.block = nil
    VMH.Announce.last, VMH.Announce.recent, VMH.Announce.queue, VMH.Announce.lastSend = {}, {}, {}, -100
    VMH.Announce.flushScheduled = false
    VMH.Mana.state, VMH.Mana.drinking, VMH.Mana.needRecover, VMH.Mana.peakMax = "ok", false, false, 0
    VMH.Health.state, VMH.Health.dead = "ok", false
    VMH.Threat.aggro, VMH.Threat.multi, VMH.Threat.threatHigh = false, false, false
    VMH.Display.preview = false
    VMH.debugLog = {}
    for k in pairs(VMH.Mana) do if k == "pending" then VMH.Mana.pending = false end end
    VMH.Health.pending, VMH.Threat.pending = false, false
    boot()
    S.chat, S.prints, S.warnings = {}, {}, {}
end
local function addLoC(locType, spellID, duration, school, text)
    local e = { locType = locType, spellID = spellID, displayText = text or locType, iconTexture = 1, startTime = NOW,
        duration = duration, lockoutSchool = school or 0 }
    S.loc[#S.loc + 1] = e
    Emit("LOSS_OF_CONTROL_ADDED")
    Emit("UNIT_AURA", "player")
    return e
end
local function removeLoC(e)
    for i, x in ipairs(S.loc) do if x == e then table.remove(S.loc, i) end end
    Emit("LOSS_OF_CONTROL_UPDATE")
    Emit("UNIT_AURA", "player")
end
local function expireLoC()
    for i = #S.loc, 1, -1 do
        local d = S.loc[i]
        if d.duration ~= SECRET and d.startTime + d.duration <= NOW then table.remove(S.loc, i) end
    end
    Emit("LOSS_OF_CONTROL_UPDATE")
end
-- advance in small steps, expiring Loss of Control entries like the client does
local function play(sec)
    local target = NOW + sec
    while NOW < target - 1e-9 do
        Advance(math.min(0.1, target - NOW))
        expireLoC()
    end
    Advance(0.2)
end

test("loads and boots cleanly", function()
    fresh()
    assert(VMH.loaded, "not loaded")
    assert(SlashCmdList.VOIDMARKHEALER, "slash missing")
    eq(VMH.Profiles:Current(), "Dungeon", "grouped world profile")
    noErrors()
end)

test("formatter never shows missing values", function()
    local F = VMH.Announce.Format
    eq(F("Healer silenced! ({dur})", {}), "Healer silenced!")
    eq(F("Healer silenced! ({dur})", { dur = "8s" }), "Healer silenced! (8s)")
    eq(F("Out of mana! ({pct}%)", { pct = 8 }), "Out of mana! (8%)")
    eq(F("Out of mana! ({pct}%)", {}), "Out of mana!")
    eq(F("Healer incapacitated! ({spell}, {dur})", { spell = "Gouge" }), "Healer incapacitated! (Gouge)")
    eq(F("Healer free - healing resumed! {note}", {}), "Healer free - healing resumed!")
end)

test("silence: one announcement, 3s warning, recovery", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    local e = addLoC("SILENCE", 15487, 8)
    Emit("UNIT_AURA", "player")
    Advance(0.3)
    local c = chatTexts()
    eq(count(c, "Healer silenced! (8s)"), 1, "single silence message")
    eq(c[1]:sub(1, 6), "PARTY:", "party channel")
    play(5.2)
    c = chatTexts()
    eq(count(c, "Healing resumes in 3s!"), 1, "3s warning")
    eq(count(c, "resumes in 5s"), 0, "no 5s warning for 8s effect")
    play(3)
    c = chatTexts()
    eq(count(c, "Healer free - healing resumed!"), 1, "recovery")
    noErrors()
end)

test("overlap: no recovery until the last effect ends; root does not block", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    addLoC("STUN", 408, 4)
    Advance(1)
    addLoC("SILENCE", 15487, 8)
    addLoC("ROOT", 122, 12)
    play(4)
    eq(count(chatTexts(), "healing resumed"), 0, "no recovery while silenced")
    play(5)
    local c = chatTexts()
    eq(count(c, "Healer free - healing resumed! (still rooted)"), 1, "recovery once, notes root")
    eq(count(c, "Healer rooted!"), 0, "root is local-only by default")
    assert(has(S.prints, "Healer rooted! (12s)"), "root shown locally")
end)

test("early dispel cancels countdown immediately", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    local e = addLoC("CONFUSE", 118, 10, 0, "Polymorphed")
    Advance(0.3)
    eq(count(chatTexts(), "Healer polymorphed! (10s)"), 1, "poly announce")
    Advance(2)
    removeLoC(e)
    Advance(0.3)
    eq(count(chatTexts(), "healing resumed"), 1, "recovered right away")
    play(9)
    eq(count(chatTexts(), "Healing resumes in"), 0, "no stale countdown")
    assert(not VMH.Countdown.block, "block cleared")
end)

test("long fear gets 5s and 3s warnings", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    addLoC("FEAR", 8122, 12)
    play(12.5)
    local c = chatTexts()
    eq(count(c, "Healing resumes in 5s!"), 1)
    eq(count(c, "Healing resumes in 3s!"), 1)
end)

test("unknown duration: no number, no countdown, recovery at end", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    local e = addLoC("STUN", 853, SECRET)
    e.startTime = SECRET
    Advance(0.3)
    local c = chatTexts()
    eq(count(c, "Healer stunned!"), 1)
    assert(not has(c, "stunned! ("), "no fabricated duration")
    Advance(4)
    eq(count(chatTexts(), "resumes in"), 0)
    removeLoC(e)
    Advance(0.3)
    eq(count(chatTexts(), "healing resumed"), 1)
    noErrors()
end)

test("secret Loss of Control + hidden auras: no errors, no alerts", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.locSecret = true
    S.aurasHidden = true
    S.hpSecret = true
    Emit("LOSS_OF_CONTROL_ADDED")
    Emit("UNIT_AURA", "player")
    Emit("UNIT_HEALTH", "player")
    Advance(1)
    eq(#S.chat, 0)
    noErrors()
end)

test("aura fallback names the caster", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.units.nameplate1 = { name = "Sneaky", surname = "Stabber", hostile = true, isPlayer = true, guid = "P-1" }
    S.auras.HARMFUL[1] = { name = "Kidney Shot", spellId = 408, duration = 5, expirationTime = NOW + 5, sourceUnit = "nameplate1", icon = 1 }
    Emit("UNIT_AURA", "player")
    Advance(0.3)
    eq(count(chatTexts(), "Healer stunned! (5s)"), 1)
    eq(VMH.History.session.sources["Sneaky Stabber"], 1, "caster recorded with full name")
end)

test("mana: thresholds, hysteresis, recovery", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    local function setMana(p) S.mana = p * 50; Emit("UNIT_POWER_UPDATE", "player"); Advance(0.5) end
    setMana(25)
    eq(count(chatTexts(), "Low mana (25%)"), 1)
    setMana(31); setMana(29); setMana(32); setMana(28)
    eq(count(chatTexts(), "Low mana"), 1, "no flapping")
    setMana(8)
    eq(count(chatTexts(), "Out of mana! (8%)"), 1)
    setMana(65)
    -- manaRecovered defaults to self only
    assert(has(S.prints, "Mana recovered (65%)"), "recovered printed locally")
    Advance(21) -- past the alert's repeat cooldown
    setMana(25)
    eq(count(chatTexts(), "Low mana (25%)"), 2, "re-armed after recovery")
end)

test("mana hidden: spell-usability fallback without a percentage", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.spellbook = { 2050, 2061, 2060 }
    S.costs = { [2050] = 75, [2061] = 380, [2060] = 710 }
    Emit("SPELLS_CHANGED")
    Emit("UNIT_POWER_UPDATE", "player")
    Advance(0.5)
    S.inCombat = true
    S.manaSecret = true
    S.usable = { [2050] = { usable = false, noMana = true }, [2061] = { usable = false, noMana = true }, [2060] = { usable = false, noMana = true } }
    Emit("SPELL_UPDATE_USABLE")
    Advance(0.5)
    local c = chatTexts()
    eq(count(c, "Out of mana!"), 1)
    assert(not has(c, "%)"), "no percentage when hidden")
    noErrors()
end)

test("channels: raid dedupe, self only, say outside instance skipped", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    S.raid = true
    VMH.db.alerts.silence.channels = { auto = true, party = true, raid = true, say = true }
    VMH.Announce:Alert("silence", { dur = "8s" })
    Advance(0.2)
    local c = chatTexts()
    eq(#c, 1, "one message")
    eq(c[1], "RAID:Healer silenced! (8s)")
    S.chat = {}
    S.raid = false
    S.homeGroup = false
    S.instanceGroup = true
    S.instance, S.instanceType = true, "party"
    VMH.db.alerts.stun.channels = { auto = true, party = true }
    VMH.Announce:Alert("stun", { dur = "4s" })
    Advance(1.2)
    eq(chatTexts()[1], "INSTANCE_CHAT:Healer stunned! (4s)")
    S.chat = {}
    VMH.db.alerts.fear.channels = { self = true }
    VMH.Announce:Alert("fear", {})
    Advance(0.2)
    eq(#S.chat, 0)
    assert(has(S.prints, "Healer feared!"))
end)

test("priority: crowd control jumps ahead of routine alerts", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    VMH.db.alerts.lowMana.channels = { auto = true }
    VMH.Announce.lastSend = NOW -- force queuing
    VMH.Announce:Alert("lowMana", { pct = 20 })
    VMH.Announce:Alert("silence", { dur = "8s" })
    Advance(3)
    local c = chatTexts()
    assert(c[1]:find("silenced"), "silence first, got " .. tostring(c[1]))
    assert(c[2] and c[2]:find("Low mana"), "low mana second")
end)

test("chat lockdown: nothing sent, shown locally", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    S.chatLocked = true
    VMH.Announce:Alert("silence", { dur = "8s" })
    Advance(0.3)
    eq(#S.chat, 0)
    assert(has(S.prints, "Healer silenced! (8s)"))
end)

test("simulations stay local and are not recorded", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    SlashCmdList.VOIDMARKHEALER("test overlap")
    Advance(12)
    SlashCmdList.VOIDMARKHEALER("test early")
    Advance(12)
    SlashCmdList.VOIDMARKHEALER("test mana")
    SlashCmdList.VOIDMARKHEALER("test interrupt")
    SlashCmdList.VOIDMARKHEALER("test unknown")
    Advance(12)
    eq(#S.chat, 0, "no group chat from simulations")
    eq(VMH.History.session.cc, 0)
    eq(VMH.History.session.blockedTime, 0)
    assert(has(S.prints, "[SIM -> PARTY]|r Healer silenced! (8s)"), "sim silence shown")
    assert(has(S.prints, "healing resumed! (still rooted)"), "sim overlap recovery")
    noErrors()
end)

test("interrupt fallback: cooldown probe proves lockout and names the kicker", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.locSecret = true
    S.units.nameplate2 = { name = "Kicky", surname = "McKick", hostile = true, isPlayer = true, guid = "P-2", targetsPlayer = true }
    Emit("UNIT_SPELLCAST_SUCCEEDED", "nameplate2", "cast-1", 1766)
    S.cooldowns[2061] = { NOW, 4 }
    Emit("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-2", 2061)
    Advance(0.4)
    local c = chatTexts()
    eq(count(c, "Healer interrupted! Holy school locked out (4s)"), 1, table.concat(c, " | "))
    eq(VMH.History.session.interrupters["Kicky McKick"], 1)
    play(4.5)
    eq(count(chatTexts(), "healing resumed"), 0, "short (<5s) recovery off by default")
end)

test("interrupt without a lockout is not reported", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.locSecret = true
    Emit("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-3", 2061)
    Advance(0.5)
    eq(#S.chat, 0)
end)

test("line of sight: names mouseover friend, local by default", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    S.units.mouseover = { name = "Tank", surname = "Person", hostile = false }
    Emit("UI_ERROR_MESSAGE", 50, SPELL_FAILED_LINE_OF_SIGHT)
    Advance(0.2)
    assert(has(S.prints, "Can't heal - out of line of sight (Tank Person)"))
    eq(#S.chat, 0)
end)

test("death clears countdown without recovery; revive announced", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.soulstone = "Use Soulstone"
    addLoC("STUN", 408, 6)
    Advance(1)
    S.dead = true
    S.loc = {}
    Emit("PLAYER_DEAD")
    Advance(2)
    local c = chatTexts()
    eq(count(c, "Healer is dead!"), 1)
    eq(count(c, "can self-resurrect (Use Soulstone)"), 1)
    eq(count(c, "healing resumed"), 0)
    S.dead = false
    Emit("PLAYER_ALIVE")
    Advance(1.5)
    eq(count(chatTexts(), "Healer is back up!"), 1)
    eq(VMH.History.session.deaths, 1)
end)

test("zoning while dead does not re-announce death", function()
    fresh()
    S.dead = true
    Emit("PLAYER_ENTERING_WORLD", false, false)
    Advance(0.5)
    eq(count(chatTexts(), "dead"), 0)
end)

test("multiple enemies on the healer", function()
    fresh()
    VMH.Profiles:Select("PvP", true)
    S.plates = { "nameplate1", "nameplate2" }
    S.units.nameplate1 = { name = "A", hostile = true, isPlayer = true, guid = "A", targetsPlayer = true }
    S.units.nameplate2 = { name = "B", hostile = true, isPlayer = true, guid = "B", targetsPlayer = true }
    Emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
    Advance(0.5)
    eq(count(chatTexts(), "2 enemies on the healer!"), 1)
end)

test("drinking announce and finish", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.mana = 2000
    S.auras.HELPFUL[1] = { name = "Drink", spellId = 430 }
    Emit("UNIT_AURA", "player")
    Advance(0.3)
    eq(count(chatTexts(), "Drinking (40% mana)"), 1)
    S.auras.HELPFUL = {}
    S.mana = 5000
    Emit("UNIT_AURA", "player")
    Advance(0.3)
    assert(has(S.prints, "Done drinking (100% mana)"))
end)

test("auto profile switching", function()
    fresh()
    S.raid, S.instance, S.instanceType = true, true, "raid"
    Emit("ZONE_CHANGED_NEW_AREA")
    eq(VMH.Profiles:Current(), "Raid")
    S.raid, S.instanceType = false, "pvp"
    Emit("GROUP_ROSTER_UPDATE")
    eq(VMH.Profiles:Current(), "PvP")
    S.instance, S.instanceType = false, "none"
    S.homeGroup = false
    Emit("ZONE_CHANGED_NEW_AREA")
    eq(VMH.Profiles:Current(), "Solo")
    -- Solo is local only
    VMH.Announce:Alert("silence", { dur = "8s" })
    Advance(0.3)
    eq(#S.chat, 0)
end)

test("profiles: create, copy, character profile, delete, saved data upgrade", function()
    fresh()
    local P = VMH.Profiles
    assert(P:Create("Mine"))
    assert(not P:Create("Mine"), "no duplicates")
    P:Select("Mine", true)
    VMH.db.alerts.silence.text = "Custom silence {dur}"
    assert(P:Copy("Dungeon"))
    eq(VMH.db.alerts.silence.text, "Healer silenced! ({dur})")
    local cp = P:MakeCharacterProfile()
    eq(cp, "Char: Voidmark Soulreaver - Forever")
    eq(VMH.csv.autoSwitch, false)
    assert(not P:Delete("Dungeon"), "presets protected")
    assert(P:Delete(cp))
    -- older saved profile missing new keys gets them filled
    VoidMarkHealerDB.profiles.Old = { general = { enabled = true }, alerts = { silence = { enabled = false, channels = { self = true } } } }
    P:Load()
    eq(VoidMarkHealerDB.profiles.Old.alerts.silence.enabled, false, "user value kept")
    eq(VoidMarkHealerDB.profiles.Old.alerts.silence.channels.auto, nil, "channel set not merged")
    assert(VoidMarkHealerDB.profiles.Old.countdown.warn3 ~= nil, "new keys filled")
end)

test("shadowform priest is treated as not healing", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.auras.HELPFUL[1] = { name = "Shadowform", spellId = 15473 }
    addLoC("STUN", 408, 6)
    Advance(0.5)
    eq(#S.chat, 0)
    VMH.db.general.healerOnly = "always"
    addLoC("SILENCE", 15487, 6)
    Advance(0.5)
    eq(count(chatTexts(), "silenced"), 1)
end)

test("manual profile choice survives roster updates", function()
    fresh()
    VMH.Profiles:Select("PvP", true)
    Emit("GROUP_ROSTER_UPDATE")
    eq(VMH.Profiles:Current(), "PvP")
end)

test("everything secret: no Lua errors anywhere", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    local saved = {}
    local names = { "UnitName", "UnitIsUnit", "UnitCanAttack", "UnitThreatSituation", "UnitGUID", "UnitIsPlayer",
        "UnitIsDeadOrGhost", "UnitPowerType", "IsInInstance", "UnitGroupRolesAssigned", "UnitAffectingCombat" }
    for _, n in ipairs(names) do saved[n] = _G[n]; _G[n] = function() return SECRET, SECRET end end
    local savedAura = C_UnitAuras.GetAuraDataByIndex
    C_UnitAuras.GetAuraDataByIndex = function(_, i) if i <= 3 then return { spellId = SECRET, name = SECRET, sourceUnit = SECRET, expirationTime = SECRET, duration = SECRET } end end
    local savedLoc = C_LossOfControl.GetActiveLossOfControlData
    S.loc = { {} }
    C_LossOfControl.GetActiveLossOfControlData = function() return { locType = SECRET, spellID = SECRET, timeRemaining = SECRET, duration = SECRET } end
    local savedCd = C_Spell.GetSpellCooldown
    C_Spell.GetSpellCooldown = function() return { startTime = SECRET, duration = SECRET } end
    S.hpSecret, S.manaSecret = true, true
    S.plates = { "nameplate1" }
    local ok, err = pcall(function()
        for _, ev in ipairs({ "LOSS_OF_CONTROL_ADDED", "PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE", "SPELL_UPDATE_USABLE",
            "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED" }) do Emit(ev) end
        Emit("UNIT_AURA", "player")
        Emit("UNIT_HEALTH", "player")
        Emit("UNIT_POWER_UPDATE", "player")
        Emit("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "x", SECRET)
        Emit("UNIT_SPELLCAST_INTERRUPTED", "player", "x", 2061)
        Emit("UI_ERROR_MESSAGE", SECRET, SECRET)
        Emit("UNIT_TARGET", "nameplate1")
        Advance(2)
        SlashCmdList.VOIDMARKHEALER("status")
        VMH.Config:Show("general")
    end)
    for n, f in pairs(saved) do _G[n] = f end
    C_UnitAuras.GetAuraDataByIndex = savedAura
    C_LossOfControl.GetActiveLossOfControlData = savedLoc
    C_Spell.GetSpellCooldown = savedCd
    assert(ok, err)
    noErrors()
end)

test("not a healer: alerts held back", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.class = "WARRIOR"
    addLoC("STUN", 408, 6)
    Advance(0.5)
    eq(#S.chat, 0)
    S.class = "PRIEST"
end)

test("config window builds every tab and widgets respond", function()
    fresh()
    if VMH.Config.frame then VMH.Config.frame:Hide() end
    SlashCmdList.VOIDMARKHEALER("")
    local C = VMH.Config
    assert(C.frame.shown, "window shown")
    for _, k in ipairs({ "general", "mana", "cc", "aggro", "announce", "visuals", "profiles", "history" }) do
        C:Show(k)
        assert(C.pages[k], "page " .. k)
    end
    -- click every button / checkbox on every page (except destructive resets) twice
    for _, page in pairs(C.pages) do
        for _, w in ipairs(page.widgets) do if w.Refresh then w:Refresh() end end
    end
    for _, f in ipairs(FRAMES) do
        if f.kind == "Button" and f.scripts.OnClick then
            local label = f.text and f.text.text or ""
            if type(label) ~= "string" then label = "" end
            if not label:find("Reset") and not label:find("Delete") and label ~= "X" then
                f.scripts.OnClick(f, "LeftButton")
            end
        end
        if f.kind == "Slider" and f.scripts.OnValueChanged then f:SetValue((f.min + f.max) / 2) end
    end
    Advance(15)
    SlashCmdList.VOIDMARKHEALER("stop")
    Advance(1)
    noErrors()
end)

test("display preview and settings layout", function()
    fresh()
    VMH.Display:SetPreview(true)
    Advance(1)
    assert(VMH.Display.frame.shown, "preview visible")
    assert(VMH.Countdown.tickerFrame.shown, "ticker running for preview")
    VMH.Display:SetPreview(false)
    VMH.db.display.locked = false
    VMH.Display:ApplyLayout()
    assert(VMH.Display.frame.shown, "unlocked shows drag anchor")
    VMH.db.display.locked = true
    VMH.Display:ApplyLayout()
    Advance(0.5)
    assert(not VMH.Display.frame.shown, "hidden when idle and locked")
    assert(not VMH.Countdown.tickerFrame.shown, "ticker stops when idle")
end)

test("status, debug and reset commands", function()
    fresh()
    SlashCmdList.VOIDMARKHEALER("status")
    SlashCmdList.VOIDMARKHEALER("debug")
    SlashCmdList.VOIDMARKHEALER("debug log")
    SlashCmdList.VOIDMARKHEALER("debug")
    SlashCmdList.VOIDMARKHEALER("reset")
    VMH.db.alerts.silence.enabled = false
    SlashCmdList.VOIDMARKHEALER("reset confirm")
    eq(VMH.db.alerts.silence.enabled, true)
    eq(#S.chat, 0, "commands never post to group")
    noErrors()
end)

print("PASSED " .. passed)
if #failed > 0 then
    for _, f in ipairs(failed) do print("FAIL " .. f) end
    error(#failed .. " test(s) failed")
end
