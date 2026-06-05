local ADDON_NAME, addon = ...
addon = addon or {}

local DISPLAY_NAME = "Chat Tabs Organizer"
local COMMAND = "/ctabs"

local DEFAULTS = {
    version = 6,
    enabled = true,
    createMissingTabs = true,
    dockTabs = true,
    clearManagedFilters = true,
    autoJoinChannels = false,
    statusMessages = true,
    appearance = {
        enabled = true,
        applyToAllTabs = true,
        fontKey = "default",
        fontFile = "Fonts\\FRIZQT__.TTF",
        fontSize = 14,
        background = {
            r = 0.02,
            g = 0.02,
            b = 0.02,
            alpha = 0.35,
        },
    },
    tabs = {
        guild = {
            enabled = true,
            name = "Guild",
            groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" },
        },
        party = {
            enabled = true,
            name = "Party",
            groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" },
        },
        communities = {
            enabled = true,
            name = "Communities",
            groups = { "COMMUNITIES" },
        },
        trade = {
            enabled = true,
            name = "Trade",
            groups = { "CHANNEL" },
            channels = { "Trade", "Services" },
            channelPatterns = { "Trade", "Services" },
        },
        whispers = {
            enabled = false,
            name = "Whispers",
            groups = { "WHISPER", "BN_WHISPER" },
        },
        localChannels = {
            enabled = false,
            name = "Local",
            groups = { "CHANNEL" },
            channels = { "General", "LocalDefense", "LookingForGroup" },
            channelPatterns = { "General", "LocalDefense", "LookingForGroup" },
        },
    },
}

local TAB_ORDER = {
    "guild",
    "party",
    "communities",
    "trade",
    "whispers",
    "localChannels",
}

local TAB_LABELS = {
    guild = "Guild",
    party = "Party",
    communities = "Communities",
    trade = "Trade and Services",
    whispers = "Whispers",
    localChannels = "Local channels",
}

local db
local optionsPanel
local settingsCategory
local controlIndex = 0
local currentTabsText

local PANEL_MIN_WIDTH = 700
local RIGHT_COLUMN_OFFSET = 360
local RIGHT_COLUMN_WIDTH = 300
local COMPACT_SLIDER_WIDTH = 210
local COMPACT_DROPDOWN_WIDTH = 165
local CURRENT_TABS_LINE_LIMIT = 34

local FONT_OPTIONS = {
    { key = "default", label = "Default", file = "Fonts\\FRIZQT__.TTF" },
    { key = "arial", label = "Arial Narrow", file = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", label = "Morpheus", file = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", label = "Skurri", file = "Fonts\\SKURRI.TTF" },
}

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue

    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end

    return value
end

local function Round(value, decimals)
    local multiplier = 10 ^ (decimals or 0)
    return math.floor((value * multiplier) + 0.5) / multiplier
end

local function CopyDefaults(source, target)
    if type(source) ~= "table" then
        return target
    end

    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = CopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

local function CopyArray(source)
    local target = {}

    if type(source) ~= "table" then
        return target
    end

    for index, value in ipairs(source) do
        target[index] = value
    end

    return target
end

local function MigrateDatabase()
    if not db then
        return
    end

    local oldVersion = tonumber(db.version) or 0

    if oldVersion >= DEFAULTS.version then
        db.enabled = true
        db.createMissingTabs = true
        db.dockTabs = true
        return
    end

    for key, defaults in pairs(DEFAULTS.tabs) do
        if db.tabs and db.tabs[key] then
            db.tabs[key].groups = CopyArray(defaults.groups)
            db.tabs[key].channels = CopyArray(defaults.channels)
            db.tabs[key].channelPatterns = CopyArray(defaults.channelPatterns)
        end
    end

    db.enabled = true
    db.createMissingTabs = true
    db.dockTabs = true

    if db.appearance and (db.appearance.fontKey == "current" or not db.appearance.fontKey) then
        db.appearance.fontKey = DEFAULTS.appearance.fontKey
        db.appearance.fontFile = DEFAULTS.appearance.fontFile
    end

    if db.tabs and db.tabs.raid then
        db.legacyRaidTabName = db.tabs.raid.name or "Raid"
        db.tabs.raid = nil
    end

    db.version = DEFAULTS.version
end

local function ResetDatabase()
    ChatTabsOrganizerDB = CopyDefaults(DEFAULTS, {})
    db = ChatTabsOrganizerDB
    addon.db = db
end

