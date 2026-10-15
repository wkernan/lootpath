#!/usr/bin/env node
// tools/simc/run-scale-factors.js (E-7, WKE-710) - DEVELOPER ONLY, never shipped.
//
// Runs SimulationCraft over a spec's own sample profile with scale factors on,
// reads the reports, and writes tools/simc/out/<specID>-<fight>.json: the
// spec's primary stat and stat list, its value metric, and one weight per
// stat with SimC's error. README.md says how to get SimC and how the committed
// fixtures under spec/fixtures/simc/reports/ were made.
'use strict';

const fs = require('fs');
const path = require('path');
const { SPECS } = require('./lib/specs');
const { excerpt, parseRun, refuse } = require('./lib/report');
const { build } = require('./lib/intermediate');
const { FIGHTS, DEFAULTS, sha256, simcPath, defaultProfile, simcArgs, runSimc } = require('./lib/simc');

const USAGE = `usage: node run-scale-factors.js <specID> [options]

Stat weights for a DPS or TANK spec from SimulationCraft's scale factors.
SimulationCraft models no healer ("Healers are not supported"): a healing spec
is refused, and healer weights come from elsewhere (docs/OWN-ENGINE.md §2b).

  <specID>            the spec's ID (102 Balance, 103 Feral, 104 Guardian have
                      a default profile; any other spec needs --profile)
  --fight <style>     ${FIGHTS.join(' | ')} (default Patchwerk: the raid band;
                      DungeonSlice: the dungeon band)
  --profile <path>    the .simc profile (default: SimC's own sample profile for
                      the spec, newest tier that has one)
  --simc <path>       simc.exe (default: $LOOTPATH_SIMC)
  --iterations <n>    default ${DEFAULTS.iterations}
  --threads <n>       default ${DEFAULTS.threads} (fixed: the split changes the draws)
  --seed <n>          default ${DEFAULTS.seed} (deterministic=1)
  --tank-value <m>    dtps (default: survival) | dps (damage) - what a tank's
                      weights measure; both are always run and kept
  --out <dir>         default tools/simc/out
  --tag <word>        appended to the report names (<spec>-<fight>-<metric>.<tag>)
  --derived-at <iso>  default now
  --from-reports <dir> read existing reports from <dir> instead of running SimC
                      (the committed fixtures: spec/fixtures/simc/reports)`;

function parseArgs(argv) {
    const o = { positional: [] };
    const takes = new Set(['--fight', '--profile', '--simc', '--iterations', '--threads', '--seed', '--tank-value', '--out', '--tag', '--derived-at', '--from-reports']);
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--help' || a === '-h') o.help = true;
        else if (takes.has(a)) {
            if (i + 1 >= argv.length) throw new Error(`${a} needs a value`);
            o[a.slice(2).replace(/-(\w)/g, (_, c) => c.toUpperCase())] = argv[++i];
        } else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
        else o.positional.push(a);
    }
    return o;
}

function wholeNumber(name, v, dflt) {
    if (v === undefined) return dflt;
    if (!/^\d+$/.test(String(v)) || Number(v) < 1) throw new Error(`${name} must be a whole number above 0, got ${v}`);
    return Number(v);
}

function baseName(specID, fight, metric, tag) {
    return `${specID}-${fight}-${metric}${tag ? `.${tag}` : ''}`;
}

// readRun(dir, base, metric) -> { run, report } from <base>.json, <base>.scale.txt, <base>.run.json.
function readRun(dir, base, metric) {
    const json = path.join(dir, `${base}.json`);
    const scale = path.join(dir, `${base}.scale.txt`);
    const side = path.join(dir, `${base}.run.json`);
    for (const f of [json, scale, side]) if (!fs.existsSync(f)) throw new Error(`missing ${f}`);
    const sidecar = JSON.parse(fs.readFileSync(side, 'utf8'));
    const run = parseRun(fs.readFileSync(json, 'utf8'), fs.readFileSync(scale, 'utf8'), metric);
    return {
        run,
        sidecar,
        report: { metric, json: path.basename(json), jsonSha256: sha256(json), scale: path.basename(scale), scaleSha256: sha256(scale), textSha256: sidecar.textSha256 },
    };
}

