-- spec/enginesearch_spec.lua (E-1a, WKE-685)
-- ns.EngineSearch: the best set of owned items by our own set value. Held
-- against brute force on SYNTHETIC inventories (several seeds; every slot
-- kind: single slots, the ring pair, the trinket pair, one-hand plus off-hand
-- against two-hand; a unique-equipped pair; a tier set that only pays at four
-- pieces), the outclassed-piece drop held against brute force over every
-- piece, a rejecting constraint hook, the coroutine yielding and resuming to
-- the same answer, determinism, nothing written to the database, the switch
-- and combat refusals. The last block runs the search over the owner's real
-- inventory of 2026-09-16 (inventory read 3: the real pieces, slots, levels
-- and set IDs; the stats from the SYNTHETIC rule in itemstats-synthetic.lua,
-- because no transcript reads that day's links) and PRINTS the evaluation
-- count and the time it took.
--
-- E-1e (WKE-703) adds the smallest two-positions-at-once case: a neck and a
-- ring sharing a limit category, which only the coupled sweep reaches.
--
-- No number in this file is a game value. The weights are
-- spec/fixtures/engine/weights-synthetic.lua with its tier multipliers changed
-- where a test says so.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
local S = require("spec.helpers.serialize")
local Stats = dofile("spec/fixtures/engine/itemstats-synthetic.lua")

local WEIGHTS = "spec/fixtures/engine/weights-synthetic.lua"
local SV = "spec/fixtures/captures/Lootpath-20260916-162655.lua"
local CHAR = "Hotornot - Arthas"
local DRESSED = 3 -- 2026-09-16T15:29:53, 15 equipped
local SEEDS = { 1, 2, 3, 4, 5, 6 }

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
    io.stdout:write("\n[enginesearch] " .. string.format(fmt, ...) .. "\n")
end

-- A small deterministic generator (an LCG), so a seed means the same
-- inventory on every machine.
local function generator(seed)
    local s = seed * 7919 + 17
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return math.floor(s / 65536) % n
    end
end

-- Synthetic itemIDs start at 900000: none is in the shipped effects table.
local nextID
local function piece(rand, slot, extra)
    nextID = nextID + 1
    local item = {
        itemID = nextID,
        key = "syn:" .. nextID,
        slot = slot,
        level = 300,
        int = 250 + rand(120),
        stamina = 1000,
        haste = 40 + rand(330),
        crit = 40 + rand(330),
        mastery = 40 + rand(330),
        vers = 40 + rand(330),
        leech = rand(40),
        sockets = rand(4) == 0 and 1 or 0,
        gems = {},
        ready = true,
    }
    for k, v in pairs(extra or {}) do
        item[k] = v
    end
    return item
end

-- The tier set of the synthetic weights, 2057: pieces a little weaker than
-- their slot's best, so wearing them only pays once four are worn.
local TIER = 2057

local function weakened(item, by)
    for _, stat in ipairs({ "int", "haste", "crit", "mastery", "vers" }) do
        item[stat] = math.floor(item[stat] * by)
    end
    return item
end

-- One synthetic inventory: two pieces in six single slots (one of them a tier
-- piece in each tier slot), one in the other four plus an outclassed spare,
-- four rings (two copies of one unique ring among them) plus an outclassed
-- one, three trinkets (unique), a one-hander, an off-hand, a shield and two
-- two-handers: 20,736 sets for brute force.
local function inventory(seed)
    nextID = 900000 + seed * 1000
    local rand = generator(seed)
    local items = {}
    local function add(item)
        items[#items + 1] = item
        return item
    end
    for _, slot in ipairs({ "Head", "Shoulder", "Chest", "Hands", "Legs" }) do
        local plain = add(piece(rand, slot))
        -- The tier piece is the plain piece's stats, 8% lower: never better
        -- alone, so only a mask (or a lucky start) reaches four.
        local tier = deepcopy(plain)
        nextID = nextID + 1
        tier.itemID, tier.key, tier.setID = nextID, "syn:" .. nextID, TIER
        add(weakened(tier, 0.92))
        if slot == "Legs" then
            -- An outclassed spare: every stat below the plain piece's.
            local spare = add(piece(rand, slot))
            for _, stat in ipairs({ "int", "haste", "crit", "mastery", "vers", "leech" }) do
                spare[stat] = math.max(0, plain[stat] - 1 - rand(20))
            end
            spare.sockets = 0
        end
    end
    add(piece(rand, "Neck"))
    add(piece(rand, "Neck"))
    for _, slot in ipairs({ "Back", "Wrist", "Waist", "Feet" }) do
        local only = add(piece(rand, slot))
        if slot == "Waist" then
            local spare = add(piece(rand, slot))
            for _, stat in ipairs({ "int", "haste", "crit", "mastery", "vers", "leech" }) do
                spare[stat] = math.max(0, only[stat] - 2)
            end
            spare.sockets = only.sockets
        end
    end
    -- Two copies of one unique ring, both strong; two plain rings; one ring
    -- outclassed by both copies AND by a plain ring.
    local uniqueID = nextID + 1
    local u1 = add(piece(rand, "Finger", { itemID = uniqueID, uniqueness = { isUnique = true } }))
    nextID = nextID + 1
    local u2 = add(deepcopy(u1))
    u2.key = u1.key .. ":copy"
    for _, stat in ipairs({ "int", "haste", "crit", "mastery", "vers" }) do
        u1[stat] = u1[stat] + 400
        u2[stat] = u2[stat] + 400
    end
    local plainRing = add(piece(rand, "Finger"))
    add(piece(rand, "Finger"))
    local low = add(piece(rand, "Finger"))
    for _, stat in ipairs({ "int", "haste", "crit", "mastery", "vers", "leech" }) do
        low[stat] = math.max(0, math.min(u1[stat], plainRing[stat]) - 5)
    end
    low.sockets = 0
    for _ = 1, 3 do
        add(piece(rand, "Trinket", { uniqueness = { isUnique = true } }))
    end
    add(piece(rand, "1H Weapon"))
    add(piece(rand, "Offhand"))
    add(piece(rand, "Shield"))
    for _ = 1, 2 do
        local two = add(piece(rand, "2H Weapon"))
        for _, stat in ipairs({ "int", "haste", "crit", "mastery", "vers" }) do
            two[stat] = two[stat] * 2 - 60 + rand(120)
        end
    end
    return items
end

local function weights(tier2, tier4)
    local w = dofile(WEIGHTS)
    w.tiers = { [TIER] = { [2] = { mult = tier2 or 1.0001 }, [4] = { mult = tier4 or 1.06 } } }
    return w
end

local OPTS = { dr = "table", contentType = "Dungeon" }

local function keysOf(items)
    local keys = {}
    for _, item in ipairs(items) do
        keys[#keys + 1] = item.key
    end
    table.sort(keys)
    return table.concat(keys, " ")
end

local function close(a, b)
    return math.abs(a - b) <= math.abs(b) * 1e-9
end

local function weaponKind(items)
    for _, item in ipairs(items) do
        if item.slot == "2H Weapon" then
            return "2H"
        end
    end
    return "1H+OH"
end

local function tierCount(items)
    local n = 0
    for _, item in ipairs(items) do
        if item.setID == TIER then
            n = n + 1
        end
    end
    return n
end

local function loaded()
    local ns, world = H.load()
    ns.db.global.developer = { engine = true }
    return ns, world
end

describe("ns.EngineSearch against brute force on synthetic inventories", function()
    local ns
    before_each(function()
        ns = loaded()
    end)
    after_each(function()
        H.unload()
    end)

    it("finds the brute-force optimum on every seed, every slot kind in play", function()
        local kinds, evals = {}, {}
        local slowest = 0
        for _, seed in ipairs(SEEDS) do
            local items = inventory(seed)
            local w = weights()
            local t0 = os.clock()
            local best = assert(ns.EngineSearch.Best(items, w, OPTS))
            local searchMs = (os.clock() - t0) * 1000
            t0 = os.clock()
            local brute = assert(ns.EngineSearch.BruteForce(items, w, OPTS))
            local bruteMs = (os.clock() - t0) * 1000
            assert.is_true(close(best.value, brute.value), "seed " .. seed)
            assert.equal(keysOf(brute.items), keysOf(best.items), "seed " .. seed)
            assert.is_true(ns.EngineSearch.UniqueOK(best.items))
            kinds[weaponKind(best.items)] = true
            evals[#evals + 1] = best.evaluations
            slowest = math.max(slowest, searchMs)
            say(
                "seed %d: search %d evaluations (%d ascent, %d runner-up), %d masks, %.1f ms;"
                    .. " brute force %d sets, %d valued, %.1f ms; equal",
                seed,
                best.evaluations,
                best.ascentEvaluations,
                best.evaluations - best.ascentEvaluations,
                best.masks,
                searchMs,
                brute.sets,
                brute.evaluations,
                bruteMs
            )
        end
        -- The seeds exercise both weapon choices.
        assert.is_true(kinds["2H"] == true and kinds["1H+OH"] == true)
        assert.equal(#SEEDS, #evals)
        say("search evaluations over %d seeds: %s; slowest search %.1f ms", #SEEDS, table.concat(evals, ", "), slowest)
    end)

    it("crosses a tier threshold that pays only at four pieces, which a lone sweep cannot", function()
        local found = false
        for _, seed in ipairs(SEEDS) do
            local items = inventory(seed)
            local w = weights(1.0001, 1.12)
            local best = assert(ns.EngineSearch.Best(items, w, OPTS))
            local brute = assert(ns.EngineSearch.BruteForce(items, w, OPTS))
            assert.is_true(close(best.value, brute.value), "seed " .. seed)
            if tierCount(brute.items) >= 4 then
                found = true
                -- Without the masks, the ascent from the plain pieces stays below four.
                local pools = ns.EngineSearch.Candidates(items, w, OPTS).pools
                local lone = assert(ns.EngineSearch.Ascend(pools, nil, w, nil, OPTS))
                assert.is_true(lone.value < brute.value)
                assert.is_true(tierCount(lone.items) < 4)
            end
        end
        assert.is_true(found)
    end)

    it("never wears two copies of the unique ring, though both are the best rings by stats", function()
        for _, seed in ipairs(SEEDS) do
            local items = inventory(seed)
            local best = assert(ns.EngineSearch.Best(items, weights(), OPTS))
            -- The copy's key is the original's plus ":copy".
            local original
            for _, item in ipairs(items) do
                local base = item.key:match("^(.*):copy$")
                if base then
                    original = base
                end
            end
            local copies = 0
            for _, item in ipairs(best.items) do
                if item.key == original or item.key == original .. ":copy" then
                    copies = copies + 1
                end
            end
            assert.equal(1, copies)
            assert.is_true(ns.EngineSearch.UniqueOK(best.items))
        end
    end)

    it("holds a unique limit category across positions: a ring and a neck that share it", function()
        for _, seed in ipairs({ 1, 2, 3 }) do
            local items = inventory(seed)
            -- The best neck and the best plain ring share a category with a
            -- limit of one: the hook, not the pair options, has to keep them
            -- apart.
            local neck, ring
            for _, item in ipairs(items) do
                if item.slot == "Neck" and (not neck or item.int > neck.int) then
                    neck = item
                end
                if item.slot == "Finger" and not item.uniqueness and (not ring or item.int > ring.int) then
                    ring = item
                end
            end
            for _, item in ipairs({ neck, ring }) do
                item.uniqueness = { category = 77, max = 1 }
                for _, stat in ipairs({ "int", "haste", "crit", "mastery", "vers" }) do
                    item[stat] = item[stat] + 400
                end
            end
            local w = weights()
            local best = assert(ns.EngineSearch.Best(items, w, OPTS))
            local brute = assert(ns.EngineSearch.BruteForce(items, w, OPTS))
            local both = 0
            for _, item in ipairs(best.items) do
                if item == neck or item == ring then
                    both = both + 1
                end
            end
            assert.equal(1, both, "seed " .. seed)
            assert.is_true(close(best.value, brute.value), "seed " .. seed)
            assert.equal(keysOf(brute.items), keysOf(best.items))
        end
    end)

    -- E-1e (WKE-703): E-1d's defect in its smallest form. Neck A and ring R
    -- share a limit category of one. The ascent starts on A (the best neck by
    -- proxy), so every ring pair holding R is infeasible; A alone is worth more
    -- than the plain neck B beside the plain rings, so no single move leaves A.
    -- The optimum is B with R - two coordinates at once, which only the
    -- coupled sweep tries.
    it("leaves a limit-category neck for a better ring in the same category (two positions at once)", function()
        local function crit(id, slot, rating, category)
            return {
                itemID = id,
                key = "e1e:" .. id,
                slot = slot,
                level = 300,
                int = 0,
                haste = 0,
                crit = rating,
                mastery = 0,
                vers = 0,
                leech = 0,
                sockets = 0,
                gems = {},
                ready = true,
                uniqueness = category and { isUnique = false, category = category, max = 1 } or nil,
            }
        end
        local items = {
            crit(970001, "Neck", 400, 77), -- A
            crit(970002, "Neck", 100), -- B
            crit(970003, "Finger", 800, 77), -- R
            crit(970004, "Finger", 50), -- P1
            crit(970005, "Finger", 40), -- P2
        }
        local w = weights()
        local best = assert(ns.EngineSearch.Best(items, w, OPTS))
        local brute = assert(ns.EngineSearch.BruteForce(items, w, OPTS))
        assert.equal("e1e:970002 e1e:970003 e1e:970004", keysOf(brute.items))
        assert.equal(keysOf(brute.items), keysOf(best.items))
        assert.is_true(close(best.value, brute.value))
        local pools = ns.EngineSearch.Candidates(items, w, OPTS).pools
        local ascent = assert(ns.EngineSearch.Ascend(pools, nil, w, nil, OPTS))
        assert.equal(1, ascent.coupledMoves)
        assert.is_true(ascent.coupledPasses >= 2)
    end)

    it("agrees with brute force when the rating is the client's conversion (the stub's)", function()
        local items = inventory(3)
        local w = weights()
        local opts = { contentType = "Dungeon" }
        local best = assert(ns.EngineSearch.Best(items, w, opts))
        local brute = assert(ns.EngineSearch.BruteForce(items, w, opts))
        assert.is_true(close(best.value, brute.value))
        assert.equal(keysOf(brute.items), keysOf(best.items))
    end)

    it("refuses a brute force over the cap", function()
        local items = inventory(1)
        local result, why = ns.EngineSearch.BruteForce(items, weights(), { dr = "table", cap = 10 })
        assert.is_nil(result)
        assert.truthy(why:find("too many sets", 1, true))
    end)
end)

describe("ns.EngineSearch's outclassed-piece drop", function()
    local ns
    before_each(function()
        ns = loaded()
    end)
    after_each(function()
        H.unload()
    end)

    it("never drops the optimum: brute force over the kept pieces equals brute force over all", function()
        local droppedTotal = 0
        for _, seed in ipairs(SEEDS) do
            local items = inventory(seed)
            local w = weights()
            local all = assert(ns.EngineSearch.BruteForce(items, w, OPTS))
            local kept =
                assert(ns.EngineSearch.BruteForce(items, w, { dr = "table", contentType = "Dungeon", prune = true }))
            assert.is_true(close(kept.value, all.value), "seed " .. seed)
            assert.equal(keysOf(all.items), keysOf(kept.items))
            local c = ns.EngineSearch.Candidates(items, w, OPTS)
            droppedTotal = droppedTotal + #c.dropped
            assert.is_true(kept.sets < all.sets)
        end
        -- The guard is not vacuous: every seed drops the Legs and Waist spares
        -- and the low ring.
        assert.is_true(droppedTotal >= 3 * #SEEDS)
    end)

    it("keeps a ring outclassed by one piece only: a pair needs two", function()
        local w = weights()
        local function ring(id, v)
            return {
                itemID = id,
                key = "r" .. id,
                slot = "Finger",
                int = v,
                haste = v,
                crit = v,
                mastery = v,
                vers = v,
                leech = 0,
                sockets = 0,
                gems = {},
            }
        end
        local items = {
            ring(1, 300),
            ring(2, 290),
            { -- a third ring, strong in one stat only
                itemID = 3,
                key = "r3",
                slot = "Finger",
                int = 100,
                haste = 600,
                crit = 0,
                mastery = 0,
                vers = 0,
                leech = 0,
                sockets = 0,
                gems = {},
            },
        }
        local c = ns.EngineSearch.Candidates(items, w, OPTS)
        assert.equal(0, #c.dropped)
        assert.equal(3, #c.pools.Finger)
        local best = assert(ns.EngineSearch.Best(items, w, OPTS))
        local brute = assert(ns.EngineSearch.BruteForce(items, w, OPTS))
        assert.is_true(close(best.value, brute.value))
        assert.equal("r1 r2", keysOf(brute.items))
    end)

    it("never drops a piece with an effect entry, nor lets a limit-category piece outclass", function()
        local w = weights()
        local trinketA = {
            itemID = 1,
            key = "a",
            slot = "Trinket",
            int = 500,
            haste = 500,
            crit = 0,
            mastery = 0,
            vers = 0,
            leech = 0,
            sockets = 0,
            gems = {},
        }
        local trinketB = deepcopy(trinketA)
        trinketB.itemID, trinketB.key, trinketB.int = 2, "b", 10
        local trinketC = deepcopy(trinketA)
        trinketC.itemID, trinketC.key = 3, "c"
        local c = ns.EngineSearch.Candidates({ trinketA, trinketB, trinketC }, w, OPTS)
        -- Synthetic trinkets are not in the effects table: EffectOf says
        -- "unknown", so none of them is dropped.
        assert.equal(0, #c.dropped)
        local wristA = {
            itemID = 11,
            key = "wa",
            slot = "Wrist",
            int = 500,
            haste = 500,
            crit = 0,
            mastery = 0,
            vers = 0,
            leech = 0,
            sockets = 0,
            gems = {},
            uniqueness = { category = 7, max = 1 },
        }
        local wristB = deepcopy(wristA)
        wristB.itemID, wristB.key, wristB.int, wristB.uniqueness = 12, "wb", 10, nil
        c = ns.EngineSearch.Candidates({ wristA, wristB }, w, OPTS)
        assert.equal(0, #c.dropped)
        wristA.uniqueness = nil
        c = ns.EngineSearch.Candidates({ wristA, wristB }, w, OPTS)
        assert.equal(1, #c.dropped)
        assert.equal("wb", c.dropped[1].item.key)
    end)
end)

describe("ns.EngineSearch constraint hooks", function()
    local ns
    before_each(function()
        ns = loaded()
    end)
    after_each(function()
        H.unload()
    end)

    it("honours a hook that rejects, and still equals brute force under it", function()
        local items = inventory(2)
        local w = weights()
        local free = assert(ns.EngineSearch.Best(items, w, OPTS))
        local banned = free.items[1].key
        local hook = function(set)
            for _, item in ipairs(set) do
                if item.key == banned then
                    return false, "banned"
                end
            end
            return true
        end
        local opts = { dr = "table", contentType = "Dungeon", constraints = { hook } }
        local best = assert(ns.EngineSearch.Best(items, w, opts))
        local brute = assert(ns.EngineSearch.BruteForce(items, w, opts))
        for _, item in ipairs(best.items) do
            assert.are_not.equal(banned, item.key)
        end
        assert.is_true(best.value < free.value)
        assert.is_true(close(best.value, brute.value))
        assert.equal(keysOf(brute.items), keysOf(best.items))
    end)

    it("carries the embellishment, vault and Catalyst hooks, empty until a field can be read", function()
        local names = {}
        for _, hook in ipairs(ns.EngineSearch.HOOKS) do
            names[#names + 1] = hook.name
        end
        assert.same({ "unique", "embellishments", "vault", "catalyst" }, names)
        local items = inventory(1)
        assert.is_true(ns.EngineSearch.EmbellishmentsOK(items))
        assert.is_true(ns.EngineSearch.VaultOK(items))
        assert.is_true(ns.EngineSearch.CatalystOK(items))
        assert.is_false((ns.EngineSearch.UniqueOK({
            { itemID = 5, uniqueness = { isUnique = true } },
            { itemID = 5, uniqueness = { isUnique = true } },
        })))
        assert.is_false((ns.EngineSearch.UniqueOK({
            { itemID = 5, uniqueness = { category = 9, max = 1 } },
            { itemID = 6, uniqueness = { category = 9, max = 1 } },
        })))
    end)
end)

describe("ns.EngineSearch.Run, the coroutine under a frame budget", function()
    local ns, world
    before_each(function()
        ns, world = loaded()
    end)
    after_each(function()
        H.unload()
    end)

    -- A clock that moves one millisecond per read: the 5 ms budget is used up
    -- after a handful of evaluations, whatever the machine.
    local function fakeClock()
        local t = 0
        return function()
            t = t + 1
            return t
        end
    end

    local function drive(job, onEach)
        local frames = 0
        while not job.done do
            frames = frames + 1
            assert(frames < 100000, "runaway")
            local update = job.frame.scripts.OnUpdate
            if update then
                update(job.frame, 0.016)
            end
            if onEach then
                onEach(frames)
            end
        end
        return frames
    end

    it("yields when the budget is spent and resumes to the answer Best gives", function()
        local items = inventory(4)
        local w = weights()
        local direct = assert(ns.EngineSearch.Best(items, w, OPTS))
        local got
        local opts = { dr = "table", contentType = "Dungeon", clock = fakeClock() }
        local job = assert(ns.EngineSearch.Run(items, w, opts, function(result, why, j)
            got = { result = result, why = why, job = j }
        end))
        assert.is_true(ns.EngineSearch.Running())
        drive(job)
        assert.is_false(ns.EngineSearch.Running())
        assert.is_truthy(got.result, got.why)
        assert.is_true(got.job.slices > 1)
        assert.equal(direct.value, got.result.value)
        assert.equal(keysOf(direct.items), keysOf(got.result.items))
        assert.equal(direct.evaluations, got.result.evaluations)
        assert.is_nil(job.frame.scripts.OnUpdate)
    end)

    it("stops in combat and picks up after PLAYER_REGEN_ENABLED, to the same answer", function()
        local items = inventory(5)
        local w = weights()
        local direct = assert(ns.EngineSearch.Best(items, w, OPTS))
        local got
        local opts = { dr = "table", contentType = "Dungeon", clock = fakeClock() }
        local job = assert(ns.EngineSearch.Run(items, w, opts, function(result, _, j)
            got = { result = result, job = j }
        end))
        local fought = false
        drive(job, function(frames)
            if frames == 3 and not fought then
                fought = true
                world.inCombat = true
                job.frame.scripts.OnUpdate(job.frame, 0.016)
                -- Stopped: no OnUpdate, waiting for the event.
                assert.is_nil(job.frame.scripts.OnUpdate)
                assert.is_true(job.frame.events.PLAYER_REGEN_ENABLED == true)
                local slices = job.slices
                world.inCombat = false
                assert.equal(slices, job.slices)
                world.fireEvent("PLAYER_REGEN_ENABLED")
                assert.is_function(job.frame.scripts.OnUpdate)
            end
        end)
        assert.equal(1, got.job.pauses)
        assert.equal(direct.value, got.result.value)
        assert.equal(keysOf(direct.items), keysOf(got.result.items))
    end)

    it("stops for good when the switch is turned off mid-run", function()
        local got
        local job = assert(ns.EngineSearch.Run(inventory(1), weights(), {
            dr = "table",
            contentType = "Dungeon",
            clock = fakeClock(),
        }, function(result, why)
            got = { result = result, why = why }
        end))
        job.frame.scripts.OnUpdate(job.frame, 0.016)
        ns.db.global.developer.engine = nil
        drive(job)
        assert.is_nil(got.result)
        assert.equal("not on", got.why)
    end)

    it("runs one search at a time", function()
        local job = assert(ns.EngineSearch.Run(inventory(1), weights(), { dr = "table", clock = fakeClock() }))
        local second, why = ns.EngineSearch.Run(inventory(1), weights(), { dr = "table" })
        assert.is_nil(second)
        assert.equal(ns.EngineSearch.TEXT.running, why)
        drive(job)
    end)
end)

describe("ns.EngineSearch's refusals, determinism and stores", function()
    local ns, world
    before_each(function()
        ns, world = loaded()
    end)
    after_each(function()
        H.unload()
    end)

    it("refuses every entry point with the switch off", function()
        ns.db.global.developer = nil
        local items, w = inventory(1), weights()
        for _, call in ipairs({
            function()
                return ns.EngineSearch.Best(items, w, OPTS)
            end,
            function()
                return ns.EngineSearch.BruteForce(items, w, OPTS)
            end,
            function()
                return ns.EngineSearch.Run(items, w, OPTS)
            end,
            function()
                return ns.EngineSearch.Ascend(ns.EngineSearch.Candidates(items, w, OPTS).pools, nil, w, nil, OPTS)
            end,
        }) do
            local result, why = call()
            assert.is_nil(result)
            assert.equal("not on", why)
        end
        ns.HandleSlash("engine best")
        assert.equal(ns.PREFIX .. "not on", world.output())
    end)

    it("refuses every entry point in combat", function()
        world.inCombat = true
        local items, w = inventory(1), weights()
        local result, why = ns.EngineSearch.Best(items, w, OPTS)
        assert.is_nil(result)
        assert.equal("Out of combat only.", why)
        result, why = ns.EngineSearch.Run(items, w, OPTS)
        assert.is_nil(result)
        assert.equal("Out of combat only.", why)
        result, why = ns.EngineSearch.BruteForce(items, w, OPTS)
        assert.is_nil(result)
        assert.equal("Out of combat only.", why)
        ns.HandleSlash("engine best")
        assert.equal(ns.PREFIX .. "Out of combat only.", world.output())
    end)

    it("answers the same, byte for byte, twice", function()
        local function once()
            local r = assert(ns.EngineSearch.Best(inventory(6), weights(), OPTS))
            local positions = {}
            for i, p in ipairs(r.positions) do
                positions[i] = { position = p.position, pieces = keysOf(p.pieces), delta = p.delta }
            end
            return S.serialize({
                value = r.value,
                items = keysOf(r.items),
                evaluations = r.evaluations,
                masks = r.masks,
                positions = positions,
            })
        end
        assert.equal(once(), once())
    end)

    it("is read by no UI file", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") then
                if readAll("Lootpath/" .. f):find("EngineSearch", 1, true) then
                    readers[#readers + 1] = f
                end
            end
        end
        assert.same({}, readers)
    end)

    it("names every client function the file calls", function()
        local source = readAll("Lootpath/Modules/EngineSearch.lua")
        source = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
        source = source:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
        local named = {}
        for _, name in ipairs(ns.EngineSearch.FUNCTION_NAMES) do
            named[name] = true
        end
        local unnamed = {}
        for token in source:gmatch("[%a_][%w_]*") do
            if token:match("^[A-Z]") or token:match("^C_") or token == "debugprofilestop" then
                local value = _G[token]
                if (type(value) == "function" or type(value) == "table") and not named[token] then
                    unnamed[#unnamed + 1] = token
                end
            end
        end
        assert.same({}, unnamed)
    end)
end)

-- The owner's own inventory of 2026-09-16 (inventory read 3), its pieces read
-- through the SYNTHETIC stats rule.
local function realWorld()
    local ns, world = H.load()
    local db = R.load(SV)
    ns.db.char = deepcopy(db.char[CHAR])
    ns.db.global = deepcopy(db.global)
    ns.db.global.developer = { engine = true }
    R.inventory(world, R.snapshot("inventory", DRESSED, SV))
    local w = dofile(WEIGHTS)
    ns.engineWeights = w
    assert(ns.EngineScore.Load())
    local entries = {}
    for _, record in ipairs(ns.Inventory.Scan().records) do
        entries[#entries + 1] = { link = record.link, level = record.itemLevel }
    end
    Stats.install(world, entries)
    return ns, world
end

describe("ns.EngineSearch over the owner's real inventory (synthetic stats)", function()
    local ns, world
    before_each(function()
        ns, world = realWorld()
    end)
    after_each(function()
        H.unload()
    end)

    -- The memo (docs/OWN-ENGINE.md section 5) listed Feet 4 and 54 pieces;
    -- the scan of the same read names five Feet pieces (two copies of
    -- Miststalker's Striders among them), 55 in all.
    it("reads the inventory it says it reads: 55 pieces by slot", function()
        assert.equal("2026-09-16T15:29:53", R.snapshot("inventory", DRESSED, SV).capturedAtLocal)
        local counts = {}
        local records = ns.Inventory.Scan().records
        for _, record in ipairs(records) do
            counts[record.slot] = (counts[record.slot] or 0) + 1
        end
        assert.equal(55, #records)
        assert.same({
            Head = 2,
            Neck = 2,
            Shoulder = 4,
            Back = 3,
            Chest = 2,
            Wrist = 3,
            Hands = 1,
            Waist = 5,
            Legs = 4,
            Feet = 5,
            Finger = 5,
            Trinket = 14,
            ["1H Weapon"] = 2,
            ["2H Weapon"] = 3,
        }, counts)
    end)

    it("prints the evaluation count and the time of a search, synchronously and at a 5 ms frame budget", function()
        local records = ns.Inventory.Scan().records
        local reads = {}
        for _, record in ipairs(records) do
            reads[record.link] = ns.EngineStats.ForLink(record.link)
        end
        local items, counts = ns.EngineSearch.Vectors(records, reads)
        assert.equal(55, #items)
        assert.equal(0, counts.notReady)
        local w = ns.EngineScore.file
        local opts = { contentType = "Dungeon" }
        local t0 = debugprofilestop()
        local best = assert(ns.EngineSearch.Best(items, w, opts))
        local ms = debugprofilestop() - t0
        local c = ns.EngineSearch.Candidates(items, w, opts)
        local sizes = {}
        for _, pool in ipairs({
            "Head",
            "Neck",
            "Shoulder",
            "Back",
            "Chest",
            "Wrist",
            "Hands",
            "Waist",
            "Legs",
            "Feet",
            "Finger",
            "Trinket",
            "1H Weapon",
            "2H Weapon",
        }) do
            sizes[#sizes + 1] = pool .. " " .. #(c.pools[pool] or {})
        end
        say(
            "real inventory (2026-09-16 read 3, synthetic stats): %d pieces, %d kept, %d outclassed;"
                .. " kept by position: %s",
            #items,
            c.kept,
            #c.dropped,
            table.concat(sizes, ", ")
        )
        say(
            "real inventory: %d evaluations (%d ascent, %d runner-up), %d masks, %.1f ms synchronous"
                .. " (%.1f us per evaluation)",
            best.evaluations,
            best.ascentEvaluations,
            best.evaluations - best.ascentEvaluations,
            best.masks,
            ms,
            1000 * ms / best.evaluations
        )
        -- What enumerating would cost: brute force refuses, naming the count.
        local _, allWhy = ns.EngineSearch.BruteForce(items, w, opts)
        local _, keptWhy = ns.EngineSearch.BruteForce(items, w, { contentType = "Dungeon", prune = true })
        assert.truthy(allWhy:find("too many sets", 1, true))
        say("real inventory, brute force over every piece: %s", allWhy)
        say("real inventory, brute force over the kept pieces: %s", keptWhy)
        local got
        local job = assert(ns.EngineSearch.Run(items, w, opts, function(result, _, j)
            got = { result = result, job = j }
        end))
        local frames = 0
        while not job.done do
            frames = frames + 1
            assert(frames < 100000, "runaway")
            job.frame.scripts.OnUpdate(job.frame, 0.016)
        end
        assert.equal(best.value, got.result.value)
        say(
            "real inventory at a 5 ms budget: %d frames, %.1f ms of work, %.1f ms start to finish",
            got.job.slices,
            got.job.busyMs,
            got.job.wallMs
        )
        assert.is_true(best.evaluations > 0)
    end)

    it("prints the search in chat with the provenance line, writing no store", function()
        local before = S.serialize({
            qe = ns.db.global.qeImports,
            uf = ns.db.global.ufImports,
            ec = ns.db.global.engineCompare,
            char = ns.db.char,
        })
        world.printed = {}
        local run
        ns.EngineCompare.Command("best dungeon", function(r)
            run = r
        end)
        -- The search runs on OnUpdate: drive the module's frame.
        local guard = 0
        while not run do
            guard = guard + 1
            assert(guard < 100000, "runaway")
            for _, f in ipairs(world.frames) do
                if f.scripts.OnUpdate then
                    f.scripts.OnUpdate(f, 0.016)
                end
            end
        end
        local out = world.output()
        assert.truthy(
            out:find("engine best - weights synthetic, patch 12.1.0, derived never - Dungeon, band 10+", 1, true)
        )
        assert.truthy(out:find("  Head: ", 1, true))
        assert.truthy(out:find("  Finger 1: ", 1, true))
        assert.truthy(out:find("  Trinket 2: ", 1, true))
        assert.truthy(out:find("  Weapon: ", 1, true))
        assert.truthy(out:find("best set ", 1, true))
        assert.truthy(out:find(" set values over ", 1, true))
        assert.truthy(out:find("left out: 0 not ready, 0 secret, 0 not for this spec, ", 1, true))
        assert.is_nil(out:lower():find("plan", 1, true))
        assert.is_true(run.result.value >= run.wornValue)
        local after = S.serialize({
            qe = ns.db.global.qeImports,
            uf = ns.db.global.ufImports,
            ec = ns.db.global.engineCompare,
            char = ns.db.char,
        })
        assert.equal(before, after)
        for _, line in ipairs(world.printed) do
            say("chat: %s", line)
        end
    end)
end)

-- E-1b (WKE-688): what the runner-up line says. The owner's 2026-10-05 screens
-- printed `next best -0.000%` on every single slot and the weapon: the
-- runner-up compared option TABLES across two calls (always different), so
-- the "alternative" was the position's own piece. A position with no other
-- piece now says `only piece`; a different piece worth exactly as much says
-- `tie` and names it. And a `no band` refusal lists the bands the file
-- carries for the content type, with the command's usage.
describe("ns.EngineSearch's runner-up words and the no-band refusal", function()
    local ns, world
    before_each(function()
        ns, world = loaded()
    end)
    after_each(function()
        H.unload()
    end)

    local function item(id, slot, int, extra)
        local v = {
            itemID = id,
            key = "e1b:" .. id,
            name = "Piece " .. id,
            slot = slot,
            level = 300,
            int = int,
            stamina = 0,
            haste = 100,
            crit = 100,
            mastery = 100,
            vers = 100,
            leech = 0,
            sockets = 0,
            gems = {},
            ready = true,
        }
        for k, x in pairs(extra or {}) do
            v[k] = x
        end
        return v
    end

    -- Head: a strong and a weak piece (the weak one has more haste, so it is
    -- not outclassed and stays a candidate); Legs: one piece; trinkets: a
    -- strong one and two different pieces with the same stats. (Two equal
    -- single-slot pieces never tie: the outclass drop keeps the first. A
    -- trinket is never dropped - the effects table decides it - so two equal
    -- trinkets stay, as the owner's Oculus and Mycolic Medicine did.)
    local function small()
        return {
            item(980001, "Head", 300),
            item(980002, "Head", 200, { haste = 150 }),
            item(980003, "Legs", 250),
            item(980004, "Trinket", 120),
            item(980005, "Trinket", 120),
            item(980006, "Trinket", 150),
        }
    end

    local function byPosition(result)
        local out = {}
        for _, p in ipairs(result.positions) do
            out[p.position] = p
        end
        return out
    end

    it("names another piece as the runner-up, never the position's own", function()
        local r = assert(ns.EngineSearch.Best(small(), weights(), OPTS))
        local head = byPosition(r).Head
        assert.equal(980001, head.pieces[1].itemID)
        assert.equal(980002, head.alternative[1].itemID)
        assert.equal("next", head.state)
        assert.equal(2, head.candidates)
        assert.is_true(head.delta > 0)
    end)

    it("says `only piece` for a position with one candidate and `tie` for an equal other piece", function()
        local r = assert(ns.EngineSearch.Best(small(), weights(), OPTS))
        local p = byPosition(r)
        assert.equal("only", p.Legs.state)
        assert.equal(1, p.Legs.candidates)
        assert.is_nil(p.Legs.alternative)
        local tie
        for _, position in ipairs({ "Trinket 1", "Trinket 2" }) do
            if p[position].pieces[1].itemID ~= 980006 then
                tie = p[position]
            end
        end
        assert.equal("tie", tie.state)
        assert.equal(2, tie.candidates) -- itself and the other, its partner kept
        assert.are_not.equal(tie.pieces[1].itemID, tie.alternative[1].itemID)
        assert.equal(0, tie.delta)
        local lines = ns.EngineSearch.Lines({ file = weights(), contentType = "Dungeon", result = r })
        local text = table.concat(lines, "\n")
        assert.truthy(text:find("  Legs: Piece 980003 300 · bag · only piece", 1, true))
        assert.truthy(text:find("· next best tie: Piece 98000", 1, true))
        assert.truthy(text:find("  Head: Piece 980001 300 · bag · next best -", 1, true))
        assert.is_nil(text:find("-0.000%", 1, true))
    end)

    it("lists the bands the file carries and the usage when it finds no band", function()
        ns.engineWeights = dofile("spec/fixtures/engine/weights-fitted-shape.lua")
        ns.EngineScore.file = nil
        assert(ns.EngineScore.Load())
        world.printed = {}
        local run
        ns.EngineCompare.Command("best dungeon", function(r)
            run = r
        end)
        local guard = 0
        while not run do
            guard = guard + 1
            assert(guard < 1000, "runaway")
            for _, f in ipairs(world.frames) do
                if f.scripts.OnUpdate then
                    f.scripts.OnUpdate(f, 0.016)
                end
            end
        end
        local out = world.output()
        assert.truthy(out:find("engine best found no set: no band\n", 1, true))
        assert.truthy(
            out:find(
                "bands the weights file carries for Dungeon: 2, 4, 6, 8, 10."
                    .. " usage: /lootpath engine best dungeon <n> | raid",
                1,
                true
            )
        )
        -- With a key level the file has no band for, the same listing.
        local lines =
            ns.EngineSearch.Lines({ file = ns.EngineScore.file, contentType = "Raid", why = "no band for +7" })
        assert.equal(
            "bands the weights file carries for Raid: raid-3. usage: /lootpath engine best dungeon <n> | raid",
            lines[3]
        )
        assert.same({ "2", "4", "6", "8", "10" }, ns.EngineSearch.BandKeys(ns.EngineScore.file, nil, "Dungeon"))
    end)
end)
