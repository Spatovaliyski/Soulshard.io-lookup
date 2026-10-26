local _, A = ...
local T = A.Theme
local M = A.Motion
local width = T.width

local function sectionInput(region, enabled)
    local body = region.body
    for _, widget in ipairs(body.rows or {}) do widget:EnableMouse(enabled and widget:IsShown()) end
    for _, widget in ipairs(body.nodes or {}) do widget:EnableMouse(enabled and widget:IsShown()) end
    if body.notice then body.notice:EnableMouse(enabled and body.notice:IsShown()) end
end

local function revealSection(region)
    local body = region.body
    local timing = M.timing
    sectionInput(region, false)
    if region.message:IsShown() then
        M.Reveal(region.message, 0, timing.message, 0)
    elseif body.message and body.message:IsShown() then
        M.Reveal(body.message, 0, timing.message, 0)
    elseif body.revealRows then
        if body.summary and body.summary:IsShown() then M.Reveal(body.summary, timing.summaryDelay, timing.summary, 8) end
        for index, rows in ipairs(body.revealRows) do
            for _, row in ipairs(rows) do
                local delay = index == 9 and timing.weaponsDelay or timing.rowDelay + (index - 1) * timing.rowStagger
                local duration = index == 9 and timing.weapons or timing.row
                M.Reveal(row, delay, duration, 8, function() row:EnableMouse(true) end)
            end
        end
    else
        for index, panel in ipairs(body.panels or {}) do
            if panel:IsShown() then
                M.Reveal(panel, timing.treeDelay + (index - 1) * timing.treeStagger, timing.tree, 8, function()
                    for _, node in ipairs(body.nodes) do if node:GetParent() == panel and node:IsShown() then node:EnableMouse(true) end end
                end)
            end
        end
        if body.notice and body.notice:IsShown() then
            M.Reveal(body.notice, timing.treeDelay, timing.tree, 0, function() body.notice:EnableMouse(true) end)
        end
    end
end

-- Small line glyphs for the header buttons, drawn on a 14-unit canvas so no art ships with them.
local function lineGlyph(button, points, color, thickness)
    for index = 1, #points - 1 do
        local line = button:CreateLine(nil, "OVERLAY")
        line:SetThickness(thickness or 1.5)
        line:SetColorTexture(color[1], color[2], color[3], 1)
        line:SetStartPoint("TOPLEFT", points[index][1], -points[index][2])
        line:SetEndPoint("TOPLEFT", points[index + 1][1], -points[index + 1][2])
    end
end

-- The magnifier spans y 8 to 19.8 of the 28-unit button, so its middle (13.9) is the button's middle.
local function searchGlyph(button, x, color, backing)
    local top = 8
    local ring = T.Disc(button, "TOPLEFT", x + 2, -top, 8, color, 1, "OVERLAY")
    T.Disc(button, "TOPLEFT", x + 3.5, -(top + 1.5), 5, backing, 1, "OVERLAY", 1)
    lineGlyph(button, { { x + 8.7, top + 7.7 }, { x + 12, top + 11 } }, color, 1.6)
    return ring
end

local function externalGlyph(button, x, color)
    local top = 7
    lineGlyph(button, { { x + 6, top + 3 }, { x + 2, top + 3 }, { x + 2, top + 12 }, { x + 11, top + 12 }, { x + 11, top + 8 } }, color, 1.4)
    lineGlyph(button, { { x + 8, top + 2 }, { x + 12, top + 2 }, { x + 12, top + 6 } }, color, 1.4)
    lineGlyph(button, { { x + 12, top + 2 }, { x + 6.5, top + 7.5 } }, color, 1.4)
end

