// Config, SavedVariables discovery and the output write, over a fake game
// folder built in a temp directory. Nothing here touches the real client.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const configLib = require('../lib/config');
const { writeVerdict } = require('../lib/output');

function fakeWow(accounts) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-companion-'));
    for (const [name, contents] of Object.entries(accounts || {})) {
        const dir = path.join(root, 'WTF', 'Account', name, 'SavedVariables');
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, 'Lootpath.lua'), contents);
    }
    return root;
}

test('the built-in defaults are the owner machine and the four documents', () => {
    const config = configLib.load(path.join(os.tmpdir(), 'no-such-config.json'));
    assert.strictEqual(config.configFile, null);
    assert.strictEqual(config.wowPath, 'C:\\World of Warcraft\\_retail_');
    assert.strictEqual(config.forkPath, 'c:\\Code\\qe-live-fork');
    assert.deepStrictEqual(
        config.documents.map((d) => `${d.kind}/${d.contentType}`),
        ['topgear/Dungeon', 'upgradefinder/Dungeon', 'topgear/Raid', 'upgradefinder/Raid']
    );
});

test('the committed example config loads and matches the defaults', () => {
    const config = configLib.load(path.join(__dirname, '..', 'config.example.json'));
    assert.ok(config.configFile);
    assert.deepStrictEqual(config.warnings, []);
    for (const key of Object.keys(configLib.DEFAULTS)) {
        assert.deepStrictEqual(config[key], configLib.DEFAULTS[key], `${key} drifted from the defaults`);
    }
});

// C-5 (WKE-539). QE Live's own dialog defaults are `autoUpgradeVault = true`
// and `autoUpgradeAll = false` (SimCraftDialog.js lines 36-37), which values a
// vault option at the top of its upgrade track and owned gear where the client
// reports it. The companion's default is both OFF, so the two sides of a
// comparison are asked the same question.
test('the QE Live import settings default to both off, the opposite of his dialog', () => {
    const config = configLib.load(path.join(os.tmpdir(), 'no-such-config.json'));
    assert.strictEqual(config.qeAutoUpgradeVault, false);
    assert.strictEqual(config.qeAutoUpgradeAll, false);
    assert.deepStrictEqual(configLib.qeSettings(config), { autoUpgradeVault: false, autoUpgradeAll: false });
});

test('the settings can be set to the other consistent pair, and are typed', () => {
    const dir = fakeWow();
    const both = path.join(dir, 'both.json');
    fs.writeFileSync(both, JSON.stringify({ qeAutoUpgradeVault: true, qeAutoUpgradeAll: true }));
    assert.deepStrictEqual(configLib.qeSettings(configLib.load(both)), { autoUpgradeVault: true, autoUpgradeAll: true });

    const wrong = path.join(dir, 'wrong.json');
    fs.writeFileSync(wrong, JSON.stringify({ qeAutoUpgradeVault: 'true' }));
    assert.throws(() => configLib.load(wrong), /"qeAutoUpgradeVault" should be a boolean/);
});

test('refuses a content type QE Live does not have, naming it', () => {
    const file = path.join(fakeWow(), 'config.json');
    fs.writeFileSync(file, JSON.stringify({ documents: [{ kind: 'topgear', contentType: 'Mythic+' }] }));
    assert.throws(() => configLib.load(file), /"Mythic\+"/);
});

test('refuses a setting of the wrong type and ignores one it does not know', () => {
    const dir = fakeWow();
    const bad = path.join(dir, 'bad.json');
    fs.writeFileSync(bad, JSON.stringify({ wowPath: 3 }));
    assert.throws(() => configLib.load(bad), /should be a string/);

    const odd = path.join(dir, 'odd.json');
    fs.writeFileSync(odd, JSON.stringify({ nonsense: true }));
    assert.deepStrictEqual(configLib.load(odd).warnings, ['unknown setting "nonsense" ignored']);

    const broken = path.join(dir, 'broken.json');
    fs.writeFileSync(broken, '{ not json');
    assert.throws(() => configLib.load(broken), /not valid JSON/);
});

