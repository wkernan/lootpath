-- Lootpath/Modules/UpgradeCost.lua (M3-17b, WKE-588)
-- What the crest vendor said an item you own would cost to take further, read
-- back out of the `upgrade` capture and added up. Nothing here is estimated:
-- every figure is a number the client handed over in
-- `C_ItemUpgrade.GetItemUpgradeItemInfo()`, and an item the capture never put
-- in the vendor's window has no answer at all rather than a guessed one.
--
-- **Why a capture and not a read.** `GetItemUpgradeItemInfo` answers for ONE
-- item - whichever is in the open upgrade vendor's window - and there is no
-- call that asks about an item without putting it there. So the cost of the
-- thing you are wearing is not readable from a panel; it is readable at a
-- vendor, once, and this file is what a panel reads afterwards.
--
-- **What is a step, measured rather than assumed** (the owner's transcript,
-- `spec/fixtures/captures/Lootpath-20260915-162015.lua`, 2026-09-15 16:20):
-- `upgradeLevelInfos` carries one row for the level the item is ALREADY at as
-- well as one per level above it. That first row reads `cost 0`,
-- `isDiscounted = true` and `discountHighWatermark 302` - it is the watermark
-- the character has already paid for, not something to buy - and it is
-- recognised by the only thing that tells it apart without reading a discount:
-- `upgradeLevel <= currUpgrade`. Counting it would have said "3 steps" about
-- two.
--
-- `itemLevelIncrement` is cumulative FROM the current level, not per row: the
-- Enigmatic Dreamwatcher's Lunar Raiment sat at Champion 4/6 and item level
-- 302, its level-5 row said `+3` and its level-6 row `+6`, and 302 + 6 is the
-- 308 its `maxItemLevel` names. So a step's item level is
-- `currentLevel + itemLevelIncrement`, and that is how the steps a plan's
-- projected level actually pays for are chosen.
--
-- **`CanUpgradeItem` is recorded, never obeyed**, and what the transcript can
-- say about it is less than WKE-588 supposed. It refused both copies of the
-- Enigmatic Dreamwatcher's Leggings while taking 20 other items. The WORN copy
-- was at item level 321 in the `inventory` snapshot of the same minute - he
-- had crested it the rest of the way after the 14:27 vault capture the issue
-- was written from - and 321 is the top of the Hero track, as the Seed of
-- Radiant Hope's own rows say (Hero 2/6 at 308, its 6/6 row at 321). A refusal
-- there is simply right. The copy in his bags at 295 is not explained by
-- anything in the file, and CANNOT be, because the gate is what stopped the
-- read.
--
-- That is the argument for taking the gate out rather than against it: an
-- answer recorded beside a read can be understood later, and an answer that
-- decided whether to read cannot. So the gate here is the info's own
-- `itemUpgradeable` and `currUpgrade < maxUpgrade`, and `CanUpgradeItem` sits
-- on the row as a fact.
--
-- Nothing in this file is a healer value, and nothing in it is arithmetic on
-- one: it adds up crests and copper the vendor quoted.

local _, ns = ...

ns.UpgradeCost = {}
local UpgradeCost = ns.UpgradeCost

UpgradeCost.CAPTURE = "upgrade"

-- The client's own denomination letters. `GOLD_AMOUNT_SYMBOL` and its two
-- siblings are the strings Blizzard's own `GetMoneyString` uses in colourblind
-- mode (FormattingUtil.lua, read under `.luals/`); `GetMoneyString` itself is
-- not called because in the normal mode it returns texture escapes, and a road
-- step is plain text that `/lootpath status` prints and `spec/voice_spec.lua`
-- reads. The fallbacks are the same three letters for a headless run with no
-- FrameXML loaded.
local function symbol(name, fallback)
    local value = rawget(_G, name)
    return type(value) == "string" and value ~= "" and value or fallback
end

