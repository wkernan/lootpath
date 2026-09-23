-- spec/ufimport_spec.lua (M3-6, WKE-535)
-- The Upgrade Finder parser over real JSON text, never over a Lua table
-- pretending to be one, so the decoder is in the loop every time.
--
-- SAMPLE is hand-built (see spec/fixtures/qe/README.md): it mirrors the fork's
-- exporter field for field but no number in it came from QE Live, and it exists
-- to cover what a real export does not - a NEGATIVE value, a drop at an item
-- level the journal never lists, and an unusable itemID. REAL is the genuine
-- Dungeon export S-1 produced through QE Live's own engine.
local H = require("spec.helpers.addon")

local SAMPLE_PATH = "spec/fixtures/qe/sample-upgradefinder-v1.json"
local REAL_DUNGEON = "spec/fixtures/qe/qe-upgradefinder-Hotornot-abxrrnezfilt.json"
local REAL_RAID = "spec/fixtures/qe/qe-upgradefinder-Hotornot-kqyktjywppzw.json"

-- The sign convention, pinned here independently of the module so a flip there
-- is a red test and not a silently inverted recommendation. Read from the
-- owner's fork (branch `lootpath/upgrade-finder-export`, 2026-09-07):
--   UpgradeFinderJSONExport.ts - "rawDiff and percDiff are (new - base), so
--   POSITIVE MEANS AN UPGRADE"
--   UpgradeFinderEngine.js:372-373, with `newScore` the score of the set that
--   includes the drop and `baseScore` the set without it:
--     rawDiff  = round(((newScore - baseScore) / baseScore) * baseHPS * modelDiff)
--     percDiff = round(((newScore - baseScore) / baseScore) * modelDiff * 100000) / 1000
-- It is the OPPOSITE of the Top Gear export's, which is why the two parsers are
-- two files.
local UPGRADE_IS_BETTER_PERCENT_SIGN = 1
local UPGRADE_IS_BETTER_HPS_GAIN_SIGN = 1

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

local function parsed(ns, path)
    local result = ns.UFImport.Parse(readFile(path or SAMPLE_PATH))
    assert(result.ok, result.reason)
    return result
end

describe("UFImport.Parse refusals", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("refuses nothing at all", function()
        for _, empty in ipairs({ "", "   \n\t ", 42, true }) do
            local result = ns.UFImport.Parse(empty)
            assert.is_false(result.ok)
            assert.matches("nothing to import", result.reason)
        end
    end)

    it("refuses text that is not JSON", function()
        local result = ns.UFImport.Parse("not json at all")
        assert.is_false(result.ok)
        assert.matches("that is not JSON", result.reason)
    end)

    it("refuses JSON that is not an object", function()
        local result = ns.UFImport.Parse("[1,2,3]")
        assert.is_false(result.ok)
        -- A JSON array decodes to a table, so it fails on the schema instead.
        assert.matches("schema is missing", result.reason)
    end)

    it("refuses a Top Gear export by schema, naming both", function()
        local result = ns.UFImport.Parse(readFile("spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"))
        assert.is_false(result.ok)
        assert.matches('"qe%-live%-droptimizer"', result.reason)
        assert.matches('"qe%-live%-upgradefinder"', result.reason)
    end)

    it("refuses a future version, naming the version it saw and the one it reads", function()
        local result = ns.UFImport.Parse(sampleWith('"version": 1', '"version": 2'))
        assert.is_false(result.ok)
        assert.matches("version 2", result.reason)
        assert.matches("version 1", result.reason)
    end)

    it("refuses a version that is not a number, rather than coercing it", function()
        local result = ns.UFImport.Parse(sampleWith('"version": 1', '"version": "1"'))
        assert.is_false(result.ok)
        assert.matches('version "1"', result.reason)
    end)

    it("refuses an export with no items list", function()
        local result = ns.UFImport.Parse(sampleWith('"items": %[', '"itemsRenamed": ['))
        assert.is_false(result.ok)
        assert.matches("no items", result.reason)
    end)

    it("refuses a Classic export", function()
        local result = ns.UFImport.Parse(sampleWith('"gameType": "Retail"', '"gameType": "Classic"'))
        assert.is_false(result.ok)
        assert.matches('gameType is "Classic"', result.reason)
        assert.matches("Retail", result.reason)
    end)

    it("refuses an export with no player block, so gameType cannot be assumed", function()
        local result = ns.UFImport.Parse(sampleWith('"player": {', '"playerRenamed": {'))
        assert.is_false(result.ok)
        assert.matches("gameType is missing", result.reason)
    end)
end)

describe("UFImport sign conventions", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("pins the two signs as the fork's source states them", function()
        assert.equal(UPGRADE_IS_BETTER_PERCENT_SIGN, ns.UFImport.UPGRADE_BETTER_PERCENT_SIGN)
        assert.equal(UPGRADE_IS_BETTER_HPS_GAIN_SIGN, ns.UFImport.UPGRADE_BETTER_HPS_GAIN_SIGN)
    end)

    it("means the opposite of the Top Gear export's, on the very same number", function()
        -- +2.5 in a Top Gear differential means the alternative is WORSE.
        assert.is_false(ns.QEImport.AlternativeIsBetter({ scorePercent = 2.5 }))
        -- +2.5 in an Upgrade Finder entry means the drop is BETTER.
        assert.is_true(ns.UFImport.IsUpgrade({ upgradePercent = 2.5 }))
        -- And the trap in one line: the two percent constants are the SAME
        -- number carrying opposite meanings, so a reader who grabbed the wrong
        -- one would get no type error and no failing arithmetic - only a
        -- backwards recommendation. That is why they live in two files.
        assert.equal(ns.QEImport.ALT_WORSE_SCORE_PERCENT_SIGN, ns.UFImport.UPGRADE_BETTER_PERCENT_SIGN)
        assert.equal(-ns.QEImport.ALT_WORSE_HPS_DIFFERENCE_SIGN, ns.UFImport.UPGRADE_BETTER_HPS_GAIN_SIGN)
    end)

    it("reads a positive percent as better, a negative one as worse, and zero as neither", function()
        assert.is_true(ns.UFImport.IsUpgrade({ upgradePercent = 4.5 }))
        assert.is_false(ns.UFImport.IsUpgrade({ upgradePercent = -1.25 }))
        assert.is_false(ns.UFImport.IsUpgrade({ upgradePercent = 0 }))
    end)

    it("answers nil rather than guessing when there is no percentage", function()
        assert.is_nil(ns.UFImport.IsUpgrade({}))
        assert.is_nil(ns.UFImport.IsUpgrade(nil))
        assert.is_nil(ns.UFImport.IsUpgrade("4.5"))
    end)
end)

