# The Lootpath companion (C-1, WKE-533)

A program on the owner's own PC that closes the gearing loop without a browser
in it. It reads Lootpath's SavedVariables, builds the SimulationCraft profile
from them, runs QE Live's engine in the owner's local fork, and writes the
verdict back into the addon folder - with a log and a status chunk beside it
saying what it did.

**The loop it makes possible is `/lootpath refresh`, wait, `/lootpath refresh`.**
No `/simc`, no alt-tab, no paste. That is the floor and this README says so
rather than hiding it: SavedVariables reach disk only on `/reload` or logout,
and the client reads addon files only at load, so two reloads is the fewest a
companion can need.

**The first refresh is the one that feeds this program.** Since C-3 (WKE-536)
`/lootpath refresh` takes the three snapshots the profile is built from - `env`,
`inventory` and `vault`, in that order - and only then reloads, so what reaches
disk is the gear the character is wearing right now rather than whatever was
last captured by hand. Open the bank first if you want the bank half; the chat
line says which you got. The second refresh takes them again, harmlessly, and
its job is to load the file this program wrote. `journal` is never part of a
refresh: it is asynchronous, the profile reads none of it, and the loot map's
own cache is untouched.

**The game tells you when you are behind, so you do not have to remember (R-6,
WKE-578).** Claim a vault reward, loot a drop, catalyst or crest a piece, and a
second row appears under the window's status strip - `your gear changed since
this plan (2 items) - click to refresh` - with a small badge on the minimap
button. Clicking it is the first refresh. After the reload the same row says the
rating is being made and roughly how long that takes, and clicking it again is
the second refresh. The two-reload floor has not moved; what has changed is that
nobody has to know it is there.

**Log out, and your plan is current next time you log in; refresh only when you
want a re-rating mid-session (R-7, WKE-579).** A logout flushes SavedVariables
and this program wakes on that write, and since R-7 the addon takes the same
four snapshots - gear, bags, vault, currencies - at `PLAYER_LOGOUT` itself. So
what the write carries is the gear you logged out in, the run happens while you
are away, and the plan is waiting when you come back. Nothing is asked of the
server on the way out: the vault is read plainly, without M3-16's interaction,
because a logout has no time to wait for an answer.

Until R-7 this was true only if you refreshed first - the addon took its
snapshots nowhere but `/lootpath refresh`, so a logout after an evening of
looting saved the morning's gear again and the run was skipped as unchanged.

The log says which happened, in one line per run:

```
run after /lootpath refresh (gear captured at the click)
run after logout (gear captured at logout)
run after a capture made by hand
run after a logout or a plain reload - nothing new was captured
```

The second line is read off the addon's own label, not guessed at: every
snapshot records how it was TAKEN (`trigger = "refresh"`, `"logout"` or
`"command"`) and when. The last line still names two possibilities on purpose,
and still has cases - a plain `/reload`, an addon from before R-7, or a forced
logout in combat, where every capture refuses because nothing in Lootpath runs
in combat and the last snapshot is flushed again.

**A refresh with unchanged gear costs nothing.** Since C-4 (WKE-537) the
companion fingerprints the profile it is about to ask QE Live about, remembers
the fingerprint of the last verdict it actually wrote, and skips the run when
the two agree and that file is still there - so the second refresh of the loop
logs one line instead of spending another 17 s in the browser. The stamps in the
profile's header are stripped before hashing, so capturing the same gear again
is not a new question. `--force` runs anyway.

**It asks QE Live the same question about both sides of a comparison.** His
import dialog defaults to `autoUpgradeVault = true` and `autoUpgradeAll = false`
(`SimCraftDialog.js` lines 36-37), which values a vault option at the top of its
upgrade track and the gear you are wearing at the level the client reports. On
2026-09-08 that told the owner to take a 305 copy of a weapon they already wear
at 308, because QE Live had been asked about the vault copy at 321. Since C-5
(WKE-539) the companion **sets both boxes explicitly on every run**, defaulting
to both OFF, and records which pair it asked for in the file it writes.

**It asks the vault what-ifs by name, because a vault option is not the item as
it is offered.** Put the 308 Scavenger's Spaulders through the Catalyst and they
are tier shoulders at 308 - the set bonus kept, the item level unchanged. QE
Live models that (and upgrade tracks) in his three import checkboxes, so
Lootpath models neither: since C-6 (WKE-540) the companion runs Top Gear once per
named scenario - `asOffered`, `catalyzed`, `thisWeek`, `maxed` - because the
boxes act AT import, and stamps each document with the scenario it answers.
Measured 2026-09-09 on the owner's own vault: `asOffered` ranks the vault weapon
0.57% behind, `catalyzed` puts the catalyzed shoulders in the best set,
`thisWeek` takes the weapon at 321 and catalyzes a pair of shoulders already in
his bag, `maxed` puts the weapon in it at 321 with everything else capped too.
Four questions, four answers, none of them Lootpath's.

**It asks about several Mythic+ keys, because his engine only answers about
one.** The Upgrade Finder values every dungeon drop at the single key level
`ufSettings.dungeon` names, so "which dungeon at the lowest key still gives me
an upgrade" is not a question one export can answer. Since C-7 (WKE-543) the
companion runs the dungeon Upgrade Finder once per level in
`upgradeFinderKeyLevels` (default `+2, +4, +6, +8, +10`) and writes the level
onto each document; the addon files one verdict per `(content type, key level)`
and the loot map reads the one matching the level its walk previewed.

This is the Raider.IO pattern - their desktop client writes score databases into
the addon folder the same way - and it is the one exception to Lootpath's
"everything external arrives by paste" rule (decision 2026-09-07,
`docs/ARCHITECTURE.md` §7).

## What it never does

- **It never computes a healer value.** Every number it carries is QE Live's own
  export text, moved from his engine to the addon unchanged. It does not
  reimplement, cache-and-adjust, or fill a gap in his numbers.
- **It never talks to anything but localhost.** No backend, no telemetry,
  nothing leaves the machine. The only network call is to the fork's own dev
  server.
- **It never writes anywhere but `Interface\AddOns\Lootpath\Data\`** - the
  verdict, its own log and its own status chunk, and nothing else anywhere - and
  it refuses if the addon is not installed rather than creating a folder.
- **It never writes code.** The chunk it produces declares one local, checks
  that it really is loading inside the addon, and assigns one table of string
  literals and numbers. The addon runs each string through the same
  `ns.QEImport.Parse` a paste goes through, so every schema pin, version pin and
  refusal still applies.
- **A failed run changes nothing.** The file is written only when four
  documents are in hand; the previous good verdict stays until a run succeeds.

## Licence, and who may run this

The companion drives **the owner's clone of QE Live's fork**. Nothing of QE
Live's source is copied into this repo. His repo has no licence file, which
means all rights reserved (`docs/ARCHITECTURE.md` §4), so **this tool is for the
owner's own machine until WKE-528 settles anything wider**. If Voulk declines,
the companion stays a personal tool and the manual paste path is what ships.

## Running it

```
cd tools\companion
npm install                 # playwright, once
copy config.example.json config.json     # then edit it if your paths differ

