// The profile builder, over the committed transcript, and then measured
// against the owner's real `/simc` string.
//
// The two fixtures are two days apart (inventory captured 2026-09-05, `/simc`
// copied 2026-09-07 after the owner equipped five swaps), so they cannot match
// item for item. What CAN be checked is the grammar: every line the companion
// writes for an item the owner still had on the 7th has to be the line the
// SimulationCraft addon wrote for it, field for field and in the same order.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { parse } = require('../lib/savedvariables');
const profileLib = require('../lib/profile');

const REPO = path.join(__dirname, '..', '..', '..');
const TRANSCRIPT = path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20260906-200908.lua');
const SIMC = path.join(REPO, 'spec', 'fixtures', 'simc', 'hotornot-20260907.txt');

const db = parse(fs.readFileSync(TRANSCRIPT, 'utf8'));
const built = profileLib.build(db, { now: '2026-09-08T00:00:00Z', companionVersion: '0.1.0' });

function itemLines(text) {
    return text
        .split('\n')
        .map((l) => l.trim())
        .filter((l) => /,id=\d+/.test(l));
}
// The slot prefix is decorative (QE Live takes the slot from its own item
// database), and "# " only marks a line as not equipped, so neither belongs in
// a grammar comparison.
function fields(line) {
    return line.replace(/^#\s*/, '').replace(/^[a-z_0-9]+=/, '');
}

test('builds a profile from the committed transcript', () => {
    assert.ok(built.ok, built.ok ? '' : built.reason);
    assert.strictEqual(built.counts.equipped, 15);
    assert.strictEqual(built.counts.bagged, 35);
    assert.strictEqual(built.counts.lines, 101);
});

test('the header puts the class line inside the eight lines QE Live validates', () => {
    const lines = built.text.split('\n');
    // checkSimCValid reads lines.slice(0, 8) and needs one whose key is a
    // substring of the class it has selected.
    const head = lines.slice(0, 8);
    assert.ok(
        head.some((l) => l.startsWith('druid=')),
        `no class line in the first eight lines:\n${head.join('\n')}`
    );
    assert.strictEqual(lines[0][0], '#', 'line 0 must be a comment: it is where he reads the character name');
    assert.strictEqual(lines[0].split('-')[0].replace('#', '').trim(), 'Hotornot');
    assert.ok(lines.some((l) => l.startsWith('server=arthas')));
});

test('the class line is safely above line 8, where a "dru-id=" would be read as an item', () => {
    const lines = built.text.split('\n');
    // processAllLines takes any line containing "id=" as an item, and
    // `druid="Hotornot"` contains it. That is why it starts at index 8. The
    // header must therefore stay long enough to keep the class line below 8 and
    // short enough to keep it inside the eight checkSimCValid reads.
    const classLine = lines.findIndex((l) => l.startsWith('druid='));
    assert.ok(classLine < 8, `the class line is at ${classLine}, outside the header QE Live validates`);
    assert.ok(lines[classLine].includes('id='), 'this guard only means something while "druid" contains "id="');
    // Nothing from line 8 on is a header field; the first is the blank line
    // before the gear.
    const afterHeader = lines.slice(8).filter((l) => l.includes('id=') && !/^#?\s*[a-z_0-9]+=,id=\d+/.test(l));
    assert.deepStrictEqual(afterHeader, []);
});

test('equipped items are uncommented and bag items are commented, which is how QE Live tells them apart', () => {
    const lines = built.text.split('\n');
    const equipped = lines.filter((l) => /^[a-z_0-9]+=,id=/.test(l));
    const bagged = lines.filter((l) => /^# [a-z_0-9]+=,id=/.test(l));
    assert.strictEqual(equipped.length, 15);
    assert.strictEqual(bagged.length, 35);
});

test('paired slots are numbered from the equipment slot they were found in', () => {
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_FINGER', 11), 'finger1');
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_FINGER', 12), 'finger2');
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_TRINKET', 13), 'trinket1');
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_TRINKET', 14), 'trinket2');
    // A bag copy has no equipment slot and is always the first of the pair,
    // exactly as the SimulationCraft addon writes it.
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_FINGER', null), 'finger1');
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_WEAPON', 17), 'off_hand');
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_2HWEAPON', 16), 'main_hand');
    // Shirts and tabards have no QE Live slot and never become a line.
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_BODY', 4), null);
    assert.strictEqual(profileLib.slotPrefix('INVTYPE_TABARD', 19), null);
});

test('every equipped slot in the transcript reached a line, and nothing else did', () => {
    const equipped = built.text
        .split('\n')
        .filter((l) => /^[a-z_0-9]+=,id=/.test(l))
        .map((l) => l.split('=')[0]);
    assert.deepStrictEqual(equipped, [
        'head',
        'neck',
        'shoulder',
        'chest',
        'waist',
        'legs',
        'feet',
        'wrist',
        'hands',
        'finger1',
        'finger2',
        'trinket1',
        'trinket2',
        'back',
        'main_hand',
    ]);
});

test('the lines match the SimulationCraft addon field for field, on every item the owner still had', () => {
    const mine = new Map(itemLines(built.text).map((l) => [fields(l), l]));
    const theirs = new Set(itemLines(fs.readFileSync(SIMC, 'utf8')).map(fields));
    let identical = 0;
    for (const key of mine.keys()) if (theirs.has(key)) identical++;
    // Measured 2026-09-07: 26 of the companion's 50 item lines are byte-identical
    // to a line of the owner's own `/simc` string. The rest are items he no
    // longer had on the 7th, or had upgraded - every remaining difference is one
    // upgrade-track bonus ID or its position in the list, never a field name, a
    // missing field or a different order of fields.
    assert.strictEqual(mine.size, 50);
    assert.strictEqual(identical, 26);
});

test('the field order is the addon\'s: id, enchant, gem, bonus, then the modifiers', () => {
    // The two fixtures hold different items, so the SET of field combinations
    // cannot match. The ORDER can: every line either fixture writes has to be a
    // subsequence of this one sequence, which is what makes the companion's
    // output indistinguishable from the addon's on any item they share.
    const ORDER = ['id', 'enchant_id', 'gem_id', 'bonus_id', 'content_tuning', 'redirected_base_stats', 'crafted_stats', 'crafting_quality'];
    const isSubsequence = (names) => {
        let at = -1;
        return names.every((name) => {
            const next = ORDER.indexOf(name, at + 1);
            if (next === -1) return false;
            at = next;
            return true;
        });
    };
    const names = (l) =>
        fields(l)
            .split(',')
            .filter(Boolean)
            .map((f) => f.split('=')[0]);
    for (const line of itemLines(built.text)) {
        assert.ok(isSubsequence(names(line)), `the companion writes fields out of order: ${line}`);
    }
    for (const line of itemLines(fs.readFileSync(SIMC, 'utf8'))) {
        assert.ok(isSubsequence(names(line)), `the SimulationCraft addon disagrees with ORDER: ${line}`);
    }
});

test('refuses, naming what is missing, rather than shipping half a profile', () => {
    assert.deepStrictEqual(profileLib.build({}, {}).ok, false);
    const noCaptures = profileLib.build({ LootpathDB: { global: {} } }, {});
    assert.strictEqual(noCaptures.ok, false);
    assert.match(noCaptures.reason, /no captures table/);

    const noInventory = profileLib.build({ LootpathDB: { global: { captures: { env: db.LootpathDB.global.captures.env } } } }, {});
    assert.strictEqual(noInventory.ok, false);
    assert.deepStrictEqual(noInventory.missing, ['an inventory capture (/lootpath capture inventory)']);
    assert.strictEqual(noInventory.wanted, 'profile');

    const noEnv = profileLib.build(
        { LootpathDB: { global: { captures: { inventory: db.LootpathDB.global.captures.inventory } } } },
        {}
    );
    assert.strictEqual(noEnv.ok, false);
    assert.deepStrictEqual(noEnv.missing, ['character name', 'class', 'realm']);
});

test('names every field the SavedVariables cannot answer instead of inventing one', () => {
    assert.ok(built.warnings.some((w) => w.startsWith('no region ')));
    assert.ok(built.warnings.some((w) => w.startsWith('no level ')));
    assert.ok(built.warnings.some((w) => w.startsWith('no race ')));
    assert.ok(built.warnings.some((w) => w.includes('"profile" capture is not written yet')));
    // The lines are still written, empty, so the header keeps its length and
    // the class line stays inside the eight QE Live reads.
    const lines = built.text.split('\n');
    assert.ok(lines.includes('region='));
    assert.ok(lines.includes('level='));
    assert.ok(lines.includes('race='));
});

test('prefers the "profile" capture when the addon starts writing one', () => {
    const captures = { ...db.LootpathDB.global.captures };
    captures.profile = {
        1: {
            capturedAt: 9999999999,
            capturedAtLocal: '2026-09-08T10:00:00',
            data: {
                name: 'Hotornot',
                realm: 'Arthas',
                region: 'us',
                level: 90,
                race: 'zandalari_troll',
                classToken: 'DRUID',
                spec: 'Restoration',
                build: '12.1.0',
                interfaceVersion: 120100,
            },
        },
    };
    const result = profileLib.build({ LootpathDB: { global: { captures } } }, { companionVersion: '0.1.0' });
    assert.ok(result.ok, result.ok ? '' : result.reason);
    assert.strictEqual(result.identity.source, 'profile');
    const lines = result.text.split('\n');
    assert.ok(lines.includes('region=us'));
    assert.ok(lines.includes('level=90'));
    assert.ok(lines.includes('race=zandalari_troll'));
    assert.ok(lines.includes('spec=restoration'));
    assert.strictEqual(
        result.warnings.filter((w) => w.startsWith('no region ') || w.startsWith('no level ') || w.startsWith('no race ')).length,
        0
    );
});

test('the bank can be left out, and is reported when it was closed', () => {
    const withoutBank = profileLib.build(db, { includeBank: false });
    assert.ok(withoutBank.ok);
    assert.strictEqual(withoutBank.counts.bank, 0);
    assert.ok(built.warnings.some((w) => w.includes('the bank was closed')));
});

test('a Great Vault reward becomes a Weekly Reward Choices line', () => {
    const captures = JSON.parse(JSON.stringify(db.LootpathDB.global.captures));
    captures.vault[1].capturedAt = 9999999999;
    captures.vault[1].data.rewardLinks = {
        1: {
            link: { 1: '|cnIQ4:|Hitem:271528::::::::90:104::23:7:6652:13439:13696:12838:13692:13698:1561:1:64:251140:::::|h[x]|h|r', n: 1 },
            item: { instant: { 1: 271528, 4: 'INVTYPE_HEAD', n: 7 } },
        },
    };
    const result = profileLib.build({ LootpathDB: { global: { captures } } }, {});
    assert.ok(result.ok, result.ok ? '' : result.reason);
    assert.strictEqual(result.counts.vault, 1);
    const lines = result.text.split('\n');
    const marker = lines.indexOf('### Weekly Reward Choices');
    assert.ok(marker > 0, 'QE Live types everything after this line as a vault item');
    assert.ok(lines[marker + 1].startsWith('head=,id=271528'));
});

test('says so when QE Live valued a different spec from the one captured', () => {
    // QE Live never reads the `spec=` line; it values whatever spec is selected
    // in its own character panel. Measured 2026-09-08: a profile written
    // spec=guardian came back as a "Restoration Druid" report.
    assert.strictEqual(profileLib.specMismatch('Restoration Druid', 'Restoration'), null);
    assert.strictEqual(profileLib.specMismatch('Restoration Druid', 'restoration druid'), null);
    assert.match(profileLib.specMismatch('Restoration Druid', 'Guardian'), /valued "Restoration Druid".*captured in "Guardian"/);
    // Nothing to compare is not a disagreement.
    assert.strictEqual(profileLib.specMismatch(null, 'Guardian'), null);
    assert.strictEqual(profileLib.specMismatch('Restoration Druid', null), null);
});

test('an inventory capture with nothing equipped is refused, not shipped empty', () => {
    // QE Live would import it happily and value a naked character.
    const captures = { env: db.LootpathDB.global.captures.env, inventory: { 1: { capturedAt: 1, capturedAtLocal: 'x', data: { equipped: {}, bags: {} } } } };
    const result = profileLib.build({ LootpathDB: { global: { captures } } }, {});
    assert.strictEqual(result.ok, false);
    assert.deepStrictEqual(result.missing, ['equipped gear']);
});
