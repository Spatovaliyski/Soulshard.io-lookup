local _, A = ...
local P = {}
A.WhisperProfiles = P

-- Mirror the website: one bulk page holds `bulkLimit` characters and its link may be `bulkUrlLimit` characters long
-- (frontend/src/models/BulkInspectModel.ts and frontend/src/lib/bulkLink.ts). A link names one realm, so players from
-- several realms, or a list past either limit, still need more than one link.
local urlLimit, playerLimit = 6000, 100
local origin = "https://soulshard.io"

local function accessible(value)
    if canaccessvalue then
        local ok, allowed = pcall(canaccessvalue, value)
        if not ok or not allowed then return false end
    elseif issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    return true
end

local function text(value, maximum)
    return accessible(value) and type(value) == "string" and #value > 0 and #value <= maximum and not value:find("[%c|]")
end

local function lower(value)
    return (strlower or string.lower)(value)
end

local function knownClass(token)
    return type(token) == "string" and A.catalogs and A.catalogs[token] and token or nil
end

local function observedLevel(record)
    local level = record.observedLevel or record.level
    if type(level) == "number" and level == math.floor(level) and level >= 1 and level <= 70 then return level end
end

-- Only an explicit suffix or matching GUID evidence can establish the sender's realm.
-- LookupIdentity owns the same canonical realm handling as the existing web lookup.
function A.ResolveWhisperIdentity(rawName, guid)
    if not text(rawName, 240) then return nil end
    local name, realm = rawName:match("^([^-]+)%-(.+)$")
    name = name or rawName
    if not text(name, 192) then return nil end
    local conflicting = false
    if text(guid, 128) and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, nativeName, nativeRealm = pcall(GetPlayerInfoByGUID, guid)
        if ok and text(nativeName, 192) then
            if lower(nativeName) ~= lower(name) then conflicting = true
            elseif accessible(nativeRealm) and type(nativeRealm) == "string" then
                -- LibRealmInfo:GetRealmInfoByGUID treats an empty realm as local:
                -- https://github.com/phanx-wow/LibRealmInfo/blob/master/LibRealmInfo.lua
                -- Apply that caller convention only after the GUID corroborates the name.
                if nativeRealm == "" and GetRealmName then
                    local realmOK, localRealm = pcall(GetRealmName)
                    if realmOK and text(localRealm, 128) then nativeRealm = localRealm end
                end
                if text(nativeRealm, 128) then
                    if not realm then realm = nativeRealm
                    elseif A.LookupIdentity then
                        local author = A.LookupIdentity(name, realm)
                        local native = A.LookupIdentity(nativeName, nativeRealm)
                        if author and native and author.realmSlug ~= native.realmSlug then conflicting = true end
                    end
                end
            end
        end
    end
    local resolved
    if text(realm, 128) and A.LookupIdentity then resolved = A.LookupIdentity(name, realm) end
    local identity = {
        environment = "tbc-anniversary",
        game = "classic-anni",
        region = A.Region and A.Region() or nil,
        name = name,
        realmName = realm,
        resolution = "unresolved",
    }
    if text(guid, 128) then identity.guid = guid end
    if resolved then
        identity.name = resolved.name
        identity.region = resolved.region
        identity.realmName = resolved.realmName or realm
        identity.realmSlug = resolved.realmSlug
        identity.resolution = "exact"
    end
    if conflicting then identity.resolution = "conflicting" end
    return identity
end

function P.Contexts()
    return A.raidLibrary or {}
end

-- Raid library ids by the letters of an activity name. The listing API names activities in the client's language,
-- so a name that matches none of these stays unrecognised and the raid-parse picker asks the player instead.
local raidNames = {
    karazhan = { "karazhan" }, gruul = { "gruul" }, magtheridon = { "magtheridon" }, ssc = { "serpentshrine" },
    ["tempest-keep"] = { "tempestkeep" }, hyjal = { "hyjal" }, ["black-temple"] = { "blacktemple" },
    ["zul-aman"] = { "zulaman" }, sunwell = { "sunwell" },
}
-- Filled from an in-game dump of C_LFGList.GetActiveEntryInfo() activity ids when names alone are not enough.
P.activityRaids = {}

local function letters(value)
    return type(value) == "string" and (lower(value):gsub("[^a-z]", "")) or ""
end

