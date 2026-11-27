-- VoidMark Healer - alert definitions and default settings
local _, VMH = ...

-- Text tokens: {pct} {dur} {spell} {school} {name} {count} {source}
-- A token with no value removes its surrounding "( )" so no guessed number is ever shown.
-- priority: 5 = crowd control / recovery, 1 = routine
-- threshold: {default, min, max, label} for alerts that use one.
VMH.ALERTS = {
    -- Mana & Health
    { key = "lowMana",        tab = "mana", label = "Low mana",            prio = 2, text = "Low mana ({pct}%)", threshold = { 30, 10, 60, "Low mana at %" } },
    { key = "oom",            tab = "mana", label = "Out of mana",         prio = 3, text = "Out of mana! ({pct}%)", threshold = { 10, 1, 30, "Out of mana at %" } },
    { key = "manaRecovered",  tab = "mana", label = "Mana recovered",      prio = 1, text = "Mana recovered ({pct}%)", threshold = { 60, 30, 100, "Recovered at %" } },
    { key = "lowHealth",      tab = "mana", label = "Low health",          prio = 2, text = "Healer low health ({pct}%)", threshold = { 50, 20, 80, "Low health at %" } },
    { key = "criticalHealth", tab = "mana", label = "Critical health",     prio = 4, text = "Healer critical ({pct}%)! Help!", threshold = { 25, 5, 50, "Critical at %" } },
    { key = "death",          tab = "mana", label = "Healer death",        prio = 4, text = "Healer is dead!" },
    { key = "selfRes",        tab = "mana", label = "Self-res available", prio = 3, text = "Healer dead - can self-resurrect ({spell})" },
    { key = "revived",        tab = "mana", label = "Healer alive again",  prio = 2, text = "Healer is back up!" },
    { key = "drinking",       tab = "mana", label = "Drinking",            prio = 1, text = "Drinking ({pct}% mana)" },
    { key = "drinkDone",      tab = "mana", label = "Finished drinking",   prio = 1, text = "Done drinking ({pct}% mana)" },
    -- Aggro & Threat
    { key = "aggro",          tab = "aggro", label = "Enemy aggro",        prio = 3, text = "Healer has aggro! ({name})", context = "pve" },
    { key = "threat",         tab = "aggro", label = "Excessive threat",   prio = 2, text = "Healer threat high ({pct}%)", threshold = { 90, 60, 100, "Threat at %" }, context = "pve" },
    { key = "multiEnemy",     tab = "aggro", label = "Enemies on you", prio = 3, text = "{count} enemies on the healer!", threshold = { 2, 2, 6, "Enemies" } },
    { key = "los",            tab = "aggro", label = "Line of sight", prio = 1, text = "Can't heal - out of line of sight ({name})",
      threshold = { 50, 10, 100, "Only if their health is under %" },
      whisperText = "You're out of my line of sight - I can't heal you!" },
    -- Crowd control
    { key = "silence",        tab = "cc", label = "Silence",               prio = 5, text = "Healer silenced! ({dur})" },
    { key = "interrupt",      tab = "cc", label = "Interrupt / lockout", prio = 5, text = "Healer interrupted! {school} school locked out ({dur})" },
    { key = "stun",           tab = "cc", label = "Stun",                  prio = 5, text = "Healer stunned! ({dur})" },
    { key = "fear",           tab = "cc", label = "Fear",                  prio = 5, text = "Healer feared! ({dur})" },
    { key = "horror",         tab = "cc", label = "Horror",                prio = 5, text = "Healer horrified! ({dur})" },
    { key = "polymorph",      tab = "cc", label = "Polymorph",             prio = 5, text = "Healer polymorphed! ({dur})" },
    { key = "sap",            tab = "cc", label = "Sap",                   prio = 5, text = "Healer sapped! ({dur})" },
    { key = "blind",          tab = "cc", label = "Blind",                 prio = 5, text = "Healer blinded! ({dur})" },
    { key = "disorient",      tab = "cc", label = "Disorient",             prio = 5, text = "Healer disoriented! ({dur})" },
    { key = "sleep",          tab = "cc", label = "Sleep",                 prio = 5, text = "Healer asleep! ({dur})" },
    { key = "mindControl",    tab = "cc", label = "Mind Control",          prio = 5, text = "Healer mind controlled! ({dur})" },
    { key = "incapacitate",   tab = "cc", label = "Incapacitate",          prio = 5, text = "Healer incapacitated! ({spell}, {dur})" },
    { key = "cyclone",        tab = "cc", label = "Cyclone",               prio = 5, text = "Healer cycloned! ({dur})" },
    { key = "root",           tab = "cc", label = "Root (movement)",  prio = 2, text = "Healer rooted! ({dur})" },
    { key = "otherCC",        tab = "cc", label = "Other CC", prio = 5, text = "Healer can't act: {spell} ({dur})" },
    { key = "cantCast",       tab = "cc", label = "Can't cast (hidden CC)", prio = 5, text = "Healer can't cast heals!" },
    { key = "countdown",      tab = "cc", label = "Countdown warnings",    prio = 4, text = "Healing resumes in {dur}!" },
    { key = "recovered",      tab = "cc", label = "Healing resumed", prio = 5, text = "Healer free - healing resumed! {note}" },
}
VMH.ALERT_BY_KEY = {}
for _, a in ipairs(VMH.ALERTS) do VMH.ALERT_BY_KEY[a.key] = a end

