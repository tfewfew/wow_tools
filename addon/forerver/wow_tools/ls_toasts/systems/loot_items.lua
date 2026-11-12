local addonTable = WoWTools.lsToasts
local E, L, C = addonTable.E, addonTable.L, addonTable.C

-- Lua
local _G = getfenv(0)
local next = _G.next
local t_insert = _G.table.insert
local t_sort = _G.table.sort
local t_wipe = _G.table.wipe
local tonumber = _G.tonumber
local tostring = _G.tostring

-- Mine
local PLAYER_GUID, PLAYER_NAME

local LOOT_ITEM_CREATED_PATTERN
local LOOT_ITEM_CREATED_MULTIPLE_PATTERN
local LOOT_ITEM_PATTERN
local LOOT_ITEM_MULTIPLE_PATTERN
local LOOT_ITEM_PUSHED_PATTERN
local LOOT_ITEM_PUSHED_MULTIPLE_PATTERN

local function buildPattern(global)
    -- Build a Lua pattern from a client global string.
    -- If the global is missing/nil (e.g. a LOOT_ITEM_* string removed or
    -- renamed on the 16001/Midnight client), return a pattern that can
    -- never match ("$^") instead of throwing, so UpdatePatterns can't crash
    -- and silently kill the whole loot system.
    if global then
        return global:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
    end

    return "$^"
end

local function updatePatterns()
    LOOT_ITEM_CREATED_PATTERN = buildPattern(LOOT_ITEM_CREATED_SELF)
    LOOT_ITEM_CREATED_MULTIPLE_PATTERN = buildPattern(LOOT_ITEM_CREATED_SELF_MULTIPLE)
    LOOT_ITEM_PATTERN = buildPattern(LOOT_ITEM_SELF)
    LOOT_ITEM_MULTIPLE_PATTERN = buildPattern(LOOT_ITEM_SELF_MULTIPLE)
    LOOT_ITEM_PUSHED_PATTERN = buildPattern(LOOT_ITEM_PUSHED_SELF)
    LOOT_ITEM_PUSHED_MULTIPLE_PATTERN = buildPattern(LOOT_ITEM_PUSHED_SELF_MULTIPLE)
end

local function delayedUpdatePatterns()
    C_Timer.After(0.1, updatePatterns)
end

local function Toast_OnClick(self)
    if self._data.link and IsModifiedClick("DRESSUP") then
        DressUpItemLink(self._data.link)
    elseif self._data.item_id then
        local slot = E:SearchBagsForItemID(self._data.item_id)
        if slot >= 0 then
            OpenBag(slot)
        end
    end
end

local function Toast_OnEnter(self)
    if self._data.tooltip_link then
        GameTooltip:SetHyperlink(self._data.tooltip_link)
        GameTooltip:Show()
    end
end

local function PostSetAnimatedValue(self, value)
    self:SetText(value == 1 and "" or value)
end