function run(argv, log) {
    log = log || console.log;
    const o = parseArgs(argv);
    if (o.help || o.positional.length !== 1) {
        log(USAGE);
        return { usage: true };
    }
    if (!/^\d+$/.test(o.positional[0])) throw new Error(`<specID> must be a number, got ${o.positional[0]}`);
    const specID = Number(o.positional[0]);
    const known = SPECS[specID];
    if (known && known.healer) refuse(`spec ${specID} is ${known.specName} ${known.className}, a healer: SimulationCraft models no healer`);
    const fight = o.fight || 'Patchwerk';
    if (!FIGHTS.includes(fight)) throw new Error(`--fight must be one of ${FIGHTS.join(', ')}`);
    const tankValue = o.tankValue || 'dtps';
    if (!['dtps', 'dps'].includes(tankValue)) throw new Error('--tank-value must be dtps or dps');
    const out = path.resolve(o.out || path.join(__dirname, 'out'));
    const derivedAt = o.derivedAt || new Date().toISOString();

    const runs = [];
    const reports = [];
    let profile;
    let source;

    // Every spec runs on DPS first; SimC's report says the role, and a TANK
    // runs again on DTPS so both metrics carry SimC's own errors.
    let next;
    if (o.fromReports) {
        const dir = path.resolve(o.fromReports);
        next = (metric) => readRun(dir, baseName(specID, fight, metric, o.tag), metric);
    } else {
        const exe = simcPath(o.simc);
        profile = o.profile ? { path: path.resolve(o.profile), tier: null } : defaultProfile(exe, specID);
        if (!fs.existsSync(profile.path)) throw new Error(`no profile at ${profile.path}`);
        profile.sha256 = sha256(profile.path);
        source = o.profile ? 'simc-given-profile' : 'simc-sample-profile';
        const settings = {
            iterations: wholeNumber('--iterations', o.iterations, DEFAULTS.iterations),
            threads: wholeNumber('--threads', o.threads, DEFAULTS.threads),
            seed: wholeNumber('--seed', o.seed, DEFAULTS.seed),
        };
        const reportDir = path.join(out, 'reports');
        fs.mkdirSync(reportDir, { recursive: true });
        next = (metric) => {
            const base = baseName(specID, fight, metric, o.tag);
            const json = path.join(reportDir, `${base}.json`);
            const text = path.join(reportDir, `${base}.txt`);
            const args = simcArgs({ profile: profile.path, fight, metric, ...settings, json, text });
            log(`simc ${args.join(' ')}`);
            runSimc(exe, args, log);
            fs.writeFileSync(path.join(reportDir, `${base}.scale.txt`), excerpt(fs.readFileSync(text, 'utf8')));
            const sidecar = { args: args.slice(1).map((a) => a.replace(reportDir + path.sep, '')), profile, source, textSha256: sha256(text), simcSha256: sha256(exe) };
            fs.writeFileSync(path.join(reportDir, `${base}.run.json`), JSON.stringify(sidecar, null, 2) + '\n');
            return readRun(reportDir, base, metric);
        };
    }
    const take = (r) => {
        runs.push(r.run);
        reports.push(r.report);
        profile = r.sidecar.profile;
        source = r.sidecar.source;
        return r;
    };
    const unmeasured = {};
    const dps = take(next('dps'));
    if (dps.run.player.role === 'TANK') {
        try {
            take(next('dtps'));
        } catch (err) {
            // A fight that never damages the tank has no survival to read. With
            // --tank-value dps that is recorded, not fatal; with dtps it is.
            if (err.code !== 'no-metric' || tankValue !== 'dps') throw err;
            unmeasured.dtps = err.message;
        }
    }

    const result = build(runs, { specID, fight, tankValue, profile, source, reports, derivedAt, unmeasured });
    if (known && result.specialization !== `${known.specName} ${known.className}`) {
        refuse(`spec ${specID} is ${known.specName} ${known.className}, but the profile sims ${result.specialization}`);
    }
    fs.mkdirSync(out, { recursive: true });
    const file = path.join(out, `${specID}-${fight}${o.tag ? `.${o.tag}` : ''}.json`);
    fs.writeFileSync(file, JSON.stringify(result, null, 2) + '\n');
    log(summary(result));
    log(`wrote ${file}`);
    return { result, file };
}

function summary(r) {
    const lines = [`${r.specID} ${r.specialization} (${r.role}) ${r.fight} - SimC ${r.simc.version} ${r.simc.gitRevision}, game data ${r.simc.wowVersion}, ${r.settings.iterations} iterations`];
    for (const [metric, f] of Object.entries(r.factors)) {
        const stats = r.stats.map((k) => `${k} ${f.stats[k].value.toFixed(3)} (+/- ${f.stats[k].error.toFixed(3)})${f.stats[k].significant ? '' : ' within error'}`).join(', ');
        lines.push(`  ${metric.toUpperCase()} ${f.mean.toFixed(1)} (+/- ${f.error.toFixed(1)}): ${stats}`);
    }
    lines.push(`  value: ${r.value.metric}; weights ${r.stats.map((k) => `${k} ${r.weights[k].toFixed(3)}`).join(', ')}`);
    return lines.join('\n');
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (err) {
        console.error(err.refusal ? `refused: ${err.message}` : err.message);
        process.exit(1);
    }
}

module.exports = { run, parseArgs, baseName, USAGE };
