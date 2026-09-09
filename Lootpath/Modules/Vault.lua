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
-- The reward shape WAS measured on 2026-09-08 (§9): `itemDBID` is a hex
-- string the client hands back unchanged, and every gear reward rides with a
-- Mythic Keystone. What 2026-09-09 then measured (M3-12, WKE-547) is the
-- SECOND stage the journal already knew about: right after a client restart,
-- GetItemHyperlink answers at once with a link whose bracketed name is EMPTY
-- (`|Hitem:275547:...|h[]|h`), GetItemInfo and GetDetailedItemLevelInfo answer
-- nil, and only GetItemInfoInstant (static data) still says which slot it is.
-- The itemID, the bonus IDs and therefore the key are intact. Such a record is
-- `pending` - "not known yet", never "no name" - and this file asks the client
-- to load the item and reads it again when the client says it has.
--
-- Why C_Item.RequestLoadItemDataByID and the two load events, rather than the
-- ItemMixin (`Item:CreateFromItemID(id):ContinueOnItemLoad(fn)`): read under
-- .luals/, the mixin is that same call - `ItemEventListener:AddCallback` runs
-- `C_Item.RequestLoadItemDataByID(id)` once per id and fires the callback on
-- ITEM_DATA_LOAD_RESULT when `success` is true (Blizzard_ObjectAPI's
-- AsyncCallbackSystem.lua and Item.lua). Calling the exported function
-- directly keeps every client call in FUNCTION_NAMES as a literal name, keeps
-- the bound and the combat check in this file where a test can drive them,
-- and takes no dependency on a FrameXML object whose global (`Item`) the
-- headless harness does not model. Blizzard's own gate for "pending" is kept:
-- `itemInfo.name` missing means RETRIEVING_ITEM_INFO in its journal, and
-- `GetItemInfo` answering no name means pending here.
--
-- Every value read from the client passes ns.Safe; a secret is dropped and
-- counted, never stored. Nothing runs in combat. Reads only - asking the
-- client to load an item's data changes nothing about the character, its
-- items or its money, and the capture never asks (Captures.lua only reads the
-- link as it stands); this module asks, at panel time, out of combat.

local _, ns = ...

ns.Vault = {}
local Vault = ns.Vault

-- Every client function this file calls, named rather than discovered, for the
-- same reason JournalAdapter.FUNCTION_NAMES is a list of strings: a nil entry
-- in a table of values cannot be told from an absent one. The C_Item reads
-- were called from the start and are listed since M3-12 so the list is what it
-- claims to be; RequestLoadItemDataByID is the one call M3-12 added.
Vault.FUNCTION_NAMES = {
    "C_WeeklyRewards.HasAvailableRewards",
    "C_WeeklyRewards.CanClaimRewards",
    "C_WeeklyRewards.GetActivities",
    "C_WeeklyRewards.GetItemHyperlink",
    "C_DateAndTime.GetSecondsUntilWeeklyReset",
    "C_Item.GetDetailedItemLevelInfo",
    "C_Item.GetItemInfoInstant",
    "C_Item.GetItemInfo",
    "C_Item.RequestLoadItemDataByID",
}

-- The second read's bound, the journal's shape (Adapter.ITEM_DATA_WAIT_SECONDS
-- x ITEM_DATA_MAX_ATTEMPTS, 8 x 0.25 s): after asking the client for an item,
-- the pending records are re-read on each of the two load events for that
-- itemID and, failing those, on a timer up to this many times. A record that
-- has not resolved by then stays `pending` and is forgotten by this file, so
-- the next Options() call asks again; it is never filled with a guess.
Vault.ITEM_DATA_WAIT_SECONDS = 0.25
Vault.ITEM_DATA_MAX_ATTEMPTS = 8

-- Both events Blizzard's docs list with `itemID, success` payloads
-- (Event.lua under .luals/): ITEM_DATA_LOAD_RESULT is what the mixin's
-- AsyncCallbackSystem listens for after RequestLoadItemDataByID;
-- GET_ITEM_INFO_RECEIVED is what a plain GetItemInfo miss produces.
Vault.ITEM_DATA_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }

-- What this file is still waiting for: [itemID] = { itemID, attempts,
-- records = { [itemDBID] = record } }. One request per itemID per episode; a
-- second Options() call while the item is still pending re-uses the episode
-- rather than asking the client again.
Vault.pendingItems = {}

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

