// Writes Data/QEVerdict.lua: the one file the companion puts inside the game
// folder, and the one exception to "everything external arrives by paste"
// (decision 2026-09-07, docs/ARCHITECTURE.md §7).
//
// The chunk is DATA, never code. It declares one local, guards that it really
// was loaded by the addon, and assigns one table of string literals and
// numbers. Nothing else: no function, no loop, no call, no require of anything
// the client would have to resolve. The addon (WKE-534) lists it in the .toc
// and runs each `json` string through the same ns.QEImport.Parse a paste goes
// through, so every schema pin, version pin and refusal still applies - the
// companion is a courier, not a second parser.
//
// The escaper below is the whole security surface of that promise, so it is
// tested against quotes, backslashes, "]]", newlines, carriage returns, NULs,
// other control bytes and a chunk of Lua source pretending to be JSON.
'use strict';

// Lua 5.1 quoted-string escapes. A byte >= 0x80 passes through untouched: the
// client reads addon files as bytes and QE Live's JSON is UTF-8, so escaping
// them would only triple the file for nothing. Everything below 0x20, the
// DEL byte, the quote and the backslash are escaped, which leaves no byte that
// can end the literal early.
function luaString(value) {
    let out = '"';
    const text = String(value);
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        const code = text.charCodeAt(i);
        if (ch === '"') out += '\\"';
        else if (ch === '\\') out += '\\\\';
        else if (ch === '\n') out += '\\n';
        else if (ch === '\r') out += '\\r';
        else if (ch === '\t') out += '\\t';
        else if (code < 0x20 || code === 0x7f) out += '\\' + String(code).padStart(3, '0');
        else out += ch;
    }
    return out + '"';
}

function luaBoolean(value) {
    if (typeof value !== 'boolean') throw new Error(`refusing to write a non-boolean: ${JSON.stringify(value)}`);
    return value ? 'true' : 'false';
}

function luaNumber(value) {
    if (!Number.isFinite(value)) throw new Error(`refusing to write a non-finite number: ${value}`);
    return String(value);
}

// The contract is the ADDON's, not the companion's: `ns.companionVerdict` with
// an `exports` list of `{ schema, contentType, json }`, settled by C-2
// (WKE-534, `Lootpath/Modules/Companion.lua`). `Companion.Entry` dispatches on
// `schema`, treats `contentType` as advisory (the one inside the JSON wins) and
// ignores any field it does not know, so `bytes` rides along as a diagnostic.
const SCHEMA_BY_KIND = {
    topgear: 'qe-live-droptimizer',
    upgradefinder: 'qe-live-upgradefinder',
};
const KINDS = new Set(Object.keys(SCHEMA_BY_KIND));

// documents: [{ kind, contentType, json }] - `json` is QE Live's export text,
// carried verbatim so the addon parses exactly what the browser produced.
// Which of QE Live's own import settings this run asked for (WKE-539, C-5).
// The addon reads nothing here today - `Companion.Entry` ignores a field it
// does not know - but a verdict that says a vault option is worth 321 when the
// client reads it at 305 is only readable next to the setting that produced it,
// so the file carries it.
const QE_SETTING_KEYS = ['autoUpgradeVault', 'autoUpgradeAll'];

// The third box, written per document since C-6 (WKE-540) and never at file
// level: the file-level pair is C-2's contract and stays exactly two booleans,
// while each document says which of the three checkboxes produced IT.
const DOCUMENT_QE_SETTING_KEYS = [...QE_SETTING_KEYS, 'autoCatalyze'];

// The named scenarios (lib/config.js). Repeated here as a set rather than
// imported, so the writer refuses a name it does not know instead of writing a
// shelf the addon has never heard of; the two lists are tied together by a test.
const SCENARIOS = new Set(['asOffered', 'catalyzed', 'thisWeek', 'maxed']);

