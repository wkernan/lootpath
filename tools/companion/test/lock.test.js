// C-9 (WKE-559): never two watchers.
//
// The rule has been written down since C-1 and kept by hand: the owner knew
// whether one was already running because he had started it. A logon task means
// nobody knows, so the lock file is the one that knows. `alive` is injected
// here - a test must not depend on which pids this machine happens to have.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const lockLib = require('../lib/lock');

function lockFile() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c9-lock-'));
    return path.join(dir, 'state', 'watch.lock');
}

test('the first watcher takes the lock and the second is refused by name', () => {
    const file = lockFile();
    const first = lockLib.acquire(file, { pid: 4242, alive: () => true });
    assert.strictEqual(first.ok, true);
    assert.strictEqual(first.took, false);
    assert.ok(fs.existsSync(file));

    const second = lockLib.acquire(file, { pid: 5353, alive: () => true });
    assert.strictEqual(second.ok, false);
    assert.strictEqual(second.held.pid, 4242, 'the refusal must name the process that has it');
    assert.match(second.held.startedAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
});

test('a lock whose process is gone is taken over, never a file to delete by hand', () => {
    // A machine that lost power mid-run leaves the file behind. Refusing on it
    // would mean the logon task never starts again and nothing says why.
    const file = lockFile();
    lockLib.acquire(file, { pid: 4242, alive: () => true });
    const next = lockLib.acquire(file, { pid: 5353, alive: (pid) => pid !== 4242 });
    assert.strictEqual(next.ok, true);
    assert.strictEqual(next.took, true, 'and it says it took one over, rather than pretending nothing was there');
    assert.strictEqual(lockLib.read(file).pid, 5353);
});

test('the same process asking twice is not two watchers', () => {
    const file = lockFile();
    lockLib.acquire(file, { pid: 4242, alive: () => true });
    const again = lockLib.acquire(file, { pid: 4242, alive: () => true });
    assert.strictEqual(again.ok, true);
    assert.strictEqual(again.took, false);
});

test('a lock file nobody can read is not a held lock', () => {
    const file = lockFile();
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, 'half a json {');
    const taken = lockLib.acquire(file, { pid: 4242, alive: () => true });
    assert.strictEqual(taken.ok, true, 'a broken byte must not stop the companion from ever watching again');
    assert.strictEqual(lockLib.read(file).pid, 4242);
});

test('releasing removes our own lock and never the watcher that took over', () => {
    const file = lockFile();
    const held = lockLib.acquire(file, { pid: 4242, alive: () => true });
    assert.strictEqual(held.release(), true);
    assert.ok(!fs.existsSync(file));

    const mine = lockLib.acquire(file, { pid: 4242, alive: () => true });
    lockLib.acquire(file, { pid: 5353, alive: () => false });
    assert.strictEqual(mine.release(), false, 'the file now names another watcher; it is not ours to delete');
    assert.strictEqual(lockLib.read(file).pid, 5353);
});

test('a pid that is not a pid is not alive', () => {
    assert.strictEqual(lockLib.alive(0), false);
    assert.strictEqual(lockLib.alive(-1), false);
    assert.strictEqual(lockLib.alive(1.5), false);
    // This process is, and asking about it costs nothing.
    assert.strictEqual(lockLib.alive(process.pid), true);
});
