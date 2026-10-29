local _, A = ...
local T, W, P = A.Theme, A.Whispers, A.WhisperProfiles
local M = A.Motion
local U = {}
A.WhisperUI = U

-- The Whisper roster is the third tab of the native Looking For Group frame. Everything below is in
-- LFGParentFrame units (the frame is 384 wide and 512 tall) and follows the numbers in Blizzard's own XML
-- (Blizzard_GroupFinder_VanillaStyle): the dark inset the native list fills is x 22..346 and y 129..411, the native
-- button row sits 79 units above the bottom edge, and the tabs hang below the art. Nothing is drawn outside that.
-- The portrait ring covers the top left, so the banner starts to its right; the native options gear sits at the
-- top right of the header, which is where ours goes.
local frameLeft, frameWidth = 22, 324
local bannerX, bannerTop, bannerWidth = 82, 46, 240
local dropdownLeft, dropdownGap, dropdownTop, dropdownHeight = 26, 5, 96, 24
local raidWidth, viewWidth = 195, 116
local headerTop, headerHeight = 133, 20
local listTop, listHeight = 155, 254
local buttonLeft, buttonRight, buttonBottom, buttonHeight = 19, 40, 79, 22
local trackWidth = 6
local viewportWidth, viewportHeight = frameWidth, listHeight
local rowWidth = viewportWidth - trackWidth - 6
local playerHeight, headingHeight, sectionGap, poolSize = 42, 26, 8, 12
-- Settings opens beside the frame: the native window is about 353 wide, so its pop-up starts just past that.
local popupLeft, popupTop = 358, 8
-- Right-aligned metric columns: GearScore, average parse, best parse.
local gsWidth, parseWidth, columnGap, columnEdge = 44, 30, 2, 4
local bestX = rowWidth - columnEdge - parseWidth
local avgX = bestX - columnGap - parseWidth
local gsX = avgX - columnGap - gsWidth
local edge = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

local classOrder = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "UNKNOWN" }
local modes = { "any", "keywords", "prefix" }
local modeNames = { any = "Any whisper", keywords = "Keywords", prefix = "Prefix" }
local modeHelp = {
    any = "Every whisper from a character is collected.",
    keywords = "Whispers containing any keyword are collected.",
    prefix = "Whispers starting with this text are collected.",
}

local initialized, native, panel, tab = false, nil, nil, nil
local active, queued = false, false
-- Raid parses: nil follows the raid the group is listed for (Auto), false shows none, a string pins that raid.
local choice, grouping = nil, "class"
local contextID
local folded, acknowledged = {}, {}
local entries, items, order = {}, {}, {}
local offset, maxOffset = 0, 0
local anchorKey, anchorState
local menus, hideMenus, closeOverlays, showSettings, showCopy

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function className(token)
    if token == "UNKNOWN" then return "Unknown" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end

local function plural(count, singular, many)
    return count .. " " .. (count == 1 and singular or (many or singular .. "s"))
end

local function thousands(number)
    local digits = tostring(math.floor(number + .5))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", ""))
end

local function hex(color)
    return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255 + .5), math.floor(color[2] * 255 + .5), math.floor(color[3] * 255 + .5))
end
local mutedHex, dangerHex, goldHex = hex(T.muted), hex(T.danger), hex(T.gold)

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
    local function normal(value) return (value:lower():gsub("[%s%-']", "")) end
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

local function Label(parent, size, color, serif)
    return T.Text(parent, size, color, serif)
end

-- Text region anchored at the top-left of its parent. With a width it stays on one line.
local function text(parent, size, color, x, y, w, h, justify, serif)
    local region = Label(parent, size, color, serif)
    region:SetPoint("TOPLEFT", x, -y)
    if w then
        region:SetSize(w, h or size + 8)
        region:SetMaxLines(1)
        if region.SetWordWrap then region:SetWordWrap(false) end
    end
    if justify then region:SetJustifyH(justify) end
    return region
end

local function input(parent, x, y, inputWidth, hint)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(inputWidth, 30)
    box:SetPoint("TOPLEFT", x, -y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(1400)
    box:SetFont(T.bodyFont, 14, "")
    box:SetTextColor(unpack(T.cream))
    box:SetTextInsets(10, 10, 0, 0)
    box:SetBackdrop(edge)
    box:SetBackdropColor(unpack(T.input))
    box:SetBackdropBorderColor(unpack(T.line))
    box.placeholder = Label(box, 13, T.muted)
    box.placeholder:SetPoint("LEFT", 10, 0)
    box.placeholder:SetText(hint or "")
    box:SetScript("OnTextChanged", function(self, user)
        self.placeholder:SetShown(self:GetText() == "")
        if self.changed then self.changed(self, user) end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(T.gold)) end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(T.line)) end)
    return box
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
        self.state = state
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

-- Fold glyph: a bordered square holding a minus, or a plus while folded.
local function foldGlyph(parent)
    local glyph = T.Panel(parent, 16, 16, true)
    fill(glyph, 3, 7, 8, 2, T.gold, 1, "OVERLAY")
    glyph.vertical = fill(glyph, 6, 4, 2, 8, T.gold, 1, "OVERLAY")
    function glyph:SetFolded(isFolded) self.vertical:SetShown(isFolded) end
    return glyph
end

