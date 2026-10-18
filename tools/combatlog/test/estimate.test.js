'use strict';

// The estimate (docs/COMBAT-LOG-WEIGHTS.md §7, §9): trimmed mean, a seeded
// bootstrap, and the rank rule that writes a weight unshipped.
const test = require('node:test');
const assert = require('node:assert/strict');
const E = require('../lib/estimate');

test('the trimmed mean drops floor(0.2 n) from each end', () => {
    assert.equal(E.trimmedMean([1, 2, 3, 4]), 2.5); // n 4: nothing dropped
    assert.equal(E.trimmedMean([100, 1, 2, 3, -50]), 2); // n 5: one each end
    assert.equal(E.trimmedMean([1, 2, 3, 4, 5, 6, 7, 8, 9, 1000]), 5.5); // n 10: two each end
});

test('the bootstrap is seeded: two runs agree, a constant has a zero-width interval', () => {
    const rows = [
        { a: 1, b: 0.5 },
        { a: 1.2, b: 0.4 },
        { a: 0.9, b: 0.55 },
        { a: 1.1, b: 0.45 },
        { a: 1.05, b: 0.5 },
        { a: 1, b: 0.6 },
    ];
    assert.deepEqual(E.estimate(rows), E.estimate(rows));
    const c = E.estimate(rows.map(() => ({ k: 2 })));
    assert.deepEqual(c.k, { mean: 2, lo: 2, hi: 2 });
    const r = E.estimate(rows);
    assert.ok(r.a.lo <= r.a.mean && r.a.mean <= r.a.hi);
});

test('the rank rule: overlapping neighbours are both unshipped, the reference never is, disjoint ones ship', () => {
    const est = {
        int: { mean: 1, lo: 1, hi: 1 },
        mastery: { mean: 0.7, lo: 0.65, hi: 0.75 },
        vers: { mean: 0.54, lo: 0.53, hi: 0.55 },
        crit: { mean: 0.47, lo: 0.45, hi: 0.49 },
        leech: { mean: 0.35, lo: 0.22, hi: 0.46 },
        haste: { mean: 0.25, lo: 0.2, hi: 0.27 },
    };
    const u = E.unshippedByRank(est, 'int');
    assert.deepEqual(Object.keys(u).sort(), ['crit', 'haste', 'leech']);
    assert.match(u.crit, /overlaps leech's \[0\.2200, 0\.4600\] in rank/);
    assert.equal(u.mastery, undefined);
    assert.equal(u.vers, undefined);
    // A stat whose interval reaches the reference's 1 is unshipped too.
    assert.ok(E.unshippedByRank({ int: est.int, mastery: { mean: 0.9, lo: 0.8, hi: 1.01 } }, 'int').mastery);
});
