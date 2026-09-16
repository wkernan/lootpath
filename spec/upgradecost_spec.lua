-- spec/upgradecost_spec.lua (M3-17b, WKE-588)
-- The crest cost, over the owner's own vendor transcript.
--
-- `spec/fixtures/captures/Lootpath-20260915-162015.lua` is the first
-- `/lootpath capture upgrade` any client has ever produced: the owner standing
-- at a crest vendor with the upgrade window open, 2026-09-15 16:20 local, 128
-- candidates walked, 20,059 ms, `sawSecret = false`. The same file carries the
-- `inventory` and `currencies` snapshots of the same minute, so every figure
-- below - what he wears, what the vendor quoted, what he was carrying - was
-- read from one visit and can be checked against the other two captures line
-- for line.
--
-- Nothing here asserts a number this build produced. The two steps, the 40
-- crests, the 600,000 copper, the 2 Champion Mistcrest and the item levels are
-- all the client's own.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local VENDOR = "spec/fixtures/captures/Lootpath-20260915-162015.lua"
-- The three snapshots of that visit. The `upgrade` capture is the only one in
-- the file; `inventory` 4 and `currencies` 4 are its own flush, 13 seconds
-- after the walk began.
local UPGRADE_SNAPSHOT = 1
local INVENTORY_SNAPSHOT = 4
local CURRENCY_SNAPSHOT = 4

-- What he was wearing on the chest when he walked up to the vendor: the
-- Enigmatic Dreamwatcher's Lunar Raiment, Champion 4/6, item level 302. Its
-- key is the inventory scan's and the vendor walk's, unchanged, which is the
-- whole reason the two join.
local CHEST_KEY = "271531:1555:6652:12836:13440:13690:13698"
local CHEST_ID = 271531

