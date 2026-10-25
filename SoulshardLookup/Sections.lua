local _, A = ...

local slots = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER_1", "FINGER_2", "TRINKET_1", "TRINKET_2", "MAIN_HAND", "OFF_HAND", "RANGED", "SHIRT", "TABARD" }
A.slots = slots
A.cosmeticSlots = { SHIRT = true, TABARD = true }

function A.AverageRaidParse(raid)
    local total, count = 0, 0
    for _, boss in ipairs(raid.bosses) do
        if boss.bestParse ~= nil then
            total = total + boss.bestParse
            count = count + 1
        end
    end
    return count > 0 and total / count or nil
end

-- Highest single-boss best parse in a raid; the raid-level field covers saved data without boss rows.
function A.BestRaidParse(raid)
    local best = raid.bestParse
    for _, boss in ipairs(raid.bosses) do
        if boss.bestParse ~= nil and (best == nil or boss.bestParse > best) then best = boss.bestParse end
    end
    return best
end

-- Class name for display: the client's own localized name, else the token in title case.
function A.ClassName(token)
    local native = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[token]
    if type(native) == "string" then return native end
    return type(token) == "string" and token ~= "" and (token:sub(1, 1) .. token:sub(2):lower()) or "Unknown class"
end

-- The talent tree holding the most points in the unique active group, the way the website picks a
-- default specialization (the earliest tree wins a tie). Nil when the build is unknown or empty.
function A.DetectSpec(section, classToken)
    local data = section and section.data
    local catalog = A.catalogs and A.catalogs[classToken]
    if not data or not catalog then return nil end
    local group, active = nil, 0
    for _, candidate in ipairs(data.groups) do
        if candidate.active then group = candidate; active = active + 1 end
    end
    if active ~= 1 then return nil end
    local counts, best, bestPoints = {}, nil, 0
    for index, tree in ipairs(group.trees) do
        counts[index] = tree.points
        if tree.points > bestPoints then best, bestPoints = index, tree.points end
    end
    return { treeIndex = best, name = best and catalog[best].name, points = bestPoints, counts = counts, trees = catalog }
end

local function strings(values, maximum)
    if values == nil then return true end
    if not A.IsArray(values, maximum or 100) then return false end
    for _, value in ipairs(values) do if type(value) ~= "string" then return false end end
    return true
end

local function itemData(item)
    if type(item) ~= "table" or type(item.id) ~= "string" or type(item.name) ~= "string" then return false end
    if not item.id:match("^%d+$") or not A.IsInteger(tonumber(item.id), 1, 2147483647) then return false end
    if not strings(item.effects) or not strings(item.enchantments) or not strings(item.socketBonuses) or not strings(item.classRestrictions, 9) then return false end
    if not A.IsArray(item.gems or {}, 10) or not A.IsArray(item.sockets or {}, 10) then return false end
    for _, gem in ipairs(item.gems or {}) do
        if type(gem) ~= "table" or type(gem.id) ~= "string" or type(gem.name) ~= "string" or not strings(gem.effects) then return false end
    end
    for _, socket in ipairs(item.sockets or {}) do
        if type(socket) ~= "table" or type(socket.type) ~= "string" or (socket.gemId ~= nil and type(socket.gemId) ~= "string") then return false end
    end
    if item.weapon and (type(item.weapon) ~= "table" or type(item.weapon.damage) ~= "string") then return false end
    if item.set then
        if type(item.set) ~= "table" or type(item.set.name) ~= "string" or not A.IsArray(item.set.pieces, 30) or not A.IsArray(item.set.bonuses, 30) then return false end
        for _, piece in ipairs(item.set.pieces) do if type(piece.name) ~= "string" then return false end end
        for _, bonus in ipairs(item.set.bonuses) do if not A.IsInteger(bonus.requiredCount, 1, 30) or type(bonus.description) ~= "string" then return false end end
    end
    return true
end

local function equipment(data)
    if type(data) ~= "table" or not A.IsArray(data.slots, 19) or #data.slots ~= 19 then return false end
    if data.gearScore and (type(data.gearScore) ~= "table" or not A.IsInteger(data.gearScore.value, 0, 1000000) or data.gearScore.algorithm ~= "tacotip-0.5.1") then return false end
    for index, slot in ipairs(data.slots) do
        if slot.slot ~= slots[index] then return false end
        if slot.state == "equipped" then
            if not itemData(slot.item) then return false end
        elseif (slot.state ~= "empty" and slot.state ~= "unavailable") or slot.item then return false end
    end
    return true
end

