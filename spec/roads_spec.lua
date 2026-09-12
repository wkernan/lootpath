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
        assert.equal("this week's plan", pick.plan)
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
        assert.equal("do: take one vault reward", road.todo)
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
        assert.equal("do: run the key · tick when it drops", road.todo)
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
        assert.equal(ns.Roads.CRAFT_NOT_READ, craft.steps[1].text)
        assert.equal("do: get the spark, then order it", craft.todo)

        assert.is_table(delve)
        assert.equal(ns.Roads.TAG_DELVES, delve.tag)
        assert.equal(321, delve.arrivesAt)
        assert.equal("+2.17%", delve.rating.badge)
        -- No delve step exists until a delve capture does, and a row with no
        -- step to name carries no imperative either.
        assert.equal(ns.Roads.DELVE_NOT_READ, delve.steps[1].text)
        assert.is_nil(delve.todo)
        assert.is_nil(delve.verb)
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

    it("answers for the item under the cursor with its own road and two others", function()
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
        assert.equal(2, #answer.others)
        -- One per remaining group, in group order, never a second row of the
        -- group the hovered item is already in.
        assert.equal(ns.Roads.GROUP_ITEM, answer.others[1].group)
        assert.equal(ns.Roads.GROUP_NONE, answer.others[2].group)
        assert.is_nil(answer.phrase)
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
        assert.equal("do: take one vault reward", answer.own.todo)
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
        assert.equal("The plan would catalyst the Hide chest too, but you've only got one charge.", plan.footnote)
        assert.equal("this week's plan", plan.plan)
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
-- The parts that need no week around them.

describe("Roads vocabulary", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("keeps the four phrases exactly as the brief writes them", function()
        assert.equal("not rated · new since the last refresh", ns.Roads.PHRASE_NOT_RATED_NEW)
        assert.equal("not rated · beyond the rating's item limit", ns.Roads.PHRASE_NOT_RATED_LIMIT)
        assert.equal("not in your best set", ns.Roads.PHRASE_NOT_IN_BEST_SET)
        assert.equal("no rating", ns.Roads.PHRASE_NO_RATING)
        assert.equal(4, #ns.Roads.PHRASES)
    end)

    it("keeps the verb table to the five verbs that go somewhere", function()
        assert.same({ "Show item", "Show run", "Show in vault", "Options", "Refresh" }, ns.Roads.VERBS)
    end)

    it("names the four plans plainly and names no source", function()
        assert.same({
            asOffered = "as offered",
            catalyzed = "catalyzed",
            thisWeek = "this week's plan",
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
