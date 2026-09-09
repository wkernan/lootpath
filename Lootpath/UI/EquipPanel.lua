-- Lootpath/UI/EquipPanel.lua (M2-2, WKE-520; drawn as item lines in M5-1, WKE-550)
-- The first of the three promises: what you should be wearing right now, from
-- what you own, with one-click equip.
--
-- Native frames only (no AceGUI). The panel renders an ns.Match result and
-- nothing else: it ranks nothing, it computes nothing, and every number on a
-- row came out of QE Live's export or out of the client's own item data.
--
-- Since M5-1 a row is a `UI.ItemLine` - an icon with a quality border, the
-- item level in its corner, the name in quality colour, a grey second line and
-- a badge - instead of one font string. A swap is drawn the way it reads: the
-- icon you are wearing, an arrow, the icon QE Live wants, the Equip button.
-- `EquipPanel.Describe` is still the pure text of a row, unchanged, and the
-- widget binds the fields it gained (`name`, `second`, `badge`, `tags`,
-- `item`, `worn`) - so `/lootpath status`, the tests and the frames all read
-- the same function.
--
-- The list scrolls. Twenty rows of one font string fitted the window; twenty
-- item lines do not (20 x 38 = 760 points against a 640-point window), so the
-- list is a scroll frame rather than a taller window - M5-2 decides the
-- window's size, and this panel must not decide it for it.
--
-- Nothing here runs in combat. `InCombatLockdown()` is checked in Equip itself,
-- not only when the buttons are drawn, so a lockdown that arrives between the
-- draw and the click still refuses.

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.EquipPanel = {}
local EquipPanel = UI.EquipPanel