VMH.CHANNELS = {
    { key = "auto",     label = "Auto" },
    { key = "party",    label = "Party" },
    { key = "raid",     label = "Raid" },
    { key = "instance", label = "Instance" },
    { key = "bg",       label = "Battleground" },
    { key = "say",      label = "Say" },
    { key = "yell",     label = "Yell" },
    { key = "self",     label = "Self only" },
}

-- Raid icons for group messages ({code} shows as the icon in chat).
VMH.ICONS = {
    { value = "", label = "None" }, { value = "{skull}", label = "Skull" }, { value = "{cross}", label = "Cross" },
    { value = "{square}", label = "Square" }, { value = "{moon}", label = "Moon" }, { value = "{triangle}", label = "Triangle" },
    { value = "{diamond}", label = "Diamond" }, { value = "{circle}", label = "Circle" }, { value = "{star}", label = "Star" },
}
-- Colors: skull = aggro, red cross = bad, star = mana warnings, green triangle = good.
local ICON_FOR = {
    aggro = "{skull}", threat = "{skull}", multiEnemy = "{skull}", los = "{skull}",
    lowMana = "{star}", oom = "{star}", drinking = "{star}",
    lowHealth = "{cross}", criticalHealth = "{cross}", death = "{cross}", selfRes = "{cross}",
    manaRecovered = "{triangle}", drinkDone = "{triangle}", revived = "{triangle}", recovered = "{triangle}",
}
VMH.DefaultIcon = function(key)
    if ICON_FOR[key] then return ICON_FOR[key] end
    local a = VMH.ALERT_BY_KEY[key]
    return (a and a.tab == "cc") and "{cross}" or ""
end

VMH.SOUNDS = {
    { key = "none",    label = "None",        id = nil },
    { key = "warning", label = "Raid warning", id = 8959 },
    { key = "ready",   label = "Ready check",  id = 8960 },
    { key = "alarm",   label = "Alarm",        id = 12867 },
    { key = "alarm2",  label = "Alarm (high)", id = 12889 },
    { key = "ping",    label = "Map ping",     id = 3175 },
}

local function alertDefaults(a)
    local t = {
        enabled = true,
        text = a.text,
        channels = { auto = true },
        cooldown = (a.prio >= 5) and 0 or 20,
        sound = (a.prio >= 5) and "warning" or "none",
        onscreen = a.prio >= 4,
        context = a.context or "any",
        icon = VMH.DefaultIcon(a.key),
    }
    if a.threshold then t.threshold = a.threshold[1] end
    -- Routine notices default to local only so groups are not spammed.
    if a.key == "manaRecovered" or a.key == "drinkDone" or a.key == "los" or a.key == "lowHealth" or a.key == "root" then
        t.channels = { self = true }
    end
    if a.key == "threat" then t.enabled = false end
    -- Line of sight can whisper the player you were trying to heal (off by default).
    if a.whisperText then
        t.whisper = false
        t.whisperText = a.whisperText
    end
    if a.key == "countdown" then t.sound = "none"; t.onscreen = false end
    if a.key == "recovered" then t.sound = "ready" end
    if a.key == "los" then t.cooldown = 8 end
    return t
end

