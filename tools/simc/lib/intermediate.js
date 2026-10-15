// The runner's own output, one file per spec and fight:
// tools/simc/out/<specID>-<fight>.json, schema `lootpath-simc-scale-factors`
// version 1. It holds what the weights writer needs (role, primaryStat, stats,
// the value metric and its weights) and everything that says where the numbers
// came from (SimC's version and game data, the settings, the profile and its
// sha256, the reports and theirs).
'use strict';

const { valueWeights, refuse } = require('./report');

const SCHEMA = 'lootpath-simc-scale-factors';
const VERSION = 1;

// What a tank's "value" is, said once, written into every tank entry. The
// owner decides (docs/ARCHITECTURE.md §7 E-7, §11); `--tank-value` switches it.
const TANK_VALUE = {
    dtps:
        'survival: damage taken per second, lower is better, so each weight is minus SimC\'s DTPS factor (damage taken saved per point). DTPS counts no healing, so a stat that works through self-healing or health (Guardian mastery) reads near zero. The DPS factors are kept beside it.',
    dps: 'damage: the tank\'s own DPS, as for a DPS spec. Survival is not valued at all. The DTPS factors are kept beside it.',
};
const DAMAGER_VALUE = 'damage: DPS, higher is better; each weight is SimC\'s DPS factor (DPS per point).';

function same(runs, pick, what) {
    const first = JSON.stringify(pick(runs[0]));
    for (const r of runs.slice(1)) {
        if (JSON.stringify(pick(r)) !== first) refuse(`the runs for one spec disagree on ${what}`);
    }
}

// build(runs, meta) -> the intermediate object. `runs` are parseRun results,
// one per metric (DAMAGER: dps; TANK: dtps and dps); `meta` carries specID,
// fight, tankValue, profile { path, sha256, tier }, source, reports, derivedAt.
function build(runs, meta) {
    if (!runs.length) refuse('no runs');
    same(runs, (r) => r.simc, 'the SimC build');
    same(runs, (r) => r.settings.fightStyle, 'the fight style');
    same(runs, (r) => [r.settings.iterations, r.settings.threads, r.settings.deterministic], 'iterations, threads or determinism');
    same(runs, (r) => r.player, 'the player');
    same(runs, (r) => r.stats, 'the stats scaled');
    const first = runs[0];
    if (first.settings.fightStyle !== meta.fight) refuse(`the report's fight style is ${first.settings.fightStyle}, not ${meta.fight}`);
    const byMetric = Object.fromEntries(runs.map((r) => [r.metric.name, r]));
    const role = first.player.role;
    const valueMetric = role === 'TANK' ? meta.tankValue || 'dtps' : 'dps';
    if (role === 'DAMAGER' && valueMetric !== 'dps') refuse('a DAMAGER spec is valued on DPS');
    const valueRun = byMetric[valueMetric];
    if (!valueRun) refuse(`no ${valueMetric} run for this ${role} spec`);
    const unmeasured = meta.unmeasured || {};
    if (role === 'TANK') {
        for (const m of ['dtps', 'dps']) if (!byMetric[m] && !unmeasured[m]) refuse(`a TANK spec needs both a dtps and a dps run; ${m} is missing`);
    }

    const factors = {};
    for (const r of runs) {
        factors[r.metric.name] = {
            mean: r.metric.mean,
            error: r.metric.error,
            direction: r.metric.direction,
            stats: Object.fromEntries(Object.entries(r.factors).map(([k, f]) => [k, { value: f.value, error: f.error, significant: Math.abs(f.value) > f.error }])),
        };
    }

    return {
        schema: SCHEMA,
        version: VERSION,
        devOnly: true,
        specID: meta.specID,
        specialization: first.player.specialization,
        role,
        fight: meta.fight,
        primaryStat: first.primaryStat,
        stats: first.stats,
        unit: 'per point',
        value: {
            metric: valueMetric,
            label: valueRun.metric.label,
            mean: valueRun.metric.mean,
            error: valueRun.metric.error,
            means: role === 'TANK' ? TANK_VALUE[valueMetric] : DAMAGER_VALUE,
        },
        weights: valueWeights(valueRun),
        factors,
        unmeasured: Object.keys(unmeasured).length ? unmeasured : undefined,
        patch: first.patch,
        simc: first.simc,
        settings: first.settings,
        scaleDeltas: first.scaleDeltas,
        profile: meta.profile,
        source: meta.source,
        reports: meta.reports,
        derivedAt: meta.derivedAt,
    };
}

module.exports = { SCHEMA, VERSION, TANK_VALUE, DAMAGER_VALUE, build };
