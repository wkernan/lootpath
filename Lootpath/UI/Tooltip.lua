-- Lootpath/UI/Tooltip.lua (R-2, WKE-563; rewritten UX-3, WKE-599)
-- The item's part of the plan, on Blizzard's own tooltip.
--
-- Hover an item in your bags, in Lootpath's vault cell or in the Adventure
-- Guide and this block appends to the tooltip the client was already drawing:
--
--   Lootpath · Legs
--   Keep these on.
--   Better: Coiled Hex Legguards (344), +1.41% · The Venomous Abyss, Mythic raid
--   Rated 1h ago · /lootpath map
--
-- and nothing else. **Four lines at most, one road, no sub-header.**
--
-- That shape is the owner's, 2026-09-16, hovering his own leggings: "there is a
-- lot of text and this sounds very AI written. It needs to be short, concise,
-- warming to the player and easy for them to understand what this is trying to
-- tell them." The block he read was six lines of middot-joined fragments, and it
-- was `docs/ROADS-UX.md` surface 1 built to the letter. The copy set he approved
-- on 2026-09-17 (WKE-599, 18 cases) is what this file produces; the principles
-- behind it are unchanged and ARCHITECTURE.md §7 dates the change.
--
-- What each line is:
--
--   1. `Lootpath · <slot>`, and nothing else. The age and the command moved to
--      the last line, so a hover does not open on a command.
--   2. the item's part of the plan as one warm plain sentence a friend would
--      say - `ns.Roads.ItemSentence`, which is where every case is decided.
--      Verb first, the reason after a dash, the number only when it IS the
--      reason. Absent for nothing: a road to something you do not hold states
--      its own figure instead (`ns.Roads.WORTH_SENTENCE`).
--   3. the ONE best other road, when one gains - `Better: <item> (<level>),
--      <badge> · <instance>, <difficulty>`. The map has the rest. A road that is
--      BEHIND gets no line at all: "Better:" would be a lie and a reader cannot
--      act on a worse road. A road to something you do not hold uses this line
--      for its own where instead.
--   4. `Rated 1h ago · /lootpath map`, the age in the shortest unit and the one
--      place a command lives. `/lootpath refresh` takes the command's place when
--      this slot's bags hold something the rating never saw (R-3b's `stale`),
--      because then the refresh is the thing to do.
--
-- **What the rewrite CUT, rather than shortened.** The four honesty phrases no
-- longer take a line of their own: three of the four are not actionable from a
-- tooltip, and where a refresh is the cure line 4 already names it. The
-- sub-header "Other roads for this slot" is gone with the roads it headed. "Why
-- this?" is gone and its destination stayed: line 4 carries `/lootpath map`,
-- which is what principle 9 wanted of it. The item's own road line is gone for a
-- piece you hold - it restated the sentence above it and named the item under
-- the cursor. **The crest quote came ON** (M3-17b): on the one road whose cost
-- the vendor has quoted it is the only thing a reader can act on, and the money
-- is dropped because it is never the reason you would or would not crest.
--
-- The panel keeps every clause this drops, because there their referents are
-- visible: `ns.UpgradeMapPanel.RoadRow` is still what builds the words, so the
-- tooltip and the slot's row cannot say two different things about one road. No
-- source is named anywhere (owner's decision, 2026-09-11) and no line says "the
-- plan", "your plan" or "this plan" (owner's decision, 2026-09-16); both are
-- guarded in `spec/voice_spec.lua`.
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
-- The header is the one line that is not an aside; it names the addon and the
-- slot. The age it used to carry is on the last line (UX-3, WKE-599), which is
-- where principle 2's "every verdict has a time" is met now.
Tooltip.HEADER_HEX = "FFD100"
Tooltip.SEPARATOR = " · "
Tooltip.HEADER = "Lootpath"

-- Line 3, and the one word on the block that ranks anything: it is written only
-- over a road that GAINS, so it is the badge's own direction said in a word.
Tooltip.BETTER = "Better: %s (%s)"
-- A crest road's own line 3 (M3-17b, WKE-588): what the vendor quoted, which is
-- the one fact on that road a reader can act on from a tooltip.
Tooltip.BETTER_CREST = "Better: crest it to %d"

-- Line 4. The age in the shortest unit, and the one command on the block.
Tooltip.RATED_AGO = "Rated %s ago"
Tooltip.RATED_NOW = "Rated just now"
-- A verdict with no time on it is the one thing principle 2 forbids a surface
-- to hide, so the line says the age is missing rather than leaving it off.
Tooltip.RATED_UNKNOWN = "Rated: not known"
Tooltip.MAP = "/lootpath map"
-- What a plan that is behind the bags says about itself (R-3b, WKE-576,
-- defect 4). This slot's bags hold a piece the rating never saw, so the one
-- command the block carries is the one that cures that.
Tooltip.REFRESH = "/lootpath refresh"

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

-- The age in the shortest unit that says it, rounded DOWN, so the owner's own
-- "rated 69 minutes ago" reads `1h` (UX-3, WKE-599, reading 7). `ns.UI.AgeText`
-- stays the long form every panel prints; this is the tooltip's, and the two
-- are read off the same elapsed count so they can never disagree about which
-- hour it is.
function Tooltip.ShortAge(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        return nil
    end
    if seconds < 60 then
        return nil -- "just now" has no unit; the caller says it in words
    end
    if seconds < 3600 then
        return string.format("%dm", math.floor(seconds / 60))
    end
    if seconds < 86400 then
        return string.format("%dh", math.floor(seconds / 3600))
    end
    return string.format("%dd", math.floor(seconds / 86400))
end

function Tooltip.AgeText(exportedAt, now)
    if type(exportedAt) ~= "string" or exportedAt == "" then
        return nil
    end
    local seconds = ns.UI.AgeSeconds(exportedAt, now)
    if type(seconds) ~= "number" then
        return nil
    end
    local short = Tooltip.ShortAge(seconds)
    return short and string.format(Tooltip.RATED_AGO, short) or Tooltip.RATED_NOW
end

-- Line 1.
function Tooltip.HeaderText(answer)
    local parts = { Tooltip.HEADER }
    local slot = type(answer) == "table" and answer.slot or nil
    if type(slot) == "string" and slot ~= "" then
        parts[#parts + 1] = slot
    end
    return table.concat(parts, Tooltip.SEPARATOR)
end

-- Line 4. The command is `/lootpath refresh` exactly when the rating is behind
-- the world in THIS slot - `ns.Roads.StaleBags`, which is the same fact the
-- Upgrade Map's slot header ends on - and `/lootpath map` otherwise.
function Tooltip.FooterText(answer, now)
    local age = Tooltip.AgeText(type(answer) == "table" and answer.exportedAt or nil, now)
    local stale = type(answer) == "table" and answer.stale == true
    return table.concat({ age or Tooltip.RATED_UNKNOWN, stale and Tooltip.REFRESH or Tooltip.MAP }, Tooltip.SEPARATOR)
end

-- Where a road's item drops, for a reader who is holding one glance: the
-- instance name alone and the client's own difficulty label. The boss goes -
-- the Upgrade Map's row keeps it - and no name is shortened, because the
-- difficulty label is the client's own string ("Mythic raid", not "Mythic").
function Tooltip.WhereText(road)
    local source = type(road) == "table" and road.source or nil
    if type(source) ~= "table" then
        return nil
    end
    local instance = source.instanceName
    if type(instance) ~= "string" or instance == "" then
        return nil
    end
    if type(source.difficultyLabel) == "string" and source.difficultyLabel ~= "" then
        return string.format("%s, %s", instance, source.difficultyLabel)
    end
    return instance
end

-- Which of the slot's other roads line 3 is about: the first one that GAINS and
-- is not the pick the sentence above has already named. The pick is skipped
-- because a line that restates the line over it is exactly what the owner read
-- on 2026-09-16 - his line 3 named the item under the cursor and his line 2 had
-- said what to do with it - and on a worn piece the pick is always the first
-- other road, being the set group's own.
function Tooltip.BestOther(answer)
    for _, road in ipairs((type(answer) == "table" and answer.others) or {}) do
        if road.planPick ~= true and ns.Roads.IsForward(road) then
            return road
        end
    end
    return nil
end

-- Line 3: the one other road, and only when it gains. Every word of it is
-- `ns.UpgradeMapPanel.RoadRow`'s, so the tooltip and the slot's row cannot say
-- two different things about one road.
function Tooltip.BetterText(road, previewLevel)
    if type(road) ~= "table" or not ns.Roads.IsForward(road) then
        return nil
    end
    local Panel = ns.UpgradeMapPanel
    local row = Panel.RoadRow(road, previewLevel)
    local text
    if road.kind == ns.Roads.KIND_CREST and tonumber(row.itemLevel) then
        -- The Upgrade road says what it costs rather than what it is: the item
        -- is the one under the cursor and naming it back is the line the owner
        -- struck.
        text = string.format(Tooltip.BETTER_CREST, tonumber(row.itemLevel))
        local quote = ns.Roads.CrestQuoteText(road)
        if quote then
            text = text .. " - " .. quote
        end
        return text
    end
    text = string.format(Tooltip.BETTER, row.name or Tooltip.NamelessText(row.kind), tostring(row.itemLevel))
    if row.badge and row.badge.text then
        text = text .. ", " .. row.badge.text
    end
    local where = Tooltip.WhereText(road)
    if where then
        text = text .. Tooltip.SEPARATOR .. where
    end
    return text
end

-- The whole block as lines, in order, each with the tone it is drawn in. Pure:
-- what the tooltip says is a headless assertion over a cache entry, and no
-- frame is touched anywhere in here.
--
-- `answer` is `ns.Roads.ForItem`'s shape, which is what `ns.RoadsCache` stores.
-- With nothing rated it is a table carrying only a phrase, and the block is the
-- header, the sentence the phrase earns and the footer - never a road, never a
-- glow (principle 12).
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

    add(Tooltip.HeaderText(answer), Tooltip.HEADER_HEX, true)
    add(answer.sentence)

    -- Line 3. A road to something you do NOT hold spends it on its own where,
    -- because that is what a reader who cannot act on it needs; everything you
    -- hold spends it on the one other road that gains.
    local own = type(answer.own) == "table" and answer.own or nil
    if own and answer.held ~= true and own.group ~= ns.Roads.GROUP_SET then
        add(Tooltip.WhereText(own))
    else
        add(Tooltip.BetterText(Tooltip.BestOther(answer), opts.previewMythicPlusLevel))
    end

    add(Tooltip.FooterText(answer, opts.now))
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
    -- H-1 (WKE-596): the healing gate. In a non-healer spec there is no answer
    -- about any item - no block, no header, no "Why this?" - because every line
    -- of the block is about a rating for healing gear. It is asked here rather
    -- than in the post-call because this is the one place an answer comes from
    -- on the hover path; `Append` asks it again for the one caller that looks
    -- a key up itself (the Vault tab's cell).
    if ns.Companion and ns.Companion.Gate and ns.Companion.Gate() then
        return nil
    end
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
    -- H-1 (WKE-596): the gate again, because this is the other way in. The
    -- hover path is already silent (`Tooltip.Answer`); the Vault tab's cell
    -- looks its own key up in the cache and hands the answer straight here, so
    -- the block would otherwise still be drawn on a cell hover.
    if ns.Companion and ns.Companion.Gate and ns.Companion.Gate() then
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
