'use strict';

// E-1d (WKE-687): the offline exhaustive check. Brute force over every
// wearable set, valued with lib/score.js, against the REAL search -
// Lootpath/Modules/EngineSearch.lua run unchanged in Lua 5.1 (PATH, or the
// gates' lootpath-lua image; CI sets LOOTPATH_REQUIRE_LUA=1 so it never skips
// there).
//
//   synthetic   six seeded inventories with every slot kind (single slots, a
//               unique ring and its copy, a limit category across neck and
//               ring, unique trinkets, one-hand + off-hand + shield against
//               two two-handers, a tier set that pays only at four pieces,
//               outclassed spares, a parity finish with a gem and a ring
//               enchant): the Node enumeration equals EngineSearch.BruteForce
//               (the port of the rules is held to the Lua's own), the search
//               equals it, the kept pool keeps the optimum, Node's drop is the
//               Lua's - and the RED proof: a lone coordinate ascent without the
//               tier masks misses the optimum on a seed, and the comparison
//               says so.
//   real        the owner's 40 owned pieces with client-read stats (the
//               committed 2026-10-01 itemstats transcript; the same 40 links
//               as the committed 2026-10-02 inventory snapshots), the dev
//               weights the game ran, Dungeon +10 and Raid: every-piece and
//               kept-pool brute force, the search, every mask's ascent.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { parseSavedVariables, luaArray } = require('../../companion/lib/lua-savedvariables');
const { strippedKey } = require('../lib/stats');
const X = require('../exhaustive');

const REPO = path.join(__dirname, '..', '..', '..');
const OWNED_SNAPSHOT_FILE = path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20261002-112757.lua');

function needLua(t) {
    if (X.findLua()) return true;
    if (process.env.LOOTPATH_REQUIRE_LUA === '1') assert.fail('no Lua 5.1 on PATH and no lootpath-lua image, and LOOTPATH_REQUIRE_LUA=1');
    t.skip('no Lua 5.1 on PATH and no lootpath-lua Docker image');
    return false;
}

// --- synthetic ---------------------------------------------------------------

const { inventory, syntheticFile, writeFile } = require('../lib/synthetic');

const SEEDS = [1, 2, 3, 4, 5, 6];
const TIER4 = [1.06, 1.12];
const NO_EFFECTS = new Set();

// Where EngineSearch (E-1a) misses the brute-force optimum on these seeds -
// measured 2026-10-05 and pinned, so a change to the search shows here
// (ARCHITECTURE.md section 11, E-1d). `slots`: the positions where the search's
// set and the optimum differ; no single one of them improves alone.
//   plain    seed 1: the trinket pair and the weapon must change together -
//            the totals sit in the DR brackets, so the value is not separable
//   category seeds 3 and 5: a limit category of one shared by a neck and a
//            ring - the neck must leave the category before the ring can join
//            it, two coordinates at once
const KNOWN_MISSES = {
    'plain/1/1.06': '2H Weapon,Trinket',
    'plain/1/1.12': '2H Weapon,Trinket',
    'category/3/1.06': 'Finger,Hands,Legs,Neck',
    'category/3/1.12': 'Finger,Hands,Legs,Neck',
    'category/5/1.06': 'Finger,Neck',
    'category/5/1.12': 'Finger,Neck',
};

function bruteBoth(pieces, file, band) {
    const value = X.scorer(file, band);
    const out = {};
    for (const mode of ['all', 'kept']) {
        const p = X.pools(X.cands(pieces, file, band), band, NO_EFFECTS, mode === 'kept');
        out[mode] = { ...X.enumerate(X.coordinates(p.pools), value), dropped: p.dropped.map((c) => c.piece.idx) };
    }
    return out;
}

let syntheticRuns = null;
function synthetic() {
    if (syntheticRuns) return syntheticRuns;
    syntheticRuns = [];
    for (const variant of ['plain', 'category']) {
        for (const seed of SEEDS) {
            for (const tier4 of TIER4) {
                const pieces = inventory(seed, { category: variant === 'category' });
                const w = writeFile(syntheticFile(tier4));
                const { band } = X.bandFor(w.file, 'Dungeon', 10);
                const b = bruteBoth(pieces, w.file, band);
                // One Lua run: EngineSearch.BruteForce, then Best and every Ascend.
                const s = X.runLua(pieces, w.luaPath, 'Dungeon', 10, 'both');
                const lb = s;
                syntheticRuns.push({ key: `${variant}/${seed}/${tier4}`, pieces, b, lb, s });
            }
        }
    }
    return syntheticRuns;
}

