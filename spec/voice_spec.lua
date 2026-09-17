-- spec/voice_spec.lua (V-1, WKE-569)
-- The source-free voice, as a guard that stays.
--
-- The owner decided on 2026-09-11 (docs/ARCHITECTURE.md 7, the Roads entry;
-- docs/ROADS-UX.md "Copy voice") that player-facing text names no source: not
-- the engine, not "his", not "he", not "the addon has determined". The screen
-- shows the rating and says what to do. The Roads lane was written to that
-- rule; the three tabs that existed before it were not, and this file is what
-- keeps them there once V-1 has swept them.
--
-- Two halves, because either alone has a hole:
--
--   1. The RENDERED half drives the real window over the committed fixtures -
--      the 2026-09-05 inventory, the 2026-09-06 journal walk, the vault pair,
--      and both genuine exports - and reads back every line each tab puts on
--      screen, the status strip and its tooltip, the import dialog, and every
--      refusal the two importers and Match can produce. That is the text a
--      player actually sees, and it is the text that matters.
--
--   2. The CONSTANT half walks the panels' own string tables on a freshly
--      loaded namespace, so a phrase that no fixture happens to reach is still
--      caught. It skips bare identifiers (`no_verdict`, `thisWeek`: internal
--      names stay, by the same decision) and carries one explicit allowance,
--      documented at ALLOWED below.
--
-- Proven red 2026-09-14 by putting "QE Live's pick" back into
-- `ns.VaultPanel.PICK_LABEL`: the rendered half failed on the Vault tab's
-- headline and its grid cell, and the constant half failed on the table entry.
-- Restored, and both halves pass.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local QE_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"
local UF_EXPORT = "spec/fixtures/qe/qe-upgradefinder-Hotornot-abxrrnezfilt.json"

-- What no player-facing string may say. `verdict` is the brain's word, not a
-- player's; `his` and `he` are the engine's author; "the addon has determined"
-- is the claim Lootpath must never make, since it computes nothing.
local FORBIDDEN = {
    {
        name = "QE Live",
        find = function(text)
            return text:find("QE Live", 1, true)
        end,
    },
    {
        name = "his",
        find = function(text)
            return text:find("%f[%a]his%f[%A]")
        end,
    },
    {
        name = "he",
        find = function(text)
            return text:find("%f[%a]he%f[%A]")
        end,
    },
    {
        name = "verdict",
        find = function(text)
            return text:lower():find("verdict", 1, true)
        end,
    },
    {
        name = "the addon has determined",
        find = function(text)
            return text:lower():find("the addon has determined", 1, true)
        end,
    },
}

-- The one allowance, and why. The companion writes `Data/QEVerdict.lua` into
-- the addon folder and the addon reads it at load (decision 2026-09-07,
-- ARCHITECTURE.md 7). When that file is malformed the player is told which
-- file is wrong, by its name, because no other name would send them to it.
-- The file's name is an internal name that happens to contain the word; it
-- says nothing about where a rating came from.
local function allowed(text)
    return text:find("QEVerdict.lua", 1, true) ~= nil
end

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

