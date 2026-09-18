-- spec/roads_spec.lua (R-1, WKE-562)
-- The road model and the plan sentence over the owner's own week.
--
-- Every figure asserted below was read out of a committed file, never from the
-- design canvas and never from memory. The inputs are one week:
--
--   * `spec/fixtures/captures/Lootpath-20260908-124527.lua` - inventory
--     snapshot 7 (15 equipped / 32 bags / 0 bank, the scan the companion's
--     profile of the 09-09 run was built from) and vault snapshot 9 (the four
--     rewards that week: the Lantern, the Worldroot, the Spaulders, the Graft).
--   * `qe-droptimizer-Hotornot-hdaldwpeakpb.json` - the `thisWeek` Dungeon
--     document of the 2026-09-09 19:22 run, over exactly that profile.
--   * the five Mythic+ Upgrade Finder documents of the 2026-09-08 22:47 run.
--   * the 2026-09-06 20:09 cold journal walk (478 drops, previewed at
--     keystone 10).
--   * the 2026-09-08 23:04 currency transcript for the crest counts. That
--     transcript predates the by-ID probe and genuinely does not know the
--     Catalyst charge (M3-11, WKE-546), so the charge is driven through the
--     stub's `currencyByID` the way `spec/currencies_spec.lua` drives it, with
--     the 1 of 8 the owner read off his own tooltip on 2026-09-08. There is
--     still no committed transcript carrying the by-ID probe (ARCHITECTURE 11).
--
-- Three premises of the issue were checked against those files before a line
-- was written, and one of them was wrong; see the "premise" block at the end.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local CAPTURE = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
local CURRENCIES = "spec/fixtures/captures/Lootpath-20260908-230426.lua"
local PROFILE_SNAPSHOT = 7
local VAULT_SNAPSHOT = 9
local CURRENCY_SNAPSHOT = 2

local THIS_WEEK_DUNGEON = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json"
local MAXED_DUNGEON = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json"
local AS_OFFERED_RAID = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"

-- The five Mythic+ key levels of the 2026-09-08 22:47 companion run, with the
-- level the companion stamped on each (the JSON does not carry it).
local UPGRADE_DOCUMENTS = {
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lrxljklscrjr.json", keyLevel = 2 },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-jnjnmzftoppb.json", keyLevel = 4 },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-zmtnpejwfewe.json", keyLevel = 6 },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lttldhvkiqlr.json", keyLevel = 8 },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-wyharestkdyr.json", keyLevel = 10 },
}

-- Read off the owner's own Catalyst tooltip on 2026-09-08 and recorded in
-- Lootpath/Modules/Currencies.lua's own comment: currencyID 3465,
-- "Venomblight Manaflux", 1 of 8.
local CATALYST = {
    name = "Venomblight Manaflux",
    currencyID = 3465,
    isHeader = false,
    quantity = 1,
    maxQuantity = 8,
}

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

