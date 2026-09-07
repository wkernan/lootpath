-- Lootpath/Modules/Vault.lua (M3-3, WKE-524)
-- The Great Vault adapter: this week's options, their progress, and the item
-- link behind each generated reward, normalised into one record the Vault
-- panel renders and the QE verdict is joined to by ns.ItemKey.
--
-- The calls are the SimulationCraft addon's (its core.lua ~line 1294 reads
-- C_WeeklyRewards.HasAvailableRewards / GetActivities / GetItemHyperlink and
-- exports what they say), because that is the path QE Live's vault numbers
-- already come down. Every one of them is named in FUNCTION_NAMES below and
-- called literally; nothing here is discovered by walking C_WeeklyRewards,
-- which also carries ClaimReward.
--
-- What is measured and what is documented, kept apart on purpose:
--   * The activity shape is measured. Four `capture vault` snapshots
--     (transcripts 2026-09-05 and 2026-09-06) show ten activities carrying
--     { type, index, threshold, progress, level, id, activityTierID,
--     raidString, rewards }, with types 6/3/1/5 = World/Raid/Activities/
--     Concession against Enum.WeeklyRewardChestThresholdType as that same
--     client enumerated it in `capture env`.
--   * The REWARD shape is documented, not measured. `rewards` was empty in
--     every activity of every snapshot except the Concession one, which held a
--     currency ({ id = 3513, type = 2, quantity = 1 }) and no itemDBID. So the
--     item path below is written to Blizzard's exported
--     WeeklyRewardActivityRewardInfo ({ type, id, quantity, itemDBID? }) and to
--     Enum.CachedRewardType, and it is the one thing in this file that
--     WKE-523's after-reset capture still has to confirm.
--
-- Every value read from the client passes ns.Safe; a secret is dropped and
-- counted, never stored. Nothing runs in combat. Reads only.

local _, ns = ...

ns.Vault = {}
local Vault = ns.Vault

-- Every client function this file calls, named rather than discovered, for the
-- same reason JournalAdapter.FUNCTION_NAMES is a list of strings: a nil entry
-- in a table of values cannot be told from an absent one.
Vault.FUNCTION_NAMES = {
    "C_WeeklyRewards.HasAvailableRewards",
    "C_WeeklyRewards.CanClaimRewards",
    "C_WeeklyRewards.GetActivities",
    "C_WeeklyRewards.GetItemHyperlink",
    "C_DateAndTime.GetSecondsUntilWeeklyReset",
}

-- Enum.WeeklyRewardChestThresholdType, as the 12.1.0 client enumerated it in
-- the 2026-09-05 env capture. The live Enum wins whenever the client has it;
-- this is the fallback so a headless run and an older client still agree.
Vault.THRESHOLD_TYPE = {
    None = 0,
    Activities = 1,
    RankedPvP = 2,
    Raid = 3,
    AlsoReceive = 4,
    Concession = 5,
    World = 6,
}

-- What each row of the vault is, in the owner's words rather than the enum's.
-- "Activities" is the Mythic+ row; Blizzard's enum name is kept above and the
-- plain-English label lives here.
Vault.TYPE_LABEL = {
    [0] = "Unknown",
    [1] = "Mythic+",
    [2] = "Ranked PvP",
    [3] = "Raid",
    [4] = "Also receive",
    [5] = "Concession",
    [6] = "World",
}

-- Enum.CachedRewardType, same env capture: None 0, Item 1, Currency 2, Quest 3.
Vault.REWARD_TYPE = { None = 0, Item = 1, Currency = 2, Quest = 3 }

local function enumValue(name, fallbackTable, fallbackName)
    local live = _G.Enum and _G.Enum[name]
    local value = live and live[fallbackName]
    if type(value) == "number" then
        return value
    end
    return fallbackTable[fallbackName]
end

function Vault.ThresholdType(name)
    return enumValue("WeeklyRewardChestThresholdType", Vault.THRESHOLD_TYPE, name)
end

function Vault.RewardType(name)
    return enumValue("CachedRewardType", Vault.REWARD_TYPE, name)
end

function Vault.TypeLabel(activityType)
    return Vault.TYPE_LABEL[activityType] or ("Type " .. tostring(activityType))
end

-- Secret-guarded read, the shape Inventory uses: a secret is dropped and counted.
local function guarded(counter, value)
    local safe, secret = ns.Safe(value)
    if secret then
        counter.secretsSeen = counter.secretsSeen + 1
        return nil
    end
    return safe
end

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end
    return result
end

