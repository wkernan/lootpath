// Watching Lootpath.lua.
//
// The client rewrites SavedVariables in one go on /reload or logout, and it
// replaces the file rather than truncating it, so the watch is on the DIRECTORY
// (a watch on the file itself would follow the old inode into nothing).
// A run is triggered once the file has stopped changing for `debounceMs` AND
// two stats a debounce apart agree on its size, which is what stops a run from
// reading a file the client is still writing.
'use strict';

const fs = require('fs');
const path = require('path');

function watch(file, options, onChange) {
    const opts = options || {};
    const debounceMs = opts.debounceMs || 1500;
    const dir = path.dirname(file);
    const base = path.basename(file).toLowerCase();
    let timer = null;
    let lastSize = -1;
    let running = false;
    let again = false;

    const settle = () => {
        timer = null;
        let size = -1;
        try {
            size = fs.statSync(file).size;
        } catch {
            return;
        }
        if (size !== lastSize) {
            lastSize = size;
            timer = setTimeout(settle, debounceMs);
            return;
        }
        if (running) {
            again = true;
            return;
        }
        running = true;
        Promise.resolve(onChange())
            .catch(() => {})
            .then(() => {
                running = false;
                if (again) {
                    again = false;
                    lastSize = -1;
                    timer = setTimeout(settle, debounceMs);
                }
            });
    };

    const watcher = fs.watch(dir, { persistent: true }, (_event, name) => {
        if (name && String(name).toLowerCase() !== base) return;
        lastSize = -1;
        if (timer) clearTimeout(timer);
        timer = setTimeout(settle, debounceMs);
    });

    return {
        close() {
            if (timer) clearTimeout(timer);
            watcher.close();
        },
    };
}

module.exports = { watch };
