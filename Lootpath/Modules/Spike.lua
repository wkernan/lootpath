-- Lootpath/Modules/Spike.lua (R-0, WKE-561)
-- **Temporary. This file is deleted when R-2 (WKE-563) lands the real tooltip
-- block, and nothing may come to depend on it.** It exists to measure one
-- thing before a surface is built on it: what it costs to sit on Blizzard's
-- item tooltip.
--
-- `docs/ROADS-UX.md` (Buildability) names the risk: the post-call fires for
-- EVERY item tooltip in the game - bags, the Adventure Guide, chat links,
-- merchants, the auction house - so whatever R-2 does there has to be an O(1)
-- lookup or an immediate return. Nobody has measured how often that is, or
-- what one call costs, on the owner's client with his 74 addons. So this
-- counts, and shows the player nothing at all.
--
-- **What it records, and nothing else:** how many item tooltips fired, how long
-- each call took (`debugprofilestop`, min/avg/max), whether the hyperlink was
-- nil, whether it was ever a secret value, which tooltip frame fired, and how
-- often the handler returned at once because the client was in combat. It
-- never reads the item, never looks anything up, never draws a line.
--
-- **Nothing runs in combat.** The first thing the handler does under
-- `InCombatLockdown()` is count that it returned, and return.
--
-- Every client function this file calls, named rather than discovered, the way
-- Currencies.FUNCTION_NAMES and Vault.FUNCTION_NAMES are:
--
--   TooltipDataProcessor.AddTooltipPostCall(tooltipType, func)
--       .luals/vscode-wow-api/Annotations/FrameXML/Annotations/AddOns/
--       Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199. Blizzard
--       calls the registered function as `func(tooltip, tooltipData)` (same
--       file, line 298: `ProcessTooltipPostCalls(tooltipType, self,
--       tooltipData)`). **There is no remover**: the file declares
--       AddTooltipPreCall, AddTooltipPostCall, AddLinePreCall and
--       AddLinePostCall and no Remove* of any kind, which is why
--       `/lootpath spike tooltip off` sets a flag the handler reads first
--       rather than pretending to unhook.
--   TooltipUtil.GetDisplayedItem(tooltip)
--       .../Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua:9 - returns
--       `name, hyperlink, tooltipData.id`, taking the hyperlink from
--       `C_Item.GetItemLinkByGUID(tooltipData.guid)` when the data carries a
--       GUID and from `tooltipData.hyperlink` otherwise.
--
-- The hyperlink passes ns.Safe before anything is decided about it, so a
-- secret value is counted and dropped, never compared or stored.
--
-- The numbers land in `db.global.captures.spike` as an ordinary capture
-- snapshot, so `/reload` plus `tools\sync.ps1 -Pull` brings them back as a
-- committed transcript like every other measurement.

local _, ns = ...

ns.Spike = {}
local Spike = ns.Spike

Spike.CAPTURE = "spike"

Spike.FUNCTION_NAMES = {
    "TooltipDataProcessor.AddTooltipPostCall",
    "TooltipUtil.GetDisplayedItem",
}

local state = { installed = false, enabled = false, counters = nil }

-- Resolved once, when the hook goes in, and called through that reference
-- afterwards: the handler must never index a namespace the client may have
-- moved while it is being called for every item tooltip in the game.
local getDisplayedItem

local function newCounters()
    return {
        startedAt = time(),
        startedAtLocal = date("%Y-%m-%dT%H:%M:%S"),
        startedProfileMs = debugprofilestop(),
        calls = 0,
        totalMs = 0,
        minMs = nil,
        maxMs = nil,
        hyperlinks = 0,
        nilHyperlinks = 0,
        secretHyperlinks = 0,
        errors = 0,
        combatReturns = 0,
        frames = {},
    }
end