-- The bracketed name inside an item link, or nil when the link carries none.
-- Measured 2026-09-09 08:59: `|cnIQ1:|Hitem:275547:...|h[]|h|r` - an empty
-- pair of brackets - is what GetItemHyperlink answers before the client has
-- loaded the item. Nothing here ever prints that link.
function Vault.LinkName(link)
    if type(link) ~= "string" then
        return nil
    end
    local name = link:match("|h%[(.-)%]|h")
    if name == nil or name == "" then
        return nil
    end
    return name
end

-- Blizzard's own test for "this item's data has not arrived yet": its journal
-- draws RETRIEVING_ITEM_INFO when `itemInfo.name` is missing. Here the name is
-- GetItemInfo's first return; a link with empty brackets is the same fact seen
-- from the other side, and either one makes the record pending. A record with
-- no link at all is a different case (no identity, no key) and is not pending:
-- there is nothing to wait for.
function Vault.RewardIsPending(record)
    if type(record) ~= "table" or type(record.link) ~= "string" then
        return false
    end
    return type(record.name) ~= "string" or record.name == "" or Vault.LinkName(record.link) == nil
end

-- Reads the item behind a record's link: key, level, slot, name, quality. The
-- first read and the second read run this same code, so what the second read
-- fills is exactly what the first one could not.
local function readItem(record, counter)
    if not record.link then
        record.pending = false
        return record
    end
    -- The link is what carries the bonus IDs, so it is what carries the key the
    -- QE verdict is joined on. The key survives an empty name (measured), which
    -- is why a pending record still joins to the verdict.
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
    local name = guarded(counter, info[1])
    record.name = (type(name) == "string" and name ~= "") and name or nil
    record.quality = guarded(counter, info[3])
    record.pending = Vault.RewardIsPending(record)
    if record.pending then
        -- Not known yet, never "no item level" and never a level of 0.
        record.itemLevel = nil
        record.name = nil
    end
    return record
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
        pending = false,
    }
    -- An option whose link never arrives is an option with no identity, which
    -- is a fact worth showing rather than a reason to drop the row.
    return readItem(record, counter)
end

-- The second read of one record: the link again (the client fills its name
-- once the item is cached) and the item behind it. Returns true when the
-- record is no longer pending.
function Vault.Reread(record, counter)
    counter = counter or { secretsSeen = 0 }
    if type(record) ~= "table" then
        return false
    end
    local link = guarded(counter, call(C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink, record.itemDBID))
    if type(link) == "string" then
        record.link = link
    end
    readItem(record, counter)
    return not record.pending
end

-- ---------------------------------------------------------------------------
-- The request and the second read (M3-12, WKE-547).

local listener
local redrawScheduled = false

