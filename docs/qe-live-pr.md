# QE Live pull request draft (WKE-527, QE-1)

Prepared 2026-09-06 on the owner's fork. **Not opened upstream.** The owner decides in WKE-528 whether and how to offer it.

| | |
|---|---|
| Fork | https://github.com/wkernan/QuestionablyEpic |
| Branch | `lootpath/upgrade-finder-export` (from `dev` at `589430d10`, 2026-09-05) |
| Local clone | `c:\Code\qe-live-fork` |
| Diff | 4 files changed, 35 insertions, 6 deletions; 3 new files (`UpgradeFinderJSONExport.ts`, `UpgradeFinderJSONExport.test.js`, `GeneralComponents/CopyToClipboard.ts`) |

## What the branch does

1. **Wires the Top Gear JSON export into the UI.** `TopGearJSONExport.ts` existed since May but nothing called it; there was no Download JSON control on the live site. The report's Export menu gains **Download JSON** and **Copy JSON** (Copy opens the existing export dialog with the JSON, which already has a Copy button).
2. **Adds an Upgrade Finder export**, `qe-live-upgradefinder` v1, mirroring the Top Gear exporter's style and reusing its `serializeItem`. It reads the shortened report object the site stores, so it works on a fresh run and on a report reloaded by id. Fields: `player`, `contentType`, `reportId`, `settings` (the Upgrade Finder settings the values assume), `equipped[]`, `items[] = { id, level, slot, source {instanceId, encounterId}, dropLoc, dropType, dropDifficulty, upgradePercent, hpsGain, score }`. **Positive means an upgrade**, the opposite of the Top Gear differentials, so the fields are named for what they are.
3. **Export menu on the Upgrade Finder report** with the same two options.
4. `GenericDialog`'s Copy button goes through a small helper with an `execCommand` fallback for browsers that refuse the async Clipboard API.

## Checks run in his repo

- `react-scripts test`: the new suite passes (5 tests). Full suite result: whole suite exit 0 (jest exits non-zero on any failure); every listed suite PASS, including the new one.
- `tsc --noEmit`: 0 errors in the touched files; 205 pre-existing errors elsewhere on `dev`.
- ESLint: his `.eslintignore` ends with a bare `src/` line, so his config lints nothing in the source tree, and it has no TypeScript parser. Run with `--no-ignore`, the two edited JavaScript components carry the same finding counts before and after (8 and 47).
- `npm run build`: `npm run build` exit 0, "The build folder is ready to be deployed" (CRA type-checks during the build).

## PR description (for him, under 200 words)

> **Wire the Top Gear JSON export, add an Upgrade Finder export, add Copy JSON**
>
> `TopGearJSONExport.ts` builds a `qe-live-droptimizer` payload but nothing in the UI calls it, so there is no way to get that file today. This adds **Download JSON** and **Copy JSON** to the Top Gear report's Export menu, and the same two options on the Upgrade Finder report backed by a new `qe-live-upgradefinder` v1 export that reuses `serializeItem` and reads the stored report shape, so it works on reloaded reports too.
>
> The reason: [Lootpath](https://github.com/wkernan/lootpath) is a WoW addon that shows QE Live's Top Gear and Upgrade Finder answers in game, next to the loot map and the vault. It computes nothing itself; every number is yours, pasted in from these exports.
>
> Upgrade Finder values are exported as `upgradePercent` / `hpsGain` where positive means better, since `percDiff` and `rawDiff` are `new - base`; named that way so nobody confuses them with the Top Gear differentials' sign.
>
> Smallest diff I could manage, no new dependencies, a jest test for the exporter. Happy to reshape any of it: field names, where the buttons sit, or dropping the Upgrade Finder part if you'd rather keep that closed.

## Notes for QE-2

- Lead with the fact that the export has had no consumer and no button since May; the PR gives it both.
- Do not mention Healper unless he does.
- If he declines the Upgrade Finder half but takes the Top Gear buttons, that alone unblocks the round trip for everyone; the map stays values-free (option A).
