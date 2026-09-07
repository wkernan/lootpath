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
local R = require("spec.helpers.replay")
local S = require("spec.helpers.serialize")
local Stub = require("spec.stubs.wow")

local EXPECTED_DIR = "spec/fixtures/expected/"

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

-- ---------------------------------------------------------------------------
-- The second read (WKE-522 PR 2). The 2026-09-06 transcript found that a loot
-- row can arrive carrying only itemID, encounterID and the displayAs* flags
-- while EJ_IsLootListOutOfDate is false, so the list-level gate says nothing
-- about it. These tests drive the stub's second stage - rows come back bare
-- and EJ_LOOT_DATA_RECIEVED lands afterwards - and prove the walk re-reads.
describe("JournalAdapter.Walk second read", function()
    local ns, world

    local function targets()
        return {
            { instanceID = 1201, instanceName = "Test Dungeon One", isRaid = false, difficultyID = DUNGEON_MYTHIC },
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

    it("counts a row with no name and no link as pending, the way Blizzard's loot button does", function()
        local bare = { itemInfo = { { itemID = 220001, encounterID = 3001 }, n = 1 } }
        local whole = { itemInfo = { { itemID = 220001, name = "Test Journal Helm", link = HELM }, n = 1 } }
        assert.is_true(ns.JournalAdapter.RowIsPending(bare))
        assert.is_false(ns.JournalAdapter.RowIsPending(whole))
        assert.is_true(ns.JournalAdapter.RowIsPending({ itemInfo = { n = 0 } }))
        assert.is_true(ns.JournalAdapter.RowIsPending(nil))
    end)

    it("re-reads the whole list after the item data lands, keeping both reads", function()
        world.journal.itemDataDelaySeconds = 0.5
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        local record = result.targets[1]

        -- First read: the bare shape, exactly what the transcript recorded.
        assert.equal(2, record.pendingRows)
        assert.is_nil(record.loot.rows[1].itemInfo[1].link)
        assert.equal(220001, record.loot.rows[1].itemInfo[1].itemID)
        -- Second read: the same rows, filled in.
        assert.is_table(record.reread)
        assert.equal(0, record.rereadPendingRows)
        assert.equal(HELM, record.reread.rows[1].itemInfo[1].link)
        assert.equal(639, record.reread.rows[1].detailedLevel[1])
        assert.equal("INVTYPE_HEAD", record.reread.rows[1].instant[4])

        assert.equal(2, result.pendingRowsFirstRead)
        assert.equal(0, result.pendingRowsFinalRead)
        assert.equal(2, result.rowsFilledByReread)
        assert.is_true(result.rereads > 0)
        assert.is_number(record.itemDataWaitedMs)
    end)

    it("does not re-read a target whose rows arrived whole", function()
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        assert.equal(0, result.targets[1].pendingRows)
        assert.is_nil(result.targets[1].reread)
        assert.equal(0, result.rereads)
        assert.equal(0, result.rowsFilledByReread)
    end)

    it("gives up on a bound when the item data never arrives, and says so", function()
        world.journal.itemDataDelaySeconds = false
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        local record = result.targets[1]
        assert.equal(ns.JournalAdapter.ITEM_DATA_MAX_ATTEMPTS, record.rereads)
        assert.equal(ns.JournalAdapter.ITEM_DATA_MAX_ATTEMPTS, record.itemDataTimeouts)
        assert.equal(2, record.rereadPendingRows)
        assert.equal(2, result.pendingRowsFinalRead)
        assert.equal(0, result.rowsFilledByReread)
        -- Bounded, not hung: the walk still finished and put the view back.
        assert.is_false(result.abortedInCombat)
        assert.is_table(result.restored)
    end)

    it("names each row's boss the way Blizzard's loot button does", function()
        local result = walk({ targets = targets(), classID = 11, specID = 105 })
        local names = result.targets[1].encounterNames
        assert.equal("First Boss", names[3001][1])
        assert.equal("Second Boss", names[3002][1])
    end)
end)

-- ---------------------------------------------------------------------------
-- The aggregator, over the real transcript (WKE-523's first visit, PR #10):
-- hotornot in Restoration spec 105, 30 targets, 613 loot rows, 369 of them
-- link-less. Every number asserted below was read out of that file.
describe("ns.Journal over the 2026-09-06 transcript", function()
    local ns, snapshot, sources, summary

    before_each(function()
        ns = H.load()
        snapshot = R.snapshot("journal", 1, R.JOURNAL)
        sources, summary = ns.Journal:Build({ snapshot = snapshot })
    end)

    after_each(function()
        H.unload()
    end)

    -- What the raw snapshot says, counted here rather than taken from the
    -- module, so the assertions below are checked against the transcript.
    local function rawRows()
        local rows = {}
        for _, target in ipairs(snapshot.data.walk.targets) do
            for _, row in ipairs((target.loot and target.loot.rows) or {}) do
                rows[#rows + 1] = { target = target, row = row, info = row.itemInfo[1] }
            end
        end
        return rows
    end

    it("reads the transcript the tests claim to read", function()
        assert.equal("journal", snapshot.name)
        assert.equal(105, snapshot.data.player.specID)
        assert.equal(30, #snapshot.data.walk.targets)
        assert.equal(613, #rawRows())
    end)

    it("gives every equippable item the journal listed at least one source", function()
        local expected = {}
        for _, entry in ipairs(rawRows()) do
            local equipLoc = entry.row.instant and entry.row.instant[4]
            if ns.JournalAdapter.RowIsPending(entry.row) or ns.Inventory.SlotForEquipLoc(equipLoc) then
                expected[entry.info.itemID] = true
            end
        end
        local count = 0
        for itemID in pairs(expected) do
            count = count + 1
            assert.is_table(sources[itemID], "no source for itemID " .. itemID)
            assert.is_true(#sources[itemID] >= 1)
        end
        assert.equal(375, count)
        assert.equal(count, summary.items)
        -- and nothing invented: every itemID in the map came from a row.
        for itemID in pairs(sources) do
            assert.is_true(expected[itemID] == true)
        end
    end)

    it("speaks QE Live's slot vocabulary, from the same table Inventory reads", function()
        local vocabulary = {}
        for _, slot in pairs(ns.Inventory.SLOT_BY_EQUIPLOC) do
            vocabulary[slot] = true
        end
        local slots = {}
        for _, list in pairs(sources) do
            for _, source in ipairs(list) do
                if source.slot ~= nil then
                    assert.is_true(vocabulary[source.slot] == true, "not a QE Live slot: " .. tostring(source.slot))
                    slots[source.slot] = (slots[source.slot] or 0) + 1
                end
            end
        end
        -- The journal's own EncounterJournalItemInfo.slot is the client's
        -- localised UI text ("One-Hand", "Held In Off-hand"); the equipLoc
        -- behind it is not, and it is what the map speaks.
        assert.equal(15, slots["1H Weapon"])
        assert.equal(14, slots["2H Weapon"])
        assert.equal(11, slots["Offhand"])
        assert.equal(27, slots["Trinket"])
        assert.is_nil(slots["One-Hand"])
        assert.is_nil(slots["Held In Off-hand"])
    end)

    it("maps a dungeon item to its boss at every difficulty the walk read", function()
        -- Vile Vial of Volatile Venom, Altar of Fangs, off Rav'i.
        local list = sources[273796]
        assert.equal(3, #list)
        for _, source in ipairs(list) do
            assert.is_false(source.isRaid)
            assert.equal(1322, source.instanceID)
            assert.equal("Altar of Fangs", source.instanceName)
            assert.equal(2878, source.encounterID)
            assert.equal("Rav'i", source.encounterName)
            assert.equal("Trinket", source.slot)
            assert.is_nil(source.pending)
        end
        assert.same({ 2, 8, 23 }, { list[1].difficultyID, list[2].difficultyID, list[3].difficultyID })
        assert.same({ 276, 305, 292 }, { list[1].itemLevel, list[2].itemLevel, list[3].itemLevel })
    end)

    it("maps a raid item to its raid, flagged isRaid", function()
        -- Gebbo's Bottomless Bag, The Venomous Abyss, off The Lost Explorers.
        local list = sources[270164]
        assert.equal(2, #list)
        for _, source in ipairs(list) do
            assert.is_true(source.isRaid)
            assert.equal(1320, source.instanceID)
            assert.equal("The Venomous Abyss", source.instanceName)
            assert.equal("The Lost Explorers", source.encounterName)
            assert.equal("Trinket", source.slot)
        end
        assert.same({ 15, 16 }, { list[1].difficultyID, list[2].difficultyID })
        assert.same({ 308, 321 }, { list[1].itemLevel, list[2].itemLevel })
    end)

    it("puts dungeons before raids in an item's source list", function()
        for _, list in pairs(sources) do
            local seenRaid = false
            for _, source in ipairs(list) do
                if source.isRaid then
                    seenRaid = true
                else
                    assert.is_false(seenRaid)
                end
            end
        end
    end)

    it("never treats a link-less row as 'no item level'", function()
        assert.equal(369, summary.pendingRows)
        assert.equal(277, summary.pendingItems)
        local pendingSources = 0
        for _, list in pairs(sources) do
            for _, source in ipairs(list) do
                if source.pending then
                    pendingSources = pendingSources + 1
                    assert.is_nil(source.itemLevel)
                    assert.is_nil(source.slot)
                    -- Still a real source: the boss and the difficulty are known.
                    assert.is_number(source.encounterID)
                    assert.is_number(source.difficultyID)
                end
            end
        end
        assert.equal(369, pendingSources)
        -- Kings' Rest, off The Golden Serpent: link-less at both difficulties
        -- the walk read, so nothing about the item itself is known yet.
        local list = sources[159617]
        assert.equal(2, #list)
        assert.is_true(list[1].pending)
        assert.equal("The Golden Serpent", list[1].encounterName)
    end)

    it("drops what the journal lists but nobody can equip", function()
        assert.equal(55, summary.nonGearRows)
        assert.equal(0, summary.skippedRows)
        assert.equal(613, summary.rows)
        assert.equal(558, summary.sources)
        -- Nothing the map kept is both known and slotless.
        for itemID, list in pairs(sources) do
            for _, source in ipairs(list) do
                assert.is_true(source.pending == true or source.slot ~= nil, "slotless source for " .. itemID)
            end
        end
        -- Exactly one itemID was read whole on every row it appeared in and
        -- was not gear on any of them, so it is the only one with no source
        -- at all. A pattern (270900) and a mount (276804) survive only as
        -- pending rows elsewhere: a link-less row cannot be told from gear.
        assert.is_nil(sources[268728])
        assert.equal(1, #sources[270900])
        assert.is_true(sources[270900][1].pending)
        assert.is_true(sources[276804][1].pending)
    end)

    it("names a boss at a difficulty whose own encounter list came back empty", function()
        -- EJ_GetEncounterInfoByIndex answered nothing on every DungeonChallenge
        -- target, so 95 of the 613 rows had no boss name in their own target.
        -- A boss name is an instance-wide fact, so the Heroic read names them.
        local challenge = sources[273796][2]
        assert.equal(8, challenge.difficultyID)
        assert.equal("Rav'i", challenge.encounterName)
        for _, target in ipairs(snapshot.data.walk.targets) do
            if target.instanceID == 1322 and target.difficultyID == 8 then
                assert.equal(0, #target.encounters)
            end
        end
        -- Midnight's two targets both listed zero encounters, so its rows stay
        -- unnamed until a walk that calls EJ_GetEncounterInfo runs in game.
        assert.equal(22, summary.unnamedEncounters)
    end)

    it("prefers the second read when the walk made one", function()
        -- The committed transcript predates the second read, so every target
        -- here falls back to its first read; the aggregator says so.
        assert.equal(0, summary.rereadTargets)
        -- On a COPY: spec.helpers.replay caches the transcript, so every test in
        -- this file shares one table and a mutation here would follow the
        -- snapshot into the tests that come after it. It did: the golden this
        -- file regenerates was written from a transcript with this target's
        -- second read spliced in (588 rows instead of 613), until M3-3.
        local copy = Stub.deepcopy(snapshot)
        local target = copy.data.walk.targets[1]
        target.reread = { rows = { target.loot.rows[1] } }
        local reread, reSummary = ns.Journal:Build({ snapshot = copy, refresh = true })
        assert.equal(1, reSummary.rereadTargets)
        assert.is_true(reSummary.rows < summary.rows)
        assert.is_table(reread)
    end)

    it("carries the row's own item key and name, and neither on a pending row", function()
        -- The key M3-3 joins the map to the QE Live verdict on. Measured over
        -- this transcript: 189 keyed entries, every one of them carrying
        -- exactly ONE bonus ID, and it is 3524 on all of them - so a journal
        -- key is not the key of any copy you own, whose links carry two to
        -- seven. That is the values-free decision working, not a bug.
        local keyed, bonusIDs, pending = 0, {}, 0
        for _, list in pairs(sources) do
            for _, source in ipairs(list) do
                if source.pending then
                    pending = pending + 1
                    assert.is_nil(source.itemKey)
                    assert.is_nil(source.name)
                else
                    keyed = keyed + 1
                    assert.is_string(source.itemKey)
                    assert.is_string(source.name)
                    local id, bonus = source.itemKey:match("^(%d+):(.+)$")
                    assert.is_string(id, "a journal key with no bonus ID: " .. source.itemKey)
                    bonusIDs[bonus] = (bonusIDs[bonus] or 0) + 1
                end
            end
        end
        assert.equal(189, keyed)
        assert.equal(369, pending)
        assert.same({ ["3524"] = 189 }, bonusIDs)
        -- Item 251153 is the one itemID the committed Top Gear export and this
        -- map share: same item, three difficulties, one key, three item levels.
        local feet = sources[251153]
        assert.equal(3, #feet)
        assert.equal("Arctic Explorer's Legwraps", feet[1].name)
        for _, source in ipairs(feet) do
            assert.equal("251153:3524", source.itemKey)
        end
        assert.same({ 276, 305, 292 }, { feet[1].itemLevel, feet[2].itemLevel, feet[3].itemLevel })
        assert.is_not.equal("251153:3524", ns.ItemKey(251153, { 13440, 6652, 13662, 12699, 12835 }))
    end)

    it("records the M+ level the walk previewed, because the client has no getter for it", function()
        assert.equal(10, summary.previewMythicPlusLevel)
        local _, overridden = ns.Journal:Build({ snapshot = snapshot, refresh = true, previewMythicPlusLevel = 12 })
        assert.equal(12, overridden.previewMythicPlusLevel)
    end)

    it("matches the committed expected fixture", function()
        local expected = EXPECTED_DIR .. "journal-20260906-161213.lua"
        if os.getenv("LOOTPATH_WRITE_EXPECTED") then
            S.write(
                expected,
                { sources = sources, summary = summary },
                "-- Generated by spec/journal_spec.lua over the 2026-09-06 journal transcript.\n"
            )
        end
        assert.same(dofile(expected), { sources = sources, summary = summary })
    end)
end)

describe("ns.Journal cache", function()
    local ns, snapshot

    before_each(function()
        ns = H.load()
        snapshot = R.snapshot("journal", 1, R.JOURNAL)
    end)

    after_each(function()
        H.unload()
    end)

    it("keys on the build, the season, the spec and the difficulties", function()
        assert.equal("69587|18|105|2:8:23", ns.Journal.CacheKey(69587, 18, 105, { 23, 2, 8 }))
        assert.equal("69587|18|105|none", ns.Journal.CacheKey(69587, 18, 105, {}))
        -- the build number, not the version string: GetBuildInfo's second return
        assert.equal("69587", ns.Journal.BuildNumber(snapshot.build))
    end)

    it("stores the build it was built for under that key", function()
        local sources, summary = ns.Journal:Build({ snapshot = snapshot })
        assert.equal("69587|18|105|2:8:15:16:23", summary.cacheKey)
        assert.equal("69587", summary.build)
        assert.equal(18, summary.seasonID)
        assert.equal(105, summary.specID)
        assert.same({ 2, 8, 15, 16, 23 }, summary.difficultyIDs)
        local entry = ns.db.global.journalCache[summary.cacheKey]
        assert.equal(sources, entry.sources)
        assert.equal("69587", entry.build)
    end)

    it("answers the second Build from the cache, and rebuilds on request", function()
        local first, firstSummary, fromCache = ns.Journal:Build({ snapshot = snapshot })
        assert.is_false(fromCache)
        local second, secondSummary, cached = ns.Journal:Build({ snapshot = snapshot })
        assert.is_true(cached)
        assert.equal(first, second)
        assert.equal(firstSummary, secondSummary)
        local third, _, refreshed = ns.Journal:Build({ snapshot = snapshot, refresh = true })
        assert.is_false(refreshed)
        assert.are_not.equal(first, third)
    end)

    it("keys a difficulty subset separately", function()
        local raids, raidSummary = ns.Journal:Build({ snapshot = snapshot, difficultyIDs = { 15, 16 } })
        assert.equal("69587|18|105|15:16", raidSummary.cacheKey)
        assert.equal(6, raidSummary.targets)
        for _, list in pairs(raids) do
            for _, source in ipairs(list) do
                assert.is_true(source.isRaid)
            end
        end
    end)

    it("throws away everything the last build cached", function()
        ns.Journal:Build({ snapshot = snapshot })
        assert.is_table(ns.db.global.journalCache["69587|18|105|2:8:15:16:23"])
        assert.equal(1, ns.Journal.Invalidate(ns.db, "69999"))
        assert.same({}, ns.db.global.journalCache)

        -- and Build itself invalidates: the same walk under a newer build
        -- leaves only the new entry behind.
        ns.Journal:Build({ snapshot = snapshot })
        ns.Journal:Build({ snapshot = snapshot, build = "69999" })
        local keys = {}
        for key in pairs(ns.db.global.journalCache) do
            keys[#keys + 1] = key
        end
        assert.same({ "69999|18|105|2:8:15:16:23" }, keys)
    end)

    it("builds without a db rather than failing", function()
        local sources, summary, fromCache = ns.Journal:Build({ snapshot = snapshot, db = false })
        assert.is_false(fromCache)
        assert.is_table(sources)
        assert.is_true(summary.ok)
        assert.same({}, ns.db.global.journalCache)
    end)

    it("refuses a walk it was not given", function()
        local sources, summary = ns.Journal:Build({})
        assert.is_nil(sources)
        assert.is_false(summary.ok)
        assert.equal("no walk data", summary.reason)
    end)
end)

-- The aggregator's half of the second read: the same walk, aggregated with and
-- without the re-read the client's late EJ_LOOT_DATA_RECIEVED makes possible.
describe("ns.Journal over a walk whose item data arrives late", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        seedJournal(world)
    end)

    after_each(function()
        H.unload()
    end)

    local function walkData(delay)
        world.journal.itemDataDelaySeconds = delay
        local done
        ns.JournalAdapter.Walk({
            targets = {
                { instanceID = 1201, instanceName = "Test Dungeon One", isRaid = false, difficultyID = DUNGEON_MYTHIC },
            },
            classID = 11,
            specID = 105,
        }, function(result)
            done = result
        end)
        world.runTimers(120)
        return { walk = done, player = { specID = 105 }, season = { currentSeason = { 15, n = 1 } } }
    end

    it("knows nothing but the itemID from the first read alone", function()
        local data = walkData(0.5)
        for _, target in ipairs(data.walk.targets) do
            target.reread = nil -- what a one-pass walk would have left behind
        end
        local sources, summary = ns.Journal:Build({ data = data, build = "69587" })
        assert.equal(2, summary.pendingItems)
        assert.is_true(sources[220001][1].pending)
        assert.is_nil(sources[220001][1].itemLevel)
        assert.is_nil(sources[220001][1].slot)
    end)

    it("fills the item level and the slot from the second read", function()
        local sources, summary = ns.Journal:Build({ data = walkData(0.5), build = "69587" })
        assert.equal(0, summary.pendingItems)
        assert.equal(0, summary.pendingRows)
        assert.equal(1, summary.rereadTargets)
        assert.equal(639, sources[220001][1].itemLevel)
        assert.equal("Head", sources[220001][1].slot)
        -- The key and the name arrive with the same second read.
        assert.is_string(sources[220001][1].itemKey)
        assert.is_string(sources[220001][1].name)
        assert.equal(626, sources[220002][1].itemLevel)
        assert.equal("Finger", sources[220002][1].slot)
    end)

    it("leaves the rows pending when the item data never arrives at all", function()
        local sources, summary = ns.Journal:Build({ data = walkData(false), build = "69587" })
        assert.equal(2, summary.pendingItems)
        assert.equal(2, summary.pendingRows)
        assert.is_true(sources[220001][1].pending)
        assert.equal(3001, sources[220001][1].encounterID)
    end)
end)
