# e5c-followups: the six-key test names its second cause; the fixtures README names the current stripper

## §0
**As of 2026-10-19, evening, E-5c follow-ups (PR open on `main` 58ff299: two of WKE-714's review notes, from Stokowski's code-review stage.)**
- `tools/combatlog/test/committed-keys.test.js`: the failure message and the header comment now say that the pinned figures also move when the `dr` table in `Lootpath/Data/EngineWeights.lua` changes, because `lib/dr.js` reads the rating conversion from there. A PR that regenerates the dev weights file then points at the right cause.
- `spec/fixtures/combatlog/README.md`'s opening paragraph named `anonymise.py` as the stripper; it now names `anonymise.js`, with `anonymise.py` as what stripped the first fixture.

Proven: `TRIM` 0.2 -> 0.25 fails the figures test with the new message; restored, 3/3 pass. No figure changed.
