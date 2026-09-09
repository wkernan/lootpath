// C-7 (WKE-543): the companion runs QE Live's Upgrade Finder once per Mythic+
// key level, so the map can answer "which dungeon at the LOWEST key still gives
// me an upgrade".
//
// His Upgrade Finder values every dungeon drop at ONE key: the one
// `ufSettings.dungeon` names. That field is an INDEX into his MPLUS_KEY_REWARDS
// table, not a key level - index 7 is the "+10" button - so the companion asks
// for a key LEVEL, finds the button whose own label covers it, and then checks
// the export's `settings.dungeon` against the position of the button it
// clicked. Nothing here restates his table.
//
// No browser is opened by anything in this file. The page below is a fake that
// answers the four calls the selector step makes, and the owner's own companion
// may be watching in another window while these run.
'use strict';

const test = require('node:test');
const assert = require('node:assert');

const fs = require('fs');
const os = require('os');
const path = require('path');

const forkLib = require('../lib/fork');
const configLib = require('../lib/config');
const luaWriter = require('../lib/luawriter');
const logLib = require('../lib/log');

// MPLUS_KEY_REWARDS, read from the fork 2026-09-08: eight toggles, in his own
// order, labelled the way a player says a key. The row is deliberately written
// out as LABELS only - the test knows the labels his page shows and nothing
// about the item levels behind them, which is the whole point.
const HIS_LABELS = ['M0', '+2/3', '+4', '+5', '+6', '+7', '+8/9', '+10'];

// A page with one Paper carrying the "Mythic+ Key Level" header and one button
// per label, plus a decoy Paper of raid difficulties, because the real page has
// three toggle rows and picking the wrong one is the failure this guards.
function fakePage(labels, options) {
    const opts = options || {};
    const shown = labels || HIS_LABELS;
    let selected = opts.selected === undefined ? 7 : opts.selected;
    const clicks = [];
    const button = (index, label) => ({
        async innerText() {
            return label;
        },
        async getAttribute(name) {
            if (name === 'aria-pressed') return selected === index ? 'true' : 'false';
            if (name === 'class') return selected === index ? 'MuiToggleButton-root Mui-selected' : 'MuiToggleButton-root';
            return null;
        },
        async click() {
            clicks.push(label);
            if (opts.stuck === label) return;
            selected = index;
        },
    });
    const page = {
        clicks: clicks,
        get selected() {
            return selected;
        },
        locator(selector) {
            assert.strictEqual(selector, '.MuiPaper-root');
            const papers = [
                { text: 'Raid Difficulty Raid Finder Normal Heroic Mythic', labels: ['Raid Finder', 'Normal', 'Heroic', 'Mythic'] },
                { text: `Mythic+ Key Level ${shown.join(' ')}`, labels: shown },
            ];
            return {
                filter(filterOptions) {
                    const matching = papers.filter((paper) => paper.text.includes(filterOptions.hasText));
                    return {
                        last() {
                            const paper = matching[matching.length - 1];
                            return {
                                async count() {
                                    return paper ? 1 : 0;
                                },
                                getByRole(role) {
                                    assert.strictEqual(role, 'button');
                                    return {
                                        async count() {
                                            return paper.labels.length;
                                        },
                                        nth(index) {
                                            return button(index, paper.labels[index]);
                                        },
                                    };
                                },
                            };
                        },
                    };
                },
            };
        },
    };
    return page;
}

function quietLog() {
    return logLib.make(() => {});
}

// --- his labels, read rather than restated ----------------------------------