local function Print(message, force)
    if not DEFAULT_CHAT_FRAME then
        return
    end

    if force or (db and db.statusMessages) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. DISPLAY_NAME .. ":|r " .. tostring(message))
    end
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return false
    end

    return pcall(func, ...)
end

local ClearFrameFilters

local function Trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function LowerCommand(value)
    return string.lower(Trim(value))
end

local function NormalizeFontFile(fontFile)
    return string.lower((fontFile or ""):gsub("/", "\\"))
end

local function FindFontOptionByKey(key)
    for _, option in ipairs(FONT_OPTIONS) do
        if option.key == key then
            return option
        end
    end

    return nil
end

local function GetFontOptionByKey(key)
    local option = FindFontOptionByKey(key)

    if option then
        return option
    end

    return FONT_OPTIONS[1]
end

local function GetFontOptionByFile(fontFile)
    local normalized = NormalizeFontFile(fontFile)

    if normalized == "" then
        return nil
    end

    for _, option in ipairs(FONT_OPTIONS) do
        if option.file and NormalizeFontFile(option.file) == normalized then
            return option
        end
    end

    return nil
end

local function GetSelectedFontFile()
    local appearance = db and db.appearance

    if not appearance then
        return nil
    end

    local option = GetFontOptionByKey(appearance.fontKey)

    if option and option.file then
        return option.file
    end

    return appearance.fontFile or DEFAULTS.appearance.fontFile
end

local function GetSelectedFontLabel()
    local appearance = db and db.appearance
    local option = GetFontOptionByKey(appearance and appearance.fontKey)

    if option then
        return option.label
    end

    if appearance and appearance.fontFile then
        local matched = GetFontOptionByFile(appearance.fontFile)
        return matched and matched.label or "Default"
    end

    return "Default"
end

local function NormalizeWindowName(name)
    return LowerCommand(name)
end

