local ADDON_NAME, addon = ...

local DISPLAY_NAME = "Chat Tabs Organizer"
local COMMAND = "/ctabs"
local DB_VERSION = 7
local MAX_TABS = 10
local LOGIN_APPLY_DELAY = 2
local CHANNEL_REFRESH_DELAY = 1.5

addon.DISPLAY_NAME = DISPLAY_NAME
addon.COMMAND = COMMAND
addon.MAX_TABS = MAX_TABS

addon.FONT_OPTIONS = {
    { key = "default", label = "Default", file = "Fonts\\FRIZQT__.TTF" },
    { key = "arial", label = "Arial Narrow", file = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", label = "Morpheus", file = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", label = "Skurri", file = "Fonts\\SKURRI.TTF" },
}

-- Message types offered in the tab editor. Each maps to one or more ChatTypeGroup keys.
-- Types whose groups don't exist in the running client are hidden automatically.
addon.MESSAGE_TYPES = {
    { key = "say", label = "Say", groups = { "SAY" } },
    { key = "yell", label = "Yell", groups = { "YELL" } },
    { key = "emote", label = "Emotes", groups = { "EMOTE" } },
    { key = "guild", label = "Guild", groups = { "GUILD" } },
    { key = "officer", label = "Officer", groups = { "OFFICER" } },
    { key = "guildAchievement", label = "Guild achievements", groups = { "GUILD_ACHIEVEMENT" } },
    { key = "guildDiscord", label = "Guild Discord", groups = { "GUILD_DISCORD" } },
    { key = "party", label = "Party", groups = { "PARTY", "PARTY_LEADER" } },
    { key = "raid", label = "Raid", groups = { "RAID", "RAID_LEADER", "RAID_WARNING" } },
    { key = "instance", label = "Instance", groups = { "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } },
    { key = "whisper", label = "Whispers", groups = { "WHISPER" } },
    { key = "bnWhisper", label = "Battle.net whispers", groups = { "BN_WHISPER" } },
    { key = "communities", label = "Communities", groups = { "COMMUNITIES_CHANNEL" } },
    { key = "achievement", label = "Achievements", groups = { "ACHIEVEMENT" } },
    { key = "loot", label = "Loot", groups = { "LOOT" } },
    { key = "currency", label = "Currency", groups = { "CURRENCY" } },
    { key = "money", label = "Money", groups = { "MONEY" } },
    { key = "tradeskills", label = "Professions", groups = { "TRADESKILLS" } },
    { key = "system", label = "System", groups = { "SYSTEM" } },
    { key = "errors", label = "Errors", groups = { "ERRORS" } },
}

local DEFAULT_TAB_ORDER = { "guild", "party", "communities", "trade", "whispers", "localChannels" }

local DEFAULT_TABS = {
    guild = {
        enabled = true,
        name = "Guild",
        groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" },
        channels = {},
    },
    party = {
        enabled = true,
        name = "Party",
        groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" },
        channels = {},
    },
    communities = {
        enabled = true,
        name = "Communities",
        groups = { "COMMUNITIES_CHANNEL" },
        channels = {},
    },
    trade = {
        enabled = true,
        name = "Trade",
        groups = {},
        channels = { "Trade", "Services" },
    },
    whispers = {
        enabled = false,
        name = "Whispers",
        groups = { "WHISPER", "BN_WHISPER" },
        channels = {},
    },
    localChannels = {
        enabled = false,
        name = "Local",
        groups = {},
        channels = { "General", "LocalDefense", "LookingForGroup" },
    },
}

local DEFAULTS = {
    enabled = true,
    autoApply = true,
    dockTabs = true,
    clearManagedFilters = true,
    removeFromMainTab = false,
    autoJoinChannels = false,
    statusMessages = true,
    nextCustomId = 1,
    appearance = {
        enabled = true,
        fontKey = "default",
        fontSize = 14,
        background = {
            r = 0.02,
            g = 0.02,
            b = 0.02,
            alpha = 0.35,
        },
    },
}

addon.DEFAULTS = DEFAULTS

local db
local charDB
local eventFrame = CreateFrame("Frame")
local pendingApply
local channelRefreshQueued = false
local loginApplied = false

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue

    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end

    return value
end

local function Trim(value)
    return (tostring(value or "")):match("^%s*(.-)%s*$")
end

local function Lower(value)
    return string.lower(Trim(value))
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, inner in pairs(value) do
        copy[key] = DeepCopy(inner)
    end

    return copy
end

-- Fills in missing keys only. Not used for tabs: array merging by index would
-- resurrect entries the user removed.
local function CopyDefaults(source, target)
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

local function IndexOf(list, value)
    for index, item in ipairs(list) do
        if item == value then
            return index
        end
    end

    return nil
end

local function IndexOfInsensitive(list, value)
    local wanted = Lower(value)

    for index, item in ipairs(list) do
        if Lower(item) == wanted then
            return index
        end
    end

    return nil
end

local function AddUnique(list, value)
    value = Trim(value)

    if value ~= "" and not IndexOfInsensitive(list, value) then
        list[#list + 1] = value
    end
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return false
    end

    return pcall(func, ...)
end

local function FrameCall(frame, method, ...)
    local func = frame and frame[method]

    if type(func) ~= "function" then
        return false
    end

    return pcall(func, frame, ...)
end

local function FrameHas(frame, method, value)
    local ok, result = FrameCall(frame, method, value)
    return ok and result and true or false
end

local function Print(message, force)
    if not DEFAULT_CHAT_FRAME then
        return
    end

    if force or (db and db.statusMessages) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. DISPLAY_NAME .. ":|r " .. tostring(message))
    end
end

addon.Print = Print
addon.Trim = Trim
addon.Clamp = Clamp

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local function NewTab(source)
    return {
        enabled = source.enabled and true or false,
        name = source.name,
        groups = DeepCopy(source.groups or {}),
        channels = DeepCopy(source.channels or {}),
    }
end

local function MigrateDatabase()
    local oldVersion = tonumber(db.version) or 0

    if oldVersion >= DB_VERSION then
        return
    end

    if type(db.tabs) == "table" then
        if db.tabs.raid then
            db.legacyRaidTabName = db.tabs.raid.name or "Raid"
            db.tabs.raid = nil
        end

        for _, tab in pairs(db.tabs) do
            if type(tab) == "table" then
                local groups = {}

                for _, group in ipairs(tab.groups or {}) do
                    -- 0.1.x used a group name that doesn't exist, so the Communities tab was always empty.
                    if group == "COMMUNITIES" then
                        group = "COMMUNITIES_CHANNEL"
                    end

                    -- CHANNEL is now added automatically for tabs that list channels.
                    if group ~= "CHANNEL" then
                        AddUnique(groups, group)
                    end
                end

                local channels = {}

                for _, channel in ipairs(tab.channels or {}) do
                    AddUnique(channels, channel)
                end

                for _, channel in ipairs(tab.channelPatterns or {}) do
                    AddUnique(channels, channel)
                end

                tab.groups = groups
                tab.channels = channels
                tab.channelPatterns = nil
            end
        end
    end

    db.createMissingTabs = nil

    if type(db.appearance) == "table" then
        if db.appearance.fontKey == "current" then
            db.appearance.fontKey = DEFAULTS.appearance.fontKey
        end

        db.appearance.fontFile = nil
        db.appearance.fontFlags = nil
        db.appearance.applyToAllTabs = nil
    end

    db.version = DB_VERSION
end

local function EnsureStructure()
    CopyDefaults(DEFAULTS, db)
    db.version = DB_VERSION

    if type(db.tabs) ~= "table" then
        db.tabs = {}
    end

    for key, defaults in pairs(DEFAULT_TABS) do
        if type(db.tabs[key]) ~= "table" then
            db.tabs[key] = NewTab(defaults)
        end
    end

    for key, tab in pairs(db.tabs) do
        if type(tab) ~= "table" then
            db.tabs[key] = nil
        else
            tab.name = Trim(tab.name)

            if tab.name == "" then
                tab.name = (DEFAULT_TABS[key] and DEFAULT_TABS[key].name) or key
            end

            tab.enabled = tab.enabled and true or false
            tab.groups = type(tab.groups) == "table" and tab.groups or {}
            tab.channels = type(tab.channels) == "table" and tab.channels or {}
        end
    end

    -- Rebuild the order: keep valid known keys, then append anything missing.
    local order = {}
    local seen = {}

    if type(db.tabOrder) == "table" then
        for _, key in ipairs(db.tabOrder) do
            if db.tabs[key] and not seen[key] then
                order[#order + 1] = key
                seen[key] = true
            end
        end
    end

    for _, key in ipairs(DEFAULT_TAB_ORDER) do
        if db.tabs[key] and not seen[key] then
            order[#order + 1] = key
            seen[key] = true
        end
    end

    local extras = {}

    for key in pairs(db.tabs) do
        if not seen[key] then
            extras[#extras + 1] = key
        end
    end

    table.sort(extras)

    for _, key in ipairs(extras) do
        order[#order + 1] = key
    end

    db.tabOrder = order
end

local function EnsureCharStructure()
    if type(charDB.owned) ~= "table" then
        charDB.owned = {}
    end

    if type(charDB.mainRemoved) ~= "table" then
        charDB.mainRemoved = {}
    end

    if type(charDB.mainRemoved.groups) ~= "table" then
        charDB.mainRemoved.groups = {}
    end

    if type(charDB.mainRemoved.channels) ~= "table" then
        charDB.mainRemoved.channels = {}
    end
end

---------------------------------------------------------------------------
-- Chat windows
---------------------------------------------------------------------------

local function NumChatWindows()
    if NUM_CHAT_WINDOWS then
        return NUM_CHAT_WINDOWS
    end

    if Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows then
        return Constants.ChatFrameConstants.MaxChatWindows
    end

    return 10
end

local function NumReservedWindows()
    if C_ChatInfo and C_ChatInfo.GetNumReservedChatWindows then
        local ok, count = pcall(C_ChatInfo.GetNumReservedChatWindows)

        if ok and type(count) == "number" then
            return count
        end
    end

    return 2
end

local function GetWindowName(id)
    local name = GetChatWindowInfo(id)
    return Trim(name)
end

-- The main chat window and Combat Log are never created, renamed or closed by this addon.
local function IsReservedFrame(frame)
    if not frame or not frame.GetID then
        return true
    end

    return frame == DEFAULT_CHAT_FRAME
        or frame == COMBATLOG
        or frame:GetID() <= NumReservedWindows()
end

-- FCF_Close only hides a window and keeps its name, so a name match alone
-- doesn't mean the window is open.
local function IsWindowActive(id)
    if FCF_IsChatWindowIndexActive then
        local ok, active = pcall(FCF_IsChatWindowIndexActive, id)

        if ok then
            return active and true or false
        end
    end

    local shown = select(7, GetChatWindowInfo(id))

    if shown then
        return true
    end

    local frame = _G["ChatFrame" .. id]
    return frame and frame.isDocked and true or false
end

local function GetActiveFrames()
    local frames = {}

    for id = 1, NumChatWindows() do
        local frame = _G["ChatFrame" .. id]

        if frame and GetWindowName(id) ~= "" and IsWindowActive(id) then
            frames[#frames + 1] = frame
        end
    end

    return frames
end

-- Numbered windows plus any open temporary (whisper) windows.
local function GetStylableFrames()
    local frames = GetActiveFrames()

    if type(CHAT_FRAMES) == "table" then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local frame = _G[frameName]

            if frame and frame.isTemporary and frame.inUse ~= false and not IndexOf(frames, frame) then
                frames[#frames + 1] = frame
            end
        end
    end

    return frames
end

local function FindFramesByName(name)
    local frames = {}
    local wanted = Lower(name)

    if wanted == "" then
        return frames
    end

    for _, frame in ipairs(GetActiveFrames()) do
        if not IsReservedFrame(frame) and Lower(GetWindowName(frame:GetID())) == wanted then
            frames[#frames + 1] = frame
        end
    end

    return frames
end

local function ClearFrameFilters(frame)
    FrameCall(frame, "RemoveAllMessageGroups")
    FrameCall(frame, "RemoveAllChannels")
end

local function CloseChatFrame(frame)
    if not frame or IsReservedFrame(frame) then
        return false
    end

    if FCF_Close and SafeCall(FCF_Close, frame) then
        return true
    end

    ClearFrameFilters(frame)

    if SetChatWindowShown then
        SafeCall(SetChatWindowShown, frame:GetID(), false)
    end

    FrameCall(frame, "Hide")

    local tabFrame = _G["ChatFrame" .. frame:GetID() .. "Tab"]
    FrameCall(tabFrame, "Hide")

    return true
end

-- Returns the window this addon created or adopted for a tab, if it is still
-- open and still carries the name we gave it. The name check stops us from
-- touching a window the user opened later in the same slot.
local function GetOwnedFrame(key)
    local owned = charDB.owned[key]

    if type(owned) ~= "table" or type(owned.id) ~= "number" then
        charDB.owned[key] = nil
        return nil
    end

    local frame = _G["ChatFrame" .. owned.id]

    if frame
        and not IsReservedFrame(frame)
        and IsWindowActive(owned.id)
        and Lower(GetWindowName(owned.id)) == Lower(owned.name)
    then
        return frame
    end

    charDB.owned[key] = nil
    return nil
end

local function SetOwnedFrame(key, frame, name)
    charDB.owned[key] = { id = frame:GetID(), name = name }
end

local function IsOwnedByOtherTab(frame, key)
    for otherKey, owned in pairs(charDB.owned) do
        if otherKey ~= key and type(owned) == "table" and owned.id == frame:GetID() then
            return true
        end
    end

    return false
end

local function CloseOwnedFrame(key)
    local frame = GetOwnedFrame(key)
    charDB.owned[key] = nil

    if frame and CloseChatFrame(frame) then
        return 1
    end

    return 0
end

local function CloseFramesNamed(name)
    local closed = 0

    for _, frame in ipairs(FindFramesByName(name)) do
        if CloseChatFrame(frame) then
            closed = closed + 1
        end
    end

    return closed
end

-- Finds (or creates, unless findOnly) the window for a tab.
-- Returns frame, created, duplicatesClosed.
local function EnsureChatFrame(key, tab, findOnly)
    local frame = GetOwnedFrame(key)
    local sameName = FindFramesByName(tab.name)

    if not frame then
        for _, candidate in ipairs(sameName) do
            if not IsOwnedByOtherTab(candidate, key) then
                frame = candidate
                break
            end
        end
    end

    if findOnly then
        return frame, false, 0
    end

    local created = false

    if not frame and FCF_OpenNewWindow then
        local ok, newFrame = pcall(FCF_OpenNewWindow, tab.name, true)

        if ok and type(newFrame) == "table" and newFrame.GetID then
            frame = newFrame
        else
            frame = FindFramesByName(tab.name)[1]
        end

        created = frame ~= nil
    end

    if not frame then
        return nil, false, 0
    end

    if Trim(GetWindowName(frame:GetID())) ~= tab.name then
        if FCF_SetWindowName then
            SafeCall(FCF_SetWindowName, frame, tab.name)
        elseif SetChatWindowName then
            SafeCall(SetChatWindowName, frame:GetID(), tab.name)
        end
    end

    SetOwnedFrame(key, frame, tab.name)

    local duplicatesClosed = 0

    for _, other in ipairs(sameName) do
        if other ~= frame and not IsOwnedByOtherTab(other, key) and CloseChatFrame(other) then
            duplicatesClosed = duplicatesClosed + 1
        end
    end

    return frame, created, duplicatesClosed
end

-- Keeps managed tabs docked, in the configured order, after the user's own tabs.
local function OrderDock(frames)
    if #frames == 0 or not FCF_DockFrame or not GENERAL_CHAT_DOCK then
        return
    end

    local docked = GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES

    if type(docked) == "table" then
        local inOrder = true
        local lastPosition = 0

        for _, frame in ipairs(frames) do
            local position = IndexOf(docked, frame)

            if not position or position < lastPosition then
                inOrder = false
                break
            end

            lastPosition = position
        end

        if inOrder then
            return
        end
    end

    local selected

    if FCFDock_GetSelectedWindow then
        local ok, window = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        selected = ok and window or nil
    end

    -- FCF_DockFrame ignores frames that are already docked, so undock first
    -- and re-dock at the end of the dock to move them.
    for _, frame in ipairs(frames) do
        if frame.isDocked and FCF_UnDockFrame then
            SafeCall(FCF_UnDockFrame, frame)
        end

        SafeCall(FCF_DockFrame, frame)
    end

    if selected and FCFDock_SelectWindow then
        SafeCall(FCFDock_SelectWindow, GENERAL_CHAT_DOCK, selected)
    end
end

---------------------------------------------------------------------------
-- Channels and routing
---------------------------------------------------------------------------

local function NormalizeChannelName(channelName)
    channelName = Trim(channelName)
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
            AddUnique(channels, values[index + 1])
            index = index + 3
        else
            index = index + 1
        end
    end

    return channels
end

-- "Trade" matches "Trade", "Trade - City" and "Trade (Services)", but not "Tradesmen".
local function ChannelMatches(configuredName, channelName)
    local configured = NormalizeChannelName(configuredName)
    local actual = NormalizeChannelName(channelName)

    if configured == "" or actual:sub(1, #configured) ~= configured then
        return false
    end

    local nextChar = actual:sub(#configured + 1, #configured + 1)
    return nextChar == "" or not nextChar:match("[%w]")
end

local function GetNamedChannelsForTab(tab)
    local channels = {}

    for _, channelName in ipairs(tab.channels) do
        AddUnique(channels, channelName)
    end

    if #channels == 0 then
        return channels
    end

    for _, joined in ipairs(GetJoinedChannels()) do
        for _, configured in ipairs(tab.channels) do
            if ChannelMatches(configured, joined) then
                AddUnique(channels, joined)
                break
            end
        end
    end

    return channels
end

local function GetCommunityChannels()
    local channels = {}

    if not (C_Club and C_Club.GetSubscribedClubs and C_Club.GetStreams and GetChannelName) then
        return channels
    end

    local okClubs, clubs = pcall(C_Club.GetSubscribedClubs)

    if not okClubs or type(clubs) ~= "table" then
        return channels
    end

    for _, club in ipairs(clubs) do
        local okStreams, streams = pcall(C_Club.GetStreams, club.clubId)

        if okStreams and type(streams) == "table" then
            for _, stream in ipairs(streams) do
                local channelName

                if ChatFrameUtil and ChatFrameUtil.GetCommunitiesChannelName then
                    channelName = ChatFrameUtil.GetCommunitiesChannelName(club.clubId, stream.streamId)
                else
                    channelName = ("Community:%s:%s"):format(tostring(club.clubId), tostring(stream.streamId))
                end

                -- Only streams that are joined as chat channels can be routed.
                local channelID = GetChannelName(channelName)

                if type(channelID) == "number" and channelID > 0 then
                    AddUnique(channels, channelName)
                end
            end
        end
    end

    return channels
end

local function GroupExists(group)
    return type(ChatTypeGroup) ~= "table" or ChatTypeGroup[group] ~= nil
end

addon.GroupExists = GroupExists

-- Adds a tab's message groups and channels to its window (without removing
-- anything) and records what was routed.
local function RouteTab(frame, tab, routed)
    for _, group in ipairs(tab.groups) do
        if GroupExists(group) then
            if not FrameHas(frame, "ContainsMessageGroup", group) then
                FrameCall(frame, "AddMessageGroup", group)
            end

            routed.groups[group] = true
        end
    end

    local channels = GetNamedChannelsForTab(tab)

    if #channels > 0 and not FrameHas(frame, "ContainsMessageGroup", "CHANNEL") then
        FrameCall(frame, "AddMessageGroup", "CHANNEL")
    end

    if IndexOf(tab.groups, "COMMUNITIES_CHANNEL") then
        for _, channelName in ipairs(GetCommunityChannels()) do
            AddUnique(channels, channelName)
        end
    end

    for _, channelName in ipairs(channels) do
        if not FrameHas(frame, "ContainsChannel", channelName) then
            FrameCall(frame, "AddChannel", channelName)
        end

        routed.channels[channelName] = true
    end
end

-- Removes routed groups/channels from the main chat window, and puts back
-- anything this addon removed earlier that is no longer routed elsewhere.
-- Pass nil to restore everything.
local function UpdateMainTab(routed)
    local main = DEFAULT_CHAT_FRAME or ChatFrame1

    if not main or not charDB then
        return
    end

    local removed = charDB.mainRemoved
    routed = routed or { groups = {}, channels = {} }

    for group in pairs(removed.groups) do
        if not routed.groups[group] then
            FrameCall(main, "AddMessageGroup", group)
            removed.groups[group] = nil
        end
    end

    for channelName in pairs(removed.channels) do
        if not routed.channels[channelName] then
            FrameCall(main, "AddChannel", channelName)
            removed.channels[channelName] = nil
        end
    end

    for group in pairs(routed.groups) do
        -- CHANNEL covers every channel, so it is never removed as a whole;
        -- individual channels are removed below instead.
        if group ~= "CHANNEL" and not removed.groups[group] and FrameHas(main, "ContainsMessageGroup", group) then
            FrameCall(main, "RemoveMessageGroup", group)
            removed.groups[group] = true
        end
    end

    for channelName in pairs(routed.channels) do
        if not removed.channels[channelName] and FrameHas(main, "ContainsChannel", channelName) then
            FrameCall(main, "RemoveChannel", channelName)
            removed.channels[channelName] = true
        end
    end
end

function addon:RestoreMainTab()
    UpdateMainTab(nil)
end

local function IsChannelJoined(channelName)
    if not GetChannelName then
        return false
    end

    local channelID, joinedName = GetChannelName(channelName)

    return (type(channelID) == "number" and channelID > 0)
        or (type(joinedName) == "string" and joinedName ~= "")
end

local function RequestChannelJoins(channels)
    local requested, alreadyJoined, failed = 0, 0, 0

    if not JoinChannelByName then
        return requested, alreadyJoined, #channels
    end

    for _, channelName in ipairs(channels) do
        if IsChannelJoined(channelName) then
            alreadyJoined = alreadyJoined + 1
        elseif SafeCall(JoinChannelByName, channelName) then
            requested = requested + 1
        else
            failed = failed + 1
        end
    end

    return requested, alreadyJoined, failed
end

local function GetEnabledNamedChannels()
    local channels = {}

    for _, key in ipairs(db.tabOrder) do
        local tab = db.tabs[key]

        if tab.enabled then
            for _, channelName in ipairs(tab.channels) do
                AddUnique(channels, channelName)
            end
        end
    end

    return channels
end

function addon:JoinSelectedChannels()
    local channels = GetEnabledNamedChannels()

    if #channels == 0 then
        Print("no enabled tabs list named channels.", true)
        return
    end

    if not JoinChannelByName then
        Print("channel joining is unavailable.", true)
        return
    end

    local requested, alreadyJoined, failed = RequestChannelJoins(channels)
    local parts = {}

    if requested > 0 then
        parts[#parts + 1] = "requested " .. requested
    end

    if alreadyJoined > 0 then
        parts[#parts + 1] = alreadyJoined .. " already joined"
    end

    if failed > 0 then
        parts[#parts + 1] = failed .. " failed"
    end

    if #parts == 0 then
        parts[1] = "nothing to join"
    end

    Print("channels: " .. table.concat(parts, "; ") .. ".", true)
end

---------------------------------------------------------------------------
-- Appearance
---------------------------------------------------------------------------

function addon:GetFontOption(key)
    for _, option in ipairs(self.FONT_OPTIONS) do
        if option.key == key then
            return option
        end
    end

    return self.FONT_OPTIONS[1]
end

local function ApplyFrameAppearance(frame)
    local appearance = db.appearance
    local background = appearance.background
    local frameID = frame:GetID()
    local r = Clamp(background.r, 0, 1)
    local g = Clamp(background.g, 0, 1)
    local b = Clamp(background.b, 0, 1)
    local alpha = Clamp(background.alpha, 0, 1)
    local fontSize = Clamp(appearance.fontSize, 8, 24)
    local fontFile = addon:GetFontOption(appearance.fontKey).file

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

    -- WoW saves the font size but not the face, so the face is re-applied at
    -- every login and whenever a chat window opens.
    local ok, _, _, fontFlags = FrameCall(frame, "GetFont")
    FrameCall(frame, "SetFont", fontFile, fontSize, (ok and fontFlags) or "")
end

local function ApplyAppearance()
    if not db or not db.enabled or not db.appearance.enabled then
        return 0
    end

    local styled = 0

    for _, frame in ipairs(GetStylableFrames()) do
        ApplyFrameAppearance(frame)
        styled = styled + 1
    end

    return styled
end

function addon:ApplyVisuals()
    return ApplyAppearance()
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

local function QueueAfterCombat(verbose, light)
    if not pendingApply then
        pendingApply = { verbose = false, light = true }
    end

    pendingApply.verbose = pendingApply.verbose or verbose
    pendingApply.light = pendingApply.light and light

    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- verbose: print a summary.
-- light: only add newly available channels to existing tabs (used when
-- channels change); don't create, close, clear, dock or restyle anything.
function addon:Apply(verbose, light)
    if not db then
        return nil
    end

    if not db.enabled then
        UpdateMainTab(nil)

        if verbose then
            Print("disabled. Type " .. COMMAND .. " enable to turn it back on.", true)
        end

        return nil
    end

    if InCombatLockdown and InCombatLockdown() then
        QueueAfterCombat(verbose, light)

        if verbose then
            Print("in combat; tabs will be updated when combat ends.", true)
        end

        return nil
    end

    local result = { configured = 0, missing = 0, removed = 0, styled = 0, missingNames = {} }
    local routed = { groups = {}, channels = {} }
    local managedFrames = {}

    if not light then
        if db.legacyRaidTabName then
            result.removed = result.removed + CloseFramesNamed(db.legacyRaidTabName)
            db.legacyRaidTabName = nil
        end

        -- Windows that belonged to tabs that have since been deleted.
        for key in pairs(charDB.owned) do
            if not db.tabs[key] then
                result.removed = result.removed + CloseOwnedFrame(key)
            end
        end
    end

    for _, key in ipairs(db.tabOrder) do
        local tab = db.tabs[key]

        if tab.enabled then
            local frame, created, duplicatesClosed = EnsureChatFrame(key, tab, light)
            result.removed = result.removed + duplicatesClosed

            if frame then
                if not light and (created or db.clearManagedFilters) then
                    ClearFrameFilters(frame)
                end

                if db.autoJoinChannels and not light then
                    RequestChannelJoins(tab.channels)
                end

                RouteTab(frame, tab, routed)
                managedFrames[#managedFrames + 1] = frame
                result.configured = result.configured + 1
            elseif not light then
                result.missing = result.missing + 1
                result.missingNames[#result.missingNames + 1] = tab.name
            end
        elseif not light then
            result.removed = result.removed + CloseOwnedFrame(key)
        end
    end

    if not light and db.dockTabs then
        OrderDock(managedFrames)
    end

    UpdateMainTab(db.removeFromMainTab and routed or nil)

    if not light then
        result.styled = ApplyAppearance()
        self.lastResult = result
    end

    if verbose then
        local message = "configured " .. result.configured .. " tab" .. (result.configured == 1 and "" or "s")

        if result.removed > 0 then
            message = message .. "; closed " .. result.removed
        end

        if result.styled > 0 then
            message = message .. "; styled " .. result.styled
        end

        if result.missing > 0 then
            message = message .. "; couldn't create " .. table.concat(result.missingNames, ", ")
                .. " (the chat window limit is probably full)"
        end

        Print(message .. ".", true)
    end

    if not light and self.OnApplied then
        self:OnApplied(result)
    end

    return result
end

---------------------------------------------------------------------------
-- Tab management (used by the options panel and slash commands)
---------------------------------------------------------------------------

function addon:GetTabOrder()
    return db.tabOrder
end

function addon:GetTab(key)
    return db.tabs[key]
end

function addon:IsBuiltinTab(key)
    return DEFAULT_TABS[key] ~= nil
end

function addon:FindTabKey(query)
    local wanted = Lower(query)

    if wanted == "local" then
        wanted = "localchannels"
    end

    for _, key in ipairs(db.tabOrder) do
        if Lower(key) == wanted or Lower(db.tabs[key].name) == wanted then
            return key
        end
    end

    return nil
end

function addon:SetTabEnabled(key, enabled)
    local tab = db.tabs[key]

    if tab then
        tab.enabled = enabled and true or false
    end
end

function addon:ValidateTabName(key, name)
    name = Trim(name)

    if name == "" then
        return nil, "The name can't be empty."
    end

    if #name > 30 then
        return nil, "The name must be 30 characters or fewer."
    end

    for otherKey, tab in pairs(db.tabs) do
        if otherKey ~= key and Lower(tab.name) == Lower(name) then
            return nil, "Another tab already uses that name."
        end
    end

    for id = 1, NumReservedWindows() do
        if Lower(GetWindowName(id)) == Lower(name) then
            return nil, "That name belongs to a built-in chat window."
        end
    end

    return name
end

function addon:RenameTab(key, name)
    local tab = db.tabs[key]

    if not tab then
        return false, "Unknown tab."
    end

    local validName, err = self:ValidateTabName(key, name)

    if not validName then
        return false, err
    end

    tab.name = validName
    return true
end

function addon:SetTabChannels(key, text)
    local tab = db.tabs[key]

    if not tab then
        return
    end

    local channels = {}

    for part in tostring(text or ""):gmatch("[^,]+") do
        AddUnique(channels, part)
    end

    tab.channels = channels
end

function addon:TabHasMessageType(key, messageType)
    local tab = db.tabs[key]
    local anyAvailable = false

    for _, group in ipairs(messageType.groups) do
        if GroupExists(group) then
            anyAvailable = true

            if not IndexOf(tab.groups, group) then
                return false
            end
        end
    end

    return anyAvailable
end

function addon:SetTabMessageType(key, messageType, enabled)
    local tab = db.tabs[key]

    if not tab then
        return
    end

    for _, group in ipairs(messageType.groups) do
        local index = IndexOf(tab.groups, group)

        if enabled and not index and GroupExists(group) then
            tab.groups[#tab.groups + 1] = group
        elseif not enabled and index then
            table.remove(tab.groups, index)
        end
    end
end

function addon:MoveTab(key, delta)
    local order = db.tabOrder
    local index = IndexOf(order, key)
    local target = index and (index + delta)

    if not index or target < 1 or target > #order then
        return false
    end

    order[index], order[target] = order[target], order[index]
    return true
end

function addon:CreateCustomTab()
    if #db.tabOrder >= MAX_TABS then
        return nil, "You can have at most " .. MAX_TABS .. " tabs."
    end

    local key

    repeat
        key = "custom" .. db.nextCustomId
        db.nextCustomId = db.nextCustomId + 1
    until not db.tabs[key]

    local name = "New tab"
    local suffix = 1

    while not self:ValidateTabName(key, name) do
        suffix = suffix + 1
        name = "New tab " .. suffix
    end

    db.tabs[key] = { enabled = false, name = name, groups = {}, channels = {} }
    db.tabOrder[#db.tabOrder + 1] = key

    return key
end

function addon:DeleteTab(key)
    if self:IsBuiltinTab(key) or not db.tabs[key] then
        return false
    end

    CloseOwnedFrame(key)
    db.tabs[key] = nil

    local index = IndexOf(db.tabOrder, key)

    if index then
        table.remove(db.tabOrder, index)
    end

    return true
end

function addon:RestoreDefaultTabs()
    for key in pairs(db.tabs) do
        if not self:IsBuiltinTab(key) then
            CloseOwnedFrame(key)
            db.tabs[key] = nil
        end
    end

    for key, defaults in pairs(DEFAULT_TABS) do
        db.tabs[key] = NewTab(defaults)
    end

    db.tabOrder = DeepCopy(DEFAULT_TAB_ORDER)
end

function addon:ResetAll()
    ChatTabsOrganizerDB = {}
    db = ChatTabsOrganizerDB
    self.db = db
    EnsureStructure()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function PrintHelp()
    Print("commands:", true)
    Print(COMMAND .. " options - open settings.", true)
    Print(COMMAND .. " tabs - open the tab editor.", true)
    Print(COMMAND .. " apply - update chat tabs now.", true)
    Print(COMMAND .. " list - list managed tabs.", true)
    Print(COMMAND .. " tab <name> on|off - turn a tab on or off.", true)
    Print(COMMAND .. " join - join named channels used by enabled tabs.", true)
    Print(COMMAND .. " enable | disable - turn the addon on or off.", true)
    Print(COMMAND .. " reset - restore all default settings.", true)
end

local function PrintTabList()
    for index, key in ipairs(db.tabOrder) do
        local tab = db.tabs[key]
        local state = tab.enabled and "|cff33ff99on|r" or "|cff999999off|r"
        Print(index .. ". " .. tab.name .. " - " .. state, true)
    end
end

local function HandleSlashCommand(message)
    local command = Lower(message)

    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "options" or command == "config" or command == "settings" then
        addon:OpenOptions()
    elseif command == "tabs" or command == "edit" then
        addon:OpenOptions(true)
    elseif command == "apply" then
        addon:Apply(true)
    elseif command == "list" then
        PrintTabList()
    elseif command == "join" then
        addon:JoinSelectedChannels()
    elseif command == "enable" then
        db.enabled = true
        addon:Apply(true)
    elseif command == "disable" then
        db.enabled = false
        UpdateMainTab(nil)
        Print("disabled. Your chat windows were left as they are.", true)
    elseif command == "reset" then
        addon:ResetAll()
        addon:Apply(true)
        Print("settings reset.", true)
    else
        local query, state = command:match("^tab%s+(.-)%s+(%a+)$")

        if query and (state == "on" or state == "off") then
            local key = addon:FindTabKey(query)

            if key then
                addon:SetTabEnabled(key, state == "on")
                addon:Apply(false)
                Print(db.tabs[key].name .. " tab " .. state .. ".", true)

                if addon.RefreshOptions then
                    addon:RefreshOptions()
                end
            else
                Print("no tab named \"" .. query .. "\". Type " .. COMMAND .. " list.", true)
            end

            return
        end

        Print("unknown command. Type " .. COMMAND .. " help.", true)
    end
end

---------------------------------------------------------------------------
-- Startup and events
---------------------------------------------------------------------------

local function OnLoginApply()
    loginApplied = true

    if not db.enabled then
        return
    end

    if db.autoApply then
        addon:Apply(false)
    else
        ApplyAppearance()
    end
end

local function ScheduleChannelRefresh()
    if channelRefreshQueued or not loginApplied or not C_Timer then
        return
    end

    channelRefreshQueued = true

    C_Timer.After(CHANNEL_REFRESH_DELAY, function()
        channelRefreshQueued = false

        if db.enabled and db.autoApply then
            addon:Apply(false, true)
        end
    end)
end

local function RestyleSoon()
    if C_Timer then
        C_Timer.After(0, ApplyAppearance)
    else
        ApplyAppearance()
    end
end

function addon:OnAddonLoaded()
    if type(ChatTabsOrganizerDB) ~= "table" then
        ChatTabsOrganizerDB = {}
    end

    if type(ChatTabsOrganizerCharDB) ~= "table" then
        ChatTabsOrganizerCharDB = {}
    end

    db = ChatTabsOrganizerDB
    charDB = ChatTabsOrganizerCharDB
    self.db = db

    MigrateDatabase()
    EnsureStructure()
    EnsureCharStructure()

    if self.RegisterOptions then
        local ok, err = pcall(self.RegisterOptions, self)

        if not ok then
            Print("couldn't build the settings page: " .. tostring(err), true)
        end
    end

    if hooksecurefunc then
        if FCF_OpenTemporaryWindow then
            hooksecurefunc("FCF_OpenTemporaryWindow", RestyleSoon)
        end

        if FCF_OpenNewWindow then
            hooksecurefunc("FCF_OpenNewWindow", RestyleSoon)
        end
    end

    SLASH_CHATTABSORGANIZER1 = COMMAND
    SLASH_CHATTABSORGANIZER2 = "/chattabs"
    SlashCmdList.CHATTABSORGANIZER = HandleSlashCommand
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            self:UnregisterEvent("ADDON_LOADED")
            addon:OnAddonLoaded()
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
            self:RegisterEvent("CHANNEL_UI_UPDATE")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...

        if isInitialLogin or isReloadingUi then
            if C_Timer then
                C_Timer.After(LOGIN_APPLY_DELAY, OnLoginApply)
            else
                OnLoginApply()
            end
        end
    elseif event == "CHANNEL_UI_UPDATE" then
        ScheduleChannelRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")

        local pending = pendingApply
        pendingApply = nil

        if pending then
            addon:Apply(pending.verbose, pending.light)
        end
    end
end)
