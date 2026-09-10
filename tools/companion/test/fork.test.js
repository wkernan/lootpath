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

// -------------------------------------------------------------------------
// C-8 (WKE-558): which thirty items QE Live's Top Gear is asked about.
//
// The page below is a fake, and what it fakes is HIS rule: a card can become
// active only while the counter is under the cap (TopGear.tsx line 739), the
// counter is the number of active cards, and clicking an active card would
// deselect it. Nothing here opens a browser.
//
// The DOM read (`readCards`) is deliberately not faked twice: it is one
// `page.evaluate` whose result shape is what every test below hands in, and
// the decision it feeds - `chooseSelection` - is pure and is where the whole of
// C-8 lives.

// A card as `readCards` returns it.
function card(index, slot, name, extra) {
    return {
        index: index,
        slot: slot,
        name: name,
        level: 600 + index,
        itemID: 200000 + index,
        active: false,
        vault: false,
        catalyst: false,
        ...(extra || {}),
    };
}

// The shape of the owner's 2026-09-09 22:48 page, as the run logged it: 57
// cards, 19 of them active on import (15 equipped + 4 vault), and on a Catalyst
// pass six clones on top with one of them active.
function ownersPage(options) {
    const opts = options || {};
    const slots = ['Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet', 'Finger', 'Trinket', 'Weapons', 'Offhands'];
    const cards = [];
    let index = 0;
    for (let i = 0; i < 15; i++) cards.push(card(index++, slots[i % slots.length], `equipped ${i}`, { active: true }));
    for (let i = 0; i < 4; i++) cards.push(card(index++, slots[i], `vault ${i}`, { active: true, vault: true }));
    for (let i = 0; i < 38; i++) cards.push(card(index++, slots[i % slots.length], `bag ${i}`));
    if (opts.clones) {
        for (let i = 0; i < opts.clones; i++) {
            cards.push(card(index++, slots[i % slots.length], `clone ${i}`, { catalyst: true, active: i === 0 }));
        }
    }
    return cards;
}

// A page whose counter and cards obey his rule, so a driver that clicks the
// wrong card is caught by the counter rather than by an assertion.
function fakeTopGearPage(cards, cap) {
    const state = cards.map((c) => ({ ...c }));
    const clicks = [];
    const page = {
        cards: state,
        clicks: clicks,
        cap: cap,
        count() {
            return state.filter((c) => c.active).length;
        },
        getByText() {
            return {
                first: () => ({
                    async waitFor() {},
                    async innerText() {
                        return `Selected Items: ${page.count()}/${cap}`;
                    },
                }),
            };
        },
        async evaluate() {
            return state.map((c) => ({ ...c }));
        },
        locator(selector) {
            if (selector !== forkLib.CARD) throw new Error(`unexpected selector ${selector}`);
            return {
                nth(i) {
                    return {
                        async click() {
                            clicks.push(i);
                            const target = state[i];
                            if (!target) throw new Error(`no card ${i}`);
                            // His own guard: past the cap a click does nothing.
                            if (!target.active && page.count() >= cap) return;
                            target.active = !target.active;
                        },
                    };
                },
            };
        },
    };
    return page;
}

test('C-8: the room left by the cap goes to the vault, then the Catalyst clones, then the bags', () => {
    const plan = forkLib.chooseSelection(ownersPage({ clones: 6 }), 30);
    // 19 equipped/vault + 1 active clone = 20 active on import, so 10 of room.
    assert.strictEqual(plan.keep.length, 20);
    assert.strictEqual(plan.room, 10);
    const chosen = plan.activate;
    assert.strictEqual(chosen.length, 10);
    // Every clone that was not already active is in, and it got there before a
    // single bag item did: the `catalyzed` and `thisWeek` scenarios are ABOUT
    // the clones, and on 2026-09-09 not one of them was in the pool.
    assert.strictEqual(chosen.filter((c) => c.catalyst).length, 5, 'the five inactive clones');
    for (let i = 0; i < 5; i++) assert.ok(chosen[i].catalyst, `position ${i} should be a clone`);
    assert.strictEqual(plan.excluded.filter((c) => c.catalyst).length, 0, 'no clone is left out');
});

test('C-8: nothing that arrived active is ever deselected', () => {
    // The issue asked for active bag items to be deselected to make room. There
    // are none: `SimCImportEngine.ts` line 712 makes equipped items and VAULT
    // items active at import, and `Item.ts` line 174 gives a clone its source's
    // flag. Deselecting one would drop the character's own gear out of the pool.
    const cards = ownersPage({ clones: 6 });
    const plan = forkLib.chooseSelection(cards, 30);
    for (const chosen of plan.activate) assert.strictEqual(chosen.active, false, chosen.name);
    for (const left of plan.excluded) assert.strictEqual(left.active, false, left.name);
    assert.strictEqual(plan.keep.length + plan.activate.length + plan.excluded.length, cards.length);
});

test('C-8: a cap already full selects nothing rather than trading one item for another', () => {
    const cards = ownersPage({ clones: 6 }).map((c, i) => ({ ...c, active: i < 30 }));
    const plan = forkLib.chooseSelection(cards, 30);
    assert.strictEqual(plan.room, 0);
    assert.deepStrictEqual(plan.activate, []);
    assert.strictEqual(plan.excluded.length, cards.length - 30);
});

