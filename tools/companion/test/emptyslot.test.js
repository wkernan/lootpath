// C-14 (WKE-603): the companion never sends a profile QE Live will not rate.
//
// THE RUN THIS IS ABOUT. The owner's `/lootpath refresh` at 16:26 on
// 2026-09-16 stored an inventory read with 14 equipped records - slot 7, legs,
// absent. The companion ran twice on that write, at 21:26:35Z and 21:27:30Z,
// and both runs read (`Data/companion.log`):
//
//   profile: 14 equipped, 41 in bags, 0 in the bank, 0 vault, 167 lines
//   top gear pool (pass 1): 30/30 selected of 54 cards (14 baseline, 16 clicked)
//   top gear pool (pass 3): 22/30 selected of 54 cards (14 baseline, 8 clicked)
//   FAILED: driving QE Live failed: locator.click: Timeout 20000ms exceeded.
//
// Pass 3's 22 cards were the 14-piece baseline and eight trinkets: nothing in
// it filled the Legs slot, QE Live disabled `Go!`, and Playwright clicked the
// disabled button for twenty seconds before it gave up - twice.
//
// THE FIXTURE IS THE WRITE ITSELF. `Lootpath-20260916-162655.lua` is the
// owner's own SavedVariables, copied out of his game folder unchanged, and its
// newest inventory snapshot IS the 16:26:34 read. Every count asserted below
// was read from his log, not chosen here.
//
// Everything drives the real `once()` over a fake `_retail_` in the OS temp
// directory with the fork driver injected, exactly as emptygear.test.js does,
// so no browser opens and nothing goes near the owner's own game folder.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const companion = require('../companion');
const logLib = require('../lib/log');
const configLib = require('../lib/config');
const statusLib = require('../lib/status');
const profileLib = require('../lib/profile');

const REPO = path.join(__dirname, '..', '..', '..');
const CAPTURES = path.join(REPO, 'spec', 'fixtures', 'captures');
const EMPTY_SLOT = fs.readFileSync(path.join(CAPTURES, 'Lootpath-20260916-162655.lua'), 'utf8');
const FULL = fs.readFileSync(path.join(CAPTURES, 'Lootpath-20260906-200908.lua'), 'utf8');

function harness(savedVariables) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c14-'));
    const dir = path.join(root, 'WTF', 'Account', 'TESTACCOUNT#1', 'SavedVariables');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'Lootpath.lua'), savedVariables, 'utf8');
    const dataDir = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data');
    fs.mkdirSync(dataDir, { recursive: true });
    const stateDir = path.join(root, 'state');
    const config = { ...configLib.DEFAULTS, wowPath: root, stateDir, includeBank: true };
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
    const fork = {
        calls: [],
        async run() {
            fork.calls.push(true);
            throw new Error('the fork must never be reached for a profile QE Live would not rate');
        },
    };
    return {
        fork,
        lines,
        logText: () => lines.join('\n'),
        statusText: () => fs.readFileSync(statusFile, 'utf8'),
        verdict: configLib.verdictPath(config),
        run: (args) =>
            companion.once(config, log, { watch: false, profileOnly: false, force: false, ...(args || {}) }, { fork, status }),
    };
}

// The reconstruction is exact: the five counts the owner's own log printed at
// 21:26:38Z, off the same write. Proven red by naming an older snapshot.
test('the fixture reproduces the owner 2026-09-16 21:26 profile line', () => {
    const built = profileLib.build(EMPTY_SLOT, { includeBank: true });
    assert.ok(built.ok, built.ok ? '' : built.reason);
    assert.strictEqual(built.capturedAtLocal, '2026-09-16T16:26:34');
    assert.deepStrictEqual(built.counts, { equipped: 14, bag: 41, bank: 0, vault: 0, lines: 167 });
});

// The slot the client did not answer for, named by the profile's own reading
// rather than by counting to fifteen.
test('the profile names the empty slot, and only that one', () => {
    const built = profileLib.build(EMPTY_SLOT, { includeBank: true });
    assert.deepStrictEqual(built.missingSlots, ['legs']);
    assert.ok(!built.equippedSlots.includes('legs'));
    assert.ok(built.equippedSlots.includes('finger1') && built.equippedSlots.includes('finger2'));
});

