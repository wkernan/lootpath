-- Lootpath/Core.lua
-- Lifecycle, the shared namespace, the secret-value guard, the item key, the
-- capture registry and the /lootpath dispatcher. Every other file registers on
-- `ns`; this file owns nothing product-shaped.
--
-- The product rule, above every other rule: Lootpath never computes a healer
-- value. Every healing number on screen is QE Live's, transported unchanged.

local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
ns.PREFIX = "|cff66ccffLootpath|r: "
ns.onReady = {}
ns.captures = {}
ns.captureOrder = {}

-- Copy guards, inherited from the Healper spike where an unguarded walk of an
-- API table took the client down with an out-of-memory crash on first contact
-- (2026-08-24). The worst case must be a truncated snapshot, never a dead client.
local MAX_COPY_DEPTH = 10
local MAX_COPY_NODES = 50000

ns.MARKERS = {
    secret = "<secret>",
    secretTable = "<secret-table>",
    cycle = "<cycle>",
    maxDepth = "<max-depth>",
    uiObject = "<uiobject>",
    truncated = "<node-budget-exhausted>",
    failed = "<enumeration-failed>",
}
local MARK = ns.MARKERS

function ns.Log(fmt, ...)
    print(ns.PREFIX .. string.format(fmt, ...))
end

-- Secret-value guard. Every value read from the client passes through here
-- before it is stored or shown. Returns the value (or a marker) and whether a
-- secret was seen. Non-secret tables come back unchanged; callers that want a
-- storable copy use ns.CopyRaw.
function ns.Safe(value)
    if issecretvalue and issecretvalue(value) then
        return MARK.secret, true
    end
    local t = type(value)
    if t == "table" then
        if issecrettable and issecrettable(value) then
            return MARK.secretTable, true
        end
        return value, false
    end
    if t == "function" or t == "userdata" or t == "thread" then
        return tostring(value), false
    end
    return value, false
end

-- Deep copy of a table the client handed us, assuming nothing about its keys.
-- Cycles, depth, a node budget and UI objects are guarded; every leaf passes
-- ns.Safe. Numeric keys stay numeric so arrays survive the round trip through
-- SavedVariables. Returns the copy and whether any secret was seen.
function ns.CopyRaw(source, state, depth)
    state = state or { nodes = 0, seen = {} }
    depth = depth or 1
    if type(source) ~= "table" then
        return ns.Safe(source)
    end
    if issecretvalue and issecretvalue(source) then
        return MARK.secret, true
    end
    if issecrettable and issecrettable(source) then
        return MARK.secretTable, true
    end
    if state.seen[source] then
        return MARK.cycle, false
    end
    if depth > MAX_COPY_DEPTH then
        return MARK.maxDepth, false
    end
    state.seen[source] = true
    local out, sawSecret, isUIObject = {}, false, false
    local ok = pcall(function()
        if type(source.GetObjectType) == "function" then
            isUIObject = true
            return
        end
        for k, v in pairs(source) do
            if state.nodes >= MAX_COPY_NODES then
                out._truncated = MARK.truncated
                break
            end
            state.nodes = state.nodes + 1
            local key = type(k) == "number" and k or tostring(k)
            local copied, secret
            if type(v) == "table" then
                copied, secret = ns.CopyRaw(v, state, depth + 1)
            else
                copied, secret = ns.Safe(v)
            end
            out[key] = copied
            sawSecret = sawSecret or secret
        end
    end)
    if not ok then
        return MARK.failed, sawSecret
    end
    if isUIObject then
        return MARK.uiObject, false
    end
    return out, sawSecret
end

-- Calls fn under pcall and returns every result, positionally, as a plain
-- table with `n` set, so raw API returns land in SavedVariables exactly as the
-- client gave them (holes included). A missing function or an error is
-- recorded rather than raised: an API that moved is a finding, not a crash.
local function packResults(ok, ...)
    return ok, { n = select("#", ...), ... }
end

function ns.Probe(fn, ...)
    if type(fn) ~= "function" then
        return { absent = true }
    end
    local ok, results = packResults(pcall(fn, ...))
    if not ok then
        return { error = tostring(results[1]) }
    end
    return results
end

-- Item identity, shared by QEImport and Match (decision 2026-09-05): the
-- itemID plus its bonus IDs, sorted, joined with ":". Two copies of an item at
-- different upgrade levels carry different bonus IDs and are different items
-- to QE Live, so they are different keys here. Returns nil for anything that
-- is not a positive integer itemID with numeric bonus IDs.
function ns.ItemKey(itemID, bonusIDs)
    local id = tonumber(itemID)
    if not id or id <= 0 or id % 1 ~= 0 then
        return nil
    end
    if type(bonusIDs) ~= "table" or #bonusIDs == 0 then
        return tostring(id)
    end
    local sorted = {}
    for i = 1, #bonusIDs do
        local bonus = tonumber(bonusIDs[i])
        if not bonus then
            return nil
        end
        sorted[i] = bonus
    end
    table.sort(sorted)
    return tostring(id) .. ":" .. table.concat(sorted, ":")
