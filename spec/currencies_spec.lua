-- spec/currencies_spec.lua (M3-9, WKE-544)
--
-- **Every currency name and ID in this file is a placeholder.** No
-- `/lootpath capture currencies` transcript has been committed yet, so nothing
-- here claims to be the season's real crest or the client's real name for a
-- Catalyst charge; the shapes are Blizzard's documented `CurrencyInfo`
-- (Ketho's `CurrencyInfoDocumentation.lua`: `name`, `description`,
-- `currencyID`, `isHeader`, `quantity`, ...), the same way `vault_spec.lua`
-- drove the reward path off Blizzard's docs until the vault generated one.
--
-- What IS pinned here is the thing that matters: the module names nothing on
-- its own. `CREST_NAMES` and `CATALYST_NAMES` ship empty, and until a
-- transcript fills them every read reports `crestsKnown = false` and no
-- Catalyst count at all.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local HEADER = { name = "Placeholder Group", currencyID = 0, isHeader = true, quantity = 0 }
local CREST = { name = "Placeholder Crest", currencyID = 900001, isHeader = false, quantity = 42 }
local CREST_TWO = { name = "Placeholder Greater Crest", currencyID = 900003, isHeader = false, quantity = 7 }
local CHARGE = { name = "Placeholder Charge", currencyID = 900002, isHeader = false, quantity = 1 }

