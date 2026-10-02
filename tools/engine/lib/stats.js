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
// Client sources, all read out of a SavedVariables transcript:
//
//   capture itemstats  (E-0a, WKE-675; read since E-0f, WKE-676) - what
//                      `C_Item.GetItemStats` answers for a worn, bag, vault or
//                      journal link with its enchant and gems blanked, at the
//                      level `GetDetailedItemLevelInfo` gives that link. The
//                      keys are the client's own (the 2026-10-01 transcript):
//                      `ITEM_MOD_VERSATILITY` has no `_SHORT`. Indexed by
//                      `id@level`, by the stripped link and by `id` + bonus
//                      IDs (what an export's `equipped[]` entry carries). Where
//                      it and `capture upgrade` both name an `id@level`, this
//                      one is kept.
//   capture upgrade    (decision 2026-09-14 evening) - `GetItemUpgradeItemInfo()
//                      .upgradeLevelInfos[].levelStats`: an owned item's stats
//                      at each level of its track; two levels of one item give
//                      the scale, never guessed.
//   capture linklevel  (E-0g step 2, WKE-677) - for each journal row the
//                      capture took, `GetItemStats` on the journal link REBUILT
//                      with the track step that draws the walk's level (the
//                      `track-append` variant for the lower track, the rule
//                      ns.EngineStats installs), kept only when the client drew
//                      it at the walk's level in all three reads. Indexed by
//                      `id@walkLevel` and by the rebuilt link: real client
//                      reads at the level the Upgrade Finder row names. Where
//                      `capture itemstats` already names the `id@level`, that
//                      read is kept.
//
// A plain JSON table
// (`{ items: [{ id, level, slot, stats: { int, haste, crit, mastery, vers, leech } }] }`)
// is accepted for tests and for hand-checked tables. Every point carries the
// source it was read from, and a `client` row says which (`clientSource`).
'use strict';

const { parseSavedVariables, luaArray } = require('../../companion/lib/lua-savedvariables');
const { STATS, zeroStats } = require('./score');

const SECONDARIES = ['haste', 'crit', 'mastery', 'vers'];

// `C_Item.GetItemStats`' keys for the six stats the model reads, as the
// 2026-10-01 transcript names them. Stamina, armour, sockets, DPS and the rest
// are read by the client and not by this model.
const ITEMSTATS_KEYS = {
    ITEM_MOD_INTELLECT_SHORT: 'int',
    ITEM_MOD_HASTE_RATING_SHORT: 'haste',
    ITEM_MOD_CRIT_RATING_SHORT: 'crit',
    ITEM_MOD_MASTERY_RATING_SHORT: 'mastery',
    ITEM_MOD_VERSATILITY: 'vers',
    ITEM_MOD_CR_LIFESTEAL_SHORT: 'leech',
};

const SOURCE_ITEMSTATS = 'capture itemstats';
const SOURCE_UPGRADE = 'capture upgrade';
const SOURCE_LINKLEVEL = 'capture linklevel';

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
    return { points: new Map(), byLink: new Map(), byBonus: new Map(), slotOf: new Map(), sources: [], patch: null };
}

// `override` lets a later, more direct read replace a point already held.
function addPoint(table, id, level, stats, slot, source, override) {
    const key = `${id}@${level}`;
    const held = table.points.get(key);
    const point = { id, level, stats, source: source || 'json' };
    if (!held || (override && held.source !== point.source)) table.points.set(key, point);
    if (slot && !table.slotOf.has(id)) table.slotOf.set(id, slot);
    return table.points.get(key);
}

// The item string inside a link, split on ':' (field 1 is the itemID).
function linkFields(link) {
    const m = String(link || '').match(/\|Hitem:([^|]+)\|h/) || String(link || '').match(/^item:([^|]+)$/);
    return m ? m[1].split(':') : null;
}

