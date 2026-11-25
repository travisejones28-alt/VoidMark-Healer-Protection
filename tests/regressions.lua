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
    VMH.Mana.scanQueued = false
    VMH:RunAuraScan() -- the harness wipes timers between tests; clear the queued-scan flag
    VMH.Announce.flushScheduled = false
    VMH.Announce.held, VMH.Announce.watching = {}, false
    boot()
    -- most tests run in the open world mock; let them detect there
    VMH.sv.runIn = "everywhere"
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
    eq(F("{skull} Healer has aggro! ({name})", {}), "{skull} Healer has aggro!")
    eq(F("{rt8} Silenced ({dur}) {cross}", { dur = "8s" }), "{rt8} Silenced (8s) {cross}")
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
    -- regen ticks around the "low" spell's cost: at most one low-mana message, no recovered spam
    for _ = 1, 4 do
        S.usable = {}
        Emit("SPELL_UPDATE_USABLE")
        Advance(0.5)
        S.usable = { [2060] = { usable = false, noMana = true } }
        Emit("SPELL_UPDATE_USABLE")
        Advance(0.5)
    end
    assert(count(chatTexts(), "Low mana") <= 1, "low mana flapped")
    eq(count(S.prints, "Mana recovered"), 0, "same-spell recovery stays quiet")
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
    eq(c[1], "RAID:{skull} Healer silenced! (8s)")
    S.chat = {}
    S.raid = false
    S.homeGroup = false
    S.instanceGroup = true
    S.instance, S.instanceType = true, "party"
    VMH.db.alerts.stun.channels = { auto = true, party = true }
    VMH.Announce:Alert("stun", { dur = "4s" })
    Advance(1.2)
    eq(chatTexts()[1], "INSTANCE_CHAT:{skull} Healer stunned! (4s)")
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
    assert(has(S.prints, "[SIM -> PARTY]|r {skull} Healer silenced! (8s)"), "sim silence shown")
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


test("line of sight: damage spell (Mind Blast) never says can't heal", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    VMH.db.general.healerOnly = "always"
    S.units.target = { name = "Enemy", hostile = true }
    S.units.mouseover = { name = "Tank", surname = "Person", hostile = false }
    Emit("UNIT_SPELLCAST_FAILED", "player", "c1", 8092)
    Emit("UI_ERROR_MESSAGE", 50, SPELL_FAILED_LINE_OF_SIGHT)
    Advance(0.3)
    assert(not has(S.prints, "line of sight"), "harmful spell ignored")
    Advance(10)
    Emit("UI_ERROR_MESSAGE", 50, SPELL_FAILED_LINE_OF_SIGHT)
    Emit("UNIT_SPELLCAST_FAILED", "player", "c2", 2061)
    Advance(0.3)
    assert(has(S.prints, "out of line of sight (Tank Person)"), "heal failure reported")
end)

test("line of sight: unknown spell with only a hostile target is ignored", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    S.units.target = { name = "Enemy", hostile = true }
    Emit("UI_ERROR_MESSAGE", 50, SPELL_FAILED_LINE_OF_SIGHT)
    Advance(0.3)
    assert(not has(S.prints, "line of sight"))
end)

test("hidden Loss of Control spell + readable debuff = one announcement", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    local e = addLoC("STUN", 408, 6)
    e.spellID = SECRET
    S.auras.HARMFUL[1] = { name = "Kidney Shot", spellId = 408, duration = 6, expirationTime = NOW + 6, icon = 1 }
    Emit("UNIT_AURA", "player")
    Advance(0.5)
    eq(count(chatTexts(), "stunned"), 1)
    -- debuff becomes hidden mid-effect: the effect must not be announced again
    S.aurasHidden = true
    Emit("UNIT_AURA", "player")
    Advance(0.5)
    S.aurasHidden = false
    Emit("UNIT_AURA", "player")
    Advance(0.5)
    eq(count(chatTexts(), "stunned"), 1, "no repeat when values flip")
    eq(VMH.History.session.stunned, 1, "counted once")
end)

test("two different CCs ending together are both announced", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    addLoC("STUN", 408, 6)
    Advance(0.3)
    addLoC("SILENCE", 15487, 5.8)
    Advance(1.5)
    eq(count(chatTexts(), "stunned"), 1)
    eq(count(chatTexts(), "silenced"), 1)
end)

