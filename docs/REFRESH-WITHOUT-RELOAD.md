# Refresh without reload: the research memo (2026-09-26, night)

**Status: research, awaiting the owner's word. Nothing here is built.** Five Opus research agents worked the question on the evening of 2026-09-26; this memo is their findings checked against the code, the annotations under `.luals/` and the owner's own install, with every claim graded. Evidence grades: **(i)** Blizzard's documentation or FrameXML under `.luals/` (file and line); **(ii)** a cited web source that was read; **(iii)** an inference; **(iv)** unknown until the owner runs the named in-game step. Every figure below was read from a tool; none is invented.

## The question

The owner, 2026-09-26: "figure out how this addon can work without having to constantly refresh and reload the game each time gear has been dropped. I don't want to have to rely on a QE Live companion refresh."

Today's loop (ARCHITECTURE.md §5): `/lootpath refresh` captures gear, then `ReloadUI()` flushes SavedVariables to disk (reload 1); the companion reads them, drives the fork, writes `Data/QEVerdict.lua`; a second reload loads it (reload 2). Two reloads per refresh, and a refresh after every drop. The 2026-09-07 decision called two reloads "the floor" because SavedVariables reach disk only at reload or logout and addon files load only at load. Both facts are still true. **The floor was a floor for that courier, not for every courier.**

## The answer in one sentence

The loop can go from two reloads per drop to **zero reloads per refresh** by carrying both hops on the clipboard, and from a refresh per drop to **about one refresh per night** by having QE Live rate the likely next states before they happen, so the drop moment is answered from what is already on disk.

Two layers that stand, each on its own, and a third recorded as not worth building. Build order is the owner's; the memo's recommendation is foresight first (it removes the most refreshes and needs no new client behaviour) and the clipboard courier second (it removes both reloads from the refreshes that remain: one Ctrl+C to send the gear, one Ctrl+V to load the rating). The one thing no layer gives is a send with no keystroke at all - the only API that would (`CopyToClipboard`) is protected to Blizzard's code, and the only other zero-keystroke channel is a screenshot pixel block, recorded under the dead ends with its optics.

**Added 2026-09-27, small hours, after the owner asked for the Raider.IO shape - "just updates each evening", no `/reload`, no `/lootpath refresh`, ever:** there is a fourth layer that gives exactly that, with no keystroke at all, and it is the cheapest of the four. See "Layer 2b: capture on change" below. The rating is then always as of the last logout, foresight covers the session in between, and the clipboard courier becomes the optional "I want it tonight" hatch rather than the loop.

---

## Layer 1: foresight. Rate the future before it drops, so the drop moment needs no refresh.

### What is already answered from disk (read in the fork and in `Lootpath/Modules/`)

- **The Upgrade Finder's baseline is the worn set and nothing else.** `runUpgradeFinder` takes `player.getEquippedItems(false)` (`UpgradeFinderEngine.js:111`), scores it with Top Gear (`:121`), and for each candidate drop runs Top Gear over worn plus that one item, exporting `(new - base) / base` (`:361-378`). Bag items are never in that baseline. The candidate is built with no bonus IDs, no tertiary, no socket (`:205-226`); necks and rings get a socket anyway (`Item.ts:85`).
- **So "is this drop better than what I wear" is answered before it drops**, for every drop a document carries at the exact item ID and level, and R-2c already shows that row on the bag hover and on chat links (`Roads.lua:1084-1160`): `+1.83% rated at 305 · you hold it at 311`, `Beats what you wear - refresh.` Gaps that stand: raid is rated at one difficulty (UX-5g); sockets and tertiaries are not modelled; for a ring or trinket the export does not say WHICH one the drop pushes out (that set exists at `UpgradeFinderEngine.js:365` and is thrown away).
- **Two things go stale, and only two.** (a) The "wear it now" answer: Equip Now reads Top Gear pass 1, which never saw the drop, and a bag item might beat it. (b) Every Upgrade Finder row once the drop is WORN: the baseline set no longer exists. Rows in the drop's slot now compare against an item that is off; rows in other slots were computed against a set that changed (the sign probably holds through diminishing returns, `TopGearEngine.ts:1320-1323` - an inference, and Lootpath may not act on it). Top Gear documents went stale when the drop entered the bags, not when it was equipped. Vault documents were rated over a pool without it.
- **The Upgrade Finder export carries `equipped`, the exact worn set it compared against, with full bonus IDs (`UpgradeFinderJSONExport.ts:49`), identical across all six live documents - and `UFImport.Parse` drops it (`UFImport.lua:363-386`).** Keeping it gives an exact per-slot test of whether a rating's baseline is what the player wears, with no arithmetic.

### A hazard found in the code, to fix whatever else is decided

Once a drop X is worn, the old piece O sits in the bags. `Match.Build` finds O by key, marks the row SWAP, and hands it the unclaimed worn record - X - as `equipped` (`Match.lua:224-295`, `313-335`). Equip Now then reads `Equip O · replaces X` (`EquipPanel.lua:583-585`), and **Equip all would undo the upgrade.** Nothing checks whether the piece being replaced is one the rating ever saw. Not reproduced in game; the owner's step is in the list below. The guard: no Equip button on a swap row whose replaced piece is outside every pass's `considered` list.

A second finding: Drift's baseline lives for the session only (`Drift.lua:152-155`) and is re-taken at every load, so a plain `/reload` mid-evening clears the "gear changed" nudge. The per-item `not rated · new since the last refresh` survives because it is checked against the documents' pools. The baseline should come from the rating's own record (the Upgrade Finder's `equipped` and Top Gear's `considered`).

