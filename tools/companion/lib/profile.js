// SavedVariables -> SimulationCraft text, the profile QE Live imports.
//
// WKE-532 (S-2) owns the question of what the addon should write for this; it
// was not merged when C-1 was built, so this module reads the captures the
// addon writes TODAY (`env`, `inventory`, `vault`) and asks by name for the one
// it would rather have (`captures.profile`, PROFILE_CAPTURE below). When S-2
// lands, its answer replaces the fallback branch and nothing else here moves.
//
// What QE Live actually reads from a SimC string was measured, not assumed,
// from the fork's own parser (src/General/Items/GearImport/SimCImportEngine.ts,
// branch lootpath/upgrade-finder-export, read 2026-09-07):
//   - checkSimCValid looks at lines 0..7 ONLY, and needs one line whose key is a
//     case-insensitive substring of the class it has selected (`druid="Name"`).
//     Its `level` check starts true and is never set false, so level is in
//     practice unchecked; `length` refuses a string over 1000 lines.
//   - lines[0] must contain "#": the character name is everything before the
//     first "-" on it.
//   - realm comes from any line containing `server=`, region from `region=`.
//     `race=` is read into a local and then NOT used (the assignment is
//     commented out in his source).
//   - **`talents=` is never read.** grep over the whole fork finds no reader;
//     the talent database it ships is used by other pages. A profile without
//     talents is therefore complete for Top Gear and the Upgrade Finder.
//   - processAllLines starts at line index 8, so no item line may appear in the
//     first eight lines.
//   - an item line is any line containing `id=`, split on ",". It reads
//     `bonus_id=`, `gem_id=`, `enchant_id=`, `titan_disc_id=`,
//     `redirected_base_stats=`, `id=`, `drop_level=`, `crafted_stats=` and
//     `ilevel=`/`ilvl=`; `content_tuning=` is ignored. The line's slot prefix is
//     decorative - the slot comes from his own item database
//     (`protoItem.slot = getItemProp(protoItem.id, "slot")`).
//   - `itemEquipped` is `!line.includes("#")`, which is how the SimC addon's
//     commented "### Gear from Bags" block reaches Top Gear as candidates.
//   - items after a `### Weekly Reward Choices` line are typed "Vault".
'use strict';

const { first } = require('./savedvariables');
const { parseItemLink } = require('./itemlink');

// The capture the addon does not write yet. Named in one place so WKE-532/534
// can rename it once and the log line follows.
const PROFILE_CAPTURE = 'profile';

// Item-link modifier types, measured 2026-09-07 by joining two committed
// fixtures on itemID: head 271528 carries modifier {type=64, value=251140} in
// spec/fixtures/captures/Lootpath-20260906-200908.lua and
// `redirected_base_stats=251140` in spec/fixtures/simc/hotornot-20260907.txt;
// neck 272228 carries {type=28, value=6014} and `content_tuning=6014`. Any
// other modifier type is dropped rather than guessed at.
const MODIFIER_FIELDS = {
    28: 'content_tuning',
    64: 'redirected_base_stats',
};

// itemEquipLoc -> the SimC line prefix. Paired slots take their number from the
// equipment slot the item was found in; a bag copy is always "1", exactly as
// the SimulationCraft addon writes it (fixture, "### Gear from Bags").
const SLOT_BY_EQUIPLOC = {
    INVTYPE_HEAD: 'head',
    INVTYPE_NECK: 'neck',
    INVTYPE_SHOULDER: 'shoulder',
    INVTYPE_CLOAK: 'back',
    INVTYPE_CHEST: 'chest',
    INVTYPE_ROBE: 'chest',
    INVTYPE_WRIST: 'wrist',
    INVTYPE_HAND: 'hands',
    INVTYPE_WAIST: 'waist',
    INVTYPE_LEGS: 'legs',
    INVTYPE_FEET: 'feet',
    INVTYPE_FINGER: 'finger',
    INVTYPE_TRINKET: 'trinket',
    INVTYPE_WEAPON: 'main_hand',
    INVTYPE_WEAPONMAINHAND: 'main_hand',
    INVTYPE_WEAPONOFFHAND: 'off_hand',
    INVTYPE_RANGEDRIGHT: 'main_hand',
    INVTYPE_2HWEAPON: 'main_hand',
    INVTYPE_RANGED: 'main_hand',
    INVTYPE_HOLDABLE: 'off_hand',
    INVTYPE_SHIELD: 'off_hand',
};

