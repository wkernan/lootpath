local H = require("spec.helpers.addon")

describe("Core", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    describe("ItemKey", function()
        it("is order-independent over bonus IDs", function()
            assert.equal("12345:1:2:3", ns.ItemKey(12345, { 3, 1, 2 }))
            assert.equal(ns.ItemKey(12345, { 1, 2, 3 }), ns.ItemKey(12345, { 3, 1, 2 }))
        end)

        it("differs when the bonus IDs differ", function()
            assert.not_equal(ns.ItemKey(12345, { 1, 2 }), ns.ItemKey(12345, { 1, 2, 3 }))
            assert.not_equal(ns.ItemKey(12345, { 1, 2 }), ns.ItemKey(12346, { 1, 2 }))
        end)

        it("is the bare itemID without bonus IDs", function()
            assert.equal("12345", ns.ItemKey(12345))
            assert.equal("12345", ns.ItemKey(12345, {}))
        end)

        it("accepts numeric strings", function()
            assert.equal("12345:1:3", ns.ItemKey("12345", { "3", "1" }))
        end)

        it("returns nil for anything that is not an item", function()
            assert.is_nil(ns.ItemKey(nil))
            assert.is_nil(ns.ItemKey("helm"))
            assert.is_nil(ns.ItemKey(0))
            assert.is_nil(ns.ItemKey(-5))
            assert.is_nil(ns.ItemKey(1.5))
            assert.is_nil(ns.ItemKey(12345, { 1, "x" }))
        end)
    end)

    describe("Safe", function()
        it("passes ordinary values through", function()
            assert.same({ 42, false }, { ns.Safe(42) })
            assert.same({ "text", false }, { ns.Safe("text") })
            local t = { a = 1 }
            local got, secret = ns.Safe(t)
            assert.equal(t, got)
            assert.is_false(secret)
        end)

        it("replaces a secret value with the marker", function()
            assert.same({ ns.MARKERS.secret, true }, { ns.Safe(world.secret("hp")) })
        end)

        it("replaces a secret table with the marker", function()
            assert.same({ ns.MARKERS.secretTable, true }, { ns.Safe(world.secretTable("row")) })
        end)

        it("stringifies functions", function()
            local got, secret = ns.Safe(print)
            assert.is_string(got)
            assert.is_false(secret)
        end)
    end)

    describe("CopyRaw", function()
        it("copies nested tables and reports secrets seen", function()
            local src = { a = 1, nested = { b = "two", hidden = world.secret("x") }, list = { 10, 20 } }
            local copy, saw = ns.CopyRaw(src)
            assert.is_true(saw)
            assert.not_equal(src, copy)
            assert.equal(1, copy.a)
            assert.equal("two", copy.nested.b)
            assert.equal(ns.MARKERS.secret, copy.nested.hidden)
            assert.same({ 10, 20 }, copy.list)
        end)

        it("marks a secret table at any depth and reports it", function()
            local copy, saw = ns.CopyRaw({ outer = { inner = world.secretTable("row") } })
            assert.is_true(saw)
            assert.equal(ns.MARKERS.secretTable, copy.outer.inner)
            local top, sawTop = ns.CopyRaw(world.secretTable("root"))
            assert.equal(ns.MARKERS.secretTable, top)
            assert.is_true(sawTop)
        end)

        it("reports no secret over clean data", function()
            local _, saw = ns.CopyRaw({ a = { b = { c = 1 } } })
            assert.is_false(saw)
        end)

        it("marks cycles instead of recursing", function()
            local src = { name = "root" }
            src.self = src
            local copy = ns.CopyRaw(src)
            assert.equal("root", copy.name)
            assert.equal(ns.MARKERS.cycle, copy.self)
        end)

        it("caps depth", function()
            local root = {}
            local node = root
            for _ = 1, 12 do
                node.child = {}
                node = node.child
            end
            local copy = ns.CopyRaw(root)
            local walk = copy
            local depth = 1
            while type(walk) == "table" do
                walk = walk.child
                depth = depth + 1
            end
            assert.equal(ns.MARKERS.maxDepth, walk)
            assert.equal(11, depth)
        end)

        it("replaces UI objects with a marker", function()
            local frame = CreateFrame("Frame")
            local copy = ns.CopyRaw({ frame = frame })
            assert.equal(ns.MARKERS.uiObject, copy.frame)
        end)

        it("keeps numeric keys numeric", function()
            local copy = ns.CopyRaw({ [1] = "a", [7] = "b", x = "c" })
            assert.equal("a", copy[1])
            assert.equal("b", copy[7])
            assert.is_nil(copy["7"])
            assert.equal("c", copy.x)
        end)

        it("passes a non-table through Safe", function()
            assert.same({ 5, false }, { ns.CopyRaw(5) })
        end)
    end)

    describe("Probe", function()
        it("returns results positionally with n, holes included", function()
            local got = ns.Probe(function()
                return 1, nil, 3
            end)
            assert.equal(3, got.n)
            assert.equal(1, got[1])
            assert.is_nil(got[2])
            assert.equal(3, got[3])
        end)

        it("passes arguments through", function()
            local got = ns.Probe(function(a, b)
                return a + b
            end, 2, 3)
            assert.equal(5, got[1])
        end)

        it("records an error instead of raising", function()
            local got = ns.Probe(function()
                error("boom")
            end)
            assert.is_string(got.error)
            assert.truthy(got.error:find("boom", 1, true))
        end)

        it("records an absent function", function()
            assert.same({ absent = true }, ns.Probe(nil))
        end)
    end)

    describe("database", function()
        it("initialises AceDB with the defaults on ADDON_LOADED", function()
            assert.is_table(ns.db)
            assert.equal("LootpathDB", ns.db.sv)
            assert.same({}, ns.db.global.captures)
            assert.same({}, ns.db.global.journalCache)
            assert.equal("Mythic+", ns.db.profile.settings.contentType)
            assert.is_true(ns.ready)
        end)

        it("runs onReady hooks after the database exists", function()
            H.unload()
            ns, world = H.load({ loaded = false })
            local seen
            ns.onReady[#ns.onReady + 1] = function(given)
                seen = given.db
            end
            assert.is_nil(ns.db)
            world.fireEvent("ADDON_LOADED", "SomeOtherAddon")
            assert.is_nil(ns.db)
            world.fireEvent("ADDON_LOADED", "Lootpath")
            assert.equal(ns.db, seen)
        end)
    end)

    describe("RunCapture", function()
        before_each(function()
            ns.RegisterCapture("probe", "test capture", function()
                return { answer = 42, nested = { list = { 1, 2 } } }
            end)
        end)

        it("stores a snapshot with metadata", function()
            local result = ns.RunCapture("probe")
            assert.is_true(result.ok)
            assert.equal(1, result.count)
            local stored = ns.db.global.captures.probe[1]
            assert.equal(result.snapshot, stored)
            assert.equal("probe", stored.name)
            assert.equal(42, stored.data.answer)
            assert.same({ 1, 2 }, stored.data.nested.list)
            assert.equal(120100, stored.build[4])
            assert.is_number(stored.capturedAt)
            assert.is_string(stored.capturedAtLocal)
            assert.is_false(stored.sawSecret)
            assert.equal("0.0.0-test", stored.addonVersion)
        end)

        it("appends on repeat runs", function()
            ns.RunCapture("probe")
            local result = ns.RunCapture("probe")
            assert.equal(2, result.count)
            assert.equal(2, #ns.db.global.captures.probe)
        end)

        it("refuses in combat and stores nothing", function()
            world.inCombat = true
            local result = ns.RunCapture("probe")
            assert.same({ ok = false, reason = "combat" }, result)
            assert.is_nil(ns.db.global.captures.probe)
        end)

        it("refuses an unknown capture and names the known ones", function()
            local result = ns.RunCapture("nope")
            assert.is_false(result.ok)
            assert.truthy(result.reason:find("unknown capture 'nope'", 1, true))
            assert.truthy(result.reason:find("env", 1, true))
        end)

        it("reports a capture that errors and stores nothing", function()
            ns.RegisterCapture("broken", "", function()
                error("kaput")
            end)
            local result = ns.RunCapture("broken")
            assert.is_false(result.ok)
            assert.truthy(result.reason:find("kaput", 1, true))
            assert.is_nil(ns.db.global.captures.broken)
        end)

        it("masks secrets and flags the snapshot", function()
            ns.RegisterCapture("leaky", "", function()
                return { hp = world.secret("hp") }
            end)
            local result = ns.RunCapture("leaky")
            assert.is_true(result.ok)
            assert.is_true(result.snapshot.sawSecret)
            assert.equal(ns.MARKERS.secret, result.snapshot.data.hp)
        end)

        it("refuses before the database exists", function()
            H.unload()
            ns, world = H.load({ loaded = false })
            ns.RegisterCapture("probe", "", function()
                return {}
            end)
            local result = ns.RunCapture("probe")
            assert.is_false(result.ok)
            assert.truthy(result.reason:find("database", 1, true))
        end)

        it("re-registering a name keeps its place in the order", function()
            local before = #ns.captureOrder
            ns.RegisterCapture("probe", "again", function()
                return {}
            end)
            assert.equal(before, #ns.captureOrder)
            assert.equal("again", ns.captures.probe.help)
        end)
    end)

    describe("slash command", function()
        it("is wired to /lootpath", function()
            assert.equal("/lootpath", _G.SLASH_LOOTPATH1)
            assert.is_function(_G.SlashCmdList.LOOTPATH)
        end)

        it("opens the UI with no arguments", function()
            local toggled = false
            ns.UI.Toggle = function()
                toggled = true
            end
            _G.SlashCmdList.LOOTPATH("")
            assert.is_true(toggled)
            toggled = false
            ns.HandleSlash("   ")
            assert.is_true(toggled)
        end)

        it("runs a capture and reports the count", function()
            ns.HandleSlash("capture ENV")
            assert.equal(1, #ns.db.global.captures.env)
            assert.truthy(world.output():find("capture 'env' stored (#1", 1, true))
        end)

        it("reports a refusal with its reason", function()
            world.inCombat = true
            ns.HandleSlash("capture env")
            assert.truthy(world.output():find("refused: combat", 1, true))
        end)

        it("lists the captures", function()
            ns.HandleSlash("capture")
            local out = world.output()
            assert.truthy(out:find("captures: env, inventory, vault", 1, true))
        end)

        it("wipes the captures", function()
            ns.HandleSlash("capture env")
            ns.HandleSlash("capture wipe")
            assert.same({}, ns.db.global.captures)
            assert.truthy(world.output():find("captures cleared", 1, true))
        end)

        it("prints status", function()
            ns.HandleSlash("capture env")
            ns.HandleSlash("status")
            local out = world.output()
            assert.truthy(out:find("env=1", 1, true))
            assert.truthy(out:find("QE Live import: none", 1, true))
        end)

        it("prints help for anything else", function()
            ns.HandleSlash("frobnicate")
            assert.truthy(world.output():find("/lootpath help - this list", 1, true))
        end)
    end)

    describe("libraries", function()
        it("exposes json on the namespace", function()
            assert.is_table(ns.json)
            assert.same({ a = { 1, 2 } }, ns.json.decode('{"a":[1,2]}'))
        end)
    end)
end)
