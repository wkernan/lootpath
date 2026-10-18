'use strict';

// The parser over the committed fixture: every field position the tool reads,
// and every count spec/fixtures/combatlog/README.md records, read from the
// README itself so the two cannot drift apart silently.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const P = require('../lib/parse');

const DIR = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'combatlog');
const FIXTURE = path.join(DIR, 'WoWCombatLog-20261017-AltarOfFangs-12.txt.gz');
const README = fs.readFileSync(path.join(DIR, 'README.md'), 'utf8');
const OWNER = 'Player-69-0CC01A11';

const text = P.readText(FIXTURE);
const events = P.parseText(text);

// "`SPELL_HEAL` 16,815" -> 16815, from the README's Counts bullet.
function readmeCount(label) {
    const m = new RegExp('`' + label + '`\\s+([\\d,]+)').exec(README);
    assert.ok(m, `the README names no count for ${label}`);
    return Number(m[1].replace(/,/g, ''));
}
const count = (name) => events.filter((e) => e.event === name).length;

test("the gzip unpacks to the README's stripped text: sha256 and line count", () => {
    const sha = crypto.createHash('sha256').update(text, 'utf8').digest('hex');
    const m = /stripped plain text `([0-9a-f]{64})`/.exec(README);
    assert.equal(sha, m[1]);
    const lines = /([\d,]+) lines in and out/.exec(README);
    assert.equal(events.length, Number(lines[1].replace(/,/g, '')));
});

test("every event count the README records, as the parser counts it", () => {
    for (const name of ['SPELL_HEAL', 'SPELL_PERIODIC_HEAL', 'SPELL_ABSORBED', 'SPELL_AURA_APPLIED', 'SPELL_AURA_REFRESH', 'SPELL_AURA_REMOVED', 'SPELL_CAST_SUCCESS', 'COMBATANT_INFO', 'UNIT_DIED']) {
        assert.equal(count(name), readmeCount(name), name);
    }
    assert.equal(count('ENCOUNTER_START'), 3);
    assert.equal(count('ENCOUNTER_END'), 3);
    assert.deepEqual(events.filter((e) => e.event === 'ENCOUNTER_START').map((e) => P.encounterOf(e).name), ["Rav'i", 'The Writhing Coil', "Zul'jan"]);
});

test("the owner's heal events: total, with overheal, critical - the README's figures", () => {
    const heals = events.filter((e) => P.isHeal(e)).map(P.healOf).filter((h) => h.src === OWNER);
    const m = /The owner's heal events:\s+([\d,]+), of which ([\d,]+) carry overheal > 0 and ([\d,]+) the crit flag/.exec(README.replace(/\s+/g, ' '));
    assert.ok(m, 'the README sentence on the owner heal events');
    const n = (s) => Number(s.replace(/,/g, ''));
    assert.equal(heals.length, n(m[1]));
    assert.equal(heals.filter((h) => h.overheal > 0).length, n(m[2]));
    assert.equal(heals.filter((h) => h.critical).length, n(m[3]));
});

test('a heal has 36 fields; the critical field is 1 or nil; amount includes the overheal', () => {
    let full = 0;
    for (const e of events) {
        if (!P.isHeal(e)) continue;
        assert.equal(e.f.length, P.HEAL_FIELDS, e.stamp);
        assert.ok(e.f[P.F.CRITICAL] === '1' || e.f[P.F.CRITICAL] === 'nil', e.stamp);
        const h = P.healOf(e);
        assert.ok(h.overheal <= h.amount, `${e.stamp}: overheal above amount`);
        // A target at full health in the advanced block (hp == max hp, the
        // advanced block describes the TARGET of a heal): amount = overheal.
        if (e.f[P.F.ADV_UNIT] === h.dst && e.f[14] === e.f[15] && h.amount > 0 && h.amount === h.baseAmount) {
            if (h.overheal === h.amount) full += 1;
        }
    }
    assert.ok(full > 1000, `heals on a target at full health read amount = overheal: ${full}`);
    // Her first direct heal of the key: a target at full health.
    const first = P.healOf(events.find((e) => e.event === 'SPELL_HEAL' && e.f[P.F.SRC] === OWNER));
    assert.deepEqual([first.spellName, first.amount, first.baseAmount, first.overheal, first.critical], ['Thriving Vegetation', 14133, 14133, 14133, false]);
});

