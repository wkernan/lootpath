// Rating -> percent through Blizzard's diminishing returns, level 90.
//
// Source: maxroll.gg, "WoW Stat Diminishing Returns Summary", read 2026-09-30
// (the page says "Last Updated: March 13, 2026 for patch 12.0.1 - Midnight").
// Quoted there: Haste 44 rating for 1%, Critical Strike 46, Versatility 54,
// Mastery "Varies by specialization", Leech 69; and the brackets, e.g. Haste
// "1320 - 1760 (-10%), 1760 - 2200 (-20%), 2200 - 2640 (-30%), 2640 - 3080
// (-40%), 3080 - 8800 (-50%), >8800 (-100%)". A bracket's penalty applies to
// the rating that falls inside it. The README quotes the whole table.
//
// Mastery is NOT on the page for this spec. It is modelled with crit's rating
// per point and crit's brackets (`dr.mastery.assumed` says so); the client
// confirmed it for Restoration (below).
//
// The client answers all of this itself, and applies the brackets: the
// owner's `capture itemstats` transcript of 2026-10-01 (spec/fixtures/
// captures/Lootpath-20261001-092631.lua, E-0f) gives
// GetCombatRatingBonusForCombatRatingValue at 660..3080 and at the
// character's own rating for all five, and this table reproduces haste, crit,
// mastery and versatility to single precision and leech within 2.6e-4 (the
// client reads a constant 1.43e-5 relative below 69 per percent) - test/
// dr.test.js holds it. Mastery answered crit's figure at every point for spec
// 105. The addon converts through the client; this table stays for the
// offline fit, which has no client to ask.
'use strict';

function secondary(ratingPerPercent, start, step, cap) {
    const brackets = [];
    // -10% .. -50% in steps of `step` rating from `start`, then -100% at `cap`.
    for (let i = 0; i < 5; i++) brackets.push({ from: start + i * step, penalty: (i + 1) / 10 });
    brackets.push({ from: cap, penalty: 1 });
    return { ratingPerPercent, brackets };
}

const DEFAULT_DR = {
    source: 'maxroll.gg/wow/resources/stat-diminishing-returns, read 2026-09-30 (page: patch 12.0.1)',
    haste: secondary(44, 1320, 440, 8800),
    crit: secondary(46, 1380, 460, 9200),
    vers: secondary(54, 1620, 540, 10800),
    mastery: Object.assign(secondary(46, 1380, 460, 9200), {
        assumed: "crit's rating per point and brackets; the page says mastery varies by specialization - the 2026-10-01 transcript answered crit's figure at all seven points for spec 105",
    }),
    leech: {
        ratingPerPercent: 69,
        brackets: [
            { from: 690, penalty: 0.2 },
            { from: 1035, penalty: 0.4 },
            { from: 1380, penalty: 0.6 },
            { from: 3381, penalty: 1 },
        ],
    },
};

// Percent for a rating total. Brackets are sorted by `from`; rating below the
// first bracket counts in full.
function ratingToPercent(rating, table) {
    if (!(rating > 0)) return 0;
    let effective = 0;
    let prevFrom = 0;
    let prevPenalty = 0;
    for (const b of table.brackets) {
        if (rating <= b.from) break;
        effective += (b.from - prevFrom) * (1 - prevPenalty);
        prevFrom = b.from;
        prevPenalty = b.penalty;
    }
    effective += (rating - prevFrom) * (1 - prevPenalty);
    return effective / table.ratingPerPercent;
}

module.exports = { DEFAULT_DR, ratingToPercent };
