-- spec/enginearrival_spec.lua (A-1, WKE-709)
-- Rate on arrival: a piece of gear that lands in the bags is rated by the
-- developer engine against the worn set when Drift next reads the bags - out
-- of combat, after Drift's debounce, after combat ends when it landed in one -
-- behind `db.global.developer.engine` only, as one chat line and the
-- developer panel's `Arrivals this session` block.
--
-- The detector (`ns.Drift.Arrivals`) is held on hand-made reads. The rating
-- runs over the owner's own 2026-09-16 SavedVariables (his dressed inventory,
-- read 3, his journal walk and his stored Upgrade Finder documents - the
-- compare's own fixture, spec/enginecompare_spec.lua) with the SYNTHETIC
-- weights and the SYNTHETIC item-stats rule, so every percent here measures
-- the plumbing, never an engine. The arrivals are two real journal drops of
-- that walk the character did not own: Unpossessed Skullsash (268227) and
-- Sentinel's Vitriolic Chain (268250), each at the level the walk lists and
-- the stored Dungeon +10 document rates (321).
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
local Stats = dofile("spec/fixtures/engine/itemstats-synthetic.lua")

local WEIGHTS = "spec/fixtures/engine/weights-synthetic.lua"
local SV = "spec/fixtures/captures/Lootpath-20260916-162655.lua"
local TODAY = "spec/fixtures/captures/Lootpath-20260914-171359.lua"
local CHAR = "Hotornot - Arthas"
local DRESSED = 3 -- 2026-09-16T15:29:53, 15 equipped
local SKULLSASH, CHAIN = 268227, 268250
local LEVEL = 321

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function deepcopy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = deepcopy(v)
    end
    return out
end

local function say(fmt, ...)
    io.stdout:write("\n[enginearrival] " .. string.format(fmt, ...) .. "\n")
end

-- ---------------------------------------------------------------------------
-- The detector, pure.

local function rec(key, itemID, location, slotIndex)
    return { key = key, itemID = itemID, location = location, slotIndex = slotIndex }
end

-- A read as Drift.Read builds one: the records, the worn slots, the bank flag.
local function read(records, bank)
    local slots = {}
    for _, r in ipairs(records) do
        if r.location == "equipped" then
            slots[r.slotIndex] = r.key
        end
    end
    return { records = records, slots = slots, bank = bank == true }
end

