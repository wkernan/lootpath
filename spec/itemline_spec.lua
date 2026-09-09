-- spec/itemline_spec.lua (M5-1, WKE-550)
-- The item widget, and the Equip Now tab drawn out of it.
--
-- The stub records what a texture was told to show since M5-1, so "which icon
-- did this row get" and "what colour was its quality border" are questions a
-- headless test can ask. What the row LOOKS like at the owner's UI scale is
-- still an in-game step (M5-5) and nothing here claims it.
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")

-- The 2026-09-07 01:01 Dungeon export: 12 differentials and a top set that
-- differs from the worn set in five slots, so the tab has swap rows, already-
-- best rows and rows QE Live does not name, all at once.
local DUNGEON_EXPORT = "spec/fixtures/qe/qe-droptimizer-Hotornot-cjyztichdhze.json"

local ITEM_ID = 271528
local ICON = 7579164 -- the head slot's icon in the 2026-09-05 golden

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function registerStatic(world, itemID, icon)
    world.items[itemID] = { instant = { itemID, "Armor", "Cloth", "INVTYPE_HEAD", icon, 4, 1 } }
end

local function registerLoaded(world, itemID, name, quality, level, icon)
    world.items[itemID] = {
        instant = { itemID, "Armor", "Cloth", "INVTYPE_HEAD", icon, 4, 1 },
        info = { name, "|Hitem:" .. itemID .. "|h[" .. name .. "]|h", quality, n = 3 },
        level = level,
    }
end

describe("UI.ItemLine over a cached item", function()
    local ns, world, parent, line

    before_each(function()
        ns, world = H.load()
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        parent = CreateFrame("Frame")
        line = ns.UI.ItemLine.Create(parent, {})
    end)

    after_each(function()
        H.unload()
    end)

    it("draws the icon, the quality border, the level and the name", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID })
        assert.equal(ICON, line.icon.texture)
        assert.is_true(line.border:IsShown())
        assert.equal(ns.UI.ItemLine.ICON_BORDER_TEXTURE, line.border.texture)
        -- Tinted with the colour the CLIENT gave for that quality, whatever it
        -- is: the stub's quality 4 is { 0.5, 0.5, 0.5 }, a placeholder.
        assert.same({ 0.5, 0.5, 0.5 }, {
            line.border.vertexColor[1],
            line.border.vertexColor[2],
            line.border.vertexColor[3],
        })
        assert.equal("308", line.level:GetText())
        assert.is_truthy(line.name:GetText():find("Placeholder Hood", 1, true))
        -- The name carries the quality colour, built from the same numbers.
        assert.is_truthy(line.name:GetText():find("|cff808080", 1, true))
        -- Nothing was asked of the server: the client already had it all.
        assert.equal(0, #world.itemDataRequests)
    end)

    it("prefers what the caller already knew to what it would have to ask for", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, name = "From the scan", itemLevel = 321, icon = 42, quality = 2 })
        assert.equal(42, line.icon.texture)
        assert.equal("321", line.level:GetText())
        assert.is_truthy(line.name:GetText():find("From the scan", 1, true))
        assert.same({ 0.3, 0.3, 0.3 }, {
            line.border.vertexColor[1],
            line.border.vertexColor[2],
            line.border.vertexColor[3],
        })
    end)

    it("draws the second line, the badge and the tags the caller passed", function()
        ns.UI.ItemLine.Set(line, {
            itemID = ITEM_ID,
            second = "Ara-Kara, City of Echoes - Mythic",
            badge = { text = "+1.83%", tone = "better" },
            tags = { "vault", "catalyst", "tier" },
        })
        assert.equal("Ara-Kara, City of Echoes - Mythic", line.second:GetText())
        -- QE Live's gold, his own number, his own string: nothing is computed.
        assert.equal("|cffFFDF14+1.83%|r", line.badge:GetText())
        assert.equal(1, line.badge:GetAlpha())
        local tags = line.tags:GetText()
        assert.is_truthy(tags:find("|cff00FFFFVault|r", 1, true))
        assert.is_truthy(tags:find("|cffDDA0DDCatalyst|r", 1, true))
        assert.is_truthy(tags:find("|cffFFFF00Tier|r", 1, true))
    end)

    it("dims a worse badge to the opacity his own downgrade card uses", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, badge = { text = "-0.57%", tone = "worse" } })
        assert.equal("|cffC16719-0.57%|r", line.badge:GetText())
        assert.equal(0.72, line.badge:GetAlpha())
    end)

    it("greys a badge he did not rank, and takes a caller's own colour when given one", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, badge = { text = "not ranked", tone = "none" } })
        assert.equal("|cff909296not ranked|r", line.badge:GetText())
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, badge = { text = "swap", hex = "ffd43b" } })
        assert.equal("|cffffd43bswap|r", line.badge:GetText())
    end)

    it("names an unknown tag in grey rather than dropping it", function()
        assert.equal("|cff909296sockets|r", ns.UI.ItemLine.TagText({ "sockets" }))
        assert.equal("", ns.UI.ItemLine.TagText(nil))
    end)

    it("draws a badge atlas the client has and a word when it does not", function()
        ns.UI.ItemLine.Set(
            line,
            { itemID = ITEM_ID, badge = { text = "already best", atlas = "common-icon-checkmark" } }
        )
        assert.is_true(line.badgeIcon:IsShown())
        assert.equal("common-icon-checkmark", line.badgeIcon.atlas)
        -- The guard: a client without that atlas draws no texture at all, and
        -- the word is still there to read.
        world.atlases = {}
        ns.UI.ItemLine.Set(
            line,
            { itemID = ITEM_ID, badge = { text = "already best", atlas = "common-icon-checkmark" } }
        )
        assert.is_false(line.badgeIcon:IsShown())
        assert.is_truthy(line.badge:GetText():find("already best", 1, true))
    end)

    it("shows the item's own tooltip, with the shopping compare", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, link = "|Hitem:271528|h[Placeholder Hood]|h" })
        line.iconButton:Enter()
        assert.equal("|Hitem:271528|h[Placeholder Hood]|h", world.tooltip.hyperlink)
        assert.equal(1, #world.compareCalls)
        line.iconButton:Leave()
        -- QE Live names an item by id and gives no link: the id is enough.
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID })
        line.nameButton:Enter()
        assert.equal(ITEM_ID, world.tooltip.itemID)
        assert.is_nil(world.tooltip.hyperlink)
    end)
