// The item-link reader, against links taken out of the committed transcript
// and against Core.lua's rules for the same fields.
'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { parseItemLink } = require('../lib/itemlink');

// Equipped head slot, spec/fixtures/captures/Lootpath-20260906-200908.lua,
// inventory snapshot 2026-09-05T13:33:25.
const HEAD = '|cnIQ4:|Hitem:271528::::::::90:104::23:7:6652:13439:13696:12838:13692:13698:1561:1:64:251140:::::|h[Enigmatic Dreamwatcher\'s Somnolent Stare]|h|r';
// Equipped finger1 in the same snapshot: an enchant and a gem as well.
const RING =
    '|cnIQ4:|Hitem:151311:7968:240892::::::90:104::33:5:13440:6652:13668:12699:12790:1:28:1279:::::|h[Band of the Triumvirate]|h|r';
// A crafted item from the 2026-09-05 transcript: the crafter's GUID sits in a
// trailing field, and it carries three modifiers, two of which the companion
// has no name for and therefore drops.
const CRAFTED =
    '|Hitem:222842::::::::90:104::13:3:10827:10830:13625:3:28:2734:38:5:40:2377::::Player-69-0F82625A:|h[x]|h';

test('reads itemID, bonus IDs in link order, and the modifier pairs', () => {
    const parsed = parseItemLink(HEAD);
    assert.strictEqual(parsed.itemID, 271528);
    assert.deepStrictEqual(parsed.bonusIDs, [6652, 13439, 13696, 12838, 13692, 13698, 1561]);
    assert.deepStrictEqual(parsed.modifiers, [{ type: 64, value: 251140 }]);
    assert.strictEqual(parsed.enchantID, null);
    assert.deepStrictEqual(parsed.gems, []);
});

test('reads the enchant and the gem out of their own fields', () => {
    const parsed = parseItemLink(RING);
    assert.strictEqual(parsed.itemID, 151311);
    assert.strictEqual(parsed.enchantID, 7968);
    assert.deepStrictEqual(parsed.gems, [240892]);
    assert.deepStrictEqual(parsed.bonusIDs, [13440, 6652, 13668, 12699, 12790]);
    assert.deepStrictEqual(parsed.modifiers, [{ type: 28, value: 1279 }]);
});

test('keeps link order for the SimC line but sorts for the item key, as Core.lua does', () => {
    const parsed = parseItemLink(HEAD);
    assert.deepStrictEqual(parsed.bonusIDsSorted, [1561, 6652, 12838, 13439, 13692, 13696, 13698]);
    assert.strictEqual(parsed.key, '271528:1561:6652:12838:13439:13692:13696:13698');
});

test('an item with no bonus IDs keys on the bare itemID', () => {
    assert.strictEqual(parseItemLink('|Hitem:6948::::::::90:104|h[Hearthstone]|h').key, '6948');
});

test("a crafted item's GUID field reads as 0 rather than failing the line", () => {
    const parsed = parseItemLink(CRAFTED);
    assert.strictEqual(parsed.itemID, 222842);
    assert.deepStrictEqual(parsed.bonusIDs, [10827, 10830, 13625]);
    assert.deepStrictEqual(parsed.modifiers, [
        { type: 28, value: 2734 },
        { type: 38, value: 5 },
        { type: 40, value: 2377 },
    ]);
});

test('garbage is nil, never a half-read item', () => {
    assert.strictEqual(parseItemLink(null), null);
    assert.strictEqual(parseItemLink(''), null);
    assert.strictEqual(parseItemLink('|cff9d9d9d|Hquest:123|h[Not an item]|h|r'), null);
    assert.strictEqual(parseItemLink('|Hitem:0::::::::90:104|h[nothing]|h'), null);
});
