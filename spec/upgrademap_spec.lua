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
