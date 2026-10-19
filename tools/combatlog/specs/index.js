// The healer specs the combat-log weights tool knows, by the client's spec ID
// (E-5b, WKE-713). attribute.js and entry.js read a spec's spell table,
// constants and metadata through this registry; neither names Restoration (or
// any spec) directly. Adding a second spec is a new module beside
// restoration.js and one more line here, not a change to either of those
// files.
'use strict';

const restoration = require('./restoration');

const SPECS = new Map([[restoration.specID, restoration]]);

module.exports = { SPECS };
