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
    end
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
