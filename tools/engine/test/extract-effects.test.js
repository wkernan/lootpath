'use strict';

// E-3b (WKE-684): extract-effects.js reads a `capture effects` snapshot in the
// shape Lootpath/Captures.lua stores it. No transcript exists yet (the owner
// runs the capture after the merge), so the SavedVariables below are the
// tests' own, in the capture's stored shape; the "Use:" line is the committed
// itemstats transcript's Freightrunner's Flask line, verbatim
// (spec/fixtures/captures/Lootpath-20261001-092631.lua), and the 540 at 279 is
// the tests' own.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { extract, render, run, numbersIn } = require('../extract-effects');

const USE_276 =
    'Use: Take a sip of the drink you swiped from the freight, increasing your Critical Strike by 528 for 15 sec. (1 |4Min:Min; 30 |4Sec:Sec; Cooldown)';
const USE_279 = USE_276.replace('528', '540');

function lines(level, use) {
    return `{
        { ["type"] = 22, ["leftText"] = "Freightrunner's Flask" },
        { ["type"] = 31, ["leftText"] = "Item Level ${level}" },
        { ["type"] = 21, ["leftText"] = "Trinket", ["rightText"] = "Test Right" },
        { ["type"] = 1, ["leftText"] = " " },
        { ["type"] = 44, ["leftText"] = "${use}" },
        { ["type"] = 11, ["leftText"] = "" },
    }`;
}

const SV = `
LootpathDB = {
["global"] = {
["captures"] = {
["effects"] = {
{
["name"] = "effects",
["trigger"] = "command",
["capturedAt"] = 1790400000,
["capturedAtLocal"] = "2026-10-03T12:00:00",
["build"] = { "12.1.0", "69933", "Sep 29 2026", 120100, ["n"] = 4 },
["sawSecret"] = false,
["durationMs"] = 12.5,
["data"] = {
["linkLevelRule"] = "track-append",
["waitTimedOut"] = false,
["stillWaiting"] = 0,
["missing"] = { { ["itemID"] = 274495, ["name"] = "Pulse Seeker's Oculus" } },
["items"] = {
{
["itemID"] = 250215,
["name"] = "Freightrunner's Flask",
["kind"] = "stat_on_use",
["targets"] = {
{
["source"] = "journal",
["walkLevel"] = 276,
["difficultyID"] = 2,
["instanceName"] = "Vale",
["link"] = "|cnIQ3:|Hitem:250215::::::::90:105::2:1:3524:1:28:3024:::::|h[Freightrunner's Flask]|h|r",
["reads"] = {
{
["rule"] = "walk",
["level"] = 276,
["link"] = "|cnIQ3:|Hitem:250215::::::::90:105::2:2:3524:12820:1:28:3024:::::|h[Freightrunner's Flask]|h|r",
["detailedLevel"] = { 276, false, 276, ["n"] = 3 },
["itemLevelLine"] = "Item Level 276",
["tooltipLines"] = ${lines(276, USE_276)},
["again"] = { ["itemLevelLine"] = "Item Level 276", ["tooltipLines"] = ${lines(276, USE_276)} },
},
{
["rule"] = "next",
["level"] = 279,
["fromLevel"] = 276,
["track"] = "Adventurer",
["fromStep"] = 4,
["toStep"] = 5,
["link"] = "|cnIQ3:|Hitem:250215::::::::90:105::2:2:3524:12821:1:28:3024:::::|h[Freightrunner's Flask]|h|r",
["detailedLevel"] = { 279, false, 279, ["n"] = 3 },
["itemLevelLine"] = "Item Level 279",
["tooltipLines"] = ${lines(279, USE_279)},
},
},
},
{
["source"] = "journal",
["walkLevel"] = 44,
["reads"] = {
{ ["rule"] = "walk", ["level"] = 44, ["why"] = "no track step draws 44" },
},
},
},
},
},
},
},
},
},
},
}
`;

test('one record per item, per target, per read, with the effect text and its numbers as text', () => {
    const x = extract(SV);
    assert.equal(x.items, 1);
    assert.equal(x.records.length, 3);
    assert.equal(x.linkLevelRule, 'track-append');
    assert.deepEqual(x.missing, [{ itemID: 274495, name: "Pulse Seeker's Oculus" }]);
    const [walk, next, world] = x.records;
    assert.equal(walk.rule, 'walk');
    assert.equal(walk.level, 276);
    assert.equal(walk.itemLevelLine, 'Item Level 276');
    assert.equal(walk.lineCount, 6);
    assert.equal(walk.effects.length, 1);
    assert.deepEqual(walk.effects[0], {
        index: 5,
        type: 44,
        prefix: 'Use',
        text: USE_276,
        numbers: ['528', '15', '1', '30'],
    });
    assert.equal(walk.again.itemLevelLine, 'Item Level 276');
    assert.equal(walk.again.lineCount, 6);
    assert.deepEqual(walk.again.effects, walk.effects);
    assert.equal(next.again, null);
    assert.equal(next.level, 279);
    assert.equal(next.track, 'Adventurer');
    assert.deepEqual(next.effects[0].numbers, ['540', '15', '1', '30']);
    assert.equal(world.link, null);
    assert.equal(world.why, 'no track step draws 44');
    assert.deepEqual(world.effects, []);
});

test('numbers stay text, colour escapes are not numbers, and grouping marks are kept', () => {
    assert.deepEqual(numbersIn('|cFF00FF00Equip: heals for 12,345 over 1.5 sec.|r'), ['12,345', '1.5']);
    assert.deepEqual(numbersIn('no digits'), []);
});

test('an "Equip:" line is found by its text whatever its type, and a non-effect line is not', () => {
    const sv = SV.replace(`["type"] = 44, ["leftText"] = "${USE_276}"`, '["type"] = 99, ["leftText"] = "Equip: Your heals grant 77 Haste."');
    const walk = extract(sv).records[0];
    assert.equal(walk.effects.length, 1);
    assert.equal(walk.effects[0].prefix, 'Equip');
    assert.equal(walk.effects[0].type, 99);
    assert.deepEqual(walk.effects[0].numbers, ['77']);
});

test('the file it writes is labelled with the transcript and loads the same bytes twice', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'effects-'));
    const input = path.join(dir, 'Lootpath.lua');
    fs.writeFileSync(input, SV);
    const a = run([input, path.join(dir, 'out.lua')]);
    const b = run([input, path.join(dir, 'out.lua')]);
    assert.equal(a.text, b.text);
    assert.match(a.text, /^-- spec\/fixtures\/engine\/effects-real\.lua \(E-3b, WKE-684\)/);
    assert.ok(a.text.includes(`F.SHA256 = "${a.sha}"`));
    assert.ok(a.text.includes('"528",'));
    assert.ok(a.text.trimEnd().endsWith('return F'));
    assert.equal(render(extract(SV), 'x.lua', 'abc', 1).split('rule = "walk",').length - 1, 2);
});

test('it refuses a transcript without exactly one snapshot', () => {
    assert.throws(() => extract('LootpathDB = { ["global"] = { ["captures"] = {} } }'), /one effects snapshot/);
    const two = 'LootpathDB = { ["global"] = { ["captures"] = { ["effects"] = { { ["data"] = {} }, { ["data"] = {} } } } } }';
    assert.throws(() => extract(two), /found 2/);
});