-- One collector per test: `check` records where a string came from, and
-- `report` turns every offence into one readable failure rather than a
-- stop-on-first that hides the other nine.
local function collector()
    local offences, seen = {}, 0
    local self = {}
    function self.check(where, text)
        if type(text) ~= "string" or text == "" or allowed(text) then
            return
        end
        seen = seen + 1
        for _, word in ipairs(FORBIDDEN) do
            if word.find(text) then
                offences[#offences + 1] = string.format('%s says "%s": %s', where, word.name, text)
            end
        end
    end
    -- `least` is the number of strings the surface was measured to produce on
    -- 2026-09-14, rounded down. A guard that reads nothing passes trivially, so
    -- a surface that stops answering fails here rather than going quiet.
    function self.report(least)
        assert.is_true(
            seen >= least,
            string.format("read %d strings, expected at least %d: this surface has gone quiet", seen, least)
        )
        if #offences > 0 then
            error(
                string.format(
                    "%d player-facing string(s) name a source:\n  %s",
                    #offences,
                    table.concat(offences, "\n  ")
                ),
                2
            )
        end
    end
    function self.count()
        return seen
    end
    return self
end

-- Every string in a table, to a bounded depth, with its path. Keys are never
-- checked - `CELL_NO_VERDICT_TEXT` is a field name, not a sentence - and
-- values that are bare identifiers are skipped, because internal names stay:
-- `no_verdict` is a status, `thisWeek` is a scenario key.
local function walkStrings(check, where, value, depth, visited)
    depth = depth or 0
    visited = visited or {}
    if depth > 4 or type(value) ~= "table" or visited[value] then
        return
    end
    visited[value] = true
    for key, entry in pairs(value) do
        local path = where .. "." .. tostring(key)
        if type(entry) == "string" then
            if not entry:match("^[%w_]+$") then
                check(path, entry)
            end
        elseif type(entry) == "table" then
            walkStrings(check, path, entry, depth + 1, visited)
        end
    end
end

-- Every committed vault snapshot has an EMPTY reward list (the owner captured
-- them before the week generated), so a vault replayed as it stands never draws
-- a reward cell - and never draws the pick label, the per-option rating or the
-- headline, which is most of what this tab says. So two rewards are put on it
-- through the stub, in Blizzard's documented WeeklyRewardActivityRewardInfo
-- shape, exactly as `spec/vaultpanel_spec.lua` does: one whose exact key the
-- committed export really ranked, so the rated words are drawn, and one nothing
-- ranked, so the honesty phrase is drawn beside it.
local COVERED_ITEM = {
    id = 251153,
    bonusIDs = { 13440, 6652, 13662, 12699, 12835 },
    name = "Arctic Explorer's Legwraps",
}

local function itemLink(itemID, bonusIDs, name)
    local fields = {}
    for _ = 2, 12 do
        fields[#fields + 1] = ""
    end
    fields[#fields + 1] = tostring(#bonusIDs)
    for _, bonus in ipairs(bonusIDs) do
        fields[#fields + 1] = tostring(bonus)
    end
    return string.format("|cffa335ee|Hitem:%d:%s|h[%s]|h|r", itemID, table.concat(fields, ":"), name)
end

local function generateReward(world, activityIndex, itemID, bonusIDs, name, itemLevel)
    local link = itemLink(itemID, bonusIDs, name)
    local dbid = "vault-" .. tostring(activityIndex)
    world.vault.activities[activityIndex].rewards = {
        { type = 1, id = itemID, quantity = 1, itemDBID = dbid },
    }
    world.vault.links[dbid] = link
    world.items[link] = {
        level = itemLevel,
        detailed = { itemLevel, false, itemLevel, n = 3 },
        info = { name, link, 4, itemLevel, n = 4 },
        instant = { itemID, "Armor", "Cloth", "INVTYPE_LEGS", nil, 4, 8, n = 7 },
    }
    world.vault.hasAvailable = true
    return link
end

local function withFixtures(ns, world)
    R.inventory(world, R.snapshot("inventory", 1))
    world.bankOpen = true
    R.vault(world, R.snapshot("vault", 3, R.JOURNAL))
    generateReward(world, 1, COVERED_ITEM.id, COVERED_ITEM.bonusIDs, COVERED_ITEM.name, 298)
    generateReward(world, 2, 999001, { 1234 }, "Unranked Boots", 301)
    ns.db.global.captures.journal = { R.snapshot("journal", 1, R.JOURNAL) }
end

describe("the source-free voice (V-1, WKE-569)", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("says nothing of a source on any of the three tabs, over the committed fixtures", function()
        local c = collector()
        withFixtures(ns, world)
        local frame = ns.UI.Frame()
        frame.pasteBox:SetText(readFile(QE_EXPORT))
        frame.importButton:Click()
        frame.pasteBox:SetText(readFile(UF_EXPORT))
        frame.importButton:Click()

        for index, tab in ipairs(frame.tabs) do
            tab:Click()
            c.check("tab " .. index .. " label", tab:GetText())
        end

        -- Equip Now: the answer, the bar's key, the fold, the hint, the note,
        -- the counts and every row's words - the text model's and the drawn
        -- row's, which since M5-1b (WKE-610) are two different sets of strings.
        local equip = frame.equipPanel
        c.check("EquipNow.answer", equip.answer:GetText())
        c.check("EquipNow.answerText", ns.UI.EquipPanel.AnswerText(equip.match))
        c.check("EquipNow.allBest", ns.UI.EquipPanel.ANSWER_ALL_BEST)
        c.check("EquipNow.nothingRated", ns.UI.EquipPanel.ANSWER_NOTHING_RATED)
        c.check("EquipNow.barKey", equip.barKey:GetText())
        c.check("EquipNow.fold", equip.fold.text:GetText())
        c.check("EquipNow.foldText", ns.UI.EquipPanel.FoldText(15, 20))
        c.check("EquipNow.foldAll", ns.UI.EquipPanel.FoldText(20, 20))
        c.check("EquipNow.hint", equip.hintText)
        c.check("EquipNow.note", ns.UI.EquipPanel.NoteText(equip.match))
        for _, chip in ipairs(ns.UI.EquipPanel.Chips(equip.match) or {}) do
            c.check("EquipNow.chip", chip.label)
            c.check("EquipNow.chip", chip.text)
        end
        for _, entry in ipairs(ns.UI.EquipPanel.Bar(equip.match).key) do
            c.check("EquipNow.barKey.entry", entry.text)
        end
        for _, row in ipairs(equip.match and equip.match.rows or {}) do
            local line = ns.UI.EquipPanel.Describe(row)
            c.check("EquipNow.row.text", line.text)
            c.check("EquipNow.row.note", line.note)
            c.check("EquipNow.row.second", line.second)
            c.check("EquipNow.row.badge", line.badge and line.badge.text)
            local drawn = ns.UI.EquipPanel.Drawn(row, equip.match)
            c.check("EquipNow.drawn.second", drawn.second)
            c.check("EquipNow.drawn.note", drawn.note)
            c.check("EquipNow.drawn.verb", drawn.verb)
        end
        for _, reason in ipairs(equip.match and equip.match.fallbacks or {}) do
            c.check("EquipNow.fallback", reason)
        end
        c.check("EquipNow.excluded", ns.UI.EquipPanel.ExcludedText(equip.match))
        for _, line in ipairs(ns.UI.EquipPanel.ExcludedLines(equip.match) or {}) do
            c.check("EquipNow.excludedLine", line)
        end

        -- Upgrade Map: both modes, as lines and as the drawn elements.
        local map = frame.upgradeMapPanel
        for _, line in ipairs(ns.UpgradeMapPanel.Lines(map.model) or {}) do
            c.check("UpgradeMap.line", line)
        end
        for _, element in ipairs(map.elements or {}) do
            c.check("UpgradeMap.element.text", element.text)
            if element.row then
                c.check("UpgradeMap.element.row.value", element.row.value)
                c.check("UpgradeMap.element.row.badge", element.row.badge and element.row.badge.text)
                c.check("UpgradeMap.element.row.note", element.row.badge and element.row.badge.note)
            end
        end
        -- The other view of the same map, under both of its sorts.
        for _, sort in ipairs(ns.UpgradeMapPanel.SORTS) do
            ns.UpgradeMapPanel.Refresh(map, { mode = ns.UpgradeMapPanel.MODE_RUN, runSort = sort })
            for _, line in ipairs(ns.UpgradeMapPanel.RunLines(map.model) or {}) do
                c.check("UpgradeMap.runLine", line)
            end
        end
        ns.UpgradeMapPanel.Refresh(map, { mode = ns.UpgradeMapPanel.MODE_SLOT })

        -- The Vault, as lines and as the grid's cells.
        local vault = frame.vaultPanel
        for _, line in ipairs(ns.VaultPanel.Lines(vault.model) or {}) do
            c.check("Vault.line", line)
        end
        local grid = vault.model and vault.model.grid or { rows = {} }
        for _, row in ipairs(grid.rows or {}) do
            c.check("Vault.grid.row.label", row.label)
            for _, cell in ipairs(row.cells or {}) do
                c.check("Vault.cell.text", cell.text)
                c.check("Vault.cell.second", cell.second)
                c.check("Vault.cell.verdictText", cell.verdictText)
                c.check("Vault.cell.thresholdText", cell.thresholdText)
                c.check("Vault.cell.footer", cell.footer)
                c.check("Vault.cell.moreText", cell.moreText)
                c.check("Vault.cell.label", cell.label)
                for _, tag in ipairs(cell.tags or {}) do
                    c.check("Vault.cell.tag", type(tag) == "table" and tag.text or tag)
                end
                for _, line in ipairs(cell.tooltipLines or {}) do
                    c.check("Vault.cell.tooltip", type(line) == "table" and line.text or line)
                end
            end
        end
        c.check("Vault.grid.otherOptions", grid.otherText)

        c.report(1200)
    end)

    it("says nothing of a source on the status strip, its tooltip or the import dialog", function()
        local c = collector()
        withFixtures(ns, world)
        local frame = ns.UI.Frame()

        -- Before any import, and after each one: three states of the strip.
        local function strip(where)
            local model = ns.UI.RefreshStrip(frame)
            c.check(where .. ".text", model.text)
            for _, line in ipairs(model.tooltip or {}) do
                c.check(where .. ".tooltip", line)
            end
        end
        strip("strip.empty")
        frame.pasteBox:SetText(readFile(QE_EXPORT))
        frame.importButton:Click()
        strip("strip.topGear")
        frame.pasteBox:SetText(readFile(UF_EXPORT))
        frame.importButton:Click()
        strip("strip.upgradeFinder")

        c.check("strip.NO_VERDICT_STRIP", ns.UI.NO_VERDICT_STRIP)
        c.check("strip.STALE_STRIP_TOOLTIP", ns.UI.STALE_STRIP_TOOLTIP)
        c.check("window.verdictNote", ns.UI.VerdictNoteText())

        -- The dialog the player pastes into.
        ns.UI.ToggleImportDialog()
        local dialog = frame.importDialog
        c.check("dialog.title", dialog.TitleText and dialog.TitleText:GetText())
        c.check("dialog.instructions", dialog.pasteLabel:GetText())
        c.check("dialog.import", dialog.importButton:GetText())
        c.check("dialog.clear", dialog.clearButton:GetText())
        dialog.pasteBox:SetText("not json at all")
        dialog.importButton:Click()
        c.check("dialog.status", dialog.status and dialog.status:GetText())

        c.report(19)
    end)

    it("says nothing of a source in any refusal the paste path can produce", function()
        local c = collector()
        -- The paste path is the ONE place a file format is named, because the
        -- player is holding that file. It names the export, never the site.
        local bad = {
            "",
            "   ",
            "not json at all",
            "1234",
            '"a string"',
            "{}",
            '{"schema":"something-else","version":1}',
            '{"schema":"qe-live-droptimizer","version":99}',
            '{"schema":"qe-live-droptimizer","version":1}',
            '{"schema":"qe-live-droptimizer","version":1,"topSet":{},"player":{"gameType":"nope"}}',
        }
        for _, importer in ipairs({ "QEImport", "UFImport" }) do
            for _, text in ipairs(bad) do
                local result = ns[importer].Parse(text)
                c.check(importer .. ".refusal", result.reason)
            end
            c.check(importer .. ".store", ns[importer].Store(nil).reason)
            c.check(importer .. ".store", ns[importer].Store({}).reason)
        end

        -- Match's own refusals and its key-fallback reasons.
        c.check("Match.refusal", ns.Match.Build(nil, nil).reason)
        c.check("Match.refusal", ns.Match.Build({ ok = false, reason = "the bank is shut" }, nil).reason)
        c.check("Match.refusal", ns.Match.Build({ ok = true, records = {} }, nil).reason)

        c.report(25)
    end)

    it("says nothing of a source in the slash help, /lootpath status or Options", function()
        local c = collector()
        withFixtures(ns, world)
        ns.HandleSlash("help")
        ns.HandleSlash("status")
        for line in tostring(world.output()):gmatch("[^\n]+") do
            c.check("chat", line)
        end

        walkStrings(c.check, "Options", ns.UI.Options)
        -- 29 until R-2 (WKE-563) removed R-0's `/lootpath spike` help line with
        -- the module it drove.
        c.report(28)
    end)

    it("says nothing of a source in any panel's string table", function()
        local c = collector()
        walkStrings(c.check, "EquipPanel", ns.UI.EquipPanel)
        walkStrings(c.check, "UpgradeMapPanel", ns.UpgradeMapPanel)
        walkStrings(c.check, "VaultPanel", ns.VaultPanel)
        walkStrings(c.check, "Roads", ns.Roads)
        walkStrings(c.check, "ItemLine", ns.UI.ItemLine)
        -- Surface 1's own words (R-2, WKE-563): the tooltip block's header,
        -- sub-header and last line, and what the status strip says about which
        -- bag window the mark is drawn in.
        walkStrings(c.check, "Tooltip", ns.UI.Tooltip)
        walkStrings(c.check, "Bags", ns.UI.Bags)
        walkStrings(c.check, "Bags.Blizzard", ns.UI.Bags.Blizzard)
        walkStrings(c.check, "Bags.Baganator", ns.UI.Bags.Baganator)
        -- The importers' and Match's own pinned wording, alongside the
        -- refusals exercised above.
        walkStrings(c.check, "UFImport", ns.UFImport)
        c.report(160)
    end)
end)
