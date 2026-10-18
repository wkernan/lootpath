'use strict';

// The attribution over a tiny synthetic log whose totals are worked by hand
// (docs/COMBAT-LOG-WEIGHTS.md §6). The player: Intellect 1,000; crit 460,
// haste 440, mastery 460, versatility 540, leech 69 - every one below its
// first bracket, so 10% crit, 10% haste, 10 mastery points (18 with the base
// 8), 10% versatility, 1% leech.
const test = require('node:test');
const assert = require('node:assert/strict');
const S = require('../support/synth');
const P = require('../lib/parse');
const { walk, segmentWeights } = require('../lib/attribute');
const { loadDR } = require('../lib/dr');

const dr = loadDR();
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-9, `${msg}: ${a} vs ${b}`);

function baseLog(extra) {
    S.reset();
    return [
        S.challengeStart(10),
        S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69 }),
        S.cast(774, 1000),
        S.aura('APPLIED', 774),
        // Rejuvenation ticks for 1,000, no overheal, no crit; Harmony count 1.
        S.heal({ spellId: 774, name: 'Rejuvenation', periodic: true, amount: 1000 }),
        // Regrowth's direct heal crits for 2,000 (1,000 without the crit).
        S.heal({ spellId: 8936, name: 'Regrowth', amount: 2000, crit: true }),
        // An overhealed tick: worth nothing to any stat.
        S.heal({ spellId: 774, name: 'Rejuvenation', periodic: true, amount: 500, overheal: 100 }),
        // Leech: 69 effective at 1% leech.
        S.heal({ spellId: 143924, name: 'Leech', dst: S.PLAYER, dstName: S.PLAYER_NAME, amount: 69 }),
        // Everbloom, a share of the bloom: Intellect, versatility, haste cast form.
        S.heal({ spellId: 1244341, name: 'Everbloom', amount: 300 }),
        ...(extra || []),
        S.challengeEnd(10),
    ].join('\n');
}

const run = (text, opts) => walk(P.parseText(text), { dr, ...(opts || {}) });

test('the hand-worked totals: every stat of every event, one segment', () => {
    const w = run(baseLog());
    assert.equal(w.player, S.PLAYER);
    assert.equal(w.segments.length, 1);
    const s = w.segments[0].sums;
    assert.equal(s.events, 5);
    assert.equal(s.overhealEvents, 1);
    assert.equal(s.leechEvents, 1);
    near(s.effective, 1000 + 2000 + 400 + 69 + 300, 'effective');
    // Intellect: (1000 + 2000 + 300) / 1000.
    near(s.gain.int, 3.3, 'int');
    // Versatility: 3300 / 1.10 / 100.
    near(s.gain.vers, 30, 'vers');
    // Crit: (1000 + 2000 / 2) x (2 - 1) / 100; Everbloom cannot crit.
    near(s.gain.crit, 20, 'crit');
    // Haste, tick form: the one tick, 1000 / 1.10 / 100.
    near(s.gain.hasteTick, 1000 / 1.1 / 100, 'haste tick');
    // Haste, cast form: all three cast-scaled heals, 3300 / 1.10 / 100.
    near(s.gain.hasteCast, 30, 'haste cast');
    // Mastery: (1000 + 2000) x 0.01311 x T(1) / (1 + 18 x 0.01311 x T(1)).
    near(s.gain.mastery, (3000 * 0.01311) / (1 + 18 * 0.01311), 'mastery');
    near(s.leechEffective, 69, 'leech');

    const sw = segmentWeights(w.segments[0], dr);
    near(sw.perPercent.leech, 69, 'leech per percent');
    // Per rating point relative to Intellect: versatility 30 x (1/54) / 3.3.
    near(sw.relative.vers, 30 / 54 / 3.3, 'vers relative');
    near(sw.relative.haste, (1000 / 1.1 / 100 / 44) / 3.3, 'haste relative');
    near(sw.relative.int, 1, 'int relative');
});

test('Mark of the Wild adds 3% versatility: the denominator moves to 1.13', () => {
    S.reset();
    const text = [
        S.challengeStart(10),
        S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69, auras: [{ caster: S.ALLY, spellId: 1126 }] }),
        S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1130 }),
        S.challengeEnd(10),
    ].join('\n');
    near(run(text).segments[0].sums.gain.vers, 1130 / 1.13 / 100, 'vers with the buff');
});