-- Copper -> "60g", "60g 50s", "7s 20c", in the client's own letters and the
-- client's own denominations, dropping the parts that are zero exactly as
-- `GetMoneyString` does. nil for nothing to pay.
function UpgradeCost.MoneyText(copper)
    copper = tonumber(copper)
    if not copper or copper <= 0 then
        return nil
    end
    local perSilver = tonumber(rawget(_G, "COPPER_PER_SILVER")) or 100
    local perGold = tonumber(rawget(_G, "SILVER_PER_GOLD")) or 100
    local gold = math.floor(copper / (perSilver * perGold))
    local silver = math.floor((copper - gold * perSilver * perGold) / perSilver)
    local rest = copper % perSilver
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. symbol("GOLD_AMOUNT_SYMBOL", "g")
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. symbol("SILVER_AMOUNT_SYMBOL", "s")
    end
    if rest > 0 then
        parts[#parts + 1] = rest .. symbol("COPPER_AMOUNT_SYMBOL", "c")
    end
    return table.concat(parts, " ")
end

-- One `ItemUpgradeItemInfo` as it was stored -> the rows above the level the
-- item is already at, in the client's own order. The watermark row and
-- anything at or below `currUpgrade` is dropped here and nowhere else, so
-- there is one place that decides what a step is.
local function stepsOf(info, currentLevel)
    local out = {}
    local curr = tonumber(info.currUpgrade)
    for _, level in ipairs(type(info.upgradeLevelInfos) == "table" and info.upgradeLevelInfos or {}) do
        local upgradeLevel = tonumber(type(level) == "table" and level.upgradeLevel or nil)
        if upgradeLevel and curr and upgradeLevel > curr then
            local increment = tonumber(level.itemLevelIncrement)
            local currencies = {}
            local quoted = type(level.currencyCostsToUpgrade) == "table" and level.currencyCostsToUpgrade or {}
            for _, cost in ipairs(quoted) do
                local currencyID = tonumber(type(cost) == "table" and cost.currencyID or nil)
                local amount = tonumber(type(cost) == "table" and cost.cost or nil)
                if currencyID and amount and amount > 0 then
                    currencies[#currencies + 1] = { currencyID = currencyID, cost = amount }
                end
            end
            out[#out + 1] = {
                upgradeLevel = upgradeLevel,
                -- Cumulative from the level the item wears now, so this is the
                -- level the item ARRIVES at when this step is bought.
                itemLevel = (currentLevel and increment) and (currentLevel + increment) or nil,
                moneyCost = tonumber(level.moneyCost) or 0,
                currencies = currencies,
            }
        end
    end
    return out
end

-- One stored item record -> the row a road reads, or nil when the capture
-- never got an answer about it. The item's own identity comes off the link the
-- capture recorded, so a row joins to an inventory record by exactly the key
-- every other join in this addon uses.
local function rowOf(item)
    if type(item) ~= "table" then
        return nil
    end
    local info = type(item.info) == "table" and type(item.info[1]) == "table" and item.info[1] or nil
    if not info then
        return nil
    end
    local currentLevel = type(item.currentLevel) == "table" and tonumber(item.currentLevel[1]) or nil
    -- Kept as the boolean it was, false included: `false or nil` would have
    -- turned "the vendor refused this" into "nobody asked".
    local canUpgrade
    local answered = type(item.canUpgrade) == "table" and item.canUpgrade[1] or nil
    if answered == true or answered == false then
        canUpgrade = answered
    end
    return {
        key = item.key,
        itemID = tonumber(item.itemID),
        link = item.link,
        name = type(info.name) == "string" and info.name or nil,
        -- Recorded beside the answer, never used as one (see the header).
        canUpgrade = canUpgrade,
        itemUpgradeable = info.itemUpgradeable == true,
        currUpgrade = tonumber(info.currUpgrade),
        maxUpgrade = tonumber(info.maxUpgrade),
        -- The client's own word for the track: "Adventurer", "Champion",
        -- "Hero". Never typed in here, and never shown without it.
        track = type(info.customUpgradeString) == "string" and info.customUpgradeString or nil,
        currentLevel = currentLevel,
        maxItemLevel = tonumber(info.maxItemLevel),
        steps = stepsOf(info, currentLevel),
    }
end

-- FromSnapshot(snapshot) -> { ok = true, capturedAt, byKey, byItemID } for a
-- stored `upgrade` snapshot, or nil for anything that is not one.
--
-- `byItemID` holds the FIRST row for each item ID and is how a stale snapshot
-- is recognised: cresting an item replaces its upgrade bonus ID, so the item
-- the player is wearing today has a key the snapshot has never seen while its
-- item ID is right there.
function UpgradeCost.FromSnapshot(snapshot)
    local data = type(snapshot) == "table" and snapshot.data or nil
    if type(data) ~= "table" or type(data.items) ~= "table" then
        return nil
    end
    local byKey, byItemID = {}, {}
    for _, item in ipairs(data.items) do
        local row = rowOf(item)
        if row then
            if row.key and byKey[row.key] == nil then
                byKey[row.key] = row
            end
            if row.itemID and byItemID[row.itemID] == nil then
                byItemID[row.itemID] = row
            end
        end
    end
    return {
        ok = true,
        capturedAt = tonumber(snapshot.capturedAt),
        capturedAtLocal = snapshot.capturedAtLocal,
        byKey = byKey,
        byItemID = byItemID,
    }
end

-- The newest stored `upgrade` snapshot, or nil when none has been taken. Same
-- shape as `ns.Currencies.NewestSnapshot`, and for the same reason: the
-- capture list is the only place a snapshot lives.
function UpgradeCost.NewestSnapshot(db)
    db = db or ns.db
    local captures = db and db.global and db.global.captures or nil
    local list = type(captures) == "table" and captures[UpgradeCost.CAPTURE] or nil
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    return list[#list]
end

-- Read(opts) -> the newest snapshot's rows, or nil when the owner has never
-- stood at a crest vendor with this addon loaded. `opts.snapshot` reads one
-- particular snapshot instead, which is what the tests over the committed
-- transcript do.
function UpgradeCost.Read(opts)
    opts = opts or {}
    local snapshot = opts.snapshot
    if snapshot == nil then
        snapshot = UpgradeCost.NewestSnapshot(opts.db)
    end
    if snapshot == nil then
        return nil
    end
    return UpgradeCost.FromSnapshot(snapshot)
end

-- Which answer a held item has, and how much to trust it.
--
--   "fresh"  - the snapshot has this exact item, at the level it is at now.
--   "stale"  - the snapshot knows the item ID and disagrees about the level,
--              which is what happens after the item is crested: cresting
--              replaces the upgrade bonus ID, so the key changes too.
--   nil      - nothing about this item was ever read.
--
-- `itemLevel` is what the caller believes the item wears now (the inventory
-- scan's own figure). With none to compare against, a key match is fresh and
-- an item-ID match is not claimed to be either.
function UpgradeCost.Lookup(rows, record)
    if type(rows) ~= "table" or type(record) ~= "table" then
        return nil
    end
    local itemLevel = tonumber(record.itemLevel)
    local row = record.key and rows.byKey and rows.byKey[record.key] or nil
    if row then
        if itemLevel and row.currentLevel and row.currentLevel ~= itemLevel then
            return row, "stale"
        end
        return row, "fresh"
    end
    local itemID = tonumber(record.itemID)
    row = itemID and rows.byItemID and rows.byItemID[itemID] or nil
    if row then
        return row, "stale"
    end
    return nil
end

-- Cost(row, arrivesAt) -> { steps, money, currencies = { { currencyID, cost } } }
-- for every step from `currUpgrade + 1` up to and including the one that lands
-- at `arrivesAt`, or nil when there is nothing to buy.
--
-- A step whose item level the snapshot cannot state is not counted and stops
-- the sum: a partial total said as a whole one is worse than no number.
function UpgradeCost.Cost(row, arrivesAt)
    if type(row) ~= "table" or type(row.steps) ~= "table" or #row.steps == 0 then
        return nil
    end
    arrivesAt = tonumber(arrivesAt)
    local order, byID = {}, {}
    local steps, money = 0, 0
    for _, step in ipairs(row.steps) do
        if arrivesAt then
            if not step.itemLevel or step.itemLevel > arrivesAt then
                break
            end
        end
        steps = steps + 1
        money = money + (step.moneyCost or 0)
        for _, cost in ipairs(step.currencies) do
            if byID[cost.currencyID] == nil then
                byID[cost.currencyID] = 0
                order[#order + 1] = cost.currencyID
            end
            byID[cost.currencyID] = byID[cost.currencyID] + cost.cost
        end
    end
    if steps == 0 then
        return nil
    end
    local currencies = {}
    for _, currencyID in ipairs(order) do
        currencies[#currencies + 1] = { currencyID = currencyID, cost = byID[currencyID] }
    end
    return { steps = steps, money = money, currencies = currencies, track = row.track }
end
