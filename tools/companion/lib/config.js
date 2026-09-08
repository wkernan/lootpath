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
    // Which Mythic+ key levels the Upgrade Finder is asked about (WKE-543,
    // C-7). The owner's question is "which dungeon at the LOWEST key level
    // still gives me an upgrade", and QE Live can only answer it one key at a
    // time: his Upgrade Finder values every dungeon drop at the single key his
    // `ufSettings.dungeon` names. So the companion asks him once per level and
    // the addon files each answer under the level it was asked at.
    //
    // These are KEY LEVELS, the numbers a player says out loud. They are not
    // `ufSettings.dungeon`, which is an INDEX into his MPLUS_KEY_REWARDS table
    // (index 7 is the "+10" button, and its rows come back at 311/321/334).
    // The companion never restates that table: it reads the labels off his own
    // selector ("M0", "+2/3", "+10"), clicks the button whose label covers the
    // wanted level, and then checks the export's `settings.dungeon` against the
    // position of the button it clicked. A level his page does not offer is a
    // named failure, never a silent nearest match.
    //
    // The default spread stops at 10 because that is the top of his table on
    // the branch this drives (MPLUS_KEY_REWARDS ends at "+10"); 10 is in it
    // because 10 is the level the journal walk previews.
    upgradeFinderKeyLevels: [2, 4, 6, 8, 10],
    includeBank: true,
    // QE Live's own import checkboxes (SimCraftDialog.js lines 122-133), asked
    // for explicitly on every run rather than inherited (WKE-539, C-5).
    //
    // His dialog defaults are `autoUpgradeVault = true`, `autoUpgradeAll =
    // false` (lines 36-37), which values a VAULT option at the top of its
    // upgrade track and OWNED gear at the level the client reports. That
    // asymmetry is what told the owner on 2026-09-08 to take a 305 copy of a
    // weapon they already wear at 308: QE Live had valued the vault copy at
    // 321 (docs/ARCHITECTURE.md §9).
    //
    // Both off is one consistent question - "what is best from what I have, at
    // the levels the client reports". Both ON is the other consistent question,
    // "what is best if I upgraded everything to the top of its track". Mixing
    // them asks a question with no answer in the world, and that is the pair
    // the companion refuses to inherit silently.
    //
    // The two are not independent in his engine: `processItem` reads
    // `if (autoUpgradeAll) ... else if (type === "Vault" && autoUpgradeVault)`
    // (SimCImportEngine.ts lines 672-679), so `autoUpgradeAll` already covers
    // vault options and the vault box only decides anything while it is off.
    // Both are still set explicitly, because what is asked for should not
    // depend on reading the precedence right.
    qeAutoUpgradeVault: false,
    qeAutoUpgradeAll: false,
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
    config.upgradeFinderKeyLevels = normaliseKeyLevels(config.upgradeFinderKeyLevels);
    config.warnings = warnings;
    return config;
}

// Sorted ascending and deduplicated, so `[10, 2, 2]` and `[2, 10]` are the same
// question rather than two fingerprints - and so the last dungeon run of a plan
// is always the highest key, which is the one the Raid document inherits.
function normaliseKeyLevels(raw) {
    if (!Array.isArray(raw)) throw new ConfigError(`upgradeFinderKeyLevels should be a list of key levels, not ${JSON.stringify(raw)}`);
    const seen = new Set();
    for (const value of raw) {
        if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
            throw new ConfigError(
                `upgradeFinderKeyLevels holds ${JSON.stringify(value)}; every entry must be a whole key level like 2, 4 or 10`
            );
        }
        seen.add(value);
    }
    if (!seen.size) {
        throw new ConfigError('upgradeFinderKeyLevels is empty, so the Upgrade Finder would never be run for a dungeon');
    }
    return [...seen].sort((a, b) => a - b);
}

// The documents one run actually produces, in order. A dungeon Upgrade Finder
// document is asked once per configured key level, because his engine values
// dungeon drops at exactly one key; everything else is asked once.
//
// A NON-dungeon Upgrade Finder document is asked once, at the HIGHEST
// configured level, and records it. WKE-543 proposed recording nothing there,
// but a Raid export is not free of the key selector: measured on the committed
// 2026-09-07 pair, the Raid Upgrade Finder export carries the same 201
// dungeon-sourced rows as the Dungeon one, every one of them stamped
// `dropDifficulty: 7` at 311/321/334 - the levels key index 7 gives. A document
// whose rows were valued at a key is filed under that key, whichever content
// type QE Live was set to when it was asked.
function plannedDocuments(config) {
    const levels = config.upgradeFinderKeyLevels;
    const plan = [];
    for (const doc of config.documents) {
        if (doc.kind !== 'upgradefinder') {
            plan.push({ kind: doc.kind, contentType: doc.contentType });
        } else if (doc.contentType === 'Dungeon') {
            for (const keyLevel of levels) plan.push({ kind: doc.kind, contentType: doc.contentType, keyLevel });
        } else {
            plan.push({ kind: doc.kind, contentType: doc.contentType, keyLevel: levels[levels.length - 1] });
        }
    }
    return plan;
}

// The addon's own file inside the game folder. Nothing else is ever written
// there, and the directory is created only if the addon is installed.
// The pair the fork driver sets and the verdict file records, in one place so
// no caller has to remember which QE Live name goes with which config key.
function qeSettings(config) {
    return { autoUpgradeVault: !!config.qeAutoUpgradeVault, autoUpgradeAll: !!config.qeAutoUpgradeAll };
}

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

module.exports = { DEFAULTS, load, plannedDocuments, qeSettings, verdictPath, findSavedVariables, maskAccount, ConfigError };
