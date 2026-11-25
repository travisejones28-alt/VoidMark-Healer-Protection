-- VoidMark Healer - lightweight statistics (session + lifetime)
local _, VMH = ...
local H = VMH:NewModule("History")

local function blank()
    return { silenced = 0, interrupted = 0, stunned = 0, cc = 0, blockedTime = 0, lowMana = 0, deaths = 0,
        spells = {}, interrupters = {}, sources = {} }
end
H.blank = blank

function H:Init()
    self.session = blank()
    local sv = VMH.sv.history
    sv.lifetime = type(sv.lifetime) == "table" and sv.lifetime or blank()
    for k, v in pairs(blank()) do if sv.lifetime[k] == nil then sv.lifetime[k] = v end end
end

-- Only counts while you're healing (not as Shadow, not on a non-healing role).
function H:Enabled() return VMH.db and VMH.db.history.enabled and VMH:IsHealerActive() end

local function bump(field, amount, key)
    if not H:Enabled() then return end
    for _, t in ipairs({ H.session, VMH.sv.history.lifetime }) do
        if key then
            t[field][key] = (t[field][key] or 0) + (amount or 1)
        else
            t[field] = (t[field] or 0) + (amount or 1)
        end
    end
end

-- effect: CrowdControl effect record. Simulated effects are never recorded.
function H:RecordCC(effect)
    if effect.simulated then return end
    bump("cc")
    if effect.type == "SILENCE" then bump("silenced") end
    if effect.type == "STUN" then bump("stunned") end
    if effect.type == "LOCKOUT" then bump("interrupted") end
    if effect.name then bump("spells", 1, effect.name) end
    if effect.source then
        if effect.type == "LOCKOUT" then bump("interrupters", 1, effect.source) else bump("sources", 1, effect.source) end
    end
end

function H:RecordBlocked(seconds, simulated)
    if simulated or type(seconds) ~= "number" or seconds <= 0 or seconds > 600 then return end
    bump("blockedTime", seconds)
end

function H:RecordLowMana() bump("lowMana") end
function H:RecordDeath() bump("deaths") end

function H:Reset(which)
    if which == "session" or which == "all" then self.session = blank() end
    if which == "lifetime" or which == "all" then VMH.sv.history.lifetime = blank() end
end

local function top(map, n)
    local list = {}
    for k, v in pairs(map or {}) do list[#list + 1] = { k, v } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local out = {}
    for i = 1, math.min(n, #list) do out[#out + 1] = list[i][1] .. " (" .. list[i][2] .. ")" end
    return #out > 0 and table.concat(out, ", ") or "none"
end

local function fmtTime(s)
    s = math.floor(s or 0)
    if s >= 3600 then return string.format("%dh %dm", s / 3600, (s % 3600) / 60) end
    if s >= 60 then return string.format("%dm %ds", s / 60, s % 60) end
    return s .. "s"
end

function H:Summary(t)
    return table.concat({
        "Crowd control received: " .. t.cc,
        "Times silenced: " .. t.silenced .. "    Interrupted: " .. t.interrupted .. "    Stunned: " .. t.stunned,
        "Time unable to heal: " .. fmtTime(t.blockedTime),
        "Low-mana events: " .. t.lowMana .. "    Deaths: " .. t.deaths,
        "Most common CC: " .. top(t.spells, 5),
        "Interrupted by: " .. top(t.interrupters, 5),
        "CC applied by: " .. top(t.sources, 5),
    }, "\n")
end
