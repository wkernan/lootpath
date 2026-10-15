#!/usr/bin/env node
// Extracts spec/fixtures/engine/itemstats-real.lua from the owner's committed
// `capture itemstats` transcript (E-0f, WKE-676). DEV ONLY - nothing here ships.
//
//   node extract-itemstats.js [transcript.lua] [out.lua]
//
// Defaults: spec/fixtures/captures/Lootpath-20261001-092631.lua and
// spec/fixtures/engine/itemstats-real.lua. Every value written is one the
// client answered, copied from the transcript through
// tools/companion/lib/lua-savedvariables.js: the 80 items (link, the level the
// client gives the link, the base stats `GetItemStats` answered for the link
// with its enchant and gems blanked, sockets, gems and their empty stat
// tables, set, uniqueness), the rating conversion at the probe's six values,
// the mastery pair, healing, intellect and the secret flags, and the six
// trinket tooltips. Nothing is computed, rounded or invented; the output is
// labelled with the transcript's sha256 and a test re-runs this script and
// compares it byte for byte with the committed fixture.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { parseSavedVariables, luaArray } = require('../companion/lib/lua-savedvariables');
const { itemStatsRecords, strippedKey } = require('./lib/stats');

const REPO = path.join(__dirname, '..', '..');
const DEFAULT_IN = path.join('spec', 'fixtures', 'captures', 'Lootpath-20261001-092631.lua');
const DEFAULT_OUT = path.join('spec', 'fixtures', 'engine', 'itemstats-real.lua');

// A Lua literal for a JS value, keys in a fixed order (positional first, then
// `n`, then named keys sorted), so two runs write the same bytes.
function lua(value, indent) {
    const pad = '    '.repeat(indent);
    const inner = '    '.repeat(indent + 1);
    if (value === null || value === undefined) return 'nil';
    if (typeof value === 'boolean') return value ? 'true' : 'false';
    if (typeof value === 'number') {
        if (!Number.isFinite(value)) throw new Error(`not a finite number: ${value}`);
        return String(value);
    }
    if (typeof value === 'string') {
        return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r')}"`;
    }
    if (Array.isArray(value)) {
        if (!value.length) return '{}';
        return `{\n${value.map((v) => `${inner}${lua(v, indent + 1)},`).join('\n')}\n${pad}}`;
    }
    // A nil field is left out, as Lua would hold it.
    const keys = Object.keys(value).filter((k) => value[k] !== null && value[k] !== undefined);
    if (!keys.length) return '{}';
    const positional = keys.filter((k) => /^[1-9]\d*$/.test(k)).sort((a, b) => Number(a) - Number(b));
    const named = keys.filter((k) => !/^[1-9]\d*$/.test(k)).sort();
    const lines = [];
    for (const k of positional) lines.push(`${inner}[${k}] = ${lua(value[k], indent + 1)},`);
    for (const k of named) {
        const key = /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `[${lua(k, 0)}]`;
        lines.push(`${inner}${key} = ${lua(value[k], indent + 1)},`);
    }
    return `{\n${lines.join('\n')}\n${pad}}`;
}

// A probe `{ [1] = v, ..., n = count }` kept exactly as stored.
function probe(p) {
    if (!p || typeof p !== 'object') return null;
    const out = { n: p.n };
    for (let i = 1; i <= (p.n || 0); i++) if (p[i] !== undefined) out[i] = p[i];
    return out;
}

function nameOf(link) {
    const m = String(link).match(/\|h\[(.*)\]\|h/);
    return m ? m[1] : null;
}

