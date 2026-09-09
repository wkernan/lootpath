// C-5 (WKE-539): the driver asks QE Live for both upgrade settings explicitly,
// every run, instead of inheriting his dialog's asymmetric defaults.
//
// The fork driver is the one part of the companion that opens a browser, so the
// checkbox step is written as a function over a `page` and proved here against
// a fake one that records every click and answers `isChecked` the way MUI's
// controlled checkboxes do. No browser is opened by anything in this file, and
// the owner's own companion may be watching in another window.
//
// What is NOT proved here is that Playwright's `getByRole('checkbox', {name})`
// finds his `FormControlLabel` in a real page; that is a recorded run, and its
// figures are in the pull request (docs/ARCHITECTURE.md §9).
'use strict';

const test = require('node:test');
const assert = require('node:assert');

const forkLib = require('../lib/fork');
const luaWriter = require('../lib/luawriter');
const logLib = require('../lib/log');

// The three boxes SimCraftDialog.js renders, in JSX order, starting where his
// `useState` calls leave them: autoUpgradeAll false, autoUpgradeVault TRUE,
// autoCatalyze false (lines 36-38).
function fakeDialog(initial) {
    const state = {
        'Upgrade ALL to Max Level': false,
        'Upgrade Vault to Max Level': true,
        'Auto Catalyze': false,
        ...(initial || {}),
    };
    const clicks = [];
    const page = {
        state: state,
        clicks: clicks,
        // Only the one call the checkbox step makes. A role or an option this
        // fake does not know is a test that has drifted from the code.
        getByRole(role, options) {
            assert.strictEqual(role, 'checkbox');
            assert.strictEqual(options.exact, true);
            const name = options.name;
            return {
                async count() {
                    return name in state ? 1 : 0;
                },
                async isChecked() {
                    if (!(name in state)) throw new Error(`no checkbox ${name}`);
                    return state[name];
                },
                async click() {
                    clicks.push(name);
                    if (page.stuck === name) return;
                    state[name] = !state[name];
                },
            };
        },
    };
    return page;
}

function quietLog() {
    return logLib.make(() => {});
}

test('both boxes are set to what the run asked for, and only the ones asked about are touched', async () => {
    const page = fakeDialog();
    const applied = await forkLib.setUpgradeCheckboxes(page, { autoUpgradeVault: false, autoUpgradeAll: false }, quietLog());

    assert.strictEqual(page.state['Upgrade Vault to Max Level'], false, 'his default is true; the run asked for false');
    assert.strictEqual(page.state['Upgrade ALL to Max Level'], false);
    // Only the box that was wrong is clicked, so a run does not depend on the
    // dialog's defaults staying where they are.
    assert.deepStrictEqual(page.clicks, ['Upgrade Vault to Max Level']);
    // The Catalyst is WKE-540's question; this run does not ask it.
    assert.strictEqual(page.state['Auto Catalyze'], false);
    assert.ok(!page.clicks.includes('Auto Catalyze'));
    assert.deepStrictEqual(applied, {
        autoUpgradeAll: { want: false, was: false, clicked: false },
        autoUpgradeVault: { want: false, was: true, clicked: true },
    });
});

test('the other consistent pair is set the same way, from the same defaults', async () => {
    const page = fakeDialog();
    await forkLib.setUpgradeCheckboxes(page, { autoUpgradeVault: true, autoUpgradeAll: true }, quietLog());
    assert.strictEqual(page.state['Upgrade Vault to Max Level'], true);
    assert.strictEqual(page.state['Upgrade ALL to Max Level'], true);
    assert.deepStrictEqual(page.clicks, ['Upgrade ALL to Max Level'], 'the vault box was already true');
});

test('a dialog that opens the other way round still ends where the run asked', async () => {
    // If he ever flips his own defaults, a driver that clicked blindly would
    // produce the opposite of what was configured and say nothing.
    const page = fakeDialog({ 'Upgrade ALL to Max Level': true, 'Upgrade Vault to Max Level': false });
    await forkLib.setUpgradeCheckboxes(page, { autoUpgradeVault: false, autoUpgradeAll: false }, quietLog());
    assert.strictEqual(page.state['Upgrade Vault to Max Level'], false);
    assert.strictEqual(page.state['Upgrade ALL to Max Level'], false);
    assert.deepStrictEqual(page.clicks, ['Upgrade ALL to Max Level']);
});

