// C-17 (WKE-691): the companion starts QE Live's dev server in a way the Node
// on the owner's box allows.
//
// On 2026-10-07T02:28:30Z his watcher logged `FAILED: spawn EINVAL`: the fork
// module spawned 'npm.cmd' with the shell off on win32, and since Node's April
// 2024 security release (CVE-2024-27980) that throws before any process
// exists. The first test below calls the REAL `spawn` with the options
// `fork.forkStart` builds, against a harmless `npm.cmd` this test writes into a
// temp dir and puts first on PATH - so nothing here runs QE Live, opens a
// browser, or touches the owner's fork or his running watcher.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { spawn } = require('child_process');
const { EventEmitter } = require('events');
const fs = require('fs');
const os = require('os');
const path = require('path');

const forkLib = require('../lib/fork');

const NOT_WINDOWS = process.platform === 'win32' ? false : 'npm is npm.cmd, a batch file, only on Windows';

function tempDir() {
    return fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c17-'));
}

async function waitFor(file, ms) {
    const deadline = Date.now() + ms;
    while (Date.now() < deadline) {
        if (fs.existsSync(file)) return fs.readFileSync(file, 'utf8');
        await new Promise((r) => setTimeout(r, 100));
    }
    return null;
}

test('the fork start the module builds is accepted by spawn on win32 and runs npm start', { skip: NOT_WINDOWS }, async () => {
    const dir = tempDir();
    const marker = path.join(dir, 'marker.txt');
    // A one-line `npm.cmd` that only writes down what it was asked and whether
    // BROWSER=none reached it.
    fs.writeFileSync(path.join(dir, 'npm.cmd'), `@echo %1 %BROWSER%> "${marker}"\r\n`);
    const savedPath = process.env.PATH;
    let how;
    try {
        process.env.PATH = `${dir}${path.delimiter}${savedPath}`;
        how = forkLib.forkStart({ forkPath: dir }, 'win32');
    } finally {
        process.env.PATH = savedPath;
    }
    let child;
    assert.doesNotThrow(() => {
        child = spawn(how.file, how.args, how.options);
    }, 'spawn threw - on Windows that is EINVAL for a .cmd without the shell (CVE-2024-27980)');
    let failed = null;
    child.on('error', (e) => {
        failed = e;
    });
    child.unref();
    const wrote = await waitFor(marker, 10000);
    assert.strictEqual(failed, null, `spawn emitted ${failed && failed.message}`);
    assert.ok(wrote !== null, 'the fake npm.cmd never ran');
    assert.strictEqual(wrote.trim(), 'start none');
    fs.rmSync(dir, { recursive: true, force: true });
});

test('the fork start stays detached, silent and BROWSER=none, and on win32 uses no shell option', () => {
    for (const platform of ['win32', 'linux']) {
        const how = forkLib.forkStart({ forkPath: 'c:\fork' }, platform);
        assert.strictEqual(how.options.cwd, 'c:\fork');
        assert.strictEqual(how.options.detached, true, 'detached, so the dev server outlives one companion run');
        assert.strictEqual(how.options.stdio, 'ignore');
        assert.strictEqual(how.options.env.BROWSER, 'none');
        assert.ok(!how.options.shell, 'no shell option: DEP0190 marks args with shell as not recommended');
    }
    const win = forkLib.forkStart({ forkPath: 'c:\fork' }, 'win32');
    assert.match(win.file, /cmd(\.exe)?$/i);
    assert.deepStrictEqual(win.args, ['/d', '/s', '/c', 'npm start']);
    const posix = forkLib.forkStart({ forkPath: '/fork' }, 'linux');
    assert.strictEqual(posix.file, 'npm');
    assert.deepStrictEqual(posix.args, ['start']);
});

test('a spawn that throws becomes a fork error that says what to do', () => {
    const config = { forkPath: 'c:\Code\qe-live-fork' };
    const einval = () => {
        const e = new Error('spawn EINVAL');
        e.code = 'EINVAL';
        throw e;
    };
    assert.throws(
        () => forkLib.startFork(config, einval),
        (e) =>
            e instanceof forkLib.ForkError &&
            e.code === forkLib.UNREACHABLE &&
            e.message ===
                'could not start "npm start" in c:\Code\qe-live-fork (spawn EINVAL); run "npm start" in c:\Code\qe-live-fork yourself'
    );
});

test('a spawn error event does not take the watcher down; ensureUp reports it with the same words', async () => {
    const dir = tempDir();
    fs.writeFileSync(path.join(dir, 'package.json'), '{}');
    const config = {
        // Nothing listens on the discard port; isUp answers false at once.
        forkUrl: 'http://127.0.0.1:9/',
        forkPath: dir,
        startFork: true,
        forkStartTimeoutSeconds: 30,
    };
    const lines = [];
    const log = { info: (m) => lines.push(m) };
    const fakeSpawn = () => {
        const child = new EventEmitter();
        child.unref = () => {};
        setImmediate(() => child.emit('error', new Error('spawn cmd.exe ENOENT')));
        return child;
    };
    await assert.rejects(forkLib.ensureUp(config, log, fakeSpawn), (e) => {
        assert.ok(e instanceof forkLib.ForkError);
        assert.strictEqual(e.code, forkLib.UNREACHABLE);
        assert.strictEqual(
            e.message,
            `could not start "npm start" in ${dir} (spawn cmd.exe ENOENT); run "npm start" in ${dir} yourself`
        );
        return true;
    });
    assert.deepStrictEqual(lines, [`nothing answers http://127.0.0.1:9/; starting "npm start" in ${dir}`]);
    fs.rmSync(dir, { recursive: true, force: true });
});
