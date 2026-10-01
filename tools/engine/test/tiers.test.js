'use strict';

// E-0i (WKE-680): the tier rule the fit tool writes is the one EngineScore
// reads. The dev weights file is loaded through Lootpath/Modules/EngineScore.lua
// itself - its Load (which refuses a `tiers` it cannot read) and its SetValue -
// in Lua 5.1 (PATH or the repo's Docker image, as cli.test.js), and the tier
// multiplier it applies at 2 and 4 pieces must equal --tier2 and --tier4 under
// E-0c's additive rule: 1 + tier2 at two pieces, 1 + tier2 + tier4 at four.
// Before E-0i the file carried `{ setIDs, twoPiece, fourPiece, forceTier }`,
// EngineScore found no setID in it and the multiplier was 1 everywhere.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { run } = require('../fit-weights');
const { luaTiers } = require('../lib/luaout');

const REPO = path.join(__dirname, '..', '..', '..');
const CAPTURE = path.join(REPO, 'spec', 'fixtures', 'captures', 'Lootpath-20261001-092631.lua');
const EXPORT = path.join(REPO, 'spec', 'fixtures', 'qe', 'qe-upgradefinder-Hotornot-ynfzbppepnzw.json');
// Not QE Live's Restoration Druid numbers (0.03 / 0.055): parameters a test can
// tell apart from every default, on two sets.
const TIER2 = 0.021;
const TIER4 = 0.047;
const SETS = [2057, 1999];

function fitOnce() {
    const out = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-tiers-'));
    const args = ['--out', out, '--derived-at', '2026-10-01T00:00:00Z', '--resamples', '5', '--stats', CAPTURE, '--tier-sets', SETS.join(','), '--tier2', String(TIER2), '--tier4', String(TIER4), EXPORT];
    return { out, ...run(args, () => {}) };
}

// The Lua side: EngineScore loaded the way the addon loads it (`...` is the
// addon name and its namespace), the dev file set as ns.engineWeights, the
// client version answered with the file's own patch, then SetValue at 0..5
// pieces of each set with the tier counted, not forced.
const CHECK = `
local repo, file = arg[1], arg[2]
local ns = { onReady = {} }
ns.Safe = function(v) return v, false end
assert(loadfile(file))("Lootpath", ns)
local weights = assert(ns.engineWeights, "no ns.engineWeights")
GetBuildInfo = function() return weights.patch end
assert(loadfile(repo .. "/Lootpath/Modules/EngineScore.lua"))("Lootpath", ns)
local ok, line, detail = ns.EngineScore.Load()
if not ok then
    error("refused: " .. tostring(line) .. " " .. tostring(detail))
end
local function zero() return 0 end
local setIDs = {}
for setID in pairs(weights.tiers) do setIDs[#setIDs + 1] = setID end
table.sort(setIDs)
for _, setID in ipairs(setIDs) do
    for pieces = 0, 5 do
        local items = {}
        for i = 1, pieces do items[i] = { slot = "Slot" .. i, setID = setID, int = 0 } end
        items[#items + 1] = { slot = "Neck", int = 0 }
        local r = assert(ns.EngineScore.SetValue(items, { contentType = "Raid", rating = zero }))
        print(string.format("%d %d %.17g", setID, pieces, r.tier.mult))
    end
end
`;

function findLua() {
    const local = ['lua5.1', 'lua'].find((exe) => spawnSync(exe, ['-v'], { encoding: 'utf8' }).status === 0);
    if (local) return (script, file) => spawnSync(local, [script, REPO, file], { encoding: 'utf8' });
    const img = spawnSync('docker', ['image', 'inspect', 'lootpath-lua'], { encoding: 'utf8' });
    if (img.status !== 0) return null;
    return (script, file) =>
        spawnSync('docker', ['run', '--rm', '-v', `${REPO}:/repo`, '-v', `${path.dirname(script)}:/t`, 'lootpath-lua', 'lua', `/t/${path.basename(script)}`, '/repo', `/t/${path.basename(file)}`], { encoding: 'utf8' });
}

test('luaTiers writes { [setID] = { [2] = { mult = 1 + tier2 }, [4] = { mult = 1 + tier4 } } }', () => {
    const t = luaTiers({ setIDs: SETS, twoPiece: TIER2, fourPiece: TIER4, forceTier: true });
    assert.deepEqual([...t.keys()], SETS);
    for (const id of SETS) {
        assert.deepEqual([...t.get(id).keys()], [2, 4]);
        assert.equal(t.get(id).get(2).mult, 1 + TIER2);
        assert.equal(t.get(id).get(4).mult, 1 + TIER4);
    }
    assert.throws(() => luaTiers({ setIDs: [], twoPiece: TIER2, fourPiece: TIER4 }), /--tier-sets/);
    assert.throws(() => luaTiers({ setIDs: [2057], twoPiece: NaN, fourPiece: TIER4 }), /--tier2/);
    assert.throws(() => luaTiers({ setIDs: [2057.5], twoPiece: TIER2, fourPiece: TIER4 }), /not a setID/);
});

test('the dev file carries no trace of the fit-side tier shape', () => {
    const r = fitOnce();
    for (const field of ['setIDs', 'twoPiece', 'fourPiece', 'forceTier']) assert.ok(!r.lua.includes(field), field);
    assert.match(r.lua, /tiers = \{\n {8}\[2057\] = \{\n {12}\[2\] = \{\n {16}mult = 1\.021,/);
});

test('EngineScore loads the dev file and applies --tier2 at 2 pieces and --tier4 on top at 4', (t) => {
    const r = fitOnce();
    const script = path.join(r.out, 'tiers-check.lua');
    fs.writeFileSync(script, CHECK);
    const lua = findLua();
    if (!lua) {
        if (process.env.LOOTPATH_REQUIRE_LUA === '1') assert.fail('no Lua 5.1 on PATH and no lootpath-lua image, and LOOTPATH_REQUIRE_LUA=1');
        t.skip('no Lua 5.1 on PATH and no lootpath-lua Docker image');
        return;
    }
    const res = lua(script, r.luaPath);
    assert.equal(res.status, 0, `lua failed: ${res.stderr}`);
    const got = new Map();
    for (const line of res.stdout.trim().split(/\r?\n/)) {
        const [setID, pieces, mult] = line.trim().split(/\s+/).map(Number);
        got.set(`${setID}/${pieces}`, mult);
    }
    const sorted = SETS.slice().sort((a, b) => a - b);
    assert.equal(got.size, sorted.length * 6);
    for (const id of sorted) {
        const expected = [1, 1, 1 + TIER2, 1 + TIER2, 1 + TIER2 + TIER4, 1 + TIER2 + TIER4];
        expected.forEach((want, pieces) => {
            const mult = got.get(`${id}/${pieces}`);
            assert.ok(Math.abs(mult - want) < 1e-12, `set ${id} at ${pieces} pieces: ${mult}, want ${want}`);
        });
    }
});
