// C-16a (WKE-622): the companion's identity takes its spec from the newest
// `env` capture that NAMES one.
//
// The owner's C-16 companion restarted at 17:37:56 on 2026-09-21, driving his
// Restoration Shaman, and three runs in a row logged `character: not named by
// the capture (0 ms)` and then QE Live's own `You're currently a Restoration
// Druid but this SimC string is for a different spec.` C-16's switch never ran,
// because the field it switched on was always empty.
//
// The cause is one line of ordering. `/lootpath refresh` ends in a `/reload`,
// so a refresh's `env` snapshot is followed within a second by that reload's
// flush `env` - and a flush names no spec at all: `GetSpecializationInfo`
// answers id 0 and nothing else at `PLAYER_LOGOUT` (R-7b measured it; the
// owner's own four `env` snapshots of 2026-09-21 are the fixture below). So the
// NEWEST `env` is always the one snapshot that cannot answer this question.
//
// Nothing here opens a browser or touches the owner's game folder.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const profileLib = require('../lib/profile');
const simc = require('../lib/simc-profile');

const CAPTURES = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'captures');
const PAIR = fs.readFileSync(path.join(CAPTURES, 'flush-after-refresh.lua'), 'utf8');
const FLUSH_ONLY = fs.readFileSync(path.join(CAPTURES, 'empty-equipment-flush.lua'), 'utf8');

// The parsed shape of one `env` snapshot, which is all `characterSpec` reads.
// `data.player` / `data.realm` / `data.specInfo` are `ns.Probe` packs, keyed by
// position with an `n`; the fixture above proves this shape against the owner's
// real file, and these let one field move at a time.
function snapshot(options) {
    const opts = options || {};
    return {
        name: 'env',
        trigger: opts.trigger || 'flush',
        capturedAt: opts.at,
        capturedAtLocal: opts.local || '',
        data: {
            player: { 1: opts.player || 'Blueheeler', n: 1 },
            realm: { 1: opts.realm || 'Arthas', n: 1 },
            class: { 1: 'Shaman', 2: 'SHAMAN', 3: 11, n: 3 },
            specInfo: opts.spec ? { 1: 264, 2: opts.spec, n: 10 } : { 1: 0, 7: 0, 9: 0, 10: true, n: 10 },
        },
    };
}

test('the newest env is a nameless flush, so the spec comes from the refresh before it', () => {
    const built = profileLib.build(PAIR, {});
    assert.ok(built.ok, built.ok ? '' : built.reason);
    // The newest snapshot is the 17:42:49 flush and it is the one the name,
    // realm and class still come from.
    assert.strictEqual(built.capture.trigger, 'flush');
    assert.deepStrictEqual(built.identity, {
        name: 'Blueheeler',
        realm: 'Arthas',
        spec: 'Restoration',
        class: 'SHAMAN',
    });
});

test('the borrowed read is named in one line, and a spec the newest read named is not', () => {
    const built = profileLib.build(PAIR, {});
    assert.strictEqual(built.specChoice, 'spec from the 17:39:15 refresh read; the flush names none');

    // Nothing is said when the newest snapshot answered for itself: the line is
    // about a choice between snapshots, and there was none to make.
    const one = simc.characterSpec([snapshot({ at: 10, local: '2026-09-21T17:39:15', trigger: 'refresh', spec: 'Restoration' })], null);
    assert.strictEqual(one.spec, undefined, 'no chosen snapshot is no answer');
    const newest = snapshot({ at: 20, local: '2026-09-21T17:39:15', trigger: 'refresh', spec: 'Restoration' });
    const chose = simc.characterSpec([snapshot({ at: 10 }), newest], newest);
    assert.strictEqual(chose.spec, 'Restoration');
    assert.strictEqual(chose.note, null);
});

test('a spec is never borrowed across characters', () => {
    // The Druid's refresh and the Shaman's flush in one account-wide store is
    // exactly the pair that filed C-15; borrowing across it would put the
    // Druid's spec on the Shaman, which is the failure this is fixing.
    const druid = snapshot({ at: 10, local: '2026-09-21T17:39:15', trigger: 'refresh', player: 'Hotornot', spec: 'Restoration' });
    const shaman = snapshot({ at: 20, local: '2026-09-21T17:39:16', player: 'Blueheeler' });
    assert.strictEqual(simc.characterSpec([druid, shaman], shaman).spec, undefined);

    // Same name on another realm is another character too.
    const otherRealm = snapshot({ at: 10, local: '2026-09-21T17:39:15', trigger: 'refresh', realm: 'Area 52', spec: 'Restoration' });
    assert.strictEqual(simc.characterSpec([otherRealm, shaman], shaman).spec, undefined);

    // And the same character IS borrowed from, so the two cases above are the
    // rule doing its job rather than the reader never answering.
    const own = snapshot({ at: 10, local: '2026-09-21T17:39:15', trigger: 'refresh', spec: 'Restoration' });
    assert.strictEqual(simc.characterSpec([own, shaman], shaman).spec, 'Restoration');
});

test('the reader never reads forward from the snapshot the run was built on', () => {
    // `--env-snapshot` names an older `env` on purpose; a spec taken from a
    // newer one would make that flag mean something else.
    const older = snapshot({ at: 10, local: '2026-09-21T17:39:14' });
    const newer = snapshot({ at: 30, local: '2026-09-21T17:40:19', trigger: 'refresh', spec: 'Restoration' });
    assert.strictEqual(simc.characterSpec([older, newer], older).spec, undefined);
});

test('a transcript whose captures name no spec anywhere says so and keeps "unknown"', () => {
    // R-7b's fixture is one flush and nothing else - a real logout, with no
    // refresh behind it in the four snapshots the addon keeps.
    const built = profileLib.build(FLUSH_ONLY, {});
    assert.ok(built.ok, built.ok ? '' : built.reason);
    assert.strictEqual(built.identity.spec, undefined);
    assert.strictEqual(built.specChoice, null);
    assert.ok(
        built.warnings.some((w) => w.includes('no capture names this character\'s spec')),
        built.warnings.join(' | ')
    );
    assert.ok(built.text.split('\n')[0].includes(' - unknown - '), built.text.split('\n')[0]);
});

test("the SimC header's spec and the identity's spec are one answer", () => {
    // Requirement 3: `spec=unknown` stops appearing in a profile whose captures
    // name the spec. The header's first line carries the spec's name and the
    // `spec=` line carries its token, and both come from the same reader.
    const built = profileLib.build(PAIR, {});
    assert.ok(built.ok, built.ok ? '' : built.reason);
    const lines = built.text.split('\n');
    assert.strictEqual(lines[0], '# Blueheeler - Restoration - 2026-09-21 17:42 - US/Arthas');
    assert.ok(lines.includes('spec=restoration'), 'no spec= line for a character whose captures name one');
    assert.ok(!lines.includes('spec=unknown'), 'the flush-only reading is gone');
    assert.strictEqual(lines[0].split(' - ')[1], built.identity.spec);
});
