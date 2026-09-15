-- Lootpath/UI/Tooltip.lua (R-2, WKE-563, surface 1 of docs/ROADS-UX.md)
-- The item's part of the plan, on Blizzard's own tooltip.
--
-- Hover an item in your bags, in Lootpath's vault cell or in the Adventure
-- Guide and this block appends to the tooltip the client was already drawing:
--
--   Lootpath · Shoulder · rated 1d 2h ago
--   Catalyst this one.
--   Catalyst · Venom-Cursed Lynx's Spaulders (295) · into the tier shoulders
--       · in your best set
--   Other roads for this slot
--   Vault · open now · Scavenger's Spaulders (308) · ... · 1.73% behind ...
--   Why this? · /lootpath map
--
-- and nothing else. Three roads at most, one sub-header, "Why this?" last,
-- always (principle 10). Explain adds nothing here (principle 11). No source
-- is named anywhere (owner's decision, 2026-09-11, ARCHITECTURE.md §7).
--
-- **Every word on it is the Upgrade Map row's own.** `ns.UpgradeMapPanel.RoadRow`
-- is what builds the parts, so the tooltip and the slot's row that "Why this?"
-- points at cannot say two different things about one road.
--
-- **What the tooltip drops** is the "do:" line and the verb button, which are
-- the row's own - and, since R-2a (WKE-571), every clause whose referent is on
-- another screen: the crest COST clause (the vendor window's gate), the rival
-- clause ("the same charge as the vault Spaulders road", which points at a row
-- this reader cannot see), an item ID standing in for a name, and any road
-- nothing rated. The Upgrade Map keeps all four, because there they are true.
--
-- **The hover path is O(1).** `ns.RoadsCache` holds the answer for every key a
-- road carries, built once per verdict; this file looks it up and formats it.
-- Nothing is walked, rated or computed on a hover.
--
-- What R-0's in-client run measured, and what this is built around
-- (ARCHITECTURE.md §9, the owner's spike of 2026-09-14): 2,566 item-tooltip
-- post-calls in 133 s, avg 0.015 ms each - room to spare for a lookup - but
-- only 250 of them were `GameTooltip`. 1,490 were `ShoppingTooltip1`, 706
-- `ShoppingTooltip2` and 120 `PawnPrivateTooltip1`. **So the handler answers
-- `GameTooltip` and nothing else**, or the block is drawn three times beside
-- one hover and once inside another addon's scratch tooltip.
--
-- Every client function this file calls, named rather than discovered:
--
--   TooltipDataProcessor.AddTooltipPostCall(tooltipType, func)
--       .luals/.../Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199.
--       Blizzard calls it as `func(tooltip, tooltipData)` (same file, line
--       298). The file declares **no remover** of any kind, so what is
--       registered is registered for the session and `Enabled()` is a flag the
--       handler reads first.
--   TooltipUtil.GetDisplayedItem(tooltip)
--       .../TooltipUtil.lua:9 - returns `name, hyperlink, tooltipData.id`. The
--       hyperlink is what is keyed off: the third value is real in the shipped
--       source but the annotated `TooltipData` class does not declare it.
--
-- Nothing runs in combat: `InCombatLockdown()` is the first thing the handler
-- asks after the frame check, and the block is simply not appended. Every
-- value read from the client passes `ns.Safe`.

local _, ns = ...

ns.UI = ns.UI or {}
ns.UI.Tooltip = {}
local Tooltip = ns.UI.Tooltip

-- ---------------------------------------------------------------------------
-- The words.

-- The block's own colour: the note grey every Lootpath panel uses for an aside,
-- so the lines read as one addon's and not as Blizzard's own tooltip text.
Tooltip.NOTE_HEX = ns.UI.ItemLine and ns.UI.ItemLine.GREY or "909296"
-- The header is the one line that is not an aside; it names the addon, the slot
-- and the age, which is what principle 2 requires of every surface.
Tooltip.HEADER_HEX = "FFD100"
Tooltip.SEPARATOR = " · "
Tooltip.HEADER = "Lootpath"
Tooltip.OTHER_ROADS = "Other roads for this slot"
-- Principles 10 and 11 both say the block's last line is "Why this?", always.
-- On the Upgrade Map row it opens the row; on a tooltip it cannot be clicked,
-- so on its own it is a question with no destination - which principle 9
-- forbids ("only where they go somewhere"). It keeps its place and says where
-- to go instead: `/lootpath map` opens the window on the Upgrade Map, which is
-- the tab the row is on (R-2a, WKE-571).
Tooltip.WHY = "Why this? · /lootpath map"

-- What a road whose item the client has not named yet is called ON A TOOLTIP.
-- The panel may print "item 244572 (331)" - a row the reader can watch fill in
-- - but a hover is one glance and an item ID is not a name anybody reads
-- (R-2a, WKE-571: the owner read it on the Crafted road, 2026-09-14). The noun
-- is the road's own kind and nothing else; the level beside it is still the
-- road's own figure.
Tooltip.NAMELESS = {
    craft = "a crafted piece",
    drop = "a drop",
    delve = "a delve reward",
    vault = "a vault reward",
    catalyst = "a tier piece",
    crest = "an upgrade",
    set = "a piece you own",
    keep = "what you have on",
}
Tooltip.NAMELESS_DEFAULT = "an item"

function Tooltip.NamelessText(kind)
    return Tooltip.NAMELESS[kind] or Tooltip.NAMELESS_DEFAULT
end
Tooltip.RATED = "rated %s"
-- A verdict with no time on it is the one thing principle 2 forbids a surface
-- to hide, so the header says the age is missing rather than leaving it off.
Tooltip.RATED_UNKNOWN = "rated at an unknown time"
-- What a plan that is behind the bags says about itself (R-3b, WKE-576,
-- defect 4). `rated 8 hours ago` beside `not rated · new since the last
-- refresh` is the addon knowing the document is behind the world; the header
-- is where it already says how old the document is, so it is where it says
-- what to do about it. The command, not a verb: a tooltip has no buttons.
Tooltip.REFRESH = "/lootpath refresh"

-- "1d 2h ago" is `ns.UI.AgeText`'s, which is what the status strip and the
-- Vault tab already print, so one number never reads two ways.
function Tooltip.AgeText(exportedAt, now)
    if type(exportedAt) ~= "string" or exportedAt == "" then
        return nil
    end
    local text = ns.UI.AgeText(exportedAt, now)
    return type(text) == "string" and text or nil
end

function Tooltip.HeaderText(answer, now)
    local parts = { Tooltip.HEADER }
    local slot = type(answer) == "table" and answer.slot or nil
    if type(slot) == "string" and slot ~= "" then
        parts[#parts + 1] = slot
    end
    local age = Tooltip.AgeText(type(answer) == "table" and answer.exportedAt or nil, now)
    parts[#parts + 1] = age and string.format(Tooltip.RATED, age) or Tooltip.RATED_UNKNOWN
    if type(answer) == "table" and answer.stale == true then
        parts[#parts + 1] = Tooltip.REFRESH
    end
    return table.concat(parts, Tooltip.SEPARATOR)
end

-- One road as the tooltip says it: the source tag, the item as it would
-- arrive, the badge with its referent and level, and the resource line when one
-- is involved. The row is `ns.UpgradeMapPanel.RoadRow`'s, so the words are the
-- slot row's words; what is left off here is the "do:" line and the verb, which
-- are the row's own (surface 1 lists what the tooltip carries, and those two
-- are not on the list).
function Tooltip.RoadText(road, previewLevel)
    if type(road) ~= "table" then
        return nil
    end
    local Panel = ns.UpgradeMapPanel
    local row = Panel.RoadRow(road, previewLevel)
    local parts = {}
    if row.tag then
        parts[#parts + 1] = row.tag
    end
    parts[#parts + 1] = string.format("%s (%s)", row.name or Tooltip.NamelessText(row.kind), tostring(row.itemLevel))
    if row.second then
        parts[#parts + 1] = row.second
    end
    if row.badge then
        parts[#parts + 1] = row.badge.text
    end
    -- The row's facts MINUS the cost and rival clauses, which are true only
    -- where their referents are (Panel.RoadFactEntries says why).
    if row.tooltipFactsText then
        parts[#parts + 1] = row.tooltipFactsText
    end
    return table.concat(parts, Panel.ROAD_SEPARATOR), row
end

-- The whole block as lines, in order, each with the tone it is drawn in. Pure:
-- what the tooltip says is a headless assertion over a cache entry, and no
-- frame is touched anywhere in here.
--
-- `answer` is `ns.Roads.ForItem`'s shape, which is what `ns.RoadsCache` stores.
-- With nothing rated it is a table carrying only a phrase, and the block is the
-- header, the phrase and "Why this?" - never a road, never a sentence, and
-- never a glow (principle 12).
function Tooltip.Lines(answer, opts)
    opts = opts or {}
    local lines = {}
    if type(answer) ~= "table" then
        return lines
    end
    local function add(text, hex, header)
        if type(text) == "string" and text ~= "" then
            lines[#lines + 1] = { text = text, hex = hex or Tooltip.NOTE_HEX, header = header or nil }
        end
    end

    add(Tooltip.HeaderText(answer, opts.now), Tooltip.HEADER_HEX, true)

    -- 2. The item's part of the plan, in chat voice. Absent for a road the plan
    --    takes no position on; `ns.Roads.ItemSentence` is where that is decided.
    add(answer.sentence)

    -- 3. The item's own road - or the honesty phrase with its tail, which
    --    REPLACES it when nothing rated this item (surface 1, principle 3).
    if answer.own then
        add((Tooltip.RoadText(answer.own, opts.previewMythicPlusLevel)))
    elseif answer.phrase then
        add(answer.phrase)
    end

    -- 4. The rest of the three, under one sub-header. `ns.Roads.TOOLTIP_ROADS`
    --    is the whole block's cap and the model already respects it; it is
    --    counted again HERE because "three roads, never more" is a rule of this
    --    surface (principle 10) and must not become true only by accident of
    --    the model having exactly three groups to draw from.
    local others = type(answer.others) == "table" and answer.others or {}
    local shown = answer.own and 1 or 0
    local headed = false
    for _, road in ipairs(others) do
        local text = shown < ns.Roads.TOOLTIP_ROADS and (Tooltip.RoadText(road, opts.previewMythicPlusLevel)) or nil
        if text then
            if not headed then
                add(Tooltip.OTHER_ROADS, Tooltip.NOTE_HEX, true)
                headed = true
            end
            add(text)
            shown = shown + 1
        end
    end

    -- 5. Always last, always there.
    add(Tooltip.WHY)
    return lines
end

-- The lines as plain text, which is what `/lootpath status` style tests read
-- and what the voice guard walks.
function Tooltip.Text(answer, opts)
    local out = {}
    for index, line in ipairs(Tooltip.Lines(answer, opts)) do
        out[index] = line.text
    end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- The answer for one hover.

-- The key a hyperlink carries, through ns.Safe. nil for anything that is not an
-- item link, and nil - never a comparison - for a secret value.
function Tooltip.KeyFromLink(link)
    local safe, secret = ns.Safe(link)
    if secret or type(safe) ~= "string" or safe == "" then
        return nil
    end
    local parsed = ns.ParseItemLink(safe)
    if not parsed then
        return nil
    end
    return parsed.key, parsed.itemID
end

-- What the cache has for this link. Two lookups at most, both table indexes:
-- the item key first, and the item ID at the level the client says the item is
-- when the key misses - which is the Adventure Guide's hover, whose bonus IDs
-- are not the ones any document carries.
function Tooltip.Answer(link)
    local key, itemID = Tooltip.KeyFromLink(link)
    if not key then
        return nil
    end
    local answer = ns.RoadsCache.Lookup(key)
    if answer then
        return answer, key
    end
    local level = ns.ItemData and ns.ItemData.Cached(link) or nil
    level = level and level.itemLevel or nil
    if itemID and level then
        answer = ns.RoadsCache.LookupAtLevel(itemID, level)
        if answer then
            return answer, key
        end
    end
    -- Nothing. **The block appears only for an item the map has an entry
    -- for**, which is every piece in your bags, every vault reward, every drop
    -- the journal walk found and every row the export carries - exactly the
    -- three surfaces the brief names. A chat link, a merchant's stock and an
    -- auction house row get no block at all, because the addon has nothing to
    -- say about them and "not rated" would be a sentence about a question
    -- nobody asked. The phrase belongs on an item you HOLD, and the cache puts
    -- it there.
    return nil
end

-- ---------------------------------------------------------------------------
-- Drawing it.

-- Append the block to a tooltip. Used by the post-call and by Lootpath's own
-- vault cell, so both surfaces draw the same lines through the same function.
function Tooltip.Append(tooltip, answer, opts)
    if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then
        return false
    end
    local lines = Tooltip.Lines(answer, opts)
    if #lines == 0 then
        return false
    end
    for _, line in ipairs(lines) do
        tooltip:AddLine(ns.UI.ItemLine.Colored(line.hex, line.text))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- The hook.

Tooltip.FUNCTION_NAMES = {
    "TooltipDataProcessor.AddTooltipPostCall",
    "TooltipUtil.GetDisplayedItem",
}

local state = { installed = false, enabled = true }
-- Resolved once, when the hook goes in, and called through that reference
-- afterwards: the handler must never index a namespace the client may have
-- moved while it is being called for every item tooltip in the game.
local getDisplayedItem

function Tooltip.Available()
    return type(TooltipDataProcessor) == "table"
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and type(TooltipUtil) == "table"
        and type(TooltipUtil.GetDisplayedItem) == "function"
        and type(Enum) == "table"
        and type(Enum.TooltipDataType) == "table"
        and type(Enum.TooltipDataType.Item) == "number"
end

-- Which tooltips the block belongs on: Blizzard's one game tooltip, and nothing
-- else. R-0 measured what the alternative costs - 90% of the post-calls on the
-- owner's client came from the two shopping tooltips and another addon's
-- private one, and a block on those is the same block drawn three times beside
-- one hover.
function Tooltip.IsOurs(tooltip)
    return tooltip ~= nil and GameTooltip ~= nil and tooltip == GameTooltip
end

function Tooltip.Enabled()
    return state.enabled
end

function Tooltip.SetEnabled(enabled)
    state.enabled = enabled ~= false
    return state.enabled
end

-- The post-call. Every early return here is one R-0 measured or the client
-- rules demand, and they are in the cheapest order: the frame, the flag,
-- combat, then one read and two table indexes.
function Tooltip.OnItemTooltip(tooltip)
    if not state.enabled or not Tooltip.IsOurs(tooltip) then
        return
    end
    if InCombatLockdown() then
        return
    end
    local ok, _, hyperlink = pcall(getDisplayedItem, tooltip)
    if not ok then
        return
    end
    local answer = Tooltip.Answer(hyperlink)
    if not answer then
        return
    end
    Tooltip.Append(tooltip, answer, { previewMythicPlusLevel = Tooltip.PreviewLevel() })
end

-- The key level the client previews for the player, which is what a Mythic+
-- road is valued at (M3-10). Read off the cache's map so the hover path never
-- asks the client.
function Tooltip.PreviewLevel()
    local map = ns.RoadsCache.Map()
    return map and map.previewMythicPlusLevel or nil
end

-- One registration per session. Blizzard's handler declares no remover, so
-- installing twice would draw the block twice.
function Tooltip.Install()
    if state.installed then
        return true
    end
    if not Tooltip.Available() then
        return false
    end
    getDisplayedItem = TooltipUtil.GetDisplayedItem
    local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, Tooltip.OnItemTooltip)
    state.installed = ok
    return ok
end

function Tooltip.Installed()
    return state.installed
end

ns.onReady[#ns.onReady + 1] = function()
    if not Tooltip.Install() then
        ns.Log(
            "this client has no %s; the tooltip block is not installed.",
            table.concat(Tooltip.FUNCTION_NAMES, " / ")
        )
    end
end
