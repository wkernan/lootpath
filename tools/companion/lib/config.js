// One JSON file next to the script decides where the game and the fork live.
// The defaults are the owner's machine; nothing here is discovered from the
// environment except the account folder, which is found by glob at run time so
// no account identifier is ever written into this repo.
'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULTS = {
    wowPath: 'C:\\World of Warcraft\\_retail_',
    forkPath: 'c:\\Code\\qe-live-fork',
    forkUrl: 'http://localhost:3000',
    // Which QE Live documents to produce, in the order they are run. Content
    // types are QE Live's own strings (Dungeon / Raid); it has no "Mythic+".
    documents: [
        { kind: 'topgear', contentType: 'Dungeon' },
        { kind: 'upgradefinder', contentType: 'Dungeon' },
        { kind: 'topgear', contentType: 'Raid' },
        { kind: 'upgradefinder', contentType: 'Raid' },
    ],
    // Which Mythic+ key levels the Upgrade Finder is asked about (WKE-543,
    // C-7). The owner's question is "which dungeon at the LOWEST key level
    // still gives me an upgrade", and QE Live can only answer it one key at a
    // time: his Upgrade Finder values every dungeon drop at the single key his
    // `ufSettings.dungeon` names. So the companion asks him once per level and
    // the addon files each answer under the level it was asked at.
    //
    // These are KEY LEVELS, the numbers a player says out loud. They are not
    // `ufSettings.dungeon`, which is an INDEX into his MPLUS_KEY_REWARDS table
    // (index 7 is the "+10" button, and its rows come back at 311/321/334).
    // The companion never restates that table: it reads the labels off his own
    // selector ("M0", "+2/3", "+10"), clicks the button whose label covers the
    // wanted level, and then checks the export's `settings.dungeon` against the
    // position of the button it clicked. A level his page does not offer is a
    // named failure, never a silent nearest match.
    //
    // The default spread stops at 10 because that is the top of his table on
    // the branch this drives (MPLUS_KEY_REWARDS ends at "+10"); 10 is in it
    // because 10 is the level the journal walk previews.
    upgradeFinderKeyLevels: [2, 4, 6, 8, 10],
    // Which of QE Live's named what-if scenarios Top Gear is run under (WKE-540,
    // C-6). See SCENARIOS below; the names are fixed and the file, the addon and
    // the Vault tab all use them verbatim.
    scenarios: ['asOffered', 'catalyzed', 'thisWeek', 'maxed'],
    // How many Top Gear passes one import may make over one content type
    // (WKE-572, C-11). A non-patron's Top Gear answers a question about thirty
    // items and the character owns more, so one pass leaves the rest unrated;
    // each later pass keeps the import-time baseline, drops the bag items the
    // previous pass clicked and spends the room on cards nothing has asked
    // about yet. Four because the owner's 2026-09-14 pool was 63 cards with 20
    // active - ten new cards a pass - and four passes is the point where the
    // wall clock of a refresh starts to matter more than the tail of the bag.
    // A run that hits the bound says so in the log and leaves the rest on the
    // file's `excluded` list, which is the one place that honestly still means
    // "beyond the rating's item limit".
    topGearPasses: 4,
    includeBank: true,
    // QE Live's own import checkboxes (SimCraftDialog.js lines 122-133), asked
    // for explicitly on every run rather than inherited (WKE-539, C-5).
    //
    // His dialog defaults are `autoUpgradeVault = true`, `autoUpgradeAll =
    // false` (lines 36-37), which values a VAULT option at the top of its
    // upgrade track and OWNED gear at the level the client reports. That
    // asymmetry is what told the owner on 2026-09-08 to take a 305 copy of a
    // weapon they already wear at 308: QE Live had valued the vault copy at
    // 321 (docs/ARCHITECTURE.md §9).
    //
    // Both off is one consistent question - "what is best from what I have, at
    // the levels the client reports". Both ON is the other consistent question,
    // "what is best if I upgraded everything to the top of its track". Mixing
    // them asks a question with no answer in the world, and that is the pair
    // the companion refuses to inherit silently.
    //
    // The two are not independent in his engine: `processItem` reads
    // `if (autoUpgradeAll) ... else if (type === "Vault" && autoUpgradeVault)`
    // (SimCImportEngine.ts lines 672-679), so `autoUpgradeAll` already covers
    // vault options and the vault box only decides anything while it is off.
    // Both are still set explicitly, because what is asked for should not
    // depend on reading the precedence right.
    //
    // SINCE C-6 (WKE-540) THESE TWO GOVERN THE UPGRADE FINDER ONLY. Top Gear is
    // run once per named scenario and takes all three of its boxes from the
    // scenario table below, because a vault option is what it can BECOME and
    // that is a different question per scenario. The Upgrade Finder is not a
    // scenario question - it ranks drops the character does not own - so it
    // keeps being asked under the pair configured here. When the pair is both
    // off (the default) those boxes are the `asOffered` boxes exactly, so the
    // Upgrade Finder documents ride in the `asOffered` import and the run costs
    // one import per scenario and no more.
    qeAutoUpgradeVault: false,
    qeAutoUpgradeAll: false,
    // Start `npm start` in forkPath when nothing answers forkUrl.
    startFork: true,
    // Show the browser. Useful once, when a selector stops matching.
    headed: false,
    // Where the browser profile lives, so the welcome dialog is answered once.
    stateDir: '.state',
    // Seconds to wait for a freshly started fork to answer.
    forkStartTimeoutSeconds: 180,
    // Milliseconds of quiet after a SavedVariables write before reading it.
    debounceMs: 1500,
};

