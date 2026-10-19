// A test-only second spec (Decision 6, WKE-713): proves lib/specs/index.js's
// registry contract - identity, spellRow/ROWS/UNKNOWN, constants, buffs,
// mastery - without a real second spec's data. Two spells; a mastery that
// multiplies every heal's effective amount by a constant, needing no
// tracker state at all. Register only inside a test, with
// lib/specs/index.js's register(), and unregister() when done - never add
// this to the shipped registry.
'use strict';

const ROWS = [
    { id: 9001, name: 'Toy A', kind: 'toy', int: true, mastery: true, crit: false, tick: false, cast: false, vers: false },
    { id: 9002, name: 'Toy B', kind: 'toy', int: true, mastery: false, crit: false, tick: false, cast: false, vers: false },
];
const SPELLS = new Map(ROWS.map((r) => [r.id, r]));
const UNKNOWN = Object.freeze({ id: null, name: '(not in the table)', kind: 'unknown', int: false, crit: false, tick: false, cast: false, mastery: false, vers: false });

function spellRow(id) {
    return SPELLS.get(id) || UNKNOWN;
}

// Every heal that moves mastery gains this fraction of its effective amount,
// flat - no stacking aura, no target-dependent state, so the tracker below
// is interface-only.
const MASTERY_MULTIPLIER = 0.1;

function createTracker() {
    return {
        onCombatantInfo() {},
        onAura() {},
        onUnitDied() {},
        diag() {
            return {};
        },
    };
}

function gain(E) {
    return E * MASTERY_MULTIPLIER;
}

module.exports = {
    identity: Object.freeze({
        specID: 999,
        name: 'Toy',
        role: 'HEALER',
        primaryStat: 'int',
        stats: Object.freeze(['int', 'haste', 'crit', 'mastery', 'vers', 'leech']),
    }),
    spellRow,
    ROWS,
    UNKNOWN,
    constants: Object.freeze({ critMultiplier: 2 }),
    buffs: Object.freeze({ percent: {}, unsized: {}, hastePercent: {}, amount: {}, tracked: () => false }),
    mastery: Object.freeze({ createTracker, gain }),
    MASTERY_MULTIPLIER,
};
