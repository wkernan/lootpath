'use strict';

// E-0f (WKE-676): spec/fixtures/engine/itemstats-real.lua is what
// extract-itemstats.js writes from the committed transcript, byte for byte.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const { run } = require('../extract-itemstats');

test('the committed real-stats fixture is the extraction of the committed transcript', () => {
    const r = run([]);
    assert.equal(r.sha, 'ecb69e7e15345b4ae576a80b2ff5ef23fca1ad9f182135af7965f4e27659cac8');
    const committed = fs.readFileSync(r.outPath, 'utf8');
    assert.equal(committed, r.text);
    // 80 rows: 15 worn, 25 bag, 40 journal.
    for (const [source, n] of [['worn', 15], ['bag', 25], ['journal', 40]]) {
        assert.equal(r.text.split(`source = "${source}",`).length - 1, n, source);
    }
});
