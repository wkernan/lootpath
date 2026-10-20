'use strict';

// The writer: the committed reports -> run-scale-factors.js --from-reports ->
// write-weights.js -> a version 2 weights file that EngineScore.Load itself,
// in Lua, accepts on a 12.1.5 client and refuses on any other - the way
// tools/engine/test/patch-guard.test.js loads the fit's file.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const scale = require('../run-scale-factors');
const writer = require('../write-weights');
const { simcSpecEntry } = require('../../engine/lib/luaout');

const REPO = path.join(__dirname, '..', '..', '..');
const FIX = path.join(REPO, 'spec', 'fixtures', 'simc', 'reports');
const quiet = () => {};

function intermediates() {
    const out = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-simc-w-'));
    for (const args of [['102'], ['102', '--fight', 'DungeonSlice'], ['103'], ['103', '--fight', 'DungeonSlice'], ['104'], ['104', '--fight', 'DungeonSlice', '--tank-value', 'dps']]) {
        scale.run([...args, '--from-reports', FIX, '--out', out, '--derived-at', '2026-10-15T15:00:00Z'], quiet);
    }
    return out;
}

function writeOnce() {
    const dir = intermediates();
    return writer.run(['102', '103', '104', '--in', dir], quiet);
}

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
    for _, id in ipairs({ 102, 103, 104 }) do
        local stats, ratings, primary = ns.EngineScore.StatsFor(id)
        print(id .. " " .. primary .. " " .. table.concat(stats, ","))
    end
    local w = ns.engineWeights.specs
    print(string.format("%.17g %.17g %s %s", w[103].Raid.bands.all.weights.agi, w[104].Raid.bands.all.weights.vers, w[104].Raid.bands.all.value.metric, w[104].Dungeon.bands.all.value.metric))
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

function load(clientPatch, luaPath) {
    const lua = findLua();
    if (!lua) return null;
    const script = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-simc-lua-')), 'check.lua');
    fs.writeFileSync(script, CHECK);
    const res = lua(script, clientPatch, luaPath);
    if (res.status === null) throw new Error(`lua did not run: ${res.error}`);
    assert.equal(res.status, 0, `lua failed: ${res.stderr}`);
    return res.stdout.trim().split('\n');
}

// CI sets LOOTPATH_REQUIRE_LUA=1, so these never skip there.
function noLua(t) {
    if (process.env.LOOTPATH_REQUIRE_LUA === '1') assert.fail('no Lua 5.1 on PATH and no lootpath-lua image, and LOOTPATH_REQUIRE_LUA=1');
    t.skip('no Lua 5.1 on PATH and no lootpath-lua Docker image');
}

test('the writer emits version 2, method simc, one band `all` per content type, the tiers neutral', () => {
    const { lua, table } = writeOnce();
    assert.match(lua, /version = 2,/);
    assert.match(lua, /patch = "12\.1\.5",/);
    for (const id of [102, 103, 104]) {
        const e = table.specs.get(id);
        assert.equal(e.method, 'simc');
        assert.deepEqual(Object.keys(e.Raid.bands), ['all']);
        assert.deepEqual(Object.keys(e.Dungeon.bands), ['all']);
        assert.equal(e.Raid.bands.all.unit, 'per point');
        assert.equal(e.Raid.bands.all.fight, 'Patchwerk');
        assert.equal(e.Dungeon.bands.all.fight, 'DungeonSlice');
        assert.deepEqual([...e.tiers.keys()], [-1]);
    }
    assert.equal(table.specs.get(102).primaryStat, 'int');
    assert.equal(table.specs.get(104).role, 'TANK');
    assert.equal(table.specs.get(104).Raid.bands.all.value.metric, 'dps');
    assert.equal(table.specs.get(104).Dungeon.bands.all.value.metric, 'dps');
});

test('EngineScore.Load ACCEPTS the SimC file on a 12.1.5 client and reads each spec\'s own stats', (t) => {
    const { file, table } = writeOnce();
    const out = load('12.1.5', file);
    if (!out) {
        noLua(t);
        return;
    }
    assert.equal(out[0], 'ok', `refused: ${out[1]} / ${out[2]}`);
    assert.equal(out[1], 'Engine ratings for 12.1.5 loaded.');
    assert.equal(out[3], '102 int int,haste,crit,mastery,vers');
    assert.equal(out[4], '103 agi agi,haste,crit,mastery,vers');
    assert.equal(out[5], '104 agi agi,haste,crit,mastery,vers');
    const [agi, vers, raidMetric, dungeonMetric] = out[6].split(' ');
    assert.equal(Number(agi), table.specs.get(103).Raid.bands.all.weights.agi);
    assert.equal(Number(vers), table.specs.get(104).Raid.bands.all.weights.vers);
    assert.equal(raidMetric, 'dps');
    assert.equal(dungeonMetric, 'dps');
});

test('EngineScore.Load REFUSES the same file on a 12.1.0 client', (t) => {
    const { file } = writeOnce();
    const out = load('12.1.0', file);
    if (!out) {
        noLua(t);
        return;
    }
    assert.equal(out[0], 'refused');
    assert.equal(out[1], "Update Lootpath - its ratings are for 12.1.5, you're on 12.1.0.");
});

test('the writer is deterministic: two runs over the committed reports write byte-identical Lua', () => {
    assert.equal(writeOnce().lua, writeOnce().lua);
});

test('REFUSED: a healer input, and inputs for two different patches', () => {
    const dir = intermediates();
    const f = path.join(dir, '103-Patchwerk.json');
    const e = JSON.parse(fs.readFileSync(f, 'utf8'));
    fs.writeFileSync(f, JSON.stringify({ ...e, role: 'HEALER' }));
    assert.throws(() => writer.run(['103', '--in', dir], quiet), /models no healer/);
    fs.writeFileSync(f, JSON.stringify({ ...e, patch: '12.1.0' }));
    assert.throws(() => writer.run(['103', '--in', dir], quiet), /patch|12\.1\.0/);
});

test('REFUSED: an entry missing a weight', () => {
    const dir = intermediates();
    const raid = JSON.parse(fs.readFileSync(path.join(dir, '103-Patchwerk.json'), 'utf8'));
    const dungeon = JSON.parse(fs.readFileSync(path.join(dir, '103-DungeonSlice.json'), 'utf8'));
    delete raid.weights.haste;
    assert.throws(() => simcSpecEntry({ Raid: raid, Dungeon: dungeon }), /Raid: no weight for haste/);
});
