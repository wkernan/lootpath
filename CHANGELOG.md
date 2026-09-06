# Changelog

## Unreleased

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
