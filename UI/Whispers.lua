local _, A = ...
local T, W, P = A.Theme, A.Whispers, A.WhisperProfiles
local U = {}
A.WhisperUI = U

-- Layout. Everything below is in UI units; the window scales down (never up) to fit the screen.
local width, gutter, pageTop = 540, 20, 160
local inner = width - gutter * 2
local visibleRows, rowHeight, trackWidth = 7, 56, 8
local rowWidth = inner - trackWidth - 6
-- Roster page rhythm, top to bottom: the class chips, the list header, the list box, then the footer (Clear
-- roster and Bulk Search, with a hint line under them). The player and whisper count sits in the status strip.
local chipsTop, headerTop = 4, 60
local listTop, listHeight = 96, visibleRows * rowHeight + 2
local footerTop = listTop + listHeight + 10
local rosterHeight, settingsHeight = footerTop + 32 + 12 + 20, 598
local bottomPad = 14
-- Each tab sizes the window to its own page.
local windowHeights = { roster = pageTop + rosterHeight + bottomPad, settings = pageTop + settingsHeight + bottomPad }
local height = math.max(windowHeights.roster, windowHeights.settings)
-- Status strip: the reason on the left, the count right-aligned behind a hairline on the roster.
local countWidth = 84
-- Row portrait: a class-coloured ring around a circular portrait, a class badge at the lower right and a level badge at the lower left.
local ringX, ringSize, portraitSize, badgeSize, textX = 46, 46, 42, 22, 110
-- Navigation row (the tabs, plus the raid-parse picker on the roster) sits under the status strip.
local navTop, navHeight, tabWidth, tabGap = 114, 32, 112, 6
local tabPitch = tabWidth + tabGap
local classes = { "ALL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "UNKNOWN" }
local classNames = { ALL = "All classes", UNKNOWN = "Unknown" }
local modes = { "any", "keywords", "prefix" }
local modeNames = { any = "Any whisper", keywords = "Keywords", prefix = "Prefix" }
local modeHelp = {
    any = "Every whisper from a character is collected.",
    keywords = "Whispers containing any keyword are collected.",
    prefix = "Whispers starting with this text are collected.",
}
local sorts = { "recent", "name", "score" }
local sortNames = { recent = "Recent", name = "Name" }
local edge = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

local M = A.Motion
-- Type in this window runs one point larger than the shared defaults.
local TEXT_BUMP = 1

local initialized, native, frame, pending, manuallyClosed = false, nil, nil, false, false
local classFilter, contextID, offset, sortKey, currentTab = "ALL", nil, 0, "recent", "roster"
local views, anchorIndex, anchorState, syncing = {}, nil, false, false
local refreshRoster, selectTab, showCopy, showConfirm, closeOverlays

local function fitHeight(tab)
    if frame then frame:SetHeight(windowHeights[tab] or height) end
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function className(token)
    return classNames[token] or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or
        (token:sub(1, 1) .. token:sub(2):lower())
end

local function value(number)
    return number ~= nil and tostring(math.floor(number + 0.5)) or "—"
end

local function plural(count, singular, many)
    return count .. " " .. (count == 1 and singular or (many or singular .. "s"))
end

local function hex(color)
    return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255 + .5), math.floor(color[2] * 255 + .5), math.floor(color[3] * 255 + .5))
end
local mutedHex, dangerHex = hex(T.muted), hex(T.danger)

local function ago(timestamp)
    if type(timestamp) ~= "number" then return "?" end
    local age = math.max(0, time() - timestamp)
    if age < 15 then return "now" end
    if age < 60 then return math.floor(age) .. "s" end
    if age < 3600 then return math.floor(age / 60) .. "m" end
    if age < 86400 then return math.floor(age / 3600) .. "h" end
    return math.floor(age / 86400) .. "d"
end

local function sameRealm(realm)
    if type(GetRealmName) ~= "function" then return false end
    local ok, own = pcall(GetRealmName)
    if not ok or type(own) ~= "string" then return false end
    local function normal(text) return (text:lower():gsub("[%s%-']", "")) end
    return normal(own) == normal(realm)
end

local function displayName(identity)
    if identity.displayName then return identity.displayName end
    return (identity.name or "Unresolved player") .. (identity.realmName and ("-" .. identity.realmName) or "")
end

local function classColor(token)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token or ""]
    if color then return { color.r, color.g, color.b } end
    return T.cream
end

local function fill(parent, x, y, w, h, color, alpha, layer)
    return T.Fill(parent, x, y, w, h, color, alpha, layer)
end

-- The shared text and button builders with this window's one-point type bump applied.
local function Label(parent, size, color, serif)
    return T.Text(parent, size + TEXT_BUMP, color, serif)
end

local function Button(parent, title, w, h, onClick, variant)
    return T.Button(parent, title, w, h, onClick, variant, (variant == "primary" and 15 or 14) + TEXT_BUMP)
end

-- Text region anchored at the top-left of its parent.
local function text(parent, size, color, x, y, w, h, justify, serif)
    local region = Label(parent, size, color, serif)
    region:SetPoint("TOPLEFT", x, -y)
    if w then
        region:SetSize(w, h or size + 8)
        region:SetMaxLines(1)
    end
    if justify then region:SetJustifyH(justify) end
    return region
end

local function input(parent, x, y, inputWidth, hint)
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    edit:SetSize(inputWidth, 32)
    edit:SetPoint("TOPLEFT", x, -y)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(1400)
    edit:SetFont(T.bodyFont, 14 + TEXT_BUMP, "")
    edit:SetTextColor(unpack(T.cream))
    edit:SetTextInsets(10, 10, 0, 0)
    edit:SetBackdrop(edge)
    edit:SetBackdropColor(unpack(T.input))
    edit:SetBackdropBorderColor(unpack(T.line))
    edit.placeholder = Label(edit, 13, T.muted)
    edit.placeholder:SetPoint("LEFT", 10, 0)
    edit.placeholder:SetText(hint or "")
    edit:SetScript("OnTextChanged", function(self, user)
        self.placeholder:SetShown(self:GetText() == "")
        if self.changed then self.changed(self, user) end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(T.gold)) end)
    edit:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(T.line)) end)
    return edit
end

-- A drawn check box (no font glyphs): "off", "on" or "partial".
local function checkbox(parent)
    local box = T.Panel(parent, 18, 18, true)
    box.short = fill(box, 2.75, 10.75, 5, 2, T.gold, 1, "OVERLAY")
    box.short:SetRotation(-math.pi / 4)
    box.long = fill(box, 5.5, 9, 10, 2, T.gold, 1, "OVERLAY")
    box.long:SetRotation(math.pi / 4)
    box.dash = fill(box, 4, 8, 10, 2, T.gold, 1, "OVERLAY")
    function box:SetState(state)
        self.short:SetShown(state == "on")
        self.long:SetShown(state == "on")
        self.dash:SetShown(state == "partial")
        self:SetBackdropBorderColor(unpack(state == "off" and T.line or T.gold))
        self:SetBackdropColor(unpack(state == "off" and T.input or { 0.145, 0.118, 0.090 }))
    end
    box:SetState("off")
    return box
end

local function caret(parent, color)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(12, 8)
    holder:SetPoint("RIGHT", -10, 0)
    local left = fill(holder, 0, 2.5, 7, 2, color, 1, "OVERLAY")
    left:SetRotation(-math.pi / 4)
    local right = fill(holder, 5, 2.5, 7, 2, color, 1, "OVERLAY")
    right:SetRotation(math.pi / 4)
    return holder
end

-- Text-only button with a gold underline when active (tabs and sort keys).
local function flat(parent, title, w, h, size, onClick, serif)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(w, h)
    button.label = Label(button, size, T.muted, serif)
    button.label:SetPoint("CENTER")
    button.label:SetJustifyH("CENTER")
    button.label:SetText(title)
    button.line = fill(button, 0, h - 2, w, 2, T.gold, 1, "ARTWORK")
    button.line:Hide()
    function button:Paint()
        self.label:SetTextColor(unpack(self.active and T.gold or (self.hovered and T.cream or T.muted)))
    end
    function button:SetActive(active)
        self.active = active
        self.line:SetShown(active)
        self:Paint()
    end
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self) self.hovered = true; self:Paint() end)
    button:SetScript("OnLeave", function(self) self.hovered = false; self:Paint() end)
    return button
end

