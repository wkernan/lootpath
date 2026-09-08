# Companion spike S-1 (WKE-531): the local QE Live fork, driven headless

`run-fork.js` proves that a script can do what the owner does by hand in the
fork - paste a `/simc` string, run Top Gear and Upgrade Finder for Dungeon and
Raid, and read each report's JSON - with no human in the loop. It is the shape
the companion (WKE-533) lifts into a module. Nothing of QE Live's is copied
here; the script drives the owner's fork clone at `localhost:3000`.

## Running it

Playwright is deliberately **not** a dependency of this repo or the fork for
the spike. In a scratch directory:

```
npm init -y && npm i playwright && npx playwright install chromium
cp <this repo>/tools/companion-spike/run-fork.js .
node run-fork.js <simc.txt> <outdir> [--headed] [--smoke]
```

The copy matters: Node resolves `require('playwright')` from the SCRIPT's
directory, not the working directory, so running the file in place fails with
MODULE_NOT_FOUND however the scratch directory is set up (measured 2026-09-08).

Playwright 1.63.0; `npx playwright install chromium` downloaded Chrome
Headless Shell 153.0.8010.12 (playwright chromium-headless-shell v1243),
114.6 MiB, into `%LOCALAPPDATA%\ms-playwright\`. The fork must be serving (`npm start` in `c:\Code\qe-live-fork`,
branch `lootpath/upgrade-finder-export`).

## Measured, 2026-09-07 23:40 UTC, cold headless Chromium, the owner's `/simc` string of 18:36 local

| Step | ms |
|---|---|
| page loaded (header rendered) | 2052 |
| welcome dialog: Midnight / Druid / BEGIN! | 612 |
| SimC string imported (dialog closed, no `#SimCError`) | 545 |
| Dungeon Top Gear: 30/30 items selected (44 cards, 15 clicked) | 5240 |
| Dungeon Top Gear: report ready (`/live/report/<id>`) | 1329 |
| Dungeon Top Gear: Copy JSON read (16174 chars) | 538 |
| Dungeon Upgrade Finder: report ready | 1559 |
| Dungeon Upgrade Finder: Copy JSON read (120051 chars) | 1017 |
| Raid Top Gear: 30/30 selected (0 clicked - selection persists) | 1742 |
| Raid Top Gear: report ready | 10230 |
| Raid Top Gear: Copy JSON read (15717 chars) | 522 |
| Raid Upgrade Finder: report ready | 1477 |
| Raid Upgrade Finder: Copy JSON read (119734 chars) | 794 |
| **total** | **27657** |

Outputs: `qe-live-droptimizer` v1 for Dungeon (15 items, 12 differentials) and
Raid (15, 12); `qe-live-upgradefinder` v1 for Dungeon and Raid (357 items
each, every item with `source.instanceId` and `source.encounterId`,
`upgradePercent` > 0 on 263 and == 0 on 94, never negative; `hpsGain` agrees
in sign on every item). The two Upgrade Finder documents are committed under
`spec/fixtures/qe/` for WKE-535; the Top Gear ones are not (the character had
changed since the hand export of 2026-09-06 - the owner equipped the five
swaps - so they are a third real export, not a comparison).

No step needed a non-deterministic wait: every wait is on a URL, a dialog or
an element. The longest was Raid Top Gear's engine run (10.2 s).

## What the fork's UI actually is (every selector names its source file)

- `Import Gear` header button -> `#simcentry` textarea -> `Submit`:
  `SetupAndMenus/SimCraftDialog.js`, labels from `locale/en/translate.json`.
  The header button's accessible name did not resolve as "Import Gear" for
  `getByRole`; the visible text does.
