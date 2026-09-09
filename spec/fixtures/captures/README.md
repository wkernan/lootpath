# Committed capture transcripts from the owner client (tools/sync.ps1 -Pull).
# Raw SavedVariables, never normalised. Each is named in the PR that commits it.

## Still to capture

Nothing scheduled. Every capture the MVP needed is committed; `/lootpath refresh`
now takes `env`, `inventory` and `vault` itself (C-3), so new snapshots arrive
with every loop rather than by request.

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
  **1** for 87 rows in the cold walk's final read (108 if its two reads are
  added) and 86 in the warm one (e.g. Hex Lord's Gaze, itemID 275938) - the
  client's own figure, not a parse artefact; almost all are non-gear the
  aggregator drops, 6 and 5 reached a panel slot (WKE-530). No new
  vault snapshot: rewards are not generated until Tuesday. No secrets seen.
- Lootpath-20260908-124527.lua - WKE-523 second visit (this PR). Restoration
  spec (105). Pulled after the 2026-09-08 weekly reset with the Great Vault
  window open and nothing claimed. Nine `vault` snapshots accumulate in it; the
  ninth (12:45:26, taken by `/lootpath refresh`) is the first with generated
  rewards: 11 activities, `hasAvailableRewards` and `canClaimRewards` true,
  `secondsUntilWeeklyReset` 594873, every `progress` 0 (the new week), and
  `rewards[]` populated on 207, 208, 213, 214, 217 and 229 - each gear reward
  paired with a Mythic Keystone (180653), `itemDBID` a hex **string** such as
  `"0x4000000E5E0736EE"`, every link resolved by `GetItemHyperlink` and probed
  (`rewardLinks`: link, `GetDetailedItemLevelInfo`, `GetItemInfo`,
  `GetItemInfoInstant`). Gear offered: Preyhunter's Lantern 275547 (Offhand
  305), Lightgrasp Worldroot 251935 (2H Weapon 305), Scavenger's Spaulders
  251146 (Shoulder 308), Graft of the Domanaar 251234 (Neck 308). No secrets.
- Lootpath-20260908-230426.lua - the `currencies` capture (M3-9, WKE-544's
  human-required step, taken by `/lootpath refresh` at 23:02:37 and 23:04:26 on
  2026-09-08; the second is the one the tests read). The client's currency list
  is 18 entries: 10 headers (Midnight, Crests, Delves, Features, Professions,
  Season 2, Zones, Dungeon and Raid, Miscellaneous, Legacy) and 8 currencies -
  Voidlight Marl 3316 (37506), Tidal Spark Dust 3509 (5), Nebulous Voidcore
  3418 (0), and under "Crests" the five Mistcrests: Adventurer 3442 (356),
  Veteran 3443 (0), Champion 3444 (2), Hero 3445 (21), Myth 3446 (20). **No
  entry is a Catalyst charge.** Every earlier snapshot repeats. No secrets.
