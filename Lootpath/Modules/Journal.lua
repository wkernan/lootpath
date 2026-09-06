-- Lootpath/Modules/Journal.lua (M3-1, WKE-522 - PR 1: the adapter and its capture)
--
-- Two halves, deliberately separated:
--   ns.JournalAdapter - every Encounter Journal call, raw and secret-guarded.
--     It is the only file in the addon that touches EJ_* or C_EncounterJournal,
--     and it normalises nothing: each entry point hands back ns.Probe packs
--     (`{ n = <count>, ... }`, or `{ absent = true }` / `{ error = ... }`)
--     exactly as the client answered. Untestable headless - wowless lists the
--     EJ functions but its loot functions return nothing - so it is proven by
--     the capture below and by the stub in spec/stubs/wow.lua, which is a
--     placeholder until WKE-523 commits a real transcript.
--   ns.Journal - the pure aggregator over adapter output. It lands in PR 2,
--     written against that transcript rather than against a guess.
--
-- Three things about the journal that shape this file:
--   1. Loot loads ASYNCHRONOUSLY. EJ_GetNumLoot() answers 0 (or the previous
--      instance's list) until the client has the data, then fires
--      EJ_LOOT_DATA_RECIEVED - Blizzard's spelling, confirmed in its own
--      Blizzard_EncounterJournal.lua, which gates its re-read on
--      EJ_IsLootListOutOfDate(). So the walk is a state machine over
--      C_Timer.After, not a loop, and `capture journal` is an async capture.
--   2. EncounterJournalItemInfo carries NO item level (Blizzard's exported
--      docs, checked 2026-09-05). The level comes from
--      C_Item.GetDetailedItemLevelInfo on the row's `link`.
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

-- The aggregator. PR 2 (still WKE-522) fills this in against the WKE-523
-- transcript: Build(opts) -> { [itemID] = { { instanceID, instanceName,
-- encounterID, encounterName, difficultyID, itemLevel, slot, isRaid } ... } },
-- cached in db.global.journalCache keyed (build, seasonID, specID, difficultyID).
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
-- of date, then read. onDone(result) is called exactly once.
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
