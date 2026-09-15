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
