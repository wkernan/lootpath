// The Lua chunk writer. Its escaper is the whole of the promise that
// Data/QEVerdict.lua is data and never code, so it is tested against every
// byte that could end a string literal early, and the golden it renders is
// committed and loaded by a real Lua interpreter in spec/companionfile_spec.lua.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const luaWriter = require('../lib/luawriter');
const { render, luaString, luaNumber, luaBoolean } = luaWriter;

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

// Every Top Gear document says which named scenario it answers and which three
// boxes produced it (C-6, WKE-540), so a document built for these tests carries
// both. `asOffered` is the one Equip Now and the Upgrade Map read.
const BOXES = { autoUpgradeVault: false, autoUpgradeAll: false, autoCatalyze: false };
const CATALYZED_BOXES = { autoUpgradeVault: false, autoUpgradeAll: false, autoCatalyze: true };

function topGear(extra) {
    return { kind: 'topgear', contentType: 'Dungeon', scenario: 'asOffered', qeSettings: BOXES, json: '{}', ...extra };
}

test('refuses to render nothing, so a failed run never blanks a good verdict', () => {
    const settings = { autoUpgradeVault: false, autoUpgradeAll: false };
    assert.throws(() => render({ documents: [], qeSettings: settings }), /no documents/);
    assert.throws(() => render({ documents: [topGear({ json: '' })], qeSettings: settings }), /no JSON text/);
    assert.throws(() => render({ documents: [topGear({ kind: 'sideways' })], qeSettings: settings }), /unknown document kind/);
});

// The scenario is the shelf a Top Gear answer is filed on. A document with no
// scenario means `asOffered` in the addon, which is the one reading a
// `catalyzed` answer must never get, so the writer will not leave it out.
test('every Top Gear document must name a scenario, and no other document may', () => {
    const settings = { autoUpgradeVault: false, autoUpgradeAll: false };
    assert.throws(
        () => render({ documents: [topGear({ scenario: undefined })], qeSettings: settings }),
        /carries no scenario/
    );
    assert.throws(
        () => render({ documents: [topGear({ scenario: 'catalysed' })], qeSettings: settings }),
        /not one of asOffered, catalyzed, thisWeek, maxed/
    );
    assert.throws(
        () =>
            render({
                documents: [
                    { kind: 'upgradefinder', contentType: 'Raid', scenario: 'maxed', qeSettings: BOXES, json: '{}' },
                ],
                qeSettings: settings,
            }),
        /only a Top Gear document answers one/
    );
});

// The three boxes are per document, because two documents over the same gear
// disagree exactly because they were asked different questions.
test('every document records the three checkboxes that produced it', () => {
    const settings = { autoUpgradeVault: false, autoUpgradeAll: false };
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: settings,
        documents: [topGear({ scenario: 'catalyzed', qeSettings: CATALYZED_BOXES })],
    });
    assert.ok(
        text.includes(
            [
                '            scenario = "catalyzed",',
                '            qeSettings = {',
                '                autoUpgradeVault = false,',
                '                autoUpgradeAll = false,',
                '                autoCatalyze = true,',
                '            },',
            ].join('\n')
        ),
        text
    );
    assert.throws(
        () => render({ ...{ qeSettings: settings }, documents: [topGear({ qeSettings: undefined })] }),
        /does not say which QE Live import settings produced it/
    );
    assert.throws(
        () => render({ qeSettings: settings, documents: [topGear({ qeSettings: { autoUpgradeVault: false } })] }),
        /does not say what qeSettings.autoUpgradeAll was/
    );
    assert.throws(
        () =>
            render({
                qeSettings: settings,
                documents: [topGear({ qeSettings: { ...BOXES, autoCatalyze: 'true' } })],
            }),
        /qeSettings.autoCatalyze = "true", which is not a boolean/
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
        documents: [topGear()],
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
        documents: [topGear()],
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
        documents: [topGear({ json: '{"schema":"qe-live-droptimizer"}' })],
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

// C-8 (WKE-558). The last entry has no level on purpose: a card whose level
// could not be read is still named rather than dropped or given a number.
//
// C-10 (WKE-567): the first two carry the identity his card carries. The vault
// one has no bonus IDs, which is the bare "<itemID>" key ns.ItemKey builds for
// an item that has none; the last carries no identity at all, which is every
// entry in every file written before C-10, and is what the addon's name+level
// fallback is for.
const EXCLUDED = [
    { slot: 'Finger', name: 'Band of the "Quoted" Name', level: 678, itemID: 228638, bonusIDs: [10390, 42] },
    { slot: 'Shoulder', name: 'Spaulders of the Vault', level: 691, itemID: 271526, bonusIDs: [], vault: true },
    { slot: 'Trinket', name: 'a trinket with no level' },
];

test('C-8: a verdict with no excluded list is written exactly as it was before', () => {
    // Every file written before C-8 carries none, and so does the committed
    // placeholder: the field appears only when there is something to say.
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: BOXES,
        documents: [topGear()],
    });
    assert.ok(!text.includes('excluded'), text);
});

test('C-8: the list is written as data, and a name that could end the literal cannot', () => {
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: BOXES,
        excluded: [{ slot: 'Head', name: 'a "]] end -- name', level: 700 }],
        documents: [topGear()],
    });
    assert.ok(text.includes('excluded = {'));
    assert.ok(text.includes('name = "a \\"]] end -- name"'), text);
    // And it sits beside qeSettings, before the kilobytes of JSON.
    assert.ok(text.indexOf('excluded = {') > text.indexOf('qeSettings = {'));
    assert.ok(text.indexOf('excluded = {') < text.indexOf('exports = {'));
});

