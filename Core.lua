local _, A = ...
A.version = "0.4.1"
A.interface = 20506
A.staleAfter = 86400
A.state = "No saved data installed. Install an exported Data folder and restart WoW."

function A.Text(value)
    return (tostring(value or ""):gsub("|", "||"))
end

function A.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("Soulshard Lookup: " .. A.Text(message))
end

function A.SectionLabel(section)
    if not section then return "unavailable" end
    local label = section.state
    if section.source == "live" then label = "Live · " .. label end
    if section.fetchedAt then
        label = label .. " · " .. date("!%Y-%m-%d %H:%M UTC", section.fetchedAt)
        if time() - section.fetchedAt > A.staleAfter then label = label .. " · stale (older than 24 hours)" end
    end
    if section.reason then label = label .. " · " .. section.reason end
    return label
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        local _, _, _, interface = GetBuildInfo()
        -- Packed data indexes across frames and reports when it is published.
        if A.LoadData(A.pack, interface, true, function()
            A.Print(A.state)
            if A.WhisperUI then A.WhisperUI.Refresh() end
        end) ~= nil then A.Print(A.state) end
        if A.Whispers then A.Whispers.Initialize() end
        if A.WhisperUI then A.WhisperUI.Initialize() end
    end
    if A.LfgEvent then A.LfgEvent(event, name) end
    if A.WhisperUI then A.WhisperUI.Event(event, name) end
end)

SLASH_SOULSHARDLOOKUP1 = "/sl"
SLASH_SOULSHARDLOOKUP2 = "/lookup"
SLASH_SOULSHARDLOOKUP3 = "/al"
SLASH_SOULSHARDLOOKUP4 = "/armorylookup"
SlashCmdList.SOULSHARDLOOKUP = function(message)
    message = (message or ""):match("^%s*(.-)%s*$")
    local command, argument = message:match("^(%S*)%s*(.-)$")
    if command == "settings" and A.WhisperUI then A.WhisperUI.OpenSettings(); return end
    if command == "motion" then
        if argument == "on" or argument == "off" then
            A.Motion.SetEnabled(argument == "on")
            A.Print("Animations " .. argument .. ".")
        else A.Print("/sl motion on or /sl motion off") end
        return
    end
    if command == "" then A.ShowSearch(); return end
    if command == "inspect" and argument ~= "" then
        local identity = A.ResolveName(argument)
        if identity then A.ShowProfile(identity)
        else
            local opened = A.ShowSearch(argument)
            if opened and A.profile.search.total == 1 then A.profile.search:Submit() end
        end
        return
    end
    if command == "diagnostics" then
        local version, build, buildDate, interface = GetBuildInfo()
        A.Print("Client " .. tostring(version) .. " build " .. tostring(build) .. " " .. tostring(buildDate) .. " interface " .. tostring(interface))
        A.Print("Project " .. tostring(WOW_PROJECT_ID) .. "; locale " .. GetLocale() .. "; region " .. tostring(GetCurrentRegion()) .. "; realm " .. GetRealmName())
        A.Print("Browse hook " .. tostring(type(LFGBrowseSearchEntry_Update)) .. "; LFG " .. tostring(A.lfgState))
        if A.Whispers then
            local status = A.Whispers.GetStatus()
            A.Print("Whisper Collector: " .. status.label .. "; " .. tostring(status.reason or status.state))
        end
        if A.Portraits then A.Print(A.Portraits.Diagnostics()) end
        if A.Packed.current then A.Print("Packed data: " .. A.Packed.CacheSize() .. "/" .. A.Packed.cacheLimit .. " cached profiles") end
        for _, message in ipairs(A.diagnostics) do A.Print("Data: " .. message) end
    elseif command ~= "status" then A.ShowSearch(message); return end
    A.Print(A.state)
    A.Print("/sl or /lookup to search your realm · /sl inspect Name or Name-Realm · /sl settings · /sl motion on|off · /sl diagnostics")
end
