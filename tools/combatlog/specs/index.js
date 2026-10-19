// The healer specs the combat-log weights tool knows, by the client's spec ID
// (E-5b, WKE-713). attribute.js and entry.js read a spec's spell table, buff
// lists, constants and role/primaryStat/stats through this registry; neither
// names Restoration (or any spec) directly for those. Adding a second spec
// with that same shape is a new module beside restoration.js and one more
// line here, not a change to either of those files.
//
// Mastery's formula is not generalised, only its inputs: lib/attribute.js's
// mastery branch still assumes mastery is a count of the player's own
// stacking auras on the target (Harmony's shape), scaled by the spec's own
// stackFactor/CONSTANTS. A spec whose mastery isn't that shape needs that
// branch generalised first - it cannot be added as data alone.
'use strict';

const restoration = require('./restoration');

const SPECS = new Map([[restoration.specID, restoration]]);

module.exports = { SPECS };
