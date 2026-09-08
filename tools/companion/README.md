# The Lootpath companion (C-1, WKE-533)

A program on the owner's own PC that closes the gearing loop without a browser
in it. It reads Lootpath's SavedVariables, builds the SimulationCraft profile
from them, runs QE Live's engine in the owner's local fork, and writes one file
back into the addon folder.

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
- **It never writes anywhere but `Data/QEVerdict.lua`** inside
  `Interface\AddOns\Lootpath\`, and it refuses if the addon is not installed
  rather than creating a folder.
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

## Configuration

`config.json` next to the script; `config.example.json` is the committed copy of
the defaults, which are the owner's machine. Every key is optional.

| key | default | notes |
|---|---|---|
| `wowPath` | `C:\World of Warcraft\_retail_` | the account folder under it is discovered, never configured, and never printed |
| `forkPath` | `c:\Code\qe-live-fork` | the QE Live clone to start |
| `forkUrl` | `http://localhost:3000` | |
| `documents` | Top Gear and Upgrade Finder, Dungeon then Raid | `contentType` is QE Live's own string; it has no "Mythic+" |
| `includeBank` | `true` | bank items only reach the profile if the bank was open when the capture ran |
| `qeAutoUpgradeVault` | `false` | QE Live's "Upgrade Vault to Max Level" box, set explicitly every run |
| `qeAutoUpgradeAll` | `false` | his "Upgrade ALL to Max Level" box, likewise |
| `startFork` | `true` | |
| `headed` | `false` | show the browser when a selector stops matching |
| `stateDir` | `.state` | the browser profile (so the welcome dialog is answered once) and `last-profile.json`, the fingerprint of the last verdict written |
| `forkStartTimeoutSeconds` | `180` | |
| `debounceMs` | `1500` | quiet time after a SavedVariables write before reading it |

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

The Catalyst - his third box, "Auto Catalyze" - is **not touched**. It is
WKE-540's question (named scenarios, run several times), and a box nobody asked
about is left exactly where his dialog put it.

The file the addon reads carries the pair:

```lua
    qeSettings = {
        autoUpgradeVault = false,
        autoUpgradeAll = false,
    },
```

## What it is made of

| file | what it does |
|---|---|
| `companion.js` | the CLI: one run, or a watch |
| `lib/config.js` | config, SavedVariables discovery, the verdict path |
| `lib/lua-savedvariables.js` | reads the Lua subset the client writes, without a Lua runtime (S-2's) |
| `lib/simc-profile.js` | SavedVariables -> SimC text, mirroring the SimulationCraft addon (S-2's) |
| `lib/profile.js` | the thin shape the CLI reads, plus the spec check |
| `lib/fork.js` | drives QE Live, lifted from the S-1 spike; sets the two upgrade boxes by their label and reads them back (C-5) |
| `lib/luawriter.js` | renders `Data/QEVerdict.lua`; its escaper is the whole safety story |
| `lib/output.js` | temp file, then rename, so the client never reads half a file |
| `lib/watch.js` | one run per `/reload`, never one per byte written |
| `lib/fingerprint.js` | is this the profile QE Live was already asked about? (C-4) |

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
    exports = {
        { schema = "qe-live-droptimizer", contentType = "Dungeon", bytes = 16315, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Dungeon", bytes = 120577, json = "..." },
        { schema = "qe-live-droptimizer", contentType = "Raid", bytes = 16263, json = "..." },
        { schema = "qe-live-upgradefinder", contentType = "Raid", bytes = 120396, json = "..." },
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

91 tests over the reader, the profile builder, the config, the writer, the
watcher, the fingerprint and the driver's checkbox step. The profile builder is measured against the owner's
own `/simc` string (`spec/fixtures/simc/hotornot-20260907.txt`) and against a
committed generated profile; the writer's golden is loaded by a real Lua interpreter in
`spec/companionfile_spec.lua`. The fork driver is not mocked: it is proven by a
recorded run, whose figures are in the pull request. C-4's guards drive the real
`once()` over a fake game folder in the OS temp directory with an injected fork
driver, so no browser opens and nothing is written near the real game folder.
C-5's checkbox step is proved against a fake page that records every click and
answers `isChecked` the way his controlled MUI checkboxes do; that Playwright
finds those boxes by label in a real page is a recorded run, not a test.
