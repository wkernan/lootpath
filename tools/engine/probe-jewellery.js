#!/usr/bin/env node
// The jewellery probe (E-0l, WKE-683). DEV ONLY - nothing here ships.
//
//   node probe-jewellery.js --stats <capture.lua> [--stats ...]
//        --key-levels 1=2,2=4,4=6,6=8,7=10
//        --compare <SavedVariables.lua> --week 2026-09-29 --char "Hotornot - Arthas"
//        [--inventory 4]
//        <fit export.json|dir> ...
//
// Asks why the compare's jewellery class (Finger, Neck) misses where armour
// hits, on the rows a real compare STORED (`db.global.engineCompare[week]
// [char]`: every scored row's `link`, `level`, `key`, `slot`, `class`,
// `theirs`, `ours` floored and `raw`). It refits the bands exactly as
// fit-weights.js does (the same eight exports, the same transcripts: the dev
// weights the game ran), takes the worn set from the `--compare` file's own
// inventory snapshot `--inventory`, and:
//
//   reproduce  re-scores every stored row whose candidate link a transcript
//              read, against the stored `raw`; recomputes every stored
//              block's metrics from its stored rows (EngineCompare.Metrics,
//              ported below) against the stored `metrics`
//   recover    the client's stat vector of every jewellery row stored in two
//              or more documents: each document scores the same link with
//              another band's weights, so the stored raws pin the vector -
//              for each pair of secondaries, least squares on the two
//              amounts; the pair whose residual vanishes is the read, and a
//              row the transcripts read checks the method
//   suspects   each, re-measured on the stored rows, jewellery per band
//              (n, rho, top-1, sign, MAE, k, MAE@k):
//     1 sockets   the compare's parity mode adds sockets x the band's
//                 `gemVector`; the fitted bands carry `assumedFinish = {}`,
//                 so the gem term is zeroed and the rows re-scored
//     2 the pair  a drop whose itemID a worn ring (or trinket) carries takes
//                 only that copy's place (QE Live drops a set whose pair
//                 shares an ID); each such row re-scored, the rest kept
//     3 the mix   on the rows whose stats are read or recovered: the band's
//                 four secondary weights set to their mean; and the bands
//                 refitted with the recovered vectors added as client points
//     4 the level every jewellery row's read level against its key's, and
//                 any row at a level no track step draws (44, 344)
//
// SIGN: theirs is the stored `theirs` (`upgradePercent`, positive = better),
// read as-is; ours is floored at EngineCompare.UF_FLOOR (0) before every
// metric, as the compare does since E-0j.
'use strict';

const fs = require('fs');
const path = require('path');
const { parseSavedVariables, luaArray } = require('../companion/lib/lua-savedvariables');
const { loadTable, buildBudget, itemStats, statsForLink, readJsonInto, SECONDARIES } = require('./lib/stats');
const { fitDocument, DEFAULT_EFFECT_IDS } = require('./lib/fit');
const { DEFAULT_DR, ratingToPercent } = require('./lib/dr');
const { STATS, features, totals, candidates, zeroStats } = require('./lib/score');
const { bandKey } = require('./fit-weights');
const { wornFromCapture } = require('./percent-scale');

// EngineCompare's fixed numbers (Lootpath/Modules/EngineCompare.lua).
const UF_FLOOR = 0;
const DEAD_ZONE = 0.1;
const TOP1_WITHIN = 0.1;
const MIN_RHO_N = 5;
const JEWELLERY = 'jewellery';
const PAIRED_SLOTS = new Set(['Finger', 'Trinket']);
// Levels no track step draws (E-0g step 2): the compare leaves such rows out.
const NO_STEP_LEVELS = new Set([44, 344]);
// A recovered vector is accepted when the stored raws are met to this rms.
const RECOVER_RMS = 1e-5;

