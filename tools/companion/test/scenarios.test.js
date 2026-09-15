// C-6 (WKE-540): the vault what-ifs are QE Live's own named scenarios.
//
// A vault option is not the item as it is offered. Put the 308 Scavenger's
// Spaulders through the Catalyst and they are tier shoulders at 308; upgrade
// tracks move the level the same way. QE Live models both, in the three
// checkboxes of his import dialog, so the companion asks him each question by
// name - one import per scenario, because the boxes act AT import - and the
// addon files each answer by name.
//
// Nothing here opens a browser. The one part that does is proved by a recorded
// run, whose figures are in the pull request and docs/ARCHITECTURE.md §9.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const configLib = require('../lib/config');
const forkLib = require('../lib/fork');
const fingerprintLib = require('../lib/fingerprint');
const logLib = require('../lib/log');
const luawriterLib = require('../lib/luawriter');

function quietLog() {
    return logLib.make(() => {});
}

const WITH_VAULT = { hasVaultGear: true };
const NO_VAULT = { hasVaultGear: false };

// The validation runs inside `load`, so it is reached the way the owner reaches
// it: through a config file.
function loadWith(raw) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-c6-'));
    const file = path.join(dir, 'config.json');
    fs.writeFileSync(file, JSON.stringify(raw), 'utf8');
    return configLib.load(file);
}

// --- the table --------------------------------------------------------------

// Read from QE Live's own source, 2026-09-08 (SimCImportEngine.ts ~253-265 for
// the catalyze block, ~673-680 for the two upgrade branches). These three rows
// ARE the feature: the issue tabled them and the file, the addon and the Vault
// tab all use these names verbatim.
test('the four scenarios are the boxes the issues tabled, and nothing else', () => {
    assert.deepStrictEqual(configLib.SCENARIO_ORDER, ['asOffered', 'catalyzed', 'thisWeek', 'maxed']);
    assert.strictEqual(configLib.DEFAULT_SCENARIO, 'asOffered');
    assert.deepStrictEqual(configLib.SCENARIOS, {
        asOffered: { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: false },
        catalyzed: { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: true },
        // M3-13 (WKE-548): take one thing, upgrade it, use the charge once.
        thisWeek: { autoUpgradeAll: false, autoUpgradeVault: true, autoCatalyze: true },
        maxed: { autoUpgradeAll: true, autoUpgradeVault: true, autoCatalyze: true },
    });
    // Handed out as a copy, so a caller cannot edit the table by editing what
    // it was given.
    const boxes = configLib.scenarioBoxes('maxed');
    boxes.autoCatalyze = false;
    assert.strictEqual(configLib.SCENARIOS.maxed.autoCatalyze, true);
});

test('the default config asks all four, and the example config agrees', () => {
    const config = configLib.load(path.join(os.tmpdir(), 'no-such-config.json'));
    assert.deepStrictEqual(config.scenarios, ['asOffered', 'catalyzed', 'thisWeek', 'maxed']);
    assert.deepStrictEqual(configLib.load(path.join(__dirname, '..', 'config.example.json')).scenarios, config.scenarios);
});

test('the scenario list is one question however it is typed', () => {
    assert.deepStrictEqual(loadWith({ scenarios: ['maxed', 'asOffered', 'maxed'] }).scenarios, ['asOffered', 'maxed']);
    assert.deepStrictEqual(
        configLib.plannedDocuments(loadWith({ scenarios: ['maxed', 'asOffered'] }), WITH_VAULT),
        configLib.plannedDocuments(loadWith({ scenarios: ['asOffered', 'maxed'] }), WITH_VAULT)
    );
});

test('a name QE Live is never asked is refused, with the value in the message', () => {
    assert.throws(() => loadWith({ scenarios: ['catalysed'] }), /QE Live is asked asOffered, catalyzed, thisWeek, maxed/);
    assert.throws(() => loadWith({ scenarios: [1] }), /QE Live is asked asOffered/);
    assert.throws(() => loadWith({ scenarios: 'maxed' }), /should be a list, not a string/);
});

