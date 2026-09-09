# Lootpath UI polish - the proposal (2026-09-09)

A recommendation, not a decision. Everything here is either read from the
code in `Lootpath/UI/` on 2026-09-09, read from a page or a Blizzard source
file the same day (URL beside it), or marked as a judgement. Nothing in it
changes the product rule: **Lootpath never computes a healer value.** A polish
changes how QE Live's numbers are shown, never what they are.

## 1. What the window is today (read from the code)

- `UI/MainFrame.lua`: one 620 x 640 `BasicFrameTemplateWithInset` window.
  The top third of every tab is the paste editbox (90 points), its three
  buttons, the import status line and the verdict note. Three
  `PanelTabButtonTemplate` tabs sit under that, in the body, not on the
  frame's edge.
- `UI/EquipPanel.lua`: up to 20 fixed rows of 20 points; each row is a slot
  label, one non-wrapping font string (`item link - already equipped`, or
  `link -> link (in your bags)`), an optional wrapping note and an Equip
  button. Colour is escape codes on text: green, yellow, blue, red, grey.
- `UI/UpgradeMapPanel.lua` and `UI/VaultPanel.lua`: a `UIPanelScrollFrameTemplate`
  whose content is a column of 14-point `GameFontHighlightSmall` strings, one
  per line of `Panel.Lines(model)`. Indentation is two or four leading spaces.
  The Upgrade Map's view, sort and difficulty controls are rows of
  `UIPanelButtonTemplate` buttons that wrap (`Panel.FilterLayout`).
- No texture is created anywhere under `Lootpath/UI/`. No item icon, no
  quality border, no instance art, no currency icon. The item link's own
  colour is the only quality signal.
- `Modules/Inventory.lua` and `Modules/Vault.lua` records carry `quality` but
  no icon file ID. The journal walk's raw rows carry `icon` from
  `EncounterJournalItemInfo` (it is in the 2026-09-06 transcript), but the
  aggregator's source entry (`Modules/Journal.lua`, the `entry` table around
  line 921) does not keep it, and no `buttonImage` value appears anywhere in
  that transcript: the walk does not record the instance art
  `EJ_GetInstanceInfo` returns.
- `spec/stubs/wow.lua` models `CreateTexture`, `SetTexture`, `SetAtlas` and
  `SetVertexColor` (accepted and ignored), so icon code is already
  constructible headlessly; asserting *which* texture was set needs the stub
  to record those calls, which it does not yet.

The screenshots the owner took on 2026-09-06 (ARCHITECTURE.md §9) match:
"rows `name (ilvl) - instance - boss, difficulty` sorted by level".

## 2. What the research says (read 2026-09-09; three agents, ~320 fetches)

### 2a. The popular set is Blizzard-native, "clean", and "at a glance"