-- Settings gear drawn from flat shapes: four bars make eight teeth, a disc is the body, a smaller one the hole.
local function gear(parent, size, color)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.regions = {}
    local function place(texture, width, height, rotation)
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", 0, 0)
        texture:SetSize(width, height)
        if rotation then texture:SetRotation(rotation) end
        holder.regions[#holder.regions + 1] = texture
    end
    for step = 0, 3 do
        local bar = holder:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(color[1], color[2], color[3], 1)
        place(bar, size, math.max(2, size * .2), step * math.pi / 4)
    end
    local body = T.Disc(holder, "CENTER", 0, 0, size * .72, color, 1, "ARTWORK", 1)
    local hole = T.Disc(holder, "CENTER", 0, 0, size * .3, T.background, 1, "ARTWORK", 2)
    holder.regions[#holder.regions + 1] = body
    function holder:SetColor(value)
        for index, region in ipairs(self.regions) do
            if region ~= hole then region:SetColorTexture(value[1], value[2], value[3], 1) end
        end
    end
    return holder
end

local function reveal(region)
    M.Play(region, { duration = M.timing.message, fromY = -6 })
end

---------------------------------------------------------------------------
-- Buttons: the native red button for actions
---------------------------------------------------------------------------

local buttonFonts
local function buttonFont()
    if buttonFonts then return buttonFonts end
    local face = STANDARD_TEXT_FONT or T.headingFont
    local function make(name, color)
        local font = CreateFont(name)
        font:SetFont(face, T.minimumFontSize, "")
        font:SetTextColor(color[1], color[2], color[3])
        return font
    end
    buttonFonts = {
        normal = make("SoulshardLookupWhisperButton", { 1, .82, 0 }),
        highlight = make("SoulshardLookupWhisperButtonHighlight", { 1, 1, 1 }),
        disabled = make("SoulshardLookupWhisperButtonDisabled", { .5, .5, .5 }),
    }
    return buttonFonts
end

local function setEnabled(button, enabled)
    button.isEnabled = enabled
    if type(button.SetEnabled) == "function" then button:SetEnabled(enabled)
    elseif enabled and type(button.Enable) == "function" then button:Enable()
    elseif not enabled and type(button.Disable) == "function" then button:Disable() end
end

-- Blizzard's own red button, with its text at the addon's minimum size. A disabled button greys out and ignores clicks.
local function redButton(parent, label, w, h, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    local fonts = buttonFont()
    button:SetSize(w, h)
    button:SetNormalFontObject(fonts.normal)
    button:SetHighlightFontObject(fonts.highlight)
    button:SetDisabledFontObject(fonts.disabled)
    button:SetText(label)
    button.isEnabled = true
    button:SetScript("OnClick", function(self, ...) if self.isEnabled then onClick(self, ...) end end)
    return button
end

---------------------------------------------------------------------------
-- Status copy
---------------------------------------------------------------------------

local statusCopy = {
    recording = { "good", "Recording", "Collecting whispers while your group is listed." },
    ["not-grouped"] = { "warn", "Paused", "Join or start a raid" },
    viewing = { "good", "Viewing", "Sign-ups shared by your group's leaders. Read only." },
    ["not-listed"] = { "warn", "Paused", "List your group in Looking For Group to collect." },
    disabled = { "off", "Off", "Collection is switched off in Settings." },
    ["unsupported-client"] = { "bad", "Unavailable", "Requires the TBC Anniversary client (20506)." },
    ["storage-incompatible"] = { "bad", "Unavailable", "Saved data needs a newer version of the addon." },
}
local tones = { good = T.good, warn = T.gold, bad = T.danger, off = T.muted }
-- The empty roster explains what a paused state still needs in one paragraph; the banner keeps the short reason.
local pausedCopy = {
    ["not-grouped"] = "Collection starts once you are in a party or raid that you lead or assist, with the group listed in Looking For Group.",
    viewing = "Your leader or an assistant collects the sign-ups and shares them here. You can look, but not change anything.",
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
-- Raid parses: Auto follows the listing
---------------------------------------------------------------------------

local function autoRaid()
    local status = W.GetStatus()
    local activityIDs = W.GetContext().activityIDs
    -- A viewer does not own the listing; the leader's addon reports which raid it is for.
    if status.state == "viewing" and A.WhisperSync then activityIDs = A.WhisperSync.Listing() or {} end
    if status.state ~= "recording" and status.state ~= "viewing" then return nil, "No listing" end
    local raid = P.RaidForActivities(activityIDs)
    if raid then return raid end
    return nil, "Unknown raid"
end

-- The raid whose parses fill the Avg and Best columns, plus what Auto currently resolves to.
local function effectiveContext()
    local raid, reason = autoRaid()
    if choice == nil then return raid and raid.id or nil, raid, reason end
    if choice == false then return nil, raid, reason end
    return choice, raid, reason
end

local function raidName(id)
    for _, raid in ipairs(P.Contexts()) do if raid.id == id then return raid.name end end
    return "Raid parses"
end

---------------------------------------------------------------------------
-- Dropdowns and menus (drawn here; no dependency on native menu templates)
---------------------------------------------------------------------------

-- Blizzard's own dropdown art: the dark text holder with its bronze rim and the arrow button, the same atlases the native
-- Group Browser's dropdowns use (WowStyle1DropdownTemplate in Blizzard_Menu, Classic family, which is what the TBC
-- Anniversary client loads). Each name is checked against the client; if any is missing the dropdowns keep the flat
-- bordered style, so a client without them still gets a working control.
local dropdownArt, menuArt
local function atlasKnown(name)
    local lookup = (C_Texture and C_Texture.GetAtlasInfo) or GetAtlasInfo
    return type(lookup) == "function" and lookup(name) ~= nil
end

local function dropdownArtwork()
    if dropdownArt ~= nil then return dropdownArt or nil end
    dropdownArt = false
    local field, arrow = "common-dropdown-classic-textholder", "common-dropdown-classic-a-buttonDown"
    if atlasKnown(field) and atlasKnown(arrow) then
        local states = { [""] = arrow }
        for _, state in ipairs({ "hover", "pressed", "pressedhover" }) do
            states[state] = atlasKnown(arrow .. "-" .. state) and (arrow .. "-" .. state) or arrow
        end
        dropdownArt = { field = field, small = atlasKnown(field .. "-small") and (field .. "-small") or field, states = states }
    end
    return dropdownArt or nil
end

-- The popup menus take the native menu frame (a bronze border with a darkened inside), or stay flat without it.
local function menuArtwork()
    if menuArt ~= nil then return menuArt or nil end
    menuArt = atlasKnown("common-dropdown-classic-bg") and "common-dropdown-classic-bg" or false
    return menuArt or nil
end

local function dropdown(parent, x, w, prefix, onClick)
    local art = dropdownArtwork()
    local button = CreateFrame("Button", nil, parent, not art and "BackdropTemplate" or nil)
    button:SetSize(w, dropdownHeight)
    button:SetPoint("TOPLEFT", x, -dropdownTop)
    if art then
        -- Native placement: the field art reaches 9 left, 8 right, 8 above and 9 below the control's own rectangle.
        button.field = button:CreateTexture(nil, "BACKGROUND")
        button.field:SetPoint("TOPLEFT", -9, 8)
        button.field:SetPoint("BOTTOMRIGHT", 8, -9)
        button.field:SetAtlas(w <= 100 and art.small or art.field)
        button.arrow = button:CreateTexture(nil, "OVERLAY")
        button.arrow:SetPoint("RIGHT", -1, 0)
        button.arrow:SetAtlas(art.states[""], true)
        function button:PaintArrow()
            local state = (self.down and self.over and "pressedhover") or (self.over and "hover") or (self.down and "pressed") or ""
            self.arrow:SetAtlas(art.states[state], true)
        end
    else
        button:SetBackdrop(edge)
        button:SetBackdropColor(unpack(T.input))
        button:SetBackdropBorderColor(unpack(T.line))
        caret(button, T.gold)
    end
    local prefixWidth = 0
    -- The native dropdown sets its text in the game's small fonts (white value, gold caption), which is also what makes
    -- two labels fit a 24-high field. The flat fallback keeps the addon's own font and colours.
    local function style(region, fontObject, fallbackFont, color)
        if not art then region:SetTextColor(unpack(color)); return end
        if fontObject and region.SetFontObject then
            region:SetFontObject(fontObject)
        else
            if STANDARD_TEXT_FONT then region:SetFont(STANDARD_TEXT_FONT, 11, "") end
            region:SetTextColor(unpack(fallbackFont))
        end
    end
    if prefix then
        button.prefix = Label(button, 13, T.muted)
        button.prefix:SetPoint("LEFT", art and 9 or 8, 0)
        button.prefix:SetText(prefix)
        style(button.prefix, GameFontNormalSmall, { 1, .82, 0 }, T.muted)
        prefixWidth = art and 38 or 50
    end
    button.value = Label(button, 13, T.cream)
    button.value:SetPoint("LEFT", (art and 9 or 8) + prefixWidth, 0)
    if art then
        -- Fill whatever the arrow leaves, so the text ends with an ellipsis rather than under the arrow.
        button.value:SetPoint("RIGHT", button.arrow, "LEFT", -2, 0)
        button.value:SetHeight(20)
    else
        button.value:SetSize(w - 8 - prefixWidth - 26, 20)
    end
    button.value:SetMaxLines(1)
    if button.value.SetWordWrap then button.value:SetWordWrap(false) end
    button.value:SetJustifyH(prefix and "RIGHT" or "LEFT")
    style(button.value, GameFontHighlightSmall, { 1, 1, 1 }, T.cream)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        if art then self.over = true; self:PaintArrow() else self:SetBackdropBorderColor(unpack(T.gold)) end
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self.tip[1], unpack(T.gold))
            GameTooltip:AddLine(self.tip[2], 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        if art then self.over, self.down = false, false; self:PaintArrow() else self:SetBackdropBorderColor(unpack(T.line)) end
        GameTooltip:Hide()
    end)
    if art then
        button:HookScript("OnMouseDown", function(self) self.down = true; self:PaintArrow() end)
        button:HookScript("OnMouseUp", function(self) self.down = false; self:PaintArrow() end)
    end
    return button
end

local function paintItem(button)
    local entry = button.entry
    if not entry then return end
    local color = entry.color or (entry.danger and T.danger) or (entry.disabled and T.dim) or T.cream
    button.label:SetTextColor(unpack(color))
end

local function createMenu(width)
    local menu = T.Panel(panel, width, 40, true)
    menu:SetFrameLevel(panel:GetFrameLevel() + 30)
    local art = menuArtwork()
    local pad = art and 9 or 6
    if art then
        -- The native menu frame: bronze border around a darkened inside, reaching 3 past the menu's rectangle.
        menu:SetBackdropColor(0, 0, 0, 0)
        menu:SetBackdropBorderColor(0, 0, 0, 0)
        local frame = menu:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame:SetPoint("TOPLEFT", -3, 3)
        frame:SetPoint("BOTTOMRIGHT", 3, -4)
        frame:SetAtlas(art)
        local shade = menu:CreateTexture(nil, "BACKGROUND", nil, 0)
        shade:SetColorTexture(0, 0, 0, .8)
        shade:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
        shade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    else
        menu:SetBackdropBorderColor(unpack(T.trim))
    end
    menu.items, menu.rules = {}, {}
    menu:Hide()
    local function item(index)
        local button = menu.items[index]
        if button then return button end
        button = CreateFrame("Button", nil, menu)
        button:SetSize(width - pad * 2, 22)
        button.mark = T.Disc(button, "LEFT", 6, 0, 6, T.gold, 1, "OVERLAY")
        button.label = Label(button, 13, T.cream)
        button.right = Label(button, 13, T.muted)
        button.right:SetPoint("RIGHT", -8, 0)
        button.right:SetJustifyH("RIGHT")
        button:SetScript("OnEnter", function(self)
            local entry = self.entry
            if entry and not entry.disabled and not entry.title then self.label:SetTextColor(unpack(T.gold)) end
        end)
        button:SetScript("OnLeave", paintItem)
        button:SetScript("OnClick", function(self)
            local entry = self.entry
            if not entry or entry.disabled or entry.title then return end
            hideMenus()
            if entry.onClick then entry.onClick() end
        end)
        menu.items[index] = button
        return button
    end
    -- `list` holds { text, right, checked, color, danger, disabled, title, separator, onClick }.
    function menu:Open(list, point, relative, relativePoint, x, y)
        hideMenus()
        local top, used, rules, radio = pad, 0, 0, false
        for _, entry in ipairs(list) do if entry.checked ~= nil then radio = true end end
        for _, entry in ipairs(list) do
            if entry.separator then
                rules = rules + 1
                local rule = self.rules[rules]
                if not rule then
                    rule = fill(self, pad, 0, width - pad * 2, 1, T.line, 1, "BORDER")
                    self.rules[rules] = rule
                end
                rule:ClearAllPoints()
                rule:SetPoint("TOPLEFT", pad, -(top + 3))
                rule:Show()
                top = top + 8
            else
                used = used + 1
                local button = item(used)
                local height = entry.title and 26 or 22
                button.entry = entry
                button:SetHeight(height)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", pad, -top)
                button.label:ClearAllPoints()
                button.label:SetPoint("LEFT", radio and 20 or 8, 0)
                button.label:SetText(A.Text(entry.text or entry.title))
                button.right:SetText(A.Text(entry.right or ""))
                button.mark:SetShown(entry.checked == true)
                paintItem(button)
                button:Show()
                top = top + height
            end
        end
        for index = used + 1, #self.items do self.items[index].entry = nil; self.items[index]:Hide() end
        for index = rules + 1, #self.rules do self.rules[index]:Hide() end
        self:SetHeight(top + pad)
        self:ClearAllPoints()
        self:SetPoint(point, relative, relativePoint, x, y)
        panel.catcher:Show()
        if type(panel.EnableKeyboard) == "function" then panel:EnableKeyboard(true) end
        self:Show()
        reveal(self)
    end
    return menu
end

function hideMenus()
    if not panel or not menus then return end
    for _, menu in pairs(menus) do
        M.Stop(menu)
        menu:Hide()
    end
    panel.catcher:Hide()
    if type(panel.EnableKeyboard) == "function" then panel:EnableKeyboard(false) end
end

local function menuOpen()
    if not menus then return false end
    for _, menu in pairs(menus) do if menu:IsShown() then return true end end
    return false
end

function U.HandleEscape()
    if not panel or not menuOpen() then return false end
    hideMenus()
    return true
end

---------------------------------------------------------------------------
-- Tooltips and row actions
---------------------------------------------------------------------------

local function rowTooltip(row)
    local record, view = row.record, row.view
    if not record or not view then return end
    local color = classColor(view.classToken)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(A.Text(displayName(record.identity)), color[1], color[2], color[3])
    GameTooltip:AddLine(A.Text(className(view.classToken or "UNKNOWN") .. (view.level and (" · Level " .. view.level) or "") .. " · " .. plural(record.count or 0, "whisper")), 1, 1, 1)
    GameTooltip:AddLine(A.Text("Last whisper " .. ago(record.lastSeenAt) .. " ago · first seen " .. ago(record.firstSeenAt) .. " ago"), .75, .72, .80)
    if record.identity.resolution ~= "exact" then GameTooltip:AddLine("Identity unresolved — unavailable for bulk export.", 1, .65, .4, true) end
    if view.equipmentAt then GameTooltip:AddLine(A.Text("Equipment snapshot: " .. P.AgeLabel(view.equipmentAt)), .75, .72, .80, true) end
    if view.equipmentState == "partial" then GameTooltip:AddLine("Equipment snapshot is partial.", 1, .65, .4, true) end
    if view.raidsAt and contextID then GameTooltip:AddLine(A.Text("Raid snapshot: " .. P.AgeLabel(view.raidsAt)), .75, .72, .80, true) end
    if contextID then GameTooltip:AddLine("Avg uses recorded bosses' best parses, matching the saved raid journal.", .75, .72, .80, true) end
    -- A shared row never had the whisper text; only the leader who received it ever sees that.
    if record.remote then GameTooltip:AddLine(A.Text("Shared by " .. (record.reporter or "your group's leader")), .88, .86, .91, true)
    else GameTooltip:AddLine(A.Text(record.lastMessage and ("“" .. record.lastMessage .. "”") or "Preview unavailable after reload."), .88, .86, .91, true) end
    if not W.IsReadOnly() then GameTooltip:AddLine("Right-click for actions", .57, .54, .61) end
    GameTooltip:Show()
end

-- The target is what the sender's own whisper would have carried: a bare name on this realm, otherwise
-- Name-Realm with the spaces Blizzard strips from realm names removed.
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

local function setKeys(keys, selectedState)
    local selected = W.GetSelection()
    for _, key in ipairs(keys) do
        if (selected[key] == true) ~= selectedState then W.ToggleSelection(key) end
    end
end

local function openRowMenu(row)
    local entry = row.entry
    if not entry then return end
    local identity, key = entry.record.identity, entry.record.key
    -- A conflicting identity cannot be trusted as a whisper or invite target.
    local blocked = identity.resolution == "conflicting"
    menus.row.key = key
    menus.row:Open({
        { title = identity.name or "Unresolved player", color = classColor(row.view and row.view.classToken) },
        { text = "Whisper", disabled = blocked, onClick = function() whisperTo(identity) end },
        { text = "Invite to group", disabled = blocked, onClick = function() inviteTo(identity) end },
        { separator = true },
        { text = "Remove from roster", danger = true, onClick = function() W.Remove(key); U.Refresh() end },
    }, row.slotIndex <= 3 and "TOPRIGHT" or "BOTTOMRIGHT", row, row.slotIndex <= 3 and "BOTTOMRIGHT" or "TOPRIGHT", -14, row.slotIndex <= 3 and -2 or 2)
end

local function clickRow(row, button)
    local entry = row.entry
    if not entry or W.IsReadOnly() then return end
    if button == "RightButton" then openRowMenu(row); return end
    local key = entry.record.key
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and anchorKey then
        local from, to
        for position, other in ipairs(order) do
            if other == anchorKey then from = position end
            if other == key then to = position end
        end
        if from and to then
            local range = {}
            for position = math.min(from, to), math.max(from, to) do range[#range + 1] = order[position] end
            setKeys(range, anchorState)
            U.Refresh()
            return
        end
    end
    W.ToggleSelection(key)
    anchorKey, anchorState = key, W.GetSelection()[key] == true
    U.Refresh()
end

---------------------------------------------------------------------------
-- Roster list: class headings and player rows share one pool of slots
---------------------------------------------------------------------------

local function createPlayerRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(rowWidth, playerHeight)
    row.box = checkbox(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.name = Label(row, 14, T.cream)
    row.name:SetSize(100, 20)
    row.name:SetMaxLines(1)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.preview = Label(row, 13, T.muted)
    row.preview:SetSize(100, 18)
    row.preview:SetMaxLines(1)
    if row.preview.SetWordWrap then row.preview:SetWordWrap(false) end
    for _, spec in ipairs({ { "gs", gsX, gsWidth }, { "avg", avgX, parseWidth }, { "best", bestX, parseWidth } }) do
        local region = Label(row, 14, T.gold)
        region:SetPoint("TOPLEFT", spec[2], -5)
        region:SetSize(spec[3], 20)
        region:SetMaxLines(1)
        region:SetJustifyH("RIGHT")
        row[spec[1]] = region
    end
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", clickRow)
    row:HookScript("OnEnter", function(self) rowTooltip(self) end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function createHeading(parent)
    local head = CreateFrame("Button", nil, parent)
    head:SetSize(rowWidth, headingHeight)
    head.select = CreateFrame("Button", nil, head)
    head.select:SetSize(22, 22)
    head.select:SetPoint("LEFT", 2, 0)
    head.box = checkbox(head.select)
    head.box:SetPoint("CENTER")
    head.icon = head:CreateTexture(nil, "ARTWORK")
    head.icon:SetSize(16, 16)
    head.icon:SetPoint("LEFT", 30, 0)
    head.name = Label(head, 15, T.cream, true)
    head.name:SetPoint("LEFT", 52, 0)
    head.name:SetSize(rowWidth - 52 - 34, 20)
    head.name:SetMaxLines(1)
    head.rule = fill(head, 4, headingHeight - 2, rowWidth - 12, 1, T.gold, .6, "ARTWORK")
    head.fold = foldGlyph(head)
    head.fold:SetPoint("RIGHT", -8, 0)
    head:SetScript("OnClick", function(self)
        if not self.token then return end
        folded[self.token] = not folded[self.token] or nil
        U.Refresh()
    end)
    head.select:SetScript("OnClick", function(self)
        local heading = self:GetParent()
        if not heading.keys or W.IsReadOnly() then return end
        setKeys(heading.keys, not heading.allSelected)
        U.Refresh()
    end)
    return head
end

local function createSlot(index)
    local slot = CreateFrame("Frame", nil, panel.viewport)
    slot:SetSize(rowWidth, playerHeight)
    slot.index = index
    slot.row = createPlayerRow(slot)
    slot.row.slotIndex = index
    slot.heading = createHeading(slot)
    slot:Hide()
    return slot
end

-- GearScore and parse columns. Unknown is a dash, never zero.
local function metrics(row, view, settings)
    local columns = settings.showSnapshots
    for _, region in ipairs({ row.gs, row.avg, row.best }) do region:SetShown(columns) end
    if not columns then return end
    if view.gearScore ~= nil then
        local mark = (view.stale or view.equipmentState == "partial") and "*" or ""
        row.gs:SetText(thousands(view.gearScore) .. mark)
        row.gs:SetTextColor(unpack(view.stale and T.danger or T.gold))
    else
        row.gs:SetText("—")
        row.gs:SetTextColor(unpack(T.faint))
    end
    local parsed = contextID ~= nil and view.raidName ~= nil
    for _, spec in ipairs({ { row.avg, view.averageParse }, { row.best, view.bestParse } }) do
        local region, number = spec[1], spec[2]
        if parsed and number ~= nil then
            region:SetText(tostring(math.floor(number + .5)))
            region:SetTextColor(unpack(T.ParseColor(number)))
        else
            region:SetText("—")
            region:SetTextColor(unpack(T.faint))
        end
    end
end

local function nameText(record, view, isNew)
    local identity = record.identity
    local result = A.Text(identity.name or "Unresolved player")
    if identity.realmName and not sameRealm(identity.realmName) then result = result .. mutedHex .. "-" .. A.Text(identity.realmName) .. "|r" end
    result = result .. mutedHex .. " (" .. (view.level and tostring(view.level) or "—") .. ")  ×" .. (record.count or 0) .. "|r"
    if identity.resolution ~= "exact" then result = result .. dangerHex .. "  !|r" end
    if isNew then result = result .. goldHex .. "  NEW|r" end
    return result
end

local function paintPlayer(row, item, settings, selected)
    local entry = item.entry
    local record = entry.record
    local view = entry.view
    if not settings.showSnapshots then
        -- Saved snapshots are off: only what the whisper itself revealed.
        view = { classToken = entry.view.classToken, level = record.level, raceToken = entry.view.raceToken, sex = entry.view.sex }
    elseif contextID then
        entry.full = entry.full or P.Enrich(record, contextID)
        view = entry.full
    end
    local flat = grouping == "none"
    local boxX = flat and 4 or 20
    local nameX = flat and boxX + 46 or boxX + 26
    local token = entry.token
    local color = classColor(token ~= "UNKNOWN" and token or nil)
    row.entry, row.record, row.view = entry, record, view
    row.selected = selected[record.key] == true
    row.box:ClearAllPoints()
    row.box:SetPoint("TOPLEFT", boxX, -math.floor((playerHeight - 18) / 2))
    row.box:SetState(row.selected and "on" or "off")
    row.box:SetShown(not W.IsReadOnly())
    row.icon:SetShown(flat)
    if flat then
        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", boxX + 24, -13)
        T.ClassIcon(row.icon, token ~= "UNKNOWN" and token or nil)
    end
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", nameX, -5)
    row.name:SetWidth((settings.showSnapshots and gsX or rowWidth - columnEdge) - nameX - 6)
    row.name:SetText(nameText(record, view, not acknowledged[record.key]))
    row.name:SetTextColor(unpack(color))
    row.preview:ClearAllPoints()
    row.preview:SetPoint("TOPLEFT", nameX, -23)
    row.preview:SetWidth(rowWidth - nameX - columnEdge)
    row.preview:SetText(A.Text(ago(record.lastSeenAt) .. " · " .. (record.remote and ("Shared by " .. (record.reporter or "your group's leader")) or record.lastMessage or "Preview cleared after reload")))
    metrics(row, view, settings)
end

local function paintHeading(head, item, selected)
    local color = classColor(item.token ~= "UNKNOWN" and item.token or nil)
    head.token, head.keys = item.token, item.keys
    head.select:SetShown(not W.IsReadOnly())
    head.allSelected = item.selectedCount == #item.keys and #item.keys > 0
    head.box:SetState(head.allSelected and "on" or (item.selectedCount > 0 and "partial" or "off"))
    T.ClassIcon(head.icon, item.token ~= "UNKNOWN" and item.token or nil)
    head.name:SetText(A.Text(className(item.token)) .. mutedHex .. "  (" .. #item.keys .. ")|r")
    head.name:SetTextColor(unpack(color))
    head.rule:SetColorTexture(color[1], color[2], color[3], .6)
    head.fold:SetFolded(folded[item.token] == true)
end

local function renderList()
    local settings, selected = W.GetSettings(), W.GetSelection()
    local used, shown = 0, 0
    for _, slot in ipairs(panel.slots) do
        local item = items[offset + shown + 1]
        if item and used + item.height <= viewportHeight then
            shown = shown + 1
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", 0, -used)
            slot:SetHeight(item.height)
            slot.item = item
            if item.kind == "heading" then
                slot.row:Hide()
                slot.row.entry, slot.row.record = nil, nil
                slot.heading:ClearAllPoints()
                slot.heading:SetPoint("BOTTOMLEFT", 0, 0)
                slot.heading:Show()
                paintHeading(slot.heading, item, selected)
            else
                slot.heading:Hide()
                slot.row:ClearAllPoints()
                slot.row:SetPoint("TOPLEFT", 0, 0)
                slot.row:Show()
                paintPlayer(slot.row, item, settings, selected)
            end
            slot:Show()
            used = used + item.height
        else
            slot.item = nil
            slot.row.entry, slot.row.record = nil, nil
            slot:Hide()
        end
    end
    panel.shownCount = shown
    local overflow = maxOffset > 0
    panel.scrollbar:SetShown(overflow)
    panel.syncing = true
    panel.scrollbar:SetMinMaxValues(0, maxOffset)
    panel.scrollbar:SetValue(offset)
    panel.syncing = false
    local track = viewportHeight
    panel.thumb:SetSize(trackWidth, math.max(28, math.floor(track * math.max(1, shown) / math.max(math.max(1, shown), #items))))
end

local function setOffset(value)
    value = math.max(0, math.min(maxOffset, math.floor(value + .5)))
    if value == offset then return end
    offset = value
    if panel and panel:IsVisible() then renderList() end
end

-- Class sections in a fixed order (empty classes are skipped), or one flat list. Newest whisper first inside either.
local function buildItems()
    items, order = {}, {}
    if grouping == "none" then
        for _, entry in ipairs(entries) do
            items[#items + 1] = { kind = "player", entry = entry, height = playerHeight }
            order[#order + 1] = entry.record.key
        end
    else
        local byClass = {}
        for _, entry in ipairs(entries) do
            byClass[entry.token] = byClass[entry.token] or {}
            table.insert(byClass[entry.token], entry)
        end
        local selected = W.GetSelection()
        for _, token in ipairs(classOrder) do
            local list = byClass[token]
            if list then
                local keys, count = {}, 0
                for _, entry in ipairs(list) do
                    keys[#keys + 1] = entry.record.key
                    if selected[entry.record.key] then count = count + 1 end
                end
                items[#items + 1] = {
                    kind = "heading", token = token, keys = keys, selectedCount = count,
                    height = headingHeight + (#items > 0 and sectionGap or 0),
                }
                if not folded[token] then
                    for _, entry in ipairs(list) do
                        items[#items + 1] = { kind = "player", entry = entry, height = playerHeight }
                        order[#order + 1] = entry.record.key
                    end
                end
            end
        end
    end
    -- The largest offset still showing the last item; scrolling stops there.
    local used, count = 0, 0
    for index = #items, 1, -1 do
        used = used + items[index].height
        if used > viewportHeight then break end
        count = count + 1
    end
    maxOffset = math.max(0, #items - count)
    offset = math.max(0, math.min(offset, maxOffset))
end

---------------------------------------------------------------------------
-- Empty and paused states
---------------------------------------------------------------------------

local function layoutEmpty(empty, withButton)
    local bodyWidth = 252
    local bodyHeight
    if type(empty.body.GetStringHeight) == "function" then
        empty.body:SetSize(bodyWidth, 90)
        bodyHeight = math.max(18, math.ceil(empty.body:GetStringHeight()) + 2)
    else
        bodyHeight = 18 * math.max(1, math.ceil(#(empty.body:GetText() or "") / 34))
    end
    local total = 44 + 12 + 22 + 6 + bodyHeight + (withButton and 12 + 24 or 0)
    local y = math.max(12, math.floor((viewportHeight - total) / 2) - 6)
    empty.logo:ClearAllPoints()
    empty.logo:SetPoint("TOP", 0, -y)
    y = y + 44 + 12
    empty.title:ClearAllPoints()
    empty.title:SetPoint("TOPLEFT", 12, -y)
    y = y + 22 + 6
    empty.body:ClearAllPoints()
    empty.body:SetPoint("TOPLEFT", (rowWidth - bodyWidth) / 2, -y)
    empty.body:SetSize(bodyWidth, bodyHeight)
    y = y + bodyHeight + 12
    empty.create:ClearAllPoints()
    empty.create:SetPoint("TOP", 0, -y)
end

local function paintEmpty(status)
    local empty = panel.empty
    local _, headline, detail = describe(status)
    local title, body
    if status.state == "recording" then
        title = "Listening for whispers"
        body = "Players who whisper you about your listing appear here" .. (grouping == "class" and ", grouped by class." or ", newest first.")
    elseif status.state == "not-grouped" then
        title, body = "Not in a group", pausedCopy[status.state]
    elseif status.state == "viewing" then
        title, body = "No sign-ups shared yet", pausedCopy[status.state]
    else
        title = headline == "Off" and "Collection is off" or (headline == "Paused" and "Collection paused" or "Collection unavailable")
        body = pausedCopy[status.state] or detail
    end
    empty.title:SetText(A.Text(title))
    empty.title:SetTextColor(unpack(status.state == "recording" and T.cream or (describe(status) == "bad" and T.danger or T.cream)))
    empty.body:SetText(A.Text(body))
    local withButton = status.state == "not-listed"
    empty.create:SetShown(withButton)
    layoutEmpty(empty, withButton)
    empty:Show()
end

---------------------------------------------------------------------------
-- Panel refresh
---------------------------------------------------------------------------

local function paintBanner(status, players, whispers)
    local tone, title, detail = describe(status)
    local color = tones[tone]
    local banner = panel.banner
    banner.lamp:SetColorTexture(color[1], color[2], color[3], 1)
    banner.status:SetText(A.Text(title))
    banner.status:SetTextColor(unpack(color))
    banner.count:SetText(plural(players, "player") .. " · " .. plural(whispers, "whisper"))
    if status.state == "recording" then
        local _, raid = effectiveContext()
        if raid then detail = "Collecting for " .. raid.name .. "." end
    end
    banner.detail:SetText(A.Text(detail))
    banner.label, banner.reason = status.label, status.reason
end

local function paintControls(status, settings, total, selectedCount)
    local _, raid, reason = effectiveContext()
    local value
    if choice == nil then
        value = goldHex .. "Auto|r" .. mutedHex .. " · |r" .. (raid and A.Text(raid.name) or (mutedHex .. reason .. "|r"))
    elseif choice == false then value = "No raid parses"
    else value = A.Text(raidName(choice)) end
    panel.raidButton.value:SetText(value)
    panel.viewButton.value:SetText(grouping == "class" and "Group by class" or "No grouping")
    local box = panel.selectAll.box
    box:SetState(total > 0 and selectedCount == total and "on" or (selectedCount > 0 and "partial" or "off"))
    panel.selectAll.label:SetText(selectedCount > 0 and (selectedCount .. " selected") or (total == 0 and "Nothing to select" or ("Select all (" .. total .. ")")))
    panel.selectAll.label:SetTextColor(unpack(selectedCount > 0 and T.gold or T.muted))
    for _, caption in ipairs({ panel.captions.gs, panel.captions.avg, panel.captions.best }) do caption:SetShown(settings.showSnapshots) end
    panel.bulk:SetText(selectedCount > 0 and ("Bulk Search Selected (" .. selectedCount .. ")") or ("Bulk Search (" .. total .. ")"))
    setEnabled(panel.bulk, total > 0)
    -- A viewer sees the roster; choosing, exporting and removing are for the people who run the group.
    local readOnly = W.IsReadOnly()
    panel.selectAll:SetShown(not readOnly)
    panel.bulk:SetShown(not readOnly)
end

function U.Refresh()
    if not initialized then return end
    local records = W.GetRows()
    if tab then
        tab:SetText(#records > 0 and ("Whispers (" .. #records .. ")") or "Whispers")
        if tab.Resize then tab:Resize() end
    end
    if not panel or not panel:IsVisible() then return end
    local settings, status, selected = W.GetSettings(), W.GetStatus(), W.GetSelection()
    contextID = effectiveContext()
    entries = {}
    local whispers, selectedCount = 0, 0
    for _, record in ipairs(records) do
        whispers = whispers + (record.count or 0)
        if selected[record.key] then selectedCount = selectedCount + 1 end
        local view = P.Enrich(record)
        entries[#entries + 1] = { record = record, view = view, token = view.classToken or "UNKNOWN" }
    end
    paintBanner(status, #records, whispers)
    paintControls(status, settings, #records, selectedCount)
    buildItems()
    if #entries == 0 then paintEmpty(status) else panel.empty:Hide() end
    panel.viewport:SetShown(#entries > 0)
    renderList()
    if menus.row:IsShown() then
        local alive = false
        for _, record in ipairs(records) do if record.key == menus.row.key then alive = true end end
        if not alive then hideMenus() end
    end
    if panel.settings and panel.settings:IsShown() then panel.settings:Sync(false) end
end

---------------------------------------------------------------------------
-- Settings pop-up
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

-- Row with a check box, a title and an optional one-line description.
local function option(parent, x, y, w, title, description, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(w, description and 40 or 26)
    row:SetPoint("TOPLEFT", x, -y)
    row.box = checkbox(row)
    row.box:SetPoint("TOPLEFT", 0, -1)
    row.title = text(row, 14, T.cream, 28, 0, w - 28, 22)
    row.title:SetText(title)
    if description then
        row.description = text(row, 13, T.muted, 28, 21, w - 28, 18)
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

-- A pop-up with a title, a rule and a close button. `beside` puts it to the right of the Group Finder instead of over it.
local function dialog(globalName, width, height, title, beside)
    local box = T.Panel(panel, width, height, true)
    if beside then box:SetPoint("TOPLEFT", panel, "TOPLEFT", popupLeft, -popupTop)
    else box:SetPoint("CENTER", panel, "TOP", 0, -232) end
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetClampedToScreen(true)
    box:SetBackdropBorderColor(unpack(T.trim))
    box:EnableMouse(true)
    text(box, 16, T.gold, 0, 12, width, 24, "CENTER", true):SetText(title)
    T.Rule(box, 1, 44, width - 2)
    box.close = T.Button(box, "×", 24, 24, function() box:Hide() end)
    box.close:SetPoint("TOPRIGHT", -10, -10)
    box:SetScript("OnHide", function(self)
        M.Stop(self)
        if self.closed then self:closed() end
        local other = false
        for _, name in ipairs({ "settings", "copy" }) do
            if panel[name] and panel[name] ~= self and panel[name]:IsShown() then other = true end
        end
        if not other then panel.scrim:Hide() end
    end)
    box:Hide()
    _G[globalName] = box
    table.insert(UISpecialFrames, globalName)
    return box
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
    page.caseOption:SetPoint("TOPLEFT", page.mode == "keywords" and 176 or 16, -346)
    page.matchAllOption:SetChecked(page.matchAll)
    page.caseOption:SetChecked(page.caseSensitive)
    local dirty = filterDirty(page)
    page.dirty = dirty
    setEnabled(page.save, dirty)
    page.status:SetText(dirty and (page.message:GetText() or "") == "" and "Unsaved changes" or "")
end

local function createSettings()
    local page = dialog("SoulshardWhisperSettings", 324, 456, "Whisper Collector", true)
    local pad, contentWidth = 16, 292
    page.mode, page.matchAll, page.caseSensitive = "any", false, false

    text(page, 13, T.muted, pad, 56, contentWidth, 18):SetText("COLLECTION")
    page.collect = option(page, pad, 78, contentWidth, "Collect while eligible", "Records whispers as leader or raid assistant.", function()
        W.UpdateSettings({ enabled = not W.GetSettings().enabled })
        U.Refresh()
    end)
    text(page, 14, T.cream, pad, 130, 140, 22):SetText("Keep the roster")
    page.retention = {}
    for index, spec in ipairs({ { "24h", "24 hours", 92 }, { "session", "This session", 100 } }) do
        local button = T.Button(page, spec[2], spec[3], 26, function()
            W.UpdateSettings({ retention = spec[1] })
            U.Refresh()
        end)
        button:SetPoint("TOPRIGHT", index == 1 and -(pad + 100 + 8) or -pad, -126)
        page.retention[spec[1]] = button
    end
    page.snapshots = option(page, pad, 164, contentWidth, "Show saved GearScore and parses", "Read from the installed data pack.", function()
        W.UpdateSettings({ showSnapshots = not W.GetSettings().showSnapshots })
        U.Refresh()
    end)

    text(page, 13, T.muted, pad, 214, contentWidth, 18):SetText("CAPTURE FILTER")
    page.modeButtons = {}
    local segment = math.floor((contentWidth - 16) / 3)
    for index, mode in ipairs(modes) do
        local button = T.Button(page, modeNames[mode], segment, 26, function()
            page.mode = mode
            page.message:SetText("")
            paintFilter(page)
        end)
        button:SetPoint("TOPLEFT", pad + (index - 1) * (segment + 8), -236)
        page.modeButtons[mode] = button
    end
    page.help = text(page, 13, T.muted, pad, 268, contentWidth, 20)
    page.keywordsLabel = text(page, 13, T.muted, pad, 292, contentWidth, 20)
    page.keywordsLabel:SetText("Keywords (comma-separated, literal text)")
    page.keywords = input(page, pad, 312, contentWidth, "For example: invite, healer")
    page.prefixLabel = text(page, 13, T.muted, pad, 292, contentWidth, 20)
    page.prefixLabel:SetText("Starts with (literal text)")
    page.prefix = input(page, pad, 312, contentWidth, "For example: +")
    for _, box in ipairs({ page.keywords, page.prefix }) do
        box.changed = function() page.message:SetText(""); paintFilter(page) end
    end
    page.anyNote = text(page, 13, T.muted, pad, 296, contentWidth, 42)
    page.anyNote:SetMaxLines(2)
    if page.anyNote.SetWordWrap then page.anyNote:SetWordWrap(true) end
    page.anyNote:SetText("Filters apply to future whispers only. Players already in the roster stay there.")
    page.matchAllOption = option(page, pad, 346, 150, "Match all keywords", nil, function()
        page.matchAll = not page.matchAll
        paintFilter(page)
    end)
    page.caseOption = option(page, 176, 346, 130, "Case-sensitive", nil, function()
        page.caseSensitive = not page.caseSensitive
        paintFilter(page)
    end)
    page.status = text(page, 13, T.gold, pad, 384, 150, 20)
    page.message = text(page, 13, T.danger, pad, 384, 150, 20)
    page.save = redButton(page, "Save filter", 130, 24, function()
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
    end)
    page.save:SetPoint("TOPRIGHT", -pad, -380)
    T.Rule(page, 1, 414, 322)

    -- The roster clears itself; this is the escape hatch, and it asks twice.
    page.reset = T.Button(page, "Reset roster", 130, 24, function(self)
        if not page.confirming then
            page.confirming = true
            self.label:SetText("Click to confirm")
            return
        end
        page.confirming = false
        self.label:SetText("Reset roster")
        W.Clear()
        U.Refresh()
    end, "danger")
    page.reset:SetPoint("TOPLEFT", pad, -424)
    text(page, 13, T.muted, 160, 428, 148, 20, "RIGHT"):SetText("Esc closes")
    function page:closed()
        self.confirming = false
        self.reset.label:SetText("Reset roster")
    end

    -- Copies saved values into the page. The filter draft is only replaced while it is clean.
    function page:Sync(force)
        local settings = W.GetSettings()
        self.reset:SetShown(not W.IsReadOnly())
        self.collect:SetChecked(settings.enabled)
        self.snapshots:SetChecked(settings.showSnapshots)
        for key, button in pairs(self.retention) do button:SetSelected(settings.retention == key) end
        if force or not self.dirty then
            self.mode, self.matchAll, self.caseSensitive = settings.mode, settings.matchAll, settings.caseSensitive
            local keywords = table.concat(settings.keywords, ", ")
            if self.keywords:GetText() ~= keywords then self.keywords:SetText(keywords) end
            if self.prefix:GetText() ~= settings.prefix then self.prefix:SetText(settings.prefix) end
        end
        paintFilter(self)
    end
    return page
end

function closeOverlays(except)
    if not panel then return end
    for _, name in ipairs({ "settings", "copy" }) do
        local overlay = panel[name]
        if overlay and name ~= except and overlay:IsShown() then overlay:Hide() end
    end
    hideMenus()
end

function showSettings()
    if not panel then return end
    closeOverlays("settings")
    if not panel.settings then panel.settings = createSettings() end
    local page = panel.settings
    page:Sync(true)
    page:Show()
    reveal(page)
end

---------------------------------------------------------------------------
-- Bulk Search dialog
---------------------------------------------------------------------------

function showCopy()
    if InCombatLockdown() then A.Print("Bulk URL copying is unavailable during combat."); return end
    closeOverlays("copy")
    local result, reason = P.BuildExport(W.GetRows(), W.GetSelection(), W.GetContext().epoch)
    if not result then A.Print(reason or "No exportable players."); return end
    if result.count == 0 or #result.urls == 0 then
        A.Print("No exportable players. " .. #result.excluded .. " identities are unresolved or unsupported.")
        return
    end
    if not panel.copy then
        local box = dialog("SoulshardWhisperCopy", 300, 232, "Bulk Search")
        box.summary = text(box, 14, T.cream, 16, 56, 268, 22)
        box.help = text(box, 13, T.muted, 16, 80, 268, 52)
        box.help:SetMaxLines(3)
        if box.help.SetWordWrap then box.help:SetWordWrap(true) end
        box.help:SetText("Press Ctrl+C (Cmd+C on Mac) to copy, then paste the link into your browser.")
        box.edit = input(box, 16, 134, 268)
        box.edit:SetMaxLetters(6000)
        box.noteArea = CreateFrame("Frame", nil, box)
        box.noteArea:SetPoint("TOPLEFT", 16, -170)
        box.noteArea:SetSize(268, 22)
        box.note = text(box.noteArea, 13, T.muted, 0, 0, 268, 22)
        box.previous = redButton(box, "Previous", 78, 24, function() box:SelectLink(box.link - 1) end)
        box.previous:SetPoint("BOTTOMLEFT", 16, 16)
        box.next = redButton(box, "Next link", 90, 24, function() box:SelectLink(box.link + 1) end)
        box.next:SetPoint("LEFT", box.previous, "RIGHT", 8, 0)
        box.done = redButton(box, "Close", 74, 24, function() box:Hide() end)
        box.done:SetPoint("BOTTOMRIGHT", -16, 16)
        -- Everyone selected goes in one link. A second link only exists when the website could not hold them in one:
        -- players from several realms (a link names one realm) or a list past the page's size.
        function box:SelectLink(index)
            local urls = self.result.urls
            self.link = math.max(1, math.min(#urls, index))
            self.edit:SetText(urls[self.link])
            self.edit:SetFocus()
            self.edit:HighlightText()
            if #urls == 1 then
                self.summary:SetText(plural(self.result.count, "player"))
            else
                self.summary:SetText("Link " .. self.link .. " of " .. #urls .. " · " .. plural(self.result.counts[self.link], "player"))
            end
            self.previous:SetShown(#urls > 1)
            self.next:SetShown(#urls > 1)
            setEnabled(self.previous, self.link > 1)
            setEnabled(self.next, self.link < #urls)
        end
        box.edit:SetScript("OnTextChanged", function(self)
            if box.result and self:GetText() ~= box.result.urls[box.link] then self:SetText(box.result.urls[box.link]) end
        end)
        box.edit:SetScript("OnEscapePressed", function() box:Hide() end)
        box.edit:SetScript("OnEnterPressed", function() box:Hide() end)
        function box:closed() self.edit:ClearFocus() end
        box.noteArea:EnableMouse(true)
        box.noteArea:SetScript("OnEnter", function()
            if not box.result or #box.result.excluded == 0 then return end
            GameTooltip:SetOwner(box, "ANCHOR_LEFT")
            GameTooltip:AddLine("Excluded from export", unpack(T.gold))
            for index, excluded in ipairs(box.result.excluded) do
                if index > 10 then GameTooltip:AddLine("Additional exclusions: " .. (#box.result.excluded - 10)); break end
                GameTooltip:AddLine(A.Text(excluded.name .. ": " .. excluded.reason), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        box.noteArea:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.copy = box
    end
    local box = panel.copy
    box.result = result
    box.note:SetText(#result.excluded > 0 and (#result.excluded .. " excluded") or "")
    panel.scrim:Show()
    box:Show()
    box:SelectLink(1)
    reveal(box)
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function acknowledgeAll()
    for _, record in ipairs(W.GetRows()) do acknowledged[record.key] = true end
end

-- The native pages (Create Listing, Group Browser) draw the frame art themselves, so it vanishes with them. This draws
-- the same Blizzard textures from the Browse page at the same offsets, in a frame that sits where the pages sit, so
-- the Whispers tab is the native frame and nothing is laid over it. Texture files are read from the Browse page when it
-- exists; the paths below are the ones its XML uses.
local artFile, artAtlas = "Interface\\LFGFrame\\UI-LFG-FRAME", "groupfinder-background-classic"

local function nativeTexture(name, fallback)
    local region = _G["LFGBrowseFrame" .. name]
    if region and type(region.GetTexture) == "function" then
        local ok, value = pcall(region.GetTexture, region)
        if ok and (type(value) == "string" or type(value) == "number") then return value end
    end
    return fallback
end

local function artTexture(art, name, fallback, sublevel, width, height, x, y, top, bottom)
    local texture = art:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    texture:SetTexture(nativeTexture(name, fallback))
    texture:SetSize(width, height)
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetTexCoord(0, 1, top, bottom)
    return texture
end

local function createArt()
    local art = CreateFrame("Frame", nil, native)
    art:SetAllPoints(native)
    art.top = artTexture(art, "FrameBackgroundTop", "Interface\\LFGFrame\\UI-LFR-FRAME-MAIN", -1, 512, 121, -1, 0, 0, .236328125)
    art.middle = artTexture(art, "FrameBackgroundMiddle", artFile, -1, 512, 135, 0, 121, .236328125, .5)
    art.inset = art:CreateTexture(nil, "BACKGROUND", nil, 0)
    if type(art.inset.SetAtlas) == "function" then art.inset:SetAtlas(artAtlas) end
    art.inset:SetSize(324, 282)
    art.inset:SetPoint("TOPLEFT", 22, -129)
    art.bottom = artTexture(art, "FrameBackgroundBottom", artFile, 1, 512, 256, 0, 256, .5, 1)
    art.title = art:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    art.title:SetPoint("TOP", 0, -18)
    art.title:SetText(_G.LFG_TITLE or "Looking For Group")
    art:Hide()
    return art
end

local function createPanel()
    panel = CreateFrame("Frame", "SoulshardLookupWhispersPanel", native)
    panel:SetAllPoints(native)
    -- Above the art frame and the native widgets, below the pop-ups.
    panel:SetFrameLevel(native:GetFrameLevel() + 15)
    A.whisperPanel = panel
    panel.art = createArt()
    -- Players restored from an earlier session are not new.
    for _, record in ipairs(W.GetRows()) do if record.restored then acknowledged[record.key] = true end end

    -- Banner: status, counts, one line of detail and the gear.
    local banner = CreateFrame("Frame", nil, panel)
    banner:SetPoint("TOPLEFT", bannerX, -bannerTop)
    banner:SetSize(bannerWidth, 50)
    panel.banner = banner
    banner.lamp = T.Disc(banner, "TOPLEFT", 0, -7, 9, T.gold, 1, "ARTWORK")
    banner.status = Label(banner, 15, T.gold, true)
    banner.status:SetPoint("TOPLEFT", 14, -2)
    banner.status:SetSize(92, 20)
    banner.status:SetMaxLines(1)
    banner.count = Label(banner, 13, T.cream)
    banner.count:SetPoint("TOPRIGHT", 0, -3)
    banner.count:SetSize(134, 18)
    banner.count:SetMaxLines(1)
    banner.count:SetJustifyH("RIGHT")
    banner.detail = text(banner, 13, T.cream, 0, 26, bannerWidth, 20)
    banner:EnableMouse(true)
    banner:SetScript("OnEnter", function(self)
        if not self.label then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Whisper Collector", unpack(T.gold))
        GameTooltip:AddLine(A.Text(self.label), 1, 1, 1, true)
        if self.reason then GameTooltip:AddLine(A.Text(self.reason), .75, .72, .80, true) end
        GameTooltip:Show()
    end)
    banner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- On the spot the native Browse page keeps its own options gear (16 wide, 40 from the right, 44 from the top).
    panel.gearButton = CreateFrame("Button", nil, panel)
    panel.gearButton:SetSize(22, 22)
    panel.gearButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -37, -41)
    panel.gearButton.gear = gear(panel.gearButton, 16, T.muted)
    panel.gearButton.gear:SetPoint("CENTER")
    panel.gearButton:SetScript("OnClick", function() showSettings() end)
    panel.gearButton:SetScript("OnEnter", function(self)
        self.gear:SetColor(T.gold)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Collector settings", unpack(T.gold))
        GameTooltip:Show()
    end)
    panel.gearButton:SetScript("OnLeave", function(self) self.gear:SetColor(T.muted); GameTooltip:Hide() end)

    -- Click-away catcher shared by every menu.
    panel.catcher = CreateFrame("Button", nil, panel)
    panel.catcher:SetAllPoints(panel)
    panel.catcher:SetFrameLevel(panel:GetFrameLevel() + 20)
    panel.catcher:RegisterForClicks("AnyUp")
    panel.catcher:SetScript("OnClick", function() hideMenus() end)
    panel.catcher:Hide()
    if type(panel.SetPropagateKeyboardInput) == "function" then
        panel:SetScript("OnKeyDown", function(self, key)
            self:SetPropagateKeyboardInput(not (key == "ESCAPE" and U.HandleEscape()))
        end)
    end

    -- Two dropdowns.
    panel.raidButton = dropdown(panel, dropdownLeft, raidWidth, "Parses", function(self)
        local _, raid, reason = effectiveContext()
        local list = {
            { text = "Auto · " .. (raid and raid.name or reason), checked = choice == nil, onClick = function() choice = nil; U.Refresh() end },
            { separator = true },
        }
        for _, context in ipairs(P.Contexts()) do
            list[#list + 1] = {
                text = context.name, right = context.size and (context.size .. "-man") or nil, checked = choice == context.id,
                onClick = function() choice = context.id; U.Refresh() end,
            }
        end
        list[#list + 1] = { separator = true }
        list[#list + 1] = { text = "No raid parses", checked = choice == false, onClick = function() choice = false; U.Refresh() end }
        menus.raid:Open(list, "TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    end)
    panel.raidButton.tip = { "Raid parses", "Auto follows the raid your group is listed for. Pick a raid to show its parses instead." }
    panel.viewButton = dropdown(panel, dropdownLeft + raidWidth + dropdownGap, viewWidth, nil, function(self)
        menus.view:Open({
            { text = "Group by class", checked = grouping == "class", onClick = function() grouping, offset = "class", 0; U.Refresh() end },
            { text = "No grouping", checked = grouping == "none", onClick = function() grouping, offset = "none", 0; U.Refresh() end },
        }, "TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
    end)
    panel.viewButton.tip = { "Roster view", "Group players under their class, or list everyone newest first." }

    -- List header: select all on the left, column captions on the right.
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", frameLeft, -headerTop)
    header:SetSize(frameWidth, headerHeight)
    panel.listHeader = header
    panel.selectAll = CreateFrame("Button", nil, header)
    panel.selectAll:SetSize(180, headerHeight)
    panel.selectAll:SetPoint("TOPLEFT", 0, 0)
    panel.selectAll.box = checkbox(panel.selectAll)
    panel.selectAll.box:SetPoint("LEFT", 4, 0)
    panel.selectAll.label = text(panel.selectAll, 13, T.muted, 30, 1, 146, 18)
    panel.selectAll:SetScript("OnClick", function()
        local selected, everyone = W.GetSelection(), true
        local keys = {}
        for _, entry in ipairs(entries) do
            keys[#keys + 1] = entry.record.key
            if not selected[entry.record.key] then everyone = false end
        end
        setKeys(keys, not everyone)
        U.Refresh()
    end)
    panel.captions = {}
    for _, spec in ipairs({ { "gs", "GS", gsX, gsWidth }, { "avg", "Avg", avgX, parseWidth }, { "best", "Best", bestX, parseWidth } }) do
        local caption = text(header, 13, T.muted, 1 + spec[3], 1, spec[4], 18, "RIGHT")
        caption:SetText(spec[2])
        panel.captions[spec[1]] = caption
    end

    -- The list.
    -- No box of its own: the list sits straight on the native dark inset.
    local box = CreateFrame("Frame", nil, panel)
    box:SetSize(frameWidth, listHeight)
    box:SetPoint("TOPLEFT", frameLeft, -listTop)
    panel.listBox = box
    panel.viewport = CreateFrame("Frame", nil, box)
    panel.viewport:SetPoint("TOPLEFT", 0, 0)
    panel.viewport:SetSize(viewportWidth, viewportHeight)
    if panel.viewport.SetClipsChildren then panel.viewport:SetClipsChildren(true) end
    panel.viewport:EnableMouseWheel(true)
    panel.viewport:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta * 2) end)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta * 2) end)
    panel.slots = {}
    for index = 1, poolSize do panel.slots[index] = createSlot(index) end

    panel.scrollbar = CreateFrame("Slider", nil, box)
    panel.scrollbar:SetPoint("TOPRIGHT", -4, -2)
    panel.scrollbar:SetSize(trackWidth, viewportHeight - 4)
    panel.scrollbar:SetOrientation("VERTICAL")
    panel.scrollbar:SetValueStep(1)
    if panel.scrollbar.SetObeyStepOnDrag then panel.scrollbar:SetObeyStepOnDrag(true) end
    panel.track = fill(panel.scrollbar, 0, 0, trackWidth, viewportHeight - 4, T.line, .8)
    panel.thumb = fill(panel.scrollbar, 0, 0, trackWidth, 36, T.gold, .55, "OVERLAY")
    panel.scrollbar:SetThumbTexture(panel.thumb)
    panel.scrollbar:SetMinMaxValues(0, 0)
    panel.scrollbar:SetScript("OnValueChanged", function(_, scrolled)
        if not panel.syncing then setOffset(scrolled) end
    end)
    panel.scrollbar:Hide()

    -- Empty and paused states share the list area.
    local empty = CreateFrame("Frame", nil, box)
    empty:SetPoint("TOPLEFT", 0, 0)
    empty:SetSize(rowWidth, viewportHeight)
    empty.logo = empty:CreateTexture(nil, "ARTWORK")
    empty.logo:SetSize(44, 44)
    empty.logo:SetTexture(T.logo)
    empty.logo:SetAlpha(.7)
    empty.title = text(empty, 16, T.cream, 12, 0, rowWidth - 24, 22, "CENTER", true)
    empty.body = text(empty, 13, T.muted, 0, 0, 252, 18, "CENTER")
    empty.body:SetMaxLines(5)
    if empty.body.SetWordWrap then empty.body:SetWordWrap(true) end
    if empty.body.SetJustifyV then empty.body:SetJustifyV("TOP") end
    -- The listing form is the first tab; this jumps there.
    empty.create = redButton(empty, "Create Listing", 130, 24, function()
        local first = native.Tab1 or _G.LFGParentFrameTab1
        if first and type(first.Click) == "function" then first:Click()
        elseif first and first.scripts and first.scripts.OnClick then first.scripts.OnClick(first) end
    end)
    empty:Hide()
    panel.empty = empty

    -- The native button row (Send Message, Group Invite) spans the same edges at the same height.
    panel.bulk = redButton(panel, "Bulk Search (0)", 325, buttonHeight, function() showCopy() end)
    panel.bulk:ClearAllPoints()
    panel.bulk:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", buttonLeft, buttonBottom)
    panel.bulk:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -buttonRight, buttonBottom)

    -- Invisible click-away layer for the Bulk Search dialog, which sits over the roster and must not go stale while the
    -- selection changes. Nothing dims the frame, and Settings (beside the frame) leaves the roster usable.
    panel.scrim = CreateFrame("Button", nil, panel)
    panel.scrim:SetAllPoints(panel)
    panel.scrim:SetFrameLevel(panel:GetFrameLevel() + 40)
    panel.scrim:EnableMouse(true)
    panel.scrim:SetScript("OnClick", function() closeOverlays() end)
    panel.scrim:Hide()

    menus = { raid = createMenu(240), view = createMenu(134), row = createMenu(176) }
    panel.menus = menus

    -- Hide before the OnHide script exists: building the panel must not count as the player having seen the roster.
    panel:Hide()
    panel:SetScript("OnHide", function()
        closeOverlays()
        panel.scrim:Hide()
        acknowledgeAll()
        GameTooltip:Hide()
    end)
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local function nativeTab(index)
    return native["Tab" .. index] or _G["LFGParentFrameTab" .. index]
end

local function nativeContent()
    local frames = {}
    for _, name in ipairs({ "LFGListingFrame", "LFGBrowseFrame" }) do
        local frame = native[name] or _G[name]
        if frame and type(frame.Hide) == "function" then frames[#frames + 1] = frame end
    end
    return frames
end

local function paintTab(selected)
    if not tab then return end
    if tab.fallback then tab:SetSelected(selected); return end
    local call = selected and PanelTemplates_SelectTab or PanelTemplates_DeselectTab
    if type(call) == "function" then pcall(call, tab) end
end

local function deselectNativeTabs()
    if type(PanelTemplates_DeselectTab) ~= "function" then return end
    for index = 1, 2 do
        local other = nativeTab(index)
        if other then pcall(PanelTemplates_DeselectTab, other) end
    end
end

local function activate()
    if not native or active then return end
    if not panel then createPanel() end
    active = true
    -- The native pages carry their own widgets, so both go away; the art frame redraws the Blizzard frame in their place.
    for _, frame in ipairs(nativeContent()) do frame:Hide() end
    deselectNativeTabs()
    paintTab(true)
    W.RefreshState(true)
    panel.art:Show()
    panel:Show()
    U.Refresh()
end

-- Another tab took over (or the Group Finder closed): put the panel away and leave the native tabs to the client.
local function deactivate()
    if not active then return end
    active = false
    paintTab(false)
    if panel then
        panel:Hide()
        panel.art:Hide()
    end
end

local function createTab()
    local button
    for _, template in ipairs({ "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate", "TabButtonTemplate" }) do
        local ok, created = pcall(CreateFrame, "Button", "SoulshardLookupWhispersTab", native, template)
        if ok and created then button = created; break end
    end
    local second = nativeTab(2) or nativeTab(1)
    -- The native tabs sit one level under the frame art so its bottom edge overlaps them; the new tab does the same.
    if button and second and type(second.GetFrameLevel) == "function" and type(button.SetFrameLevel) == "function" then
        button:SetFrameLevel(second:GetFrameLevel())
    end
    if button then
        function button:Resize()
            if type(PanelTemplates_TabResize) == "function" then pcall(PanelTemplates_TabResize, self, 0) end
        end
        if second then button:SetPoint("LEFT", second, "RIGHT", -16, 0)
        else button:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", 250, -30) end
    else
        -- No native tab template on this client: a plain button in the same place keeps the roster reachable.
        button = T.Button(native, "Whispers", 100, 26, function() end)
        button.fallback = true
        function button:SetText(value) self.label:SetText(value) end
        function button:Resize() end
        if second then button:SetPoint("LEFT", second, "RIGHT", 4, 0)
        else button:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", 250, -30) end
    end
    button:SetScript("OnClick", function()
        if type(PlaySound) == "function" and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        activate()
    end)
    button:SetText("Whispers")
    button:Resize()
    A.whisperTab = button
    return button
end

local function install()
    if native or not LFGParentFrame or type(LFGParentFrame.HookScript) ~= "function" then return end
    native = LFGParentFrame
    tab = createTab()
    -- Hooks only: the native scripts, tab bookkeeping and tab count stay untouched.
    native:HookScript("OnHide", function() deactivate(); hideMenus() end)
    for index = 1, 2 do
        local other = nativeTab(index)
        if other and type(other.HookScript) == "function" then other:HookScript("OnClick", deactivate) end
    end
    for _, frame in ipairs(nativeContent()) do
        if type(frame.HookScript) == "function" then frame:HookScript("OnShow", deactivate) end
    end
    U.Refresh()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Shows the Group Finder on the Whispers tab.
function U.Open()
    if not initialized then return false end
    install()
    if not native then A.Print("The Looking For Group window is not available yet. Open it once, then try again."); return false end
    if not native:IsShown() then
        if type(ShowUIPanel) == "function" then pcall(ShowUIPanel, native) end
        if not native:IsShown() then native:Show() end
    end
    activate()
    return true
end

function U.OpenSettings()
    if InCombatLockdown() then A.Print("Collector settings are unavailable during combat."); return end
    if U.Open() then showSettings() end
end

function U.Event(event)
    if not initialized then return end
    if event == "PLAYER_REGEN_DISABLED" and panel and panel.copy then panel.copy:Hide() end
    install()
end

function U.Initialize()
    if initialized then return end
    initialized = true
    W.SetChangedCallback(function()
        if queued then return end
        if C_Timer and C_Timer.After then
            queued = true
            C_Timer.After(.05, function() queued = false; U.Refresh() end)
        else U.Refresh() end
    end)
    install()
end
