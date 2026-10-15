// Reads one SimulationCraft run: its JSON report (`json2=`, report version
// 2.0.0) and the excerpt of its text report (`output=`) that carries the scale
// factors' errors.
//
// Why two files: SimC 1210-01's JSON report holds each scale factor but not its
// error; the error is printed only in the text report's per-player `Weights :`
// line (`Agi=64.25(6.34)`). The full text report also prints the profile's
// action priority list, which is SimC's GPL-3.0 profile content, so it is never
// committed: the runner keeps the lines this file reads (the `Player:` line, the
// metric lines and the `Weights :` line) verbatim in `<run>.scale.txt` and
// records the full text's sha256 beside it.
//
// Every number here is read from SimC's output. The only arithmetic is a sign
// (a lower-is-better metric is flipped so that a stat that helps is positive),
// and that is named, guarded and tested.
'use strict';

const { ROLE, PRIMARY, RATINGS, RATING_ORDER } = require('./specs');

// The metrics a weight may be read over. `direction` is +1 when more is
// better (damage done) and -1 when less is better (damage taken): SimC reports
// a DTPS scale factor as the change in DTPS per point, negative when the stat
// helps, and does not invert it.
const METRICS = {
    dps: { direction: 1, label: 'DPS' },
    dtps: { direction: -1, label: 'DTPS' },
};

const NUM = '-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][-+]?\\d+)?';

function refuse(message, code) {
    const err = new Error(message);
    err.refusal = true;
    err.code = code;
    throw err;
}

// excerpt(fullText) -> the lines a run keeps from SimC's text report, verbatim.
function excerpt(fullText) {
    const lines = String(fullText).split(/\r?\n/);
    const players = lines.filter((l) => /^Player: /.test(l));
    if (players.length !== 1) refuse(`the text report names ${players.length} players; the runner sims exactly one`);
    const start = lines.findIndex((l) => /^Player: /.test(l));
    let end = lines.findIndex((l, i) => i > start && (/^\s*\*\*\* Targets \*\*\*/.test(l) || /^Target: /.test(l)));
    if (end < 0) end = lines.length;
    const block = lines.slice(start, end);
    const keep = [block[0]];
    for (const l of block.slice(1)) {
        if (new RegExp(`^\\s+[A-Z]+=${NUM} [A-Z]+-Error=`).test(l)) keep.push(l);
    }
    const sf = block.findIndex((l) => /^\s+Scale Factors:\s*$/.test(l));
    if (sf < 0 || !/^\s+Weights :/.test(block[sf + 1] || '')) refuse('the text report has no Scale Factors / Weights line for the player');
    keep.push(block[sf], block[sf + 1]);
    return keep.join('\n') + '\n';
}

// parseExcerpt(text) -> { player, metrics: { DPS: { mean, error } }, weights: { Agi: { value, error } } }
function parseExcerpt(text) {
    const lines = String(text).split(/\r?\n/);
    const player = (lines.find((l) => /^Player: /.test(l)) || '').replace(/^Player: /, '').trim();
    if (!player) refuse('the excerpt has no Player: line');
    const metrics = {};
    for (const l of lines) {
        const m = l.match(new RegExp(`^\\s+([A-Z]+)=(${NUM}) \\1-Error=(${NUM})/`));
        if (m) metrics[m[1]] = { mean: Number(m[2]), error: Number(m[3]) };
    }
    const w = lines.find((l) => /^\s+Weights :/.test(l));
    if (!w) refuse('the excerpt has no Weights line');
    const weights = {};
    const pair = new RegExp(`([A-Za-z]+)=(${NUM})\\((${NUM})\\)`, 'g');
    for (const m of w.matchAll(pair)) weights[m[1]] = { value: Number(m[2]), error: Number(m[3]) };
    return { player, metrics, weights };
}

function close(a, b) {
    return Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a), Math.abs(b));
}

// patchOf("12.1.5.70391") -> "12.1.5", the form GetBuildInfo() returns and the
// weights file's `patch` holds.
function patchOf(wowVersion) {
    const m = String(wowVersion || '').match(/^(\d+\.\d+\.\d+)\.\d+$/);
    if (!m) refuse(`the report's game version "${wowVersion}" is not major.minor.patch.build`);
    return m[1];
}

