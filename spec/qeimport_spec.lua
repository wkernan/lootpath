-- spec/qeimport_spec.lua (M2-1, WKE-518)
-- The parser is exercised over real JSON text, not over a Lua table pretending
-- to be one, so the decoder is in the loop every time.
--
-- SAMPLE is hand-built (see spec/fixtures/qe/README.md): it mirrors QE Live's
-- exporter field for field but no number in it came from QE Live. The last
-- block reads the genuine export WKE-519 committed.
local H = require("spec.helpers.addon")
-- M3-13 (WKE-548) joins an export to a replayed inventory snapshot.
local R = require("spec.helpers.replay")

local SAMPLE_PATH = "spec/fixtures/qe/sample-handbuilt-v1.json"

-- The sign conventions, pinned here as named constants so a flip in the module
-- is a red test and not a silently inverted recommendation. Both are read from
-- QE Live's source (branch `dev`, 2026-09-06):
--   TopGearJSONExport.ts:42-43 - "scoreDifference: number (% - positive means
--   alt is worse), rawDifference: number (HPS - negative means alt is worse)"
--   TopGearEngineShared.js:50-51, with `itemSet` the alternative and `primeSet`
--   the top set:
--     scoreDifference = (primeSet.hardScore - itemSet.hardScore) / primeSet.hardScore * 100
--     rawDifference   =  itemSet.hardScore - primeSet.hardScore
local ALT_IS_WORSE_SCORE_PERCENT_SIGN = 1
local ALT_IS_WORSE_HPS_DIFFERENCE_SIGN = -1

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

-- The sample with one JSON value replaced, for the refusal cases: the text
-- stays real JSON so only the field under test differs.
local function sampleWith(pattern, replacement)
    local text = readFile(SAMPLE_PATH)
    local swapped, count = text:gsub(pattern, replacement, 1)
    assert(count == 1, "sample edit did not apply: " .. pattern)
    return swapped
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

