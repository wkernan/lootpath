-- Lootpath/Modules/EngineEffects.lua (E-3a, WKE-679)
-- The effects table's reader and the five generic rules that turn an effect's
-- numbers into stats or healing. PURE: no client call, no state, nothing in
-- combat to worry about - every function answers from its arguments and the
-- table Data/EngineEffects.lua set at load. DEVELOPER-ONLY like the rest of
-- the engine (docs/ARCHITECTURE.md section 7, 2026-09-30, E-0; 2026-10-01,
-- E-3a); no UI file names it (spec/engineeffects_spec.lua reads every one).
--
-- Three states an item can be in when ns.EngineScore asks:
--   modelled      the table has it, a rule fits its kind and its params are
--                 there: the rule's stats or healing are added, confidence
--                 `generic`.
--   not modelled  the table has it, but its kind has no rule (`unique`,
--                 `unknown`, `damage_only`), its params are nil, it has no
--                 params at the item's level, or its params lack a field the
--                 rule reads (an RPPM, an overheal: no tooltip carries them):
--                 `nil, "not modelled"`; the item's stats still count and the
--                 result says what is missing.
--   unknown       the table does not have it: EngineScore scores its stats
--                 and, for a trinket, says the effect is unknown.
--
-- The rules and their public sources:
--   * RPPM (Dorovon, "rppm.md", https://gist.github.com/Dorovon/74c4fcf49ae799d92066b3266dcdcebc,
--     read 2026-10-01): "base_proc_chance = RPPM * min( time_since_last_trigger_attempt,
--     3.5 seconds ) / 60 seconds"; bad-luck protection "results in approximately
--     13.1% more procs than without BLP"; a haste-scaled RPPM is multiplied by
--     1 + haste (25% haste -> 1.25 times the base rate).
--   * A stat proc's average: amount x uptime, uptime = 1.131 x (1 - e^(-rppm x
--     duration / 60)), capped at 1. The 1.131 is the gist's 13.1%; the
--     exponential is the share of time covered by at least one proc when procs
--     arrive at a steady rate and a new proc refreshes the buff - an inference
--     (iii), not a quoted rule, and the reason this rule is `generic`.
--   * On-use average: amount x duration / cooldown (no alignment factor: none
--     is guessed here).
--   * Flat heal: heal x procs per minute x (1 - overheal) x targets, divided by
--     60 for healing per second; a cooldown instead of a rate is 60 / cooldown
--     procs per minute.
--   * Heal or absorb on use: amount x (1 - overheal) / cooldown, where for an
--     absorb `overheal` is the share wasted (absorb = face value x (1 - waste)).
-- The judgement numbers - overheal, targets - are params, never defaulted
-- here: a missing one answers `not modelled`. The memo's error bands per kind
-- (docs/OWN-ENGINE.md section 4) are estimates (iii) and are not used.

local _, ns = ...

ns.EngineEffects = {}
local EngineEffects = ns.EngineEffects

-- No client function: the module is pure (spec/engineeffects_spec.lua).
EngineEffects.FUNCTION_NAMES = {}

EngineEffects.SCHEMA = "lootpath-engine-effects"
EngineEffects.VERSION = 1

EngineEffects.NOT_MODELLED = "not modelled"
EngineEffects.GENERIC = "generic"

-- Dorovon's gist: BLP gives approximately 13.1% more procs.
EngineEffects.BLP = 1.131

-- The stats a rule may name (EngineScore.STATS).
local STATS = { int = true, haste = true, crit = true, mastery = true, vers = true, leech = true }

local function positive(x)
    return type(x) == "number" and x > 0 and x == x and x ~= math.huge
end

local function share(x)
    return type(x) == "number" and x >= 0 and x < 1
end

local function notModelled()
    return nil, EngineEffects.NOT_MODELLED
end

-- The table, or nil when it is missing or not this schema and version.
function EngineEffects.Table(effects)
    local t = effects or ns.engineEffects
    if type(t) ~= "table" or t.schema ~= EngineEffects.SCHEMA or t.version ~= EngineEffects.VERSION then
        return nil
    end
    if type(t.items) ~= "table" then
        return nil
    end
    return t
end

-- Classify(itemID[, effects]) -> the entry, or nil when the table does not
-- carry the item (or there is no table).
function EngineEffects.Classify(itemID, effects)
    local t = EngineEffects.Table(effects)
    local id = tonumber(itemID)
    if not t or not id then
        return nil
    end
    local entry = t.items[id]
    if type(entry) ~= "table" then
        return nil
    end
    return entry
end

-- PassiveStat({ stat = { <stat> = n } }) -> { stat = vector, confidence }.
function EngineEffects.PassiveStat(params)
    if type(params) ~= "table" or type(params.stat) ~= "table" then
        return notModelled()
    end
    local out, any = {}, false
    for stat, n in pairs(params.stat) do
        if not STATS[stat] or type(n) ~= "number" then
            return notModelled()
        end
        out[stat] = n
        any = true
    end
    if not any then
        return notModelled()
    end
    return { stat = out, confidence = EngineEffects.GENERIC }
end

