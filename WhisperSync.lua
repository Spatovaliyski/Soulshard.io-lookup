local _, A = ...
local S = {}
A.WhisperSync = S

-- Leaders and assistants share the whisper roster over the hidden addon channel: who whispered, never what they said.
-- Every addon in the group can read what is sent and a client can be edited, so the wire carries only what any raid
-- member could look up, and a receiver trusts a sender only by the group rank the server reports for that character.
-- Messages are "<version>|<op>|<fields>", at most 255 bytes:
--   U|<snapshot 0/1>|<name|realm|class|level|race|sex|count|lastAge|firstAge>...  rows (ages in seconds, never clocks)
--   D|<name|realm>...   rows removed        X   roster reset        H   a new member asks for the roster
--   S|<listed 0/1>|<activity ids>   the leader's listing, so an assistant who does not own it can still collect
local PREFIX, VERSION = "SoulshardWL", "1"
local HELLO = VERSION .. "|H"
local FIELDS, BATCH_BYTES, MAX_AGE = 9, 230, 86399
-- The client allows ten messages per prefix and then one a second; stay well under that so raid addons keep their share.
local BURST, FLUSH_DELAY, TICK = 4, 0.5, 1
local HEARTBEAT, RELAY_TTL, HELLO_DELAY = 60, 180, 2

local initialized = false
local queue = {}
local dirty, dirtyOrder, snapshotMode = {}, {}, false
local tokens, stamp, failures = BURST, 0, 0
local pumping, helloPending, helloSent, responsePending = false, false, false, false
local snapshotSeen, announced, listing = -1, false, nil
local pump, schedule

local function accessible(value)
    if type(canaccessvalue) == "function" then
        local ok, allowed = pcall(canaccessvalue, value)
        return ok and allowed == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret == false
    end
    return true
end

local function read(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, ...)
    if not ok or not accessible(value) then return nil, false end
    return value, true
end