test('a key label is read as the levels a player would say', () => {
    assert.deepStrictEqual(forkLib.keyLevelsOfLabel('M0'), [0]);
    assert.deepStrictEqual(forkLib.keyLevelsOfLabel('+4'), [4]);
    assert.deepStrictEqual(forkLib.keyLevelsOfLabel('+2/3'), [2, 3]);
    assert.deepStrictEqual(forkLib.keyLevelsOfLabel('+8/9'), [8, 9]);
    assert.deepStrictEqual(forkLib.keyLevelsOfLabel(' +10 '), [10]);
    // Anything that is not one of his key labels is nothing, never a guess.
    assert.strictEqual(forkLib.keyLevelsOfLabel('Heroic'), null);
    assert.strictEqual(forkLib.keyLevelsOfLabel('590'), null);
    assert.strictEqual(forkLib.keyLevelsOfLabel('+'), null);
    assert.strictEqual(forkLib.keyLevelsOfLabel(''), null);
});

test('every key toggle is read in his order, so its position is his index', async () => {
    const buttons = await forkLib.readKeyLevelButtons(fakePage());
    assert.deepStrictEqual(
        buttons.map((b) => [b.index, b.label, b.levels]),
        [
            [0, 'M0', [0]],
            [1, '+2/3', [2, 3]],
            [2, '+4', [4]],
            [3, '+5', [5]],
            [4, '+6', [6]],
            [5, '+7', [7]],
            [6, '+8/9', [8, 9]],
            [7, '+10', [10]],
        ]
    );
});

test('a button the companion cannot read as a key stops the count rather than shifting it', async () => {
    await assert.rejects(
        () => forkLib.readKeyLevelButtons(fakePage(['M0', 'Reset', '+4'])),
        /labelled "Reset", which is not one of QE Live's key labels/
    );
});

test('a page with no key section is a named failure, not a guess at which buttons those are', async () => {
    const page = fakePage();
    const paper = page.locator;
    page.locator = (selector) => {
        const real = paper.call(page, selector);
        return { filter: () => ({ last: () => ({ async count() { return 0; } }) }) };
    };
    await assert.rejects(() => forkLib.readKeyLevelButtons(page), /has no "Mythic\+ Key Level" section/);
});

// --- selecting a level ------------------------------------------------------

test('a level covered by a two-key label selects that one button', async () => {
    const page = fakePage(undefined, { selected: 7 });
    const chosen = await forkLib.selectKeyLevel(page, 9, quietLog());
    assert.strictEqual(chosen.label, '+8/9');
    assert.strictEqual(chosen.index, 6);
    assert.deepStrictEqual(page.clicks, ['+8/9']);
    assert.strictEqual(page.selected, 6);
});

test('the button already selected is not clicked again', async () => {
    const page = fakePage(undefined, { selected: 7 });
    const chosen = await forkLib.selectKeyLevel(page, 10, quietLog());
    assert.strictEqual(chosen.index, 7);
    assert.deepStrictEqual(page.clicks, [], 'a toggle clicked while it is on turns it off');
});

test('a key level his page does not offer is refused by name, never rounded to a near one', async () => {
    const page = fakePage();
    await assert.rejects(
        () => forkLib.selectKeyLevel(page, 12, quietLog()),
        /offers M0, \+2\/3, \+4, \+5, \+6, \+7, \+8\/9, \+10, so it cannot be asked about a \+12 key/
    );
    assert.deepStrictEqual(page.clicks, [], 'nothing is clicked when the level does not exist');
});

test('a click that does not take is a failed run, not a document filed under the wrong key', async () => {
    const page = fakePage(undefined, { selected: 7, stuck: '+4' });
    await assert.rejects(() => forkLib.selectKeyLevel(page, 4, quietLog()), /clicking "\+4" did not select it/);
});

// --- the export has to agree ------------------------------------------------

test("the export's own settings.dungeon is read, and only when it is an integer", () => {
    assert.strictEqual(forkLib.exportedKeyIndex('{"settings":{"dungeon":7}}'), 7);
    assert.strictEqual(forkLib.exportedKeyIndex('{"settings":{"dungeon":0}}'), 0);
    assert.strictEqual(forkLib.exportedKeyIndex('{"settings":{}}'), null);
    assert.strictEqual(forkLib.exportedKeyIndex('{"settings":{"dungeon":"7"}}'), null);
    assert.strictEqual(forkLib.exportedKeyIndex('not json'), null);
});

