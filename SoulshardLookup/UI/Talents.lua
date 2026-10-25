local _, A = ...
local layout = A.Theme.tree
local contentHeight = A.Theme.contentHeight

-- Blizzard's talent paintings, one per tree, in catalog order.
local backgrounds = {
    WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
    PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    MAGE = { "MageArcane", "MageFire", "MageFrost" },
    WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
}

-- The painting fills the whole panel. Blizzard crops transparent padding from the right and bottom
-- tiles, so only the 300 x 331 painting is stretched.
local function treeArt(panel)
    local scaleX = layout.width / 300
    local scaleY = layout.height / 331
    local art = {}
    for _, piece in ipairs({ { "TopLeft", 0, 0, 256, 256, 1, 1 }, { "TopRight", 256, 0, 44, 256, 0.6875, 1 }, { "BottomLeft", 0, 256, 256, 75, 1, 0.5859375 }, { "BottomRight", 256, 256, 44, 75, 0.6875, 0.5859375 } }) do
        local texture = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
        texture:SetPoint("TOPLEFT", piece[2] * scaleX, -piece[3] * scaleY)
        texture:SetSize(piece[4] * scaleX, piece[5] * scaleY)
        texture:SetTexCoord(0, piece[6], 0, piece[7])
        texture:SetAlpha(0.6)
        table.insert(art, { texture = texture, suffix = piece[1] })
    end
    return art
end