### The design: two questions per candidate, asked by QE Live, at the off-peak refresh

- **Candidates:** Upgrade Finder `drop` rows with `upgradePercent > 0`, keyed by item ID and level. Choosing which questions to ask by QE Live's own sign is the same principle as C-12's gates; it computes no value.
- **Count on the owner's live file (2026-09-26, Druid; counted with node over `Data/QEVerdict.lua`, 67 dungeon drop rows):**

  | Key level | +2 | +4 | +6 | +8 | +10 |
  |---|---|---|---|---|---|
  | Item level | 295 | 298 | 305 | 308 | 311 |
  | Upgrades | 7 | 9 | 14 | 15 | 18 |

  63 distinct item-and-level pairs, 18 distinct items; at +10 the median is +0.29%, the maximum +1.25%, one of 18 at 1% or more, over 8 slots. Raid (Mythic) drop upgrades: 24. Early-season fixtures (2026-09-07/08) show 17-41 per level; the count shrinks as gear improves.
- **Import A (tier 1):** the current profile plus `# ,id=X,ilevel=L` in the bags - a `#` line is a bag item (`SimCImportEngine.ts:490`), `ilevel=` overrides the level (`:539`, `:545`), any line after line 8 with `id=` is parsed (`:289-301`), nothing checks ownership, the filters are level over 50, a known ID, armour or weapon the class can wear (`:685-696`), and the slot comes from the item database, not the line (`:544`). One Top Gear pass (pass 1 is the answer, per C-11) with X forced into the pool ahead of other bag items. Result: a Top Gear document "with X", its `considered` naming X. **Proven headlessly on 2026-09-26 against the fork's own `runSimC`** (a temporary jest test over the committed `spec/fixtures/simc/hotornot-from-savedvariables.simc`, deleted afterwards, the fork's tree clean before and after): `# ,id=251935,ilevel=311` (a staff), `251159` (a chest) and `252258` (a ring) each import as one item at level 311 with empty bonus IDs, `isEquipped=false`, the ring with `socket=1` (`Item.ts:85`); an uncommented `chest=,id=251159,ilevel=311` imports as worn and active at 311 with the old chest gone; a nonexistent ID and an item level of 40 are dropped. **The nuance:** like every bag item it arrives `active=false` (`:712`) and enters Top Gear only once selected - which is what the companion's pass logic already does to bag cards (C-11's `chooseSelection`, `fork.js:776`) - under the cap of thirty selected (`TopGear.tsx:177`, `:739`). Its stats are the item's base stats at that level: no tertiary, crafted stat or embellishment, exactly as the Upgrade Finder rated it.
- **Import B (tier 2, optional):** worn items = Top Gear's top set from A (so the right ring comes out and the 15-or-16-worn check at `UpgradeFinderFront.js:403-415` passes by construction), everything else to the bags; the Upgrade Finder at the night's key level. Its `equipped` equals that set. Skipped when X is not in A's top set.
- **Never add an extra uncommented (worn) line**: worn items feed `activeStats` (`Player.js:491-499`), which scales the flat-healing terms (`TopGearEngine.ts:1053, 1333`); the swap must swap, not add.
- **File shape (new top-level key; old builds ignore it, because `Companion.Validate` ignores unknown top-level keys, `Companion.lua:570-622`, and a document with no scenario would otherwise be filed as `asOffered`):**
  ```
  ns.companionVerdict.foresight = {
    basedOn = "<the base run's writtenAt>",
    candidates = {
      { itemID, level, slot, dropLoc, keyLevel,
        topGear = { contentType, scenario = "asOffered", pass = 1, considered = {...}, json = "<verbatim>" },
        upgradeFinder = { { contentType, keyLevel, json = "<verbatim>" } } },
    } }
  ```
- **Addon:** a pure `ns.Foresight` module indexes candidates by item ID and level from the metadata alone and decodes a document's JSON only when a drop matches; the documents never enter SavedVariables. `UFImport.Parse` keeps `equipped`; `UFImport.WornMismatch(verdict, records)` lists the slots whose worn item differs from the rating's baseline. `Match` gains `matchedBy = "foreseen"`; the row reads `rated before it dropped`.
- **Selection:** on `BAG_UPDATE_DELAYED`, exactly one new gear piece since the rating (Drift already counts this) whose item ID and exact level match a candidate: Equip Now, the tooltip sentence and the glow read that candidate's Top Gear document. Two or more new pieces: today's behaviour, per item (pairs are not pre-rated: 153 pairs at +10). On `PLAYER_EQUIPMENT_CHANGED`, when what is worn equals the candidate's top set (X by item ID and level, the rest by exact key), the Upgrade Map reads the candidate's tier-2 documents; otherwise the staleness rules below. A second drop after that gets its figure from the tier-2 document through R-2c's lookup; the chain degrades to today's behaviour, never to a guess.
- **Cost, built from stage times measured on the owner's machine (`companion.log`, 2026-09-26 21:51-21:53Z; estimates, not a measured foresight run):**

  | Stage | Measured |
  |---|---|
  | Profile import | 724-818 ms |
  | Pool probe | 242-463 ms |
  | Content select, Dungeon | 653-803 ms |
  | Top Gear document (2 passes) | 9.2-13.1 s, about 5-7 s per pass |
  | Upgrade Finder, one key level | 1.57-2.65 s |
  | Whole run, 22 documents | 111.9 s; six runs that day 91.9-135.2 s |
  | Document size | Top Gear 34-37 K characters; Upgrade Finder 97-119 K characters |

  Tier 1: about 7-9 s per candidate, 18 candidates about 2-2.7 min, +0.65 MB of file. Tier 2: 3-4 s more per candidate, 3-4 min in all, +2.8 MB (a file of about 4 MB; loading it at login is unmeasured; each JSON stays under the 4 MB per-entry cap, `Companion.lua:80`). All 63 pairs or all five key levels in import B: over 10 MB, not recommended.
