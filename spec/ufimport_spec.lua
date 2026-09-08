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
