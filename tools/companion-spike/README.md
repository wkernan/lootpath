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
node <this repo>/tools/companion-spike/run-fork.js <simc.txt> <outdir> [--headed] [--smoke]
```

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
