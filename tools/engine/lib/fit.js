// The structure run (E-0e, WKE-674): fit E-0c's weights to one QE Live Upgrade
// Finder export, and say where the fit fails.
//
// The model is lib/score.js's. With the tier forced on for both sets (as the
// Upgrade Finder does) the multiplier cancels from the percent, and with
// V(worn) normalised so that base + w.x(worn) = 100 the predicted percent is
// exactly w . (x(with) - x(worn)) - linear in the six weights. So the fit is
// least squares on those differences, and `base = 100 - w . x(worn)` falls out.
// Seven parameters, one normalisation: the scale of a weights file is free,
// because the percent is a ratio.
//
// Rows that do not enter the fit, each counted:
//   effect     trinkets and the effect armour pieces - QE Live values their
//              effect, a stats-only model cannot; reported apart
//   censored   `upgradePercent` 0: the Upgrade Finder's Top Gear kept the worn
//              set, so the true value is "0 or worse" - reported as a sign
//              check, never fitted as a 0
//   duplicate  the same `id@level` twice in one document (two sources)
//   pair       a one-hander or off-hand beside a worn two-hander
//   no-stats   no client row in the slot's budget group
//
// SIGN: `upgradePercent` > 0 means the drop is BETTER (UFImport's convention,
// ARCHITECTURE.md §7 2026-09-08). Read as-is, never negated.
'use strict';

const { STATS, features, totals, candidates } = require('./score');
const { itemStats, craftedPair } = require('./stats');
const { leastSquares } = require('./linalg');

const DEFAULT_EFFECT_IDS = [271875, 271092, 268265, 273778];

const SLOT_CLASS = {
    Head: 'tier-slot',
    Shoulder: 'tier-slot',
    Chest: 'tier-slot',
    Hands: 'tier-slot',
    Legs: 'tier-slot',
    Wrist: 'armour',
    Waist: 'armour',
    Feet: 'armour',
    Back: 'armour',
    Neck: 'jewellery',
    Finger: 'jewellery',
    '2H Weapon': 'weapon',
    '1H Weapon': 'weapon',
    Offhand: 'weapon',
    Trinket: 'trinket',
};

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

function vec(x) {
    return STATS.map((k) => x[k]);
}

function dot(a, b) {
    let s = 0;
    for (let i = 0; i < a.length; i++) s += a[i] * b[i];
    return s;
}

// Build the worn set and every row's candidate difference vectors.
function prepare(doc, table, budget, opts) {
    const options = opts || {};
    const effectIds = new Set(options.effectIds || DEFAULT_EFFECT_IDS);
    const finish = options.assumedFinish || null;
    const dr = options.dr;
    const pair = craftedPair(doc.settings && doc.settings.craftedStats);

    const worn = doc.equipped.map((e) => {
        const s = itemStats(table, budget, e);
        return { id: e.id, level: e.level, slot: e.slot, setId: e.setId, stats: s.stats, statsSource: s.statsSource, splitSource: s.splitSource, clientSource: s.clientSource || null };
    });
    const wornMissing = worn.filter((w) => !w.stats);
    const wornUsable = worn.map((w) => (w.stats ? w : { ...w, stats: {} }));
    const xWorn = vec(features(totals(wornUsable, finish), dr));

    const seen = new Set();
    const rows = doc.items.map((r) => {
        const row = {
            id: r.id,
            level: r.level,
            slot: r.slot,
            dropLoc: r.dropLoc,
            observed: r.upgradePercent,
            slotClass: SLOT_CLASS[r.slot] || 'other',
            excluded: null,
        };
        const key = `${r.id}@${r.level}`;
        const s = itemStats(table, budget, r, { craftedPair: r.dropLoc === 'Crafted' ? pair : null });
        row.statsSource = s.statsSource;
        row.splitSource = s.splitSource;
        row.clientSource = s.clientSource || null;
        if (r.slot === 'Trinket' || effectIds.has(r.id)) row.excluded = 'effect';
        else if (seen.has(key)) row.excluded = 'duplicate';
        seen.add(key);
        if (!s.stats) {
            if (!row.excluded) row.excluded = 'no-stats';
            return row;
        }
        const item = { id: r.id, level: r.level, slot: r.slot, stats: s.stats };
        const sets = candidates(wornUsable, item);
        if (!sets.length) {
            if (!row.excluded) row.excluded = 'pair';
            return row;
        }
        row.diffs = sets.map((c) => {
            const x = vec(features(totals(c.items, finish), dr));
            return { replaced: c.replaced.map((i) => worn[i] && `${worn[i].id}@${worn[i].level}`), d: x.map((v, i) => v - xWorn[i]) };
        });
        if (!row.excluded && !(r.upgradePercent > 0)) row.excluded = 'censored';
        return row;
    });
    return { worn, wornMissing: wornMissing.length, xWorn, rows };
}

