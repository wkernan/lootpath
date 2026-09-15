#!/usr/bin/env node
// The Lootpath companion (WKE-533, C-1). Decision 2026-09-07,
// docs/ARCHITECTURE.md §7.
//
//   node companion.js                 run once over the current SavedVariables
//   node companion.js --watch         run once, then on every /reload
//   node companion.js --profile-only  build the SimC profile and print it
//   node companion.js --config <file> use a different config file
//   node companion.js --out <file>    write the chunk somewhere else (a dry run)
//   node companion.js --force         run QE Live even if the profile is
//                                     unchanged, and ask the two vault what-if
//                                     scenarios even with an empty vault
//
// The loop it makes possible: /reload, wait, /reload. No /simc, no browser, no
// paste. It reads Lootpath's own SavedVariables, builds the SimulationCraft
// profile from them, runs QE Live's engine in the owner's local fork, and
// writes Interface\AddOns\Lootpath\Data\QEVerdict.lua - the verdict the addon
// reads, and the only file it loads that it did not ship with.
//
// Since C-9 (WKE-559) two more files sit beside it in that folder and nowhere
// else: `companion.log`, every line this program prints, and
// `CompanionStatus.lua`, what the last run did - so a run that died and a run
// that had nothing to do stop looking the same from inside the game.
//
// It computes nothing. Every healing number in that file is QE Live's own
// export text, carried through unchanged for the addon to parse exactly as it
// parses a paste.
'use strict';

const fs = require('fs');
const path = require('path');

const configLib = require('./lib/config');
const logLib = require('./lib/log');
const profileLib = require('./lib/profile');
const forkLib = require('./lib/fork');
const luaWriter = require('./lib/luawriter');
const output = require('./lib/output');
const fingerprintLib = require('./lib/fingerprint');
const statusLib = require('./lib/status');
const lockLib = require('./lib/lock');
const { watch } = require('./lib/watch');

const VERSION = require('./package.json').version;

// Exit codes, so a wrapper script can tell the failures apart. The README
// lists them.
const EXIT = {
    ok: 0,
    usage: 1,
    savedVariables: 2,
    profile: 3,
    fork: 4,
    refused: 5,
    write: 6,
    // C-9 (WKE-559): another watcher already has the lock. Its own run is
    // fine; this one would be the second, and two watchers over one
    // SavedVariables file is the failure the rule has named since C-1.
    watching: 7,
};

// What each gate is waiting for, in the log's own words. The reasons a gate
// gives AFTER it is settled are lib/config.js's (`gateVerdict`); this is the
// half said before the run, when nothing has been counted yet.
const GATE_WORDS = {
    catalyst: 'you hold something the Catalyst can convert',
    upgrade: 'you hold something below its upgrade cap',
    either: 'either of those is true',
};

function parseArgs(argv) {
    const args = { watch: false, profileOnly: false, force: false, config: null, out: null };
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        if (arg === '--watch') args.watch = true;
        else if (arg === '--profile-only') args.profileOnly = true;
        else if (arg === '--force') args.force = true;
        else if (arg === '--config') args.config = argv[++i];
        else if (arg === '--out') args.out = argv[++i];
        else if (arg === '--help' || arg === '-h') args.help = true;
        else return { error: `unknown argument ${arg}` };
    }
    return args;
}