CurseForge's WoW listing on 2026-09-09 leads with Details!, DBM, Auctionator,
RareScanner, Plater, BigWigs, Leatrix Plus, Mythic Dungeon Tools, Bagnon,
WeakAuras, Simulationcraft, Raider.IO
(https://www.curseforge.com/wow/addons; the sort variants all rendered the
same "relevancy" page, so this is not a confirmed download ranking). The
words that recur in their own copy are "clean", "at a glance", "lightweight",
"modular", "nothing enabled by default". CurseForge's Midnight Addon Trials
winners (EllesmereUI, Danders Frames, Coolinator) are all pitched as "modern"
while "true to World of Warcraft's visual style"
(https://www.curseforge.com/wow/addons/ellesmereui,
https://www.icy-veins.com/wow/news/players-have-spoken-these-are-the-best-wow-midnight-addons-on-curseforge/).
Forum sentiment on ElvUI is that it is "clean and modern" but "doesn't really
feel like Warcraft"
(https://us.forums.blizzard.com/en/wow/t/elvui-vs-blizzard-ui/1836652).

**Reading:** the 2026 target is Blizzard's own post-Dragonflight chrome
(`PortraitFrameTemplate`, `ButtonFrameTemplate`, NineSlice, tabs on the
frame edge) used cleanly, not a flat dark reskin. Lootpath is already on
Blizzard templates; it is the *content* that is not native-looking.

### 2b. An item is an icon with a quality border and corner badges

Every popular addon that lists items draws the same thing: an icon, a
quality-coloured border, and small badges in the icon's corners - item level,
BoE, an upgrade arrow (Baganator: "show BoE, item level, Pawn upgrade arrows
etc. on the item icons", https://www.curseforge.com/wow/addons/baganator;
BetterBags: https://www.curseforge.com/wow/addons/better-bags). Blizzard's
Adventure Guide loot row (`EncounterItemTemplate`) is a 42 x 42 icon, the name
in `GameFontNormalMed3`, slot / armour type / boss in small text, and an
`IconBorder` of `Interface\Common\WhiteIconFrame` tinted by quality
(https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.xml).
The 12.1 way to tint it is `SetItemButtonQuality`, which reads
`ColorManager.GetColorDataForBagItemQuality`
(https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua);
quality-coloured text is `|cnIQ4:...|r`, which real 12.1 links already use
(ARCHITECTURE.md §9). The loved affordances on the forums are Pawn's green
arrow on a bag icon and one-click equip
(https://us.forums.blizzard.com/en/wow/t/any-add-on-that-just-equip-what-the-highest-ilvl-gear/165375).

### 2c. QE Live's own visual language, and who trusts it

QE Live is a dark MUI theme: gold `#EFB73E` primary, paper `#424242`,
background `#121212` (`src/theme.js` in Voulk's repo). Its item card is a
28 or 42 point icon with a 1-point quality border, the **item level overlaid
bottom-right**, the name in quality colour, and a score badge on the right:
**positive = gold `#FFDF14`, non-positive = burnt orange `#C16719`** at 0.72
opacity for downgrades (`Panels/ItemUpgradeCard.js`). Tag words under a name:
"Vault" (aqua), "Catalyst" (plum), "Tier" (yellow); dashed blue border for a
vault item, dashed green for tier (`MiniItemCard.tsx`). Values under 0.2 are
shown as a percent, otherwise raw. The Upgrade Finder report is one accordion
per boss with the boss image, sub-sections Drop / Upgraded / Bonus Roll,
sorted by `rawDiff`. (All read in the repo; his live pages render an app
shell to a fetcher. His repo has no licence: these are facts about a look,
and no code or asset of his is copied.)

Healers name QE Live as their sim on the forums ("A lot of healers will use
QELive for their gear sims",
https://us.forums.blizzard.com/en/wow/t/gear-for-healers/788155) and
distrust Pawn ("showed a 50% improvement on an unsuitable healer item",
https://us.forums.blizzard.com/en/wow/t/pawn-is-a-lying-addon/993286).

**Reading:** a QE Live user should recognise the answer on sight. Gold means
better and orange means worse, the item level lives in the icon corner, and
"Vault" / "Catalyst" / "Tier" are coloured words. Pawn's green/red is the
grammar of the tool they distrust; Lootpath should not borrow it. Naming the
source on every verdict ("QE Live, 4 minutes ago") answers the stated
complaint about advice addons, which is trust.

### 2d. The comparable set, and the empty lane

Mr. Mythical's DPS Predictor has Lootpath's exact shape - a Bags tab ("best
loadout from what you own, with one-click Equip"), a Dungeons & Raids tab,
crest and Great Vault advice, a tooltip line - for DPS and tanks, with
trinkets unsupported and healers unmentioned
(https://mrmythical.com/addons/dps-predictor). Simdragosa carries Raidbots
Droptimizer results in via a desktop companion and shows "Color-coded
thresholds (green / yellow / grey)" on tooltips
(https://www.curseforge.com/wow/addons/simdragosa). Vault helpers annotate
Blizzard's own vault window in place (Vault Focus: "Integrates directly into
Blizzard's Great Vault window", https://www.curseforge.com/wow/addons/vault-focus);
none of them picks an item for a healer. Raidbots itself has no in-game
display at all
(https://support.raidbots.com/article/54-installing-and-using-the-simulationcraft-addon).

**Reading:** nothing in the popular set shows a healer sim's verdict in game.
The lane is open, and the polish should make that fact visible at first
glance: the window is where QE Live's answer lives.

## 3. The recommendation in one line

**Blizzard's chrome, QE Live's colours, an icon for every item, and the
answer before the evidence.** Unique through its subject and its palette, not
through custom art.

## 4. What changes, by area

### 4a. Chrome and launch

- `PortraitFrameTemplate` in place of `BasicFrameTemplateWithInset`, with the
  player's spec icon in the portrait ring (the same thing the Encounter
  Journal and the Collections window do). Tabs move to the frame's bottom
  edge (`PanelTabButtonTemplate`, as now, anchored to `BOTTOMLEFT` of the
  frame) so the body is one uninterrupted inset.
- The paste box is demoted. The companion loop made pasting the exception
  (ARCHITECTURE.md §0), yet the box takes the top third of every tab. Replace
  it with one status strip under the title - source, age, content type, and
  the scenario the highlight follows - and an "Import..." button that opens
  the editbox in a small dialog. The strip is also where "companion, written
  N hours ago" turns amber when it is older than the weekly reset, which is
  the tell §11 names for a dead watcher.
- A minimap button and an AddOn Compartment entry (`## AddonCompartmentFunc`
  in the `.toc` costs no library; LibDBIcon would need vendoring and a
  licence line). Every popular addon ships one or both.
- Options: a scale slider and a "compact rows" toggle, on the existing
  Settings page. No ElvUI skin detection yet; note it as the next ask if a
  second user appears.

### 4b. One item widget, used on all three tabs

A `UI/ItemLine.lua` frame that every tab draws instead of a font string:

- 36-point icon on the left. First paint from `C_Item.GetItemInfoInstant`
  (icon, equip slot; answers without a server round trip,
  https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfoInstant); name, quality
  and level filled through `Item:CreateFromItemID(...):ContinueWithCancelOnItemLoad`
  with the cancel kept on the row so a re-drawn row never gets a late
  callback (https://warcraft.wiki.gg/wiki/ItemMixin). Until then the icon is
  `INV_Misc_QuestionMark` and the name is `RETRIEVING_ITEM_INFO`, which is
  what Blizzard's own journal shows. **This is also the fix WKE-547 needs**
  for `[] (nil)` vault rewards; the two should share the loader.
- `IconBorder` = `Interface\Common\WhiteIconFrame`, tinted through
  `ColorManager.GetColorDataForItemQuality` (or `SetItemButtonQuality` on an
  `ItemButton` intrinsic), so the 11.1.5 quality colour overrides are
  honoured.
- Item level in the icon's bottom-right corner in `NumberFontNormalSmall`,
  where QE Live and every bag addon put it.
- Name in quality colour (`|cnIQn:`), one line, truncated with the full link
  in the tooltip; a grey second line for the fact the tab is about: slot and
  where it is (Equip Now), boss and difficulty (Upgrade Map), vault row and
  the client's level (Vault).
- Hover: `GameTooltip:SetHyperlink(link)` with the shopping compare, so
  "what does this actually have on it" is one hover away and never a line of
  ours.
- A verdict badge on the right, the same shape everywhere: QE Live's number
  exactly as his export says it (`+1.83%`, `-0.57%`), gold when he says
  better, burnt orange when worse, grey "not ranked" when he did not rank
  it; tag words beside it when they apply - "Vault" (aqua), "Catalyst"
  (plum), "Tier" (yellow). The badge is text on a dark rounded backdrop; no
  bar, because a bar's length would be arithmetic on his numbers and the
  first step toward a value of our own.

### 4c. Equip Now

- Rows become icon pairs: the worn item's icon, an arrow atlas
  (`common-icon-forwardarrow`), the best item's icon, then the badge and the
  Equip button. "Already best" rows show one icon and a green
  `common-icon-checkmark` in the badge's place. The blue `best_in_vault` row
  keeps its note and gains the "Vault" tag on the second icon.
- The five counts of `SummaryText` become five small chips above the list in
  their status colours, so "5 to swap" is legible before the list is read.
- Everything else stays: same `ns.Match` rows, same `Describe` texts (now
  split between name line, second line and badge), same combat behaviour.

### 4d. Upgrade Map

- By slot: each slot is a collapsible section headed by the worn item's icon
  and level; candidate rows are item lines whose second line is `boss -
  instance, difficulty`, with `[owned 305]` becoming an "Owned" tag and the
  two value lines becoming the badge plus a small `(at +6)` after it, exactly
  the words `Panel.UpgradeText` already produces.
- By run: each run is a card with the instance's `buttonImage1` from
  `EJ_GetInstanceInfo` (a file ID the client hands over,
  https://warcraft.wiki.gg/wiki/API_EJ_GetInstanceInfo) as a left strip, the
  run name and difficulty, "best +1.83%" as a badge, and "6 of 8 drops
  rated" in grey. The walk records no instance image today (§1), so this is
  a capture change first - the walk keeps `buttonImage1` beside
  `instanceName` - and then one human-required `capture journal` to prove
  the value arrives. The two rankings stay two sort orders, never a combined
  score (decision 2026-09-08, M3-8).
- The wrapping difficulty buttons become one `WowStyle1FilterDropdownTemplate`
  dropdown (the 11.0 menu API; `UIDropDownMenu` is deprecated,
  https://warcraft.wiki.gg/wiki/Patch_11.0.0/API_changes), and View / Sort
  become a two-button toggle on the same row. `Panel.FilterLayout` and its
  tests retire with the buttons.
- The two scrolling panels move from a column of font strings to
  `WowScrollBoxList` with a data provider
  (https://warcraft.wiki.gg/wiki/Making_scrollable_frames), so 478 rows do
  not mean 478 live frames.

### 4e. Vault

- Draw the vault as the vault: three rows (Raid, Dungeons, World) of three
  option cells, in the order and with the labels Blizzard's own
  `WeeklyRewardsFrame` uses, each cell an item line for the reward the client
  offers there. QE Live's pick under the chosen scenario gets the selected
  glow (`evergreen-weeklyrewards-reward-selected` is the atlas Blizzard's
  frame uses; validate at runtime with `C_Texture.GetAtlasInfo`, and fall
  back to a gold border if it is absent).
- The headline block (M3-9) stays above the grid, first, in a larger font:
  "QE Live's pick this week (as offered): ..." with the crest counts and
  the Catalyst charge each carrying their currency icon
  (`C_CurrencyInfo.GetCurrencyInfo(id).iconFileID`, already read by M3-11).
- The per-scenario lines under each option (up to three today, four after
  WKE-548) collapse to one line for the highlighted scenario, with the rest
  in the cell's tooltip; the Options dropdown that picks the scenario moves
  onto the tab itself.

### 4f. The signature

Lootpath's identity is its subject, and the polish should say it in three
places rather than with new art: the portrait ring shows the spec the
verdict is for; the status strip says whose numbers these are and how old;
and the badge is the one shape a reader learns once and finds on every tab.
The accent colour is QE Live's gold, used only for "better" and for the
selected vault cell, so the eye goes to the answer.

## 5. What does not change

- `Panel.Model`, `Panel.RunModel`, `ns.Match`, every parser, every join.
  The model tables gain `icon` (file ID) and `quality` where they lack them;
  nothing else moves.
- `Panel.Lines` / `RunLines` / `Describe` stay as the pure text the tests and
  `/lootpath status` read; the widget renders the same fields.
- No new library. Ace3 stays AceDB only (decision 2026-09-05). No skinning
  library, no LibSharedMedia (12.0.5 changed `GetFont` to return a
  `FontAsset`, and whether LSM has adapted is unconfirmed).
- No tooltip lines on other frames, no hook into Blizzard's vault or journal
  windows (decision 2026-09-05, "tooltips descoped"). Annotating the Great
  Vault frame in place is what Vault Focus does and would be the natural
  next step after this, not part of it.

## 6. How it would be built (three issues, own worktrees, in order)

1. **M5-1 - the item line, and icons on Equip Now.** `UI/ItemLine.lua`, the
   async loader shared with WKE-547, `icon` on Inventory and Vault records,
   the stub recording `SetTexture` / `SetAtlas` / `SetVertexColor` so a test
   can assert which icon and which border colour a row got, the Equip Now
   rows and chips. Premise to check first: that `GetItemInfoInstant` answers
   for every item ID in the committed exports, and that a `ContinueOnItemLoad`
   that never fires (the wiki's warning) leaves a readable row.
2. **M5-2 - the chrome.** `PortraitFrameTemplate`, edge tabs, the status
   strip, the Import dialog, the compartment entry, scale and compact
   options. Premise to check: `PortraitFrameTemplate`'s parent keys under
   `.luals`, read rather than remembered, the way MainFrame's header comment
   does today.
3. **M5-3 - the two lists.** `WowScrollBoxList` on both panels, slot
   sections and run cards, the filter dropdown, the vault grid with the
   selected glow and currency icons. The aggregator's source entry gains
   `icon` from the raw row, and the walk gains `buttonImage1` per instance.
   Premise already checked (2026-09-09): the committed transcript carries
   `icon` on its loot rows and no `buttonImage` at all, so the run-card art
   is the one part that waits on a human-required capture; the cards ship
   without art until it lands, exactly as the Vault tab shipped before the
   currencies capture.

Each is a normal issue: premise checked against the code and a transcript,
guards proven red, five gates green, and one human-required step - a
screenshot of each tab on the owner's client, because pixels are the one
thing the stub cannot check.

## 7. Open questions for the owner (none blocks a start on M5-1)

- **Screenshots of the three tabs as they are today**, at the UI scale you
  play at. Every layout figure above is from the code; the eye test is
  yours.
- **Do you run ElvUI or another full UI suite?** It decides whether an ElvUI
  theme hook belongs in scope now or waits for a second user.
- **Standalone window or embedded?** This proposal keeps the window
  standalone. Annotating Blizzard's Great Vault frame in place (what the
  vault helpers do) is a separate, later issue if you want it.
- **QE Live's palette.** Gold-for-better and orange-for-worse are his
  colours; carrying them into the addon is a design choice that makes his
  users feel at home and is worth a sentence in the WKE-528 conversation
  with Voulk, since it is his brand as much as his numbers.
- **Window size.** 620 x 640 fits 20 Equip Now rows at 20 points; item lines
  at 36 points would fit fewer before scrolling. Either the window grows
  (Blizzard's Encounter Journal frame is 800 x 496, read from
  `Blizzard_EncounterJournal.xml` under `.luals`) or Equip Now scrolls. The
  proposal assumes it grows toward the journal's width and scrolls anyway;
  the exact size is the eye test's to settle.
