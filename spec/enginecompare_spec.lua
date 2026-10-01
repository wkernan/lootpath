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
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
local S = require("spec.helpers.serialize")
local Stats = dofile("spec/fixtures/engine/itemstats-synthetic.lua")

local WEIGHTS = "spec/fixtures/engine/weights-synthetic.lua"
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
                ["drop-wrist-effect"] = vec({ int = 60, effect = true }),
            },
            journalByKey = {
                ["10@300"] = { link = "drop-head", slot = "Head" },
                ["11@300"] = { link = "drop-wrist", slot = "Wrist" },
                ["12@300"] = { link = "drop-wrist-effect", slot = "Wrist" },
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
        local world
        ns, world = H.load()
        for index, per in pairs(Stats.RATING_PER_PERCENT) do
            world.ratingPerPercent[index] = per
        end
    end)
    after_each(function()
        H.unload()
    end)

    it("reads both columns as positive = better, and counts what it leaves out", function()
        local result = ns.EngineCompare.Compute(inputs())
        local uf = result.uf
        assert.equal(3, uf.joined)
        assert.equal(1, uf.other) -- the `max` listing
        assert.equal(1, uf.notRated) -- the drop with an effect
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
local function fixtureWorld()
    local ns, world = H.load()
    H.chicagoClock(world, NOW)
    world.secondsUntilReset = NEXT_RESET - NOW
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
        assert.equal(run.result.uf.joined - run.result.uf.notRated - run.result.uf.notCompared, #entry.rows)
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
        assert.equal(singles, #tg.rows + tg.notInPool + tg.noLink + tg.paired + tg.notRated + tg.notCompared)
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