local function talents(data, character)
    if type(data) ~= "table" or data.catalogVersion ~= A.catalogVersion or data.classToken ~= character.summary.classToken or not A.catalogs[data.classToken] then return false end
    if not A.IsArray(data.groups, 8) or not A.IsArray(data.unmatched, 240) or not strings(data.warnings, 20) then return false end
    for _, allocation in ipairs(data.unmatched) do
        if type(allocation) ~= "table" or type(allocation.name) ~= "string" or not A.IsInteger(allocation.rank, 1, 100) then return false end
    end
    for _, group in ipairs(data.groups) do
        if type(group.active) ~= "boolean" or not A.IsArray(group.trees, 3) or #group.trees ~= 3 then return false end
        for index, tree in ipairs(group.trees) do
            if tree.treeKey ~= tostring(index) or not A.IsInteger(tree.points, 0, 61) or not A.IsArray(tree.allocations, 40) then return false end
            local used, total = {}, 0
            for _, allocation in ipairs(tree.allocations) do
                local found
                for _, node in ipairs(A.catalogs[data.classToken][index].nodes) do
                    if node.nodeKey == allocation.nodeKey and A.IsInteger(allocation.rank, 1, node.maxRank) then found = node end
                end
                -- Format 2 allocations carry only nodeKey and rank; the catalog supplies the rest.
                if not found or used[allocation.nodeKey] or (allocation.name ~= nil and type(allocation.name) ~= "string") or (allocation.description ~= nil and type(allocation.description) ~= "string") or (allocation.castTime ~= nil and type(allocation.castTime) ~= "string") then return false end
                used[allocation.nodeKey] = true
                total = total + allocation.rank
            end
            if total ~= tree.points then return false end
        end
    end
    return true
end

local function raids(data)
    if type(data) ~= "table" or not A.IsArray(data.raids, 9) or #data.raids ~= #A.raidLibrary then return false end
    local function count(value) return value == nil or A.IsInteger(value, 0, 2147483647) end
    local function parse(value) return value == nil or (type(value) == "number" and value >= 0 and value <= 100) end
    for index, raid in ipairs(data.raids) do
        local definition = A.raidLibrary[index]
        if type(raid) ~= "table" or raid.id ~= definition.id or raid.name ~= definition.name or raid.artwork ~= definition.artwork or raid.total ~= definition.total or raid.size ~= definition.size or raid.phase ~= definition.phase then return false end
        if not count(raid.killed) or (raid.killed and raid.killed > raid.total) or not count(raid.runs) or not parse(raid.bestParse) or not A.IsArray(raid.bosses, 40) or #raid.bosses ~= raid.total then return false end
        for bossIndex, boss in ipairs(raid.bosses) do
            if type(boss) ~= "table" or boss.name ~= definition.bosses[bossIndex].name or not count(boss.kills) or not parse(boss.bestParse) or not parse(boss.medianParse) then return false end
        end
    end
    return true
end

A.sections = {
    { id = "equipment", label = "Equipment", major = 1, validate = equipment, render = function(...) return A.RenderEquipment(...) end },
    { id = "talents", label = "Talents", major = 1, validate = talents, render = function(...) return A.RenderTalents(...) end },
    { id = "raids", label = "Raids", major = 1, validate = raids, renderUnavailable = true, render = function(...) return A.RenderRaids(...) end },
}

local function validateSection(section, character, descriptor)
    if type(section) ~= "table" then return { state = "unavailable", reason = "not_saved" } end
    if section.major ~= descriptor.major then return { state = "unsupported", reason = "section_version" } end
    if section.state == "unavailable" then return { state = "unavailable", reason = section.reason or "not_saved" } end
    if section.state ~= "available" and section.state ~= "partial" then return { state = "unavailable", reason = "invalid_section" } end
    local ok, valid = pcall(descriptor.validate, section.data, character)
    if not A.IsInteger(section.fetchedAt, 0, time() + 300) or not ok or not valid then return { state = "unavailable", reason = "invalid_data_or_catalog" } end
    if descriptor.id == "equipment" then
        local state = "available"
        for _, slot in ipairs(section.data.slots) do
            if not A.cosmeticSlots[slot.slot] and slot.state == "unavailable" then state = "partial" end
        end
        local normalized = {}
        for key, value in pairs(section) do normalized[key] = value end
        normalized.state = state
        return normalized
    end
    return section
end

-- Full section for the profile viewer and raid tooltip. Packed profiles decode on demand; both
-- formats pass through the same validation and renderer-facing shape.
function A.GetSection(character, descriptor)
    if character.packed then return A.Packed.GetSection(character, descriptor, validateSection) end
    return validateSection(character.sections[descriptor.id], character, descriptor)
end

-- Header-only summary for search rows, tooltips and LFG annotations.
function A.GetSectionSummary(character, descriptor)
    if character.packed then return A.Packed.GetSectionSummary(character, descriptor) end
    return A.GetSection(character, descriptor)
end
