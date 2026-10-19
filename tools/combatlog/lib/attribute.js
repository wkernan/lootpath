// The stat tracker and the per-event attribution (E-5, WKE-711; E-5b,
// WKE-713; docs/COMBAT-LOG-WEIGHTS.md §2, §3, §6, §7).
//
// walk(events, opts) reads a parsed log once, in order, and returns its
// segments, each with the sums the estimate needs: per stat, how much more
// effective healing the player's heals would have done with one more percent
// of it (one more point, for Intellect). No estimate here: lib/estimate.js
// turns segments into a band's weights.
//
// Which spell moves which stat, and by how much, is read from the found
// player's own spec module (specs/index.js), not assumed: this file knows no
// spec's spells, buffs or constants by name, only the shape every spec
// module shares.
'use strict';

const P = require('./parse');
const { SPECS } = require('../specs');
const { ratingToPercent, slope } = require('./dr');

// Healing specs the tool knows, by the client's spec ID.
const HEALER_SPECS = new Set(SPECS.keys());
const GAINS = ['int', 'vers', 'crit', 'hasteTick', 'hasteCast', 'mastery'];

// The one GUID whose COMBATANT_INFO names a known healing spec.
function findPlayer(events) {
    const found = new Set();
    for (const ev of events) {
        if (ev.event !== 'COMBATANT_INFO') continue;
        const ci = P.combatantOf(ev);
        if (HEALER_SPECS.has(ci.spec)) found.add(ci.guid);
    }
    if (found.size !== 1) throw new Error(`name the player with --player: ${found.size} players in this log carry a healing spec the tool knows (${[...found].join(', ') || 'none'})`);
    return [...found][0];
}

// The player's spec ID, read from her own COMBATANT_INFO. Resolved once, up
// front, so every unit's Harmony-aura tracking has her spec module from the
// log's first COMBATANT_INFO batch - a raid lists every member's in one
// batch, in no guaranteed order, and Harmony's count is tracked for them all,
// not only the player.
function findPlayerSpec(events, player) {
    for (const ev of events) {
        if (ev.event !== 'COMBATANT_INFO') continue;
        const ci = P.combatantOf(ev);
        if (ci.guid === player) return ci.spec;
    }
    throw new Error(`no COMBATANT_INFO names ${player}'s spec`);
}

function emptySums() {
    return {
        events: 0,
        raw: 0,
        overheal: 0,
        effective: 0,
        overhealEvents: 0,
        leechEvents: 0,
        leechEffective: 0,
        gain: Object.fromEntries(GAINS.map((k) => [k, 0])),
        bySpell: {},
        unknown: {},
        unsized: {},
        guardianEvents: 0,
        guardianEffective: 0,
        absorbEvents: 0,
        absorbed: 0,
    };
}

