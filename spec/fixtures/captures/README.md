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
- Lootpath-20260909-085940.lua - the owner's first `/lootpath refresh` after a
  client restart, 2026-09-09 08:59:19 (this PR). Taken on the pre-546 build a
  moment before the reload loaded 546, so its `currencies` snapshot (index 4)
  has the list half only - crests 358 / 0 / 2 / 39 / 20, no `byID`. Its vault
  snapshot (index 13) is the measured case behind WKE-547: four of five gear
  rewards with `name = nil`, `itemLevel = nil` and an empty bracketed name in
  the link (`|h[]|h`), keys intact; progress Dungeons 1/1 (level 8), 1/4, 1/8,
  Concession 5/3; `hasAvailableRewards` true, `canClaimRewards` false. Every
  earlier snapshot repeats. No secrets.
- Lootpath-20260915-162015.lua - the owner's `upgrade` capture (WKE-574, M3-17)
  at a crest vendor with the upgrade window open, 2026-09-15 16:20 local on
  `main` at `65b0b08`: 128 items walked in 20 s, 20 answered `CanUpgradeItem`,
  each with the documented `ItemUpgradeItemInfo` shape and per-level
  `currencyCostsToUpgrade` (20 of one currency a step, the watermark row at
  cost 0). The evidence WKE-588 (M3-17b) is built from. Also the R-7a bound
  in effect: four snapshots per kind, all `flush`.
- Lootpath-20260914-171359.lua - R-2a's `glow` capture (WKE-571), the owner's
  bags 2026-09-14 17:13 local on `main` at `34ea350`: for every bag slot the
  link, the key, whether the map has it and whether the mark answers; the
  helmet 271528 is `inMap`, `isForward`, `glow = true` and drew nothing on
  screen. The evidence WKE-575 (R-2b) is built from.
- Lootpath-20260914-113012.lua - R-0's in-client run (WKE-561), the owner's
  spike session 2026-09-14 11:27:49 to 11:30 local on `main` at `78938ad`, with
  no `/lootpath refresh` in between (so its `env` snapshot is the 2026-09-10
  one and carries no keystone or bag-frame line yet). Its `spike` snapshot 1 is
  the measurement: 2,566 item-tooltip post-calls in 133,146 ms (1,156 per
  minute), per call min 0.009 / avg 0.015 / max 0.082 ms, 39 ms in total; the
  hyperlink present on every call, never nil, never a secret value, 0 errors,
  0 combat returns; by frame `ShoppingTooltip1` 1,490, `ShoppingTooltip2` 706,
  `GameTooltip` 250, `PawnPrivateTooltip1` 120. Every earlier snapshot
  repeats. No secrets.
- Lootpath-20260915-142722-vault.lua - **an extract, not a raw pull**, and the
  only one in this folder: the owner's 2026-09-15 14:27 local SavedVariables
  are 12.5 MB, which is more than this repo should carry, so M3-16b (WKE-583)
  commits the vault evidence out of it and names the whole file here. The full
  pull is `Lootpath-20260915-142722.lua` on the owner's own box, beside the
  13:58 one of the same day (11.5 MB); both predate R-7a's four-per-kind bound
  (WKE-582), which is why they grew that large. What is kept is every `vault`
  snapshot and every login-ask `env` snapshot taken after the 2026-09-15 weekly
  reset - 13 and 9 of them - written back in Blizzard's own SavedVariables
  format with the companion's parser (`tools/companion/lib/lua-savedvariables.js`)
  and re-serialised; no value is altered, only whole snapshots left out.
  What it shows, and what M3-16b was built from: four `refresh` reads that
  ASKED the client (`interact.attempted`, `updateFired`, 66.7 / 77.1 / 113.2 /
  130.9 ms) and came back with the same 10 activities, every `rewards = {}`,
  0 reward links, `hasGeneratedRewards` false; seven `flush` reads that did not
  ask and carried the same nothing; then 19:27:16Z, a `command` capture taken
  with the Great Vault window OPEN (`frameShown` true) - 11 activities, 5
  carrying rewards, `hasGeneratedRewards` and `canClaimRewards` true, 9 reward
  links (Preyhunter's Lantern, Enigmatic Dreamwatcher's Leggings, Kyrakka's
  Searing Embers, five Mythic Keystones, a Thalassian Token of Merit) - and
  19:27:22Z, the flush six seconds after the window closed, carrying the same
  11 and 9. The window generated them; the addon's interaction did not.
  No secrets seen.
