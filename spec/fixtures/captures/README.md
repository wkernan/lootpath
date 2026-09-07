# Committed capture transcripts from the owner client (tools/sync.ps1 -Pull).
# Raw SavedVariables, never normalised. Each is named in the PR that commits it.

## Still to capture

- `vault` on a week with rewards available - WKE-523, Tuesday 2026-09-08 after
  the reset: `/lootpath capture vault` before and after opening the window, to
  settle the shape of `rewards[]` and `itemDBID`. Progress was already non-zero
  on 2026-09-06 (see below), so the reset will generate rewards.
  **M3-3 depends on this one.** `Lootpath/Modules/Vault.lua` reads a generated
  reward through Blizzard's exported `WeeklyRewardActivityRewardInfo`
  (`{ type, id, quantity, itemDBID? }`) because no committed snapshot has ever
  carried one; `spec/vault_spec.lua` and `spec/vaultpanel_spec.lua` drive that
  shape through the stub and say so in their headers. When this capture lands,
  re-run those two against the real shape and turn the file header's
  "documented, not measured" note into a measured one.

## Committed

- Lootpath-20260905-133449.lua - WKE-515 (PR #3). Client 12.1.0 build 69587, hotornot on Arthas in Guardian spec (104). Snapshots: inventory x2 (bank open, then closed), vault x2 (before, then after opening the window; no progress that week), env x1. No secrets seen.
- Lootpath-20260906-161213.lua - WKE-523 first visit (this PR). Same client
  build, hotornot on Arthas in **Restoration spec (105)**. Carries the five
  09-05 snapshots again (SavedVariables accumulate) plus three new ones:
  journal x1 (16:11:01; 30 targets = 8 season dungeons x Heroic/Mythic/M+ at
  preview level 10 + 3 raids x Heroic/Mythic; 613 loot rows, 351
  `EJ_LOOT_DATA_RECIEVED` events, 0 waits, 0 timeouts, walk 434 ms; every map
  resolved by `C_EncounterJournal.GetInstanceForGameMap`, the global
  `EJ_GetInstanceForMap` answered 0 for all eight; 244 of the 613 rows carried a
  `link`, the rest only `itemID`/`encounterID`), vault x2 (16:11:30 before and
  16:11:56 after opening the window; progress non-zero, `rewards` empty in
  both). No secrets seen.
- Lootpath-20260906-200908.lua - WKE-523 second pull (this PR). Same client
  build, Restoration spec (105); the earlier snapshots repeat, plus two new
  `journal` snapshots from the two-read walk (M3-1 part 2): 19:59:34 with a
  cold item cache (`pendingRowsFirstRead` 349, `pendingRowsFinalRead` 0,
  `rowsFilledByReread` 349, 365 `EJ_LOOT_DATA_RECIEVED` events, walk 869 ms)
  and 20:04:53 after `/reload` with the cache warm (0 pending on the first
  read, 0 events, walk 549 ms). `C_Item.GetDetailedItemLevelInfo` answered
  **1** for 108 rows in the cold walk and 86 in the warm one (e.g. Hex Lord's
  Gaze, itemID 275938) - the client's own figure, not a parse artefact. No new
  vault snapshot: rewards are not generated until Tuesday. No secrets seen.
