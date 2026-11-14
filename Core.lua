-- ListInventory: lists the contents of your bags.
local ADDON_NAME, ns = ...

-- Container API compatibility: newer clients moved these into C_Container.
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

local function GetItemCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 0
    end
    local _, count = GetContainerItemInfo(bag, slot)
    return count or 0
end

local NUM_BAGS = NUM_BAG_SLOTS or 4 -- backpack is bag 0, bags 1..NUM_BAGS

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ListInventory|r: " .. msg)
end

-- Returns a sorted list of { link = ..., count = ... }, stacks merged by item link.
local function CollectInventory()
    local totals, order = {}, {}
    for bag = 0, NUM_BAGS do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local link = GetItemLink(bag, slot)
            if link then
                if not totals[link] then
                    totals[link] = 0
                    order[#order + 1] = link
                end
                totals[link] = totals[link] + GetItemCount(bag, slot)
            end
        end
    end
    local items = {}
    for _, link in ipairs(order) do
        items[#items + 1] = { link = link, count = totals[link] }
    end
    table.sort(items, function(a, b)
        local na = a.link:match("%[(.-)%]") or a.link
        local nb = b.link:match("%[(.-)%]") or b.link
        return na < nb
    end)
    return items
end

local function ListInventory(filter)
    filter = filter and filter:lower() or ""
    local items = CollectInventory()
    local shown = 0
    for _, item in ipairs(items) do
        local name = item.link:match("%[(.-)%]") or item.link
        if filter == "" or name:lower():find(filter, 1, true) then
            Print(item.link .. " x" .. item.count)
            shown = shown + 1
        end
    end
    Print(shown .. " item type(s) listed.")
end
ns.CollectInventory = CollectInventory

SLASH_LISTINVENTORY1 = "/listinv"
SLASH_LISTINVENTORY2 = "/listinventory"
SlashCmdList["LISTINVENTORY"] = function(msg)
    ListInventory(strtrim(msg or ""))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if name == ADDON_NAME then
        ListInventoryDB = ListInventoryDB or {}
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
