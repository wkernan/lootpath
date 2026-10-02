#!/usr/bin/env node
// Extracts spec/fixtures/engine/effects-real.lua from the owner's
// `capture effects` transcript (E-3b, WKE-684). DEV ONLY - nothing here ships.
//
//   node extract-effects.js <transcript.lua> [out.lua]
//
// There is no default transcript yet: the capture is built and has not run in
// a client. Once the owner's pull is committed under spec/fixtures/captures/,
// the follow-up (E-3c) runs this script on it, commits the output beside the
// transcript, and adds a byte-for-byte test to tools/engine/test/extract.test.js
// as E-0f did for extract-itemstats.js.
//
// One record per item, per target, per read - so per itemID per level: where
// the link came from (`journal` row or `owned` copy), the read's rule (`walk` -
// the link rebuilt at the walk's level; `kept` - the link as kept; `next` - one
// track step away), the level asked for, the link read,
// `GetDetailedItemLevelInfo`'s returns, the tooltip's Item Level and Upgrade
// Level lines, and every line whose text starts "Use:" or "Equip:" with the
// NUMBERS in it - as the text the client wrote, in order. Nothing is parsed into
// a value, rounded, summed or invented: "528" stays the string "528", and
// whether it is a stat amount, a duration or a cooldown is the follow-up's
// reading, not this script's. The effect lines are found by their TEXT, not
// their type: the one committed "Use:" line is type 44, which the annotations'
// enum does not list, and no committed line says what type an "Equip:" text has;
// each line's `type` is copied beside it so the transcript can settle that too.
// A read with no link (a level no track step draws) is kept with its `why`.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { parseSavedVariables, luaArray } = require('../companion/lib/lua-savedvariables');
const { lua } = require('./extract-itemstats');

const REPO = path.join(__dirname, '..', '..');
const DEFAULT_OUT = path.join('spec', 'fixtures', 'engine', 'effects-real.lua');

// A probe `{ [1] = v, ..., n = count }` kept exactly as stored.
function probe(p) {
    if (!p || typeof p !== 'object') return null;
    const out = { n: p.n };
    for (let i = 1; i <= (p.n || 0); i++) if (p[i] !== undefined) out[i] = p[i];
    return out;
}

function opt(v) {
    return v === undefined ? null : v;
}

// The text with the client's escapes taken out - colour (`|cAARRGGBB` ...
// `|r`) and the plural marker `|4` (the transcript's "1 |4Min:Min; 30
// |4Sec:Sec; Cooldown") - for finding the prefix and the numbers only; the line
// itself is kept raw.
function plain(text) {
    return String(text)
        .replace(/\|c.{8}/g, '')
        .replace(/\|r/g, '')
        .replace(/\|4/g, '');
}

const EFFECT_PREFIX = /^\s*(Use|Equip):/;

// Every run of digits in the text, with any `,` or `.` between digits, as the
// text it is. Never a number.
function numbersIn(text) {
    return plain(text).match(/\d+(?:[.,]\d+)*/g) || [];
}

function effectLines(lines) {
    const out = [];
    luaArray(lines || {}).forEach((line, i) => {
        if (!line || typeof line !== 'object' || typeof line.leftText !== 'string') return;
        const m = plain(line.leftText).match(EFFECT_PREFIX);
        if (!m) return;
        out.push({
            index: i + 1,
            type: opt(line.type),
            prefix: m[1],
            text: line.leftText,
            numbers: numbersIn(line.leftText),
        });
    });
    return out;
}

function record(item, target, read) {
    return {
        itemID: item.itemID,
        name: opt(item.name),
        kind: opt(item.kind),
        source: target.source,
        walkLevel: opt(target.walkLevel),
        ownedLevel: opt(target.ownedLevel),
        difficultyID: opt(target.difficultyID),
        instanceName: opt(target.instanceName),
        location: opt(target.location),
        rule: read.rule,
        level: opt(read.level),
        fromLevel: opt(read.fromLevel),
        track: opt(read.track),
        fromStep: opt(read.fromStep),
        toStep: opt(read.toStep),
        link: opt(read.link),
        why: opt(read.why),
        detailedLevel: probe(read.detailedLevel),
        itemLevelLine: opt(read.itemLevelLine),
        upgradeLevelLine: opt(read.upgradeLevelLine),
        lineCount: lineCount(read.tooltipLines),
        effects: effectLines(read.tooltipLines),
        // The second read of the same tooltip, taken after the capture's pause.
        again: read.again
            ? {
                  itemLevelLine: opt(read.again.itemLevelLine),
                  upgradeLevelLine: opt(read.again.upgradeLevelLine),
                  lineCount: lineCount(read.again.tooltipLines),
                  effects: effectLines(read.again.tooltipLines),
              }
            : null,
    };
}

function lineCount(lines) {
    return lines && typeof lines === 'object' ? luaArray(lines).length : null;
}

function extract(text) {
    const sv = parseSavedVariables(text);
    const caps = sv.LootpathDB.global.captures;
    const snaps = luaArray(caps.effects || {});
    if (snaps.length !== 1) throw new Error(`expected one effects snapshot, found ${snaps.length}`);
    const snap = snaps[0];
    const data = snap.data;
    const records = [];
    for (const item of luaArray(data.items)) {
        for (const target of luaArray(item.targets)) {
            for (const read of luaArray(target.reads)) records.push(record(item, target, read));
        }
    }
    return {
        capturedAt: snap.capturedAt,
        capturedAtLocal: snap.capturedAtLocal,
        build: probe(snap.build),
        trigger: snap.trigger,
        durationMs: snap.durationMs,
        sawSecret: snap.sawSecret,
        linkLevelRule: opt(data.linkLevelRule),
        waitTimedOut: opt(data.waitTimedOut),
        stillWaiting: opt(data.stillWaiting),
        items: luaArray(data.items).length,
        missing: luaArray(data.missing || {}).map((m) => ({ itemID: m.itemID, name: opt(m.name) })),
        records,
    };
}

function render(x, inputRel, sha, bytes) {
    const head = [
        '-- spec/fixtures/engine/effects-real.lua (E-3b, WKE-684)',
        '--',
        '-- GENERATED - do not edit. `node tools/engine/extract-effects.js` wrote it',
        `-- from ${inputRel.replace(/\\/g, '/')}`,
        `-- (sha256 ${sha}, ${bytes} bytes as committed),`,
        "-- the owner's `capture effects`. Every value is the client's answer copied",
        '-- through tools/companion/lib/lua-savedvariables.js; the `numbers` are the',
        "-- effect text's digits AS TEXT - nothing computed, rounded or invented.",
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
        `F.LINK_LEVEL_RULE = ${lua(x.linkLevelRule, 0)}`,
        `F.WAIT_TIMED_OUT = ${lua(x.waitTimedOut, 0)}`,
        `F.STILL_WAITING = ${lua(x.stillWaiting, 0)}`,
        `F.ITEMS = ${x.items}`,
        `F.MISSING = ${lua(x.missing, 0)}`,
        '',
        "-- One record per item, per target, per read, in the snapshot's order.",
        `F.RECORDS = ${lua(x.records, 0)}`,
        '',
        'return F',
    ];
    return head.join('\n') + '\n';
}

function run(argv) {
    const inputRel = argv[0];
    if (!inputRel) throw new Error('usage: node extract-effects.js <transcript.lua> [out.lua]');
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
        console.error(`extract-effects: ${err.message}`);
        process.exit(1);
    }
}

module.exports = { run, extract, render, numbersIn, effectLines };
