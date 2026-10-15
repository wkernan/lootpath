'use strict';

// E-0n carry-forward check (WKE-706, 2026-10-14): do weights fitted to one
// set of QE Live documents describe another? Every document of both sets is
// fitted over ONE item-stats table (the owner's 12.1.5 capture), so item stats
// cannot differ between them; then each band's weights score the other set's
// rows. Developer-only diagnostic; reads committed fixtures, writes nothing.
//   node cross-score.js
const fs = require('fs');
const path = require('path');
const { loadTable, buildBudget } = require('./lib/stats');
const { fitDocument, prepare, metrics } = require('./lib/fit');
const { DEFAULT_DR } = require('./lib/dr');
const { bandKey } = require('./fit-weights');
const R = path.join(__dirname, '..', '..', 'spec', 'fixtures');
const KL = { 1: 2, 2: 4, 4: 6, 6: 8, 7: 10 };
const read = (dir) => fs.readdirSync(dir).filter((f) => /^qe-upgradefinder-.*\.json$/.test(f)).map((f) => ({ f, doc: JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')) }));
const oldDocs = read(R + '/qe');
const newDocs = read(R + '/qe/e0n');
const table = loadTable([R + '/captures/Lootpath-20261013-183853.lua'], fs, []);
for (const { doc } of [...oldDocs, ...newDocs]) for (const r of [...doc.equipped, ...doc.items]) if (!table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
const budget = buildBudget(table);
const opts = { dr: DEFAULT_DR, resamples: 0, balance: 'none' };
const fit = (d) => { const x = fitDocument(d.doc, table, budget, opts); d.fit = x; d.w = Object.values(x.weights); d.band = bandKey(d.doc, KL); d.at = d.doc.exportedAt; };
[...oldDocs, ...newDocs].forEach(fit);
const dot = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);
function score(target, w) {
    const prep = prepare(target.doc, table, budget, opts);
    const rows = prep.rows.filter((r) => !r.excluded);
    const pred = rows.map((r) => Math.max(...r.diffs.map((c) => dot(c.d, w))));
    const out = { overall: metrics(rows.map((r) => r.observed), pred) };
    const by = {};
    rows.forEach((r, i) => { (by[r.slotClass] = by[r.slotClass] || { o: [], p: [] }); by[r.slotClass].o.push(r.observed); by[r.slotClass].p.push(pred[i]); });
    for (const [c, v] of Object.entries(by)) out[c] = metrics(v.o, v.p);
    return out;
}
const f = (x) => (x === null || x === undefined ? '  -   ' : x.toFixed(3).padStart(6));
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