function extract(text) {
    const sv = parseSavedVariables(text);
    const caps = sv.LootpathDB.global.captures;
    const snaps = luaArray(caps.itemstats || {});
    if (snaps.length !== 1) throw new Error(`expected one itemstats snapshot, found ${snaps.length}`);
    const snap = snaps[0];
    const data = snap.data;

    const rows = itemStatsRecords(caps).map(({ item: it, level }) => {
        const gems = luaArray(it.gems || {}).map((g) => ({
            index: g.index,
            id: g.gemID && g.gemID[1] !== undefined ? g.gemID[1] : null,
            name: g.gem && g.gem[1] !== undefined ? g.gem[1] : null,
            link: g.gem && g.gem[2] !== undefined ? g.gem[2] : null,
            stats: g.gemStats ? g.gemStats[1] || null : null,
        }));
        return {
            source: it.source,
            link: it.link,
            strippedLink: it.strippedLink,
            key: strippedKey(it.link),
            name: nameOf(it.link),
            itemID: it.itemID,
            level,
            detailedLevel: probe(it.detailedLevel),
            journalItemLevel: it.journalItemLevel === undefined ? null : it.journalItemLevel,
            difficultyID: it.difficultyID === undefined ? null : it.difficultyID,
            instanceName: it.instanceName === undefined ? null : it.instanceName,
            invSlot: it.invSlot === undefined ? null : it.invSlot,
            slot: it.slot === undefined ? null : it.slot,
            equipLoc: it.info ? it.info.itemEquipLoc : null,
            classID: it.info ? it.info.classID : null,
            subclassID: it.info ? it.info.subclassID : null,
            setID: it.info && it.info.setID !== undefined ? it.info.setID : null,
            stats: it.strippedStats ? it.strippedStats[1] : null,
            strippedEqual: it.strippedEqual === undefined ? null : it.strippedEqual,
            sockets: it.numSockets ? it.numSockets[1] : null,
            gems,
            uniqueness: probe(it.uniqueness),
            uniquenessByID: probe(it.uniquenessByID),
        };
    });

    const rating = {};
    for (const [key, r] of Object.entries(data.rating.ratings)) {
        rating[key] = {
            constant: r.constant,
            index: r.index,
            current: r.rating[1],
            bonus: r.bonus[1],
            at: luaArray(r.at).map((a) => ({ value: a.value, bonus: a.bonus[1] })),
        };
    }
    const tooltips = luaArray(data.tooltips || {}).map((t) => ({
        link: t.link,
        itemLevel: t.itemLevel,
        difficultyID: t.difficultyID,
        lines: luaArray(t.lines || {}).map((l) => ({ type: l.type, leftText: l.leftText })),
    }));

    return {
        capturedAtLocal: snap.capturedAtLocal,
        build: probe(snap.build),
        trigger: snap.trigger,
        durationMs: snap.durationMs,
        sawSecret: snap.sawSecret,
        specID: data.specID,
        requested: data.requested,
        stillWaiting: data.stillWaiting,
        waitTimedOut: data.waitTimedOut,
        journal: {
            rowsWithLink: data.journal.rowsWithLink,
            taken: data.journal.taken,
            instances: data.journal.instances,
            cacheEntries: luaArray(data.journal.cacheEntries).map((e) => ({ key: e.key, build: e.build, walkAt: e.walkAt })),
        },
        rows,
        rating,
        masteryEffect: probe(data.rating.masteryEffect),
        spellBonusHealing: probe(data.rating.spellBonusHealing),
        intellect: probe(data.rating.intellect),
        hasSecretRestrictions: probe(data.rating.hasSecretRestrictions),
        shouldUnitStatsBeSecret: probe(data.rating.shouldUnitStatsBeSecret),
        combatLogRestricted: probe(data.rating.combatLogRestricted),
        tooltips,
    };
}

// The fixed half of the file: how a spec puts the transcript on a stub world.
const INSTALL = `
-- Registers every row on a stub world, as the client answered it: the item
-- loaded under its own link and under the link with enchant and gems blanked
-- (GetItemInfo's returns 9, 12, 13 and 16; GetDetailedItemLevelInfo's three),
-- the base stats under both (strippedEqual is true for all 80), the socket
-- count, uniqueness, each gem's name and link in its socket and the gem link's
-- EMPTY stat table; the five current ratings, the mastery pair, healing and
-- intellect. The rating conversion is the stub's own, which answers the
-- transcript's thirty points (spec/stubs/wow.lua, world.ratingCurves).
--
-- An item already on the world is MERGED into, never replaced (E-0i, WKE-680):
-- this row's info, level and detailed level are set and every other field the
-- entry carries stays - above all \`instant\`, which R.inventory registers and
-- ns.Inventory.Scan reads, so installing after R.inventory no longer empties
-- the scan.
function F.install(world)
    for _, row in ipairs(F.ROWS) do
        local info = { row.name, row.link, 4, row.level, n = 18 }
        info[9] = row.equipLoc
        info[12] = row.classID
        info[13] = row.subclassID
        info[16] = row.setID
        for _, link in ipairs({ row.link, row.strippedLink }) do
            local entry = world.items[link] or {}
            entry.info = info
            entry.level = row.level
            entry.detailed = row.detailedLevel
            world.items[link] = entry
            world.itemStats[link] = row.stats
            world.itemSockets[link] = row.sockets
        end
        world.itemDataCached[row.itemID] = true
        world.itemUniquenessByID[row.itemID] = row.uniquenessByID
        if row.uniqueness and row.uniqueness.n > 0 then
            world.itemUniqueness[row.link] = row.uniqueness
        end
        local gems = {}
        for _, gem in ipairs(row.gems) do
            if gem.link then
                gems[gem.index] = { name = gem.name, link = gem.link, id = gem.id }
                world.itemStats[gem.link] = gem.stats
            end
        end
        if next(gems) then
            world.itemGems[row.link] = gems
        end
    end
    for _, r in pairs(F.RATING) do
        world.combatRatings[r.index] = r.current
    end
    world.masteryEffect = { F.MASTERY_EFFECT[1], F.MASTERY_EFFECT[2] }
    world.spellBonusHealing = F.SPELL_BONUS_HEALING[1]
    world.unitStats[4] = { F.INTELLECT[1], F.INTELLECT[2], F.INTELLECT[3], F.INTELLECT[4] }
end

-- The rows of one source ("worn", "bag", "journal"), in the transcript's order.
function F.rowsFrom(source)
    local out = {}
    for _, row in ipairs(F.ROWS) do
        if row.source == source then
            out[#out + 1] = row
        end
    end
    return out
end

return F
`;

