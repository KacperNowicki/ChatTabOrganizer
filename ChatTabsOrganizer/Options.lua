local ADDON_NAME, addon = ...

local Clamp = addon.Clamp
local Print = addon.Print

local mainCategory
local tabsCategory
local tabsPanel
local registeredSettings = {}

local LIST_ROWS = addon.MAX_TABS
local ROW_HEIGHT = 26
local LEFT_X = 16
local RIGHT_X = 320

local function DB()
    return addon.db
end

local function CategoryID(category)
    if not category then
        return nil
    end

    if category.GetID then
        local ok, id = pcall(category.GetID, category)

        if ok and id then
            return id
        end
    end

    return category.ID
end

---------------------------------------------------------------------------
-- Background color picker
---------------------------------------------------------------------------

local function OpenColorPicker()
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
        Print("the color picker is unavailable.", true)
        return
    end

    local background = DB().appearance.background
    local original = {
        r = Clamp(background.r, 0, 1),
        g = Clamp(background.g, 0, 1),
        b = Clamp(background.b, 0, 1),
        a = Clamp(background.alpha, 0, 1),
    }

    local function SetColor(r, g, b, a)
        local bg = DB().appearance.background
        bg.r = Clamp(r, 0, 1)
        bg.g = Clamp(g, 0, 1)
        bg.b = Clamp(b, 0, 1)
        bg.alpha = Clamp(a, 0, 1)
        addon:ApplyVisuals()
    end

    local function OnChanged()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or original.a
        SetColor(r, g, b, a)
    end

    ColorPickerFrame:SetupColorPickerAndShow({
        r = original.r,
        g = original.g,
        b = original.b,
        opacity = original.a,
        hasOpacity = true,
        swatchFunc = OnChanged,
        opacityFunc = OnChanged,
        cancelFunc = function()
            SetColor(original.r, original.g, original.b, original.a)
        end,
    })
end

---------------------------------------------------------------------------
-- Main settings page (native vertical layout)
---------------------------------------------------------------------------

