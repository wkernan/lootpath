// From segments to E-4's schema version 2 entry, for whichever healer spec
// walked them (E-5, WKE-711; E-5b, WKE-713; docs/COMBAT-LOG-WEIGHTS.md §7,
// §9). One Dungeon band per key level, the Raid band "all" for raid
// encounters; written through tools/engine's one Lua writer (lib/luaout.js),
// so there is one writer of the weights file.
'use strict';

const { luaValue, NO_TIER_SET } = require('../../engine/lib/luaout');
const { segmentWeights } = require('./attribute');
const { ratingToPercent } = require('./dr');
const E = require('./estimate');
const { SPECS } = require('../specs');

const RANKED = ['int', 'haste', 'crit', 'mastery', 'vers', 'leech'];
const ALL = [...RANKED, 'hasteCast'];
const RATINGS = ['haste', 'crit', 'mastery', 'vers', 'leech'];
const round = (x, d) => (x === null || x === undefined ? x : Number(x.toFixed(d === undefined ? 6 : d)));
const pick = (o, keys) => Object.fromEntries(keys.filter((k) => o[k] !== null && o[k] !== undefined).map((k) => [k, o[k]]));

// A segment counts when at least one of its heals moved with Intellect.
function usable(seg) {
    return seg.sums.gain.int > 0;
}

// segments of one band -> the band's numbers and provenance.
function bandOf(segs, dr, spec, opts) {
    const o = opts || {};
    const rows = segs.map((s) => segmentWeights(s, dr));
    const rel = E.estimate(rows.map((r) => pick(r.relative, ALL)), o);
    const relPct = E.estimate(rows.map((r) => pick(r.relativePercent, ALL)), o);
    const ranked = pick(rel, RANKED);
    const unshipped = E.unshippedByRank(ranked, 'int');
    if (segs.length < 2) for (const k of RATINGS) unshipped[k] = 'fewer than 2 segments: no interval';
    if (!rel.leech) unshipped.leech = 'no leech rating: nothing measured, and the method predicts none';

    // The value at the player's own stats is 100 (§9): V_obs, in Intellect
    // points, is the band's effective healing over its Intellect gain.
    const H = segs.reduce((s, x) => s + x.sums.effective, 0);
    const G = segs.reduce((s, x) => s + x.sums.gain.int, 0);
    const vObs = H / G;
    const w = (seg) => seg.sums.effective / H;
    const xObs = { int: segs.reduce((s, x) => s + w(x) * x.int, 0) };
    for (const k of RATINGS) xObs[k] = segs.reduce((s, x) => s + w(x) * ratingToPercent(x.ratings[k], dr[k]), 0);
    const perPct = { int: 1 };
    for (const k of RATINGS) perPct[k] = relPct[k] ? relPct[k].mean : 0;
    const scale = 100 / vObs;
    const baseInt = vObs - RANKED.reduce((s, k) => s + perPct[k] * xObs[k], 0);
    const weights = {};
    const intervals = {};
    for (const k of RANKED) {
        weights[k] = round(perPct[k] * scale, 9);
        intervals[k] = k === 'int' ? { lo: weights.int, hi: weights.int } : relPct[k] ? { lo: round(relPct[k].lo * scale, 9), hi: round(relPct[k].hi * scale, 9) } : undefined;
    }
    const perRatingPoint = {};
    for (const k of RANKED) if (rel[k]) perRatingPoint[k] = { mean: round(rel[k].mean), lo: round(rel[k].lo), hi: round(rel[k].hi) };

    const sum = (f) => segs.reduce((s, x) => s + f(x.sums), 0);
    const untracked = {};
    for (const id of Object.keys(spec.UNSIZED_BUFFS)) {
        const e = sum((s) => s.unsized[id] || 0);
        if (e > 0) untracked[spec.UNSIZED_BUFFS[id].name] = { spellId: Number(id), stat: spec.UNSIZED_BUFFS[id].stat, shareOfHealing: round(e / H, 4) };
    }
    const unknown = {};
    for (const s of segs) for (const [id, e] of Object.entries(s.sums.unknown)) unknown[id] = (unknown[id] || 0) + e;
    const first = segs[0];
    return {
        baseValue: round(baseInt * scale, 9),
        unit: 'per percent',
        weights,
        intervals,
        perRatingPoint,
        hasteCastForm: rel.hasteCast ? { perPercent: round(relPct.hasteCast.mean * scale, 9), perRatingPoint: { mean: round(rel.hasteCast.mean), lo: round(rel.hasteCast.lo), hi: round(rel.hasteCast.hi) } } : undefined,
        unshipped: Object.keys(unshipped).length ? unshipped : undefined,
        segments: segs.length,
        segmentNames: segs.map((s) => `${s.kind}: ${s.name}`),
        events: sum((s) => s.events),
        eventsWithoutOverheal: sum((s) => s.events - s.overhealEvents - s.leechEvents),
        overhealShare: round(sum((s) => s.overheal) / sum((s) => s.raw), 4),
        leechEvents: sum((s) => s.leechEvents),
        guardianShare: round(sum((s) => s.guardianEffective) / (H + sum((s) => s.guardianEffective)), 4),
        absorbed: sum((s) => s.absorbed),
        unknownSpells: Object.keys(unknown).length ? Object.fromEntries(Object.entries(unknown).map(([id, e]) => [id, round(e / H, 4)])) : undefined,
        untrackedBuffs: Object.keys(untracked).length ? untracked : undefined,
        player: { int: first.int, ratings: { ...first.ratings }, spec: first.spec },
        estimate: { trim: o.trim === undefined ? E.TRIM : o.trim, resamples: o.resamples === undefined ? E.RESAMPLES : o.resamples, seed: o.seed === undefined ? E.SEED : o.seed },
        assumedFinish: {},
        assumedBuffs: {},
    };
}

