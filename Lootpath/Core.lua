-- Lootpath/Core.lua
-- Lifecycle, the shared namespace, the secret-value guard, the item key, the
-- capture registry and the /lootpath dispatcher. Every other file registers on
-- `ns`; this file owns nothing product-shaped.
--
-- The product rule, above every other rule: Lootpath never computes a healer
-- value. Every healing number on screen is QE Live's, transported unchanged.

local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = (function()
    -- The .toc ships `## Version: @project-version@` and the BigWigs packager
    -- substitutes that token only when it builds a release, so a copy synced
    -- into the client by tools\sync.ps1 carries the token itself. Measured in
    -- game 2026-09-06: the window's title bar read "Lootpath @project-version@"
    -- (WKE-530 finding 5). A value that still starts with the substitution
    -- marker is not a version, so the fallback below stands instead. The fix is
    -- here rather than in sync.ps1 or the .toc, which stay what the packager
    -- reads.
    local value = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    if type(value) ~= "string" or value == "" or value:sub(1, 1) == "@" then
        return "dev"
    end
    return value
end)()
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

-- ISO 8601 in UTC -> epoch second, or nil for anything this cannot read. QE
-- Live stamps its exports that way ("2026-09-06T21:14:24.465Z", read from the
-- committed export) and the companion stamps `writtenAt` the same way, so both
-- the window's age line and the companion's freshness check read one function.
--
-- `time(t)` reads its fields as LOCAL time and `date("!*t", t)` writes UTC
-- ones, so the difference between the two at `now` is this machine's offset
-- from UTC, and adding it back turns UTC fields into an epoch.
--
-- **Both tables carry `isdst = false`, and that is the whole of the fix for
-- V-4** (WKE-589, 2026-09-15): C's `mktime`, which `time` is, reads that field.
-- Absent it means "decide for yourself", `false` means "these fields are
-- standard time", and the two answers differ by an hour while daylight time is
-- in effect. Until this commit the offset table said `false` (it is what
-- `date("!*t")` writes) and the stamp table said nothing, so during daylight
-- time the offset came out an hour too large and every age and clock the addon
-- printed was an hour too old - the owner read `written 62 minutes ago` for a
-- stamp two minutes old, 2026-09-15 17:22 CDT. Saying `false` on BOTH sides
-- makes the two interpretations cancel exactly, whatever the zone and whichever
-- side of a daylight boundary the stamp falls on: measured under
-- TZ=America/Chicago on 2026-09-15, this pairing was exact for a two-minute-old
-- stamp in summer and in winter, across the November fall-back, and for a
-- stamp half a year old, where letting `mktime` decide was an hour out.
-- `Lootpath/UI/VaultPanel.lua`'s own reader has always paired them this way.
--
-- Nothing here assumes a timezone. A stamp that cannot be read produces nil
-- rather than a wrong second.
function ns.EpochFromISO(iso, now)
    if type(iso) ~= "string" then
        return nil
    end
    local year, month, day, hour, minute, second = iso:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if not year then
        return nil
    end
    now = now or time()
    local utcNow = date("!*t", now)
    if type(utcNow) ~= "table" then
        return nil
    end
    utcNow.isdst = false
    local offset = now - time(utcNow)
    -- Every field is coerced to a number here rather than inside the table
    -- constructor: `time`'s declared field types are not optional, and a
    -- `tonumber` that LuaLS reads as `number?` fails the type gate. The pattern
    -- above matched six groups of digits, so none of these can be nil.
    local fields = {
        year = tonumber(year) or 0,
        month = tonumber(month) or 0,
        day = tonumber(day) or 0,
        hour = tonumber(hour) or 0,
        min = tonumber(minute) or 0,
        sec = tonumber(second) or 0,
        -- The other half of the pair above: read as standard time, exactly as
        -- `utcNow` was, so the offset that is added back undoes it exactly.
        isdst = false,
    }
    return time(fields) + offset
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

