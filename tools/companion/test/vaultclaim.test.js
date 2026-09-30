// C-15 (WKE-668): once the vault is claimed, the profile carries no vault
// section. A newer read in the same reward period that says nothing is waiting,
// after a read that carried rewards, is the claim - not a worse read to be
// passed over for the older one.
//
// The owner's week is `fixtures/Lootpath-20260930-live-vault.txt`: his live
// SavedVariables of 2026-09-30 11:49 local (sha256
// fd06f231f7090bee24a007c05c6ebddb8aa57221fe889d493fb12622b8176242), lines
// 120587-122077 - the `captures` key and the whole `vault` list, byte for byte
// (sha256 of those lines 04702ec96d0bbeb2e1d98032df291376f6698c6bf12485515775b5fb88406772)
// - wrapped in `LootpathDB = { ["global"] = {` and three closing braces so the
// companion's parser reads it. Nothing inside the list is altered; the parsed
// list deep-equals the one parsed out of the whole live file. It is `.txt`, not
// `.lua`, so the Lua gates (luacheck, StyLua), which exclude `spec/fixtures/`
// but not this folder, leave a transcript alone.
//
// Run from tools/companion with `node --test`.

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { parseSavedVariables, luaArray } = require('../lib/lua-savedvariables');
const { buildProfile, chooseVaultSnapshot, readTranscript, snapshotRewardLinks } = require('../lib/simc-profile');

const REPO = path.resolve(__dirname, '..', '..', '..');
const CAPTURES = path.join(REPO, 'spec', 'fixtures', 'captures');
const OWNER_WEEK = path.join(__dirname, 'fixtures', 'Lootpath-20260930-live-vault.txt');
const RESET_DAY = path.join(CAPTURES, 'Lootpath-20260915-142722-vault.lua');
const AFTER_CLAIM_0915 = path.join(CAPTURES, 'Lootpath-20260915-162015.lua');
const GEAR = path.join(CAPTURES, 'Lootpath-20260906-200908.lua');

const CLAIMED = 'claimed; no vault section this week';

function vaultList(file) {
    return luaArray(parseSavedVariables(fs.readFileSync(file, 'latin1')).LootpathDB.global.captures.vault);
}

// A JS array back into the shape a Lua list parses to (keyed from 1), which is
// what `chooseVaultSnapshot` is handed by `readTranscript`.
function luaList(snapshots) {
    const list = {};
    snapshots.forEach((snapshot, i) => {
        list[String(i + 1)] = snapshot;
    });
    return list;
}

const at = (snapshot) => new Date(snapshot.capturedAt * 1000).toISOString();
const links = (snapshot) => luaArray(snapshotRewardLinks(snapshot)).length;
const pack = (value) => ({ 1: value, n: 1 });

// A hand-built snapshot for the orderings no capture holds.
function read({ capturedAt, trigger = 'refresh', seconds, has, canClaim = false, withLinks = false }) {
    return {
        capturedAt,
        trigger,
        data: {
            secondsUntilWeeklyReset: pack(seconds),
            hasAvailableRewards: pack(has),
            canClaimRewards: pack(canClaim),
            interact: { attempted: false },
            rewardLinks: withLinks ? { 1: { itemDBID: `links@${capturedAt}` } } : {},
        },
    };
}

const week = vaultList(OWNER_WEEK);

