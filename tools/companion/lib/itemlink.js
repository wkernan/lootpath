// The item link reader, in JavaScript. It is the same field layout
// Lootpath/Core.lua's ns.ParseItemLink walks, and the two must not drift: the
// addon's is the one that decides an item key, this one only builds SimC text.
//
// One deliberate difference. ns.ParseItemLink SORTS bonus IDs, because an item
// key has to be stable whichever order the client hands them over. A SimC line
// carries them in LINK order, which is what the SimulationCraft addon writes
// and what spec/fixtures/simc/hotornot-20260907.txt shows, so this reader keeps
// the order and offers `bonusIDsSorted` beside it for anyone who needs the key.
'use strict';

// Field positions inside `item:...` (Core.lua:178-230, read from the 2026-09-05
// transcript rather than from documentation):
//   1 itemID, 2 enchantID, 3..6 gems, 13 numBonusIDs, then that many bonus IDs,
//   then numModifiers and that many (type, value) pairs.
function parseItemLink(link) {
    if (typeof link !== 'string') return null;
    const body = link.match(/\|Hitem:([^|]+)\|h/) || link.match(/^item:([^|]+)$/);
    if (!body) return null;
    // Crafted items carry the crafter's GUID (`Player-69-0F82625A`) in a
    // trailing field, so a non-numeric field reads as 0 rather than failing.
    const fields = body[1].split(':').map((f) => {
        const n = Number(f);
        return Number.isFinite(n) && f !== '' ? n : 0;
    });
    const at = (i) => fields[i - 1] || 0;
    const itemID = at(1);
    if (!itemID || itemID <= 0) return null;

    const numBonus = at(13);
    const bonusIDs = [];
    for (let i = 1; i <= numBonus; i++) {
        const id = at(13 + i);
        if (id) bonusIDs.push(id);
    }
    const gems = [];
    for (let i = 3; i <= 6; i++) {
        if (at(i)) gems.push(at(i));
    }
    const modIndex = 13 + numBonus + 1;
    const numModifiers = at(modIndex);
    const modifiers = [];
    for (let i = 1; i <= numModifiers; i++) {
        const base = modIndex + (i - 1) * 2;
        modifiers.push({ type: at(base + 1), value: at(base + 2) });
    }
    const enchantID = at(2) || null;
    return {
        itemID,
        enchantID,
        gems,
        bonusIDs,
        bonusIDsSorted: bonusIDs.slice().sort((a, b) => a - b),
        modifiers,
        key: bonusIDs.length
            ? `${itemID}:${bonusIDs
                  .slice()
                  .sort((a, b) => a - b)
                  .join(':')}`
            : String(itemID),
    };
}

module.exports = { parseItemLink };