// Equipment slot 11/13 is the first ring/trinket, 12/14 the second
// (INVSLOT_FINGER1..TRINKET2); 17 is the off hand. Confirmed against the
// transcript's invSlot/equipLoc pairs by spec/../profile.test.js.
const PAIRED_SECOND = new Set([12, 14]);

// Bag indexes whose name marks them as bank storage rather than carried bags
// (Enum.BagIndex keys, transcript 2026-09-05: CharacterBankTab_1..6 = 6..11,
// AccountBankTab_1..5 = 12..16, plus the legacy negative indexes).
function isBankBag(bag) {
    const name = String(bag.name || '');
    return /BankTab/i.test(name) || /^Bank$/i.test(name) || Number(bag.bagIndex) < 0;
}

function newestSnapshot(captures, name) {
    const list = captures && captures[name];
    if (!list || typeof list !== 'object') return null;
    let best = null;
    for (const key of Object.keys(list)) {
        const snap = list[key];
        if (!snap || typeof snap !== 'object') continue;
        if (!best || (snap.capturedAt || 0) >= (best.capturedAt || 0)) best = snap;
    }
    return best;
}

function itemLine(prefix, link, { commented }) {
    const parsed = parseItemLink(link);
    if (!parsed) return null;
    const parts = [`${prefix}=`, `id=${parsed.itemID}`];
    if (parsed.enchantID) parts.push(`enchant_id=${parsed.enchantID}`);
    if (parsed.gems.length) parts.push(`gem_id=${parsed.gems.join('/')}`);
    if (parsed.bonusIDs.length) parts.push(`bonus_id=${parsed.bonusIDs.join('/')}`);
    for (const mod of parsed.modifiers) {
        const field = MODIFIER_FIELDS[mod.type];
        if (field && mod.value) parts.push(`${field}=${mod.value}`);
    }
    const line = parts.join(',');
    return { line: commented ? `# ${line}` : line, itemID: parsed.itemID };
}

function equipLocOf(record) {
    const instant = record && record.item && record.item.instant;
    if (!instant) return null;
    return instant[4] || null;
}

function slotPrefix(equipLoc, invSlot) {
    const base = SLOT_BY_EQUIPLOC[equipLoc];
    if (!base) return null;
    if (base !== 'finger' && base !== 'trinket') {
        // A one-handed weapon in the off hand is off_hand, whatever its equipLoc.
        if (invSlot === 17 && base === 'main_hand') return 'off_hand';
        return base;
    }
    return base + (invSlot && PAIRED_SECOND.has(invSlot) ? '2' : '1');
}

function gearLines(inventorySnapshot, { includeBank }) {
    const equipped = [];
    const bagged = [];
    const skipped = { nonGear: 0, unparsable: 0, bankClosed: false };
    if (!inventorySnapshot) return { equipped, bagged, skipped };
    const data = inventorySnapshot.data || {};

    for (const key of Object.keys(data.equipped || {})) {
        const record = data.equipped[key];
        const link = first(record.link);
        const prefix = slotPrefix(equipLocOf(record), record.invSlot);
        if (!prefix) {
            skipped.nonGear++;
            continue;
        }
        const built = typeof link === 'string' ? itemLine(prefix, link, { commented: false }) : null;
        if (!built) {
            skipped.unparsable++;
            continue;
        }
        equipped.push(built);
    }

    for (const bagKey of Object.keys(data.bags || {})) {
        const bag = data.bags[bagKey];
        const bank = isBankBag(bag);
        if (bank && !includeBank) continue;
        for (const slotKey of Object.keys(bag.items || {})) {
            const record = bag.items[slotKey];
            const link = first(record.link);
            const prefix = slotPrefix(equipLocOf(record), null);
            if (!prefix) {
                skipped.nonGear++;
                continue;
            }
            const built = typeof link === 'string' ? itemLine(prefix, link, { commented: true }) : null;
            if (!built) {
                skipped.unparsable++;
                continue;
            }
            bagged.push({ ...built, bank });
        }
    }

    const bankBags = Object.keys(data.bags || {}).filter((k) => isBankBag(data.bags[k]));
    skipped.bankClosed = bankBags.every((k) => !Object.keys(data.bags[k].items || {}).length);
    return { equipped, bagged, skipped };
}

