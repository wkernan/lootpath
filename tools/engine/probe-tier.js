#!/usr/bin/env node
// The tier probe (E-0k, WKE-682). DEV ONLY - nothing here ships.
//
//   node probe-tier.js --compare <SavedVariables.lua> --week 2026-09-29
//        --char "Hotornot - Arthas" [--tier2 0.03 --tier4 0.055]
//        [--stats <capture.lua> ... --key-levels 1=2,... --qe <dir>]
//
// Asks why the compare's tier k (least-squares scale of ours onto theirs,
// EngineCompare.Scale; k > 1 means ours SMALLER) differs by band on the rows a
// real compare STORED, where armour's does not. Each suspect the issue names
// is a re-score of the stored rows, never a guess:
//
//   stored      the rows as stored: `ours` (floored at UF_FLOOR) and `raw`
//   S1/S3       the tier multiplier varied over a grid of 2- and 4-piece
//               values, added (E-0c's rule, 1 + t2 + t4) or multiplied
//               ((1 + t2)(1 + t4)), forced on both sides as EngineScore and QE
//               Live's Upgrade Finder both force it
//   S2          the same, NOT forced: a non-tier drop in a tier slot breaks
//               the worn set's bonuses (the reading forceTier would prevent)
//   S4          the gap by the WORN piece the row replaces (a tier piece, a
//               catalysed tier piece, a non-tier piece), and the offset per
//               slot that brings each row to armour's k
//   refit       (with --stats) the band refitted on the measured document
//               itself, in sample: if no weight vector closes the gap, it is
//               not the weights
//
// The re-score is exact without the item stats: the game's percent is
// 100 (V1 - V0) / V0 with V = L x M(set), and with tier forced M(with) =
// M(worn), so L1 / L0 = 1 + raw / 100. Any other multiplier rule gives
// 100 (L1 M'(with) / (L0 M'(worn)) - 1), floored as the compare floors.
//
// SIGN: theirs is `upgradePercent`, positive = better (UFImport's convention,
// ARCHITECTURE.md section 7 2026-09-08), read as-is.
'use strict';

const fs = require('fs');
const path = require('path');
const { parseSavedVariables, luaArray } = require('../companion/lib/lua-savedvariables');
const { INVTYPE_SLOT, linkBonusIDs } = require('./lib/stats');
const { tierMultiplier } = require('./lib/score');
const { UF_FLOOR } = require('./percent-scale');

const TIER_SLOTS = ['Head', 'Shoulder', 'Chest', 'Hands', 'Legs'];
// QE Live's Restoration Druid bonusHPS, the values the fit writes (E-0i).
const DEFAULT_T2 = 0.03;
const DEFAULT_T4 = 0.055;
const GRID = [0, 0.01, 0.02, 0.03, 0.04, 0.055, 0.07, 0.085, 0.1, 0.15];

function list(t) {
    if (!t) return [];
    return Array.isArray(t) ? t : luaArray(t);
}

function parseArgs(argv) {
    const o = { compare: null, week: null, char: null, tier2: DEFAULT_T2, tier4: DEFAULT_T4, stats: [], keyLevels: {}, qe: null };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        const next = () => {
            if (i + 1 >= argv.length) throw new Error(`${a} needs a value`);
            i += 1;
            return argv[i];
        };
        if (a === '--compare') o.compare = next();
        else if (a === '--week') o.week = next();
        else if (a === '--char') o.char = next();
        else if (a === '--tier2') o.tier2 = Number(next());
        else if (a === '--tier4') o.tier4 = Number(next());
        else if (a === '--stats') o.stats.push(next());
        else if (a === '--qe') o.qe = next();
        else if (a === '--key-levels') {
            for (const pair of next().split(',')) {
                const [k, v] = pair.split('=');
                o.keyLevels[k] = v;
            }
        } else throw new Error(`unknown option ${a}`);
    }
    return o;
}

const floor = (x) => Math.max(UF_FLOOR, x);

// EngineCompare.Scale and EngineCompare.MAE over `{ ours, theirs }`.
function scale(rows) {
    let a = 0;
    let b = 0;
    for (const r of rows) {
        a += r.ours * r.theirs;
        b += r.ours * r.ours;
    }
    return b > 0 ? a / b : null;
}

function mae(rows, k) {
    if (!rows.length || k === null) return null;
    return rows.reduce((s, r) => s + Math.abs(k * r.ours - r.theirs), 0) / rows.length;
}

