local _, A = ...
local T = A.Theme
local ART = "Interface\\AddOns\\SoulshardLookup\\Media\\Raids\\"
local LOGS = { 0.702, 0.659, 0.796 }
local rowPitch = 56
local columns = {
    { id = "kills", label = "Kills", right = 300 },
    { id = "highest", label = "Best", right = 382 },
    { id = "average", label = "Median", right = 470 },
}

local function value(number)
    return number and tostring(math.floor(number + 0.5)) or "—"
end

local function sep()
    return " " .. T.Wrap(T.faint, "·") .. " "
end

local function metric(parent, rightEdge, size, color, y)
    local text = T.Text(parent, size, color)
    text:SetJustifyH("RIGHT")
    text:SetSize(70, size + 5)
    text:SetPoint("TOPLEFT", rightEdge - 70, -y)
    text:SetMaxLines(1)
    return text
end

local function stat(panel, x, name)
    local entry = {}
    entry.label = T.Text(panel, 13, T.muted)
    entry.label:SetPoint("TOPLEFT", x, -106)
    entry.label:SetText(name)
    entry.value = T.Text(panel, 28, T.cream, true)
    entry.value:SetPoint("TOPLEFT", x, -124)
    entry.value:SetSize(110, 34)
    entry.value:SetMaxLines(1)
    entry.note = T.Text(panel, 13, T.dim)
    entry.note:SetPoint("TOPLEFT", x, -160)
    entry.note:SetSize(112, 18)
    entry.note:SetMaxLines(1)
    return entry
end

