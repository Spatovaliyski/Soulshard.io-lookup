local _, A = ...
local T = A.Theme
local resultLimit = A.searchLimit
local layout = T.search

local function liveFor(character, priority)
    local identity = A.ResolveName(character.identity.name, character.identity.realmName)
    if identity and A.SameCharacter(A.FindCharacter(identity), character) and A.GetPlayerContext then
        return A.GetPlayerContext(identity, nil, priority)
    end
end

local function showLiveStatus(row, live)
    if not live then
        if GameTooltip:GetOwner() == row then GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(live.refreshing and "Nearby inspection · Refreshing" or "Nearby inspection", 1, 0.85, 0.4)
    GameTooltip:AddLine(A.Text(live.message or A.SectionLabel(live.sections.equipment)), 1, 1, 1, true)
    GameTooltip:Show()
end

function A.CreateSearch(parent)
    local search = CreateFrame("Frame", nil, parent)
    search:SetAllPoints()
    search.brand = CreateFrame("Frame", nil, search)
    search.brand:SetSize(300, 36)
    search.brand:SetPoint("TOP", 0, -20)
    search.logo = search.brand:CreateTexture(nil, "ARTWORK")
    search.logo:SetSize(36, 36)
    search.logo:SetPoint("LEFT")
    search.logo:SetTexture(T.logo)
    search.title = T.Text(search.brand, 28, T.brand, true)
    search.title:SetPoint("LEFT", 44, 0)
    search.title:SetText("Soulshard Lookup")
    search.intro = T.Text(search, 16, T.cream)
    search.intro:SetPoint("TOP", 0, -62)
    search.intro:SetText("Find a character")
    search.context = T.Text(search, 13, T.muted)
    search.context:SetPoint("TOP", 0, -88)
    search.context:SetWidth(layout.cardWidth)
    search.context:SetJustifyH("CENTER")
    search.card = T.Panel(search, layout.cardWidth, layout.cardHeight)
    search.card:SetPoint("TOP", 0, -164)
    local label = T.Text(search.card, 13, T.muted)
    label:SetPoint("TOPLEFT", 16, -12)
    label:SetText("CHARACTER NAME")
    search.input = CreateFrame("EditBox", nil, search.card, "BackdropTemplate")
    search.input:SetPoint("TOPLEFT", 16, -34)
    search.input:SetSize(layout.inputWidth, 40)
    search.input:SetAutoFocus(false)
    search.input:SetMaxLetters(160)
    search.input:SetTextInsets(12, 12, 0, 0)
    search.input:SetFont(T.bodyFont, 15, "")
    search.input:SetTextColor(unpack(T.cream))
    search.input:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    search.input:SetBackdropColor(unpack(T.input))
    search.input:SetBackdropBorderColor(unpack(T.line))
    search.placeholder = T.Text(search.input, 14, T.muted)
    search.placeholder:SetPoint("LEFT", 12, 0)
    search.placeholder:SetText("Enter a name...")
    search.submit = T.Button(search.card, "Load character", layout.buttonWidth, 40, function() search:Submit() end, "primary")
    search.submit:SetPoint("TOPRIGHT", -16, -34)
    search.message = T.Text(search, 13, T.muted)
    search.message:SetPoint("BOTTOM", 0, 12)
    search.message:SetSize(layout.cardWidth, 36)
    search.message:SetJustifyH("CENTER")
    search.dropdown = T.Panel(search.card, layout.inputWidth, 1, true)
    search.dropdown:SetPoint("TOPLEFT", search.input, "BOTTOMLEFT", 0, -6)
    search.dropdown:SetFrameLevel(search.card:GetFrameLevel() + 10)
    search.dropdown:Hide()
    search.viewport = CreateFrame("ScrollFrame", nil, search.dropdown)
    search.viewport:SetPoint("TOPLEFT", 8, -7)
    search.viewport:SetSize(layout.inputWidth - 16, layout.visibleRows * layout.rowPitch)
    search.viewport:EnableMouseWheel(true)
    search.results = CreateFrame("Frame", nil, search.viewport)
    search.results:SetSize(layout.inputWidth - 16, resultLimit * layout.rowPitch)
    search.viewport:SetScrollChild(search.results)
    search.rows = {}
    for index = 1, resultLimit do
        local row = T.Button(search.results, "", layout.inputWidth - 16, 44, function() search:OpenResult(index) end)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * layout.rowPitch)
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", 12, -5)
        row.label:SetWidth(220)
        row.label:SetMaxLines(1)
        row.details = T.Text(row, 13, T.muted)
        row.details:SetPoint("TOPLEFT", 12, -23)
        row.details:SetWidth(220)
        row.details:SetMaxLines(1)
        row.score = T.Text(row, 16, T.gold)
        row.score:SetPoint("RIGHT", -12, 0)
        row:HookScript("OnEnter", function()
            local character = search.matches and search.matches[index]
            if not character then return end
            showLiveStatus(row, liveFor(character, 2))
        end)
        row:HookScript("OnLeave", function() if GameTooltip:GetOwner() == row then GameTooltip:Hide() end end)
        search.rows[index] = row
    end

    function search:ScrollTo(first)
        local count = math.min(#self.matches, resultLimit)
        self.firstVisible = math.max(1, math.min(math.max(1, count - layout.visibleRows + 1), first))
        self.viewport:SetVerticalScroll((self.firstVisible - 1) * layout.rowPitch)
    end

    function search:Select(index)
        local count = math.min(#self.matches, resultLimit)
        self.selected = count > 0 and math.max(1, math.min(count, index)) or nil
        if self.selected then
            local first = self.firstVisible or 1
            if self.selected < first then first = self.selected
            elseif self.selected >= first + layout.visibleRows then first = self.selected - layout.visibleRows + 1 end
            self:ScrollTo(first)
        end
        for rowIndex, row in ipairs(self.rows) do row:SetSelected(rowIndex == self.selected) end
    end

    function search:RefreshScores(priority)
        for index, row in ipairs(self.rows) do
            local character = self.matches and self.matches[index]
            if character then
                local live = liveFor(character, priority)
                if live and not priority and row.liveGuid ~= live.guid then live = liveFor(character, 4) end
                local equipment
                if live then equipment = live.sections.equipment
                else equipment = A.GetSectionSummary(character, A.sections[1]) end
                local score = equipment and equipment.data and equipment.data.gearScore
                row.liveGuid = live and live.guid
                row.score:SetText(score and tostring(score.value) .. " GS" .. (live and live.refreshing and "*" or "") or (live and "Live …" or "—"))
                if GameTooltip:GetOwner() == row then showLiveStatus(row, live) end
            else
                row.liveGuid = nil
            end
        end
    end

    function search:Refresh()
        local query = self.input:GetText()
        local matches, realm, reason, total = A.SearchCharacters(query)
        local resultCount = math.min(#matches, resultLimit)
        local visibleCount = math.min(resultCount, layout.visibleRows)
        local region = A.Region() == "eu" and "Europe" or (A.Region() == "us" and "Americas" or "Unknown region")
        self.matches = matches
        self.total = total or #matches
        self:ScrollTo(1)
        self.context:SetText(A.Text(region .. "  ·  " .. realm .. "  ·  Saved directory · Nearby scores are live"))
        self.placeholder:SetShown(query == "")
        for index, row in ipairs(self.rows) do
            local character = matches[index]
            row:SetShown(character ~= nil)
            if character then
                row.label:SetText(A.Text(character.identity.name))
                row.details:SetText(A.Text("Level " .. character.summary.level .. " " .. character.summary.race .. " " .. character.summary.classToken))
            end
        end
        self:RefreshScores(4)
        self:Select(1)
        self.results:SetHeight(resultCount * layout.rowPitch)
        self.viewport:SetHeight(visibleCount * layout.rowPitch)
        self.dropdown:SetHeight(14 + visibleCount * layout.rowPitch)
        self.dropdown:SetShown(visibleCount > 0)
        parent:Fit()
        if reason then self.message:SetText(reason)
        elseif query:match("^%s*$") then self.message:SetText("Your current realm is selected automatically.\nSearch saved profiles as you type, or enter Name-Realm.")
        elseif #matches == 0 then self.message:SetText("No saved characters match this name on this realm.\nTry another name, Name-Realm, or install a newer export.")
        else self.message:SetText((self.total > resultLimit and "Showing " .. resultLimit .. " of " .. self.total .. " matches. Refine your search.\n" or "") .. (resultCount > layout.visibleRows and "Scroll or use Up/Down and Enter to choose a character." or "Use Up/Down and Enter, or click a character.")) end
    end

    function search:OpenResult(index)
        local character = self.matches[index]
        if not character then return end
        local identity = A.ResolveName(character.identity.name, character.identity.realmName)
        if not identity or not A.SameCharacter(A.FindCharacter(identity), character) then
            self:Refresh()
            return
        end
        self.input:ClearFocus()
        A.ShowProfile(identity)
    end

    function search:Submit()
        if self.selected then self:OpenResult(self.selected) end
    end

    function search:Open(query)
        self:Show()
        self.input:SetText(query or "")
        self:Refresh()
        self.input:SetFocus()
    end

    search.input:SetScript("OnTextChanged", function() search:Refresh() end)
    search.input:SetScript("OnEnterPressed", function() search:Submit() end)
    search.input:SetScript("OnEscapePressed", function()
        if search.dropdown:IsShown() then search.dropdown:Hide()
        else parent:Hide() end
    end)
    search.input:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" or key == "DOWN" then
            search:RefreshScores(4)
            search.dropdown:SetShown(#search.matches > 0)
            search:Select((search.selected or 0) + (key == "DOWN" and 1 or -1))
        end
    end)
    search.viewport:SetScript("OnMouseWheel", function(_, delta) search:ScrollTo((search.firstVisible or 1) - delta) end)
    search.input:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(unpack(T.gold))
        search:RefreshScores(4)
        search.dropdown:SetShown(search.matches and #search.matches > 0)
    end)
    search.input:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(T.line))
        if not MouseIsOver(search.dropdown) then search.dropdown:Hide() end
    end)
    search:SetScript("OnHide", function() search.dropdown:Hide(); search.input:ClearFocus() end)
    search:Hide()
    return search
end

function A.RefreshLiveSearch(guid, priority)
    local frame = A.profile
    if frame and frame:IsShown() and frame.view == "search" and frame.search:IsShown() and frame.search.dropdown:IsShown() then
        frame.search:RefreshScores(priority)
    end
end
