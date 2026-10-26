local _, A = ...
local T = {}
A.Theme = T

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

T.Hex = rgb

-- Opaque colour of `color` laid over `base` at `alpha`. Flat tinted shapes use this instead of
-- translucent layers so overlapping pieces (capsule ends, hover fills) never stack their alpha.
function T.Blend(color, base, alpha)
    return {
        base[1] + (color[1] - base[1]) * alpha,
        base[2] + (color[2] - base[2]) * alpha,
        base[3] + (color[3] - base[3]) * alpha,
    }
end

-- Warm "Warcraft native" palette (Direction A). Surfaces are flat; hairlines are the cream tint at low alpha.
T.background = rgb("17130e")
T.surface = rgb("0d0b08")
T.input = rgb("0a0806")
T.raised = rgb("1d1810")
T.gold = rgb("d5a745")
T.goldBright = rgb("f1c95e")
T.brand = T.goldBright
T.logo = "Interface\\AddOns\\SoulshardLookup\\Media\\Soulshard.tga"
T.cream = rgb("e8dcc0")
T.bright = rgb("f3e7c8")
T.muted = rgb("a79c82")
T.dim = rgb("8c8168")
T.faint = rgb("6f6652")
T.hair = { 0.910, 0.847, 0.667 }
T.line = T.Blend(T.hair, T.background, 0.16)
T.titleTint = { 1, 0.925, 0.745 }
T.danger = rgb("ef7474")
T.exceptional = rgb("e879b2")
T.good = rgb("6fcf86")
T.goodText = rgb("c4e8cc")
T.warn = rgb("e0a43a")
T.trim = rgb("70592c")
T.tabActive = rgb("2a2115")
T.tabInactive = rgb("14100b")
T.tabText = rgb("9a8f76")

local locale = GetLocale()
local latin = locale ~= "ruRU" and locale ~= "zhCN" and locale ~= "zhTW" and locale ~= "koKR"
T.bodyFont = latin and "Fonts\\ARIALN.TTF" or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
T.headingFont = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
T.minimumFontSize = 13

-- Window geometry, in layout units. The profile is 800 x 720; the hanging tabs overhang the bottom edge.
T.width = 800
T.height = 720
T.titleHeight = 34
T.search = { width = 620, height = 468, cardWidth = 572, cardHeight = 88, inputWidth = 360, buttonWidth = 168, visibleRows = 3, rowPitch = 46 }
T.contentX = 25
T.contentY = 159
T.contentWidth = 750
T.contentHeight = 506
T.footerY = 685
T.tabs = { x = 30, pitch = 122, width = 116, top = 719, height = 28, activeTop = 719, activeHeight = 34 }
T.tabOverhang = 34
T.tree = { width = 242, height = 484, pitch = 254, tile = 34, columnPitch = 52, rowPitch = 45, x = 26, y = 68 }
T.quality = { POOR = { 0.55, 0.55, 0.55 }, COMMON = { 0.882, 0.863, 0.906 }, UNCOMMON = { 0.32, 0.82, 0.39 }, RARE = { 0.37, 0.62, 0.95 }, EPIC = { 0.733, 0.510, 0.937 }, LEGENDARY = { 1, 0.58, 0.17 } }

local classColors = {
    WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473", ROGUE = "fff569", PRIEST = "ffffff",
    SHAMAN = "0070de", MAGE = "69ccf0", WARLOCK = "9482c9", DRUID = "ff7d0a",
}

-- The client's own class colour when it has one, so the name matches the rest of the UI.
function T.ClassColor(token)
    local native = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[token]
    if type(native) == "table" and native.r then return { native.r, native.g, native.b } end
    return classColors[token] and rgb(classColors[token]) or T.cream
end

-- |cffRRGGBB escape for a colour triple, for text that mixes colours in one FontString.
function T.Color(color)
    return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
end

-- Colour wrapper: T.Wrap(T.muted, "text") -> "|cffa79c82text|r".
function T.Wrap(color, text)
    return T.Color(color) .. text .. "|r"
