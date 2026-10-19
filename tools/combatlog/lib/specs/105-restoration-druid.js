// Restoration Druid (105): which stat scales which heal, her buffs and
// constants, and her Harmony-shaped mastery tracker - the whole of what the
// combat-log weights tool knows about this one spec (E-5, WKE-711; E-5b,
// WKE-713).
//
// docs/COMBAT-LOG-WEIGHTS.md §5 is the table and its rules, in words; this is
// the same table as data. Every row was read from SimC 1210-01's spell_query
// over game data 12.1.5.70391, committed verbatim as
// spec/fixtures/combatlog/simc-spells-70391.txt (SP coefficients, "Can't
// Crit (93)", "Periodic Can Crit (265)", "Spell Haste Affects Periodic (173)",
// cast time, GCD, cooldown, charges, Limit, and "Ignore Caster Modifiers
// (125)", "Ignore Healing Modifiers (219)", "Ignore Caster Healing Modifiers
// (312)"). test/spells.test.js re-reads that file for every flag below.
//
// This module's exported shape is the one every spec module shares
// (lib/specs/index.js's registry, keyed by identity.specID): identity,
// spellRow/ROWS/UNKNOWN, constants, buffs, mastery. A second healer spec is
// a new file beside this one plus one line in index.js, not a change to
// lib/attribute.js or lib/entry.js, which name no spell, buff or spec.
// lib/spells.js re-exports this module's names unchanged, for lib/probe.js,
// probe.js and their tests - the Harmony probe stays Restoration-only.
//
//   kind     coefficient | share | fixed | leech
//   int      the heal moves with Intellect
//   crit     'all' (direct and ticks), 'direct' (the direct part only), false
//   tick     'periodic' (its ticks are hasted), 'all' (every event is a
//            hasted pulse), false
//   cast     faster casting means proportionally more of it
//   mastery  Harmony raises it
//   vers     versatility raises it ('inherit' for a share: its parent's)
'use strict';

const S = (id, name, kind, o) => Object.freeze({ id, name, kind, int: false, crit: false, tick: false, cast: false, mastery: false, vers: false, ...o });

const ROWS = [
    S(774, 'Rejuvenation', 'coefficient', { coefficient: { periodic: 0.924 }, int: true, crit: 'all', tick: 'periodic', cast: true, mastery: true, vers: true, why: { cast: 'GCD' } }),
    S(155777, 'Rejuvenation (Germination)', 'coefficient', { coefficient: { periodic: 0.924 }, int: true, crit: 'all', tick: 'periodic', cast: true, mastery: true, vers: true, why: { cast: 'from a Rejuvenation cast' } }),
    S(8936, 'Regrowth', 'coefficient', { coefficient: { direct: 5.36, periodic: 0.224968 }, int: true, crit: 'all', tick: 'periodic', cast: true, mastery: true, vers: true, why: { cast: '1.5 s cast' } }),
    S(33763, 'Lifebloom', 'coefficient', { coefficient: { periodic: 0.2684 }, int: true, crit: 'all', tick: 'periodic', cast: true, mastery: true, vers: true, why: { cast: 'GCD' } }),
    S(33778, 'Lifebloom (bloom)', 'coefficient', { coefficient: { direct: 2.18868 }, int: true, crit: 'all', cast: true, mastery: true, vers: true, parent: 33763 }),
    S(48438, 'Wild Growth', 'coefficient', { coefficient: { periodic: 0.481 }, int: true, crit: 'all', tick: 'periodic', mastery: true, vers: true, why: { cast: '10 s cooldown' } }),
    S(102352, 'Cenarion Ward', 'coefficient', { coefficient: { periodic: 1.3272 }, int: true, crit: 'all', tick: 'periodic', mastery: true, vers: true, why: { cast: 'talent proc in this build' } }),
    S(81269, 'Efflorescence', 'coefficient', { coefficient: { direct: 0.5856 }, int: true, crit: 'all', tick: 'all', mastery: true, vers: true, parent: 1232285, why: { tick: 'pulse 81262 has 173', cast: 'cast 1232285 has Limit 1' } }),
    S(392329, 'Verdancy', 'coefficient', { coefficient: { direct: 1.33 }, int: true, crit: 'all', cast: true, mastery: true, vers: true, parent: 33778 }),
    S(18562, 'Swiftmend', 'coefficient', { coefficient: { direct: 10.37 }, int: true, crit: 'all', mastery: true, vers: true, why: { cast: '1 charge, 15 s' } }),
    S(440121, 'Bursting Growth', 'coefficient', { coefficient: { direct: 0.4209 }, int: true, crit: 'all', mastery: true, vers: true, why: { cast: 'proc' } }),
    S(439530, 'Symbiotic Blooms', 'coefficient', { coefficient: { periodic: 0.732 }, int: true, crit: 'all', mastery: true, vers: true, why: { tick: 'no 173', cast: 'proc' } }),
    S(439902, 'Flower Walk', 'coefficient', { coefficient: { direct: 0.2 }, int: true, crit: 'all', mastery: true, vers: true, why: { cast: 'Barkskin' } }),
    S(1244341, 'Everbloom', 'share', { int: true, cast: true, vers: 'inherit', parent: 33778, ignores: [93, 312] }),
    S(447132, 'Thriving Vegetation', 'share', { int: true, crit: 'all', cast: true, vers: 'inherit', parent: 774, ignores: [312] }),
    S(1264376, "Nature's Bounty", 'share', { int: true, cast: true, vers: 'inherit', parent: 8936, ignores: [93, 219] }),
    S(392117, 'Regenerative Heartwood', 'share', { int: true, cast: true, vers: 'inherit', parent: 774, ignores: [93, 125, 219] }),
    S(474760, 'Symbiotic Relationship', 'share', { int: true, vers: 'inherit', ignores: [93, 125, 219], why: { cast: 'mixed parents' } }),
    S(22842, 'Frenzied Regeneration', 'fixed', { mastery: true, vers: true, ignores: [93] }),
    S(474683, "Aessina's Renewal", 'fixed', { ignores: [93, 125, 219] }),
    S(455470, 'Lethal Preservation', 'fixed', { ignores: [93, 219] }),
    S(455474, 'Lethal Preservation', 'fixed', { ignores: [93, 219] }),
    S(1263002, 'Rune of Unleashed Fire', 'fixed', { mastery: true, vers: true, ignores: [93] }),
    S(1287665, 'Rune of Lingering', 'fixed', { mastery: true, vers: true, why: { crit: 'no 265', tick: 'no 173' } }),
    S(1287908, 'Rune of Self-Mending', 'fixed', { crit: 'all', mastery: true, vers: true }),
    S(143924, 'Leech', 'leech', {}),
];

