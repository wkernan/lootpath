-- Lootpath/Modules/EngineSearch.lua (E-1a, WKE-685)
-- The best set of what the character owns, by our own set value: per-position
-- candidate pools with outclassed pieces dropped, every feasible tier mask,
-- and inside each mask a coordinate ascent whose every move is a full
-- ns.EngineScore.SetValue. DEVELOPER-ONLY and scoped by CLAUDE.md's scoped
-- exception and docs/ARCHITECTURE.md section 7 (2026-09-30, E-0; 2026-10-02,
-- E-1a): behind `db.global.developer.engine`, out of combat, printed by
-- `/lootpath engine best` to the chat frame of the developer who typed it and
-- to no surface; no UI file reads this module (spec/enginesearch_spec.lua reads
-- every UI file to hold that). It writes nothing to the database - not
-- `qeImports`, not `ufImports`, not `engineCompare`.
--
-- The search itself reads no client API. Item vectors come from
-- ns.EngineStats (every read through ns.Safe there); the set value is
-- ns.EngineScore.SetValue, unchanged, whose one client call is the rating
-- conversion it is handed. The only client calls in this file are the switch's
-- combat check, the frame the coroutine runs on, and the frame clock.
--
-- How the search works (docs/OWN-ENGINE.md section 5, "The search"):
--   1. Candidates: the owned items by position - the ten single slots, the
--      ring pool, the trinket pool, and the weapon pools (one-hand, off-hand,
--      two-hand). A piece is DROPPED when other pieces outclass it: as good or
--      better in every stat the band weights (in the band's direction), with
--      its sockets and the assumed finish folded in, the same tier set, and no
--      effect entry on the dropped piece. A single slot needs one such piece;
--      a ring or trinket needs two that can be worn together (a unique item
--      counts once per itemID). Why this never drops the optimum is written
--      above `Candidates`.
--   2. Masks: for each tier slot, the tier sets the weights file carries that
--      a candidate there belongs to, plus "none" when a candidate belongs to
--      none; every combination is a mask (2^5 at most with one set).
--   3. Ascend: inside one mask, start from the best piece per position by a
--      cheap one-item proxy, then sweep the coordinates - the ten single
--      slots, the ring PAIR, the trinket PAIR and the weapon choice (one-hand
--      plus off-hand against two-hand) - taking for each the option with the
--      highest full SetValue, until a sweep changes nothing. A set that breaks
--      a constraint hook is never valued. Then (E-1e, WKE-703) a COUPLED
--      sweep: for each pair of coordinates that must be able to change
--      together - two positions whose pieces share a limit category, and the
--      trinket pair with the weapon choice - every combination of their
--      options with the rest kept; when one is better it is taken and the
--      single sweeps run again. Why, and what it still does not reach, is
--      written above `couplesOf`.
--   4. Best: the best of every mask, plus each position's runner-up: the
--      value given up by the best OTHER piece there with the rest kept (E-1b,
--      WKE-688: compared by the pieces an option holds, never by the option
--      table). A position with no other piece reads `only piece`; a different
--      piece worth exactly as much reads `tie` and is named.
--
-- SetValue is called with the parity finish (`assumedFinish = true`, QE
-- Live's own rule) and WITHOUT `forceTier`: Top Gear counts the pieces a set
-- actually wears (fork TopGearEngine.ts:316-470 builds every wearable set and
-- scores each as worn); only its Upgrade Finder forces the bonus.
--
-- QE Live's Top Gear, for comparison (F, read in the fork, nothing copied):
-- `createSets` nests a loop per slot over every item (TopGearEngine.ts:316-470,
-- rings with the same ID refused but for a listed few :419-424, trinkets with
-- the same ID always :430, weapons as prebuilt combinations :410-412), scores
-- every set (:259-275) and keeps the best 3000 (`softSlice`, :29, :278-282).
-- That is tractable at a pass of 30 items; at the owner's own 55 it is about
-- 10^8 sets, so this search does not enumerate.

local _, ns = ...

ns.EngineSearch = {}
local EngineSearch = ns.EngineSearch

-- Every client function this file calls, named rather than discovered. The
-- scan is ns.Inventory's, the reads ns.EngineStats', the waits ns.ItemData's
-- (through ns.EngineCompare.Resolve); each names its own.
EngineSearch.FUNCTION_NAMES = {
    "InCombatLockdown",
    "CreateFrame",
    "debugprofilestop",
}

-- The coroutine yields once a frame's slice has run this long (ms).
EngineSearch.BUDGET_MS = 5
-- BruteForce refuses an inventory with more sets than this.
EngineSearch.BRUTE_FORCE_CAP = 100000
-- A sweep that keeps finding moves stops here (it never has; a guard). Every
-- single sweep and every coupled pass counts.
EngineSearch.MAX_SWEEPS = 64
-- A move is taken only when it beats the current value by more than this
-- share of it, so two equal sets never flip back and forth.
EngineSearch.EPSILON = 1e-12

EngineSearch.SINGLES = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet" }
EngineSearch.TIER_SLOTS = { "Head", "Shoulder", "Chest", "Hands", "Legs" }
EngineSearch.PAIRS = { "Finger", "Trinket" }
EngineSearch.ONE_HAND = "1H Weapon"
EngineSearch.OFF_HAND = "Offhand"
EngineSearch.TWO_HAND = "2H Weapon"
EngineSearch.WEAPON = "Weapon"

-- The pool an item's slot (Inventory.SLOT_BY_EQUIPLOC's vocabulary) joins.
local POOL_OF_SLOT = {
    Shield = "Offhand",
    Offhand = "Offhand",
}

-- The fields a constraint hook counts; a piece carrying one never outclasses
-- another, so a hook that starts counting it cannot be undone by the drop.
EngineSearch.HOOK_FLAGS = { "embellished", "vault", "catalyst" }

EngineSearch.TEXT = {
    notOn = "not on",
    combat = "Out of combat only.",
    running = "engine best is still working - one search at a time.",
    noSet = "engine best found no set: %s",
    header = "engine best - weights %s, patch %s, derived %s - %s, band %s",
    position = "  %s: %s · %s%s",
    runnerUp = " · next best %s%%",
    noRunnerUp = " · nothing else fits",
    -- E-1b (WKE-688): the position had no other piece at all, or its
    -- runner-up is a different piece worth exactly as much.
    onlyPiece = " · only piece",
    tie = " · next best tie: %s",
    bands = "bands the weights file carries for %s: %s. usage: /lootpath engine best dungeon <n> | raid",
    values = "best set %s, worn set %s (%s%%)",
    cost = "%d set values over %d tier mask(s); %s ms of work in %d frame(s), %s ms start to finish.",
    paused = "paused for combat %d time(s), picked up after.",
    leftOut = "left out: %d not ready, %d secret, %d not for this spec, %d outclassed by other pieces.",
    notRated = "  not rated: %d piece(s) in the best set carry an effect not modelled.",
    worn = "worn",
    bag = "bag",
    bank = "bank",
}

-- ---------------------------------------------------------------------------
-- The switch.

function EngineSearch.Enabled()
    return ns.EngineCompare ~= nil and ns.EngineCompare.Enabled() == true
end

-- Allowed() -> true | false, the one line that says why not.
function EngineSearch.Allowed()
    if not EngineSearch.Enabled() then
        return false, EngineSearch.TEXT.notOn
    end
    if InCombatLockdown() then
        return false, EngineSearch.TEXT.combat
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Constraint hooks. Each is `check(items) -> ok, why` over a whole set.

-- Unique-equipped: `uniqueness.isUnique` allows one copy of the itemID; a
-- limit category allows `max` pieces of the category (one when no max). Read
-- by ns.EngineStats from GetItemUniquenessByID.
function EngineSearch.UniqueOK(items)
    local byID, byCategory = {}, {}
    for _, item in ipairs(items) do
        local u = item.uniqueness
        if type(u) == "table" then
            if u.isUnique and item.itemID then
                byID[item.itemID] = (byID[item.itemID] or 0) + 1
                if byID[item.itemID] > 1 then
                    return false, "unique-equipped"
                end
            end
            if u.category then
                byCategory[u.category] = (byCategory[u.category] or 0) + 1
                if byCategory[u.category] > (tonumber(u.max) or 1) then
                    return false, "unique category"
                end
            end
        end
    end
    return true
end

-- Embellishments at most two: no committed transcript says which link field
-- marks an embellishment (ARCHITECTURE.md section 11), so nothing carries
-- `embellished` and this hook has nothing to count yet.
function EngineSearch.EmbellishmentsOK(_)
    return true
end

-- One Great Vault choice at most: vault options are not candidates yet (the
-- 2026-10-01 transcript read 0 vault links), so nothing carries `vault`.
function EngineSearch.VaultOK(_)
    return true
end

-- Catalyst conversions at most the charges held: the charge is not readable
-- as a currency (spec/fixtures/captures/README.md, 2026-09-08) and catalysed
-- clones are not candidates, so nothing carries `catalyst`.
function EngineSearch.CatalystOK(_)
    return true
end

EngineSearch.HOOKS = {
    { name = "unique", check = EngineSearch.UniqueOK },
    { name = "embellishments", check = EngineSearch.EmbellishmentsOK },
    { name = "vault", check = EngineSearch.VaultOK },
    { name = "catalyst", check = EngineSearch.CatalystOK },
}

-- The built-in hooks plus any a caller adds (`{ name, check }` or a bare
-- function).
local function hooksOf(extra)
    local list = {}
    for _, hook in ipairs(EngineSearch.HOOKS) do
        list[#list + 1] = hook
    end
    for i, hook in ipairs(extra or {}) do
        if type(hook) == "function" then
            list[#list + 1] = { name = "hook " .. i, check = hook }
        elseif type(hook) == "table" and type(hook.check) == "function" then
            list[#list + 1] = hook
        end
    end
    return list
end

local function feasible(hooks, items)
    for _, hook in ipairs(hooks) do
        local ok = hook.check(items)
        if not ok then
            return false
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Scoring context: the band, the options SetValue is called with, the cache
-- and the evaluation count.

local STATS = { "int", "haste", "crit", "mastery", "vers", "leech" }
local RATINGS = { "haste", "crit", "mastery", "vers", "leech" }

local function scoreOptsOf(weights, opts)
    return {
        file = weights,
        spec = opts.spec,
        contentType = opts.contentType,
        keyLevel = opts.keyLevel,
        band = opts.band,
        assumedFinish = opts.assumedFinish ~= false,
        forceTier = false,
        dr = opts.dr,
        rating = opts.rating,
        effects = opts.effects,
    }
end

local function bandOf(weights, opts)
    if type(weights) ~= "table" then
        return nil, ns.EngineScore.refusal or ns.EngineScore.TEXT.broken
    end
    if opts.band ~= nil then
        local specs = type(weights.specs) == "table" and weights.specs[opts.spec or ns.EngineScore.DEFAULT_SPEC]
        local content = type(specs) == "table" and specs[opts.contentType or ns.EngineScore.DEFAULT_CONTENT]
        local band = type(content) == "table" and type(content.bands) == "table" and content.bands[opts.band]
        if type(band) == "table" then
            return band, opts.band
        end
        return nil, ns.EngineScore.NO_BAND
    end
    return ns.EngineScore.BandFor(weights, opts.spec, opts.contentType, opts.keyLevel)
end

-- The percent one rating total converts to, the way SetValue converts it.
local function percentOf(weights, opts, stat, value)
    if type(value) ~= "number" or value <= 0 then
        return 0
    end
    if opts.dr == "table" then
        local dr = type(weights.dr) == "table" and weights.dr[stat]
        return ns.EngineScore.TablePercent(value, dr) or 0
    end
    local rate = opts.rating or (ns.EngineStats and ns.EngineStats.Rating)
    local index = ns.EngineStats and ns.EngineStats.RATING_INDEX or {}
    if type(rate) ~= "function" then
        return 0
    end
    local p = rate(index[stat], value)
    return type(p) == "number" and p or 0
end

local function newContext(weights, opts)
    opts = opts or {}
    weights = weights or ns.EngineScore.file
    local band, key = bandOf(weights, opts)
    if type(band) ~= "table" or type(band.weights) ~= "table" then
        return nil, key or ns.EngineScore.NO_BAND
    end
    return {
        weights = weights,
        opts = opts,
        band = band,
        bandKey = key,
        scoreOpts = scoreOptsOf(weights, opts),
        hooks = hooksOf(opts.constraints),
        cache = opts.cache ~= false and {} or nil,
        evaluations = 0,
        tick = opts.tick,
    }
end

-- ---------------------------------------------------------------------------
-- Candidates.

local function addInto(v, stats, times)
    if type(stats) ~= "table" then
        return
    end
    for _, stat in ipairs(STATS) do
        local x = stats[stat]
        if type(x) == "number" then
            v[stat] = v[stat] + x * times
        end
    end
end

-- What one item adds to a set's totals in SetValue's mode: its stats, plus
-- (parity) its sockets times the gem vector and its slot's enchant, or (own
-- finish) its gems' stats.
local function effective(item, band, assumedFinish)
    local v = {}
    for _, stat in ipairs(STATS) do
        v[stat] = 0
    end
    addInto(v, item, 1)
    if assumedFinish then
        local finish = band.assumedFinish
        if type(finish) == "table" then
            addInto(v, finish.gemVector, tonumber(item.sockets) or 0)
            local bySlot = finish.enchantBySlot
            addInto(v, type(bySlot) == "table" and bySlot[item.slot] or nil, 1)
        end
    elseif type(item.gems) == "table" then
        for _, gem in ipairs(item.gems) do
            addInto(v, gem.stats, 1)
        end
    end
    return v
end

-- The tier set a piece counts toward: its setID when the weights file carries
-- that set, else false. A setID the file does not carry moves no value.
local function tierKeyOf(item, weights)
    local id = item.setID
    if id ~= nil and type(weights.tiers) == "table" and type(weights.tiers[id]) == "table" then
        return id
    end
    return false
end

local function poolOf(slot)
    return POOL_OF_SLOT[slot] or slot
end

local function hookFlagged(item)
    for _, flag in ipairs(EngineSearch.HOOK_FLAGS) do
        if item[flag] then
            return true
        end
    end
    return false
end

-- `a` outclasses `b`: same tier set; as good or better in every weighted stat
-- (worse where a weight is negative); strictly better somewhere, or equal
-- everywhere and earlier in the fixed order. `a` must carry no limit category
-- and no hook flag; `b` must carry no effect entry.
local function outclasses(a, b, signs)
    if a.tier ~= b.tier then
        return false
    end
    local strictly = false
    for _, stat in ipairs(STATS) do
        local s = signs[stat]
        if s ~= 0 then
            local da, db = a.eff[stat] * s, b.eff[stat] * s
            if da < db then
                return false
            elseif da > db then
                strictly = true
            end
        end
    end
    return strictly or a.order < b.order
end

local function canOutclass(c)
    local u = c.item.uniqueness
    if type(u) == "table" and u.category then
        return false
    end
    return not hookFlagged(c.item)
end

local function canBeDropped(c, effects)
    return ns.EngineScore.EffectOf(c.item, effects) == nil
end

-- How many pieces in `list` count toward "can be worn together": a unique
-- piece counts once per itemID.
local function wearableCount(list)
    local n, seen = 0, {}
    for _, c in ipairs(list) do
        local u = c.item.uniqueness
        if type(u) == "table" and u.isUnique then
            if not seen[c.item.itemID] then
                seen[c.item.itemID] = true
                n = n + 1
            end
        else
            n = n + 1
        end
    end
    return n
end

-- Candidates(items, weights, opts) -> `{ pools = { [position] = { cand } },
-- dropped = { cand }, kept }` | nil, reason.
--
-- A cand is `{ item, order, eff, tier, proxy }`; `item` is the caller's
-- vector, untouched. `opts.prune == false` keeps every piece.
--
-- Why a drop never loses the optimum. SetValue is non-decreasing in every
-- total whose weight is positive (and non-increasing where it is negative):
-- the value is baseValue + w_int * int + sum_r w_r * pct_r(total_r), each
-- pct_r is non-decreasing in its total (the client's conversion and the
-- bracket table both only slow down, never turn back), and the tier
-- multiplier depends only on how many pieces of each set are worn. Pieces are
-- visited best first in an order that extends "outclasses" (the signed stat
-- sum, then the input order), so every piece that outclasses `b` is decided
-- before `b`. `b` is dropped only when enough KEPT pieces outclass it: one in
-- a single slot, two in a pair that count as two under unique-equipped. Take
-- an optimal set holding the most kept pieces; if it held a dropped `b`, one of
-- `b`'s kept outclassers is not `b`'s partner and not a unique copy of it, can
-- take `b`'s place without breaking a hook (it carries no limit category and
-- no hook flag, and the same tier set keeps every count), and the value does
-- not fall - a set with more kept pieces, at least as good: a contradiction.
-- `b` carries no effect entry, so no effect value is lost with it.
-- spec/enginesearch_spec.lua checks the claim against brute force.
function EngineSearch.Candidates(items, weights, opts)
    opts = opts or {}
    weights = weights or ns.EngineScore.file
    local band, why = bandOf(weights, opts)
    if type(band) ~= "table" or type(band.weights) ~= "table" then
        return nil, why or ns.EngineScore.NO_BAND
    end
    local w = band.weights
    local signs = {}
    for _, stat in ipairs(STATS) do
        local x = tonumber(w[stat]) or 0
        signs[stat] = (x > 0 and 1) or (x < 0 and -1) or 0
    end
    local assumedFinish = opts.assumedFinish ~= false
    local byPool = {}
    for i, item in ipairs(items or {}) do
        if type(item) == "table" and type(item.slot) == "string" then
            local eff = effective(item, band, assumedFinish)
            local proxy = (tonumber(w.int) or 0) * eff.int
            for _, stat in ipairs(RATINGS) do
                proxy = proxy + (tonumber(w[stat]) or 0) * percentOf(weights, opts, stat, eff[stat])
            end
            local signed = 0
            for _, stat in ipairs(STATS) do
                signed = signed + signs[stat] * eff[stat]
            end
            local cand = { item = item, order = i, eff = eff, tier = tierKeyOf(item, weights), proxy = proxy }
            cand.signed = signed
            local pool = poolOf(item.slot)
            byPool[pool] = byPool[pool] or {}
            local list = byPool[pool]
            list[#list + 1] = cand
        end
    end
    local pools, dropped, kept = {}, {}, 0
    for pool, list in pairs(byPool) do
        table.sort(list, function(a, b)
            if a.signed ~= b.signed then
                return a.signed > b.signed
            end
            return a.order < b.order
        end)
        local need = (pool == "Finger" or pool == "Trinket") and 2 or 1
        local keep = {}
        for _, c in ipairs(list) do
            local drop = false
            if opts.prune ~= false and canBeDropped(c, opts.effects) then
                local over = {}
                for _, k in ipairs(keep) do
                    if canOutclass(k) and outclasses(k, c, signs) then
                        over[#over + 1] = k
                    end
                end
                drop = wearableCount(over) >= need
            end
            if drop then
                dropped[#dropped + 1] = c
            else
                keep[#keep + 1] = c
            end
        end
        -- The ascent starts from the front: best one-item proxy first.
        table.sort(keep, function(a, b)
            if a.proxy ~= b.proxy then
                return a.proxy > b.proxy
            end
            return a.order < b.order
        end)
        pools[pool] = keep
        kept = kept + #keep
    end
    table.sort(dropped, function(a, b)
        return a.order < b.order
    end)
    return { pools = pools, dropped = dropped, kept = kept }
end

-- ---------------------------------------------------------------------------
-- Masks.

local function tierOptions(list, weights)
    local seen, options = {}, {}
    for _, entry in ipairs(list) do
        local item = entry.item or entry
        local key = entry.tier
        if key == nil then
            key = tierKeyOf(item, weights)
        end
        local index = key and tostring(key) or "none"
        if not seen[index] then
            seen[index] = true
            options[#options + 1] = key or false
        end
    end
    table.sort(options, function(a, b)
        if a == false or b == false then
            return b == false and a ~= false
        end
        return a < b
    end)
    return options
end

-- Masks(items, weights) -> `{ { [tierSlot] = setID | false } }`: for each
-- tier slot holding a candidate, every tier set the weights file carries that
-- a candidate there belongs to, plus false ("none of them") when a candidate
-- belongs to none; every combination, in a fixed order. `items` is a list of
-- vectors with `slot`, or Candidates' pools.
function EngineSearch.Masks(items, weights)
    weights = weights or ns.EngineScore.file or {}
    local bySlot = {}
    if type(items) == "table" and items[1] == nil and next(items) ~= nil then
        for pool, list in pairs(items) do
            bySlot[pool] = list
        end
    else
        for _, item in ipairs(items or {}) do
            if type(item) == "table" and item.slot then
                bySlot[item.slot] = bySlot[item.slot] or {}
                local list = bySlot[item.slot]
                list[#list + 1] = item
            end
        end
    end
    local masks = { {} }
    for _, slot in ipairs(EngineSearch.TIER_SLOTS) do
        local list = bySlot[slot]
        if list and #list > 0 then
            local options = tierOptions(list, weights)
            local nextMasks = {}
            for _, mask in ipairs(masks) do
                for _, key in ipairs(options) do
                    local copy = {}
                    for k, v in pairs(mask) do
                        copy[k] = v
                    end
                    copy[slot] = key
                    nextMasks[#nextMasks + 1] = copy
                end
            end
            masks = nextMasks
        end
    end
    return masks
end

-- ---------------------------------------------------------------------------
-- Coordinates and their options.

local function byOrder(a, b)
    return a.order < b.order
end

local function sameUnique(a, b)
    local ua, ub = a.item.uniqueness, b.item.uniqueness
    return a.item.itemID == b.item.itemID
        and type(ua) == "table"
        and ua.isUnique
        and type(ub) == "table"
        and ub.isUnique
end

-- A pair option keeps its two pieces in input order, so one set always flattens
-- to one list (one value, one cache key).
local function pairOptions(pool)
    local out = {}
    for i = 1, #pool - 1 do
        for j = i + 1, #pool do
            if not sameUnique(pool[i], pool[j]) then
                local o = { pool[i], pool[j] }
                table.sort(o, byOrder)
                out[#out + 1] = o
            end
        end
    end
    if #out == 0 then
        for _, c in ipairs(pool) do
            out[#out + 1] = { c }
        end
    end
    return out
end

local function weaponOptions(pools)
    local ones, offs, twos =
        pools[EngineSearch.ONE_HAND] or {}, pools[EngineSearch.OFF_HAND] or {}, pools[EngineSearch.TWO_HAND] or {}
    local out = {}
    -- One-hand plus off-hand first: the proxy order inside each, so the start
    -- is the best pair by proxy; two-handers after, and the start compares.
    for _, main in ipairs(ones) do
        if #offs > 0 then
            for _, off in ipairs(offs) do
                out[#out + 1] = { main, off }
            end
        else
            out[#out + 1] = { main }
        end
    end
    if #ones == 0 then
        for _, off in ipairs(offs) do
            out[#out + 1] = { off }
        end
    end
    for _, two in ipairs(twos) do
        out[#out + 1] = { two }
    end
    return out
end

local function proxyOf(option)
    local p = 0
    for _, c in ipairs(option) do
        p = p + c.proxy
    end
    return p
end

-- The coordinates for one mask: `{ name, kind, options }` in the fixed order
-- singles, rings, trinkets, weapon; nil and why when a tier slot the mask
-- names has no piece of that set.
local function coordinatesFor(pools, mask)
    local coords = {}
    for _, slot in ipairs(EngineSearch.SINGLES) do
        local pool = pools[slot]
        if pool and #pool > 0 then
            local options = {}
            for _, c in ipairs(pool) do
                if mask == nil or mask[slot] == nil or c.tier == mask[slot] then
                    options[#options + 1] = { c }
                end
            end
            if #options == 0 then
                return nil, "no piece for the mask in " .. slot
            end
            coords[#coords + 1] = { name = slot, kind = "single", options = options }
        end
    end
    for _, pool in ipairs(EngineSearch.PAIRS) do
        local list = pools[pool]
        if list and #list > 0 then
            local options = pairOptions(list)
            table.sort(options, function(a, b)
                local pa, pb = proxyOf(a), proxyOf(b)
                if pa ~= pb then
                    return pa > pb
                end
                if a[1].order ~= b[1].order then
                    return a[1].order < b[1].order
                end
                return (a[2] and a[2].order or 0) < (b[2] and b[2].order or 0)
            end)
            coords[#coords + 1] = { name = pool, kind = "pair", options = options }
        end
    end
    local weapons = weaponOptions(pools)
    if #weapons > 0 then
        table.sort(weapons, function(a, b)
            local pa, pb = proxyOf(a), proxyOf(b)
            if pa ~= pb then
                return pa > pb
            end
            if a[1].order ~= b[1].order then
                return a[1].order < b[1].order
            end
            return (a[2] and a[2].order or 0) < (b[2] and b[2].order or 0)
        end)
        coords[#coords + 1] = { name = EngineSearch.WEAPON, kind = "weapon", options = weapons }
    end
    return coords
end

-- The limit categories any option of a coordinate carries.
local function categoriesOf(coord)
    local out = {}
    for _, option in ipairs(coord.options) do
        for _, c in ipairs(option) do
            local u = c.item.uniqueness
            if type(u) == "table" and u.category ~= nil then
                out[u.category] = true
            end
        end
    end
    return out
end

-- couplesOf(coords) -> `{ { i, j } }`, i < j: the coordinate pairs the coupled
-- sweep tries together (E-1e, WKE-703), in coordinate order.
--
-- Why these two kinds. E-1d (WKE-687) found coordinate ascent stopping where no
-- SINGLE coordinate improves but two changed at once would (ARCHITECTURE.md
-- section 11, two causes, measured on seeded synthetic inventories):
--   1. a limit category shared ACROSS positions (a neck and a ring, max 1):
--      while the category neck is worn the category ring is never feasible,
--      and the neck alone never leaves it, because the ring cannot follow in
--      the same move. Any two coordinates whose options carry one category are
--      a couple. (Two copies of one unique itemID are always in one pool, and
--      a pair option already keeps them apart.)
--   2. totals inside the DR brackets: the value is not separable, so trading
--      one coordinate's stats for another's can pay only when both move. The
--      trinket pair and the weapon choice are the two coordinates that carry
--      the most rating (two pieces; a two-hander's doubled stats), where E-1d
--      saw it. Other couples that DR can make are not swept: on the owner's
--      pieces only haste can reach a bracket at all (E-1d, section 9), and a
--      sweep of every couple multiplies the cost (section 11 keeps it open).
local function couplesOf(coords)
    local out = {}
    local cats = {}
    local trinket, weapon
    for i, coord in ipairs(coords) do
        cats[i] = categoriesOf(coord)
        if coord.name == "Trinket" then
            trinket = i
        elseif coord.kind == "weapon" then
            weapon = i
        end
    end
    local seen = {}
    local function add(i, j)
        if i > j then
            i, j = j, i
        end
        local key = i .. ":" .. j
        if i ~= j and not seen[key] then
            seen[key] = true
            out[#out + 1] = { i, j }
        end
    end
    for i = 1, #coords - 1 do
        for j = i + 1, #coords do
            for category in pairs(cats[i]) do
                if cats[j][category] then
                    add(i, j)
                    break
                end
            end
        end
    end
    if trinket and weapon then
        add(trinket, weapon)
    end
    table.sort(out, function(a, b)
        if a[1] ~= b[1] then
            return a[1] < b[1]
        end
        return a[2] < b[2]
    end)
    return out
end

-- The set as SetValue reads it, in coordinate order, and its cache key.
local function flatten(coords, choice)
    local list, ids = {}, {}
    for i = 1, #coords do
        local option = choice[i]
        if option then
            for _, c in ipairs(option) do
                list[#list + 1] = c.item
                ids[#ids + 1] = c.order
            end
        end
    end
    table.sort(ids)
    return list, table.concat(ids, ",")
end

-- One full set value; every call counts unless the cache already holds it.
-- `list` and `key` may be handed in when the caller has just flattened.
local function evaluate(ctx, coords, choice, list, key)
    if not list then
        list, key = flatten(coords, choice)
    end
    if ctx.cache and ctx.cache[key] then
        return ctx.cache[key].value, ctx.cache[key]
    end
    local scored, why = ns.EngineScore.SetValue(list, ctx.scoreOpts)
    ctx.evaluations = ctx.evaluations + 1
    if ctx.tick then
        ctx.tick()
    end
    if not scored then
        return nil, why
    end
    if ctx.cache then
        ctx.cache[key] = scored
    end
    return scored.value, scored
end

local function better(v, than)
    return v > than + math.abs(than) * EngineSearch.EPSILON
end

-- The start: each coordinate's first option that keeps the partial set
-- feasible, in coordinate order.
local function start(ctx, coords)
    local choice = {}
    for i, coord in ipairs(coords) do
        local found = false
        for _, option in ipairs(coord.options) do
            choice[i] = option
            if feasible(ctx.hooks, (flatten(coords, choice))) then
                found = true
                break
            end
        end
        if not found then
            return nil, "no feasible piece for " .. coord.name
        end
    end
    return choice
end

local function ascendIn(ctx, coords)
    local choice, why = start(ctx, coords)
    if not choice then
        return nil, why
    end
    local value, scored = evaluate(ctx, coords, choice)
    if not value then
        return nil, scored
    end
    -- One feasible candidate set: valued (or nil and why on a SetValue
    -- refusal), or false when a hook rejects it.
    local function try()
        local list, key = flatten(coords, choice)
        if not feasible(ctx.hooks, list) then
            return false
        end
        return evaluate(ctx, coords, choice, list, key)
    end
    -- One single sweep: each coordinate's best option, the rest kept.
    local function singleSweep()
        local improved = false
        for i, coord in ipairs(coords) do
            local current = choice[i]
            local bestOption, bestValue, bestScored = current, value, scored
            for _, option in ipairs(coord.options) do
                if option ~= current then
                    choice[i] = option
                    local v, s = try()
                    if v == nil then
                        return nil, s
                    end
                    if v and better(v, bestValue) then
                        bestOption, bestValue, bestScored = option, v, s
                    end
                end
            end
            choice[i] = bestOption
            if bestOption ~= current then
                value, scored = bestValue, bestScored
                improved = true
            end
        end
        return improved
    end
    -- One coupled pass (E-1e): for each couple, every combination of its two
    -- coordinates' options in which BOTH change (a move of one alone is a
    -- single move, already no better once the single sweeps stop); the best
    -- such move of the first couple that has one is taken.
    local couples = couplesOf(coords)
    local function coupledPass()
        for _, couple in ipairs(couples) do
            local i, j = couple[1], couple[2]
            local ci, cj = choice[i], choice[j]
            local bestI, bestJ, bestValue, bestScored = ci, cj, value, scored
            for _, oi in ipairs(coords[i].options) do
                if oi ~= ci then
                    for _, oj in ipairs(coords[j].options) do
                        if oj ~= cj then
                            choice[i], choice[j] = oi, oj
                            local v, s = try()
                            if v == nil then
                                choice[i], choice[j] = ci, cj
                                return nil, s
                            end
                            if v and better(v, bestValue) then
                                bestI, bestJ, bestValue, bestScored = oi, oj, v, s
                            end
                        end
                    end
                end
            end
            choice[i], choice[j] = bestI, bestJ
            if bestI ~= ci then
                value, scored = bestValue, bestScored
                return true
            end
        end
        return false
    end
    local sweeps, coupledPasses, coupledMoves = 0, 0, 0
    while sweeps + coupledPasses < EngineSearch.MAX_SWEEPS do
        sweeps = sweeps + 1
        local improved, failed = singleSweep()
        if improved == nil then
            return nil, failed
        end
        if not improved then
            coupledPasses = coupledPasses + 1
            local moved, refused = coupledPass()
            if moved == nil then
                return nil, refused
            end
            if not moved then
                break
            end
            coupledMoves = coupledMoves + 1
        end
    end
    return {
        coords = coords,
        choice = choice,
        value = value,
        scored = scored,
        sweeps = sweeps,
        coupledPasses = coupledPasses,
        coupledMoves = coupledMoves,
    }
end

-- Ascend(pools, mask, weights, constraints, opts) -> `{ value, scored, items,
-- choice, coords, sweeps, coupledPasses, coupledMoves, evaluations }` | nil,
-- reason. `sweeps` counts the single sweeps, `coupledPasses` the coupled
-- passes tried, `coupledMoves` the ones that moved (E-1e). `pools` is
-- Candidates' `pools`; `mask` one of Masks' (nil: no tier restriction);
-- `constraints` hooks added to the built-in ones.
function EngineSearch.Ascend(pools, mask, weights, constraints, opts)
    local allowed, refusal = EngineSearch.Allowed()
    if not allowed then
        return nil, refusal
    end
    opts = opts or {}
    local o = {}
    for k, v in pairs(opts) do
        o[k] = v
    end
    o.constraints = constraints or opts.constraints
    local ctx, why = newContext(weights, o)
    if not ctx then
        return nil, why
    end
    local coords, noMask = coordinatesFor(pools, mask)
    if not coords then
        return nil, noMask
    end
    local result, failed = ascendIn(ctx, coords)
    if not result then
        return nil, failed
    end
    result.items = (flatten(coords, result.choice))
    result.evaluations = ctx.evaluations
    return result
end

-- ---------------------------------------------------------------------------
-- Best.

-- Two options hold the same pieces (in any order). An option is a fresh
-- table per coordinatesFor call, so two options are compared by the cands
-- they hold, never by identity: before E-1b (WKE-688) a single slot's and the
-- weapon's runner-up compared `option ~= current` across two calls, which is
-- always true, so the "alternative" was the worn piece itself and every such
-- position printed `next best -0.000%` (the owner's 2026-10-05 screens).
local function samePieces(a, b)
    if #a ~= #b then
        return false
    end
    local left = {}
    for _, c in ipairs(a) do
        left[c] = (left[c] or 0) + 1
    end
    for _, c in ipairs(b) do
        if not left[c] or left[c] == 0 then
            return false
        end
        left[c] = left[c] - 1
    end
    return true
end

-- What the runner-up says: `only` - the position had no other piece;
-- `none` - other pieces, none of them wearable here; `tie` - a different
-- piece worth exactly as much (within EPSILON); `next` - a delta.
local function runnerUpState(others, alt, delta, value)
    if others == 0 then
        return "only"
    end
    if not alt or delta == nil then
        return "none"
    end
    if math.abs(delta) <= math.abs(value) * EngineSearch.EPSILON then
        return "tie"
    end
    return "next"
end

-- Each position of the best set, and what the best alternative there gives
-- up with every other position kept (any piece the position holds, whatever
-- the mask). A ring or trinket is a position of its own, its partner kept.
-- `candidates` counts the pieces the position could hold (its own included),
-- `state` is runnerUpState's word.
local function runnerUps(ctx, pools, best)
    local free = coordinatesFor(pools, nil) or {}
    local out = {}
    local coords, choice = best.coords, best.choice
    local function alternatives(i, keepPartner)
        local coord = coords[i]
        local current = choice[i]
        local bestAlt, bestValue
        local others = 0
        local options = {}
        for _, fc in ipairs(free) do
            if fc.name == coord.name then
                options = fc.options
                break
            end
        end
        for _, option in ipairs(options) do
            local fits = not samePieces(option, current)
            if keepPartner then
                -- Only options that keep the partner and change this piece.
                fits = #option == 2
                    and (
                        (option[1] == keepPartner.partner and option[2] ~= keepPartner.self)
                        or (option[2] == keepPartner.partner and option[1] ~= keepPartner.self)
                    )
            end
            if fits then
                others = others + 1
                local held = choice[i]
                choice[i] = option
                local list, key = flatten(coords, choice)
                if feasible(ctx.hooks, list) then
                    local v = evaluate(ctx, coords, choice, list, key)
                    if v and (not bestValue or better(v, bestValue)) then
                        bestAlt, bestValue = option, v
                    end
                end
                choice[i] = held
            end
        end
        return bestAlt, bestValue, others
    end
    for i, coord in ipairs(coords) do
        local option = choice[i]
        if coord.kind == "pair" and #option == 2 then
            for n = 1, 2 do
                local self, partner = option[n], option[3 - n]
                local alt, v, others = alternatives(i, { self = self, partner = partner })
                local altPiece = alt and ((alt[1] == partner) and alt[2] or alt[1]) or nil
                local delta = v and (best.value - v) or nil
                out[#out + 1] = {
                    position = coord.name .. " " .. n,
                    pieces = { self.item },
                    alternative = altPiece and { altPiece.item } or nil,
                    delta = delta,
                    candidates = others + 1,
                    state = runnerUpState(others, altPiece, delta, best.value),
                }
            end
        else
            local alt, v, others = alternatives(i)
            local pieces, altPieces = {}, nil
            for _, c in ipairs(option) do
                pieces[#pieces + 1] = c.item
            end
            if alt then
                altPieces = {}
                for _, c in ipairs(alt) do
                    altPieces[#altPieces + 1] = c.item
                end
            end
            local delta = v and (best.value - v) or nil
            out[#out + 1] = {
                position = coord.name,
                pieces = pieces,
                alternative = altPieces,
                delta = delta,
                candidates = others + 1,
                state = runnerUpState(others, alt, delta, best.value),
            }
        end
    end
    for _, r in ipairs(out) do
        r.percent = r.delta and best.value ~= 0 and (100 * r.delta / best.value) or nil
    end
    return out
end

-- Best(items, weights, opts) -> `{ value, scored, items, positions =
-- runner-ups, evaluations, ascentEvaluations, masks, maskUsed, dropped, kept,
-- band }` | nil, reason.
--
-- `items`: ns.EngineStats vectors with `slot` (Vectors builds them from the
-- scan). `weights`: the weights file (default what EngineScore.Load kept).
-- `opts`: spec, contentType, keyLevel or band (the band, by BandFor's rule),
-- assumedFinish (default true), dr, rating, effects (passed to SetValue),
-- constraints (hooks added to the built-in ones), prune (false keeps every
-- piece), tick (called after every evaluation - Run's yield).
function EngineSearch.Best(items, weights, opts)
    local allowed, refusal = EngineSearch.Allowed()
    if not allowed then
        return nil, refusal
    end
    opts = opts or {}
    local ctx, why = newContext(weights, opts)
    if not ctx then
        return nil, why
    end
    local candidates, noBand = EngineSearch.Candidates(items, ctx.weights, opts)
    if not candidates then
        return nil, noBand
    end
    local masks = EngineSearch.Masks(candidates.pools, ctx.weights)
    local best, lastWhy
    for _, mask in ipairs(masks) do
        local coords, noMask = coordinatesFor(candidates.pools, mask)
        if coords then
            local result, failed = ascendIn(ctx, coords)
            if result then
                if not best or better(result.value, best.value) then
                    best = result
                    best.mask = mask
                end
            else
                lastWhy = failed
                if failed ~= nil and not tostring(failed):find("^no feasible") then
                    return nil, failed
                end
            end
        else
            lastWhy = noMask
        end
    end
    if not best then
        return nil, lastWhy or "nothing to wear"
    end
    local ascentEvaluations = ctx.evaluations
    local positions = runnerUps(ctx, candidates.pools, best)
    return {
        value = best.value,
        scored = best.scored,
        items = (flatten(best.coords, best.choice)),
        positions = positions,
        evaluations = ctx.evaluations,
        ascentEvaluations = ascentEvaluations,
        masks = #masks,
        maskUsed = best.mask,
        dropped = candidates.dropped,
        kept = candidates.kept,
        band = ctx.bandKey,
    }
end

-- ---------------------------------------------------------------------------
-- Brute force, for small inventories only.

-- BruteForce(items, weights, opts) -> `{ value, scored, items, sets,
-- evaluations }` | nil, reason. Every wearable set over every piece
-- (`opts.prune = true` uses Candidates' pools instead), valued one by one;
-- refused when there are more than BRUTE_FORCE_CAP sets.
function EngineSearch.BruteForce(items, weights, opts)
    local allowed, refusal = EngineSearch.Allowed()
    if not allowed then
        return nil, refusal
    end
    opts = opts or {}
    local o = {}
    for k, v in pairs(opts) do
        o[k] = v
    end
    o.prune = opts.prune == true
    o.cache = false
    local ctx, why = newContext(weights, o)
    if not ctx then
        return nil, why
    end
    local candidates, noBand = EngineSearch.Candidates(items, ctx.weights, o)
    if not candidates then
        return nil, noBand
    end
    local coords = coordinatesFor(candidates.pools, nil) or {}
    local sets = 1
    for _, coord in ipairs(coords) do
        sets = sets * #coord.options
    end
    local cap = opts.cap or EngineSearch.BRUTE_FORCE_CAP
    if sets > cap then
        return nil, string.format("too many sets: %d over the cap of %d", sets, cap)
    end
    local choice, index = {}, {}
    for i, coord in ipairs(coords) do
        index[i] = 1
        choice[i] = coord.options[1]
    end
    local best
    local n = #coords
    while true do
        local list, key = flatten(coords, choice)
        if feasible(ctx.hooks, list) then
            local v, scored = evaluate(ctx, coords, choice, list, key)
            if not v then
                return nil, scored
            end
            if not best or better(v, best.value) then
                best = { value = v, scored = scored, items = list }
            end
        end
        local i = n
        while i >= 1 do
            index[i] = index[i] + 1
            if index[i] <= #coords[i].options then
                choice[i] = coords[i].options[index[i]]
                break
            end
            index[i] = 1
            choice[i] = coords[i].options[1]
            i = i - 1
        end
        if i < 1 then
            break
        end
    end
    if not best then
        return nil, "nothing to wear"
    end
    best.sets = sets
    best.evaluations = ctx.evaluations
    return best
end

-- ---------------------------------------------------------------------------
-- The coroutine: Best, a slice per frame.

local state = { frame = nil, job = nil }

-- Run(items, weights, opts, onDone) -> job | nil, reason. Runs Best inside a
-- coroutine resumed on the frame's OnUpdate; after every evaluation it yields
-- once the slice has run `opts.budgetMs` (BUDGET_MS) by `opts.clock`
-- (debugprofilestop). Before every slice it checks combat: in combat it stops
-- and waits for PLAYER_REGEN_ENABLED, then picks up where it was (the same
-- coroutine, the same reads). With the switch turned off it stops for good.
-- `onDone(result, why, job)` once: `job = { slices, pauses, busyMs, wallMs }`.
function EngineSearch.Run(items, weights, opts, onDone)
    local allowed, refusal = EngineSearch.Allowed()
    if not allowed then
        return nil, refusal
    end
    if state.job then
        return nil, EngineSearch.TEXT.running
    end
    opts = opts or {}
    local clock = opts.clock or debugprofilestop
    local budget = opts.budgetMs or EngineSearch.BUDGET_MS
    local job = { slices = 0, pauses = 0, busyMs = 0, startedAt = clock() }
    local sliceStart = job.startedAt
    local runOpts = {}
    for k, v in pairs(opts) do
        runOpts[k] = v
    end
    runOpts.tick = function()
        if clock() - sliceStart >= budget then
            coroutine.yield()
        end
    end
    job.co = coroutine.create(function()
        return EngineSearch.Best(items, weights, runOpts)
    end)
    local frame = state.frame or CreateFrame("Frame")
    state.frame = frame
    state.job = job

    local step
    local function finish(result, why)
        frame:SetScript("OnUpdate", nil)
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        state.job = nil
        job.wallMs = clock() - job.startedAt
        job.done = true
        if onDone then
            onDone(result, why, job)
        end
    end
    step = function()
        if not EngineSearch.Enabled() then
            return finish(nil, EngineSearch.TEXT.notOn)
        end
        if InCombatLockdown() then
            frame:SetScript("OnUpdate", nil)
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            job.pauses = job.pauses + 1
            return
        end
        sliceStart = clock()
        local ok, result, why = coroutine.resume(job.co)
        job.busyMs = job.busyMs + (clock() - sliceStart)
        job.slices = job.slices + 1
        if not ok then
            return finish(nil, "errored: " .. tostring(result))
        end
        if coroutine.status(job.co) == "dead" then
            return finish(result, why)
        end
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and state.job == job then
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            frame:SetScript("OnUpdate", step)
        end
    end)
    frame:SetScript("OnUpdate", step)
    job.frame = frame
    return job
end

-- Whether a search is running (for tests and the command).
function EngineSearch.Running()
    return state.job ~= nil
end

-- ---------------------------------------------------------------------------
-- The command: `/lootpath engine best [dungeon|raid] [keylevel]`.

-- Vectors(records, reads) -> items, counts. Each scan record whose read is
-- ready and not secret, as the read's copy with the record's slot, key, link,
-- location, name and level.
function EngineSearch.Vectors(records, reads)
    local items, notReady, secret = {}, 0, 0
    for _, record in ipairs(records or {}) do
        local read = reads[record.link]
        if type(read) ~= "table" or read.ready ~= true then
            notReady = notReady + 1
        elseif read.secret then
            secret = secret + 1
        else
            local v = {}
            for k, x in pairs(read) do
                v[k] = x
            end
            v.slot = record.slot
            v.recordKey = record.key
            v.link = record.link
            v.location = record.location
            v.name = record.name
            v.level = read.level or record.itemLevel
            items[#items + 1] = v
        end
    end
    return items, { notReady = notReady, secret = secret }
end

local CONTENT = { dungeon = "Dungeon", raid = "Raid" }

local function fmt(x, pattern)
    if type(x) ~= "number" then
        return "-"
    end
    return string.format(pattern, x)
end

local function nameOf(item)
    local name = item.name or ("item " .. tostring(item.itemID))
    return string.format("%s %s", name, tostring(item.level or "?"))
end

local function whereOf(items)
    local T = EngineSearch.TEXT
    local words = {}
    for _, item in ipairs(items) do
        words[#words + 1] = (item.location == "equipped" and T.worn) or (item.location == "bank" and T.bank) or T.bag
    end
    return table.concat(words, " + ")
end

-- BandKeys(file, spec, contentType) -> the band keys the weights file carries
-- for that content type, key levels first in number order, then the rest in
-- text order ({} when it carries none). The `no band` refusal names them
-- (E-1b, WKE-688): a fitted file's Dungeon side carries one band per key
-- level, so `best` with no key level finds none (EngineScore.BandFor rule 3).
function EngineSearch.BandKeys(file, spec, contentType)
    local specs = type(file) == "table" and file.specs
    local bySpec = type(specs) == "table" and specs[spec or ns.EngineScore.DEFAULT_SPEC]
    local content = type(bySpec) == "table" and bySpec[contentType or ns.EngineScore.DEFAULT_CONTENT]
    local bands = type(content) == "table" and content.bands
    local keys = {}
    if type(bands) ~= "table" then
        return keys
    end
    for key, band in pairs(bands) do
        if type(band) == "table" then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then
            return na < nb
        end
        if na or nb then
            return na ~= nil
        end
        return a < b
    end)
    return keys
end

local function namesOf(items)
    local names = {}
    for _, item in ipairs(items or {}) do
        names[#names + 1] = nameOf(item)
    end
    return table.concat(names, " + ")
end

-- The tail of one position's line: the runner-up's delta, `only piece`, a
-- tie with the piece named, or `nothing else fits`.
local function runnerUpTail(p)
    local T = EngineSearch.TEXT
    if p.state == "only" then
        return T.onlyPiece
    end
    if p.state == "tie" then
        return string.format(T.tie, namesOf(p.alternative))
    end
    if p.percent then
        return string.format(T.runnerUp, fmt(-p.percent, "%.3f"))
    end
    return T.noRunnerUp
end

-- Lines(run) -> the chat lines for one finished search.
function EngineSearch.Lines(run)
    local T = EngineSearch.TEXT
    local file = run.file or {}
    local lines = {
        string.format(
            T.header,
            tostring(file.method),
            tostring(file.patch),
            tostring(file.derivedAt),
            tostring(run.contentType),
            tostring(run.result and run.result.band or "-")
        ),
    }
    local result = run.result
    if not result then
        lines[#lines + 1] = string.format(T.noSet, tostring(run.why))
        if tostring(run.why):find("^no band") then
            local keys = EngineSearch.BandKeys(run.file, nil, run.contentType)
            lines[#lines + 1] =
                string.format(T.bands, tostring(run.contentType), #keys > 0 and table.concat(keys, ", ") or "none")
        end
        return lines
    end
    for _, p in ipairs(result.positions) do
        lines[#lines + 1] = string.format(T.position, p.position, namesOf(p.pieces), whereOf(p.pieces), runnerUpTail(p))
    end
    local gain = run.wornValue and run.wornValue ~= 0 and (100 * (result.value - run.wornValue) / run.wornValue) or nil
    lines[#lines + 1] =
        string.format(T.values, fmt(result.value, "%.1f"), fmt(run.wornValue, "%.1f"), fmt(gain, "%+.2f"))
    local job = run.job or {}
    lines[#lines + 1] = string.format(
        T.cost,
        result.evaluations,
        result.masks,
        fmt(job.busyMs, "%.1f"),
        job.slices or 0,
        fmt(job.wallMs, "%.1f")
    )
    if (job.pauses or 0) > 0 then
        lines[#lines + 1] = string.format(T.paused, job.pauses)
    end
    lines[#lines + 1] =
        string.format(T.leftOut, run.notReady or 0, run.secret or 0, run.notForSpec or 0, #(result.dropped or {}))
    local unmodelled = result.scored and result.scored.unmodelled
    local unknown = result.scored and result.scored.unknown
    local n = (unmodelled and #unmodelled or 0) + (unknown and #unknown or 0)
    if n > 0 then
        lines[#lines + 1] = string.format(T.notRated, n)
    end
    return lines
end

-- Gather(specID) -> records, notForSpec | nil, reason: the scan, without the
-- pieces the client says are not for the spec (ItemData.SpecFit false; no
-- answer keeps the piece).
function EngineSearch.Gather(specID)
    local scan = ns.Inventory.Scan()
    if not scan.ok then
        return nil, scan.reason
    end
    local records, notForSpec = {}, 0
    for _, record in ipairs(scan.records) do
        if ns.ItemData.SpecFit(record.link, specID) == false then
            notForSpec = notForSpec + 1
        else
            records[#records + 1] = record
        end
    end
    return records, notForSpec
end

-- Command(words, onDone): `words` are the lower-cased words after `engine`,
-- `best` first. Answers one line without the switch or in combat.
function EngineSearch.Command(words, onDone)
    local T = EngineSearch.TEXT
    local allowed, refusal = EngineSearch.Allowed()
    if not allowed then
        ns.Log("%s", refusal)
        return
    end
    local contentType, keyLevel = nil, nil
    for i = 2, #words do
        if CONTENT[words[i]] then
            contentType = CONTENT[words[i]]
        elseif tonumber(words[i]) then
            keyLevel = tonumber(words[i])
        else
            ns.Log("%s", ns.EngineCompare.TEXT.usage)
            return
        end
    end
    if not contentType then
        local profile = ns.db and ns.db.profile
        local settings = type(profile) == "table" and profile.settings or nil
        contentType = type(settings) == "table" and settings.contentType or "Dungeon"
        if contentType ~= "Raid" then
            contentType = "Dungeon"
        end
    end
    if not ns.EngineScore.file then
        local ok, line, detail = ns.EngineScore.Load()
        if not ok then
            ns.Log("%s", line)
            if detail then
                ns.Log("%s", detail)
            end
            return
        end
    end
    if state.job then
        ns.Log("%s", T.running)
        return
    end
    local records, notForSpec = EngineSearch.Gather(ns.EngineScore.DEFAULT_SPEC)
    if not records then
        ns.Log("%s", T.combat)
        return
    end
    local links, seen = {}, {}
    for _, record in ipairs(records) do
        if not seen[record.link] then
            seen[record.link] = true
            links[#links + 1] = record.link
        end
    end
    local file = ns.EngineScore.file
    ns.EngineCompare.Resolve(links, function(reads)
        local items, counts = EngineSearch.Vectors(records, reads)
        local opts = { contentType = contentType, keyLevel = keyLevel }
        local worn = {}
        for _, item in ipairs(items) do
            if item.location == "equipped" then
                worn[#worn + 1] = item
            end
        end
        local wornScored = ns.EngineScore.SetValue(worn, scoreOptsOf(file, opts))
        local run = {
            file = file,
            contentType = contentType,
            keyLevel = keyLevel,
            notReady = counts.notReady,
            secret = counts.secret,
            notForSpec = notForSpec,
            wornValue = wornScored and wornScored.value or nil,
        }
        local function report(result, why, job)
            run.result, run.why, run.job = result, why, job
            for _, line in ipairs(EngineSearch.Lines(run)) do
                ns.Log("%s", line)
            end
            if onDone then
                onDone(run)
            end
        end
        local job, why = EngineSearch.Run(items, file, opts, report)
        if not job then
            ns.Log("%s", why)
        end
    end)
end
