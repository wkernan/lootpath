// SavedVariables -> SimulationCraft text, for the companion.
//
// The builder itself is S-2's (WKE-532, `simc-profile.js` beside this file,
// with `lua-savedvariables.js` as its reader). C-1 lifted both out of
// `tools/companion-spike/` rather than keeping a second copy: S-2 mirrors the
// SimulationCraft addon's own OFFSET_* constants and slot tables, reproduces the
// client's `# Checksum:` with adler32, and enforces QE Live's two line-index
// rules, and none of that is worth having twice.
//
// This file is the thin part C-1 adds around it:
//  - one shape for the CLI to read, `{ ok, text, warnings, ... }` rather than a
//    throw, so a bad transcript is a named exit code and not a stack trace;
//  - the spec check, which is C-1's own finding (see specMismatch below).
'use strict';

const { readTranscript, buildProfile, snapshotRewardLinks } = require('./simc-profile');

// The capture the addon does not write yet: one snapshot carrying the header
// facts outright instead of the companion inferring them from `env`. Named in
// one place so a later issue can add it and only this constant moves.
const PROFILE_CAPTURE = 'profile';

// A Probe pack is `{ value, n = 1 }` (ns.Probe, Core.lua); `{ absent = true }`
// and `{ error = "..." }` have no first value.
function packValue(pack, index) {
    if (!pack || typeof pack !== 'object') return undefined;
    return pack[index || 1];
}

// R-7c (WKE-594): which captures the flush that wrote this `env` snapshot read
// and threw away, by name. `flushRefusals` is written onto the snapshot by
// `ns.Companion.CaptureAtFlush` and is the only trace a refused capture leaves,
// because a refusal deliberately stores no snapshot of its own. A Lua array
// parses as an object keyed by index, so the values are taken rather than the
// keys; anything that is not a list of `{ capture, reason }` reads as no
// refusals at all rather than as a throw.
function refusedCaptures(env) {
    const list = env && env.flushRefusals;
    if (!list || typeof list !== 'object') return [];
    return Object.values(list)
        .map((entry) => (entry && typeof entry === 'object' ? entry.capture : null))
        .filter((name) => typeof name === 'string');
}

// --- QE Live's own empty-slot rule (C-14, WKE-603) ---------------------------
//
// The owner's 2026-09-16 16:26:34 inventory read had 14 equipped records: slot
// 7, legs, absent. Two companion runs built that profile, opened the fork, spent
// a minute selecting cards, and then clicked a `Go!` button QE Live had
// disabled, for twenty seconds, twice (`Data/companion.log`, 21:26-21:28Z).
//
// **The rule is QE Live's, read out of the fork, not a list of ours.**
// `src/General/Modules/TopGear/TopGear.tsx:852` is the button:
//
//     disabled={checkSlots(gameType).length > 0 || !btnActive}
//
// and `checkSlots` (`:307`, "Check that the player has selected an item in every
// slot") counts the SELECTED items per slot, skipping vault items, and reports
// every slot standing at zero - with Finger and Trinket needing two apiece.
//
// WHAT IS MIRRORED AND WHAT IS NOT. `checkSlots` also counts `2H Weapon`,
// `1H Weapon` and `Offhand`, with a rule (`:339-346`) that a two-hander
// satisfies all three. That half is deliberately NOT mirrored here: a SimC
// profile carries `main_hand=` and `off_hand=` item strings and nothing that
// says which of the three kinds the main hand is, so a companion-side weapon
// check would refuse every two-hander in the game - and the owner plays a staff.
// The disabled button itself is the guard for the weapon half (`lib/fork.js`),
// which is why that guard exists as well as this one.
//
// Note what this is ABOUT: the twelve slots the character is WEARING. QE Live
// counts what a pass has selected, and a pass selects the equipped baseline plus
// whatever it clicked - so an empty worn slot poisons any pass whose clicks
// happen not to fill it, which is exactly how pass 3 of both runs came to be
// refused while passes 1 and 2 ran.
const QE_LIVE_SLOT_GROUPS = {
    head: 'head',
    neck: 'neck',
    shoulder: 'shoulder',
    back: 'back',
    chest: 'chest',
    wrist: 'wrist',
    hands: 'hands',
    waist: 'waist',
    legs: 'legs',
    feet: 'feet',
    finger1: 'finger',
    finger2: 'finger',
    trinket1: 'trinket',
    trinket2: 'trinket',
};

