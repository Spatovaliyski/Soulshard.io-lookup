local _, A = ...
local rows = setmetatable({}, { __mode = "k" })
local buttonWidth = 128
local buttonHeight = 20
local browseFont
local hooked = false
local disabled = false
A.lfgState = "Waiting for Blizzard_GroupFinder_VanillaStyle. Applicant rows are not verified."

local function clear(row)
    local decoration = rows[row]
    if not decoration then return end
    decoration.identity = nil
    decoration.liveGuid = nil
    decoration:Hide()
    if GameTooltip:GetOwner() == decoration then GameTooltip:Hide() end
end

function A.ClearRows()
    for row in pairs(rows) do clear(row) end
end

local function resolveRow(row)
    if not A.data or not C_LFGList or not row.resultID then return nil end
    local info = C_LFGList.GetSearchResultInfo(row.resultID)
    if type(info) ~= "table" or info.isDelisted or info.numMembers ~= 1 then return nil end
    return A.ResolveName(info.leaderName)
end

local function equipmentFor(identity, priority)
    local live = A.GetPlayerContext and A.GetPlayerContext(identity, nil, priority)
    if live then return live.sections.equipment or { state = "unavailable", source = "live" }, live end
    local character = A.FindCharacter(identity)
    return character and A.GetSectionSummary(character, A.sections[1])
end

local function showTooltip(decoration, row)
    local identity = resolveRow(row)
    if not identity or not row:IsShown() then clear(row); return end
    local section, live = equipmentFor(identity, 2)
    local score = section and section.data and section.data.gearScore
    GameTooltip:SetOwner(decoration, "ANCHOR_RIGHT")
    GameTooltip:AddLine(live and "Nearby inspection" or "Inspect saved profile", 1, 0.85, 0.4)
    if section then
        GameTooltip:AddLine(A.Text(score and ("GearScore " .. score.value .. " · " .. score.algorithm) or "GearScore unavailable"), 1, 1, 1, true)
        GameTooltip:AddLine(A.Text("Equipment: " .. A.SectionLabel(section)), 0.9, 0.9, 0.9, true)
        if live and live.message then GameTooltip:AddLine(A.Text(live.message), 0.9, 0.9, 0.9, true) end
    else GameTooltip:AddLine("No saved profile. Install a newer data pack.", 1, 1, 1, true) end
    GameTooltip:Show()
end

local function freePosition(row)
    if not row.Name or not row.ActivityName or not row.DataDisplay then error("Unsupported native browse row fields.") end
    local left, bottom, width, height = row:GetRect()
    if not left or width < buttonWidth + 4 or height < buttonHeight + 2 then return nil end
    local occupied = {}
    local function include(region)
        if not region or not region:IsVisible() then return end
        local x, y, w, h = region:GetRect()
        if x and w > 0 and h > 0 then table.insert(occupied, { x - left, y - bottom, w, h }) end
    end
    include(row.Name)
    include(row.Level)
    include(row.ClassIcon)
    include(row.NewPlayerFriendlyIcon)
    include(row.ActivityName)
    include(row.DataDisplay.Comment)
    local solo = row.DataDisplay.Solo
    if solo and solo:IsVisible() then
        include(solo.RolesText)
        for _, role in ipairs(solo.Roles or {}) do include(role) end
    end
    for _, y in ipairs({ 1, height - buttonHeight - 1 }) do
        for x = width - buttonWidth - 2, 2, -8 do
            local fits = true
            for _, rect in ipairs(occupied) do
                if x < rect[1] + rect[3] + 2 and x + buttonWidth > rect[1] - 2 and y < rect[2] + rect[4] + 1 and y + buttonHeight > rect[2] - 1 then fits = false; break end
            end
            if fits then return x, y end
        end
    end
end

local function update(row, passive, requestedPriority)
    if type(row) ~= "table" or type(row.GetObjectType) ~= "function" then return end
    local hovered = rows[row] and GameTooltip:GetOwner() == rows[row]
    local previousGuid = rows[row] and rows[row].liveGuid
    clear(row)
    if InCombatLockdown() then return end
    local identity = resolveRow(row)
    if not identity then return end
    local x, y = freePosition(row)
    if not x then return end
    local decoration = rows[row]
    if not decoration then
        if not browseFont then
            browseFont = CreateFont("SoulshardLookupBrowseFont")
            browseFont:SetFont(A.Theme.bodyFont, A.Theme.minimumFontSize, "")
            browseFont:SetTextColor(unpack(A.Theme.gold))
        end
        decoration = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        decoration:SetSize(buttonWidth, buttonHeight)
        decoration:SetNormalFontObject(browseFont)
        decoration:SetHighlightFontObject(browseFont)
        decoration:SetDisabledFontObject(browseFont)
        decoration:SetFrameLevel(row:GetFrameLevel() + 2)
        decoration:SetScript("OnClick", function(self)
            if InCombatLockdown() then return end
            local current = resolveRow(row)
            if not current or not row:IsShown() then clear(row); return end
            A.ShowProfile(current)
        end)
        decoration:SetScript("OnEnter", function(self) showTooltip(self, row) end)
        decoration:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:HookScript("OnHide", function() clear(row) end)
        rows[row] = decoration
    end
    decoration:ClearAllPoints()
    decoration:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, y)
    local priority = requestedPriority
    if not passive then priority = 4 end
    local section, live = equipmentFor(identity, priority)
    if live and passive and previousGuid ~= live.guid then section, live = equipmentFor(identity, 4) end
    local score = section and section.data and section.data.gearScore
    local stale = section and section.fetchedAt and time() - section.fetchedAt > A.staleAfter
    decoration.identity = identity
    decoration.liveGuid = live and live.guid
    decoration:SetText("GS " .. (score and score.value or (live and "…" or "—")) .. ((stale or (live and live.refreshing)) and "*" or "") .. " Inspect")
    decoration:Show()
    if hovered then showTooltip(decoration, row) end
end

local function safeUpdate(row, passive, priority)
    if disabled then return end
    local ok = pcall(update, row, passive, priority)
    if not ok then
        disabled = true
        A.ClearRows()
        A.lfgState = "Browse adapter disabled: unexpected native row shape. Run /sl diagnostics."
        A.Print(A.lfgState)
    end
end

function A.RefreshLiveLfg(guid, priority)
    for row in pairs(rows) do if row:IsVisible() then safeUpdate(row, true, priority) end end
end

function A.LfgEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then A.ClearRows(); return end
    if event == "PLAYER_REGEN_ENABLED" then
        for row in pairs(rows) do if row:IsShown() then safeUpdate(row) end end
    end
    if hooked or type(LFGBrowseSearchEntry_Update) ~= "function" then return end
    local _, _, _, interface = GetBuildInfo()
    if interface ~= A.interface or not C_LFGList or type(C_LFGList.GetSearchResultInfo) ~= "function" then
        A.lfgState = "Unsupported browse API/client. Native LFG is unchanged."
        return
    end
    hooksecurefunc("LFGBrowseSearchEntry_Update", function(row) safeUpdate(row) end)
    hooked = true
    A.lfgState = "Browse hook attached for 20506; explicit realm names only. In-game placement/taint validation pending."
end
