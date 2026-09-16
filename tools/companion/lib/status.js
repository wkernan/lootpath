// Writes Lootpath/Data/CompanionStatus.lua: the second file the companion puts
// inside the game folder (C-9, WKE-559), and the answer to the oldest complaint
// about it - that a run which died and a run which had nothing to do look the
// same from inside the game (docs/ARCHITECTURE.md 11, 2026-09-09).
//
// Same rules as the verdict chunk (lib/luawriter.js): DATA, never code. One
// local, a guard that it really was loaded by the addon, one assignment of one
// table of string literals and numbers. It carries no healer value and no gear;
// it says what the last run did and when.
//
//   state              "idle" | "running" | "skipped" | "failed"
//   startedAt          ISO 8601 UTC, when this run began
//   finishedAt         ISO 8601 UTC, when it stopped - absent while running
//   stage              the stage the run is in, or died in, in the log's words
//   message            one sentence for the strip's tooltip
//   profileCapturedAt  the capture stamp the profile was built from, as the
//                      SavedVariables spell it (local, no Z)
//   verdictWrittenAt   the `writtenAt` of the verdict this run wrote
//   exitCode           the code the run returned, once it has one
//
// It is written at EVERY stage change, not once at the end, so a run in
// progress says so rather than leaving the last run's words on screen for the
// three minutes QE Live takes.
'use strict';

const luaWriter = require('./luawriter');
const output = require('./output');

// The four the addon knows (ns.Companion.STATUS_STATES). A name that is not one
// of them is refused here rather than written: the addon would show it as a
// status it cannot read, and a status nobody can read is worse than none.
const STATES = ['idle', 'running', 'skipped', 'failed'];

// The stages, in the order a run walks them, and the same words lib/log.js
// prints - so "FAILED at profile" on the status strip and `profile: ...` in the
// log name one thing.
const STAGES = ['start', 'savedvariables', 'read', 'profile', 'qe live', 'write'];

const STRING_FIELDS = ['state', 'startedAt', 'finishedAt', 'stage', 'message', 'profileCapturedAt', 'verdictWrittenAt', 'companionVersion'];

function stamp(at) {
    return at.toISOString().replace(/\.\d+Z$/, 'Z');
}

// ONE SENTENCE, ALWAYS (C-14, WKE-603).
//
// `message` has said "one sentence for the strip's tooltip" since C-9 and
// nothing enforced it. On 2026-09-16 the fork's click timed out and Playwright's
// whole error went in - its call log, its retry lines, and its ANSI colour
// codes, which the game's font draws as boxes - and from there onto the status
// strip's tooltip, which the owner read as a blob the height of his screen.
//
// So the file gets the first line, with the escape sequences taken out and a
// cap on its length; `Data/companion.log` keeps the whole text, which is where
// a reader who wants the call log should be looking anyway.
const MESSAGE_MAX = 200;

