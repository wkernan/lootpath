'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { newTable, readJsonInto, readSavedVariablesInto, buildBudget, itemStats, parseLevelStat } = require('../lib/stats');

const CAPTURE = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'captures', 'Lootpath-20260915-162015.lua');

test('levelStats strings parse to stats; armour, stamina and damage are not stats here', () => {
    assert.deepEqual(parseLevelStat('140 Intellect'), ['int', 140]);
    assert.deepEqual(parseLevelStat('|cff20ff20144 (+4)|r Intellect'), ['int', 144]);
    assert.deepEqual(parseLevelStat('103 Critical Strike'), ['crit', 103]);
    assert.deepEqual(parseLevelStat('41 Leech'), ['leech', 41]);
    assert.equal(parseLevelStat('159 Armor'), null);
    assert.equal(parseLevelStat('2699 Stamina'), null);
    assert.equal(parseLevelStat('53 - 89 Damage'), null);
});

test('the committed capture upgrade transcript gives client points (read, not typed)', () => {
    const table = readSavedVariablesInto(newTable(), fs.readFileSync(CAPTURE, 'utf8'), 'capture');
    // Enigmatic Dreamwatcher's Lunar Raiment at 302: "140 Intellect", "103
    // Critical Strike", "73 Versatility" in the transcript's levelStats.
    const p = table.points.get('271531@302');
    assert.ok(p, 'the chest at 302');
    assert.equal(p.stats.int, 140);
    assert.equal(p.stats.crit, 103);
    assert.equal(p.stats.vers, 73);
    assert.equal(p.stats.haste, 0);
    assert.equal(table.slotOf.get(271531), 'Chest');
    assert.equal(table.patch, '12.1.0');
});

function syntheticTable() {
    return readJsonInto(
        newTable(),
        {
            items: [
                { id: 1, level: 300, slot: 'Chest', stats: { int: 140, crit: 100, vers: 70 } },
                { id: 1, level: 306, slot: 'Chest', stats: { int: 148, crit: 102, vers: 72 } },
                { id: 2, level: 300, slot: 'Waist', stats: { int: 105, haste: 60, mastery: 70 } },
                { id: 2, level: 306, slot: 'Waist', stats: { int: 111, haste: 61, mastery: 72 } },
            ],
        },
        'synthetic',
    );
}

test('the stats-source flag: client, client-scaled, budget, budget-borrowed, none', () => {
    const table = syntheticTable();
    const budget = buildBudget(table);
    assert.equal(itemStats(table, budget, { id: 1, level: 300, slot: 'Chest' }).statsSource, 'client');
    const scaled = itemStats(table, budget, { id: 1, level: 312, slot: 'Chest' });
    assert.equal(scaled.statsSource, 'client-scaled');
    assert.equal(scaled.splitSource, 'client');
    assert.ok(scaled.stats.int > 148 && scaled.stats.haste === 0, 'its own split, scaled up');
    const legs = itemStats(table, budget, { id: 9, level: 306, slot: 'Legs' });
    assert.equal(legs.statsSource, 'budget-borrowed', 'legs read the chest group');
    const chest = itemStats(table, budget, { id: 10, level: 306, slot: 'Chest' });
    assert.equal(chest.statsSource, 'budget');
    assert.equal(chest.splitSource, 'equal-placeholder');
    assert.equal(chest.stats.haste, chest.stats.mastery);
    assert.equal(itemStats(table, budget, { id: 11, level: 306, slot: 'Offhand' }).statsSource, 'none');
});

test('a crafted row takes the pair settings.craftedStats names', () => {
    const table = syntheticTable();
    const budget = buildBudget(table);
    const s = itemStats(table, budget, { id: 12, level: 306, slot: 'Chest' }, { craftedPair: ['crit', 'haste'] });
    assert.equal(s.splitSource, 'settings.craftedStats');
    assert.equal(s.stats.mastery, 0);
    assert.equal(s.stats.crit, s.stats.haste);
});

test('the level curve is measured within items', () => {
    const budget = buildBudget(syntheticTable());
    // int 140 -> 148 and 105 -> 111 over 6 levels: ln ratios 0.05557, 0.05557
    assert.ok(Math.abs(budget.intSlope - Math.log(148 / 140) / 6) < 1e-3, `${budget.intSlope}`);
    assert.equal(budget.intItems, 2);
});
