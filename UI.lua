-- ListInventory: the list window that replaces the bags, with gamepad and keyboard navigation.
--
-- How item actions stay "real": each row that stands for one stack holds a stock
-- ContainerFrameItemButton for that bag and slot, so mouse clicks do exactly what they do in
-- the default bags (use, equip, sell, bank, trade, mail, split, link...). The gamepad reaches
-- the same buttons through override bindings that click the selected row's button, which keeps
-- the click secure. Override bindings can't change during combat, so in combat the window
-- reads the gamepad directly instead: navigation, stacks, pick up and destroy still work, but
-- using an item from the gamepad has to wait for the end of combat (mouse clicks still work).
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
    prevView = { "PADLSHOULDER" },
    nextView = { "PADRSHOULDER" },
    accept = { "PAD1" },
    back = { "PAD2" },
    pickup = { "PAD3" },
    destroy = { "PAD4" },
}
local REPEATS = { up = true, down = true, pageUp = true, pageDown = true }

-- Gamepad button -> action, for reading the gamepad directly during combat.
local PAD_ACTIONS = {}
for action, keys in pairs(UI.KEYS) do
    for _, key in ipairs(keys) do
        if key:find("^PAD") then PAD_ACTIONS[key] = action end
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

local function EmptyEntry(s)
    return { kind = "stack", key = EMPTY_KEY, stack = s, name = s.where, a = "", b = "", nameColor = { 0.6, 0.6, 0.6 } }
end

