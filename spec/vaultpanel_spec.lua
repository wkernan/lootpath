-- spec/vaultpanel_spec.lua (M3-3, WKE-524)
-- The Vault panel over the committed vault transcripts and the genuine QE Live
-- export. The vault's own rewards were empty in every committed snapshot, so
-- the reward rows here are driven through the stub in Blizzard's documented
-- WeeklyRewardActivityRewardInfo shape and are labelled as such; what is
-- measured is the activity list, the progress and the reset clock.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local QE_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"
-- Read from the committed export itself.
local EXPORTED_AT = "2026-09-06T21:14:24Z"
local WITH_PROGRESS = 3

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function realVerdict(ns)
    local parsed = ns.QEImport.Parse(readFile(QE_EXPORT))
    assert(parsed.ok, parsed.reason)
    return parsed.verdict
end

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

-- Puts one generated item reward on an activity, in Blizzard's documented shape.
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
        instant = { itemID, "Armor", "Cloth", "INVTYPE_FEET", nil, 4, 8, n = 7 },
    }
    world.vault.hasAvailable = true
    return link
end

-- The export's Feet item, which is the one the Top Gear top set really ranked.
local COVERED_ITEM = {
    id = 251153,
    bonusIDs = { 13440, 6652, 13662, 12699, 12835 },
    name = "Arctic Explorer's Legwraps",
}

describe("VaultPanel over the committed vault transcript", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
    end)

    after_each(function()
        H.unload()
    end)

    it("lists every option with its progress, rewards or not", function()
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = realVerdict(ns), now = 1788700000 })
        assert.is_true(model.ok)
        assert.equal(10, model.counts.options)
        assert.equal(0, model.counts.rewards)
        assert.equal(ns.VaultPanel.NO_REWARDS_NOTE, model.rewardsNote)
        assert.is_nil(model.best)
        -- Measured 2026-09-06 16:11:30.
        assert.equal("2/2 (level 10)", model.options[1].progressText)
        assert.equal("5/8", model.options[3].progressText)
        assert.is_true(model.options[1].unlocked)
        assert.is_false(model.options[3].unlocked)
    end)

    it("shows an option QE Live has not ranked with no number at all", function()
        generateReward(world, 1, 999001, { 1234 }, "Unranked Boots", 301)
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = realVerdict(ns), now = 1788700000 })
        assert.equal(1, model.counts.rewards)
        assert.equal(0, model.counts.covered)
        local reward = model.options[1].rewards[1]
        assert.equal("Unranked Boots", reward.name)
        assert.equal(301, reward.itemLevel)
        assert.is_nil(reward.qe)
        assert.is_nil(reward.value)
        assert.is_nil(model.best)
        for _, line in ipairs(ns.VaultPanel.Lines(model)) do
            assert.is_nil(line:find("QE Live: "), "an unranked option rendered a value: " .. line)
        end
    end)

    -- The red proof for the assertion above: the same panel, the same vault,
    -- one option whose exact key the export really carries.
    it("shows QE Live's verdict on an option it ranked, joined by the exact key", function()
        generateReward(world, 1, COVERED_ITEM.id, COVERED_ITEM.bonusIDs, COVERED_ITEM.name, 298)
        local verdict = realVerdict(ns)
        local key = ns.ItemKey(COVERED_ITEM.id, COVERED_ITEM.bonusIDs)
        assert.is_not_nil(verdict.topSet.items[key])

        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = verdict, now = 1788700000 })
        local reward = model.options[1].rewards[1]
        assert.equal(1, model.counts.covered)
        assert.equal(key, reward.key)
        assert.equal("topSet", reward.qe.where)
        assert.equal("QE Live: in your best set", reward.value)
        assert.is_true(reward.best)
        assert.equal(reward, model.best)
        local highlighted = 0
        for _, line in ipairs(ns.VaultPanel.Lines(model)) do
            if line:find("<- QE Live's pick", 1, true) then
                highlighted = highlighted + 1
            end
        end
        assert.equal(1, highlighted)
    end)

    it("highlights the option QE Live ranks best, and only when it ranked one", function()
        local verdict = realVerdict(ns)
        local topKey = ns.ItemKey(COVERED_ITEM.id, COVERED_ITEM.bonusIDs)
        local worseKey = ns.ItemKey(999002, { 77 })
        local betterKey = ns.ItemKey(999003, { 78 })
        verdict.alternatives = {
            { scorePercent = 3.0, hpsDifference = -600, items = { { key = worseKey, itemID = 999002 } }, gems = {} },
            { scorePercent = -1.0, hpsDifference = 200, items = { { key = betterKey, itemID = 999003 } }, gems = {} },
        }
        generateReward(world, 1, 999002, { 77 }, "Worse Alternative", 300)
        generateReward(world, 2, 999003, { 78 }, "Better Alternative", 300)
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = verdict, now = 1788700000 })
        assert.equal(2, model.counts.covered)
        assert.equal(betterKey, model.best.key)
        assert.equal("QE Live: better by 1.00% (+200.0 score)", model.best.value)
        assert.equal("QE Live: worse by 3.00% (-600.0 score)", model.options[1].rewards[1].value)

        -- A top-set option outranks any alternative: QE Live already put it in
        -- the set it recommends.
        generateReward(world, 3, COVERED_ITEM.id, COVERED_ITEM.bonusIDs, COVERED_ITEM.name, 298)
        local withTopSet = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = verdict, now = 1788700000 })
        assert.equal(topKey, withTopSet.best.key)
    end)

    it("says there is no verdict rather than showing an empty one", function()
        generateReward(world, 1, 999001, { 1234 }, "Unranked Boots", 301)
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options() })
        assert.is_false(model.hasVerdict)
        assert.equal(ns.VaultPanel.NO_VERDICT_NOTE, model.verdictNote)
        assert.is_nil(model.staleNote)
        assert.is_nil(model.options[1].rewards[1].value)
    end)

    it("reports why the vault could not be read", function()
        world.inCombat = true
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = realVerdict(ns) })
        assert.is_false(model.ok)
        assert.equal("combat", model.reason)
        -- The note is the header's, not the list's (WKE-530 finding 3).
        assert.equal(ns.VaultPanel.NOTE, model.note)
        assert.same({ "The vault could not be read: combat" }, ns.VaultPanel.Lines(model))
    end)
end)

-- The join over the real thing at last: the after-reset vault (2026-09-08
-- 12:45:26, snapshot 9 of that transcript) and the companion's Top Gear export
-- written from those same captures (uliwcyoomcub). QE Live put the vault's
-- Lightgrasp Worldroot in the top set; the option's client link carries the
-- same bonus IDs, so the exact key matches with no fallback (WKE-523 / 519).
describe("VaultPanel over the after-reset vault and the export that ranked it", function()
    local ns, world
    local AFTER_RESET = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local VAULT_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-uliwcyoomcub.json"
    local WEAPON_KEY = "251935:6652:12841"

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, AFTER_RESET))
    end)

    after_each(function()
        H.unload()
    end)

    local function verdict()
        local parsed = ns.QEImport.Parse(readFile(VAULT_EXPORT))
        assert(parsed.ok, parsed.reason)
        return parsed.verdict
    end

    it("joins the vault weapon to QE Live's top set by the exact key and highlights it", function()
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = verdict(), now = 1788900000 })
        assert.equal(1, model.counts.covered)
        local weapon
        for _, option in ipairs(model.options) do
            for _, reward in ipairs(option.rewards) do
                if reward.key == WEAPON_KEY then
                    weapon = reward
                end
            end
        end
        assert.is_not_nil(weapon)
        assert.equal("topSet", weapon.qe.where)
        assert.equal("QE Live: in your best set", weapon.value)
        assert.is_true(weapon.best)
        assert.equal(weapon, model.best)
        local highlighted = 0
        for _, line in ipairs(ns.VaultPanel.Lines(model)) do
            if line:find("<- QE Live's pick", 1, true) then
                highlighted = highlighted + 1
            end
        end
        assert.equal(1, highlighted)
    end)

    it("gives the other gear options and the keystones no number", function()
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = verdict(), now = 1788900000 })
        for _, option in ipairs(model.options) do
            for _, reward in ipairs(option.rewards) do
                if reward.key ~= WEAPON_KEY then
                    assert.is_nil(reward.value, "unranked reward carried a value: " .. tostring(reward.key))
                end
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-7 (WKE-538): the three things this panel said wrongly about that same real
-- vault. Every figure below is read from the transcript and the export the
-- block above already replays (docs/ARCHITECTURE.md §9, "Measured 2026-09-08"):
-- activities 207/208/213/214/217/229 each carry a Mythic Keystone (180653,
-- INVTYPE_NON_EQUIP_IGNORE, item level 1) beside their gear, 217 a Thalassian
-- Token of Merit (269862) as well; every `progress` is 0 while
-- HasAvailableRewards and CanClaimRewards are true; and the vault weapon reads
-- 305 in the client's link and 321 in QE Live's export.

