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
        assert.same({ ns.VaultPanel.NOTE, "The vault could not be read: combat" }, ns.VaultPanel.Lines(model))
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
        assert.equal(2, #frame.lines)
        assert.is_true(long > 2)
        for i = 3, long do
            assert.equal("", frame.rows[i]:GetText())
            assert.is_false(frame.rows[i]:IsShown())
        end
    end)
end)