function walk(events, opts) {
    const o = opts || {};
    const dr = o.dr;
    if (!dr) throw new Error('walk needs the dr table');
    const player = o.player || findPlayer(events);
    const specID = findPlayerSpec(events, player);
    const specModule = SPECS.get(specID);
    if (!specModule) throw new Error(`spec ${specID} has no combat-log module (specs/index.js)`);
    const C = { ...specModule.CONSTANTS, ...(o.constants || {}) };

    let ratings = null; // { crit, haste, mastery, vers, leech } from COMBATANT_INFO
    let ciInt = null;
    let intNow = null;
    const buffs = new Set(); // spell IDs on the player that the tracker knows
    const harmony = new Map(); // target -> Set of Harmony spell IDs of the player's
    const diag = { unseenRemovals: 0, resyncAdded: 0, resyncDropped: 0, intReadings: 0, intValues: new Set(), outsideSegments: 0, emptySegments: 0, combatantInfo: 0, ratingsChangedInSegment: 0 };

    const keys = [];
    const segments = [];
    let key = null;
    let seg = null;

    const open = (kind, name, t, extra) => {
        seg = { kind, name, start: t, end: null, ratings: null, int: null, spec: null, sums: emptySums(), ...extra };
    };
    const close = (t) => {
        if (!seg) return;
        seg.end = t;
        if (seg.sums.events > 0) segments.push(seg);
        else diag.emptySegments += 1;
        seg = null;
    };

    const harmonyOf = (unit) => {
        let s = harmony.get(unit);
        if (!s) harmony.set(unit, (s = new Set()));
        return s;
    };

    for (const ev of events) {
        const e = ev.event;
        if (e === 'CHALLENGE_MODE_START') {
            close(ev.t);
            const cs = P.challengeStartOf(ev);
            key = { zone: cs.zone, instanceId: cs.instanceId, level: cs.level, start: ev.t, end: null, success: null, durationMs: null };
            keys.push(key);
            open('trash', `${cs.zone} +${cs.level} trash`, ev.t, { contentType: 'Dungeon', band: String(cs.level), key });
            continue;
        }
        if (e === 'CHALLENGE_MODE_END') {
            close(ev.t);
            if (key) {
                const ce = P.challengeEndOf(ev);
                key.end = ev.t;
                key.success = ce.success;
                key.durationMs = ce.durationMs;
            }
            key = null;
            continue;
        }
        if (e === 'ENCOUNTER_START') {
            close(ev.t);
            const en = P.encounterOf(ev);
            if (key) open('boss', en.name, ev.t, { contentType: 'Dungeon', band: String(key.level), key, encounterId: en.id });
            else if (en.size > 5) open('boss', en.name, ev.t, { contentType: 'Raid', band: 'all', key: null, encounterId: en.id, difficulty: en.difficulty });
            continue;
        }
        if (e === 'ENCOUNTER_END') {
            const en = P.encounterOf(ev);
            if (seg && seg.kind === 'boss') seg.kill = en.kill;
            close(ev.t);
            if (key) open('trash', `${key.zone} +${key.level} trash`, ev.t, { contentType: 'Dungeon', band: String(key.level), key });
            continue;
        }
        if (e === 'COMBATANT_INFO') {
            diag.combatantInfo += 1;
            const ci = P.combatantOf(ev);
            // Harmony's count on this unit, from the auras the client listed.
            const listed = new Set(ci.auras.filter((a) => a.caster === player && specModule.HARMONY.has(a.spellId)).map((a) => a.spellId));
            const known = harmonyOf(ci.guid);
            for (const id of listed) if (!known.has(id)) diag.resyncAdded += 1;
            for (const id of known) if (!listed.has(id)) diag.resyncDropped += 1;
            harmony.set(ci.guid, listed);
            if (ci.guid === player) {
                const next = { crit: ci.crit[2], haste: ci.haste[2], mastery: ci.mastery, vers: ci.vers[1], leech: ci.leech };
                if (seg && seg.ratings && JSON.stringify(seg.ratings) !== JSON.stringify(next)) diag.ratingsChangedInSegment += 1;
                ratings = next;
                ciInt = ci.int;
                if (intNow === null) intNow = ci.int;
                // The player's own buffs, as listed.
                buffs.clear();
                for (const a of ci.auras) if (specModule.tracked(a.spellId)) buffs.add(a.spellId);
            }
            continue;
        }

        const adv = P.advancedOf(ev);
        if (adv && adv.unit === player) {
            intNow = adv.spellPower;
            diag.intReadings += 1;
            diag.intValues.add(adv.spellPower);
        }

        if (e === 'SPELL_AURA_APPLIED' || e === 'SPELL_AURA_REMOVED' || e === 'SPELL_AURA_REFRESH') {
            const a = P.auraOf(ev);
            if (a.src === player && specModule.HARMONY.has(a.spellId)) {
                const s = harmonyOf(a.dst);
                if (e === 'SPELL_AURA_APPLIED') s.add(a.spellId);
                else if (e === 'SPELL_AURA_REMOVED') {
                    if (!s.delete(a.spellId)) diag.unseenRemovals += 1;
                } else s.add(a.spellId);
            }
            if (a.dst === player && specModule.tracked(a.spellId)) {
                if (e === 'SPELL_AURA_REMOVED') buffs.delete(a.spellId);
                else buffs.add(a.spellId);
            }
            continue;
        }
        if (e === 'UNIT_DIED') {
            harmony.delete(ev.f[5]);
            continue;
        }
        if (e === 'SPELL_ABSORBED') {
            const ab = P.absorbOf(ev);
            if (ab.caster === player && seg) {
                seg.sums.absorbEvents += 1;
                seg.sums.absorbed += ab.amount;
            }
            continue;
        }
        if (!P.isHeal(ev)) continue;
        const h = P.healOf(ev);
        if (h.src !== player) {
            if (seg && P.isMyGuardian(h.srcFlags)) {
                seg.sums.guardianEvents += 1;
                seg.sums.guardianEffective += h.effective;
            }
            continue;
        }
        if (!seg) {
            diag.outsideSegments += 1;
            continue;
        }
        if (!ratings) throw new Error(`a heal of the player's at ${ev.stamp} before any COMBATANT_INFO of hers`);
        if (!seg.ratings) {
            seg.ratings = { ...ratings };
            seg.int = ciInt;
            seg.spec = specID;
        }
        const hs = harmony.get(h.dst);
        attribute(seg.sums, h, { ratings, intNow, buffs, harmony: hs, dr, C, spec: specModule });
        if (o.onHeal) o.onHeal(h, { t: ev.t, intNow, n: hs ? hs.size : 0, buffs: [...buffs].sort((a, b) => a - b).join(','), ratings, seg, spec: specModule });
    }
    close(events.length ? events[events.length - 1].t : 0);
    diag.intValues = [...diag.intValues].sort((a, b) => a - b);
    return { player, keys, segments, diag };
}

