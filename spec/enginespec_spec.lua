-- spec/enginespec_spec.lua (E-6, WKE-712)
-- The developer engine is spec-agnostic: it scores the primary stat and the
-- stat list of the spec's own entry in the weights file, the spec in use is
-- the client's current spec, and a spec the file does not carry rates nothing
-- and says one `Coming soon` line built from the file's own spec list. The
-- role gate (H-1, WKE-596) opens for the DEVELOPER surfaces only: in a
-- non-healer spec every player surface, the `inventory` capture and
-- `Companion.Refresh` keep their refusals with the developer switch on, and
-- the healer rating's stored keys are untouched by anything a Guardian session
-- does (ARCHITECTURE.md section 7, E-6: the capture-collision decision).
--
-- No number in this file is a game value. The weights are
-- spec/fixtures/engine/weights-synthetic.lua plus a SYNTHETIC Guardian (104)
-- and Feral (103) entry; the Agility key the stub answers is the global
-- string's name, which no committed transcript has read yet
-- (Lootpath/Modules/EngineStats.lua, STAT_KEYS).
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
local S = require("spec.helpers.serialize")
local Stats = dofile("spec/fixtures/engine/itemstats-synthetic.lua")

local WEIGHTS = "spec/fixtures/engine/weights-synthetic.lua"
local SV = "spec/fixtures/captures/Lootpath-20260916-162655.lua"
local CHAR = "Hotornot - Arthas"
local DRESSED = 3
-- What ns.Log puts before every chat line.
local PREFIX = "|cff66ccffLootpath|r: "

-- The client's primary-stat numbers as the stub defines them: Restoration
-- answers 4 and Guardian 2 in the owner's captures.
local GUARDIAN = { index = 3, id = 104, name = "Guardian", icon = 132276, role = "TANK", primaryStat = 2 }
local FERAL = { index = 2, id = 103, name = "Feral", icon = 132115, role = "DAMAGER", primaryStat = 2 }
-- A healing spec of another class, which the file does not carry.
local HOLY = { index = 1, id = 65, name = "Holy", icon = 135920, role = "HEALER", primaryStat = 4 }

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

-- A SYNTHETIC Agility entry: the Restoration entry's shape with Agility as
-- the primary stat and no leech.
local function agilityEntry(role)
    return {
        role = role,
        primaryStat = "agi",
        stats = { "agi", "haste", "crit", "mastery", "vers" },
        method = "synthetic",
        derivedAt = "never",
        Dungeon = {
            bands = {
                ["10+"] = {
                    baseValue = 1000,
                    weights = { agi = 1, haste = 14, crit = 22, mastery = 9, vers = 17 },
                    assumedFinish = {
                        gemVector = { crit = 10 },
                        enchantBySlot = { Finger = { haste = 5 }, Chest = { agi = 7 } },
                    },
                    assumedBuffs = { agi = 100 },
                },
            },
        },
        tiers = { [2057] = { [2] = { mult = 1.02 }, [4] = { mult = 1.04 } } },
    }
end

local function weights(extra)
    local w = dofile(WEIGHTS)
    for id, role in pairs(extra or {}) do
        w.specs[id] = agilityEntry(role)
    end
    return w
end

local function close(a, b)
    return math.abs(a - b) <= math.abs(b) * 1e-9
end

