-- spec/companion_spec.lua (C-2, WKE-534)
-- The addon half of the companion, driven the way the client drives it: the
-- verdict chunk is a REAL Lua chunk, built here from the two committed QE Live
-- exports and loaded with the same `(addonName, ns)` varargs the .toc loader
-- hands every addon file, then ADDON_LOADED is fired. Nothing here mocks
-- QEImport: a companion import goes through the same parser a paste does, so
-- these tests fail the moment those two paths drift apart.
--
-- What the companion itself writes is C-1's (WKE-533); the file shape it must
-- write is what this file pins.
local H = require("spec.helpers.addon")

-- The client runs Lua 5.1, where the source-text compiler is `loadstring`;
-- busted runs on whatever the image has. This is test code, not addon code:
-- the addon never compiles a string, and the companion file is loaded by the
-- client itself from the .toc.
local compile = loadstring or load

local RAID_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"
local DUNGEON_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cjyztichdhze.json"
local UPGRADE_FINDER_EXPORT = "spec/fixtures/qe/qe-upgradefinder-Hotornot-kqyktjywppzw.json"

-- The exportedAt of the two committed exports, read from the files themselves.
local RAID_EXPORTED_AT = "2026-09-06T21:14:24.465Z"
local DUNGEON_EXPORTED_AT = "2026-09-07T01:01:35.474Z"

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