function render(x, inputRel, sha, bytes) {
    const head = [
        '-- spec/fixtures/engine/itemstats-real.lua (E-0f, WKE-676)',
        '--',
        '-- GENERATED - do not edit. `node tools/engine/extract-itemstats.js` wrote it',
        `-- from ${inputRel.replace(/\\/g, '/')}`,
        `-- (sha256 ${sha}, ${bytes} bytes as committed),`,
        "-- the owner's `capture itemstats` on the Druid, 2026-10-01. Every value is the",
        "-- client's answer copied through tools/companion/lib/lua-savedvariables.js:",
        '-- nothing computed, rounded or invented. tools/engine/test/extract.test.js',
        '-- re-runs the script and compares the bytes.',
        '',
        'local F = {}',
        '',
        `F.SOURCE = ${lua(inputRel.replace(/\\/g, '/'), 0)}`,
        `F.SHA256 = ${lua(sha, 0)}`,
        `F.BYTES = ${bytes}`,
        `F.CAPTURED_AT_LOCAL = ${lua(x.capturedAtLocal, 0)}`,
        `F.BUILD = ${lua(x.build, 0)}`,
        `F.TRIGGER = ${lua(x.trigger, 0)}`,
        `F.DURATION_MS = ${lua(x.durationMs, 0)}`,
        `F.SAW_SECRET = ${lua(x.sawSecret, 0)}`,
        `F.SPEC_ID = ${lua(x.specID, 0)}`,
        `F.REQUESTED = ${lua(x.requested, 0)}`,
        `F.STILL_WAITING = ${lua(x.stillWaiting, 0)}`,
        `F.WAIT_TIMED_OUT = ${lua(x.waitTimedOut, 0)}`,
        `F.JOURNAL = ${lua(x.journal, 0)}`,
        '',
        '-- GetCombatRating / GetCombatRatingBonus / GetCombatRatingBonusForCombatRatingValue,',
        "-- per rating: the character's own rating and percent, and the six probe values.",
        `F.RATING = ${lua(x.rating, 0)}`,
        `F.MASTERY_EFFECT = ${lua(x.masteryEffect, 0)}`,
        `F.SPELL_BONUS_HEALING = ${lua(x.spellBonusHealing, 0)}`,
        `F.INTELLECT = ${lua(x.intellect, 0)}`,
        `F.HAS_SECRET_RESTRICTIONS = ${lua(x.hasSecretRestrictions, 0)}`,
        `F.SHOULD_UNIT_STATS_BE_SECRET = ${lua(x.shouldUnitStatsBeSecret, 0)}`,
        `F.COMBAT_LOG_RESTRICTED = ${lua(x.combatLogRestricted, 0)}`,
        '',
        "-- The 80 items in the snapshot's order: 15 worn, 25 bag, 40 journal. `stats`",
        "-- is `strippedStats`, the client's answer for `strippedLink`; `level` is",
        "-- GetDetailedItemLevelInfo's first return for the link (the level `stats` is",
        "-- at), `journalItemLevel` the walk's own level for a journal row.",
        `F.ROWS = ${lua(x.rows, 0)}`,
        '',
        '-- The six trinket tooltips, line type and left text.',
        `F.TOOLTIPS = ${lua(x.tooltips, 0)}`,
    ];
    return head.join('\n') + '\n' + INSTALL;
}

function run(argv) {
    const inputRel = argv[0] || DEFAULT_IN;
    const outRel = argv[1] || DEFAULT_OUT;
    const raw = fs.readFileSync(path.resolve(REPO, inputRel));
    const sha = crypto.createHash('sha256').update(raw).digest('hex');
    const text = render(extract(raw.toString('utf8')), inputRel, sha, raw.length);
    return { text, outPath: path.resolve(REPO, outRel), sha };
}

if (require.main === module) {
    try {
        const r = run(process.argv.slice(2));
        fs.writeFileSync(r.outPath, r.text);
        console.log(`wrote ${r.outPath} from sha256 ${r.sha}`);
    } catch (err) {
        console.error(`extract-itemstats: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, extract, render, lua };
