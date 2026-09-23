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
-- The figure is the DEFAULT a row frame is built at and what the list frame is
-- sized from before anything is drawn; what a DRAWN row is worth is
-- `EquipPanel.RowHeight`, which asks the line how tall it really is (M5-1c,
-- WKE-617). A guard holds the two to the same number.
EquipPanel.ROW_HEIGHT = 38
-- The clearance above the item line inside a row - on every row, because there
-- is one vertical rule now and a pair only moves the line sideways (M5-1c).
EquipPanel.LINE_TOP = 2
-- The gap between the line's own bottom and the note that hangs off it.
EquipPanel.NOTE_GAP = 2
-- The two gaps a swap row's worn icon and arrow put before the line starts.
EquipPanel.ARROW_GAP = 2
EquipPanel.LINE_GAP = 4
-- A row that has something more to say gets a second line under it rather than
-- a longer first one: the reason a row is what it is used to be appended to the
-- detail text, which does not wrap, so the frame cut it off mid-sentence
-- (owner, 2026-09-08). The note wraps and takes its width from the row, so it
-- fits the frame at whatever size the frame is.
EquipPanel.NOTE_HEIGHT = 16
EquipPanel.ROW_GAP = 2
-- The gap the "more rows" line under the list is drawn at.
EquipPanel.OVERFLOW_GAP = 4
-- The panel draws a fixed list inside a scroll frame. A full set is 15 to
-- 19 rows (the export's items plus anything worn in a slot it does not name),
-- so 20 covers it; anything past that is counted in a line under the list
-- instead of being silently dropped.
EquipPanel.MAX_ROWS = 20
-- The gap between the last thing the header block says and the top of the list
-- (M5-1a, WKE-597). The scroll frame hangs off whichever header element
-- actually has text on it, so an empty note line can neither leave a gap above
-- the list nor move its top.
EquipPanel.TOP_GAP = 8

-- The room the scroll bar takes on the right, and the ONE figure both sides of
-- the list read (M5-2d, WKE-631): the scroll frame's right edge is this far in
-- from the panel's, and the scroll child - the rows - is the panel's width less
-- this, so the child is exactly as wide as the frame that clips it. The bar is
-- UIPanelScrollFrameTemplate's own: `UIPanelScrollBarTemplate` is 16 wide
-- (Blizzard_SharedXML/SecureScrollTemplates.xml:8 in Ketho's annotations) and
-- hangs 6 to the right of the frame's right edge (:48-49), so it needs 22 of
-- these 26 and the other 4 are the gap to the panel's edge. A margin, not a
-- width. Before M5-2d the rows were the panel's width less 6, which was never
-- this room: they ran 20 points past the frame's edge and the Equip button on
-- each row's right lost its last 20 points (the owner's Druid, 2026-09-23).
EquipPanel.SCROLL_INSET_RIGHT = 26

-- The slot bar (M5-1b, WKE-610). Its height and the hair between its segments
-- are the only figures here; how WIDE a segment is is worked out at refresh
-- from the panel's own width divided by the number of slots, so the bar is as
-- wide as the window is and this file decides no width (M5-2c, WKE-609).
EquipPanel.BAR_HEIGHT = 12
EquipPanel.BAR_SEGMENT_GAP = 2
-- The fold line inside the list, and the hint icon under it.
EquipPanel.FOLD_HEIGHT = 18
EquipPanel.HINT_SIZE = 12
-- How much room the hint icon needs under the list. A margin, not a width.
EquipPanel.HINT_ROOM = 18
-- The worn item on a swap row: the same widget as the best item's icon, drawn
-- smaller, because the row's subject is what QE Live wants and not what is on
-- you now.
EquipPanel.WORN_ICON_SIZE = 24
EquipPanel.ARROW_SIZE = 16
-- How far into the row a swap row's item line starts: the worn icon, the gap
-- before the arrow, the arrow, and the gap after it. It is the ONE thing a
-- pair now changes about the line (M5-1c, WKE-617) - the line's top is the
-- row's top either way, so the arrow layout can no longer push the line down
-- past where the note begins.
EquipPanel.PAIR_INSET = EquipPanel.WORN_ICON_SIZE + EquipPanel.ARROW_GAP + EquipPanel.ARROW_SIZE + EquipPanel.LINE_GAP
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
--
-- **Nothing draws this any more** (M5-1b, WKE-610). A drawn row says its state
-- once, through the mark below; `already best` on screen is the tick and no
-- word at all. The table stays because `Describe` is the text model
-- `/lootpath status` and the text tests read, and that model is unchanged by
-- decision - the redraw is a renderer over the same rows.
EquipPanel.STATUS_BADGE = {
    equipped_is_best = { text = "already best", atlas = EquipPanel.CHECK_ATLAS },
    swap = { text = "swap" },
    best_in_vault = { text = "in the vault" },
    best_not_owned = { text = "not owned" },
    no_verdict = { text = "no rating" },
}

-- The five counts, in the order SummaryText says them, as the chips above the
-- list.
EquipPanel.CHIP_ORDER = {
    { key = "equipped_is_best", label = "already best" },
    { key = "swap", label = "to swap" },
    { key = "best_in_vault", label = "in the Great Vault" },
    { key = "best_not_owned", label = "not owned" },
    { key = "no_verdict", label = "no rating" },
}

-- ---------------------------------------------------------------------------
-- M5-1b (WKE-610): the marks, the bar and the fold - the approved canvas
-- (WKE-598) with the owner's five answers of 2026-09-16 applied: the mark set
-- as drawn, the slot COLUMN dropped and the slot word moved onto the row's
-- second line, the already-best rows folded behind one line, the slot bar
-- kept, dark only at ns.UI.WIDTH.
--
-- **One mark per state, in one fixed column.** The reader learns the column
-- once and then reads the list down it instead of reading each row, which is
-- what lets fifteen settled slots become texture rather than fifteen
-- sentences. `swap` has no mark on purpose: the worn icon, the arrow and the
-- Equip button are already the picture of a swap, and a sixth glyph beside
-- them would be the badge word coming back as art.
--
-- Every atlas is asked of the client at draw time through `UI.ItemLine.Atlas`
-- and drawn at MARK_SIZE, the size it is seen at (R-2b) - never at the art's
-- own size squeezed into someone else's box. A client that does not have one
-- gets a flat colour texture in the status's own hex instead, which is the
-- issue's own rule ("from Blizzard atlases where one exists and flat textures
-- otherwise") and never a word: the words on this tab are the second line and
-- the bar's key, and a mark that decayed into a badge would be the thing this
-- redraw removed.
--
-- Where each atlas was read, all under `.luals/vscode-wow-api/Annotations/`
-- on 2026-09-17, in Blizzard's own shipped XML and Lua:
--   common-icon-checkmark ....... FrameXML/Annotations/AddOns/
--       Blizzard_ChromieTimeUI/Blizzard_ChromieTimeUI.xml:23 (parentKey
--       "CompletedCheck"), and Blizzard_PlayerChoice/
--       Blizzard_PlayerChoiceOptionBase.lua.annotated.lua:391 draws it through
--       CreateAtlasMarkup(..., 16, 16), which is this file's own MARK_SIZE.
--   gficon-chest-evergreen-greatvault-collect ... Blizzard_ChallengesUI/
--       Mainline/Blizzard_ChallengesUI.xml:890, and .lua.annotated.lua:309-312
--       builds the same name from "gficon-chest-evergreen-greatvault-" plus the
--       chest's state. It is the Great Vault's own icon on Blizzard's weekly
--       chest, which is exactly what this row is about.
--   transmog-icon-warning-small ... Blizzard_Transmog/
--       Blizzard_TransmogTemplates.xml:576, and .lua.annotated.lua:533 sets it
--       on a frame Blizzard itself calls `warningIcon`.
--   common-radiobutton-circle ... Blizzard_FrameXML/RolePoll.xml:18 - the
--       hollow outline of an unselected radio button.
--   auctionhouse-itemicon-empty ... Blizzard_ItemButton/Mainline/
--       ItemButtonTemplate.xml:78, the shared item button's own "nothing here"
--       background.
-- **One thing the canvas drew does not exist**: there is no DASHED ring or
-- dashed slot frame anywhere in that tree (searched for `dash` on 2026-09-17;
-- every hit was `housing-dashboard-*`). The no-rating mark is therefore a
-- hollow ring rather than a dashed one, which says the same thing - not filled
-- in - with art the client actually ships.
EquipPanel.VAULT_ATLAS = "gficon-chest-evergreen-greatvault-collect"
EquipPanel.NOT_OWNED_ATLAS = "transmog-icon-warning-small"
EquipPanel.NO_RATING_ATLAS = "common-radiobutton-circle"
-- The frame an item you do not own is drawn in: the client's own empty item
-- button, under the desaturated icon, so a row you cannot act on looks like a
-- slot with nothing in it rather than like a piece you have.
EquipPanel.GHOST_ICON_ATLAS = "auctionhouse-itemicon-empty"

-- Drawn at the size it is seen at, and the column it sits in.
EquipPanel.MARK_SIZE = 16
EquipPanel.MARK_COLUMN = 22

-- Each mark carries its state's own hex, so the glyph in the column and the
-- segment in the bar are the same colour for the same state and the reader
-- learns one palette rather than two. `swap` is absent on purpose: the worn
-- icon, the arrow and the Equip button are already the picture of a swap, and a
-- sixth glyph beside them would be the badge word coming back as art.
EquipPanel.MARK = {
    equipped_is_best = { atlas = EquipPanel.CHECK_ATLAS, hex = EquipPanel.STATUS_HEX.equipped_is_best },
    best_in_vault = { atlas = EquipPanel.VAULT_ATLAS, hex = EquipPanel.STATUS_HEX.best_in_vault },
    best_not_owned = { atlas = EquipPanel.NOT_OWNED_ATLAS, hex = EquipPanel.STATUS_HEX.best_not_owned },
    no_verdict = { atlas = EquipPanel.NO_RATING_ATLAS, hex = EquipPanel.STATUS_HEX.no_verdict },
}

-- The one verb on this tab that is not a button that acts: an item in the
-- Great Vault cannot be equipped from here, so the row sends the reader to the
-- tab where it can be acted on. A verb that goes somewhere is the only kind
-- allowed (docs/ROADS-UX.md, the verb table: "Show in vault").
EquipPanel.VAULT_VERB = "Vault ›"

-- The one clause a row with nothing to equip carries. Second person, present
-- tense, and it stops a reader hunting his bags for a piece he has never had.
EquipPanel.NOT_OWNED_PHRASE = "you don't own this"

-- What the second line joins the slot word to.
EquipPanel.SECOND_SEPARATOR = " · "

-- The answer sentence's fixed parts. The sentence is the whole tab in one
-- line, in the words a guildmate would type; the clauses in between are built
-- from the rows.
EquipPanel.ANSWER_PROMPT = "Paste a Top Gear export above to fill this panel."
EquipPanel.ANSWER_ALL_BEST = "You're set - every slot is your best."
EquipPanel.ANSWER_NOTHING_RATED = "Nothing you're wearing is rated yet."
EquipPanel.ANSWER_TAIL = " Everything else is your best set."

-- C-14b (WKE-627). **The empty tab, when the reason it is empty is known.**
--
-- `ANSWER_PROMPT` is the right sentence for a player who has never run
-- anything. It was the wrong one for the owner's level-81 Shaman on
-- 2026-09-22: the companion HAD run, it sent all sixteen worn slots, and the
-- rating refused the character because leveling greens are gear it does not
-- know. He was told to paste an export, which would not have helped.
--
-- So when there is no import for this character AND the last run was refused
-- for that reason, the answer says what happened and the line under it says
-- what to do. The quiet facts go to the hint icon, M5-1b's pattern: a condition
-- on the answer is never a line that pushes the list down. With an import on
-- screen - pasted, or an older run that worked - none of this is drawn, because
-- the rating on screen is real.
EquipPanel.UNRATED_HEADER = "Can't rate your gear yet - it's leveling gear the rating doesn't know."
EquipPanel.UNRATED_SECOND = "Hit max level, get some real pieces on, then Refresh."

-- The bar's key, in the order the canvas reads it: what there is to do first,
-- and `already best` last and quiet, because it is the state that needs
-- nothing. Colour is never the only signal, so each colour that is present
-- carries its count in words beside it - and the words are the counts' own
-- labels from CHIP_ORDER, so nothing on this tab invents a second vocabulary
-- for the same five states.
EquipPanel.BAR_KEY_ORDER = {
    "swap",
    "best_in_vault",
    "best_not_owned",
    "no_verdict",
    "equipped_is_best",
}

-- What a shut and an open fold are marked with. Text rather than an atlas, for
-- the reason `UpgradeMapPanel.SECTION_OPEN_MARK` gives: every atlas this addon
-- draws is asked of the client first, and a caret that silently disappeared on
-- a client without the art would take the whole affordance with it.
EquipPanel.FOLD_OPEN_MARK = "-"
EquipPanel.FOLD_SHUT_MARK = "+"

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

-- A rated item as text. The rating names an item by id, bonus IDs and level
-- only, so there is no link to show; the name is asked of the client and is
-- absent whenever the item is not cached, which is honest rather than guessed.
function EquipPanel.VerdictItemText(item)
    if type(item) ~= "table" then
        return "an item the rating did not name"
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

-- The line under a `best_in_vault` row. It quotes the rating's own item level and
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
        name = string.format("%s (rated at %s)", name, tostring(level))
    end
    return string.format("Your best set has a Great Vault option in this slot: %s - see the Vault tab", name)
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
        second = level and string.format("rated at %s", tostring(level)) or "in your best set"
        item = EquipPanel.ItemFromVerdict(row.verdictItem)
        worn = EquipPanel.ItemFromRecord(row.equipped)
    else
        text = string.format("%s - %s", EquipPanel.RecordText(row.equipped), colored(status, "no rating"))
        second = "no rating"
        item = EquipPanel.ItemFromRecord(row.equipped)
    end
    -- A refusal from the last Equip click stands as the row's note until the
    -- row is built again (E-1): it is about this row's item, and no other line
    -- on screen says the bags moved under the scan.
    if row.equipRefusal then
        note = colored("best_not_owned", tostring(row.equipRefusal))
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

-- ---------------------------------------------------------------------------
-- The DRAWN row (M5-1b, WKE-610). `Describe` above is the text model and is
-- untouched; this is the same row as the canvas draws it, and the panel binds
-- both - `Describe` for the item, the worn item and whether there is anything
-- to equip, this for what the row shows.
--
-- Why two functions rather than one changed one: the text `Describe` returns
-- is what `/lootpath status` and the text tests read, and the issue holds it
-- unchanged. What GOES from the screen - the `already equipped` second line
-- and the `already best` badge word - goes from here, where the screen reads.
--
-- Drawn = { second, mark, verb, dim, ghost, note }
--   second  the row's one extra line: the slot word, then the fact the mark
--           cannot carry. An already-best row carries the slot word alone,
--           which is all that is left to say once the tick has said the rest.
--   mark    the fixed-column glyph for this state, or nil on a swap.
--   verb    `Vault ›` on a vault row and nothing anywhere else.
--   dim     an already-best row is drawn at half weight, so the rows that
--           need something read as the only full-weight things on screen.
--   ghost   an item you do not own is drawn as an empty slot.
--   note    a whole sentence under the row, kept for exactly the two cases
--           that are about THIS row and nothing else: the reason a piece is
--           not owned, and a refusal from the last Equip click (E-1). The
--           vault row's old sentence is not here: the mark says where the item
--           is, the second line carries the level the rating used, and the
--           verb goes to the tab that shows it - so the sentence said nothing
--           the row did not already say in three places.
function EquipPanel.Drawn(row, match)
    if type(row) ~= "table" then
        return { second = nil, dim = false }
    end
    local status = row.status
    local slot = type(row.slot) == "string" and row.slot or ""
    local drawn = { status = status, mark = EquipPanel.MARK[status], dim = false }
    local tail
    if status == "equipped_is_best" then
        drawn.dim = true
    elseif status == "swap" then
        tail = row.best and whereText(row.best) or nil
    elseif status == "best_in_vault" then
        local level = type(row.verdictItem) == "table" and row.verdictItem.level or nil
        tail = level and string.format("rated at %s", tostring(level)) or nil
        drawn.verb = EquipPanel.VAULT_VERB
    elseif status == "best_not_owned" then
        tail = EquipPanel.NOT_OWNED_PHRASE
        drawn.ghost = true
        drawn.note = row.reason and colored(status, tostring(row.reason)) or nil
    else
        tail = EquipPanel.NotRatedPhrase(row, match)
    end
    if tail and slot ~= "" then
        drawn.second = slot .. EquipPanel.SECOND_SEPARATOR .. tail
    else
        drawn.second = tail or (slot ~= "" and slot or nil)
    end
    if row.matchedBy == ns.Match.MATCHED_BY_ID_LEVEL and drawn.second then
        drawn.second = drawn.second .. " " .. EquipPanel.NOTE_COLOR .. "[matched by itemID and item level]|r"
    end
    -- A refusal from the last Equip click stands as the row's note until the
    -- row is built again (E-1), and outranks the not-owned reason: it is the
    -- newer thing that happened to this row.
    if row.equipRefusal then
        drawn.note = colored("best_not_owned", tostring(row.equipRefusal))
    end
    return drawn
end

-- Which honesty phrase a `no_verdict` row carries, WITH ITS TAIL WHOLE.
--
-- Not a phrase of this file's own: `ns.Roads.NotRatedPhrase` is the one place
-- that decides between the fixed phrases of `docs/ROADS-UX.md`, and it is
-- asked here with what a match actually carries - the item worn in the slot,
-- and the run's own excluded list, which `Match.Build` already puts on the
-- result. Its third answer needs the later PASSES, which a match does not
-- carry, so this row gets the two answers that are readable from here: beyond
-- the rating's item limit when the run's own list holds the piece, and new
-- since the last refresh when it does not.
function EquipPanel.NotRatedPhrase(row, match)
    local record = type(row) == "table" and row.equipped or nil
    if not (ns.Roads and ns.Roads.NotRatedPhrase and type(record) == "table") then
        return "no rating"
    end
    local excluded = type(match) == "table" and match.excluded or nil
    return (ns.Roads.NotRatedPhrase(excluded, record, record.key))
end

-- ---------------------------------------------------------------------------
-- The answer sentence: the whole tab in one line, first, so a player who reads
-- nothing else still knows what to do tonight.
--
-- It names the things there are to DO and nothing else. A piece you do not own
-- and a slot with no rating are not things to do on this tab, so they stay in
-- the bar's key where they are counted; putting them in the sentence would
-- make it a list of states rather than an answer.
--
-- Names come from `ns.Roads.ShortName`, which is the one place that turns
-- "Venom-Cursed Lynx's Spaulders" into "the Lynx shoulders". More than one
-- piece in a clause is counted rather than listed, because a sentence with
-- four names in it is a list wearing a sentence's clothes.
local function shortName(name, slot)
    if not (ns.Roads and ns.Roads.ShortName) then
        return nil
    end
    return ns.Roads.ShortName({ name = name, slot = slot })
end

local function clientName(itemID)
    if not (C_Item and C_Item.GetItemInfo and itemID) then
        return nil
    end
    local name = ns.Safe(C_Item.GetItemInfo(itemID))
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

-- C-14b (WKE-627). Is this the empty tab with a known cause? Pure over the
-- match and the companion's status file, so one call answers it for all three
-- of the strings below and the tests can put a fixture status in front of it.
--
-- `match` is a table for every import - pasted or from a run - so a character
-- with a rating on screen is never in this state, whatever the last run did.
-- `ns.Companion.UnratedGear` is the only place the state itself is decided.
function EquipPanel.UnratedState(match, status)
    if type(match) == "table" then
        return nil
    end
    local unrated = ns.Companion and ns.Companion.UnratedGear and ns.Companion.UnratedGear(status) or nil
    if not unrated then
        return nil
    end
    return {
        slots = unrated.slots,
        sent = unrated.sent,
        notTaken = unrated.notTaken,
        facts = ns.Companion.UnratedGearFacts(status),
    }
end

-- The line under the answer, or nil: this state is the only thing that has one,
-- because it is the only answer on this tab that is a thing to go and do rather
-- than a thing to read.
function EquipPanel.SecondText(unrated)
    if not unrated then
        return nil
    end
    return EquipPanel.UNRATED_SECOND
end

function EquipPanel.AnswerText(match, unrated)
    if type(match) ~= "table" then
        if unrated then
            return EquipPanel.UNRATED_HEADER
        end
        return EquipPanel.ANSWER_PROMPT
    end
    if not match.ok then
        return EquipPanel.SummaryText(match)
    end
    -- Counted, not measured by the name list: `ShortName` answers nil when a
    -- row has neither a name nor a slot it knows a word for, and a nil would
    -- silently shorten the list rather than the sentence.
    local swaps, vaults = 0, 0
    local swapName, vaultName
    for _, row in ipairs(match.rows or {}) do
        if row.status == "swap" then
            swaps = swaps + 1
            swapName = swapName or shortName(EquipPanel.RecordName(row.best), row.slot)
        elseif row.status == "best_in_vault" then
            vaults = vaults + 1
            local item = type(row.verdictItem) == "table" and row.verdictItem or nil
            vaultName = vaultName or shortName(item and clientName(item.itemID) or nil, row.slot)
        end
    end
    local clauses = {}
    if swaps == 1 and swapName then
        clauses[#clauses + 1] = "Put on " .. swapName
    elseif swaps == 1 then
        clauses[#clauses + 1] = "Put on the piece in your bags"
    elseif swaps > 1 then
        clauses[#clauses + 1] = string.format("Put on %d pieces", swaps)
    end
    if vaults == 1 and vaultName then
        clauses[#clauses + 1] = string.format("grab %s from the vault", vaultName)
    elseif vaults == 1 then
        clauses[#clauses + 1] = "grab a reward from the vault"
    elseif vaults > 1 then
        clauses[#clauses + 1] = string.format("grab %d rewards from the vault", vaults)
    end
    local counts = type(match.counts) == "table" and match.counts or {}
    local best = counts.equipped_is_best or 0
    if #clauses == 0 then
        if best > 0 then
            return EquipPanel.ANSWER_ALL_BEST
        end
        return EquipPanel.ANSWER_NOTHING_RATED
    end
    local sentence = table.concat(clauses, " and ") .. "."
    if best > 0 then
        sentence = sentence .. EquipPanel.ANSWER_TAIL
    end
    return sentence
end

-- ---------------------------------------------------------------------------
-- The bar. One segment per SLOT, in the rows' own order, so it is a picture of
-- the character rather than a score. It counts slots and never value: no
-- arithmetic touches a rating on the way here, and no percent this tab's
-- export does not itself carry appears anywhere near it.
--
-- Bar(match) -> { segments = { { status, hex } ... }, key = { ... } }
function EquipPanel.Bar(match)
    if not (type(match) == "table" and match.ok and type(match.rows) == "table") then
        return { segments = {}, key = {} }
    end
    local segments = {}
    for _, row in ipairs(match.rows) do
        segments[#segments + 1] = {
            status = row.status,
            hex = EquipPanel.STATUS_HEX[row.status] or EquipPanel.STATUS_HEX.no_verdict,
        }
    end
    local label = {}
    for _, chip in ipairs(EquipPanel.CHIP_ORDER) do
        label[chip.key] = chip.label
    end
    local counts = type(match.counts) == "table" and match.counts or {}
    local key = {}
    for _, status in ipairs(EquipPanel.BAR_KEY_ORDER) do
        local count = counts[status] or 0
        if count > 0 then
            key[#key + 1] = {
                status = status,
                count = count,
                text = string.format("%d %s", count, label[status]),
                hex = EquipPanel.STATUS_HEX[status],
                -- `already best` needs nothing done about it, so it is drawn
                -- quiet even in the key.
                quiet = status == "equipped_is_best",
            }
        end
    end
    return { segments = segments, key = key }
end

-- The key as one string, which is what the drawn panel puts in its font
-- string and what a test can read back in one piece.
function EquipPanel.BarKeyText(match)
    local parts = {}
    for _, entry in ipairs(EquipPanel.Bar(match).key) do
        local hex = entry.quiet and EquipPanel.STATUS_HEX.no_verdict or entry.hex
        parts[#parts + 1] = "|cff" .. hex .. entry.text .. "|r"
    end
    return table.concat(parts, "   ")
end

-- ---------------------------------------------------------------------------
-- The fold. Fifteen settled slots are one line by default, with the bar as the
-- proof that nothing is hidden; a caret opens them, dimmed. Which way it is
-- left is remembered PER CHARACTER, the way the Upgrade Map's sections are
-- (`UpgradeMapPanel.CollapseState`), because which character is finished is
-- about the character and not the account.
function EquipPanel.FoldState(db)
    db = db or ns.db
    local char = db and db.char
    if type(char) ~= "table" then
        return { open = false }
    end
    char.equipNow = char.equipNow or {}
    return char.equipNow
end

function EquipPanel.FoldOpen(db)
    return EquipPanel.FoldState(db).bestOpen == true
end

function EquipPanel.ToggleFold(db)
    local state = EquipPanel.FoldState(db)
    -- `nil` rather than `false` when it shuts again, the way the Upgrade Map's
    -- sections do it: the default state leaves nothing behind in the character's
    -- saved variables at all.
    state.bestOpen = (state.bestOpen ~= true) or nil
    return state.bestOpen == true
end

-- What the fold line says. When every slot is already best there is no list
-- above it at all, so it offers the whole list rather than a remainder.
function EquipPanel.FoldText(count, total)
    count = tonumber(count) or 0
    if total and count == total then
        return string.format("show all %d slots", total)
    end
    if count == 1 then
        return "1 slot already best"
    end
    return string.format("%d slots already best", count)
end

-- The drawn order: every row that needs something, in the match's own order
-- and at full weight, then the fold line, then the already-best rows when the
-- fold is open. A row that needs something is never behind the fold.
--
-- Layout(match, open) -> { { kind = "row", row = ... } or { kind = "fold",
-- count = n, total = n, open = bool } ... }
EquipPanel.ELEMENT_ROW = "row"
EquipPanel.ELEMENT_FOLD = "fold"

function EquipPanel.Layout(match, open)
    if not (type(match) == "table" and match.ok and type(match.rows) == "table") then
        return {}
    end
    local open_, folded = {}, {}
    for _, row in ipairs(match.rows) do
        if row.status == "equipped_is_best" then
            folded[#folded + 1] = row
        else
            open_[#open_ + 1] = row
        end
    end
    local elements = {}
    for _, row in ipairs(open_) do
        elements[#elements + 1] = { kind = EquipPanel.ELEMENT_ROW, row = row }
    end
    if #folded > 0 then
        elements[#elements + 1] = {
            kind = EquipPanel.ELEMENT_FOLD,
            count = #folded,
            total = #match.rows,
            open = open and true or false,
        }
        if open then
            for _, row in ipairs(folded) do
                elements[#elements + 1] = { kind = EquipPanel.ELEMENT_ROW, row = row }
            end
        end
    end
    return elements
end

-- The sentence a row says when the bag slot it was built from no longer holds
-- the copy the row means. One sentence, and it names the way out.
EquipPanel.MOVED_NOTE = "this piece moved - /lootpath refresh"

-- The sentence a row says when the client will not name one equipment slot this
-- copy can go into. One sentence, and it names the way out. Nothing is picked
-- up and nothing is equipped: the guess-by-name path it replaces is gone.
EquipPanel.UNMAPPABLE_NOTE = "can't tell where this goes - equip it by hand"

-- Which equipment slot an EMPTY-slot row equips into (E-1a, WKE-605).
--
-- E-1 left one case on the old equip-by-name call: a row with nothing worn in its
-- slot has no `dstSlot`, because `dstSlot` is the scanned `slotIndex` of the
-- item being REPLACED. The owner's legs slot was empty with both leggings in
-- the bags, so that row took the by-name path and the client put on the 295.
--
-- **The slot is asked of the client, never read off a table of ours.** Blizzard
-- ships no INVTYPE_* -> INVSLOT_* table in FrameXML (searched under .luals/ on
-- 2026-09-17: "INVTYPE_HEAD" and "INVTYPE_FINGER" appear only in a heirloom
-- branch and an Encounter Journal filter list, never as a mapping), so writing
-- one here would be a remembered table, which is the thing §7's 2026-09-06
-- decision forbids. What Blizzard DOES expose is the question answered from the
-- other end, and it is the same source its own paper-doll flyout uses:
--
--   GetInventoryItemsForSlot(slot, returnTable)     Wiki.lua:5064-5067
--     fills `returnTable` with [packedLocation] = itemID for every item in the
--     player's bags and bank that CAN be equipped in inventory slot `slot`.
--     Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua:2064-2066 is the
--     flyout's only call; Blizzard_BoostTutorial/Blizzard_TutorialLogic.lua
--     :1158-1200 walks INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED the same
--     way this does.
--   EquipmentManager_GetLocationData(packedLocation)
--     Blizzard_FrameXML/Shared/EquipmentManager.lua:1-29 - unpacks that key
--     into { isPlayer, isBank, isBags, bag, slot }. Its arithmetic is NOT
--     copied here: the client's own function is called, so a change to the
--     packing can never leave a stale copy of it in this file.
--   GetInventoryItemID("player", slot)             Wiki.lua (read-only)
--     tells an empty equipment slot from a full one.
--
-- So the two-slot locations need no special case at all: the client answers
-- both finger slots for a ring and both trinket slots for a trinket, and this
-- takes the EMPTY one, lowest first. Nor do the weapons: whether a two-hander
-- may go in the off hand is the client's answer (Titan's Grip), not ours. An
-- item the client names no slot for - or a client without these functions, or
-- a bank copy with the bank shut - returns nil, and the row refuses.
--
-- Read-only, all three of them: nothing is bought, moved, picked up or equipped
-- here.
function EquipPanel.DestinationSlot(best)
    if type(best) ~= "table" or best.bag == nil or best.slotIndex == nil then
        return nil
    end
    if
        type(GetInventoryItemsForSlot) ~= "function"
        or type(EquipmentManager_GetLocationData) ~= "function"
        or type(GetInventoryItemID) ~= "function"
        or type(INVSLOT_FIRST_EQUIPPED) ~= "number"
        or type(INVSLOT_LAST_EQUIPPED) ~= "number"
    then
        return nil
    end
    local firstEmpty
    for invSlot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local items = {}
        GetInventoryItemsForSlot(invSlot, items)
        local holds = false
        for packed in pairs(items) do
            local where = (ns.Safe(EquipmentManager_GetLocationData((ns.Safe(packed)))))
            if type(where) == "table" and (ns.Safe(where.isBags)) == true then
                local bag = tonumber((ns.Safe(where.bag)))
                local slotIndex = tonumber((ns.Safe(where.slot)))
                if bag == tonumber(best.bag) and slotIndex == tonumber(best.slotIndex) then
                    holds = true
                    break
                end
            end
        end
        if holds and firstEmpty == nil and ns.Safe(GetInventoryItemID("player", invSlot)) == nil then
            firstEmpty = invSlot
        end
    end
    -- Only an EMPTY slot, never an occupied one. This function is reached only
    -- where the row has no `dstSlot`, which is Match saying nothing is worn in
    -- that slot; if the client then names no free slot at all, the two disagree
    -- and the row refuses rather than displacing a piece nobody asked about.
    return firstEmpty
end

-- Does bag `best.bag`, slot `best.slotIndex` still hold the exact copy this row
-- was built from? The scan is a snapshot; bags move between the scan and the
-- click (a loot, a sort, a bank trip), and equipping whatever sits in that slot
-- now would be the same wrong-item bug from the other end.
--
-- C_Container.GetContainerItemInfo(containerIndex, slotIndex) -> ContainerItemInfo
-- (Blizzard's exported ContainerDocumentation.lua:71-75, read under .luals/ on
-- 2026-09-16), whose `hyperlink` and `itemID` fields are declared at :245-257.
-- The link is the strong test - it carries the bonus IDs, so it tells the 321
-- from the 295 - and the itemID is all a row can be held to when the client has
-- no link for that slot.
function EquipPanel.SlotStillHolds(best)
    if type(best) ~= "table" or best.bag == nil or best.slotIndex == nil then
        return false
    end
    local info = ns.Safe(C_Container.GetContainerItemInfo(best.bag, best.slotIndex))
    if type(info) ~= "table" then
        return false
    end
    local link = ns.Safe(info.hyperlink)
    if type(link) == "string" and type(best.link) == "string" then
        return link == best.link
    end
    local itemID = tonumber(ns.Safe(info.itemID))
    return itemID ~= nil and itemID == tonumber(best.itemID)
end

-- Equips one row's item. The combat check is here, not only on the button, so
-- a lockdown that arrives after the panel was drawn still refuses.
--
-- **By bag and slot, not by name** (E-1, WKE-604, 2026-09-16). The owner had
-- two Enigmatic Dreamwatcher's Leggings in his bags, 321 and 295; the row said
-- swap to the 321 and the first click put on the 295, because
-- the old equip-by-name call took an `ItemInfo` - a name, an
-- ID or a link (ItemDocumentation.lua:85-87) - and the client resolves it to
-- the first matching item in the bags. A link's bonus IDs do not narrow it. The
-- scan already recorded exactly which copy the row means, so this path picks
-- that one up and equips what is then on the cursor.
--
-- **Every equippable row now has a slot** (E-1a, WKE-605): a row with nothing
-- worn in its slot gets one from EquipPanel.DestinationSlot, which asks the
-- client which slots take this exact copy, so the equip-by-name call is gone
-- from this file entirely and a row the client will not place refuses instead.
--
-- The seven client functions this path may call, named here the way
-- Captures.lua names the functions its captures call, and nothing else:
--   C_Container.GetContainerItemInfo(bag, slotIndex)  ContainerDocumentation.lua:71-75
--   C_Container.PickupContainerItem(bag, slotIndex)   ContainerDocumentation.lua:159-162
--   EquipCursorItem(slot)                             GameCursorDocumentation.lua:30-32
--   ClearCursor()                                     GameCursorDocumentation.lua:2-3
--   GetInventoryItemsForSlot(slot, returnTable)       Wiki.lua:5064-5067
--   EquipmentManager_GetLocationData(packedLocation)  Shared/EquipmentManager.lua:1-29
--   GetInventoryItemID("player", slot)                Wiki.lua:5037-5042
-- The last three are read-only and pure; only the middle two move anything.
-- Nothing is bought, sold, destroyed, split, sorted or moved anywhere but onto
-- the character. `ClearCursor()` comes FIRST on every path that touches the
-- cursor - Blizzard's own EquipmentManager_EquipContainerItem opens with it
-- (EquipmentManager.lua:97-99, read under .luals/) - so an item left on the
-- cursor by anything, including a row whose equip the client refused, goes back
-- before this one picks anything up, and no click ever begins or ends a refusal
-- with the cursor holding an item.
function EquipPanel.Equip(row)
    if InCombatLockdown() then
        return { ok = false, reason = "combat" }
    end
    if not ns.Match.IsSwap(row) then
        return { ok = false, reason = "there is nothing to equip in this row" }
    end
    local best = row.best
    if not (type(best) == "table" and (best.location == "bag" or best.location == "bank")) then
        row.equipRefusal = EquipPanel.UNMAPPABLE_NOTE
        return { ok = false, reason = EquipPanel.UNMAPPABLE_NOTE, unmappable = true }
    end
    -- `dstSlot` is the equipment slot the scan actually found the replaced item
    -- in, which is what keeps two rings and two trinkets from fighting over one
    -- slot; it is nil when nothing is worn there (Match.lua:259). E-1a fills
    -- that case from the item itself rather than from what is worn, and keeps
    -- the answer on the row so the panel and Equip all see the same slot.
    -- `EquipCursorItem(slot)` declares its slot as required
    -- (GameCursorDocumentation.lua:31), so a row without one cannot be equipped
    -- at all and says so instead of guessing by name.
    if row.dstSlot == nil then
        row.dstSlot = EquipPanel.DestinationSlot(best)
    end
    if row.dstSlot == nil then
        row.equipRefusal = EquipPanel.UNMAPPABLE_NOTE
        return { ok = false, reason = EquipPanel.UNMAPPABLE_NOTE, unmappable = true }
    end
    if not EquipPanel.SlotStillHolds(best) then
        ClearCursor()
        row.equipRefusal = EquipPanel.MOVED_NOTE
        return { ok = false, reason = EquipPanel.MOVED_NOTE, moved = true }
    end
    ClearCursor()
    C_Container.PickupContainerItem(best.bag, best.slotIndex)
    EquipCursorItem(row.dstSlot)
    row.equipRefusal = nil
    return { ok = true, link = best.link, dstSlot = row.dstSlot, bag = best.bag, slotIndex = best.slotIndex }
end

-- Equip all walks the same path, row by row, with the same check per row, and
-- STOPS at the first refusal (E-1): a row that refuses because the bags moved
-- is a scan that no longer matches the bags, so every row after it is just as
-- suspect. The refusal is left on that row, where the panel draws it.
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
                return { ok = true, equipped = equipped, refusals = refusals, stoppedAt = row }
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
        return "Paste a Top Gear export above to fill this panel."
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
            "%d already best, %d to swap, %d waiting in the Great Vault, %d not owned, %d with no rating",
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
function EquipPanel.NoteText(match, unrated)
    if type(match) ~= "table" then
        -- C-14b (WKE-627): in the unrated state the note is the quiet facts
        -- behind the answer - the counts and the slots - and it goes to the
        -- hint icon rather than on screen. The answer above already says the
        -- whole of what happened.
        if unrated then
            return unrated.facts
        end
        return "Paste a Top Gear export above to fill this panel."
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
    -- C-8 (WKE-558): his Top Gear takes thirty items for a non-patron and the
    -- character owns more, so the set above can be an answer about a subset.
    -- The panel says so in the companion's own words - one wording, shared with
    -- the Vault tab - because a verdict that omits items must say so on screen.
    local excluded = EquipPanel.ExcludedText(match)
    if excluded then
        parts[#parts + 1] = EquipPanel.NOTE_COLOR .. excluded .. "|r"
    end
    return table.concat(parts, "  ")
end

-- The C-8 line for a match, or nil. Pure, and kept out of NoteText so the drawn
-- panel can hang the full list off it as a tooltip (WKE-553's style) without
-- rebuilding the wording.
function EquipPanel.ExcludedText(match)
    if type(match) ~= "table" or not match.ok then
        return nil
    end
    if not (ns.Companion and ns.Companion.ExcludedText) then
        return nil
    end
    return ns.Companion.ExcludedText(match.excluded)
end

-- Every left-out item, for that tooltip. Empty when there is nothing to say.
function EquipPanel.ExcludedLines(match)
    if type(match) ~= "table" or not (ns.Companion and ns.Companion.ExcludedLines) then
        return {}
    end
    return ns.Companion.ExcludedLines(match.excluded)
end

-- M5-1a (WKE-597): a key for the row SET, so a refresh can tell a new list
-- from the same list drawn again. It is the slot and the rated item of every
-- row, in order - not the status, not the badge, not where the item is - so
-- equipping a swap, a bag update or a redraw in combat leaves it alone, and a
-- new import or a different match changes it.
function EquipPanel.RowSignature(match)
    if type(match) ~= "table" or not match.ok or type(match.rows) ~= "table" then
        return "none"
    end
    local parts = {}
    for index = 1, #match.rows do
        local row = match.rows[index]
        local key = (row.verdictItem and row.verdictItem.key)
            or (row.equipped and row.equipped.key)
            or (row.best and row.best.key)
            or "-"
        parts[index] = tostring(row.slot or "?") .. "/" .. tostring(key)
    end
    return table.concat(parts, "|")
end

-- Put the list back at its first row. `UIPanelScrollFrameTemplate` keeps its
-- offset across a refresh and across the child being re-sized - Blizzard's own
-- `ScrollFrame_OnScrollRangeChanged` clamps the bar's value to the new range
-- (`math.min(scrollbar:GetValue(), yrange)`) rather than clearing it - so the
-- offset has to be cleared in both places: the frame's own scroll, and the
-- bar's value, which `UIPanelScrollBar_OnValueChanged` pushes straight back
-- into `SetVerticalScroll` at the next range change
-- (Blizzard_SharedXML/SecureScrollTemplates.lua).
function EquipPanel.ScrollToTop(panel)
    if type(panel) ~= "table" or not panel.scroll then
        return false
    end
    local bar = panel.scroll.ScrollBar
    if bar and type(bar.SetValue) == "function" then
        bar:SetValue(0)
    end
    if type(panel.scroll.SetVerticalScroll) == "function" then
        panel.scroll:SetVerticalScroll(0)
    end
    return true
end

-- The scroll frame hangs off the last element of the header block that has
-- something on it: the bar's key when it has text, the bar when the key is
-- empty, the answer sentence when there is no bar, and the header itself when
-- even the answer is blank. An empty font string still occupies a line, and the
-- list's top must not depend on whether this character's bank happens to be
-- open (M5-1a, WKE-597) - the rule is unchanged; M5-1b only changed which
-- elements the header block is made of.
--
-- Its bottom clears the hint icon when there is a hint, and runs to the panel's
-- own floor when there is not, for the same reason: nothing above or below the
-- list may move it about because of a condition the player cannot see.
function EquipPanel.AnchorScroll(panel)
    if type(panel) ~= "table" or not panel.scroll then
        return nil
    end
    local anchor = panel.header
    local answer = panel.answer and panel.answer:GetText()
    if answer and answer ~= "" then
        anchor = panel.answer
    end
    -- C-14b (WKE-627): the line under the answer, when there is one. It is
    -- SHOWN or not rather than empty or not, for the reason the block comment
    -- above gives - an empty font string still takes a line.
    if panel.second and panel.second:IsShown() then
        anchor = panel.second
    end
    if panel.segments and panel.segments[1] and panel.segments[1]:IsShown() then
        anchor = panel.bar
    end
    local key = panel.barKey and panel.barKey:GetText()
    if key and key ~= "" then
        anchor = panel.barKey
    end
    local floor = 4
    if panel.hint and panel.hint:IsShown() then
        floor = floor + EquipPanel.HINT_ROOM
    end
    panel.scroll:ClearAllPoints()
    panel.scroll:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -EquipPanel.TOP_GAP)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -EquipPanel.SCROLL_INSET_RIGHT, floor)
    panel.scrollAnchor = anchor
    return anchor
end

local function tooltipFor(button, text)
    if not (GameTooltip and text) then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- What a row is worth, measured rather than assumed (M5-1c, WKE-617): the
-- clearance above the line, the line's own height as the line reports it, and
-- - when the row has one - the gap and the note under it. Nothing here reads
-- ROW_HEIGHT: a row that ends where its line ends is the whole point, and the
-- note used to be drawn at a constant that the arrow layout had already passed.
function EquipPanel.RowHeight(hasNote)
    local height = EquipPanel.LINE_TOP + UI.ItemLine.Height()
    if hasNote then
        height = height + EquipPanel.NOTE_GAP + EquipPanel.NOTE_HEIGHT
    end
    return height
end

local function createRow(panel, index)
    local row = CreateFrame("Frame", nil, panel.list)
    row:SetSize(panel.rowWidth, EquipPanel.RowHeight(false))
    if index == 1 then
        row:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", panel.rows[index - 1], "BOTTOMLEFT", 0, -EquipPanel.ROW_GAP)
    end
    row:SetPoint("RIGHT", panel.list, "RIGHT", 0, 0)

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

    -- The one verb on this tab that does not act here: a Great Vault option
    -- cannot be equipped from this panel, so the row sends the reader to the
    -- tab that shows it. It sits where the Equip button sits, because a row
    -- has at most one thing to offer and they are never both on.
    row.vault = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.vault:SetSize(64, 20)
    row.vault:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    row.vault:SetText(EquipPanel.VAULT_VERB)
    row.vault:SetScript("OnClick", function()
        if UI.frame and UI.ShowTab then
            UI.ShowTab(UI.frame, UI.VAULT_TAB)
        end
    end)
    row.vault:Hide()

    -- What you are wearing now, on the rows whose answer is a swap. The row's
    -- left edge is the icon now that the slot column is gone (M5-1b): the slot
    -- word moved onto the second line, where it costs nothing on a row that
    -- already had one.
    --
    -- Centred on the line's own icon rather than sat near the row's top: the
    -- line no longer hangs off the arrow, so the pair hangs off the line
    -- (M5-1c, WKE-617) and the three icons read as one band.
    row.worn = UI.ItemLine.CreateIcon(row, { size = EquipPanel.WORN_ICON_SIZE })
    row.worn:SetPoint(
        "TOPLEFT",
        row,
        "TOPLEFT",
        0,
        -(EquipPanel.LINE_TOP + (UI.ItemLine.ICON_SIZE - EquipPanel.WORN_ICON_SIZE) / 2)
    )
    row.worn:Hide()

    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetSize(EquipPanel.ARROW_SIZE, EquipPanel.ARROW_SIZE)
    row.arrow:SetPoint("LEFT", row.worn, "RIGHT", EquipPanel.ARROW_GAP, 0)
    row.arrow:Hide()
    row.arrowText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.arrowText:SetPoint("LEFT", row.worn, "RIGHT", EquipPanel.ARROW_GAP, 0)
    row.arrowText:SetWidth(EquipPanel.ARROW_SIZE)
    row.arrowText:SetJustifyH("CENTER")
    row.arrowText:Hide()

    -- The badge column becomes the mark column: one glyph wide, so everything
    -- the ninety-point slot name and the badge word used to take goes to the
    -- item's name, which is what dropping the column was for.
    row.line = UI.ItemLine.Create(row, { badgeWidth = EquipPanel.MARK_COLUMN })

    -- The note hangs off the LINE, not off a constant (M5-1c, WKE-617): the
    -- sentence belongs to the item above it, so wherever that line ends the
    -- note begins. Anchored at a fixed 38 it was drawn over the line's own
    -- second line on every swap-shaped row, because the arrow layout started
    -- the line below the row's top and 34 points of icon then ran past 38.
    --
    -- Its right-hand end is still the row's, so it takes its width from the
    -- frame - LEFT and RIGHT anchors, no SetWidth - and wraps inside it. It
    -- clears the Equip button because it sits under it, not beside it.
    row.note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.note:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", 0, -EquipPanel.NOTE_GAP)
    row.note:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(true)
    row.note:Hide()

    return row
end

-- Where the item line starts: after the worn icon and the arrow on a pair, and
-- at the row's own left edge on a row that is about one item (M5-1b: there is
-- no slot column to start after).
--
-- ONE vertical rule for both (M5-1c, WKE-617). The line's top is the ROW's
-- top, always, and a pair only moves it sideways by `PAIR_INSET`. The branch
-- this replaces anchored the line to the arrow's own top plus 6, which put the
-- line's top below the row's and its bottom past 38 - the constant the note
-- started at - so the note was drawn over the line's second line. The worn
-- icon and the arrow are centred on the line's icon instead, which is the same
-- picture from the other end.
local function anchorLine(row, paired, button)
    row.line:ClearAllPoints()
    if button then
        row.line:SetPoint("RIGHT", button, "LEFT", -6, 0)
    else
        row.line:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    end
    row.line:SetPoint("TOPLEFT", row, "TOPLEFT", paired and EquipPanel.PAIR_INSET or 0, -EquipPanel.LINE_TOP)
end

function EquipPanel.OnEquipClicked(panel, row)
    local result = EquipPanel.Equip(row.matchRow)
    if not result.ok then
        if result.reason == "combat" then
            ns.Log("%s", EquipPanel.COMBAT_TOOLTIP)
        else
            ns.Log("%s", result.reason)
        end
        -- A refusal the bags caused is drawn on the row it belongs to, so the
        -- redraw happens for that one and not for the two that are only words.
        if result.moved then
            EquipPanel.Refresh(panel, panel.match)
        end
        return
    end
    EquipPanel.Refresh(panel, panel.match)
end

function EquipPanel.Create(parent)
    local panel = CreateFrame("Frame", nil, parent)
    -- Only a default: the window anchors this panel by two corners, which is
    -- what actually sizes it in the client. The number is exactly what those
    -- anchors produce, so a panel built on its own - which is what the render
    -- tests do - is the size the window would have made it (M5-2c, WKE-609).
    panel:SetWidth(ns.UI.PANEL_WIDTH)
    panel.rowWidth = ns.UI.PANEL_WIDTH - EquipPanel.SCROLL_INSET_RIGHT
    panel.rows = {}

    panel.header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.header:SetText("Equip Now")

    -- The answer, first (M5-1b, WKE-610): the whole tab in one line, so a
    -- player who reads nothing else still knows what to do tonight. It wraps
    -- and it takes its width from the panel, so it fits whatever the window is.
    panel.answer = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.answer:SetPoint("TOPLEFT", panel.header, "BOTTOMLEFT", 0, -6)
    panel.answer:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.answer:SetJustifyH("LEFT")
    panel.answer:SetWordWrap(true)

    -- C-14b (WKE-627): one line under the answer, and only where the answer is
    -- something to go and do. It is hidden the rest of the time rather than set
    -- to the empty string, because an empty font string still takes a line
    -- (M5-1a's rule, the one AnchorScroll is built on). It shares the bar's
    -- anchor: the two are never both drawn - this state has no match, and with
    -- no match there are no segments.
    panel.second = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.second:SetPoint("TOPLEFT", panel.answer, "BOTTOMLEFT", 0, -4)
    panel.second:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.second:SetJustifyH("LEFT")
    panel.second:SetWordWrap(true)
    panel.second:Hide()

    -- Then the bar: one segment per slot, in slot order, so it is a picture of
    -- the character rather than a score. The segments are flat colour textures
    -- on a frame that spans the panel, and their widths are shared out at
    -- refresh from the panel's OWN width - never from a number of this file's
    -- (M5-2c, WKE-609).
    panel.bar = CreateFrame("Frame", nil, panel)
    panel.bar:SetHeight(EquipPanel.BAR_HEIGHT)
    panel.bar:SetPoint("TOPLEFT", panel.answer, "BOTTOMLEFT", 0, -6)
    panel.bar:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.segments = {}

    -- And the key, which carries each present colour's count in words, because
    -- colour is never the only signal.
    panel.barKey = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    panel.barKey:SetPoint("TOPLEFT", panel.bar, "BOTTOMLEFT", 0, -4)
    panel.barKey:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.barKey:SetJustifyH("LEFT")
    panel.barKey:SetWordWrap(false)

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
        ns.Log("equipped %d item(s) from your best set.", result.equipped)
        -- The first refusal stopped the walk; it is said once here and drawn on
        -- the row it belongs to by the refresh below.
        if result.refusals[1] then
            ns.Log("%s", result.refusals[1])
        end
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
    -- Where its top goes is `AnchorScroll`'s answer, not a fixed anchor: the
    -- note line above it is empty as often as it is not (M5-1a).
    EquipPanel.AnchorScroll(panel)
    panel.list = CreateFrame("Frame", nil, panel.scroll)
    panel.list:SetSize(panel.rowWidth, EquipPanel.ROW_HEIGHT * EquipPanel.MAX_ROWS)
    panel.scroll:SetScrollChild(panel.list)

    -- The fold, inside the list: the settled slots are one line by default,
    -- with the bar above as the proof that nothing is hidden. It lives on the
    -- scroll child rather than on the panel because the rows it opens come
    -- after it and scroll with it.
    panel.fold = CreateFrame("Button", nil, panel.list)
    panel.fold:SetHeight(EquipPanel.FOLD_HEIGHT)
    panel.fold.text = panel.fold:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.fold.text:SetPoint("LEFT", panel.fold, "LEFT", 0, 0)
    panel.fold.text:SetJustifyH("LEFT")
    panel.fold:SetScript("OnClick", function()
        EquipPanel.ToggleFold(panel.db)
        EquipPanel.Refresh(panel, panel.match)
    end)
    panel.fold:Hide()

    -- The notes that are not about an item - the bank hint, the in-combat
    -- warning, the line about what a run was never shown - are a condition on
    -- the answer and not part of it, so they are an icon with the words on
    -- hover rather than a line that pushes the list down (the canvas's own
    -- recommendation, WKE-598). Nothing is lost: `NoteText` still says all of
    -- it, and the tooltip is that string.
    panel.hint = CreateFrame("Button", nil, panel)
    panel.hint:SetSize(EquipPanel.HINT_SIZE, EquipPanel.HINT_SIZE)
    panel.hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 2)
    panel.hint.icon = panel.hint:CreateTexture(nil, "ARTWORK")
    panel.hint.icon:SetAllPoints()
    panel.hint:SetScript("OnEnter", function(button)
        tooltipFor(button, panel.hintText)
    end)
    panel.hint:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    panel.hint:Hide()

    panel.overflow = panel.list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.overflow:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, 0)
    panel.overflow:SetJustifyH("LEFT")
    panel.overflow:Hide()

    return panel
end

function EquipPanel.Refresh(panel, match)
    panel.match = match
    -- The scroll child is as wide as the panel actually is, asked at layout
    -- time rather than frozen at Create: in the client the window's two corner
    -- anchors are what size this panel, and a frame sized by anchors only
    -- answers GetWidth once the client has laid it out (M5-2c, WKE-609). Until
    -- it does, the default Create derived from ns.UI.PANEL_WIDTH stands.
    local width = panel:GetWidth()
    if width and width > 0 then
        panel.rowWidth = width - EquipPanel.SCROLL_INSET_RIGHT
    end
    panel.list:SetWidth(panel.rowWidth)

    -- The answer first, then the bar, then the key. Everything that is a
    -- CONDITION on the answer rather than part of it goes to the hint icon.
    -- C-14b (WKE-627): asked once, and the three strings under it are drawn
    -- from the one answer, so the header, the line under it and the hint cannot
    -- disagree about which state the tab is in.
    local unrated = EquipPanel.UnratedState(match, ns.companionStatus)
    panel.answer:SetText(EquipPanel.AnswerText(match, unrated))
    local second = EquipPanel.SecondText(unrated)
    panel.second:SetText(second or "")
    panel.second:SetShown(second ~= nil)
    EquipPanel.DrawBar(panel, match)
    panel.hintText = EquipPanel.NoteText(match, unrated)
    if unrated and panel.hintText and panel.hintText ~= "" then
        local atlas = UI.ItemLine.Atlas(EquipPanel.NOT_OWNED_ATLAS)
        if atlas then
            panel.hint.icon:SetAtlas(atlas)
        else
            panel.hint.icon:SetColorTexture(UI.ItemLine.RGB(EquipPanel.STATUS_HEX.no_verdict))
        end
        panel.hint.icon:SetVertexColor(UI.ItemLine.RGB(EquipPanel.STATUS_HEX.no_verdict))
        panel.hint:Show()
    elseif type(match) == "table" and match.ok and panel.hintText and panel.hintText ~= "" then
        local atlas = UI.ItemLine.Atlas(EquipPanel.NOT_OWNED_ATLAS)
        if atlas then
            panel.hint.icon:SetAtlas(atlas)
        else
            panel.hint.icon:SetColorTexture(UI.ItemLine.RGB(EquipPanel.STATUS_HEX.no_verdict))
        end
        -- Grey, not the red the same glyph wears in the mark column: these are
        -- conditions on the answer, not a gap in the set.
        panel.hint.icon:SetVertexColor(UI.ItemLine.RGB(EquipPanel.STATUS_HEX.no_verdict))
        panel.hint:Show()
    else
        -- Before an import, and on a refusal, there is no answer for a note to
        -- be a condition ON: the answer line says the whole of it.
        panel.hint:Hide()
    end

    -- The header block is set: the list's top can be placed now.
    EquipPanel.AnchorScroll(panel)

    local elements = EquipPanel.Layout(match, EquipPanel.FoldOpen(panel.db))
    local rows = (type(match) == "table" and match.ok and match.rows) or {}
    local inCombat = InCombatLockdown() and true or false
    local used = 0
    -- What the last thing drawn was, so the next thing hangs off it: the fold
    -- line sits between the rows that need something and the rows that do not,
    -- so a row's top is no longer always the row above it.
    local previous = nil
    local drawn, folded = 0, 0

    local function place(frame, height)
        frame:ClearAllPoints()
        if previous then
            frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -EquipPanel.ROW_GAP)
        else
            frame:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, 0)
        end
        frame:SetPoint("RIGHT", panel.list, "RIGHT", 0, 0)
        previous = frame
        used = used + height + EquipPanel.ROW_GAP
    end

    for _, element in ipairs(elements) do
        if element.kind == EquipPanel.ELEMENT_FOLD then
            folded = element.count
            panel.fold.text:SetText(
                EquipPanel.NOTE_COLOR
                    .. (element.open and EquipPanel.FOLD_OPEN_MARK or EquipPanel.FOLD_SHUT_MARK)
                    .. " "
                    .. EquipPanel.FoldText(element.count, element.total)
                    .. "|r"
            )
            place(panel.fold, EquipPanel.FOLD_HEIGHT)
            panel.fold:SetHeight(EquipPanel.FOLD_HEIGHT)
            panel.fold:Show()
        elseif drawn < EquipPanel.MAX_ROWS then
            drawn = drawn + 1
            local i = drawn
            local frameRow = panel.rows[i]
            if not frameRow then
                frameRow = createRow(panel, i)
                panel.rows[i] = frameRow
            end
            local matchRow = element.row
            local described = EquipPanel.Describe(matchRow)
            local shownRow = EquipPanel.Drawn(matchRow, match)
            frameRow.matchRow = matchRow
            frameRow.described = described
            frameRow.drawn = shownRow
            EquipPanel.DrawRow(frameRow, described, shownRow, inCombat)
            place(frameRow, frameRow:GetHeight())
            frameRow:Show()
        end
    end
    if folded == 0 then
        panel.fold:Hide()
        panel.fold.text:SetText("")
    end

    local shown = drawn
    for i = shown + 1, #panel.rows do
        panel.rows[i]:Hide()
        -- A hidden row waits for nothing: its request is cancelled, so a late
        -- answer never redraws an item that is no longer on screen.
        UI.ItemLine.ClearIcon(panel.rows[i].worn)
        UI.ItemLine.Clear(panel.rows[i].line)
    end

    if #rows > shown + folded then
        -- Under the last thing that was drawn, not under the list frame: rows
        -- with a note are taller than one line, so the list's own height is no
        -- longer where the list ends.
        panel.overflow:ClearAllPoints()
        panel.overflow:SetPoint("TOPLEFT", previous or panel.list, "BOTTOMLEFT", 0, -EquipPanel.OVERFLOW_GAP)
        panel.overflow:SetText(string.format("%d more row(s) not shown.", #rows - shown - folded))
        panel.overflow:Show()
        -- The gap it is drawn at as well as the line itself, so the scroll
        -- child really is as tall as what is on it (M5-1c, WKE-617).
        used = used + EquipPanel.OVERFLOW_GAP + EquipPanel.NOTE_HEIGHT
    else
        panel.overflow:Hide()
    end

    -- The scroll child is as tall as what is on it, so the scrollbar knows how
    -- far there is to go and a short list does not scroll at all.
    panel.list:SetHeight(math.max(used, 1))

    -- A different list starts at its first row; the same list drawn again keeps
    -- where the player had scrolled to, so a bag update does not throw someone
    -- reading half way down back to the top (M5-1a, WKE-597).
    local signature = EquipPanel.RowSignature(match)
    if signature ~= panel.rowSignature then
        panel.rowSignature = signature
        EquipPanel.ScrollToTop(panel)
    end

    local swaps = (type(match) == "table" and match.ok and match.counts.swap) or 0
    panel.equipAll:SetEnabled(swaps > 0 and not inCombat)
    panel.equipAllReason = inCombat and EquipPanel.COMBAT_TOOLTIP or "There is nothing to swap."
    panel.equipAll:SetShown(swaps > 0)
end

-- The bar's segments: one per slot, in the rows' own order, sharing out the
-- panel's own width. Nothing here reads a number of this file's own - the bar
-- is as wide as the window makes the panel (M5-2c, WKE-609) - and nothing here
-- touches a rating: a segment is a slot, and twenty slots are twenty segments
-- whatever any of them is worth.
function EquipPanel.DrawBar(panel, match)
    local bar = EquipPanel.Bar(match)
    local count = #bar.segments
    local width = panel.bar:GetWidth()
    if not (width and width > 0) then
        width = panel.rowWidth
    end
    local each = count > 0 and math.max((width - (count - 1) * EquipPanel.BAR_SEGMENT_GAP) / count, 1) or 0
    for index = 1, count do
        local texture = panel.segments[index]
        if not texture then
            texture = panel.bar:CreateTexture(nil, "ARTWORK")
            panel.segments[index] = texture
        end
        texture:ClearAllPoints()
        texture:SetSize(each, EquipPanel.BAR_HEIGHT)
        texture:SetPoint("TOPLEFT", panel.bar, "TOPLEFT", (index - 1) * (each + EquipPanel.BAR_SEGMENT_GAP), 0)
        texture:SetColorTexture(UI.ItemLine.RGB(bar.segments[index].hex))
        texture:Show()
    end
    for index = count + 1, #panel.segments do
        panel.segments[index]:Hide()
    end
    panel.bar:SetShown(count > 0)
    panel.barKey:SetText(EquipPanel.BarKeyText(match))
end

-- One row, drawn. Split out of Refresh because Refresh now walks a layout
-- rather than a list, and the two jobs - where a row goes, and what it says -
-- read better apart.
function EquipPanel.DrawRow(frameRow, described, shownRow, inCombat)
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

    -- At most one button per row, so a button on screen always means something
    -- can be done: Equip on a swap, the Vault verb on a vault row, nothing
    -- anywhere else.
    local button = nil
    if described.actionable then
        frameRow.equip:Show()
        frameRow.equip:SetEnabled(not inCombat)
        frameRow.disabledReason = inCombat and EquipPanel.COMBAT_TOOLTIP or nil
        button = frameRow.equip
    else
        frameRow.equip:Hide()
        -- Hidden AND disabled: a row that is not a swap must not be clickable
        -- by any route, including a stale reference to it.
        frameRow.equip:SetEnabled(false)
        frameRow.disabledReason = nil
    end
    if shownRow.verb then
        frameRow.vault:SetText(shownRow.verb)
        frameRow.vault:Show()
        button = frameRow.vault
    else
        frameRow.vault:Hide()
    end

    anchorLine(frameRow, described.worn ~= nil, button)

    UI.ItemLine.Set(frameRow.line, {
        itemID = described.item and described.item.itemID or nil,
        link = described.item and described.item.link or nil,
        name = described.item and described.item.name or nil,
        quality = described.item and described.item.quality or nil,
        itemLevel = described.item and described.item.itemLevel or nil,
        icon = described.item and described.item.icon or nil,
        -- What the canvas kept and what it took away: the second line is the
        -- slot word plus the fact the mark cannot carry, the mark is the state,
        -- and no badge word is bound at all.
        second = shownRow.second,
        mark = shownRow.mark,
        dim = shownRow.dim,
        ghost = shownRow.ghost,
        ghostAtlas = EquipPanel.GHOST_ICON_ATLAS,
        tags = described.tags,
    })

    -- Measured off the line rather than off ROW_HEIGHT (M5-1c, WKE-617): the
    -- row ends where its note ends, and the note starts where the line ends.
    local height = EquipPanel.RowHeight(shownRow.note ~= nil)
    if shownRow.note then
        frameRow.note:SetText(shownRow.note)
        frameRow.note:Show()
    else
        frameRow.note:SetText("")
        frameRow.note:Hide()
    end
    frameRow:SetHeight(height)
    -- The dim is the LINE's, not the row's, and is applied once: the settled
    -- rows this is about carry nothing outside the line - no worn icon, no
    -- button and no note - so dimming the row as well would only halve the
    -- same pixels twice.
    return height
end
