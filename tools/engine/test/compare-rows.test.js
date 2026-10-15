'use strict';

// E-0m (WKE-705): the compare stores each Upgrade Finder row's stat vector
// (`rows[i].stats`, EngineCompare.RowVector) and fit-weights.js `--compare`
// fits a stored row on that vector instead of the equal placeholder;
// `--balance class` gives every slot class the same total weight.
//
// Over COMMITTED files only. Weeks one and two predate the vectors, so they
// are the "before": read through `--compare` they change nothing. The "after"
// is a fixture this test builds from week one's stored compare (the rows a
// real run stored, PR #313), each row given the vector the client read for its
// link where one is known: a committed transcript's read of that exact link,
// or - for a jewellery row no transcript read - the vector E-0l's probe
// recovers from the row's stored raws (identified only when the stored raws
// are reproduced to 1e-5, i.e. the vector the game scored; ARCHITECTURE.md
// section 9, 2026-10-02). A row with neither keeps no vector, as a row of a
// week before E-0m does. Every figure pinned below was read from the tool's
// own output on these files.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseSavedVariables, luaArray } = require('../../companion/lib/lua-savedvariables');
const { loadTable, buildBudget, itemStats, statsForLink, readCompareInto, compareRowRecords, newTable, addPoint, SOURCE_COMPARE } = require('../lib/stats');
const { rowWeights, BALANCES } = require('../lib/fit');
const { zeroStats } = require('../lib/score');
const PJ = require('../probe-jewellery');
const { run } = require('../fit-weights');

const REPO = path.join(__dirname, '..', '..', '..');
const CAP = (f) => path.join(REPO, 'spec', 'fixtures', 'captures', f);
const QE = path.join(REPO, 'spec', 'fixtures', 'qe');
const STATS = ['Lootpath-20260915-162015.lua', 'Lootpath-20260916-152428.lua', 'Lootpath-20261001-092631.lua', 'Lootpath-20261001-200927.lua'].map(CAP);
const WEEK_ONE = CAP('Lootpath-20261002-112757.lua');
const WEEK_TWO = CAP('Lootpath-20261009-204729.lua');
const KEY_LEVELS = '1=2,2=4,4=6,6=8,7=10';

// The client's SavedVariables form, enough for the reader: `["k"] = v,`.
function lua(v) {
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (typeof v === 'string') return JSON.stringify(v);
    if (Array.isArray(v)) return `{\n${v.map((x) => `${lua(x)},\n`).join('')}}`;
    return `{\n${Object.keys(v)
        .map((k) => `${/^\d+$/.test(k) ? `[${k}]` : `[${JSON.stringify(k)}]`} = ${lua(v[k])},\n`)
        .join('')}}`;
}

function savedVariables(engineCompare) {
    return `LootpathDB = ${lua({ global: { engineCompare } })}\n`;
}

function tmp(name, text) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e0m-'));
    const file = path.join(dir, name);
    fs.writeFileSync(file, text);
    return file;
}