// Equip Now and the Upgrade Map read `asOffered` and no other document, so a
// companion that stopped writing it would leave two tabs with nothing while the
// third answered a question nobody had asked first.
test('a list without asOffered is refused, and says why', () => {
    assert.throws(() => loadWith({ scenarios: ['catalyzed', 'maxed'] }), /must include "asOffered"/);
    assert.throws(() => loadWith({ scenarios: [] }), /must include "asOffered"/);
});

// --- the plan ---------------------------------------------------------------

test('with a vault to ask about, each scenario is one import and one Top Gear run per content type', () => {
    const passes = configLib.plannedPasses(configLib.load(null), WITH_VAULT);
    assert.deepStrictEqual(
        passes.map((p) => p.scenario),
        ['asOffered', 'catalyzed', 'thisWeek', 'maxed']
    );
    assert.deepStrictEqual(passes[1].boxes, { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: true });
    // The Upgrade Finder is not a scenario question, so it is asked once - in
    // the pass whose boxes already are the configured pair with catalyze off,
    // which under the default (both off) is `asOffered`.
    assert.deepStrictEqual(
        passes[0].documents.map((d) => `${d.kind}/${d.contentType}${d.keyLevel === undefined ? '' : '+' + d.keyLevel}`),
        [
            'topgear/Dungeon',
            'upgradefinder/Dungeon+2',
            'upgradefinder/Dungeon+4',
            'upgradefinder/Dungeon+6',
            'upgradefinder/Dungeon+8',
            'upgradefinder/Dungeon+10',
            'topgear/Raid',
            'upgradefinder/Raid+10',
        ]
    );
    assert.deepStrictEqual(
        passes[2].documents.map((d) => `${d.kind}/${d.contentType}`),
        ['topgear/Dungeon', 'topgear/Raid']
    );
    // Every Top Gear document says which question it answers; no Upgrade Finder
    // document claims one.
    for (const doc of configLib.plannedDocuments(configLib.load(null), WITH_VAULT)) {
        if (doc.kind === 'topgear') assert.ok(doc.scenario, JSON.stringify(doc));
        else assert.strictEqual(doc.scenario, undefined, JSON.stringify(doc));
    }
});

// C-12 (WKE-577) replaced the vault gate. Every configured scenario is planned
// whatever the vault holds; what an empty vault costs is the WAIVER, so the
// three what-ifs arrive carrying their own gate for the run to settle.
test('with no vault gear every scenario is still planned, each carrying its own gate', () => {
    const config = configLib.load(null);
    assert.deepStrictEqual(
        configLib.plannedPasses(config, NO_VAULT).map((p) => p.scenario),
        ['asOffered', 'catalyzed', 'thisWeek', 'maxed']
    );
    assert.deepStrictEqual(
        configLib.plannedPasses(config, NO_VAULT).map((p) => p.gate && p.gate.kind),
        [null, 'catalyst', 'either', 'upgrade']
    );
    // A vault with gear in it, and --force, waive the gate outright rather than
    // paying for a pool read that could only agree.
    for (const opts of [WITH_VAULT, { hasVaultGear: false, force: true }]) {
        const passes = configLib.plannedPasses(config, opts);
        assert.deepStrictEqual(
            passes.map((p) => p.scenario),
            ['asOffered', 'catalyzed', 'thisWeek', 'maxed']
        );
        assert.ok(passes.every((p) => p.gate === null), JSON.stringify(passes.map((p) => p.gate)));
        assert.ok(passes.slice(1).every((p) => typeof p.why === 'string' && p.why.length));
    }
    // The Upgrade Finder is never one of the things gated: it does not depend on
    // the vault, the Catalyst or an upgrade cap at all.
    assert.strictEqual(
        configLib.plannedDocuments(config, NO_VAULT).filter((d) => d.kind === 'upgradefinder').length,
        6
    );
});

// --- the gates (C-12, WKE-577) ----------------------------------------------

// The owner's week, 2026-09-14: vault claimed and empty, a Catalyst candidate on
// his shoulders and a staff at 315 two crest steps short of 321. Both questions
// have answers and the old gate asked neither.
const POOL_BOTH = { clones: 1, raised: 1, readBase: true, cards: 40 };
const POOL_NOTHING = { clones: 0, raised: 0, readBase: true, cards: 40 };