describe("VaultPanel against the real reward shape (WKE-538)", function()
    local ns, world
    local AFTER_RESET = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local VAULT_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-uliwcyoomcub.json"
    local WEAPON_KEY = "251935:6652:12841"
    local KEYSTONE_ID = 180653

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, AFTER_RESET))
    end)

    after_each(function()
        H.unload()
    end)

    local function verdict()
        local parsed = ns.QEImport.Parse(readFile(VAULT_EXPORT))
        assert(parsed.ok, parsed.reason)
        return parsed.verdict
    end

    -- An hour after the export was written, so the panel is reading a verdict
    -- that knows this week's vault and no staleness note is in the way.
    local function model(qeSettings)
        local v = verdict()
        v.qeSettings = qeSettings
        local now = ns.VaultPanel.EpochFromISO(v.exportedAt) + 3600
        return ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = v, now = now })
    end

    local function optionByID(m, id)
        for _, option in ipairs(m.options) do
            if option.id == id then
                return option
            end
        end
        return nil
    end

    -- Finding 1 --------------------------------------------------------------

    it("keeps the Mythic Keystone out of the gear options and names it in words", function()
        local m = model()
        -- Four gear options this week, seven non-gear rewards beside them.
        assert.equal(4, m.counts.rewards)
        assert.equal(7, m.counts.extras)

        local world2 = optionByID(m, 208)
        assert.equal(1, #world2.rewards)
        assert.equal("Lightgrasp Worldroot", world2.rewards[1].name)
        assert.equal(305, world2.rewards[1].itemLevel)
        assert.equal(1, #world2.extras)
        assert.equal(KEYSTONE_ID, world2.extras[1].itemID)
        assert.equal("+ Mythic Keystone", world2.extras[1].text)
        assert.equal("+ Mythic Keystone", world2.extrasText)
        -- Name, level and the keystone are one unit, so C-6's scenario lines can
        -- grow underneath it (WKE-540) without moving any of the three.
        -- Since C-6 the pick names the scenario it came from, and the verdict
        -- line under it is that scenario's own line. This export names none, so
        -- it is `asOffered` - what the character has now.
        assert.equal(
            "Lightgrasp Worldroot (305; QE Live valued it at 321) + Mythic Keystone  <- QE Live's pick (as offered)",
            world2.rewards[1].text
        )
        assert.same({ "as offered: in your best set" }, world2.rewards[1].verdictLines)

        -- Nothing without a slot is ever a gear option, anywhere on the panel.
        for _, option in ipairs(m.options) do
            for _, reward in ipairs(option.rewards) do
                assert.is_not_nil(reward.slot, "a non-gear reward was listed as gear: " .. tostring(reward.itemID))
                assert.are_not.equal(KEYSTONE_ID, reward.itemID)
            end
        end
    end)

    it("never renders an item level 1 row, and never a value on one", function()
        local m = model()
        local sawKeystone = 0
        for _, line in ipairs(ns.VaultPanel.Lines(m)) do
            assert.is_nil(line:find("(1)", 1, true), "a line rendered item level 1: " .. line)
            if line:find("+ Mythic Keystone", 1, true) then
                sawKeystone = sawKeystone + 1
            end
        end
        -- Six activities carry one, and every one of them is still on screen.
        assert.equal(6, sawKeystone)
        -- The keystone rides the gear's line where there is gear, and keeps a
        -- line of its own where there is none: 229 carries a keystone alone.
        local concession = optionByID(m, 229)
        assert.equal(0, #concession.rewards)
        assert.equal("+ Mythic Keystone", concession.extrasText)
        -- 217 carries both non-gear rewards, in the order the client listed them.
        assert.equal("+ Thalassian Token of Merit + Mythic Keystone", optionByID(m, 217).extrasText)
    end)

    it("keeps the keystone out of the highlight", function()
        local none = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = nil })
        assert.equal(0, none.counts.covered)
        assert.is_nil(none.best)
        -- With a verdict, the pick is the gear QE Live ranked - never the
        -- keystone that shares its row.
        local ranked = model()
        assert.equal(WEAPON_KEY, ranked.best.key)
        assert.equal(1, ranked.counts.covered)
    end)

    -- Finding 2 --------------------------------------------------------------

    it("calls a row with rewards claimable even though the reset put its progress back to 0", function()
        local m = model()
        assert.is_true(m.hasAvailableRewards)
        assert.is_true(m.canClaimRewards)

        local world2 = optionByID(m, 208)
        assert.equal(0, world2.progress)
        assert.equal(4, world2.threshold)
        assert.equal("0/4", world2.progressText)
        assert.is_true(world2.claimable)
        -- The module's field is what the client said, and is not touched here.
        assert.is_false(world2.unlocked)
        assert.equal("World 2: 0/4 - rewards ready", world2.headerText)

        local world3 = optionByID(m, 209)
        assert.equal(0, #world3.rewards)
        assert.is_false(world3.claimable)
        assert.equal("World 3: 0/8", world3.headerText)
    end)

    it("says the rewards are ready rather than that nothing has generated them", function()
        local m = model()
        assert.is_nil(m.rewardsNote)
        local claimable = 0
        for _, option in ipairs(m.options) do
            if option.claimable then
                claimable = claimable + 1
            end
        end
        -- 207, 208, 213, 214, 217 and 229.
        assert.equal(6, claimable)
    end)

    -- Hand-built, and said so: no committed transcript has a week whose only
    -- rewards are non-gear. The note is about whether the vault has GENERATED
    -- anything, so a keystone standing alone must not be reported as nothing.
    it("does not claim the vault is empty when its only reward is not gear", function()
        ns = H.load()
        local m = ns.VaultPanel.Model({
            vault = {
                ok = true,
                options = {
                    {
                        type = 5,
                        typeLabel = "Concession",
                        index = 2,
                        id = 229,
                        threshold = 3,
                        progress = 4,
                        rewards = { { itemID = 180653, name = "Mythic Keystone", itemLevel = 1 } },
                    },
                },
            },
        })
        assert.equal(0, m.counts.rewards)
        assert.equal(1, m.counts.extras)
        assert.is_nil(m.rewardsNote)
        assert.is_true(m.options[1].claimable)
    end)

    -- The game's own words for the rows (the owner's Great Vault screenshot,
    -- 2026-09-08). The module keeps the measured enum's vocabulary.
    it("names the rows the way the Great Vault window does", function()
        local m = model()
        assert.equal("World", optionByID(m, 207).rowLabel)
        assert.equal("Dungeons", optionByID(m, 213).rowLabel)
        assert.equal("Raids", optionByID(m, 210).rowLabel)
        -- A row the vault screen does not rename keeps the module's label.
        assert.equal("Concession", optionByID(m, 229).rowLabel)
        assert.equal("Mythic+", ns.Vault.TypeLabel(1))
        assert.equal("Mythic+", optionByID(m, 213).typeLabel)
    end)

    -- Finding 3 --------------------------------------------------------------

    it("shows the client's item level and QE Live's when they differ", function()
        local m = model()
        local weapon = optionByID(m, 208).rewards[1]
        assert.equal(305, weapon.itemLevel)
        assert.equal(321, weapon.qeLevel)
        assert.equal("305; QE Live valued it at 321", weapon.levelText)
        -- Both figures reach the line, and neither replaces the other.
        local line
        for _, text in ipairs(ns.VaultPanel.Lines(m)) do
            if text:find("Lightgrasp Worldroot", 1, true) then
                line = text
            end
        end
        assert.is_truthy(line:find("305", 1, true))
        assert.is_truthy(line:find("321", 1, true))
    end)

    it("names the QE Live setting that produced its level when the companion recorded it", function()
        local withVault = model({ autoUpgradeVault = true, autoUpgradeAll = false })
        assert.equal(
            "305; QE Live valued it at 321 with vault upgrades assumed",
            optionByID(withVault, 208).rewards[1].levelText
        )
        local both = model({ autoUpgradeVault = true, autoUpgradeAll = true })
        assert.equal(
            "305; QE Live valued it at 321 with vault and all upgrades assumed",
            optionByID(both, 208).rewards[1].levelText
        )
        -- Both off and the levels still differ: that is worth saying too, and it
        -- is read from the file rather than inferred from the difference.
        local neither = model({ autoUpgradeVault = false, autoUpgradeAll = false })
        assert.equal(
            "305; QE Live valued it at 321 with no upgrades assumed",
            optionByID(neither, 208).rewards[1].levelText
        )
        -- Half a pair, or a pair that is not booleans, says nothing at all.
        assert.is_nil(ns.VaultPanel.SettingsPhrase({ autoUpgradeVault = true }))
        assert.is_nil(ns.VaultPanel.SettingsPhrase({ autoUpgradeVault = "true", autoUpgradeAll = false }))
        assert.is_nil(ns.VaultPanel.SettingsPhrase(nil))
    end)

    it("shows one figure when there is nothing to disagree with", function()
        local m = model()
        -- Scavenger's Spaulders: 308 in the client's link, and QE Live's export
        -- does not carry the item at all.
        local shoulder = optionByID(m, 213).rewards[1]
        assert.equal("Scavenger's Spaulders", shoulder.name)
        assert.equal(308, shoulder.itemLevel)
        assert.is_nil(shoulder.qeLevel)
        assert.equal("308", shoulder.levelText)
        -- And a pair that agrees says it once: LevelText is the one place the
        -- two numbers are ever compared.
        assert.equal("308", ns.VaultPanel.LevelText(308, 308, nil))
        assert.equal("305; QE Live valued it at 321", ns.VaultPanel.LevelText(305, 321, nil))
    end)
end)

describe("VaultPanel staleness against the weekly reset", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
    end)

    after_each(function()
        H.unload()
    end)

    it("reads QE Live's ISO stamp back as the epoch second it means", function()
        -- A round trip through the client's own clock, so the assertion holds in
        -- any timezone: date("!...") formats an epoch as UTC, EpochFromISO reads
        -- it back.
        local epoch = 1788700000
        assert.equal(epoch, ns.VaultPanel.EpochFromISO(date("!%Y-%m-%dT%H:%M:%SZ", epoch)))
        assert.is_not_nil(ns.VaultPanel.EpochFromISO(EXPORTED_AT))
        assert.is_nil(ns.VaultPanel.EpochFromISO("last Tuesday"))
        assert.is_nil(ns.VaultPanel.EpochFromISO(nil))
    end)

    it("calls a verdict stale only when it predates the most recent reset", function()
        local exported = ns.VaultPanel.EpochFromISO(EXPORTED_AT)
        local week = ns.VaultPanel.WEEK_SECONDS
        -- now is one day after the export, next reset six days out: the last
        -- reset was a day before the export, so the export is current.
        assert.is_false(ns.VaultPanel.IsVerdictStale(EXPORTED_AT, exported + 86400, 6 * 86400))
        -- now is one day after the export, next reset in an hour: the last reset
        -- was almost a week ago and the export came after it.
        assert.is_false(ns.VaultPanel.IsVerdictStale(EXPORTED_AT, exported + 86400, 3600))
        -- now is eight days after the export: a reset has happened since.
        assert.is_true(ns.VaultPanel.IsVerdictStale(EXPORTED_AT, exported + 8 * 86400, 6 * 86400))
        -- and nothing to compare against makes no claim either way
        assert.is_nil(ns.VaultPanel.IsVerdictStale(EXPORTED_AT, exported, nil))
        assert.is_nil(ns.VaultPanel.IsVerdictStale(nil, exported, week))
    end)

    it("notes a stale verdict on the panel, and says nothing when it is current", function()
        local exported = ns.VaultPanel.EpochFromISO(EXPORTED_AT)
        -- The transcript's own clock: 150509 seconds to the reset at 16:11:30.
        local vault = ns.Vault.Options()
        assert.equal(150509, vault.secondsUntilWeeklyReset)

        local stale = ns.VaultPanel.Model({
            vault = vault,
            verdict = realVerdict(ns),
            now = exported + 8 * 86400,
        })
        assert.is_true(stale.stale)
        assert.equal(ns.VaultPanel.STALE_NOTE, stale.staleNote)
        local sawNote = false
        for _, line in ipairs(ns.VaultPanel.Lines(stale)) do
            if line == ns.VaultPanel.STALE_NOTE then
                sawNote = true
            end
        end
        assert.is_true(sawNote)

        local current = ns.VaultPanel.Model({ vault = vault, verdict = realVerdict(ns), now = exported + 3600 })
        assert.is_false(current.stale)
        assert.is_nil(current.staleNote)
    end)
end)

