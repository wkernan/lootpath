'use strict';

// specOf/buildEntry must refuse to merge two different specs' logs into one
// entry (Decision 8, WKE-713 code review): when the walks' usable segments
// carry more than one spec ID, entry.js refuses, naming the IDs, instead of
// labelling one entry with another spec's segments.
const test = require('node:test');
const assert = require('node:assert/strict');
const S = require('../support/synth');
const P = require('../lib/parse');
const { walk } = require('../lib/attribute');
const { loadDR } = require('../lib/dr');
const specs = require('../lib/specs');
const toySpec = require('../support/toy-spec');
const { specOf, buildEntry } = require('../lib/entry');

const dr = loadDR();

function walkOne(spec, spellId) {
    S.reset();
    const text = [
        S.challengeStart(10),
        S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69, spec }),
        S.heal({ spellId, name: 'heal', periodic: true, amount: 1000 }),
        S.challengeEnd(10),
    ].join('\n');
    return { file: `spec-${spec}.txt`, sha256: 'x', walk: walk(P.parseText(text), { dr, player: S.PLAYER }) };
}

test('two logs of different specs refuse to merge into one entry, in either order', () => {
    specs.register(toySpec);
    try {
        const a = walkOne(105, 774);
        const b = walkOne(999, 9001);
        assert.throws(() => specOf([a, b]), /mixed specs in one run: 105, 999 - one entry is one spec/);
        assert.throws(() => specOf([b, a]), /mixed specs in one run: 105, 999 - one entry is one spec/);
        assert.throws(() => buildEntry([a, b], dr, {}), /mixed specs in one run: 105, 999/);
    } finally {
        specs.unregister(999);
    }
});

test('logs that agree on spec still resolve to it, across multiple walks', () => {
    const a = walkOne(105, 774);
    const b = walkOne(105, 774);
    assert.equal(specOf([a, b]), 105);
});
