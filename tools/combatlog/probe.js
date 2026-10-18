#!/usr/bin/env node
// The method's two checks on a log (E-5; docs/COMBAT-LOG-WEIGHTS.md §8): the
// crit multiplier and Harmony's count against its stack table.
//   node probe.js <WoWCombatLog.txt[.gz]> [--player <GUID>] [--min-pairs N]
'use strict';

const P = require('./lib/parse');
const { probe } = require('./lib/probe');
const { loadDR } = require('./lib/dr');

function run(argv, log) {
    const say = log || console.log;
    const args = argv.slice();
    const opt = (name) => {
        const i = args.indexOf(name);
        if (i < 0) return undefined;
        const v = args[i + 1];
        args.splice(i, 2);
        return v;
    };
    const player = opt('--player');
    const minPairs = opt('--min-pairs');
    if (args.length !== 1) throw new Error('usage: node probe.js <log> [--player <GUID>] [--min-pairs N]');
    const r = probe(P.parseText(P.readText(args[0])), { dr: loadDR(), player, minPairs: minPairs === undefined ? 20 : Number(minPairs) });
    say(`crit multiplier: median ${r.critMultiplier.median === null ? '-' : r.critMultiplier.median.toFixed(4)} over ${r.critMultiplier.pairs} critical ticks between two uncritical ones`);
    say(`mastery points at her rating: ${r.masteryPoints.toFixed(4)}`);
    say("Harmony's count, consecutive uncritical ticks of one effect on one target:");
    say('change  pairs  median   predicted');
    for (const g of r.harmony) say(`${g.change.padEnd(6)}  ${String(g.pairs).padStart(5)}  ${g.median.toFixed(4)}   ${g.predicted.toFixed(4)}`);
    return r;
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(err.message);
        process.exit(1);
    }
}

module.exports = { run };