local function GetChatFramesByName(name)
    local frames = {}

    if not name or not NUM_CHAT_WINDOWS then
        return frames
    end

    local expectedName = NormalizeWindowName(name)

    for index = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. index]
        local windowName = GetChatWindowInfo(index)

        if frame and NormalizeWindowName(windowName) == expectedName then
            frames[#frames + 1] = frame
        end
    end

    return frames
end

local function GetCurrentChatFrames()
    local frames = {}

    if not NUM_CHAT_WINDOWS then
        return frames
    end

    for index = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. index]
        local name = GetChatWindowInfo(index)

        if frame and name and name ~= "" then
            frames[#frames + 1] = frame
        end
    end

    return frames
end

local function GetCurrentChatTabNames()
    local names = {}

    for _, frame in ipairs(GetCurrentChatFrames()) do
        local name = GetChatWindowInfo(frame:GetID())
        names[#names + 1] = name
    end

    return names
end

local function FormatCurrentTabsText(names)
    if #names == 0 then
        return "Current tabs:\nnone detected"
    end

    local lines = { "Current tabs:" }
    local line = ""

    for _, name in ipairs(names) do
        local nextValue = line == "" and name or (line .. ", " .. name)

        if line ~= "" and #nextValue > CURRENT_TABS_LINE_LIMIT then
            lines[#lines + 1] = line
            line = name
        else
            line = nextValue
        end
    end

    if line ~= "" then
        lines[#lines + 1] = line
    end

    return table.concat(lines, "\n")
end

local function GetAppearanceSampleFrame()
    if SELECTED_CHAT_FRAME and SELECTED_CHAT_FRAME.GetID then
        return SELECTED_CHAT_FRAME
    end

    return GetCurrentChatFrames()[1]
end

local function SyncAppearanceFromCurrentTabs()
    if not db or not db.appearance then
        return
    end

    local frame = GetAppearanceSampleFrame()

    if not frame or not frame.GetID then
        return
    end

    local _, savedFontSize, r, g, b, alpha = GetChatWindowInfo(frame:GetID())
    local fontFile, frameFontSize, fontFlags

    if frame.GetFont then
        fontFile, frameFontSize, fontFlags = frame:GetFont()
    end

    local background = db.appearance.background

    if type(background) ~= "table" then
        background = {}
        db.appearance.background = background
    end

    background.r = Clamp(r, 0, 1)
    background.g = Clamp(g, 0, 1)
    background.b = Clamp(b, 0, 1)
    background.alpha = Clamp(alpha, 0, 1)

    db.appearance.fontFile = fontFile or db.appearance.fontFile
    db.appearance.fontFlags = fontFlags or db.appearance.fontFlags or ""

    local matchedFont = GetFontOptionByFile(fontFile)
    db.appearance.fontKey = matchedFont and matchedFont.key or DEFAULTS.appearance.fontKey
    db.appearance.fontSize = Clamp(savedFontSize or frameFontSize, 8, 24)
end

local function GetChatFrameByName(name)
    return GetChatFramesByName(name)[1]
end

local function CloseChatFrame(frame)
    if not frame or not frame.GetID then
        return false
    end

    if FCF_Close and SafeCall(FCF_Close, frame) then
        return true
    end

    local frameID = frame:GetID()

    ClearFrameFilters(frame)

    if SetChatWindowShown then
        SafeCall(SetChatWindowShown, frameID, false)
    end

    if frame.Hide then
        SafeCall(frame.Hide, frame)
    end

    local tabFrame = _G["ChatFrame" .. frameID .. "Tab"]
    if tabFrame and tabFrame.Hide then
        SafeCall(tabFrame.Hide, tabFrame)
    end

    return true
end

local function EnsureChatFrame(tab)
    local frames = GetChatFramesByName(tab.name)
    local frame = frames[1]

    if not frame and db.createMissingTabs and FCF_OpenNewWindow then
        frame = FCF_OpenNewWindow(tab.name, true)
        frame = frame or GetChatFrameByName(tab.name)
    end

    if not frame then
        return nil, 0
    end

    local duplicatesRemoved = 0

    for index = 2, #frames do
        if CloseChatFrame(frames[index]) then
            duplicatesRemoved = duplicatesRemoved + 1
        end
    end

    if FCF_SetWindowName then
        SafeCall(FCF_SetWindowName, frame, tab.name)
    elseif SetChatWindowName and frame.GetID then
        SafeCall(SetChatWindowName, frame:GetID(), tab.name)
    end

    if db.dockTabs and FCF_DockFrame then
        if not SafeCall(FCF_DockFrame, frame, frame:GetID()) then
            SafeCall(FCF_DockFrame, frame)
        end
    end

    return frame, duplicatesRemoved
end

local function RemoveAllChannels(frame)
    if frame and frame.RemoveAllChannels then
        SafeCall(frame.RemoveAllChannels, frame)
        return
    end

    if ChatFrame_RemoveAllChannels then
        SafeCall(ChatFrame_RemoveAllChannels, frame)
        return
    end

    if not ChatFrame_RemoveChannel or type(frame.channelList) ~= "table" then
        return
    end

    local channels = {}
    for key, value in pairs(frame.channelList) do
        if type(key) == "string" then
            channels[#channels + 1] = key
        elseif type(value) == "string" then
            channels[#channels + 1] = value
        end
    end

    for _, channelName in ipairs(channels) do
        SafeCall(ChatFrame_RemoveChannel, frame, channelName)

        if RemoveChatWindowChannel and frame.GetID then
            SafeCall(RemoveChatWindowChannel, frame:GetID(), channelName)
        end
    end
end

function ClearFrameFilters(frame)
    if frame and frame.RemoveAllMessageGroups then
        SafeCall(frame.RemoveAllMessageGroups, frame)
    elseif ChatFrame_RemoveAllMessageGroups then
        SafeCall(ChatFrame_RemoveAllMessageGroups, frame)
    end

    RemoveAllChannels(frame)
end

local function AddMessageGroups(frame, groups)
    if type(groups) ~= "table" then
        return
    end

    for _, group in ipairs(groups) do
        if frame and frame.AddMessageGroup then
            SafeCall(frame.AddMessageGroup, frame, group)
        else
            SafeCall(ChatFrame_AddMessageGroup, frame, group)
        end
    end
end

local function AddChannelName(channels, channelName)
    if type(channelName) ~= "string" or channelName == "" or channels[channelName] then
        return
    end

    channels[channelName] = true
    channels[#channels + 1] = channelName
end

local function NormalizeChannelName(channelName)
    channelName = Trim(channelName or "")
    channelName = channelName:gsub("^%d+%.%s*", "")

    return string.lower(channelName)
end

local function GetJoinedChannels()
    local channels = {}

    if not GetChannelList then
        return channels
    end

    local values = { GetChannelList() }
    local index = 1

    while index <= #values do
        if type(values[index]) == "number" and type(values[index + 1]) == "string" then
            AddChannelName(channels, values[index + 1])
            index = index + 3
        else
            index = index + 1
        end
    end

    return channels
end

local function MatchesConfiguredChannel(tab, channelName)
    if type(channelName) ~= "string" then
        return false
    end

    local normalizedChannel = NormalizeChannelName(channelName)

    if type(tab.channels) == "table" then
        for _, configuredName in ipairs(tab.channels) do
            if normalizedChannel == NormalizeChannelName(configuredName) then
                return true
            end
        end
    end

    if type(tab.channelPatterns) == "table" then
        for _, pattern in ipairs(tab.channelPatterns) do
            if normalizedChannel:find(NormalizeChannelName(pattern), 1, true) then
                return true
            end
        end
    end

    return false
end

local function GetChannelsForTab(tab)
    local channels = {}

    if type(tab.channels) == "table" then
        for _, channelName in ipairs(tab.channels) do
            AddChannelName(channels, channelName)
        end
    end

    for _, channelName in ipairs(GetJoinedChannels()) do
        if MatchesConfiguredChannel(tab, channelName) then
            AddChannelName(channels, channelName)
        end
    end

    return channels
end

local function JoinMissingChannels(tab)
    if not db.autoJoinChannels or type(tab.channels) ~= "table" or not JoinChannelByName or not GetChannelName then
        return
    end

    for _, channelName in ipairs(tab.channels) do
        local _, joinedName = GetChannelName(channelName)
        if not joinedName then
            SafeCall(JoinChannelByName, channelName)
        end
    end
end

local function AddChannelToFrame(frame, channelName)
    if frame and frame.AddChannel then
        SafeCall(frame.AddChannel, frame, channelName)
    elseif ChatFrame_AddChannel then
        SafeCall(ChatFrame_AddChannel, frame, channelName)
    end

    if AddChatWindowChannel and frame and frame.GetID then
        SafeCall(AddChatWindowChannel, frame:GetID(), channelName)
    end
end

local function AddChannels(frame, tab)
    if not frame or (not frame.AddChannel and not ChatFrame_AddChannel) then
        return
    end

    JoinMissingChannels(tab)

    for _, channelName in ipairs(GetChannelsForTab(tab)) do
        AddChannelToFrame(frame, channelName)
    end
end

local function ApplyFrameAppearance(frame)
    local appearance = db and db.appearance
    local background = appearance and appearance.background

    if not appearance or not appearance.enabled or not background or not frame or not frame.GetID then
        return
    end

    local frameID = frame:GetID()
    local r = Clamp(background.r, 0, 1)
    local g = Clamp(background.g, 0, 1)
    local b = Clamp(background.b, 0, 1)
    local alpha = Clamp(background.alpha, 0, 1)
    local fontSize = Clamp(appearance.fontSize, 8, 24)
    local fontFile = GetSelectedFontFile()
    local fontFlags = appearance.fontFlags or ""

    if FCF_SetWindowColor then
        SafeCall(FCF_SetWindowColor, frame, r, g, b)
    elseif SetChatWindowColor then
        SafeCall(SetChatWindowColor, frameID, r, g, b)
    end

    if FCF_SetWindowAlpha then
        SafeCall(FCF_SetWindowAlpha, frame, alpha)
    elseif SetChatWindowAlpha then
        SafeCall(SetChatWindowAlpha, frameID, alpha)
    end

    if FCF_SetChatWindowFontSize then
        SafeCall(FCF_SetChatWindowFontSize, nil, frame, fontSize)
    elseif SetChatWindowSize then
        SafeCall(SetChatWindowSize, frameID, fontSize)
    end

    if fontFile and frame.SetFont then
        SafeCall(frame.SetFont, frame, fontFile, fontSize, fontFlags)
    end
end

local function ApplyAppearanceToCurrentTabs()
    local styled = 0

    if not db or not db.appearance or not db.appearance.enabled then
        return styled
    end

    for _, frame in ipairs(GetCurrentChatFrames()) do
        ApplyFrameAppearance(frame)
        styled = styled + 1
    end

    return styled
end

function addon:ApplyVisuals()
    ApplyAppearanceToCurrentTabs()
end

local function RefreshCurrentTabsText()
    if not currentTabsText then
        return
    end

    local names = GetCurrentChatTabNames()

    currentTabsText:SetText(FormatCurrentTabsText(names))
end

local function CloseManagedFrame(tab)
    local removed = 0

    if not tab then
        return removed
    end

    for _, frame in ipairs(GetChatFramesByName(tab.name)) do
        if CloseChatFrame(frame) then
            removed = removed + 1
        end
    end

    return removed
end

function addon:Apply(forceMessage)
    if not db or not db.enabled then
        if forceMessage then
            Print("disabled.", true)
        end
        return
    end

    local configured = 0
    local missing = 0
    local removed = 0
    local styled = 0

    if db.legacyRaidTabName then
        removed = removed + CloseManagedFrame({ name = db.legacyRaidTabName })
        db.legacyRaidTabName = nil
    end

    for _, key in ipairs(TAB_ORDER) do
        local tab = db.tabs and db.tabs[key]

        if tab and tab.enabled then
            local frame, duplicatesRemoved = EnsureChatFrame(tab)
            removed = removed + (duplicatesRemoved or 0)

            if frame then
                if db.clearManagedFilters then
                    ClearFrameFilters(frame)
                end

                AddMessageGroups(frame, tab.groups)
                AddChannels(frame, tab)
                configured = configured + 1
            else
                missing = missing + 1
            end
        elseif tab then
            removed = removed + CloseManagedFrame(tab)
        end
    end

    styled = ApplyAppearanceToCurrentTabs()

    if forceMessage and db.statusMessages then
        local message = "configured " .. configured .. " tabs"

        if removed > 0 then
            message = message .. "; removed " .. removed
        end

        if styled > 0 then
            message = message .. "; styled " .. styled
        end

        if missing > 0 then
            Print(message .. "; " .. missing .. " could not be created. Chat window limit may be full.", true)
        else
            Print(message .. ".", true)
        end
    end
end

local function CreateTitle(parent, text)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(text)
    return title
end

local function CreateDescription(parent, text, anchor)
    local description = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    description:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    description:SetJustifyH("LEFT")
    description:SetText(text)
    return description
end

local function CreateCheckButton(parent, label, tooltip, getValue, setValue, anchor, yOffset, onChange)
    controlIndex = controlIndex + 1

    local check = CreateFrame("CheckButton", ADDON_NAME .. "Option" .. controlIndex, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -8)

    if check.Text then
        check.Text:SetText(label)
    else
        local checkName = check:GetName()
        local textRegion = checkName and _G[checkName .. "Text"]

        if textRegion then
            textRegion:SetText(label)
        end
    end

    check.tooltipText = tooltip
    check:SetScript("OnClick", function(self)
        setValue(self:GetChecked() == true)

        if onChange then
            onChange()
        end
    end)

    parent.refreshers[#parent.refreshers + 1] = function()
        check:SetChecked(getValue() == true)
    end

    return check
end

local function CreateSlider(parent, label, tooltip, minValue, maxValue, step, getValue, setValue, anchor, yOffset, formatValue, lowLabel, highLabel, onChange, width)
    controlIndex = controlIndex + 1

    local sliderName = ADDON_NAME .. "Slider" .. controlIndex
    local slider = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    local sliderWidth = width or COMPACT_SLIDER_WIDTH
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, yOffset or -24)
    slider:SetWidth(sliderWidth)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.tooltipText = tooltip

    local labelText = _G[sliderName .. "Text"]
    local lowText = _G[sliderName .. "Low"]
    local highText = _G[sliderName .. "High"]

    if labelText then
        labelText:ClearAllPoints()
        labelText:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
        labelText:SetWidth(sliderWidth - 60)
        labelText:SetJustifyH("LEFT")
        labelText:SetText(label)
    end

    if lowText then
        lowText:SetText(lowLabel or tostring(minValue))
    end

    if highText then
        highText:SetText(highLabel or tostring(maxValue))
    end

    local valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 4)
    valueText:SetWidth(56)
    valueText:SetJustifyH("RIGHT")
    formatValue = formatValue or tostring

    local function SetValueText(value)
        valueText:SetText(formatValue(value))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = Round(value, 2)
        setValue(value)
        SetValueText(value)

        if onChange and not slider.refreshing then
            onChange()
        end
    end)

    parent.refreshers[#parent.refreshers + 1] = function()
        local value = Clamp(getValue(), minValue, maxValue)
        slider.refreshing = true
        slider:SetValue(value)
        slider.refreshing = false
        SetValueText(value)
    end

    return slider
end

local CreateButton

local function CreateDropdown(parent, label, tooltip, options, getValue, setValue, anchor, yOffset, onChange, width)
    controlIndex = controlIndex + 1

    local labelText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelText:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, yOffset or -18)
    labelText:SetText(label)

    local function GetLabelForValue(value)
        for _, option in ipairs(options) do
            if option.key == value then
                return option.label
            end
        end

        return options[1] and options[1].label or ""
    end

    if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton and UIDropDownMenu_SetWidth and UIDropDownMenu_SetText then
        local dropdownName = ADDON_NAME .. "Dropdown" .. controlIndex
        local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", -18, -2)
        dropdown.tooltipText = tooltip

        UIDropDownMenu_SetWidth(dropdown, width or COMPACT_DROPDOWN_WIDTH)
        UIDropDownMenu_Initialize(dropdown, function(_, level)
            for _, option in ipairs(options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.label
                info.checked = option.key == getValue()
                info.func = function()
                    setValue(option.key)
                    UIDropDownMenu_SetText(dropdown, GetLabelForValue(getValue()))

                    if onChange then
                        onChange()
                    end
                end

                UIDropDownMenu_AddButton(info, level)
            end
        end)

        parent.refreshers[#parent.refreshers + 1] = function()
            UIDropDownMenu_SetText(dropdown, GetLabelForValue(getValue()))
        end

        return dropdown
    end

    local button = CreateButton(parent, GetLabelForValue(getValue()), (width or COMPACT_DROPDOWN_WIDTH) + 30, labelText, 0)
    button.tooltipText = tooltip
    button:SetScript("OnClick", function()
        local currentValue = getValue()
        local nextIndex = 1

        for index, option in ipairs(options) do
            if option.key == currentValue then
                nextIndex = index + 1
                break
            end
        end

        if nextIndex > #options then
            nextIndex = 1
        end

        setValue(options[nextIndex].key)
        button:SetText(GetLabelForValue(getValue()))

        if onChange then
            onChange()
        end
    end)

    parent.refreshers[#parent.refreshers + 1] = function()
        button:SetText(GetLabelForValue(getValue()))
    end

    return button
end

local function CreateColorPicker(parent, label, tooltip, getColor, setColor, anchor, yOffset)
    controlIndex = controlIndex + 1

    local button = CreateFrame("Button", ADDON_NAME .. "Color" .. controlIndex, parent)
    button:SetSize(24, 24)
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, yOffset or -14)
    button.tooltipText = tooltip

    local swatch = button:CreateTexture(nil, "BACKGROUND")
    swatch:SetAllPoints()
    swatch:SetColorTexture(1, 1, 1, 1)
    button.swatch = swatch

    local border = button:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.75, 0.75, 0.75, 1)
    border:SetDrawLayer("BORDER", -1)

    local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", button, "RIGHT", 8, 0)
    text:SetText(label)

    local function RefreshSwatch()
        local color = getColor()
        swatch:SetColorTexture(Clamp(color.r, 0, 1), Clamp(color.g, 0, 1), Clamp(color.b, 0, 1), 1)
    end

    local function OpenPicker()
        local color = getColor()
        local original = {
            r = Clamp(color.r, 0, 1),
            g = Clamp(color.g, 0, 1),
            b = Clamp(color.b, 0, 1),
            a = Clamp(color.alpha, 0, 1),
        }

        local function ApplyColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()

            if ColorPickerFrame.GetColorAlpha then
                setColor(r, g, b, ColorPickerFrame:GetColorAlpha())
            else
                setColor(r, g, b, ColorPickerFrame.opacity or original.a)
            end

            RefreshSwatch()
            addon:RefreshOptions()
        end

        local function CancelColor()
            addon:RefreshOptions()
        end

        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = original.r,
                g = original.g,
                b = original.b,
                opacity = original.a,
                hasOpacity = true,
                swatchFunc = ApplyColor,
                opacityFunc = ApplyColor,
                cancelFunc = CancelColor,
            })
        elseif ColorPickerFrame then
            ColorPickerFrame.func = ApplyColor
            ColorPickerFrame.opacityFunc = ApplyColor
            ColorPickerFrame.cancelFunc = CancelColor
            ColorPickerFrame.hasOpacity = true
            ColorPickerFrame.opacity = original.a
            ColorPickerFrame.previousValues = { original.r, original.g, original.b, original.a }
            ColorPickerFrame:SetColorRGB(original.r, original.g, original.b)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end

    button:SetScript("OnClick", OpenPicker)
    parent.refreshers[#parent.refreshers + 1] = RefreshSwatch

    return button
end

function CreateButton(parent, label, width, anchor, xOffset)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, 24)
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset or 0, -16)
    button:SetText(label)
    return button
end

function addon:RefreshOptions(syncAppearance)
    if not optionsPanel or type(optionsPanel.refreshers) ~= "table" then
        return
    end

    if syncAppearance then
        SyncAppearanceFromCurrentTabs()
    end

    RefreshCurrentTabsText()

    for _, refresh in ipairs(optionsPanel.refreshers) do
        refresh()
    end
end

local function CreateOptionsContent(panel)
    if panel.content then
        return panel.content
    end

    local scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "OptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 0)

    local content = CreateFrame("Frame", ADDON_NAME .. "OptionsContent", scrollFrame)
    content:SetSize(760, 980)
    content.refreshers = panel.refreshers
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(width - 12, PANEL_MIN_WIDTH))
    end)

    panel.scrollFrame = scrollFrame
    panel.content = content

    return content
end

local function BuildOptionsPanel(panel)
    if panel.built then
        addon:RefreshOptions()
        return
    end

    panel.built = true
    panel.refreshers = {}

    local content = CreateOptionsContent(panel)
    SyncAppearanceFromCurrentTabs()

    local title = CreateTitle(content, DISPLAY_NAME)
    local description = CreateDescription(content, "Global settings for automatically creating and maintaining managed chat tabs.", title)

    local routingTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    routingTitle:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -24)
    routingTitle:SetText("Managed routing")

    local clearFilters = CreateCheckButton(content, "Replace filters on managed tabs", "Clear existing filters before adding this addon's configured message groups and channels.", function()
        return db.clearManagedFilters
    end, function(value)
        db.clearManagedFilters = value
    end, routingTitle, -8)

    local autoJoin = CreateCheckButton(content, "Auto-join named channels", "Try to join configured named channels such as Trade and Services when they are available.", function()
        return db.autoJoinChannels
    end, function(value)
        db.autoJoinChannels = value
    end, clearFilters, -4)

    local status = CreateCheckButton(content, "Show status messages", "Print a short confirmation when tabs are configured.", function()
        return db.statusMessages
    end, function(value)
        db.statusMessages = value
    end, autoJoin, -4)

    local tabsTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tabsTitle:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -18)
    tabsTitle:SetText("Managed tabs")

    local previous = tabsTitle
    for _, key in ipairs(TAB_ORDER) do
        previous = CreateCheckButton(content, TAB_LABELS[key], "Enable or disable this managed chat tab.", function()
            return db.tabs[key].enabled
        end, function(value)
            db.tabs[key].enabled = value
        end, previous, -4)
    end

    local apply = CreateButton(content, "Apply Now", 110, previous, 0)
    apply:SetScript("OnClick", function()
        addon:Apply(true)
    end)

    local reset = CreateButton(content, "Reset", 90, previous, 120)
    reset:SetScript("OnClick", function()
        ResetDatabase()
        addon:RefreshOptions()
        Print("settings reset. Click Apply Now to update chat tabs.", true)
    end)

    local appearanceTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    appearanceTitle:SetPoint("TOPLEFT", description, "BOTTOMLEFT", RIGHT_COLUMN_OFFSET, -24)
    appearanceTitle:SetText("All chat tab appearance")

    currentTabsText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    currentTabsText:SetPoint("TOPLEFT", appearanceTitle, "BOTTOMLEFT", 0, -8)
    currentTabsText:SetWidth(RIGHT_COLUMN_WIDTH)
    currentTabsText:SetHeight(72)
    currentTabsText:SetJustifyH("LEFT")
    currentTabsText:SetJustifyV("TOP")
    currentTabsText:SetWordWrap(true)

    if currentTabsText.SetNonSpaceWrap then
        currentTabsText:SetNonSpaceWrap(false)
    end

    local applyAppearance = CreateCheckButton(content, "Apply visual settings live", "Apply the configured color, opacity, and font size to every current chat tab.", function()
        return db.appearance.enabled
    end, function(value)
        db.appearance.enabled = value
    end, currentTabsText, -8, function()
        addon:ApplyVisuals()
    end)

    local colorPicker = CreateColorPicker(content, "Background color", "Choose the background color for all current chat tabs.", function()
        return db.appearance.background
    end, function(r, g, b, alpha)
        local background = db.appearance.background
        background.r = Clamp(r, 0, 1)
        background.g = Clamp(g, 0, 1)
        background.b = Clamp(b, 0, 1)
        background.alpha = Clamp(alpha or background.alpha, 0, 1)
        addon:ApplyVisuals()
    end, applyAppearance, -8)

    local opacity = CreateSlider(content, "Background opacity", "Set the background opacity for all current chat tabs.", 0, 1, 0.01, function()
        return db.appearance.background.alpha
    end, function(value)
        db.appearance.background.alpha = Clamp(value, 0, 1)
    end, colorPicker, -28, function(value)
        return string.format("%d%%", math.floor((value * 100) + 0.5))
    end, "0%", "100%", function()
        addon:ApplyVisuals()
    end, COMPACT_SLIDER_WIDTH)

    local fontFace = CreateDropdown(content, "Font face", "Set the font face for all current chat tabs.", FONT_OPTIONS, function()
        return db.appearance.fontKey or DEFAULTS.appearance.fontKey
    end, function(value)
        db.appearance.fontKey = value

        local option = GetFontOptionByKey(value)
        if option and option.file then
            db.appearance.fontFile = option.file
        end
    end, opacity, -34, function()
        addon:ApplyVisuals()
    end, COMPACT_DROPDOWN_WIDTH)

    local fontSize = CreateSlider(content, "Font size", "Set the font size for all current chat tabs.", 8, 24, 1, function()
        return db.appearance.fontSize
    end, function(value)
        db.appearance.fontSize = Clamp(value, 8, 24)
    end, fontFace, -30, function(value)
        return string.format("%d", math.floor(value + 0.5))
    end, "8", "24", function()
        addon:ApplyVisuals()
    end, COMPACT_SLIDER_WIDTH)

    addon:RefreshOptions()
