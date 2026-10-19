// Restoration's spell table, buffs and constants now live in
// lib/specs/105-restoration-druid.js (E-5b, WKE-713); this file is a
// one-line re-export so test/spells.test.js, test/probe.test.js, lib/probe.js
// and probe.js keep reading these names unchanged (Decision 4).
'use strict';

module.exports = require('./specs/105-restoration-druid');