local function RegisterMainCategory()
    local category, layout = Settings.RegisterVerticalLayoutCategory(addon.DISPLAY_NAME)
    local defaults = addon.DEFAULTS

    local function Header(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end

    local function Button(name, buttonText, onClick, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
    end

    local function Proxy(variable, name, defaultValue, getValue, setValue)
        local setting = Settings.RegisterProxySetting(category, "ChatTabsOrganizer_" .. variable, type(defaultValue), name, defaultValue, getValue, setValue)
        registeredSettings[#registeredSettings + 1] = setting
        return setting
    end

    local function Checkbox(field, name, tooltip, onChange)
        local setting = Proxy(field, name, defaults[field], function()
            return DB()[field] and true or false
        end, function(value)
            DB()[field] = value and true or false

            if onChange then
                onChange(value)
            end
        end)

        Settings.CreateCheckbox(category, setting, tooltip)
        return setting
    end

    local function QuietApply()
        addon:Apply(false)
    end

    Header("General")

    Checkbox("enabled", "Enable Chat Tabs Organizer", "Turn the addon off to leave your chat windows alone. Messages it removed from the main chat tab are put back.", function(value)
        if value then
            addon:Apply(false)
        else
            addon:RestoreMainTab()
        end
    end)

    Checkbox("autoApply", "Apply automatically at login", "Create and update managed tabs every time you log in or reload the UI. When this is off, click Apply now or type /ctabs apply.")
    Checkbox("statusMessages", "Show status messages", "Print a short summary in chat when tabs are updated.")

    Header("Managed tabs")

    Button("Tabs", "Edit tabs", function()
        addon:OpenOptions(true)
    end, "Choose which tabs exist, what each one shows, and their order.")

    Checkbox("removeFromMainTab", "Remove routed messages from the main chat tab", "Messages shown in a managed tab (for example Guild or Trade) stop appearing in your main chat tab too. Turn this off before uninstalling the addon to get them back.", QuietApply)
    Checkbox("clearManagedFilters", "Replace filters on managed tabs", "Clear each managed tab's existing filters before adding the ones configured here. When this is off, the configured filters are added on top of whatever the tab already shows.")
    Checkbox("dockTabs", "Keep managed tabs docked and in order", "Dock managed tabs next to your main chat tab, in the order set in the tab editor.")
    Checkbox("autoJoinChannels", "Auto-join named channels", "Try to join channels listed on enabled tabs (for example Trade and Services) when tabs are updated.")

    Button("Apply", "Apply now", function()
        addon:Apply(true)
    end, "Create, update and close managed tabs now.")

    Button("Channels", "Join channels", function()
        addon:JoinSelectedChannels()
    end, "Join every named channel listed on an enabled tab.")

    Header("Appearance (all chat tabs)")

    local appearanceDefaults = defaults.appearance

    local appearanceEnabled = Proxy("appearanceEnabled", "Apply visual settings to all chat tabs", appearanceDefaults.enabled, function()
        return DB().appearance.enabled and true or false
    end, function(value)
        DB().appearance.enabled = value and true or false
        addon:ApplyVisuals()
    end)
    Settings.CreateCheckbox(category, appearanceEnabled, "Use the color, opacity and font below on every chat tab, including whisper windows. When this is off, your chat windows keep their own settings.")

    Button("Background color", "Choose color", OpenColorPicker, "Choose the background color (and opacity) of every chat tab.")

    local opacity = Proxy("opacity", "Background opacity", appearanceDefaults.background.alpha, function()
        return Clamp(DB().appearance.background.alpha, 0, 1)
    end, function(value)
        DB().appearance.background.alpha = Clamp(value, 0, 1)
        addon:ApplyVisuals()
    end)
    local opacityOptions = Settings.CreateSliderOptions(0, 1, 0.01)
    opacityOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format("%d%%", math.floor(value * 100 + 0.5))
    end)
    Settings.CreateSlider(category, opacity, opacityOptions, "Background opacity of every chat tab.")

    local fontFace = Proxy("fontFace", "Font", appearanceDefaults.fontKey, function()
        return addon:GetFontOption(DB().appearance.fontKey).key
    end, function(value)
        DB().appearance.fontKey = value
        addon:ApplyVisuals()
    end)
    Settings.CreateDropdown(category, fontFace, function()
        local container = Settings.CreateControlTextContainer()

        for _, option in ipairs(addon.FONT_OPTIONS) do
            container:Add(option.key, option.label)
        end

        return container:GetData()
    end, "Font used by every chat tab.")

    local fontSize = Proxy("fontSize", "Font size", appearanceDefaults.fontSize, function()
        return Clamp(DB().appearance.fontSize, 8, 24)
    end, function(value)
        DB().appearance.fontSize = Clamp(math.floor(value + 0.5), 8, 24)
        addon:ApplyVisuals()
    end)
    local fontSizeOptions = Settings.CreateSliderOptions(8, 24, 1)
    fontSizeOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format("%d", math.floor(value + 0.5))
    end)
    Settings.CreateSlider(category, fontSize, fontSizeOptions, "Font size of every chat tab.")

    return category
end

---------------------------------------------------------------------------
-- Tab editor page (custom canvas)
---------------------------------------------------------------------------

StaticPopupDialogs["CHATTABSORGANIZER_DELETE_TAB"] = {
    text = "Delete the tab \"%s\"? Its chat window will be closed.",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, key)
        addon:DeleteTab(key)
        addon:Apply(false)

        if tabsPanel then
            tabsPanel.selectedKey = nil
            tabsPanel:Refresh()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CHATTABSORGANIZER_RESTORE_TABS"] = {
    text = "Restore the default tabs? Your custom tabs will be deleted and their chat windows closed.",
    button1 = OKAY or "Okay",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        addon:RestoreDefaultTabs()
        addon:Apply(false)

        if tabsPanel then
            tabsPanel.selectedKey = nil
            tabsPanel:Refresh()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateLabel(parent, text, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function CreateCheck(parent, size)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(size or 24, size or 24)
    return check
end

local function CreatePanelButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, 22)
    button:SetText(text)
    return button
end

local function CreateArrowButton(parent, direction)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(20, 20)

    local base = "Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. direction
    button:SetNormalTexture(base .. "-Up")
    button:SetPushedTexture(base .. "-Down")
    button:SetDisabledTexture(base .. "-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    return button
end

local function CreateEditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    return box
end

local function AttachTooltip(region, text)
    region:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    region:SetScript("OnLeave", GameTooltip_Hide)
end

local function BuildTabsPanel(panel)
    if panel.built then
        return
    end

    panel.built = true

    local title = CreateLabel(panel, "Tabs", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT_X, -16)

    local description = CreateLabel(panel, "Tick a tab to create it; untick it to close its window. Changes apply right away.", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetPoint("RIGHT", panel, "RIGHT", -16, 0)

    -- Tab list --------------------------------------------------------------

    local listTitle = CreateLabel(panel, "Managed tabs")
    listTitle:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)

    panel.rows = {}

    for index = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(RIGHT_X - LEFT_X - 24, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", -4, -6 - (index - 1) * ROW_HEIGHT)

        row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
        row.selectedTexture:SetAllPoints()
        row.selectedTexture:SetColorTexture(1, 0.82, 0, 0.18)

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)

        row.check = CreateCheck(row)
        row.check:SetPoint("LEFT", 2, 0)

        row.label = CreateLabel(row, "", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -48, 0)
        row.label:SetWordWrap(false)

        row.down = CreateArrowButton(row, "Down")
        row.down:SetPoint("RIGHT", -2, 0)

        row.up = CreateArrowButton(row, "Up")
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)

        row:SetScript("OnClick", function(self)
            panel.selectedKey = self.key
            panel:Refresh()
        end)

        row.check:SetScript("OnClick", function(self)
            addon:SetTabEnabled(row.key, self:GetChecked())
            panel.selectedKey = row.key
            addon:Apply(false)
            panel:Refresh()
        end)

        row.up:SetScript("OnClick", function()
            if addon:MoveTab(row.key, -1) then
                addon:Apply(false)
                panel:Refresh()
            end
        end)

        row.down:SetScript("OnClick", function()
            if addon:MoveTab(row.key, 1) then
                addon:Apply(false)
                panel:Refresh()
            end
        end)

        panel.rows[index] = row
    end

    local newTab = CreatePanelButton(panel, "New tab", 110)
    newTab:SetPoint("TOPLEFT", panel.rows[LIST_ROWS], "BOTTOMLEFT", 4, -10)
    newTab:SetScript("OnClick", function()
        local key, err = addon:CreateCustomTab()

        if key then
            panel.selectedKey = key
            panel:SetStatus("New tab added. Pick what it shows, then tick it in the list to create it.")
        else
            panel:SetStatus(err, true)
        end

        panel:Refresh()
    end)
    panel.newTab = newTab

    local restore = CreatePanelButton(panel, "Restore defaults", 130)
    restore:SetPoint("LEFT", newTab, "RIGHT", 8, 0)
    restore:SetScript("OnClick", function()
        StaticPopup_Show("CHATTABSORGANIZER_RESTORE_TABS")
    end)

    -- Editor ---------------------------------------------------------------

    local editorTitle = CreateLabel(panel, "Selected tab")
    editorTitle:SetPoint("TOPLEFT", listTitle, "TOPLEFT", RIGHT_X - LEFT_X, 0)
    panel.editorTitle = editorTitle

    local kindText = CreateLabel(panel, "", "GameFontDisableSmall")
    kindText:SetPoint("LEFT", editorTitle, "RIGHT", 8, 0)
    panel.kindText = kindText

    local nameLabel = CreateLabel(panel, "Name", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", editorTitle, "BOTTOMLEFT", 0, -12)

    local nameBox = CreateEditBox(panel, 200)
    nameBox:SetPoint("LEFT", nameLabel, "LEFT", 70, 0)
    nameBox:SetMaxLetters(30)
    panel.nameBox = nameBox

    local function CommitName(self)
        local key = panel.selectedKey

        if not key then
            return
        end

        local tab = addon:GetTab(key)
        local ok, err = addon:RenameTab(key, self:GetText())

        if ok then
            addon:Apply(false)
            panel:SetStatus(nil)
        else
            self:SetText(tab and tab.name or "")
            panel:SetStatus(err, true)
        end

        panel:Refresh()
    end

    nameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    nameBox:SetScript("OnEditFocusLost", CommitName)
    nameBox:SetScript("OnEscapePressed", function(self)
        local tab = panel.selectedKey and addon:GetTab(panel.selectedKey)
        self:SetText(tab and tab.name or "")
        self:ClearFocus()
    end)

    local typesLabel = CreateLabel(panel, "Shows", "GameFontHighlight")
    typesLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -18)

    panel.typeChecks = {}
    local column, rowIndex = 0, 0

    for _, messageType in ipairs(addon.MESSAGE_TYPES) do
        local available = false

        for _, group in ipairs(messageType.groups) do
            if addon.GroupExists(group) then
                available = true
                break
            end
        end

        if available then
            local check = CreateCheck(panel, 22)
            check:SetPoint("TOPLEFT", typesLabel, "BOTTOMLEFT", column * 150 - 2, -4 - rowIndex * 22)

            local label = CreateLabel(panel, messageType.label, "GameFontHighlightSmall")
            label:SetPoint("LEFT", check, "RIGHT", 2, 0)

            check.messageType = messageType
            check:SetScript("OnClick", function(self)
                if panel.selectedKey then
                    addon:SetTabMessageType(panel.selectedKey, self.messageType, self:GetChecked())
                    addon:Apply(false)
                    panel:Refresh()
                end
            end)

            panel.typeChecks[#panel.typeChecks + 1] = check

            column = column + 1

            if column > 1 then
                column = 0
                rowIndex = rowIndex + 1
            end
        end
    end

    local channelsLabel = CreateLabel(panel, "Channels", "GameFontHighlight")
    channelsLabel:SetPoint("TOPLEFT", typesLabel, "BOTTOMLEFT", 0, -14 - (rowIndex + (column > 0 and 1 or 0)) * 22)

    local channelsBox = CreateEditBox(panel, 270)
    channelsBox:SetPoint("TOPLEFT", channelsLabel, "BOTTOMLEFT", 6, -4)
    panel.channelsBox = channelsBox
    AttachTooltip(channelsBox, "Channel names separated by commas, for example: Trade, Services. Use the names your game client shows. \"Trade\" also matches \"Trade - City\".")

    channelsBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    channelsBox:SetScript("OnEditFocusLost", function(self)
        if panel.selectedKey then
            addon:SetTabChannels(panel.selectedKey, self:GetText())
            addon:Apply(false)
            panel:Refresh()
        end
    end)
    channelsBox:SetScript("OnEscapePressed", function(self)
        local tab = panel.selectedKey and addon:GetTab(panel.selectedKey)
        self:SetText(tab and table.concat(tab.channels, ", ") or "")
        self:ClearFocus()
    end)

    local channelsHint = CreateLabel(panel, "Comma-separated, e.g. Trade, Services", "GameFontDisableSmall")
    channelsHint:SetPoint("TOPLEFT", channelsBox, "BOTTOMLEFT", -6, -4)

    local deleteButton = CreatePanelButton(panel, "Delete tab", 110)
    deleteButton:SetPoint("TOPLEFT", channelsHint, "BOTTOMLEFT", 0, -14)
    deleteButton:SetScript("OnClick", function()
        local key = panel.selectedKey
        local tab = key and addon:GetTab(key)

        if tab and not addon:IsBuiltinTab(key) then
            StaticPopup_Show("CHATTABSORGANIZER_DELETE_TAB", tab.name, nil, key)
        end
    end)
    panel.deleteButton = deleteButton

    local applyButton = CreatePanelButton(panel, "Apply now", 110)
    applyButton:SetPoint("LEFT", deleteButton, "RIGHT", 8, 0)
    applyButton:SetScript("OnClick", function()
        addon:Apply(true)
        panel:Refresh()
    end)

    local status = CreateLabel(panel, "", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", newTab, "BOTTOMLEFT", 0, -14)
    status:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    status:SetWordWrap(true)
    panel.status = status
end

local function SetStatus(panel, text, isError)
    if not panel.status then
        return
    end

    panel.status:SetText(text or "")

    if isError then
        panel.status:SetTextColor(1, 0.3, 0.3)
    else
        panel.status:SetTextColor(1, 1, 1)
    end
end

local function RefreshTabsPanel(panel)
    if not panel.built then
        return
    end

    local order = addon:GetTabOrder()

    if not panel.selectedKey or not addon:GetTab(panel.selectedKey) then
        panel.selectedKey = order[1]
    end

    for index, row in ipairs(panel.rows) do
        local key = order[index]

        if key then
            local tab = addon:GetTab(key)
            row.key = key
            row.label:SetText(tab.name)
            row.check:SetChecked(tab.enabled)
            row.selectedTexture:SetShown(key == panel.selectedKey)
            row.up:SetEnabled(index > 1)
            row.down:SetEnabled(index < #order)
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end

    panel.newTab:SetEnabled(#order < addon.MAX_TABS)

    local key = panel.selectedKey
    local tab = key and addon:GetTab(key)

    if not tab then
        return
    end

    panel.kindText:SetText(addon:IsBuiltinTab(key) and "built-in (can be turned off, not deleted)" or "custom")

    if not panel.nameBox:HasFocus() then
        panel.nameBox:SetText(tab.name)
        panel.nameBox:SetCursorPosition(0)
    end

    if not panel.channelsBox:HasFocus() then
        panel.channelsBox:SetText(table.concat(tab.channels, ", "))
        panel.channelsBox:SetCursorPosition(0)
    end

    for _, check in ipairs(panel.typeChecks) do
        check:SetChecked(addon:TabHasMessageType(key, check.messageType))
    end

    panel.deleteButton:SetEnabled(not addon:IsBuiltinTab(key))

    local db = DB()

    if not db.enabled then
        panel:SetStatus("The addon is turned off, so changes won't affect your chat windows until you turn it back on.", true)
    end
end

local function RegisterTabsCategory(parent)
    tabsPanel = CreateFrame("Frame", ADDON_NAME .. "TabsPanel")
    tabsPanel.name = "Tabs"
    tabsPanel.parent = addon.DISPLAY_NAME
    tabsPanel.Refresh = RefreshTabsPanel
    tabsPanel.SetStatus = SetStatus

    tabsPanel:SetScript("OnShow", function(self)
        BuildTabsPanel(self)
        self:SetStatus(nil)
        self:Refresh()
    end)

    local category = Settings.RegisterCanvasLayoutSubcategory(parent, tabsPanel, "Tabs")
    return category
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function addon:OnApplied(result)
    if not tabsPanel or not tabsPanel.built or not tabsPanel:IsShown() then
        return
    end

    tabsPanel:Refresh()

    if result and result.missing > 0 then
        tabsPanel:SetStatus("Couldn't create " .. table.concat(result.missingNames, ", ")
            .. ". WoW allows only " .. (NUM_CHAT_WINDOWS or 10) .. " chat windows; close one you don't use and try again.", true)
    end
end

function addon:RefreshOptions()
    if tabsPanel and tabsPanel.built and tabsPanel:IsShown() then
        tabsPanel:Refresh()
    end
end

function addon:RegisterOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        Print("this game version doesn't support the settings page. Use " .. self.COMMAND .. " help.", true)
        return
    end

    mainCategory = RegisterMainCategory()
    tabsCategory = RegisterTabsCategory(mainCategory)
    Settings.RegisterAddOnCategory(mainCategory)

    self.settingsCategory = mainCategory
end

function addon:OpenOptions(openTabs)
    local category = openTabs and tabsCategory or mainCategory
    local id = CategoryID(category)

    if Settings and Settings.OpenToCategory and id then
        Settings.OpenToCategory(id)
    else
        Print("the settings page is unavailable.", true)
    end
end
