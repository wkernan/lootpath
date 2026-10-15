// Finding SimC and its sample profile, and the exact command a run uses.
//
// The binary is a download (GPL-3.0). It is never in the repo: the default home
// is its own directory under C:\tmp\simc (README). SimC runs with its working
// directory set to a fresh empty temp directory, never the download's, and
// every path it reads or writes is passed to it as an absolute argument.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const { SPECS, SCALE_ONLY, fileWord } = require('./specs');

const FIGHTS = ['Patchwerk', 'DungeonSlice'];

// The run's fixed settings. Fixed so a rerun reproduces the committed reports:
// the iteration count (target_error=0 so SimC never stops early), the thread
// count (each thread draws its own random stream, so the split matters) and the
// seed, with deterministic=1.
const DEFAULTS = { iterations: 100000, threads: 16, seed: 7101 };

function sha256(file) {
    return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

// simcPath(opts, env) -> the simc executable: --simc, else LOOTPATH_SIMC.
function simcPath(given, env) {
    const exe = given || (env || process.env).LOOTPATH_SIMC;
    if (!exe) throw new Error('no SimC binary: pass --simc <path to simc.exe> or set LOOTPATH_SIMC');
    if (!fs.existsSync(exe) || !fs.statSync(exe).isFile()) throw new Error(`no SimC binary at ${exe}`);
    return path.resolve(exe);
}

// tierDirs(profilesRoot) -> SimC's per-tier profile directories (MID1, MID2,
// ...), newest tier first.
function tierDirs(root) {
    if (!fs.existsSync(root)) return [];
    return fs
        .readdirSync(root, { withFileTypes: true })
        .filter((d) => d.isDirectory() && /^[A-Z]+\d+$/.test(d.name))
        .map((d) => ({ name: d.name, n: Number(d.name.match(/\d+$/)[0]) }))
        .sort((a, b) => b.n - a.n || a.name.localeCompare(b.name))
        .map((d) => d.name);
}

// defaultProfile(simcExe, specID) -> { path, tier } of SimC's own sample
// profile for the spec, from the newest tier that has one
// (`profiles/<TIER>/<TIER>_<Class>_<Spec>.simc`). Only the specs in SPECS have
// a default; any other spec is run with --profile.
function defaultProfile(simcExe, specID) {
    const spec = SPECS[specID];
    if (!spec) throw new Error(`spec ${specID} has no default profile here: pass --profile <path to its .simc>`);
    const root = path.join(path.dirname(simcExe), 'profiles');
    for (const tier of tierDirs(root)) {
        const file = path.join(root, tier, `${tier}_${fileWord(spec.className)}_${fileWord(spec.specName)}.simc`);
        if (fs.existsSync(file)) return { path: file, tier };
    }
    throw new Error(`no ${spec.specName} ${spec.className} profile under ${root}`);
}

// simcArgs(...) -> the argument list, in order; the README prints the same.
function simcArgs({ profile, fight, metric, iterations, threads, seed, json, text }) {
    return [
        profile,
        `fight_style=${fight}`,
        `iterations=${iterations}`,
        'target_error=0',
        `threads=${threads}`,
        'deterministic=1',
        `seed=${seed}`,
        'report_details=0',
        'calculate_scale_factors=1',
        `scale_only=${SCALE_ONLY}`,
        `scale_over=${metric}`,
        `json2=${json}`,
        `output=${text}`,
    ];
}

// runSimc(exe, args) -> SimC's stdout; throws on a non-zero exit. The working
// directory is a new empty temp directory.
function runSimc(exe, args, log) {
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-simc-'));
    const res = spawnSync(exe, args, { cwd, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, windowsHide: true });
    if (res.error) throw res.error;
    if (res.status !== 0) throw new Error(`simc exited ${res.status}: ${(res.stderr || res.stdout || '').trim().split('\n').slice(-5).join('\n')}`);
    if (log) log((res.stdout.split('\n').find((l) => /^SimulationCraft /.test(l)) || '').trim());
    return res.stdout;
}

module.exports = { FIGHTS, DEFAULTS, sha256, simcPath, tierDirs, defaultProfile, simcArgs, runSimc };
