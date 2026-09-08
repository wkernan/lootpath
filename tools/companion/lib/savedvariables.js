// The client's SavedVariables writer emits a strict subset of Lua: a sequence
// of `NAME = <value>` assignments where every value is a table constructor, a
// quoted string, a number, or a boolean. Keys are always bracketed
// (`["global"]`, `[3]`) or absent for array parts. Nils are never written.
//
// Parsing that subset is a hundred lines and keeps the companion free of a Lua
// runtime; the shapes below were read from the committed transcripts under
// spec/fixtures/captures/, never guessed. Anything outside the subset - a
// function call, an operator, a long string - is a parse error naming the line
// and column, because a silent partial parse would hand the profile builder a
// half-read character.
'use strict';

const IDENT = /[A-Za-z_][A-Za-z0-9_]*/y;
const NUMBER = /-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/y;

class LuaParseError extends Error {}

function parse(text) {
    const state = { text, i: 0 };
    const out = {};
    skipTrivia(state);
    while (state.i < text.length) {
        const name = readIdent(state, 'a variable name');
        skipTrivia(state);
        expect(state, '=');
        out[name] = readValue(state);
        skipTrivia(state);
        // The writer ends each assignment with a newline, but a stray `;` is
        // valid Lua and costs one line to accept.
        if (state.text[state.i] === ';') {
            state.i++;
            skipTrivia(state);
        }
    }
    return out;
}

function fail(state, message) {
    const upto = state.text.slice(0, state.i);
    const line = upto.split('\n').length;
    const col = state.i - (upto.lastIndexOf('\n') + 1) + 1;
    throw new LuaParseError(`${message} at line ${line}, column ${col}`);
}

function skipTrivia(state) {
    const { text } = state;
    for (;;) {
        while (state.i < text.length && /\s/.test(text[state.i])) state.i++;
        if (text.startsWith('--', state.i)) {
            const nl = text.indexOf('\n', state.i);
            state.i = nl === -1 ? text.length : nl + 1;
            continue;
        }
        return;
    }
}

function expect(state, ch) {
    if (state.text[state.i] !== ch) fail(state, `expected ${JSON.stringify(ch)}`);
    state.i++;
}

function readIdent(state, what) {
    IDENT.lastIndex = state.i;
    const m = IDENT.exec(state.text);
    if (!m) fail(state, `expected ${what}`);
    state.i = IDENT.lastIndex;
    return m[0];
}

// Escapes the client writes: backslash, quote, \n, \r, \t and the decimal \ddd
// form. An
// unknown escape keeps the character, which is what Lua 5.1 itself does.
function readString(state) {
    const quote = state.text[state.i];
    state.i++;
    let out = '';
    for (;;) {
        if (state.i >= state.text.length) fail(state, 'unterminated string');
        const ch = state.text[state.i];
        if (ch === quote) {
            state.i++;
            return out;
        }
        if (ch !== '\\') {
            out += ch;
            state.i++;
            continue;
        }
        state.i++;
        const esc = state.text[state.i];
        if (esc >= '0' && esc <= '9') {
            let digits = '';
            while (digits.length < 3 && state.text[state.i] >= '0' && state.text[state.i] <= '9') {
                digits += state.text[state.i];
                state.i++;
            }
            out += String.fromCharCode(parseInt(digits, 10));
            continue;
        }
        state.i++;
        if (esc === 'n') out += '\n';
        else if (esc === 'r') out += '\r';
        else if (esc === 't') out += '\t';
        else if (esc === 'a') out += '\x07';
        else if (esc === 'b') out += '\b';
        else if (esc === 'f') out += '\f';
        else if (esc === 'v') out += '\v';
        else out += esc;
    }
}

function readValue(state) {
    skipTrivia(state);
    const ch = state.text[state.i];
    if (ch === '"' || ch === "'") return readString(state);
    if (ch === '{') return readTable(state);
    if (ch === '-' || (ch >= '0' && ch <= '9') || ch === '.') {
        NUMBER.lastIndex = state.i;
        const m = NUMBER.exec(state.text);
        if (!m) fail(state, 'expected a number');
        state.i = NUMBER.lastIndex;
        return Number(m[0]);
    }
    IDENT.lastIndex = state.i;
    const word = IDENT.exec(state.text);
    if (word) {
        state.i = IDENT.lastIndex;
        if (word[0] === 'true') return true;
        if (word[0] === 'false') return false;
        if (word[0] === 'nil') return null;
        // `inf` and `nan` are what tostring gives for those numbers; the client
        // has never written one, so seeing one is worth a loud failure.
        fail(state, `unexpected word ${JSON.stringify(word[0])}`);
    }
    return fail(state, 'expected a value');
}

// Tables come back as plain objects with the array part on numeric keys
// (`{ 1: "Arthas", n: 1 }` for a Probe pack), because a Lua table is neither an
// array nor a map and the transcripts mix both in one table.
function readTable(state) {
    expect(state, '{');
    const out = {};
    let arrayIndex = 1;
    for (;;) {
        skipTrivia(state);
        if (state.text[state.i] === '}') {
            state.i++;
            return out;
        }
        let key = null;
        if (state.text[state.i] === '[') {
            state.i++;
            const k = readValue(state);
            skipTrivia(state);
            expect(state, ']');
            skipTrivia(state);
            expect(state, '=');
            key = k;
        } else {
            // `name = value` is legal Lua the client does not write; accepted so
            // a hand-written fixture parses too.
            const save = state.i;
            IDENT.lastIndex = state.i;
            const m = IDENT.exec(state.text);
            if (m) {
                const after = state.i;
                state.i = IDENT.lastIndex;
                skipTrivia(state);
                if (state.text[state.i] === '=' && state.text[state.i + 1] !== '=') {
                    state.i++;
                    key = m[0];
                } else {
                    state.i = save === after ? save : save;
                }
            }
        }
        const value = readValue(state);
        if (key === null) {
            out[arrayIndex] = value;
            arrayIndex++;
        } else if (value !== null) {
            out[key] = value;
        }
        skipTrivia(state);
        const sep = state.text[state.i];
        if (sep === ',' || sep === ';') {
            state.i++;
            continue;
        }
        if (sep === '}') continue;
        fail(state, 'expected "," or "}"');
    }
}

// A Probe pack is `{ value, n = 1 }` (ns.Probe, Core.lua), `{ absent = true }`
// or `{ error = "..." }`. First() is the one reader for all three.
function first(pack) {
    if (pack === null || typeof pack !== 'object') return undefined;
    return pack[1];
}

module.exports = { parse, first, LuaParseError };
