'use strict';

// The registry's contract (E-5b, WKE-713, Deliverable 3): a toy second spec
// proves walk() attributes through whichever module the player's own
// COMBATANT_INFO spec ID names, not Restoration's by assumption; an
// unregistered spec refuses with the exact message Decision 3 names; and
// ids() names only the shipped specs until a test registers another.
const test = require('node:test');
const assert = require('node:assert/strict');
const S = require('../support/synth');
const P = require('../lib/parse');
const { walk } = require('../lib/attribute');
const { loadDR } = require('../lib/dr');
const specs = require('../lib/specs');
const toySpec = require('./fixtures/toy-spec');

const dr = loadDR();
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-9, `${msg}: ${a} vs ${b}`);

test('ids() names only the shipped specs when the toy is not registered', () => {
    assert.deepEqual(specs.ids(), [105]);
});

test('a log whose player carries a spec the registry lacks refuses, naming it', () => {
    S.reset();
    const text = [S.challengeStart(10), S.combatant({ int: 1000, crit: 1, haste: 1, mastery: 1, vers: 1, leech: 0, spec: 777 }), S.challengeEnd(10)].join('\n');
    assert.throws(() => walk(P.parseText(text), { dr, player: S.PLAYER }), /^Error: spec 777 is not in tools\/combatlog\/lib\/specs \(known: 105\)$/);
});

test('the toy spec, registered, gives hand-checkable int and mastery gains', () => {
    specs.register(toySpec);
    try {
        S.reset();
        const text = [
            S.challengeStart(10),
            S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69, spec: 999 }),
            // Toy A (9001): int and mastery. 1000 effective: int += 1,
            // mastery += 1000 * 0.1 = 100.
            S.heal({ spellId: 9001, name: 'Toy A', amount: 1000 }),
            // Toy B (9002): int only. 500 effective: int += 0.5, no mastery.
            S.heal({ spellId: 9002, name: 'Toy B', amount: 500 }),
            S.challengeEnd(10),
        ].join('\n');
        const w = walk(P.parseText(text), { dr, player: S.PLAYER });
        assert.equal(w.segments.length, 1);
        const s = w.segments[0].sums;
        assert.equal(w.segments[0].spec, 999);
        near(s.gain.int, 1.5, 'int: 1000/1000 + 500/1000');
        near(s.gain.mastery, 100, 'mastery: 1000 * 0.1 from Toy A only');
        assert.equal(s.gain.crit, 0, 'the toy spec never crits');
        assert.equal(s.gain.hasteTick, 0, 'the toy spec is never hasted');
    } finally {
        specs.unregister(999);
    }
});

test('ids() includes a spec only while it stays registered', () => {
    specs.register(toySpec);
    try {
        assert.deepEqual(specs.ids(), [105, 999]);
    } finally {
        specs.unregister(999);
    }
    assert.deepEqual(specs.ids(), [105]);
});
