// One JSON file next to the script decides where the game and the fork live.
// The defaults are the owner's machine; nothing here is discovered from the
// environment except the account folder, which is found by glob at run time so
// no account identifier is ever written into this repo.
'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULTS = {
    wowPath: 'C:\\World of Warcraft\\_retail_',
    forkPath: 'c:\\Code\\qe-live-fork',
    forkUrl: 'http://localhost:3000',
    // Which QE Live documents to produce, in the order they are run. Content
    // types are QE Live's own strings (Dungeon / Raid); it has no "Mythic+".
    documents: [
        { kind: 'topgear', contentType: 'Dungeon' },
        { kind: 'upgradefinder', contentType: 'Dungeon' },
        { kind: 'topgear', contentType: 'Raid' },
        { kind: 'upgradefinder', contentType: 'Raid' },
    ],
    includeBank: true,
    // Start `npm start` in forkPath when nothing answers forkUrl.
    startFork: true,
    // Show the browser. Useful once, when a selector stops matching.
    headed: false,
    // Where the browser profile lives, so the welcome dialog is answered once.
    stateDir: '.state',
    // Seconds to wait for a freshly started fork to answer.
    forkStartTimeoutSeconds: 180,
    // Milliseconds of quiet after a SavedVariables write before reading it.
    debounceMs: 1500,
};

const KNOWN = new Set(Object.keys(DEFAULTS));

class ConfigError extends Error {}

function load(file) {
    const config = { ...DEFAULTS };
    let raw = null;
    if (file && fs.existsSync(file)) {
        try {
            raw = JSON.parse(fs.readFileSync(file, 'utf8'));
        } catch (e) {
            throw new ConfigError(`${file} is not valid JSON: ${e.message}`);
        }
    }
    return { ...merge(config, raw || {}), configFile: file && fs.existsSync(file) ? file : null };
}

function merge(config, raw) {
    const warnings = [];
    for (const key of Object.keys(raw)) {
        if (!KNOWN.has(key)) {
            warnings.push(`unknown setting "${key}" ignored`);
            continue;
        }
        const want = typeof DEFAULTS[key];
        const got = Array.isArray(raw[key]) ? 'object' : typeof raw[key];
        if (got !== want) {
            throw new ConfigError(`setting "${key}" should be a ${Array.isArray(DEFAULTS[key]) ? 'list' : want}, not a ${got}`);
        }
        config[key] = raw[key];
    }
    for (const doc of config.documents) {
        if (!doc || (doc.kind !== 'topgear' && doc.kind !== 'upgradefinder')) {
            throw new ConfigError(`each document needs kind "topgear" or "upgradefinder", saw ${JSON.stringify(doc && doc.kind)}`);
        }
        if (doc.contentType !== 'Dungeon' && doc.contentType !== 'Raid') {
            throw new ConfigError(
                `each document needs contentType "Dungeon" or "Raid" (QE Live's own strings; it has no "Mythic+"), saw ${JSON.stringify(doc.contentType)}`
            );
        }
    }
    if (!config.documents.length) throw new ConfigError('documents is empty, so there would be nothing to write');
    config.warnings = warnings;
    return config;
}

// The addon's own file inside the game folder. Nothing else is ever written
// there, and the directory is created only if the addon is installed.
function verdictPath(config) {
    return path.join(config.wowPath, 'Interface', 'AddOns', 'Lootpath', 'Data', 'QEVerdict.lua');
}

// WTF\Account\<ACCOUNT>\SavedVariables\Lootpath.lua, discovered the way
// tools/sync.ps1 discovers it. The newest wins when an install has several
// accounts; the folder name is masked in every log line.
function findSavedVariables(config) {
    const accounts = path.join(config.wowPath, 'WTF', 'Account');
    if (!fs.existsSync(accounts)) return { ok: false, reason: `no WTF\\Account directory under ${config.wowPath}` };
    const found = [];
    for (const entry of fs.readdirSync(accounts, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        const file = path.join(accounts, entry.name, 'SavedVariables', 'Lootpath.lua');
        if (fs.existsSync(file)) found.push({ file, account: entry.name, mtime: fs.statSync(file).mtimeMs });
    }
    if (!found.length) {
        return {
            ok: false,
            reason: `no SavedVariables\\Lootpath.lua under ${accounts} (log in with the addon enabled and /reload once)`,
        };
    }
    found.sort((a, b) => b.mtime - a.mtime);
    return { ok: true, ...found[0], all: found.length };
}

// The account folder name is an identifier; the log never prints it.
function maskAccount(file) {
    return String(file).replace(/([\\/]Account[\\/])[^\\/]+/i, '$1<account>');
}

module.exports = { DEFAULTS, load, verdictPath, findSavedVariables, maskAccount, ConfigError };