function chooseAndFit(fitRows, w0) {
    let w = w0;
    let choice = fitRows.map(() => 0);
    let result = null;
    for (let iter = 0; iter < 20; iter++) {
        if (w) choice = fitRows.map((r) => argmax(r.diffs.map((c) => dot(c.d, w))));
        const X = fitRows.map((r, i) => r.diffs[choice[i]].d);
        const y = fitRows.map((r) => r.observed);
        result = leastSquares(X, y);
        const next = fitRows.map((r) => argmax(r.diffs.map((c) => dot(c.d, result.beta))));
        w = result.beta;
        if (next.every((c, i) => c === choice[i])) break;
    }
    return { beta: result.beta, rank: result.rank, condition: result.condition, choice };
}

function argmax(a) {
    let best = 0;
    for (let i = 1; i < a.length; i++) if (a[i] > a[best]) best = i;
    return best;
}

function ranks(a) {
    const idx = a.map((v, i) => [v, i]).sort((x, y) => x[0] - y[0]);
    const r = new Array(a.length);
    for (let i = 0; i < idx.length; ) {
        let j = i;
        while (j + 1 < idx.length && idx[j + 1][0] === idx[i][0]) j += 1;
        const avg = (i + j) / 2 + 1;
        for (let k = i; k <= j; k++) r[idx[k][1]] = avg;
        i = j + 1;
    }
    return r;
}

function pearson(a, b) {
    const n = a.length;
    const ma = a.reduce((s, v) => s + v, 0) / n;
    const mb = b.reduce((s, v) => s + v, 0) / n;
    let num = 0;
    let da = 0;
    let db = 0;
    for (let i = 0; i < n; i++) {
        num += (a[i] - ma) * (b[i] - mb);
        da += (a[i] - ma) ** 2;
        db += (b[i] - mb) ** 2;
    }
    return da > 0 && db > 0 ? num / Math.sqrt(da * db) : null;
}

// Spearman rho with average ranks for ties; not computed under n = 5 (memo §6).
function spearman(a, b) {
    if (a.length < 5) return null;
    return pearson(ranks(a), ranks(b));
}

function metrics(obs, pred) {
    const n = obs.length;
    if (!n) return { n: 0, r2: null, mae: null, spearman: null };
    const mean = obs.reduce((s, v) => s + v, 0) / n;
    let ssRes = 0;
    let ssTot = 0;
    let abs = 0;
    for (let i = 0; i < n; i++) {
        ssRes += (obs[i] - pred[i]) ** 2;
        ssTot += (obs[i] - mean) ** 2;
        abs += Math.abs(obs[i] - pred[i]);
    }
    return { n, r2: ssTot > 0 ? 1 - ssRes / ssTot : null, mae: abs / n, spearman: spearman(obs, pred) };
}

