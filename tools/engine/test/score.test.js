'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fixture = require('./fixtures/score-fixture.json');
const score = require('../lib/score');
const { DEFAULT_DR, ratingToPercent } = require('../lib/dr');

const model = { ...fixture.model, dr: DEFAULT_DR };
const close = (a, b, eps, msg) => assert.ok(Math.abs(a - b) <= (eps || 1e-9), `${msg || ''} ${a} vs ${b}`);

test('DR: rating below the first bracket counts in full, inside it at -10%', () => {
    close(ratingToPercent(1320, DEFAULT_DR.haste), 30);
    // 1320 in full + 440 at 90% = 1716 effective -> 39.0%
    close(ratingToPercent(1760, DEFAULT_DR.haste), 39);
    // 1760 -> 2200 at 80%: + 352 -> 2068 / 44 = 47.0
    close(ratingToPercent(2200, DEFAULT_DR.haste), 47);
    close(ratingToPercent(1380, DEFAULT_DR.crit), 30);
    close(ratingToPercent(1620, DEFAULT_DR.vers), 30);
    close(ratingToPercent(690, DEFAULT_DR.leech), 10);
    close(ratingToPercent(0, DEFAULT_DR.haste), 0);
});

test('DR is monotonic and never gains past a bracket', () => {
    let prev = -1;
    for (let r = 0; r <= 12000; r += 7) {
        const p = ratingToPercent(r, DEFAULT_DR.haste);
        assert.ok(p >= prev, `haste ${r}`);
        prev = p;
    }
});

test('the fixture worn set: features and value, checked by hand', () => {
    const x = score.features(score.totals(fixture.worn, model.assumedFinish), DEFAULT_DR);
    for (const k of score.STATS) close(x[k], fixture.expected.wornFeatures[k], 1e-9, k);
    // By hand: int 200+150+600+100 = 1050; haste (300+400+50)/44; crit 500/46;
    // mastery 1200/46; vers 400/54; none past a bracket.
    const linear = 1000 + 1050 + (20 * 750) / 44 + (15 * 500) / 46 + (18 * 1200) / 46 + (12 * 400) / 54;
    close(score.setValue(fixture.worn, model), linear * 1.085, 1e-9, 'by hand');
    close(score.setValue(fixture.worn, model), fixture.expected.wornValue, 1e-9, 'fixture');
});

test('the fixture cases: percent, the clamp, the swap chosen', () => {
    for (const c of fixture.cases) {
        const r = score.upgrade(fixture.worn, c.item, model);
        assert.equal(r.comparable, c.comparable, c.name);
        if (!c.comparable) continue;
        assert.deepEqual(r.replaced, c.replaced, c.name);
        close(r.percent, c.percent, 1e-9, c.name);
        close(r.clampedPercent, c.clampedPercent, 1e-9, c.name);
    }
});

test('the DR-crossing ring, by hand', () => {
    // Replacing the crit/vers ring: haste 750 - 0 + 1000 = 1750 -> 1320 + 430 * 0.9
    const haste = (1320 + 430 * 0.9) / 44;
    const linear = 1000 + 1050 + 20 * haste + (15 * 300) / 46 + (18 * 1200) / 46 + (12 * 100) / 54;
    const pct = (100 * (linear * 1.085 - fixture.expected.wornValue)) / fixture.expected.wornValue;
    close(pct, fixture.cases[0].percent, 1e-9);
});

test('SIGN: a better item is positive, a worse one negative (the Upgrade Finder convention)', () => {
    assert.ok(score.upgrade(fixture.worn, fixture.cases[0].item, model).percent > 0);
    assert.ok(score.upgrade(fixture.worn, fixture.cases[4].item, model).percent < 0);
});

test('tier: forced on is the full multiplier; counted otherwise', () => {
    const tiers = { setIDs: [2057], twoPiece: 0.03, fourPiece: 0.055 };
    close(score.tierMultiplier([], tiers), 1.085);
    const counted = { ...tiers, forceTier: false };
    const piece = { setId: 2057 };
    close(score.tierMultiplier([piece], counted), 1);
    close(score.tierMultiplier([piece, piece], counted), 1.03);
    close(score.tierMultiplier([piece, piece, piece, piece], counted), 1.085);
});