node companion.js           # one run over the SavedVariables as they are
node companion.js --watch   # the same, then again on every /reload
```

The fork must be on branch `lootpath/upgrade-finder-export` (it is the branch
that has the Export > Copy JSON control at all - the live site has none). If
nothing answers `http://localhost:3000` the companion runs `npm start` in the
configured clone and waits for it.

| flag | what it does |
|---|---|
| `--watch` | run once, then on every SavedVariables write |
| `--profile-only` | build the SimC profile and print it; touches no browser |
| `--config <file>` | use a different config file |
| `--out <file>` | write the chunk somewhere else (a dry run) |
| `--force` | run QE Live even when the profile is unchanged |

Changing either upgrade setting changes the question, so it also changes the
fingerprint: the next run goes to QE Live even though not a byte of gear moved.

### Seeing what it did

The companion used to be invisible unless you were watching the window that
started it: it printed to that terminal and nowhere else, so a run that DIED and
a run that had nothing to do looked identical from inside the game - an export a
few hours old, either way. That happened on 2026-09-09 (`docs/ARCHITECTURE.md`
11). Since C-9 (WKE-559) it writes two more files, both next to the verdict:

| file | what it is |
|---|---|
| `Data\companion.log` | every line the companion prints, with the date the terminal leaves out. Rotates at 200 KB, keeping one `companion.log.1`. |
| `Data\CompanionStatus.lua` | what the last run did, as a data-only Lua chunk the addon loads: `state` (`idle` / `running` / `skipped` / `failed`), `startedAt`, `finishedAt`, `stage`, `message`, `profileCapturedAt`, `verdictWrittenAt`, `exitCode`. |

