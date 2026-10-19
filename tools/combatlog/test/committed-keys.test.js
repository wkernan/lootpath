'use strict';

// E-5c (WKE-714): pins the Restoration weights the six committed +12 keys
// under spec/fixtures/combatlog/ produce, so a change to the method, the
// estimator or the spell table that moves them fails CI loudly rather than
// silently. Measured at main 0f230fe, 2026-10-19, by re-running:
//
//   node weights.js ../../spec/fixtures/combatlog/WoWCombatLog-20261017-AltarOfFangs-12.txt.gz ../../spec/fixtures/combatlog/WoWCombatLog-20261018-VoidscarArena-12.txt.gz ../../spec/fixtures/combatlog/WoWCombatLog-20261018-RubyLifePools-12.txt.gz ../../spec/fixtures/combatlog/WoWCombatLog-20261018-MurderRow-12.txt.gz ../../spec/fixtures/combatlog/WoWCombatLog-20261018-BlindingVale-12.txt.gz ../../spec/fixtures/combatlog/WoWCombatLog-20261018-KingsRest-12.txt.gz --player Player-69-0CC01A11 --patch 12.1.5 --derived-at 2026-10-19T00:00:00Z --out /tmp/e5six
//
// If the change is intended, re-run the command above, update the figures
// in this file, and say why in the PR.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const weights = require('../weights');

const REPO = path.join(__dirname, '..', '..', '..');
const FIXTURES = path.join(REPO, 'spec', 'fixtures', 'combatlog');
const LOGS = [
    'WoWCombatLog-20261017-AltarOfFangs-12.txt.gz',
    'WoWCombatLog-20261018-VoidscarArena-12.txt.gz',
    'WoWCombatLog-20261018-RubyLifePools-12.txt.gz',
    'WoWCombatLog-20261018-MurderRow-12.txt.gz',
    'WoWCombatLog-20261018-BlindingVale-12.txt.gz',
    'WoWCombatLog-20261018-KingsRest-12.txt.gz',
].map((f) => path.join(FIXTURES, f));

const MOVED = "the six committed keys' weights moved; if the change is intended, re-run the command in this file's header, update the figures, and say why in the PR";

function run() {
    const out = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-combatlog-six-'));
    return weights.run([...LOGS, '--player', 'Player-69-0CC01A11', '--patch', '12.1.5', '--derived-at', '2026-10-19T00:00:00Z', '--out', out], () => {});
}
const entry = run().entry;
const band = entry.Dungeon.bands['12'];

test('the six keys: 48 segments, 3 dropped, the event counts and overheal share', () => {
    assert.deepStrictEqual(
        {
            logs: entry.logs.length,
            segments: band.segments,
            segmentsDropped: entry.segmentsDropped,
            events: band.events,
            eventsWithoutOverheal: band.eventsWithoutOverheal,
            overhealShare: band.overhealShare,
        },
        { logs: 6, segments: 48, segmentsDropped: 3, events: 149932, eventsWithoutOverheal: 63559, overhealShare: 0.5019 },
        MOVED
    );
});

test('the six keys: weights, intervals, per-rating-point figures, haste cast form and baseValue', () => {
    assert.deepStrictEqual(
        { weights: band.weights, intervals: band.intervals, perRatingPoint: band.perRatingPoint, hasteCastForm: band.hasteCastForm, baseValue: band.baseValue },
        {
            weights: { int: 0.027385599, haste: 0.274443185, crit: 0.588377794, mastery: 0.879046407, vers: 0.809238607, leech: 0.539794822 },
            intervals: {
                int: { lo: 0.027385599, hi: 0.027385599 },
                haste: { lo: 0.264829588, hi: 0.284889909 },
                crit: { lo: 0.579894529, hi: 0.596714766 },
                mastery: { lo: 0.846820938, hi: 0.907649839 },
                vers: { lo: 0.803285831, hi: 0.815786842 },
                leech: { lo: 0.482254359, hi: 0.588683811 },
            },
            perRatingPoint: {
                int: { mean: 1, lo: 1, hi: 1 },
                haste: { mean: 0.22776, lo: 0.219782, hi: 0.23643 },
                crit: { mean: 0.467064, lo: 0.46033, hi: 0.473682 },
                mastery: { mean: 0.697801, lo: 0.67222, hi: 0.720507 },
                vers: { mean: 0.547218, lo: 0.543193, hi: 0.551646 },
                leech: { mean: 0.285665, lo: 0.255214, hi: 0.311538 },
            },
            hasteCastForm: { perPercent: 0.547202563, perRatingPoint: { mean: 0.454123, lo: 0.448667, hi: 0.45977 } },
            baseValue: -24.650386725,
        },
        MOVED
    );
});

test('the six keys: per-rating-point ranks mastery > vers > crit > leech > haste, and no neighbour in rank overlaps - so nothing is unshipped', () => {
    assert.equal(band.unshipped, undefined, MOVED);
    const ranked = Object.entries(band.perRatingPoint)
        .filter(([k]) => k !== 'int')
        .sort((a, b) => b[1].mean - a[1].mean);
    assert.deepStrictEqual(ranked.map(([k]) => k), ['mastery', 'vers', 'crit', 'leech', 'haste'], MOVED);
    for (let i = 0; i < ranked.length - 1; i++) {
        const [, a] = ranked[i];
        const [, b] = ranked[i + 1];
        assert.ok(!(a.lo <= b.hi && b.lo <= a.hi), `${MOVED} (${ranked[i][0]}/${ranked[i + 1][0]} now overlap)`);
    }
});
