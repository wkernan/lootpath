-- spec/roadsrow_spec.lua (R-3, WKE-564)
-- Roads as the Upgrade Map slot's row, and the Vault tab's headline as the
-- week's plan sentence, over the owner's own week.
--
-- The inputs are the same week R-1 built the model on, so that every figure
-- asserted here was read out of a committed file and can be checked against
-- `spec/roads_spec.lua` line for line:
--
--   * `spec/fixtures/captures/Lootpath-20260908-124527.lua` - inventory
--     snapshot 7 and vault snapshot 9 (the Lantern, the Worldroot, the
--     Spaulders, the Graft).
--   * the FOUR Dungeon scenario documents of the 2026-09-09 19:22 run -
--     `asOffered`, `catalyzed`, `thisWeek`, `maxed` - imported the way the
--     companion writes them, so the panel picks the highlight the way the
--     window does.
--   * the SIX Upgrade Finder documents of the 2026-09-08 22:47 run. Five are
--     Dungeon (+2, +4, +6, +8, +10) and one is Raid; with the content type set
--     to Dungeon the panel reads the five, which is what it does in the client.
--   * the 2026-09-06 20:09 cold journal walk (478 drops, previewed at keystone
--     10) and the 2026-09-08 23:04 currency transcript. That transcript
--     predates the by-ID probe (M3-11, WKE-546), so the Catalyst charge is
--     driven through the stub's `currencyByID` exactly as `roads_spec` drives
--     it, with the 1 of 8 the owner read off his own tooltip.
--
-- Nothing below asserts a number this build produced without a fixture behind
-- it, and every guard was proven red one at a time before it was kept.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local CAPTURE = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
local CURRENCIES = "spec/fixtures/captures/Lootpath-20260908-230426.lua"
local PROFILE_SNAPSHOT = 7
local VAULT_SNAPSHOT = 9
local CURRENCY_SNAPSHOT = 2

local SCENARIO_FILES = {
    asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
    catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
    thisWeek = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json",
    maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
}
local SCENARIO_ORDER = { "asOffered", "catalyzed", "thisWeek", "maxed" }

local UPGRADE_DOCUMENTS = {
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lrxljklscrjr.json", keyLevel = 2, contentType = "Dungeon" },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-jnjnmzftoppb.json", keyLevel = 4, contentType = "Dungeon" },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-zmtnpejwfewe.json", keyLevel = 6, contentType = "Dungeon" },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lttldhvkiqlr.json", keyLevel = 8, contentType = "Dungeon" },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-wyharestkdyr.json", keyLevel = 10, contentType = "Dungeon" },
    { file = "spec/fixtures/qe/qe-upgradefinder-Hotornot-ynfzbppepnzw.json", keyLevel = 10, contentType = "Raid" },
}

local CATALYST = {
    name = "Venomblight Manaflux",
    currencyID = 3465,
    isHeader = false,
    quantity = 1,
    maxQuantity = 8,
}

