local _, A = ...

local snapshots, queue, observations, dirty = {}, {}, {}, {}
local owner, cooldown, sequence, epoch = nil, -10, 0, 0
local sending, tickUnits, tickNearby, tickIndex = false, nil, nil, nil
local contextDepth = 0
local observedRequest = false
local FRESHNESS, RESPONSE_TIMEOUT, CACHE_LIMIT = 10, 5, 150

-- Inspect permission can disappear during combat; proximity still selects live data.
local function unitGuid(unit)
    if type(unit) ~= "string" or unit == "" then return end
    local ok, guid = pcall(function()
        if UnitExists and not UnitExists(unit) then return end
        if not UnitIsPlayer(unit) then return end
        return UnitGUID(unit)
    end)
    return ok and guid or nil
end

local function nearby(unit)
    if not unitGuid(unit) then return false end
    if UnitIsUnit(unit, "player") then return true end
    if CheckInteractDistance then
        local ok, close = pcall(CheckInteractDistance, unit, 1)
        return ok and close or false
    end
    return false
end

function A.DisplayRealm(realm)
    local compact = realm:gsub("%s+", "")
    local localRealm = GetRealmName()
    if compact == localRealm:gsub("%s+", "") then return localRealm end
    for key, definition in pairs(A.realms or {}) do
        if key:sub(1, 3) == (A.Region() or "") .. "/" and compact == definition.name:gsub("%s+", "") then return definition.name end
    end
    return realm
end

function A.PlayerName(unit)
    if not unitGuid(unit) then return end
    local name, realm = UnitFullName(unit)
    if type(name) ~= "string" or name == "" then return end
    return name, A.DisplayRealm(realm and realm ~= "" and realm or GetRealmName())
end

local function nativeUnit()
    return InspectFrame and InspectFrame:IsShown() and InspectFrame.unit
end

local function units()
    if tickUnits then return tickUnits end
    local result, seen = {}, {}
    local function add(unit)
        if unit and not seen[unit] and unitGuid(unit) then seen[unit] = true; result[#result + 1] = unit end
    end
    add("player"); add(nativeUnit()); add("target"); add("mouseover"); add("focus")
    for index = 1, 4 do add("party" .. index) end
    for index = 1, 40 do add("raid" .. index) end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and plates then
            for _, plate in ipairs(plates) do add(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) or plate.unitToken) end
        end
    end
    return result
end

local function identityRealm(identity)
    local definition = identity.realmKey and A.realms and A.realms[identity.realmKey]
    local realm = identity.realmName or (definition and definition.name)
    if not realm and identity.realmKey then realm = identity.realmKey:match("^[^/]+/(.+)$") end
    return realm and A.DisplayRealm(realm)
end

local function identityMatches(identity, unit)
    if not identity then return true end
    local name, realm = A.PlayerName(unit)
    if not name then return false end
    local resolved = A.ResolveName(name, realm)
    if resolved and resolved.key and identity.key then
        return resolved.key == identity.key and resolved.realmKey == identity.realmKey and
            (not identity.dataset or not resolved.dataset or resolved.dataset == identity.dataset)
    end
    local expectedRealm = identityRealm(identity)
    return name == identity.name and expectedRealm and A.DisplayRealm(expectedRealm) == realm and
        (not identity.region or identity.region == A.Region()) or false
end

function A.FindNearbyUnit(identity)
    if not identity then return end
    if tickIndex then
        local key = identity.key and ("id:" .. (identity.realmKey or "") .. "/" .. tostring(identity.key)) or
            ("name:" .. (identityRealm(identity) or "") .. "/" .. (identity.name or ""))
        local unit = tickIndex[key]
        return unit and identityMatches(identity, unit) and unit or nil
    end
    for _, unit in ipairs(units()) do if nearby(unit) and identityMatches(identity, unit) then return unit end end
end

local function guidUnit(guid, hint)
    if tickNearby then return tickNearby[guid] end
    if hint and unitGuid(hint) == guid and nearby(hint) then return hint end
    for _, unit in ipairs(units()) do if unitGuid(unit) == guid and nearby(unit) then return unit end end
