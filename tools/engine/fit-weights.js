#!/usr/bin/env node
// The structure run (E-0e, WKE-674). DEV ONLY - nothing here ships.
//
//   node fit-weights.js --stats <capture.lua|table.json> [--stats ...]
//        (a capture.lua is read for its `itemstats` and `upgrade` snapshots)
//        [--key-levels 1=2,2=4,4=6,6=8,7=10] [--tier-sets 2057]
//        [--tier2 0.03] [--tier4 0.055] [--finish '{"int":0}']
//        [--effect-ids 271875,271092,268265,273778]
//        [--compare <SavedVariables.lua>] [--balance none|class]
//        [--resamples 200] [--seed 1] [--out out] <export.json|dir> ...
//
// Fits E-0c's weights to each QE Live Upgrade Finder export, writes
// out/<document>-fit.json per document and out/EngineWeights.dev.lua, and
// prints the metrics. A directory argument means every
// `qe-upgradefinder-*.json` in it. See README.md.
//
// E-0m (WKE-705): `--compare` reads the stat vector `/lootpath engine compare`
// stores beside each Upgrade Finder row (every stored week in the file) as a
// client point at that `id@level`, so the row is fitted on its own split
// instead of the equal placeholder; a stored row with no vector changes
// nothing. `--balance class` gives every slot class the same total weight in
// the least squares (lib/fit.js rowWeights), so jewellery's rows count as much
// as armour's. Neither is on by default: without them the run is E-0e's.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { loadTable, buildBudget } = require('./lib/stats');
const { fitDocument, DEFAULT_EFFECT_IDS } = require('./lib/fit');
const { DEFAULT_DR } = require('./lib/dr');
const { buildTable, render } = require('./lib/luaout');

function parseArgs(argv) {
    const opts = { stats: [], compare: [], balance: 'none', exports: [], keyLevels: {}, tierSets: [2057], tier2: 0.03, tier4: 0.055, finish: {}, effectIds: DEFAULT_EFFECT_IDS, resamples: 200, seed: 1, out: path.join(__dirname, 'out') };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        const next = () => {
            if (i + 1 >= argv.length) throw new Error(`${a} needs a value`);
            i += 1;
            return argv[i];
        };
        if (a === '--stats') opts.stats.push(next());
        else if (a === '--compare') opts.compare.push(next());
        else if (a === '--balance') opts.balance = next();
        else if (a === '--key-levels') {
            for (const pair of next().split(',')) {
                const [k, v] = pair.split('=');
                opts.keyLevels[k] = v;
            }
        } else if (a === '--tier-sets') opts.tierSets = next().split(',').map(Number);
        else if (a === '--tier2') opts.tier2 = Number(next());
        else if (a === '--tier4') opts.tier4 = Number(next());
        else if (a === '--finish') opts.finish = JSON.parse(next());
        else if (a === '--effect-ids') opts.effectIds = next().split(',').map(Number);
        else if (a === '--resamples') opts.resamples = Number(next());
        else if (a === '--seed') opts.seed = Number(next());
        else if (a === '--out') opts.out = next();
        else if (a === '--derived-at') opts.derivedAt = next();
        else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
        else opts.exports.push(a);
    }
    return opts;
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

function bandKey(doc, keyLevels) {
    if (doc.contentType === 'Raid') return `raid-${(doc.settings.raid || []).join('+')}`;
    const idx = String(doc.settings.dungeon);
    return keyLevels[idx] !== undefined ? String(keyLevels[idx]) : `dungeon-index-${idx}`;
}

function fmt(x, d) {
    return x === null || x === undefined ? '-' : x.toFixed(d === undefined ? 3 : d);
}

