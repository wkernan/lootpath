// C-4 (WKE-537): the companion skips the QE Live run when the profile is
// unchanged, so the second `/lootpath refresh` - the one whose only job is to
// load the file - does not start a run of its own.
//
// Every test here drives the real `once()` from companion.js over a fake game
// folder in the OS temp directory. Nothing writes into the real game folder,
// and the fork driver is injected, so no browser is ever opened: the point of
// most of these guards is that QE Live was NOT asked.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const companion = require('../companion');
const fingerprintLib = require('../lib/fingerprint');
const logLib = require('../lib/log');
const configLib = require('../lib/config');

const REPO = path.join(__dirname, '..', '..', '..');
const TRANSCRIPT = fs.readFileSync(path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20260906-200908.lua'), 'utf8');
const ACCOUNT = 'TESTACCOUNT#1';

// A whole fake `_retail_` under os.tmpdir(): the account folder the companion
// discovers by glob, and the AddOns\Lootpath folder output.js insists on before
// it will create `Data\`. The owner's companion may be watching his real game
// folder while these run; nothing here goes near it.
function fakeGame(savedVariables) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c4-'));
    fs.mkdirSync(savedVariablesDir(root), { recursive: true });
    fs.writeFileSync(savedVariablesFile(root), savedVariables, 'utf8');
    fs.mkdirSync(path.join(root, 'Interface', 'AddOns', 'Lootpath'), { recursive: true });
    return root;
}

function savedVariablesDir(root) {
    return path.join(root, 'WTF', 'Account', ACCOUNT, 'SavedVariables');
}

function savedVariablesFile(root) {
    return path.join(savedVariablesDir(root), 'Lootpath.lua');
}

// One harness per test: a config pointing at the fake game, a state directory of
// its own, a log captured into an array, and a fork driver that counts.
function harness(savedVariables) {
    const root = fakeGame(savedVariables === undefined ? TRANSCRIPT : savedVariables);
    const stateDir = path.join(root, 'state');
    const config = { ...configLib.DEFAULTS, wowPath: root, stateDir: stateDir, includeBank: true };
    const lines = [];
    const log = logLib.make((line) => lines.push(line));
    const fork = {
        calls: [],
        async run(runConfig, profileText) {
            fork.calls.push(profileText);
            return {
                documents: [{ kind: 'topgear', contentType: 'Dungeon', json: '{"player":{"spec":"Guardian"}}' }],
                timings: [],
                // The real driver reads the boxes back off the page after
                // clicking them (C-5); this double reports what it was asked
                // for, so a verdict file that ignores the driver and writes a
                // constant is a failing test rather than a lucky match.
                qeSettings: {
                    autoUpgradeVault: !!runConfig.qeAutoUpgradeVault,
                    autoUpgradeAll: !!runConfig.qeAutoUpgradeAll,
                },
            };
        },
    };
    return {
        root: root,
        stateDir: stateDir,
        config: config,
        lines: lines,
        fork: fork,
        verdict: configLib.verdictPath(config),
        gear: (text) => fs.writeFileSync(savedVariablesFile(root), text, 'utf8'),
        run: (args) =>
            companion.once(config, log, { watch: false, profileOnly: false, force: false, ...(args || {}) }, { fork: fork }),
        said: (needle) => lines.some((line) => line.includes(needle)),
    };
}

// The SavedVariables with every recorded capture time moved on, which is what a
// second `/lootpath refresh` produces since C-3 (WKE-536): the same gear,
// captured again a minute later.
function reCaptured(text) {
    return text.replace(/2026-09-05T13:33:25/g, '2026-09-08T09:01:02').replace(/13:33:25/g, '09:01:02');
}

test('the same profile twice: the second run is skipped and QE Live is never asked', async () => {
    const h = harness();
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 1, 'the first run must ask QE Live');
    assert.ok(fs.existsSync(h.verdict));

    h.lines.length = 0;
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 1, 'the second run must NOT open the browser');
    assert.ok(h.said('profile unchanged since '), h.lines.join(' | '));
    assert.ok(h.said('/reload in game to read it'), 'the owner still needs the cue');
});

test('a profile differing in one bonus ID runs again', async () => {
    const h = harness();
    await h.run();
    assert.strictEqual(h.fork.calls.length, 1);

    // One bonus ID of one equipped item, changed in the SavedVariables the way a
    // real upgrade changes it. This is hotornot's finger1 in the committed
    // transcript; bumping 13440 to 13441 moves exactly one profile line,
    // `finger1=,id=151311,...,bonus_id=13440/6652/...` (plus the checksum).
    const ring = 'Hitem:151311:7968:240892::::::90:104::33:5:13440:6652:13668:12699:12790:1:28:1279:::::';
    assert.ok(TRANSCRIPT.includes(ring), 'the fixture must still carry the ring this guard perturbs');
    h.gear(TRANSCRIPT.split(ring).join(ring.replace(':13440:', ':13441:')));

    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 2, 'changed gear must reach QE Live');
    assert.notStrictEqual(h.fork.calls[1], h.fork.calls[0], 'and the profile it was asked about really did change');
});

