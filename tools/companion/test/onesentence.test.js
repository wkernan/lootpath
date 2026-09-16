// C-14 (WKE-603): a failure's `message` is one sentence, always.
//
// `lib/status.js` has said "one sentence for the strip's tooltip" since C-9 and
// nothing enforced it. On 2026-09-16 the fork's click timed out on a disabled
// `Go!` and `status.failed('qe live', e.message, code)` put Playwright's whole
// error into `Data/CompanionStatus.lua`: seventeen lines of call log, the
// button's entire class list, and the ANSI colour codes the game's font draws
// as little boxes. `ns.Companion.StatusTooltip` printed it verbatim onto the
// status strip's tooltip, which is what the owner photographed.
//
// The input below is not a paraphrase. It is the exact text the companion
// wrote at 21:27:27Z, lifted out of the owner's own `Data/companion.log` and
// committed under `spec/fixtures/companion/`.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const statusLib = require('../lib/status');

const ESC = String.fromCharCode(27);
const DUMP = fs.readFileSync(
    path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'companion', 'playwright-go-disabled.txt'),
    'utf8'
);

function dataFile() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c14-status-'));
    fs.mkdirSync(path.join(root, 'Interface', 'AddOns', 'Lootpath'), { recursive: true });
    return path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', 'CompanionStatus.lua');
}

test("the fixture really is the dump that reached the owner's screen", () => {
    assert.ok(DUMP.split('\n').length > 10, 'a one-line fixture would prove nothing');
    assert.ok(DUMP.includes(ESC + '['), 'the escape sequences are the half the font draws as boxes');
    assert.ok(DUMP.includes('element is not enabled'));
    assert.ok(DUMP.includes('MuiButton'), 'the whole button markup went in too');
});

// Proven red by taking `oneSentence` back out of `status.failed`: the file
// carries all seventeen lines, escapes included, exactly as it did on the day.
test('a failure writes one clean line, and the log keeps the rest', () => {
    const file = dataFile();
    const status = statusLib.make({ file, clock: () => new Date('2026-09-16T21:27:27Z') });
    status.started();
    status.failed('qe live', DUMP, 4);

    assert.strictEqual(status.current().message, 'driving QE Live failed: locator.click: Timeout 20000ms exceeded.');

    const text = fs.readFileSync(file, 'utf8');
    assert.match(text, /message = "driving QE Live failed: locator\.click: Timeout 20000ms exceeded\."/);
    assert.ok(!text.includes(ESC), 'no escape sequence reaches the file');
    assert.ok(!text.includes('Call log'), 'the call log stays in companion.log');
    assert.ok(!text.includes('MuiButton'), 'the button markup stays in companion.log');
    assert.strictEqual(
        text.split('\n').filter((line) => line.includes('message =')).length,
        1,
        'one line in the chunk for the message, whatever came in'
    );
});

// The renderer is the second place it is enforced, so a record built by hand -
// or by a `stage()` call that was handed something long - cannot get past it.
test('the renderer caps a message even when nothing else did', () => {
    const text = statusLib.render({
        state: 'failed',
        stage: 'qe live',
        message: DUMP,
        at: new Date('2026-09-16T21:27:27Z'),
    });
    assert.ok(!text.includes(ESC));
    assert.ok(!text.includes('Call log'));
});

test('a message longer than the cap is cut, and says it was', () => {
    const long = 'x'.repeat(statusLib.MESSAGE_MAX + 50);
    assert.strictEqual(statusLib.oneSentence(long).length, statusLib.MESSAGE_MAX);
    assert.ok(statusLib.oneSentence(long).endsWith('...'));
});

test('a sentence that already fits is untouched, down to the byte', () => {
    const fits = 'refusing to rate a profile with an empty slot (legs); the previous verdict is untouched';
    assert.strictEqual(statusLib.oneSentence(fits), fits);
    assert.strictEqual(statusLib.oneSentence(undefined), undefined);
    assert.strictEqual(statusLib.oneSentence(null), null);
});
