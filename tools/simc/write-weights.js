#!/usr/bin/env node
// tools/simc/write-weights.js (E-7, WKE-710) - DEVELOPER ONLY, never shipped.
//
// Writes the weights file's version 2 per-spec entries (`method = "simc"`) for
// DPS and tank specs from run-scale-factors.js's output, through
// tools/engine/lib/luaout.js - the one writer of that file. Raid comes from the
// Patchwerk run, Dungeon from the DungeonSlice run, each as ONE band `all`
// (key-level scaling is not modelled).
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { simcSpecEntry, buildSimcTable, renderSimc } = require('../engine/lib/luaout');
const { DEFAULT_DR } = require('../engine/lib/dr');

const USAGE = `usage: node write-weights.js <specID> [<specID> ...] [--in <dir>] [--out <file>]

Writes a version 2 weights file holding one "simc" entry per spec, from
<dir>/<specID>-Patchwerk.json (Raid) and <dir>/<specID>-DungeonSlice.json
(Dungeon), both written by run-scale-factors.js. DPS and TANK specs only:
SimulationCraft models no healer.

  --in <dir>    default tools/simc/out
  --out <file>  default tools/simc/out/EngineWeights.simc.lua`;

const CONTENT = { Raid: 'Patchwerk', Dungeon: 'DungeonSlice' };

function sha256(file) {
    return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function run(argv, log) {
    log = log || console.log;
    const specIDs = [];
    let inDir = path.join(__dirname, 'out');
    let outFile;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--in') inDir = argv[++i];
        else if (a === '--out') outFile = argv[++i];
        else if (a === '--help' || a === '-h') specIDs.length = 0;
        else if (/^\d+$/.test(a)) specIDs.push(Number(a));
        else throw new Error(`unknown argument ${a}`);
    }
    if (!specIDs.length) {
        log(USAGE);
        return { usage: true };
    }
    inDir = path.resolve(inDir);
    outFile = path.resolve(outFile || path.join(inDir, 'EngineWeights.simc.lua'));

    const specs = new Map();
    const inputs = [];
    let patch;
    for (const id of specIDs) {
        const byContent = {};
        for (const [ct, fight] of Object.entries(CONTENT)) {
            const file = path.join(inDir, `${id}-${fight}.json`);
            if (!fs.existsSync(file)) throw new Error(`missing ${file}: run run-scale-factors.js ${id} --fight ${fight} first`);
            const e = JSON.parse(fs.readFileSync(file, 'utf8'));
            if (e.specID !== id) throw new Error(`${file} is for spec ${e.specID}, not ${id}`);
            if (e.fight !== fight) throw new Error(`${file} is a ${e.fight} run, not ${fight}`);
            if (e.role !== 'DAMAGER' && e.role !== 'TANK') throw new Error(`${file}: role ${e.role} - SimulationCraft models no healer`);
            if (patch === undefined) patch = e.patch;
            if (e.patch !== patch) throw new Error(`${file} is for game patch ${e.patch}, another input for ${patch}: one file holds one patch`);
            byContent[ct] = e;
            inputs.push({ file: path.basename(file), sha256: sha256(file) });
        }
        specs.set(id, simcSpecEntry(byContent));
    }
    const table = buildSimcTable(specs, { patch, dr: DEFAULT_DR });
    const lua = renderSimc(table, { inputs });
    fs.mkdirSync(path.dirname(outFile), { recursive: true });
    fs.writeFileSync(outFile, lua);
    log(`wrote ${outFile} (${specIDs.join(', ')}; patch ${patch})`);
    return { lua, file: outFile, table };
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(err.message);
        process.exit(1);
    }
}

module.exports = { run, USAGE };