end

-- Item link parser. Field layout after `item:` measured on the 2026-09-05
-- transcript and identical to the SimulationCraft addon's offsets: itemID(1),
-- enchantID(2), gems(3-6), suffixID(7), uniqueID(8), linkLevel(9), specID(10),
-- flags(11), context(12), numBonusIDs(13), the bonus IDs, then numModifiers
-- and type:value pairs. Returns nil for anything that is not an item link.
function ns.ParseItemLink(link)
    if type(link) ~= "string" then
        return nil
    end
    -- The item string is not all digits: crafted items carry the crafter's
    -- GUID (`Player-69-0F82625A`) in a trailing field (transcript 2026-09-05,
    -- bank tab 6 slot 32), so anything up to `|h` is accepted and non-numeric
    -- fields read as 0.
    local body = link:match("|Hitem:([^|]+)|h") or link:match("^item:([^|]+)$")
    if not body then
        return nil
    end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = tonumber(field) or 0
    end
    local itemID = fields[1]
    if not itemID or itemID <= 0 then
        return nil
    end
    local numBonus = fields[13] or 0
    local bonusIDs = {}
    for i = 1, numBonus do
        local id = fields[13 + i]
        if id and id ~= 0 then
            bonusIDs[#bonusIDs + 1] = id
        end
    end
    table.sort(bonusIDs)
    local gems = {}
    for i = 3, 6 do
        if fields[i] and fields[i] ~= 0 then
            gems[#gems + 1] = fields[i]
        end
    end
    local modIndex = 13 + numBonus + 1
    local numModifiers = fields[modIndex] or 0
    local modifiers = {}
    for i = 1, numModifiers do
        local base = modIndex + (i - 1) * 2
        modifiers[i] = { type = fields[base + 1] or 0, value = fields[base + 2] or 0 }
    end
    return {
        itemID = itemID,
        enchantID = fields[2] ~= 0 and fields[2] or nil,
        gems = gems,
        linkLevel = fields[9],
        specID = fields[10],
        context = fields[12],
        numBonusIDs = numBonus,
        bonusIDs = bonusIDs,
        modifiers = modifiers,
        key = ns.ItemKey(itemID, bonusIDs),
    }
end

-- Capture registry. `/lootpath capture <name>` runs a registered function and
-- stores its raw result under db.global.captures[name]; tools/sync.ps1 -Pull
-- copies the SavedVariables file back into spec/fixtures/captures/.
--
-- A capture registered with `{ async = true }` is handed a `finish(data,
-- failure)` callback instead of returning its data: the Encounter Journal
-- loads loot asynchronously (EJ_LOOT_DATA_RECIEVED), so `capture journal`
-- cannot be one synchronous call the way env, inventory and vault are. Only
-- one capture runs at a time, and an async one that never calls back is
-- abandoned after ns.CAPTURE_TIMEOUT_SECONDS rather than wedging the command.
ns.CAPTURE_TIMEOUT_SECONDS = 180

function ns.RegisterCapture(name, help, run, opts)
    assert(type(name) == "string" and name ~= "", "capture name required")
    assert(type(run) == "function", "capture '" .. tostring(name) .. "' needs a function")
    if not ns.captures[name] then
        ns.captureOrder[#ns.captureOrder + 1] = name
    end
    ns.captures[name] = { help = help or "", run = run, async = (opts and opts.async) or false }
end

local function storeSnapshot(name, data, startedAt)
    local copy, sawSecret = ns.CopyRaw(data)
    local snapshot = {
        name = name,
        capturedAt = time(),
        capturedAtLocal = date("%Y-%m-%dT%H:%M:%S"),
        build = ns.Probe(GetBuildInfo),
        addonVersion = ns.VERSION,
        sawSecret = sawSecret,
        durationMs = startedAt and (debugprofilestop() - startedAt) or nil,
        data = copy,
    }
    local list = ns.db.global.captures[name] or {}
    ns.db.global.captures[name] = list
    list[#list + 1] = snapshot
    return { ok = true, snapshot = snapshot, count = #list }
end

-- Returns the result for a synchronous capture, or `{ ok = true, pending =
-- true }` for an async one that has not finished yet. `onComplete` is called
-- with the final result either way, exactly once. `args` is whatever the
-- slash command carried after the capture name; captures that take no
-- arguments ignore it.
function ns.RunCapture(name, onComplete, args)
    local function complete(result)
        if onComplete then
            onComplete(result)
        end
        return result
    end
    local entry = ns.captures[name]
    if not entry then
        return complete({
            ok = false,
            reason = string.format(
                "unknown capture '%s' (known: %s)",
                tostring(name),
                table.concat(ns.captureOrder, ", ")
            ),
        })
    end
    if not ns.db then
        return complete({ ok = false, reason = "database not loaded yet" })
    end
    if InCombatLockdown() then
        return complete({ ok = false, reason = "combat" })
    end
    if ns.runningCapture then
        return complete({
            ok = false,
            reason = string.format("capture '%s' is still running", ns.runningCapture),
        })
    end
    local startedAt = debugprofilestop and debugprofilestop() or nil
    if not entry.async then
        local ok, data = pcall(entry.run, args)
        if not ok then
            return complete({ ok = false, reason = string.format("capture '%s' errored: %s", name, tostring(data)) })
        end
        return complete(storeSnapshot(name, data, startedAt))
    end

    ns.runningCapture = name
    local settled
    local function finish(data, failure)
        if settled then
            return
        end
        ns.runningCapture = nil
        if failure then
            settled = complete({ ok = false, reason = string.format("capture '%s' %s", name, tostring(failure)) })
        else
            settled = complete(storeSnapshot(name, data, startedAt))
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(ns.CAPTURE_TIMEOUT_SECONDS, function()
            finish(nil, string.format("gave up after %d seconds", ns.CAPTURE_TIMEOUT_SECONDS))
        end)
    end
    local ok, err = pcall(entry.run, finish, args)
    if not ok then
        finish(nil, string.format("errored: %s", tostring(err)))
    end
    return settled or { ok = true, pending = true, name = name }
end

-- SavedVariables through AceDB. `char` holds the last QE import (M2-1),
-- `global` the journal cache (M3-1) and every capture, `profile` the settings.
ns.DB_DEFAULTS = {
    char = {},
    global = { journalCache = {}, captures = {} },
    profile = { settings = { contentType = "Mythic+" } },
}

local function onAddonLoaded()
    ns.db = LibStub("AceDB-3.0"):New("LootpathDB", ns.DB_DEFAULTS, true)
    for _, fn in ipairs(ns.onReady) do
        fn(ns)
    end
    ns.ready = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        onAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        ns.Log("v%s loaded. /lootpath opens the frame; /lootpath help lists commands.", ns.VERSION)
    end
end)

local HELP = {
    "/lootpath - open the frame (arrives in M2-2)",
    "/lootpath capture <name> - record raw client returns; then /reload and run tools\\sync.ps1 -Pull",
    "/lootpath capture - list the capture commands",
    "/lootpath capture wipe - clear every stored capture",
    "/lootpath status - what is stored",
    "/lootpath help - this list",
}

local function captureCommand(rest)
    local name, args = rest:match("^(%S+)%s*(.-)$")
    if not name then
        ns.Log("captures: %s", table.concat(ns.captureOrder, ", "))
        for _, known in ipairs(ns.captureOrder) do
            ns.Log("  %s - %s", known, ns.captures[known].help)
        end
        return
    end
    name = name:lower()
    if name == "wipe" then
        if ns.db then
            ns.db.global.captures = {}
        end
        ns.Log("captures cleared. /reload to flush.")
        return
    end
    local result = ns.RunCapture(name, function(final)
        if final.ok then
            ns.Log(
                "capture '%s' stored (#%d, %s). /reload, then tools\\sync.ps1 -Pull.",
                name,
                final.count,
                final.snapshot.sawSecret and "secrets seen and masked" or "no secrets"
            )
        else
            ns.Log("capture '%s' refused: %s", name, final.reason)
        end
    end, args)
    if result.pending then
        ns.Log("capture '%s' is running; it reports when it finishes. Stay out of combat.", name)
    end
end

local function statusCommand()
    if not ns.db then
        ns.Log("database not loaded yet.")
        return
    end
    local parts = {}
    for _, known in ipairs(ns.captureOrder) do
        local list = ns.db.global.captures[known]
        parts[#parts + 1] = string.format("%s=%d", known, list and #list or 0)
    end
    ns.Log("captures stored: %s", #parts > 0 and table.concat(parts, " ") or "none")
    local import = ns.db.char.qeImport
    ns.Log(
        "QE Live import: %s",
        (import and import.exportedAt) and ("exported " .. tostring(import.exportedAt)) or "none"
    )
end

function ns.HandleSlash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""
    rest = rest or ""
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "capture" then
        captureCommand(rest)
    elseif cmd == "status" then
        statusCommand()
    else
        for _, line in ipairs(HELP) do
            ns.Log("%s", line)
        end
    end
end

SLASH_LOOTPATH1 = "/lootpath"
SlashCmdList.LOOTPATH = function(msg)
    ns.HandleSlash(msg)
end