test('a profile with no vault and one Catalyst candidate runs catalyzed', () => {
    const catalyzed = configLib.gateVerdict('catalyst', { clones: 1, raised: 0, readBase: true, cards: 40 });
    assert.strictEqual(catalyzed.ran, true);
    assert.match(catalyzed.reason, /1 Catalyst clone/);
    // And thisWeek, which is the two questions together, rides on that half
    // alone.
    assert.strictEqual(configLib.gateVerdict('either', { clones: 1, raised: 0, readBase: true, cards: 40 }).ran, true);
});

test('a profile with no vault and one item below its cap runs maxed', () => {
    const maxed = configLib.gateVerdict('upgrade', { clones: 0, raised: 1, readBase: true, cards: 40 });
    assert.strictEqual(maxed.ran, true);
    assert.match(maxed.reason, /1 item you hold below its upgrade cap/);
    assert.strictEqual(configLib.gateVerdict('either', { clones: 0, raised: 1, readBase: true, cards: 40 }).ran, true);
    // The Catalyst question is still its own, and still unanswered.
    assert.strictEqual(configLib.gateVerdict('catalyst', { clones: 0, raised: 1, readBase: true, cards: 40 }).ran, false);
});

test('a pool with nothing to catalyse and nothing below its cap asks asOffered alone, with the reason', () => {
    const records = [
        { name: 'asOffered', ran: true, reason: 'it is what you have now' },
        { name: 'catalyzed', ...configLib.gateVerdict('catalyst', POOL_NOTHING) },
        { name: 'thisWeek', ...configLib.gateVerdict('either', POOL_NOTHING) },
        { name: 'maxed', ...configLib.gateVerdict('upgrade', POOL_NOTHING) },
    ];
    assert.deepStrictEqual(
        records.filter((r) => r.ran).map((r) => r.name),
        ['asOffered']
    );
    // Three passes, two facts: the sentence says each fact once. It is read on
    // the Vault tab by a person, so it says what the scenarios ARE - the four
    // contract names stay in the log, where the pass-by-pass lines carry them.
    assert.strictEqual(
        configLib.scenarioNote(records),
        "The Catalyst question, this week's plan and the upgrade question went unasked:" +
            ' nothing you hold can be catalysed and nothing you hold is below its upgrade cap.'
    );
    // The other reachable shape: something to catalyse, nothing below its cap.
    // `thisWeek` is not in it, because either half is enough for that one.
    const halfWay = { clones: 1, raised: 0, readBase: true, cards: 40 };
    assert.strictEqual(
        configLib.scenarioNote([
            { name: 'asOffered', ran: true },
            { name: 'catalyzed', ...configLib.gateVerdict('catalyst', halfWay) },
            { name: 'thisWeek', ...configLib.gateVerdict('either', halfWay) },
            { name: 'maxed', ...configLib.gateVerdict('upgrade', halfWay) },
        ]),
        'The upgrade question went unasked: nothing you hold is below its upgrade cap.'
    );
    // A run that asked everything says nothing: the sentence exists to explain
    // an absence, and there is none.
    assert.strictEqual(
        configLib.scenarioNote([
            { name: 'asOffered', ran: true },
            { name: 'catalyzed', ...configLib.gateVerdict('catalyst', POOL_BOTH) },
        ]),
        null
    );
});

// A question skipped for want of evidence is the defect C-12 exists to fix, so
// the guard fails OPEN: no pool, no base pass, or a gate kind this build does
// not know all ask anyway, and say why.
test('a gate with nothing to read asks its pass anyway and says so', () => {
    const noPool = configLib.gateVerdict('catalyst', { clones: 0, raised: 0, readBase: true, cards: 0 });
    assert.strictEqual(noPool.ran, true);
    assert.match(noPool.reason, /pool could not be read/);
    const noBase = configLib.gateVerdict('upgrade', { clones: 0, raised: 0, readBase: false, cards: 40 });
    assert.strictEqual(noBase.ran, true);
    assert.match(noBase.reason, /base pool was never read/);
    const unknown = configLib.gateVerdict('nonsense', { clones: 0, raised: 0, readBase: true, cards: 40 });
    assert.strictEqual(unknown.ran, true);
    assert.match(unknown.reason, /not one this build knows/);
});

