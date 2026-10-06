'use strict';

// Seeded synthetic inventories and weights for the exhaustive check (E-1d,
// WKE-687; test/exhaustive.test.js). DEV ONLY. No number here is a game value.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DEFAULT_DR } = require('./dr');
const { luaValue } = require('./luaout');
const { mulberry32 } = require('./fit');

const TIER = 2057;
// Not game values: weights, a finish and a tier rule a test can tell apart.
function syntheticFile(tier4) {
    const band = {
        baseValue: 30,
        weights: { int: 0.02, haste: 0.72, crit: 0.47, mastery: 0.6, vers: 0.57, leech: 0.53 },
        assumedFinish: { gemVector: { haste: 50 }, enchantBySlot: { Finger: { mastery: 30 } } },
        assumedBuffs: {},
    };
    return {
        schema: 'lootpath-engine-weights',
        version: 1,
        method: 'synthetic',
        patch: '12.1.0',
        derivedAt: 'never',
        specs: new Map([[105, { Dungeon: { bands: { 10: band } } }]]),
        dr: DEFAULT_DR,
        tiers: new Map([
            [
                TIER,
                new Map([
                    [2, { mult: 1.0001 }],
                    [4, { mult: tier4 }],
                ]),
            ],
        ]),
    };
}

function writeFile(file) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e1d-syn-'));
    const luaPath = path.join(dir, 'weights.lua');
    fs.writeFileSync(luaPath, `local _, ns = ...\nns.engineWeights = ${luaValue(file, 0)}\n`);
    return { file, luaPath };
}

// One inventory: 20,736 sets. Synthetic itemIDs from 900000 (none in the
// effects table, so every trinket is "unknown" and never dropped, as in game).
function inventory(seed, opts) {
    const o = opts || {};
    const rand = mulberry32(seed * 7919 + 17);
    const r = (n) => Math.floor(rand() * n);
    let id = 900000 + seed * 1000;
    const items = [];
    const piece = (slot, extra) => {
        id += 1;
        const p = { itemID: id, slot, int: 250 + r(120), haste: 40 + r(330), crit: 40 + r(330), mastery: 40 + r(330), vers: 40 + r(330), leech: r(40), sockets: r(4) === 0 ? 1 : 0, location: 'bag', ...(extra || {}) };
        p.idx = items.length + 1;
        p.key = `syn:${p.idx}`;
        items.push(p);
        return p;
    };
    const spareOf = (base, slot, by) => {
        const s = piece(slot);
        for (const k of ['int', 'haste', 'crit', 'mastery', 'vers', 'leech']) s[k] = Math.max(0, base[k] - by - r(20));
        s.sockets = 0;
        return s;
    };
    for (const slot of ['Head', 'Shoulder', 'Chest', 'Hands', 'Legs']) {
        const plain = piece(slot, { location: 'equipped' });
        const tier = piece(slot, { setID: TIER, sockets: plain.sockets });
        for (const k of ['int', 'haste', 'crit', 'mastery', 'vers', 'leech']) tier[k] = Math.floor(plain[k] * 0.92);
        if (slot === 'Legs') spareOf(plain, slot, 1);
    }
    piece('Neck', { location: 'equipped' });
    const neck = piece('Neck');
    for (const slot of ['Back', 'Wrist', 'Waist', 'Feet']) {
        const only = piece(slot, { location: 'equipped' });
        if (slot === 'Waist') spareOf(only, slot, 2);
    }
    const u1 = piece('Finger', { uniqueness: { isUnique: true }, location: 'equipped' });
    const u2 = piece('Finger', { itemID: u1.itemID, uniqueness: { isUnique: true } });
    for (const k of ['int', 'haste', 'crit', 'mastery', 'vers', 'leech']) u2[k] = u1[k] - 3;
    const plainRing = piece('Finger', { location: 'equipped' });
    piece('Finger');
    const low = piece('Finger');
    for (const k of ['int', 'haste', 'crit', 'mastery', 'vers', 'leech']) low[k] = Math.max(0, Math.min(u1[k], plainRing[k]) - 5);
    low.sockets = 0;
    // With `category`: a limit category of one shared by the second neck and
    // the plain ring, both made strong - the hook, not the pair options, keeps
    // them apart, and the best set may need BOTH positions to change at once.
    if (o.category) {
        for (const p of [neck, plainRing]) {
            p.uniqueness = { isUnique: false, category: 77, max: 1 };
            for (const k of ['int', 'haste', 'crit', 'mastery', 'vers']) p[k] += 300;
        }
    }
    for (let i = 0; i < 3; i++) piece('Trinket', { uniqueness: { isUnique: true }, location: i < 2 ? 'equipped' : 'bag' });
    piece('1H Weapon');
    piece('Offhand');
    piece('Shield');
    for (let i = 0; i < 2; i++) {
        const two = piece('2H Weapon', { location: i === 0 ? 'equipped' : 'bag' });
        for (const k of ['int', 'haste', 'crit', 'mastery', 'vers']) two[k] = two[k] * 2 - 60 + r(120);
    }
    return items;
}

module.exports = { TIER, syntheticFile, writeFile, inventory };