-- The raid-library entry for the first listed activity this addon recognises, or nil.
function P.RaidForActivities(activityIDs)
    if type(activityIDs) ~= "table" then return nil end
    local function entry(id)
        for _, raid in ipairs(P.Contexts()) do if raid.id == id then return raid end end
    end
    for _, activityID in ipairs(activityIDs) do
        local mapped = P.activityRaids[activityID]
        if mapped and entry(mapped) then return entry(mapped) end
        local info
        if C_LFGList and type(C_LFGList.GetActivityInfoTable) == "function" then
            local ok, value = pcall(C_LFGList.GetActivityInfoTable, activityID)
            if ok and type(value) == "table" then info = value end
        end
        if info then
            local name = letters(info.fullName) .. "|" .. letters(info.shortName)
            for id, fragments in pairs(raidNames) do
                for _, fragment in ipairs(fragments) do
                    if name:find(fragment, 1, true) and entry(id) then return entry(id) end
                end
            end
        end
    end
    return nil
end

function P.AgeLabel(timestamp)
    if type(timestamp) ~= "number" or timestamp ~= timestamp or timestamp == math.huge or timestamp == -math.huge then return "age unknown" end
    local age = time() - timestamp
    if age < 0 then return "timestamp invalid" end
    if age < 60 then return "less than 1m old" end
    if age < 3600 then return math.floor(age / 60) .. "m old" end
    return math.floor(age / 3600) .. "h old"
end

local function savedCharacter(identity)
    if type(identity) ~= "table" or identity.environment ~= "tbc-anniversary" or identity.game ~= "classic-anni" then return nil end
    if identity.resolution ~= "exact" then return nil end
    if not A.Region or identity.region ~= A.Region() then return nil end
    local realm = identity.realmSlug or identity.realmName
    if not text(identity.name, 192) or not text(realm, 128) or not A.ResolveName or not A.FindCharacter then return nil end
    local resolved = A.ResolveName(identity.name, realm)
    return resolved and A.FindCharacter(resolved) or nil
end

local function section(character, id, details)
    for _, descriptor in ipairs(A.sections or {}) do
        if descriptor.id == id then
            local ok, value = pcall(details and A.GetSection or A.GetSectionSummary, character, descriptor)
            if ok and type(value) == "table" then return value end
            return { state = "unavailable" }
        end
    end
end

-- This path intentionally reads installed snapshots only. It must not schedule a live inspect.
function P.Enrich(record, contextID)
    local result = {
        classToken = knownClass(record.observedClassToken or record.classToken),
        level = observedLevel(record),
        raceToken = record.observedRace,
        sex = record.observedSex,
        snapshotState = "missing",
        ageLabel = "No snapshot",
    }
    local ok, character = pcall(savedCharacter, record.identity)
    if not ok then result.snapshotState = "invalid"; result.ageLabel = "Snapshot unavailable"; return result end
    if not character then return result end
    local summary = character.summary or {}
    local snapshotClass = knownClass(summary.classToken)
    if result.classToken and snapshotClass and result.classToken ~= snapshotClass then
        result.snapshotState = "conflicting"
        result.ageLabel = "Snapshot identity conflict"
        return result
    end
    result.snapshotState = "matched"
    result.classToken = result.classToken or snapshotClass
    if not result.level and type(summary.level) == "number" then result.level = summary.level; result.levelSource = "snapshot" end
    local equipment = section(character, "equipment")
    if equipment then
        result.equipmentState = equipment.state
        if equipment.data then
            result.gearScore = equipment.data.gearScore and equipment.data.gearScore.value
            result.equipmentAt = equipment.fetchedAt
            result.gearScoreMetric = equipment.data.gearScore and equipment.data.gearScore.algorithm
        end
    end
    if contextID then
        local raids = section(character, "raids", true)
        result.raidsState = raids and raids.state or "unavailable"
        if raids and raids.data then
            for _, raid in ipairs(raids.data.raids) do
                if raid.id == contextID then
                    result.raidName = raid.name
                    result.averageParse = A.AverageRaidParse(raid)
                    result.bestParse = raid.bestParse
                    result.raidsAt = raids.fetchedAt
                    break
                end
            end
        end
    end
    result.equipmentAgeLabel = P.AgeLabel(result.equipmentAt)
    result.raidsAgeLabel = P.AgeLabel(result.raidsAt)
    local oldest = result.equipmentAt
    if result.raidsAt and (not oldest or result.raidsAt < oldest) then oldest = result.raidsAt end
    result.ageLabel = "Snapshot: " .. P.AgeLabel(oldest)
    result.stale = type(oldest) == "number" and time() - oldest > (A.staleAfter or 86400) or false
    return result
