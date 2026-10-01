// The item-stats table and the stat budget (E-0e, WKE-674).
//
// Every row the fit uses needs a stat vector, and QE Live's Upgrade Finder
// export carries none: its rows are `id`, `level`, `slot` and the result, its
// `equipped[]` entries carry bonus IDs, gems, enchant and tertiary but no
// stats (checked over all eight committed documents, 2026-09-30). So the
// vector comes from the CLIENT, and each row says how:
//
//   client          the item at exactly that level, read from a transcript
//   client-scaled   the item read at another level, scaled to this one by the
//                   level curve below (its own split, the client's scale)
//   budget          no client read of the item: Intellect and the secondary
//                   total from its slot's budget at that level, measured on
//                   client rows of the SAME slot
//   budget-borrowed the same, from client rows of another slot of the same
//                   budget group (head from chest and legs, for example) -
//                   the grouping is Blizzard's allocation as the rows show it
//                   (waist and feet read the same budget, chest and legs too)
//                   and is an assumption wherever a slot has no row of its own
//   none            no client row in the group at all: the row is excluded
//
// A budget row does not know WHICH secondaries the item has. Its secondary
// total is split equally over the four (`splitSource: "equal-placeholder"`),
// or, for a crafted row, over the pair the export's own
// `settings.craftedStats` names. That split is a documented placeholder, not
// a reading, and it is the largest known error of the run until E-0a's
// transcript gives every row its own stats.
//
// Client source today: `capture upgrade` (decision 2026-09-14 evening), whose
// `GetItemUpgradeItemInfo().upgradeLevelInfos[].levelStats` gives an owned
// item's stats at each level of its track - two levels of one item give the
// scale, never guessed. E-0a's `capture itemstats` (WKE-675) is not committed;
// its return shape is unconfirmed (Ketho's annotations give
// `C_Item.GetItemStats` no return type), so it is NOT read here - wiring it is
// a follow-up once its transcript lands. A plain JSON table
// (`{ items: [{ id, level, slot, stats: { int, haste, crit, mastery, vers, leech } }] }`)
// is accepted for tests and for hand-checked tables.
'use strict';

const { parseSavedVariables, luaArray } = require('../../companion/lib/lua-savedvariables');
const { STATS, zeroStats } = require('./score');

const SECONDARIES = ['haste', 'crit', 'mastery', 'vers'];

const CLIENT_STAT_NAMES = {
    Intellect: 'int',
    Haste: 'haste',
    'Critical Strike': 'crit',
    Mastery: 'mastery',
    Versatility: 'vers',
    Leech: 'leech',
};

const INVTYPE_SLOT = {
    INVTYPE_HEAD: 'Head',
    INVTYPE_NECK: 'Neck',
    INVTYPE_SHOULDER: 'Shoulder',
    INVTYPE_CLOAK: 'Back',
    INVTYPE_CHEST: 'Chest',
    INVTYPE_ROBE: 'Chest',
    INVTYPE_WRIST: 'Wrist',
    INVTYPE_HAND: 'Hands',
    INVTYPE_WAIST: 'Waist',
    INVTYPE_LEGS: 'Legs',
    INVTYPE_FEET: 'Feet',
    INVTYPE_FINGER: 'Finger',
    INVTYPE_TRINKET: 'Trinket',
    INVTYPE_2HWEAPON: '2H Weapon',
    INVTYPE_WEAPON: '1H Weapon',
    INVTYPE_WEAPONMAINHAND: '1H Weapon',
    INVTYPE_WEAPONOFFHAND: 'Offhand',
    INVTYPE_HOLDABLE: 'Offhand',
    INVTYPE_SHIELD: 'Offhand',
};

// Budget groups: slots that read the same budget at a level.
const BUDGET_GROUP = {
    Head: 'major',
    Chest: 'major',
    Legs: 'major',
    Shoulder: 'minor',
    Waist: 'minor',
    Hands: 'minor',
    Feet: 'minor',
    Back: 'small',
    Wrist: 'small',
    Neck: 'jewel',
    Finger: 'jewel',
    Trinket: 'trinket',
    '2H Weapon': 'twoHand',
    '1H Weapon': 'oneHand',
    Offhand: 'offhand',
};

function newTable() {
    return { points: new Map(), slotOf: new Map(), sources: [], patch: null };
}