end

function addon:RegisterOptions()
    optionsPanel = CreateFrame("Frame", ADDON_NAME .. "OptionsPanel")
    optionsPanel.name = DISPLAY_NAME
    optionsPanel:SetScript("OnShow", BuildOptionsPanel)
    self.optionsPanel = optionsPanel

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, DISPLAY_NAME)
        Settings.RegisterAddOnCategory(settingsCategory)
        self.settingsCategory = settingsCategory
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(optionsPanel)
    end
end

function addon:OpenOptions()
    if Settings and Settings.OpenToCategory and settingsCategory and settingsCategory.ID then
        Settings.OpenToCategory(settingsCategory.ID)
        return
    end

    if SettingsPanel and SettingsPanel.OpenToCategory and settingsCategory and settingsCategory.ID then
        SettingsPanel:OpenToCategory(settingsCategory.ID)
        return
    end

    if InterfaceOptionsFrame_OpenToCategory and optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    end
end

local function PrintHelp()
    Print("Open " .. DISPLAY_NAME .. " and click Apply Now to update chat tabs.", true)
    Print(COMMAND .. " options - open global settings.", true)
    Print(COMMAND .. " enable | disable - toggle the addon.", true)
    Print(COMMAND .. " tab <guild|party|communities|trade|whispers|local> on|off - toggle a tab.", true)
    Print(COMMAND .. " reset - restore default settings.", true)
