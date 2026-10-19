'use strict';

// The spell table (lib/spells.js) against the client data it was read from,
// spec/fixtures/combatlog/simc-spells-70391.txt: every coefficient, every
// crit, haste and modifier flag, Harmony's label list, and the base mastery
// recomputed from the owner's committed transcript.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { ROWS, HARMONY_IDS, CONSTANTS, PERCENT_BUFFS, AMOUNT_BUFFS, stackFactor } = require('../lib/spells');

const FIX = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures');
const DUMP = fs.readFileSync(path.join(FIX, 'combatlog', 'simc-spells-70391.txt'), 'utf8');
const blocks = new Map();
for (const part of DUMP.split(/^######## /m).slice(1)) {
    const m = /^spell\.id=(\d+)\n/.exec(part);
    if (m) blocks.set(Number(m[1]), part);
}
const block = (id) => {
    assert.ok(blocks.has(id), `no spell_query for ${id} in the dump`);
    return blocks.get(id);
};
const attrs = (id) => (/^Attributes\s+:\s+(.*)$/m.exec(block(id)) || [, ''])[1];
const has = (id, n) => new RegExp(`\(${n}\)`).test(attrs(id));

test('the dump is SimC 1210-01 over game data 12.1.5.70391', () => {
    assert.match(DUMP, /SimC 1210-01, git 2358079, game data 12\.1\.5\.70391/);
});

test('every coefficient in the table is the dump\'s', () => {
    for (const r of ROWS) {
        if (!r.coefficient) continue;
        const coeffs = [...block(r.id).matchAll(/SP Coefficient: ([\d.]+)/g)].map((m) => Number(m[1]));
        for (const v of Object.values(r.coefficient)) assert.ok(coeffs.includes(v), `${r.name} ${r.id}: ${v} not in ${coeffs}`);
    }
});

test("crit: no row that can crit carries Can't Crit (93); a ticking row that crits carries 265", () => {
    for (const r of ROWS) {
        if (r.kind === 'leech') continue;
        if (r.crit) assert.ok(!has(r.id, 93), `${r.name} ${r.id} carries 93`);
        else if (!(r.why && r.why.crit)) assert.ok(has(r.id, 93), `${r.name} ${r.id} is marked no crit without 93`);
        if (r.crit && r.coefficient && r.coefficient.periodic) assert.ok(has(r.id, 265), `${r.name} ${r.id} ticks crit without 265`);
    }
    assert.ok(!has(1287665, 265), 'Rune of Lingering has no 265');
});

test('haste, tick: exactly the rows whose spell (or pulse) carries 173', () => {
    for (const r of ROWS) {
        if (r.kind === 'leech') continue;
        if (r.tick === 'periodic') assert.ok(has(r.id, 173), `${r.name}`);
        if (r.tick === 'all') assert.ok(has(81262, 173) && r.id === 81269, `${r.name}`);
        if (!r.tick && r.coefficient && r.coefficient.periodic) assert.ok(!has(r.id, 173), `${r.name} ticks hasted but is marked not`);
    }
});

test('haste, cast: no row marked cast has a cooldown, a charge or a Limit; Wild Growth and Swiftmend do', () => {
    for (const r of ROWS) {
        if (!r.cast) continue;
        const b = block(r.parent && !/GCD|Cast Time/.test(block(r.id)) ? r.parent : r.id);
        assert.ok(!/^Cooldown\s+:/m.test(b) && !/^Charges\s+:/m.test(b), `${r.name}`);
    }
    assert.match(block(48438), /^Cooldown\s+: 10 seconds/m);
    assert.match(block(18562), /^Charges\s+: 1 \(15 seconds cooldown\)/m);
    assert.ok(has(1232285, 165), 'Efflorescence cast has Limit N');
});

test('mastery and versatility: a row without them carries 125, 219 or 312', () => {
    for (const r of ROWS) {
        if (r.kind === 'leech') continue;
        const ignores = has(r.id, 125) || has(r.id, 219) || has(r.id, 312);
        assert.equal(!r.mastery, ignores, `${r.name} ${r.id} mastery`);
        if (r.vers !== 'inherit') assert.equal(!r.vers, ignores, `${r.name} ${r.id} vers`);
    }
});

test("Harmony's list is exactly the seven spells carrying label 4337", () => {
    const label = DUMP.split('######## spell.label=4337')[1];
    const ids = [...label.matchAll(/\(id=(\d+)\)/g)].map((m) => Number(m[1]));
    assert.deepEqual(ids.sort((a, b) => a - b), HARMONY_IDS.slice().sort((a, b) => a - b));
    assert.match(block(77495), /SP Coefficient: 1\.311/);
    assert.equal(CONSTANTS.harmonyCoefficient, 1.311);
    assert.equal(stackFactor(0), 0);
    assert.equal(stackFactor(2), 1.7);
    assert.equal(stackFactor(14), 3.875);
});

test('the buff amounts are the dump\'s', () => {
    assert.match(block(1126), /Modify Versatility% \(471\)\n\s+Base Value: 3 /);
    assert.equal(PERCENT_BUFFS[1126].percent, 3);
    assert.match(block(1302255), /Spell Periodic Amount \(22\)\n\s+Base Value: 15 /);
    assert.equal(AMOUNT_BUFFS[1302255], 'Genesis');
});

test("base mastery 8: the owner's 2026-10-01 transcript, effect / coefficient - the rating's points", () => {
    const t = fs.readFileSync(path.join(FIX, 'captures', 'Lootpath-20261001-092631.lua'), 'utf8');
    const eff = /\["masteryEffect"\] = \{\s*([\d.]+),\s*([\d.]+),/.exec(t);
    const mastery = /\["mastery"\] = \{\s*\["at"\][\s\S]*?\["bonusForCurrent"\] = \{\s*([\d.]+),/.exec(t);
    assert.ok(eff && mastery, 'the transcript fields');
    const base = Number(eff[1]) / Number(eff[2]) - Number(mastery[1]);
    assert.ok(Math.abs(base - CONSTANTS.masteryBase) < 1e-3, `base ${base}`);
});