test("the owner's week is the evidence: rewards at 21:49Z, then three reads saying nothing is waiting", () => {
    assert.equal(week.length, 4);
    assert.deepEqual(week.map(at), [
        '2026-09-29T21:49:32.000Z',
        '2026-09-29T22:01:12.000Z',
        '2026-09-30T00:11:49.000Z',
        '2026-09-30T00:27:51.000Z',
    ]);
    assert.deepEqual(week.map(links), [7, 0, 0, 0]);
    assert.deepEqual(
        week.map((s) => s.data.hasAvailableRewards[1]),
        [true, false, false, false]
    );
    assert.deepEqual(
        week.map((s) => s.data.canClaimRewards[1]),
        [false, false, false, false]
    );
    // None of them asked the client. The first did not need to (its activities
    // already carried the rewards); the other three could not be asked, because
    // the capture never asks a client that says nothing is waiting.
    for (const snapshot of week) {
        assert.equal(snapshot.trigger, 'refresh');
        assert.equal(snapshot.data.interact.attempted, false);
    }
    assert.equal(week[0].data.interact.reason, 'the activities already carry rewards');
    for (const snapshot of week.slice(1)) {
        assert.equal(snapshot.data.interact.reason, 'the client says no rewards are waiting');
    }
    // All four land on the same weekly reset.
    const resets = week.map((s) => s.capturedAt + s.data.secondsUntilWeeklyReset[1]);
    assert.ok(Math.max(...resets) - Math.min(...resets) <= 60, `resets ${resets.join(', ')}`);
});

test("after the claim the owner's week chooses the newest read, and the profile has no vault section", () => {
    // Proven red by removing the claim branch of chooseVaultSnapshot: the
    // 21:49Z read with seven links wins, as it did all week.
    const transcript = readTranscript(fs.readFileSync(OWNER_WEEK, 'latin1'), {});
    assert.equal(at(transcript.vault), '2026-09-30T00:27:51.000Z');
    assert.equal(
        transcript.vaultChoice,
        `the newest read says nothing is waiting after the 16:49:32 read carried rewards: ${CLAIMED}`
    );

    // The claim read alone, the very first one after it (22:01Z).
    const upToClaim = chooseVaultSnapshot(luaList(week.slice(0, 2)));
    assert.equal(at(upToClaim.snapshot), '2026-09-29T22:01:12.000Z');
    assert.ok(upToClaim.reason.endsWith(CLAIMED), upToClaim.reason);

    // Before the claim the read with rewards is still the one.
    const beforeClaim = chooseVaultSnapshot(luaList(week.slice(0, 1)));
    assert.equal(at(beforeClaim.snapshot), '2026-09-29T21:49:32.000Z');

    // What reaches the profile: the owner's week's vault on a committed
    // inventory. The claim gives no vault item; the 21:49Z read gives two (the
    // Hood and the ring; the keystones and tokens are not gear).
    const gear = readTranscript(fs.readFileSync(GEAR, 'latin1'), {});
    const claimed = buildProfile({ ...gear, vault: transcript.vault }, {});
    assert.equal(claimed.counts.vault, 0);
    const offered = buildProfile({ ...gear, vault: week[0] }, {});
    assert.equal(offered.counts.vault, 2);
});

test('the 2026-09-15 reset day still chooses the read that carries rewards', () => {
    const reset = vaultList(RESET_DAY);
    // Why an unload read is never the claim: two `logout` reads that morning
    // said nothing was waiting while the rewards were still there - the 13:57
    // refresh said true again and the 14:27 capture carried nine of them.
    assert.deepEqual(
        [reset[3], reset[4]].map((s) => [s.trigger, s.data.hasAvailableRewards[1], links(s)]),
        [
            ['logout', false, 0],
            ['logout', false, 0],
        ]
    );
    assert.equal(reset[5].trigger, 'refresh');
    assert.equal(reset[5].data.hasAvailableRewards[1], true);
    assert.equal(links(reset[11]), 9);

    const whole = readTranscript(fs.readFileSync(RESET_DAY, 'latin1'), {});
    assert.equal(at(whole.vault), '2026-09-15T19:27:22.000Z');
    assert.equal(whole.vaultChoice, 'the newest read that carries rewards; none of them asked');

    // Up to the 19:09 refresh that asked and the unload read two seconds after
    // it: no read of the period carries a link, so the newest, as before.
    const upTo1909 = chooseVaultSnapshot(luaList(reset.slice(0, 10)));
    assert.equal(at(upTo1909.snapshot), '2026-09-15T19:09:31.000Z');
    assert.equal(upTo1909.reason, 'the newest read; no snapshot this reward period carries a reward link');
});