function vaultLines(vaultSnapshot) {
    const out = [];
    if (!vaultSnapshot) return out;
    const links = (vaultSnapshot.data || {}).rewardLinks || {};
    for (const key of Object.keys(links)) {
        const reward = links[key];
        const link = first(reward.link);
        const prefix = slotPrefix(equipLocOf(reward), null);
        if (!prefix || typeof link !== 'string') continue;
        const built = itemLine(prefix, link, { commented: false });
        if (built) out.push(built);
    }
    return out;
}

// The header is fixed at eleven lines so that the class line always lands
// inside the eight QE Live validates and no item line ever does. A field the
// SavedVariables cannot answer is written empty and named in `warnings`, never
// invented.
function header(identity, meta) {
    const spec = identity.spec || 'Unknown';
    return [
        `# ${identity.name} - ${spec} - ${meta.writtenAt} - ${(identity.region || '??').toUpperCase()}/${identity.realm || '?'}`,
        `# Built by the Lootpath companion ${meta.companionVersion} from SavedVariables of ${meta.capturedAtLocal || 'unknown time'}`,
        `# WoW ${identity.build || 'unknown'}, TOC ${identity.interfaceVersion || 'unknown'}`,
        '# Lootpath never computes a healer value; this file only carries what the client already knows.',
        '',
        `${identity.classToken.toLowerCase()}="${identity.name}"`,
        `level=${identity.level || ''}`,
        `race=${identity.race || ''}`,
        `region=${identity.region || ''}`,
        `server=${(identity.realm || '').toLowerCase()}`,
        `spec=${spec.toLowerCase()}`,
    ];
}

function identityFrom(captures) {
    const profile = newestSnapshot(captures, PROFILE_CAPTURE);
    if (profile && profile.data) {
        const d = profile.data;
        return {
            source: PROFILE_CAPTURE,
            snapshot: profile,
            name: d.name,
            realm: d.realm,
            region: d.region,
            level: d.level,
            race: d.race,
            classToken: d.classToken,
            spec: d.spec,
            build: d.build,
            interfaceVersion: d.interfaceVersion,
        };
    }
    const env = newestSnapshot(captures, 'env');
    if (!env || !env.data) return { source: 'env', snapshot: null };
    const d = env.data;
    const build = d.build || {};
    return {
        source: 'env',
        snapshot: env,
        name: first(d.player),
        realm: first(d.realm),
        // `env` reads neither region, level nor race: GetCurrentRegionName,
        // UnitLevel and UnitRace are not among the functions Captures.lua names.
        region: null,
        level: null,
        race: null,
        classToken: d.class && d.class[2],
        spec: d.specInfo && d.specInfo[2],
        build: build[1],
        interfaceVersion: build[4],
    };
}