local function keysOf(list)
    local out = {}
    for _, r in ipairs(list) do
        out[#out + 1] = r.key
    end
    return out
end

describe("Drift.Arrivals, the detector", function()
    local ns
    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    local HELM = rec("1:1", 1, "equipped", 1)

    it("seeds on the first read and reports nothing", function()
        local found, known = ns.Drift.Arrivals(nil, read({ HELM, rec("2:1", 2, "bag") }))
        assert.same({}, found)
        assert.is_true(known.keys["2:1"])
    end)

    it("reports a new key in the bags once", function()
        local _, known = ns.Drift.Arrivals(nil, read({ HELM }))
        local found
        found, known = ns.Drift.Arrivals(known, read({ HELM, rec("3:1", 3, "bag") }))
        assert.same({ "3:1" }, keysOf(found))
        found = ns.Drift.Arrivals(known, read({ HELM, rec("3:1", 3, "bag") }))
        assert.same({}, found)
    end)

    it("does not report a piece moved from the bags to the bank and back", function()
        local _, known = ns.Drift.Arrivals(nil, read({ HELM, rec("4:1", 4, "bag") }, true))
        local found
        found, known = ns.Drift.Arrivals(known, read({ HELM, rec("4:1", 4, "bank") }, true))
        assert.same({}, found)
        found, known = ns.Drift.Arrivals(known, read({ HELM }, false))
        assert.same({}, found)
        found = ns.Drift.Arrivals(known, read({ HELM, rec("4:1", 4, "bag") }, true))
        assert.same({}, found)
    end)

    it("does not report a piece taken out of a bank no read has seen", function()
        local _, known = ns.Drift.Arrivals(nil, read({ HELM }, false))
        -- The bank opens and the piece comes out of it before any read sees it.
        local found
        found, known = ns.Drift.Arrivals(known, read({ HELM, rec("5:1", 5, "bag") }, true))
        assert.same({}, found)
        -- From then on the bank has been seen: a drop is a drop again.
        found = ns.Drift.Arrivals(known, read({ HELM, rec("5:1", 5, "bag"), rec("6:1", 6, "bag") }, true))
        assert.same({ "6:1" }, keysOf(found))
    end)

    it("does not report a crest or an upgrade: the same item under a new key", function()
        local _, known = ns.Drift.Arrivals(nil, read({ HELM, rec("7:12849", 7, "bag") }))
        local found
        found, known = ns.Drift.Arrivals(known, read({ HELM, rec("7:12850", 7, "bag") }))
        assert.same({}, found)
        -- Worn and crested, the same.
        found = ns.Drift.Arrivals(known, read({ rec("1:2", 1, "equipped", 1), rec("7:12850", 7, "bag") }))
        assert.same({}, found)
        -- A second copy beside the first is new gear.
        found = ns.Drift.Arrivals(known, read({ HELM, rec("7:12850", 7, "bag"), rec("7:12841", 7, "bag") }))
        assert.same({ "7:12841" }, keysOf(found))
    end)

    it("changes nothing on a read that is wearing nothing", function()
        local _, known = ns.Drift.Arrivals(nil, read({ HELM }))
        local found, after = ns.Drift.Arrivals(known, read({ rec("8:1", 8, "bag") }))
        assert.same({}, found)
        assert.equal(known, after)
    end)
end)

-- ---------------------------------------------------------------------------
-- The rating, over the owner's own state of 2026-09-16.

-- The client's own GetItemInfoInstant tuple for every walk row, out of the
-- journal snapshot itself (each row keeps `instant` beside `itemInfo`), so
-- a walk link put into the bags is scanned as the gear the client said it is.
local function registerInstants(world, data, seen)
    seen = seen or {}
    if type(data) ~= "table" or seen[data] then
        return
    end
    seen[data] = true
    local info = type(data.itemInfo) == "table" and data.itemInfo[1]
    if type(data.instant) == "table" and type(info) == "table" and type(info.link) == "string" then
        world.items[info.link] = world.items[info.link] or {}
        world.items[info.link].instant = data.instant
    end
    for _, v in pairs(data) do
        registerInstants(world, v, seen)
    end
end

local function fixtureWorld()
    local ns, world = H.load()
    local db = R.load(SV)
    ns.db.char = deepcopy(db.char[CHAR])
    ns.db.global = deepcopy(db.global)
    ns.db.global.developer = { engine = true }
    R.inventory(world, R.snapshot("inventory", DRESSED, SV))
    local weights = dofile(WEIGHTS)
    weights.specs[105].Raid = { bands = { all = deepcopy(weights.specs[105].Dungeon.bands["10+"]) } }
    ns.engineWeights = weights
    assert(ns.EngineScore.Load())
    local entries = {}
    for _, record in ipairs(ns.Inventory.Scan().records) do
        entries[#entries + 1] = { link = record.link, level = record.itemLevel }
    end
    local sources = ns.Journal:Build({ snapshot = ns.Companion.NewestSnapshot("journal"), db = false })
    local links = {}
    for itemID, list in pairs(sources) do
        for _, row in ipairs(list) do
            if row.link then
                entries[#entries + 1] = { link = row.link, level = row.itemLevel }
                if row.itemLevel == LEVEL and not links[itemID] then
                    links[itemID] = row.link
                end
            end
        end
    end
    Stats.install(world, entries)
    registerInstants(world, ns.Companion.NewestSnapshot("journal").data)
    return ns, world, links
end

local function intoBag(world, link, from, to)
    for bagIndex = from or 0, to or 4 do
        local bag = world.bags[bagIndex]
        for slotIndex = 1, (bag and bag.numSlots or 0) do
            if not bag.items[slotIndex] then
                bag.items[slotIndex] = { link = link }
                return bagIndex, slotIndex
            end
        end
    end
    error("no free slot")
end

local function outOf(world, link)
    for bagIndex, bag in pairs(world.bags) do
        for slotIndex, item in pairs(bag.items or {}) do
            if item.link == link then
                bag.items[slotIndex] = nil
                return bagIndex, slotIndex
            end
        end
    end
    return nil
end

-- What a bag event does: Drift's debounced read, then the rating.
local function bagEvent(world, n)
    for _ = 1, n or 1 do
        world.fireEvent("BAG_UPDATE_DELAYED")
    end
    world.runTimers(2)
end

local function engineLines(world)
    local out = {}
    for _, line in ipairs(world.printed) do
        if line:find("engine: ", 1, true) then
            out[#out + 1] = line
        end
    end
    return out
end

describe("Rate on arrival over the owner's 2026-09-16 gear", function()
    local ns, world, links
    before_each(function()
        ns, world, links = fixtureWorld()
        -- The session's first readable read: the detector's seed.
        bagEvent(world)
        world.printed = {}
    end)
    after_each(function()
        H.unload()
    end)

    it("reads the drops it says it reads", function()
        assert.is_string(links[SKULLSASH])
        assert.is_string(links[CHAIN])
        local document = ns.EngineCompare.ChooseDocument("Dungeon", nil)
        assert.equal(10, document.keyLevel)
        assert.equal(0.402, document.verdict.items[SKULLSASH .. "@" .. LEVEL].upgradePercent)
        assert.equal(0.37, document.verdict.items[CHAIN .. "@" .. LEVEL].upgradePercent)
        for _, record in ipairs(ns.Inventory.Scan().records) do
            assert.are_not.equal(SKULLSASH, record.itemID)
            assert.are_not.equal(CHAIN, record.itemID)
        end
    end)

    it("rates a piece that lands in the bags once, after the debounce, out of combat", function()
        intoBag(world, links[SKULLSASH])
        for _ = 1, 3 do
            world.fireEvent("BAG_UPDATE_DELAYED")
        end
        -- Inside the debounce nothing has been read.
        assert.equal(0, #ns.EngineCompare.arrivals)
        world.runTimers(2)
        assert.equal(1, #ns.EngineCompare.arrivals)
        local entry = ns.EngineCompare.arrivals[1]
        assert.equal("Waist", entry.slot)
        assert.equal(LEVEL, entry.level)
        assert.equal("10+", entry.band)
        assert.equal("Dungeon", entry.contentType)
        assert.equal(10, entry.keyLevel)
        assert.is_number(entry.ours)
        assert.is_number(entry.ms)
        -- QE Live's stored figure for the same id@level, read, not derived.
        assert.equal(0.402, entry.theirs)
        -- Ours is the Upgrade Finder percent over the worn set Drift read.
        local worn = {}
        for _, record in ipairs(ns.Inventory.Scan().records) do
            if record.location == "equipped" then
                worn[#worn + 1] = record
            end
        end
        local reads = {}
        for _, record in ipairs(worn) do
            reads[record.link] = ns.EngineStats.ForLink(record.link)
        end
        reads[links[SKULLSASH]] = ns.EngineStats.ForLink(links[SKULLSASH])
        local candidate = ns.EngineSearch.Vectors({ { link = links[SKULLSASH], slot = "Waist" } }, reads)[1]
        local direct = ns.EngineScore.UpgradePercent(ns.EngineSearch.Vectors(worn, reads), candidate, {
            assumedFinish = true,
            forceTier = true,
            contentType = "Dungeon",
            keyLevel = 10,
        })
        assert.equal(direct, entry.ours)
        local lines = engineLines(world)
        assert.same({
            ns.PREFIX .. string.format(
                "engine: %s arrived - %s over your worn set (band 10+)",
                links[SKULLSASH],
                string.format("%+.2f%%", entry.ours)
            ),
        }, lines)
        assert.is_nil(table.concat(lines):lower():find("plan", 1, true))
        say("chat: %s", lines[1])
        say(
            "arrival rated: ours %+.4f%% (synthetic), theirs %.3f (stored), %d worn pieces,"
                .. " rating %.3f ms (debugprofilestop)",
            entry.ours,
            entry.theirs,
            #worn,
            entry.ms
        )
        -- The next read sees nothing new: rated once.
        bagEvent(world, 2)
        assert.equal(1, #ns.EngineCompare.arrivals)
        assert.equal(1, #engineLines(world))
    end)

    -- One rating is under the stub clock's resolution, so the cost is read
    -- over many: the detector over Drift's whole read, and the rating over the
    -- 15 worn pieces, each by debugprofilestop (the stub's is os.clock).
    it("prints what the detector and one rating cost in this Lua", function()
        local N = 200
        intoBag(world, links[SKULLSASH])
        local scan = ns.Inventory.Scan()
        local r = { records = scan.records, slots = ns.Drift.SlotSet(scan.records), bank = false }
        local _, known = ns.Drift.Arrivals(nil, { records = {}, slots = r.slots })
        local t0 = debugprofilestop()
        for _ = 1, N do
            ns.Drift.Arrivals(known, r)
        end
        local detectMs = (debugprofilestop() - t0) / N
        local worn, reads = {}, {}
        for _, record in ipairs(scan.records) do
            reads[record.link] = ns.EngineStats.ForLink(record.link)
            if record.location == "equipped" then
                worn[#worn + 1] = record
            end
        end
        local wornItems = ns.EngineSearch.Vectors(worn, reads)
        local item = ns.EngineSearch.Vectors({ { link = links[SKULLSASH], slot = "Waist" } }, reads)[1]
        local band = { contentType = "Dungeon", keyLevel = 10, spec = 105, file = ns.EngineScore.file }
        t0 = debugprofilestop()
        local entry
        for _ = 1, N do
            entry = ns.EngineCompare.RateArrival(item, wornItems, band)
        end
        local rateMs = (debugprofilestop() - t0) / N
        assert.is_number(entry.ours)
        say(
            "cost over %d runs: detector %.4f ms per read of %d records, every one new (the upper bound);"
                .. " rating %.4f ms per arrival over %d worn pieces",
            N,
            detectMs,
            #scan.records,
            rateMs,
            #wornItems
        )
    end)

    it("waits for the end of combat when the piece lands in a fight", function()
        world.inCombat = true
        intoBag(world, links[SKULLSASH])
        bagEvent(world, 2)
        assert.equal(0, #ns.EngineCompare.arrivals)
        assert.same({}, engineLines(world))
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        world.runTimers(2)
        assert.equal(1, #ns.EngineCompare.arrivals)
        assert.equal(1, #engineLines(world))
    end)

    it("holds a read that reaches the rating in combat until PLAYER_REGEN_ENABLED", function()
        intoBag(world, links[SKULLSASH])
        local scan = ns.Inventory.Scan()
        local r = {
            keys = ns.Drift.KeySet(scan.records),
            slots = ns.Drift.SlotSet(scan.records),
            records = scan.records,
            bank = false,
        }
        -- Nothing is read in combat: the item reads are never even asked for.
        local resolve = ns.EngineCompare.Resolve
        ns.EngineCompare.Resolve = function(...)
            assert.is_false(world.inCombat == true, "Resolve reached in combat")
            return resolve(...)
        end
        world.inCombat = true
        ns.EngineCompare.ObserveRead(r)
        assert.equal(0, #ns.EngineCompare.arrivals)
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        assert.equal(1, #ns.EngineCompare.arrivals)
        assert.equal(1, #engineLines(world))
    end)

    it("holds reads that come back in combat until PLAYER_REGEN_ENABLED", function()
        -- The item reads finish after a fight has started (a link the client
        -- had to fetch): the batch waits for the fight to end, then rates.
        local resolve = ns.EngineCompare.Resolve
        local calls = 0
        ns.EngineCompare.Resolve = function(links, done)
            calls = calls + 1
            if calls == 1 then
                world.inCombat = true
                return done({}, #links, 0)
            end
            return resolve(links, done)
        end
        intoBag(world, links[SKULLSASH])
        bagEvent(world)
        assert.equal(0, #ns.EngineCompare.arrivals)
        assert.same({}, engineLines(world))
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        assert.equal(2, calls)
        assert.equal(1, #ns.EngineCompare.arrivals)
        assert.is_number(ns.EngineCompare.arrivals[1].ours)
        assert.equal(1, #engineLines(world))
    end)

    it("does not rate a piece moved between the bags and the bank", function()
        world.bankOpen = true
        world.bags[6] = { numSlots = 8, items = {} }
        bagEvent(world) -- the bank is read
        -- A piece he owned, into the bank, then back.
        local owned
        for _, record in ipairs(ns.Inventory.Scan().records) do
            if record.location == "bag" then
                owned = record.link
                break
            end
        end
        assert.is_string(owned)
        outOf(world, owned)
        intoBag(world, owned, 6, 6)
        bagEvent(world)
        outOf(world, owned)
        intoBag(world, owned)
        bagEvent(world)
        assert.equal(0, #ns.EngineCompare.arrivals)
        assert.same({}, engineLines(world))
    end)

    it("does not rate a piece taken out of a bank no read had seen", function()
        -- The chain sat in the bank; the bank was never open this session.
        world.bags[6] = { numSlots = 8, items = { [1] = { link = links[CHAIN] } } }
        bagEvent(world)
        world.bankOpen = true
        outOf(world, links[CHAIN])
        intoBag(world, links[CHAIN])
        bagEvent(world)
        assert.equal(0, #ns.EngineCompare.arrivals)
        -- A real drop after that is rated.
        intoBag(world, links[SKULLSASH])
        bagEvent(world)
        assert.equal(1, #ns.EngineCompare.arrivals)
    end)

    it("skips what is not gear, and gear that is not for this spec", function()
        local hearthstone
        for _, slot in ipairs(R.snapshot("glow", 1, TODAY).data.slots) do
            if slot.key == "6948" then
                hearthstone = slot.link
            end
        end
        assert.is_string(hearthstone)
        intoBag(world, hearthstone)
        bagEvent(world)
        -- Plate for a Druid: the client's spec list names no spec of his.
        world.itemSpecs[links[SKULLSASH]] = { 65, 66, 70 }
        intoBag(world, links[SKULLSASH])
        bagEvent(world)
        assert.equal(0, #ns.EngineCompare.arrivals)
        assert.same({}, engineLines(world))
        -- The same piece with his spec on its list is rated.
        world.itemSpecs[links[CHAIN]] = { 105 }
        intoBag(world, links[CHAIN])
        bagEvent(world)
        assert.equal(1, #ns.EngineCompare.arrivals)
    end)

    it("with the switch off says nothing, keeps nothing and builds nothing", function()
        ns.db.global.developer = nil
        intoBag(world, links[SKULLSASH])
        bagEvent(world)
        assert.equal(0, #ns.EngineCompare.arrivals)
        assert.same({}, engineLines(world))
        assert.is_nil(ns.EngineDevPanel.frame)
        assert.is_nil(ns.EngineDevPanel.Refresh())
        -- Turned on, the next read is a seed: what landed while it was off
        -- is not rated in a flood.
        ns.db.global.developer = { engine = true }
        bagEvent(world)
        assert.equal(0, #ns.EngineCompare.arrivals)
        intoBag(world, links[CHAIN])
        bagEvent(world)
        assert.equal(1, #ns.EngineCompare.arrivals)
        -- `engine off` forgets them.
        ns.HandleSlash("engine off")
        assert.equal(0, #ns.EngineCompare.arrivals)
    end)

    it("rates nothing on a refused weights file and says the refusal once", function()
        ns.engineWeights.patch = "12.0.0"
        ns.EngineScore.file = nil
        intoBag(world, links[SKULLSASH])
        bagEvent(world)
        intoBag(world, links[CHAIN])
        bagEvent(world)
        assert.equal(0, #ns.EngineCompare.arrivals)
        assert.same({}, engineLines(world))
        local refusal = "Update Lootpath - its ratings are for 12.0.0, you're on 12.1.0."
        local said = 0
        for _, line in ipairs(world.printed) do
            if line == ns.PREFIX .. refusal then
                said = said + 1
            end
        end
        assert.equal(1, said)
        assert.equal(refusal, ns.EngineCompare.arrivalRefusal)
    end)

    it("rates in the band of the session's last compare or best", function()
        ns.EngineCompare.lastAsked = { contentType = "Raid" }
        intoBag(world, links[SKULLSASH])
        bagEvent(world)
        local entry = ns.EngineCompare.arrivals[1]
        assert.equal("Raid", entry.contentType)
        assert.equal("all", entry.band)
        assert.truthy(engineLines(world)[1]:find("(band all)", 1, true))
    end)

    it("keeps the newest pieces first, at most ARRIVALS_KEPT", function()
        intoBag(world, links[SKULLSASH])
        bagEvent(world)
        intoBag(world, links[CHAIN])
        bagEvent(world)
        assert.equal(CHAIN, tonumber(ns.EngineCompare.arrivals[1].key:match("^(%d+)")))
        assert.equal(SKULLSASH, tonumber(ns.EngineCompare.arrivals[2].key:match("^(%d+)")))
        assert.equal(10, ns.EngineCompare.ARRIVALS_KEPT)
    end)
end)

-- ---------------------------------------------------------------------------
-- The developer panel's block.

describe("The arrivals block in the developer panel", function()
    local ns
    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    -- Newest first, and ours deliberately out of order: a sort by ours would
    -- move them.
    local ARRIVALS = {
        {
            key = "3:1",
            name = "Third",
            slot = "Neck",
            level = 321,
            contentType = "Dungeon",
            band = "10+",
            ours = 0.2,
            theirs = 0.37,
            ms = 0.5,
        },
        {
            key = "2:1",
            name = "Second",
            slot = "Waist",
            level = 321,
            contentType = "Dungeon",
            band = "10+",
            ours = 1.4,
            theirs = 0.402,
            ms = 0.4,
        },
        {
            key = "1:1",
            name = "First",
            slot = "Trinket",
            level = 318,
            contentType = "Dungeon",
            why = "trinket not in the effects table",
        },
        {
            key = "0:1",
            name = "Zeroth",
            slot = "Head",
            level = 308,
            contentType = "Dungeon",
            band = "10+",
            ours = -0.6,
            ms = 0.3,
        },
    }

    local function rowsOf(model)
        local out = {}
        for _, row in ipairs(model.rows) do
            if row.layout == "arrivals" and row.kind == "row" then
                out[#out + 1] = row
            end
        end
        return out
    end

    it("shows each piece once, in the order it arrived, never by ours", function()
        local model = ns.EngineDevPanel.Model({}, nil, { charKey = CHAR, arrivals = ARRIVALS })
        local rows = rowsOf(model)
        assert.equal(#ARRIVALS, #rows)
        for i, row in ipairs(rows) do
            assert.equal(i, row.arrivalIndex)
            assert.equal(ARRIVALS[i].key, row.key)
        end
        local ours = {}
        for _, row in ipairs(rows) do
            if row.ours then
                ours[#ours + 1] = row.ours
            end
        end
        local sorted = deepcopy(ours)
        table.sort(sorted, function(a, b)
            return a > b
        end)
        assert.are_not.same(sorted, ours)
        assert.same({ "Third", "Neck", "321", "Dungeon 10+", "+0.200", "0.370", "0.50", "" }, rows[1].cells)
        assert.same(
            { "First", "Trinket", "318", "-", "-", "-", "-", "trinket not in the effects table" },
            rows[3].cells
        )
        assert.same({ "Zeroth", "Head", "308", "Dungeon 10+", "-0.600", "-", "0.30", "" }, rows[4].cells)
    end)

    it("keeps ours and theirs in two cells, never one string", function()
        local model = ns.EngineDevPanel.Model({}, nil, { charKey = CHAR, arrivals = ARRIVALS })
        assert.are_not.equal(ns.EngineDevPanel.ARRIVAL_OURS_CELL, ns.EngineDevPanel.ARRIVAL_THEIRS_CELL)
        local checked = 0
        for _, row in ipairs(rowsOf(model)) do
            if row.ours and row.theirs then
                checked = checked + 1
                local o = row.cells[ns.EngineDevPanel.ARRIVAL_OURS_CELL]
                local t = row.cells[ns.EngineDevPanel.ARRIVAL_THEIRS_CELL]
                assert.equal(string.format("%+.3f", row.ours), o)
                assert.equal(string.format("%.3f", row.theirs), t)
                for _, cell in ipairs(row.cells) do
                    assert.is_false(cell:find(o, 1, true) ~= nil and cell:find(t, 1, true) ~= nil, cell)
                end
            end
        end
        assert.equal(2, checked)
    end)

    it("draws no block without arrivals given, and says what fills an empty one", function()
        local lines = ns.EngineDevPanel.Lines(ns.EngineDevPanel.Model({}, nil, { charKey = CHAR }))
        for _, text in ipairs(lines) do
            assert.are_not.equal("Arrivals this session", text)
        end
        lines = ns.EngineDevPanel.Lines(ns.EngineDevPanel.Model({}, nil, { charKey = CHAR, arrivals = {} }))
        local at
        for i, text in ipairs(lines) do
            if text == "Arrivals this session" then
                at = i
            end
        end
        assert.is_number(at)
        assert.equal("Loot or buy a piece to fill this. It is kept until you reload.", lines[at + 1])
        assert.equal("Last best set this session", lines[at + 2])
    end)

    it("draws the session's arrivals in the open panel behind the switch only", function()
        ns.db.global.developer = { engine = true }
        ns.EngineCompare.arrivals = deepcopy(ARRIVALS)
        ns.HandleSlash("engine")
        local frame = ns.EngineDevPanel.frame
        local found = false
        for _, text in ipairs(frame.lines) do
            if text == "Arrivals this session" then
                found = true
            end
        end
        assert.is_true(found)
        ns.HandleSlash("engine off")
        assert.is_false(frame:IsShown())
        assert.same({}, ns.EngineCompare.arrivals)
    end)
end)

-- ---------------------------------------------------------------------------
-- On no player surface.

describe("Rate on arrival on screen", function()
    it("is read by no UI file but the developer panel", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") and f ~= "UI/EngineDevPanel.lua" then
                local text = readAll("Lootpath/" .. f)
                for _, name in ipairs({ "arrivals", "RateArrival", "Drift.Arrivals", "Drift.Observe", "lastAsked" }) do
                    if text:find(name, 1, true) then
                        readers[#readers + 1] = f .. " " .. name
                    end
                end
            end
        end
        assert.same({}, readers)
    end)

    it("has one observer of Drift's read, the developer engine's", function()
        local ns = H.load()
        assert.equal(1, #ns.Drift.observers)
        H.unload()
    end)
end)
