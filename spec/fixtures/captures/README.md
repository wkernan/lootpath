# Committed capture transcripts from the owner client (tools/sync.ps1 -Pull).
# Raw SavedVariables, never normalised. Each is named in the PR that commits it.

## Still to capture

- `journal` - WKE-523 (M3-2). Run in **Restoration spec (105)**, out of
  combat, with no Adventure Guide open: `/lootpath capture journal`, wait for
  the "stored" line, then `/reload` and `.\tools\sync.ps1 -Pull`. The walk
  changes the Adventure Guide's tier, instance, difficulty and loot filter and
  puts all but the M+ preview level back.
- `vault` on a week with progress - WKE-523, to settle when `rewards[]` and
  `itemDBID` populate.

## Committed

- Lootpath-20260905-133449.lua - WKE-515 (PR #3). Client 12.1.0 build 69587, hotornot on Arthas in Guardian spec (104). Snapshots: inventory x2 (bank open, then closed), vault x2 (before, then after opening the window; no progress that week), env x1. No secrets seen.
