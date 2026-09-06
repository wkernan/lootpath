-- spec/journal_spec.lua (M3-1, WKE-522 - PR 1)
--
-- What these tests can and cannot prove. The Encounter Journal has no headless
-- implementation (wowless lists all 57 EJ functions; its loot functions return
-- nothing), so every value here is a placeholder shaped by the stub, and NONE
-- of it is evidence about the client. What is proven is the adapter's
-- behaviour around the client: that it probes rather than assumes, that a
-- missing function is a finding and not a crash, that a secret is masked and
-- counted, that the walk waits for EJ_LOOT_DATA_RECIEVED and gives up on a
-- bound, that combat stops it, and that it puts the journal's view state back.
--
-- The real return shapes arrive with WKE-523's transcript, and the aggregator
-- (ns.Journal) is written against that transcript in PR 2.
local H = require("spec.helpers.addon")

-- Item links shaped like the client's (transcript 2026-09-05: itemID at field
-- 1 after `item:`, bonus-ID count at field 13). Placeholder items.
local HELM = "|cnIQ4:|Hitem:220001::::::::90:105::23:2:1808:1:28:2462:::::|h[Test Journal Helm]|h|r"
local RING = "|cnIQ4:|Hitem:220002::::::::90:105::23:1:1808:1:28:2462:::::|h[Test Journal Ring]|h|r"
local CLOAK = "|cnIQ4:|Hitem:220003::::::::90:105::23:1:1808:1:28:2462:::::|h[Test Raid Cloak]|h|r"

local DUNGEON_HEROIC = 2
local DUNGEON_CHALLENGE = 8
local DUNGEON_MYTHIC = 23
local RAID_HEROIC = 15
local RAID_MYTHIC = 16

local function registerItem(world, link, itemID, level, equipLoc)
    world.items[link] = {
        level = level,
        detailed = { level, false, level - 30, n = 3 },
        instant = { itemID, "Armor", "Cloth", equipLoc, 134132, 4, 1, n = 7 },
    }
end

-- One season pool, one raid, three loot rows. Map 2001 resolves through
-- C_EncounterJournal.GetInstanceForGameMap, 2002 only through the global
-- EJ_GetInstanceForMap, and 2003 through neither - the three outcomes WKE-523
-- has to tell apart on the real client.
local function seedJournal(world)
    local J = world.journal
    J.mapTable = { 501, 502, 503 }
    J.mapUIInfo = {
        [501] = { "Test Dungeon One", 501, 1800, 111, 112, 2001 },
        [502] = { "Test Dungeon Two", 502, 1800, 121, 122, 2002 },
        [503] = { "Unmapped Dungeon", 503, 1800, 131, 132, 2003 },
    }
    J.instanceForGameMap = { [2001] = 1201 }
    J.instanceForMap = { [2002] = 1202 }
    J.instances.dungeons = {
        { instanceID = 1201, name = "Test Dungeon One", description = "one", mapID = 2001 },
        { instanceID = 1202, name = "Test Dungeon Two", description = "two", mapID = 2002 },
    }
    J.instances.raids = {
        { instanceID = 1300, name = "Test Raid", description = "raid", mapID = 2100 },
    }
    J.encounters = {
        [1201] = {
            { name = "First Boss", description = "d", encounterID = 3001 },
            { name = "Second Boss", description = "d", encounterID = 3002 },
        },
        [1202] = { { name = "Third Boss", description = "d", encounterID = 3003 } },
        [1300] = { { name = "Raid Boss", description = "d", encounterID = 3100 } },
    }
    -- EncounterJournalItemInfo as Blizzard's docs describe it: no item level.
    local helmRow = { itemID = 220001, encounterID = 3001, name = "Test Journal Helm", slot = "Head", link = HELM }
    local ringRow = { itemID = 220002, encounterID = 3002, name = "Test Journal Ring", slot = "Finger", link = RING }
    local cloakRow = { itemID = 220003, encounterID = 3100, name = "Test Raid Cloak", slot = "Back", link = CLOAK }
    J.loot = {
        [1201] = {
            [DUNGEON_HEROIC] = { helmRow },
            [DUNGEON_MYTHIC] = { helmRow, ringRow },
            [DUNGEON_CHALLENGE] = { helmRow, ringRow },
        },
        [1202] = { [DUNGEON_MYTHIC] = { ringRow } },
        [1300] = { [RAID_HEROIC] = { cloakRow }, [RAID_MYTHIC] = { cloakRow } },
    }
    registerItem(world, HELM, 220001, 639, "INVTYPE_HEAD")
    registerItem(world, RING, 220002, 626, "INVTYPE_FINGER")
    registerItem(world, CLOAK, 220003, 645, "INVTYPE_CLOAK")
    return J
