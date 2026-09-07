-- spec/match_spec.lua (M2-2, WKE-520)
-- The join is exercised over the two committed pieces of reality: the owner's
-- 2026-09-05 inventory transcript replayed through the stub, and QE Live's own
-- 2026-09-06 Top Gear export parsed from its JSON text. The synthetic cases at
-- the end are for the shapes those two fixtures do not contain yet - a bonus-ID
-- mismatch, a vault item, a closed bank.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local REAL_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"
local SAMPLE_EXPORT = "spec/fixtures/qe/sample-handbuilt-v1.json"

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function verdictFrom(ns, path)
    local parsed = ns.QEImport.Parse(readFile(path))
    assert(parsed.ok, parsed.reason)
    return parsed.verdict
end

local function scanFrom(ns, world, bankOpen)
    R.inventory(world, R.snapshot("inventory", 1))
    world.bankOpen = bankOpen and true or false
    local scan = ns.Inventory.Scan()
    assert(scan.ok, scan.reason)
    return scan
end

local function rowsFor(match, slot)
    return match.bySlot[slot] or {}
end

-- A minimal record in the shape ns.Inventory.Record produces, for the cases the
-- transcript cannot supply.
local function record(fields)
    local bonusIDs = fields.bonusIDs or {}
    return {
        key = fields.key
            or (bonusIDs[1] and (fields.itemID .. ":" .. table.concat(bonusIDs, ":")) or tostring(fields.itemID)),
        itemID = fields.itemID,
        link = fields.link or ("|Hitem:" .. fields.itemID .. "|h[fixture]|h"),
        itemLevel = fields.itemLevel,
        bonusIDs = bonusIDs,
        slot = fields.slot,
        equipLoc = fields.equipLoc,
        location = fields.location or "bag",
        bag = fields.bag,
        slotIndex = fields.slotIndex,
        name = fields.name,
        quality = fields.quality,
    }
end

