'use strict';

// E-0j (WKE-681): the percent-scale harness over COMMITTED files only - the
// eight committed Upgrade Finder exports fit the bands, the owner's
// 2026-10-01 `capture itemstats` transcript carries the six documents a
// compare read that day and the worn set (inventory snapshot 4). Every figure
// pinned below was read from the harness's own output on these files.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { run, scale, UF_FLOOR } = require('../percent-scale');

const REPO = path.join(__dirname, '..', '..', '..');
const CAP = (f) => path.join(REPO, 'spec', 'fixtures', 'captures', f);
const STATS = ['Lootpath-20260915-162015.lua', 'Lootpath-20260916-152428.lua', 'Lootpath-20261001-092631.lua', 'Lootpath-20261001-200927.lua'].map(CAP);

let cached = null;
function runOnce() {
    if (cached) return cached;
    const args = ['--key-levels', '1=2,2=4,4=6,6=8,7=10', '--measure', CAP('Lootpath-20261001-092631.lua')];
    for (const s of STATS) args.push('--stats', s);
    args.push(path.join(REPO, 'spec', 'fixtures', 'qe'));
    cached = run(args, () => {});
    return cached;
}

const near = (expected, actual, what) => assert.ok(Math.abs(expected - actual) < 0.0005, `${what}: expected ${expected}, got ${actual}`);

test('the harness floors at the same value the compare does', () => {
    const lua = fs.readFileSync(path.join(REPO, 'Lootpath', 'Modules', 'EngineCompare.lua'), 'utf8');
    const m = lua.match(/^EngineCompare\.UF_FLOOR = (-?[\d.]+)/m);
    assert.ok(m, 'EngineCompare.UF_FLOOR is defined');
    assert.equal(Number(m[1]), UF_FLOOR);
});

test('k is the least-squares scale of ours onto theirs', () => {
    const rows = [
        { theirs: 2, ours: 1 },
        { theirs: 4, ours: 2 },
    ];
    assert.equal(scale(rows, (r) => r.ours), 2);
    assert.equal(scale([], (r) => r.ours), null);
});

test('scores the six stored documents against the in-game worn total', () => {
    const r = runOnce();
    assert.equal(r.measured.length, 6);
    const plus6 = r.measured.find((m) => m.contentType === 'Dungeon' && m.keyLevel === 6);
    // EngineCompare's Top Gear line read 119.6-119.8 in game: V(worn) x 1.085.
    near(110.453, plus6.vWorn, '+6 V(worn)');
});

test('unfloored k moves with the band; floored, armour sits near 1 on every band', () => {
    const r = runOnce();
    const by = (ct, level) => r.measured.find((m) => m.contentType === ct && (ct === 'Raid' || m.keyLevel === level));
    near(0.821, by('Dungeon', 6).byClass.armour.game, '+6 armour game');
    near(0.906, by('Dungeon', 10).byClass.armour.game, '+10 armour game');
    near(1.024, by('Dungeon', 6).byClass.armour.floored, '+6 armour floored');
    near(1.011, by('Dungeon', 10).byClass.armour.floored, '+10 armour floored');
    near(0.978, by('Raid').byClass.armour.floored, 'Raid armour floored');
    // Suspect 1: pinning the worn set at 100 moves k AWAY from 1.
    near(0.743, by('Dungeon', 6).byClass.armour.pin100, '+6 armour pin100');
});
