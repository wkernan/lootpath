#!/usr/bin/env node
// Extracts spec/fixtures/engine/linklevel-real.lua from the owner's committed
// `capture linklevel` transcript (E-0g step 2, WKE-677). DEV ONLY - nothing
// here ships.
//
//   node extract-linklevel.js [transcript.lua] [out.lua]
//
// Defaults: spec/fixtures/captures/Lootpath-20261001-200927.lua and
// spec/fixtures/engine/linklevel-real.lua. Every value written is one the
// client answered, copied from the transcript through
// tools/companion/lib/lua-savedvariables.js: the 12 candidates (the kept link,
// the walk's level, the link's own level, context and bonus IDs), and for each
// variant (`kept`, `track-replace`, `track-append`) its link and its three
// reads - `before` the walk, `journal` while the Adventure Guide previewed the
// row, `after` the view was put back - as `GetDetailedItemLevelInfo`'s
// returns, `GetItemStats`' table and the tooltip's Item Level and Upgrade
// Level lines. The tooltip's other lines are left out (they are in the
// transcript). Nothing is computed, rounded or invented; the output is
// labelled with the transcript's sha256 and a test re-runs this script and
// compares it byte for byte with the committed fixture.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { parseSavedVariables, luaArray } = require('../companion/lib/lua-savedvariables');
const { lua } = require('./extract-itemstats');

const REPO = path.join(__dirname, '..', '..');
const DEFAULT_IN = path.join('spec', 'fixtures', 'captures', 'Lootpath-20261001-200927.lua');
const DEFAULT_OUT = path.join('spec', 'fixtures', 'engine', 'linklevel-real.lua');

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

function read(r) {
    if (!r) return null;
    return {
        detailedLevel: probe(r.detailedLevel),
        stats: r.stats && r.stats[1] ? r.stats[1] : null,
        itemLevelLine: r.itemLevelLine === undefined ? null : r.itemLevelLine,
        upgradeLevelLine: r.upgradeLevelLine === undefined ? null : r.upgradeLevelLine,
    };
}

function opt(v) {
    return v === undefined ? null : v;
}

function extract(text) {
    const sv = parseSavedVariables(text);
    const caps = sv.LootpathDB.global.captures;
    const snaps = luaArray(caps.linklevel || {});
    if (snaps.length !== 1) throw new Error(`expected one linklevel snapshot, found ${snaps.length}`);
    const snap = snaps[0];
    const data = snap.data;
    const candidates = luaArray(data.candidates).map((c) => ({
        itemID: c.itemID,
        name: nameOf(c.link),
        link: c.link,
        slot: opt(c.slot),
        instanceID: opt(c.instanceID),
        instanceName: opt(c.instanceName),
        encounterID: opt(c.encounterID),
        difficultyID: opt(c.difficultyID),
        isRaid: opt(c.isRaid),
        walkLevel: c.walkLevel,
        ownLevel: c.ownLevel,
        previewMythicPlusLevel: opt(c.previewMythicPlusLevel),
        context: opt(c.context),
        bonusIDs: luaArray(c.bonusIDs || {}),
        trackSteps: c.trackSteps,
        trackNote: opt(c.trackNote),
        live: c.live
            ? {
                  found: opt(c.live.found),
                  link: opt(c.live.link),
                  sameAsKept: opt(c.live.sameAsKept),
                  walkDetailedLevel: probe(c.live.walkDetailedLevel),
                  previewLevel: opt(c.live.previewLevel),
              }
            : null,
        variants: luaArray(c.variants).map((v) => ({
            rule: v.rule,
            link: v.link,
            bonusID: opt(v.bonusID),
            track: opt(v.track),
            step: opt(v.step),
            trackLevel: opt(v.trackLevel),
            before: read(v.before),
            journal: read(v.journal),
            after: read(v.after),
        })),
    }));
    const walk = data.walk || {};
    return {
        capturedAt: snap.capturedAt,
        capturedAtLocal: snap.capturedAtLocal,
        build: probe(snap.build),
        trigger: snap.trigger,
        durationMs: snap.durationMs,
        sawSecret: snap.sawSecret,
        journal: {
            rowsWithLink: data.journal.rowsWithLink,
            differing: data.journal.differing,
            differingByDifficulty: data.journal.differingByDifficulty,
            taken: data.journal.taken,
            max: data.journal.max,
            cacheEntries: luaArray(data.journal.cacheEntries).map((e) => ({ key: e.key, build: e.build, walkAt: e.walkAt })),
        },
        walk: {
            targets: walk.targets,
            durationMs: walk.durationMs,
            timeouts: walk.timeouts,
            itemDataTimeouts: walk.itemDataTimeouts,
            pendingRowsFinalRead: walk.pendingRowsFinalRead,
            secretsSeen: walk.secretsSeen,
        },
        viewStateBefore: {
            difficulty: probe(data.viewStateBefore && data.viewStateBefore.difficulty),
            tier: probe(data.viewStateBefore && data.viewStateBefore.tier),
            lootFilter: probe(data.viewStateBefore && data.viewStateBefore.lootFilter),
        },
        selectedTier: opt(data.selectedTier),
        candidates,
    };
}

