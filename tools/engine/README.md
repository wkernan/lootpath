# tools/engine - the structure run (E-0e, WKE-674)

**Developer-only. Nothing here ships.** `.pkgmeta` ignores all of `tools/`, the
output folder `tools/engine/out/` is gitignored, and the weights it writes are a
diagnostic, never a shipping file.

`fit-weights.js` fits a weights file to QE Live's own Upgrade Finder exports, so
the own-engine compare (E-0d) can measure the engine's **shape** before any
log-derived weight exists. QE Live's Restoration Druid engine is linear in the
set's stats after DR, with a weight per stat and a flat tier multiplier
(`docs/OWN-ENGINE.md` §1). If our model (E-0c's `SetValue`, here in
`lib/score.js`) has the same structure, weights fitted to QE Live's
`upgradePercent` rows reproduce them closely; a poor fit says the structure
differs - DR placement, the assumed finish, the tier rule, the base value, or
the stats we fed it - and the residuals say where.

**Why the fit is legitimate.** The exports are the owner's own runs of his own
fork; comparing outputs is using facts (memo §2c). No code, table or constant of
QE Live's is copied: its repo has no licence and was read for understanding
only. The fitted weights never ship because they are QE Live's judgement
re-expressed, not an independent engine (ARCHITECTURE.md §7, 2026-09-30 E-0e).

## Run it

```powershell
cd C:\Code\lootpath-<n>\tools\engine
node fit-weights.js `
  --stats ..\..\spec\fixtures\captures\Lootpath-20260915-162015.lua `
  --stats ..\..\spec\fixtures\captures\Lootpath-20260916-152428.lua `
  --stats ..\..\spec\fixtures\captures\Lootpath-20261001-092631.lua `
  --stats ..\..\spec\fixtures\captures\Lootpath-20261001-200927.lua `
  --key-levels 1=2,2=4,4=6,6=8,7=10 `
  ..\..\spec\fixtures\qe
```

A directory means every `qe-upgradefinder-*.json` in it. `--key-levels` maps the
export's `settings.dungeon` index to a key level; the mapping is the one
`spec/fixtures/qe/README.md` records for the committed run (the key level is
not in the JSON). Without it a Dungeon band is keyed `dungeon-index-<n>`. A Raid
band is `raid-<settings.raid>`.
In game, `/lootpath engine compare` picks the band by the document's key level
through `EngineScore.BandFor` (E-0h): the key `"10"`, else the highest `"<n>+"`
at or under the level, else the content type's only band (Raid always), else
`no band for +<level>` - so a `dungeon-index-<n>` band is never found by level.

