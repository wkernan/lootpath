// The healer specs the combat-log weights tool knows, by the client's spec
// ID (E-5b, WKE-713). lib/attribute.js and lib/entry.js read a spec's spell
// table, buffs, constants and identity through get()/ids(); neither names
// Restoration (or any spec) directly. A second real healer spec is a new
// module beside 105-restoration-druid.js plus one more line in SHIPPED
// below, not a change to attribute.js or entry.js - except its mastery
// tracker/gain contract must fit the same shape (lib/attribute.js calls
// mastery.createTracker/mastery.gain generically; it does not know Harmony's
// stacking-aura formula, but it does assume there is a tracker object with
// onCombatantInfo/onAura/onUnitDied/diag()/countFor(target) - the last of
// these is also what walk()'s onHeal diagnostic callback reports as `n`,
// for lib/probe.js).
'use strict';

const restoration = require('./105-restoration-druid');

// The specs real logs may carry. register()/unregister() (below) add and
// remove others, live - for tests only; never call them outside a test.
const SHIPPED = [restoration];

const registry = new Map(SHIPPED.map((m) => [m.identity.specID, m]));

function get(specID) {
    return registry.get(specID) || null;
}

function ids() {
    return [...registry.keys()].sort((a, b) => a - b);
}

// Test-only: adds a spec module live, so get()/ids() see it immediately -
// no module-load-time snapshot to go stale. Used to register a toy spec
// (test/fixtures/toy-spec.js) that proves the registry's contract without a
// real second spec's data. Never call this outside a test.
function register(module) {
    registry.set(module.identity.specID, module);
}

// Test-only cleanup for register(): removes a spec module added that way.
function unregister(specID) {
    registry.delete(specID);
}

module.exports = { get, ids, register, unregister };
