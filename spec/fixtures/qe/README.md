# QE Live Top Gear exports (`qe-live-droptimizer` v1)

Two kinds of file live here, and the difference matters.

## `sample-handbuilt-v1.json` - hand-built, not from QE Live

Written for M2-1 (WKE-518) by mirroring QE Live's exporter field for field:
`src/General/Modules/TopGear/Report/TopGearJSONExport.ts` on branch `dev`, read
2026-09-06. **No number in it was produced by QE Live.** It exists so the parser
can be tested before a real export exists; it proves the parser handles the
shape the exporter emits, and proves nothing about what QE Live actually sends.

It deliberately covers: a vault item inside `topSet` (`Chest`), a vault item that
appears only in an alternative (`Trinket` in the second differential), two
`Finger` items sharing an itemID at different bonus IDs, unsorted `bonusIDs`,
gems, enchants and a tertiary, and both sign conventions (every differential is
an alternative that is *worse*: `scorePercent > 0`, `hpsDifference < 0`).

## Real exports (WKE-519, owner)

A genuine Top Gear JSON for hotornot, run **in Restoration spec**, downloaded
with QE Live's Download JSON button and committed unedited. Until one lands, the
test that reads it is `pending` in `spec/qeimport_spec.lua`; that pending is
removed in the PR that follows WKE-519.

Files here are excluded from luacheck and StyLua (raw third-party payloads,
never linted or formatted).
