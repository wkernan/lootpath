'use strict';

// E-0k (WKE-682): the tier probe over COMMITTED files only - week one's stored
// compare rows (spec/fixtures/captures/Lootpath-20261002-112757.lua, PR #313),
// the worn set its own `capture itemstats` snapshot read, and for the refit
// the four transcripts and eight exports the dev weights are fitted from.
// Every figure pinned below was read from the probe's own output on these
// files; the stored k / MAE@k are the owner's screen (ARCHITECTURE.md §9,
// 2026-10-02 week one's FINAL compare).
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { run, rescore, multiplierFor, linkModifiers, scale } = require('../probe-tier');

const REPO = path.join(__dirname, '..', '..', '..');
const CAP = (f) => path.join(REPO, 'spec', 'fixtures', 'captures', f);
const STATS = ['Lootpath-20260915-162015.lua', 'Lootpath-20260916-152428.lua', 'Lootpath-20261001-092631.lua', 'Lootpath-20261001-200927.lua'].map(CAP);

let cached = null;
function runOnce() {
    if (cached) return cached;
    const args = ['--compare', CAP('Lootpath-20261002-112757.lua'), '--week', '2026-09-29', '--char', 'Hotornot - Arthas', '--key-levels', '1=2,2=4,4=6,6=8,7=10', '--qe', path.join(REPO, 'spec', 'fixtures', 'qe')];
    for (const s of STATS) args.push('--stats', s);
    cached = run(args, () => {});
    return cached;
}

const near = (expected, actual, what) => assert.ok(actual !== null && Math.abs(expected - actual) < 0.0005, `${what}: expected ${expected}, got ${actual}`);
const doc = (r, ct, d) => r.documents.find((x) => x.contentType === ct && x.document === d);

test('reads the catalyst source off a link (modifier 64, the redirected base stats)', () => {
    const link = '|cnIQ4:|Hitem:271528:7961:240892::::::90:105::35:6:6652:13440:13695:13692:13698:12845:1:64:239033:::::|h[x]|h|r';
    assert.deepEqual(linkModifiers(link), { 64: 239033 });
    assert.deepEqual(linkModifiers('|Hitem:271527:7937:::::::90:105::35:5:13693:13440:6652:13698:12846::::::|h[x]|h'), {});
});

test('the tier rules: forced is 1 + t2 + t4 whatever is worn; counted breaks at 3 pieces', () => {
    const four = [1, 2, 3, 4].map(() => ({ setID: 2057 }));
    const three = four.slice(1);
    near(1.085, multiplierFor('additive-forced', three, 0.03, 0.055), 'forced, 3 worn');
    near(1.085, multiplierFor('additive-counted', four, 0.03, 0.055), 'counted, 4 worn');
    near(1.03, multiplierFor('additive-counted', three, 0.03, 0.055), 'counted, 3 worn');
    near(1.03 * 1.055, multiplierFor('multiplicative-forced', three, 0.03, 0.055), 'multiplicative, forced');
});

test('a forced multiplier of any size leaves the percent where it was', () => {
    const worn = { Chest: { setID: 2057 }, Head: { setID: 2057 }, Hands: { setID: 2057 }, Legs: { setID: 2057 }, Shoulder: { setID: 0 } };
    const row = { slot: 'Chest', raw: 1.134 };
    for (const t of [0, 0.03, 0.15]) near(1.134, rescore(row, worn, 'additive-forced', t, t), `forced at ${t}`);
    // Counted, the chest swap loses the 4-piece and the percent goes below 0.
    assert.equal(rescore(row, worn, 'additive-counted', 0.03, 0.055), 0);
});

test('reproduces the screen: tier and armour k / MAE@k per band from the stored rows', () => {
    const r = runOnce();
    assert.equal(r.documents.length, 3);
    near(1.278, doc(r, 'Dungeon', '6').stored.tier.k, '+6 tier k');
    near(0.042, doc(r, 'Dungeon', '6').stored.tier.maeK, '+6 tier MAE@k');
    near(0.958, doc(r, 'Dungeon', '6').stored.armour.k, '+6 armour k');
    near(1.119, doc(r, 'Dungeon', '10').stored.tier.k, '+10 tier k');
    near(1.136, doc(r, 'Raid', '10').stored.tier.k, 'Raid tier k');
    near(0.960, doc(r, 'Raid', '10').stored.armour.k, 'Raid armour k');
    assert.equal(doc(r, 'Dungeon', '6').stored.tier.n, 19);
});

test('suspects 1 and 3: no forced multiplier, added or multiplied, moves tier k', () => {
    const r = runOnce();
    for (const d of r.documents) {
        for (const rule of ['additive-forced', 'multiplicative-forced']) {
            near(d.stored.tier.k, d.rules[rule].kMin, `${d.contentType} ${d.document} ${rule} min`);
            near(d.stored.tier.k, d.rules[rule].kMax, `${d.contentType} ${d.document} ${rule} max`);
        }
    }
});

test('suspect 2: counting pieces floors every catalysed-slot row and moves k away', () => {
    const r = runOnce();
    const plus6 = doc(r, 'Dungeon', '6').rules['additive-counted'].atFit;
    near(0.371, plus6.k, '+6 counted k');
    near(0.169, plus6.maeK, '+6 counted MAE@k');
    assert.equal(doc(r, 'Raid', '10').rules['additive-counted'].atFit.k, null);
});

test('suspect 4: the gap follows the worn piece the row replaces', () => {
    const r = runOnce();
    assert.equal(r.worn.slots.Head.catalysedFrom, 239033);
    assert.equal(r.worn.slots.Chest.catalysedFrom, 251226);
    assert.equal(r.worn.slots.Hands.catalysedFrom, 159337);
    assert.equal(r.worn.slots.Legs.catalysedFrom, null);
    assert.equal(r.worn.slots.Shoulder.setID, 0);
    const p = doc(r, 'Dungeon', '6');
    near(1.279, p.byKind['catalysed tier'].k, '+6 catalysed-slot k');
    near(0.371, p.byKind['non-tier'].k, '+6 non-tier (shoulder) k');
    near(0.113, p.byWorn.Head.offset, '+6 head offset');
    near(0.319, p.byWorn.Chest.offset, '+6 chest offset');
    near(0.133, p.byWorn.Hands.offset, '+6 hands offset');
    near(-0.031, p.byWorn.Shoulder.offset, '+6 shoulder offset');
});

test('refit: a band fitted on the measured document itself still leaves tier k apart from armour', () => {
    const r = runOnce();
    const plus6 = r.refit.find((x) => x.contentType === 'Dungeon' && x.keyLevel === 6);
    near(1.564, plus6.dev.tier.k, '+6 dev tier k (offline)');
    near(1.174, plus6.inSample.tier.k, '+6 in-sample tier k');
    near(0.945, plus6.inSample.armour.k, '+6 in-sample armour k');
});

test('k is the least-squares scale of ours onto theirs', () => {
    assert.equal(
        scale([
            { theirs: 2, ours: 1 },
            { theirs: 4, ours: 2 },
        ]),
        2,
    );
    assert.equal(scale([]), null);
});
