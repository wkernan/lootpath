#!/usr/bin/env node
// Top-set agreement on week one, headless (E-1b, WKE-688). DEV ONLY - nothing
// here ships.
//
//   node topgear-agreement.js [--weights <EngineWeights.lua>] [--out <dir>]
//
// Runs the REAL compare - Lootpath/Modules/EngineCompare.lua, EngineSearch.lua
// and EngineScore.lua loaded as the addon loads them, through the specs' own
// stub world (spec/helpers/addon.lua) - in Lua 5.1 (PATH, or the gates'
// `lootpath-lua` Docker image), over week one as the owner's client stored it:
//
//   the state   spec/fixtures/captures/Lootpath-20261002-112757.lua (PR #313):
//               the Top Gear pass-1 documents (Dungeon exported
//               2026-10-01T13:59:08.545Z, Raid 13:59:35.892Z, 30 cards each),
//               the Upgrade Finder documents, inventory read 4 (11:27:57, 15
//               worn) and the week's STORED compare (week 2026-09-29), with
//               the clock at that read;
//   the reads   the client's own answers for every owned link
//               (spec/fixtures/engine/itemstats-real.lua, the 2026-10-01
//               transcript - the same 40 links as this read) and the rebuilt
//               journal links (linklevel-real.lua);
//   the weights the dev file the game ran. Without --weights it is refitted
//               from the committed inputs by exhaustive.js's gameWeights (E-1d)
//               - byte-identical to the game's own Data/EngineWeights.lua
//               (sha256 printed; the test holds it). --weights loads a file as
//               it is, e.g. the game's copy.
//
// Each of `compare dungeon 6`, `dungeon 10` and `raid` is run twice: once with
// the effects table's params taken out - the table the game ran on
// 2026-10-02, so the single-swap rows must reproduce the STORED rows - and
// once with the shipped table (E-3c). Then the worn set's value the way
// `/lootpath engine best` values it (the client's rating conversion, the
// stub's - spec/stubs/wow.lua) and the way E-1d's harness did (`dr = "table"`),
// and `/lootpath engine best`'s own lines over every owned piece.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const REPO = path.join(__dirname, '..', '..');
const SV = 'spec/fixtures/captures/Lootpath-20261002-112757.lua';
const INVENTORY = 4; // 2026-10-02T11:27:57 local
const NOW = 1790958477; // that read, 16:27:57Z
const RESET = 1791298800; // the US reset after it, 2026-10-06T15:00:00Z
const CASES = [
    ['dungeon 6', 'Dungeon', 6],
    ['dungeon 10', 'Dungeon', 10],
    ['raid', 'Raid', null],
];

