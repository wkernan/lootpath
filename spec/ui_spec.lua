-- spec/ui_spec.lua (M2-2, WKE-520)
-- The window is driven through the stub's widget model: the frames are fake but
-- the wiring is the real code, so a click really reaches QEImport.Parse and a
-- refusal really reaches the status line. What a frame LOOKS like on the
-- owner's screen is an in-game step (M2-3) and is not claimed here.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
-- The widget stub itself, for the one figure a fit test needs: what a headless
-- font string says one character is worth (M5-2b, WKE-601).
local Stub = require("spec.stubs.wow")

local REAL_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"
local SAMPLE_EXPORT = "spec/fixtures/qe/sample-handbuilt-v1.json"

-- Something else entirely, put into a bag slot after the match was built, so a
-- test can say "the bags moved since the scan" (E-1, WKE-604). Nothing reads it
-- but the slot check, which compares it against the link the row carries.
local OTHER_ITEM_ID = 99999
local OTHER_LINK = "|cffa335ee|Hitem:99999::::::::80:105::::|h[Something Else]|h|r"

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function withInventory(world)
    R.inventory(world, R.snapshot("inventory", 1))
    world.bankOpen = true
end

local function firstSwapRow(panel)
    for _, row in ipairs(panel.rows) do
        if row.shown and row.matchRow and row.matchRow.status == "swap" then
            return row
        end
    end
    return nil
end