local function text(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum and not value:find("[%c|]")
end

local function lower(value)
    return (strlower or string.lower)(value)
end

local function squash(value)
    return (lower(value):gsub("[%s%-']", ""))
end

-- Plain finds keep empty fields identical on every Lua version.
local function split(message)
    local parts, position = {}, 1
    while true do
        local found = message:find("|", position, true)
        if not found then parts[#parts + 1] = message:sub(position); return parts end
        parts[#parts + 1] = message:sub(position, found - 1)
        position = found + 1
    end
end

local function role()
    local W = A.Whispers
    return W and W.SyncRole and W.SyncRole() or nil
end

local function channel()
    if read(IsInGroup, LE_PARTY_CATEGORY_HOME) ~= true then return nil end
    return read(IsInRaid, LE_PARTY_CATEGORY_HOME) == true and "RAID" or "PARTY"
end

local function canPublish()
    return role() == "authority" and channel() ~= nil
end

local function isLeader()
    return read(UnitIsGroupLeader, "player", LE_PARTY_CATEGORY_HOME) == true
end

local function after(seconds, fn)
    C_Timer.After(seconds, fn)
end

-- The unit token of the group member a sender names ("Name" on this realm, "Name-Realm" elsewhere), or nil.
local function unitFor(sender)
    local want, wantRealm = lower(sender), nil
    local bare, suffix = want:match("^([^-]+)%-(.+)$")
    if bare then want, wantRealm = bare, suffix end
    local own = read(GetRealmName)
    own = (type(own) == "string" and own ~= "") and squash(own) or ""
    wantRealm = wantRealm and squash(wantRealm) or own
    local raid = read(IsInRaid, LE_PARTY_CATEGORY_HOME) == true
    local units = { "player" }
    for index = 1, raid and 40 or 4 do units[#units + 1] = (raid and "raid" or "party") .. index end
    for _, unit in ipairs(units) do
        local ok, name, realm = pcall(UnitName, unit)
        if ok and accessible(name) and type(name) == "string" and name ~= "" and lower(name) == want then
            local unitRealm = (accessible(realm) and type(realm) == "string" and realm ~= "") and squash(realm) or own
            if unitRealm == wantRealm then return unit end
        end
    end
end

-- Only the server knows who leads or assists, so a sender's authority is read from the group, never from the message.
local function rankOf(unit)
    if read(UnitIsGroupLeader, unit) == true then return "leader" end
    if read(IsInRaid, LE_PARTY_CATEGORY_HOME) == true and read(UnitIsGroupAssistant, unit) == true then return "assistant" end
    return nil
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function send(message, target)
    local fn = type(C_ChatInfo) == "table" and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, PREFIX, message, target)
    if not ok then return false end
    local success = type(Enum) == "table" and type(Enum.SendAddonMessageResult) == "table" and Enum.SendAddonMessageResult.Success
    return result == nil or result == true or result == 0 or (success ~= nil and success ~= false and result == success)
end

local function age(timestamp, since)
    return math.max(0, math.min(MAX_AGE, math.floor(timestamp - (since or timestamp))))
end

local function encode(record, timestamp)
    local identity = record.identity
    if type(identity) ~= "table" or identity.resolution == "conflicting" or not text(identity.name, 96) then return nil end
    local realm = identity.realmName
    if not text(realm, 120) then realm = "" end
    local last = age(timestamp, record.lastSeenAt)
    return table.concat({
        identity.name, realm, record.observedClassToken or record.classToken or "", record.observedLevel or record.level or "",
        record.observedRace or "", record.observedSex or "", math.min(record.count or 1, 1000000000), last,
        math.max(last, age(timestamp, record.firstSeenAt)),
    }, "|")
end

local function enqueue(message)
    queue[#queue + 1] = message
end

local function markDirty(key)
    if not dirty[key] then
        dirty[key] = true
        dirtyOrder[#dirtyOrder + 1] = key
    end
end

local function consume(count)
    for index = 1, count do dirty[dirtyOrder[index]] = nil end
    local rest = {}
    for index = count + 1, #dirtyOrder do rest[#rest + 1] = dirtyOrder[index] end
    dirtyOrder = rest
    if #dirtyOrder == 0 then snapshotMode = false end
end

-- News that is no longer ours to send, or no longer true, is dropped; a request for the roster is still wanted.
local function dropPending()
    local kept = {}
    for _, message in ipairs(queue) do if message == HELLO then kept[#kept + 1] = message end end
    queue, dirty, dirtyOrder, snapshotMode = kept, {}, {}, false
end

-- Packs as many pending rows as fit in one message. The second result is how many pending entries it used up.
local function nextBatch(lookup)
    local timestamp = time()
    local message = VERSION .. "|U|" .. (snapshotMode and "1" or "0")
    local used, parts, consumed = #message, 0, 0
    for index, key in ipairs(dirtyOrder) do
        local record = lookup[key]
        local encoded = record and encode(record, timestamp)
        if encoded then
            if parts > 0 and used + 1 + #encoded > BATCH_BYTES then break end
            message = message .. "|" .. encoded
            used, parts = used + 1 + #encoded, parts + 1
        end
        consumed = index
    end
    return parts > 0 and message or nil, consumed
end

local function rowsByKey()
    local lookup = {}
    for _, record in ipairs(A.Whispers.GetRows()) do lookup[record.key] = record end
    return lookup
end

local function refill()
    local current = GetTime()
    tokens = math.min(BURST, tokens + (current - stamp))
    stamp = current
end

pump = function()
    pumping = false
    local target, mine = channel(), role()
    if not target or not mine then queue, dirty, dirtyOrder, snapshotMode = {}, {}, {}, false; return end
    if mine ~= "authority" then dropPending() end
    refill()
    local lookup
    while tokens >= 1 do
        local message, consumed, fromQueue
        if #queue > 0 then message, fromQueue = queue[1], true
        elseif #dirtyOrder > 0 then
            lookup = lookup or rowsByKey()
            message, consumed = nextBatch(lookup)
        else break end
        if message and not send(message, target) then
            -- Throttled or locked down: wait for the next tick, and give up on a message that keeps failing.
            failures, tokens = failures + 1, 0
            if failures >= 5 then queue, dirty, dirtyOrder, snapshotMode, failures = {}, {}, {}, false, 0 end
            break
        end
        if message then tokens, failures = tokens - 1, 0 end
        if fromQueue then table.remove(queue, 1) else consume(consumed) end
    end
    if #queue > 0 or #dirtyOrder > 0 then schedule(TICK) end
end

schedule = function(delay)
    if pumping then return end
    pumping = true
    after(delay, pump)
end

-- The leader tells the group when it is listed, because an assistant may not own the listing the collector needs.
local function announceListing()
    if not canPublish() or not isLeader() then return end
    local W = A.Whispers
    local recording = W.GetStatus().state == "recording"
    if not recording and not announced then return end
    announced = recording
    enqueue(VERSION .. "|S|" .. (recording and "1" or "0") .. "|" .. (recording and (W.GetContext().signature or "") or ""))
    schedule(FLUSH_DELAY)
end

local function respond()
    if not canPublish() then return end
    for _, record in ipairs(A.Whispers.GetRows()) do markDirty(record.key) end
    snapshotMode = #dirtyOrder > 0
    schedule(0)
    announceListing()
end

-- Everyone who joins asks once; one leader answers for all of them, and the rest stay quiet when they hear it.
local function onHello()
    if role() ~= "authority" or responsePending then return end
    responsePending = true
    local heardAt = GetTime()
    after(isLeader() and 0.5 or 2.5 + math.random() * 2.5, function()
        responsePending = false
        if snapshotSeen < heardAt then respond() end
    end)
end

local function onLocal(event, first, second)
    if event == "upsert" then
        if canPublish() then markDirty(first.key); schedule(FLUSH_DELAY) end
    elseif event == "remove" then
        if canPublish() then
            enqueue(VERSION .. "|D|" .. second.name .. "|" .. (text(second.realmName, 120) and second.realmName or ""))
            schedule(FLUSH_DELAY)
        end
    elseif event == "reset" then
        -- A reset the roster made by itself (a new raid) is the leader's to announce; an explicit one is anyone's.
        if canPublish() and (not first or isLeader()) then
            dropPending()
            enqueue(VERSION .. "|X")
            schedule(FLUSH_DELAY)
        end
    elseif event == "state" then
        announceListing()
    end
end

local function scheduleHello()
    if helloPending then return end
    helloPending = true
    after(HELLO_DELAY, function()
        helloPending = false
        if read(IsInGroup, LE_PARTY_CATEGORY_HOME) ~= true then helloSent = false; return end
        if helloSent or not role() then return end
        helloSent = true
        enqueue(HELLO)
        schedule(FLUSH_DELAY)
    end)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

-- The activity ids the group's leader reported while it is listed, or nil.
function S.Listing()
    if not listing then return nil end
    if GetTime() - listing.at > RELAY_TTL then listing = nil; return nil end
    local unit = unitFor(listing.sender)
    if not unit or rankOf(unit) ~= "leader" then listing = nil; return nil end
    return listing.ids
end

function S.Receive(prefix, message, channelName, sender)
    if prefix ~= PREFIX or (channelName ~= "RAID" and channelName ~= "PARTY") then return false end
    if not accessible(message) or not accessible(sender) or type(message) ~= "string" or #message > 255 or not text(sender, 240) then return false end
    local W = A.Whispers
    if not W or not role() then return false end
    local fields = split(message)
    if fields[1] ~= VERSION then return false end
    local unit = unitFor(sender)
    if not unit or unit == "player" then return false end
    local op = fields[2]
    -- Anyone may ask for the roster.
    if op == "H" then onHello(); return true end
    -- Only a leader or assistant may change it.
    local rank = rankOf(unit)
    if not rank then return false end
    if op == "U" then
        local count = #fields - 3
        if (fields[3] ~= "0" and fields[3] ~= "1") or count < FIELDS or count % FIELDS ~= 0 then return false end
        if fields[3] == "1" then snapshotSeen = GetTime() end
        local merged = 0
        for index = 4, #fields, FIELDS do
            local realm, class = fields[index + 1], fields[index + 2]
            if W.MergeRemote({
                name = fields[index], realm = realm ~= "" and realm or nil, classToken = class ~= "" and class or nil,
                level = tonumber(fields[index + 3]), race = fields[index + 4], sex = tonumber(fields[index + 5]),
                count = tonumber(fields[index + 6]), lastAge = tonumber(fields[index + 7]), firstAge = tonumber(fields[index + 8]),
            }, sender) then merged = merged + 1 end
        end
        return merged > 0
    elseif op == "D" then
        local count = #fields - 2
        if count < 2 or count % 2 ~= 0 then return false end
        for index = 3, #fields, 2 do W.RemoveRemote(fields[index], fields[index + 1] ~= "" and fields[index + 1] or nil) end
        return true
    elseif op == "X" then
        return W.ResetRemote()
    elseif op == "S" then
        if rank ~= "leader" then return false end
        listing = nil
        if fields[3] == "1" then
            local ids = {}
            for id in (fields[4] or ""):gmatch("%d+") do
                id = tonumber(id)
                if id and id >= 1 and id <= 2147483647 and #ids < 32 then ids[#ids + 1] = id end
            end
            table.sort(ids)
            listing = { at = GetTime(), sender = sender, ids = ids }
        end
        W.RefreshState()
        return true
    end
    return false
end

local function beat()
    announceListing()
    after(HEARTBEAT, beat)
end

function S.Initialize()
    if initialized then return true end
    local W = A.Whispers
    local register = type(C_ChatInfo) == "table" and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if not W or type(W.SetSyncListener) ~= "function" or type(register) ~= "function" then return false end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false end
    local ok, result = pcall(register, PREFIX)
    if not ok or result == false then return false end
    initialized = true
    stamp = GetTime()
    W.SetSyncListener(onLocal)
    W.SetListingRelay(S.Listing)
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then S.Receive(...) else scheduleHello() end
    end)
    scheduleHello()
    announceListing()
    after(HEARTBEAT, beat)
    return true
end