// QE Live's own rule, mirrored: `checkSlots` (TopGear.tsx:307), which the `Go!`
// button's `disabled` calls at :852. Two rings and two trinkets; one of
// everything else; weapons deliberately left to the button itself.
test("missingSlots mirrors QE Live's checkSlots for rings and trinkets", () => {
    const all = [
        'head',
        'neck',
        'shoulder',
        'back',
        'chest',
        'wrist',
        'hands',
        'waist',
        'legs',
        'feet',
        'finger1',
        'finger2',
        'trinket1',
        'trinket2',
    ];
    assert.deepStrictEqual(profileLib.missingSlots(all), []);
    assert.deepStrictEqual(profileLib.missingSlots(all.filter((s) => s !== 'finger2')), ['finger']);
    assert.deepStrictEqual(profileLib.missingSlots(all.filter((s) => s !== 'trinket1')), ['trinket']);
    // A two-hander and no offhand is a profile QE Live will rate; the weapon
    // half of `checkSlots` is not mirrored here (see lib/profile.js).
    assert.deepStrictEqual(profileLib.missingSlots([...all, 'main_hand']), []);
    // Nothing worn at all reports every one of the twelve, in QE Live's order.
    assert.strictEqual(profileLib.missingSlots([]).length, 12);
    assert.strictEqual(profileLib.missingSlots([])[0], 'head');
});

// **THE POINT OF THE ISSUE.** Proven red by deleting the `missing.length` guard
// from `companion.js`: the fork is opened, its double throws, and the run dies
// at `qe live` with exit 4 - which is the 2026-09-16 failure exactly.
test('a profile with an empty slot is refused before the fork is touched', async () => {
    const h = harness(EMPTY_SLOT);
    const code = await h.run();

    assert.strictEqual(code, companion.EXIT.emptySlot);
    assert.strictEqual(companion.EXIT.emptySlot, 9);
    // Its own code beside emptyGear's: "we sent it nothing" and "we sent it
    // something it will not rate" are two different answers.
    assert.notStrictEqual(companion.EXIT.emptySlot, companion.EXIT.emptyGear);
    assert.notStrictEqual(companion.EXIT.emptySlot, companion.EXIT.fork);

    assert.strictEqual(h.fork.calls.length, 0, 'the fork was opened for a profile QE Live would not rate');
    assert.ok(!fs.existsSync(h.verdict), 'the previous verdict must be untouched, and there was none');

    // One line, and it is the sentence the issue asked for.
    assert.match(
        h.logText(),
        /refusing to rate a profile with an empty slot \(legs\); the previous verdict is untouched/
    );
    // `skipped:`, never `FAILED:` - nothing broke (R-7c's rule, same shape).
    assert.ok(!h.logText().includes('FAILED:'), 'a refusal is not a failure');
});

// `skipped`, with the slot name on the file: the addon chooses its clause from
// the exit code and the player reads which slot from the message.
test('the status file says skipped, names the slot, and carries its own exit code', async () => {
    const h = harness(EMPTY_SLOT);
    await h.run();
    const status = h.statusText();
    assert.match(status, /state = "skipped"/);
    assert.match(status, /exitCode = 9,/);
    assert.match(status, /stage = "profile"/);
    assert.match(status, /message = "refusing to rate a profile with an empty slot \(legs\)/);
});

// The refusal must not be a new way for an ordinary run to die.
test('a profile wearing every slot is not refused', async () => {
    const h = harness(FULL);
    const code = await h.run();
    assert.notStrictEqual(code, companion.EXIT.emptySlot);
    assert.strictEqual(h.fork.calls.length, 1, 'a fully dressed profile must reach QE Live');
});

// The sentence names every empty slot rather than the first one, because a
// player who took two pieces off should not have to refresh twice to find out.
test('the refusal names every slot QE Live would report', () => {
    assert.strictEqual(
        companion.emptySlotLine(['legs', 'feet']),
        'refusing to rate a profile with an empty slot (legs, feet); the previous verdict is untouched'
    );
});
