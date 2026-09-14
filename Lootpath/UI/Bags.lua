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

ns.onReady[#ns.onReady + 1] = function()
    Bags.Install()
end
