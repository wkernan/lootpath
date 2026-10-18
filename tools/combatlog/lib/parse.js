// The WoWCombatLog.txt reader (E-5, WKE-711; docs/COMBAT-LOG-WEIGHTS.md §1).
//
// Field positions are the ones read from the committed fixture
// (spec/fixtures/combatlog/WoWCombatLog-20261017-AltarOfFangs-12.txt.gz) with
// Advanced Combat Logging on, COMBAT_LOG_VERSION 22, build 12.1.5 - not a
// wiki's. test/parse.test.js holds every position against that file. Indices
// below count the event name as field 0.
'use strict';

const fs = require('fs');
const zlib = require('zlib');

// A heal (SPELL_HEAL, SPELL_PERIODIC_HEAL) has 36 fields: 9 base (event name
// included), 3 spell, 19 advanced, 5 suffix.
const F = Object.freeze({
    SRC: 1,
    SRC_NAME: 2,
    SRC_FLAGS: 3,
    DST: 5,
    DST_NAME: 6,
    SPELL_ID: 9,
    SPELL_NAME: 10,
    // The advanced block of a SPELL_* event: its unit (for a heal, the TARGET;
    // for a cast, the CASTER), and that unit's spell power.
    ADV_UNIT: 12,
    ADV_SPELL_POWER: 17,
    ADV_ARMOR: 18,
    ADV_LENGTH: 19,
    AMOUNT: 31,
    BASE_AMOUNT: 32,
    OVERHEAL: 33,
    ABSORBED: 34,
    CRITICAL: 35,
});
const HEAL_FIELDS = 36;
const CAST_FIELDS = 31; // SPELL_CAST_SUCCESS: 12 + the advanced block

// COMBATANT_INFO, after the GUID (1) and a faction field (2): strength,
// agility, stamina, intellect (3-6), four fields (7-10), crit x3 (11-13),
// speed (14), leech (15), haste x3 (16-18), avoidance (19), mastery (20),
// versatility x3 (21-23), armour (24), spec (25), then the bracketed lists:
// talents (26), a parenthesised group (27), gear (28), auras (29) as
// caster, spellID, count triples.
const CI = Object.freeze({
    GUID: 1,
    STR: 3,
    AGI: 4,
    STA: 5,
    INT: 6,
    CRIT: [11, 12, 13],
    SPEED: 14,
    LEECH: 15,
    HASTE: [16, 17, 18],
    AVOIDANCE: 19,
    MASTERY: 20,
    VERS: [21, 22, 23],
    ARMOR: 24,
    SPEC: 25,
    AURAS: 29,
});

// SPELL_* events that carry the advanced block at F.ADV_UNIT. Only these are
// read for a spell-power (Intellect) reading.
const ADVANCED_EVENTS = new Set(['SPELL_CAST_SUCCESS', 'SPELL_HEAL', 'SPELL_PERIODIC_HEAL', 'SPELL_DAMAGE', 'SPELL_PERIODIC_DAMAGE', 'SPELL_ENERGIZE', 'SPELL_PERIODIC_ENERGIZE']);

// Split the part after the two spaces at commas outside quotes and outside
// any () or [] nesting. Quotes are kept on a quoted field (so `nil` and
// `"nil"` stay apart); unquote() strips them.
function splitFields(body) {
    const out = [];
    let depth = 0;
    let quoted = false;
    let start = 0;
    for (let i = 0; i < body.length; i++) {
        const c = body.charCodeAt(i);
        if (quoted) {
            if (c === 34 /* " */) quoted = false;
            continue;
        }
        if (c === 34) quoted = true;
        else if (c === 40 /* ( */ || c === 91 /* [ */) depth++;
        else if (c === 41 /* ) */ || c === 93 /* ] */) depth--;
        else if (c === 44 /* , */ && depth === 0) {
            out.push(body.slice(start, i));
            start = i + 1;
        }
    }
    if (quoted || depth !== 0) throw new Error(`unbalanced line: ${body.slice(0, 120)}`);
    out.push(body.slice(start));
    return out;
}

function unquote(s) {
    return s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"' ? s.slice(1, -1) : s;
}

// "10/17/2026 21:56:14.468-5" -> epoch milliseconds (the offset is hours
// from UTC). Only differences are ever used.
const TIME = /^(\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+)\.(\d+)([+-]\d+)?$/;
function parseTime(stamp) {
    const m = TIME.exec(stamp);
    if (!m) throw new Error(`not a timestamp: ${stamp}`);
    const ms = Date.UTC(+m[3], +m[1] - 1, +m[2], +m[4], +m[5], +m[6], +m[7].padEnd(3, '0').slice(0, 3));
    return ms - (m[8] ? +m[8] * 3600000 : 0);
}

// One line -> { t, stamp, event, f } or null for a blank line.
function parseLine(line) {
    if (!line) return null;
    const cut = line.indexOf('  ');
    if (cut < 0) throw new Error(`no two-space separator: ${line.slice(0, 120)}`);
    const stamp = line.slice(0, cut);
    const f = splitFields(line.slice(cut + 2));
    return { t: parseTime(stamp), stamp, event: f[0], f };
}

// The text of a log, gunzipped when the file is gzip (by its magic bytes).
function readText(file) {
    const buf = fs.readFileSync(file);
    const plain = buf.length > 2 && buf[0] === 0x1f && buf[1] === 0x8b ? zlib.gunzipSync(buf) : buf;
    return plain.toString('utf8');
}

