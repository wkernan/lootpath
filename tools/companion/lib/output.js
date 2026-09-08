// Putting the file into the game folder, safely.
//
// Two rules. The client must never read half a file, so the chunk is written
// beside its target and renamed over it (rename is atomic on NTFS, and libuv
// passes MOVEFILE_REPLACE_EXISTING so an existing file is replaced rather than
// refused). And a failed run must leave the previous good verdict alone, so
// nothing here runs until the documents are in hand and the chunk has been
// rendered in full.
'use strict';

const fs = require('fs');
const path = require('path');

function writeVerdict(target, text) {
    const dir = path.dirname(target);
    // The Data directory belongs to the addon; creating it is fine, creating
    // the AddOns folder is not - that would mean the addon is not installed.
    const addonDir = path.dirname(dir);
    if (!fs.existsSync(addonDir)) {
        throw new Error(`the addon is not installed at ${addonDir} (run .\\tools\\sync.ps1 first)`);
    }
    fs.mkdirSync(dir, { recursive: true });
    const temp = path.join(dir, `.QEVerdict.lua.${process.pid}.tmp`);
    fs.writeFileSync(temp, text, 'utf8');
    try {
        fs.renameSync(temp, target);
    } catch (e) {
        fs.rmSync(temp, { force: true });
        throw e;
    }
    return { bytes: Buffer.byteLength(text, 'utf8'), target, temp };
}

module.exports = { writeVerdict };
