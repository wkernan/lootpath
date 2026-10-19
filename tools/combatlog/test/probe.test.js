'use strict';

// The method's constants checked against the fixture's own ticks
// (docs/COMBAT-LOG-WEIGHTS.md §8): the crit multiplier the attribution uses,
// and Harmony's counted list and stack table.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const P = require('../lib/parse');
const { probe } = require('../lib/probe');
const { loadDR } = require('../lib/dr');
const { CONSTANTS } = require('../specs/restoration');

const FIXTURE = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'combatlog', 'WoWCombatLog-20261017-AltarOfFangs-12.txt.gz');
const r = probe(P.parseText(P.readText(FIXTURE)), { dr: loadDR() });

test('the crit multiplier the attribution uses is the one the fixture shows, within 2%', () => {
    assert.ok(r.critMultiplier.pairs >= 100, `pairs ${r.critMultiplier.pairs}`);
    assert.ok(Math.abs(r.critMultiplier.median / CONSTANTS.critMultiplier - 1) < 0.02, `median ${r.critMultiplier.median}`);
});

test("Harmony: ticks at an unchanged count do not move; every change of count moves the tick within 0.04 of the table's prediction", () => {
    assert.ok(r.harmony.length >= 8, `groups ${r.harmony.length}`);
    for (const g of r.harmony) {
        const [from, to] = g.change.split('->');
        if (from === to) assert.ok(Math.abs(g.median - 1) < 1e-9, `${g.change} ${g.median}`);
        else assert.ok(Math.abs(g.median - g.predicted) < 0.04, `${g.change}: ${g.median} vs ${g.predicted}`);
    }
});