local function keysOf(items)
    local keys = {}
    for _, item in ipairs(items) do
        keys[#keys + 1] = item.key
    end
    table.sort(keys)
    return table.concat(keys, " ")
end

local function item(slot, stats)
    local v = { itemID = 990000 + #slot, key = "e6:" .. slot, slot = slot, level = 300, sockets = 0, gems = {} }
    for _, field in ipairs({ "int", "agi", "str", "haste", "crit", "mastery", "vers", "leech" }) do
        v[field] = 0
    end
    for k, x in pairs(stats) do
        v[k] = x
    end
    return v
end

describe("the engine scores the spec's own primary stat (E-6)", function()
    local ns
    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    -- Proven red by making SetValue value Intellect whatever the entry says
    -- (`w.int * totals.int`): the Agility set is worth the base alone and the
    -- Intellect set the most.
    it("values Agility for an Agility entry and ignores Intellect", function()
        local w = weights({ [103] = "DAMAGER" })
        local opts = { file = w, spec = 103, dr = "table", contentType = "Dungeon" }
        local agiSet = { item("Head", { agi = 500 }) }
        local intSet = { item("Head", { int = 500 }) }
        local bare = { item("Head", {}) }
        local agi = assert(ns.EngineScore.SetValue(agiSet, opts))
        local int = assert(ns.EngineScore.SetValue(intSet, opts))
        local none = assert(ns.EngineScore.SetValue(bare, opts))
        -- base 1000 plus the buffs' 100 Agility at weight 1.
        assert.equal(1100, none.value)
        assert.equal(1600, agi.value)
        assert.equal(none.value, int.value)
        assert.is_nil(int.totals.int)
        -- The Restoration entry in the same file still values Intellect only.
        local resto = { file = w, spec = 105, dr = "table", contentType = "Dungeon" }
        assert.is_true(
            assert(ns.EngineScore.SetValue(intSet, resto)).value > assert(ns.EngineScore.SetValue(agiSet, resto)).value
        )
        assert.equal(
            assert(ns.EngineScore.SetValue(bare, resto)).value,
            assert(ns.EngineScore.SetValue(agiSet, resto)).value
        )
    end)

    -- Proven red by taking ITEM_MOD_AGILITY_SHORT out of STAT_KEYS: the
    -- Agility lands in `other` and `agi` reads 0.
    it("reads Agility and Strength off an item, and keeps a mixed primary key apart", function()
        H.unload()
        local world
        ns, world = H.load()
        local link = "|cffa335ee|Hitem:990101::::::::90:103::4:1:12851:::::|h[Synthetic Agility Helm]|h|r"
        local stripped = Stats.strip(link)
        world.items[stripped] = { info = { "Synthetic Agility Helm", stripped, 4, 300, n = 18 }, level = 300 }
        world.itemStats[stripped] = {
            ITEM_MOD_AGILITY_SHORT = 410,
            ITEM_MOD_STRENGTH_SHORT = 7,
            ITEM_MOD_AGILITY_OR_INTELLECT_SHORT = 3,
            ITEM_MOD_HASTE_RATING_SHORT = 90,
        }
        local r = ns.EngineStats.ForLink(link)
        assert.is_true(r.ready)
        assert.equal(410, r.agi)
        assert.equal(7, r.str)
        assert.equal(0, r.int)
        assert.equal(90, r.haste)
        assert.same({ ITEM_MOD_AGILITY_OR_INTELLECT_SHORT = 3 }, r.other)
    end)

    -- Speed and avoidance convert through the client's CR_SPEED / CR_AVOIDANCE.
    -- Proven red by removing them from RATING_INDEX: SetValue answers "unrated".
    it("converts speed and avoidance through the client when a spec lists them", function()
        local w = weights()
        local entry = agilityEntry("TANK")
        entry.stats = { "agi", "haste", "avoidance", "speed" }
        entry.Dungeon.bands["10+"].weights = { agi = 1, haste = 10, avoidance = 3, speed = 1 }
        w.specs[104] = entry
        local asked = {}
        local opts = {
            file = w,
            spec = 104,
            contentType = "Dungeon",
            rating = function(index, value)
                asked[#asked + 1] = index
                return value / 100, false
            end,
        }
        assert(ns.EngineScore.SetValue({ item("Head", { agi = 10, avoidance = 200, speed = 100 }) }, opts))
        table.sort(asked)
        assert.same({ 14, 20, 21 }, asked)
    end)
end)

-- The search's outclassed-piece drop over a non-healer list (E-6). The
-- synthetic inventory below is enginesearch_spec.lua's shape in small: every
-- slot kind, with Agility as the spec's primary stat and a LARGE Intellect on
-- every piece that the Agility spec must ignore.
local function generator(seed)
    local s = seed * 7919 + 17
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return math.floor(s / 65536) % n
    end
end

local function agilityInventory(seed)
    local rand = generator(seed)
    local nextID = 980000 + seed * 1000
    local items = {}
    local function add(slot, extra)
        nextID = nextID + 1
        local it = {
            itemID = nextID,
            key = "agi:" .. nextID,
            slot = slot,
            level = 300,
            agi = 250 + rand(120),
            -- Intellect the Agility spec must not count: inversely tied to
            -- Agility, so an Intellect-led prune would keep the wrong pieces.
            int = 2000 - rand(1500),
            haste = 40 + rand(330),
            crit = 40 + rand(330),
            mastery = 40 + rand(330),
            vers = 40 + rand(330),
            sockets = rand(4) == 0 and 1 or 0,
            gems = {},
            ready = true,
        }
        for k, v in pairs(extra or {}) do
            it[k] = v
        end
        items[#items + 1] = it
        return it
    end
    for _, slot in ipairs({ "Head", "Shoulder", "Chest", "Hands", "Legs" }) do
        local plain = add(slot)
        local tier = add(slot, { setID = 2057 })
        for _, stat in ipairs({ "agi", "haste", "crit", "mastery", "vers" }) do
            tier[stat] = math.floor(plain[stat] * 0.93)
        end
        -- A spare every Agility stat below the plain piece's, with MORE
        -- Intellect than anything: outclassed for this spec, never for an
        -- Intellect list.
        if slot == "Head" or slot == "Legs" then
            local spare = add(slot, { int = 9000 })
            for _, stat in ipairs({ "agi", "haste", "crit", "mastery", "vers" }) do
                spare[stat] = math.max(0, plain[stat] - 1 - rand(20))
            end
            spare.sockets = 0
        end
    end
    add("Neck")
    add("Neck")
    for _, slot in ipairs({ "Back", "Wrist", "Waist", "Feet" }) do
        add(slot)
    end
    local u = add("Finger", { uniqueness = { isUnique = true } })
    local copy = deepcopy(u)
    copy.key = u.key .. ":copy"
    items[#items + 1] = copy
    add("Finger")
    for _ = 1, 3 do
        add("Trinket", { uniqueness = { isUnique = true } })
    end
    add("1H Weapon")
    add("Offhand")
    add("2H Weapon")
    return items
end

describe("the search prunes over the spec's own stat list (E-6)", function()
    local ns
    before_each(function()
        ns = H.load()
        ns.db.global.developer = { engine = true }
    end)
    after_each(function()
        H.unload()
    end)

    -- Proven red by pruning over Restoration's fixed six (the list this file
    -- held before E-6): the Intellect-heavy spares are kept, no Agility-only
    -- spare is outclassed, and the count below fails.
    it("drops what the Agility list outclasses and still equals brute force", function()
        local w = weights({ [103] = "DAMAGER" })
        local opts = { spec = 103, dr = "table", contentType = "Dungeon" }
        local droppedTotal = 0
        for _, seed in ipairs({ 1, 2, 3, 4, 5, 6 }) do
            local items = agilityInventory(seed)
            local c = assert(ns.EngineSearch.Candidates(items, w, opts))
            local spares = 0
            for _, d in ipairs(c.dropped) do
                if d.item.int == 9000 then
                    spares = spares + 1
                end
            end
            assert.equal(2, spares, "seed " .. seed)
            droppedTotal = droppedTotal + #c.dropped
            local best = assert(ns.EngineSearch.Best(items, w, opts))
            local brute = assert(ns.EngineSearch.BruteForce(items, w, opts))
            local unpruned = assert(ns.EngineSearch.BruteForce(items, w, {
                spec = 103,
                dr = "table",
                contentType = "Dungeon",
                prune = false,
                cap = 1000000,
            }))
            assert.is_true(close(best.value, brute.value), "seed " .. seed)
            assert.is_true(close(brute.value, unpruned.value), "seed " .. seed)
            assert.equal(keysOf(brute.items), keysOf(best.items), "seed " .. seed)
            io.stdout:write(
                string.format(
                    "\n[enginespec] agility seed %d: %d pieces, %d outclassed, search %d set values,"
                        .. " brute force %d sets; equal\n",
                    seed,
                    #items,
                    #c.dropped,
                    best.evaluations,
                    unpruned.sets
                )
            )
        end
        assert.is_true(droppedTotal >= 12)
    end)
end)

describe("the spec in use is the client's current spec (E-6)", function()
    local ns, world
    before_each(function()
        ns, world = H.load()
        ns.db.global.developer = { engine = true }
    end)
    after_each(function()
        H.unload()
    end)

    it("scores Restoration in Restoration", function()
        ns.engineWeights = weights()
        assert(ns.EngineScore.Load())
        local spec, entry = ns.EngineScore.SpecInUse()
        assert.equal(105, spec)
        assert.equal("int", entry.primaryStat)
    end)

    -- Proven red by keeping the default spec in SpecInUse (`spec or
    -- DEFAULT_SPEC`): Guardian is scored with Restoration's entry and no line
    -- is said.
    it("says one Coming soon line, from the file's own spec list, for a spec it does not carry", function()
        ns.engineWeights = weights()
        assert(ns.EngineScore.Load())
        world.spec = GUARDIAN
        local spec, entry, line = ns.EngineScore.SpecInUse()
        assert.is_nil(spec)
        assert.is_nil(entry)
        assert.equal("Coming soon for Guardian. Lootpath rates Restoration gear for now.", line)
        -- A second covered spec is named by the client too, in specID order.
        ns.engineWeights = weights({ [103] = "DAMAGER" })
        assert(ns.EngineScore.Load())
        world.spec = HOLY
        local _, _, two = ns.EngineScore.SpecInUse()
        assert.equal("Coming soon for Holy. Lootpath rates Feral and Restoration gear for now.", two)
        -- A client that names no spec rates nothing either.
        world.spec = nil
        local none, _, unnamed = ns.EngineScore.SpecInUse()
        assert.is_nil(none)
        assert.equal("Coming soon for this spec. Lootpath rates Feral and Restoration gear for now.", unnamed)
    end)

    -- Proven red by taking the client's primary-stat check out of SpecInUse:
    -- the Intellect entry is scored for an Agility spec.
    it("refuses an entry whose primary stat the client disagrees with", function()
        local w = weights({ [104] = "TANK" })
        w.specs[104].primaryStat = "int"
        w.specs[104].stats = { "int", "haste", "crit", "mastery", "vers" }
        ns.engineWeights = w
        assert(ns.EngineScore.Load())
        world.spec = GUARDIAN
        local spec, _, line, detail = ns.EngineScore.SpecInUse()
        assert.is_nil(spec)
        assert.equal(ns.EngineScore.TEXT.broken, line)
        assert.equal("weights file: specs[104].primaryStat is int; the client says agi", detail)
    end)
end)

-- The owner's own inventory of 2026-09-16 (inventory read 3) through the
-- SYNTHETIC stats rule, with every Intellect key answered as Agility - the
-- client an Agility spec is assumed to be until a capture reads it.
local function realWorld(extra)
    local ns, world = H.load()
    local db = R.load(SV)
    ns.db.char = deepcopy(db.char[CHAR])
    ns.db.global = deepcopy(db.global)
    ns.db.global.developer = { engine = true }
    R.inventory(world, R.snapshot("inventory", DRESSED, SV))
    ns.engineWeights = weights(extra)
    assert(ns.EngineScore.Load())
    local entries = {}
    for _, record in ipairs(ns.Inventory.Scan().records) do
        entries[#entries + 1] = { link = record.link, level = record.itemLevel }
    end
    Stats.install(world, entries)
    for _, stats in pairs(world.itemStats) do
        stats.ITEM_MOD_AGILITY_SHORT, stats.ITEM_MOD_INTELLECT_SHORT = stats.ITEM_MOD_INTELLECT_SHORT, nil
    end
    return ns, world
end

local function drive(world, done)
    local guard = 0
    while not done() do
        guard = guard + 1
        assert(guard < 100000, "runaway")
        for _, f in ipairs(world.frames) do
            if f.scripts.OnUpdate then
                f.scripts.OnUpdate(f, 0.016)
            end
        end
    end
end

-- What the healer rating is: the stored QE Live documents, the Upgrade Finder
-- documents, the compare's weeks, the inventory reads the companion rates, and
-- the character's own store.
local function healerKeys(ns)
    return S.serialize({
        qe = ns.db.global.qeImports,
        uf = ns.db.global.ufImports,
        ec = ns.db.global.engineCompare,
        inventory = ns.db.global.captures and ns.db.global.captures.inventory,
        char = ns.db.char,
    })
end

describe("the role gate opens for the developer engine only (E-6)", function()
    local ns, world
    after_each(function()
        H.unload()
    end)

    -- Proven red by scoring the default spec in EngineSearch.Command again:
    -- the header still prints but the primary line reads `int ... on 0 of 55`.
    it("runs engine best in Guardian when the file carries Guardian, scoring Agility, storing nothing", function()
        ns, world = realWorld({ [104] = "TANK" })
        world.spec = GUARDIAN
        local before = healerKeys(ns)
        world.printed = {}
        local run
        ns.EngineCompare.Command("best dungeon", function(r)
            run = r
        end)
        drive(world, function()
            return run ~= nil
        end)
        assert.equal(104, run.spec)
        local out = world.output()
        assert.truthy(out:find("engine best - weights synthetic, patch 12.1.0, derived never - Dungeon, band 10+", 1, true))
        assert.truthy(out:find("primary stat agi: on 55 of 55 pieces read.", 1, true))
        assert.is_true(run.result.value >= run.wornValue)
        assert.is_nil(out:lower():find("plan", 1, true))
        assert.equal(before, healerKeys(ns))
        for _, line in ipairs(world.printed) do
            io.stdout:write("\n[enginespec] guardian best: " .. line .. "\n")
        end
    end)

    it("says the Coming soon line for engine best in a spec the file does not carry, and searches nothing", function()
        ns, world = realWorld()
        world.spec = GUARDIAN
        world.printed = {}
        local called = false
        ns.EngineCompare.Command("best dungeon", function()
            called = true
        end)
        assert.is_false(called)
        assert.same({ PREFIX .. "Coming soon for Guardian. Lootpath rates Restoration gear for now." }, world.printed)
    end)

    -- Proven red by taking the gate out of EngineCompare.Run: the compare
    -- reads the Guardian set and scores QE Live's Restoration documents.
    it("refuses engine compare in a spec QE Live cannot rate, with one line, reading nothing", function()
        ns, world = realWorld({ [104] = "TANK" })
        world.spec = GUARDIAN
        local before = healerKeys(ns)
        world.printed = {}
        local asked = 0
        local real = C_Item.GetItemStats
        C_Item.GetItemStats = function(...)
            asked = asked + 1
            return real(...)
        end
        ns.EngineCompare.Command("compare dungeon", function()
            error("the compare ran")
        end)
        C_Item.GetItemStats = real
        assert.same({ PREFIX .. "engine compare needs an Upgrade Finder rating; there is none for Guardian." }, world.printed)
        assert.equal(0, asked)
        assert.equal(before, healerKeys(ns))
    end)

    -- Every H-1 refusal stands with the switch on and Guardian in the file.
    -- Proven red by keying Companion.Gate on the weights file (nil when the
    -- spec is covered): every assertion on a player surface below fails.
    it("keeps every player-surface refusal and the refresh's in Guardian with the switch on", function()
        ns, world = realWorld({ [104] = "TANK" })
        assert.is_true(ns.EngineCompare.Enabled())
        world.spec = GUARDIAN
        assert.is_table(ns.Companion.Gate())
        -- The window is the one Coming soon screen.
        local model = ns.UI.ComingSoonModel()
        assert.equal("Coming soon for Guardian.", model.title)
        -- The tooltip says nothing about any item.
        local anyLink = ns.Inventory.Scan().records[1].link
        assert.is_nil(ns.UI.Tooltip.Answer(anyLink))
        -- No bag mark.
        assert.is_false(ns.Glow.WantsLink(anyLink) == true)
        -- The load line is the gate's.
        assert.equal(
            "you're in Guardian; Lootpath rates healing gear for now - switch to Restoration and it's all here.",
            ns.Drift.LoadLine()
        )
        -- The inventory capture is refused, as H-1 built it.
        local result = ns.RunCapture("inventory")
        assert.is_false(result.ok)
        assert.truthy(result.reason:find("you're in Guardian; Lootpath rates healing gear", 1, true))
        -- And the refresh stops before it captures or reloads.
        local refresh = ns.Companion.Refresh()
        assert.is_false(refresh.ok)
        assert.equal(ns.Companion.GATE_REFRESH_REASON, refresh.reason)
        assert.equal(0, world.reloads)
    end)

    -- The design decision (ARCHITECTURE.md section 7, E-6): the inventory
    -- capture keeps its refusal and the engine reads the live inventory, so
    -- nothing a Guardian session does reaches the healer rating's keys.
    -- Proven red by letting the inventory capture store in Guardian (the gate
    -- out of Captures.lua's inventoryIsGated): the inventory list grows and the
    -- serialised keys differ.
    it("leaves the healer rating's stored keys untouched after a Guardian session", function()
        ns, world = realWorld({ [104] = "TANK" })
        local before = healerKeys(ns)
        world.spec = GUARDIAN
        ns.RunCapture("inventory")
        ns.Companion.Refresh()
        ns.EngineCompare.Command("compare dungeon")
        local run
        ns.EngineCompare.Command("best dungeon", function(r)
            run = r
        end)
        drive(world, function()
            return run ~= nil
        end)
        assert.equal(before, healerKeys(ns))
        -- Back in Restoration the healer gate is down and the rating is the one
        -- stored before.
        world.spec = { index = 4, id = 105, name = "Restoration", icon = 136041, role = "HEALER" }
        assert.is_nil(ns.Companion.Gate())
        assert.equal(before, healerKeys(ns))
    end)
end)