const SPELLS = new Map(ROWS.map((r) => [r.id, r]));

// A spell not in the table counts for crit and versatility only (memo §2b).
const UNKNOWN = Object.freeze({ id: null, name: '(not in the table)', kind: 'unknown', int: false, crit: 'all', tick: false, cast: false, mastery: false, vers: true });

function spellRow(id) {
    return SPELLS.get(id) || UNKNOWN;
}

// Harmony's list: the spells carrying label 4337 (spell_query=spell.label=4337,
// exactly these seven in 12.1.5.70391).
const HARMONY_IDS = Object.freeze([774, 8936, 33763, 48438, 102352, 155777, 157982]);
const HARMONY = new Set(HARMONY_IDS);

// The stack table since 11.1 (docs/OWN-ENGINE.md §2b): T(n), 3.875 beyond 10.
const STACKS = Object.freeze([0, 1, 1.7, 2.3, 2.8, 3.2, 3.5, 3.7, 3.8, 3.85, 3.875]);
function stackFactor(n) {
    if (!(n > 0)) return 0;
    return n >= STACKS.length ? STACKS[STACKS.length - 1] : STACKS[n];
}

const CONSTANTS = Object.freeze({
    // Mastery: Harmony (77495), "SP Coefficient: 1.311": percent per mastery
    // point per counted effect.
    harmonyCoefficient: 1.311,
    // Base mastery points: GetMasteryEffect 38.56050109863281 / 1.310999989509583
    // - the 985 rating's 21.41304397583008 points (the owner's 2026-10-01
    // transcript, spec/fixtures/captures/Lootpath-20261001-092631.lua).
    // test/spells.test.js recomputes it from that file.
    masteryBase: 8,
    // The crit multiplier for heals; probe.js reads it from a log.
    critMultiplier: 2,
});

// Buffs on the player whose amount the client data gives (spell_query):
// Mark of the Wild 1126, "Modify Versatility% (471)", Base Value 3.
const PERCENT_BUFFS = Object.freeze({ 1126: { stat: 'vers', percent: 3, name: 'Mark of the Wild' } });

// Buffs that change the player's stats by an amount the client data does NOT
// give (scaled by item level; "Scaled Value: 0"), or a primary stat the
// advanced block already reads. Listed so their uptime is reported.
const UNSIZED_BUFFS = Object.freeze({
    1287771: { stat: 'mastery', name: 'Rune of Masterful Cunning', why: 'Modify Rating (189) Mastery, scaled by item level' },
    1241762: { stat: 'haste', name: 'Frenzied Focus', why: 'Modify Rating (189) Haste, scaled by item level' },
    1229746: { stat: 'int', name: 'Arcanoweave Insight', why: 'primary stat: read through the advanced block, not added' },
});