test('C-8: bag items are taken a slot at a time, so a late slot is never starved', () => {
    // Page order is his slot list, Head first (TopGear.tsx line 791). Twelve
    // rings ahead of one weapon used to mean the weapon was never asked about.
    const cards = [];
    for (let i = 0; i < 12; i++) cards.push(card(cards.length, 'Finger', `ring ${i}`));
    cards.push(card(cards.length, 'Weapons', 'the one weapon'));
    cards.push(card(cards.length, 'Trinket', 'the one trinket'));
    const plan = forkLib.chooseSelection(cards, 3);
    assert.deepStrictEqual(
        plan.activate.map((c) => c.name),
        ['ring 0', 'the one weapon', 'the one trinket']
    );
    // And inside a slot his own order is kept.
    const wide = forkLib.chooseSelection(cards, 6);
    assert.deepStrictEqual(
        wide.activate.map((c) => c.name),
        ['ring 0', 'the one weapon', 'the one trinket', 'ring 1', 'ring 2', 'ring 3']
    );
});

test('C-8: a vault item that is somehow not active comes before every clone and every bag item', () => {
    const cards = [
        card(0, 'Head', 'equipped', { active: true }),
        card(1, 'Finger', 'a ring'),
        card(2, 'Shoulder', 'a clone', { catalyst: true }),
        card(3, 'Shoulder', 'the vault spaulders', { vault: true }),
    ];
    const plan = forkLib.chooseSelection(cards, 3);
    assert.deepStrictEqual(
        plan.activate.map((c) => c.name),
        ['the vault spaulders', 'a clone']
    );
    assert.deepStrictEqual(
        plan.excluded.map((c) => c.name),
        ['a ring']
    );
});

test('C-8: selectItems clicks exactly what the plan named and reports the leftovers', async () => {
    const cards = ownersPage({ clones: 6 });
    const page = fakeTopGearPage(cards, 30);
    const selection = await forkLib.selectItems(page, quietLog());
    assert.strictEqual(selection.selected, 30);
    assert.strictEqual(selection.cap, 30);
    assert.strictEqual(selection.cards, cards.length);
    assert.strictEqual(selection.clicked, 10);
    assert.strictEqual(selection.active, 20);
    assert.strictEqual(page.clicks.length, 10);
    // Every clicked card was inactive before the run, and the counter agrees.
    assert.strictEqual(page.count(), 30);
    // The leftovers are named, with the slot and the level QE Live's own card
    // carried, and every one of them is a bag item.
    assert.strictEqual(selection.excluded.length, cards.length - 30);
    for (const left of selection.excluded) {
        assert.strictEqual(left.vault, false);
        assert.strictEqual(left.catalyst, false);
        assert.ok(left.name.startsWith('bag '), left.name);
        assert.ok(left.slot.length > 0);
        assert.strictEqual(typeof left.level, 'number');
    }
});

test('C-8: a click that does not move his counter fails the run', async () => {
    // The failure this guards is a misread card: clicking one that is really
    // active DEselects it, and the run would then export a document about a
    // pool nobody chose. The fake makes it happen by lying about one card.
    const cards = ownersPage({});
    cards[25].active = true; // really active, reported as not
    const page = fakeTopGearPage(cards, 30);
    page.evaluate = async () => cards.map((c, i) => ({ ...c, active: i === 25 ? false : c.active }));
    await assert.rejects(
        () => forkLib.selectItems(page, quietLog()),
        (e) => {
            assert.strictEqual(e.code, forkLib.DRIVE);
            assert.match(e.message, /moved QE Live's counter/);
            assert.match(e.message, /refusing to run Top Gear/);
            return true;
        }
    );
});

test('C-8: a Top Gear page with no cards is a named failure, not an empty pool', async () => {
    const page = fakeTopGearPage([], 30);
    await assert.rejects(
        () => forkLib.selectItems(page, quietLog()),
        (e) => {
            assert.strictEqual(e.code, forkLib.DRIVE);
            assert.match(e.message, /no \.MuiCardActionArea-root cards at all/);
            return true;
        }
    );
});

test('C-8: what the driver reports as excluded is exactly what the verdict writer accepts', async () => {
    const page = fakeTopGearPage(ownersPage({ clones: 6 }), 30);
    const selection = await forkLib.selectItems(page, quietLog());
    const settings = { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: false };
    const text = luaWriter.render({
        writtenAt: '2026-09-10T00:00:00Z',
        companionVersion: '0.1.0',
        qeSettings: { autoUpgradeAll: false, autoUpgradeVault: false },
        excluded: selection.excluded,
        documents: [
            {
                kind: 'topgear',
                contentType: 'Dungeon',
                scenario: 'asOffered',
                qeSettings: settings,
                excluded: selection.excluded,
                json: '{}',
            },
        ],
    });
    assert.ok(text.includes('    excluded = {'), 'the file-level list');
    assert.ok(text.includes('            excluded = {'), "the document's own list");
    const first = selection.excluded[0];
    assert.ok(text.includes(`name = ${JSON.stringify(first.name)}`), text.slice(0, 600));
    assert.ok(text.includes(`slot = ${JSON.stringify(first.slot)}, name = ${JSON.stringify(first.name)}, level = ${first.level}`));
});