// A Top Gear document must say which scenario it answers, because filing one
// under the wrong question is a wrong answer that looks right - and because a
// document with no scenario means `asOffered` in the addon, which is the ONE
// reading a `catalyzed` answer must never get. An Upgrade Finder document must
// NOT say: scenarios do not apply to drops (WKE-540, "not the Upgrade Finder's
// business"), and one that claimed a scenario would invite a shelf QE Live never
// answered.
function scenarioOf(doc) {
    if (doc.scenario === undefined || doc.scenario === null) {
        if (doc.kind === 'topgear') {
            throw new Error(`document ${doc.kind}/${doc.contentType} carries no scenario, and every Top Gear document answers one`);
        }
        return null;
    }
    if (doc.kind !== 'topgear') {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries scenario ${JSON.stringify(doc.scenario)}, and only a Top Gear document answers one`);
    }
    if (!SCENARIOS.has(doc.scenario)) {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries scenario ${JSON.stringify(doc.scenario)}, which is not one of ${[...SCENARIOS].join(', ')}`);
    }
    return doc.scenario;
}

// The checkboxes one document was produced under. Required on every document:
// the whole point of the scenarios is that two documents over the same gear
// disagree because they were asked different questions, and a document that does
// not say which question it answered cannot be read next to the other two.
function documentSettings(doc) {
    const settings = doc.qeSettings;
    if (!settings || typeof settings !== 'object') {
        throw new Error(`document ${doc.kind}/${doc.contentType} does not say which QE Live import settings produced it`);
    }
    const out = [];
    for (const key of DOCUMENT_QE_SETTING_KEYS) {
        if (settings[key] === undefined) continue;
        if (typeof settings[key] !== 'boolean') {
            throw new Error(`document ${doc.kind}/${doc.contentType} has qeSettings.${key} = ${JSON.stringify(settings[key])}, which is not a boolean`);
        }
        out.push([key, settings[key]]);
    }
    for (const key of QE_SETTING_KEYS) {
        if (settings[key] === undefined) {
            throw new Error(`document ${doc.kind}/${doc.contentType} does not say what qeSettings.${key} was`);
        }
    }
    return out;
}

// The items QE Live's Top Gear was never shown (WKE-558, C-8).
//
// A non-patron's Top Gear takes thirty items, and the character owns more than
// thirty; the driver decides which thirty and this is the rest. It is written
// because a verdict that omits items must say so on screen: the addon prints
// the count and the names on the Equip Now and Vault tabs, so a set that never
// mentions the ring in the bags says why rather than looking like an answer
// about everything the character owns.
//
// Names come off QE Live's own cards, so they are HIS strings and go through
// the same escaper every other string here does. `level` is his item level and
// is optional; a card whose level could not be read is still named.
//
// Since C-10 (WKE-567) an entry also carries the item's identity - `itemID`,
// the sorted `bonusIDs` and, on a Catalyst clone, the `originalItem` it was
// made from. The addon builds its own `ns.ItemKey` out of the first two and
// asks "was this item left out" as an identity comparison; before C-10 the only
// join was name plus level, which two same-named items at one level break. The
// numbers are QE Live's own `data-wowhead` attribute, read and carried, never
// derived: a bonus list that is not whole numbers is refused here rather than
// half-written, because a partial list makes a key that means a different item.
const MAX_EXCLUDED = 200;

function wholeNumberOrNull(value, describe) {
    if (value === undefined || value === null) return null;
    const number = Number(value);
    if (!Number.isInteger(number) || number < 0) {
        throw new Error(`${describe} is ${JSON.stringify(value)}, which is not a whole number`);
    }
    return number;
}

// The bonus IDs of one entry, sorted, or an empty list. All or nothing: an
// entry whose list holds anything but whole numbers is refused, never trimmed
// to the readable ones, because `ns.ItemKey` over a shortened list is a key for
// an item nobody owns.
function bonusIDsOf(card, where) {
    if (card.bonusIDs === undefined || card.bonusIDs === null) return [];
    if (!Array.isArray(card.bonusIDs)) {
        throw new Error(`${where} carries an excluded entry whose bonusIDs is ${JSON.stringify(card.bonusIDs)}, not an array`);
    }
    return card.bonusIDs
        .map((bonus) => {
            const number = Number(bonus);
            if (!Number.isInteger(number) || number < 0) {
                throw new Error(`${where} carries an excluded entry with bonus ID ${JSON.stringify(bonus)}, which is not a whole number`);
            }
            return number;
        })
        .sort((a, b) => a - b);
}