const KNOWN = new Set(Object.keys(DEFAULTS));

// The named what-if scenarios (WKE-540, C-6; decision 2026-09-08,
// docs/ARCHITECTURE.md §7). The owner's point: a vault option is not the item as
// it is offered. Put the 308 Scavenger's Spaulders through the Catalyst and they
// are tier shoulders at 308 - the set bonus is kept and the item level does not
// drop. Upgrade tracks do the same thing along the other axis.
//
// QE Live already models both, in his import dialog's three checkboxes
// (SimCImportEngine.ts, read 2026-09-08): `autoCatalyze` adds a catalyzed clone
// of every ACTIVE item his `Item.canBeCatalyzed()` accepts, and
// `autoUpgradeAll` / `autoUpgradeVault` raise tracked items to his
// `CONSTANTS.itemLevelCaps`. So Lootpath models neither. It asks him each
// question by name and shows each answer by name.
//
// The names are fixed and are the contract: this table, the `scenario` field in
// Data/QEVerdict.lua, `ns.QEImport.SCENARIOS` in the addon and the Vault tab's
// labels all use these four strings verbatim.
//
// `thisWeek` (M3-13, WKE-548) is the fourth, and it is the question a player
// with one Catalyst charge and a pile of crests actually asks: TAKE ONE THING,
// UPGRADE IT, USE THE CHARGE ONCE. The other three do not answer it - `maxed`
// assumes every item the character owns is upgraded to its cap, which nobody
// does in a week, and `catalyzed` assumes the charge but no upgrade at all. Its
// boxes are `autoUpgradeVault` on (the one thing taken out of the vault goes to
// the top of its track) with `autoUpgradeAll` off (nothing else moves) and
// `autoCatalyze` on (the one charge is spent).
const SCENARIOS = {
    asOffered: { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: false },
    catalyzed: { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: true },
    thisWeek: { autoUpgradeAll: false, autoUpgradeVault: true, autoCatalyze: true },
    maxed: { autoUpgradeAll: true, autoUpgradeVault: true, autoCatalyze: true },
};

// The order they are asked in and shown in: what the character has now first,
// then the three what-ifs in increasing distance from it.
const SCENARIO_ORDER = ['asOffered', 'catalyzed', 'thisWeek', 'maxed'];

// The one every other part of Lootpath reads. Equip Now and the Upgrade Map
// answer `asOffered` and nothing else, and a document that names no scenario is
// this one, so a file written before C-6 still loads (WKE-540 deliverable 2).
const DEFAULT_SCENARIO = 'asOffered';

class ConfigError extends Error {}

