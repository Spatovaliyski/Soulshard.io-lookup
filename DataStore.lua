local _, A = ...

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
end

-- Pack requirements are strict X.Y.Z; the TOC version may carry a data-release suffix.
local function versionParts(value, allowSuffix)
    if type(value) ~= "string" then return nil end
    local major, minor, patch = value:match(allowSuffix and "^(%d+)%.(%d+)%.(%d+)" or "^(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

local function supportsVersion(required)
    local major, minor, patch = versionParts(required)
    local ownMajor, ownMinor, ownPatch = versionParts(A.version, true)
    if not major or not ownMajor then return false end
    if ownMajor ~= major then return ownMajor > major end
    if ownMinor ~= minor then return ownMinor > minor end
    return ownPatch >= patch
end

local function safeValues(value, depth, budget, seen, records)
    if value == records then return true end
    local kind = type(value)
    if kind == "string" then
        return #value <= 8192
    end
    if kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
    if kind == "boolean" then return true end
    if kind ~= "table" or depth > 24 or getmetatable(value) or seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        budget.entries = budget.entries + 1
        if budget.entries > 2000000 or not safeValues(key, depth + 1, budget, seen, records) or not safeValues(item, depth + 1, budget, seen, records) then return false end
    end
    seen[value] = nil
    return true
end

local function array(value, maximum)
    if type(value) ~= "table" or getmetatable(value) then return false end
    local count = 0
    for key in pairs(value) do
        if not integer(key, 1, maximum) then return false end
        count = count + 1
    end
    return count == #value and count <= maximum
end

local function alias(index, name, key)
    if index[name] == nil then index[name] = key
    elseif index[name] ~= key then index[name] = false end
end

local function validate(pack, interface)
    if type(pack) ~= "table" then return "No saved data installed. Install an exported Data folder and restart WoW." end
    local records = type(pack.charactersFragment) == "table" and pack.charactersFragment.entries or nil
    if not safeValues(pack, 0, { entries = 0 }, {}, records) then return "Corrupt pack: invalid values or structural limits exceeded." end
    if pack.dataFiles ~= nil then
        if not array(pack.dataFiles, 1000000) or type(A.dataChunks) ~= "table" then return "Missing data files. Replace the complete SoulshardLookup/Data folder." end
        local seen = {}
        for _, name in ipairs(pack.dataFiles) do
            if type(name) ~= "string" or seen[name] or A.dataChunks[name] ~= pack.datasetVersion then return "Mixed or missing data files. Replace the complete SoulshardLookup/Data folder." end
            seen[name] = true
        end
        for name in pairs(A.dataChunks) do if not seen[name] then return "Unexpected data file. Replace the complete SoulshardLookup/Data folder." end end
    end
    if pack.formatMajor ~= 1 or not integer(pack.formatMinor, 0, 1000000) then return "Unsupported data format. Install a compatible data pack." end
    if not supportsVersion(pack.minAddonVersion) then return "This pack needs a newer Soulshard Lookup addon." end
    if interface ~= A.interface or pack.clientInterface ~= A.interface then return "Unsupported client interface. Expected 20506." end
    if type(pack.datasetVersion) ~= "string" or type(pack.scope) ~= "table" or pack.scope.game ~= "classic-anni" or not array(pack.scope.regions, 2) or not array(pack.scope.realms, 5000) then return "Corrupt pack scope." end
    if not integer(pack.generatedAt, 0, time() + 300) or not integer(pack.sourceCutoffAt, 0, pack.generatedAt + 300) then return "Corrupt pack timestamp or local clock skew." end
    if type(pack.catalogVersions) ~= "table" then return "Corrupt catalog metadata." end
    local realmFragment, characterFragment = pack.realmsFragment, pack.charactersFragment
    if type(realmFragment) ~= "table" or type(characterFragment) ~= "table" or realmFragment.datasetVersion ~= pack.datasetVersion or characterFragment.datasetVersion ~= pack.datasetVersion then return "Mixed or missing data. Replace the entire SoulshardLookup/Data folder." end
    if not array(realmFragment.entries, 5000) or not array(characterFragment.entries, math.huge) then return "Corrupt pack record arrays." end
    if type(pack.coverage) ~= "table" or pack.coverage.exported ~= #characterFragment.entries or not integer(pack.coverage.eligible, 0, math.huge) or not integer(pack.coverage.excluded, 0, math.huge) or pack.coverage.eligible ~= pack.coverage.exported + pack.coverage.excluded then return "Corrupt coverage counts." end
    local realms, realmAliases, characters, nameAliases = {}, {}, {}, {}
    local scopeRegions, scopeRealms = {}, {}
    for _, region in ipairs(pack.scope.regions) do
        if (region ~= "eu" and region ~= "us") or scopeRegions[region] then return "Corrupt region scope." end
        scopeRegions[region] = true
    end
    for _, realm in ipairs(pack.scope.realms) do
        if type(realm.region) ~= "string" or type(realm.slug) ~= "string" then return "Corrupt realm scope." end
        local key = realm.region .. "/" .. realm.slug
        if scopeRealms[key] or not scopeRegions[realm.region] then return "Corrupt realm scope." end
        scopeRealms[key] = true
    end
    for _, realm in ipairs(realmFragment.entries) do
        if (realm.region ~= "eu" and realm.region ~= "us") or type(realm.slug) ~= "string" or type(realm.name) ~= "string" or not integer(realm.id, 1, 100000000) or not array(realm.aliases, 20) then return "Corrupt realm metadata." end
        local key = realm.region .. "/" .. realm.slug
        if realms[key] or not scopeRealms[key] then return "Duplicate or out-of-scope realm identity." end
        realms[key] = realm
        alias(realmAliases, key, key)
        for _, name in ipairs(realm.aliases) do
            if type(name) ~= "string" then return "Corrupt realm alias." end
            alias(realmAliases, realm.region .. "/" .. name, key)
        end
    end
    local realmCounts = {}
    local seenIdentities = {}
    local skipped = 0
    local unknownSections = {}
    for _, character in ipairs(characterFragment.entries) do
        if not safeValues(character, 0, { entries = 0 }, {}) then return "Corrupt character: invalid values or structural limits exceeded." end
        local identity, summary = character.identity, character.summary
        if not integer(character.snapshotMajor, 1, 1000000) or type(identity) ~= "table" or type(summary) ~= "table" or type(character.sections) ~= "table" then return "Corrupt character record." end
        if identity.game ~= "classic-anni" or type(identity.region) ~= "string" or type(identity.realmSlug) ~= "string" or type(identity.nameKey) ~= "string" or type(identity.name) ~= "string" or not array(identity.nameAliases, 10) or #identity.nameAliases == 0 or not integer(summary.level, 1, 70) or type(summary.classToken) ~= "string" or type(summary.race) ~= "string" or type(summary.faction) ~= "string" or (summary.guild ~= nil and type(summary.guild) ~= "string") then return "Corrupt character identity or summary." end
        local realmKey = identity.region .. "/" .. identity.realmSlug
        local realm = realms[realmKey]
        if not realm or realm.id ~= identity.realmId or realm.name ~= identity.realmName then return "Character realm metadata does not match pack." end
        local key = realmKey .. "/" .. identity.nameKey
        if seenIdentities[key] then return "Duplicate character identity." end
        seenIdentities[key] = true
        realmCounts[realmKey] = (realmCounts[realmKey] or 0) + 1
        if character.snapshotMajor == 1 then
            characters[key] = character
            for _, name in ipairs(identity.nameAliases) do
                if type(name) ~= "string" then return "Corrupt character alias." end
                alias(nameAliases, realmKey .. "/" .. name, key)
            end
            for id in pairs(character.sections) do
                if id ~= "equipment" and id ~= "talents" and id ~= "raids" then unknownSections[tostring(id)] = true end
            end
        else
            skipped = skipped + 1
        end
    end
    for key, realm in pairs(realms) do
        if realm.profiles ~= (realmCounts[key] or 0) then return "Corrupt realm coverage counts." end
    end
    for key in pairs(scopeRealms) do if not realms[key] then return "Missing scoped realm." end end
    A.data, A.realms, A.realmAliases, A.characters, A.nameAliases = pack, realms, realmAliases, characters, nameAliases
    A.skippedSnapshots = skipped
    A.unknownSections = {}
    for id in pairs(unknownSections) do table.insert(A.unknownSections, id) end
    table.sort(A.unknownSections)
end

-- Format 1 is the isolated legacy reader; format 2 is the packed reader.
-- Async format-2 loads return nil and call done(reason) once published or failed.
function A.LoadData(pack, interface, async, done)
    A.data, A.realms, A.realmAliases, A.characters, A.nameAliases = nil, {}, {}, {}, {}
    A.Packed.Clear()
    local reason
    if type(pack) == "table" and pack.formatMajor == 2 then
        reason = A.Packed.Load(pack, interface, async, done)
    else
        local ok
        ok, reason = pcall(validate, pack, interface)
        if not ok then reason = "Corrupt data pack. Replace the complete SoulshardLookup/Data folder." end
        if not reason then
            A.state = "Loaded dataset " .. pack.datasetVersion .. ": " .. (pack.coverage.exported - A.skippedSnapshots) .. " cached profiles, " .. #pack.realmsFragment.entries .. " realms; " .. A.skippedSnapshots .. " unsupported snapshots skipped."
            if #A.unknownSections > 0 then A.state = A.state .. " Ignored optional sections: " .. table.concat(A.unknownSections, ", ") end
        end
    end
    if A.ClearRows then A.ClearRows() end
    if A.profile then A.profile:Hide() end
    if reason == "pending" then return nil end
    if reason then
        A.data = nil
        A.state = reason
    end
    return reason == nil
end

A.IsArray = array
A.IsInteger = integer
A.AddAlias = alias
A.SupportsVersion = supportsVersion