test('a header-only difference - the capture ran again over the same gear - is skipped', async () => {
    const h = harness();
    await h.run();
    h.gear(reCaptured(TRANSCRIPT));
    h.lines.length = 0;
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 1, 'a new capture stamp over the same gear is not a new question');
    assert.ok(h.said('profile unchanged since '), h.lines.join(' | '));
    // And the two profiles really would have been different text.
    assert.ok(fingerprintLib.stripVolatile(h.fork.calls[0]).dropped.length > 0, 'something must have been stripped');
});

test('--force runs even when the profile is unchanged', async () => {
    const h = harness();
    await h.run();
    assert.strictEqual(await h.run({ force: true }), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 2);
    assert.strictEqual(h.fork.calls[0], h.fork.calls[1], 'the same profile, asked again because it was told to');
});

test('the hash is remembered but the verdict file is gone: it runs', async () => {
    const h = harness();
    await h.run();
    fs.rmSync(h.verdict);
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 2, 'nothing for the addon to read means there is work to do');
    assert.ok(fs.existsSync(h.verdict));
});

test('a state file that cannot be read: it runs, and says why', async () => {
    const h = harness();
    await h.run();
    fs.writeFileSync(fingerprintLib.statePath(h.stateDir), '{ this is not JSON', 'utf8');
    h.lines.length = 0;
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 2, 'forgetting must cost a run, never skip one');
    assert.ok(h.said('is not valid JSON'), h.lines.join(' | '));
    assert.ok(h.said('running QE Live rather than assuming the verdict is current'), h.lines.join(' | '));
});

test('a dry run to --out elsewhere is not skipped because the real verdict is current', async () => {
    const h = harness();
    await h.run();
    // The --out target already exists and is stale: only comparing the
    // remembered path against the one this run was asked for catches that. If
    // the check were "the file exists", this run would skip and leave the stale
    // file sitting there.
    const elsewhere = path.join(h.root, 'dry-run.lua');
    fs.writeFileSync(elsewhere, '-- stale, from an earlier dry run\n', 'utf8');
    assert.strictEqual(await h.run({ out: elsewhere }), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 2, 'the run was asked for a different file than the one remembered');
    assert.ok(fs.readFileSync(elsewhere, 'utf8').includes('ns.companionVerdict'), 'and the stale file was replaced');
});

test('--profile-only never reads or writes the fingerprint', async () => {
    const h = harness();
    const write = process.stdout.write;
    process.stdout.write = () => true;
    try {
        assert.strictEqual(await h.run({ profileOnly: true }), companion.EXIT.ok);
    } finally {
        process.stdout.write = write;
    }
    assert.strictEqual(h.fork.calls.length, 0);
    assert.ok(!fs.existsSync(fingerprintLib.statePath(h.stateDir)), 'a printed profile is not a written verdict');
});

test('a failed run leaves no fingerprint behind', async () => {
    const h = harness();
    h.fork.run = async () => {
        throw Object.assign(new Error('the fork is down'), { code: 'fork-unreachable' });
    };
    assert.strictEqual(await h.run(), companion.EXIT.fork);
    assert.ok(!fs.existsSync(fingerprintLib.statePath(h.stateDir)), 'a failed run must not claim the verdict is current');
});

test('the state file names the hash, the stamp it wrote and the file it wrote', async () => {
    const h = harness();
    await h.run();
    const state = JSON.parse(fs.readFileSync(fingerprintLib.statePath(h.stateDir), 'utf8'));
    assert.match(state.hash, /^[0-9a-f]{64}$/);
    assert.match(state.writtenAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    assert.strictEqual(path.resolve(state.verdict), path.resolve(h.verdict));
    assert.strictEqual(state.hash, fingerprintLib.fingerprint(h.fork.calls[0], configLib.qeSettings(h.config)).hash);
    // The stamp the state file remembers is the one the addon reads out of the
    // chunk, so the skip line quotes a time the owner can check against it.
    assert.ok(fs.readFileSync(h.verdict, 'utf8').includes('writtenAt = "' + state.writtenAt + '"'));
});

// --- the fingerprint on its own ---------------------------------------------

test('exactly the four listed lines are stripped, and nothing else', () => {
    const profile = [
        '# Hotornot - Guardian - 2026-09-05 13:33 - us/Arthas',
        "# Built by Lootpath's companion from SavedVariables (WKE-532 spike), not by /simc",
        '# WoW 12.1.0.69587, TOC 120100',
        '# Inventory captured 2026-09-05T13:33:25',
        '',
        'druid="Hotornot"',
        '# Checksum: cd13649',
    ].join('\n');
    const stripped = fingerprintLib.stripVolatile(profile);
    assert.deepStrictEqual(
        stripped.dropped.map((d) => d.index),
        [0, 1, 3, 6]
    );
    assert.deepStrictEqual(stripped.kept, ['# WoW 12.1.0.69587, TOC 120100', '', 'druid="Hotornot"']);
});

test('the build line stays inside the fingerprint - a patched client is a new question', () => {
    const base = ['# WoW 12.1.0.69587, TOC 120100', 'druid="Hotornot"'].join('\n');
    const patched = ['# WoW 12.1.5.70000, TOC 120105', 'druid="Hotornot"'].join('\n');
    const settings = { autoUpgradeVault: false, autoUpgradeAll: false };
    assert.notStrictEqual(fingerprintLib.fingerprint(base, settings).hash, fingerprintLib.fingerprint(patched, settings).hash);
});

// C-5 (WKE-539). The settings are half the question QE Live is asked, so they
// are half the fingerprint - otherwise flipping a box would be answered out of
// a state file that remembers the other box's answer.
test('flipping a QE Live setting is a new question and costs a run', async () => {
    const h = harness();
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 1);

    // Not a byte of gear moved; only what is asked about it.
    h.config.qeAutoUpgradeVault = true;
    h.config.qeAutoUpgradeAll = true;
    h.lines.length = 0;
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 2, 'the new settings must reach QE Live');
    assert.strictEqual(h.fork.calls[1], h.fork.calls[0], 'and the profile itself is unchanged');
    assert.ok(!h.said('profile unchanged since '), h.lines.join(' | '));

    // And back again: the same pair as the first run is the first run's
    // question, but the state file now remembers the second's.
    h.config.qeAutoUpgradeVault = false;
    h.config.qeAutoUpgradeAll = false;
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 3);
});

