'use strict';

// E-3c (WKE-686): the trinket probe over COMMITTED files only - the eight
// committed Upgrade Finder exports fit the bands (the dev weights the game
// ran), week one's stored compare (Lootpath-20261002-112757.lua) is the
// before, week one's trinket rows are spec/fixtures/engine/compare-20260929.lua's,
// and the effects are the shipped Lootpath/Data/EngineEffects.lua. Every
// figure pinned below was read from the probe's own output on these files.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { run, paramsAt, effectAt } = require('../probe-trinkets');
const { readLuaTable } = require('../lib/luatable');

const REPO = path.join(__dirname, '..', '..', '..');
const CAP = (f) => path.join(REPO, 'spec', 'fixtures', 'captures', f);
const STATS = ['Lootpath-20260915-162015.lua', 'Lootpath-20260916-152428.lua', 'Lootpath-20261001-092631.lua', 'Lootpath-20261001-200927.lua'].map(CAP);

let cached = null;
function runOnce() {
    if (cached) return cached;
    const args = ['--key-levels', '1=2,2=4,4=6,6=8,7=10', '--compare', CAP('Lootpath-20261002-112757.lua'), '--week', '2026-09-29', '--char', 'Hotornot - Arthas'];
    for (const s of STATS) args.push('--stats', s);
    args.push(path.join(REPO, 'spec', 'fixtures', 'qe'));
    cached = run(args, () => {});
    return cached;
}

const near = (expected, actual, what) => assert.ok(Math.abs(expected - actual) < 0.0005, `${what}: expected ${expected}, got ${actual}`);
const block = (r, ct, doc) => r.blocks.find((b) => b.contentType === ct && String(b.document) === String(doc));

test('reads the shipped effects table as the Lua module does', () => {
    const t = readLuaTable(fs.readFileSync(path.join(REPO, 'Lootpath', 'Data', 'EngineEffects.lua'), 'utf8'), /^ns\.engineEffects\s*=/m);
    assert.equal(Object.keys(t.items).length, 29);
    // The same figures spec/engineeffects_spec.lua reads from the Lua side.
    assert.deepEqual(paramsAt(t.items['250215'].params, 305), { stat: 'crit', duration: 15, cooldown: 90, amount: 608 });
    assert.equal(paramsAt(t.items['250215'].params, 306), null);
    near(608 * 15 / 90, effectAt(t, 250215, 305).stat.crit, 'flask 305');
    assert.deepEqual(effectAt(t, 274495, 308).stat, { mastery: 92 });
    assert.match(effectAt(t, 250214, 305).why, /not modelled/);
    assert.match(effectAt(t, 250215, 300).why, /no params at 300/);
    assert.match(effectAt(t, 1, 300).why, /not in the effects table/);
});

test('week one: the worn trinkets are generic at their levels and no swap reaches a DR bracket', () => {
    const r = runOnce();
    assert.deepEqual(r.worn.map((w) => `${w.id}@${w.level}`), ['274495@308', '250215@334']);
    assert.deepEqual(r.worn[0].stat, { mastery: 92 });
    near(114.8333, r.worn[1].stat.crit, 'flask 334');
    assert.equal(r.linear, true);
});

test('before: every trinket row not rated; the fixture holds the same count', () => {
    const r = runOnce();
    for (const [ct, doc, n] of [['Dungeon', 6, 12], ['Dungeon', 10, 4], ['Raid', 10, 4]]) {
        const b = block(r, ct, doc);
        assert.equal(b.storedNotRated, n, `${ct} ${doc}`);
        assert.equal(b.storedTrinket, null, `${ct} ${doc}`);
        assert.equal(b.fixtureTrinketRows, n, `${ct} ${doc}`);
    }
});

test('after: one trinket row rated on +6, none elsewhere', () => {
    const r = runOnce();
    const d6 = block(r, 'Dungeon', 6);
    assert.equal(d6.rated.length, 1);
    assert.equal(d6.rated[0].key, '250215@305');
    assert.equal(d6.rated[0].replaced, '250215@334');
    near(-0.8793, d6.rated[0].raw, 'flask 305 raw');
    assert.equal(d6.rated[0].ours, 0);
    assert.equal(d6.rated[0].theirs, 0);
    assert.equal(d6.trinketAfter.n, 1);
    assert.equal(d6.trinketAfter.rho, null);
    assert.equal(d6.trinketAfter.k, null);
    near(0, d6.trinketAfter.mae, 'trinket MAE');
    assert.equal(d6.left.length, 11);
    for (const [ct, doc] of [['Dungeon', 10], ['Raid', 10]]) {
        const b = block(r, ct, doc);
        assert.equal(b.rated.length, 0);
        assert.equal(b.trinketAfter, null);
        assert.equal(b.left.length, 4);
    }
});

test('after: the worn effects scale every other percent and move k, not rho or MAE@k', () => {
    const r = runOnce();
    const d6 = block(r, 'Dungeon', 6);
    near(0.979291, d6.scale, '+6 scale');
    assert.equal(d6.direct, 5);
    assert.ok(d6.maxDirect < 1e-5, `direct: ${d6.maxDirect}`);
    near(0.958, d6.before.armour.k, 'armour k before');
    near(0.979, d6.after.armour.k, 'armour k after');
    for (const b of r.blocks) {
        for (const c of Object.keys(b.before)) {
            assert.equal(b.after[c].rho, b.before[c].rho, `${b.document} ${c} rho`);
            assert.equal(b.after[c].sign, b.before[c].sign, `${b.document} ${c} sign`);
            if (b.before[c].maeK !== null) near(b.before[c].maeK, b.after[c].maeK, `${b.document} ${c} MAE@k`);
        }
    }
});