-- The chunk the companion writes, as source text: one assignment to
-- ns.companionVerdict, every JSON document a Lua string literal, and nothing
-- else. Built and compiled here rather than hand-copied so the test carries the
-- real 16 KB and 7 KB export bodies through Lua's own string escaping.
local function verdictChunkSource(verdict)
    local parts = {}
    for _, export in ipairs(verdict.exports) do
        local settings = ""
        if export.qeSettings then
            local written = {}
            for _, key in ipairs({ "autoUpgradeVault", "autoUpgradeAll", "autoCatalyze" }) do
                if export.qeSettings[key] ~= nil then
                    written[#written + 1] = string.format("%s = %s", key, tostring(export.qeSettings[key]))
                end
            end
            settings = string.format(" qeSettings = { %s },", table.concat(written, ", "))
        end
        parts[#parts + 1] = string.format(
            "        { schema = %q, contentType = %q,%s%s%s json = %q },\n",
            export.schema,
            export.contentType or "",
            -- C-7 (WKE-543): an Upgrade Finder document says which Mythic+ key
            -- level QE Live ran it at. Written into the chunk source as a bare
            -- number, because that is what the companion writes and what the
            -- addon has to read back.
            export.keyLevel and string.format(" keyLevel = %d,", export.keyLevel) or "",
            -- C-6 (WKE-540): a Top Gear document says which named scenario it
            -- answers, and carries the three checkboxes that produced it.
            export.scenario and string.format(" scenario = %q,", export.scenario) or "",
            settings,
            export.json
        )
    end
    return string.format(
        [[
local _, ns = ...
ns.companionVerdict = {
    writtenAt = %q,
    companionVersion = %q,
    exports = {
%s    },
}
]],
        verdict.writtenAt,
        verdict.companionVersion or "0.0.0-test",
        table.concat(parts)
    )
end

-- Loads the addon with a companion chunk in place: every .toc file first (the
-- committed placeholder among them, setting nothing), then the chunk, then
-- ADDON_LOADED - which is exactly the client's order, because the .toc lists
-- Data\QEVerdict.lua and the DB is built on the event.
local function loadWithChunk(source, opts)
    opts = opts or {}
    local ns, world = H.load({ loaded = false, beforeLoad = opts.beforeLoad })
    if opts.beforeChunk then
        opts.beforeChunk(ns, world)
    end
    if source then
        local chunk = assert(compile(source, "@Lootpath/Data/QEVerdict.lua"))
        chunk(H.ADDON, ns)
    end
    if opts.setVerdict then
        ns.companionVerdict = opts.setVerdict
    end
    world.fireEvent("ADDON_LOADED", H.ADDON)
    return ns, world
end

local function twoRealExports(writtenAt)
    return {
        writtenAt = writtenAt or "2026-09-07T02:00:00Z",
        companionVersion = "0.1.0",
        exports = {
            { schema = "qe-live-droptimizer", contentType = "Dungeon", json = readFile(DUNGEON_EXPORT) },
            { schema = "qe-live-droptimizer", contentType = "Raid", json = readFile(RAID_EXPORT) },
        },
    }
end

describe("the committed Data/QEVerdict.lua placeholder", function()
    after_each(function()
        H.unload()
    end)

    it("is listed in the .toc, after Core.lua and before the modules", function()
        local files = H.tocFiles()
        local core, data, firstModule
        for index, file in ipairs(files) do
            if file == "Core.lua" then
                core = index
            elseif file == "Data/QEVerdict.lua" then
                data = index
            elseif file:match("^Modules/") and not firstModule then
                firstModule = index
            end
        end
        assert.is_number(core)
        assert.is_number(data)
        assert.is_number(firstModule)
        assert.is_true(core < data)
        assert.is_true(data < firstModule)
    end)

    it("loads and sets nothing, so a fresh install imports nothing and says nothing", function()
        local ns, world = H.load()
        assert.is_nil(ns.companionVerdict)
        assert.is_nil(ns.QEImport.Current())
        assert.is_falsy(world.output():find("companion", 1, true))
    end)

    it("is not gitignored: the .toc names it, so a release without it would not load", function()
        for line in io.lines(".gitignore") do
            local rule = line:gsub("%s+$", "")
            if rule ~= "" and rule:sub(1, 1) ~= "#" then
                assert.is_nil(rule:find("QEVerdict", 1, true), ".gitignore names QEVerdict: " .. rule)
                assert.is_nil(rule:find("Lootpath/Data", 1, true), ".gitignore names Lootpath/Data: " .. rule)
            end
        end
    end)
end)

describe("Companion.Startup over a well-formed chunk", function()
    local ns, world

    before_each(function()
        ns, world = loadWithChunk(verdictChunkSource(twoRealExports()))
    end)

    after_each(function()
        H.unload()
    end)

    it("stores both real exports under their own content types, as a paste would", function()
        local dungeon = ns.QEImport.ForContentType("Dungeon")
        local raid = ns.QEImport.ForContentType("Raid")
        assert.is_table(dungeon)
        assert.is_table(raid)
        assert.equal(DUNGEON_EXPORTED_AT, dungeon.exportedAt)
        assert.equal(RAID_EXPORTED_AT, raid.exportedAt)
        assert.equal(15, #dungeon.topSet.order)
        assert.equal(12, #dungeon.alternatives)
        assert.same({ "Dungeon", "Raid" }, ns.QEImport.StoredContentTypes())
    end)

    it("marks each verdict as the companion's and keeps the file's writtenAt", function()
        local dungeon = ns.QEImport.ForContentType("Dungeon")
        assert.equal("companion", dungeon.source)
        assert.equal("companion", ns.Companion.SourceOf(dungeon))
        assert.equal("2026-09-07T02:00:00Z", dungeon.companionWrittenAt)
        assert.equal("0.1.0", dungeon.companionVersion)
    end)

    it("says in chat which kind it imported, for what, and how old the file is", function()
        local output = world.output()
        -- The kind leads the line, in the same words the window's status line
        -- uses (ns.UI.KIND_LABEL), because two documents that both say
        -- "QE Live" answer different questions (M3-6).
        assert.is_truthy(output:find("companion import: Top Gear, Restoration Druid, Dungeon, 15 items", 1, true))
        assert.is_truthy(output:find("companion import: Top Gear, Restoration Druid, Raid, 15 items", 1, true))
        assert.is_truthy(output:find("written ", 1, true))
    end)

    it("shows the source on the window's verdict line", function()
        ns.UI.Options.Set("Dungeon")
        ns.UI.Frame()
        local note = ns.UI.VerdictNoteText()
        assert.is_truthy(note:find("Showing the Dungeon export (companion, written ", 1, true))
    end)

    it("says 'pasted' for a verdict that arrived through the editbox", function()
        ns.UI.Frame()
        ns.UI.Import(readFile(RAID_EXPORT))
        ns.UI.Options.Set("Raid")
        assert.equal("pasted", ns.Companion.SourceText(ns.QEImport.ForContentType("Raid")))
        assert.is_truthy(ns.UI.VerdictNoteText():find("Showing the Raid export (pasted).", 1, true))
    end)
end)

describe("Companion refusals", function()
    local ns, world

    -- A verdict already stored, so every refusal below can be checked to have
    -- left it alone. It is stored as a paste at a time LATER than any companion
    -- file the refusal tests carry, which is not what is being tested here -
    -- the point is that a refusal never reaches the store at all.
    local function withStoredPaste()
        ns, world = H.load()
        ns.UI.Import(readFile(RAID_EXPORT))
        return assert(ns.QEImport.ForContentType("Raid"))
    end

    after_each(function()
        H.unload()
    end)

    local function refusalFor(raw)
        ns, world = H.load()
        ns.UI.Import(readFile(RAID_EXPORT))
        local before = ns.QEImport.ForContentType("Raid")
        local result = ns.Companion.ImportAll(raw)
        return result, before
    end

    it("says nothing at all when no companion file has been written", function()
        ns, world = H.load()
        local result = ns.Companion.ImportAll(nil)
        assert.is_false(result.ok)
        assert.is_true(result.absent)
        assert.is_falsy(world.output():find("refused", 1, true))
    end)

    it("refuses a chunk with no exports list and leaves the stored verdict alone", function()
        local stored = withStoredPaste()
        local result = ns.Companion.ImportAll({ writtenAt = "2026-09-07T02:00:00Z", companionVersion = "0.1.0" })
        assert.is_false(result.ok)
        assert.is_truthy(result.reason:find("no exports list", 1, true))
        assert.equal(stored, ns.QEImport.ForContentType("Raid"))
    end)

    it("refuses an empty exports list", function()
        ns = H.load()
        local result = ns.Companion.ImportAll({ writtenAt = "2026-09-07T02:00:00Z", exports = {} })
        assert.is_false(result.ok)
        assert.is_truthy(result.reason:find("exports list is empty", 1, true))
    end)

    it("refuses a chunk that set something that is not a table", function()
        ns = H.load()
        local result = ns.Companion.ImportAll("qe-live-droptimizer")
        assert.is_false(result.ok)
        assert.is_truthy(result.reason:find("not a table", 1, true))
    end)

    it("refuses a writtenAt that is missing or is not an ISO 8601 UTC stamp", function()
        ns = H.load()
        local missing = ns.Companion.ImportAll({ exports = { { schema = "x", json = "{}" } } })
        assert.is_false(missing.ok)
        assert.is_truthy(missing.reason:find("no writtenAt string", 1, true))

        local garbage = ns.Companion.ImportAll({ writtenAt = "last Tuesday", exports = { { json = "{}" } } })
        assert.is_false(garbage.ok)
        assert.is_truthy(garbage.reason:find("not an ISO 8601 UTC stamp", 1, true))
    end)

    it("refuses an export whose json is not a string, and imports the others", function()
        local result, before = refusalFor({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = {
                { schema = "qe-live-droptimizer", contentType = "Raid", json = { 1, 2, 3 } },
                { schema = "qe-live-droptimizer", contentType = "Dungeon", json = readFile(DUNGEON_EXPORT) },
            },
        })
        assert.is_true(result.ok)
        assert.equal(1, #result.skipped)
        assert.equal(1, result.skipped[1].index)
        assert.is_truthy(result.skipped[1].reason:find("no json string (it is a table)", 1, true))
        assert.equal(before, ns.QEImport.ForContentType("Raid"))
        assert.is_table(ns.QEImport.ForContentType("Dungeon"))
    end)

    it("passes an export QE Live's own parser refuses straight through, verbatim", function()
        local body = readFile(RAID_EXPORT):gsub('"version":%s*1', '"version": 2', 1)
        local result, before = refusalFor({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = { { schema = "qe-live-droptimizer", contentType = "Raid", json = body } },
        })
        assert.is_true(result.ok)
        assert.equal(0, #result.imported)
        assert.equal(1, #result.skipped)
        assert.equal(ns.QEImport.Parse(body).reason, result.skipped[1].reason)
        assert.is_truthy(result.skipped[1].reason:find("version 2", 1, true))
        assert.equal(before, ns.QEImport.ForContentType("Raid"))
    end)

    -- Until M3-6 this document was refused by name, because handing it to the
    -- Top Gear parser would have called it a bad Top Gear export. It now goes
    -- to the parser that owns it, and to that parser's own store.
    it("hands an Upgrade Finder document to ns.UFImport, not to the Top Gear parser", function()
        ns = H.load()
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = {
                { schema = "qe-live-upgradefinder", contentType = "Raid", json = readFile(UPGRADE_FINDER_EXPORT) },
            },
        })
        assert.is_true(result.ok)
        assert.equal(0, #result.skipped)
        assert.equal(1, #result.imported)
        assert.equal("qe-live-upgradefinder", result.imported[1].schema)
        assert.equal("Raid", result.imported[1].contentType)
        assert.equal(315, result.imported[1].items)
        assert.equal("ranked drops", result.imported[1].noun)
        -- Each store holds its own kind and nothing of the other's.
        assert.is_nil(ns.QEImport.Current())
        assert.equal("qe-live-upgradefinder", ns.UFImport.ForContentType("Raid").schema)
        assert.equal("companion", ns.UFImport.Current().source)
        assert.equal("2026-09-08T02:00:00Z", ns.UFImport.Current().companionWrittenAt)
    end)

    it("carries both kinds for one content type out of one file, neither displacing the other", function()
        ns = H.load()
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = {
                { schema = "qe-live-droptimizer", contentType = "Raid", json = readFile(RAID_EXPORT) },
                { schema = "qe-live-upgradefinder", contentType = "Raid", json = readFile(UPGRADE_FINDER_EXPORT) },
            },
        })
        assert.is_true(result.ok)
        assert.equal(2, #result.imported)
        assert.equal(0, #result.skipped)
        assert.equal("qe-live-droptimizer", ns.QEImport.ForContentType("Raid").schema)
        assert.equal("qe-live-upgradefinder", ns.UFImport.ForContentType("Raid").schema)
        -- The staleness check compares like with like: a Top Gear import is
        -- never made stale by an Upgrade Finder one for the same content type.
        assert.equal(15, result.imported[1].items)
        assert.equal(315, result.imported[2].items)
    end)

    it("still refuses an Upgrade Finder document the Upgrade Finder parser refuses", function()
        ns = H.load()
        local body = readFile(UPGRADE_FINDER_EXPORT):gsub('"version": 1', '"version": 2', 1)
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = { { schema = "qe-live-upgradefinder", contentType = "Raid", json = body } },
        })
        assert.is_true(result.ok)
        assert.equal(0, #result.imported)
        assert.equal(1, #result.skipped)
        -- Word for word what the paste box would have shown.
        assert.equal(ns.UFImport.Parse(body).reason, result.skipped[1].reason)
        assert.is_nil(ns.UFImport.Current())
    end)

    it("refuses an entry with an unknown schema, naming what it read", function()
        ns = H.load()
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = { { schema = "raidbots-droptimizer", json = "{}" } },
        })
        assert.equal(1, #result.skipped)
        assert.is_truthy(result.skipped[1].reason:find('declares schema "raidbots-droptimizer"', 1, true))
        -- Both readable schemas are named, because "Lootpath reads Top Gear"
        -- became a half-truth the moment there were two (M3-6).
        assert.is_truthy(result.skipped[1].reason:find("qe-live-droptimizer", 1, true))
        assert.is_truthy(result.skipped[1].reason:find("qe-live-upgradefinder", 1, true))
    end)

    it("refuses an entry that is not a table", function()
        ns = H.load()
        local result = ns.Companion.ImportAll({ writtenAt = "2026-09-08T02:00:00Z", exports = { "not a table" } })
        assert.equal(1, #result.skipped)
        assert.is_truthy(result.skipped[1].reason:find("not a table", 1, true))
    end)

    it("refuses a secret value the way every other client read is refused", function()
        local world2
        ns, world2 = H.load()
        assert.is_false(ns.Companion.ImportAll(world2.secretTable("verdict")).ok)
        -- A secret STRING, not the table sentinel: a field that is already the
        -- right type is what ns.Safe is there for, and a bare type check would
        -- let it through.
        local result = ns.Companion.ImportAll({
            writtenAt = world2.markSecret("2026-09-08T02:00:00Z"),
            exports = { { schema = "qe-live-droptimizer", json = "{}" } },
        })
        assert.is_false(result.ok)
        assert.is_truthy(result.reason:find("no writtenAt string", 1, true))

        -- A different stamp string: Lua interns literals, so the one marked
        -- secret above is the same value here and would be refused again.
        local entry = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T03:00:00Z",
            exports = { { schema = world2.markSecret("qe-live-droptimizer"), json = "{}" } },
        })
        assert.is_true(entry.ok)
        assert.equal(1, #entry.skipped)
        assert.is_truthy(entry.skipped[1].reason:find("no schema string", 1, true))
    end)

    it("reports every refusal in chat with the file's age, and says the paste box still works", function()
        local _, world3 = loadWithChunk(nil, {
            setVerdict = { writtenAt = "2026-09-08T02:00:00Z", companionVersion = "0.1.0" },
        })
        local output = world3.output()
        assert.is_truthy(output:find("companion file refused:", 1, true))
        assert.is_truthy(output:find("The paste box still works.", 1, true))
    end)
end)

describe("Companion freshness", function()
    local ns

    after_each(function()
        H.unload()
    end)

    it("does not overwrite a paste made after the companion wrote its file", function()
        ns = H.load()
        -- The paste happens now; the companion file was written an hour ago.
        ns.UI.Import(readFile(RAID_EXPORT))
        local pasted = ns.QEImport.ForContentType("Raid")
        local anHourAgo = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 3600)
        local result = ns.Companion.ImportAll({
            writtenAt = anHourAgo,
            exports = { { schema = "qe-live-droptimizer", contentType = "Raid", json = readFile(RAID_EXPORT) } },
        })
        assert.is_true(result.ok)
        assert.equal(0, #result.imported)
        assert.equal(1, #result.skipped)
        assert.is_true(result.skipped[1].stale)
        assert.is_truthy(result.skipped[1].reason:find("keeping the stored one", 1, true))
        assert.equal(pasted, ns.QEImport.ForContentType("Raid"))
        assert.equal("pasted", ns.Companion.SourceText(ns.QEImport.ForContentType("Raid")))
    end)

    it("does overwrite a paste the companion file is newer than", function()
        ns = H.load()
        ns.UI.Import(readFile(RAID_EXPORT))
        local inAnHour = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + 3600)
        local result = ns.Companion.ImportAll({
            writtenAt = inAnHour,
            exports = { { schema = "qe-live-droptimizer", contentType = "Raid", json = readFile(RAID_EXPORT) } },
        })
        assert.equal(1, #result.imported)
        assert.equal("companion", ns.Companion.SourceOf(ns.QEImport.ForContentType("Raid")))
    end)

    it("reads the same file again on the next reload without re-importing or saying anything", function()
        local raw = twoRealExports()
        ns = H.load()
        local first = ns.Companion.ImportAll(raw)
        assert.equal(2, #first.imported)
        local stored = ns.QEImport.ForContentType("Dungeon")

        local second = ns.Companion.ImportAll(raw)
        assert.equal(0, #second.imported)
        assert.equal(0, #second.skipped)
        assert.same({ "Dungeon", "Raid" }, second.unchanged)
        assert.equal(stored, ns.QEImport.ForContentType("Dungeon"))
    end)

    it("takes a newer companion file over an older companion import", function()
        ns = H.load()
        ns.Companion.ImportAll(twoRealExports("2026-09-07T02:00:00Z"))
        local result = ns.Companion.ImportAll(twoRealExports("2026-09-08T02:00:00Z"))
        assert.equal(2, #result.imported)
        assert.equal("2026-09-08T02:00:00Z", ns.QEImport.ForContentType("Raid").companionWrittenAt)
    end)

    it("keeps a newer companion import when an older companion file is read", function()
        ns = H.load()
        ns.Companion.ImportAll(twoRealExports("2026-09-08T02:00:00Z"))
        local result = ns.Companion.ImportAll(twoRealExports("2026-09-07T02:00:00Z"))
        assert.equal(0, #result.imported)
        assert.equal(2, #result.skipped)
        assert.equal("2026-09-08T02:00:00Z", ns.QEImport.ForContentType("Raid").companionWrittenAt)
    end)
end)

-- C-3 (WKE-536). Before it, `/lootpath refresh` called ReloadUI and nothing
-- else, so the companion's profile was built from whatever the owner had last
-- CAPTURED rather than from what they were wearing. These tests are about the
-- three snapshots and their order; what the companion then does with them is
-- `tools/companion`'s own suite.
describe("/lootpath refresh", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- Records the capture names Refresh asks for, in order, while still
    -- running the real captures: the module reaches for `ns.RunCapture` at
    -- call time, which is the only reason this wrapper is reachable.
    local function recordCaptures()
        local calls = {}
        local original = ns.RunCapture
        ns.RunCapture = function(name, ...)
            calls[#calls + 1] = name
            return original(name, ...)
        end
        return calls
    end

    it("captures env, inventory, vault and currencies in that order, then reloads once", function()
        assert.same({ "env", "inventory", "vault", "currencies" }, ns.Companion.REFRESH_CAPTURES)
        local calls = recordCaptures()
        assert.equal(0, world.reloads)
        local result = ns.HandleSlash("refresh")
        assert.is_nil(result)
        assert.same({ "env", "inventory", "vault", "currencies" }, calls)
        assert.equal(1, #ns.db.global.captures.env)
        assert.equal(1, #ns.db.global.captures.inventory)
        assert.equal(1, #ns.db.global.captures.vault)
        assert.equal(1, #ns.db.global.captures.currencies)
        assert.equal(1, world.reloads)
    end)

    it("hands back every snapshot it stored", function()
        local result = ns.Companion.Refresh()
        assert.is_true(result.ok)
        assert.is_true(result.reloaded)
        for _, name in ipairs(ns.Companion.REFRESH_CAPTURES) do
            assert.equal(ns.db.global.captures[name][1], result.captured[name])
            assert.equal(name, result.captured[name].name)
        end
    end)

    it("says what it captured, and what is left to do", function()
        ns.HandleSlash("refresh")
        local output = world.output()
        assert.is_truthy(output:find("captured gear, bags, bank (closed), vault, currencies", 1, true))
        assert.is_truthy(output:find("reloading so the companion can read them", 1, true))
        assert.is_truthy(output:find("reload again when it says done", 1, true))
    end)

    -- The bank half comes out of the snapshot that was just taken, not from a
    -- second question to the client: C_Bank.CanViewBank answers true only
    -- while the bank frame is open (transcript 2026-09-05).
    it("names the bank open when the bank frame is", function()
        world.bankOpen = true
        ns.Companion.Refresh()
        assert.is_truthy(world.output():find("bank (open)", 1, true))
        assert.is_true(ns.db.global.captures.inventory[1].data.bank.predicates.CanViewBank.Character[1])
    end)

    it("names the bank closed when it is not, so a half-scanned run is visible", function()
        world.bankOpen = false
        ns.Companion.Refresh()
        assert.is_truthy(world.output():find("bank (closed)", 1, true))
        assert.is_false(ns.db.global.captures.inventory[1].data.bank.predicates.CanViewBank.Character[1])
    end)

    it("refuses in combat, because ReloadUI is protected there and the captures refuse too", function()
        world.inCombat = true
        local result = ns.Companion.Refresh()
        assert.is_false(result.ok)
        assert.equal("combat", result.reason)
        assert.equal(0, world.reloads)
        assert.is_nil(ns.db.global.captures.env)
        assert.is_nil(ns.db.global.captures.inventory)
        assert.is_nil(ns.db.global.captures.vault)
        assert.is_truthy(world.output():find("does nothing in combat", 1, true))
    end)

    -- An asynchronous capture that never calls back leaves ns.runningCapture
    -- set, which is exactly what `capture journal` looks like mid-walk. A
    -- stalled capture is registered here rather than seeding the whole
    -- Encounter Journal, because what is under test is RunCapture's refusal
    -- reaching the chat frame and stopping the reload, not the walk.
    it("does not reload when another capture is running, and repeats the refusal", function()
        ns.RegisterCapture("stalled", "test-only: never calls back", function() end, { async = true })
        assert.is_true(ns.RunCapture("stalled").pending)
        local result = ns.Companion.Refresh()
        assert.is_false(result.ok)
        assert.equal("env", result.capture)
        assert.equal("capture 'stalled' is still running", result.reason)
        assert.equal(0, world.reloads)
        assert.is_nil(ns.db.global.captures.env)
        local output = world.output()
        assert.is_truthy(output:find("/lootpath refresh stopped: capture 'env' refused:", 1, true))
        assert.is_truthy(output:find("capture 'stalled' is still running", 1, true))
    end)

    -- The client always has ReloadUI; a client that did not would otherwise
    -- get three snapshots it can never flush.
    it("captures nothing when the client cannot reload", function()
        _G.ReloadUI = nil
        local result = ns.Companion.Refresh()
        assert.is_false(result.ok)
        assert.equal("this client has no ReloadUI", result.reason)
        assert.is_nil(ns.db.global.captures.env)
    end)

    -- `journal` is asynchronous, the SimC profile reads none of it, and a
    -- reload mid-walk would abandon it.
    it("never walks the journal and never touches the loot map's cache", function()
        ns.db.global.journalCache.sentinel = { built = true }
        local calls = recordCaptures()
        ns.Companion.Refresh()
        for _, name in ipairs(calls) do
            assert.not_equal("journal", name)
        end
        assert.is_nil(ns.db.global.captures.journal)
        assert.same({ built = true }, ns.db.global.journalCache.sentinel)
    end)

    it("is listed in /lootpath help", function()
        ns.HandleSlash("help")
        assert.is_truthy(world.output():find("/lootpath refresh", 1, true))
    end)

    it("names the source of the stored import in /lootpath status", function()
        ns.Companion.ImportAll(twoRealExports())
        ns.HandleSlash("status")
        assert.is_truthy(world.output():find("(companion, written ", 1, true))
    end)
end)

-- ---------------------------------------------------------------------------
-- WKE-538 finding 3: the verdict has to be readable next to the assumption that
-- produced it. C-5 (WKE-539) made the companion set QE Live's two upgrade
-- checkboxes itself and record the pair in the file it writes; until now the
-- addon read `qeSettings` nowhere, so a vault option QE Live valued at 321
-- where the client reads 305 arrived with no way to say why. The pair is
-- carried onto each verdict, because the Vault panel reads it off whichever
-- verdict is on screen - which may have come back from SavedVariables long
-- after the file that wrote it was replaced.

describe("Companion qeSettings", function()
    local ns

    after_each(function()
        H.unload()
    end)

    local function fileWith(qeSettings)
        return {
            writtenAt = "2026-09-08T02:00:00Z",
            companionVersion = "0.1.0",
            qeSettings = qeSettings,
            exports = {
                { schema = "qe-live-droptimizer", contentType = "Raid", json = readFile(RAID_EXPORT) },
                { schema = "qe-live-upgradefinder", contentType = "Raid", json = readFile(UPGRADE_FINDER_EXPORT) },
            },
        }
    end

    it("carries the pair the companion recorded onto every verdict it stores", function()
        ns = H.load()
        local result = ns.Companion.ImportAll(fileWith({ autoUpgradeVault = false, autoUpgradeAll = false }))
        assert.is_true(result.ok)
        assert.equal(2, #result.imported)
        assert.same({ autoUpgradeVault = false, autoUpgradeAll = false }, result.qeSettings)
        -- Both kinds of document: the pair is a fact about the run, not about
        -- one of its two reports.
        assert.same({ autoUpgradeVault = false, autoUpgradeAll = false }, ns.QEImport.ForContentType("Raid").qeSettings)
        assert.same({ autoUpgradeVault = false, autoUpgradeAll = false }, ns.UFImport.ForContentType("Raid").qeSettings)
    end)

    it("keeps true as true and false as false", function()
        ns = H.load()
        ns.Companion.ImportAll(fileWith({ autoUpgradeVault = true, autoUpgradeAll = false }))
        local stored = ns.QEImport.ForContentType("Raid").qeSettings
        assert.is_true(stored.autoUpgradeVault)
        assert.is_false(stored.autoUpgradeAll)
    end)

    it("reads the pair out of a real companion chunk", function()
        local source = string.format(
            [[
local _, ns = ...
ns.companionVerdict = {
    writtenAt = "2026-09-08T02:00:00Z",
    companionVersion = "0.1.0",
    qeSettings = { autoUpgradeVault = false, autoUpgradeAll = true },
    exports = {
        { schema = "qe-live-droptimizer", contentType = "Raid", json = %q },
    },
}
]],
            readFile(RAID_EXPORT)
        )
        ns = loadWithChunk(source)
        local stored = ns.QEImport.ForContentType("Raid").qeSettings
        assert.is_false(stored.autoUpgradeVault)
        assert.is_true(stored.autoUpgradeAll)
    end)

    -- A file written before C-5, and the committed placeholder, carry no
    -- settings at all. That is silence, not a refusal: the import still happens
    -- and the panel simply reports the level difference without a reason.
    it("imports a file that does not say, and stores no settings for it", function()
        ns = H.load()
        local result = ns.Companion.ImportAll(fileWith(nil))
        assert.is_true(result.ok)
        assert.equal(2, #result.imported)
        assert.equal(0, #result.skipped)
        assert.is_nil(result.qeSettings)
        assert.is_nil(ns.QEImport.ForContentType("Raid").qeSettings)
    end)

    it("stores nothing for a pair that is not two booleans", function()
        -- Half a pair is not a pair, and a number is not a boolean: the addon
        -- says nothing about a setting the file did not state properly.
        for _, bad in ipairs({
            { autoUpgradeVault = true },
            { autoUpgradeVault = "true", autoUpgradeAll = false },
            { autoUpgradeVault = 1, autoUpgradeAll = 0 },
        }) do
            H.unload()
            ns = H.load()
            local result = ns.Companion.ImportAll(fileWith(bad))
            assert.is_true(result.ok)
            assert.is_nil(result.qeSettings)
            assert.is_nil(ns.QEImport.ForContentType("Raid").qeSettings)
        end
    end)

    it("drops a secret settings table rather than storing it", function()
        local world
        ns, world = H.load()
        local result = ns.Companion.ImportAll(fileWith(world.markSecret({
            autoUpgradeVault = true,
            autoUpgradeAll = true,
        })))
        assert.is_true(result.ok)
        assert.is_nil(result.qeSettings)
        assert.is_nil(ns.QEImport.ForContentType("Raid").qeSettings)
    end)
end)

-- ---------------------------------------------------------------------------
-- C-7 (WKE-543): one file, several Upgrade Finder documents, one per Mythic+
-- key level.
--
-- The failure this guards is quiet and total: before C-7, ImportAll asked
-- "is there already an import for this content type from this file?" and the
-- answer for the second, third, fourth and fifth dungeon document was YES,
-- because the first had just stored one. Four of five key levels would have
-- been reported as unchanged and thrown away.
describe("Companion.ImportAll with several key levels", function()
    local ns

    after_each(function()
        H.unload()
    end)

    local function fiveLevels(writtenAt)
        local exports = {}
        for _, level in ipairs({ 2, 4, 6, 8, 10 }) do
            exports[#exports + 1] = {
                schema = "qe-live-upgradefinder",
                contentType = "Raid",
                keyLevel = level,
                json = readFile(UPGRADE_FINDER_EXPORT),
            }
        end
        return { writtenAt = writtenAt or "2026-09-08T02:00:00Z", companionVersion = "0.2.0", exports = exports }
    end

    it("files every key level out of one file, and calls none of them a repeat", function()
        ns = H.load()
        local result = ns.Companion.ImportAll(fiveLevels())
        assert.is_true(result.ok)
        assert.equal(5, #result.imported)
        assert.equal(0, #result.skipped)
        assert.equal(0, #result.unchanged)
        assert.same({ 2, 4, 6, 8, 10 }, (ns.UFImport.StoredKeyLevels("Raid")))
        for _, level in ipairs({ 2, 4, 6, 8, 10 }) do
            local verdict = ns.UFImport.ForContentTypeAndLevel("Raid", level)
            assert.equal(level, verdict.keyLevel)
            assert.equal("companion", verdict.source)
        end
        -- The chat line names the level, so five lines are five answers rather
        -- than the same sentence five times.
        assert.equal(10, result.imported[5].keyLevel)
    end)

    it("reads the levels back out of a real chunk, as numbers", function()
        ns = loadWithChunk(verdictChunkSource(fiveLevels()))
        assert.equal(2, ns.companionVerdict.exports[1].keyLevel)
        assert.equal("number", type(ns.companionVerdict.exports[1].keyLevel))
        assert.same({ 2, 4, 6, 8, 10 }, (ns.UFImport.StoredKeyLevels("Raid")))
    end)

    it("reads the same file twice as unchanged, level for level", function()
        ns = H.load()
        assert.equal(5, #ns.Companion.ImportAll(fiveLevels()).imported)
        local again = ns.Companion.ImportAll(fiveLevels())
        assert.equal(0, #again.imported)
        assert.equal(5, #again.unchanged)
        assert.equal(0, #again.skipped)
    end)

    it("files a document with no key level apart, never under one it inferred", function()
        ns = H.load()
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = {
                { schema = "qe-live-upgradefinder", contentType = "Raid", json = readFile(UPGRADE_FINDER_EXPORT) },
            },
        })
        assert.is_true(result.ok)
        assert.equal(1, #result.imported)
        assert.is_nil(result.imported[1].keyLevel)
        local levels, unrecorded = ns.UFImport.StoredKeyLevels("Raid")
        assert.same({}, levels)
        assert.is_true(unrecorded)
        -- Its own settings.dungeon is 7, and 7 is an INDEX into QE Live's key
        -- table, not a key level. Reading it as one would file a +10 answer
        -- under "+7"; the addon would rather say it does not know.
        assert.equal(7, ns.UFImport.ForContentType("Raid").settings.dungeon)
        assert.is_nil(ns.UFImport.ForContentType("Raid").keyLevel)
    end)

    it("ignores a key level that is not a whole number, rather than filing under it", function()
        ns = H.load()
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = {
                {
                    schema = "qe-live-upgradefinder",
                    contentType = "Raid",
                    keyLevel = 7.5,
                    json = readFile(UPGRADE_FINDER_EXPORT),
                },
            },
        })
        assert.is_true(result.ok)
        assert.equal(1, #result.imported, "a bad key level loses the level, never the export")
        assert.is_nil(result.imported[1].keyLevel)
        local levels, unrecorded = ns.UFImport.StoredKeyLevels("Raid")
        assert.same({}, levels)
        assert.is_true(unrecorded)
    end)

    -- Every value read out of the companion file passes ns.Safe first, the
    -- standing client rule. A secret number answers no type honestly, so a key
    -- level marked secret is silence and the export is still imported.
    it("passes a secret key level through ns.Safe before it is believed", function()
        local world
        ns, world = H.load()
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-08T02:00:00Z",
            exports = {
                {
                    schema = "qe-live-upgradefinder",
                    contentType = "Raid",
                    keyLevel = world.markSecret(10),
                    json = readFile(UPGRADE_FINDER_EXPORT),
                },
            },
        })
        assert.is_true(result.ok)
        assert.equal(1, #result.imported)
        assert.is_nil(result.imported[1].keyLevel)
        assert.is_true((select(2, ns.UFImport.StoredKeyLevels("Raid"))))
    end)
end)

-- ---------------------------------------------------------------------------
-- C-6 (WKE-540): one file, three answers about the same gear.
--
-- The three documents are real, and they are the point: same profile, same
-- content type, three different questions put to QE Live through his three
-- import checkboxes. Filed by content type alone they would look like three
-- repeats of the first and two would be thrown away - the exact failure C-7 hit
-- with key levels.

local SCENARIO_FILES = {
    asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
    catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
    maxed = "spec/fixtures/qe/qe-droptimizer-Hotornot-qqrqsbudcszh.json",
}

describe("a companion file carrying the three named scenarios", function()
    local ns

    after_each(function()
        H.unload()
    end)

    local function boxesFor(scenario)
        return {
            autoUpgradeVault = scenario == "maxed",
            autoUpgradeAll = scenario == "maxed",
            autoCatalyze = scenario ~= "asOffered",
        }
    end

    local function threeScenarios(writtenAt)
        local exports = {}
        for _, scenario in ipairs({ "asOffered", "catalyzed", "maxed" }) do
            exports[#exports + 1] = {
                schema = "qe-live-droptimizer",
                contentType = "Dungeon",
                scenario = scenario,
                qeSettings = boxesFor(scenario),
                json = readFile(SCENARIO_FILES[scenario]),
            }
        end
        return { writtenAt = writtenAt or "2026-09-09T01:15:53Z", companionVersion = "0.1.0", exports = exports }
    end

    -- The startup import is what the client really runs, so the result is read
    -- from it rather than from a second ImportAll (which would be the same file
    -- read again, and correctly report three unchanged documents).
    it("imports all three and files each under its own scenario", function()
        local world
        ns, world = loadWithChunk(verdictChunkSource(threeScenarios()))
        local result = ns.Companion.Startup()
        assert.is_true(result.ok, result.reason)
        assert.is_truthy(world.output():find("catalyzed", 1, true))
        assert.equal(3, #result.unchanged, "the same file, read again, is three unchanged documents")
        assert.same({}, result.skipped)
        local shelves = ns.QEImport.Scenarios("Dungeon")
        assert.equal(3, #shelves)
        assert.equal(5544.654, shelves[1].verdict.topSet.score)
        assert.equal(5724.919, shelves[2].verdict.topSet.score)
        assert.equal(5853.843, shelves[3].verdict.topSet.score)
    end)

    -- Deliverable 2: Equip Now and the Upgrade Map read `asOffered` and never
    -- anything else, whatever else the file carried.
    it("leaves the verdict Equip Now reads as the asOffered one", function()
        ns = loadWithChunk(verdictChunkSource(threeScenarios()))
        assert.equal(5544.654, ns.QEImport.Current().topSet.score)
        assert.equal(5544.654, ns.QEImport.ForContentType("Dungeon").topSet.score)
        assert.equal(5544.654, (ns.UI.ActiveVerdict()).topSet.score)
    end)

    it("carries each document's own three checkboxes onto its verdict", function()
        ns = loadWithChunk(verdictChunkSource(threeScenarios()))
        local shelves = ns.QEImport.Scenarios("Dungeon")
        assert.is_false(shelves[1].verdict.qeSettings.autoCatalyze)
        assert.is_true(shelves[2].verdict.qeSettings.autoCatalyze)
        assert.is_false(shelves[2].verdict.qeSettings.autoUpgradeAll)
        assert.is_true(shelves[3].verdict.qeSettings.autoUpgradeAll)
        assert.is_true(shelves[3].verdict.qeSettings.autoUpgradeVault)
    end)

    -- Everything written before C-6 - the committed placeholder, C-1's own
    -- files, every paste - names no scenario, and every one of them IS the
    -- character as it stands.
    it("reads a document that names no scenario as asOffered", function()
        ns = loadWithChunk(verdictChunkSource({
            writtenAt = "2026-09-09T01:00:00Z",
            companionVersion = "0.1.0",
            exports = {
                { schema = "qe-live-droptimizer", contentType = "Dungeon", json = readFile(SCENARIO_FILES.asOffered) },
            },
        }))
        local shelves = ns.QEImport.Scenarios("Dungeon")
        assert.equal(1, #shelves)
        assert.equal("asOffered", shelves[1].scenario)
        assert.equal(5544.654, ns.QEImport.Current().topSet.score)
    end)

    -- The file-level pair is C-2's contract and stays exactly two booleans. A
    -- document that carries none falls back to it, which is every file written
    -- before C-6.
    it("falls back to the file's settings for a document that does not carry its own", function()
        local source = verdictChunkSource({
            writtenAt = "2026-09-09T01:00:00Z",
            companionVersion = "0.1.0",
            exports = {
                { schema = "qe-live-droptimizer", contentType = "Dungeon", json = readFile(SCENARIO_FILES.asOffered) },
            },
        })
        -- The file-level pair, written where C-5 puts it. `gsub` returns two
        -- values, so the replacement is parenthesised before it goes anywhere.
        source = (
            source:gsub(
                "ns%.companionVerdict = {",
                "%0\n    qeSettings = { autoUpgradeVault = true, autoUpgradeAll = false },",
                1
            )
        )
        ns = loadWithChunk(source)
        local stored = ns.QEImport.ForContentType("Dungeon")
        assert.is_true(stored.qeSettings.autoUpgradeVault)
        assert.is_false(stored.qeSettings.autoUpgradeAll)
        assert.is_nil(stored.qeSettings.autoCatalyze, "a file that says nothing about the Catalyst claims nothing")
    end)

    it("says nothing new when the same file is read again on the next reload", function()
        ns = loadWithChunk(verdictChunkSource(threeScenarios()))
        local again = ns.Companion.ImportAll(ns.companionVerdict)
        assert.is_true(again.ok)
        assert.same({}, again.imported)
        assert.equal(3, #again.unchanged)
    end)

    -- ns.Safe first, the standing client rule: a secret scenario name answers no
    -- type honestly, so it is silence and the document is still imported - as
    -- asOffered, which is what a document that does not say means.
    it("passes a secret scenario through ns.Safe before it is believed", function()
        local world
        ns, world = H.load()
        local result = ns.Companion.ImportAll({
            writtenAt = "2026-09-09T01:00:00Z",
            exports = {
                {
                    schema = "qe-live-droptimizer",
                    contentType = "Dungeon",
                    scenario = world.markSecret("catalyzed"),
                    json = readFile(SCENARIO_FILES.catalyzed),
                },
            },
        })
        assert.is_true(result.ok)
        assert.equal(1, #result.imported)
        assert.is_nil(result.imported[1].scenario)
        assert.equal("asOffered", ns.QEImport.Scenarios("Dungeon")[1].scenario)
    end)
end)
