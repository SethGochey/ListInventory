-- ListInventory: the list window that replaces the bags, with gamepad and keyboard navigation.
--
-- How item actions stay "real": each row that stands for one stack holds a stock
-- ContainerFrameItemButton for that bag and slot, so mouse clicks do exactly what they do in
-- the default bags (use, equip, sell, bank, trade, mail, split, link...).
--
-- The controller, two ways:
-- * Forever's gamepad mode (its own override bindings on every pad button, to
--   InputFunctionBindingButton_*): the game's cursor (SmartNavigation) is left in charge. The
--   list follows the cursor when it is on a row, and scrolls when it is pushed past the end.
-- * Otherwise: override bindings of ours click the selected row's item button (secure) or our
--   navigation buttons. Those can't change in combat, so in combat the window reads the pad
--   directly instead (using an item from the pad then waits for the end of combat).
--
-- The list opens and closes with the game's bag windows (watched, never replaced), so every way
-- the game opens the bags opens the list too.
local _, ns = ...
local Data = ns.Data

local UI = {}
ns.UI = UI

local VISIBLE = 11
local ROW_H = 34
local WIDTH = 420
local ITEM_BUTTON_SIZE = 37
local HOLD_DELAY, HOLD_RATE = 0.35, 0.06
local EMPTY_KEY = "empty"

-- Gamepad buttons bound while the window has focus (out of combat). Keyboard keys could be
-- added to each list, but they would block chat and movement keys while the bags are open.
UI.KEYS = {
    up = { "PADDUP" },
    down = { "PADDDOWN" },
    pageUp = { "PADLTRIGGER" },
    pageDown = { "PADRTRIGGER" },
    accept = { "PAD1" }, -- as the game's bags: A picks up / places
    back = { "PAD2" },
    use = { "PAD3" },    -- X uses / equips
    more = { "PAD4" },   -- Y opens the More menu (destroy, link)
}
local REPEATS = { up = true, down = true, pageUp = true, pageDown = true }

-- Gamepad button -> action, for reading the gamepad directly during combat.
local PAD_ACTIONS = {}
for action, keys in pairs(UI.KEYS) do
    for _, key in ipairs(keys) do
        if key:find("^PAD") then PAD_ACTIONS[key] = action end
    end
end

-- capture = true: the window reads gamepad presses itself and keeps them from the game (combat).
-- capture = false: presses go on to the override bindings. Clients without
-- SetPropagateGamePadButton only get gamepad input on the window while capturing.
local function SetPadCapture(frame, capture)
    if not frame.EnableGamePadButton then return end
    if frame.SetPropagateGamePadButton then
        frame:EnableGamePadButton(true)
        frame:SetPropagateGamePadButton(not capture)
    else
        frame:EnableGamePadButton(capture)
    end
end

local GLYPH_FALLBACK = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB" }
local function Glyph(key)
    local text = GetBindingText and GetBindingText(key)
    if text and (text:find("|A") or text:find("|T")) then return text end
    return "|cffffd100" .. (GLYPH_FALLBACK[key] or text or key) .. "|r"
end

UI.mode = "list"     -- "list", "stacks" or "confirm"
UI.entries = {}
UI.sel, UI.offset = 1, 0
UI.focused = false

---------------------------------------------------------------------------------------------
-- Entries: what each visible row shows
---------------------------------------------------------------------------------------------
local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function RowEntry(row)
    local first = row.stacks[1]
    local e = {
        kind = "row", key = row.key, row = row, name = row.name, link = row.link,
        quality = (first and first.quality) or ns.ItemQuality(row.link),
        icon = (first and first.icon) or ns.ItemIcon(row.key),
        stacks = row.stacks,
        a = row.bags > 0 and tostring(row.bags) or (row.bank > 0 and ("|cff9999ff" .. row.bank .. "b|r") or "|cff6666660|r"),
        b = tostring(row.total),
    }
    if #row.stacks == 1 then e.stack = first end
    return e
end

local function StackEntry(s, row)
    return {
        kind = "stack", key = s.key, row = row, stack = s, name = s.where, link = s.link,
        quality = s.quality, icon = s.icon,
        a = tostring(s.count), b = "",
        nameColor = s.location == "bank" and { 0.6, 0.6, 1 } or { 0.9, 0.9, 0.9 },
    }
end

-- The line between the bags and "Elsewhere": drawn, never selected.
local function DividerEntry(count)
    return { kind = "divider", key = "divider", name = "Elsewhere: your bank and other characters  |cff888888(" .. count .. ")|r",
        nameColor = { 1, 0.82, 0 }, a = "", b = "" }
end

local function EmptyEntry(s)
    return { kind = "stack", key = EMPTY_KEY, stack = s, name = s.where, a = "", b = "", nameColor = { 0.6, 0.6, 0.6 } }
end