local function Toast_SetUp(event, link, quantity)
    local sanitizedLink, originalLink, _, itemID = E:SanitizeLink(link)
    local toast, isQueued = E:FindToast(event, "link", sanitizedLink)
    if not toast then
        local ok, name, _, quality, _, _, _, _, _, _, icon, _, classID, subClassID, bindType =
            pcall(C_Item.GetItemInfo, originalLink)
        if not ok then
            return
        end
        for _, value in pairs({ name, quality, icon, classID, subClassID, bindType }) do
            if not E:IsReadable(value) then
                return
            end
        end
        local isMaterial = classID == 7 and subClassID == 0
        local isPet = classID == 15 and subClassID == 2
        local isQuestItem = bindType == 4 or (classID == 12 and subClassID == 0)

        if
            name
            and (
                (quality and quality >= C.db.profile.types.loot_items.threshold and quality <= 5)
                or (isMaterial and C.db.profile.types.loot_items.material)
                or (isPet and C.db.profile.types.loot_items.pet)
                or (isQuestItem and C.db.profile.types.loot_items.quest)
                or C.db.profile.types.loot_items.filters[itemID]
            )
        then
            toast = E:GetToast(event, "link", sanitizedLink)
            local color = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
            local title = L["YOU_RECEIVED"]
            local soundFile = "Interface\\AddOns\\wow_tools\\ls_toasts\\assets\\ui-common-loot-toast.OGG"

            toast.IconText1.PostSetAnimatedValue = PostSetAnimatedValue

            if C.db.profile.colors.name then
                name = color.hex .. name .. "|r"
            end

            if C.db.profile.colors.border then
                toast.Border:SetVertexColor(color.r, color.g, color.b)
            end

            if C.db.profile.colors.icon_border then
                toast.IconBorder:SetVertexColor(color.r, color.g, color.b)
            end

            if C.db.profile.types.loot_items.ilvl then
                local iLevel = E:GetItemLevel(originalLink)

                if iLevel > 0 then
                    name = "[" .. color.hex .. iLevel .. "|r] " .. name
                end
            end

            if quality == 5 then
                title = L["ITEM_LEGENDARY"]
                soundFile = "Interface\\AddOns\\wow_tools\\ls_toasts\\assets\\ui-legendary-loot-toast.OGG"

                toast:SetBackground("legendary")

                if not toast.Dragon.isHidden then
                    toast.Dragon:Show()
                end
            end

            if not toast.IconHL.isHidden then
                toast.IconHL:SetShown(isQuestItem)
            end

            toast.Title:SetText(title)
            toast.Text:SetText(name)
            toast.Icon:SetTexture(icon)
            toast.IconBorder:Show()
            toast.IconText1:SetAnimatedValue(quantity, true)

            toast._data.count = quantity
            toast._data.event = event
            toast._data.item_id = itemID
            toast._data.link = sanitizedLink
            toast._data.sound_file = C.db.profile.types.loot_items.sfx and soundFile
            toast._data.tooltip_link = originalLink

            toast:HookScript("OnClick", Toast_OnClick)
            toast:HookScript("OnEnter", Toast_OnEnter)
            toast:Spawn(C.db.profile.types.loot_items.anchor, C.db.profile.types.loot_items.dnd)
        end
    else
        if isQueued then
            toast._data.count = toast._data.count + quantity
            toast.IconText1:SetAnimatedValue(toast._data.count, true)
        else
            toast._data.count = toast._data.count + quantity
            toast.IconText1:SetAnimatedValue(toast._data.count)

            toast.IconText2:SetText("+" .. quantity)
            toast.IconText2.Blink:Stop()
            toast.IconText2.Blink:Play()

            toast.AnimOut:Stop()
            toast.AnimOut:Play()
        end
    end
end

-- Coalesce bag events into one next-frame snapshot. Read all bags together
-- so an internal move cannot combine a fresh destination with a cached source.
local bagSnapshot = {}
local scanScheduled, suppressBagToasts = false, false
local activationVersion = 0
local bagToastEnabled = false
local recentToasts = {}

local BAG_SETTLE_TIME = 1.5
local LOOT_MATCH_TIME = 1

local function scanBags()
    local totals = {}

    for bag = 0, NUM_BAG_SLOTS do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
        if not ok or not E:IsReadable(numSlots) or type(numSlots) ~= "number" or numSlots < 0 then
            return
        end
        for slot = 1, numSlots do
            local readable, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if not readable or not E:IsReadable(info) then
                return
            end
            if info then
                if
                    type(info) ~= "table"
                    or not E:IsReadable(info.itemID)
                    or not E:IsReadable(info.stackCount)
                    or type(info.itemID) ~= "number"
                    or (info.stackCount ~= nil and type(info.stackCount) ~= "number")
                then
                    return
                end
                local id = info.itemID
                totals[id] = (totals[id] or 0) + (info.stackCount or 1)
            end
        end
    end

    return totals
end

local function isNonLootUIOpen()
    local frames =
        { "MerchantFrame", "MailFrame", "BankFrame", "TradeFrame", "AuctionHouseFrame", "GuildBankFrame" }

    for i = 1, #frames do
        local f = _G[frames[i]]

        if f and f:IsShown() then
            return true
        end
    end

    return false
end

-- Match quantities from opposite sources. Repeated receipts from the same
-- source still contribute their full count, including rapid stack gains.
local function showLoot(source, link, quantity)
    if not E:IsReadable(link) or type(link) ~= "string" or not E:IsReadable(quantity) then
        return
    end
    local itemID = tonumber(link:match("item:(%d+)"))
    quantity = tonumber(quantity) or 0
    if not itemID or quantity <= 0 then
        return
    end

    local now = GetTime()
    local recent = recentToasts[itemID]
    if not recent or now - recent.time > LOOT_MATCH_TIME then
        recent = { chat = 0, bag = 0 }
        recentToasts[itemID] = recent
    end
    local other = source == "chat" and "bag" or "chat"
    local matched = math.min(quantity, recent[other])
    recent[other] = recent[other] - matched
    quantity = quantity - matched
    recent[source] = recent[source] + quantity
    recent.time = now

    if quantity > 0 then
        Toast_SetUp("LOOT_ITEMS", link, quantity)
    end
