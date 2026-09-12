# Changelog

## Unreleased

### Fix (2026-09-12)

- **The "items left out" note names no source.** The Equip Now and Vault tabs
  said "QE Live did not consider N of your items"; they now say "N of your
  items weren't rated this time", per the 2026-09-11 decision that nothing on
  screen names where a rating came from.

### C-10 (WKE-567) - a left-out item is identified, not just named

- **The excluded list carries the item's identity.** Each entry in
  `Data/QEVerdict.lua` now holds `itemID`, the sorted `bonusIDs` and - on a
  Catalyst clone - the `originalItem` it was made from, read off the
  `data-wowhead` attribute QE Live's own card carries. The addon builds its one
  `ns.ItemKey` from the first two, so "was this item left out of the pool" is an
  identity comparison instead of a name comparison; two same-named items at one
  item level used to answer it as one.
- `ns.Companion.ExcludedKey(entry)` and `ns.Companion.IsExcluded(excluded, key,
  item)` are the join, for the road surfaces that must say `not rated - beyond
  the rating's item limit` about one item and not about its twin. An entry that
  carries no identity - every file written before this change - is still matched
  by name and level, and the answer says which of the two it was.
- **All or nothing:** a bonus list the addon cannot read whole takes the item ID
  down with it, and the companion refuses to write one rather than trimming it.
  A shortened bonus list is a perfectly valid key for an item nobody owns.
- Nothing on screen changed: the wording, the counts and the names are C-8's.

### C-8 (WKE-558) - QE Live is asked about the right thirty items, and says which it was not

- **The companion no longer fills QE Live's Top Gear in page order.** His Top
  Gear takes 30 items for a non-patron and the character owns more, so the
  driver now reads every card first, keeps everything the import made active
  (the equipped set, the Great Vault options and their clones), and spends the
  room on Great Vault items, then every Catalyst clone, then bag items one slot
  at a time. Page order was his slot list, so the weapons and every Catalyst
  clone used to fall off the end: on 2026-09-09 the `catalyzed` scenario scored
  identically to `asOffered` because not one clone was in the pool.
- **Nothing that arrived selected is ever deselected.** A card that is active at
  import is equipped gear, a vault option, or a clone of one - never a bag item.
- **The Equip Now and Vault tabs say what was left out**: `QE Live did not
  consider 27 of your items: ...`, in one shared wording, with every name
  available to the tab that wants to show them all. A verdict that omits items
  says so on screen.
- `Data/QEVerdict.lua` carries an `excluded` list beside `qeSettings` and on
  every Top Gear document. A file written without one reads exactly as before.
- **The cap itself is untouched.** It is QE Live's own patron rule and the fork
  is read and driven, never changed in what it decides.

### Fixes (2026-09-09, the owner's first look at the M5 window)

- **The Upgrade Map tab no longer errors on open.** Its difficulty dropdown
  was built from Blizzard's filter template, which has a fixed "Filter" caption
  and no way to show the chosen difficulty; the tab asked it to anyway and the
  client raised "attempt to call a nil value". It is now the selection
  template the Vault tab already uses, and the headless client models what each
  template really has.
- **The companion no longer dies on an empty bag slot.** Blizzard writes a freed
  slot between two filled ones as a literal `nil,` in the SavedVariables; the
  walk over bag items, equipped items and vault rewards now steps over it
  instead of reading `.link` on nothing. Every `/lootpath refresh` had been
  failing with exit code 3 and leaving the old verdict in place.
- **The minimap button sits outside the minimap you actually have.** The
  launcher read a fixed 80-point radius; it now measures the minimap at every
  placement, follows it when an addon resizes it, and rides the edge of a
  square minimap (ElvUI) instead of a circle inside it.

### M5-4 (WKE-553) - the Vault, drawn as the vault

- **The tab is the Great Vault**: three rows - Raids, Dungeons, World, in
  Blizzard's own order and under the client's own headings - of three option
  cells. Each cell is the reward the client is offering there, drawn as an item
  line: its own icon with a quality-coloured border, its item level in the
  icon's corner, the name in quality colour, and a grey line saying the slot
  and the level. A cell you have not earned yet says what the client says it
  needs ("Defeat 4 Midnight Season 2 Bosses").
