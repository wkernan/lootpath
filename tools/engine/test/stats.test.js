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

// E-0f (WKE-676): the owner's `capture itemstats` transcript, read.
const ITEMSTATS = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'captures', 'Lootpath-20261001-092631.lua');
const { readItemStatsInto, statsForLink, strippedKey, bonusKey, linkBonusIDs, ITEMSTATS_KEYS, SOURCE_ITEMSTATS, SOURCE_UPGRADE } = require('../lib/stats');

let itemstatsTable = null;
function itemstats() {
    if (!itemstatsTable) itemstatsTable = readSavedVariablesInto(newTable(), fs.readFileSync(ITEMSTATS, 'utf8'), 'itemstats');
    return itemstatsTable;
}

const HELM_LINK = "|cnIQ4:|Hitem:271528:7961:240892::::::90:105::35:6:6652:13440:13695:13692:13698:12845:1:64:239033:::::|h[Enigmatic Dreamwatcher's Somnolent Stare]|h|r";

test('the itemstats transcript: 80 items read, indexed by id@level, by link and by bonus IDs', () => {
    const table = itemstats();
    const src = table.sources.find((s) => s.kind.startsWith('capture itemstats'));
    assert.equal(src.items, 80);
    assert.equal(table.byLink.size, 80);
    // The worn helm at 318: "ITEM_MOD_INTELLECT_SHORT" 162, haste 78, crit 110.
    const p = table.points.get('271528@318');
    assert.equal(p.source, SOURCE_ITEMSTATS);
    assert.deepEqual(p.stats, { int: 162, haste: 78, crit: 110, mastery: 0, vers: 0, leech: 0 });
    assert.deepEqual(statsForLink(table, HELM_LINK), p.stats);
    // The enchant and gem do not change the key: the base is the item's own.
    assert.equal(strippedKey(HELM_LINK), 'item:271528::::::::90:105::35:6:6652:13440:13695:13692:13698:12845:1:64:239033:::::');
    assert.deepEqual(linkBonusIDs(HELM_LINK), [6652, 13440, 13695, 13692, 13698, 12845]);
    assert.equal(table.byBonus.get(bonusKey(271528, [12845, 6652, 13440, 13692, 13695, 13698])), p);
    assert.equal(table.slotOf.get(271528), 'Head');
    assert.equal(table.patch, '12.1.0');
});

test('versatility is ITEM_MOD_VERSATILITY, no _SHORT, and leech is read', () => {
    assert.equal(ITEMSTATS_KEYS.ITEM_MOD_VERSATILITY, 'vers');
    assert.equal(ITEMSTATS_KEYS.ITEM_MOD_VERSATILITY_SHORT, undefined);
    const table = itemstats();
    // The worn neck at 321: mastery 220, versatility 156.
    assert.equal(table.points.get('272228@321').stats.vers, 156);
    assert.equal(table.points.get('272228@321').stats.mastery, 220);
    // The worn ring at 292 carries 53 leech.
    assert.equal(table.points.get('279010@292').stats.leech, 53);
});

test('a covered row is `client` from the itemstats transcript; budget stays the fallback', () => {
    const table = itemstats();
    const budget = buildBudget(table);
    const hit = itemStats(table, budget, { id: 271528, level: 318, slot: 'Head' });
    assert.equal(hit.statsSource, 'client');
    assert.equal(hit.clientSource, SOURCE_ITEMSTATS);
    assert.equal(hit.matchedBy, 'level');
    // An export's worn entry, matched by its bonus IDs (order free).
    const worn = itemStats(table, budget, { id: 271528, level: 999, slot: 'Head', bonusIDs: [13698, 12845, 6652, 13440, 13695, 13692] });
    assert.equal(worn.statsSource, 'client');
    assert.equal(worn.matchedBy, 'link');
    assert.equal(worn.stats.int, 162);
    const miss = itemStats(table, budget, { id: 99999999, level: 318, slot: 'Head' });
    assert.equal(miss.statsSource, 'budget');
    assert.equal(miss.clientSource, undefined);
});

test('where both transcripts name an id@level, the GetItemStats read is kept, and they agree', () => {
    const table = itemstats();
    const upgrade = readSavedVariablesInto(newTable(), fs.readFileSync(CAPTURE, 'utf8'), 'capture');
    let shared = 0;
    for (const [key, p] of table.points) {
        if (p.source !== SOURCE_ITEMSTATS) continue;
        const q = upgrade.points.get(key);
        if (!q || q.source !== SOURCE_UPGRADE) continue;
        shared += 1;
        assert.deepEqual(p.stats, q.stats, key);
    }
    assert.ok(shared > 0, 'the two client sources overlap');
});

// E-0g step 2 (WKE-677): the owner's `capture linklevel` transcript, read.
// Each candidate a track step draws gives one `client` point at the WALK's
// level - GetItemStats on the journal link rebuilt with that step appended,
// which the client drew at the walk's level in all three reads.
const LINKLEVEL = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'captures', 'Lootpath-20261001-200927.lua');
const { SOURCE_LINKLEVEL, readLinkLevelInto } = require('../lib/stats');
const { parseSavedVariables } = require('../../companion/lib/lua-savedvariables');

test('the linklevel transcript: each rebuilt-link read is a client point at the walk level', () => {
    const caps = parseSavedVariables(fs.readFileSync(LINKLEVEL, 'utf8')).LootpathDB.global.captures;
    const table = newTable();
    assert.equal(readLinkLevelInto(table, caps, 'linklevel'), 8);
    const src = table.sources.find((s) => s.kind.startsWith('capture linklevel'));
    assert.equal(src.items, 8);
    assert.equal(src.newPoints, 8);
    // Seed of Radiant Hope at 305 (Champion 5/6 appended): 137 Intellect, where
    // the kept link read 121 at 292 before the walk.
    const seed = table.points.get('250254@305');
    assert.equal(seed.source, SOURCE_LINKLEVEL);
    assert.equal(seed.stats.int, 137);
    // The raid gloves at 324 (Myth 3/6): 129 Intellect, crit 46, mastery 98.
    assert.deepEqual(table.points.get('268234@324').stats, { int: 129, haste: 0, crit: 46, mastery: 98, vers: 0, leech: 0 });
    assert.equal(table.slotOf.get(268234), 'Hands');
    // The world rows at 44 give nothing: no track step draws 44.
    for (const key of table.points.keys()) assert.ok(!key.endsWith('@44'), key);
    // A row it covers is `client` from it, at exactly the walk's level.
    const budget = buildBudget(table);
    const hit = itemStats(table, budget, { id: 268252, level: 311, slot: 'Finger' });
    assert.equal(hit.statsSource, 'client');
    assert.equal(hit.clientSource, SOURCE_LINKLEVEL);
    assert.equal(hit.stats.crit, 295);
});

test('a --stats file carrying a linklevel snapshot is read for it beside its itemstats', () => {
    const table = readSavedVariablesInto(newTable(), fs.readFileSync(LINKLEVEL, 'utf8'), 'linklevel');
    assert.ok(table.sources.some((s) => s.kind.startsWith('capture linklevel') && s.items === 8));
    assert.equal(table.points.get('251123@305').source, SOURCE_LINKLEVEL);
    assert.equal(table.points.get('251123@305').stats.int, 640);
});
