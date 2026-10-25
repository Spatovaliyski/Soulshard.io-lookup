local _, A = ...
local T = A.Theme
local G = A.GearAudit

-- Overview: the first profile tab. It summarises the other three and links into them. It is not an
-- entry in A.sections: it has no saved section of its own and reads the same three sections the
-- other tabs render.

local ART = "Interface\\AddOns\\SoulshardLookup\\Media\\Raids\\"
local LOGS = { 0.702, 0.659, 0.796 }
local chevronColor = { 0.804, 0.749, 0.604 }

-- Blizzard icon per specialization, mirroring the website's spec emblems.
local specIcons = {
    WARRIOR = { Arms = "ability_rogue_eviscerate", Fury = "ability_warrior_innerrage", Protection = "ability_warrior_defensivestance" },
    PALADIN = { Holy = "spell_holy_holybolt", Protection = "spell_holy_devotionaura", Retribution = "spell_holy_auraoflight" },
    HUNTER = { ["Beast Mastery"] = "ability_hunter_beasttaming", Marksmanship = "ability_marksmanship", Survival = "ability_hunter_swiftstrike" },
    ROGUE = { Assassination = "ability_rogue_eviscerate", Combat = "ability_backstab", Subtlety = "ability_stealth" },
    PRIEST = { Discipline = "spell_holy_wordfortitude", Holy = "spell_holy_holybolt", Shadow = "spell_shadow_shadowwordpain" },
    SHAMAN = { Elemental = "spell_nature_lightning", Enhancement = "spell_nature_lightningshield", Restoration = "spell_nature_magicimmunity" },
    MAGE = { Arcane = "spell_holy_magicalsentry", Fire = "spell_fire_firebolt02", Frost = "spell_frost_frostbolt02" },
    WARLOCK = { Affliction = "spell_shadow_deathcoil", Demonology = "spell_shadow_metamorphosis", Destruction = "spell_shadow_rainoffire" },
    DRUID = { Balance = "spell_nature_starfall", ["Feral Combat"] = "ability_racial_bearform", Restoration = "spell_nature_healingtouch" },
}

local shortNames = {
    ["Serpentshrine Cavern"] = "Serpentshrine", ["The Battle for Mount Hyjal"] = "Hyjal", ["Sunwell Plateau"] = "Sunwell",
}

local function value(number)
    return number and tostring(math.floor(number + 0.5)) or "—"
end

local function label(parent, size, color, x, y, text, serif, width)
    local text_ = T.Text(parent, size, color, serif)
    text_:SetPoint("TOPLEFT", x, -y)
    if width then text_:SetSize(width, size + 6); text_:SetMaxLines(1) end
    if text then text_:SetText(text) end
    return text_
end

