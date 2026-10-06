#!/usr/bin/env node
// The trinket probe (E-3c, WKE-686). DEV ONLY - nothing here ships.
//
//   node probe-trinkets.js --stats <capture.lua> [--stats ...]
//        --key-levels 1=2,2=4,4=6,6=8,7=10
//        --compare <SavedVariables.lua> --week 2026-09-29 --char "Hotornot - Arthas"
//        [--inventory 4] [--rows spec/fixtures/engine/compare-20260929.lua]
//        [--effects Lootpath/Data/EngineEffects.lua]
//        <fit export.json|dir> ...
//
// Re-runs week one's compare, headless, with the effects table's params in
// it, and prints the trinket class (and what the worn trinkets' effects do to
// every other class) BEFORE and AFTER. Nothing here is promoted: the figures
// are a report.
//
//   before   the week-one entries the `--compare` file STORED (E-3a's
//            compare: every trinket row `not rated`, no trinket metrics)
//   rows     week one's trinket rows: the `--rows` fixture (the same week's
//            E-0h run, documents exported 2026-10-01T13:59, stored before
//            E-3a left trinket rows out) - every trinket row of each
//            document, less those at a level no track step draws (E-0g step
//            2 leaves them out at their level); their count is checked
//            against the stored entry's `notRated`
//   effects  each worn trinket's effect at its read level and each candidate
//            trinket's at its key level, through the shipped table's params
//            (ns.EngineEffects.ParamsAt, ported below with the two rules a
//            `generic` entry uses today: PassiveStat and StatOnUse); a level
//            the table has no params for is `not modelled`, never the
//            nearest level
//   after    every stored non-trinket row re-scored with the worn trinkets'
//            effects in the worn set (and in every set the row makes, since
//            the row leaves the trinkets worn): exactly raw x V(worn) /
//            V(worn + effects) when no total crosses a DR bracket - the probe
//            checks the headroom and says so - and recomputed directly for
//            every row whose candidate link a transcript read; every trinket
//            row whose candidate AND replaced trinket are `generic` scored
//            with both effects (its stats `client` or `client-scaled` from
//            the transcripts, named), the rest left `not rated` with the
//            reason
//
// SIGN and FLOOR as probe-jewellery.js: theirs is the stored `theirs`, ours
// is floored at EngineCompare.UF_FLOOR (0) before every metric.
'use strict';

const fs = require('fs');
const path = require('path');
const { parseSavedVariables } = require('../companion/lib/lua-savedvariables');
const { loadTable, buildBudget, itemStats, statsForLink, SECONDARIES } = require('./lib/stats');
const { DEFAULT_DR, ratingToPercent } = require('./lib/dr');
const { totals, zeroStats, STATS } = require('./lib/score');
const { readLuaTable } = require('./lib/luatable');
const { wornFromCapture } = require('./percent-scale');
const PJ = require('./probe-jewellery');

const REPO = path.join(__dirname, '..', '..');
const DEFAULT_ROWS = path.join(REPO, 'spec', 'fixtures', 'engine', 'compare-20260929.lua');
const DEFAULT_EFFECTS = path.join(REPO, 'Lootpath', 'Data', 'EngineEffects.lua');
const TRINKET = 'trinket';
// The fixture's documents by the stored entry's content type and key level.
const ROW_DOCS = { 'Dungeon 6': 'Dungeon 6', 'Dungeon 10': 'Dungeon 10', 'Raid 10': 'Raid' };

function parseArgs(argv) {
    const rest = [];
    const o = { rows: DEFAULT_ROWS, effects: DEFAULT_EFFECTS };
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === '--rows') o.rows = argv[++i];
        else if (argv[i] === '--effects') o.effects = argv[++i];
        else rest.push(argv[i]);
    }
    return { ...PJ.parseArgs(rest), ...o };
}

// --- ns.EngineEffects, the two rules a `generic` entry uses ------------------

function paramsAt(params, level) {
    if (!params || typeof params !== 'object') return null;
    if (params.byLevel === undefined || params.byLevel === null) return params;
    const at = params.byLevel[String(level)];
    if (!at || typeof at !== 'object') return null;
    const out = {};
    for (const [k, v] of Object.entries(params)) if (k !== 'byLevel') out[k] = v;
    return { ...out, ...at };
}

const positive = (x) => typeof x === 'number' && x > 0 && Number.isFinite(x);

// -> { stat: vector } or { why } for an entry at a level.
function effectAt(table, id, level) {
    const entry = table.items[String(id)];
    if (!entry) return { why: 'not in the effects table' };
    const name = entry.name;
    if (entry.confidence !== 'generic') return { why: `${name}: ${entry.kind}, not modelled`, name };
    const p = paramsAt(entry.params, level);
    if (!p) return { why: `${name}: no params at ${level}`, name };
    if (entry.kind === 'passive_stat' && p.stat && typeof p.stat === 'object') {
        return { name, stat: { ...p.stat } };
    }
    if (entry.kind === 'stat_on_use' && typeof p.stat === 'string' && positive(p.amount) && positive(p.duration) && positive(p.cooldown)) {
        return { name, stat: { [p.stat]: p.amount * Math.min(1, p.duration / p.cooldown) } };
    }
    throw new Error(`${name}: a generic ${entry.kind} this probe has no port of`);
}

