// The thin layer C-1 puts around S-2's builder: one `{ ok, ... }` shape instead
// of a throw, and the spec check. S-2's own guards for the builder itself are in
// simc-profile.test.js beside this file.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const profileLib = require('../lib/profile');

const REPO = path.join(__dirname, '..', '..', '..');
const TRANSCRIPT = fs.readFileSync(path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20260906-200908.lua'), 'utf8');

test('builds from the committed transcript and reports what it counted', () => {
    const built = profileLib.build(TRANSCRIPT, {});
    assert.ok(built.ok, built.ok ? '' : built.reason);
    assert.strictEqual(built.counts.equipped, 15);
    assert.strictEqual(built.counts.bag, 35);
    assert.strictEqual(built.capturedAtLocal, '2026-09-05T13:33:25');
    assert.ok(built.text.startsWith('# Hotornot - Guardian'));
});

test('carries the identity the spec check needs', () => {
    const built = profileLib.build(TRANSCRIPT, {});
    assert.deepStrictEqual(built.identity, { name: 'Hotornot', realm: 'Arthas', spec: 'Guardian' });
});

test('names every field the SavedVariables could not answer', () => {
    const built = profileLib.build(TRANSCRIPT, {});
    // The committed transcript predates S-2's env capture, so all three are
    // missing and each is said out loud rather than written as an empty line.
    for (const field of ['region', 'level', 'race']) {
        assert.ok(
            built.warnings.some((w) => w.includes(field)),
            `nothing warned about ${field}: ${built.warnings.join(' | ')}`
        );
    }
    assert.ok(!built.text.split('\n').includes('region='), 'an empty region= would read as a measurement never taken');
    assert.ok(built.warnings.some((w) => w.includes('Great Vault')));
});

test('a transcript it cannot use is a named refusal, never a stack trace', () => {
    const notLootpath = profileLib.build('SomeOtherDB = {}', {});
    assert.strictEqual(notLootpath.ok, false);
    assert.match(notLootpath.reason, /no LootpathDB table/);
    assert.strictEqual(notLootpath.wanted, 'profile');

    const noInventory = profileLib.build('LootpathDB = { ["global"] = { ["captures"] = {} } }', {});
    assert.strictEqual(noInventory.ok, false);
    assert.match(noInventory.reason, /no `inventory` capture/);

    const notLua = profileLib.build('this is not a lua file', {});
    assert.strictEqual(notLua.ok, false);
    assert.ok(notLua.reason.length);
});

test('the bank can be left out', () => {
    const withBank = profileLib.build(TRANSCRIPT, { includeBank: true });
    const without = profileLib.build(TRANSCRIPT, { includeBank: false });
    assert.ok(withBank.ok && without.ok);
    assert.strictEqual(without.counts.bank, 0);
    assert.ok(without.counts.lines <= withBank.counts.lines);
});

test('says so when QE Live valued a different spec from the one captured', () => {
    // QE Live never reads the `spec=` line; it values whatever spec is selected
    // in its own character panel. Measured 2026-09-08: a profile written
    // spec=guardian came back as a "Restoration Druid" report.
    assert.strictEqual(profileLib.specMismatch('Restoration Druid', 'Restoration'), null);
    assert.strictEqual(profileLib.specMismatch('Restoration Druid', 'restoration druid'), null);
    assert.match(profileLib.specMismatch('Restoration Druid', 'Guardian'), /valued "Restoration Druid".*captured in "Guardian"/);
    // Nothing to compare is not a disagreement.
    assert.strictEqual(profileLib.specMismatch(null, 'Guardian'), null);
    assert.strictEqual(profileLib.specMismatch('Restoration Druid', null), null);
});

// M3-16 (WKE-557): the warning that sent the owner to this issue. It is about
// the rewards the profile could not carry, so it reads the same list
// `vaultRows` does - `snapshotRewardLinks`, which takes `interact.after` when
// the client had to be asked for the rewards and the top-level read otherwise.
// Which of the two it picks is guarded on real transcripts in
// simc-profile.test.js; what is guarded here is that the warning still fires,
// and only fires, when there is genuinely nothing to carry. Both transcripts
// are committed captures of the owner's own client.
const VAULT_WARNING = 'no generated Great Vault reward';
const WITH_REWARDS = fs.readFileSync(path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20260909-085940.lua'), 'utf8');

test('the no-vault-reward warning follows the reward list the profile actually read', () => {
    const withRewards = profileLib.build(WITH_REWARDS, {});
    assert.ok(withRewards.ok, withRewards.ok ? '' : withRewards.reason);
    assert.strictEqual(withRewards.counts.vault, 4);
    assert.ok(!withRewards.warnings.some((w) => w.includes(VAULT_WARNING)), withRewards.warnings.join(' | '));

    // The 09-06 transcript is a real capture with an empty reward list.
    const withoutRewards = profileLib.build(TRANSCRIPT, {});
    assert.ok(withoutRewards.ok, withoutRewards.ok ? '' : withoutRewards.reason);
    assert.strictEqual(withoutRewards.counts.vault, 0);
    assert.ok(withoutRewards.warnings.some((w) => w.includes(VAULT_WARNING)), withoutRewards.warnings.join(' | '));
});

// M3-16b (WKE-583): the choice of vault read is on the built profile, because
// the companion logs it. `0 vault` on the owner's reset day was a choice
// between snapshots and nothing said so.
test('the profile says which vault read it was built from', () => {
    // Proven red by dropping `vaultChoice` from the build's return: the
    // companion's log goes quiet about a choice that decided the vault
    // section.
    const withRewards = profileLib.build(WITH_REWARDS, {});
    assert.ok(withRewards.ok, withRewards.ok ? '' : withRewards.reason);
    assert.strictEqual(withRewards.counts.vault, 4);
    assert.strictEqual(withRewards.vaultChoice, 'the newest read that carries rewards; none of them asked');

    // A transcript with no vault capture at all says that, rather than nothing.
    const none = profileLib.build(TRANSCRIPT.replace(/\["vault"\]/g, '["vault_none"]'), {});
    assert.ok(none.ok, none.ok ? '' : none.reason);
    assert.strictEqual(none.vaultChoice, 'there is no vault snapshot in this transcript');
});