end

-- Match encodeURIComponent: the existing importer decodes the names path once.
local function encode(value)
    return (value:gsub("[^A-Za-z0-9%-._~!'()*]", function(character) return string.format("%%%02X", string.byte(character)) end))
end

local function validName(name)
    if not text(name, 192) or name:gsub("['%-]", ""):find("[ %d%p]") then return false end
    local characters = 0
    for index = 1, #name do
        local byte = name:byte(index)
        if byte < 128 or byte >= 192 then characters = characters + 1 end
    end
    -- WoW supplies valid UTF-8 names. Keep the web model's 2..48 character bound
    -- without attempting to transliterate names or implement Unicode normalization.
    return characters >= 2 and characters <= 48
end

local function exportIdentity(record)
    local identity = record.identity
    if type(identity) ~= "table" then return nil, "Identity unavailable" end
    if identity.resolution ~= "exact" then return nil, identity.resolution == "conflicting" and "Identity evidence conflicts" or "Identity unresolved" end
    if identity.environment ~= "tbc-anniversary" or identity.game ~= "classic-anni" then return nil, "This game has no supported bulk importer" end
    if identity.region ~= "eu" and identity.region ~= "us" then return nil, "Region unresolved" end
    if not validName(identity.name) then return nil, "Character name invalid" end
    local resolved = identity
    if not identity.realmSlug and text(identity.realmName, 128) and A.LookupIdentity and A.Region and identity.region == A.Region() then
        resolved = A.LookupIdentity(identity.name, identity.realmName) or identity
    end
    if type(resolved.realmSlug) ~= "string" or #resolved.realmSlug == 0 or #resolved.realmSlug > 100 or not resolved.realmSlug:match("^[a-z0-9%-]+$") then return nil, "Realm unresolved" end
    return { region = identity.region, realmSlug = resolved.realmSlug, name = resolved.name or identity.name }
end

function P.BuildExport(records, selectedKeys, currentEpoch)
    local selected = false
    for _, enabled in pairs(selectedKeys or {}) do if enabled then selected = true; break end end
    local result = { urls = {}, counts = {}, count = 0, excluded = {}, earlierCount = 0, scopeCount = 0 }
    local groups, groupKeys, seen = {}, {}, {}
    for _, record in ipairs(records) do
        if not selected or selectedKeys[record.key] then
            result.scopeCount = result.scopeCount + 1
            local identity, reason = exportIdentity(record)
            if not identity then
                result.excluded[#result.excluded + 1] = { name = record.identity and record.identity.name or "Unknown", reason = reason }
            else
                local groupKey = identity.region .. "/" .. identity.realmSlug
                local key = groupKey .. "/" .. lower(identity.name)
                if not seen[key] then
                    seen[key] = true
                    if not groups[groupKey] then groups[groupKey] = {}; groupKeys[#groupKeys + 1] = groupKey end
                    groups[groupKey][#groups[groupKey] + 1] = identity.name
                    if currentEpoch and record.lastListingEpoch ~= currentEpoch then result.earlierCount = result.earlierCount + 1 end
                end
            end
        end
    end
    table.sort(groupKeys)
    for _, key in ipairs(groupKeys) do
        local names = groups[key]
        table.sort(names, function(left, right)
            local leftKey, rightKey = lower(left), lower(right)
            return leftKey == rightKey and left < right or leftKey < rightKey
        end)
        local base = origin .. "/inspect/bulk/classic-anni/" .. key .. "/"
        local batch, length = {}, #base
        local function flush()
            if #batch == 0 then return end
            result.urls[#result.urls + 1] = base .. table.concat(batch, "+")
            result.counts[#result.counts + 1] = #batch
            batch, length = {}, #base
        end
        for _, name in ipairs(names) do
            local encoded = encode(name)
            if #base + #encoded > urlLimit then return nil, "A character identity exceeds the bulk URL limit." end
            if #batch >= playerLimit or length + (#batch > 0 and 1 or 0) + #encoded > urlLimit then flush() end
            length = length + (#batch > 0 and 1 or 0) + #encoded
            batch[#batch + 1] = encoded
            result.count = result.count + 1
        end
        flush()
    end
    return result
end