// The spec ID a set of walked logs belongs to: every usable segment's, which
// must agree - one entry is one spec, so a log of a different spec than the
// others', passed by mistake, is refused rather than silently merged into
// one or the other's label (every usable segment is still pooled into the
// same bands either way: see buildEntry). weights.js reuses this to tell
// buildTable which spec its entry is for.
function specOf(walks) {
    const specs = new Set();
    for (const { walk } of walks) for (const seg of walk.segments) if (usable(seg)) specs.add(seg.spec);
    if (specs.size > 1) throw new Error(`mixed specs in one run: ${[...specs].sort((a, b) => a - b).join(', ')} - one entry is one spec`);
    return specs.size ? [...specs][0] : null;
}

// walks: [{ file, sha256, walk }] -> the entry for whichever spec walked them.
function buildEntry(walks, dr, meta) {
    const m = meta || {};
    const groups = new Map();
    let dropped = 0;
    for (const { walk } of walks) {
        for (const seg of walk.segments) {
            if (!usable(seg)) {
                dropped += 1;
                continue;
            }
            const k = `${seg.contentType}\u0000${seg.band}`;
            if (!groups.has(k)) groups.set(k, { contentType: seg.contentType, band: seg.band, segs: [] });
            groups.get(k).segs.push(seg);
        }
    }
    if (!groups.size) throw new Error('no usable segment in the logs');
    const specID = specOf(walks);
    const spec = SPECS.get(specID);
    if (!spec) throw new Error(`spec ${specID} has no combat-log module (specs/index.js)`);
    const entry = {
        role: spec.role,
        primaryStat: spec.primaryStat,
        stats: spec.stats.slice(),
        method: 'combat-log',
        derivedAt: m.derivedAt,
        source: 'tools/combatlog (docs/COMBAT-LOG-WEIGHTS.md): per-event attribution over the player\'s own WoWCombatLog.txt',
        logs: walks.map(({ file, sha256, walk }) => ({
            file,
            sha256,
            player: walk.player,
            keys: walk.keys.map((k) => ({ zone: k.zone, level: k.level, timed: k.success, durationMs: k.durationMs })),
            harmony: { unseenRemovals: walk.diag.unseenRemovals, resyncAdded: walk.diag.resyncAdded, resyncDropped: walk.diag.resyncDropped },
        })),
        segmentsDropped: dropped,
    };
    const sorted = [...groups.values()].sort((a, b) => a.contentType.localeCompare(b.contentType) || String(a.band).localeCompare(String(b.band), 'en', { numeric: true }));
    for (const g of sorted) {
        entry[g.contentType] = entry[g.contentType] || { bands: {} };
        entry[g.contentType].bands[g.band] = bandOf(g.segs, dr, spec, m.estimate);
    }
    entry.tiers = new Map([[NO_TIER_SET, new Map([[2, { mult: 1 }], [4, { mult: 1 }]])]]);
    return entry;
}

function buildTable(entry, meta) {
    return { schema: 'lootpath-engine-weights', version: 2, devOnly: true, patch: meta.patch, specs: new Map([[meta.specID, entry]]), dr: meta.dr };
}

// This header names Restoration by name, unlike the rest of this file: it is
// generated TEXT, not spec-dispatched code, and changing it changes every
// byte this PR promises stays identical for Restoration (E-5b, WKE-713;
// docs/brain/inbox/WKE-713.md). It is accurate today - Restoration is the
// only module in specs/index.js - and wrong the day a second one's entry
// gets written; fix it then, when there is a real second spec's wording to
// write instead of a guess.
function render(table, meta) {
    const logs = meta.logs.map((l) => `--   ${l.file}  sha256 ${l.sha256}`).join('\n');
    return [
        '-- DEV ONLY - never ship.',
        '--',
        '-- Written by tools/combatlog/weights.js (E-5, WKE-711): Restoration stat weights',
        "-- from the player's own combat log, per docs/COMBAT-LOG-WEIGHTS.md. Weights per",
        '-- percent of each rating and per point of Intellect, scaled so the value at the',
        "-- player's own stats is 100. A stat listed under `unshipped` is one the evidence",
        '-- cannot rank; no promotion may ship it. No tier bonus is measured (set -1).',
        '-- Gitignored; .pkgmeta never packages tools/. Regenerate it; never edit it.',
        '--',
        '-- From:',
        logs,
        '',
        'local _, ns = ...',
        '',
        `ns.engineWeights = ${luaValue(table, 0)}`,
        '',
    ].join('\n');
}

module.exports = { RANKED, usable, specOf, bandOf, buildEntry, buildTable, render };
