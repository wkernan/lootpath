# Lootpath - the central brain

This document is the single source of truth for what Lootpath is, how it works, every decision made and why, what is verified and what is not, and where the work stands. **Every session that changes a decision, verifies a fact, or closes an issue updates this file in the same PR.** If this file and the code disagree, say so in the PR and fix whichever is wrong; never leave them disagreeing.

Last updated: 2026-09-05 (M0-1 skeleton, WKE-514: layout, CI gates, captures `env`/`inventory`/`vault`; several ladder items settled from public sources and the Healper spike's client capture, see §9).

---

## 1. What Lootpath is

**One sentence:** Lootpath puts QE Live's gear answers inside World of Warcraft, next to the loot they are about.

**The three promises, on one in-game frame:**
1. **Equip Now** - what you should be wearing right now, from what you own, with one-click equip.
2. **Upgrade Map** - for each gear slot, which dungeon boss or raid boss drops a candidate, and (where QE Live has ranked it) how much better it is.
3. **Vault** - which Great Vault option to take this week.

**The product rule, above every other rule:** **Lootpath never computes a healer value.** Every healing number on screen is QE Live's, transported unchanged from its export. Lootpath's own work is the scanner (gear, bags, bank, vault), the loot map (Encounter Journal walk), matching, and display. No network, no backend, no behaviour in combat, no estimate of its own to fill a gap.

**Who it is for, in order:** the owner (MVP = the owner alone, on one character); then healers generally; DPS via Raidbots/MythicSim output is a later extension of the same import interface, not an MVP goal.

**Why this exists:** the audience's whole gearing loop today is alt-tab: `/simc` in game, paste into QE Live in a browser, read the answer there, alt-tab back and try to remember it at the vault or when a drop appears. QE Live is right about the math; everything around the math happens where the game cannot see it. Mr. Mythical solves this in-game for DPS with a SimulationCraft-trained model; SimulationCraft cannot model healing, so no healer equivalent could be built that way. Lootpath is "Mr. Mythical for healers" with QE Live as the brain.

---

## 2. Owner context (facts, not preferences)

- Owner: wkernan. Senior engineer (TS/Node, Python, AWS); **no WoW healing expertise** - every mechanics claim traces to a source, never intuition.
- Repo: https://github.com/wkernan/lootpath - public, **MIT**, created 2026-09-05. Local clone `c:\Code\lootpath`, owner's alone (not a shared tree).
- Linear project **Lootpath** (team Wkernan): https://linear.app/wkernan/project/lootpath-fb6687ed82e3/overview. Labels: `ai-ready` (an outside Claude Code session can build it) and `human-required` (the owner must act, usually in game).
- Game client: Retail, Midnight expansion, patch 12.1, at `C:\World of Warcraft\_retail_`. Test character **hotornot**, Restoration Druid. Interface number **120100**, build **69587** (12.1.0), **measured**: `GetBuildInfo()` captured on the live client 2026-09-01 by the Healper spike (`HealperSpike.lua` SavedVariables, `environment.build` = `"12.1.0", "69587", "Aug 27 2026", 120100`), and `C:\World of Warcraft\.build.info` reads `12.1.0.69587` (read 2026-09-05). The earlier "build 69465" was the 08-24 build. M0-2's `capture env` re-measures; the `.toc` follows the client.
- The owner runs every in-game step. Agents cannot. Each such step is a human-required issue with exact commands.
- SimulationCraft addon: **not installed as of 2026-09-05** - the client's AddOns folder held 73 addons and no `Simulationcraft` folder (the addon's folder and `.toc` name in simulationcraft/simc-addon). The earlier "owner confirmed installed" note was wrong (premise refuted 2026-09-05). Owner installs it from CurseForge before M2-1b (WKE-519); M0-2 step 3 checks. It is the exporter Lootpath relies on.
- Sister project: Healper (`c:\Code\Healper`), a log-analysis web app, parked 2026-09-02 and kept alive cheaply. **Not a dependency.** What transferred: the addon spike's secret-value serializer pattern, `sync.ps1`, `FINDINGS.md`/`README.md` client facts, and the working discipline (evidence rules, prove-red guards, premise checks - 48 of 71 Healper issues had a wrong premise, including ones written the same day by the same author).
- Commit attribution: commits end `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; PR bodies end with the Claude Code attribution line.

---

## 3. The ecosystem, stated precisely (premise-checked 2026-09-03/05)

| Tool | What it does | Relation to Lootpath |
|---|---|---|
| **QE Live** (questionablyepic.com/live, Voulk) | Healer gearing brain: Top Gear (best set from what you own + vault), Upgrade Finder (values drops you do not own, by boss), Vault, trinket analysis. Web only. | **The brain.** Lootpath is the in-game reader of its output. |
| **Mr. Mythical** (addon) | In-game equip/loot/vault/crest recommendations from a neural-net DPS model. `/mrdps`. | The shape Lootpath copies, for healers. DPS only; cannot do healers. Open-source reference for journal walking and loadout ranking (respect its licence; mirror patterns, copy nothing). |
| **Pawn** | Same-slot item comparison in tooltips from imported stat weights (QE Live and WoWAnalyzer export weights for it). | Already owns tooltip comparison. **Lootpath does not do tooltips.** |
| **GearingWise, GearWish** | Tooltip upgrade advisor; loot wishlist. | More reasons tooltips are not a gap. |
| **Healer Stat Weights** | Computed healer weights live in-game; 234K downloads; appears unmaintained. | Proof the in-game healer audience exists. |
| **Raidbots / MythicSim** | DPS sims; Droptimizer output consumed by addons. | The DPS import path later; not MVP. |
| **WowCoach.gg** | AI log coaching, $5.99-12.99/mo, no visible traction. | The rejected product shape. AI is never the pitch. |

**The gap, exactly:** not "stat comparison for healers" (Pawn), not "loot source lists" (the Adventure Guide), but **QE Live's verdicts shown in-game next to the loot map and the vault.** That combination exists nowhere.

**Economics:** side project that pays for itself at most. Free addon, tip jar later. Comparable free-plus-Patreon tools: QE Live, Mr. Mythical, wowaudit (patron count NOT public; the "3,400" figure from an early draft was unverified and is withdrawn).

---

## 4. QE Live: everything we know (all read from its public source, branch `dev`)

- Repo: github.com/Voulk/QuestionablyEpic. **No licence file** = all rights reserved. Actively pushed (2026-09-02). We read it for understanding and schemas; we copy no code and no data tables.
- **Top Gear exports.** `src/General/Modules/TopGear/Report/TopGearJSONExport.ts`, present since at least 2026-05-20 (last touched by "handle duplicates"). Schema string `"qe-live-droptimizer"`, `version: 1`. Payload:
  ```
  { schema, version, exportedAt (ISO), player: {name, realm, region, spec, gameType: "Retail"|"Classic"},
    contentType, reportId,
    topSet: { score (hardScore), stats (setStats), items: [Item] },
    differentials: [ { scorePercent, hpsDifference, items: [Item], gems: [int] } ] }
  Item = { slot, id, level, bonusIDs: [int], gems: [int], enchant: string, tertiary: string, setId: int, isVault: bool, isExclusive: bool, source: {} }
  ```
  Sign conventions, from the source comment: `scoreDifference` is a percent where **positive means the alternative is worse**; `rawDifference` is HPS where **negative means the alternative is worse**. Pin both in tests as named constants.
  `topSet.items` are the chosen items of the best set (falls back to the full list if none flagged). `differentials` = alternative sets: only the items that differ from the top set, with the delta.
  It is a **file download** (`qe-droptimizer-<name>-<id>.json`), not a clipboard copy. **Nothing on GitHub consumes this schema** (code search 2026-09-04).
- **Upgrade Finder does NOT export.** `UpgradeFinderReport.js` has no export/copy/download path; `UpgradeItemData.js` is marked "Currently unimplemented". The in-memory result (`runUpgradeFinder`, `UpgradeFinderEngine.js` ~line 105) is `UpgradeFinderResult { itemSet, differentials, contentType, id }` where each item possibility carries `source[0].instanceId` / `encounterId` (used by `getSetItemLevel`) and differentials carry score deltas. An export mirroring Top Gear's is roughly 50 lines - in his repo.
- **Vault reaches QE Live via the SimulationCraft addon**: `simc-addon/core.lua` ~line 1294 reads `C_WeeklyRewards:HasAvailableRewards()`, `GetActivities()`, `GetItemHyperlink(rewardInfo.itemDBID)` and exports the options. QE Live marks them `vaultItem`/`isVault`.
- **Relationship history:** Voulk reviewed Healper's advice layer harshly and correctly (2026-09-01, Discord). Lootpath must read as the opposite: computes nothing, defers to his engine, drives users to his site. Outreach is the owner's (QE-2), after there is a working addon to show, leading with "your export has no consumer; here is one, plus two buttons" - a copy-to-clipboard control and the Upgrade Finder export, offered as a PR from the owner's fork. Never mention Healper unless he does.

---

## 5. Data flow (the round-trip)

1. In game: SimulationCraft addon `/simc` (includes equipped, bags, and vault when available) - copy.
2. Browser: questionablyepic.com/live - import, run **Top Gear** (M+ by default), **Download JSON**.
3. In game: `/lootpath`, paste the JSON text into the editbox. `QEImport` validates (schema, version 1, Retail) and stores the verdict in SavedVariables with its `exportedAt`.
4. `Inventory` scans; `Journal` walks (cached); `Vault` reads; `Match` joins verdict to inventory and journal by item key.
5. Three panels render. Equip Now can equip out of combat.

Constraints that shape it: addons have **no network** and **cannot read files** (hence paste); SavedVariables flush **only on `/reload` or logout**; secret values apply in combat/encounters/M+/PvP (spike-verified they lift out of combat; the guard stays on every read regardless); the bank is readable only while the bank frame is open.

---

## 6. Architecture

One shipped package `Lootpath/` (what the packager zips) plus `spec/` (tests) and `tools/` (dev scripts). One namespace table `ns` shared via `.toc` load order; modules register on `ns`; no globals except the slash handler.

| Module | Responsibility | Interface (contract) | Testable headless? |
|---|---|---|---|
| `Core.lua` (shipped M0-1) | lifecycle, events, `/lootpath` dispatcher (`capture <name>`, `capture`, `capture wipe`, `status`, `help`), AceDB SavedVariables, `ns.Safe(value)` secret guard, `ns.CopyRaw(table)` guarded deep copy (secret, cycle, depth 10, 50k nodes, UI objects), `ns.Probe(fn, ...)` pcall-to-positional-table, `ns.ItemKey(id, bonusIDs)`, `ns.RegisterCapture/RunCapture` | `ItemKey` = `"<itemID>:<sorted bonusIDs joined by :>"`, bare `"<itemID>"` with none, `nil` for garbage; ONE definition used by QEImport and Match. `RunCapture` refuses in combat (`{ok=false, reason="combat"}`), before the DB exists, and for unknown names | yes (`spec/core_spec.lua`) |
| `Captures.lua` (shipped M0-1) | `/lootpath capture env`, `inventory`, `vault` raw dumps | snapshot `{ name, capturedAt, capturedAtLocal, build, addonVersion, sawSecret, durationMs, data }` appended to `db.global.captures[name]`. Reads only; every client function called is named in the file (bank predicates are an allow-list) - never a namespace walk, because `C_Bank` also moves items and money | yes (`spec/captures_spec.lua`, over the stub) |
| `Modules/Inventory.lua` | equipped + bags + bank -> records | `{ itemID, link, itemLevel, bonusIDs (sorted), slot, location = equipped/bag/bank, bag, slotIndex, name, quality }`; `bankAvailable` flag; refuses in combat `{ok=false, reason="combat"}` | yes, over captured raw returns |
| `Modules/Journal.lua` | `JournalAdapter` (every EJ call, raw, secret-guarded) + `Journal` (pure aggregator) | `{ [itemID] = { {instanceID, instanceName, encounterID, encounterName, difficultyID, itemLevel, slot, isRaid} } }`; cached in AceDB keyed `(build, seasonID, specID, difficultyID)`. **`itemLevel` is not a field of `EncounterJournalItemInfo`** (Blizzard docs, 2026-09-05): it comes from `C_Item.GetDetailedItemLevelInfo(link)` on the loot row's `link`, as the SimC addon does for vault links | aggregator yes; adapter only via captures (wowless lists every EJ function but its loot functions return nothing) |
| `Modules/Vault.lua` | `C_WeeklyRewards` adapter | week's options: link, item key, activity type | yes, over captures |
| `Modules/QEImport.lua` | parse pasted JSON -> verdict | `{ exportedAt, spec, contentType, topSet = {score, items[itemKey]}, alternatives = [{scorePercent, hpsDifference, items}], vault = {items[itemKey]} }`; refuses non-JSON, wrong schema, `version ~= 1` (names both), missing topSet, non-Retail; warns on character-name mismatch | yes, fully |
| `Modules/Match.lua` | join verdict to inventory/journal | per slot `{ slot, equipped, best, verdictItem, status = equipped_is_best / swap / best_not_owned / no_verdict }`; exact key first, itemID+ilvl fallback **logged, never silent** | yes |
| `UI/MainFrame.lua` + `EquipPanel` / `UpgradeMapPanel` / `VaultPanel` | native frames (no AceGUI); paste editbox `SetMaxLetters(0)`; Settings API options | Equip via `C_Item.EquipItemByName(itemInfo, dstSlot)` (Blizzard docs; the global `EquipItemByName` sits in Ketho's deprecated file - settled 2026-09-05); buttons disabled in combat with tooltip | render tests over fixtures |

**SavedVariables (AceDB):** `db.char.qeImport` (last verdict + exportedAt), `db.global.journalCache[key]`, `db.profile.settings` (content type M+/raid). Captures write raw returns under a `captures` table pulled by `tools/sync.ps1 -Pull`.

**Libraries (all licence-checked, recorded in `Lootpath/Libs/LICENSES.md`):** LibStub (public domain), CallbackHandler-1.0 and AceDB-3.0 (Ace3 BSD-style, clause quoted in LICENSES.md: embedding permitted, "redistribution of a stand alone version is strictly prohibited"), rxi/json.lua 0.1.2 (MIT; vendored verbatim plus a six-line footer that sets `ns.json`, because the WoW loader discards a chunk's return value). Ace3 arrives as packager externals from the wowace SVN trunks in CI and from the WoWUIDev/Ace3 GitHub mirror locally (`tools/fetch-libs.ps1`); both directories are gitignored. Nothing else without a licence line.

**Test harness (M0-1):** `spec/stubs/wow.lua` installs a fake client into `_G` (shapes from Blizzard's docs, build tuple from the spike capture; placeholders, never wiki) and `spec/helpers/addon.lua` loads the `.toc` file list in order with `(addonName, ns)` varargs; a fake `LibStub("AceDB-3.0")` deep-copies the defaults. Fixtures under `spec/fixtures/` win over the stub whenever they disagree.

---

## 7. Decisions log (dated; do not reopen without a new entry here)

- **2026-09-04 - Addon over coach-workbench.** Bigger audience (every healer gears), Raidbots-shaped willingness to pay, and the only gap nobody fills. Workbench had better Healper reuse and a smaller market. Reuse does not drive bets.
- **2026-09-04 - Name: Lootpath.** Zero GitHub repos, no CurseForge hits (2026-09-04). CurseForge/Wago slugs to be claimed the day a public release is decided.
- **2026-09-05 - Licence: MIT.** Open source from day one; every dependency licence-checked.
- **2026-09-05 - Option A for the Upgrade Map.** Values-free for MVP: every spec-appropriate drop per slot by item level, QE deltas only where the Top Gear export covers the exact item (vault, owned). In parallel, prepare an Upgrade Finder export as a PR on the owner's fork (QE-1); owner offers it (QE-2); userscript scraper (QE-3) only if he declines - owner's call, recommendation is to leave the map values-free rather than scrape. Rejected: computing values ourselves (violates the product rule).
- **2026-09-05 - No own `/simc` exporter for MVP.** The SimulationCraft addon (Unlicense) already exports gear, bags and vault and is what QE Live expects. README tells the user to use it.
- **2026-09-05 - Tooltips descoped.** Pawn, GearingWise and GearWish already annotate tooltips; a fourth is not a gap. The dashboard and the loot map are the product.
- **2026-09-05 - Ace3: AceDB only.** UI is native frames + templates; options through the modern `Settings` API (`InterfaceOptions_AddCategory` removed in 10.0). No AceGUI.
- **2026-09-05 - rxi/json.lua, strict `version: 1` pin.** Any other version refused with a message naming both versions. No guessing at a moved schema.
- **2026-09-05 - Item identity = itemID + sorted bonus IDs.** Two copies of an item at different upgrade levels are different items to QE Live; an itemID-only match is never accepted silently.
- **2026-09-05 - Test strategy.** busted over pure modules with a hand-written WoW stub (`spec/stubs/wow.lua`) and **committed capture transcripts** from the owner's client (`/lootpath capture <name>` -> SavedVariables -> `sync.ps1 -Pull` -> `spec/fixtures/`). wowless (MIT, active) evaluated and rejected for now: no Encounter Journal stubs. Every guard proven red before it ships.
- **2026-09-05 - CI gates are real failures**: luacheck (LuaRocks, Lua 5.1, explicit WoW globals list), StyLua `--check`, LuaLS `--check` with Ketho's annotations (MIT), busted, packager zip on every PR. Branch protection requires all of them; agents merge their own PRs only when green; never bypass, never disable a test to get green.
- **2026-09-05 - Packager: BigWigsMods/packager@v2** (v2.5.1, 2025-12-02): zip artifact on PRs, GitHub release on `v*` tags. No CurseForge/Wago upload for the MVP.
- **2026-09-05 - Values-free note wording is pinned**: "Values shown are QE Live's, for items it has ranked. Other drops are listed by item level only."
- **2026-09-05 - Nothing runs in combat**; every client read passes `issecretvalue`/`issecrettable`; no network; no backend.
- **2026-09-05 - Captures `inventory` and `vault` ship in M0-1** (moved from M1-1 and M3-3) so M0-2's single game session yields three transcripts (env, inventory with bank open and closed, vault before and after opening the window). The journal capture stays in M3-1 because it needs the async walk. Captures only call functions named in `Captures.lua`; iterating a namespace and calling what it finds is forbidden (`C_Bank` moves items).
- **2026-09-05 - Local gates.** StyLua 2.5.2 and lua-language-server 3.18.2 via winget; luacheck and busted in Docker (`tools/docker/Dockerfile`, Alpine Lua 5.1 + LuaRocks) because Chocolatey needs an elevated shell the dev machine does not have. `tools/check.ps1` runs all four; CI is the authority.
- **2026-09-05 - Packager invocation** `-t Lootpath -m .pkgmeta -r .release`: `.pkgmeta` lives at the repo root, its externals are relative to `Lootpath/`, and only `Lootpath/` is zipped (`spec/`, `tools/`, `docs/` are outside the topdir).
- **2026-09-05 - LuaLS gate decides on the JSON report**, not the exit code: `lua-language-server --check` exits 0 either way (measured 2026-09-05), so `tools/luals-check.sh` fails on any diagnostic at Warning or above in `check.json`.

---

## 8. Toolchain (versions and licences, checked 2026-09-04/05)

| Tool | Version / state | Licence | Use |
|---|---|---|---|
| BigWigsMods/packager | v2.5.1 (2025-12-02), repo active 2026-09-02 | (repo) | build + release |
| luacheck | via LuaRocks, Lua 5.1 (CI: leafo/gh-actions-lua v13.0.0 + gh-actions-luarocks v6.1.0) | MIT | lint (real failure; `.luacheckrc` lists every WoW global explicitly, no `allow_defined_top`) |
| StyLua | 2.5.2 (CI: JohnnyMorganz/stylua-action v5.0.0; local: winget) | MPL-2.0 | format check |
| lua-language-server (LuaLS) + Ketho/vscode-wow-api annotations | LuaLS 3.18.2; Ketho repo pushed 2026-09-02, **but its generated Blizzard docs are at 12.0.5 (build 67451), regenerated 2026-05-13 - one patch behind the 12.1.0 client.** Blizzard's live docs in Gethe/wow-ui-source `live` (12.1.0 build 69587, 2026-09-01) are the fresher source for hand checks | MIT | type check; the gate fails on the JSON report (see decisions) |
| busted | latest via LuaRocks | MIT | unit tests |
| wowless | active 2026-09-04 | MIT | evaluated; set aside (lists all 57 EJ functions, loot functions return nothing) |
| TradeSkillMaster/wowlua-ls | active | GPL-3.0 | NOT used (dev-only GPL is fine, but Ketho's covers the need) |
| Ace3 (LibStub, CallbackHandler, AceDB) | active 2026-09-03; wowace trunks (CI) = WoWUIDev/Ace3 master (local) | BSD-style | SavedVariables |
| rxi/json.lua | 0.1.2; repo pushed 2023-11-28 (last code commit 2020-06-18) | MIT | JSON parse |
| GitHub Actions | actions/checkout v7.0.1, actions/upload-artifact v7.0.1; Dependabot weekly | - | CI plumbing |
| SimulationCraft addon | pushed 2026-08-21 | Unlicense | the exporter (user-installed, not vendored) |

---

## 9. Verification ladder

**Verified (source read or measured):** QE Live export schema and sign conventions; Upgrade Finder has no export; SimC addon exports the vault; secret values lift out of combat and SavedVariables flush on reload/logout (Healper spike, in-client); toolchain versions/licences above.

**Verified 2026-09-05 from public sources (WKE-514 session; each still gets re-measured by its capture, but none is a guess any more):**
- **Interface 120100, build 69587**: `GetBuildInfo()` in the Healper spike's SavedVariables (2026-09-01) and `.build.info`. See §2.
- **Where the game APIs live.** Of the six named APIs, five are in Blizzard's exported docs (`C_EncounterJournal.GetLootInfoByIndex(index, encounterIndex?)`, `C_EncounterJournal.SetPreviewMythicPlusLevel(level)`, `C_WeeklyRewards.GetActivities(type?)`, `C_Item.GetItemStats(itemLink)`, `C_Container.GetContainerItemInfo(containerIndex, slotIndex)`). **`EJ_SetLootFilter` and the other `EJ_*` globals are not in Blizzard's generated docs**; Ketho carries them in `Annotations/Core/Data/Wiki.lua`. They are real: Blizzard's own `Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua` (Gethe/wow-ui-source, `live`, 3731 lines) calls `EJ_SetLootFilter` (2 sites), `EJ_GetNumLoot` (2), `EJ_SelectInstance` (1), `EJ_SetDifficulty` (5), `EJ_SelectTier` (1), `EJ_GetNumTiers` (1), `EJ_GetInstanceByIndex` (8), `C_EncounterJournal.GetLootInfoByIndex` (4), registers `EJ_LOOT_DATA_RECIEVED` (that spelling; payload `itemID` per Ketho `Event.lua`) and gates its re-read on `EJ_IsLootListOutOfDate()`. **It never calls `SetPreviewMythicPlusLevel`** (0 sites), so that function's effect on loot is unobserved until M3-2.
- **`EJ_GetInstanceForGameMap` (named in WKE-522) does not exist** in Blizzard's docs, Ketho, or wowless. The real function is `C_EncounterJournal.GetInstanceForGameMap(mapID) -> journalInstanceID?`, whose doc comment says it takes a game mapID, "not a uiMapID". `C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)` returns `name, id, timeLimit, texture, backgroundTexture, mapID`. Candidate path: `GetMapTable()` -> `GetMapUIInfo().mapID` -> `GetInstanceForGameMap`. Whether those two `mapID`s are the same kind is for the M3-2 capture.
- **`EncounterJournalItemInfo` fields**: itemID, encounterID?, name?, itemQuality?, filterType?, icon?, slot?, armorType?, link?, handError?, weaponTypeError?, displayAsPerPlayerLoot?, displayAsVeryRare?, displayAsExtremelyRare?, displaySeasonID?. **No item level.**
- **Equip function**: `C_Item.EquipItemByName(itemInfo, dstSlot?)` in Blizzard docs; global `EquipItemByName` is in Ketho's `Blizzard_Deprecated/Deprecated_ItemScript.lua`.
- **`ContainerItemInfo` fields** (Blizzard docs): iconFileID, stackCount, isLocked, quality?, isReadable, hasLoot, hyperlink, isFiltered, hasNoValue, itemID, isBound, itemName. `C_Item.GetDetailedItemLevelInfo(itemInfo) -> actualItemLevel, previewLevel, sparseItemLevel`.
- **Bonus-ID layout in `item:` strings** (simulationcraft/simc-addon `core.lua`, pushed 2026-08-21, the parser QE Live's input comes through): fields split on `:`; `OFFSET_ITEM_ID = 2`, `OFFSET_ENCHANT_ID = 3`, `OFFSET_CONTEXT = 12`, `OFFSET_BONUS_ID = 13` is the **count**, the IDs follow it, then a variable list of modifier type/value pairs, then gem bonuses. M1-1's parser is written against captured links and cross-checked with this.
- **Vault**: `WeeklyRewardActivityInfo { type, index, threshold, progress, id, activityTierID, level, claimID?, raidString?, rewards[] }`; `WeeklyRewardActivityRewardInfo { type (Enum.CachedRewardType), id, quantity, itemDBID? }` - **`itemDBID` is nil for currency rewards**, and the SimC source notes `GetItemHyperlink` "may return nothing even for a valid itemDBID". SimC's vault export is `core.lua` lines 1294-1305 exactly. `C_DateAndTime.GetSecondsUntilWeeklyReset()` exists for M3-3's stale-verdict note. `C_Secrets.HasSecretRestrictions()` exists and `capture env` records it.
- **QE Live re-read 2026-09-05**: schema `"qe-live-droptimizer"`, `version: 1`, gameType `"Classic"|"Retail"`; the sign comment verbatim: "scoreDifference: number (% - positive means alt is worse), rawDifference: number (HPS - negative means alt is worse)"; download filename `qe-droptimizer-{safeName}-{resultId}.json`; no clipboard code; the exporter file has exactly one commit on `dev` (2026-05-20 "handle duplicates"); GitHub code search finds 0 uses of the schema string outside his repo; `UpgradeFinderReport.js` has no export/copy/download, `UpgradeItemData.js` line 3 reads `// == Currently unimplemented. ==`, `UpgradeFinderResult` is `{ id, itemSet, differentials, itemsCompared, contentType }`. Repo pushed 2026-09-02, default branch `dev`, no licence.
- **Ace3 licence** clause quoted in `Lootpath/Libs/LICENSES.md`.