// The pool arithmetic itself, over the card records lib/fork.js reads off his
// page (C-8/C-10's `cardFromRow` shape).
test('the pool is counted off QE Live own cards, clones apart from levels', () => {
    const base = configLib.levelsByItem([
        { itemID: 271528, level: 315, catalyst: false },
        { itemID: 271528, level: 308, catalyst: false },
        { itemID: 900001, level: 999, catalyst: true },
    ]);
    // The best of the two, and the clone is not in it at all.
    assert.deepStrictEqual([...base], [[271528, 315]]);

    // The same staff, valued at its cap by an `autoUpgradeAll` import.
    const raised = configLib.poolEvidence([{ itemID: 271528, level: 321, catalyst: false }], base);
    assert.strictEqual(raised.raised, 1);
    assert.strictEqual(raised.clones, 0);
    // Nothing moved: it is already at its cap.
    assert.strictEqual(configLib.poolEvidence([{ itemID: 271528, level: 315, catalyst: false }], base).raised, 0);
    // A clone is a Catalyst answer, never an upgrade one: its ID is a tier
    // piece the character does not own, so it is in no base pool.
    const cloned = configLib.poolEvidence([{ itemID: 900001, level: 315, catalyst: true }], base);
    assert.strictEqual(cloned.clones, 1);
    assert.strictEqual(cloned.raised, 0);
    // No base pass read at all is not "nothing moved".
    assert.strictEqual(configLib.poolEvidence([{ itemID: 271528, level: 321, catalyst: false }], null).readBase, false);
});

// C-5's pair still means something, and it means the UPGRADE FINDER's boxes.
// When it is not the `asOffered` pair the Upgrade Finder gets an import of its
// own rather than riding in a scenario that asks a different question.
test('a non-default upgrade pair gives the Upgrade Finder a pass of its own', () => {
    const config = loadWith({ qeAutoUpgradeAll: true, qeAutoUpgradeVault: true });
    const passes = configLib.plannedPasses(config, WITH_VAULT);
    assert.deepStrictEqual(
        passes.map((p) => p.scenario),
        ['asOffered', 'catalyzed', 'thisWeek', 'maxed', null]
    );
    assert.deepStrictEqual(passes[4].boxes, { autoUpgradeAll: true, autoUpgradeVault: true, autoCatalyze: false });
    assert.ok(passes[4].documents.every((d) => d.kind === 'upgradefinder'));
    assert.ok(passes[0].documents.every((d) => d.kind === 'topgear'));
    // `maxed` sets the same two upgrade boxes but ALSO catalyze, so it is not
    // the pass the Upgrade Finder can ride in - and neither is `thisWeek`, which
    // shares the vault box with it and differs on the other two.
    assert.ok(passes[2].documents.every((d) => d.kind === 'topgear'));
    assert.ok(passes[3].documents.every((d) => d.kind === 'topgear'));
});

test('a config with no Upgrade Finder documents plans no pass for one', () => {
    const config = loadWith({
        documents: [{ kind: 'topgear', contentType: 'Dungeon' }],
        qeAutoUpgradeAll: true,
        qeAutoUpgradeVault: true,
    });
    const passes = configLib.plannedPasses(config, WITH_VAULT);
    assert.deepStrictEqual(
        passes.map((p) => p.scenario),
        ['asOffered', 'catalyzed', 'thisWeek', 'maxed']
    );
    assert.strictEqual(configLib.plannedDocuments(config, WITH_VAULT).length, 4);
});

// --- the fingerprint --------------------------------------------------------

// C-4's rule: the profile decides whether QE Live is asked at all. The scenario
// list is part of the question, so adding one has to cost a run and dropping one
// has to cost a run - otherwise the verdict file would keep a document for a
// question the owner stopped asking.
test('adding or dropping a scenario is a new question and costs a run', () => {
    const profile = 'druid="Hotornot"\nlevel=80\n';
    const settings = { autoUpgradeVault: false, autoUpgradeAll: false };
    const one = fingerprintLib.fingerprint(profile, settings, [2], ['asOffered']).hash;
    const two = fingerprintLib.fingerprint(profile, settings, [2], ['asOffered', 'catalyzed']).hash;
    const three = fingerprintLib.fingerprint(profile, settings, [2], ['asOffered', 'catalyzed', 'maxed']).hash;
    assert.notStrictEqual(one, two);
    assert.notStrictEqual(two, three);
    // Reordering is not a new question.
    assert.strictEqual(three, fingerprintLib.fingerprint(profile, settings, [2], ['maxed', 'catalyzed', 'asOffered']).hash);
    assert.strictEqual(three, fingerprintLib.fingerprint(profile, settings, [2], ['maxed', 'maxed', 'catalyzed', 'asOffered']).hash);
});

