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

-- The verdict's own time, and a moment five hours after it, so the header's age
-- is a figure of the fixture rather than of the clock the tests run on.
local EXPORTED_AT = "2026-09-09T19:22:44.178Z"
local FIVE_HOURS_LATER = 1789000000

-- No player-facing string on this surface may name a source (owner's decision,
-- 2026-09-11), and none of them may use a phrasing the brief struck.
local FORBIDDEN = { "QE Live", "his", "verdict", "should", "before reset", "last day" }

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
        assert.equal("this week's plan", map.planName)
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
        assert.same({
            "Lootpath · Shoulder · rated 5 hour(s) ago",
            "Catalyst this one.",
            "Catalyst · Venom-Cursed Lynx's Spaulders (295) · into the tier shoulders · in your best set"
                .. " · the same charge as the vault Spaulders road",
            "Other roads for this slot",
            "Crafted · item 244572 (331) · +1.11% · the rating assumes Crit / Haste · spark and materials not read",
            "Upgrade · Seedpods of the Luminous Bloom (289) · no rating · crest type and cost not read"
                .. " · you hold 356 Adventurer Mistcrest, 2 Champion Mistcrest, 21 Hero Mistcrest, 20 Myth Mistcrest",
            "Why this?",
        }, lines(LYNX))
    end)

    it("draws at most three roads however many the slot has", function()
        -- Handcrafted, because the model has exactly three groups and so hands
        -- over at most two others on the owner's own week: the cap has to be
        -- asserted against an answer that tries to exceed it, or it is true by
        -- accident rather than by rule (principle 10).
        local function road(name)
            return {
                kind = ns.Roads.KIND_DROP,
                group = ns.Roads.GROUP_ITEM,
                slot = "Shoulder",
                keys = {},
                item = {
                    itemID = 1,
                    name = name,
                },
                arrivesAt = 300,
            }
        end
        local answer = {
            slot = "Shoulder",
            own = road("own"),
            others = { road("first"), road("second"), road("third"), road("fourth") },
        }
        local drawn = 0
        for _, line in ipairs(ns.UI.Tooltip.Lines(answer)) do
            if line.text:find("(300)", 1, true) then
                drawn = drawn + 1
            end
        end
        assert.equal(ns.Roads.TOOLTIP_ROADS, drawn)
        assert.equal(3, drawn)
    end)

    it("never draws more than three roads, one sub-header and Why this?", function()
        local map = ns.RoadsCache.Map()
        for key, answer in pairs(map.byKey) do
            local roads = (answer.own and 1 or 0) + #answer.others
            assert.is_true(roads <= 3, key .. " opens onto " .. roads .. " roads")
            local block = lines(key)
            assert.equal("Why this?", block[#block], key .. " does not end on Why this?")
            local headers = 0
            for _, text in ipairs(block) do
                if text == "Other roads for this slot" then
                    headers = headers + 1
                end
            end
            assert.is_true(headers <= 1, key .. " carries " .. headers .. " sub-headers")
        end
    end)

    it("leaves the sub-header off entirely when the slot has no other road", function()
        -- Built rather than found: the owner's week has no such slot, and the
        -- rule is the block's, not the week's.
        local answer = { slot = "Shoulder", others = {}, phrase = ns.Roads.PHRASE_NO_RATING }
        assert.same(
            {
                "Lootpath · Shoulder · rated at an unknown time",
                "no rating",
                "Why this?",
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
        assert.equal("Skip this one, the plan uses your Lynx shoulders.", block[2])
        assert.equal(
            "Vault · open now · Scavenger's Spaulders (308) · into the tier shoulders · upgraded to 321"
                .. " · 1.73% behind · taking the vault weapon instead"
                .. " · the same charge as the Catalyst road: one of these, not both"
                .. " · crest type and cost not readable · reset in 6d 21h",
            block[3]
        )
    end)

    it("says the pick's part of the plan on the vault weapon, crest clause and all", function()
        local block = lines(VAULT_WORLDROOT)
        assert.equal("Lootpath · 2H Weapon · rated 5 hour(s) ago", block[1])
        assert.equal("Grab this from the vault and crest it.", block[2])
    end)

    it("replaces the road with the honesty phrase and its tail when nothing rated the item", function()
        local block = lines(MISTSTALKER)
        assert.equal("Lootpath · Shoulder · rated 5 hour(s) ago", block[1])
        assert.equal(ns.Roads.PHRASE_NOT_RATED_NEW, block[2])
        assert.equal("not rated · new since the last refresh", block[2])
        -- No chat sentence: the plan says nothing about an item it never saw.
        assert.is_nil(ns.RoadsCache.Lookup(MISTSTALKER).sentence)
        assert.equal("Other roads for this slot", block[3])
        assert.equal("Why this?", block[#block])
    end)

    it("writes no plan sentence for a road the plan takes no position on", function()
        -- A journal drop is in the `item` group; "Skip this one" there would
        -- read as "skip the dungeon", which no document said.
        local map = ns.RoadsCache.Map()
        for key, answer in pairs(map.byKey) do
            if answer.own and answer.own.group ~= ns.Roads.GROUP_SET then
                assert.is_nil(answer.sentence, key .. " put a plan sentence on a " .. answer.own.group .. " road")
            end
        end
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
        assert.is_truthy(text:find("Catalyst this one.", 1, true))
        assert.is_truthy(text:find("Why this?", 1, true))
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
        assert.equal("no plan stored", map.reason)
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
        assert.equal("top_left", registered.position.corner)
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

    it("names the bag window the mark is in on the status strip's tooltip", function()
        ns.UI.Bags.Reset()
        ns.UI.Bags.Install()
        local found = false
        for _, line in ipairs(ns.UI.StatusStripModel().tooltip) do
            found = found or line == "bag glow: drawn in the client's own bag frames"
        end
        assert.is_true(found, "the strip does not say where the mark is drawn")
    end)

    it("says so honestly when no adapter fits the bag window in use", function()
        ns.UI.Bags.Reset()
        local adapters = ns.UI.Bags.adapters
        ns.UI.Bags.adapters = {}
        local ok, note = ns.UI.Bags.Install()
        assert.is_false(ok)
        assert.equal("bag glow: this bag window is not one Lootpath can mark; the tooltip still works", note)
        -- The tooltip is bag-independent and is unaffected.
        assert.is_truthy(hover(LYNX):find("Catalyst this one.", 1, true))
        ns.UI.Bags.adapters = adapters
    end)

    -- -----------------------------------------------------------------------
    -- Lootpath's own vault cell, through the same function.

    it("puts the same block on the vault cell as on a bag hover", function()
        local cell = { data = { key = VAULT_WORLDROOT, name = "Lightgrasp Worldroot", tooltipLines = {} } }
        assert.is_true(ns.VaultPanel.ShowCellTooltip(cell))
        local text = GameTooltip.stub.Text()
        assert.is_truthy(text:find("Grab this from the vault and crest it.", 1, true))
        assert.is_truthy(text:find("Why this?", 1, true))
    end)

    it("puts nothing on the vault cell in combat", function()
        world.inCombat = true
        local cell = { data = { key = VAULT_WORLDROOT, name = "Lightgrasp Worldroot", tooltipLines = {} } }
        assert.is_true(ns.VaultPanel.ShowCellTooltip(cell))
        assert.is_nil(GameTooltip.stub.Text():find("Lootpath", 1, true))
        world.inCombat = false
    end)
end)