test("Harmony's count follows the player's auras: removed means no mastery gain", () => {
    S.reset();
    const text = [
        S.challengeStart(10),
        S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69 }),
        S.aura('APPLIED', 774),
        S.aura('APPLIED', 155777),
        S.aura('APPLIED', 33763),
        S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1000 }),
        S.aura('REMOVED', 774),
        S.aura('REMOVED', 155777),
        S.aura('REMOVED', 33763),
        S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1000 }),
        // Another druid's Rejuvenation is not hers.
        S.aura('APPLIED', 774, { src: 'Player-3-0000CCCC' }),
        S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1000 }),
        S.challengeEnd(10),
    ].join('\n');
    const s = run(text).segments[0].sums;
    // Only the first heal, with three effects: T(3) = 2.3.
    near(s.gain.mastery, (1000 * 0.01311 * 2.3) / (1 + 18 * 0.01311 * 2.3), 'mastery at three');
});

test('a spell not in the table counts for crit and versatility only', () => {
    S.reset();
    const text = [S.challengeStart(10), S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69 }), S.heal({ spellId: 99999999, name: 'Mystery', amount: 1100 }), S.challengeEnd(10)].join('\n');
    const s = run(text).segments[0].sums;
    near(s.gain.int, 0, 'int');
    near(s.gain.vers, 10, 'vers');
    near(s.gain.crit, 11, 'crit');
    near(s.gain.hasteCast, 0, 'haste');
    near(s.gain.mastery, 0, 'mastery');
    assert.deepEqual(Object.keys(s.unknown), ['99999999']);
});

test('segments: trash, the boss, trash; a guardian heal is counted and valued nowhere', () => {
    const text = baseLog([S.encounterStart('Boss'), S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1000 }), S.heal({ spellId: 422090, name: 'Nourish', src: 'Creature-0-1-2-3-54983-0000000001', srcName: 'Treant', srcFlags: '0x2111', amount: 777 }), S.encounterEnd('Boss'), S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1000 })]);
    const w = run(text);
    assert.deepEqual(
        w.segments.map((s) => `${s.kind}:${s.name}:${s.band}:${s.sums.events}`),
        ['trash:Test Grove +10 trash:10:5', 'boss:Boss:10:1', 'trash:Test Grove +10 trash:10:1']
    );
    assert.equal(w.segments[1].sums.guardianEffective, 777);
    near(w.segments[1].sums.gain.int, 1, 'boss int');
});

test('the player must be named when no COMBATANT_INFO names a healing spec once', () => {
    S.reset();
    const text = [S.challengeStart(10), S.combatant({ int: 1000, crit: 1, haste: 1, mastery: 1, vers: 1, leech: 0, spec: 103 }), S.challengeEnd(10)].join('\n');
    assert.throws(() => run(text), /name the player with --player/);
});

test("her Intellect at an event is the last spell power her advanced block read", () => {
    S.reset();
    const text = [
        S.challengeStart(10),
        S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69 }),
        S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1000 }),
        S.cast(18562, 2000),
        S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1000 }),
        S.challengeEnd(10),
    ].join('\n');
    const w = run(text);
    near(w.segments[0].sums.gain.int, 1000 / 1000 + 1000 / 2000, 'int across the reading');
    assert.deepEqual(w.diag.intValues, [2000]);
});

test('a hasted tick of a spell with a cooldown counts in both haste forms; its direct cousin in neither', () => {
    S.reset();
    const text = [
        S.challengeStart(10),
        S.combatant({ int: 1000, crit: 460, haste: 440, mastery: 460, vers: 540, leech: 69 }),
        // Wild Growth ticks (173; a 10 s cooldown, so not cast-scaled itself).
        S.heal({ spellId: 48438, name: 'Wild Growth', periodic: true, amount: 1100 }),
        // Efflorescence: every pulse is hasted (81262 has 173).
        S.heal({ spellId: 81269, name: 'Efflorescence', amount: 1100 }),
        // Swiftmend: a charge, no tick: neither form.
        S.heal({ spellId: 18562, name: 'Swiftmend', amount: 1100 }),
        S.challengeEnd(10),
    ].join('\n');
    const s = run(text).segments[0].sums;
    near(s.gain.hasteTick, 20, 'tick form: 2200 / 1.10 / 100');
    near(s.gain.hasteCast, 20, 'cast form: the same two');
});