end)

describe("UI.ItemLine over an item the client has not loaded", function()
    local ns, world, line

    before_each(function()
        ns, world = H.load()
        registerStatic(world, ITEM_ID, ICON)
        line = ns.UI.ItemLine.Create(CreateFrame("Frame"), {})
    end)

    after_each(function()
        H.unload()
    end)

    it("stays readable, keeps the real icon and asks the client once", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID })
        -- The icon is static data, so it is the item's own even now.
        assert.equal(ICON, line.icon.texture)
        assert.equal(RETRIEVING_ITEM_INFO, line.name:GetText())
        assert.equal("", line.level:GetText())
        assert.is_false(line.border:IsShown())
        assert.same({ ITEM_ID }, world.itemDataRequests)
    end)

    it("falls back to Blizzard's question mark when even the icon is unknown", function()
        ns.UI.ItemLine.Set(line, { itemID = 999999 })
        assert.equal(ns.UI.ItemLine.PLACEHOLDER_ICON, line.icon.texture)
        assert.equal(RETRIEVING_ITEM_INFO, line.name:GetText())
    end)

    it("fills itself in when the client answers", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID })
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.is_truthy(line.name:GetText():find("Placeholder Hood", 1, true))
        assert.equal("308", line.level:GetText())
        assert.is_true(line.border:IsShown())
    end)

    it("is still readable when the load never fires at all", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, second = "Head - on your character" })
        world.runTimers(ns.ItemData.WAIT_SECONDS * ns.ItemData.MAX_ATTEMPTS + 1)
        assert.equal(RETRIEVING_ITEM_INFO, line.name:GetText())
        assert.equal("Head - on your character", line.second:GetText())
        assert.equal(ICON, line.icon.texture)
        assert.equal(0, ns.ItemData.EpisodeCount())
    end)

    it("never lets a late answer land on a line that has moved on", function()
        registerStatic(world, 272228, 7866587)
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID })
        -- The row is re-used for another item before the first one answers.
        ns.UI.ItemLine.Set(line, { itemID = 272228 })
        -- One episode, not two: the row stopped waiting for what it used to
        -- hold rather than leaving the client to answer about it.
        assert.equal(1, ns.ItemData.EpisodeCount())
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", ITEM_ID, true)
        assert.equal(RETRIEVING_ITEM_INFO, line.name:GetText())
        assert.equal(7866587, line.icon.texture)
        registerLoaded(world, 272228, "Placeholder Chain", 3, 301, 7866587)
        world.fireEvent("ITEM_DATA_LOAD_RESULT", 272228, true)
        assert.is_truthy(line.name:GetText():find("Placeholder Chain", 1, true))
    end)

    it("waits for nothing once it is cleared", function()
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID })
        assert.equal(1, ns.ItemData.EpisodeCount())
        ns.UI.ItemLine.Clear(line)
        assert.is_false(line:IsShown())
        assert.equal(0, ns.ItemData.EpisodeCount())
    end)