function addPoint(table, id, level, stats, slot) {
    const key = `${id}@${level}`;
    if (!table.points.has(key)) table.points.set(key, { id, level, stats });
    if (slot && !table.slotOf.has(id)) table.slotOf.set(id, slot);
}

function stripColour(s) {
    return String(s).replace(/\|c[0-9a-fA-F]{8}|\|r/g, '');
}

// "144 (+4) Intellect" -> ["int", 144]; anything else (armor, damage) -> null.
function parseLevelStat(displayString) {
    const m = stripColour(displayString).match(/^([\d,]+)(?: \([+-][\d,]+\))? (.+)$/);
    if (!m) return null;
    const key = CLIENT_STAT_NAMES[m[2]];
    if (!key) return null;
    return [key, Number(m[1].replace(/,/g, ''))];
}

function readSavedVariablesInto(table, text, label) {
    const sv = parseSavedVariables(text);
    const db = sv.LootpathDB;
    const caps = db && db.global && db.global.captures;
    if (!caps) throw new Error(`${label}: no LootpathDB.global.captures`);
    let points = 0;
    // Slots first, from every inventory read: the item's own INVTYPE.
    for (const k of Object.keys(caps.inventory || {})) {
        const data = caps.inventory[k] && caps.inventory[k].data;
        if (!data) continue;
        for (const part of ['equipped', 'bags', 'bank']) {
            for (const it of luaArray(data[part] || {})) {
                const info = it.item && it.item.info;
                const id = it.itemID && it.itemID[1];
                const slot = info && INVTYPE_SLOT[info[9]];
                if (id && slot && !table.slotOf.has(id)) table.slotOf.set(id, slot);
            }
        }
    }
    for (const k of Object.keys(caps.upgrade || {})) {
        const cap = caps.upgrade[k];
        if (cap && cap.build && cap.build[1] && !table.patch) table.patch = cap.build[1];
        const items = cap && cap.data && cap.data.items;
        if (!items) continue;
        for (const it of luaArray(items)) {
            const info = it.info && it.info[1];
            const current = it.currentLevel && it.currentLevel[1];
            if (!info || typeof current !== 'number') continue;
            for (const lvl of luaArray(info.upgradeLevelInfos || {})) {
                const stats = zeroStats();
                for (const s of luaArray(lvl.levelStats || {})) {
                    if (!s.active) continue;
                    const parsed = parseLevelStat(s.displayString);
                    if (parsed) stats[parsed[0]] = parsed[1];
                }
                const level = current + (lvl.itemLevelIncrement || 0);
                const before = table.points.size;
                addPoint(table, it.itemID, level, stats);
                points += table.points.size - before;
            }
        }
    }
    table.sources.push({ file: label, kind: 'capture upgrade (levelStats)', newPoints: points });
    return table;
}

function readJsonInto(table, obj, label) {
    let points = 0;
    for (const it of obj.items || []) {
        const stats = zeroStats();
        for (const k of STATS) stats[k] = (it.stats && it.stats[k]) || 0;
        const before = table.points.size;
        addPoint(table, it.id, it.level, stats, it.slot);
        points += table.points.size - before;
    }
    table.sources.push({ file: label, kind: 'json item-stats table', newPoints: points });
    return table;
}

function secTotal(stats) {
    let s = 0;
    for (const k of SECONDARIES) s += stats[k] || 0;
    return s;
}

// The level curve: ln(stat) linear in item level, slope measured WITHIN items
// (each item demeaned over its own levels), separately for Intellect and for
// the secondary total.
function levelSlope(table, pick) {
    const byId = new Map();
    for (const p of table.points.values()) {
        const v = pick(p.stats);
        if (!(v > 0)) continue;
        if (!byId.has(p.id)) byId.set(p.id, []);
        byId.get(p.id).push([p.level, Math.log(v)]);
    }
    let num = 0;
    let den = 0;
    let pairs = 0;
    for (const pts of byId.values()) {
        if (pts.length < 2) continue;
        const mL = pts.reduce((a, p) => a + p[0], 0) / pts.length;
        const mV = pts.reduce((a, p) => a + p[1], 0) / pts.length;
        for (const [L, v] of pts) {
            num += (L - mL) * (v - mV);
            den += (L - mL) * (L - mL);
        }
        pairs += 1;
    }
    return { slope: den > 0 ? num / den : null, items: pairs };
}

