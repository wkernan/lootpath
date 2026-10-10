#!/usr/bin/env node
// The offline exhaustive check (E-1d, WKE-687). DEV ONLY - nothing here ships.
//
//   node exhaustive.js dungeon <keyLevel> | raid
//        [--mode all|kept|both]   (default both)
//        [--no-search]            (skip the Lua search; brute force only)
//        [--itemstats <capture.lua>] [--derived-at <ISO>] [--out <dir>]
//
// Enumerates EVERY wearable set of the owner's owned pieces and values each
// with lib/score.js - the Node port of EngineScore.SetValue that E-0l
// measured reproducing the game's stored rows (ARCHITECTURE.md section 9) -
// then asks the REAL search, Lootpath/Modules/EngineSearch.lua run unchanged
// in Lua 5.1 (PATH, or the gates' `lootpath-lua` Docker image), for its answer
// over the same pieces and band, and compares: the value, and the set as a
// multiset of links (so a ring or trinket pair is unordered).
//
// Why the Lua search and not a Node port: the thing under test is the code
// that ran in the client on 2026-10-05; a port could agree with the brute force
// while the shipped file did not. tools/engine/test already loads addon Lua
// the same way (tiers.test.js, cli.test.js).
//
// The pieces: every worn and bag record of the committed `capture itemstats`
// transcript (spec/fixtures/captures/Lootpath-20261001-092631.lua) - the
// client's GetItemStats for the link with enchant and gems blanked, its
// sockets, setID and GetItemUniquenessByID, as ns.EngineStats builds a vector
// (EngineStats.lua:392-440). Every inventory snapshot from 2026-10-01 20:09 to
// 2026-10-05 16:31 holds the same 40 links (test/exhaustive.test.js holds it
// on the committed 2026-10-02 transcript). The bank was never open in those
// snapshots, so a bank piece is not in them and not here.
//
// The weights: the dev file the game ran - the fit command in README.md, its
// four transcripts and eight exports, `--derived-at 2026-10-02T02:21:19.971Z`
// (the stored compare header), refitted here into a temp dir.
//
// The rules, ported from EngineSearch.lua and cited by line:
//   positions   ten single slots, the ring pair, the trinket pair, the weapon
//               choice (:88-94, coordinatesFor :664-713)
//   pairs       every two pieces of a pool but two copies of one unique
//               itemID (sameUnique :597-604, pairOptions :608-625)
//   weapons     each one-hander with each off-hand (or alone when none), an
//               off-hand alone when no one-hander, each two-hander
//               (weaponOptions :627-651); Shield joins the off-hand pool (:97-100)
//   unique      one copy per unique itemID, `max` (1) per limit category
//               (UniqueOK :154-174); the other three hooks pass everything
//               (:179-194)
//   outclass    the kept pool (Candidates :444-519, outclasses :372-389,
//               canOutclass :391-397, canBeDropped :399-401, wearableCount
//               :405-419)
//   masks       a set's mask is the tier key of each tier slot's piece
//               (Masks :552-588, tierKeyOf :347-353); the brute force keeps
//               the optimum per mask so each Ascend can be held to it
//   value       SetValue with the parity finish and WITHOUT forceTier
//               (scoreOptsOf :237-250): each piece's sockets x the band's
//               gemVector and its slot's enchant (effective :324-343), the
//               band's assumedBuffs, the dr table, the tier counted
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { parseSavedVariables } = require('../companion/lib/lua-savedvariables');
const { itemStatsRecords, strippedKey } = require('./lib/stats');
const { setValue, STATS } = require('./lib/score');
const { DEFAULT_DR } = require('./lib/dr');
const { buildTable, luaValue } = require('./lib/luaout');
const fitWeights = require('./fit-weights');

const REPO = path.join(__dirname, '..', '..');
const CAPTURES = path.join(REPO, 'spec', 'fixtures', 'captures');
const DEFAULT_ITEMSTATS = path.join(CAPTURES, 'Lootpath-20261001-092631.lua');
// The fit command in README.md, and the derivedAt the game's compare stored.
const FIT_STATS = ['Lootpath-20260915-162015.lua', 'Lootpath-20260916-152428.lua', 'Lootpath-20261001-092631.lua', 'Lootpath-20261001-200927.lua'].map((f) => path.join(CAPTURES, f));
const FIT_KEY_LEVELS = '1=2,2=4,4=6,6=8,7=10';
const FIT_EXPORTS = path.join(REPO, 'spec', 'fixtures', 'qe');
const GAME_DERIVED_AT = '2026-10-02T02:21:19.971Z';
const EFFECTS_FILE = path.join(REPO, 'Lootpath', 'Data', 'EngineEffects.lua');