function effectItem(stat) {
    const stats = zeroStats();
    for (const [k, v] of Object.entries(stat)) stats[k] = v;
    return { id: null, slot: 'Effect', stats };
}

// --- the probe -------------------------------------------------------------

function run(argv, log) {
    const say = log || console.log;
    const o = parseArgs(argv);
    if (!o.stats.length) throw new Error('--stats is required');
    if (!o.compare || !o.week || !o.char) throw new Error('--compare, --week and --char are required');
    const fitDocs = PJ.expandExports(o.exports).map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
    if (!fitDocs.length) throw new Error('no Upgrade Finder export to fit');
    const table = loadTable(o.stats, fs);
    for (const d of fitDocs) for (const r of [...d.equipped, ...d.items]) if (r.slot && !table.slotOf.has(r.id)) table.slotOf.set(r.id, r.slot);
    const budget = buildBudget(table);
    const bands = PJ.fitBands(fitDocs, table, budget, o.keyLevels);
    const effects = readLuaTable(fs.readFileSync(o.effects, 'utf8'), /^ns\.engineEffects\s*=/m);
    const fixture = readLuaTable(fs.readFileSync(o.rows, 'utf8'), /^return/m);

    const sv = parseSavedVariables(fs.readFileSync(o.compare, 'utf8'));
    const worn = wornFromCapture(sv, o.inventory).map((e) => {
        const s = itemStats(table, budget, e);
        return { ...e, stats: s.stats || zeroStats(), statsSource: s.statsSource };
    });
    const blocks = PJ.storedBlocks(sv, o.week, o.char);
    const entries = sv.LootpathDB.global.engineCompare[o.week][o.char];
    const f3 = (x) => (x === null || x === undefined ? '-' : x.toFixed(3));
    const f4 = (x) => (x === null || x === undefined ? '-' : x.toFixed(4));
    const pc = (x) => (x === null || x === undefined ? '-' : `${Math.round(100 * x)}%`);
    const line = (label, m) => `  ${label.padEnd(24)} n ${String(m.n).padStart(2)}  rho ${f3(m.rho).padStart(6)}  top1 ${pc(m.top1).padStart(4)}  sign ${pc(m.sign).padStart(4)}  MAE ${f3(m.mae)}  k ${f3(m.k)}  MAE@k ${f3(m.maeK)}`;

    // The worn trinkets' effects.
    const wornTrinkets = worn.map((w, i) => ({ w, i })).filter((x) => x.w.slot === 'Trinket');
    const wornEffects = wornTrinkets.map(({ w, i }) => ({ i, id: w.id, level: w.level, ...effectAt(effects, w.id, w.level) }));
    say(`worn trinkets (${o.compare}, inventory ${o.inventory}): ${wornEffects.map((e) => `${e.id}@${e.level} ${e.name || '?'}: ${e.stat ? Object.entries(e.stat).map(([k, v]) => `${k} ${v.toFixed(4)}`).join(', ') : e.why}`).join('; ')}`);
    const allGeneric = wornEffects.every((e) => e.stat);
    const wornWith = [...worn, ...wornEffects.filter((e) => e.stat).map((e) => effectItem(e.stat))];

    // Is the identity exact? Headroom from the worn totals with the effects
    // to each secondary's first DR bracket, against the largest amount of
    // that secondary any single item read carries.
    const t1 = totals(wornWith, null);
    let largest = {};
    for (const k of SECONDARIES) largest[k] = 0;
    for (const p of table.points.values()) for (const k of SECONDARIES) largest[k] = Math.max(largest[k], p.stats[k] || 0);
    const headroom = {};
    let linear = true;
    for (const k of SECONDARIES) {
        const first = DEFAULT_DR[k].brackets && DEFAULT_DR[k].brackets.length ? DEFAULT_DR[k].brackets[0].from : Infinity;
        headroom[k] = { total: t1[k], firstBracket: first, largestItem: largest[k] };
        if (t1[k] + largest[k] >= first) linear = false;
    }
    say(`worn totals with the effects, first DR bracket, largest single-item amount read: ${SECONDARIES.map((k) => `${k} ${headroom[k].total.toFixed(2)} / ${headroom[k].firstBracket} / ${headroom[k].largestItem}`).join('; ')} -> ${linear ? 'no single swap reaches a bracket: the rescale is exact' : 'A SWAP MAY REACH A BRACKET: the rescale is not exact'}`);

    const result = { worn: wornEffects, linear, headroom, blocks: [] };
    for (const b of blocks) {
        const band = bands[b.band];
        if (!band) throw new Error(`no fitted band ${b.band}`);
        const docKey = `${b.contentType} ${b.document}`;
        const stored = entries[b.contentType][b.document];
        const vWorn = PJ.value(worn, band);
        const vWith = PJ.value(wornWith, band);
        const s = vWorn / vWith;

        // Non-trinket rows: before as stored; after rescaled, and checked
        // directly where a transcript read the candidate.
        let direct = 0;
        let maxDirect = 0;
        const afterRows = b.rows.map((r) => {
            const raw = r.raw * s;
            const read = statsForLink(table, r.link);
            if (read && allGeneric) {
                const p = PJ.percent(wornWith, { id: r.id, slot: r.slot, stats: read }, band, false).percent;
                direct += 1;
                maxDirect = Math.max(maxDirect, Math.abs(p - raw));
            }
            return { ...r, raw, ours: Math.max(PJ.UF_FLOOR, raw) };
        });

        // Trinket rows: the fixture's, less the levels no step draws.
        const fixtureRows = ((fixture[ROW_DOCS[docKey]] || {}).rows || {});
        const trinketRows = Object.values(fixtureRows).filter((r) => r.class === TRINKET && !PJ.NO_STEP_LEVELS.has(Number(String(r.key).split('@')[1])));
        const rated = [];
        const left = [];
        for (const r of trinketRows) {
            const id = Number(String(r.key).split('@')[0]);
            const level = Number(String(r.key).split('@')[1]);
            const cand = effectAt(effects, id, level);
            if (!cand.stat) {
                left.push({ key: r.key, why: cand.why });
                continue;
            }
            const st = itemStats(table, budget, { id, level, slot: 'Trinket' });
            // Placements: the pair rule (a worn copy of the same item takes
            // the drop's place alone), else either trinket.
            const twins = wornTrinkets.filter((x) => x.w.id === id);
            const places = twins.length ? twins : wornTrinkets;
            let best = null;
            let blocked = null;
            for (const { i } of places) {
                const out = wornEffects.find((e) => e.i === i);
                if (!out.stat) {
                    blocked = out.why;
                    continue;
                }
                const set = worn.filter((_, j) => j !== i);
                set.push({ id, slot: 'Trinket', stats: st.stats });
                for (const e of wornEffects) if (e.i !== i && e.stat) set.push(effectItem(e.stat));
                set.push(effectItem(cand.stat));
                const v = PJ.value(set, band);
                if (!best || v > best.v) best = { v, replaced: `${worn[i].id}@${worn[i].level}` };
            }
            if (!best) {
                left.push({ key: r.key, why: `replaces ${blocked}` });
                continue;
            }
            const raw = (100 * (best.v - vWith)) / vWith;
            rated.push({ key: r.key, slot: 'Trinket', cls: TRINKET, raw, ours: Math.max(PJ.UF_FLOOR, raw), theirs: r.theirs, statsSource: st.statsSource, scaledFrom: st.scaledFrom, replaced: best.replaced, effect: cand.stat });
        }

        const classes = [...new Set(b.rows.map((r) => r.cls))].sort();
        const before = {};
        const after = {};
        for (const c of classes) {
            before[c] = PJ.metrics(b.rows.filter((r) => r.cls === c));
            after[c] = PJ.metrics(afterRows.filter((r) => r.cls === c));
        }
        const trinketAfter = rated.length ? PJ.metrics(rated) : null;
        const block = {
            contentType: b.contentType,
            document: b.document,
            band: b.band,
            storedNotRated: stored.notRated,
            storedTrinket: (stored.metrics || {})[TRINKET] || null,
            fixtureTrinketRows: trinketRows.length,
            vWorn,
            vWith,
            scale: s,
            direct,
            maxDirect,
            before,
            after,
            rated,
            left,
            trinketAfter,
        };
        result.blocks.push(block);

        say('');
        say(`== ${b.contentType} [${b.document}], band ${b.band}: V(worn) ${vWorn.toFixed(4)}, with the worn trinkets' effects ${vWith.toFixed(4)}, every non-trinket percent x ${s.toFixed(6)}${direct ? `; ${direct} transcript-read rows re-scored directly, largest difference ${maxDirect.toExponential(2)}` : ''}`);
        say(`  trinket rows: week one stored not rated ${stored.notRated}, trinket metrics ${block.storedTrinket ? 'stored' : 'none'}; the fixture's trinket rows at a level a step draws: ${trinketRows.length}${trinketRows.length === stored.notRated ? ' (the same count)' : ' (A DIFFERENT COUNT)'}`);
        say(line('trinket before (stored)', { n: 0 }).replace(/rho .*$/, 'not rated: every row'));
        if (trinketAfter) say(line('trinket after', trinketAfter));
        else say('  trinket after             n  0  (no row a rule covers)');
        for (const r of rated) say(`    rated ${r.key}: ours ${f4(r.ours)} (raw ${f4(r.raw)}) over ${r.replaced}, theirs ${r.theirs}; stats ${r.statsSource}${r.scaledFrom ? ` from ${r.scaledFrom}` : ''}; effect ${Object.entries(r.effect).map(([k, v]) => `${k} ${v.toFixed(4)}`).join(', ')}`);
        say(`    still not rated: ${left.length}${left.length ? ` (${left.map((x) => `${x.key} ${x.why}`).join('; ')})` : ''}`);
        for (const c of classes) {
            say(line(`${c} before`, before[c]));
            say(line(`${c} after`, after[c]));
        }
    }
    return result;
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(`probe-trinkets: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, paramsAt, effectAt };
