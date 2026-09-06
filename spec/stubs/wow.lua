-- spec/stubs/wow.lua
-- The minimum fake WoW API surface for headless busted runs. Shapes come from
-- Blizzard's exported API docs (Ketho's annotations, checked 2026-09-05) and
-- the build tuple from the Healper spike's in-client capture of GetBuildInfo()
-- (2026-09-01, 12.1.0 build 69587). Nothing here comes from the wiki.
--
-- Values are placeholders: a test that needs a real return shape reads a
-- committed capture under spec/fixtures/ instead. The stub exists so the pure
-- modules can be exercised without a client; it proves nothing about the client.
--
-- Usage: local world = Stub.install()  ... Stub.uninstall()
-- `world` is the mutable model behind the API (combat state, bags, vault...).

local Stub = {}

local function deepcopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[deepcopy(k, seen)] = deepcopy(v, seen)
    end
    return out
end
Stub.deepcopy = deepcopy

local saved = {}
local installedNames = {}

local function define(name, value)
    if not installedNames[name] then
        installedNames[name] = true
        saved[name] = _G[name]
    end
    _G[name] = value
end

local function newFrame(kind, world)
    local f = { kind = kind or "Frame", events = {}, scripts = {}, shown = false }
    function f:RegisterEvent(event)
        self.events[event] = true
    end
    function f:UnregisterEvent(event)
        self.events[event] = nil
    end
    function f:SetScript(handler, fn)
        self.scripts[handler] = fn
    end
    function f:GetScript(handler)
        return self.scripts[handler]
    end
    function f:GetObjectType()
        return self.kind
    end
    function f:IsShown()
        return self.shown
    end
    function f:Show()
        self.shown = true
    end
    function f:Hide()
        self.shown = false
    end
    world.frames[#world.frames + 1] = f
    return f
end

function Stub.install()
    local world = {
        inCombat = false,
        hasSecretRestrictions = true,
        -- GetBuildInfo() on the live client, 2026-09-01 (HealperSpike SavedVariables).
        build = { "12.1.0", "69587", "Aug 27 2026", 120100, "", " " },
        locale = "enUS",
        realm = "TestRealm",
        playerName = "Tester",
        addons = {
            { name = "Lootpath", title = "Lootpath", loaded = true },
            { name = "Simulationcraft", title = "SimulationCraft", loaded = false },
        },
        metadata = { Version = "0.0.0-test" },
        equipped = {}, -- [invSlot] = { link = , id = }
        bags = {}, -- [bagIndex] = { numSlots = , items = { [slot] = { info = , link = , id = } } }
        items = {}, -- [link] = { level = , info = {...}, instant = {...} }
        bankOpen = false,
        vaultOpen = false,
        vault = { hasAvailable = false, canClaim = false, activities = {}, links = {}, examples = {} },
        secondsUntilReset = 3600,
        printed = {},
        frames = {},
        equipCalls = {},
        secrets = setmetatable({}, { __mode = "k" }),
        -- C_Timer.After runs on a fake clock a test drives with runTimers.
        now = 0,
        timers = {},
        -- The Encounter Journal. Placeholders in every particular: WKE-523's
        -- transcript is what settles the real shapes. What is modelled here is
        -- the BEHAVIOUR the adapter has to survive - loot that is out of date
        -- until EJ_LOOT_DATA_RECIEVED arrives, and journal view state that a
        -- walk must put back.
        journal = {
            numTiers = 3,
            currentTier = 1,
            tierInfo = { { "Tier One", "tierlink1" }, { "Tier Two", "tierlink2" }, { "Tier Three", "tierlink3" } },
            difficulty = 1,
            lootFilter = { 0, 0 },
            previewLevel = nil,
            previewLevelCalls = {},
            selectedInstance = nil,
            instances = { dungeons = {}, raids = {} },
            encounters = {}, -- [instanceID] = { { name, description, encounterID } }
            loot = {}, -- [instanceID] = { [difficultyID] = { EncounterJournalItemInfo } }
            validDifficulty = {}, -- [instanceID] = { [difficultyID] = boolean }
            mapTable = {},
            mapUIInfo = {}, -- [mapChallengeModeID] = { name, id, timeLimit, texture, background, mapID }
            instanceForGameMap = {}, -- [mapID] = journalInstanceID
            instanceForMap = {}, -- [mapID] = journalInstanceID
            season = 15,
            -- nil = loot is ready the moment it is selected. A number delays
            -- EJ_LOOT_DATA_RECIEVED by that many fake seconds; `false` means
            -- the event never comes at all.
            lootDelaySeconds = nil,
            lootPending = false,
            selectCalls = {},
            lootFilterCalls = {},
        },
    }

    -- Secrets: a sentinel registered here answers issecretvalue / issecrettable.
    function world.secret(label)
        local sentinel = { secret = label or "value" }
        world.secrets[sentinel] = "value"
        return sentinel
    end
    function world.secretTable(label)
        local sentinel = { secret = label or "table" }
        world.secrets[sentinel] = "table"
        return sentinel
    end
    function world.fireEvent(event, ...)
        for _, f in ipairs(world.frames) do
            if f.events[event] and f.scripts.OnEvent then
                f.scripts.OnEvent(f, event, ...)
            end
        end
    end
    function world.output()
        return table.concat(world.printed, "\n")
    end

    -- Drives C_Timer.After on a fake clock: fires every pending timer whose
    -- due time falls within `budgetSeconds` of now, earliest first, letting
    -- callbacks schedule more. Nothing here sleeps, so an async walk runs to
    -- completion inside a synchronous test.
    function world.runTimers(budgetSeconds)
        local deadline = world.now + (budgetSeconds or 0)
        local guard = 0
        while true do
            guard = guard + 1
            assert(guard < 100000, "stub: runaway timer loop")
            local pick
            for i = 1, #world.timers do
                local timer = world.timers[i]
                if not timer.done and (not pick or timer.at < pick.at) then
                    pick = timer
                end
            end
            if not pick or pick.at > deadline then
                return
            end
            pick.done = true
            if pick.at > world.now then
                world.now = pick.at
            end
            pick.fn()
        end
    end

    define("issecretvalue", function(value)
        return world.secrets[value] == "value"
    end)
    define("issecrettable", function(value)
        return world.secrets[value] == "table"
    end)
    define("InCombatLockdown", function()
        return world.inCombat
    end)
    define("GetBuildInfo", function()
        return unpack(world.build)
    end)
    define("GetLocale", function()
        return world.locale
    end)
    define("GetRealmName", function()
        return world.realm
    end)
    define("UnitName", function(unit)
        if unit == "player" then
            return world.playerName, nil
        end
        return nil
    end)
    define("UnitClass", function()
        return "Druid", "DRUID", 11
    end)
    define("GetSpecialization", function()
        return 4
    end)
    define("GetSpecializationInfo", function(index)
        if index == 4 then
            return 105, "Restoration", "placeholder", 136041, "HEALER", 4
        end
        return nil
    end)
    define("debugprofilestop", function()
        return os.clock() * 1000
    end)
    define("time", os.time)
    define("date", os.date)
    define("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        world.printed[#world.printed + 1] = table.concat(parts, " ")
    end)
    define("CreateFrame", function(kind)
        return newFrame(kind, world)
    end)
    define("SlashCmdList", {})

    -- FrameXML constants (Blizzard_FrameXMLBase/Constants.lua via Ketho).
    define("INVSLOT_FIRST_EQUIPPED", 1)
    define("INVSLOT_LAST_EQUIPPED", 19)
    define("NUM_BAG_SLOTS", 4)
    define("NUM_TOTAL_EQUIPPED_BAG_SLOTS", 5)

    -- Enum.BagIndex as the 12.1.0 client enumerated it (transcript 2026-09-05,
    -- capture env); the other enums from Blizzard's docs via Ketho.
    define("Enum", {
        BagIndex = {
            Accountbanktab = -3,
            Characterbanktab = -2,
            Keyring = -1,
            Backpack = 0,
            Bag_1 = 1,
            Bag_2 = 2,
            Bag_3 = 3,
            Bag_4 = 4,
            ReagentBag = 5,
            CharacterBankTab_1 = 6,
            CharacterBankTab_2 = 7,
            CharacterBankTab_3 = 8,
            CharacterBankTab_4 = 9,
            CharacterBankTab_5 = 10,
            CharacterBankTab_6 = 11,
            AccountBankTab_1 = 12,
            AccountBankTab_2 = 13,
            AccountBankTab_3 = 14,
            AccountBankTab_4 = 15,
            AccountBankTab_5 = 16,
        },
        BankType = { Character = 0, Guild = 1, Account = 2 },
        WeeklyRewardChestThresholdType = { None = 0, Activities = 1, RankedPvP = 2, Raid = 3, World = 6 },
        CachedRewardType = { None = 0, Item = 1, Currency = 2, Quest = 3 },
        ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 },
    })

    local libs = {
        ["AceDB-3.0"] = {
            New = function(_, svName, defaults)
                local db = deepcopy(defaults or {})
                db.sv = svName
                world.db = db
                return db
            end,
        },
    }
    define("LibStub", function(name, silent)
        local lib = libs[name]
        if not lib and not silent then
            error("stub: no library " .. tostring(name))
        end
        return lib
    end)

    define("C_AddOns", {
        GetNumAddOns = function()
            return #world.addons
        end,
        GetAddOnInfo = function(index)
            local a = world.addons[index]
            if not a then
                return nil
            end
            return a.name, a.title, a.notes, a.loadable ~= false, a.reason, "INSECURE"
        end,
        IsAddOnLoaded = function(indexOrName)
            for i, a in ipairs(world.addons) do
                if i == indexOrName or a.name == indexOrName then
                    return a.loaded, a.loaded
                end
            end
            return false, false
        end,
        GetAddOnMetadata = function(_, field)
            return world.metadata[field]
        end,
    })

    define("C_Secrets", {
        HasSecretRestrictions = function()
            return world.hasSecretRestrictions
        end,
    })

    define("GetInventoryItemLink", function(unit, slot)
        local e = unit == "player" and world.equipped[slot]
        return e and e.link or nil
    end)
    define("GetInventoryItemID", function(unit, slot)
        local e = unit == "player" and world.equipped[slot]
        return e and e.id or nil
    end)
    define("ItemLocation", {
        CreateFromEquipmentSlot = function(_, slot)
            return { equipmentSlotIndex = slot }
        end,
    })

    define("C_Item", {
        GetDetailedItemLevelInfo = function(link)
            local item = world.items[link]
            if not item then
                return nil
            end
            if item.detailed then
                return unpack(item.detailed, 1, item.detailed.n or 3)
            end
            return item.level, false, item.level
        end,
        GetItemInfo = function(link)
            local item = world.items[link]
            if not item or not item.info then
                return nil
            end
            -- 18 returns on 12.1.0 (transcript 2026-09-05); replayed tables carry n.
            return unpack(item.info, 1, item.info.n or #item.info)
        end,
        GetItemInfoInstant = function(link)
            local item = world.items[link]
            if not item or not item.instant then
                return nil
            end
            return unpack(item.instant, 1, 7)
        end,
        GetCurrentItemLevel = function(location)
            local e = world.equipped[location.equipmentSlotIndex]
            local item = e and world.items[e.link]
            return item and item.level or nil
        end,
        EquipItemByName = function(itemInfo, dstSlot)
            world.equipCalls[#world.equipCalls + 1] = { itemInfo, dstSlot }
        end,
    })

    define("C_Container", {
        GetContainerNumSlots = function(bag)
            local b = world.bags[bag]
            return b and b.numSlots or 0
        end,
        GetContainerNumFreeSlots = function(bag)
            local b = world.bags[bag]
            if not b then
                return 0, 0
            end
            local used = 0
            for _ in pairs(b.items or {}) do
                used = used + 1
            end
            return b.numSlots - used, 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local b = world.bags[bag]
            local it = b and b.items and b.items[slot]
            return it and it.info and deepcopy(it.info) or nil
        end,
        GetContainerItemLink = function(bag, slot)
            local b = world.bags[bag]
            local it = b and b.items and b.items[slot]
            return it and it.link or nil
        end,
        GetContainerItemID = function(bag, slot)
            local b = world.bags[bag]
            local it = b and b.items and b.items[slot]
            return it and it.id or nil
        end,
    })

    -- Transcript 2026-09-05: Character and Account answer true only while the
    -- bank frame is open; Guild is false either way.
    define("C_Bank", {
        CanViewBank = function(bankType)
            return world.bankOpen and bankType ~= 1
        end,
        CanUseBank = function(bankType)
            return world.bankOpen and bankType ~= 1
        end,
        CanPurchaseBankTab = function()
            return false
        end,
        HasMaxBankTabs = function()
            return false
        end,
    })
    local bankFrame = newFrame("Frame", world)
    function bankFrame.IsShown()
        return world.bankOpen
    end
    define("BankFrame", bankFrame)

    define("C_WeeklyRewards", {
        HasAvailableRewards = function()
            return world.vault.hasAvailable
        end,
        CanClaimRewards = function()
            return world.vault.canClaim
        end,
        GetActivities = function()
            return deepcopy(world.vault.activities)
        end,
        GetItemHyperlink = function(itemDBID)
            return world.vault.links[itemDBID]
        end,
        GetExampleRewardItemHyperlinks = function(id)
            local ex = world.vault.examples[id]
            if ex then
                return unpack(ex)
            end
            return nil
        end,
    })
    local vaultFrame = newFrame("Frame", world)
    function vaultFrame.IsShown()
        return world.vaultOpen
    end
    define("WeeklyRewardsFrame", vaultFrame)

    define("C_DateAndTime", {
        GetSecondsUntilWeeklyReset = function()
            return world.secondsUntilReset
        end,
    })

    define("C_Timer", {
        After = function(delay, fn)
            world.timers[#world.timers + 1] = { at = world.now + (tonumber(delay) or 0), fn = fn }
        end,
    })

    -- DifficultyUtil.ID, from Blizzard's shipped DifficultyUtil.lua (the
    -- annotated FrameXML source under .luals, lines 3-21), not the wiki.
    define("DifficultyUtil", {
        ID = {
            DungeonNormal = 1,
            DungeonHeroic = 2,
            DungeonChallenge = 8,
            DungeonMythic = 23,
            PrimaryRaidNormal = 14,
            PrimaryRaidHeroic = 15,
            PrimaryRaidMythic = 16,
        },
    })

    -- The Encounter Journal. Selecting an instance or a difficulty starts the
    -- client fetching loot: until it arrives EJ_IsLootListOutOfDate answers
    -- true and EJ_GetNumLoot answers 0, exactly the behaviour Blizzard's own
    -- journal codes around. world.journal.lootDelaySeconds decides how that
    -- resolves: nil = immediately, a number = after that many fake seconds and
    -- an EJ_LOOT_DATA_RECIEVED, false = never.
    local J = world.journal

    local function currentLoot()
        local byDifficulty = J.loot[J.selectedInstance]
        return (byDifficulty and byDifficulty[J.difficulty]) or {}
    end

    -- Only the latest fetch resolves, so selecting an instance and then a
    -- difficulty produces one loot list and one event, not two.
    local function startLootFetch()
        J.fetchToken = (J.fetchToken or 0) + 1
        if J.lootDelaySeconds == nil then
            J.lootPending = false
            return
        end
        J.lootPending = true
        if J.lootDelaySeconds == false then
            return
        end
        local token = J.fetchToken
        _G.C_Timer.After(J.lootDelaySeconds, function()
            if J.fetchToken ~= token then
                return
            end
            J.lootPending = false
            local first = currentLoot()[1]
            world.fireEvent("EJ_LOOT_DATA_RECIEVED", first and first.itemID or nil)
        end)
    end
    world.journal.startLootFetch = startLootFetch

    define("EJ_GetNumTiers", function()
        return J.numTiers
    end)
    define("EJ_GetCurrentTier", function()
        return J.currentTier
    end)
    define("EJ_GetTierInfo", function(index)
        local tier = J.tierInfo[index]
        if not tier then
            return nil
        end
        return tier[1], tier[2]
    end)
    define("EJ_SelectTier", function(index)
        J.currentTier = index
    end)
    define("EJ_GetInstanceByIndex", function(index, isRaid)
        local list = isRaid and J.instances.raids or J.instances.dungeons
        local instance = list[index]
        if not instance then
            return nil
        end
        -- Ketho's ordering: 1 instanceID, 2 name, 3 description, 4-10 art and
        -- flags, 11 mapID.
        local nothing = nil
        return instance.instanceID,
            instance.name,
            instance.description,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            instance.mapID
    end)
    define("EJ_GetInstanceInfo", function()
        local list = J.instances.dungeons
        for _, instance in ipairs(list) do
            if instance.instanceID == J.selectedInstance then
                return instance.name
            end
        end
        return nil
    end)
    define("EJ_GetInstanceForMap", function(mapID)
        return J.instanceForMap[mapID]
    end)
    define("EJ_SelectInstance", function(journalInstanceID)
        J.selectedInstance = journalInstanceID
        J.selectCalls[#J.selectCalls + 1] = { instance = journalInstanceID }
        startLootFetch()
    end)
    define("EJ_InstanceIsRaid", function()
        for _, instance in ipairs(J.instances.raids) do
            if instance.instanceID == J.selectedInstance then
                return true
            end
        end
        return false
    end)
    define("EJ_GetDifficulty", function()
        return J.difficulty
    end)
    define("EJ_SetDifficulty", function(difficultyID)
        J.difficulty = difficultyID
        J.selectCalls[#J.selectCalls + 1] = { difficulty = difficultyID }
        startLootFetch()
    end)
    define("EJ_IsValidInstanceDifficulty", function(difficultyID)
        local valid = J.validDifficulty[J.selectedInstance]
        if not valid then
            return true
        end
        return valid[difficultyID] == true
    end)
    define("EJ_GetLootFilter", function()
        return J.lootFilter[1], J.lootFilter[2]
    end)
    define("EJ_SetLootFilter", function(classID, specID)
        J.lootFilter = { classID, specID }
        J.lootFilterCalls[#J.lootFilterCalls + 1] = { classID, specID }
    end)
    define("EJ_ResetLootFilter", function()
        J.lootFilter = { 0, 0 }
    end)
    define("EJ_GetEncounterInfoByIndex", function(index, journalInstanceID)
        local encounters = J.encounters[journalInstanceID or J.selectedInstance] or {}
        local encounter = encounters[index]
        if not encounter then
            return nil
        end
        return encounter.name, encounter.description, encounter.encounterID
    end)
    define("EJ_GetNumLoot", function()
        if J.lootPending then
            return 0
        end
        return #currentLoot()
    end)
    define("EJ_IsLootListOutOfDate", function()
        return J.lootPending
    end)

    define("C_EncounterJournal", {
        GetLootInfoByIndex = function(index)
            if J.lootPending then
                return nil
            end
            return deepcopy(currentLoot()[index])
        end,
        GetInstanceForGameMap = function(mapID)
            return J.instanceForGameMap[mapID]
        end,
        SetPreviewMythicPlusLevel = function(level)
            J.previewLevel = level
            J.previewLevelCalls[#J.previewLevelCalls + 1] = level
        end,
        InstanceHasLoot = function()
            return true
        end,
    })
    define("C_MythicPlus", {
        GetCurrentSeason = function()
            return J.season
        end,
        GetCurrentSeasonValues = function()
            return J.season, J.season, J.season
        end,
        RequestMapInfo = function() end,
    })
    define("C_ChallengeMode", {
        GetMapTable = function()
            return deepcopy(J.mapTable)
        end,
        GetMapUIInfo = function(mapChallengeModeID)
            local info = J.mapUIInfo[mapChallengeModeID]
            if not info then
                return nil
            end
            return info[1], info[2], info[3], info[4], info[5], info[6]
        end,
    })

    return world
end

function Stub.uninstall()
    for name in pairs(installedNames) do
        _G[name] = saved[name]
    end
    installedNames = {}
    saved = {}
end

return Stub