end

-- Decorative accent per talent specialization (the three trees read apart at a glance). Unknown
-- names fall back to gold. Colour carries no meaning beyond identifying the tree.
local specAccents = {
    Arms = "c79c6e", Fury = "d9534f", Protection = "5e9ef2", Holy = "f1c95e", Retribution = "e8793a",
    ["Beast Mastery"] = "abd473", Marksmanship = "5e9ef2", Survival = "c79c6e",
    Assassination = "52d163", Combat = "d9534f", Subtlety = "8b6fd0",
    Discipline = "e1dce7", Shadow = "8b6fd0",
    Elemental = "5e9ef2", Enhancement = "e8793a", Restoration = "52d163",
    Arcane = "bb82ef", Fire = "e8793a", Frost = "69ccf0",
    Affliction = "58a862", Demonology = "8b6fd0", Destruction = "e0702f",
    Balance = "5e9ef2", ["Feral Combat"] = "e0702f",
}

function T.SpecColor(name)
    return specAccents[name] and rgb(specAccents[name]) or T.gold
end

-- Vertical fade of the window background over an image or panel.
function T.Shade(parent, x, y, width, height, topAlpha, bottomAlpha, color)
    color = color or T.background
    local texture = T.Fill(parent, x, y, width, height, { 1, 1, 1 }, 1, "ARTWORK")
    texture:SetGradient("VERTICAL",
        CreateColor(color[1], color[2], color[3], bottomAlpha),
        CreateColor(color[1], color[2], color[3], topAlpha))
    return texture
end

-- Parse tiers share the website's thresholds; an unknown parse is dim, never a tier colour.
function T.ParseColor(number)
    if not number then return T.faint end
    if number == 100 then return T.gold end
    if number >= 99 then return T.exceptional end
    if number >= 95 then return T.quality.LEGENDARY end
    if number >= 75 then return T.quality.EPIC end
    if number >= 50 then return T.quality.RARE end
    if number >= 25 then return T.quality.UNCOMMON end
    return T.muted
end

function T.Text(parent, size, color, serif)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(serif and T.headingFont or T.bodyFont, math.max(T.minimumFontSize, size), "")
    text:SetTextColor(unpack(color or T.cream))
    text:SetShadowColor(0, 0, 0, 0.85)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("LEFT")
    return text
end

function T.Fill(parent, x, y, width, height, color, alpha, layer)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetSize(width, height)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return texture
end

-- Bordered panel; still used by search and Whispers.
function T.Panel(parent, width, height, raised)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(unpack(raised and T.input or T.surface))
    panel:SetBackdropBorderColor(unpack(T.line))
    return panel
end

-- Flat borderless surface used by the profile tabs.
function T.Card(parent, width, height, color)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(width, height)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    card:SetBackdropColor(unpack(color or T.surface))
    return card
end

function T.Rule(parent, x, y, width)
    T.Fill(parent, x, y, width, 1, T.line, 1, "BORDER")
end

-- One-pixel hairline in the cream tint.
function T.Hair(parent, x, y, width, alpha)
    return T.Fill(parent, x, y, width, 1, T.hair, alpha or 0.12, "BORDER")
end

