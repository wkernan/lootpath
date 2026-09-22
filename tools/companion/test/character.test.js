// C-16 (WKE-619): the driver puts QE Live on the profile's class and spec
// before it imports.
//
// QE Live holds ONE active character and refuses a SimC string for any other
// (`SimCImportEngine.ts` lines 354 and 360). The driver never set it, so the
// owner's Restoration Shaman was told `You're currently a Restoration Druid but
// this SimC string is for a different spec.` twice on 2026-09-18 and no Shaman
// rating was ever written.
//
// Nothing here opens a browser. The page below is a fake QE Live: a header with
// the two "Current Spec" controls his own `QEHeader.js` renders (the mobile
// drawer is `keepMounted`, so one of them is always hidden), the menu that
// control opens, and an import dialog that checks the class the way his engine
// does. The owner's own companion and fork may be running in other windows and
// nothing in this file goes near either.
'use strict';

const test = require('node:test');
const assert = require('node:assert');

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const companion = require('../companion');
const forkLib = require('../lib/fork');
const statusLib = require('../lib/status');
const configLib = require('../lib/config');
const logLib = require('../lib/log');

// His retail menu, `QEHeaderClassSelector.js` lines 15-23, in his order.
const HIS_SPECS = [
    'Restoration Druid',
    'Holy Priest',
    'Discipline Priest',
    'Restoration Shaman',
    'Holy Paladin',
    'Mistweaver Monk',
    'Preservation Evoker',
];

const DRUID = { name: 'Hotornot', realm: 'Area 52', class: 'DRUID', spec: 'Restoration' };
const SHAMAN = { name: 'Bolts', realm: 'Area 52', class: 'SHAMAN', spec: 'Restoration' };

