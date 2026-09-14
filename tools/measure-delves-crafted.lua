-- tools/measure-delves-crafted.lua (R-4, WKE-565)
--
-- Reads the Crafted and Delves rows off the committed Upgrade Finder exports
-- and prints what the Upgrade Map now makes of them, so every figure in the PR
-- body, in `spec/upgrademap_spec.lua` and in `docs/ARCHITECTURE.md` is one a
-- tool produced rather than one somebody expected. Run it the way the test
-- suite runs, from the repo root:
--
--   docker run --rm -v "${PWD}:/work" lootpath-lua lua tools/measure-delves-crafted.lua
--
-- It computes nothing of QE Live's: every number below is a count of his own
-- entries, or one of his own `upgradePercent` values quoted back.
package.path = "./?.lua;" .. package.path

local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

-- The five dungeon documents and the raid one the companion wrote in a single
-- run on 2026-09-08, and the earlier 2026-09-07 pair M3-6 was built on (see
-- spec/fixtures/qe/README.md). Every one of them is committed unedited.
local DUNGEON = {
    { level = 2, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lrxljklscrjr.json" },
    { level = 4, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-jnjnmzftoppb.json" },
    { level = 6, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-zmtnpejwfewe.json" },
    { level = 8, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-lttldhvkiqlr.json" },
    { level = 10, path = "spec/fixtures/qe/qe-upgradefinder-Hotornot-wyharestkdyr.json" },
}
local RAID_KEY_10 = "spec/fixtures/qe/qe-upgradefinder-Hotornot-ynfzbppepnzw.json"
local M3_6_DUNGEON = "spec/fixtures/qe/qe-upgradefinder-Hotornot-abxrrnezfilt.json"
local M3_6_RAID = "spec/fixtures/qe/qe-upgradefinder-Hotornot-kqyktjywppzw.json"

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

local function parse(path)
    local result = ns.UFImport.Parse(readFile(path))
    assert(result.ok, result.reason)
    return result.verdict
end

local function documentsFrom(list)
    local documents = {}
    for _, entry in ipairs(list) do
        documents[#documents + 1] = { verdict = parse(entry.path), keyLevel = entry.level }
    end
    return documents
end

-- ---------------------------------------------------------------------------
say("== rows per committed export (dropLoc, as he wrote it)")
local EVERY = {
    { name = "abxrrnezfilt (Dungeon, 2026-09-07)", path = M3_6_DUNGEON },
    { name = "kqyktjywppzw (Raid, 2026-09-07)", path = M3_6_RAID },
    { name = "lrxljklscrjr (Dungeon +2)", path = DUNGEON[1].path },
    { name = "jnjnmzftoppb (Dungeon +4)", path = DUNGEON[2].path },
    { name = "zmtnpejwfewe (Dungeon +6)", path = DUNGEON[3].path },
    { name = "lttldhvkiqlr (Dungeon +8)", path = DUNGEON[4].path },
    { name = "wyharestkdyr (Dungeon +10)", path = DUNGEON[5].path },
    { name = "ynfzbppepnzw (Raid +10)", path = RAID_KEY_10 },
}
for _, file in ipairs(EVERY) do
    local verdict = parse(file.path)
    local counts, slots, noSlot = {}, {}, 0
    for _, entry in pairs(verdict.items) do
        local kind = ns.UFImport.SourceKind(entry.dropLoc)
        if kind then
            counts[kind] = (counts[kind] or 0) + 1
            if entry.slot then
                slots[kind] = slots[kind] or {}
                slots[kind][entry.slot] = true
            else
                noSlot = noSlot + 1
            end
        end
    end
    local function slotCount(kind)
        local n = 0
        for _ in pairs(slots[kind] or {}) do
            n = n + 1
        end
        return n
    end
    say(
        string.format(
            "  %-36s craft %2d over %2d slots, delve %2d over %2d slots, no slot %d",
            file.name,
            counts.craft or 0,
            slotCount("craft"),
            counts.delve or 0,
            slotCount("delve"),
            noSlot
        )
    )
end

-- ---------------------------------------------------------------------------
say("")
say("== the 2H Weapon slot, the owner's own: every committed export")
for _, file in ipairs(EVERY) do
    local verdict = parse(file.path)
    local line = { string.format("  %-36s", file.name) }
    for _, kind in ipairs(ns.UFImport.SOURCE_KINDS) do
        local rows = ns.UFImport.SourceRows({ { verdict = verdict } }, kind, "2H Weapon")
        local best = rows[1]
        line[#line + 1] = best
                and string.format(
                    "%s %d @%d %+.3f%% (%d ranked)",
                    kind,
                    best.entry.itemID,
                    best.entry.level,
                    best.entry.upgradePercent,
                    #rows
                )
            or (kind .. " none")
    end
    say(table.concat(line, "  "))
end

-- ---------------------------------------------------------------------------
say("")
say("== the panel, over the five-document companion run and the 2026-09-06 walk")
local snapshot = R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ)
local sources, summary = ns.Journal:Build({ snapshot = snapshot })
assert(summary.ok, "journal build failed")

local function report(label, documents)
    local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, upgradeDocuments = documents })
    say(
        string.format(
            "%s: %d slot sections, %d Crafted/Delves rows shown, %d crafted and %d delve rows ranked for those slots",
            label,
            model.counts.slots,
            model.counts.exportRows,
            model.counts.craftedRanked,
            model.counts.delvesRanked
        )
    )
    for _, section in ipairs(model.slots) do
        for _, row in ipairs(section.exportRows or {}) do
            say(
                string.format(
                    "    %-10s %-6s item %d (%d) - %s - %s",
                    section.slot,
                    row.sourceKind,
                    row.itemID,
                    row.itemLevel,
                    row.second,
                    tostring(row.upgradeValue)
                )
            )
        end
    end
    local runs = ns.UpgradeMapPanel.RunModel({
        sources = sources,
        summary = summary,
        upgradeDocuments = documents,
        runSort = ns.UpgradeMapPanel.SORT_BEST,
    })
    say(
        string.format(
            "  by run: %d cards (%d from the export), %d rated",
            runs.counts.runs,
            runs.counts.exportRuns,
            runs.counts.ratedRuns
        )
    )
    for _, run in ipairs(runs.runs) do
        if run.sourceKind then
            say(string.format("    card %-9s %s | %s", run.name, run.badge.text, run.countText))
            for index, row in ipairs(run.upgrades) do
                say(
                    string.format(
                        "      %2d. item %d (%s, %d) %s",
                        index,
                        row.itemID,
                        tostring(row.slot),
                        row.itemLevel,
                        tostring(row.upgradeValue)
                    )
                )
            end
        end
    end
    for _, sort in ipairs(ns.UpgradeMapPanel.SORTS) do
        local sorted = ns.UpgradeMapPanel.RunModel({
            sources = sources,
            summary = summary,
            upgradeDocuments = documents,
            runSort = sort,
        })
        local positions = {}
        for index, run in ipairs(sorted.runs) do
            if run.sourceKind then
                positions[#positions + 1] = string.format("%s at %d", run.name, index)
            end
        end
        say(string.format("  sorted by %s: top is %q; %s", sort, sorted.runs[1].label, table.concat(positions, ", ")))
        say(string.format("    headline: %s", tostring(sorted.headline)))
    end
end

report("five Dungeon documents (+2 .. +10)", documentsFrom(DUNGEON))
report("the Raid document alone (+10)", { { verdict = parse(RAID_KEY_10), keyLevel = 10 } })
report("the 2026-09-07 Raid document (M3-6, no key level)", { { verdict = parse(M3_6_RAID) } })

H.unload()