function percentile(sorted, q) {
    if (!sorted.length) return null;
    const pos = (sorted.length - 1) * q;
    const lo = Math.floor(pos);
    const hi = Math.ceil(pos);
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

function fitDocument(doc, table, budget, opts) {
    const options = opts || {};
    const resamples = options.resamples === undefined ? 200 : options.resamples;
    const prep = prepare(doc, table, budget, options);
    const fitRows = prep.rows.filter((r) => !r.excluded);
    if (fitRows.length < STATS.length) throw new Error(`${doc.reportId}: only ${fitRows.length} rows to fit`);

    const main = chooseAndFit(fitRows, null);
    const w = main.beta;
    const base = 100 - dot(w, prep.xWorn);

    // Bootstrap over rows, the candidate choice held at the main fit's.
    const rand = mulberry32(options.seed === undefined ? 1 : options.seed);
    const draws = STATS.map(() => []);
    const baseDraws = [];
    for (let b = 0; b < resamples; b++) {
        const X = [];
        const y = [];
        for (let i = 0; i < fitRows.length; i++) {
            const k = Math.floor(rand() * fitRows.length);
            X.push(fitRows[k].diffs[main.choice[k]].d);
            y.push(fitRows[k].observed);
        }
        const r = leastSquares(X, y);
        r.beta.forEach((v, j) => draws[j].push(v));
        baseDraws.push(100 - dot(r.beta, prep.xWorn));
    }
    const interval = (a) => {
        const s = a.slice().sort((x, y) => x - y);
        return [percentile(s, 0.025), percentile(s, 0.975)];
    };

    const predictRow = (r) => {
        if (!r.diffs) return null;
        return Math.max(...r.diffs.map((c) => dot(c.d, w)));
    };
    for (const r of prep.rows) {
        const p = predictRow(r);
        r.predicted = p;
        r.residual = p === null || r.excluded === 'censored' || r.excluded === 'effect' ? null : r.observed - p;
        if (r.diffs) {
            const best = argmax(r.diffs.map((c) => dot(c.d, w)));
            r.replaced = r.diffs[best].replaced;
        }
    }

    const byClass = {};
    for (const r of fitRows) (byClass[r.slotClass] = byClass[r.slotClass] || []).push(r);
    const classMetrics = {};
    for (const [c, rs] of Object.entries(byClass)) classMetrics[c] = metrics(rs.map((r) => r.observed), rs.map((r) => r.predicted));

    const count = (pred) => prep.rows.filter(pred).length;
    const censored = prep.rows.filter((r) => r.excluded === 'censored');
    const effects = prep.rows.filter((r) => r.excluded === 'effect');
    const sourceCounts = (rows) => {
        const out = {};
        for (const r of rows) out[r.statsSource] = (out[r.statsSource] || 0) + 1;
        return out;
    };
    // Which transcript a `client` / `client-scaled` row's stats were read from.
    const clientCounts = (rows) => {
        const out = {};
        for (const r of rows) if (r.clientSource) out[`${r.statsSource} <- ${r.clientSource}`] = (out[`${r.statsSource} <- ${r.clientSource}`] || 0) + 1;
        return out;
    };

    const weights = {};
    const intervals = {};
    STATS.forEach((k, j) => {
        weights[k] = w[j];
        intervals[k] = interval(draws[j]);
    });

    return {
        document: doc.reportId,
        contentType: doc.contentType,
        settings: doc.settings,
        exportedAt: doc.exportedAt,
        normalisation: 'baseValue + weights . x(worn) = 100; tier forced on cancels from the percent',
        baseValue: base,
        baseInterval: interval(baseDraws),
        weights,
        intervals,
        rank: main.rank,
        condition: main.condition,
        resamples,
        seed: options.seed === undefined ? 1 : options.seed,
        overall: metrics(fitRows.map((r) => r.observed), fitRows.map((r) => r.predicted)),
        byClass: classMetrics,
        counts: {
            rows: prep.rows.length,
            fitted: fitRows.length,
            effect: count((r) => r.excluded === 'effect'),
            censored: censored.length,
            duplicate: count((r) => r.excluded === 'duplicate'),
            pair: count((r) => r.excluded === 'pair'),
            noStats: count((r) => r.excluded === 'no-stats'),
        },
        statsSources: { fitted: sourceCounts(fitRows), all: sourceCounts(prep.rows), worn: sourceCounts(prep.worn) },
        clientSources: { fitted: clientCounts(fitRows), all: clientCounts(prep.rows), worn: clientCounts(prep.worn) },
        censoredCheck: {
            n: censored.length,
            predictedAtOrBelowZero: censored.filter((r) => r.predicted <= 0).length,
            predictedAbove0_1: censored.filter((r) => r.predicted > 0.1).length,
        },
        effects: {
            n: effects.length,
            note: 'excluded from the fit; predicted is stats-only, observed includes the effect',
            rows: effects.map((r) => ({ id: r.id, level: r.level, slot: r.slot, observed: r.observed, predicted: r.predicted, statsSource: r.statsSource })),
        },
        largestResiduals: fitRows
            .slice()
            .sort((a, b) => Math.abs(b.residual) - Math.abs(a.residual))
            .slice(0, 10)
            .map(rowOut),
        worn: prep.worn.map((x) => ({ id: x.id, level: x.level, slot: x.slot, statsSource: x.statsSource, splitSource: x.splitSource, clientSource: x.clientSource, stats: x.stats })),
        rows: prep.rows.map(rowOut),
    };
}

function rowOut(r) {
    return {
        id: r.id,
        level: r.level,
        slot: r.slot,
        slotClass: r.slotClass,
        dropLoc: r.dropLoc,
        observed: r.observed,
        predicted: r.predicted === undefined ? null : r.predicted,
        residual: r.residual === undefined ? null : r.residual,
        excluded: r.excluded,
        statsSource: r.statsSource,
        splitSource: r.splitSource,
        clientSource: r.clientSource || null,
        replaced: r.replaced || null,
    };
}

module.exports = { DEFAULT_EFFECT_IDS, SLOT_CLASS, prepare, fitDocument, metrics, spearman, ranks, mulberry32 };
