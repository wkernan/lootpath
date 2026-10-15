#!/usr/bin/env node
// The percent-scale harness (E-0j, WKE-681). DEV ONLY - nothing here ships.
//
//   node percent-scale.js --stats <capture.lua> [--stats ...]
//        --key-levels 1=2,2=4,4=6,6=8,7=10
//        --measure <capture.lua> [--inventory 4]
//        [--compare <SavedVariables.lua> --week 2026-09-29 --char "Hotornot - Arthas"]
//        <fit export.json|dir> ...
//
// Asks why the compare's k (the least-squares scale of ours onto theirs,
// `theirs ~ k x ours`, EngineCompare.Scale) moved with the band. It fits the
// bands exactly as fit-weights.js does, then scores the Upgrade Finder
// documents STORED in the `--measure` capture (`db.char.ufImportsByLevel`,
// the documents a compare run that day read) against that capture's worn set
// (its inventory snapshot `--inventory`, the 1-based index), and prints k per
// slot class under each alternative:
//
//   game        100 x dV / V(worn), V(worn) = baseValue + w . x(worn): what
//               EngineScore.UpgradePercent computes (the tier multiplier is
//               forced on both sides and cancels), every row
//   pin100      dV alone: the worn set pinned at the fit's 100 (suspect 1)
//   floored     game, ours floored at EngineCompare.UF_FLOOR (0) the way the
//               Upgrade Finder floors theirs - the compare since E-0j
//   uncensored  game, the rows whose theirs is exactly 0 left out
//   client-fit  the bands refitted on rows whose stats are client reads
//               (client / client-scaled) only (suspect 2), game and floored
//
// With `--compare`, the same k raw and floored over the rows a real compare
// STORED in that SavedVariables (`db.global.engineCompare[week][char]`),
// which are the client's own `ours`.
//
// SIGN: theirs is `upgradePercent`, positive = better (UFImport's convention,
// ARCHITECTURE.md section 7 2026-09-08), read as-is.
'use strict';

const fs = require('fs');
const path = require('path');
const { parseSavedVariables, luaArray } = require('../companion/lib/lua-savedvariables');
const { loadTable, buildBudget, INVTYPE_SLOT, linkBonusIDs } = require('./lib/stats');
const { fitDocument, prepare, DEFAULT_EFFECT_IDS } = require('./lib/fit');
const { DEFAULT_DR } = require('./lib/dr');
const { STATS } = require('./lib/score');
const { bandKey } = require('./fit-weights');

// EngineCompare.UF_FLOOR: the Upgrade Finder never reports below this.
const UF_FLOOR = 0;
const CLASSES = ['tier', 'armour', 'jewellery'];
const CLASS_OF_SLOT = { Head: 'tier', Shoulder: 'tier', Chest: 'tier', Hands: 'tier', Legs: 'tier', Back: 'armour', Wrist: 'armour', Waist: 'armour', Feet: 'armour', Neck: 'jewellery', Finger: 'jewellery' };

function parseArgs(argv) {
    const o = { stats: [], exports: [], keyLevels: {}, inventory: 4, measure: null, compare: null, week: null, char: null };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        const next = () => {
            if (i + 1 >= argv.length) throw new Error(`${a} needs a value`);
            i += 1;
            return argv[i];
        };
        if (a === '--stats') o.stats.push(next());
        else if (a === '--key-levels') {
            for (const pair of next().split(',')) {
                const [k, v] = pair.split('=');
                o.keyLevels[k] = v;
            }
        } else if (a === '--measure') o.measure = next();
        else if (a === '--inventory') o.inventory = Number(next());
        else if (a === '--compare') o.compare = next();
        else if (a === '--week') o.week = next();
        else if (a === '--char') o.char = next();
        else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
        else o.exports.push(a);
    }
    return o;
}

function list(t) {
    if (!t) return [];
    return Array.isArray(t) ? t : luaArray(t);
}

// k minimising sum (theirs - k * ours)^2 - EngineCompare.Scale.
function scale(rows, oursOf) {
    let a = 0;
    let b = 0;
    for (const r of rows) {
        const o = oursOf(r);
        a += o * r.theirs;
        b += o * o;
    }
    return b > 0 ? a / b : null;
}

const floor = (x) => Math.max(UF_FLOOR, x);
const dot = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);