-- Every string the drawn tab actually has on it. Until M5-4 the tab was one
-- column of font strings and `panel.lines` was the whole of it; it is a grid
-- now, so a test that asks "is this on screen" asks the widgets. The rows are
-- the notes, the headline block is its own frame, and every option is a cell.
local function drawnTexts(panel)
    local out = {}
    local function add(region)
        if not (region and region:IsShown()) then
            return
        end
        local text = region:GetText()
        if type(text) == "string" and text ~= "" then
            out[#out + 1] = text
        end
    end
    for _, region in ipairs(panel.rows) do
        add(region)
    end
    if panel.headline:IsShown() then
        add(panel.headline.text)
        for _, region in ipairs(panel.headline.lines) do
            add(region)
        end
    end
    for _, gridRow in ipairs(panel.gridRows) do
        if gridRow:IsShown() then
            add(gridRow.label)
            for _, cell in ipairs(gridRow.cells) do
                if cell:IsShown() then
                    if cell.line:IsShown() then
                        add(cell.line.name)
                        add(cell.line.second)
                        add(cell.line.level)
                    end
                    add(cell.label)
                    add(cell.tags)
                    add(cell.verdict)
                    add(cell.extras)
                    add(cell.footer)
                    add(cell.locked)
                end
            end
        end
    end
    for _, entry in ipairs(panel.chips) do
        if entry:IsShown() then
            add(entry.text)
        end
    end
    add(panel.other)
    add(panel.currencyNote)
    return out
end

-- The first of those strings that carries `needle`, or nil.
local function containsText(texts, needle)
    for _, text in ipairs(texts) do
        if text:find(needle, 1, true) then
            return text
        end
    end
    return nil
end

describe("VaultPanel frames", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
    end)

    after_each(function()
        H.unload()
    end)

    it("renders the notes into the panel's rows and the options into the grid", function()
        generateReward(world, 1, COVERED_ITEM.id, COVERED_ITEM.bonusIDs, COVERED_ITEM.name, 298)
        ns.QEImport.Store(realVerdict(ns))
        local frame = ns.VaultPanel.Create()
        local model = frame:Refresh()
        local notes = ns.VaultPanel.NoteLines(model)
        for i, line in ipairs(notes) do
            assert.equal(line, frame.rows[i]:GetText())
        end
        assert.equal(#notes, #frame.lines)
        assert.equal(ns.VaultPanel.NOTE, frame.note:GetText())
        assert.equal("QE Live: in your best set", model.best.value)
        -- Three rows of three cells, and the option the export covers is drawn
        -- in one of them with QE Live's own line on it (M5-4).
        assert.equal(3, #frame.gridRows)
        for _, gridRow in ipairs(frame.gridRows) do
            assert.equal(3, #gridRow.cells)
        end
        local texts = drawnTexts(frame)
        assert.is_not_nil(containsText(texts, COVERED_ITEM.name))
        assert.is_not_nil(containsText(texts, "in your best set"))
    end)

    -- The window, not the last paste, decides which verdict a panel reads
    -- (M2-2's UI.ActiveVerdict). With two imports on the character and the
    -- setting pointing at one of them, a panel reaching for QEImport.Current
    -- would answer with the other.
    it("reads the verdict the content-type setting names, not the last paste", function()
        generateReward(world, 1, COVERED_ITEM.id, COVERED_ITEM.bonusIDs, COVERED_ITEM.name, 298)
        local dungeon = realVerdict(ns)
        dungeon.contentType = "Dungeon"
        dungeon.topSet.items = {}
        dungeon.topSet.order = {}
        ns.QEImport.Store(dungeon)
        -- The Raid export is pasted second, so it is what Current() answers,
        -- and it is the one that covers this week's option.
        ns.QEImport.Store(realVerdict(ns))
        assert.equal("Raid", ns.QEImport.Current().contentType)
        assert.equal("Dungeon", ns.UI.Options.Get())

        local frame = ns.VaultPanel.Create()
        local model = frame:Refresh()
        assert.equal(0, model.counts.covered)
        assert.is_nil(model.best)
        assert.is_nil(model.options[1].rewards[1].value)

        -- Point the setting at the Raid export and the same option is covered.
        ns.db.profile.settings.contentType = "Raid"
        local covered = frame:Refresh()
        assert.equal(1, covered.counts.covered)
        assert.equal("QE Live: in your best set", covered.best.value)
    end)

    it("hides the rows and the cells a shorter render does not use", function()
        ns.QEImport.Store(realVerdict(ns))
        local frame = ns.VaultPanel.Create()
        -- Two weeks past the export, so the tab carries the stale note as well
        -- as the no-rewards one and there is more than one row to lose.
        frame:Refresh({ now = ns.VaultPanel.EpochFromISO(EXPORTED_AT) + 2 * ns.VaultPanel.WEEK_SECONDS })
        local long = #frame.lines
        assert.is_true(long >= 2)
        world.inCombat = true
        frame:Refresh()
        assert.equal(1, #frame.lines)
        for i = 2, long do
            assert.equal("", frame.rows[i]:GetText())
            assert.is_false(frame.rows[i]:IsShown())
        end
        -- A vault that could not be read draws no cells at all, rather than
        -- nine cells left over from the last time it could.
        for _, gridRow in ipairs(frame.gridRows) do
            for _, cell in ipairs(gridRow.cells) do
                assert.is_false(cell:IsShown())
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- WKE-530 (M3-5) finding 3: the pinned note was drawn twice on this tab too -
-- once by the panel header and once as the list's first row - in the owner's
-- first in-game run, 2026-09-06.

describe("VaultPanel draws the pinned note once (WKE-530 finding 3)", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
    end)

    after_each(function()
        H.unload()
    end)

    local function noteCount(frame)
        local seen = 0
        if frame.note:GetText():find(ns.VaultPanel.NOTE, 1, true) then
            seen = seen + 1
        end
        for _, text in ipairs(frame.rows) do
            if text:GetText():find(ns.VaultPanel.NOTE, 1, true) then
                seen = seen + 1
            end
        end
        return seen
    end

    it("puts it in the header and never in the list", function()
        local frame = ns.VaultPanel.Create()
        local model = frame:Refresh()
        assert.is_true(model.ok)
        assert.equal(1, noteCount(frame))
        assert.equal(ns.VaultPanel.NOTE, frame.note:GetText())
        -- The model still carries it, which is what pins the wording headlessly.
        assert.equal(ns.VaultPanel.NOTE, model.note)
    end)

    it("still says it once when the vault refuses to be read", function()
        local frame = ns.VaultPanel.Create()
        frame:Refresh()
        world.inCombat = true
        frame:Refresh()
        assert.is_false(frame.model.ok)
        assert.equal(1, noteCount(frame))
    end)
end)

-- ---------------------------------------------------------------------------
-- C-6 (WKE-540): the vault what-ifs, as QE Live's own named scenarios.
--
-- The three documents are real: one companion run on 2026-09-09 01:15 UTC over
-- the profile of the 2026-09-08 12:45 capture, asking QE Live the same gear
-- three times through his three import checkboxes. Every number asserted below
-- is his, read out of those files (spec/fixtures/qe/README.md).
--
-- The point of the feature is in one row. Under `asOffered` the vault's
-- Scavenger's Spaulders are not in his answer at all; under `catalyzed` the
-- tier shoulder he cloned from them is in the top set; under `maxed` the weapon
-- wins instead. Three questions, three answers, none of them Lootpath's.

describe("VaultPanel over the three named scenarios (WKE-540)", function()
    local ns, world
    local AFTER_RESET = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
        maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
    }
    local WEAPON_KEY = "251935:6652:12841"
    local SPAULDERS_KEY = "251146:6652:12699:12842:13440:13662"

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, AFTER_RESET))
    end)

    after_each(function()
        H.unload()
    end)

    local function scenarios(names)
        local out = {}
        for _, name in ipairs(names or { "asOffered", "catalyzed", "maxed" }) do
            local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES[name]))
            assert(parsed.ok, parsed.reason)
            parsed.verdict.scenario = name
            -- What the companion records for each document: the three boxes the
            -- run really used, read back off QE Live's own page.
            parsed.verdict.qeSettings = {
                autoUpgradeVault = name == "maxed",
                autoUpgradeAll = name == "maxed",
                autoCatalyze = name ~= "asOffered",
            }
            out[#out + 1] = { verdict = parsed.verdict, scenario = name }
        end
        return out
    end

    local function model(opts)
        opts = opts or {}
        local list = opts.scenarios or scenarios()
        return ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = list,
            verdict = list[1] and list[1].verdict or nil,
            highlightScenario = opts.highlightScenario,
            now = 1788900000,
        })
    end

    local function rewardByKey(m, key)
        for _, option in ipairs(m.options) do
            for _, reward in ipairs(option.rewards) do
                if reward.key == key then
                    return reward
                end
            end
        end
        return nil
    end

    it("shows one line per scenario that has something to say about the option", function()
        local weapon = rewardByKey(model(), WEAPON_KEY)
        assert.is_not_nil(weapon)
        assert.same({
            "as offered: worse by 0.57% (-1983.0 score)",
            "catalyzed: worse by 1.07% (-3782.0 score) (the Catalyst run made no tier version of this item)",
            "everything upgraded: in your best set",
        }, weapon.verdictLines)
    end)

    -- The owner's whole question. His exact key is nowhere in the catalyzed
    -- answer; his own clone of it is in the top set.
    it("answers the Catalyst question with the tier piece QE Live made from the option", function()
        local spaulders = rewardByKey(model(), SPAULDERS_KEY)
        assert.is_not_nil(spaulders)
        assert.same({
            "catalyzed, as tier: in your best set",
            "everything upgraded, as tier: worse by 1.72% (-5966.0 score)",
        }, spaulders.verdictLines)
        -- `asOffered` says nothing, because he ranked neither the shoulders nor
        -- any copy of them when the box was off.
        for _, line in ipairs(spaulders.verdictLines) do
            assert.is_nil(line:find("as offered", 1, true), line)
        end
    end)

    it("says nothing at all about an option no scenario ranked", function()
        local m = model()
        for _, option in ipairs(m.options) do
            for _, reward in ipairs(option.rewards) do
                if reward.key ~= WEAPON_KEY and reward.key ~= SPAULDERS_KEY then
                    assert.same({}, reward.verdictLines, "an unranked option carried a line: " .. tostring(reward.key))
                end
            end
        end
    end)

    -- The highlight follows the owner's setting, and the line says which
    -- question the pick came from: under `catalyzed` it is the shoulders, under
    -- `maxed` the weapon, and they are different items.
    it("highlights by the scenario the owner asked for, and names it on the line", function()
        local offered = model({ highlightScenario = "asOffered" })
        assert.equal("asOffered", offered.highlightScenario)
        assert.is_false(offered.highlightFellBack)
        assert.equal(WEAPON_KEY, offered.best.key)
        assert.is_truthy(offered.best.text:find("<- QE Live's pick (as offered)", 1, true))

        local catalyzed = model({ highlightScenario = "catalyzed" })
        assert.equal(SPAULDERS_KEY, catalyzed.best.key)
        assert.is_true(catalyzed.best.qeViaCatalyst)
        assert.equal("QE Live: in your best set", catalyzed.best.value)
        assert.is_truthy(catalyzed.best.text:find("<- QE Live's pick (catalyzed)", 1, true))

        local maxed = model({ highlightScenario = "maxed" })
        assert.equal(WEAPON_KEY, maxed.best.key)
        assert.is_truthy(maxed.best.text:find("<- QE Live's pick (everything upgraded)", 1, true))
    end)

    it("draws exactly one pick, whichever scenario it follows", function()
        for _, name in ipairs({ "asOffered", "catalyzed", "maxed" }) do
            local highlighted = 0
            for _, line in ipairs(ns.VaultPanel.Lines(model({ highlightScenario = name }))) do
                if line:find("<- QE Live's pick", 1, true) then
                    highlighted = highlighted + 1
                end
            end
            assert.equal(1, highlighted, name)
        end
    end)

    it("says so when the scenario the owner asked for has no answer stored", function()
        local m = model({ scenarios = scenarios({ "asOffered" }), highlightScenario = "maxed" })
        assert.equal("asOffered", m.highlightScenario)
        assert.is_true(m.highlightFellBack)
        assert.equal(
            "No everything upgraded answer is stored yet, so the pick below follows as offered.",
            m.highlightNote
        )
        assert.is_truthy(m.highlightNote)
        local found = false
        for _, line in ipairs(ns.VaultPanel.Lines(m)) do
            found = found or line == m.highlightNote
        end
        assert.is_true(found, "the fallback is said on screen, not only in the model")
    end)

    -- A paste, and every file written before C-6, name no scenario. Nothing
    -- about the panel changes for them beyond the name on the line.
    it("reads a single verdict that names no scenario as asOffered", function()
        local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES.asOffered))
        assert(parsed.ok, parsed.reason)
        local m = ns.VaultPanel.Model({ vault = ns.Vault.Options(), verdict = parsed.verdict, now = 1788900000 })
        assert.equal(1, m.counts.scenarios)
        assert.equal("asOffered", m.highlightScenario)
        assert.is_false(m.highlightFellBack)
        assert.same({ "as offered: worse by 0.57% (-1983.0 score)" }, rewardByKey(m, WEAPON_KEY).verdictLines)
    end)

    -- The note only appears where his own settings say the box was on. A
    -- document that does not say claims nothing either way.
    it("only says the Catalyst made nothing when the file says the box was on", function()
        local list = scenarios({ "catalyzed" })
        list[1].verdict.qeSettings = nil
        local weapon = rewardByKey(model({ scenarios = list }), WEAPON_KEY)
        assert.same({ "catalyzed: worse by 1.07% (-3782.0 score)" }, weapon.verdictLines)
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-9 (WKE-544): the tab leads with QE Live's pick and the steps to get there.
--
-- The owner's words after the first in-game run, 2026-09-08: the tab "doesn't do
-- a good job of telling me what my top pick is and why - the catalyst example:
-- it should guide me that I would need to get the shoulders, then use the
-- catalyst (which we should know how many charges I have), then upgrade with
-- crests (which we should know how many the player has and what type)".
--
-- Same three real documents as the C-6 block above, over the same real
-- after-reset vault. The CURRENCY half is placeholders in Blizzard's documented
-- `CurrencyInfo` shape and is labelled as such everywhere it appears: no
-- `/lootpath capture currencies` transcript exists yet, so no name or ID here is
-- claimed to be the season's real crest (spec/currencies_spec.lua says the same).
describe("VaultPanel's headline block (WKE-544)", function()
    local ns, world
    local AFTER_RESET = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
        maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
    }

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, AFTER_RESET))
    end)

    after_each(function()
        H.unload()
    end)

    local function scenarios(names)
        local out = {}
        for _, name in ipairs(names or { "asOffered", "catalyzed", "maxed" }) do
            local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES[name]))
            assert(parsed.ok, parsed.reason)
            parsed.verdict.scenario = name
            parsed.verdict.qeSettings = {
                autoUpgradeVault = name == "maxed",
                autoUpgradeAll = name == "maxed",
                autoCatalyze = name ~= "asOffered",
            }
            out[#out + 1] = { verdict = parsed.verdict, scenario = name }
        end
        return out
    end

    -- Placeholder currencies, named as placeholders. What this proves is the
    -- path from the client's list to the line, not what the season's crests are.
    local function knownCurrencies()
        world.currencies = {
            { name = "Placeholder Group", currencyID = 0, isHeader = true, quantity = 0 },
            { name = "Placeholder Crest", currencyID = 900001, isHeader = false, quantity = 42 },
            { name = "Placeholder Charge", currencyID = 900002, isHeader = false, quantity = 1 },
        }
        ns.Currencies.CREST_NAMES = { "Placeholder Crest" }
        ns.Currencies.CATALYST_NAMES = { "Placeholder Charge" }
        return ns.Currencies.Read()
    end

    local function model(opts)
        opts = opts or {}
        local list = opts.scenarios or scenarios()
        return ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = list,
            verdict = list[1] and list[1].verdict or nil,
            highlightScenario = opts.highlightScenario,
            currencies = opts.currencies,
            now = 1788900000,
        })
    end

    local function headlineLines(m)
        local out = { m.headline.text }
        for _, line in ipairs(m.headline.lines) do
            out[#out + 1] = "  " .. line.text
        end
        return out
    end

    -- The owner's own example, on his own vault, in his own words: the pick, the
    -- shoulders, the Catalyst charge he has, and the crests the other answer
    -- would need. Every number in it is QE Live's or the client's.
    --
    -- The `catalyzed` line says what the charge is spent ON since M3-15
    -- (WKE-556), and it says it with no bags read at all: converting a vault
    -- reward costs a charge like any other conversion, and the vault snapshot
    -- alone is enough to name it.
    it("leads with the pick under the owner's scenario and answers every question under it", function()
        local m = model({ highlightScenario = "catalyzed", currencies = knownCurrencies() })
        assert.same({
            "QE Live's pick this week (catalyzed): Scavenger's Spaulders (Dungeons 1)",
            "  as offered: nothing in the vault beats your set",
            "  catalyzed, as tier: in your best set - needs a Catalyst charge (you have 1)"
                .. " - and catalyze the vault's Scavenger's Spaulders (308) into the tier shoulder",
            "  everything upgraded: Lightgrasp Worldroot instead - in your best set"
                .. " - needs a Catalyst charge (you have 1) and crests (you have Placeholder Crest 42)",
        }, headlineLines(m))
    end)

    it("puts the block on screen above the option list", function()
        local m = model({ highlightScenario = "catalyzed", currencies = knownCurrencies() })
        local lines = ns.VaultPanel.Lines(m)
        assert.equal(m.headline.text, lines[1])
        assert.equal("  " .. m.headline.lines[1].text, lines[2])
        assert.equal(m.options[1].headerText, lines[2 + #m.headline.lines])
    end)

    -- The headline follows the owner's setting and nothing else. Three settings,
    -- three sentences, two different items - all of them his answers.
    it("leads with whichever scenario the owner asked for", function()
        assert.equal(
            "QE Live's pick this week (as offered): none - nothing in the vault beats your set; "
                .. "closest: Lightgrasp Worldroot (World 2)",
            model({ highlightScenario = "asOffered", currencies = knownCurrencies() }).headline.text
        )
        assert.equal(
            "QE Live's pick this week (everything upgraded): Lightgrasp Worldroot (World 2)",
            model({ highlightScenario = "maxed", currencies = knownCurrencies() }).headline.text
        )
        local m = model({ highlightScenario = "catalyzed", currencies = knownCurrencies() })
        assert.equal("Scavenger's Spaulders", m.headline.pick.name)
        assert.equal("catalyzed", m.headline.scenario)
    end)

    -- Named only when it is a different item: repeating the headline's own name
    -- under every scenario buries the one line where the answer changes.
    it("names a scenario's pick only when it differs from the headline's", function()
        local m = model({ highlightScenario = "asOffered", currencies = knownCurrencies() })
        assert.is_truthy(m.headline.lines[2].text:find("Scavenger's Spaulders instead", 1, true))
        assert.is_nil(m.headline.lines[3].text:find("Lightgrasp Worldroot", 1, true))
    end)

    -- The whole reason Modules/Currencies.lua exists, and the whole reason it
    -- ships knowing no currency by name: with nothing captured the tab says so.
    it("says unknown rather than a number when no currency list has been read", function()
        local m = model({ highlightScenario = "catalyzed" })
        assert.is_truthy(
            m.headline.lines[2].text:find("needs a Catalyst charge (unknown - run /lootpath refresh)", 1, true)
        )
        assert.is_truthy(m.headline.lines[3].text:find("and crests (unknown - run /lootpath refresh)", 1, true))
    end)

    it("says unknown while the addon has been told no currency's name", function()
        -- The shipped tables carry the 2026-09-08 names; this test is about the
        -- state before any transcript, so it empties them explicitly.
        ns.Currencies.KNOWN_IDS = { crests = {}, catalyst = {} }
        ns.Currencies.CREST_NAMES = {}
        ns.Currencies.CATALYST_NAMES = {}
        world.currencies = {
            { name = "Placeholder Crest", currencyID = 900001, isHeader = false, quantity = 42 },
        }
        local read = ns.Currencies.Read()
        assert.is_true(read.ok)
        local m = model({ highlightScenario = "catalyzed", currencies = read })
        assert.is_truthy(m.headline.lines[3].text:find("(unknown - run /lootpath refresh)", 1, true))
    end)

    -- The transcript may show the Catalyst charge is not a currency at all. Then
    -- the line says that, in those words, and never a 0.
    it(
        "shows the owner's real crest counts and the Catalyst as not readable, from the 2026-09-08 transcript",
        function()
            local snapshot = R.snapshot("currencies", 2, "spec/fixtures/captures/Lootpath-20260908-230426.lua")
            ns.Currencies.CREST_NAMES = {
                "Adventurer Mistcrest",
                "Veteran Mistcrest",
                "Champion Mistcrest",
                "Hero Mistcrest",
                "Myth Mistcrest",
            }
            ns.Currencies.CATALYST_NAMES = {}
            local m =
                model({ highlightScenario = "catalyzed", currencies = ns.Currencies.Read({ snapshot = snapshot }) })
            assert.is_truthy(m.headline.lines[2].text:find("(Catalyst charges: not readable)", 1, true))
            local crests = m.headline.lines[3].text
            assert.is_truthy(crests:find("Adventurer Mistcrest 356", 1, true))
            assert.is_truthy(crests:find("Hero Mistcrest 21", 1, true))
            assert.is_truthy(crests:find("Myth Mistcrest 20", 1, true))
            assert.is_nil(crests:find("unknown", 1, true))
        end
    )

    -- M3-11: the Catalyst charge IS a currency (Venomblight Manaflux, 3465),
    -- readable by ID even when the currency tab's headers hide it, and the
    -- client gives a maximum for it. Both numbers are the client's; nothing on
    -- this line is computed from them.
    it("puts the client's own maximum beside the charge count: you have 1 of 8", function()
        world.currencies = {
            {
                name = "Placeholder Collapsed Group",
                currencyID = 0,
                isHeader = true,
                isHeaderExpanded = false,
                quantity = 0,
            },
        }
        world.currencyByID = {
            [3465] = {
                name = "Venomblight Manaflux",
                currencyID = 3465,
                isHeader = false,
                quantity = 1,
                maxQuantity = 8,
            },
        }
        local read = ns.Currencies.Read()
        assert.equal(1, read.catalystCharges)
        assert.equal(8, read.catalystMax)
        local m = model({ highlightScenario = "catalyzed", currencies = read })
        assert.equal(
            "catalyzed, as tier: in your best set - needs a Catalyst charge (you have 1 of 8)"
                .. " - and catalyze the vault's Scavenger's Spaulders (308) into the tier shoulder",
            m.headline.lines[2].text
        )
    end)

    -- A client that gives a count and no maximum still gets a line, without an
    -- invented ceiling after it.
    it("says only the count when the client gives no maximum", function()
        local m = model({ highlightScenario = "catalyzed", currencies = knownCurrencies() })
        assert.is_truthy(m.headline.lines[2].text:find("needs a Catalyst charge (you have 1)", 1, true))
        assert.is_nil(m.headline.lines[2].text:find(" of ", 1, true))
    end)

    it("says the Catalyst charge is not readable when the client answers nothing for its ID", function()
        knownCurrencies()
        ns.Currencies.KNOWN_IDS = { crests = ns.Currencies.KNOWN_IDS.crests, catalyst = {} }
        ns.Currencies.CATALYST_NAMES = { "Placeholder Charge The Client Does Not Have" }
        local m = model({ highlightScenario = "catalyzed", currencies = ns.Currencies.Read() })
        assert.is_truthy(m.headline.lines[2].text:find("(Catalyst charges: not readable)", 1, true))
        assert.is_nil(m.headline.lines[2].text:find("you have", 1, true))
    end)

    it("says the player has none of the named crests rather than nothing at all", function()
        knownCurrencies()
        ns.Currencies.KNOWN_IDS = { crests = {}, catalyst = ns.Currencies.KNOWN_IDS.catalyst }
        ns.Currencies.CREST_NAMES = { "Placeholder Crest Nobody Has" }
        local m = model({ highlightScenario = "catalyzed", currencies = ns.Currencies.Read() })
        assert.is_truthy(m.headline.lines[3].text:find("and crests (you have none of them)", 1, true))
    end)

    -- No assumption, no phrase: `asOffered` asked QE Live about the vault as it
    -- stands, so its line names nothing the owner would have to go and get.
    it("hangs no assumption on the scenario that assumed nothing", function()
        local m = model({ highlightScenario = "asOffered", currencies = knownCurrencies() })
        assert.equal("as offered: nothing in the vault beats your set", m.headline.lines[1].text)
        assert.is_nil(ns.VaultPanel.NEEDS_TEXT.asOffered)
    end)

    -- The standing rule, as a test. Lootpath never computes a healer value and
    -- never a cost: no line here counts upgrades, prices one, or totals crests.
    it("never puts a cost or a count of upgrades on the block", function()
        for _, name in ipairs({ "asOffered", "catalyzed", "maxed" }) do
            local lines = headlineLines(model({ highlightScenario = name, currencies = knownCurrencies() }))
            for _, line in ipairs(lines) do
                for _, forbidden in ipairs({ "enough for", "cost", "each", "per upgrade", "total" }) do
                    assert.is_nil(line:lower():find(forbidden, 1, true), forbidden .. " in: " .. line)
                end
            end
        end
    end)

    it("says nothing at all when there is no QE Live import to lead with", function()
        local m = ns.VaultPanel.Model({ vault = ns.Vault.Options(), now = 1788900000 })
        assert.is_nil(m.headline)
        assert.equal(ns.VaultPanel.NO_VERDICT_NOTE, ns.VaultPanel.Lines(m)[1])
    end)

    it("says nothing at all when the vault has generated no gear", function()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
        local m = model({ highlightScenario = "catalyzed", currencies = knownCurrencies() })
        assert.equal(0, m.counts.rewards)
        assert.is_nil(m.headline)
    end)

    -- A scenario that mentions none of these options says so, rather than
    -- borrowing the answer next to it.
    it("says a scenario that ranked none of these options is silent", function()
        local list = scenarios({ "asOffered", "catalyzed" })
        list[2].verdict.topSet = { items = {}, order = {} }
        list[2].verdict.alternatives = {}
        local m = model({ scenarios = list, highlightScenario = "asOffered", currencies = knownCurrencies() })
        assert.equal("catalyzed: none of these options is in this answer", m.headline.lines[2].text)
        assert.is_nil(m.headline.lines[2].text:find("you have", 1, true))
    end)

    -- The block is built out of the lines already on the rows, so it cannot
    -- claim a pick the list below does not carry.
    it("picks the same option the list highlights", function()
        for _, name in ipairs({ "asOffered", "catalyzed", "maxed" }) do
            local m = model({ highlightScenario = name, currencies = knownCurrencies() })
            assert.equal(m.best, m.headline.pick)
            assert.is_truthy(m.best.text:find("<- QE Live's pick", 1, true))
        end
    end)

    -- The refresh the "unknown" line points at really is the one that takes the
    -- capture the count comes from.
    it("is refreshed by the command its own unknown line names", function()
        assert.is_truthy(ns.VaultPanel.COUNT_UNKNOWN:find("/lootpath refresh", 1, true))
        local seen = false
        for _, name in ipairs(ns.Companion.REFRESH_CAPTURES) do
            seen = seen or name == ns.Currencies.CAPTURE
        end
        assert.is_true(seen)
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-12 (WKE-547): the owner's screenshot of 2026-09-09 morning, right after a
-- client restart, read `[] (nil)` on four of the five options and `[] instead
-- - in your best set` in the headline. The transcript that refresh took
-- (`Lootpath-20260909-085940.lua`, vault snapshot 13) is what these tests
-- replay; snapshot 12 of the same file (2026-09-08 23:26) names the same
-- itemDBIDs and is the client's late answer.

describe("VaultPanel over the fresh-login vault (M3-12, WKE-547)", function()
    local ns, world
    local FRESH_LOGIN = "spec/fixtures/captures/Lootpath-20260909-085940.lua"
    local NAMELESS = 13
    local NAMED = 12
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
        maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
    }
    local PENDING_IDS = { 251146, 251234, 269862, 275547 }
    local NOTE = "|cff909296" -- ns.VaultPanel.NOTE_COLOR, pinned in the first test

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", NAMELESS, FRESH_LOGIN))
    end)

    after_each(function()
        H.unload()
    end)

    local function scenarios()
        local out = {}
        for _, name in ipairs({ "asOffered", "catalyzed", "maxed" }) do
            local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES[name]))
            assert(parsed.ok, parsed.reason)
            parsed.verdict.scenario = name
            parsed.verdict.qeSettings = {
                autoUpgradeVault = name == "maxed",
                autoUpgradeAll = name == "maxed",
                autoCatalyze = name ~= "asOffered",
            }
            out[#out + 1] = { verdict = parsed.verdict, scenario = name }
        end
        return out
    end

    local function rewardsByItemID(model)
        local map = {}
        for _, option in ipairs(model.options) do
            for _, reward in ipairs(option.rewards) do
                map[reward.itemID] = reward
            end
        end
        return map
    end

    local function assertNoBracketsOrNil(lines)
        for _, line in ipairs(lines) do
            assert.is_nil(line:find("[]", 1, true), "empty brackets on screen: " .. line)
            assert.is_nil(line:find("nil", 1, true), "nil on screen: " .. line)
        end
    end

    local function contains(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then
                return line
            end
        end
        return nil
    end

    it("prints no [] and no nil, and says pending in words", function()
        assert.equal(NOTE, ns.VaultPanel.NOTE_COLOR)
        assert.equal(ns.UI.EquipPanel.NOTE_COLOR, ns.VaultPanel.NOTE_COLOR)
        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), captures = false })
        assert.equal(4, model.counts.pending)
        assert.equal(4, model.counts.rewards)
        assert.equal(1, model.counts.extras)
        local lines = ns.VaultPanel.Lines(model)
        assertNoBracketsOrNil(lines)
        assert.is_not_nil(contains(lines, NOTE .. "name pending (item 275547) - level pending|r"))
        assert.is_not_nil(contains(lines, NOTE .. "name pending (item 251146) - level pending|r"))
        assert.is_not_nil(contains(lines, NOTE .. "name pending (item 251234) - level pending|r"))
        -- The Concession token is still not gear: named in words on its row.
        assert.is_not_nil(contains(lines, "+ name pending (item 269862)"))
        -- The resolved one reads as it always did.
        assert.is_not_nil(contains(lines, "Lightgrasp Worldroot (305)"))
        assert.equal(string.format(ns.VaultPanel.PENDING_NOTE, 4), model.pendingNote)
        assert.is_not_nil(contains(lines, model.pendingNote))
    end)

    it("counts, values and picks a pending reward like any other - its key is known", function()
        local model = ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = scenarios(),
            highlightScenario = "catalyzed",
            captures = false,
            now = 1789000000,
        })
        local rewards = rewardsByItemID(model)
        local spaulders = rewards[251146]
        assert.is_true(spaulders.pending)
        assert.is_not_nil(spaulders.qe)
        assert.equal("topSet", spaulders.qe.where)
        assert.is_true(spaulders.qeViaCatalyst)
        assert.is_true(spaulders.best)
        assert.equal(spaulders, model.best)
        -- Two lines, not three: "not ranked" as offered (§9's table), in the
        -- best set as tier catalyzed, an alternative as tier maxed.
        assert.equal(2, #spaulders.scenarioLines)
        -- QE Live's own level for the exact key is still his fact, and it is
        -- shown beside the pending client level, not instead of it.
        assert.equal(308, spaulders.qeLevel)
        assert.is_truthy(spaulders.levelText:find("^level pending; QE Live valued it at 308", 1))
        -- The headline uses the same words as the row.
        -- Measured: activity 213 is `index = 1` of the Dungeons row in snapshot 13.
        assert.equal(
            "QE Live's pick this week (catalyzed): name pending (item 251146) (Dungeons 1)",
            model.headline.text
        )
        local lines = ns.VaultPanel.Lines(model)
        assertNoBracketsOrNil(lines)
        -- And the "instead" naming in the other scenarios' lines, too.
        local other = ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = scenarios(),
            highlightScenario = "asOffered",
            captures = false,
            now = 1789000000,
        })
        local catalyzedLine
        for _, line in ipairs(other.headline.lines) do
            if line.scenario == "catalyzed" then
                catalyzedLine = line.text
            end
        end
        assert.is_truthy(catalyzedLine:find("name pending (item 251146) instead - in your best set", 1, true))
        assertNoBracketsOrNil(ns.VaultPanel.Lines(other))
    end)

    -- Every pending reward measured still had its slot from GetItemInfoInstant.
    -- Should one ever come back with nothing at all, "not known yet" must not
    -- become "not gear": the row stays with the gear, keyed and valued, rather
    -- than sliding into the extras where nothing is counted or ranked.
    it("keeps a pending reward the client said nothing about with the gear", function()
        local link = world.vault.links["0x4000000E5E0736EB"]
        world.items[link].instant = nil
        local model = ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = scenarios(),
            highlightScenario = "asOffered",
            captures = false,
            now = 1789000000,
        })
        local lantern = rewardsByItemID(model)[275547]
        assert.is_not_nil(lantern)
        assert.is_true(lantern.pending)
        assert.is_nil(lantern.slot)
        assert.equal("275547:6652:12841", lantern.key)
        assert.equal(4, model.counts.rewards)
        assert.equal(1, model.counts.extras)
        assertNoBracketsOrNil(ns.VaultPanel.Lines(model))
    end)

    it("says the level is pending rather than 0, nil or a snapshot's level", function()
        assert.equal("level pending", ns.VaultPanel.LevelText(nil, nil, nil, true))
        -- QE Live's level is his fact about the exact key and is still shown.
        assert.equal("level pending; QE Live valued it at 305", ns.VaultPanel.LevelText(nil, 305, nil, true))
        assert.equal("305", ns.VaultPanel.LevelText(305, 305, nil, false))
        assert.equal("level unknown", ns.VaultPanel.LevelText(nil, nil, nil, false))
        assert.equal(
            "level pending; QE Live valued it at 321 with vault and all upgrades assumed",
            ns.VaultPanel.LevelText(nil, 321, { autoUpgradeVault = true, autoUpgradeAll = true }, true)
        )
    end)

    it("shows the last capture's name, labelled, when a stored snapshot carries it", function()
        local all = R.captures(FRESH_LOGIN).vault
        assert.equal(13, #all)
        local name, when = ns.VaultPanel.NameFromCaptures("0x4000000E5E0736EB", all)
        assert.equal("Preyhunter's Lantern", name)
        assert.equal("2026-09-08T23:26:17", when)
        -- The newest snapshot that CARRIES the name, not merely the newest:
        -- snapshot 13 is the nameless one.
        assert.is_nil(ns.VaultPanel.NameFromCaptures("0x4000000E5E0736EB", { all[NAMELESS] }))
        assert.is_nil(ns.VaultPanel.NameFromCaptures("not-a-reward", all))

        local model = ns.VaultPanel.Model({ vault = ns.Vault.Options(), captures = all })
        local lines = ns.VaultPanel.Lines(model)
        assertNoBracketsOrNil(lines)
        assert.is_not_nil(contains(lines, NOTE .. "Preyhunter's Lantern (from the last capture) - level pending|r"))
        assert.is_not_nil(contains(lines, NOTE .. "Scavenger's Spaulders (from the last capture) - level pending|r"))
        assert.is_not_nil(contains(lines, "+ Thalassian Token of Merit (from the last capture)"))
        -- Still pending: the level is never taken from a snapshot.
        assert.is_true(rewardsByItemID(model)[275547].pending)
        assert.is_nil(rewardsByItemID(model)[275547].itemLevel)
    end)

    it("reads the stored snapshots from the database when none are handed in", function()
        assert.is_not_nil(
            contains(
                ns.VaultPanel.Lines(ns.VaultPanel.Model({ vault = ns.Vault.Options() })),
                "name pending (item 275547)"
            )
        )
        ns.db.global.captures.vault = R.captures(FRESH_LOGIN).vault
        assert.is_not_nil(
            contains(
                ns.VaultPanel.Lines(ns.VaultPanel.Model({ vault = ns.Vault.Options() })),
                "Preyhunter's Lantern (from the last capture)"
            )
        )
    end)

    it("redraws the tab when the client's data lands, and only when the tab is on screen", function()
        assert.is_true(ns.UI.Toggle())
        local frame = ns.UI.frame
        ns.UI.SelectTab(frame, ns.UI.VAULT_TAB)
        local panel = frame.vaultPanel
        assert.is_not_nil(contains(drawnTexts(panel), "name pending (item 275547)"))
        assert.equal(4, ns.Vault.PendingCount())

        -- The client answers; four events, one redraw, the names on screen.
        R.vaultLinks(world, R.snapshot("vault", NAMED, FRESH_LOGIN))
        for _, id in ipairs(PENDING_IDS) do
            world.fireEvent("ITEM_DATA_LOAD_RESULT", id, true)
        end
        assert.is_not_nil(contains(drawnTexts(panel), "name pending (item 275547)"))
        world.runTimers(0)
        local texts = drawnTexts(panel)
        assert.is_nil(contains(texts, "name pending"))
        assert.is_not_nil(contains(texts, "Preyhunter's Lantern"))
        assert.is_not_nil(contains(texts, "Scavenger's Spaulders"))
        -- The level moved into the icon's own corner when the tab became a
        -- grid; it is still the client's number and it is still on screen.
        assert.is_not_nil(contains(texts, "305"))
        assert.is_not_nil(contains(texts, "308"))
        assert.is_not_nil(contains(texts, "+ Thalassian Token of Merit"))
        assertNoBracketsOrNil(texts)
        assert.equal(0, ns.Vault.PendingCount())

        -- On another tab the Vault panel is left alone (M3-3's rule).
        ns.UI.SelectTab(frame, 1)
        local before = panel.lines
        assert.is_false(ns.UI.RefreshVault())
        assert.equal(before, panel.lines)
        -- And with the window closed.
        ns.UI.SelectTab(frame, ns.UI.VAULT_TAB)
        frame:Hide()
        assert.is_false(ns.UI.RefreshVault())
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-13 (WKE-548): the fourth scenario on the tab.
--
-- All four documents are real and committed unedited: the three of the
-- 2026-09-09 01:15 run and the `thisWeek` pair of the 19:22 run, every one of
-- them over the same profile - the 2026-09-08 12:45 capture, whose vault
-- snapshot 9 and inventory snapshot 7 are replayed underneath them here.

describe("VaultPanel over the fourth scenario (M3-13, WKE-548)", function()
    local ns, world
    local CAPTURE = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local PROFILE_SNAPSHOT = 7
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
        thisWeek = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json",
        maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
    }
    local SPAULDERS_KEY = "251146:6652:12699:12842:13440:13662"
    local WEAPON_KEY = "251935:6652:12841"

    -- The boxes each run really used, as the companion records them per
    -- document. `thisWeek` is the only one with the vault box on and the ALL box
    -- off, which is the whole of the question.
    local BOXES = {
        asOffered = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = false },
        catalyzed = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = true },
        thisWeek = { autoUpgradeVault = true, autoUpgradeAll = false, autoCatalyze = true },
        maxed = { autoUpgradeVault = true, autoUpgradeAll = true, autoCatalyze = true },
    }

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, CAPTURE))
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
    end)

    after_each(function()
        H.unload()
    end)

    local function scenarios(names)
        local out = {}
        for _, name in ipairs(names or ns.QEImport.SCENARIOS) do
            local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES[name]))
            assert(parsed.ok, parsed.reason)
            parsed.verdict.scenario = name
            parsed.verdict.qeSettings = BOXES[name]
            out[#out + 1] = { verdict = parsed.verdict, scenario = name }
        end
        return out
    end

    local function currencies()
        world.currencies = {
            { name = "Placeholder Group", currencyID = 0, isHeader = true, quantity = 0 },
            { name = "Placeholder Crest", currencyID = 900001, isHeader = false, quantity = 42 },
            { name = "Placeholder Charge", currencyID = 900002, isHeader = false, quantity = 1 },
        }
        ns.Currencies.CREST_NAMES = { "Placeholder Crest" }
        ns.Currencies.CATALYST_NAMES = { "Placeholder Charge" }
        return ns.Currencies.Read()
    end

    local function model(opts)
        opts = opts or {}
        local list = opts.scenarios or scenarios()
        return ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = list,
            verdict = list[1] and list[1].verdict or nil,
            inventory = opts.inventory == nil and ns.Inventory.Scan() or opts.inventory,
            highlightScenario = opts.highlightScenario or "thisWeek",
            currencies = opts.currencies,
            captures = false,
            now = 1788900000,
        })
    end

    local function headlineLines(m)
        local out = { m.headline.text }
        for _, line in ipairs(m.headline.lines) do
            out[#out + 1] = "  " .. line.text
        end
        return out
    end

    local function rewardByKey(m, key)
        for _, option in ipairs(m.options) do
            for _, reward in ipairs(option.rewards) do
                if reward.key == key then
                    return reward
                end
            end
        end
        return nil
    end

    -- The whole answer on one screen, in his words and the client's. The pick is
    -- the vault weapon; the step beside it is the Catalyst charge spent on a
    -- pair of shoulders the owner already had.
    --
    -- Two lines changed in M3-15 (WKE-556), both for the one reason: converting
    -- a vault reward costs a charge. The `catalyzed` set spends two and now says
    -- so; the fifth line, which 555 read as one charge on the Hide of
    -- Pestilence, is the absence sentence, because the three sets it was reading
    -- also convert the vault's Spaulders.
    it("leads with the fourth question and says both halves of his answer", function()
        assert.same({
            "QE Live's pick this week (vault upgraded, Catalyst used): Lightgrasp Worldroot (World 2)",
            "  as offered: nothing in the vault beats your set",
            "  catalyzed, as tier: Scavenger's Spaulders instead - in your best set"
                .. " - needs a Catalyst charge (you have 1)"
                .. " - and catalyze your Hide of Pestilence (302) into the tier chest"
                .. " and the vault's Scavenger's Spaulders (308) into the tier shoulder",
            "  this week (vault upgraded, Catalyst used): in your best set"
                .. " - needs a Catalyst charge (you have 1) and crests (you have Placeholder Crest 42)"
                .. " - and catalyze your Venom-Cursed Lynx's Spaulders (295) into the tier shoulder"
                .. " and your Hide of Pestilence (302) into the tier chest",
            "  everything upgraded: in your best set"
                .. " - needs a Catalyst charge (you have 1) and crests (you have Placeholder Crest 42)"
                .. " - and catalyze your Venom-Cursed Lynx's Spaulders (295) into the tier shoulder"
                .. " and your Hide of Pestilence (302) into the tier chest",
            "  one charge (this week, Catalyst used once):"
                .. " not in QE Live's export - no set he ranked spends the charge just once",
        }, headlineLines(model({ currencies = currencies() })))
    end)

    -- The first line supplies "this week" itself, so the scenario is named there
    -- in its short form; the line below it carries the full label the issue
    -- asked for. Both are the same scenario.
    it("says the scenario short in the first line and in full on its own", function()
        assert.equal("vault upgraded, Catalyst used", ns.VaultPanel.ScenarioHeadlineLabel("thisWeek"))
        assert.equal("this week (vault upgraded, Catalyst used)", ns.VaultPanel.ScenarioLabel("thisWeek"))
        -- Every other scenario is the same word in both places.
        for _, name in ipairs({ "asOffered", "catalyzed", "maxed" }) do
            assert.equal(ns.VaultPanel.ScenarioLabel(name), ns.VaultPanel.ScenarioHeadlineLabel(name))
        end
    end)

    -- `asOffered` stays the first line of the list whatever the highlight is, so
    -- "nothing beats your set as offered" is never hidden behind a what-if.
    it("keeps as offered first in the list under every highlight", function()
        for _, name in ipairs(ns.QEImport.SCENARIOS) do
            local m = model({ highlightScenario = name, currencies = currencies() })
            assert.equal("asOffered", m.headline.lines[1].scenario)
            assert.equal("thisWeek", m.headline.lines[3].scenario)
        end
    end)

    -- His own numbers about the vault Spaulders under the fourth question: the
    -- 1.7292% alternative of the 19:22 run, which is "take the Spaulders
    -- instead, catalyzed and upgraded to 321, and keep the 308 weapon you wear".
    it("carries his fourth answer onto every option that has one", function()
        local m = model({ currencies = currencies() })
        assert.same({
            "as offered: worse by 0.57% (-1983.0 score)",
            "catalyzed: worse by 1.07% (-3782.0 score) (the Catalyst run made no tier version of this item)",
            "this week (vault upgraded, Catalyst used): in your best set",
            "everything upgraded: in your best set",
        }, rewardByKey(m, WEAPON_KEY).verdictLines)
        assert.same({
            "catalyzed, as tier: in your best set",
            "this week (vault upgraded, Catalyst used), as tier: worse by 1.73% (-6009.0 score)",
            "everything upgraded, as tier: worse by 1.72% (-5966.0 score)",
        }, rewardByKey(m, SPAULDERS_KEY).verdictLines)
    end)

    -- The sentence is about the owner's own bags, so with no scan it is not
    -- guessed at and not softened: it is simply not said.
    it("says nothing about catalyzing an owned item when there is no scan", function()
        local m = model({ inventory = false, currencies = currencies() })
        for _, line in ipairs(m.headline.lines) do
            assert.is_nil(line.text:find("catalyze your", 1, true))
            assert.is_nil(line.text:find("QE Live did not say which", 1, true))
        end
    end)

    -- His clone is there and nothing owned matches it: the slot is named and the
    -- absence is stated, rather than a shoulder being picked for him.
    it("names the slot and the absence when nothing owned matches his clone", function()
        local records = {}
        for _, record in ipairs(ns.Inventory.Scan().records) do
            if record.itemID ~= 277782 and record.itemID ~= 251226 then
                records[#records + 1] = record
            end
        end
        local m = model({ inventory = { ok = true, records = records }, currencies = currencies() })
        assert.is_truthy(
            m.headline.lines[3].text:find(
                "and catalyze a shoulder you own (QE Live did not say which)"
                    .. " and a chest you own (QE Live did not say which)",
                1,
                true
            )
        )
    end)

    -- Nothing on this tab is valued from the scan: the pick, its row and every
    -- percentage are the same with the bags read and with them not.
    it("values nothing from the inventory it reads", function()
        local with = model({ currencies = currencies() })
        local without = model({ inventory = false, currencies = currencies() })
        assert.equal(with.headline.pick.key, without.headline.pick.key)
        assert.equal(with.headline.text, without.headline.text)
        assert.same(rewardByKey(with, SPAULDERS_KEY).verdictLines, rewardByKey(without, SPAULDERS_KEY).verdictLines)
    end)

    -- The fourth answer is missing - the companion has not run since the addon
    -- learned the name - so the highlight falls back and says so rather than
    -- answering a different question in silence.
    it("falls back to as offered, out loud, when no fourth answer is stored", function()
        local m = model({ scenarios = scenarios({ "asOffered", "catalyzed" }), currencies = currencies() })
        assert.equal("asOffered", m.headline.scenario)
        assert.is_true(m.highlightFellBack)
        assert.equal(
            "No this week (vault upgraded, Catalyst used) answer is stored yet, so the pick below follows as offered.",
            m.highlightNote
        )
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-14 (WKE-555): the fifth line - one charge, spent once.
--
-- The fourth line above it says his `thisWeek` best set catalyzes TWO of the
-- owner's items while the owner holds ONE charge. This line answers what is
-- left: of the sets QE Live himself built and scored in that same document,
-- which is the best one that spends the charge exactly once? Every figure is
-- his; the panel picks no item and compares no two of his answers.
--
-- The same four real documents and the same replayed profile as the M3-13 block
-- above, plus the Raid `thisWeek` document of the same 19:22 run.

describe("VaultPanel's fifth line, one charge (M3-14, WKE-555)", function()
    local ns, world
    local CAPTURE = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local PROFILE_SNAPSHOT = 7
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
        thisWeek = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json",
        maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
    }
    local THIS_WEEK_RAID = "spec/fixtures/qe/qe-droptimizer-Hotornot-rrwofzsbrbou.json"
    local BOXES = {
        asOffered = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = false },
        catalyzed = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = true },
        thisWeek = { autoUpgradeVault = true, autoUpgradeAll = false, autoCatalyze = true },
        maxed = { autoUpgradeVault = true, autoUpgradeAll = true, autoCatalyze = true },
    }

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, CAPTURE))
        R.inventory(world, R.snapshot("inventory", PROFILE_SNAPSHOT, CAPTURE))
    end)

    after_each(function()
        H.unload()
    end)

    local function scenarios(opts)
        opts = opts or {}
        local out = {}
        for _, name in ipairs(ns.QEImport.SCENARIOS) do
            local path = (name == "thisWeek" and opts.thisWeekFile) or SCENARIO_FILES[name]
            local parsed = ns.QEImport.Parse(readFile(path))
            assert(parsed.ok, parsed.reason)
            parsed.verdict.scenario = name
            parsed.verdict.qeSettings = BOXES[name]
            if name == "thisWeek" and opts.thisWeekBoxes ~= nil then
                parsed.verdict.qeSettings = opts.thisWeekBoxes or nil
            end
            if not (name == "thisWeek" and opts.dropThisWeek) then
                out[#out + 1] = { verdict = parsed.verdict, scenario = name }
            end
        end
        return out
    end

    local function model(opts)
        opts = opts or {}
        local list = opts.scenarios or scenarios(opts)
        return ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = list,
            verdict = list[1] and list[1].verdict or nil,
            inventory = opts.inventory == nil and ns.Inventory.Scan() or opts.inventory,
            highlightScenario = "thisWeek",
            captures = false,
            now = 1788900000,
        })
    end

    local function hasLine(lines, needle)
        for _, line in ipairs(lines) do
            if line == needle then
                return true
            end
        end
        return false
    end

    local function oneChargeText(m)
        return m.headline.oneCharge and m.headline.oneCharge.text or nil
    end

    -- The measured answer on the owner's own week, Dungeon side, RE-MEASURED
    -- under M3-15 (WKE-556). 555 read three one-charge sets here and printed the
    -- best of them - "catalyze your Hide of Pestilence (302) into the tier chest
    -- - 1.73% behind". All three ALSO convert the vault's Scavenger's Spaulders
    -- into the tier shoulder, which is a second charge, so no set of his
    -- thirteen spends it once and the absence sentence is the honest line. The
    -- second charge is read off both sides in spec/qeimport_spec.lua; here what
    -- is pinned is the line on screen.
    it("reads the Dungeon answer off his own alternatives", function()
        local m = model()
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " not in QE Live's export - no set he ranked spends the charge just once",
            oneChargeText(m)
        )
        -- The absence carries no figure at all, which is the strongest form of
        -- "no number here is not his".
        assert.is_nil(oneChargeText(m):find("%d"))
        -- It is the last line of the headline block, after the four scenarios,
        -- and it lives in the model rather than in the drawing (M5-4 redraws
        -- this tab).
        assert.equal(5, #m.headline.lines)
        assert.equal(m.headline.oneCharge, m.headline.lines[5])
        assert.equal("oneCharge", m.headline.lines[5].kind)
        assert.is_true(hasLine(ns.VaultPanel.Lines(m), "  " .. oneChargeText(m)))
    end)

    -- The Raid document of the same run, and the same answer for the same
    -- reason: its three one-charge-on-his-own-items sets convert the vault's
    -- Spaulders too.
    it("reads the Raid answer off the Raid document", function()
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " not in QE Live's export - no set he ranked spends the charge just once",
            oneChargeText(model({ thisWeekFile = THIS_WEEK_RAID }))
        )
    end)

    -- The line never carries a number that is not his: the only figures in it
    -- are the client's item level for the converted item and his own
    -- scorePercent. The candidate is hand-built at his own measured figures,
    -- because his own week no longer produces one.
    it("shows his scorePercent and the client's level, and nothing else", function()
        local text = ns.VaultPanel.OneChargeLine({
            {
                where = "alternative",
                index = 7,
                scorePercent = 1.7291667240187969,
                hpsDifference = -6009,
                catalyzed = {
                    slot = "Chest",
                    item = { itemID = 271531 },
                    owned = { name = "Hide of Pestilence", itemLevel = 302 },
                    fromVault = false,
                },
            },
        }).text
        for number in text:gmatch("%d+%.?%d*") do
            assert.is_true(number == "302" or number == "1.73", "unexpected number on the one-charge line: " .. number)
        end
    end)

    -- The vault's own wording on the fifth line (M3-15, WKE-556): a set whose
    -- one charge goes on a reward the vault is offering names it as the vault's,
    -- and one whose vault clone matched no reward says the slot and the absence.
    -- Hand-built candidates, because the owner's own week has no one-charge set.
    it("names a vault reward as the vault's on the fifth line", function()
        local function line(catalyzed)
            return ns.VaultPanel.OneChargeLine({
                {
                    where = "alternative",
                    index = 4,
                    scorePercent = 0.9,
                    hpsDifference = -300,
                    catalyzed = catalyzed,
                },
            }).text
        end
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " catalyze the vault's Scavenger's Spaulders (308) into the tier shoulder - 0.90% behind",
            line({
                slot = "Shoulder",
                item = { itemID = 271526 },
                owned = { name = "Scavenger's Spaulders", itemLevel = 308 },
                fromVault = true,
            })
        )
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " catalyze a shoulder the vault is offering (QE Live did not say which) - 0.90% behind",
            line({ slot = "Shoulder", item = { itemID = 271526 }, fromVault = true })
        )
    end)

    -- When his top set is itself the one-charge answer there is no percentage to
    -- show: it is not behind anything, it IS the set. Hand-built candidates,
    -- because the owner's own week does not contain that shape.
    it("says in your best set when the top set is the one-charge answer", function()
        local line = ns.VaultPanel.OneChargeLine({
            {
                where = "topSet",
                scorePercent = 0,
                hpsDifference = 0,
                catalyzed = {
                    slot = "Shoulder",
                    item = { itemID = 271526 },
                    owned = { name = "Venom-Cursed Lynx's Spaulders", itemLevel = 295 },
                },
            },
        })
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " catalyze your Venom-Cursed Lynx's Spaulders (295) into the tier shoulder - in your best set",
            line.text
        )
        assert.is_nil(line.text:find("%%"))
    end)

    -- No set in the document spends it once: that is the answer, said in those
    -- words, and never filled in with the two-charge set from the line above.
    it("says so plainly when no set of his spends the charge once", function()
        local line = ns.VaultPanel.OneChargeLine({})
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " not in QE Live's export - no set he ranked spends the charge just once",
            line.text
        )
        assert.is_nil(line.candidate)
    end)

    -- His clone matched nothing in the bags: the slot is named and the absence
    -- stated, the same two shapes the fourth line uses.
    it("names the slot and the absence when nothing owned matches his clone", function()
        local line = ns.VaultPanel.OneChargeLine({
            {
                where = "alternative",
                index = 3,
                scorePercent = 0.34,
                hpsDifference = -120,
                catalyzed = { slot = "Shoulder", item = { itemID = 271526 } },
            },
        })
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " catalyze a shoulder you own (QE Live did not say which) - 0.34% behind",
            line.text
        )
    end)

    -- The vault half, end to end through the model (M3-15, WKE-556). A
    -- hand-built `thisWeek` document whose top set converts NOTHING the owner
    -- owns and one thing the vault is offering - the Scavenger's Spaulders of
    -- the replayed snapshot, tier shoulder 271526 at their own bonus IDs.
    --
    -- Two things are pinned at once and no other test pins them: the line is
    -- asked for at all, on a `thisWeek` set that converts none of the owner's
    -- own items, and the vault snapshot reaches QEImport - without it the
    -- charge would still be counted but the reward could not be named.
    --
    -- The bags ARE read here, and the no-scan guard is not weakened by any of
    -- this: without a scan a tier item that is NOT a vault option cannot be told
    -- from a piece the character already wears, so a two-charge set could still
    -- read as one. No scan, no claim, exactly as in M3-14.
    local function vaultOnlyThisWeek()
        local payload = {
            schema = "qe-live-droptimizer",
            version = 1,
            exportedAt = "2026-09-09T19:22:00Z",
            reportId = "handbuilt-556",
            contentType = "Dungeon",
            player = {
                name = "Hotornot",
                realm = "Test",
                region = "US",
                spec = "Restoration Druid",
                gameType = "Retail",
            },
            topSet = {
                score = 1000,
                stats = {},
                items = {
                    {
                        slot = "Shoulder",
                        id = 271526,
                        level = 321,
                        bonusIDs = { 6652, 12699, 12842, 13440, 13662 },
                        gems = {},
                        enchant = "",
                        tertiary = "",
                        setId = 2057,
                        isVault = true,
                        isExclusive = false,
                        source = {},
                    },
                },
            },
            differentials = {},
        }
        local parsed = ns.QEImport.Parse(ns.json.encode(payload))
        assert.is_true(parsed.ok, parsed.reason)
        parsed.verdict.scenario = "thisWeek"
        parsed.verdict.qeSettings = BOXES.thisWeek
        return { { verdict = parsed.verdict, scenario = "thisWeek" } }
    end

    it("asks the question, and names the reward, for a set that converts only the vault's", function()
        local m = model({ scenarios = vaultOnlyThisWeek() })
        assert.equal(
            "one charge (this week, Catalyst used once):"
                .. " catalyze the vault's Scavenger's Spaulders (308) into the tier shoulder - in your best set",
            oneChargeText(m)
        )
        assert.equal(
            "this week (vault upgraded, Catalyst used), as tier: in your best set"
                .. " - needs a Catalyst charge (unknown - run /lootpath refresh) and crests"
                .. " (unknown - run /lootpath refresh)"
                .. " - and catalyze the vault's Scavenger's Spaulders (308) into the tier shoulder",
            m.headline.lines[1].text
        )
    end)

    -- The question only arises because his best set spends the charge more than
    -- once on the owner's items. With no `thisWeek` document, with the Catalyst
    -- box off in the run that made one, or with no bags read, there is no such
    -- set - so there is no line, not even the absence one.
    it("leaves the line off when the question cannot be asked", function()
        assert.is_nil(oneChargeText(model({ inventory = false })))
        assert.is_nil(oneChargeText(model({ dropThisWeek = true })))
        assert.is_nil(oneChargeText(model({
            thisWeekBoxes = { autoUpgradeVault = true, autoUpgradeAll = false, autoCatalyze = false },
        })))
        assert.is_nil(oneChargeText(model({ thisWeekBoxes = false })))
        for _, m in ipairs({ model({ inventory = false }), model({ dropThisWeek = true }) }) do
            for _, line in ipairs(m.headline.lines) do
                assert.is_nil(line.text:find("one charge", 1, true))
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- M5-4 (WKE-553): the vault drawn as the vault. Three rows of three option
-- cells, in Blizzard's own order, over the same real after-reset vault
-- (snapshot 9 of `Lootpath-20260908-124527.lua`) and the same four real QE Live
-- documents the blocks above read. Every cell, every glow and every threshold
-- sentence below is a second view of what `Panel.Lines` already says; nothing
-- here is a second answer.

describe("VaultPanel's grid (WKE-553)", function()
    local ns, world
    local CAPTURE = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
        thisWeek = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json",
        maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
    }
    local ORDER = { "asOffered", "catalyzed", "thisWeek", "maxed" }
    local WEAPON_KEY = "251935:6652:12841"
    local SPAULDERS_KEY = "251146:6652:12699:12842:13440:13662"

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, CAPTURE))
    end)

    after_each(function()
        H.unload()
    end)

    local function scenarios()
        local out = {}
        for _, name in ipairs(ORDER) do
            local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES[name]))
            assert(parsed.ok, parsed.reason)
            parsed.verdict.scenario = name
            parsed.verdict.qeSettings = {
                autoUpgradeVault = name == "maxed" or name == "thisWeek",
                autoUpgradeAll = name == "maxed",
                autoCatalyze = name ~= "asOffered",
            }
            out[#out + 1] = { verdict = parsed.verdict, scenario = name }
        end
        return out
    end

    local function model(highlight)
        local list = scenarios()
        return ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = list,
            verdict = list[1].verdict,
            highlightScenario = highlight,
            now = 1788900000,
        })
    end

    local function rowByKey(m, key)
        for _, gridRow in ipairs(m.grid.rows) do
            for _, cell in ipairs(gridRow.cells) do
                if cell.reward and cell.reward.key == key then
                    return gridRow, cell
                end
            end
        end
        return nil, nil
    end

    -- Deliverable 1: the grid itself.
    it("draws three rows of three cells, in Blizzard's own order", function()
        local m = model("asOffered")
        assert.equal(3, #m.grid.rows)
        assert.same({ "Raid", "Activities", "World" }, {
            m.grid.rows[1].key,
            m.grid.rows[2].key,
            m.grid.rows[3].key,
        })
        -- No RAIDS / DUNGEONS / WORLD global in this harness, so each row falls
        -- back to the label measured off the owner's own vault screen.
        assert.same({ "Raids", "Dungeons", "World" }, {
            m.grid.rows[1].label,
            m.grid.rows[2].label,
            m.grid.rows[3].label,
        })
        for _, gridRow in ipairs(m.grid.rows) do
            assert.equal(3, #gridRow.cells)
        end
    end)

    -- The red proof for the line above: define the globals and the rows are
    -- headed by the client's words instead. Sentinel values, because no
    -- transcript in this repo says what RAIDS actually reads.
    it("prefers the client's own row headings when it has them", function()
        _G.RAIDS = "PLACEHOLDER RAIDS"
        _G.DUNGEONS = "PLACEHOLDER DUNGEONS"
        _G.WORLD = "PLACEHOLDER WORLD"
        local m = model("asOffered")
        assert.same({ "PLACEHOLDER RAIDS", "PLACEHOLDER DUNGEONS", "PLACEHOLDER WORLD" }, {
            m.grid.rows[1].label,
            m.grid.rows[2].label,
            m.grid.rows[3].label,
        })
        -- And the same words reach the option list, so the two views of one
        -- vault never head the same row differently.
        assert.equal("PLACEHOLDER WORLD", m.grid.rows[3].cells[2].reward.rowLabel)
        _G.RAIDS, _G.DUNGEONS, _G.WORLD = nil, nil, nil
    end)

    it("puts each reward in the cell the client offered it in", function()
        local m = model("asOffered")
        -- Measured 2026-09-08: World 1 and 2 carry gear, Dungeons 1 and 2 carry
        -- gear, every Raid row is empty and the third cell of each row is not
        -- earned yet.
        assert.equal("reward", m.grid.rows[3].cells[1].kind)
        assert.equal("reward", m.grid.rows[3].cells[2].kind)
        assert.equal("locked", m.grid.rows[3].cells[3].kind)
        assert.equal("reward", m.grid.rows[2].cells[1].kind)
        assert.equal("reward", m.grid.rows[2].cells[2].kind)
        assert.equal("locked", m.grid.rows[2].cells[3].kind)
        for _, cell in ipairs(m.grid.rows[1].cells) do
            assert.equal("locked", cell.kind)
        end
        assert.equal(WEAPON_KEY, m.grid.rows[3].cells[2].reward.key)
        assert.equal(SPAULDERS_KEY, m.grid.rows[2].cells[1].reward.key)
        assert.equal("Scavenger's Spaulders", m.grid.rows[2].cells[1].name)
        -- The cell binds the item the way M5-1's line wants it, off the client's
        -- own record: the icon and the quality, never guessed.
        local item = m.grid.rows[3].cells[2].item
        assert.equal(251935, item.itemID)
        assert.equal("Lightgrasp Worldroot", item.name)
        assert.equal(305, item.itemLevel)
        assert.is_number(item.icon)
        assert.is_number(item.quality)
    end)

    it("keeps M3-7's level wording on the cell's second line", function()
        local m = model("asOffered")
        local weapon = m.grid.rows[3].cells[2]
        assert.is_truthy(weapon.second:find(weapon.reward.levelText, 1, true))
        assert.is_truthy(weapon.second:find(weapon.reward.slot, 1, true))
        assert.is_truthy(weapon.second:find("305", 1, true))
        -- The `maxed` run is the one whose importer had auto-upgrade-vault on,
        -- so it is the one whose own level for this weapon differs from the
        -- client's - and M3-7's rule puts both numbers on the line.
        local upgraded = model("maxed").grid.rows[3].cells[2]
        assert.is_truthy(upgraded.second:find("305", 1, true))
        assert.is_truthy(upgraded.second:find("QE Live valued it at 321", 1, true))
    end)

    -- A locked cell says what the client says it needs. Blizzard's own frame
    -- prefers the activity's `raidString` on a Raid row, so the Raid cells here
    -- read the client's own sentence; the harness has no
    -- WEEKLY_REWARDS_THRESHOLD_DUNGEONS, so those cells keep the progress
    -- wording the text panel already prints.
    it("shows Blizzard's threshold sentence on a cell with no reward", function()
        local m = model("asOffered")
        assert.equal("Defeat 2 Midnight Season 2 |4Boss:Bosses", m.grid.rows[1].cells[1].thresholdText)
        assert.equal("Defeat 4 Midnight Season 2 |4Boss:Bosses", m.grid.rows[1].cells[2].thresholdText)
        assert.equal("Defeat 6 Midnight Season 2 |4Boss:Bosses", m.grid.rows[1].cells[3].text)
        assert.is_nil(m.grid.rows[2].cells[3].thresholdText)
        assert.equal("0/8", m.grid.rows[2].cells[3].text)
    end)

    it("uses the client's own dungeon and world sentences when it has them", function()
        _G.WEEKLY_REWARDS_THRESHOLD_DUNGEONS = "Complete %d Dungeons"
        _G.WEEKLY_REWARDS_THRESHOLD_WORLD = "Complete %d World Activities"
        local m = model("asOffered")
        assert.equal("Complete 8 Dungeons", m.grid.rows[2].cells[3].text)
        assert.equal("Complete 8 World Activities", m.grid.rows[3].cells[3].text)
        _G.WEEKLY_REWARDS_THRESHOLD_DUNGEONS, _G.WEEKLY_REWARDS_THRESHOLD_WORLD = nil, nil
    end)

    it("never lets a pattern the client wrote throw the panel", function()
        _G.WEEKLY_REWARDS_THRESHOLD_DUNGEONS = "Complete %z Dungeons"
        local m = model("asOffered")
        assert.equal("0/8", m.grid.rows[2].cells[3].text)
        _G.WEEKLY_REWARDS_THRESHOLD_DUNGEONS = nil
    end)

    -- Deliverable 2: the pick.
    it("glows the cell QE Live's pick names, under each scenario", function()
        local function selected(m)
            local found = {}
            for rowIndex, gridRow in ipairs(m.grid.rows) do
                for cellIndex, cell in ipairs(gridRow.cells) do
                    if cell.selected then
                        found[#found + 1] = { rowIndex, cellIndex, cell.reward and cell.reward.key }
                    end
                end
            end
            return found
        end
        -- Under `catalyzed` his top set holds the tier shoulder he cloned from
        -- the Dungeons 1 shoulders; under `maxed` and `thisWeek` it is the World
        -- 2 weapon. Each is his answer, and each is one cell.
        assert.same({ { 2, 1, SPAULDERS_KEY } }, selected(model("catalyzed")))
        assert.same({ { 3, 2, WEAPON_KEY } }, selected(model("maxed")))
        assert.same({ { 3, 2, WEAPON_KEY } }, selected(model("thisWeek")))
        for _, name in ipairs(ORDER) do
            assert.is_true(#selected(model(name)) <= 1, name)
        end
    end)

    it("labels the pick, and labels the closest instead when nothing beats the set", function()
        local catalyzed = model("catalyzed")
        assert.equal("QE Live's pick", catalyzed.grid.rows[2].cells[1].label)
        assert.is_false(catalyzed.grid.rows[2].cells[1].closest)
        assert.is_false(catalyzed.headline.closest)

        -- Under `asOffered` the best he says about anything in this vault is
        -- still "worse than your set", so the first line refuses to call it a
        -- pick - and no cell glows.
        local offered = model("asOffered")
        assert.is_true(offered.headline.closest)
        assert.is_truthy(offered.headline.text:find("none - nothing in the vault beats your set", 1, true))
        local _, cell = rowByKey(offered, WEAPON_KEY)
        assert.is_false(cell.selected)
        assert.is_true(cell.closest)
        assert.equal("closest", cell.label)
        for _, gridRow in ipairs(offered.grid.rows) do
            for _, gridCell in ipairs(gridRow.cells) do
                assert.is_falsy(gridCell.selected)
            end
        end
    end)

    -- Deliverable 4: one scenario on the cell, every scenario in the tooltip.
    it("says the highlighted scenario's line on the cell and keeps the rest for the hover", function()
        local m = model("maxed")
        local _, weapon = rowByKey(m, WEAPON_KEY)
        assert.equal("everything upgraded: in your best set", weapon.verdictText)
        assert.equal("better", weapon.verdictTone)
        assert.same(weapon.reward.verdictLines, weapon.tooltipLines)
        assert.equal(4, #weapon.tooltipLines)

        local catalyzed = model("catalyzed")
        local _, spaulders = rowByKey(catalyzed, SPAULDERS_KEY)
        assert.equal("catalyzed, as tier: in your best set", spaulders.verdictText)
        -- His own answer is about his catalyzed clone, so the cell says so in
        -- his own tag words.
        assert.same({ "catalyst", "tier" }, spaulders.tags)
        assert.is_truthy(spaulders.footer:find("hover for the other scenarios", 1, true))
    end)

    -- The whole point of building the tooltip out of `Panel.ScenarioLine`'s own
    -- strings: the hover and the text panel cannot disagree.
    it("hovers exactly the lines the text panel prints under the same option", function()
        local m = model("maxed")
        local lines = ns.VaultPanel.Lines(m)
        local function printed(text)
            for _, line in ipairs(lines) do
                if line == "    " .. text then
                    return true
                end
            end
            return false
        end
        local seen = 0
        for _, gridRow in ipairs(m.grid.rows) do
            for _, cell in ipairs(gridRow.cells) do
                for _, line in ipairs(cell.tooltipLines or {}) do
                    assert.is_true(printed(line), "the hover said what the panel does not: " .. line)
                    seen = seen + 1
                end
            end
        end
        assert.is_true(seen > 0)
    end)

    it("says nothing of QE Live's about an option he never ranked", function()
        local m = model("maxed")
        local unranked
        for _, gridRow in ipairs(m.grid.rows) do
            for _, cell in ipairs(gridRow.cells) do
                if cell.kind == "reward" and #cell.tooltipLines == 0 then
                    unranked = cell
                end
            end
        end
        assert.is_not_nil(unranked)
        assert.equal("not ranked by QE Live in any scenario", unranked.verdictText)
        assert.equal("none", unranked.verdictTone)
        assert.same({}, unranked.tags)
    end)

    -- Nothing the client hands over is dropped by the grid: the rows Blizzard
    -- does not draw keep their place under it, in the words the text list
    -- already gives them.
    it("names the options that sit outside the three rows rather than losing them", function()
        local m = model("asOffered")
        assert.equal(2, #m.grid.other)
        for _, option in ipairs(m.grid.other) do
            assert.is_truthy(m.grid.otherText:find(option.headerText, 1, true))
        end
        assert.is_truthy(m.grid.otherText:find("Concession", 1, true))
        -- Every option is either in a cell or in that list.
        local placed = 0
        for _, gridRow in ipairs(m.grid.rows) do
            for _, cell in ipairs(gridRow.cells) do
                if cell.kind ~= "empty" then
                    placed = placed + 1
                end
            end
        end
        assert.equal(#m.options, placed + #m.grid.other)
    end)

    -- Deliverable 3's other half: the currencies, with the client's own icon
    -- and the client's own name.
    it("builds a currency chip per crest and one for the Catalyst charge", function()
        local currencies = {
            ok = true,
            crests = {
                { name = "Adventurer Mistcrest", currencyID = 3442, quantity = 356, iconFileID = 900101 },
                { name = "Myth Mistcrest", currencyID = 3446, quantity = 20, iconFileID = 900105 },
            },
            catalyst = {
                name = "Venomblight Manaflux",
                currencyID = 3465,
                quantity = 1,
                maxQuantity = 8,
                iconFileID = 900102,
            },
        }
        local chips = ns.VaultPanel.CurrencyChips(currencies)
        assert.equal(3, #chips)
        assert.same({
            key = "catalyst",
            currencyID = 3465,
            name = "Venomblight Manaflux",
            icon = 900102,
            count = "1 of 8",
            text = "Venomblight Manaflux 1 of 8",
        }, chips[1])
        assert.equal("Adventurer Mistcrest 356", chips[2].text)
        assert.equal(900105, chips[3].icon)
        -- Nothing is computed from any of it: the strip is a name, an icon and
        -- the client's own number.
        assert.equal("Myth Mistcrest 20", chips[3].text)
    end)

    it("draws no strip at all when nothing has read the currencies", function()
        assert.same({}, ns.VaultPanel.CurrencyChips(nil))
        assert.same({}, ns.VaultPanel.CurrencyChips({ ok = false, reason = "combat" }))
        assert.same({}, ns.VaultPanel.CurrencyChips({ ok = true }))
    end)

    it("carries the chips on the model the panel draws", function()
        local list = scenarios()
        local m = ns.VaultPanel.Model({
            vault = ns.Vault.Options(),
            scenarios = list,
            verdict = list[1].verdict,
            currencies = {
                ok = true,
                crests = { { name = "Hero Mistcrest", currencyID = 3445, quantity = 21, iconFileID = 900104 } },
            },
            now = 1788900000,
        })
        assert.equal(1, #m.currencyChips)
        assert.equal("Hero Mistcrest 21", m.currencyChips[1].text)
    end)
end)

-- ---------------------------------------------------------------------------
-- M5-4 (WKE-553), drawn: the same grid through the real frames. What is
-- checked here is what a widget was TOLD - which atlas a glow was given, which
-- texture a chip's icon was set to, which strings a hover put on the tooltip -
-- because that is a decision this addon makes. What any of it looks like on
-- the owner's screen is an in-game step and is not a test.

describe("VaultPanel's grid, drawn (WKE-553)", function()
    local ns, world
    local CAPTURE = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
        thisWeek = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json",
        maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
    }
    local BOXES = {
        asOffered = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = false },
        catalyzed = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = true },
        thisWeek = { autoUpgradeVault = true, autoUpgradeAll = false, autoCatalyze = true },
        maxed = { autoUpgradeVault = true, autoUpgradeAll = true, autoCatalyze = true },
    }
    local SPAULDERS_KEY = "251146:6652:12699:12842:13440:13662"
    local WEAPON_KEY = "251935:6652:12841"
    local frame

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", 9, CAPTURE))
        R.inventory(world, R.snapshot("inventory", 7, CAPTURE))
        for _, name in ipairs({ "asOffered", "catalyzed", "thisWeek", "maxed" }) do
            local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES[name]))
            assert(parsed.ok, parsed.reason)
            parsed.verdict.scenario = name
            parsed.verdict.qeSettings = BOXES[name]
            ns.QEImport.Store(parsed.verdict)
        end
        ns.db.profile.settings.contentType = ns.QEImport.ContentTypeKey(ns.QEImport.Current())
        frame = ns.VaultPanel.Create()
    end)

    after_each(function()
        H.unload()
    end)

    local function refresh(scenario)
        ns.db.profile.settings.vaultScenario = scenario
        return frame:Refresh({ now = 1788900000 })
    end

    local function cellFor(model, key)
        for rowIndex, gridRow in ipairs(model.grid.rows) do
            for cellIndex, cell in ipairs(gridRow.cells) do
                if cell.reward and cell.reward.key == key then
                    return frame.gridRows[rowIndex].cells[cellIndex], cell
                end
            end
        end
        return nil, nil
    end

    it("draws Blizzard's own selected art on the pick's cell and on no other", function()
        local model = refresh("catalyzed")
        local drawn = cellFor(model, SPAULDERS_KEY)
        assert.equal("evergreen-weeklyrewards-reward-selected", drawn.selectedTexture:GetAtlas())
        assert.is_true(drawn.selectedTexture:IsShown())
        -- The atlas is there, so the fallback border is not.
        for _, edge in ipairs(drawn.edges) do
            assert.is_false(edge:IsShown())
        end
        local marked = 0
        for _, gridRow in ipairs(frame.gridRows) do
            for _, cell in ipairs(gridRow.cells) do
                if cell.selectedTexture:IsShown() then
                    marked = marked + 1
                end
            end
        end
        assert.equal(1, marked)
    end)

    -- The red proof: take the atlas away, as a future build may, and the pick
    -- is still marked - in QE Live's own gold, on all four edges.
    it("falls back to a gold border on a client without the atlas", function()
        world.atlases["evergreen-weeklyrewards-reward-selected"] = nil
        local model = refresh("catalyzed")
        local drawn = cellFor(model, SPAULDERS_KEY)
        assert.is_false(drawn.selectedTexture:IsShown())
        -- FFDF14 as the three numbers a tint wants: 255/255, 223/255, 20/255.
        -- The same accent M5-1 gives every "better" badge, so the eye learns
        -- one colour and finds it on every tab.
        assert.equal(ns.UI.ItemLine.TONE.better.hex, ns.VaultPanel.SELECTED_HEX)
        for _, edge in ipairs(drawn.edges) do
            assert.is_true(edge:IsShown())
            assert.same({ 1, 0.87451, 0.078431, 1 }, {
                math.floor(edge.vertexColor[1] * 1e6 + 0.5) / 1e6,
                math.floor(edge.vertexColor[2] * 1e6 + 0.5) / 1e6,
                math.floor(edge.vertexColor[3] * 1e6 + 0.5) / 1e6,
                edge.vertexColor[4],
            })
        end
    end)

    it("moves the glow when the scenario changes, and shows none when nothing beats the set", function()
        local catalyzed = refresh("catalyzed")
        assert.is_true(cellFor(catalyzed, SPAULDERS_KEY).selectedTexture:IsShown())
        local maxed = refresh("maxed")
        assert.is_false(cellFor(maxed, SPAULDERS_KEY).selectedTexture:IsShown())
        assert.is_true(cellFor(maxed, WEAPON_KEY).selectedTexture:IsShown())
        local pickLabel = cellFor(maxed, WEAPON_KEY).label:GetText()
        assert.equal("QE Live's pick", (pickLabel:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))

        local offered = refresh("asOffered")
        for _, gridRow in ipairs(frame.gridRows) do
            for _, cell in ipairs(gridRow.cells) do
                assert.is_false(cell.selectedTexture:IsShown())
                for _, edge in ipairs(cell.edges) do
                    assert.is_false(edge:IsShown())
                end
            end
        end
        local closest = cellFor(offered, WEAPON_KEY)
        assert.is_true(closest.label:IsShown())
        assert.is_truthy(closest.label:GetText():find("closest", 1, true))
    end)

    it("binds every cell as an M5-1 item line, icon and quality border and all", function()
        local model = refresh("maxed")
        local drawn, cell = cellFor(model, WEAPON_KEY)
        assert.is_true(drawn.line:IsShown())
        assert.is_false(drawn.locked:IsShown())
        assert.equal(cell.item.icon, drawn.line.icon:GetTexture())
        assert.equal("305", drawn.line.level:GetText())
        assert.is_true(drawn.line.border:IsShown())
        assert.is_truthy(drawn.line.name:GetText():find("Lightgrasp Worldroot", 1, true))
        assert.is_truthy(drawn.verdict:GetText():find("everything upgraded: in your best set", 1, true))
        -- QE Live's gold on his own "better" answer; the same hex M5-1 gives
        -- every badge on every tab.
        assert.is_truthy(drawn.verdict:GetText():find(ns.UI.ItemLine.TONE.better.hex, 1, true))
        -- The keystone that rode in with it, in words and at no level.
        assert.equal("+ Mythic Keystone", drawn.extras:GetText())
    end)

    it("draws a locked cell with the client's own threshold sentence and no item", function()
        refresh("maxed")
        local raid = frame.gridRows[1].cells[1]
        assert.is_true(raid:IsShown())
        assert.is_false(raid.line:IsShown())
        assert.is_true(raid.locked:IsShown())
        assert.equal("Defeat 2 Midnight Season 2 |4Boss:Bosses", raid.locked:GetText())
        assert.equal("", raid.verdict:GetText())
    end)

    it("hovers a cell with every scenario's line, and the item line with the item", function()
        local model = refresh("maxed")
        local drawn = cellFor(model, WEAPON_KEY)
        drawn:GetScript("OnEnter")(drawn)
        local shown = world.tooltip:Text()
        assert.is_truthy(shown:find("Lightgrasp Worldroot", 1, true))
        for _, line in ipairs(select(2, cellFor(model, WEAPON_KEY)).tooltipLines) do
            assert.is_truthy(shown:find(line, 1, true), "the hover lost a line: " .. line)
        end
        -- The item itself is the item line's own hover, with the client's link
        -- and the shopping compare - never a line of ours.
        drawn.line.iconButton:Enter()
        assert.equal(select(2, cellFor(model, WEAPON_KEY)).item.link, world.tooltip.hyperlink)
        assert.equal(1, #world.compareCalls)
    end)

    it("draws one currency chip per crest and one for the charge, with the client's icons", function()
        world.currencies = {
            { name = "Placeholder Group", currencyID = 0, isHeader = true, isHeaderExpanded = true, quantity = 0 },
        }
        world.currencyByID = {
            [3442] = {
                name = "Adventurer Mistcrest",
                currencyID = 3442,
                isHeader = false,
                quantity = 356,
                iconFileID = 900101,
            },
            [3465] = {
                name = "Venomblight Manaflux",
                currencyID = 3465,
                isHeader = false,
                quantity = 1,
                maxQuantity = 8,
                iconFileID = 900102,
            },
        }
        refresh("thisWeek")
        assert.is_true(frame.chips[1]:IsShown())
        assert.equal(900102, frame.chips[1].icon:GetTexture())
        assert.equal("Venomblight Manaflux 1 of 8", frame.chips[1].text:GetText())
        assert.equal(900101, frame.chips[2].icon:GetTexture())
        assert.equal("Adventurer Mistcrest 356", frame.chips[2].text:GetText())
        assert.is_false(frame.currencyNote:IsShown())
        -- Nothing captured: no strip, and the tab says why rather than drawing
        -- a row of question marks.
        world.currencies, world.currencyByID = {}, {}
        refresh("thisWeek")
        assert.is_false(frame.chips[1]:IsShown())
        assert.is_true(frame.currencyNote:IsShown())
    end)

    -- Deliverable 4's other half: the scenario dropdown on the tab itself.
    it("puts the scenario dropdown on the tab and writes through the one setting", function()
        refresh("maxed")
        local dropdown = frame.scenarioDropdown
        assert.is_not_nil(dropdown)
        assert.equal("Vault highlight", dropdown:GetDefaultText())
        dropdown:GenerateMenu()
        assert.equal(#ns.QEImport.SCENARIOS, #dropdown.menuEntries)
        for index, scenario in ipairs(ns.QEImport.SCENARIOS) do
            -- The Settings page's own words, so the two ways to this setting
            -- never label it differently.
            assert.equal(ns.UI.Options.SCENARIO_CHOICE_LABEL[scenario], dropdown.menuEntries[index].text)
        end
        -- The entry the setting is on is the one that reads as selected.
        local maxedIndex
        for index, scenario in ipairs(ns.QEImport.SCENARIOS) do
            if scenario == "maxed" then
                maxedIndex = index
            end
        end
        assert.equal(maxedIndex, dropdown:SelectedIndex())

        -- Picking another one is the setting changing, and the tab redraws.
        local catalyzedIndex
        for index, scenario in ipairs(ns.QEImport.SCENARIOS) do
            if scenario == "catalyzed" then
                catalyzedIndex = index
            end
        end
        assert.is_true(dropdown:Pick(catalyzedIndex))
        assert.equal("catalyzed", ns.UI.Options.GetVaultScenario())
        local model = frame:Refresh({ now = 1788900000 })
        assert.equal("catalyzed", model.highlightScenario)
        assert.is_true(cellFor(model, SPAULDERS_KEY).selectedTexture:IsShown())
    end)
end)
