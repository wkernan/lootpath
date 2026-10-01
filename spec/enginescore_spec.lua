-- spec/enginescore_spec.lua (E-0c, WKE-672)
-- ns.EngineScore and Data/EngineWeights.lua: the loader's refusals with their
-- exact sentences, a set value equal to a hand computation AND to E-0e's
-- score.js fixture to six decimals, DR monotonic through the table path, the
-- parity mode's assumed finish, the tier multiplier at 2 and 4 pieces only,
-- the upgrade percent's placements, determinism, purity, timing, and no UI
-- file reading the module.
--
-- SYNTHETIC: every weight here is invented. spec/fixtures/engine/
-- score-fixture.json is E-0e's tools/engine/test/fixtures/score-fixture.json
-- copied verbatim from origin/lp-e0e-fit-weights at c76a26a (PR #298, on main
-- as 2a6932e since its merge, 19f8e44); its
-- expected values were computed by tools/engine/lib/score.js and checked by
-- hand there, so this file and score.js guard each other.
local H = require("spec.helpers.addon")

local WEIGHTS = "spec/fixtures/engine/weights-synthetic.lua"
local FITTED = "spec/fixtures/engine/weights-fitted-shape.lua"
local SCORE_FIXTURE = "spec/fixtures/engine/score-fixture.json"
local SHIPPED = "Lootpath/Data/EngineWeights.lua"

local STATS = { "int", "haste", "crit", "mastery", "vers", "leech" }

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

-- An EngineStats-shaped vector plus a slot.
local function vec(slot, stats, extra)
    local v = { slot = slot, sockets = 0, gems = {}, stamina = 0, armor = 0 }
    for _, k in ipairs(STATS) do
        v[k] = (stats and stats[k]) or 0
    end
    for k, x in pairs(extra or {}) do
        v[k] = x
    end
    return v
end

local function fromFixture(item)
    return vec(item.slot, item.stats, { setID = item.setId })
end

local function near(expected, actual, what)
    assert.is_number(actual, what)
    assert.is_true(
        math.abs(expected - actual) < 5e-7,
        string.format("%s: expected %.9f, got %.9f", what, expected, actual)
    )
end

local function loadShipped()
    local ns = {}
    assert(loadfile(SHIPPED))("Lootpath", ns)
    return ns
end