end

local function NormalizeTabKey(key)
    key = LowerCommand(key)

    if key == "local" then
        return "localChannels"
    end

    return key
end

local function HandleSlashCommand(message)
    local command = LowerCommand(message)

    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "apply" then
        Print("open options and click Apply Now to update chat tabs.", true)
    elseif command == "options" or command == "config" or command == "settings" then
        addon:OpenOptions()
    elseif command == "enable" then
        db.enabled = true
        Print("enabled. Click Apply Now to update chat tabs.", true)
    elseif command == "disable" then
        db.enabled = false
        Print("disabled.", true)
    elseif command == "reset" then
        ResetDatabase()
        addon:RefreshOptions()
        Print("settings reset. Click Apply Now to update chat tabs.", true)
    else
        local tabKey, state = command:match("^tab%s+(%S+)%s+(on)$")
        tabKey = tabKey or command:match("^tab%s+(%S+)%s+(off)$")
        state = state or command:match("^tab%s+%S+%s+(off)$")

        if tabKey and state then
            tabKey = NormalizeTabKey(tabKey)

            if db.tabs[tabKey] then
                db.tabs[tabKey].enabled = state == "on"
                addon:RefreshOptions()
                Print(TAB_LABELS[tabKey] .. " tab " .. state .. ". Click Apply Now to update chat tabs.", true)
                return
            end
        end

        Print("unknown command. Type " .. COMMAND .. " help.", true)
    end
end

function addon:OnAddonLoaded()
    ChatTabsOrganizerDB = CopyDefaults(DEFAULTS, ChatTabsOrganizerDB)
    db = ChatTabsOrganizerDB
    self.db = db
    MigrateDatabase()

    self:RegisterOptions()

    SLASH_CHATTABSORGANIZER1 = COMMAND
    SLASH_CHATTABSORGANIZER2 = "/chattabs"
    SlashCmdList.CHATTABSORGANIZER = HandleSlashCommand
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...

        if loadedAddon == ADDON_NAME then
            addon:OnAddonLoaded()
        end
    end
end)