The status chunk is written at **every stage change**, so a run in progress says
so rather than leaving the last run's words on screen for the minute QE Live
takes. The addon reads it at load like any other addon file and the window's
status strip carries one clause of it:

```
QE Live . Restoration Druid . Dungeon Top Gear . companion, written 3 minute(s) ago . vault pick: this week . companion: wrote 3 minute(s) ago
```

and, in the four other states,

```
companion: run started 22:48
companion: profile unchanged, no run (23:06)
companion: FAILED at profile (21:06) - see companion.log
companion: never seen
```

A `--profile-only` dry run writes the log and NOT the status chunk: it asks QE
Live nothing, so it has nothing to say about the last real run. `--out` moves
both files next to the file it is writing, for the same reason - a dry run must
not overwrite what the game is about to read.

### Starting with Windows

Neither the fork's dev server nor the watcher survives a reboot, and until C-9
nothing restarted them: the loop quietly stopped working and the only tell was
an ageing age on the status strip (`docs/ARCHITECTURE.md` 11, 2026-09-08).

```powershell
cd tools\companion
.\install-startup.ps1            # registers the logon task
Start-ScheduledTask -TaskName 'Lootpath companion'   # ... and try it now
.\uninstall-startup.ps1          # removes it
```

`install-startup.ps1` registers a Task Scheduler task for the **current user**,
**at logon**, hidden, working directory `tools\companion`, running
`start-companion.ps1`, which:

1. refuses if a `companion.js` is already running (see "never two watchers"
   below), and says which pid has it;
2. starts `npm start` in `forkPath` when nothing answers `forkUrl`, and waits up
   to `forkStartTimeoutSeconds` for the port;
3. runs `node companion.js --watch`.

Both scripts are idempotent: installing twice replaces the task rather than
doubling it, and uninstalling a task that is not there says so and exits 0.
Neither starts or stops a watcher the owner is running himself. The task runs
interactively as whoever registered it and no password is stored; a console may
flash for an instant at logon, which is Windows rather than a setting.

**Never two watchers.** Two companions over one SavedVariables file both wake on
the same `/reload`, both build the same profile and both drive the same browser
profile directory. Since C-9 the watcher takes a lock file in the state
directory (`.state\watch.lock`) and a second one refuses with exit code 7,
naming the pid that has it. A lock whose process is gone - a machine that lost
power mid-run - is taken over and said so; there is never a file to delete by
hand.

### Exit codes

| code | meaning |
|---|---|
| 0 | wrote the file |
| 1 | bad arguments or a config that cannot be used |
| 2 | no SavedVariables to read |
| 3 | the profile is incomplete - the message names every missing field |
| 4 | the fork is unreachable, or driving it failed |
| 5 | QE Live refused the profile (its own message is quoted) |
| 6 | the write failed; the previous verdict file is untouched |
| 7 | `--watch` only: another companion is already watching (it names the pid) |

## Configuration

`config.json` next to the script; `config.example.json` is the committed copy of
the defaults, which are the owner's machine. Every key is optional.

| key | default | notes |
|---|---|---|
| `wowPath` | `C:\World of Warcraft\_retail_` | the account folder under it is discovered, never configured, and never printed |
| `forkPath` | `c:\Code\qe-live-fork` | the QE Live clone to start |
| `forkUrl` | `http://localhost:3000` | |
| `documents` | Top Gear and Upgrade Finder, Dungeon then Raid | `contentType` is QE Live's own string; it has no "Mythic+" |
| `upgradeFinderKeyLevels` | `[2, 4, 6, 8, 10]` | key levels, sorted and deduplicated; the dungeon Upgrade Finder is run once per level |
| `scenarios` | `["asOffered", "catalyzed", "thisWeek", "maxed"]` | the named what-ifs Top Gear is run under; must include `asOffered`. Each what-if is asked when its own question has an answer (C-12, below) |
| `topGearPasses` | `4` | how many Top Gear passes one import may make over one content type; each pass is its own document (C-11, below) |
| `includeBank` | `true` | bank items only reach the profile if the bank was open when the capture ran |
| `qeAutoUpgradeVault` | `false` | QE Live's "Upgrade Vault to Max Level" box **for the Upgrade Finder**; Top Gear takes its boxes from the scenario |
| `qeAutoUpgradeAll` | `false` | his "Upgrade ALL to Max Level" box, likewise |
| `startFork` | `true` | |
| `headed` | `false` | show the browser when a selector stops matching |
| `stateDir` | `.state` | the browser profile (so the welcome dialog is answered once), `last-profile.json`, the fingerprint of the last verdict written, and `watch.lock`, the watcher's own lock |
| `forkStartTimeoutSeconds` | `180` | |
| `debounceMs` | `1500` | quiet time after a SavedVariables write before reading it |