describe("Roads over the owner's week of 2026-09-08", function()
    local ns, world, inputs

    local function upgradeDocuments()
        local documents = {}
        for _, entry in ipairs(UPGRADE_DOCUMENTS) do
            local parsed = ns.UFImport.Parse(readFile(entry.file))
            assert.is_true(parsed.ok, parsed.reason)
            documents[#documents + 1] = { verdict = parsed.verdict, keyLevel = entry.keyLevel }
        end
        return documents
    end

    local function document(path, scenario, boxes)
        local parsed = ns.QEImport.Parse(readFile(path))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = scenario
        parsed.verdict.qeSettings = boxes
        return parsed.verdict
    end

    local function thisWeek()
        return document(THIS_WEEK_DUNGEON, "thisWeek", {
            autoUpgradeVault = true,
            autoUpgradeAll = false,
            autoCatalyze = true,
        })
    end

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
        R.vault(world, R.snapshot("vault", VAULT_SNAPSHOT, CAPTURE))
        world.currencyByID = { [3465] = CATALYST }

        local inventory = ns.Inventory.Scan()
        assert.is_true(inventory.ok, inventory.reason)
        local vault = ns.Vault.Options()
        assert.is_true(vault.ok, vault.reason)
        -- The crest counts come out of the owner's own transcript; the charge
        -- comes out of the by-ID probe above, which that transcript predates.
        local currencies = ns.Currencies.Read({ snapshot = R.snapshot("currencies", CURRENCY_SNAPSHOT, CURRENCIES) })
        assert.is_true(currencies.ok)
        currencies.byID[3465] = CATALYST
        currencies = ns.Currencies.Read({ snapshot = R.snapshot("currencies", CURRENCY_SNAPSHOT, CURRENCIES) })
        currencies.catalyst = CATALYST
        currencies.catalystCharges = CATALYST.quantity
        currencies.catalystMax = CATALYST.maxQuantity

        local snapshot = R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ)
        local sources, summary = ns.Journal:Build({ snapshot = snapshot })
        local ids, seen = {}, {}
        for _, list in pairs(sources) do
            for _, entry in ipairs(list) do
                if entry.difficultyID and not seen[entry.difficultyID] then
                    seen[entry.difficultyID] = true
                    ids[#ids + 1] = entry.difficultyID
                end
            end
        end
        table.sort(ids)

        inputs = {
            verdicts = { { verdict = thisWeek(), scenario = "thisWeek" } },
            highlightedScenario = "thisWeek",
            ufDocuments = upgradeDocuments(),
            inventory = inventory,
            vault = vault,
            currencies = currencies,
            journal = { sources = sources, summary = summary },
            difficultyLabels = ns.UpgradeMapPanel.DifficultyLabels(ids, summary.previewMythicPlusLevel),
            now = 1788800000,
        }
    end)

    after_each(function()
        H.unload()
    end)

    local function group(slot, name)
        return ns.Roads.ForSlot(slot, inputs).groups[name]
    end

    -- -----------------------------------------------------------------------
    -- The shoulder slot: the Catalyst road is the pick, the vault Spaulders sit
    -- behind it, and both want the one charge.

    it("makes the Catalyst conversion of the bag Spaulders the shoulder pick", function()
        local pick = group("Shoulder", ns.Roads.GROUP_SET)[1]
        assert.equal(ns.Roads.KIND_CATALYST, pick.kind)
        assert.is_true(pick.planPick)
        -- The item shown is the one the owner can point at in his bag, not the
        -- tier clone's item ID.
        assert.equal(277782, pick.item.itemID)
        assert.equal("Venom-Cursed Lynx's Spaulders", pick.item.name)
        assert.equal(295, pick.arrivesAt)
        -- What it becomes is his clone: the tier shoulder, set 2057.
        assert.equal(271526, pick.becomes.itemID)
        assert.equal(2057, pick.becomes.setId)
        assert.equal("in your best set", pick.rating.badge)
        assert.equal("this week's picks", pick.plan)
        assert.equal("do: Catalyst it · charge 1 held, 8 max", pick.todo)
        -- No verb: the Catalyst is not something the addon may open.
        assert.is_nil(pick.verb)
    end)

    -- The measurement the whole shoulder board is built on: differential 7 of
    -- this document is `scorePercent 1.729166724018797`, and it is "take the
    -- vault Spaulders instead, catalyzed and upgraded to 321, and keep the 308
    -- weapon you wear".
    it("puts the vault Spaulders behind it at his own 1.73%, naming what it costs", function()
        local road = group("Shoulder", ns.Roads.GROUP_SET)[2]
        assert.equal(ns.Roads.KIND_VAULT, road.kind)
        assert.is_false(road.planPick)
        assert.equal(251146, road.item.itemID)
        assert.equal("Scavenger's Spaulders", road.item.name)
        assert.equal(308, road.arrivesAt)
        assert.equal(1.729166724018797, road.rating.scorePercent)
        assert.equal("1.73% behind", road.rating.badge)
        -- The referent is read off the differential's OWN item list: it also
        -- names the 2H Weapon, so taking this road costs the vault weapon.
        assert.equal("taking the vault weapon instead", road.rating.referent)
        assert.equal(321, road.rating.level)
        -- It is his clone of the option, so it spends a charge too.
        assert.equal(271526, road.becomes.itemID)
        assert.is_true(road.catalyzed)
        assert.equal(ns.Roads.VERB_SHOW_IN_VAULT, road.verb)
        -- No imperative: the road is rated behind the plan, and the shoulder
        -- plan's own pick is the Catalyst road above, not the piece worn, so
        -- there is nothing this row may tell anyone to do (R-3a, WKE-570).
        assert.is_nil(road.todo)
    end)

    it("names the two roads that want the one charge, on both sides", function()
        local set = group("Shoulder", ns.Roads.GROUP_SET)
        assert.equal("the same charge as the vault Spaulders road", set[1].rivalText)
        assert.equal("the same charge as the Catalyst road: one of these, not both", set[2].rivalText)
        assert.equal(1, set[1].resource.held)
        assert.equal(8, set[1].resource.max)
        assert.equal("Venomblight Manaflux", set[1].resource.name)
    end)

    -- Red for the assertion above: with two charges held, nothing is exclusive
    -- and neither road mentions the other.
    it("says nothing about a rival when the client says there are charges enough", function()
        inputs.currencies.catalystCharges = 2
        local set = group("Shoulder", ns.Roads.GROUP_SET)
        assert.is_nil(set[1].rivalText)
        assert.is_nil(set[2].rivalText)
    end)

    -- The Mythic+ row: the client previews the Spaulders at 305 at the owner's
    -- key, and his +6 document (settings.dungeon index 4) is the one that
    -- carries that item at that level - 0%, with 321 at +0.382% in the same
    -- document. No other key level's number reaches this row.
    it("values the Mythic+ Spaulders at the level the client previews", function()
        local road
        for _, entry in ipairs(group("Shoulder", ns.Roads.GROUP_ITEM)) do
            if entry.item.itemID == 251146 then
                road = entry
            end
        end
        assert.is_table(road)
        assert.equal(ns.Roads.KIND_DROP, road.kind)
        assert.equal(ns.Roads.TAG_MYTHIC_PLUS, road.tag)
        assert.equal(305, road.arrivesAt)
        assert.equal(0, road.rating.percent)
        assert.equal(6, road.rating.keyLevel)
        -- A zero is not a direction, and a zero at the level it arrives is
        -- exactly what the third phrase means.
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, road.rating.badge)
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, road.phrase)
        assert.equal(1, #road.rating.alsoAt)
        assert.equal("upgraded", road.rating.alsoAt[1].label)
        assert.equal(321, road.rating.alsoAt[1].level)
        assert.equal(0.382, road.rating.alsoAt[1].percent)
        assert.equal("+0.38%", road.rating.alsoAt[1].badge)
        assert.equal(6, road.rating.alsoAt[1].keyLevel)
        assert.equal("The Hoardmonger", road.source.encounterName)
        assert.equal("Den of Nalorakk", road.source.instanceName)
        assert.equal("Mythic+ 10", road.source.difficultyLabel)
        -- "not in your best set" is a rating, and it points behind, so the
        -- row carries no "do: run the key" (R-3a, WKE-570). The shoulder plan
        -- keeps nothing worn, so nothing replaces it.
        assert.is_nil(road.todo)
        assert.equal(ns.Roads.VERB_SHOW_RUN, road.verb)
    end)

    -- -----------------------------------------------------------------------
    -- The weapon slot: the vault's own Worldroot, rated at the level the plan
    -- upgraded it to, and five roads behind it.

    it("makes the vault Worldroot the weapon pick, at the level the rating assumed", function()
        local pick = group("2H Weapon", ns.Roads.GROUP_SET)[1]
        assert.equal(ns.Roads.KIND_VAULT, pick.kind)
        assert.is_true(pick.planPick)
        assert.equal(251935, pick.item.itemID)
        assert.equal("Lightgrasp Worldroot", pick.item.name)
        -- The client hands it over at 305; the rating assumed 321, so the badge
        -- says which level it is true at.
        assert.equal(305, pick.arrivesAt)
        assert.equal(321, pick.rating.level)
        assert.equal("in your best set at 321", pick.rating.badge)
        assert.equal("do: take it · rated at 321, crests not readable", pick.todo)
        assert.equal("open now", pick.openNow)
        assert.equal(ns.Roads.VERB_SHOW_IN_VAULT, pick.verb)
    end)

    -- Red for the level on that badge: put his own level back to the one the
    -- vault hands the item over at, and the badge is the plain sentence and the
    -- imperative loses its condition, because 305 is 305.
    it("drops the level from the badge when the rating assumed none", function()
        local verdict = inputs.verdicts[1].verdict
        for _, item in pairs(verdict.topSet.items) do
            if item.isVault then
                item.level = 305
            end
        end
        local pick = group("2H Weapon", ns.Roads.GROUP_SET)[1]
        assert.equal(ns.Roads.KIND_VAULT, pick.kind)
        assert.equal("in your best set", pick.rating.badge)
        assert.equal("do: take it", pick.todo)
        -- And the sentence stops telling the player to spend crests on it,
        -- because the rating no longer assumes any were.
        assert.equal(
            "Grab the Worldroot from the vault."
                .. " Catalyst the Lynx shoulders in your bag."
                .. " Skip the vault shoulders.",
            ns.Roads.PlanSentence(inputs).sentence
        )
    end)

    -- A list of seven is where a sentence gives away that a machine wrote it.
    -- This one is a real pairing and not a contrived one: the 2026-09-06 export
    -- is a plan for the character as it stood that evening, and against the
    -- 09-08 scan seven of the items it names are sitting in the owner's bags.
    it("writes a list of items the way a person writes one", function()
        local asOffered = document(AS_OFFERED_RAID, "asOffered", {
            autoUpgradeVault = false,
            autoUpgradeAll = false,
            autoCatalyze = false,
        })
        local plan = ns.Roads.PlanSentence({
            verdicts = { { verdict = asOffered, scenario = "asOffered" } },
            highlightedScenario = "asOffered",
            inventory = inputs.inventory,
        })
        assert.equal(
            "Put on the Talisman, the Miststalker shoulders, the Lynx cloak, the Falconer belt,"
                .. " the Band ring, the Seeker trinket and the Chalice.",
            plan.sentence
        )
    end)

    it("keeps the worn weapon as its own road, with what keeping it costs", function()
        local keep = group("2H Weapon", ns.Roads.GROUP_SET)[2]
        assert.equal(ns.Roads.KIND_KEEP, keep.kind)
        assert.equal(ns.Roads.TAG_KEEP, keep.tag)
        assert.equal(308, keep.arrivesAt)
        -- Differential 7 again, read from the weapon's side: keeping the 308
        -- weapon means taking the catalyzed shoulders instead.
        assert.equal("1.73% behind", keep.rating.badge)
        assert.equal("taking the catalyzed shoulders instead", keep.rating.referent)
        assert.equal("nothing to do", keep.todo)
        assert.is_nil(keep.verb)
    end)

    it("rates the raid and the key at the levels the walk previews", function()
        local raid, key
        for _, road in ipairs(group("2H Weapon", ns.Roads.GROUP_ITEM)) do
            if road.item.itemID == 268205 then
                raid = road
            elseif road.item.itemID == 159636 then
                key = road
            end
        end
        assert.is_table(raid)
        assert.equal(ns.Roads.TAG_RAID, raid.tag)
        assert.equal(324, raid.arrivesAt)
        assert.equal(3.07, raid.rating.percent)
        assert.equal("+3.07%", raid.rating.badge)
        assert.equal("Vashnik the Malignant", raid.source.encounterName)
        assert.equal("The Venomous Abyss", raid.source.instanceName)
        assert.equal("Mythic raid", raid.source.difficultyLabel)
        assert.equal(1, #raid.rating.alsoAt)
        assert.equal("at its cap", raid.rating.alsoAt[1].label)
        assert.equal(334, raid.rating.alsoAt[1].level)
        assert.equal("+4.70%", raid.rating.alsoAt[1].badge)
        assert.equal("do: raid it · tick when it drops", raid.todo)

        assert.is_table(key)
        assert.equal(ns.Roads.TAG_MYTHIC_PLUS, key.tag)
        assert.equal(305, key.arrivesAt)
        assert.equal("+0.32%", key.rating.badge)
        assert.equal("Adderis and Aspix", key.source.encounterName)
        assert.equal("Temple of Sethraliss", key.source.instanceName)
        assert.equal("upgraded", key.rating.alsoAt[1].label)
        assert.equal(321, key.rating.alsoAt[1].level)
        assert.equal("+2.62%", key.rating.alsoAt[1].badge)
    end)

    it("carries the Crafted and Delves rows the export already holds", function()
        local craft, delve
        for _, road in ipairs(group("2H Weapon", ns.Roads.GROUP_ITEM)) do
            craft = craft or (road.kind == ns.Roads.KIND_CRAFT and road or nil)
            delve = delve or (road.kind == ns.Roads.KIND_DELVE and road or nil)
        end
        assert.is_table(craft)
        assert.equal(ns.Roads.TAG_CRAFTED, craft.tag)
        assert.equal(331, craft.arrivesAt)
        assert.equal("+3.63%", craft.rating.badge)
        -- What the number assumed, from the export's own settings (R-4): the
        -- stats a crafting order would have to ask for. A fact, not a step.
        assert.equal("the rating assumes Crit / Haste", craft.steps[1].text)
        assert.is_true(craft.steps[1].fact)
        assert.equal(ns.Roads.CRAFT_NOT_READ, craft.steps[2].text)
        assert.same({ "the rating assumes Crit / Haste", ns.Roads.CRAFT_NOT_READ }, ns.Roads.Facts(craft))
        assert.equal("do: get the spark, then order it", craft.todo)
        -- The key level is not what values a crafted item, so no row names one
        -- (ns.UFImport.SourceRows; ARCHITECTURE.md 9, 2026-09-13).
        assert.is_nil(craft.rating.keyLevel)

        assert.is_table(delve)
        assert.equal(ns.Roads.TAG_DELVES, delve.tag)
        assert.equal(321, delve.arrivesAt)
        assert.equal("+2.17%", delve.rating.badge)
        -- No delve step exists until a delve capture does, and a row with no
        -- step to name carries no imperative either.
        assert.equal(ns.Roads.DELVE_NOT_READ, delve.steps[1].text)
        assert.is_nil(delve.todo)
        assert.is_nil(delve.verb)
        assert.is_nil(delve.rating.keyLevel)
        -- A delve row is not crafted, so it assumes no stats line.
        assert.same({ ns.Roads.DELVE_NOT_READ }, ns.Roads.Facts(delve))
    end)

    it("puts upgrading what you wear in the no-rating group, cost unread", function()
        local road = group("2H Weapon", ns.Roads.GROUP_NONE)[1]
        assert.equal(ns.Roads.KIND_CREST, road.kind)
        assert.equal("Lightgrasp Worldroot", road.item.name)
        assert.equal(308, road.arrivesAt)
        assert.equal(ns.Roads.PHRASE_NO_RATING, road.phrase)
        assert.equal(ns.Roads.CREST_NOT_READ, road.steps[1].text)
        -- The crest counts are the client's own, off the owner's transcript.
        assert.equal(
            "you hold 356 Adventurer Mistcrest, 2 Champion Mistcrest, 21 Hero Mistcrest, 20 Myth Mistcrest",
            road.steps[2].text
        )
        assert.is_nil(road.todo)
        assert.is_nil(road.verb)
    end)

    -- -----------------------------------------------------------------------
    -- The head slot: the helm he wears IS the plan, and the second copy of it
    -- in his bags must never be told to be put on (R-3a, WKE-570). The owner
    -- read "do: equip it" off a row rated behind his own helm on 2026-09-14.

    it("keeps the worn helm as the head pick and tells the bag copy to stay there", function()
        local set = group("Head", ns.Roads.GROUP_SET)
        assert.equal(2, #set)
        -- The pick is what he already wears, so there is nothing to do at all.
        local pick = set[1]
        assert.equal(ns.Roads.KIND_KEEP, pick.kind)
        assert.is_true(pick.planPick)
        assert.equal("Enigmatic Dreamwatcher's Somnolent Stare", pick.item.name)
        assert.equal("in your best set", pick.rating.badge)
        assert.equal("nothing to do", pick.todo)

        -- The second copy, in his bags, is an alternative rated behind it.
        local bagCopy = set[2]
        assert.is_false(bagCopy.planPick)
        assert.equal(308, bagCopy.arrivesAt)
        assert.equal(0.954912966995455, bagCopy.rating.scorePercent)
        assert.equal("0.95% behind", bagCopy.rating.badge)
        -- No imperative, and the words the slot's own plan opens with.
        assert.is_nil(bagCopy.todo and bagCopy.todo:match("^do: "))
        assert.equal("keep what you've got on", bagCopy.todo)
        assert.equal("Keep what you've got on, no crests here.", ns.Roads.ForSlot("Head", inputs).plan)
    end)

    it("says the same thing on every head road rated behind the helm he wears", function()
        local roads = ns.Roads.ForSlot("Head", inputs)
        local behind = 0
        for _, name in ipairs(ns.Roads.GROUP_ORDER) do
            for _, road in ipairs(roads.groups[name]) do
                if ns.Roads.IsRated(road) and not ns.Roads.IsForward(road) and road.kind ~= ns.Roads.KIND_KEEP then
                    behind = behind + 1
                    assert.equal(ns.Roads.TODO_KEEP_WORN, road.todo)
                end
            end
        end
        -- The bag copy, three Mythic+ drops, a Crafted row and a Delves row.
        assert.equal(6, behind)
    end)

    -- The sweep the issue asks for: not one phrasing, every phrasing, over
    -- every slot of the owner's own week.
    it("never carries an imperative on a road the plan is not going forward on", function()
        local slots = {}
        for _, record in ipairs(inputs.inventory.records) do
            if record.slot and not slots[record.slot] then
                slots[record.slot] = true
            end
        end
        local checked, imperatives = 0, 0
        for slot in pairs(slots) do
            local roads = ns.Roads.ForSlot(slot, inputs)
            for _, name in ipairs(ns.Roads.GROUP_ORDER) do
                for _, road in ipairs(roads.groups[name]) do
                    checked = checked + 1
                    if road.todo and road.todo:sub(1, 4) == ns.Roads.TODO_PREFIX then
                        imperatives = imperatives + 1
                        assert.is_true(ns.Roads.IsForward(road), (road.todo .. " on " .. slot))
                    end
                end
            end
        end
        assert.is_true(checked > 300)
        assert.is_true(imperatives > 0)
    end)

    -- Red for the gate: with the helm's own rating turned forward, the same
    -- road is told to be put on again.
    it("gives the imperative back the moment the rating points forward", function()
        local road = { kind = ns.Roads.KIND_EQUIP, todo = ns.Roads.TODO_EQUIP, rating = { kind = ns.Roads.RATING_SET } }
        local slotRoads = { groups = { set = { road }, item = {}, none = {} } }
        ns.Roads.GateImperatives(slotRoads)
        assert.is_nil(road.todo)
        road.todo, road.rating.inTopSet = ns.Roads.TODO_EQUIP, true
        ns.Roads.GateImperatives(slotRoads)
        assert.equal("do: equip it", road.todo)
    end)

    it("reads the glow's own gate off the rating and nothing else", function()
        assert.is_false(ns.Roads.IsForward(nil))
        assert.is_false(ns.Roads.IsForward({}))
        assert.is_true(ns.Roads.IsForward({ rating = { kind = ns.Roads.RATING_SET, inTopSet = true } }))
        assert.is_false(ns.Roads.IsForward({ rating = { kind = ns.Roads.RATING_SET, scorePercent = 0.95 } }))
        assert.is_true(ns.Roads.IsForward({ rating = { kind = ns.Roads.RATING_ITEM, percent = 0.17 } }))
        assert.is_false(ns.Roads.IsForward({ rating = { kind = ns.Roads.RATING_ITEM, percent = 0 } }))
        assert.is_false(ns.Roads.IsForward({ rating = { kind = ns.Roads.RATING_ITEM, percent = -0.5 } }))
        -- Not rated is not a verdict either way.
        assert.is_false(ns.Roads.IsForward({ rating = { kind = ns.Roads.RATING_NONE } }))
        assert.is_false(ns.Roads.IsRated({ rating = { kind = ns.Roads.RATING_NONE } }))
        assert.is_true(ns.Roads.IsRated({
            rating = { kind = ns.Roads.RATING_NONE },
            phrase = ns.Roads.PHRASE_NOT_IN_BEST_SET,
        }))
        assert.is_false(ns.Roads.IsRated({
            rating = { kind = ns.Roads.RATING_NONE },
            phrase = ns.Roads.PHRASE_NOT_RATED_LIMIT,
        }))
    end)

    -- -----------------------------------------------------------------------
    -- The groups are three, and they are never one ordering.

    it("never mixes a set verdict and a per-item percent into one list", function()
        local roads = ns.Roads.ForSlot("2H Weapon", inputs)
        assert.same({ "set", "item", "none" }, ns.Roads.GROUP_ORDER)
        for _, road in ipairs(roads.groups[ns.Roads.GROUP_SET]) do
            assert.equal(ns.Roads.RATING_SET, road.rating.kind)
        end
        for _, road in ipairs(roads.groups[ns.Roads.GROUP_ITEM]) do
            assert.equal(ns.Roads.RATING_ITEM, road.rating.kind)
        end
        for _, road in ipairs(roads.groups[ns.Roads.GROUP_NONE]) do
            assert.equal(ns.Roads.RATING_NONE, road.rating.kind)
        end
    end)

    it("orders the rated sources by the percent he gave, best first", function()
        local percents = {}
        for _, road in ipairs(group("2H Weapon", ns.Roads.GROUP_ITEM)) do
            percents[#percents + 1] = road.rating.percent
        end
        assert.is_true(#percents > 1)
        for index = 2, #percents do
            assert.is_true(percents[index - 1] >= percents[index])
        end
    end)

    -- -----------------------------------------------------------------------
    -- The tooltip's at-most-three.

    it("answers for the item under the cursor with its own road and the rated others", function()
        local key
        for _, record in ipairs(inputs.inventory.records) do
            if record.itemID == 277782 then
                key = record.key
            end
        end
        local answer = ns.Roads.ForItem(key, inputs)
        assert.equal("Shoulder", answer.slot)
        assert.equal(ns.Roads.KIND_CATALYST, answer.own.kind)
        assert.equal("in your best set", answer.own.rating.badge)
        -- One per remaining group, in group order, never a second row of the
        -- group the hovered item is already in - and RATED ONLY (R-2a,
        -- WKE-571). The Shoulder slot's no-rating group is not empty on this
        -- week; it took the second line of the owner's tooltip on 2026-09-14
        -- and told him nothing, so this answer no longer offers it. Principle
        -- 10's three is a cap, not a quota.
        assert.equal(1, #answer.others)
        assert.equal(ns.Roads.GROUP_ITEM, answer.others[1].group)
        assert.is_true(ns.Roads.IsRated(answer.others[1]))
        assert.is_true(#(answer.slotRoads.groups[ns.Roads.GROUP_NONE] or {}) > 0)
        assert.is_nil(answer.phrase)
    end)

    it("offers the forward road of a group before a rated-but-worse one", function()
        -- Built rather than found: the owner's week has no group whose first
        -- row is behind a later forward row, and "best-set or positive percent
        -- first" is a rule of the answer, not of his week.
        local function road(inGroup, rating)
            return { group = inGroup, slot = "Shoulder", keys = {}, rating = rating, item = { itemID = 1 } }
        end
        local behind = road(ns.Roads.GROUP_ITEM, { kind = ns.Roads.RATING_ITEM, percent = -2 })
        local forward = road(ns.Roads.GROUP_ITEM, { kind = ns.Roads.RATING_ITEM, percent = 3 })
        local slotRoads = {
            slot = "Shoulder",
            groups = {
                [ns.Roads.GROUP_SET] = { road(ns.Roads.GROUP_SET, nil) },
                [ns.Roads.GROUP_ITEM] = { behind, forward },
                [ns.Roads.GROUP_NONE] = { road(ns.Roads.GROUP_NONE, nil) },
            },
        }
        slotRoads.groups[ns.Roads.GROUP_SET][1].keys = { "the-hovered-one" }
        local answer = ns.Roads.ForItemIn(slotRoads, "the-hovered-one", {})
        assert.equal(1, #answer.others)
        assert.equal(forward, answer.others[1])
    end)

    it("hands back the phrase for an item no document has ever seen", function()
        local answer = ns.Roads.ForItem("424242:1", inputs)
        assert.is_nil(answer.own)
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, answer.phrase)
    end)

    -- The two tails have two different cures, so they are told apart by the
    -- leftover list the verdict file carries and by nothing else. The join is
    -- C-10's own (`ns.Companion.IsExcluded`), so a road and the tab that prints
    -- the note cannot answer "was this left out" differently.
    it("says 'beyond the rating's item limit' for an item on the leftover list", function()
        local record
        for _, entry in ipairs(inputs.inventory.records) do
            if entry.location == "bag" and entry.name and not record then
                record = entry
            end
        end
        -- Identity, the way a file written since C-10 carries it.
        inputs.excluded = ns.Companion.Excluded({
            {
                name = record.name,
                slot = record.slot,
                level = record.itemLevel,
                itemID = record.itemID,
                bonusIDs = record.bonusIDs,
            },
        })
        assert.equal(ns.Roads.PHRASE_NOT_RATED_LIMIT, ns.Roads.ForItem(record.key, inputs).phrase)

        -- The same item ID under a different set of bonus IDs is a different
        -- item, and identity says so: it gets the tail whose cure is a refresh,
        -- even though the name on the list is its own.
        local twin = { name = record.name, itemLevel = record.itemLevel, key = record.itemID .. ":1" }
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, ns.Roads.NotRatedPhrase(inputs.excluded, twin, twin.key))
        assert.equal(ns.Roads.PHRASE_NOT_RATED_LIMIT, ns.Roads.NotRatedPhrase(inputs.excluded, record, record.key))

        -- A file written before C-10 carries no identity, so the name and the
        -- level are all there is to match on, and they still match.
        inputs.excluded = ns.Companion.Excluded({
            { name = record.name, slot = record.slot, level = record.itemLevel },
        })
        assert.equal(ns.Roads.PHRASE_NOT_RATED_LIMIT, ns.Roads.ForItem(record.key, inputs).phrase)

        -- And with nothing on the list at all, it is the other tail.
        inputs.excluded = nil
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, ns.Roads.ForItem(record.key, inputs).phrase)
    end)

    -- C-11 (WKE-572). The owner's 2026-09-14 screen: 22 trinket rows and a pile
    -- of belts, boots and rings all reading "not rated - beyond the rating's
    -- item limit", because his 63 cards do not fit QE Live's thirty. The
    -- companion asks again over the leftovers now, and an item's rating comes
    -- from the pass that considered it.
    describe("an item a later pass rated", function()
        local record

        local function firstBagRecord()
            for _, entry in ipairs(inputs.inventory.records) do
                if entry.location == "bag" and entry.name and entry.key then
                    return entry
                end
            end
        end

        -- A pass-2 document as the verdict file carries it: the pool it was
        -- shown, and its own top set. Nothing here is merged with pass 1 and no
        -- two numbers are combined.
        local function passDocument(considered, topSetKeys)
            local items = {}
            for _, key in ipairs(topSetKeys or {}) do
                items[key] = { key = key, level = 600 }
            end
            return {
                {
                    pass = 2,
                    verdict = {
                        considered = ns.Companion.Excluded(considered),
                        topSet = { items = items },
                    },
                },
            }
        end

        before_each(function()
            record = firstBagRecord()
            -- Pass 1 never saw it: it is on the leftover list the plan's own
            -- document carries, which before C-11 was the end of the story.
            inputs.excluded = ns.Companion.Excluded({
                {
                    name = record.name,
                    slot = record.slot,
                    level = record.itemLevel,
                    itemID = record.itemID,
                    bonusIDs = record.bonusIDs,
                },
            })
        end)

        it("says it beats what you wear when the later pass put it in that pass's best set", function()
            -- Proved red first: with no later pass the line is still the limit
            -- tail, which is the screen the owner read.
            assert.equal(ns.Roads.PHRASE_NOT_RATED_LIMIT, ns.Roads.ForItem(record.key, inputs).phrase)

            inputs.passes = passDocument({
                {
                    name = record.name,
                    slot = record.slot,
                    level = record.itemLevel,
                    itemID = record.itemID,
                    bonusIDs = record.bonusIDs,
                },
            }, { record.key })
            local answer = ns.Roads.ForItem(record.key, inputs)
            assert.equal(ns.Roads.PHRASE_RATED_LATER, answer.phrase)
            assert.equal("rated · better than what you wear", answer.phrase)
            assert.equal(2, answer.laterPass)
            -- And the sentence above the line takes the plan's own position on
            -- it: the plan did not weigh this item, so it does not say "skip".
            assert.equal(ns.Roads.BEATS_WORN_SENTENCE, ns.Roads.ItemSentence(answer))
        end)

        it("says it is not in your best set when the later pass did not pick it", function()
            -- A pool that held everything the character is wearing and did not
            -- pick this item is a pool the fuller one could not have picked it
            -- out of either, so the third phrase is honest here and no number
            -- travels with it: a later pass's percents are against that pass's
            -- own top set.
            inputs.passes = passDocument({
                {
                    name = record.name,
                    slot = record.slot,
                    level = record.itemLevel,
                    itemID = record.itemID,
                    bonusIDs = record.bonusIDs,
                },
            }, {})
            local answer = ns.Roads.ForItem(record.key, inputs)
            assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, answer.phrase)
            assert.equal(2, answer.laterPass)
        end)

        it("keeps the limit tail for an item no pass was ever shown", function()
            -- The bound the companion stops at: what it never asked about is
            -- the one thing that still honestly reads "beyond the rating's item
            -- limit", and a pass that saw some OTHER item does not cure it.
            inputs.passes = passDocument({
                { name = "Something Else", slot = "Finger", level = 600, itemID = 999001, bonusIDs = { 3 } },
            }, {})
            assert.equal(ns.Roads.PHRASE_NOT_RATED_LIMIT, ns.Roads.ForItem(record.key, inputs).phrase)
        end)

        it("answers off the identity, so an item's twin does not borrow its rating", function()
            inputs.passes = passDocument({
                {
                    name = record.name,
                    slot = record.slot,
                    level = record.itemLevel,
                    itemID = record.itemID,
                    bonusIDs = record.bonusIDs,
                },
            }, { record.key })
            local twin = { name = record.name, itemLevel = record.itemLevel, key = record.itemID .. ":1" }
            assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, ns.Roads.NotRatedPhrase(nil, twin, twin.key, inputs.passes))
            assert.equal(ns.Roads.PHRASE_RATED_LATER, ns.Roads.NotRatedPhrase(nil, record, record.key, inputs.passes))
        end)

        it("is not evidence that the plan is behind the bags", function()
            -- A held piece a later pass rated is not a piece the document has
            -- never seen, so it must not make the slot say "refresh to rate it"
            -- (R-3b's defect 4 is about the other case).
            inputs.passes = passDocument({
                {
                    name = record.name,
                    slot = record.slot,
                    level = record.itemLevel,
                    itemID = record.itemID,
                    bonusIDs = record.bonusIDs,
                },
            }, { record.key })
            assert.is_false(ns.Roads.StaleBags(ns.Roads.ForSlot(record.slot, inputs), inputs))
        end)
    end)

    it("tells a vault option the plan looked at and left from one nothing rated", function()
        local lantern
        for _, option in ipairs(inputs.vault.options) do
            for _, reward in ipairs(option.rewards) do
                if reward.itemID == 275547 then
                    lantern = reward
                end
            end
        end
        -- Every vault option is active from the moment it is imported
        -- (558, `SimCImportEngine.ts:712`), so an option no set of his mentions
        -- was rated and rejected - the third phrase, never the limit's.
        local answer = ns.Roads.ForItem(lantern.key, inputs)
        assert.equal("Offhand", answer.slot)
        assert.equal(ns.Roads.KIND_VAULT, answer.own.kind)
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, answer.phrase)
        -- Rated, and rated behind: no imperative on the row (R-3a, WKE-570).
        assert.is_nil(answer.own.todo)
    end)

    -- -----------------------------------------------------------------------
    -- The plan sentence. THE VOICE TEST IS THE LIST BELOW: every sentence this
    -- module generates for the committed fixtures is written out in full, so
    -- the owner can read them the way a guildmate would.

    it("says the week's plan the way a guildmate would type it", function()
        local plan = ns.Roads.PlanSentence(inputs)
        assert.equal(
            "Grab the Worldroot from the vault and crest it."
                .. " Catalyst the Lynx shoulders in your bag."
                .. " Skip the vault shoulders.",
            plan.sentence
        )
        -- His best set spends two charges and the client says one is held, so
        -- the sentence names the first in HIS OWN top-set order and the
        -- footnote says the other. Nothing here chooses between them.
        assert.equal("You could catalyst the Hide chest too, but you've only got one charge.", plan.footnote)
        assert.equal("this week's picks", plan.plan)
    end)

    it("says both conversions in one clause when no count says one is too many", function()
        inputs.currencies.catalystCharges = nil
        local plan = ns.Roads.PlanSentence(inputs)
        assert.equal(
            "Grab the Worldroot from the vault and crest it."
                .. " Catalyst the Lynx shoulders in your bag and the Hide chest in your bag."
                .. " Skip the vault shoulders.",
            plan.sentence
        )
        assert.is_nil(plan.footnote)
    end)

    it("says the slot's own line in the same voice", function()
        assert.equal(
            "Catalyst your Lynx shoulders, skip the vault ones, no crests here.",
            ns.Roads.ForSlot("Shoulder", inputs).plan
        )
        assert.equal("Grab the Worldroot from the vault and crest it.", ns.Roads.ForSlot("2H Weapon", inputs).plan)
    end)

    -- The rule the sentences are held to (docs/ROADS-UX.md principle 16).
    it("keeps every generated sentence free of labels, numbers and sources", function()
        local lines = { ns.Roads.PlanSentence(inputs).sentence, ns.Roads.PlanSentence(inputs).footnote }
        for _, slot in ipairs({ "Head", "Neck", "Shoulder", "Chest", "2H Weapon", "Feet", "Finger", "Trinket" }) do
            lines[#lines + 1] = ns.Roads.ForSlot(slot, inputs).plan
        end
        local banned = { "%%", "QE", "Live", ":", "rated", "in your best set", "item level", "%d%d%d" }
        for _, line in ipairs(lines) do
            if line then
                for _, pattern in ipairs(banned) do
                    assert.is_nil(line:match(pattern), string.format("%q contains %q", line, pattern))
                end
            end
        end
    end)

    it("says so plainly when the plan is nothing at all", function()
        -- The 2026-09-06 export with nothing extra selected: its top set is the
        -- fifteen items the character was wearing, it has no differentials and
        -- no vault option, so there is genuinely nothing to do.
        local asOffered = document(AS_OFFERED_RAID, "asOffered", {
            autoUpgradeVault = false,
            autoUpgradeAll = false,
            autoCatalyze = false,
        })
        local plan = ns.Roads.PlanSentence({
            verdicts = { { verdict = asOffered, scenario = "asOffered" } },
            highlightedScenario = "asOffered",
        })
        assert.equal(ns.Roads.NO_PLAN_SENTENCE, plan.sentence)
        assert.equal("Nothing this week beats what you've got on.", plan.sentence)
        assert.is_nil(plan.footnote)
    end)

    it("has no sentence at all when no plan has been stored", function()
        assert.is_nil(ns.Roads.PlanSentence({}).sentence)
        assert.is_nil(ns.Roads.PlanSentence(nil).sentence)
    end)

    -- C-12 (WKE-577). The owner's screen on 2026-09-14: the Vault tab follows
    -- `thisWeek`, the companion had asked `asOffered` and nothing else, and the
    -- tab drew the fallback plan without a word about the one it was labelled
    -- with.
    describe("a plan whose scenario was never asked", function()
        local NOTE = "The upgrade question went unasked: nothing you hold is below its upgrade cap."

        local function asOfferedOnly(extra)
            local week = {
                verdicts = {
                    {
                        verdict = document(AS_OFFERED_RAID, "asOffered", {
                            autoUpgradeVault = false,
                            autoUpgradeAll = false,
                            autoCatalyze = false,
                        }),
                        scenario = "asOffered",
                    },
                },
                highlightedScenario = "thisWeek",
            }
            for key, value in pairs(extra or {}) do
                week[key] = value
            end
            return week
        end

        it("says the companion's own words as the footnote", function()
            local plan = ns.Roads.PlanSentence(asOfferedOnly({ scenarioNote = NOTE }))
            assert.equal(ns.Roads.NO_PLAN_SENTENCE, plan.sentence)
            assert.equal(NOTE, plan.footnote)
            -- The plan on screen is still named for the document that answered
            -- it, never for the one that was asked for.
            assert.equal("as offered", plan.plan)
        end)

        it("stays silent when the companion said nothing", function()
            assert.is_nil(ns.Roads.PlanSentence(asOfferedOnly()).footnote)
            assert.is_nil(ns.Roads.PlanSentence(asOfferedOnly({ scenarioNote = "" })).footnote)
            assert.is_nil(ns.Roads.PlanSentence(asOfferedOnly({ scenarioNote = {} })).footnote)
        end)

        it("does not say it when the plan on screen IS the one that was asked for", function()
            local week = asOfferedOnly({ scenarioNote = NOTE })
            week.highlightedScenario = "asOffered"
            assert.is_nil(ns.Roads.PlanSentence(week).footnote)
        end)

        it("says it after the charge footnote rather than instead of it", function()
            local week = {}
            for key, value in pairs(inputs) do
                week[key] = value
            end
            week.highlightedScenario = "notAScenarioAnyoneAsked"
            week.scenarioNote = NOTE
            local plan = ns.Roads.PlanSentence(week)
            assert.equal(
                "You could catalyst the Hide chest too, but you've only got one charge. " .. NOTE,
                plan.footnote
            )
        end)

        it("is the whole answer when there is no plan stored at all", function()
            assert.equal(NOTE, ns.Roads.PlanSentence({ scenarioNote = NOTE }).footnote)
            assert.is_nil(ns.Roads.PlanSentence({ scenarioNote = NOTE }).sentence)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- R-3b (WKE-576): the pick that has already arrived.
    --
    -- The owner's screen of 2026-09-14 night, reproduced over this week's own
    -- files. He did what the plan said - took the vault's Lightgrasp Worldroot
    -- and put crests into it - and the plan then told him to skip the result,
    -- because the claimed copy carries its own bonus IDs and so its own KEY,
    -- and no document mentions that key.
    --
    -- The claimed copy is HAND-BUILT: no capture has one, because the claim
    -- happens between two refreshes. Everything about it except its bonus ID is
    -- read out of this week's files - item 251935, slot 2H Weapon, the name the
    -- vault reward itself carries - and the bonus ID is invented precisely
    -- because it has to be a third one: 12841 is the vault's copy and 12838 is
    -- the 308 still on the character. That the key is new and the item ID is
    -- not is the whole of what the rule reads.
    local CLAIMED_LEVEL = 315

    local function wornWorldroot()
        for _, record in ipairs(inputs.inventory.records) do
            if record.location == "equipped" and record.itemID == 251935 then
                return record
            end
        end
        return nil
    end

    local function claimedWorldroot()
        local worn = wornWorldroot()
        assert.is_table(worn)
        local link = worn.link:gsub("12838", "12844")
        local parsed = ns.ParseItemLink(link)
        assert.is_table(parsed)
        local record = {
            key = parsed.key,
            itemID = parsed.itemID,
            link = link,
            name = "Lightgrasp Worldroot",
            slot = "2H Weapon",
            itemLevel = CLAIMED_LEVEL,
            location = "bag",
        }
        -- A third key, and the same item ID as both of the other two.
        assert.equal(251935, record.itemID)
        assert.is_true(record.key ~= worn.key)
        assert.is_true(record.key ~= "251935:6652:12841")
        table.insert(inputs.inventory.records, record)
        return record
    end

    local function answerFor(slot, key)
        return ns.Roads.ForItemIn(ns.Roads.ForSlot(slot, inputs), key, inputs)
    end

    it("calls a bag copy of the vault pick the pick, by item ID and never by key", function()
        local claimed = claimedWorldroot()
        local pick = group("2H Weapon", ns.Roads.GROUP_SET)[1]
        assert.equal(ns.Roads.KIND_VAULT, pick.kind)
        assert.is_true(ns.Roads.IsArrivedPick(claimed, pick))
        -- What it refuses, and both refusals matter on this very screen. The
        -- 308 he is wearing has the SAME item ID and is not something that has
        -- just turned up; the slot already has its own road for it.
        assert.is_false(ns.Roads.IsArrivedPick(wornWorldroot(), pick))
        -- The vault reward itself is the road's own item, and the road speaks
        -- for it: the pick has not "arrived" by being where it always was.
        assert.is_false(ns.Roads.IsArrivedPick({
            itemID = 251935,
            key = pick.keys[1],
            location = "bag",
        }, pick))
        -- And a road that is not the plan's pick is not a pick at all.
        assert.is_false(ns.Roads.IsArrivedPick(claimed, group("2H Weapon", ns.Roads.GROUP_SET)[2]))
    end)

    it("says the vault weapon has arrived instead of telling the player to skip it", function()
        local claimed = claimedWorldroot()
        local answer = answerFor("2H Weapon", claimed.key)
        -- No road carries this key: it is new since the last refresh, and the
        -- honesty phrase under the sentence still says exactly that.
        assert.is_nil(answer.own)
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, answer.phrase)
        assert.is_true(answer.held)
        -- 315 is above the 305 the vault is offering it at, so the crest is
        -- part of what has happened and the step left is not the refresh alone:
        -- the plan wants this staff on the character (R-3c, WKE-580).
        assert.equal("Put this on - then refresh.", ns.Roads.ItemSentence(answer))
    end)

    -- The other bag piece in the same slot, on the same screen: the rule is
    -- narrow, and a weapon that is NOT the pick still reads the way it did.
    it("still tells the player to skip a bag piece that is not the pick", function()
        claimedWorldroot()
        local decapitator
        for _, record in ipairs(inputs.inventory.records) do
            if record.location == "bag" and record.itemID == 275222 then
                decapitator = record
            end
        end
        assert.is_table(decapitator)
        local answer = answerFor("2H Weapon", decapitator.key)
        assert.equal("Pass - take the vault Worldroot.", ns.Roads.ItemSentence(answer))
    end)

    it("says the vault road is claimed and crested, with Refresh as its step", function()
        claimedWorldroot()
        local pick = group("2H Weapon", ns.Roads.GROUP_SET)[1]
        -- The badge says the furthest the piece has got: claimed, and crested
        -- past the 305 the vault offered (R-3c, WKE-580). "claimed · in your
        -- bags" is what it says while the level is still the vault's.
        assert.equal(ns.Roads.ARRIVED_CLAIMED_CRESTED, pick.claimed)
        assert.equal("claimed · now crested", pick.claimed)
        assert.equal(ns.Roads.VERB_REFRESH, pick.verb)
        assert.equal("do: refresh to rate it", pick.todo)
        -- The vault's own state is not read for any of this: the countdown the
        -- client gave is still the client's and still on the row.
        assert.is_true(pick.resetSeconds > 0)
    end)

    -- Red for all four: with nothing claimed, the same road is the one R-1
    -- built and every assertion above is false.
    it("leaves the vault road alone while the reward is still in the vault", function()
        local pick = group("2H Weapon", ns.Roads.GROUP_SET)[1]
        assert.is_nil(pick.claimed)
        assert.equal(ns.Roads.VAULT_OPEN_NOW, pick.openNow)
        assert.equal(ns.Roads.VERB_SHOW_IN_VAULT, pick.verb)
        assert.equal("do: take it · rated at 321, crests not readable", pick.todo)
        assert.is_nil(ns.Roads.ForSlot("2H Weapon", inputs).arrived)
    end)

    -- The same identity rule on the other shape it takes: a Catalyst pick that
    -- has since been converted. The shoulder pick converts the Lynx Spaulders
    -- (277782) into his tier shoulder (271526), and what comes out of the
    -- Catalyst carries the TIER item ID, so that is what is matched.
    it("knows the tier piece a converted Catalyst pick left in the bags", function()
        local pick = group("Shoulder", ns.Roads.GROUP_SET)[1]
        assert.equal(ns.Roads.KIND_CATALYST, pick.kind)
        assert.equal(271526, pick.becomes.itemID)
        -- Hand-built for the same reason the Worldroot above is: the clone
        -- exists only after a conversion no capture caught. Its item ID is the
        -- document's own (271526); its bonus IDs are not, because he crested it
        -- after converting it, and that is what makes its key one no document
        -- carries. The projection's own key, 271526:6652:12830:13662, IS on the
        -- Catalyst road (its second key), and a held item carrying that key is
        -- the road's own item rather than something that has arrived.
        local converted = {
            key = "271526:6652:12844:13662",
            itemID = 271526,
            slot = "Shoulder",
            itemLevel = 295,
            location = "bag",
        }
        table.insert(inputs.inventory.records, converted)
        assert.is_true(ns.Roads.IsArrivedPick(converted, pick))
        assert.equal("Put these on - then refresh.", ns.Roads.ItemSentence(answerFor("Shoulder", converted.key)))
        -- A Catalyst road is not a vault road and gains no vault badge.
        assert.is_nil(ns.Roads.ForSlot("Shoulder", inputs).groups[ns.Roads.GROUP_SET][1].claimed)
    end)

    -- Defect 4: a stale plan names its own remedy. The slot is stale when it
    -- holds something no road of it rates whose tail is the one a refresh
    -- cures - this week, the 259 Decapitator sitting in his bags.
    it("knows when a slot's bags have moved past the plan", function()
        assert.is_true(ns.Roads.ForSlot("2H Weapon", inputs).staleBags)
        assert.is_true(answerFor("2H Weapon", "251935:6652:12841").stale)
    end)

    it("says nothing about a refresh for a slot whose bags the plan has seen", function()
        local kept = {}
        for _, record in ipairs(inputs.inventory.records) do
            if not (record.slot == "2H Weapon" and record.location == "bag") then
                kept[#kept + 1] = record
            end
        end
        inputs.inventory.records = kept
        assert.is_false(ns.Roads.ForSlot("2H Weapon", inputs).staleBags)
        assert.is_false(answerFor("2H Weapon", "251935:6652:12841").stale)
    end)

    -- Defect 3, the half that needs nothing from the client: the name is in the
    -- vault reward's own hyperlink. Strip what the client answered and the road
    -- is still named, with no request made and none possible here.
    it("names a vault road off the reward's own link when the client named nothing", function()
        for _, option in ipairs(inputs.vault.options) do
            for _, reward in ipairs(option.rewards or {}) do
                reward.name = nil
            end
        end
        local pick = group("2H Weapon", ns.Roads.GROUP_SET)[1]
        assert.equal("Lightgrasp Worldroot", pick.item.name)
    end)

    -- -----------------------------------------------------------------------
    -- R-3c (WKE-580): the pick that has moved slot as well as key.
    --
    -- One step past R-3b. The owner crested the staff the plan picked out of
    -- his bags and put it on, and the tooltip told him to skip it in favour of
    -- itself - because the worn copy has its own key, its own road (every worn
    -- piece gets an Upgrade road) and a placement R-3b refused to look at.
    --
    -- His own week has no bag pick to reproduce that on: every slot's pick here
    -- is the vault staff, a Catalyst conversion, or the piece he wears. So the
    -- PLACEMENT is hand-built, which is what the issue asks for and the only
    -- thing here that is: the cloak the `thisWeek` top set really picks
    -- (275522, "Preyhunter's Refined Shawl", 298, in the top set at that level)
    -- is moved into the bags, which makes the plan's pick a bag piece with "do:
    -- equip it" on it, and the copies that arrive are built off that record's
    -- own hyperlink with one bonus ID changed - 12835 for 12839 - so that the
    -- key is new and the item ID is not. Every level and every name below is
    -- the committed capture's or the committed document's.
    local CLOAK = 275522

    local function cloakRecord()
        for _, record in ipairs(inputs.inventory.records) do
            if record.itemID == CLOAK then
                return record
            end
        end
        return nil
    end

    -- The plan's pick, in the bags: what "do: equip it" is written on.
    local function bagPick()
        local record = cloakRecord()
        assert.is_table(record)
        assert.equal("equipped", record.location)
        record.location = "bag"
        local pick = ns.Roads.PlanPick(ns.Roads.ForSlot("Back", inputs))
        assert.is_table(pick)
        assert.equal(ns.Roads.KIND_SET, pick.kind)
        assert.equal(298, pick.arrivesAt)
        assert.equal("do: equip it", pick.todo)
        return pick
    end

    -- A copy of it the plan has never seen, wherever the player has put it.
    local function cloakCopy(level, location)
        local record = cloakRecord()
        assert.is_table(record)
        local link = record.link:gsub("12835", "12839")
        local parsed = ns.ParseItemLink(link)
        assert.is_table(parsed)
        assert.equal(CLOAK, parsed.itemID)
        assert.is_true(parsed.key ~= record.key)
        local copy = {
            key = parsed.key,
            itemID = parsed.itemID,
            link = link,
            name = record.name,
            slot = "Back",
            itemLevel = level,
            location = location,
        }
        table.insert(inputs.inventory.records, copy)
        return copy
    end

    local function crestRoad(slot, whichGroup)
        for _, road in ipairs(ns.Roads.ForSlot(slot, inputs).groups[whichGroup]) do
            if road.kind == ns.Roads.KIND_CREST then
                return road
            end
        end
        return nil
    end

    it("calls the copy you have put on the pick, moved on", function()
        bagPick()
        local worn = cloakCopy(298, "equipped")
        local pick = ns.Roads.PlanPick(ns.Roads.ForSlot("Back", inputs))
        assert.is_true(ns.Roads.IsArrivedPick(worn, pick))
        local answer = answerFor("Back", worn.key)
        -- The half of the defect R-3b could not have caught: the worn copy DOES
        -- have a road of its own - the Upgrade road every worn piece gets - and
        -- the sentence used to be read off the plan's pick rather than off the
        -- item's own identity.
        assert.is_table(answer.own)
        assert.equal(ns.Roads.KIND_CREST, answer.own.kind)
        assert.equal("Refresh - you're already wearing it.", ns.Roads.ItemSentence(answer))
    end)

    it("says the crest as well when the worn level is above the one the plan picked", function()
        bagPick()
        local worn = cloakCopy(308, "equipped")
        local pick = ns.Roads.PlanPick(ns.Roads.ForSlot("Back", inputs))
        assert.is_true(ns.Roads.ArrivedCrested(worn, pick))
        assert.equal("Refresh - you're already wearing it.", ns.Roads.ItemSentence(answerFor("Back", worn.key)))
        -- And the road the reader would otherwise be told to walk again says
        -- where the piece has got to, and has nothing left but the refresh.
        assert.equal(ns.Roads.ARRIVED_NOW_WORN, pick.claimed)
        assert.equal("now worn", pick.claimed)
        assert.equal(ns.Roads.VERB_REFRESH, pick.verb)
        assert.equal("do: refresh to rate it", pick.todo)
        -- Nothing was claimed from anywhere, so nothing says it was: "claimed"
        -- is the vault's own word and this cloak came out of a dungeon.
        assert.is_nil(pick.claimed:find("claimed", 1, true))
    end)

    it("tells the player to put on a bag copy crested past the plan", function()
        bagPick()
        local crested = cloakCopy(308, "bag")
        local pick = ns.Roads.PlanPick(ns.Roads.ForSlot("Back", inputs))
        assert.is_true(ns.Roads.IsArrivedPick(crested, pick))
        assert.equal("Put this on - then refresh.", ns.Roads.ItemSentence(answerFor("Back", crested.key)))
        -- Still in the bags, so the step the road already carries is the right
        -- one and stays; only the badge is new.
        assert.equal(ns.Roads.ARRIVED_NOW_CRESTED, pick.claimed)
        assert.equal("now crested", pick.claimed)
        assert.equal("do: equip it", pick.todo)
    end)

    it("reads the bank the same way it reads the bags", function()
        bagPick()
        local crested = cloakCopy(308, "bank")
        local pick = ns.Roads.PlanPick(ns.Roads.ForSlot("Back", inputs))
        assert.is_true(ns.Roads.IsArrivedPick(crested, pick))
        assert.equal("Put this on - then refresh.", ns.Roads.ItemSentence(answerFor("Back", crested.key)))
    end)

    -- R-3e (WKE-585) retired the refusal this test used to make. A copy BELOW
    -- the level the plan picked at used to be "a worse duplicate, not the pick
    -- moved on"; it is now the pick with the crest half spent, and the LEVEL
    -- words the sentence rather than deciding the identity. Proven red by
    -- putting the gate back: both sentences go to "Skip this one, the plan uses
    -- your Preyhunter cloak", which is the owner's own 2026-09-15 defect.
    it("calls a copy short of the plan's level the pick, under-crested", function()
        bagPick()
        local short = cloakCopy(289, "bag")
        local pick = ns.Roads.PlanPick(ns.Roads.ForSlot("Back", inputs))
        assert.is_true(ns.Roads.IsArrivedPick(short, pick))
        assert.is_true(ns.Roads.ArrivedShort(short, pick))
        assert.is_false(ns.Roads.ArrivedCrested(short, pick))
        assert.equal("Crest this to 298 - then refresh.", ns.Roads.ItemSentence(answerFor("Back", short.key)))
    end)

    it("says the same about a copy short of the plan's level that you have put on", function()
        bagPick()
        local worn = cloakCopy(289, "equipped")
        local pick = ns.Roads.PlanPick(ns.Roads.ForSlot("Back", inputs))
        assert.is_true(ns.Roads.IsArrivedPick(worn, pick))
        assert.equal("Crest this to 298 - then refresh.", ns.Roads.ItemSentence(answerFor("Back", worn.key)))
        -- The badge says where the piece has got to, and says nothing about a
        -- crest that has not happened.
        assert.equal(ns.Roads.ARRIVED_NOW_WORN, pick.claimed)
    end)

    -- -----------------------------------------------------------------------
    -- Defect 2: the Upgrade road reads the `maxed` document.
    --
    -- Three of the owner's own worn pieces are rated by that document at a
    -- level above the one they are at, and the road used to say "no rating" and
    -- point at the level they already wear ("upgrade the 302 to 302"). Every
    -- figure below is read out of `qe-droptimizer-Hotornot-qqrqsbudcszh.json`.
    local function withMaxed()
        local maxed = document(MAXED_DUNGEON, "maxed", {
            autoUpgradeVault = true,
            autoUpgradeAll = true,
            autoCatalyze = true,
        })
        inputs.verdicts[#inputs.verdicts + 1] = { verdict = maxed, scenario = "maxed" }
        return maxed
    end

    it("rates upgrading what you wear out of the maxed document, at the level it projected", function()
        local maxed = withMaxed()
        -- The document's own answer for the cloak on the character: the same
        -- key, because the upgrade boxes move `level` and never a bonus ID, in
        -- its top set at 308 while the client reports 298.
        local projected = maxed.topSet.items["275522:41:12835:13662"]
        assert.is_table(projected)
        assert.equal(308, projected.level)
        assert.equal(298, cloakRecord().itemLevel)

        local road = crestRoad("Back", ns.Roads.GROUP_SET)
        assert.is_table(road)
        assert.equal(ns.Roads.TAG_UPGRADE, road.tag)
        assert.equal(308, road.arrivesAt)
        assert.equal("in your best set", road.rating.badge)
        assert.equal(ns.Roads.RATING_SET, road.rating.kind)
        assert.equal("everything upgraded", road.plan)
        assert.is_true(ns.Roads.IsForward(road))
        -- And it is no longer in the group whose header says "No rating".
        assert.is_nil(crestRoad("Back", ns.Roads.GROUP_NONE))
        -- The other two the same document raises, so this is not one lucky key.
        assert.equal(308, crestRoad("Feet", ns.Roads.GROUP_SET).arrivesAt)
        assert.equal(308, crestRoad("Waist", ns.Roads.GROUP_SET).arrivesAt)
    end)

    it("builds no upgrade road at all when the document projects the level already worn", function()
        local maxed = withMaxed()
        -- The necklace is at the top of its track: the document carries it at
        -- the level the client reports, so there is nothing to crest and no
        -- road, rather than a road that leads where the reader is standing.
        local projected = maxed.topSet.items["272228:6652:12846:13668"]
        assert.is_table(projected)
        assert.equal(321, projected.level)
        assert.is_nil(crestRoad("Neck", ns.Roads.GROUP_SET))
        assert.is_nil(crestRoad("Neck", ns.Roads.GROUP_NONE))
    end)

    it("says why there is no rating when the upgrade question went unasked", function()
        -- C-12's own sentence, as the companion writes it for a run that could
        -- not ask: nothing the character holds was below its cap.
        local NOTE = "The upgrade question went unasked: nothing you hold is below its upgrade cap."
        inputs.verdicts[1].verdict.scenarioNote = NOTE
        local road = crestRoad("Back", ns.Roads.GROUP_NONE)
        assert.is_table(road)
        assert.equal(ns.Roads.PHRASE_NO_RATING, road.phrase)
        assert.equal(NOTE, road.steps[1].text)
        assert.equal(NOTE, ns.Roads.Facts(road)[1])
        -- With the document stored the reason is not said, because there is
        -- nothing to explain: the run asked, and the road carries the answer.
        withMaxed()
        assert.is_nil(crestRoad("Back", ns.Roads.GROUP_NONE))
        local rated = crestRoad("Back", ns.Roads.GROUP_SET)
        assert.is_nil(rated.steps[1].text:find("unasked", 1, true))
    end)

    -- Defect 3: the crest counts leave the tooltip. They are the vendor row's
    -- business, beside the cost they would pay, and on a tooltip they were the
    -- longest clause on the block and answered a question nobody asked there
    -- (R-2a's rule, applied here).
    it("marks the crest counts a cost fact, so only the row carries them", function()
        local holding = ns.Roads.CrestHoldingText(inputs.currencies)
        assert.equal(
            "you hold 356 Adventurer Mistcrest, 2 Champion Mistcrest, 21 Hero Mistcrest, 20 Myth Mistcrest",
            holding
        )
        local road = crestRoad("Back", ns.Roads.GROUP_NONE)
        assert.is_table(road)
        local costs = ns.Roads.CostFacts(road)
        assert.equal(holding, costs[#costs])
        local facts = ns.Roads.Facts(road)
        assert.equal(holding, facts[#facts])
    end)

    -- -----------------------------------------------------------------------
    -- The premise check (CLAUDE.md: verify the issue's premise against the code
    -- and the files before building).
    --
    -- The issue asked for the weapon slot's Keep road at "2.74% behind". That
    -- figure is real, and it is not this plan's: the only set in any committed
    -- document that is 2.74% behind for keeping the worn 308 weapon ALONE is
    -- alternative 12 of the `maxed` Dungeon document, whose question is
    -- "everything upgraded". Under `thisWeek` no differential changes the
    -- weapon slot on its own; the nearest is differential 7, at 1.729%, which
    -- also takes the vault Spaulders. Both are asserted here so the correction
    -- is a measurement and not an opinion.

    it("reads 2.74% out of the plan that really says it, and 1.73% out of this one", function()
        local maxed = document(MAXED_DUNGEON, "maxed", {
            autoUpgradeVault = true,
            autoUpgradeAll = true,
            autoCatalyze = true,
        })
        -- Where the canvas's figure lives: alternative 12 of the `maxed`
        -- document, the only set in any committed file that is 2.74% behind for
        -- keeping the worn 308 weapon, and the only one that changes the weapon
        -- slot and nothing else.
        local alone = maxed.alternatives[12]
        assert.equal(2.7417885993867621, alone.scorePercent)
        assert.equal(1, #alone.items)
        assert.equal("2H Weapon", alone.items[1].slot)
        assert.equal(251935, alone.items[1].itemID)
        assert.equal(308, alone.items[1].level)

        -- What the road says is not that one. A road reports the BEST set he
        -- ranked that carries this item, which is ns.QEImport.Coverage's own
        -- rule and the rule the shoulder board reads under too; under `maxed`
        -- that set is 1.72% behind and it changes other slots as well, so the
        -- badge names what taking it costs.
        local keep
        for _, road in
            ipairs(ns.Roads.ForSlot("2H Weapon", {
                verdicts = { { verdict = maxed, scenario = "maxed" } },
                highlightedScenario = "maxed",
                inventory = inputs.inventory,
                vault = inputs.vault,
                currencies = inputs.currencies,
            }).groups[ns.Roads.GROUP_SET])
        do
            keep = keep or (road.kind == ns.Roads.KIND_KEEP and road or nil)
        end
        assert.is_table(keep)
        assert.equal(1.7168208986814304, keep.rating.scorePercent)
        assert.equal("1.72% behind", keep.rating.badge)
        assert.equal("everything upgraded", keep.plan)

        -- And under the plan the week is actually read through, the same road
        -- is differential 7 at 1.73%.
        assert.equal("1.73% behind", group("2H Weapon", ns.Roads.GROUP_SET)[2].rating.badge)
    end)
end)

-- ---------------------------------------------------------------------------
-- R-3e (WKE-585): the owner's Legs slot of 2026-09-15, after the claim.
--
-- What he read at ~15:45 local on `main` at 61b27fc, over the 14:31 verdict:
--
--   Lootpath · Legs · rated 75 minutes ago · /lootpath refresh
--   Skip this one, the plan uses your Dreamwatcher legs.
--   Catalyst · Enigmatic Dreamwatcher's Leggings (321) · into the tier legs
--
-- The plan's pick for Legs was those leggings and the tooltip over them said to
-- skip them in favour of themselves. He had done exactly what the plan said:
-- claimed the reward and crested it one step of the two, 315 -> 318.
--
-- **Why the road was a Catalyst road, read in the code and against
-- ARCHITECTURE.md §9.** At 14:31, with the Great Vault window open, the same
-- road read `Vault, open now, Enigmatic Dreamwatcher's Leggings (315), upgraded
-- to 321` - which is right. What changed in the 75 minutes is not the document:
-- the reward LEFT the vault when he claimed it. With the vault no longer
-- offering 271527, `QEImport`'s conversion join stopped recognising the set item
-- as the reward as offered and handed back a conversion with no source,
-- `setItemKind` read "conversion" as "Catalyst", and the road's `arrivesAt`
-- became the projected 321 rather than the vault's 315 - which is what then put
-- the held 318 under the level gate.
--
-- So the scenario below is that pair of states over one document, and every
-- figure in it is read from a file:
--
--   * the vault is `spec/fixtures/captures/Lootpath-20260915-142722-vault.lua`
--     snapshot 12, his own reset-day capture with the window open: it offers
--     `Enigmatic Dreamwatcher's Leggings` at **315**, link bonus IDs
--     13693:12844:13440:6652:13698.
--   * the claimed state is that same snapshot with that one reward gone, which
--     is what his client held once he had taken it.
--   * the top set's Legs entry is the vault link's own bonus IDs with the
--     upgrade bonus advanced one step, 12844 -> **12846**, at **321**: 12846 is
--     the 321 step measured in his own 16:20 documents (the worn staff
--     `251935:6652:12846` at 321), and ARCHITECTURE.md §9 records the 14:31 top
--     set carrying these leggings crested to 321.
--   * the copy in his bags is the same link with **12845**, at **318** - the key
--     his own 16:20 documents carry for the piece he crested.
--   * the Shoulder entry is the committed `thisWeek` Dungeon document's own
--     (271526 at 295, bonus IDs 6652:13662:12830), his real Catalyst clone of
--     the Venom-Cursed Lynx's Spaulders in the 09-08 scan. It is here so the one
--     charge has somewhere true to go.
describe("Roads over the owner's claimed Legs pick of 2026-09-15 (R-3e)", function()
    local ns, world, inputs

    local LEGS = 271527
    local VAULT_CAPTURE = "spec/fixtures/captures/Lootpath-20260915-142722-vault.lua"
    local WINDOW_OPEN = 12
    -- The vault's own link for the reward, read out of that snapshot.
    local VAULT_LINK = "|cffa335ee|Hitem:271527::::::::90:105::35:5:13693:12844:13440:6652:13698::::::"
        .. "|h[Enigmatic Dreamwatcher's Leggings]|h|r"

    -- The one Legs entry of the 14:31 top set: the vault reward his run upgraded
    -- to 321. `isVault` is the export's own flag for a reward this week's vault
    -- is offering.
    local function leggings()
        return {
            key = "271527:6652:12846:13440:13693:13698",
            itemID = LEGS,
            slot = "Legs",
            level = 321,
            setId = 2057,
            isVault = true,
            isExclusive = false,
            count = 1,
            bonusIDs = { 6652, 12846, 13440, 13693, 13698 },
            source = { instanceId = -98, encounterId = -98 },
        }
    end

    -- His Catalyst clone of the bag Spaulders, lifted from the committed
    -- document rather than written here.
    local function shoulderClone()
        return {
            key = "271526:6652:12830:13662",
            itemID = 271526,
            slot = "Shoulder",
            level = 295,
            setId = 2057,
            isVault = false,
            isExclusive = false,
            count = 1,
            bonusIDs = { 6652, 12830, 13662 },
            source = {},
        }
    end

    local function verdict()
        local legs, shoulder = leggings(), shoulderClone()
        return {
            scenario = "thisWeek",
            exportedAt = "2026-09-15T19:31:00Z",
            qeSettings = { autoCatalyze = true, autoUpgradeVault = true, autoUpgradeAll = false },
            topSet = {
                score = 6115.012,
                items = { [legs.key] = legs, [shoulder.key] = shoulder },
                order = { legs.key, shoulder.key },
            },
            alternatives = {},
            differentials = {},
        }
    end

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
        R.vault(world, R.snapshot("vault", WINDOW_OPEN, VAULT_CAPTURE))
        world.currencyByID = { [3465] = CATALYST }

        local inventory = ns.Inventory.Scan()
        assert.is_true(inventory.ok, inventory.reason)
        local vault = ns.Vault.Options()
        assert.is_true(vault.ok, vault.reason)
        local currencies = ns.Currencies.Read({ snapshot = R.snapshot("currencies", CURRENCY_SNAPSHOT, CURRENCIES) })
        assert.is_true(currencies.ok)
        currencies.catalyst = CATALYST
        currencies.catalystCharges = CATALYST.quantity
        currencies.catalystMax = CATALYST.maxQuantity

        inputs = {
            verdicts = { { verdict = verdict(), scenario = "thisWeek" } },
            highlightedScenario = "thisWeek",
            inventory = inventory,
            vault = vault,
            currencies = currencies,
            now = 1789500000,
        }
    end)

    after_each(function()
        H.unload()
    end)

    -- The reward as his client held it once he had taken it: gone from the
    -- vault, and nothing else changed.
    local function claimTheReward()
        for _, option in ipairs(inputs.vault.options) do
            local kept = {}
            for _, reward in ipairs(option.rewards or {}) do
                if tonumber(reward.itemID) ~= LEGS then
                    kept[#kept + 1] = reward
                end
            end
            option.rewards = kept
        end
    end

    -- The 318 in his bags: the vault's own link, crested one step.
    local function crestedTo318()
        local link = VAULT_LINK:gsub("12844", "12845")
        local parsed = ns.ParseItemLink(link)
        assert.is_table(parsed)
        assert.equal(LEGS, parsed.itemID)
        assert.equal("271527:6652:12845:13440:13693:13698", parsed.key)
        local record = {
            key = parsed.key,
            itemID = parsed.itemID,
            link = link,
            name = "Enigmatic Dreamwatcher's Leggings",
            slot = "Legs",
            itemLevel = 318,
            location = "bag",
        }
        table.insert(inputs.inventory.records, record)
        return record
    end

    local function pickFor(slot)
        return ns.Roads.PlanPick(ns.Roads.ForSlot(slot, inputs))
    end

    local function answerFor(slot, key)
        return ns.Roads.ForItemIn(ns.Roads.ForSlot(slot, inputs), key, inputs)
    end

    -- Defect 2. Proven red by putting `if conversion then return
    -- Roads.KIND_CATALYST end` back at the top of `setItemKind`: the kind goes
    -- to `catalyst`, `becomes` comes back as the leggings themselves,
    -- `catalyzed` as true, and `arrivesAt` as 321 - the owner's own row.
    it("keeps a claimed vault reward a vault road, not a Catalyst road", function()
        claimTheReward()
        local pick = pickFor("Legs")
        assert.is_table(pick)
        assert.equal(ns.Roads.KIND_VAULT, pick.kind)
        assert.equal(LEGS, pick.item.itemID)
        -- Nothing about it is a conversion, so its row says neither "into the
        -- tier legs" nor anything about a charge.
        assert.is_nil(pick.becomes)
        assert.is_nil(pick.catalyzed)
    end)

    -- And with the reward still in the vault - his 14:31 screen, the window
    -- open - the road reads what he actually saw that afternoon: the level the
    -- vault offers it at, and the level his run upgraded it to.
    it("reads the vault's own level while the reward is still in it", function()
        local pick = pickFor("Legs")
        assert.equal(ns.Roads.KIND_VAULT, pick.kind)
        assert.equal(315, pick.arrivesAt)
        assert.equal(321, pick.rating.level)
        assert.equal("Enigmatic Dreamwatcher's Leggings", pick.item.name)
        assert.equal("Grab these - crest it after.", ns.Roads.ItemSentence(answerFor("Legs", pick.keys[1])))
    end)

    -- Defect 1, on the screen that filed it. Proven red by restoring the level
    -- gate (`if level and arrivesAt and level < arrivesAt then return false
    -- end`): the sentence goes back to "Skip this one, the plan uses the vault
    -- legs."
    it("calls the part-way crested copy the pick and says what is left", function()
        claimTheReward()
        local held = crestedTo318()
        local pick = pickFor("Legs")
        assert.equal(321, pick.arrivesAt)
        assert.is_true(ns.Roads.IsArrivedPick(held, pick))
        assert.is_true(ns.Roads.ArrivedShort(held, pick))
        local answer = answerFor("Legs", held.key)
        -- No road carries this key, so the line under the sentence still says
        -- the document has never seen this copy. No rating is invented.
        assert.is_nil(answer.own)
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, answer.phrase)
        -- Once the reward is out of the vault there is no vault record left to
        -- read a name off, and the road's name on the real screen comes from
        -- `RoadsCache.FillNames`, which `Roads.ForSlot` alone does not run. So
        -- the sentence here says the slot's own word, and the owner's own words
        -- are what it says once the road is named.
        assert.equal("Crest these to 321 - then refresh.", ns.Roads.ItemSentence(answer))
        pick.item.name = "Enigmatic Dreamwatcher's Leggings"
        assert.equal("Crest these to 321 - then refresh.", ns.Roads.ArrivedSentence(held, pick))
        -- The pick's own row says the reward is out of the vault.
        assert.equal(ns.Roads.VAULT_CLAIMED, pick.claimed)
        assert.equal("claimed · in your bags", pick.claimed)
    end)

    -- The worn variant, and the one refusal R-3e did NOT touch. A WORN copy of
    -- a vault pick is still not recognised, because nothing the client says
    -- tells it from a twin the player already had on (R-3b's measurement: the
    -- vault offered the Worldroot at 305 while he wore 308). R-3e took the
    -- LEVEL out of the identity and left the placement rule exactly where the
    -- evidence stops, so this copy reads as what the plan does instead - and
    -- the worn sentence itself is the cloak's, above.
    it("still refuses a worn copy of a vault pick, level or no level", function()
        claimTheReward()
        local held = crestedTo318()
        held.location = "equipped"
        local pick = pickFor("Legs")
        assert.is_false(ns.Roads.IsArrivedPick(held, pick))
        -- And the sentence itself, asked directly, is the one the cloak reads.
        held.location = "equipped"
        assert.equal("Crest these to 321 - then refresh.", ns.Roads.ArrivedSentence(held, pick))
    end)

    -- The other state the same afternoon could have been in, and the reason the
    -- kind is decided on the SOURCE rather than on the join's answer: a refresh
    -- whose vault read came back with nothing in it. That happens - it is
    -- M3-16b's whole subject (WKE-583, reset day) - and with no rewards to
    -- vouch for anything the join falls back on its conservative reading and
    -- hands over a conversion it cannot name. The road must still be the
    -- vault's: unnamed means unknown, and a reward the plan takes out of the
    -- vault is a vault road either way.
    --
    -- Proven red by putting `if conversion then return Roads.KIND_CATALYST end`
    -- back at the top of `setItemKind`: the kind goes to `catalyst`, `becomes`
    -- comes back as the leggings themselves and `catalyzed` as true - the
    -- owner's own row, "Catalyst · ... (321) · into the tier legs".
    it("keeps the vault road a vault road when the vault read came back empty", function()
        for _, option in ipairs(inputs.vault.options) do
            option.rewards = {}
        end
        local pick = pickFor("Legs")
        assert.equal(ns.Roads.KIND_VAULT, pick.kind)
        assert.is_nil(pick.becomes)
        assert.is_nil(pick.catalyzed)
        -- With nothing to read the reward's level off, the road arrives at the
        -- level the document carries and says so; the vault's own 315 is not
        -- invented.
        assert.equal(321, pick.arrivesAt)
        -- And the join's conservative count is untouched: with no snapshot to
        -- vouch for anything, a vault tier clone is still a charge (M3-15).
        assert.equal(1, #ns.QEImport.CatalyzedVault(inputs.verdicts[1].verdict, inputs.vault))
    end)

    -- Defect 2 on the week's sentence (M3-14's one charge, WKE-555). Proven red
    -- the same way as the kind: with the Catalyst-first rule back, the join
    -- counts the leggings and the sentence spends the charge on them.
    it("sends the one charge to the bag shoulders and never to the leggings", function()
        claimTheReward()
        local plan = ns.Roads.PlanSentence({
            verdicts = inputs.verdicts,
            highlightedScenario = "thisWeek",
            inventory = inputs.inventory,
            vault = inputs.vault,
            currencies = inputs.currencies,
        })
        assert.equal("Grab the legs from the vault. Catalyst the Lynx shoulders in your bag.", plan.sentence)
        assert.is_nil(plan.footnote)
        -- And the join itself: the leggings are not a conversion under either of
        -- the two questions it asks.
        for _, conversion in ipairs(ns.QEImport.CatalyzedOwned(inputs.verdicts[1].verdict, inputs.inventory)) do
            assert.is_true(conversion.item.itemID ~= LEGS)
        end
        for _, conversion in ipairs(ns.QEImport.CatalyzedVault(inputs.verdicts[1].verdict, inputs.vault)) do
            assert.is_true(conversion.item.itemID ~= LEGS)
        end
    end)

    -- V-3 (WKE-587): the same week, once the addon knows the reward is out of
    -- the vault. The clause that sends him there goes and the Catalyst step -
    -- still this week's plan - stays. Nothing else about the sentence moves.
    --
    -- Proven red by dropping the `not week.vaultClaimed` guard from
    -- `PlanSentence`: the sentence goes back to "Grab the legs from the vault.",
    -- which is the tab telling him to fetch what he is already wearing.
    it("drops the vault clause once the reward has been claimed", function()
        claimTheReward()
        local week = {
            verdicts = inputs.verdicts,
            highlightedScenario = "thisWeek",
            inventory = inputs.inventory,
            vault = inputs.vault,
            currencies = inputs.currencies,
        }
        assert.equal(
            "Grab the legs from the vault. Catalyst the Lynx shoulders in your bag.",
            ns.Roads.PlanSentence(week).sentence
        )
        week.vaultClaimed = true
        local claimed = ns.Roads.PlanSentence(week)
        assert.equal("Catalyst the Lynx shoulders in your bag.", claimed.sentence)
        assert.is_nil(claimed.sentence:find("vault", 1, true))
    end)
end)

-- ---------------------------------------------------------------------------
-- The parts that need no week around them.

describe("Roads vocabulary", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("keeps the phrases exactly as the brief writes them", function()
        assert.equal("not rated · new since the last refresh", ns.Roads.PHRASE_NOT_RATED_NEW)
        assert.equal("not rated · beyond the rating's item limit", ns.Roads.PHRASE_NOT_RATED_LIMIT)
        assert.equal("not in your best set", ns.Roads.PHRASE_NOT_IN_BEST_SET)
        assert.equal("no rating", ns.Roads.PHRASE_NO_RATING)
        -- The fifth is C-11's (WKE-572), and it is a RATED phrase: an item the
        -- plan's own pass never saw, which a later pass put in its best set.
        assert.equal("rated · better than what you wear", ns.Roads.PHRASE_RATED_LATER)
        assert.equal(5, #ns.Roads.PHRASES)
    end)

    it("keeps the verb table to the five verbs that go somewhere", function()
        assert.same({ "Show item", "Show run", "Show in vault", "Options", "Refresh" }, ns.Roads.VERBS)
    end)

    it("names the four plans plainly and names no source", function()
        assert.same({
            asOffered = "as offered",
            catalyzed = "catalyzed",
            thisWeek = "this week's picks",
            maxed = "everything upgraded",
        }, ns.Roads.PLAN_LABEL)
        -- A name this build does not know is shown as itself rather than
        -- translated into one of the four.
        assert.equal("somethingElse", ns.Roads.PlanName("somethingElse"))
        assert.is_nil(ns.Roads.PlanName(nil))
    end)

    it("shortens an item the way a player says it", function()
        -- Every name below is one the owner's own files carry.
        assert.equal(
            "the Lynx shoulders",
            ns.Roads.ShortName({ name = "Venom-Cursed Lynx's Spaulders", slot = "Shoulder" })
        )
        assert.equal("the Hide chest", ns.Roads.ShortName({ name = "Hide of Pestilence", slot = "Chest" }))
        assert.equal("the Worldroot", ns.Roads.ShortName({ name = "Lightgrasp Worldroot", slot = "2H Weapon" }))
        assert.equal("the Spaulders", ns.Roads.ShortName({ name = "Scavenger's Spaulders" }))
        -- The client's own word for the type wins when a caller has one.
        assert.equal(
            "the staff",
            ns.Roads.ShortName({ name = "Lightgrasp Worldroot", slot = "2H Weapon", subType = "Staff" })
        )
        -- Nothing to shorten: the slot's own word, and then nothing at all.
        assert.equal("the shoulders", ns.Roads.ShortName({ slot = "Shoulder" }))
        assert.is_nil(ns.Roads.ShortName({}))
        assert.is_nil(ns.Roads.ShortName(nil))
    end)

    it("shows a zero as the phrase and a number with its sign", function()
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, ns.Roads.ItemBadge(0))
        assert.equal("+3.07%", ns.Roads.ItemBadge(3.07))
        assert.equal("-1.25%", ns.Roads.ItemBadge(-1.25))
        assert.is_nil(ns.Roads.ItemBadge(nil))
    end)

    it("says a charge as the client's two numbers and never as arithmetic", function()
        assert.equal("1 held, 8 max", ns.Roads.ChargeText({ held = 1, max = 8 }))
        assert.equal("1 held", ns.Roads.ChargeText({ held = 1 }))
        assert.is_nil(ns.Roads.ChargeText({}))
        assert.is_nil(ns.Roads.Charge({ ok = false }))
        assert.is_nil(ns.Roads.Charge({ ok = true }))
    end)

    it("refuses anything that is not a slot", function()
        local roads = ns.Roads.ForSlot(nil, {})
        assert.same({}, roads.groups[ns.Roads.GROUP_SET])
        assert.same({}, ns.Roads.ForItem(nil, {}).others)
    end)
end)

-- ---------------------------------------------------------------------------
-- R-3d (WKE-584): the vault reward the rating never imported.
--
-- The owner's screen of 2026-09-15, reset day, the Great Vault window open:
-- hovering the vault's Enigmatic Dreamwatcher's Leggings read "not in your best
-- set" and "Skip this one, the plan uses your Miststalker legs", off a verdict
-- rated 80 minutes earlier from a profile carrying `0 vault` (M3-16b, WKE-583).
-- Both of those are the addon taking a position on an item nothing ever rated,
-- which principle 3 forbids.
--
-- The vault here is the real one: snapshot 12 of
-- `spec/fixtures/captures/Lootpath-20260915-142722-vault.lua`, the hand capture
-- he took with the window open, whose 9 links carry three gear rewards - the
-- Lantern (Offhand, 279), the Leggings (Legs, 315) and Kyrakka's (Trinket,
-- 315). The document over it is the committed `thisWeek` Dungeon export of the
-- 09-09 run, a run over a DIFFERENT week's profile that therefore names none of
-- the three: exactly the shape the owner hit.
describe("Roads over a vault the rating never imported (R-3d)", function()
    local ns, world, inputs
    local RESET_DAY = "spec/fixtures/captures/Lootpath-20260915-142722-vault.lua"
    local AFTER_THE_WINDOW = 12
    -- Read off the snapshot above by `ns.Vault.Options()`, 2026-09-15.
    local LEGGINGS = "271527:6652:12844:13440:13693:13698"
    local LANTERN = "275547:6652:12825"
    local KYRAKKA = "193748:6652:12699:12844:13440"

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
        R.vault(world, R.snapshot("vault", AFTER_THE_WINDOW, RESET_DAY))

        local inventory = ns.Inventory.Scan()
        assert.is_true(inventory.ok, inventory.reason)
        local vault = ns.Vault.Options()
        assert.is_true(vault.ok, vault.reason)

        local parsed = ns.QEImport.Parse(readFile(THIS_WEEK_DUNGEON))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = "thisWeek"

        inputs = {
            verdicts = { { verdict = parsed.verdict, scenario = "thisWeek" } },
            highlightedScenario = "thisWeek",
            inventory = inventory,
            vault = vault,
            now = 1789500000,
        }
    end)

    after_each(function()
        H.unload()
    end)

    local function verdict()
        return inputs.verdicts[1].verdict
    end

    -- The vault road of a slot, and the group it landed in. Asked of all three
    -- gear rewards below, so every assertion is about the whole vault and not
    -- about one lucky row.
    local function vaultRoad(slot)
        for _, group in ipairs(ns.Roads.GROUP_ORDER) do
            for _, road in ipairs(ns.Roads.ForSlot(slot, inputs).groups[group] or {}) do
                if road.kind == ns.Roads.KIND_VAULT then
                    return road, group
                end
            end
        end
    end

    -- PROVEN RED: without the `profileVaultCount` branch in
    -- `Roads.VaultConsidered` every one of these three reads "not in your best
    -- set" in the SET group, which is the screen the owner read.
    it("says nothing rated a reward when the run's profile carried no vault section", function()
        verdict().profileVaultCount = 0
        for _, slot in ipairs({ "Legs", "Offhand", "Trinket" }) do
            local road, group = vaultRoad(slot)
            assert.is_table(road, slot)
            assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, road.phrase, slot)
            assert.equal("not rated · new since the last refresh", road.phrase)
            assert.equal(ns.Roads.GROUP_NONE, group, slot)
            assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, road.rating.badge, slot)
            -- Not knowing is not a verdict, so the row does not glow and the
            -- surfaces owe it no imperative (principles 12 and 16).
            assert.is_false(ns.Roads.IsForward(road))
            assert.is_false(ns.Roads.IsRated(road))
        end
    end)

    -- The other half of the same screen: the sentence. It is owed one
    -- (principle 16 - the vault is offering it) and it may not be "Skip this
    -- one" (principle 3).
    it("gives that reward the stale sentence and never a position on it", function()
        verdict().profileVaultCount = 0
        local answer = ns.Roads.ForItem(LEGGINGS, inputs)
        assert.equal("Legs", answer.slot)
        assert.equal(ns.Roads.KIND_VAULT, answer.own.kind)
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, answer.phrase)
        assert.equal("Not rated yet - refresh.", ns.Roads.ItemSentence(answer))
        assert.equal(ns.Roads.NOT_RATED_YET_SENTENCE, ns.Roads.ItemSentence(answer))
    end)

    -- The pool says it too, with no count at all: a document that recorded what
    -- it WAS shown and does not name these rewards is the same evidence.
    it("says the same off a recorded pool that holds none of the rewards", function()
        verdict().considered = ns.Companion.Excluded({
            { slot = "Legs", name = "Miststalker's Leggings", level = 298, itemID = 277774, bonusIDs = { 12 } },
        })
        for _, slot in ipairs({ "Legs", "Offhand", "Trinket" }) do
            local road, group = vaultRoad(slot)
            assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, road.phrase, slot)
            assert.equal(ns.Roads.GROUP_NONE, group, slot)
        end
    end)

    -- And the first case, unchanged: a pool that DID hold the reward and a best
    -- set that did not take it is rated and passed over, which is the third
    -- phrase and has been since 558.
    it("keeps the third phrase for a reward the pool really held", function()
        verdict().considered = ns.Companion.Excluded({
            {
                slot = "Legs",
                name = "Enigmatic Dreamwatcher's Leggings",
                level = 315,
                itemID = 271527,
                bonusIDs = { 6652, 12844, 13440, 13693, 13698 },
            },
        })
        local road, group = vaultRoad("Legs")
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, road.phrase)
        assert.equal(ns.Roads.GROUP_SET, group)
        assert.is_true(ns.Roads.IsRated(road))
        -- Its neighbours are not in that pool, so they read the other case: the
        -- question is asked per reward and never per file.
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, (vaultRoad("Offhand")).phrase)
    end)

    -- The bound. A verdict that recorded neither a pool nor a count cannot
    -- answer the question, so C-8's premise is what stands: every file written
    -- before C-11 and every paste is this case, and none of them changes.
    it("leaves a document that recorded nothing where 558 left it", function()
        assert.is_nil(verdict().considered)
        assert.is_nil(verdict().profileVaultCount)
        local road, group = vaultRoad("Legs")
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, road.phrase)
        assert.equal(ns.Roads.GROUP_SET, group)
        assert.is_nil(ns.Roads.VaultConsidered(inputs.verdicts[1], inputs, { key = LANTERN }))
    end)

    -- A later pass's pool answers too: a vault option is a baseline card, so it
    -- is in every pass's pool or in none of them (C-11).
    it("reads a later pass's pool as readily as the plan's own", function()
        verdict().considered = ns.Companion.Excluded({
            { slot = "Legs", name = "Miststalker's Leggings", level = 298, itemID = 277774, bonusIDs = { 12 } },
        })
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, (vaultRoad("Trinket")).phrase)
        inputs.passes = {
            {
                pass = 2,
                verdict = {
                    considered = ns.Companion.Excluded({
                        {
                            slot = "Trinket",
                            name = "Kyrakka's Searing Embers",
                            level = 315,
                            itemID = 193748,
                            bonusIDs = { 6652, 12699, 12844, 13440 },
                        },
                    }),
                },
            },
        }
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, (vaultRoad("Trinket")).phrase)
        assert.is_true(ns.Roads.VaultConsidered(inputs.verdicts[1], inputs, {
            key = KYRAKKA,
            name = "Kyrakka's Searing Embers",
            itemLevel = 315,
        }))
    end)

    -- The Vault tab's headline. A plan rated before the vault existed is not a
    -- decision about the vault, so the tab says the one true thing instead of
    -- reading a pick out of it.
    it("replaces the week's plan with its own cure when the run had no vault", function()
        local before = ns.Roads.PlanSentence(inputs)
        assert.is_string(before.sentence)
        assert.not_equal(ns.Roads.VAULT_UNRATED_SENTENCE, before.sentence)
        verdict().profileVaultCount = 0
        local plan = ns.Roads.PlanSentence(inputs)
        assert.equal("Your vault was generated after this rating. Refresh.", plan.sentence)
        assert.equal(ns.Roads.VAULT_UNRATED_SENTENCE, plan.sentence)
        assert.equal("this week's picks", plan.plan)
    end)
end)
