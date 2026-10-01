-- spec/enginecompare_spec.lua (E-0d, WKE-673)
-- ns.EngineCompare: the metrics on hand-made rows, the week key, the store
-- bounded at twelve weeks, the bar's verdicts, the `not on` line, and the
-- whole command over the owner's own 2026-09-16 SavedVariables (its stored
-- Upgrade Finder documents, its Top Gear pass-1 documents with their pools,
-- its dressed inventory read and its journal walk) - with the synthetic
-- weights and the synthetic item-stats rule, so every figure the fixture run
-- prints measures the plumbing and nothing else. Also the join over the two
-- committed Upgrade Finder exports, a run that serialises byte-identical twice,
-- and a guard that no rating store and no journal cache is written.
--
-- Since E-0f (WKE-676) the stub answers in the client's own shapes (the keys,
-- an empty table for every gem link, diminishing returns in the rating
-- conversion), and the compare's journal half is held against the client's
-- answers in spec/fixtures/engine/itemstats-real.lua: a walk link reads at the
-- level the client gives the link, which is not always the level the walk
-- listed it at. The 2026-09-16 run keeps the synthetic stats rule because the
-- transcript reads 80 links of 2026-10-01, not that day's walk and inventory.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
local S = require("spec.helpers.serialize")
local Stats = dofile("spec/fixtures/engine/itemstats-synthetic.lua")
local Real = dofile("spec/fixtures/engine/itemstats-real.lua")