function load(file) {
    const config = { ...DEFAULTS };
    let raw = null;
    if (file && fs.existsSync(file)) {
        try {
            raw = JSON.parse(fs.readFileSync(file, 'utf8'));
        } catch (e) {
            throw new ConfigError(`${file} is not valid JSON: ${e.message}`);
        }
    }
    return { ...merge(config, raw || {}), configFile: file && fs.existsSync(file) ? file : null };
}

function merge(config, raw) {
    const warnings = [];
    for (const key of Object.keys(raw)) {
        if (!KNOWN.has(key)) {
            warnings.push(`unknown setting "${key}" ignored`);
            continue;
        }
        const want = typeof DEFAULTS[key];
        const got = Array.isArray(raw[key]) ? 'object' : typeof raw[key];
        if (got !== want) {
            throw new ConfigError(`setting "${key}" should be a ${Array.isArray(DEFAULTS[key]) ? 'list' : want}, not a ${got}`);
        }
        config[key] = raw[key];
    }
    for (const doc of config.documents) {
        if (!doc || (doc.kind !== 'topgear' && doc.kind !== 'upgradefinder')) {
            throw new ConfigError(`each document needs kind "topgear" or "upgradefinder", saw ${JSON.stringify(doc && doc.kind)}`);
        }
        if (doc.contentType !== 'Dungeon' && doc.contentType !== 'Raid') {
            throw new ConfigError(
                `each document needs contentType "Dungeon" or "Raid" (QE Live's own strings; it has no "Mythic+"), saw ${JSON.stringify(doc.contentType)}`
            );
        }
    }
    if (!config.documents.length) throw new ConfigError('documents is empty, so there would be nothing to write');
    if (!Number.isInteger(config.topGearPasses) || config.topGearPasses < 1) {
        throw new ConfigError(`topGearPasses should be a whole number of passes, at least 1, not ${JSON.stringify(config.topGearPasses)}`);
    }
    config.upgradeFinderKeyLevels = normaliseKeyLevels(config.upgradeFinderKeyLevels);
    config.scenarios = normaliseScenarios(config.scenarios);
    config.warnings = warnings;
    return config;
}

// Deduplicated and put back into SCENARIO_ORDER, for the same reason the key
// levels are sorted: `["maxed", "asOffered"]` and `["asOffered", "maxed"]` are
// the same question and must not be two fingerprints.
//
// `asOffered` is not optional. It is the document Equip Now and the Upgrade Map
// read, and a companion that stopped writing it would leave those two tabs with
// nothing while the Vault tab answered a question nobody had asked first.
function normaliseScenarios(raw) {
    if (!Array.isArray(raw)) throw new ConfigError(`scenarios should be a list of scenario names, not ${JSON.stringify(raw)}`);
    const seen = new Set();
    for (const value of raw) {
        if (typeof value !== 'string' || !(value in SCENARIOS)) {
            throw new ConfigError(
                `scenarios holds ${JSON.stringify(value)}; QE Live is asked ${SCENARIO_ORDER.join(', ')} and nothing else`
            );
        }
        seen.add(value);
    }
    if (!seen.has(DEFAULT_SCENARIO)) {
        throw new ConfigError(
            `scenarios must include "${DEFAULT_SCENARIO}": Equip Now and the Upgrade Map read that document and no other`
        );
    }
    return SCENARIO_ORDER.filter((name) => seen.has(name));
}

// The three checkboxes a scenario asks QE Live for. A copy, so no caller can
// edit the table by editing what it was handed.
function scenarioBoxes(name) {
    const boxes = SCENARIOS[name];
    if (!boxes) throw new ConfigError(`unknown scenario ${JSON.stringify(name)}`);
    return { ...boxes };
}

function sameBoxes(a, b) {
    return ['autoUpgradeAll', 'autoUpgradeVault', 'autoCatalyze'].every((key) => !!a[key] === !!b[key]);
}

