// C-14a (WKE-626): a disabled `Go!` is explained in QE Live's own words.
//
// THE RUN THIS IS ABOUT. The owner refreshed on his level-81 Restoration Shaman
// in fresh Midnight leveling gear on 2026-09-22. The character stage passed
// (`Restoration Shaman (already)`), the profile imported whole - all sixteen
// worn slots, so C-14's empty-slot mirror had nothing to refuse - and the run
// then said:
//
//   top gear pool (pass 1): 25/30 selected of 25 cards (6 baseline, 19 clicked ...)
//   FAILED: QE Live's Go! button is disabled for this pool - 25 of 30 selected, 6 baseline
//
// Twenty-five cards out of thirty-three items: his importer keeps only items it
// knows, and leveling greens are mostly items it does not. No Feet card at all,
// so `checkSlots` reported Feet and the button stayed disabled - and the owner
// was told the button was disabled and nothing else.
//
// TWO PREMISES OF THE ISSUE ARE REFUTED HERE, both read out of the owner's own
// fork clone (read-only; nothing of it is copied into this repo):
//
//   * the words beside the button are NOT `Error: Add item - feet, finger,
//     weapon`. `t("TopGear.itemMissingError")` IS that string
//     (`locale/en/translate.json:595`) but it only ever reaches `checkSlots`'s
//     local `errorMessage` (`TopGear.tsx:351`, `:355`), whose `setErrorMessage`
//     is commented out at `:361` and whose state is rendered nowhere. The row
//     renders `getErrorMessage()` (`:367-389`), which builds `"Add "`.
//   * the slots are his DISPLAY names, not the SimC tokens: `getTranslatedSlotName`
//     (`locale/slotsLocale.ts`) gives Boots for `feet` and Ring for `finger`,
//     and the weapon branch (`:381-383`) appends a bare ` Weapon`.
//
// So his line reads `Add Boots, Ring,  Weapon`, double space and all, and a
// locator built on the expected prefix would have matched nothing on his page -
// the C-16b lesson over again. Every double below renders what his page
// renders, and the one that renders the OLD expectation is here to show the
// driver reading nothing from it.
//
// No browser is opened by anything in this file.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const forkLib = require('../lib/fork');
const profileLib = require('../lib/profile');
const statusLib = require('../lib/status');
const logLib = require('../lib/log');
const configLib = require('../lib/config');
const companion = require('../companion');

const REPO = path.join(__dirname, '..', '..', '..');
const CAPTURES = path.join(REPO, 'spec', 'fixtures', 'captures');
const FULL = fs.readFileSync(path.join(CAPTURES, 'Lootpath-20260906-200908.lua'), 'utf8');

// His own line, character for character: `"Add " + "Boots, " + "Ring, " + " Weapon, "`
// with the last two characters sliced off (`TopGear.tsx:385`).
const HIS_LINE = 'Add Boots, Ring,  Weapon';

function quietLog() {
    return logLib.make(() => {});
}

