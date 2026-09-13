// C-9 (WKE-559): the log file next to the verdict.
//
// The failure it answers is recorded in docs/ARCHITECTURE.md 11 (2026-09-09):
// the watcher's output went into the window that started it and nowhere else,
// so a run that died looked exactly like a run with nothing to do. Everything
// here is a real file in the OS temp directory; nothing goes near the game
// folder.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const logLib = require('../lib/log');

// A fake `_retail_` deep enough for output.js's one rule: the Data folder may be
// created, the AddOns folder may not.
function dataFile(name) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c9-log-'));
    fs.mkdirSync(path.join(root, 'Interface', 'AddOns', 'Lootpath'), { recursive: true });
    return path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', name || 'companion.log');
}

function lines(file) {
    return fs
        .readFileSync(file, 'utf8')
        .split('\n')
        .filter((line) => line.length);
}

test('every line the companion prints reaches the file, with the date the terminal does not show', () => {
    const file = dataFile();
    const printed = [];
    const log = logLib.make(logLib.tee((line) => printed.push(line), logLib.fileSink(file)));

    log.info('SavedVariables: ...\\Account\\<account>\\SavedVariables\\Lootpath.lua');
    log.warn('the bank was closed when the capture ran');
    log.error('QE Live refused the profile');
    log.stage('profile')('15 equipped');

    const written = lines(file);
    assert.strictEqual(written.length, 4);
    assert.strictEqual(printed.length, 4);
    for (let i = 0; i < written.length; i++) {
        // The same text; the file stamp is the full date, the terminal's the clock.
        const text = printed[i].replace(/^\[\d\d:\d\d:\d\d\] /, '');
        assert.match(written[i], /^\[\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\] /);
        assert.strictEqual(written[i].replace(/^\[[^\]]+\] /, ''), text);
    }
    assert.match(written[1], /warning: the bank was closed/);
    assert.match(written[2], /FAILED: QE Live refused the profile/);
    assert.match(written[3], /profile: 15 equipped \(\d+ ms\)/);
});

test('the log rotates at its cap and keeps exactly one generation', () => {
    const file = dataFile();
    const log = logLib.make(logLib.tee(() => {}, logLib.fileSink(file, { maxBytes: 400 })));
    for (let i = 0; i < 40; i++) log.info(`line ${i} ${'x'.repeat(40)}`);

    assert.ok(fs.existsSync(file), 'the live log must exist');
    assert.ok(fs.existsSync(file + '.1'), 'the previous generation must be kept');
    assert.ok(!fs.existsSync(file + '.2'), 'and only one of them');
    assert.ok(fs.statSync(file).size <= 400 + 200, 'the live log must have been cut, not grown');
    // The newest line is in the live file and the oldest is not: rotation moves
    // the old bytes aside, it does not throw the new ones away.
    assert.match(fs.readFileSync(file, 'utf8'), /line 39 /);
    assert.ok(!fs.readFileSync(file, 'utf8').includes('line 0 '));
});

test('a log file that cannot be written costs one warning and never the run', () => {
    // No AddOns folder: output.js refuses to create one, which is exactly the
    // "the addon is not installed" case.
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c9-nolog-'));
    const file = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', 'companion.log');
    const errors = [];
    const printed = [];
    const sink = logLib.fileSink(file, { onError: (e) => errors.push(e) });
    const log = logLib.make(logLib.tee((line) => printed.push(line), sink));

    log.info('one');
    log.info('two');
    log.info('three');

    assert.strictEqual(printed.length, 3, 'the terminal still gets every line');
    assert.strictEqual(errors.length, 1, 'and the owner is told once, not once a line');
    assert.match(errors[0].message, /the addon is not installed/);
    assert.ok(!fs.existsSync(file));
});

test('a sink that throws does not rob the others of the line', () => {
    const kept = [];
    const write = logLib.tee(
        () => {
            throw new Error('this sink is broken');
        },
        (line) => kept.push(line)
    );
    const log = logLib.make(write);
    log.info('still printed');
    assert.strictEqual(kept.length, 1);
});