- **Never computes:** every figure is QE Live's export carried verbatim; Lootpath chooses which questions to ask (by QE Live's sign) and which document to show (by identity). The item and level in the synthetic line are read off QE Live's own Upgrade Finder row. The one strain: the profile then carries an item the player does not own, which the companion's header has promised never to do (`simc-profile.js:13-15`). The owner's call.

### Staleness rules: what a surface may say about a number rated before the gear changed

**May (transport):** show the number unchanged with its age and the event it predates (`rated before you equipped the Signet`); name its old referent (`+1.2% over the Lynx shoulders you took off`); order rows of one document; say `not rated since you equipped X`; choose a pre-computed document by identity. **May not (computing):** subtract rows, scale a row to another level, say "still an upgrade" or "no longer" without a document that says so, drop a stale row silently, or offer an Equip whose replaced piece the rating never saw.

| State | Equip Now | Upgrade Map | Tooltip / glow | Vault tab | Strip |
|---|---|---|---|---|---|
| Drop in bags, rated ahead | the candidate's set: `Wear X - replaces O`, `rated before it dropped` | unchanged (nothing worn changed) | the candidate's sentence | pick unchanged, plus `doesn't count your new X` | no badge; `rated before it dropped · X` |
| Drop in bags, not rated ahead | as today; no row for X | as today | R-2c's row plus `refresh` | as today | today's nudge |
| X worn, matches the candidate | all already best | tier-2 documents, `as if you wore it` | from those documents | `rated before you equipped X` | quiet |
| X worn, nothing matches | swap rows that would replace an unseen piece lose the button: `rated before you equipped X · refresh` | slot S: fold behind `not rated since you equipped X`, or name the referent; other slots: same figures, eyebrow `rated before you equipped X` | line 4: `Rated 3h ago · before you equipped X`; no glow in slot S | headline provenance | nudge |

Events, all in Ketho's `Core/Data/Event.lua`: `BAG_UPDATE_DELAYED` :143, `PLAYER_EQUIPMENT_CHANGED` :1134, `ENCOUNTER_LOOT_RECEIVED` :549 (no player field; whose loot it names is unconfirmed), `SHOW_LOOT_TOAST` :1337, `LOOT_ITEM_ROLL_WON` :925, `CHALLENGE_MODE_COMPLETED` :245, `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`/`_HIDE` :1144/:1143 with `Enum.PlayerInteractionType.WeeklyRewards = 49` (`Enum.lua:7067`), `PLAYER_REGEN_ENABLED` :1167. The bag scan stays the source of truth; the loot events give earlier notice.

**A vault stand-in the addon already holds:** a dungeon vault reward is a dungeon item on the bonus track, which the Upgrade Finder rates as its `bonus` row (`UpgradeFinderEngine.js:274-280`); `VaultPanel.lua` never reads Upgrade Finder rows. An exact item-and-level row could stand in until the refresh, labelled `against what you wear`.

**Idle moments where the addon can prepare and ask, never reload (M3-16a):** leaving the instance after a key with new gear not rated ahead (`Rate your new gear`); the vault window closing (type 49; capture on hide, `Rate your vault options`); the end of the night (`Rate before you log out` - one refresh, the companion runs while the player is away, the next login loads it). With layer 2 those asks cost no reload at all.

### The owner's evening (5 keys, 2 upgrade drops, one vault open; a refresh today is 2 reloads and a 92-135 s wait)