function parseArgs(argv) {
    const o = { stats: [], exports: [], keyLevels: {}, inventory: 4, compare: null, week: null, char: null };
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
        } else if (a === '--compare') o.compare = next();
        else if (a === '--week') o.week = next();
        else if (a === '--char') o.char = next();
        else if (a === '--inventory') o.inventory = Number(next());
        else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
        else o.exports.push(a);
    }
    return o;
}

function list(t) {
    if (!t) return [];
    return Array.isArray(t) ? t : luaArray(t);
}

// --- EngineCompare.Metrics, ported line for line ---------------------------

function ranks(values) {
    const idx = values.map((_, i) => i).sort((a, b) => (values[a] === values[b] ? a - b : values[a] - values[b]));
    const out = [];
    let i = 0;
    while (i < idx.length) {
        let j = i;
        while (j < idx.length - 1 && values[idx[j + 1]] === values[idx[i]]) j += 1;
        const avg = (i + j) / 2 + 1;
        for (let k = i; k <= j; k++) out[idx[k]] = avg;
        i = j + 1;
    }
    return out;
}

function spearman(xs, ys) {
    const n = xs.length;
    if (n !== ys.length || n < MIN_RHO_N) return null;
    const rx = ranks(xs);
    const ry = ranks(ys);
    const mean = (n + 1) / 2;
    let sxy = 0;
    let sxx = 0;
    let syy = 0;
    for (let i = 0; i < n; i++) {
        const dx = rx[i] - mean;
        const dy = ry[i] - mean;
        sxy += dx * dy;
        sxx += dx * dx;
        syy += dy * dy;
    }
    if (sxx === 0 || syy === 0) return null;
    return sxy / Math.sqrt(sxx * syy);
}

function scaleK(ours, theirs) {
    let sot = 0;
    let soo = 0;
    for (let i = 0; i < ours.length; i++) {
        sot += ours[i] * theirs[i];
        soo += ours[i] * ours[i];
    }
    return soo === 0 ? null : sot / soo;
}

function mae(ours, theirs, k) {
    if (!ours.length) return null;
    const kk = k === undefined ? 1 : k;
    let s = 0;
    for (let i = 0; i < ours.length; i++) s += Math.abs(kk * ours[i] - theirs[i]);
    return s / ours.length;
}

const signOf = (x) => (x > 0 ? 1 : x < 0 ? -1 : 0);

function sign(ours, theirs) {
    let agree = 0;
    let counted = 0;
    for (let i = 0; i < ours.length; i++) {
        if (Math.abs(theirs[i]) >= DEAD_ZONE) {
            counted += 1;
            if (signOf(ours[i]) === signOf(theirs[i])) agree += 1;
        }
    }
    return counted ? agree / counted : null;
}

function topPick(rows) {
    if (rows.length < 2) return null;
    let mine = null;
    let best = null;
    for (const r of rows) {
        if (!mine || r.ours > mine.ours) mine = r;
        if (best === null || r.theirs > best) best = r.theirs;
    }
    const above = rows.filter((r) => r.theirs > mine.theirs).length;
    return { first: mine.theirs >= best - TOP1_WITHIN, inThree: above < 3 };
}

// Rows `{ key, slot, ours, theirs }` (ours already floored), in key order.
function metrics(rowsIn) {
    const rows = rowsIn.slice().sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    const ours = rows.map((r) => r.ours);
    const theirs = rows.map((r) => r.theirs);
    const bySlot = {};
    for (const r of rows) (bySlot[r.slot || '?'] = bySlot[r.slot || '?'] || []).push(r);
    let groups = 0;
    let top1 = 0;
    let top3 = 0;
    for (const slot of Object.keys(bySlot).sort()) {
        const t = topPick(bySlot[slot]);
        if (t) {
            groups += 1;
            top1 += t.first ? 1 : 0;
            top3 += t.inThree ? 1 : 0;
        }
    }
    const k = scaleK(ours, theirs);
    return {
        n: rows.length,
        rho: spearman(ours, theirs),
        top1: groups ? top1 / groups : null,
        top3: groups ? top3 / groups : null,
        sign: sign(ours, theirs),
        mae: mae(ours, theirs),
        k,
        maeK: k === null ? null : mae(ours, theirs, k),
    };
}