test('a click that does not take fails the run rather than reporting a setting it did not get', async () => {
    const page = fakeDialog();
    page.stuck = 'Upgrade Vault to Max Level';
    await assert.rejects(
        () => forkLib.setUpgradeCheckboxes(page, { autoUpgradeVault: false, autoUpgradeAll: false }, quietLog()),
        (e) => {
            assert.strictEqual(e.code, forkLib.DRIVE, 'a stuck box is exit code 4, not a refusal');
            assert.match(e.message, /did not take/);
            assert.match(e.message, /Upgrade Vault to Max Level/);
            return true;
        }
    );
});

test('a missing checkbox is named rather than guessed at by position', async () => {
    // The vault and catalyze boxes render only for gameType "Retail", so on any
    // other game type the index the S-1 spike used points at a different box.
    const page = fakeDialog();
    delete page.state['Upgrade Vault to Max Level'];
    await assert.rejects(
        () => forkLib.setUpgradeCheckboxes(page, { autoUpgradeVault: false, autoUpgradeAll: false }, quietLog()),
        (e) => {
            assert.strictEqual(e.code, forkLib.DRIVE);
            assert.match(e.message, /no checkbox labelled "Upgrade Vault to Max Level"/);
            assert.match(e.message, /will not guess/);
            return true;
        }
    );
});

// Found by a real run on 2026-09-08, not by a fake: `setUpgradeCheckboxes`
// returns the per-box detail the log wants, and handing THAT to the writer is
// a failed write after 10 s of browser. The two ends are tied together here so
// the shape cannot drift again without a red test.
test('what the driver reports is exactly what the verdict writer accepts', async () => {
    const page = fakeDialog();
    const applied = await forkLib.setUpgradeCheckboxes(page, { autoUpgradeVault: false, autoUpgradeAll: true }, quietLog());
    const settings = forkLib.settingsFrom(applied);
    assert.deepStrictEqual(settings, { autoUpgradeAll: true, autoUpgradeVault: false });
    for (const key of Object.keys(settings)) assert.strictEqual(typeof settings[key], 'boolean', key);
    // The writer is strict about this on purpose; it must not throw here.
    const text = luaWriter.render({
        writtenAt: '2026-09-08T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: settings,
        documents: [
            { kind: 'topgear', contentType: 'Dungeon', scenario: 'asOffered', qeSettings: settings, json: '{}' },
        ],
    });
    assert.ok(text.includes('autoUpgradeAll = true,'), text.slice(0, 400));
});

test('the labels are the literals in his source, not translation keys', () => {
    // The issue that asked for this expected `locale/en/translate.json`'s
    // `SimCInput.*` keys; that block holds five keys and none of them is a
    // checkbox. All three labels are plain JSX string literals
    // (SimCraftDialog.js lines 122-133, read 2026-09-08).
    assert.deepStrictEqual(forkLib.CHECKBOX_LABELS, {
        autoUpgradeAll: 'Upgrade ALL to Max Level',
        autoUpgradeVault: 'Upgrade Vault to Max Level',
        autoCatalyze: 'Auto Catalyze',
    });
});

test('the boxes are set before Submit, because handleSubmit reads their state', async () => {
    // SimCraftDialog.js `handleSubmit` passes autoUpgradeVault/autoUpgradeAll
    // into `runSimC` by value, so a box set after the click changes nothing.
    const dialog = fakeDialog();
    const order = [];
    const page = {
        getByRole(role, options) {
            if (role === 'checkbox') {
                const inner = dialog.getByRole(role, options);
                return {
                    count: inner.count,
                    isChecked: inner.isChecked,
                    async click() {
                        order.push(`checkbox:${options.name}`);
                        await inner.click();
                    },
                };
            }
            assert.strictEqual(options.name, 'Submit');
            return {
                async click() {
                    order.push('submit');
                },
            };
        },
        getByText() {
            return { first: () => ({ async click() {} }) };
        },
        locator(selector) {
            assert.ok(selector === '#simcentry' || selector === '#SimCError', selector);
            return {
                async waitFor() {},
                async fill(text) {
                    order.push(`fill:${text.length}`);
                },
                filter() {
                    // #SimCError never resolves in a run QE Live accepted.
                    return { waitFor: () => new Promise(() => {}) };
                },
            };
        },
    };
    // The success race resolves on the entry box going hidden; the fake's
    // waitFor resolves at once, which is that outcome.
    const profile = 'druid="Hotornot"';
    const settings = await forkLib.importProfile(page, profile, { autoUpgradeVault: false, autoUpgradeAll: false }, quietLog());
    assert.deepStrictEqual(order, [`fill:${profile.length}`, 'checkbox:Upgrade Vault to Max Level', 'submit']);
    assert.strictEqual(settings.autoUpgradeVault.want, false);
});
