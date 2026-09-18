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

const forkLib = require('../lib/fork');
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
function fakePage(options) {
    const opts = options || {};
    const events = [];
    let spec = opts.spec || 'Restoration Druid';
    let menuOpen = false;
    let refusal = null;
    let submitted = null;
    const specs = opts.specs || HIS_SPECS;

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
            menuOpen = true;
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
            if (role === 'option') {
                assert.strictEqual(options.exact, true);
                const there = menuOpen && specs.includes(options.name);
                return {
                    async count() {
                        return there ? 1 : 0;
                    },
                    first() {
                        return {
                            async click() {
                                events.push(`spec picked: ${options.name}`);
                                menuOpen = false;
                                // His `handlePickPlayerSpec` makes the
                                // character of that spec active (App.tsx:273).
                                if (!opts.stuck) spec = options.name;
                            },
                        };
                    },
                };
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
    // A capture too old to say is nothing, never a guess.
    assert.strictEqual(forkLib.qeSpecOf({ class: 'SHAMAN' }), null);
    assert.strictEqual(forkLib.qeSpecOf({ spec: 'Restoration' }), null);
    assert.strictEqual(forkLib.qeSpecOf(null), null);
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
    assert.deepStrictEqual(page.events, ['spec menu opened', 'spec picked: Restoration Shaman']);
});

test('the switch is asked for before the import, and the import only passes because of it', async () => {
    const page = fakePage({ spec: 'Restoration Druid' });
    await forkLib.ensureCharacter(page, SHAMAN);
    await forkLib.importProfile(page, SHAMAN_PROFILE, {}, quietLog());
    assert.deepStrictEqual(page.events, [
        'spec menu opened',
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
    assert.deepStrictEqual(page.events, ['spec menu opened', 'spec picked: Restoration Shaman'], 'asked once, not twice');
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