// ---------------------------------------------------------------------------
// The page, as his renders it.
//
// `TopGear.tsx:840-857` is one flex row: the `Selected Items` Typography, the
// error Typography (`variant="subtitle1"`, so MUI gives it
// `MuiTypography-subtitle1`), and a div holding the `Go!` Button. The double
// renders all three, plus `MiniItemCard.tsx:345`'s subtitle1 - which is `""`
// inside a `visibility: hidden` wrapper and is the only other one on the page -
// so the filter is asked the question the browser would be asked.
//
// `filter({ hasText })` is Playwright's own contract: the regex is matched
// against the element's TEXT. An element the filter drops is not in the
// collection at all, which is what `count()` answers.
function goRow(options) {
    const opts = options || {};
    const subtitles = [];
    // Every card's hidden, empty subtitle1 first, exactly where his page puts
    // them: above the bar, and there are as many as there are cards.
    for (let i = 0; i < (opts.cards === undefined ? 25 : opts.cards); i++) subtitles.push('""');
    if (opts.error !== null) subtitles.push(opts.error === undefined ? HIS_LINE : opts.error);
    const page = {
        subtitles,
        clicks: 0,
        getByRole(role, o) {
            assert.strictEqual(role, 'button');
            assert.strictEqual(o.name, 'Go!');
            return {
                async isEnabled() {
                    return opts.enabled === true;
                },
                async click() {
                    page.clicks++;
                },
            };
        },
        locator(selector) {
            assert.strictEqual(selector, forkLib.GO_ERROR, 'the error is read off the class MUI gives subtitle1');
            const all = subtitles;
            return {
                filter(f) {
                    const kept = all.filter((text) => f.hasText.test(text));
                    return {
                        async count() {
                            return kept.length;
                        },
                        first() {
                            return {
                                async innerText() {
                                    if (!kept.length) throw new Error('no such element');
                                    return kept[0];
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

// ---------------------------------------------------------------------------
// The words, parsed.

test('C-14a: his real line is read as the slots he named, in his order and his words', () => {
    assert.deepStrictEqual(forkLib.goErrorSlots(HIS_LINE), ['Boots', 'Ring', 'Weapon']);
    // One slot, which is the 2026-09-16 shape (`checkSlots` found Legs alone).
    assert.deepStrictEqual(forkLib.goErrorSlots('Add Legs'), ['Legs']);
    assert.deepStrictEqual(forkLib.goErrorSlots('Add Boots, Ring'), ['Boots', 'Ring']);
});

test('C-14a: the prefix the issue expected is not on his page, and reads as no slots at all', () => {
    // `Error: Add item - ` never reaches the DOM (see the header). Anything but
    // his own `Add ` answers nothing rather than a slot list invented from it.
    assert.deepStrictEqual(forkLib.goErrorSlots('Error: Add item - feet, finger, weapon'), []);
    assert.deepStrictEqual(forkLib.goErrorSlots(''), []);
    assert.deepStrictEqual(forkLib.goErrorSlots('Selected Items: 25/30'), []);
    assert.deepStrictEqual(forkLib.goErrorSlots(undefined), []);
    // `getErrorMessage`'s other branch (`:370-372`): more than ten missing
    // slots is "you imported nothing", not a list of slots.
    assert.deepStrictEqual(forkLib.goErrorSlots('Add Import String'), []);
});

// ---------------------------------------------------------------------------
// The refusal.

test('C-14a: a disabled Go! is refused with the slots QE Live named and its line verbatim', async () => {
    const page = goRow({ enabled: false });
    await assert.rejects(
        () => forkLib.clickGo(page, 'for this pool - 25 of 30 selected, 6 baseline'),
        (e) => {
            assert.strictEqual(e.code, forkLib.REFUSED, 'the profile is what is wrong, not the fork');
            assert.strictEqual(
                e.message,
                "QE Live's Go! button is disabled for this pool - 25 of 30 selected, 6 baseline" +
                    ' - it wants an item in: Boots, Ring, Weapon (its own words: "Add Boots, Ring, Weapon")'
            );
            assert.ok(!e.message.includes('\n'), 'a refusal is still one line');
            return true;
        }
    );
    assert.strictEqual(page.clicks, 0, 'nothing was submitted');
});

test("C-14a: a page that says nothing gives exactly the line C-14 has always given", async () => {
    for (const words of [null, '', 'Error: Add item - feet, finger, weapon']) {
        const page = goRow({ enabled: false, error: words });
        await assert.rejects(
            () => forkLib.clickGo(page, 'for this pool - 25 of 30 selected, 6 baseline'),
            (e) => {
                assert.strictEqual(
                    e.message,
                    "QE Live's Go! button is disabled for this pool - 25 of 30 selected, 6 baseline"
                );
                assert.strictEqual(e.playerMessage, undefined, 'nothing read means nothing new to say');
                return true;
            }
        );
    }
});

test('C-14a: an enabled Go! is clicked and its row is never read', async () => {
    const page = goRow({ enabled: true, error: null });
    await forkLib.clickGo(page, 'for this pool - 30 of 30 selected, 19 baseline');
    assert.strictEqual(page.clicks, 1);
});

test('C-14a: the hidden empty subtitle1 on every card is not mistaken for his error', async () => {
    const page = goRow({ enabled: false, error: null, cards: 57 });
    assert.strictEqual(await forkLib.readGoError(page), '');
});

test('C-14a: his double space is collapsed, because a status file is one sentence', async () => {
    assert.strictEqual(await forkLib.readGoError(goRow({ enabled: false })), 'Add Boots, Ring, Weapon');
});

// ---------------------------------------------------------------------------
// What QE Live did not take.

test('C-14a: the items the profile sent are read with their names and their identity', () => {
    const built = profileLib.build(FULL, { includeBank: true });
    assert.ok(built.ok, built.ok ? '' : built.reason);
    const items = forkLib.profileItems(built.text);
    // Every item line in the profile, equipped and bagged and vault alike.
    assert.strictEqual(items.length, built.counts.equipped + built.counts.bag + built.counts.bank + built.counts.vault);
    // The name is the `# Name (level)` comment the builder writes above each
    // line - the profile's item lines carry no name of their own (his own read
    // is `feet=,id=235964`), which is why the match below is by identity.
    const named = items.filter((item) => item.name);
    assert.ok(named.length > 0, 'the builder writes a comment above every item it has a name for');
    for (const item of named) assert.ok(item.level > 0, `${item.name} has a level`);
    assert.ok(
        items.every((item) => /^\d+(:\d+)*$/.test(item.key)),
        'the key is the item ID and its sorted bonus IDs, the same one ns.ItemKey is built from'
    );
});

test("C-14a: the drop is a multiset difference by identity, and names what QE Live left behind", () => {
    const profile = [
        '# Nameless - restoration - 2026-09-22 15:45 - us/realm',
        '# generated',
        '# WoW 12.0.0, TOC 120000',
        '# Inventory captured 2026-09-22T15:45:10',
        '',
        'shaman="Blueheeler"',
        'level=81',
        'spec=restoration',
        '',
        '# Mysterious Hood (126)',
        'head=,id=235950,bonus_id=3/1',
        '# Mysterious Striders (139)',
        'feet=,id=235964',
        '# Band of Sameness (120)',
        'finger1=,id=111,bonus_id=7',
        '# Band of Sameness (120)',
        'finger2=,id=111,bonus_id=7',
        '# Waterspeaker\'s Cowl (139)',
        'head=,id=777',
        '# Waterspeaker\'s Cowl (139)',
        'head=,id=777',
        '',
    ].join('\n');
    // QE Live kept the hood, exactly ONE of the two identical rings, and one of
    // the two identical tier helms. The bonus IDs come back in his own order,
    // which is why the key sorts. The last card is a Catalyst CLONE of the hood
    // - `convertToTier` puts the tier piece's own ID on it (Item.ts:268), which
    // here is the very helm the character already owns two of. It is his
    // invention and never one of the items sent, so it must not stand in for
    // the copy he dropped.
    const cards = [
        { slot: 'Head', name: 'Mysterious Hood', level: 126, itemID: 235950, bonusIDs: [3, 1], catalyst: false },
        { slot: 'Finger', name: 'Band of Sameness', level: 120, itemID: 111, bonusIDs: [7], catalyst: false },
        { slot: 'Head', name: "Waterspeaker's Cowl", level: 139, itemID: 777, bonusIDs: [], catalyst: false },
        { slot: 'Head', name: "Waterspeaker's Cowl", level: 139, itemID: 777, bonusIDs: [], catalyst: true, originalItem: 235950 },
    ];
    const drop = forkLib.poolDrop(profile, cards);
    assert.strictEqual(drop.sent, 6);
    assert.strictEqual(drop.taken, 3);
    assert.deepStrictEqual(
        drop.missing.map((item) => item.name),
        ['Mysterious Striders', 'Band of Sameness', "Waterspeaker's Cowl"],
        "in the profile's own order, and the SECOND of each pair is the one left over"
    );
    assert.strictEqual(
        forkLib.dropLine(drop),
        'QE Live did not take 3 of 6 imported items: Mysterious Striders (139), Band of Sameness (120),' +
            " Waterspeaker's Cowl (139)"
    );
});

test('C-14a: a pool that kept everything says nothing at all', () => {
    const profile = ['shaman="X"', '', '# Mysterious Hood (126)', 'head=,id=235950,bonus_id=3/1', ''].join('\n');
    const cards = [{ slot: 'Head', name: 'Mysterious Hood', level: 126, itemID: 235950, bonusIDs: [1, 3], catalyst: false }];
    const drop = forkLib.poolDrop(profile, cards);
    assert.strictEqual(drop.sent, 1);
    assert.strictEqual(drop.taken, 1);
    assert.deepStrictEqual(drop.missing, []);
    assert.strictEqual(forkLib.dropLine(drop), null, 'no line rather than a line saying nought');
});

test('C-14a: the log line names fifteen and counts the rest', () => {
    const lines = ['shaman="X"', ''];
    for (let i = 0; i < 20; i++) {
        lines.push(`# Thing ${i} (100)`);
        lines.push(`trinket1=,id=${1000 + i}`);
    }
    const drop = forkLib.poolDrop(lines.join('\n'), []);
    assert.strictEqual(drop.sent, 20);
    const line = forkLib.dropLine(drop);
    assert.ok(line.startsWith('QE Live did not take 20 of 20 imported items: Thing 0 (100), '));
    assert.ok(line.endsWith(', and 5 more'), 'one line, whatever the bags hold');
});

// ---------------------------------------------------------------------------
// What the player is told.
//
// The status file's `message` is the only one of the three surfaces that
// carries it: `ns.Companion.StatusTooltip` (Lootpath/Modules/Companion.lua)
// prints it on the status strip's tooltip. The strip's own clause and the
// chat line both say `FAILED at qe live` and never the message - read
// 2026-09-22 in `Companion.StatusText` and `Drift.LOAD_FAILED`. Nothing in the
// addon changes for this.

test('C-14a: the player sentence names no source and says nothing about a plan', () => {
    const sentence = forkLib.goRefusalForPlayer(['Boots', 'Ring', 'Weapon'], { sent: 33, missing: new Array(8) });
    assert.strictEqual(
        sentence,
        "couldn't rate this gear: no usable item in Boots, Ring, Weapon - 8 of the 33 pieces sent weren't recognised"
    );
    assert.ok(!/QE Live|QuestionablyEpic|fork/i.test(sentence), 'no source is ever named on screen');
    assert.ok(!/\bplans?\b/i.test(sentence), 'the word is banned on screen');
    assert.ok(sentence.length <= statusLib.MESSAGE_MAX, 'it reaches the tooltip whole');
    // No drop count read - a pass whose import was never probed - and the
    // sentence is the half that is known rather than a figure nobody measured.
    assert.strictEqual(
        forkLib.goRefusalForPlayer(['Boots'], null),
        "couldn't rate this gear: no usable item in Boots"
    );
});

// The whole wiring, over a real `once()`: the log keeps QE Live's line and the
// status file gets the player's.
function harness() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c14a-'));
    const dir = path.join(root, 'WTF', 'Account', 'TESTACCOUNT#1', 'SavedVariables');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'Lootpath.lua'), FULL, 'utf8');
    const dataDir = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data');
    fs.mkdirSync(dataDir, { recursive: true });
    const config = { ...configLib.DEFAULTS, wowPath: root, stateDir: path.join(root, 'state'), includeBank: true };
    const statusFile = path.join(dataDir, configLib.STATUS_FILE);
    const lines = [];
    const log = logLib.make((line) => lines.push(line));
    const status = statusLib.make({
        file: statusFile,
        companionVersion: companion.VERSION,
        onError: (e) => {
            throw e;
        },
    });
    return {
        logText: () => lines.join('\n'),
        statusText: () => fs.readFileSync(statusFile, 'utf8'),
        run: (fork) => companion.once(config, log, { watch: false, profileOnly: false, force: true }, { fork, status }),
    };
}

test('C-14a: the log says QE Live and the status file does not', async () => {
    const h = harness();
    const fork = {
        async run() {
            throw new forkLib.ForkError(
                "QE Live's Go! button is disabled for this pool - 25 of 30 selected, 6 baseline" +
                    ' - it wants an item in: Boots, Ring, Weapon (its own words: "Add Boots, Ring, Weapon")',
                forkLib.REFUSED,
                "couldn't rate this gear: no usable item in Boots, Ring, Weapon - 8 of the 33 pieces sent weren't recognised"
            );
        },
    };
    const code = await h.run(fork);
    assert.strictEqual(code, 5, 'a refusal is still exit 5');
    assert.ok(h.logText().includes('its own words: "Add Boots, Ring, Weapon"'), 'the log carries his line');
    const written = h.statusText();
    assert.ok(
        written.includes('message = "couldn\'t rate this gear: no usable item in Boots, Ring, Weapon'),
        'the file carries the player sentence'
    );
    assert.ok(!written.includes('QE Live'), 'and never names the source');
    assert.ok(written.includes('exitCode = 5'));
});

test('C-14a: a failure with no player sentence is written exactly as it always was', async () => {
    const h = harness();
    const fork = {
        async run() {
            throw new forkLib.ForkError('playwright is not installed; run "npm install" in tools/companion', forkLib.DRIVE);
        },
    };
    const code = await h.run(fork);
    assert.strictEqual(code, 4);
    assert.ok(h.statusText().includes('message = "playwright is not installed'));
});

// ---------------------------------------------------------------------------
// C-14b (WKE-627): the same refusal as DATA.
//
// C-14a put the cause into the status file as one string, and a string is a
// sentence for a tooltip. It cannot be the thing a SCREEN is chosen by - that
// is the rule R-7b wrote when it told C-4's skip from an empty read by its exit
// code, and C-14 for the third skip. So the driver hands the failure over as
// fields as well, `message` unchanged, and the addon switches on the token.

test('C-14b: the refusal carries the reason, the slots and the two counts', () => {
    const fields = forkLib.goRefusalFields(['Boots', 'Ring', 'Weapon'], { sent: 33, missing: new Array(8) });
    assert.deepStrictEqual(fields, {
        reason: 'unknown-gear',
        missingSlots: ['Boots', 'Ring', 'Weapon'],
        sent: 33,
        notTaken: 8,
    });
    assert.strictEqual(fields.reason, forkLib.REASON_UNKNOWN_GEAR);
    assert.ok(statusLib.REASONS.includes(fields.reason), 'the writer will accept it');
    // No drop read - a pass whose import was never probed - and the counts are
    // left out rather than made up, exactly as the sentence leaves them out.
    assert.deepStrictEqual(forkLib.goRefusalFields(['Boots'], null), {
        reason: 'unknown-gear',
        missingSlots: ['Boots'],
    });
    // The slots are copied, so nothing downstream can edit the driver's list.
    const slots = ['Boots'];
    forkLib.goRefusalFields(slots, null).missingSlots.push('Ring');
    assert.deepStrictEqual(slots, ['Boots']);
});

test('C-14b: a disabled Go! throws the fields beside the sentence', async () => {
    const page = goRow({ enabled: false });
    await assert.rejects(
        () => forkLib.clickGo(page, 'for this pool', { drop: { sent: 33, missing: new Array(8) } }),
        (e) => {
            assert.strictEqual(e.playerFields.reason, 'unknown-gear');
            assert.deepStrictEqual(e.playerFields.missingSlots, ['Boots', 'Ring', 'Weapon']);
            assert.strictEqual(e.playerFields.sent, 33);
            assert.strictEqual(e.playerFields.notTaken, 8);
            // C-14a's sentence is untouched by any of it.
            assert.strictEqual(
                e.playerMessage,
                "couldn't rate this gear: no usable item in Boots, Ring, Weapon" +
                    " - 8 of the 33 pieces sent weren't recognised"
            );
            return true;
        }
    );
});

test('C-14b: a refusal his page said nothing about carries no fields at all', async () => {
    const page = goRow({ enabled: false, error: null });
    await assert.rejects(
        () => forkLib.clickGo(page, 'for this pool'),
        (e) => {
            assert.strictEqual(e.playerFields, undefined, 'nothing read means nothing to write');
            return true;
        }
    );
});

test('C-14b: the status file carries the four fields, and the log still names QE Live', async () => {
    const h = harness();
    const fork = {
        async run() {
            throw new forkLib.ForkError(
                "QE Live's Go! button is disabled for this pool - it wants an item in: Cape, Chest",
                forkLib.REFUSED,
                "couldn't rate this gear: no usable item in Cape, Chest - 17 of the 32 pieces sent weren't recognised",
                { reason: 'unknown-gear', missingSlots: ['Cape', 'Chest'], sent: 32, notTaken: 17 }
            );
        },
    };
    assert.strictEqual(await h.run(fork), 5);
    const written = h.statusText();
    assert.ok(written.includes('reason = "unknown-gear",'));
    assert.ok(written.includes('missingSlots = { "Cape", "Chest" },'));
    assert.ok(written.includes('sent = 32,'));
    assert.ok(written.includes('notTaken = 17,'));
    assert.ok(written.includes('message = "couldn\'t rate this gear: no usable item in Cape, Chest'));
    assert.ok(!written.includes('QE Live'), 'the file still names no source');
    assert.ok(h.logText().includes("QE Live's Go! button is disabled"), 'the log still does');
});

test('C-14b: any other failure writes none of them, byte for byte as before', async () => {
    const h = harness();
    const fork = {
        async run() {
            throw new forkLib.ForkError('playwright is not installed; run "npm install" in tools/companion', forkLib.DRIVE);
        },
    };
    assert.strictEqual(await h.run(fork), 4);
    const written = h.statusText();
    assert.ok(written.includes('message = "playwright is not installed'));
    for (const field of ['reason', 'missingSlots', 'sent', 'notTaken']) {
        assert.ok(!written.includes(`${field} =`), `${field} is not written for a failure that has none`);
    }
});

test('C-14b: a reason the addon does not know is refused rather than written', () => {
    assert.throws(
        () => statusLib.render({ state: 'failed', reason: 'gremlins' }),
        /refusing to write status reason "gremlins"/
    );
    assert.throws(
        () => statusLib.render({ state: 'failed', reason: 'unknown-gear', missingSlots: ['Cape', 7] }),
        /refusing to write missingSlots entry 7/
    );
    assert.throws(() => statusLib.render({ state: 'failed', sent: -1 }), /refusing to write sent -1/);
    assert.throws(() => statusLib.render({ state: 'failed', notTaken: 1.5 }), /refusing to write notTaken 1.5/);
    // An empty list is not written: "none were named" is what absent says.
    assert.ok(!statusLib.render({ state: 'failed', missingSlots: [] }).includes('missingSlots'));
});

test('C-14b: the next run clears them, so yesterday\'s reason never stands over today', () => {
    const status = statusLib.make({ file: null, companionVersion: '0.1.0' });
    status.failed('qe live', 'refused', 5, { reason: 'unknown-gear', missingSlots: ['Cape'], sent: 32, notTaken: 17 });
    assert.strictEqual(status.current().reason, 'unknown-gear');
    status.started({});
    for (const field of ['reason', 'missingSlots', 'sent', 'notTaken']) {
        assert.strictEqual(status.current()[field], undefined, `${field} is cleared when a run begins`);
    }
    // And a second failure with nothing to say clears what the first one said.
    status.failed('qe live', 'refused', 5, { reason: 'unknown-gear', missingSlots: ['Cape'] });
    status.failed('profile', 'something else', 3);
    assert.strictEqual(status.current().reason, undefined);
    assert.strictEqual(status.current().missingSlots, undefined);
});