end

local function changed(snapshot)
    if snapshot then dirty[snapshot.guid] = true end
end

local function flushChanges(refreshAll)
    if contextDepth > 0 or not A.RefreshPlayerViews then return end
    local updates = dirty
    dirty = {}
    if refreshAll then A.RefreshPlayerViews(nil)
    else for guid in pairs(updates) do A.RefreshPlayerViews(guid) end end
end

local function message(snapshot, value)
    if snapshot.message ~= value then snapshot.message = value; changed(snapshot) end
end

local function refreshLevel(snapshot, unit)
    local level = UnitLevel and UnitLevel(unit)
    if A.IsInteger(level, 1, 255) and snapshot.summary.level ~= level then
        snapshot.summary.level = level
        changed(snapshot)
    end
end

local function snapshotFor(unit)
    local guid = unitGuid(unit)
    if not guid then return end
    local snapshot = snapshots[guid]
    if not snapshot then
        local name, realm = A.PlayerName(unit)
        if not name then return end
        local _, class = UnitClass(unit)
        snapshot = { guid = guid, at = -10, sections = {}, generation = 0, realm = realm,
            identity = A.ResolveName(name, realm) or { name = name, realmName = realm, region = A.Region(), realmKey = (A.Region() or "") .. "/" .. realm },
            summary = { classToken = class or "", level = UnitLevel and math.max(0, UnitLevel(unit)) or 0,
                race = UnitRace and UnitRace(unit) or "", faction = UnitFactionGroup and UnitFactionGroup(unit) or "",
                guild = GetGuildInfo and GetGuildInfo(unit) or nil }, message = "Inspecting nearby player…" }
        snapshots[guid] = snapshot
        local count, oldest = 0, nil
        for key, value in pairs(snapshots) do
            count = count + 1
            local visible = A.profile and A.profile:IsShown() and A.profile.liveSnapshot and A.profile.liveSnapshot.guid == key
            if key ~= guid and not visible and (not owner or owner.guid ~= key) and (not oldest or value.usedAt < snapshots[oldest].usedAt) then oldest = key end
        end
        if count > CACHE_LIMIT and oldest then snapshots[oldest], queue[oldest], dirty[oldest] = nil, nil, nil end
    end
    snapshot.unit, snapshot.usedAt = unit, GetTime()
    refreshLevel(snapshot, unit)
    return snapshot
end

local inventorySlots = { HEAD = 1, NECK = 2, SHOULDER = 3, SHIRT = 4, CHEST = 5, WAIST = 6, LEGS = 7,
    FEET = 8, WRIST = 9, HANDS = 10, FINGER_1 = 11, FINGER_2 = 12, TRINKET_1 = 13, TRINKET_2 = 14,
    BACK = 15, MAIN_HAND = 16, OFF_HAND = 17, RANGED = 18, TABARD = 19 }
local qualities = { [0] = "POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY", "ARTIFACT", "HEIRLOOM" }

local function liveSection(data, partial)
    return { major = 1, state = partial and "partial" or "available", source = "live", fetchedAt = time(), data = data }
end

local function freezeInventory(unit)
    local links, missing, ids = {}, {}, {}
    for slot = 1, 19 do
        links[slot] = GetInventoryItemLink(unit, slot)
        if not links[slot] then
            local id = GetInventoryItemID and GetInventoryItemID(unit, slot) or nil
            id = tonumber(id)
            if (id and id > 0) or GetInventoryItemTexture(unit, slot) then
                missing[slot] = true
                ids[slot] = id and id > 0 and id or nil
            end
        end
    end
    return { links = links, missing = missing, ids = ids, requested = {} }
end