// The positions where two sets differ, by slot.
function differing(run, a, b) {
    const by = new Map(run.pieces.map((p) => [p.idx, p]));
    const sa = new Set(a);
    const sb = new Set(b);
    const slots = new Set();
    for (const i of sa) if (!sb.has(i)) slots.add(by.get(i).slot);
    for (const i of sb) if (!sa.has(i)) slots.add(by.get(i).slot);
    return [...slots].sort().join(',');
}

test('synthetic: the Node enumeration is EngineSearch.BruteForce on every seed (the rules port)', (t) => {
    if (!needLua(t)) return;
    for (const run of synthetic()) {
        assert.equal(run.b.all.sets, 20736, run.key);
        assert.equal(run.lb.brute.sets, run.b.all.sets, run.key);
        assert.equal(run.lb.brute.evaluations, run.b.all.feasible, `${run.key}: feasible sets`);
        const c = X.compare(run.b.all.best, run.lb.brute.value, run.lb.brute.items, run.pieces);
        assert.ok(c.equal, `${run.key}: Node ${run.b.all.best.value} vs Lua BruteForce ${run.lb.brute.value}`);
    }
});

test('synthetic: the kept pool keeps the optimum and drops what Candidates drops', (t) => {
    if (!needLua(t)) return;
    for (const run of synthetic()) {
        assert.ok(run.b.kept.sets < run.b.all.sets, `${run.key}: the spares are dropped`);
        assert.ok(X.compare(run.b.all.best, run.b.kept.best.value, run.b.kept.best.items.map((c) => c.piece.idx), run.pieces).equal, `${run.key}: kept pool`);
        assert.deepEqual(run.s.dropped, run.b.kept.dropped, `${run.key}: the same pieces dropped`);
    }
});

test('synthetic: the search equals brute force but where a two-coordinate move is needed (pinned)', (t) => {
    if (!needLua(t)) return;
    const misses = {};
    for (const run of synthetic()) {
        const c = X.compare(run.b.all.best, run.s.best.value, run.s.items, run.pieces);
        if (!c.equal) {
            assert.ok(c.delta > 0, `${run.key}: a miss is below the optimum, never above`);
            misses[run.key] = differing(
                run,
                run.b.all.best.items.map((x) => x.piece.idx),
                run.s.items
            );
        }
    }
    assert.deepEqual(misses, KNOWN_MISSES);
});

test('synthetic RED: a lone ascent without the tier masks misses, and the comparison says so', (t) => {
    if (!needLua(t)) return;
    let missed = 0;
    for (const run of synthetic()) {
        const lone = X.compare(run.b.all.best, run.s.lone.value, run.s.lone.items, run.pieces);
        if (!lone.equal) {
            missed += 1;
            assert.ok(lone.delta > 0, run.key);
        }
    }
    assert.ok(missed > 0, 'no lone ascent misses: the comparison has nothing to catch');
});

test('compare: a pair in either order is one set; a different set or value is not', () => {
    const pieces = [
        { idx: 1, key: 'a' },
        { idx: 2, key: 'b' },
        { idx: 3, key: 'c' },
    ];
    const best = { value: 10, items: [{ piece: pieces[0] }, { piece: pieces[1] }] };
    assert.ok(X.compare(best, 10, [2, 1], pieces).equal);
    assert.ok(!X.compare(best, 10, [1, 3], pieces).setEqual);
    assert.ok(!X.compare(best, 9.99, [1, 2], pieces).valueEqual);
});

// --- real ------------------------------------------------------------------