end

describe("JournalAdapter", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        seedJournal(world)
    end)

    after_each(function()
        H.unload()
    end)

    describe("Availability", function()
        it("names every journal function it will call", function()
            local availability = ns.JournalAdapter.Availability()
            assert.is_true(availability.ok)
            assert.same({}, availability.missing)
            local present = table.concat(availability.present, " ")
            assert.truthy(present:find("EJ_SetLootFilter", 1, true))
            assert.truthy(present:find("C_EncounterJournal.GetLootInfoByIndex", 1, true))
            assert.truthy(present:find("C_ChallengeMode.GetMapTable", 1, true))
        end)

        it("reports a function this client does not have instead of crashing", function()
            _G.C_EncounterJournal.GetInstanceForGameMap = nil
            _G.EJ_SetLootFilter = nil
            local availability = ns.JournalAdapter.Availability()
            assert.is_false(availability.ok)
            assert.same({ "C_EncounterJournal.GetInstanceForGameMap", "EJ_SetLootFilter" }, availability.missing)
        end)
    end)

    describe("Call", function()
        it("keeps the client's returns positional, holes included", function()
            local packed = ns.JournalAdapter.Call(function()
                return 1, nil, 3
            end)
            assert.equal(3, packed.n)
            assert.equal(1, packed[1])
            assert.is_nil(packed[2])
            assert.equal(3, packed[3])
        end)

        it("records an absent function and an erroring one", function()
            assert.is_true(ns.JournalAdapter.Call(nil).absent)
            local errored = ns.JournalAdapter.Call(function()
                error("journal exploded")
            end)
            assert.truthy(errored.error:find("journal exploded", 1, true))
        end)

        it("masks a secret value and counts it", function()
            ns.JournalAdapter.secretsSeen = 0
            local packed = ns.JournalAdapter.Call(function()
                return world.secret("loot")
            end)
            assert.equal(ns.MARKERS.secret, packed[1])
            assert.equal(1, ns.JournalAdapter.secretsSeen)
        end)

        it("masks a secret table inside a returned table and counts it", function()
            ns.JournalAdapter.secretsSeen = 0
            local packed = ns.JournalAdapter.Call(function()
                return { itemID = 1, hidden = world.secretTable("rows") }
            end)
            assert.equal(1, packed[1].itemID)
            assert.equal(ns.MARKERS.secretTable, packed[1].hidden)
            assert.equal(1, ns.JournalAdapter.secretsSeen)
        end)
    end)

    describe("DifficultyID", function()
        it("prefers the client's own DifficultyUtil.ID", function()
            _G.DifficultyUtil.ID.DungeonChallenge = 99
            assert.equal(99, ns.JournalAdapter.DifficultyID("DungeonChallenge"))
        end)

        it("falls back to the values read from Blizzard's DifficultyUtil.lua", function()
            _G.DifficultyUtil = nil
            assert.equal(DUNGEON_HEROIC, ns.JournalAdapter.DifficultyID("DungeonHeroic"))
            assert.equal(DUNGEON_CHALLENGE, ns.JournalAdapter.DifficultyID("DungeonChallenge"))
            assert.equal(DUNGEON_MYTHIC, ns.JournalAdapter.DifficultyID("DungeonMythic"))
            assert.equal(RAID_MYTHIC, ns.JournalAdapter.DifficultyID("PrimaryRaidMythic"))
        end)
    end)

    describe("MythicPlusPool", function()
        it("records both map-to-instance lookups for every map in the pool", function()
            local pool = ns.JournalAdapter.MythicPlusPool()
            assert.equal(3, #pool.maps)
            local one = pool.maps[1]
            assert.equal(501, one.mapChallengeModeID)
            assert.equal("Test Dungeon One", one.mapName)
            assert.equal(2001, one.mapID)
            assert.equal(1201, one.instanceForGameMap[1])
            assert.is_nil(one.instanceForMap[1])
            local two = pool.maps[2]
            assert.is_nil(two.instanceForGameMap[1])
            assert.equal(1202, two.instanceForMap[1])
            local three = pool.maps[3]
            assert.is_nil(three.instanceForGameMap[1])
            assert.is_nil(three.instanceForMap[1])
        end)
    end)

    describe("BuildTargets", function()
        local plan

        before_each(function()
            plan = ns.JournalAdapter.DefaultTargets()
        end)

        it("takes the instance from whichever lookup answered, and says which", function()
            local pool = ns.JournalAdapter.MythicPlusPool()
            local targets = ns.JournalAdapter.BuildTargets(pool, {}, plan, 10)
            assert.equal(6, #targets) -- two resolved dungeons x three difficulties
            assert.equal("C_EncounterJournal.GetInstanceForGameMap", pool.maps[1].resolvedBy)
            assert.equal("EJ_GetInstanceForMap", pool.maps[2].resolvedBy)
            assert.equal(1201, targets[1].instanceID)
            assert.equal(DUNGEON_HEROIC, targets[1].difficultyID)
            assert.equal(DUNGEON_MYTHIC, targets[2].difficultyID)
            assert.equal(DUNGEON_CHALLENGE, targets[3].difficultyID)
            assert.equal(10, targets[3].previewLevel)
            assert.is_nil(targets[1].previewLevel)
            assert.is_false(targets[1].isRaid)
        end)

        it("reports a map neither lookup resolved instead of dropping it", function()
            local pool = ns.JournalAdapter.MythicPlusPool()
            local _, unresolved = ns.JournalAdapter.BuildTargets(pool, {}, plan, 10)
            assert.equal(1, #unresolved)
            assert.equal(503, unresolved[1].mapChallengeModeID)
            assert.equal("Unmapped Dungeon", unresolved[1].mapName)
            assert.equal(2003, unresolved[1].mapID)
        end)

        it("adds the raid at the raid difficulties, with no preview level", function()
            local pool = { maps = {} }
            local raids = ns.JournalAdapter.Instances(true)
            local targets = ns.JournalAdapter.BuildTargets(pool, raids, plan, 10)
            assert.equal(2, #targets)
            assert.is_true(targets[1].isRaid)
            assert.equal(1300, targets[1].instanceID)
            assert.equal(RAID_HEROIC, targets[1].difficultyID)
            assert.equal(RAID_MYTHIC, targets[2].difficultyID)
            assert.is_nil(targets[1].previewLevel)
        end)
    end)

    describe("LootRows", function()
        it("takes the item level from the link, because the loot row has none", function()
            _G.EJ_SelectInstance(1201)
            _G.EJ_SetDifficulty(DUNGEON_MYTHIC)
            local read = ns.JournalAdapter.LootRows()
            assert.equal(2, read.numLoot[1])
            local first = read.rows[1]
            assert.equal(220001, first.itemInfo[1].itemID)
            assert.is_nil(first.itemInfo[1].itemLevel)
            assert.equal(639, first.detailedLevel[1])
            assert.equal("INVTYPE_HEAD", first.instant[4])
            assert.equal(626, read.rows[2].detailedLevel[1])
        end)
    end)

    describe("view state", function()
        it("puts the tier, difficulty and loot filter back", function()
            world.journal.currentTier = 2
            world.journal.difficulty = DUNGEON_HEROIC
            world.journal.lootFilter = { 7, 262 }
            local before = ns.JournalAdapter.ViewState()

            ns.JournalAdapter.SelectTier(3)
            ns.JournalAdapter.SetDifficulty(RAID_MYTHIC)
            ns.JournalAdapter.SetLootFilter(11, 105)
            assert.equal(3, world.journal.currentTier)

            ns.JournalAdapter.RestoreViewState(before)
            assert.equal(2, world.journal.currentTier)
            assert.equal(DUNGEON_HEROIC, world.journal.difficulty)
            assert.same({ 7, 262 }, world.journal.lootFilter)
        end)

        it("resets the loot filter when the client never had one", function()
            world.journal.lootFilter = { nil, nil }
            local before = ns.JournalAdapter.ViewState()
            ns.JournalAdapter.SetLootFilter(11, 105)
            ns.JournalAdapter.RestoreViewState(before)
            assert.same({ 0, 0 }, world.journal.lootFilter)
        end)
    end)
end)

describe("JournalAdapter.Walk", function()
    local ns, world

    local function targets()
        return {
            { instanceID = 1201, instanceName = "Test Dungeon One", isRaid = false, difficultyID = DUNGEON_HEROIC },
            { instanceID = 1201, instanceName = "Test Dungeon One", isRaid = false, difficultyID = DUNGEON_MYTHIC },
            { instanceID = 1300, instanceName = "Test Raid", isRaid = true, difficultyID = RAID_HEROIC },
        }
    end

    local function walk(opts)
        local done
        ns.JournalAdapter.Walk(opts, function(result)
            done = result
        end)
        world.runTimers(120)
        return done
    end

    before_each(function()
        ns, world = H.load()
        seedJournal(world)
    end)

    after_each(function()
        H.unload()
    end)

    it("reads every target when the loot list is ready immediately", function()
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        assert.equal(3, #result.targets)
        assert.equal(1, result.targets[1].loot.numLoot[1])
        assert.equal(2, result.targets[2].loot.numLoot[1])
        assert.equal(220003, result.targets[3].loot.rows[1].itemInfo[1].itemID)
        assert.equal(0, result.waits)
        assert.equal(0, result.timeouts)
        assert.is_false(result.abortedInCombat)
        assert.is_number(result.durationMs)
    end)

    it("applies the loot filter and the M+ preview level per target", function()
        local list = targets()
        list[2].previewLevel = 12
        walk({ targets = list, classID = 11, specID = 105 })
        assert.same({ 12 }, world.journal.previewLevelCalls)
    end)

    it("records the encounters of each target's instance", function()
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        assert.equal(2, #result.targets[1].encounters)
        assert.equal("First Boss", result.targets[1].encounters[1].name)
        assert.equal(3002, result.targets[1].encounters[2].encounterID)
    end)

    it("waits for EJ_LOOT_DATA_RECIEVED and re-reads, counting the events", function()
        world.journal.lootDelaySeconds = 0.5
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        assert.equal(3, result.lootEvents)
        assert.is_true(result.waits > 0)
        assert.equal(1, result.targets[1].loot.numLoot[1])
        assert.equal(2, result.targets[2].loot.numLoot[1])
        assert.is_false(result.targets[1].stillOutOfDate)
        assert.equal(220001, result.lootEventItemIDs[1])
    end)

    it("gives up on a bound when the event never comes, and says so", function()
        world.journal.lootDelaySeconds = false
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        assert.equal(0, result.lootEvents)
        assert.equal(3, #result.targets)
        for _, record in ipairs(result.targets) do
            assert.equal(ns.JournalAdapter.LOOT_MAX_ATTEMPTS, record.attempts)
            assert.is_true(record.stillOutOfDate)
        end
        assert.equal(3 * (ns.JournalAdapter.LOOT_MAX_ATTEMPTS - 1), result.timeouts)
    end)

    it("abandons the walk when combat starts and never reads another target", function()
        -- Combat lands while the first target's loot is being read, so the
        -- check at the top of the next target is what has to stop the walk.
        local realGetLootInfo = _G.C_EncounterJournal.GetLootInfoByIndex
        _G.C_EncounterJournal.GetLootInfoByIndex = function(index)
            world.inCombat = true
            return realGetLootInfo(index)
        end
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        assert.is_true(result.abortedInCombat)
        assert.equal(2, result.abortedAtTarget)
        assert.equal(1, #result.targets)
    end)

    it("restores the journal's view state when it finishes", function()
        world.journal.currentTier = 2
        world.journal.difficulty = DUNGEON_HEROIC
        world.journal.lootFilter = { 7, 262 }
        local before = ns.JournalAdapter.ViewState()
        walk({ targets = targets(), classID = 11, specID = 105, viewState = before })
        assert.equal(2, world.journal.currentTier)
        assert.equal(DUNGEON_HEROIC, world.journal.difficulty)
        assert.same({ 7, 262 }, world.journal.lootFilter)
    end)

    it("restores the view state even when combat cuts it short", function()
        world.journal.lootFilter = { 7, 262 }
        local before = ns.JournalAdapter.ViewState()
        world.inCombat = true
        local result = walk({ targets = targets(), classID = 11, specID = 105, viewState = before })
        assert.is_true(result.abortedInCombat)
        assert.same({ 7, 262 }, world.journal.lootFilter)
    end)

    it("stops listening for loot events once it is done", function()
        walk({ targets = targets(), classID = 11, specID = 105 })
        assert.is_nil(ns.JournalAdapter.onLootData)
    end)
end)

describe("capture journal", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        seedJournal(world)
    end)

    after_each(function()
        H.unload()
    end)

    local function run(args)
        local final
        local immediate = ns.RunCapture("journal", function(result)
            final = result
        end, args)
        world.runTimers(120)
        return final, immediate
    end

    it("is registered last, after env, inventory and vault", function()
        assert.same({ "env", "inventory", "vault", "journal" }, ns.captureOrder)
        assert.is_true(ns.captures.journal.async)
    end)

    it("reports itself pending and stores the snapshot when the walk finishes", function()
        local final, immediate = run()
        assert.is_true(immediate.pending)
        assert.is_true(final.ok)
        local snapshot = ns.db.global.captures.journal[1]
        assert.equal(final.snapshot, snapshot)
        assert.equal("journal", snapshot.name)
        assert.is_false(snapshot.sawSecret)
        assert.equal(120100, snapshot.build[4])
    end)

    it("dumps the season, the pool, both map lookups and the unresolved maps", function()
        local data = run().snapshot.data
        assert.equal(15, data.season.currentSeason[1])
        assert.equal(3, #data.pool.maps)
        assert.equal(1201, data.pool.maps[1].instanceForGameMap[1])
        assert.equal("EJ_GetInstanceForMap", data.pool.maps[2].resolvedBy)
        assert.equal(1, #data.unresolvedMaps)
        assert.equal(503, data.unresolvedMaps[1].mapChallengeModeID)
    end)

    it("walks the resolved dungeons and the raid, with the player's class and spec", function()
        local data = run().snapshot.data
        assert.equal(11, data.requested.classID)
        assert.equal(105, data.requested.specID)
        -- two resolved dungeons x three difficulties, plus one raid x two
        assert.equal(8, data.requested.targetCount)
        assert.equal(8, #data.walk.targets)
        -- EJ_SetLootFilter takes a classID and a specID, once per target, and
        -- once more at the end to put the player's own filter back.
        assert.equal(9, #world.journal.lootFilterCalls)
        assert.same({ 11, 105 }, world.journal.lootFilterCalls[1])
        assert.same({ 11, 105 }, world.journal.lootFilterCalls[8])
        assert.same({ 0, 0 }, world.journal.lootFilterCalls[9])
        local raidTargets = 0
        for _, target in ipairs(data.walk.targets) do
            if target.isRaid then
                raidTargets = raidTargets + 1
            end
        end
        assert.equal(2, raidTargets)
    end)

    it("carries the item level and equip location the loot rows do not", function()
        local data = run().snapshot.data
        local mythic
        for _, target in ipairs(data.walk.targets) do
            if target.instanceID == 1201 and target.difficultyID == DUNGEON_MYTHIC then
                mythic = target
            end
        end
        assert.is_table(mythic)
        assert.equal(639, mythic.loot.rows[1].detailedLevel[1])
        assert.equal("INVTYPE_HEAD", mythic.loot.rows[1].instant[4])
        assert.equal("Head", mythic.loot.rows[1].itemInfo[1].slot)
    end)

    it("records how many loot events fired and how long the walk took", function()
        world.journal.lootDelaySeconds = 0.5
        local data = run().snapshot.data
        assert.equal(8, data.walk.lootEvents)
        assert.is_true(data.walk.waits > 0)
        assert.is_number(data.walk.durationMs)
        assert.is_number(ns.db.global.captures.journal[1].durationMs)
    end)

    it("takes the M+ preview level from the command, defaulting to the module's", function()
        run()
        assert.same({
            ns.JournalAdapter.DEFAULT_PREVIEW_MYTHIC_PLUS_LEVEL,
            ns.JournalAdapter.DEFAULT_PREVIEW_MYTHIC_PLUS_LEVEL,
        }, world.journal.previewLevelCalls)

        world.journal.previewLevelCalls = {}
        local data = run("14").snapshot.data
        assert.equal(14, data.requested.previewMythicPlusLevel)
        assert.same({ 14, 14 }, world.journal.previewLevelCalls)
    end)

    it("records a journal function this client does not have", function()
        _G.C_EncounterJournal.SetPreviewMythicPlusLevel = nil
        local data = run().snapshot.data
        assert.is_false(data.availability.ok)
        assert.same({ "C_EncounterJournal.SetPreviewMythicPlusLevel" }, data.availability.missing)
    end)

    it("masks and flags a secret the journal hands back", function()
        local realGetLootInfo = _G.C_EncounterJournal.GetLootInfoByIndex
        _G.C_EncounterJournal.GetLootInfoByIndex = function(index)
            local row = realGetLootInfo(index)
            if row then
                row.name = world.secret("loot name")
            end
            return row
        end
        local snapshot = run().snapshot
        -- The adapter masks at the boundary, so by the time the snapshot is
        -- copied there is no secret left to see: what survives is the marker
        -- and the count. A secret never reaches SavedVariables either way.
        assert.is_false(snapshot.sawSecret)
        assert.is_true(snapshot.data.walk.secretsSeen > 0)
        local firstRow = snapshot.data.walk.targets[1].loot.rows[1]
        assert.equal(ns.MARKERS.secret, firstRow.itemInfo[1].name)
        assert.equal(220001, firstRow.itemInfo[1].itemID)
    end)

    it("refuses in combat and stores nothing", function()
        world.inCombat = true
        local final = run()
        assert.same({ ok = false, reason = "combat" }, final)
        assert.is_nil(ns.db.global.captures.journal)
    end)

    it("puts the journal's view state back", function()
        world.journal.currentTier = 2
        world.journal.difficulty = DUNGEON_HEROIC
        world.journal.lootFilter = { 7, 262 }
        local data = run().snapshot.data
        assert.equal(2, data.viewStateBefore.tier[1])
        assert.equal(2, world.journal.currentTier)
        assert.equal(DUNGEON_HEROIC, world.journal.difficulty)
        assert.same({ 7, 262 }, world.journal.lootFilter)
    end)
end)