// The driver: plain Lua 5.1, run with the repo as the working directory.
const DRIVER = `
local weightsPath, sv, inv, now, reset = arg[1], arg[2], tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5])
package.path = "./?.lua;" .. package.path
-- The stub world replaces the global print (its chat frame); the driver
-- writes to stdout itself.
local function emit(line) io.stdout:write(line, string.char(10)) end
local H = require("spec.helpers.addon")
local R = require("spec.helpers.replay")
local Real = dofile("spec/fixtures/engine/itemstats-real.lua")
local LinkLevel = dofile("spec/fixtures/engine/linklevel-real.lua")
local CHAR = "Hotornot - Arthas"
local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepcopy(v) end
    return out
end
local function num(x) return x == nil and "-" or string.format("%.17g", x) end
local function load(stripped)
    local ns, world = H.load()
    H.chicagoClock(world, now)
    world.secondsUntilReset = reset - now
    local db = R.load(sv)
    ns.db.char = deepcopy(db.char[CHAR])
    ns.db.global = deepcopy(db.global)
    ns.db.global.developer = { engine = true }
    R.inventory(world, R.snapshot("inventory", inv, sv))
    Real.install(world)
    LinkLevel.install(world)
    assert(loadfile(weightsPath))("Lootpath", ns)
    if stripped then
        for _, entry in pairs(ns.engineEffects.items) do entry.params = nil end
    end
    ns.EngineScore.file = nil
    assert(ns.EngineScore.Load())
    return ns, world, db
end
for _, mode in ipairs({ "stripped", "shipped" }) do
    for _, case in ipairs({ { "dungeon 6", "Dungeon", 6 }, { "dungeon 10", "Dungeon", 10 }, { "raid", "Raid", nil } }) do
        local ns, world, db = load(mode == "stripped")
        local run
        ns.EngineCompare.Command("compare " .. case[1], function(r) run = r end)
        if not run then world.runTimers(30) end
        assert(run, "the compare did not finish")
        emit(string.format("case %s|%s|notReady %d", mode, case[1], run.notReady or 0))
        for _, line in ipairs(world.printed) do emit("chat " .. line) end
        local tg = run.result.tg
        emit(string.format("values %s %s %s", num(tg.wornValue), num(tg.topValue), tostring(tg.band)))
        for _, row in ipairs(tg.rows) do emit(string.format("row %s %s %s", row.key, num(row.ours), num(row.theirs))) end
        local stored = db.global.engineCompare["2026-09-29"][CHAR][case[2]]
        for _, row in ipairs(stored and stored.pass1 and stored.pass1.rows or {}) do
            emit(string.format("stored %s %s %s", row.key, num(row.ours), num(row.theirs)))
        end
        local s = tg.search or {}
        emit(string.format("search %s %s %s %s %s %s %s %s %s",
            tostring(s.agree), tostring(s.positions), num(s.ourValue), num(s.theirValue), tostring(s.band),
            tostring(s.pool), tostring(s.outside), tostring(s.notReady), tostring(s.notSearchable or s.why or "-")))
        for _, d in ipairs(s.disagreements or {}) do
            emit(string.format("diff %s|%s|%s|%s|%s|%s", d.position, table.concat(d.ours, ","), table.concat(d.theirs, ","),
                d.oursNames, d.theirsNames, num(d.delta)))
        end
        for _, p in ipairs(s.set or {}) do emit(string.format("set %s %s", p.position, p.key)) end
        -- The worn set, valued as /lootpath engine best values it (forceTier
        -- off, the client's conversion) and as E-1d's harness did (dr table).
        do
            local reads, worn, records = {}, {}, ns.Inventory.Scan().records
            for _, record in ipairs(records) do reads[record.link] = ns.EngineStats.ForLink(record.link) end
            local items = ns.EngineSearch.Vectors(records, reads)
            for _, item in ipairs(items) do if item.location == "equipped" then worn[#worn + 1] = item end end
            local base = { file = ns.EngineScore.file, contentType = case[2], keyLevel = case[3], assumedFinish = true, forceTier = false }
            local client = ns.EngineScore.SetValue(worn, base)
            base.dr = "table"
            local tableValue = ns.EngineScore.SetValue(worn, base)
            emit(string.format("worn %d %s %s", #worn, num(client and client.value), num(tableValue and tableValue.value)))
            for _, item in ipairs(worn) do emit(string.format("wornpiece %s %s %s", item.slot, tostring(item.itemID), tostring(item.level))) end
            do
                world.printed = {}
                local done
                ns.EngineCompare.Command("best " .. case[1], function(r) done = r end)
                local guard = 0
                while not done do
                    guard = guard + 1
                    assert(guard < 100000, "runaway")
                    for _, f in ipairs(world.frames) do
                        if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end
                    end
                end
                for _, line in ipairs(world.printed) do emit("best " .. line) end
                for _, p in ipairs(done.result.positions) do
                    emit(string.format("position %s|%s|%d|%s", p.position, tostring(p.state), p.candidates, num(p.delta)))
                end
            end
        end
        H.unload()
    end
end
emit("done")
`;

// How to run Lua 5.1 with the repo as the working directory: PATH, else the
// gates' Docker image with the repo mounted read-only as its /work.
function findLua() {
    const local = ['lua5.1', 'lua'].find((exe) => spawnSync(exe, ['-v'], { encoding: 'utf8' }).status === 0);
    if (local) return (dir, args) => spawnSync(local, [path.join(dir, 'driver.lua'), ...args.map((a) => (a.startsWith('@') ? path.join(dir, a.slice(1)) : a))], { cwd: REPO, encoding: 'utf8', maxBuffer: 1 << 28 });
    const img = spawnSync('docker', ['image', 'inspect', 'lootpath-lua'], { encoding: 'utf8' });
    if (img.status !== 0) return null;
    return (dir, args) =>
        spawnSync('docker', ['run', '--rm', '-v', `${REPO}:/work:ro`, '-v', `${dir}:/t`, '-w', '/work', 'lootpath-lua', 'lua', '/t/driver.lua', ...args.map((a) => (a.startsWith('@') ? `/t/${a.slice(1)}` : a))], {
            encoding: 'utf8',
            maxBuffer: 1 << 28,
        });
}