function oneSentence(message) {
    if (typeof message !== 'string') {
        return message;
    }
    const clean = message.replace(/\u001b\[[0-9;]*m/g, '');
    const first = clean.split(/\r?\n/)[0].trim();
    if (first.length <= MESSAGE_MAX) {
        return first;
    }
    return first.slice(0, MESSAGE_MAX - 3).trimEnd() + '...';
}

// The chunk, rendered from a plain record. Every string goes through the
// verdict writer's escaper - the one that is tested against quotes,
// backslashes, "]]", newlines and control bytes - because a message here is
// whatever a failure said, and a failure message is the least trustworthy
// string the companion handles.
function render(record) {
    if (!STATES.includes(record.state)) {
        throw new Error(`refusing to write status state ${JSON.stringify(record.state)}; it is not one of ${STATES.join(', ')}`);
    }
    const lines = [
        '-- Lootpath/Data/CompanionStatus.lua - written by the Lootpath companion (tools/companion).',
        '-- Generated data, never edited by hand and never a place to put logic.',
        '-- What the companion last did, so the status strip can say it (C-9, WKE-559).',
        `-- Written at ${stamp(record.at || new Date())}.`,
        'local _, ns = ...',
        'if type(ns) ~= "table" then',
        '    return',
        'end',
        'ns.companionStatus = {',
    ];
    for (const key of STRING_FIELDS) {
        const value = key === 'message' ? oneSentence(record[key]) : record[key];
        if (value === undefined || value === null || value === '') {
            continue;
        }
        lines.push(`    ${key} = ${luaWriter.luaString(value)},`);
    }
    if (record.exitCode !== undefined && record.exitCode !== null) {
        if (!Number.isInteger(record.exitCode) || record.exitCode < 0) {
            throw new Error(`refusing to write exitCode ${JSON.stringify(record.exitCode)}; it is not a whole exit code`);
        }
        lines.push(`    exitCode = ${luaWriter.luaNumber(record.exitCode)},`);
    }
    lines.push('}', '');
    return lines.join('\n');
}

// The recorder the run drives. `file` null (a --profile-only dry run) makes
// every call a no-op, so the last real run's status is not overwritten by one
// that never asked QE Live anything.
//
// Nothing here can fail a run: a status file that will not write is reported
// once through `onError` and then left alone, exactly like the log file. The
// verdict is the product; this is the companion talking about itself.
function make(options) {
    const opts = options || {};
    const file = opts.file || null;
    const clock = opts.clock || (() => new Date());
    const onError = opts.onError || (() => {});
    let broken = false;
    const record = {
        state: 'idle',
        companionVersion: opts.companionVersion,
    };

    function flush() {
        if (!file || broken) {
            return null;
        }
        try {
            record.at = clock();
            return output.writeAtomic(file, render(record));
        } catch (e) {
            broken = true;
            onError(e);
            return null;
        }
    }

    const status = {
        file,
        // What would be written, for the tests and for nothing else.
        current() {
            return { ...record };
        },
        // A run begins: everything the last run said is cleared, because half
        // of it (the stage it died at, the verdict it wrote) is about a run
        // that is over.
        started(fields) {
            const startedAt = stamp(clock());
            for (const key of STRING_FIELDS) {
                delete record[key];
            }
            delete record.exitCode;
            record.companionVersion = opts.companionVersion;
            record.state = 'running';
            record.startedAt = startedAt;
            record.stage = 'start';
            Object.assign(record, fields || {});
            return flush();
        },
        // A stage change while the run is still going.
        stage(name, fields) {
            record.state = 'running';
            record.stage = name;
            Object.assign(record, fields || {});
            return flush();
        },
        // The profile was unchanged, so QE Live was never asked (C-4). Not a
        // failure and not a write: its own state, because "nothing to do" and
        // "nothing happened" are the two the owner could not tell apart.
        skipped(message, fields) {
            record.state = 'skipped';
            record.message = message;
            record.finishedAt = stamp(clock());
            record.exitCode = 0;
            Object.assign(record, fields || {});
            return flush();
        },
        // The run died. The stage is the one the log just named, so the strip
        // can say "FAILED at profile" and the log says why.
        failed(stage, message, exitCode) {
            record.state = 'failed';
            record.stage = stage;
            // C-14 (WKE-603): the first line, stripped and capped. The log
            // already has the whole thing.
            record.message = oneSentence(message);
            record.finishedAt = stamp(clock());
            record.exitCode = exitCode;
            return flush();
        },
        // The verdict is on disk. `verdictWrittenAt` is the file's own
        // `writtenAt`, so the strip's age and the verdict's age are one number
        // read from two files.
        wrote(verdictWrittenAt, fields) {
            record.state = 'idle';
            record.stage = 'write';
            record.verdictWrittenAt = verdictWrittenAt;
            record.finishedAt = stamp(clock());
            record.exitCode = 0;
            Object.assign(record, fields || {});
            return flush();
        },
    };
    return status;
}

module.exports = { make, render, stamp, oneSentence, STATES, STAGES, STRING_FIELDS, MESSAGE_MAX };
