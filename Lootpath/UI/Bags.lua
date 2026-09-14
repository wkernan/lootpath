-- Lootpath/UI/Bags.lua (R-2, WKE-563)
-- One glow interface, one adapter per bag addon (the owner's question,
-- 2026-09-14, ARCHITECTURE.md §7).
--
-- The core exposes `ns.Glow.Wants(key)` and nothing else about bags. This file
-- is the detector: at load it asks which bag frame is actually drawing the
-- player's bags and hands that one adapter the job. An adapter knows no road,
-- no rating and no plan; it asks that one function and draws its own texture in
-- its own frame system.
--
-- **Two adapters ship with this issue**, because those are the two frames the
-- owner's client can draw:
--
--   * `UI/Bags/Baganator.lua` - the owner's own, read off his screenshot of
--     2026-09-14 (the single-view "Hotornot's Bags" window). It goes in through
--     `Baganator.API.RegisterCornerWidget`, NOT `RegisterUpgradePlugin`: only
--     one upgrade plugin is active at a time, so taking that slot would
--     displace Pawn's green arrow, and the owner has not asked for that.
--   * `UI/Bags/Blizzard.lua` - the client's own container frames, for the
--     second user and for a session with Baganator disabled.
--
-- **A bag addon with no adapter gets no glow, and the tooltip still works.**
-- That is the honest fallback: the tooltip block is bag-independent (every bag
-- addon routes its hovers through Blizzard's tooltip - R-0 saw every hover in
-- Baganator), so a player on ElvUI, Bagnon or AdiBags loses the mark and keeps
-- every word. Those are future adapters, never core changes.

local _, ns = ...

ns.UI = ns.UI or {}
ns.UI.Bags = {}
local Bags = ns.UI.Bags

-- The adapters, in the order they are asked, which is the order of preference.
-- Each registers itself here as its file loads, so the `.toc` IS the preference
-- list: Baganator before Blizzard, because a player who has Baganator loaded is
-- looking at Baganator's window and the client's container frames are still
-- there behind it. The first adapter that says it is live wins.
Bags.adapters = {}