test('the same settings twice is still a skip', async () => {
    const h = harness();
    h.config.qeAutoUpgradeVault = true;
    h.config.qeAutoUpgradeAll = true;
    await h.run();
    h.lines.length = 0;
    assert.strictEqual(await h.run(), companion.EXIT.ok);
    assert.strictEqual(h.fork.calls.length, 1, 'nothing changed, so nothing is asked');
    assert.ok(h.said('profile unchanged since '), h.lines.join(' | '));
});

test('the run says which settings it asked QE Live for, and the file records them', async () => {
    const h = harness();
    await h.run();
    assert.ok(h.said('QE Live import settings: autoUpgradeVault=false, autoUpgradeAll=false'), h.lines.join(' | '));
    const written = fs.readFileSync(h.verdict, 'utf8');
    assert.ok(written.includes('autoUpgradeVault = false,'), written.slice(0, 600));
    assert.ok(written.includes('autoUpgradeAll = false,'), written.slice(0, 600));
});

test('the file records the settings the driver actually got, not the pair asked for', async () => {
    const h = harness();
    h.config.qeAutoUpgradeVault = true;
    h.config.qeAutoUpgradeAll = true;
    await h.run();
    const written = fs.readFileSync(h.verdict, 'utf8');
    assert.ok(written.includes('autoUpgradeVault = true,'), written.slice(0, 600));
    assert.ok(written.includes('autoUpgradeAll = true,'), written.slice(0, 600));
});

test('a mixed pair is named in the log as the thing it is', async () => {
    const h = harness();
    h.config.qeAutoUpgradeVault = true;
    await h.run();
    assert.ok(h.said('autoUpgradeVault=true, autoUpgradeAll=false'), h.lines.join(' | '));
    assert.ok(h.said('different points on their upgrade tracks'), h.lines.join(' | '));
});

test('the settings line is canonical: key order cannot move the hash', () => {
    const profile = 'druid="Hotornot"';
    const a = fingerprintLib.fingerprint(profile, { autoUpgradeVault: false, autoUpgradeAll: true });
    const b = fingerprintLib.fingerprint(profile, { autoUpgradeAll: true, autoUpgradeVault: false });
    assert.strictEqual(a.hash, b.hash);
    assert.strictEqual(a.settingsLine, '# qeSettings autoUpgradeAll=true autoUpgradeVault=false');
    assert.notStrictEqual(a.hash, fingerprintLib.fingerprint(profile, { autoUpgradeVault: true, autoUpgradeAll: true }).hash);
});

test('isCurrent refuses when the remembered verdict points somewhere else', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c4-state-'));
    const here = path.join(dir, 'QEVerdict.lua');
    const other = path.join(dir, 'other.lua');
    fs.writeFileSync(here, 'x');
    // `other` exists too, so only the path comparison can refuse it.
    fs.writeFileSync(other, 'x');
    assert.strictEqual(fingerprintLib.isCurrent({ hash: 'a', verdict: here }, 'a', here).current, true);
    assert.strictEqual(fingerprintLib.isCurrent({ hash: 'a', verdict: here }, 'b', here).current, false);
    assert.strictEqual(fingerprintLib.isCurrent({ hash: 'a', verdict: here }, 'a', other).current, false);
    fs.rmSync(here);
    assert.strictEqual(fingerprintLib.isCurrent({ hash: 'a', verdict: here }, 'a', here).current, false);
});

test('a state file with no hash in it is not trusted', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c4-state-'));
    fs.writeFileSync(fingerprintLib.statePath(dir), JSON.stringify({ writtenAt: '2026-09-08T00:00:00Z' }), 'utf8');
    const read = fingerprintLib.readState(dir);
    assert.strictEqual(read.ok, false);
    assert.strictEqual(read.absent, undefined);
    assert.match(read.reason, /carries no hash and verdict path/);
});