describe("Data/EngineWeights.lua", function()
    it("sets exactly one field on the namespace and nothing else", function()
        local keys = {}
        for key in pairs(loadShipped()) do
            keys[#keys + 1] = key
        end
        assert.same({ "engineWeights" }, keys)
    end)

    it("is inert: loaded twice it is the same table, loaded with no namespace it returns", function()
        assert.same(loadShipped().engineWeights, loadShipped().engineWeights)
        local chunk = assert(loadfile(SHIPPED))
        local before = _G.engineWeights
        assert.has_no.errors(function()
            chunk()
        end)
        assert.equal(before, _G.engineWeights)
    end)

    -- A one-line table of `key = number` fields only, under an optional
    -- `key =` or `[n] =`: `{ from = 1320, penalty = 0.1 },`.
    local function isNumberTable(line)
        local body = line:match("^%s*{ (.-) },?$")
            or line:match("^%s*[%a_][%w_]* = { (.-) },?$")
            or line:match("^%s*%[%-?%d+%] = { (.-) },?$")
        if not body then
            return false
        end
        local rest = (body .. ", "):gsub("[%a_][%w_]* = %-?%d+%.?%d*, ", "")
        return rest == ""
    end

    it("does not wave through a one-line table that could run something", function()
        assert.is_true(isNumberTable("                { from = 1320, penalty = 0.1 },"))
        assert.is_true(isNumberTable("            [2] = { mult = 1.111 },"))
        assert.is_true(isNumberTable("        weights = { int = 1, haste = 1 },"))
        assert.is_false(isNumberTable("        weights = { int = os.time() },"))
        assert.is_false(isNumberTable("        weights = { int = ns.x },"))
        assert.is_false(isNumberTable('        weights = { int = "1" },'))
        assert.is_false(isNumberTable("        [f()] = { mult = 1 },"))
    end)

    it("holds no call, loop or function", function()
        for line in readAll(SHIPPED):gmatch("[^\n]+") do
            local ok = line:match("^%-%-")
                or line:match("^local _, ns = %.%.%.$")
                or line:match('^if type%(ns%) ~= "table" then$')
                or line:match("^%s*return$")
                or line:match("^end$")
                or line:match('^%s*[%w_.]+ = "[^"]*",?$')
                or line:match("^%s*[%w_.]+ = %-?[%d.]+,?$")
                or line:match("^%s*[%w_.]+ = {$")
                or line:match('^%s*%[%-?[%d"+%w]+%] = {$')
                or line:match("^%s*},?$")
                or isNumberTable(line)
            assert.is_truthy(ok, "unexpected line in a data-only chunk: " .. line)
            assert.is_falsy(line:match("^[^%-]*%f[%w]function%f[%W]"), line)
            assert.is_falsy(line:match("^[^%-]*%f[%w]for%f[%W]"), line)
            assert.is_falsy(line:match("^[^%-]*%f[%w]while%f[%W]"), line)
            if line ~= 'if type(ns) ~= "table" then' then
                assert.is_falsy(line:match("^[^%-]*[%w_%]]%("), "a call: " .. line)
            end
        end
    end)

    it("is the placeholder, and says so", function()
        local file = loadShipped().engineWeights
        assert.equal("lootpath-engine-weights", file.schema)
        assert.equal(1, file.version)
        assert.equal("placeholder", file.method)
        assert.equal("12.1.0", file.patch)
        assert.equal("never", file.derivedAt)
        assert.is_table(file.specs[105].Dungeon.bands["10+"])
        assert.is_table(file.specs[105].Raid)
        assert.truthy(readAll(SHIPPED):find("SYNTHETIC PLACEHOLDER", 1, true))
    end)

    -- Both carry E-0e's lib/dr.js brackets; a typo in either turns this red.
    it("carries the same DR brackets as the synthetic fixture", function()
        assert.same(dofile(WEIGHTS).dr, loadShipped().engineWeights.dr)
    end)
end)

describe("ns.EngineScore.Load", function()
    after_each(function()
        H.unload()
    end)

    it("loads the shipped file at login and prints nothing with the developer switch off", function()
        local ns, world = H.load()
        assert.equal("placeholder", ns.EngineScore.status)
        assert.equal(ns.engineWeights, ns.EngineScore.file)
        assert.is_nil(world.output():find("ratings", 1, true))
        assert.is_nil(world.output():find("Not rated", 1, true))
    end)

    it("says it loaded a placeholder, once, when the developer switch is on", function()
        local ns, world = H.load({ loaded = false })
        table.insert(ns.onReady, 1, function()
            ns.db.global.developer = { engine = true }
        end)
        world.fireEvent("ADDON_LOADED", H.ADDON)
        local _, n = world.output():gsub(
            "Engine ratings for 12%.1%.0 loaded %- placeholder numbers, none of them mean anything%.",
            ""
        )
        assert.equal(1, n)
    end)

    it("refuses a file whose patch is not the client's, in one sentence", function()
        local ns, world = H.load({ loaded = false })
        world.build[1] = "12.1.5"
        table.insert(ns.onReady, 1, function()
            ns.db.global.developer = { engine = true }
        end)
        world.fireEvent("ADDON_LOADED", H.ADDON)
        assert.is_nil(ns.EngineScore.file)
        assert.equal("Update Lootpath - its ratings are for 12.1.0, you're on 12.1.5.", ns.EngineScore.refusal)
        assert.truthy(world.output():find("Update Lootpath - its ratings are for 12.1.0, you're on 12.1.5.", 1, true))
    end)

    it("is silent about a refusal too with the developer switch off", function()
        local _, world = H.load({
            beforeLoad = function(w)
                w.build[1] = "12.1.5"
            end,
        })
        assert.equal("", world.output():gsub("[^\n]*loaded%. /lootpath opens[^\n]*", ""))
    end)

    local function refusedWith(mutate)
        local ns = H.load()
        mutate(ns)
        local ok, sentence = ns.EngineScore.Load()
        return ns, ok, sentence
    end

    local BROKEN = "Not rated - the rating data didn't load."

    it("refuses a missing file", function()
        local ns, ok, sentence = refusedWith(function(ns)
            ns.engineWeights = nil
        end)
        assert.is_false(ok)
        assert.equal(BROKEN, sentence)
        assert.is_nil(ns.EngineScore.file)
        assert.equal("refused", ns.EngineScore.status)
    end)

    it("refuses another schema", function()
        local _, ok, sentence = refusedWith(function(ns)
            ns.engineWeights.schema = "something-else"
        end)
        assert.is_false(ok)
        assert.equal(BROKEN, sentence)
    end)

    it("refuses another version", function()
        local _, ok, sentence = refusedWith(function(ns)
            ns.engineWeights.version = 2
        end)
        assert.is_false(ok)
        assert.equal(BROKEN, sentence)
    end)

    it("refuses a file without a spec table", function()
        local _, ok, sentence = refusedWith(function(ns)
            ns.engineWeights.specs = nil
        end)
        assert.is_false(ok)
        assert.equal(BROKEN, sentence)
        local _, ok2 = refusedWith(function(ns)
            ns.engineWeights.specs = {}
        end)
        assert.is_false(ok2)
    end)

    it("refuses when the client's version cannot be read", function()
        local _, ok, sentence = refusedWith(function()
            _G.GetBuildInfo = function()
                return nil
            end
        end)
        assert.is_false(ok)
        assert.equal(BROKEN, sentence)
    end)

    it("makes no value from a refused file", function()
        local ns = refusedWith(function(ns)
            ns.engineWeights.patch = "12.0.7"
        end)
        local value, why = ns.EngineScore.SetValue({ vec("Head", { int = 10 }) }, { dr = "table" })
        assert.is_nil(value)
        assert.equal("Update Lootpath - its ratings are for 12.0.7, you're on 12.1.0.", why)
    end)
end)

describe("ns.EngineScore.SetValue", function()
    local ns, world, W, F

    before_each(function()
        ns, world = H.load()
        W = dofile(WEIGHTS)
        F = ns.json.decode(readAll(SCORE_FIXTURE))
    end)

    after_each(function()
        H.unload()
    end)

    local function worn()
        local out = {}
        for i, item in ipairs(F.worn) do
            out[i] = fromFixture(item)
        end
        return out
    end

    local function opts(extra)
        local o = { file = W, dr = "table", forceTier = true }
        for k, v in pairs(extra or {}) do
            o[k] = v
        end
        return o
    end

    -- The copy and E-0e's own fixture are one file: a change to either side
    -- without the other turns this red.
    it("scores against a byte-identical copy of E-0e's score fixture", function()
        assert.equal(readAll("tools/engine/test/fixtures/score-fixture.json"), readAll(SCORE_FIXTURE))
    end)

    it("scores with the fixture's own model", function()
        local band = W.specs[105].Dungeon.bands["10+"]
        assert.equal(F.model.baseValue, band.baseValue)
        for _, k in ipairs(STATS) do
            assert.equal(F.model.weights[k], band.weights[k], k)
            assert.equal(F.model.assumedFinish[k] or 0, band.assumedBuffs[k] or 0, k)
        end
        assert.equal(1, #F.model.tiers.setIDs)
        assert.equal(F.model.tiers.setIDs[1], (next(W.tiers)))
        assert.is_nil(next(W.tiers, F.model.tiers.setIDs[1]))
        near(1 + F.model.tiers.twoPiece, W.tiers[2057][2].mult, "2pc")
        near(1 + F.model.tiers.fourPiece, W.tiers[2057][4].mult, "4pc")
    end)

    it("equals a hand computation of the worn set", function()
        local r = assert(ns.EngineScore.SetValue(worn(), opts()))
        -- Totals: int 200+150+600 +100 assumed; haste 300+400 +50; crit
        -- 200+300; mastery 300+900; vers 300+100. All under the first DR
        -- bracket, so each percent is rating / rating-per-percent.
        local hand = (1000 + 1050 + 20 * 750 / 44 + 15 * 500 / 46 + 18 * 1200 / 46 + 12 * 400 / 54 + 5 * 0) * 1.085
        near(hand, r.value, "worn value by hand")
        assert.same({ int = 1050, haste = 750, crit = 500, mastery = 1200, vers = 400, leech = 0 }, r.totals)
    end)

    it("equals score.js's worn features and value to six decimals", function()
        local r = assert(ns.EngineScore.SetValue(worn(), opts()))
        near(F.expected.wornFeatures.int, r.totals.int, "int")
        for _, k in ipairs({ "haste", "crit", "mastery", "vers", "leech" }) do
            near(F.expected.wornFeatures[k], r.pcts[k], k)
        end
        near(F.expected.wornValue, r.value, "wornValue")
    end)

    it("equals score.js's upgrade percent in every fixture case, to six decimals", function()
        assert.is_true(#F.cases >= 5)
        for _, case in ipairs(F.cases) do
            local percent, detail = ns.EngineScore.UpgradePercent(worn(), fromFixture(case.item), opts())
            if case.comparable then
                near(case.percent, percent, case.name)
                near(case.clampedPercent, math.max(0, percent), case.name .. " (clamped)")
                local replaced = {}
                for i, index in ipairs(case.replaced) do
                    replaced[i] = index + 1
                end
                assert.same(replaced, detail.replaced, case.name)
            else
                assert.is_nil(percent, case.name)
                assert.equal("not comparable", detail, case.name)
            end
        end
    end)

    it("crosses a DR bracket the way a hand computation does", function()
        -- The fixture's first case: haste 300 + 400 + 1000 + 50 = 1750, 430
        -- of it past 1320 at a 10% penalty.
        local set = worn()
        set[3] = fromFixture(F.cases[1].item)
        local r = assert(ns.EngineScore.SetValue(set, opts()))
        assert.equal(1750, r.totals.haste)
        near((1320 + 430 * 0.9) / 44, r.pcts.haste, "haste past 1320")
    end)

    it("is monotonic through the table path for every rating", function()
        for _, stat in ipairs({ "haste", "crit", "mastery", "vers", "leech" }) do
            local prevPct, prevValue = -1, -math.huge
            for rating = 0, 12000, 25 do
                local r = assert(ns.EngineScore.SetValue({ vec("Head", { [stat] = rating }) }, opts()))
                assert.is_true(r.pcts[stat] >= prevPct, stat .. " at " .. rating)
                assert.is_true(r.value >= prevValue, stat .. " value at " .. rating)
                prevPct, prevValue = r.pcts[stat], r.value
            end
            -- And it does diminish: the last 1000 rating before the cap buys
            -- less than the first 1000.
            local tbl = W.dr[stat]
            local cap = tbl.brackets[#tbl.brackets].from
            local first = ns.EngineScore.TablePercent(1000, tbl)
            local last = ns.EngineScore.TablePercent(cap, tbl) - ns.EngineScore.TablePercent(cap - 1000, tbl)
            assert.is_true(last < first, stat)
        end
    end)

    it("converts through the client by default, after the sum", function()
        _G.GetCombatRatingBonusForCombatRatingValue = nil
        local seen = {}
        local r = assert(ns.EngineScore.SetValue(worn(), {
            file = W,
            forceTier = true,
            rating = function(index, value)
                seen[#seen + 1] = { index, value }
                return value / 10, false
            end,
        }))
        -- One call per rating, each with the SET's total, not an item's.
        assert.same({ { 20, 750 }, { 11, 500 }, { 26, 1200 }, { 29, 400 }, { 17, 0 } }, seen)
        assert.equal(75, r.pcts.haste)
    end)

    it("uses ns.EngineStats.Rating when no rating function is given, and nothing in combat", function()
        -- The stub converts as the client does (E-0f: diminishing returns
        -- applied, the published brackets); the worn set crosses no bracket,
        -- so the client path lands on score.js's value.
        local r = assert(ns.EngineScore.SetValue(worn(), { file = W, forceTier = true }))
        near(F.expected.wornValue, r.value, "client path")
        world.inCombat = true
        local value, why = ns.EngineScore.SetValue(worn(), { file = W, forceTier = true })
        assert.is_nil(value)
        assert.equal("unrated", why)
    end)

    it("refuses a secret rating and a missing one", function()
        local value, why = ns.EngineScore.SetValue(worn(), {
            file = W,
            rating = function()
                return nil, true
            end,
        })
        assert.is_nil(value)
        assert.equal("secret", why)
        value, why = ns.EngineScore.SetValue(worn(), {
            file = W,
            rating = function()
                return nil, false
            end,
        })
        assert.is_nil(value)
        assert.equal("unrated", why)
    end)

    it("adds each item's own gems outside the parity mode", function()
        local ring = vec(
            "Finger",
            { haste = 100 },
            { sockets = 2, gems = { { id = 1, stats = vec(nil, { haste = 999 }) } } }
        )
        local r = assert(ns.EngineScore.SetValue({ ring }, opts()))
        assert.equal(100 + 999 + 50, r.totals.haste)
        assert.equal(0, r.totals.mastery)
    end)

    it("in the parity mode ignores the item's gems, counts its sockets and adds its slot's enchant", function()
        local ring = vec(
            "Finger",
            { haste = 100 },
            { sockets = 2, gems = { { id = 1, stats = vec(nil, { haste = 999 }) } } }
        )
        local r = assert(ns.EngineScore.SetValue({ ring }, opts({ assumedFinish = true })))
        -- 100 own + 2 sockets x 10 assumed + 50 buff; mastery from the
        -- Finger enchant; no Chest enchant on a ring.
        assert.equal(100 + 2 * 10 + 50, r.totals.haste)
        assert.equal(5, r.totals.mastery)
        assert.equal(100, r.totals.int)
        local bare = vec("Finger", { haste = 100 }, { sockets = 0 })
        assert.equal(100 + 50, assert(ns.EngineScore.SetValue({ bare }, opts({ assumedFinish = true }))).totals.haste)
    end)

    it("multiplies by the tier bonus at 2 and 4 pieces, and not at 1 or 3", function()
        local expected = { 1, 1.03, 1.03, 1.085, 1.085 }
        for pieces = 1, 5 do
            local set = {}
            for i = 1, pieces do
                set[i] = vec("Slot" .. i, { int = 10 }, { setID = 2057 })
            end
            set[#set + 1] = vec("Neck", { int = 10 }, { setID = 9999 })
            local r = assert(ns.EngineScore.SetValue(set, opts({ forceTier = false })))
            near(expected[pieces], r.tier.mult, pieces .. " pieces")
            assert.equal(2057, r.tier.setID)
            assert.equal(pieces, r.tier.count)
            near((1000 + 10 * (pieces + 1) + 100 + 20 * 50 / 44) * expected[pieces], r.value, pieces .. " value")
        end
        local none = assert(ns.EngineScore.SetValue({ vec("Head", { int = 10 }) }, opts({ forceTier = false })))
        assert.equal(1, none.tier.mult)
        assert.is_nil(none.tier.setID)
    end)

    it("forced on, the tier bonus is whole whatever the set wears", function()
        local r = assert(ns.EngineScore.SetValue({ vec("Head", { int = 10 }) }, opts({ forceTier = true })))
        near(1.085, r.tier.mult, "forced")
        assert.equal(2057, r.tier.setID)
        assert.equal(0, r.tier.count)
        assert.is_true(r.tier.forced)
    end)

    -- E-3a (WKE-679): the effects table decides. Soulcoiler Ritual Vessel
    -- (270162) is in the shipped table with no numbers; 999999 is in no table.
    it("scores a trinket the table carries on its stats, and names its effect as not modelled", function()
        local plain = assert(ns.EngineScore.SetValue({ vec("Head", { int = 150 }) }, opts()))
        local marked = assert(ns.EngineScore.SetValue({ vec("Trinket", { int = 150 }, { itemID = 270162 }) }, opts()))
        assert.equal(plain.value, marked.value) -- the stats still count
        assert.is_nil(plain.effectUnmodelled)
        assert.is_true(marked.effectUnmodelled)
        assert.same({ { itemID = 270162, name = "Soulcoiler Ritual Vessel", kind = "heal_on_use" } }, marked.unmodelled)
        assert.same({}, marked.effects)
        assert.is_nil(marked.effectUnknown)
    end)

    it("scores a trinket the table does not carry on plain stats, and says its effect is unknown", function()
        local plain = assert(ns.EngineScore.SetValue({ vec("Head", { int = 150 }) }, opts()))
        local r = assert(ns.EngineScore.SetValue({ vec("Trinket", { int = 150 }, { itemID = 999999 }) }, opts()))
        assert.equal(plain.value, r.value)
        assert.is_true(r.effectUnknown)
        assert.same({ { itemID = 999999 } }, r.unknown)
        assert.is_nil(r.effectUnmodelled)
        -- A non-trinket the table does not carry is a plain item.
        local head = assert(ns.EngineScore.SetValue({ vec("Head", { int = 150 }, { itemID = 999999 }) }, opts()))
        assert.is_nil(head.effectUnknown)
    end)

    local function effectsWith(entry)
        return {
            schema = "lootpath-engine-effects",
            version = 1,
            items = { [42] = entry },
            sets = {},
        }
    end

    it("adds a modelled stat effect's vector to the totals before the conversion", function()
        local effects = effectsWith({
            name = "Hand-made",
            slot = "Trinket",
            kind = "stat_on_use",
            confidence = "generic",
            params = { stat = "haste", amount = 600, duration = 20, cooldown = 120 },
        })
        local bare = assert(ns.EngineScore.SetValue({ vec("Trinket", { int = 150 }) }, opts()))
        local r = assert(
            ns.EngineScore.SetValue({ vec("Trinket", { int = 150 }, { itemID = 42 }) }, opts({ effects = effects }))
        )
        -- 600 x 20 / 120 = 100 haste on average, by hand.
        assert.equal(bare.totals.haste + 100, r.totals.haste)
        assert.is_true(r.value > bare.value)
        assert.equal(1, #r.effects)
        assert.equal("generic", r.effects[1].confidence)
        assert.same({ haste = 100 }, r.effects[1].stat)
        assert.is_nil(r.effectUnmodelled)
    end)

    it("keeps a modelled healing effect beside the value, added only through hpsPerValue", function()
        local effects = effectsWith({
            name = "Hand-made",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "generic",
            params = { amount = 90000, cooldown = 90, overheal = 0.2 },
        })
        local bare = assert(ns.EngineScore.SetValue({ vec("Trinket", { int = 150 }) }, opts()))
        local items = { vec("Trinket", { int = 150 }, { itemID = 42 }) }
        local kept = assert(ns.EngineScore.SetValue(items, opts({ effects = effects })))
        -- 90000 x 0.8 / 90 = 800 hps, by hand; no rate in the file: not added.
        assert.equal(800, kept.effects[1].hps)
        assert.equal(bare.value, kept.value)
        assert.is_true(kept.hpsNotAdded)
        local file = dofile(WEIGHTS)
        file.hpsPerValue = 4
        local added = assert(ns.EngineScore.SetValue(items, opts({ effects = effects, file = file })))
        local bareSame = assert(ns.EngineScore.SetValue({ vec("Trinket", { int = 150 }) }, opts({ file = file })))
        -- 800 / 4 = 200 points of value before the tier multiplier.
        near(bareSame.value + 200 * bareSame.tier.mult, added.value, "hps through hpsPerValue")
        assert.is_nil(added.hpsNotAdded)
    end)

    it("is deterministic", function()
        local a = assert(ns.EngineScore.SetValue(worn(), opts()))
        local b = assert(ns.EngineScore.SetValue(worn(), opts()))
        assert.same(a, b)
        local p1, d1 = ns.EngineScore.UpgradePercent(worn(), fromFixture(F.cases[1].item), opts())
        local p2, d2 = ns.EngineScore.UpgradePercent(worn(), fromFixture(F.cases[1].item), opts())
        assert.equal(p1, p2)
        assert.same(d1, d2)
    end)

    it("refuses without a band to score with", function()
        local value, why = ns.EngineScore.SetValue(worn(), opts({ contentType = "Raid" }))
        assert.is_nil(value)
        assert.equal("no band", why)
    end)

    -- Every WoW function on the stub (capitalised globals and the C_
    -- namespaces) wrapped with a counter: SetValue and UpgradePercent with a
    -- rating function handed in, or on the table path, ask the client nothing.
    it("asks the client nothing but the rating function it is handed", function()
        local calls, saved = 0, {}
        for name, value in pairs(_G) do
            if type(name) == "string" and name:match("^[A-Z]") and type(value) == "function" then
                saved[#saved + 1] = { _G, name, value }
                _G[name] = function(...)
                    calls = calls + 1
                    return value(...)
                end
            elseif type(name) == "string" and name:match("^C_") and type(value) == "table" then
                for member, fn in pairs(value) do
                    if type(fn) == "function" then
                        saved[#saved + 1] = { value, member, fn }
                        value[member] = function(...)
                            calls = calls + 1
                            return fn(...)
                        end
                    end
                end
            end
        end
        local rated = 0
        local ok, err = pcall(function()
            ns.EngineScore.SetValue(worn(), opts())
            ns.EngineScore.UpgradePercent(worn(), fromFixture(F.cases[1].item), opts())
            ns.EngineScore.SetValue(worn(), {
                file = W,
                rating = function(_, value)
                    rated = rated + 1
                    return value / 40, false
                end,
            })
        end)
        for _, s in ipairs(saved) do
            s[1][s[2]] = s[3]
        end
        assert.is_true(ok, tostring(err))
        assert.is_true(#saved > 50)
        assert.equal(0, calls)
        assert.equal(5, rated)
    end)

    -- 10,000 evaluations of a sixteen-item set on the table path. The figure
    -- is written to stderr for the PR; the bound is the PR's.
    it("evaluates 10,000 sixteen-item sets in under the bound", function()
        local slots = {
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
            "Finger",
            "Trinket",
            "Trinket",
            "1H Weapon",
            "Offhand",
        }
        local set = {}
        for i, slot in ipairs(slots) do
            set[i] = vec(slot, { int = 300 + i, haste = 100 + 7 * i, crit = 80 + 5 * i, mastery = 120 + 3 * i }, {
                setID = (i <= 5) and 2057 or nil,
                sockets = (i == 2 or i == 11) and 1 or 0,
            })
        end
        local o = opts({ assumedFinish = true, forceTier = false })
        local started = os.clock()
        local last
        for _ = 1, 10000 do
            last = ns.EngineScore.SetValue(set, o)
        end
        local elapsed = os.clock() - started
        io.stderr:write(
            string.format("\nEngineScore: 10000 x 16-item SetValue in %.3f s (%.2f us each)\n", elapsed, elapsed * 100)
        )
        assert.is_number(last.value)
        assert.is_true(elapsed < 2.0, string.format("10,000 evaluations took %.3f s", elapsed))
    end)
end)

describe("ns.EngineScore.UpgradePercent", function()
    local ns, W

    before_each(function()
        ns = H.load()
        W = dofile(WEIGHTS)
    end)

    after_each(function()
        H.unload()
    end)

    local O = function()
        return { file = W, dr = "table", forceTier = true }
    end

    it("lets a ring take the weaker ring, whichever finger it is on", function()
        local strong = vec("Finger", { haste = 600 })
        local weak = vec("Finger", { haste = 100 })
        local ring = vec("Finger", { haste = 400 })
        local base = { vec("Head", { int = 200 }), weak, strong }
        local percent, detail = ns.EngineScore.UpgradePercent(base, ring, O())
        assert.same({ 2 }, detail.replaced)
        -- By hand: haste 100 + 600 + 50 -> 400 + 600 + 50; int 200 + 100.
        local before = 1000 + 300 + 20 * 750 / 44
        local after = 1000 + 300 + 20 * 1050 / 44
        near(100 * (after - before) / before, percent, "ring percent")
        local swapped = { vec("Head", { int = 200 }), strong, weak }
        local p2, d2 = ns.EngineScore.UpgradePercent(swapped, ring, O())
        assert.same({ 3 }, d2.replaced)
        near(percent, p2, "either finger")
    end)

    -- E-3a: the flags speak about the swap. 270162 and 250214 are in the
    -- shipped table with no numbers.
    it("carries the effect flag for what the swap moves, not for what both sets wear", function()
        local worn = { vec("Trinket", { int = 100 }, { itemID = 250214 }), vec("Trinket", { int = 50 }) }
        -- A Soulcoiler coming in, over the plain trinket: not modelled, named.
        local p, d = ns.EngineScore.UpgradePercent(worn, vec("Trinket", { int = 300 }, { itemID = 270162 }), O())
        assert.is_number(p)
        assert.is_true(d.effectUnmodelled)
        assert.same({ 2 }, d.replaced)
        local names = {}
        for _, item in ipairs(d.unmodelled) do
            names[#names + 1] = item.name
        end
        assert.same({ "Soulcoiler Ritual Vessel" }, names)
        assert.is_true(d.wornEffectUnmodelled)
        -- A head piece: Lightspire Core is worn on both sides, so the row stands.
        local _, d2 = ns.EngineScore.UpgradePercent(
            { vec("Head", { int = 100 }), vec("Trinket", { int = 100 }, { itemID = 250214 }) },
            vec("Head", { int = 200 }),
            O()
        )
        assert.is_nil(d2.effectUnmodelled)
        assert.is_true(d2.wornEffectUnmodelled)
        -- A plain trinket replacing Lightspire Core: what leaves is not modelled.
        local _, d3 = ns.EngineScore.UpgradePercent(
            { vec("Trinket", { int = 100 }, { itemID = 250214 }), vec("Trinket", { int = 900 }, { itemID = 270162 }) },
            vec("Trinket", { int = 300 }, { itemID = 999999 }),
            O()
        )
        assert.is_true(d3.effectUnmodelled)
        assert.is_true(d3.effectUnknown)
    end)

    it("lets a two-hander displace both hands", function()
        local base = { vec("Head", { int = 200 }), vec("1H Weapon", { int = 300 }), vec("Offhand", { int = 100 }) }
        local staff = vec("2H Weapon", { int = 500 })
        local percent, detail = ns.EngineScore.UpgradePercent(base, staff, O())
        assert.same({ 2, 3 }, detail.replaced)
        -- int 200 + 300 + 100 + 100 assumed -> 200 + 500 + 100: 700 -> 800,
        -- on 1000 base and haste 50 / 44 x 20; the tier cancels.
        local hasteValue = 20 * 50 / 44
        near(100 * ((1000 + 800 + hasteValue) - (1000 + 700 + hasteValue)) / (1000 + 700 + hasteValue), percent, "2H")
    end)

    it("is unscaled and in the Upgrade Finder's direction, read from its sign constant", function()
        local base = { vec("Finger", { haste = 100 }), vec("Finger", { haste = 100 }) }
        local better = ns.EngineScore.UpgradePercent(base, vec("Finger", { haste = 500 }), O())
        local worse = ns.EngineScore.UpgradePercent(base, vec("Finger", { haste = 0 }), O())
        assert.is_true(ns.UFImport.IsUpgrade({ upgradePercent = better }))
        assert.is_false(ns.UFImport.IsUpgrade({ upgradePercent = worse }))
        local before = 1000 + 100 + 20 * 250 / 44
        local after = 1000 + 100 + 20 * 650 / 44
        near(100 * (after - before) / before, better, "unscaled")
    end)

    it("adds a piece for an empty slot and refuses a one-hander beside a two-hander", function()
        local base = { vec("2H Weapon", { int = 500 }) }
        local percent, detail = ns.EngineScore.UpgradePercent(base, vec("Neck", { int = 50 }), O())
        assert.same({}, detail.replaced)
        assert.is_true(percent > 0)
        local none, why = ns.EngineScore.UpgradePercent(base, vec("Offhand", { int = 50 }), O())
        assert.is_nil(none)
        assert.equal("not comparable", why)
    end)
end)

-- E-0h (WKE-678): the one rule that turns a key level into a band. The owner's
-- first fitted run (2026-10-01) scored no Dungeon row - `no band 84` - because
-- the fit writes five Dungeon bands and the compare never named one.
describe("ns.EngineScore.BandFor", function()
    local ns, W, FIT

    before_each(function()
        ns = H.load()
        W = dofile(WEIGHTS)
        FIT = dofile(FITTED)
    end)

    after_each(function()
        H.unload()
    end)

    local function file(bands, raid)
        return { specs = { [105] = { Dungeon = { bands = bands }, Raid = raid and { bands = raid } or nil } } }
    end

    local function b(n)
        return { baseValue = n, weights = {} }
    end

    it("takes the band whose key is the key level as a string", function()
        local f = file({ ["6"] = b(6), ["10"] = b(10), ["10+"] = b(99) })
        local band, key = ns.EngineScore.BandFor(f, 105, "Dungeon", 10)
        assert.equal("10", key)
        assert.equal(10, band.baseValue)
        band, key = ns.EngineScore.BandFor(f, nil, "Dungeon", "6")
        assert.equal("6", key)
        assert.equal(6, band.baseValue)
    end)

    it("lets `10+` serve 12, the highest `n+` at or under the level", function()
        local f = file({ ["2+"] = b(2), ["10+"] = b(10), ["14+"] = b(14), ["4"] = b(4) })
        local band, key = ns.EngineScore.BandFor(f, 105, "Dungeon", 12)
        assert.equal("10+", key)
        assert.equal(10, band.baseValue)
        assert.equal("10+", select(2, ns.EngineScore.BandFor(f, 105, "Dungeon", 10)))
        assert.equal("2+", select(2, ns.EngineScore.BandFor(f, 105, "Dungeon", 9)))
    end)

    it("falls back to the content type's only band", function()
        local band, key = ns.EngineScore.BandFor(W, 105, "Dungeon", 6)
        assert.equal("10+", key)
        assert.equal(W.specs[105].Dungeon.bands["10+"], band)
        assert.equal("10+", select(2, ns.EngineScore.BandFor(W, 105, "Dungeon", nil)))
    end)

    it("answers nil and names the level when no band serves it", function()
        local band, why = ns.EngineScore.BandFor(FIT, 105, "Dungeon", 12)
        assert.is_nil(band)
        assert.equal("no band for +12", why)
        band, why = ns.EngineScore.BandFor(FIT, 105, "Dungeon", 3)
        assert.is_nil(band)
        assert.equal("no band for +3", why)
        band, why = ns.EngineScore.BandFor(FIT, 105, "Dungeon", nil)
        assert.is_nil(band)
        assert.equal("no band", why)
        local value, reason = ns.EngineScore.SetValue({}, { file = FIT, dr = "table", keyLevel = 7 })
        assert.is_nil(value)
        assert.equal("no band for +7", reason)
    end)

    it("scores each fitted-shape Dungeon band at its own level and says which", function()
        -- Every band is the same but for baseValue 1000 + its level, and an
        -- empty set wears no tier: the value moves by exactly the level.
        local first = assert(ns.EngineScore.SetValue({}, { file = FIT, dr = "table", keyLevel = 2 }))
        for _, level in ipairs({ 2, 4, 6, 8, 10 }) do
            local scored = assert(ns.EngineScore.SetValue({}, { file = FIT, dr = "table", keyLevel = level }))
            assert.equal(tostring(level), scored.band)
            near(level - 2, scored.value - first.value, "band " .. level)
        end
    end)

    it("keeps Raid on its only band, whatever the key level", function()
        local band, key = ns.EngineScore.BandFor(FIT, 105, "Raid", 6)
        assert.equal("raid-3", key)
        assert.equal(2000, band.baseValue)
        assert.equal("raid-3", select(2, ns.EngineScore.BandFor(FIT, 105, "Raid", nil)))
        local a = assert(ns.EngineScore.SetValue({}, { file = FIT, dr = "table", contentType = "Raid", keyLevel = 10 }))
        local c = assert(ns.EngineScore.SetValue({}, { file = FIT, dr = "table", contentType = "Raid" }))
        assert.equal(c.value, a.value)
        assert.equal("raid-3", a.band)
        -- A key matching a Raid band's name is not read: Raid has no levels.
        local two = file({}, { ["10"] = b(10), ["raid-3"] = b(3) })
        assert.is_nil((ns.EngineScore.BandFor(two, 105, "Raid", 10)))
    end)
end)

describe("ns.EngineScore client names", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("names every client function the file calls", function()
        assert.same({ "GetBuildInfo" }, ns.EngineScore.FUNCTION_NAMES)
        local source = readAll("Lootpath/Modules/EngineScore.lua")
        source = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
        source = source:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
        local named = {}
        for _, name in ipairs(ns.EngineScore.FUNCTION_NAMES) do
            named[name] = true
        end
        local unnamed = {}
        for token in source:gmatch("[%a_][%w_]*") do
            if token:match("^[A-Z]") or token:match("^C_") then
                local value = _G[token]
                if (type(value) == "function" or type(value) == "table") and not named[token] then
                    unnamed[#unnamed + 1] = token
                end
            end
        end
        assert.same({}, unnamed)
    end)
end)

describe("ns.EngineScore on screen", function()
    it("is read by no UI file", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") then
                if readAll("Lootpath/" .. f):find("EngineScore", 1, true) then
                    readers[#readers + 1] = f
                end
            end
        end
        assert.same({}, readers)
    end)

    it("reaches no UI file through the weights either", function()
        local readers = {}
        for _, f in ipairs(H.tocFiles()) do
            if f:match("^UI/") and f:match("%.lua$") then
                if readAll("Lootpath/" .. f):find("engineWeights", 1, true) then
                    readers[#readers + 1] = f
                end
            end
        end
        assert.same({}, readers)
    end)
end)
