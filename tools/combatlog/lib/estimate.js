// A band's estimate from its segments (E-5, WKE-711; docs/COMBAT-LOG-WEIGHTS.md
// §7, §9): the trimmed mean of the segments' weights, a seeded bootstrap
// interval, and the rank rule that writes a weight `unshipped`.
'use strict';

const TRIM = 0.2;
const RESAMPLES = 2000;
const SEED = 7110;

// The same small generator tools/engine/lib/fit.js uses (mulberry32), so a
// seed gives the same draws on every machine.
function mulberry32(seed) {
    let a = seed >>> 0;
    return function next() {
        a = (a + 0x6d2b79f5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// Sorted, the lowest and highest floor(trim x n) dropped, the rest averaged.
function trimmedMean(values, trim) {
    const t = trim === undefined ? TRIM : trim;
    const v = values.slice().sort((a, b) => a - b);
    const k = Math.floor(t * v.length);
    const kept = v.slice(k, v.length - k);
    if (!kept.length) return null;
    return kept.reduce((s, x) => s + x, 0) / kept.length;
}

function percentile(sorted, q) {
    if (!sorted.length) return null;
    const pos = (sorted.length - 1) * q;
    const lo = Math.floor(pos);
    const hi = Math.ceil(pos);
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

// rows: [{ stat: value, ... }] one per segment. For every stat with a value
// in every row: the trimmed mean, and the 2.5-97.5% bootstrap interval of the
// trimmed mean over segments drawn with replacement (the same draw for every
// stat, so their correlation is kept).
function estimate(rows, opts) {
    const o = opts || {};
    const resamples = o.resamples === undefined ? RESAMPLES : o.resamples;
    const rand = mulberry32(o.seed === undefined ? SEED : o.seed);
    const stats = Object.keys(rows[0] || {}).filter((k) => rows.every((r) => typeof r[k] === 'number' && Number.isFinite(r[k])));
    const out = {};
    const draws = Object.fromEntries(stats.map((k) => [k, []]));
    for (let b = 0; b < resamples; b++) {
        const pick = rows.map(() => rows[Math.floor(rand() * rows.length)]);
        for (const k of stats) draws[k].push(trimmedMean(pick.map((r) => r[k]), o.trim));
    }
    for (const k of stats) {
        const s = draws[k].slice().sort((a, b) => a - b);
        out[k] = { mean: trimmedMean(rows.map((r) => r[k]), o.trim), lo: percentile(s, 0.025), hi: percentile(s, 0.975) };
    }
    return out;
}

const fmt = (x) => x.toFixed(4);

// The honesty rule (§9): stats ranked by point estimate; a stat whose
// interval overlaps the interval of a stat ranked next to it is unshipped.
// `fixed` names the reference stat (Intellect, 1 exactly), ranked with the
// others but never unshipped. Returns { stat: reason }.
function unshippedByRank(est, fixed) {
    const ranked = Object.keys(est).sort((a, b) => est[b].mean - est[a].mean || a.localeCompare(b));
    const out = {};
    ranked.forEach((k, i) => {
        if (k === fixed) return;
        const reasons = [];
        for (const j of [i - 1, i + 1]) {
            const n = ranked[j];
            if (!n) continue;
            const a = est[k];
            const b = est[n];
            if (a.lo <= b.hi && b.lo <= a.hi) reasons.push(`interval [${fmt(a.lo)}, ${fmt(a.hi)}] overlaps ${n}'s [${fmt(b.lo)}, ${fmt(b.hi)}] in rank`);
        }
        if (reasons.length) out[k] = reasons.join('; ');
    });
    return out;
}

module.exports = { TRIM, RESAMPLES, SEED, mulberry32, trimmedMean, percentile, estimate, unshippedByRank };
