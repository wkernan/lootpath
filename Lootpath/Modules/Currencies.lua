-- Lootpath/Modules/Currencies.lua (M3-9, WKE-544; by-ID reading M3-11, WKE-546)
-- What the player has, in the client's own words and the client's own numbers.
--
-- This module exists for exactly two lines on the Vault tab: QE Live's
-- `catalyzed` scenario assumed a Catalyst charge, and his `maxed` scenario
-- assumed upgrades bought with crests, so the tab says how many of each the
-- player actually has beside those answers. It reads a count and hands it on.
--
-- **No arithmetic, ever.** Never "enough for 3 upgrades", never a cost, never a
-- total. The upgrade cost of a given item is not readable from the client
-- outside the upgrade UI, and the standing rule against estimating a healer
-- value applies to a crest price for the same reason: a number Lootpath made up
-- is a number the owner cannot check.
--
-- **Which currencies these are is not guessed - and is not read off the currency
-- tab either.** `GetCurrencyListInfo` walks the currency TAB, and the tab lists
-- only the rows of EXPANDED headers: the owner's 2026-09-08 23:04 transcript has
-- `isHeaderExpanded = false` on 8 of its 10 headers, so the 8 currencies it
-- listed are simply the ones under the two that happened to be open. Reading
-- "the Catalyst charge is not a currency" off that list was reading the tab's
-- scroll state (M3-9, corrected here in M3-11). `GetCurrencyInfo(currencyID)`
-- answers for any ID whatever the tab is showing, so KNOWN_IDS below is the
-- primary key and the list is the fallback. Every ID in it was MEASURED - from
-- the transcript, or from the owner's own tooltip - and none is remembered from
-- a wiki page.
--
-- Every value read from the client passes ns.Safe; a secret is dropped and
-- counted, never stored or shown. Nothing runs in combat except reading a
-- capture that was already taken.

local _, ns = ...

ns.Currencies = {}
local Currencies = ns.Currencies

-- Every client function this file calls, named rather than discovered, for the
-- same reason Vault.FUNCTION_NAMES is a list of strings. C_CurrencyInfo also
-- carries RequestCurrencyDataForAccountCharacters and the currency-transfer
-- calls, which is why nothing here iterates the namespace.
Currencies.FUNCTION_NAMES = {
    "C_CurrencyInfo.GetCurrencyListSize",
    "C_CurrencyInfo.GetCurrencyListInfo",
    "C_CurrencyInfo.GetCurrencyInfo",
}

-- The capture this module falls back to when it cannot read the client itself.
Currencies.CAPTURE = "currencies"

-- The season's currencies BY ID, which is what the client answers for whatever
-- the currency tab happens to be showing. Every one of these was read from a
-- tool, never from memory:
--
--   crests   3442-3446, the five Mistcrests under the "Crests" header of the
--            owner's 2026-09-08 23:04:26 transcript
--            (`spec/fixtures/captures/Lootpath-20260908-230426.lua`), in the
--            order the client listed them.
--   catalyst 3465, "Venomblight Manaflux", from the owner's own Catalyst
--            tooltip on 2026-09-08 ("Total Maximum: 1/8, CurrencyID 3465"),
--            confirmed by the next capture's `byID` probe.
--
-- Nothing here is expanded, collapsed or otherwise touched to make it readable:
-- `ExpandCurrencyList` changes UI state and is never called.
Currencies.KNOWN_IDS = {
    crests = { 3442, 3443, 3444, 3445, 3446 },
    catalyst = { 3465 },
}

-- The names those IDs carried in the transcript, kept as the by-name fallback
-- for a client whose `GetCurrencyInfo` answers nothing for an ID, and as the
-- order the crests are shown in. The ID wins whenever it resolves, and the name
-- shown is then the client's own `CurrencyInfo.name`.
Currencies.CREST_NAMES = {
    "Adventurer Mistcrest", -- 3442
    "Veteran Mistcrest", -- 3443
    "Champion Mistcrest", -- 3444
    "Hero Mistcrest", -- 3445
    "Myth Mistcrest", -- 3446
}

Currencies.CATALYST_NAMES = {
    "Venomblight Manaflux", -- 3465
}