// Haste percent buffs multiply haste and cancel from the haste gain
// (docs/COMBAT-LOG-WEIGHTS.md §6): recorded, never valued.
const HASTE_PERCENT_BUFFS = Object.freeze({
    378989: "Lycara's Teachings (caster form)",
    1243972: 'Void-touched Drums',
});

// Buffs on the player that raise her healing by a percent of its amount and
// move no stat: tracked so probe.js compares ticks only under the same ones,
// never valued. Genesis 1302255, "Add Percent Modifier (108): Spell Periodic
// Amount", Base Value 15.
const AMOUNT_BUFFS = Object.freeze({ 1302255: 'Genesis' });

// Every buff on the player the tracker follows.
function tracked(id) {
    return Boolean(PERCENT_BUFFS[id] || UNSIZED_BUFFS[id] || HASTE_PERCENT_BUFFS[id] || AMOUNT_BUFFS[id]);
}

// Harmony's tracker (lib/attribute.js's mastery contract): the player's own
// Harmony-granting auras, counted per target, from the COMBATANT_INFO resync
// and the live aura events - exactly what walk() used to do inline.
function createTracker(player) {
    const harmony = new Map(); // target GUID -> Set of the player's Harmony spell IDs on it
    const diag = { unseenRemovals: 0, resyncAdded: 0, resyncDropped: 0 };

    const harmonyOf = (unit) => {
        let s = harmony.get(unit);
        if (!s) harmony.set(unit, (s = new Set()));
        return s;
    };

    return {
        // ci: a parsed COMBATANT_INFO, of any unit - Harmony is tracked on
        // every unit the player might have it on, not only herself.
        onCombatantInfo(ci) {
            const listed = new Set(ci.auras.filter((a) => a.caster === player && HARMONY.has(a.spellId)).map((a) => a.spellId));
            const known = harmonyOf(ci.guid);
            for (const id of listed) if (!known.has(id)) diag.resyncAdded += 1;
            for (const id of known) if (!listed.has(id)) diag.resyncDropped += 1;
            harmony.set(ci.guid, listed);
        },
        // a: a parsed aura event; kind: the raw event name (APPLIED/REMOVED/REFRESH).
        onAura(a, kind) {
            if (a.src !== player || !HARMONY.has(a.spellId)) return;
            const s = harmonyOf(a.dst);
            if (kind === 'SPELL_AURA_APPLIED') s.add(a.spellId);
            else if (kind === 'SPELL_AURA_REMOVED') {
                if (!s.delete(a.spellId)) diag.unseenRemovals += 1;
            } else s.add(a.spellId);
        },
        onUnitDied(guid) {
            harmony.delete(guid);
        },
        diag() {
            return { ...diag };
        },
        // Not part of lib/attribute.js's mastery contract: gain() below (in
        // this same module) and walk()'s onHeal diagnostic callback (kept
        // for lib/probe.js, unchanged) both need the player's current count
        // on one target.
        countFor(target) {
            const s = harmony.get(target);
            return s ? s.size : 0;
        },
    };
}

// E: this heal's effective amount. pct: percents() of attribute.js - reads
// pct.masteryPoints. tracker: this spec's own, from createTracker above.
// dst: the heal's target. C: the spec's constants (opts.constants merged
// over them).
function gain(E, pct, tracker, dst, C) {
    const n = tracker.countFor(dst);
    if (!(n > 0)) return 0;
    const T = stackFactor(n);
    const c = C.harmonyCoefficient / 100;
    const points = C.masteryBase + pct.masteryPoints;
    return (E * c * T) / (1 + points * c * T);
}

module.exports = {
    identity: Object.freeze({
        specID: 105,
        name: 'Restoration',
        role: 'HEALER',
        primaryStat: 'int',
        stats: Object.freeze(['int', 'haste', 'crit', 'mastery', 'vers', 'leech']),
    }),
    spellRow,
    ROWS,
    UNKNOWN,
    constants: CONSTANTS,
    buffs: Object.freeze({ percent: PERCENT_BUFFS, unsized: UNSIZED_BUFFS, hastePercent: HASTE_PERCENT_BUFFS, amount: AMOUNT_BUFFS, tracked }),
    mastery: Object.freeze({ createTracker, gain }),

    // Legacy flat names, for lib/spells.js's one-line re-export (Decision 4,
    // WKE-713): test/spells.test.js, test/probe.test.js, lib/probe.js and
    // probe.js keep reading these exact names, unchanged.
    AMOUNT_BUFFS,
    tracked,
    SPELLS,
    HARMONY_IDS,
    HARMONY,
    STACKS,
    stackFactor,
    CONSTANTS,
    PERCENT_BUFFS,
    UNSIZED_BUFFS,
    HASTE_PERCENT_BUFFS,
};
