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

-- env: build, addons, restrictions, the namespaces later modules touch.
-- M0-2 (WKE-515) reads build[4] against the .toc Interface number.
ns.RegisterCapture("env", "build, addon list, secret/combat state, API namespaces", function()
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