-- The inverse of ItemKey: the sorted bonus IDs a key carries, as numbers, or an
-- empty list when it carries none. It lives here, beside the one definition of
-- the format, so nothing else has to know that a key is joined with colons.
--
-- The Vault panel needs it (C-6, WKE-540): a vault reward record carries the key
-- and not the bonus IDs, and recognising QE Live's own catalyzed copy of an
-- option means comparing the bonus IDs he copied onto it.
function ns.BonusIDsFromKey(key)
    local out = {}
    if type(key) ~= "string" then
        return out
    end
    local seenID = false
    for part in key:gmatch("[^:]+") do
        if not seenID then
            seenID = true
        else
            local bonus = tonumber(part)
            if not bonus then
                return {}
            end
            out[#out + 1] = bonus
        end
    end
    return out
end

-- The bracketed name inside an item link, or nil when the link carries none.
-- An empty pair of brackets - what `C_WeeklyRewards.GetItemHyperlink` answers
-- before the client has loaded the item - is "not known yet", so it reads as
-- nil here too rather than as an empty name.
--
-- It lives here, beside the parser, because two callers need it and one name
-- reader is one answer: `ns.Vault.LinkName` is this function, and `ns.Roads`
-- falls back to it for a road whose source record the client never named
-- (R-3b, WKE-576).
function ns.LinkName(link)
    if type(link) ~= "string" then
        return nil
    end
    local name = link:match("|h%[(.-)%]|h")
    if name == nil or name == "" then
        return nil
    end
    return name
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
--
-- A capture registered with `{ refuse = function(data) ... end }` gets to look
-- at what it has just read and say, in one sentence, that it is not worth
-- storing (R-7b, WKE-591). `refuse` returns a reason string to refuse, or nil
-- to store. The refusal becomes the capture's result - `{ ok = false, reason =
-- ... }`, the same shape combat and an unknown name already return - and
-- NOTHING is written to `db.global.captures`. That is the whole point: the
-- four-deep history is the only thing the companion reads, so an empty read
-- that stored would push the newest good one a place towards the edge, and the
-- flush after it off the end. A capture with no `refuse` stores whatever it
-- read, exactly as before.
ns.CAPTURE_TIMEOUT_SECONDS = 180

function ns.RegisterCapture(name, help, run, opts)
    assert(type(name) == "string" and name ~= "", "capture name required")
    assert(type(run) == "function", "capture '" .. tostring(name) .. "' needs a function")
    if not ns.captures[name] then
        ns.captureOrder[#ns.captureOrder + 1] = name
    end
    ns.captures[name] = {
        help = help or "",
        run = run,
        async = (opts and opts.async) or false,
        refuse = (opts and opts.refuse) or nil,
    }
end

-- How the capture that is running was asked for: "refresh" while
-- `ns.Companion.Refresh` is driving the chain, "flush" for the sequence that
-- runs when the UI is unloaded, and nil - which stores as "command" - for a
-- `/lootpath capture` typed by hand. R-6 (WKE-578): the companion reads it off
-- the newest `env` snapshot to say, in its own log, whether the write it woke on
-- carried a fresh capture or is flushing the last one again.
ns.captureTrigger = nil

-- How many snapshots of one capture name are kept. R-7a (WKE-582): nothing
-- trimmed this list, so every capture ever taken stayed in SavedVariables. The
-- owner's file measured 6.1 MB on 2026-09-14 and 11.0 MB two days later, with 35
-- `inventory` snapshots in it worth 5.85 MB on their own, and the client reads
-- and writes the whole file at every login and every reload. Four is the
-- smallest number that keeps the refresh loop's two flushes with two older ones
-- beside them to compare against; the companion only ever reads the newest of
-- each name (`newestSnapshot`, `tools/companion/lib/simc-profile.js`), so the
-- rest are for a human reading a pull. A pull is the evidence for the issue it
-- was made for, and it is committed under `spec/fixtures/captures/`; the live
-- file is not an archive.
ns.CAPTURE_HISTORY = 4

local function storeSnapshot(name, data, startedAt)
    local copy, sawSecret = ns.CopyRaw(data)
    local snapshot = {
        name = name,
        trigger = ns.captureTrigger or "command",
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
    -- The newest is always the one just stored; the oldest go. `table.remove`
    -- off the front rather than a rebuilt table, so the list AceDB already holds
    -- stays the list it holds.
    while #list > ns.CAPTURE_HISTORY do
        table.remove(list, 1)
    end
    return { ok = true, snapshot = snapshot, count = #list }
end

-- The capture's own look at what it read, between reading and storing (R-7b,
-- WKE-591). Guarded the way `entry.run` is: a `refuse` that errors must not
-- turn a good read into a lost one, so it is pcalled and a throw stores.
local function refusalFor(entry, name, data)
    if type(entry.refuse) ~= "function" then
        return nil
    end
    local ok, reason = pcall(entry.refuse, data)
    if not ok or type(reason) ~= "string" or reason == "" then
        return nil
    end
    return string.format("capture '%s' read nothing worth storing: %s", name, reason)
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
        local refused = refusalFor(entry, name, data)
        if refused then
            return complete({ ok = false, reason = refused, refusedStore = true })
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
            local refused = refusalFor(entry, name, data)
            if refused then
                settled = complete({ ok = false, reason = refused, refusedStore = true })
            else
                settled = complete(storeSnapshot(name, data, startedAt))
            end
        end
    end
    local ok, err = pcall(entry.run, finish, args)
    if not ok then
        finish(nil, string.format("errored: %s", tostring(err)))
    end
    -- The abandonment timer is registered only when the capture has NOT already
    -- answered. It used to be registered first, unconditionally, and then never
    -- fire because `finish` is idempotent; the order matters since R-7
    -- (WKE-579), where the capture sequence at `PLAYER_LOGOUT` must leave no
    -- timer behind - the client stops running Lua after that event, so a timer
    -- registered there is a promise nothing can keep. An async capture that is
    -- genuinely still running is bounded exactly as it was.
    if not settled and C_Timer and C_Timer.After then
        C_Timer.After(ns.CAPTURE_TIMEOUT_SECONDS, function()
            finish(nil, string.format("gave up after %d seconds", ns.CAPTURE_TIMEOUT_SECONDS))
        end)
    end
    return settled or { ok = true, pending = true, name = name }
end

-- SavedVariables through AceDB. `char` holds the last QE import (M2-1),
-- `global` the journal cache (M3-1) and every capture, `profile` the settings.
-- `settings.contentType` is one of QE Live's OWN content type strings, read
-- from its source (`src/globalTypes.d.ts`: `contentTypes = "Raid" | "Dungeon"`).
-- It read "Mythic+" here until 2026-09-06 (M2-2), a string no export can carry;
-- "Dungeon" is QE Live's name for the Mythic+ side.
ns.DB_DEFAULTS = {
    -- `upgradeMap` is which slot sections the reader has shut and which run
    -- cards they have opened (M5-3). Per character, because which slot matters
    -- is a fact about the character rather than about the account.
    char = {
        qeImports = {},
        qeImportsByScenario = {},
        ufImports = {},
        upgradeMap = { collapsedSlots = {}, expandedRuns = {} },
    },
    -- `drift` is R-6's two remembered facts (WKE-578): `refreshStartedAt`, the
    -- stamp written just before the first reload so the wait line can count
    -- from it, and `runSeconds`, how long the last FINISHED companion run took,
    -- which is the only figure the wait line is allowed to quote. Global
    -- because the companion is one per machine, not one per character.
    global = { journalCache = {}, captures = {}, drift = {} },
    -- `vaultScenario` is the Vault tab's HIGHLIGHT only; Equip Now and the
    -- Upgrade Map read `asOffered` and nothing else, whatever this says. It
    -- defaults to `thisWeek` since M3-13 (WKE-548) because that is the question
    -- the vault poses - take one option, upgrade that one, spend the one
    -- Catalyst charge - and the tab falls back to `asOffered`, saying so, when
    -- no `thisWeek` answer has been stored yet.
    -- The chrome settings are M5-2's (WKE-551): the window's own scale, the
    -- compact row height M5-1's item line reads, and where on the minimap ring
    -- the launcher sits (degrees counter-clockwise from east; 200 puts it at
    -- the lower left, clear of Blizzard's own buttons).
    profile = {
        settings = {
            contentType = "Dungeon",
            vaultScenario = "thisWeek",
            scale = 1.0,
            compactRows = false,
            minimapAngle = 200,
            -- "Explain" (R-3, WKE-564, docs/ROADS-UX.md principle 11): one
            -- plain sentence under the first visible use of a system word in
            -- an expanded slot. Off by default, because the default is dense.
            explain = false,
        },
    },
}

local function onAddonLoaded()
    ns.db = LibStub("AceDB-3.0"):New("LootpathDB", ns.DB_DEFAULTS, true)
    for _, fn in ipairs(ns.onReady) do
        fn(ns)
    end
    ns.ready = true
end

-- R-7b (WKE-591). **The measurement, not a fix.** The flush's `inventory` read
-- is empty on a real logout and full on a `/reload`, and nothing available from
-- a desk says whether the equipment is already gone at `PLAYER_LOGOUT` or
-- merely late. Ketho's `SystemDocumentation.lua` declares both
-- `PLAYER_LEAVING_WORLD` and `PLAYER_LOGOUT` as `SynchronousEvent = true` and
-- says NOTHING about which fires first or what still answers at either, so the
-- order is not assumed here: it is measured, on the owner's own next logout.
--
-- This counts equipped links and stores nothing. It is the cheapest read that
-- can answer the question - `GetInventoryItemLink` for at most nineteen slots,
-- no item data, no containers - and `PLAYER_LEAVING_WORLD` fires on every
-- loading screen, so cheap is the requirement. The answer is left on `ns` and
-- carried into the flush's `env` snapshot by `ns.Companion.CaptureAtFlush`,
-- where a pull can be read against the `inventory` read of the same flush:
-- equipped links one event earlier and none at the flush is "late", none at
-- either is "already gone".
--
-- The whole flush sequence is deliberately NOT moved here. `PLAYER_LEAVING_WORLD`
-- is not a logout - it is every zone change and every loading screen - and the
-- sequence costs 17-49 ms measured (R-7a, and the owner's 2026-09-16 file), which
-- is not a thing to spend on each of them on a guess about ordering.
ns.leavingWorld = nil

function ns.ProbeEquippedAtLeavingWorld()
    -- Nothing runs in combat, including this (CLAUDE.md, client rules).
    if InCombatLockdown and InCombatLockdown() then
        return nil
    end
    local startedAt = debugprofilestop and debugprofilestop() or nil
    local seen = 0
    local first = INVSLOT_FIRST_EQUIPPED or 1
    local last = INVSLOT_LAST_EQUIPPED or 19
    for slot = first, last do
        if ns.Probe(GetInventoryItemLink, "player", slot)[1] then
            seen = seen + 1
        end
    end
    ns.leavingWorld = {
        equipped = seen,
        at = time(),
        atLocal = date("%Y-%m-%dT%H:%M:%S"),
        elapsedMs = startedAt and debugprofilestop and (debugprofilestop() - startedAt) or nil,
    }
    return ns.leavingWorld
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
-- R-7 (WKE-579). The last thing the addon does is take the same four snapshots
-- `/lootpath refresh` takes, so that the SavedVariables the client is about to
-- flush carry the gear the player is leaving in rather than the gear the last
-- refresh recorded. The sequence, what it skips and why, is
-- `ns.Companion.CaptureAtFlush`; this file owns only the lifecycle half.
--
-- **R-7a (WKE-582): this is not a logout event, it is an unload event.**
-- `PLAYER_LOGOUT` fires on `/reload` as well, because the UI is unloaded either
-- way, and at the moment it fires nothing can tell the two apart - only the next
-- load can (`PLAYER_ENTERING_WORLD` carries `isInitialLogin, isReloadingUi`;
-- Ketho's `SystemDocumentation.lua`), and by then the snapshot is written. So
-- the sequence keeps running on both - it is the reason the second reload of the
-- refresh loop carries fresh gear - and everything it stores is labelled
-- `flush`, which is true of both. The owner's 2026-09-15 pull had five `env`
-- snapshots stamped `logout` for at most one logout; that is the label this
-- replaces.
--
-- `PLAYER_LOGOUT` is Blizzard's own synchronous event (Ketho's
-- `SystemDocumentation.lua`: `LiteralName = "PLAYER_LOGOUT", SynchronousEvent =
-- true`), and nothing after it is allowed to be asynchronous.
frame:RegisterEvent("PLAYER_LOGOUT")
-- M3-16a (WKE-581). The vault question M3-16 asked from inside the refresh is
-- asked here instead, once per session, so the refresh never has to wait for it
-- and its `ReloadUI` stays the player's own action. What is asked, what is not,
-- and why, is `ns.Companion.AskVaultAtLogin`; this file owns only the
-- lifecycle half.
--
-- `PLAYER_ENTERING_WORLD` rather than `PLAYER_LOGIN` because it fires again
-- after every loading screen and after a `/reload`, which is when the client
-- has its world data; the handler unregisters it after the first one, which is
-- what "once per session" means. `PLAYER_REGEN_ENABLED` is registered only when
-- that first one landed in combat, where nothing runs.
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        onAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        ns.Log("v%s loaded. /lootpath opens the frame; /lootpath help lists commands.", ns.VERSION)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Guarded the way the logout is: the question is a convenience, and a
        -- client that errors on it must not be the first thing a login shows.
        -- `AskVaultAtLogin` answers nil for exactly one reason - it was in
        -- combat and deferred - so that is the only thing that keeps the
        -- regen listener alive. A question that errored is not retried: it
        -- would error again, and the refresh's popup already covers the case.
        local deferred = false
        if ns.Companion and ns.Companion.AskVaultAtLogin then
            local ok, result = pcall(ns.Companion.AskVaultAtLogin)
            deferred = ok and result == nil
        end
        if deferred then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    elseif event == "PLAYER_LEAVING_WORLD" then
        -- Guarded for the same reason the logout is, and for one more: this
        -- fires on every loading screen, so an error here would be an error on
        -- every one of them.
        pcall(ns.ProbeEquippedAtLeavingWorld)
    elseif event == "PLAYER_LOGOUT" then
        -- Guarded rather than assumed: the unload is the one moment where an
        -- error in the addon would be the last thing the player sees.
        if ns.Companion and ns.Companion.CaptureAtFlush then
            pcall(ns.Companion.CaptureAtFlush)
        end
    end
end)

local HELP = {
    "/lootpath - open the frame: paste your Top Gear JSON, then Equip Now",
    "/lootpath options - the settings page (which content type's rating to show)",
    "/lootpath refresh - capture gear, bags and vault, then reload for the companion (and read what it wrote)",
    "/lootpath capture <name> - record raw client returns; then /reload and run tools\\sync.ps1 -Pull",
    "/lootpath capture - list the capture commands",
    "/lootpath capture wipe - clear every stored capture",
    '/lootpath map - open the window on the Upgrade Map (what the tooltip\'s "Why this?" points at)',
    "/lootpath status - what is stored",
    "/lootpath glow - why the bag mark is or is not on a slot; it samples a piece of gear from your "
        .. "bags, or shift-click an item in to ask about that one",
    "/lootpath help - this list",
}

-- R-2a (WKE-571). The bag mark can fail in three places and none of them showed
-- on the owner's screen. This prints all three at once, plus the answer for one
-- item, which is what the next diagnosis reads instead of a screenshot. The
-- link is the player's own shift-click; with none given a bag slot is sampled
-- instead, so the bare command still answers.
--
-- V-2 (WKE-573): the sample is GEAR. It used to be the first slot holding
-- anything, and on the owner's first run (2026-09-14 night) that was bag 0 slot
-- 1 - the Hearthstone - so the command answered `item: key 6948 - NOT in the
-- map - glow no` about an item no plan could ever mark, and diagnosed nothing.
-- What decides is the same static-data slot every other surface uses,
-- ns.ItemData.Instant(link).slot: QE Live's own slot vocabulary, nil for
-- anything that is not equippable gear. No new client call is introduced for
-- this; C_Item.GetItemInfoInstant is already in ItemData's declared list.
local function firstBagGear()
    if not (C_Container and type(C_Container.GetContainerItemLink) == "function") then
        return nil
    end
    for bag = 0, 4 do
        local slots = ns.Safe(C_Container.GetContainerNumSlots(bag))
        for slotIndex = 1, (type(slots) == "number" and slots or 0) do
            local link = ns.Safe(C_Container.GetContainerItemLink(bag, slotIndex))
            if type(link) == "string" and link ~= "" then
                local instant = ns.ItemData and ns.ItemData.Instant(link) or nil
                if instant and instant.slot then
                    return link
                end
            end
        end
    end
    return nil
end

-- What the sampled item is called, so the reader can tell a helmet he is
-- wearing the map's answer about from one he has never seen. The client's own
-- name first; the link carries it too, and a link the client cannot name yet
-- is still a link with a name in it.
local function sampledName(link)
    local cached = ns.ItemData and ns.ItemData.Cached(link) or nil
    if cached and cached.name then
        return cached.name
    end
    return link:match("|h%[(.-)%]|h") or "an item"
end

-- Owned here rather than by ns.UI.Bags (V-1, WKE-569): these two sentences are
-- about what this COMMAND did before it asked the map anything, and the walk
-- that produces them is this file's client read.
ns.GLOW_SAMPLED = "item: no link given; sampled %s from your bags"
ns.GLOW_NO_GEAR = "item: no equippable gear in your bags to sample"

local function glowCommand(rest)
    local link = rest ~= "" and rest or nil
    if not link then
        link = firstBagGear()
        if link then
            ns.Log(ns.GLOW_SAMPLED, sampledName(link))
        else
            ns.Log("%s", ns.GLOW_NO_GEAR)
        end
    end
    for _, line in ipairs(ns.UI.Bags.DiagnosisLines(link)) do
        ns.Log("%s", line)
    end
end

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
    -- H-1 (WKE-596): the gate first, in the same words the window's screen and
    -- the load line use (`ns.Companion.GateLine` owns them), because a player
    -- who types this in a non-healer spec is owed the reason the surfaces
    -- around him have gone quiet before he reads what is stored. Everything
    -- below still prints: what is captured and what is rated are facts either
    -- way, and this command is where a player goes to read them.
    local gateLine = ns.Companion and ns.Companion.GateLine and ns.Companion.GateLine() or nil
    if gateLine then
        ns.Log("%s", gateLine)
    end
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
        "import: %s%s",
        (import and import.exportedAt) and ("exported " .. tostring(import.exportedAt)) or "none",
        import and (" (" .. ns.Companion.SourceText(import) .. ")") or ""
    )
end

function ns.HandleSlash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""
    rest = rest or ""
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "options" or cmd == "config" then
        ns.UI.OpenOptions()
    elseif cmd == "refresh" then
        ns.Companion.Refresh()
    elseif cmd == "capture" then
        captureCommand(rest)
    elseif cmd == "status" then
        statusCommand()
    elseif cmd == "map" then
        ns.UI.ShowUpgradeMap()
    elseif cmd == "glow" then
        glowCommand(rest)
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
