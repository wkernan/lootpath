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

// Temp file in the same directory, then rename: the client either reads the
// file that was there or the whole new one, never a prefix of either.
function writeAtomic(target, text) {
    const dir = dataDir(target);
    const temp = path.join(dir, `.${path.basename(target)}.${process.pid}.tmp`);
    fs.writeFileSync(temp, text, 'utf8');
    try {
        fs.renameSync(temp, target);
    } catch (e) {
        fs.rmSync(temp, { force: true });
        throw e;
    }
    return { bytes: Buffer.byteLength(text, 'utf8'), target, temp };
}

function writeVerdict(target, text) {
    return writeAtomic(target, text);
}

module.exports = { writeVerdict, writeAtomic, dataDir };
