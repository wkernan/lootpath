local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
local S = require("spec.helpers.serialize")

local EXPECTED_DIR = "spec/fixtures/expected/"
local EXPECTED_OPEN = EXPECTED_DIR .. "inventory-20260905-133449-bank-open.lua"
local EXPECTED_CLOSED = EXPECTED_DIR .. "inventory-20260905-133449-bank-closed.lua"

-- Counts the gear the raw snapshot carries, independently of the module: an
-- item is gear when its GetItemInfoInstant equipLoc is in the slot table.
local function rawGearCounts(ns, snapshot)
    local counts = { equipped = 0, bag = 0, bank = 0 }
    for _, e in ipairs(snapshot.data.equipped) do
        local loc = e.item and e.item.instant and e.item.instant[4]
        if ns.Inventory.SlotForEquipLoc(loc) then
            counts.equipped = counts.equipped + 1
        end
    end
    for _, bag in ipairs(snapshot.data.bags) do
        for _, it in pairs(bag.items) do
            local loc = it.item and it.item.instant and it.item.instant[4]
            if ns.Inventory.SlotForEquipLoc(loc) then
                local where = bag.bagIndex >= 6 and "bank" or "bag"
                counts[where] = counts[where] + 1
            end
        end
    end
    return counts
end

-- First gear item in the owned bags (0..5). The 2026-09-05 backpack holds no
-- gear at all, so the search covers every owned bag.
local function findGearInBags(ns, world)
    for bag = 0, 5 do
        local entry = world.bags[bag]
        for slot, it in pairs(entry and entry.items or {}) do
            local raw = world.items[it.link]
            if raw and raw.instant and ns.Inventory.SlotForEquipLoc(raw.instant[4]) then
                return bag, slot, it
            end
        end
    end
    return nil
end

local function countBy(records, field)
    local out = {}
    for _, r in ipairs(records) do
        out[r[field]] = (out[r[field]] or 0) + 1
    end
    return out
end