-- One reward entry -> one record, or nil when it is not an item this addon can
-- identify. A currency or a quest reward (Enum.CachedRewardType) is not gear
-- and carries no itemDBID; the Concession row in both committed transcripts is
-- exactly that, so it is skipped rather than shown as an item with no level.
function Vault.Reward(raw, counter)
    counter = counter or { secretsSeen = 0 }
    if type(raw) ~= "table" then
        return nil
    end
    local itemDBID = guarded(counter, raw.itemDBID)
    if itemDBID == nil then
        return nil
    end
    local rewardType = guarded(counter, raw.type)
    if rewardType ~= nil and rewardType ~= Vault.RewardType("Item") then
        return nil
    end
    local link = guarded(counter, call(C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink, itemDBID))
    local record = {
        itemDBID = itemDBID,
        itemID = tonumber(guarded(counter, raw.id)),
        quantity = tonumber(guarded(counter, raw.quantity)),
        link = type(link) == "string" and link or nil,
    }
    -- The link is what carries the bonus IDs, so it is what carries the key the
    -- QE verdict is joined on. An option whose link never arrives is an option
    -- with no identity, which is a fact worth showing rather than a reason to
    -- drop the row.
    if record.link then
        local parsed = ns.ParseItemLink(record.link)
        if parsed then
            record.key = parsed.key
            record.itemID = record.itemID or parsed.itemID
            record.bonusIDs = parsed.bonusIDs
        end
        -- Every return, not just the first: the equip location is the fourth of
        -- GetItemInfoInstant and the quality the third of GetItemInfo, so the
        -- calls are never wrapped in parentheses (which would truncate them).
        local instant, info = {}, {}
        if C_Item then
            record.itemLevel = guarded(counter, (C_Item.GetDetailedItemLevelInfo(record.link)))
            instant = { C_Item.GetItemInfoInstant(record.link) }
            info = { C_Item.GetItemInfo(record.link) }
        end
        record.equipLoc = guarded(counter, instant[4])
        record.slot = ns.Inventory and ns.Inventory.SlotForEquipLoc(record.equipLoc) or nil
        record.name = guarded(counter, info[1])
        record.quality = guarded(counter, info[3])
    end
    return record
end

-- Options() -> { ok = true, options, hasAvailableRewards, canClaimRewards,
--                secondsUntilWeeklyReset, secretsSeen }
--          or { ok = false, reason = "combat" | "no vault API" }
--
-- One record per activity, in the order the client listed them:
--   { type, typeLabel, index, id, threshold, progress, level, activityTierID,
--     unlocked, rewards = { <Vault.Reward records> } }
--
-- Every activity is kept, unlocked or not: "2 of 4 bosses" is the answer to
-- "what can I still earn this week", and dropping the locked rows would hide it.
function Vault.Options(_)
    if InCombatLockdown() then
        return { ok = false, reason = "combat" }
    end
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then
        return { ok = false, reason = "no vault API" }
    end
    local counter = { secretsSeen = 0 }
    local activities = guarded(counter, call(C_WeeklyRewards.GetActivities))
    local options = {}
    if type(activities) == "table" then
        for _, raw in ipairs(activities) do
            local activity = guarded(counter, raw)
            if type(activity) == "table" then
                -- Guard first, coerce second: tonumber() of a secret value is
                -- nil, which would swallow the secret before ns.Safe ever saw
                -- it and leave the count wrong.
                local threshold = tonumber(guarded(counter, activity.threshold)) or 0
                local progress = tonumber(guarded(counter, activity.progress)) or 0
                local rewards = {}
                for _, rawReward in ipairs(guarded(counter, activity.rewards) or {}) do
                    local reward = Vault.Reward(rawReward, counter)
                    if reward then
                        rewards[#rewards + 1] = reward
                    end
                end
                options[#options + 1] = {
                    type = guarded(counter, activity.type),
                    typeLabel = Vault.TypeLabel(guarded(counter, activity.type)),
                    index = tonumber(guarded(counter, activity.index)),
                    id = tonumber(guarded(counter, activity.id)),
                    threshold = threshold,
                    progress = progress,
                    level = tonumber(guarded(counter, activity.level)),
                    activityTierID = tonumber(guarded(counter, activity.activityTierID)),
                    unlocked = threshold > 0 and progress >= threshold,
                    rewards = rewards,
                }
            end
        end
    end
    return {
        ok = true,
        options = options,
        hasAvailableRewards = guarded(counter, call(C_WeeklyRewards.HasAvailableRewards)) == true,
        canClaimRewards = guarded(counter, call(C_WeeklyRewards.CanClaimRewards)) == true,
        secondsUntilWeeklyReset = guarded(counter, call(C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset)),
        secretsSeen = counter.secretsSeen,
    }
end
