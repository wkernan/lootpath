// Writes tools/engine/out/EngineWeights.dev.lua in E-0c's file shape
// (`Data/EngineWeights.lua`, WKE-672) from the structure run's fits - schema
// version 2 since E-4 (WKE-708): `role`, `primaryStat`, `stats`, `method`,
// `derivedAt` and `tiers` are the spec's own; `patch` and `dr` stay
// file-level (docs/OWN-ENGINE.md section 5).
//
// DEV ONLY. The file is gitignored, `.pkgmeta` ignores all of `tools/`, and
// the header says so; it exists so a LOCAL install can be pointed at weights
// fitted to QE Live's own exports for one compare run (README).
'use strict';

function luaString(value) {
    let out = '"';
    const text = String(value);
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        const code = text.charCodeAt(i);
        if (ch === '"') out += '\\"';
        else if (ch === '\\') out += '\\\\';
        else if (ch === '\n') out += '\\n';
        else if (ch === '\r') out += '\\r';
        else if (code < 0x20 || code === 0x7f) out += '\\' + String(code).padStart(3, '0');
        else out += ch;
    }
    return out + '"';
}

const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;
const LUA_KEYWORDS = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);

// A JS object's keys are strings and stay strings (`bands = { ["10"] = ... }`);
// a Map is how a numeric key is written (`specs = { [105] = ... }`).
function luaKey(k) {
    if (typeof k === 'number') return `[${k}]`;
    if (IDENT.test(k) && !LUA_KEYWORDS.has(k)) return k;
    return `[${luaString(k)}]`;
}

function luaValue(v, indent) {
    const pad = '    '.repeat(indent);
    if (v === null || v === undefined) return 'nil';
    if (typeof v === 'boolean') return v ? 'true' : 'false';
    if (typeof v === 'number') {
        if (!Number.isFinite(v)) throw new Error(`refusing to write a non-finite number: ${v}`);
        return String(v);
    }
    if (typeof v === 'string') return luaString(v);
    if (Array.isArray(v)) {
        if (!v.length) return '{}';
        return `{\n${v.map((x) => `${pad}    ${luaValue(x, indent + 1)},`).join('\n')}\n${pad}}`;
    }
    const entries = (v instanceof Map ? [...v.entries()] : Object.entries(v)).filter(([, x]) => x !== undefined && x !== null);
    if (!entries.length) return '{}';
    return `{\n${entries.map(([k, x]) => `${pad}    ${luaKey(k)} = ${luaValue(x, indent + 1)},`).join('\n')}\n${pad}}`;
}

// The tier rule as EngineScore reads it (E-0i, WKE-680): `tiers = { [setID] =
// { [pieces] = { mult } } }`, the shape of Data/EngineWeights.lua and the one
// `tierOf` in Lootpath/Modules/EngineScore.lua walks. EngineScore ADDS the
// bonuses a set has reached before it multiplies - mult = 1 + sum(mult - 1)
// over the thresholds reached - so `[2] = 1 + twoPiece` and `[4] = 1 +
// fourPiece` give 1 + twoPiece at two pieces and 1 + twoPiece + fourPiece at
// four, score.js's `tierMultiplier`. The fit's own `{ setIDs, twoPiece,
// fourPiece, forceTier }` stays inside the tool (the fit JSON, score.js);
// before E-0i it was written into the Lua file too, EngineScore found no
// numeric setID in it, and every fitted compare ran with a multiplier of 1.
function luaTiers(tiers) {
    if (!tiers || !Array.isArray(tiers.setIDs) || !tiers.setIDs.length) throw new Error('no tier set: --tier-sets names at least one setID');
    for (const [name, v] of [['--tier2', tiers.twoPiece], ['--tier4', tiers.fourPiece]]) {
        if (typeof v !== 'number' || !Number.isFinite(v)) throw new Error(`${name} must be a finite number, got ${v}`);
    }
    const out = new Map();
    for (const id of tiers.setIDs) {
        if (!Number.isInteger(id)) throw new Error(`--tier-sets: ${id} is not a setID`);
        out.set(
            id,
            new Map([
                [2, { mult: 1 + tiers.twoPiece }],
                [4, { mult: 1 + tiers.fourPiece }],
            ])
        );
    }
    return out;
}