// A fake QE Live page. `events` is every act in the order it happened, which is
// what proves the switch is asked for BEFORE the import rather than beside it.
//
// Since C-16b the menu below is rendered the way MUI and his own `MenuItem`
// render it, because C-16's double rendered neither and eight red guards passed
// over a driver that could not find a single option on his real page:
//
//   * an option's accessible NAME is the spec twice over. His `MenuItem` holds
//     `<ClassIcon>`, which is an `<img alt="Restoration Shaman">`
//     (ClassIcons.tsx lines 27-33 and 71-80), and an `<img alt>` inside an
//     element contributes its alt to that element's accessible name, beside the
//     `Typography` that carries the same words.
//   * an option's visible TEXT is the spec once. Alt is not text.
//   * neither exists at the moment the control's `click()` resolves: MUI mounts
//     the `Menu` popover a tick later.
function fakePage(options) {
    const opts = options || {};
    const events = [];
    let spec = opts.spec || 'Restoration Druid';
    let mounted = false;
    let refusal = null;
    let submitted = null;
    // A string is one of his retail entries: the words once, the accessible
    // name twice. An object states both halves itself.
    const specs = (opts.specs || HIS_SPECS).map((entry) =>
        typeof entry === 'string' ? { text: entry, name: entry + ' ' + entry, value: entry } : entry
    );

    // One turn of the event loop, which is all his popover costs.
    const tick = () => new Promise((resolve) => setImmediate(resolve));

    const selectAt = (index) => ({
        // The mobile drawer's copy is index 0 and is display:none at every
        // width; the desktop copy is index 1.
        async isVisible() {
            return index === (opts.visibleIndex === undefined ? 1 : opts.visibleIndex);
        },
        async innerText() {
            return spec;
        },
        async click() {
            events.push('spec menu opened');
            // His options are NOT in the DOM when this resolves.
            if (opts.menuNeverOpens) return;
            const ticks = opts.optionTicks === undefined ? 2 : opts.optionTicks;
            (async () => {
                for (let i = 0; i < ticks; i++) await tick();
                mounted = true;
                events.push('menu open');
            })();
        },
    });

    const never = () => new Promise(() => {});

    const page = {
        events: events,
        get spec() {
            return spec;
        },
        get submitted() {
            return submitted;
        },
        // What this page renders for an option, so a guard can say it rather
        // than assume it: the accessible name (alt + words) and the text.
        optionNameOf(value) {
            return (specs.find((o) => o.value === value) || {}).name;
        },
        optionTextOf(value) {
            return (specs.find((o) => o.value === value) || {}).text;
        },
        getByLabel(name, options) {
            assert.strictEqual(name, forkLib.CURRENT_SPEC_LABEL);
            assert.strictEqual(options.exact, true);
            const total = opts.labels === undefined ? 2 : opts.labels;
            return {
                async count() {
                    return total;
                },
                nth: selectAt,
            };
        },
        getByRole(role, options) {
            if (role === 'listbox') {
                return {
                    first() {
                        return this;
                    },
                    // Playwright's own `waitFor`: it polls, and it rejects when
                    // the bound is reached. The bound is asserted to be a real,
                    // finite one rather than waited out in real time, so a menu
                    // that never opens costs this test a few ticks and not the
                    // driver's ten seconds.
                    async waitFor(waitOptions) {
                        assert.strictEqual(waitOptions.state, 'visible');
                        assert.ok(
                            Number.isFinite(waitOptions.timeout) && waitOptions.timeout > 0,
                            'the wait for his menu is bounded'
                        );
                        for (let i = 0; i < 50; i++) {
                            if (mounted) return undefined;
                            await tick();
                        }
                        const e = new Error(
                            `Timeout ${waitOptions.timeout}ms exceeded waiting for getByRole('listbox').first()`
                        );
                        e.name = 'TimeoutError';
                        throw e;
                    },
                };
            }
            if (role === 'option') {
                // The words, never the accessible name: the driver may not ask
                // this page for an option BY NAME any more, because on his own
                // page that name is doubled.
                assert.strictEqual(options, undefined, 'options are found by their visible words');
                const lens = (match) => ({
                    filter(f) {
                        assert.ok(
                            f && f.hasText instanceof RegExp,
                            'the filter is a regular expression over the visible words'
                        );
                        return lens((option) => match(option) && f.hasText.test(option.text));
                    },
                    async count() {
                        events.push(mounted ? 'options counted' : 'options counted before the menu opened');
                        return mounted ? specs.filter(match).length : 0;
                    },
                    first() {
                        const picked = mounted ? specs.filter(match)[0] : undefined;
                        return {
                            async click() {
                                assert.ok(picked, 'the driver clicked an option that is not there');
                                events.push(`spec picked: ${picked.value}`);
                                mounted = false;
                                // His `handlePickPlayerSpec` makes the
                                // character of that spec active (App.tsx:273).
                                if (!opts.stuck) spec = picked.value;
                            },
                        };
                    },
                });
                return lens(() => true);
            }
            if (role === 'checkbox') {
                return {
                    async count() {
                        return 1;
                    },
                    async isChecked() {
                        return false;
                    },
                    async click() {},
                };
            }
            if (role === 'button') {
                return {
                    async click() {
                        events.push('submit');
                        // `checkSimCValid` line 354: the header's class line
                        // against the active character's spec string.
                        const klass = /^([a-z]+)=/m.exec(submitted || '');
                        const ok = klass && spec.toLowerCase().includes(klass[1].toLowerCase());
                        refusal = ok
                            ? null
                            : `You're currently a ${spec} but this SimC string is for a different spec.`;
                    },
                    first() {
                        return this;
                    },
                };
            }
            throw new Error(`the fake page was asked for role ${role}`);
        },
        getByText(what) {
            const text = String(what);
            return {
                first() {
                    return this;
                },
                async count() {
                    return 1;
                },
                async click() {
                    events.push(`clicked ${text}`);
                },
            };
        },
        locator(selector) {
            if (selector === '#simcentry') {
                return {
                    async waitFor(state) {
                        if (state && state.state === 'hidden') {
                            if (refusal) return never();
                            return undefined;
                        }
                        return undefined;
                    },
                    async fill(value) {
                        events.push('profile pasted');
                        submitted = value;
                    },
                };
            }
            if (selector === '#SimCError') {
                return {
                    filter() {
                        return {
                            async waitFor() {
                                if (!refusal) return never();
                                return undefined;
                            },
                        };
                    },
                    async innerText() {
                        return refusal || '';
                    },
                };
            }
            throw new Error(`the fake page was asked for ${selector}`);
        },
    };
    return page;
}