end)

describe("UI.ItemLine's quality colour", function()
    local ns

    before_each(function()
        ns = H.load()
    end)

    after_each(function()
        H.unload()
    end)

    it("prefers ColorManager, which is what Blizzard's own item buttons read", function()
        assert.equal("808080", ns.UI.ItemLine.QualityColor(4).hex)
    end)

    it("falls through to C_Item and then to the table, and says nothing when nobody answers", function()
        _G.ColorManager = nil
        assert.equal("808080", ns.UI.ItemLine.QualityColor(4).hex)
        _G.C_Item.GetItemQualityColor = nil
        assert.equal("808080", ns.UI.ItemLine.QualityColor(4).hex)
        _G.ITEM_QUALITY_COLORS = nil
        assert.is_nil(ns.UI.ItemLine.QualityColor(4))
        -- And a quality no client describes is a row without a border, never a
        -- row with a guessed one.
        assert.is_nil(ns.UI.ItemLine.QualityColor(nil))
        assert.is_nil(ns.UI.ItemLine.QualityColor(99))
    end)
end)

-- The tab as it is actually drawn, over the owner's own scan and his own
-- export. Every figure asserted below was read from those two files.
describe("the Equip Now tab drawn as item lines", function()
    local ns, world, panel

    before_each(function()
        ns, world = H.load()
        R.inventory(world, R.snapshot("inventory", 1))
        world.bankOpen = true
        ns.UI.Frame()
        ns.UI.frame.pasteBox:SetText(readFile(DUNGEON_EXPORT))
        ns.UI.frame.importButton:Click()
        panel = ns.UI.frame.equipPanel
    end)

    after_each(function()
        H.unload()
    end)

    local function rowsByStatus(status)
        local out = {}
        for index, frameRow in ipairs(panel.rows) do
            if frameRow.shown and frameRow.matchRow and frameRow.matchRow.status == status then
                out[#out + 1] = { row = frameRow, index = index }
            end
        end
        return out
    end

    it("gives every drawn row the icon the scan read off the client", function()
        -- Ten of the fifteen rows are about an item the scan found, so ten
        -- carry an icon file ID off the client. The other five are QE Live's
        -- own items, which he names by id only.
        local scanned, named = 0, 0
        for index = 1, #panel.match.rows do
            local frameRow = panel.rows[index]
            local described = frameRow.described
            if described.item and described.item.icon then
                assert.is_number(frameRow.line.icon.texture)
                assert.equal(described.item.icon, frameRow.line.icon.texture)
                scanned = scanned + 1
            else
                -- An item this replay's client has never described: Blizzard's
                -- own question mark, and no invented icon.
                assert.equal("best_not_owned", frameRow.matchRow.status)
                assert.equal(ns.UI.ItemLine.PLACEHOLDER_ICON, frameRow.line.icon.texture)
                named = named + 1
            end
        end
        assert.equal(10, scanned)
        assert.equal(5, named)
        -- The head slot, by its measured icon: the 2026-09-05 golden's 271528.
        local head = panel.match.bySlot["Head"][1]
        assert.equal(ICON, ns.UI.EquipPanel.Describe(head).item.icon)
    end)

    it("tints every border with the client's colour for that item's quality", function()
        for index = 1, #panel.match.rows do
            local frameRow = panel.rows[index]
            local quality = frameRow.described.item and frameRow.described.item.quality
            if quality then
                local color = ns.UI.ItemLine.QualityColor(quality)
                assert.is_true(frameRow.line.border:IsShown())
                assert.same({ color.r, color.g, color.b }, {
                    frameRow.line.border.vertexColor[1],
                    frameRow.line.border.vertexColor[2],
                    frameRow.line.border.vertexColor[3],
                })
            end
        end
    end)

    it("draws a swap as a pair with an arrow, and an already-best row as one icon", function()
        local swaps = rowsByStatus("swap")
        assert.is_true(#swaps > 0)
        for _, entry in ipairs(swaps) do
            local frameRow = entry.row
            assert.is_true(frameRow.worn:IsShown())
            assert.equal(frameRow.matchRow.equipped.icon, frameRow.worn.icon.texture)
            assert.equal(frameRow.matchRow.best.icon, frameRow.line.icon.texture)
            assert.is_true(frameRow.arrow:IsShown())
            assert.equal("common-icon-forwardarrow", frameRow.arrow.atlas)
            assert.is_true(frameRow.equip:IsShown())
            assert.is_truthy(frameRow.line.badge:GetText():find("swap", 1, true))
        end

        local best = rowsByStatus("equipped_is_best")
        assert.is_true(#best > 0)
        for _, entry in ipairs(best) do
            assert.is_false(entry.row.worn:IsShown())
            assert.is_false(entry.row.arrow:IsShown())
            assert.is_true(entry.row.line.badgeIcon:IsShown())
            assert.equal("common-icon-checkmark", entry.row.line.badgeIcon.atlas)
            assert.is_truthy(entry.row.line.badge:GetText():find("already best", 1, true))
        end
    end)

    it("writes the arrow as a word on a client without that atlas", function()
        world.atlases = {}
        ns.UI.EquipPanel.Refresh(panel, panel.match)
        local swaps = rowsByStatus("swap")
        assert.is_true(#swaps > 0)
        for _, entry in ipairs(swaps) do
            assert.is_false(entry.row.arrow:IsShown())
            assert.is_true(entry.row.arrowText:IsShown())
            assert.equal(ns.UI.EquipPanel.ARROW_FALLBACK, entry.row.arrowText:GetText())
        end
        for _, entry in ipairs(rowsByStatus("equipped_is_best")) do
            assert.is_false(entry.row.line.badgeIcon:IsShown())
            assert.is_truthy(entry.row.line.badge:GetText():find("already best", 1, true))
        end
    end)

    it("puts the five counts on the chips in their status colours", function()
        local chips = ns.UI.EquipPanel.Chips(panel.match)
        assert.equal(5, #chips)
        for index, chip in ipairs(chips) do
            assert.equal(chip.count, panel.match.counts[chip.key] or 0)
            assert.equal("|cff" .. chip.hex .. chip.text .. "|r", panel.chips[index]:GetText())
            assert.equal(ns.UI.EquipPanel.STATUS_HEX[chip.key], chip.hex)
        end
        -- The counts are said once: the chips have them, the note does not.
        assert.is_falsy(panel.summary:GetText():find("already best", 1, true))
    end)

    it("cancels what a row that is no longer drawn was waiting for", function()
        local rows = panel.match.rows
        assert.is_true(#rows > 2)
        ns.UI.EquipPanel.Refresh(panel, { ok = true, rows = { rows[1] }, counts = panel.match.counts })
        for index = 2, #panel.rows do
            assert.is_false(panel.rows[index]:IsShown())
            assert.is_nil(panel.rows[index].line.request)
            assert.is_nil(panel.rows[index].worn.request)
        end
    end)

    it("scrolls the list rather than growing the window", function()
        -- 20 item lines are 760 points against a 640-point window, so the list
        -- is a scroll frame and its child is as tall as what is on it.
        assert.equal(panel.list, panel.scroll:GetScrollChild())
        assert.is_true(panel.list:GetHeight() > 0)
        assert.is_true(ns.UI.EquipPanel.ROW_HEIGHT * ns.UI.EquipPanel.MAX_ROWS > ns.UI.HEIGHT)
    end)
end)