**Pending in-client confirmation (each is a capture the owner runs; build against the transcript, never a guess):**
| Unknown | Resolved by |
|---|---|
| Re-measure build/Interface (expected 69587 / 120100); which addons load; `HasSecretRestrictions()` out of combat | M0-2 (`capture env`) |
| `ContainerItemInfo` field **values** on real items; which `Enum.BagIndex` values answer `GetContainerNumSlots` in 12.1 (character bank is tab-based); which of `GetDetailedItemLevelInfo` / `GetItemInfo[4]` / `GetCurrentItemLevel` to use; the bank predicates' answers open vs closed; our links' exact layout | M0-2 + M1-2 (`capture inventory`, bank open and closed) |
| Whether QE's Download JSON control is present and emits `version: 1` today; vault items present in Top Gear | M2-1b (owner's real export) |
| Equip from the bank; editbox large-paste behaviour | M2-3 (in game) |
| `GetMapUIInfo().mapID` -> `GetInstanceForGameMap` works; what `SetPreviewMythicPlusLevel` does to loot rows; `EJ_LOOT_DATA_RECIEVED` timing; walk duration | M3-1 + M3-2 (`capture journal`) |
| When `GetActivities` populates rewards (before/after opening the vault window); whether `GetItemHyperlink` returns nil or nothing | M0-2 + M3-2 (`capture vault`, both states) |