// EngineSearch's vocabulary (EngineSearch.lua:83-94).
const EPSILON = 1e-12;
const SINGLES = ['Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet'];
const TIER_SLOTS = ['Head', 'Shoulder', 'Chest', 'Hands', 'Legs'];
const PAIRS = ['Finger', 'Trinket'];
const ONE_HAND = '1H Weapon';
const OFF_HAND = 'Offhand';
const TWO_HAND = '2H Weapon';
const POOL_OF_SLOT = { Shield: 'Offhand', Offhand: 'Offhand' };
// Inventory.SLOT_BY_EQUIPLOC (Inventory.lua:25-47).
const SLOT_BY_EQUIPLOC = {
    INVTYPE_HEAD: 'Head',
    INVTYPE_NECK: 'Neck',
    INVTYPE_SHOULDER: 'Shoulder',
    INVTYPE_CLOAK: 'Back',
    INVTYPE_CHEST: 'Chest',
    INVTYPE_ROBE: 'Chest',
    INVTYPE_WRIST: 'Wrist',
    INVTYPE_HAND: 'Hands',
    INVTYPE_WAIST: 'Waist',
    INVTYPE_LEGS: 'Legs',
    INVTYPE_FEET: 'Feet',
    INVTYPE_FINGER: 'Finger',
    INVTYPE_TRINKET: 'Trinket',
    INVTYPE_WEAPON: '1H Weapon',
    INVTYPE_WEAPONMAINHAND: '1H Weapon',
    INVTYPE_WEAPONOFFHAND: '1H Weapon',
    INVTYPE_RANGEDRIGHT: '1H Weapon',
    INVTYPE_2HWEAPON: '2H Weapon',
    INVTYPE_RANGED: '2H Weapon',
    INVTYPE_HOLDABLE: 'Offhand',
    INVTYPE_SHIELD: 'Shield',
};

const better = (v, than) => v > than + Math.abs(than) * EPSILON;
const probe = (p) => (p && typeof p === 'object' ? p : {});

// --- the pieces ------------------------------------------------------------

// Every worn and bag record of an itemstats transcript as an EngineStats
// vector (the six stats at the top level, as SetValue reads them) plus slot,
// key, link, location, name and level, in the transcript's order.
function piecesFromItemStats(file) {
    const caps = parseSavedVariables(fs.readFileSync(file, 'utf8')).LootpathDB.global.captures;
    const out = [];
    for (const rec of itemStatsRecords(caps)) {
        const it = rec.item;
        if (it.source !== 'worn' && it.source !== 'bag') continue;
        const slot = SLOT_BY_EQUIPLOC[it.info && it.info.itemEquipLoc];
        if (!slot) continue;
        const raw = rec.raw || {};
        const stats = {
            int: raw.ITEM_MOD_INTELLECT_SHORT || 0,
            haste: raw.ITEM_MOD_HASTE_RATING_SHORT || 0,
            crit: raw.ITEM_MOD_CRIT_RATING_SHORT || 0,
            mastery: raw.ITEM_MOD_MASTERY_RATING_SHORT || 0,
            vers: raw.ITEM_MOD_VERSATILITY || 0,
            leech: raw.ITEM_MOD_CR_LIFESTEAL_SHORT || 0,
        };
        // GetItemUniquenessByID -> isUnique, categoryName, categoryCount,
        // categoryID; a vector carries `uniqueness` only when one is set
        // (EngineStats.lua:425-440).
        const u = probe(it.uniquenessByID);
        const isUnique = u[1] === true;
        const category = typeof u[4] === 'number' ? u[4] : undefined;
        const max = typeof u[3] === 'number' ? u[3] : undefined;
        const uniqueness = isUnique || category !== undefined || max !== undefined ? { isUnique, category, max } : undefined;
        const setID = it.info && typeof it.info.setID === 'number' ? it.info.setID : undefined;
        out.push({
            idx: out.length + 1,
            itemID: rec.itemID,
            slot,
            ...stats,
            sockets: Number(probe(it.numSockets)[1]) || 0,
            setID,
            uniqueness,
            key: strippedKey(rec.link),
            link: rec.link,
            name: (String(rec.link).match(/\|h\[(.*)\]\|h/) || [])[1] || null,
            level: rec.level,
            location: it.source === 'worn' ? 'equipped' : 'bag',
        });
    }
    return out;
}