function km(rows) {
    const k = scale(rows);
    return { n: rows.length, k, maeK: mae(rows, k) };
}

// The modifier list of an item link after its bonus IDs: { [type] = value }.
// Type 64 is the catalyst's redirected base stats (the source item's ID),
// the same field the companion writes as `redirected_base_stats`.
function linkModifiers(link) {
    const m = /item:([-\d:]*)/.exec(String(link || ''));
    if (!m) return {};
    const f = m[1].split(':');
    const nBonus = Number(f[12]) || 0;
    let i = 13 + nBonus;
    const nMods = Number(f[i]) || 0;
    const out = {};
    for (let j = 0; j < nMods; j++) out[Number(f[i + 1 + 2 * j])] = Number(f[i + 2 + 2 * j]);
    return out;
}

// The worn tier-slot pieces as the client read them: the newest `capture
// itemstats` snapshot's worn items, each with its setID (GetItemInfo's) and,
// for a catalysed piece, the item its stats come from.
function wornTierSlots(sv) {
    const snaps = list(sv.LootpathDB.global.captures && sv.LootpathDB.global.captures.itemstats);
    if (!snaps.length) throw new Error('no capture itemstats snapshot to read the worn set from');
    const snap = snaps.reduce((a, b) => ((b.capturedAt || 0) > (a.capturedAt || 0) ? b : a));
    const out = {};
    for (const it of list(snap.data.items)) {
        if (it.source !== 'worn') continue;
        const slot = it.info && INVTYPE_SLOT[it.info.itemEquipLoc];
        if (!TIER_SLOTS.includes(slot)) continue;
        const mods = linkModifiers(it.link);
        out[slot] = {
            itemID: Number((/item:(\d+)/.exec(it.link) || [])[1]),
            level: typeof it.detailedLevel === 'number' ? it.detailedLevel : list(it.detailedLevel)[0],
            setID: (it.info && it.info.setID) || 0,
            catalysedFrom: mods[64] || null,
            bonusIDs: linkBonusIDs(it.link) || [],
        };
    }
    return { capturedAt: snap.capturedAt, slots: out };
}

function kindOf(worn) {
    if (!worn) return 'none';
    if (!worn.setID) return 'non-tier';
    return worn.catalysedFrom ? 'catalysed tier' : 'tier';
}

// The tier multiplier of the worn set and of the set with the row's drop in
// its slot (the drop is not a set piece: every tier-class row is a raid or
// dungeon drop without a setID), under one rule.
function setPieces(wornSlots) {
    return Object.values(wornSlots).filter((w) => w.setID);
}

function multiplierFor(rule, pieces, t2, t4) {
    const setIDs = [...new Set(pieces.map((p) => p.setID))];
    const items = pieces.map((p) => ({ setId: p.setID }));
    if (rule === 'additive-forced') return tierMultiplier(items, { setIDs, twoPiece: t2, fourPiece: t4, forceTier: true });
    if (rule === 'additive-counted') return tierMultiplier(items, { setIDs, twoPiece: t2, fourPiece: t4, forceTier: false });
    const n = items.length;
    if (rule === 'multiplicative-forced') return (1 + t2) * (1 + t4);
    if (rule === 'multiplicative-counted') return (n >= 2 ? 1 + t2 : 1) * (n >= 4 ? 1 + t4 : 1);
    throw new Error(`no rule ${rule}`);
}

function rescore(row, wornSlots, rule, t2, t4) {
    const before = setPieces(wornSlots);
    const after = before.filter((p) => p !== wornSlots[row.slot]);
    const ratio = 1 + row.raw / 100;
    const mWorn = multiplierFor(rule, before, t2, t4);
    const mWith = multiplierFor(rule, after, t2, t4);
    return floor(100 * ((ratio * mWith) / mWorn - 1));
}

function storedDocuments(sv, week, char) {
    const g = sv.LootpathDB.global;
    const store = g.engineCompare || (g.developer && g.developer.engineCompare) || {};
    const entry = store[week] && store[week][char];
    if (!entry) throw new Error(`no stored compare for ${week} / ${char}`);
    const out = [];
    for (const [ct, docs] of Object.entries(entry)) {
        for (const [doc, e] of Object.entries(docs)) {
            if (/^pass/.test(doc)) continue;
            const rows = list(e.rows).map((r) => ({ key: r.key, slot: r.slot, cls: r.class, level: r.level, theirs: r.theirs, ours: r.ours, raw: r.raw, link: r.link }));
            out.push({ contentType: ct, document: doc, band: e.band, derivedAt: e.derivedAt, qeExportedAt: e.qeExportedAt, rows });
        }
    }
    return out.sort((a, b) => String(a.qeExportedAt).localeCompare(String(b.qeExportedAt)));
}

