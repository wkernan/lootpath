// C-9 (WKE-559): Data/CompanionStatus.lua, the companion saying what it last
// did. The chunk is data and never code, exactly like the verdict file, so the
// shape rules are proved here and spec/companionfile_spec.lua loads the golden
// in a real Lua interpreter from the other side.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const statusLib = require('../lib/status');

const GOLDEN = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'expected', 'companionstatus-sample.lua');

function dataFile() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c9-status-'));
    fs.mkdirSync(path.join(root, 'Interface', 'AddOns', 'Lootpath'), { recursive: true });
    return path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', 'CompanionStatus.lua');
}

// A clock that steps one minute per reading, so the stamps in a test are
// something to assert rather than whatever the machine's second was.
function clock(startISO) {
    let at = new Date(startISO);
    return () => {
        const now = new Date(at);
        at = new Date(at.getTime() + 60000);
        return now;
    };
}

function read(file) {
    return fs.readFileSync(file, 'utf8');
}

test('a run writes its status at every stage change, not once at the end', () => {
    const file = dataFile();
    const status = statusLib.make({ file, companionVersion: '0.1.0', clock: clock('2026-09-13T22:48:00Z') });

    status.started();
    assert.match(read(file), /state = "running"/);
    assert.match(read(file), /startedAt = "2026-09-13T22:48:00Z"/);
    assert.match(read(file), /stage = "start"/);
    assert.ok(!read(file).includes('finishedAt'), 'a run in progress has not finished');

    status.stage('qe live', { message: '3 imports, 8 documents' });
    assert.match(read(file), /stage = "qe live"/);
    assert.match(read(file), /message = "3 imports, 8 documents"/);

    status.wrote('2026-09-13T22:52:00Z', { message: '8 documents' });
    const done = read(file);
    assert.match(done, /state = "idle"/);
    assert.match(done, /verdictWrittenAt = "2026-09-13T22:52:00Z"/);
    assert.match(done, /exitCode = 0,/);
    // The clock steps a minute per reading: started (22:48 + the write's own
    // 22:49), the stage change (22:50), then the finish at 22:51.
    assert.match(done, /finishedAt = "2026-09-13T22:51:00Z"/);
});

test('a failure says which stage it died at, and the code the run returned', () => {
    const file = dataFile();
    const status = statusLib.make({ file, companionVersion: '0.1.0', clock: clock('2026-09-13T21:05:00Z') });
    status.started();
    status.stage('profile');
    status.failed('profile', 'no "inventory" capture in the SavedVariables', 3);

    const text = read(file);
    assert.match(text, /state = "failed"/);
    assert.match(text, /stage = "profile"/);
    assert.match(text, /message = "no \\"inventory\\" capture in the SavedVariables"/);
    assert.match(text, /exitCode = 3,/);
    assert.match(text, /finishedAt = "2026-09-13T21:08:00Z"/);
});

test('a skipped run is its own state, because "nothing to do" is not "nothing happened"', () => {
    const file = dataFile();
    const status = statusLib.make({ file, clock: clock('2026-09-13T23:06:00Z') });
    status.started();
    status.skipped('profile unchanged since 2026-09-13T22:52:00Z; the verdict file is current', {
        verdictWrittenAt: '2026-09-13T22:52:00Z',
    });
    const text = read(file);
    assert.match(text, /state = "skipped"/);
    assert.match(text, /verdictWrittenAt = "2026-09-13T22:52:00Z"/);
    assert.match(text, /exitCode = 0,/);
});

test('a new run clears what the last one said, so no field outlives its run', () => {
    const file = dataFile();
    const status = statusLib.make({ file, companionVersion: '0.1.0', clock: clock('2026-09-13T22:48:00Z') });
    status.started();
    status.failed('qe live', 'the fork did not answer', 4);
    status.started();
    const text = read(file);
    assert.ok(!text.includes('the fork did not answer'), 'the dead run\'s message must not describe the live one');
    assert.ok(!text.includes('exitCode'), 'nor its exit code');
    assert.ok(!text.includes('finishedAt'), 'nor the moment it stopped');
    assert.match(text, /companionVersion = "0.1.0"/);
});