Options: `--tier-sets 2057` and `--tier2 0.03 --tier4 0.055` (the tier rule;
memo §1, and the committed Top Gear export's `bonusHPS` 0.085), `--finish
'{"int":0,...}'` (the assumed finish, added to every set's totals - none by
default, see "What is assumed"), `--effect-ids` (default the four below),
`--resamples 200`, `--seed 1`, `--out <dir>`, `--derived-at <ISO>`.

**The tier rule in the dev file is EngineScore's shape** (E-0i, WKE-680):
`tiers = { [setID] = { [2] = { mult = 1 + tier2 }, [4] = { mult = 1 + tier4 } } }`
for every `--tier-sets` ID. `EngineScore` adds the bonuses a set has reached
before it multiplies (`1 + Σ(mult − 1)`), so four pieces score `1 + tier2 +
tier4`, the same as `lib/score.js`. The fit's own `{ setIDs, twoPiece,
fourPiece, forceTier }` stays in the fit JSON and `score.js`; before E-0i it was
written into the Lua file too, `EngineScore` read no set from it, and every
fitted compare scored with a tier multiplier of 1 (the percents survived only
because the compare forces tier on both sides). `EngineScore.Load` now refuses a
file whose `tiers` is in any other shape (`Not rated - the rating data didn't
load.` and a developer line naming the field), and `test/tiers.test.js` loads
the written file through `EngineScore` itself and checks the multiplier at 2
and 4 pieces against the parameters.

It prints, per document, the row counts, where the stats came from, the fitted
weights with their bootstrap intervals, R², MAE and Spearman ρ overall and per
slot class, the check on censored rows, and the five largest residuals. It
writes `out/<document>-fit.json` per document (weights, intervals, metrics,
every row with its prediction, residual and stats source, the worn set as
modelled, the budget and DR used) and `out/EngineWeights.dev.lua`.

## Inputs

**The exports carry no stats.** Each Upgrade Finder row is `id`, `level`,
`slot`, `upgradePercent`, `hpsGain`, `score`; `equipped[]` carries bonus IDs,
gems, enchant and tertiary but no stat (checked over all eight committed
documents). So every stat vector comes from the client, and **every row says
which way** (`statsSource`):

| `statsSource` | meaning |
|---|---|
| `client` | the item at exactly that level (or, for a worn entry, the same item string by its bonus IDs), read from a transcript; `clientSource` says which |
| `client-scaled` | the item read at another level, its own split scaled by the level curve |
| `budget` | Intellect and the secondary TOTAL for the slot at that level, measured on client rows of the same slot |
| `budget-borrowed` | the same, from client rows of another slot in the budget group (head from chest/legs; shoulder/hands from waist/feet; wrist from back; neck from finger) |
| `none` | no client row in the group: the row is excluded |

A budget row does not know which secondaries the item carries; its total is
split equally over haste, crit, mastery and versatility (`splitSource:
"equal-placeholder"`), or for a crafted row over the pair the export's own
`settings.craftedStats` names. **The equal split is a documented placeholder**,
and on the committed exports it is the largest known error: before E-0f two
rings at 334 in the 2026-09-07 Dungeon document both predicted 1.637 where QE
Live reads 2.801 (252258) and 0.474 (251148). With the itemstats transcript
252258 reads its own split (`client-scaled` from 321) and predicts 2.980 at
334, and the five largest residuals of every document
are still `budget` rows on the equal split - rings and necks the transcript did
not read (Dungeon +10: 272147@321 Finger, observed 2.366, predicted 1.212).

**The client sources** are three, all read out of a `--stats` SavedVariables
file, and every point says which (`clientSource` on a row):

- `capture itemstats` (E-0a; read since E-0f, WKE-676): `C_Item.GetItemStats`
  on every worn, bag and vault link and up to 40 journal links, with the
  enchant and gems blanked, at the level `GetDetailedItemLevelInfo` gives that
  link. The keys are the client's own - `ITEM_MOD_INTELLECT_SHORT`,
  `ITEM_MOD_{HASTE,CRIT,MASTERY}_RATING_SHORT`, `ITEM_MOD_VERSATILITY` (no
  `_SHORT`), `ITEM_MOD_CR_LIFESTEAL_SHORT`. Indexed by `id@level`, by the
  stripped link (`statsForLink`) and by `id` + bonus IDs, so an export's
  `equipped[]` entry finds its own item string. Where it and `capture upgrade`
  name the same `id@level` this one is kept; on the committed files the 12
  shared points agree exactly. A journal link reads at the CLIENT's level for
  that link, which is not always the walk's: every keystone row the walk
  lists at 305 reads 292 (ARCHITECTURE.md §9, E-0f), so a journal point is
  filed under the level its stats are at.
- `capture upgrade` (committed captures from 2026-09-15 on):
  `GetItemUpgradeItemInfo().upgradeLevelInfos[].levelStats` gives an owned
  item's stats at every level of its track.
- `capture linklevel` (E-0g step 2, WKE-677; the 2026-10-01 20:09
  transcript): for each journal row the capture took, `GetItemStats` on the
  journal link rebuilt with the track step that draws the walk's level
  appended - the rule `ns.EngineStats` installs - kept only when the client
  drew it at the walk's level before, during and after the walk. Filed under
  `id@walkLevel` (the level the Upgrade Finder row names), `clientSource`
  `capture linklevel`; where `capture itemstats` names the same point it is
  kept. 8 points from the 12 candidates (the 4 world rows at 44 have no step).

Two levels of one item give the scale, read and never guessed. The level curve
is `ln(stat)` linear in item level, its slope measured within items,
separately for Intellect and the secondary total. A JSON table `{ "items": [{
"id", "level", "slot", "stats": { "int", "haste", "crit", "mastery", "vers",
"leech" } }] }` is accepted beside them. The run prints, per document, how many
rows read `client` / `client-scaled` stats from each transcript (`client reads`).

**The DR brackets** (`lib/dr.js`), from maxroll.gg, "WoW Stat Diminishing
Returns Summary" (https://maxroll.gg/wow/resources/stat-diminishing-returns),
**read 2026-09-30**; the page says "Last Updated: March 13, 2026 for patch
12.0.1 - Midnight". Quoted, level 90:

- Rating for 1%: Haste 44, Critical Strike 46, Versatility 54, Mastery "Varies
  by specialization"; Leech 69, Avoidance 37, Speed 12.
- Haste: "1320 - 1760 (-10%), 1760 - 2200 (-20%), 2200 - 2640 (-30%), 2640 -
  3080 (-40%), 3080 - 8800 (-50%), >8800 (-100%)"
- Critical Strike: "1380 - 1840 (-10%), 1840 - 2300 (-20%), 2300 - 2760
  (-30%), 2760 - 3220 (-40%), 3220 - 9200 (-50%), >9200 (-100%)"
- Versatility: "1620 - 2160 (-10%), 2160 - 2700 (-20%), 2700 - 3240 (-30%),
  3240 - 3780 (-40%), 3780 - 10800 (-50%), >10800 (-100%)"
- Leech: "690-1035 (-20%), 1035-1380 (-40%), 1380-3381 (-60%), >3381 (-100%)"

A bracket's penalty applies to the rating inside it. **Mastery** uses crit's
rating per point and brackets (the page gives no figure for the spec). **The
client settled both on 12.1.0** (E-0f): `GetCombatRatingBonusForCombatRatingValue`
applies diminishing returns, and this table reproduces its 35 answers in the
2026-10-01 transcript - haste, crit, mastery and versatility to single
precision, leech within 2.6e-4 (a constant 1.43e-5 relative below 69 per
percent) - with mastery equal to crit at every point for Restoration
(`test/dr.test.js`). The addon converts through the client; the table stays here
because the fit runs offline.

**Effect rows**, excluded from the fit and reported apart (`effects` in the fit
file): every trinket, and the effect armour Gaze of the Coiled Watcher 271875,
Jan'thrazet 271092, Aqirbane Reliquary 268265, Polished Lightwood Channeler
273778.

## The model and the fit

`lib/score.js` is E-0c's contract: totals over the worn set with the row's item
swapped in (either ring, either trinket, a two-hander for both hands; a
one-hander or off-hand beside a worn two-hander is not comparable), plus the
assumed finish; DR after the sum; `value = (base + w_int·int + Σ w_r·pct_r) ×
tier`, tier forced on; `percent = 100 × (V(with) − V(worn)) / V(worn)`, the best
swap. **SIGN:** positive means the item is better, the Upgrade Finder's own
convention; `upgradePercent` is read as exported, never negated. Its fixture,
`test/fixtures/score-fixture.json`, is written for the Lua `EngineScore` to be
tested against.

With the tier forced on for both sets the multiplier cancels from the percent,
and with `base + w·x(worn) = 100` the predicted percent is `w · (x(with) −
x(worn))` - linear. So the fit is least squares over the six weights per
document (content type × key level), with `base = 100 − w·x(worn)`; the scale of
the file is free because the percent is a ratio. A ring or trinket row takes the
swap the current weights prefer, refitted until the choice is stable.

Rows that do not enter the fit, each counted: `effect`; `censored`
(`upgradePercent` 0 means QE Live's Top Gear kept the worn set, so the true
value is "0 or worse" - never fitted as 0; the fit file says how many the model
also puts at or below 0); `duplicate` (one `id@level` twice); `pair`; `no-stats`.
The bootstrap resamples the fitted rows 200 times (seeded, deterministic) for a
2.5-97.5% interval per weight. Metrics: R², MAE and Spearman ρ (average ranks,
not under n = 5) overall and per slot class (tier-slot, armour, jewellery,
weapon), and the largest residuals with their rows.

## What is assumed (each is a parameter)

- No finish by default. QE Live scores every set fully finished (memo §1); its
  constants are not copied. The finish moves totals toward the DR brackets and
  changes `base`; pass `--finish` to test one.
- No buffs (`assumedBuffs` empty).
- The tier multiplier cancels from Upgrade Finder percents, so this run cannot
  see the tier rule at all.

## Use the dev file in a LOCAL install for one compare run

Only after E-0c has put `Data/EngineWeights.lua` in the addon, and only on your
own machine:

1. `.\tools\sync.ps1` as usual (a push leaves the game's `Data\` alone).
2. Copy `tools\engine\out\EngineWeights.dev.lua` over
   `C:\World of Warcraft\_retail_\Interface\AddOns\Lootpath\Data\EngineWeights.lua`.
3. `/reload`, run `/lootpath engine compare` (E-0d) with
   `db.global.developer.engine` on.
4. Put the shipped file back: copy the repo's `Lootpath\Data\EngineWeights.lua`
   over the game copy and `/reload` (`sync.ps1 -IncludeData` would also do it,
   but overwrites the companion's files in `Data\` too).

The file says `method = "fit-to-qe-exports"`, `devOnly = true` and `DEV ONLY -
never ship` in its header, with every document and sha256 it was fitted to.
E-0c refuses a file whose `patch` is not the client's; the patch is the
transcript's build (12.1.0 for the committed captures). `.pkgmeta` never packages
it: `tools` is in its `ignore` list, and the file is gitignored besides.

## The real-stats fixture

`extract-itemstats.js` writes `spec/fixtures/engine/itemstats-real.lua` from
the committed `capture itemstats` transcript (E-0f): the 80 items with their
links, levels, base stats, sockets, gems (each gem link's empty stat table),
set and uniqueness, the rating conversion at the probe's values, the mastery
pair, healing, intellect, the secret flags and the six trinket tooltips -
copied through `lua-savedvariables.js`, nothing computed. The file names the
transcript's sha256 and carries an `install(world)` the busted specs put on the
stub. Re-run after a new transcript:

```powershell
cd C:\Code\lootpath-<n>\tools\engine
node extract-itemstats.js [spec\fixtures\captures\<transcript>.lua] [spec\fixtures\engine\itemstats-real.lua]
```

(paths relative to the repo root). `test/extract.test.js` re-runs it and
compares the bytes with the committed fixture.

## The effects transcript (E-3b, WKE-684)

`extract-effects.js` reads the owner's `/lootpath capture effects` transcript
(the capture is in `Lootpath/Captures.lua`; ARCHITECTURE.md section 7,
2026-10-02, E-3b) and writes `spec/fixtures/engine/effects-real.lua`: one record
per effects-table item, per target (a cached journal row or an owned copy), per
read - `walk` (the link rebuilt at the walk's level by
`EngineStats.LinkAtLevel`), `kept` (the link as kept) and `next` (one track step
away) - with the level asked for, the link, `GetDetailedItemLevelInfo`'s
returns, the Item Level and Upgrade Level lines, and every line whose text
starts `Use:` or `Equip:` with the digits in it **as text** (`"528"`, never
528) - for the first read and for `again`, the same tooltip read a second time
after the capture's pause (four of the six trinket tooltips the itemstats
transcript read once carried no effect line). Found by text, not by line type: the one committed `Use:` line is type 44,
which the annotations' enum does not list. Nothing is parsed into a value; the
follow-up (E-3c) reads the records and fills `Data/EngineEffects.lua`'s
`params`.

**No transcript yet**, so the script has no default input:

```powershell
cd C:\Code\lootpath-<n>\tools\engine
node extract-effects.js spec\fixtures\captures\<transcript>.lua [spec\fixtures\engine\effects-real.lua]
```

`test/extract-effects.test.js` holds it to a SavedVariables in the capture's
stored shape (the tests' own, with the committed Freightrunner's Flask `Use:`
line verbatim). When the transcript lands, E-3c commits the output and adds a
byte-for-byte test to `test/extract.test.js`, as E-0f did for itemstats.

## Tests

`node --test` here (the CI `companion` job runs it beside the companion's, with
Lua 5.1 installed and `LOOTPATH_REQUIRE_LUA=1`; `tools\check.ps1` runs it in the
same gate). A synthetic export generated from known weights fits back inside the
interval; effect and censored rows are excluded and counted; every row carries
its stats source; the score fixture's values hold, by hand too; the dev file
loads in Lua 5.1 (from PATH, or the repo's `lootpath-lua` Docker image) and
carries the fitted numbers; the itemstats transcript is read (80 items, the
helm's stats, versatility's key, `client` rows flagged with their source, the
two client sources agreeing where they overlap); the DR table reproduces the
client's 35 conversions; the real-stats fixture is the extraction, byte for
byte; the effects extractor keeps every effect number as text, finds `Use:` and
`Equip:` lines by their text whatever their type, and refuses anything but one
snapshot. No npm dependency: Node's own runner and
`tools/companion/lib/lua-savedvariables.js`.

## percent-scale.js - why k moved with the band (E-0j, WKE-681)

```powershell
node percent-scale.js `
  --stats ..\..\spec\fixtures\captures\Lootpath-20260915-162015.lua `
  --stats ..\..\spec\fixtures\captures\Lootpath-20260916-152428.lua `
  --stats ..\..\spec\fixtures\captures\Lootpath-20261001-092631.lua `
  --stats ..\..\spec\fixtures\captures\Lootpath-20261001-200927.lua `
  --key-levels 1=2,2=4,4=6,6=8,7=10 `
  --measure ..\..\spec\fixtures\captures\Lootpath-20261001-092631.lua `
  [--compare <a copy of SavedVariables\Lootpath.lua> --week 2026-09-29 --char "Hotornot - Arthas"] `
  ..\..\spec\fixtures\qe
```

Fits the bands exactly as `fit-weights.js` does, then scores the Upgrade Finder
documents STORED in the `--measure` capture against that capture's worn set
(inventory snapshot `--inventory`, default 4) and prints k - the least-squares
scale of ours onto theirs, `EngineCompare.Scale` - per slot class: `game`
(`100 × ΔV / V(worn)`, what the compare computes), `pin100` (the worn set at the
fit's 100), `floored` (ours floored at the Upgrade Finder's 0, the compare
since E-0j), `uncensored` (rows whose theirs is exactly 0 left out), and the
bands refitted on client-read rows only. With `--compare`, the same k raw and
floored over the rows a real compare stored. **Read it this way:** the Upgrade
Finder never reports below 0 (its Top Gear keeps the worn set when a drop is
worse), so an unfloored k shrinks by the share of censored rows, which the band
sets; compare floored figures only. Never read the owner's SavedVariables in
place - copy them first. `test/percent-scale.test.js` holds the harness's floor
equal to `EngineCompare.UF_FLOOR` and pins its figures on the committed files.

## probe-tier.js - why tier k differs by band (E-0k, WKE-682)

```powershell
node probe-tier.js `
  --compare ..\..\spec\fixtures\captures\Lootpath-20261002-112757.lua `
  --week 2026-09-29 --char "Hotornot - Arthas" `
  [--tier2 0.03 --tier4 0.055] `
  [--stats <the four transcripts above> --key-levels 1=2,2=4,4=6,6=8,7=10 --qe ..\..\spec\fixtures\qe]
```

Re-scores the tier-class rows a real compare STORED under each suspect and
prints k and MAE@k per band. The re-score needs no item stats: with the tier
bonus forced on both sides the game's percent gives `L(with) / L(worn) = 1 +
raw / 100` exactly, so any other multiplier rule is `100 (L1 M'(with) / (L0
M'(worn)) - 1)`, floored at `UF_FLOOR`. Rules: `additive-forced` (E-0c, what
`EngineScore` does), `multiplicative-forced`, and both NOT forced (`-counted`:
a non-tier drop in a tier slot breaks the worn 4-piece), each over a grid of
2- and 4-piece values. Then the gap by the worn piece each row replaces (read
off the newest `capture itemstats` snapshot in the same file: `setID` from the
client's item info, the catalyst source from link modifier 64) and the offset
per slot that brings each row to armour's k. With `--stats` it also refits each
measured document's band IN SAMPLE (offline stats, as `percent-scale.js`
reads them) beside the dev band. `test/probe-tier.test.js` pins the figures on
the committed files.
