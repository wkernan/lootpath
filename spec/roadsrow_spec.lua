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

    local function shutAllBut(m, slot)
        local shut = {}
        for _, entry in ipairs(m.slots) do
            if entry.slot ~= slot then
                shut[entry.slot] = true
            end
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
            "Your best set · this week's plan · the pick first, then the rated alternatives",
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
        -- ...and the note is drawn under the open section, where it always was.
        local state = shutAllBut(m, "Head")
        local said = false
        for _, element in ipairs(ns.UpgradeMapPanel.Elements(m, state)) do
            said = said or element.text == head.hiddenNote
        end
        assert.is_true(said)
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
            "Upgrade · Seedpods of the Luminous Bloom (289) · no rating · crest type and cost not read"
                .. " · you hold 356 Adventurer Mistcrest, 2 Champion Mistcrest,"
                .. " 21 Hero Mistcrest, 20 Myth Mistcrest",
            lineOf(groups[3], 1)
        )
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

    it("draws a group header and a row per road, in the model's own order", function()
        local m = model()
        local state = shutAllBut(m, "Shoulder")
        local drawn = {}
        for _, element in ipairs(elements(m, state)) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_GROUP then
                drawn[#drawn + 1] = "group:" .. element.group
            elseif element.kind == ns.UpgradeMapPanel.ELEMENT_ROAD then
                drawn[#drawn + 1] = "road:" .. element.row.kind
            end
        end
        assert.same({
            "group:set",
            "road:catalyst",
            "road:vault",
            "group:item",
            "road:craft",
            "road:delve",
            "road:drop",
            "road:drop",
            "road:drop",
            "road:drop",
        }, { unpack(drawn, 1, 10) })
        -- The section element carries the slot's sentence, and only while open.
        local header
        for _, element in ipairs(elements(m, state)) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_SECTION and element.slot == "Shoulder" then
                header = element
            end
        end
        assert.equal("Catalyst your Lynx shoulders, skip the vault ones, no crests here.", header.plan)
        assert.is_true(header.height > ns.UpgradeMapPanel.SECTION_HEIGHT)
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

        local panel = ns.UpgradeMapPanel.Create()
        local element = CreateFrame("Frame", nil, panel)
        ns.UpgradeMapPanel.InitElement(panel, element, {
            kind = ns.UpgradeMapPanel.ELEMENT_ROAD,
            height = ns.UpgradeMapPanel.RoadHeight(craft),
            row = craft,
        })
        assert.equal(RETRIEVING_ITEM_INFO, element.roadLine.name:GetText())
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
        assert.is_truthy(element.roadLine.name:GetText():find("Placeholder Valediction", 1, true))
    end)

    it("says nothing under a shut section", function()
        local m = model()
        local state = { slots = {} }
        for _, entry in ipairs(m.slots) do
            state.slots[entry.slot] = true
        end
        for _, element in ipairs(elements(m, state)) do
            assert.is_nil(element.plan)
            assert.is_true(element.kind ~= ns.UpgradeMapPanel.ELEMENT_ROAD)
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
        -- The FIRST VISIBLE use decides, and on this slot that is the sentence
        -- in the section header: "Catalyst your Lynx shoulders" uses the word
        -- before any group header or row does. "plan" is first used by the set
        -- group's header, and "crest" by the vault road's facts under it.
        assert.is_true(at.Catalyst < at.plan)
        assert.is_true(at.plan < at.crest)
        assert.equal(ns.UpgradeMapPanel.ELEMENT_SECTION, list[at.Catalyst - 1].kind)
        assert.equal(ns.UpgradeMapPanel.ELEMENT_GROUP, list[at.plan - 1].kind)
        assert.equal(ns.UpgradeMapPanel.ELEMENT_ROAD, list[at.crest - 1].kind)
        -- "no crests here" is not a use of "crest": the sentence in the header
        -- did not earn the crest line, the row that says what is not readable
        -- did.
        assert.is_true(at.crest > at.Catalyst + 1)
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
    -- The printed text is the same rows.

    it("prints the same sentence, headers and rows the list draws", function()
        local m = model()
        local lines = ns.UpgradeMapPanel.Lines(m)
        local shoulder = section(m, "Shoulder")
        local at
        for index, line in ipairs(lines) do
            if line == "Shoulder" then
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
        assert.is_nil(usesForbidden("this week's plan"))
        assert.is_nil(usesForbidden("the Hoardmonger"))
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

    -- The only two slots whose sections are open by default are every slot, so
    -- the row is found by walking the model rather than by scrolling.
    local function rowWith(verb)
        for _, element in ipairs(frame.upgradeMapPanel.elements) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_ROAD and element.row.verb == verb then
                return element.row
            end
        end
        return nil
    end

    it("puts roads on the tab the window opens", function()
        local panel = frame.upgradeMapPanel
        assert.is_true(panel.model.hasRoads)
        local groups, roads = 0, 0
        for _, element in ipairs(panel.elements) do
            if element.kind == ns.UpgradeMapPanel.ELEMENT_GROUP then
                groups = groups + 1
            elseif element.kind == ns.UpgradeMapPanel.ELEMENT_ROAD then
                roads = roads + 1
            end
        end
        assert.is_true(groups > 3)
        assert.is_true(roads > 100)
    end)

    it("draws a road row with its tag, its item, its facts, its step and its button", function()
        local panel = frame.upgradeMapPanel
        local element
        for _, candidate in ipairs(panel.scrollBox:GetFrames()) do
            local data = candidate:GetElementData()
            if data.kind == ns.UpgradeMapPanel.ELEMENT_ROAD and element == nil then
                element = candidate
            end
        end
        assert.is_not_nil(element)
        local row = element:GetElementData().row
        assert.equal(row.tag, element.roadTag:GetText())
        assert.equal(row.name, element.roadLine.resolved.name)
        assert.equal(row.second or "", element.roadLine.second:GetText())
        assert.equal(row.factsText or "", element.roadFacts:GetText())
        assert.equal(row.todo or "", element.roadTodo:GetText())
        assert.equal(row.verb ~= nil, element.roadVerb:IsShown())
    end)

    -- The gold edge is the plan's own pick and nothing else, which needs a row
    -- of each to say: the first slot section holds a pick and the rows under it
    -- are not one, and a pooled frame that drew a pick must lose the edge when
    -- it comes back as something else.
    it("puts the gold edge on the pick and takes it off everything else", function()
        local panel = frame.upgradeMapPanel
        local picks, others = 0, 0
        for _, element in ipairs(panel.scrollBox:GetFrames()) do
            local data = element:GetElementData()
            if data.kind == ns.UpgradeMapPanel.ELEMENT_ROAD then
                if data.row.planPick then
                    picks = picks + 1
                    assert.is_true(element.roadEdge:IsShown())
                else
                    others = others + 1
                    assert.is_false(element.roadEdge:IsShown())
                end
            end
        end
        assert.is_true(picks > 0)
        assert.is_true(others > 0)
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
        assert.equal(ns.UpgradeMapPanel.ELEMENT_RUN, scrolled.kind)
        assert.equal(row.runKey, scrolled.run.key)
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
        assert.equal("The plan would catalyst the Hide chest too, but you've only got one charge.", plan.footnote)
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
end)