// The SimC header the profile builder writes: the class line is the class's own
// word, which is what his engine matches on.
const SHAMAN_PROFILE = 'shaman="Bolts"\nlevel=80\nspec=restoration\n';

function quietLog() {
    return logLib.make(() => {});
}

// --- his name for a character, built from the client's two halves ------------

test("QE Live's name for a character is the spec's name and the class's word", () => {
    assert.strictEqual(forkLib.qeSpecOf(SHAMAN), 'Restoration Shaman');
    assert.strictEqual(forkLib.qeSpecOf(DRUID), 'Restoration Druid');
    assert.strictEqual(forkLib.qeSpecOf({ class: 'PRIEST', spec: 'Discipline' }), 'Discipline Priest');
    assert.strictEqual(forkLib.qeSpecOf({ class: 'EVOKER', spec: 'Preservation' }), 'Preservation Evoker');
    // Every name it builds for a healer is one QE Live's own menu offers.
    for (const token of Object.keys(forkLib.QE_CLASS_WORD)) {
        const specs = HIS_SPECS.filter((name) => name.endsWith(' ' + forkLib.QE_CLASS_WORD[token]));
        assert.ok(specs.length, token);
        for (const name of specs) {
            const spec = name.slice(0, name.length - forkLib.QE_CLASS_WORD[token].length - 1);
            assert.strictEqual(forkLib.qeSpecOf({ class: token, spec: spec }), name);
        }
    }
    // A capture that names no CLASS is nothing, never a guess.
    assert.strictEqual(forkLib.qeSpecOf({ spec: 'Restoration' }), null);
    assert.strictEqual(forkLib.qeSpecOf(null), null);
});

// --- the class-only fallback (C-16a, WKE-622) --------------------------------
//
// Until C-16a a capture that named the class but no spec was `null` here too,
// and a spec-less capture is what every run gets: a flush `env` names no spec
// and the newest `env` is always a flush. The spec is now read off the newest
// capture that NAMES one (`characterSpec`, simc-profile.js) - but the addon
// keeps four snapshots (`ns.CAPTURE_HISTORY`, Core.lua), so four flushes after
// the last refresh there is genuinely no spec anywhere, and this is what
// happens then.

test('a class with exactly one healer needs no spec named; the Priest has two and is refused', () => {
    // The table is not a table of ours. It is derived here from HIS OWN menu,
    // so the two can never drift: for each class word, the specs his retail
    // list offers for it.
    const hisSpecsByClass = {};
    for (const token of Object.keys(forkLib.QE_CLASS_WORD)) {
        const word = forkLib.QE_CLASS_WORD[token];
        hisSpecsByClass[token] = HIS_SPECS.filter((name) => name.endsWith(' ' + word)).map((name) =>
            name.slice(0, name.length - word.length - 1)
        );
    }
    // Five classes with one healer each, and the Priest with two.
    assert.deepStrictEqual(
        Object.keys(hisSpecsByClass).filter((token) => hisSpecsByClass[token].length !== 1),
        ['PRIEST']
    );
    assert.deepStrictEqual(hisSpecsByClass.PRIEST.slice().sort(), ['Discipline', 'Holy']);

    // And `QE_CLASS_SOLE_SPEC` is exactly those five, with his own spec words.
    const derived = {};
    for (const token of Object.keys(hisSpecsByClass)) {
        if (hisSpecsByClass[token].length === 1) derived[token] = hisSpecsByClass[token][0];
    }
    assert.deepStrictEqual(forkLib.QE_CLASS_SOLE_SPEC, derived);

    // So a spec-less capture of any of the five names one of his characters...
    assert.strictEqual(forkLib.qeSpecOf({ class: 'SHAMAN' }), 'Restoration Shaman');
    assert.strictEqual(forkLib.qeSpecOf({ class: 'DRUID' }), 'Restoration Druid');
    assert.strictEqual(forkLib.qeSpecOf({ class: 'PALADIN' }), 'Holy Paladin');
    assert.strictEqual(forkLib.qeSpecOf({ class: 'MONK' }), 'Mistweaver Monk');
    assert.strictEqual(forkLib.qeSpecOf({ class: 'EVOKER' }), 'Preservation Evoker');
    for (const token of Object.keys(forkLib.QE_CLASS_SOLE_SPEC)) {
        assert.ok(HIS_SPECS.includes(forkLib.qeSpecOf({ class: token })), token);
    }
    // ...and a spec-less Priest names none, because two of them would do.
    assert.strictEqual(forkLib.qeSpecOf({ class: 'PRIEST' }), null);
    // A Priest whose capture DOES name a spec is untouched by any of this.
    assert.strictEqual(forkLib.qeSpecOf({ class: 'PRIEST', spec: 'Holy' }), 'Holy Priest');
});