test('C-8: only a Top Gear document chooses a pool, so only one may carry a list', () => {
    const payload = {
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: BOXES,
        documents: [{ kind: 'upgradefinder', contentType: 'Dungeon', qeSettings: BOXES, excluded: EXCLUDED, json: '{}' }],
    };
    assert.throws(() => render(payload), /only a Top Gear document chooses a pool/);
});

test('C-8: a list the driver could not have produced is refused rather than written', () => {
    const payload = {
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: BOXES,
        documents: [topGear()],
    };
    assert.throws(() => render({ ...payload, excluded: 'nothing' }), /not an array/);
    assert.throws(() => render({ ...payload, excluded: ['a ring'] }), /not a table/);
    assert.throws(() => render({ ...payload, excluded: [{ name: 'x', level: 'high' }] }), /whose level is/);
});

test('C-10: the identity travels with the name, sorted, and only when there is one', () => {
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: BOXES,
        excluded: [
            { slot: 'Shoulder', name: 'a clone', level: 308, itemID: 271526, bonusIDs: [12, 3, 7], originalItem: 228638, catalyst: true },
            { slot: 'Trinket', name: 'a card that identified nothing' },
        ],
        documents: [topGear()],
    });
    // Sorted, because ns.ItemKey sorts and a key in another order matches
    // nothing; `originalItem` is written because a clone's own ID is a tier
    // piece the character does not own.
    assert.ok(text.includes('itemID = 271526, bonusIDs = { 3, 7, 12 }, originalItem = 228638, catalyst = true'), text);
    // And an entry with no identity says nothing rather than claiming one.
    assert.ok(text.includes('{ slot = "Trinket", name = "a card that identified nothing" },'), text);
});

test('C-10: an identity that is not whole numbers is refused rather than half-written', () => {
    const payload = {
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: BOXES,
        documents: [topGear()],
    };
    const entry = (extra) => ({ ...payload, excluded: [{ slot: 'Finger', name: 'a ring', level: 678, ...extra }] });
    assert.throws(() => render(entry({ itemID: 228638.5 })), /whose itemID is 228638.5, which is not a whole number/);
    assert.throws(() => render(entry({ itemID: 228638, bonusIDs: '10390:42' })), /whose bonusIDs is "10390:42", not an array/);
    // Never trimmed to the readable ones: a shortened bonus list is a valid
    // key for an item nobody owns, which is worse than no key at all.
    assert.throws(() => render(entry({ itemID: 228638, bonusIDs: [10390, 'x'] })), /bonus ID "x", which is not a whole number/);
    assert.throws(() => render(entry({ itemID: 228638, originalItem: -1 })), /whose originalItem is -1/);
});

test('C-8: a runaway list stops at MAX_EXCLUDED instead of filling the addon folder', () => {
    const many = [];
    for (let i = 0; i < luaWriter.MAX_EXCLUDED + 50; i++) many.push({ slot: 'Finger', name: `ring ${i}`, level: 600 });
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: BOXES,
        excluded: many,
        documents: [topGear()],
    });
    assert.strictEqual((text.match(/ring \d+/g) || []).length, luaWriter.MAX_EXCLUDED);
    assert.ok(text.includes(`ring ${luaWriter.MAX_EXCLUDED - 1}`));
    assert.ok(!text.includes(`ring ${luaWriter.MAX_EXCLUDED}"`));
});

test('renders the committed golden byte for byte', () => {
    const text = render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        profileCapturedAt: '2026-09-05T13:33:25',
        qeSettings: { autoUpgradeVault: false, autoUpgradeAll: false },
        // C-8 (WKE-558): the items his 30-item Top Gear was never shown. The
        // file-level list is the base pass's; each Top Gear document also
        // carries its own, because the Catalyst passes have clones to leave out
        // that the base pass never had. A name with a quote in it is here on
        // purpose - these are QE Live's own card strings.
        excluded: EXCLUDED,
        documents: [
            topGear({ json: '{"schema":"qe-live-droptimizer","version":1}', excluded: EXCLUDED }),
            // C-6 (WKE-540): the same gear asked a different question. The Lua
            // spec proves the two land on two shelves rather than one.
            topGear({
                scenario: 'catalyzed',
                qeSettings: CATALYZED_BOXES,
                excluded: [
                    ...EXCLUDED,
                    {
                        slot: 'Shoulder',
                        name: 'a Catalyst clone',
                        level: 678,
                        // A clone's own ID is the tier piece; `originalItem` is
                        // the item it was made from (Item.ts line 268).
                        itemID: 271527,
                        bonusIDs: [12],
                        originalItem: 228638,
                        catalyst: true,
                    },
                ],
                json: '{"schema":"qe-live-droptimizer","version":1,"catalyzed":true}',
            }),
            // C-7 (WKE-543): an Upgrade Finder document says which Mythic+ key
            // level QE Live ran it at, and spec/companionfile_spec.lua loads
            // this golden in a real Lua interpreter to prove the number comes
            // back as a number.
            { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 10, qeSettings: BOXES, json: '{"schema":"qe-live-upgradefinder","version":1}' },
            { kind: 'upgradefinder', contentType: 'Raid', qeSettings: BOXES, json: HOSTILE },
        ],
    });
    if (process.env.UPDATE_GOLDEN) fs.writeFileSync(GOLDEN, text);
    assert.strictEqual(
        text,
        fs.readFileSync(GOLDEN, 'utf8'),
        'spec/fixtures/expected/qeverdict-sample.lua is out of date; re-run with UPDATE_GOLDEN=1 and check spec/companionfile_spec.lua still passes'
    );
});