// The whole Upgrade Finder step over a fake page: navigate, select, Go!, export.
// It is the one place the selector and the check meet, so it is driven end to
// end rather than asserted about in pieces.
function fakeUpgradeFinderPage(exportedIndex, options) {
    const page = fakePage(undefined, options);
    page.exported = null;
    page.goTo = [];
    page.locator_original = page.locator;
    const original = page.locator;
    page.locator = function (selector) {
        if (selector === '.MuiPaper-root') return original.call(page, selector);
        // goTo's in-app link, and readJson's dialog field.
        if (selector.startsWith('a[href=')) {
            return { first: () => ({ async count() { return 0; } }) };
        }
        if (selector === '.MuiDialog-root textarea') {
            return {
                first: () => ({
                    async waitFor() {},
                    async inputValue() {
                        return page.exported;
                    },
                }),
            };
        }
        throw new Error(`the fake page was asked for ${selector}`);
    };
    page.evaluate = async () => {};
    page.waitForURL = async () => {};
    page.keyboard = { async press() {} };
    page.getByRole = (role, options2) => {
        if (role === 'button' && options2.name === 'Go!') {
            return {
                first: () => ({ async click() {} }),
                async click() {
                    const index = page.selected;
                    page.exported = JSON.stringify({
                        schema: 'qe-live-upgradefinder',
                        settings: { dungeon: exportedIndex === undefined ? index : exportedIndex },
                    });
                },
            };
        }
        if (role === 'button' && options2.name === 'Export') return { first: () => ({ async click() {} }) };
        if (role === 'menuitem') return { async click() {} };
        throw new Error(`the fake page was asked for role ${role} ${JSON.stringify(options2)}`);
    };
    return page;
}

test('an Upgrade Finder run sets the key, runs, and hands back his export', async () => {
    const page = fakeUpgradeFinderPage();
    const json = await forkLib.runUpgradeFinder(page, 6, quietLog());
    assert.strictEqual(page.selected, 4, '+6 is his index 4');
    assert.strictEqual(JSON.parse(json).settings.dungeon, 4);
});

test('an export whose settings.dungeon is not the button that was clicked fails the run', async () => {
    // His page says the run was at index 7 while the companion clicked index 4:
    // a document filed under +6 that was really run at +10 is a wrong answer
    // that looks right, so the run fails instead (exit code 4).
    const page = fakeUpgradeFinderPage(7);
    await assert.rejects(
        () => forkLib.runUpgradeFinder(page, 6, quietLog()),
        (error) => {
            assert.strictEqual(error.code, forkLib.DRIVE);
            assert.match(error.message, /asked for a \+6 key \("\+6", his index 4\) but the export says settings.dungeon = 7/);
            return true;
        }
    );
});

test('an Upgrade Finder run without a key level leaves his selector alone', async () => {
    const page = fakeUpgradeFinderPage(undefined, { selected: 3 });
    await forkLib.runUpgradeFinder(page, undefined, quietLog());
    assert.deepStrictEqual(page.clicks, []);
    assert.strictEqual(page.selected, 3);
});

// --- the plan ---------------------------------------------------------------

test('the dungeon Upgrade Finder is planned once per key level, everything else once', () => {
    const config = configLib.load(null);
    assert.deepStrictEqual(config.upgradeFinderKeyLevels, [2, 4, 6, 8, 10]);
    assert.deepStrictEqual(configLib.plannedDocuments(config, { hasVaultGear: false }), [
        { kind: 'topgear', contentType: 'Dungeon', scenario: 'asOffered' },
        { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 2 },
        { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 4 },
        { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 6 },
        { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 8 },
        { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 10 },
        { kind: 'topgear', contentType: 'Raid', scenario: 'asOffered' },
        // Not "none", which is what WKE-543 proposed: the Raid Upgrade Finder
        // export carries the same dungeon-sourced rows as the Dungeon one, all
        // stamped with the key index the selector held (measured on the
        // committed 2026-09-07 pair: 201 rows at dropDifficulty 7). A document
        // whose rows were valued at a key is filed under that key.
        { kind: 'upgradefinder', contentType: 'Raid', keyLevel: 10 },
    ]);
});

