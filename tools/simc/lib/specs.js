// What the runner knows about a spec before SimC runs, and how SimC's report
// words map onto Lootpath's.
//
// The specs table holds only IDs this repo can source: 102/103/104 are the
// owner's own numbers in WKE-710 ("Balance (102), Feral (103) and Guardian
// (104)"), 105 is the Restoration ID every capture fixture carries. Any other
// spec runs with `--profile <path>`: the ID is the one the caller gives, and the
// class, spec and role are read from SimC's report, never from a table here.
'use strict';

const SPECS = {
    102: { className: 'Druid', specName: 'Balance' },
    103: { className: 'Druid', specName: 'Feral' },
    104: { className: 'Druid', specName: 'Guardian' },
    // Known so it can be refused by name: SimC models no healer.
    105: { className: 'Druid', specName: 'Restoration', healer: true },
};

// SimC's `role` (the profile's `role=` line, echoed in the JSON report) to the
// client's own GetSpecializationInfo role strings, which the weights file uses.
// `heal` is refused: "Healers are not supported" (docs/OWN-ENGINE.md §2c).
const ROLE = { attack: 'DAMAGER', spell: 'DAMAGER', tank: 'TANK' };

// SimC's scale-factor keys (the report's `scale_factors` names) to Lootpath's
// stat keys, and the `scale_only=` option word that asks SimC for each.
const PRIMARY = {
    Str: { key: 'str', option: 'strength' },
    Agi: { key: 'agi', option: 'agility' },
    Int: { key: 'int', option: 'intellect' },
};
const RATINGS = {
    Haste: { key: 'haste', option: 'haste' },
    Crit: { key: 'crit', option: 'crit' },
    Mastery: { key: 'mastery', option: 'mastery' },
    Vers: { key: 'vers', option: 'versatility' },
};
// The order a spec's `stats` list is written in: the primary first, then the
// ratings in EngineScore.STATS's order (haste, crit, mastery, vers).
const RATING_ORDER = ['Haste', 'Crit', 'Mastery', 'Vers'];

// Every stat the runner asks SimC to scale. SimC scales only the ones the
// spec's own class module says it scales with, so asking for all three
// primaries costs nothing: a Feral run scales Agi and never Str or Int
// (measured on SimC 1210-01, 2026-10-15). Which primary the report carries is
// how the runner learns the spec's primary stat.
const SCALE_ONLY = [...Object.values(PRIMARY), ...RATING_ORDER.map((k) => RATINGS[k])].map((s) => s.option).join(',');

function fileWord(text) {
    return String(text).replace(/ /g, '_');
}

module.exports = { SPECS, ROLE, PRIMARY, RATINGS, RATING_ORDER, SCALE_ONLY, fileWord };