describe("Currencies", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        world.currencies = { HEADER, CREST, CREST_TWO, CHARGE }
    end)

    after_each(function()
        H.unload()
    end)

    -- The names are the client's, read from the 2026-09-08 23:04 transcript,
    -- and the Catalyst charge is known NOT to be a currency there - so the
    -- module reports "known, no count" for it rather than "unknown".
    it(
        "ships knowing the five Mistcrests by the client's names, and that the Catalyst charge is no currency",
        function()
            assert.same({
                "Adventurer Mistcrest",
                "Veteran Mistcrest",
                "Champion Mistcrest",
                "Hero Mistcrest",
                "Myth Mistcrest",
            }, ns.Currencies.CREST_NAMES)
            assert.same({}, ns.Currencies.CATALYST_NAMES)
            assert.is_true(ns.Currencies.CATALYST_NOT_A_CURRENCY)
            local read = ns.Currencies.Read()
            assert.is_true(read.ok)
            assert.is_true(read.crestsKnown)
            assert.is_true(read.catalystKnown)
            assert.is_nil(read.catalystCharges)
        end
    )

    it("reads the owner's transcript: five Mistcrests with their IDs and counts, no Catalyst currency", function()
        local snapshot = R.snapshot("currencies", 2, "spec/fixtures/captures/Lootpath-20260908-230426.lua")
        assert.equal("2026-09-08T23:04:26", snapshot.capturedAtLocal)
        local read = ns.Currencies.Read({ snapshot = snapshot })
        assert.is_true(read.ok)
        assert.equal("capture", read.source)
        assert.equal(18, #read.entries)
        local headers = 0
        for _, entry in ipairs(read.entries) do
            if entry.isHeader then
                headers = headers + 1
            end
            assert.is_nil(tostring(entry.name):find("Catalyst", 1, true))
        end
        assert.equal(10, headers)
        assert.same({
            { name = "Adventurer Mistcrest", currencyID = 3442, quantity = 356 },
            { name = "Veteran Mistcrest", currencyID = 3443, quantity = 0 },
            { name = "Champion Mistcrest", currencyID = 3444, quantity = 2 },
            { name = "Hero Mistcrest", currencyID = 3445, quantity = 21 },
            { name = "Myth Mistcrest", currencyID = 3446, quantity = 20 },
        }, read.crests)
        assert.is_true(read.catalystKnown)
        assert.is_nil(read.catalystCharges)
        assert.equal(0, read.secretsSeen)
    end)

    it("reads the live list, headers and all", function()
        local read = ns.Currencies.Read()
        assert.equal("live", read.source)
        assert.equal(4, #read.entries)
        assert.is_true(read.entries[1].isHeader)
        assert.equal("Placeholder Crest", read.entries[2].name)
        assert.equal(42, read.entries[2].quantity)
        assert.equal(900001, read.entries[2].currencyID)
        assert.equal(0, read.secretsSeen)
    end)

    -- The red proof for the assertion above it: fill the names in, and the same
    -- list answers with the counts. This is what a committed transcript will do
    -- to the shipped table, one edit, with no other change anywhere.
    it("reports the counts once the names are known, in the order they are named", function()
        ns.Currencies.CREST_NAMES = { "Placeholder Greater Crest", "Placeholder Crest" }
        ns.Currencies.CATALYST_NAMES = { "Placeholder Charge" }
        local read = ns.Currencies.Read()
        assert.is_true(read.crestsKnown)
        assert.is_true(read.catalystKnown)
        assert.equal(1, read.catalystCharges)
        assert.same({
            { name = "Placeholder Greater Crest", currencyID = 900003, quantity = 7 },
            { name = "Placeholder Crest", currencyID = 900001, quantity = 42 },
        }, read.crests)
    end)

    it("says a named crest the player does not carry is absent rather than zero", function()
        ns.Currencies.CREST_NAMES = { "Placeholder Crest", "Placeholder Crest Nobody Has" }
        local read = ns.Currencies.Read()
        assert.equal(1, #read.crests)
        assert.equal("Placeholder Crest", read.crests[1].name)
    end)

    it("leaves the Catalyst count nil when no candidate name is in the list", function()
        ns.Currencies.CATALYST_NAMES = { "Placeholder Charge That Is Not A Currency" }
        local read = ns.Currencies.Read()
        assert.is_true(read.catalystKnown)
        assert.is_nil(read.catalystCharges)
    end)

    it("never matches a header, whatever it is called", function()
        ns.Currencies.CREST_NAMES = { "Placeholder Group" }
        assert.same({}, ns.Currencies.Read().crests)
    end)

    it("drops a secret entry and counts it", function()
        world.currencies = { HEADER, world.secretTable("currency"), CHARGE }
        local read = ns.Currencies.Read()
        assert.is_true(read.ok)
        assert.equal(1, read.secretsSeen)
        assert.equal(2, #read.entries)
        assert.equal("Placeholder Charge", read.entries[2].name)
    end)

    describe("without a live client", function()
        local function capture()
            local result = ns.RunCapture("currencies")
            assert(result.ok, result.reason)
            return result.snapshot
        end

        it("falls back to the newest stored capture in combat", function()
            capture()
            world.currencies = { HEADER }
            local second = capture()
            world.inCombat = true
            local read = ns.Currencies.Read()
            assert.equal("capture", read.source)
            assert.equal(1, #read.entries)
            assert.equal(second, ns.Currencies.NewestSnapshot())
        end)

        it("refuses rather than inventing a list when nothing has ever been read", function()
            world.inCombat = true
            local read = ns.Currencies.Read()
            assert.is_false(read.ok)
            assert.equal("combat", read.reason)
        end)

        it("refuses on a client with no currency API and no capture", function()
            _G.C_CurrencyInfo = nil
            local read = ns.Currencies.Read()
            assert.is_false(read.ok)
            assert.equal("no currency list has been read yet", read.reason)
        end)

        it("reads a snapshot's list and takes a missing quantity from its info half", function()
            local snapshot = capture()
            -- The list half of the transcript says nothing about how many; the
            -- info half - GetCurrencyInfo, one call per non-header entry - does.
            snapshot.data.list[2][1].quantity = nil
            local read = ns.Currencies.Read({ snapshot = snapshot })
            assert.equal("capture", read.source)
            assert.equal(42, read.entries[2].quantity)
            ns.Currencies.CREST_NAMES = { "Placeholder Crest" }
            assert.equal(42, ns.Currencies.Read({ snapshot = snapshot }).crests[1].quantity)
        end)
    end)
end)
