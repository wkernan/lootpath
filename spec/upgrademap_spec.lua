-- spec/upgrademap_spec.lua (M3-3, WKE-524)
-- The Upgrade Map panel over the committed fixtures: the 2026-09-06 journal
-- walk, the 2026-09-05 inventory transcript, and the genuine QE Live Top Gear
-- export WKE-519 committed.
--
-- The rule under test is the values-free one. Every "no number" assertion below
-- is proven red by handing the same model a verdict that DOES cover a row and
-- watching the number appear, so a passing suite means the rule holds rather
-- than that the panel is empty.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local QE_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"

-- Pinned here as well as in the module: a pending drop is unknown, not zero.
local PENDING_WORDING = "%d drops are not identified yet: their item data had not arrived. Unknown, not item level 0."

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

-- The real export, parsed. Restoration Druid, Raid content, 15 equipped items,
-- no differentials and no vault items (see spec/fixtures/qe/README.md).
local function realVerdict(ns)
    local parsed = ns.QEImport.Parse(readFile(QE_EXPORT))
    assert(parsed.ok, parsed.reason)
    return parsed.verdict
end

-- A verdict built from the export's own header but carrying `key` in its top
-- set, so the covered path can be exercised with a key the journal map really
-- holds. Nothing here invents a QE Live number: the top-set branch shows words
-- and no delta, and the alternative branch is given the deltas explicitly.
local function verdictCovering(ns, key, alternative)
    local verdict = realVerdict(ns)
    local itemID, bonus = key:match("^(%d+):?(.*)$")
    local bonusIDs = {}
    for id in (bonus or ""):gmatch("%d+") do
        bonusIDs[#bonusIDs + 1] = tonumber(id)
    end
    local item = {
        key = key,
        itemID = tonumber(itemID),
        bonusIDs = bonusIDs,
        level = 305,
        slot = "Feet",
        count = 1,
        isVault = false,
        isExclusive = false,
        gems = {},
        setId = 0,
    }
    if alternative then
        verdict.alternatives = {
            {
                scorePercent = alternative.scorePercent,
                hpsDifference = alternative.hpsDifference,
                items = { item },
                gems = {},
            },
        }
    else
        verdict.topSet.items[key] = item
        verdict.topSet.order[#verdict.topSet.order + 1] = key
    end
    return verdict
end

local function loadMap(ns)
    local snapshot = R.snapshot("journal", 1, R.JOURNAL)
    local sources, summary = ns.Journal:Build({ snapshot = snapshot })
    assert(summary.ok, "journal build failed")
    return sources, summary, snapshot
end

local function loadInventory(ns, world)
    R.inventory(world, R.snapshot("inventory", 1))
    local scan = ns.Inventory.Scan()
    assert(scan.ok, scan.reason)
    return scan
end

local function everyCandidate(model)
    local rows = {}
    for _, section in ipairs(model.slots) do
        for _, row in ipairs(section.candidates) do
            rows[#rows + 1] = row
        end
    end
    for _, row in ipairs(model.pending.rows) do
        rows[#rows + 1] = row
    end
    return rows
end

local function findRow(model, itemID, difficultyID)
    for _, row in ipairs(everyCandidate(model)) do
        if row.itemID == itemID and (difficultyID == nil or row.difficultyID == difficultyID) then
            return row
        end
    end
    return nil
end

describe("UpgradeMapPanel model over the committed walk", function()
    local ns, world, sources, summary, inventory

    before_each(function()
        ns, world = H.load()
        sources, summary = loadMap(ns)
        inventory = loadInventory(ns, world)
    end)

    after_each(function()
        H.unload()
    end)

    it("pins the note wording the decision fixed", function()
        assert.equal(
            "Values shown are QE Live's, for items it has ranked. Other drops are listed by item level only.",
            ns.UpgradeMapPanel.NOTE
        )
        assert.equal(ns.UpgradeMapPanel.NOTE, ns.UpgradeMapPanel.Model({ sources = sources }).note)
    end)

    it("files every candidate under a slot, or under the unidentified list", function()
        local model = ns.UpgradeMapPanel.Model({
            sources = sources,
            summary = summary,
            inventory = inventory,
            verdict = realVerdict(ns),
        })
        assert.is_true(model.hasMap)
        assert.equal(summary.sources, model.counts.candidates)
        local filed = 0
        for _, section in ipairs(model.slots) do
            filed = filed + #section.candidates
        end
        -- Every source is filed, listed as unidentified, or hidden at item
        -- level 1 and counted (WKE-530 finding 4). Nothing is dropped.
        assert.equal(summary.sources, filed + model.pending.count + model.counts.hiddenLevelOne)
        -- The slots come out in the character-sheet order, never sorted by name.
        local order = {}
        for _, section in ipairs(model.slots) do
            order[#order + 1] = section.slot
        end
        local expected = {}
        for _, slot in ipairs(ns.UpgradeMapPanel.SLOT_ORDER) do
            for _, section in ipairs(model.slots) do
                if section.slot == slot then
                    expected[#expected + 1] = slot
                end
            end
        end
        assert.same(expected, order)
    end)

    it("sorts a slot's candidates by item level, descending", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local checked = 0
        for _, section in ipairs(model.slots) do
            for i = 2, #section.candidates do
                assert.is_true((section.candidates[i - 1].itemLevel or 0) >= (section.candidates[i].itemLevel or 0))
                checked = checked + 1
            end
        end
        assert.is_true(checked > 0)
    end)

    it("shows the equipped item for a slot beside its candidates", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, inventory = inventory })
        local feet
        for _, section in ipairs(model.slots) do
            if section.slot == "Feet" then
                feet = section
            end
        end
        assert.is_not_nil(feet)
        assert.equal(1, #feet.equipped)
        -- Measured from the 2026-09-05 transcript through ns.Inventory.
        assert.equal("Breakwater Boots", feet.equipped[1].name)
        assert.equal(295, feet.equipped[1].itemLevel)
    end)

    it("marks a drop the character already owns without ranking it", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, inventory = inventory })
        -- Measured: three itemIDs appear in both the 09-06 map and the 09-05
        -- inventory - 268247 Feet (equipped, 295), 251136 Finger (equipped,
        -- 282) and 273796 Trinket (in a bag, 282).
        local ownedIDs = {}
        for _, row in ipairs(everyCandidate(model)) do
            if row.owned then
                ownedIDs[row.itemID] = true
            end
        end
        local distinct = 0
        for _ in pairs(ownedIDs) do
            distinct = distinct + 1
        end
        assert.equal(3, distinct)
        local row = findRow(model, 268247)
        assert.is_true(row.owned)
        assert.equal(295, row.ownedItemLevel)
        -- Ownership is a fact, never a value: it puts no number from QE Live on
        -- the row.
        assert.is_nil(row.qe)
        assert.is_nil(row.value)
    end)
end)

describe("UpgradeMapPanel is values-free", function()
    local ns, world, sources, summary, inventory

    before_each(function()
        ns, world = H.load()
        sources, summary = loadMap(ns)
        inventory = loadInventory(ns, world)
    end)

    after_each(function()
        H.unload()
    end)

    it("puts no number on any candidate the real export does not cover", function()
        local model = ns.UpgradeMapPanel.Model({
            sources = sources,
            summary = summary,
            inventory = inventory,
            verdict = realVerdict(ns),
        })
        -- Measured 2026-09-06: every keyed journal row carries exactly one bonus
        -- ID (3524) while every item in the export carries two to seven, so no
        -- key can match and the whole map renders values-free.
        assert.equal(0, model.counts.covered)
        for _, row in ipairs(everyCandidate(model)) do
            assert.is_nil(row.qe)
            assert.is_nil(row.value)
        end
        for _, line in ipairs(ns.UpgradeMapPanel.Lines(model)) do
            assert.is_nil(line:find("QE Live: "), "a values-free map rendered a value: " .. line)
        end
    end)

    it("shares an itemID with the export and still shows no number, because the keys differ", function()
        local verdict = realVerdict(ns)
        -- Measured: itemID 251153 (Arctic Explorer's Legwraps, Feet) is in both
        -- the export's top set and the journal map. The export's copy carries
        -- five bonus IDs; the map's row carries one.
        local exportKey = ns.ItemKey(251153, { 13440, 6652, 13662, 12699, 12835 })
        assert.is_not_nil(verdict.topSet.items[exportKey])
        assert.equal("251153:3524", sources[251153][1].itemKey)
        assert.is_not.equal(exportKey, sources[251153][1].itemKey)

        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, verdict = verdict })
        local row = findRow(model, 251153)
        assert.equal("Feet", row.slot)
        assert.is_nil(row.qe)
        assert.is_nil(row.value)
    end)

    -- The red proof for both assertions above: the same map, the same panel, a
    -- verdict that covers one exact key, and the number appears on that row and
    -- on no other.
    it("shows QE Live's delta on the exact key it covers, and nowhere else", function()
        local key = sources[251153][1].itemKey
        local verdict = verdictCovering(ns, key, { scorePercent = -1.5, hpsDifference = 1234.5 })
        local model =
            ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, inventory = inventory, verdict = verdict })
        local covered, uncovered = 0, 0
        for _, row in ipairs(everyCandidate(model)) do
            if row.value then
                covered = covered + 1
                assert.equal(key, row.itemKey)
                assert.equal("QE Live: better by 1.50% (+1234.5 score)", row.value)
            else
                uncovered = uncovered + 1
            end
        end
        -- Three rows share that key: Heroic, Mythic+ and Mythic.
        assert.equal(3, covered)
        assert.equal(3, model.counts.covered)
        assert.is_true(uncovered > 500)
        local rendered = 0
        for _, line in ipairs(ns.UpgradeMapPanel.Lines(model)) do
            if line:find("QE Live: better by 1.50", 1, true) then
                rendered = rendered + 1
            end
        end
        assert.equal(3, rendered)
    end)

    it("reads the direction from QE Live's sign convention, not from arithmetic", function()
        local key = sources[251153][1].itemKey
        -- Positive scorePercent means the alternative is WORSE (pinned in
        -- QEImport from QE Live's own source).
        local worse = ns.UpgradeMapPanel.Model({
            sources = sources,
            summary = summary,
            verdict = verdictCovering(ns, key, { scorePercent = 2.25, hpsDifference = -900 }),
        })
        assert.equal("QE Live: worse by 2.25% (-900.0 score)", findRow(worse, 251153).value)
        local better = ns.UpgradeMapPanel.Model({
            sources = sources,
            summary = summary,
            verdict = verdictCovering(ns, key, { scorePercent = -2.25, hpsDifference = 900 }),
        })
        assert.equal("QE Live: better by 2.25% (+900.0 score)", findRow(better, 251153).value)
    end)

    it("says a top-set item is in the best set and gives it no number", function()
        local key = sources[251153][1].itemKey
        local model = ns.UpgradeMapPanel.Model({
            sources = sources,
            summary = summary,
            verdict = verdictCovering(ns, key),
        })
        local row = findRow(model, 251153)
        assert.equal("topSet", row.qe.where)
        assert.equal("QE Live: in your best set", row.value)
        assert.is_nil(row.qe.scorePercent)
        assert.is_nil(row.qe.hpsDifference)
    end)
end)

describe("UpgradeMapPanel and rows whose item data never arrived", function()
    local ns, sources, summary

    before_each(function()
        ns = H.load()
        sources, summary = loadMap(ns)
    end)

    after_each(function()
        H.unload()
    end)

    it("lists a pending drop as unknown, never as item level 0", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        assert.is_true(model.pending.count > 0)
        local filed = 0
        for _, section in ipairs(model.slots) do
            filed = filed + #section.candidates
        end
        assert.equal(summary.sources - model.pending.count - model.counts.hiddenLevelOne, filed)
        for _, row in ipairs(model.pending.rows) do
            assert.is_true(row.pending)
            assert.is_nil(row.itemLevel)
            assert.is_nil(row.slot)
            assert.is_nil(row.itemKey)
        end
        assert.equal(PENDING_WORDING, ns.UpgradeMapPanel.PENDING_NOTE)
        assert.equal(string.format(PENDING_WORDING, model.pending.count), model.pending.note)
        local lines = ns.UpgradeMapPanel.Lines(model)
        local sawNote, sawZero = false, false
        for _, line in ipairs(lines) do
            if line:find("Unknown, not item level 0.", 1, true) then
                sawNote = true
            end
            if line:find("item data not arrived", 1, true) and line:find("(0)", 1, true) then
                sawZero = true
            end
        end
        assert.is_true(sawNote)
        assert.is_false(sawZero)
    end)

    it("says so plainly when there is no map at all", function()
        local model = ns.UpgradeMapPanel.Model({})
        assert.is_false(model.hasMap)
        -- The note is the header's, not the list's (WKE-530 finding 3).
        assert.equal(ns.UpgradeMapPanel.NOTE, model.note)
        assert.same({ ns.UpgradeMapPanel.EMPTY_NOTE }, ns.UpgradeMapPanel.Lines(model))
    end)
end)

describe("UpgradeMapPanel difficulty filter", function()
    local ns, world, sources, summary

    before_each(function()
        ns, world = H.load()
        sources, summary = loadMap(ns)
    end)

    after_each(function()
        H.unload()
    end)

    it("offers every difficulty the walk covered, with its row count", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local ids = {}
        for _, difficulty in ipairs(model.difficulties) do
            ids[#ids + 1] = difficulty.difficultyID
            assert.is_true(difficulty.selected)
        end
        -- The walk's plan: dungeons at Heroic (2), Mythic+ (8) and Mythic (23),
        -- raids at Heroic (15) and Mythic (16).
        assert.same({ 2, 8, 15, 16, 23 }, ids)
        local total = 0
        for _, difficulty in ipairs(model.difficulties) do
            total = total + difficulty.count
        end
        assert.equal(summary.sources, total)
    end)

    it("narrows the candidates to the difficulties asked for", function()
        local all = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local mythicPlus = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, difficultyIDs = { 8 } })
        assert.is_true(mythicPlus.counts.candidates < all.counts.candidates)
        for _, row in ipairs(everyCandidate(mythicPlus)) do
            assert.equal(8, row.difficultyID)
        end
        for _, difficulty in ipairs(mythicPlus.difficulties) do
            assert.equal(difficulty.difficultyID == 8, difficulty.selected)
        end
    end)

    it("labels the Mythic+ row with the keystone level the walk previewed", function()
        assert.equal(10, summary.previewMythicPlusLevel)
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local labels = {}
        for _, difficulty in ipairs(model.difficulties) do
            labels[difficulty.difficultyID] = difficulty.label
        end
        -- No GetDifficultyInfo in the stub world by default, so these are the
        -- module's own fallback names.
        assert.equal("Mythic+ 10", labels[8])
        assert.equal("Heroic dungeon", labels[2])
        assert.equal("Mythic raid", labels[16])
    end)

    it("prefers the client's own localised difficulty name when it has one", function()
        world.difficultyNames = { [8] = "Mythic Keystone", [2] = "Heroique" }
        assert.equal("Mythic Keystone 10", ns.UpgradeMapPanel.DifficultyLabel(8, 10))
        assert.equal("Heroique", ns.UpgradeMapPanel.DifficultyLabel(2, 10))
        -- and falls back when the client does not answer
        assert.equal("Mythic raid", ns.UpgradeMapPanel.DifficultyLabel(16, 10))
    end)
end)