// `item:` plus the body with fields 2-6 (enchant, four gems) blanked: the key
// `ns.EngineStats` caches under, and the link the capture asked about.
function strippedKey(link) {
    const f = linkFields(link);
    if (!f || !(Number(f[0]) > 0)) return null;
    for (let i = 1; i <= 5 && i < f.length; i++) f[i] = '';
    return `item:${f.join(':')}`;
}

// `id:b1:b2:...`, the bonus IDs sorted: what a link and an export's
// `equipped[]` entry (`id`, `bonusIDs`) have in common.
function bonusKey(id, bonusIDs) {
    if (!(Number(id) > 0) || !Array.isArray(bonusIDs)) return null;
    return [Number(id), ...bonusIDs.map(Number).sort((a, b) => a - b)].join(':');
}

// The bonus IDs a link names (field 13 counts them, the IDs follow).
function linkBonusIDs(link) {
    const f = linkFields(link);
    if (!f) return null;
    const n = Number(f[12]) || 0;
    return f.slice(13, 13 + n).map(Number);
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

// `GetItemStats`' table, as the capture stored it, into the model's six stats.
function statsFromItemStats(raw) {
    const stats = zeroStats();
    for (const [key, value] of Object.entries(raw || {})) {
        const k = ITEMSTATS_KEYS[key];
        if (k && typeof value === 'number') stats[k] = value;
    }
    return stats;
}

// Every `itemstats` snapshot's items, one record each: where it came from, the
// link, the level the client gives that link, the base stats (`strippedStats`,
// the link with enchant and gems blanked) and the slot. Shared by the reader
// below and by `extract-itemstats.js`.
function itemStatsRecords(caps) {
    const out = [];
    for (const snap of luaArray(caps.itemstats || {})) {
        const items = snap && snap.data && snap.data.items;
        for (const it of luaArray(items || {})) {
            const base = (it.strippedStats && it.strippedStats[1]) || (it.stats && it.stats[1]);
            const level = it.detailedLevel && it.detailedLevel[1];
            out.push({
                snapshot: snap,
                item: it,
                link: it.link,
                itemID: it.itemID,
                level: typeof level === 'number' ? level : null,
                raw: base && typeof base === 'object' ? base : null,
                slot: (it.info && INVTYPE_SLOT[it.info.itemEquipLoc]) || null,
            });
        }
    }
    return out;
}

function readItemStatsInto(table, caps, label) {
    let read = 0;
    let points = 0;
    for (const rec of itemStatsRecords(caps)) {
        if (!rec.raw || rec.level === null || !(rec.itemID > 0)) continue;
        read += 1;
        const before = table.points.size;
        const prior = table.points.get(`${rec.itemID}@${rec.level}`);
        const point = addPoint(table, rec.itemID, rec.level, statsFromItemStats(rec.raw), rec.slot, SOURCE_ITEMSTATS, true);
        if (table.points.size > before || (prior && prior !== point)) points += 1;
        const sk = strippedKey(rec.link);
        if (sk) table.byLink.set(sk, point);
        const bk = bonusKey(rec.itemID, linkBonusIDs(rec.link));
        if (bk) table.byBonus.set(bk, point);
        const build = rec.snapshot.build && rec.snapshot.build[1];
        if (build && !table.patch) table.patch = build;
    }
    if (read) table.sources.push({ file: label, kind: 'capture itemstats (GetItemStats)', items: read, newPoints: points });
    return read;
}

// Every `linklevel` snapshot's rebuilt-link reads, one per candidate a track
// step draws: the first `track-append` variant (the variants follow
// TrackBonusesAt's order, lowest track first), its `after` stats, filed under
// the walk's level - only when `before`, `journal` and `after` all answered
// that level. Shared by the reader below and its test.
function linkLevelRecords(caps) {
    const out = [];
    for (const snap of luaArray(caps.linklevel || {})) {
        const candidates = snap && snap.data && snap.data.candidates;
        for (const c of luaArray(candidates || {})) {
            const variant = luaArray(c.variants || {}).find((v) => v.rule === 'track-append');
            if (!variant) continue;
            const levels = ['before', 'journal', 'after'].map((k) => variant[k] && variant[k].detailedLevel && variant[k].detailedLevel[1]);
            if (!levels.every((l) => l === c.walkLevel)) continue;
            const raw = variant.after.stats && variant.after.stats[1];
            if (!raw || typeof raw !== 'object') continue;
            out.push({ snapshot: snap, candidate: c, variant, link: variant.link, itemID: c.itemID, level: c.walkLevel, raw, slot: c.slot || null });
        }
    }
    return out;
}

function readLinkLevelInto(table, caps, label) {
    let read = 0;
    let points = 0;
    for (const rec of linkLevelRecords(caps)) {
        read += 1;
        const before = table.points.size;
        const point = addPoint(table, rec.itemID, rec.level, statsFromItemStats(rec.raw), rec.slot, SOURCE_LINKLEVEL);
        if (table.points.size > before) points += 1;
        const sk = strippedKey(rec.link);
        if (sk && !table.byLink.has(sk)) table.byLink.set(sk, point);
        const build = rec.snapshot.build && rec.snapshot.build[1];
        if (build && !table.patch) table.patch = build;
    }
    if (read) table.sources.push({ file: label, kind: 'capture linklevel (GetItemStats on the rebuilt link)', items: read, newPoints: points });
    return read;
}

// The client's base stats for a link, from `capture itemstats`, or null.
function statsForLink(table, link) {
    const sk = strippedKey(link);
    const p = sk && table.byLink.get(sk);
    return p ? { ...p.stats } : null;
}

function readSavedVariablesInto(table, text, label) {
    const sv = parseSavedVariables(text);
    const db = sv.LootpathDB;
    const caps = db && db.global && db.global.captures;
    if (!caps) throw new Error(`${label}: no LootpathDB.global.captures`);
    readItemStatsInto(table, caps, label);
    readLinkLevelInto(table, caps, label);
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
                addPoint(table, it.itemID, level, stats, null, SOURCE_UPGRADE);
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
        addPoint(table, it.id, it.level, stats, it.slot, 'json');
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

// The stat vector for one item (a row, or a worn entry). A worn entry that
// carries `bonusIDs` is matched to the client's read of the same item string
// first; then `id@level`.
function itemStats(table, budget, item, opts) {
    const options = opts || {};
    const byBonus = item.bonusIDs && table.byBonus.get(bonusKey(item.id, item.bonusIDs));
    if (byBonus) return { stats: { ...byBonus.stats }, statsSource: 'client', splitSource: 'client', clientSource: byBonus.source, matchedBy: 'link' };
    const exact = table.points.get(`${item.id}@${item.level}`);
    if (exact) return { stats: { ...exact.stats }, statsSource: 'client', splitSource: 'client', clientSource: exact.source, matchedBy: 'level' };
    const own = [...table.points.values()].filter((p) => p.id === item.id);
    if (own.length && budget.intSlope !== null && budget.secSlope !== null) {
        own.sort((a, b) => Math.abs(a.level - item.level) - Math.abs(b.level - item.level));
        const from = own[0];
        const fI = Math.exp(budget.intSlope * (item.level - from.level));
        const fS = Math.exp(budget.secSlope * (item.level - from.level));
        const stats = zeroStats();
        stats.int = from.stats.int * fI;
        for (const k of ['haste', 'crit', 'mastery', 'vers', 'leech']) stats[k] = from.stats[k] * fS;
        return { stats, statsSource: 'client-scaled', splitSource: 'client', scaledFrom: from.level, clientSource: from.source };
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
    ITEMSTATS_KEYS,
    SOURCE_ITEMSTATS,
    SOURCE_UPGRADE,
    SOURCE_LINKLEVEL,
    linkLevelRecords,
    readLinkLevelInto,
    strippedKey,
    bonusKey,
    linkBonusIDs,
    statsFromItemStats,
    itemStatsRecords,
    readItemStatsInto,
    statsForLink,
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
