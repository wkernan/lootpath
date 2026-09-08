#!/usr/bin/env node
// The Lootpath companion (WKE-533, C-1). Decision 2026-09-07,
// docs/ARCHITECTURE.md §7.
//
//   node companion.js                 run once over the current SavedVariables
//   node companion.js --watch         run once, then on every /reload
//   node companion.js --profile-only  build the SimC profile and print it
//   node companion.js --config <file> use a different config file
//   node companion.js --out <file>    write the chunk somewhere else (a dry run)
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
const savedVariables = require('./lib/savedvariables');
const profileLib = require('./lib/profile');
const forkLib = require('./lib/fork');
const luaWriter = require('./lib/luawriter');
const output = require('./lib/output');
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
    const args = { watch: false, profileOnly: false, config: null, out: null };
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        if (arg === '--watch') args.watch = true;
        else if (arg === '--profile-only') args.profileOnly = true;
        else if (arg === '--config') args.config = argv[++i];
        else if (arg === '--out') args.out = argv[++i];
        else if (arg === '--help' || arg === '-h') args.help = true;
        else return { error: `unknown argument ${arg}` };
    }
    return args;
}

async function once(config, log, args) {
    const found = configLib.findSavedVariables(config);
    if (!found.ok) {
        log.error(found.reason);
        return EXIT.savedVariables;
    }
    log.info(`SavedVariables: ${configLib.maskAccount(found.file)}`);

    let done = log.stage('read');
    let db;
    try {
        db = savedVariables.parse(fs.readFileSync(found.file, 'utf8'));
    } catch (e) {
        log.error(`could not read the SavedVariables: ${e.message}`);
        return EXIT.savedVariables;
    }
    done(`${(fs.statSync(found.file).size / 1024).toFixed(0)} KB`);

    done = log.stage('profile');
    const profile = profileLib.build(db, { companionVersion: VERSION, includeBank: config.includeBank });
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
        `${profile.counts.equipped} equipped, ${profile.counts.bagged} in bags and bank, ${profile.counts.vault} vault, ${profile.counts.lines} lines`
    );

    if (args.profileOnly) {
        process.stdout.write(profile.text);
        return EXIT.ok;
    }

    done = log.stage('qe live');
    let run;
    try {
        run = await forkLib.run(config, profile.text, log, {
            stateDir: path.join(__dirname, config.stateDir),
            screenshotDir: path.join(__dirname, config.stateDir),
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
    const target = args.out || configLib.verdictPath(config);
    try {
        const text = luaWriter.render({
            // Second precision: `ns.EpochFromISO` (Core.lua) reads
            // YYYY-MM-DDTHH:MM:SS and the addon's contract spells it that way.
            writtenAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
            companionVersion: VERSION,
            profileCapturedAt: profile.capturedAtLocal,
            documents: run.documents,
        });
        const written = output.writeVerdict(target, text);
        done(`${(written.bytes / 1024).toFixed(0)} KB -> ${written.target}`);
    } catch (e) {
        log.error(`writing ${target} failed, so the previous verdict is untouched: ${e.message}`);
        return EXIT.write;
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
