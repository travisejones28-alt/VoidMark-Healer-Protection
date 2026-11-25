-- VoidMark Healer - announcements
-- Every alert goes through Alert(): gating, cooldown, duplicate suppression,
-- channel resolution, priority queue and global throttle.
-- General, Trade and guild chat are never used.
local _, VMH = ...
local A = VMH:NewModule("Announce")

A.last = {}        -- alert key -> last time fired
A.recent = {}      -- dedupe key -> time
A.queue = {}
A.lastSend = -100
A.flushScheduled = false

------------------------------------------------------------------------
-- Text formatting
------------------------------------------------------------------------
function VMH.FormatDuration(sec)
    sec = VMH.Number(sec)
    if not sec or sec <= 0 then return nil end
    return string.format("%ds", math.ceil(sec - 0.05))
end

local function tokenValue(vars, k)
    local v = vars and vars[k]
    if v == nil or v == "" then return nil end
    return tostring(v)
end

-- Tokens without a value are removed; a "( )" group left empty disappears.
function A.Format(text, vars)
    text = tostring(text or "")
    text = text:gsub("(%s*)%(([^()]*)%)", function(space, inner)
        if not inner:find("{%w+}") then return nil end
        inner = inner:gsub("{(%w+)}(%%?)", function(k, pct)
            local v = tokenValue(vars, k)
            if v == nil then return "" end
            return v .. pct
        end)
        inner = inner:gsub("^[%s,;:%-]+", ""):gsub("[%s,;:%-]+$", ""):gsub(",%s*,", ",")
        if inner == "" then return "" end
        return space .. "(" .. inner .. ")"
    end)
    text = text:gsub("{(%w+)}(%%?)", function(k, pct)
        local v = tokenValue(vars, k)
        if v == nil then return "" end
        return v .. pct
    end)
    text = text:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+([!%.,])", "%1")
    return text
end

local function sanitize(msg)
    msg = msg:gsub("|", "/")
    if #msg > 250 then msg = msg:sub(1, 250) end
    return msg
end

------------------------------------------------------------------------
-- Channels
------------------------------------------------------------------------
local function inGroup(cat)
    if cat ~= nil then return VMH.Safe(_G.IsInGroup, cat) == true end
    return VMH.Safe(_G.IsInGroup) == true
end

-- Returns an ordered list of chat types and a flag for local printing.
function A:ResolveChannels(channels)
    local ctx = VMH:GetContext()
    local INSTANCE = _G.LE_PARTY_CATEGORY_INSTANCE
    local HOME = _G.LE_PARTY_CATEGORY_HOME
    local inInstanceGroup = INSTANCE and inGroup(INSTANCE) or false
    local inHome = HOME and inGroup(HOME) or inGroup()
    local raid = VMH.Safe(_G.IsInRaid) == true
    local pvpZone = ctx.instanceType == "pvp" or ctx.instanceType == "arena"
    local set, selfPrint = {}, false
    channels = channels or {}

    if channels.auto then
        if inInstanceGroup then set.INSTANCE_CHAT = true
        elseif raid then set.RAID = true
        elseif inHome then set.PARTY = true end
    end
    if channels.party and inHome then set.PARTY = true end
    if channels.raid and raid then
        if inHome then set.RAID = true elseif inInstanceGroup then set.INSTANCE_CHAT = true end
    end
    if channels.instance and inInstanceGroup and not pvpZone then set.INSTANCE_CHAT = true end
    if channels.bg and pvpZone and (inInstanceGroup or inHome) then
        set[inInstanceGroup and "INSTANCE_CHAT" or (raid and "RAID" or "PARTY")] = true
    end
    -- The client only lets addons use Say/Yell inside instances.
    if channels.say and ctx.inInstance then set.SAY = true end
    if channels.yell and ctx.inInstance then set.YELL = true end
    if channels.self then selfPrint = true end

    -- Duplicate prevention: one group channel reaches everyone once.
    if set.RAID then set.PARTY = nil end
    if set.INSTANCE_CHAT then set.PARTY = nil; set.RAID = nil end
    if set.YELL then set.SAY = nil end

    local list = {}
    for _, t in ipairs({ "INSTANCE_CHAT", "RAID", "PARTY", "YELL", "SAY" }) do
        if set[t] then list[#list + 1] = t end
    end
    return list, selfPrint
end

local function chatLocked()
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and VMH.Readable(locked) == true
    end
    return false
end
A.ChatLocked = chatLocked

-- Re-checked at send time: the group may have changed while a message waited.
function A:StillValid(chatType)
    if chatType == "PARTY" then return inGroup() end
    if chatType == "RAID" then return VMH.Safe(_G.IsInRaid) == true end
    if chatType == "INSTANCE_CHAT" then
        local cat = _G.LE_PARTY_CATEGORY_INSTANCE
        return cat ~= nil and inGroup(cat)
    end
    if chatType == "SAY" or chatType == "YELL" then return VMH.Safe(_G.IsInInstance) == true end
    return false
end

local function send(msg, chatType)
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, msg, chatType)
    if not ok then VMH:Debug("send failed (" .. chatType .. "): " .. tostring(err)) end
    return ok
end

