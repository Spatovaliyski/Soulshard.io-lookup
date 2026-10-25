local _, A = ...
local W = {}
A.Whispers = W

local LIMIT, TTL, PREVIEW_LIMIT, DELIVERY_LIMIT = 500, 86400, 512, 512
local records, guidKeys, selected, deliveries, deliveryOrder = {}, {}, {}, {}, {}
local settings, saved, ownerKey, callback, eventFrame
local initialized, incompatible, worldReady = false, false, true
local confirmedPresence, seenListing = nil, false
local generation, overflowCount, restrictedCount = 1, 0, 0
local context = { epoch = 1, activityIDs = {}, contextState = "unknown" }
local status = { state = "listing-state-unavailable", label = "Paused — checking listing" }
local defaults = {
    enabled = true, autoShow = true, mode = "any", keywords = {}, matchAll = false,
    caseSensitive = false, prefix = "", retention = "24h", animate = true, showSnapshots = true,
}
local classTokens = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}
-- englishRace values GetPlayerInfoByGUID returns for the races a TBC character can have.
local raceTokens = {
    Human = true, Dwarf = true, Gnome = true, NightElf = true, Orc = true,
    Scourge = true, Tauren = true, Troll = true, BloodElf = true, Draenei = true,
}
-- GetPlayerInfoByGUID sex: 2 is male, 3 is female.
local function sexValue(value) return (value == 2 or value == 3) and value or nil end

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

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

