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
-- C-15 (WKE-615): who the file says it rated. The stub's own character
-- (`spec/stubs/wow.lua`: UnitName "Tester", GetRealmName "TestRealm",
-- UnitClass's token "DRUID"), because the addon compares the file against
-- exactly those three calls and imports nothing when they disagree. A verdict
-- that sets `character = false` writes none at all, which is every file written
-- before C-15 and is refused the same way a file for somebody else is.
local STUB_CHARACTER = { name = "Tester", realm = "TestRealm", class = "DRUID" }

local function characterSource(character)
    if character == false then
        return ""
    end
    local who = character or STUB_CHARACTER
    return string.format("    character = { name = %q, realm = %q, class = %q },\n", who.name, who.realm, who.class)
end

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
%s    exports = {
%s    },
}
]],
        verdict.writtenAt,
        verdict.companionVersion or "0.0.0-test",
        characterSource(verdict.character),
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
        assert.is_truthy(note:find("Showing the Dungeon Top Gear export (companion, written ", 1, true))
    end)

    it("says 'pasted' for a verdict that arrived through the editbox", function()
        ns.UI.Frame()
        ns.UI.Import(readFile(RAID_EXPORT))
        ns.UI.Options.Set("Raid")
        assert.equal("pasted", ns.Companion.SourceText(ns.QEImport.ForContentType("Raid")))
        assert.is_truthy(ns.UI.VerdictNoteText():find("Showing the Raid Top Gear export (pasted).", 1, true))
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
            setVerdict = {
                writtenAt = "2026-09-08T02:00:00Z",
                companionVersion = "0.1.0",
                -- C-15: the character gate runs first and would answer its own
                -- line, so this file says it is for the character reading it and
                -- the refusal under test is the one the exports earn.
                character = { name = "Tester", realm = "TestRealm", class = "DRUID" },
            },
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
        -- R-7b (WKE-591): a dressed character, because an empty equipment read
        -- is no longer stored at all and these tests are about the chain.
        H.dress(world)
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

    -- M3-16a (WKE-581). The client refuses `ReloadUI` unless it can attribute
    -- it to the player's own hardware event, so with nothing to wait for the
    -- reload has to happen INSIDE the slash command's execution - not from a
    -- timer, not from a callback, and with no box in the way. Proven red by
    -- deferring the call (`C_Timer.After(0, ReloadUI)`): the count is 0 when
    -- the command returns and the assertion fails on the line below.
    it("calls ReloadUI synchronously from the command when nothing had to wait", function()
        ns.HandleSlash("refresh")
        assert.equal(1, world.reloads)
        assert.equal(0, #world.popupsShown)
        world.runTimers(30)
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

    -- M3-16 (WKE-557). The vault capture is asynchronous now: when the client
    -- says rewards are waiting and lists none of them it asks for them and
    -- waits for WEEKLY_REWARDS_UPDATE. A ReloadUI in the middle of that wait
    -- would throw away the snapshot the refresh exists to take, so the order is
    -- captures, then the wait, then the reload.
    describe("when the vault capture has to ask the client", function()
        local VAULT_ITEM = "|cffa335ee|Hitem:210003::::::::80:105::13:2:7:8::::::|h[Vault Chest]|h|r"

        before_each(function()
            world.vault.hasAvailable = true
            world.vault.currentPeriod = false
            world.vault.generated = true
            world.vault.activities = {
                { type = 1, index = 1, threshold = 1, progress = 2, id = 11, level = 1, rewards = {} },
            }
            world.vault.answerOnInteract = {
                activities = {
                    {
                        type = 1,
                        index = 1,
                        threshold = 1,
                        progress = 2,
                        id = 11,
                        level = 10,
                        rewards = { { type = 1, id = 210003, quantity = 1, itemDBID = "9001" } },
                    },
                },
                links = { ["9001"] = VAULT_ITEM },
                examples = { [11] = { VAULT_ITEM } },
            }
            world.vault.answerDelaySeconds = 0.4
        end)

        it("does not reload while the vault is still being asked", function()
            local result = ns.Companion.Refresh()
            assert.is_true(result.pending)
            assert.equal(0, world.reloads)
            -- The two before it are stored; `currencies` has not run yet,
            -- because the chain is one capture at a time.
            assert.equal(1, #ns.db.global.captures.env)
            assert.equal(1, #ns.db.global.captures.inventory)
            assert.is_nil(ns.db.global.captures.vault)
            assert.is_nil(ns.db.global.captures.currencies)
        end)

        -- M3-16a (WKE-581). This is the defect the owner hit: all four
        -- snapshots were taken, `ReloadUI()` was called from the vault
        -- event's continuation, and the client answered "Interface action
        -- failed because of an AddOn" and reloaded nothing. The chain must
        -- ASK here instead. Proven red by putting `ReloadUI()` back in place
        -- of `Companion.AskForReload`: `world.reloads` is 1 and the popup
        -- assertion fails, which is exactly the shape of the bug.
        it("asks for the reload instead of calling it, with all four snapshots taken", function()
            local final
            ns.Companion.Refresh(function(result)
                final = result
            end)
            world.runTimers(10)
            assert.is_true(final.ok)
            assert.is_false(final.reloaded)
            assert.equal("popup", final.reloadPending)
            assert.equal(0, world.reloads)
            assert.equal(1, #world.popupsShown)
            assert.equal(ns.Companion.RELOAD_POPUP, world.popupsShown[1].which)
            assert.equal(1, #ns.db.global.captures.vault)
            assert.equal(1, #ns.db.global.captures.currencies)
            assert.equal(1, #ns.db.global.captures.vault[1].data.interact.after.rewardLinks)
            for _, name in ipairs(ns.Companion.REFRESH_CAPTURES) do
                assert.equal(ns.db.global.captures[name][1], final.captured[name])
            end
        end)

        -- The click is the whole point: a StaticPopup button is the hardware
        -- event the client requires, which is why the dialog calls ReloadUI
        -- from OnAccept and nothing else does. Proven red by emptying the
        -- `OnAccept` body: the click reloads nothing.
        it("reloads when the player clicks Reload, and not when he clicks Not now", function()
            ns.Companion.Refresh()
            world.runTimers(10)
            local dialog = _G.StaticPopupDialogs[ns.Companion.RELOAD_POPUP]
            assert.equal("Gear captured. Reload to send it?", dialog.text)
            assert.equal("Reload", dialog.button1)
            assert.equal("Not now", dialog.button2)
            assert.equal(0, dialog.timeout)
            assert.is_nil(dialog.OnCancel)
            assert.equal(0, world.reloads)
            assert.is_true(world.clickPopup(ns.Companion.RELOAD_POPUP))
            assert.equal(1, world.reloads)
        end)

        it("asks the same way after the bound when the client never answers", function()
            world.vault.answerOnInteract = nil
            local final
            ns.Companion.Refresh(function(result)
                final = result
            end)
            assert.equal(0, #world.popupsShown)
            world.runTimers(ns.VAULT_INTERACT_TIMEOUT_SECONDS + 1)
            assert.equal(0, world.reloads)
            assert.equal(1, #world.popupsShown)
            assert.equal("popup", final.reloadPending)
            assert.is_true(ns.db.global.captures.vault[1].data.interact.timedOut)
        end)

        -- R-6's wait line counts from `refreshStartedAt`, and its click is a
        -- plain ReloadUI. Writing the stamp on this path too is what leaves a
        -- player who clicked Not now with somewhere to click. Proven red by
        -- moving `ns.Drift.RefreshStarting()` back under the synchronous
        -- branch: `Drift.Waiting` is nil and the click runs a second refresh
        -- instead of reloading.
        it("writes R-6's stamp on the popup path, so the strip's wait line carries the same click", function()
            -- A wait stands only where a companion has been seen (R-6a): this
            -- is the previous run the owner's own machine carries.
            ns.companionStatus =
                { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
            ns.Companion.Refresh()
            world.runTimers(10)
            assert.is_string(ns.db.global.drift.refreshStartedAt)
            assert.is_truthy(ns.Drift.Waiting())
            assert.equal("wait", ns.Drift.Model().kind)
            assert.equal("reloaded", ns.Drift.Click())
            assert.equal(1, world.reloads)
        end)

        -- The one client that cannot show a box still has to be told, because
        -- the captures are sitting in memory either way. Proven red by
        -- dropping the `StaticPopup_Show` type check: the refresh errors
        -- instead of saying anything.
        it("says it in chat when the client has no StaticPopup_Show", function()
            _G.StaticPopup_Show = nil
            local final
            ns.Companion.Refresh(function(result)
                final = result
            end)
            world.runTimers(10)
            assert.equal("chat", final.reloadPending)
            assert.equal(0, world.reloads)
            assert.is_truthy(world.output():find("type /reload to send them", 1, true))
        end)

        -- The strip's own clause, and the chat line under it. Proven red by
        -- deleting the `Companion.waitingForVault` check in StatusText: the
        -- strip goes back to saying what the companion did last, which is a
        -- stale answer to what is happening right now.
        it("says it is waiting for the vault while it waits, and stops saying it after", function()
            ns.Companion.Refresh()
            assert.is_true(ns.Companion.waitingForVault)
            assert.equal("waiting for the vault", ns.Companion.StatusText(nil))
            assert.equal("waiting for the vault", ns.UI.StatusStripModel().companion)
            assert.is_truthy(world.output():find("waiting for the vault: the client is holding", 1, true))
            world.runTimers(10)
            assert.is_false(ns.Companion.waitingForVault)
            assert.equal(ns.Companion.STATUS_NEVER, ns.Companion.StatusText(nil))
        end)

        it("stops saying it when the wait times out too", function()
            world.vault.answerOnInteract = nil
            ns.Companion.Refresh()
            assert.is_true(ns.Companion.waitingForVault)
            world.runTimers(ns.VAULT_INTERACT_TIMEOUT_SECONDS + 1)
            assert.is_false(ns.Companion.waitingForVault)
        end)
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
    character = { name = "Tester", realm = "TestRealm", class = "DRUID" },
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

-- M3-13 (WKE-548): the fourth document is filed like the other three, under its
-- own name, and Equip Now still reads `asOffered` and nothing else. The file's
-- `thisWeek` export is the Dungeon document of the 2026-09-09 19:22 run,
-- committed unedited.
describe("a companion file carrying the fourth named scenario", function()
    local ns

    after_each(function()
        H.unload()
    end)

    local FOURTH = "spec/fixtures/qe/qe-droptimizer-Hotornot-hdaldwpeakpb.json"

    local function fourScenarios()
        local files = {
            asOffered = SCENARIO_FILES.asOffered,
            catalyzed = SCENARIO_FILES.catalyzed,
            thisWeek = FOURTH,
            maxed = SCENARIO_FILES.maxed,
        }
        local exports = {}
        for _, scenario in ipairs({ "asOffered", "catalyzed", "thisWeek", "maxed" }) do
            exports[#exports + 1] = {
                schema = "qe-live-droptimizer",
                contentType = "Dungeon",
                scenario = scenario,
                qeSettings = {
                    autoUpgradeVault = scenario == "maxed" or scenario == "thisWeek",
                    autoUpgradeAll = scenario == "maxed",
                    autoCatalyze = scenario ~= "asOffered",
                },
                json = readFile(files[scenario]),
            }
        end
        return { writtenAt = "2026-09-09T19:23:00Z", companionVersion = "0.1.0", exports = exports }
    end

    it("files all four, in the order they are asked, with the fourth third", function()
        ns = loadWithChunk(verdictChunkSource(fourScenarios()))
        local shelves = ns.QEImport.Scenarios("Dungeon")
        assert.equal(4, #shelves)
        assert.same(
            { "asOffered", "catalyzed", "thisWeek", "maxed" },
            { shelves[1].scenario, shelves[2].scenario, shelves[3].scenario, shelves[4].scenario }
        )
        -- His own scores, read off the four committed documents.
        assert.equal(5544.654, shelves[1].verdict.topSet.score)
        assert.equal(5724.919, shelves[2].verdict.topSet.score)
        assert.equal(5812.048, shelves[3].verdict.topSet.score)
        assert.equal(5853.843, shelves[4].verdict.topSet.score)
        assert.equal(5812.048, ns.QEImport.ForContentTypeAndScenario("Dungeon", "thisWeek").topSet.score)
    end)

    -- The fourth answer is the Vault tab's default highlight and STILL not the
    -- one Equip Now or the Upgrade Map reads: those two are `asOffered` only.
    it("leaves Equip Now reading the asOffered document", function()
        ns = loadWithChunk(verdictChunkSource(fourScenarios()))
        assert.equal(5544.654, ns.QEImport.Current().topSet.score)
        assert.equal(5544.654, ns.QEImport.ForContentType("Dungeon").topSet.score)
        assert.equal("thisWeek", ns.UI.Options.GetVaultScenario())
    end)

    -- Its own three boxes ride with it, which is what the owned-item catalyze
    -- sentence is gated on.
    it("carries the fourth document's own three checkboxes", function()
        ns = loadWithChunk(verdictChunkSource(fourScenarios()))
        local fourth = ns.QEImport.ForContentTypeAndScenario("Dungeon", "thisWeek")
        assert.is_true(fourth.qeSettings.autoCatalyze)
        assert.is_true(fourth.qeSettings.autoUpgradeVault)
        assert.is_false(fourth.qeSettings.autoUpgradeAll)
    end)
end)

-- ---------------------------------------------------------------------------
-- C-8 (WKE-558): the items QE Live's Top Gear was never shown.
--
-- His Top Gear takes thirty items for a non-patron (TopGear.tsx) and the
-- character owns more, so every Top Gear answer is an answer about a subset and
-- the file says which items were left out of it. What this pins is that the
-- names survive the chunk, that a document's own list beats the file's, that an
-- Upgrade Finder verdict never claims one, and that a malformed or secret list
-- is silence rather than a guess.
describe("Companion excluded items", function()
    local ns

    after_each(function()
        H.unload()
    end)

    local BAG = { { slot = "Finger", name = "Band of Whatever", level = 678 } }
    local CLONES = {
        { slot = "Finger", name = "Band of Whatever", level = 678 },
        { slot = "Shoulder", name = "Lynx Spaulders", level = 691, catalyst = true },
    }

    local function fileWith(excluded, docExcluded)
        return {
            writtenAt = "2026-09-10T02:00:00Z",
            companionVersion = "0.1.0",
            qeSettings = { autoUpgradeVault = false, autoUpgradeAll = false },
            excluded = excluded,
            exports = {
                {
                    schema = "qe-live-droptimizer",
                    contentType = "Raid",
                    excluded = docExcluded,
                    json = readFile(RAID_EXPORT),
                },
                { schema = "qe-live-upgradefinder", contentType = "Raid", json = readFile(UPGRADE_FINDER_EXPORT) },
            },
        }
    end

    it("carries the file's list onto a Top Gear verdict and never onto an Upgrade Finder one", function()
        ns = H.load()
        local result = ns.Companion.ImportAll(fileWith(BAG))
        assert.is_true(result.ok)
        assert.equal(2, #result.imported)
        assert.equal(1, #result.excluded)
        local stored = ns.QEImport.ForContentType("Raid").excluded
        assert.equal(1, #stored)
        assert.equal("Band of Whatever", stored[1].name)
        assert.equal(678, stored[1].level)
        -- An Upgrade Finder document is about drops and chose no pool, so it
        -- must not inherit a sentence about a Top Gear run.
        assert.is_nil(ns.UFImport.ForContentType("Raid").excluded)
    end)

    it("prefers the document's own list, because each pass chooses its own pool", function()
        ns = H.load()
        ns.Companion.ImportAll(fileWith(BAG, CLONES))
        local stored = ns.QEImport.ForContentType("Raid").excluded
        assert.equal(2, #stored)
        assert.equal("Lynx Spaulders", stored[2].name)
        assert.is_true(stored[2].catalyst)
        assert.is_nil(stored[1].catalyst, "a bag item does not claim to be a clone")
    end)

    it("imports a file that says nothing, and stores nothing for it", function()
        -- Every file written before C-8, and the committed placeholder.
        ns = H.load()
        local result = ns.Companion.ImportAll(fileWith(nil))
        assert.is_true(result.ok)
        assert.equal(2, #result.imported)
        assert.equal(0, #result.skipped)
        assert.is_nil(result.excluded)
        assert.is_nil(ns.QEImport.ForContentType("Raid").excluded)
    end)

    -- C-12 (WKE-577). The companion writes one sentence about the questions it
    -- did not ask; the addon carries it and nothing more.
    it("carries the run's scenario note onto a Top Gear verdict and never onto an Upgrade Finder one", function()
        ns = H.load()
        local file = fileWith(nil)
        file.scenarioNote = "catalyzed, thisWeek and maxed skipped: nothing you hold can be catalysed"
        local result = ns.Companion.ImportAll(file)
        assert.is_true(result.ok)
        assert.equal(file.scenarioNote, result.scenarioNote)
        assert.equal(file.scenarioNote, ns.QEImport.ForContentType("Raid").scenarioNote)
        assert.is_nil(ns.UFImport.ForContentType("Raid").scenarioNote)
    end)

    it("stores no scenario note for a run that asked everything, or for one that says nonsense", function()
        ns = H.load()
        assert.is_nil(ns.Companion.ImportAll(fileWith(nil)).scenarioNote)
        assert.is_nil(ns.QEImport.ForContentType("Raid").scenarioNote)
        H.unload()

        ns = H.load()
        local file = fileWith(nil)
        file.scenarioNote = { "not a sentence" }
        local result = ns.Companion.ImportAll(file)
        assert.is_true(result.ok, "a note it cannot read is silence, never a refused file")
        assert.is_nil(result.scenarioNote)
    end)

    it("drops an entry it cannot read rather than repairing it", function()
        ns = H.load()
        ns.Companion.ImportAll(fileWith({
            { slot = "Finger", name = "Band of Whatever", level = 678 },
            { slot = "Head", level = 700 },
            "a ring",
            { slot = "Neck", name = "Chain of Something", level = 678.5 },
        }))
        local stored = ns.QEImport.ForContentType("Raid").excluded
        assert.equal(2, #stored, "the nameless entry and the string are dropped")
        assert.equal("Chain of Something", stored[2].name)
        assert.is_nil(stored[2].level, "half an item level is not an item level")
    end)

    it("stores nothing for a list that is not a list, and nothing secret", function()
        local world
        ns, world = H.load()
        assert.is_nil(ns.Companion.Excluded("Band of Whatever"))
        assert.is_nil(ns.Companion.Excluded(42))
        assert.is_nil(ns.Companion.Excluded({}))
        assert.is_nil(ns.Companion.Excluded(world.markSecret({ { name = "Band of Whatever" } })))
        -- A secret name inside an otherwise good list is dropped with its entry.
        local mixed = ns.Companion.Excluded({
            { slot = "Finger", name = world.markSecret("Band of Whatever") },
            { slot = "Head", name = "Helm of Something" },
        })
        assert.equal(1, #mixed)
        assert.equal("Helm of Something", mixed[1].name)
    end)

    it("stops at MAX_EXCLUDED so a broken writer cannot fill the panel", function()
        ns = H.load()
        local many = {}
        for index = 1, ns.Companion.MAX_EXCLUDED + 25 do
            many[index] = { slot = "Finger", name = "ring " .. index, level = 600 }
        end
        assert.equal(ns.Companion.MAX_EXCLUDED, #ns.Companion.Excluded(many))
    end)

    -- C-10 (WKE-567): a left-out item is identified, not just named. The road
    -- surfaces say "not rated - beyond the rating's item limit" about ONE item,
    -- and two rings of one name at one item level make that sentence a coin
    -- toss until the item ID and the bonus IDs travel with the name.
    it("carries the identity his card carried, and builds the one key format", function()
        ns = H.load()
        local list = ns.Companion.Excluded({
            { slot = "Finger", name = "Band of Whatever", level = 678, itemID = 228638, bonusIDs = { 10390, 42 } },
            { slot = "Shoulder", name = "Spaulders of the Vault", level = 691, itemID = 271526 },
            {
                slot = "Shoulder",
                name = "a Catalyst clone",
                level = 678,
                itemID = 271527,
                bonusIDs = { 12 },
                originalItem = 228638,
            },
        })
        assert.equal(3, #list)
        assert.equal(228638, list[1].itemID)
        assert.same({ 10390, 42 }, list[1].bonusIDs)
        -- The key is ns.ItemKey's, built here and never read from the file, so
        -- a companion that learned to spell keys differently could not
        -- introduce a second format into the addon.
        assert.equal(ns.ItemKey(228638, { 10390, 42 }), ns.Companion.ExcludedKey(list[1]))
        -- An item with no bonus IDs is the bare "<itemID>" key, which is what
        -- such an item really is - not an entry that identified nothing.
        assert.equal("271526", ns.Companion.ExcludedKey(list[2]))
        assert.equal(228638, list[3].originalItem)
    end)

    it("drops the whole identity rather than building a key for a different item", function()
        local world
        ns, world = H.load()
        -- A bonus list with one unreadable member would otherwise become a
        -- SHORTER list, which is a perfectly valid key for an item nobody owns.
        local partial = ns.Companion.Excluded({
            { name = "Band of Whatever", level = 678, itemID = 228638, bonusIDs = { 10390, "42" } },
        })
        assert.equal(1, #partial, "the item is still named")
        assert.is_nil(partial[1].itemID)
        assert.is_nil(ns.Companion.ExcludedKey(partial[1]))
        local secret = ns.Companion.Excluded({
            { name = "Band of Whatever", level = 678, itemID = 228638, bonusIDs = world.markSecret({ 10390 }) },
        })
        assert.is_nil(secret[1].itemID)
        -- And an item ID that is not a whole positive number is no item ID.
        local half = ns.Companion.Excluded({
            { name = "Band of Whatever", level = 678, itemID = 228638.5, bonusIDs = { 10390 } },
        })
        assert.is_nil(half[1].itemID)
        assert.is_nil(half[1].bonusIDs)
        assert.is_nil(ns.Companion.ExcludedKey({ name = "Band of Whatever" }))
        assert.is_nil(ns.Companion.ExcludedKey("Band of Whatever"))
    end)

    it("answers 'was this item left out' by key, and says so", function()
        ns = H.load()
        local list = ns.Companion.Excluded({
            { slot = "Finger", name = "Band of Whatever", level = 678, itemID = 228638, bonusIDs = { 10390, 42 } },
            { slot = "Finger", name = "Band of Whatever", level = 678, itemID = 228638, bonusIDs = { 10391, 42 } },
        })
        local key = ns.ItemKey(228638, { 42, 10391 })
        local entry, how = ns.Companion.IsExcluded(list, key, { name = "Band of Whatever", level = 678 })
        assert.equal(list[2], entry, "the twin with the other bonus IDs is a different item")
        assert.equal(ns.Companion.EXCLUDED_BY_KEY, how)
        -- The same name and level at a third identity was NOT left out, and the
        -- name is not a second chance to say it was.
        assert.is_nil(
            ns.Companion.IsExcluded(list, ns.ItemKey(228638, { 42, 10392 }), { name = "Band of Whatever", level = 678 })
        )
        assert.is_nil(ns.Companion.IsExcluded(list, nil, { name = "Band of Whatever", level = 678 }))
        assert.is_nil(ns.Companion.IsExcluded(nil, key))
    end)

    it("falls back to the name and the level for a file written before C-10", function()
        ns = H.load()
        local list = ns.Companion.Excluded(CLONES)
        local entry, how =
            ns.Companion.IsExcluded(list, ns.ItemKey(228638, { 42 }), { name = "Lynx Spaulders", level = 691 })
        assert.equal("Lynx Spaulders", entry.name)
        assert.equal(ns.Companion.EXCLUDED_BY_NAME, how)
        -- The level is part of it: the same name at another level is another
        -- item, and this is the best a file with no identities can do.
        assert.is_nil(ns.Companion.IsExcluded(list, nil, { name = "Lynx Spaulders", level = 678 }))
        assert.is_nil(ns.Companion.IsExcluded(list, nil, { name = "Something Else", level = 691 }))
        assert.is_nil(ns.Companion.IsExcluded(list, nil, nil))
    end)

    it("reads the list out of a real companion chunk", function()
        local source = string.format(
            [[
local _, ns = ...
ns.companionVerdict = {
    writtenAt = "2026-09-10T02:00:00Z",
    companionVersion = "0.1.0",
    character = { name = "Tester", realm = "TestRealm", class = "DRUID" },
    excluded = {
        { slot = "Finger", name = "Band of the \"Quoted\" Name", level = 678 },
    },
    exports = {
        { schema = "qe-live-droptimizer", contentType = "Raid", json = %q },
    },
}
]],
            readFile(RAID_EXPORT)
        )
        ns = loadWithChunk(source)
        local stored = ns.QEImport.ForContentType("Raid").excluded
        assert.equal(1, #stored)
        assert.equal('Band of the "Quoted" Name', stored[1].name)
    end)

    -- The wording, in one place, because the Equip Now tab and the Vault tab
    -- both print it and neither may say something the other does not.
    it("says the count first and then the names, and names no source", function()
        ns = H.load()
        local text = ns.Companion.ExcludedText(BAG)
        assert.is_nil(text:find("QE Live", 1, true))
        assert.is_nil(text:find(" his ", 1, true))
    end)

    it("says the count first and then the names", function()
        ns = H.load()
        assert.is_nil(ns.Companion.ExcludedText(nil))
        assert.is_nil(ns.Companion.ExcludedText({}))
        assert.equal(
            "1 of your items weren't rated this time: Band of Whatever (Finger, 678).",
            ns.Companion.ExcludedText(BAG)
        )
        assert.equal(
            "2 of your items weren't rated this time: Band of Whatever (Finger, 678),"
                .. " Lynx Spaulders (Shoulder, 691, Catalyst).",
            ns.Companion.ExcludedText(CLONES)
        )
    end)

    it("names three and counts the rest", function()
        ns = H.load()
        local many = {}
        for index = 1, 27 do
            many[index] = { slot = "Finger", name = "ring " .. index }
        end
        local text = ns.Companion.ExcludedText(many)
        assert.equal(
            "27 of your items weren't rated this time: ring 1 (Finger), ring 2 (Finger), ring 3 (Finger) and 24 more.",
            text
        )
        -- And the tooltip gets every one of them.
        assert.equal(27, #ns.Companion.ExcludedLines(many))
    end)
end)

-- ---------------------------------------------------------------------------
-- C-11a (WKE-586): the "weren't rated this time" line counts the items NO pass
-- of the run was shown, not the cards pass 1 could not fit.
--
-- The failure this guards is the one the owner read on 2026-09-15 ~15:50, over
-- the 14:31 verdict whose every scenario logged `0 still to ask about`: Equip
-- Now said `25 of your items weren't rated this time` and the Vault tab said
-- 29, and both numbers were pass 1's leftovers - exactly the cards passes 2
-- and 3 went on to rate.

describe("the items no pass was shown", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- `count` items with identities of their own, so the join is C-10's and not
    -- the name+level fallback.
    local function leftovers(count, first)
        local list = {}
        for index = 1, count do
            list[index] = {
                slot = "Finger",
                name = "ring " .. (first + index - 1),
                level = 280 + index,
                itemID = 900 + first + index,
                bonusIDs = { 3 },
            }
        end
        return ns.Companion.Excluded(list)
    end

    -- The 14:31 log's shape: pass 1 leaves 27, pass 2 leaves 12, pass 3 leaves
    -- nothing. Pass 1 is the plan and goes on the scenario shelf; the later two
    -- go on the pass shelf, which is where `QEImport.Passes` reads them.
    local function run(passThreeLeaves)
        local plan = { contentType = "Dungeon", scenario = "asOffered", pass = 1, excluded = leftovers(27, 1) }
        ns.QEImport.Store(plan)
        ns.QEImport.Store({ contentType = "Dungeon", scenario = "asOffered", pass = 2, excluded = leftovers(12, 100) })
        ns.QEImport.Store({
            contentType = "Dungeon",
            scenario = "asOffered",
            pass = 3,
            excluded = passThreeLeaves > 0 and leftovers(passThreeLeaves, 500) or nil,
        })
        return plan
    end

    it("reads the last pass's leftovers and not the plan's own", function()
        local plan = run(0)
        -- Proved red: the plan's own list is the 27 cards pass 1 could not fit,
        -- and reading it off the verdict is what put 25 on his screen.
        assert.equal(27, #plan.excluded)
        assert.equal(
            "27 of your items weren't rated this time: ring 1 (Finger, 281), ring 2 (Finger, 282),"
                .. " ring 3 (Finger, 283) and 24 more.",
            ns.Companion.ExcludedText(plan.excluded)
        )
        -- And the run's answer, which is the truth: pass 3 asked about the rest.
        assert.is_nil(ns.Companion.Unrated(plan))
        assert.is_nil(ns.Companion.ExcludedText(ns.Companion.Unrated(plan)))
    end)

    it("names the last pass's leftovers, and only those, when the bound really left some", function()
        local plan = run(3)
        local unrated = ns.Companion.Unrated(plan)
        assert.equal(3, #unrated)
        assert.equal(
            "3 of your items weren't rated this time: ring 500 (Finger, 281), ring 501 (Finger, 282),"
                .. " ring 502 (Finger, 283).",
            ns.Companion.ExcludedText(unrated)
        )
        -- None of pass 1's or pass 2's leftovers is among them.
        for _, entry in ipairs(unrated) do
            assert.is_nil(ns.Companion.IsExcluded(plan.excluded, ns.Companion.ExcludedKey(entry)))
        end
    end)

    it("answers with the document's own list when the run had no later pass", function()
        -- A single-pass run, every file written before C-11, and every paste.
        local plan = { contentType = "Raid", scenario = "asOffered", pass = 1, excluded = leftovers(2, 1) }
        ns.QEImport.Store(plan)
        assert.same(plan.excluded, ns.Companion.Unrated(plan))
        assert.is_nil(ns.Companion.Unrated(nil))
        assert.is_nil(ns.Companion.Unrated({ contentType = "Raid" }))
    end)

    it("takes the passes it is handed rather than looking them up", function()
        local plan = { contentType = "Dungeon", scenario = "asOffered", pass = 1, excluded = leftovers(27, 1) }
        local handed = {
            { pass = 2, verdict = { excluded = leftovers(12, 100) } },
            { pass = 3, verdict = { excluded = leftovers(1, 700) } },
        }
        local unrated = ns.Companion.Unrated(plan, handed)
        assert.equal(1, #unrated)
        assert.equal("ring 700", unrated[1].name)
        -- An empty list is a run with no later pass, not "ask the database".
        assert.same(plan.excluded, ns.Companion.Unrated(plan, {}))
    end)
end)

-- ---------------------------------------------------------------------------
-- C-9 (WKE-559): the companion's own status file.

describe("the committed Data/CompanionStatus.lua placeholder", function()
    after_each(function()
        H.unload()
    end)

    it("is listed in the .toc, right after the verdict and before the modules", function()
        local files = H.tocFiles()
        local verdict, status, firstModule
        for index, file in ipairs(files) do
            if file == "Data/QEVerdict.lua" then
                verdict = index
            elseif file == "Data/CompanionStatus.lua" then
                status = index
            elseif file:match("^Modules/") and not firstModule then
                firstModule = index
            end
        end
        assert.is_number(verdict)
        assert.is_number(status)
        assert.equal(verdict + 1, status)
        assert.is_true(status < firstModule)
    end)

    it("loads and sets nothing, so a fresh install says the companion has never been seen", function()
        local ns = H.load()
        assert.is_nil(ns.companionStatus)
        assert.equal(ns.Companion.STATUS_NEVER, ns.Companion.StatusText(ns.companionStatus))
    end)

    it("is not gitignored: the .toc names it, so a release without it would not load", function()
        for line in io.lines(".gitignore") do
            local rule = line:gsub("%s+$", "")
            if rule ~= "" and rule:sub(1, 1) ~= "#" then
                assert.is_nil(rule:find("CompanionStatus", 1, true), ".gitignore names CompanionStatus: " .. rule)
            end
        end
    end)
end)

describe("Companion.Status", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("reads every field the companion writes", function()
        local status = ns.Companion.Status({
            state = "idle",
            startedAt = "2026-09-13T22:48:01Z",
            finishedAt = "2026-09-13T22:48:44Z",
            stage = "write",
            message = "8 documents",
            profileCapturedAt = "2026-09-13T22:47:31",
            verdictWrittenAt = "2026-09-13T22:48:44Z",
            companionVersion = "0.1.0",
            exitCode = 0,
        })
        assert.is_true(status.ok)
        assert.equal("idle", status.state)
        assert.equal("2026-09-13T22:48:01Z", status.startedAt)
        assert.equal("2026-09-13T22:48:44Z", status.finishedAt)
        assert.equal("write", status.stage)
        assert.equal("8 documents", status.message)
        assert.equal("2026-09-13T22:47:31", status.profileCapturedAt)
        assert.equal("2026-09-13T22:48:44Z", status.verdictWrittenAt)
        assert.equal("0.1.0", status.companionVersion)
        assert.equal(0, status.exitCode)
    end)

    it("calls a missing file absent rather than broken: nothing has run yet", function()
        local status = ns.Companion.Status(nil)
        assert.is_true(status.absent)
        assert.is_nil(status.ok)
    end)

    it("refuses a state it cannot act on, and anything that is not a table", function()
        assert.is_false(ns.Companion.Status({ state = "exploded" }).ok)
        assert.is_false(ns.Companion.Status({}).ok)
        assert.is_false(ns.Companion.Status("running").ok)
        assert.is_false(ns.Companion.Status(42).ok)
        for state in pairs(ns.Companion.STATUS_STATES) do
            assert.is_true(ns.Companion.Status({ state = state }).ok, state .. " is a state it can be in")
        end
    end)

    it("drops a field it cannot read rather than showing whatever was there", function()
        local status = ns.Companion.Status({
            state = "failed",
            stage = 12,
            message = {},
            exitCode = "3",
            finishedAt = "",
        })
        assert.is_true(status.ok)
        assert.is_nil(status.stage)
        assert.is_nil(status.message)
        assert.is_nil(status.exitCode)
        assert.is_nil(status.finishedAt)
        -- a fractional or negative exit code is not an exit code either
        assert.is_nil(ns.Companion.Status({ state = "idle", exitCode = 1.5 }).exitCode)
        assert.is_nil(ns.Companion.Status({ state = "idle", exitCode = -1 }).exitCode)
    end)

    it("passes every value through ns.Safe before it looks at it", function()
        -- A secret value coerces to nil and answers no type honestly, so the
        -- guard runs before anything reads it - the order M3-3 settled on.
        assert.is_false(ns.Companion.Status({ state = world.markSecret("running") }).ok)
        assert.is_false(ns.Companion.Status(world.secretTable()).ok)
        -- A whole file the client hid: every field of it is readable Lua and the
        -- guard is the only thing that refuses it.
        assert.is_false(ns.Companion.Status(world.markSecret({ state = "idle", stage = "write" })).ok)
        local status = ns.Companion.Status({
            state = "idle",
            stage = world.markSecret("write"),
            exitCode = world.markSecret(0),
        })
        assert.is_true(status.ok)
        assert.is_nil(status.stage)
        assert.is_nil(status.exitCode)
    end)
end)

-- C-14b (WKE-627). The one place in the addon that decides this state, and the
-- four fields behind it.
describe("Companion.UnratedGear", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    -- A sentinel, because `copy` cannot be handed a nil to remove a field with.
    local DROP = {}

    local REFUSAL = {
        state = "failed",
        stage = "qe live",
        finishedAt = "2026-09-22T17:18:00Z",
        exitCode = 5,
        message = "couldn't rate this gear: no usable item in Cape, Chest",
        reason = "unknown-gear",
        missingSlots = { "Cape", "Chest", "Belt", "Legs", "Boots", "Weapon" },
        sent = 32,
        notTaken = 17,
    }

    local function copy(overrides)
        local out = {}
        for key, value in pairs(REFUSAL) do
            out[key] = value
        end
        -- `DROP` rather than nil, because a nil in a table constructor is not a
        -- key at all and `pairs` would never see it.
        for key, value in pairs(overrides or {}) do
            if value == DROP then
                out[key] = nil
            else
                out[key] = value
            end
        end
        return out
    end

    it("reads the four fields off the file, in the rating's own order", function()
        local status = ns.Companion.Status(REFUSAL)
        assert.equal("unknown-gear", status.reason)
        assert.same({ "Cape", "Chest", "Belt", "Legs", "Boots", "Weapon" }, status.missingSlots)
        assert.equal(32, status.sent)
        assert.equal(17, status.notTaken)
        local unrated = ns.Companion.UnratedGear(REFUSAL)
        assert.same({ "Cape", "Chest", "Belt", "Legs", "Boots", "Weapon" }, unrated.slots)
        assert.equal(32, unrated.sent)
        assert.equal(17, unrated.notTaken)
    end)

    -- **THE OLD-SHAPE GUARD.** Every status file on disk before this was built
    -- carries none of the four, and the owner has several. It must read as the
    -- ordinary failure it has always been.
    -- Proven red by making `UnratedGear` answer on `state == "failed"` alone.
    it("answers nothing for a status file written before these fields existed", function()
        local old = copy({ reason = DROP, missingSlots = DROP, sent = DROP, notTaken = DROP })
        assert.is_nil(ns.Companion.UnratedGear(old))
        assert.is_nil(ns.Companion.UnratedGearFacts(old))
        local status = ns.Companion.Status(old)
        assert.is_true(status.ok)
        assert.is_nil(status.reason)
        assert.is_nil(status.missingSlots)
        assert.is_nil(status.sent)
        assert.is_nil(status.notTaken)
    end)

    it("answers nothing for any other status, whatever its message says", function()
        assert.is_nil(ns.Companion.UnratedGear(nil))
        assert.is_nil(ns.Companion.UnratedGear("a string"))
        assert.is_nil(ns.Companion.UnratedGear({ state = "exploded", reason = "unknown-gear" }))
        -- A reason on a run that did NOT fail is not this state.
        assert.is_nil(ns.Companion.UnratedGear(copy({ state = "idle" })))
        assert.is_nil(ns.Companion.UnratedGear(copy({ state = "skipped" })))
        -- A token this addon does not know is silence, never a guess.
        assert.is_nil(ns.Companion.UnratedGear(copy({ reason = "something-else" })))
        -- And the sentence alone never stands in for the token: this is the
        -- whole reason the token exists.
        assert.is_nil(ns.Companion.UnratedGear(copy({ reason = DROP })))
    end)

    it("takes the raw file or a record Status already read, and answers the same", function()
        assert.same(ns.Companion.UnratedGear(REFUSAL), ns.Companion.UnratedGear(ns.Companion.Status(REFUSAL)))
    end)

    it("passes the slots and the counts through ns.Safe like every other field", function()
        assert.is_nil(ns.Companion.Status(copy({ missingSlots = world.secretTable() })).missingSlots)
        assert.is_nil(ns.Companion.Status(copy({ missingSlots = "Cape" })).missingSlots)
        assert.is_nil(ns.Companion.Status(copy({ sent = world.markSecret(32) })).sent)
        assert.is_nil(ns.Companion.Status(copy({ sent = 1.5 })).sent)
        assert.is_nil(ns.Companion.Status(copy({ notTaken = -1 })).notTaken)
        -- A secret word inside the list is dropped; the rest of the list stands.
        assert.same(
            { "Cape", "Belt" },
            ns.Companion.Status(copy({ missingSlots = { "Cape", world.markSecret("Chest"), "Belt" } })).missingSlots
        )
    end)

    it("gives a list even when the file named no slots, so a caller never has to check", function()
        local unrated = ns.Companion.UnratedGear(copy({ missingSlots = DROP }))
        assert.same({}, unrated.slots)
        assert.equal(17, unrated.notTaken)
    end)

    it("says the quiet facts from the fields, never from the sentence", function()
        assert.equal(
            "17 of 32 pieces weren't recognised \194\183 slots with nothing usable: "
                .. "Cape, Chest, Belt, Legs, Boots, Weapon",
            ns.Companion.UnratedGearFacts(REFUSAL)
        )
        -- Half the facts is half the sentence, not an invented number.
        assert.equal(
            "slots with nothing usable: Cape, Chest, Belt, Legs, Boots, Weapon",
            ns.Companion.UnratedGearFacts(copy({ sent = DROP, notTaken = DROP }))
        )
        assert.equal("17 of 32 pieces weren't recognised", ns.Companion.UnratedGearFacts(copy({ missingSlots = DROP })))
        -- And nothing at all rather than a tooltip that admits it knows nothing.
        assert.is_nil(ns.Companion.UnratedGearFacts(copy({ missingSlots = DROP, sent = DROP, notTaken = DROP })))
    end)
end)

describe("Companion.StatusText", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    local NOW = "2026-09-13T22:51:00Z"

    local function at(iso)
        return date("%H:%M", ns.EpochFromISO(iso))
    end

    local function text(status)
        return ns.Companion.StatusText(status, ns.EpochFromISO(NOW))
    end

    it("says how long ago the verdict on disk was written", function()
        assert.equal(
            "companion: wrote 3 minutes ago",
            text({ state = "idle", verdictWrittenAt = "2026-09-13T22:48:00Z" })
        )
        -- The VERDICT's stamp, not the run's own finish: the two are minutes
        -- apart on a real run, and the age on the strip is about the file the
        -- addon read.
        assert.equal(
            "companion: wrote 6 minutes ago",
            text({
                state = "idle",
                verdictWrittenAt = "2026-09-13T22:45:00Z",
                finishedAt = "2026-09-13T22:50:00Z",
            })
        )
    end)

    it("says a run is running, and when it started", function()
        assert.equal(
            "companion: run started " .. at("2026-09-13T22:48:00Z"),
            text({ state = "running", stage = "qe live", startedAt = "2026-09-13T22:48:00Z" })
        )
        -- a stamp it cannot read is a clause without a time, never a wrong one
        assert.equal("companion: run started", text({ state = "running", startedAt = "some time on Tuesday" }))
    end)

    it("says there was nothing to do, which is not the same as nothing happening", function()
        assert.equal(
            "companion: profile unchanged, no run (" .. at("2026-09-13T22:06:00Z") .. ")",
            text({ state = "skipped", finishedAt = "2026-09-13T22:06:00Z" })
        )
    end)

    -- R-7b (WKE-591). Two skips, opposite news. C-4's says the plan on screen
    -- is already right; this one says nothing was sent at all, so the plan is
    -- only as new as the last read that worked. They are told apart by the exit
    -- code the companion writes, never by its message: the message is prose.
    -- Proven red by dropping the `exitCode` test from `StatusText`: both say
    -- "profile unchanged, no run", which is the opposite of what happened.
    it("tells a skip with nothing to send from a skip with nothing to do", function()
        assert.equal(
            "companion: no gear to rate, no run (" .. at("2026-09-13T22:06:00Z") .. ") - see companion.log",
            text({
                state = "skipped",
                finishedAt = "2026-09-13T22:06:00Z",
                exitCode = ns.Companion.EXIT_EMPTY_GEAR,
            })
        )
        assert.equal(8, ns.Companion.EXIT_EMPTY_GEAR)
    end)

    -- C-14 (WKE-603). The THIRD skip, and the third piece of news: the gear was
    -- read and a slot in it was bare, so nothing could be rated. Told apart from
    -- the other two by its own exit code, for the same reason.
    it("tells a skip over an empty slot from the other two skips", function()
        assert.equal(
            "companion: a gear slot was empty, no run (" .. at("2026-09-13T22:06:00Z") .. ") - see companion.log",
            text({
                state = "skipped",
                finishedAt = "2026-09-13T22:06:00Z",
                exitCode = ns.Companion.EXIT_EMPTY_SLOT,
            })
        )
        assert.equal(9, ns.Companion.EXIT_EMPTY_SLOT)
        assert.not_equal(ns.Companion.EXIT_EMPTY_GEAR, ns.Companion.EXIT_EMPTY_SLOT)
    end)

    -- C-14b (WKE-627). The one failure that is not a breakage: the gear went
    -- over whole and the rating would not take it. Named by the token the
    -- companion writes, never by reading `message`.
    -- Proven red by dropping the `UnratedGear` branch from `StatusText`: the
    -- clause goes back to "FAILED at qe live", which points at a log file
    -- instead of saying what happened to the gear.
    it("says the rating could not take this gear, and only for that reason", function()
        assert.equal(
            "companion: couldn't rate this gear (" .. at("2026-09-13T21:06:00Z") .. ") - see companion.log",
            text({
                state = "failed",
                stage = "qe live",
                finishedAt = "2026-09-13T21:06:00Z",
                exitCode = 5,
                message = "couldn't rate this gear: no usable item in Boots",
                reason = "unknown-gear",
                missingSlots = { "Boots" },
                sent = 32,
                notTaken = 17,
            })
        )
        -- The same stage, the same exit code and the same message, with no
        -- reason written: the clause every failure has always had.
        assert.equal(
            "companion: FAILED at qe live (" .. at("2026-09-13T21:06:00Z") .. ") - see companion.log",
            text({
                state = "failed",
                stage = "qe live",
                finishedAt = "2026-09-13T21:06:00Z",
                exitCode = 5,
                message = "couldn't rate this gear: no usable item in Boots",
            })
        )
    end)

    it("says where a run died, and where to read why", function()
        assert.equal(
            "companion: FAILED at profile (" .. at("2026-09-13T21:06:00Z") .. ") - see companion.log",
            text({ state = "failed", stage = "profile", finishedAt = "2026-09-13T21:06:00Z", exitCode = 3 })
        )
        -- and a failure that does not say where still says to read the log
        assert.equal(
            "companion: FAILED (" .. at("2026-09-13T21:06:00Z") .. ") - see companion.log",
            text({ state = "failed", finishedAt = "2026-09-13T21:06:00Z" })
        )
    end)

    it("says never seen for the placeholder, and says so rather than guessing at a broken file", function()
        assert.equal(ns.Companion.STATUS_NEVER, text(nil))
        assert.equal(ns.Companion.STATUS_UNREADABLE, text({ state = "exploded" }))
        assert.equal(ns.Companion.STATUS_UNREADABLE, text("a string"))
    end)

    it("falls back to the clock when an idle run names no verdict", function()
        assert.equal(
            "companion: idle (" .. at("2026-09-13T22:48:00Z") .. ")",
            text({ state = "idle", finishedAt = "2026-09-13T22:48:00Z" })
        )
        assert.equal("companion: idle", text({ state = "idle" }))
    end)

    it("puts the companion's own words in the tooltip and never on the line", function()
        local status = {
            state = "failed",
            stage = "qe live",
            message = "the fork did not answer http://localhost:3000",
            finishedAt = "2026-09-13T21:06:00Z",
        }
        assert.is_nil(text(status):find("localhost", 1, true))
        local tooltip = ns.Companion.StatusTooltip(status, ns.EpochFromISO(NOW))
        assert.equal(
            "The companion's last run: the fork did not answer http://localhost:3000 ("
                .. at("2026-09-13T21:06:00Z")
                .. ")",
            tooltip
        )
        -- a status with nothing to add adds nothing
        assert.is_nil(ns.Companion.StatusTooltip({ state = "idle" }, ns.EpochFromISO(NOW)))
    end)

    -- C-14 (WKE-603). **The tooltip is one line, whatever the file holds.**
    --
    -- The companion caps its own `message` now, but a status file written before
    -- it does not - and the owner has one on disk from 2026-09-16 16:28. The
    -- input here is that very message: the text the companion wrote at
    -- 21:27:27Z, committed under `spec/fixtures/companion/`, Playwright's whole
    -- call log with the ANSI colour codes the game's font draws as boxes.
    --
    -- Proven red by taking `Companion.OneLine` back out of `StatusTooltip`: the
    -- tooltip comes back seventeen lines long with the escapes in it, which is
    -- the blob in the owner's screenshot.
    it("gives the strip one line even when the status file carries a whole dump", function()
        local source = assert(io.open("spec/fixtures/companion/playwright-go-disabled.txt", "rb"))
        local dump = source:read("*a")
        source:close()
        -- the fixture really is the thing: many lines, with escape bytes in it
        assert.is_truthy(dump:find(string.char(10), 1, true))
        assert.is_truthy(dump:find(string.char(27), 1, true))

        local tooltip = ns.Companion.StatusTooltip({
            state = "failed",
            stage = "qe live",
            message = dump,
            finishedAt = "2026-09-13T21:06:00Z",
        }, ns.EpochFromISO(NOW))

        assert.equal(
            "The companion's last run: driving QE Live failed: locator.click: Timeout 20000ms exceeded. ("
                .. at("2026-09-13T21:06:00Z")
                .. ")",
            tooltip
        )
        assert.is_nil(tooltip:find(string.char(10), 1, true))
        assert.is_nil(tooltip:find(string.char(27), 1, true))
        assert.is_nil(tooltip:find("MuiButton", 1, true))
    end)

    -- And a message long enough to fill the screen on ONE line is cut too.
    it("caps a single line that is too long to be a tooltip", function()
        local long = string.rep("x", ns.Companion.TOOLTIP_MAX + 50)
        local capped = ns.Companion.OneLine(long)
        assert.equal(ns.Companion.TOOLTIP_MAX, #capped)
        assert.equal("...", capped:sub(-3))
        -- a sentence that fits is untouched, byte for byte
        local fits = "refusing to rate a profile with an empty slot (legs); the previous verdict is untouched"
        assert.equal(fits, ns.Companion.OneLine(fits))
    end)

    -- V-4 (WKE-589), the owner's screen at 2026-09-15 17:22 Central Daylight
    -- Time: the strip read `companion, written 62 minutes ago` for a stamp two
    -- minutes old and its tooltip put a 17:20 event at 16:22. The tests above
    -- read their expected clock through the same function the code does, so an
    -- hour's error passes through them unseen; these two say the hour out loud
    -- on a MODELLED daylight clock instead.
    describe("on a daylight-time clock", function()
        local WRITTEN = "2026-09-15T22:20:31Z"
        local AT = 1789510831 + 120 -- 22:22:31Z, two minutes later

        before_each(function()
            H.chicagoClock(world, AT)
        end)

        it("says two minutes, not sixty-two", function()
            assert.equal(
                "companion, written 2 minutes ago",
                ns.Companion.SourceText({ source = "companion", companionWrittenAt = WRITTEN }, AT)
            )
        end)

        it("puts the wall clock in the reader's own hour", function()
            assert.equal(
                "companion: profile unchanged, no run (17:20)",
                ns.Companion.StatusText({ state = "skipped", finishedAt = WRITTEN }, AT)
            )
        end)
    end)
end)

-- C-11 (WKE-572): a Top Gear run is a sequence of passes, and the file says
-- which pass each document is and what that pass was shown.
--
-- Pass 1 is the plan: it holds the equipped set, the vault options and their
-- Catalyst clones, and it is what Equip Now, the Upgrade Map and the plan
-- sentence read. A later pass is a rating for the items pass 1's thirty could
-- not hold, and it must not reach any shelf the plan is drawn from.
describe("Companion and the later Top Gear passes", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    local function fileWithPasses(writtenAt)
        return {
            writtenAt = writtenAt or "2026-09-14T02:00:00Z",
            companionVersion = "0.1.0",
            exports = {
                {
                    schema = "qe-live-droptimizer",
                    contentType = "Dungeon",
                    scenario = "asOffered",
                    pass = 1,
                    considered = { { slot = "Head", name = "Worn Helm", level = 300, itemID = 111, bonusIDs = { 5 } } },
                    excluded = {
                        {
                            slot = "Trinket",
                            name = "Seed of Radiant Hope",
                            level = 308,
                            itemID = 222,
                            bonusIDs = { 7 },
                        },
                    },
                    json = readFile(DUNGEON_EXPORT),
                },
                {
                    schema = "qe-live-droptimizer",
                    contentType = "Dungeon",
                    scenario = "asOffered",
                    pass = 2,
                    considered = {
                        {
                            slot = "Trinket",
                            name = "Seed of Radiant Hope",
                            level = 308,
                            itemID = 222,
                            bonusIDs = { 7 },
                        },
                    },
                    -- The same content type, because a later pass is the same
                    -- question over the pool the first one could not hold. The
                    -- content type is the JSON's own (QEImport.ContentTypeKey),
                    -- so a Raid document here would be a Raid answer whatever
                    -- the pass number said.
                    json = readFile(DUNGEON_EXPORT),
                },
            },
        }
    end

    it("reads the pass off each document, and a document that says nothing is the first", function()
        local entry = ns.Companion.Entry(fileWithPasses().exports[2], 2)
        assert.is_true(entry.ok, entry.reason)
        assert.equal(2, entry.pass)
        assert.equal(1, #entry.considered)
        assert.equal("Seed of Radiant Hope", entry.considered[1].name)
        -- Every file written before C-11, and every paste: nothing said, and
        -- nothing said is the first pass.
        local old = ns.Companion.Entry({ schema = "qe-live-droptimizer", json = readFile(DUNGEON_EXPORT) }, 1)
        assert.is_nil(old.pass)
        assert.is_nil(old.considered)
        -- A number that is not a pass is no evidence of one.
        local wrong =
            ns.Companion.Entry({ schema = "qe-live-droptimizer", pass = 0, json = readFile(DUNGEON_EXPORT) }, 1)
        assert.is_nil(wrong.pass)
    end)

    it("imports both passes and files the later one where the plan cannot reach it", function()
        local result = ns.Companion.ImportAll(fileWithPasses())
        assert.is_true(result.ok, result.reason)
        assert.equal(2, #result.imported)
        assert.same({ 1, 2 }, { result.imported[1].pass, result.imported[2].pass })
        assert.same({}, result.skipped)

        -- The Dungeon shelf is pass 1's document and only pass 1's. The
        -- second export here is the RAID document, so a pass-2 answer landing
        -- on the plan's shelf would be plainly visible as the wrong spec line.
        local plan = ns.QEImport.ForContentTypeAndScenario("Dungeon", "asOffered")
        assert.equal(1, ns.QEImport.PassKey(plan))
        assert.equal(1, #ns.QEImport.Scenarios("Dungeon"))
        local passes = ns.QEImport.Passes("Dungeon", "asOffered")
        assert.equal(1, #passes)
        assert.equal(2, passes[1].pass)
        -- The pool the pass saw travels onto the verdict, because the road
        -- model reads "did this pass see it" off whichever verdict is on
        -- screen, not off the file it arrived in.
        assert.equal(1, #passes[1].verdict.considered)
        assert.equal("Seed of Radiant Hope", passes[1].verdict.considered[1].name)
        assert.equal("Seed of Radiant Hope", plan.excluded[1].name)
    end)

    it("reads the same file twice as nothing new, pass by pass", function()
        local raw = fileWithPasses()
        assert.equal(2, #ns.Companion.ImportAll(raw).imported)
        local second = ns.Companion.ImportAll(raw)
        assert.equal(0, #second.imported)
        assert.equal(2, #second.unchanged)
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-16a (WKE-581). M3-16 asked the vault question from inside the refresh, and
-- the wait that followed turned the refresh's `ReloadUI` into an addon's action
-- the client refuses. The question moves to login: the same one interaction,
-- one call earlier, with nothing waiting on it - and by the time the player
-- types the refresh the client is carrying the rewards, so the chain is
-- synchronous and the reload is his own again.

describe("the vault question at login", function()
    local ns, world

    local VAULT_ITEM = "|cffa335ee|Hitem:210003::::::::80:105::13:2:7:8::::::|h[Vault Chest]|h|r"
    local ANSWERED = {
        activities = {
            {
                type = 1,
                index = 1,
                threshold = 1,
                progress = 2,
                id = 11,
                level = 10,
                rewards = { { type = 1, id = 210003, quantity = 1, itemDBID = "9001" } },
            },
        },
        links = { ["9001"] = VAULT_ITEM },
        examples = { [11] = { VAULT_ITEM } },
    }

    -- The measured state (docs/ARCHITECTURE.md §9, 2026-09-09/10): rewards are
    -- waiting and not one activity carries one.
    local function withheld()
        world.vault.hasAvailable = true
        world.vault.currentPeriod = false
        world.vault.generated = true
        world.vault.activities = {
            { type = 1, index = 1, threshold = 1, progress = 2, id = 11, level = 1, rewards = {} },
        }
        world.vault.answerOnInteract = ANSWERED
        world.vault.answerDelaySeconds = 0.4
    end

    before_each(function()
        ns, world = H.load()
        -- R-7b (WKE-591): a dressed character, because an empty equipment read
        -- is no longer stored at all and these tests are about the chain.
        H.dress(world)
    end)

    after_each(function()
        H.unload()
    end)

    -- Proven red by unregistering PLAYER_ENTERING_WORLD on Core.lua's frame:
    -- OnUIInteract is never called and the count is 0, which is the state
    -- M3-16 left the login in.
    it("asks the client once, closes the interaction, and captures nothing", function()
        withheld()
        world.fireEvent("PLAYER_ENTERING_WORLD")
        world.runTimers(10)
        assert.equal(1, world.vault.interact.onUIInteract)
        assert.equal(1, world.vault.interact.closeInteraction)
        assert.is_true(ns.vaultLoginAsk.askedAtLogin)
        assert.is_true(ns.vaultLoginAsk.updateFired)
        assert.is_number(ns.vaultLoginAsk.waitedMs)
        -- No capture, no reload: the client is just left holding its own data.
        assert.is_nil(ns.db.global.captures.vault)
        assert.is_nil(ns.db.global.captures.env)
        assert.equal(0, world.reloads)
    end)

    -- Closing the interaction on a timeout is M3-16's rule and this inherits it
    -- whole, because it is the same `ns.VaultInteract`. Proven red by returning
    -- before `record.close` in that function: the count is 0.
    it("closes the interaction on the timeout too", function()
        withheld()
        world.vault.answerOnInteract = nil
        world.fireEvent("PLAYER_ENTERING_WORLD")
        assert.equal(1, world.vault.interact.onUIInteract)
        assert.equal(0, world.vault.interact.closeInteraction)
        world.runTimers(ns.VAULT_INTERACT_TIMEOUT_SECONDS + 1)
        assert.equal(1, world.vault.interact.closeInteraction)
        assert.is_true(ns.vaultLoginAsk.timedOut)
    end)

    -- The exception is allowed only in the state it was allowed for. Proven red
    -- by making `loginAskNeeded` return true unconditionally.
    it("does not ask when no rewards are waiting", function()
        world.vault.hasAvailable = false
        world.fireEvent("PLAYER_ENTERING_WORLD")
        assert.equal(0, world.vault.interact.onUIInteract)
        assert.is_false(ns.vaultLoginAsk.askedAtLogin)
        assert.equal(ns.Companion.LOGIN_ASK_NOTHING, ns.vaultLoginAsk.reason)
    end)

    it("does not ask when the activities already carry rewards", function()
        world.vault.hasAvailable = true
        world.vault.activities = ANSWERED.activities
        world.vault.links = ANSWERED.links
        world.fireEvent("PLAYER_ENTERING_WORLD")
        assert.equal(0, world.vault.interact.onUIInteract)
        assert.is_false(ns.vaultLoginAsk.askedAtLogin)
        assert.equal(ns.Companion.LOGIN_ASK_CARRIED, ns.vaultLoginAsk.reason)
    end)

    -- Once per session, and the module says so itself rather than leaning on
    -- Core.lua having unregistered the event: `PLAYER_ENTERING_WORLD` fires
    -- again after every loading screen, and a question per zone change is not
    -- what the owner allowed. Called directly for that reason. Proven red by
    -- dropping the `Companion.loginAsked` guard: the second call asks again
    -- and the count is 2.
    it("asks once a session however many times it is called", function()
        withheld()
        -- The client that NEVER answers is where the guard is the only thing
        -- holding: after an ask that worked the activities carry rewards and
        -- `loginAskNeeded` would refuse a second one anyway, so a test built
        -- on the happy path proves nothing about the guard.
        world.vault.answerOnInteract = nil
        ns.Companion.AskVaultAtLogin()
        world.runTimers(ns.VAULT_INTERACT_TIMEOUT_SECONDS + 1)
        assert.equal(1, world.vault.interact.onUIInteract)
        ns.Companion.AskVaultAtLogin()
        world.runTimers(ns.VAULT_INTERACT_TIMEOUT_SECONDS + 1)
        assert.equal(1, world.vault.interact.onUIInteract)
        -- And through the event, which is the path the client takes.
        world.fireEvent("PLAYER_ENTERING_WORLD")
        world.runTimers(ns.VAULT_INTERACT_TIMEOUT_SECONDS + 1)
        assert.equal(1, world.vault.interact.onUIInteract)
    end)

    -- Nothing runs in combat (CLAUDE.md). Proven red by removing the
    -- `InCombatLockdown` check: the question is asked mid-fight.
    it("asks nothing in combat, and asks when the fight is over", function()
        withheld()
        world.inCombat = true
        world.fireEvent("PLAYER_ENTERING_WORLD")
        assert.equal(0, world.vault.interact.onUIInteract)
        assert.is_false(ns.vaultLoginAsk.askedAtLogin)
        assert.equal(ns.Companion.LOGIN_ASK_COMBAT, ns.vaultLoginAsk.reason)
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        world.runTimers(10)
        assert.equal(1, world.vault.interact.onUIInteract)
        assert.is_true(ns.vaultLoginAsk.askedAtLogin)
        -- And once the fight-end asked it, another one does not ask again.
        world.fireEvent("PLAYER_REGEN_ENABLED")
        world.runTimers(10)
        assert.equal(1, world.vault.interact.onUIInteract)
    end)

    -- THE POINT OF THE WHOLE ISSUE. After the login ask the client carries the
    -- rewards, so the vault capture has nothing to ask for, the chain finishes
    -- inside the slash command, and `ReloadUI` is the player's own action
    -- again. Proven red by making `AskVaultAtLogin` return without calling
    -- `ns.VaultInteract`: the refresh goes back to waiting and the popup path,
    -- and `world.reloads` is 0 on the line below.
    it("leaves the refresh synchronous: it reloads at once and shows no box", function()
        withheld()
        world.fireEvent("PLAYER_ENTERING_WORLD")
        world.runTimers(10)
        local before = world.vault.interact.onUIInteract
        local result = ns.Companion.Refresh()
        assert.is_true(result.ok)
        assert.is_true(result.reloaded)
        assert.equal(1, world.reloads)
        assert.equal(0, #world.popupsShown)
        assert.is_false(ns.Companion.waitingForVault)
        -- And the capture did not ask a second time: the client already had it.
        assert.equal(before, world.vault.interact.onUIInteract)
        assert.is_false(ns.db.global.captures.vault[1].data.interact.attempted)
    end)

    -- The transcript is the only proof the question was asked at all, since no
    -- capture was taken at the time. Proven red by removing the field from the
    -- env capture: the snapshot carries nothing about the login.
    it("is recorded in the next env snapshot", function()
        withheld()
        world.fireEvent("PLAYER_ENTERING_WORLD")
        world.runTimers(10)
        ns.HandleSlash("capture env")
        local record = ns.db.global.captures.env[1].data.vaultLoginAsk
        assert.is_true(record.askedAtLogin)
        assert.is_true(record.updateFired)
        assert.is_number(record.waitedMs)
    end)

    it("records that the login looked and found nothing to ask about", function()
        world.vault.hasAvailable = false
        world.fireEvent("PLAYER_ENTERING_WORLD")
        ns.HandleSlash("capture env")
        local record = ns.db.global.captures.env[1].data.vaultLoginAsk
        assert.is_false(record.askedAtLogin)
        assert.equal(ns.Companion.LOGIN_ASK_NOTHING, record.reason)
    end)

    -- A capture taken before any login event still says so rather than looking
    -- like a login that found nothing.
    it("records `absent` when no login event has run", function()
        ns.HandleSlash("capture env")
        assert.is_true(ns.db.global.captures.env[1].data.vaultLoginAsk.absent)
    end)
end)

-- ---------------------------------------------------------------------------
-- R-7 (WKE-579). "Log out, and your plan is current next time you log in" was
-- true only after a refresh: the addon took its snapshots nowhere else, so the
-- logout flushed the last ones again and the companion skipped an unchanged
-- profile (R-6's finding, docs/ARCHITECTURE.md §7). The same four snapshots at
-- `PLAYER_LOGOUT` are what make the sentence true. There is no reload, nothing
-- asynchronous, and the vault is read plainly.
--
-- R-7a (WKE-582): `PLAYER_LOGOUT` is an unload event, not a logout event - it
-- fires on `/reload` too, and the owner's 2026-09-15 pull carried five `env`
-- snapshots stamped `logout` for at most one logout. The sequence still runs on
-- both, because a reload's snapshot is what makes the refresh loop's second
-- reload carry fresh gear; what changed is that everything it writes says
-- `flush`, which is true of either.

describe("the capture at the flush", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        -- R-7b (WKE-591): a dressed character, because an empty equipment read
        -- is no longer stored at all and these tests are about the chain.
        H.dress(world)
    end)

    after_each(function()
        H.unload()
    end)

    local function recordCaptures()
        local calls = {}
        local original = ns.RunCapture
        ns.RunCapture = function(name, ...)
            calls[#calls + 1] = name
            return original(name, ...)
        end
        return calls
    end

    -- Proven red by unregistering PLAYER_LOGOUT on Core.lua's frame: no
    -- snapshot is stored at all and the count is 0, which is the behaviour this
    -- issue exists to change.
    it("runs the refresh's captures except the vault, exactly once, and never reloads", function()
        local calls = recordCaptures()
        world.fireEvent("PLAYER_LOGOUT")
        assert.same({ "env", "inventory", "currencies" }, calls)
        assert.same({ "env", "inventory", "currencies" }, ns.Companion.FLUSH_CAPTURES)
        for _, name in ipairs(ns.Companion.FLUSH_CAPTURES) do
            assert.equal(1, #ns.db.global.captures[name])
        end
        assert.equal(0, world.reloads)
    end)

    -- M3-16b (WKE-583): the vault is not one of them, and the reason is the
    -- owner's reset day. His refresh at 19:09:29Z asked the client and stored
    -- the answer; the flush at the refresh's own reload stored the same read
    -- two seconds later and, being the newest, was what the companion built the
    -- profile from. A read that cannot ask can only shadow one that did.
    -- Proven red by putting "vault" back into `Companion.FLUSH_SKIPS`' way -
    -- that is, by running `REFRESH_CAPTURES` here again: a vault snapshot is
    -- stored at the flush and this fails on both counts.
    it("never captures the vault at the flush", function()
        local calls = recordCaptures()
        world.fireEvent("PLAYER_LOGOUT")
        for _, name in ipairs(calls) do
            assert.not_equal("vault", name)
        end
        assert.is_nil(ns.db.global.captures.vault)
    end)

    -- The reload is the refresh's last step and must not be the logout's: the
    -- client is already leaving. Proven red by calling `ReloadUI()` at the end
    -- of `CaptureAtFlush`.
    it("does not need ReloadUI at all", function()
        _G.ReloadUI = nil
        local result = ns.Companion.CaptureAtFlush()
        assert.is_true(result.ok)
        assert.equal(1, #ns.db.global.captures.env)
    end)

    -- Every snapshot carries the label, which is the only thing that lets the
    -- companion say what the write carried rather than guessing. R-7a (WKE-582):
    -- the label is `flush`, never `logout`, because `PLAYER_LOGOUT` fires on a
    -- `/reload` too and nothing here can tell the two apart. Proven red by
    -- dropping the `ns.captureTrigger` assignment: the snapshots read "command"
    -- and the companion's line is the hand-capture one.
    it("labels every snapshot `flush`, and leaves the trigger clean behind it", function()
        ns.Companion.CaptureAtFlush()
        for _, name in ipairs(ns.Companion.FLUSH_CAPTURES) do
            assert.equal("flush", ns.db.global.captures[name][1].trigger)
            assert.not_equal("logout", ns.db.global.captures[name][1].trigger)
        end
        assert.is_nil(ns.captureTrigger)
        ns.HandleSlash("capture env")
        assert.equal("command", ns.db.global.captures.env[2].trigger)
    end)

    -- What the owner's transcripts are read for: five of them on 2026-09-15
    -- measured 19.5-33.1 ms. `capturedOn` says `flush` for the same reason
    -- `trigger` does, and the cost field is named for the occasion it measures.
    -- Proven red by removing the two fields.
    it("stamps the env snapshot with the occasion and what the sequence cost", function()
        local result = ns.Companion.CaptureAtFlush()
        local env = ns.db.global.captures.env[1]
        assert.equal("flush", env.capturedOn)
        assert.equal(result.elapsedMs, env.flushMs)
        assert.is_true(type(env.flushMs) == "number" and env.flushMs >= 0)
    end)

    -- Nothing at logout may fail loudly: a capture that throws leaves the ones
    -- after it to run and is recorded rather than raised. Proven red by
    -- dropping the `pcall` around `ns.RunCapture`: the error escapes and the
    -- three captures after `env` never happen.
    it("keeps going when one capture throws, and records what refused", function()
        local original = ns.RunCapture
        ns.RunCapture = function(name, onComplete, args)
            if name == "inventory" then
                error("the client moved C_Container")
            end
            return original(name, onComplete, args)
        end
        local result = ns.Companion.CaptureAtFlush()
        assert.is_false(result.ok)
        assert.equal(1, #result.failures)
        assert.equal("inventory", result.failures[1].capture)
        assert.is_truthy(tostring(result.failures[1].reason):find("C_Container", 1, true))
        assert.equal(1, #ns.db.global.captures.env)
        assert.is_nil(ns.db.global.captures.inventory)
        assert.is_nil(ns.db.global.captures.vault)
        assert.equal(1, #ns.db.global.captures.currencies)
    end)

    -- And the event itself cannot carry an error out of the addon either.
    it("cannot throw out of PLAYER_LOGOUT", function()
        ns.Companion.CaptureAtFlush = function()
            error("anything at all")
        end
        assert.has_no.errors(function()
            world.fireEvent("PLAYER_LOGOUT")
        end)
    end)

    -- R-7b (WKE-591). **THE POINT OF THE ISSUE.** The owner's 2026-09-15
    -- 22:11:52 logout flushed an `inventory` snapshot of `equipped 0` (his live
    -- file, parsed 2026-09-16); it became the newest, the companion built a
    -- profile with no gear in it, sent it to QE Live and died at the fork. On a
    -- `/reload` the same sequence reads all fifteen pieces, so the empty read
    -- is the logout's and nothing at the moment it happens can say why.
    describe("when the client answers the equipment scan with nothing", function()
        before_each(function()
            -- A level-90 Druid the client will not name gear for: exactly the
            -- shape of the 22:11:52 flush, where `env` still answered
            -- `UnitLevel 90` and `UnitClass Druid`.
            world.equipped = {}
        end)

        -- Proven red by taking `{ refuse = inventoryIsEmpty }` off the
        -- `inventory` capture: an empty snapshot is stored and both of the
        -- first two assertions fail.
        it("stores no inventory snapshot, and the rest of the flush still runs", function()
            local result = ns.Companion.CaptureAtFlush()
            assert.is_nil(ns.db.global.captures.inventory)
            assert.equal(1, #ns.db.global.captures.env)
            assert.equal(1, #ns.db.global.captures.currencies)
            assert.is_false(result.ok)
            assert.equal(1, #result.failures)
            assert.equal("inventory", result.failures[1].capture)
        end)

        -- What the refusal is for: the newest good read is still the newest,
        -- so the companion's next run reads the gear the player was actually
        -- wearing rather than nothing.
        it("leaves yesterday's good read the newest one on disk", function()
            H.dress(world)
            assert.is_true(ns.RunCapture("inventory").ok)
            world.equipped = {}
            world.fireEvent("PLAYER_LOGOUT")
            local list = ns.db.global.captures.inventory
            assert.equal(1, #list)
            assert.equal(1, #list[1].data.equipped)
        end)

        -- A refusal stores no snapshot of its own, so the only trace it can
        -- leave is on the one record of the same flush that IS stored. Without
        -- it a pull shows an `inventory` history hours older than the `env`
        -- beside it and nothing saying why. Proven red by deleting the
        -- `flushRefusals` assignment in `CaptureAtFlush`.
        it("records on the env snapshot that the inventory read was refused, and why", function()
            world.fireEvent("PLAYER_LOGOUT")
            local env = ns.db.global.captures.env[1]
            assert.equal(1, #env.flushRefusals)
            assert.equal("inventory", env.flushRefusals[1].capture)
            assert.truthy(tostring(env.flushRefusals[1].reason):find(ns.INVENTORY_EMPTY_REASON, 1, true))
        end)
    end)

    -- R-7b (WKE-591): the measurement, not a fix. Ketho's
    -- `SystemDocumentation.lua` declares `PLAYER_LEAVING_WORLD` and
    -- `PLAYER_LOGOUT` both `SynchronousEvent = true` and says nothing about
    -- which fires first or what still answers at either, so the addon counts
    -- equipped links one event earlier and carries the count into the flush's
    -- own `env` snapshot. The owner's next real logout is what reads it.
    describe("the equipment count one event earlier", function()
        it("counts links at PLAYER_LEAVING_WORLD without storing a snapshot", function()
            local before = ns.db.global.captures.inventory
            world.fireEvent("PLAYER_LEAVING_WORLD")
            assert.equal(1, ns.leavingWorld.equipped)
            assert.is_string(ns.leavingWorld.atLocal)
            assert.equal(before, ns.db.global.captures.inventory)
        end)

        -- The whole question in one record: what the client answered one event
        -- before the flush, beside what it answered at it. Proven red by
        -- deleting the `leavingWorld` assignment in `CaptureAtFlush`.
        it("carries that count into the flush's env snapshot", function()
            world.fireEvent("PLAYER_LEAVING_WORLD")
            world.equipped = {}
            world.fireEvent("PLAYER_LOGOUT")
            local env = ns.db.global.captures.env[1]
            assert.equal(1, env.leavingWorld.equipped)
            assert.is_nil(ns.db.global.captures.inventory)
        end)

        it("reads nothing in combat, because nothing does", function()
            world.inCombat = true
            world.fireEvent("PLAYER_LEAVING_WORLD")
            assert.is_nil(ns.leavingWorld)
        end)
    end)

    -- Nothing runs in combat, and ns.RunCapture refuses every capture there, so
    -- a forced logout in combat stores nothing and says so. Not even an `env`
    -- record survives, which is the honest answer rather than a half-snapshot.
    it("captures nothing in combat", function()
        world.inCombat = true
        local result = ns.Companion.CaptureAtFlush()
        assert.is_false(result.ok)
        assert.equal("combat", result.reason)
        assert.is_nil(ns.db.global.captures.env)
        assert.is_nil(ns.db.global.captures.inventory)
        assert.is_nil(ns.db.global.captures.vault)
        assert.is_nil(ns.db.global.captures.currencies)
    end)

    -- M3-16's interaction asks the server for the withheld rewards and waits
    -- for WEEKLY_REWARDS_UPDATE. At the flush there is no time to wait and
    -- nothing left running to receive the answer. R-7 read the vault plainly
    -- here and said so; M3-16b takes it out of the sequence altogether, so the
    -- client is not asked and nothing is stored.
    describe("with the client holding the vault rewards back", function()
        before_each(function()
            world.vault.hasAvailable = true
            world.vault.currentPeriod = false
            world.vault.generated = true
            world.vault.activities = {
                { type = 1, index = 1, threshold = 1, progress = 2, id = 11, level = 1, rewards = {} },
            }
        end)

        -- Proven red by running `REFRESH_CAPTURES` in `CaptureAtFlush` again:
        -- OnUIInteract is called once, the capture is left pending on a timer
        -- that can never fire, and the empty read is stored over the refresh's.
        it("never asks the client, and stores no vault snapshot at all", function()
            ns.Companion.CaptureAtFlush()
            assert.is_nil(ns.db.global.captures.vault)
            assert.equal(0, world.vault.interact.onUIInteract)
            assert.equal(0, world.vault.interact.closeInteraction)
        end)

        -- And the refresh's answer is what survives the flush that follows it,
        -- which is the whole point: the owner's 19:09:29Z read, not the
        -- 19:09:31Z one.
        it("leaves the refresh's vault snapshot as the newest one", function()
            world.vault.answerOnInteract = {
                activities = {
                    {
                        type = 1,
                        index = 1,
                        threshold = 1,
                        progress = 2,
                        id = 11,
                        level = 10,
                        rewards = { { type = 1, id = 210003, quantity = 1, itemDBID = "9001" } },
                    },
                },
                links = { ["9001"] = "|cffa335ee|Hitem:210003::::::::80:105::::::|h[Placeholder]|h|r" },
                examples = {},
            }
            ns.Companion.Refresh()
            world.runTimers(10)
            local stored = ns.db.global.captures.vault
            assert.equal(1, #stored)
            ns.Companion.CaptureAtFlush()
            assert.equal(1, #ns.db.global.captures.vault)
            assert.is_true(ns.db.global.captures.vault[1].data.interact.attempted)
            assert.equal(1, #ns.db.global.captures.vault[1].data.interact.after.rewardLinks)
        end)

        -- Nothing asynchronous: `PLAYER_LOGOUT` is synchronous and the client
        -- stops running Lua after it, so a timer left behind is a promise
        -- nothing can keep. Proven red by restoring RunCapture's unconditional
        -- timeout registration: one timer is left pending.
        it("leaves no timer behind", function()
            local before = #world.timers
            ns.Companion.CaptureAtFlush()
            assert.equal(before, #world.timers)
            assert.is_nil(ns.runningCapture)
        end)

        -- The refresh is unchanged: the interaction still happens there.
        it("leaves the refresh's own interaction alone", function()
            ns.Companion.Refresh()
            assert.equal(1, world.vault.interact.onUIInteract)
        end)
    end)
end)

-- ---------------------------------------------------------------------------
-- C-13 (WKE-584): how many vault items the run's profile carried.
--
-- File-level, like the scenario note and for the same reason: the profile is
-- the RUN's and not any one document's. ZERO is the whole point of the field -
-- on reset day before the player opens the Great Vault the companion builds a
-- profile with no vault section at all (M3-16b, WKE-583), and nothing else the
-- file carries tells that from a pool that simply had no vault card in it.
describe("the count of vault items the profile carried (C-13)", function()
    local ns

    local function file(fields)
        local raw = {
            writtenAt = "2026-09-15T19:09:00Z",
            companionVersion = "0.1.0",
            exports = {
                {
                    schema = "qe-live-droptimizer",
                    contentType = "Dungeon",
                    scenario = "thisWeek",
                    json = readFile(DUNGEON_EXPORT),
                },
            },
        }
        for key, value in pairs(fields or {}) do
            raw[key] = value
        end
        return raw
    end

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("carries a zero onto the verdict as a zero and never as an absence", function()
        local result = ns.Companion.ImportAll(file({ profileVaultCount = 0 }))
        assert.is_true(result.ok, result.reason)
        assert.equal(0, result.profileVaultCount)
        assert.equal(0, ns.QEImport.ForContentTypeAndScenario("Dungeon", "thisWeek").profileVaultCount)
    end)

    it("carries a count the same way", function()
        local result = ns.Companion.ImportAll(file({ profileVaultCount = 4 }))
        assert.is_true(result.ok, result.reason)
        assert.equal(4, ns.QEImport.ForContentTypeAndScenario("Dungeon", "thisWeek").profileVaultCount)
    end)

    it("says nothing for a file that said nothing, and for one that said something else", function()
        assert.is_nil(ns.Companion.ImportAll(file()).profileVaultCount)
        assert.is_nil(ns.Companion.ImportAll(file({ profileVaultCount = "4" })).profileVaultCount)
        assert.is_nil(ns.Companion.ImportAll(file({ profileVaultCount = -1 })).profileVaultCount)
        assert.is_nil(ns.Companion.ImportAll(file({ profileVaultCount = 1.5 })).profileVaultCount)
    end)
end)

-- R-7b (WKE-591), the owner's question of 2026-09-15 night: he was logged in as
-- Guardian when the logout captured nothing, and asked whether the spec had
-- caused it. It had not - the scan never looks at spec, and the `env` read of
-- that flush records class Druid with `specInfo` absent - but the question
-- named the hole beside it. A refresh taken in a non-healing spec captures THAT
-- spec's equipment as "what you wear", and the plan reads that gear as worn.
--
-- `tools/companion/lib/profile.js` `specMismatch` catches one half of this,
-- after the fact: QE Live's own browser profile against the capture. This is
-- the half the client can say BEFORE the mistake is made. Nothing is refused
-- and no rating is touched.
describe("the spec you are in against the spec the plan is for", function()
    local ns, world

    local GUARDIAN = { index = 3, id = 104, name = "Guardian", icon = 132276, role = "TANK" }

    before_each(function()
        ns, world = loadWithChunk(verdictChunkSource(twoRealExports()))
    end)

    after_each(function()
        H.unload()
    end)

    -- The committed export is a Restoration Druid's, which is what makes
    -- Guardian a disagreement rather than a made-up pair.
    it("reads the plan's own spec off the committed export", function()
        -- QE Live's own word for it, carried through unchanged: the export says
        -- "Restoration Druid" and the clause quotes the export.
        assert.equal("Restoration Druid", ns.UI.ActiveVerdict().spec)
    end)

    -- The string, once. Proven red by returning nil from `SpecClause` whenever
    -- the two names differ: every assertion below is nil.
    it("says which spec you are in and which the plan is for", function()
        world.spec = GUARDIAN
        assert.equal(
            "you're in Guardian; this rating is for Restoration Druid - switch and refresh",
            ns.Companion.SpecClauseNow()
        )
    end)

    it("says nothing when the two agree", function()
        -- The client says "Restoration" and the export says "Restoration Druid":
        -- one contains the other, which is agreement (`profile.js` compares its
        -- own pair the same way).
        assert.equal("Restoration", ns.Companion.CurrentSpec())
        assert.is_nil(ns.Companion.SpecClauseNow())
    end)

    it("says nothing when the client names no spec and no capture does either", function()
        world.spec = nil
        assert.is_nil(ns.Companion.SpecClauseNow())
    end)

    -- The issue's own shape: `specInfo = { 104, "Guardian" }` as an `env`
    -- capture stores it. The fallback is what a flush needs - the owner's
    -- 2026-09-16 file shows `GetSpecializationInfo` answering id 0 and no name
    -- at `PLAYER_LOGOUT`, so at that moment the stored capture is the only
    -- thing that names a spec at all.
    it("falls back to the newest env capture when the client will not answer", function()
        world.spec = nil
        local env = { specInfo = { 104, "Guardian", n = 2 } }
        assert.equal("Guardian", ns.Companion.SpecFromEnv(env))
        assert.equal(
            "you're in Guardian; this rating is for Restoration Druid - switch and refresh",
            ns.Companion.SpecClause(ns.UI.ActiveVerdict(), env)
        )
        -- and `{ absent = true }`, which is what the capture writes when the
        -- client names nothing, names nothing here either
        assert.is_nil(ns.Companion.SpecFromEnv({ specInfo = { absent = true } }))
    end)

    -- **H-1 (WKE-596) took the three cases below off the Guardian path.** R-7b
    -- said its sentence in a non-healer spec and let the refresh happen anyway;
    -- the healing gate stops the refresh in that spec outright, and says its own
    -- sentence on the same three surfaces. The clause itself is not retired: it
    -- is what a role the client does not NAME still says, off the newest `env`
    -- capture, and that is the path these three now drive. The gate's own
    -- behaviour is proven in "the healing gate" below.
    --
    -- The stored `env` snapshot is the shape `Companion.SpecFromEnv` reads and
    -- the one the flush writes.
    local function envNaming(spec)
        return { { capturedAt = time() - 60, data = { specInfo = { spec.id, spec.name, n = 2 } } } }
    end

    -- It never stops anything. Proven red by returning early from `Refresh`
    -- when the clause is non-nil: nothing is captured and nothing reloads.
    it("is said before the refresh captures, and the refresh happens anyway", function()
        world.spec = nil
        ns.db.global.captures.env = envNaming(GUARDIAN)
        H.dress(world)
        ns.Companion.Refresh()
        assert.is_truthy(world.output():find("this rating is for Restoration", 1, true))
        assert.equal(1, #ns.db.global.captures.inventory)
        assert.equal(1, world.reloads)
    end)

    -- R-6a's load line answers the question the player asked; this answers the
    -- one he did not know to ask, at the same moment and after it.
    it("is said at the load after a refresh, under the rating's own news", function()
        world.spec = nil
        ns.db.global.captures.env = envNaming(GUARDIAN)
        ns.db.global.drift = { refreshStartedAt = date("!%Y-%m-%dT%H:%M:%SZ", time() - 60) }
        -- R-6b (WKE-628): the skip has to be THIS click's answer, so its clock
        -- is dated from the same `now` the click is rather than from a fixed
        -- 2026-09-13 stamp that every later click is newer than. What this test
        -- is about - the spec clause said under the rating's own news - is
        -- untouched.
        ns.companionStatus = { state = "skipped", finishedAt = date("!%Y-%m-%dT%H:%M:%SZ", time() - 5) }
        local line = ns.Drift.LoadLine()
        assert.equal(ns.Drift.LOAD_SKIPPED, line)
        assert.is_truthy(world.output():find("this rating is for Restoration", 1, true))
    end)

    -- The strip: the sentence takes the line and the four facts go one surface
    -- in, exactly as M3-16b's wait does. Proven red by returning
    -- `table.concat(parts, ...)` from `lineFrom` regardless: the line is the
    -- facts again and the clause is nowhere.
    it("takes the strip's own line, and the facts it displaces go to the tooltip", function()
        world.spec = nil
        ns.db.global.captures.env = envNaming(GUARDIAN)
        local model = ns.UI.StatusStripModel()
        assert.equal("you're in Guardian; this rating is for Restoration Druid - switch and refresh", model.text)
        assert.equal(model.text, model.specClause)
        assert.is_truthy(table.concat(model.tooltip, "\n"):find("Restoration", 1, true))
    end)

    it("leaves the strip's line alone when the two agree", function()
        local model = ns.UI.StatusStripModel()
        assert.is_nil(model.specClause)
        assert.is_truthy(model.text:find("Restoration", 1, true))
    end)
end)

-- ---------------------------------------------------------------------------
-- H-1 (WKE-596): the healing gate.
--
-- The owner, 2026-09-16 evening: "Lootpath is strictly to help healers. When I
-- change my spec, Lootpath still attempts to tell me in my bags and in the UI
-- that I need to equip my healing gear. It should only do that in my healing
-- spec."
--
-- The gate is keyed on the ROLE the client names, never on a class or a spec
-- table of Lootpath's, and a role the client does NOT name is never gated -
-- which is the whole of R-7b's finding (the spec read is empty at
-- `ADDON_LOADED` and at a flush) turned into a rule.
describe("the healing gate", function()
    local ns, world

    local GUARDIAN = { index = 3, id = 104, name = "Guardian", icon = 132276, role = "TANK" }
    local BALANCE = { index = 1, id = 102, name = "Balance", icon = 136096, role = "DAMAGER" }
    -- A class with no healing spec at all: the stub's own four, minus the one.
    local NO_HEALER = {
        { index = 1, id = 250, name = "Blood", icon = 135770, role = "TANK" },
        { index = 2, id = 251, name = "Frost", icon = 135773, role = "DAMAGER" },
        { index = 3, id = 252, name = "Unholy", icon = 135775, role = "DAMAGER" },
    }

    before_each(function()
        ns, world = loadWithChunk(verdictChunkSource(twoRealExports()))
    end)

    after_each(function()
        H.unload()
    end)

    -- The read itself. Blizzard's fifth return, which is the one fact the whole
    -- gate stands on. Proven red by reading the fourth instead: the role is the
    -- spec's icon ID and nothing is ever gated.
    it("reads the role off the client's own fifth return", function()
        assert.equal("HEALER", ns.Companion.CurrentRole())
        world.spec = GUARDIAN
        assert.equal("TANK", ns.Companion.CurrentRole())
        world.spec = BALANCE
        assert.equal("DAMAGER", ns.Companion.CurrentRole())
        world.spec = nil
        assert.is_nil(ns.Companion.CurrentRole())
    end)

    -- The healer spec's own name, walked out of the client rather than looked
    -- up in a table of ours - which is what lets the sentence say `Restoration`
    -- for this Druid and the right word for any class Lootpath never heard of.
    it("names the healing spec by walking the class's own specializations", function()
        assert.equal("Restoration", ns.Companion.HealingSpecName())
        -- It does not depend on which spec the player is standing in.
        world.spec = GUARDIAN
        assert.equal("Restoration", ns.Companion.HealingSpecName())
        -- A class with no healing spec names none, and the sentences drop the
        -- clause that would have pointed at one.
        world.specs = NO_HEALER
        world.spec = NO_HEALER[1]
        assert.is_nil(ns.Companion.HealingSpecName())
        assert.equal("you're in Blood; Lootpath rates healing gear for now.", ns.Companion.GateLine())
        assert.equal(
            "you're in Blood; Lootpath rates healing gear, and this class has none",
            ns.Companion.GateRefreshLine()
        )
    end)

    -- Proven red by gating on `role ~= HEALER` alone, without the nil test:
    -- every assertion in this one fails, and so does half the suite - which is
    -- the point. A load reads no spec.
    it("never gates a role the client does not name", function()
        world.spec = nil
        assert.is_nil(ns.Companion.CurrentRole())
        assert.is_nil(ns.Companion.Gate())
        assert.is_nil(ns.Companion.GateLine())
        assert.is_nil(ns.Companion.GateCaptureReason())
        assert.is_nil(ns.Companion.GateRefreshLine())
    end)

    it("is down in the healing spec and up in every other named role", function()
        assert.is_nil(ns.Companion.Gate())
        world.spec = GUARDIAN
        local gate = ns.Companion.Gate()
        assert.equal("TANK", gate.role)
        assert.equal("Guardian", gate.spec)
        assert.equal("Restoration", gate.healer)
        world.spec = BALANCE
        assert.equal("Balance", ns.Companion.Gate().spec)
    end)

    -- The refresh. Proven red by taking the gate out of `Companion.Refresh`:
    -- the Guardian set is captured and the client reloads, which is exactly the
    -- noise the owner reported.
    it("stops the refresh before it captures or reloads, and says which spec to switch to", function()
        world.spec = GUARDIAN
        H.dress(world)
        local result = ns.Companion.Refresh()
        assert.is_false(result.ok)
        assert.equal(ns.Companion.GATE_REFRESH_REASON, result.reason)
        assert.is_truthy(world.output():find("you're in Guardian; switch to Restoration to refresh", 1, true))
        -- Nothing stored at all: not the gear, and not the `env` read either,
        -- because the refresh returns before the first capture runs.
        assert.equal(0, #(ns.db.global.captures.inventory or {}))
        assert.equal(0, #(ns.db.global.captures.env or {}))
        assert.equal(0, world.reloads)
    end)

    it("refreshes as it always has in the healing spec", function()
        H.dress(world)
        local result = ns.Companion.Refresh()
        assert.is_true(result.ok)
        assert.equal(1, #ns.db.global.captures.inventory)
        assert.equal(1, world.reloads)
    end)

    -- The load line, and `/lootpath status`'s first line: one sentence, the
    -- screen's own. Proven red by taking the gate out of `Drift.LoadLine`: the
    -- refresh state is announced again and the spec clause under it.
    it("says one sentence at the load, and nothing else", function()
        world.spec = GUARDIAN
        ns.db.global.drift = { refreshStartedAt = date("!%Y-%m-%dT%H:%M:%SZ", time() - 60) }
        ns.companionStatus = { state = "skipped", finishedAt = "2026-09-13T22:06:00Z" }
        local line = ns.Drift.LoadLine()
        assert.equal(
            "you're in Guardian; Lootpath rates healing gear for now - switch to Restoration and it's all here.",
            line
        )
        local output = world.output()
        assert.is_nil(output:find(ns.Drift.LOAD_SKIPPED, 1, true))
        assert.is_nil(output:find("this rating is for", 1, true))
    end)

    it("names the gate on the first line of /lootpath status", function()
        world.spec = GUARDIAN
        ns.HandleSlash("status")
        local output = world.output()
        assert.is_truthy(output:find("you're in Guardian; Lootpath rates healing gear for now", 1, true))
        -- and everything the command already printed still prints
        assert.is_truthy(output:find("captures stored:", 1, true))
    end)

    -- The nudge row and the minimap badge. Proven red by taking the gate out of
    -- `Drift.Check`: the nudge stands in Guardian and the badge with it.
    it("raises no nudge, and takes a standing one down on the spec change", function()
        ns.Drift.SetBehind({ count = 2, name = "Test Helm" })
        assert.is_table(ns.Drift.Model())
        world.spec = GUARDIAN
        world.fireEvent("PLAYER_SPECIALIZATION_CHANGED")
        world.runTimers(2)
        assert.is_nil(ns.Drift.Behind())
        assert.is_nil(ns.Drift.Model())
    end)
end)

-- ---------------------------------------------------------------------------
-- C-15 (WKE-615): a rating is for ONE character.
--
-- The owner, 2026-09-18, logged an old Restoration Shaman in on the account his
-- Druid is rated on. Equip Now showed the DRUID's answer - fifteen `you don't
-- own this` rows of Druid pieces beside the Shaman's own worn icons - and the
-- strip said `last rated 15 hours ago` as though the rating were his. His words:
-- "It looks as though it's trying to add items from 'hotornot' my druid."
--
-- `Data/QEVerdict.lua` is one file per machine and every character that logs in
-- loads it, so the store was never the problem: `QEImport.Store` writes into
-- `db.char` and always has. The file simply did not say whose gear it had
-- rated. Now it does, and this is the gate that reads it.
describe("C-15: the companion file names who it rated", function()
    local ns, world

    after_each(function()
        H.unload()
    end)

    -- The stub's own character is Tester of TestRealm, a DRUID (spec/stubs/wow).
    -- Those are the three the gate compares, and this is somebody else.
    local function asShaman(w)
        w.playerName = "Zapper"
        w.playerClass = { "Shaman", "SHAMAN", 7 }
    end

    local function druidsFile(writtenAt)
        local file = twoRealExports(writtenAt)
        file.character = { name = "Hotornot", realm = "Area 52", class = "DRUID" }
        return file
    end

    it("imports the file written for this character, exactly as before", function()
        ns, world = loadWithChunk(verdictChunkSource(twoRealExports()))
        assert.is_table(ns.QEImport.ForContentType("Dungeon"))
        assert.is_table(ns.QEImport.ForContentType("Raid"))
        assert.is_falsy(world.output():find("/lootpath refresh to rate this character", 1, true))
    end)

    -- The line the owner sees, in the addon's voice: what the rating is, who it
    -- is for, and the one thing that fixes it. No source named, nothing about a
    -- file on disk, and no offer to repair anything.
    it("refuses a file written for another character, in one line, and stores nothing", function()
        ns, world = loadWithChunk(verdictChunkSource(druidsFile()), { beforeLoad = asShaman })
        assert.is_truthy(
            world
                .output()
                :find("this rating is for Hotornot on Area 52 - /lootpath refresh to rate this character", 1, true),
            world.output()
        )
        assert.is_nil(ns.QEImport.Current())
        assert.is_nil(ns.QEImport.ForContentType("Dungeon"))
        assert.is_nil(ns.QEImport.ForContentType("Raid"))
        -- And nothing of the import's own chat, which would read as a rating
        -- that had arrived.
        assert.is_falsy(world.output():find("companion import:", 1, true))
    end)

    -- Two characters of one name on two realms are two characters. The realm is
    -- compared because the same name exists on every realm there is, and a
    -- rating for one of them is not a rating for the other.
    it("refuses a file for the same name on another realm", function()
        local file = twoRealExports()
        file.character = { name = "Tester", realm = "Another Realm", class = "DRUID" }
        ns, world = loadWithChunk(verdictChunkSource(file))
        assert.is_truthy(
            world
                .output()
                :find("this rating is for Tester on Another Realm - /lootpath refresh to rate this character", 1, true),
            world.output()
        )
        assert.is_nil(ns.QEImport.Current())
    end)

    -- Every file written before C-15, including the one the owner has on disk
    -- right now. It is refused for the same reason a file for somebody else is:
    -- a rating that cannot say who it is for cannot be trusted to anyone, and
    -- one `/lootpath refresh` replaces it.
    it("refuses a file that names no character at all", function()
        ns, world = loadWithChunk(verdictChunkSource({
            writtenAt = "2026-09-07T02:00:00Z",
            companionVersion = "0.1.0",
            character = false,
            exports = twoRealExports().exports,
        }))
        assert.is_truthy(
            world
                .output()
                :find("this rating doesn't say which character it's for - /lootpath refresh to rate this one", 1, true),
            world.output()
        )
        assert.is_nil(ns.QEImport.Current())
    end)

    -- `/lootpath status` says the same words. A player who types it because a
    -- tab looks wrong is owed the reason before the counts.
    it("says the same line on /lootpath status", function()
        ns, world = loadWithChunk(verdictChunkSource(druidsFile()), { beforeLoad = asShaman })
        local before = #world.output()
        ns.HandleSlash("status")
        local said = world.output():sub(before + 1)
        assert.is_truthy(
            said:find("this rating is for Hotornot on Area 52 - /lootpath refresh to rate this character", 1, true),
            said
        )
    end)

    -- The paste box is the player's own act and is untouched: he asked for THIS
    -- export on THIS character by pasting it.
    it("leaves the paste path alone", function()
        ns, world = loadWithChunk(verdictChunkSource(druidsFile()), { beforeLoad = asShaman })
        ns.UI.Frame()
        ns.UI.Import(readFile(RAID_EXPORT))
        assert.is_table(ns.QEImport.ForContentType("Raid"))
        assert.equal("pasted", ns.Companion.SourceText(ns.QEImport.ForContentType("Raid")))
    end)

    -- The import carries the file's claim onto the rating, so one that came back
    -- out of SavedVariables can still say who it is for long after the file that
    -- brought it was replaced.
    it("carries the character onto the stored rating", function()
        ns = loadWithChunk(verdictChunkSource(twoRealExports()))
        local stored = ns.QEImport.ForContentType("Raid")
        assert.equal("Tester", stored.character.name)
        assert.equal("TestRealm", stored.character.realm)
        assert.equal("DRUID", stored.character.class)
    end)
end)

-- The half of C-15 the spec check owns. `SpecClause` compared spec NAMES by
-- lower-case substring, and `Restoration` matches `Restoration` across Druid and
-- Shaman - which is why the owner's Shaman was never told anything. The class
-- token does not collide, so it is compared first, and a rating for somebody
-- else is never a spec line: switching spec would not fix it.
describe("C-15: SpecClause compares the class before the spec name", function()
    local ns

    after_each(function()
        H.unload()
    end)

    local DRUIDS_RATING = {
        spec = "Restoration Druid",
        character = { name = "Hotornot", realm = "Area 52", class = "DRUID" },
    }

    it("answers the character refusal for a Restoration Shaman against a Restoration Druid's rating", function()
        ns = H.load({
            beforeLoad = function(w)
                w.playerName = "Zapper"
                w.playerClass = { "Shaman", "SHAMAN", 7 }
                w.spec = { index = 1, id = 264, name = "Restoration", icon = 1, role = "HEALER" }
            end,
        })
        assert.equal(
            "this rating is for Hotornot on Area 52 - /lootpath refresh to rate this character",
            ns.Companion.SpecClause(DRUIDS_RATING)
        )
    end)

    it("says nothing to the Druid the rating is for, whose spec name the Shaman shares", function()
        ns = H.load({
            beforeLoad = function(w)
                w.playerName = "Hotornot"
                w.realm = "Area 52"
                w.playerClass = { "Druid", "DRUID", 11 }
                w.spec = { index = 4, id = 105, name = "Restoration", icon = 1, role = "HEALER" }
            end,
        })
        assert.is_nil(ns.Companion.SpecClause(DRUIDS_RATING))
    end)

    -- The spec line is still the spec line for the character the rating IS for.
    it("still says the spec line when only the spec differs", function()
        ns = H.load({
            beforeLoad = function(w)
                w.playerName = "Hotornot"
                w.realm = "Area 52"
                w.playerClass = { "Druid", "DRUID", 11 }
                w.spec = { index = 3, id = 104, name = "Guardian", icon = 1, role = "TANK" }
            end,
        })
        assert.equal(
            "you're in Guardian; this rating is for Restoration Druid - switch and refresh",
            ns.Companion.SpecClause(DRUIDS_RATING)
        )
    end)

    -- A paste carries no character and is not refused here: the player asked for
    -- that export on this character by pasting it.
    it("says nothing about a character for a rating that claims none", function()
        ns = H.load({
            beforeLoad = function(w)
                w.playerName = "Zapper"
                w.playerClass = { "Shaman", "SHAMAN", 7 }
            end,
        })
        assert.is_nil(ns.Companion.SpecClause({ spec = "Restoration Druid" }))
    end)
end)

-- C-15a (WKE-620): a rating already STORED is swept at login too.
--
-- The owner, 2026-09-18 afternoon, on `main` 4279b37 with C-15 in the game:
-- Equip Now on his Restoration Shaman still showed the Druid's fifteen `you
-- don't own this` rows. C-15 was doing its job - the chat line said the file on
-- disk did not say which character it was for - but the gate stops an IMPORT,
-- and the rating on screen had been stored by the Shaman's FIRST login, months
-- of reloads before the gate existed. Nothing was ever going to take it out:
-- the file that would have replaced it is refused every time.
--
-- So the store is swept, by source and by character, and one line says so.
describe("C-15a: a stored rating that is not this character's is dropped at login", function()
    local ns, world

    after_each(function()
        H.unload()
    end)

    local DROPPED_LINE = "dropped a rating that wasn't for this character - /lootpath refresh to rate this one"

    -- The stub's own character (spec/stubs/wow) is Tester of TestRealm, a DRUID.
    local THIS_CHARACTER = { name = "Tester", realm = "TestRealm", class = "DRUID" }
    local ANOTHER_CHARACTER = { name = "Hotornot", realm = "Area 52", class = "DRUID" }

    -- A store with one Top Gear rating and one Upgrade Finder document on it,
    -- put there the way a player puts one there, and NO companion file at all -
    -- so `Startup` below imports nothing and the only thing it can do is sweep.
    -- What makes each rating the companion's is then stamped on by hand, which
    -- is the honest model: a verdict that came back out of SavedVariables is a
    -- table with a `source` field and nothing more.
    local function seedStore()
        ns, world = H.load()
        ns.UI.Import(readFile(RAID_EXPORT))
        ns.UI.Import(readFile(UPGRADE_FINDER_EXPORT))
    end

    local function stamp(verdict, character)
        verdict.source = ns.Companion.SOURCE_COMPANION
        verdict.companionWrittenAt = "2026-09-17T02:00:00Z"
        verdict.character = character
        return verdict
    end

    local function storedTopGear()
        return assert(ns.QEImport.ForContentType("Raid"), "no Top Gear rating was seeded")
    end

    local function storedUpgradeFinder()
        return assert(ns.UFImport.Current(), "no Upgrade Finder document was seeded")
    end

    local function saidDroppedLine()
        return world.output():find(DROPPED_LINE, 1, true) ~= nil
    end

    it("drops a companion rating that names no character, and says so once", function()
        seedStore()
        stamp(storedTopGear(), nil)
        local before = #world.output()
        local result = ns.Companion.Startup()
        assert.equal(1, result.dropped)
        assert.is_nil(ns.QEImport.Current())
        assert.is_nil(ns.QEImport.ForContentType("Raid"))
        local said = world.output():sub(before + 1)
        assert.is_truthy(said:find(DROPPED_LINE, 1, true), said)
        -- Once. The rating is on three shelves; the line is about the player's
        -- screen, not about the store's shape.
        local _, times = said:gsub((DROPPED_LINE:gsub("%p", "%%%0")), "")
        assert.equal(1, times)
    end)

    it("drops a companion rating that names another character", function()
        seedStore()
        stamp(storedTopGear(), ANOTHER_CHARACTER)
        local result = ns.Companion.Startup()
        assert.equal(1, result.dropped)
        assert.is_nil(ns.QEImport.ForContentType("Raid"))
        assert.is_true(saidDroppedLine())
    end)

    it("keeps a companion rating that names THIS character, and says nothing", function()
        seedStore()
        local kept = stamp(storedTopGear(), THIS_CHARACTER)
        local result = ns.Companion.Startup()
        assert.equal(0, result.dropped)
        assert.equal(kept, ns.QEImport.ForContentType("Raid"))
        assert.is_false(saidDroppedLine())
    end)

    -- Deliverable 3. A paste is the player's own act on this character: he went
    -- and got that export and put it in the box himself. It carries no
    -- `character` and never will, so the rule is read off `source`, and a paste
    -- is kept whoever pasted it and whatever it names.
    it("keeps a pasted rating that names no character", function()
        seedStore()
        local pasted = storedTopGear()
        assert.is_nil(pasted.character)
        assert.equal("pasted", ns.Companion.SourceText(pasted))
        local result = ns.Companion.Startup()
        assert.equal(0, result.dropped)
        assert.equal(pasted, ns.QEImport.ForContentType("Raid"))
        assert.is_false(saidDroppedLine())
    end)

    it("drops the Upgrade Finder documents by the same rule, off all three shelves", function()
        seedStore()
        stamp(storedUpgradeFinder(), ANOTHER_CHARACTER)
        local contentType = ns.UFImport.ContentTypeKey(storedUpgradeFinder())
        assert.is_true(#ns.UFImport.Documents(contentType) > 0)
        local result = ns.Companion.Startup()
        assert.equal(1, result.dropped)
        assert.is_nil(ns.UFImport.Current())
        assert.is_nil(ns.UFImport.ForContentType(contentType))
        assert.same({}, ns.UFImport.Documents(contentType))
        assert.is_true(saidDroppedLine())
    end)

    -- Both stores, one line, and the count is by verdict rather than by shelf:
    -- a Top Gear rating sits on three shelves and an Upgrade Finder document on
    -- three of its own, and that is two ratings gone, not six.
    it("counts two ratings, not the six shelf entries they sit on", function()
        seedStore()
        stamp(storedTopGear(), ANOTHER_CHARACTER)
        stamp(storedUpgradeFinder(), ANOTHER_CHARACTER)
        local result = ns.Companion.Startup()
        assert.equal(2, result.dropped)
    end)

    -- C-11's later-pass shelf is a shelf like the others and is swept like the
    -- others: a pass-2 answer for a character who is not here rates items this
    -- one does not own.
    it("sweeps the by-scenario and later-pass shelves as well", function()
        seedStore()
        local plan = storedTopGear()
        local pass2 = { contentType = "Raid", pass = 2, spec = plan.spec, topSet = plan.topSet }
        ns.QEImport.Store(pass2)
        stamp(pass2, ANOTHER_CHARACTER)
        stamp(plan, ANOTHER_CHARACTER)
        assert.equal(1, #ns.QEImport.Passes("Raid", ns.QEImport.DEFAULT_SCENARIO))
        local result = ns.Companion.Startup()
        assert.equal(2, result.dropped)
        assert.is_nil(ns.QEImport.ForContentTypeAndScenario("Raid", ns.QEImport.DEFAULT_SCENARIO))
        assert.same({}, ns.QEImport.Passes("Raid", ns.QEImport.DEFAULT_SCENARIO))
    end)

    -- Deliverable 5, as a guard. The sweep is about ratings and nothing else:
    -- which slot sections the reader has shut is a fact about this character
    -- and has nothing to do with whose rating was stored.
    it("leaves db.char.upgradeMap and the rest of db.char alone", function()
        seedStore()
        ns.db.char.upgradeMap.collapsedSlots.Head = true
        ns.db.char.upgradeMap.expandedRuns["a-run"] = true
        stamp(storedTopGear(), ANOTHER_CHARACTER)
        ns.Companion.Startup()
        assert.is_true(ns.db.char.upgradeMap.collapsedSlots.Head)
        assert.is_true(ns.db.char.upgradeMap.expandedRuns["a-run"])
    end)

    -- Deliverable 4. An import calls it because a new rating is a new answer
    -- for every hover; a DROP is the same event with the sharper edge - the
    -- cache may already hold roads built from what has just gone.
    it("tells the roads cache the answer changed", function()
        seedStore()
        stamp(storedTopGear(), ANOTHER_CHARACTER)
        local calls = 0
        ns.RoadsCache.Changed = function()
            calls = calls + 1
        end
        ns.Companion.Startup()
        assert.equal(1, calls)
    end)

    it("does not tell the roads cache anything when nothing was dropped", function()
        seedStore()
        local calls = 0
        ns.RoadsCache.Changed = function()
            calls = calls + 1
        end
        ns.Companion.Startup()
        assert.equal(0, calls)
    end)

    -- The owner's own case, end to end: the Shaman logs in, the file on disk is
    -- the Druid's, and the Druid's rating is already in the Shaman's db.char.
    -- C-15's line refuses the file, C-15a's drops what is stored, and Equip Now
    -- has nothing of the Druid's left to draw.
    it("refuses the file AND empties the store when the Shaman logs in", function()
        ns, world = loadWithChunk(verdictChunkSource(twoRealExports()))
        assert.is_table(ns.QEImport.ForContentType("Dungeon"))
        assert.is_table(ns.QEImport.ForContentType("Raid"))
        world.playerName = "Zapper"
        world.playerClass = { "Shaman", "SHAMAN", 7 }
        local before = #world.output()
        local result = ns.Companion.Startup()
        assert.is_false(result.ok)
        assert.is_true(result.otherCharacter)
        assert.equal(2, result.dropped)
        assert.is_nil(ns.QEImport.Current())
        assert.is_nil(ns.QEImport.ForContentType("Dungeon"))
        assert.is_nil(ns.QEImport.ForContentType("Raid"))
        assert.is_nil(ns.UI.ActiveVerdict())
        local said = world.output():sub(before + 1)
        assert.is_truthy(said:find("this rating is for Tester on TestRealm", 1, true), said)
        assert.is_truthy(said:find(DROPPED_LINE, 1, true), said)
    end)

    -- And the Druid's own login is untouched: the file is his, the sweep finds
    -- nothing of anyone else's, and the rating is imported exactly as before.
    it("says nothing and drops nothing on the character the file names", function()
        ns, world = loadWithChunk(verdictChunkSource(twoRealExports()))
        local before = #world.output()
        local result = ns.Companion.Startup()
        assert.equal(0, result.dropped)
        assert.is_true(result.ok)
        assert.is_table(ns.QEImport.ForContentType("Raid"))
        assert.is_falsy(world.output():sub(before + 1):find(DROPPED_LINE, 1, true))
    end)
end)