function buildBudget(table) {
    const intCurve = levelSlope(table, (s) => s.int);
    const secCurve = levelSlope(table, secTotal);
    const groups = {};
    for (const p of table.points.values()) {
        const slot = table.slotOf.get(p.id);
        const group = slot && BUDGET_GROUP[slot];
        if (!group) continue;
        const g = groups[group] || (groups[group] = { slots: new Set(), n: 0, intLog: [], secLog: [], intZero: 0, secZero: 0 });
        g.slots.add(slot);
        g.n += 1;
        if (p.stats.int > 0 && intCurve.slope !== null) g.intLog.push(Math.log(p.stats.int) - intCurve.slope * p.level);
        else g.intZero += 1;
        const st = secTotal(p.stats);
        if (st > 0 && secCurve.slope !== null) g.secLog.push(Math.log(st) - secCurve.slope * p.level);
        else g.secZero += 1;
    }
    const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;
    const out = { intSlope: intCurve.slope, secSlope: secCurve.slope, intItems: intCurve.items, secItems: secCurve.items, groups: {} };
    for (const [name, g] of Object.entries(groups)) {
        out.groups[name] = {
            slots: [...g.slots].sort(),
            points: g.n,
            intLogBase: g.intLog.length ? mean(g.intLog) : null,
            secLogBase: g.secLog.length ? mean(g.secLog) : null,
        };
    }
    return out;
}

function budgetAt(budget, group, level) {
    const g = budget.groups[group];
    if (!g) return null;
    const int = g.intLogBase === null ? 0 : Math.exp(g.intLogBase + budget.intSlope * level);
    const sec = g.secLogBase === null ? 0 : Math.exp(g.secLogBase + budget.secSlope * level);
    return { int, sec };
}

function craftedPair(craftedStats) {
    if (!craftedStats) return null;
    const names = { crit: 'crit', haste: 'haste', mastery: 'mastery', vers: 'vers', versatility: 'vers' };
    const pair = String(craftedStats)
        .split('/')
        .map((s) => names[s.trim().toLowerCase()])
        .filter(Boolean);
    return pair.length === 2 ? pair : null;
}

// The stat vector for one item (a row, or a worn entry).
function itemStats(table, budget, item, opts) {
    const options = opts || {};
    const exact = table.points.get(`${item.id}@${item.level}`);
    if (exact) return { stats: { ...exact.stats }, statsSource: 'client', splitSource: 'client' };
    const own = [...table.points.values()].filter((p) => p.id === item.id);
    if (own.length && budget.intSlope !== null && budget.secSlope !== null) {
        own.sort((a, b) => Math.abs(a.level - item.level) - Math.abs(b.level - item.level));
        const from = own[0];
        const fI = Math.exp(budget.intSlope * (item.level - from.level));
        const fS = Math.exp(budget.secSlope * (item.level - from.level));
        const stats = zeroStats();
        stats.int = from.stats.int * fI;
        for (const k of ['haste', 'crit', 'mastery', 'vers', 'leech']) stats[k] = from.stats[k] * fS;
        return { stats, statsSource: 'client-scaled', splitSource: 'client', scaledFrom: from.level };
    }
    const group = BUDGET_GROUP[item.slot];
    const b = group && budgetAt(budget, group, item.level);
    if (!b) return { stats: null, statsSource: 'none', splitSource: null };
    const measured = budget.groups[group].slots.includes(item.slot);
    const stats = zeroStats();
    stats.int = b.int;
    const pair = options.craftedPair;
    if (pair) {
        for (const k of pair) stats[k] = b.sec / 2;
    } else {
        for (const k of SECONDARIES) stats[k] = b.sec / 4;
    }
    return {
        stats,
        statsSource: measured ? 'budget' : 'budget-borrowed',
        splitSource: pair ? 'settings.craftedStats' : 'equal-placeholder',
    };
}

function loadTable(files, fs) {
    const table = newTable();
    for (const f of files) {
        const text = fs.readFileSync(f, 'utf8');
        if (/\.json$/i.test(f)) readJsonInto(table, JSON.parse(text), f);
        else readSavedVariablesInto(table, text, f);
    }
    return table;
}

module.exports = {
    SECONDARIES,
    BUDGET_GROUP,
    INVTYPE_SLOT,
    newTable,
    addPoint,
    parseLevelStat,
    readSavedVariablesInto,
    readJsonInto,
    loadTable,
    buildBudget,
    budgetAt,
    craftedPair,
    itemStats,
};