// parseRun(json, excerptText, metric) -> one run read: SimC's version and game
// data, the sim's settings, the player, the metric, and the scale factor and
// error of every stat the spec scales with. Refuses a report that does not
// carry everything a weight needs.
function parseRun(jsonText, excerptText, metric) {
    if (!METRICS[metric]) refuse(`unknown metric "${metric}" (dps or dtps)`);
    const report = typeof jsonText === 'string' ? JSON.parse(jsonText) : jsonText;
    if (!report || !report.sim || !Array.isArray(report.sim.players)) refuse('not a SimC JSON report (no sim.players)');
    if (report.report_version !== '2.0.0') refuse(`JSON report version ${report.report_version}; the runner reads 2.0.0`);
    if (report.sim.players.length !== 1) refuse(`the report holds ${report.sim.players.length} players; the runner sims exactly one`);
    const p = report.sim.players[0];
    const opts = report.sim.options || {};
    const dbc = (opts.dbc && opts.dbc[opts.dbc.version_used]) || null;
    if (!dbc) refuse('the report names no game data (sim.options.dbc)');

    const role = ROLE[p.role];
    if (!role) refuse(`SimC's role for ${p.specialization} is "${p.role}" - SimC models no healer, and the runner rates DAMAGER and TANK specs only`);
    if (!opts.scaling || opts.scaling.calculate_scale_factors !== 1) refuse('the report was not run with calculate_scale_factors=1');

    const text = parseExcerpt(excerptText);
    if (text.player.split(' ')[0] !== p.name) refuse(`the excerpt is for "${text.player.split(' ')[0]}", the report for "${p.name}"`);

    // Which metric the factors are over: the JSON does not record scale_over,
    // so the top-level factors must equal that metric's own entry in
    // scale_factors_all.
    const all = p.scale_factors_all || {};
    const top = p.scale_factors || {};
    const over = all[metric];
    if (!over) refuse(`the report has no ${metric} scale factors`);
    for (const k of Object.keys(top)) {
        if (!close(top[k], over[k])) refuse(`the report's scale factors are not its ${metric} factors (${k}: ${top[k]} vs ${over[k]}) - run with scale_over=${metric}`);
    }

    // SimC prints a metric's line only when it is not zero: no DTPS= line
    // means nothing in the fight damaged the player (measured: DungeonSlice,
    // SimC 1210-01, a Guardian's DTPS is 0 on every iteration).
    const label = METRICS[metric].label;
    const m = text.metrics[label];
    if (!m) refuse(`the report has no ${label}: nothing in this fight gave the player a ${label} to measure`, 'no-metric');

    const primaries = Object.keys(PRIMARY).filter((k) => k in top);
    if (primaries.length !== 1) refuse(`the report scales ${primaries.length ? primaries.join(' and ') : 'no primary stat'}; a spec has exactly one of Str, Agi, Int`);
    const wanted = [primaries[0], ...RATING_ORDER];
    const factors = {};
    for (const k of wanted) {
        const key = (PRIMARY[k] || RATINGS[k]).key;
        const tw = text.weights[k];
        if (!(k in top) || typeof top[k] !== 'number' || !Number.isFinite(top[k])) refuse(`the report has no scale factor for ${key}`);
        if (!tw || !Number.isFinite(tw.value) || !Number.isFinite(tw.error)) refuse(`the text report has no scale factor and error for ${key}`);
        if (!(tw.error > 0)) refuse(`SimC did not scale ${key} over ${metric} (error ${tw.error}): it was not in scale_only`);
        if (!close(tw.value, top[k])) refuse(`the text report's ${key} factor ${tw.value} is not the JSON report's ${top[k]}`);
        factors[key] = { value: top[k], error: tw.error };
    }

    return {
        simc: {
            version: report.version,
            gitRevision: report.git_revision,
            gitBranch: report.git_branch,
            buildDate: report.build_date,
            wowVersion: dbc.wow_version,
            hotfixDate: dbc.hotfix_date,
            dataVersion: opts.dbc.version_used,
        },
        patch: patchOf(dbc.wow_version),
        player: { name: p.name, specialization: p.specialization, simcRole: p.role, role, talents: p.talents },
        settings: {
            fightStyle: opts.fight_style,
            iterations: opts.iterations,
            targetError: opts.target_error,
            threads: opts.threads,
            deterministic: opts.deterministic,
            maxTime: opts.max_time,
            varyCombatLength: opts.vary_combat_length,
            desiredTargets: opts.desired_targets,
            scaleOnly: opts.scaling.scale_only,
        },
        scaleDeltas: p.scale_deltas || {},
        metric: { name: metric, label, mean: m.mean, error: m.error, direction: METRICS[metric].direction },
        primaryStat: PRIMARY[primaries[0]].key,
        stats: wanted.map((k) => (PRIMARY[k] || RATINGS[k]).key),
        factors,
    };
}

// valueWeights(run) -> { [stat]: weight } with "higher is better" for every
// metric: SimC's factor times the metric's direction. A DTPS factor of -7.4
// (versatility lowers damage taken) becomes a weight of +7.4.
function valueWeights(run) {
    const out = {};
    for (const [k, f] of Object.entries(run.factors)) out[k] = run.metric.direction * f.value;
    const primary = out[run.primaryStat];
    const err = run.factors[run.primaryStat].error;
    // More of the primary stat never makes a spec worse at its own job. A
    // primary weight below zero by more than its error means the metric was
    // read the wrong way round.
    if (primary < 0 && Math.abs(primary) > err) {
        refuse(`the ${run.metric.label} value reads the wrong way round: ${run.primaryStat} would be worth ${primary} (error ${err})`);
    }
    return out;
}

module.exports = { METRICS, excerpt, parseExcerpt, parseRun, valueWeights, patchOf, refuse };
