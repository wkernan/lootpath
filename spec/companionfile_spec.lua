-- spec/companionfile_spec.lua (C-1, WKE-533)
-- The one Lua file the companion writes, loaded by a real Lua interpreter.
--
-- `tools/companion/lib/luawriter.js` renders the chunk and
-- `tools/companion/test/luawriter.test.js` holds it to the committed golden
-- byte for byte. This spec closes the loop from the other side: it loads that
-- golden the way the client will - as an addon file called with
-- (addonName, ns) - and checks that every hostile byte the writer escaped comes
-- back as the byte QE Live exported, and that loading it does nothing except
-- set one table.
--
-- Why it matters: the chunk is the one exception to "everything external
-- arrives by paste" (decision 2026-09-07, docs/ARCHITECTURE.md §7). It is data,
-- never code, and the addon runs each `json` string through the same
-- ns.QEImport.Parse a paste goes through.

local GOLDEN = "spec/fixtures/expected/qeverdict-sample.lua"

-- The same bytes tools/companion/test/luawriter.test.js feeds the writer:
-- everything that could end a Lua literal early, and a chunk of Lua source
-- pretending to be a QE Live export. \195\169 is UTF-8 for an e-acute, spelt in
-- escapes so this file stays ASCII.
local HOSTILE = 'quote " backslash \\ close ]] and ]==] newline \n return \r tab \t nul \000 del \127 '
    .. 'accented \195\169 lua os.execute("calc") end return {} --[['

