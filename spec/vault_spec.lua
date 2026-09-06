-- spec/vault_spec.lua (M3-3, WKE-524)
-- ns.Vault over the committed `capture vault` transcripts, replayed through the
-- stub so C_WeeklyRewards answers exactly what the owner's client said.
--
-- Two halves, kept apart on purpose:
--   * the activity half is measured - four snapshots across 2026-09-05 and
--     2026-09-06, one week with no progress and one with progress on three
--     thresholds;
--   * the REWARD half is not. `rewards` was empty in every activity of every
--     snapshot except the Concession row, which carried a currency. Those tests
--     drive the stub with Blizzard's exported WeeklyRewardActivityRewardInfo
--     shape ({ type, id, quantity, itemDBID? }) and say so, and WKE-523's
--     after-reset capture is what will confirm them.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

-- Snapshot order inside the 2026-09-06 transcript: SavedVariables accumulate,
-- so 1 and 2 are the 09-05 pair (no progress) and 3 and 4 the 09-06 pair
-- (progress on three thresholds), before and after opening the vault window.
local NO_PROGRESS = 1
local WITH_PROGRESS = 3

-- An item link built field for field the way ns.ParseItemLink reads one:
-- itemID(1), enchant(2), gems(3-6), suffix(7), unique(8), linkLevel(9),
-- specID(10), flags(11), context(12), numBonusIDs(13), then the bonus IDs. The
-- key each test asserts is ns.ItemKey's, so a mistake here fails the test
-- rather than passing quietly.
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

-- One generated reward, in Blizzard's documented shape (not measured; see the
-- file header). `itemDBID` is opaque to us, so the stub's link table is keyed
-- on whatever the activity carries.
local function generateReward(world, activityIndex, itemID, bonusIDs, name, itemLevel)
    local link = itemLink(itemID, bonusIDs, name)
    local dbid = "vault-" .. tostring(itemID)
    world.vault.activities[activityIndex].rewards = {
        { type = 1, id = itemID, quantity = 1, itemDBID = dbid },
    }
    world.vault.links[dbid] = link
    world.items[link] = {
        level = itemLevel,
        detailed = { itemLevel, false, itemLevel, n = 3 },
        info = { name, link, 4, itemLevel, n = 4 },
        instant = { itemID, "Armor", "Plate", "INVTYPE_FEET", nil, 4, 8, n = 7 },
    }
    return link, dbid
end

