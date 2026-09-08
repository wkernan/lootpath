#!/usr/bin/env node
// The Lootpath companion (WKE-533, C-1). Decision 2026-09-07,
// docs/ARCHITECTURE.md §7.
//
//   node companion.js                 run once over the current SavedVariables
//   node companion.js --watch         run once, then on every /reload
//   node companion.js --profile-only  build the SimC profile and print it
//   node companion.js --config <file> use a different config file
//   node companion.js --out <file>    write the chunk somewhere else (a dry run)
//   node companion.js --force         run QE Live even if the profile is unchanged
//
// The loop it makes possible: /reload, wait, /reload. No /simc, no browser, no
// paste. It reads Lootpath's own SavedVariables, builds the SimulationCraft
// profile from them, runs QE Live's engine in the owner's local fork, and
// writes Interface\AddOns\Lootpath\Data\QEVerdict.lua - the only file it ever
// writes inside the game folder, and the only file the addon loads that it did
// not ship with.
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
async function once(config, log, args, deps) {
    const fork = (deps && deps.fork) || forkLib;
    // path.resolve, not path.join, so an absolute stateDir (which is what a
    // test passes) is honoured instead of being glued onto __dirname.
    const stateDir = path.resolve(__dirname, config.stateDir);
    const found = configLib.findSavedVariables(config);
    if (!found.ok) {
        log.error(found.reason);
        return EXIT.savedVariables;
    }
    log.info(`SavedVariables: ${configLib.maskAccount(found.file)}`);

    let done = log.stage('read');
    let text;
    try {
        text = fs.readFileSync(found.file, 'utf8');
    } catch (e) {
        log.error(`could not read the SavedVariables: ${e.message}`);
        return EXIT.savedVariables;
    }
    done(`${(Buffer.byteLength(text) / 1024).toFixed(0)} KB`);

    done = log.stage('profile');
    const profile = profileLib.build(text, { includeBank: config.includeBank });
    if (!profile.ok) {
        log.error(profile.reason);
        if (profile.wanted) {
            log.info(
                `the companion would rather read one "${profile.wanted}" capture; until the addon writes it, run /lootpath capture inventory and /reload`
            );
        }
        return EXIT.profile;
    }
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
    const print = fingerprintLib.fingerprint(profile.text, wanted);
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
            return EXIT.ok;
        }
    }

    log.info(
        `QE Live import settings: autoUpgradeVault=${wanted.autoUpgradeVault}, autoUpgradeAll=${wanted.autoUpgradeAll}` +
            (wanted.autoUpgradeVault === wanted.autoUpgradeAll
                ? ''
                : " - a mixed pair, which values vault options and owned gear at different points on their upgrade tracks")
    );

    done = log.stage('qe live');
    let run;
    try {
        run = await fork.run(config, profile.text, log, {
            stateDir,
            screenshotDir: stateDir,
        });
    } catch (e) {
        log.error(e.message);
        if (e.code === forkLib.REFUSED) return EXIT.refused;
        return EXIT.fork;
    }
    done(`${run.documents.length} documents`);
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
            documents: run.documents,
        });
        const written = output.writeVerdict(target, text);
        done(`${(written.bytes / 1024).toFixed(0)} KB -> ${written.target}`);
    } catch (e) {
        log.error(`writing ${target} failed, so the previous verdict is untouched: ${e.message}`);
        return EXIT.write;
    }
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

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const log = logLib.make();
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
    for (const warning of config.warnings || []) log.warn(warning);
    log.info(`Lootpath companion ${VERSION}${config.configFile ? ` (config ${config.configFile})` : ' (built-in defaults)'}`);

    const code = await once(config, log, args);
    if (!args.watch) return code;

    const found = configLib.findSavedVariables(config);
    if (!found.ok) {
        log.error(found.reason);
        return EXIT.savedVariables;
    }
    log.info(`watching ${configLib.maskAccount(found.file)}; /reload in game to trigger a run. Ctrl+C to stop.`);
    watch(found.file, { debounceMs: config.debounceMs }, async () => {
        log.info('SavedVariables changed');
        const result = await once(config, log, args);
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

module.exports = { parseArgs, once, EXIT, VERSION };