end

local function updateBags()
    scanScheduled = false
    local suppressed = suppressBagToasts or isNonLootUIOpen()
    suppressBagToasts = false
    local current = scanBags()
    if not current then
        bagSnapshot = nil
        recentToasts = {}
        return
    end
    local now = GetTime()
    for id, recent in next, recentToasts do
        if now - recent.time > LOOT_MATCH_TIME then
            recentToasts[id] = nil
        end
    end

    if not bagToastEnabled or suppressed or not bagSnapshot then
        if not bagSnapshot then
            recentToasts = {}
        end
        bagSnapshot = current
        return
    end

    for id, count in next, current do
        local gained = count - (bagSnapshot[id] or 0)
        if gained > 0 then
            local _, link = C_Item.GetItemInfo(id)
            if link then
                showLoot("bag", link, gained)
            end
        end
    end

    bagSnapshot = current
end

local function scheduleBagScan()
    suppressBagToasts = suppressBagToasts or isNonLootUIOpen()
    if scanScheduled then
        return
    end
    scanScheduled = true
    local version = activationVersion
    C_Timer.After(0, function()
        if version == activationVersion then
            updateBags()
        end
    end)
end

local function BAG_UPDATE(bag)
    if E:IsReadable(bag) and type(bag) == "number" and bag >= 0 and bag <= NUM_BAG_SLOTS then
        scheduleBagScan()
    end
end

local function CHAT_MSG_LOOT(message, _, _, _, name, _, _, _, _, _, _, guid)
    if
        not E:IsReadable(message)
        or type(message) ~= "string"
        or not E:IsReadable(name)
        or not E:IsReadable(guid)
    then
        return
    end
    -- Only toast the player's own loot.
    -- On some clients (e.g. 16001/Midnight) the guid/name args may be nil or
    -- formatted with a realm suffix, so only bail out when they are present
    -- AND clearly belong to someone else. Otherwise a self-loot where the
    -- client didn't populate one of the args would be wrongly filtered out.
    if
        (guid and E:IsReadable(PLAYER_GUID) and PLAYER_GUID and guid ~= PLAYER_GUID)
        or (
            type(name) == "string"
            and E:IsReadable(PLAYER_NAME)
            and PLAYER_NAME
            and Ambiguate(name, "none") ~= Ambiguate(PLAYER_NAME, "none")
        )
    then
        return
    end

    local link, quantity = message:match(LOOT_ITEM_MULTIPLE_PATTERN)
    if not link then
        link, quantity = message:match(LOOT_ITEM_PUSHED_MULTIPLE_PATTERN)
        if not link then
            link, quantity = message:match(LOOT_ITEM_CREATED_MULTIPLE_PATTERN)
            if not link then
                quantity, link = 1, message:match(LOOT_ITEM_PATTERN)
                if not link then
                    quantity, link = 1, message:match(LOOT_ITEM_PUSHED_PATTERN)
                    if not link then
                        quantity, link = 1, message:match(LOOT_ITEM_CREATED_PATTERN)
                        if not link then
                            -- Fallback: extract the item link directly so loot
                            -- detection no longer depends on the LOOT_ITEM_*
                            -- global string format/availability on this client.
                            quantity, link = 1, message:match("|Hitem:.-|h%[.-%]|h")
                        end
                    end
                end
            end
        end
    end

    if not link then
        return
    end

    showLoot("chat", link, quantity)
end

local newID
local pendingItemIDs = {}
local handleItemInfo, updateFilterOptions

