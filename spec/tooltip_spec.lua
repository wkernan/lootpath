-- spec/tooltip_spec.lua (R-2, WKE-563)
-- Surface 1: the item's part of the plan on Blizzard's own tooltip, the cache
-- that makes a hover a lookup, and the bag glow - over the owner's own week.
--
-- The inputs are the week R-1 built the model on and R-3 drew the slot's row
-- over, so every figure asserted here is already asserted line for line in
-- `spec/roads_spec.lua` and `spec/roadsrow_spec.lua`:
--
--   * `spec/fixtures/captures/Lootpath-20260908-124527.lua` - inventory
--     snapshot 7 and vault snapshot 9.
--   * the FOUR Dungeon scenario documents of the 2026-09-09 19:22 run.
--   * the SIX Upgrade Finder documents of the 2026-09-08 22:47 run.
--   * the 2026-09-06 20:09 cold journal walk (478 drops, previewed at
--     keystone 10) and the 2026-09-08 23:04 currency transcript.
--
-- **One of the issue's own test expectations is refuted here and the truth is
-- asserted instead.** WKE-563 asks for "hovering the Hide of Pestilence yields
-- no glow". On the committed documents the Hide of Pestilence is the tier chest
-- in every set of this week (ARCHITECTURE.md §9, the M3-15 correction of
-- 2026-09-09), so its Catalyst road reads "in your best set" and principle 12
-- says that is exactly what glows. The item the issue wanted - a piece in the
-- bags that the rating leaves behind - is the Miststalker's Spaulders, and that
-- is the one asserted dark.
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

-- The owner's own items, by the key the inventory snapshot carries.
local LYNX = "277782:6652:12830:13662"
local HIDE = "251226:6652:12699:12836:13440:13662"
local MISTSTALKER = "272244:6652:12822:13663"
local SEEDPODS = "250022:3174:6652:12806:13340:13440:13574"
local VAULT_SPAULDERS = "251146:6652:12699:12842:13440:13662"
local VAULT_WORLDROOT = "251935:6652:12841"
-- The other weapon in his bags this week: a 259 the rating never saw.
local DECAPITATOR = "275222:6652:12793:13334"

-- A link the plan will never point at, taken out of R-2a's own `glow` capture
-- rather than written here: bag 0 slot 1 of the owner's 2026-09-14 bags, which
-- that transcript records as `inMap = false`, `glow = false`. R-2b's guard that
-- the widget answers exactly `false` needs a real negative, and this is his.
local GLOW_CAPTURE = "spec/fixtures/captures/Lootpath-20260914-171359.lua"
local HEARTHSTONE_LINK = (function()
    local slots = R.snapshot("glow", 1, GLOW_CAPTURE).data.slots
    for _, slot in ipairs(slots) do
        if slot.key == "6948" then
            return slot.link
        end
    end
    error("the glow capture no longer carries the Hearthstone slot")
end)()

-- The verdict's own time, and a moment five hours after it, so the header's age
-- is a figure of the fixture rather than of the clock the tests run on.
local EXPORTED_AT = "2026-09-09T19:22:44.178Z"
local FIVE_HOURS_LATER = 1789000000

-- No player-facing string on this surface may name a source (owner's decision,
-- 2026-09-11), and none of them may use a phrasing the brief struck.
local FORBIDDEN =
    { "QE Live", "his", "verdict", "should", "before reset", "last day", "the plan", "your plan", "this plan" }

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function usesForbidden(text)
    if type(text) ~= "string" then
        return nil
    end
    for _, word in ipairs(FORBIDDEN) do
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