// The worn set as the capture's inventory snapshot read it, in the export's
// `equipped[]` shape so lib/stats finds each item's client read by link.
function wornFromCapture(sv, index) {
    const snaps = list(sv.LootpathDB.global.captures.inventory);
    const snap = snaps[index - 1];
    if (!snap) throw new Error(`no inventory snapshot ${index}`);
    return list(snap.data.equipped).map((e) => {
        const link = list(e.link)[0];
        const instant = list(e.item && e.item.instant);
        const level = list(e.item && e.item.detailedLevel)[0];
        return { id: list(e.itemID)[0], level, slot: INVTYPE_SLOT[instant[3]] || null, bonusIDs: linkBonusIDs(link) || [] };
    });
}

function isDrop(entry) {
    if (entry.dropType === 'drop') return true;
    return list(entry.sources).some((s) => s.dropType === 'drop') || Object.values(entry.sources || {}).some((s) => s && s.dropType === 'drop');
}

// The stored Upgrade Finder documents of the capture, in the export's shape.
function documentsFromCapture(sv, worn) {
    const docs = [];
    for (const ch of Object.values(sv.LootpathDB.char || {})) {
        const byLevel = ch.ufImportsByLevel || {};
        for (const [ct, levels] of Object.entries(byLevel)) {
            for (const [level, v] of Object.entries(levels)) {
                const items = Object.values(v.items || {})
                    .filter(isDrop)
                    .map((e) => ({ id: e.itemID, level: e.level, slot: e.slot, dropLoc: e.dropLoc, upgradePercent: e.upgradePercent }));
                docs.push({ reportId: v.reportId, exportedAt: v.exportedAt, contentType: ct, keyLevel: Number(level), settings: v.settings, equipped: worn, items });
            }
        }
    }
    return docs;
}

function fitBands(fitDocs, table, budget, keyLevels, keepRow) {
    const bands = {};
    const opts = { effectIds: DEFAULT_EFFECT_IDS, assumedFinish: {}, dr: DEFAULT_DR, resamples: 0 };
    for (const d of fitDocs.slice().sort((a, b) => String(a.exportedAt).localeCompare(String(b.exportedAt)))) {
        let doc = d;
        if (keepRow) {
            const prep = prepare(d, table, budget, opts);
            const keep = new Set(prep.rows.filter(keepRow).map((r) => `${r.id}@${r.level}`));
            doc = { ...d, items: d.items.filter((r) => keep.has(`${r.id}@${r.level}`)) };
        }
        const fit = fitDocument(doc, table, budget, opts);
        bands[bandKey(d, keyLevels)] = { baseValue: fit.baseValue, w: STATS.map((k) => fit.weights[k]), fitted: fit.counts.fitted, document: d.reportId };
    }
    return bands;
}

// Every comparable drop row of a measured document under one band.
function measure(doc, band, table, budget) {
    const opts = { effectIds: DEFAULT_EFFECT_IDS, assumedFinish: {}, dr: DEFAULT_DR };
    const prep = prepare(doc, table, budget, opts);
    const vWorn = band.baseValue + dot(band.w, prep.xWorn);
    const rows = [];
    for (const r of prep.rows) {
        if (!r.diffs || r.excluded === 'effect' || r.excluded === 'duplicate') continue;
        const delta = Math.max(...r.diffs.map((c) => dot(c.d, band.w)));
        rows.push({ key: `${r.id}@${r.level}`, cls: CLASS_OF_SLOT[r.slot] || 'other', theirs: r.observed, delta, game: (100 * delta) / vWorn, statsSource: r.statsSource });
    }
    const wornSources = {};
    for (const x of prep.worn) wornSources[x.statsSource] = (wornSources[x.statsSource] || 0) + 1;
    return { vWorn, rows, wornSources };
}

function classTable(rows) {
    const out = {};
    for (const cls of CLASSES) {
        const rs = rows.filter((r) => r.cls === cls);
        const unc = rs.filter((r) => r.theirs !== 0);
        out[cls] = {
            n: rs.length,
            censored: rs.length - unc.length,
            game: scale(rs, (r) => r.game),
            pin100: scale(rs, (r) => r.delta),
            floored: scale(rs, (r) => floor(r.game)),
            uncensored: scale(unc, (r) => r.game),
        };
    }
    return out;
}

function storedRows(svPath, week, char) {
    const sv = parseSavedVariables(fs.readFileSync(svPath, 'utf8'));
    const entry = sv.LootpathDB.global.engineCompare[week][char];
    const out = [];
    for (const [ct, docs] of Object.entries(entry)) {
        for (const [doc, e] of Object.entries(docs)) {
            if (doc === 'pass1') continue;
            const rows = list(e.rows).map((r) => ({ key: r.key, cls: r.class, theirs: r.theirs, ours: r.ours }));
            const byClass = {};
            for (const cls of CLASSES) {
                const rs = rows.filter((r) => r.cls === cls);
                byClass[cls] = { n: rs.length, censored: rs.filter((r) => r.theirs === 0).length, raw: scale(rs, (r) => r.ours), floored: scale(rs, (r) => floor(r.ours)) };
            }
            out.push({ contentType: ct, document: doc, band: e.band, derivedAt: e.derivedAt, qeExportedAt: e.qeExportedAt, byClass });
        }
    }
    return out;
}

