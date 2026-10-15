'use strict';

// Two runs agree. The committed Feral Patchwerk report was run three times
// with the same settings: twice with seed 7101 (`103-Patchwerk-dps` and its
// `.rerun`) and once with seed 7102 (`.seed7102`).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { parseRun } = require('../lib/report');

const FIX = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'simc', 'reports');

function runOf(base) {
    return parseRun(fs.readFileSync(path.join(FIX, `${base}.json`), 'utf8'), fs.readFileSync(path.join(FIX, `${base}.scale.txt`), 'utf8'), 'dps');
}

test('the same seed reproduces every scale factor (to floating-point merge order)', () => {
    const a = runOf('103-Patchwerk-dps');
    const b = runOf('103-Patchwerk-dps.rerun');
    for (const k of a.stats) {
        const rel = Math.abs(a.factors[k].value - b.factors[k].value) / Math.abs(a.factors[k].value);
        assert.ok(rel < 1e-9, `${k}: ${a.factors[k].value} vs ${b.factors[k].value}`);
        assert.ok(Math.abs(a.factors[k].error - b.factors[k].error) / a.factors[k].error < 1e-9, `${k} error`);
    }
    assert.ok(Math.abs(a.metric.mean - b.metric.mean) / a.metric.mean < 1e-9);
});

test('another seed draws differently and still agrees within the error SimC prints', () => {
    const a = runOf('103-Patchwerk-dps');
    const c = runOf('103-Patchwerk-dps.seed7102');
    let differs = false;
    for (const k of a.stats) {
        const d = Math.abs(a.factors[k].value - c.factors[k].value);
        if (d > 0) differs = true;
        assert.ok(d <= a.factors[k].error + c.factors[k].error, `${k}: ${a.factors[k].value} vs ${c.factors[k].value}, errors ${a.factors[k].error} and ${c.factors[k].error}`);
    }
    assert.ok(differs, 'a different seed must draw different numbers');
});