### The Mythic+ key levels

QE Live's Upgrade Finder has one key selector and values every dungeon drop at
it. `upgradeFinderKeyLevels` is the list of key **levels** the companion asks
him about; the dungeon Upgrade Finder is planned once per level, and every
Upgrade Finder document says which level produced it:

```lua
        {
            schema = "qe-live-upgradefinder",
            contentType = "Dungeon",
            keyLevel = 10,
            ...
```

**A key level is not `ufSettings.dungeon`.** That field is an INDEX into his
`MPLUS_KEY_REWARDS` table (`src/Databases/MPlusKeyRewards.ts`): index 7 is the
"+10" button, whose rows come back at 311 / 321 / 334. The companion never
restates that table. It reads the labels off his own selector - `M0`, `+2/3`,
`+4`, `+8/9`, `+10` - clicks the button whose label covers the level asked for,
and then checks the export's `settings.dungeon` against the position of the
button it clicked. A level his page does not offer (`+12` today) is a named
failure, never a nearest match; a mismatch between the click and the export
fails the whole run with exit code 4, because a document filed under the wrong
key level is a wrong answer that looks right.

The Raid Upgrade Finder runs once, at the highest configured level, and records
it. WKE-543 proposed recording nothing there; the export does not allow it. On
the committed 2026-09-07 pair the Raid export carries the same 201
dungeon-sourced rows as the Dungeon one, every one stamped `dropDifficulty: 7`
at 311 / 321 / 334 - so a Raid document IS valued at a key, and is filed under
it.

Changing the list changes the question, so it changes the fingerprint: adding or
removing a level costs one run even though not a byte of gear moved. Reordering
it does not - the list is sorted and deduplicated before it is hashed.

### The two upgrade settings

QE Live's importer can raise an item to the top of its upgrade track before
valuing it. Two boxes decide which items that happens to, and **there are two
consistent ways to set them**:

| `qeAutoUpgradeVault` | `qeAutoUpgradeAll` | the question it asks |
|---|---|---|
| `false` | `false` | **the companion's default.** "What is best out of what I have, at the levels the client reports?" Everything is valued where it actually is - the vault option at the item level the Great Vault window shows, the gear on your back at the item level on its tooltip. |
| `true` | `true` | "What is best if I upgraded everything to the top of its track?" Also answerable, and the right question when you have the crests to spend on anything. |

**`true` / `false` - QE Live's own default - is neither**, and it is the pair the
companion refuses to inherit by saying nothing. It values a vault option at its
maximum and owned gear where it stands, so the two sides of the comparison are
not the same world: measured 2026-09-08, it put the vault's Lightgrasp Worldroot
in the top set at **level 321** while the client read the same link at **305**
and the owner was already wearing the item at **308**
(`docs/ARCHITECTURE.md` §9). Both numbers are facts; asked together they are not
a recommendation. Setting them the other way round (`false` / `true`) is not a
third choice: his `processItem` reads `if (autoUpgradeAll) ... else if (type ===
"Vault" && autoUpgradeVault)` (`SimCImportEngine.ts` lines 672-679), so
`autoUpgradeAll` already covers vault options and the vault box only decides
anything while it is off. Both are still clicked explicitly, because what is
being asked should not depend on reading that precedence right.

**Since C-6 (WKE-540) this pair governs the Upgrade Finder only.** Top Gear is
run once per named scenario and takes all three of its boxes from the scenario
table below. The Upgrade Finder is not a scenario question - it ranks drops you
do not own - so it is still asked under the pair configured here. When the pair
is both off (the default) those are the `asOffered` boxes exactly, so the Upgrade
Finder documents ride in the `asOffered` import and a run costs one import per
scenario and no more; set it otherwise and the Upgrade Finder gets an import of
its own, which the log names.