-- Every known ID, crests then the Catalyst, as the capture probes them.
function Currencies.AllKnownIDs()
    local out = {}
    for _, group in ipairs({ Currencies.KNOWN_IDS.crests, Currencies.KNOWN_IDS.catalyst }) do
        for _, id in ipairs(group or {}) do
            out[#out + 1] = id
        end
    end
    return out
end

-- Secret-guarded read, the shape Vault.lua uses: a secret is dropped and counted.
local function guarded(counter, value)
    local safe, secret = ns.Safe(value)
    if secret then
        counter.secretsSeen = counter.secretsSeen + 1
        return nil
    end
    return safe
end

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end
    return result
end

-- One CurrencyInfo -> one record, guarded. Headers are kept: they are how the
-- client groups the list, and a reader of the transcript needs the grouping to
-- tell an upgrade crest from a holiday token.
local function record(counter, raw, index)
    local safe = guarded(counter, raw)
    if type(safe) ~= "table" then
        return nil
    end
    local name = guarded(counter, safe.name)
    return {
        index = index,
        isHeader = guarded(counter, safe.isHeader) == true,
        -- Kept because it is the field that proved the tab hides what it has
        -- not expanded, and a reader of a future transcript needs it too.
        isHeaderExpanded = guarded(counter, safe.isHeaderExpanded) == true,
        name = type(name) == "string" and name ~= "" and name or nil,
        currencyID = tonumber(guarded(counter, safe.currencyID)),
        quantity = tonumber(guarded(counter, safe.quantity)),
        maxQuantity = tonumber(guarded(counter, safe.maxQuantity)),
    }
end

-- The live answer for every known ID, whatever the currency tab is showing.
-- `GetCurrencyInfo(currencyID)` is documented to answer for any ID (Ketho's
-- CurrencyInfoDocumentation.lua) and is the reason this module no longer
-- depends on which headers the player left expanded.
local function liveByID(counter)
    local C = C_CurrencyInfo
    if not (C and C.GetCurrencyInfo) then
        return {}
    end
    local out = {}
    for _, id in ipairs(Currencies.AllKnownIDs()) do
        local full = record(counter, call(C.GetCurrencyInfo, id), nil)
        if full then
            full.currencyID = full.currencyID or id
            out[full.currencyID] = full
        end
    end
    return out
end

-- The live list, or nil when this client has no currency API to ask.
local function liveEntries(counter)
    local C = C_CurrencyInfo
    if not (C and C.GetCurrencyListSize and C.GetCurrencyListInfo) then
        return nil
    end
    local size = tonumber(guarded(counter, call(C.GetCurrencyListSize)))
    if not size then
        return nil
    end
    local out = {}
    for index = 1, size do
        local entry = record(counter, call(C.GetCurrencyListInfo, index), index)
        if entry then
            out[#out + 1] = entry
        end
    end
    return out
end

-- The same list out of a stored `currencies` snapshot, plus everything the
-- snapshot knows by ID. `data.list[i]` is an ns.Probe pack, so the CurrencyInfo
-- is its first positional result; `data.info` carries the full GetCurrencyInfo
-- for every non-header entry the list showed, and `data.byID[id]` (M3-11) the
-- same call made for every ID in KNOWN_IDS whether the tab showed it or not.
--
-- Returns `entries, byID`. `byID` is the ID-keyed answer the reader should
-- prefer; a snapshot taken before M3-11 has no `data.byID`, so it carries only
-- what the list itself named, which is exactly what such a transcript knows.
function Currencies.FromSnapshot(snapshot, counter)
    counter = counter or { secretsSeen = 0 }
    local data = type(snapshot) == "table" and snapshot.data or nil
    if type(data) ~= "table" or type(data.list) ~= "table" then
        return nil
    end
    local byID = {}
    for _, extra in ipairs(data.info or {}) do
        local probe = type(extra) == "table" and extra.info or nil
        local full = type(probe) == "table" and record(counter, probe[1], nil) or nil
        if full and full.currencyID then
            byID[full.currencyID] = full
        end
    end
    -- The direct probe outranks the list's info half: it is the one that
    -- answers for a currency under a collapsed header.
    for id, probe in pairs(type(data.byID) == "table" and data.byID or {}) do
        local key = tonumber(id)
        local full = type(probe) == "table" and record(counter, probe[1], nil) or nil
        if full and key then
            full.currencyID = full.currencyID or key
            byID[full.currencyID] = full
        end
    end
    local out = {}
    for index = 1, #data.list do
        local probe = data.list[index]
        local entry = type(probe) == "table" and record(counter, probe[1], index) or nil
        if entry then
            local full = entry.currencyID and byID[entry.currencyID] or nil
            if full then
                entry.name = entry.name or full.name
                entry.quantity = entry.quantity or full.quantity
            end
            out[#out + 1] = entry
        end
    end
    return out, byID
end

-- The newest stored `currencies` snapshot, or nil when none has been taken.
function Currencies.NewestSnapshot()
    local db = ns.db
    local captures = db and db.global and db.global.captures or nil
    local list = type(captures) == "table" and captures[Currencies.CAPTURE] or nil
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    return list[#list]
end

-- Read(opts) -> { ok = true, source = "live"|"capture", entries, byID, crests,
--                 crestsKnown, catalystKnown, catalystCharges, catalystMax,
--                 secretsSeen }
--            or { ok = false, reason }
--
-- **By ID first.** Each of KNOWN_IDS.crests and KNOWN_IDS.catalyst is looked up
-- in the ID-keyed answers (the direct `GetCurrencyInfo` probe, then the info
-- half of the list); only when no ID answers does the client's list get asked
-- by name, through CREST_NAMES / CATALYST_NAMES. The name shown is always the
-- client's own `CurrencyInfo.name`. That order is the whole point of M3-11: the
-- currency tab lists only expanded headers, so a by-name read of it reports
-- absent for a currency the player is holding.
--
-- `crests` is one record per configured crest that the player actually carries,
-- in KNOWN_IDS order; `crestsKnown` / `catalystKnown` say whether an ID (or a
-- name) is configured at all, which is the difference between "you have none"
-- and "nobody has told this addon what a crest is". `catalystCharges` and
-- `catalystMax` are the client's `quantity` and `maxQuantity`, numbers or nil,
-- and nil is never shown as 0.
--
-- The live client wins when it can be asked, because the capture may be days
-- old; in combat, or on a client with no currency API, the newest stored
-- snapshot answers instead and says so through `source`.
function Currencies.Read(opts)
    opts = opts or {}
    local counter = { secretsSeen = 0 }
    local entries, byID, source
    if opts.snapshot ~= nil then
        entries, byID = Currencies.FromSnapshot(opts.snapshot, counter)
        source = "capture"
    elseif not InCombatLockdown() then
        entries = liveEntries(counter)
        if entries then
            byID, source = liveByID(counter), "live"
        end
    end
    if not entries then
        local snapshot = Currencies.NewestSnapshot()
        if snapshot then
            entries, byID = Currencies.FromSnapshot(snapshot, counter)
            source = "capture"
        end
    end
    if not entries then
        return {
            ok = false,
            reason = InCombatLockdown() and "combat" or "no currency list has been read yet",
            secretsSeen = counter.secretsSeen,
        }
    end
    byID = byID or {}

    local byName, listByID = {}, {}
    for _, entry in ipairs(entries) do
        if not entry.isHeader then
            if entry.name and byName[entry.name] == nil then
                byName[entry.name] = entry
            end
            if entry.currencyID and listByID[entry.currencyID] == nil then
                listByID[entry.currencyID] = entry
            end
        end
    end

    -- One currency, by ID first and by name only when no ID answered.
    local function resolve(id, name)
        local found = (id and (byID[id] or listByID[id])) or (name and byName[name]) or nil
        if found and found.quantity then
            return found
        end
        return nil
    end

    local crestIDs, crestNames = Currencies.KNOWN_IDS.crests or {}, Currencies.CREST_NAMES
    local crests = {}
    for index = 1, math.max(#crestIDs, #crestNames) do
        local found = resolve(crestIDs[index], crestNames[index])
        if found then
            crests[#crests + 1] = {
                name = found.name or crestNames[index],
                currencyID = found.currencyID,
                quantity = found.quantity,
            }
        end
    end

    local catalystIDs = Currencies.KNOWN_IDS.catalyst or {}
    local catalyst
    for index = 1, math.max(#catalystIDs, #Currencies.CATALYST_NAMES) do
        catalyst = resolve(catalystIDs[index], Currencies.CATALYST_NAMES[index])
        if catalyst then
            break
        end
    end

    return {
        ok = true,
        source = source,
        entries = entries,
        byID = byID,
        crests = crests,
        crestsKnown = #crestIDs > 0 or #crestNames > 0,
        catalystKnown = #catalystIDs > 0 or #Currencies.CATALYST_NAMES > 0,
        catalystCharges = catalyst and catalyst.quantity or nil,
        catalystMax = catalyst and catalyst.maxQuantity or nil,
        secretsSeen = counter.secretsSeen,
    }
end
