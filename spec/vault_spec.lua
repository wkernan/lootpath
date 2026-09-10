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
            "C_Item.GetDetailedItemLevelInfo",
            "C_Item.GetItemInfoInstant",
            "C_Item.GetItemInfo",
        }, ns.Vault.FUNCTION_NAMES)
        -- RequestLoadItemDataByID left this list in M5-1 (WKE-550) with the
        -- asking itself: ns.ItemData calls it now and names it, and a list
        -- that claimed a call this file no longer makes would be worth nothing.
        assert.same({
            "C_Item.GetItemInfoInstant",
            "C_Item.GetItemInfo",
            "C_Item.GetDetailedItemLevelInfo",
            "C_Item.RequestLoadItemDataByID",
        }, ns.ItemData.FUNCTION_NAMES)
        -- Every name resolves on the stub; the literal call sites are the only
        -- callers, and nothing in either file is reached through these lists.
        for _, list in ipairs({ ns.Vault.FUNCTION_NAMES, ns.ItemData.FUNCTION_NAMES }) do
            for _, name in ipairs(list) do
                local namespace, member = name:match("^(C_[%w_]+)%.([%w_]+)$")
                assert.is_function(_G[namespace][member], name)
            end
        end
    end)
end)

-- The reward half, measured at last: the 2026-09-08 12:45:26 snapshot, taken
-- after the weekly reset with the vault window open and nothing claimed. Every
-- value asserted here was read from that transcript (WKE-523, second visit).
describe("ns.Vault over the after-reset transcript (generated rewards)", function()
    local ns, world
    local AFTER_RESET = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local SNAPSHOT = 9 -- the ninth vault snapshot in that file is 2026-09-08T12:45:26

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", SNAPSHOT, AFTER_RESET))
    end)

    after_each(function()
        H.unload()
    end)

    local function byID(result)
        local map = {}
        for _, option in ipairs(result.options) do
            map[option.id] = option
        end
        return map
    end

    -- M5-4 (WKE-553): the client's own sentence for a Raid row's threshold,
    -- kept because Blizzard's own vault frame prefers it over
    -- WEEKLY_REWARDS_THRESHOLD_RAID and the drawn grid has to say the same
    -- thing. Recorded verbatim, %d and plural marker and all; nothing formats
    -- it in this module.
    it("keeps the client's own raidString on every option that has one", function()
        local options = byID(ns.Vault.Options())
        assert.equal("Defeat %d Midnight Season 2 |4Boss:Bosses", options[210].raidString)
        assert.equal("Defeat %d Midnight Season 2 |4Boss:Bosses", options[212].raidString)
        -- Measured: this client sent the same string on every row, Raid or not.
        assert.equal("Defeat %d Midnight Season 2 |4Boss:Bosses", options[208].raidString)
        assert.equal(0, ns.Vault.Options().secretsSeen)
    end)

    it("reads a week whose rewards are generated but unclaimed", function()
        local result = ns.Vault.Options()
        assert.is_true(result.ok)
        assert.is_true(result.hasAvailableRewards)
        assert.is_true(result.canClaimRewards)
        assert.equal(594873, result.secondsUntilWeeklyReset)
        assert.equal(0, result.secretsSeen)
        assert.equal(11, #result.options)
        -- Progress reset to 0 on every row while the rewards stayed claimable.
        local options = byID(result)
        assert.equal(0, options[207].progress)
        assert.equal(2, options[207].threshold)
        assert.equal(2, #options[207].rewards)
        assert.equal(0, options[208].progress)
        assert.equal(2, #options[208].rewards)
        assert.equal(0, #options[209].rewards)
        assert.equal(0, #options[210].rewards)
        assert.equal(2, #options[213].rewards)
        assert.equal(2, #options[214].rewards)
        assert.equal(0, #options[215].rewards)
    end)

    it("carries itemDBID as the hex string the client gave, and resolves its link", function()
        local options = byID(ns.Vault.Options())
        local rewards = options[208].rewards
        local weapon
        for _, reward in ipairs(rewards) do
            if reward.itemID == 251935 then
                weapon = reward
            end
        end
        assert.is_not_nil(weapon)
        assert.equal("0x4000000E5E0736EE", weapon.itemDBID)
        assert.equal("251935:6652:12841", weapon.key)
        assert.same({ 6652, 12841 }, weapon.bonusIDs)
        assert.equal("2H Weapon", weapon.slot)
        assert.equal("INVTYPE_2HWEAPON", weapon.equipLoc)
        assert.equal(305, weapon.itemLevel)
        assert.equal("Lightgrasp Worldroot", weapon.name)
        assert.equal(4, weapon.quality)
        assert.equal(1, weapon.quantity)
    end)

    it("keys the other gear rewards the same way", function()
        local options = byID(ns.Vault.Options())
        local found = {}
        for _, id in ipairs({ 207, 213, 214 }) do
            for _, reward in ipairs(options[id].rewards) do
                if reward.slot then
                    found[reward.itemID] = reward
                end
            end
        end
        assert.equal("Offhand", found[275547].slot)
        assert.equal(305, found[275547].itemLevel)
        assert.equal("275547:6652:12841", found[275547].key)
        assert.equal("Shoulder", found[251146].slot)
        assert.equal(308, found[251146].itemLevel)
        assert.equal("251146:6652:12699:12842:13440:13662", found[251146].key)
        assert.equal("Neck", found[251234].slot)
        assert.equal(308, found[251234].itemLevel)
        assert.equal("251234:6652:12699:12842:13440:13668", found[251234].key)
    end)

    it("carries the Mythic Keystone that rides along with every gear reward as an item with no slot", function()
        -- Measured: every rewarded row carries { id = 180653, type = 1 } beside
        -- its gear, and the client answers INVTYPE_NON_EQUIP_IGNORE and level 1
        -- for it. ns.Vault keeps the record and says what it is; deciding not to
        -- show it as gear is the panel's job (see the 2026-09-08 findings).
        local options = byID(ns.Vault.Options())
        local keystones = 0
        for _, id in ipairs({ 207, 208, 213, 214, 229 }) do
            for _, reward in ipairs(options[id].rewards) do
                if reward.itemID == 180653 then
                    keystones = keystones + 1
                    assert.is_nil(reward.slot)
                    assert.equal("INVTYPE_NON_EQUIP_IGNORE", reward.equipLoc)
                    assert.equal(1, reward.itemLevel)
                    assert.equal("Mythic Keystone", reward.name)
                    assert.equal("180653", reward.key)
                end
            end
        end
        assert.equal(5, keystones)
    end)

    -- M5-1 (WKE-550): every reward record carries the icon file ID the client
    -- gave, so the Vault tab's item lines have one to draw. It is the fifth
    -- return of GetItemInfoInstant and therefore static data, which is why it
    -- is there even on a record that is still pending.
    it("carries the client's own icon on every reward", function()
        local result = ns.Vault.Options()
        local withIcon = 0
        for _, option in ipairs(result.options) do
            for _, reward in ipairs(option.rewards) do
                assert.is_number(reward.icon)
                withIcon = withIcon + 1
            end
        end
        assert.is_true(withIcon > 0)
    end)

    -- M3-12 must not change what this snapshot says: every item was cached
    -- when it was taken, so nothing is pending and the client is not asked.
    it("has nothing pending and asks the client for nothing", function()
        local result = ns.Vault.Options()
        assert.equal(0, result.pendingRewards)
        assert.equal(0, result.requestedItems)
        assert.equal(0, #world.itemDataRequests)
        assert.equal(0, ns.Vault.PendingCount())
        for _, option in ipairs(result.options) do
            for _, reward in ipairs(option.rewards) do
                assert.is_false(reward.pending)
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-12 (WKE-547): the 2026-09-09 08:59:19 snapshot, taken by `/lootpath
-- refresh` right after a full client restart. Measured in that transcript
-- (docs/ARCHITECTURE.md §9, "Checked 2026-09-09 mid-morning"): four of the
-- five rewards come back with a link whose bracketed name is EMPTY
-- (`|h[]|h`), GetItemInfo and GetDetailedItemLevelInfo answer nothing, and
-- GetItemInfoInstant still names the slot; only the Lightgrasp Worldroot - a
-- copy of which the owner wears - resolved. The itemIDs, bonus IDs and keys
-- are intact. Every figure below was read from that snapshot; the "late
-- answer" is the 2026-09-08 23:26:17 snapshot of the SAME itemDBIDs, which
-- carries every name and level, replayed over the nameless one.
describe("ns.Vault over the fresh-login transcript (M3-12, WKE-547)", function()
    local ns, world
    local FRESH_LOGIN = "spec/fixtures/captures/Lootpath-20260909-085940.lua"
    local NAMELESS = 13 -- 2026-09-09T08:59:19, right after the client restart
    local NAMED = 12 -- 2026-09-08T23:26:17, the same rewards with every name
    local PENDING_IDS = { 251146, 251234, 269862, 275547 }

    before_each(function()
        ns, world = H.load()
        R.vault(world, R.snapshot("vault", NAMELESS, FRESH_LOGIN))
    end)

    after_each(function()
        H.unload()
    end)

    local function rewardsByItemID(result)
        local map = {}
        for _, option in ipairs(result.options) do
            for _, reward in ipairs(option.rewards) do
                map[reward.itemID] = reward
            end
        end
        return map
    end

    local function sortedRequests()
        local out = {}
        for _, id in ipairs(world.itemDataRequests) do
            out[#out + 1] = id
        end
        table.sort(out)
        return out
    end

    -- The client's later answer: the named snapshot's links and item probes
    -- laid over the world, then the load event for each item, the way the
    -- client fires ITEM_DATA_LOAD_RESULT(itemID, true) once it has the data.
    local function clientAnswers(event, ids)
        R.vaultLinks(world, R.snapshot("vault", NAMED, FRESH_LOGIN))
        for _, id in ipairs(ids or PENDING_IDS) do
            world.fireEvent(event or "ITEM_DATA_LOAD_RESULT", id, true)
        end
    end

    local function listenerEvents()
        for _, frame in ipairs(world.frames) do
            if frame.events["ITEM_DATA_LOAD_RESULT"] or frame.events["GET_ITEM_INFO_RECEIVED"] then
                return frame.events
            end
        end
        return nil
    end

    it("reads a nameless link as pending, with the key intact and nothing invented", function()
        local result = ns.Vault.Options()
        assert.is_true(result.ok)
        assert.equal(0, result.secretsSeen)
        assert.equal(4, result.pendingRewards)
        local rewards = rewardsByItemID(result)
        -- The three gear rewards: pending, keyed, slotted, no name, no level.
        local lantern = rewards[275547]
        assert.is_true(lantern.pending)
        assert.equal("275547:6652:12841", lantern.key)
        assert.equal("Offhand", lantern.slot)
        assert.equal("INVTYPE_HOLDABLE", lantern.equipLoc)
        assert.is_nil(lantern.name)
        assert.is_nil(lantern.itemLevel)
        assert.equal("0x4000000E5E0736EB", lantern.itemDBID)
        assert.equal("251146:6652:12699:12842:13440:13662", rewards[251146].key)
        assert.is_true(rewards[251146].pending)
        assert.equal("Shoulder", rewards[251146].slot)
        assert.equal("251234:6652:12699:12842:13440:13668", rewards[251234].key)
        assert.is_true(rewards[251234].pending)
        assert.equal("Neck", rewards[251234].slot)
        -- The Concession token: pending too, and the client's static data
        -- still says it is not gear.
        assert.is_true(rewards[269862].pending)
        assert.is_nil(rewards[269862].slot)
        assert.equal("INVTYPE_NON_EQUIP_IGNORE", rewards[269862].equipLoc)
        assert.equal("269862", rewards[269862].key)
        -- The one that resolved: the owner wears a copy of it.
        local weapon = rewards[251935]
        assert.is_false(weapon.pending)
        assert.equal("Lightgrasp Worldroot", weapon.name)
        assert.equal(305, weapon.itemLevel)
        assert.equal("251935:6652:12841", weapon.key)
    end)

    it("reads the empty brackets the client really sent as no name", function()
        assert.is_nil(ns.Vault.LinkName("|cnIQ1:|Hitem:275547::::::::90:105::108:2:6652:12841::::::|h[]|h|r"))
        assert.equal(
            "Lightgrasp Worldroot",
            ns.Vault.LinkName("|cnIQ4:|Hitem:251935::::::::90:105::55:2:6652:12841::::::|h[Lightgrasp Worldroot]|h|r")
        )
        assert.is_nil(ns.Vault.LinkName(nil))
        -- A record with no link at all is not pending: there is nothing to
        -- wait for (the M3-3 "link never arrives" case keeps its own meaning).
        assert.is_false(ns.Vault.RewardIsPending({ itemDBID = "no-link" }))
    end)

    it("asks the client to load each pending item once, and never the resolved one", function()
        local result = ns.Vault.Options()
        assert.equal(4, result.requestedItems)
        assert.same(PENDING_IDS, sortedRequests())
        assert.equal(4, ns.Vault.PendingCount())
        local events = listenerEvents()
        assert.is_not_nil(events)
        assert.is_true(events["ITEM_DATA_LOAD_RESULT"])
        assert.is_true(events["GET_ITEM_INFO_RECEIVED"])
        -- A second look while the items are still pending re-uses the episode.
        local again = ns.Vault.Options()
        assert.equal(4, again.pendingRewards)
        assert.equal(0, again.requestedItems)
        assert.equal(4, #world.itemDataRequests)
    end)

    it("does not ask when told not to", function()
        local result = ns.Vault.Options({ request = false })
        assert.equal(4, result.pendingRewards)
        assert.equal(0, result.requestedItems)
        assert.equal(0, #world.itemDataRequests)
        assert.equal(0, ns.Vault.PendingCount())
    end)

    it("fills the pending records on the client's load event and redraws the Vault tab once", function()
        local redraws = 0
        ns.UI.RefreshVault = function()
            redraws = redraws + 1
            return true
        end
        local result = ns.Vault.Options()
        local rewards = rewardsByItemID(result)
        clientAnswers("ITEM_DATA_LOAD_RESULT")
        -- The records the panel was handed are filled in place: the second
        -- read is the same code as the first, over the client's later answer.
        assert.is_false(rewards[275547].pending)
        assert.equal("Preyhunter's Lantern", rewards[275547].name)
        assert.equal(305, rewards[275547].itemLevel)
        assert.equal("275547:6652:12841", rewards[275547].key)
        assert.equal("Scavenger's Spaulders", rewards[251146].name)
        assert.equal(308, rewards[251146].itemLevel)
        assert.equal("Graft of the Domanaar", rewards[251234].name)
        assert.equal(308, rewards[251234].itemLevel)
        assert.is_false(rewards[269862].pending)
        assert.equal(0, ns.Vault.PendingCount())
        -- Four events, one redraw: coalesced onto the next frame.
        assert.equal(0, redraws)
        world.runTimers(0)
        assert.equal(1, redraws)
        world.runTimers(ns.Vault.ITEM_DATA_WAIT_SECONDS * ns.Vault.ITEM_DATA_MAX_ATTEMPTS + 1)
        assert.equal(1, redraws)
        -- Nothing left to wait for, so the listener stops listening.
        assert.is_nil(listenerEvents())
    end)

    it("takes GET_ITEM_INFO_RECEIVED as the same answer", function()
        local result = ns.Vault.Options()
        local rewards = rewardsByItemID(result)
        clientAnswers("GET_ITEM_INFO_RECEIVED", { 275547 })
        assert.is_false(rewards[275547].pending)
        assert.equal("Preyhunter's Lantern", rewards[275547].name)
        assert.is_true(rewards[251146].pending)
        assert.equal(3, ns.Vault.PendingCount())
    end)

    it("fills the records on the bounded re-read when no event comes", function()
        local redraws = 0
        ns.UI.RefreshVault = function()
            redraws = redraws + 1
        end
        local result = ns.Vault.Options()
        local rewards = rewardsByItemID(result)
        -- The data arrives, but the client fires nothing.
        R.vaultLinks(world, R.snapshot("vault", NAMED, FRESH_LOGIN))
        assert.is_true(rewards[275547].pending)
        world.runTimers(ns.Vault.ITEM_DATA_WAIT_SECONDS)
        assert.is_false(rewards[275547].pending)
        assert.equal("Preyhunter's Lantern", rewards[275547].name)
        assert.equal(0, ns.Vault.PendingCount())
        assert.equal(1, redraws)
    end)

    it("leaves a record the client never describes pending, in words, and asks again on the next look", function()
        local redraws = 0
        ns.UI.RefreshVault = function()
            redraws = redraws + 1
        end
        local result = ns.Vault.Options()
        local rewards = rewardsByItemID(result)
        world.runTimers(ns.Vault.ITEM_DATA_WAIT_SECONDS * ns.Vault.ITEM_DATA_MAX_ATTEMPTS + 1)
        -- Forgotten by the module, still pending on the record, nothing drawn.
        assert.equal(0, ns.Vault.PendingCount())
        assert.is_true(rewards[275547].pending)
        assert.is_nil(rewards[275547].name)
        assert.is_nil(rewards[275547].itemLevel)
        assert.equal("275547:6652:12841", rewards[275547].key)
        assert.equal(0, redraws)
        assert.equal(4, #world.itemDataRequests)
        -- The next Options() is a new episode: the client is asked again.
        local again = ns.Vault.Options()
        assert.equal(4, again.pendingRewards)
        assert.equal(4, again.requestedItems)
        assert.equal(8, #world.itemDataRequests)
    end)

    it("does not guess at an item whose load the client says failed", function()
        local result = ns.Vault.Options()
        local rewards = rewardsByItemID(result)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", 275547, false)
        assert.is_true(rewards[275547].pending)
        assert.is_nil(rewards[275547].name)
        assert.equal(3, ns.Vault.PendingCount())
    end)

    it("reads nothing in combat, and resolves once combat ends", function()
        local result = ns.Vault.Options()
        local rewards = rewardsByItemID(result)
        world.inCombat = true
        clientAnswers("ITEM_DATA_LOAD_RESULT")
        assert.is_true(rewards[275547].pending)
        assert.equal(4, ns.Vault.PendingCount())
        world.inCombat = false
        clientAnswers("ITEM_DATA_LOAD_RESULT")
        assert.is_false(rewards[275547].pending)
        assert.equal(0, ns.Vault.PendingCount())
    end)

    it("ignores load events for items it is not waiting for", function()
        ns.Vault.Options()
        assert.is_false(ns.Vault.OnItemData("ITEM_DATA_LOAD_RESULT", 180653, true))
        assert.equal(4, ns.Vault.PendingCount())
    end)
end)
