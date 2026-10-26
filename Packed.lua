local _, A = ...
-- Format-2 reader. Blocks stay Base64-encoded until a record is requested;
-- login builds only per-realm name indexes from character headers.
local C = A.Codec
local floor, sub, sort = math.floor, string.sub, table.sort
local P = {}
A.Packed = P

local profileFamilies = { "characters", "equipment", "talents", "raidlog" }
local familyNames = { characters = true, equipment = true, talents = true, raidlog = true, items = true }
-- Fixed WoW class IDs used by the saved-data format.
local classes = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID" }
local states = { [0] = "unavailable", [1] = "available", [2] = "partial" }
local reasons = { [1] = "not_saved", [2] = "invalid_timestamp" }
local sources = { equipment = "blizzard", talents = "blizzard", raids = "warcraftlogs" }
local detailFamilies = { equipment = "equipment", talents = "talents", raids = "raidlog" }
local cacheLimit, itemCacheLimit = 32, 256
local maxRecords, maxBytes, maxProfileBytes = 256, 192 * 1024, 128 * 1024
local lower = strlower or string.lower

P.cacheLimit = cacheLimit
P.stats = { headers = 0, details = 0, indexed = 0 }

A.diagnostics = {}
function A.Diagnose(message)
    local list = A.diagnostics
    if #list < 20 then list[#list + 1] = tostring(message):sub(1, 160) end
end

-- Cooperative work: synchronous loads never yield; login loads yield each frame.
local work = 0
local function step()
    work = work + 1
    if work < 256 or not P.yielding then return end
    work = 0
    if not debugprofilestop or debugprofilestop() - (P.frameStart or 0) > 8 then coroutine.yield() end
end

local function fail(message) error({ reason = message }, 0) end

local function validateBlock(block, realms, records)
    local family = block.kind
    if not familyNames[family] then fail("Unsupported data block family.") end
    if not A.IsInteger(block.count, 1, maxRecords) or not A.IsInteger(block.bytes, 0, maxBytes) or not A.IsInteger(block.first, 1, 4294967295) then fail("Corrupt data block bounds.") end
    if type(block.offsets) ~= "string" or type(block.payload) ~= "string" then fail("Corrupt data block strings.") end
    if #block.offsets ~= floor(((block.count + 1) * 4 + 2) / 3) * 4 or #block.payload ~= floor((block.bytes + 2) / 3) * 4 then fail("Corrupt data block framing.") end
    local last = block.first + block.count - 1
    if family == "items" then
        if block.realm ~= 0 or last > records.items then fail("Corrupt item block range.") end
    else
        local realm = realms[block.realm]
        if not realm or block.first < realm.firstProfileId or last >= realm.firstProfileId + realm.profiles then fail("Data block crosses a realm boundary.") end
    end
    local ok, raw = pcall(C.Base64, block.offsets)
    if not ok or #raw ~= (block.count + 1) * 4 then fail("Invalid Base64 offset table.") end
    local previous = C.Offset(raw, 0)
    if previous ~= 0 then fail("Invalid offset table.") end
    for index = 1, block.count do
        local offset = C.Offset(raw, index)
        if offset < previous or offset - previous > maxProfileBytes then fail("Invalid offset table.") end
        -- Only detail records of unavailable sections may be empty.
        if offset == previous and (family == "characters" or family == "items") then fail("Empty identity or item record.") end
        previous = offset
    end
    if previous ~= block.bytes then fail("Invalid offset table.") end
    -- Keep the compact decoded table; offsets stay registered so a reload revalidates.
    block.raw = raw
end

local function validateCoverage(list, total)
    sort(list, function(left, right) return left.first < right.first end)
    local nextId = 1
    for _, block in ipairs(list) do
        if block.first ~= nextId then fail("Missing or duplicate data blocks.") end
        nextId = block.first + block.count
    end
    if nextId ~= total + 1 then fail("Missing data blocks.") end
end

