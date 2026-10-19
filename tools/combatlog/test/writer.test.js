'use strict';

// The writer over the committed fixture: E-4's version 2 entry with
// method = "combat-log", one Dungeon band "12", the unshipped rule in the
// file; two runs write byte-identical output; and EngineScore.Load, in Lua,
// accepts the file on a 12.1.5 client (the way tools/simc's writer test loads
// SimC's).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const weights = require('../weights');
const { loadDR, ratingToPercent } = require('../lib/dr');

const REPO = path.join(__dirname, '..', '..', '..');
const FIXTURE = path.join(REPO, 'spec', 'fixtures', 'combatlog', 'WoWCombatLog-20261017-AltarOfFangs-12.txt.gz');

const tmpDirs = [];
test.after(() => {
    for (const dir of tmpDirs) fs.rmSync(dir, { recursive: true, force: true });
});

function writeOnce() {
    const out = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-combatlog-w-'));
    tmpDirs.push(out);
    const r = weights.run([FIXTURE, '--patch', '12.1.5', '--derived-at', '2026-10-17T22:16:10Z', '--out', out], () => {});
    return { ...r, json: fs.readFileSync(path.join(out, 'combatlog-weights.json'), 'utf8') };
}
// The first run's output must survive until the Lua tests below read first.file,
// so its folder is removed by the top-level after hook, not a per-test one.
const first = writeOnce();

test('version 2, method combat-log, Restoration\'s six stats, one Dungeon band "12" per percent, the tiers neutral', () => {
    assert.match(first.lua, /^-- DEV ONLY - never ship\./);
    assert.match(first.lua, /version = 2,/);
    assert.match(first.lua, /patch = "12\.1\.5",/);
    const e = first.table.specs.get(105);
    assert.equal(e.method, 'combat-log');
    assert.equal(e.role, 'HEALER');
    assert.equal(e.primaryStat, 'int');
    assert.deepEqual(e.stats, ['int', 'haste', 'crit', 'mastery', 'vers', 'leech']);
    assert.deepEqual(Object.keys(e.Dungeon.bands), ['12']);
    assert.equal(e.Raid, undefined);
    const b = e.Dungeon.bands['12'];
    assert.equal(b.unit, 'per percent');
    assert.deepEqual([...e.tiers.keys()], [-1]);
    // The provenance: the log by sha256, the key, the segments and events.
    assert.equal(e.logs[0].sha256, 'f56583dd549a25b7893fd24e45678edbda837b6c0c376db1497f767d532566dd');
    assert.deepEqual(e.logs[0].keys, [{ zone: 'Altar of Fangs', level: 12, timed: true, durationMs: 1218077 }]);
    assert.equal(b.segments, 6);
    assert.equal(e.segmentsDropped, 1);
    assert.equal(b.events, 19255);
    // The value at her stats is 100: base + w . x(observed).
    const dr = loadDR();
    const x = { int: b.player.int };
    for (const k of ['haste', 'crit', 'mastery', 'vers', 'leech']) x[k] = ratingToPercent(b.player.ratings[k], dr[k]);
    const v = b.baseValue + Object.keys(x).reduce((s, k) => s + b.weights[k] * x[k], 0);
    assert.ok(Math.abs(v - 100) < 1e-5, `value at her stats ${v}`);
});