test('finds the SavedVariables without the account name ever being hardcoded', () => {
    const root = fakeWow({ '123456789#1': 'LootpathDB = {}' });
    const found = configLib.findSavedVariables({ wowPath: root });
    assert.ok(found.ok);
    assert.strictEqual(found.account, '123456789#1');
    assert.strictEqual(found.all, 1);
});

test('picks the newest when an install has more than one account', () => {
    const root = fakeWow({ old: 'LootpathDB = {}', fresh: 'LootpathDB = {}' });
    const fresh = path.join(root, 'WTF', 'Account', 'fresh', 'SavedVariables', 'Lootpath.lua');
    const old = path.join(root, 'WTF', 'Account', 'old', 'SavedVariables', 'Lootpath.lua');
    fs.utimesSync(old, new Date(1000), new Date(1000));
    fs.utimesSync(fresh, new Date(2000), new Date(2000));
    const found = configLib.findSavedVariables({ wowPath: root });
    assert.strictEqual(found.account, 'fresh');
    assert.strictEqual(found.all, 2);
});

test('says what to do when there is nothing to read', () => {
    // An account folder exists but the addon has never flushed.
    const root = fakeWow();
    fs.mkdirSync(path.join(root, 'WTF', 'Account', '123456789#1', 'SavedVariables'), { recursive: true });
    assert.match(configLib.findSavedVariables({ wowPath: root }).reason, /log in with the addon enabled/);
    // No WoW at that path at all.
    assert.match(configLib.findSavedVariables({ wowPath: path.join(os.tmpdir(), 'nope') }).reason, /no WTF/);
});

test('never prints the account folder name', () => {
    const masked = configLib.maskAccount('C:\\World of Warcraft\\_retail_\\WTF\\Account\\123456789#1\\SavedVariables\\Lootpath.lua');
    assert.ok(!masked.includes('123456789'));
    assert.ok(masked.endsWith('<account>\\SavedVariables\\Lootpath.lua'));
});

test('the verdict path is the addon\'s own Data folder and nowhere else', () => {
    // The separator is the platform's - CI runs this on Linux - so the
    // assertion is about the segments, not about backslashes.
    const root = path.join('C:', 'World of Warcraft', '_retail_');
    const target = configLib.verdictPath({ wowPath: root });
    assert.strictEqual(target, path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', 'QEVerdict.lua'));
});

test('writes through a temp file and leaves no temp behind', () => {
    const root = fakeWow();
    const addon = path.join(root, 'Interface', 'AddOns', 'Lootpath');
    fs.mkdirSync(addon, { recursive: true });
    const target = path.join(addon, 'Data', 'QEVerdict.lua');
    const written = writeVerdict(target, 'first\n');
    assert.strictEqual(fs.readFileSync(target, 'utf8'), 'first\n');
    assert.strictEqual(written.bytes, 6);
    // The client must never read half a file, so the bytes go to a temp file
    // beside the target and the rename does the publishing.
    assert.ok(written.temp, 'nothing was written through a temp file');
    assert.strictEqual(path.dirname(written.temp), path.dirname(target), 'the temp must be on the same volume to rename atomically');
    assert.notStrictEqual(written.temp, target);
    assert.ok(!fs.existsSync(written.temp));
    // A second write replaces it in place: no EEXIST, no half file.
    writeVerdict(target, 'second\n');
    assert.strictEqual(fs.readFileSync(target, 'utf8'), 'second\n');
    assert.deepStrictEqual(fs.readdirSync(path.dirname(target)), ['QEVerdict.lua']);
});

test('refuses to write when the addon is not installed, rather than creating a stray folder', () => {
    const root = fakeWow();
    const target = path.join(root, 'Interface', 'AddOns', 'Lootpath', 'Data', 'QEVerdict.lua');
    assert.throws(() => writeVerdict(target, 'x'), /the addon is not installed/);
    assert.ok(!fs.existsSync(path.join(root, 'Interface')));
});