- **QE Live's pick carries the Great Vault's own selected glow** - Blizzard's
  `evergreen-weeklyrewards-reward-selected`, or a gold border on a client that
  no longer has that art - and a "QE Live's pick" label. When the honest answer
  is "none - nothing in the vault beats your set", **no cell glows**: the
  closest option gets a grey "closest" label instead, so the grid and the
  headline never disagree.
- **One scenario on the cell, all of them one hover away.** The cell shows the
  line for the scenario the highlight follows; hovering it shows every
  scenario's line, word for word the same strings the text panel prints.
  Hovering the icon or the name still opens the item's own tooltip with the
  shopping compare.
- **The scenario dropdown is on the tab itself**, beside the header, in the
  Settings page's own words and writing through the same one setting. The
  Settings page keeps its copy.
- **The crests and the Catalyst charge are drawn with the client's own icons**
  and the client's own names, in a strip under the grid. Still no arithmetic:
  a chip is a name, an icon and the number the client reports.
- The headline block is unchanged and still comes first, now with the pick's
  icon beside it and its first line in a larger font.
- Nothing the vault offers is off the screen: the Mythic Keystone that rides
  in with a reward is named on its cell, and the rows Blizzard does not draw -
  Concession, "Also receive" - are listed under the grid.

### M5-3 (WKE-552) - the Upgrade Map, drawn

- **The list is a real list.** Both views moved from a column of one font
  string per line to Blizzard's own `WowScrollBoxList` over a data provider,
  so the committed walk's 478 drops cost the frames that fit on screen rather
  than one frame per drop.
- **By slot: a collapsible section per slot**, headed by the icon and item
  level of what that slot is wearing and by how many drops it has. Candidate
  rows are the M5-1 item line - the drop's own icon, its name in quality
  colour, and a grey second line saying `boss - instance, difficulty`.
  `[owned 305]` is the "Owned" tag; QE Live's verdict is the badge on the
  right, with the document that gave the number - `(at +6)` - in grey after
  it. Which sections are shut is remembered per character.
- **By run: a card per run** - the instance's own Adventure Guide art as a
  left strip, the run and its difficulty, `best +1.83%` as QE Live's badge and
  the drop count in grey. A card opens onto its rated drops. The two sort
  orders stay two orders and are never combined into a score.
- **One difficulty dropdown** in place of the row of buttons that used to wrap
  (and, before that, run off the window's edge). It is the 11.0 menu API, and
  its rows are the map's own difficulties with the map's own counts.
- **The journal walk now records the instance's art** (`buttonImage1`,
  `buttonImage2` and `bgImage` from `EJ_GetInstanceInfo`, all file IDs the
  client hands over) and the aggregator keeps the loot row's `icon`. Both are
  reads of a call the walk already made; the capture still touches nothing.
  Every walk taken before this change has no art, and a run card with no art
  draws a plain strip rather than a stand-in picture.
- Nothing about the numbers changed. `Panel.Lines` and `Panel.RunLines` are
  byte for byte what they were, every join is untouched, and every badge is
  still one of QE Live's own sentences.

### M3-15 (WKE-556) - a catalyzed vault reward costs a charge

- **The "one charge" line counted a converted Great Vault reward as free.** The
  Catalyst spends one charge per item it converts, and it does not care whether
  the item came out of a bag or out of the vault. M3-14 counted only the
  owner's own items, so a set that converts his chest AND the vault's shoulders
  was shown as spending the charge once.
- **Every conversion is counted now, the vault's included.** A tier item the
  export flags as a vault option is a charge unless the vault is offering that
  very item ID - a reward that arrives as a tier piece already converts
  nothing. With no vault snapshot to compare against, a vault tier item counts
  as a charge: calling a conversion free is the one mistake worth avoiding.
