-- spec/itemdata_spec.lua (M5-1, WKE-550)
-- The one item loader, driven through the stub: the client is asked once, the
-- two load events and the bounded timer are the two ways an answer arrives,
-- and a row that is handed another item never hears about the first one again.
--
-- The stub never answers by itself. A test that wants an item to arrive
-- registers it in `world.items` and fires the event the client would fire, so
-- "the client answered late" and "the client never answered" are both things
-- a test says rather than things it waits for.
local H = require("spec.helpers.addon")

-- Two placeholder items in Blizzard's documented shapes: GetItemInfoInstant
-- returns itemID, itemType, itemSubType, itemEquipLoc, icon, classID,
-- subClassID and GetItemInfo returns name, link, quality first (ItemDocumentation
-- under .luals/). No value here is claimed to be a real item's.
local ITEM_ID = 271528
local ICON = 7579164 -- the head slot's icon in the 2026-09-05 golden
local OTHER_ID = 272228

local function registerStatic(world, itemID, icon)
    world.items[itemID] = {
        instant = { itemID, "Armor", "Cloth", "INVTYPE_HEAD", icon, 4, 1 },
    }
end

local function registerLoaded(world, itemID, name, quality, level, icon)
    world.items[itemID] = {
        instant = { itemID, "Armor", "Cloth", "INVTYPE_HEAD", icon, 4, 1 },
        info = { name, "|Hitem:" .. itemID .. "|h[" .. name .. "]|h", quality, n = 3 },
        level = level,
    }
end

