local _, A = ...
A.searchLimit = 6

function A.Region()
    local region = GetCurrentRegion()
    if region == 1 then return "us" end
    if region == 3 then return "eu" end
end

function A.ResolveName(rawName, explicitRealm)
    if not A.data or type(rawName) ~= "string" then return nil end
    local name, realm = rawName, explicitRealm
    if not realm then name, realm = rawName:match("^([^-]+)%-(.+)$") end
    if not name or not realm then return nil end
    local region = A.Region()
    if not region then return nil end
    local realmKey = A.realmAliases[region .. "/" .. realm]
    if not realmKey then return nil end
    local key
    if A.Packed.current then key = A.Packed.Resolve(A.realms[realmKey].ordinal, name)
    else key = A.nameAliases[realmKey .. "/" .. name] end
    if key == false then return nil end
    return { region = region, realmSlug = realmKey:sub(#region + 2), name = name, key = key, realmKey = realmKey, dataset = A.data.datasetVersion }
end

-- Browser lookups also work without an installed profile. Keep their realm
-- canonicalization shared by single-player and collected bulk links.
function A.LookupIdentity(name, realm)
    local region = A.Region()
    if not region or type(name) ~= "string" or name == "" or name:find("[%c|]") then return end
    local short, suffix = name:match("^([^-]+)%-(.+)$")
    name, realm = short or name, suffix or realm or GetRealmName()
    if type(realm) ~= "string" or realm == "" or realm:find("[%c|]") then return end
    realm = A.DisplayRealm(realm)
    local identity = A.ResolveName(name, realm)
    if identity then
        identity.realmName = realm
        return identity
    end
    return {
        region = region, name = name, realmName = realm,
        realmSlug = realm:lower():gsub("'", ""):gsub("%s+", "-"),
    }
end

-- Packed profile IDs are dataset-local; an identity from a replaced dataset never resolves.
function A.FindCharacter(identity)
    if not identity or not identity.key then return nil end
    if A.Packed.current then
        if identity.dataset ~= A.data.datasetVersion then return nil end
        return A.Packed.Character(identity.key)
    end
    return A.characters[identity.key]
end

-- Cached packed profiles can be recreated after eviction, so compare stable IDs.
function A.SameCharacter(left, right)
    if not left or not right then return false end
    if left.packed or right.packed then return left.packed and right.packed and left.dataset == right.dataset and left.profileId == right.profileId end
    return left == right
end

-- User searches may infer a realm. LFG identities still require an explicit, exact realm.
-- Returns at most A.searchLimit profiles, the realm label, a reason and the unique total.
function A.SearchCharacters(query)
    local value = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    local name, realm = value:match("^([^-]+)%-(.+)$")
    name = name or value
    realm = realm or GetRealmName()
    local region = A.Region()
    local matches = {}
    if A.loading then return matches, realm, "Saved profiles are still loading. Try again in a moment.", 0 end
    if not A.data then return matches, realm, "No saved data installed. Install an exported addon release.", 0 end
    if not region then return matches, realm, "This region is not supported by this archive.", 0 end
    local realmKey = A.realmAliases[region .. "/" .. realm]
    if not realmKey then return matches, realm, "No saved profiles for this realm. Try Name-Realm or install a newer export.", 0 end
    if name == "" then return matches, realm, nil, 0 end
    if #value > 240 or value:find("[%c|]") then return matches, realm, "Enter a character name or Name-Realm.", 0 end
    local lower = strlower or string.lower
    local prefix = lower(name)
    if A.Packed.current then
        local ids, total = A.Packed.Search(A.realms[realmKey].ordinal, prefix, A.searchLimit)
        for _, id in ipairs(ids) do
            local character = A.Packed.Character(id)
            if character then table.insert(matches, character) end
        end
        return matches, A.realms[realmKey].name, nil, total
    end
    for _, character in pairs(A.characters) do
        local identity = character.identity
        if identity.region == region and region .. "/" .. identity.realmSlug == realmKey then
            for _, alias in ipairs(identity.nameAliases) do
                if lower(alias):sub(1, #prefix) == prefix then
                    table.insert(matches, character)
                    break
                end
            end
        end
    end
    table.sort(matches, function(left, right) return left.identity.nameKey < right.identity.nameKey end)
    local total = #matches
    for index = total, A.searchLimit + 1, -1 do matches[index] = nil end
    return matches, A.realms[realmKey].name, nil, total
end