local function verdict(items, extra)
    local map, order = {}, {}
    for _, item in ipairs(items) do
        item.key = item.key or tostring(item.itemID)
        item.count = 1
        map[item.key] = item
        order[#order + 1] = item.key
    end
    local out = { topSet = { score = 1, stats = {}, items = map, order = order }, alternatives = {}, vault = {} }
    for k, v in pairs(extra or {}) do
        out[k] = v
    end
    return out
end

describe("Match.Build refusals", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("passes a combat refusal through instead of matching against nothing", function()
        local result = ns.Match.Build({ ok = false, reason = "combat" }, verdict({}))
        assert.is_false(result.ok)
        assert.equal("combat", result.reason)
    end)

    it("refuses when there is no inventory at all", function()
        assert.is_false(ns.Match.Build(nil, verdict({})).ok)
        assert.is_false(ns.Match.Build("not a scan", verdict({})).ok)
    end)

    it("refuses when nothing has been imported", function()
        local result = ns.Match.Build({ ok = true, records = {} }, nil)
        assert.is_false(result.ok)
        assert.is_truthy(result.reason:find("no QE Live verdict", 1, true))
    end)
end)

describe("Match.Build over the 2026-09-05 transcript and the genuine QE Live export", function()
    local ns, world, match

    before_each(function()
        ns, world = H.load()
        local scan = scanFrom(ns, world, true)
        match = ns.Match.Build(scan, verdictFrom(ns, REAL_EXPORT))
        assert.is_true(match.ok)
    end)

    after_each(function()
        H.unload()
    end)

    it("makes one row per item in the export's top set", function()
        -- The export carries 15 items and the character wears 15 pieces in
        -- exactly those slots, so nothing is left over.
        assert.equal(15, #match.rows)
        assert.equal(0, match.counts.no_verdict)
        assert.equal(
            15,
            match.counts.equipped_is_best + match.counts.swap + match.counts.best_not_owned + match.counts.no_verdict
        )
    end)

    it("reads the head off the character and the neck out of the bags", function()
        -- Head 271528 carries the same seven bonus IDs in the export and in the
        -- transcript, so it joins by key with no fallback.
        local head = rowsFor(match, "Head")[1]
        assert.equal("equipped_is_best", head.status)
        assert.equal(ns.Match.MATCHED_BY_KEY, head.matchedBy)
        assert.equal("271528:1561:6652:12838:13439:13692:13696:13698", head.best.key)
        assert.equal("equipped", head.best.location)

        -- The export wants neck 272229; the character is wearing 272228 and the
        -- other one is in a bag.
        local neck = rowsFor(match, "Neck")[1]
        assert.equal("swap", neck.status)
        assert.equal(272229, neck.best.itemID)
        assert.equal("bag", neck.best.location)
        assert.equal(272228, neck.equipped.itemID)
        assert.equal(2, neck.dstSlot)
        assert.is_true(ns.Match.IsSwap(neck))
    end)

    it("says which items the scan cannot find", function()
        local feet = rowsFor(match, "Feet")[1]
        assert.equal("best_not_owned", feet.status)
        assert.is_nil(feet.best)
        assert.equal(251153, feet.verdictItem.itemID)
        -- The bank was open for this scan, so the reason is the plain one.
        assert.is_truthy(feet.reason:find("did not find it", 1, true))
        assert.is_false(ns.Match.IsSwap(feet))
    end)

    it("gives each of a matched pair its own row and its own equipment slot", function()
        local fingers = rowsFor(match, "Finger")
        assert.equal(2, #fingers)
        -- Ring 151311 is worn in slot 11 and stays there; ring 259912 comes out
        -- of a bag and targets slot 12, the ring QE Live did not keep.
        local kept, swapped
        for _, row in ipairs(fingers) do
            if row.status == "equipped_is_best" then
                kept = row
            else
                swapped = row
            end
        end
        assert.is_table(kept)
        assert.equal(151311, kept.best.itemID)
        assert.equal(11, kept.dstSlot)
        assert.equal("swap", swapped.status)
        assert.equal(259912, swapped.best.itemID)
        assert.equal(251136, swapped.equipped.itemID)
        assert.equal(12, swapped.dstSlot)

        local trinkets = rowsFor(match, "Trinket")
        assert.equal(2, #trinkets)
        assert.equal("swap", trinkets[1].status)
        assert.equal("swap", trinkets[2].status)
        assert.equal(13, trinkets[1].dstSlot)
        assert.equal(14, trinkets[2].dstSlot)
        assert.are_not.equal(trinkets[1].best.key, trinkets[2].best.key)
    end)

    it("orders rows the way a character sheet reads and never invents a row", function()
        local seen = {}
        local previous = 0
        for _, row in ipairs(match.rows) do
            local rank = ns.Match.SLOT_RANK[row.slot]
            assert.is_number(rank)
            assert.is_true(rank >= previous)
            previous = rank
            seen[row.slot] = true
            assert.is_string(row.status)
            assert.is_truthy(row.verdictItem or row.equipped)
        end
        assert.is_true(seen["Head"] and seen["2H Weapon"])
    end)

    it("carries the export's own header through to the result", function()
        assert.equal("Raid", match.contentType)
        assert.equal("Restoration Druid", match.spec)
        assert.equal("2026-09-06T21:14:24.465Z", match.exportedAt)
        assert.is_true(match.bankAvailable)
        assert.same({}, match.fallbacks)
    end)

    it("reports the bank as closed and says so in the not-owned reason", function()
        local closed = ns.Match.Build(scanFrom(ns, world, false), verdictFrom(ns, REAL_EXPORT))
        assert.is_false(closed.bankAvailable)
        local feet = rowsFor(closed, "Feet")[1]
        assert.equal("best_not_owned", feet.status)
        assert.is_truthy(feet.reason:find("bank is closed", 1, true))
    end)
end)

describe("Match.Build over the hand-built sample", function()
    local ns, world, match

    before_each(function()
        ns, world = H.load()
        match = ns.Match.Build(scanFrom(ns, world, true), verdictFrom(ns, SAMPLE_EXPORT))
        assert.is_true(match.ok)
    end)

    after_each(function()
        H.unload()
    end)

    it("makes a no_verdict row for every slot the export does not name", function()
        -- The sample's top set covers 7 slots (Head, Neck, Chest, Finger x2,
        -- Trinket, 2H Weapon); the character wears 15 pieces.
        assert.equal(7, #verdictFrom(ns, SAMPLE_EXPORT).topSet.order)
        assert.is_true(match.counts.no_verdict > 0)
        local shoulder = rowsFor(match, "Shoulder")[1]
        assert.equal("no_verdict", shoulder.status)
        assert.is_table(shoulder.equipped)
        assert.is_nil(shoulder.verdictItem)
        assert.is_false(ns.Match.IsSwap(shoulder))
    end)

    it("reaches every status at least once across the two fixtures", function()
        local real = ns.Match.Build(scanFrom(ns, world, true), verdictFrom(ns, REAL_EXPORT))
        local total = {}
        for status, count in pairs(real.counts) do
            total[status] = (total[status] or 0) + count
        end
        for status, count in pairs(match.counts) do
            total[status] = (total[status] or 0) + count
        end
        for _, status in ipairs({ "equipped_is_best", "swap", "best_not_owned", "no_verdict" }) do
            assert.is_true((total[status] or 0) > 0, status .. " was never reached")
        end
    end)

    it("calls a vault item the sample owns nowhere a vault option, not a missing item", function()
        -- The sample's Chest (251216) IS in the transcript, so the vault reason
        -- needs an item the scan cannot see: the sample's second differential
        -- carries an isVault Trinket that the top set does not.
        local vaultItem
        for _, item in pairs(verdictFrom(ns, SAMPLE_EXPORT).vault) do
            vaultItem = vaultItem or item
        end
        assert.is_table(vaultItem)
        local built = ns.Match.Build(
            { ok = true, records = {}, bankAvailable = true },
            verdict({
                {
                    itemID = vaultItem.itemID,
                    key = vaultItem.key,
                    slot = "Trinket",
                    level = vaultItem.level,
                    bonusIDs = vaultItem.bonusIDs,
                    isVault = true,
                },
            })
        )
        local row = rowsFor(built, "Trinket")[1]
        assert.equal("best_not_owned", row.status)
        assert.is_truthy(row.reason:find("Great Vault", 1, true))
    end)
end)

describe("Match.Build item identity", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("falls back to itemID and item level when the bonus IDs differ, and never silently", function()
        local inventory = {
            ok = true,
            bankAvailable = true,
            records = {
                record({ itemID = 271528, bonusIDs = { 10, 20 }, itemLevel = 308, slot = "Head", location = "bag" }),
            },
        }
        local built = ns.Match.Build(
            inventory,
            verdict({
                { itemID = 271528, key = "271528:30:40", slot = "Head", level = 308, bonusIDs = { 30, 40 } },
            })
        )
        local row = built.bySlot["Head"][1]
        assert.equal("swap", row.status)
        assert.equal(ns.Match.MATCHED_BY_ID_LEVEL, row.matchedBy)
        assert.equal(1, #built.fallbacks)
        assert.is_truthy(built.fallbacks[1]:find("30:40", 1, true))
        assert.is_truthy(built.fallbacks[1]:find("10:20", 1, true))
        -- Visible, not just returned: the chat frame carries it too.
        assert.is_truthy(world.output():find("matched by itemID and item level", 1, true))
    end)

    it("never accepts an itemID-only match when the item levels differ", function()
        local inventory = {
            ok = true,
            bankAvailable = true,
            records = {
                record({ itemID = 271528, bonusIDs = { 10 }, itemLevel = 291, slot = "Head", location = "bag" }),
            },
        }
        local built = ns.Match.Build(
            inventory,
            verdict({ { itemID = 271528, key = "271528:30", slot = "Head", level = 308, bonusIDs = { 30 } } })
        )
        assert.equal("best_not_owned", built.bySlot["Head"][1].status)
        assert.same({}, built.fallbacks)
    end)

    it("claims each copy once, so a pair of identical rings needs two of them", function()
        local one = record({ itemID = 500, bonusIDs = { 1 }, itemLevel = 300, slot = "Finger", location = "bag" })
        local built = ns.Match.Build(
            { ok = true, bankAvailable = true, records = { one } },
            verdict({
                { itemID = 500, key = "500:1", slot = "Finger", level = 300, bonusIDs = { 1 } },
                { itemID = 500, key = "500:1", slot = "Finger", level = 300, bonusIDs = { 1 } },
            })
        )
        -- One copy owned, two wanted: the second row cannot borrow the first.
        local fingers = built.bySlot["Finger"]
        assert.equal(2, #fingers)
        assert.equal("swap", fingers[1].status)
        assert.equal("best_not_owned", fingers[2].status)
    end)

    it("prefers the copy already on the character over an identical one in a bag", function()
        local worn = record({
            itemID = 500,
            bonusIDs = { 1 },
            itemLevel = 300,
            slot = "Finger",
            location = "equipped",
            slotIndex = 11,
        })
        local spare = record({ itemID = 500, bonusIDs = { 1 }, itemLevel = 300, slot = "Finger", location = "bag" })
        local built = ns.Match.Build(
            { ok = true, bankAvailable = true, records = { spare, worn } },
            verdict({ { itemID = 500, key = "500:1", slot = "Finger", level = 300, bonusIDs = { 1 } } })
        )
        assert.equal("equipped_is_best", built.bySlot["Finger"][1].status)
        assert.equal("equipped", built.bySlot["Finger"][1].best.location)
    end)

    it("leaves dstSlot nil when the slot is empty, so the client chooses", function()
        local built = ns.Match.Build({
            ok = true,
            bankAvailable = true,
            records = {
                record({ itemID = 500, bonusIDs = { 1 }, itemLevel = 300, slot = "Head", location = "bag" }),
            },
        }, verdict({ { itemID = 500, key = "500:1", slot = "Head", level = 300, bonusIDs = { 1 } } }))
        local row = built.bySlot["Head"][1]
        assert.equal("swap", row.status)
        assert.is_nil(row.dstSlot)
        assert.is_nil(row.equipped)
    end)
end)