// The fixed half of the file: how a spec puts the transcript on a stub world.
const INSTALL = `
-- Registers every REBUILT link (\`track-replace\`, \`track-append\`) on a stub
-- world as the client answered it - GetItemInfo's name, link, quality and
-- level, GetDetailedItemLevelInfo's three returns and GetItemStats' table - but
-- only when its three reads (before, journal, after) answered the same level:
-- every rebuilt link in the transcript did, and a read that follows the view
-- is not one a stub can answer with one value. The kept links are not
-- registered: their reads followed the Adventure Guide's view (292 before and
-- 305 during and after for a keystone link, 305 before and 219 after for a
-- raid link) and itemstats-real.lua already holds them as that morning's
-- client read them.
--
-- The socket count is the transcript's \`EMPTY_SOCKET_PRISMATIC\`: the capture
-- did not ask GetItemNumSockets, and on all 80 items of the 2026-10-01 09:26
-- transcript the two answered the same count (ARCHITECTURE.md section 7, E-0f).
-- An item already on the world is merged into, never replaced.
function F.install(world)
    for _, candidate in ipairs(F.CANDIDATES) do
        for _, variant in ipairs(candidate.variants) do
            local b, j, a = variant.before, variant.journal, variant.after
            local level = b and b.detailedLevel and b.detailedLevel[1]
            if
                variant.rule ~= "kept"
                and level
                and j.detailedLevel[1] == level
                and a.detailedLevel[1] == level
            then
                local entry = world.items[variant.link] or {}
                entry.info = { candidate.name, variant.link, 4, level, n = 18 }
                entry.level = level
                entry.detailed = b.detailedLevel
                world.items[variant.link] = entry
                world.itemStats[variant.link] = b.stats
                world.itemSockets[variant.link] = b.stats.EMPTY_SOCKET_PRISMATIC or 0
                world.itemDataCached[candidate.itemID] = true
            end
        end
    end
end

-- The variant of a candidate by rule and bonus ID (nil for \`kept\`).
function F.variant(candidate, rule, bonusID)
    for _, variant in ipairs(candidate.variants) do
        if variant.rule == rule and variant.bonusID == bonusID then
            return variant
        end
    end
    return nil
end

return F
`;

function render(x, inputRel, sha, bytes) {
    const head = [
        '-- spec/fixtures/engine/linklevel-real.lua (E-0g step 2, WKE-677)',
        '--',
        '-- GENERATED - do not edit. `node tools/engine/extract-linklevel.js` wrote it',
        `-- from ${inputRel.replace(/\\/g, '/')}`,
        `-- (sha256 ${sha}, ${bytes} bytes as committed),`,
        "-- the owner's `capture linklevel` on the Druid, 2026-10-01. Every value is the",
        "-- client's answer copied through tools/companion/lib/lua-savedvariables.js:",
        '-- nothing computed, rounded or invented. tools/engine/test/extract.test.js',
        '-- re-runs the script and compares the bytes.',
        '',
        'local F = {}',
        '',
        `F.SOURCE = ${lua(inputRel.replace(/\\/g, '/'), 0)}`,
        `F.SHA256 = ${lua(sha, 0)}`,
        `F.BYTES = ${bytes}`,
        `F.CAPTURED_AT = ${lua(x.capturedAt, 0)}`,
        `F.CAPTURED_AT_LOCAL = ${lua(x.capturedAtLocal, 0)}`,
        `F.BUILD = ${lua(x.build, 0)}`,
        `F.TRIGGER = ${lua(x.trigger, 0)}`,
        `F.DURATION_MS = ${lua(x.durationMs, 0)}`,
        `F.SAW_SECRET = ${lua(x.sawSecret, 0)}`,
        `F.JOURNAL = ${lua(x.journal, 0)}`,
        `F.WALK = ${lua(x.walk, 0)}`,
        `F.VIEW_STATE_BEFORE = ${lua(x.viewStateBefore, 0)}`,
        `F.SELECTED_TIER = ${lua(x.selectedTier, 0)}`,
        '',
        "-- The 12 candidates in the snapshot's order. `walkLevel` is the level the",
        "-- walk listed the row at, `ownLevel` the kept link's level when the capture",
        '-- chose it; each variant carries its three reads.',
        `F.CANDIDATES = ${lua(x.candidates, 0)}`,
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
        console.error(`extract-linklevel: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, extract, render };
