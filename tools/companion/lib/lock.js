// Never two watchers (measured 2026-09-07, docs/ARCHITECTURE.md 9).
//
// Two companions watching one SavedVariables file both wake on the same
// /reload, both build the same profile, and both drive the same browser
// profile directory - which is a fork run that fights itself and a verdict file
// written twice from two runs that disagree. The rule has been written down
// since C-1; since C-9 (WKE-559) it is ENFORCED, because a start-with-Windows
// task means the owner no longer knows by hand whether one is already running.
//
// A lock file in the state directory, holding the pid that took it. A pid that
// is no longer alive does not hold anything: the lock is taken over and said
// so, because a machine that lost power mid-run must not need a file deleted by
// hand before the companion will start again.
'use strict';

const fs = require('fs');
const path = require('path');

// `process.kill(pid, 0)` sends no signal and answers the one question here.
// EPERM means a process with that pid exists and belongs to somebody else,
// which is still a process: on Windows every kill of a foreign pid answers
// that way, so it counts as alive.
function alive(pid) {
    if (!Number.isInteger(pid) || pid <= 0) {
        return false;
    }
    try {
        process.kill(pid, 0);
        return true;
    } catch (e) {
        return e && e.code === 'EPERM';
    }
}

// Whoever the file says holds it, or null for a file that is missing,
// unreadable or not the JSON this writes. An unreadable lock is not a held
// lock: it is a lock nobody can prove, and the companion would rather run than
// refuse on a broken byte.
function read(file) {
    let text;
    try {
        text = fs.readFileSync(file, 'utf8');
    } catch {
        return null;
    }
    try {
        const held = JSON.parse(text);
        if (!held || typeof held !== 'object' || !Number.isInteger(held.pid)) {
            return null;
        }
        return held;
    } catch {
        return null;
    }
}

// acquire(file) -> { ok: true, held, took, release() } or { ok: false, held }.
// `took` is true when a dead pid's lock was taken over, so the caller can say
// so in the log instead of pretending nothing was there.
function acquire(file, options) {
    const opts = options || {};
    const pid = opts.pid || process.pid;
    const isAlive = opts.alive || alive;
    const now = opts.now || (() => new Date());
    const existing = read(file);
    if (existing && existing.pid !== pid && isAlive(existing.pid)) {
        return { ok: false, held: existing };
    }
    const held = {
        pid,
        startedAt: now().toISOString().replace(/\.\d+Z$/, 'Z'),
        watching: opts.watching || null,
    };
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(held, null, 4) + '\n', 'utf8');
    return {
        ok: true,
        held,
        took: !!(existing && existing.pid !== pid),
        // Only ever removes OUR lock: a file that now names another pid belongs
        // to the watcher that took over after this one died, and deleting it
        // would let a third start beside it.
        release() {
            const current = read(file);
            if (current && current.pid !== pid) {
                return false;
            }
            fs.rmSync(file, { force: true });
            return true;
        },
    };
}

module.exports = { acquire, read, alive };