-- Same tacotip-0.5.1 formula as the website; inputs come from native item links.
local weights = { INVTYPE_RELIC = .3164, INVTYPE_TRINKET = .5625, INVTYPE_2HWEAPON = 2,
    INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 1, INVTYPE_RANGED = .3164,
    INVTYPE_THROWN = .3164, INVTYPE_RANGEDRIGHT = .3164, INVTYPE_SHIELD = 1,
    INVTYPE_WEAPON = 1, INVTYPE_HOLDABLE = 1, INVTYPE_HEAD = 1, INVTYPE_NECK = .5625,
    INVTYPE_SHOULDER = .75, INVTYPE_CHEST = 1, INVTYPE_ROBE = 1, INVTYPE_WAIST = .75,
    INVTYPE_LEGS = 1, INVTYPE_FEET = .75, INVTYPE_WRIST = .5625, INVTYPE_HAND = .75,
    INVTYPE_FINGER = .5625, INVTYPE_CLOAK = .5625 }
local scoringSlots = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function gearScore(links, missing, class)
    local items, count = {}, 0
    for _, slot in ipairs(scoringSlots) do
        local link = links[slot]
        if link then
            local _, _, rarity, level, _, _, _, _, equip = GetItemInfo(link)
            if not rarity or not level or not weights[equip] then return end
            items[slot] = { rarity = rarity, level = level, equip = equip }
            count = count + 1
        elseif missing[slot] then return end
    end
    if count == 0 then return end
    local paired = items[17] and ((items[16] and weights[items[16].equip] == 2) or weights[items[17].equip] == 2) and .5 or 1
    local total = 0
    for slot, item in pairs(items) do
        local rarity, level, scale = item.rarity, item.level, 1
        if rarity == 5 then rarity, scale = 4, 1.3
        elseif rarity == 0 or rarity == 1 then rarity, scale = 2, .005
        elseif rarity == 7 then rarity, level = 3, 187.05 end
        if rarity >= 2 and rarity <= 4 then
            local offset, divisor
            if level < 100 and rarity == 4 then offset, divisor = .25, 1.6275
            elseif (level < 168 and rarity == 4) or (level < 148 and rarity == 3) or (level < 138 and rarity == 2) or level <= 120 then
                offset = ({ [4] = 26, [3] = .75, [2] = 8 })[rarity]
                divisor = ({ [4] = 1.2, [3] = 1.8, [2] = 2 })[rarity]
            else
                offset = ({ [4] = 91.45, [3] = 81.375, [2] = 73 })[rarity]
                divisor = ({ [4] = .65, [3] = .8125, [2] = 1 })[rarity]
            end
            local weapon = slot == 16 or slot == 17
            local hunter = class == "HUNTER" and (weapon and .3164 or slot == 18 and 5.3224 or 1) or 1
            total = total + math.max(0, math.floor((level - offset) / divisor * weights[item.equip] * 1.8618 * scale)) * hunter * (weapon and paired or 1)
        end
    end
    return math.floor(total)
end


local function captureTalents(unit, snapshot)
    local catalog = A.catalogs[snapshot.summary.classToken]
    if not catalog or not GetNumTalents then return end
    local modern = C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo
    if not modern and not GetTalentInfo then return end
    local inspect = not UnitIsUnit(unit, "player")
    local active = C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup or GetActiveTalentGroup
    local group = active and active(inspect, false) or 1
    local trees, unmatched, partial, total = {}, {}, false, 0
    for treeIndex, definition in ipairs(catalog) do
        local count = GetNumTalents(treeIndex, inspect, false)
        if not A.IsInteger(count, 1, 40) then return end
        local tree = { treeKey = tostring(treeIndex), points = 0, allocations = {} }
        local seen = {}
        for talentIndex = 1, count do
            local name, row, column, rank, maximum
            if modern then
                local info = modern({ specializationIndex = treeIndex, talentIndex = talentIndex, isInspect = inspect,
                    isPet = false, groupIndex = group, target = unit })
                if info then name, row, column, rank, maximum = info.name, info.tier, info.column, info.rank, info.maxRank end
            else
                local icon
                name, icon, row, column, rank, maximum = GetTalentInfo(treeIndex, talentIndex, inspect, false, group)
            end
            if not name or not A.IsInteger(rank, 0, 5) or not A.IsInteger(row, 1, 9) or not A.IsInteger(column, 1, 4) then return end
            local node
            for _, candidate in ipairs(definition.nodes) do
                if candidate.row == row - 1 and candidate.column == column - 1 then node = candidate; break end
            end
            if not node or seen[node.nodeKey] or rank > node.maxRank or (maximum and maximum ~= node.maxRank) then
                partial = true
                if rank > 0 then table.insert(unmatched, { name = name, rank = rank, description = "Native talent could not be mapped to the catalog." }) end
            else
                seen[node.nodeKey] = true
                tree.points = tree.points + rank
                if rank > 0 then table.insert(tree.allocations, { nodeKey = node.nodeKey, rank = rank }) end
            end
            total = total + rank
        end
        for _, node in ipairs(definition.nodes) do if not seen[node.nodeKey] then partial = true end end
        trees[treeIndex] = tree
    end
    if total > math.max(0, snapshot.summary.level - 9) then return end
    return liveSection({ catalogVersion = A.catalogVersion, classToken = snapshot.summary.classToken,
        groups = { { active = true, trees = trees } }, unmatched = unmatched, warnings = {} }, partial)