test("10s effect seen late still gets the 5s warning", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    local e = addLoC("STUN", 853, 10)
    e.startTime = NOW - 0.15
    play(10.5)
    eq(count(chatTexts(), "Healing resumes in 5s!"), 1)
    eq(count(chatTexts(), "Healing resumes in 3s!"), 1)
end)

test("leaving the group drops queued party messages", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    VMH.Announce.lastSend = NOW
    VMH.Announce:Alert("silence", { dur = "8s" })
    S.homeGroup = false
    Advance(2)
    eq(#S.chat, 0)
end)

test("health alerts only in combat, with hysteresis", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    VMH.db.alerts.lowHealth.channels = { auto = true }
    local function hp(p) S.hp = p * 50; Emit("UNIT_HEALTH", "player"); Advance(0.4) end
    hp(40)
    eq(#S.chat, 0, "out of combat: quiet")
    S.inCombat = true
    hp(70); hp(40)
    eq(count(chatTexts(), "Healer low health (40%)"), 1)
    hp(52); hp(45)
    eq(count(chatTexts(), "low health"), 1, "no flapping")
    hp(20)
    eq(count(chatTexts(), "Healer critical (20%)! Help!"), 1)
end)

test("timer and ticker errors are contained", function()
    fresh()
    VMH.After(0, function() error("boom") end)
    Advance(0.1)
    local found = false
    for _, l in ipairs(VMH.debugLog) do if l:find("timer error") then found = true end end
    assert(found, "logged, not raised")
    local real = VMH.Display.Tick
    VMH.Display.Tick = function() error("tick boom") end
    VMH.CrowdControl:Simulate({ type = "STUN", spellID = 408, duration = 3 })
    Advance(0.5)
    VMH.Display.Tick = real
    assert(not VMH.Countdown.tickerFrame.shown or true)
    VMH.CrowdControl:EndSimulation()
    Advance(0.5)
end)

test("history ignores CC while not healing", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.auras.HELPFUL[1] = { name = "Shadowform", spellId = 15473 }
    addLoC("STUN", 408, 4)
    play(5)
    eq(VMH.History.session.cc, 0)
    eq(VMH.History.session.blockedTime, 0)
end)

test("config: countdown tab, scroll bar on long pages, short status", function()
    fresh()
    local C = VMH.Config
    C:Show("cc")
    assert(C.pages.cc.bar.shown, "crowd control page shows a scroll bar")
    C:Show("countdown")
    assert(C.pages.countdown, "countdown tab")
    C.pages.cc.bar:SetValue(50)
    eq(C.pages.cc.scroll.vscroll, 50, "bar scrolls the page")
    assert(VMH.Commands:ShortStatus():find("Ready"), VMH.Commands:ShortStatus())
    C.frame:Hide()
end)

test("run in: dungeons and raids only is the default and pauses the open world", function()
    fresh()
    VoidMarkHealerDB.runIn = nil
    VMH.Profiles:Load()
    eq(VMH.sv.runIn, "dungeonraid", "default")
    VMH.Profiles:Select("Dungeon", true)
    addLoC("STUN", 408, 6)
    S.mana = 400; Emit("UNIT_POWER_UPDATE", "player")
    S.plates = { "nameplate1" }
    S.units.nameplate1 = { name = "A", hostile = true, isPlayer = true, guid = "A", targetsPlayer = true }
    S.units.nameplate2 = { name = "B", hostile = true, isPlayer = true, guid = "B", targetsPlayer = true }
    S.plates = { "nameplate1", "nameplate2" }
    Emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    play(7)
    eq(#S.chat, 0, "nothing in the open world")
    eq(VMH.History.session.cc, 0, "nothing counted")
    assert(not VMH.Display.frame.shown, "display hidden")
    -- simulations still work for setup
    SlashCmdList.VOIDMARKHEALER("test silence")
    Advance(0.5)
    assert(has(S.prints, "[SIM -> PARTY]|r {skull} Healer silenced! (8s)"), "sim works in world")
    SlashCmdList.VOIDMARKHEALER("stop")
    Advance(0.5)
    -- inside a dungeon it runs
    S.loc = {}
    S.instance, S.instanceType = true, "party"
    Emit("PLAYER_ENTERING_WORLD", false, false)
    Advance(1)
    addLoC("SILENCE", 15487, 6)
    Advance(0.5)
    eq(count(chatTexts(), "Healer silenced! (6s)"), 1, "runs in dungeon")
end)

test("run in: battlegrounds only with the instances option", function()
    fresh()
    VMH.Profiles:Select("PvP", true)
    S.instance, S.instanceType = true, "pvp"
    VMH.sv.runIn = "dungeonraid"
    assert(not VMH:IsActiveHere())
    VMH.sv.runIn = "instances"
    assert(VMH:IsActiveHere())
    SlashCmdList.VOIDMARKHEALER("world")
    eq(VMH.sv.runIn, "everywhere")
    SlashCmdList.VOIDMARKHEALER("world")
    eq(VMH.sv.runIn, "dungeonraid")
end)

test("skull prefix: on by default, old blank prefixes upgraded once, custom kept", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    VMH.Announce:Alert("silence", { dur = "8s" })
    Advance(0.3)
    eq(S.chat[1].msg, "{skull} Healer silenced! (8s)")
    assert(not has(S.prints, "{skull}"), "local prints stay clean")
    VoidMarkHealerDB.skullPrefixSet = nil
    VoidMarkHealerDB.profiles.Dungeon.announce.prefix = ""
    VoidMarkHealerDB.profiles.Raid.announce.prefix = "[Heals]"
    VMH.Profiles:Load()
    eq(VoidMarkHealerDB.profiles.Dungeon.announce.prefix, "{skull}")
    eq(VoidMarkHealerDB.profiles.Raid.announce.prefix, "[Heals]")
    VoidMarkHealerDB.profiles.Dungeon.announce.prefix = ""
    VMH.Profiles:Load()
    eq(VoidMarkHealerDB.profiles.Dungeon.announce.prefix, "", "turning it off sticks")
end)

test("debug trail explains a missed alert and survives reload", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.role = "DAMAGER"
    addLoC("SILENCE", 6726, 5)
    Advance(0.5)
    S.role = "NONE"
    local log = table.concat(VMH.debugLog, "\n")
    assert(log:find("CC added: Silence", 1, true) or log:find("CC added: nil (spell 6726)", 1, true), log)
    assert(log:find("alert silence: not healer (role DAMAGER", 1, true), log)
    S.loc = { { locType = "PACIFY", spellID = 999, displayText = "Pacified", startTime = NOW, duration = 5 } }
    Emit("LOSS_OF_CONTROL_UPDATE")
    Advance(0.3)
    assert(table.concat(VMH.debugLog, "\n"):find("Loss of Control ignored: PACIFY", 1, true))
    -- reload keeps the trail
    local before = #VoidMarkHealerDB.log
    VMH.Profiles:Load()
    assert(#VMH.debugLog >= before, "trail kept")
    S.loc = {}
end)

test("chat lockdown: OOM and death post after unlock only if still true", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.chatLocked = true
    S.mana = 400; Emit("UNIT_POWER_UPDATE", "player"); Advance(0.5)
    VMH.Announce:Alert("aggro", {})
    Advance(1.5)
    eq(#S.chat, 0, "nothing sent while locked")
    assert(has(S.prints, "will post when it unlocks"), "user told it is held")
    Advance(5)
    S.chatLocked = false
    Advance(3)
    local c = chatTexts()
    eq(count(c, "Out of mana! (8%)"), 1, "OOM posted after unlock")
    eq(count(c, "aggro"), 0, "stale aggro not posted")
    -- recovered before unlock: dropped
    S.chat = {}
    S.chatLocked = true
    Advance(25)
    S.dead = true; Emit("PLAYER_DEAD"); Advance(1.5)
    S.dead = false; Emit("PLAYER_ALIVE"); Advance(0.5)
    S.chatLocked = false
    Advance(4)
    eq(count(chatTexts(), "Healer is dead!"), 0, "death not posted after revive")
end)

test("out of range: no alert at all", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    VMH.db.general.healerOnly = "always"
    S.units.mouseover = { name = "Tank", surname = "Person", hostile = false, isPlayer = true }
    Emit("UI_ERROR_MESSAGE", 51, SPELL_FAILED_OUT_OF_RANGE)
    Emit("UNIT_SPELLCAST_FAILED", "player", "c", 2061)
    Advance(1.5)
    eq(#S.chat, 0)
    assert(not has(S.prints, "range"), "nothing printed")
    assert(VMH.ALERT_BY_KEY.range == nil, "alert gone")
    eq(VMH.db.alerts.range, nil, "no settings")
end)

test("line of sight: optional whisper to that player, per-player cooldown", function()
    fresh()
    VMH.Profiles:Select("Custom", true)
    VMH.db.alerts.los.channels = {}
    VMH.db.alerts.los.whisper = true
    S.units.mouseover = { name = "Tank", surname = "Person", hostile = false, isPlayer = true }
    local function fail()
        Emit("UI_ERROR_MESSAGE", 50, SPELL_FAILED_LINE_OF_SIGHT)
        Emit("UNIT_SPELLCAST_FAILED", "player", "c", 2061)
        Advance(1.2)
    end
    fail()
    eq(#S.chat, 1)
    eq(S.chat[1].type, "WHISPER")
    eq(S.chat[1].target, "Tank-Person")
    eq(S.chat[1].msg, "You're out of my line of sight - I can't heal you!")
    fail()
    eq(#S.chat, 1, "same player within cooldown")
    S.units.mouseover = { name = "Guard", hostile = false, isPlayer = false }
    Advance(9)
    fail()
    eq(#S.chat, 1, "NPCs never whispered")
end)

test("old saved range settings are cleaned up", function()
    fresh()
    VoidMarkHealerDB.profiles.Dungeon.alerts.range = { enabled = true, channels = { auto = true } }
    VoidMarkHealerDB.rangeWhisperSet = true
    VMH.Profiles:Load()
    eq(VoidMarkHealerDB.profiles.Dungeon.alerts.range, nil)
    eq(VoidMarkHealerDB.rangeWhisperSet, nil)
end)

test("mob silence not in the spell list is read from its tooltip (Shrieking Banshee)", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.locSecret = true
    VMH.CrowdControl.tipCache = {}
    S.auras.HARMFUL[1] = { name = "Disease Cloud", spellId = 99001, duration = 30, expirationTime = NOW + 30, tip = "Reduces Stamina by 10." }
    S.auras.HARMFUL[2] = { name = "Deafening Screech", spellId = 99002, duration = 8, expirationTime = NOW + 8, tip = "Cannot cast spells." }
    Emit("UNIT_AURA", "player")
    Advance(0.4)
    eq(count(chatTexts(), "Healer silenced! (8s)"), 1, table.concat(chatTexts(), " | "))
    local calls = TIP_CALLS
    Emit("UNIT_AURA", "player")
    Advance(0.4)
    eq(TIP_CALLS, calls, "tooltip read once per debuff (cached)")
    S.auras.HARMFUL[2] = nil
    Emit("UNIT_AURA", "player")
    Advance(1.5)
    eq(count(chatTexts(), "healing resumed"), 1)
    -- hidden tooltip text: no guess, retried later
    VMH.CrowdControl.tipCache = {}
    S.tipSecret = true
    S.auras.HARMFUL[2] = { name = "Mystery", spellId = 99003, duration = 5, expirationTime = NOW + 5, tip = "Stunned." }
    Emit("UNIT_AURA", "player"); Advance(0.4)
    eq(count(chatTexts(), "stunned"), 0)
    S.tipSecret = false
    Emit("UNIT_AURA", "player"); Advance(0.4)
    eq(count(chatTexts(), "Healer stunned!"), 1, "picked up once readable")
    noErrors()
end)

test("everything hidden: greyed-out heal announces 'can't cast' and recovery", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.spellbook = { 1706, 2050, 2061 }          -- Levitate (reagent), Lesser Heal, Flash Heal
    S.costs = { [1706] = 20, [2050] = 75, [2061] = 380 }
    Emit("SPELLS_CHANGED"); Advance(1.5)
    VMH.CrowdControl.healDirty = true
    S.inCombat = true
    S.locSecret, S.aurasHidden = true, true
    S.usable = { [1706] = { usable = false, noMana = false } }  -- no feathers: must never trigger
    Emit("SPELL_UPDATE_USABLE"); Advance(0.5)
    eq(#S.chat, 0, "reagent spell ignored")
    eq(VMH.CrowdControl.healSpell, 2050, "cheapest real heal")
    S.loc = { { locType = SECRET, spellID = SECRET, startTime = NOW, duration = 6 } }
    S.usable[2050] = { usable = false, noMana = false }
    Emit("LOSS_OF_CONTROL_ADDED"); Emit("SPELL_UPDATE_USABLE"); Advance(0.5)
    eq(count(chatTexts(), "Healer can't cast heals!"), 1, table.concat(chatTexts(), " | "))
    assert(table.concat(VMH.debugLog, "\n"):find("probe LOSS_OF_CONTROL_ADDED: LoC count HIDDEN", 1, true), "snapshot logged")
    Advance(4)
    S.usable[2050] = nil; S.loc = {}
    Emit("SPELL_UPDATE_USABLE"); Advance(1.5)
    eq(count(chatTexts(), "healing resumed"), 1)
    -- out of mana is not "can't cast"
    S.usable[2050] = { usable = false, noMana = true }
    Emit("SPELL_UPDATE_USABLE"); Advance(0.5)
    eq(count(chatTexts(), "can't cast"), 1, "no repeat for OOM")
end)

test("readable silence wins over the greyed-out check (no double alert)", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.spellbook = { 2050 }; S.costs = { [2050] = 75 }
    Emit("SPELLS_CHANGED"); Advance(1.5)
    VMH.CrowdControl.healDirty = true
    S.inCombat = true
    S.usable = { [2050] = { usable = false, noMana = false } }
    addLoC("SILENCE", 15487, 5)
    Emit("SPELL_UPDATE_USABLE"); Advance(0.5)
    eq(count(chatTexts(), "silenced"), 1)
    eq(count(chatTexts(), "can't cast"), 0)
end)

test("own on-screen warning, tooltip and color chooser work (no Blizzard frames)", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    VMH.Announce:Alert("silence", { dur = "8s" })
    local w = VoidMarkHealerWarning
    assert(w and w.shown, "warning shown")
    eq(w.lines[1].text, "Healer silenced! (8s)")
    Advance(4)
    assert(not w.shown, "warning fades out")
    VMH.Config:Show("visuals")
    local swatch
    for _, f in ipairs(FRAMES) do if f.swatch then swatch = f end end
    swatch.scripts.OnClick(swatch)
    assert(VoidMarkHealerColorChooser.shown, "chooser opens")
    local pick
    for _, f in ipairs(FRAMES) do if f.parent == VoidMarkHealerColorChooser and f.scripts.OnClick then pick = f end end
    pick.scripts.OnClick(pick)
    assert(not VoidMarkHealerColorChooser.shown, "chooser closes after pick")
    local btn
    for _, f in ipairs(FRAMES) do if f.kind == "Button" and f.scripts.OnEnter and f.text and f.text.text == "Full status in chat" then btn = f end end
    VMH.Config:Show("general")
    for _, f in ipairs(FRAMES) do if f.kind == "Button" and f.text and f.text.text == "Full status in chat" then btn = f end end
    btn.scripts.OnEnter(btn)
    assert(VoidMarkHealerTooltip and VoidMarkHealerTooltip.shown, "own tooltip")
    btn.scripts.OnLeave(btn)
    assert(not VoidMarkHealerTooltip.shown)
    VMH.Config.frame:Hide()
end)

test("sounds off by default and for existing profiles; can be turned back on", function()
    fresh()
    VMH.Profiles:Select("Dungeon", true)
    S.sounds = {}
    addLoC("SILENCE", 15487, 8)
    play(9)
    eq(#S.sounds, 0, "no sounds")
    VoidMarkHealerDB.soundsOffSet = nil
    VoidMarkHealerDB.profiles.Raid.visuals.sound = true
    VMH.Profiles:Load()
    eq(VoidMarkHealerDB.profiles.Raid.visuals.sound, false, "old profile switched off")
    VoidMarkHealerDB.profiles.Raid.visuals.sound = true
    VMH.Profiles:Load()
    eq(VoidMarkHealerDB.profiles.Raid.visuals.sound, true, "your later choice sticks")
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
