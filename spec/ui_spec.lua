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
        assert.is_falsy(frameRow.detail:GetText():find(feet.reason, 1, true))
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
        assert.equal(frameRow.detail, anchors["TOPLEFT"])
        assert.equal(frameRow, anchors["RIGHT"])
        -- The first line still does not wrap: it is one line by design, and
        -- everything long about a row now lives on the note.
        assert.is_false(frameRow.detail.wordWrap)
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
        local detail = frameRow.detail:GetText()
        assert.is_truthy(detail:find("already equipped", 1, true))
        assert.is_falsy(detail:find("not found", 1, true))
        assert.is_falsy(detail:find("->", 1, true))
        assert.is_truthy(detail:find("[Lightgrasp Worldroot]", 1, true))
    end)

    it("names the vault option and the tab that shows it, on a line of its own", function()
        local frameRow = vaultRow()
        assert.is_true(frameRow.note:IsShown())
        local note = frameRow.note:GetText()
        assert.is_truthy(note:find(EXPECTED_NOTE, 1, true))
        assert.is_truthy(note:find(ns.UI.EquipPanel.NOTE_COLOR, 1, true))
        assert.is_falsy(frameRow.detail:GetText():find("Great Vault", 1, true))
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
        local summary = panel.summary:GetText()
        assert.is_truthy(summary:find("14 already best, 0 to swap, 1 waiting in the Great Vault, 0 not owned", 1, true))
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
        local lines = ns.UpgradeMapPanel.Lines(panel.model)
        assert.is_true(#lines > 100)
        for i, line in ipairs(lines) do
            assert.equal(line, panel.rows[i]:GetText())
        end
    end)

    it("puts no QE Live number on screen, because the real export covers nothing", function()
        assert.equal(0, panel.model.counts.covered)
        for i = 1, #panel.lines do
            assert.is_nil(panel.rows[i]:GetText():find("QE Live: ", 1, true))
        end
    end)

    it("narrows to one difficulty when its filter button is clicked", function()
        local before = panel.model.counts.candidates
        local mythicPlus
        for _, button in ipairs(panel.filterButtons) do
            if button:GetText():find("Mythic+ 10", 1, true) then
                mythicPlus = button
            end
        end
        assert.is_not_nil(mythicPlus)
        mythicPlus:Click()
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
        local covered = 0
        for i = 1, #panel.lines do
            if panel.rows[i]:GetText():find("QE Live: in your best set", 1, true) then
                covered = covered + 1
            end
        end
        assert.equal(3, covered)
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

    local function noteCount(panel, note)
        local seen = 0
        if panel.note:GetText():find(note, 1, true) then
            seen = seen + 1
        end
        for _, text in ipairs(panel.rows) do
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

    it("keeps every difficulty button inside the panel's width", function()
        frame.tabs[2]:Click()
        local panel = frame.upgradeMapPanel
        assert.is_true(#panel.filterButtons > 1)
        local used = {}
        for _, placement in ipairs(panel.filterLayout.buttons) do
            used[placement.row] = (used[placement.row] or 0) + placement.width + ns.UpgradeMapPanel.FILTER_BUTTON_GAP
        end
        for row, total in pairs(used) do
            assert.is_true(total <= panel:GetWidth(), string.format("filter row %d is %d wide", row, total))
        end
        -- and no two buttons carry the same words
        local seen = {}
        for _, button in ipairs(panel.filterButtons) do
            if button:IsShown() then
                assert.is_nil(seen[button:GetText()], "two filter buttons read " .. button:GetText())
                seen[button:GetText()] = true
            end
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

describe("UI.ActiveUpgradeFinder", function()
    local ns, world, frame

    before_each(function()
        ns, world = H.load()
        withInventory(world)
        frame = ns.UI.Frame()
    end)

    after_each(function()
        H.unload()
    end)

    it("answers nothing before anything is imported", function()
        assert.is_nil(ns.UI.ActiveUpgradeFinder())
    end)

    it("prefers the content type the setting asks for over the most recent paste", function()
        frame.pasteBox:SetText(readFile(UF_DUNGEON_EXPORT))
        frame.importButton:Click()
        frame.pasteBox:SetText(readFile(UF_RAID_EXPORT))
        frame.importButton:Click()
        assert.equal("Raid", ns.UFImport.Current().contentType)
        assert.equal("Dungeon", ns.UI.Options.Get())
        local verdict, contentType, fellBack = ns.UI.ActiveUpgradeFinder()
        assert.equal("Dungeon", verdict.contentType)
        assert.equal("Dungeon", contentType)
        assert.is_false(fellBack)
    end)

    it("falls back to the most recent one, and says it fell back", function()
        frame.pasteBox:SetText(readFile(UF_RAID_EXPORT))
        frame.importButton:Click()
        local verdict, contentType, fellBack = ns.UI.ActiveUpgradeFinder()
        assert.equal("Raid", verdict.contentType)
        assert.equal("Raid", contentType)
        assert.is_true(fellBack)
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
        local valued = 0
        for i = 1, #panel.lines do
            if panel.rows[i]:GetText():find("QE Live: ", 1, true) then
                valued = valued + 1
            end
        end
        -- The 30 ranked rows plus nothing else: this export has no Top Gear
        -- coverage behind it, so `covered` is still zero.
        assert.equal(0, panel.model.counts.covered)
        assert.equal(30, valued)
    end)

    it("goes back to a values-free map the moment the import is gone", function()
        ns.db.char.ufImport = nil
        ns.db.char.ufImports = {}
        frame.tabs[2]:Click()
        assert.is_false(panel.model.hasUpgrades)
        assert.equal(0, panel.model.counts.ranked)
        for i = 1, #panel.lines do
            assert.is_nil(panel.rows[i]:GetText():find("QE Live: ", 1, true))
        end
    end)
end)
