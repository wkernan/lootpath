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

    -- M5-1c (WKE-617): a line that REPORTS its height is what lets a caller
    -- put something under it. Equip Now's note used to hang off a constant of
    -- the panel's own, which the line had already passed.
    it("reports the height it takes, from whichever of its two columns is taller", function()
        assert.equal(36, ns.UI.ItemLine.Height())
        assert.equal(ns.UI.ItemLine.Height(), line:GetHeight())
        assert.equal(ns.UI.ItemLine.Height(), line.lineHeight)
        -- The default 34-point icon is the taller column, so the answer is the
        -- one the frame has always been set to.
        assert.equal(ns.UI.ItemLine.ICON_SIZE + ns.UI.ItemLine.LINE_PAD, ns.UI.ItemLine.Height())
        -- A small icon is not the taller column, and the two text lines are.
        local text = ns.UI.ItemLine.NAME_HEIGHT + ns.UI.ItemLine.SECOND_GAP + ns.UI.ItemLine.SECOND_HEIGHT
        assert.equal(31, text)
        assert.equal(text + ns.UI.ItemLine.LINE_PAD, ns.UI.ItemLine.Height(12))
        local small = ns.UI.ItemLine.Create(parent, { size = 12 })
        assert.equal(33, small:GetHeight())
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
        line.iconButton.stub:Enter()
        assert.equal("|Hitem:271528|h[Placeholder Hood]|h", world.tooltip.hyperlink)
        assert.equal(1, #world.compareCalls)
        line.iconButton.stub:Leave()
        -- QE Live names an item by id and gives no link: the id is enough.
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID })
        line.nameButton.stub:Enter()
        assert.equal(ITEM_ID, world.tooltip.itemID)
        assert.is_nil(world.tooltip.hyperlink)
    end)

    -- M5-3a. A journal drop's link carries the previewed key level, so the
    -- hover reads at the level the row prints; with only an id the client
    -- draws the item as it exists in its own expansion and says nothing about
    -- it, which is how a 305 row hovered as Item Level 28.
    it("says so when it can only show the item at its base level", function()
        ns.UI.ItemLine.Set(line, {
            itemID = ITEM_ID,
            levelNote = "shown at its base level - /lootpath capture journal to read it at +10",
        })
        line.iconButton.stub:Enter()
        assert.equal(ITEM_ID, world.tooltip.itemID)
        local text = world.tooltip.stub.Text()
        assert.is_truthy(
            text:find("shown at its base level - /lootpath capture journal to read it at +10", 1, true),
            "the base-level line was not on the tooltip: " .. text
        )
        line.iconButton.stub:Leave()

        -- With a link there is nothing to say: the tooltip is the item at the
        -- level the link carries, and the note is not drawn even when a caller
        -- hands one in.
        ns.UI.ItemLine.Set(line, {
            itemID = ITEM_ID,
            link = "|Hitem:271528|h[Placeholder Hood]|h",
            levelNote = "shown at its base level - /lootpath capture journal to read it at +10",
        })
        line.iconButton.stub:Enter()
        assert.equal("|Hitem:271528|h[Placeholder Hood]|h", world.tooltip.hyperlink)
        assert.is_nil(world.tooltip.stub.Text():find("base level", 1, true))
    end)

    -- M5-3b. The link is right about the item and its track and silent about
    -- the key level the row was rated at, so a hover can draw the right item
    -- at 292 under a row that says 305. The row says its own level instead;
    -- no link is ever built with a level modifier.
    it("says the drop's own level when the link draws another", function()
        local link = "|Hitem:271528|h[Placeholder Hood]|h"
        world.items[link] = { level = 292 }

        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, link = link, dropLevel = 305, keyLevel = 10 })
        line.iconButton.stub:Enter()
        local text = world.tooltip.stub.Text()
        assert.is_truthy(
            text:find("Drops at 305 from a +10 · shown at 292 above", 1, true),
            "the level line was not on the tooltip: " .. text
        )
        line.iconButton.stub:Leave()

        -- The levels agree: the tooltip is the row, and a line saying so twice
        -- would be noise.
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, link = link, dropLevel = 292, keyLevel = 10 })
        line.iconButton.stub:Enter()
        assert.is_nil(world.tooltip.stub.Text():find("Drops at", 1, true))
        line.iconButton.stub:Leave()

        -- A raid drop is read at no key level, so the sentence names none
        -- rather than a number that would mean nothing there.
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, link = link, dropLevel = 311 })
        line.iconButton.stub:Enter()
        assert.is_truthy(
            world.tooltip.stub.Text():find("Drops at 311 · shown at 292 above", 1, true),
            "the raid wording was not on the tooltip: " .. world.tooltip.stub.Text()
        )
        line.iconButton.stub:Leave()

        -- The client will not say what the link draws. Then nothing numeric is
        -- printed: there is no second number to compare, and neither one would
        -- have been read from anything.
        world.items[link] = nil
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, link = link, dropLevel = 305, keyLevel = 10 })
        line.iconButton.stub:Enter()
        local unanswered = world.tooltip.stub.Text()
        assert.is_truthy(
            unanswered:find("shown at its own level above", 1, true),
            "the no-answer wording was not on the tooltip: " .. unanswered
        )
        assert.is_nil(unanswered:find("305", 1, true))
        assert.is_nil(unanswered:find("Drops at", 1, true))
        line.iconButton.stub:Leave()

        -- A row that is not a drop hands in no level of its own, so no tab but
        -- the map's drops can ever get this line.
        world.items[link] = { level = 292 }
        ns.UI.ItemLine.Set(line, { itemID = ITEM_ID, link = link, itemLevel = 305 })
        line.iconButton.stub:Enter()
        local plain = world.tooltip.stub.Text()
        assert.is_nil(plain:find("Drops at", 1, true))
        assert.is_nil(plain:find("shown at", 1, true))
    end)