describe("the crest cost, over the owner's vendor transcript of 2026-09-15 16:20", function()
    local ns, world, rows, currencies

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", INVENTORY_SNAPSHOT, VENDOR))
        rows = ns.UpgradeCost.FromSnapshot(R.snapshot("upgrade", UPGRADE_SNAPSHOT, VENDOR))
        currencies = ns.Currencies.Read({ snapshot = R.snapshot("currencies", CURRENCY_SNAPSHOT, VENDOR) })
        assert.is_true(currencies.ok)
    end)

    after_each(function()
        H.unload()
    end)

    -- -----------------------------------------------------------------------
    -- What a step is.

    it("sums the chest's two steps to what the vendor quoted", function()
        local row = rows.byKey[CHEST_KEY]
        assert.is_table(row)
        assert.equal("Enigmatic Dreamwatcher's Lunar Raiment", row.name)
        assert.equal("Champion", row.track)
        assert.equal(4, row.currUpgrade)
        assert.equal(6, row.maxUpgrade)
        assert.equal(302, row.currentLevel)

        -- Three rows came back and two of them are steps: see below.
        assert.equal(2, #row.steps)
        assert.same({ 5, 6 }, { row.steps[1].upgradeLevel, row.steps[2].upgradeLevel })
        -- `itemLevelIncrement` is cumulative from the level the item wears now,
        -- so +3 and +6 off 302 are the 305 and the 308 that `maxItemLevel`
        -- names.
        assert.same({ 305, 308 }, { row.steps[1].itemLevel, row.steps[2].itemLevel })

        local cost = ns.UpgradeCost.Cost(row, 308)
        assert.equal(2, cost.steps)
        assert.equal(600000, cost.money)
        assert.same({ { currencyID = 3444, cost = 40 } }, cost.currencies)
    end)

    -- The watermark row. `upgradeLevelInfos` carries one row for the level the
    -- item is ALREADY at - `cost 0`, `isDiscounted true`,
    -- `discountHighWatermark 302` - and counting it would have said "3 steps"
    -- about two. It is recognised by `upgradeLevel <= currUpgrade` and nothing
    -- else.
    it("never counts the row for the level the item is already at", function()
        local raw = R.snapshot("upgrade", UPGRADE_SNAPSHOT, VENDOR)
        local info
        for _, item in ipairs(raw.data.items) do
            if item.key == CHEST_KEY then
                info = item.info[1]
            end
        end
        assert.is_table(info)
        -- Three rows in the client's own answer, and the first one is the
        -- watermark it has already paid for.
        assert.equal(3, #info.upgradeLevelInfos)
        local watermark = info.upgradeLevelInfos[1]
        assert.equal(4, watermark.upgradeLevel)
        assert.equal(0, watermark.itemLevelIncrement)
        assert.equal(0, watermark.currencyCostsToUpgrade[1].cost)
        assert.is_true(watermark.currencyCostsToUpgrade[1].discountInfo.isDiscounted)
        assert.equal(302, watermark.currencyCostsToUpgrade[1].discountInfo.discountHighWatermark)

        -- And it is in none of the steps.
        for _, step in ipairs(rows.byKey[CHEST_KEY].steps) do
            assert.is_true(step.upgradeLevel > info.currUpgrade)
        end
    end)

    -- A step the plan does not pay for is not in the sum: the road quotes the
    -- price of the level it is promising, never of the whole track.
    it("stops at the level the plan projects", function()
        local row = rows.byKey[CHEST_KEY]
        local one = ns.UpgradeCost.Cost(row, 305)
        assert.equal(1, one.steps)
        assert.equal(300000, one.money)
        assert.same({ { currencyID = 3444, cost = 20 } }, one.currencies)
        -- Below the first step there is nothing to buy at all.
        assert.is_nil(ns.UpgradeCost.Cost(row, 302))
    end)

    -- The discount is not only the watermark ROW. The owner's legs watermark is
    -- 321, above the whole Champion track, so every step of the Miststalker's
    -- Cuisses (Champion 2/6, 295) was quoted at zero crests - money only. A
    -- reader that took "cost 0" to mean "this is the watermark row" would have
    -- thrown all four steps away.
    it("keeps a step the high watermark has made free, and says only the money", function()
        local row
        for _, candidate in pairs(rows.byKey) do
            if candidate.name == "Miststalker's Cuisses" then
                row = candidate
            end
        end
        assert.is_table(row)
        assert.equal(2, row.currUpgrade)
        assert.equal(295, row.currentLevel)
        local cost = ns.UpgradeCost.Cost(row, 308)
        assert.equal(4, cost.steps)
        assert.same({}, cost.currencies)
        assert.equal("4 steps · 120g", ns.Roads.CrestCostText(cost, currencies))
    end)

    -- -----------------------------------------------------------------------
    -- What the clause says.

    it("words the chest's cost in the client's own name, ID and denominations", function()
        local cost = ns.UpgradeCost.Cost(rows.byKey[CHEST_KEY], 308)
        assert.equal("2 steps · 40 Champion Mistcrest · 60g", ns.Roads.CrestCostText(cost, currencies))
        -- The name came out of the currencies read by ID, never from a table in
        -- this addon: an ID that read has never named is said as its number.
        assert.equal("Champion Mistcrest", ns.Roads.CurrencyName(currencies, 3444))
        assert.equal("currency 9999999", ns.Roads.CurrencyName(currencies, 9999999))
    end)

    it("says one step as one step", function()
        local cost = ns.UpgradeCost.Cost(rows.byKey[CHEST_KEY], 305)
        assert.equal("1 step · 20 Champion Mistcrest · 30g", ns.Roads.CrestCostText(cost, currencies))
    end)

    -- -----------------------------------------------------------------------
    -- The holdings clause.

    it("compares what he holds against what the steps cost", function()
        local cost = ns.UpgradeCost.Cost(rows.byKey[CHEST_KEY], 308)
        -- 2 Champion Mistcrest on the client, 40 on the vendor's quote.
        assert.equal(2, ns.Roads.CurrencyHeld(currencies, 3444))
        assert.equal("you hold 2 Champion Mistcrest, 38 short", ns.Roads.CrestHoldingText(currencies, cost))
    end)

    it("says enough when the holding covers the steps", function()
        -- The Adventurer track, where he was carrying 409 of the 3442 crest.
        local row
        for _, candidate in pairs(rows.byKey) do
            if candidate.name == "Circlet of Encroaching Shadow" then
                row = candidate
            end
        end
        assert.is_table(row)
        local cost = ns.UpgradeCost.Cost(row, row.maxItemLevel)
        assert.equal(3442, cost.currencies[1].currencyID)
        assert.is_true(cost.currencies[1].cost < 409)
        assert.equal(
            string.format("you hold 409 Adventurer Mistcrest, enough"),
            ns.Roads.CrestHoldingText(currencies, cost)
        )
    end)

    -- With no cost to hold it against, the clause is what it has always been:
    -- the whole list, in the client's own order, with nothing added up.
    it("keeps the whole list when there is no cost beside it", function()
        assert.equal(
            "you hold 409 Adventurer Mistcrest, 35 Veteran Mistcrest, 2 Champion Mistcrest,"
                .. " 8 Hero Mistcrest, 20 Myth Mistcrest",
            ns.Roads.CrestHoldingText(currencies)
        )
    end)

    -- -----------------------------------------------------------------------
    -- How fresh the answer is.

    it("joins a worn item to its own row by key, at the level it was read at", function()
        local row, freshness = ns.UpgradeCost.Lookup(rows, { key = CHEST_KEY, itemID = CHEST_ID, itemLevel = 302 })
        assert.equal("fresh", freshness)
        assert.equal("Enigmatic Dreamwatcher's Lunar Raiment", row.name)
    end)

    -- Cresting an item replaces its upgrade bonus ID, so the piece on the
    -- character after a trip to the vendor has a key the snapshot has never
    -- seen while its item ID is right there. That is a stale snapshot, and a
    -- stale snapshot is not quoted from.
    it("calls a row stale when the item has been crested since it was read", function()
        local _, byKey = ns.UpgradeCost.Lookup(rows, { key = CHEST_KEY, itemID = CHEST_ID, itemLevel = 305 })
        assert.equal("stale", byKey)
        local row, byID = ns.UpgradeCost.Lookup(rows, {
            key = "271531:1555:6652:12836:13440:13690:99999",
            itemID = CHEST_ID,
            itemLevel = 305,
        })
        assert.equal("stale", byID)
        assert.equal(CHEST_ID, row.itemID)
    end)

    it("has no answer at all about an item the walk never read", function()
        assert.is_nil(ns.UpgradeCost.Lookup(rows, { key = "1:2", itemID = 1, itemLevel = 300 }))
    end)

    -- -----------------------------------------------------------------------
    -- What `CanUpgradeItem` is worth, which is why it is recorded and not
    -- obeyed (M3-17b). The issue's reading of the owner's own leggings does not
    -- survive the transcript beside the inventory snapshot of the same minute:
    -- he crested them the rest of the way after the 14:27 vault capture, so at
    -- 16:20 they were at 321 - the top of the Hero track, as the Seed of
    -- Radiant Hope's own rows show - and a refusal there is simply right.
    --
    -- What is left is the second copy, in his bags at 295, refused just the
    -- same; and about THAT one the transcript can say nothing, because the
    -- gate is what stopped the read. Which is the argument for taking the gate
    -- out: a fact recorded beside an answer can be understood later, and a fact
    -- that decided whether to look cannot.
    it("records the refusal and, under the old gate, could not explain it", function()
        local raw = R.snapshot("upgrade", UPGRADE_SNAPSHOT, VENDOR)
        local refused = {}
        for _, item in ipairs(raw.data.items) do
            if item.itemID == 271527 then
                refused[#refused + 1] = item
            end
        end
        assert.equal(2, #refused)
        for _, item in ipairs(refused) do
            assert.is_false(item.canUpgrade[1])
            -- Nothing was read, because the gate came first.
            assert.is_nil(item.info)
        end

        -- The worn one was at the cap of its track, which the client itself
        -- says through another Hero item: 308 at 2/6, 321 at 6/6.
        local inventory = ns.Inventory.Scan()
        local worn
        for _, record in ipairs(inventory.records) do
            if record.itemID == 271527 and record.location == "equipped" then
                worn = record
            end
        end
        assert.equal(321, worn.itemLevel)
        local hero
        for _, candidate in pairs(rows.byKey) do
            if candidate.name == "Seed of Radiant Hope" then
                hero = candidate
            end
        end
        assert.equal("Hero", hero.track)
        assert.equal(321, hero.maxItemLevel)
        assert.equal(321, hero.steps[#hero.steps].itemLevel)
    end)

    -- -----------------------------------------------------------------------
    -- The money.

    it("writes copper in the client's own denominations, dropping what is zero", function()
        assert.equal("60g", ns.UpgradeCost.MoneyText(600000))
        assert.equal("1g 23s 45c", ns.UpgradeCost.MoneyText(12345))
        assert.equal("45c", ns.UpgradeCost.MoneyText(45))
        assert.is_nil(ns.UpgradeCost.MoneyText(0))
        assert.is_nil(ns.UpgradeCost.MoneyText(nil))
    end)
end)

-- ---------------------------------------------------------------------------
-- The road itself: the Upgrade row for what he wears, with the vendor's quote
-- on it.
--
-- The plan's projected level is the one thing here that is not the client's, so
-- it is stated as plainly as possible: a `maxed` document carrying exactly the
-- chest's own key at the 308 the vendor's own top step lands on. That is the
-- shape `ns.QEImport` stores and `Roads.MaxedAnswer` reads, and nothing else
-- about it is claimed to be a real export.
describe("the Upgrade road for what you wear, with the vendor's quote on it", function()
    local ns, world, inputs, inventory

    local function maxedVerdict(key, level)
        return {
            exportedAt = "2026-09-15T21:20:00Z",
            contentType = "Dungeon",
            scenario = "maxed",
            topSet = { items = { [key] = { key = key, level = level, slot = "Chest" } } },
            alternatives = {},
        }
    end

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", INVENTORY_SNAPSHOT, VENDOR))
        inventory = ns.Inventory.Scan()
        assert.is_true(inventory.ok, inventory.reason)
        local currencies = ns.Currencies.Read({ snapshot = R.snapshot("currencies", CURRENCY_SNAPSHOT, VENDOR) })
        inputs = {
            verdicts = { { verdict = maxedVerdict(CHEST_KEY, 308), scenario = "maxed" } },
            highlightedScenario = "maxed",
            inventory = inventory,
            currencies = currencies,
            upgradeRows = ns.UpgradeCost.FromSnapshot(R.snapshot("upgrade", UPGRADE_SNAPSHOT, VENDOR)),
            now = 1789507215,
        }
    end)

    after_each(function()
        H.unload()
    end)

    local function crestRoad(slot)
        for _, group in pairs(ns.Roads.ForSlot(slot, inputs).groups) do
            for _, road in ipairs(group) do
                if road.kind == ns.Roads.KIND_CREST then
                    return road
                end
            end
        end
        return nil
    end

    it("puts the cost and the comparison on the chest's Upgrade row", function()
        local road = crestRoad("Chest")
        assert.is_table(road)
        assert.equal(308, road.arrivesAt)
        assert.equal("2 steps · 40 Champion Mistcrest · 60g", road.steps[1].text)
        assert.equal("you hold 2 Champion Mistcrest, 38 short", road.steps[2].text)
    end)

    -- R-2a's rule: a cost clause answers "what will this cost me" beside the
    -- counts the reader can see, and a tooltip about one item is not that
    -- screen. Both clauses are marked `cost`, so the row keeps them and the
    -- tooltip drops them.
    it("keeps the quote on the row and off the tooltip", function()
        local row = ns.UpgradeMapPanel.RoadRow(crestRoad("Chest"))
        assert.same({
            "2 steps · 40 Champion Mistcrest · 60g",
            "you hold 2 Champion Mistcrest, 38 short",
        }, row.costFacts)
        assert.is_truthy(row.factsText:find("40 Champion Mistcrest", 1, true))
        assert.is_nil(row.tooltipFactsText and row.tooltipFactsText:find("40 Champion Mistcrest", 1, true))
    end)

    -- The head he wears was never in the vendor's window, so there is no answer
    -- about it - and the clause names the one thing that would produce one.
    it("keeps the unread phrase, with its cure, for an item the walk never read", function()
        local road = crestRoad("Head")
        assert.is_table(road)
        assert.equal(
            "crest type and cost not read - visit a crest vendor and /lootpath capture upgrade",
            ns.Roads.CREST_NOT_READ
        )
        assert.equal(ns.Roads.CREST_NOT_READ, road.steps[1].text)
        -- And with nothing to compare against, the holdings clause is the whole
        -- list again.
        assert.is_truthy(road.steps[2].text:find("409 Adventurer Mistcrest", 1, true))
    end)

    -- The same words for the snapshot that has been overtaken: he crested the
    -- chest after this walk, so the row the walk left behind is about a piece
    -- that no longer exists, and it is not quoted from.
    it("refuses to quote a snapshot the item has been crested past", function()
        for _, record in ipairs(inventory.records) do
            if record.key == CHEST_KEY then
                record.itemLevel = 305
            end
        end
        inputs.verdicts = { { verdict = maxedVerdict(CHEST_KEY, 308), scenario = "maxed" } }
        local road = crestRoad("Chest")
        assert.is_table(road)
        assert.equal(ns.Roads.CREST_NOT_READ, road.steps[1].text)
    end)
end)
