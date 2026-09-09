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

describe("VaultPanel frames", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
    end)

    after_each(function()
        H.unload()
    end)

    it("renders the model's lines into the panel's font strings", function()
        generateReward(world, 1, COVERED_ITEM.id, COVERED_ITEM.bonusIDs, COVERED_ITEM.name, 298)
        ns.QEImport.Store(realVerdict(ns))
        local frame = ns.VaultPanel.Create()
        local model = frame:Refresh()
        local lines = ns.VaultPanel.Lines(model)
        assert.is_true(#lines >= 11)
        for i, line in ipairs(lines) do
            assert.equal(line, frame.rows[i]:GetText())
        end
        assert.equal(ns.VaultPanel.NOTE, frame.note:GetText())
        assert.equal("QE Live: in your best set", model.best.value)
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

    it("hides the rows a shorter render does not use", function()
        ns.QEImport.Store(realVerdict(ns))
        local frame = ns.VaultPanel.Create()
        local long = #ns.VaultPanel.Lines(frame:Refresh())
        world.inCombat = true
        frame:Refresh()
        assert.equal(1, #frame.lines)
        assert.is_true(long > 2)
        for i = 2, long do
            assert.equal("", frame.rows[i]:GetText())
            assert.is_false(frame.rows[i]:IsShown())
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