// The one spec the fit tool fits: Restoration Druid, QE Live's own
// (GetSpecializationInfo's specID 105, role "HEALER"; Intellect; the stat list
// EngineScore summed before version 2 made it per spec, in the same order).
const RESTORATION = Object.freeze({
    specID: 105,
    role: 'HEALER',
    primaryStat: 'int',
    stats: Object.freeze(['int', 'haste', 'crit', 'mastery', 'vers', 'leech']),
});

// bandKey(fit) -> the key inside `bands` (a key level for Dungeon, the raid
// difficulty list for Raid). When two documents share a band, the later
// `exportedAt` wins and the other is listed under `superseded`.
function buildTable(fits, meta) {
    const content = {};
    const superseded = [];
    const sorted = fits.slice().sort((a, b) => String(a.fit.exportedAt).localeCompare(String(b.fit.exportedAt)));
    for (const { fit, band } of sorted) {
        const ct = (content[fit.contentType] = content[fit.contentType] || { bands: {} });
        if (ct.bands[band]) superseded.push(ct.bands[band].fittedTo);
        ct.bands[band] = {
            baseValue: fit.baseValue,
            weights: { ...fit.weights },
            assumedFinish: meta.assumedFinish || {},
            assumedBuffs: meta.assumedBuffs || {},
            fittedTo: fit.document,
            r2: fit.overall.r2,
            mae: fit.overall.mae,
        };
    }
    const resto = {
        role: RESTORATION.role,
        primaryStat: RESTORATION.primaryStat,
        stats: RESTORATION.stats.slice(),
        method: 'fit-to-qe-exports',
        derivedAt: meta.derivedAt,
        ...content,
        tiers: luaTiers(meta.tiers),
    };
    return {
        schema: 'lootpath-engine-weights',
        version: 2,
        devOnly: true,
        patch: meta.patch,
        fittedTo: meta.documents,
        superseded,
        specs: new Map([[RESTORATION.specID, resto]]),
        dr: meta.dr,
    };
}

function render(table, meta) {
    const docs = meta.documents.map((d) => `--   ${d.file}  sha256 ${d.sha256}`).join('\n');
    return [
        '-- DEV ONLY - never ship.',
        '--',
        '-- Written by tools/engine/fit-weights.js (E-0e, WKE-674): weights FITTED to',
        "-- QE Live's own Upgrade Finder exports, the structure run. A diagnostic, not a",
        '-- shipping file: it is gitignored, .pkgmeta never packages tools/, and it is',
        '-- copied over Data/EngineWeights.lua only in a LOCAL install for one compare',
        '-- run (tools/engine/README.md). Regenerate it; never edit it.',
        '--',
        '-- Fitted to:',
        docs,
        // E-0m (WKE-705): said only when used, so a plain run's file is unchanged.
        ...(meta.compareVectors || (meta.balance && meta.balance !== 'none') ? ['--', `-- Stored compare vectors read (--compare): ${meta.compareVectors || 0}; balance: ${meta.balance || 'none'}.`] : []),
        '',
        'local _, ns = ...',
        '',
        `ns.engineWeights = ${luaValue(table, 0)}`,
        '',
    ].join('\n');
}

// --- SimC entries (E-7, WKE-710) ---------------------------------------------
// tools/simc writes DPS and tank specs into the same version 2 shape through
// these, so there is one writer of the weights file, not two.

// No tier bonus is measured by a scale-factor run, and EngineScore.Load
// refuses a spec without `tiers` (TiersProblem). Set -1 is carried by no item
// and a multiplier of 1 changes nothing: the placeholder file's convention.
const NO_TIER_SET = -1;
function neutralTiers() {
    return new Map([[NO_TIER_SET, new Map([[2, { mult: 1 }], [4, { mult: 1 }]])]]);
}

