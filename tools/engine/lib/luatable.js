// Reads one Lua table constructor out of a source file (E-3c, WKE-686): the
// table `ns.engineEffects = { ... }` in Lootpath/Data/EngineEffects.lua, or
// the `return { ... }` of a spec fixture. DEV ONLY.
//
// Not a Lua interpreter. The table is handed to the strict SavedVariables
// reader (tools/companion/lib/lua-savedvariables.js) after one rewrite: a bare
// key (`name = `) becomes `["name"] = `, the only constructor form those files
// use that the client's serialiser never writes. Strings and comments are
// copied through untouched, so a key-like run inside a string is never
// rewritten; anything else the reader does not accept still throws.
'use strict';

const { parseSavedVariables } = require('../../companion/lib/lua-savedvariables');

function bracketBareKeys(src) {
    let out = '';
    let i = 0;
    // The last character that is neither space nor comment: a bare key only
    // ever follows `{`, `,` or `;`.
    let prev = '';
    while (i < src.length) {
        const c = src[i];
        if (c === '"' || c === "'") {
            let j = i + 1;
            while (j < src.length && src[j] !== c) j += src[j] === '\\' ? 2 : 1;
            out += src.slice(i, j + 1);
            i = j + 1;
            prev = c;
            continue;
        }
        if (src.startsWith('--', i)) {
            const j = src.indexOf('\n', i);
            const end = j < 0 ? src.length : j;
            out += src.slice(i, end);
            i = end;
            continue;
        }
        const m = /^[A-Za-z_][A-Za-z0-9_]*(?=\s*=(?!=))/.exec(src.slice(i));
        if (m && (prev === '{' || prev === ',' || prev === ';')) {
            out += `["${m[0]}"]`;
            i += m[0].length;
            prev = ']';
            continue;
        }
        out += c;
        if (!/\s/.test(c)) prev = c;
        i += 1;
    }
    return out;
}

// The constructor starting at the first `{` after `anchor` (a RegExp), to its
// matching `}`.
function constructorAfter(text, anchor) {
    const m = anchor.exec(text);
    if (!m) throw new Error(`no ${anchor} in the file`);
    let i = text.indexOf('{', m.index + m[0].length);
    if (i < 0) throw new Error(`no table after ${anchor}`);
    const start = i;
    let depth = 0;
    while (i < text.length) {
        const c = text[i];
        if (c === '"' || c === "'") {
            let j = i + 1;
            while (j < text.length && text[j] !== c) j += text[j] === '\\' ? 2 : 1;
            i = j + 1;
            continue;
        }
        if (text.startsWith('--', i)) {
            const j = text.indexOf('\n', i);
            i = j < 0 ? text.length : j;
            continue;
        }
        if (c === '{') depth += 1;
        if (c === '}') {
            depth -= 1;
            if (depth === 0) return text.slice(start, i + 1);
        }
        i += 1;
    }
    throw new Error(`unterminated table after ${anchor}`);
}

function readLuaTable(text, anchor) {
    return parseSavedVariables(`T = ${bracketBareKeys(constructorAfter(text, anchor))}`).T;
}

module.exports = { readLuaTable, bracketBareKeys, constructorAfter };