// The itemIDs the effects table classifies (Data/EngineEffects.lua `items`).
function effectIDs(file) {
    const text = fs.readFileSync(file || EFFECTS_FILE, 'utf8');
    const body = text.slice(text.indexOf('items = {'));
    const ids = new Set();
    for (const m of body.matchAll(/^\s*\[(\d+)\] = \{/gm)) ids.add(Number(m[1]));
    return ids;
}

// --- the weights -----------------------------------------------------------

// Refit the dev weights the game ran into `dir`; returns the file as a JS
// table (luaout's buildTable, the table the Lua file renders) and its path.
function gameWeights(opts) {
    const o = opts || {};
    const dir = o.dir || fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e1d-weights-'));
    const args = ['--out', dir, '--derived-at', o.derivedAt || GAME_DERIVED_AT, '--resamples', '0', '--key-levels', FIT_KEY_LEVELS];
    for (const s of FIT_STATS) args.push('--stats', s);
    args.push(FIT_EXPORTS);
    const r = fitWeights.run(args, () => {});
    const meta = { patch: '-', derivedAt: o.derivedAt || GAME_DERIVED_AT, documents: [], assumedFinish: {}, assumedBuffs: {}, dr: DEFAULT_DR, tiers: r.fits[0].tiers };
    const file = buildTable(
        r.fits.map((fit) => ({ fit, band: fit.band })),
        meta
    );
    return { file, luaPath: r.luaPath, derivedAt: meta.derivedAt };
}

// EngineScore.BandFor (EngineScore.lua:228-263): the exact key level, else
// the highest "<n>+" at or under it, else the content type's only band.
function bandFor(file, contentType, keyLevel) {
    const resto = file.specs instanceof Map ? file.specs.get(105) : file.specs[105];
    const bands = resto && resto[contentType] && resto[contentType].bands;
    if (!bands) return null;
    const level = Number.isInteger(keyLevel) && keyLevel >= 0 ? keyLevel : null;
    if (level !== null && contentType !== 'Raid') {
        if (bands[String(level)]) return { band: bands[String(level)], key: String(level) };
        let bestKey = null;
        let bestFrom = null;
        for (const key of Object.keys(bands)) {
            const m = key.match(/^(\d+)\+$/);
            const from = m ? Number(m[1]) : null;
            if (from !== null && from <= level && (bestFrom === null || from > bestFrom)) {
                bestKey = key;
                bestFrom = from;
            }
        }
        if (bestKey) return { band: bands[bestKey], key: bestKey };
    }
    const keys = Object.keys(bands);
    return keys.length === 1 ? { band: bands[keys[0]], key: keys[0] } : null;
}

// The file's tiers (`Map setID -> Map pieces -> { mult }`, or the plain-object
// form) in score.js's counted shape. score.js counts the pieces of every listed
// set together, which is EngineScore's tierOf only when the file carries ONE
// set at 2 and 4 pieces: anything else is refused, not approximated.
function scoreTiers(tiers) {
    const entries = tiers instanceof Map ? [...tiers.entries()] : Object.entries(tiers || {}).map(([k, v]) => [Number(k), v]);
    if (entries.length !== 1) throw new Error(`score.js counts one tier set; the file carries ${entries.length}`);
    const [setID, steps] = entries[0];
    const get = (n) => (steps instanceof Map ? steps.get(n) : steps[n]);
    const keys = steps instanceof Map ? [...steps.keys()] : Object.keys(steps).map(Number);
    if (keys.length !== 2 || !get(2) || !get(4)) throw new Error(`tier set ${setID}: score.js reads exactly a 2- and a 4-piece bonus`);
    return { setIDs: [setID], twoPiece: get(2).mult - 1, fourPiece: get(4).mult - 1, forceTier: false };
}

function tierKeyOf(piece, tiers) {
    if (piece.setID === undefined) return false;
    const has = tiers instanceof Map ? tiers.has(piece.setID) : tiers && tiers[piece.setID] !== undefined;
    return has ? piece.setID : false;
}

// --- the value -------------------------------------------------------------

// What one piece adds to the totals in the parity mode (effective, :324-343).
function effective(piece, band) {
    const v = {};
    for (const s of STATS) v[s] = piece[s] || 0;
    const finish = band.assumedFinish || {};
    for (const s of STATS) v[s] += ((finish.gemVector && finish.gemVector[s]) || 0) * (piece.sockets || 0);
    const enchant = finish.enchantBySlot && finish.enchantBySlot[piece.slot];
    for (const s of STATS) v[s] += (enchant && enchant[s]) || 0;
    return v;
}

// A scorer over the pieces: value(list of cands) = score.js setValue with the
// band's model, the tier counted.
function scorer(file, band) {
    const model = {
        baseValue: band.baseValue || 0,
        weights: band.weights,
        assumedFinish: band.assumedBuffs && Object.keys(band.assumedBuffs).length ? band.assumedBuffs : null,
        dr: file.dr || DEFAULT_DR,
        tiers: scoreTiers(file.tiers),
    };
    return (items) => setValue(items, model);
}

// --- candidates and the outclass rule ---------------------------------------

function cands(pieces, file, band) {
    return pieces.map((p) => {
        const eff = effective(p, band);
        return { piece: p, order: p.idx, eff, tier: tierKeyOf(p, file.tiers), scoring: { stats: eff, setId: p.setID } };
    });
}

function signsOf(weights) {
    const signs = {};
    for (const s of STATS) {
        const x = Number(weights[s]) || 0;
        signs[s] = x > 0 ? 1 : x < 0 ? -1 : 0;
    }
    return signs;
}

function outclasses(a, b, signs) {
    if (a.tier !== b.tier) return false;
    let strictly = false;
    for (const s of STATS) {
        if (signs[s] === 0) continue;
        const da = a.eff[s] * signs[s];
        const db = b.eff[s] * signs[s];
        if (da < db) return false;
        if (da > db) strictly = true;
    }
    return strictly || a.order < b.order;
}

const canOutclass = (c) => !(c.piece.uniqueness && c.piece.uniqueness.category !== undefined);

// EngineScore.EffectOf is nil only for a piece the table does not carry that is
// not a trinket (EngineScore.lua:399-415): only such a piece can be dropped.
const canBeDropped = (c, effects) => !effects.has(c.piece.itemID) && c.piece.slot !== 'Trinket';

function wearableCount(list) {
    let n = 0;
    const seen = new Set();
    for (const c of list) {
        const u = c.piece.uniqueness;
        if (u && u.isUnique) {
            if (!seen.has(c.piece.itemID)) {
                seen.add(c.piece.itemID);
                n += 1;
            }
        } else n += 1;
    }
    return n;
}

// Candidates' pools: every piece (`prune` false) or the kept ones.
function pools(all, band, effects, prune) {
    const signs = signsOf(band.weights);
    const byPool = {};
    for (const c of all) {
        c.signed = STATS.reduce((s, k) => s + signs[k] * c.eff[k], 0);
        const pool = POOL_OF_SLOT[c.piece.slot] || c.piece.slot;
        (byPool[pool] = byPool[pool] || []).push(c);
    }
    const out = {};
    const dropped = [];
    for (const [pool, list] of Object.entries(byPool)) {
        list.sort((a, b) => (a.signed !== b.signed ? b.signed - a.signed : a.order - b.order));
        const need = pool === 'Finger' || pool === 'Trinket' ? 2 : 1;
        const keep = [];
        for (const c of list) {
            let drop = false;
            if (prune && canBeDropped(c, effects)) {
                const over = keep.filter((k) => canOutclass(k) && outclasses(k, c, signs));
                drop = wearableCount(over) >= need;
            }
            (drop ? dropped : keep).push(c);
        }
        keep.sort((a, b) => a.order - b.order);
        out[pool] = keep;
    }
    dropped.sort((a, b) => a.order - b.order);
    return { pools: out, dropped };
}

// --- the coordinates -------------------------------------------------------

const sameUnique = (a, b) => a.piece.itemID === b.piece.itemID && a.piece.uniqueness && a.piece.uniqueness.isUnique && b.piece.uniqueness && b.piece.uniqueness.isUnique;

function pairOptions(pool) {
    const out = [];
    for (let i = 0; i < pool.length - 1; i++) for (let j = i + 1; j < pool.length; j++) if (!sameUnique(pool[i], pool[j])) out.push([pool[i], pool[j]]);
    if (!out.length) for (const c of pool) out.push([c]);
    return out;
}

function weaponOptions(p) {
    const ones = p[ONE_HAND] || [];
    const offs = p[OFF_HAND] || [];
    const twos = p[TWO_HAND] || [];
    const out = [];
    for (const main of ones) {
        if (offs.length) for (const off of offs) out.push([main, off]);
        else out.push([main]);
    }
    if (!ones.length) for (const off of offs) out.push([off]);
    for (const two of twos) out.push([two]);
    return out;
}

function coordinates(p) {
    const coords = [];
    for (const slot of SINGLES) if (p[slot] && p[slot].length) coords.push({ name: slot, options: p[slot].map((c) => [c]) });
    for (const pool of PAIRS) if (p[pool] && p[pool].length) coords.push({ name: pool, options: pairOptions(p[pool]) });
    const weapons = weaponOptions(p);
    if (weapons.length) coords.push({ name: 'Weapon', options: weapons });
    return coords;
}

// UniqueOK (EngineSearch.lua:154-174) over cands.
function uniqueOK(list) {
    const byID = new Map();
    const byCategory = new Map();
    for (const c of list) {
        const u = c.piece.uniqueness;
        if (!u) continue;
        if (u.isUnique && c.piece.itemID) {
            const n = (byID.get(c.piece.itemID) || 0) + 1;
            if (n > 1) return false;
            byID.set(c.piece.itemID, n);
        }
        if (u.category !== undefined) {
            const n = (byCategory.get(u.category) || 0) + 1;
            if (n > (Number(u.max) || 1)) return false;
            byCategory.set(u.category, n);
        }
    }
    return true;
}

// Every set over the coordinates, valued; the best overall, the best per
// mask (the tier key each tier slot's piece carries, Masks :552-588) and the
// best few distinct values.
function enumerate(coords, value, opts) {
    const o = opts || {};
    const n = coords.length;
    let sets = 1;
    for (const c of coords) sets *= c.options.length;
    // Per coordinate, per option: the mask label it contributes ('' off the
    // tier slots) and the scoring vectors, built once.
    const label = coords.map((c) => c.options.map((opt) => (TIER_SLOTS.includes(c.name) ? `${c.name}=${opt[0].tier === false ? 'none' : opt[0].tier}` : '')));
    const scoring = coords.map((c) => c.options.map((opt) => opt.map((x) => x.scoring)));
    const index = new Array(n).fill(0);
    const list = [];
    const scored = [];
    let best = null;
    const perMask = new Map();
    let feasible = 0;
    let top = [];
    const TOP = o.top || 5;
    for (;;) {
        list.length = 0;
        scored.length = 0;
        for (let i = 0; i < n; i++) {
            const opt = coords[i].options[index[i]];
            const sc = scoring[i][index[i]];
            for (let j = 0; j < opt.length; j++) {
                list.push(opt[j]);
                scored.push(sc[j]);
            }
        }
        if (uniqueOK(list)) {
            feasible += 1;
            const v = value(scored);
            if (!best || better(v, best.value)) best = { value: v, items: list.slice() };
            let mk = '';
            for (let i = 0; i < n; i++) {
                const l = label[i][index[i]];
                if (l) mk = mk ? `${mk},${l}` : l;
            }
            const held = perMask.get(mk);
            if (!held || better(v, held.value)) perMask.set(mk, { value: v, items: list.slice() });
            if (top.length < TOP || v > top[top.length - 1]) {
                if (!top.some((t) => Math.abs(t - v) <= Math.abs(v) * 1e-12)) {
                    top.push(v);
                    top.sort((a, b) => b - a);
                    top = top.slice(0, TOP);
                }
            }
        }
        let i = n - 1;
        while (i >= 0) {
            index[i] += 1;
            if (index[i] < coords[i].options.length) break;
            index[i] = 0;
            i -= 1;
        }
        if (i < 0) break;
    }
    return { sets, feasible, best, perMask, top };
}

// --- the Lua search --------------------------------------------------------

// The real EngineSearch, its EngineScore and EngineEffects, loaded the way the
// addon loads them. The effects table is the shipped one with every `params`
// taken out - classified, nothing modelled, as the game ran it on 2026-10-05 -
// so the value is the stats alone on both sides. Prints the best, its items,
// the drop, every mask's Ascend, and the worn set's value.
const LUA_SEARCH = `
local repo, weightsPath, itemsPath, contentType, keyLevel, mode = arg[1], arg[2], arg[3], arg[4], tonumber(arg[5]), arg[6]
local ns = { onReady = {} }
ns.Safe = function(v) return v, false end
ns.Log = function() end
InCombatLockdown = function() return false end
assert(loadfile(weightsPath))("Lootpath", ns)
GetBuildInfo = function() return ns.engineWeights.patch end
assert(loadfile(repo .. "/Lootpath/Data/EngineEffects.lua"))("Lootpath", ns)
assert(loadfile(repo .. "/Lootpath/Modules/EngineEffects.lua"))("Lootpath", ns)
assert(loadfile(repo .. "/Lootpath/Modules/EngineScore.lua"))("Lootpath", ns)
ns.EngineCompare = { Enabled = function() return true end }
assert(loadfile(repo .. "/Lootpath/Modules/EngineSearch.lua"))("Lootpath", ns)
local file = ns.engineWeights
local effects = { schema = ns.engineEffects.schema, version = ns.engineEffects.version, items = {} }
for id, entry in pairs(ns.engineEffects.items) do
    local copy = {}
    for k, v in pairs(entry) do copy[k] = v end
    copy.params = nil
    effects.items[id] = copy
end
local items = assert(loadfile(itemsPath))()
local opts = { contentType = contentType, keyLevel = keyLevel, dr = "table", effects = effects }
local function idx(list)
    local out = {}
    for _, item in ipairs(list) do out[#out + 1] = item.idx end
    table.sort(out)
    return table.concat(out, ",")
end
local function maskOf(mask)
    local out = {}
    for _, slot in ipairs(ns.EngineSearch.TIER_SLOTS) do
        local v = mask and mask[slot]
        if v ~= nil then out[#out + 1] = slot .. "=" .. (v == false and "none" or tostring(v)) end
    end
    return table.concat(out, ",")
end
if mode == "brute" or mode == "both" then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.cap = 10000000
    local r = assert(ns.EngineSearch.BruteForce(items, file, o))
    print(string.format("brute %.17g %d %d %s", r.value, r.sets, r.evaluations, idx(r.items)))
    if mode == "brute" then return end
end
local t0 = os.clock()
local best = assert(ns.EngineSearch.Best(items, file, opts))
local ms = (os.clock() - t0) * 1000
local worn = {}
for _, item in ipairs(items) do if item.location == "equipped" then worn[#worn + 1] = item end end
local wornScored = assert(ns.EngineScore.SetValue(worn, { file = file, contentType = contentType, keyLevel = keyLevel, assumedFinish = true, forceTier = false, dr = "table", effects = effects }))
print(string.format("best %.17g %d %d %d %d %s %.3f", best.value, best.evaluations, best.ascentEvaluations, best.masks, best.kept, tostring(best.band), ms))
print("items " .. idx(best.items))
print("mask " .. maskOf(best.maskUsed))
print("dropped " .. idx((function() local l = {} for _, c in ipairs(best.dropped) do l[#l + 1] = c.item end return l end)()))
print(string.format("worn %.17g", wornScored.value))
local c = ns.EngineSearch.Candidates(items, file, opts)
local lone = ns.EngineSearch.Ascend(c.pools, nil, file, nil, opts)
if lone then print(string.format("lone %.17g %s", lone.value, idx(lone.items))) end
for _, mask in ipairs(ns.EngineSearch.Masks(c.pools, file)) do
    local r, why = ns.EngineSearch.Ascend(c.pools, mask, file, nil, opts)
    if r then
        print(string.format("ascend %s %.17g %d %s", maskOf(mask), r.value, r.sweeps, idx(r.items)))
    else
        print(string.format("ascend %s none %s", maskOf(mask), tostring(why)))
    end
end
`;

// How to run Lua 5.1: PATH, else the gates' Docker image (as tiers.test.js).
function findLua() {
    const local = ['lua5.1', 'lua'].find((exe) => spawnSync(exe, ['-v'], { encoding: 'utf8' }).status === 0);
    if (local) return (dir, script, args) => spawnSync(local, [path.join(dir, script), REPO, ...args.map((a) => (a.startsWith('@') ? path.join(dir, a.slice(1)) : a))], { encoding: 'utf8', maxBuffer: 1 << 26 });
    const img = spawnSync('docker', ['image', 'inspect', 'lootpath-lua'], { encoding: 'utf8' });
    if (img.status !== 0) return null;
    return (dir, script, args) =>
        spawnSync('docker', ['run', '--rm', '-v', `${REPO}:/repo:ro`, '-v', `${dir}:/t`, 'lootpath-lua', 'lua', `/t/${script}`, '/repo', ...args.map((a) => (a.startsWith('@') ? `/t/${a.slice(1)}` : a))], { encoding: 'utf8', maxBuffer: 1 << 26 });
}

// The pieces as a Lua chunk returning the list (the vector fields only).
function luaItems(pieces) {
    const plain = pieces.map((p) => {
        const o = { idx: p.idx, itemID: p.itemID, slot: p.slot, sockets: p.sockets, gems: [], ready: true };
        for (const s of STATS) o[s] = p[s] || 0;
        if (p.setID !== undefined) o.setID = p.setID;
        if (p.uniqueness) {
            o.uniqueness = { isUnique: !!p.uniqueness.isUnique };
            if (p.uniqueness.category !== undefined) o.uniqueness.category = p.uniqueness.category;
            if (p.uniqueness.max !== undefined) o.uniqueness.max = p.uniqueness.max;
        }
        if (p.location) o.location = p.location;
        if (p.key) o.key = p.key;
        return o;
    });
    return `return ${luaValue(plain, 0)}\n`;
}

// runLua(pieces, luaPath, contentType, keyLevel, mode) -> parsed lines, or
// null when there is no Lua 5.1 to run.
function runLua(pieces, luaPath, contentType, keyLevel, mode) {
    const lua = findLua();
    if (!lua) return null;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e1d-lua-'));
    fs.writeFileSync(path.join(dir, 'search.lua'), LUA_SEARCH);
    fs.writeFileSync(path.join(dir, 'items.lua'), luaItems(pieces));
    fs.copyFileSync(luaPath, path.join(dir, 'weights.lua'));
    const t0 = process.hrtime.bigint();
    const res = lua(dir, 'search.lua', ['@weights.lua', '@items.lua', contentType, String(keyLevel === null || keyLevel === undefined ? '' : keyLevel), mode || 'search']);
    const wallMs = Number(process.hrtime.bigint() - t0) / 1e6;
    if (res.status !== 0) throw new Error(`lua search failed: ${res.stderr || res.stdout}`);
    return parseLua(res.stdout, wallMs);
}

const idxList = (s) => (s ? s.split(',').filter(Boolean).map(Number) : []);

function parseLua(stdout, wallMs) {
    const out = { masks: [], wallMs };
    for (const line of stdout.trim().split(/\r?\n/)) {
        const w = line.trim().split(' ');
        if (w[0] === 'best') out.best = { value: Number(w[1]), evaluations: Number(w[2]), ascentEvaluations: Number(w[3]), masks: Number(w[4]), kept: Number(w[5]), band: w[6], ms: Number(w[7]) };
        else if (w[0] === 'items') out.items = idxList(w[1]);
        else if (w[0] === 'mask') out.maskUsed = w[1] || '';
        else if (w[0] === 'dropped') out.dropped = idxList(w[1]);
        else if (w[0] === 'worn') out.worn = Number(w[1]);
        else if (w[0] === 'lone') out.lone = { value: Number(w[1]), items: idxList(w[2]) };
        else if (w[0] === 'ascend') out.masks.push(w[2] === 'none' ? { mask: w[1], value: null, why: w.slice(3).join(' ') } : { mask: w[1], value: Number(w[2]), sweeps: Number(w[3]), items: idxList(w[4]) });
        else if (w[0] === 'brute') out.brute = { value: Number(w[1]), sets: Number(w[2]), evaluations: Number(w[3]), items: idxList(w[4]) };
    }
    return out;
}

// --- the comparison --------------------------------------------------------

// A set as the multiset of its pieces' links (idx when a piece has no link),
// so two copies of one link and a pair in either order are one set.
function setKey(idxs, byIdx) {
    return idxs
        .map((i) => (byIdx.get(i) && byIdx.get(i).key) || `#${i}`)
        .sort()
        .join(' | ');
}

const close = (a, b) => Math.abs(a - b) <= Math.max(Math.abs(a), Math.abs(b)) * 1e-9;

// compare(brute, search, pieces) -> { equal, valueEqual, setEqual, delta }.
function compare(bruteBest, searchValue, searchIdx, pieces) {
    const byIdx = new Map(pieces.map((p) => [p.idx, p]));
    const bruteIdx = bruteBest.items.map((c) => c.piece.idx);
    const valueEqual = close(bruteBest.value, searchValue);
    const setEqual = setKey(bruteIdx, byIdx) === setKey(searchIdx, byIdx);
    return { equal: valueEqual && setEqual, valueEqual, setEqual, delta: bruteBest.value - searchValue };
}

// The most rating any set can carry, per stat (each coordinate's largest
// option summed), beside the first DR bracket: below it the value is linear
// in that stat for every set.
function headroom(coords, dr) {
    const out = {};
    for (const s of ['haste', 'crit', 'mastery', 'vers', 'leech']) {
        let max = 0;
        for (const c of coords) max += Math.max(...c.options.map((o) => o.reduce((a, x) => a + x.eff[s], 0)));
        out[s] = { max, firstBracket: dr[s].brackets[0].from };
    }
    return out;
}

// --- one run ---------------------------------------------------------------

function check(o) {
    const pieces = o.pieces;
    const { file, luaPath } = o.weights;
    const found = bandFor(file, o.contentType, o.keyLevel);
    if (!found) throw new Error(`no band for ${o.contentType} ${o.keyLevel}`);
    const { band, key } = found;
    const value = scorer(file, band);
    const effects = o.effects || effectIDs();
    const result = { contentType: o.contentType, keyLevel: o.keyLevel, band: key, derivedAt: file.derivedAt, pieces: pieces.length, modes: {} };
    for (const mode of o.modes || ['all', 'kept']) {
        const all = cands(pieces, file, band);
        const p = pools(all, band, effects, mode === 'kept');
        const coords = coordinates(p.pools);
        if (mode === 'all') result.headroom = headroom(coords, file.dr || DEFAULT_DR);
        const t0 = process.hrtime.bigint();
        const e = enumerate(coords, value);
        const ms = Number(process.hrtime.bigint() - t0) / 1e6;
        result.modes[mode] = {
            sets: e.sets,
            feasible: e.feasible,
            ms,
            best: e.best,
            perMask: e.perMask,
            top: e.top,
            dropped: p.dropped.map((c) => c.piece.idx),
            pools: Object.fromEntries(Object.entries(p.pools).map(([k, v]) => [k, v.length])),
        };
    }
    const worn = cands(
        pieces.filter((p) => p.location === 'equipped'),
        file,
        band
    );
    result.worn = value(worn.map((c) => c.scoring));
    if (o.search !== false) {
        const lua = runLua(pieces, luaPath, o.contentType, o.keyLevel);
        result.search = lua;
        if (lua) {
            const ref = (result.modes.all || result.modes.kept).best;
            result.compare = compare(ref, lua.best.value, lua.items, pieces);
            result.maskCompare = [];
            const perMask = (result.modes.all || result.modes.kept).perMask;
            for (const m of lua.masks) {
                const b = perMask.get(m.mask);
                result.maskCompare.push({ mask: m.mask, brute: b ? b.value : null, ascend: m.value, sweeps: m.sweeps, ...(b && m.value !== null ? compare(b, m.value, m.items, pieces) : { equal: !b && m.value === null }) });
            }
        }
    }
    return result;
}

// --- the command -----------------------------------------------------------

function parseArgs(argv) {
    const o = { contentType: null, keyLevel: null, modes: ['all', 'kept'], search: true, itemstats: DEFAULT_ITEMSTATS, derivedAt: GAME_DERIVED_AT, out: path.join(__dirname, 'out') };
    const rest = [];
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        const next = () => {
            if (i + 1 >= argv.length) throw new Error(`${a} needs a value`);
            i += 1;
            return argv[i];
        };
        if (a === '--mode') {
            const m = next();
            o.modes = m === 'both' ? ['all', 'kept'] : [m];
            if (!o.modes.every((x) => x === 'all' || x === 'kept')) throw new Error('--mode is all, kept or both');
        } else if (a === '--no-search') o.search = false;
        else if (a === '--itemstats') o.itemstats = next();
        else if (a === '--derived-at') o.derivedAt = next();
        else if (a === '--out') o.out = next();
        else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
        else rest.push(a);
    }
    if (rest[0] === 'dungeon' && rest.length === 2 && /^\d+$/.test(rest[1])) {
        o.contentType = 'Dungeon';
        o.keyLevel = Number(rest[1]);
    } else if (rest[0] === 'raid' && rest.length === 1) o.contentType = 'Raid';
    else throw new Error('usage: node exhaustive.js dungeon <keyLevel> | raid [--mode all|kept|both] [--no-search]');
    return o;
}

