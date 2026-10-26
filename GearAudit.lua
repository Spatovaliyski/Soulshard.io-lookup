local _, A = ...
local G = {}
A.GearAudit = G

-- Derived equipment checks for a nearby (live) inspection. Everything here is read from the item
-- links the client returned; nothing is a recommendation, and a value that cannot be read is
-- counted as unknown, never as a pass or a failure.

G.labels = {
    HEAD = "Head", NECK = "Neck", SHOULDER = "Shoulder", BACK = "Back", CHEST = "Chest", WRIST = "Wrist", HANDS = "Hands",
    WAIST = "Waist", LEGS = "Legs", FEET = "Feet", FINGER_1 = "Ring I", FINGER_2 = "Ring II", TRINKET_1 = "Trinket I",
    TRINKET_2 = "Trinket II", MAIN_HAND = "Main hand", OFF_HAND = "Off hand", RANGED = "Ranged", SHIRT = "Shirt", TABARD = "Tabard",
}

-- Same rules as the website's enchantEligibility. Rings need an enchanter, which a nearby
-- inspection cannot show, so they are never audited.
local armorSlots = { HEAD = true, SHOULDER = true, BACK = true, CHEST = true, WRIST = true, HANDS = true, LEGS = true, FEET = true }
local weaponSlots = { MAIN_HAND = true, OFF_HAND = true, RANGED = true }
local meleeSubclasses = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [20] = true }
local scopedSubclasses = { [2] = true, [3] = true, [18] = true }

local function itemClass(id)
    local lookup = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(lookup) ~= "function" then return nil end
    local ok, _, _, _, _, _, classId, subclassId = pcall(lookup, tonumber(id))
    if ok and type(classId) == "number" and type(subclassId) == "number" then return classId, subclassId end
end

-- true / false, or nil when the item type is needed and cannot be read.
function G.CanEnchant(slot, item)
    if armorSlots[slot] then return true end
    if not weaponSlots[slot] then return false end
    local classId, subclassId = itemClass(item.id)
    if not classId then return nil end
    if slot == "OFF_HAND" and classId == 4 then return subclassId == 6 end
    if classId ~= 2 then return false end
    if slot == "RANGED" then return scopedSubclasses[subclassId] == true end
    return meleeSubclasses[subclassId] == true
end

-- The colon-separated item string of a link as numbers: enchant first, then the four gem slots.
local function linkFields(link)
    local body = type(link) == "string" and link:match("item:([%-%d:]*)")
    if not body then return nil end
    local fields = {}
    for value in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = tonumber(value) or 0 end
    return { enchant = fields[2] or 0, gems = { fields[3] or 0, fields[4] or 0, fields[5] or 0, fields[6] or 0 } }
end

-- Sockets the base item has, from the client's item stats for the bare item id.
local function socketCount(item)
    local stats = GetItemStats or (C_Item and C_Item.GetItemStats)
    if type(stats) ~= "function" then return nil end
    local ok, result = pcall(stats, "item:" .. tostring(item.id))
    if not ok or type(result) ~= "table" then return nil end
    local total = 0
    for key, amount in pairs(result) do
        if type(key) == "string" and key:find("^EMPTY_SOCKET_") and type(amount) == "number" then total = total + amount end
    end
    return total
end

local function plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

-- Audit one equipment section. Only live sections carry item links; a saved profile reports
-- `recorded = false` so the UI can say the evidence was not preserved.
function G.Audit(section)
    local audit = { recorded = false, enchants = {}, sockets = {}, unknownEnchants = 0, unknownSockets = 0, marks = {}, checked = 0 }
    if not section or not section.data or section.source ~= "live" then return audit end
    audit.recorded = true
    for _, entry in ipairs(section.data.slots) do
        local item = entry.item
        if entry.state == "equipped" and item and not A.cosmeticSlots[entry.slot] then
            audit.checked = audit.checked + 1
            local fields = linkFields(item.link)
            local mark = {}
            local eligible = G.CanEnchant(entry.slot, item)
            if eligible and not fields then audit.unknownEnchants = audit.unknownEnchants + 1
            elseif eligible == nil then audit.unknownEnchants = audit.unknownEnchants + 1
            elseif eligible and fields.enchant == 0 then
                mark.enchant = true
                audit.enchants[#audit.enchants + 1] = entry.slot
            end
            local total = socketCount(item)
            if total == nil or not fields then
                if total ~= 0 then audit.unknownSockets = audit.unknownSockets + 1 end
            elseif total > 0 then
                local filled = 0
                for _, gem in ipairs(fields.gems) do if gem ~= 0 then filled = filled + 1 end end
                local empty = math.max(0, total - filled)
                if empty > 0 then
                    mark.sockets = empty
                    audit.sockets[#audit.sockets + 1] = { slot = entry.slot, count = empty }
                end
            end
            if mark.enchant or mark.sockets then audit.marks[entry.slot] = mark end
        end
    end
    return audit
end

-- Slot names in equipment order, with a count after a slot that has several empty sockets.
function G.SlotList(entries)
    local names = {}
    for _, entry in ipairs(entries) do
        local slot = type(entry) == "table" and entry.slot or entry
        local count = type(entry) == "table" and entry.count or 1
        names[#names + 1] = (G.labels[slot] or slot) .. (count > 1 and (" ×" .. count) or "")
    end
    return table.concat(names, ", ")
end

-- Finding rows for the Overview audit card and the Equipment centre panel.
-- kind: "warn" | "socket" | "ok" | "unknown".
function G.Findings(audit)
    local rows = {}
    if not audit.recorded then
        rows[1] = { kind = "unknown", head = "Enchants and gems not recorded", detail = "Saved profiles keep item names only", short = "Not recorded", shortDetail = "Saved: item names only" }
        return rows
    end
    local sockets = 0
    for _, entry in ipairs(audit.sockets) do sockets = sockets + entry.count end
    if #audit.enchants > 0 then rows[#rows + 1] = { kind = "warn", head = plural(#audit.enchants, "missing enchant"), detail = G.SlotList(audit.enchants) } end
    if sockets > 0 then rows[#rows + 1] = { kind = "socket", head = plural(sockets, "empty socket"), detail = G.SlotList(audit.sockets) } end
    if audit.unknownEnchants + audit.unknownSockets > 0 then
        rows[#rows + 1] = { kind = "unknown", head = plural(audit.unknownEnchants + audit.unknownSockets, "check") .. " unreadable", detail = "Item data was not available", shortDetail = "No item data" }
    end
    if #rows == 0 then rows[1] = { kind = "ok", head = "No missing enchants or empty sockets", detail = audit.checked .. " items checked", short = "No issues found" } end
    return rows
end

-- Evidence shown when a marker is hovered.
function G.MarkerTooltip(kind, slot, item)
    local lines = { title = kind == "enchant" and "Missing enchant" or "Empty socket" }
    lines.subject = (G.labels[slot] or slot) .. " · " .. tostring(item and item.name or "")
    lines.body = kind == "enchant" and "No enchantment is recorded on this item." or "A socket on this item holds no gem."
    lines.evidence = "Inspected item data"
    lines.rule = kind == "enchant" and ((G.labels[slot] or slot) .. " can be enchanted") or "Sockets counted from the item's base stats"
    return lines
end
