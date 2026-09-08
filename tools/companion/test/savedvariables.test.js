// The SavedVariables reader, over hand-written Lua and over the committed
// transcripts. The transcripts are the authority: if the client ever writes
// something this parser cannot read, these tests are where it shows.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { parse, first, LuaParseError } = require('../lib/savedvariables');

const CAPTURES = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'captures');
const TRANSCRIPT = path.join(CAPTURES, 'Lootpath-20260906-200908.lua');

test('reads a table with string keys, an array part and nested tables', () => {
    const db = parse('X = {\n["a"] = "one",\n["b"] = { 1, 2, ["n"] = 2 },\n["c"] = true,\n}\n');
    assert.deepStrictEqual(db.X, { a: 'one', b: { 1: 1, 2: 2, n: 2 }, c: true });
});

test('reads every escape the client writes', () => {
    const db = parse('X = { ["s"] = "a\\"b\\\\c\\nd\\re\\tf\\009g" }');
    assert.strictEqual(db.X.s, 'a"b\\c\nd\re\tf\tg');
});

test('reads numbers the way the client writes them', () => {
    const db = parse('X = { 1788633193, 27.30429999995977, -3, 1e3, 0.5 }');
    assert.deepStrictEqual(db.X, { 1: 1788633193, 2: 27.30429999995977, 3: -3, 4: 1000, 5: 0.5 });
});

test('drops nil values rather than carrying a null into the profile', () => {
    const db = parse('X = { ["a"] = nil, ["b"] = 1 }');
    assert.deepStrictEqual(db.X, { b: 1 });
});

test('refuses anything outside the subset instead of half-parsing it', () => {
    assert.throws(() => parse('X = { ["a"] = someCall() }'), LuaParseError);
    assert.throws(() => parse('X = { ["a"] = "unterminated }'), LuaParseError);
    assert.throws(() => parse('X = { ["a"] 1 }'), LuaParseError);
});

test('names what it wanted, and the line and column, on a parse failure', () => {
    // The message matters as much as the throw: a parser that gave up on the
    // value and then complained about the comma would send whoever reads the
    // log to the wrong character.
    assert.throws(() => parse('X = {\n["a"] = 1,\n["b"] = @\n}'), /^Error: expected a value at line 3, column 9$/);
    assert.throws(() => parse('X = {\n["a"] = 1\n["b"] = 2\n}'), /^Error: expected "," or "}" at line 3, column 1$/);
});

test('First() reads a Probe pack, an absent pack and a plain value', () => {
    assert.strictEqual(first({ 1: 'Arthas', n: 1 }), 'Arthas');
    assert.strictEqual(first({ absent: true }), undefined);
    assert.strictEqual(first(null), undefined);
    assert.strictEqual(first('not a pack'), undefined);
});

test('reads the committed 1.9 MB transcript and finds every capture', () => {
    const db = parse(fs.readFileSync(TRANSCRIPT, 'utf8'));
    const captures = db.LootpathDB.global.captures;
    assert.deepStrictEqual(Object.keys(captures).sort(), ['env', 'inventory', 'journal', 'vault']);
    // Figures read from the transcript itself, not from memory.
    assert.strictEqual(Object.keys(captures.inventory).length, 2);
    assert.strictEqual(Object.keys(captures.vault).length, 4);
    assert.strictEqual(Object.keys(captures.journal).length, 3);
    const env = captures.env[1];
    assert.strictEqual(first(env.data.player), 'Hotornot');
    assert.strictEqual(first(env.data.realm), 'Arthas');
    assert.strictEqual(env.data.class[2], 'DRUID');
    assert.strictEqual(env.data.build[4], 120100);
});

test('reads the other two committed transcripts too', () => {
    for (const name of ['Lootpath-20260905-133449.lua', 'Lootpath-20260906-161213.lua']) {
        const db = parse(fs.readFileSync(path.join(CAPTURES, name), 'utf8'));
        assert.ok(db.LootpathDB.global.captures.inventory, `${name} has an inventory capture`);
    }
});