-- The share of time a refreshing RPPM buff is up (see the header):
-- min(1, BLP x (1 - e^(-rppm x duration / 60))).
function EngineEffects.Uptime(rppm, duration)
    if not positive(rppm) or not positive(duration) then
        return nil
    end
    local up = EngineEffects.BLP * (1 - math.exp(-rppm * duration / 60))
    if up > 1 then
        up = 1
    end
    return up
end

-- StatProc({ stat, amount, rppm, duration, hasteScaled, haste }) -> average
-- stat = amount x uptime. A haste-scaled proc's RPPM is multiplied by
-- 1 + haste (haste a fraction, 0.25 for 25%); `haste` is required then.
function EngineEffects.StatProc(params)
    if type(params) ~= "table" or not STATS[params.stat] then
        return notModelled()
    end
    if not positive(params.amount) or not positive(params.rppm) or not positive(params.duration) then
        return notModelled()
    end
    local rppm = params.rppm
    if params.hasteScaled then
        if type(params.haste) ~= "number" or params.haste < 0 then
            return notModelled()
        end
        rppm = rppm * (1 + params.haste)
    end
    local uptime = EngineEffects.Uptime(rppm, params.duration)
    return { stat = { [params.stat] = params.amount * uptime }, uptime = uptime, confidence = EngineEffects.GENERIC }
end

-- StatOnUse({ stat, amount, duration, cooldown }) -> amount x duration /
-- cooldown (a duration longer than the cooldown counts as always up).
function EngineEffects.StatOnUse(params)
    if type(params) ~= "table" or not STATS[params.stat] then
        return notModelled()
    end
    if not positive(params.amount) or not positive(params.duration) or not positive(params.cooldown) then
        return notModelled()
    end
    local uptime = math.min(1, params.duration / params.cooldown)
    return { stat = { [params.stat] = params.amount * uptime }, uptime = uptime, confidence = EngineEffects.GENERIC }
end

-- FlatHeal({ heal, procsPerMinute | cooldown, overheal, targets }) -> hps =
-- heal x procs per minute x (1 - overheal) x targets / 60.
function EngineEffects.FlatHeal(params)
    if type(params) ~= "table" or not positive(params.heal) then
        return notModelled()
    end
    local ppm = params.procsPerMinute
    if ppm == nil and positive(params.cooldown) then
        ppm = 60 / params.cooldown
    end
    if not positive(ppm) or not share(params.overheal) or not positive(params.targets) then
        return notModelled()
    end
    local hps = params.heal * ppm * (1 - params.overheal) * params.targets / 60
    return { hps = hps, confidence = EngineEffects.GENERIC }
end

-- HealOnUse({ amount, cooldown, overheal }) -> hps = amount x (1 - overheal)
-- / cooldown; an absorb's `overheal` is its waste.
function EngineEffects.HealOnUse(params)
    if type(params) ~= "table" or not positive(params.amount) or not positive(params.cooldown) then
        return notModelled()
    end
    if not share(params.overheal) then
        return notModelled()
    end
    return { hps = params.amount * (1 - params.overheal) / params.cooldown, confidence = EngineEffects.GENERIC }
end

-- The rule for each kind a rule covers; every other kind is not modelled.
EngineEffects.RULES = {
    passive_stat = "PassiveStat",
    stat_proc = "StatProc",
    stat_on_use = "StatOnUse",
    flat_heal = "FlatHeal",
    heal_on_use = "HealOnUse",
}

-- ParamsAt(params, level) -> the params a rule reads at one item level, or
-- nil. Params read from a tooltip (E-3c, WKE-686) carry the level-independent
-- fields at the top and the amounts that follow the item level under
-- `byLevel[level]`, one entry per level the client was read at: the rule gets
-- the top fields with that level's fields laid over them. A level the client
-- was not read at answers nil - never the nearest level, never interpolated
-- (docs/ARCHITECTURE.md section 7, 2026-10-05, E-3c). Params without `byLevel`
-- are taken as they are.
function EngineEffects.ParamsAt(params, level)
    if type(params) ~= "table" then
        return nil
    end
    if params.byLevel == nil then
        return params
    end
    local at = type(params.byLevel) == "table" and params.byLevel[tonumber(level)] or nil
    if type(at) ~= "table" then
        return nil
    end
    local out = {}
    for k, v in pairs(params) do
        if k ~= "byLevel" then
            out[k] = v
        end
    end
    for k, v in pairs(at) do
        out[k] = v
    end
    return out
end

-- Evaluate(entry[, level]) -> { stat = vector } | { hps = n } with confidence
-- `generic`, or nil, "not modelled" (a kind no rule covers, params nil, no
-- params at this level, or params a rule refuses). `level` is the item level
-- the client read the item at (ns.EngineStats' `level`).
function EngineEffects.Evaluate(entry, level)
    if type(entry) ~= "table" then
        return notModelled()
    end
    local rule = EngineEffects.RULES[entry.kind]
    if not rule or entry.params == nil then
        return notModelled()
    end
    local params = EngineEffects.ParamsAt(entry.params, level)
    if params == nil then
        return notModelled()
    end
    return EngineEffects[rule](params)
end