// The player's percents at this moment.
function percents(ratings, buffs, dr, spec) {
    let versBuff = 0;
    for (const id of buffs) if (spec.PERCENT_BUFFS[id] && spec.PERCENT_BUFFS[id].stat === 'vers') versBuff += spec.PERCENT_BUFFS[id].percent;
    return {
        vers: ratingToPercent(ratings.vers, dr.vers) + versBuff,
        haste: ratingToPercent(ratings.haste, dr.haste),
        masteryPoints: ratingToPercent(ratings.mastery, dr.mastery),
        leech: ratingToPercent(ratings.leech, dr.leech),
    };
}

// One heal event of the player's into a segment's sums (§6).
function attribute(sums, h, ctx) {
    const { ratings, intNow, buffs, dr, C, spec } = ctx;
    const row = spec.spellRow(h.spellId);
    sums.events += 1;
    sums.raw += h.amount;
    sums.overheal += h.overheal;
    sums.effective += h.effective;
    const by = (sums.bySpell[h.spellId] = sums.bySpell[h.spellId] || { name: h.spellName, events: 0, effective: 0, overheal: 0 });
    by.events += 1;
    by.effective += h.effective;
    by.overheal += h.overheal;
    if (row.kind === 'unknown') sums.unknown[h.spellId] = (sums.unknown[h.spellId] || 0) + h.effective;
    for (const id of buffs) if (spec.UNSIZED_BUFFS[id]) sums.unsized[id] = (sums.unsized[id] || 0) + h.effective;

    if (row.kind === 'leech') {
        sums.leechEvents += 1;
        sums.leechEffective += h.effective;
        return;
    }
    // The overheal rule: an event that overhealed at all is worth nothing.
    if (h.overheal > 0) {
        sums.overhealEvents += 1;
        return;
    }
    const E = h.effective;
    const pct = percents(ratings, buffs, dr, spec);
    const g = sums.gain;
    if (row.int) g.int += E / intNow;
    if (row.vers) g.vers += E / (1 + pct.vers / 100) / 100;
    if (row.crit === 'all' || (row.crit === 'direct' && !h.periodic)) {
        const base = h.critical ? h.amount / C.critMultiplier : h.amount;
        g.crit += (base * (C.critMultiplier - 1)) / 100;
    }
    const tick = row.tick === 'all' || (row.tick === 'periodic' && h.periodic);
    if (tick) g.hasteTick += E / (1 + pct.haste / 100) / 100;
    if (tick || row.cast) g.hasteCast += E / (1 + pct.haste / 100) / 100;
    if (row.mastery) {
        const n = ctx.harmony ? ctx.harmony.size : 0;
        if (n > 0) {
            const T = spec.stackFactor(n);
            const c = C.harmonyCoefficient / 100;
            const points = C.masteryBase + pct.masteryPoints;
            g.mastery += (E * c * T) / (1 + points * c * T);
        }
    }
}

// A segment's weights: per percent (per point for Intellect), per rating
// point, and per rating point relative to Intellect's per point (§7).
function segmentWeights(seg, dr) {
    const s = seg.sums;
    const r = seg.ratings;
    const leechPct = ratingToPercent(r.leech, dr.leech);
    const perPercent = {
        int: s.gain.int,
        haste: s.gain.hasteTick,
        hasteCast: s.gain.hasteCast,
        crit: s.gain.crit,
        mastery: s.gain.mastery,
        vers: s.gain.vers,
        leech: leechPct > 0 ? s.leechEffective / leechPct : null,
    };
    const slopes = { haste: slope(r.haste, dr.haste), hasteCast: slope(r.haste, dr.haste), crit: slope(r.crit, dr.crit), mastery: slope(r.mastery, dr.mastery), vers: slope(r.vers, dr.vers), leech: slope(r.leech, dr.leech) };
    const perPoint = { int: perPercent.int };
    const relative = { int: 1 };
    const relativePercent = { int: 1 };
    for (const k of Object.keys(slopes)) {
        perPoint[k] = perPercent[k] === null ? null : perPercent[k] * slopes[k];
        relative[k] = perPoint[k] === null || !(perPercent.int > 0) ? null : perPoint[k] / perPercent.int;
        relativePercent[k] = perPercent[k] === null || !(perPercent.int > 0) ? null : perPercent[k] / perPercent.int;
    }
    return { perPercent, perPoint, relative, relativePercent, slopes };
}

module.exports = { HEALER_SPECS, GAINS, findPlayer, walk, attribute, percents, segmentWeights, emptySums };
