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
ns.RegisterCapture(
    "vault",
    "Great Vault activities and reward links (run before and after opening the vault)",
    function()
        local W = C_WeeklyRewards
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
        return {
            namespaceKeys = sortedKeys(W),
            hasAvailableRewards = ns.Probe(W and W.HasAvailableRewards),
            canClaimRewards = ns.Probe(W and W.CanClaimRewards),
            frameShown = WeeklyRewardsFrame and ns.Probe(WeeklyRewardsFrame.IsShown, WeeklyRewardsFrame)
                or { absent = true },
            blizzardAddonLoaded = ns.Probe(C_AddOns and C_AddOns.IsAddOnLoaded, "Blizzard_WeeklyRewards"),
            secondsUntilWeeklyReset = ns.Probe(C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset),
            activities = activities,
            rewardLinks = rewardLinks,
            exampleLinks = exampleLinks,
        }
    end
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