describe("ParseItemLink", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("parses every link in the transcript to the itemID and bonus count the client reported", function()
        local links = R.links(R.snapshot("inventory", 1))
        assert.is_true(#links > 100)
        local nonItems = 0
        for _, entry in ipairs(links) do
            local parsed = ns.ParseItemLink(entry.link)
            if not entry.link:find("|Hitem:", 1, true) then
                -- Bag slots can hold non-items: the transcript has a `|Hkeystone:` link.
                nonItems = nonItems + 1
                assert.is_nil(parsed, entry.link)
                parsed = nil
            end
            if parsed == nil and entry.link:find("|Hitem:", 1, true) then
                error("item link did not parse: " .. entry.link)
            end
        end
        assert.is_true(nonItems >= 1)
        for _, entry in ipairs(links) do
            local parsed = ns.ParseItemLink(entry.link)
            if parsed == nil then
                assert.is_falsy(entry.link:find("|Hitem:", 1, true))
                break
            end
            assert.equal(entry.item.instant[1], parsed.itemID, entry.link)
            -- An empty count field (Hearthstone: `...::86:::::::`) means zero bonus IDs.
            local declared = tonumber(entry.link:match("|Hitem:" .. string.rep("[^:]*:", 12) .. "(%d*)")) or 0
            assert.equal(declared, parsed.numBonusIDs, entry.link)
            assert.equal(declared, #parsed.bonusIDs, entry.link)
            for i = 2, #parsed.bonusIDs do
                assert.is_true(parsed.bonusIDs[i - 1] <= parsed.bonusIDs[i], entry.link)
            end
            assert.equal(ns.ItemKey(parsed.itemID, parsed.bonusIDs), parsed.key)
        end
    end)

    it("reads the fields of a real 12.1 link", function()
        local p = ns.ParseItemLink(
            "|cnIQ4:|Hitem:271528::::::::90:104::23:7:6652:13439:13696:12838:13692:13698:1561:1:64:251140:::::"
                .. "|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
        )
        assert.equal(271528, p.itemID)
        assert.is_nil(p.enchantID)
        assert.same({}, p.gems)
        assert.equal(90, p.linkLevel)
        assert.equal(104, p.specID)
        assert.equal(23, p.context)
        assert.equal(7, p.numBonusIDs)
        assert.same({ 1561, 6652, 12838, 13439, 13692, 13696, 13698 }, p.bonusIDs)
        assert.same({ { type = 64, value = 251140 } }, p.modifiers)
        assert.equal("271528:1561:6652:12838:13439:13692:13696:13698", p.key)
    end)

    -- Links assembled field by field so the colon count cannot be miscounted:
    -- itemID, enchant, gem1-4, suffix, uniqueID, linkLevel, specID, flags, context, numBonusIDs, ...
    local function link(fields)
        return "|cnIQ4:|Hitem:" .. table.concat(fields, ":") .. "|h[x]|h|r"
    end

    it("reads enchant and gem fields when present", function()
        local enchanted =
            ns.ParseItemLink(link({ 266430, 7960, "", "", "", "", "", "", 90, 104, "", 42, 2, 13577, 12790 }))
        assert.equal(7960, enchanted.enchantID)
        assert.same({}, enchanted.gems)
        assert.same({ 12790, 13577 }, enchanted.bonusIDs)
        local gemmed = ns.ParseItemLink(link({ 251166, "", 240982, "", "", "", "", "", 90, 104, "", 23, 0 }))
        assert.is_nil(gemmed.enchantID)
        assert.same({ 240982 }, gemmed.gems)
        assert.equal(0, gemmed.numBonusIDs)
        assert.equal("251166", gemmed.key)
    end)

    it("parses the transcript's own enchanted and gemmed links", function()
        local enchanted =
            ns.ParseItemLink("|cnIQ4:|Hitem:266430:7960:::::::90:104::42:3:13577:12790:12667:1:28:4240:::::|h[x]|h|r")
        assert.equal(7960, enchanted.enchantID)
        assert.same({ 12667, 12790, 13577 }, enchanted.bonusIDs)
        assert.same({ { type = 28, value = 4240 } }, enchanted.modifiers)
        local gemmed = ns.ParseItemLink(
            "|cnIQ4:|Hitem:251166::240982::::::90:104::23:6:13439:6652:13534:13577:12699:12790:1:28:3025:::::|h[x]|h|r"
        )
        assert.same({ 240982 }, gemmed.gems)
        assert.equal(6, gemmed.numBonusIDs)
        assert.same({ 6652, 12699, 12790, 13439, 13534, 13577 }, gemmed.bonusIDs)
    end)

    it("parses a crafted item whose link carries the crafter GUID and atlas markup", function()
        local p = ns.ParseItemLink(
            "|cnIQ2:|Hitem:222842::::::::90:104::13:3:10827:10830:13625:3:28:2734:38:5:40:2377::::Player-69-0F82625A:"
                .. "|h[Weavercloth Fishing Cap |A:Professions-ChatIcon-Quality-Tier2:17:15::1|a]|h|r"
        )
        assert.is_table(p)
        assert.equal(222842, p.itemID)
        assert.same({ 10827, 10830, 13625 }, p.bonusIDs)
        assert.equal(3, #p.modifiers)
        assert.equal("222842:10827:10830:13625", p.key)
    end)

    it("accepts a bare item string and rejects anything else", function()
        assert.equal(12345, ns.ParseItemLink("item:12345::::::::80:105::13:2:1:2").itemID)
        assert.is_nil(ns.ParseItemLink(nil))
        assert.is_nil(ns.ParseItemLink("|cff0070dd|Hspell:774|h[Rejuvenation]|h|r"))
        assert.is_nil(ns.ParseItemLink("not a link"))
        assert.is_nil(ns.ParseItemLink("|Hitem:0::|h[x]|h"))
    end)

    it("is order-independent in the key it derives", function()
        local a = ns.ParseItemLink("item:1:::::::::::0:2:5:9")
        local b = ns.ParseItemLink("item:1:::::::::::0:2:9:5")
        assert.equal(a.key, b.key)
        assert.equal("1:5:9", a.key)
    end)
end)

describe("Inventory", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    describe("slot map", function()
        it("uses QE Live's slot vocabulary", function()
            local map = ns.Inventory.SLOT_BY_EQUIPLOC
            assert.equal("Head", map.INVTYPE_HEAD)
            assert.equal("Back", map.INVTYPE_CLOAK)
            assert.equal("Hands", map.INVTYPE_HAND)
            assert.equal("Finger", map.INVTYPE_FINGER)
            assert.equal("2H Weapon", map.INVTYPE_2HWEAPON)
            assert.equal("Offhand", map.INVTYPE_HOLDABLE)
            assert.equal("Shield", map.INVTYPE_SHIELD)
        end)

        it("treats non-gear as no slot", function()
            for _, loc in ipairs({
                "INVTYPE_NON_EQUIP_IGNORE",
                "INVTYPE_BAG",
                "INVTYPE_BODY",
                "INVTYPE_TABARD",
                "INVTYPE_PROFESSION_TOOL",
            }) do
                assert.is_nil(ns.Inventory.SlotForEquipLoc(loc), loc)
            end
            assert.is_nil(ns.Inventory.SlotForEquipLoc(nil))
        end)

        it("covers every gear equipLoc the transcript contains", function()
            local seen = {}
            for _, entry in ipairs(R.links(R.snapshot("inventory", 1))) do
                local loc = entry.item and entry.item.instant and entry.item.instant[4]
                if loc then
                    seen[loc] = true
                end
            end
            for _, loc in ipairs({
                "INVTYPE_HEAD",
                "INVTYPE_TRINKET",
                "INVTYPE_2HWEAPON",
                "INVTYPE_SHIELD",
                "INVTYPE_HOLDABLE",
                "INVTYPE_ROBE",
                "INVTYPE_WEAPONMAINHAND",
                "INVTYPE_RANGEDRIGHT",
            }) do
                assert.is_true(seen[loc], loc .. " missing from transcript")
                assert.is_string(ns.Inventory.SlotForEquipLoc(loc), loc)
            end
        end)
    end)

    describe("Scan over the transcript, bank open", function()
        local snapshot, result

        before_each(function()
            snapshot = R.snapshot("inventory", 1)
            R.inventory(world, snapshot)
            result = ns.Inventory:Scan()
        end)

        it("reports the bank available and no secrets", function()
            assert.is_true(result.ok)
            assert.is_true(result.bankAvailable)
            assert.equal(0, result.secretsSeen)
        end)

        it("returns one record per gear item the client reported, by location", function()
            assert.same(rawGearCounts(ns, snapshot), countBy(result.records, "location"))
        end)

        it("fills every field from the client's own returns", function()
            for _, r in ipairs(result.records) do
                local raw = world.items[r.link]
                assert.is_table(raw, r.link)
                assert.equal(raw.detailed[1], r.itemLevel, r.link)
                assert.equal(raw.info[1], r.name, r.link)
                assert.equal(raw.info[3], r.quality, r.link)
                assert.equal(raw.instant[1], r.itemID, r.link)
                assert.equal(raw.instant[4], r.equipLoc, r.link)
                assert.equal(ns.Inventory.SlotForEquipLoc(raw.instant[4]), r.slot, r.link)
                assert.equal(ns.ItemKey(r.itemID, r.bonusIDs), r.key, r.link)
                assert.is_number(r.slotIndex)
                if r.location == "equipped" then
                    assert.is_nil(r.bag)
                    assert.equal(world.equipped[r.slotIndex].link, r.link)
                else
                    assert.is_number(r.bag)
                    assert.equal(world.bags[r.bag].items[r.slotIndex].link, r.link)
                    assert.is_true((r.location == "bank") == (r.bag >= 6), r.link)
                end
            end
        end)

        it("orders equipped, then bags, then bank tabs ascending", function()
            local rank = { equipped = 1, bag = 2, bank = 3 }
            for i = 2, #result.records do
                local a, b = result.records[i - 1], result.records[i]
                local ra, rb = rank[a.location], rank[b.location]
                assert.is_true(ra <= rb)
                if ra == rb and a.bag and b.bag then
                    assert.is_true(a.bag <= b.bag)
                end
            end
        end)

        it("skips non-gear even though the client returned it", function()
            local nonGear = 0
            for _, entry in ipairs(R.links(snapshot)) do
                if not ns.Inventory.SlotForEquipLoc(entry.item.instant[4]) then
                    nonGear = nonGear + 1
                end
            end
            assert.is_true(nonGear > 100)
            for _, r in ipairs(result.records) do
                assert.is_string(r.slot)
            end
        end)

        it("matches the committed expected fixture", function()
            if os.getenv("LOOTPATH_WRITE_EXPECTED") then
                S.write(
                    EXPECTED_OPEN,
                    result,
                    "-- Generated by spec/inventory_spec.lua over the 2026-09-05 transcript, bank open.\n"
                )
            end
            local expected = dofile(EXPECTED_OPEN)
            assert.same(expected, result)
        end)
    end)

    describe("Scan over the transcript, bank closed", function()
        local result

        before_each(function()
            R.inventory(world, R.snapshot("inventory", 2))
            result = ns.Inventory:Scan()
        end)

        it("reports the bank unavailable and returns no bank records", function()
            assert.is_true(result.ok)
            assert.is_false(result.bankAvailable)
            assert.is_nil(countBy(result.records, "location").bank)
        end)

        it("returns the same equipped and bag records as the open scan", function()
            local closed = countBy(result.records, "location")
            R.inventory(world, R.snapshot("inventory", 1))
            local open = countBy(ns.Inventory:Scan().records, "location")
            assert.equal(open.equipped, closed.equipped)
            assert.equal(open.bag, closed.bag)
        end)

        it("matches the committed expected fixture", function()
            if os.getenv("LOOTPATH_WRITE_EXPECTED") then
                S.write(
                    EXPECTED_CLOSED,
                    result,
                    "-- Generated by spec/inventory_spec.lua over the 2026-09-05 transcript, bank closed.\n"
                )
            end
            assert.same(dofile(EXPECTED_CLOSED), result)
        end)
    end)

    describe("guards", function()
        it("refuses to scan in combat", function()
            R.inventory(world, R.snapshot("inventory", 1))
            world.inCombat = true
            assert.same({ ok = false, reason = "combat" }, ns.Inventory:Scan())
        end)

        it("drops a secret link and counts it", function()
            R.inventory(world, R.snapshot("inventory", 2))
            local before = #ns.Inventory:Scan().records
            world.equipped[1] = { link = world.secret("helm"), id = 1 }
            local result = ns.Inventory:Scan()
            assert.equal(before - 1, #result.records)
            assert.equal(1, result.secretsSeen)
        end)

        it("drops a secret container table and counts it", function()
            R.inventory(world, R.snapshot("inventory", 2))
            local before = #ns.Inventory:Scan().records
            local gearBag, slot = findGearInBags(ns, world)
            assert.is_number(gearBag, "no gear in the owned bags to poison")
            local poisoned = world.secretTable("container")
            _G.C_Container.GetContainerItemInfo = function(bag, index)
                if bag == gearBag and index == slot then
                    return poisoned
                end
                local b = world.bags[bag]
                local it = b and b.items[index]
                return it and it.info or nil
            end
            _G.C_Container.GetContainerItemLink = function(bag, index)
                if bag == gearBag and index == slot then
                    return world.secret("link")
                end
                local b = world.bags[bag]
                local it = b and b.items[index]
                return it and it.link or nil
            end
            local result = ns.Inventory:Scan()
            assert.equal(before - 1, #result.records)
            assert.equal(2, result.secretsSeen)
        end)

        it("does not silently call the bank when CanViewBank is missing", function()
            R.inventory(world, R.snapshot("inventory", 1))
            _G.C_Bank = nil
            local result = ns.Inventory:Scan()
            assert.is_false(result.bankAvailable)
            assert.is_nil(countBy(result.records, "location").bank)
        end)

        it("falls back to the container quality when GetItemInfo is not cached", function()
            R.inventory(world, R.snapshot("inventory", 2))
            local gearBag, slot, entry = findGearInBags(ns, world)
            assert.is_number(gearBag, "no gear in the owned bags")
            world.items[entry.link].info = nil
            local record =
                ns.Inventory.Record(entry.link, { location = "bag", bag = gearBag, slotIndex = slot }, entry.info)
            assert.equal(entry.info.quality, record.quality)
            assert.is_nil(record.name)
        end)
    end)
end)