- empty-equipment-flush.lua - **hand-written, not a pull**, and the only one in
  this folder that is: the write carrying the real thing was four snapshots deep
  and the flushes after it pushed it off the end before it could be pulled. The
  shape is read, not invented - the owner's live SavedVariables, parsed
  2026-09-16 with `tools/companion/lib/lua-savedvariables.js`, carry the flush of
  his 2026-09-15 22:11:52 logout with `equipped 0`, all twenty bag records
  answering `numSlots 0`, and the whole capture 0.58 ms, beside `equipped 15` and
  14.4-29.6 ms for the two reload flushes and the refresh of the next day. The
  `env` read of that same flush still answers `UnitLevel 90` and `UnitClass
  Druid`, carries `trigger = "flush"` and `capturedOn = "flush"`, and names no
  spec at all (`GetSpecializationInfo` answers id 0 and no name at
  `PLAYER_LOGOUT`). Built through `tools/companion/lib/profile.js` it produces
  `0 equipped, 0 in bags, 0 in the bank, 0 vault, 14 lines` - the owner's
  2026-09-15 22:07 terminal, line for line. It is what R-7b (WKE-591) pins the
  companion's refusal and the flush label against. No secrets.
- Lootpath-20260916-140011.lua - **the third real logout, and the first pulled
  under R-7b (WKE-591) - but the flush itself ran the OLD addon.** The owner
  logged out for real at 14:00:11 local, logged in, and ran `sync.ps1 -Pull`.
  The synced files (`main` `6417440`, pushed 13:50:26) hold R-7b, yet the
  14:00:11 `inventory` snapshot is STORED with `equipped 0`, 20 bag records, 0
  items, `durationMs 0.88`, and its `env` carries no `leavingWorld` and no
  `flushRefusals`: the client loads addon files only at load, the owner was
  logged in when the sync landed, and so the logout flushed with the code
  loaded at his earlier login. The three flushes beside it (12:22:28,
  12:22:47, 12:53:39, all reloads) read `equipped 15`. What this pull DOES
  prove is the companion half on the new code: the watcher restarted at
  18:51Z on `6417440` woke on this write at 19:00:14Z, built `0 equipped, 0
  in bags, 0 in the bank, 0 vault, 14 lines`, and refused before the fork
  with exit 8 and `state = "skipped"` (`Data/companion.log`,
  `Data/CompanionStatus.lua`), the verdict untouched. The addon half - the
  refusal and `leavingWorld` - waits on the NEXT real logout, which will be
  the first taken by the new code. No secrets.
- Lootpath-20260916-142559.lua - **the fourth real logout, and the first on
  the R-7b build (WKE-591): the measurement, and it closes the question.** The
  owner logged out for real at 14:25:58 local on `main` `6417440` (loaded at
  his login after the 14:00 one), logged in, and ran `sync.ps1 -Pull`. The
  flush's `env` snapshot carries `leavingWorld = { equipped = 0, elapsedMs =
  0.069 }` - at `PLAYER_LEAVING_WORLD` the client already answers
  `GetInventoryItemLink` with nothing for every slot - and `flushRefusals`
  naming `inventory` with R-7b's reason; no `inventory` snapshot was stored
  for that flush, so the four stored ones are the three reload reads of
  12:22-12:53 (`equipped 15`) and the 14:00:11 empty one the pre-R-7b addon
  stored. So a real logout reads no gear at either event, and the flush on a
  logout can keep `env`, `vault` and `currencies` current but never the gear;
  R-7c (WKE-594) retires the promise in the words. The watcher on this write
  (19:26:02Z) again refused the 14:00:11 read with exit 8. No secrets.
- Lootpath-20260916-152428.lua - **the second vendor walk, on the M3-17b build
  (WKE-588), and the flush that healed the loop.** The owner took three
  `upgrade` captures at a crest vendor with the window open (15:21:48,
  15:21:58, 15:24:11 local, `main` `72b377f`), reloaded and pulled. Each walk:
  138 candidates, 181-201 ms, `walkMs` 139, `eventsSeen` 158, 19 answered
  `CanUpgradeItem` true and all 19 came back with `GetItemUpgradeItemInfo`
  and per-step costs - against 128 candidates and 20,059 ms on 2026-09-15,
  which is the 2 s-per-item wait M3-17b removed, measured gone. The
  `Item can no longer be upgraded` text the owner saw is Blizzard's own
  `ITEM_UPGRADE_NO_MORE_UPGRADES` on the upgrade frame, shown for each maxed
  item as the walk passes it through the window; not an error. **The 295
  Enigmatic Dreamwatcher's Leggings (item 271527, bag copy) answered nothing
  at all**: `CanUpgradeItem` false, `GetItemUpgradeItemInfo` nil,
  `GetItemUpgradeCurrentLevel` nil, `GetItemHyperlink` nil after
  `SetItemUpgradeFromLocation`, watermark 321 - the client will not put it in
  the window, while every other 295 leg piece in the same bags (Miststalker's
  Cuisses, Preyhunter's Sleek Trousers, two copies of item 272245) loads and
  answers `Champion` 2/6, `maxItemLevel` 308, the watermark row free and
  300000 copper a step. WHY the client refuses that one item is not in the
  file. The flush of the reload (15:24:28) stored `equipped 15`, the first good
  inventory read since the empty 14:00:11 one, and the companion built a full
  profile from it (`profile unchanged since 19:43:56Z`). Crest counts at the
  time: Adventurer 329, Veteran 35, Champion 2, Hero 8, Myth 40. No secrets.
