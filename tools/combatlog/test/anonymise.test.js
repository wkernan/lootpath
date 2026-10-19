'use strict';

// Stripping (docs/COMBAT-LOG-WEIGHTS.md §10): no other player's name or GUID
// survives, the owner and everything else are untouched, and the committed
// fixture is already clean - a second pass over it changes nothing.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { anonymise } = require('../lib/anonymise');
const cli = require('../anonymise');
const { readText } = require('../lib/parse');

const FIXTURE = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'combatlog', 'WoWCombatLog-20261017-AltarOfFangs-12.txt.gz');
const OWNER = 'Player-69-0CC01A11';
const OWNER_NAME = 'Hotornot-Arthas-US';

// Two other players, a pet named after one of them whose owner GUID appears
// only bare in the advanced block, and a third player who appears only bare.
const OWNER_S = 'Player-1-0000AAAA';
const RAW = [
    `10/17/2026 20:00:00.000-5  SPELL_HEAL,${OWNER_S},"Healer-Realm-US",0x511,0x80000000,Player-2-0000BBBB,"Tankard-Other-US",0x512,0x80000000,774,"Rejuvenation",0x8,Player-2-0000BBBB,0000000000000000,1,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,10,10,0,0,nil`,
    `10/17/2026 20:00:01.000-5  SPELL_HEAL,Pet-0-1-2-3-4-0000000001,"Tankard's Wolf",0x1112,0x80000000,Player-3-0000CCCC,"Mender-Realm-US",0x512,0x80000000,1,"Bite",0x1,Pet-0-1-2-3-4-0000000001,Player-2-0000BBBB,1,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,10,10,0,0,nil`,
    `10/17/2026 20:00:02.000-5  SPELL_AURA_APPLIED,Player-4-0000DDDD,nil,0x512,0x80000000,${OWNER_S},"Healer-Realm-US",0x511,0x80000000,1126,"Mark of the Wild",0x8,BUFF`,
    `10/17/2026 20:00:03.000-5  CHAT_MSG,"Mender says hello to Tankard and Healer"`,
    '',
].join('\n');

test('a synthetic log: every other player replaced, the owner and all else untouched', () => {
    const r = anonymise(RAW, OWNER_S);
    assert.deepEqual(r.leftover, []);
    for (const gone of ['Player-2-0000BBBB', 'Player-3-0000CCCC', 'Player-4-0000DDDD', 'Tankard', 'Mender']) assert.ok(!r.text.includes(gone), `${gone} survived`);
    assert.ok(r.text.includes(`${OWNER_S},"Healer-Realm-US"`), 'the owner is kept');
    assert.ok(r.text.includes('"Rejuvenation"') && r.text.includes('Mark of the Wild'), 'spells untouched');
    assert.equal(r.text.split('\n').length, RAW.split('\n').length);
    // Named GUIDs numbered in sorted order, the bare-only GUID after them.
    assert.ok(r.text.includes('Player-0-00000001,"Player1-Realm"'));
    assert.ok(r.text.includes('Player-0-00000002,"Player2-Realm"'));
    assert.ok(r.text.includes('Player-0-00000003,nil'));
    assert.ok(r.text.includes(`"Player1's Wolf"`), 'a pet named after its owner');
    assert.ok(r.text.includes('Player2 says hello to Player1 and Healer'), 'bare names in other text');
});

test('a second pass over a stripped text is a no-op', () => {
    const once = anonymise(RAW, OWNER_S).text;
    const twice = anonymise(once, OWNER_S);
    assert.deepEqual(twice.leftover, []);
    assert.equal(twice.text, once);
});

test("the committed fixture names no player but the owner and the pseudonyms, and passes through unchanged", (t) => {
    const text = readText(FIXTURE);
    const names = new Map();
    for (const m of text.matchAll(/(Player-\d+-[0-9A-F]+),"([^"]+)"/g)) names.set(m[1], m[2]);
    for (const [guid, name] of names) {
        if (guid === OWNER) assert.equal(name, OWNER_NAME);
        else {
            assert.match(guid, /^Player-0-0000000\d$/);
            assert.equal(name, `Player${guid.slice(-1)}-Realm`);
        }
    }
    const guids = new Set(text.match(/Player-\d+-[0-9A-F]+/g));
    for (const g of guids) assert.ok(g === OWNER || /^Player-0-0000000\d$/.test(g), `an unstripped GUID: ${g}`);
    assert.equal(names.size, 5);

    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-anon-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const out = path.join(dir, 'again.txt');
    const r = cli.run([FIXTURE, out, OWNER], () => {});
    assert.equal(r.players, 4);
    const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
    assert.equal(sha(fs.readFileSync(out)), sha(Buffer.from(text, 'utf8')));
});

test('the owner must be a player GUID', () => {
    assert.throws(() => anonymise(RAW, 'Healer-Realm-US'), /not a player GUID/);
});