-- The words no player-facing string R-3 puts on screen may contain. The first
-- three are the source rule (owner's decision, 2026-09-11); the last three are
-- the phrasings the brief struck, each of which says "nothing happened" without
-- saying what would change it. The older wording elsewhere on these tabs -
-- `Panel.NOTE` and the M3-3 value badges - is 569's sweep (V-1) and is not what
-- this list is checked against.
local FORBIDDEN = { "QE Live", "his", "verdict", "not asked", "no document", "next:" }

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

-- Whole words only, and case-insensitively: "this" is not "his", and "Verdict"
-- would be as wrong as "verdict".
local function usesForbidden(text)
    if type(text) ~= "string" then
        return nil
    end
    for _, word in ipairs(FORBIDDEN) do
        -- Built from the LOWERCASED word, never lowercased afterwards: `%A` and
        -- `%a` are two different classes and `pattern:lower()` would quietly
        -- turn the closing frontier into the opening one.
        local pattern = word:lower():gsub("%p", "%%%0")
        if word:match("^%a") then
            pattern = "%f[%a]" .. pattern
        end
        if word:match("%a$") then
            pattern = pattern .. "%f[%A]"
        end
        if text:lower():find(pattern) then
            return word
        end
    end
    return nil
end

describe("Roads as the Upgrade Map slot's row, over the owner's week of 2026-09-08", function()
    local ns, world, gathered

    local function scenarioExports()
        local exports = {}
        for _, name in ipairs(SCENARIO_ORDER) do
            exports[#exports + 1] = {
                schema = "qe-live-droptimizer",
                contentType = "Dungeon",
                scenario = name,
                qeSettings = {
                    autoUpgradeVault = name == "maxed" or name == "thisWeek",
                    autoUpgradeAll = name == "maxed",
                    autoCatalyze = name ~= "asOffered",
                },
                json = readFile(SCENARIO_FILES[name]),
            }
        end
        for _, entry in ipairs(UPGRADE_DOCUMENTS) do
            exports[#exports + 1] = {
                schema = "qe-live-upgradefinder",
                contentType = entry.contentType,
                keyLevel = entry.keyLevel,
                json = readFile(entry.file),
            }
        end
        return exports
    end

    before_each(function()
        ns, world = H.load()
        ns.UI.Options.Set("Dungeon")
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
        R.vault(world, R.snapshot("vault", VAULT_SNAPSHOT, CAPTURE))
        world.currencyByID = { [3465] = CATALYST }
        ns.db.global.captures.journal = { R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ) }

        local imported = ns.Companion.ImportAll({ writtenAt = "2026-09-09T19:22:00Z", exports = scenarioExports() })
        assert.is_true(imported.ok, imported.reason)
        assert.equal(0, #imported.skipped, imported.skipped[1] and imported.skipped[1].reason)

        -- Everything the panel reads in the client, read the same way: this is
        -- `Panel.Gather`'s own answer, so a model built on it is the model the
        -- window builds.
        gathered = ns.UpgradeMapPanel.Gather({ db = ns.db })
        -- The currency transcript predates the by-ID probe; the charge is the
        -- owner's own tooltip reading, exactly as roads_spec drives it.
        local currencies = ns.Currencies.Read({ snapshot = R.snapshot("currencies", CURRENCY_SNAPSHOT, CURRENCIES) })
        assert.is_true(currencies.ok)
        currencies.catalyst = CATALYST
        currencies.catalystCharges = CATALYST.quantity
        currencies.catalystMax = CATALYST.maxQuantity
        gathered.currencies = currencies
    end)

    after_each(function()
        H.unload()
    end)

    local function model(opts)
        for key, value in pairs(opts or {}) do
            gathered[key] = value
        end
        return ns.UpgradeMapPanel.Model(gathered)
    end

    local function section(m, slot)
        for _, entry in ipairs(m.slots) do
            if entry.slot == slot then
                return entry
            end
        end
        return nil
    end

    local function lineOf(group, index)
        return ns.UpgradeMapPanel.RoadLineText(group.rows[index])
    end

    local function elements(m, state)
        return ns.UpgradeMapPanel.Elements(m, state)
    end

    -- Every other slot shut and this one OPEN by a saved click: since UX-6
    -- (WKE-637) a slot with no saved click follows the first-worth-taking rule,
    -- so a test that wants one slot open says so (`false` is "opened").
    local function shutAllBut(m, slot)
        local shut = {}
        for _, entry in ipairs(m.slots) do
            shut[entry.slot] = entry.slot ~= slot
        end
        return { slots = shut }
    end

    -- -----------------------------------------------------------------------
    -- The four documents really are on the shelf, and the highlight is the one
    -- the Vault tab follows.

    it("reads all four plans and follows the one the Vault tab is set to", function()
        local m = model()
        assert.equal(4, #gathered.scenarios)
        assert.equal("thisWeek", gathered.highlightScenario)
        assert.is_true(m.hasRoads)
        assert.equal(5, #m.upgradeDocuments)
    end)

    -- -----------------------------------------------------------------------
    -- The shoulder slot, group by group, against the canvas.

    it("heads the shoulder section with the slot's own sentence, in chat voice", function()
        local shoulder = section(model(), "Shoulder")
        assert.equal("Catalyst your Lynx shoulders, skip the vault ones, no crests here.", shoulder.plan)
    end)

    it("gives the shoulder slot three groups in the model's fixed order", function()
        local groups = section(model(), "Shoulder").roadGroups
        assert.equal(3, #groups)
        assert.same(
            { ns.Roads.GROUP_SET, ns.Roads.GROUP_ITEM, ns.Roads.GROUP_NONE },
            { groups[1].group, groups[2].group, groups[3].group }
        )
        assert.equal(
            "Your best set · this week's picks · the pick first, then the rated alternatives",
            groups[1].header
        )
        assert.equal(
            "Other rated sources · percents are against what you wear · at your key's preview level, per the client",
            groups[2].header
        )
        assert.equal("No rating", groups[3].header)
    end)

    it("draws the shoulder pick and the vault option the canvas draws", function()
        local groups = section(model(), "Shoulder").roadGroups
        assert.equal(2, #groups[1].rows)
        assert.equal(
            "Catalyst · Venom-Cursed Lynx's Spaulders (295) · into the tier shoulders · in your best set"
                .. " · the same charge as the vault Spaulders road · do: Catalyst it · charge 1 held, 8 max",
            lineOf(groups[1], 1)
        )
        assert.equal(
            "Vault · open now · Scavenger's Spaulders (308) · into the tier shoulders · upgraded to 321"
                .. " · 1.73% behind · taking the vault weapon instead"
                .. " · the same charge as the Catalyst road: one of these, not both"
                .. " · crest type and cost not readable · reset in 6d 21h",
            lineOf(groups[1], 2)
        )
        -- The pick carries the gold edge and the other row does not.
        assert.is_true(groups[1].rows[1].planPick)
        assert.is_false(groups[1].rows[2].planPick)
    end)

    -- -----------------------------------------------------------------------
    -- The head slot, drawn: R-3a's defect as the owner saw it (WKE-570).

    it("ends the head row rated behind the worn helm with the plan's own words", function()
        local head = section(model(), "Head")
        assert.equal("Keep what you've got on, no crests here.", head.plan)
        local groups = head.roadGroups
        assert.equal(2, #groups[1].rows)
        assert.equal(
            "Keep (what you wear) · Enigmatic Dreamwatcher's Somnolent Stare (308) · what you wear now"
                .. " · in your best set · nothing to do",
            lineOf(groups[1], 1)
        )
        -- The second copy of it, in his bags. This row used to end
        -- "do: equip it": the defect, on a row rated 0.95% behind the helm
        -- the row above says to keep. (The headless client knows no name for
        -- this key, so the row says the item ID; on the owner's screen it was
        -- the helm's own name.)
        assert.equal(
            "In your bags · item 271528 (308) · 0.95% behind · keep what you've got on",
            lineOf(groups[1], 2)
        )
    end)

    it("draws no imperative anywhere on a row the plan is not going forward on", function()
        local m = model()
        local rows, imperatives = 0, 0
        for _, entry in ipairs(m.slots) do
            for _, group in ipairs(entry.roadGroups or {}) do
                for _, row in ipairs(group.rows) do
                    rows = rows + 1
                    local line = ns.UpgradeMapPanel.RoadLineText(row)
                    if line:find(" · do: ", 1, true) then
                        imperatives = imperatives + 1
                        assert.is_true(ns.Roads.IsForward(row.road), line)
                    end
                end
            end
        end
        assert.is_true(rows > 300)
        assert.is_true(imperatives > 0)
        -- The one line the owner photographed is gone from the whole screen.
        for _, entry in ipairs(m.slots) do
            for _, group in ipairs(entry.roadGroups or {}) do
                for _, row in ipairs(group.rows) do
                    if row.todo == "do: equip it" then
                        assert.is_true(ns.Roads.IsForward(row.road), lineOf(group, 1))
                    end
                end
            end
        end
    end)

    it("values the shoulder Mythic+ row at the level the client previews", function()
        local groups = section(model(), "Shoulder").roadGroups
        assert.equal(
            "Mythic+ · Scavenger's Spaulders (305) · The Hoardmonger - Den of Nalorakk, Mythic+ 10"
                .. " · not in your best set · upgraded 321 at +0.38%"
                .. " · crest type and cost not readable",
            lineOf(groups[2], 5)
        )
    end)

    -- M5-3a: a drop road draws a journal entry, and the hover has to read at
    -- the level the row prints. The cold 2026-09-06 20:09 walk this file is
    -- built on is one the aggregator kept links on, so the rows carry them.
    it("carries the drop's own link onto its road row", function()
        local groups = section(model(), "Shoulder").roadGroups
        local drop
        for _, group in ipairs(groups) do
            for _, row in ipairs(group.rows) do
                if row.kind == ns.Roads.KIND_DROP and row.link then
                    drop = drop or row
                end
            end
        end
        assert.is_table(drop, "no drop road carried a link")
        assert.equal(drop.itemID, tonumber(drop.link:match("|Hitem:(%d+)")))
        assert.is_nil(drop.levelNote)

        -- A road whose entry has no link - every entry of a cache written
        -- before M5-3a - says at what level the client is about to draw it.
        local bare = ns.UpgradeMapPanel.RoadRow({
            kind = ns.Roads.KIND_DROP,
            item = { itemID = drop.itemID, name = "Scavenger's Spaulders" },
            source = { difficultyID = 8 },
            arrivesAt = 305,
        }, 10)
        assert.is_nil(bare.link)
        assert.equal("shown at its base level - /lootpath capture journal to read it at +10", bare.levelNote)

        -- M5-3b: what the hover checks the link's own tooltip against. A drop
        -- road arrives at a level a walk previewed; a road named by a document
        -- does not, and carries neither number, so the line can never reach it.
        assert.equal(drop.itemLevel, drop.dropLevel)
        assert.equal(305, bare.dropLevel)
        assert.equal(10, bare.keyLevel)
        local raid = ns.UpgradeMapPanel.RoadRow({
            kind = ns.Roads.KIND_DROP,
            item = { itemID = drop.itemID, name = "Scavenger's Spaulders" },
            source = { difficultyID = 16 },
            arrivesAt = 311,
        }, 10)
        assert.equal(311, raid.dropLevel)
        assert.is_nil(raid.keyLevel)
        local upgrade = ns.UpgradeMapPanel.RoadRow({
            kind = ns.Roads.KIND_UPGRADE,
            item = { itemID = drop.itemID, name = "Scavenger's Spaulders" },
            source = { difficultyID = 8 },
            arrivesAt = 321,
        }, 10)
        assert.is_nil(upgrade.dropLevel)
        assert.is_nil(upgrade.keyLevel)
    end)

    -- WKE-530 finding 4 survives the change of rows: the client answers item
    -- level 1 for a cosmetic or a quest drop, so those are hidden and counted,
    -- and the section still says how many rather than listing them.
    it("keeps the item-level-1 drops out of the roads and still says how many", function()
        local m = model()
        assert.equal(6, m.counts.hiddenLevelOne)
        local head = section(m, "Head")
        assert.equal(5, head.hiddenLevelOne)
        for _, group in ipairs(head.roadGroups) do
            for _, row in ipairs(group.rows) do
                assert.is_true(row.itemLevel ~= ns.UpgradeMapPanel.HIDDEN_ITEM_LEVEL)
            end
        end
        -- ...and since UX-6 (WKE-637) the note is on the slot line's hover, not
        -- under the open slot: it explains the list, it is not part of it.
        local state = shutAllBut(m, "Head")
        local said = false
        for _, element in ipairs(ns.UpgradeMapPanel.Elements(m, state)) do
            said = said or element.text == head.hiddenNote
        end
        assert.is_false(said)
        local hovered = 0
        for _, line in ipairs(ns.UpgradeMapPanel.SlotTooltipLines(head)) do
            if line == head.hiddenNote then
                hovered = hovered + 1
            end
        end
        assert.equal(1, hovered)
        -- The printed list says it too, and exactly once.
        local printed = 0
        for _, line in ipairs(ns.UpgradeMapPanel.Lines(m)) do
            if line == "  " .. head.hiddenNote then
                printed = printed + 1
            end
        end
        assert.equal(1, printed)
    end)

    it("puts upgrading what you wear in the no-rating group, with what you hold", function()
        local groups = section(model(), "Shoulder").roadGroups
        assert.equal(
            "Upgrade · Seedpods of the Luminous Bloom (289) · no rating · "
                .. ns.Roads.CREST_NOT_READ
                .. " · you hold 356 Adventurer Mistcrest, 2 Champion Mistcrest,"
                .. " 21 Hero Mistcrest, 20 Myth Mistcrest",
            lineOf(groups[3], 1)
        )
    end)

    -- R-3c (WKE-580): the same road, where the `maxed` document HAS an answer.
    -- The cloak on the character is 298 and that document carries it at 308 in
    -- its top set, so the row says what upgrading it is worth instead of "no
    -- rating", and it names the run it read - the only row on this panel whose
    -- plan is not the group's.
    it("rates the Upgrade road out of the maxed document and names that plan", function()
        local back = section(model(), "Back")
        local row
        for _, entry in ipairs(back.roadGroups) do
            for _, candidate in ipairs(entry.rows) do
                row = row or (candidate.kind == ns.Roads.KIND_CREST and candidate or nil)
            end
        end
        assert.is_table(row)
        assert.equal(308, row.itemLevel)
        assert.equal("in your best set", row.badge.text)
        assert.equal("rated under everything upgraded", row.second)
        -- The group header still names the plan the screen is following, off
        -- the pick rather than off this row.
        assert.equal("this week's picks", ns.UpgradeMapPanel.RoadPlanName(back.roads))
    end)

    -- The same rule where the owner's own week cannot reach it: a slot whose
    -- Upgrade road comes FIRST in the group, or is the only road in it. The
    -- header must still name the plan the screen is following, or nothing -
    -- never the `maxed` run the Upgrade road always reads.
    it("never lets the Upgrade road name the plan the group header follows", function()
        local crest = { kind = ns.Roads.KIND_CREST, plan = "everything upgraded", keys = {} }
        local pick = { kind = ns.Roads.KIND_KEEP, plan = "this week's picks", keys = {} }
        assert.equal(
            "this week's picks",
            ns.UpgradeMapPanel.RoadPlanName({ groups = { [ns.Roads.GROUP_SET] = { crest, pick } } })
        )
        assert.is_nil(ns.UpgradeMapPanel.RoadPlanName({ groups = { [ns.Roads.GROUP_SET] = { crest } } }))
    end)

    -- -----------------------------------------------------------------------
    -- The weapon slot.

    it("heads the weapon section with its own sentence and draws the pick and the Keep row", function()
        local weapon = section(model(), "2H Weapon")
        assert.equal("Grab the Worldroot from the vault and crest it.", weapon.plan)
        local groups = weapon.roadGroups
        assert.equal(
            "Vault · open now · Lightgrasp Worldroot (305) · upgraded to 321 · in your best set at 321"
                .. " · crest type and cost not readable · reset in 6d 21h"
                .. " · do: take it · rated at 321, crests not readable",
            lineOf(groups[1], 1)
        )
        assert.equal(
            "Keep (what you wear) · Lightgrasp Worldroot (308) · what you wear now · 1.73% behind"
                .. " · taking the catalyzed shoulders instead · nothing to do",
            lineOf(groups[1], 2)
        )
    end)

    it("labels the raid row's second figures with his own words for them", function()
        local groups = section(model(), "2H Weapon").roadGroups
        assert.equal(
            "Raid · Venomancer's Winged Channeler (324) · Vashnik the Malignant - The Venomous Abyss, Mythic raid"
                .. " · +3.07% · at its cap 334 +4.70%"
                .. " · crest type and cost not readable · do: raid it · tick when it drops",
            lineOf(groups[2], 3)
        )
    end)

    -- -----------------------------------------------------------------------
    -- Verbs: one, from the table, only where it goes somewhere.

    it("gives a verb only to the roads that go somewhere, and only from the table", function()
        local m = model()
        local verbs, without = {}, 0
        for _, slot in ipairs({ "Shoulder", "2H Weapon" }) do
            for _, group in ipairs(section(m, slot).roadGroups) do
                for _, row in ipairs(group.rows) do
                    if row.verb then
                        verbs[row.verb] = (verbs[row.verb] or 0) + 1
                        -- A verb on this surface always has a destination.
                        assert.is_true(row.runKey ~= nil or row.vaultKey ~= nil)
                    else
                        without = without + 1
                        -- The Catalyst, a craft, a delve, the upgrade vendor and
                        -- the row for what you wear: nothing the addon may open.
                        assert.is_true(row.kind ~= ns.Roads.KIND_DROP)
                    end
                end
            end
        end
        assert.same({ ["Show run"] = verbs["Show run"], ["Show in vault"] = verbs["Show in vault"] }, verbs)
        assert.equal(2, verbs["Show in vault"])
        assert.is_true(without > 0)
        for verb in pairs(verbs) do
            local known = false
            for _, allowed in ipairs(ns.Roads.VERBS) do
                known = known or allowed == verb
            end
            assert.is_true(known, verb)
        end
    end)

    -- Red for the line above: strip the run a drop comes from and the button
    -- goes with it, because a verb with nowhere to go is not offered.
    it("drops Show run when there is no run to show", function()
        local road = {
            kind = ns.Roads.KIND_DROP,
            slot = "Shoulder",
            item = { itemID = 1, name = "x" },
            keys = {},
            steps = {},
            verb = ns.Roads.VERB_SHOW_RUN,
            rating = { kind = ns.Roads.RATING_ITEM, percent = 1, badge = "+1.00%" },
        }
        assert.is_nil(ns.UpgradeMapPanel.RoadRow(road, 10).verb)
        road.source = { instanceID = 1311, difficultyID = 8, isRaid = false }
        assert.equal(ns.Roads.VERB_SHOW_RUN, ns.UpgradeMapPanel.RoadRow(road, 10).verb)
    end)

    -- -----------------------------------------------------------------------
    -- The element list: what is DRAWN, and the Explain sentences.

    it("draws a group eyebrow and a card per road, in the model's own order", function()
        local m = model()
        local state = shutAllBut(m, "Shoulder")
        local drawn = {}
        for _, element in ipairs(elements(m, state)) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_GROUP then
                drawn[#drawn + 1] = "group:" .. element.group
            elseif element.kind == ns.UpgradeMapPanel.ELEMENT_CARD_ROW then
                for _, card in ipairs(element.cards) do
                    drawn[#drawn + 1] = "card:" .. card.row.kind
                end
            end
        end
        -- Since UX-6c (WKE-640) only a road worth drawing is drawn: the vault
        -- Spaulders are rated 1.73% behind the Catalyst and sit behind the
        -- slot's fold.
        assert.same({
            "group:set",
            "card:catalyst",
            "group:item",
            "card:craft",
            "card:delve",
            "card:drop",
            "card:drop",
            "card:drop",
            "card:drop",
            "card:drop",
        }, { unpack(drawn, 1, 10) })
        -- The slot's sentence is off the line since UX-6 (WKE-637) and on its
        -- hover, word for word; the line is one fixed height, open or shut.
        local header
        for _, element in ipairs(elements(m, state)) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_SECTION and element.slot == "Shoulder" then
                header = element
            end
        end
        assert.is_nil(header.plan)
        assert.equal(ns.UpgradeMapPanel.SLOT_LINE_HEIGHT, header.height)
        assert.equal(
            "Catalyst your Lynx shoulders, skip the vault ones, no crests here.",
            ns.UpgradeMapPanel.SlotTooltipLines(header.section)[2]
        )
    end)

    -- R-4 (WKE-565): what the Upgrade Finder export knows about its two
    -- non-drop sources, on the rows R-3 already draws for them. The rows
    -- themselves are R-3's - `ns.Roads.ForSlot` has built a craft and a delve
    -- road per slot since R-1 and the test above draws them - so what is
    -- asserted here is only what R-4 added: the stats line the crafted rating
    -- assumed, the absence of a key level, and the name the export does not
    -- carry.
    it("says what the crafted rating assumed and names no key level", function()
        local m = model()
        local rows = {}
        for _, group in ipairs(section(m, "2H Weapon").roadGroups) do
            for _, row in ipairs(group.rows) do
                rows[row.kind] = rows[row.kind] or row
            end
        end
        local craft, delve = rows[ns.Roads.KIND_CRAFT], rows[ns.Roads.KIND_DELVE]
        assert.is_table(craft)
        assert.equal(237849, craft.itemID)
        assert.equal(331, craft.itemLevel)
        assert.equal("+3.63%", craft.badge.text)
        -- The stats line is the export's own `settings.craftedStats`, said as
        -- a fact beside the badge because a crafting order has to ask for it.
        assert.is_not_nil(craft.factsText:find("the rating assumes Crit / Haste", 1, true))
        assert.is_not_nil(craft.factsText:find(ns.Roads.CRAFT_NOT_READ, 1, true))
        assert.equal("do: get the spark, then order it", craft.todo)

        assert.is_table(delve)
        assert.equal(272273, delve.itemID)
        assert.equal(321, delve.itemLevel)
        assert.equal("+2.17%", delve.badge.text)
        assert.equal(ns.Roads.DELVE_NOT_READ, delve.factsText)
        -- Neither says "at +2": every document of one companion run values
        -- these rows identically, so a key level would be a claim his own
        -- files deny (ns.UFImport.SourceRows, ARCHITECTURE.md 7 2026-09-13).
        for _, row in ipairs({ craft, delve }) do
            assert.is_nil(row.second and row.second:find("at +", 1, true))
            assert.is_nil(row.factsText:find("at +", 1, true))
        end

        -- Proven red the only way that matters: with no Upgrade Finder
        -- document at all the slot has neither row.
        local without = model({ upgradeDocuments = {}, upgrades = nil })
        for _, group in ipairs(section(without, "2H Weapon").roadGroups) do
            for _, row in ipairs(group.rows) do
                assert.is_not.equal(ns.Roads.KIND_CRAFT, row.kind)
                assert.is_not.equal(ns.Roads.KIND_DELVE, row.kind)
            end
        end
    end)

    -- The export carries an itemID and an item level and no name at all, so
    -- the row carries none either and the drawn line asks the client for it -
    -- the M3-12 pending pattern, which R-3's row already goes through.
    it("asks the client for the name the export does not carry", function()
        local m = model()
        local craft
        for _, group in ipairs(section(m, "2H Weapon").roadGroups) do
            for _, row in ipairs(group.rows) do
                craft = craft or (row.kind == ns.Roads.KIND_CRAFT and row or nil)
            end
        end
        assert.is_nil(craft.name)
        assert.equal(237849, craft.itemID)

        -- Since UX-6 (WKE-637) the road is a card, and the card asks.
        local panel = ns.UpgradeMapPanel.Create()
        local element = CreateFrame("Frame", nil, panel)
        local width, height = ns.UpgradeMapPanel.CardSize(nil)
        ns.UpgradeMapPanel.InitElement(panel, element, {
            kind = ns.UpgradeMapPanel.ELEMENT_CARD_ROW,
            height = height + ns.UpgradeMapPanel.TILE_ROW_PADDING,
            tileWidth = width,
            tileHeight = height,
            cards = { { row = craft } },
        })
        local card = element.cards[1]
        assert.equal(RETRIEVING_ITEM_INFO, card.name:GetText())
        local asked = false
        for _, itemID in ipairs(world.itemDataRequests) do
            asked = asked or itemID == craft.itemID
        end
        assert.is_true(asked, "the row never asked the client to name the item")
        world.items[craft.itemID] = {
            instant = { craft.itemID, "Weapon", "Staff", "INVTYPE_2HWEAPON", 4242, 2, 10 },
            info = {
                "Placeholder Valediction",
                "|Hitem:" .. craft.itemID .. "|h[Placeholder Valediction]|h",
                4,
                n = 3,
            },
            level = craft.itemLevel,
        }
        world.fireEvent("ITEM_DATA_LOAD_RESULT", craft.itemID, true)
        assert.is_truthy(card.name:GetText():find("Placeholder Valediction", 1, true))
        -- ...and its icon art followed: the card is re-drawn, not only its icon.
        assert.equal(card.cardIcon.resolved.icon, card.art:GetTexture())
    end)

    it("says nothing under a shut section", function()
        local m = model()
        local state = { slots = {} }
        for _, entry in ipairs(m.slots) do
            state.slots[entry.slot] = true
        end
        for _, element in ipairs(elements(m, state)) do
            assert.is_nil(element.plan)
            assert.is_true(element.kind ~= ns.UpgradeMapPanel.ELEMENT_CARD_ROW)
            assert.is_true(element.kind ~= ns.UpgradeMapPanel.ELEMENT_GROUP)
        end
    end)

    it("explains a system word once, under the first row that uses it", function()
        local m = model()
        local state = shutAllBut(m, "Shoulder")
        state.explain = true
        local list = elements(m, state)
        local seen, at = {}, {}
        for index, element in ipairs(list) do
            if element.tone == ns.UpgradeMapPanel.EXPLAIN_TONE then
                seen[element.text] = (seen[element.text] or 0) + 1
                at[element.text:match("^(%a+):")] = index
            end
        end
        for text, count in pairs(seen) do
            assert.equal(1, count, text)
        end
        -- The FIRST VISIBLE use decides. Since UX-6 (WKE-637) what is visible
        -- under a slot is its eyebrows and its cards - the slot's sentence and
        -- the long group headers are on the hover - so each sentence sits under
        -- the eyebrow or the card row whose drawn words first use the word, and
        -- nothing drawn above it used the word first.
        local Panel = ns.UpgradeMapPanel
        local function drawnWords(element)
            local words = {}
            if element.kind == Panel.ELEMENT_GROUP then
                words[#words + 1] = element.text
            end
            for _, card in ipairs(element.cards or {}) do
                local badge = Panel.CardBadge(card.row)
                words[#words + 1] = Panel.CardSecond(card.row)
                words[#words + 1] = badge and badge.text or nil
                words[#words + 1] = Panel.CardLine(card.row)
            end
            return words
        end
        local function uses(element, word)
            for _, text in pairs(drawnWords(element)) do
                if Panel.UsesWord(text, word) then
                    return true
                end
            end
            return false
        end
        assert.is_number(at.Catalyst)
        for word, index in pairs(at) do
            local owner = index - 1
            while list[owner].tone == Panel.EXPLAIN_TONE do
                owner = owner - 1
            end
            assert.is_true(uses(list[owner], word), word)
            for earlier = 1, owner - 1 do
                assert.is_false(uses(list[earlier], word), word .. " used earlier")
            end
        end
        -- The Catalyst card's own step names it: "Catalyst it · charge ...".
        assert.equal(Panel.ELEMENT_CARD_ROW, list[at.Catalyst - 1].kind)
        -- The one figure an Explain sentence carries is the client's own.
        assert.equal(
            "Catalyst: converts one piece into your tier set and spends one charge."
                .. " The client says 1 held, 8 max.",
            list[at.Catalyst].text
        )
    end)

    -- Red for the line above: with Explain off there is not one of them.
    it("adds no Explain sentence when the reader has not asked for one", function()
        local m = model()
        local state = shutAllBut(m, "Shoulder")
        for _, element in ipairs(elements(m, state)) do
            assert.is_true(element.tone ~= ns.UpgradeMapPanel.EXPLAIN_TONE)
        end
    end)

    -- -----------------------------------------------------------------------
    -- R-3b (WKE-576): the row of a vault pick that is already in the bags, and
    -- the slot header of a plan the bags have moved past.

    -- Hand-built, because the claim happens between two refreshes and no
    -- capture has one. Item 251935 and the 2H Weapon slot are this week's; the
    -- bonus ID has to be a third one (12841 is the vault's copy, 12838 the 308
    -- he is wearing), which is exactly the point: the key is new, the item ID
    -- is not, and the item ID is what decides.
    local function claimWorldroot()
        local worn
        for _, record in ipairs(gathered.inventory.records) do
            if record.location == "equipped" and record.itemID == 251935 then
                worn = record
            end
        end
        assert.is_table(worn)
        local link = worn.link:gsub("12838", "12844")
        local parsed = ns.ParseItemLink(link)
        assert.is_table(parsed)
        table.insert(gathered.inventory.records, {
            key = parsed.key,
            itemID = parsed.itemID,
            link = link,
            name = "Lightgrasp Worldroot",
            slot = "2H Weapon",
            itemLevel = 315,
            location = "bag",
        })
    end

    it("says a claimed vault reward is claimed and crested instead of open now", function()
        claimWorldroot()
        local weapon = section(model(), "2H Weapon")
        local row = weapon.roadGroups[1].rows[1]
        assert.equal(ns.Roads.KIND_VAULT, row.kind)
        assert.is_true(row.planPick)
        -- 315 is above the 305 the vault offers it at, so the badge says the
        -- crest as well as the claim (R-3c, WKE-580).
        assert.equal("Vault · claimed · now crested", row.tag)
        assert.equal("do: refresh to rate it", row.todo)
        assert.equal(ns.Roads.VERB_REFRESH, row.verb)
        local text = ns.UpgradeMapPanel.RoadLineText(row)
        assert.is_truthy(text:find("Vault · claimed · now crested", 1, true))
        assert.is_nil(text:find("open now", 1, true))
        assert.is_nil(text:find("do: take it", 1, true))
    end)

    -- Red for all of that: with the reward still in the vault the row is the
    -- one R-3 shipped.
    it("says open now while the reward is still in the vault", function()
        local weapon = section(model(), "2H Weapon")
        local row = weapon.roadGroups[1].rows[1]
        assert.equal("Vault · open now", row.tag)
        assert.equal("do: take it · rated at 321, crests not readable", row.todo)
        assert.equal(ns.Roads.VERB_SHOW_IN_VAULT, row.verb)
    end)

    -- Principle 9: a verb goes somewhere. This one's destination is not a
    -- screen but the refresh itself, which is `/lootpath refresh` and nothing
    -- else - the same captures, the same two reloads, the same combat refusal.
    it("follows the Refresh verb to the companion refresh and nowhere else", function()
        local asked = 0
        local real = ns.Companion.Refresh
        ns.Companion.Refresh = function()
            asked = asked + 1
            return { ok = true }
        end
        assert.is_true(ns.UpgradeMapPanel.FollowVerb(nil, { verb = ns.Roads.VERB_REFRESH }))
        assert.equal(1, asked)
        -- A row with no verb at all follows nothing.
        assert.is_false(ns.UpgradeMapPanel.FollowVerb(nil, {}))
        assert.equal(1, asked)
        ns.Companion.Refresh = real
    end)

    -- Defect 4: the slot header of a plan the bags have moved past names the
    -- remedy, in the same words the tooltip's header uses. This week's weapon
    -- slot holds the 259 Decapitator, which the rating never saw.
    it("names the refresh on a slot header whose bags the plan has not seen", function()
        local m = model()
        assert.equal("2H Weapon · /lootpath refresh", ns.UpgradeMapPanel.SectionHeaderText(section(m, "2H Weapon")))
        -- And nothing on a slot that holds nothing the plan has not seen: of
        -- this week's sixteen, Neck, Back, Chest and Hands are the four whose
        -- bags the rating covers completely.
        assert.equal("Chest", ns.UpgradeMapPanel.SectionHeaderText(section(m, "Chest")))
        -- The PRINTED header keeps it. Since UX-6 (WKE-637) the DRAWN line is
        -- the slot's name alone, and the remedy is the tab's one nudge.
        local element
        for _, entry in ipairs(elements(m, shutAllBut(m, "2H Weapon"))) do
            if entry.kind == ns.UpgradeMapPanel.ELEMENT_SECTION and entry.slot == "2H Weapon" then
                element = entry
            end
        end
        assert.is_table(element)
        assert.equal("2H Weapon", element.header)
        assert.equal(ns.UpgradeMapPanel.STALE_NUDGE, ns.UpgradeMapPanel.StaleNudge(m))
    end)

    -- -----------------------------------------------------------------------
    -- The printed text is the same rows.

    it("prints the same sentence, headers and rows the list draws", function()
        local m = model()
        local lines = ns.UpgradeMapPanel.Lines(m)
        local shoulder = section(m, "Shoulder")
        -- The slot's header, which since R-3b (WKE-576) names the refresh when
        -- the slot's bags hold something the plan has not seen - and this
        -- week's Shoulder does.
        local header = ns.UpgradeMapPanel.SectionHeaderText(shoulder)
        assert.equal("Shoulder · /lootpath refresh", header)
        local at
        for index, line in ipairs(lines) do
            if line == header then
                at = index
            end
        end
        assert.is_number(at)
        -- One equipped line, then the slot's sentence, then the first header.
        assert.equal("  " .. shoulder.plan, lines[at + 1 + #shoulder.equipped])
        assert.equal("  " .. shoulder.roadGroups[1].header, lines[at + 2 + #shoulder.equipped])
        assert.equal("    " .. lineOf(shoulder.roadGroups[1], 1), lines[at + 3 + #shoulder.equipped])
    end)

    -- -----------------------------------------------------------------------
    -- The voice.

    it("names no source and strikes no phrase the brief struck", function()
        local m = model()
        local checked = 0
        for _, entry in ipairs(m.slots) do
            local offender = usesForbidden(entry.plan)
            assert.is_nil(offender, tostring(entry.plan))
            for _, group in ipairs(entry.roadGroups or {}) do
                assert.is_nil(usesForbidden(group.header), group.header)
                for _, row in ipairs(group.rows) do
                    local text = ns.UpgradeMapPanel.RoadLineText(row)
                    assert.is_nil(usesForbidden(text), text)
                    checked = checked + 1
                end
            end
        end
        assert.is_true(checked > 300)
        for _, word in ipairs(ns.UpgradeMapPanel.EXPLAIN_WORDS) do
            local sentence = ns.UpgradeMapPanel.ExplainText(word, "1 held, 8 max")
            assert.is_nil(usesForbidden(sentence), sentence)
        end
    end)

    -- Red for the line above: the check really does catch each word, as a word.
    it("catches every forbidden word and lets an innocent one through", function()
        assert.equal("QE Live", usesForbidden("rated by QE Live"))
        assert.equal("his", usesForbidden("his answer"))
        assert.equal("verdict", usesForbidden("the verdict says"))
        assert.equal("not asked", usesForbidden("not asked about"))
        assert.equal("no document", usesForbidden("no document covers it"))
        assert.equal("next:", usesForbidden("next: run the key"))
        assert.is_nil(usesForbidden("this week's picks"))
        assert.is_nil(usesForbidden("the Hoardmonger"))
    end)
    -- -----------------------------------------------------------------------
    -- UX-6 (WKE-637): Roads at a glance. A slot is one line, a road is a card,
    -- and the explanations come off the screen onto the hovers.

    local function sectionElement(list, slot)
        for _, element in ipairs(list) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_SECTION and element.slot == slot then
                return element
            end
        end
        return nil
    end

    -- Everything drawn under one slot's line, up to the next slot's.
    local function under(list, slot)
        local out, inside = {}, false
        for _, element in ipairs(list) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_SECTION then
                inside = element.slot == slot
            elseif inside then
                out[#out + 1] = element
            end
        end
        return out
    end

    local function allOpen(m)
        local open = {}
        for _, entry in ipairs(m.slots) do
            open[entry.slot] = false
        end
        return { slots = open }
    end

    local function rowWhere(m, slot, test)
        for _, group in ipairs(section(m, slot).roadGroups) do
            for _, row in ipairs(group.rows) do
                if test(row) then
                    return row
                end
            end
        end
        return nil
    end

    it("draws a slot as one line and its roads as eyebrows over rows of cards, across first (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local list = elements(m, shutAllBut(m, "Shoulder"))
        local line = sectionElement(list, "Shoulder")
        -- The line: the slot's name alone, the worn item, and no sentence.
        assert.equal("Shoulder", line.header)
        assert.equal(Panel.SLOT_LINE_HEIGHT, line.height)
        assert.is_nil(line.plan)
        assert.is_nil(line.count)
        assert.is_table(line.worn)
        assert.is_false(line.collapsed)

        local width, height = Panel.CardSize(nil)
        local expected, drawn = {}, {}
        local function addCards(rows)
            for index, row in ipairs(rows) do
                if (index - 1) % Panel.TILES_PER_ROW == 0 then
                    expected[#expected + 1] = "cards"
                end
                expected[#expected + 1] = row
            end
        end
        -- Since UX-6b (WKE-639) the no-rating group is sorted: the roads rated
        -- at another level follow the rated group's own. Since UX-6c
        -- (WKE-640) only what is worth drawing is drawn, each group in its
        -- own order, and everything else is behind ONE fold, shut.
        local sorted = section(m, "Shoulder").noRating
        assert.is_true(#sorted.otherLevel > 0)
        assert.is_true(#sorted.unknown > 0)
        local folded = {}
        local function keep(rows, group)
            local worth = {}
            for _, row in ipairs(rows) do
                if row.kind ~= ns.Roads.KIND_KEEP then
                    local into = Panel.CardWorthDrawing(row) and worth or folded
                    into[#into + 1] = row
                end
            end
            if #worth > 0 then
                expected[#expected + 1] = "eyebrow:" .. Panel.GROUP_EYEBROW[group]
                addCards(worth)
            end
        end
        for _, group in ipairs(section(m, "Shoulder").roadGroups) do
            if group.group == ns.Roads.GROUP_ITEM then
                local rows = { unpack(group.rows) }
                for _, row in ipairs(sorted.otherLevel) do
                    rows[#rows + 1] = row
                end
                keep(rows, group.group)
            elseif group.group ~= ns.Roads.GROUP_NONE then
                keep(group.rows, group.group)
            end
        end
        for _, row in ipairs(sorted.unknown) do
            folded[#folded + 1] = row
        end
        expected[#expected + 1] = "fold:" .. Panel.FoldText(folded, false)
        for _, element in ipairs(under(list, "Shoulder")) do
            if element.kind == Panel.ELEMENT_FOLD then
                drawn[#drawn + 1] = "fold:" .. element.text
            elseif element.kind == Panel.ELEMENT_GROUP then
                drawn[#drawn + 1] = "eyebrow:" .. element.text
            elseif element.kind == Panel.ELEMENT_CARD_ROW then
                drawn[#drawn + 1] = "cards"
                assert.is_true(#element.cards <= Panel.TILES_PER_ROW)
                assert.equal(width, element.tileWidth)
                assert.equal(height, element.tileHeight)
                assert.equal(height + Panel.TILE_ROW_PADDING, element.height)
                assert.equal(Panel.CARD_INDENT, element.indent)
                for _, card in ipairs(element.cards) do
                    drawn[#drawn + 1] = card.row
                end
            else
                error(
                    "under the slot, an element that is not an eyebrow, a fold or a card row: "
                        .. tostring(element.kind)
                )
            end
        end
        assert.is_true(#drawn > 6)
        assert.equal(#expected, #drawn)
        for index = 1, #expected do
            assert.equal(expected[index], drawn[index], "position " .. index)
        end
        -- The eyebrows are the short forms, two to four words each.
        assert.equal("eyebrow:In your best set", drawn[1])
        assert.equal("In your best set", Panel.GROUP_EYEBROW[ns.Roads.GROUP_SET])
        assert.equal("Rated against what you wear", Panel.GROUP_EYEBROW[ns.Roads.GROUP_ITEM])
        assert.equal("No rating", Panel.GROUP_EYEBROW[ns.Roads.GROUP_NONE])
        -- Four across, derived the way the by-run tiles are, over the list
        -- less the indent past the slot's icon column.
        assert.equal(Panel.TileSize(Panel.ListWidth(nil) - Panel.CARD_INDENT), width)
        assert.equal(Panel.SLOT_ICON_X + Panel.SLOT_ICON_SIZE + Panel.TILE_GAP, Panel.CARD_INDENT)
    end)

    it("puts the best road's badge on the slot line, and none when no road beats what is worn (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local list = elements(m, { slots = {} })
        -- Head keeps what it wears; the best per-item percent is the raid drop's.
        assert.same({ text = "+2.99%", tone = "better" }, sectionElement(list, "Head").badge)
        -- Shoulder's answer is a whole-set pick, the Catalyst, and that wins.
        assert.same({ text = "in your best set", tone = "neutral" }, sectionElement(list, "Shoulder").badge)
        -- The 1H Weapon slot has nothing rated forward: no badge at all.
        assert.is_nil(sectionElement(list, "1H Weapon").badge)
        assert.same(Panel.SlotBadge(section(m, "Head")), sectionElement(list, "Head").badge)
        assert.is_nil(Panel.SlotBadge(nil))
    end)

    it("opens the first slot worth taking and shuts the rest, a saved click winning (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        assert.equal("Head", Panel.FirstWorthTaking(m))
        local sections = 0
        for _, element in ipairs(elements(m, { slots = {} })) do
            if element.kind == Panel.ELEMENT_SECTION then
                sections = sections + 1
                assert.equal(element.slot ~= "Head", element.collapsed, element.slot)
            end
        end
        assert.equal(#m.slots, sections)
        local list = elements(m, { slots = { Head = true, Neck = false } })
        assert.is_true(sectionElement(list, "Head").collapsed)
        assert.is_false(sectionElement(list, "Neck").collapsed)
        assert.is_true(sectionElement(list, "Shoulder").collapsed)

        -- A first slot that only keeps what it wears is not worth taking, nor
        -- is one whose only step is a refresh, nor one that says to keep.
        local function slotOf(name, group, row)
            return { slot = name, roadGroups = { { group = group, rows = { row } } } }
        end
        local handBuilt = {
            slots = {
                slotOf("Head", ns.Roads.GROUP_SET, { kind = ns.Roads.KIND_KEEP, todo = ns.Roads.TODO_NOTHING }),
                slotOf("Neck", ns.Roads.GROUP_ITEM, { kind = ns.Roads.KIND_DROP, todo = ns.Roads.TODO_REFRESH }),
                slotOf("Shoulder", ns.Roads.GROUP_ITEM, { kind = ns.Roads.KIND_DROP, todo = ns.Roads.TODO_KEEP_WORN }),
                slotOf("Back", ns.Roads.GROUP_ITEM, { kind = ns.Roads.KIND_DROP, todo = ns.Roads.TODO_RAID }),
            },
        }
        assert.equal("Back", Panel.FirstWorthTaking(handBuilt))
        handBuilt.slots[4] = nil
        assert.is_nil(Panel.FirstWorthTaking(handBuilt))
        assert.is_nil(Panel.FirstWorthTaking(nil))
    end)

    it("says the bags changed once for the tab, never on a slot line (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        assert.equal(Panel.STALE_NUDGE, Panel.StaleNudge(m))
        assert.equal("your bags changed since this rating · Refresh", Panel.STALE_NUDGE)
        for _, element in ipairs(elements(m, allOpen(m))) do
            for _, text in pairs({ element.text or false, element.header or false }) do
                if text then
                    assert.is_nil(text:find(Panel.SECTION_REFRESH, 1, true), text)
                    assert.is_nil(text:find(Panel.STALE_NUDGE, 1, true), text)
                end
            end
        end
        for _, entry in ipairs(m.slots) do
            entry.staleBags = false
        end
        assert.is_nil(Panel.StaleNudge(m))
        assert.is_nil(Panel.StaleNudge(nil))
    end)

    it("puts nothing on screen from the sentences it dropped, and keeps them on the hover (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local dropped = { Panel.GROUP_SET_TAIL, ns.Roads.ITEM_SCALE_TEXT, Panel.SECTION_REFRESH, Panel.NOTE }
        if m.upgradeDocumentsNote then
            dropped[#dropped + 1] = m.upgradeDocumentsNote
        end
        for _, entry in ipairs(m.slots) do
            dropped[#dropped + 1] = entry.plan
            dropped[#dropped + 1] = entry.hiddenNote
        end
        local shown, cards = {}, 0
        for _, element in ipairs(elements(m, allOpen(m))) do
            assert.is_true(element.kind ~= "road", "a road row is still drawn")
            shown[#shown + 1] = element.text
            shown[#shown + 1] = element.header
            for _, card in ipairs(element.cards or {}) do
                cards = cards + 1
                assert.is_true(card.row.kind ~= ns.Roads.KIND_KEEP, "the Keep row is drawn")
                shown[#shown + 1] = Panel.CardSecond(card.row)
                shown[#shown + 1] = Panel.CardLine(card.row)
                local badge = Panel.CardBadge(card.row)
                shown[#shown + 1] = badge and badge.text or nil
            end
        end
        assert.is_true(cards > 100)
        for _, text in pairs(shown) do
            for _, sentence in pairs(dropped) do
                assert.is_nil(text:find(sentence, 1, true), text)
            end
        end
        -- ...and each one is still one hover away, on the slot line.
        local shoulder = section(m, "Shoulder")
        local tooltip = table.concat(Panel.SlotTooltipLines(shoulder), "\n")
        assert.is_not_nil(tooltip:find(shoulder.plan, 1, true))
        assert.is_not_nil(tooltip:find(Panel.GROUP_SET_TAIL, 1, true))
        assert.is_not_nil(tooltip:find(ns.Roads.ITEM_SCALE_TEXT, 1, true))
        -- Head's answer keeps what it wears, so its hover carries the Keep row.
        local head = section(m, "Head")
        local headTip = table.concat(Panel.SlotTooltipLines(head), "\n")
        assert.is_not_nil(headTip:find(ns.Roads.TAG_KEEP, 1, true))
        assert.is_not_nil(headTip:find(head.hiddenNote, 1, true))
        -- The long group header is the same string it always was.
        assert.equal(
            "Other rated sources · percents are against what you wear · at your key's preview level, per the client",
            ns.Roads.GROUP_HEADER[ns.Roads.GROUP_ITEM]
        )
    end)

    it("draws a card's lines from the road's own strings (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local raid = rowWhere(m, "Head", function(row)
            return row.badge and row.badge.text == "+2.99%"
        end)
        assert.equal("do: raid it · tick when it drops", raid.todo)
        assert.equal("raid it · tick when it drops", Panel.CardLine(raid))
        assert.equal(raid.second, Panel.CardSecond(raid))
        assert.equal(raid.badge, Panel.CardBadge(raid))
        -- No step: the first fact, which on this row is the level it upgrades to.
        local noStep = rowWhere(m, "1H Weapon", function(row)
            return row.todo == nil and row.facts[1] ~= nil
        end)
        assert.equal(noStep.facts[1], Panel.CardLine(noStep))
        -- A no-rating road: no badge, and its phrase on the second line.
        local none = rowWhere(m, "Head", function(row)
            return row.group == ns.Roads.GROUP_NONE
        end)
        assert.is_nil(Panel.CardBadge(none))
        assert.equal(ns.Roads.PHRASE_NO_RATING, Panel.CardSecond(none))
        -- The hover's own lines: the badge against its scale, the facts a
        -- tooltip may carry, the cost, and where a click goes.
        local lines = Panel.CardTooltipLines(raid)
        assert.equal("+2.99%" .. Panel.ROAD_SEPARATOR .. ns.Roads.ITEM_SCALE_TEXT, lines[1])
        assert.equal(Panel.CARD_CLICK_TEXT[ns.Roads.VERB_SHOW_RUN], lines[#lines])
        assert.equal("click: show the run", lines[#lines])
        assert.is_not_nil(table.concat(lines, "\n"):find(raid.costText, 1, true))
        local craft = rowWhere(m, "Head", function(row)
            return row.kind == ns.Roads.KIND_CRAFT
        end)
        assert.is_nil(table.concat(Panel.CardTooltipLines(craft), "\n"):find("click:", 1, true))
    end)

    -- -----------------------------------------------------------------------
    -- UX-6b (WKE-639): the `No rating` flood, sorted before it is folded. On
    -- this week Head opens onto 35 cards and 26 of them had no rating; every
    -- figure below is one of the committed documents' own rows.

    local function noRatingRow(m, slot, name)
        for _, group in ipairs(section(m, slot).roadGroups) do
            if group.group == ns.Roads.GROUP_NONE then
                for _, row in ipairs(group.rows) do
                    if row.name == name then
                        return row
                    end
                end
            end
        end
        return nil
    end

    local function otherLevelRow(m, slot, name)
        for _, row in ipairs(section(m, slot).noRating.otherLevel) do
            if row.name == name then
                return row
            end
        end
        return nil
    end

    -- Hand-built documents over one item, in the shape UFImport.Parse gives.
    local function document(keyLevel, rows)
        local items, levels = {}, {}
        for _, spec in ipairs(rows) do
            local key = ns.UFImport.Key(1001, spec[1])
            items[key] = {
                key = key,
                itemID = 1001,
                level = spec[1],
                dropType = spec[2],
                upgradePercent = spec[3],
                sources = { { dropType = spec[2] } },
            }
            levels[#levels + 1] = spec[1]
        end
        table.sort(levels)
        return { keyLevel = keyLevel, verdict = { items = items, levelsByItemID = { [1001] = levels } } }
    end

    it("sorts every no-rating road: rated at another level, not for this spec, or unknown (UX-6b)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local documents = m.upgradeDocuments
        local warmask = noRatingRow(m, "Head", "Shadow Hunter's Warmask")
        assert.equal(308, warmask.itemLevel)
        -- His documents carry it, never at the level it drops at.
        assert.is_nil(ns.UFImport.LookupAcrossLevels(documents, warmask.itemID, 308))
        assert.is_table(ns.UFImport.LevelsAcrossLevels(documents, warmask.itemID))
        assert.equal(Panel.NO_RATING_OTHER_LEVEL, Panel.NoRatingKind(warmask.road, documents))
        -- A document row is asked first: an item he rated was viable to him.
        assert.equal(
            Panel.NO_RATING_OTHER_LEVEL,
            Panel.NoRatingKind(warmask.road, documents, function()
                return false
            end)
        )

        local unknown = section(m, "Head").noRating.unknown[1]
        assert.is_nil(ns.UFImport.LevelsAcrossLevels(documents, unknown.itemID))
        assert.equal(Panel.NO_RATING_UNKNOWN, Panel.NoRatingKind(unknown.road, documents))
        -- The client's own answer decides offspec, and "cannot tell" is not it.
        local calls = {}
        assert.equal(
            Panel.NO_RATING_OFFSPEC,
            Panel.NoRatingKind(unknown.road, documents, function(road)
                calls[#calls + 1] = road
                return false
            end)
        )
        assert.same({ unknown.road }, calls)
        for _, answer in ipairs({ true, "nil" }) do
            local said = answer ~= "nil" and answer or nil
            assert.equal(
                Panel.NO_RATING_UNKNOWN,
                Panel.NoRatingKind(unknown.road, documents, function()
                    return said
                end)
            )
        end
        -- Only a drop: a piece you own is yours whatever spec it names.
        local crest = rowWhere(m, "Shoulder", function(row)
            return row.group == ns.Roads.GROUP_NONE and row.kind == ns.Roads.KIND_CREST
        end)
        assert.equal(
            Panel.NO_RATING_UNKNOWN,
            Panel.NoRatingKind(crest.road, documents, function()
                return false
            end)
        )
        -- A road with a rating is none of the three.
        local rated = rowWhere(m, "Head", function(row)
            return row.group == ns.Roads.GROUP_ITEM
        end)
        assert.is_nil(Panel.NoRatingKind(rated.road, documents))
        assert.is_nil(Panel.NoRatingKind(nil, documents))

        -- The counts, read off the committed week: other level, offspec, unknown.
        local counts = {}
        for _, entry in ipairs(m.slots) do
            local sorted = entry.noRating
            counts[entry.slot] = { #sorted.otherLevel, #sorted.offspec, #sorted.unknown }
        end
        assert.same({ 10, 0, 16 }, counts.Head)
        assert.same({ 9, 0, 18 }, counts.Chest)
        assert.same({ 23, 0, 30 }, counts.Trinket)
        assert.same({ 10, 0, 0 }, counts.Back)
    end)

    it("carries the document's own row onto a drop rated at another level, and says the level (UX-6b)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local documents = m.upgradeDocuments
        -- A Heroic raid drop at 308 that his run rated at 321 as a drop and at
        -- 334 with its crests spent: the card carries the drop figure, the
        -- hover the other.
        local warmask = otherLevelRow(m, "Head", "Shadow Hunter's Warmask")
        assert.equal(ns.Roads.GROUP_ITEM, warmask.group)
        assert.same({ text = "+0.17%", tone = "better" }, Panel.CardBadge(warmask))
        assert.equal("rated at 321", Panel.CardLine(warmask))
        assert.equal(warmask.second, Panel.CardSecond(warmask))
        assert.is_not_nil(Panel.CardSecond(warmask):find("Heroic raid", 1, true))
        local hover = Panel.CardTooltipLines(warmask)
        assert.equal("+0.17% · rated at 321, drops at 308", hover[1])
        assert.equal("crested to 334 · +0.75%", hover[2])
        -- Both figures are his rows, whole, and out of one document.
        local rating = warmask.otherLevel
        assert.equal(321, rating.drop.level)
        assert.equal(334, rating.max.level)
        assert.is_true(ns.UFImport.HasDropType(rating.drop.entry, ns.UFImport.DROP_TYPE_DROP))
        assert.is_true(ns.UFImport.HasDropType(rating.max.entry, ns.UFImport.DROP_TYPE_MAX))
        assert.equal(rating.drop.entry.upgradePercent, rating.drop.percent)
        assert.equal(rating.max.entry.upgradePercent, rating.max.percent)
        assert.equal(rating.drop.keyLevel, rating.max.keyLevel)
        assert.equal(ns.UFImport.LookupAcrossLevels(documents, warmask.itemID, 321).upgradePercent, rating.drop.percent)

        -- Drop and max at ONE level: the card carries it and the hover has no
        -- second figure to add.
        local gaze = otherLevelRow(m, "Head", "Gaze of the Coiled Watcher")
        assert.equal(315, gaze.itemLevel)
        assert.equal("rated at 344", Panel.CardLine(gaze))
        assert.same({ text = "+2.99%", tone = "better" }, Panel.CardBadge(gaze))
        local gazeHover = table.concat(Panel.CardTooltipLines(gaze), "\n")
        assert.equal("+2.99% · rated at 344, drops at 315", Panel.CardTooltipLines(gaze)[1])
        assert.is_nil(gazeHover:find("crested to", 1, true))

        -- A figure at or below zero keeps the model's own word for it.
        local crown = otherLevelRow(m, "Head", "Crown of Roaring Storms")
        assert.same({ text = ns.Roads.PHRASE_NOT_IN_BEST_SET, tone = "none" }, Panel.CardBadge(crown))
        assert.equal("rated at 295", Panel.CardLine(crown))

        -- The road is untouched: no rating in the model and in the printed lines.
        assert.equal(ns.Roads.GROUP_NONE, warmask.road.group)
        assert.equal(ns.Roads.PHRASE_NO_RATING, warmask.road.phrase)
        local printed
        for _, line in ipairs(Panel.Lines(m)) do
            if line:find("Shadow Hunter's Warmask (308)", 1, true) then
                printed = line
            end
        end
        assert.is_string(printed)
        assert.is_not_nil(printed:find(ns.Roads.PHRASE_NO_RATING, 1, true), printed)
        assert.is_nil(printed:find("rated at", 1, true), printed)
        -- The slot's badge is still the best AT-LEVEL road's.
        assert.same({ text = "+2.99%", tone = "better" }, Panel.SlotBadge(section(m, "Head")))

        -- Drawn in the rated group after its own roads, and not in the fold.
        local drawn, rated = {}, 0
        for _, element in ipairs(under(elements(m, shutAllBut(m, "Head")), "Head")) do
            if element.group == ns.Roads.GROUP_ITEM then
                for _, card in ipairs(element.cards or {}) do
                    drawn[#drawn + 1] = card.row
                    if not card.row.otherLevel then
                        rated = rated + 1
                    end
                end
            end
            for _, card in ipairs(element.cards or {}) do
                assert.are_not.equal(ns.Roads.GROUP_NONE, card.row.group)
            end
        end
        -- Since UX-6c (WKE-640) only the two above zero: the other eight are
        -- the +2 run's 295 rows, `not in your best set`, behind the fold.
        assert.equal(rated + 2, #drawn)
        for index = rated + 1, #drawn do
            assert.is_table(drawn[index].otherLevel, "position " .. index)
        end
        -- Best figure first among them, his number's order.
        assert.equal(gaze, drawn[rated + 1])
        assert.equal(warmask, drawn[rated + 2])
    end)

    it("reads a max-only row as `crested to`, and a drop's cap out of the drop's own document (UX-6b)", function()
        local Panel = ns.UpgradeMapPanel
        local maxOnly = Panel.OtherLevelRating({ document(nil, { { 334, "max", 0.5 } }) }, 1001)
        assert.is_nil(maxOnly.drop)
        assert.equal(334, maxOnly.max.level)
        local row = Panel.OtherLevelRow({ itemLevel = 308, kind = ns.Roads.KIND_DROP }, maxOnly)
        assert.equal("crested to 334", row.levelLine)
        assert.same({ text = "+0.50%", tone = "better" }, row.badge)
        assert.same({ "+0.50% · crested to 334, drops at 308" }, row.otherLevelHover)
        -- The +4 run carries a lower cap, but the card's drop row is the +2
        -- run's, so its cap is too.
        local both = Panel.OtherLevelRating({
            document(2, { { 295, "drop", -0.1 }, { 308, "max", 0.2 } }),
            document(4, { { 300, "max", 0.9 } }),
        }, 1001)
        assert.equal(295, both.drop.level)
        assert.equal(2, both.drop.keyLevel)
        assert.equal(308, both.max.level)
        assert.equal(2, both.max.keyLevel)
        -- Since UX-6d (WKE-641) the crested row, the upgrade of the two, is
        -- the one the card wears.
        assert.same(
            { "drops at 276 · not better at 295 · crested to 308, +0.20%" },
            Panel.OtherLevelRow({ itemLevel = 276 }, both).otherLevelHover
        )
        -- A bonus-roll row alone is no figure this card carries.
        assert.is_nil(Panel.OtherLevelRating({ document(nil, { { 321, "bonus", 1 } }) }, 1001))
        assert.is_nil(Panel.OtherLevelRating(nil, 1001))
    end)

    it("draws no card for a drop the client says is not for this spec, and prints it (UX-6b)", function()
        local Panel = ns.UpgradeMapPanel
        local target = section(model(), "Head").noRating.unknown[1]
        assert.is_table(target)
        local m = model({
            specFit = function(road)
                if road.item and road.item.itemID == target.itemID then
                    return false
                end
                return nil
            end,
        })
        local head = section(m, "Head")
        assert.equal(1, #head.noRating.offspec)
        assert.equal(target.itemID, head.noRating.offspec[1].itemID)
        assert.equal(15, #head.noRating.unknown)
        local every = allOpen(m)
        every.fold = {}
        for _, entry in ipairs(m.slots) do
            every.fold[entry.slot] = true
        end
        local seenFold = false
        for _, element in ipairs(elements(m, every)) do
            for _, card in ipairs(element.cards or {}) do
                assert.are_not.equal(target.itemID, card.row.itemID)
            end
            if element.kind == Panel.ELEMENT_FOLD and element.slot == "Head" then
                -- Not drawn and not counted either (UX-6c keeps UX-6b's rule).
                seenFold = true
                assert.equal("- 29 more items", element.text)
                assert.equal(15, element.unrated)
            end
        end
        assert.is_true(seenFold)
        local printed = false
        for _, line in ipairs(Panel.Lines(m)) do
            if line:find(target.name .. " (" .. tostring(target.itemLevel) .. ")", 1, true) then
                printed = printed or line:find(ns.Roads.PHRASE_NO_RATING, 1, true) ~= nil
            end
        end
        assert.is_true(printed)
    end)

    it("folds everything not drawn behind one line per slot, counted two ways, shut by default (UX-6c)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local unknown = section(m, "Head").noRating.unknown
        assert.equal(16, #unknown)
        local function drawnUnder(state, slot)
            local fold, cards, eyebrows, afterFold = nil, {}, {}, {}
            for _, element in ipairs(under(elements(m, state), slot or "Head")) do
                if element.kind == Panel.ELEMENT_FOLD then
                    assert.is_nil(fold, "one fold line per slot")
                    fold = element
                elseif element.kind == Panel.ELEMENT_GROUP then
                    eyebrows[#eyebrows + 1] = (fold and "folded:" or "") .. element.text
                end
                for _, card in ipairs(element.cards or {}) do
                    cards[#cards + 1] = card.row
                    if fold then
                        afterFold[#afterFold + 1] = card.row
                    end
                end
            end
            return fold, cards, eyebrows, afterFold
        end
        -- Shut, the default: the upgrades, then the line and its count, and
        -- none of the folded cards.
        local fold, cards, eyebrows = drawnUnder(shutAllBut(m, "Head"))
        assert.equal("+ 30 more items", fold.text)
        assert.equal("14 rated below what you wear · 16 not rated", fold.hover)
        assert.is_false(fold.open)
        assert.equal(30, fold.count)
        assert.equal(14, fold.rated)
        assert.equal(16, fold.unrated)
        assert.equal("Head", fold.slot)
        assert.equal(5, #cards)
        for _, row in ipairs(cards) do
            assert.is_true(Panel.CardWorthDrawing(row))
        end
        assert.same({ "Rated against what you wear" }, eyebrows)
        -- Open: every folded card, after the line, each group under its own
        -- eyebrow so the two scales never share a row; the rated ones keep
        -- their figure, the unrated ones are the dimmed no-rating cards.
        local state = shutAllBut(m, "Head")
        state.fold = { Head = true }
        local afterFold
        fold, cards, eyebrows, afterFold = drawnUnder(state)
        assert.equal("- 30 more items", fold.text)
        assert.is_true(fold.open)
        assert.equal(35, #cards)
        assert.equal(30, #afterFold)
        assert.same({
            "Rated against what you wear",
            "folded:In your best set",
            "folded:Rated against what you wear",
            "folded:No rating",
        }, eyebrows)
        for index, row in ipairs(afterFold) do
            assert.is_false(Panel.CardWorthDrawing(row), "position " .. index)
        end
        for index, row in ipairs(unknown) do
            assert.equal(row, afterFold[14 + index])
        end
        -- A zero count is not printed: Back folds only rated roads.
        fold = drawnUnder(shutAllBut(m, "Back"), "Back")
        assert.equal("+ 5 more items", fold.text)
        assert.equal("5 rated below what you wear", fold.hover)
        -- The noun is the rows' own: a set road is not a drop.
        assert.equal("+ 1 more drop", Panel.FoldText({ { kind = ns.Roads.KIND_DROP } }, false))
        assert.equal("- 2 more drops", Panel.FoldText({ { kind = "drop" }, { kind = "drop" } }, true))
        assert.equal("+ 1 more item", Panel.FoldText({ { kind = ns.Roads.KIND_CREST } }, false))
        assert.equal("1 not rated", Panel.FoldHover({ { kind = ns.Roads.KIND_DROP } }))
        assert.is_nil(Panel.FoldHover({}))

        -- Per character, nil the default and nil again when it shuts, under
        -- the key that says what it holds now.
        assert.is_nil(ns.db.char.upgradeMap and ns.db.char.upgradeMap.foldOpen and ns.db.char.upgradeMap.foldOpen.Head)
        assert.is_true(Panel.ToggleFold(ns.db, "Head"))
        assert.is_true(ns.db.char.upgradeMap.foldOpen.Head)
        assert.is_true(Panel.CollapseState(ns.db).fold.Head)
        assert.is_false(Panel.ToggleFold(ns.db, "Head"))
        assert.is_nil(ns.db.char.upgradeMap.foldOpen.Head)
        -- A save from UX-6b is not migrated: it opens nothing.
        ns.db.char.upgradeMap.noRatingOpen = { Head = true }
        local saved = Panel.CollapseState(ns.db)
        saved.slots.Head = false
        fold = drawnUnder(saved)
        assert.is_false(fold.open)
    end)

    -- -----------------------------------------------------------------------
    -- UX-6c (WKE-640): a slot draws only its upgrades. The source's own line
    -- for an upgrade is a score above zero (PanelSlots.js:102), read off the
    -- sign by ns.UFImport.IsUpgrade; there is no band around zero.

    local function itemRow(percent, alsoAt)
        return {
            kind = ns.Roads.KIND_DROP,
            road = { rating = { kind = ns.Roads.RATING_ITEM, percent = percent, alsoAt = alsoAt } },
        }
    end

    it("draws a card only when its figure is above zero, the pick, or a step the answer names (UX-6c)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        -- An upgrade: his figure above zero.
        local gaze = rowWhere(m, "Head", function(row)
            return row.name == "Gaze of the Coiled Watcher" and row.group == ns.Roads.GROUP_ITEM
        end)
        assert.equal("+2.99%", gaze.badge.text)
        assert.is_true(Panel.CardWorthDrawing(gaze))
        assert.is_true(Panel.CardWorthDrawing(itemRow(0.01)))
        -- A tie and a downgrade: not drawn, and no band lets a near miss in.
        assert.is_false(Panel.CardWorthDrawing(itemRow(0)))
        assert.is_false(Panel.CardWorthDrawing(itemRow(-0.01)))
        assert.is_false(Panel.CardWorthDrawing(itemRow("-0.5")))
        local crown = rowWhere(m, "Head", function(row)
            return row.name == "Crown of Roaring Storms" and row.group == ns.Roads.GROUP_ITEM
        end)
        assert.equal(ns.Roads.PHRASE_NOT_IN_BEST_SET, crown.road.phrase)
        assert.is_false(Panel.CardWorthDrawing(crown))
        -- A crested-only upgrade: worse as it drops, above zero with its
        -- crests spent (the `max` row, out of the same document).
        local shawl = rowWhere(m, "Back", function(row)
            return row.name == "Amani Summoning Shawl" and row.group == ns.Roads.GROUP_ITEM
        end)
        assert.is_false(ns.UFImport.IsUpgrade({ upgradePercent = shawl.road.rating.percent }))
        assert.is_true(Panel.CardWorthDrawing(shawl))
        assert.is_true(Panel.CardWorthDrawing(itemRow(-0.2, { { dropType = "max", percent = 0.3 } })))
        assert.is_false(Panel.CardWorthDrawing(itemRow(-0.2, { { dropType = "max", percent = 0 } })))
        -- The bonus-roll row is not the crested row: his `bonus` state is the
        -- vault / bonus-roll copy (UpgradeFinderEngine.js:259), not this drop.
        assert.is_false(Panel.CardWorthDrawing(itemRow(-0.2, { { dropType = "bonus", percent = 0.5 } })))
        local guise = rowWhere(m, "Head", function(row)
            return row.name == "Vilefiend's Guise" and row.group == ns.Roads.GROUP_ITEM
        end)
        assert.is_false(Panel.CardWorthDrawing(guise))
        -- The same on a drop rated at another level (UX-6b's rows, whole).
        local hide = otherLevelRow(m, "Chest", "Hide of Pestilence")
        assert.is_false(ns.UFImport.IsUpgrade(hide.otherLevel.drop.entry))
        assert.is_true(ns.UFImport.IsUpgrade(hide.otherLevel.max.entry))
        assert.is_true(Panel.CardWorthDrawing(hide))
        assert.is_true(Panel.CardWorthDrawing(otherLevelRow(m, "Head", "Shadow Hunter's Warmask")))
        local both = Panel.OtherLevelRating({
            document(2, { { 295, "drop", -0.1 }, { 308, "max", 0.2 } }),
        }, 1001)
        assert.is_true(Panel.CardWorthDrawing(Panel.OtherLevelRow({ itemLevel = 276 }, both)))
        local neither = Panel.OtherLevelRating({
            document(2, { { 295, "drop", -0.1 }, { 308, "max", 0 } }),
        }, 1001)
        assert.is_false(Panel.CardWorthDrawing(Panel.OtherLevelRow({ itemLevel = 276 }, neither)))
        assert.is_false(Panel.CardWorthDrawing(otherLevelRow(m, "Head", "Crown of Roaring Storms")))
        -- The set group's pick, and a whole-set verdict IN the best set.
        local catalyst = rowWhere(m, "Shoulder", function(row)
            return row.planPick
        end)
        assert.is_true(Panel.CardWorthDrawing(catalyst))
        assert.is_true(Panel.CardWorthDrawing({ planPick = true, road = {} }))
        assert.is_true(Panel.CardWorthDrawing({ road = { rating = { kind = ns.Roads.RATING_SET, inTopSet = true } } }))
        -- A later pass's verdict is a verdict.
        assert.is_true(Panel.CardWorthDrawing({ road = { phrase = ns.Roads.PHRASE_RATED_LATER } }))
        -- `not in your best set`: a whole-set alternative behind the pick, and
        -- a vault reward the run passed over.
        local vault = rowWhere(m, "Shoulder", function(row)
            return row.kind == ns.Roads.KIND_VAULT and row.group == ns.Roads.GROUP_SET
        end)
        assert.equal("1.73% behind", vault.badge.text)
        assert.is_false(Panel.CardWorthDrawing(vault))
        assert.is_false(Panel.CardWorthDrawing({
            kind = ns.Roads.KIND_VAULT,
            road = { phrase = ns.Roads.PHRASE_NOT_IN_BEST_SET, rating = { kind = ns.Roads.RATING_NONE } },
        }))
        -- No figure: never drawn on its own.
        assert.is_false(Panel.CardWorthDrawing(section(m, "Head").noRating.unknown[1]))
        assert.is_false(Panel.CardWorthDrawing(itemRow(nil)))
        assert.is_false(Panel.CardWorthDrawing({ road = { rating = { kind = ns.Roads.RATING_NONE } } }))
        assert.is_false(Panel.CardWorthDrawing(nil))
        -- A step the answer goes forward on is always drawn; the refresh and
        -- `keep what you've got on` are not such steps.
        assert.is_true(Panel.CardWorthDrawing({ todo = ns.Roads.TODO_TAKE_VAULT, road = {} }))
        assert.is_true(Panel.CardWorthDrawing({ todo = ns.Roads.TODO_CATALYST, road = {} }))
        assert.is_false(Panel.CardWorthDrawing({ todo = ns.Roads.TODO_REFRESH, road = {} }))
        assert.is_false(Panel.CardWorthDrawing({ todo = ns.Roads.TODO_KEEP_WORN, road = {} }))
        -- Every road the model gives an imperative is drawn, so the slot that
        -- starts open always opens onto a card (FirstWorthTaking is untouched).
        for _, entry in ipairs(m.slots) do
            for _, group in ipairs(entry.roadGroups or {}) do
                for _, row in ipairs(Panel.CardRows(group)) do
                    if Panel.IsImperative(row.todo) then
                        assert.is_true(Panel.CardWorthDrawing(row), entry.slot .. " " .. tostring(row.name))
                    end
                end
            end
        end
    end)

    it("counts each slot's drawn and folded roads on the committed week (UX-6c)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local counts = {}
        for _, entry in ipairs(m.slots) do
            if entry.roadGroups then
                local state = shutAllBut(m, entry.slot)
                local drawn, fold = 0, nil
                for _, element in ipairs(under(elements(m, state), entry.slot)) do
                    drawn = drawn + #(element.cards or {})
                    if element.kind == Panel.ELEMENT_FOLD then
                        fold = element
                    end
                end
                counts[entry.slot] = { drawn, fold and fold.rated or 0, fold and fold.unrated or 0 }
            end
        end
        -- drawn / folded, rated below what you wear / folded, not rated
        assert.same({ 5, 14, 16 }, counts.Head)
        assert.same({ 16, 0, 18 }, counts.Chest)
        assert.same({ 20, 26, 30 }, counts.Trinket)
        assert.same({ 18, 5, 0 }, counts.Back)
        assert.same({ 0, 20, 37 }, counts["1H Weapon"])
        -- A slot with nothing worth drawing: no badge, no card, the fold alone;
        -- and it is not the slot that starts open.
        local list = elements(m, { slots = {} })
        assert.is_nil(sectionElement(list, "1H Weapon").badge)
        assert.equal("Head", Panel.FirstWorthTaking(m))
        for _, slot in ipairs({ "1H Weapon", "Offhand", "Shield" }) do
            assert.equal(0, counts[slot][1], slot)
        end
    end)

    -- UX-6d (WKE-641): a card drawn only because its crested row is above
    -- zero wears that row. The owner: "badge them and show the player it
    -- would be better if they [crested] it."
    it("wears the drop row if it is an upgrade, else the crested row if it is (UX-6d)", function()
        local Panel = ns.UpgradeMapPanel
        local up, tie, down = { percent = 0.2 }, { percent = 0 }, { percent = -0.1 }
        local crest, flat = { percent = 0.5 }, { percent = 0 }
        assert.equal(up, Panel.WornRow(up, crest))
        assert.equal(crest, Panel.WornRow(tie, crest))
        assert.equal(crest, Panel.WornRow(down, crest))
        assert.equal(tie, Panel.WornRow(tie, flat))
        assert.equal(down, Panel.WornRow(down, nil))
        assert.equal(crest, Panel.WornRow(nil, crest))
        assert.equal(flat, Panel.WornRow(nil, flat))
        assert.is_nil(Panel.WornRow(nil, nil))
        -- The same choice is what decides a card is drawn, so the two cannot
        -- disagree: drawn exactly when the worn row is an upgrade.
        local shapes = {
            itemRow(0.3),
            itemRow(0),
            itemRow(-0.2, { { dropType = "max", percent = 0.3 } }),
            itemRow(-0.2, { { dropType = "max", percent = 0 } }),
            itemRow(-0.2, { { dropType = "bonus", percent = 0.5 } }),
        }
        for index, row in ipairs(shapes) do
            local worn = Panel.WornRow(Panel.CardRatingRows(row))
            assert.equal(
                ns.UFImport.IsUpgrade({ upgradePercent = worn.percent }) == true,
                Panel.CardWorthDrawing(row),
                "shape " .. index
            )
        end
    end)

    it("wears the crested figure on a card drawn only for its crested row, and says to crest it (UX-6d)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        -- Rated at another level: drops at 276, his drop row at 295 is not
        -- above zero, his crested row at 308 is.
        local hide = otherLevelRow(m, "Chest", "Hide of Pestilence")
        assert.same({ text = "+0.14%", tone = "better" }, Panel.CardBadge(hide))
        assert.equal("crest it to 308", Panel.CardLine(hide))
        local hideHover = Panel.CardTooltipLines(hide)
        assert.equal("drops at 276 · not better at 295 · crested to 308, +0.14%", hideHover[1])
        assert.is_nil(table.concat(hideHover, "\n"):find("crested to 308 · ", 1, true))
        -- Its figures are still his rows, whole.
        assert.equal(hide.otherLevel.max.entry.upgradePercent, hide.otherLevel.max.percent)

        -- Rated at the level it drops: the model's road is untouched, the card
        -- drawn for it wears the cap row out of the same document.
        local shawl = rowWhere(m, "Back", function(row)
            return row.name == "Amani Summoning Shawl" and row.group == ns.Roads.GROUP_ITEM
        end)
        local face = Panel.CardFace(shawl)
        assert.are_not.equal(shawl, face)
        assert.same({ text = "+0.31%", tone = "better" }, Panel.CardBadge(face))
        assert.equal("crest it to 334", Panel.CardLine(face))
        local hover = Panel.CardTooltipLines(face)
        assert.equal("drops at 318 · not better as it drops · crested to 334, +0.31%", hover[1])
        local joined = table.concat(hover, "\n")
        assert.is_nil(joined:find("at its cap", 1, true), joined)
        assert.is_not_nil(joined:find("crest type and cost not readable", 1, true), joined)
        assert.is_not_nil(joined:find("click: show the run", 1, true), joined)
        -- The road, its row and the printed line are what they were: the
        -- printed line already carries the cap clause.
        assert.same({ text = ns.Roads.PHRASE_NOT_IN_BEST_SET, tone = "none" }, shawl.badge)
        assert.equal(ns.Roads.TODO_KEEP_WORN, shawl.todo)
        assert.is_not_nil(Panel.RoadLineText(shawl):find("at its cap 334 +0.31%", 1, true))
        assert.is_nil(Panel.RoadLineText(shawl):find("crest it", 1, true))
        -- And that face is the card the list draws.
        local drawnShawl
        for _, element in ipairs(under(elements(m, shutAllBut(m, "Back")), "Back")) do
            for _, card in ipairs(element.cards or {}) do
                if card.row.name == "Amani Summoning Shawl" then
                    drawnShawl = card.row
                end
            end
        end
        assert.equal("crest it to 334", Panel.CardLine(drawnShawl))
        assert.equal("+0.31%", Panel.CardBadge(drawnShawl).text)

        -- A drop row above zero keeps the drop face, the crested row on the hover.
        local warmask = otherLevelRow(m, "Head", "Shadow Hunter's Warmask")
        assert.equal("rated at 321", Panel.CardLine(warmask))
        assert.same({ text = "+0.17%", tone = "better" }, Panel.CardBadge(warmask))
        assert.equal("crested to 334 · +0.75%", Panel.CardTooltipLines(warmask)[2])
        local gaze = rowWhere(m, "Head", function(row)
            return row.name == "Gaze of the Coiled Watcher" and row.group == ns.Roads.GROUP_ITEM
        end)
        assert.equal(gaze, Panel.CardFace(gaze))
        -- Neither above zero: the drop face, as before (and folded).
        local crown = rowWhere(m, "Head", function(row)
            return row.name == "Crown of Roaring Storms" and row.group == ns.Roads.GROUP_ITEM
        end)
        assert.equal(crown, Panel.CardFace(crown))
        -- No drop row at all: UX-6b's crested-only card, unchanged.
        local maxOnly = Panel.OtherLevelRating({ document(nil, { { 334, "max", 0.5 } }) }, 1001)
        local row = Panel.OtherLevelRow({ itemLevel = 308, kind = ns.Roads.KIND_DROP }, maxOnly)
        assert.equal("crested to 334", Panel.CardLine(row))
        assert.same({ "+0.50% · crested to 334, drops at 308" }, Panel.CardTooltipLines(row))
        -- A hand-built pair: the crested row worn, its hover naming both.
        local pair = Panel.OtherLevelRating({ document(2, { { 295, "drop", -0.1 }, { 308, "max", 0.2 } }) }, 1001)
        local worn = Panel.OtherLevelRow({ itemLevel = 276 }, pair)
        assert.same({ text = "+0.20%", tone = "better" }, worn.badge)
        assert.equal("crest it to 308", Panel.CardLine(worn))
        assert.same({ "drops at 276 · not better at 295 · crested to 308, +0.20%" }, worn.otherLevelHover)
    end)

    it("puts a positive badge on every drawn rated card of the committed week (UX-6d)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        local crested, total, flat = {}, 0, {}
        for _, entry in ipairs(m.slots) do
            if entry.roadGroups then
                for _, element in ipairs(under(elements(m, shutAllBut(m, entry.slot)), entry.slot)) do
                    for _, card in ipairs(element.cards or {}) do
                        local row = card.row
                        if row.group == ns.Roads.GROUP_ITEM then
                            if not (row.badge and row.badge.tone == "better") then
                                flat[#flat + 1] = entry.slot .. " " .. tostring(row.name)
                            end
                            local line = Panel.CardLine(row) or ""
                            if line:find("^crest it to %d+$") then
                                crested[entry.slot] = (crested[entry.slot] or 0) + 1
                                total = total + 1
                            end
                        end
                    end
                end
            end
        end
        assert.same({}, flat)
        -- The other-level cards sort by the figure they wear, best first, so a
        -- crested badge takes its place among the drop badges.
        for _, entry in ipairs(m.slots) do
            local last
            for _, row in ipairs(entry.noRating and entry.noRating.otherLevel or {}) do
                local worn = tonumber(Panel.WornRow(row.otherLevel.drop, row.otherLevel.max).percent) or 0
                assert.is_true(last == nil or worn <= last, entry.slot .. " " .. tostring(row.name))
                last = worn
            end
        end
        -- The 46 UX-6c counted wearing `not in your best set`, each slot's own.
        assert.same({
            Shoulder = 6,
            Back = 6,
            Chest = 2,
            Wrist = 2,
            Hands = 2,
            Waist = 4,
            Legs = 8,
            Feet = 4,
            Trinket = 4,
            ["2H Weapon"] = 8,
        }, crested)
        assert.equal(46, total)
    end)

    it("says a vault reward not rated yet once, beside the bags, never on a card (UX-6b)", function()
        local Panel = ns.UpgradeMapPanel
        local vault = { kind = ns.Roads.KIND_VAULT, phrase = ns.Roads.PHRASE_NOT_RATED_NEW }
        local function slotWith(roads, stale)
            return { staleBags = stale, roads = { groups = { [ns.Roads.GROUP_NONE] = roads } } }
        end
        local m = {
            slots = {
                slotWith({ vault }),
                slotWith({ vault, { kind = ns.Roads.KIND_DROP, phrase = ns.Roads.PHRASE_NO_RATING } }, true),
            },
        }
        assert.equal(
            "your bags changed since this rating · 2 vault rewards not rated yet · Refresh",
            Panel.StaleNudge(m)
        )
        m.slots[2].staleBags = false
        assert.equal("2 vault rewards not rated yet · Refresh", Panel.StaleNudge(m))
        m.slots[2] = slotWith({}, false)
        assert.equal("1 vault reward not rated yet · Refresh", Panel.StaleNudge(m))
        m.slots[1] = slotWith({ { kind = ns.Roads.KIND_DROP, phrase = ns.Roads.PHRASE_NOT_RATED_NEW } })
        assert.equal("1 item not rated yet · Refresh", Panel.StaleNudge(m))
        m.slots[1] = slotWith({}, false)
        assert.is_nil(Panel.StaleNudge(m))
        -- The committed week has no such road: the nudge is UX-6's, byte for byte.
        local week = model()
        assert.is_nil(Panel.NotRatedYetText(week))
        assert.equal(Panel.STALE_NUDGE, Panel.StaleNudge(week))
    end)

    it("keeps the `show no value` note off the cards that now show one, and in the printed lines (UX-6b)", function()
        local Panel = ns.UpgradeMapPanel
        local m = model()
        assert.is_string(m.levelMismatchNote)
        local every = allOpen(m)
        for _, element in ipairs(elements(m, every)) do
            assert.are_not.equal(m.levelMismatchNote, element.text)
        end
        local printed = false
        for _, line in ipairs(Panel.Lines(m)) do
            printed = printed or line == m.levelMismatchNote
        end
        assert.is_true(printed)
    end)
end)

-- ---------------------------------------------------------------------------
-- The verbs, on the frames, and the Vault tab's headline.

describe("Roads on the window, over the owner's week of 2026-09-08", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        ns.UI.Options.Set("Dungeon")
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
        R.vault(world, R.snapshot("vault", VAULT_SNAPSHOT, CAPTURE))
        world.currencyByID = { [3465] = CATALYST }
        ns.db.global.captures.journal = { R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ) }

        local exports = {}
        for _, name in ipairs(SCENARIO_ORDER) do
            exports[#exports + 1] = {
                schema = "qe-live-droptimizer",
                contentType = "Dungeon",
                scenario = name,
                -- The three boxes each run really used, as the companion
                -- records them per document: `CatalyzedOwned` reads them, so a
                -- document without them is a plan that catalyzes nothing.
                qeSettings = {
                    autoUpgradeVault = name == "maxed" or name == "thisWeek",
                    autoUpgradeAll = name == "maxed",
                    autoCatalyze = name ~= "asOffered",
                },
                json = readFile(SCENARIO_FILES[name]),
            }
        end
        for _, entry in ipairs(UPGRADE_DOCUMENTS) do
            exports[#exports + 1] = {
                schema = "qe-live-upgradefinder",
                contentType = entry.contentType,
                keyLevel = entry.keyLevel,
                json = readFile(entry.file),
            }
        end
        local imported = ns.Companion.ImportAll({ writtenAt = "2026-09-09T19:22:00Z", exports = exports })
        assert.is_true(imported.ok, imported.reason)

        frame = ns.UI.Frame()
        frame.tabs[2]:Click()
    end)

    after_each(function()
        H.unload()
    end)

    -- Since UX-6 (WKE-637) only the first slot worth taking starts open, so
    -- the row is found by walking the model rather than the drawn list.
    local function rowWith(verb)
        for _, section in ipairs(frame.upgradeMapPanel.model.slots) do
            for _, group in ipairs(section.roadGroups or {}) do
                for _, row in ipairs(group.rows) do
                    if row.verb == verb then
                        return row
                    end
                end
            end
        end
        return nil
    end

    -- One card row of one open slot, bound to a fresh element frame the way
    -- the scroll box binds one.
    local function boundCardRow(panel, model, slot, nth, foldOpen)
        local state = { slots = {}, fold = { [slot] = foldOpen or nil } }
        for _, entry in ipairs(model.slots) do
            state.slots[entry.slot] = entry.slot ~= slot
        end
        local seen, inside = 0, false
        for _, data in ipairs(ns.UpgradeMapPanel.Elements(model, state)) do
            if data.kind == ns.UpgradeMapPanel.ELEMENT_SECTION then
                inside = data.slot == slot
            elseif inside and data.kind == ns.UpgradeMapPanel.ELEMENT_CARD_ROW then
                seen = seen + 1
                if seen == nth then
                    local element = CreateFrame("Frame", nil, panel)
                    ns.UpgradeMapPanel.InitElement(panel, element, data)
                    return element, data
                end
            end
        end
        return nil
    end

    -- The walk with the art a post-M5-3 walk records put on it, the way the
    -- by-run tests do: a stub-shaped value, never a real instance's file.
    local function modelWithArt()
        local gathered = ns.UpgradeMapPanel.Gather({ db = ns.db })
        local withArt = {}
        for itemID, list in pairs(gathered.sources) do
            local copies = {}
            for index, entry in ipairs(list) do
                local copy = {}
                for k, v in pairs(entry) do
                    copy[k] = v
                end
                copy.instanceImage = 4000 + (entry.instanceID or 0)
                copies[index] = copy
            end
            withArt[itemID] = copies
        end
        gathered.sources = withArt
        return ns.UpgradeMapPanel.Model(gathered)
    end

    it("draws a card over the instance's own art, and over the item's icon when the walk has none (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local panel = frame.upgradeMapPanel
        -- Head's first card row is its rated drops: a raid drop, then a craft
        -- (since UX-6c the set group's one road, rated behind, is folded).
        local element, data = boundCardRow(panel, modelWithArt(), "Head", 1)
        assert.is_table(element)
        local drop, craft = element.cards[1], element.cards[2]
        assert.equal(ns.Roads.KIND_DROP, data.cards[1].row.kind)
        assert.equal(ns.Roads.KIND_CRAFT, data.cards[2].row.kind)
        local source = data.cards[1].row.road.source
        assert.equal(4000 + source.instanceID, data.cards[1].art)
        assert.equal(4000 + source.instanceID, drop.art:GetTexture())
        assert.same(Panel.TILE_ART_TEX_COORD, drop.art.texCoord)
        assert.equal(1, drop.art:GetAlpha())
        -- The craft has no instance: its own icon, cropped to the card.
        assert.is_nil(data.cards[2].art)
        assert.equal(craft.cardIcon.resolved.icon, craft.art:GetTexture())
        assert.same(Panel.MosaicTexCoord(data.tileWidth, data.tileHeight), craft.art.texCoord)
        assert.equal(Panel.MOSAIC_ALPHA, craft.art:GetAlpha())
        -- The card's own strings, the badge on its plate, the icon at 28.
        local row = data.cards[1].row
        assert.equal(Panel.CardSecond(row), drop.second:GetText())
        assert.equal(Panel.CardLine(row), drop.cardLine:GetText())
        assert.equal(ns.UI.ItemLine.BadgeText(row.badge), drop.badge:GetText())
        assert.is_true(drop.badgePlate:IsShown())
        assert.equal(Panel.CARD_ICON_SIZE, drop.cardIcon:GetWidth())
        assert.equal(data.tileWidth, drop:GetWidth())
        assert.equal(1, drop:GetAlpha())
        -- ...placed across, past the icon column.
        assert.equal(Panel.CARD_INDENT, drop.points[1][4])
        assert.equal(Panel.CARD_INDENT + data.tileWidth + Panel.TILE_GAP, craft.points[1][4])

        -- The committed walk predates the art: every drop card then draws its
        -- item's own icon, and nothing is borrowed from another instance.
        local plain = boundCardRow(panel, Panel.Model(Panel.Gather({ db = ns.db })), "Head", 1)
        assert.equal(plain.cards[1].cardIcon.resolved.icon, plain.cards[1].art:GetTexture())
        assert.equal(Panel.MOSAIC_ALPHA, plain.cards[1].art:GetAlpha())
    end)

    it("dims a no-rating card and puts its phrase on the second line (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local panel = frame.upgradeMapPanel
        local element, data
        for nth = 1, 20 do
            -- Behind the fold since UX-6b (one fold since UX-6c): opened, as a
            -- click would.
            element, data = boundCardRow(panel, panel.model, "Head", nth, true)
            if data and data.group == ns.Roads.GROUP_NONE then
                break
            end
        end
        assert.equal(ns.Roads.GROUP_NONE, data.group)
        local tile = element.cards[1]
        assert.equal(Panel.TILE_DIM_ALPHA, tile:GetAlpha())
        assert.equal(ns.Roads.PHRASE_NO_RATING, tile.second:GetText())
        assert.is_false(tile.badgePlate:IsShown())
    end)

    it("follows a card click to the run, and a vault card to the vault (UX-6)", function()
        local panel = frame.upgradeMapPanel
        local element, data = boundCardRow(panel, panel.model, "Head", 1)
        local row = data.cards[1].row
        assert.is_string(row.runKey)
        assert.equal(ns.UpgradeMapPanel.MODE_SLOT, panel.mode)
        -- A craft card goes nowhere: a click on it changes nothing.
        element.cards[2]:Click()
        assert.equal(ns.UpgradeMapPanel.MODE_SLOT, panel.mode)
        element.cards[1]:Click()
        assert.equal(ns.UpgradeMapPanel.MODE_RUN, panel.mode)
        assert.is_true(ns.db.char.upgradeMap.expandedRuns[row.runKey])
        assert.equal(ns.UpgradeMapPanel.ELEMENT_RUN_ROW, panel.scrollBox.scrolledTo.kind)

        panel.modeButtons[1]:Click()
        -- Neck's vault reward is rated behind what is worn, so since UX-6c it
        -- is behind the fold: opened, its card clicks through as before.
        local vaultCard
        for nth = 1, 10 do
            local vault = boundCardRow(panel, panel.model, "Neck", nth, true)
            for _, card in ipairs(vault and vault.cards or {}) do
                if card:IsShown() and card.card and card.card.row.verb == ns.Roads.VERB_SHOW_IN_VAULT then
                    vaultCard = vaultCard or card
                end
            end
        end
        assert.is_table(vaultCard)
        vaultCard:Click()
        assert.equal(ns.UI.VAULT_TAB, frame.selectedTab)
        assert.equal(vaultCard.card.row.vaultKey, ns.VaultPanel.pointedAt)
    end)

    it("hovers a card as the item's own tooltip, then its badge, facts and click (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local panel = frame.upgradeMapPanel
        local element, data = boundCardRow(panel, panel.model, "Head", 1)
        local row = data.cards[1].row
        element.cards[1].stub.Enter()
        local text = GameTooltip.stub.Text()
        assert.is_true(GameTooltip.hyperlink == row.link or GameTooltip.itemID == row.itemID)
        for _, line in ipairs(Panel.CardTooltipLines(row)) do
            assert.is_not_nil(text:find(line, 1, true), line)
        end
        assert.is_not_nil(text:find("click: show the run", 1, true))
    end)

    it("says the bags changed once, under the header, in the slot view only (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local panel = frame.upgradeMapPanel
        assert.equal(Panel.MODE_SLOT, panel.mode)
        assert.is_true(panel.answer:IsShown())
        local text = panel.answer:GetText()
        local _, count = text:gsub((Panel.STALE_NUDGE:gsub("%p", "%%%0")), "")
        assert.equal(1, count)
        assert.is_not_nil(text:find("|cff" .. Panel.STALE_HEX, 1, true))
        panel.modeButtons[2]:Click()
        assert.is_nil((panel.answer:GetText() or ""):find(Panel.STALE_NUDGE, 1, true))
    end)

    it("toggles a slot line on a click and keeps it per character (UX-6)", function()
        local Panel = ns.UpgradeMapPanel
        local panel = frame.upgradeMapPanel
        -- Bound the way the scroll box binds a frame, from the list the panel
        -- drew: a slot below the fold has no frame of its own in the stub.
        local function lineFor(slot)
            for _, data in ipairs(panel.elements) do
                if data.kind == Panel.ELEMENT_SECTION and data.slot == slot then
                    local element = CreateFrame("Frame", nil, panel)
                    Panel.InitElement(panel, element, data)
                    return element, data
                end
            end
            return nil
        end
        local head, data = lineFor("Head")
        assert.is_false(data.collapsed)
        assert.equal("Head", head.sectionName:GetText())
        assert.equal(ns.UI.ItemLine.BadgeText(data.badge), head.sectionBadge:GetText())
        head.sectionButton:Click()
        assert.is_true(ns.db.char.upgradeMap.collapsedSlots.Head)
        head = lineFor("Head")
        head.sectionButton:Click()
        assert.is_false(ns.db.char.upgradeMap.collapsedSlots.Head)
        local neck, neckData = lineFor("Neck")
        assert.is_true(neckData.collapsed)
        neck.sectionButton:Click()
        assert.is_false(ns.db.char.upgradeMap.collapsedSlots.Neck)
        -- Its hover is the slot's own sentence and the long headers.
        head = lineFor("Head")
        head.sectionButton.stub.Enter()
        assert.is_not_nil(GameTooltip.stub.Text():find(panel.model.slots[1].plan, 1, true))
    end)

    it("puts roads on the tab the window opens, under the one slot worth taking", function()
        local panel = frame.upgradeMapPanel
        assert.is_true(panel.model.hasRoads)
        local groups, folds, cards, open = 0, 0, 0, {}
        for _, element in ipairs(panel.elements) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_GROUP then
                groups = groups + 1
            elseif element.kind == ns.UpgradeMapPanel.ELEMENT_FOLD then
                folds = folds + 1
            elseif element.kind == ns.UpgradeMapPanel.ELEMENT_CARD_ROW then
                cards = cards + #element.cards
            elseif element.kind == ns.UpgradeMapPanel.ELEMENT_SECTION and not element.collapsed then
                open[#open + 1] = element.slot
            end
        end
        -- Since UX-6 (WKE-637) one slot opens by itself - the first worth
        -- taking - and every card under it is one of its roads.
        assert.same({ "Head" }, open)
        -- Head's upgrades and the one fold over everything else (UX-6c): 35
        -- roads, 30 of them behind the fold, shut by default.
        assert.equal(1, groups)
        assert.equal(1, folds)
        assert.equal(5, cards)
    end)

    it("draws a card with its item, its second line and its step, on screen", function()
        local panel = frame.upgradeMapPanel
        local element
        for _, candidate in ipairs(panel.scrollBox:GetFrames()) do
            local data = candidate:GetElementData()
            if data.kind == ns.UpgradeMapPanel.ELEMENT_CARD_ROW and element == nil then
                element = candidate
            end
        end
        assert.is_not_nil(element)
        local data = element:GetElementData()
        for index, card in ipairs(data.cards) do
            local tile = element.cards[index]
            assert.is_true(tile:IsShown())
            assert.equal(card.row.name or tile.cardIcon.resolved.name, tile.name:GetText())
            assert.equal(ns.UpgradeMapPanel.CardSecond(card.row) or "", tile.second:GetText())
            assert.equal(ns.UpgradeMapPanel.CardLine(card.row) or "", tile.cardLine:GetText())
        end
        for index = #data.cards + 1, ns.UpgradeMapPanel.TILES_PER_ROW do
            assert.is_false(element.cards[index]:IsShown())
        end
    end)

    -- The gold edge is the answer's own pick and nothing else, which needs a
    -- card of each to say: Shoulder's first card is its Catalyst pick and the
    -- vault card is not (behind the fold since UX-6c, rated 1.73% behind the
    -- pick, so the fold is opened for it), and a pooled card that drew a pick
    -- must lose the edge when it comes back as something else.
    it("puts the gold edge on the pick and takes it off everything else", function()
        local panel = frame.upgradeMapPanel
        local element, data = boundCardRow(panel, panel.model, "Shoulder", 1)
        assert.is_true(data.cards[1].row.planPick)
        for _, edge in ipairs(element.cards[1].edges) do
            assert.is_true(edge:IsShown())
        end
        local vaultElement, vaultData
        for nth = 1, 10 do
            vaultElement, vaultData = boundCardRow(panel, panel.model, "Shoulder", nth, true)
            if vaultData and vaultData.cards[1].row.kind == ns.Roads.KIND_VAULT then
                break
            end
        end
        assert.equal(ns.Roads.KIND_VAULT, vaultData.cards[1].row.kind)
        assert.is_false(vaultData.cards[1].row.planPick)
        for _, edge in ipairs(vaultElement.cards[1].edges) do
            assert.is_false(edge:IsShown())
        end
        -- The same frames re-bound to Head's rated drops: no edge anywhere.
        local _, headData = boundCardRow(panel, panel.model, "Head", 1)
        ns.UpgradeMapPanel.InitElement(panel, element, headData)
        for _, tile in ipairs(element.cards) do
            for _, edge in ipairs(tile.edges) do
                assert.is_false(edge:IsShown())
            end
        end
    end)

    it("scrolls the by-run view to the run when Show run is clicked", function()
        local panel = frame.upgradeMapPanel
        local row = rowWith(ns.Roads.VERB_SHOW_RUN)
        assert.is_not_nil(row)
        assert.equal(ns.UpgradeMapPanel.MODE_SLOT, panel.mode)
        ns.UpgradeMapPanel.FollowVerb(panel, row)
        assert.equal(ns.UpgradeMapPanel.MODE_RUN, panel.mode)
        -- The card is open, and the box was asked to put THAT run on screen.
        assert.is_true(ns.db.char.upgradeMap.expandedRuns[row.runKey])
        local scrolled = panel.scrollBox.scrolledTo
        assert.is_table(scrolled)
        -- Since UX-5 (WKE-614) a run is a TILE in a row of four rather than an
        -- element of its own, so what the box is asked for is the row that
        -- carries it.
        assert.equal(ns.UpgradeMapPanel.ELEMENT_RUN_ROW, scrolled.kind)
        local found = false
        for _, run in ipairs(scrolled.runs) do
            found = found or run.key == row.runKey
        end
        assert.is_true(found)
    end)

    -- Red for the line above: a run key the by-run view does not have scrolls
    -- to nothing rather than to the nearest thing.
    it("scrolls to nothing when the run is not in the by-run list", function()
        local panel = frame.upgradeMapPanel
        ns.UpgradeMapPanel.ShowRun(panel, "dungeon:9999:8:10")
        assert.is_nil(panel.scrollBox.scrolledTo)
    end)

    it("opens the Vault tab at the cell when Show in vault is clicked", function()
        local panel = frame.upgradeMapPanel
        local row = rowWith(ns.Roads.VERB_SHOW_IN_VAULT)
        assert.is_not_nil(row)
        ns.UpgradeMapPanel.FollowVerb(panel, row)
        assert.equal(ns.UI.VAULT_TAB, frame.selectedTab)
        assert.equal(row.vaultKey, ns.VaultPanel.pointedAt)
        -- Exactly one cell is marked, and it is the one holding that reward.
        local marked = 0
        for _, gridRow in ipairs(frame.vaultPanel.gridRows) do
            for _, cell in ipairs(gridRow.cells) do
                if cell.flash:IsShown() then
                    marked = marked + 1
                    assert.equal(row.vaultKey, cell.data.reward.key)
                end
            end
        end
        assert.equal(1, marked)
    end)

    -- Red for the line above: the mark goes away on its own, and nothing else
    -- about the cell moved while it was there.
    it("takes the mark off again when its time is up", function()
        local panel = frame.upgradeMapPanel
        ns.UpgradeMapPanel.FollowVerb(panel, rowWith(ns.Roads.VERB_SHOW_IN_VAULT))
        world.runTimers(ns.VaultPanel.POINT_SECONDS + 1)
        assert.is_nil(ns.VaultPanel.pointedAt)
        for _, gridRow in ipairs(frame.vaultPanel.gridRows) do
            for _, cell in ipairs(gridRow.cells) do
                assert.is_false(cell.flash:IsShown())
            end
        end
    end)

    it("opens the Vault tab with the week's plan as its first words", function()
        frame.tabs[3]:Click()
        local panel = frame.vaultPanel
        local plan = panel.model.headline.plan
        assert.equal(
            "Grab the Worldroot from the vault and crest it."
                .. " Catalyst the Lynx shoulders in your bag."
                .. " Skip the vault shoulders.",
            plan.sentence
        )
        assert.equal("You could catalyst the Hide chest too, but you've only got one charge.", plan.footnote)
        -- Drawn above the pick, and the pick is still there under it.
        assert.equal(plan.sentence, panel.headline.plan:GetText())
        assert.equal(plan.footnote, panel.headline.planFootnote:GetText())
        assert.equal(panel.model.headline.text, panel.headline.text:GetText())
        -- The first thing the tab says after its own notes (this transcript's
        -- export predates the reset, so there is one), and the pick's line is
        -- the one under it.
        local printed = ns.VaultPanel.Lines(panel.model)
        local at
        for index, line in ipairs(printed) do
            if line == plan.sentence then
                at = index
            end
        end
        assert.is_number(at)
        assert.equal("  " .. plan.footnote, printed[at + 1])
        assert.equal(panel.model.headline.text, printed[at + 2])
        -- The sentence says what to do and names nobody.
        assert.is_nil(usesForbidden(plan.sentence), plan.sentence)
        assert.is_nil(usesForbidden(plan.footnote), plan.footnote)
    end)

    -- The headline block is laid out by hand rather than by a scroll box, so a
    -- sentence that wraps has to be given the room it takes: a plan twice as
    -- long as one line is twice as tall, and a block with no plan takes none.
    it("gives a wrapping plan sentence the room it needs", function()
        local one = string.rep("a", ns.VaultPanel.PLAN_CHARS_PER_LINE)
        assert.equal(14, ns.VaultPanel.PlanHeight(one, 14))
        assert.equal(28, ns.VaultPanel.PlanHeight(one .. "b", 14))
        assert.equal(0, ns.VaultPanel.PlanHeight(nil, 14))
        assert.equal(0, ns.VaultPanel.PlanHeight("", 14))
        -- ...and the block on screen is given at least that much room, on top
        -- of the pick's icon, for the two sentences it is really carrying.
        frame.tabs[3]:Click()
        local plan = frame.vaultPanel.model.headline.plan
        local needed = ns.VaultPanel.PlanHeight(plan.sentence, 18) + ns.VaultPanel.PlanHeight(plan.footnote, 14)
        -- Three lines for the sentence and two for the footnote, over this week.
        assert.equal(54 + 28, needed)
        assert.is_true(frame.vaultPanel.headline:GetHeight() >= 32 + needed)
    end)

    -- -----------------------------------------------------------------------
    -- UX-6b (WKE-639): the fold, clicked, and the client's own spec answer.

    local function foldFor(panel, slot)
        for _, data in ipairs(panel.elements) do
            if data.kind == ns.UpgradeMapPanel.ELEMENT_FOLD and data.slot == slot then
                return data
            end
        end
        return nil
    end

    local function cardsUnder(panel, slot)
        local count, inside = 0, false
        for _, data in ipairs(panel.elements) do
            if data.kind == ns.UpgradeMapPanel.ELEMENT_SECTION then
                inside = data.slot == slot
            elseif inside then
                count = count + #(data.cards or {})
            end
        end
        return count
    end

    it("opens and shuts a slot's fold on a click, per character, its hover the two counts (UX-6c)", function()
        local Panel = ns.UpgradeMapPanel
        local panel = frame.upgradeMapPanel
        local data = foldFor(panel, "Head")
        assert.equal("+ 30 more items", data.text)
        assert.equal(5, cardsUnder(panel, "Head"))
        local element = CreateFrame("Frame", nil, panel)
        Panel.InitElement(panel, element, data)
        assert.equal("+ 30 more items", element.foldText:GetText())
        assert.is_true(element.foldButton:IsShown())
        element.foldButton.stub.Enter()
        assert.equal("14 rated below what you wear · 16 not rated", GameTooltip.stub.Text())
        element.foldButton.stub.Leave()
        element.foldButton:Click()
        assert.is_true(ns.db.char.upgradeMap.foldOpen.Head)
        assert.equal("- 30 more items", foldFor(panel, "Head").text)
        assert.equal(35, cardsUnder(panel, "Head"))
        -- Bound again, as the scroll box would, and shut.
        Panel.InitElement(panel, element, foldFor(panel, "Head"))
        element.foldButton:Click()
        assert.is_nil(ns.db.char.upgradeMap.foldOpen.Head)
        assert.equal(5, cardsUnder(panel, "Head"))
        -- A fold with no hover leaves none behind on a pooled frame.
        Panel.InitElement(panel, element, { kind = Panel.ELEMENT_FOLD, slot = "Head", text = "+ 0 more drops" })
        assert.is_nil(element.foldButton:GetScript("OnEnter"))
        -- A frame pooled into another kind hides the fold.
        Panel.InitElement(panel, element, { kind = Panel.ELEMENT_GROUP, text = "In your best set" })
        assert.is_false(element.foldButton:IsShown())
    end)

    it("takes a drop off the list when the client's own spec list leaves this spec out (UX-6b)", function()
        local Panel = ns.UpgradeMapPanel
        local panel = frame.upgradeMapPanel
        local head
        for _, entry in ipairs(panel.model.slots) do
            if entry.slot == "Head" then
                head = entry
            end
        end
        local unknown = head.noRating.unknown
        local other, fits, silent = unknown[1], unknown[2], unknown[3]
        -- Each is asked by the link the walk kept, once its data has arrived.
        for _, row in ipairs({ other, fits, silent }) do
            assert.is_string(row.link)
            world.items[row.link] = world.items[row.link] or {}
            world.items[row.link].info = { row.name, row.link, 4, n = 3 }
        end
        -- Spec IDs in the stub's own terms: 105 is the stub's player
        -- (spec/stubs/wow.lua), 999 is any spec that is not.
        world.itemSpecs[other.link] = { 999 }
        world.itemSpecs[fits.link] = { 999, 105 }
        world.itemSpecs[silent.link] = {}
        Panel.Refresh(panel)
        for _, entry in ipairs(panel.model.slots) do
            if entry.slot == "Head" then
                head = entry
            end
        end
        assert.equal(1, #head.noRating.offspec)
        assert.equal(other.itemID, head.noRating.offspec[1].itemID)
        assert.equal(15, #head.noRating.unknown)
        assert.equal("+ 29 more items", foldFor(panel, "Head").text)
        assert.equal(15, foldFor(panel, "Head").unrated)
        -- Printed still, with its phrase (`/lootpath status` reads these lines).
        local printed = table.concat(panel.lines, "\n")
        assert.is_not_nil(printed:find(other.name .. " (" .. tostring(other.itemLevel) .. ")", 1, true))
    end)
end)