### The named scenarios

A vault option is what it can BECOME, not what it is offered as. QE Live models
the two transformations that matter in his import dialog - `autoCatalyze` adds a
catalyzed clone of every active item his `Item.canBeCatalyzed()` accepts, and the
two upgrade boxes raise tracked items to his `CONSTANTS.itemLevelCaps` - so
Lootpath asks him each question by name instead of modelling either.

| scenario | ALL | vault | catalyze | the question |
|---|---|---|---|---|
| `asOffered` | off | off | off | what each item is right now |
| `catalyzed` | off | off | **on** | if I catalyze what can be catalyzed |
| `thisWeek` | off | **on** | **on** | take one thing, upgrade it, use the charge once |
| `maxed` | **on** | **on** | **on** | if I upgrade everything to its cap and catalyze |

`thisWeek` (M3-13, WKE-548) is the question a player with one Catalyst charge and
a pile of crests actually asks, and none of the other three answer it:
`asOffered` assumes no charge and no upgrade, `catalyzed` assumes the charge but
no upgrade, and `maxed` assumes every item you own is at its cap, which nobody
reaches in a week. **Take one thing, upgrade it, use the charge once** - the
vault box on so the one option you take goes to the top of its track, the ALL box
off so nothing else moves. Measured 2026-09-09 19:22 on the owner's own profile:
Dungeon 5812.048, Raid 6014.255, the vault's Lightgrasp Worldroot at 321 in the
set and the Venom-Cursed Lynx's Spaulders already in his bag catalyzed into the
tier shoulder (`spec/fixtures/qe/README.md`).

The names are the contract: they are what `lib/config.js` holds, what each
document in `Data/QEVerdict.lua` carries, and what `ns.QEImport.SCENARIOS` reads
back. **Top Gear only** - the Upgrade Finder ranks drops you do not own, and
scenarios do not apply to those.

Each scenario is a separate IMPORT, not a flag on a run: `runSimC` is handed the
checkbox state at Submit (`SimCraftDialog.js` `handleSubmit`), so a box flipped
afterwards changes nothing. Measured 2026-09-09, three scenarios over two content
types: **three imports, six documents, 41.7 s warm**; the `thisWeek` import alone,
measured the same day at 19:22 through the S-1 spike, took **39.3 s** for its two
Top Gear and two Upgrade Finder documents.

**Which scenarios a run asks (C-12, WKE-577).** `asOffered` is always asked,
because Equip Now and the Upgrade Map read that document and no other. Each of
the other three is asked when ITS OWN question has an answer:

| scenario | asked when |
|---|---|
| `catalyzed` | QE Live made at least one Catalyst clone out of what you hold |
| `maxed` | at least one item you hold came back above the level the `asOffered` import valued it at, which is his engine saying it is below its cap |
| `thisWeek` | either of those |

The gate is settled INSIDE the run, after that pass's import, off the pool QE
Live built: Catalyst eligibility is his `Item.canBeCatalyzed` and an upgrade cap
is his `CONSTANTS.itemLevelCaps`, and Lootpath restates neither. So the driver
opens Top Gear, reads the cards it already reads for C-8, and counts. What a
skipped pass saves is its Top Gear documents, not its import. A profile with a
vault section that has gear in it, and `--force`, waive the gate outright.

It fails OPEN: a pool that could not be read, or a base pass that was never read,
asks the pass anyway and says so. The defect this replaced was a question skipped
for want of evidence, and it must not come back in through the guard.

Until 2026-09-14 the gate was `profile.counts.vault > 0` alone. The owner's first
refresh after claiming his vault reward refuted it: he was holding a Catalyst
candidate and a weapon two crest steps short of its cap, and the run asked about
neither because the vault was empty.

Every pass says which way its gate went, and why, in the log:

```
  catalyzed: asked - 1 Catalyst clone of what you hold
  maxed: SKIPPED - nothing you hold is below its upgrade cap
```

and a run that skipped anything says it once more, in one sentence, in the status
file's `message` (the strip's tooltip) and in the verdict's `scenarioNote` (the
Vault tab's plan footnote):