local function line(parent, points, color, thickness, originX, originY)
    local made = {}
    for index = 1, #points - 1 do
        local segment = parent:CreateLine(nil, "OVERLAY")
        segment:SetThickness(thickness or 1.5)
        segment:SetColorTexture(color[1], color[2], color[3], 1)
        segment:SetStartPoint("TOPLEFT", (originX or 0) + points[index][1], -((originY or 0) + points[index][2]))
        segment:SetEndPoint("TOPLEFT", (originX or 0) + points[index + 1][1], -((originY or 0) + points[index + 1][2]))
        made[#made + 1] = segment
    end
    return made
end

-- 12-unit "bar chart" glyph that marks Warcraft Logs data.
local function chartGlyph(parent, x, y, color)
    T.Fill(parent, x + 0.7, y + 5, 1.6, 6, color, 1, "OVERLAY")
    T.Fill(parent, x + 4.2, y + 1.5, 1.6, 9.5, color, 1, "OVERLAY")
    T.Fill(parent, x + 7.7, y + 4.2, 1.6, 6.8, color, 1, "OVERLAY")
    T.Fill(parent, x + 0.7, y + 10.4, 10.6, 1.4, color, 1, "OVERLAY")
end

local chevronPoints = { { 0, 0 }, { 4.4, 4.3 }, { 0, 8.6 } }

local function chevron(parent, x, y, color)
    return line(parent, chevronPoints, color, 1.5, x, y)
end

-- Moves an existing chevron's two segments to a new origin.
local function placeChevron(segments, x, y)
    for index, segment in ipairs(segments) do
        segment:SetStartPoint("TOPLEFT", x + chevronPoints[index][1], -(y + chevronPoints[index][2]))
        segment:SetEndPoint("TOPLEFT", x + chevronPoints[index + 1][1], -(y + chevronPoints[index + 1][2]))
    end
end

local function dot(parent, x, y, size, color)
    return T.Disc(parent, "TOPLEFT", x, -y, size, color, 1, "ARTWORK")
end

local function qualityColor(item)
    local quality = item and (item.qualityCode or item.quality or "COMMON"):upper()
    return T.quality[quality] or T.cream
end

local function itemIcon(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(tonumber(item.id)) end
    if GetItemIcon then return GetItemIcon(tonumber(item.id)) end
end

-- ---------------------------------------------------------------------------------------------
-- A. Performance strip
-- ---------------------------------------------------------------------------------------------

local function raidSelector(strip, x, interactive, onClick)
    local button = CreateFrame("Button", nil, strip)
    button:SetPoint("TOPLEFT", x, -80)
    button:SetSize(210, 20)
    button.name = T.Text(button, 14, T.cream)
    button.name:SetPoint("LEFT")
    button.rule = T.Fill(button, 0, 17, 10, 1, T.dim, 0.8, "OVERLAY")
    button.arrow = line(button, { { 0, 0 }, { 3.5, 3.5 }, { 7, 0 } }, chevronColor, 1.4, 0, 8)
    button.tail = T.Text(button, 14, T.cream)
    button:SetScript("OnClick", onClick)
    function button:SetRaid(text, enabled)
        self.name:SetText(A.Text(text))
        local nameWidth = T.TextWidth(self.name)
        self.rule:SetSize(nameWidth, 1)
        for index, segment in ipairs(self.arrow) do
            segment:SetStartPoint("TOPLEFT", nameWidth + 7 + (index - 1) * 3.5, -(index == 1 and 8 or 11.5))
            segment:SetEndPoint("TOPLEFT", nameWidth + 7 + index * 3.5, -(index == 1 and 11.5 or 8))
            segment:SetShown(enabled)
        end
        self.rule:SetShown(enabled)
        self.tail:ClearAllPoints()
        self.tail:SetPoint("LEFT", self, "LEFT", nameWidth + (enabled and 22 or 4), 0)
        self.tail:SetText(T.Wrap(T.faint, "·") .. " DPS")
        self:EnableMouse(enabled)
    end
    return button
end

-- Strip: figures above a hairline, then a 32-unit source band whose text is centred in it.
local STRIP_HEIGHT = 136

local function buildStrip(body)
    local strip = T.Card(body, 750, STRIP_HEIGHT)
    strip:SetPoint("TOPLEFT")
    T.Fill(strip, 300, 12, 1, 120, T.hair, 0.09, "BORDER")
    T.Fill(strip, 525, 12, 1, 92, T.hair, 0.09, "BORDER")
    T.Fill(strip, 14, 104, 722, 1, T.hair, 0.09, "BORDER")
    label(strip, 15, T.muted, 26, 10, "GearScore")
    strip.gs = label(strip, 56, T.Hex("f1dfa6"), 25, 27, "—", true, 270)
    label(strip, 15, T.muted, 326, 10, "Average parse")
    strip.average = label(strip, 46, T.faint, 325, 35, "—", true, 190)
    label(strip, 15, T.muted, 551, 10, "Best parse")
    strip.best = label(strip, 46, T.faint, 550, 35, "—", true, 180)
    strip.averageRaid = raidSelector(strip, 326, true, function() body:ToggleRaidMenu("average") end)
    strip.bestRaid = raidSelector(strip, 551, true, function() body:ToggleRaidMenu("best") end)
    strip.equipmentDot = dot(strip, 26, 116, 8, T.good)
    strip.equipmentSource = label(strip, 13, T.goodText, 41, 112, "")
    chartGlyph(strip, 326, 115, LOGS)
    strip.logsSource = label(strip, 13, LOGS, 344, 112, "")
    return strip
end

local function updateStrip(strip, ctx, raid, index)
    local equipment, raids = ctx.equipment, ctx.raids
    local score = equipment.data and equipment.data.gearScore
    strip.gs:SetText(score and tostring(score.value) or "—")
    strip.gs:SetTextColor(unpack(score and T.Hex("f1dfa6") or T.faint))
    local average = raid and A.AverageRaidParse(raid)
    local best = raid and A.BestRaidParse(raid)
    strip.average:SetText(value(average))
    strip.average:SetTextColor(unpack(T.ParseColor(average)))
    strip.best:SetText(value(best))
    strip.best:SetTextColor(unpack(T.ParseColor(best)))
    local enabled = ctx.menuCount > 1
    strip.averageRaid:SetRaid(raid and raid.name or "No logged parses", raid ~= nil and enabled)
    strip.bestRaid:SetRaid(raid and raid.name or "No logged parses", raid ~= nil and enabled)
    local sep = " " .. T.Wrap(T.faint, "·") .. " "
    if equipment.source == "live" and equipment.data then
        strip.equipmentDot:SetColorTexture(T.good[1], T.good[2], T.good[3], 1)
        strip.equipmentSource:SetTextColor(unpack(T.goodText))
        strip.equipmentSource:SetText("Live equipment" .. sep .. T.Wrap(T.muted, "inspected " .. (equipment.fetchedAt and T.Ago(equipment.fetchedAt) or "just now")))
    elseif equipment.data then
        strip.equipmentDot:SetColorTexture(T.dim[1], T.dim[2], T.dim[3], 1)
        strip.equipmentSource:SetTextColor(unpack(T.muted))
        strip.equipmentSource:SetText("Saved equipment" .. (equipment.fetchedAt and (sep .. T.Ago(equipment.fetchedAt)) or ""))
    else
        strip.equipmentDot:SetColorTexture(T.faint[1], T.faint[2], T.faint[3], 1)
        strip.equipmentSource:SetTextColor(unpack(T.dim))
        strip.equipmentSource:SetText("Equipment unavailable")
    end
    if raids.data then
        strip.logsSource:SetTextColor(unpack(LOGS))
        strip.logsSource:SetText("Warcraft Logs" .. sep .. "historical" .. (raids.fetchedAt and (sep .. "saved " .. T.Ago(raids.fetchedAt)) or ""))
    else
        strip.logsSource:SetTextColor(unpack(T.dim))
        strip.logsSource:SetText("Warcraft Logs" .. sep .. "no saved parses")
    end
end

-- ---------------------------------------------------------------------------------------------
-- B. Equipment audit
-- ---------------------------------------------------------------------------------------------

local function tileTooltip(tile)
    local entry = tile.entry
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    if not entry or not entry.item then
        GameTooltip:SetText(G.labels[tile.slot] .. ": " .. (entry and entry.state == "empty" and "empty" or "not recorded"))
        GameTooltip:Show()
        return
    end
    GameTooltip:SetHyperlink(entry.item.link or "item:" .. entry.item.id)
    local mark = tile.mark
    if mark and (mark.enchant or mark.sockets) then
        GameTooltip:AddLine(" ")
        if mark.enchant then GameTooltip:AddLine("Missing enchant", 0.88, 0.64, 0.23) end
        if mark.sockets then GameTooltip:AddLine(mark.sockets == 1 and "Empty socket" or (mark.sockets .. " empty sockets"), 0.88, 0.64, 0.23) end
    end
    GameTooltip:Show()
end

-- The audit card is a 48-unit header band (title and button centred in it), one row per finding,
-- then the item tiles. Three findings use a tighter row pitch so the cards below keep their height.
local AUDIT_HEADER = 48

local function placeAuditRows(audit, pitch)
    for index, row in ipairs(audit.rows) do
        local y = AUDIT_HEADER + 10 + (index - 1) * pitch
        row.glyph:ClearAllPoints()
        row.glyph:SetPoint("TOPLEFT", 18, -(y + 4))
        row.head:ClearAllPoints()
        row.head:SetPoint("TOPLEFT", 50, -(y + 5))
        row.detail:ClearAllPoints()
        row.detail:SetPoint("TOPLEFT", 298, -(y + 5))
    end
end

local function buildAudit(body, open)
    local audit = T.Card(body, 750, 196)
    audit:SetPoint("TOPLEFT", 0, -(STRIP_HEIGHT + 12))
    label(audit, 18, T.goldBright, 18, 13, "Equipment Audit", true)
    audit.derived = T.Text(audit, 13, T.muted)
    audit.derived:SetJustifyH("RIGHT")
    -- Label, a 14-unit gap, then the arrow. The button is sized from the measured label so the gap
    -- holds with any font, and the "derived" note follows the button's left edge.
    local button = T.Button(audit, "Open Equipment", 128, 26, function() open("equipment") end, "tint", 14)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 14, 0)
    button:SetPoint("TOPRIGHT", -16, -11)
    button.arrow = chevron(button, 0, 8.5, T.Hex("ecd9a0"))
    function button:Fit()
        local arrowX = 14 + math.ceil(T.TextWidth(self.label)) + 14
        self:SetSize(arrowX + 5 + 14, 26)
        placeChevron(self.arrow, arrowX, 8.5)
    end
    button:Fit()
    audit.open = button
    audit.derived:SetPoint("RIGHT", button, "LEFT", -14, 0)
    T.Fill(audit, 18, AUDIT_HEADER, 714, 1, T.hair, 0.12, "BORDER")
    audit.rows = {}
    for index = 1, 3 do
        local row = {}
        row.glyph = T.StatusGlyph(audit, 20, T.surface)
        row.head = T.Text(audit, 16, T.bright)
        row.head:SetSize(246, 20)
        row.head:SetMaxLines(1)
        row.detail = T.Text(audit, 15, T.muted)
        row.detail:SetSize(430, 20)
        row.detail:SetMaxLines(1)
        audit.rows[index] = row
    end
    placeAuditRows(audit, 30)
    audit.tiles = {}
    local order = {}
    for _, slot in ipairs(A.slots) do if not A.cosmeticSlots[slot] then order[#order + 1] = slot end end
    for index, slot in ipairs(order) do
        local tile = CreateFrame("Button", nil, audit)
        tile.slot = slot
        tile.index = index
        tile:SetSize(30, 30)
        tile:SetPoint("TOPLEFT", 18 + (index - 1) * 36, -150)
        tile.border = T.Fill(tile, 0, 0, 30, 30, T.quality.EPIC, 1, "BACKGROUND")
        tile.inner = T.Fill(tile, 1, 1, 28, 28, { 0.04, 0.03, 0.06 }, 1, "BORDER")
        tile.icon = tile:CreateTexture(nil, "ARTWORK")
        tile.icon:SetPoint("TOPLEFT", 2, -2)
        tile.icon:SetSize(26, 26)
        tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        tile.enchant = T.StatusGlyph(tile, 14, T.surface)
        tile.enchant:SetPoint("TOPRIGHT", 5, 5)
        tile.enchant:SetKind("warn")
        tile.socket = T.StatusGlyph(tile, 14, T.surface)
        tile.socket:SetPoint("BOTTOMRIGHT", 5, -5)
        tile.socket:SetKind("socket")
        tile:SetScript("OnEnter", tileTooltip)
        tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
        audit.tiles[index] = tile
    end
    audit.recorded = T.Text(audit, 13, T.muted)
    audit.recorded:SetPoint("TOPRIGHT", -18, -153)
    audit.recorded:SetJustifyH("RIGHT")
    return audit
end

local function updateAudit(audit, ctx)
    local equipment = ctx.equipment
    local result = G.Audit(equipment)
    ctx.audit = result
    audit.open:Fit()
    audit.derived:SetText(result.recorded and "Derived from live items" or (equipment.data and "Saved profile" or "Equipment unavailable"))
    local findings
    if equipment.data then findings = G.Findings(result)
    else findings = { { kind = "unknown", head = "Equipment not available", detail = "Nothing to check yet" } } end
    -- The card is as tall as its findings: header, one row per finding, then the item tiles.
    local shown = math.max(1, math.min(#audit.rows, #findings))
    local pitch = shown >= 3 and 26 or 30
    placeAuditRows(audit, pitch)
    local tilesY = AUDIT_HEADER + 10 + shown * pitch + 8
    local height = tilesY + 44
    audit:SetHeight(height)
    for index, row in ipairs(audit.rows) do
        local finding = findings[index]
        row.glyph:SetShown(finding ~= nil)
        row.head:SetShown(finding ~= nil)
        row.detail:SetShown(finding ~= nil)
        if finding then
            row.glyph:SetKind(finding.kind)
            row.head:SetText(A.Text(finding.head))
            row.detail:SetText(A.Text(finding.detail))
        end
    end
    local bySlot, recorded, total = {}, 0, 0
    for _, entry in ipairs(equipment.data and equipment.data.slots or {}) do bySlot[entry.slot] = entry end
    for _, tile in ipairs(audit.tiles) do
        local entry = bySlot[tile.slot]
        total = total + 1
        if entry and entry.state ~= "unavailable" then recorded = recorded + 1 end
        tile.entry = entry
        tile.mark = result.marks[tile.slot]
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", 18 + (tile.index - 1) * 36, -tilesY)
        local item = entry and entry.item
        local color = item and qualityColor(item) or T.faint
        tile.border:SetColorTexture(color[1], color[2], color[3], item and 1 or 0.35)
        tile.icon:SetTexture(itemIcon(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
        tile.icon:SetShown(item ~= nil)
        tile.enchant:SetShown(tile.mark ~= nil and tile.mark.enchant == true)
        tile.socket:SetShown(tile.mark ~= nil and tile.mark.sockets ~= nil)
    end
    audit.recorded:ClearAllPoints()
    audit.recorded:SetPoint("TOPRIGHT", -18, -(tilesY + 3))
    audit.recorded:SetText(equipment.data and (recorded .. " of " .. total .. " recorded") or "")
    return height
end

-- ---------------------------------------------------------------------------------------------
-- C. Talents summary
-- ---------------------------------------------------------------------------------------------

-- A 42-unit header band holds the title and status; below it sit the spec identity and tree counts.
local TALENTS_BASE = 152

local function buildTalents(body, open)
    local card = CreateFrame("Button", nil, body, "BackdropTemplate")
    card:SetSize(300, TALENTS_BASE)
    card:SetPoint("TOPLEFT", 0, -356)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    card:SetBackdropColor(unpack(T.surface))
    card:SetScript("OnClick", function() open("talents") end)
    card:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(T.Blend(T.hair, T.surface, 0.05))) end)
    card:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(T.surface)) end)
    label(card, 17, T.goldBright, 16, 11, "Talents", true)
    card.statusText = T.Text(card, 13, T.goodText)
    card.statusText:SetPoint("TOPRIGHT", -30, -14)
    card.statusText:SetJustifyH("RIGHT")
    card.statusDot = T.Disc(card, "TOPRIGHT", -62, -17, 7, T.good, 1, "ARTWORK")
    chevron(card, 281, 17, chevronColor)
    T.Fill(card, 16, 42, 268, 1, T.hair, 0.12, "BORDER")
    -- Two groups move as the card grows: the spec identity and the tree counts.
    card.specGroup = CreateFrame("Frame", nil, card)
    card.specGroup:SetSize(300, 100)
    card.specGroup:SetPoint("TOPLEFT")
    card.treeGroup = CreateFrame("Frame", nil, card)
    card.treeGroup:SetSize(300, 100)
    card.treeGroup:SetPoint("TOPLEFT")
    local spec, trees = card.specGroup, card.treeGroup
    card.ring = T.Disc(spec, "TOPLEFT", 16, -48, 48, T.surface, 1, "BACKGROUND")
    card.icon = spec:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(42, 42)
    card.icon:SetPoint("TOPLEFT", 19, -51)
    T.Circle(spec, card.icon)
    card.name = label(spec, 22, T.bright, 76, 46, "", true, 216)
    card.detail = label(spec, 14, T.muted, 76, 74, "", false, 216)
    card.bars, card.counts, card.names = {}, {}, {}
    for index = 1, 3 do
        local x = 16 + (index - 1) * 91
        card.bars[index] = T.Fill(trees, x, 104, 86, 3, T.gold, 1, "ARTWORK")
        card.counts[index] = label(trees, 23, T.cream, x, 109, "", false, 86)
        card.names[index] = label(trees, 13, T.muted, x, 131, "", false, 86)
    end
    function card:SetLayout(top, height)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", 0, -top)
        self:SetSize(300, height)
        local extra = math.max(0, height - TALENTS_BASE)
        self.specGroup:ClearAllPoints()
        self.specGroup:SetPoint("TOPLEFT", 0, -math.floor(extra * 0.25))
        self.treeGroup:ClearAllPoints()
        self.treeGroup:SetPoint("TOPLEFT", 0, -math.floor(extra * 0.6))
    end
    return card
end

local function updateTalents(card, ctx)
    local talents, spec = ctx.talents, ctx.spec
    local live = talents.source == "live"
    card.statusDot:SetColorTexture(unpack(live and T.good or T.dim))
    card.statusText:SetTextColor(unpack(live and T.goodText or T.muted))
    card.statusText:SetText(talents.data and (live and "Live" or "Saved") or "Unavailable")
    card.statusDot:SetShown(talents.data ~= nil)
    card.statusDot:ClearAllPoints()
    card.statusDot:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(30 + T.TextWidth(card.statusText) + 7), -17)
    for index = 1, 3 do
        card.bars[index]:SetShown(spec ~= nil)
        card.counts[index]:SetShown(spec ~= nil)
        card.names[index]:SetShown(spec ~= nil)
    end
    if not spec then
        card.ring:SetColorTexture(T.surface[1], T.surface[2], T.surface[3], 1)
        card.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        card.icon:SetAlpha(0.35)
        card.name:SetText(talents.data and "No unique build" or "Unknown build")
        card.name:SetTextColor(unpack(T.muted))
        card.detail:SetText(talents.data and "An unknown build is never shown as empty" or "Talents were not recorded")
        return
    end
    local accent = T.SpecColor(spec.name)
    card.icon:SetAlpha(1)
    if spec.name then
        local icon = specIcons[ctx.character.summary.classToken]
        icon = icon and icon[spec.name]
        local catalogIcon = spec.trees[spec.treeIndex].nodes[1] and spec.trees[spec.treeIndex].nodes[1].icon
        card.icon:SetTexture("Interface\\Icons\\" .. (icon or catalogIcon or "INV_Misc_QuestionMark"))
        card.ring:SetColorTexture(unpack(T.Blend(accent, T.surface, 0.7)))
        card.name:SetText(A.Text(spec.name))
        card.name:SetTextColor(unpack(T.bright))
        card.detail:SetText("Detected from deepest tree " .. T.Wrap(T.faint, "·") .. " " .. spec.points .. " points")
    else
        card.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        card.icon:SetAlpha(0.35)
        card.ring:SetColorTexture(T.surface[1], T.surface[2], T.surface[3], 1)
        card.name:SetText("No talents spent")
        card.name:SetTextColor(unpack(T.muted))
        card.detail:SetText("The active build has no points")
    end
    for index = 1, 3 do
        local points = spec.counts[index] or 0
        local tree = spec.trees[index]
        local color = T.SpecColor(tree.name)
        card.bars[index]:SetColorTexture(color[1], color[2], color[3], points > 0 and 1 or 0.5)
        card.counts[index]:SetText(tostring(points))
        card.counts[index]:SetTextColor(unpack(index == spec.treeIndex and T.goldBright or points > 0 and T.Hex("ece0c2") or T.Hex("7d725c")))
        card.names[index]:SetText(A.Text(tree.name))
    end
end

-- ---------------------------------------------------------------------------------------------
-- D. Raid experience
-- ---------------------------------------------------------------------------------------------

local function buildRaid(body, open)
    local card = CreateFrame("Button", nil, body, "BackdropTemplate")
    card:SetSize(438, 148)
    card:SetPoint("TOPLEFT", 312, -356)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    card:SetBackdropColor(unpack(T.surface))
    card.art = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.art:SetPoint("TOPLEFT")
    card.art:SetSize(438, 70)
    card.art:SetTexCoord(0, 1, 0.21, 0.66)
    card.art:SetAlpha(0.85)
    card.shadeTop = T.Shade(card, 0, 0, 438, 35, 0.55, 0.15, T.surface)
    card.shadeBottom = T.Shade(card, 0, 35, 438, 35, 0.15, 0.96, T.surface)
    card.shift = 0
    card.phase = label(card, 13, T.goldBright, 16, 6, "")
    card.title = label(card, 25, T.bright, 16, 26, "", true, 300)
    card.logs = T.Text(card, 13, LOGS)
    card.logs:SetPoint("TOPRIGHT", -30, -14)
    card.logs:SetJustifyH("RIGHT")
    chevron(card, 421, 17, chevronColor)
    card.chart = CreateFrame("Frame", nil, card)
    card.chart:SetSize(12, 12)
    chartGlyph(card.chart, 0, 0, LOGS)
    card.progress = label(card, 16, T.cream, 16, 80, "", false, 406)
    card.segments = {}
    for index = 1, 10 do card.segments[index] = T.Fill(card, 16, 107, 20, 5, T.gold, 1, "ARTWORK") end
    card.also = label(card, 13, T.muted, 16, 122, "", false, 406)
    card.empty = label(card, 16, T.muted, 16, 84, "No logged raid kills for this character.", false, 406)
    card:SetScript("OnEnter", function(self) self.art:SetAlpha(1) end)
    card:SetScript("OnLeave", function(self) self.art:SetAlpha(0.85) end)
    -- A taller card shows more banner and moves the progress lines down with it.
    function card:SetLayout(top, height)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", 312, -top)
        self:SetSize(438, height)
        local shift = math.floor(math.max(0, height - 148) * 0.7)
        self.shift = shift
        local banner = 70 + shift
        local span = math.min(1, 0.45 * banner / 70)
        local first = math.max(0, math.min(1 - span, 0.435 - span / 2))
        self.art:SetSize(438, banner)
        self.art:SetTexCoord(0, 1, first, first + span)
        self.shadeTop:SetSize(438, banner / 2)
        self.shadeBottom:ClearAllPoints()
        self.shadeBottom:SetPoint("TOPLEFT", 0, -banner / 2)
        self.shadeBottom:SetSize(438, banner / 2)
        self.phase:ClearAllPoints()
        self.phase:SetPoint("TOPLEFT", 16, -(banner - 64))
        self.title:ClearAllPoints()
        self.title:SetPoint("TOPLEFT", 16, -(banner - 44))
        self.progress:ClearAllPoints()
        self.progress:SetPoint("TOPLEFT", 16, -(80 + shift))
        self.also:ClearAllPoints()
        self.also:SetPoint("TOPLEFT", 16, -(122 + shift))
        self.empty:ClearAllPoints()
        self.empty:SetPoint("TOPLEFT", 16, -(84 + shift))
    end
    return card
end

local function updateRaid(card, ctx, raid, index)
    card:SetScript("OnClick", function() ctx.open("raids", index) end)
    local sep = " " .. T.Wrap(T.faint, "·") .. " "
    card.art:SetShown(raid ~= nil)
    card.empty:SetShown(raid == nil)
    for _, widget in ipairs({ card.phase, card.title, card.logs, card.chart, card.progress, card.also }) do widget:SetShown(raid ~= nil) end
    if not raid then
        for _, segment in ipairs(card.segments) do segment:Hide() end
        card.empty:SetText(ctx.raids.data and "No logged raid kills for this character." or "Raid progression was not recorded.")
        return
    end
    card.art:SetTexture(ART .. raid.artwork .. ".tga")
    card.phase:SetText("Phase " .. raid.phase .. sep .. raid.size .. " players")
    card.title:SetText(A.Text(raid.name))
    card.logs:SetText("Logs" .. sep .. (ctx.raids.fetchedAt and ("saved " .. T.Ago(ctx.raids.fetchedAt)) or "saved"))
    card.chart:ClearAllPoints()
    card.chart:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(30 + T.TextWidth(card.logs) + 7), -16)
    local killed = raid.killed or 0
    local line_ = T.Wrap(killed == raid.total and T.goldBright or T.cream, tostring(killed)) .. " " .. T.Wrap(T.muted, "/ " .. raid.total .. " bosses defeated")
    if raid.runs then line_ = line_ .. sep .. T.Wrap(T.bright, tostring(raid.runs)) .. " " .. T.Wrap(T.muted, "logged runs") end
    card.progress:SetText(line_)
    local gap, span = 3, 406
    for segmentIndex, segment in ipairs(card.segments) do
        segment:SetShown(segmentIndex <= raid.total)
        if segmentIndex <= raid.total then
            local width = (span - gap * (raid.total - 1)) / raid.total
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", 16 + (segmentIndex - 1) * (width + gap), -(107 + card.shift))
            segment:SetSize(width, 5)
            local boss = raid.bosses[segmentIndex]
            local color = boss and boss.kills and boss.kills > 0 and T.Hex("d9ac4a") or T.Blend(T.hair, T.surface, 0.14)
            segment:SetColorTexture(color[1], color[2], color[3], 1)
        end
    end
    local others = {}
    for otherIndex, other in ipairs(ctx.raids.data.raids) do
        if otherIndex ~= index and (other.killed or 0) > 0 then
            others[#others + 1] = A.Text(shortNames[other.name] or other.name) .. " " .. other.killed .. "/" .. other.total
        end
    end
    local shown = {}
    for position = 1, math.min(3, #others) do shown[position] = others[position] end
    local extra = #others > 3 and (sep .. "+" .. (#others - 3) .. " more") or ""
    card.also:SetText(#others > 0 and ("Also logged: " .. table.concat(shown, sep) .. extra) or "")
end

-- ---------------------------------------------------------------------------------------------
-- Raid menu: which raid the performance strip and the raid card describe
-- ---------------------------------------------------------------------------------------------

-- The menu opens under the selector that was clicked: the average column's left edge, or flush with
-- the strip's right edge for the best-parse column so it never leaves the window.
local MENU_WIDTH = 224
local menuLeft = { average = 316, best = 750 - MENU_WIDTH }

local function buildMenu(body)
    local menu = T.Panel(body, MENU_WIDTH, 40, true)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetPoint("TOPLEFT", body, "TOPLEFT", menuLeft.average, -104)
    menu.catcher = CreateFrame("Button", nil, menu)
    menu.catcher:SetAllPoints(UIParent)
    menu.catcher:SetFrameLevel(menu:GetFrameLevel() - 1)
    menu.catcher:SetScript("OnClick", function() menu:Hide() end)
    menu.rows = {}
    for index = 1, #A.raidLibrary do
        local row = T.Button(menu, "", MENU_WIDTH - 12, 26, function() body:SelectOverviewRaid(index) end, "ghost", 14)
        row:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 28)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 10, 0)
        row.average = T.Text(row, 14, T.muted)
        row.average:SetPoint("RIGHT", -10, 0)
        row.average:SetJustifyH("RIGHT")
        menu.rows[index] = row
    end
    menu:Hide()
    return menu
end

-- The raid the strip describes by default: the latest raid with a logged average, else the latest with kills.
local function defaultRaid(raids)
    local fallback
    for index = #raids, 1, -1 do
        local raid = raids[index]
        if A.AverageRaidParse(raid) then return index end
        if not fallback and (raid.killed or 0) > 0 then fallback = index end
    end
    return fallback
end

function A.RenderOverview(body, ctx)
    if not body.built then
        body.built = true
        local function open(id, raidIndex) body.context.open(id, raidIndex) end
        body.strip = buildStrip(body)
        body.audit = buildAudit(body, open)
        body.talentsCard = buildTalents(body, open)
        body.raidCard = buildRaid(body, open)
        body.menu = buildMenu(body)
        body.rows = { body.strip, body.audit, body.talentsCard, body.raidCard }
        body.revealRows = { { body.strip }, { body.audit }, { body.talentsCard, body.raidCard } }
        body:HookScript("OnHide", function() body.menu:Hide() end)
        function body:ToggleRaidMenu(which)
            which = menuLeft[which] and which or "average"
            if self.menu:IsShown() and self.menu.opener == which then self.menu:Hide(); return end
            self.menu.opener = which
            self.menu:ClearAllPoints()
            self.menu:SetPoint("TOPLEFT", self, "TOPLEFT", menuLeft[which], -104)
            self.menu:Show()
        end
        function body:SelectOverviewRaid(index)
            self.raidIndex = index
            self.menu:Hide()
            self:Refresh()
        end
        function body:Refresh()
            local context = self.context
            local raids = context.raids.data and context.raids.data.raids or {}
            local index = self.raidIndex
            local raid = index and raids[index]
            updateStrip(self.strip, context, raid, index)
            updateRaid(self.raidCard, context, raid, index)
        end
    end
    body.context = ctx
    body.menu:Hide()
    local key = (ctx.character.identity.realmName or "") .. "/" .. (ctx.character.identity.name or "")
    local raids = ctx.raids.data and ctx.raids.data.raids or {}
    local choices = 0
    for _, raid in ipairs(raids) do if A.AverageRaidParse(raid) then choices = choices + 1 end end
    ctx.menuCount = choices
    if body.raidKey ~= key or not (body.raidIndex and raids[body.raidIndex]) then
        body.raidKey = key
        body.raidIndex = defaultRaid(raids)
    end
    local auditHeight = updateAudit(body.audit, ctx)
    -- The two lower cards take whatever height the audit leaves.
    local lowerTop = STRIP_HEIGHT + 12 + auditHeight + 12
    body.talentsCard:SetLayout(lowerTop, T.contentHeight - lowerTop)
    body.raidCard:SetLayout(lowerTop, T.contentHeight - lowerTop)
    updateTalents(body.talentsCard, ctx)
    for index, row in ipairs(body.menu.rows) do
        local raid = raids[index]
        local average = raid and A.AverageRaidParse(raid)
        row:SetShown(average ~= nil)
        if average then
            row.label:SetText(A.Text(raid.name))
            row.average:SetText(value(average))
            row.average:SetTextColor(unpack(T.ParseColor(average)))
        end
    end
    local shownRows = 0
    for index, row in ipairs(body.menu.rows) do
        if row:IsShown() then
            shownRows = shownRows + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, -6 - (shownRows - 1) * 28)
        end
    end
    body.menu:SetHeight(12 + math.max(1, shownRows) * 28 - 2)
    body:Refresh()
    return T.contentHeight
end