function excludedList(value, where) {
    if (value === undefined || value === null) return null;
    if (!Array.isArray(value)) {
        throw new Error(`${where} carries an excluded list that is ${JSON.stringify(value)}, not an array`);
    }
    return value.slice(0, MAX_EXCLUDED).map((card) => {
        if (!card || typeof card !== 'object') {
            throw new Error(`${where} carries an excluded entry that is ${JSON.stringify(card)}, not a table`);
        }
        const name = card.name === undefined || card.name === null ? '' : String(card.name);
        const slot = card.slot === undefined || card.slot === null ? '' : String(card.slot);
        const level = card.level === undefined || card.level === null ? null : Number(card.level);
        if (level !== null && !Number.isFinite(level)) {
            throw new Error(`${where} carries an excluded entry whose level is ${JSON.stringify(card.level)}`);
        }
        const itemID = wholeNumberOrNull(card.itemID, `${where} carries an excluded entry whose itemID`);
        const originalItem = wholeNumberOrNull(card.originalItem, `${where} carries an excluded entry whose originalItem`);
        return {
            slot,
            name,
            level,
            itemID,
            bonusIDs: bonusIDsOf(card, where),
            originalItem,
            vault: !!card.vault,
            catalyst: !!card.catalyst,
        };
    });
}

// The Lua lines for one such list, at the given indent, under the field `name`
// (`excluded` or, since C-11, `considered`). Written as an array of tables so
// the addon can name each one; nothing here is computed and nothing here is a
// healer value.
function excludedLines(list, indent, name) {
    const pad = ' '.repeat(indent);
    const lines = [`${pad}${name || 'excluded'} = {`];
    for (const card of list) {
        const fields = [`slot = ${luaString(card.slot)}`, `name = ${luaString(card.name)}`];
        if (card.level !== null) fields.push(`level = ${luaNumber(card.level)}`);
        if (card.itemID !== null) fields.push(`itemID = ${luaNumber(card.itemID)}`);
        if (card.bonusIDs.length) fields.push(`bonusIDs = { ${card.bonusIDs.map(luaNumber).join(', ')} }`);
        if (card.originalItem !== null) fields.push(`originalItem = ${luaNumber(card.originalItem)}`);
        if (card.vault) fields.push('vault = true');
        if (card.catalyst) fields.push('catalyst = true');
        lines.push(`${pad}    { ${fields.join(', ')} },`);
    }
    lines.push(`${pad}},`);
    return lines;
}

// The Mythic+ key level an Upgrade Finder document was run at (WKE-543, C-7),
// written as the number a player says out loud rather than QE Live's
// `settings.dungeon`, which is an index into his own table. The addon files
// each Upgrade Finder verdict under (contentType, keyLevel) and never converts
// one to the other: the level is his page's answer, carried like every other
// number in this file.
//
// A Top Gear document never carries one, and neither does an Upgrade Finder
// document the driver ran without touching the selector.
function keyLevelOf(doc) {
    if (doc.keyLevel === undefined || doc.keyLevel === null) return null;
    if (!Number.isInteger(doc.keyLevel) || doc.keyLevel < 0) {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries keyLevel ${JSON.stringify(doc.keyLevel)}, which is not a whole key level`);
    }
    if (doc.kind !== 'upgradefinder') {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries a keyLevel, and only an Upgrade Finder document is run at a key level`);
    }
    return doc.keyLevel;
}