// `deps` exists for the tests: the fork driver is the one part that opens a
// browser, so a test that has to prove QE Live was NOT asked hands in its own.
// `deps.status` is C-9's recorder (lib/status.js); with none, every status call
// is a no-op and nothing is written, which is what a --profile-only dry run
// wants.
async function once(config, log, args, deps) {
    const fork = (deps && deps.fork) || forkLib;
    const status = (deps && deps.status) || statusLib.make({});
    // path.resolve, not path.join, so an absolute stateDir (which is what a
    // test passes) is honoured instead of being glued onto __dirname.
    const stateDir = path.resolve(__dirname, config.stateDir);
    status.started();
    const found = configLib.findSavedVariables(config);
    if (!found.ok) {
        log.error(found.reason);
        status.failed('savedvariables', found.reason, EXIT.savedVariables);
        return EXIT.savedVariables;
    }
    log.info(`SavedVariables: ${configLib.maskAccount(found.file)}`);

    status.stage('read');
    let done = log.stage('read');
    let text;
    try {
        text = fs.readFileSync(found.file, 'utf8');
    } catch (e) {
        log.error(`could not read the SavedVariables: ${e.message}`);
        status.failed('read', `could not read the SavedVariables: ${e.message}`, EXIT.savedVariables);
        return EXIT.savedVariables;
    }
    done(`${(Buffer.byteLength(text) / 1024).toFixed(0)} KB`);

    status.stage('profile');
    done = log.stage('profile');
    const profile = profileLib.build(text, { includeBank: config.includeBank });
    if (!profile.ok) {
        log.error(profile.reason);
        if (profile.wanted) {
            log.info(
                `the companion would rather read one "${profile.wanted}" capture; until the addon writes it, run /lootpath capture inventory and /reload`
            );
        }
        status.failed('profile', profile.reason, EXIT.profile);
        return EXIT.profile;
    }
    status.stage('profile', { profileCapturedAt: profile.capturedAtLocal });
    for (const warning of profile.warnings) log.warn(warning);
    done(
        `${profile.counts.equipped} equipped, ${profile.counts.bag} in bags, ${profile.counts.bank} in the bank, ${profile.counts.vault} vault, ${profile.counts.lines} lines`
    );

    if (args.profileOnly) {
        process.stdout.write(profile.text);
        return EXIT.ok;
    }

    // C-4 (WKE-537). Two reloads is the floor of the loop, so the second one
    // arrives with the same gear as the first and must not cost another 17 s of
    // QE Live. The debounce is not the answer and is untouched at its 1500 ms:
    // two reloads twenty seconds apart really are two writes, and the second has
    // to be read in case the owner captured between them - it is the PROFILE,
    // not the write, that decides.
    const target = args.out || configLib.verdictPath(config);
    // C-5 (WKE-539). The settings are half the question, so they are half the
    // fingerprint: the same gear with `autoUpgradeVault` flipped is a different
    // answer out of QE Live and has to cost a run.
    const wanted = configLib.qeSettings(config);
    // C-7 (WKE-543). The key levels the Upgrade Finder is asked about are the
    // other half of the question, so they are the other half of the print.
    // C-6 (WKE-540). So are the named scenarios Top Gear is run under.
    // C-12 (WKE-577). The PLANNED list, not the configured one: what a run asks
    // is the question, and a run that would ask a different set of questions
    // must not be skipped as unchanged. Which of the planned what-ifs actually
    // produce documents is settled later, off the pool QE Live builds out of
    // this very profile text - so that half of the decision is already in the
    // hash, through the profile.
    const hasVaultGear = profile.counts.vault > 0;
    const planned = configLib.plannedScenarios(config, { hasVaultGear, force: args.force });
    const print = fingerprintLib.fingerprint(profile.text, wanted, config.upgradeFinderKeyLevels, planned);
    if (!args.force) {
        const stored = fingerprintLib.readState(stateDir);
        if (!stored.ok && !stored.absent) {
            log.warn(`${stored.reason}; running QE Live rather than assuming the verdict is current`);
        }
        const current = stored.ok ? fingerprintLib.isCurrent(stored.state, print.hash, target) : { current: false };
        if (current.current) {
            log.info(
                `profile unchanged since ${current.writtenAt}; the verdict file is current - /reload in game to read it`
            );
            status.skipped(`profile unchanged since ${current.writtenAt}; the verdict file is current`, {
                verdictWrittenAt: current.writtenAt,
            });
            return EXIT.ok;
        }
    }

    // C-6 (WKE-540), rewritten by C-12 (WKE-577). Each what-if is planned
    // whatever the vault holds, and gated on its own question: `catalyzed` on
    // whether anything the character holds can be catalysed at all, `maxed` on
    // whether anything is below its upgrade cap, `thisWeek` on either. Only QE
    // Live can answer those, so the gate is settled inside the run, after that
    // pass's import, off the pool it built - and what is saved when the answer
    // is no is the pass's Top Gear documents, not the import.
    const passes = configLib.plannedPasses(config, { hasVaultGear, force: args.force });
    const plan = passes.flatMap((pass) => pass.documents);
    const gated = passes.filter((pass) => pass.gate);
    log.info(
        `Mythic+ key levels: ${config.upgradeFinderKeyLevels.map((level) => '+' + level).join(', ')}` +
            ` - one Upgrade Finder run per key level (QE Live values dungeon drops at one key at a time)`
    );
    log.info(
        `QE Live scenarios: ${planned.join(', ') || 'none'}` +
            (gated.length
                ? ` (${gated.map((pass) => `${pass.scenario} asked only if ${GATE_WORDS[pass.gate.kind]}`).join(', ')})`
                : ' (every one of them asked outright)') +
            ` - up to ${passes.length} imports, ${plan.length} documents`
    );
    log.info(
        `QE Live Upgrade Finder import settings: autoUpgradeVault=${wanted.autoUpgradeVault}, autoUpgradeAll=${wanted.autoUpgradeAll}` +
            (wanted.autoUpgradeVault === wanted.autoUpgradeAll
                ? ''
                : " - a mixed pair, which values vault options and owned gear at different points on their upgrade tracks")
    );

    status.stage('qe live', { message: `${passes.length} imports, ${plan.length} documents` });
    done = log.stage('qe live');
    let run;
    try {
        run = await fork.run(config, profile.text, log, {
            stateDir,
            screenshotDir: stateDir,
            passes,
        });
    } catch (e) {
        log.error(e.message);
        const code = e.code === forkLib.REFUSED ? EXIT.refused : EXIT.fork;
        status.failed('qe live', e.message, code);
        return code;
    }
    done(`${run.documents.length} documents`);
    // What the run actually asked, and why it did not ask the rest (C-12). A
    // driver that reports nothing - the injected one in the tests - leaves the
    // record empty, and an empty record is no note rather than a wrong one.
    const scenarios = Array.isArray(run.scenarios) ? run.scenarios : [];
    const scenarioNote = configLib.scenarioNote(scenarios);
    if (scenarioNote) log.info(`QE Live scenarios asked: ${scenarios.filter((s) => s.ran).map((s) => s.name).join(', ') || 'none'} - ${scenarioNote}`);
    for (const doc of run.documents) {
        let spec = null;
        try {
            spec = (JSON.parse(doc.json).player || {}).spec;
        } catch {
            // The addon is the parser; a document this side cannot read is
            // still carried, and QEImport refuses it with its own message.
        }
        const mismatch = profileLib.specMismatch(spec, profile.identity.spec);
        if (mismatch) {
            log.warn(mismatch);
            break;
        }
    }

    status.stage('write');
    done = log.stage('write');
    // Second precision: `ns.EpochFromISO` (Core.lua) reads
    // YYYY-MM-DDTHH:MM:SS and the addon's contract spells it that way.
    const writtenAt = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
    try {
        const text = luaWriter.render({
            writtenAt,
            companionVersion: VERSION,
            profileCapturedAt: profile.capturedAtLocal,
            // What the driver read back off the page, not what was asked for,
            // so the file records the run rather than the intention. A driver
            // that reports nothing (the injected one in the tests) falls back
            // to the configured pair.
            qeSettings: run.qeSettings || wanted,
            // The items the base pass's Top Gear was never shown (C-8). A
            // driver that reports nothing writes no list, which is what every
            // file written before C-8 carries.
            excluded: run.excluded || null,
            // Which questions this run left unasked, and why, in one sentence
            // (C-12, WKE-577). The same string goes into the status file below,
            // so the strip's tooltip and the Vault tab's footnote are one set
            // of words read out of two files. Absent when everything was asked.
            scenarioNote: scenarioNote,
            documents: run.documents,
        });
        const written = output.writeVerdict(target, text);
        done(`${(written.bytes / 1024).toFixed(0)} KB -> ${written.target}`);
    } catch (e) {
        log.error(`writing ${target} failed, so the previous verdict is untouched: ${e.message}`);
        status.failed('write', `writing the verdict failed, so the previous one is untouched: ${e.message}`, EXIT.write);
        return EXIT.write;
    }
    // Only now: the status file says a verdict was written when one was, and
    // never a moment before.
    status.wrote(writtenAt, {
        message: `${run.documents.length} documents` + (scenarioNote ? ` - ${scenarioNote}` : ''),
    });
    // After the write, never before: the fingerprint records what the addon can
    // actually read. A state file that will not write costs one extra run next
    // time and nothing else, so it is a warning and not a failed run.
    try {
        fingerprintLib.writeState(stateDir, { hash: print.hash, writtenAt, verdict: path.resolve(target) });
    } catch (e) {
        log.warn(`could not remember this profile's fingerprint (${e.message}); the next run will repeat the work`);
    }
    log.info('/reload in game to read it');
    return EXIT.ok;
}

