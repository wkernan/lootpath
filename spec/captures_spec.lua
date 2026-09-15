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

    it("registers env, inventory, vault, currencies, glow, upgrade and journal in that order", function()
        -- `journal` registers in Modules/Journal.lua, which the .toc loads
        -- after this file, so it comes last. R-0's `spike` was the sixth and
        -- went away with R-2 (WKE-563), which is the surface it measured;
        -- `glow` is R-2a's (WKE-571) and `upgrade` M3-17's (WKE-574), and both
        -- register here, at the end of this file.
        assert.same({ "env", "inventory", "vault", "currencies", "glow", "upgrade", "journal" }, ns.captureOrder)
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

        -- R-0 (WKE-561). The Roads brief wants "your key +8" beside a dungeon
        -- drop; this is the read it rests on, recorded raw and shown nowhere.
        describe("the keystone", function()
            it("records the level, both map IDs and the name behind the challenge map ID", function()
                world.keystone = { level = 8, challengeMapID = 542, mapID = 2664 }
                local data = ns.RunCapture("env").snapshot.data
                assert.equal(8, data.keystone.level[1])
                assert.equal(542, data.keystone.challengeMapID[1])
                assert.equal(2664, data.keystone.mapID[1])
                assert.equal(1, data.keystone.level.n)
            end)

            it("asks GetMapUIInfo with the challenge map ID, not the map ID", function()
                world.keystone = { level = 8, challengeMapID = 542, mapID = 2664 }
                world.journal.mapUIInfo[542] = { "Ara-Kara, City of Echoes", 542, 1980, 4030202, 4030203, 2664 }
                local data = ns.RunCapture("env").snapshot.data
                assert.equal("Ara-Kara, City of Echoes", data.keystone.mapUIInfo[1])
                assert.equal(2664, data.keystone.mapUIInfo[6])
            end)

            it("records a character holding no key as the client answers it, and asks for no name", function()
                local data = ns.RunCapture("env").snapshot.data
                assert.equal(0, data.keystone.level[1])
                assert.equal(0, data.keystone.challengeMapID[1])
                -- 0 is a number, so the name IS asked for; what comes back is
                -- the client's own nothing rather than an invented name.
                assert.is_nil(data.keystone.mapUIInfo[1])
            end)

            it("records an absent keystone API as absent, not as a zero", function()
                _G.C_MythicPlus = nil
                local data = ns.RunCapture("env").snapshot.data
                assert.same({ absent = true }, data.keystone.level)
                assert.same({ absent = true }, data.keystone.mapUIInfo)
            end)
        end)

        -- R-0 (WKE-561): which bag frames are live. The glow has three code
        -- paths and nothing recorded which one the owner is looking at.
        describe("the bag addons", function()
            it("probes the six names by name and records what each answered", function()
                world.addons[#world.addons + 1] = { name = "Baganator", title = "Baganator", loaded = true }
                world.addons[#world.addons + 1] = { name = "ElvUI", title = "ElvUI", loaded = false }
                local data = ns.RunCapture("env").snapshot.data
                assert.same({
                    "Baganator",
                    "Syndicator",
                    "ElvUI",
                    "Pawn",
                    "Blizzard_UIPanels_Game",
                    "Blizzard_BankUI",
                }, data.bagAddons.probed)
                assert.is_true(data.bagAddons.loaded.Baganator[1])
                assert.is_false(data.bagAddons.loaded.ElvUI[1])
                assert.is_false(data.bagAddons.loaded.Pawn[1])
            end)

            it("records the type of each bag global, never calling one", function()
                local data = ns.RunCapture("env").snapshot.data
                assert.equal("nil", data.bagAddons.globals.ContainerFrameCombinedBags)
                assert.equal("nil", data.bagAddons.globals.Baganator)
                _G.ContainerFrameCombinedBags = _G.CreateFrame("Frame", "ContainerFrameCombinedBags")
                local second = ns.RunCapture("env").snapshot.data
                assert.equal("table", second.bagAddons.globals.ContainerFrameCombinedBags)
            end)
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

        -- M3-16 (WKE-557). Blizzard's own UpdatePreviousClaim reads exactly
        -- this pair to decide whether to show the "rewards from last week"
        -- notice, and the pair is what says the client is holding rewards back.
        it("records whether the rewards are this period's and whether any were generated", function()
            world.vault.currentPeriod = false
            world.vault.generated = true
            local data = ns.RunCapture("vault").snapshot.data
            assert.is_false(data.areRewardsForCurrentRewardPeriod[1])
            assert.is_true(data.hasGeneratedRewards[1])
        end)

        it("names every C_WeeklyRewards function it may call, and never ClaimReward", function()
            local names = ns.RunCapture("vault").snapshot.data.functionNames
            assert.same({
                "AreRewardsForCurrentRewardPeriod",
                "CanClaimRewards",
                "CloseInteraction",
                "GetActivities",
                "GetExampleRewardItemHyperlinks",
                "GetItemHyperlink",
                "HasAvailableRewards",
                "HasGeneratedRewards",
                "OnUIInteract",
            }, names)
            for _, name in ipairs(names) do
                assert.not_equal("ClaimReward", name)
                assert.not_equal("SelectReward", name)
            end
        end)

        -- The interaction is for one state and one state only: the client says
        -- rewards are waiting and lists not one of them. With rewards in the
        -- list (the before_each above) nothing is asked for.
        it("does not interact when the activities already carry rewards", function()
            local data = ns.RunCapture("vault").snapshot.data
            assert.is_false(data.interact.attempted)
            assert.equal("the activities already carry rewards", data.interact.reason)
            assert.equal(0, world.vault.interact.onUIInteract)
            assert.equal(0, world.vault.interact.closeInteraction)
        end)

        it("does not interact when the client says no rewards are waiting", function()
            world.vault.hasAvailable = false
            local data = ns.RunCapture("vault").snapshot.data
            assert.is_false(data.interact.attempted)
            assert.equal("the client says no rewards are waiting", data.interact.reason)
            assert.equal(0, world.vault.interact.onUIInteract)
        end)

        -- The measured state, replayed: HasAvailableRewards true, activities
        -- carrying this period's progress with `rewards = {}` on every one, so
        -- the reward links are empty (owner's SavedVariables, 2026-09-09 22:40Z
        -- onwards, ARCHITECTURE.md §9).
        describe("when the client is holding the rewards back", function()
            before_each(function()
                world.vault.hasAvailable = true
                world.vault.canClaim = false
                world.vault.currentPeriod = false
                world.vault.generated = true
                -- This period's progress, no rewards on any activity.
                world.vault.activities = {
                    { type = 1, index = 1, threshold = 1, progress = 2, id = 11, level = 1, rewards = {} },
                }
                world.vault.examples = {}
                world.vault.links = {}
                -- What the server answers with once the vault is interacted
                -- with: last week's unclaimed reward, back in the list.
                world.vault.answerOnInteract = {
                    activities = {
                        {
                            type = 1,
                            index = 1,
                            threshold = 1,
                            progress = 2,
                            id = 11,
                            level = 10,
                            rewards = { { type = 1, id = 210003, quantity = 1, itemDBID = "9001" } },
                        },
                    },
                    links = { ["9001"] = VAULT_ITEM },
                    examples = { [11] = { VAULT_ITEM } },
                }
                world.vault.answerDelaySeconds = 0.4
            end)

            it("asks the client, waits for the update, reads again and closes the interaction", function()
                local result = ns.RunCapture("vault")
                -- Nothing is stored until the client answers: the snapshot is
                -- the point of the wait.
                assert.is_true(result.pending)
                assert.is_nil(ns.db.global.captures.vault)
                assert.equal(1, world.vault.interact.onUIInteract)

                world.runTimers(10)

                local snapshot = ns.db.global.captures.vault[1]
                local data = snapshot.data
                assert.is_true(data.interact.attempted)
                assert.equal("rewards are waiting and no activity carries one", data.interact.reason)
                assert.is_true(data.interact.updateFired)
                assert.is_false(data.interact.timedOut)
                assert.is_number(data.interact.waitedMs)
                assert.equal(1, world.vault.interact.closeInteraction)

                -- Both reads are kept and neither is merged into the other.
                assert.same({}, data.rewardLinks)
                assert.equal(0, #data.activities[1][1].rewards)
                assert.equal(1, #data.interact.after.rewardLinks)
                local reward = data.interact.after.rewardLinks[1]
                assert.equal("9001", reward.itemDBID)
                assert.equal(210003, reward.itemID)
                assert.equal(VAULT_ITEM, reward.link[1])
                assert.equal(623, reward.item.detailedLevel[1])
                assert.equal(VAULT_ITEM, data.interact.after.exampleLinks[1][1])
            end)

            -- The guard proven red in the other direction: with no answer from
            -- the server the snapshot SAYS the wait timed out rather than
            -- looking like an empty vault, and CloseInteraction still runs.
            it("gives up after the bound, says so, and closes the interaction anyway", function()
                world.vault.answerOnInteract = nil
                assert.is_true(ns.RunCapture("vault").pending)
                assert.equal(1, world.vault.interact.onUIInteract)
                assert.equal(0, world.vault.interact.closeInteraction)

                world.runTimers(ns.VAULT_INTERACT_TIMEOUT_SECONDS + 1)

                local data = ns.db.global.captures.vault[1].data
                assert.is_true(data.interact.attempted)
                assert.is_false(data.interact.updateFired)
                assert.is_true(data.interact.timedOut)
                assert.is_nil(data.interact.after)
                assert.equal(1, world.vault.interact.closeInteraction)
            end)

            -- A second WEEKLY_REWARDS_UPDATE - the client fires it for its own
            -- reasons - must not store a second snapshot or close twice.
            it("settles once, however many updates arrive", function()
                ns.RunCapture("vault")
                world.runTimers(10)
                world.fireEvent("WEEKLY_REWARDS_UPDATE")
                world.runTimers(10)
                assert.equal(1, #ns.db.global.captures.vault)
                assert.equal(1, world.vault.interact.closeInteraction)
            end)

            it("does not ask a client that has no OnUIInteract", function()
                _G.C_WeeklyRewards.OnUIInteract = nil
                local data = ns.RunCapture("vault").snapshot.data
                assert.is_false(data.interact.attempted)
                assert.equal("this client has no C_WeeklyRewards.OnUIInteract", data.interact.reason)
                assert.equal(0, world.vault.interact.closeInteraction)
            end)
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

    -- M3-17 (WKE-574). The third capture that is not purely a read: it puts
    -- each owned upgradeable item in the open vendor window, reads the crest
    -- cost the client will only answer for the item in the window, and clears
    -- it again. Every number in `world.upgrade.items` below is a PLACEHOLDER in
    -- Blizzard's documented shape (ItemUpgradeDocumentation.lua) - no
    -- `/lootpath capture upgrade` transcript exists yet, and the owner's first
    -- run at a vendor is what settles the real one. What these tests pin is the
    -- SHAPE of the walk: every candidate asked about, the window set and
    -- cleared once per item, the wait recorded rather than assumed, and nothing
    -- that could spend a crest ever reached for.
    describe("upgrade", function()
        -- The documented ItemUpgradeItemInfo shape, one upgrade level deep.
        local function upgradeInfo(name, currUpgrade, maxUpgrade, currencyID, cost)
            return {
                iconID = 100001,
                name = name,
                itemUpgradeable = true,
                displayQuality = 4,
                highWatermarkSlot = 1,
                currUpgrade = currUpgrade,
                maxUpgrade = maxUpgrade,
                minItemLevel = 600,
                maxItemLevel = 639,
                upgradeLevelInfos = {
                    {
                        upgradeLevel = currUpgrade + 1,
                        displayQuality = 4,
                        itemLevelIncrement = 3,
                        levelStats = {},
                        currencyCostsToUpgrade = {
                            {
                                cost = cost,
                                currencyID = currencyID,
                                discountInfo = {
                                    isDiscounted = false,
                                    discountHighWatermark = 0,
                                    isPartialTwoHandDiscount = false,
                                    isAccountWideDiscount = false,
                                    doesCurrentCharacterMeetHighWatermark = false,
                                },
                            },
                        },
                        itemCostsToUpgrade = {},
                    },
                },
                upgradeCostTypesForSeason = { { currencyID = currencyID, orderIndex = 1 } },
            }
        end

        before_each(function()
            world.upgrade.frameOpen = true
            world.equipped[1] = { link = HELM, id = 210001 }
            world.bags[0] = {
                numSlots = 4,
                items = { [3] = { link = RING, id = 210002 } },
            }
            world.upgrade.items[HELM] = {
                canUpgrade = true,
                info = upgradeInfo("Test Helm", 4, 8, 900001, 15),
                currentLevel = { 610, false },
                highWatermark = { 610, 616 },
            }
            world.upgrade.items[RING] = {
                canUpgrade = true,
                info = upgradeInfo("Test Ring", 2, 8, 900002, 10),
                currentLevel = { 600, false },
                highWatermark = { 600, 606 },
            }
        end)

        it("refuses when the upgrade window is not open", function()
            world.upgrade.frameOpen = false
            local result = ns.RunCapture("upgrade")
            assert.is_false(result.ok)
            assert.equal("capture 'upgrade' needs the upgrade window open - open the crest vendor first", result.reason)
            -- Nothing was set, nothing was cleared, nothing was asked about.
            assert.same({ set = 0, clear = 0, canUpgrade = 0 }, world.upgrade.calls)
            assert.is_nil(ns.db.global.captures.upgrade)
        end)

        it("refuses in combat", function()
            world.inCombat = true
            local result = ns.RunCapture("upgrade")
            assert.is_false(result.ok)
            assert.equal("combat", result.reason)
            assert.equal(0, world.upgrade.calls.set)
        end)

        it("refuses a client with no C_ItemUpgrade", function()
            _G.C_ItemUpgrade = nil
            local result = ns.RunCapture("upgrade")
            assert.is_false(result.ok)
            assert.equal("capture 'upgrade' needs C_ItemUpgrade; this client has none", result.reason)
        end)

        it("sets each owned item in turn, reads the cost the window answers, and clears it", function()
            local result = ns.RunCapture("upgrade")
            -- Nothing is stored until the client has answered for every item.
            assert.is_true(result.pending)
            assert.is_nil(ns.db.global.captures.upgrade)

            world.runTimers(10)

            local data = ns.db.global.captures.upgrade[1].data
            assert.equal(2, data.candidateCount)
            assert.equal(2, #data.items)
            -- Equipped first, then the bags, which is the order Blizzard's own
            -- upgrade flyout collects them in.
            assert.same({ HELM, RING }, world.upgrade.setLinks)

            local helm = data.items[1]
            assert.equal("equipped", helm.source)
            assert.equal(1, helm.invSlot)
            assert.equal(HELM, helm.link)
            assert.equal(ns.ItemKey(210001, { 1, 2 }), helm.key)
            assert.equal(210001, helm.itemID)
            assert.is_true(helm.canUpgrade[1])
            assert.is_true(helm.eventFired)
            assert.is_false(helm.timedOut)
            assert.is_number(helm.waitedMs)
            -- The cost table exactly as the client returned it.
            local level = helm.info[1].upgradeLevelInfos[1]
            assert.equal(5, level.upgradeLevel)
            assert.equal(900001, level.currencyCostsToUpgrade[1].currencyID)
            assert.equal(15, level.currencyCostsToUpgrade[1].cost)
            assert.is_false(level.currencyCostsToUpgrade[1].discountInfo.isDiscounted)
            assert.equal(4, helm.info[1].currUpgrade)
            assert.equal(8, helm.info[1].maxUpgrade)
            assert.equal(610, helm.currentLevel[1])
            assert.is_false(helm.currentLevel[2])
            assert.equal(610, helm.highWatermark[1])
            assert.equal(616, helm.highWatermark[2])
            -- Which item the window believed it was showing when it was read.
            assert.equal(HELM, helm.hyperlink[1])

            local ring = data.items[2]
            assert.equal("bag", ring.source)
            assert.equal(0, ring.bag)
            assert.equal(3, ring.slotIndex)
            assert.equal(RING, ring.hyperlink[1])
            assert.equal(900002, ring.info[1].upgradeLevelInfos[1].currencyCostsToUpgrade[1].currencyID)

            -- Two items set, and the window cleared after each one plus once
            -- more at the end, so nothing of the capture's is left in it.
            assert.equal(2, world.upgrade.calls.set)
            assert.equal(3, world.upgrade.calls.clear)
            assert.is_nil(world.upgrade.current)
        end)

        -- The guard proven red in the other direction: a client that never
        -- fires ITEM_UPGRADE_MASTER_SET_ITEM must produce a transcript that
        -- SAYS the wait timed out, rather than one that looks like a fast
        -- answer, and the window is still cleared.
        it("gives up after the bound per item, says so, and clears the window anyway", function()
            world.upgrade.answersWithEvent = false
            assert.is_true(ns.RunCapture("upgrade").pending)
            world.runTimers(2 * ns.UPGRADE_SET_TIMEOUT_SECONDS + 1)

            local data = ns.db.global.captures.upgrade[1].data
            assert.equal(2, #data.items)
            for _, item in ipairs(data.items) do
                assert.is_false(item.eventFired)
                assert.is_true(item.timedOut)
                -- It reads anyway: a timed-out wait is a suspect read, not a
                -- missing one, and the hyperlink beside it says which.
                assert.is_table(item.info)
            end
            assert.equal(ns.UPGRADE_SET_TIMEOUT_SECONDS, data.timeoutSeconds)
            assert.equal(3, world.upgrade.calls.clear)
        end)

        it("settles one item once, however many events arrive", function()
            ns.RunCapture("upgrade")
            world.runTimers(10)
            world.fireEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
            world.runTimers(10)
            assert.equal(1, #ns.db.global.captures.upgrade)
            assert.equal(2, world.upgrade.calls.set)
        end)

        it("records an item the vendor refuses and never puts it in the window", function()
            world.upgrade.items[RING].canUpgrade = false
            ns.RunCapture("upgrade")
            world.runTimers(10)

            local data = ns.db.global.captures.upgrade[1].data
            local ring = data.items[2]
            assert.equal(RING, ring.link)
            assert.is_false(ring.canUpgrade[1])
            assert.is_nil(ring.info)
            assert.is_nil(ring.hyperlink)
            assert.is_nil(ring.eventFired)
            assert.same({ HELM }, world.upgrade.setLinks)
        end)

        it("records a client that errors on one item and walks on to the next", function()
            world.upgrade.errorOnSet = HELM
            ns.RunCapture("upgrade")
            world.runTimers(10)

            local data = ns.db.global.captures.upgrade[1].data
            assert.is_string(data.items[1].set.error)
            assert.is_false(data.items[1].eventFired)
            assert.equal(RING, data.items[2].hyperlink[1])
        end)

        it("records what was in the window when it began and does not put it back", function()
            world.upgrade.current = VAULT_ITEM
            ns.RunCapture("upgrade")
            world.runTimers(10)

            local data = ns.db.global.captures.upgrade[1].data
            assert.equal(VAULT_ITEM, data.itemInWindowAtStart[1])
            assert.is_true(data.frameShown[1])
            -- Cleared, not restored: putting an item the owner did not choose
            -- into the window would be a change this capture does not make.
            assert.is_nil(world.upgrade.current)
        end)

        it("names every C_ItemUpgrade function it may call, and never the one that spends crests", function()
            ns.RunCapture("upgrade")
            world.runTimers(10)
            local names = ns.db.global.captures.upgrade[1].data.functionNames
            assert.same({
                "CanUpgradeItem",
                "ClearItemUpgrade",
                "GetHighWatermarkForItem",
                "GetItemHyperlink",
                "GetItemUpgradeCurrentLevel",
                "GetItemUpgradeItemInfo",
                "SetItemUpgradeFromLocation",
            }, names)
            for _, name in ipairs(names) do
                assert.not_equal("UpgradeItem", name)
                assert.not_equal("SetItemUpgradeFromCursorItem", name)
                assert.not_equal("CloseItemUpgrade", name)
            end
        end)

        -- The source assertion the issue asks for. A name that is never called
        -- is one thing; a file that cannot contain the call is another, and
        -- this is the one that survives a later edit.
        it("has no call in its source that could spend a crest or close the window", function()
            local source = assert(io.open("Lootpath/Captures.lua")):read("*a")
            assert.is_nil(source:find("C_ItemUpgrade.UpgradeItem", 1, true))
            assert.is_nil(source:find("U.UpgradeItem", 1, true))
            assert.is_nil(source:find("SetItemUpgradeFromCursorItem(", 1, true))
            assert.is_nil(source:find("CloseItemUpgrade(", 1, true))
            -- And the stub has no such function either, so a call that went
            -- looking for one would fail rather than silently pass.
            assert.is_nil(_G.C_ItemUpgrade.UpgradeItem)
            assert.is_nil(_G.C_ItemUpgrade.CloseItemUpgrade)
            assert.is_nil(_G.C_ItemUpgrade.SetItemUpgradeFromCursorItem)
        end)
    end)
end)