// simcSpecEntry(byContent) -> one spec's version 2 entry from tools/simc's
// intermediate files (`lootpath-simc-scale-factors` v1), keyed by content type
// (`{ Raid: <Patchwerk>, Dungeon: <DungeonSlice> }`). Each content type gets
// ONE band, `all`: key-level scaling is not modelled. The weights are SimC's,
// per POINT of each stat (`unit`), not per percent of a rating: the band says
// so and nothing reads a SimC entry until E-6. `baseValue` is 0: a scale
// factor is a slope at the sample profile, and no intercept is measured.
function simcSpecEntry(byContent) {
    const parts = Object.entries(byContent).filter(([, e]) => e);
    if (!parts.length) throw new Error('no SimC entry to write');
    const [, first] = parts[0];
    for (const [ct, e] of parts) {
        if (e.schema !== 'lootpath-simc-scale-factors' || e.version !== 1) throw new Error(`${ct}: not a tools/simc file (schema ${e.schema} v${e.version})`);
        for (const k of ['specID', 'role', 'primaryStat', 'patch']) {
            if (e[k] !== first[k]) throw new Error(`${ct}: ${k} is ${e[k]}, the other content type's is ${first[k]}`);
        }
        if (JSON.stringify(e.stats) !== JSON.stringify(first.stats)) throw new Error(`${ct}: stats differ between content types`);
        if (e.simc.gitRevision !== first.simc.gitRevision) throw new Error(`${ct}: SimC build differs between content types`);
        for (const k of e.stats) {
            if (typeof e.weights[k] !== 'number' || !Number.isFinite(e.weights[k])) throw new Error(`${ct}: no weight for ${k}`);
        }
    }
    const entry = {
        role: first.role,
        primaryStat: first.primaryStat,
        stats: first.stats.slice(),
        method: 'simc',
        derivedAt: parts.map(([, e]) => e.derivedAt).sort().pop(),
        source: first.source,
        simc: { version: first.simc.version, gitRevision: first.simc.gitRevision, wowVersion: first.simc.wowVersion },
    };
    for (const [ct, e] of parts) {
        entry[ct] = {
            bands: {
                all: {
                    baseValue: 0,
                    unit: e.unit,
                    weights: Object.fromEntries(e.stats.map((k) => [k, e.weights[k]])),
                    errors: Object.fromEntries(e.stats.map((k) => [k, e.factors[e.value.metric].stats[k].error])),
                    value: { metric: e.value.metric, mean: e.value.mean, error: e.value.error },
                    fight: e.fight,
                    iterations: e.settings.iterations,
                    profile: e.profile.sha256,
                    assumedFinish: {},
                    assumedBuffs: {},
                },
            },
        };
    }
    entry.tiers = neutralTiers();
    return entry;
}

// buildSimcTable(specs, meta) -> a version 2 table of SimC entries.
// `specs` is a Map specID -> simcSpecEntry(); every intermediate must be for
// the same game patch (meta.patch), the one file-level `patch`.
function buildSimcTable(specs, meta) {
    return {
        schema: 'lootpath-engine-weights',
        version: 2,
        devOnly: true,
        patch: meta.patch,
        specs,
        dr: meta.dr,
    };
}

function renderSimc(table, meta) {
    const runs = meta.inputs.map((i) => `--   ${i.file}  sha256 ${i.sha256}`).join('\n');
    return [
        '-- DEV ONLY - never ship.',
        '--',
        "-- Written by tools/simc/write-weights.js (E-7, WKE-710): stat weights from",
        "-- SimulationCraft's own scale factors over its sample profiles, run by us. Weights",
        '-- are per POINT of each stat (`unit`), baseValue 0, no tier bonus measured (set',
        '-- -1). Gitignored; .pkgmeta never packages tools/. Regenerate it; never edit it.',
        '--',
        '-- From:',
        runs,
        '',
        'local _, ns = ...',
        '',
        `ns.engineWeights = ${luaValue(table, 0)}`,
        '',
    ].join('\n');
}

module.exports = { luaString, luaValue, luaTiers, buildTable, render, RESTORATION, NO_TIER_SET, simcSpecEntry, buildSimcTable, renderSimc };