local WEIGHTS = "spec/fixtures/engine/weights-synthetic.lua"
local FITTED = "spec/fixtures/engine/weights-fitted-shape.lua"
local SHIPPED = "Lootpath/Data/EngineWeights.lua"
local SV = "spec/fixtures/captures/Lootpath-20260916-162655.lua"
local CHAR = "Hotornot - Arthas"
local DRESSED = 3 -- 2026-09-16T15:29:53, 15 equipped (spec/drift_spec.lua's)
local UF_DUNGEON_10 = "spec/fixtures/qe/qe-upgradefinder-Hotornot-wyharestkdyr.json"
local UF_RAID = "spec/fixtures/qe/qe-upgradefinder-Hotornot-ynfzbppepnzw.json"

-- 2026-09-16T20:30:00Z, and the US reset after it, 2026-09-22T15:00:00Z.
local NOW = 1789590600
local NEXT_RESET = 1790089200

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

local function rowsOf(pairs_)
    local rows = {}
    for i, p in ipairs(pairs_) do
        rows[i] = { key = "k" .. string.format("%02d", i), slot = p[3] or "Head", ours = p[1], theirs = p[2] }
    end
    return rows
end

describe("EngineCompare metrics on hand-made rows", function()
    local ns
    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    it("ranks ties by the mean of their positions", function()
        assert.same({ 1, 2.5, 2.5, 4 }, ns.EngineCompare.Ranks({ 1, 5, 5, 9 }))
        assert.same({ 3, 1, 2 }, ns.EngineCompare.Ranks({ 0.3, -1, 0 }))
    end)

    it("gives rho 1 for the same order, -1 for a reversed list", function()
        assert.equal(1, ns.EngineCompare.Spearman({ 1, 2, 3, 4, 5 }, { 10, 20, 30, 40, 50 }))
        assert.equal(-1, ns.EngineCompare.Spearman({ 1, 2, 3, 4, 5 }, { 5, 4, 3, 2, 1 }))
    end)

    it("does not compute rho for a tie-only list or under five rows", function()
        assert.is_nil(ns.EngineCompare.Spearman({ 1, 2, 3, 4, 5 }, { 7, 7, 7, 7, 7 }))
        assert.is_nil(ns.EngineCompare.Spearman({ 2, 2, 2, 2, 2 }, { 1, 2, 3, 4, 5 }))
        assert.is_nil(ns.EngineCompare.Spearman({ 1, 2, 3, 4 }, { 1, 2, 3, 4 }))
    end)

    it("uses average ranks: a tied pair moves rho off 1 by the textbook amount", function()
        -- ranks x 1..5, y 1, 2.5, 2.5, 4, 5: Pearson on ranks = 9.5 / sqrt(10 * 9.5)
        local rho = ns.EngineCompare.Spearman({ 1, 2, 3, 4, 5 }, { 1, 2, 2, 4, 5 })
        assert.is_true(math.abs(rho - 9.5 / math.sqrt(95)) < 1e-12)
    end)

    it("fits k on a known scale and leaves MAE after k at zero", function()
        local ours = { 0.2, -0.4, 1.0, 0.6 }
        local theirs = {}
        for i, x in ipairs(ours) do
            theirs[i] = 1.5 * x
        end
        local k = ns.EngineCompare.Scale(ours, theirs)
        assert.is_true(math.abs(k - 1.5) < 1e-12)
        assert.is_true(ns.EngineCompare.MAE(ours, theirs, k) < 1e-12)
        assert.is_true(math.abs(ns.EngineCompare.MAE(ours, theirs) - 0.5 * (0.2 + 0.4 + 1.0 + 0.6) / 4) < 1e-12)
        assert.is_nil(ns.EngineCompare.Scale({ 0, 0 }, { 1, 2 }))
    end)

    it("counts signs outside the dead zone only", function()
        local share, counted = ns.EngineCompare.Sign({ 0.5, -0.5, 0.3, 9 }, { 0.4, 0.2, 0.05, -0.09 })
        assert.equal(2, counted) -- 0.05 and -0.09 are ties
        assert.equal(0.5, share)
        assert.is_nil((ns.EngineCompare.Sign({ 1 }, { 0.01 })))
    end)

    it("calls top-1 within 0.1 points and top-3 by their order", function()
        local first, three = ns.EngineCompare.TopPick(rowsOf({ { 5, 1.00 }, { 1, 1.05 }, { 0, 0.2 } }))
        assert.is_true(first)
        assert.is_true(three)
        first, three = ns.EngineCompare.TopPick(rowsOf({ { 5, 0.1 }, { 1, 1.0 }, { 0, 0.9 }, { 0, 0.8 }, { 0, 0.7 } }))
        assert.is_false(first)
        assert.is_false(three)
        assert.is_nil(ns.EngineCompare.TopPick(rowsOf({ { 1, 1 } })))
    end)

    it("reports rho per slot, its median and minimum, and n", function()
        local rows = rowsOf({
            { 1, 1, "Head" },
            { 2, 2, "Head" },
            { 3, 3, "Head" },
            { 4, 4, "Head" },
            { 5, 5, "Head" },
            { 1, 5, "Legs" },
            { 2, 4, "Legs" },
            { 3, 3, "Legs" },
            { 4, 2, "Legs" },
            { 5, 1, "Legs" },
        })
        local m = ns.EngineCompare.Metrics(rows)
        assert.equal(10, m.n)
        assert.equal(1, m.rhoBySlot.Head)
        assert.equal(-1, m.rhoBySlot.Legs)
        assert.equal(0, m.rhoMedian)
        assert.equal(-1, m.rhoMin)
        assert.equal(2, m.groups)
        assert.equal(0.5, m.top1)
        assert.is_false(ns.EngineCompare.Passes(m))
    end)

    it("passes the per-run bar only when every figure clears it", function()
        local good = { rhoMedian = 0.98, rhoMin = 0.95, top1 = 1, sign = 1, maeK = 0.05 }
        assert.is_true(ns.EngineCompare.Passes(good))
        for field, bad in pairs({ rhoMedian = 0.96, rhoMin = 0.89, top1 = 0.8, sign = 0.9, maeK = 0.08 }) do
            local m = deepcopy(good)
            m[field] = bad
            assert.is_false(ns.EngineCompare.Passes(m), field)
        end
    end)

    it("classes slots, trinkets apart", function()
        local C = ns.EngineCompare.CLASS_OF_SLOT
        assert.equal("tier", C.Head)
        assert.equal("armour", C.Wrist)
        assert.equal("jewellery", C.Finger)
        assert.equal("weapon", C["2H Weapon"])
        assert.equal("trinket", C.Trinket)
    end)

    it("reads both sign constants rather than its own arithmetic", function()
        local text = readAll("Lootpath/Modules/EngineCompare.lua")
        assert.truthy(text:find("UFImport.UPGRADE_BETTER_PERCENT_SIGN", 1, true))
        assert.truthy(text:find("QEImport.ALT_WORSE_SCORE_PERCENT_SIGN", 1, true))
        assert.falsy(text:find("/ 1.5", 1, true))
    end)
end)

-- A hand-made compare: two worn pieces, three drops, three Top Gear swaps, the
-- synthetic weights. Every vector is written here, so each sign is known.
describe("EngineCompare.Compute on hand-made inputs", function()
    local ns
    local function vec(stats)
        local v = { ready = true, sockets = 0, gems = {} }
        for _, k in ipairs({ "int", "haste", "crit", "mastery", "vers", "leech" }) do
            v[k] = 0
        end
        for k, x in pairs(stats) do
            v[k] = x
        end
        return v
    end
    local function alt(scorePercent, itemID, slot)
        return {
            scorePercent = scorePercent,
            items = { { key = itemID .. ":1", itemID = itemID, bonusIDs = { 1 }, slot = slot } },
        }
    end
    local function drop(key, dropType, percent)
        return { key = key, dropType = dropType, upgradePercent = percent, sources = {} }
    end
    local function inputs()
        return {
            contentType = "Dungeon",
            file = dofile(WEIGHTS),
            worn = { { link = "worn-head", slot = "Head" }, { link = "worn-wrist", slot = "Wrist" } },
            owned = {
                ["1:1"] = { link = "worn-head" },
                ["2:1"] = { link = "worn-wrist" },
                ["3:1"] = { link = "bag-head-better" },
                ["4:1"] = { link = "bag-wrist-worse" },
                ["5:1"] = { link = "bag-head-elsewhere" },
            },
            reads = {
                ["worn-head"] = vec({ int = 100 }),
                ["worn-wrist"] = vec({ int = 50 }),
                ["bag-head-better"] = vec({ int = 200 }),
                ["bag-wrist-worse"] = vec({ int = 10 }),
                ["bag-head-elsewhere"] = vec({ int = 300 }),
                ["drop-head"] = vec({ int = 150 }),
                ["drop-wrist"] = vec({ int = 40 }),
                ["drop-head-effect"] = vec({ int = 60, itemID = 271875 }), -- Gaze of the Coiled Watcher, in the table
            },
            journalByKey = {
                ["10@300"] = { link = "drop-head", slot = "Head" },
                ["11@300"] = { link = "drop-wrist", slot = "Wrist" },
                ["12@300"] = { link = "drop-head-effect", slot = "Head" },
            },
            document = {
                keyLevel = 10,
                verdict = {
                    exportedAt = "x",
                    order = { "10@300", "11@300", "12@300", "13@300" },
                    items = {
                        ["10@300"] = drop("10@300", "drop", 0.8),
                        ["11@300"] = drop("11@300", "drop", -0.3),
                        ["12@300"] = drop("12@300", "drop", 0.2),
                        ["13@300"] = drop("13@300", "max", 1.0),
                    },
                },
            },
            topGear = {
                exportedAt = "y",
                considered = { { itemID = 3, bonusIDs = { 1 } }, { itemID = 4, bonusIDs = { 1 } } },
                topSet = {
                    order = { "1:1", "2:1" },
                    items = { ["1:1"] = { slot = "Head" }, ["2:1"] = { slot = "Wrist" } },
                },
                -- scorePercent positive: the alternative is WORSE.
                alternatives = { alt(-0.5, 3, "Head"), alt(0.4, 4, "Wrist"), alt(-0.9, 5, "Head") },
            },
        }
    end

    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    it("reads both columns as positive = better, and counts what it leaves out", function()
        local result = ns.EngineCompare.Compute(inputs())
        local uf = result.uf
        assert.equal(3, uf.joined)
        assert.equal(1, uf.other) -- the `max` listing
        assert.equal(1, uf.notRated) -- the drop the effects table carries
        assert.same({ { key = "12@300", names = "Gaze of the Coiled Watcher" } }, uf.notRatedItems)
        assert.equal(0, uf.generic)
        assert.equal(0, uf.unknown)
        assert.equal(2, #uf.rows)
        local byKey = {}
        for _, row in ipairs(uf.rows) do
            byKey[row.key] = row
        end
        assert.is_true(byKey["10@300"].ours > 0)
        assert.equal(0.8, byKey["10@300"].theirs)
        assert.is_true(byKey["11@300"].ours < 0)
        assert.equal(-0.3, byKey["11@300"].theirs)
        assert.equal("tier", byKey["10@300"].class)
        assert.equal("armour", byKey["11@300"].class)

        local tg = result.tg
        assert.equal(1, tg.notInPool) -- item 5 is not in the pass's pool
        assert.equal(2, #tg.rows)
        for _, row in ipairs(tg.rows) do
            byKey[row.key] = row
        end
        assert.is_true(byKey["3:1"].ours > 0)
        assert.equal(0.5, byKey["3:1"].theirs)
        assert.is_true(byKey["4:1"].ours < 0)
        assert.equal(-0.4, byKey["4:1"].theirs)
        assert.is_true(tg.topValue > 0)
        assert.equal(tg.topValue, tg.wornValue) -- the best set here is the worn set
    end)
end)

describe("EngineCompare week, store and verdicts", function()
    local ns
    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    it("keys a week by the reset clock's period start", function()
        assert.equal("2026-09-15", ns.EngineCompare.WeekKey(NOW, NEXT_RESET - NOW))
        -- Seconds of jitter on either side land on the same day.
        assert.equal("2026-09-15", ns.EngineCompare.WeekKey(NOW + 7, NEXT_RESET - NOW - 3))
        -- One second after the reset is the next week.
        assert.equal("2026-09-22", ns.EngineCompare.WeekKey(NEXT_RESET + 1, 604799))
        assert.is_nil(ns.EngineCompare.WeekKey(NOW, nil))
    end)

    it("keeps twelve weeks and replaces a run of the same week and document", function()
        local store = {}
        for day = 1, 14 do
            ns.EngineCompare.Store(store, string.format("2026-01-%02d", day), "c", "Dungeon", 10, { n = day })
        end
        local weeks = {}
        for k in pairs(store) do
            weeks[#weeks + 1] = k
        end
        table.sort(weeks)
        assert.equal(12, #weeks)
        assert.equal("2026-01-03", weeks[1])
        ns.EngineCompare.Store(store, "2026-01-14", "c", "Dungeon", 10, { n = 99 })
        assert.equal(99, store["2026-01-14"].c.Dungeon[10].n)
        assert.equal(12, #weeks)
    end)

    local PASS = { n = 12, rhoMedian = 0.99, rhoMin = 0.95, top1 = 1, sign = 1, maeK = 0.01, k = 1.0 }
    local FAIL = { n = 12, rhoMedian = 0.5, rhoMin = 0.2, top1 = 0.5, sign = 0.5, maeK = 0.4, k = 1.0 }

    local function week(store, key, dungeon, raid)
        ns.EngineCompare.Store(store, key, "c", "Dungeon", 10, { metrics = { tier = dungeon } })
        if raid then
            ns.EngineCompare.Store(store, key, "c", "Raid", 10, { metrics = { tier = raid } })
        end
    end

    it("says N/3 weeks, then ready, and no when the latest week fails", function()
        local store = {}
        week(store, "2026-09-01", PASS, PASS)
        assert.equal("1/3 weeks", ns.EngineCompare.Verdicts(store, "c").tier)
        week(store, "2026-09-08", PASS, nil) -- one content type only: partial
        assert.equal("1/3 weeks", ns.EngineCompare.Verdicts(store, "c").tier)
        week(store, "2026-09-15", PASS, PASS)
        week(store, "2026-09-22", PASS, PASS)
        assert.equal("ready", ns.EngineCompare.Verdicts(store, "c").tier)
        assert.equal("0/3 weeks", ns.EngineCompare.Verdicts(store, "c").trinket)
        week(store, "2026-09-29", PASS, FAIL)
        assert.equal("no", ns.EngineCompare.Verdicts(store, "c").tier)
    end)

    it("says no after three weeks when k moves more than 10%", function()
        local store = {}
        local wide = deepcopy(PASS)
        wide.k = 1.3
        week(store, "2026-09-01", PASS, PASS)
        week(store, "2026-09-08", PASS, PASS)
        week(store, "2026-09-15", wide, wide)
        assert.equal("no", ns.EngineCompare.Verdicts(store, "c").tier)
    end)
end)

describe("/lootpath engine", function()
    local ns, world
    before_each(function()
        ns, world = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    it("says `not on` and nothing else without the switch", function()
        ns.HandleSlash("engine compare dungeon 10")
        assert.equal(ns.PREFIX .. "not on", world.output())
        assert.is_nil(ns.db.global.engineCompare)
    end)

    it("clears the switch with `off`", function()
        ns.db.global.developer = { engine = true }
        ns.HandleSlash("engine off")
        assert.is_nil(ns.db.global.developer.engine)
        world.printed = {}
        ns.HandleSlash("engine compare")
        assert.equal(ns.PREFIX .. "not on", world.output())
    end)

    it("says one line in combat", function()
        ns.db.global.developer = { engine = true }
        world.inCombat = true
        ns.HandleSlash("engine compare raid")
        assert.equal(ns.PREFIX .. "Out of combat only.", world.output())
    end)

    it("is read by no UI file", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") then
                if readAll("Lootpath/" .. f):find("EngineCompare", 1, true) then
                    readers[#readers + 1] = f
                end
            end
        end
        assert.same({}, readers)
    end)
end)

-- The owner's own state of 2026-09-16, everything the command reads.
local function fixtureWorld(weightsFor)
    local ns, world = H.load()
    H.chicagoClock(world, NOW)
    world.secondsUntilReset = NEXT_RESET - NOW
    local db = R.load(SV)
    ns.db.char = deepcopy(db.char[CHAR])
    ns.db.global = deepcopy(db.global)
    ns.db.global.developer = { engine = true }
    R.inventory(world, R.snapshot("inventory", DRESSED, SV))
    local weights
    if weightsFor then
        weights = weightsFor()
    else
        weights = dofile(WEIGHTS)
        weights.specs[105].Raid = { bands = { all = deepcopy(weights.specs[105].Dungeon.bands["10+"]) } }
    end
    ns.engineWeights = weights
    assert(ns.EngineScore.Load())
    local entries = {}
    for _, record in ipairs(ns.Inventory.Scan().records) do
        entries[#entries + 1] = { link = record.link, level = record.itemLevel }
    end
    local sources = ns.Journal:Build({ snapshot = ns.Companion.NewestSnapshot("journal"), db = false })
    for _, list in pairs(sources) do
        for _, row in ipairs(list) do
            if row.link then
                entries[#entries + 1] = { link = row.link, level = row.itemLevel }
            end
        end
    end
    Stats.install(world, entries)
    return ns, world, sources
end

-- Counted straight off the walk, not through the module: the document's
-- `drop` entries whose `id@level` some journal row carries a link for.
local function walkJoinCount(ns, verdict, sources)
    local linked = {}
    for itemID, list in pairs(sources) do
        for _, row in ipairs(list) do
            if row.link and row.itemLevel then
                linked[string.format("%d@%d", itemID, row.itemLevel)] = true
            end
        end
    end
    local n = 0
    for key, entry in pairs(verdict.items) do
        if linked[key] and ns.UFImport.IsDropAtLevel(entry) then
            n = n + 1
        end
    end
    return n
end

local function compare(ns, words)
    local run
    ns.EngineCompare.Command(words, function(r)
        run = r
    end)
    return run
end

describe("/lootpath engine compare over the owner's 2026-09-16 SavedVariables", function()
    local ns, world, sources
    before_each(function()
        ns, world, sources = fixtureWorld()
    end)
    after_each(function()
        H.unload()
    end)

    it("reads the transcript it says it reads", function()
        assert.equal(4784520, #readAll(SV))
        assert.equal("2026-09-16T15:29:53", R.snapshot("inventory", DRESSED, SV).capturedAtLocal)
    end)

    for _, case in ipairs({ { "dungeon 10", "Dungeon", 10 }, { "raid", "Raid", 10 } }) do
        local words, ct, level = case[1], case[2], case[3]
        it("prints the join count the walk carries, " .. ct, function()
            local run = compare(ns, "compare " .. words)
            assert.is_table(run, "the run finished")
            local verdict = ns.UFImport.ForContentTypeAndLevel(ct, level)
            local expected = walkJoinCount(ns, verdict, sources)
            assert.equal(expected, run.result.uf.joined)
            assert.truthy(world.output():find(string.format(": %d drop rows joined;", expected), 1, true))
            assert.equal(0, run.notReady)
            -- The report, echoed so the brain's figures are read from here.
            io.write("\n[E-0d fixture run: engine compare " .. words .. "]\n" .. world.output() .. "\n")
        end)
    end

    it("files the run under week, character, content type and key level", function()
        local run = compare(ns, "compare dungeon 10")
        local entry = ns.db.global.engineCompare["2026-09-15"]["Tester - TestRealm"].Dungeon[10]
        assert.is_table(entry)
        assert.equal("12.1.0", entry.weightsPatch)
        assert.equal("synthetic", entry.method)
        assert.equal("never", entry.derivedAt)
        assert.equal(run.result.uf.exportedAt, entry.qeExportedAt)
        assert.equal(
            run.result.uf.joined - run.result.uf.notRated - run.result.uf.unknown - run.result.uf.notCompared,
            #entry.rows
        )
        local row = entry.rows[1]
        assert.is_string(row.key)
        assert.is_number(row.ours)
        assert.is_number(row.theirs)
        assert.is_string(row.class)
        assert.is_table(entry.metrics)
        local tg = ns.db.global.engineCompare["2026-09-15"]["Tester - TestRealm"].Dungeon.pass1
        assert.is_table(tg)
        -- A second run of the same week and document replaces its own entry.
        compare(ns, "compare dungeon 10")
        local docs = 0
        for _ in pairs(ns.db.global.engineCompare["2026-09-15"]["Tester - TestRealm"].Dungeon) do
            docs = docs + 1
        end
        assert.equal(2, docs)
    end)

    it("serialises byte-identical when run twice", function()
        compare(ns, "compare dungeon 10")
        local first = S.serialize(ns.db.global.engineCompare)
        local firstOutput = world.output()
        world.printed = {}
        ns.EngineStats.Reset()
        compare(ns, "compare dungeon 10")
        assert.equal(first, S.serialize(ns.db.global.engineCompare))
        assert.equal(firstOutput, world.output())
    end)

    it("writes no rating store and no journal cache", function()
        local function snapshotOf()
            local global = {}
            for k, v in pairs(ns.db.global) do
                if k ~= "engineCompare" then
                    global[k] = v
                end
            end
            return S.serialize({ char = ns.db.char, global = global, profile = ns.db.profile })
        end
        local before = snapshotOf()
        compare(ns, "compare dungeon 10")
        compare(ns, "compare raid")
        assert.is_table(ns.db.global.engineCompare)
        assert.equal(before, snapshotOf())
    end)

    it("compares Top Gear pass 1's single swaps inside the pool", function()
        local run = compare(ns, "compare dungeon 10")
        local tg = run.result.tg
        assert.is_table(tg)
        assert.is_nil(tg.topMissing)
        local verdict = ns.QEImport.ForContentTypeAndScenario("Dungeon", "asOffered")
        local singles = 0
        for _, alt in ipairs(verdict.alternatives) do
            if #alt.items == 1 then
                singles = singles + 1
            end
        end
        assert.equal(
            singles,
            #tg.rows + tg.notInPool + tg.noLink + tg.paired + tg.notRated + tg.unknown + tg.notCompared
        )
        assert.is_number(tg.wornValue)
        assert.is_number(tg.topValue)
    end)

    it("says how many items were not ready, after the bounded wait", function()
        local record
        for _, r in ipairs(ns.Inventory.Scan().records) do
            if r.location == "equipped" then
                record = r
                break
            end
        end
        world.itemStats[Stats.strip(record.link)] = nil
        local run
        ns.EngineCompare.Command("compare dungeon 10", function(r)
            run = r
        end)
        assert.is_nil(run, "it waits")
        world.runTimers(10)
        assert.is_table(run)
        assert.equal(1, run.notReady)
        assert.truthy(world.output():find("1 item(s) were not ready and are left out.", 1, true))
    end)

    it("prints the stored weeks' verdicts", function()
        compare(ns, "compare dungeon 10")
        compare(ns, "compare raid")
        world.printed = {}
        ns.HandleSlash("engine compare weeks")
        local out = world.output()
        assert.truthy(out:find("2026-09-15: tier ", 1, true))
        assert.truthy(out:find("bar (printed, not enforced): tier ", 1, true))
    end)

    -- E-0i (WKE-680): a stored run explains itself - the link as scored and
    -- the level the client read for it sit beside ours and theirs.
    it("stores each row's link as scored and the client's read level of it", function()
        compare(ns, "compare dungeon 10")
        compare(ns, "compare raid")
        local byDoc = ns.db.global.engineCompare["2026-09-15"]["Tester - TestRealm"]
        local n = 0
        for _, entry in ipairs({ byDoc.Dungeon[10], byDoc.Dungeon.pass1, byDoc.Raid[10], byDoc.Raid.pass1 }) do
            assert.is_true(#entry.rows > 0)
            for _, row in ipairs(entry.rows) do
                assert.is_string(row.link, row.key)
                assert.truthy(row.link:find("|Hitem:", 1, true), row.key)
                local read = ns.EngineStats.ForLink(row.link)
                assert.is_number(row.level, row.key)
                assert.equal(read.level, row.level, row.key)
                n = n + 1
            end
        end
        assert.is_true(n > 0)
    end)

    it("prints key, link and level, ours and theirs per row under the verbose switch only", function()
        local run = compare(ns, "compare raid")
        local plain = world.output()
        local row = run.result.uf.rows[1]
        local line =
            string.format("    %s · %s %d · %.4f · %.4f", row.key, row.link, row.level, row.ours, row.theirs)
        assert.is_nil(plain:find(line, 1, true))
        local storedPlain = S.serialize(ns.db.global.engineCompare)
        -- The one switch, toggled by `/lootpath engine verbose` (E-3a's word).
        ns.HandleSlash("engine verbose")
        assert.is_true(ns.db.global.developer.engineVerbose)
        world.printed = {}
        run = compare(ns, "compare raid")
        local verbose = world.output()
        assert.truthy(verbose:find(line, 1, true))
        local _, rowLines = verbose:gsub(":     [^\n]* · [^\n]* · [^\n]* · [^\n]*", "")
        assert.equal(#run.result.uf.rows + #run.result.tg.rows, rowLines)
        -- The stored entry is the same with the switch on or off.
        assert.equal(storedPlain, S.serialize(ns.db.global.engineCompare))
        -- Toggled off again, the rows are gone from the print.
        ns.HandleSlash("engine verbose")
        assert.is_nil(ns.db.global.developer.engineVerbose)
        world.printed = {}
        compare(ns, "compare raid")
        assert.is_nil(world.output():find(line, 1, true))
        -- `compare weeks` is unchanged by it.
        ns.db.global.developer.engineVerbose = true
        world.printed = {}
        ns.HandleSlash("engine compare weeks")
        assert.is_nil(world.output():find(" · |", 1, true))
    end)

    it("prints the field a refused weights file tripped on", function()
        ns.engineWeights.tiers = { setIDs = { 2057 }, twoPiece = 0.03, fourPiece = 0.055, forceTier = true }
        ns.EngineScore.file = nil
        world.printed = {}
        assert.is_nil(compare(ns, "compare raid"))
        local out = world.output()
        assert.truthy(out:find("Not rated - the rating data didn't load.", 1, true))
        assert.truthy(out:find("weights file: tiers.forceTier is not keyed by a setID", 1, true))
    end)
end)

-- E-0h (WKE-678): the key level reaches the score. The owner's first fitted
-- run (2026-10-01) printed `not compared: 84 (no band 84)` for Dungeon +6 and
-- `not compared: 3 (no base 3)` for Top Gear, because the fit writes one
-- Dungeon band per key level and the compare named none.
describe("/lootpath engine compare names the band it scores with", function()
    after_each(function()
        H.unload()
    end)

    -- Every Top Gear single swap is accounted for in one of the counters.
    local function tgAccounted(ns, ct, tg)
        local verdict = ns.QEImport.ForContentTypeAndScenario(ct, "asOffered")
        local singles = 0
        for _, alt in ipairs(verdict.alternatives) do
            if #alt.items == 1 then
                singles = singles + 1
            end
        end
        assert.equal(
            singles,
            #tg.rows + tg.notInPool + tg.noLink + tg.paired + tg.notRated + tg.unknown + tg.notCompared
        )
    end

    local function noBandReason(block)
        for why in pairs(block.reasons) do
            if tostring(why):find("no band", 1, true) or why == "no base" then
                return why
            end
        end
        return nil
    end

    it("prints the band key in each block's header", function()
        local ns, world = fixtureWorld()
        local run = compare(ns, "compare dungeon 10")
        assert.equal("10+", run.result.uf.band)
        assert.equal("10+", run.result.tg.band)
        local out = world.output()
        assert.truthy(
            out:find("Upgrade Finder Dungeon +10 (exported " .. run.result.uf.exportedAt .. "), band 10+: ", 1, true)
        )
        assert.truthy(
            out:find("Top Gear pass 1 Dungeon (exported " .. run.result.tg.exportedAt .. "), band 10+: ", 1, true)
        )
    end)

    it("scores every joined row of the fitted shape on both content types", function()
        local ns, world = fixtureWorld(function()
            return dofile(FITTED)
        end)
        for _, case in ipairs({ { "dungeon 10", "Dungeon", "10" }, { "raid", "Raid", "raid-3" } }) do
            world.printed = {}
            local run = compare(ns, "compare " .. case[1])
            local uf, tg = run.result.uf, run.result.tg
            assert.equal(case[3], uf.band, case[2])
            assert.equal(case[3], tg.band, case[2])
            assert.is_nil(noBandReason(uf), case[2])
            assert.is_nil(noBandReason(tg), case[2])
            assert.is_true(uf.joined > 0)
            -- Every joined row is scored or held for a reason that is not the band.
            local scored = #uf.rows
            assert.equal(uf.joined, scored + uf.notRated + uf.unknown + uf.notCompared, case[2])
            assert.is_true(scored > 0, case[2])
            assert.is_number(tg.topValue, case[2])
            assert.is_number(tg.wornValue, case[2])
            assert.is_true(#tg.rows > 0, case[2])
            tgAccounted(ns, case[2], tg)
            assert.truthy(world.output():find("band " .. case[3] .. ": ", 1, true), case[2])
        end
        -- Every Dungeon level the owner stored that day (+2, +4, +6, +8, +10) is
        -- scored on its own band - +6 is the document that said `no band 84`.
        local levels = ns.UFImport.StoredKeyLevels("Dungeon")
        table.sort(levels)
        assert.same({ 2, 4, 6, 8, 10 }, levels)
        for _, level in ipairs(levels) do
            local run = compare(ns, "compare dungeon " .. level)
            assert.equal(level, run.result.uf.keyLevel)
            assert.equal(tostring(level), run.result.uf.band)
            assert.equal(tostring(level), run.result.tg.band)
            assert.is_nil(noBandReason(run.result.uf), level)
            assert.is_nil(noBandReason(run.result.tg), level)
        end
    end)

    it("names the level when the document's level has no band", function()
        local ns, world = fixtureWorld(function()
            local w = dofile(FITTED)
            w.specs[105].Dungeon.bands["10"] = nil
            return w
        end)
        local run = compare(ns, "compare dungeon 10")
        local uf, tg = run.result.uf, run.result.tg
        assert.is_nil(uf.band)
        assert.equal("no band for +10", uf.noBand)
        assert.equal(0, #uf.rows)
        assert.equal(uf.joined, uf.notCompared)
        assert.same({ ["no band for +10"] = uf.joined }, uf.reasons)
        assert.same({ ["no band for +10"] = tg.notCompared }, tg.reasons)
        local out = world.output()
        assert.truthy(out:find(string.format("not compared: %d (no band for +10)\n", uf.joined), 1, true))
        assert.truthy(out:find(string.format("not compared: %d (no band for +10)\n", tg.notCompared), 1, true))
        assert.truthy(out:find("), band -: ", 1, true))
        assert.is_nil(out:find("(no band)", 1, true))
        assert.is_nil(out:find("no base", 1, true))
    end)

    it("still scores with the placeholder file's one `10+` band", function()
        local ns = fixtureWorld(function()
            local shipped = {}
            assert(loadfile(SHIPPED))("Lootpath", shipped)
            return shipped.engineWeights
        end)
        assert.equal("placeholder", ns.EngineScore.file.method)
        for _, case in ipairs({ { "dungeon 10", "10+" }, { "raid", "all" } }) do
            local run = compare(ns, "compare " .. case[1])
            assert.equal(case[2], run.result.uf.band)
            assert.equal(case[2], run.result.tg.band)
            assert.is_nil(noBandReason(run.result.uf))
            assert.is_true(#run.result.uf.rows > 0)
        end
    end)
end)

describe("EngineCompare's join over the committed Upgrade Finder exports", function()
    local ns, sources
    before_each(function()
        local _
        ns, _, sources = fixtureWorld()
    end)
    after_each(function()
        H.unload()
    end)

    -- Byte length, against the sha256 recorded in spec/fixtures/qe/README.md.
    for _, case in ipairs({ { UF_DUNGEON_10, 120017 }, { UF_RAID, 119677 } }) do
        it("joins " .. case[1] .. " exactly where the walk has a link", function()
            local text = readAll(case[1])
            assert.equal(case[2], #text)
            local parsed = ns.UFImport.Parse(text)
            assert.is_true(parsed.ok)
            local join = ns.EngineCompare.UFJoin(parsed.verdict, ns.EngineCompare.JournalLinks(sources))
            assert.equal(walkJoinCount(ns, parsed.verdict, sources), #join.joined)
            io.write(
                string.format(
                    "\n[E-0d committed export %s: %d joined, %d drop rows with no link, %d other listings]",
                    case[1],
                    #join.joined,
                    join.noLink,
                    join.other
                )
            )
        end)
    end
end)

-- The compare keys a journal row by the level the WALK listed it at, and
-- scores the row's link; the client reads that link at its own level. On the
-- owner's 2026-10-01 transcript the two differ on 17 of the 40 sampled rows:
-- every keystone row (difficulty 8) the walk listed at 305 reads 292 - the
-- same stats as the Mythic (23) row at 292 - the raid rows read the
-- difficulty's base level (308 heroic, 321 mythic) whatever boss the walk
-- listed them under (305 / 311 / 318 / 324), and the world rows the walk
-- listed at 44 read 263 / 276. So a joined keystone row is scored with stats
-- 13 levels below the row it is compared against (ARCHITECTURE.md section 11, E-0f).
describe("EngineCompare's journal half against the client's own reads", function()
    local ns
    before_each(function()
        local world
        ns, world = H.load()
        Real.install(world)
    end)
    after_each(function()
        H.unload()
    end)

    it("reads each walk link at the client's level, which differs from the walk's on 17 of 40", function()
        local rows = Real.rowsFrom("journal")
        assert.equal(40, #rows)
        local differ, byDifficulty = 0, {}
        for _, row in ipairs(rows) do
            local read = ns.EngineStats.ForLink(row.link)
            assert.is_true(read.ready, row.link)
            assert.equal(row.level, read.level)
            if read.level ~= row.journalItemLevel then
                differ = differ + 1
                local d = byDifficulty[row.difficultyID] or {}
                d[#d + 1] = row.journalItemLevel .. "->" .. read.level
                byDifficulty[row.difficultyID] = d
            end
        end
        assert.equal(17, differ)
        for _, change in ipairs(byDifficulty[8]) do
            assert.equal("305->292", change)
        end
        assert.equal(7, #byDifficulty[8])
        -- Keystone and Mythic rows of one item read the same stats at 292.
        local keystone, mythic
        for _, row in ipairs(rows) do
            if row.itemID == 251123 and row.difficultyID == 8 then
                keystone = ns.EngineStats.ForLink(row.link)
            elseif row.itemID == 251123 and row.difficultyID == 23 then
                mythic = ns.EngineStats.ForLink(row.link)
            end
        end
        for _, field in ipairs({ "int", "haste", "crit", "stamina" }) do
            assert.equal(mythic[field], keystone[field], field)
        end
        assert.equal(567, keystone.int)
    end)

    it("joins a walk row under the walk's own level, not the client's", function()
        local sources = {}
        for _, row in ipairs(Real.rowsFrom("journal")) do
            sources[row.itemID] = sources[row.itemID] or {}
            table.insert(sources[row.itemID], { link = row.link, itemLevel = row.journalItemLevel, slot = row.slot })
        end
        local byKey = ns.EngineCompare.JournalLinks(sources)
        local found
        for _, row in ipairs(Real.rowsFrom("journal")) do
            if row.itemID == 159317 and row.difficultyID == 8 then
                found = row
            end
        end
        assert.is_table(byKey["159317@305"])
        assert.equal(found.link, byKey["159317@305"].link)
        assert.equal(292, ns.EngineStats.ForLink(byKey["159317@305"].link).level)
    end)
end)

-- E-3a (WKE-679): the effects table makes the `not rated` count real. The
-- owner's fitted +6 run (2026-10-01 night) compared 13 trinket rows; over the
-- committed 2026-09-16 fixture, with the fitted-shape weights, this run
-- prints how many joined trinket rows the table carries and asserts the
-- counts as read. Every row the table carries is left out of every metric.
describe("/lootpath engine compare with the effects table", function()
    after_each(function()
        H.unload()
    end)

    -- The joined rows' itemIDs and slots, read straight off the walk.
    local function joinedRows(ns, verdict, sources)
        local out = {}
        for itemID, list in pairs(sources) do
            for _, row in ipairs(list) do
                if row.link and row.itemLevel then
                    local key = string.format("%d@%d", itemID, row.itemLevel)
                    local entry = verdict.items[key]
                    if entry and ns.UFImport.IsDropAtLevel(entry) and not out[key] then
                        out[key] = { itemID = itemID, slot = row.slot }
                    end
                end
            end
        end
        return out
    end

    it("leaves every row the table carries out of every metric, on the +6 document", function()
        local ns, world, sources = fixtureWorld(function()
            return dofile(FITTED)
        end)
        ns.db.global.developer.engineVerbose = true
        local run = compare(ns, "compare dungeon 6")
        local uf = run.result.uf
        local verdict = ns.UFImport.ForContentTypeAndLevel("Dungeon", 6)
        local trinkets, inTable, effectRows = 0, 0, 0
        local oneHanders = {}
        for _, row in pairs(joinedRows(ns, verdict, sources)) do
            local carried = ns.engineEffects.items[row.itemID] ~= nil
            if carried and row.slot == "1H Weapon" then
                oneHanders[#oneHanders + 1] = row.itemID
            end
            if row.slot == "Trinket" then
                trinkets = trinkets + 1
                inTable = inTable + (carried and 1 or 0)
            end
            effectRows = effectRows + (carried and 1 or 0)
        end
        io.write(
            string.format(
                "\n[E-3a fixture run: engine compare dungeon 6 - %d joined, %d trinket rows, %d of them in the "
                    .. "effects table, %d joined rows in the table; not rated %d, unknown %d, generic %d]\n%s\n",
                uf.joined,
                trinkets,
                inTable,
                effectRows,
                uf.notRated,
                uf.unknown,
                uf.generic,
                world.output()
            )
        )
        -- As read from the run above.
        assert.equal(84, uf.joined)
        assert.equal(13, trinkets) -- the owner's +6 run compared 13 trinket rows too
        assert.equal(17, effectRows) -- 13 trinkets, Gaze, Aqirbane and the two one-handers
        assert.equal(13, inTable)
        -- 15, not 17: the two one-handers (Jan'thrazet, Polished Lightwood
        -- Channeler) beside the worn two-hander are `not comparable` first.
        table.sort(oneHanders)
        assert.same({ 271092, 273778 }, oneHanders)
        assert.same({ ["not comparable"] = uf.notCompared }, uf.reasons)
        assert.equal(15, uf.notRated)
        assert.equal(0, uf.unknown)
        assert.equal(0, uf.generic)
        -- No metric holds a row whose item the table carries, and no trinket
        -- row is in the class table.
        for _, row in ipairs(uf.rows) do
            local id = tonumber(row.key:match("^(%d+)@"))
            assert.is_nil(ns.engineEffects.items[id], row.key)
            assert.are_not.equal("trinket", row.class, row.key)
        end
        assert.is_nil(uf.metrics.trinket)
        assert.equal(uf.notRated, #uf.notRatedItems)
        local out = world.output()
        assert.truthy(out:find(string.format("  not rated: %d (effect not modelled)\n", uf.notRated), 1, true))
        assert.truthy(out:find("  generic: 0 (effect from a generic rule)\n", 1, true))
        assert.truthy(out:find("  trinket: no row a rule covers yet\n", 1, true))
        for _, item in ipairs(uf.notRatedItems) do
            assert.truthy(out:find("    " .. item.names .. " (" .. item.key .. ")\n", 1, true), item.key)
        end
    end)

    it("lists no names without the verbose switch, and the switch toggles", function()
        local ns, world = fixtureWorld(function()
            return dofile(FITTED)
        end)
        local run = compare(ns, "compare dungeon 6")
        assert.is_true(run.result.uf.notRated > 0)
        local out = world.output()
        assert.truthy(out:find(string.format("  not rated: %d (effect not modelled)", run.result.uf.notRated), 1, true))
        for _, item in ipairs(run.result.uf.notRatedItems) do
            assert.is_nil(out:find("    " .. item.names .. " (" .. item.key .. ")", 1, true), item.key)
        end
        world.printed = {}
        ns.HandleSlash("engine verbose")
        assert.is_true(ns.db.global.developer.engineVerbose)
        assert.truthy(world.output():find("engine verbose on", 1, true))
        ns.HandleSlash("engine verbose")
        assert.is_nil(ns.db.global.developer.engineVerbose)
    end)
end)

-- E-0i (WKE-680): a code-independence guard. `compare raid` (verbose on) driven over the
-- owner's 2026-10-01 transcript as committed - inventory snapshot 4 (09:26:31,
-- the flush after `capture itemstats`), the Raid Upgrade Finder document stored
-- in it (exported 2026-10-01T13:59:43.959Z), its Top Gear pass 1, its newest
-- journal walk, and the client's own item reads in itemstats-real.lua - with
-- the SYNTHETIC fitted-shape weights. Every value pinned below is what this
-- commit computed (read from this spec's own run, never copied from elsewhere);
-- any later change to how a Raid row is scored turns it red. Only the links the
-- capture read have stats here: 2 of the 30 joined Upgrade Finder rows score,
-- the other 28 links are not in the transcript and wait out as not ready.
local TRANSCRIPT = "spec/fixtures/captures/Lootpath-20261001-092631.lua"
local TRANSCRIPT_INVENTORY = 4
-- 2026-10-01T14:26:31Z (09:26:31 Chicago), and the US reset after it,
-- 2026-10-06T15:00:00Z.
local TRANSCRIPT_NOW = 1790864791
local TRANSCRIPT_RESET = 1791298800

local PINNED = {
    uf = {
        ["268234@324"] = 0.39908906504140779,
        ["268247@318"] = 0.37838637717233659,
    },
    tg = {
        { "271528:6652:12845:13440:13692:13695:13698", 0.24358358586260817 },
        { "277781:6652:12836:13662:13696", -0.064902948040283195 },
    },
    worn = 5709.2518928414584,
    best = 5699.0687604303903,
}

local function transcriptWorld()
    local ns, world = H.load()
    H.chicagoClock(world, TRANSCRIPT_NOW)
    world.secondsUntilReset = TRANSCRIPT_RESET - TRANSCRIPT_NOW
    local db = R.load(TRANSCRIPT)
    ns.db.char = deepcopy(db.char[CHAR])
    ns.db.global = deepcopy(db.global)
    ns.db.global.developer = { engine = true }
    R.inventory(world, R.snapshot("inventory", TRANSCRIPT_INVENTORY, TRANSCRIPT))
    -- AFTER R.inventory: install merges into the items it registered.
    Real.install(world)
    ns.engineWeights = dofile(FITTED)
    assert(ns.EngineScore.Load())
    return ns, world
end

describe("/lootpath engine compare raid over the 2026-10-01 transcript", function()
    after_each(function()
        H.unload()
    end)

    it("keeps the inventory scan whole when the real reads are installed after it", function()
        local ns = transcriptWorld()
        assert.equal("2026-10-01T09:26:31", R.snapshot("inventory", TRANSCRIPT_INVENTORY, TRANSCRIPT).capturedAtLocal)
        local scan = ns.Inventory.Scan()
        assert.is_true(scan.ok)
        local equipped = 0
        for _, record in ipairs(scan.records) do
            if record.location == "equipped" then
                equipped = equipped + 1
            end
        end
        assert.equal(15, equipped)
        assert.equal(40, #scan.records)
    end)

    it("scores every Raid row and both Top Gear sets as this commit did", function()
        local ns, world = transcriptWorld()
        local run
        ns.db.global.developer.engineVerbose = true
        ns.EngineCompare.Command("compare raid", function(r)
            run = r
        end)
        world.runTimers(10)
        assert.is_table(run, "the run finished")
        io.write("\n[E-0i transcript run: engine compare raid, verbose on]\n" .. world.output() .. "\n")
        local uf, tg = run.result.uf, run.result.tg
        for _, row in ipairs(uf.rows) do
            io.write(string.format("[E-0i pin] uf %s %.17g\n", row.key, row.ours))
        end
        for _, row in ipairs(tg.rows) do
            io.write(string.format("[E-0i pin] tg %s %.17g\n", row.key, row.ours))
        end
        io.write(string.format("[E-0i pin] worn %.17g best %.17g\n", tg.wornValue, tg.topValue))
        assert.equal("2026-10-01T13:59:43.959Z", uf.exportedAt)
        assert.equal("raid-3", uf.band)
        assert.equal(30, uf.joined)
        assert.equal(28, uf.notCompared)
        assert.same({ ["not ready"] = 28 }, uf.reasons)
        assert.equal(28, run.notReady)
        local function pinned(expected, actual, what)
            assert.is_number(actual, what)
            assert.is_true(
                math.abs(expected - actual) <= 1e-12 * math.max(1, math.abs(expected)),
                string.format("%s: pinned %.17g, computed %.17g", what, expected, actual)
            )
        end
        local seen = 0
        for _, row in ipairs(uf.rows) do
            pinned(PINNED.uf[row.key], row.ours, row.key)
            seen = seen + 1
        end
        local want = 0
        for _ in pairs(PINNED.uf) do
            want = want + 1
        end
        assert.equal(want, seen)
        assert.equal(#PINNED.tg, #tg.rows)
        for i, row in ipairs(tg.rows) do
            assert.equal(PINNED.tg[i][1], row.key)
            pinned(PINNED.tg[i][2], row.ours, row.key)
        end
        pinned(PINNED.worn, tg.wornValue, "worn set")
        pinned(PINNED.best, tg.topValue, "best set")
    end)
end)

-- E-0g (WKE-677): the walk's link reads at its own level, so with
-- REBUILD_AT_LEVEL on every joined row is read through a link rebuilt at the
-- row's level and kept only when the client draws that level; the rest are
-- LEFT OUT and counted on their own header line. The switch ships OFF (no rule
-- is proven until `capture linklevel`'s transcript lands), and off, nothing
-- about the compare changes. The rules and reads here are the tests' own.
describe("EngineCompare at the row's level", function()
    local ns
    local L10 = "|cnIQ4:|Hitem:10::::::::90:105::16:1:3524:1:28:1279:::::|h[Drop Ten]|h|r"
    local L11 = "|cnIQ4:|Hitem:11::::::::90:105::16:1:3524:1:28:1279:::::|h[Drop Eleven]|h|r"
    local function vec(stats)
        local v = { ready = true, sockets = 0, gems = {} }
        for _, k in ipairs({ "int", "haste", "crit", "mastery", "vers", "leech" }) do
            v[k] = 0
        end
        for k, x in pairs(stats) do
            v[k] = x
        end
        return v
    end
    local function drop(key, percent)
        return { key = key, dropType = "drop", upgradePercent = percent, sources = {} }
    end
    local function inputs()
        local rule = function()
            return { 12837 }
        end
        local R10 = ns.EngineStats.RebuildLink(L10, rule())
        local R11 = ns.EngineStats.RebuildLink(L11, rule())
        return {
            contentType = "Dungeon",
            file = dofile(WEIGHTS),
            worn = { { link = "worn-head", slot = "Head" }, { link = "worn-wrist", slot = "Wrist" } },
            owned = {},
            reads = {
                ["worn-head"] = vec({ int = 100 }),
                ["worn-wrist"] = vec({ int = 50 }),
                -- The kept links, at the client's own 292.
                [L10] = vec({ int = 150, level = 292 }),
                [L11] = vec({ int = 40, level = 292 }),
                -- Rebuilt: the head drawn at the row's 305, the wrist at 292.
                [R10] = vec({ int = 180, level = 305 }),
                [R11] = vec({ int = 45, level = 292 }),
            },
            journalByKey = {
                ["10@305"] = { link = L10, slot = "Head", itemLevel = 305 },
                ["11@305"] = { link = L11, slot = "Wrist", itemLevel = 305 },
            },
            document = {
                keyLevel = 10,
                verdict = {
                    exportedAt = "x",
                    order = { "10@305", "11@305" },
                    items = { ["10@305"] = drop("10@305", 0.8), ["11@305"] = drop("11@305", -0.3) },
                },
            },
        },
            rule,
            R10
    end
    local function lines(result)
        return table.concat(
            ns.EngineCompare.Lines({ file = {}, contentType = "Dungeon", charKey = "c", result = result }),
            "\n"
        )
    end

    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        ns.EngineCompare.REBUILD_AT_LEVEL = false
        ns.EngineStats.linkLevelRule = nil
        H.unload()
    end)

    it("ships with the switch off and no rule installed", function()
        assert.is_false(ns.EngineCompare.REBUILD_AT_LEVEL)
        assert.is_nil(ns.EngineStats.linkLevelRule)
    end)

    it("off, reads the walk's own link exactly as before and prints no `at level` line", function()
        local result = ns.EngineCompare.Compute(inputs())
        assert.is_nil(result.uf.atLevel)
        assert.equal(2, #result.uf.rows)
        assert.equal(L10, ns.EngineCompare.CandidateLink({ row = { link = L10, itemLevel = 305 } }))
        assert.is_nil(lines(result):find("at level", 1, true))
    end)

    it("on with no rule, leaves every joined row out and says why, never scoring one", function()
        ns.EngineCompare.REBUILD_AT_LEVEL = true
        local result = ns.EngineCompare.Compute(inputs())
        assert.equal(2, result.uf.joined)
        assert.equal(0, #result.uf.rows)
        assert.equal(0, result.uf.notCompared)
        assert.same({ rebuilt = 0, leftOut = 2, reasons = { ["no rule yet"] = 2 } }, result.uf.atLevel)
        assert.truthy(lines(result):find("  at level: 0 rebuilt, 2 left out (no rule yet)", 1, true))
    end)

    it("on with a rule, scores the rows drawn at their level and leaves out the one that is not", function()
        ns.EngineCompare.REBUILD_AT_LEVEL = true
        local input, rule, R10 = inputs()
        ns.EngineStats.linkLevelRule = rule
        assert.equal(R10, ns.EngineCompare.CandidateLink({ row = { link = L10, itemLevel = 305 } }))
        local result = ns.EngineCompare.Compute(input)
        assert.equal(1, #result.uf.rows)
        assert.equal("10@305", result.uf.rows[1].key)
        assert.same({ rebuilt = 1, leftOut = 1, reasons = { ["read at 292, not 305"] = 1 } }, result.uf.atLevel)
        assert.truthy(lines(result):find("  at level: 1 rebuilt, 1 left out (read at 292, not 305)", 1, true))
        -- Scored with the rebuilt read (180), not the kept one (150).
        ns.EngineCompare.REBUILD_AT_LEVEL = false
        local off = ns.EngineCompare.Compute(inputs())
        assert.equal("10@305", off.uf.rows[1].key)
        assert.is_true(result.uf.rows[1].ours > off.uf.rows[1].ours)
    end)

    it("on, counts a rebuilt link the client has not read as not ready, not as left out", function()
        ns.EngineCompare.REBUILD_AT_LEVEL = true
        local input, rule, R10 = inputs()
        ns.EngineStats.linkLevelRule = rule
        input.reads[R10] = { ready = false }
        local result = ns.EngineCompare.Compute(input)
        assert.equal(1, result.uf.atLevel.leftOut)
        assert.equal(1, result.uf.notCompared)
        assert.same({ ["not ready"] = 1 }, result.uf.reasons)
    end)
end)

describe("/lootpath engine compare at the row's level, over the owner's 2026-09-16 SavedVariables", function()
    local ns
    before_each(function()
        ns = fixtureWorld()
    end)
    after_each(function()
        ns.EngineCompare.REBUILD_AT_LEVEL = false
        H.unload()
    end)

    it("on with no rule, joins as before and leaves every joined row out, counted on its own line", function()
        local first = compare(ns, "compare dungeon 10")
        local before = first.result.uf
        local tgBefore = first.result.tg and #(first.result.tg.rows or {}) or 0
        assert.is_true(before.joined > 0)
        assert.is_nil(before.atLevel)
        ns.EngineCompare.REBUILD_AT_LEVEL = true
        local run = compare(ns, "compare dungeon 10")
        local uf = run.result.uf
        assert.equal(before.joined, uf.joined)
        assert.equal(0, #uf.rows)
        assert.equal(uf.joined, uf.atLevel.leftOut)
        assert.same({ ["no rule yet"] = uf.joined }, uf.atLevel.reasons)
        assert.equal(0, run.notReady)
        -- Top Gear is not a journal row: unchanged.
        assert.equal(tgBefore, run.result.tg and #(run.result.tg.rows or {}) or 0)
    end)
end)
