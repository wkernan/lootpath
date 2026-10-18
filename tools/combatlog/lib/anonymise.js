// Strip every player but one from a WoWCombatLog text (E-5, WKE-711;
// docs/COMBAT-LOG-WEIGHTS.md §10). The Node port of the stripping the
// coordinator ran over the first fixture (tools/combatlog/anonymise.py, which
// this replaces), with one change: a GUID or name that maps to ITSELF (a file
// already stripped) is not "left in the output", so a second run over a
// stripped file is a no-op instead of a refusal.
//
// Every other player's GUID becomes Player-0-NNNNNNNN (numbered in the order
// of the sorted original GUIDs that carry a name; GUIDs seen only bare - a
// pet's owner in the advanced block - numbered after them), and each of
// their quoted names becomes "PlayerN-Realm" (a bare name "PlayerN"). Bare
// occurrences of a name of four or more letters inside any other text are
// replaced too (a pet named after its owner). Nothing else changes.
'use strict';

const GUID_NAME = /(Player-\d+-[0-9A-F]+),"([^"]+)"/g;
const GUID = /Player-\d+-[0-9A-F]+/g;
const pseudo = (n) => `Player-0-${String(n).padStart(8, '0')}`;

function replaceAll(text, from, to) {
    return from === to ? text : text.split(from).join(to);
}

function anonymise(text, owner) {
    if (!/^Player-\d+-[0-9A-F]+$/.test(owner || '')) throw new Error(`not a player GUID: ${owner}`);
    const names = new Map(); // guid -> Set of names
    for (const m of text.matchAll(GUID_NAME)) {
        if (m[1] === owner) continue;
        if (!names.has(m[1])) names.set(m[1], new Set());
        names.get(m[1]).add(m[2]);
    }
    const guids = new Map();
    [...names.keys()].sort().forEach((g, i) => guids.set(g, pseudo(i + 1)));
    let count = guids.size;
    for (const g of [...new Set(text.match(GUID) || [])].sort()) {
        if (g !== owner && !guids.has(g)) guids.set(g, pseudo(++count));
    }
    const nameMap = new Map();
    for (const [g, set] of names) {
        const num = guids.get(g).slice(-8).replace(/^0+/, '');
        for (const name of set) {
            nameMap.set(name, `Player${num}-Realm`);
            const bare = name.split('-')[0];
            if (!nameMap.has(bare)) nameMap.set(bare, `Player${num}`);
        }
    }
    let out = text;
    for (const [g, p] of guids) out = replaceAll(out, g, p);
    const longestFirst = [...nameMap.keys()].sort((a, b) => b.length - a.length);
    for (const name of longestFirst) out = replaceAll(out, `"${name}"`, `"${nameMap.get(name)}"`);
    for (const name of longestFirst) if (name.length >= 4) out = replaceAll(out, name, nameMap.get(name));

    const leftover = [...[...guids].filter(([g, p]) => g !== p && out.includes(g)).map(([g]) => g), ...longestFirst.filter((n) => n.length >= 4 && n !== nameMap.get(n) && out.includes(n))];
    return { text: out, players: guids.size, names: nameMap.size, leftover, guids, nameMap };
}

module.exports = { anonymise };