-- The tooltip frame's name, or "<unnamed>" for one that has none. Asked through
-- a type check and a pcall because the handler is handed whatever Blizzard
-- passed it, and a spike that errors on someone else's frame is a spike that
-- spams the owner's chat.
local function frameName(tooltip)
    if type(tooltip) ~= "table" or type(tooltip.GetName) ~= "function" then
        return "<no-name-method>"
    end
    local ok, name = pcall(tooltip.GetName, tooltip)
    if not ok then
        return "<name-errored>"
    end
    name = ns.Safe(name)
    return type(name) == "string" and name ~= "" and name or "<unnamed>"
end

-- The post-call itself. Registered once, for Enum.TooltipDataType.Item only.
local function onItemTooltip(tooltip)
    local c = state.counters
    if not state.enabled or not c then
        return
    end
    if InCombatLockdown() then
        c.combatReturns = c.combatReturns + 1
        return
    end
    local startedMs = debugprofilestop()
    local ok, _, hyperlink = pcall(getDisplayedItem, tooltip)
    if not ok then
        c.errors = c.errors + 1
    else
        -- ns.Safe first, then the question: a secret value is a marker string
        -- here, so nothing ever compares or keeps the client's own value.
        local safe, sawSecret = ns.Safe(hyperlink)
        if sawSecret then
            c.secretHyperlinks = c.secretHyperlinks + 1
        elseif safe == nil then
            c.nilHyperlinks = c.nilHyperlinks + 1
        else
            c.hyperlinks = c.hyperlinks + 1
        end
    end
    local elapsed = debugprofilestop() - startedMs
    c.calls = c.calls + 1
    c.totalMs = c.totalMs + elapsed
    if not c.minMs or elapsed < c.minMs then
        c.minMs = elapsed
    end
    if not c.maxMs or elapsed > c.maxMs then
        c.maxMs = elapsed
    end
    local name = frameName(tooltip)
    c.frames[name] = (c.frames[name] or 0) + 1
end

-- Everything the hook needs, present and of the right type. A client that
-- moved any of it is a finding, not a crash.
function Spike.Available()
    return type(TooltipDataProcessor) == "table"
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and type(TooltipUtil) == "table"
        and type(TooltipUtil.GetDisplayedItem) == "function"
        and type(Enum) == "table"
        and type(Enum.TooltipDataType) == "table"
        and type(Enum.TooltipDataType.Item) == "number"
end

-- The hook goes in once per session, whatever `on` and `off` do afterwards:
-- Blizzard's handler has no remover, and registering twice would double every
-- number this is here to measure.
function Spike.Install()
    if state.installed then
        return true
    end
    if not Spike.Available() then
        return false
    end
    getDisplayedItem = TooltipUtil.GetDisplayedItem
    local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, onItemTooltip)
    state.installed = ok
    return ok
end

-- The counters as a plain table, with the derived figures filled in. Every one
-- of them is arithmetic over what was measured; nothing here is an estimate.
function Spike.Counters()
    local c = state.counters
    if not c then
        return nil
    end
    local out = {}
    for k, v in pairs(c) do
        out[k] = v
    end
    out.frames = {}
    for name, count in pairs(c.frames) do
        out.frames[name] = count
    end
    out.elapsedMs = debugprofilestop() - c.startedProfileMs
    out.avgMs = c.calls > 0 and (c.totalMs / c.calls) or 0
    out.callsPerMinute = out.elapsedMs > 0 and (c.calls * 60000 / out.elapsedMs) or 0
    return out
end

-- What the `spike` capture stores. No client value is read here beyond the
-- types of the three names the hook needs.
function Spike.Snapshot()
    return {
        note = "R-0 measurement only (WKE-561); this capture goes away with R-2",
        api = {
            AddTooltipPostCall = type(TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall),
            GetDisplayedItem = type(TooltipUtil and TooltipUtil.GetDisplayedItem),
            itemDataType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item or nil,
        },
        installed = state.installed,
        enabled = state.enabled,
        run = Spike.Counters(),
    }
