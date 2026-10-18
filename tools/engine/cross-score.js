'use strict';

// E-0n carry-forward check (WKE-706, 2026-10-14): do weights fitted to one
// set of QE Live documents describe another? Every document of both sets is
// fitted over ONE item-stats table (the owner's 12.1.5 capture), so item stats
// cannot differ between them; then each band's weights score the other set's
// rows. Developer-only diagnostic; reads committed fixtures, writes nothing.
//   node cross-score.js
//
// E-5 (WKE-711, 2026-10-18): with --weights, score one or more version 2
// weights FILES (the combat-log tool's, the fitted dev file the game runs)
// against the committed Upgrade Finder documents over the same one table, side
// by side, never combined: per document, each file's band (EngineScore.BandFor's
// rule) predicts every row's percent, and rho / k / MAE are printed per class.
//   node cross-score.js --weights <file.lua> [--weights <file.lua> ...] [--docs <dir>]
const fs = require('fs');
const path = require('path');
const { loadTable, buildBudget } = require('./lib/stats');
const { fitDocument, prepare, metrics } = require('./lib/fit');
const { STATS } = require('./lib/score');
const { DEFAULT_DR } = require('./lib/dr');
const { readLuaTable } = require('./lib/luatable');
const { bandKey } = require('./fit-weights');
const R = path.join(__dirname, '..', '..', 'spec', 'fixtures');
const KL = { 1: 2, 2: 4, 4: 6, 6: 8, 7: 10 };
const TABLE_CAPTURE = R + '/captures/Lootpath-20261013-183853.lua';
const read = (dir) =>
    fs
        .readdirSync(dir)
        .filter((f) => /^qe-upgradefinder-.*\.json$/.test(f))
        .sort()
        .map((f) => ({ f, doc: JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')) }));
const dot = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);
const f = (x) => (x === null || x === undefined ? '  -   ' : x.toFixed(3).padStart(6));
const CLASSES = ['overall', 'tier-slot', 'armour', 'jewellery', 'weapon'];

function oneTable(docs) {
    const table = loadTable([TABLE_CAPTURE], fs, []);
    for (const { doc } of docs) for (const r of [...doc.equipped, ...doc.items]) if (!table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
    return { table, budget: buildBudget(table) };
}

function carryForward() {
    const oldDocs = read(R + '/qe');
    const newDocs = read(R + '/qe/e0n');
    const { table, budget } = oneTable([...oldDocs, ...newDocs]);
    const opts = { dr: DEFAULT_DR, resamples: 0, balance: 'none' };
    const fit = (d) => {
        const x = fitDocument(d.doc, table, budget, opts);
        d.fit = x;
        d.w = Object.values(x.weights);
        d.band = bandKey(d.doc, KL);
        d.at = d.doc.exportedAt;
    };
    [...oldDocs, ...newDocs].forEach(fit);
    function score(target, w) {
        const prep = prepare(target.doc, table, budget, opts);
        const rows = prep.rows.filter((r) => !r.excluded);
        const pred = rows.map((r) => Math.max(...r.diffs.map((c) => dot(c.d, w))));
        const out = { overall: metrics(rows.map((r) => r.observed), pred) };
        const by = {};
        rows.forEach((r, i) => {
            by[r.slotClass] = by[r.slotClass] || { o: [], p: [] };
            by[r.slotClass].o.push(r.observed);
            by[r.slotClass].p.push(pred[i]);
        });
        for (const [c, v] of Object.entries(by)) out[c] = metrics(v.o, v.p);
        return out;
    }
    const line = (label, m) => console.log(label.padEnd(34) + ['overall', 'tier', 'armour', 'jewellery', 'weapon'].map((c) => (m[c] ? `${c} rho ${f(m[c].spearman)} k ${f(m[c].k)} mae ${f(m[c].mae)}` : `${c} -`)).join(' | '));
    // For each band, the old document the game file kept (the later export of a band).
    const oldBy = {};
    for (const d of oldDocs) if (!oldBy[d.band] || d.at > oldBy[d.band].at) oldBy[d.band] = d;
    console.log('patch of the one table:', table.patch, '; old docs', oldDocs.length, 'new docs', newDocs.length);
    for (const n of newDocs.sort((a, b) => String(a.band).localeCompare(String(b.band)))) {
        const o = oldBy[n.band];
        console.log(`\n== band ${n.band}: new ${n.doc.reportId} (${n.at}) vs old ${o ? o.doc.reportId + ' (' + o.at + ')' : 'NONE'}`);
        if (!o) continue;
        line('old w on OLD doc (its own fit)', score(o, o.w));
        line('old w on NEW doc', score(n, o.w));
        line('new w on NEW doc (its own fit)', score(n, n.w));
        line('new w on OLD doc', score(o, n.w));
        const keys = Object.keys(n.fit.weights);
        console.log('weights old: ' + keys.map((k, i) => `${k} ${o.w[i].toFixed(4)}`).join(', '));
        console.log('weights new: ' + keys.map((k, i) => `${k} ${n.w[i].toFixed(4)}`).join(', '));
    }
}

// --- --weights (E-5) ----------------------------------------------------------

// EngineScore.BandFor's rule (Lootpath/Modules/EngineScore.lua): a Dungeon key
// level takes its exact band, else the highest "N+" band at or below it; a Raid
// document its raid band; failing both, a content type with ONE band takes it.
// Raid documents fall back to the file's Dungeon band only when the file has no
// Raid at all (the combat-log file's first log is a key); the label says so.
function bandFor(entry, doc) {
    const ct = doc.contentType;
    const pickOnly = (bands) => {
        const keys = Object.keys(bands || {});
        return keys.length === 1 ? keys[0] : null;
    };
    const content = entry[ct];
    if (content && content.bands) {
        const bands = content.bands;
        if (ct === 'Raid') {
            const k = bandKey(doc, KL);
            if (bands[k]) return { key: k, band: bands[k], label: k };
        } else {
            const level = KL[String(doc.settings.dungeon)];
            if (level !== undefined && bands[String(level)]) return { key: String(level), band: bands[String(level)], label: String(level) };
            let best = null;
            for (const k of Object.keys(bands)) {
                const m = /^(\d+)\+$/.exec(k);
                if (m && level !== undefined && Number(m[1]) <= level && (!best || Number(m[1]) > Number(/^(\d+)/.exec(best)[1]))) best = k;
            }
            if (best) return { key: best, band: bands[best], label: best };
        }
        const only = pickOnly(bands);
        if (only) return { key: only, band: bands[only], label: only };
        return null;
    }
    if (ct === 'Raid' && !entry.Raid && entry.Dungeon) {
        const only = pickOnly(entry.Dungeon.bands);
        if (only) return { key: only, band: entry.Dungeon.bands[only], label: `Dungeon ${only} (no Raid band)` };
    }
    return null;
}

function loadWeightsFile(file, specID) {
    const t = readLuaTable(fs.readFileSync(file, 'utf8'), /^ns\.engineWeights\s*=/m);
    if (!t || t.version !== 2) throw new Error(`${file}: not a version 2 weights file`);
    const entry = t.specs && (t.specs[specID] || t.specs[String(specID)]);
    if (!entry) throw new Error(`${file}: no spec ${specID}`);
    return { file, method: entry.method, entry, patch: t.patch };
}

// The predicted percent of each row with one band: 100 x (V(with) - V(worn)) /
// V(worn), V = base + w . x - the Upgrade Finder way, tier forced on (it
// cancels). A band whose base + w . x(worn) is 100 (the fit's normalisation)
// reduces to w . d.
function scoreBand(prep, band) {
    if (band.unit && band.unit !== 'per percent') throw new Error(`a band in unit ${band.unit}: cross-score reads per percent only`);
    const w = STATS.map((k) => band.weights[k] || 0);
    const vWorn = (band.baseValue || 0) + dot(w, prep.xWorn);
    const rows = prep.rows.filter((r) => !r.excluded);
    const pred = rows.map((r) => (100 * Math.max(...r.diffs.map((c) => dot(c.d, w)))) / vWorn);
    const out = { overall: metrics(rows.map((r) => r.observed), pred) };
    const by = {};
    rows.forEach((r, i) => {
        by[r.slotClass] = by[r.slotClass] || { o: [], p: [] };
        by[r.slotClass].o.push(r.observed);
        by[r.slotClass].p.push(pred[i]);
    });
    for (const [c, v] of Object.entries(by)) out[c] = metrics(v.o, v.p);
    return { metrics: out, vWorn, pred };
}

function scoreFiles(files, opts) {
    const o = opts || {};
    const say = o.log || console.log;
    const spec = o.spec || 105;
    const docs = read(o.docs || R + '/qe');
    const { table, budget } = oneTable(docs);
    const loaded = files.map((file) => loadWeightsFile(file, spec));
    const prepOpts = { dr: DEFAULT_DR, resamples: 0, balance: 'none' };
    const results = [];
    say(`one item-stats table: ${path.basename(TABLE_CAPTURE)} (patch ${table.patch}); documents ${docs.length} from ${path.relative(R, o.docs || R + '/qe')}`);
    loaded.forEach((l, i) => say(`file ${i + 1}: ${path.basename(l.file)} - method ${l.method}, patch ${l.patch}`));
    // Each file's band weights relative to its own Intellect weight (per percent
    // of a rating per point of Intellect): the two methods' numbers side by side.
    for (const [i, l] of loaded.entries()) {
        for (const ct of ['Dungeon', 'Raid']) {
            if (!l.entry[ct]) continue;
            for (const [k, b] of Object.entries(l.entry[ct].bands).sort(([a], [c]) => a.localeCompare(c, 'en', { numeric: true }))) {
                say(`file ${i + 1} ${ct} ${k}: per percent / Int ` + STATS.slice(1).map((s) => `${s} ${(b.weights[s] / b.weights.int).toFixed(2)}`).join(', '));
            }
        }
    }
    for (const { f: name, doc } of docs) {
        const prep = prepare(doc, table, budget, prepOpts);
        say(`\n== ${name.replace(/^qe-upgradefinder-Hotornot-|\.json$/g, '')}: ${doc.contentType} ${doc.contentType === 'Raid' ? (doc.settings.raid || []).join('+') : `+${KL[String(doc.settings.dungeon)]}`} (${doc.exportedAt})`);
        const row = { document: doc.reportId, contentType: doc.contentType, files: [] };
        loaded.forEach((l, i) => {
            const b = bandFor(l.entry, doc);
            if (!b) {
                say(`  file ${i + 1}: no band`);
                row.files.push(null);
                return;
            }
            const s = scoreBand(prep, b.band);
            say(`  file ${i + 1} band ${b.label.padEnd(24)} ` + CLASSES.map((c) => (s.metrics[c] ? `${c} n ${String(s.metrics[c].n).padStart(3)} rho ${f(s.metrics[c].spearman)} k ${f(s.metrics[c].k)} mae ${f(s.metrics[c].mae)}` : `${c} -`)).join(' | '));
            row.files.push({ band: b.label, ...s });
        });
        results.push(row);
    }
    return { loaded, results };
}

if (require.main === module) {
    const argv = process.argv.slice(2);
    const files = [];
    let docs;
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === '--weights') files.push(argv[++i]);
        else if (argv[i] === '--docs') docs = argv[++i];
        else {
            console.error(`unknown argument ${argv[i]}`);
            process.exit(1);
        }
    }
    if (files.length) scoreFiles(files, { docs });
    else carryForward();
}

module.exports = { bandFor, scoreBand, scoreFiles, loadWeightsFile };