test("the advanced block: a heal's unit is the target, a cast's the caster; her spell power is her Intellect", () => {
    const heal = events.find((e) => P.isHeal(e) && e.f[P.F.SRC] === OWNER && e.f[P.F.DST] !== OWNER);
    assert.equal(heal.f[P.F.ADV_UNIT], heal.f[P.F.DST]);
    const casts = events.filter((e) => e.event === 'SPELL_CAST_SUCCESS' && e.f[P.F.SRC] === OWNER);
    assert.ok(casts.length > 0);
    for (const c of casts) {
        assert.equal(c.f.length, P.CAST_FIELDS, c.stamp);
        assert.equal(c.f[P.F.ADV_UNIT], OWNER, c.stamp);
    }
    const ci = P.combatantOf(events.find((e) => e.event === 'COMBATANT_INFO' && e.f[1] === OWNER));
    assert.equal(P.advancedOf(casts[0]).spellPower, ci.int);
    assert.equal(P.advancedOf(casts[0]).armor, ci.armor);
    const readings = new Set(events.map(P.advancedOf).filter((a) => a && a.unit === OWNER).map((a) => a.spellPower));
    assert.deepEqual([...readings].sort((a, b) => a - b), [3076, 3093, 3111, 3127]);
});

test("COMBATANT_INFO: the owner's stats at the positions read, the aura list at field 29", () => {
    const lines = events.filter((e) => e.event === 'COMBATANT_INFO');
    const owner = lines.filter((e) => e.f[1] === OWNER).map(P.combatantOf);
    assert.equal(owner.length, 4);
    for (const ci of owner) {
        assert.deepEqual(
            [ci.str, ci.agi, ci.sta, ci.int, ci.crit, ci.speed, ci.leech, ci.haste, ci.avoidance, ci.mastery, ci.vers, ci.armor, ci.spec],
            [268, 622, 37454, 3076, [427, 427, 427], 0, 302, [1000, 1000, 1000], 77, 1082, [323, 323, 323], 1028, 105]
        );
        assert.equal(ci.auras[0].caster, OWNER);
    }
    // Every player's crit, haste and versatility triples are equal in every line.
    for (const e of lines) {
        const ci = P.combatantOf(e);
        for (const k of ['crit', 'haste', 'vers']) assert.equal(new Set(ci[k]).size, 1, `${ci.guid} ${k}`);
        assert.match(e.f[P.CI.AURAS], /^\[.*\]$/);
    }
    // One line per player at the key's start and at each boss.
    assert.equal(new Set(lines.map((e) => e.f[1])).size, 5);
});

test('CHALLENGE_MODE_START and _END carry the key level; the key was timed', () => {
    const start = P.challengeStartOf(events.find((e) => e.event === 'CHALLENGE_MODE_START'));
    assert.deepEqual([start.zone, start.instanceId, start.level], ['Altar of Fangs', 2993, 12]);
    const end = P.challengeEndOf(events.find((e) => e.event === 'CHALLENGE_MODE_END'));
    assert.deepEqual([end.success, end.level, end.durationMs], [true, 12, 1218077]);
});

test('the field splitter keeps quoted commas and nested lists whole', () => {
    assert.deepEqual(P.splitFields('A,"b, c",[1,(2,3)],(4,5),nil'), ['A', '"b, c"', '[1,(2,3)]', '(4,5)', 'nil']);
    assert.throws(() => P.splitFields('A,"open'), /unbalanced/);
});