-- `fontSize` overrides the label size. Variants: default (outlined), primary (solid gold), danger,
-- tint (flat gold wash) and ghost (text only).
function T.Button(parent, label, width, height, callback, variant, fontSize)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local primary, danger = variant == "primary", variant == "danger"
    local flat = variant == "tint" or variant == "ghost"
    local accent = danger and T.danger or T.gold
    local tintFill = T.Blend(T.gold, T.background, 0.16)
    button:SetSize(width, height)
    if flat then button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    else button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }) end
    local color = primary and T.background or variant == "tint" and rgb("f3e2b0") or variant == "ghost" and rgb("cdbf9a") or accent
    button.label = T.Text(button, fontSize or (primary and 15 or 14), color, primary)
    button.label:SetPoint("CENTER")
    button.label:SetText(label)
    button.feedback = T.Fill(button, 0, 0, width, height, primary and T.cream or accent, 1, "BORDER")
    button.feedback:SetAllPoints()
    button.feedback:SetAlpha(0)
    local function feedback(alpha, duration)
        A.Motion.Play(button.feedback, { fromAlpha = A.Motion.Alpha(button.feedback), toAlpha = alpha, duration = duration, restAlpha = 0 })
    end
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        if not flat then self:SetBackdropBorderColor(unpack(primary and T.cream or accent)) end
        feedback(0.08, A.Motion.timing.hover)
    end)
    button:SetScript("OnLeave", function(self) self.hovered = false; self:SetSelected(self.selected); feedback(0, A.Motion.timing.hover) end)
    button:SetScript("OnMouseDown", function() feedback(0.14, A.Motion.timing.press) end)
    button:SetScript("OnMouseUp", function(self) feedback(self.hovered and 0.08 or 0, A.Motion.timing.hover) end)
    button:HookScript("OnHide", function(self) A.Motion.Stop(self.feedback); self.feedback:SetAlpha(0); self.hovered = false; self:SetSelected(self.selected) end)
    function button:SetSelected(selected)
        self.selected = selected
        if primary then
            self:SetBackdropColor(unpack(T.gold))
            self:SetBackdropBorderColor(unpack(T.gold))
            self.label:SetTextColor(unpack(T.background))
        elseif variant == "tint" then
            self:SetBackdropColor(unpack(tintFill))
        elseif variant == "ghost" then
            self:SetBackdropColor(T.background[1], T.background[2], T.background[3], 0)
        else
            self:SetBackdropColor(selected and 0.145 or T.surface[1], selected and 0.118 or T.surface[2], selected and 0.090 or T.surface[3], 1)
            self:SetBackdropBorderColor(unpack(selected and accent or T.line))
            self.label:SetTextColor(unpack(selected and T.cream or accent))
        end
    end
    button:SetSelected(false)
    return button
end

local classIcons = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

-- Per-class square icons; the character-create atlas cells render unevenly at small sizes.
function T.ClassIcon(texture, token)
    local name = classIcons[token]
    texture:SetTexture("Interface\\Icons\\" .. (name and ("ClassIcon_" .. name) or "INV_Misc_QuestionMark"))
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

-- Circle clip for any texture. The mask is a shipped alpha disc so nothing depends on a Blizzard
-- file name; a client without mask textures leaves the texture square instead of failing.
T.circleMask = "Interface\\AddOns\\SoulshardLookup\\Media\\CircleMask.tga"