local MORE_OPTIONS = {
    { action = "destroy", name = "Destroy", nameColor = { 1, 0.35, 0.35 } },
    { action = "link", name = "Link in chat" },
    { action = "cancel", name = "Back" },
}

function UI:BuildEntries()
    local live = ns.live
    if self.mode == "more" or self.mode == "confirm" then
        local s = self.moreStack
        if s and ns.SlotLink(s.bag, s.slot) == s.link then
            local entries = {}
            for _, o in ipairs(MORE_OPTIONS) do
                entries[#entries + 1] = { kind = "option", key = "option:" .. o.action, action = o.action,
                    name = o.name, nameColor = o.nameColor or { 0.9, 0.9, 0.9 }, a = "", b = "" }
            end
            self.drillTitle = (s.link or "?") .. (s.count and s.count > 1 and ("  |cffaaaaaax" .. s.count .. "|r") or "")
            self.entries = entries
            return
        end
        -- The stack is gone: back to where the menu was opened from.
        self.mode, self.moreStack, self.confirm = self.moreReturn or "list", nil, nil
    end
    local rows = Data.BuildRows({
        chars = ns.group, current = ns.charName, stacks = live.stacks,
        itemLink = ns.ItemLink,
    })
    local entries = {}

    if self.mode ~= "list" then
        if self.drillKey == EMPTY_KEY then
            for _, s in ipairs(live.empty) do entries[#entries + 1] = EmptyEntry(s) end
            self.drillTitle = "Empty slots"
        else
            for _, row in ipairs(rows) do
                if row.key == self.drillKey then
                    for _, s in ipairs(row.stacks) do entries[#entries + 1] = StackEntry(s, row) end
                    self.drillTitle = row.name .. "  |cffaaaaaa" .. row.bags .. " here, " .. row.total .. " total|r"
                    self.drillLink = row.link
                end
            end
        end
        if #entries > 0 then
            self.entries = entries
            return
        end
        -- The stacks are gone (used up, sold, moved): back to the list.
        self:LeaveStacks()
    end

    -- In your bags (and the bank while it's open), then Empty slots, then everything elsewhere.
    local elsewhere = {}
    for _, row in ipairs(rows) do
        if row.section == "here" then
            entries[#entries + 1] = RowEntry(row)
        else
            elsewhere[#elsewhere + 1] = RowEntry(row)
        end
    end
    if #live.empty > 0 then
        local e = {
            kind = "empty", key = EMPTY_KEY, name = "Empty slots", a = tostring(#live.empty), b = "",
            stacks = live.empty, nameColor = { 0.6, 0.6, 0.6 },
        }
        if #live.empty == 1 then e.stack = live.empty[1] end
        entries[#entries + 1] = e
    end
    self.firstElsewhere = nil
    if #elsewhere > 0 then
        entries[#entries + 1] = DividerEntry(#elsewhere)
        self.firstElsewhere = #entries + 1
        for _, e in ipairs(elsewhere) do entries[#entries + 1] = e end
    end
    self.entries = entries
end

function UI:Selected()
    return self.entries[self.sel]
end

-- Remember the selection by identity so a rebuild doesn't move it.
local function Identity(e)
    if not e then return nil end
    if e.kind == "stack" and e.stack then return e.stack.bag .. ":" .. e.stack.slot end
    return e.key
end

---------------------------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------------------------
local function MakeRow(parent, i)
    local row = CreateFrame("Button", "ListInventoryRow" .. i, parent)
    row:SetSize(WIDTH - 32, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.index = i

    row.selTex = row:CreateTexture(nil, "BACKGROUND")
    row.selTex:SetAllPoints()
    row.selTex:SetColorTexture(1, 0.82, 0, 0.18)
    row.selEdge = row:CreateTexture(nil, "ARTWORK")
    row.selEdge:SetPoint("TOPLEFT")
    row.selEdge:SetPoint("BOTTOMLEFT")
    row.selEdge:SetWidth(3)
    row.selEdge:SetColorTexture(1, 0.82, 0, 0.9)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 6, ROW_H - 6)
    row.icon:SetPoint("LEFT", 6, 0)

    -- The holder's ID is the bag, the item button's ID is the slot: that is all the stock item
    -- button needs to behave like a slot in the default bags.
    local holder = CreateFrame("Frame", nil, row)
    holder:SetSize(ROW_H - 6, ROW_H - 6)
    holder:SetPoint("LEFT", 6, 0)
    holder.GetBagID = function(self) return self:GetID() end
    holder.IsCombinedBagContainer = function() return false end
    row.holder = holder

    local ok, button = pcall(CreateFrame, "ItemButton", "ListInventoryRow" .. i .. "Item", holder, "ContainerFrameItemButtonTemplate")
    if not ok then
        button = CreateFrame("Button", "ListInventoryRow" .. i .. "Item", holder, "ContainerFrameItemButtonTemplate")
    end
    button:SetScale((ROW_H - 6) / ITEM_BUTTON_SIZE)
    button:ClearAllPoints()
    button:SetPoint("CENTER")
    button:HookScript("OnEnter", function() UI:Select(row.index + UI.offset, true) end)
    row.item = button

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -112, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.colB = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.colB:SetPoint("RIGHT", -22, 0)
    row.colB:SetWidth(44)
    row.colB:SetJustifyH("RIGHT")

    row.colA = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.colA:SetPoint("RIGHT", row.colB, "LEFT", -6, 0)
    row.colA:SetWidth(44)
    row.colA:SetJustifyH("RIGHT")

    row.more = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.more:SetPoint("RIGHT", -6, 0)
    row.more:SetText(">")

    row:SetScript("OnEnter", function() UI:Select(row.index + UI.offset, true) end)
    row:SetScript("OnClick", function(_, mouse)
        UI:Select(row.index + UI.offset)
        if mouse == "RightButton" then
            if UI.mode ~= "list" then UI:Do("back") end
        else
            local e = UI:Selected()
            if e and not e.stack then UI:Do("accept") end
        end
    end)
    return row
end

local function MakeNavButton(action)
    local b = CreateFrame("Button", "ListInventoryNav_" .. action, UIParent)
    b:Hide()
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(_, _, down)
        if down then
            UI:Do(action)
            if REPEATS[action] then UI:StartRepeat(action) end
        else
            UI:StopRepeat()
        end
    end)
    return b
end

function UI:Init()
    if self.frame then return end

    local ok, frame = pcall(CreateFrame, "Frame", "ListInventoryFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        frame = CreateFrame("Frame", "ListInventoryFrame", UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    frame:SetSize(WIDTH, 122 + VISIBLE * ROW_H)
    -- Above the game's bag window it covers (and the blocker over that window).
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    -- Dragged only when opened on its own (/li): with the bags it sits over the bag window.
    frame:SetScript("OnDragStart", function(f)
        if UI.openedBy ~= "bags" then f:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(f)
        if UI.openedBy == "bags" then return end
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        ns.db.point = { point, relPoint, x, y }
    end)
    frame:Hide()
    -- Not in UISpecialFrames: in Forever, the pad's B runs CloseSpecialWindows, which would run
    -- tainted with an addon frame in that list. Escape is an override binding instead (below).
    self.frame = frame
    self:RestorePosition()

    if type(frame.CloseButton) == "table" then frame.CloseButton:SetScript("OnClick", function() UI:Do("close") end) end
    frame.title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not frame.TitleText then frame.title:SetPoint("TOP", 0, -14) end

    self.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.heading:SetPoint("TOPLEFT", 18, -32)
    self.heading:SetPoint("RIGHT", -18, 0)
    self.heading:SetJustifyH("LEFT")
    self.heading:SetWordWrap(false)

    self.colHeadB = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.colHeadB:SetPoint("TOPRIGHT", -38, -56)
    self.colHeadB:SetWidth(44)
    self.colHeadB:SetJustifyH("RIGHT")
    self.colHeadA = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.colHeadA:SetPoint("RIGHT", self.colHeadB, "LEFT", -6, 0)
    self.colHeadA:SetWidth(44)
    self.colHeadA:SetJustifyH("RIGHT")

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 14, -70)
    list:SetSize(WIDTH - 32, VISIBLE * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(-delta) end)
    self.list = list

    self.rows = {}
    for i = 1, VISIBLE do self.rows[i] = MakeRow(list, i) end

    self.scrollText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.scrollText:SetPoint("TOPLEFT", 18, -56)

    self.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.money:SetPoint("BOTTOMLEFT", 18, 30)
    self.free = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.free:SetPoint("BOTTOMRIGHT", -18, 30)

    self.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.hint:SetPoint("BOTTOMLEFT", 18, 12)
    self.hint:SetPoint("BOTTOMRIGHT", -18, 12)
    self.hint:SetJustifyH("LEFT")
    self.hint:SetWordWrap(false)

    self.nav = {}
    for action in pairs(self.KEYS) do self.nav[action] = MakeNavButton(action) end
    self.nav.close = MakeNavButton("close")

    -- During combat the gamepad is read directly (see the top of this file). Out of combat the
    -- presses propagate on to the override bindings.
    if frame.EnableGamePadButton then
        frame:SetScript("OnGamePadButtonDown", function(_, key)
            if not InCombatLockdown() or not UI.focused or UI.gamepadMode then return end
            local action = PAD_ACTIONS[key]
            if not action then return end
            UI:Do(action, true)
            if REPEATS[action] then UI:StartRepeat(action, true) end
        end)
        frame:SetScript("OnGamePadButtonUp", function() UI:StopRepeat() end)
        -- (setting a gamepad script switches the frame's gamepad input on by itself: off again,
        -- or the window would swallow every press while it is shown)
        SetPadCapture(frame, false)
    end
    frame:SetScript("OnUpdate", function() UI:FollowCursor() end)

    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN or 862)
        ns:Scan()
        UI:Refresh()
    end)
    frame:SetScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE or 863)
        UI:StopRepeat()
        UI:ClearBindings()
        UI.mode, UI.confirm, UI.focused, UI.openedBy = "list", nil, false, nil
        UI:StopFollowing()
        if GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == UI.list then GameTooltip:Hide() end
    end)

    self:WatchBagFrames()
end

function UI:RestorePosition()
    local p = ns.db.point
    self.frame:ClearAllPoints()
    if p then
        self.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        self.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 90)
    end
end

---------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------
function UI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    local keep = Identity(self:Selected())
    self:BuildEntries()
    if keep then
        for i, e in ipairs(self.entries) do
            if Identity(e) == keep then self.sel = i break end
        end
    end
    self:Render()
    -- (Render worked out whether gamepad mode is on)
    if ns.Gamepad then ns.Gamepad:Apply() end
end

local function ShowItemButton(row, s)
    local b = row.item
    row.holder:SetID(s.bag)
    b:SetID(s.slot)
    if b.SetBagID then pcall(b.SetBagID, b, s.bag) end
    if SetItemButtonTexture then pcall(SetItemButtonTexture, b, s.icon) end
    if SetItemButtonCount then pcall(SetItemButtonCount, b, s.count or 0) end
    if SetItemButtonDesaturated then pcall(SetItemButtonDesaturated, b, s.locked) end
    if SetItemButtonQuality then pcall(SetItemButtonQuality, b, s.quality, s.link) end
    row.holder:Show()
    -- The game's bag code keeps slot buttons hidden until a bag window shows them.
    b:Show()
    -- Its "new item" glow is the bag window's business, not the list's.
    for _, k in ipairs({ "NewItemTexture", "BattlepayItemTexture" }) do
        local t = b[k]
        if type(t) == "table" and t.Hide then t:Hide() end
    end
    for _, k in ipairs({ "newitemglowAnim", "flashAnim" }) do
        local a = b[k]
        if type(a) == "table" and a.Stop then a:Stop() end
    end
    -- Our own icon under the game's slot button: it shows whether or not the button draws.
    row.icon:SetTexture(s.icon)
    row.icon:SetShown(s.icon ~= nil)
    row.icon:SetDesaturated(s.locked and true or false)
end

function UI:Render()
    if not (self.frame and self.frame:IsShown()) then return end
    local n = #self.entries
    self.sel = math.max(1, math.min(self.sel, n))
    if self.sel <= self.offset then self.offset = self.sel - 1 end
    if self.sel > self.offset + VISIBLE then self.offset = self.sel - VISIBLE end
    self.offset = math.max(0, math.min(self.offset, n - VISIBLE))

    local dim = self.mode == "confirm"
    for i, row in ipairs(self.rows) do
        local index = self.offset + i
        local e = self.entries[index]
        row.entry = e
        if not e then
            row:Hide()
        else
            row:Show()
            local selected = index == self.sel
            row.selTex:SetShown(selected)
            row.selEdge:SetShown(selected and self.focused)
            row:SetAlpha((dim and not selected) and 0.35 or 1)
            row.name:SetText(e.name)
            if e.nameColor then
                row.name:SetTextColor(unpack(e.nameColor))
            else
                row.name:SetTextColor(QualityColor(e.quality))
            end
            row.colA:SetText(e.a)
            row.colB:SetText(e.b)
            if ns.Gamepad then ns.Gamepad:Decorate(row, e, selected) end
            row.more:SetShown(e.stacks ~= nil and #e.stacks > 1)
            if e.stack then
                ShowItemButton(row, e.stack)
            else
                row.holder:Hide()
                row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:SetShown(e.kind ~= "empty" and e.kind ~= "option" and e.kind ~= "divider")
                row.icon:SetDesaturated(e.row ~= nil and e.row.bags == 0 and e.row.bank == 0)
            end
        end
    end

    local inList = self.mode == "list"
    self.heading:SetText(inList and "In your bags" or (self.drillTitle or ""))
    self.colHeadA:SetText(inList and "Bags" or ((self.mode == "stacks") and "Count" or ""))
    self.colHeadB:SetText(inList and "Total" or "")

    self.frame.title:SetText("Inventory - " .. (ns.charName or ""))
    self.scrollText:SetText(n > VISIBLE and ((self.offset + 1) .. "-" .. math.min(n, self.offset + VISIBLE) .. " of " .. n) or "")
    local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    self.money:SetText(coins and coins(GetMoney()) or "")
    self.free:SetText(ns.live.free .. "/" .. ns.live.slots .. " free" .. (ns.bankOpen and "  |cff9999ff(bank open)|r" or ""))
    self:RenderHint()

    self:UpdateBindings()
    self:UpdateTooltip()
end

function UI:RenderHint()
    if self.message then
        self.hint:SetText(self.message)
        return
    end
    if self.gamepadMode and ns.Gamepad and ns.Gamepad.browsing then
        self.hint:SetText("|cffaaaaaaD-pad: browse items elsewhere   Up from the top: back to your bags|r   "
            .. Glyph("PAD2") .. " Close")
        return
    end
    if self.gamepadMode then
        -- The buttons are the game's own here; the D-pad follows the list.
        self.hint:SetText(Glyph("PAD1") .. " Select   " .. Glyph("PAD3") .. " Use   " .. Glyph("PAD4") .. " More   "
            .. Glyph("PAD2") .. " Close   |cffaaaaaaD-pad: items, stacks|r")
        return
    end
    if not self.focused then
        self.hint:SetText("")
        return
    end
    if self.mode == "confirm" then
        local s = self.confirm
        self.hint:SetText("|cffff5555Destroy|r " .. (s.link or "?") .. " x" .. (s.count or 1) .. "?   " .. Glyph("PAD1") .. " Yes   " .. Glyph("PAD2") .. " No")
        return
    end
    local e = self:Selected()
    local parts = {}
    if self.mode == "more" then
        parts[#parts + 1] = Glyph("PAD1") .. " Select"
    elseif e and e.stacks and #e.stacks > 1 and not e.stack then
        parts[#parts + 1] = Glyph("PAD1") .. " Stacks"
    elseif e and e.stack and e.stack.empty then
        parts[#parts + 1] = Glyph("PAD1") .. " Put here"
    elseif e and e.stack then
        parts[#parts + 1] = Glyph("PAD1") .. ((GetCursorInfo() and " Place") or " Pick up")
        parts[#parts + 1] = Glyph("PAD3") .. " Use"
        parts[#parts + 1] = Glyph("PAD4") .. " More"
    end
    parts[#parts + 1] = Glyph("PAD2") .. (self.mode == "list" and " Close" or " Back")
    self.hint:SetText(table.concat(parts, "   "))
end

function UI:Flash(text)
    self.message = text
    self:RenderHint()
    if self.messageTimer then self.messageTimer:Cancel() end
    self.messageTimer = C_Timer.NewTimer(3, function()
        UI.message = nil
        UI:RenderHint()
    end)
end

function UI:VisibleRow(index)
    local i = index - self.offset
    if i >= 1 and i <= VISIBLE then return self.rows[i] end
end

function UI:UpdateTooltip()
    if not self.focused then return end
    local e = self:Selected()
    local row = e and self:VisibleRow(self.sel)
    if not row or (e.stack and e.stack.empty) or e.kind == "empty" then
        if GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == self.list then GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", -4, 0)
    local s = e.stack
    if s and s.bag == ns.BANK and BankButtonIDToInvSlotID then
        GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(s.slot))
    elseif s then
        GameTooltip:SetBagItem(s.bag, s.slot)
    elseif e.link then
        GameTooltip:SetHyperlink(e.link)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------------------------
-- Gamepad and keyboard
---------------------------------------------------------------------------------------------
function UI:ClearBindings()
    if self.bound and not InCombatLockdown() then
        ClearOverrideBindings(self.frame)
        self.bound = false
    end
end

-- Point every key at the right button for the current selection: the selected stack's real
-- item button for use and pick up, otherwise our own (insecure) navigation buttons.
function UI:UpdateBindings()
    if InCombatLockdown() then return end
    if not self.frame:IsShown() then
        self:ClearBindings()
        return
    end
    ClearOverrideBindings(self.frame)
    self.bound = false
    -- Forever's gamepad mode puts its own override bindings on the pad: with ours cleared, what
    -- PAD1 does now tells whether it is on.
    local wasGamepad = self.gamepadMode
    self.gamepadMode = ns.GamepadUI()
    if wasGamepad ~= self.gamepadMode then self:RenderHint() end
    -- Escape closes a list opened on its own (/li). With the bags, Escape is the game's: it
    -- closes the bags, and the list with them.
    if self.openedBy == nil then
        SetOverrideBindingClick(self.frame, true, "ESCAPE", self.nav.close:GetName(), "LeftButton")
        self.bound = true
    end
    if not self.focused or self.gamepadMode then return end
    local e = self:Selected()
    local row = e and e.stack and self:VisibleRow(self.sel)
    local itemButton = row and (self.mode == "list" or self.mode == "stacks") and row.item:GetName()
    for action, keys in pairs(self.KEYS) do
        local target, mouse = self.nav[action]:GetName(), "LeftButton"
        if itemButton and action == "accept" then
            target = itemButton -- left click: pick up, or place what the cursor holds
        elseif itemButton and action == "use" and not e.stack.empty then
            target, mouse = itemButton, "RightButton"
        end
        for _, key in ipairs(keys) do SetOverrideBindingClick(self.frame, true, key, target, mouse) end
    end
    self.bound = true
end

function UI:OnCombat(starting)
    if not self.frame then return end
    if starting then
        -- Last chance before lockdown: drop the bindings and read the gamepad directly instead
        -- (not in Forever's gamepad mode: the game's cursor keeps the pad).
        self:ClearBindings()
        if not self.gamepadMode then SetPadCapture(self.frame, true) end
    else
        SetPadCapture(self.frame, false)
        self:Render()
    end
end

function UI:StartRepeat(action)
    self:StopRepeat()
    self.repeatTimer = C_Timer.NewTimer(HOLD_DELAY, function()
        UI.repeatTicker = C_Timer.NewTicker(HOLD_RATE, function() UI:Do(action) end)
    end)
end

function UI:StopRepeat()
    if self.repeatTimer then self.repeatTimer:Cancel() self.repeatTimer = nil end
    if self.repeatTicker then self.repeatTicker:Cancel() self.repeatTicker = nil end
end

function UI:Select(index, fromMouse)
    if index < 1 or index > #self.entries then return end
    if self.entries[index].kind == "divider" then
        if fromMouse then return end
        -- (stepping onto it: one further, the way we were going)
        local step = index > self.sel and 1 or -1
        if self.entries[index + step] then return self:Select(index + step) end
        return
    end
    if fromMouse and self.mode == "confirm" then return end
    if index == self.sel and fromMouse then return end
    self.sel = index
    self:Render()
end

function UI:Scroll(delta)
    self:Select(math.max(1, math.min(#self.entries, self.sel + delta)))
end

function UI:Drill(e)
    self.listSel = self.sel
    self.mode = "stacks"
    self.drillKey = e.key
    self.sel, self.offset = 1, 0
    self:Refresh()
end

function UI:LeaveStacks()
    self.mode = "list"
    self.drillKey = nil
    self.sel, self.offset = self.listSel or 1, 0
end

-- `fromPad` is true when called from the direct gamepad handler (combat); otherwise from a
-- navigation button or a mouse click.
function UI:Do(action, fromPad)
    local e = self:Selected()
    local n = #self.entries
    if action == "up" then
        if self.mode ~= "confirm" then self:Select(self.sel > 1 and self.sel - 1 or n) end
    elseif action == "down" then
        if self.mode ~= "confirm" then self:Select(self.sel < n and self.sel + 1 or 1) end
    elseif action == "pageUp" then
        if self.mode ~= "confirm" then self:Select(math.max(1, self.sel - VISIBLE)) end
    elseif action == "pageDown" then
        if self.mode ~= "confirm" then self:Select(math.min(n, self.sel + VISIBLE)) end
    elseif action == "back" then
        if self.mode == "confirm" then
            self.mode, self.confirm = "more", nil
            self:Render()
        elseif self.mode == "more" then
            self.mode, self.moreStack = self.moreReturn or "list", nil
            self.sel = self.moreSel or 1
            self:Refresh()
        elseif self.mode == "stacks" then
            self:LeaveStacks()
            self:Refresh()
        else
            self:Do("close")
        end
    elseif action == "close" then
        if self.openedBy == "bags" and CloseAllBags then
            -- Closing the game's bags closes the list with them.
            pcall(CloseAllBags)
        end
        if self.frame:IsShown() then self.frame:Hide() end
    elseif action == "accept" then
        if self.mode == "confirm" then
            self:DestroyConfirmed()
        elseif self.mode == "more" then
            if e then self:MoreOption(e.action) end
        elseif e and e.stacks and #e.stacks > 1 and not e.stack then
            self:Drill(e)
        elseif e and e.stack then
            -- Only reached without a secure binding (combat): pick up / place is allowed.
            ns.PickupSlot(e.stack.bag, e.stack.slot)
        elseif e and e.row then
            self:Flash("None of these are in your bags right now.")
        end
    elseif action == "use" then
        if self.mode ~= "list" and self.mode ~= "stacks" then return end
        if e and e.stacks and #e.stacks > 1 and not e.stack then
            self:Drill(e)
        elseif e and e.stack and not e.stack.empty then
            -- Only reached without a secure binding: during combat.
            self:Flash("Using items with the controller waits until combat ends. Clicking still works.")
        end
    elseif action == "more" then
        if self.mode ~= "list" and self.mode ~= "stacks" then return end
        if e and e.stack and not e.stack.empty then
            self.moreStack, self.moreReturn, self.moreSel = e.stack, self.mode, self.sel
            self.mode = "more"
            self.sel, self.offset = 1, 0
            self:Refresh()
        elseif e and e.stacks and #e.stacks > 1 and not e.stack then
            self:Drill(e)
        end
    end
end

function UI:MoreOption(action)
    local s = self.moreStack
    if not s then return end
    if action == "destroy" then
        self.confirm = s
        self.mode = "confirm"
        self:Render()
    elseif action == "link" then
        local inserted = ChatEdit_InsertLink and ChatEdit_InsertLink(s.link)
        if not inserted and ChatFrame_OpenChat then ChatFrame_OpenChat(s.link) end
        self:Do("back")
    else
        self:Do("back")
    end
end

function UI:DestroyConfirmed()
    local s = self.confirm
    self.confirm = nil
    -- Back to where the More menu was opened from.
    self.mode, self.moreStack = self.moreReturn or "list", nil
    self.sel = self.moreSel or 1
    if s and ns.SlotLink(s.bag, s.slot) == s.link then
        ClearCursor()
        ns.PickupSlot(s.bag, s.slot)
        if CursorHasItem() then DeleteCursorItem() end
    else
        self:Flash("That stack moved, so nothing was destroyed.")
    end
    self:Refresh()
end

---------------------------------------------------------------------------------------------
-- Opening and closing, and taking over the bag keys
---------------------------------------------------------------------------------------------
-- `opener` is "bags" when the list opened with the game's bags, nil when the player opened it
-- on its own (/li).
function UI:Open(opener)
    if not self.frame then return end
    if self.frame:IsShown() then return end
    self.openedBy = opener
    self.focused = true
    self.mode, self.sel, self.offset = "list", 1, 0
    self:Place()
    self.frame:Show()
end

-- `opener` nil closes the list; "bags" closes it only if it opened with the bags.
function UI:Close(opener)
    if not (self.frame and self.frame:IsShown()) then return end
    if opener ~= nil and opener ~= self.openedBy then return end
    self.frame:Hide()
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open(nil)
    end
end

-- With the bags: beside the game's bag window. On its own: where the player last dragged it.
function UI:Place()
    local bags = self:ShownBagFrame()
    if self.openedBy == "bags" and bags then
        -- Right over the hidden bag window: the game's menus for an item (More) open over its
        -- hidden slot, so they land inside the list.
        self.frame:ClearAllPoints()
        self.frame:SetPoint("BOTTOMRIGHT", bags, "BOTTOMRIGHT", 0, 0)
    else
        self:RestorePosition()
    end
end

---------------------------------------------------------------------------------------------
-- The game's bag windows, watched (never replaced: the radial menu, the bag chord, the bag
-- keys and the vendor all open these, and replacing the game's functions taints them)
---------------------------------------------------------------------------------------------
UI.bagFrames = {}
UI.bagOpens = {}

function UI:ShownBagFrame()
    for _, f in ipairs(self.bagFrames) do
        if f:IsShown() then return f end
    end
end

local function BagFrameShown(f)
    -- Diagnostics for /li probe: where the call that opened the bags came from (names only).
    local stack = debugstack and debugstack(3, 12, 0) or ""
    table.insert(UI.bagOpens, 1, { frame = f:GetName(), time = date and date("%H:%M:%S"), stack = stack })
    if #UI.bagOpens > 6 then table.remove(UI.bagOpens) end
    if ns.db.replaceBags then
        if UI.frame:IsShown() then
            if UI.openedBy == "bags" then
                UI:Place()
                UI:Refresh()
            end
        else
            UI:Open("bags")
        end
    end
end

local function BagFrameHidden()
    if UI:ShownBagFrame() then return end
    UI:Close("bags")
end

local function Watch(f)
    if not f or f.listInventoryWatched or not f.HookScript then return end
    f.listInventoryWatched = true
    table.insert(UI.bagFrames, f)
    f:HookScript("OnShow", BagFrameShown)
    f:HookScript("OnHide", BagFrameHidden)
end

function UI:WatchBagFrames()
    Watch(_G.ContainerFrameCombinedBags)
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        -- Only frames that show player bags; bank bag windows are left alone.
        if f then
            f:HookScript("OnShow", function(self)
                if ns.IsPlayerBag(self:GetID()) then BagFrameShown(self) end
            end)
            f:HookScript("OnHide", BagFrameHidden)
            table.insert(self.bagFrames, f)
        end
    end
end

---------------------------------------------------------------------------------------------
-- Forever's gamepad mode: follow the game's cursor
---------------------------------------------------------------------------------------------
local held = {}

local function RowOf(button)
    if not button then return nil end
    for i, row in ipairs(UI.rows) do
        if button == row or button == row.item then return i end
    end
end

local function CursorTarget(row)
    return row.holder:IsShown() and row.item or row
end

function UI:StopFollowing()
    wipe(held)
    self.cursorOnList = false
    if ns.Gamepad then ns.Gamepad:Release() end
end

function UI:FollowCursor()
    if ns.Gamepad then ns.Gamepad:Tick() end
end

---------------------------------------------------------------------------------------------
-- /li probe: names and call paths only, saved to ListInventoryDB.probe
---------------------------------------------------------------------------------------------
local function FunctionNames(t)
    local names, seen = {}, {}
    local function add(tbl)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(k) == "string" and type(v) == "function" and not seen[k] then
                seen[k] = true
                names[#names + 1] = k
            end
        end
    end
    if type(t) ~= "table" then return nil end
    add(t)
    local mt = getmetatable(t)
    if mt and type(mt.__index) == "table" then add(mt.__index) end
    table.sort(names)
    return names
end

local function FieldNames(t)
    if type(t) ~= "table" then return nil end
    local names = {}
    for k, v in pairs(t) do
        if type(k) == "string" then names[#names + 1] = k .. " (" .. type(v) .. ")" end
    end
    table.sort(names)
    return names
end

function UI:Probe()
    local p = { time = date and date("%Y-%m-%d %H:%M:%S") }
    if GetBuildInfo then p.build = table.concat({ tostringall(GetBuildInfo()) }, " ") end
    p.gamepadMode = self.gamepadMode
    p.pad1 = GetBindingAction("PAD1", true)
    p.pad2 = GetBindingAction("PAD2", true)
    p.paddown = GetBindingAction("PADDDOWN", true)
    p.gamePadEnabled = C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled()
    local nav = _G.SmartNavigation
    p.smartNavigation = FunctionNames(nav)
    p.gamepadModeFields = FieldNames(_G.GamepadMode)
    p.frameControlsManager = FunctionNames(_G.GamepadMode and GamepadMode.FrameControlsManager)
    local globals = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:find("SmartNav") or k:find("InputFunction") or k:find("Radial")
            or k:find("GamePad") or k:find("Gamepad")) then
            globals[#globals + 1] = k .. " (" .. type(v) .. ")"
        end
    end
    table.sort(globals)
    p.globals = globals
    p.bagFrames = {}
    for _, f in ipairs(self.bagFrames) do p.bagFrames[#p.bagFrames + 1] = (f:GetName() or "?") .. (f:IsShown() and " shown" or "") end
    p.bagOpens = self.bagOpens
    p.listShown = self.frame:IsShown()
    p.cursorOnList = self.cursorOnList
    if nav and nav.GetCurrentButton then
        local ok, b = pcall(nav.GetCurrentButton, nav)
        p.cursorButton = ok and b and b.GetName and (b:GetName() or "unnamed") or tostring(ok and b)
    end
    -- Can the game's cursor be put on a row of ours?
    local row = self.frame:IsShown() and self.rows[1]:IsShown() and self.rows[1]
    if row and nav and nav.SelectButton then
        local ok, err = pcall(nav.SelectButton, nav, CursorTarget(row))
        local ok2, b = pcall(nav.GetCurrentButton, nav)
        p.selectTest = { called = ok, err = not ok and tostring(err) or nil,
            landed = ok2 and b == CursorTarget(row) or false }
    end
    ns.db.probe = p
    ns.Print(("probe saved: %d cursor functions, %d manager functions, %d globals, %d bag opens recorded.")
        :format(p.smartNavigation and #p.smartNavigation or 0, p.frameControlsManager and #p.frameControlsManager or 0,
            #globals, #self.bagOpens))
    if p.selectTest then
        ns.Print("cursor test: " .. (p.selectTest.landed and "the game's cursor moved onto the list." or "the game's cursor could not be moved onto the list."))
    end
    ns.Print("Type /reload, then send WTF/Account/<account>/SavedVariables/ListInventory.lua")
end

function UI:Diagnose()
    local b = self.rows and self.rows[1] and self.rows[1].item
    ns.Print("item button template: " .. (b and (b.GetObjectType and b:GetObjectType() or "?") or "missing")
        .. ", gamepad input: " .. tostring(self.frame and self.frame.EnableGamePadButton ~= nil)
        .. ", gamepad propagation: " .. tostring(self.frame and self.frame.SetPropagateGamePadButton ~= nil)
        .. ", bindings active: " .. tostring(self.bound == true)
        .. ", gamepad mode: " .. tostring(self.gamepadMode == true)
        .. ", bag windows watched: " .. #self.bagFrames)
    -- Why the game's slot button might not draw inside a row
    local row = self.rows and self.rows[1]
    if b and row then
        local ok, text = pcall(function()
            local icon
            for _, candidate in ipairs({ b.icon, b.Icon, b:GetName() and _G[b:GetName() .. "IconTexture"] }) do
                if type(candidate) == "table" and candidate.GetTexture then icon = candidate break end
            end
            local w, h = b:GetSize()
            return ("slot button: shown %s, visible %s, alpha %s, size %sx%s, scale %s, points %s, holder visible %s, icon %s, GetBagID %s, bag %s slot %s")
                :format(tostring(b:IsShown()), tostring(b:IsVisible()), tostring(b:GetAlpha()), tostring(w), tostring(h),
                    tostring(b:GetScale()), tostring(b:GetNumPoints()), tostring(row.holder:IsVisible()),
                    tostring(icon and icon:GetTexture()), tostring(b.GetBagID ~= nil),
                    tostring(row.holder:GetID()), tostring(b:GetID()))
        end)
        ns.Print(ok and text or ("slot button: could not inspect (" .. tostring(text) .. ")"))
    end
end