describe("QEImport.Parse refusals", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("refuses nothing at all", function()
        for _, empty in ipairs({ "", "   \n\t ", 42, true }) do
            local result = ns.QEImport.Parse(empty)
            assert.is_false(result.ok)
            assert.matches("nothing to import", result.reason, 1, true)
        end
        local nothing = ns.QEImport.Parse(nil)
        assert.is_false(nothing.ok)
        assert.matches("nothing to import", nothing.reason, 1, true)
    end)

    it("refuses text that is not JSON, quoting the decoder without its file and line", function()
        local result = ns.QEImport.Parse("this is the SimC export, not the QE one")
        assert.is_false(result.ok)
        assert.matches("that is not JSON", result.reason, 1, true)
        assert.is_nil(result.reason:find("json.lua:", 1, true))
        assert.is_nil(result.verdict)
    end)

    it("refuses JSON that is not an object", function()
        local result = ns.QEImport.Parse("1234")
        assert.is_false(result.ok)
        assert.matches("not a QE Live export", result.reason, 1, true)
    end)

    it("refuses another tool's JSON by schema, naming what it saw", function()
        local result = ns.QEImport.Parse('{"schema":"raidbots-droptimizer","version":1}')
        assert.is_false(result.ok)
        assert.matches("raidbots%-droptimizer", result.reason)
        assert.matches("qe%-live%-droptimizer", result.reason)
    end)

    it("refuses an object with no schema at all", function()
        local result = ns.QEImport.Parse("{}")
        assert.is_false(result.ok)
        assert.matches("schema is missing", result.reason, 1, true)
    end)

    it("refuses a future version, naming the version it saw and the one it reads", function()
        local result = ns.QEImport.Parse(sampleWith('"version": 1', '"version": 2'))
        assert.is_false(result.ok)
        assert.matches("version 2", result.reason, 1, true)
        assert.matches("reads version 1", result.reason, 1, true)
    end)

    it("refuses a version that is not a number, rather than coercing it", function()
        local result = ns.QEImport.Parse(sampleWith('"version": 1', '"version": "1"'))
        assert.is_false(result.ok)
        assert.matches('version "1"', result.reason, 1, true)
    end)

    it("refuses an export with no topSet", function()
        local result = ns.QEImport.Parse('{"schema":"qe-live-droptimizer","version":1}')
        assert.is_false(result.ok)
        assert.matches("no topSet", result.reason, 1, true)
    end)

    it("refuses a Classic export", function()
        local result = ns.QEImport.Parse(sampleWith('"gameType": "Retail"', '"gameType": "Classic"'))
        assert.is_false(result.ok)
        assert.matches('gameType is "Classic"', result.reason, 1, true)
        assert.matches("Retail exports only", result.reason, 1, true)
    end)

    it("refuses an export with no player block, so gameType cannot be assumed", function()
        local result = ns.QEImport.Parse('{"schema":"qe-live-droptimizer","version":1,"topSet":{"score":1,"items":[]}}')
        assert.is_false(result.ok)
        assert.matches("gameType is missing", result.reason, 1, true)
    end)

    it("clips a long string in a refusal rather than echoing the paste back", function()
        local blob = string.rep("x", 500)
        local result = ns.QEImport.Parse('{"schema":"' .. blob .. '"}')
        assert.is_false(result.ok)
        assert.is_true(#result.reason < 160)
        assert.matches("...", result.reason, 1, true)
    end)
end)

describe("QEImport.Parse over the hand-built v1 sample", function()
    local ns, world, result

    before_each(function()
        ns, world = H.load()
        result = ns.QEImport.Parse(readFile(SAMPLE_PATH))
        assert.is_true(result.ok, result.reason)
    end)

    after_each(function()
        H.unload()
    end)

    it("carries the export's own header fields through unchanged", function()
        local v = result.verdict
        assert.equal("2026-09-06T18:22:41.113Z", v.exportedAt)
        assert.equal("Restoration Druid", v.spec)
        assert.equal("Mythic+", v.contentType)
        assert.equal("handbuilt-0001", v.reportId)
        assert.equal("Hotornot", v.player.name)
        assert.equal("US", v.player.region)
        assert.equal("Retail", v.player.gameType)
    end)

    it("carries QE Live's score and stats without touching them", function()
        assert.equal(132456, result.verdict.topSet.score)
        assert.same({
            intellect = 42110,
            haste = 8123,
            crit = 5401,
            mastery = 9902,
            versatility = 3115,
            leech = 480,
        }, result.verdict.topSet.stats)
    end)

    it("keys every topSet item by ns.ItemKey and keeps the export's order", function()
        local topSet = result.verdict.topSet
        assert.equal(7, #topSet.order)
        assert.equal(7, countKeys(topSet.items))
        -- Computed here from the raw fields, independently of the module.
        local headKey = ns.ItemKey(271528, { 6652, 13439, 13696, 12838, 13692, 13698, 1561 })
        assert.equal("271528:1561:6652:12838:13439:13692:13696:13698", headKey)
        assert.equal(headKey, topSet.order[1])
        assert.equal("Head", topSet.items[headKey].slot)
        assert.equal(308, topSet.items[headKey].level)
        assert.equal(0, result.verdict.skippedItems)
    end)

    it("sorts bonus IDs on the item the way Inventory records carry them", function()
        local headKey = ns.ItemKey(271528, { 6652, 13439, 13696, 12838, 13692, 13698, 1561 })
        assert.same({ 1561, 6652, 12838, 13439, 13692, 13696, 13698 }, result.verdict.topSet.items[headKey].bonusIDs)
    end)

    it("keeps two copies of an itemID apart when their bonus IDs differ", function()
        local items = result.verdict.topSet.items
        local upgraded = ns.ItemKey(268221, { 10390, 6652 })
        local plain = ns.ItemKey(268221, { 10390 })
        assert.not_equal(upgraded, plain)
        assert.equal(311, items[upgraded].level)
        assert.equal(304, items[plain].level)
        assert.equal("Leech", items[plain].tertiary)
        assert.is_nil(items[upgraded].tertiary) -- "" is carried as absent
    end)

    it("carries gems, enchant and setId as the exporter emits them", function()
        local neck = result.verdict.topSet.items[ns.ItemKey(271531, { 10390, 12040 })]
        assert.same({ 213743, 213743 }, neck.gems)
        assert.is_nil(neck.enchant)
        assert.equal(0, neck.setId)
        local chest = result.verdict.topSet.items[ns.ItemKey(271525, { 13692, 1561, 6652 })]
        assert.equal("Crystalline Radiance", chest.enchant)
        assert.equal(1834, chest.setId)
    end)

    it("reads every differential as an alternative that is worse, in both signs", function()
        local alternatives = result.verdict.alternatives
        assert.equal(2, #alternatives)
        for _, alternative in ipairs(alternatives) do
            assert.is_true(alternative.scorePercent * ALT_IS_WORSE_SCORE_PERCENT_SIGN > 0)
            assert.is_true(alternative.hpsDifference * ALT_IS_WORSE_HPS_DIFFERENCE_SIGN > 0)
            assert.is_false(ns.QEImport.AlternativeIsBetter(alternative))
        end
        assert.equal(0.4194, alternatives[1].scorePercent)
        assert.equal(-557, alternatives[1].hpsDifference)
        assert.same({ 213743 }, alternatives[1].gems)
    end)

    it("carries only the items that differ, as a list, in the export's order", function()
        local second = result.verdict.alternatives[2].items
        assert.equal(2, #second)
        assert.equal("Trinket", second[1].slot)
        assert.equal("Head", second[2].slot)
        assert.equal(ns.ItemKey(268261, { 10390, 13692 }), second[1].key)
    end)

    it("surfaces vault items from the top set and from alternatives alike", function()
        local vault = result.verdict.vault
        local chosen = ns.ItemKey(271525, { 13692, 1561, 6652 }) -- topSet, isVault
        local rejected = ns.ItemKey(268261, { 10390, 13692 }) -- only in a differential, isVault
        assert.equal(2, countKeys(vault))
        assert.equal("Chest", vault[chosen].slot)
        assert.equal("Trinket", vault[rejected].slot)
        assert.is_true(vault[chosen].isVault)
        -- The rejected option is not in the top set: that is the point of it.
        assert.is_nil(result.verdict.topSet.items[rejected])
    end)

    it("warns, without refusing, when the export is for another character", function()
        assert.equal("Tester", world.playerName)
        assert.equal(1, #result.warnings)
        assert.matches("this export is for Hotornot", result.warnings[1], 1, true)
        assert.matches("you are playing Tester", result.warnings[1], 1, true)
    end)

    it("is silent when the export is for the logged-in character, whatever the case", function()
        world.playerName = "HOTORNOT"
        local same = ns.QEImport.Parse(readFile(SAMPLE_PATH))
        assert.is_true(same.ok)
        assert.same({}, same.warnings)
    end)
end)

describe("QEImport.Parse over the genuine Dungeon export with comparison items", function()
    -- qe-droptimizer-Hotornot-cjyztichdhze.json: the fork, 2026-09-07 01:01 UTC,
    -- content toggle "Dungeon", bag and bank items clicked on the gear screen,
    -- no vault rewards generated yet. Every number here was read from the file.
    local DUNGEON_PATH = "spec/fixtures/qe/qe-droptimizer-Hotornot-cjyztichdhze.json"
    local ns, result

    before_each(function()
        ns = H.load()
        result = ns.QEImport.Parse(readFile(DUNGEON_PATH))
        assert.is_true(result.ok, result.reason)
    end)

    after_each(function()
        H.unload()
    end)

    it("names the content type QE Live actually emits for Mythic+", function()
        assert.equal("Dungeon", result.verdict.contentType)
        assert.equal("cjyztichdhze", result.verdict.reportId)
        assert.equal("2026-09-07T01:01:35.474Z", result.verdict.exportedAt)
        assert.equal(5460.909, result.verdict.topSet.score)
        assert.equal(15, #result.verdict.topSet.order)
    end)

    it("reads twelve real differentials, every one an alternative that is worse", function()
        local alternatives = result.verdict.alternatives
        assert.equal(12, #alternatives)
        for _, alternative in ipairs(alternatives) do
            assert.is_true(alternative.scorePercent * ALT_IS_WORSE_SCORE_PERCENT_SIGN >= 0)
            assert.is_true(alternative.hpsDifference * ALT_IS_WORSE_HPS_DIFFERENCE_SIGN >= 0)
            assert.is_false(ns.QEImport.AlternativeIsBetter(alternative))
        end
        -- The exporter really does emit a zero-delta alternative.
        assert.equal(0, alternatives[1].scorePercent)
        assert.equal(0, alternatives[1].hpsDifference)
        assert.equal(1, #alternatives[1].items)
        assert.equal("Waist", alternatives[1].items[1].slot)
        assert.equal(277781, alternatives[1].items[1].itemID)
        assert.equal(0.3296154541304388, alternatives[2].scorePercent)
        assert.equal(-1194, alternatives[2].hpsDifference)
    end)

    it("carries a two-item alternative as a list in the export's order", function()
        local third = result.verdict.alternatives[3].items
        assert.equal(2, #third)
        assert.equal("Back", third[1].slot)
        assert.equal(275525, third[1].itemID)
        assert.equal("Waist", third[2].slot)
    end)

    it("has no vault option before the weekly reset has generated rewards", function()
        assert.equal(0, countKeys(result.verdict.vault))
    end)
end)

describe("QEImport.Parse over the companion's export with a vault option in the top set", function()
    -- qe-droptimizer-Hotornot-uliwcyoomcub.json: written by the companion on
    -- 2026-09-08 from the after-reset captures, contentType Dungeon. The vault
    -- offered Lightgrasp Worldroot (251935, bonus IDs 6652/12841); QE Live put
    -- it in the top set. Every value here was read from the file.
    local VAULT_PATH = "spec/fixtures/qe/qe-droptimizer-Hotornot-uliwcyoomcub.json"
    local ns, result

    before_each(function()
        ns = H.load()
        result = ns.QEImport.Parse(readFile(VAULT_PATH))
        assert.is_true(result.ok, result.reason)
    end)

    after_each(function()
        H.unload()
    end)

    it("surfaces the vault option QE Live chose, keyed the way the client's own link keys it", function()
        local v = result.verdict
        assert.equal("Dungeon", v.contentType)
        assert.equal("2026-09-08T17:45:38.291Z", v.exportedAt)
        assert.equal(5647.977, v.topSet.score)
        assert.equal(15, #v.topSet.order)
        assert.equal(12, #v.alternatives)
        local key = ns.ItemKey(251935, { 6652, 12841 })
        assert.equal("251935:6652:12841", key)
        assert.equal(1, countKeys(v.vault))
        local option = v.vault[key]
        assert.is_not_nil(option)
        assert.is_true(option.isVault)
        assert.equal("2H Weapon", option.slot)
        -- QE Live's level for the option, not the client's 305 (ARCHITECTURE.md 9, 2026-09-08).
        assert.equal(321, option.level)
        assert.equal(option, v.topSet.items[key])
    end)

    it("marks nothing else in the top set as a vault option", function()
        local count = 0
        for _, key in ipairs(result.verdict.topSet.order) do
            if result.verdict.topSet.items[key].isVault then
                count = count + 1
            end
        end
        assert.equal(1, count)
    end)
end)

describe("QEImport item identity and robustness", function()
    local ns

    local function envelope(items)
        return '{"schema":"qe-live-droptimizer","version":1,"exportedAt":"2026-09-06T00:00:00.000Z",'
            .. '"player":{"name":"Tester","realm":"TestRealm","region":"US","spec":"Restoration Druid",'
            .. '"gameType":"Retail"},"contentType":"Mythic+","reportId":"x",'
            .. '"topSet":{"score":1,"stats":{},"items":['
            .. items
            .. ']},"differentials":[]}'
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("gives reordered bonus IDs one key, so the same item imports the same way twice", function()
        local a = ns.QEImport.Parse(envelope('{"slot":"Head","id":271528,"bonusIDs":[6652,1561,13692],"level":308}'))
        local b = ns.QEImport.Parse(envelope('{"slot":"Head","id":271528,"bonusIDs":[13692,6652,1561],"level":308}'))
        assert.is_true(a.ok)
        assert.is_true(b.ok)
        assert.same(a.verdict.topSet.order, b.verdict.topSet.order)
        assert.equal("271528:1561:6652:13692", a.verdict.topSet.order[1])
    end)

    it("counts a matched pair rather than collapsing it to one item", function()
        local ring = '{"slot":"Finger","id":268221,"bonusIDs":[10390],"level":304}'
        local parsed = ns.QEImport.Parse(envelope(ring .. "," .. ring))
        assert.is_true(parsed.ok)
        local key = ns.ItemKey(268221, { 10390 })
        assert.equal(2, #parsed.verdict.topSet.order)
        assert.equal(key, parsed.verdict.topSet.order[2])
        assert.equal(2, parsed.verdict.topSet.items[key].count)
    end)

    it("skips an item with no usable itemID, warns, and keeps the rest", function()
        local parsed = ns.QEImport.Parse(
            envelope(
                '{"slot":"Head","id":271528,"bonusIDs":[6652],"level":308},'
                    .. '{"slot":"Neck","id":0,"bonusIDs":[],"level":300},'
                    .. '{"slot":"Back","id":268300,"bonusIDs":["oops"],"level":300}'
            )
        )
        assert.is_true(parsed.ok)
        assert.equal(1, #parsed.verdict.topSet.order)
        assert.equal(2, parsed.verdict.skippedItems)
        assert.matches("2 item(s) carried no usable itemID", parsed.warnings[1], 1, true)
    end)

    it("warns when the topSet lists no items", function()
        local parsed = ns.QEImport.Parse(envelope(""))
        assert.is_true(parsed.ok)
        assert.matches("no items", parsed.warnings[1], 1, true)
    end)

    it("reads an alternative that beats the top set as better, if QE Live ever emits one", function()
        -- Real differentials are alternatives to the winning set, so they are
        -- worse; this pins the other direction of the same convention.
        assert.is_true(ns.QEImport.AlternativeIsBetter({ scorePercent = -0.5, hpsDifference = 700 }))
        assert.is_false(ns.QEImport.AlternativeIsBetter({ scorePercent = 0 }))
        assert.is_nil(ns.QEImport.AlternativeIsBetter({}))
        assert.is_nil(ns.QEImport.AlternativeIsBetter("not a table"))
    end)
end)

describe("QEImport storage", function()
    local ns

    after_each(function()
        H.unload()
    end)

    it("stores the last verdict under db.char.qeImport with its exportedAt", function()
        ns = H.load()
        local imported = ns.QEImport.Import(readFile(SAMPLE_PATH))
        assert.is_true(imported.ok, imported.reason)
        local stored = ns.db.char.qeImport
        assert.equal(imported.verdict, stored)
        assert.equal("2026-09-06T18:22:41.113Z", stored.exportedAt)
        assert.is_number(stored.importedAt)
        assert.equal(stored, ns.QEImport.Current())
    end)

    it("replaces the previous import rather than accumulating verdicts", function()
        ns = H.load()
        ns.QEImport.Import(readFile(SAMPLE_PATH))
        local second = ns.QEImport.Import(sampleWith('"reportId": "handbuilt%-0001"', '"reportId": "handbuilt-0002"'))
        assert.is_true(second.ok, second.reason)
        assert.equal("handbuilt-0002", ns.db.char.qeImport.reportId)
    end)

    it("refuses to store before the database exists, and stores nothing", function()
        ns = H.load({ loaded = false })
        assert.is_nil(ns.db)
        local imported = ns.QEImport.Import(readFile(SAMPLE_PATH))
        assert.is_false(imported.ok)
        assert.matches("database not loaded yet", imported.reason, 1, true)
        assert.is_nil(ns.QEImport.Current())
    end)

    it("leaves a refused paste out of the database entirely", function()
        ns = H.load()
        ns.QEImport.Import(readFile(SAMPLE_PATH))
        local refused = ns.QEImport.Import("not json")
        assert.is_false(refused.ok)
        assert.equal("handbuilt-0001", ns.db.char.qeImport.reportId)
    end)

    it("tells /lootpath status how old the verdict is", function()
        local world
        ns, world = H.load()
        ns.QEImport.Import(readFile(SAMPLE_PATH))
        ns.HandleSlash("status")
        assert.matches("QE Live import: exported 2026-09-06T18:22:41.113Z", world.output(), 1, true)
    end)
end)

describe("QEImport.Parse over a genuine QE Live export", function()
    -- qe-droptimizer-Hotornot-cxeiassqdyvz.json: produced by QE Live's own
    -- engine on the owner's fork, 2026-09-06, Restoration, contentType Raid,
    -- with no extra items selected on the gear screen (see the fixture README).
    -- Every number asserted here was read from that file, none from the module.
    local REAL_PATH = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"
    local ns, result

    before_each(function()
        ns = H.load()
        result = ns.QEImport.Parse(readFile(REAL_PATH))
        assert.is_true(result.ok, result.reason)
    end)

    after_each(function()
        H.unload()
    end)

    it("passes every refusal gate: schema, numeric version 1, topSet, Retail", function()
        local v = result.verdict
        assert.equal("2026-09-06T21:14:24.465Z", v.exportedAt)
        assert.equal("Restoration Druid", v.spec)
        assert.equal("Raid", v.contentType)
        assert.equal("cxeiassqdyvz", v.reportId)
        assert.equal("Hotornot", v.player.name)
        assert.equal("Arthas", v.player.realm)
        assert.equal("US", v.player.region)
        assert.equal("Retail", v.player.gameType)
    end)

    it("carries the real score and the full stats block, extra keys included", function()
        local topSet = result.verdict.topSet
        assert.equal(5452.55, topSet.score)
        assert.equal(12, countKeys(topSet.stats))
        assert.equal(763, topSet.stats.crit)
        assert.equal(811, topSet.stats.mastery)
        assert.equal(550, topSet.stats.versatility)
        assert.equal(249, topSet.stats.leech)
        assert.equal(2780.5365, topSet.stats.intellect)
        assert.equal(1895.0843266929514, topSet.stats.haste)
        assert.equal(2611.4102495719035, topSet.stats.hps)
        assert.equal(1.04, topSet.stats.manaPerc)
    end)

    it("keys the fifteen equipped items and keeps the export's slot order", function()
        local topSet = result.verdict.topSet
        assert.equal(15, #topSet.order)
        assert.equal(15, countKeys(topSet.items))
        assert.equal(0, result.verdict.skippedItems)
        -- The head is the same item the 2026-09-05 inventory transcript carries.
        local headKey = ns.ItemKey(271528, { 6652, 13439, 13696, 12838, 13692, 13698, 1561 })
        assert.equal("271528:1561:6652:12838:13439:13692:13696:13698", headKey)
        assert.equal(headKey, topSet.order[1])
        assert.equal("Head", topSet.items[headKey].slot)
        assert.equal(308, topSet.items[headKey].level)
        assert.equal(2057, topSet.items[headKey].setId)
        assert.equal("Empowered Hex of Leeching", topSet.items[headKey].enchant)
        assert.equal("2H Weapon", topSet.items[topSet.order[15]].slot)
        assert.equal(302, topSet.items[topSet.order[15]].level)
    end)

    it("keeps two rings with different itemIDs as two Finger entries", function()
        local items = result.verdict.topSet.items
        local signet = ns.ItemKey(259912, { 6652, 13668, 12790 })
        local band = ns.ItemKey(151311, { 13440, 6652, 13668, 12699, 12790 })
        assert.equal("Finger", items[signet].slot)
        assert.equal("Finger", items[band].slot)
        assert.same({ 240892 }, items[signet].gems)
        assert.equal(1331, items[band].setId)
        assert.equal(1, items[signet].count)
    end)

    it("reads an export made with no comparison items as a bare top set", function()
        assert.same({}, result.verdict.alternatives)
        assert.equal(0, countKeys(result.verdict.vault))
        for _, key in ipairs(result.verdict.topSet.order) do
            assert.is_false(result.verdict.topSet.items[key].isVault)
        end
    end)

    it("stores it like any other verdict", function()
        local imported = ns.QEImport.Import(readFile(REAL_PATH))
        assert.is_true(imported.ok, imported.reason)
        assert.equal("cxeiassqdyvz", ns.db.char.qeImport.reportId)
        assert.equal("2026-09-06T21:14:24.465Z", ns.QEImport.Current().exportedAt)
    end)
end)

-- ---------------------------------------------------------------------------
-- C-6 (WKE-540): the named scenarios, and QE Live's own catalyzed copy.
--
-- Every figure below is read from the six exports of the 2026-09-09 01:15
-- companion run, committed unedited (spec/fixtures/qe/README.md): the same
-- profile asked three questions through QE Live's three import checkboxes.

local SCENARIO_EXPORTS = {
    asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
    catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
    maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
}

-- The vault options of the 2026-09-08 12:45 capture, as the client's own links
-- carry them (ARCHITECTURE.md 9).
local SPAULDERS = { itemID = 251146, slot = "Shoulder", bonusIDs = { 6652, 12699, 12842, 13440, 13662 } }
local WEAPON = { itemID = 251935, slot = "2H Weapon", bonusIDs = { 6652, 12841 } }
local NECK = { itemID = 251234, slot = "Neck", bonusIDs = { 6652, 12699, 12842, 13440, 13668 } }

describe("QEImport and the named scenarios", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    local function verdictOf(scenario)
        local parsed = ns.QEImport.Parse(readFile(SCENARIO_EXPORTS[scenario]))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = scenario
        return parsed.verdict
    end

    it("reads a missing scenario as asOffered and an unknown one as its own shelf", function()
        assert.same({ "asOffered", "catalyzed", "thisWeek", "maxed" }, ns.QEImport.SCENARIOS)
        assert.equal("asOffered", ns.QEImport.DEFAULT_SCENARIO)
        assert.equal("asOffered", ns.QEImport.ScenarioKey({}))
        assert.equal("asOffered", ns.QEImport.ScenarioKey(nil))
        assert.equal("catalyzed", ns.QEImport.ScenarioKey({ scenario = "catalyzed" }))
        -- Not "asOffered": a name this build does not know is no evidence that
        -- the answer is the one Equip Now reads.
        assert.equal("unknown", ns.QEImport.ScenarioKey({ scenario = "catalysed" }))
        assert.equal("unknown", ns.QEImport.ScenarioKey({ scenario = 7 }))
    end)

    it("files three answers for one content type on three shelves", function()
        for _, scenario in ipairs({ "asOffered", "catalyzed", "maxed" }) do
            local stored = ns.QEImport.Store(verdictOf(scenario))
            assert.is_true(stored.ok, stored.reason)
        end
        local shelves = ns.QEImport.Scenarios("Dungeon")
        assert.equal(3, #shelves)
        assert.same(
            { "asOffered", "catalyzed", "maxed" },
            { shelves[1].scenario, shelves[2].scenario, shelves[3].scenario }
        )
        -- QE Live's own scores, in the order the scenarios are asked.
        assert.equal(5544.654, shelves[1].verdict.topSet.score)
        assert.equal(5724.919, shelves[2].verdict.topSet.score)
        assert.equal(5853.843, shelves[3].verdict.topSet.score)
    end)

    -- Deliverable 2 of the issue: Equip Now and the Upgrade Map never change
    -- meaning. They read `qeImports` / `qeImport`, and only the `asOffered`
    -- document is ever filed there.
    it("keeps qeImport and qeImports answering asOffered whatever else is stored", function()
        ns.QEImport.Store(verdictOf("asOffered"))
        ns.QEImport.Store(verdictOf("catalyzed"))
        ns.QEImport.Store(verdictOf("maxed"))
        assert.equal(5544.654, ns.QEImport.ForContentType("Dungeon").topSet.score)
        assert.equal(5544.654, ns.QEImport.Current().topSet.score)
        assert.equal("asOffered", ns.QEImport.Current().scenario)
    end)

    it("asks what a verdict replaces per scenario, so three answers are not one repeat", function()
        local offered = verdictOf("asOffered")
        ns.QEImport.Store(offered)
        assert.equal(offered, ns.QEImport.Existing(verdictOf("asOffered")))
        assert.is_nil(ns.QEImport.Existing(verdictOf("catalyzed")))
        ns.QEImport.Store(verdictOf("catalyzed"))
        assert.equal(5724.919, ns.QEImport.Existing(verdictOf("catalyzed")).topSet.score)
    end)

    -- A character upgraded from a pre-C-6 build has a verdict under the content
    -- type alone. It is what it always was - a document that named no scenario -
    -- so it reads as asOffered and an asOffered import still replaces it.
    it("reads a pre-C-6 stored verdict as the asOffered answer", function()
        local legacy = verdictOf("asOffered")
        legacy.scenario = nil
        ns.QEImport.Store(legacy)
        ns.db.char.qeImportsByScenario = {}
        local shelves = ns.QEImport.Scenarios("Dungeon")
        assert.equal(1, #shelves)
        assert.equal("asOffered", shelves[1].scenario)
        assert.equal(legacy, shelves[1].verdict)
        assert.equal(legacy, ns.QEImport.Existing(verdictOf("asOffered")))
    end)

    it("answers nothing for a content type it has never seen", function()
        assert.same({}, ns.QEImport.Scenarios("Dungeon"))
        assert.same({}, ns.QEImport.Scenarios(nil))
        assert.is_nil(ns.QEImport.ForContentTypeAndScenario("Dungeon", "maxed"))
    end)
end)

-- QE Live's `autoCatalyze` does not change an item: SimCImportEngine.ts keeps
-- the original and ADDS a clone, and Item.convertToTier gives the clone the
-- tier piece's item ID and set ID while keeping the slot, the level, the bonus
-- IDs and the vault flag. Measured in the committed catalyzed export: the
-- vault's Scavenger's Spaulders 251146 appear as 271526 at 308, setId 2057,
-- isVault, carrying the Spaulders' own bonus IDs - IN THE TOP SET.
describe("QEImport.CatalyzedCoverage over QE Live's own catalyzed run", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    local function verdictOf(scenario)
        local parsed = ns.QEImport.Parse(readFile(SCENARIO_EXPORTS[scenario]))
        assert.is_true(parsed.ok, parsed.reason)
        return parsed.verdict
    end

    it("finds his tier copy of the vault shoulders, which the exact key never could", function()
        local catalyzed = verdictOf("catalyzed")
        local key = ns.ItemKey(SPAULDERS.itemID, SPAULDERS.bonusIDs)
        assert.is_nil(ns.QEImport.Coverage(catalyzed, key), "the un-catalyzed shoulders are not in his answer")
        local found = ns.QEImport.CatalyzedCoverage(catalyzed, SPAULDERS)
        assert.is_not_nil(found)
        assert.equal("topSet", found.where)
        assert.equal(271526, found.item.itemID)
        assert.equal(308, found.item.level)
        assert.equal(2057, found.item.setId)
        assert.is_true(found.item.isVault)
        assert.equal(251146, found.catalyzedFrom)
        -- The bonus IDs are the option's own, which is exactly what makes the
        -- clone recognisable.
        assert.same(SPAULDERS.bonusIDs, found.item.bonusIDs)
    end)

    it("carries his delta when the copy is only an alternative", function()
        local found = ns.QEImport.CatalyzedCoverage(verdictOf("maxed"), SPAULDERS)
        assert.is_not_nil(found)
        assert.equal("alternative", found.where)
        assert.equal(271526, found.item.itemID)
        assert.equal(321, found.item.level)
        assert.is_false(found.isBetter)
    end)

    it("finds nothing when his run made no copy, which is his canBeCatalyzed saying no", function()
        -- Catalyze was off in this run altogether.
        assert.is_nil(ns.QEImport.CatalyzedCoverage(verdictOf("asOffered"), SPAULDERS))
        -- Catalyze was ON here, and he still made no copy of a weapon or a neck:
        -- his canBeCatalyzed only accepts Head/Chest/Shoulder/Legs/Hands.
        local catalyzed = verdictOf("catalyzed")
        assert.is_nil(ns.QEImport.CatalyzedCoverage(catalyzed, WEAPON))
        assert.is_nil(ns.QEImport.CatalyzedCoverage(catalyzed, NECK))
    end)

    it("never matches on the slot alone, and never on an item with no bonus IDs", function()
        local catalyzed = verdictOf("catalyzed")
        -- The right slot and the wrong bonus IDs is a different item, however
        -- close it looks.
        assert.is_nil(
            ns.QEImport.CatalyzedCoverage(catalyzed, { itemID = 251146, slot = "Shoulder", bonusIDs = { 6652, 12841 } })
        )
        assert.is_nil(ns.QEImport.CatalyzedCoverage(catalyzed, { itemID = 251146, slot = "Shoulder", bonusIDs = {} }))
        assert.is_nil(
            ns.QEImport.CatalyzedCoverage(catalyzed, { itemID = 251146, slot = "Head", bonusIDs = SPAULDERS.bonusIDs })
        )
        -- And never the option itself, whatever else matches.
        assert.is_nil(
            ns.QEImport.CatalyzedCoverage(
                catalyzed,
                { itemID = 271526, slot = "Shoulder", bonusIDs = SPAULDERS.bonusIDs }
            )
        )
    end)

    -- His catalyzed run clones the WORN shoulder too (271526 at 295, from the
    -- 250022 the character is wearing), and that clone is not `isVault`. This
    -- function answers about vault OPTIONS, so the flag is what stops a line
    -- about gear the vault is not offering appearing on the Vault tab.
    it("never answers with the copy of an item the vault is not offering", function()
        local worn = { itemID = 250022, slot = "Shoulder", bonusIDs = { 6652, 12830, 13662 } }
        local catalyzed = verdictOf("catalyzed")
        -- The clone really is in his answer, at the worn item's own bonus IDs.
        local clone = catalyzed.topSet.items[ns.ItemKey(271526, worn.bonusIDs)]
        if not clone then
            for _, alternative in ipairs(catalyzed.alternatives) do
                for _, item in ipairs(alternative.items) do
                    if item.itemID == 271526 and item.level == 295 then
                        clone = item
                    end
                end
            end
        end
        assert.is_not_nil(clone, "his catalyzed run cloned the worn shoulder too")
        assert.is_false(clone.isVault)
        assert.is_nil(ns.QEImport.CatalyzedCoverage(catalyzed, worn))
    end)

    -- An item with no bonus IDs is not identified by them: two unrelated plain
    -- items would match each other. The committed exports carry none, so the
    -- case is built by hand, field for field from QE Live's own exporter.
    it("never matches two items that share nothing but an empty bonus ID list", function()
        local text = [==[{
            "schema": "qe-live-droptimizer", "version": 1,
            "exportedAt": "2026-09-09T01:00:00Z",
            "player": { "name": "Hotornot", "realm": "Arthas", "region": "us",
                        "spec": "Restoration Druid", "gameType": "Retail" },
            "contentType": "Dungeon", "reportId": "handbuilt",
            "topSet": { "score": 1, "stats": {}, "items": [
                { "slot": "Shoulder", "id": 900001, "level": 300, "bonusIDs": [], "gems": [],
                  "enchant": "", "tertiary": "", "setId": 0, "isVault": true,
                  "isExclusive": false, "source": {} }
            ] },
            "differentials": []
        }]==]
        local parsed = ns.QEImport.Parse(text)
        assert.is_true(parsed.ok, parsed.reason)
        assert.is_nil(
            ns.QEImport.CatalyzedCoverage(parsed.verdict, { itemID = 900002, slot = "Shoulder", bonusIDs = {} })
        )
    end)

    it("refuses what it cannot read rather than guessing", function()
        assert.is_nil(ns.QEImport.CatalyzedCoverage(nil, SPAULDERS))
        assert.is_nil(ns.QEImport.CatalyzedCoverage(verdictOf("catalyzed"), nil))
        assert.is_nil(ns.QEImport.CatalyzedCoverage(verdictOf("catalyzed"), { itemID = nil, slot = "Shoulder" }))
        assert.is_nil(ns.QEImport.CatalyzedCoverage(verdictOf("catalyzed"), { itemID = 251146, slot = nil }))
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-13 (WKE-548): the fourth question, and the item it catalyzes out of the
-- owner's own bags.
--
-- Every figure below is read from `qe-droptimizer-Hotornot-hdaldwpeakpb.json` -
-- the `thisWeek` Dungeon document of the 2026-09-09 19:22 run, committed
-- unedited - joined to inventory snapshot 7 of the 2026-09-08 12:45 capture,
-- which is the capture that run's profile was built from.

local THIS_WEEK_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json"
local AFTER_RESET_CAPTURE = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
-- The snapshot the companion's profile of that run was built from: 15 equipped,
-- 32 in bags, 0 in the bank, 4 vault, 158 lines.
local PROFILE_SNAPSHOT = 7

describe("QEImport.CatalyzedOwned over the fourth question (WKE-548)", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, AFTER_RESET_CAPTURE))
    end)

    after_each(function()
        H.unload()
    end)

    local function thisWeek(boxes)
        local parsed = ns.QEImport.Parse(readFile(THIS_WEEK_EXPORT))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = "thisWeek"
        parsed.verdict.qeSettings = boxes or { autoUpgradeVault = true, autoUpgradeAll = false, autoCatalyze = true }
        return parsed.verdict
    end

    local function scan()
        local result = ns.Inventory.Scan()
        assert.is_true(result.ok, result.reason)
        return result
    end

    -- The measurement this whole issue exists for. His `thisWeek` top set takes
    -- the vault's weapon at 321 and catalyzes TWO pieces the owner already had:
    -- the Venom-Cursed Lynx's Spaulders sitting in a bag at 295, and the Hide of
    -- Pestilence at 302. Neither is a vault option; neither can be found by the
    -- exact key, because his clone carries the tier piece's item ID.
    it("names the owned items his best set catalyzed, in his own order", function()
        local found = ns.QEImport.CatalyzedOwned(thisWeek(), scan())
        assert.equal(2, #found)
        assert.equal("Shoulder", found[1].slot)
        assert.equal(271526, found[1].item.itemID)
        assert.equal(295, found[1].item.level)
        assert.equal(2057, found[1].item.setId)
        assert.equal(277782, found[1].owned.itemID)
        assert.equal("Venom-Cursed Lynx's Spaulders", found[1].owned.name)
        assert.equal(295, found[1].owned.itemLevel)
        assert.equal("Chest", found[2].slot)
        assert.equal(271531, found[2].item.itemID)
        assert.equal(251226, found[2].owned.itemID)
        assert.equal("Hide of Pestilence", found[2].owned.name)
        assert.equal(302, found[2].owned.itemLevel)
    end)

    -- The clone keeps the original's bonus IDs on a different item ID, which is
    -- the whole join. Read off both sides rather than restated.
    it("joins on the fields his convertToTier copied, not on the item ID", function()
        local found = ns.QEImport.CatalyzedOwned(thisWeek(), scan())
        assert.same({ 6652, 12830, 13662 }, found[1].item.bonusIDs)
        assert.same({ 6652, 12830, 13662 }, found[1].owned.bonusIDs)
        assert.are_not.equal(found[1].item.itemID, found[1].owned.itemID)
    end)

    -- The four tier pieces the owner WEARS are in the same top set with the same
    -- kind of set ID. They are passed over because their exact key is in the
    -- scan: there is nothing to catalyze into a piece already owned.
    it("passes over the tier pieces the owner already wears", function()
        local found = ns.QEImport.CatalyzedOwned(thisWeek(), scan())
        for _, entry in ipairs(found) do
            assert.are_not.equal(271528, entry.item.itemID)
            assert.are_not.equal(271527, entry.item.itemID)
            assert.are_not.equal(250025, entry.item.itemID)
        end
    end)

    -- A set ID in a run whose Catalyst box was OFF is a tier piece the character
    -- wears, not a clone. Read off the boxes the companion recorded, never
    -- inferred from the scenario's name.
    it("says nothing at all when the run did not ask QE Live to catalyze", function()
        local off = thisWeek({ autoUpgradeVault = true, autoUpgradeAll = false, autoCatalyze = false })
        assert.same({}, ns.QEImport.CatalyzedOwned(off, scan()))
        local silent = thisWeek()
        silent.qeSettings = nil
        assert.same({}, ns.QEImport.CatalyzedOwned(silent, scan()))
    end)

    -- With nothing scanned there is no owned item to have looked for, so there
    -- is no sentence to say - not even the "he did not say which" one.
    it("claims nothing when there is no scan to read", function()
        assert.same({}, ns.QEImport.CatalyzedOwned(thisWeek(), nil))
        assert.same({}, ns.QEImport.CatalyzedOwned(thisWeek(), { ok = false, reason = "combat" }))
        assert.same({}, ns.QEImport.CatalyzedOwned(thisWeek(), { records = {} }))
    end)

    -- His clone is in the set and nothing owned matches it: the entry still
    -- comes back, with no owned item on it, so the caller says he catalyzed
    -- something in that slot without naming what.
    it("reports a clone nothing owned matches, with no item named", function()
        local records = {}
        for _, record in ipairs(scan().records) do
            if record.itemID ~= 277782 and record.itemID ~= 251226 then
                records[#records + 1] = record
            end
        end
        local found = ns.QEImport.CatalyzedOwned(thisWeek(), { ok = true, records = records })
        assert.equal(2, #found)
        assert.is_nil(found[1].owned)
        assert.equal("Shoulder", found[1].slot)
        assert.is_nil(found[2].owned)
    end)

    it("refuses anything that is not a verdict", function()
        assert.same({}, ns.QEImport.CatalyzedOwned(nil, scan()))
        assert.same({}, ns.QEImport.CatalyzedOwned("thisWeek", scan()))
    end)
end)
