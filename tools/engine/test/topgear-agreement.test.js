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
const fs = require('fs');
const crypto = require('crypto');
const T = require('../topgear-agreement');

// The game's own Data/EngineWeights.lua, read in the owner's install on
// 2026-10-06 (derived 2026-10-02T02:21:19.971Z), schema version 1: the refit,
// read back in version 1's layout (v1View below), must be it.
const GAME_WEIGHTS_SHA256 = '72126c5d940b949bea7f2daba87fa8326a8e6f33ce8ad3ca8632eeef7cb9c78d';
// The same refit as tools/engine writes it since E-4 (WKE-708), schema
// version 2: read from this test's own run.
const REFIT_V2_SHA256 = '7d67ff8dd53f490ddeeda5a406410e1d743079224f1cb0affa3d7c504dcb8ed7';

// v1View(text) -> the version 2 file in version 1's layout, byte for byte as
// tools/engine wrote it before E-4: `version = 1`, `method` and `derivedAt`
// back at the top, the spec's `role`, `primaryStat`, `stats`, `method` and
// `derivedAt` lines gone, its `tiers` block back at the end of the file one
// level out. Nothing else moves, so every number the game scored with is
// compared, unchanged, against the game's own file.
function v1View(text) {
    const one = (re, what) => {
        const m = text.match(re);
        assert.ok(m, `v1View: no ${what}`);
        return m;
    };
    const method = one(/\n {12}method = ("[^"]*"),/, 'spec method')[1];
    const derivedAt = one(/\n {12}derivedAt = ("[^"]*"),/, 'spec derivedAt')[1];
    const tiers = one(/\n {12}tiers = \{\n[\s\S]*?\n {12}\},/, 'spec tiers')[0];
    let out = text.replace(tiers, '');
    for (const re of [/\n {12}role = "[^"]*",/, /\n {12}primaryStat = "[^"]*",/, /\n {12}stats = \{[^}]*\n {12}\},/, /\n {12}method = "[^"]*",/, /\n {12}derivedAt = "[^"]*",/]) {
        assert.ok(re.test(out), `v1View: ${re}`);
        out = out.replace(re, '');
    }
    out = out.replace(/\n {4}version = 2,\n {4}devOnly = true,\n( {4}patch = "[^"]*",\n)/, (_, patch) => `\n    version = 1,\n    method = ${method},\n    devOnly = true,\n${patch}    derivedAt = ${derivedAt},\n`);
    const outdented = tiers.replace(/\n {8}/g, '\n');
    assert.ok(out.endsWith('\n}\n'), 'v1View: the file ends with its table');
    return `${out.slice(0, -3)}${outdented}\n}\n`;
}

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

test('the refitted weights are the game file, byte for byte, read in version 1\'s layout', (t) => {
    const r = result(t);
    if (!r) return;
    assert.equal(r.weights.sha256, REFIT_V2_SHA256);
    const v1 = v1View(fs.readFileSync(r.weights.path, 'utf8'));
    assert.equal(crypto.createHash('sha256').update(v1).digest('hex'), GAME_WEIGHTS_SHA256);
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
