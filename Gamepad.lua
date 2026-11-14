-- ListInventory: Forever's gamepad mode.
--
-- The game's controller cursor (SmartNavigation) only moves inside windows the game manages, so
-- the list can't hold it. Instead the game's bag window stays open, faded out, and the cursor is
-- steered through its slots in the list's order: each occupied slot gets jump overrides, so
-- up/down go to the previous/next item in the list and left/right step through that item's
-- stacks. The list highlights whatever slot the cursor is on. A, X, Y and B stay the game's
-- own, so using, equipping, splitting and destroying work exactly as in the default bags.
--
-- The game's frames are never changed directly (that taints them in Forever): the fade is an
-- alpha animation of ours aimed at them.
local _, ns = ...
local UI = ns.UI

local GP = {}
ns.Gamepad = GP

GP.touched = {}      -- game slot buttons we set jump overrides on
GP.indexBySlot = {}  -- "bag:slot" -> { entry index, stack index }
GP.stackIndex = nil  -- which of the selected entry's stacks the cursor is on

local function Nav()
    return _G.SmartNavigation
end

local function Dir(name)
    local dirs = _G.SMART_NAV_INPUT_DIRECTION
    return dirs and dirs[name]
end

local function Available()
    return Nav() and _G.SmartNavigation_AddJumpNavigationOverride and Dir("UP") ~= nil
end

local function SlotKey(button)
    if not (button and button.GetBagID and button.GetID) then return nil end
    local ok, bag = pcall(button.GetBagID, button)
    if not ok or type(bag) ~= "number" then return nil end
    return bag .. ":" .. button:GetID()
end

---------------------------------------------------------------------------------------------
-- Fading the game's windows (an animation of ours; their own alpha is never touched)
---------------------------------------------------------------------------------------------
local fader = CreateFrame("Frame")
local fades = {}

local function Fade(region, on)
    if not (region and region.GetObjectType) then return end
    local group = fades[region]
    if not group then
        if not on then return end
        local ok, g = pcall(function()
            local g = fader:CreateAnimationGroup()
            local a = g:CreateAnimation("Alpha")
            a:SetTarget(region)
            a:SetFromAlpha(0)
            a:SetToAlpha(0)
            a:SetDuration(3600)
            g:SetLooping("REPEAT")
            return g
        end)
        if not ok then return end
        group = g
        fades[region] = group
    end
    if on and not group:IsPlaying() then
        group:Play()
    elseif not on and group:IsPlaying() then
        group:Stop()
    end
end

-- The game's bag window is hidden while the list is open with it, whichever input is in use,
-- except while the cursor holds an item: then it shows, so the item sits over real slots.
function GP:Covering()
    return ns.db.hideGrid ~= false and UI.frame and UI.frame:IsShown() and UI.openedBy == "bags"
end

-- Holding an item with the Gamepad UI on: the game's grid is back in charge until it's placed.
function GP:Handover()
    return self.holding and UI.gamepadMode and self:Covering()
end

function GP:ShouldHide()
    return self:Covering() and not self:Handover()
end

function GP:UpdateFade()
    local hide = self:ShouldHide()
    for _, f in ipairs(UI.bagFrames) do Fade(f, hide and f:IsShown()) end
    local nav = Nav()
    Fade(nav and nav.Pointer, hide and UI.gamepadMode)
    self:Block(hide)
end

-- Something of ours over the hidden bag window, so stray mouse clicks can't reach its slots.
function GP:Block(on)
    local bags = on and UI:ShownBagFrame()
    if not self.blocker then
        local b = CreateFrame("Frame", nil, UIParent)
        b:EnableMouse(true)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function() end)
        b:SetFrameStrata("HIGH")
        b:SetFrameLevel(1) -- under the list, which sits over the same window
        b:Hide()
        self.blocker = b
    end
    if bags then
        self.blocker:ClearAllPoints()
        self.blocker:SetAllPoints(bags)
        self.blocker:Show()
    else
        self.blocker:Hide()
    end
end

---------------------------------------------------------------------------------------------
-- The game's slot buttons, by bag and slot
---------------------------------------------------------------------------------------------
local function CollectButtons(frame, out, depth)
    if not frame or depth > 4 then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        local key = child.IsShown and child:IsShown() and SlotKey(child)
        if key then
            out[key] = child
        else
            CollectButtons(child, out, depth + 1)
        end
    end
end

function GP:SlotButtons()
    local out = {}
    for _, f in ipairs(UI.bagFrames) do
        if f:IsShown() then CollectButtons(f, out, 0) end
    end
    return out
end

---------------------------------------------------------------------------------------------
-- Steering
---------------------------------------------------------------------------------------------
local function Jump(from, dir, to)
    pcall(_G.SmartNavigation_AddJumpNavigationOverride, from, Dir(dir), to)
