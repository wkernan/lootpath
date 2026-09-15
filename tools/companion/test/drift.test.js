// R-6 (WKE-578): what the companion can say about the write it woke on.
//
// The client flushes SavedVariables on a logout and on every reload, and the
// watcher runs on every write, so most writes carry the same captures over
// again. Two facts tell a fresh one from a repeat: the `trigger` the addon now
// records on every snapshot ("refresh" or "command"), and the `env` snapshot's
// own stamp measured against the one the last written run read.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const profileLib = require('../lib/profile');
const fingerprintLib = require('../lib/fingerprint');

const REPO = path.join(__dirname, '..', '..', '..');
const CAPTURES = path.join(REPO, 'spec', 'fixtures', 'captures');
const TODAY = fs.readFileSync(path.join(CAPTURES, 'Lootpath-20260914-171359.lua'), 'utf8');

test("reads the env capture's stamp off the owner's own 2026-09-14 transcript", () => {
    const built = profileLib.build(TODAY, {});
    assert.ok(built.ok, built.ok ? '' : built.reason);
    assert.strictEqual(typeof built.capture.capturedAt, 'number');
    // That transcript was captured before R-6, so it records no trigger at all,
    // and the builder says so rather than guessing at one.
    assert.strictEqual(built.capture.trigger, null);
});

test('a snapshot the addon labelled is carried through verbatim', () => {
    // Every env snapshot in the file, so whichever one is newest is labelled;
    // that transcript carries 19 of them.
    const labelled = TODAY.split('["name"] = "env",').join('["name"] = "env", ["trigger"] = "refresh",');
    assert.notStrictEqual(labelled, TODAY);
    assert.strictEqual(profileLib.build(labelled, {}).capture.trigger, 'refresh');
});

test('a capture newer than the one the last run read is a new capture', () => {
    assert.strictEqual(fingerprintLib.captureIsNew({ envCapturedAt: 100 }, 200), true);
    assert.strictEqual(fingerprintLib.captureIsNew({ envCapturedAt: 200 }, 200), false);
    assert.strictEqual(fingerprintLib.captureIsNew({ envCapturedAt: 300 }, 200), false);
});

test('a state file or a transcript that cannot answer reads as unknown, never as either answer', () => {
    assert.strictEqual(fingerprintLib.captureIsNew(null, 200), null);
    assert.strictEqual(fingerprintLib.captureIsNew({}, 200), null);
    assert.strictEqual(fingerprintLib.captureIsNew({ envCapturedAt: 100 }, null), null);
});

test('the state file remembers the capture, and reading it back survives the round trip', (t) => {
    const dir = fs.mkdtempSync(path.join(require('os').tmpdir(), 'lootpath-drift-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const verdict = path.join(dir, 'QEVerdict.lua');
    fs.writeFileSync(verdict, '-- placeholder\n');
    fingerprintLib.writeState(dir, {
        hash: 'abc',
        writtenAt: '2026-09-14T23:10:00Z',
        verdict,
        envCapturedAt: 1789000000,
    });
    const back = fingerprintLib.readState(dir);
    assert.ok(back.ok, back.ok ? '' : back.reason);
    assert.strictEqual(back.state.envCapturedAt, 1789000000);
    assert.strictEqual(fingerprintLib.captureIsNew(back.state, 1789000000), false);
    assert.strictEqual(fingerprintLib.captureIsNew(back.state, 1789000060), true);
});

// R-7 (WKE-579), corrected by R-7a (WKE-582). The addon takes the same four
// snapshots when the UI is unloaded, labelled `trigger = "flush"`, so the write
// the client makes on the way out carries the gear the player was in - and the
// log can say a capture was taken instead of naming two possibilities. What it
// may NOT say is "logout": `PLAYER_LOGOUT` fires on `/reload` too, and this line
// printed "run after logout" for a plain reload on 2026-09-15.
const { whatThisWriteCarried } = require('../companion');

const STORED = (envCapturedAt) => ({ ok: true, state: { envCapturedAt } });

test('a flush capture is named as one, and the line never claims a logout', () => {
    const line = whatThisWriteCarried({ capture: { trigger: 'flush', capturedAt: 200 } }, STORED(100));
    assert.strictEqual(line, 'run after a logout or reload (gear captured at the flush)');
    assert.ok(!/run after logout/.test(line));
});

// An addon at exactly R-7 wrote `logout` for the same event and the same four
// captures. It reads as the same line rather than as an unlabelled write.
test('an R-7 snapshot labelled logout reads as a flush', () => {
    assert.strictEqual(
        whatThisWriteCarried({ capture: { trigger: 'logout', capturedAt: 200 } }, STORED(100)),
        'run after a logout or reload (gear captured at the flush)'
    );
});

test('the other three lines are what they were', () => {
    assert.strictEqual(
        whatThisWriteCarried({ capture: { trigger: 'refresh', capturedAt: 200 } }, STORED(100)),
        'run after /lootpath refresh (gear captured at the click)'
    );
    assert.strictEqual(
        whatThisWriteCarried({ capture: { trigger: 'command', capturedAt: 200 } }, STORED(100)),
        'run after a capture made by hand'
    );
    assert.strictEqual(
        whatThisWriteCarried({ capture: { trigger: null, capturedAt: 200 } }, STORED(100)),
        'run after a write whose capture does not say how it was taken (an addon from before R-6)'
    );
});

// A write carrying a capture the last run already read is a logout or reload
// that captured nothing because it happened in combat. The label on the old
// capture does not make it new, whatever it says.
test('a capture the last run already read is still nothing new, even labelled flush', () => {
    assert.strictEqual(
        whatThisWriteCarried({ capture: { trigger: 'flush', capturedAt: 200 } }, STORED(200)),
        'run after a logout or a plain reload - nothing new was captured'
    );
});

// An unknown state file cannot refute a label the addon wrote down.
test('a flush is named even when the state file cannot say whether the capture is new', () => {
    assert.strictEqual(
        whatThisWriteCarried({ capture: { trigger: 'flush', capturedAt: 200 } }, { ok: false }),
        'run after a logout or reload (gear captured at the flush)'
    );
});
