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

A genuine Top Gear JSON for hotornot, produced by QE Live's own engine and
committed unedited. The live site has no Download JSON control (WKE-527), so
the file comes from the owner's fork running locally (`c:\Code\qe-live-fork`,
branch `lootpath/upgrade-finder-export`, Export > Download JSON).

- `qe-droptimizer-Hotornot-cxeiassqdyvz.json` - exported 2026-09-06T21:14:24Z,
  **Restoration Druid**, **contentType `Raid`** (not Mythic+: the owner left the
  fork's default), from a `/simc` taken the same evening with no vault rewards
  available and **no extra items selected** on the gear screen, so `topSet` is
  the 15 equipped items, `differentials` is `[]`, and no item is `isVault`. It
  proves the header, the item shape, the real `stats` block (12 keys: the six
  the hand-built sample has plus `hps`, `dps`, `mana`, `manaPerc`, `allyStats`,
  `bonusHPS`) and the `version: 1` number. A second export with Mythic+ content,
  bag items selected and vault options present is the next fixture to add.

`spec/qeimport_spec.lua` reads this file in its "genuine QE Live export" block.

Files here are excluded from luacheck and StyLua (raw third-party payloads,
never linted or formatted).