test('a Priest whose captures name no spec is refused before the browser is opened', async () => {
    // Nothing answers this URL and `startFork` is false, so if the refusal were
    // not first the failure would be `fork-unreachable` instead.
    const config = { ...configLib.load(null), forkUrl: 'http://127.0.0.1:9/nothing', startFork: false };
    await assert.rejects(
        () => forkLib.run(config, SHAMAN_PROFILE, quietLog(), { identity: { name: 'Vows', realm: 'Arthas', class: 'PRIEST' } }),
        (e) => {
            assert.strictEqual(e.code, forkLib.REFUSED, 'exit 5, and not the unreachable fork');
            assert.strictEqual(e.message, "no capture names this Priest's spec - /lootpath refresh in the spec you heal in");
            return true;
        }
    );

    // A capture too old to name the class at all is still not a refusal: it is
    // `character: not named by the capture`, and the import speaks for itself.
    assert.strictEqual(forkLib.qeSpecOf({ name: 'Vows' }), null);
});

test('the welcome tile and the menu item come from the same name', () => {
    // `Welcome.tsx:72-76`: the priests are two tiles with one class word, so the
    // class TOKEN the driver used before C-16 named neither of them.
    assert.strictEqual(forkLib.welcomeTileLabel('Holy Priest'), 'H Priest');
    assert.strictEqual(forkLib.welcomeTileLabel('Discipline Priest'), 'D Priest');
    assert.strictEqual(forkLib.welcomeTileLabel('Restoration Shaman'), 'Shaman');
    assert.strictEqual(forkLib.welcomeTileLabel('Preservation Evoker'), 'Evoker');
    assert.strictEqual(forkLib.welcomeTileLabel('Mistweaver Monk'), 'Monk');
});

// --- the page reporting the profile's own character -------------------------

test('a page already on the profile\'s character is left alone, and says "already"', async () => {
    const page = fakePage({ spec: 'Restoration Druid' });
    const character = await forkLib.ensureCharacter(page, DRUID);
    assert.deepStrictEqual(character, {
        spec: 'Restoration Druid',
        was: 'Restoration Druid',
        switched: false,
        note: 'Restoration Druid (already)',
    });
    assert.deepStrictEqual(page.events, [], 'nothing on his page was touched');
});

// --- the page reporting another ---------------------------------------------

test("a page on another character is switched through QE Live's own control, and says which way", async () => {
    const page = fakePage({ spec: 'Restoration Druid' });
    const character = await forkLib.ensureCharacter(page, SHAMAN);
    assert.deepStrictEqual(character, {
        spec: 'Restoration Shaman',
        was: 'Restoration Druid',
        switched: true,
        note: 'Restoration Shaman (switched from Restoration Druid)',
    });
    assert.strictEqual(page.spec, 'Restoration Shaman');
    assert.deepStrictEqual(page.events, [
        'spec menu opened',
        'menu open',
        'options counted',
        'spec picked: Restoration Shaman',
    ]);
});