test('the level list is one question however it is typed', () => {
    // Sorted and deduplicated by `load`, so `[10, 2, 2]` and `[2, 10]` are one
    // plan and - because the fingerprint hashes the same list - one question.
    assert.deepStrictEqual(loadWith([10, 2, 2, 10]).upgradeFinderKeyLevels, [2, 10]);
    assert.deepStrictEqual(
        configLib.plannedDocuments(loadWith([10, 2, 2, 10]), { hasVaultGear: true }),
        configLib.plannedDocuments(loadWith([2, 10]), { hasVaultGear: true })
    );
});

// The validation runs inside `load`, so it is reached through a config file the
// way the owner would reach it.
function loadWith(value) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c7-'));
    const file = path.join(dir, 'config.json');
    fs.writeFileSync(file, JSON.stringify({ upgradeFinderKeyLevels: value }), 'utf8');
    return configLib.load(file);
}

test('a level list that is not a list of whole key levels is refused with the value in it', () => {
    assert.throws(() => loadWith([-1]), /every entry must be a whole key level/);
    assert.throws(() => loadWith([4.5]), /every entry must be a whole key level/);
    assert.throws(() => loadWith(['10']), /every entry must be a whole key level/);
    assert.throws(() => loadWith([]), /upgradeFinderKeyLevels is empty/);
    // A string is not a list, and `typeof` alone would not have caught it.
    assert.throws(() => loadWith('2,4'), /should be a list, not a string/);
    // A key level of 0 is M0, which his page really does offer.
    assert.deepStrictEqual(loadWith([0, 10]).upgradeFinderKeyLevels, [0, 10]);
});

// --- the document the addon reads -------------------------------------------

const BOXES = { autoUpgradeVault: false, autoUpgradeAll: false, autoCatalyze: false };

test('an Upgrade Finder document records the key level it was run at', () => {
    const text = luaWriter.render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        profileCapturedAt: '2026-09-05T13:33:25',
        qeSettings: { autoUpgradeVault: false, autoUpgradeAll: false },
        documents: [
            { kind: 'topgear', contentType: 'Dungeon', scenario: 'asOffered', qeSettings: BOXES, json: '{}' },
            { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 2, qeSettings: BOXES, json: '{}' },
            { kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 10, qeSettings: BOXES, json: '{}' },
        ],
    });
    assert.match(text, /contentType = "Dungeon",\n            keyLevel = 2,/);
    assert.match(text, /contentType = "Dungeon",\n            keyLevel = 10,/);
    // The Top Gear document is not run at a key level and must not claim one.
    const topGear = text.split('        {')[1];
    assert.ok(!topGear.includes('keyLevel'), topGear);
});

test('a key level that is not a whole number, or is on the wrong kind of document, is refused', () => {
    const payload = {
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        profileCapturedAt: '',
        qeSettings: { autoUpgradeVault: false, autoUpgradeAll: false },
    };
    assert.throws(
        () => luaWriter.render({ ...payload, documents: [{ kind: 'upgradefinder', contentType: 'Dungeon', keyLevel: 2.5, json: '{}' }] }),
        /not a whole key level/
    );
    assert.throws(
        () => luaWriter.render({ ...payload, documents: [{ kind: 'topgear', contentType: 'Dungeon', keyLevel: 2, json: '{}' }] }),
        /only an Upgrade Finder document is run at a key level/
    );
});
