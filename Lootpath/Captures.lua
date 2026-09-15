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
-- **This is the second recorded exception to "captures only read"** (the first
-- is the journal's view state, ARCHITECTURE.md §7 2026-09-06), allowed by the
-- owner's decision of 2026-09-14. `OnUIInteract` tells the server the player is
-- interacting with the vault and the server answers with the reward list; it
-- changes nothing about the character, its items or its money, and
-- `CloseInteraction` is called afterwards **always, including on timeout**.
-- `ClaimReward` and `SelectReward` are never called and are not named below.
--
-- **The exception has a second limit since R-7 (WKE-579): it never happens at
-- logout.** The capture sequence at `PLAYER_LOGOUT` passes `skipInteract`, so
-- `OnUIInteract` is not called there at all - there is no time to wait for the
-- server's answer and nothing left running to receive it - and the snapshot
-- records `interact.skipped = "logout"`.
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
-- `interact.after` holds the same three lists read again once the update fires.
-- Nothing is copied between them: a reader that wants the best list takes
-- `interact.after` when it is there and the top level otherwise, which is what
-- `VaultPanel.NameFromCaptures` and the companion's `vaultRows` do.
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
-- Nothing has measured how fast the server answers yet - the first
-- `/lootpath refresh` on a synced build is what will say - so the bound is the
-- owner's "a few seconds" and the snapshot records whether it fired and how
-- long it took rather than assuming either.
ns.VAULT_INTERACT_TIMEOUT_SECONDS = 5

-- Why a capture read the vault without asking the client for the withheld
-- rewards (R-7, WKE-579). One string, here beside the bound it replaces.
ns.VAULT_SKIPPED_REASON = "a logout has no time to ask the client and nothing to wait with"

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
    -- `args.skipInteract` is R-7's (WKE-579): the capture sequence at
    -- `PLAYER_LOGOUT` has no time to ask the server anything and no way to wait
    -- for an answer, so it passes `{ skipInteract = "logout" }` and gets the
    -- plain read. The snapshot then says `interact.skipped = "logout"` rather
    -- than looking like a refresh whose interaction was not needed. A table
    -- rather than a string, so `/lootpath capture vault <text>` cannot reach it.
    function(finish, args)
        local W = C_WeeklyRewards
        local skipInteract = type(args) == "table" and args.skipInteract or nil
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
        if needed and skipInteract then
            needed, reason = false, ns.VAULT_SKIPPED_REASON
        end
        if needed and type(W and W.OnUIInteract) ~= "function" then
            needed, reason = false, "this client has no C_WeeklyRewards.OnUIInteract"
        end
        if not needed then
            -- `skipped` is recorded whether or not the interaction would have
            -- happened: what it says is that this read was the plain one and
            -- why, which is true of every capture the logout takes.
            data.interact = { attempted = false, reason = reason, skipped = skipInteract }
            return finish(data)
        end

        local record = { attempted = true, reason = reason, updateFired = false, timedOut = false }
        data.interact = record
        local startedAt = debugprofilestop and debugprofilestop() or nil
        local listener = CreateFrame("Frame")
        local settled = false

        -- CloseInteraction is the other half of OnUIInteract and runs on every
        -- path out of here - the update, the timeout, and a client that errors
        -- on OnUIInteract itself. Blizzard's frame calls it from OnHide for the
        -- same reason: an interaction the server is never told ended is the one
        -- thing this capture could leave behind.
        local function settle(fired)
            if settled then
                return
            end
            settled = true
            listener:UnregisterEvent("WEEKLY_REWARDS_UPDATE")
            listener:SetScript("OnEvent", nil)
            record.updateFired = fired
            record.timedOut = not fired
            if startedAt and debugprofilestop then
                record.waitedMs = debugprofilestop() - startedAt
            end
            if fired then
                record.after = vaultLists(W)
            end
            record.close = ns.Probe(W.CloseInteraction)
            finish(data)
        end

        listener:SetScript("OnEvent", function(_, event)
            if event == "WEEKLY_REWARDS_UPDATE" then
                settle(true)
            end
        end)
        listener:RegisterEvent("WEEKLY_REWARDS_UPDATE")
        record.interact = ns.Probe(W.OnUIInteract)
        if record.interact.error then
            -- The client refused the question; there is nothing to wait for,
            -- and CloseInteraction still runs on the way out.
            return settle(false)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(ns.VAULT_INTERACT_TIMEOUT_SECONDS, function()
                settle(false)
            end)
        else
            settle(false)
        end
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
-- **What is NOT known, and is what the transcript is for.** Whether
-- `SetItemUpgradeFromLocation` needs the vendor frame open at all, whether it
-- fires `ITEM_UPGRADE_MASTER_SET_ITEM` (Blizzard's frame re-reads on that
-- event, same file lines 42 and 83, which is the only reason to think it
-- does), how long the client takes to answer, and whether the info comes back
-- nil for an item the vendor will not take: none of that is in the exported
-- docs, and the Warcraft Wiki is stale after 10.1.7. So the capture asks for
-- the frame to be open, waits for the event per item with a bound, and records
-- for every item whether the event fired, how long it waited and exactly what
-- came back - rather than assuming any of it. The shape of
-- `ItemUpgradeItemInfo` IS documented (`currUpgrade`, `maxUpgrade`,
-- `upgradeLevelInfos[]`, each with `currencyCostsToUpgrade[]` and
-- `itemCostsToUpgrade[]`), and it is stored raw anyway: nothing is normalised
-- here, and no road reads it until the transcript is committed.
local UPGRADE_FUNCTION_NAMES = {
    "CanUpgradeItem",
    "ClearItemUpgrade",
    "GetHighWatermarkForItem",
    "GetItemHyperlink",
    "GetItemUpgradeCurrentLevel",
    "GetItemUpgradeItemInfo",
    "SetItemUpgradeFromLocation",
}

-- How long the capture waits for ITEM_UPGRADE_MASTER_SET_ITEM after setting
-- ONE item before it reads anyway and says it timed out. Nothing has measured
-- how fast the client answers - the owner's first run at a vendor is what will
-- say - so this is a bound, not a measurement, and every item's record carries
-- `eventFired` and `waitedMs` so the transcript can replace it with a figure.
ns.UPGRADE_SET_TIMEOUT_SECONDS = 2

-- Every owned item the vendor might take, in the order Blizzard's own flyout
-- would collect them: the equipped slots first, then the bags. Only the two
-- inventory reads and the two container reads the other captures already make.
-- `CanUpgradeItem` is asked about each one below, and an item it refuses is
-- recorded with that answer rather than dropped, because "the vendor will not
-- take this" is as much of a finding as a cost table.
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
-- FLAT onto the item's own record. Called once per item, after the client has
-- either answered or run out of time.
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
            timeoutSeconds = ns.UPGRADE_SET_TIMEOUT_SECONDS,
            -- What was in the window before the capture touched it. The window
            -- is cleared when the capture is done and this is NOT put back:
            -- setting an item the owner did not choose is a change, and the
            -- transcript saying what was there is enough for him to put it
            -- back himself.
            itemInWindowAtStart = ns.Probe(U.GetItemHyperlink),
            candidateCount = #candidates,
            items = {},
        }

        local index = 0
        local function nextItem()
            index = index + 1
            local candidate = candidates[index]
            if not candidate then
                -- The window is left empty on every path out of here,
                -- including a client that errored on any one item.
                data.clearedAtEnd = ns.Probe(U.ClearItemUpgrade)
                return finish(data)
            end

            local parsed = ns.ParseItemLink(candidate.link)
            local record = {
                source = candidate.source,
                invSlot = candidate.invSlot,
                bag = candidate.bag,
                slotIndex = candidate.slotIndex,
                link = candidate.link,
                key = parsed and parsed.key or nil,
                itemID = parsed and parsed.itemID or nil,
                canUpgrade = ns.Probe(U.CanUpgradeItem, candidate.location),
            }
            data.items[#data.items + 1] = record

            if ns.Safe(record.canUpgrade[1]) ~= true then
                -- The vendor will not take it. Nothing was set, so there is
                -- nothing to clear, and the answer itself is the record.
                return nextItem()
            end

            local startedAt = debugprofilestop and debugprofilestop() or nil
            local listener = CreateFrame("Frame")
            local settled = false
            local function settle(fired)
                if settled then
                    return
                end
                settled = true
                listener:UnregisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
                listener:SetScript("OnEvent", nil)
                record.eventFired = fired
                record.timedOut = not fired
                if startedAt and debugprofilestop then
                    record.waitedMs = debugprofilestop() - startedAt
                end
                upgradeReadsInto(record, U, candidate.link)
                record.cleared = ns.Probe(U.ClearItemUpgrade)
                nextItem()
            end

            listener:SetScript("OnEvent", function(_, event)
                if event == "ITEM_UPGRADE_MASTER_SET_ITEM" then
                    settle(true)
                end
            end)
            listener:RegisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
            record.set = ns.Probe(U.SetItemUpgradeFromLocation, candidate.location)
            if record.set.error then
                -- The client refused to take the item; there is nothing to
                -- wait for, and the window is still cleared on the way out.
                return settle(false)
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(ns.UPGRADE_SET_TIMEOUT_SECONDS, function()
                    settle(false)
                end)
            else
                settle(false)
            end
        end

        nextItem()
    end,
    { async = true }
)
