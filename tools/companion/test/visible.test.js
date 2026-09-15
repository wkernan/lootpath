// C-9 (WKE-559): the companion is visible from inside the game.
//
// Everything here drives the real `once()` (and, at the end, the real CLI in a
// child process) over a fake `_retail_` in the OS temp directory, with the fork
// driver injected exactly as C-4's tests inject it - so no browser opens and
// nothing goes near the owner's own game folder or the watcher he runs himself.
//
// What it proves: a run says what it is doing while it is doing it, a run that
// dies says where, a run with nothing to do says that instead, and every line
// any of them printed is in a file the owner can read tomorrow.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const companion = require('../companion');
const logLib = require('../lib/log');
const configLib = require('../lib/config');
const statusLib = require('../lib/status');

const REPO = path.join(__dirname, '..', '..', '..');
const TRANSCRIPT = fs.readFileSync(path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20260906-200908.lua'), 'utf8');
const ACCOUNT = 'TESTACCOUNT#1';

function fakeGame(savedVariables) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c9-'));
    const dir = path.join(root, 'WTF', 'Account', ACCOUNT, 'SavedVariables');
    fs.mkdirSync(dir, { recursive: true });
    if (savedVariables !== null) fs.writeFileSync(path.join(dir, 'Lootpath.lua'), savedVariables, 'utf8');
    fs.mkdirSync(path.join(root, 'Interface', 'AddOns', 'Lootpath'), { recursive: true });
    return root;
}

// The same shape C-4's harness uses, with the two files C-9 adds wired the way
// the CLI wires them.
function harness(options) {
    const opts = options || {};
    const root = fakeGame(opts.savedVariables === undefined ? TRANSCRIPT : opts.savedVariables);
    const stateDir = path.join(root, 'state');
    const config = { ...configLib.DEFAULTS, wowPath: root, stateDir: stateDir, includeBank: true };
    const dataDir = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data');
    const logFile = path.join(dataDir, configLib.LOG_FILE);
    const statusFile = path.join(dataDir, configLib.STATUS_FILE);
    const lines = [];
    const log = logLib.make(logLib.tee((line) => lines.push(line), logLib.fileSink(logFile)));
    const seen = [];
    const status = statusLib.make({
        file: statusFile,
        companionVersion: companion.VERSION,
        onError: (e) => {
            throw e;
        },
    });
    const fork = {
        calls: [],
        // The owner's own week by default: something to catalyse and something
        // below its cap, so every configured scenario is asked.
        evidence: { clones: 1, raised: 1, readBase: true, cards: 40 },
        async run(runConfig, profileText, runLog, runOpts) {
            fork.calls.push(profileText);
            // What the status file says WHILE QE Live is being asked - the one
            // moment the owner used to have no way to see.
            seen.push(fs.readFileSync(statusFile, 'utf8'));
            if (opts.forkThrows) {
                const error = new Error(opts.forkThrows);
                error.code = opts.forkCode;
                throw error;
            }
            // The gates C-12 put on the three what-ifs are settled inside the
            // real driver, after each import, off QE Live's own pool. The
            // double is handed what that pool would have said (`fork.evidence`)
            // and settles them through the very same `configLib.gateVerdict`.
            const scenarios = [];
            const passes = ((runOpts && runOpts.passes) || []).filter((pass) => {
                if (!pass.scenario) return true;
                const settled = pass.gate
                    ? configLib.gateVerdict(pass.gate.kind, fork.evidence)
                    : { ran: true, reason: pass.why || 'asked whatever the pool holds', missing: [] };
                scenarios.push({ name: pass.scenario, ran: settled.ran, reason: settled.reason, missing: settled.missing });
                return settled.ran;
            });
            return {
                scenarios,
                documents: passes.flatMap((pass) =>
                    pass.documents.map((doc) => ({
                        kind: doc.kind,
                        contentType: doc.contentType,
                        keyLevel: doc.keyLevel,
                        scenario: doc.scenario,
                        qeSettings: pass.boxes,
                        json: '{"player":{"spec":"Guardian"}}',
                    }))
                ),
                timings: [],
                qeSettings: {
                    autoUpgradeVault: !!runConfig.qeAutoUpgradeVault,
                    autoUpgradeAll: !!runConfig.qeAutoUpgradeAll,
                },
            };
        },
    };
    return {
        root,
        config,
        lines,
        fork,
        status,
        logFile,
        statusFile,
        duringForkRun: seen,
        verdict: configLib.verdictPath(config),
        statusText: () => fs.readFileSync(statusFile, 'utf8'),
        logText: () => fs.readFileSync(logFile, 'utf8'),
        run: (args) =>
            companion.once(config, log, { watch: false, profileOnly: false, force: false, ...(args || {}) }, { fork, status }),
    };
}