// Sorted ascending and deduplicated, so `[10, 2, 2]` and `[2, 10]` are the same
// question rather than two fingerprints - and so the last dungeon run of a plan
// is always the highest key, which is the one the Raid document inherits.
function normaliseKeyLevels(raw) {
    if (!Array.isArray(raw)) throw new ConfigError(`upgradeFinderKeyLevels should be a list of key levels, not ${JSON.stringify(raw)}`);
    const seen = new Set();
    for (const value of raw) {
        if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
            throw new ConfigError(
                `upgradeFinderKeyLevels holds ${JSON.stringify(value)}; every entry must be a whole key level like 2, 4 or 10`
            );
        }
        seen.add(value);
    }
    if (!seen.size) {
        throw new ConfigError('upgradeFinderKeyLevels is empty, so the Upgrade Finder would never be run for a dungeon');
    }
    return [...seen].sort((a, b) => a - b);
}

// Every Upgrade Finder document one configured entry expands into.
function upgradeFinderDocuments(config, doc) {
    const levels = config.upgradeFinderKeyLevels;
    if (doc.contentType === 'Dungeon') {
        return levels.map((keyLevel) => ({ kind: doc.kind, contentType: doc.contentType, keyLevel }));
    }
    return [{ kind: doc.kind, contentType: doc.contentType, keyLevel: levels[levels.length - 1] }];
}

// The PASSES one run makes over QE Live (WKE-540, C-6): an import with one set
// of checkboxes, then every document that import can answer.
//
// A pass exists because the three boxes act AT IMPORT: `runSimC` is handed their
// state (SimCraftDialog.js handleSubmit), and a box flipped afterwards changes
// nothing. So each scenario means re-pasting the same profile with different
// boxes and running Top Gear again over the player it built.
//
// `opts.hasVaultGear` / `opts.force` WAIVE the gate on the three what-ifs; they
// no longer decide it (C-12, WKE-577). Until 2026-09-14 a vault section with
// gear in it was the only thing that let `catalyzed`, `thisWeek` or `maxed` be
// asked at all, on the premise that with nothing in the vault there is nothing
// to catalyse or upgrade that is not already yours. The owner's first refresh
// after claiming his vault reward refuted it: he was holding a Catalyst
// candidate and a weapon two crest steps short of its cap, and the companion
// asked about neither because the vault was empty.
//
// So each what-if is now gated on ITS OWN question, and the gate is settled
// after that pass's import, off the pool QE Live itself built - `gate.kind`
// here, `poolEvidence` / `gateVerdict` below, and lib/fork.js reading the cards.
// A vault section with gear in it, or `--force`, still waives the gate outright
// rather than paying for a pool read that could only agree.
//
// Why the fork decides and not this file: Catalyst eligibility is a season's
// worth of slot and source rules that live in his `Item.canBeCatalyzed`, and an
// item's upgrade cap is his `CONSTANTS.itemLevelCaps`. Lootpath restates
// neither. It imports the profile with the boxes the question needs and counts
// what came back.

// The Upgrade Finder is not a scenario question - scenarios are about the vault
// options in front of you, and the Upgrade Finder ranks drops you do not own -
// so its documents ride in whichever pass already asks for the configured
// `qeAutoUpgradeAll` / `qeAutoUpgradeVault` pair with catalyze off. Under the
// default (both off) that pass IS `asOffered` and no extra import happens; under
// any other pair the Upgrade Finder gets a pass of its own, which is honest
// rather than cheap: it is a different question and it is asked separately.
//
// What each scenario's question needs before it is worth an answer. `null` is
// "always": `asOffered` is what the character has now, and that question has an
// answer whatever the character is holding.
//
//   catalyst  QE Live made at least one Catalyst clone out of this pool
//   upgrade   at least one item this pool carries came back above the level the
//             base pass valued it at, which is his engine saying it is below
//             its upgrade cap
//   either    `thisWeek` is the two questions together (take one thing, upgrade
//             it, spend the one charge), so either half is reason enough
const SCENARIO_GATES = {
    asOffered: null,
    catalyzed: 'catalyst',
    thisWeek: 'either',
    maxed: 'upgrade',
};

const GATE_KINDS = ['catalyst', 'upgrade', 'either'];

function gateOf(name) {
    if (!(name in SCENARIOS)) throw new ConfigError(`unknown scenario ${JSON.stringify(name)}`);
    return SCENARIO_GATES[name] || null;
}

