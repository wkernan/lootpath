// The Lua chunk writer. Its escaper is the whole of the promise that
// Data/QEVerdict.lua is data and never code, so it is tested against every
// byte that could end a string literal early, and the golden it renders is
// committed and loaded by a real Lua interpreter in spec/companionfile_spec.lua.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { render, luaString, luaNumber } = require('../lib/luawriter');

const GOLDEN = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'expected', 'qeverdict-sample.lua');

// Everything that could break out of a Lua string literal, plus a chunk of Lua
// source pretending to be a QE Live export. Kept identical to the expectation
// in spec/companionfile_spec.lua, which loads the golden this renders.
const HOSTILE =
    'quote " backslash \\ close ]] and ]==] newline \n return \r tab \t nul \u0000 del \u007f accented \u00e9 ' +
    'lua os.execute("calc") end return {} --[[';

test('escapes every byte that could end the literal early', () => {
    assert.strictEqual(luaString('a"b'), '"a\\"b"');
    assert.strictEqual(luaString('a\\b'), '"a\\\\b"');
    assert.strictEqual(luaString('a\nb'), '"a\\nb"');
    assert.strictEqual(luaString('a\rb'), '"a\\rb"');
    assert.strictEqual(luaString('a\tb'), '"a\\tb"');
    assert.strictEqual(luaString('a\u0000b'), '"a\\000b"');
    assert.strictEqual(luaString('a\u0001b'), '"a\\001b"');
    assert.strictEqual(luaString('a\u007fb'), '"a\\127b"');
});

test('leaves "]]" alone, because a quoted literal has no bracket to close', () => {
    assert.strictEqual(luaString(']]'), '"]]"');
});

test('carries UTF-8 through untouched rather than tripling the file', () => {
    assert.strictEqual(luaString('caf\u00e9'), '"caf\u00e9"');
});

test('refuses a number the client could not read back', () => {
    assert.strictEqual(luaNumber(16174), '16174');
    assert.throws(() => luaNumber(Infinity), /non-finite/);
    assert.throws(() => luaNumber(NaN), /non-finite/);
});

test('refuses to render nothing, so a failed run never blanks a good verdict', () => {
    assert.throws(() => render({ documents: [] }), /no documents/);
    assert.throws(() => render({ documents: [{ kind: 'topgear', contentType: 'Dungeon', json: '' }] }), /no JSON text/);
    assert.throws(() => render({ documents: [{ kind: 'sideways', contentType: 'Dungeon', json: '{}' }] }), /unknown document kind/);
});

test('the chunk declares one table and calls nothing', () => {
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        profileCapturedAt: '2026-09-05T13:33:25',
        documents: [{ kind: 'topgear', contentType: 'Dungeon', json: '{"schema":"qe-live-droptimizer"}' }],
    });
    const code = text
        .split('\n')
        .filter((l) => !l.trim().startsWith('--'))
        .join('\n');
    // Nothing that could run: no call syntax, no loop, no function.
    assert.ok(!/\bfunction\b|\bfor\b|\bwhile\b|\bloadstring\b|\brequire\b/.test(code), code);
    // The only parentheses are the vararg guard's type() check.
    assert.deepStrictEqual(code.match(/[a-zA-Z_.]+\(/g), ['type(']);
    assert.ok(code.includes('ns.companionVerdict = {'));
});

test('renders the committed golden byte for byte', () => {
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        profileCapturedAt: '2026-09-05T13:33:25',
        documents: [
            { kind: 'topgear', contentType: 'Dungeon', json: '{"schema":"qe-live-droptimizer","version":1}' },
            { kind: 'upgradefinder', contentType: 'Raid', json: HOSTILE },
        ],
    });
    if (process.env.UPDATE_GOLDEN) fs.writeFileSync(GOLDEN, text);
    assert.strictEqual(
        text,
        fs.readFileSync(GOLDEN, 'utf8'),
        'spec/fixtures/expected/qeverdict-sample.lua is out of date; re-run with UPDATE_GOLDEN=1 and check spec/companionfile_spec.lua still passes'
    );
});