end


function A.LiveGearScore(unit)
    local frozen = freezeInventory(unit)
    local _, class = UnitClass(unit)
    return gearScore(frozen.links, frozen.missing, class)
end

local function updateEquipment(snapshot, frozen)
    if snapshots[snapshot.guid] ~= snapshot or snapshot.inventory ~= frozen then return end
    local slots, partial = {}, false
    for index, slot in ipairs(A.slots) do
        local native, entry = inventorySlots[slot], { slot = slot, state = "empty" }
        local link = frozen.links[native]
        if link then
            local name, _, quality, level = GetItemInfo(link)
            local id = link:match("item:(%d+)")
            if name and id and quality and level then
                entry.state = "equipped"
                entry.item = { id = id, name = name, link = link, qualityCode = qualities[quality], itemLevel = level }
            else entry.state = "unavailable" end
        elseif frozen.missing[native] then entry.state = "unavailable" end
        if entry.state == "unavailable" then partial = true end
        slots[index] = entry
    end
    local score = gearScore(frozen.links, frozen.missing, snapshot.summary.classToken)
    local section = liveSection({ slots = slots, gearScore = score and { value = score, algorithm = "tacotip-0.5.1" } }, partial)
    -- Item metadata resolves against these captured links, never the shared inspect cache.
    local parts = { section.state, score or "-" }
    for _, entry in ipairs(slots) do parts[#parts + 1] = entry.item and (entry.item.link .. entry.item.name) or entry.state end
    local signature = table.concat(parts, ";")
    if signature ~= frozen.signature then
        frozen.signature = signature
        snapshot.sections.equipment = section
        changed(snapshot)
    end
    if snapshot.captured and section.state == "available" and snapshot.sections.talents and snapshot.sections.talents.state == "available" then
        snapshot.refreshing = false
        message(snapshot, nil)
    end
end

local function requestItems(snapshot, frozen)
    local generation = snapshot.generation
    local function ready()
        if snapshots[snapshot.guid] == snapshot and snapshot.generation == generation and snapshot.inventory == frozen then
            updateEquipment(snapshot, frozen)
            flushChanges()
        end
    end
    for slot = 1, 19 do
        local link = frozen.links[slot]
        local id = link and tonumber(link:match("item:(%d+)")) or frozen.ids[slot]
        local cached = link and GetItemInfo(link)
        if id and not cached and not frozen.requested[id] then
            frozen.requested[id] = true
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            if Item and Item.CreateFromItemLink and link then
                local ok, item = pcall(Item.CreateFromItemLink, Item, link)
                if ok and item and item.ContinueOnItemLoad then item:ContinueOnItemLoad(ready) end
            end
        end
    end
end

local function canRead(request)
    if not request or owner ~= request or request.epoch ~= epoch or not request.ready then return false end
    local unit = guidUnit(request.guid, request.unit)
    local native = nativeUnit()
    if not unit or (native and unitGuid(native) ~= request.guid) then return false end
    request.unit = unit
    return true
end

local function collect(request)
    if not request.self and not canRead(request) then return end
    local snapshot, unit = request.snapshot, request.unit
    if snapshots[snapshot.guid] ~= snapshot or unitGuid(unit) ~= snapshot.guid then return end
    refreshLevel(snapshot, unit)
    if not request.frozen then
        snapshot.generation = snapshot.generation + 1
        request.frozen = freezeInventory(unit)
        snapshot.inventory = request.frozen
        snapshot.at = GetTime()
        snapshot.captured = false
    else
        -- Missing native links may appear late. Only the current response owner may reread them.
        for slot in pairs(request.frozen.missing) do
            local link = GetInventoryItemLink(unit, slot)
            if link then request.frozen.links[slot], request.frozen.missing[slot] = link, nil end
        end
    end
    updateEquipment(snapshot, request.frozen)
    requestItems(snapshot, request.frozen)
    if not request.talentsReady then
        local ok, talents = pcall(captureTalents, unit, snapshot)
        if ok and talents then
            snapshot.sections.talents = talents
            request.talentsReady = true
            changed(snapshot)
        end
    end
    -- Item loads continue independently after inspection ownership moves on.
    request.complete = request.talentsReady and next(request.frozen.missing) == nil
    snapshot.captured = request.complete
    if request.complete and snapshot.sections.equipment.state == "available" and snapshot.sections.talents.state == "available" then
        snapshot.refreshing = false
        message(snapshot, nil)
    end
end

local function enqueue(snapshot, priority)
    if not snapshot then return end
    if owner and owner.guid == snapshot.guid and not owner.complete then
        owner.priority = math.min(owner.priority, priority)
        return
    end
    if (snapshot.captured and GetTime() - snapshot.at < FRESHNESS) or (snapshot.retryAt and GetTime() < snapshot.retryAt) then return end
    local request = queue[snapshot.guid]
    if not request then
        sequence = sequence + 1
        request = { snapshot = snapshot, guid = snapshot.guid, priority = priority, order = sequence }
        queue[snapshot.guid] = request
    elseif priority < request.priority then
        sequence = sequence + 1
        request.priority, request.order = priority, sequence
    end
    snapshot.refreshing = snapshot.sections.equipment ~= nil or snapshot.sections.talents ~= nil
    message(snapshot, InCombatLockdown() and "Live inspection paused during combat." or
        (snapshot.refreshing and "Refreshing nearby inspection…" or "Inspecting nearby player…"))
end

local function rememberObservation(identity, unit)
    if not identity then return end
    local key = (identity.realmKey or identity.realmName or identity.realmSlug or "") .. "/" .. (identity.name or "")
    observations[key] = { identity = identity, guid = unit and unitGuid(unit) or nil, usedAt = GetTime() }
    local count, oldest = 0, nil
    for candidate, value in pairs(observations) do
        count = count + 1
        if candidate ~= key and (not oldest or value.usedAt < observations[oldest].usedAt) then oldest = candidate end
    end
    if count > CACHE_LIMIT and oldest then observations[oldest] = nil end
end

local dispatch, installInspectHook
local function getPlayerContext(identity, unit, priority)
    if not (nearby(unit) and identityMatches(identity, unit)) then unit = identity and A.FindNearbyUnit(identity) or nil end
    rememberObservation(identity, unit)
    if not unit then return end
    local snapshot = snapshotFor(unit)
    if not snapshot then return end
    if not identity then rememberObservation(snapshot.identity, unit) end
    if priority then
        installInspectHook()
        if UnitIsUnit(unit, "player") then
            if GetTime() - snapshot.at >= FRESHNESS then collect({ self = true, snapshot = snapshot, guid = snapshot.guid, unit = unit }) end
        else enqueue(snapshot, priority); dispatch() end
    end
    return snapshot
end

function A.GetPlayerContext(identity, unit, priority)
    contextDepth = contextDepth + 1
    local snapshot = getPlayerContext(identity, unit, priority)
    contextDepth = contextDepth - 1
    return snapshot
end

function A.RequestPlayerInspection(unit, priority)
    return A.GetPlayerContext(nil, unit, priority or 1)
end

dispatch = function()
    if GetTime() < cooldown or InCombatLockdown() or nativeUnit() then return end
    local best
    for guid, request in pairs(queue) do
        local unit = guidUnit(guid, request.snapshot.unit)
        if not unit then queue[guid] = nil; changed(request.snapshot)
        elseif (not request.retryAt or GetTime() >= request.retryAt) and (not CanInspect or CanInspect(unit, false)) and
            (not UnitIsConnected or UnitIsConnected(unit)) then
            request.unit = unit
            if not best or request.priority < best.priority or
                (request.priority == best.priority and ((request.priority == 4 and request.order < best.order) or (request.priority ~= 4 and request.order > best.order))) then best = request end
        end
    end
    if not best then return end
    -- A foreground choice may replace a slow background response once the shared cooldown ends.
    if owner and not owner.complete and best.priority > owner.priority and GetTime() - owner.at < RESPONSE_TIMEOUT then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    if type(NotifyInspect) ~= "function" then return end
    queue[best.guid] = nil
    observedRequest = true
    epoch = epoch + 1
    owner = { snapshot = best.snapshot, guid = best.guid, unit = best.unit, priority = best.priority, at = GetTime(), epoch = epoch }
    cooldown = GetTime() + 2
    sending = true
    NotifyInspect(best.unit)
    sending = false
end

local inspectHooked = false
installInspectHook = function()
    if inspectHooked or type(NotifyInspect) ~= "function" or not hooksecurefunc then return end
    inspectHooked = true
    hooksecurefunc("NotifyInspect", function(unit)
        cooldown = GetTime() + 2
        observedRequest = true
        local guid = unitGuid(unit)
        if sending then return end
        local previous = owner
        epoch = epoch + 1
        owner = nil
        if previous and not previous.complete then
            message(previous.snapshot, "Another inspection interrupted this lookup. Waiting to retry…")
            if guidUnit(previous.guid, previous.unit) then enqueue(previous.snapshot, previous.priority) end
        end
        if guid and nearby(unit) then
            local snapshot = snapshotFor(unit)
            if snapshot then
                queue[guid] = nil
                owner = { snapshot = snapshot, guid = guid, unit = unit, at = GetTime(), epoch = epoch, priority = nativeUnit() and 1 or 3 }
            end
        end
    end)
end

local function observeReady(guid)
    if type(guid) ~= "string" then return end
    if owner and owner.guid ~= guid then return end
    local unit = guidUnit(guid, owner and owner.unit)
    if not unit then return end
    if not owner then
        -- Unknown competing requests and timed-out responses must not resurrect old ownership.
        if observedRequest then return end
        local snapshot = snapshotFor(unit)
        if not snapshot then return end
        observedRequest = true
        epoch = epoch + 1
        owner = { snapshot = snapshot, guid = guid, unit = unit, at = GetTime(), epoch = epoch, priority = nativeUnit() and 1 or 3 }
    end
    if GetTime() - owner.at > RESPONSE_TIMEOUT then return end
    owner.ready = true
    queue[guid] = nil
    collect(owner)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_ENABLED", "INSPECT_READY", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, value)
    installInspectHook()
    if event == "INSPECT_READY" then observeReady(value)
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        for _, snapshot in pairs(snapshots) do
            local frozen = snapshot.inventory
            if frozen and frozen.requested[tonumber(value)] then updateEquipment(snapshot, frozen) end
        end
        if owner and owner.ready then collect(owner) end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local guid = unitGuid(value)
        local snapshot = guid and snapshots[guid]
        if snapshot then
            if UnitIsUnit(value, "player") then collect({ self = true, snapshot = snapshot, guid = guid, unit = value })
            else
                local priority = owner and owner.guid == guid and owner.priority or 3
                if owner and owner.guid == guid then owner = nil; epoch = epoch + 1 end
                -- A gear change invalidates both the old score and all outstanding item callbacks.
                snapshot.generation = snapshot.generation + 1
                snapshot.inventory, snapshot.sections.equipment = nil, nil
                snapshot.at, snapshot.captured, snapshot.retryAt = -10, false, nil
                changed(snapshot)
                enqueue(snapshot, priority)
            end
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        local snapshot = nearby("player") and snapshotFor("player")
        if snapshot then collect({ self = true, snapshot = snapshot, guid = snapshot.guid, unit = "player" }) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        for _, snapshot in pairs(snapshots) do changed(snapshot) end
    end
    flushChanges()
end)

