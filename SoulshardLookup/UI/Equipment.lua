local _, A = ...

local columnWidth, centreWidth = 246, 220

local function itemTooltip(button)
    local slot = button.slot
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if not slot.item then
        GameTooltip:SetText(slot.state == "empty" and "Empty slot" or "Equipment unavailable")
        GameTooltip:Show()
        return
    end
    local item = slot.item
    GameTooltip:SetHyperlink(item.link or "item:" .. item.id)
    GameTooltip:AddLine(" ")
    if button.section.source ~= "live" then GameTooltip:AddLine("Base item from the game. Saved enchants, gems and set progress are not represented.", 0.5, 0.5, 0.5, true) end
    GameTooltip:AddLine((button.section.source == "live" and "Nearby inspection · " or "Saved profile · ") .. A.SectionLabel(button.section), 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

-- Evidence for one audit marker, shown on the native tooltip.
local function markerTooltip(glyph)
    local lines = A.GearAudit.MarkerTooltip(glyph.markerKind, glyph.markerSlot, glyph.markerItem)
    GameTooltip:SetOwner(glyph, "ANCHOR_RIGHT")
    GameTooltip:SetText(lines.title, 1, 0.85, 0.4)
    GameTooltip:AddLine(A.Text(lines.subject), 1, 1, 1, true)
    GameTooltip:AddLine(lines.body, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Evidence", lines.evidence, 1, 0.82, 0, 0.9, 0.9, 0.9)
    GameTooltip:AddDoubleLine("Rule", lines.rule, 1, 0.82, 0, 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Derived audit · Live inspection · Read only", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local leftSlots = { HEAD = 1, NECK = 2, SHOULDER = 3, BACK = 4, CHEST = 5, SHIRT = 6, TABARD = 7, WRIST = 8 }
local rightSlots = { HANDS = 1, WAIST = 2, LEGS = 3, FEET = 4, FINGER_1 = 5, FINGER_2 = 6, TRINKET_1 = 7, TRINKET_2 = 8 }
local weapons = { MAIN_HAND = 1, OFF_HAND = 2, RANGED = 3 }
local weaponX = { 0, 264, 502 }
local weaponWidth = { columnWidth, centreWidth, columnWidth }

local function createRow(parent, T)
    local row = CreateFrame("Button", nil, parent)
    row.hover = T.Fill(row, 0, 0, columnWidth, 54, T.hair, 0.065, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.rule = T.Fill(row, 6, 53, columnWidth - 12, 1, T.hair, 0.07, "BORDER")
    row.border = T.Fill(row, 4, 7, 40, 40, T.quality.EPIC, 1, "BORDER")
    row.well = T.Fill(row, 5, 8, 38, 38, { 0.04, 0.03, 0.06 }, 1, "ARTWORK")
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon:SetPoint("TOPLEFT", 7, -10)
    row.icon:SetSize(32, 32)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.label = T.Text(row, 13, T.muted)
    row.label:SetPoint("TOPLEFT", 54, -9)
    row.text = T.Text(row, 15, T.cream)
    row.text:SetPoint("TOPLEFT", 54, -27)
    row.text:SetMaxLines(1)
    row.marks = {}
    for index, kind in ipairs({ "enchant", "socket" }) do
        local glyph = T.StatusGlyph(row, 16, T.background)
        glyph:SetKind(kind == "enchant" and "warn" or "socket")
        glyph.markerKind = kind
        glyph:EnableMouse(true)
        glyph:SetScript("OnEnter", markerTooltip)
        glyph:SetScript("OnLeave", function() GameTooltip:Hide() end)
        glyph:Hide()
        row.marks[index] = glyph
    end
    row:SetScript("OnEnter", function(self) self.hover:Show(); itemTooltip(self) end)
    row:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    row:HookScript("OnHide", function(self) self.hover:Hide() end)
    return row
end

local function createSummary(parent, T)
    local panel = T.Card(parent, centreWidth, 432)
    panel:SetPoint("TOPLEFT", 264, 0)
    local function text(size, color, x, y, serif, width)
        local fontString = T.Text(panel, size, color, serif)
        fontString:SetPoint("TOPLEFT", x, -y)
        if width then fontString:SetSize(width, size + 6); fontString:SetMaxLines(1) end
        return fontString
    end
    local heading = text(18, T.goldBright, 18, 12, true)
    heading:SetText("Gear check")
    T.Hair(panel, 18, 46, 184, 0.14)
    text(14, T.muted, 18, 58):SetText("GearScore")
    panel.score = text(40, T.bright, 17, 78, true, 190)
    panel.dot = T.Disc(panel, "TOPLEFT", 18, -130, 7, T.good, 1, "ARTWORK")
    panel.source = text(13, T.goodText, 32, 126, false, 170)
    T.Hair(panel, 18, 154, 184, 0.14)
    panel.spec = text(16, T.Hex("ece0c2"), 18, 166, false, 184)
    panel.coverage = text(14, T.muted, 18, 188, false, 184)
    panel.derived = text(13, T.muted, 18, 222, false, 184)
    panel.findings = {}
    for index = 1, 3 do
        local y = 250 + (index - 1) * 48
        local finding = {}
        finding.glyph = T.StatusGlyph(panel, 20, T.surface)
        finding.glyph:SetPoint("TOPLEFT", 18, -(y + 1))
        finding.head = text(15, T.bright, 48, y, false, 160)
        finding.detail = text(13, T.muted, 48, y + 20, false, 160)
        panel.findings[index] = finding
    end
    panel.hint = text(13, T.dim, 18, 404, false, 184)
    return panel
end

function A.RenderEquipment(parent, section, character, context)
    local T = A.Theme
    local G = A.GearAudit
    parent.rows = parent.rows or {}
    parent.revealRows = {}
    for _, row in ipairs(parent.rows) do row:Hide() end
    if parent.summary then parent.summary:Hide() end
    if not section.data then return T.contentHeight end
    if not parent.summary then parent.summary = createSummary(parent, T) end
    local summary = parent.summary
    local live = section.source == "live"
    local audit = G.Audit(section)
    local score = section.data.gearScore
    summary.score:SetText(score and tostring(score.value) or "—")
    summary.score:SetTextColor(unpack(score and T.bright or T.faint))
    summary.dot:SetColorTexture(unpack(live and T.good or T.dim))
    summary.source:SetTextColor(unpack(live and T.goodText or T.muted))
    local sep = " " .. T.Wrap(T.faint, "·") .. " "
    summary.source:SetText((live and "Live" or "Saved") .. (section.fetchedAt and (sep .. (live and "inspected " or "") .. T.Ago(section.fetchedAt)) or ""))
    local className = A.ClassName(character.summary.classToken)
    local spec = context and context.spec
    summary.spec:SetText(A.Text((spec and spec.name and (spec.name .. " ") or "") .. className))
    summary.derived:SetText(live and "Derived from live items" or "Saved profile")
    local recorded, total = 0, 0
    for index, slot in ipairs(section.data.slots) do
        local row = parent.rows[index]
        local weapon = weapons[slot.slot]
        local width = weapon and weaponWidth[weapon] or columnWidth
        if not A.cosmeticSlots[slot.slot] then
            total = total + 1
            if slot.state ~= "unavailable" then recorded = recorded + 1 end
        end
        if not row then
            row = createRow(parent, T)
            parent.rows[index] = row
        end
        row:SetSize(width, 54)
        row.text:SetSize(width - 60, 20)
        row.label:SetText(G.labels[slot.slot] or slot.slot)
        row:ClearAllPoints()
        if weapon then row:SetPoint("TOPLEFT", weaponX[weapon], -452)
        elseif leftSlots[slot.slot] then row:SetPoint("TOPLEFT", 0, -(leftSlots[slot.slot] - 1) * 54)
        else row:SetPoint("TOPLEFT", 502, -(rightSlots[slot.slot] - 1) * 54) end
        row.slot = slot
        -- A hairline under each column row, and one above the weapons that spans the window.
        local position = leftSlots[slot.slot] or rightSlots[slot.slot]
        row.rule:ClearAllPoints()
        if position and position < 8 then
            row.rule:SetPoint("TOPLEFT", 6, -53)
            row.rule:SetSize(columnWidth - 12, 1)
        elseif weapon == 1 then
            row.rule:SetPoint("TOPLEFT", 0, 8)
            row.rule:SetSize(750, 1)
        end
        row.rule:SetShown(position ~= nil and position < 8 or weapon == 1)
        local revealIndex = weapon and 9 or leftSlots[slot.slot] or rightSlots[slot.slot]
        parent.revealRows[revealIndex] = parent.revealRows[revealIndex] or {}
        table.insert(parent.revealRows[revealIndex], row)
        row.section = section
        local quality = slot.item and (slot.item.qualityCode or slot.item.quality or "COMMON"):upper()
        local color = T.quality[quality] or T.cream
        local icon
        if slot.item then
            if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(tonumber(slot.item.id))
            elseif GetItemIcon then icon = GetItemIcon(tonumber(slot.item.id)) end
        end
        row.border:SetColorTexture(color[1], color[2], color[3], slot.item and 1 or 0.3)
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetShown(slot.item ~= nil)
        row.text:SetTextColor(unpack(slot.item and color or T.dim))
        row.text:SetText(A.Text(slot.item and slot.item.name or (slot.state == "empty" and "Empty slot" or "Not recorded")))
        -- Audit markers sit at the right edge of the row; the first visible one is outermost.
        local mark = audit.marks[slot.slot]
        local offset = 8
        for _, glyph in ipairs(row.marks) do
            local shown = mark ~= nil and ((glyph.markerKind == "enchant" and mark.enchant) or (glyph.markerKind == "socket" and mark.sockets)) and true or false
            glyph:SetShown(shown)
            if shown then
                glyph:ClearAllPoints()
                glyph:SetPoint("TOPRIGHT", row, "TOPRIGHT", -offset, -9)
                glyph.markerSlot = slot.slot
                glyph.markerItem = slot.item
                offset = offset + 22
            end
        end
        row:Show()
    end
    summary.coverage:SetText(recorded .. " of " .. total .. " slots recorded")
    local findings = G.Findings(audit)
    for index, finding in ipairs(summary.findings) do
        local entry = findings[index]
        finding.glyph:SetShown(entry ~= nil)
        finding.head:SetShown(entry ~= nil)
        finding.detail:SetShown(entry ~= nil)
        if entry then
            finding.glyph:SetKind(entry.kind)
            finding.head:SetText(A.Text(entry.short or entry.head))
            finding.detail:SetText(A.Text(entry.shortDetail or entry.detail))
        end
    end
    summary.hint:SetText((#audit.enchants + #audit.sockets) > 0 and "Hover a marker for its evidence." or (section.state == "partial" and "Unrecorded slots are not empty slots." or ""))
    summary:Show()
    return T.contentHeight
end