local function showRaid(parent, index)
    parent.selected = index
    local raid = parent.raids[index]
    local panel = parent.detail
    for rowIndex, button in ipairs(parent.rows) do button:SetSelected(rowIndex == index) end
    panel.art:SetTexture(ART .. raid.artwork .. ".tga")
    panel.chapter:SetText("Phase " .. raid.phase .. sep() .. raid.size .. " players")
    panel.title:SetText(A.Text(raid.name))
    local killed = raid.killed or 0
    local complete = killed == raid.total
    panel.defeated.value:SetText(T.Wrap(complete and T.goldBright or killed > 0 and T.Hex("ece0c2") or T.dim, tostring(killed)) .. T.Wrap(T.muted, " / " .. raid.total))
    panel.runs.value:SetText(value(raid.runs))
    panel.runs.value:SetTextColor(unpack(raid.runs and T.bright or T.faint))
    local average, best = A.AverageRaidParse(raid), A.BestRaidParse(raid)
    local parsed = 0
    for _, boss in ipairs(raid.bosses) do if boss.bestParse ~= nil then parsed = parsed + 1 end end
    panel.average.value:SetText(value(average))
    panel.average.value:SetTextColor(unpack(T.ParseColor(average)))
    panel.average.note:SetText(average and (parsed == raid.total and "mean of boss bests" or (parsed .. " of " .. raid.total .. " bosses")) or "no logged parses")
    panel.best.value:SetText(value(best))
    panel.best.value:SetTextColor(unpack(T.ParseColor(best)))
    for bossIndex, row in ipairs(panel.bossRows) do
        local boss = raid.bosses[bossIndex]
        row:SetShown(boss ~= nil)
        if boss then
            row.number:SetText(string.format("%02d", bossIndex))
            row.name:SetText(A.Text(boss.name))
            row.name:SetTextColor(unpack(boss.kills ~= nil and T.Hex("ece0c2") or T.dim))
            row.kills:SetText(value(boss.kills))
            row.kills:SetTextColor(unpack(boss.kills ~= nil and T.cream or T.faint))
            row.highest:SetText(value(boss.bestParse))
            row.highest:SetTextColor(unpack(T.ParseColor(boss.bestParse)))
            row.average:SetText(value(boss.medianParse))
            row.average:SetTextColor(unpack(T.ParseColor(boss.medianParse)))
            row.rule:SetShown(bossIndex < #raid.bosses)
        end
    end
    local gap = 3
    for bossIndex, segment in ipairs(panel.segments) do
        segment:SetShown(bossIndex <= raid.total)
        if bossIndex <= raid.total then
            local width = (136 - gap * (raid.total - 1)) / raid.total
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", 16 + (bossIndex - 1) * (width + gap), -164)
            segment:SetSize(width, 4)
            local boss = raid.bosses[bossIndex]
            local color = boss and boss.kills and boss.kills > 0 and T.Hex("d9ac4a") or T.Blend(T.hair, T.surface, 0.14)
            segment:SetColorTexture(color[1], color[2], color[3], 1)
        end
    end
end

local function createRow(parent, definition, index)
    local row = CreateFrame("Button", nil, parent.list)
    row:SetSize(244, 52)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * rowPitch)
    row.selectedFill = T.Fill(row, 0, 0, 244, 52, T.gold, 0.11, "BACKGROUND")
    row.selectedFill:SetAllPoints()
    row.selectedFill:Hide()
    row.hover = T.Fill(row, 0, 0, 244, 52, T.hair, 0.05, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.art = row:CreateTexture(nil, "ARTWORK")
    row.art:SetPoint("TOPLEFT", 10, -6)
    row.art:SetSize(60, 40)
    row.art:SetTexture(ART .. definition.artwork .. ".tga")
    row.art:SetTexCoord(0.232, 0.768, 0, 1)
    row.activePhase = definition.phase == A.currentRaidPhase
    row.phaseMarker = T.Fill(row, 0, 9, 3, 34, T.gold, 1, "OVERLAY")
    row.phaseMarker:SetShown(row.activePhase)
    row.title = T.Text(row, 15, row.activePhase and T.goldBright or T.bright)
    row.title:SetPoint("TOPLEFT", 80, -6)
    row.title:SetSize(158, 20)
    row.title:SetMaxLines(1)
    row.title:SetText(A.Text(definition.name))
    row.progress = T.Text(row, 13, T.dim)
    row.progress:SetPoint("TOPLEFT", 80, -27)
    row.progress:SetSize(158, 18)
    row.progress:SetMaxLines(1)
    function row:SetSelected(selected)
        self.selected = selected
        self.selectedFill:SetShown(selected)
    end
    row:SetScript("OnClick", function() showRaid(parent, index) end)
    row:SetScript("OnEnter", function(self) if not self.selected then self.hover:Show() end end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:HookScript("OnHide", function(self) self.hover:Hide() end)
    return row
end

function A.RenderRaids(parent, section)
    if not parent.detail then
        parent.rows = {}
        parent.eyebrow = T.Text(parent, 18, T.goldBright, true)
        parent.eyebrow:SetPoint("TOPLEFT", 4, 0)
        parent.eyebrow:SetText("The Burning Crusade")
        parent.subtitle = T.Text(parent, 13, T.muted)
        parent.subtitle:SetPoint("TOPLEFT", 4, -26)
        parent.subtitle:SetText("Raid journal" .. sep() .. "gold edge = current phase")
        parent.viewport = CreateFrame("ScrollFrame", nil, parent)
        parent.viewport:SetPoint("TOPLEFT", 0, -52)
        parent.viewport:SetSize(244, 454)
        parent.viewport:EnableMouseWheel(true)
        parent.list = CreateFrame("Frame", nil, parent.viewport)
        parent.list:SetSize(244, 1)
        parent.viewport:SetScrollChild(parent.list)
        parent.scrollbar = CreateFrame("Slider", nil, parent)
        parent.scrollbar:SetPoint("TOPLEFT", 248, -52)
        parent.scrollbar:SetSize(4, 452)
        parent.scrollbar:SetOrientation("VERTICAL")
        parent.scrollbar:SetValueStep(1)
        T.Fill(parent.scrollbar, 0, 0, 4, 452, T.hair, 0.09)
        local thumb = T.Fill(parent.scrollbar, 0, 0, 4, 36, T.gold, 0.55)
        parent.scrollbar:SetThumbTexture(thumb)
        parent.scrollbar:SetScript("OnValueChanged", function(_, offset)
            parent.scrollOffset = offset
            parent.viewport:SetVerticalScroll(offset)
        end)
        function parent:UpdateRaidScroll()
            local height = #self.rows * rowPitch - 4
            self.list:SetHeight(height)
            self.maxScroll = math.max(0, height - self.viewport:GetHeight())
            self.scrollbar:SetMinMaxValues(0, self.maxScroll)
            self.scrollbar:SetShown(self.maxScroll > 0)
            self.scrollbar:SetValue(math.min(self.scrollOffset or 0, self.maxScroll))
        end
        parent.viewport:SetScript("OnSizeChanged", function() parent:UpdateRaidScroll() end)
        parent.viewport:SetScript("OnMouseWheel", function(_, delta)
            parent.scrollbar:SetValue(math.max(0, math.min(parent.maxScroll, (parent.scrollOffset or 0) - delta * rowPitch)))
        end)
        for index, definition in ipairs(A.raidLibrary) do parent.rows[index] = createRow(parent, definition, index) end

        local panel = T.Card(parent, 486, 506)
        panel:SetPoint("TOPLEFT", 264, 0)
        panel.art = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
        panel.art:SetPoint("TOPLEFT")
        panel.art:SetSize(486, 96)
        panel.art:SetTexCoord(0, 1, 0.17, 0.72)
        panel.art:SetAlpha(0.85)
        T.Shade(panel, 0, 0, 486, 38, 0.55, 0.15, T.surface)
        T.Shade(panel, 0, 38, 486, 58, 0.15, 0.96, T.surface)
        panel.chapter = T.Text(panel, 13, T.goldBright)
        panel.chapter:SetPoint("TOPLEFT", 16, -8)
        panel.title = T.Text(panel, 29, T.bright, true)
        panel.title:SetPoint("TOPLEFT", 16, -30)
        panel.title:SetSize(450, 36)
        panel.title:SetMaxLines(1)
        panel.source = T.Text(panel, 13, LOGS)
        panel.source:SetPoint("TOPRIGHT", -16, -8)
        panel.source:SetJustifyH("RIGHT")
        panel.chart = CreateFrame("Frame", nil, panel)
        panel.chart:SetSize(12, 12)
        T.Fill(panel.chart, 0.7, 5, 1.6, 6, LOGS, 1, "OVERLAY")
        T.Fill(panel.chart, 4.2, 1.5, 1.6, 9.5, LOGS, 1, "OVERLAY")
        T.Fill(panel.chart, 7.7, 4.2, 1.6, 6.8, LOGS, 1, "OVERLAY")
        T.Fill(panel.chart, 0.7, 10.4, 10.6, 1.4, LOGS, 1, "OVERLAY")
        panel.defeated = stat(panel, 16, "Bosses defeated")
        panel.runs = stat(panel, 172, "Logged runs")
        panel.runs.note:SetText("final-boss kills")
        panel.average = stat(panel, 276, "Average parse")
        panel.best = stat(panel, 388, "Best parse")
        panel.best.note:SetText("any logged kill")
        panel.defeated.note:SetText("")
        panel.segments = {}
        for index = 1, 10 do panel.segments[index] = T.Fill(panel, 16, 164, 20, 4, T.gold, 1, "ARTWORK") end
        T.Hair(panel, 16, 186, 454, 0.12)
        local encounter = T.Text(panel, 13, T.muted)
        encounter:SetPoint("TOPLEFT", 16, -194)
        encounter:SetText("Encounter")
        panel.columns = {}
        for _, column in ipairs(columns) do
            local heading = metric(panel, column.right, 13, T.muted, 194)
            heading:SetText(column.label)
            panel.columns[column.id] = heading
        end
        panel.bossRows = {}
        for index = 1, 10 do
            local y = 218 + (index - 1) * 26
            local row = CreateFrame("Frame", nil, panel)
            row:SetPoint("TOPLEFT", 16, -y)
            row:SetSize(454, 26)
            row.number = T.Text(row, 13, T.faint)
            row.number:SetPoint("TOPLEFT", 0, -3)
            row.name = T.Text(row, 15, T.cream)
            row.name:SetPoint("TOPLEFT", 28, -3)
            row.name:SetSize(190, 20)
            row.name:SetMaxLines(1)
            row.kills = metric(row, 284, 15, T.cream, 3)
            row.highest = metric(row, 366, 15, T.cream, 3)
            row.average = metric(row, 454, 15, T.cream, 3)
            row.rule = T.Fill(row, 0, 25, 454, 1, T.hair, 0.06, "BORDER")
            panel.bossRows[index] = row
        end
        panel.note = T.Text(panel, 13, T.dim)
        panel.note:SetPoint("TOPLEFT", 16, -482)
        panel.note:SetSize(454, 18)
        panel.note:SetMaxLines(1)
        panel.note:SetText("Runs = final-boss kills" .. sep() .. "Median = typical parse on that boss" .. sep() .. "— = no logged data")
        parent.detail = panel
        function parent:SelectRaid(index)
            if self.raids and self.raids[index] then showRaid(self, index) end
        end
        parent.revealRows = { parent.rows, { panel } }
    end
    parent.raids = section.data and section.data.raids or A.raidLibrary
    for index, button in ipairs(parent.rows) do
        local raid = parent.raids[index]
        local killed = raid.killed or 0
        if killed == 0 then
            button.progress:SetText("No logged kills")
        else
            button.progress:SetText(T.Wrap(killed == raid.total and T.goldBright or T.Hex("ece0c2"), tostring(killed)) .. T.Wrap(T.muted, " / " .. raid.total .. " bosses") .. (raid.runs and (sep() .. T.Wrap(T.muted, raid.runs .. " runs")) or ""))
        end
        button.progress:SetTextColor(unpack(T.dim))
    end
    parent:UpdateRaidScroll()
    local panel = parent.detail
    if section.data then
        panel.source:SetText("Warcraft Logs" .. sep() .. "DPS" .. sep() .. "historical" .. (section.fetchedAt and (sep() .. "saved " .. T.Ago(section.fetchedAt)) or ""))
    else
        panel.source:SetText("No raid progression logged for this character")
    end
    panel.chart:ClearAllPoints()
    panel.chart:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(16 + T.TextWidth(panel.source) + 7), -12)
    panel.chart:SetShown(section.data ~= nil)
    showRaid(parent, parent.selected or 1)
    return T.contentHeight
end