test('a read holding the rewards back (true, no link) after a read with links is not a claim', () => {
    // The 09-15 shape the comment in chooseVaultSnapshot is about: the read
    // with rewards, then a plain read two seconds later that says rewards are
    // waiting and lists none. Proven red by dropping `hasAvailableRewards ===
    // false` from the claim test: the plain read wins as a "claim".
    const choice = chooseVaultSnapshot(
        luaList([
            read({ capturedAt: 1000, seconds: 500000, has: true, withLinks: true }),
            read({ capturedAt: 1002, trigger: 'command', seconds: 499998, has: true }),
        ])
    );
    assert.equal(choice.snapshot.capturedAt, 1000);
    assert.equal(choice.reason, 'the newest read that carries rewards; none of them asked');
});

test('an unload read saying nothing is waiting is not the claim', () => {
    // Proven red by dropping the unload filter: the logout read wins as a claim.
    for (const trigger of ['logout', 'flush']) {
        const choice = chooseVaultSnapshot(
            luaList([
                read({ capturedAt: 1000, seconds: 500000, has: true, withLinks: true }),
                read({ capturedAt: 2000, trigger, seconds: 499000, has: false }),
            ])
        );
        assert.equal(choice.snapshot.capturedAt, 1000, trigger);
    }
});

test('the claim read must be newer than the read with links', () => {
    // An empty refresh BEFORE the read with links is the vault before it
    // filled, not a claim. Proven red by dropping the "newer than" test: the
    // earlier empty refresh wins because the read with links is an unload read.
    const choice = chooseVaultSnapshot(
        luaList([
            read({ capturedAt: 1000, seconds: 500000, has: false }),
            read({ capturedAt: 2000, trigger: 'logout', seconds: 499000, has: true, withLinks: true }),
        ])
    );
    assert.equal(choice.snapshot.capturedAt, 2000);
});

test('a client that can still claim has not been claimed from', () => {
    // Mirrors VaultPanel.ClaimedThisPeriod's other half. Proven red by dropping
    // the `canClaimRewards` test.
    const choice = chooseVaultSnapshot(
        luaList([
            read({ capturedAt: 1000, seconds: 500000, has: true, withLinks: true }),
            read({ capturedAt: 2000, seconds: 499000, has: false, canClaim: true }),
        ])
    );
    assert.equal(choice.snapshot.capturedAt, 1000);
});

test('a period of empty reads only still chooses the newest', () => {
    const transcript = readTranscript(fs.readFileSync(AFTER_CLAIM_0915, 'latin1'), {});
    assert.equal(at(transcript.vault), '2026-09-15T21:20:15.000Z');
    assert.equal(transcript.vaultChoice, 'the newest read; no snapshot this reward period carries a reward link');
});

test("a new reward period is not touched by last week's claim", () => {
    // The owner's four reads, then one after the next reset. Its reset lands a
    // week after theirs (the period filter drops all four), so last week's
    // links and last week's claim are both out of the running.
    const lastReset = week[3].capturedAt + week[3].data.secondsUntilWeeklyReset[1];
    const nextAt = lastReset + 1200;
    const nextSeconds = lastReset + 604800 - nextAt;

    const withRewards = read({ capturedAt: nextAt, seconds: nextSeconds, has: true, withLinks: true });
    const offered = chooseVaultSnapshot(luaList([...week, withRewards]));
    assert.equal(offered.snapshot, withRewards);
    assert.equal(offered.reason, 'the newest read that carries rewards; none of them asked');

    const heldBack = read({ capturedAt: nextAt, seconds: nextSeconds, has: true });
    const waiting = chooseVaultSnapshot(luaList([...week, heldBack]));
    assert.equal(waiting.snapshot, heldBack);
    assert.equal(waiting.reason, 'the newest read; no snapshot this reward period carries a reward link');
});