// Which Top Gear pass produced this document (WKE-572, C-11).
//
// A run over a character with more than thirty cards is a sequence of passes:
// pass 1 is the pool C-8 chooses, and each later pass keeps the import-time
// baseline and spends the room on the cards no pass has asked about yet. The
// number is written because the addon reads an item's rating off the pass that
// CONSIDERED it, and because the plan sentence and the best set come from pass
// 1 and from nothing else - a pass-2 document filed as though it were pass 1
// would put a set QE Live built over a different pool on the Equip Now tab.
//
// Absent means pass 1, so every file written before C-11 still says what it
// said. An Upgrade Finder document is one run over every drop the walk knows
// and chooses no pool, so it never carries a pass above 1.
function passOf(doc) {
    if (doc.pass === undefined || doc.pass === null) return null;
    if (!Number.isInteger(doc.pass) || doc.pass < 1) {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries pass ${JSON.stringify(doc.pass)}, which is not a whole pass number from 1`);
    }
    if (doc.pass > 1 && doc.kind !== 'topgear') {
        throw new Error(`document ${doc.kind}/${doc.contentType} carries pass ${doc.pass}, and only a Top Gear run makes more than one pass`);
    }
    return doc.pass;
}

// Who this rating is FOR (C-15, WKE-615).
//
// `Data/QEVerdict.lua` is ONE file per machine, and the addon loads it at every
// character's login. Until this field existed the file said nothing about whose
// gear it had rated, so an alt logging in imported the main's answer into its
// own store: the owner's Restoration Shaman, 2026-09-18, was offered fifteen
// Druid pieces it did not own. The companion has always KNOWN - `profile.js`
// builds `identity` out of the newest `env` capture - and simply did not say.
//
// `name` and `realm` are the client's own `UnitName("player")` and
// `GetRealmName()`, carried through that capture; the addon compares them
// against the same two calls and imports nothing when they disagree. BOTH are
// required: a file that cannot say who it is for cannot be trusted to anyone,
// and writing one without them would be writing the bug back.
//
// `class` is the class TOKEN - `UnitClass`'s second return, `DRUID`, the same
// word on every locale - and is optional, because a transcript captured before
// the field was carried has none. It is what finally tells a Restoration
// Druid's rating from a Restoration Shaman's: the two specs share a name, so
// the spec check alone never fired.
function characterOf(character) {
    if (!character || typeof character !== 'object') {
        throw new Error('refusing to write a verdict file that does not say which character it rated');
    }
    const text = (value) => (value === undefined || value === null ? '' : String(value));
    const name = text(character.name);
    const realm = text(character.realm);
    if (!name) throw new Error('refusing to write a verdict file whose character has no name');
    if (!realm) throw new Error('refusing to write a verdict file whose character has no realm');
    return { name, realm, class: text(character.class) };
}

function characterLines(character, indent) {
    const pad = ' '.repeat(indent);
    const lines = [`${pad}character = {`, `${pad}    name = ${luaString(character.name)},`, `${pad}    realm = ${luaString(character.realm)},`];
    if (character.class) lines.push(`${pad}    class = ${luaString(character.class)},`);
    lines.push(`${pad}},`);
    return lines;
}

function render(payload) {
    const { writtenAt, companionVersion, profileCapturedAt, documents, qeSettings, excluded, scenarioNote, profileVaultCount } = payload;
    const character = characterOf(payload.character);
    if (!Array.isArray(documents) || !documents.length) {
        throw new Error('refusing to write a verdict file with no documents');
    }
    if (!qeSettings || typeof qeSettings !== 'object') {
        throw new Error('refusing to write a verdict file that does not say which QE Live import settings produced it');
    }
    for (const key of QE_SETTING_KEYS) {
        if (typeof qeSettings[key] !== 'boolean') {
            throw new Error(`qeSettings.${key} must be a boolean, saw ${JSON.stringify(qeSettings[key])}`);
        }
    }
    const lines = [
        '-- Lootpath/Data/QEVerdict.lua - written by the Lootpath companion (tools/companion).',
        '-- Generated data, never edited by hand and never a place to put logic.',
        '-- Every string below is QE Live\'s own export text, carried unchanged; the addon',
        '-- runs each one through ns.QEImport.Parse exactly as it does a paste.',
        `-- Written at ${String(writtenAt).replace(/[^0-9A-Za-z:+.\-T Z]/g, '')}.`,
        'local _, ns = ...',
        'if type(ns) ~= "table" then',
        '    return',
        'end',
        'ns.companionVerdict = {',
        `    writtenAt = ${luaString(writtenAt)},`,
        `    companionVersion = ${luaString(companionVersion)},`,
        `    profileCapturedAt = ${luaString(profileCapturedAt || '')},`,
        ...characterLines(character, 4),
        '    qeSettings = {',
        ...QE_SETTING_KEYS.map((key) => `        ${key} = ${luaBoolean(qeSettings[key])},`),
        '    },',
    ];
    // Which named scenarios this run left unasked, and why, in the companion's
    // own words (C-12, WKE-577). One sentence and not a table: the addon shows
    // it, it does not reason over it, and the log carries the pass-by-pass
    // detail. Absent when every configured scenario was asked, which is most
    // weeks and is not worth a sentence.
    if (scenarioNote !== undefined && scenarioNote !== null && scenarioNote !== '') {
        if (typeof scenarioNote !== 'string') {
            throw new Error(`scenarioNote must be a string, saw ${JSON.stringify(scenarioNote)}`);
        }
        lines.push(`    scenarioNote = ${luaString(scenarioNote)},`);
    }
    // How many vault items the profile this run was built from carried (C-13,
    // WKE-584). A number and not a flag, because it is a count the profile
    // builder already has, and ZERO is the whole point: the addon cannot
    // otherwise tell a pool that held no vault card from a pool nobody
    // recorded, and on reset day before the player opens the Great Vault the
    // two look identical (M3-16b, WKE-583). Absent when the run did not say,
    // which is every file written before C-13.
    if (profileVaultCount !== undefined && profileVaultCount !== null) {
        if (!Number.isInteger(profileVaultCount) || profileVaultCount < 0) {
            throw new Error(`profileVaultCount must be a whole count from 0, saw ${JSON.stringify(profileVaultCount)}`);
        }
        lines.push(`    profileVaultCount = ${luaNumber(profileVaultCount)},`);
    }
    const fileExcluded = excludedList(excluded, 'the file');
    if (fileExcluded) lines.push(...excludedLines(fileExcluded, 4));
    lines.push('    exports = {');
    for (const doc of documents) {
        if (!KINDS.has(doc.kind)) throw new Error(`unknown document kind: ${doc.kind}`);
        if (typeof doc.json !== 'string' || !doc.json.length) {
            throw new Error(`document ${doc.kind}/${doc.contentType} carries no JSON text`);
        }
        const keyLevel = keyLevelOf(doc);
        const scenario = scenarioOf(doc);
        const pass = passOf(doc);
        lines.push('        {', `            schema = ${luaString(SCHEMA_BY_KIND[doc.kind])},`, `            contentType = ${luaString(doc.contentType)},`);
        if (keyLevel !== null) lines.push(`            keyLevel = ${luaNumber(keyLevel)},`);
        if (scenario !== null) lines.push(`            scenario = ${luaString(scenario)},`);
        if (pass !== null) lines.push(`            pass = ${luaNumber(pass)},`);
        lines.push('            qeSettings = {');
        for (const [key, value] of documentSettings(doc)) lines.push(`                ${key} = ${luaBoolean(value)},`);
        lines.push('            },');
        const docExcluded = excludedList(doc.excluded, `document ${doc.kind}/${doc.contentType}`);
        if (docExcluded) {
            if (doc.kind !== 'topgear') {
                throw new Error(
                    `document ${doc.kind}/${doc.contentType} carries an excluded list, and only a Top Gear document chooses a pool`
                );
            }
            lines.push(...excludedLines(docExcluded, 12));
        }
        // The other half of the pool (C-11): what this pass DID ask about. The
        // addon reads an item's rating off the pass that considered it, so a
        // document that cannot say what it saw is a document nothing can be
        // asked of; and "considered by no pass at all" is the one thing that
        // still honestly reads "beyond the rating's item limit".
        const docConsidered = excludedList(doc.considered, `document ${doc.kind}/${doc.contentType}`);
        if (docConsidered) {
            if (doc.kind !== 'topgear') {
                throw new Error(
                    `document ${doc.kind}/${doc.contentType} carries a considered list, and only a Top Gear document chooses a pool`
                );
            }
            lines.push(...excludedLines(docConsidered, 12, 'considered'));
        }
        lines.push(
            `            bytes = ${luaNumber(Buffer.byteLength(doc.json, 'utf8'))},`,
            `            json = ${luaString(doc.json)},`,
            '        },'
        );
    }
    lines.push('    },', '}', '');
    return lines.join('\n');
}

module.exports = {
    render,
    luaString,
    luaNumber,
    luaBoolean,
    characterOf,
    characterLines,
    keyLevelOf,
    passOf,
    scenarioOf,
    documentSettings,
    excludedList,
    excludedLines,
    MAX_EXCLUDED,
    KINDS,
    SCHEMA_BY_KIND,
    QE_SETTING_KEYS,
    DOCUMENT_QE_SETTING_KEYS,
    SCENARIOS,
};