describe("UpgradeMapPanel frames", function()
    local ns, world, snapshot

    before_each(function()
        ns, world = H.load()
        snapshot = select(3, loadMap(ns))
        loadInventory(ns, world)
        ns.db.global.captures.journal = { snapshot }
    end)

    after_each(function()
        H.unload()
    end)

    it("renders the model's lines into the panel's font strings", function()
        local frame = ns.UpgradeMapPanel.Create()
        local model = frame:Refresh()
        assert.is_not_nil(model)
        local lines = ns.UpgradeMapPanel.Lines(model)
        assert.is_true(#lines > 100)
        for i, line in ipairs(lines) do
            assert.equal(line, frame.rows[i]:GetText())
        end
        assert.equal(ns.UpgradeMapPanel.NOTE, frame.note:GetText())
    end)

    it("builds one filter button per difficulty plus All, and clicking one narrows the panel", function()
        local frame = ns.UpgradeMapPanel.Create()
        local model = frame:Refresh()
        assert.equal(#model.difficulties + 1, #frame.filterButtons)
        assert.equal("All", frame.filterButtons[#frame.filterButtons]:GetText())

        local mythicPlus
        for _, button in ipairs(frame.filterButtons) do
            if button:GetText():find("Mythic+ 10", 1, true) then
                mythicPlus = button
            end
        end
        assert.is_not_nil(mythicPlus)
        mythicPlus:Click()
        assert.same({ 8 }, frame.difficultyIDs)
        for _, row in ipairs(everyCandidate(frame.model)) do
            assert.equal(8, row.difficultyID)
        end
        frame.filterButtons[#frame.filterButtons]:Click()
        assert.is_nil(frame.difficultyIDs)
        assert.is_true(frame.model.counts.candidates > model.counts.candidates / 2)
    end)

    it("says why it is empty rather than rendering a map in combat", function()
        local frame = ns.UpgradeMapPanel.Create()
        world.inCombat = true
        frame:Refresh()
        assert.same({
            "Lootpath does not read the client in combat. Leave combat and reopen this panel.",
        }, frame.lines)
        -- and the header still says the one thing it always says
        assert.equal(ns.UpgradeMapPanel.NOTE, frame.note:GetText())
    end)

    it("points at the capture when no walk has been stored", function()
        ns.db.global.captures.journal = nil
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        assert.same({ ns.UpgradeMapPanel.EMPTY_NOTE }, frame.lines)
    end)
end)

-- ---------------------------------------------------------------------------
-- WKE-530 (M3-5): the four Upgrade Map findings from the owner's first in-game
-- run of the whole window, 2026-09-06. Each one is a thing the panel did on
-- screen, so each test below fails on the code as it stood before this issue.

describe("UpgradeMapPanel difficulty labels (WKE-530 finding 1)", function()
    local ns, world, sources, summary

    -- What the client actually answered, read off the filter row in the
    -- 2026-09-06 screenshots: GetDifficultyInfo hands back the bare localised
    -- word, so dungeon Heroic (2) and raid Heroic (15) are both "Heroic", and
    -- dungeon Mythic (23) and raid Mythic (16) are both "Mythic".
    local AMBIGUOUS = { [2] = "Heroic", [15] = "Heroic", [23] = "Mythic", [16] = "Mythic", [8] = "Mythic Keystone" }

    before_each(function()
        ns, world = H.load()
        sources, summary = loadMap(ns)
    end)

    after_each(function()
        H.unload()
    end)

    it("gives no two difficulties in one map the same label, even when the client does", function()
        world.difficultyNames = AMBIGUOUS
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local byLabel = {}
        for _, difficulty in ipairs(model.difficulties) do
            assert.is_nil(byLabel[difficulty.label], "two difficulties share the label " .. difficulty.label)
            byLabel[difficulty.label] = difficulty.difficultyID
        end
        -- The colliding pairs fall back to the qualified names the module
        -- already carried; the M+ row keeps the client's word and its level.
        assert.equal(2, byLabel["Heroic dungeon"])
        assert.equal(15, byLabel["Heroic raid"])
        assert.equal(23, byLabel["Mythic dungeon"])
        assert.equal(16, byLabel["Mythic raid"])
        assert.equal(8, byLabel["Mythic Keystone 10"])
    end)

    it("labels a candidate row exactly as the button that filters to it", function()
        world.difficultyNames = AMBIGUOUS
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local byID = {}
        for _, difficulty in ipairs(model.difficulties) do
            byID[difficulty.difficultyID] = difficulty.label
        end
        local checked = 0
        for _, row in ipairs(everyCandidate(model)) do
            assert.equal(byID[row.difficultyID], row.difficultyLabel)
            checked = checked + 1
        end
        assert.is_true(checked > 200)
    end)

    it("keeps the client's own localised name wherever nothing else shares it", function()
        world.difficultyNames = { [2] = "Heroique", [15] = "Heroique de raid", [8] = "Cle mythique" }
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local byID = {}
        for _, difficulty in ipairs(model.difficulties) do
            byID[difficulty.difficultyID] = difficulty.label
        end
        assert.equal("Heroique", byID[2])
        assert.equal("Heroique de raid", byID[15])
        assert.equal("Cle mythique 10", byID[8])
        -- and the ones the client did not name still use the fallbacks
        assert.equal("Mythic raid", byID[16])
        assert.equal("Mythic dungeon", byID[23])
    end)

    it("falls back to the difficulty ID when even the qualified names collide", function()
        -- No entry in DIFFICULTY_NAME for 900 or 901, so the qualified fallback
        -- cannot separate them and the ID is the last word.
        world.difficultyNames = { [900] = "Brutal", [901] = "Brutal" }
        local labels = ns.UpgradeMapPanel.DifficultyLabels({ 900, 901 })
        assert.equal("Brutal (difficulty 900)", labels[900])
        assert.equal("Brutal (difficulty 901)", labels[901])
    end)

    it("does not rename the buttons when a filter is applied", function()
        world.difficultyNames = AMBIGUOUS
        local all = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local filtered = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, difficultyIDs = { 2 } })
        assert.equal(#all.difficulties, #filtered.difficulties)
        for i, difficulty in ipairs(all.difficulties) do
            assert.equal(difficulty.label, filtered.difficulties[i].label)
        end
    end)
end)

describe("UpgradeMapPanel filter row layout (WKE-530 finding 2)", function()
    local ns, world, snapshot

    before_each(function()
        ns, world = H.load()
        snapshot = select(3, loadMap(ns))
        loadInventory(ns, world)
        ns.db.global.captures.journal = { snapshot }
    end)

    after_each(function()
        H.unload()
    end)

    it("packs a row only as far as the width allows, then starts another", function()
        local Panel = ns.UpgradeMapPanel
        local labels = { "Heroic dungeon (67)", "Mythic+ 10 (54)", "Heroic raid (38)", "Mythic raid (39)" }
        assert.equal(1, Panel.FilterLayout(labels, 5000).rows)
        assert.is_true(Panel.FilterLayout(labels, 260).rows > 1)
        for _, width in ipairs({ 260, 400, 530 }) do
            local layout = Panel.FilterLayout(labels, width)
            local used = {}
            for _, placement in ipairs(layout.buttons) do
                used[placement.row] = (used[placement.row] or -Panel.FILTER_BUTTON_GAP)
                    + Panel.FILTER_BUTTON_GAP
                    + placement.width
            end
            for row, total in pairs(used) do
                assert.is_true(total <= width, string.format("row %d ran to %d in %d points", row, total, width))
            end
        end
    end)

    it("wraps the real filter row instead of running off the frame", function()
        local frame = ns.UpgradeMapPanel.Create()
        local model = frame:Refresh()
        -- Measured over the committed walk: five difficulties plus All, whose
        -- labels come out 134, 110, 116, 116, 134 and 60 points wide - 690
        -- points of buttons plus gaps, which cannot fit the frame's 560. In
        -- game on 2026-09-06 the fifth was clipped at the window's edge.
        assert.equal(6, #frame.filterButtons)
        assert.equal(#model.difficulties + 1, #frame.filterButtons)
        assert.is_true(frame.filterRows > 1)
        local used = {}
        for _, placement in ipairs(frame.filterLayout.buttons) do
            used[placement.row] = (used[placement.row] or 0) + placement.width + ns.UpgradeMapPanel.FILTER_BUTTON_GAP
        end
        for row, total in pairs(used) do
            assert.is_true(total <= frame:GetWidth(), string.format("filter row %d is %d wide", row, total))
        end
    end)

    it("anchors the first button of a wrapped row below the row above it", function()
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        local firstOfSecondRow
        for index, placement in ipairs(frame.filterLayout.buttons) do
            if placement.row == 2 and placement.column == 1 then
                firstOfSecondRow = index
            end
        end
        assert.is_not_nil(firstOfSecondRow)
        -- Re-anchored on every refresh, so the only point on it is this one.
        local button = frame.filterButtons[firstOfSecondRow]
        assert.equal(1, #button.points)
        assert.equal("TOPLEFT", button.points[1][1])
        assert.equal(frame.filterButtons[1], button.points[1][2])
        assert.equal("BOTTOMLEFT", button.points[1][3])
        -- and the list starts below every filter row, not under the second one
        local scrollPoint = frame.scroll.points[1]
        assert.equal(frame.filterLabel, scrollPoint[2])
        assert.is_true(scrollPoint[5] <= -(frame.filterRows * ns.UpgradeMapPanel.FILTER_ROW_HEIGHT))
    end)
end)

describe("UpgradeMapPanel draws the pinned note once (WKE-530 finding 3)", function()
    local ns, world, snapshot

    before_each(function()
        ns, world = H.load()
        snapshot = select(3, loadMap(ns))
        loadInventory(ns, world)
        ns.db.global.captures.journal = { snapshot }
    end)

    after_each(function()
        H.unload()
    end)

    local function noteCount(frame)
        local seen = 0
        if frame.note:GetText():find(ns.UpgradeMapPanel.NOTE, 1, true) then
            seen = seen + 1
        end
        for _, text in ipairs(frame.rows) do
            if text:GetText():find(ns.UpgradeMapPanel.NOTE, 1, true) then
                seen = seen + 1
            end
        end
        return seen
    end

    it("puts it in the header and never in the list", function()
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        assert.equal(1, noteCount(frame))
        assert.equal(ns.UpgradeMapPanel.NOTE, frame.note:GetText())
        -- The model still carries it, which is what pins the wording headlessly.
        assert.equal(ns.UpgradeMapPanel.NOTE, frame.model.note)
    end)

    it("still says it once when the map is empty, and once in combat", function()
        ns.db.global.captures.journal = nil
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        assert.equal(1, noteCount(frame))
        world.inCombat = true
        frame:Refresh()
        assert.equal(1, noteCount(frame))
    end)
end)

describe("UpgradeMapPanel hides drops at item level 1 (WKE-530 finding 4)", function()
    local ns, sources, summary

    before_each(function()
        ns = H.load()
        -- The warm-cache walk of 2026-09-06 20:04, whose rows the finding was
        -- measured over: no pending rows at all, so every item level in it is
        -- one the client answered.
        local snapshot = R.snapshot("journal", R.JOURNAL_TWO_READ_WARM, R.JOURNAL_TWO_READ)
        sources, summary = ns.Journal:Build({ snapshot = snapshot })
        assert(summary.ok, "journal build failed")
    end)

    after_each(function()
        H.unload()
    end)

    it("keeps no candidate at item level 1, and counts the ones it hid", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        -- Measured over this transcript: 265 sources, none pending, of which 5
        -- came back at item level 1 - all of them Head - and 12 at level 44.
        assert.equal(265, summary.sources)
        assert.equal(0, model.pending.count)
        assert.equal(5, model.counts.hiddenLevelOne)
        for _, section in ipairs(model.slots) do
            for _, row in ipairs(section.candidates) do
                assert.is_not.equal(ns.UpgradeMapPanel.HIDDEN_ITEM_LEVEL, row.itemLevel)
            end
        end
        local head, hidden = nil, 0
        for _, section in ipairs(model.slots) do
            hidden = hidden + section.hiddenLevelOne
            if section.slot == "Head" then
                head = section
            end
        end
        assert.equal(5, hidden)
        assert.equal(5, head.hiddenLevelOne)
        assert.equal("5 drops at item level 1 hidden: cosmetic and quest items", head.hiddenNote)
    end)

    it("says so at the end of the slot it hid them from", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        local lines = ns.UpgradeMapPanel.Lines(model)
        local headAt, noteAt, nextSlotAt
        for i, line in ipairs(lines) do
            if line == "Head" then
                headAt = i
            elseif line == "  5 drops at item level 1 hidden: cosmetic and quest items" then
                noteAt = i
            elseif headAt and not nextSlotAt and i > headAt and not line:find("^  ") then
                nextSlotAt = i
            end
        end
        assert.is_not_nil(headAt)
        assert.is_not_nil(noteAt)
        assert.is_true(noteAt > headAt)
        assert.equal(noteAt + 1, nextSlotAt)
    end)

    it("hides on exactly 1 and on no other threshold", function()
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        assert.equal(1, ns.UpgradeMapPanel.HIDDEN_ITEM_LEVEL)
        local at44, lowest = 0, math.huge
        for _, section in ipairs(model.slots) do
            for _, row in ipairs(section.candidates) do
                if row.itemLevel == 44 then
                    at44 = at44 + 1
                end
                lowest = math.min(lowest, row.itemLevel)
            end
        end
        -- The 12 rows the client answered 44 for are real loot and are shown.
        assert.equal(12, at44)
        assert.equal(44, lowest)
    end)
end)

-- Its own load, because ns.Journal:Build memoises per item across snapshots
-- (the cache is keyed on the build number, ARCHITECTURE.md 7), so a walk built
-- after the warm one in the same session would inherit its item levels.
describe("UpgradeMapPanel and a walk whose rows never arrived (WKE-530 finding 4)", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("never hides a pending row, because unknown is not item level 1", function()
        -- The 16:11 walk carries 369 rows whose item data never arrived.
        local sources, summary = ns.Journal:Build({ snapshot = R.snapshot("journal", 1, R.JOURNAL) })
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        assert.equal(369, model.pending.count)
        for _, row in ipairs(model.pending.rows) do
            assert.is_nil(row.itemLevel)
        end
        -- A hidden row is still a candidate: the map keeps the fact and only
        -- the panel declines to list it.
        assert.equal(summary.sources, model.counts.candidates)
        assert.equal(2, model.counts.hiddenLevelOne)
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-6 (WKE-535): the Upgrade Finder join. Its own loads, because
-- ns.Journal:Build memoises a walk per build number and a second snapshot built
-- in the same session would inherit the first one's rows.

local UF_DUNGEON = "spec/fixtures/qe/qe-upgradefinder-Hotornot-abxrrnezfilt.json"
local UF_SAMPLE = "spec/fixtures/qe/sample-upgradefinder-v1.json"

local function upgrades(ns, path)
    local result = ns.UFImport.Parse(readFile(path or UF_DUNGEON))
    assert(result.ok, result.reason)
    return result.verdict
end

-- The 2026-09-06 20:09 cold-cache walk, which is the one whose rows all
-- arrived (0 pending): the join is measured over a complete map.
local function coldWalk(ns)
    local snapshot = R.snapshot("journal", R.JOURNAL_TWO_READ_COLD, R.JOURNAL_TWO_READ)
    local sources, summary = ns.Journal:Build({ snapshot = snapshot })
    assert(summary.ok, "journal build failed")
    return sources, summary
end

describe("UpgradeMapPanel without an Upgrade Finder export", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("changes nothing at all: no row gains a number and nothing is counted", function()
        local sources, summary = coldWalk(ns)
        local model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        assert.is_false(model.hasUpgrades)
        assert.equal(0, model.counts.ranked)
        assert.equal(0, model.counts.rankedAtAnotherLevel)
        assert.is_nil(model.levelMismatchNote)
        assert.same({}, model.upgradeLevelMismatches)
        for _, row in ipairs(everyCandidate(model)) do
            assert.is_nil(row.upgrade)
            assert.is_nil(row.upgradeValue)
        end
    end)
end)

describe("UpgradeMapPanel joined to the genuine Upgrade Finder export", function()
    local ns, sources, summary, model

    before_each(function()
        ns = H.load()
        sources, summary = coldWalk(ns)
        model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, upgrades = upgrades(ns) })
    end)

    after_each(function()
        H.unload()
    end)

    it("puts QE Live's number on the 30 rows he ranked at the level the journal shows", function()
        -- Measured over the committed pair: the 2026-09-06 20:09 cold walk (478
        -- sources) against the 2026-09-07 Dungeon export (315 entries).
        assert.is_true(model.hasUpgrades)
        assert.equal(478, model.counts.candidates)
        assert.equal(30, model.counts.ranked)
        local rows = 0
        for _, row in ipairs(everyCandidate(model)) do
            if row.upgradeValue then
                rows = rows + 1
                assert.is_not_nil(row.upgrade)
                assert.equal(row.itemLevel, row.upgrade.level)
                assert.equal(row.itemID, row.upgrade.itemID)
            else
                assert.is_nil(row.upgrade)
            end
        end
        assert.equal(30, rows)
    end)

    it("transports his percentage unchanged onto the row", function()
        -- Measured: 268205 (Venomancer's Winged Channeler, 2H Weapon) is in the
        -- walk at 324 from Vashnik the Malignant, and the export ranks it at
        -- 324 at 3.076%.
        local row = findRow(model, 268205)
        assert.equal(324, row.itemLevel)
        assert.equal(3.076, row.upgrade.upgradePercent)
        assert.equal("QE Live: better by 3.08%", row.upgradeValue)
    end)

    it("says no change where QE Live's number is zero, rather than a direction he did not give", function()
        -- Measured: 268248 (Amani Summoning Shawl, Back) at 318 is ranked 0.
        local row = findRow(model, 268248)
        assert.equal(0, row.upgrade.upgradePercent)
        assert.equal("QE Live: no change", row.upgradeValue)
    end)

    it("shows nothing for a drop he ranked at another item level, and counts it", function()
        -- Measured: 218 rows over 97 distinct drops sit at an item level the
        -- export does not carry - the Upgrade Finder assumed key level 7 while
        -- the walk previewed key level 10 (ARCHITECTURE.md 11).
        assert.equal(218, model.counts.rankedAtAnotherLevel)
        assert.equal(97, #model.upgradeLevelMismatches)
        for _, row in ipairs(everyCandidate(model)) do
            if row.rankedAtAnotherLevel then
                assert.is_nil(row.upgrade)
                assert.is_nil(row.upgradeValue)
                for _, level in ipairs(row.rankedAtAnotherLevel) do
                    assert.is_not.equal(row.itemLevel, level)
                end
            end
        end
        local first = model.upgradeLevelMismatches[1]
        assert.is_number(first.itemID)
        assert.is_true(first.rows >= 1)
        assert.is_true(#first.rankedLevels > 0)
    end)

    it("renders his value on the row's line and never the word HPS", function()
        local lines = ns.UpgradeMapPanel.Lines(model)
        local valued = 0
        for _, line in ipairs(lines) do
            if line:find("QE Live: better by", 1, true) or line:find("QE Live: no change", 1, true) then
                valued = valued + 1
            end
            assert.is_nil(line:find("HPS"), "a line named HPS: " .. line)
            assert.is_nil(line:find("hpsGain"), "a line leaked hpsGain: " .. line)
        end
        assert.equal(30, valued)
    end)

    it("says how many drops he ranked at another level, in the pinned wording", function()
        local note = string.format("%d drops are ranked by QE Live at another item level, so they show no value.", 218)
        assert.equal(note, model.levelMismatchNote)
        local found = false
        for _, line in ipairs(ns.UpgradeMapPanel.Lines(model)) do
            if line == note then
                found = true
            end
        end
        assert.is_true(found)
    end)
end)

describe("UpgradeMapPanel and the hand-built Upgrade Finder sample", function()
    local ns, sources, summary, model

    before_each(function()
        ns = H.load()
        sources, summary = coldWalk(ns)
        model = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary, upgrades = upgrades(ns, UF_SAMPLE) })
    end)

    after_each(function()
        H.unload()
    end)

    -- The real export ranks nothing below the current set, so the worse
    -- direction can only be proven over a hand-built file. This is the red
    -- proof for "better": flip the sign and the word changes.
    it("reads a negative percentage as worse, from the pinned sign and not from arithmetic", function()
        local row = findRow(model, 270162)
        assert.equal(318, row.itemLevel)
        assert.equal(-1.25, row.upgrade.upgradePercent)
        assert.equal("QE Live: worse by 1.25%", row.upgradeValue)
        assert.is_false(ns.UFImport.IsUpgrade(row.upgrade))
    end)

    it("reads a positive percentage on the same map as better", function()
        local row = findRow(model, 268205)
        assert.equal("QE Live: better by 4.50%", row.upgradeValue)
        assert.is_true(ns.UFImport.IsUpgrade(row.upgrade))
    end)

    it("gives no number to a drop the sample ranks only at a level the journal never lists", function()
        -- 268219 is in the walk at 321; the sample ranks it at 9999 alone.
        local row = findRow(model, 268219)
        assert.equal(321, row.itemLevel)
        assert.is_nil(row.upgrade)
        assert.is_nil(row.upgradeValue)
        assert.same({ 9999 }, row.rankedAtAnotherLevel)
    end)

    it("carries both ways of getting a two-source drop onto the row", function()
        local row = findRow(model, 268205)
        assert.equal(2, row.upgrade.count)
        assert.equal(2, #row.upgrade.sources)
    end)

    it("never joins a row whose item data never arrived, because its level is unknown", function()
        local pendingWalk = ns.Journal:Build({ snapshot = R.snapshot("journal", 1, R.JOURNAL), refresh = true })
        local pendingModel = ns.UpgradeMapPanel.Model({ sources = pendingWalk, upgrades = upgrades(ns, UF_SAMPLE) })
        assert.is_true(pendingModel.pending.count > 0)
        for _, row in ipairs(pendingModel.pending.rows) do
            assert.is_nil(row.upgrade)
            assert.is_nil(row.upgradeValue)
            assert.is_nil(row.rankedAtAnotherLevel)
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- WKE-542 (M3-8): the by-run view. The owner's question on the first day of
-- real use was "what would be the best run for me to do right now", which the
-- slot view above cannot answer. Every figure named below was read from the
-- committed fixtures by a script before it was written down.

local UF_RAID = "spec/fixtures/qe/qe-upgradefinder-Hotornot-kqyktjywppzw.json"

-- Every drop the journal lists, grouped the way a run groups them, computed
-- here from `sources` alone. The denominator on screen has to equal this or the
-- count line is saying something the walk did not.
local function journalDropsPerRun(ns, sources, previewLevel)
    local counts = {}
    for _, list in pairs(sources) do
        for _, entry in ipairs(list) do
            local level = ns.UpgradeMapPanel.RunKeyLevel(entry.difficultyID, previewLevel, entry)
            local key = ns.UpgradeMapPanel.RunKey(entry, level)
            counts[key] = (counts[key] or 0) + 1
        end
    end
    return counts
end

describe("UpgradeMapPanel by-run view, joined to the genuine Raid export", function()
    local ns, sources, summary

    before_each(function()
        ns = H.load()
        sources, summary = coldWalk(ns)
    end)

    after_each(function()
        H.unload()
    end)

    local function runModel(sort, opts)
        opts = opts or {}
        return ns.UpgradeMapPanel.RunModel({
            sources = sources,
            summary = summary,
            upgrades = upgrades(ns, UF_RAID),
            runSort = sort,
            difficultyIDs = opts.difficultyIDs,
        })
    end

    it("carries the whole walk: 48 runs over the 478 drops the slot view counts", function()
        -- Measured over the 2026-09-06 20:09 cold walk, whose rows all arrived.
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        assert.equal(48, model.counts.runs)
        assert.equal(478, model.counts.drops)
        local slotModel = ns.UpgradeMapPanel.Model({ sources = sources, summary = summary })
        assert.equal(slotModel.counts.candidates, model.counts.drops)
    end)

    it("is one run per dungeon and difficulty, and one run per raid boss and difficulty", function()
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        local dungeons, raids = 0, 0
        local seen = {}
        for _, run in ipairs(model.runs) do
            assert.is_nil(seen[run.key])
            seen[run.key] = true
            if run.isRaid then
                raids = raids + 1
                assert.is_number(run.encounterID)
                assert.is_not_nil(run.label:find(run.encounterName, 1, true))
            else
                dungeons = dungeons + 1
                -- A dungeon run is the whole dungeon: no boss in its identity.
                assert.is_nil(run.encounterID)
                assert.is_nil(run.encounterName)
            end
        end
        -- Measured: 8 dungeons, seven of them walked at all three dungeon
        -- difficulties and Kings' Rest at two, so 23; and 25 raid boss and
        -- difficulty pairs, 13 Heroic and 12 Mythic.
        assert.equal(23, dungeons)
        assert.equal(25, raids)
        assert.equal(48, dungeons + raids)
    end)

    it("ranked by best upgrade, puts QE Live's biggest single number first", function()
        -- Measured: Gaze of the Coiled Watcher (Head, 344) from Ula'tek is the
        -- Raid export's largest upgradePercent among the walk's drops, 3.42.
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        local top = model.runs[1]
        assert.equal("The Venomous Abyss - Ula'tek - Mythic raid", top.label)
        assert.equal(3.42, top.bestPercent)
        assert.equal(
            "The Venomous Abyss - Ula'tek - Mythic raid: best +3.42% (Gaze of the Coiled Watcher, Head); "
                .. "2 of 3 drops rated upgrades",
            top.text
        )
        for index = 2, #model.runs do
            assert.is_true((model.runs[index].bestPercent or 0) <= top.bestPercent)
        end
    end)

    it("ranked by most upgrades, puts the run with the most rated drops first", function()
        -- Measured: The Coiled Altar has 4 of its 6 drops rated, more than any
        -- other run, though its best single number (2.035) is only the fourth.
        local model = runModel(ns.UpgradeMapPanel.SORT_COUNT)
        local top = model.runs[1]
        assert.equal("The Venomous Abyss - The Coiled Altar - Mythic raid", top.label)
        assert.equal(4, top.rated)
        assert.equal(6, top.drops)
        assert.equal(2.035, top.bestPercent)
        assert.equal("4 of 6 drops rated upgrades", top.countText)
        for index = 2, #model.runs do
            assert.is_true(model.runs[index].rated <= top.rated)
        end
    end)

    it("answers at first glance, in one sentence naming the top row under the sort", function()
        local best = runModel(ns.UpgradeMapPanel.SORT_BEST)
        assert.equal(
            "Best run right now (by best upgrade): The Venomous Abyss, Ula'tek, Mythic raid - +3.42% for Head.",
            best.headline
        )
        assert.equal("The Venomous Abyss, Ula'tek, Mythic raid", best.runs[1].name)
        local count = runModel(ns.UpgradeMapPanel.SORT_COUNT)
        assert.equal(
            "Best run right now (by most upgrades): The Venomous Abyss, The Coiled Altar, Mythic raid - "
                .. "4 of 6 drops rated upgrades.",
            count.headline
        )
        assert.equal("The Venomous Abyss, The Coiled Altar, Mythic raid", count.runs[1].name)
        -- The sentence is the list's first line, so it is the first thing read.
        assert.equal(best.headline, ns.UpgradeMapPanel.RunLines(best)[1])
        assert.equal(count.headline, ns.UpgradeMapPanel.RunLines(count)[1])
    end)

    it("says a run has nothing rated rather than ranking it, and sorts it last", function()
        -- Measured: 9 of the 48 runs have a rated drop; the other 39 do not,
        -- every one of them a dungeon, because the export assumed key level 7
        -- and the walk previewed 10 (ARCHITECTURE.md 11).
        for _, sort in ipairs(ns.UpgradeMapPanel.SORTS) do
            local model = runModel(sort)
            assert.equal(9, model.counts.ratedRuns)
            local firstEmpty
            for index, run in ipairs(model.runs) do
                if run.rated == 0 then
                    firstEmpty = firstEmpty or index
                    assert.is_nil(run.best)
                    assert.is_nil(run.bestPercent)
                    assert.is_not_nil(run.text:find("no drop rated by QE Live yet", 1, true))
                else
                    assert.is_nil(firstEmpty, "a rated run sorted after an unrated one")
                end
            end
            assert.equal(10, firstEmpty)
        end
    end)

    it("always shows the denominator, and it is the journal's own drop count for that run", function()
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        local fromJournal = journalDropsPerRun(ns, sources, summary.previewMythicPlusLevel)
        local total = 0
        for _, run in ipairs(model.runs) do
            assert.equal(fromJournal[run.key], run.drops)
            assert.equal(string.format("%d of %d drops rated upgrades", run.rated, run.drops), run.countText)
            assert.is_not_nil(run.text:find(run.countText, 1, true))
            total = total + run.drops
        end
        assert.equal(478, total)
    end)

    it("lists a run's rated drops under it, best first, with QE Live's own words", function()
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        local lines = ns.UpgradeMapPanel.RunLines(model)
        local top = model.runs[1]
        assert.equal(2, #top.upgrades)
        assert.equal("Gaze of the Coiled Watcher", top.upgrades[1].name)
        assert.equal("Aqirbane Reliquary", top.upgrades[2].name)
        local at
        for index, line in ipairs(lines) do
            if line == top.text then
                at = index
            end
        end
        assert.is_not_nil(at)
        assert.equal("  Gaze of the Coiled Watcher (Head, 344) - Ula'tek - QE Live: better by 3.42%", lines[at + 1])
        assert.equal("  Aqirbane Reliquary (Neck, 344) - Ula'tek - QE Live: better by 1.91%", lines[at + 2])
    end)

    it("counts only the drops QE Live's own IsUpgrade calls upgrades", function()
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        -- Measured: the Raid export ranks 30 of the walk's rows at the level it
        -- shows, of which 21 are upgrades and 9 are his zero.
        assert.equal(21, model.counts.rated)
        local rated = 0
        for _, run in ipairs(model.runs) do
            rated = rated + #run.upgrades
            for _, row in ipairs(run.upgrades) do
                assert.is_true(ns.UFImport.IsUpgrade(row.upgrade))
                assert.equal(row.itemLevel, row.upgrade.level)
                assert.equal(row.itemID, row.upgrade.itemID)
            end
        end
        assert.equal(21, rated)
    end)

    it("offers the two rankings as facts and never an expected value, a chance or a weighting", function()
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        assert.equal(ns.UpgradeMapPanel.RUN_NOTE, model.runNote)
        local lines = ns.UpgradeMapPanel.RunLines(model)
        assert.equal(ns.UpgradeMapPanel.RUN_NOTE, lines[2])
        -- Every line except the note itself, which is the sentence that says
        -- none of these words are what the view is doing.
        for _, line in ipairs(lines) do
            if line ~= ns.UpgradeMapPanel.RUN_NOTE then
                for _, banned in ipairs({ "expected", "probability", "weighted", "chance", "odds", "1 in " }) do
                    assert.is_nil(line:lower():find(banned, 1, true), "a line said " .. banned .. ": " .. line)
                end
            end
        end
    end)

    it("says which key level the Mythic Keystone runs are shown at", function()
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST)
        assert.same({ 10 }, model.keyLevels)
        assert.equal(
            "Mythic Keystone runs are shown at key level 10, which is what the walk previewed. "
                .. "A key level with no walk and no QE Live export of its own is not shown.",
            model.keyLevelNote
        )
        local found = false
        for _, line in ipairs(ns.UpgradeMapPanel.RunLines(model)) do
            if line == model.keyLevelNote then
                found = true
            end
        end
        assert.is_true(found)
    end)

    it("follows the difficulty filter, and the buttons still count the whole map", function()
        local model = runModel(ns.UpgradeMapPanel.SORT_BEST, { difficultyIDs = { 8 } })
        -- Measured: the walk previews 54 Mythic Keystone drops over 7 dungeons.
        assert.equal(7, model.counts.runs)
        assert.equal(54, model.counts.drops)
        for _, run in ipairs(model.runs) do
            assert.equal(8, run.difficultyID)
        end
        local unfiltered = runModel(ns.UpgradeMapPanel.SORT_BEST)
        assert.equal(#unfiltered.difficulties, #model.difficulties)
        for index, difficulty in ipairs(model.difficulties) do
            assert.equal(unfiltered.difficulties[index].count, difficulty.count)
            assert.equal(unfiltered.difficulties[index].label, difficulty.label)
            assert.equal(difficulty.difficultyID == 8, difficulty.selected)
        end
    end)
end)

describe("UpgradeMapPanel by-run view, joined to the genuine Dungeon export", function()
    local ns, sources, summary

    before_each(function()
        ns = H.load()
        sources, summary = coldWalk(ns)
    end)

    after_each(function()
        H.unload()
    end)

    -- The two exports are two different answers, and the view ranks whichever
    -- one is on screen: the same walk under the Dungeon export puts a different
    -- run first, because his numbers differ.
    it("ranks the same walk by the Dungeon export's own numbers", function()
        local model = ns.UpgradeMapPanel.RunModel({
            sources = sources,
            summary = summary,
            upgrades = upgrades(ns),
            runSort = ns.UpgradeMapPanel.SORT_BEST,
        })
        assert.equal(22, model.counts.rated)
        assert.equal(9, model.counts.ratedRuns)
        assert.equal(
            "The Venomous Abyss - Vashnik the Malignant - Mythic raid: best +3.08% "
                .. "(Venomancer's Winged Channeler, 2H Weapon); 3 of 3 drops rated upgrades",
            model.runs[1].text
        )
        assert.equal(
            "Best run right now (by best upgrade): The Venomous Abyss, Vashnik the Malignant, Mythic raid - "
                .. "+3.08% for 2H Weapon.",
            model.headline
        )
    end)
end)

describe("UpgradeMapPanel by-run view without an Upgrade Finder export", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("ranks nothing, says why, and still lists every run with its drop count", function()
        local sources, summary = coldWalk(ns)
        local model = ns.UpgradeMapPanel.RunModel({ sources = sources, summary = summary })
        assert.is_false(model.hasUpgrades)
        assert.equal(0, model.counts.rated)
        assert.equal(0, model.counts.ratedRuns)
        assert.equal(48, model.counts.runs)
        assert.equal("No run in this map has a drop QE Live rates as an upgrade.", model.headline)
        for _, run in ipairs(model.runs) do
            assert.is_nil(run.best)
            assert.is_true(run.drops > 0)
        end
        local lines = ns.UpgradeMapPanel.RunLines(model)
        assert.equal(ns.UpgradeMapPanel.RUN_NO_IMPORT_NOTE, lines[3])
    end)

    it("points at the capture when there is no walk at all", function()
        local model = ns.UpgradeMapPanel.RunModel({})
        assert.is_false(model.hasMap)
        assert.same({ ns.UpgradeMapPanel.EMPTY_NOTE }, ns.UpgradeMapPanel.RunLines(model))
        assert.is_nil(model.headline)
    end)
end)

describe("UpgradeMapPanel by-run key levels (the shape WKE-543 fills in)", function()
    local ns, sources, summary

    before_each(function()
        ns = H.load()
        sources, summary = coldWalk(ns)
    end)

    after_each(function()
        H.unload()
    end)

    it("makes the key level part of a Mythic Keystone run's identity and of nothing else", function()
        local mplus = { instanceID = 1313, difficultyID = 8, isRaid = false }
        assert.is_not.equal(
            ns.UpgradeMapPanel.RunKey(mplus, ns.UpgradeMapPanel.RunKeyLevel(8, 10)),
            ns.UpgradeMapPanel.RunKey(mplus, ns.UpgradeMapPanel.RunKeyLevel(8, 12))
        )
        -- A Heroic dungeon has no key level, so nothing about it moves.
        local heroic = { instanceID = 1313, difficultyID = 2, isRaid = false }
        assert.is_nil(ns.UpgradeMapPanel.RunKeyLevel(2, 10))
        assert.equal(
            ns.UpgradeMapPanel.RunKey(heroic, ns.UpgradeMapPanel.RunKeyLevel(2, 10)),
            ns.UpgradeMapPanel.RunKey(heroic, ns.UpgradeMapPanel.RunKeyLevel(2, 12))
        )
    end)

    it("reads a key level off the entry when it carries one, over the walk's previewed level", function()
        assert.equal(10, ns.UpgradeMapPanel.RunKeyLevel(8, 10, {}))
        assert.equal(12, ns.UpgradeMapPanel.RunKeyLevel(8, 10, { mythicPlusLevel = 12 }))
        assert.is_nil(ns.UpgradeMapPanel.RunKeyLevel(2, 10, { mythicPlusLevel = 12 }))
    end)

    it("sorts one dungeon at two key levels as two runs, each with its own label and count", function()
        -- A cached fixture is shared mutable state (ARCHITECTURE.md 7), so the
        -- second key level is built onto a copy and the walk is left alone.
        local doubled = {}
        for itemID, list in pairs(sources) do
            local copy = {}
            for _, entry in ipairs(list) do
                copy[#copy + 1] = entry
                if entry.difficultyID == 8 and entry.instanceID == 1313 then
                    local twelve = {}
                    for field, value in pairs(entry) do
                        twelve[field] = value
                    end
                    twelve.mythicPlusLevel = 12
                    copy[#copy + 1] = twelve
                end
            end
            doubled[itemID] = copy
        end
        local model = ns.UpgradeMapPanel.RunModel({ sources = doubled, summary = summary })
        local ten, twelve
        for _, run in ipairs(model.runs) do
            if run.instanceID == 1313 and run.difficultyID == 8 then
                if run.keyLevel == 10 then
                    ten = run
                elseif run.keyLevel == 12 then
                    twelve = run
                end
            end
        end
        assert.is_not_nil(ten)
        assert.is_not_nil(twelve)
        assert.is_not.equal(ten.key, twelve.key)
        assert.equal("Voidscar Arena - Mythic+ 10", ten.label)
        assert.equal("Voidscar Arena - Mythic+ 12", twelve.label)
        assert.equal(6, ten.drops)
        assert.equal(6, twelve.drops)
        assert.equal(49, model.counts.runs)
        assert.same({ 10, 12 }, model.keyLevels)
        assert.equal(
            "Mythic Keystone runs are shown at key levels 10, 12, which is what the walk previewed. "
                .. "A key level with no walk and no QE Live export of its own is not shown.",
            model.keyLevelNote
        )
    end)
end)

describe("UpgradeMapPanel view toggle on the frames", function()
    local ns, world, snapshot

    before_each(function()
        ns, world = H.load()
        snapshot = select(3, loadMap(ns))
        loadInventory(ns, world)
        ns.db.global.captures.journal = { snapshot }
        ns.UFImport.Store(upgrades(ns, UF_RAID))
    end)

    after_each(function()
        H.unload()
    end)

    it("opens on the slot view, with the sort buttons out of the way", function()
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        assert.equal(ns.UpgradeMapPanel.MODE_SLOT, frame.mode)
        assert.equal("By slot", frame.modeButtons[1]:GetText())
        assert.equal("By run", frame.modeButtons[2]:GetText())
        assert.is_false(frame.modeButtons[1]:IsEnabled())
        assert.is_true(frame.modeButtons[2]:IsEnabled())
        for _, button in ipairs(frame.sortButtons) do
            assert.is_false(button:IsShown())
        end
        assert.is_false(frame.sortLabel:IsShown())
    end)

    it("switches to the by-run view on a click and back again byte for byte", function()
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        local slotLines = {}
        for index, line in ipairs(frame.lines) do
            slotLines[index] = line
        end
        assert.same(ns.UpgradeMapPanel.Lines(frame.model), slotLines)

        frame.modeButtons[2]:Click()
        assert.equal(ns.UpgradeMapPanel.MODE_RUN, frame.mode)
        assert.same(ns.UpgradeMapPanel.RunLines(frame.model), frame.lines)
        assert.is_not.same(slotLines, frame.lines)
        for index, line in ipairs(frame.lines) do
            assert.equal(line, frame.rows[index]:GetText())
        end
        -- Nothing is left over from the longer list of the other view.
        for index = #frame.lines + 1, #frame.rows do
            assert.equal("", frame.rows[index]:GetText())
            assert.is_false(frame.rows[index]:IsShown())
        end

        frame.modeButtons[1]:Click()
        assert.equal(ns.UpgradeMapPanel.MODE_SLOT, frame.mode)
        assert.same(slotLines, frame.lines)
        for index, line in ipairs(slotLines) do
            assert.equal(line, frame.rows[index]:GetText())
        end
    end)

    it("offers the two sort orders in the run view and re-sorts on a click", function()
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        frame.modeButtons[2]:Click()
        assert.equal("best upgrade", frame.sortButtons[1]:GetText())
        assert.equal("most upgrades", frame.sortButtons[2]:GetText())
        assert.is_true(frame.sortLabel:IsShown())
        assert.is_false(frame.sortButtons[1]:IsEnabled())
        assert.is_true(frame.sortButtons[2]:IsEnabled())
        local byBest = frame.model.runs[1].key

        frame.sortButtons[2]:Click()
        assert.equal(ns.UpgradeMapPanel.SORT_COUNT, frame.runSort)
        assert.equal(ns.UpgradeMapPanel.SORT_COUNT, frame.model.sort)
        assert.is_not.equal(byBest, frame.model.runs[1].key)
        assert.is_not_nil(frame.model.headline:find("by most upgrades", 1, true))
        assert.is_false(frame.sortButtons[2]:IsEnabled())
        assert.is_true(frame.sortButtons[1]:IsEnabled())

        -- The sort survives a trip through the slot view.
        frame.modeButtons[1]:Click()
        frame.modeButtons[2]:Click()
        assert.equal(ns.UpgradeMapPanel.SORT_COUNT, frame.model.sort)
    end)

    it("keeps the difficulty filter across the two views", function()
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        for _, button in ipairs(frame.filterButtons) do
            if button:GetText():find("Mythic+ 10", 1, true) then
                button:Click()
            end
        end
        assert.same({ 8 }, frame.difficultyIDs)
        frame.modeButtons[2]:Click()
        assert.same({ 8 }, frame.difficultyIDs)
        for _, run in ipairs(frame.model.runs) do
            assert.equal(8, run.difficultyID)
        end
    end)

    it("says why it is empty in the run view too, rather than a map, in combat", function()
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        frame.modeButtons[2]:Click()
        world.inCombat = true
        frame:Refresh()
        assert.same({
            "Lootpath does not read the client in combat. Leave combat and reopen this panel.",
        }, frame.lines)
        assert.equal(ns.UpgradeMapPanel.NOTE, frame.note:GetText())
    end)
end)
