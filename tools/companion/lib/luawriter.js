// Writes Data/QEVerdict.lua: the one file the companion puts inside the game
// folder, and the one exception to "everything external arrives by paste"
// (decision 2026-09-07, docs/ARCHITECTURE.md §7).
//
// The chunk is DATA, never code. It declares one local, guards that it really
// was loaded by the addon, and assigns one table of string literals and
// numbers. Nothing else: no function, no loop, no call, no require of anything
// the client would have to resolve. The addon (WKE-534) lists it in the .toc
// and runs each `json` string through the same ns.QEImport.Parse a paste goes
// through, so every schema pin, version pin and refusal still applies - the
// companion is a courier, not a second parser.
//
// The escaper below is the whole security surface of that promise, so it is
// tested against quotes, backslashes, "]]", newlines, carriage returns, NULs,
// other control bytes and a chunk of Lua source pretending to be JSON.
'use strict';

// Lua 5.1 quoted-string escapes. A byte >= 0x80 passes through untouched: the
// client reads addon files as bytes and QE Live's JSON is UTF-8, so escaping
// them would only triple the file for nothing. Everything below 0x20, the
// DEL byte, the quote and the backslash are escaped, which leaves no byte that
// can end the literal early.
function luaString(value) {
    let out = '"';
    const text = String(value);
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        const code = text.charCodeAt(i);
        if (ch === '"') out += '\\"';
        else if (ch === '\\') out += '\\\\';
        else if (ch === '\n') out += '\\n';
        else if (ch === '\r') out += '\\r';
        else if (ch === '\t') out += '\\t';
        else if (code < 0x20 || code === 0x7f) out += '\\' + String(code).padStart(3, '0');
        else out += ch;
    }
    return out + '"';
}

function luaBoolean(value) {
    if (typeof value !== 'boolean') throw new Error(`refusing to write a non-boolean: ${JSON.stringify(value)}`);
    return value ? 'true' : 'false';
}

function luaNumber(value) {
    if (!Number.isFinite(value)) throw new Error(`refusing to write a non-finite number: ${value}`);
    return String(value);
}

// The contract is the ADDON's, not the companion's: `ns.companionVerdict` with
// an `exports` list of `{ schema, contentType, json }`, settled by C-2
// (WKE-534, `Lootpath/Modules/Companion.lua`). `Companion.Entry` dispatches on
// `schema`, treats `contentType` as advisory (the one inside the JSON wins) and
// ignores any field it does not know, so `bytes` rides along as a diagnostic.
const SCHEMA_BY_KIND = {
    topgear: 'qe-live-droptimizer',
    upgradefinder: 'qe-live-upgradefinder',
};
const KINDS = new Set(Object.keys(SCHEMA_BY_KIND));

// documents: [{ kind, contentType, json }] - `json` is QE Live's export text,
// carried verbatim so the addon parses exactly what the browser produced.
// Which of QE Live's own import settings this run asked for (WKE-539, C-5).
// The addon reads nothing here today - `Companion.Entry` ignores a field it
// does not know - but a verdict that says a vault option is worth 321 when the
// client reads it at 305 is only readable next to the setting that produced it,
// so the file carries it.
const QE_SETTING_KEYS = ['autoUpgradeVault', 'autoUpgradeAll'];

// The Mythic+ key level an Upgrade Finder document was run at (WKE-543, C-7),
// written as the number a player says out loud rather than QE Live's
// `settings.dungeon`, which is an index into his own table. The addon files
// each Upgrade Finder verdict under (contentType, keyLevel) and never converts
// one to the other: the level is his page's answer, carried like every other
// number in this file.
//
// A Top Gear document never carries one, and neither does an Upgrade Finder
// document the driver ran without touching the selector.
function keyLevelOf(doc) {
    if (doc.keyLevel === undefined || doc.keyLevel === null) return null;
    if (!Number.isInteger(doc.keyLevel) || doc.keyLevel < 0) {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries keyLevel ${JSON.stringify(doc.keyLevel)}, which is not a whole key level`);
    }
    if (doc.kind !== 'upgradefinder') {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries a keyLevel, and only an Upgrade Finder document is run at a key level`);
    }
    return doc.keyLevel;
}

function render(payload) {
    const { writtenAt, companionVersion, profileCapturedAt, documents, qeSettings } = payload;
    if (!Array.isArray(documents) || !documents.length) {
        throw new Error('refusing to write a verdict file with no documents');
    }
    if (!qeSettings || typeof qeSettings !== 'object') {
        throw new Error('refusing to write a verdict file that does not say which QE Live import settings produced it');
    }
    for (const key of QE_SETTING_KEYS) {
        if (typeof qeSettings[key] !== 'boolean') {
            throw new Error(`qeSettings.${key} must be a boolean, saw ${JSON.stringify(qeSettings[key])}`);
        }
    }
    const lines = [
        '-- Lootpath/Data/QEVerdict.lua - written by the Lootpath companion (tools/companion).',
        '-- Generated data, never edited by hand and never a place to put logic.',
        '-- Every string below is QE Live\'s own export text, carried unchanged; the addon',
        '-- runs each one through ns.QEImport.Parse exactly as it does a paste.',
        `-- Written at ${String(writtenAt).replace(/[^0-9A-Za-z:+.\-T Z]/g, '')}.`,
        'local _, ns = ...',
        'if type(ns) ~= "table" then',
        '    return',
        'end',
        'ns.companionVerdict = {',
        `    writtenAt = ${luaString(writtenAt)},`,
        `    companionVersion = ${luaString(companionVersion)},`,
        `    profileCapturedAt = ${luaString(profileCapturedAt || '')},`,
        '    qeSettings = {',
        ...QE_SETTING_KEYS.map((key) => `        ${key} = ${luaBoolean(qeSettings[key])},`),
        '    },',
        '    exports = {',
    ];
    for (const doc of documents) {
        if (!KINDS.has(doc.kind)) throw new Error(`unknown document kind: ${doc.kind}`);
        if (typeof doc.json !== 'string' || !doc.json.length) {
            throw new Error(`document ${doc.kind}/${doc.contentType} carries no JSON text`);
        }
        const keyLevel = keyLevelOf(doc);
        lines.push('        {', `            schema = ${luaString(SCHEMA_BY_KIND[doc.kind])},`, `            contentType = ${luaString(doc.contentType)},`);
        if (keyLevel !== null) lines.push(`            keyLevel = ${luaNumber(keyLevel)},`);
        lines.push(
            `            bytes = ${luaNumber(Buffer.byteLength(doc.json, 'utf8'))},`,
            `            json = ${luaString(doc.json)},`,
            '        },'
        );
    }
    lines.push('    },', '}', '');
    return lines.join('\n');
}

module.exports = { render, luaString, luaNumber, luaBoolean, keyLevelOf, KINDS, SCHEMA_BY_KIND, QE_SETTING_KEYS };