end

ns.RegisterCapture(Spike.CAPTURE, "what /lootpath spike tooltip counted (R-0 measurement; reads nothing)", function()
    return Spike.Snapshot()
end)

local function store()
    ns.RunCapture(Spike.CAPTURE, function(final)
        if final.ok then
            ns.Log(
                "tooltip spike: numbers stored as capture '%s' (#%d). /reload, then tools\\sync.ps1 -Pull.",
                Spike.CAPTURE,
                final.count
            )
        else
            ns.Log("tooltip spike: numbers not stored: %s", final.reason)
        end
    end)
end

-- The report, as lines, so a test reads exactly what the owner reads. No source
-- is named on any of them (owner decision, ARCHITECTURE.md §7 2026-09-11);
-- they are measurements, and they go to chat, not to a player-facing surface.
function Spike.ReportLines()
    local run = Spike.Counters()
    if not run then
        return { "tooltip spike: not counting yet - /lootpath spike tooltip on" }
    end
    local names = {}
    for name in pairs(run.frames) do
        names[#names + 1] = name
    end
    table.sort(names)
    local frames = {}
    for i, name in ipairs(names) do
        frames[i] = string.format("%s=%d", name, run.frames[name])
    end
    return {
        string.format(
            "tooltip spike: %d item tooltips in %.1f s (%.1f per minute), counting %s",
            run.calls,
            run.elapsedMs / 1000,
            run.callsPerMinute,
            state.enabled and "on" or "off"
        ),
        string.format(
            "tooltip spike: %.4f ms per call (min %.4f, max %.4f, total %.1f)",
            run.avgMs,
            run.minMs or 0,
            run.maxMs or 0,
            run.totalMs
        ),
        string.format(
            "tooltip spike: hyperlink %d, nil %d, secret %d, errored %d, in combat and returned %d",
            run.hyperlinks,
            run.nilHyperlinks,
            run.secretHyperlinks,
            run.errors,
            run.combatReturns
        ),
        string.format("tooltip spike: frames %s", #frames > 0 and table.concat(frames, " ") or "none"),
    }
end

function Spike.TooltipOn()
    if not Spike.Install() then
        ns.Log("tooltip spike: this client has no %s; nothing installed.", table.concat(Spike.FUNCTION_NAMES, " / "))
        return false
    end
    state.counters = newCounters()
    state.enabled = true
    ns.Log("tooltip spike: counting. /lootpath spike tooltip report prints the numbers, off stops counting.")
    return true
end

function Spike.TooltipOff()
    if not state.enabled then
        ns.Log("tooltip spike: already off.")
        return false
    end
    state.enabled = false
    ns.Log("tooltip spike: stopped.")
    store()
    return true
end

function Spike.TooltipReport()
    for _, line in ipairs(Spike.ReportLines()) do
        ns.Log("%s", line)
    end
    -- Stored as well as printed: the owner's run ends in a `/reload`, and a
    -- number that only ever reached chat is a number no transcript carries.
    if state.counters then
        store()
    end
end

local HELP = {
    "/lootpath spike tooltip on - start counting item tooltips (measurement only; nothing is shown)",
    "/lootpath spike tooltip off - stop counting and store the numbers",
    "/lootpath spike tooltip report - print the numbers and store them",
}

function Spike.Command(rest)
    local what, action = (rest or ""):match("^(%S*)%s*(.-)$")
    what = (what or ""):lower()
    action = (action or ""):lower()
    if what ~= "tooltip" then
        for _, line in ipairs(HELP) do
            ns.Log("%s", line)
        end
        return
    end
    if action == "on" then
        Spike.TooltipOn()
    elseif action == "off" then
        Spike.TooltipOff()
    elseif action == "report" or action == "" then
        Spike.TooltipReport()
    else
        for _, line in ipairs(HELP) do
            ns.Log("%s", line)
        end
    end
end