local function createProfile()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(width, T.height)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdropColor(unpack(T.background))
    _G.SoulshardLookupProfile = frame
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    local function dragHandle(x, y, handleWidth, handleHeight, anchorRight)
        local drag = CreateFrame("Frame", nil, frame)
        drag:SetPoint("TOPLEFT", x, -y)
        if anchorRight then drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", anchorRight, -y) else drag:SetWidth(handleWidth) end
        drag:SetHeight(handleHeight)
        drag:EnableMouse(true)
        drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", function() frame:StartMoving() end)
        drag:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            local point, _, relativePoint, left, top = frame:GetPoint()
            if type(ArmoryLookupPreferences) ~= "table" then ArmoryLookupPreferences = {} end
            ArmoryLookupPreferences.point = point
            ArmoryLookupPreferences.relativePoint = relativePoint
            ArmoryLookupPreferences.x = left
            ArmoryLookupPreferences.y = top
        end)
        return drag
    end
    -- The title bar and the identity block move the window; the buttons on the right do not.
    dragHandle(0, 0, 0, T.titleHeight, -40)
    dragHandle(0, T.titleHeight, 520, 110)
    local preferences = ArmoryLookupPreferences
    local points = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    if type(preferences) == "table" and points[preferences.point] and points[preferences.relativePoint] and type(preferences.x) == "number" and type(preferences.y) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint(preferences.point, UIParent, preferences.relativePoint, preferences.x, preferences.y)
    end

    -- Everything that belongs to a character profile (not the search view) lives in `chrome`, so
    -- switching views is one Show/Hide. The hanging tabs are children of it and overhang the bottom edge.
    frame.chrome = CreateFrame("Frame", nil, frame)
    frame.chrome:SetPoint("TOPLEFT")
    frame.chrome:SetSize(width, T.height)
    local chrome = frame.chrome

    -- Title bar: part of the frame, not a floating plate.
    local titleFill = T.Blend(T.titleTint, T.background, 0.05)
    T.Fill(chrome, 0, 0, width, T.titleHeight, titleFill, 1, "BACKGROUND")
    frame.logo = chrome:CreateTexture(nil, "ARTWORK")
    frame.logo:SetSize(18, 18)
    frame.logo:SetPoint("TOPLEFT", 16, -8)
    frame.logo:SetTexture(T.logo)
    frame.brand = T.Text(chrome, 18, T.brand, true)
    frame.brand:SetPoint("LEFT", frame.logo, "RIGHT", 9, 0)
    frame.brand:SetText("Soulshard")

    frame.close = CreateFrame("Button", nil, frame)
    frame.close:SetSize(24, 24)
    frame.close:SetPoint("TOPRIGHT", -10, -5)
    frame.close:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.close.fill = T.Fill(frame.close, 0, 0, 24, 24, { 0.941, 0.843, 0.604 }, 0.10, "BACKGROUND")
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.close:SetScript("OnEnter", function(self) self.fill:SetAlpha(0.2) end)
    frame.close:SetScript("OnLeave", function(self) self.fill:SetAlpha(0.1) end)
    for _, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local stroke = T.Fill(frame.close, 5, 11, 14, 2, { 0.941, 0.843, 0.604 }, 1, "OVERLAY")
        stroke:SetRotation(angle)
    end

    -- Persistent character header.
    frame.identity = CreateFrame("Frame", nil, chrome)
    frame.identity:SetPoint("TOPLEFT")
    frame.identity:SetSize(width, 150)
    local identity = frame.identity
    frame.portrait = T.Disc(identity, "TOPLEFT", 27, -53, 74, T.surface, 1, "BACKGROUND")
    frame.classIcon = identity:CreateTexture(nil, "ARTWORK")
    frame.classIcon:SetSize(56, 56)
    frame.classIcon:SetPoint("TOPLEFT", 36, -62)
    T.Circle(identity, frame.classIcon)
    frame.levelBadge = T.Capsule(identity, 28, 21, T.Hex("17110a"))
    frame.levelBadge:SetPoint("TOPLEFT", 73, -105)
    frame.levelBadge:SetFrameLevel(identity:GetFrameLevel() + 3)
    frame.level = T.Text(frame.levelBadge, 14, T.goldBright, true)
    frame.level:SetPoint("CENTER")
    frame.faction = identity:CreateTexture(nil, "ARTWORK")
    frame.faction:SetPoint("TOPLEFT", 117, -59)
    frame.faction:SetSize(20, 25)
    frame.faction:SetTexCoord(0.1, 0.9, 0, 1)
    frame.heading = T.Text(identity, 30, T.cream, true)
    frame.heading:SetSize(430, 36)
    frame.heading:SetMaxLines(1)
    function frame:SetFaction(faction)
        faction = (faction or ""):lower()
        local known = faction == "alliance" or faction == "horde"
        if known then self.faction:SetTexture("Interface\\AddOns\\SoulshardLookup\\Media\\Factions\\" .. faction .. ".tga") end
        self.faction:SetShown(known)
        self.heading:ClearAllPoints()
        self.heading:SetPoint("TOPLEFT", known and 143 or 117, -53)
    end
    frame.details = T.Text(identity, 16, { 0.925, 0.878, 0.761 })
    frame.details:SetPoint("TOPLEFT", 117, -92)
    frame.details:SetSize(480, 22)
    frame.details:SetMaxLines(1)
    frame.guild = T.Text(identity, 14, T.muted)
    frame.guild:SetPoint("TOPLEFT", 117, -114)
    frame.guild:SetSize(480, 20)
    frame.guild:SetMaxLines(1)

    -- Where the numbers come from, as a capsule: live inspection, saved profile or a warning.
    frame.pill = T.Capsule(identity, 190, 24, T.Blend(T.good, T.background, 0.14))
    frame.pill:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -65)
    frame.pillDot = T.Disc(frame.pill, "LEFT", 9, 0, 8, T.good, 1, "ARTWORK")
    frame.pillText = T.Text(frame.pill, 14, T.goodText)
    frame.pillText:SetPoint("LEFT", 24, 0)
    function frame:SetSource(kind, text)
        local accent = kind == "live" and T.good or kind == "warn" and T.warn or T.dim
        local label = kind == "live" and T.goodText or kind == "warn" and T.bright or T.muted
        self.pill:SetColor(T.Blend(accent, T.background, kind == "saved" and 0.1 or 0.14))
        self.pillDot:SetColorTexture(accent[1], accent[2], accent[3], 1)
        self.pillText:SetTextColor(unpack(label))
        self.pillText:SetText(A.Text(text))
        self.pill:Resize(math.max(110, 24 + T.TextWidth(self.pillText) + 12))
    end

    -- GearScore stays visible on the tabs that do not show it elsewhere. Hovering explains the score.
    frame.scorePanel = CreateFrame("Frame", nil, identity)
    frame.scorePanel:SetSize(170, 24)
    frame.scorePanel:SetPoint("RIGHT", frame.pill, "LEFT", -16, 0)
    frame.scorePanel:EnableMouse(true)
    frame.score = T.Text(frame.scorePanel, 25, T.bright, true)
    frame.score:SetPoint("RIGHT")
    frame.scoreLabel = T.Text(frame.scorePanel, 14, T.muted)
    frame.scoreLabel:SetPoint("RIGHT", frame.score, "LEFT", -9, 0)
    frame.scoreLabel:SetText("GearScore")
    frame.scorePanel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(frame.scoreTitle or "GearScore", 1, 0.85, 0.4)
        GameTooltip:AddLine(A.Text(frame.scoreTooltip or "No saved score available."), 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    frame.scorePanel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.scorePanel:Hide()

    frame.onlineButton = T.Button(identity, "Online Profile", 134, 28, function()
        local target = frame.profileIdentity
        if target then A.ShowLookupURL(target.name, frame.profileRealm or target.realmName) end
    end, "ghost", 15)
    frame.searchButton = T.Button(identity, "New Search", 122, 28, function() A.ShowSearch() end, "tint", 15)
    frame.searchButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -97)
    frame.onlineButton:SetPoint("RIGHT", frame.searchButton, "LEFT", -10, 0)
    for _, button in ipairs({ frame.onlineButton, frame.searchButton }) do
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", 32, 0)
    end
    searchGlyph(frame.searchButton, 11, T.Hex("f3e2b0"), T.Blend(T.gold, T.background, 0.16))
    externalGlyph(frame.onlineButton, 12, { 0.804, 0.749, 0.604 })

    T.Hair(identity, 25, 145, 750, 0.14)

    -- Footer: what the visible tab is showing, and which archive it came from.
    T.Hair(chrome, 25, 677, 750, 0.12)
    frame.status = T.Text(chrome, 13, T.muted)
    frame.status:SetPoint("TOPLEFT", 27, -685)
    frame.status:SetSize(560, 18)
    frame.status:SetMaxLines(1)
    frame.dataset = T.Text(chrome, 13, T.dim)
    frame.dataset:SetPoint("TOPRIGHT", -27, -685)
    frame.dataset:SetJustifyH("RIGHT")
    frame.dataset:SetSize(190, 18)

    frame.regions = {}
    frame.tabs = {}
    frame.order = {}
    local descriptors = { { id = "overview", label = "Overview" } }
    for _, descriptor in ipairs(A.sections) do descriptors[#descriptors + 1] = descriptor end
    for index, descriptor in ipairs(descriptors) do
        local region = CreateFrame("Frame", nil, frame)
        region:SetPoint("TOPLEFT", T.contentX, -T.contentY)
        region:SetSize(T.contentWidth, T.contentHeight)
        region.body = CreateFrame("Frame", nil, region)
        region.body:SetAllPoints()
        region.message = T.Text(region, 16, T.muted, true)
        region.message:SetPoint("CENTER")
        region.message:SetSize(640, 90)
        region.message:SetJustifyH("CENTER")
        frame.regions[descriptor.id] = region
        frame.order[index] = descriptor.id
        local tab = T.Tab(chrome, descriptor.label, T.tabs.x + (index - 1) * T.tabs.pitch, function() frame:SelectSection(descriptor.id) end)
        frame.tabs[descriptor.id] = tab
        tab.sectionIndex = index
    end
    frame.search = A.CreateSearch(frame)
    function frame:Fit()
        local viewWidth = self.view == "search" and T.search.width or width
        local viewHeight = self.view == "search" and T.search.height or T.height + T.tabOverhang
        self:SetSize(viewWidth, self.view == "search" and T.search.height or T.height)
        self:SetScale(math.min(0.8, UIParent:GetWidth() / (viewWidth + 40), UIParent:GetHeight() / (viewHeight + 40)))
    end
    function frame:SetProfileShown(shown)
        self.chrome:SetShown(shown)
        if shown then self.search:Hide() end
    end
    function frame:SetSectionStatus()
        self.status:SetText(A.Text(self.sectionStatuses and self.sectionStatuses[self.selectedSection] or "No saved profile available"))
        self.scorePanel:SetShown(self.view == "profile" and self.hasScore == true and (self.selectedSection == "talents" or self.selectedSection == "raids"))
    end
    function frame:CancelMotion()
        self.motionGeneration = (self.motionGeneration or 0) + 1
        self:SetScript("OnUpdate", nil)
        M.CancelAll()
        self:SetAlpha(1)
        for key, region in pairs(self.regions) do
            local selected = self.view == "profile" and key == self.selectedSection
            region:SetShown(selected)
            sectionInput(region, selected)
            self.tabs[key]:SetSelected(key == self.selectedSection)
        end
        self.scorePanel:EnableMouse(self.view == "profile")
        self:SetSectionStatus()
    end
    function frame:SelectSection(id, immediate)
        if not self.regions[id] or (not immediate and id == self.selectedSection) then return end
        local previous = self.selectedSection
        self:CancelMotion()
        self.selectedSection = id
        for key, tab in pairs(self.tabs) do tab:SetSelected(key == id) end
        local region = self.regions[id]
        region:SetHeight(T.contentHeight)
        self:Fit()
        GameTooltip:Hide()
        if immediate or not previous or not M.Enabled() then
            for key, candidate in pairs(self.regions) do
                candidate:SetShown(key == id)
                sectionInput(candidate, key == id)
            end
            self:SetSectionStatus()
            return
        end
        local outgoing = self.regions[previous]
        local direction = self.tabs[id].sectionIndex > self.tabs[previous].sectionIndex and 1 or -1
        local generation = self.motionGeneration
        sectionInput(outgoing, false)
        sectionInput(region, false)
        self:SetSectionStatus()
        M.Play(outgoing, { fromAlpha = 1, toAlpha = 0, toX = -direction * 12, duration = M.timing.exit, smoothing = "IN", finish = function()
            if self.motionGeneration ~= generation then return end
            outgoing:Hide()
            outgoing:SetAlpha(1)
            region:Show()
            local message = region.message:IsShown() or (region.body.message and region.body.message:IsShown())
            M.Play(region, { fromX = message and 0 or direction * 24, duration = message and M.timing.message or M.timing.enter, finish = function()
                if self.motionGeneration == generation then sectionInput(region, true) end
            end })
        end })
    end
    function frame:RevealProfile(opening)
        if opening then M.Reveal(self, 0, M.timing.window, 0) end
        M.Reveal(self.identity, 0, M.timing.identity, 6)
        self.scorePanel:EnableMouse(false)
        M.Reveal(self.scorePanel, M.timing.scoreDelay, M.timing.score, 6, function() self.scorePanel:EnableMouse(true) end)
        revealSection(self.regions[self.selectedSection])
    end
    function frame:QueueProfileReveal(opening)
        if not M.Enabled() then self:RevealProfile(opening); return end
        -- Let native anchors and inherited scale settle before translations start.
        self:SetAlpha(0)
        self.scorePanel:EnableMouse(false)
        sectionInput(self.regions[self.selectedSection], false)
        local generation = self.motionGeneration
        self:SetScript("OnUpdate", function()
            if self.motionGeneration ~= generation or not self:IsShown() or self.view ~= "profile" then return end
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            self:RevealProfile(opening)
        end)
    end
    frame:SetScript("OnHide", function() frame:CancelMotion(); GameTooltip:Hide(); frame.search.input:ClearFocus() end)
    frame:Hide()
    table.insert(UISpecialFrames, "SoulshardLookupProfile")
    A.profile = frame
    return frame
end

-- "Level 70 Gnome Warlock · Destruction" with the specialization picked out in gold. Saved text is
-- escaped before the colour codes are added, so only this function's own codes survive.
local function detailsLine(summary, spec)
    local dot = T.Wrap(T.faint, "  ·  ")
    local line = "Level " .. A.Text(summary.level) .. " " .. A.Text(summary.race) .. " " .. A.Text(A.ClassName(summary.classToken))
    if spec and spec.name then line = line .. dot .. T.Wrap(T.goldBright, A.Text(spec.name)) end
    return line
end

function A.ShowProfile(identity, live, refresh)
    if InCombatLockdown() and not (refresh and A.profile and A.profile:IsShown() and A.profile.view == "profile") then
        A.Print("Profile lookup is unavailable during combat."); return
    end
    if A.GetPlayerContext then live = A.GetPlayerContext(identity, live and live.unit, 1) end
    local frame = A.profile or createProfile()
    local saved = A.FindCharacter(identity)
    local character = live and { identity = { name = identity.name, realmName = live.realm }, summary = live.summary } or saved
    local function sectionFor(descriptor)
        if live and descriptor.id ~= "raids" then
            return live.sections[descriptor.id] or { state = "unavailable", source = "live", reason = "inspection_pending" }
        end
        return (saved and A.GetSection(saved, descriptor)) or { state = "unavailable" }
    end
    local profileKey = live and live.guid or identity.key and (tostring(identity.dataset or "") .. "#" .. tostring(identity.key)) or ((identity.realmKey or "") .. "/" .. identity.name)
    if not refresh and frame:IsShown() and frame.view == "profile" and frame.profileKey == profileKey and frame.liveSnapshot == live then return end
    local opening = not frame:IsShown()
    frame:CancelMotion()
    frame.view = "profile"
    frame:Fit()
    frame.profileKey = profileKey
    frame.liveSnapshot = live
    frame.profileIdentity = identity
    frame.profileRealm = live and live.realm or saved and saved.identity.realmName or identity.realmName
    frame.sectionStatuses = {}
    frame:SetProfileShown(true)
    frame:Show()
    if not character then
        frame:SetFaction(nil)
        frame.heading:SetText(A.Text(identity.name))
        frame.heading:SetTextColor(unpack(T.cream))
        frame.details:SetText("No entry in this archive")
        frame.guild:SetText("")
        frame.levelBadge:Hide()
        T.ClassIcon(frame.classIcon, "")
        frame.portrait:SetColorTexture(T.surface[1], T.surface[2], T.surface[3], 1)
        frame.hasScore = false
        frame.score:SetText("—")
        frame.scoreTitle = "GearScore"
        frame.scoreTooltip = nil
        frame:SetSource("saved", "Not in archive")
        frame.dataset:SetText("SAVED PROFILES ONLY")
        for _, region in pairs(frame.regions) do
            region.body:Hide()
            region.message:SetText("This character is not in your saved archive.\nInstall a newer exported Soulshard Lookup release while WoW is closed.")
            region.message:Show()
        end
        frame:SelectSection("overview", true)
        frame:QueueProfileReveal(opening)
        return
    end
    local summary = character.summary
    local sections = {}
    for _, descriptor in ipairs(A.sections) do sections[descriptor.id] = sectionFor(descriptor) end
    local equipment, talents, raids = sections.equipment, sections.talents, sections.raids
    local spec = A.DetectSpec(talents, summary.classToken)
    local score = equipment.data and equipment.data.gearScore
    local classColor = T.ClassColor(summary.classToken)
    T.ClassIcon(frame.classIcon, summary.classToken)
    frame.portrait:SetColorTexture(unpack(T.Blend(classColor, T.surface, 0.3)))
    frame:SetFaction(summary.faction)
    frame.heading:SetText(A.Text(character.identity.name))
    frame.heading:SetTextColor(unpack(classColor))
    frame.levelBadge:Show()
    frame.level:SetText(tostring(summary.level))
    frame.levelBadge:Resize(math.max(26, T.TextWidth(frame.level) + 12))
    frame.details:SetText(detailsLine(summary, spec))
    frame.guild:SetText(A.Text(character.identity.realmName) .. T.Wrap(T.faint, "  ·  ") .. A.Text(summary.guild and ("<" .. summary.guild .. ">") or "No guild"))
    frame.hasScore = score ~= nil
    frame.score:SetText(score and tostring(score.value) or "—")
    frame.scoreTitle = (equipment.source == "live" or (live and not equipment.data)) and "Live GearScore" or "Saved GearScore"
    frame.scoreTooltip = score and (score.algorithm .. "\n" .. T.SectionStatus(equipment)) or "Equipment is unavailable or incomplete. Missing scores are never shown as zero."
    if live and equipment.source == "live" and equipment.data then
        frame:SetSource(equipment.state == "partial" and "warn" or "live", equipment.state == "partial" and "Live inspection · partial" or ("Live inspection · " .. (equipment.fetchedAt and T.Ago(equipment.fetchedAt) or "just now")))
    elseif live then
        frame:SetSource("warn", "Inspection pending")
    else
        frame:SetSource("saved", "Saved profile" .. (equipment.fetchedAt and (" · " .. T.Ago(equipment.fetchedAt)) or ""))
    end
    frame.dataset:SetText(A.Text(saved and "Archive " .. A.data.datasetVersion:sub(-12) or "Nearby player"))
    local liveNote = live and live.message and (" · " .. live.message) or ""
    local equipmentStatus = T.SectionStatus(equipment)
    frame.sectionStatuses.overview = "Overview  ·  " .. equipmentStatus .. liveNote
    for _, descriptor in ipairs(A.sections) do
        local section = sections[descriptor.id]
        local region = frame.regions[descriptor.id]
        frame.sectionStatuses[descriptor.id] = descriptor.label .. "  ·  " .. T.SectionStatus(section)
        if live and live.message and descriptor.id ~= "raids" then
            frame.sectionStatuses[descriptor.id] = frame.sectionStatuses[descriptor.id] .. " · " .. live.message
        end
        region.body:Show()
        descriptor.render(region.body, section, character, { spec = spec })
        region.message:SetShown(not section.data and not descriptor.renderUnavailable)
        if not section.data then region.message:SetText("No compatible " .. descriptor.label:lower() .. " saved in this archive.\nThe other profile sections remain available.") end
        if live and not section.data and descriptor.id ~= "raids" then region.message:SetText(live.message or "This player's " .. descriptor.label:lower() .. " could not be inspected.") end
    end
    if raids.data and raids.fetchedAt then
        frame.sectionStatuses.raids = "Raids  ·  Warcraft Logs  ·  historical, saved " .. T.Ago(raids.fetchedAt)
    end
    local overview = frame.regions.overview
    overview.body:Show()
    overview.message:Hide()
    A.RenderOverview(overview.body, {
        character = character,
        live = live,
        spec = spec,
        equipment = equipment,
        talents = talents,
        raids = raids,
        open = function(id, raidIndex)
            local raidBody = frame.regions.raids.body
            if raidIndex and raidBody.SelectRaid then raidBody:SelectRaid(raidIndex) end
            frame:SelectSection(id)
        end,
    })
    frame:SelectSection(frame.selectedSection or "overview", true)
    if not refresh then frame:QueueProfileReveal(opening) end
end

function A.ShowSearch(query)
    if InCombatLockdown() then A.Print("New search is unavailable during combat."); return end
    local frame = A.profile or createProfile()
    local opening = not frame:IsShown()
    frame:CancelMotion()
    frame.view = "search"
    frame.liveSnapshot = nil
    frame:Show()
    frame:SetProfileShown(false)
    for _, region in pairs(frame.regions) do region:Hide() end
    frame:Fit()
    GameTooltip:Hide()
    frame.search:Open(query)
    if opening then M.Reveal(frame, 0, M.timing.window, 0) end
    M.Reveal(frame.search, 0, M.timing.window, 8)
    return true
end
