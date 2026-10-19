// Two checks a log can answer about the method's own constants (E-5;
// docs/COMBAT-LOG-WEIGHTS.md §8). Each compares ticks of ONE heal-over-time
// effect on ONE target, so the spell, the target and (nearly) the moment are
// held equal:
//
//   critMultiplier  a critical tick's raw amount over the mean of the nearest
//                   uncritical ticks before and after it, when Harmony's
//                   count, her Intellect and her tracked buffs were the same
//                   at all three; the median.
//   harmony         consecutive uncritical ticks, same Intellect and buffs:
//                   the later over the earlier, grouped by the change of
//                   Harmony's count; each group's median beside
//                   (1 + P c T(later)) / (1 + P c T(earlier)).
//
// Wild Growth is left out: its ticks shrink over its duration by design.
'use strict';

const { walk } = require('./attribute');
// This probe is Restoration's own: Harmony and its stack table are hers, so
// it reads her spec module directly rather than through specs/index.js's
// by-spec-ID dispatch (E-5b, WKE-713).
const { stackFactor, CONSTANTS } = require('../specs/restoration');
const { ratingToPercent } = require('./dr');

const DECLINING = new Set([48438]);

function median(a) {
    if (!a.length) return null;
    const s = a.slice().sort((x, y) => x - y);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function probe(events, opts) {
    const o = opts || {};
    const series = new Map(); // spell|target -> ticks
    const C = { ...CONSTANTS, ...(o.constants || {}) };
    let masteryPoints = null;
    walk(events, {
        ...o,
        onHeal(h, ctx) {
            if (!h.periodic || DECLINING.has(h.spellId) || !(h.amount > 0)) return;
            if (masteryPoints === null) masteryPoints = C.masteryBase + ratingToPercent(ctx.ratings.mastery, o.dr.mastery);
            const k = `${h.spellId}|${h.dst}`;
            if (!series.has(k)) series.set(k, []);
            series.get(k).push({ t: ctx.t, raw: h.amount, crit: h.critical, n: ctx.n, int: ctx.intNow, buffs: ctx.buffs, spellId: h.spellId });
        },
    });
    const same = (a, b) => a.n === b.n && a.int === b.int && a.buffs === b.buffs;
    const critRatios = [];
    const groups = new Map();
    for (const ticks of series.values()) {
        for (let i = 1; i < ticks.length - 1; i++) {
            const [a, b, c] = [ticks[i - 1], ticks[i], ticks[i + 1]];
            if (b.crit && !a.crit && !c.crit && same(a, b) && same(b, c)) critRatios.push(b.raw / ((a.raw + c.raw) / 2));
        }
        for (let i = 1; i < ticks.length; i++) {
            const [a, b] = [ticks[i - 1], ticks[i]];
            if (a.crit || b.crit || a.int !== b.int || a.buffs !== b.buffs || a.n < 1 || b.n < 1) continue;
            const g = `${a.n}->${b.n}`;
            if (!groups.has(g)) groups.set(g, { from: a.n, to: b.n, ratios: [] });
            groups.get(g).ratios.push(b.raw / a.raw);
        }
    }
    const c = C.harmonyCoefficient / 100;
    const predicted = (from, to) => (1 + masteryPoints * c * stackFactor(to)) / (1 + masteryPoints * c * stackFactor(from));
    const harmony = [...groups.values()]
        .filter((g) => g.ratios.length >= (o.minPairs || 20))
        .sort((x, y) => x.from - y.from || x.to - y.to)
        .map((g) => ({ change: `${g.from}->${g.to}`, pairs: g.ratios.length, median: median(g.ratios), predicted: predicted(g.from, g.to) }));
    return { critMultiplier: { pairs: critRatios.length, median: median(critRatios) }, masteryPoints, harmony };
}

module.exports = { probe, median };