describe("the companion's Data/QEVerdict.lua", function()
    local function load()
        local chunk = loadfile(GOLDEN)
        assert.is_function(chunk, "the golden did not even parse as Lua")
        local ns = {}
        chunk("Lootpath", ns)
        return ns
    end

    it("sets exactly one field on the namespace and nothing else", function()
        local ns = load()
        local keys = {}
        for key in pairs(ns) do
            keys[#keys + 1] = key
        end
        assert.are.same({ "companionVerdict" }, keys)
    end)

    it("carries the companion's own stamp", function()
        local file = load().companionVerdict
        assert.are.equal("2026-09-08T00:00:00Z", file.writtenAt)
        assert.are.equal("0.1.0", file.companionVersion)
        assert.are.equal("2026-09-05T13:33:25", file.profileCapturedAt)
        assert.are.equal(4, #file.exports)
    end)

    -- C-5 (WKE-539): the file says which of QE Live's own import settings
    -- produced it, so a vault option he values at 321 while the client reads
    -- the same link at 305 is readable rather than a contradiction. They must
    -- come back as Lua booleans: the string "false" would be truthy.
    it("says which QE Live import settings produced it", function()
        local file = load().companionVerdict
        assert.is_table(file.qeSettings)
        assert.is_boolean(file.qeSettings.autoUpgradeVault)
        assert.is_boolean(file.qeSettings.autoUpgradeAll)
        assert.is_false(file.qeSettings.autoUpgradeVault)
        assert.is_false(file.qeSettings.autoUpgradeAll)
    end)

    it("hands the addon QE Live's export text, unchanged", function()
        local documents = load().companionVerdict.exports
        assert.are.equal("qe-live-droptimizer", documents[1].schema)
        assert.are.equal("Dungeon", documents[1].contentType)
        assert.are.equal('{"schema":"qe-live-droptimizer","version":1}', documents[1].json)
        assert.are.equal("qe-live-droptimizer", documents[2].schema)
        assert.are.equal("Dungeon", documents[2].contentType)
        assert.are.equal('{"schema":"qe-live-droptimizer","version":1,"catalyzed":true}', documents[2].json)
        assert.are.equal("qe-live-upgradefinder", documents[3].schema)
        assert.are.equal("Dungeon", documents[3].contentType)
        assert.are.equal("qe-live-upgradefinder", documents[4].schema)
        assert.are.equal("Raid", documents[4].contentType)
    end)

    -- C-6 (WKE-540): a Top Gear document says which named scenario it answers,
    -- and carries the three checkboxes that produced it. Two documents over the
    -- same gear and the same content type differ only in the question asked, so
    -- a document that did not say would be indistinguishable from the other.
    it("says which named scenario each Top Gear document answers", function()
        local documents = load().companionVerdict.exports
        assert.are.equal("asOffered", documents[1].scenario)
        assert.are.equal("catalyzed", documents[2].scenario)
        assert.is_nil(documents[3].scenario, "an Upgrade Finder document answers no scenario")
        assert.is_nil(documents[4].scenario)
        assert.is_false(documents[1].qeSettings.autoCatalyze)
        assert.is_true(documents[2].qeSettings.autoCatalyze)
        assert.is_boolean(documents[2].qeSettings.autoUpgradeVault)
        assert.is_false(documents[2].qeSettings.autoUpgradeAll)
    end)

    -- C-7 (WKE-543): an Upgrade Finder document says which Mythic+ key level QE
    -- Live ran it at, because his engine values dungeon drops at exactly one
    -- key and the addon files each answer under the level it was asked at. It
    -- has to arrive as a Lua NUMBER: the string "10" would key a different
    -- shelf from the number 10 and quietly split one content type in two.
    it("says which Mythic+ key level an Upgrade Finder document was run at", function()
        local documents = load().companionVerdict.exports
        assert.is_nil(documents[1].keyLevel, "a Top Gear document is not run at a key level")
        assert.are.equal(10, documents[3].keyLevel)
        assert.are.equal("number", type(documents[3].keyLevel))
        assert.is_nil(documents[4].keyLevel, "a document that was not run at a key level must not claim one")
    end)

    it("round-trips every byte that could have ended the literal early", function()
        local documents = load().companionVerdict.exports
        assert.are.equal(HOSTILE, documents[4].json)
        -- Length is asserted separately, because an escape that silently ate a
        -- byte would still compare equal to a matching mistake above.
        assert.are.equal(#HOSTILE, #documents[4].json)
        assert.are.equal(#HOSTILE, documents[4].bytes)
    end)

    -- C-8 (WKE-558): a non-patron's Top Gear takes thirty items and the
    -- character owns more, so the file names the ones QE Live was never shown.
    -- A verdict that omits items must say so on screen, and the panels can only
    -- say it if the names survive the chunk.
    it("names the items QE Live's Top Gear was never shown", function()
        local file = load().companionVerdict
        assert.are.equal(3, #file.excluded)
        assert.are.equal("Finger", file.excluded[1].slot)
        -- The quote in the name is the point: it came off QE Live's own card
        -- and went through the same escaper the JSON does.
        assert.are.equal('Band of the "Quoted" Name', file.excluded[1].name)
        assert.are.equal(678, file.excluded[1].level)
        assert.are.equal("number", type(file.excluded[1].level))
        assert.is_true(file.excluded[2].vault)
        assert.is_nil(file.excluded[1].vault, "a bag item does not claim to be a vault item")
        -- A card whose level could not be read is still named.
        assert.is_nil(file.excluded[3].level)
        assert.are.equal("a trinket with no level", file.excluded[3].name)
    end)

    it("gives each Top Gear document its own pool leftovers", function()
        local documents = load().companionVerdict.exports
        -- The Catalyst pass has a clone to leave out that the base pass never
        -- had, so one list for the whole file would be wrong about one of them.
        assert.are.equal(3, #documents[1].excluded)
        assert.are.equal(4, #documents[2].excluded)
        assert.is_true(documents[2].excluded[4].catalyst)
        assert.are.equal("a Catalyst clone", documents[2].excluded[4].name)
        assert.is_nil(documents[3].excluded, "an Upgrade Finder document chooses no pool")
        assert.is_nil(documents[4].excluded)
    end)

    it("is inert: loading it twice touches nothing but the namespace it is given", function()
        local chunk = loadfile(GOLDEN)
        local first = {}
        local second = {}
        chunk("Lootpath", first)
        chunk("Lootpath", second)
        assert.are.same(first.companionVerdict, second.companionVerdict)
        -- Called with no namespace at all - as a stray `lua QEVerdict.lua`
        -- would - it returns rather than erroring or writing a global.
        local before = _G.companionVerdict
        assert.has_no.errors(function()
            chunk()
        end)
        assert.are.equal(before, _G.companionVerdict)
    end)

    -- Since C-8 the chunk also holds one-line tables: `{ slot = "Head", name =
    -- "x", level = 700 },`. They are data too, and they are checked field by
    -- field rather than waved through - a key, an `=`, and a quoted string, a
    -- whole number or `true`, and nothing that could be a call.
    local function isInlineTable(line)
        local body = line:match("^%s*{ (.*) },$")
        if not body then
            return false
        end
        -- Escaped backslashes first, then escaped quotes, so a name that holds
        -- either cannot end a literal early here any more than it can in Lua.
        local stripped = body:gsub("\\\\", "@"):gsub('\\"', "@"):gsub('"[^"]*"', '""')
        for field in (stripped .. ", "):gmatch("(.-), ") do
            local ok = field:match('^[%w_]+ = ""$') or field:match("^[%w_]+ = %d+$") or field:match("^[%w_]+ = true$")
            if not ok then
                return false
            end
        end
        return true
    end

    -- The guard above is itself a guard, so it is proven rather than trusted:
    -- a one-line table that hides a call, a key it did not expect or an
    -- unterminated literal is not a line this waves through.
    it("does not wave through a one-line table that could run something", function()
        assert.is_true(isInlineTable('    { slot = "Head", name = "a \\"]] end -- name", level = 700 },'))
        assert.is_true(isInlineTable("    { vault = true },"))
        assert.is_false(isInlineTable('    { name = os.execute("calc") },'))
        assert.is_false(isInlineTable("    { name = ns.Something },"))
        assert.is_false(isInlineTable('    { name = "unterminated },'))
        assert.is_false(isInlineTable("    qeSettings = { autoUpgradeVault = false },"))
    end)

    it("holds no source a client could execute", function()
        local source = assert(io.open(GOLDEN, "rb"))
        local text = source:read("*a")
        source:close()
        -- Every line is a comment, the vararg guard, or one `key = value`.
        for line in text:gmatch("[^\n]+") do
            local ok = line:match("^%-%-")
                or line:match("^local _, ns = %.%.%.$")
                or line:match('^if type%(ns%) ~= "table" then$')
                or line:match("^%s*return$")
                or line:match("^end$")
                or line:match("^%s*[%w_.]+ = ")
                or line:match("^%s*[{}],?$")
                or isInlineTable(line)
            assert.is_truthy(ok, "unexpected line in a data-only chunk: " .. line)
        end
    end)
end)
