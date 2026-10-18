// Rating -> percent through the brackets Lootpath/Data/EngineWeights.lua
// carries in its `dr` table (E-5; docs/COMBAT-LOG-WEIGHTS.md §4), read from
// that file so the addon and this tool convert the same way. A bracket's
// penalty applies to the rating inside it.
'use strict';

const fs = require('fs');
const path = require('path');
const { readLuaTable } = require('../../engine/lib/luatable');

const WEIGHTS_FILE = path.join(__dirname, '..', '..', '..', 'Lootpath', 'Data', 'EngineWeights.lua');
const RATINGS = ['haste', 'crit', 'mastery', 'vers', 'leech'];

// -> { haste: { ratingPerPercent, brackets: [{ from, penalty }] }, ... }
function loadDR(file) {
    const table = readLuaTable(fs.readFileSync(file || WEIGHTS_FILE, 'utf8'), /^ns\.engineWeights\s*=/m);
    const dr = table && table.dr;
    if (!dr) throw new Error(`no dr table in ${file || WEIGHTS_FILE}`);
    const out = {};
    for (const k of RATINGS) {
        const t = dr[k];
        // The SavedVariables reader returns a Lua list as an object keyed "1".."n".
        const list = t && (Array.isArray(t.brackets) ? t.brackets : t.brackets && Object.keys(t.brackets).sort((a, b) => a - b).map((i) => t.brackets[i]));
        if (!t || !(t.ratingPerPercent > 0) || !list || !list.length) throw new Error(`dr.${k} missing or malformed`);
        out[k] = { ratingPerPercent: t.ratingPerPercent, brackets: list.map((b) => ({ from: b.from, penalty: b.penalty })).sort((a, b) => a.from - b.from) };
    }
    return out;
}

function ratingToPercent(rating, t) {
    if (!(rating > 0)) return 0;
    let effective = 0;
    let prevFrom = 0;
    let prevPenalty = 0;
    for (const b of t.brackets) {
        if (rating <= b.from) break;
        effective += (b.from - prevFrom) * (1 - prevPenalty);
        prevFrom = b.from;
        prevPenalty = b.penalty;
    }
    effective += (rating - prevFrom) * (1 - prevPenalty);
    return effective / t.ratingPerPercent;
}

// d(percent)/d(rating) at a rating: (1 - the penalty of the bracket the NEXT
// point falls in) / rating per percent.
function slope(rating, t) {
    let penalty = 0;
    for (const b of t.brackets) if (rating >= b.from) penalty = b.penalty;
    return (1 - penalty) / t.ratingPerPercent;
}

module.exports = { WEIGHTS_FILE, RATINGS, loadDR, ratingToPercent, slope };
