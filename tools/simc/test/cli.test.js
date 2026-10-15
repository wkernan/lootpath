'use strict';

// The command line: the healer refusal, the usage text, the default profile
// lookup, the exact SimC arguments, and rebuilding every committed spec from
// its committed reports without SimC.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { run, USAGE } = require('../run-scale-factors');
const { defaultProfile, simcArgs, simcPath } = require('../lib/simc');

const FIX = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'simc', 'reports');
const quiet = () => {};

function tmp() {
    return fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-simc-test-'));
}

test('the usage text says SimC models no healer', () => {
    assert.match(USAGE, /models no healer/);
    const lines = [];
    assert.deepEqual(run([], (l) => lines.push(l)), { usage: true });
    assert.match(lines.join('\n'), /Healers are not supported/);
});

test('REFUSED: Restoration (105), a healer, before SimC is even looked for', () => {
    assert.throws(() => run(['105'], quiet), /a healer: SimulationCraft models no healer/);
});

test('the default profile is the newest tier that has the spec', () => {
    const root = tmp();
    const exe = path.join(root, 'simc.exe');
    fs.writeFileSync(exe, '');
    for (const [tier, files] of [['MID1', ['Druid_Balance', 'Druid_Feral']], ['MID2', ['Druid_Feral']], ['PreRaids', ['Druid_Balance']]]) {
        fs.mkdirSync(path.join(root, 'profiles', tier), { recursive: true });
        for (const f of files) fs.writeFileSync(path.join(root, 'profiles', tier, `${tier}_${f}.simc`), '');
    }
    assert.equal(defaultProfile(exe, 103).tier, 'MID2');
    assert.equal(defaultProfile(exe, 102).tier, 'MID1');
    assert.throws(() => defaultProfile(exe, 104), /no Guardian Druid profile/);
    assert.throws(() => defaultProfile(exe, 250), /pass --profile/);
});

test('SimC runs with fixed iterations, no early stop, a fixed seed and the metric named', () => {
    const args = simcArgs({ profile: 'p.simc', fight: 'Patchwerk', metric: 'dtps', iterations: 100000, threads: 16, seed: 7101, json: 'r.json', text: 'r.txt' });
    for (const a of ['fight_style=Patchwerk', 'iterations=100000', 'target_error=0', 'threads=16', 'deterministic=1', 'seed=7101', 'calculate_scale_factors=1', 'scale_over=dtps', 'json2=r.json', 'output=r.txt']) {
        assert.ok(args.includes(a), a);
    }
    assert.ok(args.includes('scale_only=strength,agility,intellect,haste,crit,mastery,versatility'));
});

test('no SimC binary: refused with what to pass', () => {
    assert.throws(() => simcPath(undefined, {}), /pass --simc/);
    assert.throws(() => simcPath(path.join(tmp(), 'nope.exe'), {}), /no SimC binary at/);
});

test('every committed spec and fight rebuilds from its reports alone', () => {
    const out = tmp();
    const cases = [
        [['102', '--fight', 'Patchwerk'], 'int', 'DAMAGER', 'dps'],
        [['102', '--fight', 'DungeonSlice'], 'int', 'DAMAGER', 'dps'],
        [['103', '--fight', 'Patchwerk'], 'agi', 'DAMAGER', 'dps'],
        [['103', '--fight', 'DungeonSlice'], 'agi', 'DAMAGER', 'dps'],
        [['104', '--fight', 'Patchwerk'], 'agi', 'TANK', 'dtps'],
        [['104', '--fight', 'DungeonSlice', '--tank-value', 'dps'], 'agi', 'TANK', 'dps'],
    ];
    for (const [args, primary, role, metric] of cases) {
        const { result, file } = run([...args, '--from-reports', FIX, '--out', out, '--derived-at', '2026-10-15T00:00:00Z'], quiet);
        assert.ok(fs.existsSync(file));
        assert.equal(result.primaryStat, primary, args.join(' '));
        assert.equal(result.role, role, args.join(' '));
        assert.equal(result.value.metric, metric, args.join(' '));
        assert.equal(result.patch, '12.1.5');
        assert.equal(result.source, 'simc-sample-profile');
        assert.match(result.profile.sha256, /^[0-9a-f]{64}$/);
        for (const r of result.reports) assert.match(r.jsonSha256, /^[0-9a-f]{64}$/);
    }
});

test('Guardian DungeonSlice: DTPS is not measurable there, so a survival value is refused and the damage value records why', () => {
    const out = tmp();
    assert.throws(() => run(['104', '--fight', 'DungeonSlice', '--from-reports', FIX, '--out', out], quiet), /no DTPS/);
    const { result } = run(['104', '--fight', 'DungeonSlice', '--tank-value', 'dps', '--from-reports', FIX, '--out', out], quiet);
    assert.match(result.unmeasured.dtps, /no DTPS/);
    assert.equal(result.factors.dtps, undefined);
});

test('REFUSED: a profile that sims another spec than the ID given', () => {
    const dir = tmp();
    for (const ext of ['json', 'scale.txt', 'run.json']) fs.copyFileSync(path.join(FIX, `103-Patchwerk-dps.${ext}`), path.join(dir, `102-Patchwerk-dps.${ext}`));
    assert.throws(() => run(['102', '--from-reports', dir, '--out', tmp()], quiet), /spec 102 is Balance Druid, but the profile sims Feral Druid/);
});
