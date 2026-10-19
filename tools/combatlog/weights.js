#!/usr/bin/env node
// A healer spec's stat weights from the player's own combat log (E-5,
// WKE-711; E-5b, WKE-713). The method is docs/COMBAT-LOG-WEIGHTS.md; which
// spec's table and constants apply comes from lib/specs/index.js, keyed by
// the found player's spec ID. Only Restoration (105) has a module today.
// This file only drives the method.
//
//   node weights.js <WoWCombatLog.txt[.gz]>... [--player <GUID>] [--patch 12.1.5]
//                   [--out <dir>] [--derived-at <ISO>] [--resamples N] [--seed N]
//
// Writes <out>/EngineWeights.combatlog.lua (E-4's schema version 2, one entry
// for the walked spec, `method = "combat-log"`) and
// <out>/combatlog-weights.json (the same entry and the per-segment figures),
// and prints the weights with their intervals. DEV ONLY: developer data until
// a dated decision promotes it.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const P = require('./lib/parse');
const { walk, segmentWeights } = require('./lib/attribute');
const { loadDR } = require('./lib/dr');
const { buildEntry, buildTable, render, specOf, RANKED } = require('./lib/entry');
const specs = require('./lib/specs');

const USAGE = 'usage: node weights.js <log>... [--player <GUID>] [--patch <x.y.z>] [--out <dir>] [--derived-at <ISO>] [--resamples N] [--seed N]';

function parseArgs(argv) {
    const o = { logs: [], out: path.join(__dirname, 'out') };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        const val = () => {
            if (i + 1 >= argv.length) throw new Error(`${a} needs a value\n${USAGE}`);
            return argv[++i];
        };
        if (a === '--player') o.player = val();
        else if (a === '--patch') o.patch = val();
        else if (a === '--out') o.out = val();
        else if (a === '--derived-at') o.derivedAt = val();
        else if (a === '--resamples') o.resamples = Number(val());
        else if (a === '--seed') o.seed = Number(val());
        else if (a.startsWith('--')) throw new Error(`unknown option ${a}\n${USAGE}`);
        else o.logs.push(a);
    }
    if (!o.logs.length) throw new Error(USAGE);
    return o;
}

// The client build from a raw log's header line, when it has one.
function headerPatch(text) {
    const m = /COMBAT_LOG_VERSION,\d+,ADVANCED_LOG_ENABLED,(\d),BUILD_VERSION,([\d.]+)/.exec(text.slice(0, 4096));
    return m ? { advanced: m[1] === '1', patch: m[2] } : null;
}

function run(argv, log) {
    const say = log || console.log;
    const o = parseArgs(argv);
    const dr = loadDR();
    const walks = [];
    let patch = o.patch;
    for (const file of o.logs) {
        const buf = fs.readFileSync(file);
        const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
        const text = P.readText(file);
        const head = headerPatch(text);
        if (head && !head.advanced) throw new Error(`${file}: Advanced Combat Logging was off; the method needs it`);
        if (head) {
            if (patch && patch !== head.patch) throw new Error(`${file}: build ${head.patch}, but --patch or another log says ${patch}`);
            patch = head.patch;
        }
        const w = walk(P.parseText(text), { dr, player: o.player });
        walks.push({ file: path.basename(file), sha256, walk: w });
    }
    if (!patch) throw new Error('no log header names the build: pass --patch (the README of a committed segment records it)');
    const derivedAt = o.derivedAt || new Date().toISOString().replace(/\.\d+Z$/, 'Z');
    const est = {};
    if (o.resamples !== undefined) est.resamples = o.resamples;
    if (o.seed !== undefined) est.seed = o.seed;
    const entry = buildEntry(walks, dr, { derivedAt, estimate: est });
    const specID = specOf(walks);
    const table = buildTable(entry, { patch, dr, specID });
    const lua = render(table, { logs: walks, specName: specs.get(specID).identity.name });
    fs.mkdirSync(o.out, { recursive: true });
    const file = path.join(o.out, 'EngineWeights.combatlog.lua');
    fs.writeFileSync(file, lua);
    const segments = walks.flatMap(({ file: f, walk: w }) =>
        w.segments.map((s) => ({ log: f, kind: s.kind, name: s.name, band: s.band, seconds: (s.end - s.start) / 1000, events: s.sums.events, effective: s.sums.effective, relative: segmentWeights(s, dr).relative }))
    );
    const json = JSON.stringify({ schema: 'lootpath-combatlog-weights', version: 1, patch, entry: { ...entry, tiers: undefined }, segments }, null, 2) + '\n';
    fs.writeFileSync(path.join(o.out, 'combatlog-weights.json'), json);

    say(`player ${walks.map((w) => w.walk.player).join(', ')}; patch ${patch}; logs ${walks.length}`);
    for (const ct of ['Dungeon', 'Raid']) {
        if (!entry[ct]) continue;
        for (const [band, b] of Object.entries(entry[ct].bands)) {
            say(`\n${ct} band ${band}: ${b.segments} segments, ${b.events} heal events (${b.eventsWithoutOverheal} without overheal), overheal ${(b.overhealShare * 100).toFixed(1)}% of raw`);
            say('stat        per percent (value 100 at her stats)   per rating point / Int   interval            ');
            for (const k of RANKED) {
                const r = b.perRatingPoint[k];
                const iv = b.intervals[k];
                say(
                    `${k.padEnd(10)}  ${String(b.weights[k]).padEnd(14)} [${iv ? `${iv.lo}, ${iv.hi}` : '-'}]`.padEnd(56) +
                        `${r ? r.mean.toFixed(4) : '-'}`.padEnd(10) +
                        `${r ? `[${r.lo.toFixed(4)}, ${r.hi.toFixed(4)}]` : ''}`.padEnd(20) +
                        (b.unshipped && b.unshipped[k] ? `UNSHIPPED: ${b.unshipped[k]}` : '')
                );
            }
            if (b.hasteCastForm) say(`haste, cast form: per rating point / Int ${b.hasteCastForm.perRatingPoint.mean.toFixed(4)} [${b.hasteCastForm.perRatingPoint.lo.toFixed(4)}, ${b.hasteCastForm.perRatingPoint.hi.toFixed(4)}]`);
            say(`baseValue ${b.baseValue}`);
        }
    }
    say(`\nwrote ${file}`);
    return { file, lua, table, entry, walks, json };
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(err.message);
        process.exit(1);
    }
}

module.exports = { run, parseArgs, headerPatch };
