'use strict';

// E-0l (WKE-683): the jewellery probe over COMMITTED files only - the eight
// committed Upgrade Finder exports fit the bands (the dev weights the game
// ran, as percent-scale.test.js does), and week one's stored compare rows
// (spec/fixtures/captures/Lootpath-20261002-112757.lua, PR #313) are probed.
// Every figure pinned below was read from the probe's own output on these
// files.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { run, metrics } = require('../probe-jewellery');
const score = require('../lib/score');

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

test('the metric port uses the compare\'s own fixed numbers', () => {
    const lua = fs.readFileSync(path.join(REPO, 'Lootpath', 'Modules', 'EngineCompare.lua'), 'utf8');
    const src = fs.readFileSync(path.join(__dirname, '..', 'probe-jewellery.js'), 'utf8');
    for (const name of ['UF_FLOOR', 'DEAD_ZONE', 'TOP1_WITHIN', 'MIN_RHO_N']) {
        const l = lua.match(new RegExp(`^EngineCompare\\.${name} = (-?[\\d.]+)`, 'm'));
        const j = src.match(new RegExp(`^const ${name} = (-?[\\d.]+);`, 'm'));
        assert.ok(l && j, `${name} is defined on both sides`);
        assert.equal(Number(j[1]), Number(l[1]), name);
    }
});

test('reproduces the game: the stored raws and the stored metrics', () => {
    const r = runOnce();
    assert.equal(r.reproduce.linkRows, 9);
    assert.ok(r.reproduce.maxDiff < 1e-5, `raw: ${r.reproduce.maxDiff}`);
    assert.ok(r.reproduce.maxMetricDiff < 1e-12, `metrics: ${r.reproduce.maxMetricDiff}`);
    const plus6 = r.suspects['Dungeon 6'];
    near(0.594, plus6.stored.rho, '+6 jewellery rho');
    near(0.559, plus6.stored.k, '+6 jewellery k');
    near(0.12, plus6.stored.maeK, '+6 jewellery MAE@k');
});

test('recovers each jewellery read from its stored raws, checked on the one a transcript read', () => {
    const r = runOnce();
    const by = Object.fromEntries(r.recovered.filter((x) => x.documents > 1).map((x) => [x.key, x]));
    assert.deepEqual(Object.keys(by).sort(), ['268249@324', '268250@321', '268251@324', '268252@324', '268266@318']);
    for (const x of Object.values(by)) assert.ok(x.identified, `${x.key} identified`);
    // The check: 268252@324 was read by `capture linklevel`.
    assert.equal(by['268252@324'].read.haste, 63);
    assert.equal(by['268252@324'].read.crit, 319);
    assert.equal(by['268252@324'].stats.haste, 63);
    assert.equal(by['268252@324'].stats.crit, 319);
    assert.deepEqual(by['268250@321'].pair, ['haste', 'crit']);
    assert.equal(by['268250@321'].stats.haste, 288);
    assert.equal(by['268250@321'].stats.crit, 88);
    assert.deepEqual(by['268251@324'].pair, ['haste', 'mastery']);
    assert.equal(by['268251@324'].stats.mastery, 325);
    assert.deepEqual(by['268249@324'].pair, ['crit', 'mastery']);
    assert.equal(by['268249@324'].stats.mastery, 314);
    assert.deepEqual(by['268266@318'].pair, ['haste', 'vers']);
    assert.equal(by['268266@318'].stats.vers, 81);
    assert.equal(r.recovered.filter((x) => x.documents === 1).length, 11);
});

test('suspect 1, sockets: no gem term in any band, so zeroing it moves nothing', () => {
    const r = runOnce();
    for (const S of Object.values(r.suspects)) {
        assert.equal(S.sockets.gemVector, null);
        assert.equal(S.sockets.maxMove, 0);
    }
});

