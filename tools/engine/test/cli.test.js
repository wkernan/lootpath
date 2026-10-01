'use strict';

// End to end over the COMMITTED exports and capture: the tool runs, every row
// says where its stats came from, effects are excluded and counted, and the
// dev weights file it writes loads in Lua 5.1 - the gates' Lua, from PATH or
// the repo's Docker image. CI sets LOOTPATH_REQUIRE_LUA=1 so the Lua half can
// never skip there.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const { run } = require('../fit-weights');

const REPO = path.join(__dirname, '..', '..', '..');
const QE = path.join(REPO, 'spec', 'fixtures', 'qe');
// The two `capture upgrade` transcripts and, since E-0f, the `capture itemstats` one.
const CAPTURES = ['Lootpath-20260915-162015.lua', 'Lootpath-20260916-152428.lua', 'Lootpath-20261001-092631.lua'].map((f) => path.join(REPO, 'spec', 'fixtures', 'captures', f));
const SOURCES = new Set(['client', 'client-scaled', 'budget', 'budget-borrowed', 'none']);

let cached = null;
function runOnce() {
    if (cached) return cached;
    const out = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-engine-'));
    const args = ['--out', out, '--derived-at', '2026-09-30T00:00:00Z', '--key-levels', '1=2,2=4,4=6,6=8,7=10'];
    for (const c of CAPTURES) args.push('--stats', c);
    args.push(QE);
    cached = { out, ...run(args, () => {}) };
    return cached;
}

test('the tool runs over the eight committed Upgrade Finder exports', () => {
    const r = runOnce();
    assert.equal(r.fits.length, 8);
    for (const f of r.fits) {
        assert.ok(fs.existsSync(path.join(r.out, `${f.file.replace(/\.json$/, '')}-fit.json`)), f.file);
        assert.equal(f.rank, 6, `${f.file} rank`);
        assert.equal(f.resamples, 200);
    }
});

test('every row carries its stats source, and the fit file counts them', () => {
    const r = runOnce();
    for (const f of r.fits) {
        for (const row of f.rows) assert.ok(SOURCES.has(row.statsSource), `${f.file} ${row.id}@${row.level}: ${row.statsSource}`);
        const total = Object.values(f.statsSources.all).reduce((a, b) => a + b, 0);
        assert.equal(total, f.counts.rows);
    }
});

test('every document reads client stats from the itemstats transcript, and says how many', () => {
    const r = runOnce();
    for (const f of r.fits) {
        const fromItemstats = Object.entries(f.clientSources.all)
            .filter(([k]) => k.endsWith('<- capture itemstats'))
            .reduce((a, [, n]) => a + n, 0);
        assert.ok(fromItemstats > 0, `${f.file}: no row read from capture itemstats`);
        for (const row of f.rows) {
            if (row.statsSource === 'client' || row.statsSource === 'client-scaled') assert.ok(row.clientSource, `${f.file} ${row.id}@${row.level}`);
            else assert.equal(row.clientSource, null);
        }
    }
});

test('effect rows on the real exports: every trinket and the four named armour pieces', () => {
    const r = runOnce();
    const named = new Set([271875, 271092, 268265, 273778]);
    for (const f of r.fits) {
        const doc = JSON.parse(fs.readFileSync(path.join(QE, f.file), 'utf8'));
        const expected = doc.items.filter((i) => i.slot === 'Trinket' || named.has(i.id)).length;
        assert.equal(f.counts.effect, expected, f.file);
        assert.ok(f.rows.filter((x) => x.excluded === 'effect').every((x) => x.residual === null));
    }
});

test('the SIGN: observed is upgradePercent as exported, never negated', () => {
    const r = runOnce();
    const f = r.fits[0];
    const doc = JSON.parse(fs.readFileSync(path.join(QE, f.file), 'utf8'));
    doc.items.forEach((item, i) => assert.equal(f.rows[i].observed, item.upgradePercent));
});

test('the dev weights file: header, documents and their sha256s', () => {
    const r = runOnce();
    assert.ok(r.lua.startsWith('-- DEV ONLY - never ship.'));
    for (const f of fs.readdirSync(QE).filter((x) => /^qe-upgradefinder-/.test(x))) {
        const sha = crypto.createHash('sha256').update(fs.readFileSync(path.join(QE, f))).digest('hex');
        assert.ok(r.lua.includes(`--   ${f}  sha256 ${sha}`), f);
    }
    assert.match(r.lua, /method = "fit-to-qe-exports"/);
});

function findLua(dir) {
    const local = ['lua5.1', 'lua'].find((exe) => spawnSync(exe, ['-v'], { encoding: 'utf8' }).status === 0);
    if (local) return (script, file) => spawnSync(local, [path.join(dir, script), path.join(dir, file)], { encoding: 'utf8' });
    const img = spawnSync('docker', ['image', 'inspect', 'lootpath-lua'], { encoding: 'utf8' });
    if (img.status === 0) return (script, file) => spawnSync('docker', ['run', '--rm', '-v', `${dir}:/t`, 'lootpath-lua', 'lua', `/t/${script}`, `/t/${file}`], { encoding: 'utf8' });
    return null;
}

test('the dev weights file loads in Lua 5.1 and carries the fitted numbers', (t) => {
    const r = runOnce();
    const check = [
        'local chunk = assert(loadfile(arg[1]))',
        'local ns = {}',
        'chunk("Lootpath", ns)',
        'local w = assert(ns.engineWeights, "no ns.engineWeights")',
        'assert(w.schema == "lootpath-engine-weights" and w.version == 1 and w.method == "fit-to-qe-exports")',
        'local d = assert(w.specs[105].Dungeon.bands["10"], "no Dungeon band 10")',
        'local rd = assert(w.specs[105].Raid.bands["raid-3"], "no Raid band")',
        'print(string.format("%.17g %.17g %.17g %d", d.baseValue, d.weights.mastery, rd.weights.int, #w.fittedTo))',
    ].join('\n');
    fs.writeFileSync(path.join(r.out, 'check.lua'), check);
    const lua = findLua(r.out);
    if (!lua) {
        if (process.env.LOOTPATH_REQUIRE_LUA === '1') assert.fail('no Lua 5.1 on PATH and no lootpath-lua image, and LOOTPATH_REQUIRE_LUA=1');
        t.skip('no Lua 5.1 on PATH and no lootpath-lua Docker image');
        return;
    }
    const res = lua('check.lua', 'EngineWeights.dev.lua');
    assert.equal(res.status, 0, `lua failed: ${res.stderr}`);
    const [base, mastery, raidInt, docs] = res.stdout.trim().split(/\s+/).map(Number);
    // Dungeon band "10": the later of the two +10 documents wins (wyharestkdyr).
    const dungeon = r.fits.find((f) => f.document === 'wyharestkdyr');
    const raid = r.fits.find((f) => f.document === 'ynfzbppepnzw');
    assert.ok(Math.abs(base - dungeon.baseValue) < 1e-9, `${base} vs ${dungeon.baseValue}`);
    assert.ok(Math.abs(mastery - dungeon.weights.mastery) < 1e-12);
    assert.ok(Math.abs(raidInt - raid.weights.int) < 1e-15);
    assert.equal(docs, 8);
});