test('a run that writes a verdict says so, and says it was running while it ran', async () => {
    const h = harness();
    assert.strictEqual(await h.run(), companion.EXIT.ok);

    // While QE Live was being asked.
    assert.strictEqual(h.duringForkRun.length, 1);
    assert.match(h.duringForkRun[0], /state = "running"/);
    assert.match(h.duringForkRun[0], /stage = "qe live"/);
    assert.ok(!h.duringForkRun[0].includes('verdictWrittenAt'), 'nothing was written yet, so nothing may say it was');

    // And afterwards.
    const status = h.statusText();
    assert.match(status, /state = "idle"/);
    assert.match(status, /stage = "write"/);
    assert.match(status, /exitCode = 0,/);
    const writtenAt = status.match(/verdictWrittenAt = "([^"]+)"/);
    assert.ok(writtenAt, 'the status file must carry the verdict it wrote');
    // The same stamp the addon reads off the verdict itself: one number in two
    // files, never two answers.
    assert.ok(fs.readFileSync(h.verdict, 'utf8').includes(`writtenAt = "${writtenAt[1]}"`));
    assert.match(status, /profileCapturedAt = "\d{4}-\d\d-\d\dT/);

    // The log carries the lines the terminal got.
    const log = h.logText();
    assert.match(log, /SavedVariables: /);
    assert.match(log, /profile: \d+ equipped/);
    assert.match(log, /qe live: \d+ documents/);
    assert.match(log, /^\[\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\] /m);
    assert.ok(!log.includes(ACCOUNT), 'the account folder is an identifier and is masked in the log too');
});

// C-12 (WKE-577). "8 documents" was all the strip's tooltip could say about a
// run that asked one question where the morning's asked four, and the owner had
// no way in from the game to find out why. The sentence is the companion's own,
// written once and put in both files it writes.
test('a run that skipped a question says so in the status file, in the verdict\'s own words', async () => {
    const h = harness();
    h.fork.evidence = { clones: 0, raised: 0, readBase: true, cards: 40 };
    assert.strictEqual(await h.run(), companion.EXIT.ok);

    const note =
        "The Catalyst question, this week's plan and the upgrade question went unasked:" +
        ' nothing you hold can be catalysed and nothing you hold is below its upgrade cap.';
    const status = h.statusText();
    assert.match(status, /state = "idle"/);
    assert.ok(status.includes(note), status);
    assert.ok(status.includes('message = "8 documents - ' + note), status);
    // The same words in the verdict, so the Vault tab's footnote and the
    // strip's tooltip cannot say two things about one run.
    assert.ok(fs.readFileSync(h.verdict, 'utf8').includes(`scenarioNote = "${note}"`));
    assert.ok(h.logText().includes(note), h.logText());
});

// The week the owner is usually in: every question has an answer, so there is
// no absence to explain and the tooltip is left saying what it always said.
test('a run that asked everything adds nothing to the status message', async () => {
    const h = harness();
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.match(h.statusText(), /message = "\d+ documents",/);
    assert.ok(!fs.readFileSync(h.verdict, 'utf8').includes('scenarioNote'));
});

