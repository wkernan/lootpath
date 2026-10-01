// A synthetic Upgrade Finder export generated FROM known weights, and the
// item-stats table it was generated with. Every number here is invented.
'use strict';

const score = require('../lib/score');
const { DEFAULT_DR } = require('../lib/dr');
const { mulberry32 } = require('../lib/fit');

const TRUE_MODEL = {
    baseValue: 2000,
    weights: { int: 1.2, haste: 30, crit: 22, mastery: 35, vers: 18, leech: 10 },
    assumedFinish: {},
    dr: DEFAULT_DR,
    tiers: { setIDs: [9999], twoPiece: 0.03, fourPiece: 0.055, forceTier: true },
};

const SLOTS = ['Head', 'Shoulder', 'Chest', 'Hands', 'Legs', 'Wrist', 'Waist', 'Feet', 'Back', 'Neck', 'Finger', '2H Weapon'];
const SEC = ['haste', 'crit', 'mastery', 'vers'];

function makeItem(rand, id, slot, level) {
    const jewel = slot === 'Neck' || slot === 'Finger';
    const scale = Math.exp(0.009 * (level - 300));
    const stats = { int: jewel ? 0 : Math.round((slot === '2H Weapon' ? 600 : 120) * scale * (0.8 + 0.4 * rand())) };
    const a = SEC[Math.floor(rand() * 4)];
    let b = SEC[Math.floor(rand() * 4)];
    if (b === a) b = SEC[(SEC.indexOf(a) + 1) % 4];
    const total = Math.round((jewel ? 260 : 170) * scale * (0.8 + 0.4 * rand()));
    const share = 0.25 + 0.5 * rand();
    for (const k of SEC) stats[k] = 0;
    stats[a] = Math.round(total * share);
    stats[b] = total - stats[a];
    stats.leech = rand() < 0.2 ? Math.round(40 * rand()) : 0;
    return { id, level, slot, stats };
}

function generate(seed) {
    const rand = mulberry32(seed || 7);
    const tableItems = [];
    const worn = [];
    let id = 100000;
    const wornSlots = ['Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet', 'Finger', 'Finger', 'Trinket', 'Trinket', '2H Weapon'];
    for (const slot of wornSlots) {
        id += 1;
        const it = slot === 'Trinket' ? { id, level: 300, slot, stats: { int: 140 } } : makeItem(rand, id, slot, 300);
        tableItems.push(it);
        worn.push({ slot, id, level: 300, bonusIDs: [], gems: [], enchant: '', tertiary: '', setId: 0, isVault: false, isExclusive: false, source: {} });
    }
    const wornItems = tableItems.map((t) => ({ slot: t.slot, stats: t.stats, setId: 0 }));
    const rows = [];
    for (let i = 0; i < 160; i++) {
        id += 1;
        const slot = SLOTS[i % SLOTS.length];
        const level = [311, 321, 334][i % 3];
        const it = makeItem(rand, id, slot, level);
        tableItems.push(it);
        const r = score.upgrade(wornItems, it, TRUE_MODEL);
        rows.push({
            id,
            level,
            slot,
            source: {},
            dropLoc: 'Dungeon',
            dropType: 'drop',
            dropDifficulty: 7,
            // QE Live rounds to three decimals and shows a worse item as 0.
            upgradePercent: Math.round(r.clampedPercent * 1000) / 1000,
            hpsGain: 0,
            score: r.clampedPercent / 100,
        });
    }
    // Two rows the fit must exclude as effects: a trinket and a named effect armour piece.
    rows.push({ id: 300001, level: 321, slot: 'Trinket', source: {}, dropLoc: 'Raid', dropType: 'drop', dropDifficulty: 3, upgradePercent: 1.5, hpsGain: 0, score: 0.015 });
    tableItems.push({ id: 300001, level: 321, slot: 'Trinket', stats: { int: 160 } });
    rows.push({ id: 271875, level: 321, slot: 'Neck', source: {}, dropLoc: 'Raid', dropType: 'drop', dropDifficulty: 3, upgradePercent: 2.2, hpsGain: 0, score: 0.022 });
    tableItems.push({ id: 271875, level: 321, slot: 'Neck', stats: { int: 0, crit: 150, haste: 150 } });

    const doc = {
        schema: 'qe-live-upgradefinder',
        version: 1,
        exportedAt: '2026-09-30T00:00:00.000Z',
        player: { name: 'Synthetic', spec: 'Restoration Druid' },
        contentType: 'Dungeon',
        reportId: 'synthetic',
        settings: { raid: [3], dungeon: 7, craftedStats: 'Crit / Haste' },
        equipped: worn,
        items: rows,
    };
    // What the fit should find: the true weights in the fit's normalisation
    // (base + w . x(worn) = 100).
    const x = score.features(score.totals(wornItems, {}), DEFAULT_DR);
    const linearWorn = score.linearValue(x, TRUE_MODEL);
    const expected = {};
    for (const k of score.STATS) expected[k] = (TRUE_MODEL.weights[k] * 100) / linearWorn;
    expected.baseValue = (TRUE_MODEL.baseValue * 100) / linearWorn;
    return { doc, table: { items: tableItems }, expected };
}

module.exports = { generate, TRUE_MODEL };