function sha256(file) {
    return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

// The weights file: the one named, or the refit (E-1d's gameWeights).
function weightsFile(given) {
    if (given) return path.resolve(given);
    const { gameWeights } = require('./exhaustive');
    return gameWeights().luaPath;
}

function parse(stdout) {
    const cases = [];
    let cur = null;
    for (const line of stdout.split(/\r?\n/)) {
        if (line.startsWith('case ')) {
            const [mode, name, nr] = line.slice(5).split('|');
            cur = { mode, name, notReady: Number(nr.split(' ')[1]), chat: [], rows: [], stored: [], diffs: [], set: [], wornPieces: [], best: [], positions: [] };
            cases.push(cur);
            continue;
        }
        if (!cur) continue;
        const sp = line.indexOf(' ');
        const head = line.slice(0, sp);
        const rest = line.slice(sp + 1);
        const w = rest.split(' ');
        const n = (x) => (x === '-' ? null : Number(x));
        if (head === 'chat') cur.chat.push(rest);
        else if (head === 'values') cur.values = { worn: n(w[0]), top: n(w[1]), band: w[2] };
        else if (head === 'row') cur.rows.push({ key: w[0], ours: n(w[1]), theirs: n(w[2]) });
        else if (head === 'stored') cur.stored.push({ key: w[0], ours: n(w[1]), theirs: n(w[2]) });
        else if (head === 'search') cur.search = { agree: n(w[0]), positions: n(w[1]), ourValue: n(w[2]), theirValue: n(w[3]), band: w[4], pool: n(w[5]), outside: n(w[6]), notReady: n(w[7]), refused: w.slice(8).join(' ') };
        else if (head === 'diff') {
            const [position, ours, theirs, oursNames, theirsNames, delta] = rest.split('|');
            cur.diffs.push({ position, ours: ours ? ours.split(',') : [], theirs: theirs ? theirs.split(',') : [], oursNames, theirsNames, delta: n(delta) });
        } else if (head === 'set') cur.set.push({ position: w[0], key: w[1] });
        else if (head === 'worn') cur.worn = { pieces: Number(w[0]), client: n(w[1]), table: n(w[2]) };
        else if (head === 'wornpiece') cur.wornPieces.push({ slot: w[0], itemID: Number(w[1]), level: Number(w[2]) });
        else if (head === 'best') cur.best.push(rest);
        else if (head === 'position') {
            const [position, state, candidates, delta] = rest.split('|');
            cur.positions.push({ position, state, candidates: Number(candidates), delta: n(delta) });
        }
    }
    return cases;
}

// run({ weights }) -> { weights: { path, sha256 }, cases } | null without Lua.
function run(opts) {
    const o = opts || {};
    const lua = findLua();
    if (!lua) return null;
    const weights = weightsFile(o.weights);
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lootpath-e1b-'));
    fs.writeFileSync(path.join(dir, 'driver.lua'), DRIVER);
    fs.copyFileSync(weights, path.join(dir, 'weights.lua'));
    const res = lua(dir, ['@weights.lua', SV, String(INVENTORY), String(NOW), String(RESET)]);
    if (res.status !== 0 || !/\ndone\s*$/.test(res.stdout)) throw new Error(`lua compare failed (status ${res.status}${res.error ? `, ${res.error.message}` : ""}): ${res.stderr || ""} ${String(res.stdout || "").slice(-2000)}`);
    return { weights: { path: weights, sha256: sha256(weights) }, cases: parse(res.stdout) };
}

function parseArgs(argv) {
    const o = { weights: null, out: path.join(__dirname, 'out') };
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === '--weights') o.weights = argv[++i];
        else if (argv[i] === '--out') o.out = argv[++i];
        else throw new Error(`usage: node topgear-agreement.js [--weights <file>] [--out <dir>] (unknown ${argv[i]})`);
    }
    return o;
}

const f = (x, d) => (typeof x === 'number' ? x.toFixed(d === undefined ? 4 : d) : '-');

function main(argv, log) {
    const say = log || console.log;
    const o = parseArgs(argv);
    const r = run(o);
    if (!r) throw new Error('no Lua 5.1 on PATH and no lootpath-lua image');
    say(`weights ${r.weights.path} sha256 ${r.weights.sha256}`);
    for (const c of r.cases) {
        say(`\n== ${c.mode} effects, compare ${c.name} (band ${c.values && c.values.band}; ${c.notReady} not ready)`);
        say(`worn ${f(c.values.worn)}, QE Live's top set ${f(c.values.top)} (the block's forceTier-on values)`);
        const stored = new Map(c.stored.map((s) => [s.key, s]));
        for (const row of c.rows) {
            const s = stored.get(row.key);
            say(`  swap ${row.key}: ours ${f(row.ours, 6)}${s ? `, stored ${f(s.ours, 6)}, diff ${(row.ours - s.ours).toExponential(2)}` : ''}`);
        }
        const s = c.search;
        say(`  search: agree ${s.agree} of ${s.positions}; ours ${f(s.ourValue)}, QE Live's top set by our value ${f(s.theirValue)}; band ${s.band}; pool ${s.pool}, outside ${s.outside}, not ready ${s.notReady}${s.refused !== '-' ? `; ${s.refused}` : ''}`);
        for (const d of c.diffs) say(`    ${d.position}: ours ${d.oursNames} [${d.ours.join(', ')}] vs QE Live ${d.theirsNames} [${d.theirs.join(', ')}], ours by ${f(d.delta, 3)}%`);
        if (c.worn) say(`  worn set (${c.worn.pieces} pieces), forceTier off: client conversion ${f(c.worn.client)}, dr table ${f(c.worn.table)}`);
        for (const line of c.best) say(`  ${line}`);
    }
    fs.mkdirSync(o.out, { recursive: true });
    const out = path.join(o.out, 'topgear-agreement.json');
    fs.writeFileSync(out, JSON.stringify(r, null, 2) + '\n');
    say(`\nwrote ${out}`);
    return r;
}

if (require.main === module) {
    try {
        main(process.argv.slice(2));
    } catch (err) {
        console.error(`topgear-agreement: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, main, parse, findLua, SV, INVENTORY, NOW, RESET, CASES };