end

function GP:Clear()
    local clear = _G.SmartNavigation_ClearJumpNavigationOverrides
    for b in pairs(self.touched) do
        if clear then pcall(clear, b) end
    end
    wipe(self.touched)
    wipe(self.indexBySlot)
    self.chain = nil
end

function GP:Active()
    return UI.gamepadMode and UI.frame and UI.frame:IsShown() and UI.openedBy == "bags"
        and UI:ShownBagFrame() ~= nil and Available()
end

-- Rebuild the jump chain from the list's current order.
function GP:Apply()
    self:Clear()
    self:UpdateFade()
    -- (holding an item: the game's grid has the cursor until it's placed)
    if not self:Active() or self:Handover() then return end
    local buttons = self:SlotButtons()
    local chain = {}
    for i, e in ipairs(UI.entries) do
        local stacks = e.stacks or (e.stack and { e.stack }) or {}
        local found = {}
        for si, s in ipairs(stacks) do
            local key = s.bag .. ":" .. s.slot
            local b = buttons[key]
            if b then
                found[#found + 1] = b
                self.indexBySlot[key] = { i, si }
            end
        end
        if #found > 0 then chain[#chain + 1] = { index = i, buttons = found } end
    end
    for ci, link in ipairs(chain) do
        local prev, nxt = chain[ci - 1], chain[ci + 1]
        for bi, b in ipairs(link.buttons) do
            self.touched[b] = true
            -- (at an end: a jump to itself, so the cursor stays rather than wandering off)
            Jump(b, "UP", prev and prev.buttons[1] or b)
            Jump(b, "DOWN", nxt and nxt.buttons[1] or b)
            Jump(b, "LEFT", link.buttons[bi - 1] or b)
            Jump(b, "RIGHT", link.buttons[bi + 1] or b)
        end
    end
    self.chain = chain

    if #chain == 0 then
        -- The game may lay its slots out just after the window shows: look again shortly.
        self.retries = (self.retries or 0) + 1
        if self.retries <= 5 then C_Timer.After(0.1, function() GP:Apply() end) end
        return
    end
    self.retries = 0

    -- Put the cursor on the list's selection when the bags open, or when it sits on a bag slot
    -- the list doesn't know. (Never pulled back from another window, such as a vendor's.)
    local nav = Nav()
    local ok, current = pcall(nav.GetCurrentButton, nav)
    local key = ok and SlotKey(current)
    if not self.placed or (key and not self.indexBySlot[key]) then
        self.placed = true
        local target = chain[1]
        for _, link in ipairs(chain) do
            if link.index <= UI.sel then target = link end
        end
        if nav.SelectButton then pcall(nav.SelectButton, nav, target.buttons[1]) end
    end
end

-- From the list's OnUpdate.
function GP:Tick()
    local holding = GetCursorInfo() ~= nil
    if holding ~= self.holding then
        self.holding = holding
        if self:Handover() then
            -- The grid shows and the cursor moves on it as usual; the list steps aside.
            self:Clear()
            self:ShowList(false)
            self:UpdateFade()
        else
            self:ShowList(true)
            self:Apply() -- re-hides the grid and puts the list order back on the cursor
        end
    end
    if UI.gamepadMode then self:Follow() end
end

-- The list out of the way (invisible, no mouse) while the game's grid has the held item.
function GP:ShowList(on)
    if not UI.frame then return end
    UI.frame:SetAlpha(on and 1 or 0)
    UI.frame:EnableMouse(on)
    UI.list:SetShown(on)
end

-- The list follows the game's cursor.
function GP:Follow()
    if not self.chain then return end
    local nav = Nav()
    local ok, current = pcall(nav.GetCurrentButton, nav)
    local at = ok and self.indexBySlot[SlotKey(current) or ""]
    if not at then return end
    if at[1] ~= UI.sel or at[2] ~= self.stackIndex then
        UI.sel, self.stackIndex = at[1], at[2]
        UI:Render()
    end
end

-- From UI:Render: the selected row shows which of its stacks the cursor is on.
function GP:Decorate(row, e, selected)
    if not (selected and self.chain and e.stacks and #e.stacks > 1 and self.stackIndex) then return end
    local s = e.stacks[self.stackIndex]
    if not s then return end
    row.name:SetText(e.name .. "  |cffaaaaaa< " .. self.stackIndex .. " of " .. #e.stacks .. " >|r")
    row.colA:SetText(s.empty and "" or tostring(s.count))
end

function GP:Release()
    self:Clear()
    self.placed, self.retries, self.holding = false, 0, nil
    self:ShowList(true)
    self:UpdateFade()
    self.stackIndex = nil
end
