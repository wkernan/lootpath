local H = require("spec.helpers.addon")

-- Item links shaped like the client's (itemID at field 2, bonus-ID count at
-- field 14 per the SimulationCraft addon's parser). Placeholders until the
-- M1-2 capture transcript lands under spec/fixtures/captures/.
local HELM = "|cffa335ee|Hitem:210001::::::::80:105::13:2:1:2::::::|h[Test Helm]|h|r"
local RING = "|cffa335ee|Hitem:210002::::::::80:105::13:1:5::::::|h[Test Ring]|h|r"
local VAULT_ITEM = "|cffa335ee|Hitem:210003::::::::80:105::13:2:7:8::::::|h[Vault Chest]|h|r"

describe("captures", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("registers env, inventory, vault, currencies and journal in that order", function()
        -- `journal` registers in Modules/Journal.lua, which the .toc loads
        -- after this file, so it comes last.
        assert.same({ "env", "inventory", "vault", "currencies", "journal" }, ns.captureOrder)
    end)

    describe("env", function()
        it("records the build tuple raw", function()
            local result = ns.RunCapture("env")
            assert.is_true(result.ok)
            local data = result.snapshot.data
            assert.equal("12.1.0", data.build[1])
            assert.equal("69587", data.build[2])
            assert.equal(120100, data.build[4])
            assert.equal(6, data.build.n)
        end)

        it("records every addon with its loaded state", function()
            local data = ns.RunCapture("env").snapshot.data
            assert.equal(2, data.addons.count[1])
            assert.equal("Lootpath", data.addons.list[1].name)
            assert.is_true(data.addons.list[1].loaded)
            assert.equal("Simulationcraft", data.addons.list[2].name)
            assert.is_false(data.addons.list[2].loaded)
        end)

        -- WKE-532: the companion builds the SimC profile header out of these.
        -- The `n` assertions matter as much as the values: ns.Probe packs a
        -- pcall, so a missing function would come back as a pack with no
        -- positional result rather than as a wrong string.
        it("records the four player facts the SimC profile header needs", function()
            local data = ns.RunCapture("env").snapshot.data
            assert.equal(90, data.level[1])
            assert.equal("Zandalari Troll", data.race[1])
            assert.equal("ZandalariTroll", data.race[2])
            assert.equal(31, data.race[3])
            assert.equal(3, data.race.n)
            assert.equal("US", data.region[1])
            assert.equal(1, data.regionID[1])
        end)

        it("records an absent region API as absent, not as a guess", function()
            _G.GetCurrentRegionName = nil
            local data = ns.RunCapture("env").snapshot.data
            assert.same({ absent = true }, data.region)
            assert.equal(1, data.regionID[1])
        end)

        it("records secret and combat state", function()
            local data = ns.RunCapture("env").snapshot.data
            assert.equal("function", data.secrets.issecretvalue)
            assert.equal("function", data.secrets.issecrettable)
            assert.is_true(data.secrets.hasSecretRestrictions[1])
            assert.is_false(data.inCombatLockdown[1])
        end)

        it("records enums, namespaces and EJ globals", function()
            local data = ns.RunCapture("env").snapshot.data
            assert.equal(0, data.enums.BagIndex.Backpack)
            assert.equal(2, data.enums.BankType.Account)
            assert.same({
                "GetInstanceForGameMap",
                "GetLootInfoByIndex",
                "InstanceHasLoot",
                "SetPreviewMythicPlusLevel",
            }, data.namespaces.C_EncounterJournal)
            -- The stub's journal surface (M3-1, plus EJ_GetEncounterInfo in
            -- PR 2); the real client listed 35 EJ_ globals in the 2026-09-05
            -- transcript.
            assert.truthy(table.concat(data.globals.EJ, " "):find("EJ_SetLootFilter=function", 1, true))
            assert.equal(19, #data.globals.EJ)
            assert.equal("function", data.globals.equip["C_Item.EquipItemByName"])
            assert.equal("nil", data.globals.equip.EquipItemByName)
            assert.equal(1, data.constants.INVSLOT_FIRST_EQUIPPED)
            assert.equal(19, data.constants.INVSLOT_LAST_EQUIPPED)
        end)

        it("records an absent API as absent, not as an error", function()
            _G.C_Secrets = nil
            local result = ns.RunCapture("env")
            assert.is_true(result.ok)
            assert.same({ absent = true }, result.snapshot.data.secrets.hasSecretRestrictions)
        end)
    end)

    describe("inventory", function()
        before_each(function()
            world.equipped[1] = { link = HELM, id = 210001 }
            world.items[HELM] = {
                level = 610,
                info = {
                    "Test Helm",
                    HELM,
                    4,
                    610,
                    80,
                    "Armor",
                    "Leather",
                    1,
                    "INVTYPE_HEAD",
                    1,
                    0,
                    4,
                    2,
                    1,
                    11,
                    0,
                    false,
                },
                instant = { 210001, "Armor", "Leather", "INVTYPE_HEAD", 1, 4, 2 },
            }
            world.bags[0] = {
                numSlots = 4,
                items = {
                    [3] = {
                        info = { hyperlink = RING, itemID = 210002, stackCount = 1, quality = 4, isBound = true },
                        link = RING,
                        id = 210002,
                    },
                },
            }
            world.items[RING] = { level = 600 }
            world.bags[6] = { numSlots = 0, items = {} }
        end)

        it("records equipped slots with the raw item probes", function()
            local data = ns.RunCapture("inventory").snapshot.data
            assert.equal(1, #data.equipped)
            local helm = data.equipped[1]
            assert.equal(1, helm.invSlot)
            assert.equal(HELM, helm.link[1])
            assert.equal(210001, helm.itemID[1])
            assert.equal(610, helm.item.detailedLevel[1])
            assert.equal("Test Helm", helm.item.info[1])
            assert.equal("INVTYPE_HEAD", helm.item.instant[4])
            assert.equal(610, helm.currentLevel[1])
        end)

        it("records every bag index with its slot count and only occupied slots", function()
            local data = ns.RunCapture("inventory").snapshot.data
            local byIndex = {}
            for _, bag in ipairs(data.bags) do
                byIndex[bag.bagIndex] = bag
            end
            assert.is_table(byIndex[0])
            assert.equal("Backpack", byIndex[0].name)
            assert.equal(4, byIndex[0].numSlots[1])
            assert.equal(3, byIndex[0].freeSlots[1])
            assert.is_nil(byIndex[0].items[1])
            local ring = byIndex[0].items[3]
            assert.equal(210002, ring.info[1].itemID)
            assert.equal(RING, ring.info[1].hyperlink)
            assert.equal(RING, ring.link[1])
            assert.equal(600, ring.item.detailedLevel[1])
            assert.is_nil(ring.item.info[1])
            assert.is_table(byIndex[-3])
            assert.equal(0, byIndex[-3].numSlots[1])
        end)

        it("walks bag indexes in ascending order", function()
            local data = ns.RunCapture("inventory").snapshot.data
            for i = 2, #data.bags do
                assert.is_true(data.bags[i - 1].bagIndex < data.bags[i].bagIndex)
            end
        end)

        it("records the bank state both ways", function()
            local closed = ns.RunCapture("inventory").snapshot.data.bank
            assert.is_false(closed.frameShown[1])
            assert.is_false(closed.predicates.CanViewBank.Character[1])
            world.bankOpen = true
            local open = ns.RunCapture("inventory").snapshot.data.bank
            assert.is_true(open.frameShown[1])
            assert.is_true(open.predicates.CanViewBank.Account[1])
            assert.same({ "CanPurchaseBankTab", "CanUseBank", "CanViewBank", "HasMaxBankTabs" }, open.namespaceKeys)
        end)

        it("never calls a bank function outside the allow list", function()
            local called = false
            _G.C_Bank.AutoDepositItemsIntoBank = function()
                called = true
            end
            local result = ns.RunCapture("inventory")
            assert.is_true(result.ok)
            assert.is_false(called)
            assert.is_nil(result.snapshot.data.bank.predicates.AutoDepositItemsIntoBank)
        end)
    end)

    describe("vault", function()
        before_each(function()
            world.vault.hasAvailable = true
            world.vault.activities = {
                {
                    type = 1,
                    index = 1,
                    threshold = 1,
                    progress = 4,
                    id = 11,
                    activityTierID = 100,
                    level = 10,
                    rewards = {
                        { type = 1, id = 210003, quantity = 1, itemDBID = "9001" },
                        { type = 2, id = 3008, quantity = 15 },
                    },
                },
            }
            world.vault.links["9001"] = VAULT_ITEM
            world.items[VAULT_ITEM] = { level = 623 }
            world.vault.examples[11] = { VAULT_ITEM }
        end)

        it("records the activities raw and resolves item reward links", function()
            local data = ns.RunCapture("vault").snapshot.data
            assert.is_true(data.hasAvailableRewards[1])
            assert.is_false(data.canClaimRewards[1])
            assert.equal(11, data.activities[1][1].id)
            assert.equal(2, #data.activities[1][1].rewards)
            assert.equal(1, #data.rewardLinks)
            local reward = data.rewardLinks[1]
            assert.equal(1, reward.activityIndex)
            assert.equal(1, reward.rewardIndex)
            assert.equal(210003, reward.itemID)
            assert.equal("9001", reward.itemDBID)
            assert.equal(VAULT_ITEM, reward.link[1])
            assert.equal(623, reward.item.detailedLevel[1])
            assert.equal(VAULT_ITEM, data.exampleLinks[1][1])
        end)

        it("skips currency rewards without calling GetItemHyperlink on nil", function()
            local calls = {}
            _G.C_WeeklyRewards.GetItemHyperlink = function(itemDBID)
                calls[#calls + 1] = itemDBID
                return world.vault.links[itemDBID]
            end
            ns.RunCapture("vault")
            assert.same({ "9001" }, calls)
        end)

        it("records a link that came back empty", function()
            -- The SimC addon notes GetItemHyperlink "may return nothing"; whether
            -- that is nil or no value is what the transcript's `n` will show.
            world.vault.links["9001"] = nil
            local reward = ns.RunCapture("vault").snapshot.data.rewardLinks[1]
            assert.is_nil(reward.link[1])
            assert.is_number(reward.link.n)
            assert.is_nil(reward.item)
        end)

        it("records the frame and reset state", function()
            local data = ns.RunCapture("vault").snapshot.data
            assert.is_false(data.frameShown[1])
            assert.equal(3600, data.secondsUntilWeeklyReset[1])
            world.vaultOpen = true
            assert.is_true(ns.RunCapture("vault").snapshot.data.frameShown[1])
        end)

        it("survives an empty vault", function()
            world.vault.hasAvailable = false
            world.vault.activities = {}
            local result = ns.RunCapture("vault")
            assert.is_true(result.ok)
            assert.same({}, result.snapshot.data.rewardLinks)
        end)
    end)

    -- WKE-544 (M3-9), with the by-ID probe of WKE-546 (M3-11). Every name and
    -- ID in `world.currencies` below is a placeholder in Blizzard's documented
    -- CurrencyInfo shape (Ketho's CurrencyInfoDocumentation.lua) and is
    -- labelled as such; the IDs the capture PROBES are the real measured ones,
    -- because they are the addon's own `Currencies.KNOWN_IDS`. What the tests
    -- pin is the SHAPE of the walk - every index, headers kept, the full info
    -- behind every non-header entry, and a direct answer for every known ID
    -- whatever the currency tab is showing.
    describe("currencies", function()
        before_each(function()
            world.currencies = {
                { name = "Placeholder Header", currencyID = 0, isHeader = true, isHeaderExpanded = true, quantity = 0 },
                { name = "Placeholder Crest", currencyID = 900001, isHeader = false, quantity = 42 },
                { name = "Placeholder Charge", currencyID = 900002, isHeader = false, quantity = 1 },
            }
        end)

        it("records every index of the list, headers included", function()
            local data = ns.RunCapture("currencies").snapshot.data
            assert.equal(3, data.listSize[1])
            assert.equal(3, #data.list)
            assert.is_true(data.list[1][1].isHeader)
            -- The field that proved the list is the tab's scroll state and not
            -- the player's holdings (WKE-546); it keeps being recorded.
            assert.is_true(data.list[1][1].isHeaderExpanded)
            assert.equal("Placeholder Crest", data.list[2][1].name)
            assert.equal(42, data.list[2][1].quantity)
        end)

        -- The M3-11 half: the capture asks the client about every ID the addon
        -- knows, so a currency under a header the player left collapsed - which
        -- the list never shows - is in the transcript all the same.
        it("probes every known currency ID and stores the answers under byID", function()
            world.currencies = {
                {
                    name = "Placeholder Collapsed Header",
                    currencyID = 0,
                    isHeader = true,
                    isHeaderExpanded = false,
                    quantity = 0,
                },
            }
            world.currencyByID = {
                [3465] = {
                    name = "Venomblight Manaflux",
                    currencyID = 3465,
                    isHeader = false,
                    quantity = 1,
                    maxQuantity = 8,
                },
            }
            local data = ns.RunCapture("currencies").snapshot.data
            assert.same(ns.Currencies.AllKnownIDs(), data.probedIDs)
            assert.equal(1, #data.list)
            assert.equal(0, #data.info)
            for _, id in ipairs(data.probedIDs) do
                assert.is_table(data.byID[id])
            end
            assert.equal("Venomblight Manaflux", data.byID[3465][1].name)
            assert.equal(1, data.byID[3465][1].quantity)
            assert.equal(8, data.byID[3465][1].maxQuantity)
        end)

        it("never expands a header to make one readable", function()
            _G.C_CurrencyInfo.ExpandCurrencyList = function()
                error("ExpandCurrencyList changes UI state and must never be called")
            end
            assert.is_true(ns.RunCapture("currencies").ok)
        end)

        it("records the full info behind every non-header entry and no header", function()
            local data = ns.RunCapture("currencies").snapshot.data
            assert.equal(2, #data.info)
            assert.equal(900001, data.info[1].currencyID)
            assert.equal(2, data.info[1].index)
            assert.equal(42, data.info[1].info[1].quantity)
            assert.equal(900002, data.info[2].currencyID)
            for _, entry in ipairs(data.info) do
                assert.is_false(entry.info[1].isHeader)
            end
        end)

        it("names the namespace it read without calling anything it did not name", function()
            local called = false
            _G.C_CurrencyInfo.RequestCurrencyDataForAccountCharacters = function()
                called = true
            end
            local data = ns.RunCapture("currencies").snapshot.data
            assert.is_false(called)
            assert.is_truthy(table.concat(data.namespaceKeys, " "):find("GetCurrencyListSize", 1, true))
        end)

        it("survives a client with no currency API", function()
            _G.C_CurrencyInfo = nil
            local result = ns.RunCapture("currencies")
            assert.is_true(result.ok)
            assert.same({ absent = true }, result.snapshot.data.listSize)
            assert.same({}, result.snapshot.data.list)
            assert.same({}, result.snapshot.data.info)
            assert.same({}, result.snapshot.data.byID)
        end)

        it("drops a secret entry rather than storing it", function()
            world.currencies[2] = world.secretTable("currency")
            local result = ns.RunCapture("currencies")
            assert.is_true(result.ok)
            assert.is_true(result.snapshot.sawSecret)
            assert.equal(ns.MARKERS.secretTable, result.snapshot.data.list[2][1])
            -- The secret entry produced no GetCurrencyInfo call, so only the
            -- other non-header entry is in `info`.
            assert.equal(1, #result.snapshot.data.info)
            assert.equal(900002, result.snapshot.data.info[1].currencyID)
        end)
    end)
end)
