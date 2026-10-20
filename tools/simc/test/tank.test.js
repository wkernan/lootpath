'use strict';

// What a tank's value is, and the guard against reading it the wrong way round.
// SimC reports a DTPS scale factor as the change in damage taken per point:
// negative when the stat helps. A survival weight is minus that.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { parseRun, valueWeights, METRICS } = require('../lib/report');
const { build } = require('../lib/intermediate');

const FIX = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'simc', 'reports');

function runOf(base, metric) {
    return parseRun(fs.readFileSync(path.join(FIX, `${base}.json`), 'utf8'), fs.readFileSync(path.join(FIX, `${base}.scale.txt`), 'utf8'), metric);
}

const META = { specID: 104, fight: 'Patchwerk', profile: { path: 'x', sha256: 'y', tier: 'MID1' }, source: 'simc-sample-profile', reports: [], derivedAt: '2026-10-15T00:00:00Z' };

test('DTPS is lower-is-better and DPS higher-is-better', () => {
    assert.equal(METRICS.dtps.direction, -1);
    assert.equal(METRICS.dps.direction, 1);
});

test('a Guardian survival weight is minus SimC\'s DTPS factor, so a stat that lowers damage taken is worth more than zero', () => {
    const r = runOf('104-Patchwerk-dtps', 'dtps');
    const w = valueWeights(r);
    for (const k of r.stats) assert.equal(w[k], -r.factors[k].value, k);
    // Agility and versatility both lower the Guardian's damage taken in SimC
    // (negative DTPS factors, well outside their error).
    for (const k of ['agi', 'vers']) {
        assert.ok(r.factors[k].value < 0 && Math.abs(r.factors[k].value) > r.factors[k].error, `${k} DTPS factor ${r.factors[k].value}`);
        assert.ok(w[k] > 0, `${k} weight ${w[k]}`);
    }
});

test('REFUSED: a tank value computed the wrong way round (DTPS read as higher-is-better)', () => {
    const r = runOf('104-Patchwerk-dtps', 'dtps');
    const wrong = { ...r, metric: { ...r.metric, direction: 1 } };
    assert.throws(() => valueWeights(wrong), /reads the wrong way round: agi would be worth -/);
});

test('the Guardian entry is valued on DPS by default and keeps its DTPS factors beside it', () => {
    const runs = [runOf('104-Patchwerk-dps', 'dps'), runOf('104-Patchwerk-dtps', 'dtps')];
    const e = build(runs, META);
    assert.equal(e.role, 'TANK');
    assert.equal(e.value.metric, 'dps');
    assert.match(e.value.means, /^damage/);
    assert.ok(e.factors.dps && e.factors.dtps);
    for (const k of e.stats) assert.equal(e.weights[k], e.factors.dps.stats[k].value);
});

test('--tank-value dtps values a Guardian on its survival (minus SimC\'s DTPS factor)', () => {
    const runs = [runOf('104-Patchwerk-dps', 'dps'), runOf('104-Patchwerk-dtps', 'dtps')];
    const e = build(runs, { ...META, tankValue: 'dtps' });
    assert.equal(e.value.metric, 'dtps');
    assert.match(e.value.means, /^survival/);
    for (const k of e.stats) assert.equal(e.weights[k], -e.factors.dtps.stats[k].value);
});

test('REFUSED: a tank entry missing its DTPS run when DTPS was measurable', () => {
    assert.throws(() => build([runOf('104-Patchwerk-dps', 'dps')], { ...META, tankValue: 'dps' }), /needs both a dtps and a dps run; dtps is missing/);
});
