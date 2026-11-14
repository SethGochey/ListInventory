-- Plain Lua 5.1 tests for ListInventory/Data.lua. Run from the repository root:
--   luajit tests/Data_test.lua
local ns = {}
local chunk = assert(loadfile("Data.lua"))
chunk("ListInventory", ns)
local Data = ns.Data

local failures, passed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failures = failures + 1
        print("FAIL: " .. name .. (detail and (" - " .. tostring(detail)) or ""))
    end
end

local function eq(name, got, want)
    check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

local LINEN = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"
local WOOL = "|cffffffff|Hitem:2592::::::::60:::::|h[Wool Cloth]|h|r"
local MONKEY = "|cff1eff00|Hitem:9800::::::-15:0:60:::::|h[Bandit Cloak of the Monkey]|h|r"
local EAGLE = "|cff1eff00|Hitem:9800::::::-17:0:60:::::|h[Bandit Cloak of the Eagle]|h|r"
local OLD_STYLE = "|cffffffff|Hitem:2589:0:0:0:0:0:0:0|h[Linen Cloth]|h|r"

-- ItemKey
eq("plain item key", Data.ItemKey(LINEN), "2589")
eq("old-style link key", Data.ItemKey(OLD_STYLE), "2589")
eq("suffix kept apart (monkey)", Data.ItemKey(MONKEY), "9800:-15")
eq("suffix kept apart (eagle)", Data.ItemKey(EAGLE), "9800:-17")
eq("not a link", Data.ItemKey("hello"), nil)
eq("nil link", Data.ItemKey(nil), nil)
eq("item id from key", Data.KeyItemID("9800:-15"), 9800)
eq("item id from plain key", Data.KeyItemID("2589"), 2589)

-- ItemName
eq("name from link", Data.ItemName(LINEN), "Linen Cloth")
eq("name from suffixed link", Data.ItemName(EAGLE), "Bandit Cloak of the Eagle")

-- GroupKey
eq("group key", Data.GroupKey("Whitemane", "normal", "Horde"), "Whitemane|normal|Horde")
eq("group key default ruleset", Data.GroupKey("Whitemane", nil, "Horde"), "Whitemane|normal|Horde")

-- CountStacks
local counts = Data.CountStacks({ { key = "2589", count = 20 }, { key = "2589", count = 7 }, { key = "2592", count = 3 }, { count = 5 } })
eq("count stacks sums", counts["2589"], 27)
eq("count stacks other", counts["2592"], 3)

-- Breakdown and Describe
local chars = {
    Main = { bags = { ["2589"] = 27 }, bank = { ["2589"] = 40 } },
    Alt = { bags = { ["2589"] = 100, ["2592"] = 5 }, bank = {} },
    Bank = { bags = {}, bank = { ["2589"] = 200 } },
    Empty = { bags = {}, bank = {} },
}
local list, total = Data.Breakdown(chars, "Main", "2589")
eq("breakdown total", total, 367)
eq("breakdown size skips characters with none", #list, 3)
eq("breakdown current first", list[1].name, "Main")
eq("breakdown then by count", list[2].name, "Bank")
eq("breakdown last", list[3].name, "Alt")
eq("describe bags and bank", Data.Describe(list[1]), "67 (27 bags, 40 bank)")
eq("describe bank only", Data.Describe(list[2]), "200 (bank)")
eq("describe bags only", Data.Describe(list[3]), "100")
local _, none = Data.Breakdown(chars, "Main", "9999")
eq("breakdown of unknown item", none, 0)

-- BuildRows
local stacks = {
    { key = "2589", link = LINEN, count = 20, location = "bags", bag = 1, slot = 4, bagOrder = 2 },
    { key = "2589", link = LINEN, count = 7, location = "bags", bag = 0, slot = 9, bagOrder = 1 },
    { key = "9800:-15", link = MONKEY, count = 1, location = "bags", bag = 0, slot = 1, bagOrder = 1 },
    { key = "9800:-17", link = EAGLE, count = 1, location = "bags", bag = 0, slot = 2, bagOrder = 1 },
}
local links = { ["2592"] = WOOL, ["2589"] = LINEN }
local function itemLink(key) return links[key] end

local rows = Data.BuildRows({ chars = chars, current = "Main", stacks = stacks, view = "bags", itemLink = itemLink })
eq("bags view rows", #rows, 3)
eq("sorted by name 1", rows[1].name, "Bandit Cloak of the Eagle")
eq("sorted by name 2", rows[2].name, "Bandit Cloak of the Monkey")
eq("sorted by name 3", rows[3].name, "Linen Cloth")
local linen = rows[3]
eq("linen in this character's bags", linen.bags, 27)
eq("linen in this character's bank", linen.bank, 40)
eq("linen total across characters", linen.total, 367)
eq("linen stacks", #linen.stacks, 2)
eq("stacks in bag order", linen.stacks[1].bag, 0)

local all = Data.BuildRows({ chars = chars, current = "Main", stacks = stacks, view = "all", itemLink = itemLink })
eq("all view adds items only alts have", #all, 4)
local wool
for _, r in ipairs(all) do if r.key == "2592" then wool = r end end
check("wool row present", wool ~= nil)
if wool then
    eq("wool name from saved link", wool.name, "Wool Cloth")
    eq("wool not in this character's bags", wool.bags, 0)
    eq("wool total", wool.total, 5)
    eq("wool has no stacks to act on", #wool.stacks, 0)
end

local filtered = Data.BuildRows({ chars = chars, current = "Main", stacks = stacks, view = "all", filter = "cloth", itemLink = itemLink })
eq("filter by name", #filtered, 2)

-- Live stacks newer than the saved record still count.
local stale = { Main = { bags = { ["2589"] = 5 }, bank = {} } }
local live = Data.BuildRows({ chars = stale, current = "Main", stacks = stacks, view = "bags", itemLink = itemLink })
for _, r in ipairs(live) do
    if r.key == "2589" then
        eq("live bags beat stale saved count", r.bags, 27)
        eq("total follows live count", r.total, 27)
    end
end

-- Bank stacks (bank window open) sort after bag stacks.
local withBank = {
    { key = "2589", link = LINEN, count = 20, location = "bank", bag = -1, slot = 1, bagOrder = 1 },
    { key = "2589", link = LINEN, count = 7, location = "bags", bag = 2, slot = 3, bagOrder = 3 },
}
local bankRows = Data.BuildRows({ chars = chars, current = "Main", stacks = withBank, view = "bags" })
eq("bag stacks before bank stacks", bankRows[1].stacks[1].location, "bags")

-- Unknown item with no link gets a placeholder name and still sorts.
local unknown = Data.BuildRows({ chars = { Main = { bags = { ["123"] = 1 }, bank = {} } }, current = "Main", view = "all" })
eq("placeholder name", unknown[1].name, "item:123")

print(passed .. " passed, " .. failures .. " failed")
os.exit(failures == 0 and 0 or 1)