| | Today | Foresight alone | Foresight + clipboard courier |
|---|---|---|---|
| Login | 2 reloads (a logout reads no gear, R-7c) | 0 (the end-of-night run is already loaded) | 0 |
| Vault (weekly) | 2 | 2 | 0 reloads, one paste |
| Upgrade 1 | 2 | 0 | 0 |
| Upgrade 2 | 2 | 0-2 (its figure is there; the pair's imperative is not) | 0, or one paste |
| Non-upgrade drops | the nudge fires for any new key (`Drift.lua:352-375`), up to 2 each | 0 if the nudge stays quiet when the exact-level row says `not better` (owner's call) | 0 |
| End of night | 0 | 1 refresh (2 reloads) | 1 refresh, 0 reloads |
| **Reloads** | **8 on a vault night, 6 otherwise, plus nudges; 6-9 min waiting** | **3-5 / 1-3** | **0** |

---

## Layer 2: the clipboard courier. Zero reloads for the refreshes that remain.

Both hops of the round trip can ride the Windows clipboard. Nothing else outside the client removes either hop (see the dead ends), and this is the pattern every SimulationCraft user already performs: the SimC addon shows its profile in an EditBox for Ctrl+C; QE Live and Raidbots take a paste.

### Outbound: the refresh puts the gear on the clipboard instead of on disk

- **Mechanism.** `/lootpath refresh`, or the nudge's click, runs the four captures exactly as now and then, instead of `ReloadUI()`, shows the companion's export in an EditBox, focused and highlighted, and the player presses Ctrl+C - the SimulationCraft addon's own flow. The export is the capture records the companion's `simc-profile.js` already reads, plus identity, `capturedAt`, a header line (`LOOTPATH-EXPORT v1 <name>-<realm> <epoch>`) and a checksum. `OnKeyDown` sees the Ctrl+C and closes the box with `sent` (SimC's `core.lua:919-941` watches Ctrl/Meta+C the same way and hides after 0.1 s "just in case"). One keystroke.
  - **Why not `CopyToClipboard(text)`, which would make the command itself the send:** the API is **protected, not hardware-event gated** - an addon cannot call it from anywhere, a click or a slash command included. `HasRestrictions = true` in its documentation (`OsDocumentation.lua.annotated.lua:10-13`) **(i)** is a catch-all flag that names no rule (202 functions carry it, from `CreateFrame` to `TargetUnit`; `C_UI.Reload` carries none and still needs a hardware event); the wiki lists it under `#protected - This can only be called from secure code` **(ii)** https://warcraft.wiki.gg/wiki/API_CopyToClipboard; and it was confirmed on the Midnight client on 2026-06-12: `[ADDON_ACTION_FORBIDDEN] AddOn 'BetterWardrobe' tried to call the protected function 'CopyToClipboard()'` from a menu CLICK through Blizzard's own `DressUpModelFrameMixin.lua:54` **(ii)** (BetterWardrobe issue #585). Narcissus lists the error as known and falls back to "an editbox where player can press Ctrl+C"; SimC, WeakAuras, DevTool and CraftersBoard all use the EditBox. So does Lootpath.
  - **(ii)** the SimC addon (`core.lua`, `simulationcraft/simc-addon`, last commit 2026-08-21, `## Interface: 120005, 120007, 120100`): a `UIPanelScrollFrameTemplate` holding a multi-line EditBox (`:906-918`), `SetText` then `HighlightText()` (`:1014-1015`), no size handling, no `CopyToClipboard` anywhere. **(iv) V4** for a 10,000- and 50,000-character copy surviving intact.
- **Companion.** A clipboard listener (Win32 `AddClipboardFormatListener`, or a Node clipboard module; the listener inspects in memory only, logs nothing that lacks the header, and honours `ExcludeClipboardContentFromMonitorProcessing`), the header check, then the pipeline it runs today from SavedVariables - `lua-savedvariables.js` is reused unchanged if the export is emitted as a Lua table literal. C-4's fingerprint, C-15's character gate, C-16's spec read all stand.
- **What it retires from the critical path:** the SavedVariables flush, R-7's logout captures, C-17's rename retry, the `refreshStartedAt` wait line's dependence on a reload. None of it is wrong; it stops being the courier.
- **A related fact from the prior-art pass:** the SimC addon exposes `SimulationcraftAPI.GetSimcProfile` so another addon can obtain the profile string in game **(ii)**. Lootpath could hand the companion a real SimC string when that addon is present; the captures carry the vault, currencies and upgrade facts SimC does not, so the export stays Lootpath's own.

### Inbound: the companion puts the compressed verdict on the clipboard; the player pastes once

- **Measured on the owner's live `Data/QEVerdict.lua` (written 2026-09-26 16:53):** raw 1,163,848 bytes; `gzip -9` 57,111 bytes; gzip then base64 with no line wraps 76,148 characters (gzip -6: 82,956). The brain records a 1,593 KB verdict (§9) and one in-game paste of 16 KB (§9), the largest on record.
- **The client decodes natively.** `C_EncodingUtil.DecodeBase64` (`EncodingUtilDocumentation.lua.annotated.lua:29-43`), `DecompressString` (`:62-76`), `DeserializeJSON` (`:94-106`), with `CompressString`, `EncodeBase64`, `SerializeJSON` and the hex and CBOR pairs beside them **(i)**; `Enum.CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 }` (`Core/Data/Enum.lua:2157-2161`) **(i)**; the decoders are `MayReturnNothing = true`, so nil is handled, and `DecompressString` "will validate any checksums added by the compression method and raise an error if the data appears to be invalid" and has "a hard limit ... currently equal to approximately 100 MB" **(ii)** https://warcraft.wiki.gg/wiki/API_C_EncodingUtil.DecompressString - so the call sits in a `pcall`, and 1.2 MB is far inside the cap. The namespace arrived in 11.1.5 (Ketho's per-patch GlobalAPI snapshots: none in 11.1.0, all ten in 11.1.5, identical in 12.1.0) **(ii)**. Blizzard itself runs the chain DecodeBase64 → DecompressString → DeserializeCBOR in `CooldownViewerSettingsDataStoreSerialization.lua.annotated.lua:232-244` **(i)**. No library to vendor, no licence entry.
- **Mechanism.** The companion gzips the verdict envelope (each QE Live document as an unchanged string, plus `character`, `writtenAt`, `profileCapturedAt`, and the status file's content), base64s it behind a magic prefix (`LOOTPATH-VERDICT:1:`), and writes the clipboard; on the PC it plays a sound or shows a toast, which is the `wrote` line made audible. The addon's existing paste box (`MainFrame.lua:1040-1060`, `SetMaxLetters(0)`, multi-line) gains the prefix in `UI.DetectSchema`/`ImportAny`, imports on `OnTextChanged` with `userInput` true - WeakAuras' pattern, no button **(ii)** - decodes, and runs the existing Companion path: character gate, `DropForeignImports`, `QEImport.Parse` and `UFImport` with every pin and refusal. **Never `loadstring` pasted text**; the envelope is data.
- **The wait.** The addon cannot see the companion's status without a load; the strip's wait line counts as R-6 built it, and the paste is the load. An early paste pastes the addon's own outbound export back (the clipboard still holds it): the prefix says so and the addon answers `still rating`. A paste of a payload it already holds answers `that's the rating you have`. Unlimited per session; a paste is not used up.
- **Failure modes.** A freeze on a 76 KB paste **(iv)** - the 2016 report is of a 270,000-character paste lagging from word wrap, with `SetMaxBytes(1)` plus `OnChar` buffering as semlar's cure **(ii)** https://www.wowinterface.com/forums/showthread.php?t=53494; **WeakAuras today uses none of it** - a plain AceGUI `MultiLineEditBox` that imports on `OnTextChanged` when the trimmed text is over 20 characters (`ImportExport.lua:87-93`, last changed 2024-07-04) **(ii)**, and WeakAuras strings of tens of KB are pasted every day, which is the best evidence there is short of the owner's paste; the companion overwrites what the player had copied (announce it; opt-in); Windows clipboard history keeps the payload, and cloud clipboard sync would upload it (disclose); `OpenClipboard` fails while another process holds it (retry); a focused box eats keystrokes (focus it only when the player opened it).
- **Policy.** Fits CLAUDE.md's "everything external arrives by paste" to the letter. The 2026-09-07 decision rejected "a clipboard helper (still a hop outside the game)"; that hop was an alt-tab, and this has none - the reversal needs its own dated entry, which §7 now carries as a proposal.

### The owner's in-game steps for layer 2 (one session, about fifteen minutes; each `/run` fits the 255-character chat limit)

- **V4, a large copy:** `/run local e=CreateFrame("EditBox",nil,UIParent,"InputBoxTemplate")e:SetSize(300,30)e:SetPoint("CENTER")e:SetMaxLetters(0)e:SetText(("0123456789"):rep(1000))e:SetFocus()e:HighlightText()e:SetScript("OnEscapePressed",e.Hide)` - Ctrl+C, Esc, paste into Notepad: exactly 10,000 characters. Repeat with `rep(5000)`.
- **The paste, compressed:** in PowerShell, `$b=[IO.File]::ReadAllBytes("C:\World of Warcraft\_retail_\Interface\AddOns\Lootpath\Data\QEVerdict.lua"); $m=New-Object IO.MemoryStream; $g=New-Object IO.Compression.GZipStream($m,[IO.Compression.CompressionLevel]::Optimal); $g.Write($b,0,$b.Length); $g.Close(); Set-Clipboard ([Convert]::ToBase64String($m.ToArray()))`. In game, open the Import dialog, click the box, Ctrl+V, do NOT click Import; note any freeze. Then `/run local s=LootpathImportDialog.pasteBox:GetText() local t=debugprofilestop() local z=C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(s),2) print(#s,z and #z,debugprofilestop()-t)` - expected about 76,000-83,000, 1163848, and the milliseconds. Click Clear. (The dialog's global name is the one `MainFrame.lua` gives it; adjust if it differs.)
- **The limit, uncompressed (optional):** `Get-Content -Raw "<same path>" | Set-Clipboard`, paste, `/run print(#LootpathImportDialog.pasteBox:GetText())` - whether 1.16 MB is truncated and how long it freezes.
- **The decoder's speed on its own (optional):** `/run local s=string.rep("abcdefgh",262144) local c=C_EncodingUtil.CompressString(s) local t=debugprofilestop() local d=C_EncodingUtil.DecompressString(c) print(#s,#c,#d,d==s,debugprofilestop()-t)` - 2 MB round-tripped, `true`, and the milliseconds.
- **For the record only:** `/run print(pcall(CopyToClipboard,"lootpath-probe"))` - expected: the "blocked from an action only available to the Blizzard UI" error and the clipboard unchanged. Nothing is built on it either way.

---

## Layer 2b: capture on change. The Raider.IO shape - it updates while you are logged out, and the login is the load. No command, no reload, no keystroke.

The owner, 2026-09-27: "What would it take to make the addon more like raider.io that just updates each evening? ... not needing to do a /reload or a /lootpath refresh. Is there a world at all where we can make this happen?" There is, and most of it is already built.

### Why it works where R-7 could not

R-7 (WKE-579) captured gear AT `PLAYER_LOGOUT` and R-7c (WKE-594) measured that the item layer is torn down before either `PLAYER_LEAVING_WORLD` or `PLAYER_LOGOUT` fires: four real logouts, four empty reads, `equipped 0` in 0.07 ms. So the flush carried whatever the last MANUAL capture held, and the promise "log out and the rating is current next login" was retired. **The read at logout is impossible; a read at the moment the gear CHANGES is not.** `Drift` already listens to `PLAYER_EQUIPMENT_CHANGED` and `BAG_UPDATE_DELAYED` for the nudge (`Drift.lua:352-375`), the Roads cache already rebuilds on those events plus `WEEKLY_REWARDS_UPDATE` and `CURRENCY_DISPLAY_UPDATE` (ROADS-UX buildability), and an `inventory` capture costs 14-30 ms on the owner's real bags (§9). If those same events also refresh the stored `inventory`, `vault` and `currencies` snapshots - out of combat, debounced to one scan per few seconds, a change in combat taken at `PLAYER_REGEN_ENABLED` - then what SavedVariables hold in memory is always the character's current gear, and the logout flush, which already writes `env`, `vault` and `currencies` correctly (R-7b), writes it to disk with no command from the player. The `env` snapshot at the flush still names no spec (C-16a), and the companion's newest-named-spec walk already covers that.

### The evening

1. Log in. The rating the companion wrote after last night's logout is loaded by the login itself (`Companion.Startup`, the character gate, every pin) - the login IS reload 2, and it was always going to happen.
2. Play. Drops are answered by foresight (layer 1). Every equip, loot, vault claim and currency change refreshes the snapshot in memory. Nothing to do.
3. Log out. The client writes SavedVariables. The watcher wakes (as today), the fingerprint says the profile changed (C-4), QE Live runs for the measured 92-135 s plus foresight's estimated 2-4 minutes, the verdict file is written (C-17's rename retry has no reload to collide with), the companion sleeps.
4. Next login loads it. Repeat.

Zero reloads, zero commands, zero keystrokes. The companion runs at logon like Raider.IO's client; that is the one thing no design removes (§"The question").

### The trade, stated plainly

The rating is always **as of the last logout**. Foresight covers the drops of the session in between. What arrives a login late is what foresight does not predict: the vault options once the window generates them (the Upgrade Finder's `bonus` rows stand in until then, labelled `against what you wear`), the craft and Catalyst questions, and a drop nobody foresaw. For any of those wanted TONIGHT, the clipboard courier (layer 2) is the two-keystroke hatch; without it the answer is tomorrow's login - exactly as a Raider.IO score waits for the next login after the run is uploaded. Two healers in one evening: the verdict file is one per machine and the last to log out owns it (C-15), so the second character loads the first's file, is refused by the character gate, and keeps its own last import; carrying several characters' documents in one file is the contract change that fixes it, and it is modest.

### What it costs

- **Addon, one small issue:** capture-on-change. The three captures already exist as functions; the new part is the event wiring, the debounce, the combat deferral, and the rule that a snapshot taken this way is stored like a refresh's (`trigger = "change"`), inside `ns.CAPTURE_HISTORY`'s ring of four so nothing grows. The bank stays readable only while its frame is open, as today. Every read passes `ns.Safe`, as today. **Nothing new is called**: the same `C_Container`, `C_Item`, `C_WeeklyRewards` and `C_CurrencyInfo` reads the captures make now, on events the addon already registers.
- **Companion:** nothing for this layer; foresight (issues 3 and 4) is what makes the login-loaded rating cover the session.
- **Words on screen:** `Drift.Decide` already says the rating's age; the strip says when it was rated and the login line says what loaded. R-7c's guard in `spec/drift_spec.lua` forbids any string that puts "logout" beside "captured" or "current" - and this layer does not need one: the honest sentence is `rated at your last logout, 14 hours ago`, which names the time and no promise. Whether that sentence is allowed past the guard is a wording decision for the issue, not a reason against the layer.
- **What the verification ladder owes:** one real logout on the built branch with a gear change in the session, then `tools\sync.ps1 -Pull`, and the transcript's newest `inventory` snapshot carrying `trigger = "change"` with the changed piece in it and a stamp before the flush. That is the whole proof, and it is the owner's.

### How the four layers now fit

| Layer | Removes | Keystrokes per refresh | Reloads |
|---|---|---|---|
| 1 Foresight | the refresh after every drop | - | - |
| 2 Clipboard courier | both reloads from a refresh you ask for tonight | 2 | 0 |
| 2b Capture on change | the refresh itself: the logout is the send, the login is the load | 0 | 0 |
| 3 Load-on-demand stubs | (not recommended) | | |

With 1 and 2b built, the owner never types `/lootpath refresh` and never reloads; with 2 beside them he can also have tonight's vault rated tonight for two keystrokes.

---

## Layer 3: load-on-demand stubs. A zero-keystroke inbound on paper; its ready flag is gone and its optics are worse than the paste. Not recommended.

- **Mechanism.** Ship N small addons `LootpathVerdict1..N`, each a `.toc` with `## LoadOnDemand: 1`, `## Group: Lootpath` (the AddOn list groups them under Lootpath; the Group value "must EXACTLY match the name of the parent addon", `AddonList.lua.annotated.lua:437-439` **(i)**) and a placeholder `Verdict.lua`. The companion writes the verdict into the next unused stub (temp file + rename), then raises a ready flag. The addon, out of combat, calls `C_AddOns.LoadAddOn("LootpathVerdictK")`, reads the payload through `C_AddOns.GetAddOnLocalTable`, imports it through the Companion path, and wipes the table.
- **What is known.** `LoadAddOn` has no `HasRestrictions` and no `IsProtectedFunction` flag (`AddOnsDocumentation.lua.annotated.lua:347`) **(i)**; it returns `loaded, reason` with the `ADDON_*` reason tokens (`AddOnsDocumentation.lua:132-136`; `UIParent.lua.annotated.lua:250-259`) **(i)**; Blizzard's own AddOn list enables and loads a LoD addon mid-session with no reload (`AddonList.lua.annotated.lua:559-569, 590-597`) **(i)**; DBM loads boss modules at runtime the same way (observed in `DBM-Core/modules/Loading.lua`). A LoD addon's files "get parsed at load time, so can be changed while the game is running but before the addon is loaded, however once loaded they can't be reloaded" - elcius, 2014 **(ii)** https://www.wowinterface.com/forums/printthread.php?t=49982. New addon FOLDERS are enumerated at launch or `/reload` only (TOC_format **(ii)**), and DBM's own string says some `.toc` changes need a restart; **so the stubs must ship and be present at launch.** A stub's SavedVariables would be worse (a write-back clobber at the next flush, and the account path).
- **What is not known (iv).** Whether the 12.1 client reads the stub's Lua from disk at `LoadAddOn` time or indexed it at launch - the one direct statement is twelve years old, and the wiki's `PlaySoundFile` page says of addon files "The file must exist prior to logging in or reloading" **(ii)**, which points at an index taken at login or `/reload`; whether a stub that shipped at a few bytes and is replaced by 1.1 MB loads.
- **The ready flag is gone.** The addon needs a non-consuming "is it written yet" signal before it burns a stub, and the two candidates fail: `PlaySoundFile`'s `willPlay` is a real existence check on retail (wow-voiceover's `Utils.lua:95-107` uses it as one **(ii)**) but only against the file index taken at the last login or reload, so a `ready.ogg` created mid-session is invisible **(ii)**; and `Texture:SetTexture(path)` "always appears to return true, even for invalid FileIDs" **(ii)** https://warcraft.wiki.gg/wiki/API_TextureBase_SetTexture. Without a flag the load is a click on "load it" - the same one action as Ctrl+V, with a stub spent on every early click.
- **One untested variant of the flag, for either layer (iv).** The index problem is about files CREATED mid-session. A silent `Media/ready.ogg` that ships with the addon is indexed at login; if `willPlay` turns false once the companion DELETES it (and the companion restores it at its next start), the addon has a one-bit "the rating is written" signal with no load and no paste - enough for the strip to say `rating ready - press Ctrl+V` instead of counting time, on the clipboard path too. Whether a delete after login flips `willPlay`, or the client answers from a cached handle, is unread. The probe: ship the file, log in, `/run local w,h=PlaySoundFile("Interface\\AddOns\\Lootpath\\Media\\ready.ogg","Master") print(w) if h then StopSound(h) end` (expect true), delete the file on disk, run it again (false decides it), then put the file back.
- **The optics.** In the 2014 thread that is the channel's only evidence, a WoWInterface moderator wrote: "Manipulating game and/or addon data for the sole purpose of bypassing the sandbox feature of the addon system is against the ToU" **(ii)** https://www.wowinterface.com/forums/printthread.php?t=49982 - aimed at a live texture-resize trick, and a companion that rewrites a load-on-demand file mid-session and then loads it is a step closer to that than rewrite-then-`/reload`, which is what Raider.IO and WeakAuras Companion do and what Lootpath does today.
- **Capacity, for the record.** One stub is one delivery per UI session; every flush makes every stub fresh again.
- **Probe kit.** Drafted, UNRUN, under the session scratchpad (`agent-inbound/probe-kit/`). Kept only in case the owner wants the zero-keystroke inbound badly enough to accept a "load it" click and the optics; the paste needs none of it.

---

## Dead ends, recorded so nobody reopens them

- **The Battle.net Profile API.** Character resources are "updated upon character logout" (Blizzard's namespaces guide **(ii)**), so it is staler than a reload; Raidbots: "usually takes a few minutes ... sometimes longer ... from time to time the API will not be updated" **(ii)**. It exposes equipped items well (SimC's `bcp_api.cpp` parses `bonus_list`, `enchantments`, `sockets`, `modified_crafting_stat`) and **no bags, no bank, no Great Vault, no currencies** (the portal's endpoint list **(ii)**; "there is no support on the API for inventory data", API forum **(ii)**). Nothing to build on.
- **The combat log.** With advanced logging on, `COMBATANT_INFO` at `ENCOUNTER_START` carries worn gear as `(ItemID, iLvl, (enchants), (bonus IDs), (gems))` **(ii)**, live to disk - worn only, encounter start only, not triggerable, no bags or vault. No addon-controllable line lands in it.
- **The chat log.** `LoggingChat(true)` exists (`Core/Data/Wiki.lua:7539`) **(i)**; a whisper to self in 255-character chunks might reach `Logs\WoWChatLog.txt`, but `SendChatMessage` is `HasRestrictions` (`ChatInfoDocumentation.lua.annotated.lua:555-558`) **(i)**, the file is buffered (a 2012 thread on its buffer size **(ii)**), whether `print`/`AddMessage`/`CHAT_MSG_ADDON` lines are logged is unread, the payload travels through Blizzard's chat servers (against the spirit of "no network"), and base64 whispered to oneself invites the spam filter. Not worth its V6 test unless everything above fails.
- **A screenshot with an encoded pixel block - the only zero-keystroke outbound there is.** `Screenshot()` carries no restriction flag (`ClientDocumentation.lua.annotated.lua:86-88`) **(i)** and current addons call it from event handlers with no click on the Midnight client - Memento `core/Capture.lua:109-151` off `ACHIEVEMENT_EARNED`, `ENCOUNTER_END`, `PLAYER_LEVEL_UP` (last commit 2026-09-24; its issue #5 of 2026-02-01 is a user complaining it fired on every reload), NexEnhance, MidnightUI, Multishot **(ii)**; `SCREENSHOT_STARTED/SUCCEEDED/FAILED` exist **(i)**; pixel-exact drawing is possible (`PixelUtil.GetPixelToUIUnitFactor` = `768 / physicalHeight`, `SetIgnoreParentScale`, `SetSnapToPixelGrid`, `SetTexelSnappingBias` **(i)**); `screenshotFormat` takes `jpeg` (default), `png` or `tga`, is not a secure CVar (`cvar.ts:8609-8614`), and WindTools and Multishot set it from Lua **(ii)** - the owner's is the lossy default (no line in his `Config.wtf`; `screenshotQuality 10`). Capacity by arithmetic 3-25 KB per block; 2-3 days of addon work and 2 of companion work; a 4K file of 10-25 MB per send. It is zero keystrokes and it works in principle - and it is pixel encoding, the reader half of which is what pixel bots do; CraftPresence's own README says the technique "has not been verified by Blizzard". Kept as a footnote behind the clipboard, which is one keystroke and beyond reproach; if the owner ever wants the command alone to be the send, this is the only way, and it is his call.
- **Live screen reading** (the companion samples the game window: CraftPresence, `AipNooBest/wow-discord-rpc`, `wodim/wow-discord-rich-presence` **(ii)**): windowed mode only, hundreds to low thousands of bytes, and the worst optics of anything here. No.
- **CVars, `macros-cache.txt`, `bindings-cache.wtf`, `AddOns.txt`, `Config.wtf`:** written at logout or reload, or server-synced, or a clobber of the player's own settings **(ii)**. No.
- **The `Logs\*.log` files** (read on the owner's disk): engine messages and load-time dumps only; nothing an addon controls at runtime.
- **`C_VoiceChat.SpeakText` into a custom Windows voice:** the API has no restriction flag **(i)** and a self-written voice would receive the text exactly - as a DLL loaded inside the game's process. Third-party code in the process is the clearest anti-cheat line there is. Never.
- **A partial SavedVariables flush:** no such API (`C_AddOns.SaveAddOns` saves enable state only, `AddOnsDocumentation.lua:145`) **(i)**. `ReloadUI` is `C_UI.Reload` (`InterfaceUtil.lua.annotated.lua:1-3`); `ConsoleExec("reloadui")` from a timer would be routing around the hardware-event rule. Never.
- **Re-reading a loaded addon's files:** `dofile`, `load`, `loadfile` are removed from the client's Lua (`Core/Lua/basic.lua:6`) **(i)**.
- **Texture or font side channels for inbound data:** no API reads texels; a glyph-width channel is absurd. No.
- **The companion pressing keys** (`SendInput` of Ctrl+V or a slash command): input automation under the EULA's bot clause and "one hardware function = one action" **(ii)**. The player's own keystroke is the line, and it is not crossed.
- **No companion at all:** the manual path (`/simc`, the browser, paste the verdict) is already one paste and zero reloads, at the cost of two alt-tabs. Nothing hosted can push into the client.

## Policy, in one paragraph

The EULA's data-mining clause literally covers any external program that "reads ... information generated or stored by the Platform" - which is today's SavedVariables courier, every combat-log uploader and the Raider.IO client alike; in practice reading files the client writes and writing addon data files are public, tolerated practice, synthesising input is prohibited, and pixel reading is unruled. The clipboard courier is the SimulationCraft pattern in both directions: text the player can see, keys the player presses.

## Verification status of this memo

- Four research agents (inbound, outbound, workflow, external), one verification agent on the outbound agent's web claims (that agent's own fetches were blocked, so its (ii) grades came from search summaries until re-read), and a sixth that proved the synthetic bag line against the fork's own importer headlessly (five tests, all passing; the fork's tree clean before and after). Their conclusions and what each still owes are folded in above.
- **Nothing here has run in a client.** The (iv) items are the owner's fifteen minutes; the memo does not stand or fall on any single one, because the layers are independent.

## Proposed issues, for the owner's word (not filed)

1. **Equip Now guard** - no Equip on a swap whose replaced piece is outside every pass's `considered`; the hazard above. Small, independent of everything else.
2. **Keep the Upgrade Finder's `equipped`; provenance on stale surfaces** - `UFImport` keeps the baseline, `Drift` takes its baseline from the rating's record, the phrases `rated before you equipped X` / `not rated since you equipped X` on the surfaces in the table. No companion change.
3. **Foresight tier 1** - the companion's import A per candidate, the `foresight` key, `ns.Foresight`, the selection rule on the drop, `rated before it dropped`.
4. **Foresight tier 2** - import B and the after-equip selection.
5. **Clipboard inbound** - the companion's gzip+base64 envelope and sound; the paste box's prefix, auto-import and native decode. Preceded by the owner's paste test.
6. **Clipboard outbound** - the refresh ends in the highlighted export box and the player's Ctrl+C instead of `ReloadUI`; the companion's clipboard listener. With 5, zero reloads.
7. **Load-on-demand stub spike** - only if the owner wants it after reading layer 3; the memo's own recommendation is to leave it.
8. **Upstream ask on the fork PR** - have `processItem` export the displaced item (`UpgradeFinderEngine.js:365`), so "which ring does it replace" is QE Live's own answer.
9. **Capture on change (layer 2b)** - the `inventory`, `vault` and `currencies` captures re-run on the gear, vault and currency events the addon already registers, out of combat, debounced, stored as `trigger = "change"` in the ring of four; the logout flush then carries current gear with no command. Small; the first issue to build if the owner wants the Raider.IO shape, beside issue 1.
10. **Several characters in one verdict file** - the contract change that lets two healers in one evening each load their own rating at login. Only needed with 9.

Every issue filed from this list carries the worktree and rebase commands and a reading list (this memo, §0, §5, §7 of the brain), as the working rules require.