- **A browser with no saved character gets a welcome dialog** ("Welcome to QE
  Live! Select an era" / class tiles / BEGIN!) over the header. The owner never
  sees it (characters live in `localStorage`). The script picks Midnight and
  Druid. Tiles are CSS-uppercased; the DOM text is "Druid".
- **Dungeon/Raid is not a header toggle in this build.**
  `Header/ContentToggle.js` (`aria-label="dungeonLabel"`) is rendered nowhere
  (grep). The switch is the "Content" select on `CharacterPanel.tsx` (~line
  432, MenuItems "Dungeon"/"Raid", dispatching `toggleContent`), and that
  panel renders only inside the analysis pages. `/embellishments` **crashes
  in his code with this character** (`EmbellishmentAnalysis` ->
  `getEmbellishAtLevel` -> `runGenericPPMTrinket` -> `getDiminishedValue`,
  "Cannot read properties of undefined (reading 'length')"), so the script
  uses `/circlet`, which works. The dispatch is global, so Top Gear and Upgrade
  Finder then run for that content type.
- The app is served under `/live/` (the fork's `homepage`), so report URLs are
  `/live/report/<id>` and `/live/upgradereport/`; paths are matched by
  inclusion.
- Top Gear: item cards are `.MuiCardActionArea-root` (`TopGear/MiniItemCard.tsx`);
  an active card's parent class contains `selected`. `Selected Items: n/cap`
  and `Go!` come from `TopGear/TopGear.tsx`; **`topGearCap` is 30 for a
  non-patron**, so "every bag and bank item" means the first 30 not already
  active (44 cards were on the page; 15 equipped were pre-selected, 15 more
  were clicked to reach 30). The selection persists across the content switch.
- Export: the `Export` button (`TopGear/Report/MenuDropdown.tsx`) opens a menu
  with `Download JSON` and `Copy JSON` (`TopGearReport.js:297-327`,
  `UpgradeFinderReport.js:132-136`). `Copy JSON` opens `GenericDialog.tsx`
  with the JSON in a `TextField`; the script reads that field's value, which
  needs neither clipboard permissions nor download interception.
- Upgrade Finder settings default to `{ raid: [3], dungeon: 7, pvp: 0,
  craftedLevel: 2, craftedStats: "Crit / Haste", itemTypes: [Drop, Upgraded,
  Bonus Roll] }` (`settings` in the export). Its item levels for dungeon drops
  are 311 / 321 / 334 (key level 7, drop / upgraded / max), which is not the
  journal walk's preview level 10 - WKE-535 has to reconcile the two before
  the itemID + level join finds anything.

## Left for the companion (WKE-533)

Selecting "every" bag item is a loop over cards up to the cap; a "select all"
control on the fork would be nicer but is not needed. The welcome dialog and
the `/circlet` detour are two extra steps a persistent browser profile would
remove (Playwright `launchPersistentContext`) - worth doing in C-1, not here.

---

# Companion spike S-2 (WKE-532): the SimC profile, built from SavedVariables

`simc-profile.js` builds a SimulationCraft text profile out of one Lootpath
capture transcript, so the companion (WKE-533) can feed QE Live without the
owner running `/simc`. `lua-savedvariables.js` is the strict Lua-table reader it
uses; `simc-profile.test.js` is its guards.

```
node tools/companion-spike/simc-profile.js build <Lootpath.lua> [out.simc] [--no-bank] [--snapshot=N]
node tools/companion-spike/simc-profile.js diff  <Lootpath.lua> <real.simc>  [--no-bank] [--snapshot=N]
node --test tools/companion-spike/simc-profile.test.js
```

The tests are Node 22's built-in runner - no dependency to install, and nothing
added to CI's five Lua gates. 32 tests, all green.

## The answer

**Yes.** Everything QE Live's importer reads off an item line comes out of the
item link, which Lootpath's `inventory` capture already stores verbatim. Of the
header, QE Live reads four things, and the `env` capture carried three of them;
this PR adds the fourth (`region`) and two more for faithfulness.

## What QE Live's importer actually reads

Read from the fork's `src/General/Items/GearImport/SimCImportEngine.ts`
(branch `lootpath/upgrade-finder-export`, 2026-09-07), not guessed.

| Where | What it reads | Lootpath has it? |
|---|---|---|
| `lines[0]` | the text before the first `-`, as the character name; the line must contain `#` and must not contain "Warcraft Logs" | yes (`env.player`) |
| any line | `server=` -> realm, `region=` -> region | realm yes; **region added by this PR** |
| `lines.slice(0, 8)` | `checkSimCValid`: one of the first EIGHT lines must have, before its `=`, a string the player's class name contains. Nothing else can fail - `level` and `version` are initialised true, `gameType` only fails on a Classic string, `length` only above 1000 lines | yes (`env.class[2]`) |
| item lines, from index **8** | `id=`, `bonus_id=`, `gem_id=`, `enchant_id=`, `crafted_stats=`, `drop_level=`, `redirected_base_stats=`, `titan_disc_id=`, `ilevel=`/`ilvl=` | all but `titan_disc_id` come out of the link |
| section markers | `### Weekly Reward Choices` and `### Linked gear` as line indices; an item line between them is a vault item | yes (the `vault` capture) |
| any item line | `#` anywhere in the line means "not equipped" | yes |

**Lines the SimulationCraft addon writes that QE Live never reads:**
`talents=` (and every `# Saved Loadout:` / `### Offspec Loadouts` block),
`level=`, `race=`, `zandalari_loa=`, `role=`, `professions=`, `spec=`,
`# loot_spec=`, the whole `### Additional Character Info` block, and the
`# Checksum:` line. On an item line, `content_tuning=`, `crafting_quality=` and
`gem_bonus_id=` reach no branch of `processItem`'s else-if chain.

**So talents are not a capture this project needs.** The issue asked whether
`C_Traits` / `C_ClassTalents` would have to be captured; the importer never
looks at the string, so no capture was written. (`bonus_roll_items` is read, but
through `lines.indexOf("bonus_roll_items")` - an exact whole-line match against a
line the addon writes as `# bonus_roll_items=...`, so it never fires.)

**Two line-index rules are load-bearing and are asserted on every build:** the
class line must be inside lines 0..7, and no item line may be, because
`processAllLines` starts its loop at `i = 8`.

## What the profile is built from

Only the transcript. Item fields come from the link through the SimulationCraft
addon's own offsets (`core.lua` lines 36-61), mirrored - the addon is Unlicense,
so its logic is free to mirror; nothing of QE Live's is copied anywhere here.

Two fields the addon emits are deliberately not emitted, both named in the code:

* `crafting_quality=` - `C_TradeSkillUI.GetItemCraftedQualityByItemInfo`, not in
  the link. **QE Live ignores it.**
* `titan_disc_id=` - a tooltip spell scan of four specific belts (itemIDs
  242664, 245964, 245965, 245966). **QE Live reads it.** This is the one
  importer-consumed item field the companion cannot produce today; it matters
  only if the owner equips one of those four belts, and none is in his
  transcript.

## Slot mapping

The addon indexes gear by its own slot NUMBER; Lootpath's capture stores
Blizzard's inventory slot id. Thirteen of the nineteen entries in the inverse map
are confirmed against the owner's own 2026-09-07 `/simc` string - the same item
appears at a known inventory slot in the capture and under a known SimC slot
token in his string: head(1), neck(2), shoulder(3), chest(5), waist(6), legs(7),
feet(8), wrist(9), hands(10), finger(11), trinket(13) and back(15), plus cloak
and 2H weapon through the bag-item table. The rest are Blizzard's documented
`INVSLOT_*` constants.

## Measured, 2026-09-08, against the owner's real `/simc` string

`spec/fixtures/simc/hotornot-from-savedvariables.simc` is the profile this script
builds from `spec/fixtures/captures/Lootpath-20260906-200908.lua` (newest
`inventory` snapshot, 2026-09-05 13:33:25, bank closed): 148 lines, 15 equipped
and 35 bag items. `--snapshot=0` is the bank-open snapshot of 13:33:13 and adds
31 bank items.

### 1. The item encoder, against `hotornot-20260907.txt`

```
node tools/companion-spike/simc-profile.js diff \
  spec/fixtures/captures/Lootpath-20260906-200908.lua \
  spec/fixtures/simc/hotornot-20260907.txt
```

| | |
|---|---|
| items in both, same itemID and same bonus IDs | **26** |
| field mismatches in anything QE Live reads | **0** |
| differences in fields QE Live ignores | **0** |
| slot-token differences | 3 (all `finger1`/`finger2`, `trinket1`/`trinket2`) |
| equipped-vs-bags differences | 8 |
| items only the generated profile has | 24 |
| items only the real string has | 17 |

Twenty-six items are encoded byte for byte the way the SimulationCraft addon
encoded them, from a link Lootpath read two days earlier - `bonus_id`,
`enchant_id`, `gem_id`, `crafted_stats`, `drop_level`, `redirected_base_stats`
and even `content_tuning`, which QE Live throws away.

**The other differences are the character, not the script.** The capture is from
2026-09-05 13:33 and the `/simc` string from 2026-09-07 18:36; in between the
owner equipped the five swaps from the 09-06 export, upgraded several pieces (the
neck 272228 carries bonus 12842 in the capture and 12845 in the string) and moved
a ring and a trinket between positions. The addon assigns `finger1` / `finger2`
and `trinket1` / `trinket2` by which inventory slot the item sits in, so a swap
renames both - and QE Live ignores the slot token entirely, taking an item's slot
from its own item database.

**This comparison cannot be made cleanly from the committed fixtures**, because
no inventory capture was ever taken in the same session as a `/simc` string. That
is a one-line addition to Tuesday's run sheet, not a defect: `/lootpath capture
inventory` with the bank open, immediately before `/simc`. Until then the encoder
is proven over the 26 items that happen to overlap.

The SimC checksum is proven exactly: `adler32` over the owner's real string
reproduces the `# Checksum: 14cbd9e1` his own client wrote.

### 2. Through QE Live, 2026-09-08, the fork at `localhost:3000`

`run-fork.js` (S-1) imported the generated profile and produced all four
documents in **18.8 s** - Top Gear and Upgrade Finder for Dungeon and Raid,
`qe-live-droptimizer` v1 (15 items, 12 differentials each) and
`qe-live-upgradefinder` v1 (357 items each). **QE Live raised no import error**;
50 item lines became 46 Top Gear cards (its own `level > 50` and armour-type
filter dropped 4), against 44 lines and 44 cards for the real string.

Comparing that run's Upgrade Finder `equipped` array with the one S-1 committed
from the real string
(`spec/fixtures/qe/qe-upgradefinder-Hotornot-abxrrnezfilt.json`):

| | |
|---|---|
| equipped items QE Live built, generated / real | 15 / 15 |
| equipped items in both (same itemID and bonus IDs) | 6 |
| field differences on those six | **0** - `slot`, `level`, `bonusIDs` including their order, `gems`, `enchant`, `tertiary`, `setId`, `isVault`, `isExclusive` |
| item levels agreeing with the client's own `C_Item.GetDetailedItemLevelInfo` | **15 of 15** |
| `player.region` | `""` generated, `"US"` real |

The nine equipped items that differ are the same gear drift as above. The item
level check is the stronger one: for all fifteen, QE Live's own engine landed on
exactly the number the client reported in the capture.

`player.region` was the only field QE Live wanted and Lootpath did not have.

## What this PR added to the addon

`env` now also reads `UnitLevel`, `UnitRace`, `GetCurrentRegionName` and
`GetCurrentRegion` - four documented reads with no side effect, named in
`Captures.lua` like every other capture call. `region` is the one QE Live
consumes; `level` and `race` are there so the profile can carry what the
SimulationCraft addon carries, and a future difference can be classified rather
than shrugged at.

**Human-required, one line, whenever convenient:** `/lootpath capture env`, then
`/reload`, then `tools\sync.ps1 -Pull`. Until then the builder reports those
three as missing and omits their lines rather than writing them empty.

## Left for the companion (WKE-533)

* Pick the newest `inventory` snapshot on its own; the `--snapshot` flag exists
  for the spike's comparisons.
* Decide what to do about the 30-item Top Gear cap when the bank is included:
  the bank-open capture can offer 81 items and QE Live selects 30.
* The vault section is written from the `vault` capture's `rewardLinks` and is
  **untested** - no committed snapshot has ever carried a generated reward. The
  first one arrives with WKE-523's after-reset capture.