const f = (x, d) => (typeof x === 'number' ? x.toFixed(d === undefined ? 6 : d) : '-');

function describe(idxs, pieces) {
    const byIdx = new Map(pieces.map((p) => [p.idx, p]));
    return idxs
        .map((i) => byIdx.get(i))
        .sort((a, b) => a.idx - b.idx)
        .map((p) => `${p.slot} ${p.itemID}@${p.level}${p.location === 'equipped' ? ' (worn)' : ''}`);
}

function run(argv, log) {
    const say = log || console.log;
    const o = parseArgs(argv);
    const pieces = piecesFromItemStats(o.itemstats);
    const weights = gameWeights({ derivedAt: o.derivedAt });
    const r = check({ pieces, weights, contentType: o.contentType, keyLevel: o.keyLevel, modes: o.modes, search: o.search });
    say(`exhaustive: ${r.contentType}${r.keyLevel !== null ? ` +${r.keyLevel}` : ''}, band ${r.band}, weights derived ${r.derivedAt}; ${pieces.length} pieces from ${path.basename(o.itemstats)}`);
    say(`worn set ${f(r.worn)}`);
    for (const [mode, m] of Object.entries(r.modes)) {
        say(`${mode === 'all' ? 'every piece' : 'kept pool'}: ${m.sets} sets (${m.feasible} feasible), ${f(m.ms, 0)} ms; dropped ${m.dropped.length}${m.dropped.length ? ` (${describe(m.dropped, pieces).join('; ')})` : ''}`);
        say(`  optimum ${f(m.best.value)}; next distinct values ${m.top.slice(1).map((v) => f(v)).join(', ')}`);
        say(`  ${describe(m.best.items.map((c) => c.piece.idx), pieces).join('; ')}`);
    }
    if (r.headroom) say(`most rating any set can carry vs the first DR bracket: ${Object.entries(r.headroom).map(([k, h]) => `${k} ${h.max}/${h.firstBracket}`).join(', ')}`);
    if (r.modes.all && r.modes.kept) say(`outclass rule: every-piece optimum ${f(r.modes.all.best.value)} vs kept-pool ${f(r.modes.kept.best.value)} - ${close(r.modes.all.best.value, r.modes.kept.best.value) ? 'equal' : 'DIFFERENT'}`);
    if (o.search && !r.search) say('search: no Lua 5.1 on PATH and no lootpath-lua image - not run');
    if (r.search) {
        const s = r.search;
        say(`search (EngineSearch.lua in Lua 5.1): ${f(s.best.value)}, ${s.best.evaluations} set values (${s.best.ascentEvaluations} ascent) over ${s.best.masks} masks, kept ${s.best.kept}, dropped ${s.dropped.length}; ${f(s.best.ms, 1)} ms in Lua, ${f(s.wallMs, 0)} ms with start-up`);
        say(`  ${describe(s.items, pieces).join('; ')}`);
        say(`  worn set in Lua ${f(s.worn)}${close(s.worn, r.worn) ? ' (= score.js)' : ` (score.js ${f(r.worn)})`}`);
        const c = r.compare;
        say(`search vs brute force: ${c.equal ? 'EQUAL' : 'DIFFERENT'} (value ${c.valueEqual ? 'equal' : 'differs'}, set ${c.setEqual ? 'equal' : 'differs'}, brute - search ${c.delta.toExponential(3)})`);
        const missed = r.maskCompare.filter((m) => !m.equal);
        say(`per mask: ${r.maskCompare.length - missed.length} of ${r.maskCompare.length} ascents reach their mask's brute-force optimum`);
        for (const m of missed) say(`  ${m.mask}: brute ${f(m.brute)}, ascend ${f(m.ascend)} after ${m.sweeps} sweep(s)`);
    }
    fs.mkdirSync(o.out, { recursive: true });
    const name = `exhaustive-${r.contentType === 'Raid' ? 'raid' : `dungeon-${r.keyLevel}`}.json`;
    const json = {
        ...r,
        modes: Object.fromEntries(
            Object.entries(r.modes).map(([k, m]) => [
                k,
                { ...m, best: { value: m.best.value, items: m.best.items.map((c) => c.piece.idx) }, perMask: Object.fromEntries([...m.perMask].map(([mk, v]) => [mk, { value: v.value, items: v.items.map((c) => c.piece.idx) }])) },
            ])
        ),
        piecesList: pieces.map((p) => ({ idx: p.idx, itemID: p.itemID, level: p.level, slot: p.slot, location: p.location, name: p.name })),
    };
    const outPath = path.join(o.out, name);
    fs.writeFileSync(outPath, JSON.stringify(json, null, 2) + '\n');
    say(`wrote ${outPath}`);
    return r;
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(`exhaustive: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, check, headroom, piecesFromItemStats, effectIDs, gameWeights, bandFor, scoreTiers, cands, pools, coordinates, enumerate, uniqueOK, runLua, findLua, compare, scorer, GAME_DERIVED_AT, DEFAULT_ITEMSTATS };