function plannedPasses(config, opts) {
    const options = opts || {};
    const waived = options.hasVaultGear
        ? 'the vault has gear to ask about'
        : options.force
          ? '--force asked for it'
          : null;
    const wanted = config.scenarios.slice();
    const finderBoxes = {
        autoUpgradeAll: !!config.qeAutoUpgradeAll,
        autoUpgradeVault: !!config.qeAutoUpgradeVault,
        autoCatalyze: false,
    };
    const finders = config.documents.filter((doc) => doc.kind === 'upgradefinder');
    const host = finders.length ? wanted.find((name) => sameBoxes(SCENARIOS[name], finderBoxes)) || null : null;

    const passes = wanted.map((name) => ({
        scenario: name,
        boxes: scenarioBoxes(name),
        // null when this pass runs whatever its pool turns out to hold, and
        // `why` is what the log and the verdict then say about it; a
        // `{ kind }` otherwise, for lib/fork.js to settle after the import.
        gate: gateOf(name) && !waived ? { kind: gateOf(name) } : null,
        why: gateOf(name) ? waived || null : 'it is what you have now',
        // config.documents order is kept inside a pass, so the content type
        // switches as few times as the configured list allows.
        documents: config.documents.flatMap((doc) => {
            if (doc.kind === 'topgear') return [{ kind: doc.kind, contentType: doc.contentType, scenario: name }];
            return name === host ? upgradeFinderDocuments(config, doc) : [];
        }),
    }));
    if (finders.length && !host) {
        passes.push({
            scenario: null,
            boxes: finderBoxes,
            gate: null,
            why: 'the Upgrade Finder is not a scenario question',
            documents: finders.flatMap((doc) => upgradeFinderDocuments(config, doc)),
        });
    }
    return passes;
}

// The named scenarios one run PLANS to ask, which is what the fingerprint is
// hashed over (C-12). Every gate below is settled from the pool QE Live builds
// out of the profile text, and the profile text is already in the hash, so a
// run whose answer would differ has a different fingerprint whether the gate
// moved or the gear did.
function plannedScenarios(config, opts) {
    return plannedPasses(config, opts)
        .map((pass) => pass.scenario)
        .filter(Boolean);
}

// The highest level each item ID appears at in one pass's pool. Keyed by item
// ID and not by the whole item key on purpose: a card's bonus IDs are his
// engine's business and an upgrade may or may not rewrite them, while the ID of
// the item in the character's hands does not move. Two rings of one ID collapse
// to their best, which is all the question needs - "did anything come back
// higher than the base pass valued it at".
//
// Catalyst clones are left out: a clone's ID is a tier piece the character does
// not own, so it is in no base pool and would read as an upgrade of nothing.
function levelsByItem(cards) {
    const levels = new Map();
    for (const card of cards || []) {
        if (!card || card.catalyst) continue;
        const id = card.itemID;
        if (!Number.isInteger(id) || !Number.isInteger(card.level)) continue;
        if (!levels.has(id) || levels.get(id) < card.level) levels.set(id, card.level);
    }
    return levels;
}

// What one pass's pool says about the two questions. Pure: cards in, counts out.
function poolEvidence(cards, baseLevels) {
    const list = Array.isArray(cards) ? cards : [];
    const clones = list.filter((card) => card && card.catalyst).length;
    let raised = 0;
    if (baseLevels instanceof Map) {
        for (const [id, level] of levelsByItem(list)) {
            const was = baseLevels.get(id);
            if (Number.isInteger(was) && level > was) raised += 1;
        }
    }
    return { clones, raised, readBase: baseLevels instanceof Map, cards: list.length };
}

