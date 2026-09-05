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

    -- Enum values from Blizzard's docs (Ketho Annotations/Core/Data/Enum.lua); subset.
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
            return item.level, false, item.level
        end,
        GetItemInfo = function(link)
            local item = world.items[link]
            if not item or not item.info then
                return nil
            end
            return unpack(item.info, 1, 17)
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

    define("C_Bank", {
        CanViewBank = function()
            return world.bankOpen
        end,
        CanUseBank = function()
            return world.bankOpen
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

    -- Namespaces the env capture lists; empty until their issues fill them.
    define("C_EncounterJournal", { GetLootInfoByIndex = function() end })
    define("C_MythicPlus", { GetCurrentSeason = function() end })
    define("C_ChallengeMode", { GetMapTable = function() end })
    define("EJ_GetNumLoot", function()
        return 0
    end)

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