local function after(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

local function pendingCount()
    local count = 0
    for _ in pairs(Vault.pendingItems) do
        count = count + 1
    end
    return count
end

function Vault.PendingCount()
    return pendingCount()
end

-- Tells the window that pending records have resolved. Coalesced: several
-- items answering in one frame produce one redraw, and the redraw itself is
-- the window's (UI.RefreshVault redraws the Vault tab only when it is the tab
-- on screen - M3-3's "only the visible tab redraws" rule).
local function notifyResolved()
    if redrawScheduled then
        return
    end
    redrawScheduled = true
    after(0, function()
        redrawScheduled = false
        if ns.UI and ns.UI.RefreshVault then
            ns.UI.RefreshVault()
        end
    end)
end

local function stopWatching()
    if listener then
        for _, event in ipairs(Vault.ITEM_DATA_EVENTS) do
            listener:UnregisterEvent(event)
        end
    end
end

-- Re-reads every pending record for `itemID` (or for every pending item when
-- nil), forgets the ones that resolved, and asks for one redraw if any did.
-- Returns how many records resolved.
function Vault.ResolvePending(itemID)
    local resolved = 0
    for id, entry in pairs(Vault.pendingItems) do
        if itemID == nil or id == itemID then
            local stillPending = false
            for _, record in pairs(entry.records) do
                if Vault.Reread(record) then
                    resolved = resolved + 1
                else
                    stillPending = true
                end
            end
            if not stillPending then
                Vault.pendingItems[id] = nil
            end
        end
    end
    if resolved > 0 then
        notifyResolved()
    end
    if pendingCount() == 0 then
        stopWatching()
    end
    return resolved
end

-- Forgets an item without resolving it: the client said the load failed, or
-- the bound ran out. Its records stay `pending` and say so on screen; the next
-- Options() call asks the client again.
local function forget(itemID)
    Vault.pendingItems[itemID] = nil
    if pendingCount() == 0 then
        stopWatching()
    end
end

function Vault.OnItemData(event, itemID, success)
    if not Vault.pendingItems[itemID] then
        return false
    end
    if InCombatLockdown() then
        -- Nothing runs in combat. The record stays pending; the window's own
        -- PLAYER_REGEN_ENABLED refresh calls Options() again afterwards.
        return false
    end
    if success == false and event == "ITEM_DATA_LOAD_RESULT" then
        -- What Blizzard's AsyncCallbackSystem does with a failed load: drop the
        -- callbacks. The record is not filled and not guessed at.
        forget(itemID)
        return false
    end
    Vault.ResolvePending(itemID)
    return true
end

local function ensureListener()
    if listener then
        return listener
    end
    listener = CreateFrame("Frame")
    listener:SetScript("OnEvent", function(_, event, itemID, success)
        Vault.OnItemData(event, itemID, success)
    end)
    return listener
end

function Vault.WatchItemData()
    local frame = ensureListener()
    for _, event in ipairs(Vault.ITEM_DATA_EVENTS) do
        frame:RegisterEvent(event)
    end
    return frame
end

-- The bound: one timer per pending item, re-armed until the item resolves or
-- ITEM_DATA_MAX_ATTEMPTS have passed. The events above are the fast path;
-- this is what stops a record from waiting forever on a client that never
-- answers.
local function scheduleCheck(entry)
    after(Vault.ITEM_DATA_WAIT_SECONDS, function()
        local live = Vault.pendingItems[entry.itemID]
        if live ~= entry then
            return -- resolved, forgotten, or replaced by a later episode
        end
        entry.attempts = entry.attempts + 1
        if not InCombatLockdown() then
            Vault.ResolvePending(entry.itemID)
        end
        if Vault.pendingItems[entry.itemID] == entry then
            if entry.attempts >= Vault.ITEM_DATA_MAX_ATTEMPTS then
                entry.gaveUp = true
                forget(entry.itemID)
            else
                scheduleCheck(entry)
            end
        end
    end)
end

-- Asks the client to load a pending record's item, once per itemID per
-- episode, and remembers the record so the second read can fill it in place.
-- Returns true when a request was made by this call.
function Vault.RequestItemData(record)
    if type(record) ~= "table" or not record.pending or type(record.itemID) ~= "number" then
        return false
    end
    local entry = Vault.pendingItems[record.itemID]
    local requested = false
    if not entry then
        entry = { itemID = record.itemID, attempts = 0, records = {} }
        Vault.pendingItems[record.itemID] = entry
        Vault.WatchItemData()
        if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
            requested = pcall(C_Item.RequestLoadItemDataByID, record.itemID) == true
        end
        entry.requested = requested
        scheduleCheck(entry)
    end
    entry.records[record.itemDBID or record] = record
    return requested
end

-- Options(opts) -> { ok = true, options, hasAvailableRewards, canClaimRewards,
--                    secondsUntilWeeklyReset, secretsSeen, pendingRewards,
--                    requestedItems }
--             or { ok = false, reason = "combat" | "no vault API" }
--
-- One record per activity, in the order the client listed them:
--   { type, typeLabel, index, id, threshold, progress, level, activityTierID,
--     unlocked, rewards = { <Vault.Reward records> } }
--
-- Every activity is kept, unlocked or not: "2 of 4 bosses" is the answer to
-- "what can I still earn this week", and dropping the locked rows would hide it.
--
-- A reward whose item data has not arrived comes back `pending` and, unless
-- `opts.request == false`, the client is asked to load it (once per itemID per
-- episode). The call stays synchronous: it returns the pending records now and
-- the second read fills them when the client answers.
function Vault.Options(opts)
    if InCombatLockdown() then
        return { ok = false, reason = "combat" }
    end
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then
        return { ok = false, reason = "no vault API" }
    end
    local request = not (type(opts) == "table" and opts.request == false)
    local counter = { secretsSeen = 0 }
    local activities = guarded(counter, call(C_WeeklyRewards.GetActivities))
    local options = {}
    local pendingRewards, requestedItems = 0, 0
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
                        if reward.pending then
                            pendingRewards = pendingRewards + 1
                            if request and Vault.RequestItemData(reward) then
                                requestedItems = requestedItems + 1
                            end
                        end
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
        pendingRewards = pendingRewards,
        requestedItems = requestedItems,
    }
end
