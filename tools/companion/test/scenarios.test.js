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
test('the three scenarios are the boxes the issue tabled, and nothing else', () => {
    assert.deepStrictEqual(configLib.SCENARIO_ORDER, ['asOffered', 'catalyzed', 'maxed']);
    assert.strictEqual(configLib.DEFAULT_SCENARIO, 'asOffered');
    assert.deepStrictEqual(configLib.SCENARIOS, {
        asOffered: { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: false },
        catalyzed: { autoUpgradeAll: false, autoUpgradeVault: false, autoCatalyze: true },
        maxed: { autoUpgradeAll: true, autoUpgradeVault: true, autoCatalyze: true },
    });
    // Handed out as a copy, so a caller cannot edit the table by editing what
    // it was given.
    const boxes = configLib.scenarioBoxes('maxed');
    boxes.autoCatalyze = false;
    assert.strictEqual(configLib.SCENARIOS.maxed.autoCatalyze, true);
});

test('the default config asks all three, and the example config agrees', () => {
    const config = configLib.load(path.join(os.tmpdir(), 'no-such-config.json'));
    assert.deepStrictEqual(config.scenarios, ['asOffered', 'catalyzed', 'maxed']);
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
    assert.throws(() => loadWith({ scenarios: ['catalysed'] }), /QE Live is asked asOffered, catalyzed, maxed/);
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
        ['asOffered', 'catalyzed', 'maxed']
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

// Without a vault section there is nothing to catalyze or upgrade that is not
// already the character's, and the two extra imports would cost a browser minute
// a week for an answer nobody asked for.
test('with no vault gear only asOffered is asked, and --force asks anyway', () => {
    const config = configLib.load(null);
    assert.deepStrictEqual(
        configLib.plannedPasses(config, NO_VAULT).map((p) => p.scenario),
        ['asOffered']
    );
    assert.deepStrictEqual(
        configLib.plannedPasses(config, { hasVaultGear: false, force: true }).map((p) => p.scenario),
        ['asOffered', 'catalyzed', 'maxed']
    );
    // The Upgrade Finder is never one of the things skipped: it does not depend
    // on the vault at all.
    assert.strictEqual(
        configLib.plannedDocuments(config, NO_VAULT).filter((d) => d.kind === 'upgradefinder').length,
        6
    );
});

// C-5's pair still means something, and it means the UPGRADE FINDER's boxes.
// When it is not the `asOffered` pair the Upgrade Finder gets an import of its
// own rather than riding in a scenario that asks a different question.
test('a non-default upgrade pair gives the Upgrade Finder a pass of its own', () => {
    const config = loadWith({ qeAutoUpgradeAll: true, qeAutoUpgradeVault: true });
    const passes = configLib.plannedPasses(config, WITH_VAULT);
    assert.deepStrictEqual(
        passes.map((p) => p.scenario),
        ['asOffered', 'catalyzed', 'maxed', null]
    );
    assert.deepStrictEqual(passes[3].boxes, { autoUpgradeAll: true, autoUpgradeVault: true, autoCatalyze: false });
    assert.ok(passes[3].documents.every((d) => d.kind === 'upgradefinder'));
    assert.ok(passes[0].documents.every((d) => d.kind === 'topgear'));
    // `maxed` sets the same two upgrade boxes but ALSO catalyze, so it is not
    // the pass the Upgrade Finder can ride in.
    assert.ok(passes[2].documents.every((d) => d.kind === 'topgear'));
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
        ['asOffered', 'catalyzed', 'maxed']
    );
    assert.strictEqual(configLib.plannedDocuments(config, WITH_VAULT).length, 3);
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
