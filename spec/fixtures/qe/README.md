# QE Live exports (`qe-live-droptimizer` and `qe-live-upgradefinder`, both v1)

Two kinds of file live here - hand-built and genuine - and the difference
matters more than which schema a file carries.

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
  `bonusHPS`) and the `version: 1` number.
- `qe-droptimizer-Hotornot-cjyztichdhze.json` - exported 2026-09-07T01:01:35Z,
  **Restoration Druid**, **contentType `Dungeon`** (QE Live's name for the
  Mythic+ side; there is no "Mythic+" content type), with bag and bank items
  clicked on the gear screen, so it carries **12 `differentials`** (one with a
  zero delta, the rest worse in both signs) and a top set that differs from the
  worn set in five slots. Still no `isVault` item: the weekly reset had not
  generated rewards. The export with vault options is Tuesday 2026-09-08's.

- `qe-droptimizer-Hotornot-uliwcyoomcub.json` (Dungeon) and
  `qe-droptimizer-Hotornot-ebeaqmvbnpqa.json` (Raid) - **written by the
  companion**, 2026-09-08 17:45 UTC, from the after-reset captures (WKE-533,
  the two-refresh loop; extracted unedited from the `Data/QEVerdict.lua` it
  wrote). The first exports with a vault option: `isVault: true` on Lightgrasp
  Worldroot 251935 (bonus IDs 6652/12841) **in the top set** of both, at QE
  Live's `level` 321 - the client reports the same link at item level 305; QE
  Live's importer values a vault option at its assumed upgrade (its
  auto-upgrade-vault setting). 15 items, 12 differentials each; scores
  5647.977 (Dungeon) and 5860.499 (Raid).

## The three named scenarios (C-6, WKE-540)

Six documents from **one companion run**, 2026-09-09 01:15 UTC, extracted
unedited from the `Data/QEVerdict.lua` it wrote. Same gear, same profile
(15 equipped / 32 bags / 0 bank / 4 vault, 158 lines), three questions - QE
Live's three import checkboxes, set explicitly per scenario and read back off
his page before every Submit. The four vault options behind them are the ones
in the 2026-09-08 12:45 capture: Preyhunter's Lantern 275547 (Offhand 305),
Lightgrasp Worldroot 251935 (2H Weapon 305), Scavenger's Spaulders 251146
(Shoulder 308), Graft of the Domanaar 251234 (Neck 308).

| file | content type | scenario | boxes (all / vault / catalyze) | top set score |
|---|---|---|---|---|
| `qe-droptimizer-Hotornot-hldibnbaajft.json` | Dungeon | `asOffered` | off / off / off | 5544.654 |
| `qe-droptimizer-Hotornot-xacelnbtfevd.json` | Raid | `asOffered` | off / off / off | 5757.608 |
| `qe-droptimizer-Hotornot-xrjevewtwqsw.json` | Dungeon | `catalyzed` | off / off / **on** | 5724.919 |
| `qe-droptimizer-Hotornot-kqaeqimkpsfw.json` | Raid | `catalyzed` | off / off / **on** | 5928.158 |
| `qe-droptimizer-Hotornot-qqrqsbudcszh.json` | Dungeon | `maxed` | **on / on / on** | 5853.843 |
| `qe-droptimizer-Hotornot-ddveeejxcsvb.json` | Raid | `maxed` | **on / on / on** | 6055.955 |

All six scores reproduce the 2026-09-08 ~13:20 spike exactly (ARCHITECTURE.md
9), so the companion's scenario driver and `run-fork.js --scenario` agree.

**What the catalyzed runs prove about the join.** `autoCatalyze` does not change
an item: `SimCImportEngine.ts` keeps the original and ADDS a clone, and
`Item.convertToTier` gives the clone the tier piece's item ID and set ID while
keeping the slot, the level, the bonus IDs and the `vaultItem` flag. In these
files the vault's Scavenger's Spaulders `251146` appear as
`271526 @ 308, setId 2057, isVault, bonusIDs [12842, 13440, 6652, 13662, 12699]`
- the Spaulders' own bonus IDs, on a different item ID - **in the top set** of
both `catalyzed` documents. The exact-key join can never find that, which is why
`ns.QEImport.CatalyzedCoverage` looks for his clone by the fields he copied. The
exporter carries neither `catalyzedID` nor `isCatalystItem`, so those fields are
all there is to recognise it by.

**Measured over these six, option by option** (`ns.QEImport.Coverage` then
`CatalyzedCoverage`, Dungeon figures; Raid in brackets):

| option | `asOffered` | `catalyzed` | `maxed` |
|---|---|---|---|
| Lightgrasp Worldroot | 0.5681% behind (0.5471%) | 1.0743% behind (1.0627%) | **in the best set at 321** |
| Scavenger's Spaulders | not ranked | **in the best set, as tier 271526 at 308** | 1.7168% behind as tier at 321 (1.6348%) |
| Preyhunter's Lantern | not ranked | not ranked | not ranked |
| Graft of the Domanaar | not ranked | not ranked | not ranked |

So the answer changes with the question: catalyze and the shoulders win, upgrade
everything and the weapon does. That is the whole of WKE-540, and none of it is
computed here.

`spec/qeimport_spec.lua` reads these files in its "genuine QE Live export" blocks.