// The gate, settled. `{ ran, reason }`, and the reason is said whichever way it
// went, because "why did this run make eight documents where the last one made
// fourteen" is the question the log has to answer without being asked twice.
//
// It FAILS OPEN: a gate with no pool to read, or a kind this build does not
// know, runs its pass and says so. A question skipped for want of evidence is
// the defect C-12 exists to fix, and it must not come back in through the
// guard.
function gateVerdict(kind, evidence) {
    const seen = evidence || {};
    const clones = seen.clones || 0;
    const raised = seen.raised || 0;
    if (!GATE_KINDS.includes(kind)) {
        return {
            ran: true,
            reason: `the ${JSON.stringify(kind)} gate is not one this build knows, so the pass was asked anyway`,
        };
    }
    if (!seen.cards) {
        return { ran: true, reason: "QE Live's pool could not be read, so nothing was assumed" };
    }
    const catalyst = clones > 0;
    const upgrade = seen.readBase ? raised > 0 : true;
    const catalystWhy = catalyst
        ? `${clones} Catalyst ${clones === 1 ? 'clone' : 'clones'} of what you hold`
        : 'nothing you hold can be catalysed';
    const upgradeWhy = !seen.readBase
        ? 'the base pool was never read, so nothing was assumed about upgrade caps'
        : upgrade
          ? `${raised} ${raised === 1 ? 'item' : 'items'} you hold below ${raised === 1 ? 'its' : 'their'} upgrade cap`
          : 'nothing you hold is below its upgrade cap';
    // `missing` is the QUESTIONS that came back without an answer, and it is
    // what `scenarioNote` builds its one sentence out of. Three skipped passes
    // that all foundered on the same two facts have to read as those two facts
    // said once, not as three reasons said in a row.
    if (kind === 'catalyst') return { ran: catalyst, reason: catalystWhy, missing: catalyst ? [] : ['catalyst'] };
    if (kind === 'upgrade') return { ran: upgrade, reason: upgradeWhy, missing: upgrade ? [] : ['upgrade'] };
    if (catalyst || upgrade) {
        return {
            ran: true,
            reason: [catalyst ? catalystWhy : null, upgrade ? upgradeWhy : null].filter(Boolean).join(', '),
            missing: [],
        };
    }
    return { ran: false, reason: `${catalystWhy}, and ${upgradeWhy}`, missing: ['catalyst', 'upgrade'] };
}

// The atoms `scenarioNote` says, one per question that had no answer.
const MISSING_WORDS = {
    catalyst: 'nothing you hold can be catalysed',
    upgrade: 'nothing you hold is below its upgrade cap',
};

