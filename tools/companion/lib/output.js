// Putting files into the game folder, safely.
//
// Two rules. The client must never read half a file, so a chunk is written
// beside its target and renamed over it (rename is atomic on NTFS, and libuv
// passes MOVEFILE_REPLACE_EXISTING so an existing file is replaced rather than
// refused). And a failed run must leave the previous good verdict alone, so
// nothing here runs until the documents are in hand and the chunk has been
// rendered in full.
//
// Since C-9 (WKE-559) three files live in that folder rather than one -
// `QEVerdict.lua`, `CompanionStatus.lua` and `companion.log` - so the directory
// rule is one function all three go through.
'use strict';

const fs = require('fs');
const path = require('path');

// The Data directory belongs to the addon; creating it is fine, creating the
// AddOns folder is not - that would mean the addon is not installed and the
// companion would be writing into nothing.
function dataDir(target) {
    const dir = path.dirname(target);
    const addonDir = path.dirname(dir);
    if (!fs.existsSync(addonDir)) {
        throw new Error(`the addon is not installed at ${addonDir} (run .\\tools\\sync.ps1 first)`);
    }
    fs.mkdirSync(dir, { recursive: true });
    return dir;
}

// C-17 (WKE-624): the rename is retried while the CLIENT is holding the file.
//
// 2026-09-21 17:40:23, the owner's terminal: `EPERM: operation not permitted,
// rename '...\.CompanionStatus.lua.47652.tmp' -> '...\CompanionStatus.lua'`.
// The SavedVariables had changed a second earlier - he was reloading, and the
// client reads `Data\*.lua` at that instant. Windows refuses a rename over a
// file another process holds open. The run then failed and the strip kept
// saying `rating your gear` for three minutes, because the failure was never
// written where the addon reads it.
//
// A reload's read of one small file is brief, so waiting it out is the whole
// fix. TEN tries over at most ~1.9 s: 25 ms before the second, doubling to a
// 300 ms ceiling (25, 50, 100, 200, then 300 five times). Ten because the
// warning must still arrive while a person is watching the terminal, and ~2 s
// because that is the order of a reload's read of one small file and far below
// the minutes a run takes. The numbers are a CHOICE, not a measurement:
// nothing here was timed against a real client, and the ceiling is only what
// keeps the wait bounded.
const RETRY_CODES = ['EPERM', 'EBUSY', 'EACCES'];
const RETRY_TRIES = 10;
const RETRY_FIRST_MS = 25;
const RETRY_MAX_MS = 300;

function backoff(attempt) {
    return Math.min(RETRY_FIRST_MS * Math.pow(2, attempt - 1), RETRY_MAX_MS);
}

// Synchronous, because every writer here is: the run has nothing else to do
// while the client finishes reading, and an async hop would let a later stage
// write the same file underneath this one.
function sleepSync(ms) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// Temp file in the same directory, then rename: the client either reads the
// file that was there or the whole new one, never a prefix of either.
//
// `options.onRetry(tries, target)` is called ONCE, and only when a rename
// needed more than one try - never per try, because a line every 25 ms is
// noise about a second nobody was hurt by. `options.sleep` is for the tests,
// so a bounded wait does not have to be waited out.
function writeAtomic(target, text, options) {
    const opts = options || {};
    const onRetry = opts.onRetry || (() => {});
    const sleep = opts.sleep || sleepSync;
    const dir = dataDir(target);
    const temp = path.join(dir, `.${path.basename(target)}.${process.pid}.tmp`);
    fs.writeFileSync(temp, text, 'utf8');
    for (let tries = 1; ; tries += 1) {
        try {
            fs.renameSync(temp, target);
        } catch (e) {
            // A path that is wrong, or a directory that went away, will be
            // just as wrong in two seconds: only the three codes a foreign
            // handle produces are worth waiting on. The temp file stays put
            // between tries - it is the whole rendered chunk, and rewriting it
            // each time would be work for nothing.
            if (tries < RETRY_TRIES && RETRY_CODES.includes(e.code)) {
                sleep(backoff(tries));
                continue;
            }
            fs.rmSync(temp, { force: true });
            throw e;
        }
        if (tries > 1) {
            onRetry(tries, target);
        }
        return { bytes: Buffer.byteLength(text, 'utf8'), target, temp, tries };
    }
}

function writeVerdict(target, text, options) {
    return writeAtomic(target, text, options);
}

module.exports = { writeVerdict, writeAtomic, dataDir, backoff, RETRY_CODES, RETRY_TRIES, RETRY_FIRST_MS, RETRY_MAX_MS };
