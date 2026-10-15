'use strict';

// E-1b (WKE-688): the Top Gear compare's best-set search over pass 1's pool,
// run for real - EngineCompare.lua, EngineSearch.lua and EngineScore.lua in Lua
// 5.1 through the specs' stub world - over week one as the owner's client
// stored it (spec/fixtures/captures/Lootpath-20261002-112757.lua, read 4), the
// client's own item reads, and the dev weights the game ran, refitted from the
// committed inputs. CI sets LOOTPATH_REQUIRE_LUA=1 so it never skips there.
// Every figure pinned below was read from the harness's own output on these
// files (ARCHITECTURE.md section 9, 2026-10-06, E-1b).
const test = require('node:test');
const assert = require('node:assert/strict');
const T = require('../topgear-agreement');

// The game's own Data/EngineWeights.lua, read in the owner's install on
// 2026-10-06 (derived 2026-10-02T02:21:19.971Z): the refit must be it.
const GAME_WEIGHTS_SHA256 = '72126c5d940b949bea7f2daba87fa8326a8e6f33ce8ad3ca8632eeef7cb9c78d';

let cached = null;
function result(t) {
    if (cached) return cached;
    if (!T.findLua()) {
        if (process.env.LOOTPATH_REQUIRE_LUA === '1') assert.fail('no Lua 5.1 on PATH and no lootpath-lua image, and LOOTPATH_REQUIRE_LUA=1');
        t.skip('no Lua 5.1 on PATH and no lootpath-lua Docker image');
        return null;
    }
    cached = T.run({});
    return cached;
}

const near = (expected, actual, tol, what) => assert.ok(Math.abs(expected - actual) <= tol, `${what}: expected ${expected}, got ${actual}`);
const caseOf = (r, mode, name) => r.cases.find((c) => c.mode === mode && c.name === name);

test('the refitted weights are the game file, byte for byte', (t) => {
    const r = result(t);
    if (!r) return;
    assert.equal(r.weights.sha256, GAME_WEIGHTS_SHA256);
});

test('the single-swap rows reproduce the rows week one STORED (effects as the game ran them)', (t) => {
    const r = result(t);
    if (!r) return;
    // Dungeon's pass-1 entry was stored by the +10 run (one pass1 shelf per
    // content type), so +10 and Raid are the two the store holds.
    for (const name of ['dungeon 10', 'raid']) {
        const c = caseOf(r, 'stripped', name);
        assert.ok(c.stored.length > 0, name);
        assert.equal(c.rows.length, c.stored.length, name);
        const stored = new Map(c.stored.map((s) => [s.key, s]));
        for (const row of c.rows) {
            assert.ok(stored.has(row.key), `${name} ${row.key}`);
            near(stored.get(row.key).ours, row.ours, 1e-5, `${name} ${row.key}`);
            assert.equal(row.theirs, stored.get(row.key).theirs);
        }
    }
});

test('the worn set: 119.7418 (+10) and 119.5546 (Raid) by the game file - client conversion and dr table alike', (t) => {
    const r = result(t);
    if (!r) return;
    const d10 = caseOf(r, 'stripped', 'dungeon 10');
    const raid = caseOf(r, 'stripped', 'raid');
    for (const [c, v] of [
        [d10, 119.74184626955022],
        [raid, 119.55458434955396],
    ]) {
        assert.equal(c.worn.pieces, 15);
        near(v, c.worn.client, 1e-9, `${c.name} client`);
        near(v, c.worn.table, 1e-9, `${c.name} table`);
        // The block's forceTier-on worn value is the same set at four pieces.
        near(v, c.values.worn, 1e-9, `${c.name} block`);
    }
    // The worn pieces as read: the head at 318, Ula'tek's Bind at 292 - the
    // set the screen of 2026-10-05 no longer wore (its head read 321, the ring 308).
    const levels = Object.fromEntries(d10.wornPieces.map((p) => [p.itemID, p.level]));
    assert.equal(levels[271528], 318);
    assert.equal(levels[279010], 292);
});

test('top-set agreement on week one, per band (shipped effects)', (t) => {
    const r = result(t);
    if (!r) return;
    const expected = {
        'dungeon 6': { agree: 12, band: '6', at: ['Head', 'Waist', 'Finger'] },
        'dungeon 10': { agree: 12, band: '10', at: ['Head', 'Waist', 'Finger'] },
        raid: { agree: 13, band: 'raid-3', at: ['Neck', 'Finger'] },
    };
    for (const mode of ['stripped', 'shipped']) {
        for (const [name, e] of Object.entries(expected)) {
            const c = caseOf(r, mode, name);
            assert.equal(c.search.agree, e.agree, `${mode} ${name}`);
            assert.equal(c.search.positions, 15, `${mode} ${name}`);
            assert.equal(c.search.band, e.band, `${mode} ${name}`);
            assert.equal(c.search.pool, 30, `${mode} ${name}`);
            assert.equal(c.search.outside, 9, `${mode} ${name}`);
            assert.equal(c.search.notReady, 0, `${mode} ${name}`);
            assert.deepEqual(
                c.diffs.map((d) => d.position),
                e.at,
                `${mode} ${name}`
            );
            for (const d of c.diffs) {
                assert.equal(d.ours.length, 1, `${mode} ${name} ${d.position}`);
                assert.equal(d.theirs.length, 1, `${mode} ${name} ${d.position}`);
                assert.ok(d.delta > 0, `${mode} ${name} ${d.position}: our piece scores higher by our value`);
            }
            // The chat says it: one line per disagreement, then the count.
            const differs = c.chat.filter((l) => l.includes('top set differs at '));
            assert.equal(differs.length, e.at.length, `${mode} ${name}`);
            assert.ok(c.chat.some((l) => l.includes(`top set: agrees on ${e.agree} of 15 positions`)), `${mode} ${name}`);
        }
    }
    // The ring: ours Ritual Binder's Ring 308 from the bag, QE Live's the worn Ula'tek's Bind 292.
    const ring = caseOf(r, 'shipped', 'raid').diffs.find((d) => d.position === 'Finger');
    assert.deepEqual(ring.ours, ['159459:6652:12699:12842:13440:13668']);
    assert.deepEqual(ring.theirs, ['279010:41:12833:13668']);
});

test('`engine best` on week one: no single slot reads its own piece as the runner-up', (t) => {
    const r = result(t);
    if (!r) return;
    for (const c of r.cases) {
        const legs = c.positions.find((p) => p.position === 'Legs');
        assert.equal(legs.state, 'only', c.name);
        assert.equal(legs.candidates, 1, c.name);
        assert.ok(c.best.some((l) => l.includes('Legs: ') && l.endsWith(' · only piece')), c.name);
        for (const p of c.positions) {
            if (p.state === 'next') assert.ok(p.delta > 0, `${c.mode} ${c.name} ${p.position}: delta ${p.delta}`);
        }
        assert.ok(!c.best.some((l) => l.includes('next best -0.000%')), `${c.mode} ${c.name}`);
    }
    // Before E-3c's params, the worn Oculus and Mycolic Medicine are the same
    // intellect at 308: a true tie, named.
    const before = caseOf(r, 'stripped', 'dungeon 10');
    assert.equal(before.positions.find((p) => p.position === 'Trinket 1').state, 'tie');
    assert.ok(before.best.some((l) => l.includes('Trinket 1: Pulse Seeker\'s Oculus 308 · worn · next best tie: Mycolic Medicine 308')));
});