function probeDocument(doc, worn, t2, t4) {
    const tier = doc.rows.filter((r) => r.cls === 'tier');
    const armour = doc.rows.filter((r) => r.cls === 'armour');
    const out = { contentType: doc.contentType, document: doc.document, band: doc.band, stored: { tier: km(tier), armour: km(armour) } };

    // S1 / S3 / S2: the multiplier varied, each rule over the whole grid.
    out.rules = {};
    for (const rule of ['additive-forced', 'multiplicative-forced', 'additive-counted', 'multiplicative-counted']) {
        const at = (a, b) => km(tier.map((r) => ({ ...r, ours: rescore(r, worn.slots, rule, a, b) })));
        const grid = [];
        for (const a of GRID) for (const b of GRID) grid.push({ t2: a, t4: b, ...at(a, b) });
        const ks = grid.map((g) => g.k).filter((k) => k !== null);
        const best = grid.filter((g) => g.k !== null).reduce((x, y) => (Math.abs(y.k - out.stored.armour.k) < Math.abs(x.k - out.stored.armour.k) ? y : x), grid.find((g) => g.k !== null) || grid[0]);
        out.rules[rule] = { atFit: at(t2, t4), kMin: ks.length ? Math.min(...ks) : null, kMax: ks.length ? Math.max(...ks) : null, nullK: grid.length - ks.length, best };
    }

    // S4: by the worn piece the row replaces, and the offset per slot.
    out.byWorn = {};
    for (const slot of TIER_SLOTS) {
        const rs = tier.filter((r) => r.slot === slot);
        if (!rs.length) continue;
        const w = worn.slots[slot];
        const kArm = out.stored.armour.k;
        const pos = rs.filter((r) => r.theirs > 0);
        const offset = pos.length ? pos.reduce((s, r) => s + (r.theirs / kArm - r.raw), 0) / pos.length : null;
        out.byWorn[slot] = { worn: w ? `${w.itemID}@${w.level}` : null, kind: kindOf(w), catalysedFrom: w && w.catalysedFrom, ...km(rs), positive: pos.length, offset };
    }
    const byKind = {};
    for (const r of tier) (byKind[kindOf(worn.slots[r.slot])] = byKind[kindOf(worn.slots[r.slot])] || []).push(r);
    out.byKind = {};
    for (const [kind, rs] of Object.entries(byKind)) out.byKind[kind] = km(rs);
    return out;
}

// In sample: the band refitted on the measured document itself (the
// documents the same SavedVariables stored, scored against its inventory
// snapshot 4, as percent-scale.js reads them), beside the dev weights' fit.
function refit(o, sv) {
    const { loadTable, buildBudget } = require('./lib/stats');
    const { fitDocument, prepare, DEFAULT_EFFECT_IDS } = require('./lib/fit');
    const { DEFAULT_DR } = require('./lib/dr');
    const { STATS } = require('./lib/score');
    const { bandKey } = require('./fit-weights');
    const { wornFromCapture, documentsFromCapture } = require('./percent-scale');
    const CLASS = { Head: 'tier', Shoulder: 'tier', Chest: 'tier', Hands: 'tier', Legs: 'tier', Back: 'armour', Wrist: 'armour', Waist: 'armour', Feet: 'armour' };
    const table = loadTable(o.stats, fs);
    const docs = documentsFromCapture(sv, wornFromCapture(sv, 4));
    const fitDocs = fs
        .readdirSync(o.qe)
        .filter((f) => /^qe-upgradefinder-.*\.json$/.test(f))
        .sort()
        .map((f) => JSON.parse(fs.readFileSync(path.join(o.qe, f), 'utf8')));
    for (const d of [...fitDocs, ...docs]) for (const r of [...d.equipped, ...d.items]) if (r.slot && !table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
    const budget = buildBudget(table);
    const opts = { effectIds: DEFAULT_EFFECT_IDS, assumedFinish: {}, dr: DEFAULT_DR, resamples: 0 };
    const band = (fit) => ({ baseValue: fit.baseValue, w: STATS.map((k) => fit.weights[k]) });
    const dev = {};
    for (const d of fitDocs.slice().sort((a, b) => String(a.exportedAt).localeCompare(String(b.exportedAt)))) dev[bandKey(d, o.keyLevels)] = band(fitDocument(d, table, budget, opts));
    const dot = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);
    const out = [];
    for (const doc of docs.sort((a, b) => String(a.exportedAt).localeCompare(String(b.exportedAt)))) {
        const key = doc.contentType === 'Raid' ? Object.keys(dev).find((k) => k.startsWith('raid-')) : String(doc.keyLevel);
        if (!dev[key]) continue;
        const prep = prepare(doc, table, budget, opts);
        const score = (b) => {
            const v = b.baseValue + dot(b.w, prep.xWorn);
            const rows = prep.rows
                .filter((r) => r.diffs && r.excluded !== 'effect' && r.excluded !== 'duplicate' && CLASS[r.slot])
                .map((r) => ({ cls: CLASS[r.slot], theirs: r.observed, ours: floor((100 * Math.max(...r.diffs.map((c) => dot(c.d, b.w)))) / v) }));
            return { tier: km(rows.filter((r) => r.cls === 'tier')), armour: km(rows.filter((r) => r.cls === 'armour')) };
        };
        out.push({ contentType: doc.contentType, keyLevel: doc.keyLevel, band: key, dev: score(dev[key]), inSample: score(band(fitDocument(doc, table, budget, opts))) });
    }
    return out;
}

