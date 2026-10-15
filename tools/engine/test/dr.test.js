'use strict';

// E-0f (WKE-676): the published brackets in lib/dr.js against what the client
// answered on 2026-10-01 - GetCombatRatingBonusForCombatRatingValue at 660 ..
// 3080 and at the character's own rating, for all five ratings.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { parseSavedVariables, luaArray } = require('../../companion/lib/lua-savedvariables');
const { DEFAULT_DR, ratingToPercent } = require('../lib/dr');

const TRANSCRIPT = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'captures', 'Lootpath-20261001-092631.lua');
const KEY = { haste: 'haste', crit: 'crit', mastery: 'mastery', versatility: 'vers', leech: 'leech' };
// Single precision for the four; leech reads a constant 1.43e-5 relative below
// 69 rating per percent at every point, which the table does not carry.
const TOLERANCE = { haste: 1e-5, crit: 1e-5, mastery: 1e-5, versatility: 1e-5, leech: 3e-4 };

test('the client applies diminishing returns, and the published brackets reproduce it', () => {
    const db = parseSavedVariables(fs.readFileSync(TRANSCRIPT, 'utf8')).LootpathDB;
    const ratings = luaArray(db.global.captures.itemstats)[0].data.rating.ratings;
    let points = 0;
    for (const [name, r] of Object.entries(ratings)) {
        const table = DEFAULT_DR[KEY[name]];
        const all = [...luaArray(r.at).map((a) => [a.value, a.bonus[1]]), [r.rating[1], r.bonus[1]]];
        for (const [value, bonus] of all) {
            assert.ok(Math.abs(ratingToPercent(value, table) - bonus) < TOLERANCE[name], `${name} at ${value}: ${bonus}`);
            points += 1;
        }
    }
    assert.equal(points, 35);
    // Undiminished, haste at 2640 would be 60; the client said 54.
    const haste = luaArray(ratings.haste.at);
    assert.equal(haste[1].bonus[1], 30);
    assert.equal(haste[4].bonus[1], 54);
    // Mastery answered crit's figure at every point for spec 105.
    luaArray(ratings.mastery.at).forEach((a, i) => assert.equal(a.bonus[1], luaArray(ratings.crit.at)[i].bonus[1]));
});