```
The upgrade question went unasked: nothing you hold is below its upgrade cap.
```

The file the addon reads carries the pair at file level:

```lua
    qeSettings = {
        autoUpgradeVault = false,
        autoUpgradeAll = false,
    },
```

each Top Gear document's scenario and its own three boxes:

```lua
        {
            schema = "qe-live-droptimizer", contentType = "Dungeon",
            scenario = "thisWeek",
            qeSettings = { autoUpgradeVault = true, autoUpgradeAll = false, autoCatalyze = true },
            ...
        },
```

and, on every Upgrade Finder document, the key level it was run at:

```lua
        { schema = "qe-live-upgradefinder", contentType = "Dungeon", keyLevel = 2, ... },
```


### The Top Gear passes (C-11, WKE-572)

A non-patron's Top Gear answers a question about **thirty** items
(`TopGear.tsx:177`, `topGearCap = patronCaps[patronStatus] || 30`), and the owner
owns more. C-8 chose which thirty and said out loud which ones it did not, and
that honesty was the whole of the problem: on the 2026-09-14 11:42 run the log
read `30/30 of 63 (20 active, 10 clicked, 33 left out)`, **22 of the 33 were
trinket rows**, and every one of them showed in game as `not rated · beyond the
rating's item limit`. A verdict that cannot speak about gear the player is
holding makes the honest phrases look like the addon's fault.

So a Top Gear run is a SEQUENCE of passes now, and the fork's cap is still never
edited (§7, 2026-09-07: the fork is read and driven, never changed in what it
decides).

* **The baseline** is the cards QE Live made active at IMPORT, read once per
  import before anything is clicked. His own engine says what they are: a vault
  item is active from the moment it is imported (`SimCImportEngine.ts:712`) and a
  Catalyst clone inherits its source's flag (`Item.ts:174`), so the baseline is
  the equipped set, the vault options, and the clones of those. It is in every
  pass, and nothing here ever deselects one.
* **Pass 1** is exactly C-8's pool: the baseline, then the room spent on the
  vault, the clones and the bags, a slot at a time.
* **Each later pass** keeps the baseline, deselects the bag items the previous
  pass clicked, and spends the room on cards no pass has asked about yet. No card
  outside the baseline is ever asked about twice.
* **Every pass is its own document**, over its own pool. Nothing is merged and no
  two numbers are ever combined: Lootpath never computes a healer value.

The loop stops on the first of three things: nothing left out, no room past the
baseline to make progress with, or `topGearPasses`. A run that hits the bound
says so in the log and leaves the rest on the file's `excluded` list, which is
then the one list that honestly still means "beyond the rating's item limit".

Each Top Gear document says which pass it is and what that pass was shown:

```lua
        {
            schema = "qe-live-droptimizer", contentType = "Dungeon",
            scenario = "asOffered",
            pass = 2,
            qeSettings = { autoUpgradeVault = false, autoUpgradeAll = false, autoCatalyze = false },
            considered = {
                { slot = "Trinket", name = "Seed of Radiant Hope", level = 308, itemID = 251234, bonusIDs = { 42 } },
            },
            excluded = { ... },
            ...
        },
```

`pass` absent means pass 1, so every file written before C-11 and every paste
still says exactly what it said. `considered` is the same shape as `excluded`,
because the addon asks the same identity question of both lists (C-10) and a
second shape would be a second answer to it.

**What the addon does with them.** Pass 1 is the plan and nothing else is: Equip
Now, the Upgrade Map, the plan sentence and the best set read pass 1, and a later
pass is filed on a shelf none of them can reach (`ns.QEImport.Passes`). An item's
RATING comes from the pass that considered it. A later pass's pool has no vault
option and no Catalyst clone in it, so a later pass's percents are against that
pass's own top set and no percent from one is ever printed beside a pass-1 row;
what the addon says instead is `rated · better than what you wear` when the pass
put the item in its own best set, and `not in your best set` when it did not.

The bound is in the fingerprint (C-4), for the same reason the scenarios and the
key levels are: raising it asks QE Live about items the last run never showed
him, and lowering it drops documents the verdict file is still carrying.
## What it is made of