function run(argv, log) {
    const say = log || console.log;
    const opts = parseArgs(argv);
    if (!opts.stats.length) throw new Error('--stats <capture.lua|table.json> is required: the exports carry no item stats');
    const files = expandExports(opts.exports);
    if (!files.length) throw new Error('no Upgrade Finder export given');

    const table = loadTable(opts.stats, fs, opts.compare);
    const docs = files.map((f) => {
        const raw = fs.readFileSync(f);
        const doc = JSON.parse(raw.toString('utf8'));
        if (doc.schema !== 'qe-live-upgradefinder' || doc.version !== 1) throw new Error(`${f}: not a qe-live-upgradefinder v1 document`);
        return { file: f, doc, sha256: crypto.createHash('sha256').update(raw).digest('hex') };
    });
    // Slots the transcript does not name come from the exports' own rows.
    for (const { doc } of docs) for (const r of [...doc.equipped, ...doc.items]) if (!table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
    const budget = buildBudget(table);
    const tiers = { setIDs: opts.tierSets, twoPiece: opts.tier2, fourPiece: opts.tier4, forceTier: true };

    fs.mkdirSync(opts.out, { recursive: true });
    const bySource = {};
    for (const p of table.points.values()) bySource[p.source] = (bySource[p.source] || 0) + 1;
    say(`item-stats table: ${table.points.size} client points ${JSON.stringify(bySource)} (${[...new Set(table.sources.map((s) => path.basename(s.file)))].join(', ')}), patch ${table.patch || 'unknown'}`);
    for (const src of table.sources.filter((x) => x.kind.startsWith('compare rows'))) {
        say(`compare rows (${path.basename(src.file)}): ${src.rows} stored Upgrade Finder rows, ${src.vectors} with a vector (weeks ${src.weeks.join(', ') || 'none'}); ${src.points} new client points, ${src.held} already read by a transcript`);
    }
    say(`balance: ${opts.balance}`);
    say(`level curve: Intellect ${fmt(budget.intSlope * 100, 3)}%/level over ${budget.intItems} items, secondaries ${fmt(budget.secSlope * 100, 3)}%/level over ${budget.secItems} items`);
    say(`budget groups: ${Object.entries(budget.groups).map(([g, v]) => `${g} (${v.slots.join('/')}, ${v.points})`).join('; ')}`);

    const fits = [];
    for (const { file, doc, sha256 } of docs) {
        const fit = fitDocument(doc, table, budget, { effectIds: opts.effectIds, assumedFinish: opts.finish, dr: DEFAULT_DR, resamples: opts.resamples, seed: opts.seed, balance: opts.balance });
        fit.file = path.basename(file);
        fit.sha256 = sha256;
        fit.band = bandKey(doc, opts.keyLevels);
        fit.budget = budget;
        fit.dr = DEFAULT_DR;
        fit.tiers = tiers;
        const stem = path.basename(file).replace(/\.json$/, '');
        fs.writeFileSync(path.join(opts.out, `${stem}-fit.json`), JSON.stringify(fit, null, 2) + '\n');
        fits.push({ fit, band: fit.band });

        say('');
        say(`== ${fit.file} (${doc.contentType}, band ${fit.band}) ==`);
        say(`rows ${fit.counts.rows}: fitted ${fit.counts.fitted}, effect ${fit.counts.effect}, censored ${fit.counts.censored}, duplicate ${fit.counts.duplicate}, pair ${fit.counts.pair}, no-stats ${fit.counts.noStats}`);
        say(`stats sources (fitted): ${JSON.stringify(fit.statsSources.fitted)}; worn: ${JSON.stringify(fit.statsSources.worn)}`);
        say(`client reads (all rows): ${JSON.stringify(fit.clientSources.all)}; fitted: ${JSON.stringify(fit.clientSources.fitted)}; worn: ${JSON.stringify(fit.clientSources.worn)}`);
        say(`rank ${fit.rank}/6, condition ${fmt(fit.condition, 1)}`);
        say(`baseValue ${fmt(fit.baseValue, 2)} [${fmt(fit.baseInterval[0], 2)}, ${fmt(fit.baseInterval[1], 2)}]`);
        for (const k of Object.keys(fit.weights)) say(`  w_${k.padEnd(8)} ${fmt(fit.weights[k], 5)} [${fmt(fit.intervals[k][0], 5)}, ${fmt(fit.intervals[k][1], 5)}]`);
        say(`overall: n ${fit.overall.n}, R2 ${fmt(fit.overall.r2)}, MAE ${fmt(fit.overall.mae)}, rho ${fmt(fit.overall.spearman)}`);
        for (const [c, m] of Object.entries(fit.byClass)) say(`  ${c.padEnd(10)} n ${String(m.n).padStart(3)}, R2 ${fmt(m.r2)}, MAE ${fmt(m.mae)}, rho ${fmt(m.spearman)}, k ${fmt(m.k)}, on the equal placeholder ${fit.placeholderByClass[c] || 0}`);
        say(`censored (observed 0): ${fit.censoredCheck.n}, predicted <= 0: ${fit.censoredCheck.predictedAtOrBelowZero}, predicted > 0.1: ${fit.censoredCheck.predictedAbove0_1}`);
        say('largest residuals (observed - predicted):');
        for (const r of fit.largestResiduals.slice(0, 5)) say(`  ${r.id}@${r.level} ${r.slot} ${r.dropLoc}: observed ${fmt(r.observed)}, predicted ${fmt(r.predicted)}, residual ${fmt(r.residual)} [${r.statsSource}/${r.splitSource}]`);
    }

    const meta = {
        patch: table.patch || 'unknown',
        derivedAt: opts.derivedAt || new Date().toISOString(),
        documents: docs.map((d) => ({ file: path.basename(d.file), sha256: d.sha256 })),
        assumedFinish: opts.finish,
        assumedBuffs: {},
        dr: DEFAULT_DR,
        tiers,
        balance: opts.balance,
        compareVectors: table.sources.filter((x) => x.kind.startsWith('compare rows')).reduce((n, x) => n + x.vectors, 0),
    };
    const lua = render(buildTable(fits, meta), meta);
    const luaPath = path.join(opts.out, 'EngineWeights.dev.lua');
    fs.writeFileSync(luaPath, lua);
    say('');
    say(`wrote ${fits.length} fit file(s) and ${luaPath}`);
    return { fits: fits.map((f) => f.fit), luaPath, lua };
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(`fit-weights: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, parseArgs, bandKey };