function expandExports(args) {
    const files = [];
    for (const a of args) {
        if (fs.statSync(a).isDirectory()) {
            for (const f of fs.readdirSync(a).sort()) if (/^qe-upgradefinder-.*\.json$/.test(f)) files.push(path.join(a, f));
        } else files.push(a);
    }
    return files;
}

function run(argv, log) {
    const say = log || console.log;
    const o = parseArgs(argv);
    if (!o.stats.length) throw new Error('--stats is required');
    if (!o.measure) throw new Error('--measure <capture.lua> is required');
    const fitDocs = expandExports(o.exports).map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
    if (!fitDocs.length) throw new Error('no Upgrade Finder export to fit');
    const table = loadTable(o.stats, fs);
    const sv = parseSavedVariables(fs.readFileSync(o.measure, 'utf8'));
    const worn = wornFromCapture(sv, o.inventory);
    const docs = documentsFromCapture(sv, worn);
    for (const d of [...fitDocs, ...docs]) for (const r of [...d.equipped, ...d.items]) if (r.slot && !table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
    const budget = buildBudget(table);
    const dev = fitBands(fitDocs, table, budget, o.keyLevels, null);
    const clientFit = fitBands(fitDocs, table, budget, o.keyLevels, (r) => r.statsSource === 'client' || r.statsSource === 'client-scaled');

    const f = (x) => (x === null || x === undefined ? '-' : x.toFixed(3));
    const result = { measured: [], stored: [] };
    say(`fitted bands: ${Object.entries(dev).map(([k, b]) => `${k} (baseValue ${f(b.baseValue)}, ${b.fitted} rows)`).join('; ')}`);
    say(`client-read refit: ${Object.entries(clientFit).map(([k, b]) => `${k} (baseValue ${f(b.baseValue)}, ${b.fitted} rows)`).join('; ')}`);
    for (const doc of docs.sort((a, b) => String(a.exportedAt).localeCompare(String(b.exportedAt)))) {
        const key = doc.contentType === 'Raid' ? Object.keys(dev).find((k) => k.startsWith('raid-')) : String(doc.keyLevel);
        const band = dev[key];
        if (!band) continue;
        const m = measure(doc, band, table, budget);
        const c = measure(doc, clientFit[key], table, budget);
        const byClass = classTable(m.rows);
        const byClassClient = classTable(c.rows);
        result.measured.push({ contentType: doc.contentType, keyLevel: doc.keyLevel, exportedAt: doc.exportedAt, band: key, vWorn: m.vWorn, byClass, byClassClient });
        say('');
        say(`== ${doc.contentType} ${doc.contentType === 'Raid' ? '' : `+${doc.keyLevel} `}(exported ${doc.exportedAt}), band ${key}: V(worn) ${f(m.vWorn)}, worn stats ${JSON.stringify(m.wornSources)}`);
        say('  class      n   cens  game    pin100  floored uncens  | client-fit game  floored');
        for (const cls of CLASSES) {
            const a = byClass[cls];
            const b = byClassClient[cls];
            say(`  ${cls.padEnd(9)} ${String(a.n).padStart(3)} ${String(a.censored).padStart(4)}   ${f(a.game).padEnd(7)} ${f(a.pin100).padEnd(7)} ${f(a.floored).padEnd(7)} ${f(a.uncensored).padEnd(7)} | ${f(b.game).padEnd(16)} ${f(b.floored)}`);
        }
    }
    if (o.compare) {
        result.stored = storedRows(o.compare, o.week, o.char);
        say('');
        say(`== the rows a compare stored (${o.week}, ${o.char}): k raw -> floored ==`);
        for (const s of result.stored) {
            say(`  ${s.contentType} ${s.document} (band ${s.band}, weights ${s.derivedAt}): ${CLASSES.map((c) => `${c} n ${s.byClass[c].n} cens ${s.byClass[c].censored} k ${f(s.byClass[c].raw)} -> ${f(s.byClass[c].floored)}`).join('; ')}`);
        }
    }
    return result;
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(`percent-scale: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, scale, UF_FLOOR, wornFromCapture, documentsFromCapture };