describe("In place: the tooltip block, the cache and the bag glow", function()
    local ns, world, gathered, model

    local function exports()
        local list = {}
        for _, name in ipairs(SCENARIO_ORDER) do
            list[#list + 1] = {
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
            list[#list + 1] = {
                schema = "qe-live-upgradefinder",
                contentType = entry.contentType,
                keyLevel = entry.keyLevel,
                json = readFile(entry.file),
            }
        end
        return list
    end

    before_each(function()
        ns, world = H.load()
        ns.UI.Options.Set("Dungeon")
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
        R.vault(world, R.snapshot("vault", VAULT_SNAPSHOT, CAPTURE))
        world.currencyByID = { [3465] = CATALYST }
        ns.db.global.captures.journal = { R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ) }

        local imported = ns.Companion.ImportAll({ writtenAt = EXPORTED_AT, exports = exports() })
        assert.is_true(imported.ok, imported.reason)

        gathered = ns.UpgradeMapPanel.Gather({ db = ns.db })
        local currencies = ns.Currencies.Read({ snapshot = R.snapshot("currencies", CURRENCY_SNAPSHOT, CURRENCIES) })
        currencies.catalyst = CATALYST
        currencies.catalystCharges = CATALYST.quantity
        currencies.catalystMax = CATALYST.maxQuantity
        gathered.currencies = currencies
        model = ns.UpgradeMapPanel.Model(gathered)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
    end)

    after_each(function()
        ns.RoadsCache.Reset()
        ns.UI.Bags.Reset()
        H.unload()
    end)

    local function lines(key)
        local answer = ns.RoadsCache.Lookup(key)
        assert.is_table(answer, "no cache entry for " .. tostring(key))
        local map = ns.RoadsCache.Map()
        local out = {}
        for index, line in
            ipairs(ns.UI.Tooltip.Lines(answer, {
                now = FIVE_HOURS_LATER,
                previewMythicPlusLevel = map.previewMythicPlusLevel,
            }))
        do
            out[index] = line.text
        end
        return out
    end

    -- -----------------------------------------------------------------------
    -- The map itself.

    it("builds one map over the owner's week, off the same model the tab draws", function()
        local map = ns.RoadsCache.Map()
        assert.is_nil(map.reason)
        assert.equal("thisWeek", map.scenario)
        assert.equal("this week's picks", map.planName)
        assert.equal(EXPORTED_AT, map.exportedAt)
        assert.equal(10, map.previewMythicPlusLevel)
        -- Every slot the tab shows, and the slots it does not reach.
        assert.equal(16, map.counts.slots)
        assert.is_true(map.counts.keys > 400)
    end)

    it("hands a slot the tab's own roads rather than building them a second time", function()
        local map = ns.RoadsCache.Map()
        local section
        for _, entry in ipairs(model.slots) do
            section = section or (entry.slot == "Shoulder" and entry or nil)
        end
        assert.is_table(section)
        assert.equal(section.roads, map.bySlot.Shoulder)
    end)

    -- -----------------------------------------------------------------------
    -- The block, line for line, on the canvas's own item.

    it("draws the Lynx Spaulders exactly as surface 1 describes it", function()
        -- R-2a (WKE-571) took three things off this block, each named on the
        -- owner's screen of 2026-09-14 and each for the same reason: the
        -- tooltip is the surface with the least room and it may not carry a
        -- clause whose referent is on another screen.
        --
        --   * the rival clause on the Catalyst road ("the same charge as the
        --     vault Spaulders road") points at a row this reader cannot see -
        --     principle 6's own rule. The panel keeps it.
        --   * the Crafted road's name had not arrived, and "item 244572" is an
        --     ID rather than a name. The cache now asks the client for it, and
        --     until it lands the tooltip says what kind of thing it is.
        --   * the Seedpods row is a NO RATING road, and it took a line under a
        --     best-set pick to say nothing. Rated roads only, here.
        -- R-3b (WKE-576) added a fourth clause, `/lootpath refresh` on the age
        -- line; R-2l (WKE-695) took the `Better:` line and the age line off
        -- the block on the owner's word of 2026-10-07. The Catalyst road is a
        -- set verdict, not a percent against what you wear, so there is no
        -- `Upgrade` line either.
        assert.same({
            "Lootpath · Shoulder",
            "Catalyst these - tier shoulders.",
        }, lines(LYNX))
    end)

    it("keeps every one of those clauses on the Upgrade Map row, where their referents are", function()
        -- The same road, through the row the panel draws: the tooltip drops
        -- them, the panel does not, and both read the SAME strings.
        local road
        for _, entry in ipairs(ns.RoadsCache.Map().bySlot.Shoulder.groups[ns.Roads.GROUP_SET] or {}) do
            road = road or (road == nil and entry.kind == ns.Roads.KIND_CATALYST and entry or nil)
        end
        assert.is_table(road)
        local row = ns.UpgradeMapPanel.RoadRow(road)
        assert.is_truthy(row.factsText:find("the same charge as the vault Spaulders road", 1, true))
        assert.is_nil(row.tooltipFactsText and row.tooltipFactsText:find("the same charge as", 1, true))
        -- And the no-rating road is still on the slot: it was dropped from the
        -- tooltip's three, not from the model.
        assert.is_true(#(ns.RoadsCache.Map().bySlot.Shoulder.groups[ns.Roads.GROUP_NONE] or {}) > 0)
    end)

    it("separates the cost clause the vendor window gates, and keeps it on the panel", function()
        local road
        for _, entry in ipairs(ns.RoadsCache.Map().bySlot.Shoulder.groups[ns.Roads.GROUP_SET] or {}) do
            road = road or (entry.kind == ns.Roads.KIND_VAULT and entry or nil)
        end
        assert.is_table(road)
        local row = ns.UpgradeMapPanel.RoadRow(road)
        assert.same({ ns.Roads.CREST_NOT_READABLE }, row.costFacts)
        assert.equal(ns.Roads.CREST_NOT_READABLE, row.costText)
        assert.is_truthy(row.factsText:find(ns.Roads.CREST_NOT_READABLE, 1, true))
        assert.is_nil(row.tooltipFactsText:find(ns.Roads.CREST_NOT_READABLE, 1, true))
    end)

    -- R-3c (WKE-580), defect 3: the crest counts are the vendor row's business.
    -- On the owner's block of 2026-09-14 they were the longest clause on the
    -- Upgrade line and answered a question nobody asked on a tooltip - the same
    -- rule R-2a applied to the cost clause, one clause later.
    it("keeps the crest counts off the Upgrade road's tooltip line and on its row", function()
        local HOLDING = "you hold 356 Adventurer Mistcrest, 2 Champion Mistcrest, 21 Hero Mistcrest, 20 Myth Mistcrest"
        assert.same({
            "Lootpath · Shoulder",
            "Swap these - Catalyst your Lynx shoulders.",
        }, lines(SEEDPODS))
        -- And the row the panel draws still says it, beside the crest counts
        -- the reader can see: dropped from the tooltip, not from the model.
        local road
        for _, entry in ipairs(ns.RoadsCache.Map().bySlot.Shoulder.groups[ns.Roads.GROUP_NONE] or {}) do
            road = road or (entry.kind == ns.Roads.KIND_CREST and entry or nil)
        end
        assert.is_table(road)
        local row = ns.UpgradeMapPanel.RoadRow(road)
        assert.is_truthy(row.costText:find(HOLDING, 1, true))
        assert.is_truthy(row.factsText:find(HOLDING, 1, true))
        assert.is_nil(row.tooltipFactsText:find(HOLDING, 1, true))
        assert.equal(ns.Roads.CREST_NOT_READ, row.tooltipFactsText)
    end)

    it("says the age in the shortest unit that says it, rounded down", function()
        -- Reading 7 of the approved copy set, over the owner's own figure: the
        -- block he read on 2026-09-16 said `rated 69 minutes ago` and the
        -- approved one says `1h`. Every other rung is here too, because the
        -- rule is the ladder and not the one number.
        local Tip = ns.UI.Tooltip
        assert.is_nil(Tip.ShortAge(0))
        assert.is_nil(Tip.ShortAge(59))
        assert.equal("1m", Tip.ShortAge(60))
        assert.equal("59m", Tip.ShortAge(3599))
        assert.equal("1h", Tip.ShortAge(60 * 69))
        assert.equal("1h", Tip.ShortAge(3600))
        assert.equal("23h", Tip.ShortAge(86399))
        assert.equal("2d", Tip.ShortAge(86400 * 2 + 3600 * 23))
        -- And the words the line is built from.
        assert.equal("Rated just now", Tip.AgeText(EXPORTED_AT, ns.EpochFromISO(EXPORTED_AT) + 3))
        assert.equal("Rated 1h ago", Tip.AgeText(EXPORTED_AT, ns.EpochFromISO(EXPORTED_AT) + 60 * 69))
        assert.is_nil(Tip.AgeText(nil))
        assert.equal("Rated: not known · /lootpath map", Tip.FooterText({}))
    end)

    it("writes no Better: line for a road that is rated BEHIND what you wear", function()
        -- Reading 2 of the approved copy set. "Better:" over a road that loses
        -- would be a lie, and a reader cannot act on a worse road, so the block
        -- is three lines instead. Handcrafted off the owner's own vault
        -- Spaulders row, which reads `1.73% behind` on his week.
        local function road(inTopSet)
            return {
                kind = ns.Roads.KIND_VAULT,
                group = ns.Roads.GROUP_SET,
                slot = "Shoulder",
                keys = {},
                item = { itemID = 1, name = "Scavenger's Spaulders" },
                arrivesAt = 308,
                rating = {
                    kind = ns.Roads.RATING_SET,
                    inTopSet = inTopSet,
                    scorePercent = inTopSet and nil or 1.729166724018797,
                    badge = inTopSet and "in your best set" or "1.73% behind",
                },
            }
        end
        local behind = road(false)
        assert.equal("1.73% behind", ns.Roads.SetBadge(behind.rating))
        assert.is_nil(ns.UI.Tooltip.BetterText(behind))
        assert.is_nil(ns.UI.Tooltip.BestOther({ others = { behind } }))
        -- The same road the other way round earns the line, so what is being
        -- asserted is the direction and not the road.
        assert.equal("Better: Scavenger's Spaulders (308), in your best set", ns.UI.Tooltip.BetterText(road(true)))
    end)

    it("puts the vendor's own quote on the Upgrade road's line, and no money", function()
        -- M3-17b (WKE-588) read the cost off the owner's `upgrade` capture of
        -- 2026-09-15 and R-2a kept it off the tooltip, because its referent was
        -- the vendor window. UX-3 (WKE-599), reading 5, reverses that for this
        -- one road: since the vendor has been visited it is the only thing on
        -- that road a reader can act on, and the item is the one under the
        -- cursor, so the line says what it costs rather than naming it back.
        --
        -- Handcrafted, because on the committed week the Upgrade road for a
        -- worn piece sits in the same group as that piece's own Keep road and
        -- so is never one of the slot's "other" roads. The figures are the
        -- owner's own transcript's, asserted against it in
        -- `spec/upgradecost_spec.lua`.
        local road = {
            kind = ns.Roads.KIND_CREST,
            group = ns.Roads.GROUP_SET,
            slot = "Chest",
            keys = {},
            item = { itemID = 1, name = "Lunar Raiment" },
            arrivesAt = 308,
            rating = { kind = ns.Roads.RATING_SET, inTopSet = true, badge = "in your best set" },
            steps = {
                {
                    text = "2 steps · 40 Champion Mistcrest · 60g",
                    fact = true,
                    cost = true,
                    quote = "2 steps, 40 Champion Mistcrest",
                },
            },
        }
        assert.equal("Better: crest it to 308 - 2 steps, 40 Champion Mistcrest", ns.UI.Tooltip.BetterText(road))
        -- The money is the row's, not the block's.
        assert.is_nil(ns.UI.Tooltip.BetterText(road):find("60g", 1, true))
        -- With no capture behind it the road quotes nothing and the line is the
        -- level alone.
        road.steps[1].quote = nil
        assert.equal("Better: crest it to 308", ns.UI.Tooltip.BetterText(road))
    end)

    -- R-2l (WKE-695): the owner, 2026-10-07 - "the user can go to ... Upgrade
    -- Map to find out". PROVEN RED: with `Lines` drawing `BetterText` again,
    -- `Better: second (300), +1.50%` comes back.
    it("draws no other road at all, however many the slot has", function()
        -- Handcrafted, because the model hands over at most two others on the
        -- owner's own week: the rule has to be asserted against an answer that
        -- tries to exceed it, or it is true by accident rather than by rule
        -- (UX-3, WKE-599; principle 10's three became one).
        local function road(name, pick)
            return {
                kind = ns.Roads.KIND_DROP,
                group = ns.Roads.GROUP_ITEM,
                slot = "Shoulder",
                keys = {},
                planPick = pick or nil,
                item = { itemID = 1, name = name },
                arrivesAt = 300,
                rating = { kind = ns.Roads.RATING_ITEM, percent = 1.5, badge = ns.Roads.ItemBadge(1.5) },
            }
        end
        local answer = {
            slot = "Shoulder",
            held = true,
            own = road("own"),
            -- The pick first, which is where a worn piece's own set group puts
            -- it, and which line 2 has already named.
            others = { road("the pick", true), road("second"), road("third"), road("fourth") },
        }
        local drawn, better = 0, nil
        for _, line in ipairs(ns.UI.Tooltip.Lines(answer)) do
            if line.text:find("(300)", 1, true) then
                drawn = drawn + 1
                better = line.text
            end
        end
        assert.equal(0, drawn)
        assert.is_nil(better)
    end)

    -- R-2l (WKE-695): the block is the header, the percent line when there is
    -- one, the sentence, and one of R-2c's other-level line or R-2d's finish
    -- line - never a `Better:` line, never an age, never a command. PROVEN
    -- RED: with `Lines` drawing `FooterText` again, every key ends on `Rated 5h
    -- ago · /lootpath ...`.
    it("never draws more than four lines, and none of them is an age, a command or another road", function()
        local map = ns.RoadsCache.Map()
        for key, answer in pairs(map.byKey) do
            local block = lines(key)
            assert.is_false(answer.otherLevel ~= nil and answer.finish ~= nil, key .. " carries both")
            assert.is_true(#block <= 4, key .. " draws " .. #block .. " lines")
            for _, text in ipairs(block) do
                assert.is_nil(text:find("/lootpath", 1, true), key .. ": " .. text)
                assert.is_nil(text:find("^Better: "), key .. ": " .. text)
                assert.is_nil(text:find("^Rated "), key .. ": " .. text)
            end
        end
    end)

    -- R-2l (WKE-695): with the age line gone, it is the header alone.
    it("is the header alone when there is no sentence and no figure", function()
        -- Built rather than found: the owner's week has no such slot, and the
        -- rule is the block's, not the week's. The honesty phrase that used to
        -- take line 2 is cut (UX-3, WKE-599, reading 3).
        local answer = { slot = "Shoulder", others = {}, phrase = ns.Roads.PHRASE_NO_RATING }
        assert.same(
            {
                "Lootpath · Shoulder",
            },
            (function()
                local out = {}
                for index, line in ipairs(ns.UI.Tooltip.Lines(answer)) do
                    out[index] = line.text
                end
                return out
            end)()
        )
    end)

    it("says the vault option's part of the plan, and names what the plan takes instead", function()
        local block = lines(VAULT_SPAULDERS)
        assert.equal("Pass - Catalyst your Lynx shoulders.", block[2])
        -- Reading 2 of the approved set: this reward is 1.73% BEHIND, so it is
        -- never the "Better:" line about itself, and neither is the Catalyst
        -- pick line 2 has already named. What is left is the one road on the
        -- slot that gains. What the Upgrade Map's row still says about the
        -- reward, word for word, is asserted in `spec/roadsrow_spec.lua`.
        -- R-2l (WKE-695): no `Better:` line and no age line any more, and no
        -- percent line - its rating is a set verdict.
        assert.equal(2, #block)
    end)

    it("says the pick's part of the plan on the vault weapon, crest clause and all", function()
        local block = lines(VAULT_WORLDROOT)
        assert.equal("Lootpath · 2H Weapon", block[1])
        assert.equal("Grab this - crest it after.", block[2])
        assert.equal(2, #block)
    end)

    it("takes a position on a bag piece the rating never saw, and keeps the phrase under it", function()
        -- R-2a (WKE-571). The owner hovered this helmet's Shoulder twin on
        -- 2026-09-14 and the block opened on "not rated" with no sentence at
        -- all, which is the one thing principle 16 forbids: the plan comes
        -- first. The plan DOES have a position on every piece you hold - use
        -- it, catalyst it, or skip it - and the sentence for exactly this case
        -- already existed. What it never had was a way in for an item no road
        -- carries.
        local block = lines(MISTSTALKER)
        assert.equal("Lootpath · Shoulder", block[1])
        assert.equal("Pass - Catalyst your Lynx shoulders.", block[2])
        -- UX-3 (WKE-599), reading 3: the honesty phrase no longer takes a line
        -- of its own. A reader cannot act on "not rated · new since the last
        -- refresh" from a tooltip, and the cure is on the last line instead.
        for _, text in ipairs(block) do
            assert.is_nil(text:find(ns.Roads.PHRASE_NOT_RATED_NEW, 1, true), text)
        end
        -- R-2l (WKE-695): the cure line went with the footer; the window's
        -- strip still says it.
        assert.equal(2, #block)
    end)

    it("takes a position on every piece in the bags, rated or not", function()
        -- The rule as a rule rather than as one item: nothing the player is
        -- carrying opens without a sentence.
        local map = ns.RoadsCache.Map()
        local read = 0
        for _, record in ipairs(gathered.inventory.records) do
            local answer = map.byKey[record.key]
            if answer then
                read = read + 1
                assert.is_string(answer.sentence, record.key .. " (" .. tostring(record.name) .. ") has no sentence")
            end
        end
        assert.is_true(read > 20, "read only " .. read .. " held pieces")
    end)

    it("gives a road to something you do not have a figure and never an imperative", function()
        -- A journal drop is in the `item` group and is not in the bags; an
        -- imperative there would read as "run the dungeon", which no document
        -- said. Reading 4 of the approved copy set: line 2 states the road's own
        -- percent against what you wear and decides nothing.
        local map = ns.RoadsCache.Map()
        local worth, silent = 0, 0
        for key, answer in pairs(map.byKey) do
            if answer.own and answer.own.group ~= ns.Roads.GROUP_SET and not answer.held then
                local sentence = answer.sentence
                if sentence == nil then
                    silent = silent + 1
                else
                    worth = worth + 1
                    assert.is_truthy(
                        sentence:match("^Worth %d+%.%d%d%% over your [%a ]+%.$"),
                        key .. " says " .. sentence
                    )
                    -- No verb, so nothing here sends a player anywhere.
                    assert.is_true(ns.Roads.IsForward(answer.own), key .. " is worth something it does not gain")
                end
            end
        end
        assert.is_true(worth > 10, "read only " .. worth .. " rated roads to things the player does not hold")
        assert.is_true(silent > 100, "read only " .. silent .. " unrated roads to things the player does not hold")
    end)

    it("names no source and uses no struck phrasing anywhere in the block", function()
        local map = ns.RoadsCache.Map()
        local read = 0
        for key in pairs(map.byKey) do
            for _, text in ipairs(lines(key)) do
                read = read + 1
                assert.is_nil(usesForbidden(text), key .. ": " .. text)
            end
        end
        -- R-2l (WKE-695) took two lines off most blocks; 885 on this week.
        assert.is_true(read > 800, "read only " .. read .. " lines")
    end)

    -- -----------------------------------------------------------------------
    -- The glow (principle 12).

    it("glows on the two bag pieces this week's plan takes, and on nothing else in the bags", function()
        -- The Hide of Pestilence is the tier chest in EVERY set of this week
        -- (ARCHITECTURE.md §9, 2026-09-09), so it glows: the issue's "no glow"
        -- expectation was written before that correction landed.
        assert.is_true(ns.Glow.Wants(LYNX))
        assert.is_true(ns.Glow.Wants(HIDE))
        -- Rated and left behind, and not rated at all: neither is a mark.
        assert.is_false(ns.Glow.Wants(MISTSTALKER))
        assert.is_false(ns.Glow.Wants(SEEDPODS))
        assert.is_false(ns.Glow.Wants(VAULT_SPAULDERS))
        -- The plan's own vault pick does.
        assert.is_true(ns.Glow.Wants(VAULT_WORLDROOT))
    end)

    it("refuses to glow for anything it was not asked about", function()
        assert.is_false(ns.Glow.Wants(nil))
        assert.is_false(ns.Glow.Wants(12345))
        assert.is_false(ns.Glow.Wants("no such key"))
    end)

    it("glows only for a set verdict in the top set or a positive percent", function()
        assert.is_true(ns.RoadsCache.RoadWantsGlow({
            rating = { kind = ns.Roads.RATING_SET, inTopSet = true },
        }))
        assert.is_false(ns.RoadsCache.RoadWantsGlow({
            rating = { kind = ns.Roads.RATING_SET, inTopSet = false },
        }))
        assert.is_true(ns.RoadsCache.RoadWantsGlow({
            rating = { kind = ns.Roads.RATING_ITEM, percent = 0.04 },
        }))
        -- Zero is not a direction (M3-3's rule, and principle 12's).
        assert.is_false(ns.RoadsCache.RoadWantsGlow({
            rating = { kind = ns.Roads.RATING_ITEM, percent = 0 },
        }))
        assert.is_false(ns.RoadsCache.RoadWantsGlow({
            rating = { kind = ns.Roads.RATING_ITEM, percent = -1.2 },
        }))
        assert.is_false(ns.RoadsCache.RoadWantsGlow({ phrase = ns.Roads.PHRASE_NO_RATING }))
        assert.is_false(ns.RoadsCache.RoadWantsGlow(nil))
    end)

    it("answers the glow from a link the way a bag adapter hands one over", function()
        local link = nil
        for _, record in ipairs(gathered.inventory.records) do
            link = link or (record.key == LYNX and record.link or nil)
        end
        assert.is_string(link)
        assert.is_true(ns.Glow.WantsLink(link))
        assert.is_false(ns.Glow.WantsLink("not a link"))
        assert.is_false(ns.Glow.WantsLink(nil))
    end)

    -- -----------------------------------------------------------------------
    -- The hook itself.

    local function linkFor(key)
        for _, record in ipairs(gathered.inventory.records) do
            if record.key == key then
                return record.link
            end
        end
        for _, option in ipairs(gathered.vault.options or {}) do
            for _, reward in ipairs(option.rewards or {}) do
                if reward.key == key then
                    return reward.link
                end
            end
        end
        return nil
    end

    local function hover(key, frame)
        local shown = world.showItemTooltip({ hyperlink = linkFor(key) }, frame)
        return shown.stub.Text()
    end

    it("installs exactly one item post-call, and only one", function()
        assert.is_true(ns.UI.Tooltip.Installed())
        assert.equal(1, #world.tooltipPostCalls[Enum.TooltipDataType.Item])
        -- Blizzard declares no remover, so a second install would draw the
        -- block twice for the rest of the session.
        assert.is_true(ns.UI.Tooltip.Install())
        assert.equal(1, #world.tooltipPostCalls[Enum.TooltipDataType.Item])
    end)

    it("appends the block to GameTooltip on a bag hover", function()
        local text = hover(LYNX)
        assert.is_truthy(text:find("Catalyst these - tier shoulders.", 1, true))
        -- R-2l (WKE-695): the block carries no command any more.
        assert.is_truthy(text:find("Lootpath · Shoulder", 1, true))
        assert.is_nil(text:find("/lootpath", 1, true))
    end)

    it("answers GameTooltip and nothing else, which is 90% of the calls R-0 counted", function()
        -- The owner's spike run of 2026-09-14: 1,490 ShoppingTooltip1, 706
        -- ShoppingTooltip2 and 120 PawnPrivateTooltip1 against 250 GameTooltip.
        for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "PawnPrivateTooltip1" }) do
            local other = world.newTooltip(name)
            local text = hover(LYNX, other)
            assert.is_nil(text:find("Lootpath", 1, true), name .. " got the block")
        end
    end)

    it("adds nothing at all in combat", function()
        world.inCombat = true
        local text = hover(LYNX)
        assert.is_nil(text:find("Lootpath", 1, true))
        world.inCombat = false
        assert.is_truthy(hover(LYNX):find("Lootpath", 1, true))
    end)

    it("adds nothing for a secret hyperlink, and never reads the value itself", function()
        local link = linkFor(LYNX)
        world.secrets[link] = "value"
        local text = hover(LYNX)
        assert.is_nil(text:find("Lootpath", 1, true))
        -- And the key is never made from the client's own value: what comes
        -- back is nil and the marker, never a parse of the secret.
        local key, secret = ns.UI.Tooltip.KeyFromLink(link)
        assert.is_nil(key)
        assert.is_nil(secret)
        -- The same link, no longer secret, is the one that answers.
        world.secrets[link] = nil
        assert.equal(LYNX, (ns.UI.Tooltip.KeyFromLink(link)))
    end)

    it("adds nothing for a chat link or a merchant item whose item ID the map has nothing for", function()
        local link = "|Hitem:99999::::::::80:105::::::|h[Nothing]|h"
        world.items[link] = { level = 308, info = { "Nothing", link, 4, n = 3 } }
        local shown = world.showItemTooltip({ hyperlink = link })
        assert.is_nil(shown.stub.Text():find("Lootpath", 1, true))
        shown = world.showItemTooltip({ hyperlink = link }, ItemRefTooltip)
        assert.is_nil(shown.stub.Text():find("Lootpath", 1, true))
        assert.is_nil(ns.UI.Tooltip.Answer(link))
    end)

    -- -----------------------------------------------------------------------
    -- R-2c (WKE-646): a copy the documents rate at another level. The owner,
    -- 2026-09-25: a party member's Band of the Amani Warlord clicked in chat
    -- drew Pawn's line and no Lootpath block, and a Sickening Signet at 311 in
    -- his bags was told to pass. The ring here is this week's Finger drop
    -- 252258, rated at 305 by the key documents at +1.833 (`spec/roads_spec.lua`
    -- asserts the row); 251148 is the Finger drop rated at 305 at exactly 0.

    -- A copy of a drop under bonus IDs no document carries, at `level`, as the
    -- client would name it.
    local function copyLink(itemID, level)
        local link = string.format("|cffa335ee|Hitem:%d::::::::90:105::35:2:6652:12798::::::|h[Ring]|h|r", itemID)
        world.items[link] = { level = level, info = { "Ring", link, 4, n = 3 } }
        return link
    end

    -- The same copy, in the bags, and the map rebuilt over it.
    local function holdCopy(itemID, level)
        local link = copyLink(itemID, level)
        local parsed = ns.ParseItemLink(link)
        table.insert(gathered.inventory.records, {
            key = parsed.key,
            itemID = itemID,
            link = link,
            name = "Ring",
            slot = "Finger",
            itemLevel = level,
            location = "bag",
        })
        model = ns.UpgradeMapPanel.Model(gathered)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
        return parsed.key, link
    end

    it("answers a chat link at a level no road arrives at, with the rated figure and the link's level", function()
        local link = copyLink(252258, 308)
        local answer, _, level = ns.UI.Tooltip.Answer(link)
        assert.is_table(answer)
        assert.equal(308, level)
        assert.equal(305, answer.otherLevel.ratedAt)
        local shown = world.showItemTooltip({ hyperlink = link }, ItemRefTooltip)
        local text = shown.stub.Text()
        assert.is_truthy(text:find("Lootpath · Finger", 1, true))
        assert.is_truthy(text:find("+1.83% rated at 305 · this one is 308", 1, true))
        -- Nobody holds it, so it takes no position.
        assert.is_nil(text:find("Pass", 1, true))
        assert.is_nil(text:find("Beats", 1, true))
    end)

    it("draws the block on ItemRefTooltip and GameTooltip, and on no other tooltip", function()
        local link = copyLink(252258, 308)
        assert.is_true(ns.UI.Tooltip.IsOurs(ItemRefTooltip))
        assert.is_true(ns.UI.Tooltip.IsOurs(GameTooltip))
        assert.is_truthy(world.showItemTooltip({ hyperlink = link }).stub.Text():find("Lootpath", 1, true))
        for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "PawnPrivateTooltip1" }) do
            local other = world.newTooltip(name)
            assert.is_false(ns.UI.Tooltip.IsOurs(other))
            local text = world.showItemTooltip({ hyperlink = link }, other).stub.Text()
            assert.is_nil(text:find("Lootpath", 1, true), name .. " got the block")
        end
    end)

    it("tells the owner's bag copy it beats what he wears, with both levels, and marks it", function()
        local key, link = holdCopy(252258, 311)
        local text = world.showItemTooltip({ hyperlink = link }).stub.Text()
        assert.is_truthy(text:find(ns.Roads.BEATS_WORN_SENTENCE, 1, true))
        assert.is_truthy(text:find("+1.83% rated at 305 · you hold it at 311 · Refresh rates this one", 1, true))
        -- R-2l (WKE-695): the `Better:` line is off the block, and the figure
        -- is a row at ANOTHER level than the copy's, so it is never the
        -- `Upgrade` line either (the other-level line carries it, both levels).
        assert.is_nil(text:find("Better: ", 1, true))
        assert.is_nil(text:find("Upgrade", 1, true))
        assert.is_nil(text:find("Pass", 1, true))
        assert.is_nil(text:find("not rated", 1, true))
        assert.is_true(ns.Glow.Wants(key))
    end)

    it("keeps the pass on a bag copy rated at or below what he wears, with the figure, and does not mark it", function()
        local key, link = holdCopy(251148, 311)
        local text = world.showItemTooltip({ hyperlink = link }).stub.Text()
        assert.is_truthy(text:find("Pass - ", 1, true))
        assert.is_truthy(text:find("rated at 305: not better · you hold it at 311", 1, true))
        assert.is_nil(text:find("not rated", 1, true))
        assert.is_false(ns.Glow.Wants(key))
        assert.is_false(ns.RoadsCache.RoadWantsGlow(nil, { upgrade = false }))
        assert.is_true(ns.RoadsCache.RoadWantsGlow(nil, { upgrade = true }))
    end)

    -- -----------------------------------------------------------------------
    -- R-2d (WKE-648): what the rating enchanted and gemmed a piece of the set
    -- with. The owner, 2026-09-25 night: "On hover of an item I'm wearing,
    -- Lootpath should also tell me what the best gem/enchant or whatever
    -- consumable I can purchase to use on it." On this week the set keeps his
    -- worn ring 251136, and the thisWeek document rates it with Zul'jin's
    -- Mastery and gem 240892. His worn link carries the gem and NO enchant (its
    -- enchant field is empty in the 2026-09-08 capture), so since R-2g
    -- (WKE-665) the rated enchant is marked missing: absence needs no join.
    -- The other worn ring, 259912, carries enchant 7968, and an enchant that is
    -- present is never compared (ARCHITECTURE.md §11). The worn neck 272228 is
    -- rated with gem 240983 and no enchant, and carries 240983.
    local RING = "251136:6652:12698:12822:13438:13668"
    local OTHER_RING = "259912:6652:12790:13668"
    local NECK = "272228:6652:12846:13668"

    local function ringPick()
        for _, road in ipairs(ns.RoadsCache.Map().bySlot.Finger.groups[ns.Roads.GROUP_SET]) do
            for _, key in ipairs(road.keys) do
                if key == RING then
                    return road
                end
            end
        end
        return nil
    end

    it(
        "says what the rating enchanted and gemmed a worn piece of the set with, and marks nothing that matches",
        function()
            world.items[240892] = { info = { "Stub Gem", "|Hitem:240892|h[Stub Gem]|h", 3, n = 3 } }
            -- Both worn rings (251136 and 259912) are rated with 240892.
            assert.equal(2, ns.RoadsCache.NameGems(ns.RoadsCache.Map()))
            local ring = lines(RING)
            assert.equal("Keep this on.", ring[2])
            assert.equal("rated with: Zul'jin's Mastery (missing) · Stub Gem", ring[3])
            assert.same({ { id = 240892, missing = false, name = "Stub Gem" } }, ns.RoadsCache.Lookup(RING).finish.gems)
            -- A gem the client has not named yet, and no enchant.
            assert.equal("rated with: a gem", lines(NECK)[3])
            assert.is_nil(hover(RING):find("Stub Gem (missing)", 1, true))
            -- A ring carrying an enchant ID is never marked, whichever it is.
            assert.is_nil(ns.RoadsCache.Lookup(OTHER_RING).finish.enchantMissing)
            assert.equal("rated with: Zul'jin's Mastery · Stub Gem", lines(OTHER_RING)[3])
        end
    )

    it("marks a gem the rating used that the worn copy does not carry, in the better tone and in a word", function()
        local pick = ringPick()
        assert.is_table(pick)
        pick.verdictItem.gems = { 240892, 240983 }
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
        local answer = ns.RoadsCache.Lookup(RING)
        assert.same({ { id = 240892, missing = false }, { id = 240983, missing = true } }, answer.finish.gems)
        assert.equal("rated with: Zul'jin's Mastery (missing) · a gem, a gem (missing)", lines(RING)[3])
        local better = ns.UI.ItemLine.TONE.better.hex
        assert.is_truthy(hover(RING):find("|cff" .. better .. "a gem (missing)|r", 1, true))
    end)

    -- R-2g (WKE-665). The owner, 2026-09-30: "any item I have on that is
    -- missing a gem or enchant, we are ensuring we state that to the player."
    -- His own worn ring is the case: rated with Zul'jin's Mastery, and its
    -- link carries no enchant at all. PROVEN RED: without the mark this line
    -- reads `rated with: Zul'jin's Mastery · Stub Gem`.
    it("marks the rated enchant on a worn copy that carries none, in the better tone and in a word", function()
        world.items[240892] = { info = { "Stub Gem", "|Hitem:240892|h[Stub Gem]|h", 3, n = 3 } }
        ns.RoadsCache.NameGems(ns.RoadsCache.Map())
        local answer = ns.RoadsCache.Lookup(RING)
        assert.equal("Zul'jin's Mastery", answer.finish.enchant)
        assert.is_true(answer.finish.enchantMissing)
        local text, parts = ns.UI.Tooltip.FinishText(answer)
        assert.equal("rated with: Zul'jin's Mastery (missing) · Stub Gem", text)
        local better = ns.UI.ItemLine.TONE.better.hex
        assert.same({ text = "Zul'jin's Mastery (missing)", hex = better }, parts[2])
        assert.equal(ns.UI.Tooltip.NOTE_HEX, parts[4].hex)
        assert.is_truthy(hover(RING):find("|cff" .. better .. "Zul'jin's Mastery (missing)|r", 1, true))
        -- One shape for a gem and an enchant alike.
        assert.equal(ns.UI.Tooltip.FINISH_MISSING, "%s (missing)")
        assert.is_nil(ns.UI.Tooltip.GEM_MISSING)
    end)

    it("says nothing about the finish of a piece outside the set, or of one the set converts", function()
        assert.is_nil(ns.RoadsCache.Lookup(MISTSTALKER).finish)
        for _, text in ipairs(lines(MISTSTALKER)) do
            assert.is_nil(text:find("rated with", 1, true))
        end
        assert.is_nil(hover(MISTSTALKER):find("rated with", 1, true))
        -- Nor on a piece the set CONVERTS: the Lynx Spaulders are the Catalyst
        -- pick, and the set's item is the tier clone that comes out, whose
        -- enchant the document names - not the piece under the cursor.
        local lynx = ns.RoadsCache.Lookup(LYNX)
        assert.equal(ns.Roads.KIND_CATALYST, lynx.own.kind)
        assert.is_true(lynx.own.planPick)
        assert.is_string(lynx.own.verdictItem.enchant)
        assert.is_nil(lynx.finish)
        assert.is_nil(hover(LYNX):find("rated with", 1, true))
    end)

    it("reads a link's own enchant and gems, and never a secret", function()
        local link = "|cffa335ee|Hitem:251136:7968:240892:240983::::::90:105::35:2:6652:12798::::::|h[Ring]|h|r"
        assert.same({ enchantID = 7968, gems = { 240892, 240983 } }, ns.ItemData.LinkFinish(link))
        local bare = "|cffa335ee|Hitem:251136::::::::90:105::35:2:6652:12798::::::|h[Ring]|h|r"
        assert.same({ gems = {} }, ns.ItemData.LinkFinish(bare))
        world.secrets[link] = "value"
        assert.is_nil(ns.ItemData.LinkFinish(link))
        assert.is_nil(ns.ItemData.LinkFinish(nil))
        assert.is_nil(ns.ItemData.LinkFinish("not a link"))
    end)

    it("walks nothing on the hover path", function()
        -- "O(1) on the hover path" as a guard rather than a claim: once the map
        -- is built, a hover may not reach the model, the journal walk or a bag
        -- scan. This is what "no table allocation beyond the lines" can be
        -- proven to mean in a language whose allocator a test cannot ask.
        -- R-2c's chat link is hovered too, and its other-level lookup is one
        -- of the things counted: it is answered off the map, never walked.
        local chat = copyLink(252258, 308)
        local calls = 0
        local function count(holder, name)
            local original = holder[name]
            holder[name] = function(...)
                calls = calls + 1
                return original(...)
            end
        end
        count(ns.Roads, "ForSlot")
        count(ns.Roads, "ForItem")
        count(ns.Roads, "ForItemIn")
        count(ns.Roads, "ForItemIDIn")
        count(ns.Roads, "OtherLevelRoad")
        count(ns.Roads, "OtherLevelRating")
        count(ns.Roads, "RatedFinish")
        count(ns.Roads, "CompareFinish")
        count(ns.ItemData, "LinkFinish")
        count(ns.Roads, "PlanSentence")
        count(ns.Inventory, "Scan")
        count(ns.UpgradeMapPanel, "Model")
        count(ns.UpgradeMapPanel, "Gather")
        for _ = 1, 50 do
            hover(LYNX)
            hover(MISTSTALKER)
            hover(VAULT_SPAULDERS)
            world.showItemTooltip({ hyperlink = chat }, ItemRefTooltip)
            hover(RING)
        end
        assert.equal(0, calls)
    end)

    -- -----------------------------------------------------------------------
    -- When the map is rebuilt.

    it("rebuilds, debounced, on each of the four events it names", function()
        world.runTimers(5) -- drain the build the login queued
        for _, event in ipairs(ns.RoadsCache.EVENTS) do
            ns.RoadsCache.Reset()
            world.fireEvent(event)
            assert.is_false(ns.RoadsCache.Ready(), event .. " built before the debounce ran")
            world.runTimers(5)
            assert.is_true(ns.RoadsCache.Ready(), event .. " did not rebuild")
        end
    end)

    it("answers a burst of them with one build", function()
        world.runTimers(5)
        ns.RoadsCache.Reset()
        local builds = 0
        local original = ns.RoadsCache.Rebuild
        ns.RoadsCache.Rebuild = function(...)
            builds = builds + 1
            return original(...)
        end
        world.fireEvent("BAG_UPDATE_DELAYED")
        world.fireEvent("BAG_UPDATE_DELAYED")
        world.fireEvent("PLAYER_EQUIPMENT_CHANGED")
        world.runTimers(5)
        assert.equal(1, builds)
        ns.RoadsCache.Rebuild = original
    end)

    it("does not rebuild on an event it never named", function()
        world.runTimers(5)
        ns.RoadsCache.Reset()
        for _, event in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_DISABLED", "BAG_UPDATE" }) do
            world.fireEvent(event)
        end
        world.runTimers(5)
        assert.is_false(ns.RoadsCache.Ready())
    end)

    it("refuses to rebuild in combat and picks it up again when combat ends", function()
        world.runTimers(5)
        ns.RoadsCache.Reset()
        world.inCombat = true
        local map, reason = ns.RoadsCache.Rebuild()
        assert.is_nil(map)
        assert.equal("combat", reason)
        assert.is_false(ns.RoadsCache.Ready())
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        world.runTimers(5)
        assert.is_true(ns.RoadsCache.Ready())
    end)

    it("keeps the mark it had while combat refuses a rebuild", function()
        world.inCombat = true
        ns.RoadsCache.Rebuild()
        assert.is_true(ns.Glow.Wants(LYNX))
        assert.is_false(ns.Glow.Wants(MISTSTALKER))
        world.inCombat = false
    end)

    it("says why it has nothing when no plan is stored", function()
        local map = ns.RoadsCache.SetMap(ns.RoadsCache.Build({}))
        assert.equal("no rating stored", map.reason)
        assert.same({}, map.byKey)
        assert.is_false(ns.Glow.Wants(LYNX))
    end)

    -- -----------------------------------------------------------------------
    -- The bag glow, one adapter per bag addon.

    it("picks Blizzard's own bag frames when no bag addon is loaded", function()
        ns.UI.Bags.Reset()
        assert.is_true((ns.UI.Bags.Install()))
        assert.equal("blizzard", ns.UI.Bags.Chosen().name)
        assert.equal("bag glow: drawn in the client's own bag frames", ns.UI.Bags.StatusText())
    end)

    it("marks only the wanted slots in a Blizzard bag frame, and marks nothing else", function()
        local frame = world.newContainerFrame(0, 3)
        local slots = { LYNX, MISTSTALKER, VAULT_SPAULDERS }
        world.bags[0] = { numSlots = 3, items = {} }
        for slot, key in ipairs(slots) do
            world.bags[0].items[slot] = { info = { hyperlink = linkFor(key) }, link = linkFor(key) }
        end
        assert.equal(1, ns.UI.Bags.Blizzard.UpdateFrame(frame))
        assert.is_true(frame.Items[1].LootpathGlow:IsShown())
        assert.is_false(frame.Items[2].LootpathGlow:IsShown())
        assert.is_false(frame.Items[3].LootpathGlow:IsShown())
    end)

    it("draws its own texture and never touches the one another addon owns", function()
        local frame = world.newContainerFrame(0, 1)
        world.bags[0] = { numSlots = 1, items = { [1] = { info = { hyperlink = linkFor(LYNX) } } } }
        local button = frame.Items[1]
        -- Pawn's, on a real container item button. Nothing here may write to it.
        button.UpgradeIcon = { touched = false }
        ns.UI.Bags.Blizzard.UpdateFrame(frame)
        assert.is_false(button.UpgradeIcon.touched)
        assert.is_table(button.LootpathGlow)
    end)

    it("leaves every mark exactly as it was while the client is in combat", function()
        local frame = world.newContainerFrame(0, 1)
        world.bags[0] = { numSlots = 1, items = { [1] = { info = { hyperlink = linkFor(LYNX) } } } }
        ns.UI.Bags.Blizzard.OnUpdateItems(frame)
        assert.is_true(frame.Items[1].LootpathGlow:IsShown())
        -- The item goes away and combat starts: the hook returns before it can
        -- read anything, so the mark keeps its last state.
        world.bags[0].items[1] = nil
        world.inCombat = true
        ns.UI.Bags.Blizzard.OnUpdateItems(frame)
        assert.is_true(frame.Items[1].LootpathGlow:IsShown())
        world.inCombat = false
        ns.UI.Bags.Blizzard.OnUpdateItems(frame)
        assert.is_false(frame.Items[1].LootpathGlow:IsShown())
    end)

    it("hooks UpdateItems rather than replacing it", function()
        local hooked
        for _, entry in ipairs(world.secureHooks) do
            if entry.name == "UpdateItems" then
                hooked = entry
            end
        end
        assert.is_table(hooked, "UpdateItems was never hooked")
        assert.equal(ns.UI.Bags.Blizzard.OnUpdateItems, hooked.hook)
        assert.equal(ContainerFrameMixin, hooked.holder)
    end)

    it("prefers Baganator when it is loaded, as a corner widget rather than an upgrade plugin", function()
        local registered, upgradePlugins = {}, 0
        _G.Baganator = {
            API = {
                RegisterCornerWidget = function(label, id, onUpdate, onInit, position, isFast)
                    registered = {
                        label = label,
                        id = id,
                        onUpdate = onUpdate,
                        onInit = onInit,
                        position = position,
                        isFast = isFast,
                    }
                end,
                RegisterUpgradePlugin = function()
                    upgradePlugins = upgradePlugins + 1
                end,
                RequestItemButtonsRefresh = function() end,
            },
        }
        ns.UI.Bags.Reset()
        assert.is_true((ns.UI.Bags.Install()))
        assert.equal("baganator", ns.UI.Bags.Chosen().name)
        assert.equal("lootpath_glow", registered.id)
        -- TOP RIGHT, not top left (R-2a, WKE-571). Baganator ships top-left as
        -- `{"junk", "item_level"}` (Core/Config.lua:46) and shows only the
        -- FIRST widget in a corner that answers true
        -- (ItemViewCommon/ItemButton.lua:174-177), so R-2's `priority = 1` in
        -- top-left would have hidden the item level on every slot the plan
        -- marks. Top right ships empty.
        assert.equal("top_right", registered.position.corner)
        assert.equal(1, registered.position.priority)
        assert.is_true(registered.isFast)
        -- Pawn's arrow keeps its slot: only one upgrade plugin is active at a
        -- time, and Lootpath never takes that one.
        assert.equal(0, upgradePlugins)
        _G.Baganator = nil
    end)

    it("shows Baganator's corner widget for a wanted slot and hides it otherwise", function()
        local button = world.newContainerFrame(0, 1).Items[1]
        local widget = ns.UI.Bags.Baganator.OnInit(button)
        assert.is_table(widget)
        assert.is_true(ns.UI.Bags.Baganator.OnUpdate(widget, { itemLink = linkFor(LYNX) }))
        assert.is_false(ns.UI.Bags.Baganator.OnUpdate(widget, { itemLink = linkFor(MISTSTALKER) }))
        assert.is_false(ns.UI.Bags.Baganator.OnUpdate(widget, {}))
    end)

    -- -----------------------------------------------------------------------
    -- The picture, and whether the widget is ever asked (R-2b, WKE-575).
    --
    -- The owner's second night: `/lootpath glow` said `adapter: baganator`,
    -- `Baganator draws the widget in its top right corner`, `glow yes` for the
    -- helmet - and the slot on screen had nothing in it. The answer path is
    -- right; what was drawn was `evergreen-weeklyrewards-reward-selected`,
    -- which he then measured with `C_Texture.GetAtlasInfo` at **214 x 121**,
    -- squeezed by `SetAllPoints` into a 15-point square. These are the guards
    -- on the two things that night could not settle from a screenshot.

    it("draws a mark it can draw itself, at the widget's own size, never a stretched atlas", function()
        local Adapter = ns.UI.Bags.Baganator
        local button = world.newContainerFrame(0, 1).Items[1]
        local widget = Adapter.OnInit(button)

        assert.equal(Adapter.SIZE, widget.width)
        assert.equal(Adapter.SIZE, widget.height)

        -- Both layers are a texture, and NEITHER is an atlas: the stub clears
        -- one when the other is set, so an atlas creeping back in fails here.
        assert.equal(Adapter.EDGE_TEXTURE, widget.edge:GetTexture())
        assert.equal(Adapter.FILL_TEXTURE, widget.fill:GetTexture())
        assert.is_nil(widget.edge:GetAtlas())
        assert.is_nil(widget.fill:GetAtlas())

        -- UX-4c: both layers fill the frame, at the same anchor, with NO offset
        -- between them. The keyline is dilated into the edge FILE, so the two
        -- have to be registered texel for texel; the inset the old mark used
        -- shrank the fill instead, and a shrunken fill is a shadow on one side.
        assert.same({ "ALL" }, widget.edge.points[1])
        assert.same({ "ALL" }, widget.fill.points[1])
        assert.is_nil(widget.fill.points[2])
        assert.is_nil(Adapter.EDGE_INSET)

        -- UX-4b: the accent is the BRAND, not QE Live's gold. The gold goes on
        -- meaning "better" in the numbers; this mark means "this is Lootpath",
        -- and a mark that shared the gold would be saying the other thing.
        assert.equal(ns.UI.BRAND_HEX, Adapter.FILL_HEX)
        assert.are_not.equal(ns.UI.ItemLine.TONE.better.hex, Adapter.FILL_HEX)
        local r, g, b = ns.UI.ItemLine.RGB(Adapter.FILL_HEX)
        assert.same({ r, g, b, nil }, widget.fill.vertexColor)
        assert.same(Adapter.EDGE_COLOR, widget.edge.vertexColor)
    end)

    it("draws the Waymark out of the addon's own file, at the size that file was drawn for", function()
        local Adapter = ns.UI.Bags.Baganator
        local button = world.newContainerFrame(0, 1).Items[1]
        local widget = Adapter.OnInit(button)

        -- The addon's own textures, named through the one MEDIA table, never a
        -- path spelled out here and never Blizzard's flat white square.
        assert.equal(ns.UI.MEDIA.MARK16_EDGE, Adapter.EDGE_TEXTURE)
        assert.equal(ns.UI.MEDIA.MARK16_FILL, Adapter.FILL_TEXTURE)
        assert.equal(ns.UI.MEDIA.MARK16_EDGE, widget.edge:GetTexture())
        assert.equal(ns.UI.MEDIA.MARK16_FILL, widget.fill:GetTexture())
        assert.are_not.equal([[Interface\Buttons\WHITE8X8]], Adapter.EDGE_TEXTURE)
        assert.are_not.equal([[Interface\Buttons\WHITE8X8]], Adapter.FILL_TEXTURE)

        -- UX-4c: two DIFFERENT files. One texture drawn twice is the old mark,
        -- and it cannot carry a keyline and a brand colour at once.
        assert.are_not.equal(Adapter.EDGE_TEXTURE, Adapter.FILL_TEXTURE)

        -- R-2b: a mark is drawn at the size it will be seen at. Both files are
        -- 16 texels square, so the frame is 16 points and nothing is resampled.
        assert.equal(16, Adapter.SIZE)
        assert.equal(Adapter.SIZE, widget.width)
    end)

    it("marks the client's own bags with the same mark, the same size, in the same corner", function()
        local Baganator = ns.UI.Bags.Baganator
        local Blizzard = ns.UI.Bags.Blizzard

        -- The two adapters never load without each other, and a mark that
        -- changed in one bag window and not the other is the fault this guards.
        assert.equal(Baganator.EDGE_TEXTURE, Blizzard.EDGE_TEXTURE)
        assert.equal(Baganator.FILL_TEXTURE, Blizzard.FILL_TEXTURE)
        assert.equal(Baganator.SIZE, Blizzard.SIZE)
        assert.equal(Baganator.FILL_HEX, Blizzard.FILL_HEX)
        assert.same(Baganator.EDGE_COLOR, Blizzard.EDGE_COLOR)

        -- UX-4c: the keyline colour is one value, in `ns.UI.MARK_EDGE_COLOR`,
        -- wherever a Waymark is tinted. Each adapter keeps its own copy for the
        -- reason its file gives; the copies are checked against the one.
        assert.same(ns.UI.MARK_EDGE_COLOR, Baganator.EDGE_COLOR)
        assert.same(ns.UI.MARK_EDGE_COLOR, Blizzard.EDGE_COLOR)

        -- And the inset is gone from both, together. Half a migration - one
        -- adapter still shrinking its fill - would draw two different marks.
        assert.is_nil(Baganator.EDGE_INSET)
        assert.is_nil(Blizzard.EDGE_INSET)

        local button = world.newContainerFrame(0, 1).Items[1]
        local fill = Blizzard.Texture(button)
        local edge = fill.edge

        -- The vault atlas R-2b took out of the Baganator corner is gone from
        -- here too: it was a 214 x 121 banner stretched over a square button.
        assert.equal(ns.UI.MEDIA.MARK16_FILL, fill:GetTexture())
        assert.equal(ns.UI.MEDIA.MARK16_EDGE, edge:GetTexture())
        assert.is_nil(fill:GetAtlas())
        assert.is_nil(edge:GetAtlas())
        assert.is_nil(Blizzard.ATLAS)

        -- A corner mark at its own size, not SetAllPoints over the whole slot.
        -- R-2b's anchor, untouched by UX-4c: top-right of the button, no offset.
        assert.equal(Blizzard.SIZE, edge.width)
        assert.equal(Blizzard.SIZE, edge.height)
        assert.same({ "TOPRIGHT", button, "TOPRIGHT", 0, 0 }, edge.points[1])

        -- UX-4c: the fill is pinned to the EDGE's own rectangle, so the keyline
        -- lands on the chevrons' edges and nowhere else. `SetAllPoints(edge)`,
        -- not a bare `SetAllPoints()` onto the whole item button - which is the
        -- 214x121 mistake in another costume, and the stub keeps the argument so
        -- the two can be told apart.
        assert.same({ "ALL", edge }, fill.points[1])
        assert.is_nil(fill.points[2])

        local r, g, b = ns.UI.ItemLine.RGB(ns.UI.BRAND_HEX)
        assert.same({ r, g, b, nil }, fill.vertexColor)
        assert.same(Blizzard.EDGE_COLOR, edge.vertexColor)
    end)

    it("shows and hides both layers of the client-bag mark together", function()
        local Blizzard = ns.UI.Bags.Blizzard
        local button = world.newContainerFrame(0, 1).Items[1]
        local fill = Blizzard.Texture(button)

        -- Both start hidden, so a slot the plan says nothing about carries
        -- nothing at all.
        assert.is_false(fill:IsShown())
        assert.is_false(fill.edge:IsShown())

        Blizzard.SetShown(fill, true)
        assert.is_true(fill:IsShown())
        assert.is_true(fill.edge:IsShown())

        -- Half a mark left on screen is the fault: a brand-coloured chevron with
        -- no keyline, or a near-black one with no colour.
        Blizzard.SetShown(fill, false)
        assert.is_false(fill:IsShown())
        assert.is_false(fill.edge:IsShown())
    end)

    it("answers Baganator with exactly true or exactly false, never a truthy value", function()
        local Adapter = ns.UI.Bags.Baganator
        local button = world.newContainerFrame(0, 1).Items[1]
        local widget = Adapter.OnInit(button)

        -- `ItemButton.lua:140` branches on `show == nil` to QUEUE the slot
        -- rather than hide it, so anything but the two booleans puts a slot in
        -- a queue it does not belong in.
        assert.equal(true, Adapter.OnUpdate(widget, { itemLink = linkFor(LYNX) }))
        assert.equal(false, Adapter.OnUpdate(widget, { itemLink = HEARTHSTONE_LINK }))
        assert.equal(false, Adapter.OnUpdate(widget, {}))
    end)

    it("counts what Baganator asked it, and says so when it was never asked", function()
        local Adapter = ns.UI.Bags.Baganator
        _G.Baganator = {
            API = {
                RegisterCornerWidget = function() end,
                RequestItemButtonsRefresh = function() end,
                GetCurrentCornerForWidget = function()
                    return "top_right"
                end,
            },
        }
        ns.UI.Bags.Reset()
        assert.is_true((ns.UI.Bags.Install()))

        Adapter.ResetCalls()
        local said = table.concat(Adapter.DiagnosisLines(), "\n")
        assert.is_truthy(said:find(Adapter.NEVER_ASKED, 1, true), said)

        local button = world.newContainerFrame(0, 1).Items[1]
        local widget = Adapter.OnInit(button)
        Adapter.OnUpdate(widget, { itemLink = HEARTHSTONE_LINK })
        Adapter.OnUpdate(widget, { itemLink = linkFor(LYNX) })

        assert.equal(2, Adapter.calls)
        assert.equal(true, Adapter.lastAnswer)
        said = table.concat(ns.UI.Bags.DiagnosisLines(linkFor(LYNX)), "\n")
        assert.is_truthy(
            said:find("Baganator asked the widget 2 times this session, last answer: yes for ", 1, true),
            said
        )
        assert.is_falsy(said:find(Adapter.NEVER_ASKED, 1, true), said)

        -- The name comes out of the link's own brackets, with no client read.
        assert.equal("Hearthstone", Adapter.LinkName(HEARTHSTONE_LINK))

        Adapter.ResetCalls()
        _G.Baganator = nil
        ns.UI.Bags.Reset()
    end)

    it("names the bag window the mark is in on the status strip's tooltip", function()
        ns.UI.Bags.Reset()
        ns.UI.Bags.Install()
        local found = false
        for _, line in ipairs(ns.UI.StatusStripModel().tooltip) do
            found = found or line == "bag glow: drawn in the client's own bag frames"
        end
        assert.is_true(found, "the strip does not say where the mark is drawn")
    end)

    -- -----------------------------------------------------------------------
    -- The diagnosis (R-2a, WKE-571).
    --
    -- The owner's first real screens showed no mark anywhere and nothing on
    -- them told the three causes apart. These are the guards on the command
    -- that says which, so the next diagnosis is one line rather than three
    -- photographs.

    it("asks the client for the name of a road whose item it has never seen", function()
        -- R-2a (WKE-571). "item 244572 (331)" reached the owner's tooltip
        -- because nothing had ever asked: a crafted row's item ID comes out of
        -- the export, never off a link the player has held, so the client's
        -- cache has no name for it. The build now asks, once per item ID, and
        -- rebuilds when the name lands.
        world.itemDataRequests = {}
        assert.is_true(ns.RoadsCache.RequestNames(ns.RoadsCache.Map()) > 0)
        local asked = {}
        for _, itemID in ipairs(world.itemDataRequests) do
            asked[itemID] = true
        end
        assert.is_true(asked[244572], "never asked the client to name the crafted item")
        -- Once per session, not once per rebuild: the map is rebuilt on four
        -- events and a bag sort fires one of them per bag.
        world.itemDataRequests = {}
        assert.equal(0, ns.RoadsCache.RequestNames(ns.RoadsCache.Map()))
        assert.equal(0, #world.itemDataRequests)
    end)

    it("says which adapter, what the bag addon does with it, and what the map holds", function()
        ns.UI.Bags.Reset()
        ns.UI.Bags.Install()
        local text = table.concat(ns.UI.Bags.DiagnosisLines(linkFor(LYNX)), "\n")
        assert.is_truthy(text:find("adapter: blizzard", 1, true), text)
        assert.is_truthy(text:find("map: ", 1, true), text)
        assert.is_truthy(text:find(LYNX, 1, true), text)
        assert.is_truthy(text:find("item: in the map", 1, true), text)
        assert.is_truthy(text:find("item: glow yes", 1, true), text)
        assert.is_truthy(text:find("the map points at it", 1, true), text)
    end)

    it("says glow no, and why, for a piece the plan leaves behind", function()
        ns.UI.Bags.Reset()
        ns.UI.Bags.Install()
        local text = table.concat(ns.UI.Bags.DiagnosisLines(linkFor(MISTSTALKER)), "\n")
        assert.is_truthy(text:find("item: glow no", 1, true), text)
        assert.is_truthy(text:find("item: in the map", 1, true), text)
        -- The Miststalker's has no road of its own, so the line says the phrase
        -- rather than a road that is not there.
        assert.is_truthy(text:find("item: no road of its own", 1, true), text)
    end)

    it("tells an empty map apart from an item the map does not carry", function()
        ns.UI.Bags.Reset()
        ns.UI.Bags.Install()
        local held = linkFor(LYNX)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build({}))
        assert.is_truthy(table.concat(ns.UI.Bags.DiagnosisLines(held), "\n"):find("no rating stored", 1, true))
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
        local text = table.concat(ns.UI.Bags.DiagnosisLines("|Hitem:99999::::::::80:105::::::|h[Nothing]|h"), "\n")
        assert.is_truthy(text:find("item: NOT in the map", 1, true), text)
        assert.is_truthy(text:find("map: ", 1, true), text)
    end)

    it("refuses to read a secret link, and says what it wants instead", function()
        local link = linkFor(LYNX)
        world.secrets[link] = "value"
        local text = table.concat(ns.UI.Bags.DiagnosisLines(link), "\n")
        assert.is_truthy(text:find(ns.UI.Bags.NO_LINK, 1, true), text)
        assert.is_nil(text:find("item: key", 1, true))
        world.secrets[link] = nil
    end)

    it("says what Baganator is doing with the widget, in Baganator's own answer", function()
        local corner = nil
        _G.Baganator = {
            API = {
                RegisterCornerWidget = function() end,
                RequestItemButtonsRefresh = function() end,
                GetCurrentCornerForWidget = function(id)
                    assert.equal("lootpath_glow", id)
                    return corner
                end,
            },
        }
        ns.UI.Bags.Reset()
        assert.is_true((ns.UI.Bags.Install()))
        -- Registered, and no corner array is drawing it: the one state R-2 had
        -- no way to see, and the one the owner's blank screen could have been.
        local text = table.concat(ns.UI.Bags.DiagnosisLines(nil), "\n")
        assert.is_truthy(text:find(ns.UI.Bags.Baganator.NOT_IN_A_CORNER, 1, true), text)
        -- And it is on the status strip too, where a reader hunting a missing
        -- mark looks first.
        assert.equal(ns.UI.Bags.Baganator.STATUS_NOTE, ns.UI.Bags.StatusText())
        -- Drawing it: the strip goes back to naming the window.
        corner = "top_right"
        assert.is_truthy(
            table
                .concat(ns.UI.Bags.DiagnosisLines(nil), "\n")
                :find("Baganator draws the widget in its top right", 1, true)
        )
        assert.equal(
            "bag glow: drawn in Baganator's bag window, beside whatever else marks a slot",
            ns.UI.Bags.StatusText()
        )
        _G.Baganator = nil
    end)

    it("records the same four facts for every bag slot as a capture", function()
        -- Over the owner's own bags as the capture of 2026-09-08 recorded
        -- them, replayed into the stub client: the capture walks what is
        -- actually there rather than a frame a test built for it.
        local result = ns.RunCapture("glow")
        assert.is_true(result.ok, result.reason)
        local data = result.snapshot.data
        assert.is_true(#data.slots > 50, "walked only " .. #data.slots .. " bag slots")
        local byKey = {}
        for _, slot in ipairs(data.slots) do
            byKey[slot.key] = slot
        end
        assert.is_true(byKey[LYNX].inMap)
        assert.is_true(byKey[LYNX].glow)
        assert.is_true(byKey[LYNX].isForward)
        assert.equal(ns.Roads.KIND_CATALYST, byKey[LYNX].ownKind)
        assert.is_true(byKey[MISTSTALKER].inMap)
        assert.is_false(byKey[MISTSTALKER].glow)
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, byKey[MISTSTALKER].phrase)
        assert.equal("Pass - Catalyst your Lynx shoulders.", byKey[MISTSTALKER].sentence)
        -- And what the map was built from, so a transcript can be diffed
        -- against the keys the bags made without asking the client twice.
        assert.equal(ns.RoadsCache.Map().counts.keys, data.mapKeys)
        assert.equal(data.mapKeys, #data.mapKeyList)
        assert.equal("blizzard", data.adapter)
    end)

    it("says so honestly when no adapter fits the bag window in use", function()
        ns.UI.Bags.Reset()
        local adapters = ns.UI.Bags.adapters
        ns.UI.Bags.adapters = {}
        local ok, note = ns.UI.Bags.Install()
        assert.is_false(ok)
        assert.equal("bag glow: this bag window is not one Lootpath can mark; the tooltip still works", note)
        -- The tooltip is bag-independent and is unaffected.
        assert.is_truthy(hover(LYNX):find("Catalyst these - tier shoulders.", 1, true))
        ns.UI.Bags.adapters = adapters
    end)

    -- -----------------------------------------------------------------------
    -- R-3b (WKE-576): the bag item that IS the plan's vault pick, and the names
    -- the documents never carried.

    -- The owner's screen of 2026-09-14 night, over this week's own files. The
    -- claimed copy is hand-built - no capture has one, because the claim
    -- happens between two refreshes - and everything about it except its bonus
    -- ID is this week's: item 251935, the 2H Weapon slot, the name the vault
    -- reward itself carries. The bonus ID has to be a third one (12841 is the
    -- vault's copy, 12838 the 308 still on him), which is the whole point: the
    -- key is new and the item ID is not.
    local CLAIMED_LINK_BONUS = "12844"

    local function claimWorldroot()
        local worn
        for _, record in ipairs(gathered.inventory.records) do
            if record.location == "equipped" and record.itemID == 251935 then
                worn = record
            end
        end
        assert.is_table(worn)
        local link = worn.link:gsub("12838", CLAIMED_LINK_BONUS)
        local parsed = ns.ParseItemLink(link)
        assert.is_table(parsed)
        local record = {
            key = parsed.key,
            itemID = parsed.itemID,
            link = link,
            name = "Lightgrasp Worldroot",
            slot = "2H Weapon",
            itemLevel = 315,
            location = "bag",
        }
        table.insert(gathered.inventory.records, record)
        model = ns.UpgradeMapPanel.Model(gathered)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
        return record
    end

    it("tells the player the vault weapon has arrived, not to skip it", function()
        -- Every line of the block the owner read was honest about the document
        -- and the sentence was wrong about the world: this item IS the vault
        -- weapon, claimed and crested since the rating was made. The sentence
        -- now says so, the honesty phrase under it still says the item is not
        -- rated, and the vault road above no longer offers a walk to the vault.
        local claimed = claimWorldroot()
        local block = lines(claimed.key)
        assert.equal("Lootpath · 2H Weapon", block[1])
        assert.equal("Put this on - then refresh.", block[2])
        -- R-2l (WKE-695): no age line; the refresh is in the sentence.
        for _, text in ipairs(block) do
            assert.is_nil(text:find("/lootpath", 1, true), text)
        end
        -- And the road the block no longer draws still says where the piece has
        -- got to, on the Upgrade Map's row: dropped from the tooltip, not from
        -- the model.
        local pick = ns.Roads.PlanPick(ns.RoadsCache.Map().bySlot["2H Weapon"])
        assert.equal(ns.Roads.ARRIVED_CLAIMED_CRESTED, pick.claimed)
    end)

    -- R-3c (WKE-580): the same pick one step further on. The owner crested the
    -- staff the plan picked and PUT IT ON, and the block he read opened on
    -- "Skip this one, the plan uses your Worldroot" - the plan telling him to
    -- skip the staff in favour of itself.
    --
    -- Reproduced on the cloak, for the reason spec/roads_spec.lua gives: his
    -- week has no bag pick, so the placement is hand-built off the capture's
    -- own record (275522 moved into the bags, a copy at 308 put on, its bonus
    -- ID 12835 changed to 12839 so the key is new and the item ID is not).
    local function wearCrestedCloak()
        local record
        for _, held in ipairs(gathered.inventory.records) do
            if held.location == "equipped" and held.itemID == 275522 then
                record = held
            end
        end
        assert.is_table(record)
        record.location = "bag"
        local link = record.link:gsub("12835", "12839")
        local parsed = ns.ParseItemLink(link)
        assert.is_table(parsed)
        local worn = {
            key = parsed.key,
            itemID = parsed.itemID,
            link = link,
            name = record.name,
            slot = "Back",
            itemLevel = 308,
            location = "equipped",
        }
        -- The crest replaced the rated key (R-2k, WKE-694): while the pick's
        -- own key is still held, no other copy is the pick.
        for index, held in ipairs(gathered.inventory.records) do
            if held == record then
                table.remove(gathered.inventory.records, index)
                break
            end
        end
        table.insert(gathered.inventory.records, worn)
        model = ns.UpgradeMapPanel.Model(gathered)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
        return worn
    end

    it("tells the player the pick is on the character, not to skip it", function()
        local worn = wearCrestedCloak()
        local block = lines(worn.key)
        assert.equal("Refresh - you're already wearing it.", block[2])
        -- R-2l (WKE-695): the slot's one road that gains (`Better: Silken
        -- Voodoo Drape (344), +1.24% · ...` before) and the age line are off
        -- the block; the Upgrade Map's slot still names it.
        assert.equal(2, #block)
        -- And the row the plan's pick is on says where the piece has got to.
        local pick = ns.Roads.PlanPick(ns.RoadsCache.Map().bySlot.Back)
        assert.equal(ns.Roads.ARRIVED_NOW_WORN, pick.claimed)
        assert.equal("do: refresh to rate it", pick.todo)
    end)

    it("takes no position on a claimed pick it has no rating for", function()
        -- Principle 12: the sentence is not a verdict and the item is not
        -- rated, so nothing about it glows.
        local claimed = claimWorldroot()
        assert.is_false(ns.Glow.Wants(claimed.key))
    end)

    -- R-2j (WKE-693): the block over the vault pick in the bags under the
    -- vault's OWN key, before a refresh. The owner's screen of 2026-10-06 read
    -- `Grab this from the vault.` over the helm he had just taken; the same
    -- state on this week's files is the Worldroot taken as offered (the vault
    -- reward's own record from snapshot 9, with only `location` added, because
    -- no capture holds a claim made between two refreshes) and the client's
    -- vault after a claim (no activity carries a reward, nothing waiting:
    -- V-3, R-2f). PROVEN RED: without the R-2j branch in `ItemSentence` the
    -- second line is `Grab this from the vault.`
    local function takeWorldrootAsOffered()
        local reward
        for _, option in ipairs(gathered.vault.options) do
            for _, held in ipairs(option.rewards or {}) do
                if tonumber(held.itemID) == 251935 then
                    reward = held
                end
            end
        end
        assert.is_table(reward)
        assert.equal(VAULT_WORLDROOT, reward.key)
        for _, option in ipairs(gathered.vault.options) do
            option.rewards = {}
        end
        gathered.vault.hasAvailableRewards = false
        local record = {
            key = reward.key,
            itemID = reward.itemID,
            bonusIDs = reward.bonusIDs,
            link = reward.link,
            name = reward.name,
            slot = "2H Weapon",
            itemLevel = reward.itemLevel,
            location = "bag",
        }
        table.insert(gathered.inventory.records, record)
        model = ns.UpgradeMapPanel.Model(gathered)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
        return record
    end

    it("never tells the player to grab from the vault the pick in his bags (R-2j)", function()
        local before = lines(VAULT_WORLDROOT)
        assert.equal("Grab this - crest it after.", before[2])
        local held = takeWorldrootAsOffered()
        local block = lines(held.key)
        assert.equal("Lootpath · 2H Weapon", block[1])
        assert.equal("Crest this to 321 - then refresh.", block[2])
        -- Everything under the sentence is the block it was (since R-2l,
        -- WKE-695, no `Better:` line and no age line on either).
        assert.equal(#before, #block)
        for index = 3, #block do
            assert.equal(before[index], block[index])
        end
        for _, text in ipairs(block) do
            assert.is_nil(text:find("Grab", 1, true), text)
            assert.is_nil(text:find("from the vault", 1, true), text)
            assert.is_nil(usesForbidden(text), text)
        end
        -- The row the block no longer sends him along says where the piece is.
        local pick = ns.Roads.PlanPick(ns.RoadsCache.Map().bySlot["2H Weapon"])
        assert.equal(ns.Roads.VAULT_CLAIMED, pick.claimed)
    end)

    -- -----------------------------------------------------------------------
    -- Defect 3: the names the request never delivered.

    -- The road's name comes off the SOURCE record, and a QE Live item entry has
    -- no name field at all - so a road built from a document is nameless until
    -- something names it. R-2a asked the client and rebuilt when the answer
    -- landed; the rebuild re-read the same nameless source, so the name reached
    -- the row and never the road. This is the look at what the client answered.
    local function namelessVault()
        for _, option in ipairs(gathered.vault.options) do
            for _, reward in ipairs(option.rewards or {}) do
                reward.name = nil
                reward.link = nil
            end
        end
        local m = ns.UpgradeMapPanel.Model(gathered)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(m))
        return m
    end

    -- The owner's own sentence, reproduced: `the plan uses the vault weapon` is
    -- what a nameless vault pick reads as, because `ns.Roads.ShortName` falls
    -- back to the slot's word when there is no name to shorten.
    it("carries a name the client answers into the sentence, not only the row", function()
        local wornLink
        for _, record in ipairs(gathered.inventory.records) do
            if record.location == "equipped" and record.itemID == 251935 then
                wornLink = record.link
            end
        end
        assert.is_string(wornLink)
        local m = namelessVault()
        assert.equal("Pass - take the vault weapon.", ns.RoadsCache.Lookup(DECAPITATOR).sentence)

        -- The client can name item 251935: the owner is wearing one. Asked by
        -- item ID, which is how `ns.ItemData` asks.
        world.items[251935] = world.items[wornLink]
        local map = ns.RoadsCache.Map()
        assert.is_true(ns.RoadsCache.FillNames(map) > 0)
        assert.equal("Lightgrasp Worldroot", map.bySlot["2H Weapon"].groups[ns.Roads.GROUP_SET][1].item.name)
        -- A sentence is written inside the build, so the map is built once more
        -- over the roads the fill has named - which is what `Cache.Rebuild`
        -- does with the count this returns.
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(m))
        assert.equal("Pass - take the vault Worldroot.", ns.RoadsCache.Lookup(DECAPITATOR).sentence)
    end)

    it("asks the client only for what no link and no record named", function()
        local m = namelessVault()
        local map = ns.RoadsCache.Map()
        -- Nothing in this world answers GetItemInfo for a bare item ID, so the
        -- fill finds nothing and every nameless road is asked about instead.
        assert.equal(0, ns.RoadsCache.FillNames(map))
        assert.is_true(ns.RoadsCache.RequestNames(map) > 0)
        -- And a second pass asks for nothing: one request per item ID for the
        -- session, which is what R-2a made it.
        assert.equal(0, ns.RoadsCache.RequestNames(map))
        assert.is_table(m)
    end)

    -- -----------------------------------------------------------------------
    -- Lootpath's own vault cell, through the same function.

    it("puts the same block on the vault cell as on a bag hover", function()
        local cell = { data = { key = VAULT_WORLDROOT, name = "Lightgrasp Worldroot", tooltipLines = {} } }
        assert.is_true(ns.VaultPanel.ShowCellTooltip(cell))
        local text = GameTooltip.stub.Text()
        assert.is_truthy(text:find("Grab this - crest it after.", 1, true))
        assert.is_truthy(text:find("Lootpath · 2H Weapon", 1, true))
    end)

    it("puts nothing on the vault cell in combat", function()
        world.inCombat = true
        local cell = { data = { key = VAULT_WORLDROOT, name = "Lightgrasp Worldroot", tooltipLines = {} } }
        assert.is_true(ns.VaultPanel.ShowCellTooltip(cell))
        assert.is_nil(GameTooltip.stub.Text():find("Lootpath", 1, true))
        world.inCombat = false
    end)

    -- -----------------------------------------------------------------------
    -- H-1 (WKE-596): the healing gate, on the two in-place surfaces.
    --
    -- Every assertion here is over the SAME week as the ones above - the
    -- owner's own captures, his own exports, the map already built - so what is
    -- proven is the gate and nothing else: these keys glow and these blocks
    -- draw the moment the spec is a healing one again.

    local GUARDIAN = { index = 3, id = 104, name = "Guardian", icon = 132276, role = "TANK" }

    it("marks no bag slot at all in a non-healer spec", function()
        -- Proven red by taking the gate out of `ns.Glow.Wants`: the Guardian
        -- assertions answer true again, which is a mark on the owner's bags in
        -- a spec Lootpath rates nothing for.
        assert.is_true(ns.Glow.Wants(LYNX))
        world.spec = GUARDIAN
        assert.is_false(ns.Glow.Wants(LYNX))
        assert.is_false(ns.Glow.Wants(HIDE))
        assert.is_false(ns.Glow.Wants(VAULT_WORLDROOT))
        -- And the adapter's own way in, which is the one a bag addon calls.
        local link = nil
        for _, record in ipairs(gathered.inventory.records) do
            link = link or (record.key == LYNX and record.link or nil)
        end
        assert.is_string(link)
        assert.is_false(ns.Glow.WantsLink(link))
        -- Switching back needs nothing but the client answering again: the role
        -- is read live, never remembered.
        world.spec = { index = 4, id = 105, name = "Restoration", icon = 136041, role = "HEALER" }
        assert.is_true(ns.Glow.Wants(LYNX))
    end)

    it("answers no hover in a non-healer spec, and draws no block on the vault cell", function()
        local link = nil
        for _, record in ipairs(gathered.inventory.records) do
            link = link or (record.key == LYNX and record.link or nil)
        end
        assert.is_string(link)
        assert.is_table(ns.UI.Tooltip.Answer(link))
        world.spec = GUARDIAN
        -- No block, no header, no "Why this?" - there is no answer to draw one
        -- from. Proven red by taking the gate out of `Tooltip.Answer`.
        assert.is_nil(ns.UI.Tooltip.Answer(link))
        -- And the other way in: the Vault tab's cell looks its own key up and
        -- hands the answer straight to `Append`. Proven red by taking the gate
        -- out of `Tooltip.Append`, which puts the block back on the cell.
        assert.is_false(ns.VaultPanel.AppendRoads(GameTooltip, { key = VAULT_WORLDROOT }))
        assert.is_nil(GameTooltip.stub.Text():find("Why this?", 1, true))
    end)

    it("says nothing about a role the client does not name", function()
        -- The rule the whole gate turns on: at `ADDON_LOADED` and on a real
        -- logout the spec read is empty (R-7b), and an unknown role behaves
        -- exactly as it did before H-1.
        world.spec = nil
        assert.is_nil(ns.Companion.CurrentRole())
        assert.is_nil(ns.Companion.Gate())
        assert.is_true(ns.Glow.Wants(LYNX))
    end)
end)

-- ---------------------------------------------------------------------------
-- R-3d (WKE-584): the owner's reset-day hover, end to end.
--
-- The whole path, from the file the companion writes to the words on the
-- tooltip: `profileVaultCount = 0` in the verdict file (C-13) reaches the vault
-- road through `ns.Companion.ImportAll` and `ns.Roads.VaultConsidered`, and the
-- block over the vault's Enigmatic Dreamwatcher's Leggings stops telling the
-- reader to skip an item nothing ever rated.
--
-- The vault is snapshot 12 of the 2026-09-15 pull - his own 9 links, read with
-- the Great Vault window open (M3-16b, WKE-583) - and the documents are the
-- same committed 09-09 run every other block here is drawn over, which is a run
-- over a different week's profile and names none of those rewards.
describe("The tooltip over a vault the rating never imported (R-3d)", function()
    local ns, world
    local RESET_DAY = "spec/fixtures/captures/Lootpath-20260915-142722-vault.lua"
    local AFTER_THE_WINDOW = 12
    -- Read off that snapshot by `ns.Vault.Options()`, 2026-09-15.
    local LEGGINGS = "271527:6652:12844:13440:13693:13698"

    local function exports()
        local list = {}
        for _, name in ipairs(SCENARIO_ORDER) do
            list[#list + 1] = {
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
        return list
    end

    local function build(fileFields)
        local payload = { writtenAt = EXPORTED_AT, exports = exports() }
        for key, value in pairs(fileFields or {}) do
            payload[key] = value
        end
        local imported = ns.Companion.ImportAll(payload)
        assert.is_true(imported.ok, imported.reason)
        local gathered = ns.UpgradeMapPanel.Gather({ db = ns.db })
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(ns.UpgradeMapPanel.Model(gathered)))
    end

    local function lines(key)
        local answer = ns.RoadsCache.Lookup(key)
        assert.is_table(answer, "no cache entry for " .. tostring(key))
        local out = {}
        for index, line in ipairs(ns.UI.Tooltip.Lines(answer, { now = FIVE_HOURS_LATER })) do
            out[index] = line.text
        end
        return out
    end

    before_each(function()
        ns, world = H.load()
        ns.UI.Options.Set("Dungeon")
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
        R.vault(world, R.snapshot("vault", AFTER_THE_WINDOW, RESET_DAY))
    end)

    after_each(function()
        ns.RoadsCache.Reset()
        ns.UI.Bags.Reset()
        H.unload()
    end)

    -- PROVEN RED: this is the screen the owner read on 2026-09-15, and without
    -- the R-3d branch it comes back word for word.
    it("stops saying skip about a reward the run never imported", function()
        build({ profileVaultCount = 0 })
        local block = lines(LEGGINGS)
        assert.same({
            "Lootpath · Legs",
            "Not rated yet - refresh.",
        }, block)
        -- The two words that were the defect, gone from the whole block.
        for _, text in ipairs(block) do
            assert.is_nil(text:match("^Skip this one"), text)
            assert.is_nil(text:match("^Pass"), text)
            assert.is_nil(text:match("not in your best set"), text)
        end
        -- And the slot's real answer is where it belongs: on the road that has a
        -- rating, which the Upgrade Map's row still draws.
        local keep = ns.Roads.PlanPick(ns.RoadsCache.Map().bySlot.Legs)
        assert.equal(ns.Roads.KIND_KEEP, keep.kind)
        assert.equal("in your best set", keep.rating.badge)
    end)

    -- The same file without the count: nothing on record, so C-8's premise
    -- stands and the block is the one it has always been. The two runs
    -- differing by that one field is what proves the field is what decides.
    it("keeps the old block for a file that never said what its profile held", function()
        build({})
        local block = lines(LEGGINGS)
        assert.same({
            "Lootpath · Legs",
            "Pass - use your Dreamwatcher legs.",
        }, block)
    end)

    -- The glow follows, because it is principle 12's one test and not a second
    -- one: not knowing is not a verdict either way.
    it("does not glow on a reward nothing rated", function()
        build({ profileVaultCount = 0 })
        assert.is_false(ns.Glow.Wants(LEGGINGS))
    end)
end)

-- R-2e (WKE-663): the block over the vault reward the pick catalyzes, claimed
-- and in the bags. The owner's screen of 2026-09-29 read `Pass - take the vault
-- Dreamwatcher helm.` under the header. The document and the links are the ones
-- spec/roads_spec.lua's R-2e block reads (spec/fixtures/qe/README.md); the
-- block is asked of the answer the cache stores, built the way
-- `ns.RoadsCache.Build` builds it, and the line order is the one it always had.
describe("The tooltip over a claimed vault reward the pick catalyzes (R-2e)", function()
    local ns
    local THIS_WEEK_RAID = "spec/fixtures/qe/qe-droptimizer-Hotornot-mjiycadonbqq.json"
    local CATALYZED_DUNGEON = "spec/fixtures/qe/qe-droptimizer-Hotornot-esdfxjozstkc.json"
    local HOOD_LINK = "|cnIQ4:|Hitem:239033::::::::90:105::35:6:12844:13440:6652:13695:13662:12699::::::"
        .. "|h[Hood of the Slithering Loa]|h|r"
    -- Five minutes after the Raid document's own `exportedAt`
    -- (2026-09-30T00:17:03.103Z is 1790727423 by `date -u +%s`), and after the
    -- Dungeon one's (00:16:22.471Z, 1790727382).
    local FIVE_MINUTES_LATER = 1790727723

    local function block(path, scenario, settings)
        local parsed = ns.QEImport.Parse(readFile(path))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = scenario
        parsed.verdict.qeSettings = settings
        local link = ns.ParseItemLink(HOOD_LINK)
        local hood = {
            key = link.key,
            itemID = link.itemID,
            bonusIDs = link.bonusIDs,
            link = HOOD_LINK,
            name = "Hood of the Slithering Loa",
            slot = "Head",
            itemLevel = 315,
            location = "bag",
        }
        local inputs = {
            verdicts = { { verdict = parsed.verdict, scenario = scenario } },
            highlightedScenario = scenario,
            inventory = { records = { hood } },
            -- The client's vault after the claim: no gear.
            vault = { ok = true, options = { { rewards = {} } } },
        }
        local answer = ns.Roads.ForItemIn(ns.Roads.ForSlot("Head", inputs), hood.key, inputs)
        answer.sentence = ns.Roads.ItemSentence(answer)
        answer.exportedAt = parsed.verdict.exportedAt
        local out = {}
        for index, line in ipairs(ns.UI.Tooltip.Lines(answer, { now = FIVE_MINUTES_LATER })) do
            out[index] = line.text
        end
        return out
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- PROVEN RED: without the R-2e branch the second line is `Pass - take the
    -- vault helm.`
    it("answers the claimed Hood as the pick, crest after, and never as a pass", function()
        local lines = block(THIS_WEEK_RAID, "thisWeek", {
            autoUpgradeVault = true,
            autoUpgradeAll = false,
            autoCatalyze = true,
        })
        assert.same({
            "Lootpath · Head",
            "Catalyst this - tier helm, crest it after.",
        }, lines)
        for _, text in ipairs(lines) do
            assert.is_nil(text:find("Pass", 1, true), text)
            assert.is_nil(text:find("take the vault", 1, true), text)
            assert.is_nil(usesForbidden(text), text)
        end
    end)

    it("says the Catalyst alone when the rating kept the helm at the Hood's level", function()
        local lines = block(CATALYZED_DUNGEON, "catalyzed", {
            autoUpgradeVault = false,
            autoUpgradeAll = false,
            autoCatalyze = true,
        })
        assert.equal("Catalyst this - tier helm.", lines[2])
    end)
end)

-- R-2f (WKE-664): the block over the tier helm on the owner's head after the
-- claim, the Catalyst and one crest (318), the old 308 copy in his bags and
-- the vault empty. His screen of 2026-09-30 read `Swap this - take the vault
-- Dreamwatcher helm.` under the header. The document is R-2e's Dungeon one;
-- the two copies are the tier link with the upgrade bonus ID replaced by
-- invented ones (spec/roads_spec.lua's R-2f block says why).
describe("The tooltip over the worn vault pick after the claim (R-2f)", function()
    local ns
    local CATALYZED_DUNGEON = "spec/fixtures/qe/qe-droptimizer-Hotornot-esdfxjozstkc.json"
    local TIER_LINK = "|cnIQ4:|Hitem:271528::::::::90:105::35:7:6652:12844:13440:13695:13692:13698:1568"
        .. ":1:64:239033:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    -- Five minutes after the document's own `exportedAt` (R-2e's figure).
    local FIVE_MINUTES_LATER = 1790727723

    local function copyAt(bonusID, level, location)
        local link = (TIER_LINK:gsub(":12844:", ":" .. bonusID .. ":"))
        local parsed = ns.ParseItemLink(link)
        return {
            key = parsed.key,
            itemID = parsed.itemID,
            bonusIDs = parsed.bonusIDs,
            link = link,
            name = "Enigmatic Dreamwatcher's Somnolent Stare",
            slot = "Head",
            itemLevel = level,
            location = location,
        }
    end

    local function block(worn, others)
        local parsed = ns.QEImport.Parse(readFile(CATALYZED_DUNGEON))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = "catalyzed"
        parsed.verdict.qeSettings = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = true }
        local records = { worn }
        for _, record in ipairs(others or {}) do
            records[#records + 1] = record
        end
        local inputs = {
            verdicts = { { verdict = parsed.verdict, scenario = "catalyzed" } },
            highlightedScenario = "catalyzed",
            inventory = { records = records },
            -- The client's vault after the claim: no gear.
            vault = { ok = true, options = { { rewards = {} } } },
        }
        local answer = ns.Roads.ForItemIn(ns.Roads.ForSlot("Head", inputs), worn.key, inputs)
        answer.sentence = ns.Roads.ItemSentence(answer)
        answer.exportedAt = parsed.verdict.exportedAt
        local out = {}
        for index, line in ipairs(ns.UI.Tooltip.Lines(answer, { now = FIVE_MINUTES_LATER })) do
            out[index] = line.text
        end
        return out
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- PROVEN RED: without `wornIsPick` the second line is `Swap this - take
    -- the vault helm.`
    it("answers the worn helm as the pick, and never as a swap", function()
        local lines = block(copyAt(12845, 318, "equipped"), { copyAt(12838, 308, "bag") })
        assert.same({
            "Lootpath · Head",
            "Refresh - you're already wearing it.",
            -- The rated finish comes with it (R-2d): the helm is the pick now.
            -- The test link carries neither an enchant nor a gem (R-2g).
            "rated with: Empowered Hex of Leeching (missing) · a gem (missing)",
        }, lines)
        for _, text in ipairs(lines) do
            assert.is_nil(text:find("Swap", 1, true), text)
            assert.is_nil(text:find("take the vault", 1, true), text)
            assert.is_nil(usesForbidden(text), text)
        end
    end)
end)

-- R-2h (WKE-667): the block over the tier helm on the owner's head with
-- `everything upgraded` highlighted, after R-2f. His screen of 2026-09-30 read
-- `Swap this - take the vault Dreamwatcher helm.` under the header. The
-- document is his own `maxed` one of 14:43 UTC and the links are his inventory
-- capture of 16:56 UTC (spec/fixtures/qe/README.md; spec/roads_spec.lua's R-2h
-- block reads all four of that morning's documents).
describe("The tooltip over a worn copy of the pick below the pick's level (R-2h)", function()
    local ns
    local MAXED_DUNGEON = "spec/fixtures/qe/qe-droptimizer-Hotornot-ujciztenjvjk.json"
    local WORN_LINK = "|cnIQ4:|Hitem:271528:7961:240892::::::90:105::35:6:6652:13440:13695:13692:13698:12845"
        .. ":1:64:239033:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    local BAG_LINK = "|cnIQ4:|Hitem:271528:7960:::::::90:105::23:7:6652:13439:13696:12838:13692:13698:1561"
        .. ":1:64:251140:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    -- Five minutes after the document's own `exportedAt`, 2026-09-30T14:43:24.983Z.
    local FIVE_MINUTES_LATER = 1790779705

    local function record(link, level, location)
        local parsed = ns.ParseItemLink(link)
        return {
            key = parsed.key,
            itemID = parsed.itemID,
            bonusIDs = parsed.bonusIDs,
            link = link,
            name = "Enigmatic Dreamwatcher's Somnolent Stare",
            slot = "Head",
            itemLevel = level,
            location = location,
        }
    end

    local function block(worn, bag)
        local parsed = ns.QEImport.Parse(readFile(MAXED_DUNGEON))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = "maxed"
        parsed.verdict.qeSettings = { autoUpgradeVault = true, autoUpgradeAll = true, autoCatalyze = true }
        local inputs = {
            verdicts = { { verdict = parsed.verdict, scenario = "maxed" } },
            highlightedScenario = "maxed",
            inventory = { records = { worn, bag } },
            -- The client's vault after the claim: no gear, nothing waiting.
            vault = { ok = true, hasAvailableRewards = false, options = { { rewards = {} } } },
        }
        local answer = ns.Roads.ForItemIn(ns.Roads.ForSlot("Head", inputs), worn.key, inputs)
        answer.sentence = ns.Roads.ItemSentence(answer)
        answer.exportedAt = parsed.verdict.exportedAt
        local out = {}
        for index, line in ipairs(ns.UI.Tooltip.Lines(answer, { now = FIVE_MINUTES_LATER })) do
            out[index] = line.text
        end
        return out
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- PROVEN RED: without the R-2h branch the second line is `Swap this - take
    -- the vault helm.`
    it("tells the owner to crest the worn helm to 321, and never to swap it", function()
        local lines = block(record(WORN_LINK, 318, "equipped"), record(BAG_LINK, 308, "bag"))
        assert.same({
            "Lootpath · Head",
            "Crest this to 321 - then refresh.",
        }, lines)
        for _, text in ipairs(lines) do
            assert.is_nil(text:find("Swap", 1, true), text)
            assert.is_nil(text:find("take the vault", 1, true), text)
            assert.is_nil(usesForbidden(text), text)
        end
    end)
end)

-- R-2i (WKE-669): the block over the owner's worn helm and neck, whose gems
-- the rating dealt out the other way round (his helm carries 240892 and is
-- rated with 240983, his neck the reverse; fork `TopGearEngine.ts:85-94`).
-- Each socket is filled, so neither is marked: the line repeats the rating's
-- own names and says nothing else. The document is his Dungeon `asOffered` of
-- 22:18:09Z and the links his inventory capture of 22:20:53 UTC
-- (spec/fixtures/qe/README.md; spec/roads_spec.lua's R-2i block).
describe("The tooltip over a worn piece whose rated gem sits in another worn piece (R-2i)", function()
    local ns, world
    local DOCUMENT = "spec/fixtures/qe/qe-droptimizer-Hotornot-fummnzrekbwq.json"
    local HELM_LINK = "|cnIQ4:|Hitem:271528:7961:240892::::::90:105::35:6:6652:13440:13695:13692:13698:12845"
        .. ":1:64:239033:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    local BARE_HELM_LINK = "|cnIQ4:|Hitem:271528:7961:::::::90:105::35:6:6652:13440:13695:13692:13698:12845"
        .. ":1:64:239033:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    local NECK_LINK =
        "|cnIQ4:|Hitem:272228::240983::::::90:105::110:3:6652:13668:12846:1:28:6014:::::|h[Whispering Periapt]|h|r"
    -- Five minutes after the document's own `exportedAt`, 2026-09-30T22:18:09.961Z.
    local FIVE_MINUTES_LATER = 1790806990

    local function record(link, slot, level)
        local parsed = ns.ParseItemLink(link)
        return {
            key = parsed.key,
            itemID = parsed.itemID,
            bonusIDs = parsed.bonusIDs,
            link = link,
            name = "Worn Piece",
            slot = slot,
            itemLevel = level,
            location = "equipped",
        }
    end

    local function block(worn, records)
        local parsed = ns.QEImport.Parse(readFile(DOCUMENT))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = "asOffered"
        parsed.verdict.qeSettings = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = false }
        local inputs = {
            verdicts = { { verdict = parsed.verdict, scenario = "asOffered" } },
            highlightedScenario = "asOffered",
            inventory = { records = records },
            vault = { ok = true, hasAvailableRewards = false, options = { { rewards = {} } } },
        }
        local answer = ns.Roads.ForItemIn(ns.Roads.ForSlot(worn.slot, inputs), worn.key, inputs)
        answer.sentence = ns.Roads.ItemSentence(answer)
        answer.exportedAt = parsed.verdict.exportedAt
        ns.RoadsCache.NameGems({ byKey = { [worn.key] = answer } })
        local out = {}
        for index, line in ipairs(ns.UI.Tooltip.Lines(answer, { now = FIVE_MINUTES_LATER })) do
            out[index] = line.text
        end
        return out, answer
    end

    before_each(function()
        ns, world = H.load()
        -- The client's names for the two gems, as stubs: the client's own name
        -- for the meta gem 240983 is unread (the engine's comment and its gem
        -- table name it two ways, `TopGearEngine.ts:86`, `GemDB.ts:20-22`).
        world.items[240983] = { info = { "Stub Meta Gem", "|Hitem:240983|h[Stub Meta Gem]|h", 3, n = 3 } }
        world.items[240892] = { info = { "Stub Gem", "|Hitem:240892|h[Stub Gem]|h", 3, n = 3 } }
    end)

    after_each(function()
        H.unload()
    end)

    -- PROVEN RED: under R-2d's per-ID rule the third lines read `rated with:
    -- Empowered Hex of Leeching · Stub Meta Gem (missing)` and `rated with:
    -- Stub Gem (missing)`.
    it("names the rated gem on his helm and neck, and marks neither", function()
        local helm, neck = record(HELM_LINK, "Head", 318), record(NECK_LINK, "Neck", 321)
        local helmLines = block(helm, { helm, neck })
        assert.equal("Keep this on.", helmLines[2])
        assert.equal("rated with: Empowered Hex of Leeching · Stub Meta Gem", helmLines[3])
        local neckLines = block(neck, { helm, neck })
        assert.equal("Keep this on.", neckLines[2])
        assert.equal("rated with: Stub Gem", neckLines[3])
        for _, text in ipairs({ helmLines[3], neckLines[3] }) do
            assert.is_nil(text:find("(missing)", 1, true), text)
            assert.is_nil(usesForbidden(text), text)
        end
        -- The whole line in the note tone: nothing drawn in the mark's colour.
        local _, answer = block(helm, { helm, neck })
        local _, parts = ns.UI.Tooltip.FinishText(answer)
        for _, part in ipairs(parts) do
            assert.equal(ns.UI.Tooltip.NOTE_HEX, part.hex)
        end
    end)

    -- An empty socket still says so, even with the meta gem on his neck.
    it("still marks a gem whose socket is empty", function()
        local helm, neck = record(BARE_HELM_LINK, "Head", 318), record(NECK_LINK, "Neck", 321)
        local lines = block(helm, { helm, neck })
        assert.equal("rated with: Empowered Hex of Leeching · Stub Meta Gem (missing)", lines[3])
    end)
end)

-- R-2k (WKE-694): the owner's three copies of his tier helm after the reset-day
-- refresh, 2026-10-06 evening. "After a new refresh the tooltip on the item says
-- to wear this, but Equip Now tab doesn't show this." The bag 318 (Myth 1/6,
-- from the vault) read `Wear this.` over `rated with: Empowered Hex of Leeching
-- (missing)`, while Equip Now kept the worn 321 (Hero 6/6).
--
-- The replay (ARCHITECTURE.md §9) found the issue's premise wrong: every copy
-- was answered by its OWN key, never by level or item ID. The bag 318's
-- answer was its own - `everything upgraded`, the highlighted scenario, picks
-- that very copy at 334 - and lacked only the crest. The copies that borrowed
-- another copy's answer were the OTHER two: R-3c's item-ID identity read the
-- worn 321 as the pick "already worn" and the bag 308 as the pick "short of its
-- crest", each with the 318's `rated with:` line. Equip Now reads `as offered`,
-- which keeps the worn 321, and is unchanged.
--
-- The documents are his pass-1 Dungeon `asOffered` and `maxed` of 02:43:42Z and
-- 02:46:02Z, from the companion's verdict file of 02:46:35Z; the links are his
-- inventory capture of 2026-10-07 02:46:39 UTC (spec/fixtures/qe/README.md).
describe("The tooltip over three copies of the worn top-set helm (R-2k)", function()
    local ns
    local MAXED = "spec/fixtures/qe/qe-droptimizer-Hotornot-zdgtaqcigomq.json"
    local AS_OFFERED = "spec/fixtures/qe/qe-droptimizer-Hotornot-abqtlwlwsnms.json"
    local WORN_LINK = "|cnIQ4:|Hitem:271528:7961:240892::::::90:105::35:6:6652:13440:13695:13692:13698:12846"
        .. ":1:64:239033:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    local BAG_318_LINK = "|cnIQ4:|Hitem:271528::::::::90:105::35:6:13692:12849:13440:6652:13696:13698"
        .. "::::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    local BAG_308_LINK = "|cnIQ4:|Hitem:271528:7960:::::::90:105::23:7:6652:13439:13696:12838:13692:13698:1561"
        .. ":1:64:251140:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    -- Five minutes after the `maxed` document's own `exportedAt`.
    local FIVE_MINUTES_LATER = 1791341462

    local worn, bag318, bag308, lookups

    local function record(link, level, location)
        local parsed = ns.ParseItemLink(link)
        return {
            key = parsed.key,
            itemID = parsed.itemID,
            bonusIDs = parsed.bonusIDs,
            link = link,
            name = "Enigmatic Dreamwatcher's Somnolent Stare",
            slot = "Head",
            itemLevel = level,
            location = location,
        }
    end

    -- The map over his three copies under one scenario, built the way the
    -- hover reads it.
    local function build(path, scenario, settings)
        local parsed = ns.QEImport.Parse(readFile(path))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = scenario
        parsed.verdict.qeSettings = settings
        local inputs = {
            verdicts = { { verdict = parsed.verdict, scenario = scenario } },
            highlightedScenario = scenario,
            inventory = { records = { worn, bag318, bag308 } },
            -- After the claim: no gear in the vault, nothing waiting.
            vault = { ok = true, hasAvailableRewards = false, options = { { rewards = {} } } },
        }
        ns.RoadsCache.SetMap(ns.RoadsCache.Build({ roadInputs = inputs }))
        return inputs
    end

    local function block(link)
        local answer, key = ns.UI.Tooltip.Answer(link)
        assert.is_table(answer, link)
        local out = {}
        for index, line in ipairs(ns.UI.Tooltip.Lines(answer, { now = FIVE_MINUTES_LATER })) do
            out[index] = line.text
        end
        return out, answer, key
    end

    local function maxed()
        return build(MAXED, "maxed", { autoUpgradeVault = true, autoUpgradeAll = true, autoCatalyze = true })
    end

    local function asOffered()
        return build(
            AS_OFFERED,
            "asOffered",
            { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = false }
        )
    end

    before_each(function()
        ns = H.load()
        worn = record(WORN_LINK, 321, "equipped")
        bag318 = record(BAG_318_LINK, 318, "bag")
        bag308 = record(BAG_308_LINK, 308, "bag")
        -- Every fallback lookup counted: a copy you hold must never need one.
        lookups = 0
        local atLevel, item = ns.RoadsCache.LookupAtLevel, ns.RoadsCache.LookupItem
        ns.RoadsCache.LookupAtLevel = function(...)
            lookups = lookups + 1
            return atLevel(...)
        end
        ns.RoadsCache.LookupItem = function(...)
            lookups = lookups + 1
            return item(...)
        end
    end)

    after_each(function()
        ns.RoadsCache.Reset()
        H.unload()
    end)

    -- The replay's first finding, kept: a copy you hold is answered by its own
    -- key and nothing else, so neither fallback is ever asked.
    it("answers every copy he holds by its own key", function()
        maxed()
        for _, held in ipairs({ worn, bag318, bag308 }) do
            local _, answer, key = block(held.link)
            assert.equal(held.key, key)
            assert.is_true(answer.held)
            assert.equal(held.key, answer.heldItem.key)
        end
        assert.equal(0, lookups)
    end)

    -- PROVEN RED: without the crest clause the second line is `Wear this.`, the
    -- owner's sentence.
    it("tells the bag 318 to go on and be crested, from its own rating", function()
        maxed()
        local lines, answer = block(bag318.link)
        assert.equal("Lootpath · Head", lines[1])
        assert.equal("Wear this - crest it after.", lines[2])
        -- Its own entry, at 334: the rating enchants that very copy, and the
        -- copy carries no enchant.
        assert.equal(bag318.key, answer.own.verdictItem.key)
        assert.equal(334, answer.own.verdictItem.level)
        assert.equal("rated with: Empowered Hex of Leeching (missing)", lines[3])
        for _, text in ipairs(lines) do
            assert.is_nil(usesForbidden(text), text)
        end
    end)

    -- PROVEN RED: with `IsArrivedPick` reading the item ID while the pick's own
    -- key is held, this is `Refresh - you're already wearing it.` over the
    -- 318's `rated with: Empowered Hex of Leeching`.
    it("never calls the worn 321 the 318's pick, nor gives it the 318's finish", function()
        local inputs = maxed()
        local lines, answer = block(worn.link)
        assert.equal("Swap this - use your Dreamwatcher helm.", lines[2])
        assert.is_nil(answer.finish)
        for _, text in ipairs(lines) do
            assert.is_nil(text:find("already wearing", 1, true), text)
            assert.is_nil(text:find("rated with", 1, true), text)
        end
        local pick = ns.Roads.PlanPick(ns.RoadsCache.Map().bySlot.Head)
        assert.is_true(pick.ownHeld)
        assert.is_true(ns.Roads.HoldsOwnKey(pick, inputs))
        assert.is_false(ns.Roads.IsArrivedPick(worn, pick))
        -- And the pick's row is not "now worn" over a copy that is not it.
        assert.is_nil(pick.claimed)
        assert.is_nil(pick.arrived)
    end)

    -- PROVEN RED: the same mutation reads `Crest this to 318 - then refresh.`
    -- here, with the 318's finish line.
    it("passes on the bag 308, and never tells it to crest to the 318's level", function()
        maxed()
        local lines, answer = block(bag308.link)
        assert.equal("Pass - use your Dreamwatcher helm.", lines[2])
        assert.is_nil(answer.finish)
        for _, text in ipairs(lines) do
            assert.is_nil(text:find("Crest this", 1, true), text)
            assert.is_nil(text:find("rated with", 1, true), text)
        end
    end)

    -- What Equip Now reads, `as offered`: the worn 321 is the pick, its block
    -- names its own enchant, and both bag copies pass. Unchanged by R-2k.
    it("keeps the worn 321 on as offered, with its own finish", function()
        asOffered()
        local lines, answer = block(worn.link)
        assert.equal("Keep this on.", lines[2])
        assert.equal(worn.key, answer.own.verdictItem.key)
        -- The client names the gem in game; headless it is `a gem`. His socket
        -- is filled, so nothing is marked (R-2i).
        assert.equal("rated with: Empowered Hex of Leeching · a gem", lines[3])
        for _, held in ipairs({ bag318, bag308 }) do
            local bagLines, bagAnswer = block(held.link)
            assert.equal("Pass - use your Dreamwatcher helm.", bagLines[2])
            assert.is_nil(bagAnswer.finish)
        end
    end)

    -- Equip Now's own join over the same three copies and the `as offered`
    -- document: the worn copy, by key (M2-6).
    it("leaves Equip Now on the worn 321", function()
        local parsed = ns.QEImport.Parse(readFile(AS_OFFERED))
        assert.is_true(parsed.ok, parsed.reason)
        local matched = ns.Match.Build({ ok = true, records = { worn, bag318, bag308 } }, parsed.verdict)
        assert.is_true(matched.ok, matched.reason)
        local head
        for _, row in ipairs(matched.rows) do
            if row.slot == "Head" then
                head = row
            end
        end
        assert.is_table(head)
        assert.equal(worn.key, head.best.key)
        assert.equal(ns.Match.MATCHED_BY_KEY, head.matchedBy)
        assert.equal(ns.Match.STATUS.EQUIPPED_IS_BEST, head.status)
    end)
end)

-- R-2l (WKE-695): a piece you hold that wins only once it is crested. The
-- owner, 2026-10-07, over the same bag 318 helm: "if this is telling me to wear
-- this, then shouldn't Equip Now also be telling me to equip it? ... does it
-- have to be crested all the way to 334 to be better? If not then we should say
-- the very next item level that will make it better." And his tooltip design of
-- the same day: the percent on its own line above the sentence, `+0.19%
-- Upgrade`, only when it is an upgrade; no `Better:` line; no `Rated ...`
-- footer; the short sentence `Crest to 324 - then wear`.
--
-- The documents are his, unedited (spec/fixtures/qe/README.md): the R-2k pair
-- for Dungeon (the 23:19-23:21Z run's Dungeon `asOffered` and `maxed` differ
-- from them only in `exportedAt` and `reportId`), and that later run's Dungeon
-- +10 and Raid Upgrade Finder documents and Raid pass-1 `asOffered` and
-- `maxed`. The links are R-2k's, his inventory capture of 2026-10-07 02:46:39
-- UTC.
describe("A held piece that wins only once crested (R-2l)", function()
    local ns
    local FILES = {
        Dungeon = {
            asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-abqtlwlwsnms.json",
            maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-zdgtaqcigomq.json",
            uf = "spec/fixtures/qe/r2l/qe-upgradefinder-Hotornot-pxfjkvtjslxy.json",
        },
        Raid = {
            asOffered = "spec/fixtures/qe/r2l/qe-droptimizer-Hotornot-hfuvwbktjxbn.json",
            maxed = "spec/fixtures/qe/r2l/qe-droptimizer-Hotornot-yomfpzeabcrr.json",
            uf = "spec/fixtures/qe/r2l/qe-upgradefinder-Hotornot-vpbzaajcevxr.json",
        },
    }
    local SETTINGS = {
        asOffered = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = false },
        maxed = { autoUpgradeVault = true, autoUpgradeAll = true, autoCatalyze = true },
    }
    local WORN_LINK = "|cnIQ4:|Hitem:271528:7961:240892::::::90:105::35:6:6652:13440:13695:13692:13698:12846"
        .. ":1:64:239033:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    local BAG_318_LINK = "|cnIQ4:|Hitem:271528::::::::90:105::35:6:13692:12849:13440:6652:13696:13698"
        .. "::::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"
    local BAG_308_LINK = "|cnIQ4:|Hitem:271528:7960:::::::90:105::23:7:6652:13439:13696:12838:13692:13698:1561"
        .. ":1:64:251140:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r"

    local worn, bag318, bag308

    local function record(link, level, location)
        local parsed = ns.ParseItemLink(link)
        return {
            key = parsed.key,
            itemID = parsed.itemID,
            bonusIDs = parsed.bonusIDs,
            link = link,
            name = "Enigmatic Dreamwatcher's Somnolent Stare",
            slot = "Head",
            itemLevel = level,
            location = location,
        }
    end

    local function droptimizer(contentType, scenario)
        local parsed = ns.QEImport.Parse(readFile(FILES[contentType][scenario]))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = scenario
        parsed.verdict.qeSettings = SETTINGS[scenario]
        return parsed.verdict
    end

    local function upgradeFinder(contentType)
        local parsed = ns.UFImport.Parse(readFile(FILES[contentType].uf))
        assert.is_true(parsed.ok, parsed.reason)
        return { { verdict = parsed.verdict, keyLevel = 10 } }
    end

    -- The map over his three copies, the content type on screen, the
    -- scenario the hover follows - built the way the hover reads it.
    local function build(contentType, highlighted, documents)
        local inputs = {
            verdicts = {
                { verdict = droptimizer(contentType, "asOffered"), scenario = "asOffered" },
                { verdict = droptimizer(contentType, "maxed"), scenario = "maxed" },
            },
            highlightedScenario = highlighted,
            ufDocuments = documents or upgradeFinder(contentType),
            inventory = { records = { worn, bag318, bag308 } },
            vault = { ok = true, hasAvailableRewards = false, options = { { rewards = {} } } },
        }
        ns.RoadsCache.SetMap(ns.RoadsCache.Build({ roadInputs = inputs }))
        return inputs
    end

    local function block(link)
        local answer = ns.UI.Tooltip.Answer(link)
        assert.is_table(answer, link)
        local out = {}
        for index, line in ipairs(ns.UI.Tooltip.Lines(answer, {})) do
            out[index] = line.text
        end
        return out, answer
    end

    local function headRow(contentType)
        local matched =
            ns.Match.Build({ ok = true, records = { worn, bag318, bag308 } }, droptimizer(contentType, "asOffered"))
        assert.is_true(matched.ok, matched.reason)
        for _, row in ipairs(matched.rows) do
            if row.slot == "Head" then
                return row, matched
            end
        end
        error("no Head row")
    end

    before_each(function()
        ns = H.load()
        worn = record(WORN_LINK, 321, "equipped")
        bag318 = record(BAG_318_LINK, 318, "bag")
        bag308 = record(BAG_308_LINK, 308, "bag")
    end)

    after_each(function()
        ns.RoadsCache.Reset()
        H.unload()
    end)

    -- PROVEN RED (the R-2l branch in `ItemSentence` off): `Wear this - crest it
    -- after.`, R-2k's words, the order the owner called wrong.
    it("under Dungeon tells the bag 318 to crest to 324 first, with that level's percent", function()
        build("Dungeon", "maxed")
        local lines, answer = block(bag318.link)
        assert.same({
            "Lootpath · Head",
            "+0.19% Upgrade",
            "Crest to 324 - then wear.",
            "rated with: Empowered Hex of Leeching (missing)",
        }, lines)
        -- The rows, as his documents carry them, from one document.
        assert.equal(324, answer.crestTo.level)
        assert.equal(0.194, answer.crestTo.percent)
        assert.same({ { level = 324, percent = 0.194 }, { level = 334, percent = 0.608 } }, answer.crestTo.rows)
        for _, text in ipairs(lines) do
            assert.is_nil(usesForbidden(text), text)
            assert.is_nil(text:find("Better:", 1, true), text)
            assert.is_nil(text:find("Rated ", 1, true), text)
            assert.is_nil(text:find("/lootpath", 1, true), text)
        end
    end)

    -- The same copy under the scenario Equip Now reads: not the pick there, and
    -- still the crest, never a pass on the piece that wins at 324.
    it("says the same under as offered, where the 318 is rated behind", function()
        build("Dungeon", "asOffered")
        local lines = block(bag318.link)
        assert.same({ "Lootpath · Head", "+0.19% Upgrade", "Crest to 324 - then wear." }, lines)
    end)

    -- PROVEN RED (the crest step out of `finishSetRoad`): the row's next step is
    -- `put it on` and the slot's line `Put on the Dreamwatcher helm, no crests
    -- here.`
    it("puts both levels on the crest step and takes `no crests here` off the Head line", function()
        build("Dungeon", "maxed")
        local slotRoads = ns.RoadsCache.Map().bySlot.Head
        local pick = ns.Roads.PlanPick(slotRoads)
        assert.equal(ns.Roads.KIND_SET, pick.kind)
        assert.equal(bag318.key, pick.keys[1])
        assert.equal("crest to 324 +0.19% · to 334 +0.61%", pick.nextStep.text)
        assert.equal("do: crest to 324 - then wear", pick.todo)
        local line = ns.Roads.SlotSentence(slotRoads)
        assert.equal("Crest the Dreamwatcher helm to 324, then put it on.", line)
        assert.is_nil(line:find("no crests here", 1, true))
    end)

    -- PROVEN RED (`AnswerText` ignoring the pending crests): `You're set -
    -- every slot is your best.`, the owner's screen.
    it("has Equip Now name the cresting and never offer the 318 as a swap, under Dungeon", function()
        build("Dungeon", "maxed")
        local head = headRow("Dungeon")
        assert.equal(worn.key, head.best.key)
        assert.equal(ns.Match.STATUS.EQUIPPED_IS_BEST, head.status)
        local crests = ns.UI.EquipPanel.PendingCrests()
        assert.equal(1, #crests)
        assert.equal(bag318.key, crests[1].key)
        assert.equal(324, crests[1].level)
        local match = { ok = true, rows = { head }, counts = { equipped_is_best = 1 } }
        assert.equal(
            "You're set - the helm in your bags wants cresting.",
            ns.UI.EquipPanel.AnswerText(match, nil, crests)
        )
        assert.equal("You're set - every slot is your best.", ns.UI.EquipPanel.AnswerText(match, nil, {}))
    end)

    -- Decision 4: Raid's `as offered` takes the 318 as it is, so the piece is a
    -- win now and Equip Now offers the swap. The tooltip keeps R-2k's words and
    -- carries NO percent line: no document rates 271528 at 318, and the +0.37%
    -- is the 324 row's - a figure for a level the copy is not at (R-2c's rule:
    -- the rated figure is never stretched to the copy's level).
    it("under Raid wears the 318 now, offers the swap, and puts no 324 figure on a 318", function()
        build("Raid", "maxed")
        local lines, answer = block(bag318.link)
        assert.same({
            "Lootpath · Head",
            "Wear this - crest it after.",
            "rated with: Empowered Hex of Leeching (missing)",
        }, lines)
        assert.is_nil(answer.crestTo)
        assert.is_true(ns.Roads.WinsAsOffered(build("Raid", "maxed"), bag318))
        local head = headRow("Raid")
        assert.equal(ns.Match.STATUS.SWAP, head.status)
        assert.equal(bag318.key, head.best.key)
        assert.same({}, ns.UI.EquipPanel.PendingCrests())
        local match = { ok = true, rows = { head }, counts = { swap = 1 } }
        assert.equal("Put on the Dreamwatcher helm.", ns.UI.EquipPanel.AnswerText(match, nil, {}))
        local slotRoads = ns.RoadsCache.Map().bySlot.Head
        assert.equal("Put on the Dreamwatcher helm and crest it.", ns.Roads.SlotSentence(slotRoads))
    end)

    -- PROVEN RED (`IsUpgrade` dropped from `FirstWinningLevel`): the 318 reads
    -- `Crest to 324 - then wear.` over rows that are not upgrades.
    it("passes on a held copy with no positive row, and shows no percent", function()
        -- His Dungeon document with every row for this item set to a figure
        -- that is not an upgrade - the one hand-made case in this block.
        local documents = upgradeFinder("Dungeon")
        for _, entry in pairs(documents[1].verdict.items) do
            if entry.itemID == 271528 then
                entry.upgradePercent = -0.1
            end
        end
        build("Dungeon", "asOffered", documents)
        local lines, answer = block(bag318.link)
        assert.is_nil(answer.crestTo)
        assert.same({ "Lootpath · Head", "Pass - use your Dreamwatcher helm." }, lines)
    end)

    -- PROVEN RED (the `CatalystSource` refusal out of `CrestToWin`): a copy
    -- whose link names the item it was converted from is answered with the
    -- drop's rows. The transcripts show such a copy carrying its source's
    -- secondaries (Crit/Haste from the Hood, Haste/Mastery from 251140), so it
    -- is not the drop at any level.
    it("never answers a Catalyst copy with the drop's rows", function()
        local inputs = build("Dungeon", "asOffered")
        assert.equal(324, ns.Roads.CrestToWin(inputs, bag318).level)
        local converted = record(BAG_318_LINK:gsub("::::::|h", ":1:64:239033:::::|h", 1), 318, "bag")
        assert.equal(bag318.key, converted.key)
        assert.equal(239033, ns.Roads.CatalystSource(converted))
        assert.is_nil(ns.Roads.CrestToWin(inputs, converted))
    end)

    -- Decision 3: a drop rated BELOW what you wear keeps its signed badge on
    -- the Upgrade Map and loses the figure on the tooltip.
    it("shows no percent over a drop rated negative, and the badge stays signed", function()
        local answer = {
            held = false,
            slot = "Head",
            others = {},
            own = {
                kind = ns.Roads.KIND_DROP,
                group = ns.Roads.GROUP_ITEM,
                rating = { kind = ns.Roads.RATING_ITEM, percent = -0.5 },
            },
        }
        assert.is_nil(ns.Roads.UpgradePercent(answer))
        for _, line in ipairs(ns.UI.Tooltip.Lines(answer, {})) do
            assert.is_nil(line.text:find("Upgrade", 1, true), line.text)
            assert.is_nil(line.text:find("%", 1, true), line.text)
        end
        assert.equal("-0.50%", ns.Roads.ItemBadge(-0.5))
        -- And the same drop rated above: the figure is the block's line, and
        -- the sentence that restated it is not drawn twice.
        answer.own.rating.percent = 0.372
        answer.sentence = ns.Roads.ItemSentence(answer)
        assert.equal("Worth 0.37% over your helm.", answer.sentence)
        local lines = ns.UI.Tooltip.Lines(answer, {})
        assert.equal("+0.37% Upgrade", lines[2].text)
        assert.equal(2, #lines)
    end)
end)
