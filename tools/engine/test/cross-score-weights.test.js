'use strict';

// cross-score.js --weights (E-5, WKE-711): a version 2 weights FILE scored
// against the committed Upgrade Finder documents - the band chosen by
// EngineScore.BandFor's rule, the percent the Upgrade Finder way.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const cs = require('../cross-score');
const { prepare } = require('../lib/fit');
const { loadTable, buildBudget } = require('../lib/stats');
const { STATS } = require('../lib/score');
const { DEFAULT_DR } = require('../lib/dr');

const R = path.join(__dirname, '..', '..', '..');
const PLACEHOLDER = path.join(R, 'Lootpath', 'Data', 'EngineWeights.lua');
const QE = path.join(R, 'spec', 'fixtures', 'qe');
const doc = (id) => JSON.parse(fs.readFileSync(path.join(QE, `qe-upgradefinder-Hotornot-${id}.json`), 'utf8'));

test("the band is EngineScore.BandFor's: an exact level, else the highest N+ at or below, else a content type's only band", () => {
    const { entry } = cs.loadWeightsFile(PLACEHOLDER, 105);
    assert.equal(cs.bandFor(entry, doc('abxrrnezfilt')).key, '10+'); // Dungeon +10
    assert.equal(cs.bandFor(entry, doc('lrxljklscrjr')).key, '10+'); // +2: the only Dungeon band
    assert.equal(cs.bandFor(entry, doc('kqyktjywppzw')).key, 'all'); // Raid
    const two = { Dungeon: { bands: { '2+': { a: 1 }, '8+': { b: 1 }, 12: { c: 1 } } } };
    assert.equal(cs.bandFor(two, doc('lttldhvkiqlr')).key, '8+'); // +8
    assert.equal(cs.bandFor(two, doc('zmtnpejwfewe')).key, '2+'); // +6
    const keyOnly = { Dungeon: { bands: { 12: { c: 1 } } } };
    assert.equal(cs.bandFor(keyOnly, doc('kqyktjywppzw')).label, 'Dungeon 12 (no Raid band)');
});

test('a band normalised to base + w . x(worn) = 100 predicts exactly w . d, the fit tool\'s percent', () => {
    const d = doc('abxrrnezfilt');
    const table = loadTable([path.join(R, 'spec', 'fixtures', 'captures', 'Lootpath-20261013-183853.lua')], fs, []);
    for (const r of [...d.equipped, ...d.items]) if (!table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
    const prep = prepare(d, table, buildBudget(table), { dr: DEFAULT_DR });
    const w = { int: 0.01, haste: 0.4, crit: 0.3, mastery: 0.5, vers: 0.35, leech: 0.1 };
    const wv = STATS.map((k) => w[k]);
    const base = 100 - wv.reduce((s, v, i) => s + v * prep.xWorn[i], 0);
    const s = cs.scoreBand(prep, { baseValue: base, weights: w });
    assert.ok(Math.abs(s.vWorn - 100) < 1e-9);
    const rows = prep.rows.filter((r) => !r.excluded);
    rows.forEach((r, i) => {
        const wd = Math.max(...r.diffs.map((c) => c.d.reduce((a, v, j) => a + v * wv[j], 0)));
        assert.ok(Math.abs(s.pred[i] - wd) < 1e-9, `row ${r.id}: ${s.pred[i]} vs ${wd}`);
    });
    // Doubling the scale of the whole band changes nothing: the percent is a ratio.
    const s2 = cs.scoreBand(prep, { baseValue: 2 * base, weights: Object.fromEntries(Object.entries(w).map(([k, v]) => [k, 2 * v])) });
    assert.ok(Math.abs(s2.metrics.overall.k - s.metrics.overall.k) < 1e-12);
    assert.ok(Math.abs(s2.metrics.overall.mae - s.metrics.overall.mae) < 1e-12);
    assert.throws(() => cs.scoreBand(prep, { unit: 'per point', weights: w }), /per percent only/);
});
