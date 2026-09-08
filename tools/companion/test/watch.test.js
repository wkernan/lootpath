// The watcher, over a real file in a temp directory. The client writes
// SavedVariables in one go on /reload, but it replaces the file rather than
// truncating it, and a slow disk can leave it growing for a moment; both cases
// have to end in exactly one run.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { watch } = require('../lib/watch');

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

function temp() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-watch-'));
    return path.join(dir, 'Lootpath.lua');
}

test('one write is one run', async () => {
    const file = temp();
    fs.writeFileSync(file, 'LootpathDB = {}');
    let runs = 0;
    const w = watch(file, { debounceMs: 60 }, () => {
        runs++;
    });
    await wait(50);
    fs.writeFileSync(file, 'LootpathDB = { ["global"] = {} }');
    await wait(400);
    w.close();
    assert.strictEqual(runs, 1);
});

test('a file still growing is left alone until it settles', async () => {
    // The gaps here are LONGER than the debounce, so the timer alone would fire
    // in the middle of the write. Only the two-stats-agree check keeps the run
    // back until the file has stopped growing.
    const file = temp();
    fs.writeFileSync(file, 'a');
    let runs = 0;
    let sizeAtRun = -1;
    const w = watch(file, { debounceMs: 40 }, () => {
        runs++;
        sizeAtRun = fs.statSync(file).size;
    });
    await wait(30);
    for (let i = 0; i < 5; i++) {
        fs.appendFileSync(file, 'x'.repeat(100));
        await wait(60);
    }
    await wait(400);
    w.close();
    assert.strictEqual(runs, 1);
    assert.strictEqual(sizeAtRun, 501, 'the run must see the whole file, never a prefix of it');
});

test('a write during a run queues exactly one more run, never a pile of them', async () => {
    const file = temp();
    fs.writeFileSync(file, 'a');
    let runs = 0;
    let running = 0;
    const w = watch(file, { debounceMs: 40 }, async () => {
        running++;
        assert.strictEqual(running, 1, 'two runs overlapped');
        runs++;
        await wait(250);
        running--;
    });
    await wait(30);
    fs.appendFileSync(file, 'b');
    await wait(150);
    fs.appendFileSync(file, 'c');
    fs.appendFileSync(file, 'd');
    await wait(800);
    w.close();
    assert.strictEqual(runs, 2);
});

test('a run that throws does not stop the watch', async () => {
    const file = temp();
    fs.writeFileSync(file, 'a');
    let runs = 0;
    const w = watch(file, { debounceMs: 40 }, async () => {
        runs++;
        throw new Error('QE Live refused the profile');
    });
    await wait(30);
    fs.appendFileSync(file, 'b');
    await wait(200);
    fs.appendFileSync(file, 'c');
    await wait(300);
    w.close();
    assert.strictEqual(runs, 2);
});