describe("UI.Toggle", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        withInventory(world)
    end)

    after_each(function()
        H.unload()
    end)

    it("opens on /lootpath and closes on the next one", function()
        assert.is_nil(ns.UI.frame)
        ns.HandleSlash("")
        assert.is_true(ns.UI.frame:IsShown())
        ns.HandleSlash("")
        assert.is_false(ns.UI.frame:IsShown())
    end)

    it("builds the frame once and gives it a global name so Escape can close it", function()
        local frame = ns.UI.Frame()
        assert.equal(frame, ns.UI.Frame())
        assert.equal("LootpathMainFrame", frame.frameName)
        assert.equal(_G.UISpecialFrames[#_G.UISpecialFrames], "LootpathMainFrame")
        assert.is_true(frame.movable)
    end)
end)

describe("the paste editbox", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("is a multi-line box with no letter limit", function()
        local box = ns.UI.frame.pasteBox
        assert.equal(0, box:GetMaxLetters())
        assert.is_true(box:IsMultiLine())
        assert.equal(ns.UI.PASTE_INSTRUCTIONS, ns.UI.frame.pasteLabel:GetText())
    end)

    it("carries a 200 KB string without truncating it", function()
        local size = 200 * 1024
        local big = string.rep("x", size - 1) .. "Z"
        local box = ns.UI.frame.pasteBox
        box:SetText(big)
        local out = box:GetText()
        assert.equal(size, #out)
        assert.equal(big, out)
        assert.equal("Z", out:sub(-1))
    end)

    it("hides the character counter, which counts down from the letter limit", function()
        -- InputScrollFrame_OnTextChanged writes GetMaxLetters() - GetNumLetters()
        -- into CharCount, which is a large negative number at maxLetters 0.
        assert.is_true(ns.UI.frame.pasteScroll.hideCharCount)
        assert.is_false(ns.UI.frame.pasteScroll.CharCount:IsShown())
    end)
end)

describe("the import status line", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("imports the genuine export through the button and names spec, content and count", function()
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        assert.is_true(ns.UI.frame.importButton:Click())
        local status = ns.UI.frame.status:GetText()
        assert.is_truthy(status:find("Restoration Druid", 1, true))
        assert.is_truthy(status:find("Raid", 1, true))
        assert.is_truthy(status:find("15 items", 1, true))
        assert.is_truthy(status:find("ago", 1, true) or status:find("just now", 1, true))
        assert.is_table(ns.QEImport.Current())
        assert.equal("cxeiassqdyvz", ns.QEImport.Current().reportId)
    end)

    it("shows the parser's refusal verbatim and stores nothing", function()
        ns.UI.frame.pasteBox:SetText("{ not json at all")
        ns.UI.frame.importButton:Click()
        local refusal = ns.QEImport.Parse("{ not json at all")
        assert.is_false(refusal.ok)
        assert.is_truthy(ns.UI.frame.status:GetText():find(refusal.reason, 1, true))
        assert.is_nil(ns.QEImport.Current())
    end)

    it("refuses an empty box with the parser's own words", function()
        ns.UI.frame.importButton:Click()
        assert.is_truthy(ns.UI.frame.status:GetText():find("nothing to import", 1, true))
    end)

    it("keeps the parser's warnings under the status line", function()
        -- The stub's player is "Tester" and the export is for "Hotornot".
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        assert.is_truthy(ns.UI.frame.status:GetText():find("Hotornot", 1, true))
    end)

    it("clears the box and the line", function()
        ns.UI.frame.pasteBox:SetText("rubbish")
        ns.UI.frame.importButton:Click()
        ns.UI.frame.clearButton:Click()
        assert.equal("", ns.UI.frame.pasteBox:GetText())
        assert.equal("", ns.UI.frame.status:GetText())
    end)
end)

-- A clock this test owns outright, so the assertions do not depend on the
-- timezone of whatever machine runs busted. `daysFromCivil` / `civilFromDays`
-- are Howard Hinnant's public-domain proleptic-Gregorian pair; the point is
-- only that they are an exact inverse of each other, which is what lets the
-- test install a machine at any UTC offset and check the answer is the same.
local function daysFromCivil(y, m, d)
    y = y - (m <= 2 and 1 or 0)
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function civilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    return y + (m <= 2 and 1 or 0), m, d
end

local function epochFromUTC(f)
    return daysFromCivil(f.year, f.month, f.day) * 86400 + (f.hour or 0) * 3600 + (f.min or 0) * 60 + (f.sec or 0)
end

local function utcFieldsOf(epoch)
    local days = math.floor(epoch / 86400)
    local rest = epoch - days * 86400
    local year, month, day = civilFromDays(days)
    return {
        year = year,
        month = month,
        day = day,
        hour = math.floor(rest / 3600),
        min = math.floor(rest % 3600 / 60),
        sec = rest % 60,
        isdst = false,
    }
end

-- Installs a client whose local clock sits `offsetSeconds` from UTC, the way
-- the owner's does: `time(fields)` reads its fields as LOCAL time and
-- `date("!*t", t)` writes UTC ones.
local function installClockAt(offsetSeconds)
    _G.time = function(fields)
        if fields == nil then
            return 0
        end
        return epochFromUTC(fields) - offsetSeconds
    end
    _G.date = function(format, t)
        assert(format == "!*t", "the age reader only ever asks for UTC fields")
        return utcFieldsOf(t)
    end
end

describe("UI.AgeText", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("reads QE Live's UTC timestamp whatever this machine's timezone is", function()
        -- 2026-09-06T21:14:24Z is the exportedAt of the committed export.
        local iso = "2026-09-06T21:14:24.465Z"
        local exportedAt = epochFromUTC({ year = 2026, month = 9, day = 6, hour = 21, min = 14, sec = 24 })
        -- UTC, the owner's US Eastern, and a half-hour offset that is nobody's
        -- rounding error. The age must not move with any of them.
        for _, offset in ipairs({ 0, -5 * 3600, 9.5 * 3600, 14 * 3600 }) do
            installClockAt(offset)
            assert.equal(0, ns.UI.AgeSeconds(iso, exportedAt))
            assert.equal(3600, ns.UI.AgeSeconds(iso, exportedAt + 3600))
            assert.equal("just now", ns.UI.AgeText(iso, exportedAt))
            assert.equal("30 seconds ago", ns.UI.AgeText(iso, exportedAt + 30))
            assert.equal("10 minutes ago", ns.UI.AgeText(iso, exportedAt + 600))
            assert.equal("3 hours ago", ns.UI.AgeText(iso, exportedAt + 3 * 3600))
            assert.equal("4 days ago", ns.UI.AgeText(iso, exportedAt + 4 * 86400))
            -- One of anything is singular, which is the whole of the rule the
            -- "(s)" was standing in for (R-2a, WKE-571). The bands above never
            -- produce a 1 - the minute band runs to 90 minutes and each band
            -- rounds into the next at 1.5 - so the rule is asserted where it
            -- lives rather than through a moment that cannot happen.
            assert.equal("1 hour", ns.UI.Plural(1, "hour"))
            assert.equal("4 hours", ns.UI.Plural(4, "hour"))
            assert.equal("0 days", ns.UI.Plural(0, "day"))
        end
    end)

    it("shows the string unchanged rather than guessing at one it cannot read", function()
        assert.is_nil(ns.UI.AgeSeconds("last Tuesday"))
        assert.equal("last Tuesday", ns.UI.AgeText("last Tuesday"))
        assert.equal("at an unknown time", ns.UI.AgeText(nil))
    end)
end)

describe("the Equip Now panel", function()
    local ns, world, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        panel = ns.UI.frame.equipPanel
    end)

    after_each(function()
        H.unload()
    end)

    -- M5-1b (WKE-610): the rows that need something are drawn first and at full
    -- weight; the already-best rows are one folded line until the caret is
    -- clicked, and then they follow it. The slot word is on the row's second
    -- line - there is no slot column to read it out of any more.
    it("draws the rows that need something, folds the rest, and opens them on the caret", function()
        assert.equal(15, #panel.match.rows)
        local needs, best = {}, {}
        for _, matchRow in ipairs(panel.match.rows) do
            if matchRow.status == "equipped_is_best" then
                best[#best + 1] = matchRow
            else
                needs[#needs + 1] = matchRow
            end
        end
        assert.is_true(#needs > 0 and #best > 0)

        for i, matchRow in ipairs(needs) do
            local frameRow = panel.rows[i]
            assert.is_true(frameRow.shown)
            assert.equal(matchRow, frameRow.matchRow)
            assert.is_truthy(frameRow.line.second:GetText():find(matchRow.slot, 1, true))
        end
        assert.is_false(panel.rows[#needs + 1] and panel.rows[#needs + 1].shown or false)
        assert.is_true(panel.fold:IsShown())
        assert.is_truthy(panel.fold.text:GetText():find(ns.UI.EquipPanel.FoldText(#best, 15), 1, true))
        assert.is_truthy(panel.fold.text:GetText():find(ns.UI.EquipPanel.FOLD_SHUT_MARK, 1, true))

        assert.is_true(panel.fold:Click())
        assert.is_truthy(panel.fold.text:GetText():find(ns.UI.EquipPanel.FOLD_OPEN_MARK, 1, true))
        for i, matchRow in ipairs(best) do
            local frameRow = panel.rows[#needs + i]
            assert.is_true(frameRow.shown)
            assert.equal(matchRow, frameRow.matchRow)
            -- Nothing but the slot word: the tick has said the rest.
            assert.equal(matchRow.slot, frameRow.line.second:GetText())
        end
        assert.is_false(panel.overflow:IsShown())

        -- and it is remembered per character, the way the Upgrade Map's
        -- sections are
        assert.is_true(ns.UI.EquipPanel.FoldOpen(ns.db))
        assert.is_true(ns.db.char.equipNow.bestOpen)
        assert.is_true(panel.fold:Click())
        assert.is_false(ns.UI.EquipPanel.FoldOpen(ns.db))
        assert.is_nil(ns.db.char.equipNow.bestOpen)
    end)

    it("summarises the counts and puts the Equip button only on swap rows", function()
        -- The counts are the bar's key above the list (M5-1b); the text model
        -- `/lootpath status` reads still says all five, unchanged.
        local chips = ns.UI.EquipPanel.Chips(panel.match)
        assert.equal(5, #chips)
        assert.equal("equipped_is_best", chips[1].key)
        assert.is_truthy(panel.barKey:GetText():find("already best", 1, true))
        assert.is_truthy(ns.UI.EquipPanel.SummaryText(panel.match):find("already best", 1, true))
        ns.UI.EquipPanel.ToggleFold(ns.db)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        local swapButtons, otherButtons = 0, 0
        for i = 1, #panel.match.rows do
            local frameRow = panel.rows[i]
            if frameRow.matchRow.status == "swap" then
                assert.is_true(frameRow.equip:IsShown())
                assert.is_true(frameRow.equip:IsEnabled())
                swapButtons = swapButtons + 1
            else
                assert.is_false(frameRow.equip:IsShown())
                otherButtons = otherButtons + 1
            end
        end
        assert.equal(panel.match.counts.swap, swapButtons)
        assert.is_true(swapButtons > 0 and otherButtons > 0)
    end)

    -- E-1 (WKE-604): the copy, not the name. Two of the same item in the bags
    -- and `C_Item.EquipItemByName` puts on whichever the client finds first, so
    -- every one of these asserts the BAG AND SLOT the scan recorded.
    it("equips the copy the row means, by its bag and slot, and never by name", function()
        local row = firstSwapRow(panel)
        assert.is_table(row)
        local best = row.matchRow.best
        assert.equal("bag", best.location)
        assert.is_true(row.equip:Click())
        assert.equal(0, #world.equipCalls)
        assert.equal(1, #world.pickupCalls)
        assert.same({ best.bag, best.slotIndex, best.link }, world.pickupCalls[1])
        assert.equal(1, #world.equipCursorCalls)
        assert.equal(row.matchRow.equipped.slotIndex, world.equipCursorCalls[1].slot)
        assert.equal(best.link, world.equipCursorCalls[1].link)
        -- Cleared before the pickup, the way Blizzard's own EquipmentManager
        -- opens, and holding nothing afterwards.
        assert.is_true(world.clearCursorCalls >= 1)
        assert.is_nil(world.heldItem)
    end)

    it("refuses when the bags moved under the scan, says so on the row, and holds nothing", function()
        local row = firstSwapRow(panel)
        local best = row.matchRow.best
        world.bags[best.bag].items[best.slotIndex] = {
            link = OTHER_LINK,
            id = OTHER_ITEM_ID,
            info = { hyperlink = OTHER_LINK, itemID = OTHER_ITEM_ID },
        }
        assert.is_true(row.equip:Click())
        assert.equal(0, #world.pickupCalls)
        assert.equal(0, #world.equipCursorCalls)
        assert.equal(0, #world.equipCalls)
        assert.is_nil(world.heldItem)
        assert.is_true(world.clearCursorCalls >= 1)
        assert.is_truthy(row.note:GetText():find(ns.UI.EquipPanel.MOVED_NOTE, 1, true))
        assert.is_true(row.note:IsShown())
    end)

    it("equips every swap row at once, each by its own bag and slot, and no other row", function()
        assert.is_true(panel.equipAll:IsShown())
        panel.equipAll:Click()
        assert.equal(0, #world.equipCalls)
        assert.equal(panel.match.counts.swap, #world.pickupCalls)
        assert.equal(panel.match.counts.swap, #world.equipCursorCalls)
        local wanted = {}
        for _, matchRow in ipairs(panel.match.rows) do
            if matchRow.status == "swap" then
                wanted[matchRow.best.link] = { matchRow.best.bag, matchRow.best.slotIndex, matchRow.dstSlot }
            end
        end
        for index, call in ipairs(world.equipCursorCalls) do
            local want = wanted[call.link]
            assert.is_truthy(want ~= nil)
            assert.same({ want[1], want[2], call.link }, world.pickupCalls[index])
            assert.equal(want[3], call.slot)
        end
    end)

    it("stops Equip all at the first row whose slot moved, with the refusal on that row", function()
        local row = firstSwapRow(panel)
        local best = row.matchRow.best
        world.bags[best.bag].items[best.slotIndex] = {
            link = OTHER_LINK,
            id = OTHER_ITEM_ID,
            info = { hyperlink = OTHER_LINK, itemID = OTHER_ITEM_ID },
        }
        assert.is_true(panel.match.counts.swap > 1)
        panel.equipAll:Click()
        assert.equal(0, #world.pickupCalls)
        assert.equal(0, #world.equipCursorCalls)
        assert.equal(0, #world.equipCalls)
        assert.is_truthy(row.note:GetText():find(ns.UI.EquipPanel.MOVED_NOTE, 1, true))
    end)

    it("never calls EquipItemByName at all", function()
        -- E-1a (WKE-605) flips E-1's guard. E-1 let one by-name call survive
        -- for a row with no destination slot; now every equippable row has one,
        -- so the CALL SITE must be gone from this file entirely - a line whose
        -- first non-blank is `C_Item.EquipItemByName(`. A comment naming the
        -- function would not be a call, and there is not one of either.
        local source = readFile("Lootpath/UI/EquipPanel.lua")
        local _, byName = source:gsub("\n[ \t]*C_Item%.EquipItemByName%(", "")
        assert.equal(0, byName)
        assert.is_nil(source:find("EquipItemByName", 1, true))
        assert.is_truthy(source:find("\n    EquipCursorItem(row.dstSlot)", 1, true))
        -- The guard that refuses a record with no bag slot to pick up from.
        assert.is_truthy(source:find('(best.location == "bag" or best.location == "bank")', 1, true))
    end)

    -- E-1a (WKE-605): the owner's legs slot was EMPTY, both leggings were in
    -- the bags, and Equip all put on the 295 - the one case E-1 left on the
    -- by-name path. `dstSlot` is the scanned slot of the item being REPLACED
    -- (Match.lua:259), so an empty slot has none; these ask the client where
    -- the copy goes instead. `world.slotsForItem` is the client's answer, and
    -- nothing here asserts that a particular item belongs in a particular slot.
    local function emptySlotRow(slots)
        local source = firstSwapRow(panel)
        assert.is_table(source)
        local best = source.matchRow.best
        for _, invSlot in ipairs(slots) do
            world.equipped[invSlot] = nil
        end
        world.slotsForItem[best.link] = slots
        return { slot = source.matchRow.slot, status = "swap", best = best, dstSlot = nil }
    end

    it("equips an empty slot into the slot the client names for that copy, never by name", function()
        -- Legs, the owner's own case: nothing worn, one slot offered.
        local row = emptySlotRow({ 7 })
        local best = row.best
        -- A SECOND copy of the same link elsewhere in the bags, which is what
        -- made the by-name path put on the wrong one.
        world.bags[best.bag].items[best.slotIndex + 40] = {
            link = best.link,
            id = best.itemID,
            info = { hyperlink = best.link, itemID = best.itemID },
        }
        local result = ns.UI.EquipPanel.Equip(row)
        assert.is_true(result.ok)
        assert.equal(7, row.dstSlot)
        assert.equal(0, #world.equipCalls)
        assert.equal(1, #world.pickupCalls)
        assert.same({ best.bag, best.slotIndex, best.link }, world.pickupCalls[1])
        assert.equal(1, #world.equipCursorCalls)
        assert.equal(7, world.equipCursorCalls[1].slot)
        assert.equal(best.slotIndex, world.equipCursorCalls[1].slotIndex)
        assert.is_nil(world.heldItem)
    end)

    it("puts a ring in the empty one of the two finger slots the client offers", function()
        local row = emptySlotRow({ 11, 12 })
        -- Finger1 worn, Finger2 empty: the client offers both, only one is free.
        world.equipped[11] = { link = OTHER_LINK, id = OTHER_ITEM_ID }
        assert.is_true(ns.UI.EquipPanel.Equip(row).ok)
        assert.equal(12, row.dstSlot)
        assert.equal(12, world.equipCursorCalls[1].slot)
        assert.equal(0, #world.equipCalls)
    end)

    it("takes the other finger slot when that is the empty one", function()
        local row = emptySlotRow({ 11, 12 })
        world.equipped[12] = { link = OTHER_LINK, id = OTHER_ITEM_ID }
        assert.is_true(ns.UI.EquipPanel.Equip(row).ok)
        assert.equal(11, row.dstSlot)
        assert.equal(11, world.equipCursorCalls[1].slot)
    end)

    it("sends a two-hander to the main hand when the client offers both hands", function()
        -- INVSLOT_MAINHAND 16, INVSLOT_OFFHAND 17 (Constants.lua:168-169). A
        -- client that offers a two-hander for both is a Titan's Grip warrior;
        -- with both free the main hand is the one that comes first.
        local row = emptySlotRow({ 16, 17 })
        assert.is_true(ns.UI.EquipPanel.Equip(row).ok)
        assert.equal(16, row.dstSlot)
        assert.equal(16, world.equipCursorCalls[1].slot)
        assert.equal(0, #world.equipCalls)
    end)

    it("refuses in one sentence when the client names no slot for the item", function()
        local row = emptySlotRow({})
        local result = ns.UI.EquipPanel.Equip(row)
        assert.is_false(result.ok)
        assert.equal(ns.UI.EquipPanel.UNMAPPABLE_NOTE, result.reason)
        assert.equal(ns.UI.EquipPanel.UNMAPPABLE_NOTE, row.equipRefusal)
        assert.is_nil(row.dstSlot)
        assert.equal(0, #world.pickupCalls)
        assert.equal(0, #world.equipCursorCalls)
        assert.equal(0, #world.equipCalls)
        assert.is_nil(world.heldItem)
    end)

    it("takes an empty-slot row through Equip all by location too, and stops at one it cannot place", function()
        local placed = emptySlotRow({ 7 })
        -- A second row of its own, in a bag slot the client offers for nothing,
        -- so Equip all's per-row path is what is read and the panel's own rows
        -- are untouched.
        local unplaceable = {
            slot = "Finger",
            status = "swap",
            best = {
                location = "bag",
                link = OTHER_LINK,
                itemID = OTHER_ITEM_ID,
                bag = placed.best.bag,
                slotIndex = 99,
            },
            dstSlot = nil,
        }
        local result = ns.UI.EquipPanel.EquipAll({ ok = true, rows = { placed, unplaceable } })
        assert.is_true(result.ok)
        assert.equal(1, result.equipped)
        assert.equal(7, world.equipCursorCalls[1].slot)
        assert.equal(0, #world.equipCalls)
        assert.same({ ns.UI.EquipPanel.UNMAPPABLE_NOTE }, result.refusals)
        assert.equal(unplaceable, result.stoppedAt)
    end)

    it("says what it is showing per row", function()
        local head = panel.match.bySlot["Head"][1]
        assert.is_truthy(ns.UI.EquipPanel.Describe(head).text:find("already equipped", 1, true))
        local feet = panel.match.bySlot["Feet"][1]
        local described = ns.UI.EquipPanel.Describe(feet)
        assert.is_false(described.actionable)
        assert.is_truthy(described.text:find("not found", 1, true))
        assert.is_truthy(described.text:find("251153", 1, true))
    end)

    -- WKE-541: the reason a row is what it is is a sentence, and the detail
    -- line does not wrap, so the frame used to cut it off mid-word. It goes on
    -- its own line under the row instead.
    it("puts a not-owned reason on its own line and not off the edge of the first", function()
        local feet = panel.match.bySlot["Feet"][1]
        local described = ns.UI.EquipPanel.Describe(feet)
        assert.is_truthy(described.note:find(feet.reason, 1, true))
        assert.is_falsy(described.text:find(feet.reason, 1, true))

        local frameRow
        for _, candidate in ipairs(panel.rows) do
            if candidate.matchRow == feet then
                frameRow = candidate
            end
        end
        assert.is_table(frameRow)
        assert.is_true(frameRow.note:IsShown())
        assert.is_truthy(frameRow.note:GetText():find(feet.reason, 1, true))
        -- Neither line of the item line carries the sentence: the name is the
        -- item's, the second line is QE Live's level, the note is the reason.
        assert.is_falsy(frameRow.line.name:GetText():find(feet.reason, 1, true))
        assert.is_falsy(frameRow.line.second:GetText():find(feet.reason, 1, true))
        assert.equal(ns.UI.EquipPanel.RowHeight(true), frameRow:GetHeight())
    end)

    it("gives every note line the frame's width rather than a number of its own", function()
        local frameRow = panel.rows[1]
        -- Never SetWidth: the note's right-hand end is the row's, so it is as
        -- wide as the frame is at whatever size the frame is. Its LEFT is the
        -- line's since M5-1c (WKE-617) - the sentence belongs to the item above
        -- it - which narrows it by the pair inset and never by a number here.
        assert.equal(0, frameRow.note:GetWidth())
        assert.is_true(frameRow.note.wordWrap)
        local anchors = {}
        for _, point in ipairs(frameRow.note.points) do
            anchors[point[1]] = point[2]
        end
        assert.equal(frameRow.line, anchors["TOPLEFT"])
        assert.equal(frameRow, anchors["RIGHT"])
        -- The item line's own two lines still do not wrap: they are one line
        -- each by design, and everything long about a row lives on the note.
        assert.is_false(frameRow.line.name.wordWrap)
        assert.is_false(frameRow.line.second.wordWrap)
    end)

    it("takes a row back to one line when its note goes away", function()
        local feet, head
        -- The already-best rows are behind the fold by default (M5-1b), and
        -- this is about a frame that is RECYCLED from one row to another, so
        -- both kinds have to be drawn.
        ns.UI.EquipPanel.ToggleFold(ns.db)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.matchRow and frameRow.matchRow.status == "best_not_owned" then
                feet = feet or frameRow
            elseif frameRow.matchRow and frameRow.matchRow.status == "equipped_is_best" then
                head = head or frameRow
            end
        end
        assert.is_table(feet)
        assert.is_table(head)
        assert.equal(ns.UI.EquipPanel.RowHeight(false), head:GetHeight())
        assert.is_false(head.note:IsShown())
        assert.equal("", head.note:GetText())
        -- Frames are reused across refreshes: a note left on a recycled row
        -- would attach one row's sentence to another row's item.
        -- Held before the refresh: Refresh reassigns every frame row's matchRow,
        -- and these two frames are the ones it is about to hand new rows to.
        local feetRow, headRow = feet.matchRow, head.matchRow
        ns.UI.EquipPanel.Refresh(panel, { ok = true, rows = { feetRow, headRow }, counts = panel.match.counts })
        assert.equal(ns.UI.EquipPanel.RowHeight(true), panel.rows[1]:GetHeight())
        ns.UI.EquipPanel.Refresh(panel, { ok = true, rows = { headRow }, counts = panel.match.counts })
        assert.equal(ns.UI.EquipPanel.RowHeight(false), panel.rows[1]:GetHeight())
        assert.is_false(panel.rows[1].note:IsShown())
    end)

    it("shows nothing to equip before anything is imported", function()
        H.unload()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
        ns.UI.Refresh()
        local fresh = ns.UI.frame.equipPanel
        -- The answer line carries it: before an import there is no answer for a
        -- quiet note to be a condition on, so the prompt IS the answer and the
        -- hint icon stays down (M5-1b).
        assert.is_truthy(fresh.answer:GetText():find("Paste a Top Gear", 1, true))
        assert.is_false(fresh.hint:IsShown())
        assert.is_false(fresh.equipAll:IsShown())
    end)
end)

-- M5-1c (WKE-617): the owner's screenshot on WKE-592 had the red not-owned
-- sentence printed ON TOP of the row's second line on all eight not-owned rows.
-- The note started at a constant 38 from the row's top while the item line
-- started BELOW that top - the arrow layout anchored it to the arrow's own top
-- plus 6 - so 34 points of icon ran past the constant. The note hangs off the
-- line now, and the row is as tall as the line plus the note.
describe("an Equip Now row's note and its real height (M5-1c)", function()
    local ns, world, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        world.bankOpen = false
        ns.UI.Frame()
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        panel = ns.UI.frame.equipPanel
        -- The settled rows are behind the fold by default (M5-1b); this is
        -- about every shape of row, so they are all on screen.
        ns.UI.EquipPanel.ToggleFold(ns.db)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
    end)

    after_each(function()
        H.unload()
    end)

    local function pointNamed(frame, name)
        for _, point in ipairs(frame.points) do
            if point[1] == name then
                return point
            end
        end
        return nil
    end

    -- Where a row's line begins and ends, in the row's own coordinates: the top
    -- is negative and down is more negative, which is how the client reads an
    -- offset from a TOPLEFT anchor. Resolved from the stub's recorded points
    -- rather than assumed, so an anchor moved anywhere else fails here.
    local function lineSpan(row)
        local point = pointNamed(row.line, "TOPLEFT")
        assert.is_table(point)
        assert.equal(row, point[2])
        assert.equal("TOPLEFT", point[3])
        local top = point[5]
        return top, top - row.line:GetHeight()
    end

    local function noteTop(row)
        local point = pointNamed(row.note, "TOPLEFT")
        assert.is_table(point)
        assert.equal(row.line, point[2])
        assert.equal("BOTTOMLEFT", point[3])
        local _, bottom = lineSpan(row)
        return bottom + point[5], bottom
    end

    local function rowsByShape()
        local paired, plain, noted
        for _, row in ipairs(panel.rows) do
            if row.shown then
                if row.worn:IsShown() then
                    paired = paired or row
                else
                    plain = plain or row
                end
                if row.note:IsShown() then
                    noted = noted or row
                end
            end
        end
        return paired, plain, noted
    end

    it("starts the item line at the row's own top in both layouts", function()
        local paired, plain = rowsByShape()
        assert.is_table(paired)
        assert.is_table(plain)
        -- One vertical rule. A pair moves the line sideways and nothing else:
        -- the inset is the worn icon, the arrow and the gaps around them.
        local pairedPoint = pointNamed(paired.line, "TOPLEFT")
        local plainPoint = pointNamed(plain.line, "TOPLEFT")
        assert.equal(paired, pairedPoint[2])
        assert.equal(plain, plainPoint[2])
        assert.equal(-ns.UI.EquipPanel.LINE_TOP, pairedPoint[5])
        assert.equal(-ns.UI.EquipPanel.LINE_TOP, plainPoint[5])
        assert.equal(ns.UI.EquipPanel.PAIR_INSET, pairedPoint[4])
        assert.equal(0, plainPoint[4])
        assert.equal(46, ns.UI.EquipPanel.PAIR_INSET)
        -- And the worn icon is centred on the line's icon, which is the same
        -- picture read from the other end.
        local worn = pointNamed(paired.worn, "TOPLEFT")
        assert.equal(paired, worn[2])
        assert.equal(
            -(ns.UI.EquipPanel.LINE_TOP + (ns.UI.ItemLine.ICON_SIZE - ns.UI.EquipPanel.WORN_ICON_SIZE) / 2),
            worn[5]
        )
    end)

    it("begins a swap-shaped row's note under the line, not over its second line", function()
        local paired = select(1, rowsByShape())
        assert.is_table(paired)
        local top, bottom = noteTop(paired)
        assert.equal(-ns.UI.EquipPanel.LINE_TOP - paired.line:GetHeight(), bottom)
        assert.is_true(top <= bottom)
        assert.equal(bottom - ns.UI.EquipPanel.NOTE_GAP, top)
        -- What the screenshot was: at the old constant the note began 38 points
        -- down, which is above where a line that starts at the row's top ends
        -- once the arrow layout has pushed it further down still.
        assert.is_true(top < -ns.UI.EquipPanel.ROW_HEIGHT)
        assert.equal(-40, top)
    end)

    it("begins a plain row's note under the line too", function()
        local plain = select(2, rowsByShape())
        assert.is_table(plain)
        local top, bottom = noteTop(plain)
        assert.is_true(top <= bottom)
        assert.equal(-40, top)
    end)

    it("is as tall as the line plus the note when a note is drawn", function()
        local _, _, noted = rowsByShape()
        assert.is_table(noted)
        assert.equal(36, ns.UI.ItemLine.Height())
        assert.equal(noted.line:GetHeight(), ns.UI.ItemLine.Height())
        local expected = ns.UI.EquipPanel.LINE_TOP
            + noted.line:GetHeight()
            + ns.UI.EquipPanel.NOTE_GAP
            + ns.UI.EquipPanel.NOTE_HEIGHT
        assert.equal(expected, noted:GetHeight())
        assert.equal(56, noted:GetHeight())
        -- The note really does fit inside the row it made taller.
        local top = noteTop(noted)
        assert.is_true(top - ns.UI.EquipPanel.NOTE_HEIGHT >= -noted:GetHeight())
    end)

    it("leaves a row without a note at the height it always was", function()
        local _, plain = rowsByShape()
        assert.is_table(plain)
        assert.is_false(plain.note:IsShown())
        assert.equal(ns.UI.EquipPanel.ROW_HEIGHT, plain:GetHeight())
        assert.equal(38, plain:GetHeight())
        -- The constant the rows are BUILT at is the measured height of a row
        -- with no note, so the two can never drift apart unnoticed.
        assert.equal(ns.UI.EquipPanel.RowHeight(false), ns.UI.EquipPanel.ROW_HEIGHT)
    end)

    it("makes the list as tall as the rows it drew", function()
        local sum = 0
        for _, row in ipairs(panel.rows) do
            if row.shown then
                sum = sum + row:GetHeight() + ns.UI.EquipPanel.ROW_GAP
            end
        end
        if panel.fold:IsShown() then
            sum = sum + panel.fold:GetHeight() + ns.UI.EquipPanel.ROW_GAP
        end
        if panel.overflow:IsShown() then
            sum = sum + ns.UI.EquipPanel.OVERFLOW_GAP + ns.UI.EquipPanel.NOTE_HEIGHT
        end
        assert.equal(sum, panel.list:GetHeight())
        -- The two notes on this character's set are what the list gained over
        -- a set of fifteen plain rows and the fold line.
        assert.equal(656, panel.list:GetHeight())
    end)
end)

-- M5-1a (WKE-597): the owner's Equip Now was cut off at the top - no Head row
-- and a half-drawn Shoulder row under the bank hint. Two readings were open;
-- the stub answered them before anything was built. The scroll frame's top
-- anchor and the first row's anchor are IDENTICAL with the note line empty and
-- with it full, so the note's own height cannot move a row inside the list -
-- but nothing ever cleared the scroll offset, and an offset set before a
-- refresh survived it, which is reading 1. Blizzard's own
-- `ScrollFrame_OnScrollRangeChanged` clamps the bar to the new range rather
-- than clearing it (SecureScrollTemplates.lua:64, in Ketho's annotations), and
-- `UIPanelScrollBar_OnValueChanged` pushes the bar's value back into
-- `SetVerticalScroll` (:22) - so the bar is cleared as well as the frame.
describe("the Equip Now list's top (M5-1a)", function()
    local ns, world, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        world.bankOpen = false
        ns.UI.Frame()
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        panel = ns.UI.frame.equipPanel
    end)

    after_each(function()
        H.unload()
    end)

    local function topAnchor(frame)
        for _, point in ipairs(frame.points) do
            if point[1] == "TOPLEFT" then
                return point
            end
        end
        return nil
    end

    it("hangs the list under the bar's key, which is the last thing the header says", function()
        assert.is_true(panel.barKey:GetText() ~= "")
        local point = topAnchor(panel.scroll)
        assert.equal(panel.barKey, point[2])
        assert.equal("BOTTOMLEFT", point[3])
        assert.equal(-ns.UI.EquipPanel.TOP_GAP, point[5])
    end)

    -- M5-1b (WKE-610) settles M5-1a's fault at the other end: the bank hint is
    -- an icon under the list now, not a line above it, so whether this
    -- character's bank happens to be open cannot move the list's top at all.
    it("puts the list's top in the same place whether there is a hint or not", function()
        local shut = topAnchor(panel.scroll)
        assert.is_truthy(ns.UI.EquipPanel.NoteText(panel.match):find("bank closed", 1, true))
        assert.is_true(panel.hint:IsShown())

        world.bankOpen = true
        ns.UI.Refresh()
        assert.equal("", ns.UI.EquipPanel.NoteText(panel.match))
        assert.is_false(panel.hint:IsShown())
        local open = topAnchor(panel.scroll)
        assert.equal(shut[2], open[2])
        assert.equal(shut[3], open[3])
        assert.equal(shut[5], open[5])
        -- And the first row is still at the very top of the list either way:
        -- where the rows sit inside the list never depended on the note.
        local row = topAnchor(panel.rows[1])
        assert.equal(panel.list, row[2])
        assert.equal("TOPLEFT", row[3])
        assert.equal(0, row[5])
    end)

    it("starts a new row set at its first row, frame and bar both", function()
        panel.scroll.ScrollBar:SetValue(60)
        assert.equal(60, panel.scroll.verticalScroll)
        local rows = panel.match.rows
        assert.is_true(#rows > 2)
        ns.UI.EquipPanel.Refresh(panel, { ok = true, rows = { rows[2] }, counts = panel.match.counts })
        assert.equal(0, panel.scroll.verticalScroll)
        -- The bar too: the template clamps ITS value to the new range on the
        -- next resize and pushes it straight back into the frame, so a frame
        -- scrolled to 0 over a bar still holding 60 does not stay at 0.
        assert.equal(0, panel.scroll.ScrollBar:GetValue())
    end)

    it("keeps where the player had scrolled to when the same rows are drawn again", function()
        panel.scroll.ScrollBar:SetValue(60)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        assert.equal(60, panel.scroll.verticalScroll)
        assert.equal(60, panel.scroll.ScrollBar:GetValue())
    end)

    it("reads a row set by its slots and its rated items, not by what is worn", function()
        local rows = panel.match.rows
        local before = ns.UI.EquipPanel.RowSignature(panel.match)
        -- The same rows with every status flipped: a bag update or an equip is
        -- not a different list.
        local same = { ok = true, rows = {}, counts = panel.match.counts }
        for index, row in ipairs(rows) do
            local copy = {}
            for key, value in pairs(row) do
                copy[key] = value
            end
            copy.status = "equipped_is_best"
            same.rows[index] = copy
        end
        assert.equal(before, ns.UI.EquipPanel.RowSignature(same))
        assert.is_true(ns.UI.EquipPanel.RowSignature({ ok = true, rows = { rows[1] } }) ~= before)
        assert.equal("none", ns.UI.EquipPanel.RowSignature(nil))
    end)

    it("opens the tab at the top after the player scrolled down and left it", function()
        panel.scroll.ScrollBar:SetValue(60)
        ns.UI.SelectTab(ns.UI.frame, 2)
        assert.equal(60, panel.scroll.verticalScroll)
        ns.UI.SelectTab(ns.UI.frame, 1)
        assert.equal(0, panel.scroll.verticalScroll)
        assert.equal(0, panel.scroll.ScrollBar:GetValue())
    end)
end)

-- WKE-541 (M2-4): the row the owner saw on his first day. The 2026-09-08
-- inventory snapshot `/lootpath refresh` took at 12:45:26 (snapshot 7) joined
-- to the export the companion wrote from it, which put the Great Vault's
-- Lightgrasp Worldroot at rated at 321 in the top set while the owner
-- was wearing the 305 copy. The tab used to render that as a red failed swap
-- with the explanation running off the frame; it is now the staff he wears,
-- with a line underneath naming the vault option and the tab that shows it.
describe("the Equip Now panel on a Great Vault option in the top set (WKE-541)", function()
    local ns, world, panel
    local AFTER_RESET = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local VAULT_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-uliwcyoomcub.json"
    local WEAPON_ID = 251935
    local EXPECTED_NOTE = "Your best set has a Great Vault option in this slot: "
        .. "Lightgrasp Worldroot (rated at 321) - see the Vault tab"

    local function vaultRow()
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.matchRow and frameRow.matchRow.status == "best_in_vault" then
                return frameRow
            end
        end
        return nil
    end

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", 7, AFTER_RESET))
        -- C_Item.GetItemInfo takes an itemID as well as a link (Blizzard's
        -- exported docs), which is the form the panel uses because QE Live
        -- names an item by id and never by link. The stub answers whatever it
        -- was given, so the id is registered here with the name the transcript
        -- carries on the equipped copy of the same staff.
        world.items[WEAPON_ID] = { info = { "Lightgrasp Worldroot", n = 1 } }
        ns.UI.Frame()
        ns.UI.frame.pasteBox:SetText(readFile(VAULT_EXPORT))
        ns.UI.frame.importButton:Click()
        panel = ns.UI.frame.equipPanel
    end)

    after_each(function()
        H.unload()
    end)

    it("shows the staff he is wearing instead of a swap that failed", function()
        local frameRow = vaultRow()
        assert.is_table(frameRow)
        -- One item line, no pair: nothing is being swapped for anything. The
        -- slot word is on the second line now that the column is gone, and
        -- beside it the level the rating used, which is the number the reader
        -- is about to compare with what he wears (M5-1b).
        assert.is_truthy(frameRow.line.name:GetText():find("Lightgrasp Worldroot", 1, true))
        assert.is_truthy(frameRow.line.second:GetText():find("2H Weapon", 1, true))
        assert.is_truthy(frameRow.line.second:GetText():find("rated at 321", 1, true))
        assert.is_falsy(frameRow.line.second:GetText():find("already equipped", 1, true))
        assert.is_false(frameRow.worn:IsShown())
        assert.is_false(frameRow.arrow:IsShown())
        assert.is_false(frameRow.arrowText:IsShown())
        assert.equal("", frameRow.line.badge:GetText())
        -- The vault mark, in the fixed column, and the verb that goes to the
        -- tab where the reward can be acted on.
        assert.is_true(frameRow.line.mark:IsShown())
        assert.equal(ns.UI.EquipPanel.VAULT_ATLAS, frameRow.line.mark.atlas)
        assert.is_true(frameRow.vault:IsShown())
        assert.equal(ns.UI.EquipPanel.VAULT_VERB, frameRow.vault:GetText())
        frameRow.vault:Click()
        assert.equal(ns.UI.VAULT_TAB, ns.UI.frame.selectedTab)
        ns.UI.ShowTab(ns.UI.frame, 1)
        -- And QE Live's own word for what is waiting there, in his colour.
        assert.is_truthy(frameRow.line.tags:GetText():find("Vault", 1, true))
        assert.is_truthy(frameRow.line.tags:GetText():find(ns.UI.ItemLine.TAG.vault.hex, 1, true))
        assert.is_truthy(ns.UI.EquipPanel.Describe(frameRow.matchRow).text:find("already equipped", 1, true))
    end)

    -- The text model still says the whole sentence, word for word - that is
    -- what `/lootpath status` and the text tests read, and M5-1b left it alone.
    -- What changed is the DRAWN row: the mark says where the item is, the
    -- second line carries the level the rating used, and the verb goes to the
    -- tab that shows it, so a sentence repeating all three came off the screen
    -- (WKE-598's canvas, the owner's answer 1).
    it("keeps the vault sentence in the text model and says it in three marks on screen", function()
        local frameRow = vaultRow()
        local described = ns.UI.EquipPanel.Describe(frameRow.matchRow)
        assert.is_truthy(described.note:find(EXPECTED_NOTE, 1, true))
        assert.is_truthy(described.note:find(ns.UI.EquipPanel.NOTE_COLOR, 1, true))
        assert.equal(EXPECTED_NOTE, ns.UI.EquipPanel.VaultNoteText(frameRow.matchRow.verdictItem))

        assert.is_false(frameRow.note:IsShown())
        assert.equal("", frameRow.note:GetText())
        assert.equal(ns.UI.EquipPanel.RowHeight(false), frameRow:GetHeight())
        assert.is_falsy(frameRow.line.name:GetText():find("Great Vault", 1, true))
        assert.is_falsy(frameRow.line.second:GetText():find("Great Vault", 1, true))
    end)

    -- And the answer sentence over this exact week: fourteen slots settled and
    -- one reward waiting, so the tab's whole first line is the one thing there
    -- is to do and then the tail that says the rest is fine (M5-1b).
    it("puts the one thing there is to do in the answer sentence, and nothing else", function()
        local answer = ns.UI.EquipPanel.AnswerText(panel.match)
        assert.equal(answer, panel.answer:GetText())
        assert.is_truthy(answer:find("from the vault", 1, true))
        assert.is_truthy(answer:find(ns.UI.EquipPanel.ANSWER_TAIL, 1, true))
        -- Nothing to put on, so the sentence never says so.
        assert.equal(0, panel.match.counts.swap)
        assert.is_falsy(answer:find("Put on", 1, true))
        -- and not a percent anywhere on it, because the export carries none
        assert.is_falsy(answer:find("%%"))
    end)

    it("offers nothing to equip on that row and nothing to equip at all", function()
        local frameRow = vaultRow()
        assert.is_false(ns.UI.EquipPanel.Describe(frameRow.matchRow).actionable)
        assert.is_false(frameRow.equip:IsShown())
        assert.is_false(frameRow.equip:IsEnabled())
        assert.equal(0, panel.match.counts.swap)
        assert.is_false(panel.equipAll:IsShown())
        assert.is_false(ns.UI.EquipPanel.Equip(frameRow.matchRow).ok)
    end)

    it("counts it as waiting in the vault, not as a hole in his gear", function()
        local summary = ns.UI.EquipPanel.SummaryText(panel.match)
        assert.is_truthy(summary:find("14 already best, 0 to swap, 1 waiting in the Great Vault, 0 not owned", 1, true))
        -- The same counts, in the bar's key - except that a state with nothing
        -- in it is not drawn at all, because a `0 to swap` is a word spent
        -- saying nothing (M5-1b).
        local key = panel.barKey:GetText()
        assert.is_truthy(key:find("14 already best", 1, true))
        assert.is_truthy(key:find("1 in the Great Vault", 1, true))
        assert.is_falsy(key:find("0 to swap", 1, true))
        assert.is_falsy(key:find("0 not owned", 1, true))
        -- and one segment per slot, never one per point of anything
        assert.equal(#panel.match.rows, #ns.UI.EquipPanel.Bar(panel.match).segments)
    end)

    it("does not claim an empty slot is already equipped", function()
        local row = {
            slot = "Trinket",
            status = "best_in_vault",
            verdictItem = { itemID = 998877, level = 300, isVault = true },
        }
        local described = ns.UI.EquipPanel.Describe(row)
        assert.is_falsy(described.text:find("already equipped", 1, true))
        assert.is_truthy(described.text:find("nothing equipped", 1, true))
        assert.is_truthy(described.note:find("Great Vault option in this slot", 1, true))
    end)
end)

-- M5-1b (WKE-610): Equip Now redrawn to the approved canvas (WKE-598) with the
-- owner's five answers of 2026-09-16 - the mark set as drawn, the slot column
-- dropped, the already-best rows folded, the slot bar kept, dark only at 760.
-- Everything here is read off the owner's own scan and his own export.
describe("Equip Now redrawn (M5-1b)", function()
    local ns, world, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        panel = ns.UI.frame.equipPanel
    end)

    after_each(function()
        H.unload()
    end)

    local function rowFor(status)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.shown and frameRow.matchRow and frameRow.matchRow.status == status then
                return frameRow
            end
        end
        return nil
    end

    it("gives each state its own mark, at the size it is seen at, and no badge word", function()
        ns.UI.EquipPanel.ToggleFold(ns.db)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        local seen = {}
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.shown and frameRow.matchRow then
                local status = frameRow.matchRow.status
                seen[status] = true
                local mark = ns.UI.EquipPanel.MARK[status]
                if mark then
                    assert.is_true(frameRow.line.mark:IsShown())
                    assert.equal(mark.atlas, frameRow.line.mark.atlas)
                    assert.equal(ns.UI.ItemLine.MARK_SIZE, frameRow.line.mark:GetWidth())
                    assert.equal(ns.UI.ItemLine.MARK_SIZE, frameRow.line.mark:GetHeight())
                    -- The art is never asked to draw itself at its own size:
                    -- R-2b, the fault that squashed a 214x121 atlas into 15
                    -- points, cannot happen to a mark drawn this way.
                    assert.is_false(frameRow.line.mark.atlasUsedSize)
                    assert.equal(ns.UI.EquipPanel.STATUS_HEX[status], mark.hex)
                else
                    -- A swap: the pair and the button are the picture.
                    assert.equal("swap", status)
                    assert.is_false(frameRow.line.mark:IsShown())
                end
                -- No badge word on any row, in any state.
                assert.equal("", frameRow.line.badge:GetText())
            end
        end
        assert.is_true(seen.equipped_is_best and seen.swap and seen.best_not_owned)
    end)

    it("puts the slot on the row's second line, because there is no slot column", function()
        ns.UI.EquipPanel.ToggleFold(ns.db)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.shown and frameRow.matchRow then
                assert.is_truthy(frameRow.line.second:GetText():find(frameRow.matchRow.slot, 1, true))
                assert.is_nil(frameRow.slotText)
            end
        end
        -- A swap says where the piece is, after the slot; an already-best row
        -- says the slot and stops.
        local swap = rowFor("swap")
        assert.is_table(swap)
        assert.equal(
            swap.matchRow.slot .. ns.UI.EquipPanel.SECOND_SEPARATOR .. "in your bags",
            swap.line.second:GetText()
        )
    end)

    it("says the answer in one sentence for each of the three cases", function()
        -- Something to do: this week has swaps, so the sentence opens with the
        -- thing to put on and closes with the tail.
        assert.is_true(panel.match.counts.swap > 0)
        local answer = ns.UI.EquipPanel.AnswerText(panel.match)
        assert.equal(answer, panel.answer:GetText())
        assert.is_truthy(answer:find("Put on ", 1, true))
        assert.is_truthy(answer:find(ns.UI.EquipPanel.ANSWER_TAIL, 1, true))
        -- Nothing to do: every row settled.
        local settled = { ok = true, rows = {}, counts = { equipped_is_best = 0 } }
        for _, row in ipairs(panel.match.rows) do
            if row.status == "equipped_is_best" then
                settled.rows[#settled.rows + 1] = row
                settled.counts.equipped_is_best = settled.counts.equipped_is_best + 1
            end
        end
        assert.is_true(#settled.rows > 0)
        assert.equal(ns.UI.EquipPanel.ANSWER_ALL_BEST, ns.UI.EquipPanel.AnswerText(settled))
        -- Nothing rated at all: the honest state, not a claim that all is well.
        local unrated = { ok = true, rows = {}, counts = { equipped_is_best = 0, no_verdict = 0 } }
        for _, row in ipairs(panel.match.rows) do
            if row.status == "equipped_is_best" then
                unrated.rows[#unrated.rows + 1] = { slot = row.slot, status = "no_verdict", equipped = row.equipped }
                unrated.counts.no_verdict = unrated.counts.no_verdict + 1
            end
        end
        assert.equal(ns.UI.EquipPanel.ANSWER_NOTHING_RATED, ns.UI.EquipPanel.AnswerText(unrated))
    end)

    it("draws one bar segment per slot, in slot order, and never one per point of value", function()
        local bar = ns.UI.EquipPanel.Bar(panel.match)
        assert.equal(#panel.match.rows, #bar.segments)
        for index, segment in ipairs(bar.segments) do
            assert.equal(panel.match.rows[index].status, segment.status)
        end
        -- Drawn: one texture per segment, each a flat colour in that state's
        -- own hex, sharing out the panel's own width rather than a number of
        -- the panel's (M5-2c, WKE-609).
        local drawnSegments = 0
        for index, texture in ipairs(panel.segments) do
            if texture:IsShown() then
                drawnSegments = drawnSegments + 1
                local r, g, b = ns.UI.ItemLine.RGB(bar.segments[index].hex)
                assert.same({ r, g, b }, { texture.colorTexture[1], texture.colorTexture[2], texture.colorTexture[3] })
                assert.equal(ns.UI.EquipPanel.BAR_HEIGHT, texture:GetHeight())
            end
        end
        assert.equal(#bar.segments, drawnSegments)
        -- The segments fill the panel's width, gaps included, and no figure of
        -- this panel's own decides it.
        local count = #bar.segments
        local expected = (panel.rowWidth - (count - 1) * ns.UI.EquipPanel.BAR_SEGMENT_GAP) / count
        assert.equal(expected, panel.segments[1]:GetWidth())
        -- The key says each present colour's count in words; colour is never
        -- the only signal.
        local key = panel.barKey:GetText()
        for _, entry in ipairs(bar.key) do
            assert.is_truthy(key:find(entry.text, 1, true))
        end
        -- and in the canvas's order: what there is to do first, settled last.
        local swapAt = key:find("to swap", 1, true)
        local bestAt = key:find("already best", 1, true)
        assert.is_truthy(swapAt)
        assert.is_truthy(bestAt)
        assert.is_true(swapAt < bestAt)
        -- No percent on this tab that the export does not itself carry.
        assert.is_falsy(key:find("%%"))
    end)

    it("folds the settled rows by default, opens them dim, and remembers which per character", function()
        local settled = panel.match.counts.equipped_is_best
        assert.is_true(settled > 0)
        assert.is_false(ns.UI.EquipPanel.FoldOpen(ns.db))
        assert.is_true(panel.fold:IsShown())
        local drawn = 0
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.shown and frameRow.matchRow then
                drawn = drawn + 1
                assert.is_not.equal("equipped_is_best", frameRow.matchRow.status)
            end
        end
        assert.equal(#panel.match.rows - settled, drawn)

        panel.fold:Click()
        assert.is_true(ns.UI.EquipPanel.FoldOpen(ns.db))
        drawn = 0
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.shown and frameRow.matchRow then
                drawn = drawn + 1
                if frameRow.matchRow.status == "equipped_is_best" then
                    assert.equal(ns.UI.ItemLine.DIM_ALPHA, frameRow.line:GetAlpha())
                else
                    assert.equal(1, frameRow.line:GetAlpha())
                end
            end
        end
        assert.equal(#panel.match.rows, drawn)

        -- Remembered per character, in the same place the Upgrade Map keeps its
        -- sections: a fresh panel over the same database opens already open.
        local second = ns.UI.EquipPanel.Create(ns.UI.frame)
        ns.UI.EquipPanel.Refresh(second, panel.match)
        assert.is_true(second.fold:IsShown())
        assert.is_truthy(second.fold.text:GetText():find(ns.UI.EquipPanel.FOLD_OPEN_MARK, 1, true))
    end)

    it("moves the quiet notes onto an icon whose hover says them whole", function()
        world.bankOpen = false
        ns.UI.Refresh()
        local note = ns.UI.EquipPanel.NoteText(panel.match)
        assert.is_truthy(note:find("bank closed", 1, true))
        assert.is_true(panel.hint:IsShown())
        assert.equal(note, panel.hintText)
        -- It is an icon, not a line: nothing on the panel puts those words on
        -- screen until the hover.
        assert.is_falsy(panel.answer:GetText():find("bank closed", 1, true))
        assert.is_falsy(panel.barKey:GetText():find("bank closed", 1, true))
        panel.hint:GetScript("OnEnter")(panel.hint)
        assert.equal(note, world.tooltip.stub:Text())
        assert.equal(panel.hint, world.tooltip.owner)
    end)
end)

describe("the Equip Now panel in combat", function()
    local ns, world, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        panel = ns.UI.frame.equipPanel
        ns.UI.frame:Show()
    end)

    after_each(function()
        H.unload()
    end)

    it("keeps the last scan on screen, disables every button and says why", function()
        world.inCombat = true
        world.fireEvent("PLAYER_REGEN_DISABLED")
        assert.is_true(panel.match.stale)
        assert.equal(15, #panel.match.rows)
        -- The in-combat warning is a condition on the answer, so since M5-1b it
        -- is the hint icon's own words rather than a line above the list; the
        -- text model still says it in the same sentence it always did.
        assert.is_true(panel.hint:IsShown())
        assert.is_truthy(panel.hintText:find("In combat", 1, true))
        assert.is_truthy(ns.UI.EquipPanel.NoteText(panel.match):find("In combat", 1, true))
        assert.is_false(panel.equipAll:IsEnabled())
        ns.UI.EquipPanel.ToggleFold(ns.db)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        for i = 1, #panel.match.rows do
            assert.is_false(panel.rows[i].equip:IsEnabled())
        end
    end)

    it("refuses the click and the tooltip says so", function()
        local row = firstSwapRow(panel)
        world.inCombat = true
        world.fireEvent("PLAYER_REGEN_DISABLED")
        assert.is_false(row.equip:Click())
        assert.equal(0, #world.equipCalls)
        row.equip.stub:Enter()
        assert.equal(ns.UI.EquipPanel.COMBAT_TOOLTIP, world.tooltip.stub:Text())

        assert.is_false(panel.equipAll:Click())
        assert.equal(0, #world.equipCalls)
    end)

    it("refuses in Equip itself, not only on the button", function()
        local row = firstSwapRow(panel).matchRow
        world.inCombat = true
        local result = ns.UI.EquipPanel.Equip(row)
        assert.is_false(result.ok)
        assert.equal("combat", result.reason)
        assert.equal(0, #world.equipCalls)
        assert.is_false(ns.UI.EquipPanel.EquipAll(panel.match).ok)
        assert.equal(0, #world.equipCalls)
    end)

    it("comes back to a fresh scan when combat ends", function()
        world.inCombat = true
        world.fireEvent("PLAYER_REGEN_DISABLED")
        world.inCombat = false
        world.fireEvent("PLAYER_REGEN_ENABLED")
        assert.is_nil(panel.match.stale)
        assert.is_true(panel.equipAll:IsEnabled())
        assert.is_true(firstSwapRow(panel).equip:IsEnabled())
    end)
end)

describe("the content type setting", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("registers one dropdown offering QE Live's own two content types", function()
        -- Two dropdowns since C-6 (WKE-540): the content type and the Vault
        -- tab's highlight scenario, in that order.
        assert.equal(2, #world.settings.dropdowns)
        local dropdown = world.settings.dropdowns[1]
        assert.equal("Lootpath", dropdown.category.name)
        assert.is_true(dropdown.category.registered)
        local values = {}
        for _, entry in ipairs(dropdown.options()) do
            values[#values + 1] = entry.value
        end
        assert.same({ "Dungeon", "Raid" }, values)
        assert.same({ "Dungeon", "Raid" }, ns.QEImport.CONTENT_TYPES)
    end)

    it("opens the page through Settings.OpenToCategory", function()
        ns.HandleSlash("options")
        assert.equal(1, #world.settings.opened)
        assert.equal(ns.UI.Options.category:GetID(), world.settings.opened[1])
    end)

    it("keeps a Dungeon export and a Raid export side by side and shows the chosen one", function()
        -- The genuine export is Raid; the hand-built sample is Mythic+, which
        -- QE Live has never called "Mythic+" - so it files under "Unknown"
        -- until an export with contentType "Dungeon" exists.
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        local raid = ns.QEImport.ForContentType("Raid")
        assert.is_table(raid)
        assert.equal("cxeiassqdyvz", raid.reportId)

        -- A Dungeon export, made by swapping only the contentType string of the
        -- genuine file so everything else stays QE Live's.
        local dungeonText = readFile(REAL_EXPORT):gsub('"contentType":%s*"Raid"', '"contentType": "Dungeon"', 1)
        assert.are_not.equal(readFile(REAL_EXPORT), dungeonText)
        ns.UI.frame.pasteBox:SetText(dungeonText)
        ns.UI.frame.importButton:Click()

        assert.is_table(ns.QEImport.ForContentType("Raid"))
        assert.is_table(ns.QEImport.ForContentType("Dungeon"))
        assert.same({ "Dungeon", "Raid" }, ns.QEImport.StoredContentTypes())

        ns.UI.Options.Set("Raid")
        assert.equal("Raid", select(2, ns.UI.ActiveVerdict()))
        assert.equal("Raid", ns.UI.Refresh().contentType)
        ns.UI.Options.Set("Dungeon")
        assert.equal("Dungeon", ns.UI.Refresh().contentType)
    end)

    it("falls back to the most recent import and says that it did", function()
        ns.UI.frame.pasteBox:SetText(readFile(REAL_EXPORT))
        ns.UI.frame.importButton:Click()
        -- Nothing has ever been pasted for the default (Dungeon).
        assert.equal("Dungeon", ns.UI.Options.Get())
        local verdict, contentType, fellBack = ns.UI.ActiveVerdict()
        assert.is_table(verdict)
        assert.equal("Raid", contentType)
        assert.is_true(fellBack)
        -- "pasted" became "imported" in C-2, because the companion is now the
        -- other way an export gets here.
        assert.is_truthy(ns.UI.VerdictNoteText():find("nothing has been imported for Dungeon", 1, true))
        -- V-2 (WKE-573): the sentence names the export as well as the content type
        assert.is_truthy(ns.UI.VerdictNoteText():find("Raid Top Gear export", 1, true))
        assert.is_truthy(ns.UI.VerdictNoteText():find("(pasted)", 1, true))
    end)

    it("files an export with no content type under Unknown rather than dropping it", function()
        ns.UI.frame.pasteBox:SetText(readFile(SAMPLE_EXPORT))
        ns.UI.frame.importButton:Click()
        assert.equal("Mythic+", ns.QEImport.Current().contentType)
        assert.is_table(ns.QEImport.ForContentType("Mythic+"))
        assert.same({ "Mythic+" }, ns.QEImport.StoredContentTypes())
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-3 (WKE-524): the Upgrade Map and Vault tabs in the same window.

local function withJournalWalk(ns)
    ns.db.global.captures.journal = { R.snapshot("journal", 1, R.JOURNAL) }
end

describe("the window's three tabs", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        R.vault(world, R.snapshot("vault", 3, R.JOURNAL))
        withJournalWalk(ns)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("has one tab per promise, in the order the product states them", function()
        assert.equal(3, #frame.tabs)
        assert.same(
            { "Equip Now", "Upgrade Map", "Vault" },
            { frame.tabs[1]:GetText(), frame.tabs[2]:GetText(), frame.tabs[3]:GetText() }
        )
        -- PanelTabButtonTemplate's parentArray puts each tab in frame.Tabs, and
        -- PanelTemplates_SetNumTabs is what Blizzard's own artwork reads.
        assert.equal(3, #frame.Tabs)
        assert.equal(3, frame.numTabs)
        assert.same({ 1, 2, 3 }, { frame.tabs[1]:GetID(), frame.tabs[2]:GetID(), frame.tabs[3]:GetID() })
    end)

    it("opens on Equip Now with the other two panels hidden", function()
        assert.equal(1, frame.selectedTab)
        assert.is_true(frame.equipPanel:IsShown())
        assert.is_false(frame.upgradeMapPanel:IsShown())
        assert.is_false(frame.vaultPanel:IsShown())
    end)

    it("opens on the Upgrade Map when the tooltip's last line sends a reader there", function()
        -- R-2a (WKE-571): the tooltip's "Why this?" cannot be clicked, so it
        -- names `/lootpath map`, and this is the destination it names. It
        -- SHOWS rather than toggles - a reader who typed it from a tooltip
        -- asked to see the tab, never to close a window.
        frame:Hide()
        assert.equal(frame, ns.UI.ShowUpgradeMap())
        assert.is_true(frame:IsShown())
        assert.equal(2, frame.selectedTab)
        assert.is_true(frame.upgradeMapPanel:IsShown())
        -- Typed a second time with the window already open on that tab: still
        -- open, still that tab.
        ns.UI.ShowUpgradeMap()
        assert.is_true(frame:IsShown())
        assert.equal(2, frame.selectedTab)
        -- UX-3 (WKE-599) moved those words onto the block's last line,
        -- which is the one place a command lives now.
        assert.is_truthy(ns.UI.Tooltip.MAP:find("/lootpath map", 1, true))
    end)

    it("shows exactly one panel per tab clicked", function()
        for _, tab in ipairs(ns.UI.TABS) do
            frame.tabs[tab.id]:Click()
            assert.equal(tab.id, frame.selectedTab)
            assert.equal(tab.id, _G.PanelTemplates_GetSelectedTab(frame))
            local shown = {}
            for _, other in ipairs(ns.UI.TABS) do
                if frame[other.key]:IsShown() then
                    shown[#shown + 1] = other.key
                end
            end
            assert.same({ tab.key }, shown)
        end
    end)

    it("draws only the tab that is on screen", function()
        -- The Equip tab is up, so a refresh scans and matches and leaves the
        -- other two panels untouched. Walking 613 journal rows to redraw a
        -- panel nobody is looking at is the thing this avoids.
        assert.is_nil(frame.upgradeMapPanel.model)
        assert.is_nil(frame.vaultPanel.model)
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        frame.importButton:Click()
        assert.is_table(frame.equipPanel.match)
        assert.is_nil(frame.upgradeMapPanel.model)
        assert.is_nil(frame.vaultPanel.model)

        frame.tabs[2]:Click()
        assert.is_table(frame.upgradeMapPanel.model)
        assert.is_nil(frame.vaultPanel.model)
    end)
end)

describe("the Upgrade Map tab", function()
    local ns, world, frame, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        withJournalWalk(ns)
        frame = ns.UI.Frame()
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        frame.importButton:Click()
        frame.tabs[2]:Click()
        panel = frame.upgradeMapPanel
    end)

    after_each(function()
        H.unload()
    end)

    it("renders the map into the window and pins the values-free note", function()
        -- Since UX-5 (WKE-614) the note is not a paragraph under the header: it
        -- is the first line of the hint icon's tooltip, verbatim.
        assert.equal(ns.UpgradeMapPanel.NOTE, ns.UpgradeMapPanel.HintLines(panel.model, panel.mode)[1])
        assert.equal("Upgrade Map", panel.header:GetText())
        assert.is_true(panel.model.hasMap)
        -- The printed text is still the model's own, unchanged by M5-3...
        assert.same(ns.UpgradeMapPanel.Lines(panel.model), panel.lines)
        assert.is_true(#panel.lines > 100)
        -- ...and what is DRAWN is the element list, through the scroll box.
        assert.is_true(#panel.elements > 100)
        local frames = panel.scrollBox:GetFrames()
        assert.is_true(#frames > 0)
        assert.same(panel.elements[1], frames[1]:GetElementData())
    end)

    it("puts no QE Live number on screen, because the real export covers nothing", function()
        assert.equal(0, panel.model.counts.covered)
        for _, line in ipairs(panel.lines) do
            assert.is_nil(line:find("QE Live: ", 1, true))
        end
        -- Not on a badge either, which is where a drawn row carries a number.
        -- Since R-3 the slot's rows are its roads and every one of them has a
        -- badge, so the assertion is what a badge may SAY: one of the phrases,
        -- never a percentage and never a source.
        for _, element in ipairs(panel.elements) do
            local badge = element.row and element.row.badge
            if badge then
                assert.is_nil(badge.text:find("%%"))
                assert.is_nil(badge.text:find("QE Live", 1, true))
            end
        end
    end)

    it("narrows to one difficulty when its dropdown row is picked", function()
        local before = panel.model.counts.candidates
        local mythicPlus
        for _, option in ipairs(panel.difficultyDropdown.menuElements) do
            if option.text:find("Mythic+ 10", 1, true) then
                mythicPlus = option
            end
        end
        assert.is_not_nil(mythicPlus)
        mythicPlus:Select()
        assert.same({ 8 }, panel.difficultyIDs)
        assert.is_true(panel.model.counts.candidates < before)
    end)

    it("says nothing about anything once the import is gone", function()
        assert.is_true(panel.model.hasVerdict)
        ns.db.char.qeImport = nil
        ns.db.char.qeImports = {}
        frame.tabs[2]:Click()
        assert.is_false(panel.model.hasVerdict)
    end)

    -- The distinguishing case: two imports on the character, the setting
    -- pointing at one of them, and the most recent paste being the other. A
    -- panel reading QEImport.Current() would show the Raid answer under a
    -- Dungeon setting with nothing said, which is exactly what UI.ActiveVerdict
    -- exists to prevent (M2-2).
    it("shows the content type the setting asks for, not the last paste", function()
        -- A Dungeon export built from the real one, with the Feet item's bonus
        -- IDs replaced by the single one (3524) that the committed journal walk
        -- really carries for that itemID, so the exact-key join lands.
        local dungeon = readFile(REAL_EXPORT)
            :gsub('"contentType": "Raid"', '"contentType": "Dungeon"', 1)
            :gsub("13440,%s*6652,%s*13662,%s*12699,%s*12835", "3524", 1)
        frame.pasteBox:SetText(dungeon)
        frame.importButton:Click()
        assert.equal("Dungeon", ns.QEImport.Current().contentType)
        -- ...then the Raid export, so the LAST paste is the Raid one.
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        frame.importButton:Click()
        assert.equal("Raid", ns.QEImport.Current().contentType)
        assert.equal("Dungeon", ns.UI.Options.Get())

        frame.tabs[2]:Click()
        -- The Dungeon export covers the journal's three rows for 251153; the
        -- Raid one covers nothing at all. The join itself is unchanged by R-3.
        assert.equal(3, panel.model.counts.covered)
        -- What is on screen is the Dungeon answer, said by the roads: the Feet
        -- slot's set group is headed by THAT document's plan name and holds the
        -- item it put in the best set. A panel reading the last paste would
        -- have no set group here at all, because the Raid answer covers nothing.
        local feet
        for _, section in ipairs(panel.model.slots) do
            if section.slot == "Feet" then
                feet = section
            end
        end
        assert.is_table(feet)
        local setGroup = feet.roadGroups[1]
        assert.equal(ns.Roads.GROUP_SET, setGroup.group)
        assert.equal("Your best set · as offered · the pick first, then the rated alternatives", setGroup.header)
        assert.equal(1, #setGroup.rows)
        assert.equal(251153, setGroup.rows[1].itemID)
        assert.equal("in your best set", setGroup.rows[1].badge.text)
        -- ...and the same row is drawn, through the element list.
        local badged = 0
        for _, element in ipairs(panel.elements) do
            local badge = element.row and element.row.badge
            if badge and badge.text == "in your best set" then
                badged = badged + 1
            end
        end
        assert.is_true(badged >= 1)
    end)
end)

describe("the Vault tab", function()
    local ns, world, frame, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        R.vault(world, R.snapshot("vault", 3, R.JOURNAL))
        frame = ns.UI.Frame()
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        frame.importButton:Click()
        frame.tabs[3]:Click()
        panel = frame.vaultPanel
    end)

    after_each(function()
        H.unload()
    end)

    it("renders the week's notes into the window and its options into the grid", function()
        -- No legend under the header since V-5 (WKE-600).
        assert.is_nil(rawget(panel, "note"))
        assert.equal("Vault", panel.header:GetText())
        assert.equal(10, panel.model.counts.options)
        local notes = ns.VaultPanel.NoteLines(panel.model)
        for i, line in ipairs(notes) do
            assert.equal(line, panel.rows[i]:GetText())
        end
        -- Since M5-4 the options are the grid, in Blizzard's own order.
        assert.equal(3, #panel.gridRows)
        assert.equal("Raids", panel.gridRows[1].label:GetText())
        assert.equal("Dungeons", panel.gridRows[2].label:GetText())
        assert.equal("World", panel.gridRows[3].label:GetText())
        -- This week has generated nothing, so every cell is a locked one and
        -- says what the client says it needs.
        for _, gridRow in ipairs(panel.gridRows) do
            assert.equal(3, #gridRow.cells)
            for _, cell in ipairs(gridRow.cells) do
                assert.is_true(cell:IsShown())
                assert.is_true(cell.locked:IsShown())
                assert.is_false(cell.line:IsShown())
            end
        end
    end)

    it("says the vault has generated nothing yet rather than showing an empty list", function()
        assert.equal(0, panel.model.counts.rewards)
        local sawNote = false
        for i = 1, #panel.lines do
            if panel.rows[i]:GetText() == ns.VaultPanel.NO_REWARDS_NOTE then
                sawNote = true
            end
        end
        assert.is_true(sawNote)
    end)

    it("shows the vault's own refusal when the client cannot be read", function()
        world.inCombat = true
        frame.tabs[3]:Click()
        assert.is_false(panel.model.ok)
        assert.equal("combat", panel.model.reason)
        assert.equal("The vault could not be read: combat", panel.rows[1]:GetText())
    end)
end)

-- ---------------------------------------------------------------------------
-- WKE-530 (M3-5) through the real window: the pinned note appeared twice on
-- both tabs, the filter row ran off the frame, and the title bar showed the
-- packager's own token. All four were on screen in the owner's first in-game
-- run of the whole window, 2026-09-06.

describe("the window after WKE-530", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        withJournalWalk(ns)
        R.vault(world, R.snapshot("vault", 3, R.JOURNAL))
        frame = ns.UI.Frame()
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        frame.importButton:Click()
    end)

    after_each(function()
        H.unload()
    end)

    -- Counted over whatever the panel puts in its list: font strings on the
    -- Vault tab, and since M5-3 the Upgrade Map's scroll box elements.
    local function noteCount(panel, note)
        local seen = 0
        -- Since V-5 (WKE-600) not every tab has a pinned note at all.
        if panel.note and panel.note:GetText():find(note, 1, true) then
            seen = seen + 1
        end
        -- Since UX-5 (WKE-614) the Upgrade Map says its pinned note on its hint
        -- icon rather than under its header; it is still said exactly once.
        if panel.hintText and panel.hintText:find(note, 1, true) then
            seen = seen + 1
        end
        for _, element in ipairs(panel.elements or {}) do
            if type(element.text) == "string" and element.text:find(note, 1, true) then
                seen = seen + 1
            end
        end
        for _, text in ipairs(panel.rows or {}) do
            if text:GetText():find(note, 1, true) then
                seen = seen + 1
            end
        end
        return seen
    end

    it("draws each tab's pinned note exactly once", function()
        frame.tabs[2]:Click()
        assert.equal(1, noteCount(frame.upgradeMapPanel, ns.UpgradeMapPanel.NOTE))
        -- The Vault tab's own legend is gone since V-5 (WKE-600), so "exactly
        -- once" became "nowhere" - counted over the same sentence, written out
        -- because the constant that held it no longer exists.
        frame.tabs[3]:Click()
        assert.equal(
            0,
            noteCount(frame.vaultPanel, "Rated options show their value. Other options are listed by item level only.")
        )
    end)

    -- Finding 2 was five difficulty buttons overflowing the window's width and
    -- the fifth being clipped at its edge. Since M5-3 there are no difficulty
    -- buttons: one dropdown holds every difficulty a map can have in the width
    -- of one control, and the row it sits on cannot overflow however many the
    -- walk found. What is left of the finding is that the dropdown is inside
    -- the panel and that no two rows read the same.
    it("holds every difficulty in one dropdown that fits the panel's width", function()
        frame.tabs[2]:Click()
        local panel = frame.upgradeMapPanel
        assert.is_true(#panel.model.difficulties > 1)
        assert.is_true(panel.difficultyDropdown:IsShown())
        assert.is_true(panel.difficultyDropdown:GetWidth() < panel:GetWidth())
        local seen = {}
        for _, option in ipairs(panel.difficultyDropdown.menuElements) do
            assert.is_nil(seen[option.text], "two dropdown rows read " .. option.text)
            seen[option.text] = true
        end
    end)

    it("titles itself with the name-mark, and says the version where ages are read", function()
        -- UX-4b: the title is the wordmark texture and carries no words, so the
        -- version moved to the foot of the status strip's tooltip.
        assert.equal("", frame.TitleText:GetText())
        local wordmark = frame.titleWordmark
        assert.is_table(wordmark)
        assert.equal(ns.UI.MEDIA.WORDMARK, wordmark:GetTexture())
        assert.is_nil(wordmark:GetAtlas())
        -- Drawn at the texture's own 4:1 ratio: a stretched name-mark is a
        -- different name-mark.
        assert.equal(ns.UI.TITLE_WORDMARK_HEIGHT, wordmark.height)
        assert.equal(ns.UI.TITLE_WORDMARK_HEIGHT * ns.UI.TITLE_WORDMARK_RATIO, wordmark.width)
        -- In the brand colour, from the one string that holds it.
        local r, g, b = ns.UI.ItemLine.RGB(ns.UI.BRAND_HEX)
        assert.same({ r, g, b, nil }, wordmark.vertexColor)
        -- It hangs in the template's title container, which is what centres it
        -- clear of the portrait ring.
        assert.same({ "CENTER", frame.TitleContainer, "CENTER", 0, 0 }, wordmark.points[1])

        assert.equal("Lootpath 0.0.0-test", ns.UI.VersionText())
        H.unload()
        local dev = H.load({
            beforeLoad = function(w)
                w.metadata.Version = "@project-version@"
            end,
        })
        -- Never the packager's token, wherever the version is printed.
        assert.equal("Lootpath dev", dev.UI.VersionText())
        assert.equal("", dev.UI.Frame().TitleText:GetText())
    end)
end)

-- ---------------------------------------------------------------------------
-- M3-6 (WKE-535): one paste box, two schemas.

local UF_DUNGEON_EXPORT = "spec/fixtures/qe/qe-upgradefinder-Hotornot-abxrrnezfilt.json"
local UF_RAID_EXPORT = "spec/fixtures/qe/qe-upgradefinder-Hotornot-kqyktjywppzw.json"

describe("the paste box routes by schema", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("reads the schema out of the text without decoding it", function()
        assert.equal("qe-live-droptimizer", ns.UI.DetectSchema(readFile(REAL_EXPORT)))
        assert.equal("qe-live-upgradefinder", ns.UI.DetectSchema(readFile(UF_DUNGEON_EXPORT)))
        assert.is_nil(ns.UI.DetectSchema("not json at all"))
        assert.is_nil(ns.UI.DetectSchema(nil))
    end)

    it("sends an Upgrade Finder export to UFImport and leaves the Top Gear store empty", function()
        frame.pasteBox:SetText(readFile(UF_DUNGEON_EXPORT))
        assert.is_true(frame.importButton:Click())
        assert.is_nil(ns.QEImport.Current())
        assert.is_table(ns.UFImport.Current())
        assert.equal("abxrrnezfilt", ns.UFImport.Current().reportId)
        local status = frame.status:GetText()
        assert.is_truthy(status:find("Upgrade Finder", 1, true))
        assert.is_truthy(status:find("Restoration Druid", 1, true))
        assert.is_truthy(status:find("Dungeon", 1, true))
        assert.is_truthy(status:find("315 ranked drops", 1, true))
    end)

    it("sends a Top Gear export to QEImport and names it as such", function()
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        assert.is_true(frame.importButton:Click())
        assert.is_table(ns.QEImport.Current())
        assert.is_nil(ns.UFImport.Current())
        local status = frame.status:GetText()
        assert.is_truthy(status:find("Top Gear", 1, true))
        assert.is_truthy(status:find("15 items", 1, true))
    end)

    it("refuses a third schema by name, naming both the ones it reads, and stores nothing", function()
        frame.pasteBox:SetText('{ "schema": "raidbots-droptimizer", "version": 1 }')
        frame.importButton:Click()
        local status = frame.status:GetText()
        assert.is_truthy(status:find("raidbots-droptimizer", 1, true))
        assert.is_truthy(status:find("qe-live-droptimizer", 1, true))
        assert.is_truthy(status:find("qe-live-upgradefinder", 1, true))
        assert.is_nil(ns.QEImport.Current())
        assert.is_nil(ns.UFImport.Current())
    end)

    it("still lets a parser answer for text that names no schema at all", function()
        frame.pasteBox:SetText("{ not json at all")
        frame.importButton:Click()
        assert.is_truthy(frame.status:GetText():find("that is not JSON", 1, true))
    end)

    it("shows both ages once the character has both kinds for one content type", function()
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        frame.importButton:Click()
        assert.equal("Raid", ns.QEImport.Current().contentType)
        frame.pasteBox:SetText(readFile(UF_RAID_EXPORT))
        frame.importButton:Click()
        local status = frame.status:GetText()
        -- "Imported" and the kind are separated by the colour escape.
        assert.is_truthy(status:find("|r Upgrade Finder:", 1, true))
        assert.is_truthy(status:find("Also stored:", 1, true))
        assert.is_truthy(status:find("Top Gear (Raid)", 1, true))
    end)

    it("says nothing about a counterpart of another content type", function()
        frame.pasteBox:SetText(readFile(REAL_EXPORT))
        frame.importButton:Click()
        -- The Top Gear export is Raid; this Upgrade Finder one is Dungeon.
        frame.pasteBox:SetText(readFile(UF_DUNGEON_EXPORT))
        frame.importButton:Click()
        assert.is_nil(frame.status:GetText():find("Also stored:", 1, true))
    end)
end)

describe("UI.ActiveUpgradeFinderDocuments", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("answers an empty list before anything is imported", function()
        assert.same({}, (ns.UI.ActiveUpgradeFinderDocuments()))
    end)

    it("prefers the content type the setting asks for over the most recent paste", function()
        frame.pasteBox:SetText(readFile(UF_DUNGEON_EXPORT))
        frame.importButton:Click()
        frame.pasteBox:SetText(readFile(UF_RAID_EXPORT))
        frame.importButton:Click()
        assert.equal("Raid", ns.UFImport.Current().contentType)
        assert.equal("Dungeon", ns.UI.Options.Get())
        local documents, contentType, fellBack = ns.UI.ActiveUpgradeFinderDocuments()
        assert.equal(1, #documents)
        assert.equal("Dungeon", documents[1].verdict.contentType)
        assert.equal("Dungeon", contentType)
        assert.is_false(fellBack)
    end)

    it("falls back to the most recent one, and says it fell back", function()
        frame.pasteBox:SetText(readFile(UF_RAID_EXPORT))
        frame.importButton:Click()
        local documents, contentType, fellBack = ns.UI.ActiveUpgradeFinderDocuments()
        assert.equal(1, #documents)
        assert.equal("Raid", documents[1].verdict.contentType)
        assert.equal("Raid", contentType)
        assert.is_true(fellBack)
    end)

    it("hands back every key level stored for the content type, never one of them", function()
        frame.pasteBox:SetText(readFile(UF_DUNGEON_EXPORT))
        frame.importButton:Click()
        -- A second document for the same content type at a key level of its
        -- own, filed the way ns.Companion files one.
        local parsedAt6 = ns.UFImport.Parse(readFile(UF_DUNGEON_EXPORT))
        parsedAt6.verdict.keyLevel = 6
        assert(ns.UFImport.Store(parsedAt6.verdict).ok)
        local documents = ns.UI.ActiveUpgradeFinderDocuments()
        assert.equal(2, #documents)
        assert.equal(6, documents[1].keyLevel)
        assert.is_nil(documents[2].keyLevel, "the document that names no level comes last")
    end)
end)

describe("the Upgrade Map tab with an Upgrade Finder export", function()
    local ns, world, frame, panel

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        withJournalWalk(ns)
        frame = ns.UI.Frame()
        frame.pasteBox:SetText(readFile(UF_DUNGEON_EXPORT))
        frame.importButton:Click()
        frame.tabs[2]:Click()
        panel = frame.upgradeMapPanel
    end)

    after_each(function()
        H.unload()
    end)

    it("puts QE Live's Upgrade Finder numbers on the rows he ranked, through the window", function()
        -- Measured over the 2026-09-06 16:12 walk (558 sources) and the
        -- 2026-09-07 Dungeon export.
        assert.is_true(panel.model.hasUpgrades)
        assert.equal(30, panel.model.counts.ranked)
        assert.equal(151, panel.model.counts.rankedAtAnotherLevel)
        -- A valued row is one whose line carries one of the four sentences
        -- `Panel.UpgradeBadge` writes. The badge no longer leads with a name,
        -- so there is no prefix left to count by (V-1, WKE-569); a pasted
        -- export names no key level either, so there is no "(at +10)" note on
        -- these rows. Nothing else on this map says these words: the export
        -- behind it has no Top Gear coverage, so no `ValueBadge` sentence is
        -- drawn (`counts.covered` is zero, asserted below).
        local function valuedLine(line)
            return line:find("better by ", 1, true)
                or line:find("worse by ", 1, true)
                or line:find("no change", 1, true)
                or line:find("rated, no value given", 1, true)
        end
        local valued, badged = 0, 0
        for _, line in ipairs(panel.lines) do
            if valuedLine(line) then
                valued = valued + 1
            end
        end
        for _, element in ipairs(panel.elements) do
            if element.row and element.row.badge then
                badged = badged + 1
            end
        end
        assert.equal(30, badged)
        -- The 30 ranked rows plus nothing else: this export has no Top Gear
        -- coverage behind it, so `covered` is still zero.
        assert.equal(0, panel.model.counts.covered)
        assert.equal(30, valued)
    end)

    it("goes back to a values-free map the moment the import is gone", function()
        -- Three shelves since C-7 (WKE-543): the most recent import, the one
        -- per content type, and the one per content type AND Mythic+ key
        -- level. The panel reads the last of them, so clearing the first two
        -- and stopping would leave the map valued from a shelf nobody looked
        -- at - which is exactly what this guard is here to catch.
        ns.db.char.ufImport = nil
        ns.db.char.ufImports = {}
        ns.db.char.ufImportsByLevel = {}
        frame.tabs[2]:Click()
        assert.is_false(panel.model.hasUpgrades)
        assert.equal(0, panel.model.counts.ranked)
        for _, line in ipairs(panel.lines) do
            assert.is_nil(line:find("QE Live: ", 1, true))
        end
        for _, element in ipairs(panel.elements) do
            assert.is_nil(element.row and element.row.badge)
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- C-6 (WKE-540): the second setting, and the window's read of the scenarios.

describe("the vault highlight scenario setting", function()
    local ns, world

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("registers a second dropdown offering the four named scenarios", function()
        assert.equal(2, #world.settings.dropdowns)
        local dropdown = world.settings.dropdowns[2]
        assert.equal("Lootpath", dropdown.category.name)
        local values = {}
        for _, entry in ipairs(dropdown.options()) do
            values[#values + 1] = entry.value
        end
        assert.same({ "asOffered", "catalyzed", "thisWeek", "maxed" }, values)
        assert.same(ns.QEImport.SCENARIOS, values)
    end)

    -- M3-13 (WKE-548): the highlight defaults to the question the vault poses -
    -- take one option, upgrade that one, spend the one Catalyst charge. Equip
    -- Now and the Upgrade Map are unmoved by it and still read `asOffered`,
    -- which the two assertions below the default pin.
    it("defaults to thisWeek, the question the vault poses", function()
        assert.equal("thisWeek", ns.UI.Options.GetVaultScenario())
        assert.equal("thisWeek", ns.DB_DEFAULTS.profile.settings.vaultScenario)
        assert.equal("asOffered", ns.QEImport.DEFAULT_SCENARIO)
    end)

    it("remembers what it is set to, and ignores what is not a name", function()
        ns.UI.Options.SetVaultScenario("catalyzed")
        assert.equal("catalyzed", ns.UI.Options.GetVaultScenario())
        assert.equal("catalyzed", ns.db.profile.settings.vaultScenario)
        ns.UI.Options.SetVaultScenario("")
        ns.UI.Options.SetVaultScenario(nil)
        assert.equal("catalyzed", ns.UI.Options.GetVaultScenario())
    end)
end)

describe("UI.ActiveVerdictScenarios", function()
    local ns
    local SCENARIO_FILES = {
        asOffered = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json",
        catalyzed = "spec/fixtures/qe/qe-droptimizer-Hotornot-xrjevewtwqsw.json",
    }

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    local function store(scenario)
        local parsed = ns.QEImport.Parse(readFile(SCENARIO_FILES[scenario]))
        assert(parsed.ok, parsed.reason)
        parsed.verdict.scenario = scenario
        ns.QEImport.Store(parsed.verdict)
        return parsed.verdict
    end

    it("answers an empty list before anything is imported, never nil", function()
        local scenarios, contentType, fellBack = ns.UI.ActiveVerdictScenarios()
        assert.same({}, scenarios)
        assert.equal("Dungeon", contentType)
        assert.is_false(fellBack)
    end)

    it("hands back every stored scenario for the content type on screen", function()
        store("asOffered")
        store("catalyzed")
        local scenarios, contentType, fellBack = ns.UI.ActiveVerdictScenarios()
        assert.equal("Dungeon", contentType)
        assert.is_false(fellBack)
        assert.same({ "asOffered", "catalyzed" }, { scenarios[1].scenario, scenarios[2].scenario })
    end)

    -- Deliverable 2, from the window's side: ActiveVerdict answers asOffered
    -- however many what-ifs are stored beside it, so Equip Now and the Upgrade
    -- Map read what the character has now.
    it("leaves ActiveVerdict answering asOffered", function()
        store("asOffered")
        store("catalyzed")
        local verdict, contentType, fellBack = ns.UI.ActiveVerdict()
        assert.equal(5544.654, verdict.topSet.score)
        assert.equal("Dungeon", contentType)
        assert.is_false(fellBack)
    end)

    it("falls back to the content type that has answers, and says it fell back", function()
        store("asOffered")
        ns.UI.Options.Set("Raid")
        local scenarios, contentType, fellBack = ns.UI.ActiveVerdictScenarios()
        assert.equal("Dungeon", contentType)
        assert.is_true(fellBack)
        assert.equal(1, #scenarios)
    end)
end)

-- ---------------------------------------------------------------------------
-- M5-2 (WKE-551): the chrome. The portrait ring, the status strip, the import
-- dialog, the tabs on the bottom edge, the launcher and the two new settings.
-- Everything here is the stub's widget model again: WHERE a thing is anchored
-- and WHAT it was told to draw are decisions this code makes and a test can
-- hold; what any of it looks like is the owner's eye test (M5-5, WKE-554).

local DUNGEON_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-hldibnbaajft.json"

describe("the window's chrome (M5-2)", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("is a PortraitFrameTemplate with the template's own four keys", function()
        assert.equal("PortraitFrameTemplate", frame.template)
        assert.is_table(frame.TitleContainer)
        assert.equal(frame.TitleContainer.TitleText, frame.TitleText)
        assert.is_table(frame.CloseButton)
        assert.is_table(frame.PortraitContainer)
        -- The template's font string is still there and still the container's;
        -- since UX-4b it is blank, because the name-mark texture draws instead.
        assert.equal("", frame.TitleText:GetText())
        assert.equal(ns.UI.MEDIA.WORDMARK, frame.titleWordmark:GetTexture())
    end)

    it("keeps a title in words on a client with no container to hang a texture on", function()
        -- The name-mark hangs in TitleContainer. A client that has a TitleText
        -- and no container gets the name as text: a window with no title at all
        -- would be the worse answer.
        local said = {}
        local bare = {
            TitleText = {
                SetText = function(_, value)
                    said[#said + 1] = value
                end,
                GetText = function()
                    return said[#said]
                end,
            },
        }
        assert.equal("text", ns.UI.ApplyTitle(bare))
        assert.equal("Lootpath", said[1])
        assert.is_nil(bare.titleWordmark)

        -- And a frame with no title at all is left alone rather than erroring.
        assert.is_nil(ns.UI.ApplyTitle({}))

        -- The real window goes the other way.
        assert.equal("wordmark", ns.UI.ApplyTitle(ns.UI.Frame()))
    end)

    it("still closes on Escape, still drags and still clamps", function()
        assert.equal("LootpathMainFrame", frame.frameName)
        local names = {}
        for _, name in ipairs(_G.UISpecialFrames) do
            names[name] = true
        end
        assert.is_true(names["LootpathMainFrame"])
        assert.is_true(frame.movable)
        assert.is_true(frame.clamped)
        assert.equal(frame.StartMoving, frame:GetScript("OnDragStart"))
    end)

    it("puts the player's spec icon in the ring", function()
        assert.equal("spec", ns.UI.ApplyPortrait(frame))
        assert.equal(world.spec.icon, frame.PortraitContainer.portrait:GetTexture())
        assert.same({ 0, 1, 0, 1 }, frame.PortraitContainer.portrait.texCoord)
    end)

    it("reads the spec through C_SpecializationInfo, and through the globals when it is gone", function()
        assert.equal(world.spec.icon, ns.UI.SpecIcon())
        local saved = _G.C_SpecializationInfo
        _G.C_SpecializationInfo = nil
        assert.equal(world.spec.icon, ns.UI.SpecIcon())
        _G.C_SpecializationInfo = saved
    end)

    it("falls back to the class icon when the client names no spec", function()
        world.spec = nil
        assert.is_nil(ns.UI.SpecIcon())
        assert.equal("class", ns.UI.ApplyPortrait(frame))
        assert.equal(ns.UI.CLASS_ICON_FILE, frame.PortraitContainer.portrait:GetTexture())
        assert.same(_G.CLASS_ICON_TCOORDS.DRUID, frame.PortraitContainer.portrait.texCoord)
    end)

    it("leaves the ring empty rather than guessing when the client names neither", function()
        world.spec = nil
        local coords = _G.CLASS_ICON_TCOORDS
        _G.CLASS_ICON_TCOORDS = nil
        assert.is_nil(ns.UI.ApplyPortrait(frame))
        _G.CLASS_ICON_TCOORDS = coords
    end)

    it("redraws the ring when the player changes specialization", function()
        world.spec = { index = 2, id = 103, name = "Feral", icon = 132115, role = "DAMAGER" }
        world.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.equal(132115, frame.PortraitContainer.portrait:GetTexture())
        assert.equal(132115, ns.UI.minimapButton.icon:GetTexture())
    end)

    it("hangs the tabs off the frame's bottom edge", function()
        local point = frame.tabs[1].points[1]
        assert.equal("TOPLEFT", point[1])
        assert.equal(frame, point[2])
        assert.equal("BOTTOMLEFT", point[3])
        -- the other two still hang off the one before them
        assert.equal("LEFT", frame.tabs[2].points[1][1])
        assert.equal(frame.tabs[1], frame.tabs[2].points[1][2])
    end)

    -- M5-2b (WKE-601): the owner's words on 2026-09-16 - "the copy is being
    -- covered by the Spec symbol in the top left corner - let's move it down".
    -- The strip is a full-width row BELOW the portrait ring, which Blizzard's
    -- own template puts 55 points under the frame's top edge.
    it("puts the status strip on its own full-width row below the portrait ring", function()
        local left, right = frame.statusStrip.points[1], frame.statusStrip.points[2]
        assert.equal("TOPLEFT", left[1])
        assert.equal(frame, left[2])
        assert.equal("TOPRIGHT", right[1])
        assert.equal(frame, right[2])
        -- one row, both ends at the same height, and that height is under the
        -- ring rather than beside it
        assert.equal(-ns.UI.STRIP_TOP, left[5])
        assert.equal(-ns.UI.STRIP_TOP, right[5])
        assert.is_true(ns.UI.STRIP_TOP > ns.UI.RING_BOTTOM)
    end)

    it("runs each panel from under the strip to the frame's own bottom", function()
        for _, tab in ipairs(ns.UI.TABS) do
            local panel = frame[tab.key]
            assert.equal(frame.statusStrip, panel.points[1][2])
            assert.equal("BOTTOMLEFT", panel.points[1][3])
            assert.equal(frame, panel.points[2][2])
        end
    end)
end)

describe("the window's width (M5-2c)", function()
    local ns, world, frame

    -- The x offset of the first point a frame was given under this name.
    local function offsetOf(widget, name)
        for _, point in ipairs(widget.points) do
            if point[1] == name then
                return point[4]
            end
        end
        return nil
    end

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("is the 760 the owner chose, and is still 640 tall", function()
        assert.equal(760, ns.UI.WIDTH)
        assert.equal(760, frame:GetWidth())
        assert.equal(640, ns.UI.HEIGHT)
        assert.equal(640, frame:GetHeight())
    end)

    it("gives every tab's panel exactly the width its own two anchors make", function()
        -- What the window hands a panel, worked out from the anchors and from
        -- nothing else: the strip's left edge, plus the panel's own offset off
        -- the strip's BOTTOMLEFT, across to the panel's BOTTOMRIGHT offset off
        -- the frame's right edge.
        local left = offsetOf(frame.statusStrip, "TOPLEFT") + offsetOf(frame.equipPanel, "TOPLEFT")
        local right = ns.UI.WIDTH + offsetOf(frame.equipPanel, "BOTTOMRIGHT")
        assert.equal(right - left, ns.UI.PANEL_WIDTH)
        -- and every panel is that wide on its own, so a panel the render tests
        -- build without a window is the size the window would have made it
        for _, tab in ipairs(ns.UI.TABS) do
            assert.equal(ns.UI.PANEL_WIDTH, frame[tab.key]:GetWidth())
        end
    end)

    it("derives the Equip Now rows from the panel rather than from a number", function()
        local panel = frame.equipPanel
        ns.UI.RefreshEquip(frame)
        assert.equal(panel:GetWidth() - ns.UI.EquipPanel.ROW_INSET, panel.rowWidth)
        assert.equal(panel.rowWidth, panel.list:GetWidth())
        -- and it follows the panel, rather than the width Create happened to
        -- start it at
        panel:SetWidth(400)
        ns.UI.RefreshEquip(frame)
        assert.equal(400 - ns.UI.EquipPanel.ROW_INSET, panel.rowWidth)
        assert.equal(panel.rowWidth, panel.list:GetWidth())
    end)
end)

describe("the status strip (M5-2)", function()
    local ns, world, frame

    local function importDungeon()
        frame.pasteBox:SetText(readFile(DUNGEON_EXPORT))
        frame.importButton:Click()
        return ns.QEImport.Current()
    end

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
        frame:Show()
    end)

    after_each(function()
        H.unload()
    end)

    -- C-9 (WKE-559): the sixth fact. With the committed placeholder in place -
    -- which is what every test here loads - the companion has never run, and
    -- the strip says so rather than leaving the line to be read as "fine".
    it("says there is nothing yet before anything is imported", function()
        local expected = ns.UI.NO_VERDICT_STRIP .. ns.UI.SEPARATOR .. ns.Companion.STATUS_NEVER
        assert.equal(expected, ns.UI.RefreshStrip(frame).text)
        assert.equal(expected, frame.stripText:GetText())
    end)

    -- Four facts since V-2 (WKE-573), not five: the content type and the
    -- export's name came off the line into the tooltip's own sentence, so the
    -- companion clause is not the half the window's width cuts (R-3a, WKE-570).
    --
    -- The clock is PINNED here, and it has to be. `UI.StatusStripModel` reads
    -- staleness off the real `time()` when no caller gives it one, and the
    -- committed export this test pastes was written at 2026-09-06T21:14:24Z -
    -- so "is this verdict from before the last weekly reset" stopped being
    -- false at a wall-clock instant, and the assertion below started failing on
    -- `main` in the small hours of 2026-09-16 UTC with nothing having changed.
    -- V-4's modelled clock (WKE-589) is what makes the question answerable
    -- again: `now` is an hour after the export, inside its own week, so the
    -- test asks what it always meant to ask.
    it("names the spec, the source, the scenario and the companion over a pasted one", function()
        H.chicagoClock(world, 1788729264 + 3600)
        importDungeon()
        local model = ns.UI.RefreshStrip(frame)
        assert.is_false(model.stale)
        local parts = {}
        for part in (model.text .. ns.UI.SEPARATOR):gmatch("(.-)\194\183") do
            parts[#parts + 1] = (part:gsub("^%s+", ""):gsub("%s+$", ""))
        end
        assert.equal(4, #parts)
        assert.equal("Restoration Druid", parts[1])
        assert.is_truthy(parts[2]:find("^pasted, exported "))
        -- the default highlight is M3-13's `thisWeek` (WKE-548)
        assert.equal(ns.UI.SCENARIO_TAG[ns.QEImport.DEFAULT_SCENARIO], "vault pick: as offered")
        assert.equal("vault pick: this week", parts[3])
        assert.equal(ns.Companion.STATUS_NEVER, parts[4])

        -- and the two words really are gone from the line and kept in the
        -- tooltip: moved, not lost.
        assert.is_nil(model.text:find("Dungeon", 1, true))
        assert.is_nil(model.text:find("Top Gear", 1, true))
        assert.is_truthy(table.concat(model.tooltip, "\n"):find("Dungeon Top Gear export", 1, true))
    end)

    -- M5-2b (WKE-601). The owner's screen on 2026-09-16 ended
    -- `... companion: pr...`: the row was too narrow for four facts and the
    -- client cut the last one mid-word. A narrow row now shows FEWER WHOLE
    -- clauses - never a partial one - and the line entire goes to the tooltip,
    -- so the fact that came off the row is one hover away.
    it("drops whole clauses from the right when the row is too narrow", function()
        H.chicagoClock(world, 1788729264 + 3600)
        importDungeon()
        local whole = ns.UI.StatusStripModel().parts
        assert.equal(4, #whole)
        local function width(count)
            return #table.concat(whole, ns.UI.SEPARATOR, 1, count) * Stub.CHAR_WIDTH
        end

        -- Room for every fact: the line is the line, and nothing is repeated
        -- into the tooltip.
        frame.stripText:SetWidth(width(4))
        local model = ns.UI.RefreshStrip(frame)
        assert.equal(4, model.shownClauses)
        assert.equal(table.concat(whole, ns.UI.SEPARATOR), frame.stripText:GetText())
        assert.is_nil(model.tooltip[1]:find(whole[4], 1, true))

        -- One character less than the whole line needs: the LAST fact comes
        -- off, whole, and the three in front of it are untouched.
        frame.stripText:SetWidth(width(4) - Stub.CHAR_WIDTH)
        model = ns.UI.RefreshStrip(frame)
        assert.equal(3, model.shownClauses)
        assert.equal(table.concat(whole, ns.UI.SEPARATOR, 1, 3), frame.stripText:GetText())
        assert.is_nil(frame.stripText:GetText():find(whole[4], 1, true))
        -- and the whole line is the tooltip's first line, so the clause that
        -- came off the row is one hover away
        assert.equal(table.concat(whole, ns.UI.SEPARATOR), model.tooltip[1])

        -- Narrower still: two facts, then one. The first clause always stays,
        -- even when the row cannot hold it.
        frame.stripText:SetWidth(width(2))
        assert.equal(2, ns.UI.RefreshStrip(frame).shownClauses)
        frame.stripText:SetWidth(width(1))
        assert.equal(1, ns.UI.RefreshStrip(frame).shownClauses)
        frame.stripText:SetWidth(1)
        assert.equal(1, ns.UI.RefreshStrip(frame).shownClauses)
        assert.equal(whole[1], frame.stripText:GetText())
    end)

    -- A row that has not been laid out yet - and every headless caller - reads
    -- exactly as it did before the fit existed.
    it("shortens nothing when there is no width to fit into", function()
        H.chicagoClock(world, 1788729264 + 3600)
        importDungeon()
        frame.stripText:SetWidth(0)
        local model = ns.UI.RefreshStrip(frame)
        assert.equal(#model.parts, model.shownClauses)
        assert.equal(model.text, frame.stripText:GetText())
    end)

    -- The five states of the companion's own file, on the line the owner is
    -- already reading. Each one is the answer to a question the window could not
    -- answer before C-9: did it run, is it running, did it die, did it have
    -- nothing to do.
    it("says what the companion last did, in one clause per state", function()
        importDungeon()
        local now = ns.EpochFromISO("2026-09-13T22:51:00Z")
        local function clause(status)
            ns.companionStatus = status
            return ns.UI.StatusStripModel(now).companion
        end

        assert.equal(
            "companion: wrote 3 minutes ago",
            clause({
                state = "idle",
                verdictWrittenAt = "2026-09-13T22:48:00Z",
                finishedAt = "2026-09-13T22:48:01Z",
            })
        )
        assert.equal(
            "companion: profile unchanged, no run (" .. date("%H:%M", ns.EpochFromISO("2026-09-13T22:06:00Z")) .. ")",
            clause({ state = "skipped", finishedAt = "2026-09-13T22:06:00Z" })
        )
        assert.equal(
            "companion: FAILED at profile ("
                .. date("%H:%M", ns.EpochFromISO("2026-09-13T21:06:00Z"))
                .. ") - see companion.log",
            clause({ state = "failed", stage = "profile", finishedAt = "2026-09-13T21:06:00Z" })
        )
        assert.equal(
            "companion: run started " .. date("%H:%M", ns.EpochFromISO("2026-09-13T22:48:00Z")),
            clause({ state = "running", startedAt = "2026-09-13T22:48:00Z", stage = "qe live" })
        )
        assert.equal(ns.Companion.STATUS_NEVER, clause(nil))
        assert.equal(ns.Companion.STATUS_UNREADABLE, clause({ state = "exploded" }))

        -- and the clause really is the last thing on the line, not only a field
        ns.companionStatus = { state = "failed", stage = "qe live", finishedAt = "2026-09-13T21:06:00Z" }
        local model = ns.UI.StatusStripModel(now)
        assert.is_truthy(model.text:find("companion: FAILED at qe live", 1, true))
        assert.is_truthy(model.text:find(" - see companion.log", 1, true))
    end)

    it("puts the companion's own sentence in the tooltip, last", function()
        importDungeon()
        ns.companionStatus = {
            state = "failed",
            stage = "qe live",
            message = "the fork did not answer http://localhost:3000",
            finishedAt = "2026-09-13T21:06:00Z",
        }
        local model = ns.UI.StatusStripModel(ns.EpochFromISO("2026-09-13T22:51:00Z"))
        -- Last of the FACTS. Since UX-4b the version is one line below it, which
        -- is a label and not a fact about the export.
        local last = model.tooltip[#model.tooltip - 1]
        assert.is_truthy(last:find("The companion's last run: the fork did not answer", 1, true))
        assert.equal(ns.UI.VersionText(), model.tooltip[#model.tooltip])
    end)

    it("ends the strip's tooltip with the version, with an export and without one", function()
        -- UX-4b: the title carries the name-mark and no words, so this is the
        -- one place the build is written down. Both branches of the model put it
        -- last, so a reader always finds it in the same place.
        local empty = ns.UI.StatusStripModel(ns.EpochFromISO("2026-09-13T22:51:00Z"))
        assert.equal("Lootpath 0.0.0-test", empty.tooltip[#empty.tooltip])

        importDungeon()
        local full = ns.UI.StatusStripModel(ns.EpochFromISO("2026-09-13T22:51:00Z"))
        assert.equal("Lootpath 0.0.0-test", full.tooltip[#full.tooltip])

        -- And it is never on the strip's own line, which is for facts that
        -- change.
        assert.is_nil(full.text:find("Lootpath 0.0.0-test", 1, true))
    end)

    it("says the companion wrote it, and how long ago", function()
        local verdict = importDungeon()
        verdict.source = ns.Companion.SOURCE_COMPANION
        verdict.companionWrittenAt = "2026-09-09T12:00:00.000Z"
        local now = ns.EpochFromISO("2026-09-09T12:04:00.000Z")
        local model = ns.UI.StatusStripModel(now)
        assert.is_truthy(model.text:find("companion, written 4 minutes ago", 1, true))
        -- and not the exported age as well: the source says one age, not two
        assert.is_nil(model.text:find("exported", 1, true))
    end)

    it("turns the age amber when the export predates the client's own weekly reset", function()
        local verdict = importDungeon()
        local now = ns.EpochFromISO("2026-09-09T12:00:00.000Z")
        world.secondsUntilReset = 3600
        verdict.exportedAt = "2026-08-20T12:00:00.000Z"
        local model = ns.UI.StatusStripModel(now)
        assert.is_true(model.stale)
        assert.is_truthy(model.text:find("|cffffd43b", 1, true))
        assert.same(ns.UI.STALE_STRIP_TOOLTIP, model.tooltip[2])

        -- and an export made since that reset is not amber
        verdict.exportedAt = "2026-09-08T12:00:00.000Z"
        local fresh = ns.UI.StatusStripModel(now)
        assert.is_false(fresh.stale)
        assert.is_nil(fresh.text:find("|cffffd43b", 1, true))
    end)

    it("says nothing about staleness when the client will not say when the reset is", function()
        local verdict = importDungeon()
        verdict.exportedAt = "2026-08-20T12:00:00.000Z"
        world.secondsUntilReset = nil
        local model = ns.UI.StatusStripModel(ns.EpochFromISO("2026-09-09T12:00:00.000Z"))
        assert.is_nil(model.stale)
        assert.is_nil(model.text:find("|cffffd43b", 1, true))
    end)

    -- V-2 (WKE-573): the line measured against the one measurement that exists.
    --
    -- The stub has no pixels (ARCHITECTURE.md 9, said of every M5 surface), and
    -- this repo holds no screenshot a headless test could measure, so the budget
    -- is not read off font metrics: it is the owner's OWN cut line, counted in
    -- characters. ARCHITECTURE.md 11 records what his screen showed at the
    -- window's default width on 2026-09-14, after V-1 and before this change:
    --
    --   Restoration Druid - Dungeon Top Gear - companion, written 5 day(s) ago
    --   - vault pick: this week - compani
    --
    -- which is 104 characters before the cut. The font is proportional, so 104
    -- characters is a PROXY and a LOWER bound on the width the strip really
    -- has - which is exactly what makes it safe to assert against: a line at or
    -- under it was within a width the owner's screen has already been seen to
    -- draw. It is not a pixel claim, and this test does not make one.
    local STRIP_BUDGET_CHARS = 104

    -- UTF-8 characters, not bytes: the separator is two bytes and the line
    -- carries three of them.
    local function charCount(text)
        return #text - select(2, text:gsub("[\128-\191]", ""))
    end

    it("fits the whole companion clause inside the width the owner's own screen drew", function()
        local verdict = importDungeon()
        -- The owner's 2026-09-14 state, as ARCHITECTURE.md 11 recorded it: the
        -- companion wrote the export, five days before he looked at it.
        verdict.source = ns.Companion.SOURCE_COMPANION
        verdict.companionWrittenAt = "2026-09-09T07:00:00.000Z"
        ns.companionStatus = {
            state = "idle",
            verdictWrittenAt = "2026-09-09T07:00:00.000Z",
            finishedAt = "2026-09-09T07:00:01Z",
        }
        local now = ns.EpochFromISO("2026-09-14T07:00:00.000Z")
        local model = ns.UI.StatusStripModel(now)

        -- the clause is whole, and it is the end of the line
        assert.equal("companion: wrote 5 days ago", model.companion)
        assert.is_truthy(model.text:find(model.companion, 1, true))
        assert.equal(#model.text - #model.companion + 1, model.text:find(model.companion, 1, true))

        -- and the whole line is inside the budget the owner's screen measured
        assert.is_true(
            charCount(model.text) <= STRIP_BUDGET_CHARS,
            string.format("%d characters, budget %d: [%s]", charCount(model.text), STRIP_BUDGET_CHARS, model.text)
        )

        -- The proof that the dropped fact is what bought the room: put
        -- `Dungeon Top Gear` back where it sat and the same line is over the
        -- budget again, by the 19 characters of the fact and its separator -
        -- which is the cut the owner read.
        local before = model.text:gsub("^(.-)(" .. ns.UI.SEPARATOR .. ")", "%1%2Dungeon Top Gear%2", 1)
        assert.equal(charCount(model.text) + 19, charCount(before))
        assert.is_true(charCount(before) > STRIP_BUDGET_CHARS)
    end)

    -- What V-2 does NOT fix, said out loud rather than left to be discovered:
    -- the longest companion clause is half as long again as the line has room
    -- for, and dropping one fact cannot make it fit. The reader of a failed run
    -- is sent to the tooltip, which carries the companion's whole sentence.
    it("cannot fit the longest companion clause, and keeps it whole in the tooltip", function()
        local verdict = importDungeon()
        verdict.source = ns.Companion.SOURCE_COMPANION
        verdict.companionWrittenAt = "2026-09-09T07:00:00.000Z"
        ns.companionStatus = {
            state = "failed",
            stage = "qe live",
            message = "the fork did not answer http://localhost:3000",
            finishedAt = "2026-09-09T07:00:01Z",
        }
        local model = ns.UI.StatusStripModel(ns.EpochFromISO("2026-09-14T07:00:00.000Z"))
        assert.is_true(charCount(model.text) > STRIP_BUDGET_CHARS)
        assert.is_truthy(table.concat(model.tooltip, "\n"):find("the fork did not answer", 1, true))
    end)

    it("puts the other stored export in the strip's tooltip, not on the line", function()
        importDungeon()
        frame.pasteBox:SetText(readFile(UF_DUNGEON_EXPORT))
        frame.importButton:Click()
        local model = ns.UI.RefreshStrip(frame)
        assert.is_nil(model.text:find("Upgrade Finder", 1, true))
        local joined = table.concat(model.tooltip, "\n")
        assert.is_truthy(joined:find("Also stored:", 1, true))
        assert.is_truthy(joined:find("Upgrade Finder", 1, true))

        frame.statusStrip:GetScript("OnEnter")(frame.statusStrip)
        assert.is_truthy(world.tooltip.stub:Text():find("Also stored:", 1, true))
    end)

    it("follows the vault scenario setting", function()
        importDungeon()
        assert.is_truthy(ns.UI.RefreshStrip(frame).text:find("vault pick: this week", 1, true))
        ns.UI.Options.SetVaultScenario("catalyzed")
        assert.is_truthy(ns.UI.RefreshStrip(frame).text:find("vault pick: catalyzed", 1, true))
    end)
end)

-- R-6 (WKE-578): the nudge, on the window and on the launcher.
--
-- The drift itself is spec/drift_spec.lua's, over the owner's own 2026-09-14
-- gear. What is measured HERE is only the wiring: the second row appears and
-- goes, the strip carries it in its own height so the body moves with it, the
-- click reaches the refresh, and the launcher's badge and tooltip say the same
-- thing the row does.
describe("the nudge row (R-6)", function()
    local ns, world, frame

    -- The drift is stated directly rather than replayed, because this file is
    -- about the widgets; drift_spec drives the real scan over the real capture.
    local function behind(count, name)
        ns.Drift.SetBehind({ count = count, name = name })
    end

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
        frame:Show()
    end)

    after_each(function()
        H.unload()
    end)

    it("is not there at all while the plan and the gear agree", function()
        ns.UI.RefreshStrip(frame)
        assert.is_false(frame.nudgeButton:IsShown())
        assert.equal(ns.UI.STRIP_HEIGHT, frame.statusStrip.height)
    end)

    it("appears as a second row, and the strip grows so the body moves down with it", function()
        behind(2, "Lightgrasp Worldroot")
        ns.UI.RefreshStrip(frame)
        assert.is_true(frame.nudgeButton:IsShown())
        assert.equal(
            "your gear changed since this rating (2 items) \194\183 click to refresh",
            frame.nudgeButton.label.text
        )
        assert.equal(ns.UI.STRIP_HEIGHT + ns.UI.NUDGE_HEIGHT, frame.statusStrip.height)
        -- every tab's panel hangs off the strip's bottom edge, so nothing has to
        -- be moved by hand for the row to fit
        for _, tab in ipairs(ns.UI.TABS) do
            assert.equal(frame.statusStrip, frame[tab.key].points[1][2])
            assert.equal("BOTTOMLEFT", frame[tab.key].points[1][3])
        end
    end)

    it("names the newest arrival on its hover, and the line again above it", function()
        behind(1, "Lightgrasp Worldroot")
        ns.UI.RefreshStrip(frame)
        frame.nudgeButton:GetScript("OnEnter")(frame.nudgeButton)
        local shown = world.tooltip.stub:Text()
        assert.is_truthy(shown:find("click to refresh", 1, true))
        assert.is_truthy(shown:find("Lightgrasp Worldroot", 1, true))
    end)

    it("runs the refresh when it is clicked, and writes the stamp the wait counts from", function()
        -- A wait stands only where a companion has been seen (R-6a).
        ns.companionStatus = { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
        behind(1, "Lightgrasp Worldroot")
        ns.UI.RefreshStrip(frame)
        assert.equal(0, world.reloads)
        frame.nudgeButton:Click()
        assert.equal(1, world.reloads)
        assert.is_string(ns.db.global.drift.refreshStartedAt)
        for _, name in ipairs(ns.Companion.REFRESH_CAPTURES) do
            assert.is_truthy(ns.db.global.captures[name] and #ns.db.global.captures[name] > 0, name)
        end
    end)

    it("goes away again once the nudge has nothing to say", function()
        behind(1, "Lightgrasp Worldroot")
        ns.UI.RefreshStrip(frame)
        assert.is_true(frame.nudgeButton:IsShown())
        ns.Drift.SetBehind(nil)
        ns.UI.RefreshStrip(frame)
        assert.is_false(frame.nudgeButton:IsShown())
        assert.equal(ns.UI.STRIP_HEIGHT, frame.statusStrip.height)
    end)

    it("leaves the four facts on the first row exactly as they were", function()
        behind(3, "Lightgrasp Worldroot")
        local model = ns.UI.RefreshStrip(frame)
        assert.is_nil(model.text:find("click to refresh", 1, true))
        assert.equal(model.text, frame.stripText.text)
    end)

    it("badges the launcher while the gear has moved, and says the same words on its tooltip", function()
        local button = ns.UI.MinimapButton()
        assert.is_false(button.driftDot:IsShown())
        behind(1, "Lightgrasp Worldroot")
        ns.UI.RefreshMinimapDot()
        assert.is_true(button.driftDot:IsShown())
        assert.is_true(button.driftDotAccent:IsShown())
        button:GetScript("OnEnter")(button)
        assert.is_truthy(world.tooltip.stub:Text():find("click to refresh", 1, true))
        ns.Drift.SetBehind(nil)
        ns.UI.RefreshMinimapDot()
        assert.is_false(button.driftDot:IsShown())
    end)

    it("draws the badge as the Waymark in the brand colour, and leaves the launcher's icon alone", function()
        local button = ns.UI.MinimapButton()

        -- UX-4b: the badge is the mark, not a flat square, in both layers.
        -- UX-4c: it is the same PAIR the bag corner draws - the keyline file
        -- under the fill file - so the badge, the bag, the compartment entry and
        -- the listing tile are one shape.
        assert.equal(ns.UI.MEDIA.MARK16_EDGE, button.driftDot:GetTexture())
        assert.equal(ns.UI.MEDIA.MARK16_FILL, button.driftDotAccent:GetTexture())
        assert.equal(ns.UI.Bags.Baganator.EDGE_TEXTURE, button.driftDot:GetTexture())
        assert.equal(ns.UI.Bags.Baganator.FILL_TEXTURE, button.driftDotAccent:GetTexture())
        assert.is_nil(button.driftDot:GetAtlas())
        assert.is_nil(button.driftDotAccent:GetAtlas())
        -- The 16-point drawing and never mark64: R-6 draws this at 9 points, and
        -- R-2b is the rule that a mark is drawn at the size it will be seen at.
        assert.are_not.equal(ns.UI.MEDIA.MARK64, button.driftDot:GetTexture())
        assert.are_not.equal(ns.UI.MEDIA.MARK64, button.driftDotAccent:GetTexture())

        -- The accent is the brand, no longer QE Live's gold; the keyline is the
        -- one near-black every tinted Waymark is outlined in, no longer this
        -- badge's own flat black.
        local r, g, b = ns.UI.ItemLine.RGB(ns.UI.BRAND_HEX)
        assert.same({ r, g, b, nil }, button.driftDotAccent.vertexColor)
        assert.same(ns.UI.MARK_EDGE_COLOR, button.driftDot.vertexColor)
        assert.are_not.same({ 0, 0, 0, 1 }, button.driftDot.vertexColor)

        -- R-6's geometry is untouched: the size and the corner are R-6's own.
        assert.equal(ns.UI.MINIMAP_DOT_SIZE, button.driftDot.width)
        assert.same({ "TOPRIGHT", button, "TOPRIGHT", -4, -4 }, button.driftDot.points[1])

        -- UX-4c: the two layers are the SAME size at the SAME anchor, no offset
        -- and no shrunken accent. The keyline is dilated into the edge file now,
        -- so shrinking the fill by two points would only eat the chevrons.
        assert.equal(ns.UI.MINIMAP_DOT_SIZE, button.driftDotAccent.width)
        assert.equal(button.driftDot.width, button.driftDotAccent.width)
        assert.equal(button.driftDot.height, button.driftDotAccent.height)
        assert.same({ "CENTER", button.driftDot, "CENTER", 0, 0 }, button.driftDotAccent.points[1])
        assert.is_nil(button.driftDotAccent.points[2])

        -- 593 stands: the launcher's own icon is the character's spec icon and
        -- no mark of ours went onto it.
        assert.are_not.equal(ns.UI.MEDIA.MARK16_EDGE, button.icon:GetTexture())
        assert.are_not.equal(ns.UI.MEDIA.MARK16_FILL, button.icon:GetTexture())
        assert.are_not.equal(ns.UI.MEDIA.MARK64, button.icon:GetTexture())
        assert.same({ 0.05, 0.95, 0.05, 0.95 }, button.icon.texCoord)
    end)

    -- M3-16b (WKE-583): the wait is the STRIP's, not the row's, and the badge
    -- stays up for it. R-6 kept the badge off during the wait on the argument
    -- that a player who is waiting has already clicked; the owner's own words
    -- on 2026-09-15 are that with the window shut he has no way to know the
    -- refresh is still happening, and the launcher is the only surface left.
    -- Proven red by putting `model.kind == "behind"` back into
    -- `UI.RefreshMinimapDot`: the badge goes out and the first assertion fails;
    -- and by drawing the wait on the nudge row again: the second fails.
    it("keeps the badge on the launcher while the rating is being made, and draws no second row", function()
        local button = ns.UI.MinimapButton()
        behind(1, "Lightgrasp Worldroot")
        ns.companionStatus = { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
        ns.db.global.drift.refreshStartedAt = date("!%Y-%m-%dT%H:%M:%SZ", math.floor(time()))
        local model = ns.UI.RefreshStrip(frame)
        assert.is_true(button.driftDot:IsShown())
        assert.is_false(frame.nudgeButton:IsShown())
        assert.equal(ns.UI.STRIP_HEIGHT, frame.statusStrip.height)
        assert.is_truthy(model.text:find("rating your gear", 1, true))
        -- and the launcher's hover says it once, not twice
        button:GetScript("OnEnter")(button)
        local _, saidTwice = world.tooltip.stub:Text():gsub("rating your gear", "")
        assert.equal(1, saidTwice)
    end)
    -- C-14 (WKE-603): the nudge row hovers as ONE line, and never the strip's.
    --
    -- The owner photographed a tooltip the height of his screen ending in
    -- Playwright's call log. The companion's note belongs to the STRIP,
    -- one row up, and this is the guard that the nudge row cannot inherit it:
    -- with a status file carrying a dump, the row's hover is its own line and the
    -- newest arrival, and nothing else at all.
    --
    -- Proven red by giving the row the strip's tooltip lines: the companion's
    -- sentence lands on it and every assertion below fails at once.
    it("hovers as the nudge alone, with no companion note on it", function()
        ns.companionStatus = {
            state = "failed",
            stage = "qe live",
            message = "driving QE Live failed: locator.click: Timeout 20000ms exceeded.",
            finishedAt = "2026-09-14T22:48:41Z",
        }
        behind(1, "Lightgrasp Worldroot")
        ns.UI.RefreshStrip(frame)
        frame.nudgeButton:GetScript("OnEnter")(frame.nudgeButton)
        local shown = world.tooltip.stub:Text()
        assert.is_truthy(shown:find("click to refresh", 1, true))
        assert.is_truthy(shown:find("Lightgrasp Worldroot", 1, true))
        assert.is_nil(shown:find("companion", 1, true))
        assert.is_nil(shown:find("locator.click", 1, true))
        -- and the STRIP, one row up, is where that sentence really lives
        frame.statusStrip:GetScript("OnEnter")(frame.statusStrip)
        assert.is_truthy(world.tooltip.stub:Text():find("locator.click", 1, true))
    end)
end)

-- M3-16b (WKE-583): the wait indicator, on the strip's own row.
--
-- The owner's screen on 2026-09-15 read `...on Druid - companion, written 4
-- hours ago - vault pick: everything upgraded - companion: run st...`, cut at
-- the window's width, and R-6's `rating your gear ... click to load it` was
-- below it and past the cut, so he could not find it and assumed the refresh
-- had finished. What is measured here is that the wait line is the FIRST thing
-- on the strip and fits inside the width his own screen drew.
describe("the wait on the strip (M3-16b)", function()
    local ns, world, frame

    local function importDungeon()
        frame.pasteBox:SetText(readFile(DUNGEON_EXPORT))
        frame.importButton:Click()
        return ns.QEImport.Current()
    end

    -- The same budget, and the same reasoning, as the V-2 test above: the
    -- owner's own cut line counted in characters, a proxy and a lower bound on
    -- the width the strip really has, never a pixel claim.
    local STRIP_BUDGET_CHARS = 104

    local function charCount(text)
        return #text - select(2, text:gsub("[\128-\191]", ""))
    end

    local function waiting()
        ns.db.global.drift = ns.db.global.drift or {}
        ns.db.global.drift.refreshStartedAt = date("!%Y-%m-%dT%H:%M:%SZ", math.floor(time()))
    end

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        -- R-6a (WKE-590): a wait stands only where a companion has been SEEN.
        -- With no status file at all the load line answers `the companion
        -- hasn't been seen` and the strip stops counting, so the world these
        -- draw in carries the previous run a real machine carries. Set here
        -- rather than in `waiting`, because the line the wait DISPLACES is read
        -- before the wait starts and it carries C-9's clause too.
        ns.companionStatus = { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
        frame = ns.UI.Frame()
        frame:Show()
    end)

    after_each(function()
        H.unload()
    end)

    -- Proven red by appending the wait to the line instead of leading with it
    -- (`parts[#parts + 1] = wait.text`): the line starts with the spec and the
    -- wait line is no longer at character 1.
    it("puts the wait line first, whole, and inside the width the owner's screen drew", function()
        importDungeon()
        waiting()
        local model = ns.UI.RefreshStrip(frame)
        assert.is_table(model.wait)
        assert.equal(model.wait.text, model.text)
        assert.equal(1, model.text:find("rating your gear", 1, true))
        assert.equal(model.text, frame.stripText.text)
        assert.is_true(
            charCount(model.text) <= STRIP_BUDGET_CHARS,
            string.format("%d characters, budget %d: [%s]", charCount(model.text), STRIP_BUDGET_CHARS, model.text)
        )
        -- The whole wait clause is inside the first N characters, which is the
        -- part of the line the owner's screen has been seen to draw.
        assert.is_truthy(model.text:sub(1, STRIP_BUDGET_CHARS):find("click to load it", 1, true))
    end)

    -- The facts it displaced are moved, not lost - the same trade V-2 made with
    -- the content type.
    it("keeps the four facts it displaced, in the strip's own tooltip", function()
        importDungeon()
        local before = ns.UI.RefreshStrip(frame).text
        waiting()
        local model = ns.UI.RefreshStrip(frame)
        assert.is_nil(model.text:find("vault pick", 1, true))
        local tooltip = table.concat(model.tooltip, "\n")
        assert.is_truthy(tooltip:find(before, 1, true))
        assert.is_truthy(tooltip:find(ns.Drift.WAIT_TOOLTIP, 1, true))
    end)

    -- The row the sentence is written on is the row that answers the click, so
    -- `click to load it` is true of it. Proven red by returning nil from
    -- `UI.StripClick`: nothing reloads.
    it("reloads when the strip is clicked, and does nothing when there is no wait", function()
        importDungeon()
        ns.UI.RefreshStrip(frame)
        frame.statusStrip:GetScript("OnMouseUp")(frame.statusStrip)
        assert.equal(0, world.reloads)
        waiting()
        ns.UI.RefreshStrip(frame)
        frame.statusStrip:GetScript("OnMouseUp")(frame.statusStrip)
        assert.equal(1, world.reloads)
    end)

    -- With nothing imported at all the line is still the wait's: an empty
    -- window that is waiting has exactly one thing to say.
    it("leads with the wait even with no export on this character", function()
        waiting()
        local model = ns.UI.RefreshStrip(frame)
        assert.equal(1, model.text:find("rating your gear", 1, true))
        assert.is_truthy(table.concat(model.tooltip, "\n"):find(ns.UI.NO_VERDICT_STRIP, 1, true))
    end)
end)

-- R-8 (WKE-616): the strip's refresh is a button.
--
-- The owner read his own strip on 2026-09-18 - `your gear wasn't read at logout
-- - last rated 15 hours ago \194\183 /lootpath refresh to rate what you wear now` -
-- and said "we should just make this a button that will run that command for
-- the user when they click it." So the command comes off the strip and a third
-- button goes on the row beside `Import...` and `Options`, running exactly what
-- the chat command runs.
describe("the Refresh button on the strip (R-8)", function()
    local ns, world, frame

    local GUARDIAN = { index = 3, id = 104, name = "Guardian", icon = 132276, role = "TANK" }

    local function waiting()
        ns.db.global.drift = ns.db.global.drift or {}
        ns.db.global.drift.refreshStartedAt = date("!%Y-%m-%dT%H:%M:%SZ", math.floor(time()))
    end

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        -- A wait stands only where a companion has been seen (R-6a).
        ns.companionStatus = { state = "idle", startedAt = "2026-09-14T22:48:00Z", finishedAt = "2026-09-14T22:48:41Z" }
        frame = ns.UI.Frame()
        frame:Show()
    end)

    after_each(function()
        H.unload()
    end)

    -- Proven red by anchoring the button to the strip's RIGHT instead of to
    -- `Import...`'s LEFT: it lands on top of Options.
    it("is the third button on the strip's row, left of Import and Options", function()
        assert.is_table(frame.refreshButton)
        assert.equal("Refresh", frame.refreshButton:GetText())
        -- a FRAME child like the other two (H-1a), so the Coming soon screen
        -- cannot take it off with the strip
        assert.equal(frame, frame.refreshButton:GetParent())
        assert.equal(frame.openImportButton, frame.refreshButton.points[1][2])
        assert.equal("LEFT", frame.refreshButton.points[1][3])
        -- the same height as the two it sits beside
        assert.equal(frame.openImportButton.height, frame.refreshButton.height)
        -- and the line of facts now stops at IT, not at Import
        assert.equal(frame.refreshButton, frame.stripText.points[2][2])
    end)

    -- Proven red by making the OnClick a no-op: nothing is captured and nothing
    -- reloads.
    it("runs what /lootpath refresh runs: the captures, the stamp and the reload", function()
        assert.equal(0, world.reloads)
        frame.refreshButton:Click()
        assert.equal(1, world.reloads)
        assert.is_string(ns.db.global.drift.refreshStartedAt)
        for _, name in ipairs(ns.Companion.REFRESH_CAPTURES) do
            assert.is_truthy(ns.db.global.captures[name] and #ns.db.global.captures[name] > 0, name)
        end
    end)

    -- The same function the strip's wait click reaches (`Drift.Click`), so a
    -- rating that is already being made is LOADED rather than asked for twice.
    it("loads instead of asking again while a rating is out there", function()
        waiting()
        local stamp = ns.db.global.drift.refreshStartedAt
        ns.UI.RefreshStrip(frame)
        frame.refreshButton:Click()
        assert.equal(1, world.reloads)
        -- the wait's own stamp is untouched: nothing was asked for a second time
        assert.equal(stamp, ns.db.global.drift.refreshStartedAt)
        assert.is_nil(ns.db.global.captures.inventory)
    end)

    it("says on its hover what this press will do, in this state", function()
        frame.refreshButton:GetScript("OnEnter")(frame.refreshButton)
        assert.equal(ns.Drift.REFRESH_TOOLTIP, world.tooltip.stub:Text())
        world.tooltip:ClearLines()
        waiting()
        frame.refreshButton:GetScript("OnEnter")(frame.refreshButton)
        assert.equal(ns.Drift.REFRESH_TOOLTIP_WAIT, world.tooltip.stub:Text())
    end)

    -- Proven red by dropping the `SetEnabled` out of `UI.RefreshStrip`: the
    -- button stays lit in combat and the click reaches `Companion.Refresh`.
    it("greys out in combat, and the press does nothing there", function()
        world.inCombat = true
        ns.UI.RefreshStrip(frame)
        assert.is_false(frame.refreshButton:IsEnabled())
        frame.refreshButton:Click()
        assert.equal(0, world.reloads)
        world.tooltip:ClearLines()
        frame.refreshButton:GetScript("OnEnter")(frame.refreshButton)
        assert.equal(ns.Drift.REFRESH_TOOLTIP_COMBAT, world.tooltip.stub:Text())
        -- and it comes back when the fight is over
        world.inCombat = false
        ns.UI.RefreshStrip(frame)
        assert.is_true(frame.refreshButton:IsEnabled())
    end)

    -- H-1a's rule for Import and Options: a refresh is never wrong to offer, so
    -- the button stays where it is over the Coming soon screen. Its click then
    -- reaches `Companion.Refresh`, which refuses with the gate's own line and
    -- captures nothing (H-1).
    it("stays on the row over the Coming soon screen, and the press is refused there", function()
        world.spec = GUARDIAN
        ns.UI.Refresh()
        assert.is_false(frame.statusStrip:IsShown())
        assert.equal(frame, frame.refreshButton:GetParent())
        assert.equal(frame.openImportButton, frame.refreshButton.points[1][2])
        frame.refreshButton:Click()
        assert.equal(0, world.reloads)
        assert.is_nil(ns.db.global.captures.inventory)
        assert.is_truthy(tostring(world.output()):find("Guardian", 1, true))
    end)
end)

describe("the import dialog (M5-2)", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("is built with the window, hidden, and opened by the strip's button", function()
        assert.is_table(frame.importDialog)
        assert.is_false(frame.importDialog:IsShown())
        frame.openImportButton:Click()
        assert.is_true(frame.importDialog:IsShown())
        frame.openImportButton:Click()
        assert.is_false(frame.importDialog:IsShown())
    end)

    it("closes with the window, rather than floating on with nothing behind it", function()
        frame:Show()
        frame.openImportButton:Click()
        assert.is_true(frame.importDialog:IsShown())
        frame:Hide()
        frame:GetScript("OnHide")(frame)
        assert.is_false(frame.importDialog:IsShown())
    end)

    it("closes on Escape like the window does", function()
        local names = {}
        for _, name in ipairs(_G.UISpecialFrames) do
            names[name] = true
        end
        assert.is_true(names["LootpathImportDialog"])
    end)

    it("carries the paste box, the buttons and the import status line", function()
        local dialog = frame.importDialog
        assert.equal(dialog, dialog.pasteBox:GetParent():GetParent())
        assert.equal(dialog, dialog.importButton:GetParent())
        assert.equal(dialog, dialog.clearButton:GetParent())
        assert.equal(dialog, dialog.status:GetParent())
        assert.equal(ns.UI.PASTE_INSTRUCTIONS, dialog.pasteLabel:GetText())
        -- and the window's own keys still name them, so UI.Import is untouched
        assert.equal(dialog.pasteBox, frame.pasteBox)
        assert.equal(dialog.status, frame.status)
    end)

    it("round-trips a paste through UI.Import and answers inside the dialog", function()
        frame.openImportButton:Click()
        frame.pasteBox:SetText(readFile(DUNGEON_EXPORT))
        frame.importButton:Click()
        local status = frame.importDialog.status:GetText()
        assert.is_truthy(status:find("Imported", 1, true))
        assert.is_truthy(status:find("Restoration Druid", 1, true))
        assert.is_table(ns.QEImport.Current())
        -- and the strip behind it now names the same import - by the spec,
        -- since V-2 (WKE-573) took the content type and the export's name off
        -- the line and left them in the strip's own tooltip
        local model = ns.UI.RefreshStrip(frame)
        assert.is_truthy(model.text:find("Restoration Druid", 1, true))
        assert.is_truthy(table.concat(model.tooltip, "\n"):find("Dungeon Top Gear export", 1, true))

        frame.clearButton:Click()
        assert.equal("", frame.pasteBox:GetText())
        assert.equal("", frame.importDialog.status:GetText())
    end)
end)

describe("the launcher (M5-2)", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("names a global AddOn Compartment function in the .toc, and it toggles the window", function()
        local names = {}
        for line in io.lines(H.TOC) do
            local key, value = line:match("^##%s*([%w_]+):%s*(.-)%s*$")
            if key then
                names[key] = value
            end
        end
        assert.equal("LootpathToggle", names.AddonCompartmentFunc)
        assert.is_function(_G[names.AddonCompartmentFunc])
        assert.is_false(frame:IsShown())
        _G.LootpathToggle("Lootpath", "LeftButton")
        assert.is_true(frame:IsShown())
        _G.LootpathToggle("Lootpath", "LeftButton")
        assert.is_false(frame:IsShown())
    end)

    it("puts a button on the minimap at the saved angle, and toggles from it", function()
        local button = ns.UI.minimapButton
        assert.is_table(button)
        assert.equal(_G.Minimap, button:GetParent())
        assert.equal("LootpathMinimapButton", button.frameName)
        local x, y = ns.UI.MinimapButtonOffset(ns.DB_DEFAULTS.profile.settings.minimapAngle)
        assert.same({ "CENTER", _G.Minimap, "CENTER", x, y }, button.points[1])
        button:Click("LeftButton")
        assert.is_true(frame:IsShown())
        button:Click("LeftButton")
        assert.is_false(frame:IsShown())
    end)

    it("opens the options page on a right-click", function()
        ns.UI.minimapButton:Click("RightButton")
        assert.equal(1, #world.settings.opened)
        assert.is_false(frame:IsShown())
    end)

    it("places a button by its angle, and reads an angle back off a position", function()
        local x, y = ns.UI.MinimapButtonOffset(0)
        assert.equal(ns.UI.MINIMAP_RADIUS, x)
        assert.is_true(math.abs(y) < 1e-9)
        x, y = ns.UI.MinimapButtonOffset(90)
        assert.is_true(math.abs(x) < 1e-9)
        assert.equal(ns.UI.MINIMAP_RADIUS, y)
        -- and back again, for every quarter of the ring
        for _, angle in ipairs({ 0, 45, 90, 180, 270, 315 }) do
            local ox, oy = ns.UI.MinimapButtonOffset(angle)
            assert.is_true(math.abs(ns.UI.MinimapAngleFrom(0, 0, ox, oy) - angle) < 1e-9)
        end
    end)

    it("sits just outside whatever size the minimap really is, not a fixed 80 points", function()
        -- ElvUI and other minimap addons resize the minimap after login; a
        -- fixed radius left the button inside the map (owner, 2026-09-09).
        local x, y = ns.UI.MinimapButtonOffset(0, 200, 200)
        assert.equal(100 + ns.UI.MINIMAP_MARGIN, x)
        assert.is_true(math.abs(y) < 1e-9)
        -- the default 140-point map puts the button at 75, which is where
        -- LibDBIcon's `lib.radius` of 5 puts every other addon's button
        -- (M5-2a, WKE-593; it was 80, five points off the ring they share)
        x = ns.UI.MinimapButtonOffset(0, 140, 140)
        assert.equal(75, x)
        assert.equal(75, ns.UI.MINIMAP_RADIUS)
        assert.equal(5, ns.UI.MINIMAP_MARGIN)
    end)

    it("draws LibDBIcon's retail geometry, so it reads as one of the row it sits in", function()
        -- M5-2a (WKE-593): ours had the library's CLASSIC branch - a 20-point
        -- icon in the BACKGROUND with no disc behind it under a 53-point
        -- border - which is what made a square spec icon overrun the ring.
        local button = ns.UI.minimapButton
        assert.equal(31, button.width)

        local border = button.border
        assert.equal(50, border.width)
        assert.equal(50, border.height)
        assert.equal("OVERLAY", border.drawLayer)
        assert.same({ "TOPLEFT", button, "TOPLEFT", 0, 0 }, border.points[1])
        assert.equal("Interface/Minimap/MiniMap-TrackingBorder", border:GetTexture())

        local background = button.background
        assert.equal(24, background.width)
        assert.equal(24, background.height)
        assert.equal("BACKGROUND", background.drawLayer)
        assert.same({ "CENTER", button, "CENTER", 0, 0 }, background.points[1])
        assert.equal("Interface/Minimap/UI-Minimap-Background", background:GetTexture())

        local icon = button.icon
        assert.equal(18, icon.width)
        assert.equal(18, icon.height)
        assert.equal("ARTWORK", icon.drawLayer)
        assert.same({ "CENTER", button, "CENTER", 0, 0 }, icon.points[1])
        -- and NOT masked: the client refuses tex coords on a masked texture
        -- (the owner's Lua Error window, 2026-09-16 14:39:48), and the trim
        -- below is what the button needs. The stub enforces the same rule.
        assert.is_nil(icon:GetMask())
        assert.same({ 0.05, 0.95, 0.05, 0.95 }, icon.texCoord)
    end)

    it("trims the icon's own edge off, by five percent of whatever range it carries", function()
        -- LibDBIcon's `updateCoord`: the trim is of the RANGE, so a class
        -- circle's quarter of the sheet is trimmed by a quarter as much and
        -- stays centred on its own art.
        assert.same({ 0.05, 0.95, 0.05, 0.95 }, { ns.UI.TrimIconCoords(nil) })
        assert.same({ 0.05, 0.95, 0.05, 0.95 }, { ns.UI.TrimIconCoords({ 0, 1, 0, 1 }) })
        local x1, x2, y1, y2 = ns.UI.TrimIconCoords({ 0, 0.25, 0.5, 0.75 })
        assert.is_true(math.abs(x1 - 0.0125) < 1e-9)
        assert.is_true(math.abs(x2 - 0.2375) < 1e-9)
        assert.is_true(math.abs(y1 - 0.5125) < 1e-9)
        assert.is_true(math.abs(y2 - 0.7375) < 1e-9)
        -- the spec icon on the button carries that trim
        assert.same({ 0.05, 0.95, 0.05, 0.95 }, ns.UI.minimapButton.icon.texCoord)
    end)

    it("shows the spec, else the class circle, else the question mark", function()
        -- The same three steps ApplyPortrait takes, shared rather than copied,
        -- so the button and the window cannot disagree about the spec.
        local texture, coords, kind = ns.UI.MinimapIcon()
        assert.equal(world.spec.icon, texture)
        assert.is_nil(coords)
        assert.equal("spec", kind)

        world.spec = nil
        texture, coords, kind = ns.UI.MinimapIcon()
        assert.equal(ns.UI.CLASS_ICON_FILE, texture)
        assert.same(_G.CLASS_ICON_TCOORDS.DRUID, coords)
        assert.equal("class", kind)

        local saved = _G.CLASS_ICON_TCOORDS
        _G.CLASS_ICON_TCOORDS = nil
        texture, coords, kind = ns.UI.MinimapIcon()
        assert.equal("Interface/Icons/INV_Misc_QuestionMark", texture)
        assert.is_nil(coords)
        assert.equal("fallback", kind)
        _G.CLASS_ICON_TCOORDS = saved
    end)

    it("puts the class circle on the button, trimmed, when there is no spec", function()
        world.spec = nil
        assert.equal("class", ns.UI.ApplyMinimapIcon())
        local icon = ns.UI.minimapButton.icon
        assert.equal(ns.UI.CLASS_ICON_FILE, icon:GetTexture())
        assert.same({ ns.UI.TrimIconCoords(_G.CLASS_ICON_TCOORDS.DRUID) }, icon.texCoord)
    end)

    it("hugs a square minimap's edge instead of a circle inside it", function()
        -- GetMinimapShape() == "SQUARE" is the convention square-minimap addons
        -- (ElvUI among them) publish and LibDBIcon reads. On a circle the
        -- diagonal point would sit at (w cos 45, w sin 45), inside the corner.
        local w = 100 + ns.UI.MINIMAP_MARGIN
        local x, y = ns.UI.MinimapButtonOffset(45, 200, 200, "SQUARE")
        -- the corner: on the diagonal, within the margin of the edge, never
        -- past it (LibDBIcon's convention, so the button does not poke out)
        assert.is_true(math.abs(x - y) < 1e-9)
        assert.is_true(x > w - ns.UI.MINIMAP_DIAGONAL_INSET and x <= w)
        -- the diagonal pull-back is LibDBIcon's flat 10, not the margin: the
        -- two were equal by accident while the margin was 10 (M5-2a)
        assert.equal(10, ns.UI.MINIMAP_DIAGONAL_INSET)
        -- at 60 degrees the x half of the diagonal is still inside the edge,
        -- so it is the unclamped value and pins the inset exactly
        local dx = ns.UI.MinimapButtonOffset(60, 200, 200, "SQUARE")
        assert.is_true(math.abs(dx - math.cos(math.rad(60)) * (math.sqrt(2 * w * w) - 10)) < 1e-9)
        -- and on a circle the same angle would sit well inside that corner
        local rx = ns.UI.MinimapButtonOffset(45, 200, 200, "ROUND")
        assert.is_true(rx < x)
        x, y = ns.UI.MinimapButtonOffset(0, 200, 200, "SQUARE")
        assert.equal(w, x)
        assert.is_true(math.abs(y) < 1e-9)
        x, y = ns.UI.MinimapButtonOffset(200, 200, 200, "SQUARE")
        assert.is_true(x >= -w and x <= w and y >= -w and y <= w)
        -- an unknown shape is treated as round
        x = ns.UI.MinimapButtonOffset(0, 200, 200, "SOMETHING-ELSE")
        assert.equal(w, x)
    end)

    it("moves with the minimap when the minimap is resized, and reads the client's shape", function()
        local button = ns.UI.minimapButton
        _G.Minimap:SetSize(200, 200)
        _G.Minimap:GetScript("OnSizeChanged")(_G.Minimap)
        local x, y = ns.UI.MinimapButtonOffset(ns.DB_DEFAULTS.profile.settings.minimapAngle, 200, 200)
        local point = button.points[#button.points]
        assert.same({ "CENTER", "CENTER" }, { point[1], point[3] })
        assert.equal(_G.Minimap, point[2])
        assert.is_true(math.abs(point[4] - x) < 1e-9 and math.abs(point[5] - y) < 1e-9)
        _G.GetMinimapShape = function()
            return "SQUARE"
        end
        ns.UI.SetMinimapAngle(0)
        point = button.points[#button.points]
        assert.equal(100 + ns.UI.MINIMAP_MARGIN, point[4])
        _G.GetMinimapShape = nil
    end)

    it("saves where the button was dragged to, in the profile", function()
        local button = ns.UI.minimapButton
        _G.Minimap.center = { 500, 400 }
        _G.Minimap.effectiveScale = 2
        -- the cursor is in pre-scale coordinates, so this is (580, 400) on the
        -- UI: due east of the minimap's centre, which is angle 0.
        world.cursor = { 1160, 800 }
        button:GetScript("OnDragStart")(button)
        button:GetScript("OnUpdate")(button)
        assert.equal(0, ns.db.profile.settings.minimapAngle)
        assert.equal(ns.UI.MINIMAP_RADIUS, button.points[#button.points][4])
        button:GetScript("OnDragStop")(button)
        assert.is_nil(button:GetScript("OnUpdate"))
    end)

    it("fixes the icon at login without the window ever being opened", function()
        -- M5-2a (WKE-593): the button is built at ADDON_LOADED, and on the
        -- owner's client the spec read is nil that early - so after every
        -- reload the button showed a question mark until the window had been
        -- opened AND the spec changed. The button now carries the events
        -- itself.
        H.unload()
        local other, otherWorld = H.load({
            beforeLoad = function(w)
                w.spec = nil
                _G.CLASS_ICON_TCOORDS = nil
            end,
        })
        -- nothing named a spec or a class at load, so the button starts blank
        assert.is_nil(other.UI.frame)
        assert.equal("Interface/Icons/INV_Misc_QuestionMark", other.UI.minimapButton.icon:GetTexture())

        -- the client answers the spec read a moment later; no window exists
        otherWorld.spec = { index = 4, id = 105, name = "Restoration", icon = 136041, role = "HEALER" }
        otherWorld.fireEvent("PLAYER_LOGIN")
        assert.is_nil(other.UI.frame)
        assert.equal(136041, other.UI.minimapButton.icon:GetTexture())

        -- and PLAYER_ENTERING_WORLD answers too, whichever of the two the
        -- client gets there first with
        otherWorld.spec = { index = 2, id = 103, name = "Feral", icon = 132115, role = "DAMAGER" }
        otherWorld.fireEvent("PLAYER_ENTERING_WORLD", true, false)
        assert.is_nil(other.UI.frame)
        assert.equal(132115, other.UI.minimapButton.icon:GetTexture())

        -- as does a spec change, still with no window
        otherWorld.spec = { index = 4, id = 105, name = "Restoration", icon = 136041, role = "HEALER" }
        otherWorld.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.is_nil(other.UI.frame)
        assert.equal(136041, other.UI.minimapButton.icon:GetTexture())

        H.unload()
    end)

    it("survives a client with no minimap at all", function()
        H.unload()
        local saved = _G.Minimap
        local other = H.load({
            beforeLoad = function()
                _G.Minimap = nil
            end,
        })
        assert.is_nil(other.UI.minimapButton)
        assert.is_nil(other.UI.MinimapButton())
        _G.Minimap = saved
    end)
end)

describe("the scale and compact-rows settings (M5-2)", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("registers a scale slider over the addon's own bounds", function()
        assert.equal(1, #world.settings.sliders)
        local slider = world.settings.sliders[1]
        local Options = ns.UI.Options
        assert.equal("LootpathScale", slider.setting.variable)
        assert.equal("number", slider.setting.variableType)
        assert.equal(Options.SCALE_MIN, slider.options.minValue)
        assert.equal(Options.SCALE_MAX, slider.options.maxValue)
        assert.equal((Options.SCALE_MAX - Options.SCALE_MIN) / Options.SCALE_STEP, slider.options.steps)
    end)

    it("applies the scale to the window and remembers it", function()
        assert.equal(1.0, frame:GetScale())
        world.settings.settings["LootpathScale"].SetValue(1.25)
        assert.equal(1.25, frame:GetScale())
        assert.equal(1.25, ns.db.profile.settings.scale)
        assert.equal(1.25, ns.UI.Options.GetScale())
    end)

    it("clamps a scale that would put the window off the screen, reading and writing", function()
        assert.equal(ns.UI.Options.SCALE_MAX, ns.UI.Options.SetScale(4))
        assert.equal(ns.UI.Options.SCALE_MIN, ns.UI.Options.SetScale(0.1))
        assert.is_nil(ns.UI.Options.SetScale("enormous"))
        ns.db.profile.settings.scale = 9
        assert.equal(ns.UI.Options.SCALE_MAX, ns.UI.Options.GetScale())
    end)

    it("registers a compact-rows checkbox and stores what it is set to", function()
        -- Two checkboxes since R-3: compact rows, then Explain.
        assert.equal(2, #world.settings.checkboxes)
        local checkbox = world.settings.checkboxes[1]
        assert.equal("LootpathCompactRows", checkbox.setting.variable)
        assert.equal("boolean", checkbox.setting.variableType)
        assert.is_false(ns.UI.Options.GetCompactRows())
        world.settings.settings["LootpathCompactRows"].SetValue(true)
        assert.is_true(ns.UI.Options.GetCompactRows())
        assert.is_true(ns.db.profile.settings.compactRows)
    end)
end)

-- ---------------------------------------------------------------------------
-- H-1 (WKE-596): the window in a non-healer spec is one screen.
--
-- The owner asked for "a Coming Soon screen for any other spec, and nothing
-- about healing items when I'm not healing" (2026-09-16 evening). The three
-- panels are hidden, the three tabs are disabled, and three lines take the
-- body: which spec he is in, what Lootpath rates and which spec of his class
-- rates it, and how old the rating waiting for him is.
describe("the healing gate's screen", function()
    local ns, world, frame

    local GUARDIAN = { index = 3, id = 104, name = "Guardian", icon = 132276, role = "TANK" }
    local RESTORATION = { index = 4, id = 105, name = "Restoration", icon = 136041, role = "HEALER" }

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    -- Proven red by taking the gate out of `UI.ShowTab`: all three tabs are
    -- clickable in Guardian and the Equip Now panel is on screen with the
    -- Guardian set in it.
    it("hides the three panels and disables the three tabs", function()
        assert.is_true(frame.equipPanel:IsShown())
        world.spec = GUARDIAN
        ns.UI.Refresh()
        for _, tab in ipairs(ns.UI.TABS) do
            assert.is_false(frame[tab.key]:IsShown(), tab.key .. " is still on screen")
        end
        for index, button in ipairs(frame.tabs) do
            assert.is_false(button:IsEnabled(), "tab " .. index .. " can still be clicked")
        end
        assert.is_true(frame.comingSoon:IsShown())
        -- The tab he was on is remembered, not forgotten.
        assert.equal(1, frame.selectedTab)
    end)

    it("puts the tabs back on a spec change, with no reload", function()
        -- Open: the window redraws on the spec change only while it is on
        -- screen, and one that is shut is redrawn when it is next opened.
        frame:Show()
        world.spec = GUARDIAN
        world.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.is_true(frame.comingSoon:IsShown())
        world.spec = RESTORATION
        world.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.is_false(frame.comingSoon:IsShown())
        assert.is_true(frame.equipPanel:IsShown())
        assert.is_true(frame.tabs[1]:IsEnabled())
        assert.equal(0, world.reloads)
    end)

    -- The three lines. Proven red by writing the gate's spec into the body
    -- instead of the healing one: the sentence tells the player to switch to
    -- the spec he is already in.
    it("names the spec, what is rated, and the spec to switch to", function()
        world.spec = GUARDIAN
        local model = ns.UI.ComingSoonModel()
        assert.equal("Coming soon for Guardian.", model.title)
        assert.equal("Lootpath rates healing gear for now. Switch to Restoration and it's all here.", model.body)
        ns.UI.Refresh()
        assert.equal("Coming soon for Guardian.", frame.comingSoon.title:GetText())
        assert.equal(
            "Lootpath rates healing gear for now. Switch to Restoration and it's all here.",
            frame.comingSoon.body:GetText()
        )
    end)

    it("says when the rating was last written, in the strip's own words", function()
        world.spec = GUARDIAN
        -- Nothing imported yet.
        assert.equal("Not rated yet.", ns.UI.ComingSoonModel().age)
        -- and with a rating on screen, its age - the companion's `writtenAt`
        -- when the file wrote it, which is the stamp the strip reads too.
        local exported = "2026-09-06T21:14:24.465Z"
        ns.db.char.qeImport = { exportedAt = exported, spec = "Restoration Druid", topSet = { items = {} } }
        ns.db.char.qeImports = { Dungeon = ns.db.char.qeImport }
        local now = ns.EpochFromISO(exported) + 47 * 60
        assert.equal("Last rated 47 minutes ago.", ns.UI.ComingSoonModel(now).age)
    end)

    -- The strip keeps its four facts and loses the clause that the screen now
    -- says. Proven red by leaving `specClause` in the model: the strip says
    -- `you're in Guardian; this plan is for Restoration Druid` one row above a
    -- screen that has just said the same thing better.
    it("drops the strip's spec clause while the screen is up, and keeps the facts", function()
        ns.db.char.qeImport =
            { exportedAt = "2026-09-06T21:14:24.465Z", spec = "Restoration Druid", topSet = { items = {} } }
        ns.db.char.qeImports = { Dungeon = ns.db.char.qeImport }
        world.spec = GUARDIAN
        local model = ns.UI.StatusStripModel()
        assert.is_nil(model.specClause)
        assert.is_truthy(model.text:find("Restoration Druid", 1, true))
    end)

    it("is not up in the healing spec, nor in a spec the client does not name", function()
        assert.is_nil(ns.UI.ComingSoonModel())
        world.spec = nil
        assert.is_nil(ns.UI.ComingSoonModel())
        ns.UI.Refresh()
        assert.is_false(frame.comingSoon:IsShown())
        assert.is_true(frame.equipPanel:IsShown())
    end)

    -- H-1a (WKE-606): the strip goes with the panels.
    --
    -- The owner's check of H-1 in Guardian: the screen was right and the row
    -- above it still read `Restoration Druid - companion, written 3 minutes
    -- ago - vault pick: everything upgraded`. Those are the healing set's facts
    -- and the screen has already said the only one that is owed to a player who
    -- is not healing.
    it("hides the strip and the nudge row while the screen is up", function()
        ns.Drift.SetBehind({ count = 2, name = "Lightgrasp Worldroot" })
        ns.UI.RefreshStrip(frame)
        assert.is_true(frame.statusStrip:IsShown())
        assert.is_true(frame.nudgeButton:IsShown())
        world.spec = GUARDIAN
        ns.UI.Refresh()
        assert.is_false(frame.statusStrip:IsShown())
        assert.is_false(frame.nudgeButton:IsShown())
        assert.equal("", frame.stripText:GetText())
    end)

    -- The two buttons are not the strip's to take away. In the client a child of
    -- a hidden frame is hidden with it, so they are the FRAME's children since
    -- this issue and they still hang off the strip's row, which a hidden frame
    -- still has. (The stub's `shown` is its own flag and knows nothing about a
    -- parent, so the parentage is what is asserted: it is the thing that is
    -- true or false on a real screen.)
    it("leaves Import and Options where they are", function()
        world.spec = GUARDIAN
        ns.UI.Refresh()
        assert.is_false(frame.statusStrip:IsShown())
        assert.equal(frame, frame.openImportButton:GetParent())
        assert.equal(frame, frame.optionsButton:GetParent())
        assert.equal(frame.statusStrip, frame.optionsButton.points[1][2])
    end)

    -- A hidden frame gets no OnEnter and no mouse-up in the client; the stub
    -- will run either script on demand, so the model behind them is what is
    -- asserted - there is none, and both say nothing.
    it("has no tooltip and no click while it is hidden", function()
        world.spec = GUARDIAN
        ns.UI.Refresh()
        assert.is_nil(frame.stripModel)
        world.tooltip:ClearLines()
        frame.statusStrip:GetScript("OnEnter")(frame.statusStrip)
        assert.equal("", world.tooltip.stub:Text())
        assert.is_nil(ns.UI.StripClick(frame))
        assert.equal(0, world.reloads)
    end)

    it("is on screen in the healing spec, and in a spec the client does not name", function()
        ns.UI.Refresh()
        assert.is_true(frame.statusStrip:IsShown())
        world.spec = nil
        ns.UI.Refresh()
        assert.is_true(frame.statusStrip:IsShown())
    end)

    it("puts the strip back on the spec change, with no reload", function()
        frame:Show()
        world.spec = GUARDIAN
        world.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.is_false(frame.statusStrip:IsShown())
        world.spec = RESTORATION
        world.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.is_true(frame.statusStrip:IsShown())
        assert.is_truthy(frame.stripModel)
        assert.equal(0, world.reloads)
    end)
end)