test('the pieces are the owned set: 40 client reads, the same links as the committed 2026-10-02 inventory', () => {
    const pieces = X.piecesFromItemStats(X.DEFAULT_ITEMSTATS);
    assert.equal(pieces.length, 40);
    assert.equal(pieces.filter((p) => p.location === 'equipped').length, 15);
    const sv = parseSavedVariables(fs.readFileSync(OWNED_SNAPSHOT_FILE, 'utf8'));
    const snaps = luaArray(sv.LootpathDB.global.captures.inventory);
    const last = snaps[snaps.length - 1];
    assert.equal(last.capturedAtLocal, '2026-10-02T11:27:57');
    const links = [];
    for (const e of luaArray(last.data.equipped)) links.push(luaArray(e.link)[0]);
    for (const bag of luaArray(last.data.bags)) {
        for (const it of Object.values(bag.items || {})) {
            if (!it || typeof it !== 'object' || !it.item) continue;
            const loc = luaArray(it.item.instant)[3];
            if (loc && /^INVTYPE_(HEAD|NECK|SHOULDER|CLOAK|CHEST|ROBE|WRIST|HAND|WAIST|LEGS|FEET|FINGER|TRINKET|WEAPON|2HWEAPON|WEAPONMAINHAND|WEAPONOFFHAND|HOLDABLE|SHIELD|RANGED|RANGEDRIGHT)$/.test(loc)) links.push(luaArray(it.link)[0]);
        }
    }
    assert.deepEqual(links.map(strippedKey).sort(), pieces.map((p) => p.key).sort());
});

let weightsOnce = null;
const gameWeights = () => (weightsOnce = weightsOnce || X.gameWeights());

// Figures read from `node exhaustive.js dungeon 10` and `raid`, 2026-10-05.
const REAL = [
    { name: 'Dungeon +10', contentType: 'Dungeon', keyLevel: 10, band: '10', worn: 119.741846, best: 120.094083 },
    { name: 'Raid', contentType: 'Raid', keyLevel: null, band: 'raid-3', worn: 119.554584, best: 120.855172 },
];

for (const r of REAL) {
    test(`real, ${r.name}: brute force over every piece and the kept pool, and the search, agree`, (t) => {
        if (!needLua(t)) return;
        const pieces = X.piecesFromItemStats(X.DEFAULT_ITEMSTATS);
        const res = X.check({ pieces, weights: gameWeights(), contentType: r.contentType, keyLevel: r.keyLevel });
        assert.equal(res.band, r.band);
        assert.equal(res.derivedAt, X.GAME_DERIVED_AT);
        assert.equal(res.modes.all.sets, 3499200);
        assert.equal(res.modes.kept.sets, 2332800);
        assert.equal(res.modes.all.dropped.length, 0);
        assert.equal(res.modes.kept.dropped.length, 1);
        assert.ok(Math.abs(res.worn - r.worn) < 5e-7, `worn ${res.worn}`);
        assert.ok(Math.abs(res.modes.all.best.value - r.best) < 5e-7, `best ${res.modes.all.best.value}`);
        assert.equal(res.modes.kept.best.value, res.modes.all.best.value, 'the outclass rule drops no optimum');
        // The Lua: the game's own counts on the owner's screen, 2026-10-05
        // (632 set values over 16 masks, 1 piece outclassed).
        assert.equal(res.search.best.evaluations, 632);
        assert.equal(res.search.best.masks, 16);
        assert.deepEqual(res.search.dropped, res.modes.kept.dropped);
        assert.ok(Math.abs(res.search.worn - res.worn) <= Math.abs(res.worn) * 1e-12, 'EngineScore and score.js value the worn set alike');
        assert.ok(res.compare.equal, `search ${res.search.best.value} vs brute ${res.modes.all.best.value}`);
        assert.equal(res.maskCompare.length, 16);
        for (const m of res.maskCompare) assert.ok(m.equal, `mask ${m.mask}: ascend ${m.ascend}, brute ${m.brute}`);
    });
}

test('scoreTiers refuses a file score.js cannot count', () => {
    assert.throws(() => X.scoreTiers(new Map()), /one tier set/);
    assert.throws(() => X.scoreTiers(new Map([[1, new Map([[2, { mult: 1.1 }]])]])), /2- and a 4-piece/);
    assert.deepEqual(X.scoreTiers(new Map([[2057, new Map([[2, { mult: 1.03 }], [4, { mult: 1.055 }]])]])).setIDs, [2057]);
});