function run(argv, log) {
    const say = log || console.log;
    const o = parseArgs(argv);
    if (!o.compare || !o.week || !o.char) throw new Error('--compare, --week and --char are required');
    const sv = parseSavedVariables(fs.readFileSync(o.compare, 'utf8'));
    const worn = wornTierSlots(sv);
    const docs = storedDocuments(sv, o.week, o.char);
    const f = (x) => (x === null || x === undefined ? '-' : x.toFixed(3));
    const kmText = (m) => `n ${m.n} k ${f(m.k)} MAE@k ${f(m.maeK)}`;

    say(`worn tier slots (capture itemstats ${worn.capturedAt}): ${TIER_SLOTS.map((s) => {
        const w = worn.slots[s];
        return w ? `${s} ${w.itemID}@${w.level} ${kindOf(w)}${w.catalysedFrom ? ` from ${w.catalysedFrom}` : ''}` : `${s} -`;
    }).join('; ')}`);
    say(`tier multiplier at the fit's values: t2 ${o.tier2}, t4 ${o.tier4}; grid ${GRID.join(' ')} for each`);
    const result = { worn, documents: [], refit: null };
    for (const doc of docs) {
        const p = probeDocument(doc, worn, o.tier2, o.tier4);
        result.documents.push(p);
        say('');
        say(`== ${p.contentType} [${p.document}], band ${p.band} ==`);
        say(`  stored      tier ${kmText(p.stored.tier)} | armour ${kmText(p.stored.armour)}`);
        for (const [rule, r] of Object.entries(p.rules)) {
            say(`  ${rule.padEnd(22)} at fit: ${kmText(r.atFit)}; over the grid k ${f(r.kMin)}..${f(r.kMax)}${r.nullK ? ` (${r.nullK} pairs with every row floored)` : ''}; nearest armour: t2 ${r.best.t2} t4 ${r.best.t4} k ${f(r.best.k)}`);
        }
        for (const [slot, b] of Object.entries(p.byWorn)) {
            say(`  replaces ${slot.padEnd(8)} worn ${String(b.worn).padEnd(10)} ${b.kind.padEnd(14)} ${kmText(b)}; positive ${b.positive}; offset at armour k ${f(b.offset)}`);
        }
        say(`  by worn kind: ${Object.entries(p.byKind).map(([kind, m]) => `${kind} ${kmText(m)}`).join('; ')}`);
    }
    if (o.stats.length) {
        if (!o.qe) throw new Error('--stats needs --qe <dir> for the dev bands');
        result.refit = refit(o, sv);
        say('');
        say('== refit: the dev bands vs the band refitted on the measured document itself (offline stats, floored) ==');
        for (const r of result.refit) {
            say(`  ${r.contentType} ${r.contentType === 'Raid' ? '' : `+${r.keyLevel} `}band ${r.band}: dev tier ${kmText(r.dev.tier)}, armour ${kmText(r.dev.armour)} | in sample tier ${kmText(r.inSample.tier)}, armour ${kmText(r.inSample.armour)}`);
        }
    }
    return result;
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(`probe-tier: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, rescore, multiplierFor, linkModifiers, wornTierSlots, storedDocuments, scale, mae, GRID };
