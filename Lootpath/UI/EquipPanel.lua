-- Lootpath/UI/EquipPanel.lua (M2-2, WKE-520)
-- The first of the three promises: what you should be wearing right now, from
-- what you own, with one-click equip.
--
-- Native frames only (no AceGUI). The panel renders an ns.Match result and
-- nothing else: it ranks nothing, it computes nothing, and every number on a
-- row came out of QE Live's export or out of the client's own item data.
--
-- Nothing here runs in combat. `InCombatLockdown()` is checked in Equip itself,
-- not only when the buttons are drawn, so a lockdown that arrives between the
-- draw and the click still refuses.

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.EquipPanel = {}
local EquipPanel = UI.EquipPanel

EquipPanel.ROW_HEIGHT = 20
-- The panel draws a fixed list rather than a scroll frame. A full set is 15 to
-- 19 rows (the export's items plus anything worn in a slot it does not name),
-- so 20 covers it; anything past that is counted in a line under the list
-- instead of being silently dropped.
EquipPanel.MAX_ROWS = 20

EquipPanel.COMBAT_TOOLTIP = "Lootpath does not equip anything in combat."

local STATUS_COLOR = {
    equipped_is_best = "|cff40c057",
    swap = "|cffffd43b",
    best_not_owned = "|cffff6b6b",
    no_verdict = "|cff909296",
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

local function whereText(record)
    if record.location == "bank" then
        return "in your bank"
    end
    if record.location == "bag" then
        return "in your bags"
    end
    return "on your character"
end

-- One row as { slot, text, status, actionable }. Pure: the frames call it, the
-- tests call it, and neither needs the other.
function EquipPanel.Describe(row)
    if type(row) ~= "table" then
        return { slot = "", text = "", status = "", actionable = false }
    end
    local status = row.status
    local text
    if status == "equipped_is_best" then
        text = string.format("%s - %s", EquipPanel.RecordText(row.best), colored(status, "already equipped"))
    elseif status == "swap" then
        text = string.format(
            "%s  ->  %s  %s",
            EquipPanel.RecordText(row.equipped),
            EquipPanel.RecordText(row.best),
            colored(status, "(" .. whereText(row.best) .. ")")
        )
    elseif status == "best_not_owned" then
        text = string.format(
            "%s  ->  %s  %s",
            EquipPanel.RecordText(row.equipped),
            EquipPanel.VerdictItemText(row.verdictItem),
            colored(status, "(not found: " .. tostring(row.reason) .. ")")
        )
    else
        text = string.format(
            "%s - %s",
            EquipPanel.RecordText(row.equipped),
            colored(status, "QE Live's set does not name this slot")
        )
    end
    if row.matchedBy == ns.Match.MATCHED_BY_ID_LEVEL then
        text = text .. " |cff909296[matched by itemID and item level]|r"
    end
    return { slot = row.slot, text = text, status = status, actionable = ns.Match.IsSwap(row) }
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

-- The summary line above the list.
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
            "%d already best, %d to swap, %d not owned, %d without a verdict",
            counts.equipped_is_best,
            counts.swap,
            counts.best_not_owned,
            counts.no_verdict
        )
    if match.bankAvailable == false then
        line = line .. " |cff909296(bank closed - open it to include bank items)|r"
    end
    return line
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
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(panel.rowWidth, EquipPanel.ROW_HEIGHT)
    if index == 1 then
        row:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", panel.rows[index - 1], "BOTTOMLEFT", 0, -2)
    end

    row.slotText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.slotText:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.slotText:SetWidth(80)
    row.slotText:SetJustifyH("LEFT")

    row.equip = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.equip:SetSize(64, EquipPanel.ROW_HEIGHT - 2)
    row.equip:SetPoint("RIGHT", row, "RIGHT", 0, 0)
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

    row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.detail:SetPoint("LEFT", row.slotText, "RIGHT", 6, 0)
    row.detail:SetPoint("RIGHT", row.equip, "LEFT", -6, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    return row
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

    panel.summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", panel.header, "BOTTOMLEFT", 0, -4)
    panel.summary:SetJustifyH("LEFT")

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

    panel.list = CreateFrame("Frame", nil, panel)
    panel.list:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -8)
    panel.list:SetSize(panel.rowWidth, EquipPanel.ROW_HEIGHT * EquipPanel.MAX_ROWS)

    panel.overflow = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.overflow:SetPoint("TOPLEFT", panel.list, "BOTTOMLEFT", 0, -4)
    panel.overflow:SetJustifyH("LEFT")
    panel.overflow:Hide()

    return panel
end

function EquipPanel.Refresh(panel, match)
    panel.match = match
    panel.summary:SetText(EquipPanel.SummaryText(match))

    local rows = (type(match) == "table" and match.ok and match.rows) or {}
    local shown = math.min(#rows, EquipPanel.MAX_ROWS)
    local inCombat = InCombatLockdown() and true or false

    for i = 1, shown do
        local frameRow = panel.rows[i]
        if not frameRow then
            frameRow = createRow(panel, i)
            panel.rows[i] = frameRow
        end
        local matchRow = rows[i]
        local described = EquipPanel.Describe(matchRow)
        frameRow.matchRow = matchRow
        frameRow.slotText:SetText(described.slot)
        frameRow.detail:SetText(described.text)
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
    end

    if #rows > shown then
        panel.overflow:SetText(string.format("%d more row(s) not shown.", #rows - shown))
        panel.overflow:Show()
    else
        panel.overflow:Hide()
    end

    local swaps = (type(match) == "table" and match.ok and match.counts.swap) or 0
    panel.equipAll:SetEnabled(swaps > 0 and not inCombat)
    panel.equipAllReason = inCombat and EquipPanel.COMBAT_TOOLTIP or "There is nothing to swap."
    panel.equipAll:SetShown(swaps > 0)
end
