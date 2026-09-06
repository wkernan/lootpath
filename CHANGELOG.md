# Changelog

## Unreleased

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
