-- Lootpath/Captures.lua
-- Diagnostic captures: `/lootpath capture <name>` dumps raw client returns to
-- SavedVariables so the owner can pull a transcript (tools/sync.ps1 -Pull) and
-- commit it under spec/fixtures/captures/. Nothing here is normalised; the
-- whole point is to learn what the client says rather than confirm a guess.
--
-- Every value passes ns.Probe (pcall, positional results) and then ns.CopyRaw
-- (secret guard, cycle/depth/node guards) inside ns.RunCapture. No capture
-- calls a client function that could act on the character: only reads, and
-- only functions named here, never anything discovered by iterating a namespace.
--
-- `/lootpath capture journal` is registered in Modules/Journal.lua instead,
-- beside the adapter that names every Encounter Journal function it calls: the
-- rule is that a capture calls only what its own file names, and the journal's
-- list belongs with the adapter. It is also the one capture that is not purely
-- a read - selecting a tier, instance, difficulty or loot filter changes the
-- Adventure Guide's view state (nothing about the character), and it puts all
-- three back when it is done.
--
-- `vault` is the SECOND capture that is not purely a read (owner's decision
-- 2026-09-14, M3-16/WKE-557): when the client says rewards are waiting and
-- lists none of them, it calls `C_WeeklyRewards.OnUIInteract()`, waits a
-- bounded few seconds for `WEEKLY_REWARDS_UPDATE`, reads again and calls
-- `CloseInteraction()` - the pair Blizzard's own vault frame calls on every
-- open and close. It marks the vault as looked at and claims nothing; the full
-- reasoning is above the capture itself.
--
-- `upgrade` is the THIRD (owner's decision 2026-09-14 evening, M3-17/WKE-574):
-- the client answers `C_ItemUpgrade.GetItemUpgradeItemInfo()` only for the item
-- currently in the open upgrade vendor's window, so the capture puts each owned
-- upgradeable item there, reads the crest type and cost, and clears the window
-- again. Nothing is bought, nothing is upgraded, nothing moves; the full
-- reasoning is above that capture.
--
-- `itemstats` (E-0a, WKE-675) is purely a read again: item stats, gems,
-- sockets, set ID and uniqueness for worn, bag, vault and CACHED journal links,
-- and the client's rating conversion for values the character does not have.
-- It opens no window and changes no view; the full list is above it.

local _, ns = ...

local function sortedKeys(tbl)
    local keys = {}
    if type(tbl) == "table" then
        for k in pairs(tbl) do
            keys[#keys + 1] = tostring(k)
        end
        table.sort(keys)
    end
    return keys
end

local function globalsWithPrefix(prefix)
    local names = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, #prefix) == prefix then
            names[#names + 1] = k .. "=" .. type(v)
        end
    end
    table.sort(names)
    return names
end

local function enumCopy(name)
    local enum = Enum and Enum[name]
    if type(enum) ~= "table" then
        return { absent = true }
    end
    local out = {}
    for k, v in pairs(enum) do
        out[tostring(k)] = v
    end
    return out
end

-- Everything the client can say about one item link, raw. Shared by the
-- inventory and vault captures so both transcripts carry the same shape.
local function itemProbe(link)
    if not C_Item then
        return { absent = true }
    end
    return {
        detailedLevel = ns.Probe(C_Item.GetDetailedItemLevelInfo, link),
        info = ns.Probe(C_Item.GetItemInfo, link),
        instant = ns.Probe(C_Item.GetItemInfoInstant, link),
    }
end

-- The Mythic+ keystone the character owns, raw (R-0, WKE-561). The Roads brief
-- wants "your key +8" beside a dungeon drop, so the spike reads the key before
-- any surface is built on it. All four calls are in Blizzard's exported docs
-- (Ketho's annotations, read 2026-09-12):
--
--   MythicPlusInfoDocumentation.lua:38 GetOwnedKeystoneLevel() -> keyStoneLevel
--   MythicPlusInfoDocumentation.lua:34 GetOwnedKeystoneChallengeMapID() -> challengeMapID
--   MythicPlusInfoDocumentation.lua:42 GetOwnedKeystoneMapID() -> mapID
--   ChallengeModeInfoDocumentation.lua:81 GetMapUIInfo(mapChallengeModeID)
--       -> name, id, timeLimit, texture?, backgroundTexture, mapID
--
-- Every one of them only answers a question; nothing here starts, alters or
-- slots a keystone. The name is asked for with the CHALLENGE map ID, which is
-- what GetMapUIInfo takes; GetOwnedKeystoneMapID's `mapID` is the other number
-- and is recorded beside it rather than swapped for it. Nothing is displayed
-- yet: this is a transcript read, and R-2 decides what to do with it.
local function keystoneProbe()
    local M = C_MythicPlus
    local level = ns.Probe(M and M.GetOwnedKeystoneLevel)
    local challengeMapID = ns.Probe(M and M.GetOwnedKeystoneChallengeMapID)
    local mapID = ns.Probe(M and M.GetOwnedKeystoneMapID)
    local challengeID = ns.Safe(challengeMapID[1])
    local mapUIInfo = { absent = true }
    if type(challengeID) == "number" and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        mapUIInfo = ns.Probe(C_ChallengeMode.GetMapUIInfo, challengeID)
    end
    return {
        level = level,
        challengeMapID = challengeMapID,
        mapID = mapID,
        mapUIInfo = mapUIInfo,
    }
end

-- Which bag frames are live (R-0, WKE-561). The Roads brief's bag glow has
-- three code paths - Blizzard's own bags, Baganator's plugin API, ElvUI's
-- Pawn-only arrow - and which of them the owner is actually looking at was
-- written down nowhere. The addon list above already carries all 74 of his
-- addons, so this is a named summary rather than a new source: the four names
-- the brief argues about, plus the globals that say which frames exist.
--
-- **`Blizzard_Bags` is not a thing on 12.1**: Blizzard's container frames ship
-- inside `Blizzard_UIPanels_Game` (`.luals/.../Blizzard_UIPanels_Game/Mainline/
-- ContainerFrame.lua`), and the bank is the separate `Blizzard_BankUI` the
-- inventory capture already probes, so those are the two names asked for here.
-- `ContainerFrameCombinedBags` is the one-bag view; a client with it is a
-- client whose bag buttons R-2 would have to walk differently from four
-- separate frames. Types only - nothing is called on any of them.
local BAG_ADDON_NAMES = { "Baganator", "Syndicator", "ElvUI", "Pawn", "Blizzard_UIPanels_Game", "Blizzard_BankUI" }

-- Read through `rawget`, and only for its type: these are other addons' names,
-- so nothing indexes into one and nothing calls one.
local BAG_GLOBAL_NAMES = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1",
    "Baganator",
    "Syndicator",
    "ElvUI",
    "PawnUI",
}

local function bagAddonProbe()
    local loaded = {}
    for _, name in ipairs(BAG_ADDON_NAMES) do
        loaded[name] = ns.Probe(C_AddOns and C_AddOns.IsAddOnLoaded, name)
    end
    local globals = {}
    for _, name in ipairs(BAG_GLOBAL_NAMES) do
        globals[name] = type(rawget(_G, name))
    end
    return {
        probed = BAG_ADDON_NAMES,
        globals = globals,
        loaded = loaded,
    }
end

-- env: build, addons, restrictions, the namespaces later modules touch.
-- M0-2 (WKE-515) reads build[4] against the .toc Interface number.
ns.RegisterCapture("env", "build, player facts, addon list, secret/combat state, API namespaces", function()
    local addons = { count = ns.Probe(C_AddOns and C_AddOns.GetNumAddOns), list = {} }
    local count = addons.count[1]
    if type(count) == "number" then
        for i = 1, count do
            local info = ns.Probe(C_AddOns.GetAddOnInfo, i)
            addons.list[i] = {
                name = info[1],
                title = info[2],
                loadable = info[4],
                reason = info[5],
                loaded = ns.Probe(C_AddOns.IsAddOnLoaded, i)[1],
            }
        end
    end
    local spec = ns.Probe(GetSpecialization)
    return {
        build = ns.Probe(GetBuildInfo),
        locale = ns.Probe(GetLocale),
        realm = ns.Probe(GetRealmName),
        player = ns.Probe(UnitName, "player"),
        class = ns.Probe(UnitClass, "player"),
        -- The SimC profile header the companion builds (WKE-532) needs these
        -- four beside the three above; QE Live's importer reads only `region`
        -- of them, but a profile that omits what the SimulationCraft addon
        -- writes is a profile whose differences we cannot classify. All four
        -- are documented reads with no side effect (Ketho's annotations:
        -- UnitLevel, UnitRace, GetCurrentRegionName, GetCurrentRegion).
        level = ns.Probe(UnitLevel, "player"),
        race = ns.Probe(UnitRace, "player"),
        region = ns.Probe(GetCurrentRegionName),
        regionID = ns.Probe(GetCurrentRegion),
        specIndex = spec,
        specInfo = spec[1] and ns.Probe(GetSpecializationInfo, spec[1]) or { absent = true },
        inCombatLockdown = ns.Probe(InCombatLockdown),
        secrets = {
            issecretvalue = type(issecretvalue),
            issecrettable = type(issecrettable),
            hasSecretRestrictions = ns.Probe(C_Secrets and C_Secrets.HasSecretRestrictions),
        },
        addons = addons,
        constants = {
            INVSLOT_FIRST_EQUIPPED = INVSLOT_FIRST_EQUIPPED,
            INVSLOT_LAST_EQUIPPED = INVSLOT_LAST_EQUIPPED,
            NUM_BAG_SLOTS = NUM_BAG_SLOTS,
            NUM_TOTAL_EQUIPPED_BAG_SLOTS = NUM_TOTAL_EQUIPPED_BAG_SLOTS,
        },
        -- M3-16a (WKE-581): what the login ask did, if it ran. Written by
        -- `ns.Companion.AskVaultAtLogin` and carried here untouched, so the
        -- transcript proves the question was asked one call earlier than the
        -- refresh - `askedAtLogin`, `updateFired`, `waitedMs` - even though no
        -- capture was taken at the time. `{ askedAtLogin = false, reason }`
        -- when the login found nothing to ask about.

        -- M3-16a (WKE-581): what the login ask did, if it ran. Written by
        -- `ns.Companion.AskVaultAtLogin` and carried here untouched, so the
        -- transcript proves the question was asked one call earlier than the
        -- refresh - `askedAtLogin`, `updateFired`, `waitedMs` - even though no
        -- capture was taken at the time. `{ askedAtLogin = false, reason }`
        -- when the login found nothing to ask about.
        vaultLoginAsk = ns.vaultLoginAsk and ns.CopyRaw(ns.vaultLoginAsk) or { absent = true },
        -- R-0 (WKE-561): the key, and which bag frames are live. Both are
        -- recorded raw and shown nowhere.
        keystone = keystoneProbe(),
        bagAddons = bagAddonProbe(),
        enums = {
            BagIndex = enumCopy("BagIndex"),
            BankType = enumCopy("BankType"),
            WeeklyRewardChestThresholdType = enumCopy("WeeklyRewardChestThresholdType"),
            CachedRewardType = enumCopy("CachedRewardType"),
            ItemQuality = enumCopy("ItemQuality"),
        },
        namespaces = {
            C_AddOns = sortedKeys(C_AddOns),
            C_Bank = sortedKeys(C_Bank),
            C_ChallengeMode = sortedKeys(C_ChallengeMode),
            C_Container = sortedKeys(C_Container),
            C_EncounterJournal = sortedKeys(C_EncounterJournal),
            C_Item = sortedKeys(C_Item),
            C_MythicPlus = sortedKeys(C_MythicPlus),
            C_Secrets = sortedKeys(C_Secrets),
            C_WeeklyRewards = sortedKeys(C_WeeklyRewards),
        },
        globals = {
            EJ = globalsWithPrefix("EJ_"),
            equip = {
                EquipItemByName = type(_G.EquipItemByName),
                ["C_Item.EquipItemByName"] = type(C_Item and C_Item.EquipItemByName),
                GetInventoryItemLink = type(_G.GetInventoryItemLink),
                GetInventoryItemID = type(_G.GetInventoryItemID),
            },
        },
    }
end)

-- inventory: every equipped slot and every bag index the client enumerates,
-- raw. M1-2 (WKE-517) runs it with the bank open and closed; M1-1 writes the
-- normaliser against the transcript. Bank predicates are an explicit allow
-- list (they only answer questions); C_Bank also carries functions that move
-- items and money, which is why no capture ever iterates a namespace and calls
-- what it finds.
--
-- **R-7b (WKE-591): an empty read is not a capture.** On a real logout the
-- client answers this scan with nothing. The owner's live SavedVariables, read
-- 2026-09-16 with `tools/companion/lib/lua-savedvariables.js`, carry the flush
-- of his 2026-09-15 22:11:52 logout: `equipped 0`, every one of the twenty bag
-- records present but `numSlots 0` and no items, the whole capture 0.58 ms -
-- against 15.4 ms and `equipped 15` for the refresh 14 hours later, and 14.4
-- and 29.6 ms for the two reload flushes beside it. The `env` read of that same
-- flush still answers `UnitLevel 90` and `UnitClass Druid`, so it is the item
-- and container layer that is gone, not the character. The client is not asked
-- to explain itself; the pair of facts - no equipped links, and a character who
-- has a level and a class - is the tell, and a read that shows it is refused
-- rather than stored, so the newest good read stays the newest.
ns.INVENTORY_EMPTY_REASON = "the client answered the equipment scan with nothing"

local function inventoryIsEmpty(data)
    if type(data) ~= "table" or type(data.equipped) ~= "table" then
        return nil
    end
    if #data.equipped > 0 then
        return nil
    end
    -- The same two reads `env` makes one capture earlier in the same flush,
    -- asked here directly: a character who is naked has no level and no class
    -- either, and this must never refuse a read that is genuinely empty.
    local level = ns.Probe(UnitLevel, "player")[1]
    local class = ns.Probe(UnitClass, "player")[1]
    if type(level) == "number" and level > 0 and type(class) == "string" and class ~= "" then
        return ns.INVENTORY_EMPTY_REASON
    end
    return nil
end

-- **H-1 (WKE-596): a non-healer spec's gear is not stored either.** The read
-- itself is fine - the client answers it - but storing it would make it the
-- newest `inventory` snapshot, and the companion rates the newest: one `/reload`
-- in Guardian and the rating on screen is about the Guardian set, which is the
-- noise the owner saw. So it is refused on the same path R-7b's empty read is
-- refused on: nothing is stored, the newest good read stays newest, and a flush
-- records the refusal and its reason on its own `env` snapshot
-- (`CaptureAtFlush`'s `flushRefusals`).
--
-- `env`, `vault`, `currencies` and `upgrade` are untouched - `env` is what
-- records which spec this was - and a role the client does not name is not
-- gated, so a flush that reads no spec stores gear exactly as it did before.
local function inventoryIsGated()
    return ns.Companion and ns.Companion.GateCaptureReason and ns.Companion.GateCaptureReason() or nil
end

local function refuseInventory(data)
    return inventoryIsGated() or inventoryIsEmpty(data)
end

ns.RegisterCapture(
    "inventory",
    "equipped slots, every bag index, bank state (open the bank first for that half)",
    function()
        local equipped = {}
        local first = INVSLOT_FIRST_EQUIPPED or 1
        local last = INVSLOT_LAST_EQUIPPED or 19
        for slot = first, last do
            local link = ns.Probe(GetInventoryItemLink, "player", slot)
            local itemID = ns.Probe(GetInventoryItemID, "player", slot)
            if link[1] or itemID[1] then
                local record = { invSlot = slot, link = link, itemID = itemID }
                if link[1] then
                    record.item = itemProbe(link[1])
                end
                if ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
                    record.currentLevel = ns.Probe(function()
                        local location = ItemLocation:CreateFromEquipmentSlot(slot)
                        ---@cast location ItemLocation
                        return C_Item.GetCurrentItemLevel(location)
                    end)
                end
                equipped[#equipped + 1] = record
            end
        end

        local bags = {}
        local bagIndexes = {}
        for name, value in pairs((Enum and Enum.BagIndex) or {}) do
            bagIndexes[#bagIndexes + 1] = { name = tostring(name), value = value }
        end
        table.sort(bagIndexes, function(a, b)
            return a.value < b.value
        end)
        for _, bag in ipairs(bagIndexes) do
            local numSlots = ns.Probe(C_Container and C_Container.GetContainerNumSlots, bag.value)
            local record = {
                name = bag.name,
                bagIndex = bag.value,
                numSlots = numSlots,
                freeSlots = ns.Probe(C_Container and C_Container.GetContainerNumFreeSlots, bag.value),
                items = {},
            }
            local n = numSlots[1]
            if type(n) == "number" and n > 0 then
                for slot = 1, n do
                    local info = ns.Probe(C_Container.GetContainerItemInfo, bag.value, slot)
                    local link = ns.Probe(C_Container.GetContainerItemLink, bag.value, slot)
                    local itemID = ns.Probe(C_Container.GetContainerItemID, bag.value, slot)
                    if info[1] or link[1] or itemID[1] then
                        record.items[slot] = {
                            info = info,
                            link = link,
                            itemID = itemID,
                            item = link[1] and itemProbe(link[1]) or nil,
                        }
                    end
                end
            end
            bags[#bags + 1] = record
        end

        local bank = {
            frameShown = BankFrame and ns.Probe(BankFrame.IsShown, BankFrame) or { absent = true },
            blizzardAddonLoaded = ns.Probe(C_AddOns and C_AddOns.IsAddOnLoaded, "Blizzard_BankUI"),
            namespaceKeys = sortedKeys(C_Bank),
            predicates = {},
        }
        local bankTypes = (Enum and Enum.BankType) or {}
        for _, fname in ipairs({ "CanViewBank", "CanUseBank", "CanPurchaseBankTab", "HasMaxBankTabs" }) do
            local fn = C_Bank and C_Bank[fname]
            local byType = {}
            for typeName, typeValue in pairs(bankTypes) do
                byType[tostring(typeName)] = ns.Probe(fn, typeValue)
            end
            bank.predicates[fname] = byType
        end

        return { equipped = equipped, bags = bags, bank = bank }
    end,
    { refuse = refuseInventory }
)

-- vault: the same C_WeeklyRewards calls the SimulationCraft addon makes, raw.
-- M3-2 (WKE-523) runs it before and after opening the Great Vault window so the
-- two transcripts settle when GetActivities populates rewards.
--
-- **M3-16 (WKE-557): the one place a capture asks the server a question.**
-- After the week's first progress the client stops carrying LAST week's
-- unclaimed rewards in `GetActivities()`: measured in the owner's own
-- SavedVariables over sixteen snapshots (2026-09-09/10, ARCHITECTURE.md §9) -
-- `HasAvailableRewards()` stays true, `CanClaimRewards()` stays false, and
-- every activity comes back with `rewards = {}`, so `rewardLinks` is empty, the
-- companion writes "no generated Great Vault reward" and the Vault tab has
-- nothing to rank. Blizzard's own frame is why: `WeeklyRewardsMixin:OnShow`
-- calls `C_WeeklyRewards.OnUIInteract()` and re-reads on
-- `WEEKLY_REWARDS_UPDATE`, and `OnHide` calls `CloseInteraction()`
-- (`.luals/.../Blizzard_WeeklyRewards/Blizzard_WeeklyRewards.lua.annotated.lua`
-- lines 69-91, read 2026-09-14). The owner cannot open the Great Vault window
-- on this client at all, so "open it first" is not available to him.
--
-- **M3-16b (WKE-583): on RESET DAY the interaction is not what generates the
-- rewards, and the owner's window opens after all.** Measured on 2026-09-15,
-- the first day of the new week, in the owner's own SavedVariables: the refresh
-- at 19:09:29Z asked, `WEEKLY_REWARDS_UPDATE` came back in 113.2 ms, and the
-- read after it was the read before it - 10 activities, every `rewards = {}`,
-- 0 reward links, `HasGeneratedRewards()` false. The owner then OPENED the
-- Great Vault window (it opened; on 2026-09-08/09 it would not) and ran
-- `/lootpath capture vault` with it shown: 11 activities, 5 carrying rewards,
-- `HasGeneratedRewards()` and `CanClaimRewards()` true, 9 reward links. The
-- window is what generated them; this capture's one interaction did not, and
-- the addon does not get a second exception to try to (ARCHITECTURE.md §7,
-- 2026-09-15). What the Vault tab says instead is `VaultPanel.OPEN_VAULT_NOTE`.
--
-- **What this capture does have to do is stop settling on the first update.**
-- Blizzard's frame re-reads on EVERY `WEEKLY_REWARDS_UPDATE` while it is shown
-- (`WeeklyRewardsMixin:OnEvent`, same file), and until M3-16b this capture read
-- once, on the first, and closed. So it now reads on every update inside the
-- bound and settles when a read CARRIES rewards or the bound ends, and
-- `interact.updates` records every update's stamp and what it carried -
-- `{ { ms, activities, links }, ... }` - which is how the next transcript will
-- say whether a second or third update ever brings data the first did not.
-- `CloseInteraction` still runs once, at the end, on every path out.
--
-- **This is the second recorded exception to "captures only read"** (the first
-- is the journal's view state, ARCHITECTURE.md §7 2026-09-06), allowed by the
-- owner's decision of 2026-09-14. `OnUIInteract` tells the server the player is
-- interacting with the vault and the server answers with the reward list; it
-- changes nothing about the character, its items or its money, and
-- `CloseInteraction` is called afterwards **always, including on timeout**.
-- `ClaimReward` and `SelectReward` are never called and are not named below.
--
-- **The exception has a second limit since R-7 (WKE-579): it never happens at
-- the flush.** The capture sequence at `PLAYER_LOGOUT` - which fires on a
-- `/reload` as well as on a logout (R-7a, WKE-582) - has no time to wait for
-- the server's answer and nothing left running to receive it. R-7 read the
-- vault there plainly and said so; M3-16b takes the vault out of that sequence
-- altogether (`Companion.FLUSH_CAPTURES`), because a read that cannot ask can
-- only shadow one that did: the owner's 19:09:31Z flush snapshot, two seconds
-- after the refresh's, is the one the companion built its reset-day profile
-- from and it carried nothing.
--
-- Every C_WeeklyRewards function this capture calls, with the exported
-- documentation line it comes from (Ketho's
-- `.luals/.../WeeklyRewardsDocumentation.lua`, read 2026-09-14):
--
--   WeeklyRewardsDocumentation.lua:6   AreRewardsForCurrentRewardPeriod() -> isCurrentPeriod
--   WeeklyRewardsDocumentation.lua:10  CanClaimRewards() -> canClaimRewards
--   WeeklyRewardsDocumentation.lua:17  CloseInteraction()
--   WeeklyRewardsDocumentation.lua:80  HasAvailableRewards() -> hasAvailableRewards
--   WeeklyRewardsDocumentation.lua:84  HasGeneratedRewards() -> hasGeneratedRewards
--   WeeklyRewardsDocumentation.lua:95  OnUIInteract()
--
-- plus `GetActivities`, `GetItemHyperlink` and `GetExampleRewardItemHyperlinks`,
-- which this capture has called since WKE-514. Nothing in `C_WeeklyRewards` is
-- reached for that is not on this list, and nothing is found by walking the
-- namespace.
--
-- **The snapshot keeps both reads.** `activities` / `rewardLinks` /
-- `exampleLinks` at the top level are the BEFORE read - what the client says
-- with no interaction, exactly as every snapshot to date has carried it - and
-- `interact.after` holds the same three lists read again once the update fires;
-- since M3-16b it is the LAST update's read rather than the first's, because
-- every update inside the bound is read. Nothing is copied between them: a
-- reader that wants the best list takes `interact.after` when it is there and
-- the top level otherwise, which is what `VaultPanel.NameFromCaptures` and the
-- companion's `vaultRows` do.
local VAULT_FUNCTION_NAMES = {
    "AreRewardsForCurrentRewardPeriod",
    "CanClaimRewards",
    "CloseInteraction",
    "GetActivities",
    "GetExampleRewardItemHyperlinks",
    "GetItemHyperlink",
    "HasAvailableRewards",
    "HasGeneratedRewards",
    "OnUIInteract",
}

-- How long the capture waits for WEEKLY_REWARDS_UPDATE after OnUIInteract.
-- Since M3-16b it is not a wait for ONE update but the window every update is
-- read inside. The first answers fast - 66.7, 77.1, 113.2 and 130.9 ms in the
-- owner's four asked refreshes of 2026-09-15 (his SavedVariables, read with
-- `tools/companion/lib/lua-savedvariables.js`) - so the bound is not about the
-- first answer at all; it is how long a second or third one is waited for, and
-- it stays the owner's "a few seconds".
ns.VAULT_INTERACT_TIMEOUT_SECONDS = 5

-- The three lists, read together. Called once before the interaction and, when
-- the client answers, once after it; nothing is normalised either time.
local function vaultLists(W)
    local activities = ns.Probe(W and W.GetActivities)
    local rewardLinks = {}
    local exampleLinks = {}
    if type(activities[1]) == "table" then
        for i, activity in ipairs(activities[1]) do
            exampleLinks[i] = ns.Probe(W.GetExampleRewardItemHyperlinks, activity.id)
            for j, reward in ipairs(activity.rewards or {}) do
                if reward.itemDBID ~= nil then
                    local link = ns.Probe(W.GetItemHyperlink, reward.itemDBID)
                    rewardLinks[#rewardLinks + 1] = {
                        activityIndex = i,
                        rewardIndex = j,
                        activityType = activity.type,
                        activityID = activity.id,
                        itemID = reward.id,
                        itemDBID = reward.itemDBID,
                        link = link,
                        item = link[1] and itemProbe(link[1]) or nil,
                    }
                end
            end
        end
    end
    return { activities = activities, rewardLinks = rewardLinks, exampleLinks = exampleLinks }
end

-- **The interaction itself, with nothing around it (M3-16a, WKE-581).**
--
-- Two callers ask the server the same question: the `vault` capture below, and
-- `ns.Companion.AskVaultAtLogin`, which asks once at login so that by the time
-- the player types `/lootpath refresh` the client already carries the rewards
-- and the refresh chain is synchronous again. One function rather than two
-- copies, because the exception the owner allowed on 2026-09-14 is exactly
-- this pair of calls and it must not be able to drift into two versions.
--
-- `record` is filled IN PLACE - `interact`, `updateFired`, `updates`,
-- `timedOut`, `waitedMs`, `close` - so the caller keeps whatever else it wrote
-- there.
--
-- `onUpdate`, when given, runs on EVERY `WEEKLY_REWARDS_UPDATE` inside the
-- bound, while the interaction is still open and the server's answer is fresh
-- (the capture reads the lists again there). It is handed `(record, entry)`,
-- where `entry` is that update's own row in `record.updates` and already
-- carries its `ms`; what it returns decides whether this is the answer -
-- truthy settles, falsy waits for the next update or the bound. With no
-- `onUpdate` at all the FIRST update settles, which is the login ask: it reads
-- nothing, so a second update has nothing to tell it.
--
-- `onDone` runs exactly once on every path out, after `CloseInteraction`.
--
-- `timedOut` means the bound ended rather than `onUpdate` being satisfied, so
-- an interaction that saw three updates and liked none of them says so; a
-- separate `updateFired` says whether the client answered at all.
--
-- CloseInteraction is the other half of OnUIInteract and runs on every path out
-- of here - the update, the timeout, and a client that errors on OnUIInteract
-- itself. Blizzard's frame calls it from OnHide for the same reason: an
-- interaction the server is never told ended is the one thing this could leave
-- behind.
function ns.VaultInteract(record, onUpdate, onDone)
    local W = C_WeeklyRewards
    local startedAt = debugprofilestop and debugprofilestop() or nil
    local listener = CreateFrame("Frame")
    local settled = false

    local function elapsed()
        if startedAt and debugprofilestop then
            return debugprofilestop() - startedAt
        end
        return nil
    end

    local function settle(timedOut)
        if settled then
            return
        end
        settled = true
        listener:UnregisterEvent("WEEKLY_REWARDS_UPDATE")
        listener:SetScript("OnEvent", nil)
        record.timedOut = timedOut
        record.waitedMs = elapsed()
        record.close = ns.Probe(W.CloseInteraction)
        if onDone then
            onDone(record)
        end
    end

    listener:SetScript("OnEvent", function(_, event)
        if event ~= "WEEKLY_REWARDS_UPDATE" or settled then
            return
        end
        record.updateFired = true
        record.updates = record.updates or {}
        local entry = { ms = elapsed() }
        record.updates[#record.updates + 1] = entry
        if not onUpdate then
            return settle(false)
        end
        if onUpdate(record, entry) then
            settle(false)
        end
    end)
    listener:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    record.interact = ns.Probe(W.OnUIInteract)
    if record.interact.error then
        -- The client refused the question; there is nothing to wait for, and
        -- CloseInteraction still runs on the way out.
        settle(true)
        return record
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(ns.VAULT_INTERACT_TIMEOUT_SECONDS, function()
            settle(true)
        end)
    else
        settle(true)
    end
    return record
end

-- True when the vault is in exactly the state the measurement described: the
-- client says rewards are waiting and lists not one of them. Anything else - no
-- rewards at all, or rewards already in the list - is left alone, so the
-- interaction happens only when it is the thing that would change the answer.
local function vaultNeedsInteraction(hasAvailableRewards, lists)
    if ns.Safe(hasAvailableRewards[1]) ~= true then
        return false, "the client says no rewards are waiting"
    end
    if #lists.rewardLinks > 0 then
        return false, "the activities already carry rewards"
    end
    return true, "rewards are waiting and no activity carries one"
end

ns.RegisterCapture(
    "vault",
    "Great Vault activities and reward links (asks the client for the rewards when it is holding them back)",
    function(finish)
        local W = C_WeeklyRewards
        local before = vaultLists(W)
        local hasAvailableRewards = ns.Probe(W and W.HasAvailableRewards)
        local data = {
            namespaceKeys = sortedKeys(W),
            functionNames = VAULT_FUNCTION_NAMES,
            hasAvailableRewards = hasAvailableRewards,
            canClaimRewards = ns.Probe(W and W.CanClaimRewards),
            -- The pair Blizzard's own UpdatePreviousClaim reads to decide
            -- whether to show the "rewards from last week" notice. Recorded
            -- whether or not the interaction happens, because
            -- `HasAvailableRewards and not AreRewardsForCurrentRewardPeriod`
            -- IS the state this capture exists for.
            areRewardsForCurrentRewardPeriod = ns.Probe(W and W.AreRewardsForCurrentRewardPeriod),
            hasGeneratedRewards = ns.Probe(W and W.HasGeneratedRewards),
            frameShown = WeeklyRewardsFrame and ns.Probe(WeeklyRewardsFrame.IsShown, WeeklyRewardsFrame)
                or { absent = true },
            blizzardAddonLoaded = ns.Probe(C_AddOns and C_AddOns.IsAddOnLoaded, "Blizzard_WeeklyRewards"),
            secondsUntilWeeklyReset = ns.Probe(C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset),
            activities = before.activities,
            rewardLinks = before.rewardLinks,
            exampleLinks = before.exampleLinks,
        }

        local needed, reason = vaultNeedsInteraction(hasAvailableRewards, before)
        if needed and type(W and W.OnUIInteract) ~= "function" then
            needed, reason = false, "this client has no C_WeeklyRewards.OnUIInteract"
        end
        if not needed then
            data.interact = { attempted = false, reason = reason }
            return finish(data)
        end

        local record = { attempted = true, reason = reason, updateFired = false, timedOut = false, updates = {} }
        data.interact = record
        ns.VaultInteract(record, function(_, entry)
            -- Every update inside the bound, not only the first (M3-16b): the
            -- lists read again while the interaction is still open, kept beside
            -- the first read rather than replacing it, and each update's row
            -- says what THAT read carried. The answer is a read that carries
            -- rewards; anything else leaves the listener up for the next one.
            local read = vaultLists(W)
            record.after = read
            entry.activities = type(read.activities[1]) == "table" and #read.activities[1] or 0
            entry.links = #read.rewardLinks
            return entry.links > 0
        end, function()
            finish(data)
        end)
    end,
    { async = true }
)

-- currencies: the client's own currency list, headers included, and the full
-- CurrencyInfo behind every non-header entry (M3-9, WKE-544).
--
-- The Vault tab wants to say "you have 1 Catalyst charge" and "you have 42
-- Runed Mistcrests" beside the scenarios that assumed them. **Which currency
-- IDs those are is not guessed**: this capture writes down what the client
-- calls everything, the owner commits the transcript, and
-- Modules/Currencies.lua reads the season's crests and the Catalyst charge from
-- it. Until that has happened the tab says "unknown - run /lootpath refresh"
-- rather than a number.
--
-- **The list half of this capture is the currency TAB, and the tab lists only
-- the rows of expanded headers** (M3-11, WKE-546): the 2026-09-08 23:04
-- transcript recorded `isHeaderExpanded = false` on 8 of its 10 headers, and
-- the eight currencies it listed were simply the ones under the two that were
-- open - which is how "the Catalyst charge is not a currency" got written down
-- from a scroll state. So the capture ALSO probes `GetCurrencyInfo(id)` for
-- every ID in `Currencies.KNOWN_IDS` and stores the answers under `data.byID`,
-- where a currency under a collapsed header still shows up. `isHeaderExpanded`
-- keeps being recorded because it is the field that proved this.
-- `ExpandCurrencyList` would open the headers and is NOT called: captures only
-- read, with the one recorded journal exception.
--
-- The headers are kept because they are how the client groups the list, and the
-- grouping is the evidence for which entries are the season's upgrade
-- currencies. All three calls are in Blizzard's exported docs (Ketho's
-- CurrencyInfoDocumentation.lua): GetCurrencyListSize() -> number,
-- GetCurrencyListInfo(index) -> CurrencyInfo, GetCurrencyInfo(type) ->
-- CurrencyInfo, whose fields include name, description, currencyID, isHeader,
-- quantity, maxQuantity, quantityEarnedThisWeek and iconFileID. Every one of
-- them only answers a question; nothing in C_CurrencyInfo is called that is not
-- named here, and nothing here transfers, spends or converts anything.
ns.RegisterCapture("currencies", "the currency list with its headers, and the full info behind every entry", function()
    local C = C_CurrencyInfo
    local size = ns.Probe(C and C.GetCurrencyListSize)
    local list, info = {}, {}
    local count = size[1]
    if C and type(count) == "number" then
        for index = 1, count do
            local probe = ns.Probe(C.GetCurrencyListInfo, index)
            list[index] = probe
            -- Guard first, read second: a secret CurrencyInfo comes back
            -- from ns.Safe as a marker string, and asking a string for its
            -- currencyID would be a nil index rather than a finding.
            local record = ns.Safe(probe[1])
            if type(record) == "table" then
                local isHeader = ns.Safe(record.isHeader)
                local currencyID = ns.Safe(record.currencyID)
                if isHeader ~= true and type(currencyID) == "number" then
                    info[#info + 1] = {
                        index = index,
                        currencyID = currencyID,
                        info = ns.Probe(C.GetCurrencyInfo, currencyID),
                    }
                end
            end
        end
    end
    -- The by-ID half. `Currencies.KNOWN_IDS` is read at capture time, not at
    -- load time, because Modules/Currencies.lua loads after this file.
    local byID = {}
    local known = ns.Currencies and ns.Currencies.AllKnownIDs and ns.Currencies.AllKnownIDs() or {}
    if C and C.GetCurrencyInfo then
        for _, currencyID in ipairs(known) do
            byID[currencyID] = ns.Probe(C.GetCurrencyInfo, currencyID)
        end
    end
    return {
        namespaceKeys = sortedKeys(C),
        listSize = size,
        list = list,
        info = info,
        probedIDs = known,
        byID = byID,
    }
end)

-- R-2a (WKE-571). The bag mark did not appear on any slot of the owner's real
-- screen, and three different causes produce that same blank: the adapter never
-- installed, the bag addon never draws the widget, or the lookup answers false
-- for every key. `/lootpath glow` says which for ONE item, on screen; this
-- records the same four facts for EVERY bag slot at once, so a transcript can
-- settle whether the key a bag hands over is the key the map was built from.
--
-- Only reads, and only the two container functions named here - the same two
-- `Modules/Inventory.lua` already scans with. Nothing acts on the character,
-- its items or its money.
ns.RegisterCapture(
    "glow",
    "every bag slot: the link, the key it makes, whether the map has it, and what the mark answers",
    function()
        local slots = {}
        local C = C_Container
        if C and C.GetContainerNumSlots and C.GetContainerItemLink then
            for bag = 0, (NUM_BAG_SLOTS or 4) do
                local count = ns.Safe(C.GetContainerNumSlots(bag))
                for slotIndex = 1, (type(count) == "number" and count or 0) do
                    local link = ns.Safe(C.GetContainerItemLink(bag, slotIndex))
                    if type(link) == "string" and link ~= "" then
                        local parsed = ns.ParseItemLink(link)
                        local key = parsed and parsed.key or nil
                        local answer = key and ns.RoadsCache.Lookup(key) or nil
                        local own = answer and answer.own or nil
                        slots[#slots + 1] = {
                            bag = bag,
                            slotIndex = slotIndex,
                            link = link,
                            key = key,
                            inMap = answer ~= nil,
                            glow = key ~= nil and ns.Glow.Wants(key) or false,
                            ownKind = own and own.kind or nil,
                            ownGroup = own and own.group or nil,
                            isForward = own ~= nil and ns.Roads.IsForward(own) or false,
                            phrase = answer and answer.phrase or nil,
                            sentence = answer and answer.sentence or nil,
                        }
                    end
                end
            end
        end
        local map = ns.RoadsCache.Map()
        local adapter = ns.UI.Bags.Chosen()
        return {
            adapter = adapter and adapter.name or nil,
            adapterLabel = adapter and adapter.label or nil,
            statusText = ns.UI.Bags.StatusText(),
            baganatorCorner = ns.UI.Bags.Baganator.Corner(),
            -- How many times Baganator actually called the widget this
            -- session, and what it last said (R-2b, WKE-575). Zero here with a
            -- corner named above is the whole finding: the mark was never
            -- asked for, and nothing about the picture or the map is the
            -- cause.
            baganatorCalls = ns.UI.Bags.Baganator.calls,
            baganatorLastAnswer = ns.UI.Bags.Baganator.lastAnswer,
            baganatorLastLink = ns.UI.Bags.Baganator.lastLink,
            mapReason = map and map.reason or "no map",
            mapKeys = map and map.counts.keys or 0,
            mapGlowing = map and map.counts.glowing or 0,
            -- The map's own keys, so a transcript can be diffed against the
            -- keys the bags made without asking the client twice.
            mapKeyList = (function()
                local keys = {}
                for key in pairs((map and map.byKey) or {}) do
                    keys[#keys + 1] = key
                end
                table.sort(keys)
                return keys
            end)(),
            slots = slots,
        }
    end
)

-- upgrade: what the crest vendor says every upgradeable item the character
-- owns would cost to take one step further (M3-17, WKE-574).
--
-- **This is the THIRD capture that is not purely a read** (the journal's view
-- state, ARCHITECTURE.md §7 2026-09-06; the vault's interaction, M3-16, above),
-- allowed by the owner's decision of 2026-09-14 evening on WKE-568 question 2.
-- Every crest road on every surface says `crest type and cost not readable`
-- because `C_ItemUpgrade.GetItemUpgradeItemInfo()` answers for ONE item only -
-- whichever is in the open upgrade vendor's window - and there is no call that
-- asks about an item without putting it there. So this capture puts each owned
-- upgradeable item in the window, reads, and clears it again.
--
-- What it changes is the vendor window's own display, and nothing else: no
-- item moves, nothing is bought, nothing is upgraded, no currency is spent.
-- `UpgradeItem` is the one call that would spend crests and it is never made,
-- never named below, and `spec/captures_spec.lua` asserts this file's own
-- source does not contain it. `SetItemUpgradeFromCursorItem` is not called
-- either - it would depend on what the owner is holding - and
-- `CloseItemUpgrade` is not called, because closing the window the owner
-- opened is a change this capture has no business making.
--
-- Every C_ItemUpgrade function this capture calls, with the exported
-- documentation line it comes from (Ketho's
-- `.luals/.../ItemUpgradeDocumentation.lua`, read 2026-09-14):
--
--   ItemUpgradeDocumentation.lua:7   CanUpgradeItem(baseItem) -> isValid
--   ItemUpgradeDocumentation.lua:10  ClearItemUpgrade()
--   ItemUpgradeDocumentation.lua:19  GetHighWatermarkForItem(itemInfo)
--                                      -> characterHighWatermark, accountHighWatermark
--   ItemUpgradeDocumentation.lua:34  GetItemHyperlink() -> link
--   ItemUpgradeDocumentation.lua:39  GetItemUpgradeCurrentLevel()
--                                      -> itemLevel, isPvpItemLevel
--   ItemUpgradeDocumentation.lua:50  GetItemUpgradeItemInfo() -> ItemUpgradeItemInfo
--   ItemUpgradeDocumentation.lua:71  SetItemUpgradeFromLocation(itemToSet)
--
-- The walk is Blizzard's own, taken apart: `ItemUpgradeSlotMixin` builds its
-- flyout from `ItemUtil.IteratePlayerInventoryAndEquipment` filtered by
-- `CanUpgradeItem`, and its click handler calls `SetItemUpgradeFromLocation`
-- (`.luals/.../Blizzard_ItemUpgradeUI/Mainline/Blizzard_ItemUpgradeUI.lua.annotated.lua`
-- lines 906-940, read 2026-09-14). The iterator itself is not called here:
-- this file walks the equipped slots and the bags with the same two container
-- reads the inventory capture already makes, so every function the capture
-- reaches is named in this file.
--
-- **What the owner's first transcript settled** (M3-17b, WKE-588;
-- `spec/fixtures/captures/Lootpath-20260915-162015.lua`, taken 2026-09-15
-- 16:20 at a crest vendor, 128 candidates, 20,059 ms, no secret seen). Two
-- things M3-17 guessed at are now measured, and both of them changed here.
--
--   1. **The wait was worth nothing.** `ITEM_UPGRADE_MASTER_SET_ITEM` fired
--      for 10 of the 20 items the vendor took and never arrived for the other
--      10, which sat out the whole 2 s bound - and the info read was complete
--      for all 20. The waiting cost 20,026.6 ms of the capture's 20,059 ms.
--      So the read happens immediately after `SetItemUpgradeFromLocation` and
--      nothing is waited for. The event is still LISTENED for, over the whole
--      walk rather than per item, and `data.eventsSeen` records how many
--      arrived, because "we no longer wait for it" is not the same claim as
--      "it does not happen". What tells a fresh read from a stale one is
--      `record.hyperlink`, which was always the honest check and is still
--      taken for every item.
--
--      The one thing the transcript does NOT settle is whether an immediate
--      read is complete: every event that DID fire arrived 12.7-27.4 ms after
--      its set, so a synchronous read is a frame or two ahead of it, and the
--      ten that read complete without an event read 2 s late. The next
--      transcript answers it, out of `hyperlink` and the info beside it.
--
--   2. **`CanUpgradeItem` is not the gate** - though not for the reason
--      WKE-588 gave. It refused both copies of the Enigmatic Dreamwatcher's
--      Leggings while taking 20 other items. The worn copy was at 321 in the
--      `inventory` snapshot of the same minute, which is the top of the Hero
--      track, so that refusal is right. The copy in his bags at 295 is
--      unexplained by anything in the file, and cannot be explained from it,
--      **because the gate is what stopped the read**. An answer recorded
--      beside a read can be understood later; an answer that decided whether
--      to read cannot. So every candidate now goes into the window and is
--      read, `CanUpgradeItem`'s answer is recorded BESIDE the info, and what a
--      reader gates on is the info's own `itemUpgradeable` and
--      `currUpgrade < maxUpgrade` (`ns.UpgradeCost`).
--
-- The shape of `ItemUpgradeItemInfo` IS documented (`currUpgrade`,
-- `maxUpgrade`, `upgradeLevelInfos[]`, each with `currencyCostsToUpgrade[]`
-- and `itemCostsToUpgrade[]`), and it is stored raw anyway: nothing is
-- normalised here. `ns.UpgradeCost` is the one reader.
local UPGRADE_FUNCTION_NAMES = {
    "CanUpgradeItem",
    "ClearItemUpgrade",
    "GetHighWatermarkForItem",
    "GetItemHyperlink",
    "GetItemUpgradeCurrentLevel",
    "GetItemUpgradeItemInfo",
    "SetItemUpgradeFromLocation",
}

-- The one wait that is left, and it is not per item: after the walk has set,
-- read and cleared every candidate, the capture yields to the client once so
-- that any ITEM_UPGRADE_MASTER_SET_ITEM the walk provoked can be counted
-- before the snapshot is written. Zero seconds is the next frame, which is
-- where the client delivers events; nothing is read in it and nothing depends
-- on what it finds.
ns.UPGRADE_SETTLE_SECONDS = 0

-- Every owned item the vendor might take, in the order Blizzard's own flyout
-- would collect them: the equipped slots first, then the bags. Only the two
-- inventory reads and the two container reads the other captures already make.
-- `CanUpgradeItem` is asked about each one below and its answer is recorded
-- beside the read rather than in front of it (see above): it is a fact about
-- the item, not a decision about whether to look at one.
local function upgradeCandidates()
    local out = {}
    if not (ItemLocation and C_ItemUpgrade) then
        return out
    end
    local first = INVSLOT_FIRST_EQUIPPED or 1
    local last = INVSLOT_LAST_EQUIPPED or 19
    for slot = first, last do
        local link = ns.Safe(GetInventoryItemLink and GetInventoryItemLink("player", slot))
        if type(link) == "string" and link ~= "" then
            out[#out + 1] = {
                source = "equipped",
                invSlot = slot,
                link = link,
                location = ItemLocation:CreateFromEquipmentSlot(slot),
            }
        end
    end
    local C = C_Container
    if C and C.GetContainerNumSlots and C.GetContainerItemLink and ItemLocation.CreateFromBagAndSlot then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local count = ns.Safe(C.GetContainerNumSlots(bag))
            for slotIndex = 1, (type(count) == "number" and count or 0) do
                local link = ns.Safe(C.GetContainerItemLink(bag, slotIndex))
                if type(link) == "string" and link ~= "" then
                    out[#out + 1] = {
                        source = "bag",
                        bag = bag,
                        slotIndex = slotIndex,
                        link = link,
                        location = ItemLocation:CreateFromBagAndSlot(bag, slotIndex),
                    }
                end
            end
        end
    end
    return out
end

-- Everything the vendor window says while ONE item sits in it, raw, written
-- FLAT onto the item's own record. Called once per item, immediately after the
-- item was set and before the window is cleared again (M3-17b).
--
-- **Flat because of `ns.CopyRaw`'s depth guard, measured here rather than
-- assumed** (busted, 2026-09-14): `MAX_COPY_DEPTH` is 10, and the deepest
-- thing worth having in this transcript is the discount on a crest cost -
-- `data`(1) `items`(2) `items[i]`(3) `info`(4) `info[1]`(5)
-- `upgradeLevelInfos`(6) `[1]`(7) `currencyCostsToUpgrade`(8) `[1]`(9)
-- `discountInfo`(10). One `read = { ... }` sublevel between the record and the
-- probes pushed it to 11 and the first run of these tests stored
-- `<max-depth>` in its place. Nothing is hidden by that - the marker is right
-- there in the transcript - but the discount is half of what a crest road
-- would have to say, so the sublevel went away instead of the guard.
local function upgradeReadsInto(record, U, link)
    record.info = ns.Probe(U.GetItemUpgradeItemInfo)
    record.currentLevel = ns.Probe(U.GetItemUpgradeCurrentLevel)
    -- GetHighWatermarkForItem takes an `ItemInfo`, which Blizzard's own alias
    -- says is a number or a string (BlizzardType.lua:22), so it is handed the
    -- link rather than the location.
    record.highWatermark = ns.Probe(U.GetHighWatermarkForItem, link)
    -- Which item the window believes it is showing: the one way a reader can
    -- tell a stale read from a fresh one without trusting the wait.
    record.hyperlink = ns.Probe(U.GetItemHyperlink)
end

ns.RegisterCapture(
    "upgrade",
    "crest type and cost for every owned upgradeable item (open the crest vendor first)",
    function(finish)
        local U = C_ItemUpgrade
        if type(U) ~= "table" or type(U.SetItemUpgradeFromLocation) ~= "function" then
            return finish(nil, "needs C_ItemUpgrade; this client has none")
        end
        local frame = rawget(_G, "ItemUpgradeFrame")
        local shown = frame and ns.Probe(frame.IsShown, frame) or { absent = true }
        if ns.Safe(shown[1]) ~= true then
            return finish(nil, "needs the upgrade window open - open the crest vendor first")
        end

        local candidates = upgradeCandidates()
        local data = {
            functionNames = UPGRADE_FUNCTION_NAMES,
            frameShown = shown,
            blizzardAddonLoaded = ns.Probe(C_AddOns and C_AddOns.IsAddOnLoaded, "Blizzard_ItemUpgradeUI"),
            settleSeconds = ns.UPGRADE_SETTLE_SECONDS,
            -- What was in the window before the capture touched it. The window
            -- is cleared when the capture is done and this is NOT put back:
            -- setting an item the owner did not choose is a change, and the
            -- transcript saying what was there is enough for him to put it
            -- back himself.
            itemInWindowAtStart = ns.Probe(U.GetItemHyperlink),
            candidateCount = #candidates,
            items = {},
        }

        -- One listener for the whole walk, not one per item: nothing waits for
        -- this event any more, and what is worth recording is how many of them
        -- the walk provoked at all.
        local listener = CreateFrame("Frame")
        local eventsSeen = 0
        listener:SetScript("OnEvent", function(_, event)
            if event == "ITEM_UPGRADE_MASTER_SET_ITEM" then
                eventsSeen = eventsSeen + 1
            end
        end)
        listener:RegisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")

        local startedAt = debugprofilestop and debugprofilestop() or nil
        for _, candidate in ipairs(candidates) do
            local parsed = ns.ParseItemLink(candidate.link)
            local record = {
                source = candidate.source,
                invSlot = candidate.invSlot,
                bag = candidate.bag,
                slotIndex = candidate.slotIndex,
                link = candidate.link,
                key = parsed and parsed.key or nil,
                itemID = parsed and parsed.itemID or nil,
                -- Recorded, never obeyed (M3-17b): the owner's transcript has
                -- it saying false about an item with two levels left.
                canUpgrade = ns.Probe(U.CanUpgradeItem, candidate.location),
            }
            data.items[#data.items + 1] = record
            record.set = ns.Probe(U.SetItemUpgradeFromLocation, candidate.location)
            if not record.set.error then
                -- Immediately. The 2 s bound M3-17 waited per item bought
                -- nothing the transcript can find, and `hyperlink` beside the
                -- read is what says which item the window was answering about.
                upgradeReadsInto(record, U, candidate.link)
            end
            -- The window is left empty after every item, on the error path too.
            record.cleared = ns.Probe(U.ClearItemUpgrade)
            -- How many of the events the walk has provoked had been delivered
            -- by the time this item was read. The client delivers between
            -- frames and this walk never yields, so this is expected to be
            -- zero for every item; it is recorded rather than assumed.
            record.eventsSeenAtRead = eventsSeen
        end
        data.walkMs = startedAt and debugprofilestop and (debugprofilestop() - startedAt) or nil
        data.clearedAtEnd = ns.Probe(U.ClearItemUpgrade)

        local function stop()
            listener:UnregisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
            listener:SetScript("OnEvent", nil)
            data.eventsSeen = eventsSeen
            finish(data)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(ns.UPGRADE_SETTLE_SECONDS, stop)
        else
            stop()
        end
    end,
    { async = true }
)

-- itemstats (E-0a, WKE-675): what the client answers about an item's stats,
-- gems, sockets, set ID and uniqueness, and what its rating conversion answers
-- for a value the character does not have. The transcript every own-engine
-- piece is built against (ARCHITECTURE.md §7, 2026-09-30 late night, point 5;
-- `docs/OWN-ENGINE.md` §3). It computes nothing: every number in the snapshot is
-- one the client said, and the one comparison it makes - whether a link's stats
-- equal the same link's stats with the enchant and gems blanked - is a yes or
-- no about two client answers, not a value.
--
-- **Purely a read.** It opens nothing, selects nothing and puts nothing in any
-- window: the journal half reads the walk `capture journal` already CACHED in
-- `db.global.journalCache` and never touches the Adventure Guide (an empty cache
-- refuses the capture with `ns.ITEMSTATS_NO_JOURNAL`); the vault half reads
-- `ns.Vault.Options({ request = false })`; the upgrade vendor is not involved.
-- Refused in combat by `ns.RunCapture`, and refused again if combat started
-- while it waited for item data, so nothing is read in combat.
--
-- What it walks: every worn item; every bag item with a slot in QE Live's
-- vocabulary (`ns.ItemData.Instant(link).slot`); every vault option that
-- carries a link; and up to `ns.ITEMSTATS_JOURNAL_MAX` journal rows, chosen by
-- `ns.ItemStatsJournalSample` (trinkets first, then round-robin across
-- instances, so the sample spans every instance the cache holds before it takes
-- a second row from any). Items whose data is not cached are asked for through
-- `ns.ItemData.Watch` and waited on for at most `ns.ITEMSTATS_WAIT_SECONDS` in
-- all; a row still uncached is read anyway and says so (`cachedAtRead`).
--
-- Every client function this capture calls, with the exported documentation
-- line it comes from (Ketho's annotations under `.luals/.../Blizzard_API
-- DocumentationGenerated/`, read 2026-09-30). The shapes are recorded raw: the
-- annotations give `GetItemStats` only as `LuaValueVariant statTable`, so the
-- transcript is what says what the table holds.
--
--   ItemDocumentation.lua:126        C_Item.GetDetailedItemLevelInfo(itemInfo)
--   ItemDocumentation.lua:187        C_Item.GetItemGem(hyperlink, index) -> gemName, gemLink
--   ItemDocumentation.lua:193        C_Item.GetItemGemID(itemInfo, index) -> gemID
--   ItemDocumentation.lua:240        C_Item.GetItemInfo(itemInfo) (setID is return 16)
--   ItemDocumentation.lua:321        C_Item.GetItemNumSockets(itemInfo) -> socketCount
--   ItemDocumentation.lua:366        C_Item.GetItemStats(itemLink) -> statTable
--   ItemDocumentation.lua:379        C_Item.GetItemUniqueness(itemInfo) -> limitCategory, limitMax
--   ItemDocumentation.lua:387        C_Item.GetItemUniquenessByID(itemInfo)
--                                      -> isUnique, limitCategoryName?, limitCategoryCount?, limitCategoryID?
--   ItemDocumentation.lua:545        C_Item.IsItemDataCachedByID(itemInfo) -> isCached
--   PlayerScriptDocumentation.lua:134 GetCombatRating(ratingIndex)
--   PlayerScriptDocumentation.lua:139 GetCombatRatingBonus(ratingIndex)
--   PlayerScriptDocumentation.lua:145 GetCombatRatingBonusForCombatRatingValue(ratingIndex, value)
--   PlayerScriptDocumentation.lua:219 GetMasteryEffect()
--   PlayerScriptDocumentation.lua:385 GetSpellBonusHealing()
--   UnitDocumentation.lua:1130       UnitStat(unit, index)
--   SecretPredicateAPIDocumentation.lua:44  C_Secrets.HasSecretRestrictions()
--   SecretPredicateAPIDocumentation.lua:183 C_Secrets.ShouldUnitStatsBeSecret()
--   CombatLogDocumentation.lua:31    C_CombatLog.IsCombatLogRestricted()
--   TooltipInfoDocumentation.lua:121 C_TooltipInfo.GetHyperlink(hyperlink, ...)
--
-- plus the inventory read and the two container reads the other captures
-- already make. The addon's own readers it goes through name their client
-- calls in their own files: `ns.ItemData.Instant` / `SpecFit` / `Watch`
-- (ItemData.FUNCTION_NAMES), `ns.Vault.Options` (Vault.FUNCTION_NAMES) and
-- `ns.Companion.CurrentSpecID`. Nothing is found by walking a namespace.
local ITEMSTATS_FUNCTION_NAMES = {
    "C_CombatLog.IsCombatLogRestricted",
    "C_Container.GetContainerItemLink",
    "C_Container.GetContainerNumSlots",
    "C_Item.GetDetailedItemLevelInfo",
    "C_Item.GetItemGem",
    "C_Item.GetItemGemID",
    "C_Item.GetItemInfo",
    "C_Item.GetItemNumSockets",
    "C_Item.GetItemStats",
    "C_Item.GetItemUniqueness",
    "C_Item.GetItemUniquenessByID",
    "C_Item.IsItemDataCachedByID",
    "C_Secrets.HasSecretRestrictions",
    "C_Secrets.ShouldUnitStatsBeSecret",
    "C_TooltipInfo.GetHyperlink",
    "GetCombatRating",
    "GetCombatRatingBonus",
    "GetCombatRatingBonusForCombatRatingValue",
    "GetInventoryItemLink",
    "GetMasteryEffect",
    "GetSpellBonusHealing",
    "UnitStat",
}
ns.ITEMSTATS_FUNCTION_NAMES = ITEMSTATS_FUNCTION_NAMES

-- The addon readers it calls, each of which names its own client calls.
local ITEMSTATS_MODULE_READS = {
    "ns.Companion.CurrentSpecID",
    "ns.ItemData.Instant",
    "ns.ItemData.SpecFit",
    "ns.ItemData.Watch",
    "ns.Vault.Options",
}

-- The bounds. 40 journal rows and 6 trinket tooltips are the issue's numbers;
-- the wait is "a few seconds in all", and ItemData's own per-item bound (8 x
-- 0.25 s) sits inside it.
ns.ITEMSTATS_JOURNAL_MAX = 40
ns.ITEMSTATS_TOOLTIP_MAX = 6
ns.ITEMSTATS_WAIT_SECONDS = 3

-- Rating values the conversion is asked about beside the character's own.
-- 1320 and 2640 are the pair that settle diminishing returns for haste: at 44
-- rating per percent (`docs/OWN-ENGINE.md` §3, graded (ii)) an undiminished
-- conversion answers 30 and 60, and one with the published penalty answers
-- about 30 and about 56. The transcript says which; nothing here assumes it.
ns.ITEMSTATS_RATING_VALUES = { 660, 1320, 1760, 2200, 2640, 3080 }

-- The five secondary ratings, by Blizzard's own constant names
-- (PaperDollFrame.lua.annotated.lua:14-32 under .luals/). The live constant is
-- read when the client defines it, and the annotated number stands in when it
-- does not; `fromGlobal` says which happened.
local ITEMSTATS_RATINGS = {
    { key = "haste", constant = "CR_HASTE_SPELL", index = 20 },
    { key = "crit", constant = "CR_CRIT_SPELL", index = 11 },
    { key = "mastery", constant = "CR_MASTERY", index = 26 },
    { key = "versatility", constant = "CR_VERSATILITY_DAMAGE_DONE", index = 29 },
    { key = "leech", constant = "CR_LIFESTEAL", index = 17 },
}

-- Intellect, as `UnitStat` indexes it (strength 1, agility 2, stamina 3,
-- intellect 4).
local ITEMSTATS_INTELLECT_INDEX = 4

ns.ITEMSTATS_NO_JOURNAL = "needs a cached journal walk - run /lootpath capture journal first"

-- The same link with the enchant and all four gem fields blanked
-- (`item:<id>:::::`, the item string's fields 2-6 by ns.ParseItemLink's count):
-- what `GetItemStats` answers for it, beside what it answers for the link as
-- worn, says whether gems and enchant are inside the stat table. nil for a
-- string that is not an item link.
function ns.ItemStatsStrippedLink(link)
    if type(link) ~= "string" then
        return nil
    end
    local stripped, count = link:gsub("item:(%d+):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*", "item:%1:::::", 1)
    if count == 0 then
        return nil
    end
    return stripped
end

-- Two stat tables, copied through ns.CopyRaw, compared key by key. true or
-- false when both are tables, nil when either is not (absent, secret or an
-- error), because "could not compare" is not "different".
local function sameStats(a, b)
    local left, right = ns.CopyRaw(a), ns.CopyRaw(b)
    if type(left) ~= "table" or type(right) ~= "table" then
        return nil
    end
    for k, v in pairs(left) do
        if right[k] ~= v then
            return false
        end
    end
    for k in pairs(right) do
        if left[k] == nil then
            return false
        end
    end
    return true
end

local function num(v)
    return tonumber(v) or 0
end

local function journalRowBefore(a, b)
    if num(a.instanceID) ~= num(b.instanceID) then
        return num(a.instanceID) < num(b.instanceID)
    end
    if num(a.encounterID) ~= num(b.encounterID) then
        return num(a.encounterID) < num(b.encounterID)
    end
    if num(a.itemID) ~= num(b.itemID) then
        return num(a.itemID) < num(b.itemID)
    end
    if num(a.difficultyID) ~= num(b.difficultyID) then
        return num(a.difficultyID) < num(b.difficultyID)
    end
    return a.link < b.link
end

-- Every journal row with a link, out of every cache entry `capture journal`
-- left behind, once per link, in a fixed order.
local function journalRowsWithLink(cache)
    local rows, seen, entries = {}, {}, {}
    if type(cache) ~= "table" then
        return rows, entries
    end
    local keys = {}
    for key in pairs(cache) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local entry = cache[key]
        if type(entry) == "table" and type(entry.sources) == "table" then
            entries[#entries + 1] = { key = key, build = entry.build, walkAt = entry.walkAt }
            for itemID, list in pairs(entry.sources) do
                for _, row in ipairs(type(list) == "table" and list or {}) do
                    local link = type(row) == "table" and row.link or nil
                    if type(link) == "string" and link ~= "" and not seen[link] then
                        seen[link] = true
                        rows[#rows + 1] = {
                            link = link,
                            itemID = tonumber(itemID),
                            instanceID = row.instanceID,
                            instanceName = row.instanceName,
                            encounterID = row.encounterID,
                            difficultyID = row.difficultyID,
                            itemLevel = row.itemLevel,
                            slot = row.slot,
                            isRaid = row.isRaid,
                            -- The keystone level the walk previewed (the
                            -- entry's own record of it; no getter exists).
                            -- Read by `capture linklevel` (E-0g) only.
                            previewMythicPlusLevel = type(entry.summary) == "table"
                                    and tonumber(entry.summary.previewMythicPlusLevel)
                                or nil,
                        }
                    end
                end
            end
        end
    end
    table.sort(rows, journalRowBefore)
    return rows, entries
end

-- Takes rows that `want` accepts, one instance at a time in turn, until
-- `taken` holds `limit` rows or nothing acceptable is left.
local function takeRoundRobin(rows, picked, taken, want, limit)
    local queues, order = {}, {}
    for _, row in ipairs(rows) do
        if not picked[row] and want(row) then
            local id = num(row.instanceID)
            if not queues[id] then
                queues[id] = {}
                order[#order + 1] = id
            end
            local queue = queues[id]
            queue[#queue + 1] = row
        end
    end
    local progressed = true
    while #taken < limit and progressed do
        progressed = false
        for _, id in ipairs(order) do
            local queue = queues[id]
            if #taken < limit and #queue > 0 then
                local row = table.remove(queue, 1)
                picked[row] = true
                taken[#taken + 1] = row
                progressed = true
            end
        end
    end
end

-- The journal sample: trinkets first, round-robin across instances, up to the
-- tooltip bound; then every other row, round-robin across instances, up to
-- `max`. So the sample spans every instance the cache holds before it takes a
-- second row from any, and carries trinkets and armour both whenever the cache
-- does. Returns the rows and a summary of what was there to choose from.
function ns.ItemStatsJournalSample(cache, max)
    max = max or ns.ITEMSTATS_JOURNAL_MAX
    local rows, entries = journalRowsWithLink(cache)
    local taken, picked = {}, {}
    takeRoundRobin(rows, picked, taken, function(row)
        return row.slot == "Trinket"
    end, math.min(ns.ITEMSTATS_TOOLTIP_MAX, max))
    takeRoundRobin(rows, picked, taken, function()
        return true
    end, max)

    local instances, bySlot, instanceCount = {}, {}, 0
    for _, row in ipairs(taken) do
        local id = num(row.instanceID)
        if not instances[id] then
            instances[id] = true
            instanceCount = instanceCount + 1
        end
        local slot = row.slot or "unknown"
        bySlot[slot] = (bySlot[slot] or 0) + 1
    end
    return taken,
        {
            cacheEntries = entries,
            rowsWithLink = #rows,
            taken = #taken,
            max = max,
            instances = instanceCount,
            bySlot = bySlot,
        }
end

-- The worn and bag halves: every worn link, and every bag link the client
-- gives a slot in QE Live's vocabulary.
local function ownedTargets(targets, specID)
    local first = INVSLOT_FIRST_EQUIPPED or 1
    local last = INVSLOT_LAST_EQUIPPED or 19
    for slot = first, last do
        local link = ns.Safe(GetInventoryItemLink and GetInventoryItemLink("player", slot))
        if type(link) == "string" and link ~= "" then
            targets[#targets + 1] = { source = "worn", invSlot = slot, link = link }
        end
    end
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemLink) then
        return
    end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local count = ns.Safe(C.GetContainerNumSlots(bag))
        for slotIndex = 1, (type(count) == "number" and count or 0) do
            local link = ns.Safe(C.GetContainerItemLink(bag, slotIndex))
            local instant = type(link) == "string" and link ~= "" and ns.ItemData.Instant(link) or nil
            if instant and instant.slot then
                targets[#targets + 1] = {
                    source = "bag",
                    bag = bag,
                    slotIndex = slotIndex,
                    link = link,
                    slot = instant.slot,
                    -- Recorded, never obeyed: whether the client says this
                    -- item is for the current spec (nil = no answer).
                    specFit = ns.ItemData.SpecFit(link, specID),
                }
            end
        end
    end
end

-- The vault half: every option's reward link, as `ns.Vault.Options` reads it.
-- Returns why there is none when the reader refused.
local function vaultTargets(targets)
    local vault = ns.Vault and ns.Vault.Options and ns.Vault.Options({ request = false }) or nil
    if type(vault) ~= "table" or not vault.ok then
        return type(vault) == "table" and vault.reason or "no vault reader"
    end
    for _, option in ipairs(vault.options or {}) do
        for _, reward in ipairs(option.rewards or {}) do
            if type(reward.link) == "string" and reward.link ~= "" then
                targets[#targets + 1] = {
                    source = "vault",
                    activityType = option.type,
                    activityIndex = option.index,
                    activityID = option.id,
                    link = reward.link,
                    slot = reward.slot,
                }
            end
        end
    end
    return nil
end

-- Every link the capture reads, in the order the snapshot lists them: worn,
-- bags, vault, journal. Each target carries where it came from; the reads are
-- added by `itemStatsRead` once the wait is over.
local function itemStatsTargets(journalRows, specID)
    local targets = {}
    ownedTargets(targets, specID)
    local vaultNote = vaultTargets(targets)
    for _, row in ipairs(journalRows) do
        targets[#targets + 1] = {
            source = "journal",
            link = row.link,
            slot = row.slot,
            instanceID = row.instanceID,
            instanceName = row.instanceName,
            encounterID = row.encounterID,
            difficultyID = row.difficultyID,
            journalItemLevel = row.itemLevel,
            isRaid = row.isRaid,
            specFit = ns.ItemData.SpecFit(row.link, specID),
        }
    end
    for _, target in ipairs(targets) do
        local parsed = ns.ParseItemLink(target.link)
        target.itemID = parsed and parsed.itemID or nil
        -- The enchant and gems the link itself names: a parse of the string
        -- already in hand, no call.
        target.linkFinish = ns.ItemData.LinkFinish(target.link)
    end
    return targets, vaultNote
end

-- Each socket's gem, its ID, and the gem link's own stats.
local function gemReads(I, link, sockets)
    local gems = {}
    for index = 1, (type(sockets) == "number" and math.min(sockets, 4) or 0) do
        local gem = ns.Probe(I.GetItemGem, link, index)
        local record = { index = index, gem = gem, gemID = ns.Probe(I.GetItemGemID, link, index) }
        local gemLink = ns.Safe(gem[2])
        if type(gemLink) == "string" and gemLink ~= "" then
            record.gemStats = ns.Probe(I.GetItemStats, gemLink)
        end
        gems[index] = record
    end
    return gems
end

-- Everything the client says about one link, written onto its own record.
-- Raw probes throughout: ns.CopyRaw at the store is what masks a secret and
-- sets the snapshot's `sawSecret`, as for every other capture.
local function itemStatsRead(record)
    local I = C_Item or {}
    local link = record.link
    record.cachedAtRead = record.itemID and ns.Probe(I.IsItemDataCachedByID, record.itemID) or { absent = true }
    record.stats = ns.Probe(I.GetItemStats, link)
    record.strippedLink = ns.ItemStatsStrippedLink(link)
    if record.strippedLink then
        record.strippedStats = ns.Probe(I.GetItemStats, record.strippedLink)
        -- Equal tables mean the stat table leaves gems and enchant out.
        record.strippedEqual = sameStats(record.stats[1], record.strippedStats[1])
    end
    record.numSockets = ns.Probe(I.GetItemNumSockets, link)
    record.gems = gemReads(I, link, ns.Safe(record.numSockets[1]))
    record.detailedLevel = ns.Probe(I.GetDetailedItemLevelInfo, link)
    local info = ns.Probe(I.GetItemInfo, link)
    -- Four of GetItemInfo's returns, by position (12.1.0's 18-return order,
    -- transcript 2026-09-05): itemEquipLoc 9, classID 12, subclassID 13, setID 16.
    record.info = {
        n = info.n,
        error = info.error,
        absent = info.absent,
        itemEquipLoc = info[9],
        classID = info[12],
        subclassID = info[13],
        setID = info[16],
    }
    record.uniqueness = ns.Probe(I.GetItemUniqueness, link)
    record.uniquenessByID = record.itemID and ns.Probe(I.GetItemUniquenessByID, record.itemID) or { absent = true }
end

-- The rating probe: each secondary rating as the character has it, what the
-- client converts it to, and what it converts the six fixed values to.
local function itemStatsRatings()
    local out = {}
    for _, rating in ipairs(ITEMSTATS_RATINGS) do
        local live = rawget(_G, rating.constant)
        local index = type(live) == "number" and live or rating.index
        local current = ns.Probe(GetCombatRating, index)
        local record = {
            constant = rating.constant,
            index = index,
            fromGlobal = type(live) == "number",
            rating = current,
            bonus = ns.Probe(GetCombatRatingBonus, index),
            at = {},
        }
        local value = ns.Safe(current[1])
        if type(value) == "number" then
            record.bonusForCurrent = ns.Probe(GetCombatRatingBonusForCombatRatingValue, index, value)
        else
            record.bonusForCurrent = { skipped = "the current rating was not a number" }
        end
        for i, v in ipairs(ns.ITEMSTATS_RATING_VALUES) do
            record.at[i] = { value = v, bonus = ns.Probe(GetCombatRatingBonusForCombatRatingValue, index, v) }
        end
        out[rating.key] = record
    end
    return {
        ratings = out,
        masteryEffect = ns.Probe(GetMasteryEffect),
        spellBonusHealing = ns.Probe(GetSpellBonusHealing),
        intellect = ns.Probe(UnitStat, "player", ITEMSTATS_INTELLECT_INDEX),
        hasSecretRestrictions = ns.Probe(C_Secrets and C_Secrets.HasSecretRestrictions),
        shouldUnitStatsBeSecret = ns.Probe(C_Secrets and C_Secrets.ShouldUnitStatsBeSecret),
        combatLogRestricted = ns.Probe(C_CombatLog and C_CombatLog.IsCombatLogRestricted),
    }
end

-- One tooltip's lines, `type` and `leftText` only. A secret at any level is
-- stored as itself, so ns.CopyRaw masks it and the snapshot's `sawSecret` says
-- so; nothing is indexed through one.
local function tooltipLines(record, probe)
    local data = ns.Safe(probe[1])
    if type(data) ~= "table" then
        record.data = probe
        return
    end
    local lines = ns.Safe(data.lines)
    if type(lines) ~= "table" then
        record.lines = data.lines
        return
    end
    record.lines = {}
    for i, line in ipairs(lines) do
        if type(ns.Safe(line)) == "table" then
            record.lines[i] = { type = line.type, leftText = line.leftText }
        else
            record.lines[i] = line
        end
    end
end

-- The trinket tooltip sample, out of the journal sample.
local function itemStatsTooltips(journalRows)
    local out = {}
    for _, row in ipairs(journalRows) do
        if #out >= ns.ITEMSTATS_TOOLTIP_MAX then
            break
        end
        if row.slot == "Trinket" then
            local record = { link = row.link, itemLevel = row.itemLevel, difficultyID = row.difficultyID }
            tooltipLines(record, ns.Probe(C_TooltipInfo and C_TooltipInfo.GetHyperlink, row.link))
            out[#out + 1] = record
        end
    end
    return out
end

ns.RegisterCapture(
    "itemstats",
    "item stats, gems, sockets, set and uniqueness on worn, bag, vault and journal items, and the rating conversion",
    function(finish)
        local cache = ns.db and ns.db.global and ns.db.global.journalCache or nil
        local journalRows, journalSummary = ns.ItemStatsJournalSample(cache, ns.ITEMSTATS_JOURNAL_MAX)
        if journalSummary.rowsWithLink == 0 then
            return finish(nil, ns.ITEMSTATS_NO_JOURNAL)
        end
        local specID = ns.Companion and ns.Companion.CurrentSpecID and ns.Companion.CurrentSpecID() or nil
        local targets, vaultNote = itemStatsTargets(journalRows, specID)
        local data = {
            functionNames = ITEMSTATS_FUNCTION_NAMES,
            moduleReads = ITEMSTATS_MODULE_READS,
            specID = specID,
            journal = journalSummary,
            vaultNote = vaultNote,
            waitSeconds = ns.ITEMSTATS_WAIT_SECONDS,
            items = targets,
        }

        -- Ask for what is not cached, once per item ID, and wait for at most
        -- the bound. Every target records what the client said before the wait.
        local waiting, handles, pending, done = {}, {}, 0, false
        local function readAll(timedOut)
            if done then
                return
            end
            done = true
            for _, handle in ipairs(handles) do
                ns.ItemData.Cancel(handle)
            end
            if InCombatLockdown() then
                return finish(nil, "stopped: combat started while it waited for item data; nothing stored")
            end
            data.waitTimedOut = timedOut
            data.stillWaiting = pending
            for _, target in ipairs(targets) do
                local state = target.itemID and waiting[target.itemID] or nil
                if state then
                    target.waited = true
                    target.gaveUp = not state.resolved
                end
                itemStatsRead(target)
            end
            data.rating = itemStatsRatings()
            data.tooltips = itemStatsTooltips(journalRows)
            finish(data)
        end
        local function settleOne()
            pending = pending - 1
            if pending == 0 then
                readAll(false)
            end
        end

        for _, target in ipairs(targets) do
            local id = target.itemID
            target.cachedBefore = id and ns.Probe(C_Item and C_Item.IsItemDataCachedByID, id) or { absent = true }
            if id and ns.Safe(target.cachedBefore[1]) ~= true and not waiting[id] then
                local state = {}
                waiting[id] = state
                pending = pending + 1
                handles[#handles + 1] = ns.ItemData.Watch(id, function(itemID)
                    local cached = ns.Safe(ns.Probe(C_Item and C_Item.IsItemDataCachedByID, itemID)[1])
                    if cached ~= true and not ns.ItemData.IsCached(itemID) then
                        return false
                    end
                    state.resolved = true
                    settleOne()
                    return true
                end, settleOne)
            end
        end
        data.requested = pending
        if pending == 0 then
            return readAll(false)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(ns.ITEMSTATS_WAIT_SECONDS, function()
                readAll(true)
            end)
        else
            readAll(true)
        end
    end,
    { async = true }
)

-- linklevel (E-0g, WKE-677): which link makes the client draw a journal row at
-- the level the walk LISTED it at. The walk keeps each drop's link and the
-- level the Adventure Guide previewed while it read it; read later, the link
-- answers at its OWN level (17 of 40 journal rows of the 2026-10-01 `capture
-- itemstats` transcript: keystone rows listed at 305 read 292, raid rows read
-- the difficulty's base level, world rows listed at 44 read 263 / 276), so the
-- engine compare scores a keystone row with 292 stats (ARCHITECTURE.md
-- section 11, E-0f). This capture asks the client, for up to
-- `ns.LINKLEVEL_MAX` such rows, what each candidate link draws, side by side,
-- and decides nothing: the transcript decides the rule
-- `ns.EngineStats.LinkAtLevel` takes.
--
-- The candidates per row (`variants`, each read three times - `before` the
-- walk, `journal` while the Adventure Guide previews the row's own instance,
-- difficulty and keystone level, and `after` the view is put back):
--   * `kept` - the link exactly as the walk kept it. Its `journal` read is
--     candidate (c): the SAME link read while the journal previews the row
--     (M5-3a measured the walk reading 305 off the keystone link that reads
--     292 later, so the client's answer may follow the view, not the link);
--   * `track-replace` / `track-append` - candidate (a): the link with its
--     bonus-ID list replaced by, or extended with, one bonus ID that puts an
--     item on an upgrade track at the row's level, for every track step that
--     draws it (Data/TrackBonusIDs.lua, Blizzard's data read through
--     SimulationCraft's extracted output at build 12.1.0.69933; 305 is both
--     Champion 5/6 and Hero 1/6, so both are tried). The two forms are the two
--     a public addon was seen to use (Mr. Mythical's GearSources.lua: its
--     dungeon preview replaces, its raid preview appends) - an inference about
--     the client this capture proves or refutes; nothing of that addon is
--     copied. A level no step draws (the world rows' 44) gets none, and says so;
--   * `journal-live` - candidate (b): the link the journal's loot list hands
--     out NOW for the row's item at the previewed target, when it differs from
--     the kept one (`live.sameAsKept` says whether it did). No `before` read:
--     it exists only once the walk is there.
-- For every read: `GetItemStats`, `GetDetailedItemLevelInfo`, and the
-- tooltip's lines (`C_TooltipInfo.GetHyperlink`, type and left text), with the
-- Item Level line (type 31, Enum.TooltipDataLineType.ItemLevel, Enum.lua:8638
-- under .luals/) and the Upgrade Level line (32, :8639) picked out by TYPE,
-- never by text.
--
-- **Not purely a read, and only in the way `capture journal` is not:** the
-- re-read goes through `ns.JournalAdapter.Walk` - the same walk, the same
-- adapter, the same view-state setters (instance, difficulty, loot filter,
-- keystone preview level) - which records the tier, difficulty and loot filter
-- first and puts all three back when it finishes, including when combat ends
-- it. As for `capture journal`, there is no getter for the keystone preview
-- level, so that one stays where the walk left it. Nothing acts on the
-- character, its items or its money. Refused in combat by ns.RunCapture; combat
-- during the walk stores nothing. An empty journal cache refuses the capture
-- (`ns.LINKLEVEL_NO_JOURNAL`), as does a cache with no row that differs
-- (`ns.LINKLEVEL_NONE`).
--
-- Every client function this section calls, with its exported documentation
-- line (Ketho's annotations under .luals/, Blizzard_APIDocumentationGenerated/):
--
--   ItemDocumentation.lua:126        C_Item.GetDetailedItemLevelInfo(itemInfo)
--   ItemDocumentation.lua:366        C_Item.GetItemStats(itemLink) -> statTable
--   TooltipInfoDocumentation.lua:121 C_TooltipInfo.GetHyperlink(hyperlink, ...)
--
-- and through the addon's own modules, whose client calls are named in their
-- own files (the Encounter Journal's in Modules/Journal.lua's
-- `Adapter.FUNCTION_NAMES`): the ones in LINKLEVEL_MODULE_READS. Nothing is
-- found by walking a namespace.
local LINKLEVEL_FUNCTION_NAMES = {
    "C_Item.GetDetailedItemLevelInfo",
    "C_Item.GetItemStats",
    "C_TooltipInfo.GetHyperlink",
}
ns.LINKLEVEL_FUNCTION_NAMES = LINKLEVEL_FUNCTION_NAMES

local LINKLEVEL_MODULE_READS = {
    "ns.EngineStats.LinkFields",
    "ns.EngineStats.RebuildLink",
    "ns.EngineStats.TrackBonusesAt",
    "ns.JournalAdapter.DifficultyID",
    "ns.JournalAdapter.Player",
    "ns.JournalAdapter.SelectTier",
    "ns.JournalAdapter.Tiers",
    "ns.JournalAdapter.ViewState",
    "ns.JournalAdapter.Walk",
}
ns.LINKLEVEL_MODULE_READS = LINKLEVEL_MODULE_READS

-- The issue's bound, and the tooltip line types picked out of each read.
ns.LINKLEVEL_MAX = 12
ns.LINKLEVEL_LINE_ITEM_LEVEL = 31
ns.LINKLEVEL_LINE_UPGRADE_LEVEL = 32

ns.LINKLEVEL_NO_JOURNAL = ns.ITEMSTATS_NO_JOURNAL
ns.LINKLEVEL_NONE = "found no cached journal row the client reads at another level than the walk listed"
ns.LINKLEVEL_COMBAT = "stopped: combat started during the walk; nothing stored"

-- One link, read the three ways. Raw probes, as everywhere in this file:
-- ns.CopyRaw at the store masks a secret and sets `sawSecret`.
local function linkLevelRead(link)
    local I = C_Item or {}
    local read = {
        stats = ns.Probe(I.GetItemStats, link),
        detailedLevel = ns.Probe(I.GetDetailedItemLevelInfo, link),
    }
    local tooltip = {}
    tooltipLines(tooltip, ns.Probe(C_TooltipInfo and C_TooltipInfo.GetHyperlink, link))
    read.tooltipLines = tooltip.lines
    read.tooltipData = tooltip.data
    for _, line in ipairs(type(tooltip.lines) == "table" and tooltip.lines or {}) do
        if type(line) == "table" then
            local lineType = ns.Safe(line.type)
            if lineType == ns.LINKLEVEL_LINE_ITEM_LEVEL and read.itemLevelLine == nil then
                read.itemLevelLine = line.leftText
            elseif lineType == ns.LINKLEVEL_LINE_UPGRADE_LEVEL and read.upgradeLevelLine == nil then
                read.upgradeLevelLine = line.leftText
            end
        end
    end
    return read
end

-- A list of rows taken round-robin out of per-key queues, in `order`.
local function roundRobin(order, queues, limit)
    local out = {}
    local progressed = true
    while progressed and (not limit or #out < limit) do
        progressed = false
        for _, key in ipairs(order) do
            local queue = queues[key]
            if #queue > 0 and (not limit or #out < limit) then
                out[#out + 1] = table.remove(queue, 1)
                progressed = true
            end
        end
    end
    return out
end

-- The candidates: every cached journal row whose link the client reads NOW at
-- another level than the walk listed, grouped by difficulty, each difficulty's
-- rows taken round-robin across instances, and the difficulties taken in turn
-- (lowest ID first) until `max` rows are taken. So keystone rows, raid rows
-- and world rows all reach the sample whenever the cache carries them, and no
-- one instance fills it.
function ns.LinkLevelCandidates(cache, max)
    max = max or ns.LINKLEVEL_MAX
    local rows, entries = journalRowsWithLink(cache)
    local I = C_Item or {}
    local byDifficulty, difficulties, differing, perDifficulty = {}, {}, 0, {}
    for _, row in ipairs(rows) do
        local own = ns.Safe(ns.Probe(I.GetDetailedItemLevelInfo, row.link)[1])
        if type(own) == "number" and type(row.itemLevel) == "number" and own ~= row.itemLevel then
            differing = differing + 1
            row.ownLevel = own
            local d = num(row.difficultyID)
            if not byDifficulty[d] then
                byDifficulty[d] = { order = {}, queues = {} }
                difficulties[#difficulties + 1] = d
            end
            local group = byDifficulty[d]
            local id = num(row.instanceID)
            if not group.queues[id] then
                group.queues[id] = {}
                group.order[#group.order + 1] = id
            end
            local queue = group.queues[id]
            queue[#queue + 1] = row
            perDifficulty[d] = (perDifficulty[d] or 0) + 1
        end
    end
    table.sort(difficulties)
    local perGroup = {}
    for _, d in ipairs(difficulties) do
        perGroup[d] = roundRobin(byDifficulty[d].order, byDifficulty[d].queues)
    end
    local taken = roundRobin(difficulties, perGroup, max)
    return taken,
        {
            cacheEntries = entries,
            rowsWithLink = #rows,
            differing = differing,
            differingByDifficulty = perDifficulty,
            taken = #taken,
            max = max,
        }
end

-- A row's candidate links, before anything is read.
local function linkLevelVariants(row)
    local variants = { { rule = "kept", link = row.link } }
    local parsed = ns.EngineStats.LinkFields(row.link)
    local steps = ns.EngineStats.TrackBonusesAt(row.itemLevel)
    for _, step in ipairs(steps) do
        local function variant(rule, link)
            variants[#variants + 1] = {
                rule = rule,
                link = link,
                bonusID = step.bonusID,
                track = step.track,
                step = step.step,
                trackLevel = step.itemLevel,
                clientConfirmedLevel = step.client,
            }
        end
        local replaced = ns.EngineStats.RebuildLink(row.link, { step.bonusID })
        if replaced then
            variant("track-replace", replaced)
        end
        if parsed then
            local list = {}
            for i, id in ipairs(parsed.bonusIDs) do
                list[i] = id
            end
            list[#list + 1] = step.bonusID
            local appended = ns.EngineStats.RebuildLink(row.link, list)
            if appended and appended ~= replaced then
                variant("track-append", appended)
            end
        end
    end
    return variants, parsed, #steps
end

local function targetKey(instanceID, difficultyID)
    return tostring(instanceID) .. "|" .. tostring(difficultyID)
end

-- One walk target per instance and difficulty the candidates name, in the
-- order they first name them; a keystone target previews the level the cached
-- walk previewed.
local function linkLevelTargets(candidates)
    local targets, seen = {}, {}
    local challenge = ns.JournalAdapter.DifficultyID("DungeonChallenge")
    for _, candidate in ipairs(candidates) do
        local key = targetKey(candidate.instanceID, candidate.difficultyID)
        if not seen[key] then
            seen[key] = true
            targets[#targets + 1] = {
                instanceID = candidate.instanceID,
                instanceName = candidate.instanceName,
                isRaid = candidate.isRaid == true,
                difficultyID = candidate.difficultyID,
                previewLevel = candidate.difficultyID == challenge and candidate.previewMythicPlusLevel or nil,
            }
        end
    end
    return targets
end

-- The live journal row for a candidate in a target's final read: the same
-- item, and the same encounter when both name one.
local function liveRow(read, candidate)
    for _, row in ipairs((read and read.rows) or {}) do
        local info = row.itemInfo and row.itemInfo[1]
        if type(info) == "table" and tonumber(info.itemID) == candidate.itemID then
            if candidate.encounterID == nil or info.encounterID == nil or info.encounterID == candidate.encounterID then
                return row, info
            end
        end
    end
    return nil
end

-- What the walk's own pass over a target adds to each candidate there: the
-- live link and the `journal` read of every variant, taken while the
-- Adventure Guide still previews that target.
local function readUnderView(record, read, candidates)
    for _, candidate in ipairs(candidates) do
        local row, info = liveRow(read, candidate)
        local link = info and ns.Safe(info.link) or nil
        local sameAsKept = nil
        if type(link) == "string" then
            sameAsKept = link == candidate.link
        end
        candidate.live = {
            found = row ~= nil,
            link = link,
            sameAsKept = sameAsKept,
            -- What the walk's own GetDetailedItemLevelInfo of the live link
            -- answered, under the preview (the adapter's read, already copied).
            walkDetailedLevel = row and row.detailedLevel or nil,
            previewLevel = record.previewLevel,
        }
        for _, variant in ipairs(candidate.variants) do
            variant.journal = linkLevelRead(variant.link)
        end
        if type(link) == "string" and link ~= "" and link ~= candidate.link then
            candidate.variants[#candidate.variants + 1] =
                { rule = "journal-live", link = link, journal = linkLevelRead(link) }
        end
    end
end

local function newCandidate(row)
    local variants, parsed, steps = linkLevelVariants(row)
    for _, variant in ipairs(variants) do
        variant.before = linkLevelRead(variant.link)
    end
    return {
        itemID = row.itemID,
        link = row.link,
        instanceID = row.instanceID,
        instanceName = row.instanceName,
        encounterID = row.encounterID,
        difficultyID = row.difficultyID,
        isRaid = row.isRaid,
        slot = row.slot,
        walkLevel = row.itemLevel,
        ownLevel = row.ownLevel,
        previewMythicPlusLevel = row.previewMythicPlusLevel,
        context = parsed and parsed.context or nil,
        bonusIDs = parsed and parsed.bonusIDs or nil,
        trackSteps = steps,
        trackNote = steps == 0 and ("no track step draws " .. tostring(row.itemLevel)) or nil,
        variants = variants,
    }
end

local function walkSummary(result, targetCount)
    local errors = {}
    for _, record in ipairs(result.targets or {}) do
        if record.onTargetReadError then
            errors[#errors + 1] = record.onTargetReadError
        end
    end
    return {
        targets = targetCount,
        durationMs = result.durationMs,
        lootEvents = result.lootEvents,
        waits = result.waits,
        timeouts = result.timeouts,
        itemDataTimeouts = result.itemDataTimeouts,
        pendingRowsFinalRead = result.pendingRowsFinalRead,
        restored = result.restored,
        secretsSeen = result.secretsSeen,
        errors = #errors > 0 and errors or nil,
    }
end

ns.RegisterCapture(
    "linklevel",
    "journal links at the walk's level: each rebuilt candidate and the live journal link, read side by side "
        .. "(async; sets and restores the Adventure Guide view)",
    function(finish)
        local cache = ns.db and ns.db.global and ns.db.global.journalCache or nil
        local rows, summary = ns.LinkLevelCandidates(cache, ns.LINKLEVEL_MAX)
        if summary.rowsWithLink == 0 then
            return finish(nil, ns.LINKLEVEL_NO_JOURNAL)
        end
        if #rows == 0 then
            return finish(nil, ns.LINKLEVEL_NONE)
        end
        local trackData = ns.trackBonusIDs
        local data = {
            functionNames = LINKLEVEL_FUNCTION_NAMES,
            moduleReads = LINKLEVEL_MODULE_READS,
            journal = summary,
            trackTable = type(trackData) == "table" and { build = trackData.build, source = trackData.source } or nil,
            lineTypes = { itemLevel = ns.LINKLEVEL_LINE_ITEM_LEVEL, upgradeLevel = ns.LINKLEVEL_LINE_UPGRADE_LEVEL },
            candidates = {},
        }
        local byTarget = {}
        for i, row in ipairs(rows) do
            local candidate = newCandidate(row)
            data.candidates[i] = candidate
            local key = targetKey(candidate.instanceID, candidate.difficultyID)
            byTarget[key] = byTarget[key] or {}
            table.insert(byTarget[key], candidate)
        end

        local Adapter = ns.JournalAdapter
        local player = Adapter.Player()
        local viewState = Adapter.ViewState()
        data.viewStateBefore = viewState
        local tiers = Adapter.Tiers()
        if type(tiers.numTiers[1]) == "number" then
            data.selectedTier = tiers.numTiers[1]
            Adapter.SelectTier(data.selectedTier)
        end
        local targets = linkLevelTargets(data.candidates)

        Adapter.Walk({
            targets = targets,
            classID = player.classID,
            specID = player.specID,
            viewState = viewState,
            onTargetRead = function(record, read)
                readUnderView(record, read, byTarget[targetKey(record.instanceID, record.difficultyID)] or {})
            end,
        }, function(result)
            if result.abortedInCombat then
                return finish(nil, ns.LINKLEVEL_COMBAT)
            end
            data.walk = walkSummary(result, #targets)
            for _, candidate in ipairs(data.candidates) do
                for _, variant in ipairs(candidate.variants) do
                    variant.after = linkLevelRead(variant.link)
                end
            end
            finish(data)
        end)
    end,
    { async = true }
)
