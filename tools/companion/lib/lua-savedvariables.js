// Reads a WoW SavedVariables file (the subset Blizzard's serialiser writes) into
// plain JavaScript values. Used by the companion spike (WKE-532) to turn
// `WTF\Account\<account>\SavedVariables\Lootpath.lua` into the data the SimC
// profile builder needs.
//
// This is deliberately a strict parser, not a Lua interpreter: it accepts exactly
// what the client writes - `Name = { ... }` assignments of nested table
// constructors whose entries are `["key"] = value`, `[number] = value` or a bare
// positional value - and throws on anything else, naming the line. A silent
// mis-parse of a transcript would be a fabricated measurement.
//
// Lua tables are 1-based and may be sparse, so every table becomes a JS object
// with string keys plus a hidden `arrayLength` helper. Call `luaArray(t)` to get
// the 1..n dense prefix as a JS array, which is what the capture format uses for
// `ns.Probe` packs and for lists.

"use strict";

const ESCAPES = {
  a: "\x07",
  b: "\b",
  f: "\f",
  n: "\n",
  r: "\r",
  t: "\t",
  v: "\v",
  "\\": "\\",
  '"': '"',
  "'": "'",
  "\n": "\n",
};

class LuaParseError extends Error {
  constructor(message, source, index) {
    const line = source.slice(0, index).split("\n").length;
    super(`${message} (line ${line})`);
    this.name = "LuaParseError";
    this.line = line;
  }
}

function parseSavedVariables(text) {
  const state = { text, i: 0 };
  const out = {};
  skipSpace(state);
  while (state.i < state.text.length) {
    const name = readName(state);
    skipSpace(state);
    expect(state, "=");
    skipSpace(state);
    out[name] = readValue(state);
    skipSpace(state);
  }
  return out;
}

function skipSpace(state) {
  const { text } = state;
  for (;;) {
    while (state.i < text.length && /\s/.test(text[state.i])) state.i += 1;
    if (text.startsWith("--", state.i)) {
      while (state.i < text.length && text[state.i] !== "\n") state.i += 1;
      continue;
    }
    return;
  }
}

function expect(state, char) {
  if (state.text[state.i] !== char) {
    throw new LuaParseError(`expected ${JSON.stringify(char)} but saw ${JSON.stringify(state.text[state.i])}`, state.text, state.i);
  }
  state.i += 1;
}

function readName(state) {
  const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(state.text.slice(state.i));
  if (!match) throw new LuaParseError("expected a global name", state.text, state.i);
  state.i += match[0].length;
  return match[0];
}

function readString(state) {
  const quote = state.text[state.i];
  state.i += 1;
  let out = "";
  for (;;) {
    if (state.i >= state.text.length) throw new LuaParseError("unterminated string", state.text, state.i);
    const c = state.text[state.i];
    if (c === quote) {
      state.i += 1;
      return out;
    }
    if (c === "\\") {
      state.i += 1;
      const e = state.text[state.i];
      const digits = /^\d{1,3}/.exec(state.text.slice(state.i));
      if (digits) {
        out += String.fromCharCode(parseInt(digits[0], 10));
        state.i += digits[0].length;
        continue;
      }
      if (!(e in ESCAPES)) throw new LuaParseError(`unknown string escape \\${e}`, state.text, state.i);
      out += ESCAPES[e];
      state.i += 1;
      continue;
    }
    out += c;
    state.i += 1;
  }
}

function readValue(state) {
  const { text } = state;
  const c = text[state.i];
  if (c === "{") return readTable(state);
  if (c === '"' || c === "'") return readString(state);
  if (text.startsWith("true", state.i)) {
    state.i += 4;
    return true;
  }
  if (text.startsWith("false", state.i)) {
    state.i += 5;
    return false;
  }
  if (text.startsWith("nil", state.i)) {
    state.i += 3;
    return null;
  }
  const number = /^-?(?:0x[0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/.exec(text.slice(state.i));
  if (number) {
    state.i += number[0].length;
    return Number(number[0]);
  }
  // The serialiser writes inf/nan unquoted for out-of-range doubles. Accept them
  // rather than silently mis-parsing the rest of the file.
  const word = /^-?(?:inf|nan|1\.#INF|-1\.#IND)/.exec(text.slice(state.i));
  if (word) {
    state.i += word[0].length;
    return word[0].startsWith("-") ? -Infinity : Infinity;
  }
  throw new LuaParseError("expected a value", text, state.i);
}

function readTable(state) {
  expect(state, "{");
  const table = Object.create(null);
  let nextIndex = 1;
  skipSpace(state);
  while (state.text[state.i] !== "}") {
    if (state.i >= state.text.length) throw new LuaParseError("unterminated table", state.text, state.i);
    let key = null;
    if (state.text[state.i] === "[") {
      state.i += 1;
      skipSpace(state);
      const rawKey = readValue(state);
      if (typeof rawKey !== "string" && typeof rawKey !== "number") {
        throw new LuaParseError("table key must be a string or a number", state.text, state.i);
      }
      key = String(rawKey);
      skipSpace(state);
      expect(state, "]");
      skipSpace(state);
      expect(state, "=");
      skipSpace(state);
    }
    const value = readValue(state);
    if (key === null) {
      table[String(nextIndex)] = value;
      nextIndex += 1;
    } else {
      table[key] = value;
    }
    skipSpace(state);
    if (state.text[state.i] === "," || state.text[state.i] === ";") {
      state.i += 1;
      skipSpace(state);
    }
  }
  expect(state, "}");
  return table;
}

// The dense 1..n prefix of a Lua table, as a JS array. Everything the capture
// format calls a list is written this way.
function luaArray(table) {
  const out = [];
  if (!table) return out;
  for (let i = 1; ; i += 1) {
    const value = table[String(i)];
    if (value === undefined) return out;
    out.push(value);
  }
}

module.exports = { parseSavedVariables, luaArray, LuaParseError };