-- Row with a check box, a title and a one-line description.
local function option(parent, x, y, w, title, description, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(w, description and 40 or 26)
    row:SetPoint("TOPLEFT", x, -y)
    row.box = checkbox(row)
    row.box:SetPoint("TOPLEFT", 0, -1)
    row.title = text(row, 14, T.cream, 30, 0, w - 30, 22)
    row.title:SetText(title)
    if description then
        row.description = text(row, 13, T.muted, 30, 21, w - 30, 18)
        row.description:SetText(description)
    end
    function row:SetChecked(checked)
        self.checked = checked
        self.box:SetState(checked and "on" or "off")
    end
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", function(self) self.title:SetTextColor(unpack(T.gold)) end)
    row:SetScript("OnLeave", function(self) self.title:SetTextColor(unpack(T.cream)) end)
    return row
end

local function card(parent, y, h, title)
    local panel = T.Panel(parent, inner, h)
    panel:SetPoint("TOPLEFT", 0, -y)
    local heading = text(panel, 13, T.gold, 16, 10, inner - 32, 20)
    heading:SetText(title)
    T.Rule(panel, 1, 36, inner - 2)
    return panel
end

---------------------------------------------------------------------------
-- Motion
---------------------------------------------------------------------------

-- The window borrows the profile page's vocabulary: staged fades with a short rise, a light sweep along the
-- title rule, a sliding tab underline and a slide between pages. `animated` is the single gate for all of it,
-- so /sl motion off and the "Animate window" setting both fall back to plain, immediate changes.
local tracked = {}
local cancelMotion, placeTabLine

local function animated()
    return M.Enabled() and W.GetSettings().animate ~= false
end

-- Every region this window animates is recorded so one call can put them all back at rest.
local function settle()
    for region in pairs(tracked) do M.Stop(region) end
    tracked = {}
end

local function play(region, options)
    tracked[region] = true
    if animated() then M.Play(region, options); return end
    M.Stop(region)
    region:SetAlpha(options.toAlpha or 1)
    if options.finish then options.finish() end
end

local function reveal(region, delay, duration, rise, finish)
    play(region, { delay = delay, duration = duration, fromY = -(rise or 0), finish = finish })
end

-- Eases a texture's alpha to `target`. It jumps there when motion is off or the row now shows someone else.
local function ease(texture, target, instant)
    tracked[texture] = true
    local from = M.Alpha(texture)
    if instant or not animated() or not frame or not frame:IsShown() or math.abs(from - target) < .01 then
        M.Stop(texture)
        texture:SetAlpha(target)
        return
    end
    M.Play(texture, { fromAlpha = from, toAlpha = target, duration = M.timing.hover, restAlpha = target })
end

-- Rows fade up in a short cascade after the list itself changes (class chip, sort, raid context).
local function revealRows()
    if not frame or not animated() then return end
    for index, row in ipairs(frame.rows) do
        if row:IsShown() then reveal(row, (index - 1) * M.timing.rowStagger, M.timing.row, 6) end
    end
    if frame.empty:IsShown() then reveal(frame.empty, 0, M.timing.row, 6) end
end

local function revealRoster()
    local timing = M.timing
    local base = timing.rowDelay
    reveal(frame.count, base - .04, timing.row, 8)
    reveal(frame.chipStrip, base - .02, timing.row, 8)
    reveal(frame.listHeader, base, timing.row, 8)
    for index, row in ipairs(frame.rows) do
        if row:IsShown() then reveal(row, base + .02 + (index - 1) * timing.rowStagger, timing.row, 8) end
    end
    if frame.empty:IsShown() then reveal(frame.empty, base + .02, timing.row, 8) end
    reveal(frame.footer, base + .14, timing.row, 6)
end

local function revealSettings()
    local timing = M.timing
    for index, panel in ipairs(frame.settings.cards) do
        reveal(panel, timing.treeDelay + (index - 1) * timing.treeStagger, timing.tree, 8)
    end
end

local function revealWindow()
    local timing = M.timing
    reveal(frame, 0, timing.window, 0)
    reveal(frame.head, 0, timing.identity, 6)
    reveal(frame.statusStrip, timing.scoreDelay, timing.score, 6)
    reveal(frame.nav, timing.summaryDelay, timing.summary, 6)
    if currentTab == "roster" then revealRoster() else revealSettings() end
    if animated() then
        frame.sweep:Show()
        play(frame.sweep, { fromAlpha = 1, toAlpha = 0, toX = width - 2 - 72, duration = timing.sweep, finish = function() frame.sweep:Hide() end })
    end
end

-- The window starts invisible and begins its entrance one frame later, so anchors and scale have settled
-- before anything translates.
local function openMotion()
    if not animated() then return end
    frame:SetAlpha(0)
    local generation = frame.motionGeneration
    frame:SetScript("OnUpdate", function(self)
        if self.motionGeneration ~= generation or not self:IsShown() then return end
        self:SetScript("OnUpdate", nil)
        revealWindow()
    end)
end

function placeTabLine()
    local line = frame.tabLine
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", (currentTab == "settings" and 1 or 0) * tabPitch, -(navHeight - 3))
end

-- Stops every running motion and puts the window in the state its current tab implies.
function cancelMotion()
    if not frame then return end
    frame.motionGeneration = (frame.motionGeneration or 0) + 1
    frame:SetScript("OnUpdate", nil)
    settle()
    frame:SetAlpha(1)
    frame.sweep:Hide()
    frame.roster:SetShown(currentTab == "roster")
    frame.settings:SetShown(currentTab == "settings")
    frame.contextButton:SetShown(currentTab == "roster")
    fitHeight(currentTab)
    placeTabLine()
end

---------------------------------------------------------------------------
-- Status copy
---------------------------------------------------------------------------

local statusCopy = {
    recording = { "good", "Recording", "Collecting whispers while your group is listed." },
    ["not-grouped"] = { "warn", "Paused", "Join or start a raid" },
    ["not-leader-or-assistant"] = { "warn", "Paused", "Only the leader or an assistant can collect." },
    ["not-listed"] = { "warn", "Paused", "List your group in Looking For Group to collect." },
    disabled = { "off", "Off", "Collection is switched off in Settings." },
    ["unsupported-client"] = { "bad", "Unavailable", "Requires the TBC Anniversary client (20506)." },
    ["storage-incompatible"] = { "bad", "Unavailable", "Saved data needs a newer version of the addon." },
}
local tones = { good = T.good, warn = T.gold, bad = T.danger, off = T.muted }
-- The empty roster explains what a paused state still needs in one paragraph; the status strip keeps the short reason.
local pausedCopy = {
    ["not-grouped"] = "Collection starts once you are in a party or raid that you lead or assist, with the group listed in Looking For Group.",
    ["not-leader-or-assistant"] = "Only the party leader or a raid assistant can collect whispers. Ask for assist or lead the group yourself, and keep it listed in Looking For Group.",
    ["not-listed"] = "Your group is not listed yet. List it in Looking For Group and the players who whisper you will appear here.",
}

local function describe(status)
    local entry = statusCopy[status.state]
    if entry then return entry[1], entry[2], entry[3] end
    local title, rest = (status.label or ""):match("^(.-)%s+—%s+(.+)$")
    if title then return "warn", title, rest:sub(1, 1):upper() .. rest:sub(2) .. "." end
    return "warn", "Paused", status.label or "Waiting for the client."
end

---------------------------------------------------------------------------
-- Window chrome
---------------------------------------------------------------------------

local function anchor()
    if not frame then return end
    local scale = math.min(.8, (UIParent:GetWidth() - 24) / width, (UIParent:GetHeight() - 24) / height)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    if not native then frame:SetPoint("CENTER", UIParent, "CENTER"); return end
    local right = native.GetRight and native:GetRight()
    local nativeScale = native.GetEffectiveScale and native:GetEffectiveScale() or 1
    local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local fitsRight = not right or right * nativeScale / parentScale + width * scale + 12 <= UIParent:GetWidth()
    if fitsRight then frame:SetPoint("TOPLEFT", native, "TOPRIGHT", 12, 0)
    else frame:SetPoint("TOPRIGHT", native, "TOPLEFT", -12, 0) end
end

-- A menu and its click-away catcher always change together.
local function hideMenus()
    if not frame then return end
    for _, name in ipairs({ "contextMenu", "rowMenu" }) do
        local menu = frame[name]
        if menu then
            M.Stop(menu)
            menu:Hide()
            menu.catcher:Hide()
        end
    end
end

local function setMenu(shown)
    if not frame or not frame.contextMenu then return end
    if shown then hideMenus() end
    frame.contextMenu:SetShown(shown)
    frame.contextMenu.catcher:SetShown(shown)
    if shown then reveal(frame.contextMenu, 0, M.timing.message, 6) end
end

function closeOverlays(except)
    if not frame then return end
    for _, name in ipairs({ "copy", "confirm" }) do
        local overlay = frame[name]
        if name ~= except and overlay then M.Stop(overlay); overlay:Hide() end
    end
    hideMenus()
    frame.scrim:SetShown(except ~= nil)
end

function U.HandleEscape()
    if not frame then return false end
    for _, name in ipairs({ "copy", "confirm" }) do
        local overlay = frame[name]
        if overlay and overlay:IsShown() then overlay:Hide(); return true end
    end
    if frame.contextMenu:IsShown() or frame.rowMenu:IsShown() then hideMenus(); return true end
    if currentTab == "settings" then selectTab("roster"); return true end
    return false
end

local function close()
    manuallyClosed = true
    if frame then frame:Hide() end
end

local function dialog(width_, height_, title)
    local panel = T.Panel(frame, width_, height_, true)
    panel:SetPoint("CENTER", frame, "CENTER", 0, 20)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetBackdropBorderColor(unpack(T.trim))
    local heading = text(panel, 17, T.gold, 20, 15, width_ - 40, 26, nil, true)
    heading:SetText(title)
    T.Rule(panel, 1, 52, width_ - 2)
    panel:Hide()
    return panel
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function rowTooltip(row)
    local record, view = row.record, row.view
    if not record then return end
    local color = classColor(view.classToken)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(A.Text(displayName(record.identity)), color[1], color[2], color[3])
    GameTooltip:AddLine(A.Text(className(view.classToken or "UNKNOWN") .. (view.level and (" · Level " .. view.level) or "") .. " · " .. plural(record.count or 0, "whisper")), 1, 1, 1)
    GameTooltip:AddLine(A.Text("Last whisper " .. ago(record.lastSeenAt) .. " ago · first seen " .. ago(record.firstSeenAt) .. " ago"), .75, .72, .80)
    if record.identity.resolution ~= "exact" then GameTooltip:AddLine("Identity unresolved — unavailable for bulk export.", 1, .65, .4, true) end
    if record.lastListingEpoch ~= W.GetContext().epoch then GameTooltip:AddLine("Earlier listing — still included in this collection.", 1, .65, .4, true) end
    if view.equipmentAt then GameTooltip:AddLine(A.Text("Equipment snapshot: " .. P.AgeLabel(view.equipmentAt)), .75, .72, .80, true) end
    if view.equipmentState == "partial" then GameTooltip:AddLine("Equipment snapshot is partial.", 1, .65, .4, true) end
    if view.raidsAt and contextID then GameTooltip:AddLine(A.Text("Raid snapshot: " .. P.AgeLabel(view.raidsAt)), .75, .72, .80, true) end
    if contextID then GameTooltip:AddLine("AVG uses recorded bosses' best parses, matching the saved raid journal.", .75, .72, .80, true) end
    GameTooltip:AddLine(A.Text(record.lastMessage and ("“" .. record.lastMessage .. "”") or "Preview unavailable after reload."), .88, .86, .91, true)
    GameTooltip:AddLine("Right-click for actions", .57, .54, .61)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Bulk Search and confirmation dialogs
---------------------------------------------------------------------------

function showCopy()
    if InCombatLockdown() then A.Print("Bulk URL copying is unavailable during combat."); return end
    local newlyDimmed = not frame.scrim:IsShown()
    closeOverlays("copy")
    local result, reason = P.BuildExport(W.GetRows(), W.GetSelection(), W.GetContext().epoch)
    if not result then closeOverlays(); A.Print(reason or "No exportable players."); return end
    if result.count == 0 or #result.urls == 0 then
        closeOverlays()
        A.Print("No exportable players. " .. #result.excluded .. " identities are unresolved or unsupported.")
        return
    end
    if not frame.copy then
        local panel = dialog(480, 292, "Bulk Search")
        panel.summary = text(panel, 14, T.cream, 20, 68, 440, 22)
        panel.help = text(panel, 13, T.muted, 20, 96, 440, 40)
        panel.help:SetMaxLines(2)
        panel.help:SetText("Press Ctrl+C (Cmd+C on Mac) to copy, then paste the link into your browser.")
        panel.edit = input(panel, 20, 144, 440)
        panel.edit:SetMaxLetters(2000)
        panel.note = text(panel, 13, T.muted, 20, 190, 440, 22)
        panel.noteArea = CreateFrame("Frame", nil, panel)
        panel.noteArea:SetPoint("TOPLEFT", 20, -190)
        panel.noteArea:SetSize(440, 24)
        panel.previous = Button(panel, "Previous", 100, 32, function() panel:SelectBatch(panel.batch - 1) end)
        panel.previous:SetPoint("BOTTOMLEFT", 20, 20)
        panel.next = Button(panel, "Next batch", 118, 32, function() panel:SelectBatch(panel.batch + 1) end)
        panel.next:SetPoint("LEFT", panel.previous, "RIGHT", 10, 0)
        local done = Button(panel, "Close", 100, 32, function() panel:Hide() end, "primary")
        done:SetPoint("BOTTOMRIGHT", -20, 20)
        function panel:SelectBatch(index)
            self.batch = math.max(1, math.min(#self.result.urls, index))
            self.edit:SetText(self.result.urls[self.batch])
            self.edit:SetFocus()
            self.edit:HighlightText()
            self.summary:SetText(plural(self.result.count, "player") .. " · Batch " .. self.batch .. " of " .. #self.result.urls)
            self.previous:SetAlpha(self.batch > 1 and 1 or .45)
            self.next:SetAlpha(self.batch < #self.result.urls and 1 or .45)
        end
        panel.edit:SetScript("OnTextChanged", function(self)
            if panel.result and self:GetText() ~= panel.result.urls[panel.batch] then self:SetText(panel.result.urls[panel.batch]) end
        end)
        panel.edit:SetScript("OnEscapePressed", function() panel:Hide() end)
        panel.edit:SetScript("OnEnterPressed", function() panel:Hide() end)
        panel:SetScript("OnHide", function() M.Stop(panel); panel.edit:ClearFocus(); frame.scrim:Hide() end)
        panel.noteArea:EnableMouse(true)
        panel.noteArea:SetScript("OnEnter", function()
            if not panel.result or #panel.result.excluded == 0 then return end
            GameTooltip:SetOwner(panel, "ANCHOR_LEFT")
            GameTooltip:AddLine("Excluded from export", unpack(T.gold))
            for index, excluded in ipairs(panel.result.excluded) do
                if index > 10 then GameTooltip:AddLine("Additional exclusions: " .. (#panel.result.excluded - 10)); break end
                GameTooltip:AddLine(A.Text(excluded.name .. ": " .. excluded.reason), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        panel.noteArea:SetScript("OnLeave", function() GameTooltip:Hide() end)
        _G.SoulshardWhisperCopy = panel
        table.insert(UISpecialFrames, "SoulshardWhisperCopy")
        frame.copy = panel
    end
    local panel = frame.copy
    panel.result = result
    panel.note:SetText(#result.excluded .. " excluded · " .. result.earlierCount .. " from earlier listings")
    frame.scrim:Show()
    panel:Show()
    panel:SelectBatch(1)
    if newlyDimmed then reveal(frame.scrim, 0, M.timing.message, 0) end
    reveal(panel, 0, M.timing.enter, 8)
end

function showConfirm()
    local newlyDimmed = not frame.scrim:IsShown()
    closeOverlays("confirm")
    if not frame.confirm then
        local panel = dialog(440, 212, "Clear roster?")
        panel.message = text(panel, 14, T.cream, 20, 68, 400, 66)
        panel.message:SetMaxLines(3)
        local erase = Button(panel, "Clear roster", 150, 32, function() W.Clear(); panel:Hide(); U.Refresh() end, "danger")
        erase:SetPoint("BOTTOMLEFT", 20, 20)
        local cancel = Button(panel, "Cancel", 104, 32, function() panel:Hide() end)
        cancel:SetPoint("BOTTOMRIGHT", -20, 20)
        panel:SetScript("OnHide", function() M.Stop(panel); frame.scrim:Hide() end)
        frame.confirm = panel
    end
    frame.confirm.message:SetText("Remove " .. plural(#W.GetRows(), "player") .. " from this roster? Saved profile snapshots and settings are kept.")
    frame.scrim:Show()
    frame.confirm:Show()
    if newlyDimmed then reveal(frame.scrim, 0, M.timing.message, 0) end
    reveal(frame.confirm, 0, M.timing.enter, 8)
end

---------------------------------------------------------------------------
-- Roster page
---------------------------------------------------------------------------

local function toggleKey(entry)
    W.ToggleSelection(entry.record.key)
end

-- Row actions. The target is what the sender's own whisper would have carried: a bare name on this
-- realm, otherwise Name-Realm with the spaces Blizzard strips from realm names removed.
local function chatTarget(identity)
    if type(identity.name) ~= "string" then return nil end
    if not identity.realmName or sameRealm(identity.realmName) then return identity.name end
    return identity.name .. "-" .. (identity.realmName:gsub("%s", ""))
end

local function whisperTo(identity)
    local target = chatTarget(identity)
    if not target then return end
    if type(ChatFrame_SendTell) == "function" then pcall(ChatFrame_SendTell, target)
    elseif type(ChatFrame_OpenChat) == "function" then pcall(ChatFrame_OpenChat, "/w " .. target .. " ")
    else A.Print("Chat is unavailable.") end
end

local function inviteTo(identity)
    local target = chatTarget(identity)
    if not target then return end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if type(invite) ~= "function" then A.Print("Group invites are unavailable on this client."); return end
    pcall(invite, target)
end

local function openRowMenu(row)
    local entry, menu = row.entry, frame.rowMenu
    if not entry or not menu then return end
    local identity = entry.record.identity
    local color = classColor(row.view and row.view.classToken)
    hideMenus()
    menu.key, menu.identity = entry.record.key, identity
    menu.title:SetText(A.Text(identity.name or "Unresolved player"))
    menu.title:SetTextColor(unpack(color))
    -- A conflicting identity cannot be trusted as a whisper or invite target.
    menu.blocked = identity.resolution == "conflicting"
    menu.whisper:SetAlpha(menu.blocked and .45 or 1)
    menu.invite:SetAlpha(menu.blocked and .45 or 1)
    menu:ClearAllPoints()
    if row.index - offset <= 3 then menu:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", -14, -2)
    else menu:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", -14, 2) end
    menu:Show()
    menu.catcher:Show()
    reveal(menu, 0, M.timing.message, 6)
end

local function clickRow(row, button)
    local entry = row.entry
    if not entry then return end
    if button == "RightButton" then openRowMenu(row); return end
    local selected = W.GetSelection()
    local index = row.index
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and anchorIndex and views[anchorIndex] then
        local first, last = math.min(anchorIndex, index), math.max(anchorIndex, index)
        for position = first, last do
            local other = views[position]
            if other and (selected[other.record.key] == true) ~= anchorState then toggleKey(other) end
        end
    else
        toggleKey(entry)
        anchorIndex, anchorState = index, selected[entry.record.key] == true
    end
    U.Refresh()
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(rowWidth, rowHeight)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
    row.bg = fill(row, 0, 0, rowWidth, rowHeight - 1, T.gold, 1, "BACKGROUND")
    row.bg:SetAlpha(0)
    fill(row, 0, rowHeight - 1, rowWidth, 1, T.line, .9, "BORDER")
    row.stripe = fill(row, 0, 0, 3, rowHeight - 1, T.gold, 1, "ARTWORK")
    row.box = checkbox(row)
    row.box:SetPoint("TOPLEFT", 16, -math.floor((rowHeight - 18) / 2))
    local ringY = (rowHeight - 1 - ringSize) / 2
    local lower = ringY + ringSize - badgeSize + 4
    row.ring = T.Disc(row, "TOPLEFT", ringX, -ringY, ringSize, T.line, 1, "BORDER")
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(portraitSize, portraitSize)
    row.portrait:SetPoint("TOPLEFT", ringX + (ringSize - portraitSize) / 2, -(ringY + (ringSize - portraitSize) / 2))
    T.Circle(row, row.portrait)
    -- Class badge, lower right. Its icon is left out when the portrait itself is the class icon.
    local badgeX = ringX + ringSize / 2 + 17
    row.badgeBack = T.Disc(row, "TOPLEFT", badgeX - badgeSize / 2, -lower, badgeSize, T.background, 1, "ARTWORK", 2)
    row.badge = row:CreateTexture(nil, "ARTWORK", nil, 3)
    row.badge:SetSize(badgeSize - 5, badgeSize - 5)
    row.badge:SetPoint("TOPLEFT", badgeX - badgeSize / 2 + 2.5, -(lower + 2.5))
    T.Circle(row, row.badge)
    -- Level badge, lower left.
    local levelX = ringX + ringSize / 2 - 17
    row.levelBack = T.Disc(row, "TOPLEFT", levelX - badgeSize / 2, -lower, badgeSize, T.background, 1, "ARTWORK", 2)
    row.level = text(row, 13, T.cream, levelX - badgeSize / 2, lower + 3, badgeSize, 16, "CENTER")
    local metricWidth = 132
    row.name = text(row, 15, T.cream, textX, 8, rowWidth - textX - metricWidth - 20, 20)
    row.preview = text(row, 13, T.muted, textX, 30, rowWidth - textX - metricWidth - 20, 18)
    row.metric = Label(row, 15, T.gold)
    row.metric:SetPoint("TOPRIGHT", -14, -8)
    row.metric:SetSize(metricWidth, 20)
    row.metric:SetMaxLines(1)
    row.metric:SetJustifyH("RIGHT")
    row.sub = Label(row, 13, T.muted)
    row.sub:SetPoint("TOPRIGHT", -14, -30)
    row.sub:SetSize(metricWidth, 18)
    row.sub:SetMaxLines(1)
    row.sub:SetJustifyH("RIGHT")
    function row:Paint()
        -- A row that was just handed to a different player jumps to its state; hover and selection ease.
        local instant = self.rebound
        self.rebound = nil
        ease(self.bg, self.selected and .14 or (self.hovered and .07 or 0), instant)
        ease(self.stripe, self.selected and 1 or (self.hovered and .7 or .45), instant)
        self.box:SetState(self.selected and "on" or "off")
    end
    function row:SetSelected(selected)
        self.selected = selected
        self:Paint()
    end
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", clickRow)
    row:HookScript("OnEnter", function(self) self.hovered = true; self:Paint(); rowTooltip(self) end)
    row:HookScript("OnLeave", function(self) self.hovered = false; self:Paint(); GameTooltip:Hide() end)
    return row
end

local function nameText(entry)
    local identity, record = entry.record.identity, entry.record
    local result = A.Text(identity.name or "Unresolved player")
    if identity.realmName and not sameRealm(identity.realmName) then result = result .. mutedHex .. "-" .. A.Text(identity.realmName) .. "|r" end
    result = result .. mutedHex .. "  ×" .. (record.count or 0) .. "|r"
    if identity.resolution ~= "exact" then result = result .. dangerHex .. "  !|r" end
    return result
end

local function fullView(entry, settings)
    if not settings.showSnapshots then
        return { classToken = entry.view.classToken, level = entry.record.level, raceToken = entry.view.raceToken, sex = entry.view.sex }
    end
    if not contextID then return entry.view end
    entry.full = entry.full or P.Enrich(entry.record, contextID)
    return entry.full
end

-- The portrait is the live picture when the player is in view, else a generic race portrait, else the class icon.
-- A class icon portrait already says the class, so the badge only appears next to a real or race portrait.
local function paintPortrait(row)
    local entry, view = row.entry, row.view
    if not entry or not view then return end
    local source = A.Portraits.Apply(row.portrait, entry.record.identity, view)
    row.source = source
    local badged = source ~= "class" and view.classToken ~= nil
    row.badgeBack:SetShown(badged)
    row.badge:SetShown(badged)
    if badged then T.ClassIcon(row.badge, view.classToken) end
end

local function renderRows()
    local settings, selected = W.GetSettings(), W.GetSelection()
    local epoch = W.GetContext().epoch
    local fresh = frame.fresh
    for index, row in ipairs(frame.rows) do
        local entry = views[offset + index]
        local previousKey = row.record and row.record.key
        row:SetShown(entry ~= nil)
        row.entry, row.record, row.index = entry, entry and entry.record, offset + index
        if entry then
            local record = entry.record
            row.rebound = previousKey ~= record.key
            local view = fullView(entry, settings)
            local token = view.classToken
            local color = classColor(token)
            row.view = view
            row.ring:SetColorTexture(color[1], color[2], color[3], token and .9 or .35)
            row.stripe:SetColorTexture(color[1], color[2], color[3], 1)
            row.level:SetText(view.level and tostring(view.level) or "")
            row.levelBack:SetShown(view.level ~= nil)
            paintPortrait(row)
            row.name:SetText(nameText(entry))
            row.name:SetTextColor(unpack(color))
            row.preview:SetText(A.Text(ago(record.lastSeenAt) .. " · " .. (record.lastMessage or "Preview cleared after reload")))
            local metric, sub, subColor = "", "", T.muted
            if settings.showSnapshots then
                if view.gearScore ~= nil then
                    metric = value(view.gearScore) .. " GS" .. (view.equipmentState == "partial" and "*" or "")
                    if contextID and view.raidName and (view.averageParse ~= nil or view.bestParse ~= nil) then
                        sub = value(view.averageParse) .. " avg · " .. value(view.bestParse) .. " best"
                    elseif contextID then sub = "No raid data"
                    else sub = "saved " .. ago(view.equipmentAt or view.raidsAt) end
                    if view.stale then subColor = T.danger end
                else
                    metric = "—"
                    if contextID and view.raidName and (view.averageParse ~= nil or view.bestParse ~= nil) then
                        sub = value(view.averageParse) .. " avg · " .. value(view.bestParse) .. " best"
                        if view.stale then subColor = T.danger end
                    else sub = "No snapshot" end
                end
            end
            row.metric:SetText(A.Text(metric))
            row.metric:SetTextColor(unpack(metric == "—" and T.muted or T.gold))
            row.sub:SetText(A.Text(sub))
            row.sub:SetTextColor(unpack(subColor))
            local earlier = record.lastListingEpoch ~= epoch
            for _, region in ipairs({ row.name, row.preview, row.metric, row.sub, row.level }) do region:SetAlpha(earlier and .6 or 1) end
            for _, region in ipairs({ row.ring, row.portrait, row.badgeBack, row.badge, row.levelBack }) do region:SetAlpha(earlier and .6 or 1) end
            row:SetSelected(selected[record.key] == true)
            if fresh and fresh[record.key] then reveal(row, 0, M.timing.row, 8) end
        end
    end
    local overflow = math.max(0, #views - visibleRows)
    frame.scrollbar:SetShown(overflow > 0)
    syncing = true
    frame.scrollbar:SetMinMaxValues(0, overflow)
    frame.scrollbar:SetValue(offset)
    syncing = false
    local track = visibleRows * rowHeight - 2
    frame.thumb:SetSize(trackWidth, math.max(28, math.floor(track * visibleRows / math.max(visibleRows, #views))))
end

-- Repaint only the portraits: joining the group or targeting a player can give a row a live picture without anything else changing.
function U.RepaintPortraits()
    if not frame or not frame:IsShown() or currentTab ~= "roster" then return end
    for _, row in ipairs(frame.rows) do
        if row:IsShown() then paintPortrait(row) end
    end
end

local function setOffset(value_)
    local maximum = math.max(0, #views - visibleRows)
    value_ = math.max(0, math.min(maximum, math.floor(value_ + .5)))
    if value_ == offset then return end
    offset = value_
    if frame and frame:IsShown() then renderRows() end
end

local function sortViews(list, settings)
    if sortKey == "recent" then return end
    local scored = {}
    if sortKey == "score" then
        for _, entry in ipairs(list) do
            local source = (contextID and settings.showSnapshots) and fullView(entry, settings) or entry.view
            scored[entry] = contextID and settings.showSnapshots and (source.averageParse or source.bestParse) or source.gearScore
        end
    end
    table.sort(list, function(left, right)
        if sortKey == "name" then
            local a, b = (strlower or string.lower)(left.display), (strlower or string.lower)(right.display)
            if a ~= b then return a < b end
        else
            local a, b = scored[left], scored[right]
            if a ~= b then
                if a == nil then return false end
                if b == nil then return true end
                return a > b
            end
        end
        return left.order < right.order
    end)
end

-- Lays out whatever the empty state shows as one block, centred in the list area and a little above the
-- middle: logo, title, body, then the reset button when a filter hides everyone.
local function layoutEmpty(empty, hasReset)
    local bodyWidth = rowWidth - 112
    local bodyHeight
    if type(empty.body.GetStringHeight) == "function" then
        -- Measure with room to spare so the text is never clipped, then fit the box to it.
        empty.body:SetSize(bodyWidth, 80)
        bodyHeight = math.max(20, math.ceil(empty.body:GetStringHeight()) + 2)
    else
        bodyHeight = 20 * math.max(1, math.ceil(#(empty.body:GetText() or "") / 52))
    end
    local total = 52 + 16 + 24 + 6 + bodyHeight + (hasReset and 20 + 32 or 0)
    local y = math.max(16, math.floor((visibleRows * rowHeight - total) / 2) - 8)
    empty.logo:ClearAllPoints()
    empty.logo:SetPoint("TOP", 0, -y)
    y = y + 52 + 16
    empty.title:ClearAllPoints()
    empty.title:SetPoint("TOPLEFT", 24, -y)
    y = y + 24 + 6
    empty.body:ClearAllPoints()
    empty.body:SetPoint("TOPLEFT", 56, -y)
    empty.body:SetSize(bodyWidth, bodyHeight)
    y = y + bodyHeight
    if hasReset then
        empty.reset:ClearAllPoints()
        empty.reset:SetPoint("TOP", 0, -(y + 20))
    end
end

local function emptyState(status, total, hidden, state, tone)
    local empty = frame.empty
    local title, body = "", ""
    if total > 0 then
        title = "No players match"
        body = plural(hidden, "player") .. " hidden by the class filter."
    elseif state == "recording" then
        title = "Listening for whispers"
        body = "Players who whisper you about your listing will appear here, with their saved GearScore when the archive knows them."
    else
        local _, headline, detail = describe(status)
        title = headline == "Paused" and "Collection paused" or (headline == "Off" and "Collection is off" or "Collection unavailable")
        body = pausedCopy[state] or detail
    end
    empty.title:SetText(A.Text(title))
    empty.title:SetTextColor(unpack(total > 0 and T.cream or (tone == "bad" and T.danger or T.gold)))
    empty.body:SetText(A.Text(body))
    empty.reset:SetShown(total > 0)
    layoutEmpty(empty, total > 0)
    empty:SetShown(true)
end

function refreshRoster(settings, status)
    local records, selected = W.GetRows(), W.GetSelection()
    local epoch = W.GetContext().epoch
    local list, counts = {}, { ALL = 0 }
    local whispers, selectedCount, earlier = 0, 0, 0
    for index, record in ipairs(records) do
        whispers = whispers + (record.count or 0)
        if selected[record.key] then selectedCount = selectedCount + 1 end
        if record.lastListingEpoch ~= epoch then earlier = earlier + 1 end
        local display = displayName(record.identity)
        local view = P.Enrich(record)
        local token = view.classToken or "UNKNOWN"
        counts.ALL = counts.ALL + 1
        counts[token] = (counts[token] or 0) + 1
        if classFilter == "ALL" or classFilter == token then list[#list + 1] = { record = record, view = view, display = display, order = index } end
    end
    sortViews(list, settings)
    views = list
    if anchorIndex and not views[anchorIndex] then anchorIndex = nil end
    offset = math.max(0, math.min(offset, math.max(0, #views - visibleRows)))
    frame.counts = counts

    frame.bulk.label:SetText(selectedCount > 0 and ("Bulk Search Selected (" .. selectedCount .. ")") or ("Bulk Search (" .. #records .. ")"))
    frame.clear:SetAlpha(#records > 0 and 1 or .45)
    local players = #views ~= #records and (#views .. " of " .. plural(#records, "player")) or plural(#records, "player")
    frame.count:SetText(players .. "\n" .. plural(whispers, "whisper"))

    for _, token in ipairs(classes) do
        local chip = frame.chips[token]
        local count = counts[token] or 0
        local active = classFilter == token
        chip.count:SetText(count > 0 and tostring(count) or "")
        chip.count:SetTextColor(unpack(active and T.gold or T.muted))
        chip.icon:SetAlpha((count > 0 or active) and 1 or .3)
        chip.icon:SetDesaturated(count == 0 and not active)
        chip.active = active
        if token == "ALL" then
            -- Chosen, "All" is a solid gold disc with dark type; otherwise a faint gold tint with gold type.
            chip.icon:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], active and 1 or .18)
            chip.all:SetTextColor(unpack(active and T.background or T.gold))
        end
        -- Resting ring: the class colour when anyone of that class is on the roster, otherwise the dim line colour.
        chip.restColor = count > 0 and ((token == "ALL" or token == "UNKNOWN") and T.muted or classColor(token)) or T.line
        chip.ring:SetColorTexture(unpack(active and T.gold or (chip.hovered and T.muted or chip.restColor)))
        chip.ring:SetAlpha(active and 1 or (count > 0 and .85 or .6))
    end

    local shownSelected = 0
    for _, entry in ipairs(views) do if selected[entry.record.key] then shownSelected = shownSelected + 1 end end
    frame.selectAll.box:SetState(#views > 0 and shownSelected == #views and "on" or (shownSelected > 0 and "partial" or "off"))
    local hiddenSelected = selectedCount - shownSelected
    frame.selectAll.label:SetText(selectedCount > 0 and (selectedCount .. " selected" .. (hiddenSelected > 0 and (" · " .. hiddenSelected .. " hidden") or "")) or (#views == 0 and "Nothing to select" or ("Select " .. (#views == #records and "all" or "shown") .. " (" .. #views .. ")")))
    frame.selectAll.label:SetTextColor(unpack(selectedCount > 0 and T.gold or T.muted))
    local parseMode = contextID ~= nil and settings.showSnapshots
    frame.sortButtons.score.label:SetText(parseMode and "Parse" or "GearScore")
    for _, key in ipairs(sorts) do frame.sortButtons[key]:SetActive(sortKey == key) end

    local contextLabel = "Raid parses"
    for _, context in ipairs(P.Contexts()) do if context.id == contextID then contextLabel = context.name end end
    frame.contextButton.label:SetText(A.Text(contextLabel))
    frame.contextButton:SetSelected(contextID ~= nil)
    for index, button in ipairs(frame.contextMenu.buttons) do
        local choice = frame.contextMenu.choices[index]
        button:SetSelected((choice.id or nil) == contextID)
    end
    if frame.rowMenu:IsShown() then
        local alive = false
        for _, record in ipairs(records) do if record.key == frame.rowMenu.key then alive = true end end
        if not alive then hideMenus() end
    end

    local filtered = classFilter ~= "ALL"
    if status.overflowCount and status.overflowCount > 0 then frame.message:SetText("Collection full — new players are skipped.")
    elseif earlier > 0 then frame.message:SetText(plural(earlier, "player") .. " from earlier listings (dimmed). Clear the roster to start fresh.")
    elseif filtered then frame.message:SetText("Filters only change the view. Bulk Search uses everyone, or your selection.")
    else frame.message:SetText("Click a row to select; Shift-click for a range; right-click for actions.") end

    local tone, _, _ = describe(status)
    if #views == 0 then emptyState(status, #records, #records - #views, status.state, tone)
    else frame.empty:Hide() end
    -- Players who arrived since the last paint fade in; the first paint after opening has nothing to compare with.
    frame.fresh = nil
    local known, current = frame.knownKeys, {}
    for _, record in ipairs(records) do
        current[record.key] = true
        if known and not known[record.key] then
            frame.fresh = frame.fresh or {}
            frame.fresh[record.key] = true
        end
    end
    frame.knownKeys = current
    renderRows()
    frame.fresh = nil
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------

local function parseKeywords(source)
    local keywords = {}
    for term in source:gmatch("[^,]+") do
        term = term:match("^%s*(.-)%s*$")
        if term ~= "" then keywords[#keywords + 1] = term end
    end
    return keywords
end

local function filterDirty(page)
    local saved = W.GetSettings()
    if page.mode ~= saved.mode or page.matchAll ~= saved.matchAll or page.caseSensitive ~= saved.caseSensitive then return true end
    if page.mode == "keywords" and table.concat(parseKeywords(page.keywords:GetText()), ",") ~= table.concat(saved.keywords, ",") then return true end
    if page.mode == "prefix" and page.prefix:GetText() ~= saved.prefix then return true end
    return false
end

local function paintFilter(page)
    for _, mode in ipairs(modes) do page.modeButtons[mode]:SetSelected(page.mode == mode) end
    page.help:SetText(modeHelp[page.mode])
    page.keywordsLabel:SetShown(page.mode == "keywords")
    page.keywords:SetShown(page.mode == "keywords")
    page.prefixLabel:SetShown(page.mode == "prefix")
    page.prefix:SetShown(page.mode == "prefix")
    page.anyNote:SetShown(page.mode == "any")
    page.matchAllOption:SetShown(page.mode == "keywords")
    page.caseOption:SetShown(page.mode ~= "any")
    page.caseOption:ClearAllPoints()
    page.caseOption:SetPoint("TOPLEFT", page.mode == "keywords" and 256 or 16, -180)
    -- "Any whisper" has no inputs, so its card is shorter and the Display card follows it up.
    local filterHeight = page.mode == "any" and 218 or 262
    page.filterCard:SetHeight(filterHeight)
    page.displayCard:ClearAllPoints()
    page.displayCard:SetPoint("TOPLEFT", 0, -(188 + filterHeight + 8))
    page.matchAllOption:SetChecked(page.matchAll)
    page.caseOption:SetChecked(page.caseSensitive)
    local dirty = filterDirty(page)
    page.dirty = dirty
    page.save.label:SetText(dirty and "Save filter" or "Saved")
    page.save:SetAlpha(dirty and 1 or .45)
    page.status:SetText(dirty and page.message:GetText() == "" and "Unsaved changes" or "")
end

local function createSettings(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", gutter, -pageTop)
    page:SetSize(inner, settingsHeight)
    local pad = 16
    local contentWidth = inner - pad * 2
    page.cards = {}

    local collection = card(page, 0, 180, "COLLECTION")
    page.cards[1] = collection
    page.toggles = {}
    local fields = {
        { "enabled", "Collect while eligible", "Record whispers while you lead a listed group." },
        { "autoShow", "Show beside Looking For Group", "Open this window together with the Group Finder." },
    }
    for index, field in ipairs(fields) do
        local key = field[1]
        local row = option(collection, pad, 48 + (index - 1) * 46, contentWidth, field[2], field[3], function()
            W.UpdateSettings({ [key] = not W.GetSettings()[key] })
            U.Refresh()
        end)
        page.toggles[index] = { button = row, key = key }
    end
    text(collection, 14, T.cream, pad, 149, 200, 22):SetText("Keep the roster")
    page.retention = {}
    for index, choice in ipairs({ { "24h", "24 hours", 112 }, { "session", "This session", 128 } }) do
        local button = Button(collection, choice[2], choice[3], 30, function()
            W.UpdateSettings({ retention = choice[1] })
            U.Refresh()
        end)
        button:SetPoint("TOPRIGHT", index == 1 and -(pad + 128 + 8) or -pad, -144)
        page.retention[choice[1]] = button
    end

    local filter = card(page, 188, 262, "CAPTURE FILTER")
    page.cards[2] = filter
    page.filterCard = filter
    page.mode, page.matchAll, page.caseSensitive = "any", false, false
    page.modeButtons = {}
    local gap = 8
    local segment = math.floor((contentWidth - gap * 2) / 3)
    for index, mode in ipairs(modes) do
        local button = Button(filter, modeNames[mode], segment, 30, function()
            page.mode = mode
            page.message:SetText("")
            paintFilter(page)
        end)
        button:SetPoint("TOPLEFT", pad + (index - 1) * (segment + gap), -48)
        page.modeButtons[mode] = button
    end
    page.help = text(filter, 13, T.muted, pad, 88, contentWidth, 20)
    page.keywordsLabel = text(filter, 13, T.muted, pad, 116, contentWidth, 20)
    page.keywordsLabel:SetText("Keywords (comma-separated, literal text)")
    page.keywords = input(filter, pad, 138, contentWidth, "For example: invite, healer")
    page.prefixLabel = text(filter, 13, T.muted, pad, 116, contentWidth, 20)
    page.prefixLabel:SetText("Starts with (literal text)")
    page.prefix = input(filter, pad, 138, contentWidth, "For example: +")
    for _, edit in ipairs({ page.keywords, page.prefix }) do
        edit.changed = function() page.message:SetText(""); paintFilter(page) end
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    page.matchAllOption = option(filter, pad, 180, 220, "Match all keywords", nil, function()
        page.matchAll = not page.matchAll
        paintFilter(page)
    end)
    page.caseOption = option(filter, pad + 240, 180, 190, "Case-sensitive", nil, function()
        page.caseSensitive = not page.caseSensitive
        paintFilter(page)
    end)
    page.anyNote = text(filter, 13, T.muted, pad, 120, contentWidth, 42)
    page.anyNote:SetMaxLines(2)
    page.anyNote:SetText("Filters apply to future whispers only. Players already in the roster stay there.")
    page.status = text(filter, 13, T.gold, pad, 0, 140, 20)
    page.message = text(filter, 13, T.danger, pad, 0, 280, 20)
    page.message:SetMaxLines(1)
    -- Both sit on the Save button's line, which rides the bottom edge of the card.
    for _, label in ipairs({ page.status, page.message }) do
        label:ClearAllPoints()
        label:SetPoint("BOTTOMLEFT", pad, 20)
    end
    page.save = Button(filter, "Saved", 140, 32, function()
        if not page.dirty then return end
        local keywords = page.mode == "keywords" and parseKeywords(page.keywords:GetText()) or W.GetSettings().keywords
        local prefix = page.mode == "prefix" and page.prefix:GetText() or W.GetSettings().prefix
        local ok, reason = W.UpdateSettings({
            mode = page.mode, keywords = keywords, prefix = prefix,
            matchAll = page.matchAll, caseSensitive = page.caseSensitive,
        })
        page.message:SetTextColor(unpack(ok and T.good or T.danger))
        page.message:SetText(ok and "Filter saved." or A.Text(reason))
        paintFilter(page)
    end, "primary")
    page.save:SetPoint("BOTTOMRIGHT", -pad, 14)

    local display = card(page, 458, 140, "DISPLAY")
    page.cards[3] = display
    page.displayCard = display
    page.displayToggles = {}
    local displayFields = {
        { "showSnapshots", "Show saved snapshots", "GearScore and raid parses from installed data." },
        { "animate", "Animate window", "Fade and slide the window in as it opens and changes pages." },
    }
    for index, field in ipairs(displayFields) do
        local key = field[1]
        local row = option(display, pad, 48 + (index - 1) * 46, contentWidth, field[2], field[3], function()
            W.UpdateSettings({ [key] = not W.GetSettings()[key] })
            U.Refresh()
        end)
        page.displayToggles[index] = { button = row, key = key }
    end
    page:Hide()
    return page
end

-- Copies saved values into the page. The filter draft is only replaced when it is clean.
local function syncSettings(force)
    local page, settings = frame.settings, W.GetSettings()
    for _, toggle in ipairs(page.toggles) do toggle.button:SetChecked(settings[toggle.key]) end
    for _, toggle in ipairs(page.displayToggles) do toggle.button:SetChecked(settings[toggle.key]) end
    for key, button in pairs(page.retention) do button:SetSelected(settings.retention == key) end
    if force or not page.dirty then
        page.mode, page.matchAll, page.caseSensitive = settings.mode, settings.matchAll, settings.caseSensitive
        local keywords = table.concat(settings.keywords, ", ")
        if page.keywords:GetText() ~= keywords then page.keywords:SetText(keywords) end
        if page.prefix:GetText() ~= settings.prefix then page.prefix:SetText(settings.prefix) end
    end
    paintFilter(page)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function paintStatus(status)
    local tone, title, detail = describe(status)
    local color = tones[tone]
    local strip = frame.statusStrip
    strip.accent:SetColorTexture(color[1], color[2], color[3], 1)
    strip.lamp:SetColorTexture(color[1], color[2], color[3], 1)
    strip.glow:SetColorTexture(color[1], color[2], color[3], .22)
    strip.tint:SetGradient("HORIZONTAL", CreateColor(color[1], color[2], color[3], .2), CreateColor(color[1], color[2], color[3], 0))
    frame.status:SetText(A.Text(title))
    frame.status:SetTextColor(unpack(color))
    frame.statusDetail:SetText(A.Text(detail))
    strip.label, strip.reason = status.label, status.reason
    -- A change of state (Paused to Recording, say) fades the new wording in; the first paint after opening does not.
    local key = tone .. "|" .. title
    if strip.key and strip.key ~= key then
        reveal(frame.status, 0, M.timing.message, 0)
        reveal(frame.statusDetail, 0, M.timing.message, 0)
    end
    strip.key = key
end

local chipRing, chipIcon = 32, 28

local function createChips(parent)
    local chips, slot = {}, math.floor(inner / #classes)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(inner, 50)
    strip:SetPoint("TOPLEFT", 0, -chipsTop)
    frame.chipStrip = strip
    for index, token in ipairs(classes) do
        -- A round class icon inside a ring; the ring carries the state (gold when filtered, class colour when present).
        local chip = CreateFrame("Button", nil, strip)
        chip:SetSize(slot - 3, 50)
        chip:SetPoint("TOPLEFT", 1 + (index - 1) * slot, 0)
        chip.ring = T.Disc(chip, "TOP", 0, -1, chipRing, T.line, 1, "BORDER")
        chip.icon = chip:CreateTexture(nil, "ARTWORK")
        chip.icon:SetSize(chipIcon, chipIcon)
        chip.icon:SetPoint("TOP", 0, -1 - (chipRing - chipIcon) / 2)
        T.Circle(chip, chip.icon)
        if token == "ALL" then
            chip.icon:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], .18)
            chip.all = Label(chip, 14, T.gold, true)
            chip.all:SetPoint("TOP", 0, -1 - (chipRing - 20) / 2)
            chip.all:SetSize(slot - 3, 20)
            chip.all:SetJustifyH("CENTER")
            chip.all:SetText("All")
        else T.ClassIcon(chip.icon, token) end
        chip.count = Label(chip, 13, T.muted)
        chip.count:SetPoint("BOTTOM", 0, 0)
        chip.count:SetSize(slot - 3, 17)
        chip.count:SetJustifyH("CENTER")
        chip:SetScript("OnClick", function()
            classFilter = (classFilter == token or token == "ALL") and "ALL" or token
            offset = 0
            U.Refresh()
            revealRows()
        end)
        chip:SetScript("OnEnter", function(self)
            self.hovered = true
            if not self.active then self.ring:SetColorTexture(unpack(T.muted)) end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(A.Text(className(token)), unpack(T.gold))
            GameTooltip:AddLine(plural(frame.counts and frame.counts[token] or 0, "player"), 1, 1, 1)
            GameTooltip:Show()
        end)
        chip:SetScript("OnLeave", function(self)
            self.hovered = false
            if not self.active then self.ring:SetColorTexture(unpack(self.restColor or T.line)) end
            GameTooltip:Hide()
        end)
        chips[token] = chip
    end
    return chips
end

local function createContextMenu(parent)
    local choices = { { id = false, label = "No raid context" } }
    for _, context in ipairs(P.Contexts()) do choices[#choices + 1] = { id = context.id, label = context.name } end
    local menu = T.Panel(parent, 236, #choices * 34 + 16, true)
    menu:SetPoint("TOPRIGHT", frame.contextButton, "BOTTOMRIGHT", 0, -6)
    menu:SetFrameLevel(parent:GetFrameLevel() + 30)
    menu:SetBackdropBorderColor(unpack(T.trim))
    menu.catcher = CreateFrame("Button", nil, frame)
    menu.catcher:SetAllPoints()
    menu.catcher:SetFrameLevel(frame:GetFrameLevel() + 20)
    menu.catcher:SetScript("OnClick", function() setMenu(false) end)
    menu.catcher:Hide()
    menu.buttons, menu.choices = {}, choices
    for index, choice in ipairs(choices) do
        local button = Button(menu, A.Text(choice.label), 220, 30, function()
            contextID = choice.id or nil
            setMenu(false)
            U.Refresh()
            revealRows()
        end)
        button:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 34)
        menu.buttons[index] = button
    end
    menu:Hide()
    return menu
end

local function createRowMenu()
    local menu = T.Panel(frame, 236, 156, true)
    menu:SetFrameLevel(frame:GetFrameLevel() + 31)
    menu:SetBackdropBorderColor(unpack(T.trim))
    menu.title = text(menu, 14, T.cream, 14, 10, 208, 22)
    menu.title:SetMaxLines(1)
    T.Rule(menu, 1, 38, 234)
    menu.catcher = CreateFrame("Button", nil, frame)
    menu.catcher:SetAllPoints()
    menu.catcher:SetFrameLevel(frame:GetFrameLevel() + 20)
    menu.catcher:RegisterForClicks("AnyUp")
    menu.catcher:SetScript("OnClick", function() hideMenus() end)
    menu.catcher:Hide()
    menu.whisper = Button(menu, "Whisper", 220, 30, function()
        if menu.blocked then return end
        local identity = menu.identity
        hideMenus()
        whisperTo(identity)
    end)
    menu.whisper:SetPoint("TOPLEFT", 8, -46)
    menu.invite = Button(menu, "Invite to group", 220, 30, function()
        if menu.blocked then return end
        local identity = menu.identity
        hideMenus()
        inviteTo(identity)
    end)
    menu.invite:SetPoint("TOPLEFT", 8, -82)
    menu.remove = Button(menu, "Remove from roster", 220, 30, function()
        local key = menu.key
        hideMenus()
        W.Remove(key)
        U.Refresh()
    end, "danger")
    menu.remove:SetPoint("TOPLEFT", 8, -118)
    menu:Hide()
    return menu
end

local function createRoster(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", gutter, -pageTop)
    page:SetSize(inner, rosterHeight)

    -- The player and whisper count sits at the right of the status strip, behind a hairline; it belongs to
    -- this page so it leaves with it.
    local strip = frame.statusStrip
    frame.count = Label(page, 13, T.cream)
    frame.count:SetPoint("RIGHT", strip, "RIGHT", -16, 0)
    frame.count:SetSize(countWidth, 34)
    frame.count:SetMaxLines(2)
    frame.count:SetJustifyH("RIGHT")
    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(T.line[1], T.line[2], T.line[3], 1)
    divider:SetSize(1, 24)
    divider:SetPoint("RIGHT", strip, "RIGHT", -(16 + countWidth + 14), 0)

    -- The raid-parse picker lives on the right of the tab row, where it is always within reach.
    frame.contextButton = Button(frame.nav, "Raid parses", 188, 28, function()
        setMenu(not frame.contextMenu:IsShown())
    end)
    frame.contextButton:SetPoint("TOPRIGHT", 0, 0)
    frame.contextButton.label:ClearAllPoints()
    frame.contextButton.label:SetPoint("CENTER", -8, 0)
    frame.contextButton.label:SetSize(144, 20)
    frame.contextButton.label:SetMaxLines(1)
    frame.contextButton.label:SetJustifyH("CENTER")
    caret(frame.contextButton, T.gold)
    frame.contextButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Raid parses", unpack(T.gold))
        GameTooltip:AddLine("Show saved parses for one raid on every row instead of snapshot age.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.contextButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

    frame.chips = createChips(page)

    -- Header above the list: bulk select on the left, sort keys on the right.
    local listHeader = CreateFrame("Frame", nil, page)
    listHeader:SetPoint("TOPLEFT", 0, -headerTop)
    listHeader:SetSize(inner, 28)
    frame.listHeader = listHeader
    frame.selectAll = CreateFrame("Button", nil, listHeader)
    frame.selectAll:SetSize(250, 28)
    frame.selectAll:SetPoint("TOPLEFT", 0, 0)
    frame.selectAll.box = checkbox(frame.selectAll)
    frame.selectAll.box:SetPoint("LEFT", 0, 0)
    frame.selectAll.label = text(frame.selectAll, 13, T.muted, 30, 4, 216, 20)
    frame.selectAll:SetScript("OnClick", function()
        local selected, all = W.GetSelection(), true
        for _, entry in ipairs(views) do if not selected[entry.record.key] then all = false end end
        for _, entry in ipairs(views) do if (selected[entry.record.key] == true) == all then toggleKey(entry) end end
        U.Refresh()
    end)
    frame.sortButtons = {}
    local sortWidths = { recent = 64, name = 54, score = 92 }
    local previous
    for _, key in ipairs({ "score", "name", "recent" }) do
        local button = flat(listHeader, sortNames[key] or "GearScore", sortWidths[key], 28, 13, function()
            sortKey = key
            offset = 0
            U.Refresh()
            revealRows()
        end)
        if previous then button:SetPoint("RIGHT", previous, "LEFT", -2, 0) else button:SetPoint("TOPRIGHT", 0, 0) end
        frame.sortButtons[key] = button
        previous = button
    end
    frame.sortLabel = Label(listHeader, 13, T.muted)
    frame.sortLabel:SetPoint("RIGHT", previous, "LEFT", -6, 0)
    frame.sortLabel:SetText("Sort")

    local box = T.Panel(page, inner, listHeight, true)
    box:SetPoint("TOPLEFT", 0, -listTop)
    frame.listBox = box
    frame.viewport = CreateFrame("Frame", nil, box)
    frame.viewport:SetPoint("TOPLEFT", 1, -1)
    frame.viewport:SetSize(rowWidth, visibleRows * rowHeight)
    frame.viewport:EnableMouseWheel(true)
    frame.viewport:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta * 2) end)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta * 2) end)
    frame.rows = {}
    for index = 1, visibleRows do frame.rows[index] = createRow(frame.viewport, index) end

    frame.scrollbar = CreateFrame("Slider", nil, box)
    frame.scrollbar:SetPoint("TOPRIGHT", -3, -2)
    frame.scrollbar:SetSize(trackWidth, visibleRows * rowHeight - 2)
    frame.scrollbar:SetOrientation("VERTICAL")
    frame.scrollbar:SetValueStep(1)
    if frame.scrollbar.SetObeyStepOnDrag then frame.scrollbar:SetObeyStepOnDrag(true) end
    fill(frame.scrollbar, 0, 0, trackWidth, visibleRows * rowHeight - 2, T.line, .8)
    frame.thumb = fill(frame.scrollbar, 0, 0, trackWidth, 36, T.gold, .55, "OVERLAY")
    frame.scrollbar:SetThumbTexture(frame.thumb)
    frame.scrollbar:SetMinMaxValues(0, 0)
    frame.scrollbar:SetScript("OnValueChanged", function(_, scrolled)
        if not syncing then setOffset(scrolled) end
    end)
    frame.scrollbar:Hide()

    -- Empty state shares the list area.
    local empty = CreateFrame("Frame", nil, box)
    empty:SetPoint("TOPLEFT", 1, -1)
    empty:SetSize(rowWidth, visibleRows * rowHeight)
    empty.logo = empty:CreateTexture(nil, "ARTWORK")
    empty.logo:SetSize(52, 52)
    empty.logo:SetPoint("TOP", 0, -24)
    empty.logo:SetTexture(T.logo)
    empty.logo:SetAlpha(.6)
    empty.title = text(empty, 17, T.gold, 24, 0, rowWidth - 48, 24, "CENTER", true)
    empty.body = text(empty, 14, T.muted, 56, 0, rowWidth - 112, 20, "CENTER")
    empty.body:SetMaxLines(4)
    if empty.body.SetJustifyV then empty.body:SetJustifyV("TOP") end
    empty.reset = Button(empty, "Show all classes", 170, 32, function()
        classFilter, offset = "ALL", 0
        U.Refresh()
        revealRows()
    end)
    empty.reset:SetPoint("TOP", 0, 0)
    empty:Hide()
    frame.empty = empty

    local footer = CreateFrame("Frame", nil, page)
    footer:SetPoint("TOPLEFT", 0, -footerTop)
    footer:SetSize(inner, 64)
    frame.footer = footer
    frame.clear = Button(footer, "Clear roster", 132, 32, showConfirm, "danger")
    frame.clear:SetPoint("TOPLEFT", 0, 0)
    frame.bulk = Button(footer, "Bulk Search", 240, 32, function() showCopy() end, "primary")
    frame.bulk:SetPoint("TOPRIGHT", 0, 0)
    frame.message = text(footer, 13, T.muted, 0, 46, inner, 20)

    frame.contextMenu = createContextMenu(page)
    return page
end

local function create()
    frame = T.Panel(UIParent, width, height)
    A.whisperWindow = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdropColor(unpack(T.background))
    frame:SetBackdropBorderColor(unpack(T.trim))

    -- Inner hairline and gold corner brackets give the frame a game-dialog feel without Blizzard art.
    -- The bottom edge hangs from the bottom of the frame, so each tab can size the window to its own page.
    local function edge(layer, color, w, h, ...)
        local texture = frame:CreateTexture(nil, layer)
        texture:SetColorTexture(color[1], color[2], color[3], 1)
        if w then texture:SetWidth(w) end
        if h then texture:SetHeight(h) end
        for index = 1, select("#", ...), 3 do
            local point, x, y = select(index, ...)
            texture:SetPoint(point, x, y)
        end
    end
    edge("BORDER", T.line, nil, 1, "TOPLEFT", 3, -3, "TOPRIGHT", -3, -3)
    edge("BORDER", T.line, nil, 1, "BOTTOMLEFT", 3, 3, "BOTTOMRIGHT", -3, 3)
    edge("BORDER", T.line, 1, nil, "TOPLEFT", 3, -3, "BOTTOMLEFT", 3, 3)
    edge("BORDER", T.line, 1, nil, "TOPRIGHT", -3, -3, "BOTTOMRIGHT", -3, 3)
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local x, y = point:find("LEFT") and 3 or -3, point:find("TOP") and -3 or 3
        edge("ARTWORK", T.trim, 12, 2, point, x, y)
        edge("ARTWORK", T.trim, 2, 12, point, x, y)
    end

    frame.motionGeneration = 0

    -- Title bar. The logo and title live in their own container so they can rise on their own.
    local header = fill(frame, 1, 1, width - 2, 46, { 1, 1, 1 }, 1, "BACKGROUND")
    header:SetGradient("VERTICAL", CreateColor(T.surface[1], T.surface[2], T.surface[3], 1), CreateColor(0.150, 0.125, 0.092, 1))
    fill(frame, 1, 47, width - 2, 1, T.trim, 1, "BORDER")
    frame.head = CreateFrame("Frame", nil, frame)
    frame.head:SetPoint("TOPLEFT", 1, -1)
    frame.head:SetSize(width - 2 - 60, 46)
    frame.logo = frame.head:CreateTexture(nil, "ARTWORK")
    frame.logo:SetSize(28, 28)
    frame.logo:SetPoint("TOPLEFT", 19, -9)
    frame.logo:SetTexture(T.logo)
    frame.title = text(frame.head, 19, T.gold, 57, 11, 220, 26, nil, true)
    frame.title:SetText("Whispers")
    frame.dismiss = Button(frame, "×", 28, 28, close)
    frame.dismiss:SetPoint("TOPRIGHT", -16, -10)
    -- A short light bar that crosses the title rule when the window opens, as on the profile page.
    frame.sweep = CreateFrame("Frame", nil, frame)
    frame.sweep:SetPoint("TOPLEFT", 1, -45)
    frame.sweep:SetSize(72, 4)
    fill(frame.sweep, 0, 0, 72, 4, T.quality.EPIC, .2, "ARTWORK")
    fill(frame.sweep, 0, 1, 72, 1, T.gold, .8, "OVERLAY")
    frame.sweep:Hide()

    -- Status strip (always visible)
    local strip = T.Panel(frame, inner, 44, true)
    strip:SetPoint("TOPLEFT", gutter, -62)
    strip:SetBackdropColor(unpack(T.input))
    strip.tint = fill(strip, 1, 1, inner - 2, 42, { 1, 1, 1 }, 1, "BACKGROUND")
    strip.accent = fill(strip, 1, 1, 3, 42, T.gold, 1, "ARTWORK")
    strip.glow = fill(strip, 19, 16, 12, 12, T.gold, .22, "ARTWORK")
    strip.glow:SetRotation(math.pi / 4)
    strip.lamp = fill(strip, 21, 18, 8, 8, T.gold, 1, "OVERLAY")
    strip.lamp:SetRotation(math.pi / 4)
    frame.statusStrip = strip
    frame.status = Label(strip, 15, T.gold, true)
    frame.status:SetPoint("LEFT", 44, 0)
    frame.statusDetail = Label(strip, 13, T.cream)
    frame.statusDetail:SetPoint("LEFT", 136, 0)
    frame.statusDetail:SetSize(inner - 136 - (16 + countWidth + 14) - 12, 34)
    frame.statusDetail:SetMaxLines(2)
    strip:EnableMouse(true)
    strip:SetScript("OnEnter", function(self)
        if not self.label then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Whisper Collector", unpack(T.gold))
        GameTooltip:AddLine(A.Text(self.label), 1, 1, 1, true)
        if self.reason then GameTooltip:AddLine(A.Text(self.reason), .75, .72, .80, true) end
        GameTooltip:Show()
    end)
    strip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Navigation: two equal tabs sharing one gold underline that slides between them.
    local nav = CreateFrame("Frame", nil, frame)
    nav:SetPoint("TOPLEFT", gutter, -navTop)
    nav:SetSize(inner, navHeight)
    frame.nav = nav
    fill(nav, 0, navHeight - 1, inner, 1, T.line, 1, "BORDER")
    frame.tabLine = fill(nav, 0, navHeight - 3, tabWidth, 2, T.gold, 1, "ARTWORK")
    frame.tabs = {}
    for index, definition in ipairs({ { "roster", "Roster" }, { "settings", "Settings" } }) do
        local name = definition[1]
        local tab = flat(nav, definition[2], tabWidth, navHeight - 3, 15, function() selectTab(name) end, true)
        tab:SetPoint("TOPLEFT", (index - 1) * tabPitch, 0)
        tab.label:ClearAllPoints()
        tab.label:SetPoint("LEFT", 14, 0)
        tab.line:Hide()
        function tab:SetActive(active)
            self.active = active
            self:Paint()
        end
        frame.tabs[name] = tab
    end
    frame.tabs.roster.badge = Label(frame.tabs.roster, 13, T.muted)
    frame.tabs.roster.badge:SetPoint("LEFT", frame.tabs.roster.label, "RIGHT", 8, 0)

    frame.roster = createRoster(frame)
    frame.rowMenu = createRowMenu()
    frame.settings = createSettings(frame)
    frame.body = frame.roster

    -- Overlays
    frame.scrim = CreateFrame("Button", nil, frame)
    frame.scrim:SetAllPoints()
    frame.scrim:SetFrameLevel(frame:GetFrameLevel() + 40)
    frame.scrim:EnableMouse(true)
    local shade = frame.scrim:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, .62)
    frame.scrim:SetScript("OnClick", function() closeOverlays() end)
    frame.scrim:Hide()

    frame:SetScript("OnHide", function()
        closeOverlays()
        currentTab = "roster"
        frame.knownKeys, frame.fresh = nil, nil
        frame.statusStrip.key = nil
        cancelMotion()
        frame.tabs.roster:SetActive(true)
        frame.tabs.settings:SetActive(false)
        GameTooltip:Hide()
    end)
    if type(frame.EnableKeyboard) == "function" and type(frame.SetPropagateKeyboardInput) == "function" then
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(self, key)
            self:SetPropagateKeyboardInput(not (key == "ESCAPE" and U.HandleEscape()))
        end)
    end
    _G.SoulshardWhisperWindow = frame
    table.insert(UISpecialFrames, "SoulshardWhisperWindow")
    frame.tabs.roster:SetActive(true)
    frame:Hide()
end

-- Switches pages with no motion at all.
local function applyTab(name)
    currentTab = name
    fitHeight(name)
    frame.roster:SetShown(name == "roster")
    frame.settings:SetShown(name == "settings")
    frame.contextButton:SetShown(name == "roster")
    frame.tabs.roster:SetActive(name == "roster")
    frame.tabs.settings:SetActive(name == "settings")
    placeTabLine()
    if name == "settings" then syncSettings(true) end
end

function selectTab(name)
    if not frame then return end
    closeOverlays()
    local previous = currentTab
    -- Settle anything still moving so the change starts from a known state.
    cancelMotion()
    if previous == name or not frame:IsShown() or not animated() then
        applyTab(name)
        U.Refresh()
        return
    end
    local direction = name == "settings" and 1 or -1
    local outgoing = previous == "roster" and frame.roster or frame.settings
    local incoming = name == "roster" and frame.roster or frame.settings
    local generation = frame.motionGeneration
    currentTab = name
    fitHeight(name)
    frame.tabs.roster:SetActive(name == "roster")
    frame.tabs.settings:SetActive(name == "settings")
    if name == "settings" then syncSettings(true) end
    -- The incoming page is filled in while it is still hidden.
    U.Refresh()
    local timing = M.timing
    play(frame.tabLine, { fromAlpha = 1, toX = direction * tabPitch, duration = timing.underline, finish = placeTabLine })
    if previous == "roster" then
        play(frame.contextButton, { fromAlpha = 1, toAlpha = 0, duration = timing.exit, smoothing = "IN", finish = function()
            if frame.motionGeneration ~= generation then return end
            frame.contextButton:Hide()
            frame.contextButton:SetAlpha(1)
        end })
    end
    play(outgoing, { fromAlpha = 1, toAlpha = 0, toX = -direction * 12, duration = timing.exit, smoothing = "IN", finish = function()
        if frame.motionGeneration ~= generation then return end
        outgoing:Hide()
        outgoing:SetAlpha(1)
        incoming:Show()
        play(incoming, { fromX = direction * 24, duration = timing.enter })
        if name == "roster" then
            frame.contextButton:Show()
            reveal(frame.contextButton, 0, timing.message, 0)
        end
    end })
end

function U.Refresh()
    if not frame or not frame:IsShown() then return end
    local settings, status = W.GetSettings(), W.GetStatus()
    paintStatus(status)
    local total = #W.GetRows()
    frame.tabs.roster.badge:SetText(total > 0 and tostring(total) or "")
    if currentTab == "roster" then refreshRoster(settings, status)
    else syncSettings(false) end
end

function U.Show(manual, tab)
    if not initialized then return end
    if not manual and (manuallyClosed or not W.GetSettings().autoShow) then return end
    if manual then manuallyClosed = false end
    W.RefreshState(true)
    if W.GetStatus().state == "unsupported-client" then return end
    if InCombatLockdown() then
        if manual then A.Print("Collector settings are unavailable during combat.") else pending = true end
        return
    end
    pending = false
    if not frame then create() end
    local wasShown = frame:IsShown()
    anchor()
    frame:Show()
    -- A window that is opening lands directly on the requested page, so the entrance is the only motion.
    if tab and not wasShown then applyTab(tab) end
    U.Refresh()
    if not wasShown then openMotion() end
end

function U.OpenSettings()
    local wasShown = frame and frame:IsShown()
    U.Show(true, "settings")
    if wasShown and frame:IsShown() then selectTab("settings") end
end

local function install()
    if native or not LFGParentFrame or type(LFGParentFrame.HookScript) ~= "function" then return end
    native = LFGParentFrame
    native:HookScript("OnShow", function() manuallyClosed = false; U.Show() end)
    native:HookScript("OnHide", function() pending = false; if frame then frame:Hide() end end)
    native:HookScript("OnSizeChanged", anchor)
    if native:IsShown() then U.Show() end
end

function U.Event(event)
    if not initialized then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if frame and frame.copy then frame.copy:Hide() end
    elseif event == "PLAYER_REGEN_ENABLED" and pending and native and native:IsShown() then U.Show() end
    install()
end

function U.Initialize()
    if initialized then return end
    initialized = true
    W.SetChangedCallback(function()
        if not frame or not frame:IsShown() or frame.refreshQueued then return end
        if C_Timer and C_Timer.After then
            frame.refreshQueued = true
            C_Timer.After(.05, function() frame.refreshQueued = false; U.Refresh() end)
        else U.Refresh() end
    end)
    local displayEvents = CreateFrame("Frame")
    displayEvents:RegisterEvent("UI_SCALE_CHANGED")
    displayEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
    displayEvents:SetScript("OnEvent", anchor)
    local portraitEvents, portraitQueued = CreateFrame("Frame"), false
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_PORTRAIT_UPDATE", "PLAYER_TARGET_CHANGED" }) do portraitEvents:RegisterEvent(event) end
    portraitEvents:SetScript("OnEvent", function()
        if portraitQueued or not frame or not frame:IsShown() then return end
        portraitQueued = true
        local function run() portraitQueued = false; U.RepaintPortraits() end
        if C_Timer and C_Timer.After then C_Timer.After(.1, run) else run() end
    end)
    install()
end