describe("ns.Vault over the committed transcripts", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("reads the week with progress as the client reported it", function()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
        local result = ns.Vault.Options()
        assert.is_true(result.ok)
        assert.equal(10, #result.options)
        assert.equal(0, result.secretsSeen)
        assert.is_false(result.hasAvailableRewards)

        local byID = {}
        for _, option in ipairs(result.options) do
            byID[option.id] = option
        end
        -- Measured, 2026-09-06 16:11:30: World 207 at 2/2 level 10, 208 at 5/4
        -- level 8, 209 at 5/8; Mythic+ 213 at 1/1 level 3; Raid 210 at 0/2.
        assert.equal(2, byID[207].progress)
        assert.equal(2, byID[207].threshold)
        assert.equal(10, byID[207].level)
        assert.is_true(byID[207].unlocked)
        assert.equal(5, byID[208].progress)
        assert.is_true(byID[208].unlocked)
        assert.equal(5, byID[209].progress)
        assert.equal(8, byID[209].threshold)
        assert.is_false(byID[209].unlocked)
        assert.is_true(byID[213].unlocked)
        assert.is_false(byID[210].unlocked)
    end)

    it("labels each row with the threshold type the env capture enumerated", function()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
        local byID = {}
        for _, option in ipairs(ns.Vault.Options().options) do
            byID[option.id] = option
        end
        assert.equal("World", byID[207].typeLabel)
        assert.equal("Raid", byID[210].typeLabel)
        assert.equal("Mythic+", byID[213].typeLabel)
        assert.equal("Concession", byID[229].typeLabel)
        -- Enum.WeeklyRewardChestThresholdType, 2026-09-05 capture env.
        assert.equal(1, ns.Vault.ThresholdType("Activities"))
        assert.equal(5, ns.Vault.ThresholdType("Concession"))
        assert.equal(6, ns.Vault.ThresholdType("World"))
    end)

    it("reads the week with no progress as nothing unlocked", function()
        R.vault(world, R.snapshot("vault", NO_PROGRESS, R.JOURNAL))
        local result = ns.Vault.Options()
        assert.equal(10, #result.options)
        for _, option in ipairs(result.options) do
            assert.equal(0, option.progress)
            assert.is_false(option.unlocked)
            assert.equal(0, #option.rewards)
        end
    end)

    it("skips the Concession row's currency instead of showing it as an item", function()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
        -- Measured: activity 229 carries { id = 3513, type = 2, quantity = 1 }
        -- and no itemDBID. Enum.CachedRewardType 2 is Currency.
        local raw
        for _, activity in ipairs(world.vault.activities) do
            if activity.id == 229 then
                raw = activity.rewards[1]
            end
        end
        assert.equal(3513, raw.id)
        assert.equal(ns.Vault.RewardType("Currency"), raw.type)
        assert.is_nil(raw.itemDBID)
        assert.is_nil(ns.Vault.Reward(raw))
        for _, option in ipairs(ns.Vault.Options().options) do
            assert.equal(0, #option.rewards)
        end
    end)

    it("turns a generated item reward into a keyed record", function()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
        -- Blizzard's documented reward shape, not a measured one (file header).
        local bonusIDs = { 13440, 6652, 13662, 12699, 12835 }
        local link = generateReward(world, 1, 251153, bonusIDs, "Arctic Explorer's Legwraps", 298)
        local options = ns.Vault.Options().options
        local reward = options[1].rewards[1]
        assert.equal(1, #options[1].rewards)
        assert.equal(link, reward.link)
        assert.equal(ns.ItemKey(251153, bonusIDs), reward.key)
        assert.equal(251153, reward.itemID)
        assert.equal(298, reward.itemLevel)
        assert.equal("Feet", reward.slot)
        assert.equal("Arctic Explorer's Legwraps", reward.name)
    end)

    it("keeps an option whose link never arrives, with no key rather than a wrong one", function()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
        world.vault.activities[1].rewards = { { type = 1, id = 251153, quantity = 1, itemDBID = "no-link" } }
        local reward = ns.Vault.Options().options[1].rewards[1]
        assert.equal("no-link", reward.itemDBID)
        assert.is_nil(reward.link)
        assert.is_nil(reward.key)
        assert.is_nil(reward.itemLevel)
    end)
end)

describe("ns.Vault guards", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", WITH_PROGRESS, R.JOURNAL))
    end)

    after_each(function()
        H.unload()
    end)

    it("refuses in combat", function()
        world.inCombat = true
        local result = ns.Vault.Options()
        assert.is_false(result.ok)
        assert.equal("combat", result.reason)
        -- and the same call answers once combat is over
        world.inCombat = false
        assert.is_true(ns.Vault.Options().ok)
    end)

    it("refuses plainly when the client has no vault API", function()
        _G.C_WeeklyRewards = nil
        local result = ns.Vault.Options()
        assert.is_false(result.ok)
        assert.equal("no vault API", result.reason)
    end)

    -- The stub's GetActivities hands back a deep copy, which loses the identity
    -- its secret sentinels are recognised by, so these two drive the API
    -- directly: what is under test is the guard in ns.Vault, not the stub.
    it("drops a secret activity and counts it", function()
        local activities = _G.C_WeeklyRewards.GetActivities()
        activities[1] = world.secretTable("activity")
        _G.C_WeeklyRewards.GetActivities = function()
            return activities
        end
        local result = ns.Vault.Options()
        assert.is_true(result.ok)
        assert.equal(9, #result.options)
        assert.equal(1, result.secretsSeen)
    end)

    it("drops a secret field and falls back rather than storing the marker", function()
        local activities = _G.C_WeeklyRewards.GetActivities()
        activities[1].threshold = world.secret("threshold")
        _G.C_WeeklyRewards.GetActivities = function()
            return activities
        end
        local result = ns.Vault.Options()
        assert.equal(10, #result.options)
        assert.equal(0, result.options[1].threshold)
        assert.is_false(result.options[1].unlocked)
        assert.equal(1, result.secretsSeen)
    end)

    it("names every client function it calls", function()
        assert.same({
            "C_WeeklyRewards.HasAvailableRewards",
            "C_WeeklyRewards.CanClaimRewards",
            "C_WeeklyRewards.GetActivities",
            "C_WeeklyRewards.GetItemHyperlink",
            "C_DateAndTime.GetSecondsUntilWeeklyReset",
        }, ns.Vault.FUNCTION_NAMES)
    end)
end)