function fit(extra) {
    const args = ['--key-levels', KEY_LEVELS, '--resamples', '0', '--derived-at', '2026-10-09T00:00:00Z', '--out', fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e0m-out-')), ...extra];
    for (const s of STATS) args.push('--stats', s);
    args.push(QE);
    const lines = [];
    const r = run(args, (l) => lines.push(l));
    return { ...r, lines };
}

const cache = {};
function once(key, make) {
    if (!(key in cache)) cache[key] = make();
    return cache[key];
}

// Week one's stored compare with each row's vector where the client's read of
// it is known (see the header). Returns the file and where each vector came from.
function weekOneWithVectors() {
    return once('fixture', () => {
        const args = ['--key-levels', KEY_LEVELS, '--compare', WEEK_ONE, '--week', '2026-09-29', '--char', 'Hotornot - Arthas'];
        for (const s of STATS) args.push('--stats', s);
        args.push(QE);
        const probe = PJ.run(args, () => {});
        const recovered = new Map(probe.recovered.filter((r) => r.identified).map((r) => [r.key, r.stats]));
        const table = loadTable(STATS, fs);
        const week = parseSavedVariables(fs.readFileSync(WEEK_ONE, 'utf8')).LootpathDB.global.engineCompare['2026-09-29'];
        const origin = { read: new Set(), recovered: new Set(), none: 0 };
        const out = {};
        for (const char of Object.keys(week)) {
            out[char] = {};
            for (const ct of Object.keys(week[char])) {
                out[char][ct] = {};
                for (const doc of Object.keys(week[char][ct])) {
                    if (doc === 'pass1') continue;
                    const rows = luaArray(week[char][ct][doc].rows).map((row) => {
                        const read = statsForLink(table, row.link);
                        if (read) {
                            origin.read.add(row.key);
                            return { ...row, stats: { ...read } };
                        }
                        if (recovered.has(row.key)) {
                            origin.recovered.add(row.key);
                            return { ...row, stats: { ...recovered.get(row.key) } };
                        }
                        origin.none += 1;
                        return { ...row };
                    });
                    out[char][ct][doc] = { rows };
                }
            }
        }
        return { file: tmp('week-one-with-vectors.lua', savedVariables({ '2026-09-29': out })), origin };
    });
}

const jewellery = (r) => Object.fromEntries(r.fits.map((f) => [f.file, { rho: f.byClass.jewellery.spearman, k: f.byClass.jewellery.k, placeholder: f.placeholderByClass.jewellery, n: f.byClass.jewellery.n }]));
const near = (expected, actual, what) => assert.ok(Math.abs(expected - actual) < 0.0005, `${what}: expected ${expected}, got ${actual}`);

test('a stored row with a vector is a client point at the level it was read; one without adds nothing', () => {
    const text = savedVariables({
        '2026-10-13': {
            'Hotornot - Arthas': {
                Dungeon: {
                    6: {
                        rows: [
                            { key: '999001@324', level: 324, slot: 'Finger', class: 'jewellery', stats: { int: 0, haste: 61, crit: 312, mastery: 0, vers: 0, leech: 0, sockets: 1 } },
                            { key: '999002@324', level: 324, slot: 'Finger', class: 'jewellery' },
                            // A point a transcript already holds is kept.
                            { key: '999003@321', level: 321, slot: 'Neck', class: 'jewellery', stats: { int: 0, haste: 1, crit: 1, mastery: 1, vers: 1, leech: 0, sockets: 1 } },
                        ],
                    },
                    pass1: { rows: [{ key: '999004:1:2', level: 300, slot: 'Finger', stats: { int: 0, haste: 9, crit: 9, mastery: 9, vers: 9, leech: 0, sockets: 0 } }] },
                },
            },
        },
    });
    const records = compareRowRecords(parseSavedVariables(text));
    assert.deepEqual(records.map((r) => [r.key, r.vector !== null]), [['999001@324', true], ['999002@324', false], ['999003@321', true]]);
    const table = newTable();
    addPoint(table, 999003, 321, { ...zeroStats(), haste: 200, mastery: 100 }, 'Neck', 'capture itemstats');
    // A ring of the same group read by a transcript, so the budget has a jewel group.
    addPoint(table, 999005, 321, { ...zeroStats(), haste: 150, crit: 150 }, 'Finger', 'capture itemstats');
    const counts = readCompareInto(table, text, 'synthetic');
    assert.deepEqual({ rows: counts.rows, vectors: counts.vectors, points: counts.points, held: counts.held }, { rows: 3, vectors: 2, points: 1, held: 1 });
    const budget = buildBudget(table);
    const used = itemStats(table, budget, { id: 999001, level: 324, slot: 'Finger' });
    assert.equal(used.statsSource, 'client');
    assert.equal(used.splitSource, 'client');
    assert.equal(used.clientSource, SOURCE_COMPARE);
    assert.deepEqual(used.stats, { int: 0, haste: 61, crit: 312, mastery: 0, vers: 0, leech: 0 });
    const fallback = itemStats(table, budget, { id: 999002, level: 324, slot: 'Finger' });
    assert.equal(fallback.splitSource, 'equal-placeholder');
    assert.equal(fallback.stats.haste, fallback.stats.mastery);
    assert.equal(table.points.get('999003@321').source, 'capture itemstats');
    assert.equal(table.points.get('999003@321').stats.haste, 200);
});

test('before: weeks one and two carry no vector, so --compare over them changes no weight', () => {
    const base = once('base', () => fit([]));
    const before = once('before', () => fit(['--compare', WEEK_ONE, '--compare', WEEK_TWO]));
    const said = before.lines.filter((l) => l.startsWith('compare rows'));
    assert.equal(said.length, 2);
    assert.match(said[0], /: 85 stored Upgrade Finder rows, 0 with a vector \(weeks none\); 0 new client points/);
    assert.match(said[1], /: 171 stored Upgrade Finder rows, 0 with a vector \(weeks none\); 0 new client points/);
    assert.equal(before.lua.replace(/^-- .*\n/gm, ''), base.lua.replace(/^-- .*\n/gm, ''));
    for (let i = 0; i < base.fits.length; i++) {
        assert.deepEqual(before.fits[i].weights, base.fits[i].weights, base.fits[i].file);
        assert.deepEqual(before.fits[i].byClass, base.fits[i].byClass, base.fits[i].file);
    }
    // The before, as the tool prints it: jewellery rho 0.660-0.688, k 1.019-1.028,
    // 24-34 of 34-48 fitted jewellery rows on the equal placeholder.
    const j = jewellery(base);
    near(0.676, j['qe-upgradefinder-Hotornot-abxrrnezfilt.json'].rho, '+10 (abxrrnezfilt) rho');
    near(0.66, j['qe-upgradefinder-Hotornot-lttldhvkiqlr.json'].rho, '+8 rho');
    near(1.028, j['qe-upgradefinder-Hotornot-kqyktjywppzw.json'].k, 'raid k');
    assert.equal(j['qe-upgradefinder-Hotornot-kqyktjywppzw.json'].placeholder, 34);
    assert.equal(j['qe-upgradefinder-Hotornot-kqyktjywppzw.json'].n, 48);
});

test('after: the stored vectors replace the placeholder and every document\'s jewellery rho rises', () => {
    const { file, origin } = weekOneWithVectors();
    assert.equal(origin.read.size, 5);
    assert.deepEqual([...origin.recovered].sort(), ['268249@324', '268250@321', '268251@324', '268266@318']);
    const base = once('base', () => fit([]));
    const after = once('after', () => fit(['--compare', file]));
    const said = after.lines.find((l) => l.startsWith('compare rows'));
    assert.match(said, /: 85 stored Upgrade Finder rows, 21 with a vector \(weeks 2026-09-29\); 4 new client points, 9 already read by a transcript/);
    const b = jewellery(base);
    const a = jewellery(after);
    for (const doc of Object.keys(b)) {
        assert.ok(a[doc].rho > b[doc].rho, `${doc}: rho ${b[doc].rho} -> ${a[doc].rho}`);
        assert.ok(a[doc].placeholder < b[doc].placeholder, `${doc}: placeholder ${b[doc].placeholder} -> ${a[doc].placeholder}`);
        assert.equal(a[doc].n, b[doc].n, doc);
    }
    near(0.745, a['qe-upgradefinder-Hotornot-abxrrnezfilt.json'].rho, '+10 (abxrrnezfilt) rho');
    near(0.773, a['qe-upgradefinder-Hotornot-lttldhvkiqlr.json'].rho, '+8 rho');
    near(0.719, a['qe-upgradefinder-Hotornot-kqyktjywppzw.json'].rho, 'raid rho');
    near(1.015, a['qe-upgradefinder-Hotornot-kqyktjywppzw.json'].k, 'raid k');
    assert.equal(a['qe-upgradefinder-Hotornot-kqyktjywppzw.json'].placeholder, 26);
});

test('after, balanced: every slot class carries the same weight, and jewellery k moves toward 1', () => {
    const { file } = weekOneWithVectors();
    const after = once('after', () => fit(['--compare', file]));
    const balanced = once('balanced', () => fit(['--compare', file, '--balance', 'class']));
    assert.ok(balanced.lines.includes('balance: class'));
    const a = jewellery(after);
    const c = jewellery(balanced);
    for (const doc of Object.keys(a)) {
        assert.ok(Math.abs(c[doc].k - 1) < Math.abs(a[doc].k - 1), `${doc}: k ${a[doc].k} -> ${c[doc].k}`);
        assert.equal(balanced.fits.find((f) => f.file === doc).balance, 'class');
    }
    near(0.756, c['qe-upgradefinder-Hotornot-abxrrnezfilt.json'].rho, '+10 (abxrrnezfilt) rho');
    near(1.003, c['qe-upgradefinder-Hotornot-kqyktjywppzw.json'].k, 'raid k');
});

test('the class balance: equal totals per class, summing to N; none is all ones; anything else refused', () => {
    const rows = [...Array(6).fill('armour'), ...Array(2).fill('jewellery'), ...Array(4).fill('tier-slot')].map((slotClass) => ({ slotClass }));
    const w = rowWeights(rows, 'class');
    const total = (c) => rows.reduce((s, r, i) => s + (r.slotClass === c ? w[i] : 0), 0);
    for (const c of ['armour', 'jewellery', 'tier-slot']) near(4, total(c), c);
    near(12, w.reduce((s, x) => s + x, 0), 'sum');
    assert.deepEqual(rowWeights(rows, 'none'), Array(12).fill(1));
    assert.deepEqual(rowWeights(rows), Array(12).fill(1));
    assert.deepEqual(BALANCES, ['none', 'class']);
    assert.throws(() => rowWeights(rows, 'jewellery'), /unknown balance jewellery/);
});
