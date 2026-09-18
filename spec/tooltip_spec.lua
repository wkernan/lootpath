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
        -- R-3b (WKE-576) added the fourth clause: this slot's bags hold the
        -- Miststalker's Spaulders, which the rating never saw, so the header
        -- says what cures that.
        assert.same({
            "Lootpath · Shoulder",
            "Catalyst these - tier shoulders.",
            "Better: a crafted piece (331), +1.11%",
            "Rated 5h ago · /lootpath refresh",
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
            "Better: a crafted piece (331), +1.11%",
            "Rated 5h ago · /lootpath refresh",
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

    it("draws ONE other road however many the slot has, and never the pick", function()
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
        assert.equal(1, drawn)
        assert.equal("Better: second (300), +1.50%", better)
    end)

    it("never draws more than four lines, and the last is the age and one command", function()
        local map = ns.RoadsCache.Map()
        for key in pairs(map.byKey) do
            local block = lines(key)
            assert.is_true(#block <= 4, key .. " draws " .. #block .. " lines")
            local last = block[#block]
            assert.is_true(
                last == "Rated 5h ago · /lootpath map" or last == "Rated 5h ago · /lootpath refresh",
                key .. " ends on " .. tostring(last)
            )
            -- One command on the block, and it is on that line.
            local commands = 0
            for _, text in ipairs(block) do
                if text:find("/lootpath", 1, true) then
                    commands = commands + 1
                end
            end
            assert.equal(1, commands, key .. " carries " .. commands .. " commands")
        end
    end)

    it("is two lines when there is no sentence and no road that gains", function()
        -- Built rather than found: the owner's week has no such slot, and the
        -- rule is the block's, not the week's. The honesty phrase that used to
        -- take line 2 is cut (UX-3, WKE-599, reading 3).
        local answer = { slot = "Shoulder", others = {}, phrase = ns.Roads.PHRASE_NO_RATING }
        assert.same(
            {
                "Lootpath · Shoulder",
                "Rated: not known · /lootpath map",
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
        assert.equal("Better: a crafted piece (331), +1.11%", block[3])
        assert.equal("Rated 5h ago · /lootpath refresh", block[4])
    end)

    it("says the pick's part of the plan on the vault weapon, crest clause and all", function()
        local block = lines(VAULT_WORLDROOT)
        assert.equal("Lootpath · 2H Weapon", block[1])
        assert.equal("Grab this - crest it after.", block[2])
        assert.equal("Rated 5h ago · /lootpath refresh", block[#block])
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
        assert.equal("Rated 5h ago · /lootpath refresh", block[#block])
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
        assert.is_true(read > 1000, "read only " .. read .. " lines")
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
        assert.is_truthy(text:find("/lootpath map", 1, true) or text:find("/lootpath refresh", 1, true))
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

    it("adds nothing for a chat link or a merchant item no road knows", function()
        local shown = world.showItemTooltip({ hyperlink = "|Hitem:99999::::::::80:105::::::|h[Nothing]|h" })
        assert.is_nil(shown.stub.Text():find("Lootpath", 1, true))
    end)

    it("walks nothing on the hover path", function()
        -- "O(1) on the hover path" as a guard rather than a claim: once the map
        -- is built, a hover may not reach the model, the journal walk or a bag
        -- scan. This is what "no table allocation beyond the lines" can be
        -- proven to mean in a language whose allocator a test cannot ask.
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
        count(ns.Roads, "PlanSentence")
        count(ns.Inventory, "Scan")
        count(ns.UpgradeMapPanel, "Model")
        count(ns.UpgradeMapPanel, "Gather")
        for _ = 1, 50 do
            hover(LYNX)
            hover(MISTSTALKER)
            hover(VAULT_SPAULDERS)
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
        assert.equal("Rated 5h ago · /lootpath refresh", block[#block])
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
        table.insert(gathered.inventory.records, worn)
        model = ns.UpgradeMapPanel.Model(gathered)
        ns.RoadsCache.SetMap(ns.RoadsCache.Build(model))
        return worn
    end

    it("tells the player the pick is on the character, not to skip it", function()
        local worn = wearCrestedCloak()
        local block = lines(worn.key)
        assert.equal("Refresh - you're already wearing it.", block[2])
        -- The road the worn copy really has - the Upgrade road every worn piece
        -- gets - rates nothing, so line 3 is the slot's one road that does gain
        -- instead, named as the item and where it drops. The row on the panel
        -- still carries the Upgrade road.
        assert.equal("Better: Silken Voodoo Drape (344), +1.24% · The Venomous Abyss, Mythic raid", block[3])
        -- The Back slot's bags hold nothing the rating never saw once the pick
        -- is on the character, so the command is the map's and not the
        -- refresh's: `answer.stale` is this slot's bags, not the block's mood.
        assert.equal("Rated 5h ago · /lootpath map", block[4])
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
        assert.is_truthy(text:find("Rated ", 1, true))
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
            "Rated 5h ago · /lootpath refresh",
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
            "Rated 5h ago · /lootpath refresh",
        }, block)
    end)

    -- The glow follows, because it is principle 12's one test and not a second
    -- one: not knowing is not a verdict either way.
    it("does not glow on a reward nothing rated", function()
        build({ profileVaultCount = 0 })
        assert.is_false(ns.Glow.Wants(LEGGINGS))
    end)
end)