## Upgrade Finder exports (`qe-live-upgradefinder` v1, the fork's schema)

Produced headless by `tools/companion-spike/run-fork.js` (WKE-531) from the
owner's `/simc` string of 2026-09-07 18:36 (`spec/fixtures/simc/`), through
the fork's Upgrade Finder with its default settings (`raid: [3]`, `dungeon: 7`).
Committed unedited for WKE-535 (M3-6).

- `qe-upgradefinder-Hotornot-abxrrnezfilt.json` - contentType `Dungeon`,
  exported 2026-09-07T23:40:54Z, 357 items, every one with `source`.
- `qe-upgradefinder-Hotornot-kqyktjywppzw.json` - contentType `Raid`,
  exported 2026-09-07T23:41:09Z, 357 items.

`upgradePercent` is > 0 on 263 listings and 0 on 94, never negative, and
`hpsGain` agrees in sign on every one (positive means better - the opposite of
the Top Gear differentials). Deduplicated to itemID + item level, the Dungeon
file is **315 entries: 228 better, 87 at zero, none worse**.

**Measured for WKE-535 (2026-09-08):** dungeon drops sit at 311 / 321 / 334 for
key level 7 and raid drops at 318 / 324 / 344 for difficulty 3. Joined to the
committed journal walks by itemID + item level, **30 rows gain a number** - all
of them raid drops, whose levels the walk previews too - while 218 rows of the
20:09 cold walk (97 distinct drops) are ranked at an item level the walk does
not show, because the walk previewed key level 10 and the export assumed 7.
See ARCHITECTURE.md 9.

## Upgrade Finder exports at five Mythic+ key levels (M3-10, WKE-545)

Six documents from **one companion run**, 2026-09-08 22:47 UTC, extracted
unedited from the `Data/QEVerdict.lua` it wrote (the same extraction the C-2
contract feeds the addon). C-7 (WKE-543) is what made the run several documents
wide: the companion clicks QE Live's own key selector once per level in
`upgradeFinderKeyLevels` and stamps the level it clicked onto each document.
**The key level is not in the JSON** - the JSON carries `settings.dungeon`,
which is an *index* into his `MPLUS_KEY_REWARDS` table - so a test that needs
the level supplies it the way `ns.Companion` does, from the file's own
`keyLevel` field.

| file | content type | key level | `settings.dungeon` | items | dungeon drop / max / bonus |
|---|---|---|---|---|---|
| `qe-upgradefinder-Hotornot-lrxljklscrjr.json` | Dungeon | +2 | 1 | 357 | 295 / 308 / 321 |
| `qe-upgradefinder-Hotornot-jnjnmzftoppb.json` | Dungeon | +4 | 2 | 357 | 298 / 308 / 321 |
| `qe-upgradefinder-Hotornot-zmtnpejwfewe.json` | Dungeon | +6 | 4 | 290 | 305 / - / 321 |
| `qe-upgradefinder-Hotornot-lttldhvkiqlr.json` | Dungeon | +8 | 6 | 290 | 308 / - / 321 |
| `qe-upgradefinder-Hotornot-wyharestkdyr.json` | Dungeon | +10 | 7 | 357 | 311 / 321 / 334 |
| `qe-upgradefinder-Hotornot-ynfzbppepnzw.json` | Raid | +10 | 7 | 357 | 311 / 321 / 334 |

Every one of them carries the same raid rows (his `raid: [3]` setting is
unchanged across the run) at 318 / 321 / 324 / 334 / 344, which is why the four
documents that are not +6 still rank 30 rows of the committed walk.

**The measurement this set exists for** (`tools/measure-cross-level.lua`, over
the 2026-09-06 20:09 cold walk, 478 drops previewed at keystone 10):

- The client lists a Mythic Keystone drop at **305**; QE Live's **+10** document
  values it at **311**. Neither is Lootpath's to adjust, and joining on the
  exact `itemID@itemLevel` pair against the +10 document alone ranks **30** rows,
  all of them raid drops - which is why every dungeon run read "no drop rated by
  QE Live yet" before M3-10.
- His **+6** document drops at 305, so joining across all five ranks **84** rows
  (54 of them Mythic Keystone), leaving 164 ranked only at another item level.
  The other four documents carry **no** keystone row of this walk at all.
- These are the exports `spec/ufimport_spec.lua` and `spec/upgrademap_spec.lua`
  read in their M3-10 blocks.

The 2026-09-07 pair above (`abxrrnezfilt`, `kqyktjywppzw`) is kept as it is: it
is a different run, with QE Live's default upgrade checkboxes rather than C-5's
explicit pair, and the specs that read it are testing the parser and the
single-document paste path.

## `sample-upgradefinder-v1.json` - hand-built, not from QE Live

Written for M3-6 (WKE-535) by mirroring the fork's exporter field for field.
**No number in it was produced by QE Live.** It covers what the real exports
do not: a **negative** `upgradePercent` (the real files have none), a zero, a
drop listed twice with two drop types, a Delve drop whose `dropType` is `null`
and whose `dropDifficulty` is the empty string, a drop ranked only at an item
level the journal never lists, and an entry with an unusable itemID. Its
itemIDs are ones the committed walks really carry, so the panel join can be
exercised in both directions.

Files here are excluded from luacheck and StyLua (raw third-party payloads,
never linted or formatted).
