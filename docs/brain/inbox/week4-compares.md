# week4-compares: week four of the engine compare, the vector refit's first unseen week; WKE-707 passes in game

## §0
**As of 2026-10-20, afternoon CDT, week four stored (the owner's reset-day run; `spec/fixtures/captures/Lootpath-20261020-145040.lua`, PR open on `main` b55ad9d).**
- **The weights:** the game ran the 2026-10-15 vector refit (`fit-to-qe-exports`, `patch 12.1.5`, derivedAt 2026-10-15T15:31:13.136Z). It was fitted on week three's vectors, so week four's 22 QE Live documents (exported 2026-10-20T19:37-19:38Z) are the first it never saw.
- **Rank agreement holds:** tier, armour and weapon rank exactly as QE Live in Dungeon +6, and armour does in every band.
- **The scale mostly fixed itself:** on the Upgrade Finder rows, `k` sits within 0.90-1.03 on every class but Raid jewellery (0.747), against 0.41-1.27 on week three's carried weights.
- **Jewellery is the one class still off:** rank 0.890 at +6 and 0.918 at +10, but 0.803 with top1 50% in Raid.
- **Top-set agreement:** 12 / 12 / 14 of 16 (Dungeon +6 / +10 / Raid). Week three: 12 / 12 / 13 of 15.
- **The bar passes no class** (printed, not enforced), so the passing-week count is still at zero for every class.
- **WKE-707 (R-2s) verified in game:** the claimed vault Sandals (318, Myth 1/6, 1 Myth crest held) read `Lootpath · Feet` / `Crest to 334` / `+0.54% Upgrade` with no refresh. Before the claim, the offered reward read `Grab these - crest it after.` The short form decided 2026-10-18 is what ships.

## §9 Verification ladder
- **2026-10-20, afternoon CDT - week four of the engine compare (the owner's reset-day run, PR open).**
  - **The run, as it happened:**
    1. The companion watcher was not running at first: its last log line was 2026-10-19T20:59:53Z, no `companion.js --watch` process existed and no startup task was registered. The owner started it.
    2. The Vault tab said `This week's vault rewards have not been generated yet. Open the Great Vault, then refresh` (M3-16b, as designed).
    3. Opening the vault generated two Dungeons rewards (Enigmatic Dreamwatcher's Plumage and Sand-Shined Snakeskin Sandals, both 318 Myth 1/6), each tooltip reading `Not rated yet - refresh.`
    4. The refresh rated 22 documents in 146,656 ms and wrote the verdict at 19:39:56Z with `2 vault`. The verdict: `Grab the Sandals from the vault and crest it. Skip the vault shoulders.` (the Sandals `the pick`, `in your best set`; the Plumage `0.37% behind`, both rated at 334).
  - **Log noise, not a defect in the rating:** the companion logged five `the SavedVariables carry no vault reward 180653 / 269862: equipLoc INVTYPE_NON_EQUIP_IGNORE ...` warnings for the vault's non-gear rewards. Leaving them out is right; the wording ("carry no vault reward") is wrong and repeated.
  - **Stored per class**, read from `db.global.engineCompare` with `tools/companion/lib/lua-savedvariables.js`. Each cell is week three (carried weights, derived 2026-10-14T19:34:31.408Z) -> week four (vector refit):

| Band | Class | n | rho | top1 | MAE | k |
|---|---|---|---|---|---|---|
| Dungeon 6 | tier | 19 | 0.997 -> 1.000 | 1.00 -> 1.00 | 0.049 -> 0.002 | 1.269 -> 0.996 |
| Dungeon 6 | armour | 15 | 0.985 -> 1.000 | 1.00 -> 1.00 | 0.015 -> 0.001 | 0.968 -> 0.993 |
| Dungeon 6 | jewellery | 16 | 0.658 -> 0.890 | 0.50 -> 1.00 | 0.095 -> 0.013 | 0.621 -> 1.004 |
| Dungeon 6 | weapon | 5 | 1.000 -> 1.000 | 1.00 -> 1.00 | 0.037 -> 0.004 | 1.205 -> 1.021 |
| Dungeon 10 | armour | 5 | 0.895 -> 1.000 | 1.00 -> 1.00 | 0.013 -> 0.003 | 0.961 -> 1.017 |
| Dungeon 10 | jewellery | 5 | 0.658 -> 0.918 | 0.50 -> 1.00 | 0.213 -> 0.027 | 0.610 -> 0.945 |
| Dungeon 10 | tier | 4 | - | - | 0.057 -> 0.012 | 1.119 -> 0.986 |
| Raid (raid-3) | armour | 5 | 1.000 -> 1.000 | 1.00 -> 1.00 | 0.016 -> 0.005 | 0.957 -> 1.010 |
| Raid (raid-3) | jewellery | 5 | 0.895 -> 0.803 | 0.50 -> 0.50 | 0.397 -> 0.128 | 0.407 -> 0.747 |
| Raid (raid-3) | tier | 4 | - | - | 0.041 -> 0.038 | 1.066 -> 0.902 |

  - **Top Gear pass 1:** it differs at Waist, Trinket and Weapon in both Dungeon bands. In Raid it differs at Feet (ours keeps the worn Arctic Explorer's Legwraps 308 over QE Live's new Sandals 318, +0.125% by our value) and Trinket. The Trinket difference (ours Pulse Seeker's Oculus 308, theirs Vile Vial of Volatile Venom 331, +0.59% to +0.69% by our value) is in every band. Trinkets are still not modelled.
  - **Dungeon 10 and Raid share their counts:** both joined the same 15 items at 318 / 321 / 324, with the same 30 / 72 / 213 counts, and QE Live's value differs on 10 of the 15. They are one item list rated in two contexts, as on week three.
  - **The capture:** weeks 2026-09-29 to 2026-10-13 are identical to the 2026-10-14 pull. Week 2026-10-20 has 90 rows and 86 vectors.
  - **WKE-707 in game:** after the claim, the Sandals in the bag read `Crest to 334` / `+0.54% Upgrade`.