| file | what it does |
|---|---|
| `companion.js` | the CLI: one run, or a watch |
| `lib/config.js` | config, SavedVariables discovery, the verdict path |
| `lib/lua-savedvariables.js` | reads the Lua subset the client writes, without a Lua runtime (S-2's) |
| `lib/simc-profile.js` | SavedVariables -> SimC text, mirroring the SimulationCraft addon (S-2's) |
| `lib/profile.js` | the thin shape the CLI reads, plus the spec check |
| `lib/fork.js` | drives QE Live, lifted from the S-1 spike; sets the checkboxes by their label and reads them back (C-5), one import per scenario (C-6) |
| `lib/luawriter.js` | renders `Data/QEVerdict.lua`; its escaper is the whole safety story |
| `lib/output.js` | temp file, then rename, so the client never reads half a file |
| `lib/watch.js` | one run per `/reload`, never one per byte written |
| `lib/fingerprint.js` | is this the profile QE Live was already asked about? (C-4) |
| `lib/status.js` | renders `Data/CompanionStatus.lua` - what the last run did (C-9) |
| `lib/lock.js` | never two watchers: the lock file and whose pid holds it (C-9) |
| `start-companion.ps1` | the fork if it is not up, then the watcher - what the logon task runs (C-9) |
| `install-startup.ps1` / `uninstall-startup.ps1` | register and remove that logon task (C-9) |

`lib/config.js` also owns `plannedPasses(config, { hasVaultGear, force })`, which
turns the configured lists into the PASSES one run makes over QE Live - an import
with one set of checkboxes, then every document that import can answer - and
`plannedDocuments`, which is that flattened. A pass exists because the boxes act
at import (C-6); inside one, the dungeon Upgrade Finder is fanned out over
`upgradeFinderKeyLevels` (C-7). Since C-12 a what-if pass also carries a `gate`
for the driver to settle after its import, and the pure half of that decision -
`levelsByItem`, `poolEvidence`, `gateVerdict`, `scenarioNote` - lives there too,
so every word the log, the status file and the verdict say about a skipped
question is written in one place.

## What the addon gets

```lua
local _, ns = ...
if type(ns) ~= "table" then
    return
end
ns.companionVerdict = {
    writtenAt = "2026-09-08T00:15:02Z",
    companionVersion = "0.1.0",
    profileCapturedAt = "2026-09-05T13:33:25",
    qeSettings = {
        autoUpgradeVault = false,
        autoUpgradeAll = false,
    },
    -- Only when a run asked fewer questions than the config lists (C-12).
    scenarioNote = "The upgrade question went unasked: nothing you hold is below its upgrade cap.",
    exports = {
        { schema = "qe-live-droptimizer", contentType = "Dungeon", bytes = 16315, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Dungeon", keyLevel = 2, bytes = 118981, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Dungeon", keyLevel = 4, bytes = 119038, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Dungeon", keyLevel = 6, bytes = 98092, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Dungeon", keyLevel = 8, bytes = 98320, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Dungeon", keyLevel = 10, bytes = 120017, json = "..." },
        { schema = "qe-live-droptimizer", contentType = "Raid", bytes = 16263, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Raid", keyLevel = 10, bytes = 120396, json = "..." },
    },
}
```

The shape is **the addon's**, settled by C-2 (WKE-534, `Lootpath/Modules/Companion.lua`):
`Companion.Entry` dispatches on `schema`, treats `contentType` as advisory (the
content type inside the JSON is the one an import is filed under) and ignores
any field it does not know, which is where `bytes`, `profileCapturedAt` and
`qeSettings` sit - the addon reads none of the three today, and WKE-538 may show
the last of them on the Vault tab.
It feeds each `json` to `ns.QEImport.Parse` (Top Gear) or refuses it by name
until WKE-535's reader exists (Upgrade Finder).
`spec/fixtures/expected/qeverdict-sample.lua` is a committed sample, and
`spec/companionfile_spec.lua` loads it in a real Lua interpreter.

## Things that bite

- **`tools\sync.ps1` would clobber the verdict file the moment the repo ships a
  placeholder at the same path.** Measured 2026-09-08 by running `Push-Addon`'s
  `Copy-Item -Path Lootpath\* -Destination <game> -Recurse -Force` in a temp
  tree: with no `Data\` in the repo the companion's file survives a sync
  untouched; with a repo `Data\QEVerdict.lua` in place, the sync overwrites it
  with the placeholder. C-2 (WKE-534) ships that placeholder and answers this by
  making `sync.ps1` leave an existing copy alone unless it is passed
  `-IncludeData`; a sync that did use it costs one companion run.
- **QE Live values the spec selected in ITS OWN character panel**, not the
  `spec=` line: `runSimC` never reads that line. Measured 2026-09-08 - a profile
  written `spec=guardian` came back as a "Restoration Druid" report, because
  that is what the browser profile held. The companion compares the two and says
  so; getting it right is a matter of picking the spec once in the fork.
- **`talents=` is never read by QE Live either.** grep over the whole fork finds
  no reader for it, so a profile without talents is complete for Top Gear and
  the Upgrade Finder. That is why the companion does not ask the addon for one.
- **The profile builder is S-2's (WKE-532), lifted here from
  `tools/companion-spike/` so there is one copy rather than two.** It mirrors the
  SimulationCraft addon's own offsets and slot tables, reproduces the client's
  `# Checksum:` line, and enforces QE Live's two line-index rules itself. C-1
  wraps it in `lib/profile.js` only to turn a throw into a named exit code and to
  add the spec check.
- **The bank only reaches the profile if it was open** when
  `/lootpath capture inventory` ran; the companion says so in its log.
- **A field the SavedVariables do not carry is left out, never written empty.**
  `region`, `level` and `race` come from `capture env`, which only learned to
  read them in S-2 - so until the owner runs a fresh `capture env`, those three
  lines are missing and the log names each one. QE Live reads only `region` of
  the three, and reads it from any line.
- **Top Gear's item cap is 30** for a non-patron, so a large bag plus bank is
  trimmed to the first 30 candidates by the fork itself.
- **The debounce is not what stops the second run, and never was.** It is still
  1500 ms and only keeps the companion from reading a file the client is halfway
  through writing. Two reloads twenty seconds apart really are two writes, and
  the second must be READ - the owner may have opened the bank and captured
  between them - so it is the profile that decides whether QE Live is asked, not
  the write. Skipping is decided on the profile the fork would be handed, not on
  the SavedVariables: anything the profile does not carry cannot change QE Live's
  answer, and anything it does carry does.
- **Forgetting costs a run; it never skips one.** A missing, unreadable or
  half-written `.state/last-profile.json` runs QE Live and says why, and the
  fingerprint is stored only after the verdict file is safely written.

## Tests

```
npm test        # node --test, no install needed for the pure parts
```

186 tests over the reader, the profile builder, the config, the writers, the
watcher, the fingerprint, the log file, the status chunk, the watcher's lock,
the driver's checkbox step, its key selector and its scenario passes. The profile builder is measured against the owner's
own `/simc` string (`spec/fixtures/simc/hotornot-20260907.txt`) and against a
committed generated profile; the writer's golden is loaded by a real Lua interpreter in
`spec/companionfile_spec.lua`. The fork driver is not mocked: it is proven by a
recorded run, whose figures are in the pull request. C-4's guards drive the real
`once()` over a fake game folder in the OS temp directory with an injected fork
driver, so no browser opens and nothing is written near the real game folder.
C-5's checkbox step is proved against a fake page that records every click and
answers `isChecked` the way his controlled MUI checkboxes do; that Playwright
finds those boxes by label in a real page is a recorded run, not a test. C-7's
key selector is proved the same way, against a fake page carrying his eight
toggle labels plus a decoy row of raid difficulties - what is NOT proved there is
that the "Mythic+ Key Level" Paper is the one Playwright finds in his real page,
and that is the recorded run in the pull request. C-6's scenario table is
proved over the plan (`plannedPasses`) and the same fake dialog, and end to end
through `once()`: with no vault gear only `asOffered` is asked, `--force` asks
all three, and changing the list costs a run. C-9's log and status chunk are
driven the same way - a whole fake `_retail_` in the temp directory, the fork
injected - and twice through the real CLI in a child process, because the log
file and the status recorder are `main()`'s to wire and no in-process test can
say it did. **What is NOT tested is the Task Scheduler task**: there is no
Windows and no logon in CI, so `install-startup.ps1` is proved by the owner
registering it once and rebooting (WKE-559). What IS tested of the three scripts
is that install and uninstall name the same task and that the task starts the
script that starts the watcher - the part that breaks silently when a file is
renamed.
