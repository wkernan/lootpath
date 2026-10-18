#!/usr/bin/env node
// Strip every player but the owner from a WoWCombatLog segment before it is
// committed (E-5, WKE-711; docs/COMBAT-LOG-WEIGHTS.md §10). Replaces
// tools/combatlog/anonymise.py, which stripped the first fixture.
//
//   node anonymise.js <in.txt[.gz]> <out.txt[.gz]> <owner GUID>
//
// An output path ending in .gz is gzipped (level 9). Refuses to write when any
// original GUID or name of four or more letters is left. Prints the counts
// and both sha256s (of the plain text).
'use strict';

const fs = require('fs');
const zlib = require('zlib');
const crypto = require('crypto');
const { readText } = require('./lib/parse');
const { anonymise } = require('./lib/anonymise');

const sha = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');
const lineCount = (s) => (s.match(/\n/g) || []).length;

function run(argv, log) {
    const say = log || console.log;
    if (argv.length !== 3) throw new Error('usage: node anonymise.js <in.txt[.gz]> <out.txt[.gz]> <owner GUID>');
    const [src, dst, owner] = argv;
    const text = readText(src);
    const r = anonymise(text, owner);
    if (r.leftover.length) throw new Error(`left in the output, nothing written: ${r.leftover.slice(0, 10).join(', ')}`);
    const bytes = Buffer.from(r.text, 'utf8');
    fs.writeFileSync(dst, dst.endsWith('.gz') ? zlib.gzipSync(bytes, { level: 9 }) : bytes);
    say(`players replaced: ${r.players} names: ${r.names}`);
    say(`lines in: ${lineCount(text)} lines out: ${lineCount(r.text)}`);
    say(`owner events: ${r.text.split(owner).length - 1}`);
    say(`sha256 in : ${sha(text)} ${Buffer.byteLength(text, 'utf8')}`);
    say(`sha256 out: ${sha(r.text)} ${bytes.length}`);
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
