-- Lootpath/Modules/EngineScore.lua (E-0c, WKE-672)
-- The first number Lootpath makes: a set value from item stats, the rating
-- conversion and a shipped weights file (Data/EngineWeights.lua), and an
-- upgrade percent from two such values. DEVELOPER-ONLY and scoped by
-- docs/ARCHITECTURE.md section 7 (2026-09-30, E-0, the owner's second word;
-- E-0c): behind `db.global.developer.engine`, read by no tooltip, glow, Equip
-- Now, Upgrade Map, Vault or strip (spec/enginescore_spec.lua reads every UI
-- file to hold that), never combined with QE Live's numbers in one list.
-- Section 1's rule governs every surface a player sees.
--
-- The model is QE Live's Restoration Druid Top Gear, which is linear (fork
-- TopGearEngine.ts:947-1097, ItemUtilities.ts:593-607):
--
--   totals  = the set's stats summed, plus its gems (or, in the parity mode,
--             the file's assumed gem per socket and enchant per slot), plus
--             the file's assumed buffs
--   pct_r   = each rating's total converted to percent AFTER the sum
--   value   = (baseValue + w_int * int + sum_r w_r * pct_r) * tier multiplier
--   percent = 100 * (V(best set with the candidate) - V(worn)) / V(worn)
--
-- Our percents are UNSCALED: no 1.5 (Top Gear's `modelDiff`) anywhere here.
--
-- Effects (E-3a, WKE-679): an item whose ID is in the effects table
-- (Data/EngineEffects.lua, ns.EngineEffects) is an effect item. A modelled
-- stat effect's vector is added to the totals before the conversion; a
-- modelled healing effect is kept in `effects` and added to the value only
-- when the band (or the file) carries `hpsPerValue` - healing per second per
-- point of value - else it is NOT added and the result says
-- `hpsNotAdded = true`. An effect not modelled (every entry today: the table
-- ships with no numbers) leaves the item's STATS counting and marks the
-- result `effectUnmodelled` with the item named. A trinket the table does not
-- carry is scored on its stats and marked `effectUnknown`.

local _, ns = ...

ns.EngineScore = {}
local EngineScore = ns.EngineScore

-- Every client function this file calls, named rather than discovered. Only
-- Load asks the client anything; SetValue and UpgradePercent call nothing but
-- the rating function they are handed (default ns.EngineStats.Rating, which
-- names its own).
EngineScore.FUNCTION_NAMES = { "GetBuildInfo" }

EngineScore.SCHEMA = "lootpath-engine-weights"
EngineScore.VERSION = 1

-- What the loader says, and nothing else. Printed only for a developer.
EngineScore.TEXT = {
    patch = "Update Lootpath - its ratings are for %s, you're on %s.",
    broken = "Not rated - the rating data didn't load.",
    loaded = "Engine ratings for %s loaded.",
    placeholder = "Engine ratings for %s loaded - placeholder numbers, none of them mean anything.",
}

EngineScore.DEFAULT_SPEC = 105
EngineScore.DEFAULT_CONTENT = "Dungeon"

-- The stats a total carries and the ones converted to percent.
EngineScore.STATS = { "int", "haste", "crit", "mastery", "vers", "leech" }
EngineScore.RATINGS = { "haste", "crit", "mastery", "vers", "leech" }

-- The off-hand slots a two-hander displaces (Inventory.SLOT_BY_EQUIPLOC's
-- vocabulary, which is QE Live's Top Gear export's).
local TWO_HAND = "2H Weapon"
local ONE_HAND = "1H Weapon"
local OFF_HANDS = { Offhand = true, Shield = true }
local TRINKET = "Trinket"

-- The loaded file, or nil; why it is not loaded; whether it is a placeholder.
EngineScore.file = nil
EngineScore.refusal = nil
EngineScore.status = "unloaded"

local function refuse(sentence)
    EngineScore.file = nil
    EngineScore.refusal = sentence
    EngineScore.status = "refused"
    return false, sentence
end

local function clientPatch()
    if type(GetBuildInfo) ~= "function" then
        return nil
    end
    local ok, version = pcall(GetBuildInfo)
    if not ok then
        return nil
    end
    local safe, secret = ns.Safe(version)
    if secret or type(safe) ~= "string" or safe == "" then
        return nil
    end
    return safe
end

-- Load() -> true, line | false, refusal. Reads ns.engineWeights (set by
-- Data/EngineWeights.lua at load) and GetBuildInfo()'s version, and keeps the
-- file only when its schema, version and spec table are there and its patch is
-- the client's.
function EngineScore.Load()
    local file = ns.engineWeights
    if type(file) ~= "table" then
        return refuse(EngineScore.TEXT.broken)
    end
    if file.schema ~= EngineScore.SCHEMA or file.version ~= EngineScore.VERSION then
        return refuse(EngineScore.TEXT.broken)
    end
    if type(file.specs) ~= "table" or next(file.specs) == nil then
        return refuse(EngineScore.TEXT.broken)
    end
    if type(file.patch) ~= "string" then
        return refuse(EngineScore.TEXT.broken)
    end
    local patch = clientPatch()
    if not patch then
        return refuse(EngineScore.TEXT.broken)
    end
    if file.patch ~= patch then
        return refuse(string.format(EngineScore.TEXT.patch, file.patch, patch))
    end
    EngineScore.file = file
    EngineScore.refusal = nil
    if file.method == "placeholder" then
        EngineScore.status = "placeholder"
        return true, string.format(EngineScore.TEXT.placeholder, file.patch)
    end
    EngineScore.status = "loaded"
    return true, string.format(EngineScore.TEXT.loaded, file.patch)
end

-- The reason a key level finds no band; the level is always named when there
-- is one, so a compare never prints a bare "no band" for a Dungeon document.
EngineScore.NO_BAND = "no band"
EngineScore.NO_BAND_FOR = "no band for +%d"

local function integerLevel(keyLevel)
    local level = tonumber(keyLevel)
    if not level or level < 0 or level % 1 ~= 0 then
        return nil
    end
    return level
end

-- BandFor(file, spec, contentType, keyLevel) -> band, key | nil, reason.
-- THE one rule that picks the band a set is scored with (E-0h, WKE-678;
-- docs/ARCHITECTURE.md section 7). It lives here, not in a caller, so every
-- caller - the compare today, anything later - resolves a key level the same
-- way. A weights file keys a band by a string: E-0e's fit writes the key level
-- (`["2"]` .. `["10"]`, tools/engine/lib/luaout.js), the placeholder `["10+"]`,
-- Raid `["raid-<difficulties>"]`. In order:
--   1. the band whose key is the key level as a string ("10" for 10);
--   2. else a key "<n>+" with n <= the key level, the highest such n ("10+"
--      serves 10 and above). Ranges ("7-9") may be supported later; they are
--      not read here;
--   3. else, when the content type has exactly one band, that band;
--   4. else nil and "no band for +<level>" ("no band" with no level).
-- Raid skips 1 and 2: a key level means nothing there, the only band is used.
-- The chosen band's KEY comes back beside it so a caller can print it.
function EngineScore.BandFor(file, spec, contentType, keyLevel)
    contentType = contentType or EngineScore.DEFAULT_CONTENT
    local level = integerLevel(keyLevel)
    local why = level and string.format(EngineScore.NO_BAND_FOR, level) or EngineScore.NO_BAND
    local specs = type(file) == "table" and file.specs
    local bySpec = type(specs) == "table" and specs[spec or EngineScore.DEFAULT_SPEC]
    local content = type(bySpec) == "table" and bySpec[contentType]
    local bands = type(content) == "table" and content.bands
    if type(bands) ~= "table" then
        return nil, why
    end
    if level and contentType ~= "Raid" then
        local exact = tostring(level)
        if type(bands[exact]) == "table" then
            return bands[exact], exact
        end
        local bestKey, bestFrom
        for key, band in pairs(bands) do
            local from = type(key) == "string" and type(band) == "table" and tonumber(key:match("^(%d+)%+$"))
            if from and from <= level and (not bestFrom or from > bestFrom) then
                bestKey, bestFrom = key, from
            end
        end
        if bestKey then
            return bands[bestKey], bestKey
        end
    end
    local onlyKey, onlyBand, n = nil, nil, 0
    for key, band in pairs(bands) do
        onlyKey, onlyBand, n = key, band, n + 1
    end
    if n == 1 and type(onlyBand) == "table" then
        return onlyBand, onlyKey
    end
    return nil, why
end

-- The band SetValue scores with: opts.spec (105), opts.contentType
-- ("Dungeon"), and opts.band (a key, taken as given) or opts.keyLevel through
-- BandFor's rule.
local function bandOf(file, opts)
    if opts.band ~= nil then
        local specs = type(file.specs) == "table" and file.specs[opts.spec or EngineScore.DEFAULT_SPEC]
        local content = type(specs) == "table" and specs[opts.contentType or EngineScore.DEFAULT_CONTENT]
        local bands = type(content) == "table" and content.bands
        local band = type(bands) == "table" and bands[opts.band] or nil
        if type(band) == "table" then
            return band, opts.band
        end
        return nil, EngineScore.NO_BAND
    end
    return EngineScore.BandFor(file, opts.spec, opts.contentType, opts.keyLevel)
end

local function add(totals, stats, times)
    if type(stats) ~= "table" then
        return
    end
    for _, stat in ipairs(EngineScore.STATS) do
        local v = stats[stat]
        if type(v) == "number" then
            totals[stat] = totals[stat] + v * times
        end
    end
end

-- Rating -> percent through a bracket table: below the first bracket every
-- point counts; inside a bracket its penalty applies to the rating there.
function EngineScore.TablePercent(rating, table_)
    if type(rating) ~= "number" or rating <= 0 or type(table_) ~= "table" then
        return 0
    end
    local per = table_.ratingPerPercent
    if type(per) ~= "number" or per <= 0 then
        return nil
    end
    local effective, prevFrom, prevPenalty = 0, 0, 0
    for _, b in ipairs(table_.brackets or {}) do
        if rating <= b.from then
            break
        end
        effective = effective + (b.from - prevFrom) * (1 - prevPenalty)
        prevFrom, prevPenalty = b.from, b.penalty
    end
    effective = effective + (rating - prevFrom) * (1 - prevPenalty)
    return effective / per
end

-- The setIDs in the file's tiers, sorted, each with its thresholds sorted:
-- built once per tiers table so a hot loop never sorts.
local tierOrder = setmetatable({}, { __mode = "k" })

local function orderedTiers(tiers)
    local held = tierOrder[tiers]
    if held then
        return held
    end
    local list = {}
    for setID, thresholds in pairs(tiers) do
        if type(setID) == "number" and type(thresholds) == "table" then
            local steps = {}
            for pieces, bonus in pairs(thresholds) do
                if type(pieces) == "number" and type(bonus) == "table" and type(bonus.mult) == "number" then
                    steps[#steps + 1] = { pieces = pieces, mult = bonus.mult }
                end
            end
            table.sort(steps, function(a, b)
                return a.pieces < b.pieces
            end)
            list[#list + 1] = { setID = setID, steps = steps }
        end
    end
    table.sort(list, function(a, b)
        return a.setID < b.setID
    end)
    tierOrder[tiers] = list
    return list
end

-- `{ setID, count, mult, forced }`: the set with the most pieces worn (the
-- lowest setID on a tie, or the file's lowest with none worn when forced).
-- Every set's reached bonuses add before they multiply (QE Live's bonusHPS).
-- Forced on, the chosen set counts as having reached every threshold.
local function tierOf(items, tiers, force)
    local result = { setID = nil, count = 0, mult = 1, forced = force and true or false }
    if type(tiers) ~= "table" then
        return result
    end
    local list = orderedTiers(tiers)
    if #list == 0 then
        return result
    end
    local counts = {}
    for _, item in ipairs(items) do
        local id = item.setID
        if id ~= nil then
            counts[id] = (counts[id] or 0) + 1
        end
    end
    local chosen
    for _, entry in ipairs(list) do
        local c = counts[entry.setID] or 0
        if not chosen or c > (counts[chosen.setID] or 0) then
            chosen = entry
        end
    end
    if not force and (counts[chosen.setID] or 0) == 0 then
        chosen = nil
    end
    local bonus = 0
    for _, entry in ipairs(list) do
        local c = counts[entry.setID] or 0
        for _, step in ipairs(entry.steps) do
            if c >= step.pieces or (force and entry == chosen) then
                bonus = bonus + (step.mult - 1)
            end
        end
    end
    if chosen then
        result.setID = chosen.setID
        result.count = counts[chosen.setID] or 0
    end
    result.mult = 1 + bonus
    return result
end

-- EffectOf(item[, effects]) -> state, entry, answer. `state` is "modelled"
-- (the table carries the item and its rule answered: `answer` is `{ stat }` or
-- `{ hps }`), "not_modelled" (the table carries it, no rule answers),
-- "unknown" (a trinket the table does not carry) or nil (a plain item).
-- `effects` defaults to the loaded table, ns.engineEffects.
function EngineScore.EffectOf(item, effects)
    if type(item) ~= "table" or not ns.EngineEffects then
        return nil
    end
    local entry = ns.EngineEffects.Classify(item.itemID, effects)
    if not entry then
        if item.slot == TRINKET then
            return "unknown"
        end
        return nil
    end
    local answer = ns.EngineEffects.Evaluate(entry)
    if answer then
        return "modelled", entry, answer
    end
    return "not_modelled", entry
end

local function named(item, entry)
    return { itemID = item.itemID, name = entry and entry.name or nil, kind = entry and entry.kind or nil }
end

-- SetValue(items, opts) -> `{ value, totals, pcts, band, tier = { setID,
-- count, mult, forced }, effects = { { itemID, name, kind, confidence, stat |
-- hps } }, effectUnmodelled = true | nil, unmodelled = { { itemID, name, kind
-- } } | nil, effectUnknown = true | nil, unknown = { { itemID } } | nil,
-- hpsNotAdded = true | nil }` (`band` is the KEY of the band scored with), or
-- nil and the reason.
--
-- `items`: ns.EngineStats vectors (with `itemID`) plus `slot`. `opts`:
--   file          the weights table (default: what Load kept)
--   spec, contentType   which content (105, "Dungeon")
--   keyLevel      the key level, resolved to a band by BandFor's rule
--   band          a band key taken as given (instead of keyLevel)
--   assumedFinish true: the parity mode - each item's sockets times the
--                 file's gem vector and the file's enchant for its slot, its
--                 own gems ignored (QE Live's rule, TopGearEngine.ts:565-634)
--   dr            "table": the file's brackets; otherwise `rating`
--   rating        function(index, value) -> (percent, secret), default
--                 ns.EngineStats.Rating - the only client call SetValue makes
--   forceTier     true: the tier bonus is on whatever the set wears
--   effects       the effects table (default: ns.engineEffects)
function EngineScore.SetValue(items, opts)
    opts = opts or {}
    local file = opts.file or EngineScore.file
    if type(file) ~= "table" then
        return nil, EngineScore.refusal or EngineScore.TEXT.broken
    end
    if type(items) ~= "table" then
        return nil, "no items"
    end
    local band, bandKey = bandOf(file, opts)
    if type(band) ~= "table" then
        return nil, bandKey
    end
    if type(band.weights) ~= "table" then
        return nil, EngineScore.NO_BAND
    end

    local totals = {}
    for _, stat in ipairs(EngineScore.STATS) do
        totals[stat] = 0
    end
    local finish = opts.assumedFinish and band.assumedFinish or nil
    local effects, unmodelled, unknown, hps = {}, nil, nil, 0
    for _, item in ipairs(items) do
        add(totals, item, 1)
        if opts.assumedFinish then
            if finish then
                add(totals, finish.gemVector, tonumber(item.sockets) or 0)
                local bySlot = finish.enchantBySlot
                add(totals, type(bySlot) == "table" and bySlot[item.slot] or nil, 1)
            end
        elseif type(item.gems) == "table" then
            for _, gem in ipairs(item.gems) do
                add(totals, gem.stats, 1)
            end
        end
        local state, entry, answer = EngineScore.EffectOf(item, opts.effects)
        if state == "modelled" and answer then
            local kept = named(item, entry)
            kept.confidence = answer.confidence
            if answer.stat then
                kept.stat = answer.stat
                add(totals, answer.stat, 1)
            else
                kept.hps = answer.hps
                hps = hps + answer.hps
            end
            effects[#effects + 1] = kept
        elseif state == "not_modelled" then
            unmodelled = unmodelled or {}
            unmodelled[#unmodelled + 1] = named(item, entry)
        elseif state == "unknown" then
            unknown = unknown or {}
            unknown[#unknown + 1] = { itemID = item.itemID }
        end
    end
    add(totals, band.assumedBuffs, 1)

    local pcts = {}
    if opts.dr == "table" then
        local dr = file.dr
        if type(dr) ~= "table" then
            return nil, "no dr table"
        end
        for _, stat in ipairs(EngineScore.RATINGS) do
            local p = EngineScore.TablePercent(totals[stat], dr[stat])
            if p == nil then
                return nil, "no dr table"
            end
            pcts[stat] = p
        end
    else
        local rate = opts.rating or (ns.EngineStats and ns.EngineStats.Rating)
        local index = ns.EngineStats and ns.EngineStats.RATING_INDEX or {}
        if type(rate) ~= "function" then
            return nil, "unrated"
        end
        for _, stat in ipairs(EngineScore.RATINGS) do
            local p, secret = rate(index[stat], totals[stat])
            if secret then
                return nil, "secret"
            end
            if type(p) ~= "number" then
                return nil, "unrated"
            end
            pcts[stat] = p
        end
    end

    local w = band.weights
    local value = (band.baseValue or 0) + (w.int or 0) * totals.int
    for _, stat in ipairs(EngineScore.RATINGS) do
        value = value + (w[stat] or 0) * pcts[stat]
    end
    -- A modelled healing effect joins the value only through the file's own
    -- exchange rate (value += hps / hpsPerValue, before the tier multiplier);
    -- with none, it is kept beside the value and not added.
    local hpsNotAdded
    if hps > 0 then
        local rate = band.hpsPerValue or file.hpsPerValue
        if type(rate) == "number" and rate > 0 then
            value = value + hps / rate
        else
            hpsNotAdded = true
        end
    end
    local tier = tierOf(items, file.tiers, opts.forceTier)
    value = value * tier.mult

    return {
        value = value,
        totals = totals,
        pcts = pcts,
        band = bandKey,
        tier = tier,
        effects = effects,
        effectUnmodelled = unmodelled and true or nil,
        unmodelled = unmodelled,
        effectUnknown = unknown and true or nil,
        unknown = unknown,
        hpsNotAdded = hpsNotAdded,
    }
end

local function slotIndices(worn, slot)
    local out = {}
    for i, item in ipairs(worn) do
        if item.slot == slot then
            out[#out + 1] = i
        end
    end
    return out
end

-- Every set the candidate makes by taking a slot it fits: either ring, either
-- trinket, the two-hander's place or both hands for a two-hander. A
-- one-hander or an off-hand beside a worn two-hander makes none: it needs a
-- partner the comparison does not add (E-0e's score.js does the same).
function EngineScore.Placements(worn, candidate)
    local out = {}
    local function swap(replaced)
        local drop = {}
        for _, i in ipairs(replaced) do
            drop[i] = true
        end
        local set = {}
        for i, item in ipairs(worn) do
            if not drop[i] then
                set[#set + 1] = item
            end
        end
        set[#set + 1] = candidate
        out[#out + 1] = { replaced = replaced, items = set }
    end
    local slot = candidate.slot
    if slot == TWO_HAND then
        local twos = slotIndices(worn, TWO_HAND)
        if #twos > 0 then
            for _, i in ipairs(twos) do
                swap({ i })
            end
        else
            local hands = {}
            for i, item in ipairs(worn) do
                if item.slot == ONE_HAND or OFF_HANDS[item.slot] then
                    hands[#hands + 1] = i
                end
            end
            swap(hands)
        end
        return out
    end
    if slot == ONE_HAND or OFF_HANDS[slot] then
        if #slotIndices(worn, TWO_HAND) > 0 then
            return out
        end
    end
    local same = slotIndices(worn, slot)
    if #same > 0 then
        for _, i in ipairs(same) do
            swap({ i })
        end
    else
        swap({})
    end
    return out
end

-- UpgradePercent(worn, candidate, opts) -> percent, detail | nil, reason.
-- `percent` = 100 * (V(best placement) - V(worn)) / V(worn), in the Upgrade
-- Finder's direction (UFImport.UPGRADE_BETTER_PERCENT_SIGN, read here, never
-- re-derived), UNSCALED; the best is the highest value over the candidate's
-- placements; `opts` as SetValue's, `forceTier` included. `detail` is
-- `{ base, value, replaced = { worn indices }, effectUnmodelled, unmodelled,
-- effectUnknown, generic, wornEffectUnmodelled }`.
--
-- The flags speak about the CHANGE, not the whole set: `effectUnmodelled` is
-- true when the candidate or an item it replaces carries an effect not
-- modelled. An unmodelled effect worn in both sets is missing from both values
-- alike, so it is carried as `wornEffectUnmodelled` and does not stop the row
-- (it still moves the denominator a little; a later issue that models it
-- moves every percent). `effectUnknown` likewise (a trinket the table does not
-- carry, on either side of the swap); `generic` when a modelled effect is on
-- either side.
function EngineScore.UpgradePercent(worn, candidate, opts)
    if type(worn) ~= "table" or type(candidate) ~= "table" then
        return nil, "no items"
    end
    local base, why = EngineScore.SetValue(worn, opts)
    if not base then
        return nil, why
    end
    if base.value == 0 then
        return nil, "zero base"
    end
    local best
    for _, placement in ipairs(EngineScore.Placements(worn, candidate)) do
        local scored, reason = EngineScore.SetValue(placement.items, opts)
        if not scored then
            return nil, reason
        end
        if not best or scored.value > best.scored.value then
            best = { scored = scored, replaced = placement.replaced }
        end
    end
    if not best then
        return nil, "not comparable"
    end
    local sign = ns.UFImport and ns.UFImport.UPGRADE_BETTER_PERCENT_SIGN or 1
    local percent = sign * 100 * (best.scored.value - base.value) / base.value
    local change = { candidate }
    for _, i in ipairs(best.replaced) do
        change[#change + 1] = worn[i]
    end
    local flags = EngineScore.ChangeEffects(change, opts and opts.effects)
    return percent,
        {
            base = base.value,
            value = best.scored.value,
            replaced = best.replaced,
            effectUnmodelled = flags.effectUnmodelled,
            unmodelled = flags.unmodelled,
            effectUnknown = flags.effectUnknown,
            generic = flags.generic,
            wornEffectUnmodelled = base.effectUnmodelled,
        }
end

-- ChangeEffects(items[, effects]) -> `{ effectUnmodelled, unmodelled = {
-- { itemID, name, kind } }, effectUnknown, generic }` over the items a swap
-- moves (the one coming in and the ones going out): what UpgradePercent and
-- the compare's Top Gear block mark a row with.
function EngineScore.ChangeEffects(items, effects)
    local out = {}
    for _, item in ipairs(items or {}) do
        local state, entry = EngineScore.EffectOf(item, effects)
        if state == "not_modelled" then
            out.effectUnmodelled = true
            out.unmodelled = out.unmodelled or {}
            out.unmodelled[#out.unmodelled + 1] = named(item, entry)
        elseif state == "unknown" then
            out.effectUnknown = true
        elseif state == "modelled" then
            out.generic = true
        end
    end
    return out
end

-- At load: read the file once. Silent unless the developer switch is on.
ns.onReady[#ns.onReady + 1] = function()
    local _, line = EngineScore.Load()
    local global = ns.db and ns.db.global
    local developer = type(global) == "table" and global.developer
    if type(developer) == "table" and developer.engine == true and line then
        ns.Log("%s", line)
    end
end