---

## 10. Issue map (WKE-514..529, Linear project Lootpath)

**Addon lane (sequential; blockers set on the board):**
514 M0-1 skeleton + CI + CLAUDE.md + captures `env`, `inventory`, `vault` (ai; **PR #2, 2026-09-05**) -> **515 M0-2** branch protection, one game session running all three captures (env; inventory with the bank open and again closed; vault before and after opening the window), SimC addon install (you) -> 516 M1-1 Inventory normaliser against the transcript (ai; the capture half already shipped in 514, so one PR unless the transcript demands a second capture) -> **517 M1-2** only if 516 needs another capture (you) -> 518 M2-1 QEImport (ai; can start when 514 merges) + **519 M2-1b** real QE export fixture (you) -> 520 M2-2 Match + editbox + Equip Now (ai) -> **521 M2-3** verify in game (you) -> 522 M3-1 Journal + `capture journal` (ai; two PRs) -> **523 M3-2** journal + vault captures (you) -> 524 M3-3 Upgrade Map + Vault panels (ai) -> **525 M3-4** verify + one week of real use (you) -> 526 M4-1 v0.1.0 README/changelog/tag (ai).

**QE Live lane (parallel from day one):** 527 QE-1 export + copy button on the owner's fork, PR text drafted, **never opened upstream** (ai) -> **528 QE-2** outreach and fallback decision (you) -> 529 QE-3 userscript, **gated on 528 saying so** (ai).

**Dispatchable now:** 514 and 527 (different repos). After 514 merges: 516 and 518 in parallel.

**MVP done means:** 525's week of real use is commented, and 526 is tagged. "You, alone, using it."

---

## 11. Risks and open questions

- Ketho's generated annotations are one patch behind the client (12.0.5 vs 12.1.0). An API added or renamed in 12.1 fails the LuaLS gate as undefined; handle each case with a scoped `---@diagnostic` or `---@cast` plus a note here, never by loosening the gate. Blizzard's live docs on Gethe/wow-ui-source are the tie-breaker.
- The M+ pool -> journal instance mapping is the step most likely to differ from any doc; the candidate path is in §9 and M3-2 proves it. Blizzard's own journal never calls `SetPreviewMythicPlusLevel`, so its effect on loot rows is unobserved.
- Ace3 comes from two sources (wowace SVN in CI, GitHub mirror locally); drift between them would show up as a CI-only failure.
- QE Live's schema is his to change; a moved schema fails loudly (version pin) rather than wrongly.
- The owner's character name and realm are in the committed QE fixture; owner said that is fine for a public repo of their own character, and may ask for scrubbing.
- Voulk may decline the PR; the map stays values-free (recommended) or QE-3 is built (owner's call).
- Paste path is download-then-paste until a copy button exists on QE Live.
- SimC addon export format changes are outside our control; QE Live absorbs them, we only depend on its JSON.

---

## 12. Working rules (also in CLAUDE.md, shipped in 514)

Branch per issue (`lp-<n>-<slug>`), PR to `main`, never commit to `main` directly, merge your own PR only when every CI check is green. Read the whole Linear issue including its "Working in this repo" section. Verify the issue's premise against the code before building; a wrong premise is reported in the PR and the right thing is built instead - scaling down is fine, widening is not. Never write a measured figure you did not read from a tool. Every guard proven red. Every client read secret-guarded; nothing in combat; no network; **Lootpath never computes a healer value.** In-game steps are the owner's: write the capture, hand it over as human-required, build against the transcript. Report in every PR: what shipped; premise check; measured figures with the tool; guards and how each went red; CI results; left undone, deliberately. **And update this file** with any decision, verified fact, or closed issue.