test("the honesty rule is in the file: every stat whose interval overlaps a neighbour's is unshipped with its reason", () => {
    const b = first.table.specs.get(105).Dungeon.bands['12'];
    const ranked = Object.entries(b.perRatingPoint).sort((p, q) => q[1].mean - p[1].mean);
    ranked.forEach(([k, r], i) => {
        if (k === 'int') return;
        const overlaps = [ranked[i - 1], ranked[i + 1]].filter(Boolean).some(([, n]) => r.lo <= n.hi && n.lo <= r.hi);
        assert.equal(Boolean(b.unshipped && b.unshipped[k]), overlaps, k);
        if (overlaps) assert.match(b.unshipped[k], /overlaps .* in rank/);
    });
    assert.match(first.lua, /unshipped = \{/);
});

test('two runs over the fixture write byte-identical Lua and JSON', () => {
    const second = writeOnce();
    assert.equal(second.lua, first.lua);
    assert.equal(second.json, first.json);
});

const CHECK = `
local repo, clientPatch, file = arg[1], arg[2], arg[3]
local ns = { onReady = {} }
ns.Safe = function(v) return v, false end
assert(loadfile(file))("Lootpath", ns)
GetBuildInfo = function() return clientPatch end
assert(loadfile(repo .. "/Lootpath/Modules/EngineScore.lua"))("Lootpath", ns)
local ok, line, detail = ns.EngineScore.Load()
print(ok and "ok" or "refused")
print(tostring(line))
print(tostring(detail))
if ok then
    local stats, ratings, primary = ns.EngineScore.StatsFor(105)
    print(primary .. " " .. table.concat(stats, ","))
    local band, key = ns.EngineScore.BandFor(ns.engineWeights, 105, "Dungeon", 12)
    print(tostring(key) .. " " .. string.format("%.9g", band.weights.mastery))
end
`;

function findLua() {
    const local = ['lua5.1', 'lua'].find((exe) => spawnSync(exe, ['-v'], { encoding: 'utf8' }).status === 0);
    if (local) return (script, clientPatch, file) => spawnSync(local, [script, REPO, clientPatch, file], { encoding: 'utf8' });
    const img = spawnSync('docker', ['image', 'inspect', 'lootpath-lua'], { encoding: 'utf8' });
    if (img.status !== 0) return null;
    return (script, clientPatch, file) =>
        spawnSync(
            'docker',
            ['run', '--rm', '-v', `${REPO}:/repo`, '-v', `${path.dirname(script)}:/t`, '-v', `${path.dirname(file)}:/f`, 'lootpath-lua', 'lua', `/t/${path.basename(script)}`, '/repo', clientPatch, `/f/${path.basename(file)}`],
            { encoding: 'utf8' }
        );
}

function load(clientPatch, t) {
    const lua = findLua();
    if (!lua) return null;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-combatlog-lua-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const script = path.join(dir, 'check.lua');
    fs.writeFileSync(script, CHECK);
    const res = lua(script, clientPatch, first.file);
    if (res.status === null) throw new Error(`lua did not run: ${res.error}`);
    assert.equal(res.status, 0, `lua failed: ${res.stderr}`);
    return res.stdout.trim().split('\n');
}

// CI sets LOOTPATH_REQUIRE_LUA=1, so these never skip there.
function noLua(t) {
    if (process.env.LOOTPATH_REQUIRE_LUA === '1') assert.fail('no Lua 5.1 on PATH and no lootpath-lua image, and LOOTPATH_REQUIRE_LUA=1');
    t.skip('no Lua 5.1 on PATH and no lootpath-lua Docker image');
}

test('EngineScore.Load ACCEPTS the combat-log file on a 12.1.5 client and finds band "12" for a +12', (t) => {
    const out = load('12.1.5', t);
    if (!out) return noLua(t);
    assert.equal(out[0], 'ok', `refused: ${out[1]} / ${out[2]}`);
    assert.equal(out[3], 'int int,haste,crit,mastery,vers,leech');
    const [key, mastery] = out[4].split(' ');
    assert.equal(key, '12');
    assert.equal(Number(mastery), Number(first.table.specs.get(105).Dungeon.bands['12'].weights.mastery.toPrecision(9)));
});

test('EngineScore.Load REFUSES it on a 12.1.0 client', (t) => {
    const out = load('12.1.0', t);
    if (!out) return noLua(t);
    assert.equal(out[0], 'refused');
    assert.equal(out[1], "Update Lootpath - its ratings are for 12.1.5, you're on 12.1.0.");
});

test('a log without a header needs --patch; an unknown option is refused', () => {
    assert.throws(() => weights.run([FIXTURE, '--out', os.tmpdir()], () => {}), /pass --patch/);
    assert.throws(() => weights.parseArgs([FIXTURE, '--bogus']), /unknown option/);
    assert.deepEqual(weights.headerPatch('1/1/2026 0:00:00.000-5  COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.1.5,PROJECT_ID,1\n'), { advanced: true, patch: '12.1.5' });
});