function P.Validate(pack, interface)
    if not A.IsInteger(pack.formatMinor, 0, 1000000) then fail("Unsupported data format. Install a compatible data pack.") end
    if not A.SupportsVersion(pack.minAddonVersion) then fail("This pack needs a newer Soulshard Lookup addon.") end
    if interface ~= A.interface or pack.clientInterface ~= A.interface then fail("Unsupported client interface. Expected 20506.") end
    local dataset = pack.datasetVersion
    if type(dataset) ~= "string" or not dataset:match("^[%w%-]+$") or #dataset > 80 or type(pack.scope) ~= "table" or pack.scope.game ~= "classic-anni" or not A.IsArray(pack.scope.regions, 2) or not A.IsArray(pack.scope.realms, 5000) then fail("Corrupt pack scope.") end
    if not A.IsInteger(pack.generatedAt, 0, time() + 300) or not A.IsInteger(pack.sourceCutoffAt, 0, pack.generatedAt + 300) then fail("Corrupt pack timestamp or local clock skew.") end
    if type(pack.catalogVersions) ~= "table" or type(pack.sections) ~= "table" or type(pack.records) ~= "table" then fail("Corrupt catalog metadata.") end
    local coverage, records = pack.coverage, pack.records
    if type(coverage) ~= "table" or not A.IsInteger(coverage.exported, 0, 4294967295) or not A.IsInteger(coverage.excluded, 0, 4294967295) or coverage.eligible ~= coverage.exported + coverage.excluded then fail("Corrupt coverage counts.") end
    if records.profiles ~= coverage.exported or not A.IsInteger(records.items, 0, 4294967295) then fail("Corrupt record counts.") end
    -- Incompatible catalogs or section versions disable one section, never the pack.
    local disabled = {
        equipment = pack.sections.equipment ~= 1 or pack.scoreAlgorithm ~= "tacotip-0.5.1",
        talents = pack.sections.talents ~= 1 or pack.catalogVersions.talents ~= A.catalogVersion,
        raids = pack.sections.raids ~= 1 or pack.catalogVersions.raids ~= A.raidCatalogVersion,
    }
    local scopeRegions, scopeRealms = {}, {}
    for _, region in ipairs(pack.scope.regions) do
        if (region ~= "eu" and region ~= "us") or scopeRegions[region] then fail("Corrupt region scope.") end
        scopeRegions[region] = true
    end
    for _, realm in ipairs(pack.scope.realms) do
        if type(realm) ~= "table" or type(realm.region) ~= "string" or type(realm.slug) ~= "string" then fail("Corrupt realm scope.") end
        local key = realm.region .. "/" .. realm.slug
        if scopeRealms[key] or not scopeRegions[realm.region] then fail("Corrupt realm scope.") end
        scopeRealms[key] = true
    end
    if not A.IsArray(pack.realms, 5000) then fail("Corrupt realm metadata.") end
    local realms, realmsByKey, realmAliases, nextId = {}, {}, {}, 1
    for ordinal, realm in ipairs(pack.realms) do
        if type(realm) ~= "table" or (realm.region ~= "eu" and realm.region ~= "us") or type(realm.slug) ~= "string" or type(realm.name) ~= "string" or not A.IsInteger(realm.id, 1, 100000000) or not A.IsArray(realm.aliases, 20) or not A.IsInteger(realm.profiles, 0, 4294967295) or realm.firstProfileId ~= nextId then fail("Corrupt realm metadata.") end
        local key = realm.region .. "/" .. realm.slug
        if realmsByKey[key] or not scopeRealms[key] then fail("Duplicate or out-of-scope realm identity.") end
        local entry = { region = realm.region, slug = realm.slug, name = realm.name, id = realm.id, profiles = realm.profiles, firstProfileId = realm.firstProfileId, ordinal = ordinal, key = key }
        realms[ordinal], realmsByKey[key] = entry, entry
        A.AddAlias(realmAliases, key, key)
        for _, alias in ipairs(realm.aliases) do
            if type(alias) ~= "string" then fail("Corrupt realm alias.") end
            A.AddAlias(realmAliases, realm.region .. "/" .. alias, key)
        end
        nextId = nextId + realm.profiles
    end
    if nextId ~= records.profiles + 1 then fail("Corrupt realm coverage counts.") end
    for key in pairs(scopeRealms) do if not realmsByKey[key] then fail("Missing scoped realm.") end end
    -- Every expected file must have loaded exactly once, from this dataset only.
    if not A.IsArray(pack.blockFiles, 100000) then fail("Missing data files. Replace the complete SoulshardLookup/Data folder.") end
    local expected, blockTotal = {}, 0
    for _, file in ipairs(pack.blockFiles) do
        if type(file) ~= "table" or type(file.name) ~= "string" or expected[file.name] or not A.IsInteger(file.blocks, 1, 100000) then fail("Corrupt data file list.") end
        expected[file.name] = file.blocks
        blockTotal = blockTotal + file.blocks
    end
    local loaded = {}
    for _, file in ipairs(A.packedFiles) do
        if file.dataset ~= dataset then fail("Mixed or missing data files. Replace the complete SoulshardLookup/Data folder.") end
        if not expected[file.name] then fail("Unexpected data file. Replace the complete SoulshardLookup/Data folder.") end
        if loaded[file.name] or file.blocks ~= expected[file.name] then fail("Duplicate or incomplete data file. Replace the complete SoulshardLookup/Data folder.") end
        loaded[file.name] = true
    end
    for name in pairs(expected) do if not loaded[name] then fail("Missing data files. Replace the complete SoulshardLookup/Data folder.") end end
    if #A.packedBlocks ~= blockTotal then fail("Missing or duplicate data blocks.") end
    local families = { characters = {}, equipment = {}, talents = {}, raidlog = {}, items = {} }
    for _, block in ipairs(A.packedBlocks) do
        if block.dataset ~= dataset then fail("Mixed or missing data files. Replace the complete SoulshardLookup/Data folder.") end
        validateBlock(block, realms, records)
        local list = families[block.kind]
        list[#list + 1] = block
    end
    for _, family in ipairs(profileFamilies) do validateCoverage(families[family], records.profiles) end
    validateCoverage(families.items, records.items)
    return { pack = pack, realms = realms, realmsByKey = realmsByKey, realmAliases = realmAliases, families = families, disabled = disabled, items = records.items }
end

-- Stable bottom-up merge sort of parallel arrays, yielding between bounded runs.
local function mergeSort(keys, ids)
    local count = #keys
    local sourceKeys, sourceIds, targetKeys, targetIds = keys, ids, {}, {}
    local width = 1
    while width < count do
        local first = 1
        while first <= count do
            local middle, finish = math.min(first + width, count + 1), math.min(first + width * 2, count + 1)
            local left, right = first, middle
            for target = first, finish - 1 do
                local takeRight = right < finish and (left >= middle or sourceKeys[right] < sourceKeys[left])
                if takeRight then
                    targetKeys[target], targetIds[target] = sourceKeys[right], sourceIds[right]
                    right = right + 1
                else
                    targetKeys[target], targetIds[target] = sourceKeys[left], sourceIds[left]
                    left = left + 1
                end
                step()
            end
            first = finish
        end
        sourceKeys, targetKeys = targetKeys, sourceKeys
        sourceIds, targetIds = targetIds, sourceIds
        width = width * 2
    end
    return sourceKeys, sourceIds
end

local function readIdentity(s, i, j)
    local name, nameKey, count
    name, i = C.Str(s, i, j)
    nameKey, i = C.Str(s, i, j)
    count, i = C.Uint(s, i, j)
    if name == "" or nameKey == "" or count > 9 then error("Invalid identity record.") end
    local aliases = { name }
    for index = 1, count do
        local alias
        alias, i = C.Str(s, i, j)
        if alias == "" then error("Invalid identity alias.") end
        aliases[index + 1] = alias
    end
    return name, nameKey, aliases, i
end

-- Search keys use the same runtime lowercase function as the legacy search.
function P.Index(prepared)
    local search = {}
    for ordinal, realm in ipairs(prepared.realms) do
        local keys, ids, seen = {}, {}, {}
        for _, block in ipairs(prepared.families.characters) do
            if block.realm == ordinal then
                local ok, payload = pcall(C.Base64, block.payload)
                if not ok or #payload ~= block.bytes then fail("Invalid Base64 character block.") end
                for index = 0, block.count - 1 do
                    local start, finish = C.Offset(block.raw, index), C.Offset(block.raw, index + 1)
                    local valid, _, nameKey, aliases = pcall(readIdentity, payload, start + 1, finish)
                    if not valid then fail("Corrupt character identity.") end
                    if seen[nameKey] then fail("Duplicate character identity.") end
                    seen[nameKey] = true
                    local id, used = block.first + index, {}
                    for _, alias in ipairs(aliases) do
                        local key = lower(alias)
                        if not used[key] then
                            used[key] = true
                            keys[#keys + 1], ids[#ids + 1] = key, id
                        end
                    end
                    step()
                end
            end
        end
        keys, ids = mergeSort(keys, ids)
        search[ordinal] = { keys = keys, ids = ids }
        P.stats.indexed = P.stats.indexed + #keys
    end
    prepared.search = search
    prepared.cache = { entries = {}, count = 0, clock = 0 }
    prepared.itemCache = { entries = {}, count = 0 }
    return prepared
end

function P.Publish(prepared)
    P.current = prepared
    A.data, A.realms, A.realmAliases, A.characters, A.nameAliases = prepared.pack, prepared.realmsByKey, prepared.realmAliases, {}, {}
    A.skippedSnapshots, A.unknownSections = 0, {}
    local notes = {}
    for _, id in ipairs({ "equipment", "talents", "raids" }) do
        if prepared.disabled[id] then notes[#notes + 1] = id end
    end
    A.state = "Loaded dataset " .. prepared.pack.datasetVersion .. ": " .. prepared.pack.coverage.exported .. " cached profiles, " .. #prepared.realms .. " realms."
    if #notes > 0 then A.state = A.state .. " Incompatible sections disabled: " .. table.concat(notes, ", ") end
end

function P.Clear()
    P.current, P.job = nil, nil
    A.diagnostics = {}
    A.loading = nil
    if P.loader then P.loader:SetScript("OnUpdate", nil) end
end

local function failure(result)
    if type(result) == "table" and result.reason then return result.reason end
    A.Diagnose(result)
    return "Corrupt data pack. Replace the complete SoulshardLookup/Data folder."
end

-- Returns the failure reason, or nil once published. Async loads return "pending"
-- and publish from a frame driver; nothing is visible until indexing completes.
function P.Load(pack, interface, async, done)
    P.Clear()
    local ok, prepared = pcall(P.Validate, pack, interface)
    if not ok then return failure(prepared) end
    if not async then
        P.yielding = false
        local indexed, result = pcall(P.Index, prepared)
        if not indexed then return failure(result) end
        P.Publish(result)
        return nil
    end
    P.yielding = true
    A.loading = true
    A.state = "Loading saved profiles..."
    local job = coroutine.create(P.Index)
    P.job = job
    P.loader = P.loader or CreateFrame("Frame")
    P.loader:SetScript("OnUpdate", function()
        if P.job ~= job then return end
        P.frameStart = debugprofilestop and debugprofilestop() or 0
        local resumed, result = coroutine.resume(job, prepared)
        if resumed and coroutine.status(job) ~= "dead" then return end
        P.loader:SetScript("OnUpdate", nil)
        P.job, A.loading, P.yielding = nil, nil, false
        if resumed then P.Publish(result) else A.state = failure(result) end
        if done then done(not resumed and A.state or nil) end
    end)
    return "pending"
end

local function findBlock(family, id)
    local list = P.current.families[family]
    local low, high = 1, #list
    while low <= high do
        local middle = floor((low + high) / 2)
        local block = list[middle]
        if id < block.first then high = middle - 1
        elseif id >= block.first + block.count then low = middle + 1
        else return block end
    end
end

local function record(family, id)
    local block = findBlock(family, id)
    if not block then error("Missing record.") end
    local index = id - block.first
    local start, finish = C.Offset(block.raw, index), C.Offset(block.raw, index + 1)
    return C.Range(block.payload, start, finish), block
end

local function sectionHeader(s, i, j)
    local code
    code, i = C.U8(s, i, j)
    local state = states[code]
    if not state then error("Invalid section state.") end
    if state == "unavailable" then
        local reason
        reason, i = C.U8(s, i, j)
        if not reasons[reason] then error("Invalid section reason.") end
        return { state = state, reason = reasons[reason] }, i
    end
    local fetchedAt
    fetchedAt, i = C.Uint(s, i, j)
    return { state = state, fetchedAt = fetchedAt }, i
end

local function decodeHeader(id)
    P.stats.headers = P.stats.headers + 1
    local s, block = record("characters", id)
    local j = #s
    local name, nameKey, aliases, i = readIdentity(s, 1, j)
    local realm = P.current.realms[block.realm]
    local code, level, race, faction, guild
    code, i = C.U8(s, i, j)
    level, i = C.U8(s, i, j)
    race, i = C.Str(s, i, j)
    faction, i = C.Str(s, i, j)
    guild, i = C.OptStr(s, i, j)
    if not classes[code] or level < 1 or level > 70 then error("Invalid character summary.") end
    local equipment, talents, raids
    equipment, i = sectionHeader(s, i, j)
    if equipment.state ~= "unavailable" then
        local score
        score, i = C.OptUint(s, i, j)
        if score then equipment.gearScore = { value = score, algorithm = "tacotip-0.5.1" }
        else
            local reason
            reason, i = C.U8(s, i, j)
            if reason ~= 1 then error("Invalid score reason.") end
            equipment.scoreReason = "not_calculated"
        end
    end
    talents, i = sectionHeader(s, i, j)
    if talents.state ~= "unavailable" then
        local count
        count, i = C.Uint(s, i, j)
        if count > 8 then error("Too many talent groups.") end
        talents.groups = {}
        for index = 1, count do
            local active, first, second, third
            active, i = C.Bool(s, i, j)
            first, i = C.Uint(s, i, j)
            second, i = C.Uint(s, i, j)
            third, i = C.Uint(s, i, j)
            if first > 61 or second > 61 or third > 61 then error("Invalid talent points.") end
            talents.groups[index] = { active = active, points = { first, second, third } }
        end
    end
    raids, i = sectionHeader(s, i, j)
    if raids.state ~= "unavailable" then
        local count
        count, i = C.Uint(s, i, j)
        if count > 40 then error("Too many raids.") end
        raids.raids = {}
        for index = 1, count do
            local killed, runs, best
            killed, i = C.OptUint(s, i, j)
            runs, i = C.OptUint(s, i, j)
            best, i = C.Percentile(s, i, j)
            raids.raids[index] = { killed = killed, runs = runs, bestParse = best }
        end
    end
    if i ~= j + 1 then error("Trailing character bytes.") end
    return {
        packed = true,
        profileId = id,
        dataset = P.current.pack.datasetVersion,
        sections = {},
        identity = { game = "classic-anni", region = realm.region, realmSlug = realm.slug, realmId = realm.id, realmName = realm.name, name = name, nameKey = nameKey, nameAliases = aliases },
        summary = { classToken = classes[code], level = level, race = race, faction = faction, guild = guild },
        summaries = { equipment = equipment, talents = talents, raids = raids },
    }
end

-- One bounded LRU cache holds headers and their validated sections.
local function remember(id, character)
    local cache = P.current.cache
    cache.clock = cache.clock + 1
    local entry = cache.entries[id]
    if entry and (not character or entry.character == character) then
        entry.used = cache.clock
        return entry
    end
    if not character then
        local ok, decoded = pcall(decodeHeader, id)
        if not ok then
            A.Diagnose("Profile " .. id .. ": " .. tostring(decoded))
            return nil
        end
        character = decoded
    end
    if not entry then cache.count = cache.count + 1 end
    entry = { character = character, sections = {}, used = cache.clock }
    cache.entries[id] = entry
    if cache.count > cacheLimit then
        local oldest, oldestId
        for key, candidate in pairs(cache.entries) do
            if key ~= id and (not oldest or candidate.used < oldest.used) then oldest, oldestId = candidate, key end
        end
        cache.entries[oldestId] = nil
        cache.count = cache.count - 1
    end
    return entry
end

function P.Character(id)
    if not P.current or not A.IsInteger(id, 1, P.current.pack.records.profiles) then return nil end
    local entry = remember(id)
    return entry and entry.character
end

function P.CacheSize() return P.current and P.current.cache.count or 0 end

local function current(character)
    return P.current and character.dataset == P.current.pack.datasetVersion and character.summaries
end

function P.Item(ordinal)
    local items = P.current.itemCache
    local item = items.entries[ordinal]
    if item then return item end
    if not A.IsInteger(ordinal, 1, P.current.items) then error("Invalid item reference.") end
    local s = record("items", ordinal)
    local j = #s
    local id, name, quality, i
    id, i = C.Uint(s, 1, j)
    name, i = C.Str(s, i, j)
    quality, i = C.Str(s, i, j)
    if id < 1 or id > 2147483647 or i ~= j + 1 then error("Invalid item record.") end
    if items.count >= itemCacheLimit then items.entries, items.count = {}, 0 end
    item = { id = tostring(id), name = name, qualityCode = quality }
    items.entries[ordinal], items.count = item, items.count + 1
    return item
end

local layouts = {}
local function layout(classToken)
    if layouts[classToken] then return layouts[classToken] end
    local nodes = {}
    for treeIndex, tree in ipairs(A.catalogs[classToken]) do
        local ordered = {}
        for _, node in ipairs(tree.nodes) do ordered[#ordered + 1] = node end
        sort(ordered, function(left, right)
            if left.row ~= right.row then return left.row < right.row end
            return left.column < right.column
        end)
        for _, node in ipairs(ordered) do nodes[#nodes + 1] = { tree = treeIndex, nodeKey = node.nodeKey, maxRank = node.maxRank } end
    end
    layouts[classToken] = nodes
    return nodes
end

local decoders = {}

function decoders.equipment(character, summary)
    local s = record("equipment", character.profileId)
    local i, j = 1, #s
    local slots = {}
    for index, slot in ipairs(A.slots) do
        local ref
        ref, i = C.Uint(s, i, j)
        if ref == 0 then slots[index] = { slot = slot, state = "unavailable" }
        elseif ref == 1 then slots[index] = { slot = slot, state = "empty" }
        else slots[index] = { slot = slot, state = "equipped", item = P.Item(ref - 1) } end
    end
    if i ~= j + 1 then error("Trailing equipment bytes.") end
    return { gearScore = summary.gearScore, scoreReason = summary.scoreReason, slots = slots }
end

function decoders.talents(character, summary)
    local classToken = character.summary.classToken
    local nodes = layout(classToken)
    local s = record("talents", character.profileId)
    local i, j = 1, #s
    if j == 0 then error("Missing talent detail.") end
    local groups = {}
    for groupIndex, saved in ipairs(summary.groups) do
        local ranks
        ranks, i = C.Ranks(s, i, j, #nodes)
        local trees = {}
        for treeIndex = 1, 3 do trees[treeIndex] = { treeKey = tostring(treeIndex), points = saved.points[treeIndex], allocations = {} } end
        for index, node in ipairs(nodes) do
            local rank = ranks[index]
            if rank > node.maxRank then error("Talent rank exceeds its maximum.") end
            if rank > 0 then
                local allocations = trees[node.tree].allocations
                allocations[#allocations + 1] = { nodeKey = node.nodeKey, rank = rank }
            end
        end
        groups[groupIndex] = { active = saved.active, trees = trees }
    end
    local count, unmatched, warnings = nil, {}, {}
    count, i = C.Uint(s, i, j)
    if count > 240 then error("Too many unmatched talents.") end
    for index = 1, count do
        local name, rank, description
        name, i = C.Str(s, i, j)
        rank, i = C.Uint(s, i, j)
        description, i = C.Str(s, i, j)
        if rank < 1 or rank > 100 then error("Invalid unmatched talent rank.") end
        unmatched[index] = { name = name, rank = rank, description = description }
    end
    count, i = C.Uint(s, i, j)
    if count > 20 then error("Too many talent warnings.") end
    for index = 1, count do warnings[index], i = C.Str(s, i, j) end
    if i ~= j + 1 then error("Trailing talent bytes.") end
    return { catalogVersion = A.catalogVersion, classToken = classToken, groups = groups, unmatched = unmatched, warnings = warnings }
end

function decoders.raids(character, summary)
    local library = A.raidLibrary
    if #summary.raids ~= #library then error("Raid count does not match the catalog.") end
    local s = record("raidlog", character.profileId)
    local i, j = 1, #s
    local raids = {}
    for index, definition in ipairs(library) do
        local saved = summary.raids[index]
        local bosses = {}
        for bossIndex, boss in ipairs(definition.bosses) do
            local mask, kills, best, median
            mask, i = C.U8(s, i, j)
            if mask > 7 then error("Invalid raid presence mask.") end
            if mask % 2 == 1 then kills, i = C.Uint(s, i, j) end
            if floor(mask / 2) % 2 == 1 then best, i = C.Parse(s, i, j) end
            if mask >= 4 then median, i = C.Parse(s, i, j) end
            bosses[bossIndex] = { name = boss.name, kills = kills, bestParse = best, medianParse = median }
        end
        raids[index] = { id = definition.id, name = definition.name, phase = definition.phase, size = definition.size, artwork = definition.artwork, total = definition.total, killed = saved.killed, runs = saved.runs, bestParse = saved.bestParse, bosses = bosses }
    end
    if i ~= j + 1 then error("Trailing raid bytes.") end
    return { raids = raids }
end

local unavailable = { state = "unavailable", reason = "invalid_data_or_catalog" }

-- Decodes one section on demand, then validates it with the shared renderer rules.
function P.GetSection(character, descriptor, validate)
    if not current(character) then return { state = "unavailable", reason = "dataset_replaced" } end
    local summary = character.summaries[descriptor.id]
    if summary.state == "unavailable" then return { state = "unavailable", reason = summary.reason } end
    if P.current.disabled[descriptor.id] then return { state = "unsupported", reason = "section_catalog" } end
    local entry = remember(character.profileId, character)
    local cached = entry.sections[descriptor.id]
    if cached then return cached end
    P.stats.details = P.stats.details + 1
    local ok, data = pcall(decoders[descriptor.id], character, summary)
    local section
    if ok then
        section = validate({ major = 1, state = summary.state, fetchedAt = summary.fetchedAt, source = sources[descriptor.id], data = data }, character, descriptor)
    else
        A.Diagnose("Profile " .. character.profileId .. " " .. descriptor.id .. ": " .. tostring(data))
        section = unavailable
    end
    entry.sections[descriptor.id] = section
    return section
end

-- Header-only view for search rows, tooltips and LFG annotations.
function P.GetSectionSummary(character, descriptor)
    if not current(character) then return { state = "unavailable", reason = "dataset_replaced" } end
    local summary = character.summaries[descriptor.id]
    if summary.state == "unavailable" then return { state = "unavailable", reason = summary.reason } end
    if P.current.disabled[descriptor.id] then return { state = "unsupported", reason = "section_catalog" } end
    if not A.IsInteger(summary.fetchedAt, 0, time() + 300) then return unavailable end
    local data
    if descriptor.id == "equipment" then data = { gearScore = summary.gearScore }
    elseif descriptor.id == "talents" then
        data = { groups = {} }
        for index, group in ipairs(summary.groups) do
            data.groups[index] = { active = group.active, trees = { { points = group.points[1] }, { points = group.points[2] }, { points = group.points[3] } } }
        end
    else
        if #summary.raids ~= #A.raidLibrary then return unavailable end
        data = { raids = {} }
        for index, raid in ipairs(summary.raids) do
            local definition = A.raidLibrary[index]
            if raid.killed and raid.killed > definition.total then return unavailable end
            data.raids[index] = { id = definition.id, name = definition.name, total = definition.total, killed = raid.killed, runs = raid.runs, bestParse = raid.bestParse }
        end
    end
    return { major = 1, state = summary.state, fetchedAt = summary.fetchedAt, source = sources[descriptor.id], data = data }
end

local function lowerBound(keys, value)
    local low, high = 1, #keys + 1
    while low < high do
        local middle = floor((low + high) / 2)
        if keys[middle] < value then low = middle + 1 else high = middle end
    end
    return low
end

-- Returns up to limit unique profile IDs in canonical name order and the total.
-- Profile IDs follow the exporter's byte-ordered nameKey, so lower IDs sort first.
function P.Search(ordinal, prefix, limit)
    local index = P.current.search[ordinal]
    local keys, ids = index.keys, index.ids
    local seen, best, total = {}, {}, 0
    for position = lowerBound(keys, prefix), #keys do
        if sub(keys[position], 1, #prefix) ~= prefix then break end
        local id = ids[position]
        if not seen[id] then
            seen[id] = true
            total = total + 1
            if #best < limit or id < best[#best] then
                local at = #best + 1
                while at > 1 and best[at - 1] > id do
                    best[at] = best[at - 1]
                    at = at - 1
                end
                best[at] = id
                best[limit + 1] = nil
            end
        end
    end
    return best, total
end

-- Exact alias lookup: lowercase candidates, then the exact saved alias. An alias
-- shared by different profiles stays unresolved (false), like the legacy reader.
function P.Resolve(ordinal, name)
    local index = P.current.search[ordinal]
    local keys, ids = index.keys, index.ids
    local key = lower(name)
    local found
    for position = lowerBound(keys, key), #keys do
        if keys[position] ~= key then break end
        local character = P.Character(ids[position])
        if character then
            for _, alias in ipairs(character.identity.nameAliases) do
                if alias == name then
                    if found and found ~= character.profileId then return false end
                    found = character.profileId
                end
            end
        end
    end
    return found
end