function lines(text) {
    const out = text.split('\n');
    for (let i = 0; i < out.length; i++) if (out[i].endsWith('\r')) out[i] = out[i].slice(0, -1);
    if (out.length && out[out.length - 1] === '') out.pop();
    return out;
}

// Every event of a log text, in order.
function parseText(text) {
    return lines(text).map(parseLine).filter(Boolean);
}

const num = (s) => {
    const v = Number(s);
    if (!Number.isFinite(v)) throw new Error(`not a number: ${s}`);
    return v;
};

function isHeal(ev) {
    return ev.event === 'SPELL_HEAL' || ev.event === 'SPELL_PERIODIC_HEAL';
}

// A heal's numbers. Amount INCLUDES the overheal (a heal on a target at full
// health reads amount = overheal; test/parse.test.js shows it on the
// fixture), so effective = amount - overheal.
function healOf(ev) {
    const f = ev.f;
    if (f.length !== HEAL_FIELDS) throw new Error(`${ev.event} with ${f.length} fields at ${ev.stamp}, expected ${HEAL_FIELDS}`);
    const amount = num(f[F.AMOUNT]);
    const overheal = num(f[F.OVERHEAL]);
    return {
        src: f[F.SRC],
        srcFlags: parseInt(f[F.SRC_FLAGS], 16),
        dst: f[F.DST],
        spellId: num(f[F.SPELL_ID]),
        spellName: unquote(f[F.SPELL_NAME]),
        periodic: ev.event === 'SPELL_PERIODIC_HEAL',
        amount,
        baseAmount: num(f[F.BASE_AMOUNT]),
        overheal,
        absorbed: num(f[F.ABSORBED]),
        effective: amount - overheal,
        critical: f[F.CRITICAL] === '1',
    };
}

// The advanced block's unit and its spell power, or null.
function advancedOf(ev) {
    if (!ADVANCED_EVENTS.has(ev.event)) return null;
    const f = ev.f;
    if (f.length < F.ADV_UNIT + F.ADV_LENGTH) return null;
    return { unit: f[F.ADV_UNIT], spellPower: num(f[F.ADV_SPELL_POWER]), armor: num(f[F.ADV_ARMOR]) };
}

// "[a,b,c,d,e,f]" -> [{ caster, spellId, count }, ...]
function auraList(field) {
    const inner = field.replace(/^\[/, '').replace(/\]$/, '');
    if (!inner) return [];
    const parts = inner.split(',');
    if (parts.length % 3 !== 0) throw new Error(`COMBATANT_INFO aura list not in triples: ${field.slice(0, 80)}`);
    const out = [];
    for (let i = 0; i < parts.length; i += 3) out.push({ caster: parts[i], spellId: num(parts[i + 1]), count: num(parts[i + 2]) });
    return out;
}

function combatantOf(ev) {
    const f = ev.f;
    const triple = (idx) => idx.map((i) => num(f[i]));
    return {
        guid: f[CI.GUID],
        str: num(f[CI.STR]),
        agi: num(f[CI.AGI]),
        sta: num(f[CI.STA]),
        int: num(f[CI.INT]),
        crit: triple(CI.CRIT),
        speed: num(f[CI.SPEED]),
        leech: num(f[CI.LEECH]),
        haste: triple(CI.HASTE),
        avoidance: num(f[CI.AVOIDANCE]),
        mastery: num(f[CI.MASTERY]),
        vers: triple(CI.VERS),
        armor: num(f[CI.ARMOR]),
        spec: num(f[CI.SPEC]),
        auras: auraList(f[CI.AURAS]),
    };
}

function auraOf(ev) {
    const f = ev.f;
    return { src: f[F.SRC], dst: f[F.DST], spellId: num(f[F.SPELL_ID]), spellName: unquote(f[F.SPELL_NAME]), kind: f[12] };
}

// SPELL_ABSORBED: the absorbing aura's caster sits 4 fields before the end
// (caster GUID, name, flags, raid flags, spell ID, name, school, amount,
// total, critical). A melee absorb has no attacking spell, so it is read
// from the end.
function absorbOf(ev) {
    const f = ev.f;
    const n = f.length;
    return { caster: f[n - 10], spellId: num(f[n - 6]), spellName: unquote(f[n - 5]), amount: num(f[n - 3]) };
}

function challengeStartOf(ev) {
    return { zone: unquote(ev.f[1]), instanceId: num(ev.f[2]), level: num(ev.f[4]) };
}

function challengeEndOf(ev) {
    return { instanceId: num(ev.f[1]), success: ev.f[2] === '1', level: num(ev.f[3]), durationMs: num(ev.f[4]) };
}

function encounterOf(ev) {
    return { id: num(ev.f[1]), name: unquote(ev.f[2]), difficulty: num(ev.f[3]), size: num(ev.f[4]), instanceId: num(ev.f[5]), kill: ev.event === 'ENCOUNTER_END' ? ev.f[6] === '1' : undefined };
}

// The source flags of a guardian or pet of the logging player: affiliation
// "mine" (0x1), and type guardian (0x2000) or pet (0x1000).
function isMyGuardian(flags) {
    return (flags & 0x1) === 0x1 && (flags & 0x3000) !== 0;
}

module.exports = {
    F,
    CI,
    HEAL_FIELDS,
    CAST_FIELDS,
    ADVANCED_EVENTS,
    splitFields,
    unquote,
    parseTime,
    parseLine,
    readText,
    lines,
    parseText,
    isHeal,
    healOf,
    advancedOf,
    auraList,
    combatantOf,
    auraOf,
    absorbOf,
    challengeStartOf,
    challengeEndOf,
    encounterOf,
    isMyGuardian,
};
