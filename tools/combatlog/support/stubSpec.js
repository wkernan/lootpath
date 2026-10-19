// A synthetic second healer spec, registered only inside a test (E-5b,
// WKE-713 rework). It proves attribute.js and entry.js dispatch a spec
// module by ID rather than assuming Restoration's; its spells, buffs and
// constants are deliberately unlike hers, not a guess at a real class's.
'use strict';

function makeStubSpec(specID) {
    return {
        specID,
        role: 'HEALER',
        primaryStat: 'int',
        stats: ['int', 'vers'],
        tracked: () => false,
        // Every heal moves Intellect and versatility only - never crit, a
        // tick, a cast, or mastery - so a segment attributed through this
        // module looks nothing like one attributed through Restoration's
        // table, even over the same spell IDs.
        spellRow: () => ({ kind: 'coefficient', int: true, crit: false, tick: false, cast: false, mastery: false, vers: true }),
        HARMONY: new Set(),
        stackFactor: () => 0,
        CONSTANTS: { critMultiplier: 2, harmonyCoefficient: 0, masteryBase: 0 },
        PERCENT_BUFFS: {},
        UNSIZED_BUFFS: {},
    };
}

module.exports = { makeStubSpec };
