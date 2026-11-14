-- ListInventory: saved data, bag and bank scanning, events, item tooltips and the /li command.
local addonName, ns = ...
local Data = ns.Data

ns.defaults = {
    replaceBags = true, -- open the list with the game's bags
    tooltip = true,     -- add counts from all characters to item tooltips
    hideGrid = true,    -- gamepad mode: fade the game's bag window while the list drives its cursor
    view = "bags",      -- "bags" or "all"
}

ns.debug = false
ns.live = { stacks = {}, empty = {}, free = 0, slots = 0 }
ns.bankOpen = false

local function Print(msg)
    print("|cff33ff99ListInventory|r: " .. msg)
end
ns.Print = Print

local function Debug(msg)
    if ns.debug then Print("|cff999999[debug]|r " .. msg) end
end
ns.Debug = Debug

---------------------------------------------------------------------------------------------
-- Container API: newer clients keep these in C_Container, older ones as globals.
---------------------------------------------------------------------------------------------
local C = C_Container or {}

local function NumSlots(bag)
    local f = C.GetContainerNumSlots or GetContainerNumSlots
    return f and f(bag) or 0
end

-- icon, count, locked, quality, link for one slot, or nil when it is empty.
local function SlotInfo(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if i then return i.iconFileID, i.stackCount, i.isLocked, i.quality, i.hyperlink end
        return nil
    end
    local icon, count, locked, quality, _, _, link = GetContainerItemInfo(bag, slot)
    if icon then return icon, count, locked, quality, link end
    return nil
end

function ns.SlotLink(bag, slot)
    local _, _, _, _, link = SlotInfo(bag, slot)
    return link
end

function ns.PickupSlot(bag, slot)
    local f = C.PickupContainerItem or PickupContainerItem
    f(bag, slot)
end

ns.BACKPACK = BACKPACK_CONTAINER or 0
ns.BANK = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1

local function LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

function ns.IsPlayerBag(bag)
    return type(bag) == "number" and bag >= ns.BACKPACK and bag <= LastBag()
end

-- { bag ID, label } for the bags, in display order.
local function BagList()
    local list = { { ns.BACKPACK, "Backpack" } }
    for i = 1, LastBag() do list[#list + 1] = { ns.BACKPACK + i, "Bag " .. i } end
    return list
end

local function BankList()
    local list = { { ns.BANK, "Bank" } }
    local first = Enum and Enum.BagIndex and Enum.BagIndex.BankBag_1 or (LastBag() + 1)
    for i = 1, NUM_BANKBAGSLOTS or 6 do list[#list + 1] = { first + i - 1, "Bank bag " .. i } end
    return list
end

---------------------------------------------------------------------------------------------
-- Forever's Gamepad UI setting (Options > Gamepad). On, the game's controller cursor runs the
-- bags; the active input still flips between pad and mouse as either is used, which doesn't
-- matter here.
---------------------------------------------------------------------------------------------
function ns.GamepadUI()
    local util = _G.InputUtil
    if util and util.IsGamepadUIEnabled then
        local ok, on = pcall(util.IsGamepadUIEnabled)
        if ok then return on and true or false end
    end
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    local style = getCVar and getCVar("InputDeviceInterfaceStyle")
    local padStyle = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
    if style ~= nil and padStyle ~= nil then return tostring(style) == tostring(padStyle) end
    -- Neither known: the game's own pad bindings tell (only while the pad is the active input).
    return (GetBindingAction("PAD1", true) or ""):find("InputFunctionBindingButton", 1, true) ~= nil
end

---------------------------------------------------------------------------------------------
-- Items: links and icons for things that are not in front of us right now.
---------------------------------------------------------------------------------------------
-- Item info: Forever only has the C_Item versions of most of these.
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function HasName(link)
    return Data.ItemName(link) ~= nil
end
ns.HasName = HasName

-- A link for an item seen before. Links saved before the game had loaded the item have no name
-- ("[]"): ask the game again, and ask it to load the item if it doesn't know it yet (a
-- GET_ITEM_INFO_RECEIVED then redraws the list).
function ns.ItemLink(key)
    local saved = ns.db and ns.db.items[key]
    if HasName(saved) then return saved end
    local id = Data.KeyItemID(key)
    if id and not key:find(":", 1, true) and GetInfo then
        local _, link = GetInfo(id)
        if HasName(link) then
            ns.db.items[key] = link
            return link
        end
    end
    if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return saved
end

function ns.ItemIcon(key)
    local id = Data.KeyItemID(key)
    if not id then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
end

function ns.ItemQuality(link)
    if not link then return nil end
    if C_Item and C_Item.GetItemQualityByID then
        local q = C_Item.GetItemQualityByID(link)
        if q then return q end
    end
    if not GetInfo then return nil end
    local _, _, q = GetInfo(link)
    return q
end

---------------------------------------------------------------------------------------------
-- Saved data
--   ListInventoryDB.groups[groupKey][characterName] = { class, bags = {key=n}, bank = {key=n}, bankSeen, updated }
--   ListInventoryDB.items[key] = item link (so alts' items have a name and quality)
---------------------------------------------------------------------------------------------
local function LoadDB()
    if type(ListInventoryDB) ~= "table" then ListInventoryDB = {} end
    local db = ListInventoryDB
    for k, v in pairs(ns.defaults) do
        if db[k] == nil then db[k] = v end
    end
    -- Positions saved by earlier builds came from the list docked beside the bags: drop them.
    if (db.layout or 0) < 2 then
        db.point = nil
        db.layout = 2
    end
    db.groups = db.groups or {}
    db.items = db.items or {}
    ns.db = db
end

-- Characters on the same realm, ruleset and faction share counts. The ruleset tells normal,
-- hardcore and seasonal characters apart where the client reports them.
local function Ruleset()
    local parts = {}
    local ok, hardcore = pcall(function() return C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() end)
    if ok and hardcore then parts[#parts + 1] = "hardcore" end
    local ok2, season = pcall(function()
        return C_Seasons and C_Seasons.HasActiveSeason and C_Seasons.HasActiveSeason() and C_Seasons.GetActiveSeason()
    end)
    if ok2 and season then parts[#parts + 1] = "season" .. tostring(season) end
    return #parts > 0 and table.concat(parts, "+") or "normal"
end

local function SetupCharacter()
    local realm = GetRealmName()
    ns.groupKey = Data.GroupKey(realm, Ruleset(), UnitFactionGroup("player"))
    ns.charName = UnitName("player")
    ns.db.groups[ns.groupKey] = ns.db.groups[ns.groupKey] or {}
    ns.group = ns.db.groups[ns.groupKey]
    local rec = ns.group[ns.charName] or {}
    rec.class = select(2, UnitClass("player"))
    rec.bags = rec.bags or {}
    rec.bank = rec.bank or {}
    ns.group[ns.charName] = rec
    ns.record = rec
end

---------------------------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------------------------
local function ScanContainers(list, location, stacks, empty)
    local slots, order = 0, 0
    for _, entry in ipairs(list) do
        local bag, label = entry[1], entry[2]
        local n = NumSlots(bag)
        order = order + 1
        for slot = 1, n do
            slots = slots + 1
            local icon, count, locked, quality, link = SlotInfo(bag, slot)
            local where = label .. ", slot " .. slot
            if icon then
                local key = Data.ItemKey(link)
                stacks[#stacks + 1] = {
                    key = key, link = link, icon = icon, count = count or 1, locked = locked,
                    quality = quality, bag = bag, slot = slot, bagOrder = order,
                    location = location, where = where,
                }
                if key and HasName(link) and not HasName(ns.db.items[key]) then ns.db.items[key] = link end
            elseif empty then
                empty[#empty + 1] = { bag = bag, slot = slot, bagOrder = order, location = location, where = where, empty = true, count = 0 }
            end
        end
    end
    return slots
end

function ns:Scan()
    if not self.record then return end
    local stacks, empty = {}, {}
    local bagStacks = {}
    local slots = ScanContainers(BagList(), "bags", bagStacks, empty)
    for _, s in ipairs(bagStacks) do stacks[#stacks + 1] = s end
    self.record.bags = Data.CountStacks(bagStacks)

    if self.bankOpen then
        local bankStacks = {}
        ScanContainers(BankList(), "bank", bankStacks, nil)
        for _, s in ipairs(bankStacks) do stacks[#stacks + 1] = s end
        self.record.bank = Data.CountStacks(bankStacks)
        self.record.bankSeen = time()
    end
    self.record.updated = time()

    self.live = { stacks = stacks, empty = empty, free = #empty, slots = slots }
    Debug("scanned " .. #stacks .. " stacks, " .. #empty .. " free")
end

-- Coalesced rescan: a burst of bag events causes one scan and redraw on the next frame.
local pending = false
function ns:MarkDirty()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        ns:Scan()
        if ns.UI then ns.UI:Refresh() end
    end)
end

---------------------------------------------------------------------------------------------
-- Tooltips: add "how many do I have everywhere" to every item tooltip.
---------------------------------------------------------------------------------------------
local MAX_TOOLTIP_CHARS = 8

local function AddCounts(tooltip, link)
    if not (ns.db and ns.db.tooltip and ns.group and link) then return end
    local key = Data.ItemKey(link)
    if not key then return end
    local list, total = Data.Breakdown(ns.group, ns.charName, key)
    if total == 0 then return end
    tooltip:AddDoubleLine("|cff33ff99Total|r", "|cff33ff99" .. total .. "|r")
    for i, e in ipairs(list) do
        if i > MAX_TOOLTIP_CHARS then
            tooltip:AddLine("  +" .. (#list - MAX_TOOLTIP_CHARS) .. " more", 0.6, 0.6, 0.6)
            break
        end
        local color = RAID_CLASS_COLORS and ns.group[e.name] and RAID_CLASS_COLORS[ns.group[e.name].class]
        local r, g, b = 0.8, 0.8, 0.8
        if color then r, g, b = color.r, color.g, color.b end
        tooltip:AddDoubleLine("  " .. e.name, Data.Describe(e), r, g, b, 1, 1, 1)
    end
    tooltip:Show()
end

-- The game prints "Interface action failed because of an AddOn" at most once a session, and not
-- always with an ADDON_ACTION_BLOCKED event. Note where the call came from (file and function
-- names only) so it can be traced.
local function RecordBlocked(event, addon, func, stack)
    if not ns.db then return end
    ns.db.blocked = ns.db.blocked or {}
    table.insert(ns.db.blocked, 1, {
        event = event, addon = tostring(addon), func = tostring(func),
        time = date and date("%Y-%m-%d %H:%M:%S"), stack = stack,
    })
    while #ns.db.blocked > 10 do table.remove(ns.db.blocked) end
end
ns.RecordBlocked = RecordBlocked

local seenMessage = false
local function MessageShown(how)
    if seenMessage then return end
    seenMessage = true
    local stack = debugstack and debugstack(3, 30, 0) or ""
    RecordBlocked("message", "?", how, stack)
    -- (the first line of the stack: who asked for the message)
    local first = stack:match("([^\n]+)") or "?"
    Print("the game showed \"Interface action failed\", called from: " .. first .. " (full path saved for /li status).")
end

local function WatchBlockedMessage()
    if not hooksecurefunc then return end
    if type(DisplayInterfaceActionBlockedMessage) == "function" then
        hooksecurefunc("DisplayInterfaceActionBlockedMessage", function() MessageShown("DisplayInterfaceActionBlockedMessage") end)
    end
    -- However it is printed: the chat frames, for that exact text.
    local text = INTERFACE_ACTION_BLOCKED
    if type(text) ~= "string" then return end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.AddMessage then
            hooksecurefunc(cf, "AddMessage", function(_, msg)
                if msg == text then MessageShown("ChatFrame" .. i .. ":AddMessage") end
            end)
        end
    end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            local link = data and data.hyperlink
            if not link and tooltip.GetItem then link = select(2, tooltip:GetItem()) end
            AddCounts(tooltip, link)
            if ns.Gamepad then ns.Gamepad:OnItemTooltip(tooltip) end
        end)
    else
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            tooltip:HookScript("OnTooltipSetItem", function(self)
                AddCounts(self, select(2, self:GetItem()))
                if ns.Gamepad then ns.Gamepad:OnItemTooltip(self) end
            end)
        end
    end
end

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------
local EVENTS = {
    "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
    "ITEM_DATA_LOAD_RESULT",
    "PLAYER_MONEY",
    "CURSOR_CHANGED",
    "GAME_PAD_ACTIVE_CHANGED",
    "GAME_PAD_CONNECTED",
    "GAME_PAD_DISCONNECTED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
-- The game blocking something because of this addon: say what, and keep it for /li status.
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then LoadDB() end
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- Every one is kept, whichever addon the game blames (arg1), with the blocked function.
        if not ns.db then return end
        local func = ...
        RecordBlocked(event, arg1, func, debugstack and debugstack(2, 20, 0))
        Print(("the game blocked |cffff8080%s|r, blaming %s (%s)."):format(tostring(func), tostring(arg1), event))
        return
    end
    if event == "PLAYER_LOGIN" then
        SetupCharacter()
        for _, e in ipairs(EVENTS) do
            -- pcall: an event missing from this client must not break loading.
            if not pcall(self.RegisterEvent, self, e) then Debug("event not available: " .. e) end
        end
        ns:Scan()
        HookTooltips()
        WatchBlockedMessage()
        if ns.UI then ns.UI:Init() end
        return
    end

    if event == "BANKFRAME_OPENED" then
        ns.bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        ns.bankOpen = false
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if ns.UI then ns.UI:OnCombat(event == "PLAYER_REGEN_DISABLED") end
        return
    elseif event == "CURSOR_CHANGED" or event == "PLAYER_MONEY" or event:find("^GAME_PAD") then
        if ns.UI then ns.UI:Render() end
        return
    end
    Debug("event " .. event)
    ns:MarkDirty()
end)

---------------------------------------------------------------------------------------------
-- /li
---------------------------------------------------------------------------------------------
local function Ago(t)
    if not t then return "never" end
    local d = time() - t
    if d < 120 then return "just now" end
    if d < 7200 then return math.floor(d / 60) .. " min ago" end
    if d < 172800 then return math.floor(d / 3600) .. " h ago" end
    return math.floor(d / 86400) .. " days ago"
end

-- The group key uses "|" separators, which WoW reads as escape codes in printed text.
function ns.GroupLabel()
    return (tostring(ns.groupKey):gsub("|", " / "))
end

local function ListCharacters()
    Print("characters counted together (" .. ns.GroupLabel() .. "):")
    local names = {}
    for name in pairs(ns.group or {}) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local rec = ns.group[name]
        print(("  %s - updated %s, bank seen %s"):format(name, Ago(rec.updated), Ago(rec.bankSeen)))
    end
end

SLASH_LISTINVENTORY1 = "/li"
SLASH_LISTINVENTORY2 = "/listinv"
SLASH_LISTINVENTORY3 = "/listinventory"
SlashCmdList["LISTINVENTORY"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    if not ns.db or not ns.record then return end

    if cmd == "" then
        if ns.UI then ns.UI:Toggle() end
    elseif cmd == "default" then
        ns.db.replaceBags = not ns.db.replaceBags
        Print(ns.db.replaceBags and "the list now opens with your bags." or "the list no longer opens with your bags. /li still opens it.")
    elseif cmd == "tooltip" then
        ns.db.tooltip = not ns.db.tooltip
        Print("tooltip counts " .. (ns.db.tooltip and "on" or "off"))
    elseif cmd == "chars" then
        ListCharacters()
    elseif cmd == "forget" and rest ~= "" then
        local name = rest:sub(1, 1):upper() .. rest:sub(2):lower()
        if name == ns.charName then
            Print("you can't forget the character you're logged in on.")
        elseif ns.group[name] then
            ns.group[name] = nil
            Print("forgot " .. name .. ".")
            ns:MarkDirty()
        else
            Print("no character called " .. name .. " in this group. /li chars lists them.")
        end
    elseif cmd == "status" then
        Print("group " .. ns.GroupLabel() .. ", " .. #ns.live.stacks .. " stacks, " .. ns.live.free .. "/" .. ns.live.slots .. " slots free")
        Print("opens with bags: " .. tostring(ns.db.replaceBags) .. ", tooltip counts: " .. tostring(ns.db.tooltip))
        Print("this character's bank last seen: " .. Ago(ns.record.bankSeen))
        for i, b in ipairs(ns.db.blocked or {}) do
            if i > 3 then break end
            Print(("blocked: %s, blaming %s, at %s (%s)"):format(b.func, tostring(b.addon), tostring(b.time), b.event))
            if b.event == "message" and b.stack then
                -- The game's own lines near the top, and every line from this addon.
                local n = 0
                for line in b.stack:gmatch("[^\n]+") do
                    n = n + 1
                    if n <= 6 or line:find("ListInventory", 1, true) then print("    " .. line) end
                end
            end
        end
        if ns.UI then ns.UI:Diagnose() end
    elseif cmd == "grid" then
        ns.db.hideGrid = not ns.db.hideGrid
        Print("gamepad mode: the game's bag window is " .. (ns.db.hideGrid and "hidden" or "shown") .. " while the list is open.")
        if ns.UI then ns.UI:Refresh() end
    elseif cmd == "probe" then
        if ns.UI then ns.UI:Probe() end
    elseif cmd == "debug" then
        ns.debug = not ns.debug
        Print("debug " .. (ns.debug and "on" or "off"))
    else
        Print("commands:")
        print("  /li - open or close the list")
        print("  /li default - open the list with your bags, or not")
        print("  /li tooltip - item tooltip counts on/off")
        print("  /li chars - characters counted together")
        print("  /li forget <name> - stop counting a deleted or transferred character")
        print("  /li status - diagnostics")
        print("  /li grid - gamepad mode: show or hide the game's bag window behind the list")
        print("  /li probe - save controller diagnostics")
    end
end
