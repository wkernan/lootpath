// Writes tools/engine/out/EngineWeights.dev.lua in E-0c's file shape
// (`Data/EngineWeights.lua`, WKE-672) from the structure run's fits.
//
// DEV ONLY. The file is gitignored, `.pkgmeta` ignores all of `tools/`, and
// the header says so; it exists so a LOCAL install can be pointed at weights
// fitted to QE Live's own exports for one compare run (README).
'use strict';

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
        else if (code < 0x20 || code === 0x7f) out += '\\' + String(code).padStart(3, '0');
        else out += ch;
    }
    return out + '"';
}

const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;
const LUA_KEYWORDS = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);

// A JS object's keys are strings and stay strings (`bands = { ["10"] = ... }`);
// a Map is how a numeric key is written (`specs = { [105] = ... }`).
function luaKey(k) {
    if (typeof k === 'number') return `[${k}]`;
    if (IDENT.test(k) && !LUA_KEYWORDS.has(k)) return k;
    return `[${luaString(k)}]`;
}

function luaValue(v, indent) {
    const pad = '    '.repeat(indent);
    if (v === null || v === undefined) return 'nil';
    if (typeof v === 'boolean') return v ? 'true' : 'false';
    if (typeof v === 'number') {
        if (!Number.isFinite(v)) throw new Error(`refusing to write a non-finite number: ${v}`);
        return String(v);
    }
    if (typeof v === 'string') return luaString(v);
    if (Array.isArray(v)) {
        if (!v.length) return '{}';
        return `{\n${v.map((x) => `${pad}    ${luaValue(x, indent + 1)},`).join('\n')}\n${pad}}`;
    }
    const entries = (v instanceof Map ? [...v.entries()] : Object.entries(v)).filter(([, x]) => x !== undefined && x !== null);
    if (!entries.length) return '{}';
    return `{\n${entries.map(([k, x]) => `${pad}    ${luaKey(k)} = ${luaValue(x, indent + 1)},`).join('\n')}\n${pad}}`;
}

// bandKey(fit) -> the key inside `bands` (a key level for Dungeon, the raid
// difficulty list for Raid). When two documents share a band, the later
// `exportedAt` wins and the other is listed under `superseded`.
function buildTable(fits, meta) {
    const resto = {};
    const superseded = [];
    const sorted = fits.slice().sort((a, b) => String(a.fit.exportedAt).localeCompare(String(b.fit.exportedAt)));
    for (const { fit, band } of sorted) {
        const ct = (resto[fit.contentType] = resto[fit.contentType] || { bands: {} });
        if (ct.bands[band]) superseded.push(ct.bands[band].fittedTo);
        ct.bands[band] = {
            baseValue: fit.baseValue,
            weights: { ...fit.weights },
            assumedFinish: meta.assumedFinish || {},
            assumedBuffs: meta.assumedBuffs || {},
            fittedTo: fit.document,
            r2: fit.overall.r2,
            mae: fit.overall.mae,
        };
    }
    return {
        schema: 'lootpath-engine-weights',
        version: 1,
        method: 'fit-to-qe-exports',
        devOnly: true,
        patch: meta.patch,
        derivedAt: meta.derivedAt,
        fittedTo: meta.documents,
        superseded,
        specs: new Map([[105, resto]]),
        dr: meta.dr,
        tiers: meta.tiers,
    };
}

function render(table, meta) {
    const docs = meta.documents.map((d) => `--   ${d.file}  sha256 ${d.sha256}`).join('\n');
    return [
        '-- DEV ONLY - never ship.',
        '--',
        '-- Written by tools/engine/fit-weights.js (E-0e, WKE-674): weights FITTED to',
        "-- QE Live's own Upgrade Finder exports, the structure run. A diagnostic, not a",
        '-- shipping file: it is gitignored, .pkgmeta never packages tools/, and it is',
        '-- copied over Data/EngineWeights.lua only in a LOCAL install for one compare',
        '-- run (tools/engine/README.md). Regenerate it; never edit it.',
        '--',
        '-- Fitted to:',
        docs,
        '',
        'local _, ns = ...',
        '',
        `ns.engineWeights = ${luaValue(table, 0)}`,
        '',
    ].join('\n');
}

module.exports = { luaString, luaValue, buildTable, render };
