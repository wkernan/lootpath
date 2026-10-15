'use strict';

// E-0n (WKE-706): the client moved to 12.1.5 and the developer engine refused
// its 12.1.0 weights. The fit tool now takes `patch` from the newest
// patch-bearing capture (stats.test.js proves that in isolation); this file
// proves the thing that actually matters to a player-adjacent guard -
// `EngineScore.Load` itself, in Lua, accepting a refit tagged `12.1.5` and
// still refusing one tagged `12.1.0`, and that the refit is reproducible.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { run } = require('../fit-weights');

const REPO = path.join(__dirname, '..', '..', '..');
const CAPTURE_1215 = path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20261013-183853.lua');
const EXPORT = path.join(REPO, 'spec', 'fixtures', 'qe', 'e0n', 'qe-upgradefinder-Hotornot-yzpttpqbdisx.json');
const DERIVED_AT = '2026-10-13T23:45:00Z';

function fitOnce(extraArgs) {
    const out = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e0n-'));
    const args = ['--out', out, '--derived-at', DERIVED_AT, '--resamples', '0', '--balance', 'none', '--stats', CAPTURE_1215, ...(extraArgs || []), EXPORT];
    return { out, ...run(args, () => {}) };
}

// The Lua side: EngineScore loaded the way the addon loads it, the dev file
// set as ns.engineWeights, the client version answered as `arg[2]` says, then
// Load() asked for - the same thing `/lootpath engine` prints to a developer.
const CHECK = `
local repo, clientPatch, file = arg[1], arg[2], arg[3]
local ns = { onReady = {} }
ns.Safe = function(v) return v, false end
assert(loadfile(file))("Lootpath", ns)
GetBuildInfo = function() return clientPatch end
assert(loadfile(repo .. "/Lootpath/Modules/EngineScore.lua"))("Lootpath", ns)
local ok, line = ns.EngineScore.Load()
print(ok and "ok" or "refused")
print(tostring(line))
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

function loadResult(scriptDir, clientPatch, luaPath) {
    const lua = findLua();
    if (!lua) return null;
    const script = path.join(scriptDir, 'patch-check.lua');
    fs.writeFileSync(script, CHECK);
    const res = lua(script, clientPatch, luaPath);
    if (res.status === null) throw new Error(`lua did not run: ${res.error}`);
    const [status, line] = res.stdout.trim().split('\n');
    return { status, line, stderr: res.stderr };
}

// CI sets LOOTPATH_REQUIRE_LUA=1 (as for cli.test.js), so these never skip there.
function noLua(t) {
    if (process.env.LOOTPATH_REQUIRE_LUA === '1') assert.fail('no Lua 5.1 on PATH and no lootpath-lua image, and LOOTPATH_REQUIRE_LUA=1');
    t.skip('no Lua 5.1 on PATH and no lootpath-lua Docker image');
}

test('the fit over the owner\'s fresh 12.1.5 itemstats capture emits patch = "12.1.5"', () => {
    const r = fitOnce();
    assert.match(r.lua, /patch = "12\.1\.5",/);
    assert.ok(r.fits.length === 1 && r.fits[0].overall.n > 0, 'the document actually fitted something');
});

test('EngineScore.Load ACCEPTS the refit file on a 12.1.5 client', (t) => {
    const r = fitOnce();
    const res = loadResult(r.out, '12.1.5', r.luaPath);
    if (!res) {
        noLua(t);
        return;
    }
    assert.equal(res.status, 'ok', `EngineScore refused the refit on 12.1.5: ${res.line}`);
});

test('EngineScore.Load REFUSES the SAME refit file on a 12.1.0 client - the guard the owner saw, still live', (t) => {
    const r = fitOnce();
    const res = loadResult(r.out, '12.1.0', r.luaPath);
    if (!res) {
        noLua(t);
        return;
    }
    assert.equal(res.status, 'refused');
    assert.equal(res.line, "Update Lootpath - its ratings are for 12.1.5, you're on 12.1.0.");
});

test('a weights file still tagged 12.1.0 is refused on a 12.1.5 client (the owner\'s exact sentence)', (t) => {
    // The committed, shipped placeholder - still 12.1.0, deliberately (E-0n:
    // the tool's contract covers out/EngineWeights.dev.lua only).
    const placeholder = path.join(REPO, 'Lootpath', 'Data', 'EngineWeights.lua');
    const res = loadResult(fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e0n-ph-')), '12.1.5', placeholder);
    if (!res) {
        noLua(t);
        return;
    }
    assert.equal(res.status, 'refused');
    assert.equal(res.line, "Update Lootpath - its ratings are for 12.1.0, you're on 12.1.5.");
});

test('the 12.1.5 refit is deterministic: two runs over the same inputs write byte-identical Lua', () => {
    const a = fitOnce();
    const b = fitOnce();
    assert.equal(a.lua, b.lua);
});
