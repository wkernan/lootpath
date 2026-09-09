-- spec/currencies_spec.lua (M3-9, WKE-544; by-ID reading M3-11, WKE-546)
--
-- Two kinds of test live here. The ones over `world.currencies` use
-- **placeholder** names and IDs in Blizzard's documented `CurrencyInfo` shape
-- (Ketho's `CurrencyInfoDocumentation.lua`: `name`, `description`,
-- `currencyID`, `isHeader`, `isHeaderExpanded`, `quantity`, `maxQuantity`, ...)
-- and pin the SHAPE of the read. The ones over
-- `spec/fixtures/captures/Lootpath-20260908-230426.lua` are the owner's real
-- client and pin real measured numbers.
--
-- What M3-11 pins above everything else: **an ID beats the list.** The client's
-- currency tab lists only the rows of expanded headers, so a currency the
-- player is holding can be missing from the list entirely; `GetCurrencyInfo(id)`
-- answers for it anyway, and `Read()` asks that first.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local HEADER = { name = "Placeholder Group", currencyID = 0, isHeader = true, isHeaderExpanded = true, quantity = 0 }
-- A header the player left collapsed: the real client lists no rows under one.
local COLLAPSED = {
    name = "Placeholder Collapsed Group",
    currencyID = 0,
    isHeader = true,
    isHeaderExpanded = false,
    quantity = 0,
}
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

    -- The IDs are the measured ones: 3442-3446 from the 2026-09-08 23:04
    -- transcript's "Crests" header, 3465 from the owner's Catalyst tooltip the
    -- same night ("Total Maximum: 1/8, CurrencyID 3465").
    it("ships knowing the five Mistcrests and the Catalyst charge by currency ID", function()
        assert.same({ crests = { 3442, 3443, 3444, 3445, 3446 }, catalyst = { 3465 } }, ns.Currencies.KNOWN_IDS)
        assert.same({ 3442, 3443, 3444, 3445, 3446, 3465 }, ns.Currencies.AllKnownIDs())
        assert.same({
            "Adventurer Mistcrest",
            "Veteran Mistcrest",
            "Champion Mistcrest",
            "Hero Mistcrest",
            "Myth Mistcrest",
        }, ns.Currencies.CREST_NAMES)
        assert.same({ "Venomblight Manaflux" }, ns.Currencies.CATALYST_NAMES)
        -- The wrong conclusion M3-9 shipped, gone rather than set false.
        assert.is_nil(ns.Currencies.CATALYST_NOT_A_CURRENCY)
        local read = ns.Currencies.Read()
        assert.is_true(read.ok)
        assert.is_true(read.crestsKnown)
        assert.is_true(read.catalystKnown)
    end)

    -- **The whole issue, as one test.** Every header is collapsed, so the list
    -- shows nothing at all - and the five crests and the Catalyst charge come
    -- back anyway, out of the by-ID probe, with the client's own names.
    it("reads the crests and the Catalyst out of a list whose headers are all collapsed", function()
        world.currencies = { COLLAPSED, COLLAPSED }
        world.currencyByID = {
            [3442] = { name = "Adventurer Mistcrest", currencyID = 3442, isHeader = false, quantity = 356 },
            [3445] = { name = "Hero Mistcrest", currencyID = 3445, isHeader = false, quantity = 21 },
            [3465] = {
                name = "Venomblight Manaflux",
                currencyID = 3465,
                isHeader = false,
                quantity = 1,
                maxQuantity = 8,
            },
        }
        local read = ns.Currencies.Read()
        assert.is_true(read.ok)
        assert.equal(2, #read.entries)
        assert.is_true(read.entries[1].isHeader)
        assert.is_false(read.entries[1].isHeaderExpanded)
        assert.same({
            { name = "Adventurer Mistcrest", currencyID = 3442, quantity = 356 },
            { name = "Hero Mistcrest", currencyID = 3445, quantity = 21 },
        }, read.crests)
        assert.equal(1, read.catalystCharges)
        assert.equal(8, read.catalystMax)
    end)

    -- The red proof for the ordering: the list and the probe answer two
    -- different numbers for the same currency, under the same name, and the
    -- probe is the one that is shown.
    it("prefers the ID probe over the list when both name the same currency", function()
        world.currencies = {
            HEADER,
            { name = "Adventurer Mistcrest", currencyID = 3442, isHeader = false, quantity = 1 },
        }
        world.currencyByID = {
            [3442] = { name = "Adventurer Mistcrest", currencyID = 3442, isHeader = false, quantity = 356 },
        }
        local read = ns.Currencies.Read()
        assert.same({ { name = "Adventurer Mistcrest", currencyID = 3442, quantity = 356 } }, read.crests)
    end)

    it("falls back to the list by name for an ID the client answers nothing for", function()
        world.currencies = {
            HEADER,
            { name = "Myth Mistcrest", currencyID = 3446, isHeader = false, quantity = 20 },
        }
        _G.C_CurrencyInfo.GetCurrencyInfo = function()
            return nil
        end
        local read = ns.Currencies.Read()
        assert.same({ { name = "Myth Mistcrest", currencyID = 3446, quantity = 20 } }, read.crests)
        assert.is_nil(read.catalystCharges)
    end)

    -- The 23:04 transcript predates the by-ID probe, so it is the "collapsed
    -- headers, no `byID`" case for good: the crests resolve out of the list's
    -- info half, and the Catalyst charge is genuinely unreadable from it.
    it("reads the owner's pre-M3-11 transcript: five Mistcrests by ID, and no Catalyst answer", function()
        local snapshot = R.snapshot("currencies", 2, "spec/fixtures/captures/Lootpath-20260908-230426.lua")
        assert.equal("2026-09-08T23:04:26", snapshot.capturedAtLocal)
        local read = ns.Currencies.Read({ snapshot = snapshot })
        assert.is_true(read.ok)
        assert.equal("capture", read.source)
        assert.equal(18, #read.entries)
        assert.is_nil(read.byID[3465])
        -- The finding that undid M3-9's conclusion: most of this list's headers
        -- were collapsed, so the eight currencies under the other two are all
        -- the tab could ever have shown.
        local headers, collapsed = 0, 0
        for _, entry in ipairs(read.entries) do
            if entry.isHeader then
                headers = headers + 1
                if not entry.isHeaderExpanded then
                    collapsed = collapsed + 1
                end
            end
        end
        assert.equal(10, headers)
        assert.equal(8, collapsed)
        assert.same({
            { name = "Adventurer Mistcrest", currencyID = 3442, quantity = 356 },
            { name = "Veteran Mistcrest", currencyID = 3443, quantity = 0 },
            { name = "Champion Mistcrest", currencyID = 3444, quantity = 2 },
            { name = "Hero Mistcrest", currencyID = 3445, quantity = 21 },
            { name = "Myth Mistcrest", currencyID = 3446, quantity = 20 },
        }, read.crests)
        assert.is_true(read.catalystKnown)
        assert.is_nil(read.catalystCharges)
        assert.is_nil(read.catalystMax)
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

        -- The combat path, and the path the owner's next transcript will take:
        -- the stored snapshot's `byID` half answers for a currency its list
        -- never showed, so a reload in combat reads the same charge count the
        -- live client would.
        it("reads the charge out of a stored snapshot's byID when the list showed nothing", function()
            world.currencies = { COLLAPSED }
            world.currencyByID = {
                [3465] = {
                    name = "Venomblight Manaflux",
                    currencyID = 3465,
                    isHeader = false,
                    quantity = 1,
                    maxQuantity = 8,
                },
            }
            capture()
            world.inCombat = true
            local read = ns.Currencies.Read()
            assert.equal("capture", read.source)
            assert.equal(1, #read.entries)
            assert.equal("Venomblight Manaflux", read.byID[3465].name)
            assert.equal(1, read.catalystCharges)
            assert.equal(8, read.catalystMax)
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
