-- spec/qeimport_spec.lua (M2-1, WKE-518)
-- The parser is exercised over real JSON text, not over a Lua table pretending
-- to be one, so the decoder is in the loop every time.
--
-- SAMPLE is hand-built (see spec/fixtures/qe/README.md): it mirrors QE Live's
-- exporter field for field but no number in it came from QE Live. The test that
-- reads a genuine export is `pending` until WKE-519 commits one.
local H = require("spec.helpers.addon")

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

describe("QEImport over a genuine QE Live export", function()
    pending("reads the real Top Gear JSON committed by WKE-519 (M2-1b) - fixture not yet in the repo")
end)