function T.Circle(frame, texture)
    if type(frame.CreateMaskTexture) ~= "function" or type(texture.AddMaskTexture) ~= "function" then return nil end
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(texture)
    mask:SetTexture(T.circleMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:AddMaskTexture(mask)
    return mask
end

-- A flat-coloured circle anchored by `point` to its parent.
function T.Disc(parent, point, x, y, size, color, alpha, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    texture:SetSize(size, size)
    texture:SetPoint(point, x, y)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    T.Circle(parent, texture)
    return texture
end

-- Flat capsule (pill) of one opaque colour: two end discs and a body that stop at each other's edge.
function T.Capsule(parent, width, height, color)
    local capsule = CreateFrame("Frame", nil, parent)
    capsule:SetSize(width, height)
    capsule.left = T.Disc(capsule, "TOPLEFT", 0, 0, height, color, 1, "BACKGROUND")
    capsule.right = T.Disc(capsule, "TOPRIGHT", 0, 0, height, color, 1, "BACKGROUND")
    capsule.body = T.Fill(capsule, height / 2, 0, width - height, height, color, 1, "BACKGROUND")
    function capsule:SetColor(value)
        for _, region in ipairs({ self.left, self.right, self.body }) do region:SetColorTexture(value[1], value[2], value[3], 1) end
    end
    function capsule:Resize(value)
        self:SetSize(value, height)
        self.body:SetSize(math.max(0, value - height), height)
    end
    return capsule
end

-- Width of a FontString's text. A client always measures; the fallback only serves tools that do not.
function T.TextWidth(text)
    if text.GetStringWidth then
        local measured = text:GetStringWidth()
        if type(measured) == "number" and measured > 0 then return measured end
    end
    -- Fallback estimate for environments without GetStringWidth: colour codes take no space.
    local plain = (text:GetText() or ""):gsub("||", "|"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #plain * 0.38 * (text.fontSize or 14)
end

-- Hanging profile tab (Blizzard inspect-frame convention): flat, square top, rounded bottom corners.
-- Tabs hang from the window's bottom edge like bookmarks; the selected one is taller. `x` is the left edge inside `parent`.
function T.Tab(parent, label, x, callback)
    local tab = CreateFrame("Button", nil, parent)
    local width = T.tabs.width
    tab.x = x
    tab.body = tab:CreateTexture(nil, "BACKGROUND")
    tab.foot = tab:CreateTexture(nil, "BACKGROUND")
    tab.left = tab:CreateTexture(nil, "BACKGROUND")
    tab.right = tab:CreateTexture(nil, "BACKGROUND")
    T.Circle(tab, tab.left)
    T.Circle(tab, tab.right)
    tab.label = T.Text(tab, 16, T.tabText, true)
    function tab:Paint()
        local selected = self.selected
        local color = selected and T.tabActive or (self.hovered and T.Blend(T.hair, T.tabInactive, 0.07) or T.tabInactive)
        local radius = selected and 9 or 8
        local height = selected and T.tabs.activeHeight or T.tabs.height
        self:SetSize(width, height)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", parent, "TOPLEFT", self.x, -(selected and T.tabs.activeTop or T.tabs.top))
        self.body:ClearAllPoints()
        self.body:SetPoint("TOPLEFT")
        self.body:SetSize(width, height - radius)
        self.foot:ClearAllPoints()
        self.foot:SetPoint("BOTTOMLEFT", radius, 0)
        self.foot:SetSize(width - radius * 2, radius)
        self.left:ClearAllPoints()
        self.left:SetPoint("BOTTOMLEFT")
        self.left:SetSize(radius * 2, radius * 2)
        self.right:ClearAllPoints()
        self.right:SetPoint("BOTTOMRIGHT")
        self.right:SetSize(radius * 2, radius * 2)
        for _, region in ipairs({ self.body, self.foot, self.left, self.right }) do region:SetColorTexture(color[1], color[2], color[3], 1) end
        self.label:ClearAllPoints()
        self.label:SetPoint("CENTER", 0, selected and -1 or -2)
        self.label:SetTextColor(unpack(selected and T.goldBright or (self.hovered and T.cream or T.tabText)))
    end
    function tab:SetSelected(selected)
        self.selected = selected
        self:Paint()
    end
    tab.label:SetText(label)
    tab:SetScript("OnClick", callback)
    tab:SetScript("OnEnter", function(self) self.hovered = true; self:Paint() end)
    tab:SetScript("OnLeave", function(self) self.hovered = false; self:Paint() end)
    tab:HookScript("OnHide", function(self) self.hovered = false; self:Paint() end)
    tab:SetSelected(false)
    return tab
end

-- Status glyphs are drawn from flat shapes on a 20-unit canvas, so they scale cleanly and need no
-- shipped art. `backing` is the surface colour behind a ring's hollow centre.
local function drawWarning(glyph, fill, stroke, backing, size)
    local dark = rgb("1b1206")
    for step = 0, 14 do
        local span = 17.2 * (step + 1) / 15
        fill(10 - span / 2, 2.2 + step, span, 1.05, T.warn)
    end
    fill(9.05, 7.4, 1.9, 5, dark)
    fill(8.9, 13.6, 2.2, 2.2, dark)
end

local function drawSocket(glyph, fill, stroke, backing, size)
    local points = { { 10, 2.4 }, { 17.4, 10 }, { 10, 17.6 }, { 2.6, 10 } }
    for index, point in ipairs(points) do
        local next = points[index % 4 + 1]
        stroke(point[1], point[2], next[1], next[2], T.warn, 2.2)
    end
end

local function drawRing(glyph, fill, stroke, color, backing, mark, size)
    local scale = size / 20
    local function disc(offset, diameter, tint)
        local texture = glyph:CreateTexture(nil, "ARTWORK")
        texture:SetSize(diameter * scale, diameter * scale)
        texture:SetPoint("TOPLEFT", offset * scale, -offset * scale)
        texture:SetColorTexture(tint[1], tint[2], tint[3], 1)
        T.Circle(glyph, texture)
    end
    disc(2, 16, color)
    disc(3.8, 12.4, backing)
    if mark == "check" then
        stroke(6, 10.3, 8.8, 13.1, color, 2)
        stroke(8.8, 13.1, 14, 7.6, color, 2)
    else
        stroke(6.5, 10, 13.5, 10, color, 2)
    end
end

local drawers = {
    warn = drawWarning,
    socket = drawSocket,
    ok = function(glyph, fill, stroke, backing, size) drawRing(glyph, fill, stroke, T.good, backing, "check", size) end,
    unknown = function(glyph, fill, stroke, backing, size) drawRing(glyph, fill, stroke, T.dim, backing, "dash", size) end,
}

-- One glyph frame holding every status shape; SetKind shows exactly one of them.
function T.StatusGlyph(parent, size, backing)
    local glyph = CreateFrame("Frame", nil, parent)
    glyph:SetSize(size, size)
    glyph.shapes = {}
    local scale = size / 20
    for kind, draw in pairs(drawers) do
        local shape = CreateFrame("Frame", nil, glyph)
        shape:SetPoint("TOPLEFT")
        shape:SetSize(size, size)
        local function fill(x, y, width, height, color)
            local texture = shape:CreateTexture(nil, "ARTWORK")
            texture:SetPoint("TOPLEFT", x * scale, -y * scale)
            texture:SetSize(width * scale, height * scale)
            texture:SetColorTexture(color[1], color[2], color[3], 1)
        end
        local function stroke(x1, y1, x2, y2, color, thickness)
            local line = shape:CreateLine(nil, "OVERLAY")
            line:SetThickness(thickness * scale)
            line:SetColorTexture(color[1], color[2], color[3], 1)
            line:SetStartPoint("TOPLEFT", x1 * scale, -y1 * scale)
            line:SetEndPoint("TOPLEFT", x2 * scale, -y2 * scale)
        end
        draw(shape, fill, stroke, backing or T.surface, size)
        shape:Hide()
        glyph.shapes[kind] = shape
    end
    function glyph:SetKind(kind)
        self.kind = kind
        for name, shape in pairs(self.shapes) do shape:SetShown(name == kind) end
    end
    return glyph
end

function T.SectionStatus(section)
    local labels = { available = "Saved", partial = "Saved · Partial record", unavailable = "Unavailable", unsupported = "Incompatible section" }
    local label = labels[section.state] or "Unavailable"
    if section.source == "live" then label = section.state == "partial" and "Live · Partial record" or "Live" end
    if section.fetchedAt then
        label = label .. " · " .. date("!%d %b %Y, %H:%M UTC", section.fetchedAt)
        if time() - section.fetchedAt > A.staleAfter then label = label .. " · Older than 24 hours" end
    end
    return label
end

-- "just now", "5 min ago", "3 hours ago", "4 days ago".
function T.Ago(timestamp)
    local seconds = math.max(0, time() - timestamp)
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. " min ago" end
    if seconds < 86400 then
        local hours = math.floor(seconds / 3600)
        return hours .. (hours == 1 and " hour ago" or " hours ago")
    end
    local days = math.floor(seconds / 86400)
    return days .. (days == 1 and " day ago" or " days ago")
end