describe("UFImport.Key", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("joins itemID and item level, which is what the stored report identifies a drop by", function()
        assert.equal("268205@324", ns.UFImport.Key(268205, 324))
        assert.equal("268205@324", ns.UFImport.Key("268205", "324"))
    end)

    it("refuses anything that is not a positive integer itemID with a numeric level", function()
        assert.is_nil(ns.UFImport.Key(0, 324))
        assert.is_nil(ns.UFImport.Key(-5, 324))
        assert.is_nil(ns.UFImport.Key(268205.5, 324))
        assert.is_nil(ns.UFImport.Key(268205, nil))
        assert.is_nil(ns.UFImport.Key(268205, "many"))
        assert.is_nil(ns.UFImport.Key(nil, nil))
    end)
end)

describe("UFImport.Parse over the hand-built v1 sample", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("carries the export's own header fields through unchanged", function()
        local verdict = parsed(ns).verdict
        assert.equal("qe-live-upgradefinder", verdict.schema)
        assert.equal(1, verdict.version)
        assert.equal("2026-09-07T12:00:00.000Z", verdict.exportedAt)
        assert.equal("handbuilt535", verdict.reportId)
        assert.equal("Dungeon", verdict.contentType)
        assert.equal("Restoration Druid", verdict.spec)
        assert.same({
            name = "Hotornot",
            realm = "Arthas",
            region = "US",
            spec = "Restoration Druid",
            gameType = "Retail",
        }, verdict.player)
        -- The report's own ufSettings, carried whole: they are what says which
        -- key level and raid difficulty the item levels below assume.
        assert.equal(7, verdict.settings.dungeon)
        assert.same({ 3 }, verdict.settings.raid)
    end)

    it("transports every number of one drop without touching it", function()
        local entry = parsed(ns).verdict.items["270162@318"]
        assert.equal(270162, entry.itemID)
        assert.equal(318, entry.level)
        assert.equal("Trinket", entry.slot)
        assert.equal(1320, entry.instanceID)
        assert.equal(2879, entry.encounterID)
        assert.equal("Raid", entry.dropLoc)
        assert.equal("drop", entry.dropType)
        assert.equal(3, entry.dropDifficulty)
        assert.equal(-1.25, entry.upgradePercent)
        assert.equal(-430, entry.hpsGain)
        assert.equal(-0.0125, entry.score)
    end)

    it("keeps a drop listed twice as one entry with both ways of getting it", function()
        local verdict = parsed(ns).verdict
        local entry = verdict.items["268205@324"]
        assert.equal(2, entry.count)
        assert.equal(2, #entry.sources)
        assert.equal("drop", entry.sources[1].dropType)
        assert.equal("bonus", entry.sources[2].dropType)
        -- One key in the order, not two: the map row joins on the key.
        local seen = 0
        for _, key in ipairs(verdict.order) do
            if key == "268205@324" then
                seen = seen + 1
            end
        end
        assert.equal(1, seen)
    end)

    it("reads a Delve drop's absent dropType and empty dropDifficulty as absent, never as zero", function()
        local entry = parsed(ns).verdict.items["272147@321"]
        assert.is_nil(entry.dropType)
        assert.is_nil(entry.dropDifficulty)
        assert.equal("Delves", entry.dropLoc)
        assert.equal(-98, entry.instanceID)
    end)

    it("skips a drop with no usable itemID, warns, and keeps the rest", function()
        local result = parsed(ns)
        assert.equal(1, result.verdict.skippedItems)
        assert.equal(5, countKeys(result.verdict.items))
        local warned = false
        for _, warning in ipairs(result.warnings) do
            if warning:match("carried no usable itemID") then
                warned = true
            end
        end
        assert.is_true(warned)
    end)

    it("warns, without refusing, when the export is for another character", function()
        local result = parsed(ns)
        local warned = false
        for _, warning in ipairs(result.warnings) do
            if warning:match("this export is for Hotornot, and you are playing Tester") then
                warned = true
            end
        end
        assert.is_true(warned)
    end)

    it("warns when a repeat disagrees about the value, and keeps the first", function()
        -- The second copy of 268205@324, with a different number on it. QE Live
        -- has never emitted this; if he ever does, it is reported rather than
        -- resolved by this module choosing one.
        local text = readFile(SAMPLE_PATH)
        local seen = 0
        text = text:gsub('"upgradePercent": 4%.5', function(match)
            seen = seen + 1
            return seen == 2 and '"upgradePercent": 9.9' or match
        end)
        assert.equal(2, seen)
        local result = ns.UFImport.Parse(text)
        assert.is_true(result.ok)
        assert.equal(4.5, result.verdict.items["268205@324"].upgradePercent)
        local warned = false
        for _, warning in ipairs(result.warnings) do
            if warning:match("listed twice with different values") then
                warned = true
            end
        end
        assert.is_true(warned)
    end)

    it("warns when the export ranks nothing", function()
        local text = readFile(SAMPLE_PATH)
        local head = text:sub(1, text:find('"items"', 1, true) - 1)
        local result = ns.UFImport.Parse(head .. '"items": [] }')
        assert.is_true(result.ok)
        local warned = false
        for _, warning in ipairs(result.warnings) do
            if warning:match("ranks no drops") then
                warned = true
            end
        end
        assert.is_true(warned)
    end)
end)

describe("UFImport lookup by itemID and item level", function()
    local ns, verdict

    before_each(function()
        ns = H.load()
        verdict = parsed(ns).verdict
    end)

    after_each(function()
        H.unload()
    end)

    it("answers for the exact item level QE Live valued", function()
        local entry = ns.UFImport.Lookup(verdict, 268205, 324)
        assert.is_not_nil(entry)
        assert.equal(4.5, entry.upgradePercent)
    end)

    it("answers nothing for the same itemID at another level, and never a nearby number", function()
        assert.is_nil(ns.UFImport.Lookup(verdict, 268205, 321))
        assert.is_nil(ns.UFImport.Lookup(verdict, 268205, 334))
        assert.is_nil(ns.UFImport.Lookup(verdict, 268205, nil))
    end)

    it("says which levels it does carry, so a caller can tell silence from a level mismatch", function()
        assert.same({ 324 }, ns.UFImport.LevelsFor(verdict, 268205))
        assert.same({ 9999 }, ns.UFImport.LevelsFor(verdict, 268219))
        assert.is_nil(ns.UFImport.LevelsFor(verdict, 1))
    end)

    it("sorts the levels of an itemID ranked more than once", function()
        local real = parsed(ns, REAL_DUNGEON).verdict
        -- Measured over the committed export: 268205 is ranked at two levels,
        -- 324 (raid difficulty 3) and 334 (dungeon key level 7's max).
        assert.same({ 324, 334 }, ns.UFImport.LevelsFor(real, 268205))
    end)

    it("answers nothing for a verdict that is not one", function()
        assert.is_nil(ns.UFImport.Lookup(nil, 268205, 324))
        assert.is_nil(ns.UFImport.Lookup({}, 268205, 324))
        assert.is_nil(ns.UFImport.LevelsFor(nil, 268205))
    end)
end)

describe("UFImport.Parse over the genuine Dungeon export", function()
    local ns, verdict

    before_each(function()
        ns = H.load()
        verdict = parsed(ns, REAL_DUNGEON).verdict
    end)

    after_each(function()
        H.unload()
    end)

    it("passes every refusal gate: schema, numeric version 1, items, Retail", function()
        assert.equal("qe-live-upgradefinder", verdict.schema)
        assert.equal(1, verdict.version)
        assert.equal("Retail", verdict.player.gameType)
        assert.equal("Restoration Druid", verdict.spec)
        assert.equal("Dungeon", verdict.contentType)
        assert.equal("2026-09-07T23:40:54.760Z", verdict.exportedAt)
        assert.equal("abxrrnezfilt", verdict.reportId)
    end)

    it("reads 357 listed drops as 315 distinct itemID + level entries", function()
        assert.equal(315, #verdict.order)
        assert.equal(315, countKeys(verdict.items))
        local listings = 0
        for _, key in ipairs(verdict.order) do
            listings = listings + verdict.items[key].count
        end
        assert.equal(357, listings)
        assert.equal(0, verdict.skippedItems)
    end)

    it("keeps every way of getting a drop that several drop types list", function()
        local multi = 0
        for _, key in ipairs(verdict.order) do
            if #verdict.items[key].sources > 1 then
                multi = multi + 1
            end
        end
        -- Measured over the committed export.
        assert.equal(35, multi)
    end)

    it("ranks 228 drops above the current set and 87 at no change, and never below it", function()
        local better, zero, worse = 0, 0, 0
        for _, key in ipairs(verdict.order) do
            local entry = verdict.items[key]
            if entry.upgradePercent == 0 then
                zero = zero + 1
            elseif ns.UFImport.IsUpgrade(entry) then
                better = better + 1
            else
                worse = worse + 1
            end
        end
        assert.equal(228, better)
        assert.equal(87, zero)
        assert.equal(0, worse)
    end)

    it("has hpsGain agreeing in sign with upgradePercent on every drop", function()
        local checked = 0
        for _, key in ipairs(verdict.order) do
            local entry = verdict.items[key]
            local percentSign = entry.upgradePercent * ns.UFImport.UPGRADE_BETTER_PERCENT_SIGN
            local hpsSign = entry.hpsGain * ns.UFImport.UPGRADE_BETTER_HPS_GAIN_SIGN
            assert.is_true((percentSign > 0) == (hpsSign > 0))
            checked = checked + 1
        end
        assert.equal(315, checked)
    end)

    it("carries the item levels his settings assume, and no others", function()
        local levels = {}
        for _, key in ipairs(verdict.order) do
            levels[verdict.items[key].level] = true
        end
        local seen = {}
        for level in pairs(levels) do
            seen[#seen + 1] = level
        end
        table.sort(seen)
        -- Measured: `dungeon: 7` values dungeon drops at 311 / 321 / 334, and
        -- `raid: [3]` values raid drops at 318 / 324 / 344 (331 crafted).
        assert.same({ 311, 318, 321, 324, 331, 334, 344 }, seen)
    end)

    it("transports one real drop's numbers exactly as the file has them", function()
        local entry = verdict.items["268205@334"]
        assert.equal(268205, entry.itemID)
        assert.equal(334, entry.level)
        assert.equal("2H Weapon", entry.slot)
        assert.equal(1320, entry.instanceID)
        assert.equal(2882, entry.encounterID)
        assert.equal(4.714, entry.upgradePercent)
        assert.equal(16499, entry.hpsGain)
        assert.equal(0.04714077530355201, entry.score)
    end)

    it("reads the Raid export the same way", function()
        local raid = parsed(ns, REAL_RAID).verdict
        assert.equal("Raid", raid.contentType)
        assert.equal(315, #raid.order)
    end)
end)

describe("UFImport storage", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("stores the last import and files it by content type", function()
        local result = ns.UFImport.Import(readFile(SAMPLE_PATH))
        assert.is_true(result.ok)
        assert.equal(result.verdict, ns.UFImport.Current())
        assert.equal(result.verdict, ns.UFImport.ForContentType("Dungeon"))
        assert.is_number(result.verdict.importedAt)
    end)

    it("keeps a Dungeon and a Raid export side by side rather than overwriting", function()
        assert.is_true(ns.UFImport.Import(readFile(REAL_DUNGEON)).ok)
        assert.is_true(ns.UFImport.Import(readFile(REAL_RAID)).ok)
        assert.equal("Dungeon", ns.UFImport.ForContentType("Dungeon").contentType)
        assert.equal("Raid", ns.UFImport.ForContentType("Raid").contentType)
        assert.same({ "Dungeon", "Raid" }, ns.UFImport.StoredContentTypes())
        assert.equal("Raid", ns.UFImport.Current().contentType)
    end)

    it("stores separately from the Top Gear import, so neither can overwrite the other", function()
        assert.is_true(ns.QEImport.Import(readFile("spec/fixtures/qe/qe-droptimizer-Hotornot-cjyztichdhze.json")).ok)
        assert.is_true(ns.UFImport.Import(readFile(REAL_DUNGEON)).ok)
        assert.equal("qe-live-droptimizer", ns.QEImport.Current().schema)
        assert.equal("qe-live-upgradefinder", ns.UFImport.Current().schema)
        assert.equal("qe-live-droptimizer", ns.QEImport.ForContentType("Dungeon").schema)
        assert.equal("qe-live-upgradefinder", ns.UFImport.ForContentType("Dungeon").schema)
    end)

    it("files an export with no content type under Unknown rather than dropping it", function()
        local text = sampleWith('"contentType": "Dungeon"', '"contentType": ""')
        local result = ns.UFImport.Import(text)
        assert.is_true(result.ok)
        assert.equal(ns.QEImport.UNKNOWN_CONTENT_TYPE, ns.UFImport.ContentTypeKey(result.verdict))
        assert.is_not_nil(ns.UFImport.ForContentType(ns.QEImport.UNKNOWN_CONTENT_TYPE))
    end)

    it("refuses to store before the database exists, and stores nothing", function()
        H.unload()
        ns = H.load({ loaded = false })
        local result = ns.UFImport.Import(readFile(SAMPLE_PATH))
        assert.is_false(result.ok)
        assert.matches("database not loaded", result.reason)
        assert.is_nil(ns.UFImport.Current())
    end)

    it("leaves a refused paste out of the database entirely", function()
        assert.is_false(ns.UFImport.Import("nonsense").ok)
        assert.is_nil(ns.UFImport.Current())
        assert.same({}, ns.UFImport.StoredContentTypes())
    end)
end)

-- ---------------------------------------------------------------------------
-- C-7 (WKE-543): one Upgrade Finder verdict per Mythic+ key level.
--
-- QE Live's Upgrade Finder values every dungeon drop at ONE key - the one
-- `ufSettings.dungeon` names - so "which dungeon at the lowest key still gives
-- me an upgrade" takes several exports. The companion asks him once per level
-- and writes the level onto each document; this is the shelf they land on.
--
-- The key level is always the COMPANION's number. `settings.dungeon` is an
-- index into his MPLUS_KEY_REWARDS table (index 7 is the "+10" button), and
-- nothing here turns one into the other.
describe("UFImport key levels", function()
    local ns

    -- A stored import at a key level, the way ns.Companion files one: the
    -- verdict is parsed from real JSON, then the level the companion file named
    -- is set on it before Store, which is exactly Companion.ImportAll's order.
    local function importAt(path, keyLevel)
        local result = ns.UFImport.Parse(readFile(path))
        assert(result.ok, result.reason)
        result.verdict.keyLevel = keyLevel
        assert(ns.UFImport.Store(result.verdict).ok)
        return result.verdict
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("reads a key level only when it is a whole, non-negative number", function()
        assert.equal(0, ns.UFImport.KeyLevelOf({ keyLevel = 0 }))
        assert.equal(10, ns.UFImport.KeyLevelOf({ keyLevel = 10 }))
        assert.is_nil(ns.UFImport.KeyLevelOf({ keyLevel = 7.5 }))
        assert.is_nil(ns.UFImport.KeyLevelOf({ keyLevel = -1 }))
        assert.is_nil(ns.UFImport.KeyLevelOf({ keyLevel = "10" }), "a level nobody wrote as a number is not a level")
        assert.is_nil(ns.UFImport.KeyLevelOf({}))
        assert.is_nil(ns.UFImport.KeyLevelOf(nil))
        -- What a CALLER asks about is normalised instead, because a lookup by
        -- key "10" is a lookup for key 10 and refusing it would only hide a
        -- typo behind an empty panel.
        assert.equal(10, ns.UFImport.KeyLevelKey("10"))
        assert.equal(ns.UFImport.UNKNOWN_KEY_LEVEL, ns.UFImport.KeyLevelKey(nil))
        assert.equal(ns.UFImport.UNKNOWN_KEY_LEVEL, ns.UFImport.KeyLevelKey(7.5))
    end)

    it("files one content type's exports side by side, one per key level", function()
        importAt(REAL_DUNGEON, 2)
        importAt(REAL_DUNGEON, 10)
        assert.same({ 2, 10 }, (ns.UFImport.StoredKeyLevels("Dungeon")))
        assert.equal(2, ns.UFImport.ForContentTypeAndLevel("Dungeon", 2).keyLevel)
        assert.equal(10, ns.UFImport.ForContentTypeAndLevel("Dungeon", 10).keyLevel)
        -- A level nobody asked QE Live about is nothing, never the nearest one.
        assert.is_nil(ns.UFImport.ForContentTypeAndLevel("Dungeon", 4))
        -- And the Raid shelf is untouched by any of it.
        assert.same({}, (ns.UFImport.StoredKeyLevels("Raid")))
    end)

    it("keeps a level-less export on its own shelf rather than under a level it made up", function()
        importAt(REAL_DUNGEON, 10)
        local pasted = ns.UFImport.Import(readFile(REAL_DUNGEON))
        assert.is_true(pasted.ok)
        local levels, unrecorded = ns.UFImport.StoredKeyLevels("Dungeon")
        assert.same({ 10 }, levels)
        assert.is_true(unrecorded)
        assert.equal(10, ns.UFImport.ForContentTypeAndLevel("Dungeon", 10).keyLevel)
        assert.is_nil(ns.UFImport.ForContentTypeAndLevel("Dungeon", nil).keyLevel)
        -- `settings.dungeon` is 7 in this export and 7 is an INDEX, not a key
        -- level. Reading it as one would file a +10 answer under "+7".
        assert.equal(7, pasted.verdict.settings.dungeon)
    end)

    it("hands every stored document back in ascending key order, the one that does not say last", function()
        importAt(REAL_DUNGEON, 8)
        importAt(REAL_DUNGEON, 2)
        assert.is_true(ns.UFImport.Import(readFile(REAL_DUNGEON)).ok)
        local documents = ns.UFImport.Documents("Dungeon")
        assert.equal(3, #documents)
        assert.equal(2, documents[1].keyLevel)
        assert.equal(8, documents[2].keyLevel)
        assert.is_nil(documents[3].keyLevel, "a document that names no key level comes last")
        assert.equal(2, documents[1].verdict.keyLevel)
        -- Nothing else's shelf is read.
        assert.same({}, ns.UFImport.Documents("Raid"))
        assert.same({}, ns.UFImport.Documents(nil))
    end)

    it("reads SavedVariables written before the by-level shelf existed", function()
        -- A character who imported under M3-6 has ufImports and no
        -- ufImportsByLevel at all. The verdict is still there; it simply never
        -- said which key it was run at.
        assert.is_true(ns.UFImport.Import(readFile(REAL_DUNGEON)).ok)
        ns.db.char.ufImportsByLevel = nil
        local documents = ns.UFImport.Documents("Dungeon")
        assert.equal(1, #documents)
        assert.equal("Dungeon", documents[1].verdict.contentType)
        assert.is_nil(documents[1].keyLevel)
    end)

    it("answers what a new verdict replaces by content type AND key level", function()
        local at2 = importAt(REAL_DUNGEON, 2)
        assert.equal(at2, ns.UFImport.Existing({ contentType = "Dungeon", keyLevel = 2 }))
        -- The +4 document is not a repeat of the +2 one, which is the whole
        -- reason ns.Companion asks the importer instead of matching on content
        -- type: five documents in one file would otherwise become one import.
        assert.is_nil(ns.UFImport.Existing({ contentType = "Dungeon", keyLevel = 4 }))
        assert.is_nil(ns.UFImport.Existing({ contentType = "Raid", keyLevel = 2 }))
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-10 (WKE-545): the cross-level join.
--
-- C-7 filed one document per key level and the panel picked ONE of them. That
-- answered nothing about dungeons: QE Live's +10 document values a dungeon drop
-- at 311 while the client's own keystone-10 preview lists it at 305, so the
-- exact `itemID@level` key missed on every dungeon row. Neither number is
-- Lootpath's to adjust, so the join asks EVERY stored document and keeps the
-- exact match wherever it is - which turns out to be his +6 document, whose
-- dungeon drops come back at 305.
--
-- The five documents below are one companion run (2026-09-08 22:47, five key
-- levels), committed unedited; see spec/fixtures/qe/README.md.
describe("UFImport.LookupAcrossLevels over the five committed key levels", function()
    local ns

    local BY_LEVEL = {
        [2] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lrxljklscrjr.json",
        [4] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-jnjnmzftoppb.json",
        [6] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-zmtnpejwfewe.json",
        [8] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lttldhvkiqlr.json",
        [10] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-wyharestkdyr.json",
    }
    local LEVELS = { 2, 4, 6, 8, 10 }

    -- The item level each of his dungeon documents drops at, read off the
    -- documents themselves by tools/measure-cross-level.lua: +2 at 295, +4 at
    -- 298, +6 at 305, +8 at 308, +10 at 311. 305 is the level the client
    -- previews a keystone 10 at, which is why the +6 document is the one that
    -- answers the walk.
    local DUNGEON_DROP_LEVEL = { [2] = 295, [4] = 298, [6] = 305, [8] = 308, [10] = 311 }

    -- A real dungeon drop, carried by every one of the five documents at that
    -- document's own level: Sickening Signet of Atroxus, which the 2026-09-06
    -- walk lists too.
    local DUNGEON_ITEM = 252258
    local DUNGEON_KEY_321 = "252258@321"

    local function documents()
        for _, level in ipairs(LEVELS) do
            local document = ns.UFImport.Parse(readFile(BY_LEVEL[level]))
            assert(document.ok, document.reason)
            document.verdict.keyLevel = level
            assert(ns.UFImport.Store(document.verdict).ok)
        end
        return ns.UFImport.Documents("Dungeon")
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("finds the walk's 305 dungeon drop in the +6 document and nowhere else", function()
        local list = documents()
        assert.equal(5, #list)
        local entry, keyLevel, how, matches = ns.UFImport.LookupAcrossLevels(list, DUNGEON_ITEM, 305)
        assert.is_not_nil(entry)
        assert.equal(6, keyLevel)
        assert.equal(ns.UFImport.MATCH_ONLY, how)
        assert.equal(1, matches)
        assert.equal(305, entry.level)
        assert.equal("drop", entry.dropType)
        -- Which is exactly the level the single-document pick could not reach:
        -- the +10 document has this item, at 311, and says nothing about 305.
        assert.is_nil(ns.UFImport.Lookup(ns.UFImport.ForContentTypeAndLevel("Dungeon", 10), DUNGEON_ITEM, 305))
        assert.is_not_nil(ns.UFImport.Lookup(ns.UFImport.ForContentTypeAndLevel("Dungeon", 10), DUNGEON_ITEM, 311))
    end)

    it("takes each document's own drop level from that document and no other", function()
        local list = documents()
        for _, level in ipairs(LEVELS) do
            local entry, keyLevel = ns.UFImport.LookupAcrossLevels(list, DUNGEON_ITEM, DUNGEON_DROP_LEVEL[level])
            assert.is_not_nil(entry, "no document carries this drop at " .. DUNGEON_DROP_LEVEL[level])
            assert.equal(level, keyLevel)
            assert.equal(DUNGEON_DROP_LEVEL[level], entry.level)
        end
    end)

    it("never answers for an item level no document carries", function()
        local list = documents()
        -- 306 sits between his +6 (305) and his +8 (308) and belongs to
        -- neither. A neighbour is not an answer, and interpolating one would be
        -- Lootpath computing a healer value.
        assert.is_nil(ns.UFImport.LookupAcrossLevels(list, DUNGEON_ITEM, 306))
        assert.is_nil(ns.UFImport.LookupAcrossLevels(list, DUNGEON_ITEM, nil))
        assert.is_nil(ns.UFImport.LookupAcrossLevels(list, 0, 305))
        assert.is_nil(ns.UFImport.LookupAcrossLevels(nil, DUNGEON_ITEM, 305))
        -- But it does say the item is known at other levels, which is the fact
        -- the panel counts instead of showing a number.
        assert.same({ 295, 298, 305, 308, 311, 321, 334 }, ns.UFImport.LevelsAcrossLevels(list, DUNGEON_ITEM))
        assert.is_nil(ns.UFImport.LevelsAcrossLevels(list, 1))
    end)

    it("prefers the document that calls the level a drop when several carry it", function()
        local list = documents()
        -- 321 is a real collision: all five documents list this item there,
        -- four of them as a `bonus` roll and the +10 one as its `max` upgrade.
        -- None of them calls it a drop, so the lowest key level wins.
        local entry, keyLevel, how, matches = ns.UFImport.LookupAcrossLevels(list, DUNGEON_ITEM, 321)
        assert.equal(5, matches)
        assert.equal(ns.UFImport.MATCH_LOWEST, how)
        assert.equal(2, keyLevel)
        assert.equal(321, entry.level)

        -- And when one of them DOES call it a drop, that one wins whatever its
        -- key level: the tie follows QE Live's own dropType, not the order the
        -- documents happen to sit in.
        local higher = ns.UFImport.ForContentTypeAndLevel("Dungeon", 8)
        higher.items[DUNGEON_KEY_321].dropType = ns.UFImport.DROP_TYPE_DROP
        local picked, level, pick = ns.UFImport.LookupAcrossLevels(list, DUNGEON_ITEM, 321)
        assert.equal(8, level)
        assert.equal(ns.UFImport.MATCH_DROP, pick)
        assert.equal(higher.items[DUNGEON_KEY_321], picked)
    end)

    it("reads a drop type QE Live listed on a repeat of the same item at that level", function()
        local list = documents()
        local entry = ns.UFImport.ForContentTypeAndLevel("Dungeon", 6).items[DUNGEON_KEY_321]
        assert.is_false(ns.UFImport.IsDropAtLevel(entry))
        assert.is_false(ns.UFImport.IsDropAtLevel(nil))
        -- One item at one level can be listed several ways in one export (drop,
        -- max, bonus); the parser keeps the first and files the rest as
        -- `sources`, so both are read before the tie is called.
        entry.sources[#entry.sources + 1] = { dropType = ns.UFImport.DROP_TYPE_DROP }
        assert.is_true(ns.UFImport.IsDropAtLevel(entry))
        local _, keyLevel, how = ns.UFImport.LookupAcrossLevels(list, DUNGEON_ITEM, 321)
        assert.equal(6, keyLevel)
        assert.equal(ns.UFImport.MATCH_DROP, how)
    end)

    it("names the documents it joined against, and only says how when there are several", function()
        local list = documents()
        assert.equal(
            "Upgrade Finder at +2, +4, +6, +8, +10 (5 documents)."
                .. " A drop takes its number from whichever of them values it at the item level the loot map lists.",
            ns.UFImport.DocumentsNote(list)
        )
        assert.equal(
            "Upgrade Finder at +6 (1 document).",
            ns.UFImport.DocumentsNote({ { verdict = {}, keyLevel = 6 } })
        )
        assert.equal(
            "Upgrade Finder, with no Mythic+ key level named (1 document).",
            ns.UFImport.DocumentsNote({ { verdict = {} } })
        )
        assert.matches(
            "at %+2, and 1 that name no key level %(2 documents%)",
            ns.UFImport.DocumentsNote({ { verdict = {}, keyLevel = 2 }, { verdict = {} } })
        )
        assert.is_nil(ns.UFImport.DocumentsNote({}))
        assert.is_nil(ns.UFImport.DocumentsNote(nil))
    end)

    it("labels a key level as QE Live's own button and nothing else", function()
        assert.equal("+10", ns.UFImport.KeyLabel(10))
        assert.equal("+0", ns.UFImport.KeyLabel(0))
        assert.equal("+2", ns.UFImport.KeyLabel("2"))
        assert.is_nil(ns.UFImport.KeyLabel(nil))
        assert.is_nil(ns.UFImport.KeyLabel(7.5))
        assert.is_nil(ns.UFImport.KeyLabel(-1))
    end)
end)

-- R-4 (WKE-565): the rows that are not a boss drop.
--
-- Every committed export carries them and nothing ever asked for them. The
-- figures below were read off the files by tools/measure-delves-crafted.lua
-- before they were written down here.
describe("UFImport Delves and Crafted rows", function()
    local ns

    local BY_LEVEL = {
        [2] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lrxljklscrjr.json",
        [4] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-jnjnmzftoppb.json",
        [6] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-zmtnpejwfewe.json",
        [8] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lttldhvkiqlr.json",
        [10] = "spec/fixtures/qe/qe-upgradefinder-Hotornot-wyharestkdyr.json",
    }
    local RAID_KEY_10 = "spec/fixtures/qe/qe-upgradefinder-Hotornot-ynfzbppepnzw.json"

    -- The owner's own two-hander slot, the one the issue was filed on: the
    -- crafted Magister's Valediction at 331 and the delve two-hander at 321.
    local CRAFTED_WEAPON = 237849
    local DELVE_WEAPON = 272273

    local function verdictAt(path)
        local result = ns.UFImport.Parse(readFile(path))
        assert(result.ok, result.reason)
        return result.verdict
    end

    local function dungeonDocuments()
        local documents = {}
        for _, level in ipairs({ 2, 4, 6, 8, 10 }) do
            documents[#documents + 1] = { verdict = verdictAt(BY_LEVEL[level]), keyLevel = level }
        end
        return documents
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("names a kind for exactly the two dropLoc values that are not a drop", function()
        assert.equal("craft", ns.UFImport.SourceKind("Crafted"))
        assert.equal("delve", ns.UFImport.SourceKind("Delves"))
        -- Everything else is a drop and belongs to the journal's half of the
        -- panel, including the number his own unit-test fixture uses and the
        -- two words the real exports carry for a boss.
        assert.is_nil(ns.UFImport.SourceKind("Dungeon"))
        assert.is_nil(ns.UFImport.SourceKind("Raid"))
        assert.is_nil(ns.UFImport.SourceKind(1))
        assert.is_nil(ns.UFImport.SourceKind(nil))
        assert.is_nil(ns.UFImport.SourceKind("crafted"))
    end)

    it("puts the kind and the crafted row's profession index on the entry itself", function()
        local verdict = verdictAt(BY_LEVEL[10])
        local crafted = verdict.items[CRAFTED_WEAPON .. "@331"]
        assert.is_not_nil(crafted)
        assert.equal("craft", crafted.sourceKind)
        assert.equal("Crafted", crafted.dropLoc)
        -- His own sentinel instance, and the encounterId carried as the index
        -- it is. Never turned into a profession name here.
        assert.equal(ns.UFImport.CRAFTED_INSTANCE_ID, crafted.instanceID)
        assert.equal(3, crafted.professionIndex)
        assert.equal(crafted.encounterID, crafted.professionIndex)
        -- `dropType` is null and `dropDifficulty` is the empty string on these
        -- rows, so neither the drop tie-break nor a difficulty means anything.
        assert.is_nil(crafted.dropType)
        assert.is_nil(crafted.dropDifficulty)
        assert.is_false(ns.UFImport.IsDropAtLevel(crafted))

        local delve = verdict.items[DELVE_WEAPON .. "@321"]
        assert.equal("delve", delve.sourceKind)
        assert.equal(ns.UFImport.DELVE_INSTANCE_ID, delve.instanceID)
        assert.equal(ns.UFImport.DELVE_INSTANCE_ID, delve.encounterID)
        -- A delve row has no profession, so it carries no index at all.
        assert.is_nil(delve.professionIndex)

        -- Proven red on a real boss drop of the same file: it has neither.
        local drop = verdict.items["252258@311"]
        assert.is_not_nil(drop)
        assert.is_nil(drop.sourceKind)
        assert.is_nil(drop.professionIndex)
    end)

    it("carries 18 crafted and 33 delve rows in every committed export", function()
        local files = { BY_LEVEL[2], BY_LEVEL[4], BY_LEVEL[6], BY_LEVEL[8], BY_LEVEL[10], RAID_KEY_10 }
        for _, path in ipairs(files) do
            local documents = { { verdict = verdictAt(path) } }
            assert.equal(18, #ns.UFImport.SourceRows(documents, "craft"), path)
            assert.equal(33, #ns.UFImport.SourceRows(documents, "delve"), path)
            for _, held in ipairs(ns.UFImport.SourceRows(documents, "delve")) do
                assert.equal(321, held.entry.level)
                assert.equal(ns.UFImport.DELVE_INSTANCE_ID, held.entry.instanceID)
            end
            for _, held in ipairs(ns.UFImport.SourceRows(documents, "craft")) do
                assert.equal(331, held.entry.level)
                assert.equal(ns.UFImport.CRAFTED_INSTANCE_ID, held.entry.instanceID)
                assert.is_number(held.entry.professionIndex)
            end
        end
    end)

    it("orders a kind by the percentage he gave, best first", function()
        local documents = { { verdict = verdictAt(BY_LEVEL[10]), keyLevel = 10 } }
        local crafted = ns.UFImport.SourceRows(documents, "craft")
        assert.equal(CRAFTED_WEAPON, crafted[1].entry.itemID)
        assert.equal(3.627, crafted[1].entry.upgradePercent)
        local previous
        for _, held in ipairs(crafted) do
            if previous then
                assert.is_true(held.entry.upgradePercent <= previous)
            end
            previous = held.entry.upgradePercent
        end
        -- Narrowed to one slot, it is the same order over the same entries.
        local weapon = ns.UFImport.SourceRows(documents, "craft", "2H Weapon")
        assert.equal(2, #weapon)
        assert.equal(CRAFTED_WEAPON, weapon[1].entry.itemID)
        for _, held in ipairs(weapon) do
            assert.equal("2H Weapon", held.entry.slot)
        end
        local delves = ns.UFImport.SourceRows(documents, "delve", "2H Weapon")
        assert.equal(2, #delves)
        assert.equal(DELVE_WEAPON, delves[1].entry.itemID)
        assert.equal(2.171, delves[1].entry.upgradePercent)
        -- An unknown kind is not a kind: no rows, rather than every row.
        assert.equal(0, #ns.UFImport.SourceRows(documents, "vendor"))
        assert.equal(0, #ns.UFImport.SourceRows(documents, nil))
        assert.equal(0, #ns.UFImport.SourceRows(nil, "craft"))
    end)

    it("says the five key-level documents agree about every one of these rows", function()
        -- Measured: all five dungeon documents carry the same 51 Crafted and
        -- Delves rows with the same upgradePercent on every one, because a
        -- Mythic+ key is not what values a crafted item. So no row names a key
        -- level, and the first document (the lowest key) is the one kept.
        local documents = dungeonDocuments()
        local rows = 0
        for _, kind in ipairs(ns.UFImport.SOURCE_KINDS) do
            for _, held in ipairs(ns.UFImport.SourceRows(documents, kind)) do
                rows = rows + 1
                assert.equal(5, held.documents, held.entry.key)
                assert.is_nil(held.disagrees, held.entry.key)
                assert.equal(2, held.keyLevel)
            end
        end
        assert.equal(51, rows)

        -- Proven red with two documents that really do disagree: the Raid
        -- export values 33 of the same 51 rows differently (his content type
        -- is what moves them), and a row that two stored documents disagree
        -- about says which document it took.
        local mixed = { { verdict = verdictAt(BY_LEVEL[10]), keyLevel = 10 }, { verdict = verdictAt(RAID_KEY_10) } }
        local disagreed = 0
        for _, kind in ipairs(ns.UFImport.SOURCE_KINDS) do
            for _, held in ipairs(ns.UFImport.SourceRows(mixed, kind)) do
                assert.equal(2, held.documents)
                if held.disagrees then
                    disagreed = disagreed + 1
                    assert.equal(10, held.keyLevel)
                end
            end
        end
        assert.equal(33, disagreed)
    end)

    it("reads the crafted settings as a stats line and an INDEX, never an item level", function()
        local verdict = verdictAt(BY_LEVEL[10])
        local settings = ns.UFImport.CraftedSettings(verdict)
        assert.equal("Crit / Haste", settings.stats)
        -- 2 is a row of his own crafted-level table, and the rows it produced
        -- arrive at item level 331. The two are never confused: the level on a
        -- row is the row's own.
        assert.equal(2, settings.levelIndex)
        assert.equal(331, verdict.items[CRAFTED_WEAPON .. "@331"].level)
        assert.is_nil(ns.UFImport.CraftedSettings({}))
        assert.is_nil(ns.UFImport.CraftedSettings(nil))
        assert.is_nil(ns.UFImport.CraftedSettings({ settings = {} }))
        -- Carried on every crafted row of that document, and on no delve row:
        -- the stats line is about what a crafting order would make.
        local documents = { { verdict = verdict, keyLevel = 10 } }
        for _, held in ipairs(ns.UFImport.SourceRows(documents, "craft")) do
            assert.equal("Crit / Haste", held.crafted.stats)
        end
        for _, held in ipairs(ns.UFImport.SourceRows(documents, "delve")) do
            assert.is_nil(held.crafted)
        end
    end)

    it("keeps a row with no usable itemID out, as it keeps out any other", function()
        -- The hand-built sample's crafted row carries itemID 0 and an empty
        -- source, which UFImport.Item refuses; its delve row is real and is
        -- read. A row nobody can identify is skipped, never shown as item 0.
        local verdict = verdictAt(SAMPLE_PATH)
        local documents = { { verdict = verdict } }
        assert.equal(0, #ns.UFImport.SourceRows(documents, "craft"))
        local delves = ns.UFImport.SourceRows(documents, "delve")
        assert.equal(1, #delves)
        assert.equal(272147, delves[1].entry.itemID)
        assert.equal(321, delves[1].entry.level)
        assert.equal(1, verdict.skippedItems)
    end)
end)

-- UX-6b (WKE-639): a drop's row at ANOTHER level, by his own dropType.
describe("UFImport.OtherLevelEntry", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

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
                sources = { { dropType = spec[2] }, spec[4] and { dropType = spec[4] } or nil },
            }
            levels[#levels + 1] = spec[1]
        end
        table.sort(levels)
        return { keyLevel = keyLevel, verdict = { items = items, levelsByItemID = { [1001] = levels } } }
    end

    it("takes the lowest level carrying the type, from the lowest key level that does", function()
        local plus2 = document(2, { { 298, "bonus", 0.4 }, { 308, "drop", 0.3, "max" } })
        local plus4 = document(4, { { 298, "drop", 0.2 }, { 311, "drop", 0.1 } })
        local entry, level, keyLevel, from = ns.UFImport.OtherLevelEntry({ plus2, plus4 }, 1001, "drop")
        assert.equal(298, level)
        assert.equal(4, keyLevel)
        assert.equal(plus4, from)
        assert.equal(0.2, entry.upgradePercent)
        -- A type carried only as a later listing still counts.
        local maxEntry, maxLevel = ns.UFImport.OtherLevelEntry({ plus2, plus4 }, 1001, "max")
        assert.equal(308, maxLevel)
        assert.is_true(ns.UFImport.HasDropType(maxEntry, "max"))
        assert.is_true(ns.UFImport.IsDropAtLevel(maxEntry))
        -- Nothing of that type, and nothing at all.
        assert.is_nil(ns.UFImport.OtherLevelEntry({ plus4 }, 1001, "max"))
        assert.is_nil(ns.UFImport.OtherLevelEntry({ plus2 }, 2002, "drop"))
        assert.is_false(ns.UFImport.HasDropType(nil, "drop"))
        assert.is_false(ns.UFImport.HasDropType(maxEntry, nil))
    end)
end)
