# Lootpath - the central brain

This document is the single source of truth for what Lootpath is, how it works, every decision made and why, what is verified and what is not, and where the work stands. **Every session that changes a decision, verifies a fact, or closes an issue updates this file in the same PR.** If this file and the code disagree, say so in the PR and fix whichever is wrong; never leave them disagreeing.

Last updated: 2026-09-05 (project created; nothing built yet).

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
- Game client: Retail, Midnight expansion, patch 12.1, at `C:\World of Warcraft\_retail_`. Test character **hotornot**, Restoration Druid. Interface number believed **120100** (from the Healper spike, build 69465); **M0-2 confirms it from `GetBuildInfo()`** and the `.toc` follows the client, not this note.
- The owner runs every in-game step. Agents cannot. Each such step is a human-required issue with exact commands.
- SimulationCraft addon: owner confirmed installed (2026-09-05). It is the exporter Lootpath relies on.
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
| `Core.lua` | lifecycle, events, `/lootpath` dispatcher (`capture <name>` subcommands), AceDB SavedVariables, `ns.Safe()` secret guard, `ns.ItemKey(id, bonusIDs)` | `ItemKey` = itemID + sorted bonusIDs joined; ONE definition used by QEImport and Match | yes |
| `Modules/Inventory.lua` | equipped + bags + bank -> records | `{ itemID, link, itemLevel, bonusIDs (sorted), slot, location = equipped/bag/bank, bag, slotIndex, name, quality }`; `bankAvailable` flag; refuses in combat `{ok=false, reason="combat"}` | yes, over captured raw returns |
| `Modules/Journal.lua` | `JournalAdapter` (every EJ call, raw, secret-guarded) + `Journal` (pure aggregator) | `{ [itemID] = { {instanceID, instanceName, encounterID, encounterName, difficultyID, itemLevel, slot, isRaid} } }`; cached in AceDB keyed `(build, seasonID, specID, difficultyID)` | aggregator yes; adapter only via captures (**wowless has no EJ stubs**) |
| `Modules/Vault.lua` | `C_WeeklyRewards` adapter | week's options: link, item key, activity type | yes, over captures |
| `Modules/QEImport.lua` | parse pasted JSON -> verdict | `{ exportedAt, spec, contentType, topSet = {score, items[itemKey]}, alternatives = [{scorePercent, hpsDifference, items}], vault = {items[itemKey]} }`; refuses non-JSON, wrong schema, `version ~= 1` (names both), missing topSet, non-Retail; warns on character-name mismatch | yes, fully |
| `Modules/Match.lua` | join verdict to inventory/journal | per slot `{ slot, equipped, best, verdictItem, status = equipped_is_best / swap / best_not_owned / no_verdict }`; exact key first, itemID+ilvl fallback **logged, never silent** | yes |
| `UI/MainFrame.lua` + `EquipPanel` / `UpgradeMapPanel` / `VaultPanel` | native frames (no AceGUI); paste editbox `SetMaxLetters(0)`; Settings API options | Equip via the 12.x equip function (name confirmed by annotations); buttons disabled in combat with tooltip | render tests over fixtures |

**SavedVariables (AceDB):** `db.char.qeImport` (last verdict + exportedAt), `db.global.journalCache[key]`, `db.profile.settings` (content type M+/raid). Captures write raw returns under a `captures` table pulled by `tools/sync.ps1 -Pull`.

**Libraries (all licence-checked, recorded in `Libs/LICENSES.md`):** LibStub (public domain), CallbackHandler-1.0 and AceDB-3.0 (Ace3 BSD-style; embedding permitted, standalone redistribution prohibited), rxi/json.lua (MIT). Nothing else without a licence line.

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

---

## 8. Toolchain (versions and licences, checked 2026-09-04/05)