function UI:BuildEntries()
    local live = ns.live
    local rows = Data.BuildRows({
        chars = ns.group, current = ns.charName, stacks = live.stacks,
        view = self.mode == "list" and ns.db.view or "bags",
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

    for _, row in ipairs(rows) do entries[#entries + 1] = RowEntry(row) end
    if ns.db.view == "bags" and #live.empty > 0 then
        local e = {
            kind = "empty", key = EMPTY_KEY, name = "Empty slots", a = tostring(#live.empty), b = "",
            stacks = live.empty, nameColor = { 0.6, 0.6, 0.6 },
        }
        if #live.empty == 1 then e.stack = live.empty[1] end
        entries[#entries + 1] = e
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

local function MakeTab(parent, label, view)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(110, 20)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetAllPoints()
    tab.text:SetText(label)
    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetPoint("BOTTOMLEFT", 10, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", -10, 0)
    tab.underline:SetHeight(2)
    tab.underline:SetColorTexture(1, 0.82, 0, 1)
    tab:SetScript("OnClick", function() UI:SetView(view) end)
    return tab
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
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        ns.db.point = { point, relPoint, x, y }
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "ListInventoryFrame")
    self.frame = frame
    self:RestorePosition()

    frame.title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not frame.TitleText then frame.title:SetPoint("TOP", 0, -14) end

    self.tabs = {
        bags = MakeTab(frame, "Bags", "bags"),
        all = MakeTab(frame, "Everything", "all"),
    }
    self.tabs.bags:SetPoint("TOPLEFT", 16, -30)
    self.tabs.all:SetPoint("LEFT", self.tabs.bags, "RIGHT", 4, 0)

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

    -- During combat the gamepad is read directly (see the top of this file). Out of combat the
    -- presses propagate on to the override bindings.
    if frame.EnableGamePadButton then
        frame:EnableGamePadButton(true)
        frame:SetPropagateGamePadButton(true)
        frame:SetScript("OnGamePadButtonDown", function(_, key)
            if not InCombatLockdown() or not UI.focused then return end
            local action = PAD_ACTIONS[key]
            if not action then return end
            UI:Do(action, true)
            if REPEATS[action] then UI:StartRepeat(action, true) end
        end)
        frame:SetScript("OnGamePadButtonUp", function() UI:StopRepeat() end)
    end

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
        if GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == UI.list then GameTooltip:Hide() end
    end)

    self:InstallBagHooks()
end

function UI:RestorePosition()
    local p = ns.db.point
    self.frame:ClearAllPoints()
    if p then
        self.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        self.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -90, 110)
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
end

local function ShowItemButton(row, s)
    local b = row.item
    row.holder:SetID(s.bag)
    b:SetID(s.slot)
    if b.SetBagID then pcall(b.SetBagID, b, s.bag) end
    SetItemButtonTexture(b, s.icon)
    SetItemButtonCount(b, s.count or 0)
    SetItemButtonDesaturated(b, s.locked)
    if SetItemButtonQuality then pcall(SetItemButtonQuality, b, s.quality, s.link) end
    row.holder:Show()
    row.icon:Hide()
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
            row.more:SetShown(e.stacks ~= nil and #e.stacks > 1)
            if e.stack then
                ShowItemButton(row, e.stack)
            else
                row.holder:Hide()
                row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:SetShown(e.kind ~= "empty")
                row.icon:SetDesaturated(e.row ~= nil and e.row.bags == 0 and e.row.bank == 0)
            end
        end
    end

    local inList = self.mode == "list"
    for view, tab in pairs(self.tabs) do
        tab:SetShown(inList)
        tab.underline:SetShown(ns.db.view == view)
        tab.text:SetFontObject(ns.db.view == view and "GameFontHighlight" or "GameFontDisable")
    end
    self.heading:SetShown(not inList)
    if not inList then self.heading:SetText(self.drillTitle or "") end
    self.colHeadA:SetText(inList and "Bags" or "Count")
    self.colHeadB:SetText(inList and "Total" or "")

    self.frame.title:SetText("Inventory - " .. (ns.charName or ""))
    self.scrollText:SetText(n > VISIBLE and ((self.offset + 1) .. "-" .. math.min(n, self.offset + VISIBLE) .. " of " .. n) or "")
    self.money:SetText(GetCoinTextureString and GetCoinTextureString(GetMoney()) or "")
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
    if not self.focused then
        self.hint:SetText("|cffaaaaaaPress your bag key to use the list with the controller.|r")
        return
    end
    if self.mode == "confirm" then
        local s = self.confirm
        self.hint:SetText("|cffff5555Destroy|r " .. (s.link or "?") .. " x" .. (s.count or 1) .. "?   " .. Glyph("PAD1") .. " Yes   " .. Glyph("PAD2") .. " No")
        return
    end
    local e = self:Selected()
    local parts = {}
    if e and e.stacks and #e.stacks > 1 and not e.stack then
        parts[#parts + 1] = Glyph("PAD1") .. " Stacks"
    elseif e and e.stack and e.stack.empty then
        parts[#parts + 1] = Glyph("PAD1") .. " Put here"
    elseif e and e.stack then
        parts[#parts + 1] = Glyph("PAD1") .. ((GetCursorInfo() and " Place") or " Use")
        parts[#parts + 1] = Glyph("PAD3") .. " Pick up"
        parts[#parts + 1] = Glyph("PAD4") .. " Destroy"
    end
    parts[#parts + 1] = Glyph("PAD2") .. (self.mode == "stacks" and " Back" or " Close")
    if self.mode == "list" then parts[#parts + 1] = Glyph("PADLSHOULDER") .. Glyph("PADRSHOULDER") .. " View" end
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
    if not (self.frame:IsShown() and self.focused) then
        self:ClearBindings()
        return
    end
    ClearOverrideBindings(self.frame)
    local e = self:Selected()
    local row = e and e.stack and self:VisibleRow(self.sel)
    local itemButton = row and self.mode ~= "confirm" and row.item:GetName()
    for action, keys in pairs(self.KEYS) do
        local target, mouse = self.nav[action]:GetName(), "LeftButton"
        if itemButton and action == "accept" then
            target = itemButton
            mouse = (GetCursorInfo() or e.stack.empty) and "LeftButton" or "RightButton"
        elseif itemButton and action == "pickup" then
            target = itemButton
        end
        for _, key in ipairs(keys) do SetOverrideBindingClick(self.frame, true, key, target, mouse) end
    end
    self.bound = true
end

function UI:OnCombat(starting)
    if not self.frame then return end
    if starting then
        -- Last chance before lockdown: drop the bindings and read the gamepad directly instead.
        self:ClearBindings()
        if self.frame.SetPropagateGamePadButton then self.frame:SetPropagateGamePadButton(false) end
    else
        if self.frame.SetPropagateGamePadButton then self.frame:SetPropagateGamePadButton(true) end
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
    if fromMouse and self.mode == "confirm" then return end
    if index == self.sel and fromMouse then return end
    self.sel = index
    self:Render()
end

function UI:Scroll(delta)
    self:Select(math.max(1, math.min(#self.entries, self.sel + delta)))
end

function UI:SetView(view)
    if self.mode ~= "list" or ns.db.view == view then return end
    ns.db.view = view
    self.sel, self.offset = 1, 0
    self:Refresh()
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
    elseif action == "prevView" or action == "nextView" then
        self:SetView(ns.db.view == "bags" and "all" or "bags")
    elseif action == "back" then
        if self.mode == "confirm" then
            self.mode, self.confirm = self.confirmReturn, nil
            self:Render()
        elseif self.mode == "stacks" then
            self:LeaveStacks()
            self:Refresh()
        elseif self.openedBy then
            -- Opened by another window (vendor, bank, mail): hand the controller back to it.
            self.focused = false
            GameTooltip:Hide()
            self:Render()
        else
            self.frame:Hide()
        end
    elseif action == "accept" then
        if self.mode == "confirm" then
            self:DestroyConfirmed()
        elseif e and e.stacks and #e.stacks > 1 and not e.stack then
            self:Drill(e)
        elseif e and e.stack then
            -- Only reached without a secure binding: during combat.
            if GetCursorInfo() or e.stack.empty then
                ns.PickupSlot(e.stack.bag, e.stack.slot)
            else
                self:Flash("Using items with the controller waits until combat ends. Clicking still works.")
            end
        elseif e and e.row then
            self:Flash("None of these are in your bags right now.")
        end
    elseif action == "pickup" then
        if self.mode == "confirm" then return end
        if e and e.stack then
            ns.PickupSlot(e.stack.bag, e.stack.slot)
        elseif e and e.stacks and #e.stacks > 1 then
            self:Drill(e)
        end
    elseif action == "destroy" then
        if self.mode == "confirm" then return end
        if e and e.stack and not e.stack.empty then
            self.confirm = e.stack
            self.confirmReturn = self.mode
            self.mode = "confirm"
            self:Render()
        elseif e and e.stacks and #e.stacks > 1 then
            self:Drill(e)
        end
    end
end

function UI:DestroyConfirmed()
    local s = self.confirm
    self.mode, self.confirm = self.confirmReturn, nil
    if s and ns.SlotLink(s.bag, s.slot) == s.link then
        ClearCursor()
        ns.PickupSlot(s.bag, s.slot)
        if CursorHasItem() then DeleteCursorItem() end
    else
        self:Flash("That stack moved, so nothing was destroyed.")
    end
    self:Render()
end

---------------------------------------------------------------------------------------------
-- Opening and closing, and taking over the bag keys
---------------------------------------------------------------------------------------------
-- `opener` is the window that asked for the bags (vendor, bank, mail...), or nil when the
-- player did. Only a player-opened list takes the controller straight away.
function UI:Open(opener)
    if not self.frame then return end
    if self.frame:IsShown() then return end
    self.openedBy = opener
    self.focused = opener == nil
    self.mode, self.sel, self.offset = "list", 1, 0
    self.frame:Show()
end

-- `opener` nil closes the list. A window closing (vendor, bank...) passes itself and only
-- closes the list if it was the one that opened it.
function UI:Close(opener)
    if not (self.frame and self.frame:IsShown()) then return end
    if opener ~= nil and opener ~= self.openedBy then return end
    self.frame:Hide()
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        if self.focused then
            self.frame:Hide()
        else
            self.focused = true
            self:Render()
        end
    else
        self:Open(nil)
    end
end

function UI:InstallBagHooks()
    local orig = {}
    self.orig = orig
    local function Replace(name, fn)
        local original = _G[name]
        if type(original) ~= "function" then return end
        orig[name] = original
        _G[name] = function(...)
            if ns.db.replaceBags then return fn(original, ...) end
            return original(...)
        end
    end

    Replace("ToggleAllBags", function() UI:Toggle() end)
    Replace("ToggleBackpack", function() UI:Toggle() end)
    Replace("OpenAllBags", function(_, frame) UI:Open(frame or "auto") end)
    Replace("OpenBackpack", function() UI:Open("auto") end)
    Replace("CloseAllBags", function(original, frame, ...)
        UI:Close(frame)
        return original(frame, ...) -- still closes any default bank bag windows
    end)
    Replace("CloseBackpack", function(original, ...)
        UI:Close()
        return original(...)
    end)
    Replace("ToggleBag", function(original, id, ...)
        if ns.IsPlayerBag(id) then return UI:Toggle() end
        return original(id, ...)
    end)
    Replace("OpenBag", function(original, id, ...)
        if ns.IsPlayerBag(id) then return UI:Open("auto") end
        return original(id, ...)
    end)
end

function UI:Diagnose()
    local b = self.rows and self.rows[1] and self.rows[1].item
    ns.Print("item button template: " .. (b and (b.GetObjectType and b:GetObjectType() or "?") or "missing")
        .. ", gamepad input: " .. tostring(self.frame and self.frame.EnableGamePadButton ~= nil)
        .. ", bindings active: " .. tostring(self.bound == true))
end