function Bags.Register(adapter)
    Bags.adapters[#Bags.adapters + 1] = adapter
    return adapter
end

local state = { chosen = nil, reason = nil }

-- Which adapter draws the glow this session. Asked once, at load, because a bag
-- addon is enabled or not for the whole session - and asked again by hand only
-- in a test.
function Bags.Choose()
    for _, adapter in ipairs(Bags.adapters) do
        if adapter.Available() then
            state.chosen = adapter
            state.reason = adapter.name
            return adapter
        end
    end
    state.chosen = nil
    state.reason = nil
    return nil
end

function Bags.Chosen()
    return state.chosen
end

-- What the status strip's tooltip says about the mark, in the same voice as
-- everything else: what it does, and where, or that it does not.
Bags.NO_ADAPTER = "bag glow: this bag window is not one Lootpath can mark; the tooltip still works"
Bags.GLOW_LINE = "bag glow: %s"

function Bags.StatusText()
    local adapter = state.chosen
    if not adapter then
        return Bags.NO_ADAPTER
    end
    -- An adapter that can tell it is installed but NOT drawing says so here
    -- rather than letting the strip promise a mark the reader cannot see
    -- (R-2a, WKE-571). Only the adapter knows; the strip only prints.
    if type(adapter.StatusNote) == "function" then
        local note = adapter.StatusNote()
        if type(note) == "string" and note ~= "" then
            return note
        end
    end
    return string.format(Bags.GLOW_LINE, adapter.label)
end

function Bags.Install()
    local adapter = Bags.Choose()
    if not adapter then
        return false, Bags.NO_ADAPTER
    end
    local ok = adapter.Install() == true
    if not ok then
        state.chosen = nil
        return false, Bags.NO_ADAPTER
    end
    return true, Bags.StatusText()
end

-- Every adapter redraws through this, so a rebuilt map reaches whichever bag is
-- open without any of them knowing what a rebuild is.
function Bags.Refresh()
    local adapter = state.chosen
    if adapter and type(adapter.Refresh) == "function" then
        return adapter.Refresh()
    end
    return false
end

function Bags.Reset()
    state.chosen = nil
    state.reason = nil
end

-- ---------------------------------------------------------------------------
-- The diagnosis (R-2a, WKE-571).
--
-- The owner's first real screens showed no mark on any slot, and NOTHING ON
-- SCREEN told the three possible causes apart: the adapter never installed,
-- the bag addon never draws the widget, or the lookup answers false. Each of
-- those is a different fix and a screenshot cannot say which. So the addon says
-- it itself, in one command, and the next diagnosis is one line rather than
-- another round of photographs.
--
-- Pure over what it is handed: every client read is the caller's (`/lootpath
-- glow` in Core.lua, which passes the link), so the lines are a headless
-- assertion and a test can drive them without a bag frame.

Bags.NO_MAP = "map: nothing built yet"
Bags.MAP_LINE = "map: %d keys, %d of them marked"
Bags.MAP_EMPTY = "map: nothing built - %s"
Bags.NO_LINK = "item: no link given; hover a bag slot and shift-click it into the command"
Bags.BAD_LINK = "item: that is not an item link"

-- What the map says about one link, in the four steps a false answer can fail
-- at: the key the link makes, whether that key is in the map, what the map
-- says about it, and whether the item's own road is one the plan points at.
-- These four are the whole of `ns.Glow.WantsLink`, said out loud.
function Bags.LinkLines(link)
    local lines = {}
    local safe, secret = ns.Safe(link)
    if secret or type(safe) ~= "string" or safe == "" then
        lines[#lines + 1] = Bags.NO_LINK
        return lines
    end
    local parsed = ns.ParseItemLink(safe)
    if not parsed or not parsed.key then
        lines[#lines + 1] = Bags.BAD_LINK
        return lines
    end
    lines[#lines + 1] = string.format("item: key %s", parsed.key)
    local answer = ns.RoadsCache.Lookup(parsed.key)
    lines[#lines + 1] = string.format("item: %s the map", answer and "in" or "NOT in")
    lines[#lines + 1] = string.format("item: glow %s", ns.Glow.Wants(parsed.key) and "yes" or "no")
    local own = answer and answer.own or nil
    if own then
        lines[#lines + 1] = string.format(
            "item: its own road is %s, and the plan %s it",
            tostring(own.kind),
            ns.Roads.IsForward(own) and "points at" or "does not point at"
        )
    elseif answer then
        lines[#lines + 1] = string.format("item: no road of its own - %s", tostring(answer.phrase))
    end
    return lines
end

-- The whole answer: which adapter, what the bag addon says about it, what the
-- map holds, and what all of that comes to for one item.
function Bags.DiagnosisLines(link)
    local lines = {}
    local adapter = state.chosen
    if adapter then
        lines[#lines + 1] = string.format("adapter: %s - %s", adapter.name, adapter.label)
    else
        local names = {}
        for _, candidate in ipairs(Bags.adapters) do
            names[#names + 1] = candidate.name
        end
        lines[#lines + 1] = string.format(
            "adapter: none. %s said no.",
            #names > 0 and table.concat(names, ", ") or "no adapter is registered, which"
        )
    end
    if adapter and type(adapter.DiagnosisLines) == "function" then
        for _, line in ipairs(adapter.DiagnosisLines()) do
            lines[#lines + 1] = line
        end
    end
    local map = ns.RoadsCache.Map()
    if not map then
        lines[#lines + 1] = Bags.NO_MAP
    elseif map.reason then
        lines[#lines + 1] = string.format(Bags.MAP_EMPTY, map.reason)
    else
        lines[#lines + 1] = string.format(Bags.MAP_LINE, map.counts.keys, map.counts.glowing)
    end
    for _, line in ipairs(Bags.LinkLines(link)) do
        lines[#lines + 1] = line
    end
    return lines
end

ns.onReady[#ns.onReady + 1] = function()
    Bags.Install()
end
