// SavedVariables -> SimulationCraft text, for the companion.
//
// The builder itself is S-2's (WKE-532, `simc-profile.js` beside this file,
// with `lua-savedvariables.js` as its reader). C-1 lifted both out of
// `tools/companion-spike/` rather than keeping a second copy: S-2 mirrors the
// SimulationCraft addon's own OFFSET_* constants and slot tables, reproduces the
// client's `# Checksum:` with adler32, and enforces QE Live's two line-index
// rules, and none of that is worth having twice.
//
// This file is the thin part C-1 adds around it:
//  - one shape for the CLI to read, `{ ok, text, warnings, ... }` rather than a
//    throw, so a bad transcript is a named exit code and not a stack trace;
//  - the spec check, which is C-1's own finding (see specMismatch below).
'use strict';

const { readTranscript, buildProfile } = require('./simc-profile');

// The capture the addon does not write yet: one snapshot carrying the header
// facts outright instead of the companion inferring them from `env`. Named in
// one place so a later issue can add it and only this constant moves.
const PROFILE_CAPTURE = 'profile';

// A Probe pack is `{ value, n = 1 }` (ns.Probe, Core.lua); `{ absent = true }`
// and `{ error = "..." }` have no first value.
function packValue(pack, index) {
    if (!pack || typeof pack !== 'object') return undefined;
    return pack[index || 1];
}

// `text` is the SavedVariables file, verbatim.
function build(text, options) {
    const opts = options || {};
    let transcript;
    try {
        transcript = readTranscript(text, opts);
    } catch (e) {
        return { ok: false, reason: e.message, wanted: PROFILE_CAPTURE };
    }
    let built;
    try {
        built = buildProfile(transcript, { includeBank: opts.includeBank !== false });
    } catch (e) {
        return { ok: false, reason: e.message, wanted: PROFILE_CAPTURE };
    }

    const env = transcript.env;
    const warnings = built.missing.map(
        (field) => `the SavedVariables carry no ${field}; the line is left out rather than written empty`
    );
    if (!transcript.vault || !Object.keys((transcript.vault.data || {}).rewardLinks || {}).length) {
        warnings.push('no generated Great Vault reward in the SavedVariables, so the profile has no vault section');
    }

    return {
        ok: true,
        text: built.text,
        warnings,
        counts: built.counts,
        capturedAtLocal: built.capturedAtLocal,
        identity: {
            name: env && packValue(env.data.player),
            realm: env && packValue(env.data.realm),
            // GetSpecializationInfo's second return is the spec's own name.
            spec: env && packValue(env.data.specInfo, 2),
        },
    };
}

// QE Live values the spec selected in ITS OWN character panel, not the `spec=`
// line: `runSimC` never reads that line (SimCImportEngine.ts, and S-2's field
// table says the same). Measured 2026-09-08 - a profile written `spec=guardian`
// came back as a "Restoration Druid" report, because that is what the browser
// profile held. So every Top Gear document is checked against the spec the
// SavedVariables recorded, and a disagreement is said out loud with both names:
// the numbers are QE Live's and they are for ITS spec, whatever the client last
// captured.
function specMismatch(verdictSpec, capturedSpec) {
    if (!verdictSpec || !capturedSpec) return null;
    const normalise = (s) => String(s).toLowerCase();
    if (normalise(verdictSpec).includes(normalise(capturedSpec))) return null;
    return `QE Live valued "${verdictSpec}" but the SavedVariables were captured in "${capturedSpec}"; the numbers are for QE Live's spec. Pick the right spec in the fork, or capture again in the spec you play`;
}

module.exports = { build, specMismatch, PROFILE_CAPTURE };
