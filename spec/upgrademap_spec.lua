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
        assert.equal(summary.sources, filed + model.pending.count)
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
        assert.equal(summary.sources - model.pending.count, filed)
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
        assert.same({ ns.UpgradeMapPanel.NOTE, ns.UpgradeMapPanel.EMPTY_NOTE }, ns.UpgradeMapPanel.Lines(model))
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
            ns.UpgradeMapPanel.NOTE,
            "Lootpath does not read the client in combat. Leave combat and reopen this panel.",
        }, frame.lines)
    end)

    it("points at the capture when no walk has been stored", function()
        ns.db.global.captures.journal = nil
        local frame = ns.UpgradeMapPanel.Create()
        frame:Refresh()
        assert.same({ ns.UpgradeMapPanel.NOTE, ns.UpgradeMapPanel.EMPTY_NOTE }, frame.lines)
    end)
end)
