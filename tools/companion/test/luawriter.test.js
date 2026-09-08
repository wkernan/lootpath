// The Lua chunk writer. Its escaper is the whole of the promise that
// Data/QEVerdict.lua is data and never code, so it is tested against every
// byte that could end a string literal early, and the golden it renders is
// committed and loaded by a real Lua interpreter in spec/companionfile_spec.lua.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { render, luaString, luaNumber, luaBoolean } = require('../lib/luawriter');

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
    const settings = { autoUpgradeVault: false, autoUpgradeAll: false };
    assert.throws(() => render({ documents: [], qeSettings: settings }), /no documents/);
    assert.throws(
        () => render({ documents: [{ kind: 'topgear', contentType: 'Dungeon', json: '' }], qeSettings: settings }),
        /no JSON text/
    );
    assert.throws(
        () => render({ documents: [{ kind: 'sideways', contentType: 'Dungeon', json: '{}' }], qeSettings: settings }),
        /unknown document kind/
    );
});

// C-5 (WKE-539). The verdict is only readable next to the settings that
// produced it - a vault option QE Live values at 321 while the client reads the
// same link at 305 is not a contradiction once the file says which question was
// asked - so a file that does not say is not written at all.
test('writes the QE Live import settings the run asked for, as Lua booleans', () => {
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        profileCapturedAt: '2026-09-05T13:33:25',
        qeSettings: { autoUpgradeVault: true, autoUpgradeAll: false },
        documents: [{ kind: 'topgear', contentType: 'Dungeon', json: '{}' }],
    });
    assert.ok(
        text.includes(
            ['    qeSettings = {', '        autoUpgradeVault = true,', '        autoUpgradeAll = false,', '    },', ''].join('\n')
        ),
        text
    );
    // Next to writtenAt, ahead of the exports, so the setting is readable
    // before the 120 KB of JSON rather than after it.
    assert.ok(text.indexOf('qeSettings = {') > text.indexOf('writtenAt = '));
    assert.ok(text.indexOf('qeSettings = {') < text.indexOf('exports = {'));
});

test('refuses to write a verdict that does not say which settings produced it', () => {
    const payload = {
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        documents: [{ kind: 'topgear', contentType: 'Dungeon', json: '{}' }],
    };
    assert.throws(() => render(payload), /which QE Live import settings/);
    assert.throws(() => render({ ...payload, qeSettings: { autoUpgradeVault: false } }), /autoUpgradeAll must be a boolean/);
    assert.throws(
        () => render({ ...payload, qeSettings: { autoUpgradeVault: 'false', autoUpgradeAll: false } }),
        /autoUpgradeVault must be a boolean/
    );
    // "false" the string would be truthy in Lua, which is exactly the mistake
    // a boolean check has to catch.
    assert.strictEqual(luaBoolean(false), 'false');
    assert.throws(() => luaBoolean('false'), /non-boolean/);
    assert.throws(() => luaBoolean(0), /non-boolean/);
});

test('the chunk declares one table and calls nothing', () => {
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        profileCapturedAt: '2026-09-05T13:33:25',
        qeSettings: { autoUpgradeVault: false, autoUpgradeAll: false },
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
        qeSettings: { autoUpgradeVault: false, autoUpgradeAll: false },
        documents: [
            { kind: 'topgear', contentType: 'Dungeon', json: '{"schema":"qe-live-droptimizer","version":1}' },
            // C-7 (WKE-543): an Upgrade Finder document says which Mythic+ key
            // level QE Live ran it at, and spec/companionfile_spec.lua loads
            // this golden in a real Lua interpreter to prove the number comes
            // back as a number.
            { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 10, json: '{"schema":"qe-live-upgradefinder","version":1}' },
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