// The log file and the status chunk both live beside whatever verdict this run
// would write - next to `QEVerdict.lua` for a real run, next to the file
// `--out` names for a dry one - so a dry run never overwrites what the game is
// about to read (C-9, WKE-559).
function visibility(config, args, log) {
    const target = args.out || configLib.verdictPath(config);
    const dir = path.dirname(target);
    const file = path.join(dir, configLib.LOG_FILE);
    const logSink = logLib.fileSink(file, {
        onError: (e) => log.warn(`the log file ${file} cannot be written (${e.message}); the terminal is all there is`),
    });
    // --profile-only touches no browser and writes no verdict, so it says
    // nothing about the last real run either: a null file makes every status
    // call a no-op.
    const status = statusLib.make({
        file: args.profileOnly ? null : path.join(dir, configLib.STATUS_FILE),
        companionVersion: VERSION,
        onError: (e) => log.warn(`the status file cannot be written (${e.message}); the log is still the record`),
    });
    return { logSink, status, logFile: file };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    // Until the config is read there is nowhere to put a log file: where it
    // goes is the config's answer. The two failures below are therefore the
    // only ones the terminal alone ever sees.
    let log = logLib.make();
    if (args.error) {
        log.error(args.error);
        return EXIT.usage;
    }
    if (args.help) {
        process.stdout.write(fs.readFileSync(path.join(__dirname, 'README.md'), 'utf8'));
        return EXIT.ok;
    }
    let config;
    try {
        config = configLib.load(args.config || path.join(__dirname, 'config.json'));
    } catch (e) {
        log.error(e.message);
        return EXIT.usage;
    }
    const seen = visibility(config, args, log);
    log = logLib.make(logLib.tee(logLib.consoleSink(), seen.logSink));
    for (const warning of config.warnings || []) log.warn(warning);
    log.info(`Lootpath companion ${VERSION}${config.configFile ? ` (config ${config.configFile})` : ' (built-in defaults)'}`);
    log.info(`log file: ${seen.logFile}`);

    // Never two watchers (lib/lock.js). The refusal comes BEFORE the first run,
    // because a second companion that ran once and then refused to watch would
    // still have driven the browser profile the first one is using.
    let lock = null;
    if (args.watch) {
        const lockFile = path.join(path.resolve(__dirname, config.stateDir), configLib.LOCK_FILE);
        const taken = lockLib.acquire(lockFile, { watching: configLib.maskAccount(configLib.verdictPath(config)) });
        if (!taken.ok) {
            log.error(
                `another companion is already watching (pid ${taken.held.pid}, since ${taken.held.startedAt}).` +
                    ` Two watchers would both run QE Live on every /reload. Stop that one, or delete ${lockFile} if it is gone.`
            );
            return EXIT.watching;
        }
        lock = taken;
        if (taken.took) {
            log.warn('a previous watcher left its lock behind and is no longer running; taking it over');
        }
        const release = () => {
            if (lock) {
                lock.release();
                lock = null;
            }
        };
        process.on('exit', release);
        for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
            process.on(signal, () => {
                release();
                process.exit(EXIT.ok);
            });
        }
    }

    const code = await once(config, log, args, { status: seen.status });
    if (!args.watch) return code;

    const found = configLib.findSavedVariables(config);
    if (!found.ok) {
        log.error(found.reason);
        return EXIT.savedVariables;
    }
    log.info(`watching ${configLib.maskAccount(found.file)}; /reload in game to trigger a run. Ctrl+C to stop.`);
    watch(found.file, { debounceMs: config.debounceMs }, async () => {
        log.info('SavedVariables changed');
        const result = await once(config, log, args, { status: seen.status });
        if (result !== EXIT.ok) log.warn(`that run failed with exit code ${result}; the previous verdict file is untouched`);
    });
    // Never resolves: the watcher owns the process from here.
    await new Promise(() => {});
    return EXIT.ok;
}

if (require.main === module) {
    main().then(
        (code) => {
            process.exitCode = code;
        },
        (e) => {
            process.stderr.write(`FAILED: ${e && e.stack ? e.stack : e}\n`);
            process.exitCode = EXIT.usage;
        }
    );
}

module.exports = { parseArgs, once, visibility, EXIT, VERSION };
