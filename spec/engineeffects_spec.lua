-- spec/engineeffects_spec.lua (E-3a, WKE-679)
-- ns.EngineEffects and Data/EngineEffects.lua: each generic rule on
-- hand-made params against a value computed by hand in the comment beside it;
-- nil params, and the kinds no rule covers, answer `not modelled`; the
-- shipped table's classification (25 trinkets by kind, the four effect
-- armour and weapon pieces); every itemID found in the repo's own data; the
-- chunk discipline; a pure module; no UI file naming it. Since E-3c
-- (WKE-686): the params filled from the effects transcript - three entries
-- `generic` with every field their rule reads at every level they list,
-- every number found in spec/fixtures/engine/effects-real.lua at its level,
-- every `not_modelled` entry still `not modelled` at every level, and a level
-- the capture did not read never answered.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local SHIPPED = "Lootpath/Data/EngineEffects.lua"
local MODULE = "Lootpath/Modules/EngineEffects.lua"
local SV = "spec/fixtures/captures/Lootpath-20260916-162655.lua"
local WALK_KEY = "69587|18|105|2:8:15:16:23"
local EFFECTS = "spec/fixtures/engine/effects-real.lua"

-- What each rule reads before it answers (this spec's own reading of
-- Lootpath/Modules/EngineEffects.lua): a flat heal's rate is
-- `procsPerMinute` or `cooldown`, listed here as the cooldown.
local RULE_READS = {
    passive_stat = { "stat" },
    stat_proc = { "stat", "amount", "rppm", "duration" },
    stat_on_use = { "stat", "amount", "duration", "cooldown" },
    flat_heal = { "heal", "cooldown", "overheal", "targets" },
    heal_on_use = { "amount", "cooldown", "overheal" },
}

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
                or line:match("^%s*%[%d+%] = { [%a_]+ = %d+ },$")
                or line:match("^%s*%[%d+%] = { stat = { [%a_]+ = %d+ } },$")
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

    -- docs/OWN-ENGINE.md section 4's classification, counted off the file;
    -- since E-3c (WKE-686) the numbers the effects transcript gave.
    it("classifies the season's 25 trinkets and four effect pieces, with numbers only where read", function()
        local t = loadShipped().engineEffects
        local trinkets, others = {}, {}
        local n = 0
        local generic, withParams = {}, {}
        for id, entry in pairs(t.items) do
            n = n + 1
            if entry.confidence == "generic" then
                generic[#generic + 1] = id
            else
                assert.equal("not_modelled", entry.confidence, id)
            end
            if entry.params ~= nil then
                withParams[#withParams + 1] = id
            end
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
        -- Generic: the three whose tooltip gives every field the rule reads.
        table.sort(generic)
        assert.same({ 250215, 273649, 274495 }, generic)
        -- Params: every item whose effect text the capture read and whose
        -- kind a rule covers; never the eight the capture found nowhere,
        -- never a kind no rule reads.
        table.sort(withParams)
        assert.same({
            193748,
            250214,
            250215,
            250248,
            250254,
            250255,
            251789,
            270162,
            270171,
            273649,
            273796,
            274495,
        }, withParams)
        local Effects = dofile(EFFECTS)
        for _, m in ipairs(Effects.MISSING) do
            assert.is_table(t.items[m.itemID], m.itemID)
            assert.is_nil(t.items[m.itemID].params, m.itemID)
            assert.equal("not_modelled", t.items[m.itemID].confidence, m.itemID)
        end
        assert.equal(8, #Effects.MISSING)
        for id, entry in pairs(t.items) do
            if not RULE_READS[entry.kind] then
                assert.is_nil(entry.params, id)
            end
        end
    end)

    -- E-3c: every generic entry carries, at every level it lists, every field
    -- its rule reads - the list below is this spec's own reading of each rule
    -- in Lootpath/Modules/EngineEffects.lua, not the module's.
    it("gives every generic entry every field its rule reads, at every level it lists", function()
        local t = loadShipped().engineEffects
        local ns = { engineEffects = t }
        assert(loadfile(MODULE))("Lootpath", ns)
        local checked = 0
        for id, entry in pairs(t.items) do
            if entry.confidence == "generic" then
                local reads = RULE_READS[entry.kind]
                assert.is_table(reads, id)
                assert.is_table(entry.params.byLevel, id)
                for level in pairs(entry.params.byLevel) do
                    local p = ns.EngineEffects.ParamsAt(entry.params, level)
                    for _, field in ipairs(reads) do
                        assert.is_not_nil(p[field], string.format("%d@%d lacks %s", id, level, field))
                    end
                    local answer = ns.EngineEffects.Evaluate(entry, level)
                    assert.is_table(answer, string.format("%d@%d", id, level))
                    assert.equal("generic", answer.confidence)
                    checked = checked + 1
                end
            end
        end
        assert.equal(14, checked) -- 2 Oculus levels, 8 Flask, 4 Emblem
    end)

    -- E-3c: every number in the table is a string the client wrote, at the
    -- level the entry files it under. Amounts are found among the effect
    -- line's own digits (`numbers`, as the client wrote them, "34,166") on a
    -- record whose tooltip says "Item Level <level>"; a duration as "<n>
    -- sec" in that text; a cooldown as the text's "(N Min M Sec Cooldown)".
    it("cites every number to effects-real.lua at the level it is filed under", function()
        local Effects = dofile(EFFECTS)
        local function grouped(n)
            local s = tostring(n)
            local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
            return (out:gsub("^,", ""))
        end
        local function linesAt(id, level)
            local out = {}
            for _, r in ipairs(Effects.RECORDS) do
                if r.itemID == id then
                    for _, read in ipairs({ r, r.again or {} }) do
                        if read.itemLevelLine == "Item Level " .. level then
                            for _, e in ipairs(read.effects or {}) do
                                out[#out + 1] = e
                            end
                        end
                    end
                end
            end
            return out
        end
        local function cooldownOf(text)
            local inner = text:match("%(([^()]*Cooldown)%)")
            if not inner then
                return nil
            end
            inner = inner:gsub("|4", "")
            local mins = tonumber(inner:match("(%d+) Min")) or 0
            local secs = tonumber(inner:match("(%d+) Sec")) or 0
            return mins * 60 + secs
        end
        local cited = 0
        for id, entry in pairs(loadShipped().engineEffects.items) do
            if entry.params then
                for level, at in pairs(entry.params.byLevel) do
                    local lines = linesAt(id, level)
                    assert.is_true(#lines > 0, string.format("no effect line for %d at %d", id, level))
                    local values = {}
                    for k, v in pairs(at) do
                        if type(v) == "table" then
                            for _, x in pairs(v) do
                                values[#values + 1] = x
                            end
                        else
                            values[#values + 1] = v
                        end
                        assert.is_not_nil(k)
                    end
                    for _, v in ipairs(values) do
                        local found = false
                        for _, e in ipairs(lines) do
                            for _, s in ipairs(e.numbers) do
                                found = found or s == grouped(v)
                            end
                        end
                        assert.is_true(found, string.format("%d@%d: %s is not in the client's text", id, level, v))
                        cited = cited + 1
                    end
                    if entry.params.duration then
                        local found = false
                        for _, e in ipairs(lines) do
                            found = found or e.text:find(entry.params.duration .. " sec", 1, true) ~= nil
                        end
                        assert.is_true(found, string.format("%d@%d: duration", id, level))
                    end
                    if entry.params.cooldown then
                        local found = false
                        for _, e in ipairs(lines) do
                            found = found or cooldownOf(e.text) == entry.params.cooldown
                        end
                        assert.is_true(found, string.format("%d@%d: cooldown", id, level))
                    end
                end
            end
        end
        assert.equal(64, cited)
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

    -- E-3c: a `not_modelled` entry still reads `not modelled` - with no
    -- level, and at every level it carries numbers for - so the compare
    -- still leaves its row out as `not rated`; a `generic` entry answers only
    -- at a level the capture read.
    it("answers every not_modelled entry as not modelled at every level it carries", function()
        local notModelled = 0
        for id, entry in pairs(ns.engineEffects.items) do
            assert.equal(entry, ns.EngineEffects.Classify(id))
            assert.same({ nil, "not modelled" }, { ns.EngineEffects.Evaluate(entry) }, id)
            if entry.confidence == "not_modelled" then
                notModelled = notModelled + 1
                local levels = entry.params and entry.params.byLevel or { [308] = true }
                for level in pairs(levels) do
                    assert.same(
                        { nil, "not modelled" },
                        { ns.EngineEffects.Evaluate(entry, level) },
                        string.format("%d@%d", id, level)
                    )
                end
            end
        end
        assert.equal(26, notModelled)
        assert.is_nil(ns.EngineEffects.Classify(999999))
        assert.is_nil(ns.EngineEffects.Classify(nil))
        assert.is_nil(ns.EngineEffects.Classify(270162, { schema = "other", version = 1, items = {} }))
    end)

    it("reads params at the item's level only, never between levels", function()
        -- Freightrunner's Flask: 608 crit at 305, 617 at 308, both for 15 s
        -- every 90 s: 608 * 15 / 90 = 101.333..., 617 * 15 / 90 = 102.833...
        local flask = ns.engineEffects.items[250215]
        near(608 * 15 / 90, ns.EngineEffects.Evaluate(flask, 305).stat.crit, "flask 305")
        near(617 * 15 / 90, ns.EngineEffects.Evaluate(flask, 308).stat.crit, "flask 308")
        -- 306 sits between two levels read: not modelled, never interpolated.
        assert.same({ nil, "not modelled" }, { ns.EngineEffects.Evaluate(flask, 306) })
        assert.same({ nil, "not modelled" }, { ns.EngineEffects.Evaluate(flask, nil) })
        -- Pulse Seeker's Oculus: the always-on Mastery at the level read.
        assert.same(
            { stat = { mastery = 92 }, confidence = "generic" },
            ns.EngineEffects.Evaluate(ns.engineEffects.items[274495], 308)
        )
        -- ParamsAt lays the level's fields over the shared ones and keeps no
        -- `byLevel`; params without `byLevel` pass through as they are.
        assert.same(
            { stat = "crit", duration = 15, cooldown = 90, amount = 608 },
            ns.EngineEffects.ParamsAt(flask.params, 305)
        )
        local flat = { amount = 1, cooldown = 2 }
        assert.equal(flat, ns.EngineEffects.ParamsAt(flat, 999))
        assert.is_nil(ns.EngineEffects.ParamsAt({ byLevel = { [1] = { amount = 1 } } }, 2))
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
