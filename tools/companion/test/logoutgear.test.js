// R-7c (WKE-594): a real logout never reads the gear, so the log must not say
// the flush captured it - and a skip must not be logged as a failure.
//
// The evidence is the owner's own 14:25:58 logout, pulled as
// `spec/fixtures/captures/Lootpath-20260916-142559.lua` and committed: its
// newest `env` snapshot is a flush carrying
// `flushRefusals = { { capture = "inventory", ... } }`, and no `inventory`
// snapshot was stored for it, so the newest inventory read in the file is the
// EMPTY 14:00:11 one stored by the pre-R-7b addon. Everything below is driven
// over that file, and the fake `_retail_` lives in the OS temp directory with
// the fork injected, exactly as emptygear.test.js does - no browser opens and
// nothing goes near the owner's own game folder.
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
const LOGOUT_PULL = fs.readFileSync(path.join(CAPTURES, 'Lootpath-20260916-142559.lua'), 'utf8');
const FULL = fs.readFileSync(path.join(CAPTURES, 'Lootpath-20260906-200908.lua'), 'utf8');

function harness(savedVariables) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-r7c-'));
    const dir = path.join(root, 'WTF', 'Account', 'TESTACCOUNT#1', 'SavedVariables');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'Lootpath.lua'), savedVariables, 'utf8');
    const dataDir = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data');
    fs.mkdirSync(dataDir, { recursive: true });
    const stateDir = path.join(root, 'state');
    const config = { ...configLib.DEFAULTS, wowPath: root, stateDir, includeBank: true };
    const lines = [];
    const log = logLib.make((line) => lines.push(line));
    const status = statusLib.make({
        file: path.join(dataDir, configLib.STATUS_FILE),
        companionVersion: companion.VERSION,
        onError: (e) => {
            throw e;
        },
    });
    const fork = {
        calls: [],
        async run() {
            fork.calls.push(true);
            throw new Error('the fork must never be reached for a profile with no gear in it');
        },
    };
    return {
        fork,
        logText: () => lines.join('\n'),
        run: (args) =>
            companion.once(config, log, { watch: false, profileOnly: false, force: false, ...(args || {}) }, { fork, status }),
    };
}

// The fact the whole issue rests on, read off the committed pull rather than
// asserted from the issue text. Proven red by dropping `flushRefusals` from
// `lib/profile.js`: the list comes back empty and the line below reverts to
// "gear captured at the flush".
test("the 14:25:58 logout's env snapshot says the flush refused the inventory", () => {
    const built = profileLib.build(LOGOUT_PULL, { includeBank: true });
    assert.ok(built.ok, built.ok ? '' : built.reason);
    assert.strictEqual(built.capture.trigger, 'flush');
    assert.deepStrictEqual(built.capture.flushRefusals, ['inventory']);
});

// **The line R-7c asks for.** The gear was NOT captured at that flush, so the
// log names the read the run is actually rating. Proven red by deleting the
// `flushRefusals` branch from `whatThisWriteCarried`: the line says "gear
// captured at the flush" about a flush that captured none.
test('a write whose flush refused the inventory says which read it rated', () => {
    const built = profileLib.build(LOGOUT_PULL, { includeBank: true });
    assert.strictEqual(
        companion.whatThisWriteCarried(built, { ok: false }),
        `run after a logout that could not read the gear; rating the inventory read of ${built.capturedAtLocal}`
    );
    // and the read it names is the owner's own 14:00:11 one
    assert.strictEqual(built.capturedAtLocal, '2026-09-16T14:00:11');
});

// A flush that read the gear is untouched: it captured at the flush and says so.
test('a flush that refused nothing still reads as a flush', () => {
    const built = profileLib.build(FULL, { includeBank: true });
    assert.deepStrictEqual(built.capture.flushRefusals, []);
    assert.notStrictEqual(
        companion.whatThisWriteCarried(built, { ok: false }),
        `run after a logout that could not read the gear; rating the inventory read of ${built.capturedAtLocal}`
    );
});

// The nit R-7b left. The status file has said `skipped` since R-7b and the log
// said `FAILED:` beside it about the same run. Proven red by putting
// `log.error` back in `companion.js`: the log reads `FAILED: refusing to rate`.
test('the empty-gear refusal is logged as a skip, not as a failure', async () => {
    const h = harness(LOGOUT_PULL);
    const code = await h.run();

    // The newest inventory read in this file is itself the empty 14:00:11 one,
    // so the existing exit-8 refusal is what follows - which is the case the
    // issue names.
    assert.strictEqual(code, companion.EXIT.emptyGear);
    assert.strictEqual(h.fork.calls.length, 0);

    const text = h.logText();
    assert.match(text, /skipped: refusing to rate a profile with no equipped gear/);
    assert.doesNotMatch(text, /FAILED: refusing to rate/);
    // and the line above it is the one that says which read was on offer
    assert.match(text, /run after a logout that could not read the gear; rating the inventory read of/);
});

// `log.skipped` is the prefix, and it is not `warning:` either: a reader
// grepping the file for a state finds the same word the status file carries.
test('log.skipped writes the same word the status file uses', () => {
    const lines = [];
    const log = logLib.make((line) => lines.push(line));
    log.skipped('nothing to do');
    assert.match(lines[0], /skipped: nothing to do$/);
    assert.doesNotMatch(lines[0], /FAILED|warning/);
});