test('the switch is asked for before the import, and the import only passes because of it', async () => {
    const page = fakePage({ spec: 'Restoration Druid' });
    await forkLib.ensureCharacter(page, SHAMAN);
    await forkLib.importProfile(page, SHAMAN_PROFILE, {}, quietLog());
    assert.deepStrictEqual(page.events, [
        'spec menu opened',
        'menu open',
        'options counted',
        'spec picked: Restoration Shaman',
        'clicked /import gear/i',
        'profile pasted',
        'submit',
    ]);
});

test("without the switch that same import is QE Live's own refusal, unchanged", async () => {
    // The 2026-09-18 log, twice. `REFUSED` is exit 5 and the message is his.
    const page = fakePage({ spec: 'Restoration Druid' });
    await assert.rejects(
        () => forkLib.importProfile(page, SHAMAN_PROFILE, {}, quietLog()),
        (e) => {
            assert.strictEqual(e.code, forkLib.REFUSED);
            assert.strictEqual(
                e.message,
                "QE Live refused the profile: You're currently a Restoration Druid but this SimC string is for a different spec."
            );
            return true;
        }
    );
});

// --- the switch failing ------------------------------------------------------

test('a "different spec" refusal after the switch is still one refusal, and the driver does not loop', async () => {
    // His menu takes the click and his header does not move - so the import is
    // refused after a switch that was asked for exactly once.
    const page = fakePage({ spec: 'Restoration Druid', stuck: true });
    await assert.rejects(
        () => forkLib.ensureCharacter(page, SHAMAN),
        (e) => {
            assert.strictEqual(e.code, forkLib.DRIVE);
            assert.match(e.message, /asked for "Restoration Shaman" and its header still says "Restoration Druid"/);
            return true;
        }
    );
    assert.deepStrictEqual(
        page.events,
        ['spec menu opened', 'menu open', 'options counted', 'spec picked: Restoration Shaman'],
        'asked once, not twice'
    );
});

test('a spec his own menu does not offer is refused with exit 5 rather than guessed at', async () => {
    const page = fakePage({ spec: 'Restoration Druid' });
    await assert.rejects(
        () => forkLib.ensureCharacter(page, { class: 'DRUID', spec: 'Balance' }),
        (e) => {
            assert.strictEqual(e.code, forkLib.REFUSED, 'the profile is what is wrong, not the driver');
            assert.match(e.message, /does not offer "Balance Druid"/);
            return true;
        }
    );
    assert.strictEqual(page.spec, 'Restoration Druid', 'his page is left where it was');
});

// --- the icon's alt text and the menu's own delay (C-16b, WKE-625) -----------

test("an option's accessible name is the spec twice over, and it is still the one picked", async () => {
    // What the double renders, stated out loud: his `MenuItem` is an
    // `<img alt="Restoration Shaman">` beside a `Typography` of the same words,
    // so the accessible name is doubled and the visible text is not.
    const page = fakePage({ spec: 'Restoration Druid' });
    assert.strictEqual(page.optionNameOf('Restoration Shaman'), 'Restoration Shaman Restoration Shaman');
    assert.strictEqual(page.optionTextOf('Restoration Shaman'), 'Restoration Shaman');

    // The driver never asks by name (the double refuses that question), and the
    // switch lands anyway - which the C-16 driver's
    // `getByRole('option', { name, exact: true })` could not do on his page.
    const character = await forkLib.ensureCharacter(page, SHAMAN);
    assert.strictEqual(character.note, 'Restoration Shaman (switched from Restoration Druid)');
    assert.strictEqual(page.spec, 'Restoration Shaman');
});

