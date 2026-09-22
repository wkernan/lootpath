// C-17 (WKE-624): the rename into the game folder is retried while the client
// is holding the file.
//
// The owner's terminal, 2026-09-21 17:40:23: `EPERM: operation not permitted,
// rename '...\.CompanionStatus.lua.47652.tmp' -> '...\CompanionStatus.lua'` -
// he was reloading, and the client reads `Data\*.lua` at that instant. The run
// failed and the strip went on saying `rating your gear` for three minutes.
//
// `fs.renameSync` is replaced for the length of a test rather than faked as a
// whole module: everything else here - the temp file, the directory rule, the
// bytes - is the real filesystem, so what is proved is the real writer.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const output = require('../lib/output');

// A real Data file inside a real AddOns tree, because `dataDir` refuses to
// create the AddOns folder and that rule is not the one under test here.
function dataFile(name) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c17-'));
    fs.mkdirSync(path.join(root, 'Interface', 'AddOns', 'Lootpath'), { recursive: true });
    return path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', name);
}

// Throws `code` on the first `times` calls, then hands the rename back to the
// real one. Returns a restore function; every test calls it.
function renameFails(times, code) {
    const real = fs.renameSync;
    let calls = 0;
    fs.renameSync = (from, to) => {
        calls += 1;
        if (calls <= times) {
            const e = new Error(`${code}: operation not permitted, rename '${from}' -> '${to}'`);
            e.code = code;
            throw e;
        }
        return real(from, to);
    };
    return {
        calls: () => calls,
        restore: () => {
            fs.renameSync = real;
        },
    };
}

// The sleep is handed in, so a bounded wait is recorded rather than waited out.
function recorder() {
    const waits = [];
    return { waits, sleep: (ms) => waits.push(ms) };
}

test('a rename the client refuses twice is retried, the file lands, and one line says so', () => {
    const file = dataFile('CompanionStatus.lua');
    const stub = renameFails(2, 'EPERM');
    const clock = recorder();
    const said = [];
    try {
        const written = output.writeAtomic(file, 'ns.companionStatus = {}\n', {
            sleep: clock.sleep,
            onRetry: (tries, target) => said.push(`status file written after ${tries} tries; the client was reading it (${path.basename(target)})`),
        });
        assert.equal(written.tries, 3);
        assert.equal(stub.calls(), 3);
        assert.equal(fs.readFileSync(file, 'utf8'), 'ns.companionStatus = {}\n');
        assert.deepEqual(clock.waits, [25, 50]);
        // ONCE, never per try.
        assert.deepEqual(said, ['status file written after 3 tries; the client was reading it (CompanionStatus.lua)']);
        // And the temp file is not left in the folder the addon loads out of.
        assert.equal(fs.existsSync(written.temp), false);
    } finally {
        stub.restore();
    }
});

test('a rename that succeeds first time says nothing at all', () => {
    const file = dataFile('QEVerdict.lua');
    const said = [];
    const written = output.writeVerdict(file, 'ns.qeVerdict = {}\n', {
        onRetry: (tries) => said.push(tries),
    });
    assert.equal(written.tries, 1);
    assert.deepEqual(said, []);
});

test('a rename that never succeeds gives up as it always did, and the previous file stands', () => {
    const file = dataFile('CompanionStatus.lua');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, 'the previous status\n', 'utf8');
    const stub = renameFails(Infinity, 'EPERM');
    const clock = recorder();
    const said = [];
    try {
        assert.throws(
            () => output.writeAtomic(file, 'the new status\n', { sleep: clock.sleep, onRetry: (tries) => said.push(tries) }),
            /EPERM/
        );
        // Ten tries, nine waits, and the ceiling really is a ceiling.
        assert.equal(stub.calls(), output.RETRY_TRIES);
        assert.equal(stub.calls(), 10);
        assert.deepEqual(clock.waits, [25, 50, 100, 200, 300, 300, 300, 300, 300]);
        assert.ok(
            clock.waits.reduce((a, b) => a + b, 0) <= 2000,
            'the whole wait stays inside two seconds'
        );
        // Nothing was said about a retry that never worked: the warning the
        // caller already prints is the record.
        assert.deepEqual(said, []);
        assert.equal(fs.readFileSync(file, 'utf8'), 'the previous status\n');
    } finally {
        stub.restore();
    }
    // The temp file went with the failure.
    const leftovers = fs.readdirSync(path.dirname(file)).filter((n) => n.endsWith('.tmp'));
    assert.deepEqual(leftovers, []);
});

test('EBUSY and EACCES are waited on too; ENOENT is not retried', () => {
    for (const code of ['EBUSY', 'EACCES']) {
        const file = dataFile('CompanionStatus.lua');
        const stub = renameFails(1, code);
        const clock = recorder();
        try {
            const written = output.writeAtomic(file, 'x\n', { sleep: clock.sleep });
            assert.equal(written.tries, 2, `${code} is retried`);
        } finally {
            stub.restore();
        }
    }
    const file = dataFile('CompanionStatus.lua');
    const stub = renameFails(1, 'ENOENT');
    const clock = recorder();
    try {
        assert.throws(() => output.writeAtomic(file, 'x\n', { sleep: clock.sleep }), /ENOENT/);
        // One try, no wait: a path that is wrong will be just as wrong in two
        // seconds.
        assert.equal(stub.calls(), 1);
        assert.deepEqual(clock.waits, []);
    } finally {
        stub.restore();
    }
});

test('the backoff doubles from 25 ms and stops at 300', () => {
    assert.deepEqual(
        [1, 2, 3, 4, 5, 6, 9].map(output.backoff),
        [25, 50, 100, 200, 300, 300, 300]
    );
    assert.equal(output.RETRY_FIRST_MS, 25);
    assert.equal(output.RETRY_MAX_MS, 300);
    assert.deepEqual(output.RETRY_CODES, ['EPERM', 'EBUSY', 'EACCES']);
});
