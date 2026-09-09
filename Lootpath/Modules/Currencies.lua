-- Lootpath/Modules/Currencies.lua (M3-9, WKE-544)
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
-- **Which currencies these are is not guessed.** The season's crests and the
-- Catalyst charge are identified by the CLIENT'S OWN NAMES, and the name tables
-- below are empty until `/lootpath capture currencies` has been run once and its
-- transcript committed (the capture is in Captures.lua; the names and their IDs
-- are then recorded in docs/ARCHITECTURE.md 9). Until then every reader is told
-- "unknown", which is true, rather than a number read off an ID somebody
-- remembered from a wiki page.
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

-- The season's upgrade crests, by the name the client prints for them, in the
-- order they should be shown. **Empty until the transcript lands** - the owner
-- runs `/lootpath capture currencies` once, the transcript names them, and they
-- are written here with their IDs recorded in docs/ARCHITECTURE.md 9. An empty
-- table is not a bug and is not a gap to fill with a guess: it is this module
-- reporting `crestsKnown = false`, and the Vault tab saying so in words.
Currencies.CREST_NAMES = {}

-- The Catalyst charge, the same way, as a list because the client may not call
-- it what the community does - or may not carry it as a currency at all. When
-- the transcript shows it is not a currency this list stays empty and the tab
-- says "Catalyst charges: not readable" rather than inventing a count.
Currencies.CATALYST_NAMES = {}

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
        name = type(name) == "string" and name ~= "" and name or nil,
        currencyID = tonumber(guarded(counter, safe.currencyID)),
        quantity = tonumber(guarded(counter, safe.quantity)),
    }
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

-- The same list out of a stored `currencies` snapshot. `data.list[i]` is an
-- ns.Probe pack, so the CurrencyInfo is its first positional result; `data.info`
-- carries the full GetCurrencyInfo for every non-header entry, and supplies the
-- quantity for anything the list itself did not name.
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
    return out
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

-- Read(opts) -> { ok = true, source = "live"|"capture", entries, crests,
--                 crestsKnown, catalystKnown, catalystCharges, secretsSeen }
--            or { ok = false, reason }
--
-- `crests` is one record per name in CREST_NAMES that the player actually
-- carries, in that order; `crestsKnown` says whether the name list has been
-- filled in from a transcript at all, which is the difference between "you have
-- none" and "nobody has told this addon what a crest is called".
-- `catalystCharges` is a number or nil, and nil is never shown as 0.
--
-- The live client wins when it can be asked, because the capture may be days
-- old; in combat, or on a client with no currency API, the newest stored
-- snapshot answers instead and says so through `source`.
function Currencies.Read(opts)
    opts = opts or {}
    local counter = { secretsSeen = 0 }
    local entries, source
    if opts.snapshot ~= nil then
        entries, source = Currencies.FromSnapshot(opts.snapshot, counter), "capture"
    elseif not InCombatLockdown() then
        entries = liveEntries(counter)
        source = entries and "live" or nil
    end
    if not entries then
        local snapshot = Currencies.NewestSnapshot()
        if snapshot then
            entries, source = Currencies.FromSnapshot(snapshot, counter), "capture"
        end
    end
    if not entries then
        return {
            ok = false,
            reason = InCombatLockdown() and "combat" or "no currency list has been read yet",
            secretsSeen = counter.secretsSeen,
        }
    end

    local byName = {}
    for _, entry in ipairs(entries) do
        if not entry.isHeader and entry.name and byName[entry.name] == nil then
            byName[entry.name] = entry
        end
    end

    local crests = {}
    for _, name in ipairs(Currencies.CREST_NAMES) do
        local entry = byName[name]
        if entry and entry.quantity then
            crests[#crests + 1] = { name = name, currencyID = entry.currencyID, quantity = entry.quantity }
        end
    end

    local catalystCharges
    for _, name in ipairs(Currencies.CATALYST_NAMES) do
        local entry = byName[name]
        if entry and entry.quantity then
            catalystCharges = entry.quantity
            break
        end
    end

    return {
        ok = true,
        source = source,
        entries = entries,
        crests = crests,
        crestsKnown = #Currencies.CREST_NAMES > 0,
        catalystKnown = #Currencies.CATALYST_NAMES > 0,
        catalystCharges = catalystCharges,
        secretsSeen = counter.secretsSeen,
    }
end
