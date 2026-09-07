-- Lootpath/Modules/Journal.lua (M3-1, WKE-522 - PR 1 the adapter, PR 2 the aggregator)
--
-- Two halves, deliberately separated:
--   ns.JournalAdapter - every Encounter Journal call, raw and secret-guarded.
--     It is the only file in the addon that touches EJ_* or C_EncounterJournal,
--     and it normalises nothing: each entry point hands back ns.Probe packs
--     (`{ n = <count>, ... }`, or `{ absent = true }` / `{ error = ... }`)
--     exactly as the client answered. Untestable headless - wowless lists the
--     EJ functions but its loot functions return nothing - so it is proven by
--     the capture below and by the stub in spec/stubs/wow.lua.
--   ns.Journal - the pure aggregator over adapter output (PR 2), written
--     against spec/fixtures/captures/Lootpath-20260906-161213.lua rather than
--     against a guess.
--
-- Three things about the journal that shape this file:
--   1. Loot loads ASYNCHRONOUSLY, in TWO stages. EJ_GetNumLoot() answers 0 (or
--      the previous instance's list) until the client has the LIST, then fires
--      EJ_LOOT_DATA_RECIEVED - Blizzard's spelling, confirmed in its own
--      Blizzard_EncounterJournal.lua, which gates its re-read on
--      EJ_IsLootListOutOfDate(). So the walk is a state machine over
--      C_Timer.After, not a loop, and `capture journal` is an async capture.
--      The second stage is the ITEM data behind each row: 369 of the 613 rows
--      in the 2026-09-06 transcript came back carrying only itemID,
--      encounterID and the displayAs* flags, while EJ_IsLootListOutOfDate was
--      false on every read - so that gate says nothing about it. The walk
--      therefore reads each target a second time (Adapter.Walk, below).
--   2. EncounterJournalItemInfo carries NO item level (Blizzard's exported
--      docs, checked 2026-09-05). The level comes from
--      C_Item.GetDetailedItemLevelInfo on the row's `link`, which is why a row
--      that arrives without a link is "not known yet", never "no item level".
--   3. Selecting a tier, an instance, a difficulty or a loot filter MUTATES
--      the journal's view state. That is the one place a Lootpath capture is
--      not purely a read: it changes what the Adventure Guide shows, nothing
--      about the character. The walk records the previous tier, difficulty and
--      loot filter and puts them back when it finishes, including when it
--      aborts. There is no getter for the M+ preview level, so that one cannot
--      be restored - noted in docs/ARCHITECTURE.md.

local _, ns = ...

ns.JournalAdapter = {}
local Adapter = ns.JournalAdapter

-- The aggregator: Build(opts) -> { [itemID] = { { instanceID, instanceName,
-- encounterID, encounterName, difficultyID, itemLevel, slot, isRaid,
-- itemKey, name } ... } },
-- cached in db.global.journalCache keyed (build, seasonID, specID, difficultyID).
-- Implemented at the bottom of this file, after the adapter it reads.
ns.Journal = {}

-- Difficulty IDs, read from Blizzard's own DifficultyUtil.lua (shipped source,
-- mirrored in .luals/vscode-wow-api/Annotations/FrameXML/.../DifficultyUtil.lua,
-- lines 3-21) rather than from the wiki. The live DifficultyUtil.ID table wins
-- whenever the client has it; these are the fallback so a headless run and an
-- older client still agree.
Adapter.DIFFICULTY = {
    DungeonHeroic = 2,
    DungeonChallenge = 8, -- Mythic Keystone; the journal's M+ difficulty
    DungeonMythic = 23,
    PrimaryRaidNormal = 14,
    PrimaryRaidHeroic = 15,
    PrimaryRaidMythic = 16,
}

function Adapter.DifficultyID(name)
    local live = _G.DifficultyUtil
    local id = live and live.ID and live.ID[name]
    if type(id) == "number" then
        return id
    end
    return Adapter.DIFFICULTY[name]
end

-- What the capture walks unless the owner asks for something else. The issue's
-- brief: the season's M+ dungeon pool at Heroic and Mythic plus one M+ preview
-- level, and the current raid at Heroic and Mythic.
Adapter.DEFAULT_PREVIEW_MYTHIC_PLUS_LEVEL = 10

function Adapter.DefaultTargets()
    return {
        dungeon = {
            { difficulty = "DungeonHeroic" },
            { difficulty = "DungeonMythic" },
            { difficulty = "DungeonChallenge", preview = true },
        },
        raid = {
            { difficulty = "PrimaryRaidHeroic" },
            { difficulty = "PrimaryRaidMythic" },
        },
    }
end

-- How long one loot list is given to arrive before the walk moves on. Bounded
-- so a journal that never answers costs a known number of seconds per target
-- instead of hanging the capture; every wait and every timeout is counted into
-- the transcript, because "how long did the walk take and how many events
-- fired" is one of the questions WKE-523 exists to answer.
Adapter.LOOT_WAIT_SECONDS = 0.25
Adapter.LOOT_MAX_ATTEMPTS = 8

-- The second stage's bound, kept as its own pair of constants because it is a
-- different wait: the loot LIST is there, but the ITEM data behind some of its
-- rows is not. Same shape, so a target that never fills costs a known number
-- of seconds instead of hanging the walk, and every re-read and every timeout
-- is counted into the transcript.
Adapter.ITEM_DATA_WAIT_SECONDS = 0.25
Adapter.ITEM_DATA_MAX_ATTEMPTS = 8