test('the scenario line is canonical and says so when there is nothing in it', () => {
    assert.strictEqual(fingerprintLib.scenariosLine(['maxed', 'asOffered']), '# scenarios asOffered,maxed');
    assert.strictEqual(fingerprintLib.scenariosLine([]), '# scenarios none');
    assert.strictEqual(fingerprintLib.scenariosLine(undefined), '# scenarios none');
});

// --- the driver -------------------------------------------------------------

// The same fake dialog fork.test.js uses, starting where his `useState` calls
// leave it: autoUpgradeAll false, autoUpgradeVault TRUE, autoCatalyze false
// (SimCraftDialog.js lines 36-38).
function fakeDialog() {
    const state = {
        'Upgrade ALL to Max Level': false,
        'Upgrade Vault to Max Level': true,
        'Auto Catalyze': false,
    };
    const clicks = [];
    return {
        state: state,
        clicks: clicks,
        getByRole(role, options) {
            assert.strictEqual(role, 'checkbox');
            const name = options.name;
            return {
                async count() {
                    return name in state ? 1 : 0;
                },
                async isChecked() {
                    return state[name];
                },
                async click() {
                    clicks.push(name);
                    state[name] = !state[name];
                },
            };
        },
    };
}

// C-5 deliberately left `autoCatalyze` where QE Live put it, because it was
// WKE-540's box. It is asked for now, by the same rule as the other two: set,
// read back, and a click that did not take is a failed run.
test('a scenario sets all three boxes, catalyze included, and reports what the page said', async () => {
    const page = fakeDialog();
    const applied = await forkLib.setUpgradeCheckboxes(page, configLib.scenarioBoxes('catalyzed'), quietLog());
    assert.deepStrictEqual(forkLib.settingsFrom(applied), {
        autoUpgradeAll: false,
        autoUpgradeVault: false,
        autoCatalyze: true,
    });
    // His dialog opens with the vault box on and catalyze off, so exactly those
    // two are clicked and the third is left alone.
    assert.deepStrictEqual(page.clicks.sort(), ['Auto Catalyze', 'Upgrade Vault to Max Level']);
});

test('the maxed scenario turns all three on', async () => {
    const page = fakeDialog();
    const applied = await forkLib.setUpgradeCheckboxes(page, configLib.scenarioBoxes('maxed'), quietLog());
    assert.deepStrictEqual(forkLib.settingsFrom(applied), {
        autoUpgradeAll: true,
        autoUpgradeVault: true,
        autoCatalyze: true,
    });
    assert.deepStrictEqual(page.state, {
        'Upgrade ALL to Max Level': true,
        'Upgrade Vault to Max Level': true,
        'Auto Catalyze': true,
    });
});

// The whole reason a scenario is a PASS and not a flag on a run: `runSimC` is
// handed the checkbox state at Submit (SimCraftDialog.js handleSubmit), so a box
// flipped after the import changes nothing and the same player is scored twice.
test('each pass re-imports the profile before its documents are run', async () => {
    const imports = [];
    const documents = [];
    const passes = [
        { scenario: 'asOffered', boxes: configLib.scenarioBoxes('asOffered'), documents: [{ kind: 'topgear', contentType: 'Dungeon', scenario: 'asOffered' }] },
        { scenario: 'catalyzed', boxes: configLib.scenarioBoxes('catalyzed'), documents: [{ kind: 'topgear', contentType: 'Dungeon', scenario: 'catalyzed' }] },
    ];
    // The order the driver really works in, recorded through the two calls it
    // makes per pass. `run` itself opens a browser, so what is proved here is
    // the loop's shape over the same plan the driver is handed.
    for (const pass of passes) {
        const page = fakeDialog();
        const applied = await forkLib.setUpgradeCheckboxes(page, pass.boxes, quietLog());
        imports.push(forkLib.settingsFrom(applied));
        for (const doc of pass.documents) documents.push({ ...doc, qeSettings: forkLib.settingsFrom(applied) });
    }
    assert.strictEqual(imports.length, 2);
    assert.strictEqual(imports[0].autoCatalyze, false);
    assert.strictEqual(imports[1].autoCatalyze, true);
    assert.deepStrictEqual(
        documents.map((d) => `${d.scenario}:${d.qeSettings.autoCatalyze}`),
        ['asOffered:false', 'catalyzed:true']
    );
});