// One entry per group, in the order `checkSlots` walks its own table, with how
// many QE Live wants: two rings, two trinkets, one of everything else.
const QE_LIVE_SLOT_WANTED = [
    ['head', 1],
    ['neck', 1],
    ['shoulder', 1],
    ['back', 1],
    ['chest', 1],
    ['wrist', 1],
    ['hands', 1],
    ['waist', 1],
    ['legs', 1],
    ['feet', 1],
    ['finger', 2],
    ['trinket', 2],
];

// The slot names QE Live would report as missing for a character wearing
// `equippedSlots` (SimC names, as `buildProfile` returns them), in its own
// order. An empty list is a profile QE Live will take.
function missingSlots(equippedSlots) {
    const worn = {};
    for (const slot of equippedSlots || []) {
        const group = QE_LIVE_SLOT_GROUPS[slot];
        if (group) worn[group] = (worn[group] || 0) + 1;
    }
    return QE_LIVE_SLOT_WANTED.filter(([group, wanted]) => (worn[group] || 0) < wanted).map(([group]) => group);
}

// `text` is the SavedVariables file, verbatim.
function build(text, options) {
    const opts = options || {};
    let transcript;
    try {
        transcript = readTranscript(text, opts);
    } catch (e) {
        return { ok: false, reason: e.message, wanted: PROFILE_CAPTURE };
    }
    let built;
    try {
        built = buildProfile(transcript, { includeBank: opts.includeBank !== false });
    } catch (e) {
        return { ok: false, reason: e.message, wanted: PROFILE_CAPTURE };
    }

    const env = transcript.env;
    const warnings = built.missing.map(
        (field) => `the SavedVariables carry no ${field}; the line is left out rather than written empty`
    );
    if (!transcript.vault || !Object.keys(snapshotRewardLinks(transcript.vault) || {}).length) {
        warnings.push('no generated Great Vault reward in the SavedVariables, so the profile has no vault section');
    }

    return {
        ok: true,
        text: built.text,
        warnings,
        counts: built.counts,
        // C-14 (WKE-603): which slots the character is wearing something in,
        // and which of QE Live's twelve are empty. `missing` is what the
        // refusal names; an empty list is a profile QE Live will take.
        equippedSlots: built.equippedSlots,
        missingSlots: missingSlots(built.equippedSlots),
        capturedAtLocal: built.capturedAtLocal,
        // M3-16b (WKE-583): which of the transcript's vault snapshots the
        // profile was built from, and why (see chooseVaultSnapshot in
        // simc-profile.js). The companion logs it, because `0 vault` on reset
        // day was a choice between snapshots and the log said nothing about it.
        vaultChoice: transcript.vaultChoice || null,
        // R-6 (WKE-578): how the newest `env` snapshot came to be taken, and
        // when. `trigger` is "refresh" for a snapshot `/lootpath refresh` took,
        // "flush" for one the unload sequence took (R-7a, WKE-582; "logout" from
        // an addon at exactly R-7) and "command" for one typed by hand; a
        // transcript written before R-6 carries none of them, and reads as
        // unknown rather than as any of them.
        capture: {
            trigger: (env && typeof env.trigger === 'string' && env.trigger) || null,
            capturedAt: (env && typeof env.capturedAt === 'number' && env.capturedAt) || null,
            // R-7c (WKE-594): `["inventory"]` for a flush that could not read
            // the gear, which is every real logout measured so far.
            flushRefusals: refusedCaptures(env),
        },
        identity: {
            name: env && packValue(env.data.player),
            realm: env && packValue(env.data.realm),
            // GetSpecializationInfo's second return is the spec's own name.
            spec: env && packValue(env.data.specInfo, 2),
        },
    };
}

// QE Live values the spec selected in ITS OWN character panel, not the `spec=`
// line: `runSimC` never reads that line (SimCImportEngine.ts, and S-2's field
// table says the same). Measured 2026-09-08 - a profile written `spec=guardian`
// came back as a "Restoration Druid" report, because that is what the browser
// profile held. So every Top Gear document is checked against the spec the
// SavedVariables recorded, and a disagreement is said out loud with both names:
// the numbers are QE Live's and they are for ITS spec, whatever the client last
// captured.
function specMismatch(verdictSpec, capturedSpec) {
    if (!verdictSpec || !capturedSpec) return null;
    const normalise = (s) => String(s).toLowerCase();
    if (normalise(verdictSpec).includes(normalise(capturedSpec))) return null;
    return `QE Live valued "${verdictSpec}" but the SavedVariables were captured in "${capturedSpec}"; the numbers are for QE Live's spec. Pick the right spec in the fork, or capture again in the spec you play`;
}

module.exports = { build, specMismatch, missingSlots, PROFILE_CAPTURE, QE_LIVE_SLOT_WANTED };