local function talentTooltip(button)
    local node, allocation = button.node, button.allocation
    local rank = allocation and allocation.rank or 0
    local spellId = node.spellIds[math.max(1, rank)]
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(spellId)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(button.live and "Live rank" or "Saved rank", button.rankLabel, 1, 0.82, 0, 1, 1, 1)
    if rank == 0 then GameTooltip:AddLine(button.partial and "Allocation unknown. Showing the first rank." or "Unspent talent. Showing the first rank.", 0.5, 0.5, 0.5, true) end
    GameTooltip:AddLine(button.live and "Nearby inspection · Read only" or "Saved profile · Read only", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function noticeTooltip(self)
    if not self.data then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Partial talent record", 1, 0.85, 0.4)
    GameTooltip:AddLine("Question marks indicate unknown allocations, not unspent points.", 0.9, 0.9, 0.9, true)
    for _, allocation in ipairs(self.data.unmatched) do
        GameTooltip:AddLine(A.Text(allocation.name .. " · rank " .. allocation.rank), 1, 1, 1, true)
        GameTooltip:AddLine(A.Text(allocation.description), 0.9, 0.9, 0.9, true)
    end
    GameTooltip:Show()
end

-- Allocated / not-allocated key under the trees, built once.
local function createLegend(parent, T)
    local legend = CreateFrame("Frame", nil, parent)
    legend:SetPoint("TOPLEFT", 2, -490)
    legend:SetSize(560, 16)
    local function mini(x, allocated)
        T.Fill(legend, x, 1, 14, 14, allocated and T.gold or T.Blend(T.hair, T.background, 0.22), 1, "BORDER")
        T.Fill(legend, x + 1, 2, 12, 12, { 0.03, 0.025, 0.02 }, 1, "ARTWORK")
        local square = T.Fill(legend, x + 2, 3, 10, 10, T.Hex("e0702f"), allocated and 1 or 0.35, "OVERLAY")
        return square
    end
    mini(0, true)
    local allocated = T.Text(legend, 13, T.muted)
    allocated:SetPoint("LEFT", 22, 0)
    allocated:SetText("Allocated")
    mini(100, false)
    local unallocated = T.Text(legend, 13, T.muted)
    unallocated:SetPoint("LEFT", 122, 0)
    unallocated:SetText("Not allocated")
    legend.total = T.Text(legend, 13, T.muted)
    legend.total:SetPoint("LEFT", unallocated, "RIGHT", 8, 0)
    legend.hint = T.Text(parent, 13, T.dim)
    legend.hint:SetPoint("TOPRIGHT", -2, -490)
    legend.hint:SetJustifyH("RIGHT")
    legend.hint:SetText("Hover a talent for its tooltip.")
    return legend
end

function A.RenderTalents(parent, section, character)
    local T = A.Theme
    parent.nodes = parent.nodes or {}
    parent.panels = parent.panels or {}
    parent.links = parent.links or {}
    for _, node in ipairs(parent.nodes) do node:Hide() end
    for _, panel in ipairs(parent.panels) do panel:Hide() end
    for _, link in ipairs(parent.links) do link:Hide() end
    if not parent.notice then
        parent.notice = T.Button(parent, "Partial record · Hover for details", 280, 22, nil, "tint", 13)
        parent.notice:SetPoint("TOPRIGHT", 0, -487)
        parent.notice:SetScript("OnEnter", noticeTooltip)
        parent.notice:SetScript("OnLeave", function() GameTooltip:Hide() end)
        parent.message = T.Text(parent, 18, T.muted, true)
        parent.message:SetPoint("CENTER")
        parent.message:SetSize(640, 80)
        parent.message:SetJustifyH("CENTER")
        parent.legend = createLegend(parent, T)
    end
    parent.notice:Hide()
    parent.message:Hide()
    parent.legend:Hide()
    parent.legend.hint:Hide()
    if not section.data then return contentHeight end
    local data = section.data
    local group
    local activeCount = 0
    for _, candidate in ipairs(data.groups) do
        if candidate.active then group = candidate; activeCount = activeCount + 1 end
    end
    if activeCount ~= 1 then
        parent.message:SetText("No unique active talent group was saved.\nAn unknown build is never shown as an empty build.")
        parent.message:Show()
        return contentHeight
    end
    parent.notice.data = data
    parent.notice:SetShown(section.state == "partial")
    parent.legend:Show()
    parent.legend.hint:SetShown(section.state ~= "partial")
    local deepest, total = 0, 0
    for _, tree in ipairs(group.trees) do
        total = total + tree.points
        deepest = math.max(deepest, tree.points)
    end
    parent.legend.total:SetText(T.Wrap(T.faint, "·") .. " " .. total .. " points in all")
    local nodeIndex = 0
    local linkIndex = 0
    for treeIndex, tree in ipairs(A.catalogs[character.summary.classToken]) do
        local savedTree = group.trees[treeIndex]
        local allocations = {}
        for _, allocation in ipairs(savedTree.allocations) do allocations[allocation.nodeKey] = allocation end
        local accent = T.SpecColor(tree.name)
        local panel = parent.panels[treeIndex]
        if not panel then
            panel = T.Card(parent, layout.width, layout.height)
            panel:SetPoint("TOPLEFT", (treeIndex - 1) * layout.pitch, 0)
            panel.accent = T.Fill(panel, 0, 0, layout.width, 3, accent, 1, "ARTWORK")
            -- A card-coloured veil keeps icons and numbers readable: darker behind the header.
            panel.shade = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
            panel.shade:SetAllPoints()
            panel.shade:SetColorTexture(1, 1, 1, 1)
            panel.shade:SetGradient("VERTICAL", CreateColor(T.surface[1], T.surface[2], T.surface[3], 0.3), CreateColor(T.surface[1], T.surface[2], T.surface[3], 0.7))
            -- Shown only when the client has no painting for the tree.
            panel.watermark = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
            panel.watermark:SetPoint("CENTER", 0, -20)
            panel.watermark:SetSize(160, 160)
            panel.watermark:SetAlpha(0.1)
            panel.watermark:SetDesaturated(true)
            panel.art = treeArt(panel)
            panel.title = T.Text(panel, 19, T.goldBright, true)
            panel.title:SetPoint("TOPLEFT", 14, -10)
            panel.title:SetSize(layout.width - 80, 26)
            panel.title:SetMaxLines(1)
            panel.subtitle = T.Text(panel, 13, T.muted)
            panel.subtitle:SetPoint("TOPLEFT", 14, -35)
            panel.points = T.Text(panel, 26, T.cream, true)
            panel.points:SetPoint("TOPRIGHT", -14, -8)
            panel.points:SetJustifyH("RIGHT")
            T.Hair(panel, 14, 58, layout.width - 28, 0.12)
            parent.panels[treeIndex] = panel
        end
        local pointsInTree = savedTree.points
        panel:SetBackdropColor(unpack(T.Blend(accent, T.surface, 0.05)))
        panel.accent:SetColorTexture(accent[1], accent[2], accent[3], pointsInTree > 0 and 1 or 0.55)
        panel.title:SetText(A.Text(tree.name))
        panel.title:SetTextColor(unpack(pointsInTree > 0 and T.goldBright or T.muted))
        panel.subtitle:SetText(section.source == "live" and "Live points" or "Saved points")
        panel.points:SetText(tostring(pointsInTree))
        panel.points:SetTextColor(unpack(pointsInTree > 0 and pointsInTree == deepest and T.goldBright or pointsInTree > 0 and T.Hex("ece0c2") or T.Hex("7d725c")))
        local watermark = tree.nodes[1] and tree.nodes[1].icon
        panel.watermark:SetTexture(watermark and "Interface\\Icons\\" .. watermark or "Interface\\Icons\\INV_Misc_Book_09")
        local background = backgrounds[character.summary.classToken][treeIndex]
        local hasArt = true
        for _, piece in ipairs(panel.art) do
            if piece.texture:SetTexture("Interface\\TalentFrame\\" .. background .. "-" .. piece.suffix) == false then hasArt = false end
        end
        for _, piece in ipairs(panel.art) do piece.texture:SetShown(hasArt) end
        panel.watermark:SetShown(not hasArt)
        panel:Show()
        for _, node in ipairs(tree.nodes) do
            nodeIndex = nodeIndex + 1
            local button = parent.nodes[nodeIndex]
            if not button then
                button = CreateFrame("Button", nil, panel, "BackdropTemplate")
                button:SetSize(layout.tile, layout.tile)
                button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                button:SetBackdropColor(0.027, 0.024, 0.02, 1)
                button.icon = button:CreateTexture(nil, "ARTWORK")
                button.icon:SetPoint("TOPLEFT", 3, -3)
                button.icon:SetSize(layout.tile - 6, layout.tile - 6)
                button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                button.badge = T.Card(button, 30, 17, T.surface)
                button.badge:SetPoint("BOTTOMRIGHT", 8, -7)
                button.rank = T.Text(button.badge, 13, T.cream)
                button.rank:SetPoint("CENTER")
                button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(T.goldBright)); talentTooltip(self) end)
                button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(self.color)); GameTooltip:Hide() end)
                parent.nodes[nodeIndex] = button
            end
            button:SetParent(panel)
            local allocation = allocations[node.nodeKey]
            local rank = allocation and allocation.rank or 0
            local partial = section.state == "partial"
            button.node = node
            button.allocation = allocation
            button.partial = partial
            button.live = section.source == "live"
            button.rankLabel = (rank == 0 and partial and "?" or tostring(rank)) .. "/" .. node.maxRank
            button.color = rank > 0 and T.gold or T.Blend(T.hair, T.surface, 0.18)
            button:SetBackdropBorderColor(unpack(button.color))
            button.rank:SetText(button.rankLabel)
            button.rank:SetTextColor(unpack(rank == node.maxRank and T.goldBright or rank > 0 and T.cream or T.dim))
            button.icon:SetTexture(node.icon and "Interface\\Icons\\" .. node.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            button.icon:SetDesaturated(rank == 0)
            button.icon:SetAlpha(rank > 0 and 1 or 0.4)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", layout.x + node.column * layout.columnPitch, -layout.y - node.row * layout.rowPitch)
            button:Show()
            if node.prerequisite then
                linkIndex = linkIndex + 1
                local link = parent.links[linkIndex]
                if not link then
                    link = panel:CreateLine(nil, "ARTWORK")
                    link:SetThickness(2)
                    parent.links[linkIndex] = link
                end
                local color = rank > 0 and T.gold or T.hair
                link:SetColorTexture(color[1], color[2], color[3], rank > 0 and 0.85 or 0.16)
                link:SetParent(panel)
                local sameRow = node.prerequisite.row == node.row
                local direction = node.column > node.prerequisite.column and 1 or -1
                local fromX = layout.x + node.prerequisite.column * layout.columnPitch + (sameRow and (direction > 0 and layout.tile or 0) or layout.tile / 2)
                local fromY = -layout.y - node.prerequisite.row * layout.rowPitch - (sameRow and layout.tile / 2 or layout.tile)
                local toX = layout.x + node.column * layout.columnPitch + (sameRow and (direction > 0 and 0 or layout.tile) or layout.tile / 2)
                local toY = -layout.y - node.row * layout.rowPitch - (sameRow and layout.tile / 2 or 0)
                link:SetStartPoint("TOPLEFT", fromX, fromY)
                link:SetEndPoint("TOPLEFT", toX, toY)
                link:Show()
            end
        end
    end
    return contentHeight
end
