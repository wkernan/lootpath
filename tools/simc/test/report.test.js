'use strict';

// The parser over the committed SimC reports (spec/fixtures/simc), and the
// guards that refuse a report a weight cannot be read from.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { excerpt, parseExcerpt, parseRun, valueWeights } = require('../lib/report');

const FIX = path.join(__dirname, '..', '..', '..', 'spec', 'fixtures', 'simc', 'reports');

function load(base) {
    return { json: JSON.parse(fs.readFileSync(path.join(FIX, `${base}.json`), 'utf8')), scale: fs.readFileSync(path.join(FIX, `${base}.scale.txt`), 'utf8') };
}

test('every committed report parses: one primary stat, the four ratings, game data 12.1.5', () => {
    const want = {
        '102-Patchwerk-dps': ['int', 'DAMAGER', 'Balance Druid'],
        '102-DungeonSlice-dps': ['int', 'DAMAGER', 'Balance Druid'],
        '103-Patchwerk-dps': ['agi', 'DAMAGER', 'Feral Druid'],
        '103-DungeonSlice-dps': ['agi', 'DAMAGER', 'Feral Druid'],
        '104-Patchwerk-dps': ['agi', 'TANK', 'Guardian Druid'],
        '104-Patchwerk-dtps': ['agi', 'TANK', 'Guardian Druid'],
        '104-DungeonSlice-dps': ['agi', 'TANK', 'Guardian Druid'],
    };
    for (const [base, [primary, role, spec]] of Object.entries(want)) {
        const { json, scale } = load(base);
        const r = parseRun(json, scale, base.split('-')[2]);
        assert.equal(r.primaryStat, primary, base);
        assert.equal(r.player.role, role, base);
        assert.equal(r.player.specialization, spec, base);
        assert.deepEqual(r.stats, [primary, 'haste', 'crit', 'mastery', 'vers'], base);
        assert.equal(r.patch, '12.1.5', base);
        assert.equal(r.simc.version, '1210-01', base);
        assert.equal(r.simc.gitRevision, '2358079', base);
        assert.equal(r.settings.iterations, 100000, base);
        assert.equal(r.settings.targetError, 0, base);
        for (const k of r.stats) assert.ok(r.factors[k].error > 0, `${base} ${k} has an error`);
    }
});

test('each factor is the JSON report\'s number and each error the text report\'s, read not computed', () => {
    const { json, scale } = load('103-Patchwerk-dps');
    const r = parseRun(json, scale, 'dps');
    const text = parseExcerpt(scale);
    assert.equal(r.factors.agi.value, json.sim.players[0].scale_factors.Agi);
    assert.equal(r.factors.agi.error, text.weights.Agi.error);
    assert.equal(r.factors.vers.value, json.sim.players[0].scale_factors.Vers);
    assert.equal(r.metric.mean, text.metrics.DPS.mean);
});

test('the excerpt keeps the Player, metric and Weights lines and drops the action list', () => {
    const full = [
        '',
        'Player: X night_elf druid feral 90',
        '  DPS=100.5 DPS-Error=1.5/1.49% DPS-Range=10/10%',
        '  Talents: ABC',
        '  Priorities (actions.default):',
        '    shred,if=combo_points<5',
        '  Scale Factors:',
        '    Weights :  Agi=2(0.5)  Crit=1(0.5)',
        '',
        ' *** Targets *** ',
        'Target: Fluffy_Pillow',
        '  Scale Factors:',
        '    Weights :',
    ].join('\n');
    const kept = excerpt(full);
    assert.equal(kept, ['Player: X night_elf druid feral 90', '  DPS=100.5 DPS-Error=1.5/1.49% DPS-Range=10/10%', '  Scale Factors:', '    Weights :  Agi=2(0.5)  Crit=1(0.5)', ''].join('\n'));
    assert.doesNotMatch(kept, /shred/);
});

test('REFUSED: a report with a stat missing from its scale factors', () => {
    const { json, scale } = load('103-Patchwerk-dps');
    const p = json.sim.players[0];
    delete p.scale_factors.Haste;
    delete p.scale_factors_all.dps.Haste;
    assert.throws(() => parseRun(json, scale, 'dps'), /the report has no scale factor for haste/);
});

test('REFUSED: a text report with a stat missing from its Weights line', () => {
    const { json, scale } = load('103-Patchwerk-dps');
    const cut = scale.replace(/ {2}Mastery=[^ ]+/, '');
    assert.notEqual(cut, scale);
    assert.throws(() => parseRun(json, cut, 'dps'), /the text report has no scale factor and error for mastery/);
});

test('REFUSED: a stat SimC did not scale (error 0)', () => {
    const { json, scale } = load('103-Patchwerk-dps');
    const zero = scale.replace(/Crit=(-?[\d.e+-]+)\(([\d.e+-]+)\)/, 'Crit=$1(0)');
    assert.throws(() => parseRun(json, zero, 'dps'), /SimC did not scale crit/);
});

test('REFUSED: factors read over the wrong metric (a dps report read as dtps)', () => {
    const { json, scale } = load('104-Patchwerk-dps');
    assert.throws(() => parseRun(json, scale, 'dtps'), /not its dtps factors/);
});

test('REFUSED: a healer - SimC models none', () => {
    const { json, scale } = load('103-Patchwerk-dps');
    json.sim.players[0].role = 'heal';
    assert.throws(() => parseRun(json, scale, 'dps'), /SimC models no healer/);
});

test('REFUSED: a report that scales two primary stats', () => {
    const { json, scale } = load('103-Patchwerk-dps');
    json.sim.players[0].scale_factors.Str = 1;
    json.sim.players[0].scale_factors_all.dps.Str = 1;
    assert.throws(() => parseRun(json, scale, 'dps'), /scales Str and Agi/);
});

test('REFUSED: an excerpt from another run\'s player', () => {
    const { json } = load('103-Patchwerk-dps');
    const other = load('102-Patchwerk-dps').scale;
    assert.throws(() => parseRun(json, other, 'dps'), /the excerpt is for/);
});

test('REFUSED: DungeonSlice gives a tank no DTPS to read (SimC 1210-01: no damage taken)', () => {
    const { json, scale } = load('104-DungeonSlice-dtps');
    assert.equal(json.sim.players[0].collected_data.dtps.mean, 0);
    assert.throws(
        () => parseRun(json, scale, 'dtps'),
        (err) => err.code === 'no-metric' && /no DTPS/.test(err.message)
    );
});

test('a DPS weight is SimC\'s DPS factor unchanged', () => {
    const { json, scale } = load('103-Patchwerk-dps');
    const r = parseRun(json, scale, 'dps');
    const w = valueWeights(r);
    for (const k of r.stats) assert.equal(w[k], r.factors[k].value);
});
