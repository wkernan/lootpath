'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { generate } = require('../support/synthetic');
const { newTable, readJsonInto, buildBudget } = require('../lib/stats');
const { fitDocument, spearman } = require('../lib/fit');
const { DEFAULT_DR } = require('../lib/dr');
const score = require('../lib/score');

function setup(seed) {
    const g = generate(seed);
    const table = readJsonInto(newTable(), g.table, 'synthetic');
    const budget = buildBudget(table);
    const fit = fitDocument(g.doc, table, budget, { dr: DEFAULT_DR, resamples: 200, seed: 1 });
    return { g, fit, table, budget };
}

test('a synthetic export generated from known weights fits back to them, inside the interval', () => {
    const { g, fit } = setup(7);
    assert.equal(fit.rank, 6);
    for (const k of score.STATS) {
        const [lo, hi] = fit.intervals[k];
        assert.ok(lo <= g.expected[k] && g.expected[k] <= hi, `${k}: ${g.expected[k]} outside [${lo}, ${hi}]`);
        const rel = Math.abs(fit.weights[k] - g.expected[k]) / g.expected[k];
        assert.ok(rel < 0.05, `${k}: fitted ${fit.weights[k]} vs ${g.expected[k]} (${(rel * 100).toFixed(2)}%)`);
    }
    const relBase = Math.abs(fit.baseValue - g.expected.baseValue) / g.expected.baseValue;
    assert.ok(relBase < 0.05, `base ${fit.baseValue} vs ${g.expected.baseValue}`);
    assert.ok(fit.overall.r2 > 0.999, `R2 ${fit.overall.r2}`);
    assert.ok(fit.overall.spearman > 0.99, `rho ${fit.overall.spearman}`);
});

test('the fitted weights reproduce the percent through score.upgrade (one model, two paths)', () => {
    const { g, fit } = setup(7);
    const model = {
        baseValue: fit.baseValue,
        weights: fit.weights,
        assumedFinish: {},
        dr: DEFAULT_DR,
        tiers: { forceTier: true, twoPiece: 0.03, fourPiece: 0.055 },
    };
    const worn = fit.worn.map((w) => ({ slot: w.slot, stats: w.stats }));
    const byKey = new Map(g.table.items.map((t) => [`${t.id}@${t.level}`, t]));
    const fitted = fit.rows.filter((x) => !x.excluded);
    assert.ok(fitted.length > 40);
    for (const r of fitted) {
        const u = score.upgrade(worn, byKey.get(`${r.id}@${r.level}`), model);
        assert.ok(Math.abs(u.percent - r.predicted) < 1e-9, `${r.id}: ${u.percent} vs ${r.predicted}`);
    }
});

test('effect rows are excluded from the fit and counted: trinkets and the named armour', () => {
    const { fit } = setup(7);
    assert.equal(fit.counts.effect, 2);
    assert.equal(fit.effects.n, 2);
    assert.deepEqual(fit.effects.rows.map((r) => r.id).sort(), [271875, 300001]);
    for (const r of fit.rows.filter((x) => x.excluded === 'effect')) assert.equal(r.residual, null);
    const c = fit.counts;
    assert.equal(c.fitted + c.effect + c.censored + c.duplicate + c.pair + c.noStats, c.rows);
});

test('censored rows (upgradePercent 0) never enter the fit and are counted', () => {
    const { fit } = setup(7);
    const zeros = fit.rows.filter((r) => r.observed === 0 && r.excluded !== 'effect');
    assert.ok(zeros.length > 0, 'the synthetic export has worse items');
    assert.equal(fit.counts.censored, zeros.length);
    for (const r of zeros) assert.equal(r.excluded, 'censored');
});

test('spearman: average ranks for ties, null under five', () => {
    assert.equal(spearman([1, 2, 3, 4], [1, 2, 3, 4]), null);
    assert.ok(Math.abs(spearman([1, 2, 3, 4, 5], [5, 6, 7, 8, 9]) - 1) < 1e-12);
    assert.ok(Math.abs(spearman([1, 2, 3, 4, 5], [5, 4, 3, 2, 1]) + 1) < 1e-12);
    assert.ok(Math.abs(spearman([1, 1, 2, 3, 4], [1, 1, 2, 3, 4]) - 1) < 1e-12);
});
