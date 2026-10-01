-- spec/engineeffects_spec.lua (E-3a, WKE-679)
-- ns.EngineEffects and Data/EngineEffects.lua: each generic rule on
-- hand-made params against a value computed by hand in the comment beside it;
-- nil params, and the kinds no rule covers, answer `not modelled`; the
-- shipped table's classification (25 trinkets by kind, the four effect
-- armour and weapon pieces, every entry `not_modelled` with `params = nil`);
-- every itemID found in the repo's own data; the chunk discipline; a pure
-- module; no UI file naming it.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local SHIPPED = "Lootpath/Data/EngineEffects.lua"
local MODULE = "Lootpath/Modules/EngineEffects.lua"
local SV = "spec/fixtures/captures/Lootpath-20260916-162655.lua"
local WALK_KEY = "69587|18|105|2:8:15:16:23"

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function loadShipped()
    local ns = {}
    assert(loadfile(SHIPPED))("Lootpath", ns)
    return ns
end

local function near(expected, actual, what)
    assert.is_number(actual, what)
    assert.is_true(
        math.abs(expected - actual) < 1e-6,
        string.format("%s: expected %.9f, got %.9f", what, expected, actual)
    )
end

describe("Data/EngineEffects.lua", function()
    it("sets exactly one field on the namespace and nothing else", function()
        local keys = {}
        for key in pairs(loadShipped()) do
            keys[#keys + 1] = key
        end
        assert.same({ "engineEffects" }, keys)
    end)

    it("is inert: loaded twice it is the same table, loaded with no namespace it returns", function()
        assert.same(loadShipped().engineEffects, loadShipped().engineEffects)
        local chunk = assert(loadfile(SHIPPED))
        local before = _G.engineEffects
        assert.has_no.errors(function()
            chunk()
        end)
        assert.equal(before, _G.engineEffects)
    end)

    it("holds no call, loop or function", function()
        for line in readAll(SHIPPED):gmatch("[^\n]+") do
            local ok = line:match("^%-%-")
                or line:match("^%s+%-%- ")
                or line:match("^local _, ns = %.%.%.$")
                or line:match('^if type%(ns%) ~= "table" then$')
                or line:match("^%s*return$")
                or line:match("^end$")
                or line:match('^%s*[%w_.]+ = "[^"]*",?$')
                or line:match("^%s*[%w_.]+ = %-?[%d.]+,?$")
                or line:match("^%s*params = nil,$")
                or line:match("^%s*sets = {},$")
                or line:match("^%s*[%w_.]+ = {$")
                or line:match("^%s*%[%d+%] = {$")
                or line:match("^%s*},?$")
            assert.is_truthy(ok, "unexpected line in a data-only chunk: " .. line)
            assert.is_falsy(line:match("^[^%-]*%f[%w]function%f[%W]"), line)
            assert.is_falsy(line:match("^[^%-]*%f[%w]for%f[%W]"), line)
            assert.is_falsy(line:match("^[^%-]*%f[%w]while%f[%W]"), line)
            if line ~= 'if type(ns) ~= "table" then' then
                assert.is_falsy(line:match("^[^%-]*[%w_%]]%("), "a call: " .. line)
            end
        end
    end)

    it("carries its schema, version, patch and season", function()
        local t = loadShipped().engineEffects
        assert.equal("lootpath-engine-effects", t.schema)
        assert.equal(1, t.version)
        assert.equal("12.1.0", t.patch)
        assert.equal(2, t.season)
        assert.is_string(t.derivedAt)
        assert.is_string(t.source)
        assert.same({}, t.sets)
    end)

    -- docs/OWN-ENGINE.md section 4's classification, counted off the file.
    it("classifies the season's 25 trinkets and four effect pieces, and ships no numbers", function()
        local t = loadShipped().engineEffects
        local trinkets, others = {}, {}
        local n = 0
        for id, entry in pairs(t.items) do
            n = n + 1
            assert.equal("not_modelled", entry.confidence, id)
            assert.is_nil(entry.params, id)
            assert.is_string(entry.name, id)
            local bucket = entry.slot == "Trinket" and trinkets or others
            bucket[entry.kind] = (bucket[entry.kind] or 0) + 1
        end
        assert.equal(29, n)
        assert.same({
            passive_stat = 1,
            stat_proc = 5,
            stat_on_use = 3,
            flat_heal = 5,
            heal_on_use = 6,
            unique = 4,
            unknown = 1,
        }, trinkets)
        assert.same({ unknown = 3, damage_only = 1 }, others)
        assert.equal("damage_only", t.items[273778].kind)
        for _, id in ipairs({ 270164, 270167, 270169, 193757 }) do
            assert.equal("unique", t.items[id].kind, id)
        end
    end)

    -- Every ID is in the committed walk's journalCache or in an export under
    -- spec/fixtures/qe/, under the slot the entry names.
    it("names only items the repo's own data carries, at the slot it carries them", function()
        local walk = R.load(SV).global.journalCache[WALK_KEY].sources
        local exports = {}
        local list = assert(io.popen("ls spec/fixtures/qe/*.json"))
        for path in list:lines() do
            exports[#exports + 1] = readAll(path)
        end
        list:close()
        assert.is_true(#exports > 20)
        local inWalk, inExports = 0, 0
        for id, entry in pairs(loadShipped().engineEffects.items) do
            local rows = walk[id]
            local found = false
            if rows then
                inWalk = inWalk + 1
                found = true
                assert.equal(entry.slot, rows[1].slot, id)
                assert.equal(entry.name, rows[1].name, id)
            end
            local pattern = '"id": ' .. id .. ',%s*"level": %d+,[^}]-"slot": "([^"]+)"'
            local slotPattern = '"slot": "([^"]+)",%s*"id": ' .. id .. ","
            for _, text in ipairs(exports) do
                local slot = text:match(slotPattern) or text:match(pattern)
                if slot then
                    assert.equal(entry.slot, slot, id)
                    found = true
                    inExports = inExports + 1
                    break
                end
            end
            assert.is_true(found, "no repo data carries " .. id)
        end
        assert.equal(19, inWalk)
        assert.equal(28, inExports) -- all but Forgotten Farstrider's Insignia
    end)
end)

describe("ns.EngineEffects rules", function()
    local ns
    before_each(function()
        ns = H.load()
    end)
    after_each(function()
        H.unload()
    end)

    it("passes a passive stat through", function()
        local r = ns.EngineEffects.PassiveStat({ stat = { haste = 120 } })
        assert.same({ stat = { haste = 120 }, confidence = "generic" }, r)
    end)

    it("averages an RPPM stat proc with bad-luck protection", function()
        -- rppm 2, 15 s: x = 2 * 15 / 60 = 0.5; e^-0.5 = 0.6065306597;
        -- uptime = 1.131 * (1 - 0.6065306597) = 0.4450138239; 1000 * that.
        local r = ns.EngineEffects.StatProc({ stat = "crit", amount = 1000, rppm = 2, duration = 15 })
        near(445.0138239, r.stat.crit, "stat proc")
        assert.equal("generic", r.confidence)
        -- Haste-scaled at 25% haste: rppm 2.5, x = 0.625, e^-0.625 = 0.5352614285;
        -- 1.131 * 0.4647385715 = 0.5256193244.
        local h = ns.EngineEffects.StatProc({
            stat = "crit",
            amount = 1000,
            rppm = 2,
            duration = 15,
            hasteScaled = true,
            haste = 0.25,
        })
        near(525.6193244, h.stat.crit, "haste-scaled proc")
        -- Uptime never passes 1: rppm 10, 30 s gives 1.131 * (1 - e^-5) = 1.1234.
        local capped = ns.EngineEffects.StatProc({ stat = "haste", amount = 500, rppm = 10, duration = 30 })
        assert.equal(500, capped.stat.haste)
        -- Haste-scaled without a haste figure: not modelled, never guessed.
        local missing =
            { ns.EngineEffects.StatProc({ stat = "crit", amount = 1, rppm = 1, duration = 1, hasteScaled = true }) }
        assert.same({ nil, "not modelled" }, missing)
    end)

    it("averages a stat on-use over its cooldown", function()
        -- 600 * 20 / 120 = 100.
        local r = ns.EngineEffects.StatOnUse({ stat = "haste", amount = 600, duration = 20, cooldown = 120 })
        assert.equal(100, r.stat.haste)
        -- A buff as long as its cooldown is always up.
        local always = ns.EngineEffects.StatOnUse({ stat = "vers", amount = 50, duration = 60, cooldown = 30 })
        assert.equal(50, always.stat.vers)
    end)

    it("turns a flat heal proc into healing per second", function()
        -- 20000 * 3 per minute * (1 - 0.25) * 2 targets / 60 = 1500.
        local r = ns.EngineEffects.FlatHeal({ heal = 20000, procsPerMinute = 3, overheal = 0.25, targets = 2 })
        assert.equal(1500, r.hps)
        assert.equal("generic", r.confidence)
        -- A 30 s cooldown is 2 per minute: 20000 * 2 * 0.75 * 2 / 60 = 1000.
        local cd = ns.EngineEffects.FlatHeal({ heal = 20000, cooldown = 30, overheal = 0.25, targets = 2 })
        assert.equal(1000, cd.hps)
        -- No overheal or no targets: a judgement number is missing, not defaulted.
        assert.same(
            { nil, "not modelled" },
            { ns.EngineEffects.FlatHeal({ heal = 1, procsPerMinute = 1, targets = 1 }) }
        )
        assert.same(
            { nil, "not modelled" },
            { ns.EngineEffects.FlatHeal({ heal = 1, procsPerMinute = 1, overheal = 0 }) }
        )
    end)

    it("turns a heal or absorb on use into healing per second", function()
        -- 90000 * (1 - 0.2) / 90 = 800.
        local r = ns.EngineEffects.HealOnUse({ amount = 90000, cooldown = 90, overheal = 0.2 })
        assert.equal(800, r.hps)
        assert.same({ nil, "not modelled" }, { ns.EngineEffects.HealOnUse({ amount = 90000, cooldown = 90 }) })
        assert.same(
            { nil, "not modelled" },
            { ns.EngineEffects.HealOnUse({ amount = 90000, cooldown = 90, overheal = 1 }) }
        )
    end)

    it("answers not modelled for nil params, a kind no rule covers, and a broken param", function()
        for _, kind in ipairs({ "passive_stat", "stat_proc", "stat_on_use", "flat_heal", "heal_on_use" }) do
            assert.same({ nil, "not modelled" }, { ns.EngineEffects.Evaluate({ kind = kind, params = nil }) }, kind)
        end
        local params = { amount = 90000, cooldown = 90, overheal = 0.2, stat = { haste = 1 } }
        for _, kind in ipairs({ "unique", "unknown", "damage_only" }) do
            assert.same({ nil, "not modelled" }, { ns.EngineEffects.Evaluate({ kind = kind, params = params }) }, kind)
        end
        assert.same(
            { nil, "not modelled" },
            { ns.EngineEffects.StatOnUse({ stat = "spirit", amount = 1, duration = 1, cooldown = 1 }) }
        )
        assert.same({ nil, "not modelled" }, { ns.EngineEffects.PassiveStat({ stat = { haste = "1" } }) })
        -- A kind a rule covers, with params, is evaluated by that rule.
        local r =
            ns.EngineEffects.Evaluate({ kind = "heal_on_use", params = { amount = 900, cooldown = 9, overheal = 0 } })
        assert.equal(100, r.hps)
    end)

    it("answers every shipped entry as not modelled today", function()
        for id, entry in pairs(ns.engineEffects.items) do
            assert.equal(entry, ns.EngineEffects.Classify(id))
            assert.same({ nil, "not modelled" }, { ns.EngineEffects.Evaluate(entry) }, id)
        end
        assert.is_nil(ns.EngineEffects.Classify(999999))
        assert.is_nil(ns.EngineEffects.Classify(nil))
        assert.is_nil(ns.EngineEffects.Classify(270162, { schema = "other", version = 1, items = {} }))
    end)
end)

describe("ns.EngineEffects is pure", function()
    after_each(function()
        H.unload()
    end)

    it("asks the client nothing", function()
        local ns = H.load()
        local calls, saved = 0, {}
        for name, value in pairs(_G) do
            if type(name) == "string" and name:match("^[A-Z]") and type(value) == "function" then
                saved[#saved + 1] = { name, value }
                _G[name] = function(...)
                    calls = calls + 1
                    return value(...)
                end
            end
        end
        ns.EngineEffects.StatProc({ stat = "crit", amount = 1000, rppm = 2, duration = 15 })
        ns.EngineEffects.FlatHeal({ heal = 1, procsPerMinute = 1, overheal = 0, targets = 1 })
        for id, entry in pairs(ns.engineEffects.items) do
            ns.EngineEffects.Classify(id)
            ns.EngineEffects.Evaluate(entry)
        end
        for _, pair in ipairs(saved) do
            _G[pair[1]] = pair[2]
        end
        assert.equal(0, calls)
    end)

    it("names no client function in its source", function()
        local ns = H.load()
        assert.same({}, ns.EngineEffects.FUNCTION_NAMES)
        local source = readAll(MODULE)
        source = source:gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""')
        local unnamed = {}
        for token in source:gmatch("[%a_][%w_]*") do
            if token:match("^[A-Z]") or token:match("^C_") then
                local value = _G[token]
                if type(value) == "function" or type(value) == "table" then
                    unnamed[#unnamed + 1] = token
                end
            end
        end
        assert.same({}, unnamed)
    end)

    it("is read by no UI file, nor is its table", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") then
                local text = readAll("Lootpath/" .. f)
                if text:find("EngineEffects", 1, true) or text:find("engineEffects", 1, true) then
                    readers[#readers + 1] = f
                end
            end
        end
        assert.same({}, readers)
    end)

    it("is in the .toc, the table before the module, both before EngineScore", function()
        local order = {}
        for i, f in ipairs(H.tocFiles()) do
            order[f] = i
        end
        assert.is_number(order["Data/EngineEffects.lua"])
        assert.is_number(order["Modules/EngineEffects.lua"])
        assert.is_true(order["Data/EngineEffects.lua"] < order["Modules/EngineEffects.lua"])
        assert.is_true(order["Modules/EngineEffects.lua"] < order["Modules/EngineScore.lua"])
    end)
end)
