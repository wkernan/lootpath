-- Lootpath/UI/ItemLine.lua (M5-1, WKE-550)
-- One item, drawn the way every addon that lists items draws one and the way
-- QE Live's own cards do: an icon with a quality-coloured border, the item
-- level in the icon's corner, the name in quality colour, a grey second line
-- for the fact the tab is about, a text badge on the right and tag words
-- under it. Every tab renders this widget instead of a font string.
--
-- Read rather than remembered (2026-09-09, all under .luals/ or in the
-- owner's local checkout of QE Live's fork):
--   * Blizzard's Adventure Guide loot row and its item buttons tint
--     `Interface\Common\WhiteIconFrame` by quality
--     (Blizzard_ItemButton/Shared/ItemButtonTemplate.xml line 41, the
--     IconBorder texture), and the colour comes from
--     `ColorManager.GetColorDataForItemQuality`
--     (Blizzard_Colors/Mainline/ColorManager.lua line 52), which reads the
--     ITEM_QUALITY_COLORS table that already carries the 11.1.5 overrides.
--     `C_Item.GetItemQualityColor(quality) -> r, g, b, hex`
--     (Blizzard's exported ItemDocumentation) is the fallback, and the table
--     itself the last one; each is guarded, because a client that lacks one
--     must still draw a row.
--   * The icon is the FIFTH return of `C_Item.GetItemInfoInstant`
--     (ItemDocumentation): static data, so it answers with no server round
--     trip and a row that is still loading still shows the right icon.
--   * QE Live's badge colours are his own, read from his source in
--     `c:\Code\qe-live-fork`: `upgradeColor` in
--     `src/General/Modules/UpgradeFinder/Panels/ItemUpgradeCard.js` line 134
--     returns `#FFDF14` when his number is positive and `#C16719` otherwise,
--     and that file's `downgrade` card style is `opacity: 0.72`. His tag
--     words and their colours are `getItemTags` in
--     `src/General/Modules/TopGear/MiniItemCard.tsx` line 85: leech lime,
--     vault aqua, exclusive orange, tier yellow, catalyst plum, embellishment
--     lightblue. Those are CSS colour words; the hex each one resolves to was
--     read from the CSS named-colour table (`color-name/index.js` in that
--     checkout's node_modules), not from memory.
--
-- **The badge is text, never a bar.** A bar's length would be arithmetic on
-- QE Live's numbers and the first step towards a value of our own; Lootpath
-- never computes a healer value. Every badge string is handed in by the
-- caller, already formatted, and this file only colours it.
--
-- Every client read passes ns.Safe and is wrapped in pcall, because a widget
-- that throws takes the whole window with it. Nothing here runs in combat:
-- it draws what the panel already had.

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.ItemLine = {}
local ItemLine = UI.ItemLine

-- The brand (UX-4b, WKE-611). NOT a tone: a tone is what QE Live thinks of an
-- item, and this says nothing about an item at all - it is the one colour
-- Lootpath's own mark is drawn in, wherever the addon draws one. It lives here
-- because this file owns hex-to-tint and loads before every other UI file.
--
-- #FF1A8C was picked by measurement, not by taste (§7, 2026-09-16). It is no
-- item-quality colour and reads as none of them - its nearest is epic purple at
-- CIEDE2000 25.2 - it is nowhere near the green arrow Baganator draws two
-- corners away (#42FD02, read out of `Pawn\Textures\UpgradeArrow.tga`, the file
-- Baganator's own corner widget names), nowhere near Pawn's pale blue icon
-- (#A4DBFF, read the same way), and nowhere near QE Live's gold, which goes on
-- meaning "better" in the numbers. It carries a WCAG contrast of 5.34 against
-- the near-black keyline it is drawn on and 3.63 against white, so it reads on
-- the dark bag ground and on Blizzard's pale frame both.
--
-- Change this one string and every tinted mark changes with it. The two
-- textures that cannot be tinted where they are used - `mark64` behind the
-- .toc's icon line, `icon256` on the listing tile - carry the same hex in
-- `tools/media/svg/`, and moving the brand means moving it there too and
-- re-rendering (`tools/media/README.md`).
UI.BRAND_HEX = "FF1A8C"

-- The addon's own art, rendered from `tools/media/svg/` (UX-4b). The client
-- appends the extension itself, so no path here names one; every file is a TGA
-- at a power-of-two size and none is a .blp.
UI.MEDIA = {
    MARK16 = [[Interface\AddOns\Lootpath\Media\mark16]],
    MARK64 = [[Interface\AddOns\Lootpath\Media\mark64]],
    WORDMARK = [[Interface\AddOns\Lootpath\Media\wordmark]],
    ICON256 = [[Interface\AddOns\Lootpath\Media\icon256]],
}

ItemLine.ICON_SIZE = 34
ItemLine.NAME_HEIGHT = 16
ItemLine.SECOND_HEIGHT = 14
ItemLine.BADGE_WIDTH = 104
ItemLine.ICON_GAP = 6

-- Blizzard's own quality border, from ItemButtonTemplate.xml.
ItemLine.ICON_BORDER_TEXTURE = [[Interface\Common\WhiteIconFrame]]
-- What Blizzard's journal shows for a row whose item has not arrived.
ItemLine.PLACEHOLDER_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
ItemLine.PLACEHOLDER_NAME = "Retrieving item information"

-- The badge's tones. His palette has exactly two colours - better and worse -
-- so everything that is not one of his verdicts is grey: `none` is "QE Live
-- did not rank this" and `neutral` is "this badge is not one of his numbers
-- at all" (a status word, a count). They share the grey the panels already
-- use for asides, because inventing a third colour of his would be inventing.
ItemLine.GREY = "909296"
ItemLine.TONE = {
    better = { hex = "FFDF14", alpha = 1 },
    worse = { hex = "C16719", alpha = 0.72 },
    none = { hex = ItemLine.GREY, alpha = 1 },
    neutral = { hex = ItemLine.GREY, alpha = 1 },
}
ItemLine.DEFAULT_TONE = "neutral"

-- QE Live's tag words, in his colours (see the header for where each came
-- from). A tag this table does not know is still drawn - in grey, with the
-- word the caller passed - because silence about a tag would be a lie about
-- the item.
ItemLine.TAG = {
    vault = { label = "Vault", hex = "00FFFF" }, -- aqua
    catalyst = { label = "Catalyst", hex = "DDA0DD" }, -- plum
    tier = { label = "Tier", hex = "FFFF00" }, -- yellow
    exclusive = { label = "Exclusive", hex = "FFA500" }, -- orange
    embellishment = { label = "Embellishment", hex = "ADD8E6" }, -- lightblue
    leech = { label = "Leech", hex = "00FF00" }, -- lime
    owned = { label = "Owned", hex = ItemLine.GREY },
}
-- His card separates tags with a slash (MiniItemCard.tsx, "It adds colored
-- tags to the item card, separated by a / where applicable").
ItemLine.TAG_SEPARATOR = " / "

local function colored(hex, text)
    return "|cff" .. hex .. tostring(text) .. "|r"
end
ItemLine.Colored = colored

local function probe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        return nil
    end
    -- Each parenthesised: ns.Safe answers (value, isSecret) and the last one
    -- in a list would otherwise carry its flag out with it.
    return (ns.Safe(a)), (ns.Safe(b)), (ns.Safe(c)), (ns.Safe(d))
end

-- One of this addon's own hex tones as the three numbers a texture's tint
-- takes. The tones above are written as hex because that is how QE Live's own
-- source writes them; a texture wants 0-1 floats, and every surface that needs
-- both used to convert it again in its own file. White for anything this
-- cannot read, because a tint is multiplied over the texture and white is
-- "leave it alone" - never a guessed colour.
function ItemLine.RGB(hex)
    if type(hex) ~= "string" or #hex < 6 then
        return 1, 1, 1
    end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then
        return 1, 1, 1
    end
    return r / 255, g / 255, b / 255
end

-- The quality colour, through Blizzard's three answers in the order the 12.1
-- client itself prefers them. Returns { r, g, b, hex } - hex without the
-- escape, so a caller can put it either in a colour code or on a texture -
-- or nil when no client answers, which is a row with no border rather than a
-- row with a guessed one.
function ItemLine.QualityColor(quality)
    quality = tonumber(quality)
    if quality == nil then
        return nil
    end
    local r, g, b
    local data = probe(ColorManager and ColorManager.GetColorDataForItemQuality, quality)
    if type(data) == "table" then
        r, g, b = tonumber(data.r), tonumber(data.g), tonumber(data.b)
    end
    if not (r and g and b) then
        r, g, b = probe(C_Item and C_Item.GetItemQualityColor, quality)
        r, g, b = tonumber(r), tonumber(g), tonumber(b)
    end
    if not (r and g and b) then
        local colors = ITEM_QUALITY_COLORS
        local entry = type(colors) == "table" and colors[quality] or nil
        if type(entry) == "table" then
            r, g, b = tonumber(entry.r), tonumber(entry.g), tonumber(entry.b)
        end
    end
    if not (r and g and b) then
        return nil
    end
    return {
        r = r,
        g = g,
        b = b,
        hex = string.format(
            "%02x%02x%02x",
            math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5)
        ),
    }
end

-- An atlas the client actually has, with the art's OWN size: `{ name, width,
-- height }`, or nil. Blizzard adds and removes atlases between builds, so every
-- one this addon draws is asked for first (C_Texture.GetAtlasInfo, exported)
-- and the caller shows a word instead when the answer is no.
--
-- `width` and `height` are the client's own figures - the `width` and `height`
-- fields of the AtlasInfo it answers with (Ketho, `---@class AtlasInfo` in
-- Blizzard_APIDocumentationGenerated/TextureUtilsDocumentation.lua) - and this
-- addon knows the size of no atlas: a caller that needs one asks here, at draw
-- time, on the client that has it. A client that answers an atlas but no usable
-- size gets the name and no size, which is "draw it the way you would have
-- anyway" rather than a guessed pair of numbers (V-5a, WKE-607).
function ItemLine.AtlasInfo(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local info = probe(C_Texture and C_Texture.GetAtlasInfo, name)
    if type(info) ~= "table" then
        return nil
    end
    local width = tonumber((ns.Safe(info.width)))
    local height = tonumber((ns.Safe(info.height)))
    if not width or not height or width <= 0 or height <= 0 then
        return { name = name }
    end
    return { name = name, width = width, height = height }
end

-- An atlas name the client actually has, or nil. The name-only half of
-- `ItemLine.AtlasInfo`, kept because most callers only need to know whether
-- there is art to draw or a word to say instead.
function ItemLine.Atlas(name)
    local info = ItemLine.AtlasInfo(name)
    return info and info.name or nil
end

-- What the line will actually draw for an item, in one table: what the caller
-- knew, then what the client has cached, then the client's static data, then
-- Blizzard's own placeholders. `pending` says the client cannot name the item
-- yet - the row is readable either way, which is the whole point.
--
-- item = { itemID, link, levelNote, dropLevel, keyLevel, name, quality,
--          itemLevel, icon, second, badge, tags }
function ItemLine.Resolve(item)
    if type(item) ~= "table" then
        return { pending = false, name = ItemLine.PLACEHOLDER_NAME, icon = ItemLine.PLACEHOLDER_ICON }
    end
    local key = item.link or item.itemID
    local name, quality, itemLevel, icon = item.name, item.quality, item.itemLevel, item.icon
    if key ~= nil and (name == nil or quality == nil or itemLevel == nil) then
        local cached = ns.ItemData.Cached(key)
        if cached then
            name = name or cached.name
            quality = quality or cached.quality
            itemLevel = itemLevel or cached.itemLevel
        end
    end
    if key ~= nil and icon == nil then
        local instant = ns.ItemData.Instant(key)
        icon = instant and instant.icon or nil
    end
    local pending = type(name) ~= "string" or name == ""
    if pending then
        name = RETRIEVING_ITEM_INFO or ItemLine.PLACEHOLDER_NAME
    end
    -- The id is what the loader asks about, and a caller that only had a link
    -- still has one inside it: ns.ParseItemLink is the one link parser.
    local itemID = tonumber(item.itemID)
    if itemID == nil and type(item.link) == "string" then
        local parsed = ns.ParseItemLink(item.link)
        itemID = parsed and parsed.itemID or nil
    end
    return {
        itemID = itemID,
        link = item.link,
        -- Only ever read where there is no link: what the hover says about a
        -- tooltip the client can only draw at the item's base level (M5-3a).
        levelNote = item.levelNote,
        -- What a DROP row prints and at what key level the walk previewed it
        -- (M5-3b). Only a drop row sets them, so no other tab can ever get a
        -- "Drops at" line, and the hover compares them with what the link
        -- draws on its own. Kept apart from `itemLevel`, which every caller
        -- sets and which the client may well have filled in itself.
        dropLevel = tonumber(item.dropLevel),
        keyLevel = tonumber(item.keyLevel),
        name = name,
        quality = quality,
        itemLevel = itemLevel,
        icon = icon or ItemLine.PLACEHOLDER_ICON,
        pending = pending,
    }
end

-- The tag words as one coloured string, or "" when there are none.
function ItemLine.TagText(tags)
    if type(tags) ~= "table" then
        return ""
    end
    local parts = {}
    for _, tag in ipairs(tags) do
        local known = ItemLine.TAG[tag]
        local label = known and known.label or tostring(tag)
        local hex = known and known.hex or ItemLine.GREY
        parts[#parts + 1] = colored(hex, label)
    end
    return table.concat(parts, ItemLine.TAG_SEPARATOR)
end

local function tone(badge)
    local name = type(badge) == "table" and badge.tone or nil
    return ItemLine.TONE[name] or ItemLine.TONE[ItemLine.DEFAULT_TONE]
end

-- The badge as a coloured string, or "" when the row has none. A caller with
-- a colour of its own (Equip Now's status colours) passes `badge.hex` and
-- gets it; everything else takes QE Live's tone.
--
-- `badge.note` is an aside that belongs WITH the verdict but is not part of
-- it - the Upgrade Map's "(at +6)", which names the stored document a number
-- came from (M5-3). It is always grey, whatever tone the verdict is, because
-- it is not one of his numbers; and it shares the badge's font string so the
-- two never drift apart on screen.
function ItemLine.BadgeText(badge)
    if type(badge) ~= "table" or type(badge.text) ~= "string" or badge.text == "" then
        return ""
    end
    local text = colored(badge.hex or tone(badge).hex, badge.text)
    if type(badge.note) == "string" and badge.note ~= "" then
        text = text .. " " .. colored(ItemLine.GREY, badge.note)
    end
    return text
end

-- The grey line under the item on a drop's hover, when the tooltip the client
-- drew is not the level the row printed (M5-3b, WKE-608). Measured by the
-- owner on 2026-09-16: the journal link carries no level of its own - the
-- previewed key level rides on the item context - so the walk read 305 off it
-- with the Adventure Guide previewing key 10, and a later `SetHyperlink` on
-- the same link drew what the link says by itself, 292. The link is right
-- about the item and its track and silent about the +10; the row says the
-- level in its own words instead. **No link is ever built with a level
-- modifier**: a synthesised link would be a made-up item.
--
-- One function decides which line a hover gets, for both cases: the link-less
-- one M5-3a added (the wording comes in as `levelNote`, built where the row
-- knows its difficulty) and this one.
ItemLine.DROP_LEVEL_NOTE_KEYED = "Drops at %d from a +%d · shown at %d above"
ItemLine.DROP_LEVEL_NOTE = "Drops at %d · shown at %d above"
-- The client would not say what the link draws. Then there is no number to
-- print that would be read from anything, and the reader is told only that
-- the tooltip is the link's own level and the row's is the one above it.
ItemLine.OWN_LEVEL_NOTE = "shown at its own level above"

function ItemLine.LevelNote(item, linkLevel)
    if type(item) ~= "table" then
        return nil
    end
    if type(item.link) ~= "string" then
        local note = item.levelNote
        if type(note) == "string" and note ~= "" then
            return note
        end
        return nil
    end
    local dropLevel = tonumber(item.dropLevel)
    if dropLevel == nil then
        return nil
    end
    linkLevel = tonumber(linkLevel)
    if linkLevel == nil then
        return ItemLine.OWN_LEVEL_NOTE
    end
    if linkLevel == dropLevel then
        return nil
    end
    local keyLevel = tonumber(item.keyLevel)
    if keyLevel then
        return string.format(ItemLine.DROP_LEVEL_NOTE_KEYED, dropLevel, keyLevel, linkLevel)
    end
    return string.format(ItemLine.DROP_LEVEL_NOTE, dropLevel, linkLevel)
end

function ItemLine.ShowTooltip(line, anchorTo)
    local item = line.resolved
    if not (GameTooltip and item) then
        return false
    end
    GameTooltip:SetOwner(anchorTo or line, "ANCHOR_RIGHT")
    local hasLink = type(item.link) == "string"
    if hasLink and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(item.link)
    elseif item.itemID and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(item.itemID)
    else
        GameTooltip:SetText(item.name, 1, 1, 1, 1, true)
    end
    -- Without a link - an older walk, a row built before the link was kept -
    -- the client draws the item as it exists in its own expansion, and the
    -- reader is told that in the first line under it rather than left to read
    -- Item Level 28 as if it were the row's number (M5-3a). With one, the
    -- client draws the item the link names at whatever level the link says on
    -- its own, which is not always the level the row was rated at (M5-3b):
    -- asked here, at hover time, through the same guarded probe every other
    -- client read in this file goes through.
    local linkLevel = nil
    if hasLink then
        linkLevel = probe(C_Item and C_Item.GetDetailedItemLevelInfo, item.link)
    end
    local note = ItemLine.LevelNote(item, linkLevel)
    if note and GameTooltip.AddLine then
        GameTooltip:AddLine(colored(ItemLine.GREY, note))
    end
    GameTooltip:Show()
    -- The shopping compare, which is what makes "what does this actually have
    -- on it" one hover away rather than a line of ours. Guarded: it is a
    -- FrameXML global, not an exported API.
    if type(GameTooltip_ShowCompareItem) == "function" then
        pcall(GameTooltip_ShowCompareItem, GameTooltip, anchorTo or line)
    end
    return true
end

local function hideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function hoverTarget(line, frame)
    frame:SetScript("OnEnter", function(self)
        ItemLine.ShowTooltip(line, self)
    end)
    frame:SetScript("OnLeave", hideTooltip)
    return frame
end

-- Create(parent, opts) -> line
--   opts.size       icon edge, default ICON_SIZE
--   opts.badgeWidth the column the badge and the tags share
function ItemLine.Create(parent, opts)
    opts = opts or {}
    local size = tonumber(opts.size) or ItemLine.ICON_SIZE
    local badgeWidth = tonumber(opts.badgeWidth) or ItemLine.BADGE_WIDTH

    local line = CreateFrame("Frame", nil, parent)
    line.iconSize = size
    line:SetHeight(size + 2)

    -- The icon and its border are the icon button's own regions, so a hover
    -- anywhere on the icon is a hover on the item.
    local iconButton = CreateFrame("Button", nil, line)
    iconButton:SetSize(size, size)
    iconButton:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
    line.iconButton = hoverTarget(line, iconButton)

    line.icon = iconButton:CreateTexture(nil, "ARTWORK")
    line.icon:SetAllPoints()

    line.border = iconButton:CreateTexture(nil, "OVERLAY")
    line.border:SetAllPoints()
    line.border:SetTexture(ItemLine.ICON_BORDER_TEXTURE)
    line.border:Hide()

    -- Bottom-right of the icon, where QE Live and every bag addon put it.
    line.level = iconButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    line.level:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -1, 1)
    line.level:SetJustifyH("RIGHT")

    local nameButton = CreateFrame("Button", nil, line)
    nameButton:SetHeight(ItemLine.NAME_HEIGHT)
    nameButton:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", ItemLine.ICON_GAP, 0)
    nameButton:SetPoint("RIGHT", line, "RIGHT", -badgeWidth - ItemLine.ICON_GAP, 0)
    line.nameButton = hoverTarget(line, nameButton)

    line.name = nameButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    line.name:SetAllPoints()
    line.name:SetJustifyH("LEFT")
    -- One line, always: the whole item is one hover away, so a name that does
    -- not fit is truncated rather than allowed to push the row taller.
    line.name:SetWordWrap(false)

    line.second = line:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    line.second:SetPoint("TOPLEFT", nameButton, "BOTTOMLEFT", 0, -1)
    line.second:SetPoint("RIGHT", nameButton, "RIGHT", 0, 0)
    line.second:SetHeight(ItemLine.SECOND_HEIGHT)
    line.second:SetJustifyH("LEFT")
    line.second:SetWordWrap(false)

    line.badge = line:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    line.badge:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, -1)
    line.badge:SetWidth(badgeWidth)
    line.badge:SetJustifyH("RIGHT")
    line.badge:SetWordWrap(false)

    -- The badge's optional atlas (Equip Now's checkmark), drawn instead of the
    -- word when the client has the atlas and hidden when it does not.
    line.badgeIcon = line:CreateTexture(nil, "ARTWORK")
    line.badgeIcon:SetSize(16, 16)
    line.badgeIcon:SetPoint("RIGHT", line.badge, "LEFT", -2, 0)
    line.badgeIcon:Hide()

    line.tags = line:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    line.tags:SetPoint("TOPRIGHT", line.badge, "BOTTOMRIGHT", 0, -2)
    line.tags:SetWidth(badgeWidth)
    line.tags:SetJustifyH("RIGHT")
    line.tags:SetWordWrap(false)

    return line
end

-- Sets one item onto one line. Safe to call over and over on the same frame:
-- a pending request from the item this line used to hold is cancelled first,
-- so a late answer never lands on a row that has moved on.
function ItemLine.Set(line, item)
    ns.ItemData.Cancel(line.request)
    line.request = nil
    line.item = item

    local resolved = ItemLine.Resolve(item)
    line.resolved = resolved

    line.icon:SetTexture(resolved.icon)

    local color = ItemLine.QualityColor(resolved.quality)
    if color then
        line.border:SetVertexColor(color.r, color.g, color.b)
        line.border:Show()
        line.name:SetText(colored(color.hex, resolved.name))
    else
        line.border:Hide()
        line.name:SetText(resolved.name)
    end

    line.level:SetText(resolved.itemLevel and tostring(resolved.itemLevel) or "")

    local second = type(item) == "table" and item.second or nil
    line.second:SetText(type(second) == "string" and second or "")

    local badge = type(item) == "table" and item.badge or nil
    line.badge:SetText(ItemLine.BadgeText(badge))
    line.badge:SetAlpha(tone(badge).alpha or 1)

    local atlas = type(badge) == "table" and ItemLine.Atlas(badge.atlas) or nil
    if atlas then
        line.badgeIcon:SetAtlas(atlas)
        line.badgeIcon:Show()
    else
        line.badgeIcon:Hide()
    end

    line.tags:SetText(ItemLine.TagText(type(item) == "table" and item.tags or nil))

    -- The client cannot name it yet: ask, once, and redraw this line when the
    -- answer comes. If it never comes the row stays exactly as it is - the
    -- question mark and RETRIEVING_ITEM_INFO, which is what Blizzard's own
    -- journal leaves on screen.
    if resolved.pending and resolved.itemID then
        line.request = ns.ItemData.Request(resolved.itemID, function()
            if line.item == item then
                ItemLine.Set(line, item)
            end
        end)
    end

    line:Show()
    return line
end

-- Hides a line and forgets what it was waiting for.
function ItemLine.Clear(line)
    ns.ItemData.Cancel(line.request)
    line.request = nil
    line.item = nil
    line.resolved = nil
    line:Hide()
end

-- ---------------------------------------------------------------------------
-- The icon on its own. Equip Now's swap rows are a pair - what you are wearing,
-- an arrow, what QE Live wants - and the left half of that pair is an icon and
-- nothing else. It is the same three regions as a full line's icon (texture,
-- quality border, level in the corner) and the same hover, so the two halves
-- of a swap are the same object drawn at two sizes.

function ItemLine.CreateIcon(parent, opts)
    opts = opts or {}
    local size = tonumber(opts.size) or ItemLine.ICON_SIZE
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetAllPoints()
    button.border:SetTexture(ItemLine.ICON_BORDER_TEXTURE)
    button.border:Hide()
    button.level = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.level:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.level:SetJustifyH("RIGHT")
    return hoverTarget(button, button)
end

function ItemLine.SetIcon(button, item)
    ns.ItemData.Cancel(button.request)
    button.request = nil
    button.item = item
    local resolved = ItemLine.Resolve(item)
    button.resolved = resolved
    button.icon:SetTexture(resolved.icon)
    local color = ItemLine.QualityColor(resolved.quality)
    if color then
        button.border:SetVertexColor(color.r, color.g, color.b)
        button.border:Show()
    else
        button.border:Hide()
    end
    button.level:SetText(resolved.itemLevel and tostring(resolved.itemLevel) or "")
    if resolved.pending and resolved.itemID then
        button.request = ns.ItemData.Request(resolved.itemID, function()
            if button.item == item then
                ItemLine.SetIcon(button, item)
            end
        end)
    end
    button:Show()
    return button
end

function ItemLine.ClearIcon(button)
    ns.ItemData.Cancel(button.request)
    button.request = nil
    button.item = nil
    button.resolved = nil
    button:Hide()
end
