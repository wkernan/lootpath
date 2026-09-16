// R-7b (WKE-591): the companion never rates nothing.
//
// The owner's 2026-09-15 22:07 run built a profile of `0 equipped, 0 in bags,
// 0 in the bank, 0 vault, 14 lines` out of a logout that had captured nothing,
// sent it to QE Live anyway, and died three stages later at the fork with
// `Selected Items: 0/30` - a fork failure, exit 4, for a question that was
// empty before the browser was opened. The safety at the far end held and the
// verdict file was untouched; the log named the wrong thing.
//
// Everything here drives the real `once()` over a fake `_retail_` in the OS
// temp directory with the fork driver injected, exactly as visible.test.js
// does, so no browser opens and nothing goes near the owner's own game folder.
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
// The hand-written flush that read nothing. Its provenance - the owner's live
// SavedVariables, parsed 2026-09-16 - is the file's own header and the README
// beside it.
const EMPTY = fs.readFileSync(path.join(CAPTURES, 'empty-equipment-flush.lua'), 'utf8');
const FULL = fs.readFileSync(path.join(CAPTURES, 'Lootpath-20260906-200908.lua'), 'utf8');

function harness(savedVariables) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-r7b-'));
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
            throw new Error('the fork must never be reached for a profile with no gear in it');
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

// The reconstruction is exact: the same five counts the owner's terminal
// printed at 22:07:51. Proven red by putting a single equipped record back into
// the fixture - `14 lines` becomes 16 and `0 equipped` becomes 1.
test('the fixture reproduces the owner 2026-09-15 22:07 profile line', () => {
    const built = profileLib.build(EMPTY, { includeBank: true });
    assert.ok(built.ok, built.ok ? '' : built.reason);
    assert.deepStrictEqual(built.counts, { equipped: 0, bag: 0, bank: 0, vault: 0, lines: 14 });
});

// **THE POINT OF THE ISSUE'S SECOND HALF.** Proven red by deleting the
// `profile.counts.equipped === 0` guard from `companion.js`: the fork double
// throws its own message, the run dies at `qe live`, and the status file says
// `failed` with exit 4 - which is the 2026-09-15 failure exactly.
test('a profile with no equipped gear is refused before the fork is touched', async () => {
    const h = harness(EMPTY);
    const code = await h.run();

    assert.strictEqual(code, companion.EXIT.emptyGear);
    assert.strictEqual(companion.EXIT.emptyGear, 8);
    // Its own code, so a wrapper can tell "we sent it nothing" from "QE Live broke".
    assert.notStrictEqual(companion.EXIT.emptyGear, companion.EXIT.fork);
    assert.notStrictEqual(companion.EXIT.emptyGear, companion.EXIT.profile);

    assert.strictEqual(h.fork.calls.length, 0, 'the fork was opened for a profile with no gear in it');
    assert.ok(!fs.existsSync(h.verdict), 'the previous verdict must be untouched, and there was none');

    // One line, and it is the sentence the issue asked for.
    assert.match(
        h.logText(),
        /refusing to rate a profile with no equipped gear \(the newest inventory read is empty\); the previous verdict is untouched/
    );
});

// `skipped`, not `failed`: nothing broke. The addon reads the state to choose
// its clause and the exit code to choose WHICH skip it was (C-4's "your gear
// hasn't changed" is the other one), so both have to be on the file.
test('the status file says skipped, with the reason and its own exit code', async () => {
    const h = harness(EMPTY);
    await h.run();
    const status = h.statusText();
    assert.match(status, /state = "skipped"/);
    assert.match(status, /exitCode = 8,/);
    assert.match(status, /stage = "profile"/);
    assert.match(status, /message = "refusing to rate a profile with no equipped gear/);
});

// The refusal must not be a new way for an ordinary run to die.
test('a profile that carries gear is not refused', async () => {
    const h = harness(FULL);
    const code = await h.run();
    assert.notStrictEqual(code, companion.EXIT.emptyGear);
    assert.strictEqual(h.fork.calls.length, 1, 'a profile with fifteen pieces on it must reach QE Live');
});

// `--profile-only` opens nothing and writes nothing, and printing the empty
// profile is how this gets diagnosed in the first place. Proven red by moving
// the guard above the `--profile-only` branch: the profile never reaches stdout.
test('--profile-only still prints the empty profile, because that is the evidence', async () => {
    const h = harness(EMPTY);
    const out = [];
    const write = process.stdout.write.bind(process.stdout);
    process.stdout.write = (chunk) => {
        out.push(String(chunk));
        return true;
    };
    try {
        assert.strictEqual(await h.run({ profileOnly: true }), companion.EXIT.ok);
    } finally {
        process.stdout.write = write;
    }
    assert.match(out.join(''), /^druid="Hotornot"$/m);
});

// ---------------------------------------------------------------------------
// The flush label, and the issue's third premise (R-7b, WKE-591).
//
// **The premise is wrong, and this is what refutes it.** The issue reported
// `run after a write whose capture does not say how it was taken (an addon from
// before R-6)` for a snapshot whose `trigger` is `"flush"`, and asked which side
// had drifted. Neither had. The addon writes `trigger = "flush"` and
// `capturedOn = "flush"` (`Companion.CaptureAtFlush`), the parser lifts
// `env.trigger` (`lib/profile.js`), and `whatThisWriteCarried` has had the
// `flush` branch since R-7a. The owner's live SavedVariables, parsed 2026-09-16,
// carry both fields on every flush snapshot in the file.
//
// What actually happened: R-7a merged at 15:47 on 2026-09-15 and renamed the
// label from `logout` to `flush` on BOTH sides at once. The addon in game was
// re-synced; the watcher process in the owner's own window was not restarted,
// so it was still running the pre-R-7a `whatThisWriteCarried`, whose only
// branch was `capture.trigger === 'logout'`. A new addon's `flush` fell through
// it to the catch-all. `git show 866e8d7^:tools/companion/companion.js` is the
// code that printed that line.
//
// So there is nothing to fix and a guard to keep: the line is pinned here
// against the very env snapshot shape that was misread.
test('a flush snapshot reads as a flush, whatever else the write carried', () => {
    const built = profileLib.build(EMPTY, { includeBank: true });
    assert.strictEqual(built.capture.trigger, 'flush');
    assert.strictEqual(
        companion.whatThisWriteCarried(built, { ok: false }),
        'run after a logout or reload (gear captured at the flush)'
    );
});

// An addon from before R-6 really does write no trigger, and that line is the
// one the owner saw. It stays, and it stays reachable only by a transcript that
// genuinely says nothing.
test('a transcript with no trigger at all is the only thing that reads as one', () => {
    const noTrigger = EMPTY.replace('["trigger"] = "flush"', '["trigger"] = nil');
    const built = profileLib.build(noTrigger, { includeBank: true });
    assert.strictEqual(built.capture.trigger, null);
    assert.strictEqual(
        companion.whatThisWriteCarried(built, { ok: false }),
        'run after a write whose capture does not say how it was taken (an addon from before R-6)'
    );
});
