-- ListInventory: pure item-counting logic. Nothing here calls the game: everything comes in
-- as plain tables, so it can be tested outside the client (see tests/Data_test.lua).
local _, ns = ...

local Data = {}
ns.Data = Data

-- Key that identifies "the same item" for counting: the item ID, plus the random-enchant
-- suffix when there is one, so "of the Monkey" and "of the Eagle" are counted separately.
-- Returns nil for anything that is not an item link.
function Data.ItemKey(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("item:([%-%d:]*)")
    if not body then return nil end
    local fields = {}
    for v in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = v end
    local id = tonumber(fields[1])
    if not id then return nil end
    local suffix = tonumber(fields[7])
    if suffix and suffix ~= 0 then return id .. ":" .. suffix end
    return tostring(id)
end

-- Item ID from a key made by ItemKey.
function Data.KeyItemID(key)
    return key and tonumber(tostring(key):match("^(%-?%d+)")) or nil
end

-- The bracketed name inside an item link.
function Data.ItemName(link)
    if type(link) ~= "string" then return nil end
    return link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
end

-- Characters are grouped by realm, ruleset and faction: alts in the same group are counted together.
function Data.GroupKey(realm, ruleset, faction)
    return (realm or "?") .. "|" .. (ruleset or "normal") .. "|" .. (faction or "?")
end

-- Sum stack counts by key. `stacks` is a list of { key = ..., count = ... }.
function Data.CountStacks(stacks)
    local counts = {}
    for _, s in ipairs(stacks or {}) do
        if s.key then counts[s.key] = (counts[s.key] or 0) + (s.count or 1) end
    end
    return counts
end

local function LocationOrder(s)
    return s.location == "bank" and 1 or 0
end

local function SortStacks(a, b)
    if LocationOrder(a) ~= LocationOrder(b) then return LocationOrder(a) < LocationOrder(b) end
    if a.bagOrder ~= b.bagOrder then return (a.bagOrder or 0) < (b.bagOrder or 0) end
    return (a.slot or 0) < (b.slot or 0)
end

-- Per-character counts of one item, current character first, then by count.
-- `chars` maps character name -> { bags = { [key] = n }, bank = { [key] = n }, bankSeen = time }.
-- Returns the list and the total across all of them.
function Data.Breakdown(chars, current, key)
    local list, total = {}, 0
    for name, rec in pairs(chars or {}) do
        local bags = rec.bags and rec.bags[key] or 0
        local bank = rec.bank and rec.bank[key] or 0
        if bags + bank > 0 then
            list[#list + 1] = { name = name, bags = bags, bank = bank, total = bags + bank, current = name == current }
            total = total + bags + bank
        end
    end
    table.sort(list, function(a, b)
        if a.current ~= b.current then return a.current end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return list, total
end

-- "20 (12 bags, 8 bank)", or just "12" when it is all in one place.
function Data.Describe(entry)
    if entry.bank > 0 and entry.bags > 0 then
        return entry.total .. " (" .. entry.bags .. " bags, " .. entry.bank .. " bank)"
    elseif entry.bank > 0 then
        return entry.bank .. " (bank)"
    end
    return tostring(entry.bags)
end

-- Build the rows of the main list.
-- opts:
--   chars    saved records of every character in the group (see Breakdown)
--   current  the logged-in character's name
--   stacks   live stacks the player can act on now: { key, link, count, location = "bags"|"bank", bag, slot, bagOrder }
--   view     "bags": only items in `stacks`; "all": every item anyone in the group has
--   filter   optional lower-case text the item name must contain
--   itemName function(key) -> name or nil, for items not in `stacks`
--   itemLink function(key) -> link or nil
-- Each row: { key, name, link, bags, bank, total, stacks = { ... } } where bags/bank are the
-- current character's counts and total covers every character in the group.
function Data.BuildRows(opts)
    local chars, current = opts.chars or {}, opts.current
    local rowsByKey, rows = {}, {}

    local function Row(key)
        local row = rowsByKey[key]
        if not row then
            row = { key = key, stacks = {} }
            rowsByKey[key] = row
            rows[#rows + 1] = row
        end
        return row
    end

    for _, s in ipairs(opts.stacks or {}) do
        if s.key then
            local row = Row(s.key)
            row.stacks[#row.stacks + 1] = s
            row.link = row.link or s.link
        end
    end

    if opts.view == "all" then
        for _, rec in pairs(chars) do
            for _, where in ipairs({ "bags", "bank" }) do
                for key, n in pairs(rec[where] or {}) do
                    if n > 0 then Row(key) end
                end
            end
        end
    end

    local mine = chars[current] or {}
    local filter = opts.filter ~= "" and opts.filter or nil
    local out = {}
    for _, row in ipairs(rows) do
        row.link = row.link or (opts.itemLink and opts.itemLink(row.key))
        row.name = Data.ItemName(row.link) or (opts.itemName and opts.itemName(row.key)) or ("item:" .. row.key)
        local _, total = Data.Breakdown(chars, current, row.key)
        row.bags = mine.bags and mine.bags[row.key] or 0
        row.bank = mine.bank and mine.bank[row.key] or 0
        -- Live stacks are the truth for this character even if the saved copy lags behind.
        local liveBags, liveBank = 0, 0
        for _, s in ipairs(row.stacks) do
            if s.location == "bank" then liveBank = liveBank + (s.count or 1) else liveBags = liveBags + (s.count or 1) end
        end
        if liveBags > row.bags then total = total + liveBags - row.bags; row.bags = liveBags end
        if liveBank > row.bank then total = total + liveBank - row.bank; row.bank = liveBank end
        row.total = total
        table.sort(row.stacks, SortStacks)
        if not filter or row.name:lower():find(filter, 1, true) then
            out[#out + 1] = row
        end
    end

    table.sort(out, function(a, b)
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return out
end