local elapsed, sourceElapsed, demandElapsed = 0, 0, 0
events:SetScript("OnUpdate", function(_, delta)
    elapsed, sourceElapsed, demandElapsed = elapsed + delta, sourceElapsed + delta, demandElapsed + delta
    if elapsed < .2 then return end
    elapsed = 0
    tickUnits = units()
    tickNearby, tickIndex = {}, {}
    for _, unit in ipairs(tickUnits) do
        if nearby(unit) then
            local guid = unitGuid(unit)
            if not tickNearby[guid] then tickNearby[guid] = unit end
            local name, realm = A.PlayerName(unit)
            if name then
                local nameKey = "name:" .. realm .. "/" .. name
                if not tickIndex[nameKey] then tickIndex[nameKey] = unit end
                local identity = A.ResolveName(name, realm)
                if identity and identity.key then
                    local idKey = "id:" .. identity.realmKey .. "/" .. tostring(identity.key)
                    if not tickIndex[idKey] then tickIndex[idKey] = unit end
                end
            end
        end
    end
    if owner then
        local unit = guidUnit(owner.guid, owner.unit)
        local timedOut = unit and not owner.complete and GetTime() - owner.at > RESPONSE_TIMEOUT
        if not unit or timedOut then
            changed(owner.snapshot)
            if not owner.complete then
                -- Target tokens are recycled; losing one is not an inspection failure.
                owner.snapshot.retryAt = timedOut and GetTime() + RESPONSE_TIMEOUT or nil
                owner.snapshot.refreshing = false
                message(owner.snapshot, timedOut and "Live inspection timed out. Retrying automatically…" or
                    "Live inspection interrupted. Waiting for this player…")
            end
            owner = nil
        elseif owner.ready and not owner.complete then collect(owner) end
    end
    -- Warm foreground units and group members before their tooltip/menu is opened.
    for _, unit in ipairs(units()) do
        local priority
        if unit == nativeUnit() then priority = 1
        elseif unit == "mouseover" then priority = 2
        elseif unit == "target" or unit == "focus" then priority = 3
        elseif unit:match("^party%d+$") or unit:match("^raid%d+$") then priority = 4 end
        if priority and nearby(unit) and not UnitIsUnit(unit, "player") then
            local snapshot = snapshotFor(unit)
            if snapshot and (priority ~= 4 or not snapshot.captured) then enqueue(snapshot, priority) end
        end
    end
    if A.profile and A.profile:IsShown() and A.profile.view == "profile" and A.profile.profileIdentity then
        local unit = A.FindNearbyUnit(A.profile.profileIdentity)
        if unit and not UnitIsUnit(unit, "player") then enqueue(snapshotFor(unit), 1) end
    end
    if demandElapsed >= 1 then
        demandElapsed = 0
        if A.RefreshLiveSearch then A.RefreshLiveSearch(nil, 4) end
        if A.RefreshLiveLfg then A.RefreshLiveLfg(nil, 4) end
    end
    if GameTooltip and GameTooltip.GetUnit and GameTooltip:IsShown() then
        local _, unit = GameTooltip:GetUnit()
        if nearby(unit) and not UnitIsUnit(unit, "player") then enqueue(snapshotFor(unit), 2) end
    end
    dispatch()
    local refreshAll = false
    if sourceElapsed >= .5 then
        sourceElapsed = 0
        for _, observation in pairs(observations) do
            local unit = A.FindNearbyUnit(observation.identity)
            local guid = unit and unitGuid(unit) or nil
            if guid ~= observation.guid then observation.guid = guid; refreshAll = true end
        end
    end
    flushChanges(refreshAll)
    tickUnits, tickNearby, tickIndex = nil, nil, nil
end)
installInspectHook()
