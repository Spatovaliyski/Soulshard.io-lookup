local _, A = ...
local M = {}
A.Motion = M
M.timing = { window = 0.18, identity = 0.16, scoreDelay = 0.04, score = 0.18, summaryDelay = 0.08, summary = 0.22, rowDelay = 0.10, rowStagger = 0.02, row = 0.16, weaponsDelay = 0.27, weapons = 0.18, treeDelay = 0.08, treeStagger = 0.05, tree = 0.22, exit = 0.08, enter = 0.16, underline = 0.14, message = 0.12, sweep = 0.32, hover = 0.09, press = 0.06 }
local active = {}

function M.Enabled()
    return type(ArmoryLookupPreferences) ~= "table" or ArmoryLookupPreferences.motionEnabled ~= false
end

function M.Stop(region)
    local state = active[region]
    if not state then return end
    active[region] = nil
    state.generation = state.generation + 1
    state.group:Stop()
    region:SetAlpha(state.restAlpha)
end

function M.CancelAll()
    local regions = {}
    for region in pairs(active) do table.insert(regions, region) end
    for _, region in ipairs(regions) do M.Stop(region) end
end

function M.Alpha(region)
    local state = active[region]
    if not state then return region:GetAlpha() end
    local progress = state.alpha:GetProgress()
    if state.smoothing == "OUT" then progress = 1 - (1 - progress) ^ 2
    elseif state.smoothing == "IN" then progress = progress ^ 2 end
    return state.fromAlpha + (state.toAlpha - state.fromAlpha) * progress
end

function M.Play(region, options)
    M.Stop(region)
    local fromAlpha = options.fromAlpha or 0
    local toAlpha = options.toAlpha or 1
    if not M.Enabled() then
        region:SetAlpha(toAlpha)
        if options.finish then options.finish() end
        return
    end
    local moving = (options.fromX or 0) ~= 0 or (options.fromY or 0) ~= 0 or (options.toX or 0) ~= 0 or (options.toY or 0) ~= 0
    local cacheKey = moving and "armoryMotion" or "armoryFade"
    local state = region[cacheKey]
    if not state then
        local group = region:CreateAnimationGroup()
        local hold = group:CreateAnimation("Alpha")
        hold:SetOrder(1)
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetOrder(2)
        state = { group = group, hold = hold, alpha = alpha, generation = 0 }
        -- Even zero-offset translations can interfere with animated children in WoW.
        -- Keep pure fades in a separate group that never creates a transform.
        if moving then
            state.origin = group:CreateAnimation("Translation")
            state.origin:SetOrder(1)
            state.origin:SetDuration(0)
            state.translation = group:CreateAnimation("Translation")
            state.translation:SetOrder(2)
        end
        region[cacheKey] = state
    end
    state.generation = state.generation + 1
    state.fromAlpha = fromAlpha
    state.toAlpha = toAlpha
    state.restAlpha = options.restAlpha or 1
    state.smoothing = options.smoothing or "OUT"
    local generation = state.generation
    state.hold:SetFromAlpha(fromAlpha)
    state.hold:SetToAlpha(fromAlpha)
    state.hold:SetDuration(options.delay or 0)
    state.alpha:SetFromAlpha(fromAlpha)
    state.alpha:SetToAlpha(toAlpha)
    state.alpha:SetDuration(options.duration)
    state.alpha:SetSmoothing(state.smoothing)
    if moving then
        -- Establish the entrance offset without moving layout anchors.
        state.origin:SetOffset(options.fromX or 0, options.fromY or 0)
        state.translation:SetOffset((options.toX or 0) - (options.fromX or 0), (options.toY or 0) - (options.fromY or 0))
        state.translation:SetDuration(options.duration)
        state.translation:SetSmoothing(state.smoothing)
    end
    state.group:SetScript("OnFinished", function()
        if active[region] ~= state or state.generation ~= generation then return end
        active[region] = nil
        region:SetAlpha(toAlpha)
        if options.finish then options.finish() end
    end)
    active[region] = state
    region:SetAlpha(fromAlpha)
    state.group:Play()
end

function M.Reveal(region, delay, duration, rise, finish)
    M.Play(region, { delay = delay, duration = duration, fromY = -(rise or 0), finish = finish })
end

function M.SetEnabled(enabled)
    if type(ArmoryLookupPreferences) ~= "table" then ArmoryLookupPreferences = {} end
    ArmoryLookupPreferences.motionEnabled = enabled
    if A.profile then A.profile:CancelMotion() else M.CancelAll() end
end