test('suspect 2, the pair: the lower copy of a worn ring takes that copy\'s place, and +6 moves', () => {
    const r = runOnce();
    const plus6 = r.suspects['Dungeon 6'];
    assert.equal(plus6.pair.twins.length, 1);
    const t = plus6.pair.twins[0];
    assert.equal(t.key, '252258@305');
    assert.deepEqual(t.replacedBefore, ['279010@292']);
    assert.deepEqual(t.replacedAfter, ['252258@321']);
    assert.ok(t.after < 0, `with the rule: ${t.after}`);
    assert.equal(t.theirs, 0);
    near(0.678, plus6.pair.metrics.rho, '+6 rho with the rule');
    near(0.584, plus6.pair.metrics.k, '+6 k with the rule');
    near(0.112, plus6.pair.metrics.maeK, '+6 MAE@k with the rule');
    assert.equal(r.suspects['Dungeon 10'].pair.twins.length, 0);
    assert.equal(r.suspects['Raid 10'].pair.twins.length, 0);
});

test('suspect 3, the mix: the worn totals sit below every DR bracket; the refit with the recovered reads moves k toward 1', () => {
    const r = runOnce();
    for (const k of ['haste', 'crit', 'mastery', 'vers']) near(1, r.dr[k].marginal, `${k} marginal`);
    near(0.587, r.suspects['Dungeon 6'].mix.harness.k, '+6 harness k');
    near(1.018, r.suspects['Dungeon 6'].mix.refit.k, '+6 refit k');
    near(0.908, r.suspects['Dungeon 10'].mix.refit.k, '+10 refit k');
    near(0.679, r.suspects['Raid 10'].mix.refit.k, 'Raid refit k');
    near(0.7, r.suspects['Dungeon 6'].mix.refit.rho, '+6 refit rho');
    near(1.004, r.suspects['Dungeon 10'].mix.equalSecondaries.k, '+10 equal k');
    near(-0.4, r.suspects['Dungeon 10'].mix.equalSecondaries.rho, '+10 equal rho');
});

test('suspect 4, the level: every jewellery row was read at its key\'s level', () => {
    const r = runOnce();
    for (const S of Object.values(r.suspects)) {
        assert.deepEqual(S.level.offLevel, []);
        assert.deepEqual(S.level.noStep, []);
    }
});

test('the metric port: ties share ranks, under five rows there is no rho', () => {
    const m = metrics([
        { key: 'a', slot: 'Neck', ours: 0, theirs: 0 },
        { key: 'b', slot: 'Neck', ours: 0, theirs: 0.5 },
        { key: 'c', slot: 'Neck', ours: 1, theirs: 1 },
        { key: 'd', slot: 'Neck', ours: 2, theirs: 2 },
    ]);
    assert.equal(m.rho, null);
    assert.equal(m.top1, 1);
    assert.equal(m.k, (0.5 * 0 + 1 + 4) / 5);
});

test('score.js: a paired slot never holds two copies of one item', () => {
    const worn = [
        { id: 1, slot: 'Finger', stats: { haste: 300 } },
        { id: 2, slot: 'Finger', stats: { haste: 100 } },
        { id: 3, slot: 'Trinket', stats: { int: 50 } },
        { id: 4, slot: 'Trinket', stats: { int: 10 } },
        { id: 5, slot: 'Neck', stats: { crit: 100 } },
    ];
    assert.deepEqual(score.candidates(worn, { id: 1, slot: 'Finger', stats: {} }).map((c) => c.replaced), [[0]]);
    assert.deepEqual(score.candidates(worn, { id: 9, slot: 'Finger', stats: {} }).map((c) => c.replaced), [[0], [1]]);
    assert.deepEqual(score.candidates(worn, { id: 3, slot: 'Trinket', stats: {} }).map((c) => c.replaced), [[2]]);
    // A neck is one slot: the rule has nothing to narrow.
    assert.deepEqual(score.candidates(worn, { id: 5, slot: 'Neck', stats: {} }).map((c) => c.replaced), [[4]]);
});