------------------------------------------------------------------------
-- Queue: highest priority first, one announcement per throttle interval.
------------------------------------------------------------------------
function A:Flush()
    self.flushScheduled = false
    local now = VMH.Now()
    local q = self.queue
    for i = #q, 1, -1 do
        if q[i].expires and q[i].expires < now then
            VMH:Debug("dropped stale: " .. q[i].text)
            table.remove(q, i)
        end
    end
    if #q == 0 then return end
    local gap = VMH.db and VMH.db.announce.throttle or 1
    local wait = (self.lastSend + gap) - now
    if wait > 0 then
        self:Schedule(wait)
        return
    end
    table.sort(q, function(a, b)
        if a.prio ~= b.prio then return a.prio > b.prio end
        return a.created < b.created
    end)
    local entry = table.remove(q, 1)
    self.lastSend = now
    if chatLocked() then
        VMH:Print(entry.text .. " |cff888888(group chat is locked by the game right now)|r")
    else
        for _, ct in ipairs(entry.chatTypes) do
            if self:StillValid(ct) then send(entry.text, ct)
            else VMH:Debug("skipped " .. ct .. " (no longer in that group): " .. entry.text) end
        end
    end
    if #q > 0 then self:Schedule(gap) end
end

function A:Schedule(delay)
    if self.flushScheduled then return end
    self.flushScheduled = true
    VMH.After(math.max(0.05, delay), function() A:Flush() end)
end

function A:Enqueue(text, chatTypes, prio, expires)
    local q = self.queue
    -- Routine alerts never pile up behind a burst; keep at most 6 waiting.
    if #q >= 6 then
        table.sort(q, function(a, b) return a.prio > b.prio end)
        if q[#q].prio > prio then return end
        table.remove(q)
    end
    q[#q + 1] = { text = text, chatTypes = chatTypes, prio = prio, created = VMH.Now(),
        expires = expires or (VMH.Now() + (prio >= 4 and 8 or 5)) }
    self:Flush()
end

------------------------------------------------------------------------
-- Local feedback
------------------------------------------------------------------------
function A:PlaySound(key)
    if not VMH.db.visuals.sound or not key or key == "none" then return end
    for _, s in ipairs(VMH.SOUNDS) do
        if s.key == key and s.id then
            VMH.Safe(_G.PlaySound, s.id, VMH.db.visuals.soundChannel or "Master")
            return
        end
    end
end

function A:OnScreen(text, prio)
    if not VMH.db.visuals.onscreen then return end
    local frame = _G.RaidWarningFrame
    local add = _G.RaidNotice_AddMessage
    if frame and type(add) == "function" then
        local color = { r = 0.75, g = 0.45, b = 1 }
        if prio >= 5 then color = { r = 1, g = 0.25, b = 0.3 } end
        pcall(add, frame, text, color)
    end
end

------------------------------------------------------------------------
-- Gating
------------------------------------------------------------------------
function A:ContextAllowed(cfg)
    if cfg.context == "any" or not cfg.context then return true end
    local ctx = VMH:GetContext()
    if cfg.context == "pvp" then return ctx.pvp end
    if cfg.context == "pve" then return not ctx.pvp end
    return true
end

-- opts: test (button/command), sim (simulation), expires (drop if late),
--       dedupe (custom duplicate key), ignoreCooldown
function A:Alert(key, vars, opts)
    opts = opts or {}
    local def = VMH.ALERT_BY_KEY[key]
    local db = VMH.db
    if not def or not db then return false, "unknown" end
    local cfg = db.alerts[key]
    local manual = opts.test or opts.sim
    if not db.general.enabled and not opts.test then return false, "disabled" end
    if not cfg.enabled and not opts.test then return false, "alert off" end
    if not manual then
        if not VMH:IsActiveHere() then return false, "not active here" end
        if not self:ContextAllowed(cfg) then return false, "context" end
        if not VMH:IsHealerActive() then return false, "not healer" end
    end
    local now = VMH.Now()
    if not manual and not opts.ignoreCooldown and cfg.cooldown and cfg.cooldown > 0 then
        local last = self.last[key]
        if last and now - last < cfg.cooldown then return false, "cooldown" end
    end

    local text = A.Format(cfg.text ~= "" and cfg.text or def.text, vars)
    if text == "" then return false, "empty" end

    local dkey = opts.dedupe or text
    local window = db.announce.duplicateWindow or 0
    if not manual then
        if window > 0 then
            local seen = self.recent[dkey]
            if seen and now - seen < window then return false, "duplicate" end
        end
        self.recent[dkey] = now
        self.last[key] = now
        for k, t in pairs(self.recent) do if now - t > 60 then self.recent[k] = nil end end
    end

    self:PlaySound(cfg.sound)
    if cfg.onscreen then self:OnScreen(text, def.prio) end

    local chatTypes, selfPrint = self:ResolveChannels(cfg.channels)
    local outgoing = db.announce.outgoing
    local prefix = db.announce.prefix or ""
    local msg = sanitize((prefix ~= "" and (prefix .. " ") or "") .. text)

    local localOnly = opts.sim or (opts.test and not db.general.testsSendChat)
    if localOnly then
        local where = #chatTypes > 0 and table.concat(chatTypes, "+") or (selfPrint and "self" or "no channel")
        VMH:Print("|cffffd200[" .. (opts.sim and "SIM" or "TEST") .. " -> " .. where .. "]|r " .. msg)
        return true, "local"
    end
    if selfPrint then VMH:Print(text) end
    if outgoing and #chatTypes > 0 then
        self:Enqueue(msg, chatTypes, def.prio, opts.expires)
    elseif #chatTypes > 0 then
        VMH:Debug("outgoing disabled: " .. msg)
    end
    return true, "sent"
end

function A:OnSettingsChanged()
    self.queue = {}
end