test('the options are not counted before his menu has opened', async () => {
    // MUI mounts the popover after the click resolves. Four ticks here, and the
    // count still happens on the far side of the wait.
    const page = fakePage({ spec: 'Restoration Druid', optionTicks: 4 });
    await forkLib.ensureCharacter(page, SHAMAN);
    assert.deepStrictEqual(page.events, [
        'spec menu opened',
        'menu open',
        'options counted',
        'spec picked: Restoration Shaman',
    ]);
    assert.ok(
        !page.events.includes('options counted before the menu opened'),
        'the 2026-09-22 failure: zero options because none had rendered yet'
    );
});

test('a menu that never opens is a named driver failure, not "does not offer"', async () => {
    const page = fakePage({ spec: 'Restoration Druid', menuNeverOpens: true });
    await assert.rejects(
        () => forkLib.ensureCharacter(page, SHAMAN),
        (e) => {
            // The control is ours to drive, so this is `fork-drive` and not the
            // exit-5 refusal that blames his menu's contents.
            assert.strictEqual(e.code, forkLib.DRIVE);
            assert.match(e.message, /was clicked and no menu opened within \d+ms; nothing was chosen/);
            return true;
        }
    );
    assert.deepStrictEqual(page.events, ['spec menu opened'], 'nothing was counted and nothing was clicked');
});

test('the match is exact on the WORDS: a spec never wins because it begins another', async () => {
    // His Classic list holds `Restoration Druid Classic`
    // (QEHeaderClassSelector.js lines 24-31), and the anchored regex is what
    // keeps the old `exact: true` promise now that the name is no longer used.
    //
    // Read, never copied, and said plainly: his Classic `MenuItem` strips the
    // word in its own `Typography` (line 56), so in a Classic menu the visible
    // words are identical to retail's and only MUI's `data-value` would tell
    // them apart. That is unreachable here - `classNames[gameType]` renders one
    // list, never both, and the driver only ever asks for a retail name.
    const page = fakePage({
        spec: 'Holy Paladin',
        specs: [
            {
                text: 'Restoration Druid Classic',
                name: 'Restoration Druid Restoration Druid Classic',
                value: 'Restoration Druid Classic',
            },
            { text: 'Holy Paladin', name: 'Holy Paladin Holy Paladin', value: 'Holy Paladin' },
        ],
    });
    await assert.rejects(
        () => forkLib.ensureCharacter(page, DRUID),
        (e) => {
            assert.strictEqual(e.code, forkLib.REFUSED);
            assert.match(e.message, /does not offer "Restoration Druid"/);
            return true;
        }
    );
    assert.strictEqual(page.spec, 'Holy Paladin', 'the Classic entry was not picked in its place');
});

test('the visible one of his two header controls is the one that is read', async () => {
    // `QEHeader.js` renders its drawer twice and `keepMounted` keeps the mobile
    // copy in the DOM, so `.first()` would read a hidden control.
    const page = fakePage({ spec: 'Restoration Shaman', visibleIndex: 1 });
    assert.deepStrictEqual((await forkLib.ensureCharacter(page, SHAMAN)).switched, false);
    // None of them visible, and a header with no control at all, are two named
    // failures rather than a click into nothing.
    await assert.rejects(
        () => forkLib.ensureCharacter(fakePage({ visibleIndex: -1 }), SHAMAN),
        (e) => {
            assert.strictEqual(e.code, forkLib.DRIVE);
            assert.match(e.message, /2 "Current Spec" controls and none of them is visible/);
            return true;
        }
    );
    await assert.rejects(
        () => forkLib.ensureCharacter(fakePage({ labels: 0 }), SHAMAN),
        (e) => {
            assert.strictEqual(e.code, forkLib.DRIVE);
            assert.match(e.message, /no "Current Spec" control/);
            return true;
        }
    );
});

// --- a class QE Live has no character for ------------------------------------