function VMH.BaseProfile()
    local p = {
        general = {
            enabled = true,
            healerOnly = "class",      -- always | class | role
            testsSendChat = false,     -- per-alert Test buttons stay local unless enabled
        },
        announce = {
            outgoing = true,           -- false = nothing leaves this client
            prefix = "",               -- optional extra text after each alert's icon
            iconStyle = "double",      -- double = two icons each side, single = one before
            throttle = 1.0,            -- seconds between outgoing messages
            duplicateWindow = 6,       -- identical text within this window is dropped
            hysteresis = 10,           -- percentage points before mana/health re-arm
        },
        countdown = {
            enabled = true,
            smart = true,              -- duration-based plan (see Countdown.lua)
            minDuration = 5,
            warn10 = false, warn5 = true, warn3 = true, warn2 = false, warn1 = false,
            recovery = true,
            recoveryShort = false,     -- recovery announcement for effects under 5s
            chat = true,
            onscreen = true,
            sound = false,
        },
        display = {
            enabled = true, locked = true, scale = 1.0, alpha = 1.0,
            fontSize = 12, iconSize = 26, barWidth = 200, barHeight = 14, maxRows = 5,
            showOutOfCombat = true,
            point = "CENTER", relPoint = "CENTER", x = 0, y = 180,
            colorBlocked = { 0.85, 0.15, 0.25 },
            colorLockout = { 0.62, 0.36, 1.0 },
            colorMovement = { 0.95, 0.7, 0.1 },
            colorBackground = { 0.05, 0.03, 0.09, 0.85 },
        },
        visuals = {
            onscreen = true,           -- master switch for on-screen warnings
            sound = false,             -- master switch for sounds (off: you already know when you're CC'd)
            soundChannel = "Master",
        },
        history = { enabled = true },
        alerts = {},
    }
    for _, a in ipairs(VMH.ALERTS) do p.alerts[a.key] = alertDefaults(a) end
    return p
end

local function setChannels(p, keys, channels)
    for _, k in ipairs(keys) do
        local c = {}
        for _, ch in ipairs(channels) do c[ch] = true end
        p.alerts[k].channels = c
    end
end
local CC_KEYS = { "silence", "interrupt", "stun", "fear", "horror", "polymorph", "sap", "blind", "disorient",
    "sleep", "mindControl", "incapacitate", "cyclone", "otherCC", "cantCast", "countdown", "recovered" }
VMH.CC_KEYS = CC_KEYS

-- Presets are applied on top of BaseProfile().
VMH.PRESETS = {
    Dungeon = function(p)
        p.alerts.los.enabled = true
        p.alerts.los.channels = { auto = true }
        p.alerts.multiEnemy.enabled = true
        p.alerts.multiEnemy.threshold = 3   -- two mobs on the healer is a normal pull
        p.countdown.minDuration = 8         -- short CC: alert + recovery only
    end,
    Raid = function(p)
        p.announce.throttle = 2.0
        p.announce.duplicateWindow = 12
        for _, a in pairs(p.alerts) do if a.cooldown > 0 then a.cooldown = a.cooldown * 2 end end
        for _, k in ipairs({ "lowMana", "drinking", "drinkDone", "los", "threat", "multiEnemy", "root", "lowHealth" }) do
            p.alerts[k].channels = { self = true }
        end
        p.alerts.aggro.channels = { self = true }
        p.countdown.chat = false       -- countdown stays on screen in raids
        p.countdown.recoveryShort = false
    end,
    PvP = function(p)
        for _, k in ipairs({ "lowMana", "drinking", "drinkDone", "manaRecovered", "los", "aggro", "threat" }) do
            p.alerts[k].enabled = false
        end
        p.alerts.multiEnemy.enabled = true
        p.alerts.multiEnemy.threshold = 2   -- PvP: two players on you matters
        p.alerts.multiEnemy.context = "any"
        p.alerts.multiEnemy.cooldown = 15
        p.alerts.root.channels = { auto = true }
        p.countdown.minDuration = 4
        p.countdown.recoveryShort = true
        p.alerts.oom.channels = { auto = true }
    end,
    Solo = function(p)
        for _, a in pairs(p.alerts) do a.channels = { self = true } end
    end,
    Custom = function(p) end,
}
VMH.PRESET_ORDER = { "Dungeon", "Raid", "PvP", "Solo", "Custom" }

function VMH.BuildPreset(name)
    local p = VMH.BaseProfile()
    local fn = VMH.PRESETS[name]
    if fn then fn(p) end
    return p
end
