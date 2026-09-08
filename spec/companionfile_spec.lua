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
        assert.are.equal(3, #file.exports)
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
        assert.are.equal("qe-live-upgradefinder", documents[2].schema)
        assert.are.equal("Dungeon", documents[2].contentType)
        assert.are.equal("qe-live-upgradefinder", documents[3].schema)
        assert.are.equal("Raid", documents[3].contentType)
    end)

    -- C-7 (WKE-543): an Upgrade Finder document says which Mythic+ key level QE
    -- Live ran it at, because his engine values dungeon drops at exactly one
    -- key and the addon files each answer under the level it was asked at. It
    -- has to arrive as a Lua NUMBER: the string "10" would key a different
    -- shelf from the number 10 and quietly split one content type in two.
    it("says which Mythic+ key level an Upgrade Finder document was run at", function()
        local documents = load().companionVerdict.exports
        assert.is_nil(documents[1].keyLevel, "a Top Gear document is not run at a key level")
        assert.are.equal(10, documents[2].keyLevel)
        assert.are.equal("number", type(documents[2].keyLevel))
        assert.is_nil(documents[3].keyLevel, "a document that was not run at a key level must not claim one")
    end)

    it("round-trips every byte that could have ended the literal early", function()
        local documents = load().companionVerdict.exports
        assert.are.equal(HOSTILE, documents[3].json)
        -- Length is asserted separately, because an escape that silently ate a
        -- byte would still compare equal to a matching mistake above.
        assert.are.equal(#HOSTILE, #documents[3].json)
        assert.are.equal(#HOSTILE, documents[3].bytes)
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
            assert.is_truthy(ok, "unexpected line in a data-only chunk: " .. line)
        end
    end)
end)