-- A row is as tall as the item line inside it, plus the gap the icon needs.
EquipPanel.ROW_HEIGHT = 38
-- A row that has something more to say gets a second line under it rather than
-- a longer first one: the reason a row is what it is used to be appended to the
-- detail text, which does not wrap, so the frame cut it off mid-sentence
-- (owner, 2026-09-08). The note wraps and takes its width from the row, so it
-- fits the frame at whatever size the frame is.
EquipPanel.NOTE_HEIGHT = 16
EquipPanel.ROW_GAP = 2
-- The panel draws a fixed list inside a scroll frame. A full set is 15 to
-- 19 rows (the export's items plus anything worn in a slot it does not name),
-- so 20 covers it; anything past that is counted in a line under the list
-- instead of being silently dropped.
EquipPanel.MAX_ROWS = 20

-- The column the slot name gets. Everything to the right of it is anchored, not
-- sized, so the text a row shows is bounded by the frame and not by a number.
EquipPanel.SLOT_COLUMN = 80
-- The worn item on a swap row: the same widget as the best item's icon, drawn
-- smaller, because the row's subject is what QE Live wants and not what is on
-- you now.
EquipPanel.WORN_ICON_SIZE = 24
EquipPanel.ARROW_SIZE = 16
-- Blizzard's own arrow, from Blizzard_TransformManipulator's RotateControlFrame
-- (`common-icon-forwardarrow`), and its own tick, from Blizzard_ChromieTimeUI
-- and the Housing dashboard (`common-icon-checkmark`) - both read under
-- .luals/ on 2026-09-09. Each is asked for at runtime with
-- C_Texture.GetAtlasInfo and each has a word to fall back on.
EquipPanel.ARROW_ATLAS = "common-icon-forwardarrow"
EquipPanel.ARROW_FALLBACK = "->"
EquipPanel.CHECK_ATLAS = "common-icon-checkmark"

EquipPanel.COMBAT_TOOLTIP = "Lootpath does not equip anything in combat."

-- The panel's note colour: the grey it already uses for asides that are not a
-- row's verdict (the bank-closed hint, the matched-by hint).
EquipPanel.NOTE_COLOR = "|cff909296"

-- One colour per status, as the hex alone, so the same value can go into an
-- escape code (the text `Describe` produces), onto a chip and onto a badge.
EquipPanel.STATUS_HEX = {
    equipped_is_best = "40c057",
    swap = "ffd43b",
    -- Blue, not the gap's red: a vault option is waiting for you, not missing.
    best_in_vault = "74c0fc",
    best_not_owned = "ff6b6b",
    no_verdict = "909296",
}

local STATUS_COLOR = {}
for status, hex in pairs(EquipPanel.STATUS_HEX) do
    STATUS_COLOR[status] = "|cff" .. hex
end
EquipPanel.STATUS_COLOR = STATUS_COLOR

-- The badge each status carries. Short, because it is a column and not a
-- sentence; the sentence is the note. `already best` also draws Blizzard's
-- tick when the client has that atlas.
EquipPanel.STATUS_BADGE = {
    equipped_is_best = { text = "already best", atlas = EquipPanel.CHECK_ATLAS },
    swap = { text = "swap" },
    best_in_vault = { text = "in the vault" },
    best_not_owned = { text = "not owned" },
    no_verdict = { text = "not ranked" },
}

-- The five counts, in the order SummaryText says them, as the chips above the
-- list.
EquipPanel.CHIP_ORDER = {
    { key = "equipped_is_best", label = "already best" },
    { key = "swap", label = "to swap" },
    { key = "best_in_vault", label = "in the Great Vault" },
    { key = "best_not_owned", label = "not owned" },
    { key = "no_verdict", label = "without a verdict" },
}

local NOTHING_EQUIPPED = "(nothing equipped)"

local function colored(status, text)
    return (STATUS_COLOR[status] or "|cffffffff") .. text .. "|r"
end

-- An Inventory record as text: its item link when the client gave one, and
-- otherwise the plainest true thing we can say about it.
function EquipPanel.RecordText(record)
    if type(record) ~= "table" then
        return NOTHING_EQUIPPED
    end
    return record.link or record.name or ("item " .. tostring(record.itemID))
end

-- The name an item line shows for a scanned record: the client's own name, or
-- nothing, and never the link's markup - the line colours the name itself,
-- from the quality, and a row with no name yet says RETRIEVING_ITEM_INFO.
function EquipPanel.RecordName(record)
    if type(record) ~= "table" then
        return nil
    end
    if type(record.name) == "string" and record.name ~= "" then
        return record.name
    end
    return nil
end

-- A verdict item as text. QE Live names an item by id, bonus IDs and level
-- only, so there is no link to show; the name is asked of the client and is
-- absent whenever the item is not cached, which is honest rather than guessed.
function EquipPanel.VerdictItemText(item)
    if type(item) ~= "table" then
        return "an item QE Live did not name"
    end
    local name
    if C_Item and C_Item.GetItemInfo and item.itemID then
        name = ns.Safe(C_Item.GetItemInfo(item.itemID))
    end
    if type(name) ~= "string" or name == "" then
        name = "item " .. tostring(item.itemID)
    end
    if item.level then
        return string.format("%s (ilvl %s)", name, tostring(item.level))
    end
    return name
end

-- The line under a `best_in_vault` row. It quotes QE Live's own item level and
-- sends the reader to the tab that shows the vault: Lootpath never computes a
-- healer value, so this line says where the number came from and stops.
function EquipPanel.VaultNoteText(item)
    local name
    if type(item) == "table" and C_Item and C_Item.GetItemInfo and item.itemID then
        name = ns.Safe(C_Item.GetItemInfo(item.itemID))
    end
    if type(name) ~= "string" or name == "" then
        name = "item " .. tostring(type(item) == "table" and item.itemID or "?")
    end
    local level = type(item) == "table" and item.level or nil
    if level then
        name = string.format("%s (QE Live's level %s)", name, tostring(level))
    end
    return string.format("QE Live's best set has a Great Vault option in this slot: %s - see the Vault tab", name)
end

local function whereText(record)
    if record.location == "bank" then
        return "in your bank"
    end
    if record.location == "bag" then
        return "in your bags"
    end
    return "on your character"
end

-- One scanned record as the shape UI.ItemLine binds. The icon and the quality
-- came off the scan (M5-1 put `icon` on the record); everything the scan did
-- not have, the widget asks the client for.
function EquipPanel.ItemFromRecord(record)
    if type(record) ~= "table" then
        return nil
    end
    return {
        itemID = record.itemID,
        link = record.link,
        name = EquipPanel.RecordName(record),
        quality = record.quality,
        itemLevel = record.itemLevel,
        icon = record.icon,
    }
end

-- One item of QE Live's set as the shape UI.ItemLine binds. He names an item
-- by id, bonus IDs and level and gives no link, no name and no icon, so the
-- level in the icon's corner is HIS level and the rest is the client's.
function EquipPanel.ItemFromVerdict(item)
    if type(item) ~= "table" then
        return nil
    end
    return { itemID = item.itemID, itemLevel = item.level }
end

-- One row as { slot, text, note, status, actionable, name, second, badge,
-- tags, item, worn }. `text` is the whole row as one string and is what
-- `/lootpath status` and the text tests read; `note` is a whole second line or
-- nil; nothing long is ever appended to `text`, because `text` does not wrap.
-- The fields after `actionable` are what the widget binds, and they say the
-- same thing `text` says, split into the places a drawn row puts it.
-- Pure: the frames call it, the tests call it, and neither needs the other.
function EquipPanel.Describe(row)
    if type(row) ~= "table" then
        return { slot = "", text = "", status = "", actionable = false, tags = {} }
    end
    local status = row.status
    local text, note, second, item, worn
    local tags = {}
    if status == "equipped_is_best" then
        text = string.format("%s - %s", EquipPanel.RecordText(row.best), colored(status, "already equipped"))
        second = "already equipped"
        item = EquipPanel.ItemFromRecord(row.best)
    elseif status == "swap" then
        text = string.format(
            "%s  ->  %s  %s",
            EquipPanel.RecordText(row.equipped),
            EquipPanel.RecordText(row.best),
            colored(status, "(" .. whereText(row.best) .. ")")
        )
        second = whereText(row.best)
        item = EquipPanel.ItemFromRecord(row.best)
        worn = EquipPanel.ItemFromRecord(row.equipped)
    elseif status == "best_in_vault" then
        -- Not a failed swap. The row says what you are wearing, exactly as it
        -- would if QE Live had not named a vault option here, and the note
        -- underneath says what QE Live wanted instead.
        if row.equipped then
            text = string.format("%s - %s", EquipPanel.RecordText(row.equipped), colored(status, "already equipped"))
            second = "already equipped"
        else
            text = string.format("%s - %s", NOTHING_EQUIPPED, colored(status, "nothing owned for this slot"))
            second = "nothing owned for this slot"
        end
        note = EquipPanel.NOTE_COLOR .. EquipPanel.VaultNoteText(row.verdictItem) .. "|r"
        item = EquipPanel.ItemFromRecord(row.equipped)
        -- His own word for it, in his own colour: what is waiting in this slot
        -- is a vault option, and the note says which tab shows it.
        tags[#tags + 1] = "vault"
    elseif status == "best_not_owned" then
        text = string.format(
            "%s  ->  %s  %s",
            EquipPanel.RecordText(row.equipped),
            EquipPanel.VerdictItemText(row.verdictItem),
            colored(status, "(not found)")
        )
        -- The reason is a sentence, so it goes on its own line rather than off
        -- the right-hand edge of the frame.
        note = colored(status, tostring(row.reason))
        local level = type(row.verdictItem) == "table" and row.verdictItem.level or nil
        second = level and string.format("QE Live's level %s", tostring(level)) or "named by QE Live"
        item = EquipPanel.ItemFromVerdict(row.verdictItem)
        worn = EquipPanel.ItemFromRecord(row.equipped)
    else
        text = string.format(
            "%s - %s",
            EquipPanel.RecordText(row.equipped),
            colored(status, "QE Live's set does not name this slot")
        )
        second = "QE Live's set does not name this slot"
        item = EquipPanel.ItemFromRecord(row.equipped)
    end
    if row.matchedBy == ns.Match.MATCHED_BY_ID_LEVEL then
        text = text .. " |cff909296[matched by itemID and item level]|r"
        second = second .. " |cff909296[matched by itemID and item level]|r"
    end
    local badge = EquipPanel.STATUS_BADGE[status]
    return {
        slot = row.slot,
        text = text,
        note = note,
        status = status,
        actionable = ns.Match.IsSwap(row),
        name = item and item.name or nil,
        second = second,
        badge = badge and {
            text = badge.text,
            atlas = badge.atlas,
            hex = EquipPanel.STATUS_HEX[status],
        } or nil,
        tags = tags,
        item = item,
        worn = worn,
    }
end

-- Equips one row's item. The combat check is here, not only on the button, so
-- a lockdown that arrives after the panel was drawn still refuses.
function EquipPanel.Equip(row)
    if InCombatLockdown() then
        return { ok = false, reason = "combat" }
    end
    if not ns.Match.IsSwap(row) then
        return { ok = false, reason = "there is nothing to equip in this row" }
    end
    -- C_Item.EquipItemByName(itemInfo, dstSlot?) - Blizzard's exported docs,
    -- read 2026-09-06; the global EquipItemByName is deprecated. dstSlot is the
    -- equipment slot the scan actually found the replaced item in, which is
    -- what keeps two rings and two trinkets from fighting over one slot; it is
    -- nil when the slot was empty, and the client then chooses.
    C_Item.EquipItemByName(row.best.link, row.dstSlot)
    return { ok = true, link = row.best.link, dstSlot = row.dstSlot }
end

function EquipPanel.EquipAll(match)
    if InCombatLockdown() then
        return { ok = false, reason = "combat" }
    end
    local equipped, refusals = 0, {}
    for _, row in ipairs((type(match) == "table" and match.rows) or {}) do
        if ns.Match.IsSwap(row) then
            local result = EquipPanel.Equip(row)
            if result.ok then
                equipped = equipped + 1
            else
                refusals[#refusals + 1] = result.reason
            end
        end
    end
    return { ok = true, equipped = equipped, refusals = refusals }
end

-- The five counts, in words and in their status colours, as the chips above
-- the list. Pure, and empty when there is nothing to count.
function EquipPanel.Chips(match)
    if not (type(match) == "table" and match.ok and type(match.counts) == "table") then
        return {}
    end
    local chips = {}
    for _, chip in ipairs(EquipPanel.CHIP_ORDER) do
        local count = match.counts[chip.key] or 0
        chips[#chips + 1] = {
            key = chip.key,
            count = count,
            text = string.format("%d %s", count, chip.label),
            hex = EquipPanel.STATUS_HEX[chip.key],
        }
    end
    return chips
end

-- The summary line above the list: the whole of what the panel says about a
-- match, in one string. `/lootpath status` and the text tests read this; the
-- drawn panel splits it into the chips and NoteText.
function EquipPanel.SummaryText(match)
    if type(match) ~= "table" then
        return "Paste a QE Live Top Gear export above to fill this panel."
    end
    if not match.ok then
        if match.reason == "combat" then
            return "|cffff6b6bLootpath does not read your gear in combat.|r"
        end
        return "|cffff6b6b" .. tostring(match.reason) .. "|r"
    end
    local counts = match.counts
    local prefix = ""
    if match.stale then
        prefix = "|cffff6b6bIn combat: this is the last scan and nothing can be equipped.|r  "
    end
    local line = prefix
        .. string.format(
            "%d already best, %d to swap, %d waiting in the Great Vault, %d not owned, %d without a verdict",
            counts.equipped_is_best,
            counts.swap,
            counts.best_in_vault or 0,
            counts.best_not_owned,
            counts.no_verdict
        )
    if match.bankAvailable == false then
        line = line .. " |cff909296(bank closed - open it to include bank items)|r"
    end
    return line
end

-- Everything the summary says that the chips do not: the prompt before an
-- import, a refusal, the in-combat warning and the bank hint. The counts
-- themselves are the chips' (M5-1), so nothing on screen says them twice.
function EquipPanel.NoteText(match)
    if type(match) ~= "table" then
        return "Paste a QE Live Top Gear export above to fill this panel."
    end
    if not match.ok then
        return EquipPanel.SummaryText(match)
    end
    local parts = {}
    if match.stale then
        parts[#parts + 1] = "|cffff6b6bIn combat: this is the last scan and nothing can be equipped.|r"
    end
    if match.bankAvailable == false then
        parts[#parts + 1] = "|cff909296(bank closed - open it to include bank items)|r"
    end
    return table.concat(parts, "  ")
end

local function tooltipFor(button, text)
    if not (GameTooltip and text) then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function createRow(panel, index)
    local row = CreateFrame("Frame", nil, panel.list)
    row:SetSize(panel.rowWidth, EquipPanel.ROW_HEIGHT)
    if index == 1 then
        row:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", panel.rows[index - 1], "BOTTOMLEFT", 0, -EquipPanel.ROW_GAP)
    end
    row:SetPoint("RIGHT", panel.list, "RIGHT", 0, 0)

    row.slotText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.slotText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    row.slotText:SetWidth(EquipPanel.SLOT_COLUMN)
    row.slotText:SetHeight(UI.ItemLine.NAME_HEIGHT)
    row.slotText:SetJustifyH("LEFT")

    row.equip = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.equip:SetSize(64, 20)
    -- Anchored to the top, not the middle: a row with a note is taller than the
    -- item line and the button belongs beside the first line of it.
    row.equip:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    row.equip:SetText("Equip")
    row.equip:SetScript("OnClick", function()
        EquipPanel.OnEquipClicked(panel, row)
    end)
    row.equip:SetScript("OnEnter", function(button)
        if not button:IsEnabled() then
            tooltipFor(button, row.disabledReason or EquipPanel.COMBAT_TOOLTIP)
        end
    end)
    row.equip:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- What you are wearing now, on the rows whose answer is a swap.
    row.worn = UI.ItemLine.CreateIcon(row, { size = EquipPanel.WORN_ICON_SIZE })
    row.worn:SetPoint("TOPLEFT", row.slotText, "TOPRIGHT", 4, -4)
    row.worn:Hide()

    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetSize(EquipPanel.ARROW_SIZE, EquipPanel.ARROW_SIZE)
    row.arrow:SetPoint("LEFT", row.worn, "RIGHT", 2, 0)
    row.arrow:Hide()
    row.arrowText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.arrowText:SetPoint("LEFT", row.worn, "RIGHT", 2, 0)
    row.arrowText:SetWidth(EquipPanel.ARROW_SIZE)
    row.arrowText:SetJustifyH("CENTER")
    row.arrowText:Hide()

    row.line = UI.ItemLine.Create(row, {})

    -- The note takes its width from the row itself - LEFT and RIGHT anchors,
    -- no SetWidth - so it is as wide as the frame is and wraps inside it. It
    -- clears the Equip button because it sits under it, not beside it.
    row.note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.note:SetPoint("TOPLEFT", row, "TOPLEFT", EquipPanel.SLOT_COLUMN, -EquipPanel.ROW_HEIGHT)
    row.note:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(true)
    row.note:Hide()

    return row
end

-- Where the item line starts: after the worn icon and the arrow on a pair,
-- and straight after the slot column on a row that is about one item.
local function anchorLine(row, paired)
    row.line:ClearAllPoints()
    row.line:SetPoint("RIGHT", row.equip, "LEFT", -6, 0)
    if paired then
        row.line:SetPoint("TOPLEFT", row.arrowText, "TOPRIGHT", 4, 6)
    else
        row.line:SetPoint("TOPLEFT", row.slotText, "TOPRIGHT", 4, 2)
    end
end

function EquipPanel.OnEquipClicked(panel, row)
    local result = EquipPanel.Equip(row.matchRow)
    if not result.ok then
        if result.reason == "combat" then
            ns.Log("%s", EquipPanel.COMBAT_TOOLTIP)
        else
            ns.Log("%s", result.reason)
        end
        return
    end
    EquipPanel.Refresh(panel, panel.match)
end

function EquipPanel.Create(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel.rowWidth = 560
    panel.rows = {}

    panel.header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.header:SetText("Equip Now")

    -- The counts, as five chips in their status colours, so "5 to swap" is
    -- legible before the list is read.
    panel.chips = {}
    for index = 1, #EquipPanel.CHIP_ORDER do
        local fontString = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        if index == 1 then
            fontString:SetPoint("TOPLEFT", panel.header, "BOTTOMLEFT", 0, -6)
        else
            fontString:SetPoint("LEFT", panel.chips[index - 1], "RIGHT", 10, 0)
        end
        fontString:SetJustifyH("LEFT")
        fontString:SetWordWrap(false)
        panel.chips[index] = fontString
    end

    panel.summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", panel.chips[1], "BOTTOMLEFT", 0, -4)
    panel.summary:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.summary:SetJustifyH("LEFT")
    panel.summary:SetWordWrap(true)

    panel.equipAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.equipAll:SetSize(90, 22)
    panel.equipAll:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 2)
    panel.equipAll:SetText("Equip all")
    panel.equipAll:SetScript("OnClick", function()
        local result = EquipPanel.EquipAll(panel.match)
        if not result.ok then
            ns.Log("%s", EquipPanel.COMBAT_TOOLTIP)
            return
        end
        ns.Log("equipped %d item(s) from QE Live's set.", result.equipped)
        EquipPanel.Refresh(panel, panel.match)
    end)
    panel.equipAll:SetScript("OnEnter", function(button)
        if not button:IsEnabled() then
            tooltipFor(button, panel.equipAllReason or EquipPanel.COMBAT_TOOLTIP)
        end
    end)
    panel.equipAll:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Twenty item lines are taller than the window, so the list scrolls: the
    -- rows live on `panel.list`, which is the scroll frame's child, and how big
    -- the window itself should be is M5-2's question rather than this panel's.
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -8)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
    panel.list = CreateFrame("Frame", nil, panel.scroll)
    panel.list:SetSize(panel.rowWidth, EquipPanel.ROW_HEIGHT * EquipPanel.MAX_ROWS)
    panel.scroll:SetScrollChild(panel.list)

    panel.overflow = panel.list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.overflow:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, 0)
    panel.overflow:SetJustifyH("LEFT")
    panel.overflow:Hide()

    return panel
end

function EquipPanel.Refresh(panel, match)
    panel.match = match
    -- The scroll child is as wide as the panel was told to be: the window sets
    -- `rowWidth` after Create, so the width is taken here rather than frozen.
    panel.list:SetWidth(panel.rowWidth)
    panel.summary:SetText(EquipPanel.NoteText(match))

    local chips = EquipPanel.Chips(match)
    for index, fontString in ipairs(panel.chips) do
        local chip = chips[index]
        if chip then
            fontString:SetText("|cff" .. chip.hex .. chip.text .. "|r")
            fontString:Show()
        else
            fontString:SetText("")
            fontString:Hide()
        end
    end

    local rows = (type(match) == "table" and match.ok and match.rows) or {}
    local shown = math.min(#rows, EquipPanel.MAX_ROWS)
    local inCombat = InCombatLockdown() and true or false
    local used = 0

    for i = 1, shown do
        local frameRow = panel.rows[i]
        if not frameRow then
            frameRow = createRow(panel, i)
            panel.rows[i] = frameRow
        end
        local matchRow = rows[i]
        local described = EquipPanel.Describe(matchRow)
        frameRow.matchRow = matchRow
        frameRow.described = described
        frameRow.slotText:SetText(described.slot)

        if described.worn then
            UI.ItemLine.SetIcon(frameRow.worn, described.worn)
            local atlas = UI.ItemLine.Atlas(EquipPanel.ARROW_ATLAS)
            if atlas then
                frameRow.arrow:SetAtlas(atlas)
                frameRow.arrow:Show()
                frameRow.arrowText:SetText("")
                frameRow.arrowText:Hide()
            else
                frameRow.arrow:Hide()
                frameRow.arrowText:SetText(EquipPanel.ARROW_FALLBACK)
                frameRow.arrowText:Show()
            end
        else
            UI.ItemLine.ClearIcon(frameRow.worn)
            frameRow.arrow:Hide()
            frameRow.arrowText:SetText("")
            frameRow.arrowText:Hide()
        end
        anchorLine(frameRow, described.worn ~= nil)

        UI.ItemLine.Set(frameRow.line, {
            itemID = described.item and described.item.itemID or nil,
            link = described.item and described.item.link or nil,
            name = described.item and described.item.name or nil,
            quality = described.item and described.item.quality or nil,
            itemLevel = described.item and described.item.itemLevel or nil,
            icon = described.item and described.item.icon or nil,
            second = described.second,
            badge = described.badge,
            tags = described.tags,
        })

        local height = EquipPanel.ROW_HEIGHT
        if described.note then
            frameRow.note:SetText(described.note)
            frameRow.note:Show()
            height = height + EquipPanel.NOTE_HEIGHT
        else
            frameRow.note:SetText("")
            frameRow.note:Hide()
        end
        frameRow:SetHeight(height)
        used = used + height + EquipPanel.ROW_GAP

        if described.actionable then
            frameRow.equip:Show()
            frameRow.equip:SetEnabled(not inCombat)
            frameRow.disabledReason = inCombat and EquipPanel.COMBAT_TOOLTIP or nil
        else
            frameRow.equip:Hide()
            -- Hidden AND disabled: a row that is not a swap must not be
            -- clickable by any route, including a stale reference to it.
            frameRow.equip:SetEnabled(false)
            frameRow.disabledReason = nil
        end
        frameRow:Show()
    end
    for i = shown + 1, #panel.rows do
        panel.rows[i]:Hide()
        -- A hidden row waits for nothing: its request is cancelled, so a late
        -- answer never redraws an item that is no longer on screen.
        UI.ItemLine.ClearIcon(panel.rows[i].worn)
        UI.ItemLine.Clear(panel.rows[i].line)
    end

    if #rows > shown then
        -- Under the last row that was drawn, not under the list frame: rows with
        -- a note are taller than one line, so the list's own height is no longer
        -- where the list ends.
        panel.overflow:ClearAllPoints()
        local last = shown > 0 and panel.rows[shown] or panel.list
        panel.overflow:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -4)
        panel.overflow:SetText(string.format("%d more row(s) not shown.", #rows - shown))
        panel.overflow:Show()
        used = used + EquipPanel.NOTE_HEIGHT
    else
        panel.overflow:Hide()
    end

    -- The scroll child is as tall as what is on it, so the scrollbar knows how
    -- far there is to go and a short list does not scroll at all.
    panel.list:SetHeight(math.max(used, 1))

    local swaps = (type(match) == "table" and match.ok and match.counts.swap) or 0
    panel.equipAll:SetEnabled(swaps > 0 and not inCombat)
    panel.equipAllReason = inCombat and EquipPanel.COMBAT_TOOLTIP or "There is nothing to swap."
    panel.equipAll:SetShown(swaps > 0)
end