test('a class QE Live has no character for is refused before the browser is opened', async () => {
    assert.strictEqual(forkLib.qeHasClass({ class: 'WARRIOR', spec: 'Arms' }), false);
    assert.strictEqual(forkLib.qeHasClass(SHAMAN), true);
    // A capture that names no class is not a refusal: it is a capture too old to
    // say, and the import speaks for itself.
    assert.strictEqual(forkLib.qeHasClass({ spec: 'Restoration' }), true);

    // Nothing answers this URL and `startFork` is false, so if the refusal were
    // not first the failure would be `fork-unreachable` instead.
    const config = { ...configLib.load(null), forkUrl: 'http://127.0.0.1:9/nothing', startFork: false };
    await assert.rejects(
        () => forkLib.run(config, SHAMAN_PROFILE, quietLog(), { identity: { class: 'WARRIOR', spec: 'Arms' } }),
        (e) => {
            assert.strictEqual(e.code, forkLib.REFUSED, 'exit 5, and not the unreachable fork');
            assert.strictEqual(e.message, 'QE Live rates healers and has no character for a WARRIOR; nothing was asked of it');
            return true;
        }
    );
});

// --- the welcome path still works, and now for every class -------------------

test('the welcome dialog clicks the tile for the profile\'s own character', async () => {
    const clicks = [];
    const welcomePage = (label) => ({
        getByText(what) {
            const text = String(what);
            return {
                async count() {
                    return 1;
                },
                first() {
                    return this;
                },
                async click() {
                    clicks.push(text);
                },
                async waitFor() {},
            };
        },
        getByRole() {
            return {
                async click() {
                    clicks.push('Begin!');
                },
            };
        },
    });
    assert.strictEqual(await forkLib.dismissWelcome(welcomePage(), 'Restoration Shaman'), true);
    assert.deepStrictEqual(clicks, ['/^Shaman$/i', 'Begin!']);
    clicks.length = 0;
    await forkLib.dismissWelcome(welcomePage(), 'Holy Priest');
    assert.deepStrictEqual(clicks, ['/^H Priest$/i', 'Begin!'], 'the class token PRIEST named no tile at all');
});

// --- the hand-off ------------------------------------------------------------

// The driver can only put QE Live on a character the run told it about, so the
// one line in `companion.js` that hands `profile.identity` over is a guard of
// its own: without it every switch above is dead code.
test('the run hands the driver the identity the profile was built from', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c16-'));
    const dir = path.join(root, 'WTF', 'Account', 'TESTACCOUNT#1', 'SavedVariables');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
        path.join(dir, 'Lootpath.lua'),
        fs.readFileSync(path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'captures', 'Lootpath-20260906-200908.lua'), 'utf8'),
        'utf8'
    );
    fs.mkdirSync(path.join(root, 'Interface', 'AddOns', 'Lootpath'), { recursive: true });
    const config = { ...configLib.DEFAULTS, wowPath: root, stateDir: path.join(root, 'state'), includeBank: true };
    const handed = [];
    const fork = {
        async run(runConfig, profileText, runLog, runOpts) {
            handed.push(runOpts && runOpts.identity);
            return { documents: [], timings: [], scenarios: [], qeSettings: {} };
        },
    };
    await companion.once(config, quietLog(), { watch: false, profileOnly: false, force: true }, {
        fork,
        status: statusLib.make({ file: path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', configLib.STATUS_FILE) }),
    });
    assert.strictEqual(handed.length, 1);
    assert.ok(handed[0], 'the driver was handed no identity at all');
    // The committed transcript's own character, and the two fields the switch
    // is built from. It was captured in GUARDIAN - the same capture 2026-09-08
    // proved QE Live values as a Restoration Druid whatever the `spec=` line
    // says - so this is also the identity whose name his menu does not offer,
    // and the one the read above refuses at exit 5 rather than guessing at.
    assert.strictEqual(handed[0].class, 'DRUID');
    assert.strictEqual(handed[0].spec, 'Guardian');
    assert.strictEqual(forkLib.qeSpecOf(handed[0]), 'Guardian Druid');
    assert.strictEqual(forkLib.qeHasClass(handed[0]), true, 'the CLASS is one he has a character for');
});