- **On the owner's own week the honest answer is an absence.** All three sets
  the old count offered also convert the vault's Scavenger's Spaulders, so the
  line now reads "not in QE Live's export - no set he ranked spends the charge
  just once" on both the Dungeon and the Raid document.
- **The scenario lines say when a vault reward is converted**, in the same
  sentence as the owner's own conversions - "and catalyze your Hide of
  Pestilence (302) into the tier chest and the vault's Scavenger's Spaulders
  (308) into the tier shoulder" - so the count of charges on screen no longer
  understates what QE Live told the owner to do. That half is said even with no
  bags read: the vault snapshot alone is enough to name it.

### M5-1 (WKE-550) - Equip Now, drawn as items

- **Every row is the item, not a sentence about it.** A row now shows the
  item's own icon with a quality-coloured border, its item level in the icon's
  corner, its name in quality colour and a grey line under it saying where it
  is - the shape Blizzard's Adventure Guide and every popular bag addon use. A
  swap reads left to right: what you are wearing, an arrow, what QE Live wants,
  the Equip button. An already-best row is one icon with a green tick. Hovering
  the icon or the name opens the item's own tooltip, with the shopping compare.
- **The five counts are chips above the list**, each in its status colour, so
  "5 to swap" is legible before a single row is read.
- **A verdict badge on the right, in QE Live's own colours** - gold when his
  number says better, burnt orange when it says worse, grey when he did not
  rank it. It is always text: a bar's length would be arithmetic on his
  numbers, and Lootpath never computes a healer value.
- **The list scrolls** rather than the window growing.
- **An item the client has not loaded yet is still a readable row.** It keeps
  its own icon (static data answers before the load) and says
  "Retrieving item information", exactly as Blizzard's journal does; Lootpath
  asks the client for the item once and fills the row in when it answers, and
  leaves the row alone if it never does. A row handed another item stops
  waiting for the first, so a late answer can never land on the wrong line.
- **One loader, shared.** The request-and-re-read the Vault tab got in M3-12 is
  now `ns.ItemData` and every tab uses it. The Vault tab behaves exactly as it
  did.

### M5-2 (WKE-551) - the chrome: a portrait ring, a status strip, and the paste box behind a dialog

- **The window wears Blizzard's portrait frame, and the ring says whose answer
  this is.** `PortraitFrameTemplate` in place of `BasicFrameTemplateWithInset`,
  with the player's current specialization icon in the ring - the class icon
  when the client names no spec, and an empty ring rather than a guess when it
  names neither. It is redrawn when the player changes specialization. Escape
  still closes the window, and it still drags and clamps.
- **The tabs moved to the frame's bottom edge**, where the Encounter Journal
  puts them, so the body above them is one uninterrupted rectangle.
- **One status strip in place of the paste box.** `QE Live - Restoration Druid
  - Dungeon Top Gear - companion, written 4 minute(s) ago - vault pick: as
  offered`, on one line under the title. The age turns amber when the export
  is older than the client's own weekly reset, which is what a dead companion
  watcher looks like. The sentence the window used to keep under the status
  line, the other stored export and the reason an age is amber are all in the
  strip's tooltip.
- **The paste box is now an Import dialog** behind the strip's `Import...`
  button, with the editbox, Import, Clear and the import status line inside it.
  Nothing about importing changed: the same routing, the same parsers, the same
  refusals shown verbatim. Options is still one click from the strip.
- **A launcher.** An AddOn Compartment entry (`## AddonCompartmentFunc` in the
  `.toc`, no library) and a minimap button drawn natively: left-click toggles
  the window, right-click opens the options page, and dragging moves it around
  the ring with the angle saved in the profile.
- **Two settings**: a window scale slider (0.7 to 1.3, applied with
  `SetScale` on the window alone) and a "compact rows" checkbox, which is
  stored for the item line M5-1 draws and changes nothing on screen yet.
- The Import dialog closes with the window, so a paste box never floats on
  with nothing behind it.
- The window size is unchanged at 620 x 640: WKE-549 has not answered the
  size question.

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