function build(db, options) {
    const opts = options || {};
    const root = db && (db.LootpathDB || db);
    const captures = root && root.global && root.global.captures;
    const warnings = [];
    if (!captures) {
        return { ok: false, reason: 'the SavedVariables carry no captures table (run /lootpath capture inventory, then /reload)' };
    }

    const identity = identityFrom(captures);
    const missing = [];
    if (!identity.name) missing.push('character name');
    if (!identity.classToken) missing.push('class');
    if (!identity.realm) missing.push('realm');

    const inventory = newestSnapshot(captures, 'inventory');
    if (!inventory) missing.push('an inventory capture (/lootpath capture inventory)');

    if (missing.length) {
        return {
            ok: false,
            reason: `the SavedVariables lack ${missing.join(', ')}`,
            missing,
            wanted: PROFILE_CAPTURE,
        };
    }

    const gear = gearLines(inventory, { includeBank: opts.includeBank !== false });
    if (!gear.equipped.length) {
        return {
            ok: false,
            reason: 'the inventory capture holds no equipped gear',
            missing: ['equipped gear'],
            wanted: PROFILE_CAPTURE,
        };
    }

    for (const field of ['region', 'level', 'race']) {
        if (!identity[field]) {
            warnings.push(
                `no ${field} in the SavedVariables (the "${PROFILE_CAPTURE}" capture would carry it); the line is written empty`
            );
        }
    }
    if (identity.source !== PROFILE_CAPTURE) {
        warnings.push(`built from the "env" and "inventory" captures; the "${PROFILE_CAPTURE}" capture is not written yet`);
    }
    if (gear.skipped.bankClosed) {
        warnings.push('the bank was closed when this inventory capture ran, so no bank item is in the profile');
    }

    const meta = {
        writtenAt: opts.now || new Date().toISOString(),
        companionVersion: opts.companionVersion || 'dev',
        capturedAtLocal: inventory.capturedAtLocal,
    };
    const lines = header(identity, meta);
    lines.push('', '### Gear');
    for (const item of gear.equipped) lines.push(item.line);
    if (gear.bagged.length) {
        lines.push('', '### Gear from Bags', '#');
        for (const item of gear.bagged) lines.push(item.line, '#');
    }
    const vault = vaultLines(newestSnapshot(captures, 'vault'));
    if (vault.length) {
        lines.push('', '### Weekly Reward Choices');
        for (const item of vault) lines.push(item.line);
    } else {
        warnings.push('no generated Great Vault reward in the SavedVariables, so the profile has no vault section');
    }

    const text = lines.join('\n') + '\n';
    // His parser refuses a string over 1000 lines (checkSimCValid), and the
    // bank can push a real character past that, so the companion says so here
    // rather than letting QE Live answer with an unexplained error dialog.
    if (lines.length >= 1000) {
        return {
            ok: false,
            reason: `the profile is ${lines.length} lines and QE Live refuses anything over 1000; run with includeBank: false`,
        };
    }

    return {
        ok: true,
        text,
        warnings,
        counts: {
            equipped: gear.equipped.length,
            bagged: gear.bagged.length,
            bank: gear.bagged.filter((i) => i.bank).length,
            vault: vault.length,
            lines: lines.length,
            skippedNonGear: gear.skipped.nonGear,
            skippedUnparsable: gear.skipped.unparsable,
        },
        identity,
        capturedAt: inventory.capturedAt,
        capturedAtLocal: inventory.capturedAtLocal,
    };
}

// QE Live values the spec selected in ITS OWN character panel, not the `spec=`
// line: runSimC never reads that line (SimCImportEngine.ts). Measured
// 2026-09-08 - a profile written `spec=guardian` came back as a "Restoration
// Druid" report, because that is what the browser profile had. So every Top
// Gear document is checked against the spec the SavedVariables recorded, and a
// disagreement is said out loud with both names: the numbers are QE Live's and
// they are for ITS spec, whatever the client last captured.
function specMismatch(verdictSpec, capturedSpec) {
    if (!verdictSpec || !capturedSpec) return null;
    const normalise = (s) => String(s).toLowerCase();
    if (normalise(verdictSpec).includes(normalise(capturedSpec))) return null;
    return `QE Live valued "${verdictSpec}" but the SavedVariables were captured in "${capturedSpec}"; the numbers are for QE Live's spec. Pick the right spec in the fork, or capture again in the spec you play`;
}

module.exports = {
    build,
    specMismatch,
    PROFILE_CAPTURE,
    SLOT_BY_EQUIPLOC,
    MODIFIER_FIELDS,
    slotPrefix,
    isBankBag,
    newestSnapshot,
};