| Tool | Version / state | Licence | Use |
|---|---|---|---|
| BigWigsMods/packager | v2.5.1 (2025-12-02), repo active 2026-09-02 | (repo) | build + release |
| luacheck | via LuaRocks, Lua 5.1 | MIT | lint (real failure) |
| StyLua | latest | MPL-2.0 | format check |
| lua-language-server (LuaLS) + Ketho/vscode-wow-api annotations | annotations pushed 2026-09-02 | MIT | type check against Blizzard's exported API docs |
| busted | latest | MIT | unit tests |
| wowless | active 2026-09-04 | MIT | evaluated; rejected for now (no EJ stubs) |
| TradeSkillMaster/wowlua-ls | active | GPL-3.0 | NOT used (dev-only GPL is fine, but Ketho's covers the need) |
| Ace3 (LibStub, CallbackHandler, AceDB) | active 2026-09-03 | BSD-style | SavedVariables |
| rxi/json.lua | 2023-11-28 | MIT | JSON parse |
| SimulationCraft addon | pushed 2026-08-21 | Unlicense | the exporter (user-installed, not vendored) |

---

## 9. Verification ladder

**Verified (source read or measured):** QE Live export schema and sign conventions; Upgrade Finder has no export; SimC addon exports the vault; all six named game APIs exist in Blizzard's exported docs (`C_EncounterJournal.GetLootInfoByIndex`, `SetPreviewMythicPlusLevel`, `C_WeeklyRewards.GetActivities`, `EJ_SetLootFilter`, `C_Item.GetItemStats`, `C_Container.GetContainerItemInfo`); secret values lift out of combat and SavedVariables flush on reload/logout (Healper spike, in-client); toolchain versions/licences above.

**Pending in-client confirmation (each is a capture the owner runs; build against the transcript, never a guess):**
| Unknown | Resolved by |
|---|---|
| Live Interface number (120100?) and build | M0-2 (`capture env`) |
| `C_Container.GetContainerItemInfo` table fields; item level source; bonus-ID position/order in `item:` links | M1-2 (`capture inventory`, bank open and closed) |
| Whether QE's Download JSON control is present and emits `version: 1` today; vault items present in Top Gear | M2-1b (owner's real export) |
| Which equip function exists in 12.x; equip from bank; editbox large-paste behaviour | M2-2 (annotations) + M2-3 (in game) |
| Path from M+ map IDs to journal instances; `EJ_LOOT_DATA_RECIEVED` timing; walk duration | M3-1 + M3-2 (`capture journal`) |
| When `GetActivities` populates rewards (before/after opening the vault window) | M3-2 (`capture vault`, both states) |

---

## 10. Issue map (WKE-514..529, Linear project Lootpath)

**Addon lane (sequential; blockers set on the board):**
514 M0-1 skeleton + CI + CLAUDE.md + `capture env` (ai) -> **515 M0-2** branch protection, first capture, Interface number, SimC addon check (you) -> 516 M1-1 Inventory + `capture inventory` (ai; two PRs, capture first) -> **517 M1-2** bank capture (you) -> 518 M2-1 QEImport (ai; can start when 514 merges) + **519 M2-1b** real QE export fixture (you) -> 520 M2-2 Match + editbox + Equip Now (ai) -> **521 M2-3** verify in game (you) -> 522 M3-1 Journal + `capture journal` (ai; two PRs) -> **523 M3-2** journal + vault captures (you) -> 524 M3-3 Upgrade Map + Vault panels (ai) -> **525 M3-4** verify + one week of real use (you) -> 526 M4-1 v0.1.0 README/changelog/tag (ai).

**QE Live lane (parallel from day one):** 527 QE-1 export + copy button on the owner's fork, PR text drafted, **never opened upstream** (ai) -> **528 QE-2** outreach and fallback decision (you) -> 529 QE-3 userscript, **gated on 528 saying so** (ai).

**Dispatchable now:** 514 and 527 (different repos). After 514 merges: 516 and 518 in parallel.

**MVP done means:** 525's week of real use is commented, and 526 is tagged. "You, alone, using it."

---

## 11. Risks and open questions

- The `.toc` Interface number is a belief until M0-2 measures it.
- The M+ pool -> journal instance mapping is the step most likely to differ from any doc; M3-1 finds the path in the annotations and M3-2 proves it.
- QE Live's schema is his to change; a moved schema fails loudly (version pin) rather than wrongly.
- The owner's character name and realm are in the committed QE fixture; owner said that is fine for a public repo of their own character, and may ask for scrubbing.
- Voulk may decline the PR; the map stays values-free (recommended) or QE-3 is built (owner's call).
- Paste path is download-then-paste until a copy button exists on QE Live.
- SimC addon export format changes are outside our control; QE Live absorbs them, we only depend on its JSON.

---

## 12. Working rules (also in CLAUDE.md once 514 lands)

Branch per issue (`lp-<n>-<slug>`), PR to `main`, never commit to `main` directly, merge your own PR only when every CI check is green. Read the whole Linear issue including its "Working in this repo" section. Verify the issue's premise against the code before building; a wrong premise is reported in the PR and the right thing is built instead - scaling down is fine, widening is not. Never write a measured figure you did not read from a tool. Every guard proven red. Every client read secret-guarded; nothing in combat; no network; **Lootpath never computes a healer value.** In-game steps are the owner's: write the capture, hand it over as human-required, build against the transcript. Report in every PR: what shipped; premise check; measured figures with the tool; guards and how each went red; CI results; left undone, deliberately. **And update this file** with any decision, verified fact, or closed issue.