local function text(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum and not value:find("[%c|]")
end

local function now()
    local value, ok = read(time)
    return ok and integer(value, 1, 2147483647) and value or nil
end

local function tuple(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local value = tostring(select(index, ...) or "")
        parts[index] = #value .. ":" .. value
    end
    return table.concat(parts)
end

local function lower(value)
    return (strlower or string.lower)(value)
end

local function notify()
    if callback then callback() end
end

local function setStatus(state, label, reason)
    local changed = status.state ~= state or status.reason ~= reason
    status = { state = state, label = label, reason = reason, overflowCount = overflowCount, restrictedCount = restrictedCount }
    return changed
end

local function settingsCopy(source)
    local result = {}
    for key, value in pairs(defaults) do
        if key == "keywords" then
            result.keywords = {}
            local terms = source and source.keywords
            if type(terms) == "table" and not getmetatable(terms) then
                for index = 1, math.min(#terms, 21) do result.keywords[index] = terms[index] end
            elseif terms ~= nil then result.keywords = terms end
        else
            result[key] = source and source[key]
            if result[key] == nil then result[key] = value end
        end
    end
    return result
end

local function validateSettings(value)
    for _, key in ipairs({ "enabled", "autoShow", "matchAll", "caseSensitive", "animate", "showSnapshots" }) do
        if type(value[key]) ~= "boolean" then return false, "Invalid " .. key .. " setting." end
    end
    if value.mode ~= "any" and value.mode ~= "keywords" and value.mode ~= "prefix" then return false, "Choose a capture mode." end
    if value.retention ~= "24h" and value.retention ~= "session" then return false, "Choose 24 hours or this session." end
    if type(value.prefix) ~= "string" or #value.prefix > 64 or value.prefix:find("%c") then return false, "The prefix must be at most 64 bytes without control characters." end
    if type(value.keywords) ~= "table" or getmetatable(value.keywords) or #value.keywords > 20 then return false, "Enter at most 20 keywords." end
    local count = 0
    for key, term in pairs(value.keywords) do
        if not integer(key, 1, 20) or type(term) ~= "string" or term == "" or #term > 64 or term:find("%c") then return false, "Each keyword must contain 1–64 bytes without control characters." end
        count = count + 1
    end
    if count ~= #value.keywords then return false, "Invalid keyword list." end
    if value.mode == "keywords" and count == 0 then return false, "Enter at least one keyword." end
    if value.mode == "prefix" and value.prefix == "" then return false, "Enter a nonempty prefix." end
    return true
end

local function identityCopy(identity)
    local result = {}
    for _, key in ipairs({ "environment", "game", "region", "name", "realmName", "realmSlug", "resolution", "guid" }) do
        local value = identity[key]
        if type(value) == "string" then result[key] = value end
    end
    return result
end

local function recordKey(identity)
    if identity.resolution ~= "exact" and identity.guid then return tuple(identity.environment, identity.region, "guid", identity.guid) end
    return tuple(identity.environment, identity.region, identity.realmSlug or identity.realmName, lower(identity.name))
end

local function save()
    if not saved or incompatible or not ownerKey then return end
    saved.settings[ownerKey] = settingsCopy(settings)
    if settings.retention == "session" then saved.collections[ownerKey] = nil; return end
    local rows = {}
    for _, record in pairs(records) do
        rows[#rows + 1] = {
            identity = identityCopy(record.identity), firstSeenAt = record.firstSeenAt,
            lastSeenAt = record.lastSeenAt, count = record.count,
            firstListingEpoch = record.firstListingEpoch, lastListingEpoch = record.lastListingEpoch,
            observedClassToken = record.observedClassToken, observedLevel = record.observedLevel,
            observedRace = record.observedRace, observedSex = record.observedSex,
        }
    end
    saved.collections[ownerKey] = { schemaVersion = 1, rows = rows, epoch = context.epoch, signature = context.signature }
end

local function prune()
    local timestamp = now()
    if not timestamp then return false end
    local changed = false
    for key, record in pairs(records) do
        if record.lastSeenAt > timestamp + 300 or timestamp - record.lastSeenAt >= TTL then
            records[key], selected[key] = nil, nil
            if record.identity.guid then guidKeys[record.identity.guid] = nil end
            changed = true
        end
    end
    if changed then save() end
    return changed
end

local function restore()
    local collection = saved and saved.collections[ownerKey]
    if settings.retention == "session" then save(); return end
    if type(collection) ~= "table" or collection.schemaVersion ~= 1 or type(collection.rows) ~= "table" then return end
    local timestamp = now()
    if not timestamp then return end
    if integer(collection.epoch, 1, 1000000000) then context.epoch = collection.epoch end
    if type(collection.signature) == "string" and #collection.signature <= 512 and collection.signature:match("^[%d,]+$") then context.signature = collection.signature end
    for index = 1, math.min(#collection.rows, LIMIT) do
        local item = collection.rows[index]
        local identity = type(item) == "table" and item.identity
        if type(identity) == "table" and identity.environment == "tbc-anniversary" and identity.game == "classic-anni" and
            (identity.region == "eu" or identity.region == "us") and text(identity.name, 96) and
            (identity.realmName == nil or text(identity.realmName, 120)) and (identity.realmSlug == nil or text(identity.realmSlug, 120)) and
            (identity.guid == nil or text(identity.guid, 128)) and
            (identity.resolution == "exact" or identity.resolution == "unresolved" or identity.resolution == "conflicting") and
            integer(item.firstSeenAt, 1, timestamp + 300) and integer(item.lastSeenAt, item.firstSeenAt, timestamp + 300) and
            timestamp - item.lastSeenAt < TTL and integer(item.count, 1, 1000000000) then
            identity = identityCopy(identity)
            if identity.resolution == "exact" and (not identity.realmName or not identity.realmSlug) then identity.resolution = "unresolved" end
            local key = recordKey(identity)
            if not records[key] then
                local class = classTokens[item.observedClassToken] and item.observedClassToken or nil
                records[key] = {
                    key = key, identity = identity, firstSeenAt = item.firstSeenAt, lastSeenAt = item.lastSeenAt,
                    count = item.count, acceptedMessageCount = item.count, classToken = class, observedClassToken = class,
                    level = integer(item.observedLevel, 1, 70) and item.observedLevel or nil,
                    observedLevel = integer(item.observedLevel, 1, 70) and item.observedLevel or nil,
                    observedRace = raceTokens[item.observedRace] and item.observedRace or nil,
                    observedSex = sexValue(item.observedSex),
                    firstListingEpoch = integer(item.firstListingEpoch, 1, context.epoch) and item.firstListingEpoch or context.epoch,
                    lastListingEpoch = integer(item.lastListingEpoch, 1, context.epoch) and item.lastListingEpoch or context.epoch,
                    generation = generation, restored = true,
                }
                if identity.guid then guidKeys[identity.guid] = key end
            end
        end
    end
    seenListing = context.signature ~= nil or next(records) ~= nil
    save()
end

local function clientSupported()
    if type(GetBuildInfo) ~= "function" then return false end
    local ok, version, build, buildDate, interface = pcall(GetBuildInfo)
    if not ok or not accessible(version) or not accessible(interface) then return false end
    return type(version) == "string" and version:match("^2%.5%.") ~= nil and interface == 20506
end

local function lockedDown()
    if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.InChatMessagingLockdown) ~= "function" then return false, true end
    local value, ok = read(C_ChatInfo.InChatMessagingLockdown)
    return value, ok and type(value) == "boolean"
end

local function readContext(entry)
    local ids, ok = read(function() return entry.activityIDs end)
    if not ok then return {}, "restricted" end
    if type(ids) ~= "table" then return {}, "unknown" end
    local result, seen = {}, {}
    for index = 1, math.min(#ids, 32) do
        local id, readable = read(function() return ids[index] end)
        if not readable then return {}, "restricted" end
        if not integer(id, 1, 2147483647) then return {}, "unknown" end
        if not seen[id] then result[#result + 1], seen[id] = id, true end
    end
    table.sort(result)
    return result, #result > 0 and "known" or "unknown"
end

function W.RefreshState(quiet, leadershipChanged)
    if not initialized then return status end
    local changed
    local epochChanged = leadershipChanged == true
    if incompatible then changed = setStatus("storage-incompatible", "Paused — saved collection needs a compatible addon")
    elseif not settings.enabled then changed = setStatus("disabled", "Collector disabled")
    elseif not clientSupported() then changed = setStatus("unsupported-client", "Unavailable — requires TBC Anniversary 20506", "Other clients, including Forever, require a validated adapter.")
    elseif not ownerKey then changed = setStatus("identity-unavailable", "Paused — local character identity unavailable")
    elseif not worldReady then changed = setStatus("listing-state-unavailable", "Paused — changing world")
    else
        local lockdown, readable = lockedDown()
        if not readable or lockdown then changed = setStatus("restricted-data", "Paused — client data restricted")
        elseif type(IsInGroup) ~= "function" or type(IsInRaid) ~= "function" or type(UnitIsGroupLeader) ~= "function" or
            type(UnitIsGroupAssistant) ~= "function" or not accessible(LE_PARTY_CATEGORY_HOME) or type(LE_PARTY_CATEGORY_HOME) ~= "number" then
            changed = setStatus("capability-unavailable", "Paused — home-group APIs unavailable")
        else
            local grouped, groupedOK = read(IsInGroup, LE_PARTY_CATEGORY_HOME)
            local raid, raidOK = read(IsInRaid, LE_PARTY_CATEGORY_HOME)
            local leader, leaderOK = read(UnitIsGroupLeader, "player", LE_PARTY_CATEGORY_HOME)
            local assistant, assistantOK = read(UnitIsGroupAssistant, "player")
            if not groupedOK or not raidOK or not leaderOK or not assistantOK or type(grouped) ~= "boolean" or type(raid) ~= "boolean" or
                type(leader) ~= "boolean" or type(assistant) ~= "boolean" then
                changed = setStatus("restricted-data", "Paused — group authority unavailable")
            elseif not grouped then changed = setStatus("not-grouped", "Paused — party or raid leadership required")
            elseif not leader and not (raid and assistant) then changed = setStatus("not-leader-or-assistant", "Paused — leader or raid assistant required")
            elseif type(C_LFGList) ~= "table" or type(C_LFGList.HasActiveEntryInfo) ~= "function" or type(C_LFGList.GetActiveEntryInfo) ~= "function" then
                changed = setStatus("capability-unavailable", "Paused — active-listing API unavailable")
            else
                local active, activeOK = read(C_LFGList.HasActiveEntryInfo)
                if not activeOK or type(active) ~= "boolean" then changed = setStatus("listing-state-unavailable", "Paused — listing state unavailable")
                elseif not active then
                    confirmedPresence = "inactive"
                    changed = setStatus("not-listed", "Paused — group is not listed")
                else
                    local entry, entryOK = read(C_LFGList.GetActiveEntryInfo)
                    if not entryOK then changed = setStatus("restricted-data", "Paused — listing data restricted")
                    elseif type(entry) ~= "table" then changed = setStatus("listing-state-unavailable", "Paused — listing state unavailable")
                    else
                        local ids, contextState = readContext(entry)
                        local signature = contextState == "known" and table.concat(ids, ",") or nil
                        if (confirmedPresence == "inactive" and seenListing) or (signature and context.signature and signature ~= context.signature) then epochChanged = true end
                        confirmedPresence, seenListing = "active", true
                        context.activityIDs, context.contextState = ids, contextState
                        if signature then context.signature = signature end
                        changed = setStatus("recording", "Recording", contextState ~= "known" and "Listing activity context unavailable." or nil)
                    end
                end
            end
        end
    end
    if epochChanged then
        context.epoch = context.epoch + 1
        save()
        changed = true
    end
    if changed and not quiet then notify() end
    return status
end

local function matches(message)
    if settings.mode == "any" then return true end
    local value = settings.caseSensitive and message or lower(message)
    if settings.mode == "prefix" then
        local prefix = settings.caseSensitive and settings.prefix or lower(settings.prefix)
        return value:sub(1, #prefix) == prefix
    end
    for _, term in ipairs(settings.keywords) do
        term = settings.caseSensitive and term or lower(term)
        local found = value:find(term, 1, true) ~= nil
        if settings.matchAll and not found then return false end
        if not settings.matchAll and found then return true end
    end
    return settings.matchAll and #settings.keywords > 0
end

local function preview(message)
    local value = message:gsub("[%c]", " ")
    local last = math.min(#value, PREVIEW_LIMIT)
    if last < #value then
        while last > 0 and value:byte(last + 1) >= 128 and value:byte(last + 1) < 192 do last = last - 1 end
    end
    return value:sub(1, last)
end

local function deliverySeen(id)
    if not integer(id, 1, 2147483647) then return false end
    if deliveries[id] then return true end
    deliveries[id] = true
    deliveryOrder[#deliveryOrder + 1] = id
    if #deliveryOrder > DELIVERY_LIMIT then deliveries[table.remove(deliveryOrder, 1)] = nil end
    return false
end

local function observeClass(record, guid)
    if not guid or record.identity.resolution == "conflicting" or type(GetPlayerInfoByGUID) ~= "function" then return end
    local ok, localizedClass, token, localizedRace, race, sex, name, realm, level = pcall(GetPlayerInfoByGUID, guid)
    if not ok or not accessible(token) or not accessible(name) or not accessible(realm) or not accessible(level) or
        not accessible(race) or not accessible(sex) then return end
    if not text(name, 96) or lower(name) ~= lower(record.identity.name) then return end
    if text(realm, 120) and record.identity.realmName then
        local nativeIdentity = A.LookupIdentity and read(A.LookupIdentity, name, realm)
        if nativeIdentity and nativeIdentity.realmSlug and record.identity.realmSlug then
            if nativeIdentity.realmSlug ~= record.identity.realmSlug then return end
        elseif lower(realm) ~= lower(record.identity.realmName) then return end
    end
    if classTokens[token] then record.classToken, record.observedClassToken = token, token end
    if integer(level, 1, 70) then record.level, record.observedLevel = level, level end
    -- Race and sex are what the portrait falls back to when the character is out of range.
    if raceTokens[race] then record.observedRace = race end
    record.observedSex = sexValue(sex) or record.observedSex
end

function W.Receive(...)
    if not initialized then return false end
    W.RefreshState(true)
    if status.state ~= "recording" then notify(); return false end
    local message, author = select(1, ...), select(2, ...)
    local lineID, guid = select(11, ...), select(12, ...)
    if not accessible(message) or not accessible(author) or not accessible(guid) then
        restrictedCount = restrictedCount + 1
        setStatus("restricted-data", "Paused — whisper data restricted")
        notify()
        return false
    end
    if type(message) ~= "string" or not text(author, 240) or not matches(message) then return false end
    if guid ~= nil and (type(guid) ~= "string" or #guid > 128 or guid:find("[%c|]")) then guid = nil end
    if type(A.ResolveWhisperIdentity) ~= "function" then return false end
    local identity = A.ResolveWhisperIdentity(author, guid)
    if not identity or not text(identity.name, 96) then return false end
    if accessible(lineID) and deliverySeen(lineID) then return false end
    local timestamp = now()
    if not timestamp then return false end
    prune()
    local key = recordKey(identity)
    local record = records[key]
    local previousKey = guid and guidKeys[guid]
    local previous = previousKey and records[previousKey]
    if not record and previous and lower(previous.identity.name) == lower(identity.name) and
        (not previous.identity.realmSlug or not identity.realmSlug or previous.identity.realmSlug == identity.realmSlug) then
        record = previous
        records[previousKey], records[key] = nil, record
        if selected[previousKey] then selected[previousKey], selected[key] = nil, true end
        record.key = key
    end
    if record and guid and record.identity.guid and guid ~= record.identity.guid then
        record.identity.resolution, identity.resolution = "conflicting", "conflicting"
        key = tuple(key, guid)
        record = records[key]
        if not record and previous then
            record = previous
            records[previousKey], records[key] = nil, record
            if selected[previousKey] then selected[previousKey], selected[key] = nil, true end
            record.key = key
            record.identity.resolution = "conflicting"
        end
    end
    if not record then
        local count = 0
        for _ in pairs(records) do count = count + 1 end
        if count >= LIMIT then
            overflowCount = overflowCount + 1
            status.overflowCount = overflowCount
            notify()
            return false
        end
        record = {
            key = key, identity = identity, firstSeenAt = timestamp, lastSeenAt = timestamp,
            count = 0, acceptedMessageCount = 0, firstListingEpoch = context.epoch,
            lastListingEpoch = context.epoch, generation = generation,
        }
        records[key] = record
    elseif identity.resolution == "conflicting" then
        record.identity = identity
        record.classToken, record.observedClassToken, record.level, record.observedLevel = nil, nil, nil, nil
        record.observedRace, record.observedSex = nil, nil
    elseif identity.resolution == "exact" and record.identity.resolution ~= "conflicting" then
        record.identity = identity
    end
    record.lastSeenAt, record.lastListingEpoch = timestamp, context.epoch
    if guid then guidKeys[guid] = key end
    record.count = math.min(record.count + 1, 1000000000)
    record.acceptedMessageCount = record.count
    record.lastMessage, record.restored = preview(message), false
    observeClass(record, guid)
    save()
    notify()
    return true
end

function W.SetChangedCallback(fn)
    callback = fn
end

function W.GetSettings()
    return settingsCopy(settings)
end

function W.UpdateSettings(changes)
    if incompatible then return false, "Saved collector settings need a compatible addon." end
    if type(changes) ~= "table" then return false, "Invalid collector settings." end
    local nextSettings = settingsCopy(settings)
    for key, value in pairs(changes) do
        if defaults[key] == nil then return false, "Unknown collector setting." end
        nextSettings[key] = value
    end
    local valid, reason = validateSettings(nextSettings)
    if not valid then return false, reason end
    settings = settingsCopy(nextSettings)
    save()
    W.RefreshState(true)
    notify()
    return true
end

function W.GetRows()
    prune()
    local result = {}
    for _, record in pairs(records) do result[#result + 1] = record end
    table.sort(result, function(left, right)
        if left.lastSeenAt ~= right.lastSeenAt then return left.lastSeenAt > right.lastSeenAt end
        return left.key < right.key
    end)
    return result
end

function W.GetSelection()
    return selected
end

function W.ToggleSelection(key)
    if records[key] then selected[key] = not selected[key] or nil; notify() end
end

function W.GetStatus()
    status.overflowCount, status.restrictedCount = overflowCount, restrictedCount
    return status
end

function W.GetContext()
    return context
end

-- Drops one player. A later accepted whisper adds them again as a new row.
function W.Remove(key)
    local record = records[key]
    if not record then return false end
    records[key], selected[key] = nil, nil
    local guid = record.identity.guid
    if guid and guidKeys[guid] == key then guidKeys[guid] = nil end
    save()
    notify()
    return true
end

function W.Clear()
    generation = generation + 1
    records, guidKeys, selected, deliveries, deliveryOrder = {}, {}, {}, {}, {}
    overflowCount = 0
    context.epoch, context.signature, context.activityIDs, context.contextState = 1, nil, {}, "unknown"
    confirmedPresence, seenListing = nil, false
    save()
    W.RefreshState(true)
    notify()
end

function W.Initialize()
    if initialized then return end
    initialized = true
    settings = settingsCopy()
    if type(ArmoryLookupPreferences) ~= "table" then ArmoryLookupPreferences = {} end
    local feature = ArmoryLookupPreferences.whispers
    if type(feature) == "table" and type(feature.schemaVersion) == "number" and feature.schemaVersion > 1 then
        incompatible = true
    else
        if type(feature) ~= "table" or feature.schemaVersion ~= 1 then feature = { schemaVersion = 1, settings = {}, collections = {} } end
        if type(feature.settings) ~= "table" then feature.settings = {} end
        if type(feature.collections) ~= "table" then feature.collections = {} end
        ArmoryLookupPreferences.whispers, saved = feature, feature
    end
    local name, nameOK = read(UnitName, "player")
    local realm, realmOK = read(GetRealmName)
    local region = read(A.Region)
    if nameOK and realmOK and text(name, 96) and text(realm, 120) and (region == "eu" or region == "us") and clientSupported() then
        ownerKey = tuple("tbc-anniversary", region, realm, name)
    end
    if saved and ownerKey then
        local loaded = saved.settings[ownerKey]
        if type(loaded) == "table" then
            local candidate = settingsCopy(loaded)
            if validateSettings(candidate) then settings = candidate end
        end
        restore()
    end
    eventFrame = CreateFrame("Frame")
    for _, event in ipairs({ "CHAT_MSG_WHISPER", "LFG_LIST_ACTIVE_ENTRY_UPDATE", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD" }) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_WHISPER" then W.Receive(...); return end
        if event == "PLAYER_LEAVING_WORLD" then worldReady = false
        elseif event == "PLAYER_ENTERING_WORLD" then worldReady = true end
        W.RefreshState(true, event == "PARTY_LEADER_CHANGED")
        notify()
    end)
    W.RefreshState(true)
    notify()
end
