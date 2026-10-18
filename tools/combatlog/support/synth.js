// Builders for a tiny synthetic combat log in the fixture's own line shapes
// (36-field heals, 31-field casts, COMBATANT_INFO with the aura list at field
// 29), so the attribution can be checked by hand.
'use strict';

const PLAYER = 'Player-1-0000AAAA';
const PLAYER_NAME = 'Healer-Realm-US';
const ALLY = 'Player-2-0000BBBB';
const ALLY_NAME = 'Tankard-Other-US';

let clock = 0;
function stamp(t) {
    const ms = t === undefined ? (clock += 100) : t;
    const d = new Date(Date.UTC(2026, 9, 17, 20, 0, 0) + ms);
    const p = (n, w) => String(n).padStart(w || 2, '0');
    return `${d.getUTCMonth() + 1}/${d.getUTCDate()}/${d.getUTCFullYear()} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}.${p(d.getUTCMilliseconds(), 3)}-5`;
}
const line = (body) => `${stamp()}  ${body}`;
const adv = (unit, sp) => [unit, '0000000000000000', 100, 100, 0, sp, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0].join(',');

function heal(o) {
    const ev = o.periodic ? 'SPELL_PERIODIC_HEAL' : 'SPELL_HEAL';
    const src = o.src || PLAYER;
    const srcName = o.srcName || PLAYER_NAME;
    const dst = o.dst || ALLY;
    const dstName = o.dstName || ALLY_NAME;
    return line(`${ev},${src},"${srcName}",${o.srcFlags || '0x511'},0x80000000,${dst},"${dstName}",0x512,0x80000000,${o.spellId},"${o.name || 'Heal'}",0x8,${adv(dst, o.dstSp || (dst === PLAYER ? 1000 : 500))},${o.amount},${o.amount},${o.overheal || 0},0,${o.crit ? '1' : 'nil'}`);
}

function cast(spellId, sp, target) {
    return line(`SPELL_CAST_SUCCESS,${PLAYER},"${PLAYER_NAME}",0x511,0x80000000,${target || ALLY},"${ALLY_NAME}",0x512,0x80000000,${spellId},"Cast",0x8,${adv(PLAYER, sp)}`);
}

function aura(kind, spellId, o) {
    const x = o || {};
    return line(`SPELL_AURA_${kind},${x.src || PLAYER},"${PLAYER_NAME}",0x511,0x80000000,${x.dst || ALLY},"${x.dstName || ALLY_NAME}",0x512,0x80000000,${spellId},"Aura",0x8,BUFF`);
}

function combatant(o) {
    const auras = (o.auras || []).map((a) => `${a.caster},${a.spellId},1`).join(',');
    const t = (v) => `${v},${v},${v}`;
    return line(`COMBATANT_INFO,${o.guid || PLAYER},0,10,20,30000,${o.int},0,0,0,0,${t(o.crit)},0,${o.leech},${t(o.haste)},0,${o.mastery},${t(o.vers)},900,${o.spec || 105},[(1,2,1)],(0,0,0,0),[(0,0,(),(),())],[${auras}],1,0,0,0`);
}

const challengeStart = (level) => line(`CHALLENGE_MODE_START,"Test Grove",9999,1,${level},[10]`);
const challengeEnd = (level) => line(`CHALLENGE_MODE_END,9999,1,${level},60000,1.0,2.0`);
const encounterStart = (name) => line(`ENCOUNTER_START,1,"${name}",8,5,9999`);
const encounterEnd = (name) => line(`ENCOUNTER_END,1,"${name}",8,5,1,30000`);

function reset() {
    clock = 0;
}

module.exports = { PLAYER, PLAYER_NAME, ALLY, ALLY_NAME, heal, cast, aura, combatant, challengeStart, challengeEnd, encounterStart, encounterEnd, line, reset };
