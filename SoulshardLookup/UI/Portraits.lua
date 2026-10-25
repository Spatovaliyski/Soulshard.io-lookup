local _, A = ...
local T = A.Theme
local R = {}
A.Portraits = R

-- Portrait for a player the client may not be able to show. Tiers, best first:
--   unit   the live 2D portrait, when the player is in the group or targeted and in view
--   race   a generic race and sex portrait the client actually ships
--   class  the class icon, or a question mark when the class is unknown
-- Blizzard's generic portrait file names are not documented, so each candidate is looked up
-- with GetFileIDFromPath before it is used; nothing is ever pointed at a file that is missing.

local lower = strlower or string.lower
local TEMPORARY = "Interface\\CharacterFrame\\TemporaryPortrait-"
local ACHIEVEMENT = "Interface\\Icons\\Achievement_Character_"
-- englishRace token from GetPlayerInfoByGUID -> the spelling the achievement icons use.
local achievementRace = {
    Human = "Human", Dwarf = "Dwarf", Gnome = "Gnome", NightElf = "Nightelf", Orc = "Orc",
    Scourge = "Undead", Tauren = "Tauren", Troll = "Troll", BloodElf = "Bloodelf", Draenei = "Draenei",
}
local FULL, ICON = { 0, 1, 0, 1 }, { 0.07, 0.93, 0.07, 0.93 }
-- A file lookup may or may not want an extension, so both spellings are tried; the spelling that
-- resolved is the one handed to SetTexture.
local spellings = { "", ".blp", ".tga" }
local resolved = {}

local partyUnits, raidUnits = {}, {}
for index = 1, 4 do partyUnits[index] = "party" .. index end
for index = 1, 40 do raidUnits[index] = "raid" .. index end

local function accessible(value)
    if type(canaccessvalue) == "function" then
        local ok, allowed = pcall(canaccessvalue, value)
        return ok and allowed == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret == false
    end
    return true
end

local function exists(path)
    if type(GetFileIDFromPath) ~= "function" then return false end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and type(id) == "number" and id > 0
end

local function firstExisting(path)
    for _, extension in ipairs(spellings) do
        if exists(path .. extension) then return path .. extension end
    end
end

-- The generic portrait for a race and sex (GetPlayerInfoByGUID values), or nil when the client has none.
function R.Fallback(race, sex)
    if not achievementRace[race] or (sex ~= 2 and sex ~= 3) then return nil end
    local gender = sex == 3 and "Female" or "Male"
    local key = race .. gender
    local hit = resolved[key]
    if not hit then
        local path = firstExisting(TEMPORARY .. gender .. "-" .. race)
        if path then hit = { path, FULL, "temporary" }
        else
            path = firstExisting(ACHIEVEMENT .. achievementRace[race] .. "_" .. gender)
            if path then hit = { path, ICON, "achievement" } end
        end
        -- Only a hit is remembered, so a lookup that failed early is retried on the next paint.
        resolved[key] = hit
    end
    if hit then return hit[1], hit[2], hit[3] end
end

local function squash(value)
    return (lower(value):gsub("[%s%-']", ""))
end

-- The unit token of the player, when they are the target or in the group, so the live portrait can be drawn.
function R.GroupUnit(identity)
    local name = identity and identity.name
    if type(name) ~= "string" or type(UnitName) ~= "function" then return nil end
    local want = lower(name)
    local function matches(unit)
        local ok, unitName, unitRealm = pcall(UnitName, unit)
        if not ok or type(unitName) ~= "string" or not accessible(unitName) or lower(unitName) ~= want then return false end
        if type(UnitIsPlayer) == "function" and not UnitIsPlayer(unit) then return false end
        if identity.realmName and type(unitRealm) == "string" and unitRealm ~= "" and accessible(unitRealm) then
            return squash(unitRealm) == squash(identity.realmName)
        end
        return true
    end
    if matches("target") then return "target" end
    if type(IsInGroup) == "function" and not IsInGroup() then return nil end
    local raid = type(IsInRaid) == "function" and IsInRaid()
    local units = raid and raidUnits or partyUnits
    for index = 1, #units do
        if matches(units[index]) then return units[index] end
    end
end

local function visible(unit)
    if type(UnitIsVisible) ~= "function" then return false end
    local ok, result = pcall(UnitIsVisible, unit)
    return ok and (result == true or result == 1)
end

-- Paint `texture` for this player and report which tier supplied it.
function R.Apply(texture, identity, view)
    local unit = R.GroupUnit(identity)
    if unit and type(SetPortraitTexture) == "function" and visible(unit) then
        texture:SetTexCoord(0, 1, 0, 1)
        if pcall(SetPortraitTexture, texture, unit) then return "unit" end
    end
    local path, coords = R.Fallback(view.raceToken, view.sex)
    if path then
        texture:SetTexture(path)
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return "race"
    end
    T.ClassIcon(texture, view.classToken)
    return "class"
end

-- One line for /sl diagnostics: what this client can actually draw.
function R.Diagnostics()
    local temporary, achievement, missing = 0, 0, 0
    for race in pairs(achievementRace) do
        for _, sex in ipairs({ 2, 3 }) do
            local path, _, kind = R.Fallback(race, sex)
            if not path then missing = missing + 1
            elseif kind == "temporary" then temporary = temporary + 1
            else achievement = achievement + 1 end
        end
    end
    return "Whisper portraits: circle masks " .. tostring(type(UIParent) == "table" and type(UIParent.CreateMaskTexture) == "function") ..
        "; GetFileIDFromPath " .. tostring(type(GetFileIDFromPath)) ..
        "; generic portraits " .. temporary .. " TemporaryPortrait, " .. achievement .. " achievement icon, " .. missing .. " missing (class icon shown)"
end