test('a second run with nothing to do says "no run" rather than nothing at all', async () => {
    const h = harness();
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 1, 'C-4 still skips the second run');

    const status = h.statusText();
    assert.match(status, /state = "skipped"/);
    assert.match(status, /message = "profile unchanged since /);
    assert.match(status, /verdictWrittenAt = "/);
    assert.match(status, /exitCode = 0,/);
});

test('a run that dies in the fork says where it died, and the verdict it did not write', async () => {
    const h = harness({ forkThrows: 'the fork did not answer http://localhost:3000' });
    assert.strictEqual(await h.run(), companion.EXIT.fork);

    const status = h.statusText();
    assert.match(status, /state = "failed"/);
    assert.match(status, /stage = "qe live"/);
    assert.match(status, /message = "the fork did not answer http:\/\/localhost:3000"/);
    assert.match(status, new RegExp(`exitCode = ${companion.EXIT.fork},`));
    assert.ok(!status.includes('verdictWrittenAt'), 'a run that wrote nothing must not name a verdict');
    assert.ok(!fs.existsSync(h.verdict), 'and the verdict file is still untouched');
    assert.match(h.logText(), /FAILED: the fork did not answer/);
});

test('a write that fails says so, and never claims the verdict it did not write', async () => {
    const h = harness();
    // An --out inside a folder that is not an installed addon: output.js refuses
    // to create the AddOns tree, which is the write failure a full disk or a
    // moved game folder produces.
    const nowhere = path.join(h.root, 'nowhere', 'Lootpath', 'Data', 'QEVerdict.lua');
    assert.strictEqual(await h.run({ out: nowhere }), companion.EXIT.write);

    const status = h.statusText();
    assert.match(status, /state = "failed"/);
    assert.match(status, /stage = "write"/);
    assert.ok(!status.includes('verdictWrittenAt'), 'nothing was written, so nothing may say it was');
    assert.match(status, new RegExp(`exitCode = ${companion.EXIT.write},`));
    assert.ok(!fs.existsSync(nowhere));
});

test('a run with no SavedVariables to read fails at the first stage and names it', async () => {
    const h = harness({ savedVariables: null });
    assert.strictEqual(await h.run(), companion.EXIT.savedVariables);
    const status = h.statusText();
    assert.match(status, /state = "failed"/);
    assert.match(status, /stage = "savedvariables"/);
    assert.match(status, new RegExp(`exitCode = ${companion.EXIT.savedVariables},`));
});

// The wiring itself: `once()` is handed a status recorder by main(), and the
// log file is main()'s too. Nothing above proves main() does either, so this
// runs the real CLI in a child process over a fake game folder.
test('the CLI itself writes both files, without being handed anything', () => {
    const root = fakeGame(null);
    const stateDir = path.join(root, 'state');
    const configFile = path.join(root, 'companion.json');
    fs.writeFileSync(configFile, JSON.stringify({ wowPath: root, stateDir, startFork: false }), 'utf8');

    let code = 0;
    try {
        execFileSync(process.execPath, [path.join(__dirname, '..', 'companion.js'), '--config', configFile], {
            encoding: 'utf8',
        });
    } catch (e) {
        code = e.status;
    }
    assert.strictEqual(code, companion.EXIT.savedVariables, 'no SavedVariables in this fake game folder');

    const dataDir = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data');
    const log = fs.readFileSync(path.join(dataDir, configLib.LOG_FILE), 'utf8');
    assert.match(log, /Lootpath companion \d/);
    assert.match(log, /FAILED: no SavedVariables/);
    const status = fs.readFileSync(path.join(dataDir, configLib.STATUS_FILE), 'utf8');
    assert.match(status, /state = "failed"/);
    assert.match(status, /stage = "savedvariables"/);
    assert.match(status, new RegExp(`companionVersion = "${companion.VERSION}"`));
});

test('the CLI refuses to be the second watcher, before it runs anything', () => {
    const root = fakeGame(TRANSCRIPT);
    const stateDir = path.join(root, 'state');
    const configFile = path.join(root, 'companion.json');
    fs.writeFileSync(configFile, JSON.stringify({ wowPath: root, stateDir, startFork: false }), 'utf8');
    // A lock held by a process that is certainly alive: this one.
    fs.mkdirSync(stateDir, { recursive: true });
    fs.writeFileSync(
        path.join(stateDir, configLib.LOCK_FILE),
        JSON.stringify({ pid: process.pid, startedAt: '2026-09-13T22:00:00Z' }),
        'utf8'
    );

    let code = 0;
    let output = '';
    try {
        output = execFileSync(
            process.execPath,
            [path.join(__dirname, '..', 'companion.js'), '--config', configFile, '--watch'],
            { encoding: 'utf8', timeout: 30000 }
        );
    } catch (e) {
        code = e.status;
        output = String(e.stdout || '');
    }
    assert.strictEqual(code, companion.EXIT.watching);
    assert.match(output, new RegExp(`another companion is already watching \\(pid ${process.pid}`));
    // And it refused BEFORE doing any work: no verdict, and the fork was never
    // reached (this config would have had to open a browser to get that far).
    assert.ok(!fs.existsSync(configLib.verdictPath({ wowPath: root })));
});

test('--profile-only is a dry run: it writes the log and leaves the last real status alone', () => {
    const root = fakeGame(TRANSCRIPT);
    const stateDir = path.join(root, 'state');
    const configFile = path.join(root, 'companion.json');
    fs.writeFileSync(configFile, JSON.stringify({ wowPath: root, stateDir, startFork: false }), 'utf8');
    const dataDir = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data');
    fs.mkdirSync(dataDir, { recursive: true });
    const statusFile = path.join(dataDir, configLib.STATUS_FILE);
    fs.writeFileSync(statusFile, '-- the last real run\n', 'utf8');

    const profile = execFileSync(
        process.execPath,
        [path.join(__dirname, '..', 'companion.js'), '--config', configFile, '--profile-only'],
        { encoding: 'utf8' }
    );
    assert.match(profile, /^druid="Hotornot"$/m, 'the profile itself goes to stdout, as --profile-only promises');
    assert.strictEqual(fs.readFileSync(statusFile, 'utf8'), '-- the last real run\n');
    assert.match(fs.readFileSync(path.join(dataDir, configLib.LOG_FILE), 'utf8'), /profile: \d+ equipped/);
});
