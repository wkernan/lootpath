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
        parts[#parts + 1] = string.format(
            "        { schema = %q, contentType = %q, json = %q },\n",
            export.schema,
            export.contentType or "",
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

describe("/lootpath refresh", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("says what will happen, then reloads", function()
        assert.equal(0, world.reloads)
        local result = ns.HandleSlash("refresh")
        assert.equal(1, world.reloads)
        assert.is_nil(result)
        local output = world.output()
        assert.is_truthy(output:find("reloading so the companion can read your gear", 1, true))
        assert.is_truthy(output:find("reload again when it says done", 1, true))
    end)

    it("refuses in combat, because ReloadUI is protected there", function()
        world.inCombat = true
        local result = ns.Companion.Refresh()
        assert.is_false(result.ok)
        assert.equal("combat", result.reason)
        assert.equal(0, world.reloads)
        assert.is_truthy(world.output():find("does nothing in combat", 1, true))
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