// --- the fourth question (M3-13, WKE-548) -----------------------------------
//
// The three above do not answer the one a player with one Catalyst charge and a
// pile of crests actually asks. `maxed` assumes every item the character owns is
// at its cap, which nobody reaches in a week; `catalyzed` assumes the charge and
// no upgrade at all. `thisWeek` is the middle: take ONE thing out of the vault,
// upgrade THAT one thing, spend the charge, change nothing else.
//
// Measured 2026-09-09 19:22 over the owner's own profile (the 2026-09-08 12:45
// capture, 158 lines), boxes [all, vault, catalyze] = [false, true, true]:
// Dungeon top set 5812.048, Raid 6014.255 - the same two figures the earlier
// spike run of that morning produced, and neither of them any other scenario's.
test('the fourth scenario is the vault box on, the ALL box off, and the charge spent', () => {
    assert.deepStrictEqual(configLib.SCENARIOS.thisWeek, {
        autoUpgradeAll: false,
        autoUpgradeVault: true,
        autoCatalyze: true,
    });
    // It is nobody else's boxes: the vault box is what separates it from
    // `catalyzed`, and the ALL box is what separates it from `maxed`.
    assert.ok(!configLib.sameBoxes(configLib.SCENARIOS.thisWeek, configLib.SCENARIOS.catalyzed));
    assert.ok(!configLib.sameBoxes(configLib.SCENARIOS.thisWeek, configLib.SCENARIOS.maxed));
    // Asked third: after what the character has now and the plain Catalyst
    // question, before the one that assumes everything is capped.
    assert.strictEqual(configLib.SCENARIO_ORDER.indexOf('thisWeek'), 2);
});

// It is the two what-ifs together - take one thing, upgrade it, spend the one
// charge - so since C-12 it is gated on either of them having an answer.
test('the fourth scenario is gated on either of the other two questions', () => {
    const config = configLib.load(null);
    for (const opts of [NO_VAULT, WITH_VAULT, { hasVaultGear: false, force: true }]) {
        assert.ok(configLib.plannedPasses(config, opts).some((p) => p.scenario === 'thisWeek'), JSON.stringify(opts));
    }
    assert.strictEqual(configLib.gateOf('thisWeek'), 'either');
    assert.strictEqual(
        configLib.plannedPasses(config, NO_VAULT).find((p) => p.scenario === 'thisWeek').gate.kind,
        'either'
    );
    // Waived by a vault with gear in it, like the other two.
    assert.strictEqual(configLib.plannedPasses(config, WITH_VAULT).find((p) => p.scenario === 'thisWeek').gate, null);
});

// Adding it to the list is a new question and has to cost a run, which is the
// whole point of hashing the scenario list beside the profile.
test('adding the fourth scenario moves the fingerprint', () => {
    const profile = 'druid="Hotornot"\nhead=,id=271528';
    const settings = { autoUpgradeVault: false, autoUpgradeAll: false };
    const three = fingerprintLib.fingerprint(profile, settings, [2], ['asOffered', 'catalyzed', 'maxed']).hash;
    const four = fingerprintLib.fingerprint(profile, settings, [2], [
        'asOffered',
        'catalyzed',
        'thisWeek',
        'maxed',
    ]).hash;
    assert.notStrictEqual(three, four);
    assert.strictEqual(
        fingerprintLib.scenariosLine(['maxed', 'thisWeek', 'asOffered', 'catalyzed']),
        '# scenarios asOffered,catalyzed,maxed,thisWeek'
    );
});

// The writer refuses a name the addon has never heard of, and the two lists are
// the same list.
test('the writer knows exactly the scenarios the config does', () => {
    assert.deepStrictEqual([...luawriterLib.SCENARIOS].sort(), [...configLib.SCENARIO_ORDER].sort());
});
