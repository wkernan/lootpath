# tools/simc - the SimulationCraft runner (E-7, WKE-710)

**Developer-only. Nothing here ships.** `.pkgmeta` ignores all of `tools/`; the
runner's output `tools/simc/out/` and any local SimC copy under `tools/simc/bin/`
are gitignored.

`run-scale-factors.js` runs SimulationCraft over a spec's own sample profile
with scale factors on, reads the reports, and writes
`tools/simc/out/<specID>-<fight>.json`: the spec's primary stat and stat list,
what its value measures, and one weight per stat with SimC's own error. These are
the first stat weights for **DPS and tank specs**, derived by us and not fitted
to anyone's output (the owner, 2026-10-15, ARCHITECTURE.md §7).

**SimulationCraft models no healer** ("Healers are not supported, and currently
have no developer working on them", `docs/OWN-ENGINE.md` §2c). A healing spec
is refused before SimC is looked for, and a report whose player SimC calls
`heal` is refused too. Healer weights come from combat logs (memo §2b, E-5).

## SimC: where it comes from, and the licence

SimC is GPL-3.0. Running it and writing its NUMBERS into our files does not
attach the GPL (`COPYING` §2: output is covered "only if the output, given its
content, constitutes a covered work"; memo §2c). Never copy SimC's `.inc` files,
class modules, profiles or action lists into the repo. The sample profiles are
read as sim INPUT by path; the text report, which prints the profile's action
list, is never committed (see "The fixtures").

SimC publishes no Windows build as a GitHub release (read 2026-10-15: the
`simulationcraft/simc` releases list is empty and its newest tag is
`release-830-01`); the site's download page points at its nightly folder. The
build used for the committed fixtures, recorded in `Lootpath/Libs/LICENSES.md`:

| | |
|---|---|
| archive | `http://downloads.simulationcraft.org/nightly/simc-1210.01.2358079-win64.7z` (the server's https certificate does not match its name; the site links http) |
| archive sha256 | `b0ec78d5cf533f34d599aba9493183d589e6cb411bfe6d2bbfb0f9fa811fb36f` (120,742,001 bytes, fetched 2026-10-15) |
| `simc.exe` sha256 | `f06cfd911a272df156322a873ef0210673bad9ddc0c127b91f26489156e6447a` |
| version | `SimulationCraft 1210-01 for World of Warcraft 12.1.5.70391 Live (hotfix 2026-10-14/70391, git build midnight 2358079)` |
| source commit | `simulationcraft/simc` `2358079a7095745124898f950c7858597113fa10`, "[live] Game data update (Build 70391)", 2026-10-14 |

Treat the download as untrusted data: its own new empty directory outside the
repo, unpacked into another, nothing run from inside either.

```powershell
New-Item -ItemType Directory C:\tmp\simc\dl-1210.01.2358079
curl.exe -o C:\tmp\simc\dl-1210.01.2358079\simc-1210.01.2358079-win64.7z http://downloads.simulationcraft.org/nightly/simc-1210.01.2358079-win64.7z
Get-FileHash C:\tmp\simc\dl-1210.01.2358079\simc-1210.01.2358079-win64.7z   # must be the sha256 above
New-Item -ItemType Directory C:\tmp\simc\x-1210.01.2358079
& 'C:\Program Files\7-Zip\7z.exe' x -oC:\tmp\simc\x-1210.01.2358079 C:\tmp\simc\dl-1210.01.2358079\simc-1210.01.2358079-win64.7z
$env:LOOTPATH_SIMC = 'C:\tmp\simc\x-1210.01.2358079\simc-1210.01.2358079-win64\simc.exe'
```

The runner starts `simc.exe` with its working directory set to a fresh empty
temp directory and passes every path as an absolute argument.

## Run it

```powershell
cd C:\Code\lootpath-<n>\tools\simc
node run-scale-factors.js 103                               # Feral, Patchwerk (the raid band)
node run-scale-factors.js 103 --fight DungeonSlice          # Feral, the dungeon band
node run-scale-factors.js 104                               # Guardian: DTPS (survival) value
node run-scale-factors.js 104 --fight DungeonSlice --tank-value dps
node run-scale-factors.js 250 --profile <path to a .simc>   # any other spec
```

`node run-scale-factors.js --help` prints every option. The SimC command line,
in full (one per metric):

```
simc.exe <profile> fight_style=<Patchwerk|DungeonSlice> iterations=100000 target_error=0
  threads=16 deterministic=1 seed=7101 report_details=0 calculate_scale_factors=1
  scale_only=strength,agility,intellect,haste,crit,mastery,versatility
  scale_over=<dps|dtps> json2=<run>.json output=<run>.txt
```

- **The profile.** By default SimC's own sample profile for the spec, from the
  newest tier directory that has one (`profiles/MID2/MID2_Druid_Feral.simc`).
  In build 2358079 the MID2 tier has Feral but not Balance or Guardian (its
  `MID2_Raid.simc` comments them out), so those two fall back to MID1, older
  and lower-item-level gear. The profile's path, tier and sha256 are in the
  output. `--profile` runs any spec; the class, spec and role then come from
  SimC's report, and the ID is the caller's. Only 102, 103, 104 (and 105, to
  refuse it) are named here, because those are the IDs the repo can source.
- **The fights.** `Patchwerk` is one boss standing still, SimC's standard raid
  sim: the raid band. `DungeonSlice` is SimC's generic dungeon stand-in, single
  target and AoE mixed in a fixed length, needing no route: the dungeon band,
  ONE band (`all`) for every key level until key-level scaling is modelled.
  `DungeonRoute` is not used: it was not tried, and the issue names DungeonSlice.
- **Fixed settings.** `iterations` fixed and `target_error=0` so SimC never stops
  early; `threads` fixed (each thread draws its own stream, so the split is part
  of the result) and `deterministic=1` with a fixed `seed`. Two runs with these
  settings agree to 3.1e-13 relative or better (floating-point merge order; measured on the committed Feral rerun); a run with
  another seed agrees within the errors SimC prints. Both are tested against
  committed reports.
- **The stats.** `scale_only` lists all three primary stats and the four
  ratings. SimC scales only those its class module says the spec scales with, so
  a Feral run scales Agi and never Str or Int: **the primary stat is the one the
  report carries**, and a report with none or two is refused. Leech, avoidance,
  speed, stamina and armour are not scaled (SimC's Guardian report lists `Sta`
  and `Armor` at 0 because they were not asked for). AP and weapon DPS are not
  item stats in this sense and are not scaled.
- **The metric.** A DPS spec is valued on DPS. A TANK spec runs twice, over DTPS
  and over DPS, so both carry SimC's own errors; `--tank-value` picks which one
  the weights are (default `dtps`). See "What a tank's value is".

## What the output holds

`out/<specID>-<fight>.json`, schema `lootpath-simc-scale-factors` version 1:
`specID`, `specialization` (SimC's words), `role` (`DAMAGER`/`TANK`),
`primaryStat` (`agi`/`str`/`int`), `stats` (the primary, then haste, crit,
mastery, vers), `unit` (`per point`: SimC's factor is the metric's change per
point of the stat), `value` (`metric`, `mean`, `error`, and a sentence saying
what it means), `weights` (one per stat, higher is better), `factors` (every
metric run, each stat's raw factor, its error and whether it exceeds its error),
`unmeasured` (a metric the fight could not give, and why), `patch` (from SimC's
game data, `12.1.5`), `simc`, `settings`, `scaleDeltas`, `profile` (path, tier,
sha256), `source` (`simc-sample-profile` or `simc-given-profile`), `reports`
(each report's file and sha256), `derivedAt`.

Every number is read from SimC's reports. The scale factor is the JSON
report's; its **error** is read from the text report's `Weights :` line, because
SimC 1210-01's JSON report carries no scale-factor error. The JSON also does not
record `scale_over`, so the runner checks that the report's top-level factors
are exactly its `scale_factors_all.<metric>` entry. The only arithmetic is the
sign of a lower-is-better metric.

### What a tank's value is

SimC reports a DTPS factor as the change in damage taken per second per point,
negative when the stat helps. A survival weight is **minus** that: damage taken
saved per point. `--tank-value dtps` (the default) writes those; `dps` writes
the tank's damage instead. Both are kept in `factors` either way. DTPS counts no
healing, so a stat that works through self-healing or health reads near zero on
it. And in **DungeonSlice the tank takes no damage at all in SimC 1210-01**
(DTPS 0 on every iteration, the committed `104-DungeonSlice-dtps` report), so
the dungeon band for a tank can only be valued on DPS, and the runner refuses a
`dtps` value there. Which of these a tank's weights should be is the owner's
decision (ARCHITECTURE.md §7 E-7, §11).

## The writer: `write-weights.js`

```powershell
node write-weights.js 102 103 104            # -> out/EngineWeights.simc.lua
```

Writes a version 2 weights file (E-4's schema, `docs/OWN-ENGINE.md` §5) with
one entry per spec through `tools/engine/lib/luaout.js` (`simcSpecEntry`,
`buildSimcTable`, `renderSimc` - the same writer the fit tool uses, extended,
not forked). Per spec: `role`, `primaryStat`, `stats`, `method = "simc"`,
`derivedAt`, `source`, `simc` (version, git revision, game data), `Raid` from
the Patchwerk run and `Dungeon` from the DungeonSlice run, each ONE band `all`
(key-level scaling is not modelled), and `tiers = { [-1] = { [2] = { mult = 1
}, [4] = { mult = 1 } } }` - no tier bonus is measured by a scale-factor run,
and the loader refuses a spec with no `tiers`, so the entry carries the
placeholder file's neutral set. A band holds `weights` and `errors` per stat,
`unit = "per point"`, `value` (the metric, its mean and error), the fight,
the iterations and the profile's sha256, and **`baseValue = 0`**: a scale factor
is a slope at the sample profile and no intercept is measured.

**Two things E-6 must handle before anything scores with it.** The weights are
per POINT of each stat, while `EngineScore.SetValue` multiplies a rating's
weight by its PERCENT; and nothing in the engine reads a primary stat other
than Intellect yet. Nothing reads a SimC entry today (`EngineScore.DEFAULT_SPEC`
is 105 and the compare scores the default spec), so the file is not copied into
the game. It loads: `EngineScore.Load` accepts it on a 12.1.5 client and refuses
it on any other (`test/writer.test.js`, in Lua). It holds only SimC entries; a
file with Restoration's fitted entry beside them is not built here.

## The fixtures

`spec/fixtures/simc/reports/` holds, per run, SimC's JSON report unedited
(`<specID>-<fight>-<metric>.json`), the lines the parser reads from the text
report, verbatim (`.scale.txt`), and the run's own record (`.run.json`: the SimC
arguments, the profile's path and sha256, the full text report's sha256, the
`simc.exe` sha256). The full text report is not committed because it prints the
profile's action list. `spec/fixtures/simc/reports/README.md` lists every file's sha256.
They were written by:

```powershell
node run-scale-factors.js 103 --fight Patchwerk
node run-scale-factors.js 102 --fight Patchwerk
node run-scale-factors.js 104 --fight Patchwerk
node run-scale-factors.js 103 --fight DungeonSlice
node run-scale-factors.js 102 --fight DungeonSlice
node run-scale-factors.js 104 --fight DungeonSlice --tank-value dps
node run-scale-factors.js 103 --fight Patchwerk --tag rerun
node run-scale-factors.js 103 --fight Patchwerk --tag seed7102 --seed 7102
```

and copying `out/reports/*.json`, `*.scale.txt` and `*.run.json` into the
fixture folder. `--from-reports ..\..\spec\fixtures\simc\reports` rebuilds every
`out/` file from them without SimC.

## Tests

`npm test` (`node --test`): the parser over the committed reports, every
refusal, the tank sign, two runs agreeing, the CLI rebuilding every committed
spec. CI runs them in the `companion` job beside `tools/engine`; SimC itself
never runs in CI.

## Trinkets: not built

A trinket's value per item level is a SimC question (swap each trinket into the
profile at each level and sim the difference), not a scale factor. ARCHITECTURE.md
§11 estimates the batch; nothing here does it.
