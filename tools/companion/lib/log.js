// One line per stage, with the milliseconds it took. The companion runs
// unattended in a terminal behind the game, so the log is the only place a
// failure can be seen: it names the stage, never a stack trace alone.
//
// Since C-9 (WKE-559) the same lines are also APPENDED TO A FILE next to the
// verdict, `Lootpath/Data/companion.log`. The reason is the one
// docs/ARCHITECTURE.md 11 records on 2026-09-09: a watcher started from a
// session window printed into that window and nowhere else, so a refresh whose
// run died looked exactly like a refresh that had nothing to do. A log that
// outlives the window is the difference.
//
// A line reaches the terminal as `[19:47:02] profile: 15 equipped (41 ms)` and
// the file as `[2026-09-13T19:47:02Z] profile: 15 equipped (41 ms)`: the same
// text, with the date the terminal does not need and a file read tomorrow does.
'use strict';

const fs = require('fs');

const output = require('./output');

// 200 KB, one kept generation. A run writes on the order of twenty lines, so
// this is months of watching; the point of the cap is that an unattended
// program must not grow without bound inside the game folder.
const MAX_BYTES = 200 * 1024;

function clock(at) {
    return at.toTimeString().slice(0, 8);
}

// Second precision, the same shape `writtenAt` is written in (luawriter.js), so
// every stamp the companion produces reads the same way.
function stamp(at) {
    return at.toISOString().replace(/\.\d+Z$/, 'Z');
}

// The console sink, and the default when `make` is handed nothing.
function consoleSink() {
    return (line) => process.stdout.write(line + '\n');
}

// Rotation: at `maxBytes` the file becomes `<file>.1` and a new one starts.
// One generation is kept, deliberately - two would double the bytes in a folder
// the addon has to load out of, and the interesting failure is always the last
// one. Returns true when it rotated.
function rotate(file, maxBytes) {
    let size = 0;
    try {
        size = fs.statSync(file).size;
    } catch {
        return false;
    }
    if (size < maxBytes) {
        return false;
    }
    const previous = file + '.1';
    fs.rmSync(previous, { force: true });
    fs.renameSync(file, previous);
    return true;
}

// A sink that appends every line to `file`. It is deliberately forgiving: a log
// that cannot be written is reported ONCE through `onError` and then goes
// quiet, because a companion that dies over its own log file is worse than one
// that says nothing about it. The directory rule is output.js's - the Data
// folder is created, the AddOns folder never is.
function fileSink(file, options) {
    const opts = options || {};
    const maxBytes = opts.maxBytes || MAX_BYTES;
    const onError = opts.onError || (() => {});
    let broken = false;
    const sink = (line, record) => {
        if (broken) {
            return;
        }
        const at = (record && record.at) || new Date();
        const text = record ? record.text : line;
        try {
            output.dataDir(file);
            rotate(file, maxBytes);
            fs.appendFileSync(file, `[${stamp(at)}] ${text}\n`, 'utf8');
        } catch (e) {
            broken = true;
            onError(e);
        }
    };
    sink.file = file;
    sink.maxBytes = maxBytes;
    return sink;
}

// Every sink gets every line; one that throws does not rob the others of it.
function tee(...sinks) {
    const kept = sinks.filter(Boolean);
    return (line, record) => {
        for (const sink of kept) {
            try {
                sink(line, record);
            } catch {
                // A sink that throws has already failed its own way; the run
                // is not the place to find out about it.
            }
        }
    };
}

// `sink(line, record)` - `record` is { at, level, text }, where `text` is the
// line without the clock the terminal wants. A sink that takes only the line
// (every caller before C-9, and every test that captures one) is unaffected.
function make(sink) {
    const write = sink || consoleSink();
    const emit = (level, text) => {
        const at = new Date();
        write(`[${clock(at)}] ${text}`, { at, level, text });
    };
    const log = {
        info(message) {
            emit('info', String(message));
        },
        warn(message) {
            emit('warn', `warning: ${message}`);
        },
        error(message) {
            emit('error', `FAILED: ${message}`);
        },
        // stage("profile") -> done("15 equipped, 35 in bags") prints the note
        // and the elapsed milliseconds on one line.
        stage(name) {
            const started = Date.now();
            return (note) => {
                const ms = Date.now() - started;
                emit('info', `${name}: ${note ? note + ' ' : ''}(${ms} ms)`);
                return ms;
            };
        },
    };
    return log;
}

module.exports = { make, consoleSink, fileSink, tee, rotate, stamp, MAX_BYTES };
