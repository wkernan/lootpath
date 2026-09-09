# Changelog

## Unreleased

### M3-12 (WKE-547) - vault rewards read before their item data is cached

- **No more `[] (nil)` on the Vault tab after a client restart.** Right after
  logging in, the client hands over a reward's link with an empty name and
  answers nothing for its item level; the tab printed both. A reward like that
  is now `pending`: its row reads `name pending (item 275547) - level pending`
  in the panel's grey - or `Preyhunter's Lantern (from the last capture) -
  level pending` when an earlier vault snapshot named the same reward - and the
  headline uses the same words. Its key is intact, so every QE Live line under
  it, the counts and the pick are exactly what they were.
- **Lootpath asks the client for the item and reads it again.** One
  `C_Item.RequestLoadItemDataByID` per pending item, a second read on the
  client's load event (or on a bounded timer, 8 x 0.25 s, like the journal's),
  and one redraw of the Vault tab when it is the tab on screen. A reward the
  client never describes stays pending in words and is asked for again on the
  next look; nothing is guessed.

### M2-4 (WKE-541) - Equip Now says plainly when the best set is in the vault

- **A Great Vault option in QE Live's best set is not a "not owned" swap.** The
  tab used to draw it in the same red as a real gap -
  `[Lightgrasp Worldroot] -> item 251935 (ilvl 321) (not found: it is a Great
  Vault option you have not taken yet)` - for an item that is not missing at
  all, only unclaimed. The row now shows the piece you are wearing meanwhile,
  and a line under it says
  `QE Live's best set has a Great Vault option in this slot: Lightgrasp
  Worldroot (QE Live's level 321) - see the Vault tab`. The summary counts it
  apart: `14 already best, 0 to swap, 1 waiting in the Great Vault, 0 not
  owned, 0 without a verdict`.
- **Nothing is cut off at the frame's edge any more.** Every sentence a row has
  to say - the vault line, and the reason an item really was not found - now
  goes on its own wrapping line whose width comes from the row rather than from
  a fixed number.
- The Equip button is unchanged, and a vault row offers none: nothing here
  equips anything new.

### M3-7 (WKE-538) - the Vault panel against the real reward shape

- **The Mythic Keystone is no longer listed as gear.** The client hands one over
  in the same rewards list as every gear reward (and row 217 a Thalassian Token
  of Merit as well), and the panel showed it as "Mythic Keystone (1)" beside a
  305 weapon, where the 1 reads as an item level. Anything with no equippable
  slot is now named in words on the gear's own line - "+ Mythic Keystone" - with
  no level and never a value, and it is neither counted as an option nor
  eligible for QE Live's pick.
- **A row with rewards says "rewards ready".** After the weekly reset the client
  puts every activity's progress back to 0 while the rewards sit there
  claimable, so "unlocked" (progress >= threshold) read false on exactly the
  rows you can collect from. A row with no reward still shows its progress.
- **Both item levels, when they differ.** QE Live can be asked to value a vault
  option at its assumed upgrade, so the same link is 305 in the client and 321
  in the export that ranked it. The line now reads
  `Lightgrasp Worldroot (305; QE Live valued it at 321)`, and names which
  upgrade assumption produced his number when the companion recorded it
  (`qeSettings`, C-5). Neither number is adjusted and neither is chosen over the
  other; nothing is inferred from the difference.
- The rows carry the Great Vault window's own names - **Dungeons**, **Raids**,
  World - so one vocabulary covers both screens. `ns.Vault` keeps the measured
  enum's, and is untouched by all of the above.

### C-5 (WKE-539) - the companion asks QE Live for both upgrade settings

- **The companion no longer inherits QE Live's asymmetric import defaults.** His
  dialog opens with "Upgrade Vault to Max Level" on and "Upgrade ALL to Max
  Level" off, which values a vault option at the top of its upgrade track and
  the gear on your back where the client reports it - so a 305 vault weapon was
  ranked above the 308 copy already equipped. The driver now sets both boxes on
  every run, by the label each is rendered with, reads them back, and fails the
  run rather than reporting a setting it did not get.
- **Both default off**, which asks one answerable question: what is best out of
  what you have, at the levels the client reports. `qeAutoUpgradeVault` /
  `qeAutoUpgradeAll` in `config.json` set the other consistent pair (both on)
  for a "what if I upgraded everything" run. "Auto Catalyze" is not touched.
- `Data/QEVerdict.lua` records the pair as `qeSettings`, so a verdict is
  readable next to the question that produced it. M3-7 is what reads it: the
  Vault panel names the assumption behind QE Live's item level.
- Changing either setting changes the fingerprint, so the next run goes to QE
  Live even though no gear moved.

### M3-6 (WKE-535) - the Upgrade Finder import

- `ns.UFImport`: QE Live's `qe-live-upgradefinder` v1 export - the one that
  values drops you do **not** own - parsed and stored. Its own module, because
  its sign convention is the opposite of Top Gear's while the constant is the
  same `+1`: `upgradePercent` and `hpsGain` are positive when the drop is
  BETTER. Refuses the wrong schema (naming both), a `version` that is not the
  number `1`, a missing `items` list and a non-Retail export; warns on a
  character mismatch, an empty export, skipped drops and a drop listed twice
  with different values. Entries key on **itemID + item level**, because the
  stored report carries no bonus IDs; a drop several drop types list is one
  entry with several `sources`. Filed per content type in `db.char.ufImports`
  beside `db.char.qeImport`, so neither kind can overwrite the other.
- **One paste box, two schemas.** `UI.DetectSchema` reads the `schema` string
  without decoding the blob and `UI.ImportAny` routes it; the status line says
  which kind was imported and, when the character has both for that content
  type, shows the other one's age too. A third schema is refused by name.
  `UI.ActiveUpgradeFinder()` picks the export the content-type setting asks for,
  exactly as `UI.ActiveVerdict()` does for Top Gear.
- **The Upgrade Map has a second path to a number**, and it is still QE Live's
  own: a row whose itemID and item level the Upgrade Finder ranked shows his
  percentage. Measured over the committed fixtures - the 2026-09-06 20:09 cold
  walk against the 2026-09-07 Dungeon export - **30 of 478 rows gained a
  number**; 218 rows over 97 distinct drops are ranked at another item level,
  show nothing, and are counted with a line saying so. A zero reads "no change"
  rather than a direction QE Live did not give, `hpsGain` never reaches a row,
  and a pending row is never joined because its level is unknown, not wrong.
- **The companion's Upgrade Finder documents are read, not refused.** C-2 left
  `ns.Companion` refusing a `qe-live-upgradefinder` entry by name; it now picks
  the importer by schema and calls only `Parse`, `ContentTypeKey`,
  `ForContentType` and `Store` on it, so the staleness check compares like with
  like - a Top Gear import is never made stale by an Upgrade Finder one for the
  same content type - and the chat line names the kind, as the window does.

### C-2 (WKE-534) - the addon side of the local companion

- `Lootpath/Data/QEVerdict.lua`, listed in the `.toc` after `Core.lua`: the one
  file besides a paste that QE Live's answers reach the addon through. The
  committed copy is a placeholder that sets nothing and ships with the addon,
  because the `.toc` names it; the companion overwrites it on the owner's own
  machine. Its contract is one assignment - `ns.companionVerdict = { writtenAt,
  companionVersion, exports = { { schema, contentType, json } } }`, Lua strings,
  numbers and tables only.
- `ns.Companion` imports it at load: every field type-checked and passed through
  `ns.Safe`, nothing in the chunk called, no `loadstring`, and each export run
  through **the same `ns.QEImport.Parse` a paste goes through**, so every
  schema, version and `gameType` refusal applies word for word and is reported
  in chat with the file's age. A `qe-live-upgradefinder` document is refused by
  name until M3-6 can read one.
- The later of the file and what is stored wins: a paste made after the
  companion wrote its file is kept and says so, and reading the same file again
  on the next `/reload` imports nothing and says nothing.
- The window's verdict line and `/lootpath status` say where the verdict came
  from - "pasted", or "companion, written 4 minute(s) ago".
- `/lootpath refresh`: one word for the reload the loop needs, refused in combat
  because `ReloadUI` is protected there.
- `tools\sync.ps1` no longer overwrites the game's `Data\QEVerdict.lua` with
  the repo placeholder; `-IncludeData` does it deliberately.

### M2-2 (WKE-520) - Match, the paste editbox and the Equip Now panel

- `ns.Match.Build(inventory, verdict)`: QE Live's top set joined to the
  Inventory scan, one row per gear slot the export names plus one for anything
  worn in a slot it does not. Statuses `equipped_is_best`, `swap`,
  `best_not_owned` (saying whether it is an unclaimed vault option, a bank
  Lootpath cannot see into, or simply absent) and `no_verdict`. Exact
  `ns.ItemKey` first; an itemID + item-level fallback that reaches both the
  result and the chat frame; an itemID-only match is never accepted. Each
  inventory record is claimed once, so a matched pair of rings needs two.
- The first window. `/lootpath` opens a movable native frame with the paste
  editbox (`InputScrollFrameTemplate`, `SetMaxLetters(0)`), an import status
  line showing the spec, content type, export age and item count - or the
  parser's refusal verbatim - and the Equip Now panel: one row per slot,
  equipped -> best with item links, an **Equip** button per swap and an
  **Equip all**. Equipping goes through `C_Item.EquipItemByName(link, dstSlot)`
  with `dstSlot` taken from the scan, so two rings and two trinkets never
  fight over one slot.
- Nothing equips in combat: the buttons disable with a tooltip saying so, the
  refusal is repeated inside `Equip` itself, and the panel keeps the last scan
  on screen marked stale rather than blanking mid-pull.
- Options page through the `Settings` API, one setting: which content type's
  verdict the panels read. **QE Live's content types are `Dungeon` and `Raid`**
  (`src/globalTypes.d.ts`), so the default moved from `Mythic+`, a string no
  export can carry, to `Dungeon`. Imports are now filed by content type in
  `db.char.qeImports` as well as most-recent in `db.char.qeImport`, so pasting
  a Raid export no longer loses the Dungeon one.
- The test stub grew a widget model (frames, buttons, font strings, an editbox,
  GameTooltip and the Settings API), so the window is driven headlessly: a
  click really reaches `QEImport.Parse` and a 200 KB paste really round-trips.

### M3-1 (WKE-522, PR 1) - Journal adapter and `capture journal`

- `ns.JournalAdapter`: the only place the addon touches the Encounter Journal.
  Every call goes through `ns.Probe` and `ns.CopyRaw`, so returns stay exactly
  as the client gave them, secrets are masked and counted, and a function this
  client does not have is a finding (`Availability()`) rather than a crash.
- `JournalAdapter.Walk` drives instance / difficulty / loot filter / M+ preview
  level per target, waits for `EJ_LOOT_DATA_RECIEVED` on a bound (8 attempts,
  0.25s apart) rather than assuming the loot list is ready, counts the events,
  waits, timeouts and elapsed time, abandons the walk if combat starts, and
  restores the journal's tier, difficulty and loot filter when it finishes.
- `/lootpath capture journal [preview level]` dumps the season's M+ pool, both
  candidate map-to-instance lookups side by side, the maps neither resolved,
  the tiers, the raid list, and every raw loot row per target with the item
  level and equip location the loot rows themselves do not carry. For WKE-523.
- Captures can now be asynchronous: `ns.RegisterCapture(..., { async = true })`
  gets a `finish` callback, `RunCapture` answers `pending`, only one capture
  runs at a time, and one that never calls back is abandoned after 180s.
- `ns.Journal` (the pure aggregator and its cache) lands in PR 2, written
  against WKE-523's transcript rather than against a guess.

### M2-1 (WKE-518) - QEImport

- `ns.QEImport.Parse(text)`: QE Live's `qe-live-droptimizer` v1 Top Gear JSON
  in, a verdict model out, or one plain refusal. Refuses an empty paste,
  non-JSON, non-object JSON, another tool's schema, any `version` that is not
  the number `1` (naming both), a missing `topSet`, and a non-Retail export.
  Warns without refusing when the export is for another character, when the
  top set is empty, and when an item carried no usable itemID.
- Verdict: `topSet` keyed by `ns.ItemKey` with the export's own order and a
  count per matched pair, `alternatives` carrying QE Live's `scorePercent` and
  `hpsDifference` unchanged, and `vault` gathering every vault option the
  export mentions - including the ones QE Live ranked below the top set.
- `ns.QEImport.AlternativeIsBetter` is the single reading of QE Live's sign
  convention, verified twice from its source and pinned in the tests.
- The last import is stored in `db.char.qeImport` with its `exportedAt`.
- Tests run over real JSON text: a hand-built v1 sample under
  `spec/fixtures/qe/` until the owner commits a genuine export (WKE-519), for
  which the spec carries a `pending`.

### M1-1 (WKE-516) - Inventory

- `ns.Inventory:Scan()`: equipped slots, owned bags and, while the bank is
  open, every bank tab, normalised to one record per piece of gear with a
  QE Live slot name and the item key. Refuses in combat; reports
  `bankAvailable`; drops and counts secret values.
- `ns.ParseItemLink`: the one item-link parser (bonus IDs sorted, crafter GUID
  and atlas markup tolerated, keystone links rejected).
- Tests replay the 2026-09-05 transcript through the stub; golden fixtures
  under `spec/fixtures/expected/`.

### M0-1 (WKE-514) - skeleton

- Addon layout under `Lootpath/`, AceDB SavedVariables, the shared namespace,
  the secret-value guard (`ns.Safe`, `ns.CopyRaw`), `ns.ItemKey`, and the
  `/lootpath` dispatcher.
- Captures: `/lootpath capture env`, `inventory`, `vault` dump raw client
  returns to SavedVariables for the owner's transcripts.
- CI gates: luacheck, StyLua, lua-language-server (Ketho annotations), busted,
  BigWigsMods packager zip on every PR and a GitHub release on `v*` tags.
- Dev tooling: `tools/check.ps1`, `tools/sync.ps1`, `tools/fetch-libs.ps1`,
  `tools/fetch-annotations.ps1`, `tools/docker/Dockerfile`.
- Vendored rxi/json.lua (MIT). Ace3 LibStub, CallbackHandler-1.0 and AceDB-3.0
  as packager externals.