-- Every client function this file calls, named here and nowhere discovered by
-- walking a namespace. All of them read or set journal view state; none of
-- them acts on the character or its items. The list is names rather than
-- values because a table entry whose value is nil simply is not there, and
-- "this client does not have that function" is precisely what the capture
-- needs to record.
Adapter.FUNCTION_NAMES = {
    "EJ_GetNumTiers",
    "EJ_GetCurrentTier",
    "EJ_GetTierInfo",
    "EJ_SelectTier",
    "EJ_GetInstanceByIndex",
    "EJ_GetInstanceInfo",
    "EJ_GetInstanceForMap",
    "EJ_SelectInstance",
    "EJ_InstanceIsRaid",
    "EJ_GetDifficulty",
    "EJ_SetDifficulty",
    "EJ_IsValidInstanceDifficulty",
    "EJ_GetLootFilter",
    "EJ_SetLootFilter",
    "EJ_ResetLootFilter",
    "EJ_GetEncounterInfoByIndex",
    "EJ_GetEncounterInfo",
    "EJ_GetNumLoot",
    "EJ_IsLootListOutOfDate",
    "C_EncounterJournal.GetLootInfoByIndex",
    "C_EncounterJournal.GetInstanceForGameMap",
    "C_EncounterJournal.SetPreviewMythicPlusLevel",
    "C_EncounterJournal.InstanceHasLoot",
    "C_ChallengeMode.GetMapTable",
    "C_ChallengeMode.GetMapUIInfo",
    "C_MythicPlus.GetCurrentSeason",
    "C_MythicPlus.GetCurrentSeasonValues",
    "C_MythicPlus.RequestMapInfo",
}

-- Looks one of those names up. Only names from the list above reach here, and
-- only the availability report uses it: every actual call site below names its
-- function literally, so nothing is ever called because a lookup found it.
function Adapter.Resolve(name)
    local namespace, member = name:match("^(C_[%w_]+)%.([%w_]+)$")
    if namespace then
        local api = _G[namespace]
        return type(api) == "table" and api[member] or nil
    end
    return _G[name]
end

