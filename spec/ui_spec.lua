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
        local summary = panel.summary:GetText()
        assert.is_truthy(summary:find("already best", 1, true))
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
        assert.equal(1, #world.settings.dropdowns)
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
        assert.is_truthy(ns.UI.VerdictNoteText():find("nothing has been pasted for Dungeon", 1, true))
    end)

    it("files an export with no content type under Unknown rather than dropping it", function()
        ns.UI.frame.pasteBox:SetText(readFile(SAMPLE_EXPORT))
        ns.UI.frame.importButton:Click()
        assert.equal("Mythic+", ns.QEImport.Current().contentType)
        assert.is_table(ns.QEImport.ForContentType("Mythic+"))
        assert.same({ "Mythic+" }, ns.QEImport.StoredContentTypes())
    end)
end)