test('it is data: one assignment of strings and numbers, no call and no loop', () => {
    const text = statusLib.render({
        state: 'failed',
        startedAt: '2026-09-13T22:48:00Z',
        finishedAt: '2026-09-13T22:49:00Z',
        stage: 'qe live',
        // Everything that could end a Lua literal early, because a failure
        // message is whatever went wrong and nobody wrote it on purpose. It is
        // all on the FIRST line since C-14 (WKE-603), because the first line is
        // the only one the chunk carries now - and the escaper is still what
        // has to survive it.
        message: 'quote " backslash \\ close ]] nul \0 os.execute("calc") --[[\n return \r rest',
        exitCode: 4,
        at: new Date('2026-09-13T22:49:00Z'),
    });
    for (const line of text.split('\n')) {
        if (!line.length) continue;
        const ok =
            line.startsWith('--') ||
            line === 'local _, ns = ...' ||
            line === 'if type(ns) ~= "table" then' ||
            line === '    return' ||
            line === 'end' ||
            line === 'ns.companionStatus = {' ||
            line === '}' ||
            /^ {4}[A-Za-z]+ = ("|\d)/.test(line);
        assert.ok(ok, `unexpected line in a data-only chunk: ${line}`);
    }
    assert.ok(!text.includes('\n]]'), 'a "]]" in a message must not reach the chunk unescaped');
    assert.match(text, /message = "quote \\" backslash \\\\ close \]\] nul/);
    // C-14 (WKE-603): the second line of a message never reaches the file.
    assert.ok(!text.includes('rest'), 'only the first line of a message is written');
});

test('a state the addon does not know is refused rather than written', () => {
    assert.throws(() => statusLib.render({ state: 'exploded' }), /not one of idle, running, skipped, failed/);
    assert.throws(() => statusLib.render({ state: 'idle', exitCode: 1.5 }), /not a whole exit code/);
});

test('a status file that cannot be written costs one warning and never the run', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c9-nostatus-'));
    const file = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', 'CompanionStatus.lua');
    const errors = [];
    const status = statusLib.make({ file, onError: (e) => errors.push(e) });
    status.started();
    status.stage('read');
    status.failed('read', 'nope', 2);
    assert.strictEqual(errors.length, 1, 'told once, not once a stage');
    assert.match(errors[0].message, /the addon is not installed/);
});

test('a recorder with no file writes nothing at all, which is what --profile-only wants', () => {
    const file = dataFile();
    const quiet = statusLib.make({});
    quiet.started();
    quiet.wrote('2026-09-13T22:52:00Z');
    assert.ok(!fs.existsSync(file));
    assert.strictEqual(quiet.file, null);
});

test('the committed golden is what the writer renders', () => {
    const text = statusLib.render({
        state: 'idle',
        startedAt: '2026-09-13T22:48:01Z',
        finishedAt: '2026-09-13T22:48:44Z',
        stage: 'write',
        message: 'the "Dungeon" run: 8 documents \\ one backslash ]] and a newline\n',
        profileCapturedAt: '2026-09-13T22:47:31',
        verdictWrittenAt: '2026-09-13T22:48:44Z',
        companionVersion: '0.1.0',
        exitCode: 0,
        at: new Date('2026-09-13T22:48:44Z'),
    });
    if (process.env.UPDATE_GOLDEN) fs.writeFileSync(GOLDEN, text);
    assert.strictEqual(
        text,
        fs.readFileSync(GOLDEN, 'utf8'),
        'spec/fixtures/expected/companionstatus-sample.lua is out of date; re-run with UPDATE_GOLDEN=1 and check spec/companionfile_spec.lua still passes'
    );
});

// C-17 (WKE-624): a status write that had to wait for the client says so once,
// through the recorder's own caller, because only the caller has the log.
test('the retry notice reaches the status recorder\'s caller', () => {
    const file = dataFile();
    const said = [];
    const real = fs.renameSync;
    let calls = 0;
    fs.renameSync = (from, to) => {
        calls += 1;
        if (calls === 1) {
            const e = new Error('EPERM: operation not permitted, rename');
            e.code = 'EPERM';
            throw e;
        }
        return real(from, to);
    };
    try {
        const status = statusLib.make({
            file,
            companionVersion: '0.1.0',
            clock: clock('2026-09-21T17:40:22Z'),
            onRetry: (tries) => said.push(`status file written after ${tries} tries; the client was reading it`),
        });
        const written = status.started();
        assert.equal(written.tries, 2);
        assert.deepEqual(said, ['status file written after 2 tries; the client was reading it']);
        assert.match(read(file), /state = "running"/);
    } finally {
        fs.renameSync = real;
    }
});
