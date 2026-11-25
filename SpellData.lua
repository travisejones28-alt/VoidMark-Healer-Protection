-- VoidMark Healer - spell data
-- Spell IDs are used first; localized names are derived from these IDs at
-- runtime so detection works on any client language.
local _, VMH = ...
local D = {}
VMH.SpellData = D

-- Crowd-control categories. blocks = prevents healing.
-- alert = alert key in Defaults; label = short on-screen label.
D.TYPES = {
    SILENCE      = { alert = "silence",      label = "Silenced",      blocks = true,  order = 1 },
    LOCKOUT      = { alert = "interrupt",    label = "Locked out",    blocks = true,  order = 2 },
    STUN         = { alert = "stun",         label = "Stunned",       blocks = true,  order = 3 },
    FEAR         = { alert = "fear",         label = "Feared",        blocks = true,  order = 4 },
    HORROR       = { alert = "horror",       label = "Horrified",     blocks = true,  order = 5 },
    POLYMORPH    = { alert = "polymorph",    label = "Polymorphed",   blocks = true,  order = 6 },
    SAP          = { alert = "sap",          label = "Sapped",        blocks = true,  order = 7 },
    BLIND        = { alert = "blind",        label = "Blinded",       blocks = true,  order = 8 },
    DISORIENT    = { alert = "disorient",    label = "Disoriented",   blocks = true,  order = 9 },
    SLEEP        = { alert = "sleep",        label = "Asleep",        blocks = true,  order = 10 },
    CHARM        = { alert = "mindControl",  label = "Mind controlled", blocks = true, order = 11 },
    INCAPACITATE = { alert = "incapacitate", label = "Incapacitated", blocks = true,  order = 12 },
    CYCLONE      = { alert = "cyclone",      label = "Cycloned",      blocks = true,  order = 13 },
    OTHER        = { alert = "otherCC",      label = "Can't act",     blocks = true,  order = 14 },
    ROOT         = { alert = "root",         label = "Rooted",        blocks = false, order = 15 },
}

-- spellID -> type
local CC = {}
D.CC = CC
local function add(kind, ...)
    for i = 1, select("#", ...) do CC[select(i, ...)] = kind end
end
add("POLYMORPH", 118, 12824, 12825, 12826, 28270, 28271, 28272)
add("SAP", 6770, 2070, 11297)
add("BLIND", 2094)
add("INCAPACITATE", 1776, 1777, 8629, 11285, 11286, 3355, 14308, 14309, 20066)
add("STUN", 408, 8643, 1833, 853, 5588, 5589, 10308, 5211, 6798, 8983, 9005, 9823, 9827,
    7922, 20253, 20614, 20615, 12809, 20549, 5530, 12355, 15269, 16922, 19410, 19577, 24394, 20170, 18093)
add("FEAR", 8122, 8124, 10888, 10890, 5782, 6213, 6215, 5484, 17928, 5246, 1513, 14326, 14327)
add("HORROR", 6789, 17925, 17926)
add("CHARM", 605, 10911, 10912)
add("SLEEP", 2637, 18657, 18658, 19386, 24132, 24133, 700, 1090)
add("DISORIENT", 19503)
add("CYCLONE", 33786)
add("SILENCE", 15487, 18469, 18425, 24259, 18498, 19821)
add("ROOT", 122, 865, 6131, 10230, 339, 1062, 5195, 5196, 9852, 9853, 19975, 19974, 19973, 19972, 19971, 19970,
    23694, 12494, 13099, 19306, 20909, 20910, 19229, 19185)
add("OTHER", 6358)

-- Enemy interrupt abilities (used to name the interrupter when visible).
D.INTERRUPTS = {}
for _, id in ipairs({ 1766, 1767, 1768, 1769, 6552, 6554, 72, 1671, 1672, 2139, 8042, 8044, 8045, 8046,
    10412, 10413, 10414, 19244, 19647, 16979, 15487 }) do D.INTERRUPTS[id] = true end

-- Drink buffs. Names come from these IDs so the check works in any locale.
D.DRINKS = { 430, 431, 432, 1133, 1135, 1137, 10250, 22734, 24355, 25696, 26261, 26475, 29007, 18233, 23540, 24707 }

-- Spell school bit flags (lockoutSchool).
D.SCHOOLS = { [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature", [16] = "Frost", [32] = "Shadow", [64] = "Arcane" }

-- School that each healing class heals with. 0 = treat every lockout as blocking.
D.HEAL_SCHOOL = { PRIEST = 2, PALADIN = 2, DRUID = 8, SHAMAN = 8 }

-- Priest damage spells are Shadow; used when a lockout is detected through
-- a cooldown probe instead of Loss of Control data.
D.SHADOW_SPELLS = {}
for _, id in ipairs({ 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947, 15407, 17311, 17312, 17313, 17314,
    18807, 605, 10911, 10912, 589, 594, 970, 992, 2767, 10892, 10893, 10894 }) do D.SHADOW_SPELLS[id] = true end

local band = bit and bit.band or function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end
D.band = band

function D.SchoolName(mask)
    if type(mask) ~= "number" or mask <= 0 then return nil end
    if D.SCHOOLS[mask] then return D.SCHOOLS[mask] end
    local names = {}
    for bitv = 1, 64 do
        if D.SCHOOLS[bitv] and band(mask, bitv) ~= 0 then names[#names + 1] = D.SCHOOLS[bitv] end
    end
    if #names == 0 then return nil end
    return table.concat(names, "/")
end

function D.LockoutBlocksHealing(mask)
    local heal = D.HEAL_SCHOOL[VMH.PlayerClass() or ""] or 0
    if heal == 0 or type(mask) ~= "number" or mask == 0 then return true end
    return band(mask, heal) ~= 0
end

-- Localized name lookups, built lazily.
local nameToType, drinkNames
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return VMH.Safe(C_Spell.GetSpellName, id) end
    return (VMH.Safe(_G.GetSpellInfo, id))
end
D.SpellName = spellName

function D.TypeForName(name)
    if type(name) ~= "string" then return nil end
    if not nameToType then
        nameToType = {}
        for id, kind in pairs(CC) do
            local n = spellName(id)
            if n and not nameToType[n] then nameToType[n] = kind end
        end
    end
    return nameToType[name]
end

function D.IsDrinkName(name)
    if type(name) ~= "string" then return false end
    if not drinkNames then
        drinkNames = {}
        for _, id in ipairs(D.DRINKS) do
            local n = spellName(id)
            if n then drinkNames[n] = true end
        end
    end
    return drinkNames[name] == true
end

-- Loss of Control locType -> our type (used when the spell is not in CC).
D.LOC_TYPES = {
    STUN = "STUN", STUN_MECHANIC = "STUN", FEAR = "FEAR", FEAR_MECHANIC = "FEAR",
    CONFUSE = "DISORIENT", CHARM = "CHARM", POSSESS = "CHARM",
    SILENCE = "SILENCE", PACIFYSILENCE = "SILENCE", SCHOOL_INTERRUPT = "LOCKOUT", ROOT = "ROOT",
}

-- Display text keywords help split CONFUSE into the categories players expect.
D.TEXT_HINTS = {
    { "olymorph", "POLYMORPH" }, { "apped", "SAP" }, { "lind", "BLIND" }, { "sleep", "SLEEP" },
    { "orror", "HORROR" }, { "ncapacitat", "INCAPACITATE" }, { "yclone", "CYCLONE" },
    { "isorient", "DISORIENT" },
}
