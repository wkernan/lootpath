local H = require("spec.helpers.addon")

describe("Core", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- C-6 (WKE-540). A vault reward record carries the key and not the bonus
    -- IDs, and recognising QE Live's own catalyzed copy of an option means
    -- comparing the bonus IDs he copied onto it. The inverse lives beside the
    -- one definition of the format so nothing else has to know about colons.
    describe("BonusIDsFromKey", function()
        it("is the inverse of ItemKey, sorted the way ItemKey sorted them", function()
            assert.same({ 1, 2, 3 }, ns.BonusIDsFromKey(ns.ItemKey(12345, { 3, 1, 2 })))
            assert.same(
                { 6652, 12699, 12842, 13440, 13662 },
                ns.BonusIDsFromKey(ns.ItemKey(251146, { 13440, 6652, 13662, 12699, 12842 }))
            )
        end)

        it("answers an empty list for a key with no bonus IDs, and for nothing at all", function()
            assert.same({}, ns.BonusIDsFromKey(ns.ItemKey(12345)))
            assert.same({}, ns.BonusIDsFromKey(nil))
            assert.same({}, ns.BonusIDsFromKey(12345))
        end)

        it("answers an empty list rather than a partial one for a key it cannot read", function()
            assert.same({}, ns.BonusIDsFromKey("12345:1:x:3"))
        end)
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
            assert.same({}, ns.db.char.qeImports)
            -- QE Live's own content types are "Raid" and "Dungeon"
            -- (src/globalTypes.d.ts line 130, read 2026-09-06). The default
            -- read "Mythic+" until M2-2 - a string no export can carry, so the
            -- setting could never have matched one.
            assert.equal("Dungeon", ns.db.profile.settings.contentType)
            local known = false
            for _, value in ipairs(ns.QEImport.CONTENT_TYPES) do
                known = known or value == ns.db.profile.settings.contentType
            end
            assert.is_true(known)
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

        -- R-7a (WKE-582). Nothing trimmed this list, so the owner's
        -- SavedVariables reached 11.0 MB in two days and the client read and
        -- wrote all of it at every login and every reload.
        describe("the history bound", function()
            it("keeps at most ns.CAPTURE_HISTORY snapshots per name", function()
                assert.equal(4, ns.CAPTURE_HISTORY)
                for _ = 1, ns.CAPTURE_HISTORY + 3 do
                    ns.RunCapture("probe")
                end
                assert.equal(ns.CAPTURE_HISTORY, #ns.db.global.captures.probe)
            end)

            it("drops the oldest, and the newest is always the one just stored", function()
                for index = 1, ns.CAPTURE_HISTORY + 2 do
                    ns.RegisterCapture("stamped", "", function()
                        return { index = index }
                    end)
                    local result = ns.RunCapture("stamped")
                    local list = ns.db.global.captures.stamped
                    assert.equal(result.snapshot, list[#list])
                    assert.equal(index, list[#list].data.index)
                end
                local list = ns.db.global.captures.stamped
                assert.equal(ns.CAPTURE_HISTORY, #list)
                -- The survivors are the newest, oldest first.
                local kept = {}
                for _, snapshot in ipairs(list) do
                    kept[#kept + 1] = snapshot.data.index
                end
                assert.same({ 3, 4, 5, 6 }, kept)
            end)

            it("trims the list AceDB already holds rather than replacing it", function()
                for _ = 1, ns.CAPTURE_HISTORY + 1 do
                    ns.RunCapture("probe")
                end
                local list = ns.db.global.captures.probe
                ns.RunCapture("probe")
                assert.equal(list, ns.db.global.captures.probe)
                assert.equal(ns.CAPTURE_HISTORY, #list)
            end)

            it("counts what is kept, not what was ever stored", function()
                local result
                for _ = 1, ns.CAPTURE_HISTORY + 2 do
                    result = ns.RunCapture("probe")
                end
                assert.equal(ns.CAPTURE_HISTORY, result.count)
            end)
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

        it("passes the rest of the command through as arguments", function()
            local seen
            ns.RegisterCapture("witharg", "", function(args)
                seen = args
                return {}
            end)
            ns.HandleSlash("capture witharg 14")
            assert.equal("14", seen)
        end)
    end)

    -- Async captures exist because the Encounter Journal loads loot only after
    -- EJ_LOOT_DATA_RECIEVED (M3-1, WKE-522), so `capture journal` cannot be one
    -- synchronous call the way env, inventory and vault are.
    describe("RunCapture, async", function()
        local finishLater

        before_each(function()
            ns.RegisterCapture("slow", "async test capture", function(finish, args)
                finishLater = function(data)
                    finish(data or { answer = 42, args = args })
                end
            end, { async = true })
            ns.RegisterCapture("quick", "sync test capture", function()
                return { answer = 7 }
            end)
        end)

        it("reports itself pending and stores nothing until it finishes", function()
            local final
            local immediate = ns.RunCapture("slow", function(result)
                final = result
            end, "seven")
            assert.same({ ok = true, pending = true, name = "slow" }, immediate)
            assert.is_nil(final)
            assert.is_nil(ns.db.global.captures.slow)

            finishLater()
            assert.is_true(final.ok)
            assert.equal(42, final.snapshot.data.answer)
            assert.equal("seven", final.snapshot.data.args)
            assert.equal(final.snapshot, ns.db.global.captures.slow[1])
            assert.is_number(final.snapshot.durationMs)
        end)

        it("refuses a second capture while one is still running", function()
            ns.RunCapture("slow")
            local blocked = ns.RunCapture("quick")
            assert.is_false(blocked.ok)
            assert.truthy(blocked.reason:find("'slow' is still running", 1, true))
            assert.is_nil(ns.db.global.captures.quick)

            finishLater()
            assert.is_true(ns.RunCapture("quick").ok)
        end)

        it("stores only the first finish, never a second", function()
            local calls = 0
            ns.RunCapture("slow", function()
                calls = calls + 1
            end)
            finishLater()
            finishLater()
            assert.equal(1, calls)
            assert.equal(1, #ns.db.global.captures.slow)
        end)

        it("gives up on one that never calls back, and lets the next one run", function()
            local final
            ns.RunCapture("slow", function(result)
                final = result
            end)
            world.runTimers(ns.CAPTURE_TIMEOUT_SECONDS)
            assert.is_false(final.ok)
            assert.truthy(final.reason:find("gave up after 180 seconds", 1, true))
            assert.is_nil(ns.db.global.captures.slow)
            assert.is_true(ns.RunCapture("quick").ok)
        end)

        it("reports one that errors on the way in and stores nothing", function()
            ns.RegisterCapture("brokenasync", "", function()
                error("journal exploded")
            end, { async = true })
            local final = ns.RunCapture("brokenasync", function(result)
                return result
            end)
            local reported
            ns.RunCapture("brokenasync", function(result)
                reported = result
            end)
            assert.is_false(final.ok)
            assert.truthy(final.reason:find("journal exploded", 1, true))
            assert.is_false(reported.ok)
            assert.is_nil(ns.db.global.captures.brokenasync)
        end)

        it("refuses in combat before it starts anything", function()
            world.inCombat = true
            local final = ns.RunCapture("slow", function(result)
                return result
            end)
            assert.same({ ok = false, reason = "combat" }, final)
            assert.is_nil(ns.runningCapture)
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

        it("prints the bag mark's diagnosis, with no bag hovered and nothing built", function()
            -- R-2a (WKE-571). The bare command answers: an owner whose mark is
            -- missing types six letters and reads which of the three places it
            -- failed in, without a plan, a bag addon or an item link.
            ns.HandleSlash("glow")
            local out = world.output()
            assert.truthy(out:find("adapter: ", 1, true), out)
            assert.truthy(out:find("map: ", 1, true), out)
            assert.truthy(out:find(ns.UI.Bags.NO_LINK, 1, true), out)
        end)

        it("samples a piece of gear from the bags, not the first thing in slot 1", function()
            -- V-2 (WKE-573). On the owner's first run (2026-09-14 night) the
            -- bare command took bag 0 slot 1 and reported on item 6948, the
            -- Hearthstone: `item: key 6948 - NOT in the map - glow no`, which
            -- is true of every Hearthstone and diagnoses nothing. The bags here
            -- are shaped the same way his are: a Hearthstone in slot 1 and gear
            -- behind it.
            local hearth = "|Hitem:6948::::::::80:105::::::|h[Hearthstone]|h"
            local helm = "|Hitem:222222::::::::80:105::::::|h[Miststalker's Hood]|h"
            world.items[hearth] = { instant = { 6948, "Miscellaneous", "Other", "", 134414, 15, 0 } }
            world.items[helm] = { instant = { 222222, "Armor", "Leather", "INVTYPE_HEAD", 134415, 4, 2 } }
            world.bags[0] = {
                numSlots = 2,
                items = { [1] = { link = hearth }, [2] = { link = helm } },
            }

            ns.HandleSlash("glow")
            local out = world.output()
            assert.truthy(out:find("sampled Miststalker's Hood from your bags", 1, true), out)
            assert.truthy(out:find("item: key 222222", 1, true), out)
            assert.is_nil(out:find("6948", 1, true), out)
        end)

        it("says so when there is no gear in the bags to sample", function()
            local hearth = "|Hitem:6948::::::::80:105::::::|h[Hearthstone]|h"
            world.items[hearth] = { instant = { 6948, "Miscellaneous", "Other", "", 134414, 15, 0 } }
            world.bags[0] = { numSlots = 1, items = { [1] = { link = hearth } } }

            ns.HandleSlash("glow")
            local out = world.output()
            assert.truthy(out:find(ns.GLOW_NO_GEAR, 1, true), out)
            -- and it still tells him how to ask about one himself
            assert.truthy(out:find(ns.UI.Bags.NO_LINK, 1, true), out)
        end)

        it("asks about the item a link was shift-clicked into the command", function()
            ns.HandleSlash("glow |Hitem:99999::::::::80:105::::::|h[Nothing]|h")
            local out = world.output()
            assert.truthy(out:find("item: key 99999", 1, true), out)
            assert.truthy(out:find("item: NOT in the map", 1, true), out)
            assert.truthy(out:find("item: glow no", 1, true), out)
        end)

        it("opens the window on the Upgrade Map, which is where the tooltip sends the reader", function()
            local shown
            ns.UI.ShowUpgradeMap = function()
                shown = true
            end
            ns.HandleSlash("map")
            assert.is_true(shown)
        end)

        it("prints status", function()
            ns.HandleSlash("capture env")
            ns.HandleSlash("status")
            local out = world.output()
            assert.truthy(out:find("env=1", 1, true))
            assert.truthy(out:find("import: none", 1, true))
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

-- ---------------------------------------------------------------------------
-- WKE-530 (M3-5) finding 5: the window's title bar read
-- "Lootpath @project-version@" on the copy tools\sync.ps1 put in the client on
-- 2026-09-06. The .toc carries `## Version: @project-version@` and the BigWigs
-- packager substitutes it only when it builds a release, so a dev copy has the
-- token itself in its metadata.

describe("ns.VERSION", function()
    after_each(function()
        H.unload()
    end)

    it("falls back to dev when the packager has not substituted the .toc token", function()
        local ns = H.load({
            beforeLoad = function(world)
                world.metadata.Version = "@project-version@"
            end,
        })
        assert.equal("dev", ns.VERSION)
    end)

    it("uses the packaged version when there is one", function()
        local ns = H.load()
        assert.equal("0.0.0-test", ns.VERSION)
    end)

    it("falls back for any unsubstituted token, and for no metadata at all", function()
        local ns = H.load({
            beforeLoad = function(world)
                world.metadata.Version = "@project-revision@"
            end,
        })
        assert.equal("dev", ns.VERSION)
        H.unload()
        ns = H.load({
            beforeLoad = function(world)
                world.metadata.Version = nil
            end,
        })
        assert.equal("dev", ns.VERSION)
        H.unload()
        ns = H.load({
            beforeLoad = function(world)
                world.metadata.Version = ""
            end,
        })
        assert.equal("dev", ns.VERSION)
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-16a (WKE-581). Core.lua owns only the lifecycle half of the login ask:
-- which event asks it, when it stops listening, and what a question that
-- errored must not do. What is asked and why is `Companion.AskVaultAtLogin`,
-- which spec/companion_spec.lua covers.

describe("the login ask's lifecycle", function()
    local ns, world

    local function lootpathFrame()
        -- The one frame Core.lua registers ADDON_LOADED on: the stub keeps
        -- every frame ever created, so it is found by what it listens to
        -- rather than by an index that other modules could shift.
        for _, f in ipairs(world.frames) do
            if f.events["PLAYER_LOGOUT"] then
                return f
            end
        end
        return nil
    end

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- Proven red by removing the `frame:RegisterEvent("PLAYER_ENTERING_WORLD")`
    -- line: the frame never listens and the login never asks.
    it("listens for PLAYER_ENTERING_WORLD and stops after the first one", function()
        local frame = lootpathFrame()
        assert.is_truthy(frame)
        assert.is_true(frame.events["PLAYER_ENTERING_WORLD"])
        world.fireEvent("PLAYER_ENTERING_WORLD")
        assert.is_nil(frame.events["PLAYER_ENTERING_WORLD"])
        -- Nothing was deferred, so it is not waiting on the end of a fight
        -- either: the session's question is settled.
        assert.is_nil(frame.events["PLAYER_REGEN_ENABLED"])
    end)

    -- A login in combat is the one reason to keep listening, and the end of
    -- the fight is what ends that. Proven red by registering
    -- PLAYER_REGEN_ENABLED unconditionally: the listener outlives the answer.
    it("waits for the end of the fight only when the login was in combat", function()
        local frame = lootpathFrame()
        world.inCombat = true
        world.fireEvent("PLAYER_ENTERING_WORLD")
        assert.is_true(frame.events["PLAYER_REGEN_ENABLED"])
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        assert.is_nil(frame.events["PLAYER_REGEN_ENABLED"])
    end)

    -- The login is the one moment where an error in the addon is the first
    -- thing the player sees, so the question is pcalled the way the logout's
    -- capture is - and a question that threw is not asked again on every
    -- fight end. Proven red by calling `ns.Companion.AskVaultAtLogin()`
    -- directly instead of through `pcall`: the event handler errors.
    it("survives a question that throws, and does not retry it", function()
        local frame = lootpathFrame()
        ns.Companion.AskVaultAtLogin = function()
            error("no vault here")
        end
        world.fireEvent("PLAYER_ENTERING_WORLD")
        assert.is_nil(frame.events["PLAYER_REGEN_ENABLED"])
        assert.is_nil(frame.events["PLAYER_ENTERING_WORLD"])
    end)
end)