local function removeFilter(info)
    C.db.profile.types.loot_items.filters[tonumber(info[#info - 1])] = nil

    updateFilterOptions()
end

function handleItemInfo(id, isOk)
    if isOk then
        pendingItemIDs[id] = nil
    end

    if not next(pendingItemIDs) then
        updateFilterOptions()
    end
end

function updateFilterOptions()
    if not C.db.profile.types.loot_items.enabled then
        return
    end

    local options = t_wipe(C.options.args.types.args.loot_items.plugins.filters)
    local nameToIndex = {}
    local name, quaility, icon, color, _

    for id in next, C.db.profile.types.loot_items.filters do
        if not C_Item.GetItemInfoInstant(id) then
            -- remove invalid IDs, some people do stuff...
            C.db.profile.types.loot_items.filters[id] = nil
        else
            name = C_Item.GetItemInfo(id)
            if name then
                t_insert(nameToIndex, name)
            else
                pendingItemIDs[id] = true
            end
        end
    end

    t_sort(nameToIndex)

    for i = 1, #nameToIndex do
        nameToIndex[nameToIndex[i]] = i
    end

    for id in next, C.db.profile.types.loot_items.filters do
        if not pendingItemIDs[id] then
            name, _, quaility, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
            color = ITEM_QUALITY_COLORS[quaility] or ITEM_QUALITY_COLORS[1]

            options[tostring(id)] = {
                order = nameToIndex[name] + 20,
                type = "group",
                name = ("|T%s:0:0:0:0:64:64:4:60:4:60|t %s%s|r"):format(icon, color.hex, name),
                args = {
                    delete = {
                        type = "execute",
                        order = 1,
                        name = L["DELETE"],
                        func = removeFilter,
                    },
                },
            }
        end
    end

    if next(pendingItemIDs) then
        E:RegisterEvent("GET_ITEM_INFO_RECEIVED", handleItemInfo)
    else
        E:UnregisterEvent("GET_ITEM_INFO_RECEIVED", handleItemInfo)
    end
end

local function Enable()
    updatePatterns()

    if C.db.profile.types.loot_items.enabled then
        local guidOK, guid = pcall(UnitGUID, "player")
        local nameOK, name = pcall(UnitName, "player")
        PLAYER_GUID, PLAYER_NAME = nil, nil
        if guidOK and E:IsReadable(guid) then
            PLAYER_GUID = guid
        end
        if nameOK and E:IsReadable(name) then
            PLAYER_NAME = name
        end
        activationVersion = activationVersion + 1
        local version = activationVersion
        recentToasts = {}
        scanScheduled, suppressBagToasts = false, false
        E:RegisterEvent("CHAT_MSG_LOOT", CHAT_MSG_LOOT)
        E:RegisterEvent("PLAYER_ENTERING_WORLD", delayedUpdatePatterns)
        E:RegisterEvent("BAG_UPDATE", BAG_UPDATE)
        E:RegisterEvent("BAG_UPDATE_DELAYED", scheduleBagScan)

        bagSnapshot = scanBags()
        -- Stay silent until bags have had time to settle, then flip on toasting.
        bagToastEnabled = false
        C_Timer.After(BAG_SETTLE_TIME, function()
            if version == activationVersion then
                bagSnapshot = scanBags()
                bagToastEnabled = true
            end
        end)

        updateFilterOptions()
    end
end

local function Disable()
    activationVersion = activationVersion + 1
    bagToastEnabled = false
    bagSnapshot, recentToasts = {}, {}
    scanScheduled, suppressBagToasts = false, false
    E:UnregisterEvent("CHAT_MSG_LOOT", CHAT_MSG_LOOT)
    E:UnregisterEvent("PLAYER_ENTERING_WORLD", delayedUpdatePatterns)
    E:UnregisterEvent("BAG_UPDATE", BAG_UPDATE)
    E:UnregisterEvent("BAG_UPDATE_DELAYED", scheduleBagScan)
    E:UnregisterEvent("GET_ITEM_INFO_RECEIVED", handleItemInfo)
    pendingItemIDs = {}
end

local function Test()
    -- common, Hearthstone
    local _, link = C_Item.GetItemInfo(6948)
    if link then
        Toast_SetUp("COMMON_LOOT_TEST", link, 1)
    end

    -- common, pet, Tiny Crimson Whelpling
    _, link = C_Item.GetItemInfo(8499)
    if link then
        Toast_SetUp("COMMON_LOOT_TEST", link, 1)
    end

    -- uncommon, Chromatic Sword
    _, link = C_Item.GetItemInfo(1604)
    if link then
        Toast_SetUp("COMMON_LOOT_TEST", link, 1)
    end

    -- rare, Arcanite Reaper
    _, link = C_Item.GetItemInfo(12784)
    if link then
        Toast_SetUp("COMMON_LOOT_TEST", link, 1)
    end

    -- epic, Corrupted Ashbringer
    _, link = C_Item.GetItemInfo(22691)
    if link then
        Toast_SetUp("COMMON_LOOT_TEST", link, 1)
    end

    -- legendary, Atiesh, Greatstaff of the Guardian
    _, link = C_Item.GetItemInfo(22589)
    if link then
        Toast_SetUp("COMMON_LOOT_TEST", link, 1)
    end
end

E:RegisterOptions("loot_items", {
    enabled = true,
    anchor = 1,
    dnd = false,
    sfx = true,
    ilvl = true,
    material = false,
    pet = false,
    quest = false,
    threshold = 1,
    filters = {},
}, {
    name = L["TYPE_LOOT_ITEMS"],
    get = function(info)
        return C.db.profile.types.loot_items[info[#info]]
    end,
    set = function(info, value)
        C.db.profile.types.loot_items[info[#info]] = value
    end,
    args = {
        enabled = {
            order = 1,
            type = "toggle",
            name = L["ENABLE"],
            set = function(_, value)
                C.db.profile.types.loot_items.enabled = value

                if value then
                    Enable()
                else
                    Disable()
                end
            end,
        },
        dnd = {
            order = 2,
            type = "toggle",
            name = L["DND"],
            desc = L["DND_TOOLTIP"],
        },
        sfx = {
            order = 3,
            type = "toggle",
            name = L["SFX"],
        },
        ilvl = {
            order = 4,
            type = "toggle",
            name = L["SHOW_ILVL"],
            desc = L["SHOW_ILVL_DESC"],
        },
        threshold = {
            order = 5,
            type = "select",
            name = L["LOOT_THRESHOLD"],
            values = {
                [0] = ITEM_QUALITY_COLORS[0].hex .. ITEM_QUALITY0_DESC .. "|r",
                [1] = ITEM_QUALITY_COLORS[1].hex .. ITEM_QUALITY1_DESC .. "|r",
                [2] = ITEM_QUALITY_COLORS[2].hex .. ITEM_QUALITY2_DESC .. "|r",
                [3] = ITEM_QUALITY_COLORS[3].hex .. ITEM_QUALITY3_DESC .. "|r",
                [4] = ITEM_QUALITY_COLORS[4].hex .. ITEM_QUALITY4_DESC .. "|r",
            },
        },
        test = {
            type = "execute",
            order = 9,
            width = "full",
            name = L["TEST"],
            func = Test,
        },
        spacer_1 = {
            order = 10,
            type = "description",
            name = " ",
        },
        filters = {
            order = 11,
            type = "group",
            name = L["FILTERS"],
            inline = true,
            args = {
                desc = {
                    order = 1,
                    type = "description",
                    name = L["ITEM_FILTERS_DESC"],
                },
                spacer_1 = {
                    order = 2,
                    type = "description",
                    name = " ",
                },
                quest = {
                    order = 3,
                    type = "toggle",
                    name = L["QUEST_ITEMS"],
                },
                pet = {
                    order = 4,
                    type = "toggle",
                    name = L["PETS"],
                },
                material = {
                    order = 5,
                    type = "toggle",
                    name = L["MATERIALS"],
                },
            },
        },
        new = {
            order = 12,
            type = "group",
            name = L["NEW"],
            args = {
                desc = {
                    order = 1,
                    type = "description",
                    name = L["NEW_ITEM_FILTER_DESC"],
                },
                id = {
                    order = 2,
                    type = "input",
                    name = L["ID"],
                    dialogControl = "LSPreviewBoxItem",
                    validate = function(_, value)
                        value = tonumber(value)
                        if value then
                            return not not C_Item.GetItemInfoInstant(value)
                        else
                            return true
                        end
                    end,
                    set = function(_, value)
                        value = tonumber(value)
                        if value and C_Item.GetItemInfoInstant(value) then
                            newID = value
                        else
                            newID = nil -- jic
                        end
                    end,
                    get = function()
                        return tostring(newID or "")
                    end,
                },
                add = {
                    type = "execute",
                    order = 3,
                    name = L["ADD"],
                    disabled = function()
                        return not newID or C.db.profile.types.loot_items.filters[newID]
                    end,
                    func = function()
                        C.db.profile.types.loot_items.filters[newID] = true
                        newID = nil

                        updateFilterOptions()
                    end,
                },
            },
        },
    },
    plugins = {
        filters = {},
    },
})

E:RegisterSystem("loot_items", Enable, Disable, Test)