// --- the model -------------------------------------------------------------

const floor = (x) => Math.max(UF_FLOOR, x);

function value(items, band) {
    const x = features(totals(items, band.finish || null), DEFAULT_DR);
    let v = band.baseValue;
    for (const s of STATS) v += band.weights[s] * x[s];
    return v;
}

// EngineScore.UpgradePercent over score.js's placements (the pair rule
// included unless `ignorePairRule`): 100 x (V(best) - V(worn)) / V(worn).
function percent(worn, item, band, ignorePairRule) {
    const vWorn = value(worn, band);
    const probe = ignorePairRule ? { ...item, id: null } : item;
    let best = null;
    let replaced = null;
    for (const c of candidates(worn, probe)) {
        const v = value(c.items, band);
        if (best === null || v > best) {
            best = v;
            replaced = c.replaced;
        }
    }
    if (best === null) return null;
    return { percent: (100 * (best - vWorn)) / vWorn, replaced };
}

function fitBands(fitDocs, table, budget, keyLevels) {
    const bands = {};
    const opts = { effectIds: DEFAULT_EFFECT_IDS, assumedFinish: {}, dr: DEFAULT_DR, resamples: 0 };
    for (const d of fitDocs.slice().sort((a, b) => String(a.exportedAt).localeCompare(String(b.exportedAt)))) {
        const fit = fitDocument(d, table, budget, opts);
        // assumedFinish is what fit-weights.js writes into every band: {}.
        bands[bandKey(d, keyLevels)] = { baseValue: fit.baseValue, weights: { ...fit.weights }, assumedFinish: {}, document: d.reportId };
    }
    return bands;
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

// --- the stored rows -------------------------------------------------------

function storedBlocks(sv, week, char) {
    const entry = sv.LootpathDB.global.engineCompare[week][char];
    const blocks = [];
    for (const ct of Object.keys(entry).sort()) {
        for (const doc of Object.keys(entry[ct]).sort((a, b) => Number(a) - Number(b))) {
            if (doc === 'pass1') continue;
            const e = entry[ct][doc];
            const rows = list(e.rows).map((r) => ({ key: r.key, id: Number(String(r.key).split('@')[0]), keyLevel: Number(String(r.key).split('@')[1]), level: r.level, slot: r.slot, cls: r.class, link: r.link, theirs: r.theirs, ours: r.ours, raw: r.raw }));
            blocks.push({ contentType: ct, document: doc, band: e.band, derivedAt: e.derivedAt, metrics: e.metrics, rows });
        }
    }
    return blocks;
}

// --- recovery --------------------------------------------------------------

function pairStats(pair, x) {
    const s = zeroStats();
    s[pair[0]] = x[0];
    s[pair[1]] = x[1];
    return s;
}

// Least squares on the two amounts of one secondary pair: Gauss-Newton from a
// fixed grid of starts, the best non-negative answer kept.
function solvePair(obs, pair, worn, bands) {
    const model = (x, o) => percent(worn, { id: null, slot: o.slot, stats: pairStats(pair, x) }, bands[o.band], true).percent;
    let best = null;
    for (const a0 of [50, 150, 250, 350]) {
        for (const b0 of [20, 100, 200, 300]) {
            let x = [a0, b0];
            for (let it = 0; it < 60; it++) {
                const r = obs.map((o) => model(x, o) - o.raw);
                const J = obs.map((o) => [0, 1].map((k) => {
                    const xp = x.slice();
                    xp[k] += 1e-3;
                    return (model(xp, o) - model(x, o)) / 1e-3;
                }));
                let a = 0;
                let b = 0;
                let c = 0;
                let g0 = 0;
                let g1 = 0;
                for (let i = 0; i < obs.length; i++) {
                    a += J[i][0] * J[i][0];
                    b += J[i][0] * J[i][1];
                    c += J[i][1] * J[i][1];
                    g0 += J[i][0] * r[i];
                    g1 += J[i][1] * r[i];
                }
                const det = a * c - b * b;
                if (Math.abs(det) < 1e-18) break;
                const d0 = (c * g0 - b * g1) / det;
                const d1 = (a * g1 - b * g0) / det;
                x = [x[0] - d0, x[1] - d1];
                if (Math.abs(d0) + Math.abs(d1) < 1e-9) break;
            }
            const rms = Math.sqrt(obs.reduce((s, o) => s + (model(x, o) - o.raw) ** 2, 0) / obs.length);
            if (x[0] >= -1e-6 && x[1] >= -1e-6 && (!best || rms < best.rms)) best = { x, rms };
        }
    }
    return best;
}

function recover(blocks, worn, bands, table) {
    const byKey = new Map();
    for (const b of blocks) {
        for (const r of b.rows) {
            if (r.cls !== JEWELLERY) continue;
            if (!byKey.has(r.key)) byKey.set(r.key, []);
            byKey.get(r.key).push({ band: b.band, raw: r.raw, slot: r.slot, link: r.link, id: r.id, level: r.level });
        }
    }
    const out = [];
    for (const [key, obs] of [...byKey.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
        if (obs.length < 2) {
            out.push({ key, documents: obs.length, identified: false });
            continue;
        }
        const fits = [];
        for (let i = 0; i < SECONDARIES.length; i++) {
            for (let j = i + 1; j < SECONDARIES.length; j++) {
                const pair = [SECONDARIES[i], SECONDARIES[j]];
                const f = solvePair(obs, pair, worn, bands);
                if (f) fits.push({ pair, x: f.x, rms: f.rms });
            }
        }
        fits.sort((a, b) => a.rms - b.rms);
        const top = fits[0];
        const rounded = top.x.map((v) => Math.round(v));
        const model = (o) => percent(worn, { id: null, slot: o.slot, stats: pairStats(top.pair, rounded) }, bands[o.band], true).percent;
        const roundedRms = Math.sqrt(obs.reduce((s, o) => s + (model(o) - o.raw) ** 2, 0) / obs.length);
        const read = statsForLink(table, obs[0].link);
        out.push({
            key,
            id: obs[0].id,
            level: obs[0].level,
            slot: obs[0].slot,
            documents: obs.length,
            identified: roundedRms < RECOVER_RMS,
            pair: top.pair,
            stats: pairStats(top.pair, rounded),
            rms: top.rms,
            roundedRms,
            runnerUp: fits[1] ? { pair: fits[1].pair, rms: fits[1].rms } : null,
            read,
        });
    }
    return out;
}

// --- the probe -------------------------------------------------------------

function run(argv, log) {
    const say = log || console.log;
    const o = parseArgs(argv);
    if (!o.stats.length) throw new Error('--stats is required');
    if (!o.compare || !o.week || !o.char) throw new Error('--compare, --week and --char are required');
    const fitDocs = expandExports(o.exports).map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
    if (!fitDocs.length) throw new Error('no Upgrade Finder export to fit');
    const table = loadTable(o.stats, fs);
    for (const d of fitDocs) for (const r of [...d.equipped, ...d.items]) if (r.slot && !table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
    const budget = buildBudget(table);
    const bands = fitBands(fitDocs, table, budget, o.keyLevels);

    const sv = parseSavedVariables(fs.readFileSync(o.compare, 'utf8'));
    const worn = wornFromCapture(sv, o.inventory).map((e) => {
        const s = itemStats(table, budget, e);
        return { ...e, stats: s.stats || zeroStats(), statsSource: s.statsSource };
    });
    const blocks = storedBlocks(sv, o.week, o.char);
    const f3 = (x) => (x === null || x === undefined ? '-' : x.toFixed(3));
    const pc = (x) => (x === null || x === undefined ? '-' : `${Math.round(100 * x)}%`);
    const line = (label, m) => `  ${label.padEnd(26)} n ${String(m.n).padStart(2)}  rho ${f3(m.rho).padStart(6)}  top1 ${pc(m.top1).padStart(4)}  sign ${pc(m.sign).padStart(4)}  MAE ${f3(m.mae)}  k ${f3(m.k)}  MAE@k ${f3(m.maeK)}`;
    const result = { bands, worn, blocks: [], recovered: [], suspects: {} };

    // Reproduce.
    say(`worn set (${o.compare}, inventory ${o.inventory}): ${worn.map((w) => `${w.id}@${w.level} ${w.slot} ${w.statsSource}`).join('; ')}`);
    let linkRows = 0;
    let maxDiff = 0;
    let maxMetricDiff = 0;
    for (const b of blocks) {
        const band = bands[b.band];
        if (!band) throw new Error(`no fitted band ${b.band}`);
        for (const r of b.rows) {
            const read = statsForLink(table, r.link);
            if (!read) continue;
            const p = percent(worn, { id: r.id, slot: r.slot, stats: read }, band, true);
            linkRows += 1;
            maxDiff = Math.max(maxDiff, Math.abs(p.percent - r.raw));
        }
        for (const cls of Object.keys(b.metrics || {})) {
            const m = metrics(b.rows.filter((r) => r.cls === cls));
            for (const f of ['rho', 'top1', 'top3', 'sign', 'mae', 'k', 'maeK']) {
                const stored = b.metrics[cls][f];
                if (typeof stored === 'number' && typeof m[f] === 'number') maxMetricDiff = Math.max(maxMetricDiff, Math.abs(stored - m[f]));
                else if ((stored === undefined || stored === null) !== (m[f] === null)) maxMetricDiff = Infinity;
            }
        }
    }
    result.reproduce = { linkRows, maxDiff, maxMetricDiff };
    // Where the worn totals sit in DR: the share of one more rating point
    // that still counts (the client's brackets, lib/dr.js).
    const wornTotals = totals(worn, null);
    result.dr = {};
    for (const k of SECONDARIES) {
        const t = DEFAULT_DR[k];
        result.dr[k] = { total: wornTotals[k], marginal: (ratingToPercent(wornTotals[k] + 1, t) - ratingToPercent(wornTotals[k], t)) * t.ratingPerPercent };
    }
    say(`reproduce: ${linkRows} stored rows whose link a transcript read, harness - stored raw at most ${maxDiff.toExponential(2)}; every stored block's metrics recomputed from its rows, largest difference ${maxMetricDiff.toExponential(2)}`);

    say(`worn totals and the share of the next point that counts: ${SECONDARIES.map((k) => `${k} ${result.dr[k].total} (${result.dr[k].marginal.toFixed(2)})`).join(', ')}`);

    // Recover.
    const recovered = recover(blocks, worn, bands, table);
    result.recovered = recovered;
    say('');
    say('recover: the client\'s stat vector of each jewellery row from its stored raws (rows in two or more documents)');
    for (const r of recovered) {
        if (r.documents < 2) continue;
        const s = r.pair.map((k) => `${k} ${r.stats[k]}`).join(' / ');
        const check = r.read ? `; transcript read: ${SECONDARIES.filter((k) => r.read[k]).map((k) => `${k} ${r.read[k]}`).join(' / ')}` : '';
        say(`  ${r.key.padEnd(11)} ${r.slot.padEnd(6)} ${r.documents} documents: ${s}, rms ${r.roundedRms.toExponential(2)} (next pair ${r.runnerUp.pair.join('/')} ${r.runnerUp.rms.toExponential(2)})${r.identified ? '' : ' NOT IDENTIFIED'}${check}`);
    }
    const singles = recovered.filter((r) => r.documents < 2).map((r) => r.key);
    say(`  in one document only, not identifiable from its raw alone: ${singles.length} (${singles.join(', ')})`);
    const known = new Map();
    for (const r of recovered) if (r.identified) known.set(r.key, r.stats);
    const statsOf = (r) => statsForLink(table, r.link) || known.get(r.key) || null;

    // Suspects, per band.
    for (const b of blocks) {
        const band = bands[b.band];
        const jew = b.rows.filter((r) => r.cls === JEWELLERY);
        const S = {};
        S.stored = metrics(jew.map((r) => ({ key: r.key, slot: r.slot, ours: r.ours, theirs: r.theirs })));

        // 1: the gem term zeroed. The fitted band's assumedFinish carries no
        // gemVector, so zeroing it re-scores every row to the same percent.
        const gemVector = band.assumedFinish && band.assumedFinish.gemVector;
        const zeroed = { ...band, assumedFinish: {}, finish: null };
        let gemMoved = 0;
        for (const r of jew) {
            const st = statsOf(r);
            if (!st) continue;
            const a = percent(worn, { id: r.id, slot: r.slot, stats: st }, band, true).percent;
            const z = percent(worn, { id: r.id, slot: r.slot, stats: st }, zeroed, true).percent;
            gemMoved = Math.max(gemMoved, Math.abs(a - z));
        }
        S.sockets = { gemVector: gemVector || null, maxMove: gemMoved, metrics: S.stored };

        // 2: the pair rule.
        const twins = [];
        const pairRows = jew.map((r) => {
            const wornTwin = PAIRED_SLOTS.has(r.slot) && worn.some((w) => w.slot === r.slot && w.id === r.id);
            if (!wornTwin) return { key: r.key, slot: r.slot, ours: r.ours, theirs: r.theirs };
            const s = statsOf(r) || itemStats(table, budget, { id: r.id, level: r.level, slot: r.slot }).stats;
            const src = statsForLink(table, r.link) ? 'client' : known.has(r.key) ? 'recovered' : itemStats(table, budget, { id: r.id, level: r.level, slot: r.slot }).statsSource;
            const before = percent(worn, { id: r.id, slot: r.slot, stats: s }, band, true);
            const after = percent(worn, { id: r.id, slot: r.slot, stats: s }, band, false);
            twins.push({ key: r.key, statsSource: src, storedRaw: r.raw, harnessBefore: before.percent, replacedBefore: before.replaced.map((i) => `${worn[i].id}@${worn[i].level}`), after: after.percent, replacedAfter: after.replaced.map((i) => `${worn[i].id}@${worn[i].level}`), theirs: r.theirs });
            return { key: r.key, slot: r.slot, ours: floor(after.percent), theirs: r.theirs };
        });
        S.pair = { twins, metrics: metrics(pairRows) };

        // 3: the mix, on the rows whose stats are read or recovered.
        const sub = jew.filter((r) => statsOf(r));
        const subRows = (bandUse) => sub.map((r) => ({ key: r.key, slot: r.slot, ours: floor(percent(worn, { id: r.id, slot: r.slot, stats: statsOf(r) }, bandUse, false).percent), theirs: r.theirs }));
        const mean = SECONDARIES.reduce((s, k) => s + band.weights[k], 0) / SECONDARIES.length;
        const equal = { ...band, weights: { ...band.weights } };
        for (const k of SECONDARIES) equal.weights[k] = mean;
        S.mix = {
            rows: sub.map((r) => r.key),
            stored: metrics(sub.map((r) => ({ key: r.key, slot: r.slot, ours: r.ours, theirs: r.theirs }))),
            harness: metrics(subRows(band)),
            equalSecondaries: metrics(subRows(equal)),
        };

        // 4: the level.
        const offLevel = jew.filter((r) => r.level !== r.keyLevel).map((r) => r.key);
        const noStep = jew.filter((r) => NO_STEP_LEVELS.has(r.level) || NO_STEP_LEVELS.has(r.keyLevel)).map((r) => r.key);
        S.level = { offLevel, noStep };

        result.suspects[`${b.contentType} ${b.document}`] = S;
        result.blocks.push({ contentType: b.contentType, document: b.document, band: b.band });
    }

    // 3, refitted: the recovered vectors as client points in the fit.
    const refitTable = loadTable(o.stats, fs);
    for (const d of fitDocs) for (const r of [...d.equipped, ...d.items]) if (r.slot && !refitTable.slotOf.has(r.id)) refitTable.slotOf.set(r.id, r.slot);
    readJsonInto(refitTable, { items: recovered.filter((r) => r.identified && !r.read).map((r) => ({ id: r.id, level: r.level, slot: r.slot, stats: r.stats })) }, 'recovered from the stored raws');
    const refit = fitBands(fitDocs, refitTable, buildBudget(refitTable), o.keyLevels);
    result.refit = refit;
    for (const b of blocks) {
        const S = result.suspects[`${b.contentType} ${b.document}`];
        const sub = b.rows.filter((r) => r.cls === JEWELLERY && statsOf(r));
        S.mix.refit = metrics(sub.map((r) => ({ key: r.key, slot: r.slot, ours: floor(percent(worn, { id: r.id, slot: r.slot, stats: statsOf(r) }, refit[b.band], false).percent), theirs: r.theirs })));
    }

    say('');
    say(`fitted bands (secondary weights per percent): ${Object.entries(bands).map(([k, b]) => `${k} haste ${f3(b.weights.haste)} crit ${f3(b.weights.crit)} mastery ${f3(b.weights.mastery)} vers ${f3(b.weights.vers)}`).join('; ')}`);
    say(`refitted with the recovered vectors:        ${Object.entries(refit).map(([k, b]) => `${k} haste ${f3(b.weights.haste)} crit ${f3(b.weights.crit)} mastery ${f3(b.weights.mastery)} vers ${f3(b.weights.vers)}`).join('; ')}`);
    for (const b of blocks) {
        const S = result.suspects[`${b.contentType} ${b.document}`];
        say('');
        say(`== ${b.contentType} [${b.document}], band ${b.band}: jewellery`);
        say(line('stored (the screen)', S.stored));
        say(line('1 sockets: gem term zeroed', S.sockets.metrics) + `  (gemVector ${S.sockets.gemVector ? 'set' : 'none'}; largest move ${S.sockets.maxMove.toExponential(1)})`);
        say(line('2 the pair rule', S.pair.metrics));
        for (const t of S.pair.twins) say(`      ${t.key} (${t.statsSource} stats): stored raw ${t.storedRaw.toFixed(4)}, harness ${t.harnessBefore.toFixed(4)} over ${t.replacedBefore.join(',')}; with the rule ${t.after.toFixed(4)} over ${t.replacedAfter.join(',')}; theirs ${t.theirs}`);
        say(`    3 the mix, on the ${S.mix.rows.length} rows read or recovered (${S.mix.rows.join(', ')}):`);
        say(line('  stored', S.mix.stored));
        say(line('  harness, the pair rule', S.mix.harness));
        say(line('  equal secondary weights', S.mix.equalSecondaries));
        say(line('  refit with recovered', S.mix.refit));
        say(`  4 the level: ${S.level.offLevel.length} rows read at another level than their key's${S.level.offLevel.length ? ` (${S.level.offLevel.join(', ')})` : ''}; ${S.level.noStep.length} at a level no step draws`);
    }
    return result;
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(`probe-jewellery: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, metrics, spearman, ranks, recover, percent, value, fitBands, expandExports, storedBlocks, parseArgs, UF_FLOOR, NO_STEP_LEVELS };
