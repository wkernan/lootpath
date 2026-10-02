// The set value of E-0c's `ns.EngineScore`, in JavaScript (E-0e, WKE-674).
//
// E-0c (WKE-672) is not built yet; this file implements its issue contract so
// the structure run measures the same model the addon will run, and its
// fixture (test/fixtures/score-fixture.json) is the one the Lua port is tested
// against:
//
//   totals   = the stats of the set's items summed, plus an assumed finish
//   pct_r    = rating -> percent AFTER the sum, through the DR brackets
//   value    = (base + w_int * int + sum_r w_r * pct_r) * tierMultiplier
//   tier     = forced on (the Upgrade Finder's `forceTier`), so 1 + 2pc + 4pc
//   percent  = 100 * (V(with) - V(worn)) / V(worn), V(with) the best set over
//              the worn set with the item swapped in: either ring, either
//              trinket (only the worn copy's place when the pair holds the
//              same item), a two-hander for both hands
//
// SIGN: a positive percent means the item is BETTER, the Upgrade Finder's own
// convention (`upgradePercent`, ARCHITECTURE.md §7 2026-09-08). The Upgrade
// Finder never shows a negative: its Top Gear may keep the worn set, so a
// worse item reads 0. `clampedPercent` mirrors that; `percent` does not clamp.
'use strict';

const { DEFAULT_DR, ratingToPercent } = require('./dr');

const RATING_STATS = ['haste', 'crit', 'mastery', 'vers', 'leech'];
const STATS = ['int', ...RATING_STATS];

function zeroStats() {
    const out = {};
    for (const k of STATS) out[k] = 0;
    return out;
}

function totals(items, finish) {
    const t = zeroStats();
    for (const it of items) for (const k of STATS) t[k] += (it.stats && it.stats[k]) || 0;
    if (finish) for (const k of STATS) t[k] += finish[k] || 0;
    return t;
}

// The feature vector the weights multiply: Intellect raw, every rating stat as
// a percent after DR.
function features(t, dr) {
    const table = dr || DEFAULT_DR;
    const x = { int: t.int };
    for (const k of RATING_STATS) x[k] = ratingToPercent(t[k], table[k]);
    return x;
}

function tierMultiplier(items, tiers) {
    if (!tiers) return 1;
    const two = tiers.twoPiece || 0;
    const four = tiers.fourPiece || 0;
    if (tiers.forceTier !== false) return 1 + two + four;
    const sets = new Set(tiers.setIDs || []);
    let pieces = 0;
    for (const it of items) if (sets.has(it.setId)) pieces += 1;
    return 1 + (pieces >= 2 ? two : 0) + (pieces >= 4 ? four : 0);
}

function linearValue(x, model) {
    let v = model.baseValue || 0;
    for (const k of STATS) v += (model.weights[k] || 0) * x[k];
    return v;
}

function setValue(items, model) {
    const x = features(totals(items, model.assumedFinish), model.dr);
    return linearValue(x, model) * tierMultiplier(items, model.tiers);
}

// A paired slot never holds two copies of one item (E-0l, WKE-683): QE Live's
// Top Gear drops every set whose ring pair or trinket pair shares an item ID
// (fork TopGearEngine.ts:415-420 for rings, :428 for trinkets), so a drop
// whose ID a worn ring or trinket already carries can only take that copy's
// place. EngineScore.Placements holds the same rule.
const PAIRED_SLOTS = new Set(['Finger', 'Trinket']);

const WEAPON_2H = '2H Weapon';
const WEAPON_1H = '1H Weapon';
const OFFHAND = 'Offhand';

// Every set the item can make by replacing worn items. `[]` means the item
// cannot stand in the worn set alone: a one-hander or an off-hand beside a
// worn two-hander needs a partner the Upgrade Finder does not add.
function candidates(worn, item) {
    const out = [];
    const swap = (indices) => {
        const set = worn.filter((_, i) => !indices.includes(i));
        set.push(item);
        out.push({ replaced: indices.slice(), items: set });
    };
    const idx = (slot) => worn.map((w, i) => (w.slot === slot ? i : -1)).filter((i) => i >= 0);
    if (item.slot === WEAPON_2H) {
        const two = idx(WEAPON_2H);
        if (two.length) for (const i of two) swap([i]);
        else swap([...idx(WEAPON_1H), ...idx(OFFHAND)]);
        return out;
    }
    if (item.slot === WEAPON_1H || item.slot === OFFHAND) {
        if (idx(WEAPON_2H).length) return out;
        const same = idx(item.slot);
        if (same.length) for (const i of same) swap([i]);
        else swap([]);
        return out;
    }
    const same = idx(item.slot);
    const twins = PAIRED_SLOTS.has(item.slot) && item.id !== undefined && item.id !== null ? same.filter((i) => worn[i].id === item.id) : [];
    if (twins.length) for (const i of twins) swap([i]);
    else if (same.length) for (const i of same) swap([i]);
    else swap([]);
    return out;
}

function upgrade(worn, item, model) {
    const base = setValue(worn, model);
    const sets = candidates(worn, item);
    if (!sets.length) return { comparable: false, percent: null, clampedPercent: null, replaced: null };
    let best = null;
    for (const c of sets) {
        const v = setValue(c.items, model);
        if (!best || v > best.v) best = { v, replaced: c.replaced };
    }
    const percent = (100 * (best.v - base)) / base;
    return { comparable: true, percent, clampedPercent: Math.max(0, percent), replaced: best.replaced, base };
}

module.exports = {
    STATS,
    RATING_STATS,
    zeroStats,
    totals,
    features,
    tierMultiplier,
    linearValue,
    setValue,
    candidates,
    upgrade,
};
