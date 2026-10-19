'use strict';

// specOf/buildEntry must refuse to merge two different specs' logs into one
// entry (E-5b, WKE-713 rework): a run with a second spec module registered
// is not a run any real log could produce today - Restoration is the only
// module - but the code must not silently label itself after whichever
// walk's segments came first, the way it used to
// (.stokowski/artifacts/probe-mixed-specs.js reproduces the old behaviour).
const test = require('node:test');
const assert = require('node:assert/strict');
const S = require('../support/synth');
const { makeStubSpec } = require('../support/stubSpec');
const P = require('../lib/parse');
const { walk } = require('../lib/attribute');
const { loadDR } = require('../lib/dr');
const { SPECS } = require('../specs');
const { specOf, buildEntry } = require('../lib/entry');

const dr = loadDR();

function walkOne(spec) {
    S.reset();
    const text = [
        S.challengeStart(10),
        S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69, spec }),
        S.heal({ spellId: 774, name: 'Rejuvenation', periodic: true, amount: 1000 }),
        S.challengeEnd(10),
    ].join('\n');
    return { file: `spec-${spec}.txt`, sha256: 'x', walk: walk(P.parseText(text), { dr, player: S.PLAYER }) };
}

test('two logs of different specs refuse to merge into one entry, in either order', () => {
    const stub = makeStubSpec(902);
    SPECS.set(902, stub);
    try {
        const a = walkOne(105);
        const b = walkOne(902);
        assert.throws(() => specOf([a, b]), /mixed specs in one run: 105, 902 - one entry is one spec/);
        assert.throws(() => specOf([b, a]), /mixed specs in one run: 105, 902 - one entry is one spec/);
        assert.throws(() => buildEntry([a, b], dr, {}), /mixed specs in one run: 105, 902/);
    } finally {
        SPECS.delete(902);
    }
});

test('logs that agree on spec still resolve to it, across multiple walks', () => {
    const a = walkOne(105);
    const b = walkOne(105);
    assert.equal(specOf([a, b]), 105);
});
