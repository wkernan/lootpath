// Is this profile the one QE Live was already run on? (WKE-537, C-4.)
//
// Every `/reload` writes SavedVariables and the watcher runs on every write, so
// the SECOND `/lootpath refresh` - the one whose only job is to load the file
// the companion wrote - used to start a QE Live run of its own over the same
// gear. Measured on the owner's machine 2026-09-07: the third run of the
// evening took 17.7 s to produce four documents byte-identical to the second's.
//
// The fix is a fingerprint of the profile with its volatile lines removed, and
// one small JSON file remembering the fingerprint of the last verdict actually
// written. Same fingerprint, and the file it names still on disk, means there
// is nothing to ask QE Live.
//
// It is deliberately a hash of the PROFILE, not of the SavedVariables: the
// profile is exactly what QE Live is asked about, so anything the profile does
// not carry cannot change the answer, and anything it does carry does.
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const STATE_FILE = 'last-profile.json';

// The lines that move on their own, with no change behind them. Each one is
// listed here rather than matched by a general "looks like a date" rule, so a
// new header line is a deliberate decision and not an accident.
//
// MEASURED 2026-09-08: `lib/simc-profile.js` was asked to build
// `spec/fixtures/captures/Lootpath-20260906-200908.lua` twice, the second time
// with the capture's local time moved from 2026-09-05T13:33:25 to
// 2026-09-08T09:01:02 and nothing else touched. Exactly three of the 148 lines
// differed: 0, 3 and the trailing checksum. The `# Built by ...` line (index 1)
// did not move, and is dropped anyway because it names this tool rather than the
// character - a change to that string is not a change to the gear.
const VOLATILE_LINES = [
    {
        // "# Hotornot - Guardian - 2026-09-05 13:33 - us/Arthas". The stamp is
        // the inventory capture's local time. Everything else on the line is
        // repeated on a real line below it (`druid="Hotornot"`, `spec=`,
        // `region=`, `server=`), so dropping the whole line hides nothing.
        pattern: /^# .+ - .+ - \d{4}-\d\d-\d\d \d\d:\d\d - /,
        why: 'the identity line carries the capture time',
    },
    {
        // "# Built by Lootpath's companion from SavedVariables ..." - constant
        // today, and about the tool rather than the character either way.
        pattern: /^# Built by Lootpath's companion /,
        why: 'the source line names this tool, not the gear',
    },
    {
        // "# Inventory captured 2026-09-05T13:33:25".
        pattern: /^# Inventory captured /,
        why: 'the capture stamp',
    },
    {
        // "# Checksum: cd13649" - adler32 over every line above it, so it moves
        // whenever the two stamps above do and has to go with them.
        pattern: /^# Checksum: /,
        why: 'adler32 over the body, so it follows the stamps above',
    },
];

// Returns the lines that survive and, for the record, the ones that did not.
function stripVolatile(profileText) {
    const kept = [];
    const dropped = [];
    const lines = String(profileText).split('\n');
    for (let i = 0; i < lines.length; i++) {
        const rule = VOLATILE_LINES.find((r) => r.pattern.test(lines[i]));
        if (rule) dropped.push({ index: i, line: lines[i], why: rule.why });
        else kept.push(lines[i]);
    }
    return { kept, dropped };
}

function fingerprint(profileText) {
    const { kept, dropped } = stripVolatile(profileText);
    return {
        hash: crypto.createHash('sha256').update(kept.join('\n'), 'utf8').digest('hex'),
        dropped,
    };
}

function statePath(stateDir) {
    return path.join(stateDir, STATE_FILE);
}

// Never throws. A state file that cannot be read is not an error worth stopping
// a run for - it only means the companion has forgotten, and forgetting must
// cost a run rather than skip one.
function readState(stateDir) {
    const file = statePath(stateDir);
    let raw;
    try {
        raw = fs.readFileSync(file, 'utf8');
    } catch (e) {
        if (e.code === 'ENOENT') return { ok: false, absent: true, file, reason: `${file} does not exist yet` };
        return { ok: false, file, reason: `${file} could not be read: ${e.message}` };
    }
    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (e) {
        return { ok: false, file, reason: `${file} is not valid JSON: ${e.message}` };
    }
    if (!parsed || typeof parsed.hash !== 'string' || typeof parsed.verdict !== 'string') {
        return { ok: false, file, reason: `${file} carries no hash and verdict path` };
    }
    return { ok: true, file, state: parsed };
}

// Written after the verdict file, never before: the hash records what the addon
// can actually read, so a run that failed to write leaves the previous
// fingerprint standing and the next run repeats the work.
function writeState(stateDir, state) {
    fs.mkdirSync(stateDir, { recursive: true });
    const file = statePath(stateDir);
    const temp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temp, JSON.stringify(state, null, 4) + '\n', 'utf8');
    try {
        fs.renameSync(temp, file);
    } catch (e) {
        fs.rmSync(temp, { force: true });
        throw e;
    }
    return file;
}

// Three things have to hold before a run is skipped: the profile is the same,
// the remembered verdict is the file this run would write, and that file is
// still there. The second is what keeps `--out <somewhere else>` honest.
function isCurrent(state, hash, target) {
    if (!state || state.hash !== hash) return { current: false, reason: 'the profile changed' };
    if (path.resolve(String(state.verdict)) !== path.resolve(target)) {
        return { current: false, reason: `the last verdict went to ${state.verdict}, not ${target}` };
    }
    if (!fs.existsSync(target)) return { current: false, reason: `${target} is gone` };
    return { current: true, writtenAt: state.writtenAt };
}

module.exports = { fingerprint, stripVolatile, readState, writeState, statePath, isCurrent, VOLATILE_LINES, STATE_FILE };
