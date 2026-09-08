-- tools/measure-cross-level.lua (M3-10, WKE-545)
--
-- Reads the cross-level join off the committed fixtures and prints it, so every
-- figure in the PR body and in `spec/upgrademap_spec.lua` is one a tool
-- produced rather than one somebody expected. Run it the way the test suite
-- runs, from the repo root:
--
--   docker run --rm -v "${PWD}:/work" lootpath-lua lua tools/measure-cross-level.lua
--
-- It computes nothing of QE Live's: every number below is a count of his own
-- entries, or one of his own `upgradePercent` values quoted back.
package.path = "./?.lua;" .. package.path

local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

-- The five dungeon documents and the raid one the companion wrote in a single
-- run on 2026-09-08 (see spec/fixtures/qe/README.md), with the key level the
-- companion stamped on each - the number it reports for the button it clicked
-- on QE Live's own key selector, never one derived here.
local DUNGEON = {
    { level = 2, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lrxljklscrjr.json" },
    { level = 4, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-jnjnmzftoppb.json" },
    { level = 6, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-zmtnpejwfewe.json" },
    { level = 8, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lttldhvkiqlr.json" },
    { level = 10, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-wyharestkdyr.json" },
}
local RAID = { level = 10, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-ynfzbppepnzw.json" }

-- The stub world replaces the global print (spec/stubs/wow.lua), so this writes
-- straight to stdout and stays readable after H.load().
local function say(text)
    io.stdout:write(text, "\n")
end

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local ns = H.load()

local function storeAll(list)
    local exports = {}
    for _, document in ipairs(list) do
        exports[#exports + 1] = {
            schema = "qe-live-upgradefinder",
            contentType = "Dungeon",
            keyLevel = document.level,
            json = readFile(document.path),
        }
    end
    local result = ns.Companion.ImportAll({ writtenAt = "2026-09-08T22:47:59Z", exports = exports })
    assert(result.ok, result.reason)
    assert(#result.skipped == 0, result.skipped[1] and result.skipped[1].reason)
    return result
end

storeAll(DUNGEON)

local snapshot = R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ)
local sources, summary = ns.Journal:Build({ snapshot = snapshot })
assert(summary.ok, "journal build failed")
say(
    string.format(
        "walk: %d drops, previewed at Mythic Keystone %s",
        summary.sources,
        tostring(summary.previewMythicPlusLevel)
    )
)

-- Per document, how many of the walk's rows that document alone carries at the
-- walk's own item level.
local documents = ns.UFImport.Documents("Dungeon")
say(string.format("documents stored for Dungeon: %d", #documents))
local mythicPlus = ns.JournalAdapter.DifficultyID("DungeonChallenge")
for _, document in ipairs(documents) do
    local hits, keystone, upgrades = 0, 0, 0
    for itemID, entries in pairs(sources) do
        for _, entry in ipairs(entries) do
            if entry.itemLevel then
                local found = ns.UFImport.Lookup(document.verdict, itemID, entry.itemLevel)
                if found then
                    hits = hits + 1
                    if entry.difficultyID == mythicPlus then
                        keystone = keystone + 1
                    end
                    if ns.UFImport.IsUpgrade(found) then
                        upgrades = upgrades + 1
                    end
                end
            end
        end
    end
    say(
        string.format(
            "  +%s: %d walk rows carried (%d of them Mythic Keystone), %d of them upgrades",
            tostring(document.keyLevel),
            hits,
            keystone,
            upgrades
        )
    )
    -- What ONE document alone would have put on the panel, which is what C-7
    -- did: the baseline the cross-level join is measured against.
    local alone = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, upgradeDocuments = { document } })
    say(
        string.format(
            "     alone: %d rows ranked, %d ranked only at another level",
            alone.counts.ranked,
            alone.counts.rankedAtAnotherLevel
        )
    )
end

local model = ns.UpgradeMapPanel.Model({
    sources = sources,
    summary = summary,
    upgradeDocuments = documents,
})
say(
    string.format(
        "slot view: %d candidates, %d ranked across levels, %d ranked only at another level",
        model.counts.candidates,
        model.counts.ranked,
        model.counts.rankedAtAnotherLevel
    )
)
say("slot view note: " .. tostring(model.upgradeDocumentsNote))

-- Which key level the rows that DID rank came from, and how the tie between two
-- documents carrying one drop at one level was settled.
local byLevel, byHow = {}, {}
for _, section in ipairs(model.slots) do
    for _, row in ipairs(section.candidates) do
        if row.upgrade then
            local label = tostring(row.upgradeKeyLevel)
            byLevel[label] = (byLevel[label] or 0) + 1
            byHow[row.upgradeKeyPick] = (byHow[row.upgradeKeyPick] or 0) + 1
        end
    end
end
for label, count in pairs(byLevel) do
    say(string.format("  rows valued by the +%s document: %d", label, count))
end
for how, count in pairs(byHow) do
    say(string.format("  chosen because: %s (%d rows)", how, count))
end

for _, sort in ipairs({ ns.UpgradeMapPanel.SORT_BEST, ns.UpgradeMapPanel.SORT_COUNT }) do
    local runs = ns.UpgradeMapPanel.RunModel({
        sources = sources,
        summary = summary,
        upgradeDocuments = documents,
        runSort = sort,
    })
    say(
        string.format(
            "by-run (%s): %d runs, %d rated, %d of %d drops rated",
            sort,
            runs.counts.runs,
            runs.counts.ratedRuns,
            runs.counts.rated,
            runs.counts.drops
        )
    )
    say("  headline: " .. tostring(runs.headline))
    local shown = 0
    for _, run in ipairs(runs.runs) do
        if run.best and shown < 5 then
            shown = shown + 1
            say(string.format("  %d. %s", shown, run.text))
        end
    end
    local dungeon
    for _, run in ipairs(runs.runs) do
        if not run.isRaid and run.best and not dungeon then
            dungeon = run
        end
    end
    say("  top dungeon run: " .. (dungeon and dungeon.text or "none"))
end

-- The raid document on its own, which is the join M3-6 already had: a raid drop
-- at the level the walk previews.
H.unload()
ns = H.load()
local raid = ns.Companion.ImportAll({
    writtenAt = "2026-09-08T22:47:59Z",
    exports = {
        { schema = "qe-live-upgradefinder", contentType = "Raid", keyLevel = RAID.level, json = readFile(RAID.path) },
    },
})
assert(raid.ok, raid.reason)
local raidDocuments = ns.UFImport.Documents("Raid")
local raidSnapshot = R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ)
local raidSources, raidSummary = ns.Journal:Build({ snapshot = raidSnapshot })
local raidModel = ns.UpgradeMapPanel.Model({
    sources = raidSources,
    summary = raidSummary,
    upgradeDocuments = raidDocuments,
})
say(
    string.format(
        "raid document alone: %d ranked, %d ranked only at another level; note: %s",
        raidModel.counts.ranked,
        raidModel.counts.rankedAtAnotherLevel,
        tostring(raidModel.upgradeDocumentsNote)
    )
)
for _, section in ipairs(raidModel.slots) do
    for _, row in ipairs(section.candidates) do
        if row.upgrade and row.itemLevel == 344 then
            say(string.format("  a 344 raid row: item %d - %s", row.itemID, row.upgradeValue))
            return
        end
    end
end