describe("ns.ItemData.Instant", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("answers with the icon and the slot before the item has loaded", function()
        registerStatic(world, ITEM_ID, ICON)
        local instant = ns.ItemData.Instant(ITEM_ID)
        assert.equal(ITEM_ID, instant.itemID)
        assert.equal(ICON, instant.icon)
        assert.equal("INVTYPE_HEAD", instant.equipLoc)
        -- QE Live's vocabulary, through the one table that maps it.
        assert.equal("Head", instant.slot)
        -- Static data: nothing was asked of the server to answer this.
        assert.equal(0, #world.itemDataRequests)
    end)

    it("says nothing about an item the client says nothing about", function()
        assert.is_nil(ns.ItemData.Instant(999999))
        assert.is_nil(ns.ItemData.Instant(nil))
    end)

    it("reads a name only once the client has one", function()
        registerStatic(world, ITEM_ID, ICON)
        assert.is_nil(ns.ItemData.Cached(ITEM_ID))
        assert.is_false(ns.ItemData.IsCached(ITEM_ID))
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        local cached = ns.ItemData.Cached(ITEM_ID)
        assert.equal("Placeholder Hood", cached.name)
        assert.equal(4, cached.quality)
        assert.equal(308, cached.itemLevel)
        assert.is_true(ns.ItemData.IsCached(ITEM_ID))
    end)

    it("reads an empty name as no name, which is Blizzard's own gate", function()
        world.items[ITEM_ID] = { info = { "", "|Hitem:" .. ITEM_ID .. "|h[]|h", 1, n = 3 } }
        assert.is_nil(ns.ItemData.Cached(ITEM_ID))
    end)
end)

describe("ns.ItemData.Request", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        registerStatic(world, ITEM_ID, ICON)
    end)

    after_each(function()
        H.unload()
    end)

    local function fired()
        local calls = {}
        return calls, function(itemID)
            calls[#calls + 1] = itemID
        end
    end

    it("asks the client once and fires once when it answers", function()
        local calls, callback = fired()
        local handle = ns.ItemData.Request(ITEM_ID, callback)
        assert.is_table(handle)
        assert.is_true(handle.requested)
        assert.same({ ITEM_ID }, world.itemDataRequests)
        assert.equal(0, #calls)

        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.same({ ITEM_ID }, calls)

        -- One episode, one answer: a second event for the same item finds
        -- nothing waiting and fires nothing.
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.equal(1, #calls)
        assert.equal(0, ns.ItemData.EpisodeCount())
    end)

    it("asks the client once for two rows about the same item", function()
        local firstCalls, first = fired()
        local secondCalls, second = fired()
        local a = ns.ItemData.Request(ITEM_ID, first)
        local b = ns.ItemData.Request(ITEM_ID, second)
        assert.is_true(a.requested)
        assert.is_false(b.requested)
        assert.equal(1, #world.itemDataRequests)
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("GET_ITEM_INFO_RECEIVED", ITEM_ID, true)
        assert.equal(1, #firstCalls)
        assert.equal(1, #secondCalls)
    end)

    it("never fires for a row that cancelled - the guard against a late answer", function()
        local calls, callback = fired()
        local handle = ns.ItemData.Request(ITEM_ID, callback)
        handle:Cancel()
        assert.equal(0, ns.ItemData.EpisodeCount())
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.equal(0, #calls)
    end)

    it("keeps the other row's request when one of two cancels", function()
        local firstCalls, first = fired()
        local secondCalls, second = fired()
        local a = ns.ItemData.Request(ITEM_ID, first)
        ns.ItemData.Request(ITEM_ID, second)
        a:Cancel()
        assert.equal(1, ns.ItemData.EpisodeCount())
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.equal(0, #firstCalls)
        assert.equal(1, #secondCalls)
    end)

    it("gives up after the bound and fires nothing at all", function()
        local calls, callback = fired()
        ns.ItemData.Request(ITEM_ID, callback)
        world.runTimers(ns.ItemData.WAIT_SECONDS * ns.ItemData.MAX_ATTEMPTS + 1)
        assert.equal(0, #calls)
        assert.equal(0, ns.ItemData.EpisodeCount())
        -- And the client answering after that changes nothing: nobody is
        -- waiting, so nothing is drawn on a row that has stopped asking.
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.equal(0, #calls)
    end)

    it("takes the timer as an occasion when the client fires nothing", function()
        local calls, callback = fired()
        ns.ItemData.Request(ITEM_ID, callback)
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        assert.equal(0, #calls)
        world.runTimers(ns.ItemData.WAIT_SECONDS)
        assert.same({ ITEM_ID }, calls)
    end)

    it("does not guess at an item whose load the client says failed", function()
        local calls, callback = fired()
        ns.ItemData.Request(ITEM_ID, callback)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, false)
        assert.equal(0, #calls)
        assert.equal(0, ns.ItemData.EpisodeCount())
    end)

    it("reads nothing in combat, and reads once combat ends", function()
        local calls, callback = fired()
        ns.ItemData.Request(ITEM_ID, callback)
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.inCombat = true
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.equal(0, #calls)
        assert.equal(1, ns.ItemData.EpisodeCount())
        world.inCombat = false
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.same({ ITEM_ID }, calls)
    end)

    it("listens only while something is waiting", function()
        local function listening()
            local frame = ns.ItemData.Listener()
            return frame ~= nil and frame.events["ITEM_DATA_LOAD_RESULT"] == true
        end
        assert.is_false(listening())
        local calls, callback = fired()
        ns.ItemData.Request(ITEM_ID, callback)
        assert.is_true(listening())
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.equal(1, #calls)
        assert.is_false(listening())
    end)

    it("keeps two items apart", function()
        registerStatic(world, OTHER_ID, 7866587)
        local firstCalls, first = fired()
        local secondCalls, second = fired()
        ns.ItemData.Request(ITEM_ID, first)
        ns.ItemData.Request(OTHER_ID, second)
        assert.equal(2, ns.ItemData.EpisodeCount())
        registerLoaded(world, OTHER_ID, "Placeholder Chain", 4, 308, 7866587)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", OTHER_ID, true)
        assert.equal(0, #firstCalls)
        assert.same({ OTHER_ID }, secondCalls)
        assert.equal(1, ns.ItemData.EpisodeCount())
    end)

    it("refuses a non-item and a caller with nothing to call", function()
        assert.is_nil(ns.ItemData.Request("not an id", function() end))
        assert.is_nil(ns.ItemData.Request(ITEM_ID, nil))
        assert.is_nil(ns.ItemData.Watch(nil, function() end))
        assert.equal(0, ns.ItemData.EpisodeCount())
    end)
end)
