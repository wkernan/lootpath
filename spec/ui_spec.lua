-- spec/ui_spec.lua (M2-2, WKE-520)
-- The window is driven through the stub's widget model: the frames are fake but
-- the wiring is the real code, so a click really reaches QEImport.Parse and a
-- refusal really reaches the status line. What a frame LOOKS like on the
-- owner's screen is an in-game step (M2-3) and is not claimed here.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

local REAL_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cxeiassqdyvz.json"
local SAMPLE_EXPORT = "spec/fixtures/qe/sample-handbuilt-v1.json"

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
            assert.equal("30 second(s) ago", ns.UI.AgeText(iso, exportedAt + 30))
            assert.equal("10 minute(s) ago", ns.UI.AgeText(iso, exportedAt + 600))
            assert.equal("3 hour(s) ago", ns.UI.AgeText(iso, exportedAt + 3 * 3600))
            assert.equal("4 day(s) ago", ns.UI.AgeText(iso, exportedAt + 4 * 86400))
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

    it("draws one row per match row, in the match's order", function()
        assert.equal(15, #panel.match.rows)
        for i, matchRow in ipairs(panel.match.rows) do
            local frameRow = panel.rows[i]
            assert.is_true(frameRow.shown)
            assert.equal(matchRow.slot, frameRow.slotText:GetText())
            assert.equal(matchRow, frameRow.matchRow)
        end
        assert.is_false(panel.overflow:IsShown())
    end)

    it("summarises the counts and puts the Equip button only on swap rows", function()
        -- The counts are the five chips above the list (M5-1); the summary
        -- line keeps only what the chips do not say.
        local chips = ns.UI.EquipPanel.Chips(panel.match)
        assert.equal(5, #chips)
        assert.equal("equipped_is_best", chips[1].key)
        assert.is_truthy(panel.chips[1]:GetText():find("already best", 1, true))
        assert.is_truthy(ns.UI.EquipPanel.SummaryText(panel.match):find("already best", 1, true))
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

    it("equips one item by its link and into the slot the scan found", function()
        local row = firstSwapRow(panel)
        assert.is_table(row)
        assert.is_true(row.equip:Click())
        assert.equal(1, #world.equipCalls)
        assert.equal(row.matchRow.best.link, world.equipCalls[1][1])
        assert.equal(row.matchRow.equipped.slotIndex, world.equipCalls[1][2])
    end)

    it("equips every swap row at once and no other row", function()
        assert.is_true(panel.equipAll:IsShown())
        panel.equipAll:Click()
        assert.equal(panel.match.counts.swap, #world.equipCalls)
        local wanted = {}
        for _, matchRow in ipairs(panel.match.rows) do
            if matchRow.status == "swap" then
                wanted[matchRow.best.link] = matchRow.dstSlot
            end
        end
        for _, call in ipairs(world.equipCalls) do
            assert.is_truthy(wanted[call[1]] ~= nil)
            assert.equal(wanted[call[1]], call[2])
        end
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
        assert.equal(ns.UI.EquipPanel.ROW_HEIGHT + ns.UI.EquipPanel.NOTE_HEIGHT, frameRow:GetHeight())
    end)

    it("gives every note line the frame's width rather than a number of its own", function()
        local frameRow = panel.rows[1]
        -- Never SetWidth: the note is anchored to both edges of the row, so it
        -- is as wide as the frame is at whatever size the frame is.
        assert.equal(0, frameRow.note:GetWidth())
        assert.is_true(frameRow.note.wordWrap)
        local anchors = {}
        for _, point in ipairs(frameRow.note.points) do
            anchors[point[1]] = point[2]
        end
        assert.equal(frameRow, anchors["TOPLEFT"])
        assert.equal(frameRow, anchors["RIGHT"])
        -- The item line's own two lines still do not wrap: they are one line
        -- each by design, and everything long about a row lives on the note.
        assert.is_false(frameRow.line.name.wordWrap)
        assert.is_false(frameRow.line.second.wordWrap)
    end)

    it("takes a row back to one line when its note goes away", function()
        local feet, head
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.matchRow and frameRow.matchRow.status == "best_not_owned" then
                feet = feet or frameRow
            elseif frameRow.matchRow and frameRow.matchRow.status == "equipped_is_best" then
                head = head or frameRow
            end
        end
        assert.is_table(feet)
        assert.is_table(head)
        assert.equal(ns.UI.EquipPanel.ROW_HEIGHT, head:GetHeight())
        assert.is_false(head.note:IsShown())
        assert.equal("", head.note:GetText())
        -- Frames are reused across refreshes: a note left on a recycled row
        -- would attach one row's sentence to another row's item.
        -- Held before the refresh: Refresh reassigns every frame row's matchRow,
        -- and these two frames are the ones it is about to hand new rows to.
        local feetRow, headRow = feet.matchRow, head.matchRow
        ns.UI.EquipPanel.Refresh(panel, { ok = true, rows = { feetRow, headRow }, counts = panel.match.counts })
        assert.equal(ns.UI.EquipPanel.ROW_HEIGHT + ns.UI.EquipPanel.NOTE_HEIGHT, panel.rows[1]:GetHeight())
        ns.UI.EquipPanel.Refresh(panel, { ok = true, rows = { headRow }, counts = panel.match.counts })
        assert.equal(ns.UI.EquipPanel.ROW_HEIGHT, panel.rows[1]:GetHeight())
        assert.is_false(panel.rows[1].note:IsShown())
    end)

    it("shows nothing to equip before anything is imported", function()
        H.unload()
        ns, world = H.load()
        withInventory(world)
        ns.UI.Frame()
        ns.UI.Refresh()
        local fresh = ns.UI.frame.equipPanel
        assert.is_truthy(fresh.summary:GetText():find("Paste a QE Live", 1, true))
        assert.is_false(fresh.equipAll:IsShown())
    end)
end)

-- WKE-541 (M2-4): the row the owner saw on his first day. The 2026-09-08
-- inventory snapshot `/lootpath refresh` took at 12:45:26 (snapshot 7) joined
-- to the export the companion wrote from it, which put the Great Vault's
-- Lightgrasp Worldroot at QE Live's level 321 in the top set while the owner
-- was wearing the 305 copy. The tab used to render that as a red failed swap
-- with the explanation running off the frame; it is now the staff he wears,
-- with a line underneath naming the vault option and the tab that shows it.
describe("the Equip Now panel on a Great Vault option in the top set (WKE-541)", function()
    local ns, world, panel
    local AFTER_RESET = "spec/fixtures/captures/Lootpath-20260908-124527.lua"
    local VAULT_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-uliwcyoomcub.json"
    local WEAPON_ID = 251935
    local EXPECTED_NOTE = "QE Live's best set has a Great Vault option in this slot: "
        .. "Lightgrasp Worldroot (QE Live's level 321) - see the Vault tab"

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
        assert.equal("2H Weapon", frameRow.slotText:GetText())
        -- One item line, no pair: nothing is being swapped for anything.
        assert.is_truthy(frameRow.line.name:GetText():find("Lightgrasp Worldroot", 1, true))
        assert.equal("already equipped", frameRow.line.second:GetText())
        assert.is_false(frameRow.worn:IsShown())
        assert.is_false(frameRow.arrow:IsShown())
        assert.is_false(frameRow.arrowText:IsShown())
        assert.is_falsy(frameRow.line.badge:GetText():find("not owned", 1, true))
        -- And QE Live's own word for what is waiting there, in his colour.
        assert.is_truthy(frameRow.line.tags:GetText():find("Vault", 1, true))
        assert.is_truthy(frameRow.line.tags:GetText():find(ns.UI.ItemLine.TAG.vault.hex, 1, true))
        assert.is_truthy(ns.UI.EquipPanel.Describe(frameRow.matchRow).text:find("already equipped", 1, true))
    end)

    it("names the vault option and the tab that shows it, on a line of its own", function()
        local frameRow = vaultRow()
        assert.is_true(frameRow.note:IsShown())
        local note = frameRow.note:GetText()
        assert.is_truthy(note:find(EXPECTED_NOTE, 1, true))
        assert.is_truthy(note:find(ns.UI.EquipPanel.NOTE_COLOR, 1, true))
        assert.is_falsy(frameRow.line.name:GetText():find("Great Vault", 1, true))
        assert.is_falsy(frameRow.line.second:GetText():find("Great Vault", 1, true))
        assert.equal(EXPECTED_NOTE, ns.UI.EquipPanel.VaultNoteText(frameRow.matchRow.verdictItem))
    end)

    it("wraps that line inside the frame rather than cutting it off", function()
        local frameRow = vaultRow()
        assert.is_true(frameRow.note.wordWrap)
        assert.equal(0, frameRow.note:GetWidth())
        assert.equal(ns.UI.EquipPanel.ROW_HEIGHT + ns.UI.EquipPanel.NOTE_HEIGHT, frameRow:GetHeight())
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
        -- The same five counts as the chips the panel actually draws.
        local drawn = {}
        for _, chip in ipairs(panel.chips) do
            drawn[#drawn + 1] = chip:GetText()
        end
        assert.is_truthy(drawn[1]:find("14 already best", 1, true))
        assert.is_truthy(drawn[2]:find("0 to swap", 1, true))
        assert.is_truthy(drawn[3]:find("1 in the Great Vault", 1, true))
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
        assert.is_truthy(panel.summary:GetText():find("In combat", 1, true))
        assert.is_false(panel.equipAll:IsEnabled())
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
        row.equip:Enter()
        assert.equal(ns.UI.EquipPanel.COMBAT_TOOLTIP, world.tooltip:Text())

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
        assert.equal(ns.UpgradeMapPanel.NOTE, panel.note:GetText())
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
        for _, element in ipairs(panel.elements) do
            assert.is_nil(element.row and element.row.badge)
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
        -- Raid one covers nothing at all.
        assert.equal(3, panel.model.counts.covered)
        local covered, badged = 0, 0
        for _, line in ipairs(panel.lines) do
            if line:find("QE Live: in your best set", 1, true) then
                covered = covered + 1
            end
        end
        for _, element in ipairs(panel.elements) do
            local badge = element.row and element.row.badge
            if badge and badge.text == "QE Live: in your best set" then
                badged = badged + 1
            end
        end
        assert.equal(3, covered)
        assert.equal(3, badged)
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

    it("renders the week's options into the window", function()
        assert.equal(ns.VaultPanel.NOTE, panel.note:GetText())
        assert.equal("Vault", panel.header:GetText())
        assert.equal(10, panel.model.counts.options)
        local lines = ns.VaultPanel.Lines(panel.model)
        for i, line in ipairs(lines) do
            assert.equal(line, panel.rows[i]:GetText())
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
        if panel.note:GetText():find(note, 1, true) then
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
        frame.tabs[3]:Click()
        assert.equal(1, noteCount(frame.vaultPanel, ns.VaultPanel.NOTE))
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

    it("titles itself with a version, never with the packager's token", function()
        assert.equal("Lootpath 0.0.0-test", frame.TitleText:GetText())
        H.unload()
        local dev = H.load({
            beforeLoad = function(w)
                w.metadata.Version = "@project-version@"
            end,
        })
        assert.equal("Lootpath dev", dev.UI.Frame().TitleText:GetText())
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
        local valued, badged = 0, 0
        for _, line in ipairs(panel.lines) do
            if line:find("QE Live: ", 1, true) then
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
        assert.equal("Lootpath " .. ns.VERSION, frame.TitleText:GetText())
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

    it("runs each panel from under the strip to the frame's own bottom", function()
        for _, tab in ipairs(ns.UI.TABS) do
            local panel = frame[tab.key]
            assert.equal(frame.statusStrip, panel.points[1][2])
            assert.equal("BOTTOMLEFT", panel.points[1][3])
            assert.equal(frame, panel.points[2][2])
        end
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

    it("says there is nothing yet before anything is imported", function()
        assert.equal(ns.UI.NO_VERDICT_STRIP, ns.UI.RefreshStrip(frame).text)
        assert.equal(ns.UI.NO_VERDICT_STRIP, frame.stripText:GetText())
    end)

    it("names QE Live, the spec, the export and the scenario over a pasted one", function()
        importDungeon()
        local model = ns.UI.RefreshStrip(frame)
        assert.is_false(model.stale)
        local parts = {}
        for part in (model.text .. ns.UI.SEPARATOR):gmatch("(.-)\194\183") do
            parts[#parts + 1] = (part:gsub("^%s+", ""):gsub("%s+$", ""))
        end
        assert.equal(5, #parts)
        assert.equal("QE Live", parts[1])
        assert.equal("Restoration Druid", parts[2])
        assert.equal("Dungeon Top Gear", parts[3])
        assert.is_truthy(parts[4]:find("^pasted, exported "))
        -- the default highlight is M3-13's `thisWeek` (WKE-548)
        assert.equal(ns.UI.SCENARIO_TAG[ns.QEImport.DEFAULT_SCENARIO], "vault pick: as offered")
        assert.equal("vault pick: this week", parts[5])
    end)

    it("says the companion wrote it, and how long ago", function()
        local verdict = importDungeon()
        verdict.source = ns.Companion.SOURCE_COMPANION
        verdict.companionWrittenAt = "2026-09-09T12:00:00.000Z"
        local now = ns.EpochFromISO("2026-09-09T12:04:00.000Z")
        local model = ns.UI.StatusStripModel(now)
        assert.is_truthy(model.text:find("companion, written 4 minute(s) ago", 1, true))
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
        assert.is_truthy(world.tooltip:Text():find("Also stored:", 1, true))
    end)

    it("follows the vault scenario setting", function()
        importDungeon()
        assert.is_truthy(ns.UI.RefreshStrip(frame).text:find("vault pick: this week", 1, true))
        ns.UI.Options.SetVaultScenario("catalyzed")
        assert.is_truthy(ns.UI.RefreshStrip(frame).text:find("vault pick: catalyzed", 1, true))
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
        -- and the strip behind it now names the same import
        assert.is_truthy(ns.UI.RefreshStrip(frame).text:find("Dungeon Top Gear", 1, true))

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
        assert.equal(1, #world.settings.checkboxes)
        local checkbox = world.settings.checkboxes[1]
        assert.equal("LootpathCompactRows", checkbox.setting.variable)
        assert.equal("boolean", checkbox.setting.variableType)
        assert.is_false(ns.UI.Options.GetCompactRows())
        world.settings.settings["LootpathCompactRows"].SetValue(true)
        assert.is_true(ns.UI.Options.GetCompactRows())
        assert.is_true(ns.db.profile.settings.compactRows)
    end)
end)
