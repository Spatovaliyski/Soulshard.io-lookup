local _, A = ...

local function encode(value)
    return (value:gsub("[^%w%-._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local displayRealm = A.DisplayRealm

function A.LookupURL(name, realm)
    local identity = A.LookupIdentity(name, realm)
    if not identity then return end
    return "https://soulshard.io/inspect/character/classic-anni/" .. identity.region .. "/" .. encode(identity.realmSlug) .. "/" .. encode(identity.name)
end

function A.ShowLookupURL(name, realm)
    if InCombatLockdown() then A.Print("Browser lookup is unavailable during combat."); return end
    local url = A.LookupURL(name, realm)
    if not url then A.Print("Unable to resolve this player's name, realm or region."); return end
    local dialog = A.lookupDialog
    if not dialog then
        dialog = A.Theme.Panel(UIParent, 560, 132)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        local title = A.Theme.Text(dialog, 16, A.Theme.gold)
        title:SetPoint("TOPLEFT", 16, -12)
        title:SetText("Soulshard Lookup")
        local help = A.Theme.Text(dialog, 14, A.Theme.cream)
        help:SetPoint("TOPLEFT", 16, -39)
        help:SetText("Press Ctrl+C, then paste into your browser.")
        dialog.edit = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
        dialog.edit:SetSize(520, 24)
        dialog.edit:SetPoint("TOPLEFT", 20, -66)
        dialog.edit:SetAutoFocus(false)
        dialog.edit:SetFont(A.Theme.bodyFont, 14, "")
        dialog.edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
        dialog.edit:SetScript("OnEnterPressed", function() dialog:Hide() end)
        dialog:SetScript("OnHide", function() dialog.edit:ClearFocus() end)
        local close = A.Theme.Button(dialog, "Close", 80, 22, function() dialog:Hide() end)
        close:SetPoint("BOTTOMRIGHT", -16, 8)
        _G.SoulshardLookupURLDialog = dialog
        table.insert(UISpecialFrames, "SoulshardLookupURLDialog")
        A.lookupDialog = dialog
    end
    dialog:Show()
    dialog.edit:SetText(url)
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
end

local function inspectUnit()
    return InspectFrame and InspectFrame:IsShown() and InspectFrame.unit
end

function A.ShowPlayerProfile(unit)
    if InCombatLockdown() then A.Print("Player lookup is unavailable during combat."); return end
    local name, realm = A.PlayerName(unit)
    if not name then return end
    local identity = A.ResolveName(name, realm) or { name = name, realmName = realm, region = A.Region(), realmKey = (A.Region() or "") .. "/" .. realm }
    local snapshot = A.GetPlayerContext(identity, unit, 1)
    if snapshot or A.FindCharacter(identity) then A.ShowProfile(identity, snapshot)
    else A.Print("This player is no longer nearby or inspectable.") end
end
local function parseValue(value)
    if value == nil then return "-" end
    -- Match raidProgression.parseQuality and the frontend raid card palette.
    local color = "91899c"
    if value == 100 then color = "d5a745"
    elseif value >= 99 then color = "e879b2"
    elseif value >= 95 then color = "ff963b"
    elseif value >= 75 then color = "bb82ef"
    elseif value >= 50 then color = "69a8fa"
    elseif value >= 25 then color = "5bbf70" end
    return "|cff" .. color .. tostring(math.floor(value + 0.5)) .. "|r"
end

local function addRaidTooltip(tooltip, section)
    tooltip:AddDoubleLine("Raids (saved)", "Parse AVG / BEST", .88, .86, .91, .7, .67, .76)
    for _, raid in ipairs(section.data.raids) do
        local color = raid.killed == 0 and "ff5555" or raid.killed == raid.total and "55ff55" or "ffffff"
        local progress = "|cff" .. color .. (raid.killed or "-") .. "/" .. raid.total .. "|r"
        tooltip:AddDoubleLine(A.Text(raid.name) .. "  " .. progress,
            parseValue(A.AverageRaidParse(raid)) .. " / " .. parseValue(raid.bestParse), .88, .86, .91, 1, 1, 1)
    end
end

local function addTooltip(tooltip)
    local _, unit = tooltip:GetUnit()
    local name, realm = A.PlayerName(unit)
    if not name or tooltip.soulshardAdded then return end
    tooltip.soulshardAdded = true
    local identity = A.ResolveName(name, realm)
    local snapshot = A.GetPlayerContext(identity, unit, 2)
    local equipment = snapshot and snapshot.sections.equipment
    local score = equipment and equipment.data.gearScore and equipment.data.gearScore.value
    tooltip:AddLine("Soulshard Lookup", 1, .82, .3)
    if score then tooltip:AddDoubleLine("GearScore (live)", tostring(score), .88, .86, .91, 1, .82, .3)
    elseif snapshot then tooltip:AddLine(A.Text(snapshot.message or "Live GearScore unavailable."), .62, .59, .68, true) end
    local talents = snapshot and snapshot.sections.talents
    if talents then
        local points, highest, spec = {}, -1, ""
        for index, tree in ipairs(talents.data.groups[1].trees) do
            points[index] = tostring(tree.points)
            if tree.points > highest then highest, spec = tree.points, A.catalogs[snapshot.summary.classToken][index].name end
        end
        tooltip:AddDoubleLine(talents.state == "partial" and "Talents (live, partial)" or "Talents (live)", A.Text(spec) .. " [" .. table.concat(points, "/") .. "]", .88, .86, .91, .88, .86, .91)
    end
    local character = A.FindCharacter(identity)
    if character then
        for _, descriptor in ipairs(A.sections) do
            -- Raid logs remain archived; nearby equipment and talents never fall back to the archive.
            local section = descriptor.id == "raids" and A.GetSection(character, descriptor) or (not snapshot and A.GetSectionSummary(character, descriptor))
            if section and descriptor.id == "equipment" and section.data and section.data.gearScore then
                tooltip:AddDoubleLine("GearScore (saved)", tostring(section.data.gearScore.value), .88, .86, .91, 1, .82, .3)
            elseif section and descriptor.id == "raids" and section.data then addRaidTooltip(tooltip, section)
            elseif section and descriptor.id == "talents" and section.data then
                for _, group in ipairs(section.data.groups) do
                    if group.active then
                        local points = {}
                        for _, tree in ipairs(group.trees) do table.insert(points, tostring(tree.points)) end
                        tooltip:AddDoubleLine("Talents (saved)", table.concat(points, "/"), .88, .86, .91, .88, .86, .91)
                    end
                end
            end
            if section and section.data then
                local stale = time() - section.fetchedAt > A.staleAfter
                local status = section.state == "partial" and "partial" or ""
                if stale then status = status .. (status ~= "" and " · " or "") .. "stale (older than 24 hours)" end
                if status ~= "" then
                    local color = stale and A.Theme.danger or A.Theme.muted
                    tooltip:AddLine(A.Text("Saved " .. descriptor.label .. ": " .. status), color[1], color[2], color[3], true)
                end
            end
        end
    end
    tooltip:Show()
end
local function installInspectButton()
    if not InspectFrame or A.inspectLookup or InCombatLockdown() then return end
    local button = CreateFrame("Button", nil, InspectFrame, "UIPanelButtonTemplate")
    button:SetSize(108, 22)
    button:SetPoint("TOPRIGHT", -12, -32)
    button:SetText("Lookup")
    button:SetScript("OnClick", function()
        local name, realm = A.PlayerName(InspectFrame.unit)
        if name then A.ShowPlayerProfile(InspectFrame.unit) end
    end)
    button.score = A.Theme.Text(InspectFrame, 14, A.Theme.gold)
    button.score:SetPoint("RIGHT", button, "LEFT", -8, 0)
    InspectFrame:HookScript("OnShow", function() button.score:SetText("") end)
    InspectFrame:HookScript("OnHide", function() button.score:SetText("") end)
    if type(InspectFrame_Show) == "function" then
        hooksecurefunc("InspectFrame_Show", function() button.score:SetText("") end)
    end
    A.inspectLookup = button
end

local installedMenu = false
local function installMenu()
    if installedMenu or not Menu or not Menu.ModifyMenu then return end
    installedMenu = true
    for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_SELF" }) do
        Menu.ModifyMenu(tag, function(_, root, context)
            if not context then return end
            local name, realm
            if context.unit then name, realm = A.PlayerName(context.unit)
            else name, realm = context.name, context.server end
            if not A.LookupURL(name, realm) then return end
            local short, suffix = name:match("^([^-]+)%-(.+)$")
            local identity = A.ResolveName(short or name, displayRealm(suffix or realm or GetRealmName())) or
                { name = short or name, realmName = displayRealm(suffix or realm or GetRealmName()), region = A.Region() }
            local character = A.FindCharacter(identity)
            local snapshot = A.GetPlayerContext(identity, context.unit, 1)
            local equipment = snapshot and snapshot.sections.equipment or (not snapshot and character and A.GetSectionSummary(character, A.sections[1]))
            local score = equipment and equipment.data and equipment.data.gearScore
            root:CreateDivider()
            root:CreateTitle("Soulshard Lookup")
            root:CreateButton("Soulshard Web Lookup", function() A.ShowLookupURL(name, realm) end)
            local ingame = root:CreateButton("Ingame Lookup (" .. (score and tostring(score.value) or "-") .. "gs)", function()
                local live = A.GetPlayerContext(identity, context.unit, 1)
                if live then A.ShowPlayerProfile(live.unit)
                elseif character then A.ShowProfile(identity)
                else A.Print("This player is no longer nearby or inspectable.") end
            end)
            ingame:SetEnabled(character ~= nil or snapshot ~= nil)
        end)
    end
end

function A.RefreshPlayerViews(guid)
    local hovered, hoveredGuid
    if GameTooltip and GameTooltip.GetUnit and GameTooltip:IsShown() then
        local ignored
        ignored, hovered = GameTooltip:GetUnit()
        hoveredGuid = hovered and UnitGUID(hovered)
    end
    if A.profile and A.profile:IsShown() and A.profile.view == "profile" and A.profile.profileIdentity then
        local live = A.profile.liveSnapshot
        if not guid or not live or live.guid == guid then A.ShowProfile(A.profile.profileIdentity, nil, true) end
    end
    local unit = inspectUnit()
    if A.inspectLookup and unit then
        local snapshot = A.GetPlayerContext(nil, unit)
        local equipment = snapshot and snapshot.sections.equipment
        local score = equipment and equipment.data.gearScore
        A.inspectLookup.score:SetText(score and "GS " .. score.value or "")
    end
    if hovered and hoveredGuid and UnitGUID(hovered) == hoveredGuid and (not guid or hoveredGuid == guid) then
        GameTooltip.soulshardAdded = nil
        GameTooltip:SetUnit(hovered)
    end
    if A.RefreshLiveLfg then A.RefreshLiveLfg(guid) end
    if A.RefreshLiveSearch then A.RefreshLiveSearch(guid) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function() installInspectButton(); installMenu() end)
if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipCleared", function(self) self.soulshardAdded = nil end)
    GameTooltip:HookScript("OnTooltipSetUnit", addTooltip)
end