-- Which of them this client actually has. A missing function is a finding for
-- the transcript, never a crash: WKE-522 named EJ_GetInstanceForGameMap, which
-- does not exist under that name on any client we can see.
function Adapter.Availability()
    local present, missing = {}, {}
    for _, name in ipairs(Adapter.FUNCTION_NAMES) do
        if type(Adapter.Resolve(name)) == "function" then
            present[#present + 1] = name
        else
            missing[#missing + 1] = name
        end
    end
    table.sort(present)
    table.sort(missing)
    return { present = present, missing = missing, ok = #missing == 0 }
end

-- Probe + secret guard. ns.Probe keeps the client's returns positional
-- (holes included); ns.CopyRaw replaces any secret value or table with a
-- marker and counts it. Table returns come back as copies, so nothing the
-- adapter hands out is still owned by the client.
Adapter.secretsSeen = 0

function Adapter.Call(fn, ...)
    local packed = ns.Probe(fn, ...)
    if packed.absent or packed.error then
        return packed
    end
    for i = 1, packed.n do
        local value, secret = ns.CopyRaw(packed[i])
        packed[i] = value
        if secret then
            Adapter.secretsSeen = Adapter.secretsSeen + 1
        end
    end
    return packed
end

-- Who the loot filter is for. EJ_SetLootFilter takes a classID and a specID;
-- the spec matters, which is why WKE-523 must be run in Restoration (105) and
-- not in the Guardian spec the 2026-09-05 transcript was taken in.
function Adapter.Player()
    local specIndex = Adapter.Call(GetSpecialization)
    local class = Adapter.Call(UnitClass, "player")
    local specInfo = type(specIndex[1]) == "number" and Adapter.Call(GetSpecializationInfo, specIndex[1])
        or { absent = true }
    return {
        name = Adapter.Call(UnitName, "player"),
        class = class,
        classID = class[3],
        specIndex = specIndex,
        specInfo = specInfo,
        specID = specInfo[1],
    }
end

function Adapter.Season()
    return {
        currentSeason = Adapter.Call(C_MythicPlus and C_MythicPlus.GetCurrentSeason),
        currentSeasonValues = Adapter.Call(C_MythicPlus and C_MythicPlus.GetCurrentSeasonValues),
    }
end

-- The season's Mythic+ dungeon pool, and the step WKE-522 flagged as the one
-- most likely to differ from any doc: turning a mapChallengeModeID into a
-- journal instance. Both candidates are recorded side by side for every map -
-- C_EncounterJournal.GetInstanceForGameMap (Blizzard's exported docs; its
-- comment says the argument is a game mapID, "not a uiMapID") and the global
-- EJ_GetInstanceForMap (present on the 12.1.0 client, transcript 2026-09-05,
-- listed by neither Ketho nor wowless) - so the transcript settles which one
-- answers and whether GetMapUIInfo's mapID is the mapID either expects.
function Adapter.MythicPlusPool()
    local mapTable = Adapter.Call(C_ChallengeMode and C_ChallengeMode.GetMapTable)
    local maps = {}
    if type(mapTable[1]) == "table" then
        for i, mapChallengeModeID in ipairs(mapTable[1]) do
            local uiInfo = Adapter.Call(C_ChallengeMode.GetMapUIInfo, mapChallengeModeID)
            local mapID = uiInfo[6]
            maps[i] = {
                mapChallengeModeID = mapChallengeModeID,
                mapUIInfo = uiInfo,
                mapName = uiInfo[1],
                mapID = mapID,
                instanceForGameMap = Adapter.Call(
                    C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap,
                    mapID
                ),
                instanceForMap = Adapter.Call(_G.EJ_GetInstanceForMap, mapID),
            }
        end
    end
    return { mapTable = mapTable, maps = maps }
end

function Adapter.Tiers()
    local numTiers = Adapter.Call(_G.EJ_GetNumTiers)
    local tiers = {}
    if type(numTiers[1]) == "number" then
        for i = 1, numTiers[1] do
            tiers[i] = Adapter.Call(_G.EJ_GetTierInfo, i)
        end
    end
    return { numTiers = numTiers, currentTier = Adapter.Call(_G.EJ_GetCurrentTier), tiers = tiers }
end

function Adapter.SelectTier(index)
    return Adapter.Call(_G.EJ_SelectTier, index)
end

-- Every instance the selected tier lists, dungeons or raids. Blizzard's own
-- journal walks EJ_GetInstanceByIndex(i, isRaid) until it answers nothing.
function Adapter.Instances(isRaid, limit)
    local instances = {}
    for index = 1, limit or 100 do
        local probe = Adapter.Call(_G.EJ_GetInstanceByIndex, index, isRaid)
        if type(probe[1]) ~= "number" then
            break
        end
        instances[index] = { index = index, instanceID = probe[1], name = probe[2], info = probe }
    end
    return instances
end

function Adapter.SelectInstance(journalInstanceID)
    return Adapter.Call(_G.EJ_SelectInstance, journalInstanceID)
end

function Adapter.SetDifficulty(difficultyID)
    return Adapter.Call(_G.EJ_SetDifficulty, difficultyID)
end

function Adapter.SetLootFilter(classID, specID)
    return Adapter.Call(_G.EJ_SetLootFilter, classID, specID)
end

-- Blizzard's own Encounter Journal never calls this (0 sites in its 12.1.0
-- source), so what it does to the loot rows is unobserved until WKE-523.
function Adapter.SetPreviewMythicPlusLevel(level)
    return Adapter.Call(C_EncounterJournal and C_EncounterJournal.SetPreviewMythicPlusLevel, level)
end

function Adapter.IsValidInstanceDifficulty(difficultyID)
    return Adapter.Call(_G.EJ_IsValidInstanceDifficulty, difficultyID)
end

function Adapter.Encounters(journalInstanceID, limit)
    local encounters = {}
    for index = 1, limit or 40 do
        local probe = Adapter.Call(_G.EJ_GetEncounterInfoByIndex, index, journalInstanceID)
        if type(probe[1]) ~= "string" then
            break
        end
        encounters[index] = { index = index, name = probe[1], encounterID = probe[3], info = probe }
    end
    return encounters
end

-- One read of the currently selected instance/difficulty's loot list. The item
-- level and the equip location are not in EncounterJournalItemInfo, so both
-- are probed from the row's link, the way the SimulationCraft addon does for
-- vault links.
function Adapter.LootRows()
    local numLoot = Adapter.Call(_G.EJ_GetNumLoot)
    local outOfDate = Adapter.Call(_G.EJ_IsLootListOutOfDate)
    local rows = {}
    if type(numLoot[1]) == "number" then
        for index = 1, numLoot[1] do
            local probe = Adapter.Call(C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex, index)
            local info = probe[1]
            local row = { index = index, itemInfo = probe }
            if type(info) == "table" and type(info.link) == "string" then
                row.detailedLevel = Adapter.Call(C_Item and C_Item.GetDetailedItemLevelInfo, info.link)
                row.instant = Adapter.Call(C_Item and C_Item.GetItemInfoInstant, info.link)
            end
            rows[index] = row
        end
    end
    return { numLoot = numLoot, outOfDate = outOfDate, rows = rows }
end

-- A loot list is worth waiting for while the client says it is out of date.
local function lootIsPending(read)
    return read.outOfDate[1] == true
end

-- Blizzard's own test for "this row's item data has not arrived yet":
-- EncounterJournalItemMixin:Init draws RETRIEVING_ITEM_INFO and blanks the
-- slot and armour type when `itemInfo.name` is missing
-- (Blizzard_EncounterJournal.lua, Mainline). The link is checked with it
-- because the link is what carries the item level.
function Adapter.RowIsPending(row)
    local info = row and row.itemInfo and row.itemInfo[1]
    if type(info) ~= "table" then
        return true
    end
    return type(info.name) ~= "string" or type(info.link) ~= "string"
end

function Adapter.CountPendingRows(read)
    local pending = 0
    for _, row in ipairs((read and read.rows) or {}) do
        if Adapter.RowIsPending(row) then
            pending = pending + 1
        end
    end
    return pending
end

-- Boss names for the encounters a read's rows point at. Blizzard's own loot
-- button resolves a row's boss exactly this way - EJ_GetEncounterInfo(
-- itemInfo.encounterID) in EncounterJournalItemMixin:Init - because
-- EJ_GetEncounterInfoByIndex answers nothing at some difficulties (measured:
-- every DungeonChallenge target and both Midnight targets in the 2026-09-06
-- transcript listed zero encounters, leaving 95 of 613 rows unnamed).
function Adapter.EncounterNames(read)
    local names = {}
    for _, row in ipairs((read and read.rows) or {}) do
        local info = row.itemInfo and row.itemInfo[1]
        local encounterID = type(info) == "table" and info.encounterID or nil
        if type(encounterID) == "number" and names[encounterID] == nil then
            names[encounterID] = Adapter.Call(_G.EJ_GetEncounterInfo, encounterID)
        end
    end
    return names
end

-- Journal view state, so the walk can put back what it changed. There is no
-- getter for the M+ preview level, so it is not in here.
function Adapter.ViewState()
    local filter = Adapter.Call(_G.EJ_GetLootFilter)
    return {
        tier = Adapter.Call(_G.EJ_GetCurrentTier),
        difficulty = Adapter.Call(_G.EJ_GetDifficulty),
        lootFilter = filter,
    }
end

function Adapter.RestoreViewState(state)
    state = state or {}
    local tier = (state.tier or {})[1]
    local difficulty = (state.difficulty or {})[1]
    local filter = state.lootFilter or {}
    local restored = {}
    if type(tier) == "number" then
        restored.tier = Adapter.Call(_G.EJ_SelectTier, tier)
    end
    if type(difficulty) == "number" then
        restored.difficulty = Adapter.Call(_G.EJ_SetDifficulty, difficulty)
    end
    if type(filter[1]) == "number" and type(filter[2]) == "number" then
        restored.lootFilter = Adapter.Call(_G.EJ_SetLootFilter, filter[1], filter[2])
    else
        restored.lootFilter = Adapter.Call(_G.EJ_ResetLootFilter)
    end
    return restored
end

-- EJ_LOOT_DATA_RECIEVED - Blizzard's spelling, kept verbatim. The frame is
-- created once and only listens while a walk is running.
local listener

local function ensureListener()
    if listener then
        return listener
    end
    listener = CreateFrame("Frame")
    listener:SetScript("OnEvent", function(_, event, itemID)
        if Adapter.onLootData then
            Adapter.onLootData(event, itemID)
        end
    end)
    return listener
end

function Adapter.WatchLootData(handler)
    local frame = ensureListener()
    Adapter.onLootData = handler
    frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
    return frame
end

function Adapter.StopWatchingLootData()
    if listener then
        listener:UnregisterEvent("EJ_LOOT_DATA_RECIEVED")
    end
    Adapter.onLootData = nil
end

local function after(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

local function now()
    return debugprofilestop and debugprofilestop() or 0
end

-- The walk. `targets` is a flat list of { instanceID, instanceName, isRaid,
-- difficultyID, difficultyName, previewLevel }; each one is selected, given up
-- to LOOT_MAX_ATTEMPTS x LOOT_WAIT_SECONDS for its loot list to stop being out
-- of date, then read TWICE. onDone(result) is called exactly once.
--
-- Why twice, and which of Blizzard's patterns this mirrors. Its
-- EncounterJournal_OnEvent splits EJ_LOOT_DATA_RECIEVED two ways: an event
-- carrying an itemID while the list is current refreshes just that row
-- (EncounterJournal_LootCallback), and anything else re-reads the whole list
-- (EncounterJournal_LootUpdate, an EJ_GetNumLoot loop over
-- C_EncounterJournal.GetLootInfoByIndex). The walk mirrors the second: it has
-- no frame per row to refresh, and it cannot come back to a target once the
-- next EJ_SelectInstance has moved the journal on, so the whole list is read
-- again in place. The first read is kept as `record.loot` and the second as
-- `record.reread`, so the transcript carries both and the next `capture
-- journal` can show what the second one filled in.
--
-- Nothing in here runs in combat: the walk checks before every target and
-- abandons the rest with `abortedInCombat` if the player is pulled into one.
function Adapter.Walk(opts, onDone)
    opts = opts or {}
    local targets = opts.targets or {}
    local result = {
        targets = {},
        lootEvents = 0,
        lootEventItemIDs = {},
        waits = 0,
        timeouts = 0,
        rereads = 0,
        itemDataTimeouts = 0,
        pendingRowsFirstRead = 0,
        pendingRowsFinalRead = 0,
        rowsFilledByReread = 0,
        abortedInCombat = false,
    }
    local startedAt = now()
    local finished = false
    local waiting = nil

    Adapter.WatchLootData(function(_, itemID)
        result.lootEvents = result.lootEvents + 1
        if #result.lootEventItemIDs < 200 then
            result.lootEventItemIDs[#result.lootEventItemIDs + 1] = itemID
        end
        if waiting then
            local resume = waiting
            waiting = nil
            resume()
        end
    end)

    local finishWalk, nextTarget

    function finishWalk()
        if finished then
            return
        end
        finished = true
        waiting = nil
        Adapter.StopWatchingLootData()
        result.durationMs = now() - startedAt
        result.restored = Adapter.RestoreViewState(opts.viewState)
        result.secretsSeen = Adapter.secretsSeen
        onDone(result)
    end

    local index = 0
    function nextTarget()
        if finished then
            return
        end
        index = index + 1
        local target = targets[index]
        if not target then
            return finishWalk()
        end
        if InCombatLockdown() then
            result.abortedInCombat = true
            result.abortedAtTarget = index
            return finishWalk()
        end

        local record = {
            instanceID = target.instanceID,
            instanceName = target.instanceName,
            isRaid = target.isRaid,
            difficultyID = target.difficultyID,
            difficultyName = target.difficultyName,
            previewLevel = target.previewLevel,
            attempts = 0,
            selectInstance = Adapter.SelectInstance(target.instanceID),
        }
        record.validDifficulty = Adapter.IsValidInstanceDifficulty(target.difficultyID)
        record.setDifficulty = Adapter.SetDifficulty(target.difficultyID)
        record.setLootFilter = Adapter.SetLootFilter(opts.classID, opts.specID)
        if target.previewLevel then
            record.setPreviewLevel = Adapter.SetPreviewMythicPlusLevel(target.previewLevel)
        end
        record.encounters = Adapter.Encounters(target.instanceID)
        result.targets[index] = record

        local attemptStartedAt = now()
        local itemDataStartedAt
        local settleItemData, waitForItemData

        -- Stage two: the list is in, but some rows have no name and no link.
        -- Wait for EJ_LOOT_DATA_RECIEVED (or the bound), then re-read the
        -- whole list the way EncounterJournal_LootUpdate does.
        function settleItemData()
            if finished then
                return
            end
            record.rereads = record.rereads + 1
            result.rereads = result.rereads + 1
            local reread = Adapter.LootRows()
            record.reread = reread
            record.rereadPendingRows = Adapter.CountPendingRows(reread)
            if record.rereadPendingRows > 0 and record.rereads < Adapter.ITEM_DATA_MAX_ATTEMPTS then
                return waitForItemData()
            end
            record.itemDataWaitedMs = now() - itemDataStartedAt
            result.pendingRowsFinalRead = result.pendingRowsFinalRead + record.rereadPendingRows
            result.rowsFilledByReread = result.rowsFilledByReread + (record.pendingRows - record.rereadPendingRows)
            record.encounterNames = Adapter.EncounterNames(reread)
            after(0, nextTarget)
        end

        function waitForItemData()
            if finished then
                return
            end
            local resumed = false
            local function resume()
                if resumed or finished then
                    return
                end
                resumed = true
                settleItemData()
            end
            waiting = resume
            after(Adapter.ITEM_DATA_WAIT_SECONDS, function()
                if waiting == resume then
                    waiting = nil
                end
                if not resumed and not finished then
                    record.itemDataTimeouts = (record.itemDataTimeouts or 0) + 1
                    result.itemDataTimeouts = result.itemDataTimeouts + 1
                end
                resume()
            end)
        end

        local function read()
            if finished then
                return
            end
            record.attempts = record.attempts + 1
            local loot = Adapter.LootRows()
            if lootIsPending(loot) and record.attempts < Adapter.LOOT_MAX_ATTEMPTS then
                result.waits = result.waits + 1
                local attempt = record.attempts
                local resumed = false
                local function resume()
                    if resumed or finished then
                        return
                    end
                    resumed = true
                    read()
                end
                waiting = resume
                after(Adapter.LOOT_WAIT_SECONDS, function()
                    if waiting == resume then
                        waiting = nil
                    end
                    if not resumed and not finished and record.attempts == attempt then
                        record.timedOutAttempts = (record.timedOutAttempts or 0) + 1
                        result.timeouts = result.timeouts + 1
                    end
                    resume()
                end)
                return
            end
            record.loot = loot
            record.stillOutOfDate = lootIsPending(loot)
            record.waitedMs = now() - attemptStartedAt
            record.pendingRows = Adapter.CountPendingRows(loot)
            record.rereads = 0
            result.pendingRowsFirstRead = result.pendingRowsFirstRead + record.pendingRows
            if record.pendingRows > 0 then
                itemDataStartedAt = now()
                return waitForItemData()
            end
            result.pendingRowsFinalRead = result.pendingRowsFinalRead + record.pendingRows
            record.encounterNames = Adapter.EncounterNames(loot)
            after(0, nextTarget)
        end
        read()
    end

    after(0, nextTarget)
    return result
end

-- Builds the flat target list from the season pool and the current tier's
-- raids. Journal instance IDs for the M+ pool come from whichever of the two
-- map lookups answered; a map neither could resolve is recorded as unresolved
-- rather than dropped, because that is the finding WKE-523 is looking for.
function Adapter.BuildTargets(pool, raidInstances, plan, previewLevel)
    local targets, unresolved = {}, {}
    for _, map in ipairs(pool.maps or {}) do
        local instanceID = map.instanceForGameMap[1] or map.instanceForMap[1]
        if type(instanceID) == "number" then
            map.journalInstanceID = instanceID
            map.resolvedBy = type(map.instanceForGameMap[1]) == "number" and "C_EncounterJournal.GetInstanceForGameMap"
                or "EJ_GetInstanceForMap"
            for _, step in ipairs(plan.dungeon) do
                targets[#targets + 1] = {
                    instanceID = instanceID,
                    instanceName = map.mapName,
                    isRaid = false,
                    difficultyID = Adapter.DifficultyID(step.difficulty),
                    difficultyName = step.difficulty,
                    previewLevel = step.preview and previewLevel or nil,
                }
            end
        else
            unresolved[#unresolved + 1] = {
                mapChallengeModeID = map.mapChallengeModeID,
                mapName = map.mapName,
                mapID = map.mapID,
            }
        end
    end
    for _, instance in ipairs(raidInstances or {}) do
        for _, step in ipairs(plan.raid) do
            targets[#targets + 1] = {
                instanceID = instance.instanceID,
                instanceName = instance.name,
                isRaid = true,
                difficultyID = Adapter.DifficultyID(step.difficulty),
                difficultyName = step.difficulty,
            }
        end
    end
    return targets, unresolved
end

-- ---------------------------------------------------------------------------
-- ns.Journal - the pure aggregator (PR 2)
--
-- Build(opts) turns one journal walk into the loot map:
--
--   { [itemID] = { { instanceID, instanceName, encounterID, encounterName,
--                    difficultyID, itemLevel, slot, isRaid, pending,
--                    itemKey, name } ... } }
--
-- It is pure Lua over a table the adapter already produced - the same shape a
-- `capture journal` snapshot stores - so like QEImport.Parse it carries no
-- combat guard and reads nothing from the client. The walk in front of it does
-- both (decision 2026-09-06).
--
-- Four things the 2026-09-06 transcript decided, none of them guessed:
--   * `slot` comes from the row's C_Item.GetItemInfoInstant equipLoc through
--     ns.Inventory.SlotForEquipLoc, NOT from EncounterJournalItemInfo.slot.
--     Both were measured, and they agree one-for-one across all 244 rows that
--     carried an equipLoc (e.g. "One-Hand"/INVTYPE_WEAPON, "Held In
--     Off-hand"/INVTYPE_HOLDABLE), but the row's own string is the client's
--     localised UI text while the equipLoc is not - and going through
--     Inventory's table is what makes Journal and Inventory speak one slot
--     vocabulary, which is QE Live's, which is what M3-3 joins them on.
--   * A row whose item data had not arrived (no name, no link) is carried with
--     `pending = true` and a nil itemLevel and slot. "Not known yet" is never
--     "no item level": 240 of the 376 itemIDs in that walk were link-less on
--     EVERY row, so treating them as slotless would silently lose 64% of the
--     map.
--   * `itemKey` is ns.ItemKey over the row's OWN link, and it is nil on a
--     pending row for the same reason `itemLevel` is: the link has not
--     arrived, not "this item has no key". Measured over the same transcript:
--     all 189 keyed entries carry exactly ONE bonus ID, and it is 3524 on
--     every one of them, while the item level moves with the difficulty (item
--     251153 is 276 Heroic / 292 Mythic / 305 at M+10 on the same key). So a
--     journal key is not the key of any copy you own - the export's items
--     carry two to seven bonus IDs - and M3-3's exact-key join stays honest by
--     matching almost nothing. That is the values-free decision working, not a
--     bug (see ARCHITECTURE.md 7, 2026-09-06).
--   * Boss names are an instance-wide fact, not a per-difficulty one. The
--     walk's own encounter list came back empty for every DungeonChallenge
--     target, so names seen at one difficulty of an instance name the same
--     encounters at its others.
local Journal = ns.Journal

-- Numbers numerically, anything else by its string form: difficulty IDs are
-- numbers, and 2:8:15:16:23 reads better than the lexicographic order.
function Journal.CompareIDs(a, b)
    if type(a) == "number" and type(b) == "number" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

-- Cache key. The issue's four parts, in order, with the difficulties joined
-- and sorted so the same walk always produces the same key.
function Journal.CacheKey(build, seasonID, specID, difficultyIDs)
    local sorted = {}
    for _, id in ipairs(difficultyIDs or {}) do
        sorted[#sorted + 1] = tonumber(id) or id
    end
    table.sort(sorted, Journal.CompareIDs)
    local difficulties = #sorted > 0 and table.concat(sorted, ":") or "none"
    return table.concat({ tostring(build), tostring(seasonID), tostring(specID), difficulties }, "|")
end

-- Everything the client built for another build is gone the moment the build
-- changes: item levels, bonus IDs and the season's pool all move with a patch,
-- so a stale entry is worse than no entry. Returns how many it dropped.
function Journal.Invalidate(db, build)
    local cache = db and db.global and db.global.journalCache
    if type(cache) ~= "table" then
        return 0
    end
    local dropped = 0
    for key, entry in pairs(cache) do
        if type(entry) ~= "table" or tostring(entry.build) ~= tostring(build) then
            cache[key] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

-- The read a target's rows are taken from: the second one whenever the walk
-- made it, because that is the one taken after EJ_LOOT_DATA_RECIEVED.
local function finalRead(target)
    return target.reread or target.loot
end

local function probeValue(pack)
    return type(pack) == "table" and pack[1] or nil
end

-- GetBuildInfo() -> version, build, date, tocversion. The cache is keyed on
-- the BUILD number (69587 on 2026-09-06), not the version string: a hotfix
-- build can move item levels without moving "12.1.0".
function Journal.BuildNumber(pack)
    if type(pack) ~= "table" then
        return nil
    end
    return pack[2] or pack[1]
end

-- [instanceID][encounterID] = boss name, gathered across every target of an
-- instance before any row is read.
local function encounterIndex(targets)
    local byInstance = {}
    for _, target in ipairs(targets) do
        local names = byInstance[target.instanceID]
        if not names then
            names = {}
            byInstance[target.instanceID] = names
        end
        for _, encounter in ipairs(target.encounters or {}) do
            if type(encounter.encounterID) == "number" and type(encounter.name) == "string" then
                names[encounter.encounterID] = encounter.name
            end
        end
        for encounterID, pack in pairs(target.encounterNames or {}) do
            local name = probeValue(pack)
            if type(name) == "string" and names[encounterID] == nil then
                names[encounterID] = name
            end
        end
    end
    return byInstance
end

-- Deterministic order, so a golden fixture is stable: dungeons before raids,
-- then instance, difficulty, encounter, and a known row before a pending one.
local function sortSources(list)
    table.sort(list, function(a, b)
        if (a.isRaid == true) ~= (b.isRaid == true) then
            return b.isRaid == true
        end
        if a.instanceID ~= b.instanceID then
            return (a.instanceID or 0) < (b.instanceID or 0)
        end
        if a.difficultyID ~= b.difficultyID then
            return (a.difficultyID or 0) < (b.difficultyID or 0)
        end
        if a.encounterID ~= b.encounterID then
            return (a.encounterID or 0) < (b.encounterID or 0)
        end
        return (a.pending and 1 or 0) < (b.pending and 1 or 0)
    end)
end

local function aggregate(targets, wanted)
    local names = encounterIndex(targets)
    local sources, seen = {}, {}
    local summary = {
        targets = 0,
        rows = 0,
        skippedRows = 0,
        nonGearRows = 0,
        pendingRows = 0,
        duplicateRows = 0,
        rereadTargets = 0,
        sources = 0,
        items = 0,
        pendingItems = 0,
        unnamedEncounters = 0,
    }

    for _, target in ipairs(targets) do
        if not wanted or wanted[target.difficultyID] then
            summary.targets = summary.targets + 1
            if target.reread then
                summary.rereadTargets = summary.rereadTargets + 1
            end
            local read = finalRead(target)
            for _, row in ipairs((read and read.rows) or {}) do
                summary.rows = summary.rows + 1
                local info = row.itemInfo and row.itemInfo[1]
                local itemID = type(info) == "table" and tonumber(info.itemID) or nil
                local pending = Adapter.RowIsPending(row)
                local slot = ns.Inventory and ns.Inventory.SlotForEquipLoc(row.instant and row.instant[4]) or nil
                -- The row's own link. Kept per source rather than per item
                -- because nothing promises the journal previews one link for
                -- an item at every difficulty; on the 2026-09-06 transcript it
                -- did (one bonus ID, 3524, on all 189 keyed entries), and the
                -- entry is where the next capture can show that it stopped.
                local parsed = (not pending) and ns.ParseItemLink(info.link) or nil
                if not itemID or itemID <= 0 or itemID % 1 ~= 0 then
                    summary.skippedRows = summary.skippedRows + 1
                elseif not pending and not slot then
                    -- Known, and known not to be gear: a pattern, a mount, a
                    -- toy. Inventory drops these too (decision 2026-09-06).
                    summary.nonGearRows = summary.nonGearRows + 1
                else
                    if pending then
                        summary.pendingRows = summary.pendingRows + 1
                    end
                    local encounterID = info.encounterID
                    local encounterName = names[target.instanceID] and names[target.instanceID][encounterID] or nil
                    if encounterID ~= nil and encounterName == nil then
                        summary.unnamedEncounters = summary.unnamedEncounters + 1
                    end
                    local key = table.concat({
                        itemID,
                        tostring(target.instanceID),
                        tostring(encounterID),
                        tostring(target.difficultyID),
                    }, "|")
                    local existing = seen[key]
                    if existing then
                        summary.duplicateRows = summary.duplicateRows + 1
                        if existing.pending and not pending then
                            existing.pending = nil
                            existing.slot = slot
                            existing.itemLevel = tonumber(probeValue(row.detailedLevel))
                            existing.itemKey = parsed and parsed.key or nil
                            existing.name = type(info.name) == "string" and info.name or nil
                        end
                    else
                        local entry = {
                            instanceID = target.instanceID,
                            instanceName = target.instanceName,
                            encounterID = encounterID,
                            encounterName = encounterName,
                            difficultyID = target.difficultyID,
                            itemLevel = not pending and tonumber(probeValue(row.detailedLevel)) or nil,
                            slot = slot,
                            isRaid = target.isRaid == true,
                            pending = pending or nil,
                            itemKey = parsed and parsed.key or nil,
                            -- The name the client already handed the walk, so
                            -- a panel built from the cache reads as item names
                            -- rather than item IDs even when the client has
                            -- since forgotten the item.
                            name = (not pending) and type(info.name) == "string" and info.name or nil,
                        }
                        seen[key] = entry
                        local list = sources[itemID]
                        if not list then
                            list = {}
                            sources[itemID] = list
                        end
                        list[#list + 1] = entry
                        summary.sources = summary.sources + 1
                    end
                end
            end
        end
    end

    for _, list in pairs(sources) do
        sortSources(list)
        summary.items = summary.items + 1
        local known = false
        for _, entry in ipairs(list) do
            if not entry.pending then
                known = true
            end
        end
        if not known then
            summary.pendingItems = summary.pendingItems + 1
        end
    end
    return sources, summary
end

-- Build(opts) -> sources, summary, fromCache
--
-- opts.data       the `data` table of a `capture journal` snapshot (required),
--                 or opts.snapshot and its .data is used
-- opts.difficultyIDs  only these difficulties (default: every one the walk saw)
-- opts.db         AceDB (default ns.db); no db means no caching, never an error
-- opts.build / opts.seasonID / opts.specID   override what the walk recorded
-- opts.previewMythicPlusLevel  override the M+ level the walk previewed
-- opts.refresh    rebuild even when the cache already holds this key
function Journal.Build(_, opts)
    opts = opts or {}
    local snapshot = opts.snapshot
    local data = opts.data or (snapshot and snapshot.data)
    if type(data) ~= "table" or type(data.walk) ~= "table" then
        return nil, { ok = false, reason = "no walk data" }, false
    end
    local targets = data.walk.targets or {}

    local wanted, difficultyIDs = nil, {}
    if opts.difficultyIDs then
        wanted = {}
        for _, id in ipairs(opts.difficultyIDs) do
            wanted[id] = true
            difficultyIDs[#difficultyIDs + 1] = id
        end
    else
        local seen = {}
        for _, target in ipairs(targets) do
            if target.difficultyID ~= nil and not seen[target.difficultyID] then
                seen[target.difficultyID] = true
                difficultyIDs[#difficultyIDs + 1] = target.difficultyID
            end
        end
    end

    table.sort(difficultyIDs, Journal.CompareIDs)

    local build = opts.build or (snapshot and Journal.BuildNumber(snapshot.build)) or Journal.BuildNumber(data.build)
    local seasonID = opts.seasonID or probeValue(data.season and data.season.currentSeason)
    local specID = opts.specID or (data.player and data.player.specID) or (data.requested and data.requested.specID)
    local key = Journal.CacheKey(build, seasonID, specID, difficultyIDs)

    local db = opts.db
    if db == nil then
        db = ns.db
    end
    local cache = db and db.global and db.global.journalCache or nil
    if cache then
        Journal.Invalidate(db, build)
        local entry = cache[key]
        if entry and not opts.refresh then
            return entry.sources, entry.summary, true
        end
    end

    local sources, summary = aggregate(targets, wanted)
    summary.ok = true
    summary.cacheKey = key
    summary.build = build
    summary.seasonID = seasonID
    summary.specID = specID
    summary.difficultyIDs = difficultyIDs
    -- The M+ level the walk previewed. There is no getter for it on the client
    -- (decision 2026-09-06), so the number the capture asked for is the only
    -- record of what difficulty 8's item levels mean.
    summary.previewMythicPlusLevel = opts.previewMythicPlusLevel
        or (data.requested and tonumber(data.requested.previewMythicPlusLevel))
        or nil
    if cache then
        cache[key] = { build = build, sources = sources, summary = summary }
    end
    return sources, summary, false
end

-- /lootpath capture journal [preview M+ level]
--
-- Async (see ns.RunCapture): it starts the walk and calls `finish` when the
-- last loot list is in. Registered here rather than in Captures.lua because
-- this is the file that names every Encounter Journal function it calls, which
-- is what the "captures call only what their own file names" rule is for.
--
-- The one capture that is not purely a read: it selects tiers, instances,
-- difficulties and a loot filter, and it restores all three when it is done.
ns.RegisterCapture(
    "journal",
    "walk the season's M+ pool and the current raid for loot (async; takes a few seconds)",
    function(finish, args)
        local previewLevel = tonumber(args and args:match("%d+")) or Adapter.DEFAULT_PREVIEW_MYTHIC_PLUS_LEVEL
        Adapter.secretsSeen = 0

        local availability = Adapter.Availability()
        local player = Adapter.Player()
        local viewState = Adapter.ViewState()
        local season = Adapter.Season()
        -- Blizzard's own UI asks for the map pool before reading it; harmless
        -- if the data is already there.
        local requestMapInfo = Adapter.Call(C_MythicPlus and C_MythicPlus.RequestMapInfo)
        local pool = Adapter.MythicPlusPool()

        local tiers = Adapter.Tiers()
        local selectedTier
        if type(tiers.numTiers[1]) == "number" then
            selectedTier = tiers.numTiers[1]
            Adapter.SelectTier(selectedTier)
        end
        local dungeonInstances = Adapter.Instances(false)
        local raidInstances = Adapter.Instances(true)

        local plan = Adapter.DefaultTargets()
        local targets, unresolved = Adapter.BuildTargets(pool, raidInstances, plan, previewLevel)

        Adapter.Walk({
            targets = targets,
            classID = player.classID,
            specID = player.specID,
            viewState = viewState,
        }, function(result)
            finish({
                requested = {
                    previewMythicPlusLevel = previewLevel,
                    plan = plan,
                    classID = player.classID,
                    specID = player.specID,
                    targetCount = #targets,
                },
                availability = availability,
                player = player,
                viewStateBefore = viewState,
                season = season,
                requestMapInfo = requestMapInfo,
                pool = pool,
                unresolvedMaps = unresolved,
                tiers = tiers,
                selectedTier = selectedTier,
                dungeonInstances = dungeonInstances,
                raidInstances = raidInstances,
                walk = result,
            })
        end)
    end,
    { async = true }
)