end)

-- M5-1d (WKE-632). The owner, 2026-09-23, on Equip Now: "I don't like how if
-- my cursor is in the negative space in line with a piece of gear, I see the
-- gear stats." The name's hover target used to run from the icon to the
-- badge column, which on Equip Now is the far side of the row; it now ends
-- where the name the client drew ends.
--
-- The stub lays nothing out, so the room the client would give the name (its
-- own resolved width between the icon and the badge column) is set by hand,
-- and the text's width is whatever the stub's FontString:GetStringWidth
-- answers for the text the line actually wrote - read back, never written
-- down here.
describe("UI.ItemLine's name hover", function()
    local ns, world, line, IL
    local ROOM = 300

    local function point(region, name)
        for _, p in ipairs(region.points) do
            if p[1] == name then
                return p
            end
        end
        return nil
    end

    -- The button spans the whole name box: today's target, the fallback.
    local function isFullWidth(button)
        local all = point(button, "ALL")
        return all ~= nil and all[2] == line.name
    end

    before_each(function()
        ns, world = H.load()
        IL = ns.UI.ItemLine
        registerLoaded(world, ITEM_ID, "Placeholder Hood", 4, 308, ICON)
        line = IL.Create(CreateFrame("Frame"), {})
    end)

    after_each(function()
        H.unload()
    end)

    it("ends where the name ends, and the hover is still the item", function()
        line.name:SetWidth(ROOM)
        IL.Set(line, {
            itemID = ITEM_ID,
            link = "|Hitem:271528|h[Placeholder Hood]|h",
            name = "Placeholder Hood",
            quality = 4,
        })
        assert.is_truthy(line.name:GetText():find("Placeholder Hood", 1, true))
        local measured = line.name:GetStringWidth()
        assert.is_true(measured > 0 and measured < ROOM, "the stub's name width was " .. tostring(measured))
        assert.equal(measured, line.nameButton:GetWidth())
        -- Pinned at the name's left, the height of the name's box, and tied to
        -- nothing on the right: a width, not a stretch to the line's edge.
        assert.same({ "TOPLEFT", line.name, "TOPLEFT", 0, 0 }, point(line.nameButton, "TOPLEFT"))
        assert.same({ "BOTTOMLEFT", line.name, "BOTTOMLEFT", 0, 0 }, point(line.nameButton, "BOTTOMLEFT"))
        for _, edge in ipairs({ "ALL", "RIGHT", "TOPRIGHT", "BOTTOMRIGHT" }) do
            assert.is_nil(point(line.nameButton, edge), "the name button is still tied on " .. edge)
        end

        -- Hovering the name is hovering the item.
        line.nameButton.stub:Enter()
        assert.equal("|Hitem:271528|h[Placeholder Hood]|h", world.tooltip.hyperlink)
        assert.equal(1, #world.compareCalls)
        line.nameButton.stub:Leave()

        -- A point past the name, still inside the room the name had: the line
        -- wires two hover targets - the icon, left of the name box, and the
        -- name button, which now covers [0, measured] from the name box's left
        -- - and the line itself answers no hover. So nothing is under it.
        local past = measured + 1
        assert.is_true(past < ROOM)
        assert.is_true(past > line.nameButton:GetWidth())
        assert.is_nil(line:GetScript("OnEnter"))
        assert.same({ "TOPLEFT", line, "TOPLEFT", 0, 0 }, point(line.iconButton, "TOPLEFT"))
    end)

    it("never runs past the room the name had", function()
        line.name:SetWidth(ROOM)
        IL.Set(line, { itemID = ITEM_ID, name = string.rep("Very Long Name ", 10), quality = 4 })
        assert.is_true(line.name:GetStringWidth() > ROOM)
        assert.equal(ROOM, line.nameButton:GetWidth())
    end)

    it("moves nothing else: the name's box and the second line keep today's anchors", function()
        line.name:SetWidth(ROOM)
        IL.Set(line, { itemID = ITEM_ID, second = "Shoulder · in your bags" })
        assert.same({ "TOPLEFT", line.iconButton, "TOPRIGHT", IL.ICON_GAP, 0 }, point(line.name, "TOPLEFT"))
        assert.same({ "RIGHT", line, "RIGHT", -IL.BADGE_WIDTH - IL.ICON_GAP, 0 }, point(line.name, "RIGHT"))
        assert.equal(IL.NAME_HEIGHT, line.name:GetHeight())
        -- The second line hangs off the name's box, not off the button, so
        -- fitting the button to the name cannot narrow it.
        assert.same({ "TOPLEFT", line.name, "BOTTOMLEFT", 0, -IL.SECOND_GAP }, point(line.second, "TOPLEFT"))
        assert.same({ "RIGHT", line.name, "RIGHT", 0, 0 }, point(line.second, "RIGHT"))
        assert.equal("Shoulder · in your bags", line.second:GetText())
    end)

    it("keeps the full-width target when the client cannot measure the name", function()
        -- No answer at all.
        line.name:SetWidth(ROOM)
        line.name.GetStringWidth = nil
        IL.Set(line, { itemID = ITEM_ID })
        assert.is_true(isFullWidth(line.nameButton))
        -- An answer of 0.
        line.name.GetStringWidth = function()
            return 0
        end
        IL.Set(line, { itemID = ITEM_ID })
        assert.is_true(isFullWidth(line.nameButton))
        -- An answer that throws.
        line.name.GetStringWidth = function()
            error("no")
        end
        IL.Set(line, { itemID = ITEM_ID })
        assert.is_true(isFullWidth(line.nameButton))
        -- And the hover still works from there.
        line.nameButton.stub:Enter()
        assert.equal(ITEM_ID, world.tooltip.itemID)
    end)

    it("keeps the full-width target while the name is still pending", function()
        line.name:SetWidth(ROOM)
        IL.Set(line, { itemID = 999999 })
        assert.equal(RETRIEVING_ITEM_INFO, line.name:GetText())
        assert.is_true(isFullWidth(line.nameButton))
    end)

    it("keeps the full-width target until the client has laid the name out, then fits", function()
        -- No room yet: nothing to cap at, so never narrower than the text.
        IL.Set(line, { itemID = ITEM_ID })
        assert.is_true(isFullWidth(line.nameButton))
        -- The client lays the line out and says its size changed.
        line.name:SetWidth(ROOM)
        local onSize = line:GetScript("OnSizeChanged")
        assert.is_function(onSize)
        onSize(line, 500, IL.Height())
        assert.is_false(isFullWidth(line.nameButton))
        assert.equal(line.name:GetStringWidth(), line.nameButton:GetWidth())
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
        -- M5-1b (WKE-610): the already-best rows are folded behind one line by
        -- default, so this file - which is about how a row is DRAWN - opens the
        -- fold and looks at all fifteen.
        ns.UI.EquipPanel.ToggleFold(ns.db)
        ns.UI.EquipPanel.Refresh(panel, panel.match)
    end)

    after_each(function()
        H.unload()
    end)

    -- Every item that is actually on screen. Since the fold, the drawn order
    -- is "everything that needs something, then the settled rows", so a row
    -- frame's index is no longer its index in the match; and since M5-1e
    -- (WKE-633) the settled rows are cells two across, not row frames, so they
    -- are read off the panel's pairs, left then right.
    local function drawnRows()
        local out = {}
        for _, frameRow in ipairs(panel.rows) do
            if frameRow.shown and frameRow.matchRow then
                out[#out + 1] = frameRow
            end
        end
        for _, pair in ipairs(panel.pairs) do
            if pair.shown then
                for _, cell in ipairs({ pair.left, pair.right }) do
                    if cell.shown and cell.matchRow then
                        out[#out + 1] = cell
                    end
                end
            end
        end
        return out
    end

    local function rowsByStatus(status)
        local out = {}
        for index, frameRow in ipairs(drawnRows()) do
            if frameRow.matchRow.status == status then
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
        assert.equal(#panel.match.rows, #drawnRows())
        for _, frameRow in ipairs(drawnRows()) do
            local described = frameRow.described
            if described.item and described.item.icon then
                assert.is_number(frameRow.line.icon.texture)
                assert.equal(described.item.icon, frameRow.line.icon.texture)
                scanned = scanned + 1
            else
                -- An item this replay's client has never described, and one you
                -- do not own either way: since M5-1b it is drawn as the
                -- client's own EMPTY item button rather than as a piece of gear
                -- with a question mark on it, and no icon is invented.
                assert.equal("best_not_owned", frameRow.matchRow.status)
                assert.is_nil(frameRow.line.icon.texture)
                assert.equal(ns.UI.EquipPanel.GHOST_ICON_ATLAS, frameRow.line.icon.atlas)
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
        for _, frameRow in ipairs(drawnRows()) do
            local quality = frameRow.described.item and frameRow.described.item.quality
            -- Except an item you do not own, which is drawn as an empty slot
            -- and so has no copy to have a quality (M5-1b).
            if quality and not frameRow.drawn.ghost then
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
            -- M5-1b: the picture IS the sentence on a swap row, so the row
            -- carries no mark and no badge word beside the button.
            assert.is_false(frameRow.line.mark:IsShown())
            assert.equal("", frameRow.line.badge:GetText())
        end

        local best = rowsByStatus("equipped_is_best")
        assert.is_true(#best > 0)
        for _, entry in ipairs(best) do
            -- One icon: a settled cell (M5-1e) has no worn icon and no arrow
            -- to hide - it was never given either.
            assert.is_nil(entry.row.worn)
            assert.is_nil(entry.row.arrow)
            -- The tick, in the mark column, and no word anywhere on the row:
            -- no `already best` badge and no `already equipped` second line.
            assert.is_true(entry.row.line.mark:IsShown())
            assert.equal("common-icon-checkmark", entry.row.line.mark.atlas)
            assert.equal("", entry.row.line.badge:GetText())
            assert.is_falsy(entry.row.line.second:GetText():find("already equipped", 1, true))
            assert.is_falsy(entry.row.line.second:GetText():find("already best", 1, true))
            -- and the whole line is at half weight
            assert.equal(ns.UI.ItemLine.DIM_ALPHA, entry.row.line:GetAlpha())
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
        -- A client without the art draws the mark as a flat colour texture in
        -- the state's own hex - the same column, the same size, no word.
        local best = rowsByStatus("equipped_is_best")
        assert.is_true(#best > 0)
        for _, entry in ipairs(best) do
            local mark = entry.row.line.mark
            assert.is_true(mark:IsShown())
            assert.is_nil(mark.atlas)
            assert.is_table(mark.colorTexture)
            local r, g, b = ns.UI.ItemLine.RGB(ns.UI.EquipPanel.STATUS_HEX.equipped_is_best)
            assert.same({ r, g, b }, { mark.colorTexture[1], mark.colorTexture[2], mark.colorTexture[3] })
            assert.equal("", entry.row.line.badge:GetText())
        end
    end)

    it("puts the counts in the bar's key, in their status colours, and nowhere else", function()
        local bar = ns.UI.EquipPanel.Bar(panel.match)
        -- One segment per slot, in the rows' own order: the bar counts slots
        -- and never value.
        assert.equal(#panel.match.rows, #bar.segments)
        for index, segment in ipairs(bar.segments) do
            assert.equal(panel.match.rows[index].status, segment.status)
            assert.equal(ns.UI.EquipPanel.STATUS_HEX[segment.status], segment.hex)
        end
        -- Only the states that are actually present carry a count in words.
        local key = ns.UI.EquipPanel.BarKeyText(panel.match)
        for _, entry in ipairs(bar.key) do
            assert.is_true(entry.count > 0)
            assert.equal(panel.match.counts[entry.status], entry.count)
            assert.is_truthy(key:find(entry.text, 1, true))
        end
        assert.equal(key, panel.barKey:GetText())
        -- and a state with nothing in it is not in the key at all
        for status, count in pairs(panel.match.counts) do
            if count == 0 then
                for _, entry in ipairs(bar.key) do
                    assert.is_not.equal(status, entry.status)
                end
            end
        end
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
        -- and the settled cells (M5-1e): the one row left is drawn in the first
        -- pair's left cell, and every other cell waits for nothing
        for index, pair in ipairs(panel.pairs) do
            for side, cell in ipairs({ pair.left, pair.right }) do
                if not (index == 1 and side == 1) then
                    assert.is_false(cell:IsShown())
                    assert.is_nil(cell.line.request)
                end
            end
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