// "a", "a and b", "a, b and c" - the way a person writes a list.
function joinNames(names) {
    if (names.length <= 1) return names[0] || '';
    if (names.length === 2) return `${names[0]} and ${names[1]}`;
    return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

// What a reader is told a scenario IS. The four names are the contract - the
// verdict file, `ns.QEImport.SCENARIOS` and the Vault tab's dropdown all use
// them verbatim - but the contract is not English, and the sentence below is
// read on the Vault tab by a person who never chose those words. The log keeps
// the names: its pass-by-pass lines say `catalyzed: SKIPPED - ...`, which is
// the one grep the next reading needs.
//
// `thisWeek` is spelled the way `ns.Roads.PLAN_LABEL` spells it, so the footnote
// and the plan's own label name one thing.
const SCENARIO_WORDS = {
    asOffered: 'what you have now',
    catalyzed: 'the Catalyst question',
    // `ns.Roads.PLAN_LABEL.thisWeek`, verbatim.
    thisWeek: "this week's plan",
    maxed: 'the upgrade question',
};

// The one sentence the log, the status file and the verdict all say about a run
// that asked fewer questions than the config lists (C-12). One function, so the
// strip's tooltip and the Vault tab's footnote cannot word it two ways.
//
// null when every configured scenario was asked, which is the week the owner is
// usually in and is not worth a sentence.
function scenarioNote(records) {
    const skipped = (records || []).filter((record) => record && record.ran === false);
    if (!skipped.length) return null;
    const reasons = [];
    for (const record of skipped) {
        for (const missing of record.missing || []) {
            const words = MISSING_WORDS[missing];
            if (words && !reasons.includes(words)) reasons.push(words);
        }
        // A skip with no question named - a shape this build does not know -
        // still says whatever it did say, rather than being counted silently.
        if (!(record.missing || []).length && record.reason && !reasons.includes(record.reason)) {
            reasons.push(record.reason);
        }
    }
    const names = skipped.map((record) => SCENARIO_WORDS[record.name] || record.name);
    const why = joinNames(reasons) || 'no reason was recorded';
    const said = `${joinNames(names)} went unasked: ${why}.`;
    return said.charAt(0).toUpperCase() + said.slice(1);
}

// The documents one run actually produces, in order, flattened out of the
// passes above. A dungeon Upgrade Finder document is asked once per configured
// key level, because his engine values dungeon drops at exactly one key; a Top
// Gear document is asked once per scenario, because his three boxes act at
// import.
//
// A NON-dungeon Upgrade Finder document is asked once, at the HIGHEST
// configured level, and records it. WKE-543 proposed recording nothing there,
// but a Raid export is not free of the key selector: measured on the committed
// 2026-09-07 pair, the Raid Upgrade Finder export carries the same 201
// dungeon-sourced rows as the Dungeon one, every one of them stamped
// `dropDifficulty: 7` at 311/321/334 - the levels key index 7 gives. A document
// whose rows were valued at a key is filed under that key, whichever content
// type QE Live was set to when it was asked.
function plannedDocuments(config, opts) {
    return plannedPasses(config, opts).flatMap((pass) => pass.documents);
}

// The addon's own file inside the game folder. Nothing else is ever written
// there, and the directory is created only if the addon is installed.
// The pair the fork driver sets and the verdict file records, in one place so
// no caller has to remember which QE Live name goes with which config key.
function qeSettings(config) {
    return { autoUpgradeVault: !!config.qeAutoUpgradeVault, autoUpgradeAll: !!config.qeAutoUpgradeAll };
}

// The three files the companion writes into the addon's own Data folder. The
// verdict is C-2's contract; the status chunk and the log are C-9's (WKE-559),
// and they live BESIDE the verdict rather than in the state directory because
// the addon reads one of them at load and the owner reads the other over the
// game's shoulder.
const VERDICT_FILE = 'QEVerdict.lua';
const STATUS_FILE = 'CompanionStatus.lua';
const LOG_FILE = 'companion.log';
// Not in the game folder: the watcher's lock is the companion talking to
// itself, and nothing the client loads should have to step over it.
const LOCK_FILE = 'watch.lock';

function dataPath(config, name) {
    return path.join(config.wowPath, 'Interface', 'AddOns', 'Lootpath', 'Data', name);
}

function verdictPath(config) {
    return dataPath(config, VERDICT_FILE);
}

function statusPath(config) {
    return dataPath(config, STATUS_FILE);
}

function logPath(config) {
    return dataPath(config, LOG_FILE);
}

// WTF\Account\<ACCOUNT>\SavedVariables\Lootpath.lua, discovered the way
// tools/sync.ps1 discovers it. The newest wins when an install has several
// accounts; the folder name is masked in every log line.
function findSavedVariables(config) {
    const accounts = path.join(config.wowPath, 'WTF', 'Account');
    if (!fs.existsSync(accounts)) return { ok: false, reason: `no WTF\\Account directory under ${config.wowPath}` };
    const found = [];
    for (const entry of fs.readdirSync(accounts, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        const file = path.join(accounts, entry.name, 'SavedVariables', 'Lootpath.lua');
        if (fs.existsSync(file)) found.push({ file, account: entry.name, mtime: fs.statSync(file).mtimeMs });
    }
    if (!found.length) {
        return {
            ok: false,
            reason: `no SavedVariables\\Lootpath.lua under ${accounts} (log in with the addon enabled and /reload once)`,
        };
    }
    found.sort((a, b) => b.mtime - a.mtime);
    return { ok: true, ...found[0], all: found.length };
}

// The account folder name is an identifier; the log never prints it.
function maskAccount(file) {
    return String(file).replace(/([\\/]Account[\\/])[^\\/]+/i, '$1<account>');
}

module.exports = {
    DEFAULTS,
    SCENARIOS,
    SCENARIO_ORDER,
    DEFAULT_SCENARIO,
    load,
    plannedPasses,
    plannedScenarios,
    plannedDocuments,
    SCENARIO_GATES,
    SCENARIO_WORDS,
    GATE_KINDS,
    gateOf,
    levelsByItem,
    poolEvidence,
    gateVerdict,
    scenarioNote,
    scenarioBoxes,
    sameBoxes,
    qeSettings,
    dataPath,
    verdictPath,
    statusPath,
    logPath,
    VERDICT_FILE,
    STATUS_FILE,
    LOG_FILE,
    LOCK_FILE,
    findSavedVariables,
    maskAccount,
    ConfigError,
};
