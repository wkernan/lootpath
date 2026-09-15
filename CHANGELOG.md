# Changelog

## Unreleased

### R-7a (WKE-582) - log out *or reload*, and Lootpath keeps only what it needs

- **It is a reload as well as a logout, and now it says so.** The game unloads
  the interface for both, so the snapshots R-7 takes "on the way out" were
  already being taken on every `/reload` - and were being labelled a logout,
  which the companion then printed for a plain reload. Nothing at that moment
  can tell the two apart. So the capture keeps happening on both, which is what
  makes the second reload of a refresh carry your current gear, and everything
  it records now says `flush`: `run after a logout or reload (gear captured at
  the flush)`. `run after logout` is gone, because nothing could prove it.
- **The saved file no longer grows forever.** Lootpath kept every snapshot it
  had ever taken: the owner's file went from 6.1 MB to 11.0 MB in two days, 35
  copies of the same bag scan among them, and the game reads and writes all of
  it at every login and every reload. It now keeps the four newest of each kind
  and drops the rest - enough to compare a refresh against what came before it,
  and nothing beyond that.
- **Nothing you look at changes.** The companion has always read the newest
  snapshot of each kind and still does.

### R-7 (WKE-579) - log out, and your plan is current next time you log in

- **Logging out now captures your gear.** Lootpath takes the same four
  snapshots on the way out that `/lootpath refresh` takes - gear, bags, vault,
  currencies - so the save the game writes as you leave carries what you logged
  out in. The companion rates it while you are away, and the plan is waiting at
  the next login. Before this, a logout saved whatever was last captured, so the
  story was only true if you had remembered to refresh first.
- **Refresh is now for mid-session only.** Claim a reward, crest a piece or loot
  a drop and want the rating to catch up before you carry on? That is what the
  window's `click to refresh` row is for. Log out instead, and you need do
  nothing.
- **It costs the logout nothing and cannot go wrong loudly.** Nothing waits,
  nothing is asked of the server, and no reload is involved - the game is
  already leaving. The Great Vault is read plainly; a capture that fails leaves
  the other three standing. A forced logout in combat captures nothing at all,
  because nothing in Lootpath runs in combat.
- **The companion's log says which it was.** `run after a logout or reload (gear
  captured at the flush)` joins the three lines R-6 added, and is read off the
  addon's own label rather than guessed at.

### R-6 (WKE-578) - the window tells you when your gear has moved past the plan

- **A second row under the status strip, when there is something to say.** Claim
  your vault reward, loot a drop, catalyst or crest a piece, and the window says
  `your gear changed since this plan (2 items) - click to refresh`. Hovering it
  names the newest arrival. Clicking it does the whole first step for you: it
  captures your gear, bags, bank, vault and currencies and reloads. Before this
  the only place that said anything was the tooltip of the item itself, and only
  if you happened to hover it.
- **The launcher wears a small gold badge while that row is up**, with the same
  words on its tooltip. No sound, no popup, nothing flashing.
- **After the reload the window says the rating is being made, and roughly how
  long it takes.** `rating your gear, started 30 seconds ago, usually ready in
  about 45 seconds - click to load it`, counting. "About 45 seconds" is the last
  run that actually rated something, rounded to the nearest 15 seconds; until
  there has been one it says `usually about a minute` and nothing more precise.
  Clicking reloads. Click too early and the same line comes back with the new
  time. A run that died says so instead, as it did before.
- **It stays quiet about things that are not gear.** A potion stack, a crest
  token or a Hearthstone moving is not a change to your gear and does not set it
  off; neither is putting on something out of your own bags that the plan
  already knew about, nor opening the bank.
- **Log out, and your plan is current next time you log in - if you refreshed
  first.** The companion's log now says which it was: `run after /lootpath
  refresh (gear captured at the click)`, or `run after a logout or a plain
  reload - nothing new was captured`. A logout on its own saves the gear that
  was last captured, not the gear you are wearing; see the companion's README.


### R-3b (WKE-576) - when you have already done what the plan said

- **The thing you just took out of the vault is no longer something to skip.**
  Take the weapon the plan picked, put crests into it, and hovering it in your
  bags used to read `Skip this one, the plan uses the vault weapon.` - the plan
  telling you to skip the very thing it sent you for. It now reads `This is the
  vault Worldroot the plan wanted. Refresh to rate it at 315.` The rating has
  not seen it yet and the line under it still says so; nothing is guessed at.
  The same holds for a tier piece you have already put through the Catalyst.
- **A vault reward that is already in your bags says so.** Its road on the
  Upgrade Map reads `claimed · in your bags` instead of `open now`, its step is
  to refresh rather than to take it, and its button is Refresh. Nothing here
  asks the vault anything - it reads your bags.
- **Roads have their names.** A rating carries item IDs and levels and no names
  at all, so a road could sit there as `a vault reward (321)` or `a crafted
  piece (331)` for hours even when the item was one you were wearing. Roads now
  take the name out of the reward's own link where there is one, and out of what
  your client already knows where there is not - and the plan's own sentences
  say the name too, not just the rows.
- **A plan that is behind your bags says what to do about it.** Where a slot
  holds something the rating never saw, the tooltip's header and that slot's
  header on the Upgrade Map both end `/lootpath refresh`.

### R-2b (WKE-575) - the bag mark is drawn at the size you see it at, and it says how often your bag addon asked for it

- **The mark in your bags is a new picture.** It was the Great Vault's own
  selection glow, borrowed so that the bag and the Vault tab would mean the
  same thing with the same picture. That glow is 214 by 121 pixels and is made
  to sit behind a whole vault cell; in a bag slot's corner it was squeezed into
  a 15-pixel square and came out as nothing you could see. The corner mark is
  now a solid gold square with a dark edge, drawn at the size it is shown at,
  in the same gold the Vault tab edges its pick with. The Vault tab keeps its
  glow.
- **`/lootpath glow` says how many times your bag addon actually asked.** It
  reads `Baganator asked the widget <n> times this session, last answer: yes for
  <the item>`. If that number is 0 after you have opened your bags, your
  bag addon never asked for the mark at all - which is a different fault from a
  mark that is asked for and not drawn, and the command says so in those words.
  `/lootpath capture glow` records the same.

### R-2a (WKE-571) - the plan takes a position on everything you own, and a missing mark says why

- **A piece in your bags always gets a sentence now, rated or not.** A helmet
  the rating never reached used to open on `not rated` and nothing else. The
  plan has a position on everything you own - use it, catalyst it, or skip it -
  so it says `Skip this one, the plan uses your Lynx shoulders.` and keeps the
  honesty phrase as its road line underneath. A road to something you do not
  have - a dungeon drop, a crafted row, a delve row - still gets no sentence,
  because the plan takes no position on those.
- **Four things left the tooltip's road lines, and the Upgrade Map kept all
  four.** The crest cost clause, whose answer is at the vendor; the "same
  charge as" cross-reference, which points at a row you cannot see from a
  tooltip; `item 244572`, which is an ID and not a name (the tooltip says
  `a crafted piece (331)` until the client answers, and it now asks); and a
  `no rating` road that was taking one of three lines under a best-set pick.
  Other roads on a tooltip are rated roads only.
- **`Why this?` goes somewhere.** It reads `Why this? · /lootpath map`, and
  `/lootpath map` opens the window on the Upgrade Map.
- **`4 hour(s) ago` is `4 hours ago`.**
- **The bag mark explains itself.** `/lootpath glow` says which bag window
  Lootpath is marking and why, what your bag addon is doing with the mark, how
  much the plan has in it, and - for an item you shift-click into the command,
  or the first thing in your bags - whether the mark should be there at all.
  `/lootpath capture glow` records the same for every bag slot.
- **The mark moved to the top-right corner in Baganator.** Its top-left corner
  is where your item level is drawn, and a corner shows one mark at a time.

### R-2 (WKE-563) - In place: the plan on the tooltip, and a glow that means one thing

- **Blizzard's own item tooltip gains a Lootpath block.** Hover a piece in
  your bags, in Lootpath's vault cell or in the Adventure Guide and the
  tooltip the client was already drawing gains a header with the slot and the
  rating's age, the item's part of this week's plan in the words a guildmate
  would type (`Catalyst this one.`, `Grab this from the vault and crest it.`,
  `Skip this one, the plan uses your Lynx shoulders.`), the item's own road,
  up to two more under `Other roads for this slot`, and `Why this?` last.
  Three roads, never a fourth. When nothing rated the item the honesty phrase
  takes the road's place, with the tail that says which cure it has.
- **A bag glow that fires only for a road worth taking.** A slot is marked
  when the plan rates that item, or something it can become, as in your best
  set or a positive percent. Rated-and-behind does not glow; not rated does
  not glow.
- **One glow interface, one adapter per bag window.** Lootpath draws the mark
  in Baganator's window through its public corner-widget API, so an upgrade
  arrow you already have keeps its place, and in the client's own bag frames
  otherwise. A bag addon Lootpath has no adapter for gets no mark and loses
  nothing on the tooltip; the status strip says which window the mark is in.
- **Nothing is computed and nothing runs in combat.** Every line is a road
  from the model and every number is a document's. The hover is a table lookup
  into a map built once per verdict and rebuilt when your bags, your gear, the
  vault, your currencies, an item's data or the companion's answer changes; in
  combat the tooltip adds nothing, the marks keep their last state and nothing
  is rebuilt until combat ends.
- **Removed:** the temporary `/lootpath spike tooltip` measurement command and
  its capture. It existed to measure this surface before it was built, and
  this is the surface.
### R-3a (WKE-570) - a road rated behind what you wear never tells you to take it

- **No "do:" on a road the plan is not going forward on.** A second copy of the
  helm you are wearing, rated 0.95% behind it, ended its row with
  `do: equip it`. Every imperative a row can carry is now one entry in a
  phrasing table, and one gate decides whether the row gets it: the rating is
  "in your best set", or it is a percent above zero. That gate is the same one
  the bag glow uses, so the two cannot come apart.
- **What a gated row says instead is the plan's own words.** Where the plan for
  the slot is to keep the piece you are wearing, every road rated behind it
  ends `keep what you've got on` - the same clause the slot's header opens
  with. Where the plan picks another road in the slot, the row ends after its
  facts; the badge already says what the plan does instead
  ("taking the vault weapon instead"). A road nothing rated says neither: not
  knowing is not a verdict.
- **The Keep row is unchanged**: `nothing to do` is not an imperative.
- **The "the pick" label sits inside its cell.** On the Vault tab it was drawn
  above the cell's top edge and landed on the bottom of the row above it. Every
  cell now reserves a band at its top for the label, so the pick can move
  without anything else moving.


### Fix (2026-09-14)

- **`tools\sync.ps1` writes a `Data\` placeholder the game lacks.** After C-9
  added `Data\CompanionStatus.lua` to the `.toc`, a sync that found the
  companion's `QEVerdict.lua` kept the whole folder and never added the new
  file, and the client raised "Error loading ..." at login. A file the game has
  is still never overwritten.

### R-4 (WKE-565) - Crafting and Delves as runs, and what the export knows

- **The by-run view gains the two sources the loot map cannot walk.** Every
  Upgrade Finder export the companion writes carries 33 `Delves` rows and 18
  `Crafted` ones beside its drops, and the by-run view had nowhere to put them:
  it lists what the Adventure Guide walk found, and the walk finds no crafting
  order and no delve. There is now a `Crafting` card and a `Delves` card beside
  the instance cards, ranked by the same two orders every run uses - best
  upgrade, most upgrades - and never by a combined score. Open one and it lists
  every ranked item it has.
- **By slot they are already there**, as the roads R-3 draws under
  `Other rated sources`: one road per crafted and per delve item the export
  ranks for the slot. This release points that list at the one place these rows
  are found and ordered, and gives the crafted road the line its rating
  assumed - `the rating assumes Crit / Haste` - beside `spark and materials not
  read`.
- **A card's denominator says "ranked items", not "drops".** A run's count is
  out of every drop the Adventure Guide lists for it; these two have no loot
  table behind them, only the items the export ranks, and the wording says so.
- **They carry no difficulty, so no difficulty filter hides them**, and the
  difficulty dropdown gains no entry for them. Said once under the list.
- **What cannot be read is said, not guessed:** a crafted row reads
  `Crafted, Crit / Haste - spark and materials not read` (the crafted LEVEL in
  the same settings is an index, not an item level, and is never shown), and a
  delve row reads `Delves - key and Bountiful state not read`.
- **No row names a Mythic+ key**, because the key is not what values them:
  measured over one companion run, all five key-level documents carry these 51
  rows with identical numbers and only a Raid export differs. A row says which
  document it came from only when two stored documents disagree about it.
- The export carries no item names, so a row asks the client for one and fills
  itself in when the answer arrives, exactly as a Great Vault reward does.
- Not one number on the tab changed: every percentage is the export's own, and
  the walk's own counts, rows and rankings are what they were.
### V-1 (WKE-569) - no screen names where a rating came from

The owner decided on 2026-09-11 that player-facing text names no source: not
the engine, not "his", not an address, not "the addon has determined". The
screen shows the rating and says what to do. The Roads lane was written to that
rule; the three tabs that existed before it were not. This is the rest of it.

Nothing on screen moved but the words. No number, no ordering, no count and no
row changed.

- **Ratings speak for themselves.** "QE Live's pick" is now "the pick", "QE Live
  valued it at 321" is "rated at 321", "QE Live: better by 3.08%" is "better by
  3.08%", and "QE Live: no change" is "no change". Equip Now's fifth count was
  "without a verdict" and is "no rating"; a slot the best set does not name said
  "QE Live's set does not name this slot" and now carries the phrase table's
  `no rating`.
- **The status strip is five facts, not six.** It opened with the engine's name;
  it opens on your spec.
- **The paste path still tells you what to paste**, because you are holding that
  file - it is the one place a file format is named. "paste the Top Gear JSON
  export (its Download JSON button) here"; "this is not a Top Gear export: its
  schema is %s". The site is not named.
- **Internal names are untouched**: module names, `qeSettings`, the
  `qe-live-droptimizer` schema strings, the `no_verdict` status. One
  player-facing string keeps a listed word by design - the companion's refusals
  name `Data\QEVerdict.lua`, because a malformed file is no use to a player who
  is not told which file it is.
- **A guard that stays**, `spec/voice_spec.lua`. One half drives the real window
  over the committed fixtures with both genuine exports and reads back every
  tab's lines, the Vault grid's cells, the strip and its tooltip, the Import
  dialog, every refusal the two importers and `Match` can produce, the slash help
  and `/lootpath status`. The other walks the panels' own string tables, so a
  branch no fixture reaches is caught as well. Each half asserts a floor on how
  many strings it read, so a surface that goes quiet fails instead of passing
  empty.
- **The Upgrade Map's ten badge sentences are named constants now.** Four of them
  sit in branches no committed fixture reaches, and as literals inside those
  branches they were the one place a source could come back unwatched.
- **Two strings were looked at and left, deliberately.** The Vault tab's
  `this week (vault upgraded, Catalyst used)` scenario label names no source, and
  its parenthetical is the only place the tab says what that scenario assumed.
  `ValueBadge`'s optional lead survives because the Vault tab passes a scenario
  name through it, which is not a source either.

### T-1 (WKE-560) - the headless stub models one widget's mixin chain per widget

Nothing in the addon changed. This is the test harness, and it is the class of
bug that hid the Upgrade Map crash behind 761 green tests.

- **Every kind and every template `spec/stubs/wow.lua` models was diffed,
  method by method, against Blizzard's exported annotations** (Ketho's, under
  `.luals/`), and each block now names the file and line it was read from.
- **The leak was the constructor, not the templates.** One `newRegion` built
  every widget out of the union of `Region`, `FontString` and `Texture`, and
  `newFrame` added `ScrollFrame`'s scroll setters on top - so a plain `Frame`
  answered `SetText`, `SetTexture`, `SetTexCoord` and `SetScrollChild`, a
  `FontString` answered `SetAtlas`, and a `Texture` answered `SetText`.
  Nineteen method names left the widgets that do not have them.
- **A template is added to, never subtracted from.** The dropdown fix that
  shipped in PR #72 handed `SetDefaultText` to every `DropdownButton` and took
  it back inside `attachTemplate`; a dropdown built with no template never
  reached the subtraction and answered it anyway. The caption surface is now
  attached only to `WowStyle1DropdownTemplate`, whose mixin actually has it.
- **Nothing that is not the client's sits in a Blizzard method slot.** The
  stub's own test affordances moved to `widget.stub`: `button.stub:Enter()`,
  `dropdown.stub:Pick(2)`, `box.stub:Acquire()`, `world.tooltip.stub:Text()`.
  `Pick` was the dangerous one - the client has a real `Pick` that takes a menu
  description, not an index.
- **A released scroll-box row stops answering for its old data**, the way the
  real view clears `GetElementData` when it puts a frame back in the pool.
- **New `spec/stubs_spec.lua`** locks all of it: every removal is asserted
  absent on the widget that does not have it and present on the one that does.
### C-9 (WKE-559) - the companion is visible from inside the game

- **A log file next to the verdict.** `Data\companion.log` carries every line
  the companion prints, with the date the terminal leaves out, and rotates at
  200 KB keeping one `companion.log.1`. Until now the watcher printed into
  whichever window started it and nowhere else, so a run that died looked
  exactly like a run that had nothing to do.
- **A status chunk the addon reads.** `Data\CompanionStatus.lua` says what the
  last run did - `state` (`idle` / `running` / `skipped` / `failed`),
  `startedAt`, `finishedAt`, `stage`, `message`, `profileCapturedAt`,
  `verdictWrittenAt`, `exitCode` - and is written at every stage change, so a
  run in progress says so rather than leaving the last one's words on screen.
  Data and never code, like the verdict chunk, through the same escaper.
- **The status strip says it in one clause**: `companion: wrote 3 minute(s)
  ago`, `companion: run started 22:48`, `companion: profile unchanged, no run
  (23:06)`, `companion: FAILED at profile (21:06) - see companion.log`, or
  `companion: never seen` with the committed placeholder in place. It is on the
  line even when nothing has been imported at all, and the companion's own
  sentence rides in the strip's tooltip.
- **Start with Windows.** `tools\companion\install-startup.ps1` registers a
  logon task for the current user that runs `start-companion.ps1`: the fork's
  dev server if nothing answers it, then `node companion.js --watch`.
  `uninstall-startup.ps1` removes it; both are idempotent and neither touches a
  watcher the owner started himself.
- **Never two watchers, enforced.** The watcher takes a lock file in the state
  directory and a second one exits 7 naming the pid that holds it. A lock whose
  process is gone is taken over, so there is never a file to delete by hand.
- `tools\sync.ps1` keeps the game's `Data\` when EITHER companion file is
  there, so a status that says why a run died is not replaced by the
  placeholder.
### R-3 (WKE-564) - Roads as the Upgrade Map slot's row, and the week's plan on the Vault tab

- **A slot on the Upgrade Map now opens onto its roads, in three groups.** The
  slot header carries the slot's own line in chat voice - "Catalyst your Lynx
  shoulders, skip the vault ones, no crests here." - and under it sit *Your best
  set* (the pick with a gold edge, then the rated alternatives, each naming what
  it is measured against), *Other rated sources* (the percents against what you
  wear, with the scale named once in the header) and *No rating*. The group
  order is fixed and is not a ranking; inside a group the order is the rating's
  own.
- **Every row says the same things in the same order:** where it comes from, the
  item as it would arrive, the badge with its referent and the level the rating
  assumed, the muted facts (what you hold, what is not readable, the other road
  that wants the same charge, the client's own countdown), the thing to do, and
  one button - but only where the button goes somewhere.
- **Two verbs are wired.** *Show run* switches to the by-run view, opens that
  run's card and scrolls to it; *Show in vault* opens the Vault tab and marks
  the cell for a few seconds. The Catalyst, a craft, a delve and the upgrade
  vendor have no button, because the client offers no call for them.
- **The Vault tab opens with the week's plan.** "Grab the Worldroot from the
  vault and crest it. Catalyst the Lynx shoulders in your bag. Skip the vault
  shoulders.", with the footnote when the plan wants more Catalyst charges than
  you hold. Everything the tab already said is still under it, unmoved.
- **New setting: Explain** (off by default). With it on, one plain sentence
  appears under the first use of a system word in an expanded slot - track,
  crest, Catalyst, Bountiful, spark, plan - each saying only what the client
  says or what the rating names.
- Nothing here names where a rating came from, and no number in it is
  Lootpath's. Journal drops the client answers item level 1 for are still
  hidden and still counted, exactly as before.

### R-1 (WKE-562) - the road model and the plan sentence

- **`ns.Roads`, the one model every Roads surface will render.** A road is one
  way to get an item into a slot: the vault, the Catalyst, a boss drop, a
  crafted item, a delve, the piece you already wear, or upgrading it.
  `ns.Roads.ForSlot(slot, inputs)` answers for a slot, `ns.Roads.ForItem(key,
  inputs)` answers for the item under the cursor with at most three roads.
  Nothing is drawn by this change.
- **Three groups, never one ordering.** Your best set, other rated sources
  (percents against what you wear) and no rating. A whole-set verdict and a
  per-item percent are two scales, so they are never sorted together; inside a
  group the order is the rating's own.
- **The four honesty phrases and the five verbs are constants**, so three
  surfaces cannot drift apart about what "not rated" means or where a button
  goes. A road whose next step is not something the addon may open - the
  Catalyst, a crafting order, a vendor, a delve - carries no button at all.
- **Every surface that shows more than one road now has a sentence to open
  with**, in the words a guildmate would type: "Grab the Worldroot from the
  vault and crest it. Catalyst the Lynx shoulders in your bag. Skip the vault
  shoulders." When the plan spends more Catalyst charges than you hold, the
  sentence says the first and a footnote says the rest - it never picks for you.
- **No string in it names where a rating came from**, and no number in it is
  Lootpath's: every badge is a figure one of the companion's documents carries.
- Crest costs still say "not readable" for a vault reward or a drop and "not
  read" for a piece you own, a delve row still says "not read", and a crafted
  row still says "spark and materials not read". None of those is readable from
  the client.
### R-0 (WKE-561) - the Roads spike: measure first, show nothing

- **A tooltip counter behind `/lootpath spike tooltip on|off|report`, off unless
  you turn it on.** It counts how many item tooltips fire, what each call costs,
  whether the hyperlink was nil or secret, which tooltip frame fired, and how
  often it returned at once because you were in combat. It reads nothing about
  the item and draws nothing on any tooltip. The numbers are printed on request
  and stored as a `spike` capture, so `/reload` keeps them.
- **Temporary on purpose:** the module, the command and the capture go away when
  the real tooltip block lands.
- **`/lootpath capture env` records two more things:** the Mythic+ keystone you
  own (level, both map IDs, and the dungeon's name) and which bag addons and bag
  frames are live. Both are recorded for the transcript; neither is displayed.

### Fix (2026-09-12)

- **The "items left out" note names no source.** The Equip Now and Vault tabs
  said "QE Live did not consider N of your items"; they now say "N of your
  items weren't rated this time", per the 2026-09-11 decision that nothing on
  screen names where a rating came from.

### C-10 (WKE-567) - a left-out item is identified, not just named

- **The excluded list carries the item's identity.** Each entry in
  `Data/QEVerdict.lua` now holds `itemID`, the sorted `bonusIDs` and - on a
  Catalyst clone - the `originalItem` it was made from, read off the
  `data-wowhead` attribute QE Live's own card carries. The addon builds its one
  `ns.ItemKey` from the first two, so "was this item left out of the pool" is an
  identity comparison instead of a name comparison; two same-named items at one
  item level used to answer it as one.
- `ns.Companion.ExcludedKey(entry)` and `ns.Companion.IsExcluded(excluded, key,
  item)` are the join, for the road surfaces that must say `not rated - beyond
  the rating's item limit` about one item and not about its twin. An entry that
  carries no identity - every file written before this change - is still matched
  by name and level, and the answer says which of the two it was.
- **All or nothing:** a bonus list the addon cannot read whole takes the item ID
  down with it, and the companion refuses to write one rather than trimming it.
  A shortened bonus list is a perfectly valid key for an item nobody owns.
- Nothing on screen changed: the wording, the counts and the names are C-8's.

### C-8 (WKE-558) - QE Live is asked about the right thirty items, and says which it was not

- **The companion no longer fills QE Live's Top Gear in page order.** His Top
  Gear takes 30 items for a non-patron and the character owns more, so the
  driver now reads every card first, keeps everything the import made active
  (the equipped set, the Great Vault options and their clones), and spends the
  room on Great Vault items, then every Catalyst clone, then bag items one slot
  at a time. Page order was his slot list, so the weapons and every Catalyst
  clone used to fall off the end: on 2026-09-09 the `catalyzed` scenario scored
  identically to `asOffered` because not one clone was in the pool.
- **Nothing that arrived selected is ever deselected.** A card that is active at
  import is equipped gear, a vault option, or a clone of one - never a bag item.
- **The Equip Now and Vault tabs say what was left out**: `QE Live did not
  consider 27 of your items: ...`, in one shared wording, with every name
  available to the tab that wants to show them all. A verdict that omits items
  says so on screen.
- `Data/QEVerdict.lua` carries an `excluded` list beside `qeSettings` and on
  every Top Gear document. A file written without one reads exactly as before.
- **The cap itself is untouched.** It is QE Live's own patron rule and the fork
  is read and driven, never changed in what it decides.

### Fixes (2026-09-09, the owner's first look at the M5 window)

- **The Upgrade Map tab no longer errors on open.** Its difficulty dropdown
  was built from Blizzard's filter template, which has a fixed "Filter" caption
  and no way to show the chosen difficulty; the tab asked it to anyway and the
  client raised "attempt to call a nil value". It is now the selection
  template the Vault tab already uses, and the headless client models what each
  template really has.
- **The companion no longer dies on an empty bag slot.** Blizzard writes a freed
  slot between two filled ones as a literal `nil,` in the SavedVariables; the
  walk over bag items, equipped items and vault rewards now steps over it
  instead of reading `.link` on nothing. Every `/lootpath refresh` had been
  failing with exit code 3 and leaving the old verdict in place.
- **The minimap button sits outside the minimap you actually have.** The
  launcher read a fixed 80-point radius; it now measures the minimap at every
  placement, follows it when an addon resizes it, and rides the edge of a
  square minimap (ElvUI) instead of a circle inside it.

### M5-4 (WKE-553) - the Vault, drawn as the vault

- **The tab is the Great Vault**: three rows - Raids, Dungeons, World, in
  Blizzard's own order and under the client's own headings - of three option
  cells. Each cell is the reward the client is offering there, drawn as an item
  line: its own icon with a quality-coloured border, its item level in the
  icon's corner, the name in quality colour, and a grey line saying the slot
  and the level. A cell you have not earned yet says what the client says it
  needs ("Defeat 4 Midnight Season 2 Bosses").
- **QE Live's pick carries the Great Vault's own selected glow** - Blizzard's
  `evergreen-weeklyrewards-reward-selected`, or a gold border on a client that
  no longer has that art - and a "QE Live's pick" label. When the honest answer
  is "none - nothing in the vault beats your set", **no cell glows**: the
  closest option gets a grey "closest" label instead, so the grid and the
  headline never disagree.
- **One scenario on the cell, all of them one hover away.** The cell shows the
  line for the scenario the highlight follows; hovering it shows every
  scenario's line, word for word the same strings the text panel prints.
  Hovering the icon or the name still opens the item's own tooltip with the
  shopping compare.
- **The scenario dropdown is on the tab itself**, beside the header, in the
  Settings page's own words and writing through the same one setting. The
  Settings page keeps its copy.
- **The crests and the Catalyst charge are drawn with the client's own icons**
  and the client's own names, in a strip under the grid. Still no arithmetic:
  a chip is a name, an icon and the number the client reports.
- The headline block is unchanged and still comes first, now with the pick's
  icon beside it and its first line in a larger font.
- Nothing the vault offers is off the screen: the Mythic Keystone that rides
  in with a reward is named on its cell, and the rows Blizzard does not draw -
  Concession, "Also receive" - are listed under the grid.

### M5-3 (WKE-552) - the Upgrade Map, drawn

- **The list is a real list.** Both views moved from a column of one font
  string per line to Blizzard's own `WowScrollBoxList` over a data provider,
  so the committed walk's 478 drops cost the frames that fit on screen rather
  than one frame per drop.
- **By slot: a collapsible section per slot**, headed by the icon and item
  level of what that slot is wearing and by how many drops it has. Candidate
  rows are the M5-1 item line - the drop's own icon, its name in quality
  colour, and a grey second line saying `boss - instance, difficulty`.
  `[owned 305]` is the "Owned" tag; QE Live's verdict is the badge on the
  right, with the document that gave the number - `(at +6)` - in grey after
  it. Which sections are shut is remembered per character.
- **By run: a card per run** - the instance's own Adventure Guide art as a
  left strip, the run and its difficulty, `best +1.83%` as QE Live's badge and
  the drop count in grey. A card opens onto its rated drops. The two sort
  orders stay two orders and are never combined into a score.
- **One difficulty dropdown** in place of the row of buttons that used to wrap
  (and, before that, run off the window's edge). It is the 11.0 menu API, and
  its rows are the map's own difficulties with the map's own counts.
- **The journal walk now records the instance's art** (`buttonImage1`,
  `buttonImage2` and `bgImage` from `EJ_GetInstanceInfo`, all file IDs the
  client hands over) and the aggregator keeps the loot row's `icon`. Both are
  reads of a call the walk already made; the capture still touches nothing.
  Every walk taken before this change has no art, and a run card with no art
  draws a plain strip rather than a stand-in picture.
- Nothing about the numbers changed. `Panel.Lines` and `Panel.RunLines` are
  byte for byte what they were, every join is untouched, and every badge is
  still one of QE Live's own sentences.

### M3-15 (WKE-556) - a catalyzed vault reward costs a charge

- **The "one charge" line counted a converted Great Vault reward as free.** The
  Catalyst spends one charge per item it converts, and it does not care whether
  the item came out of a bag or out of the vault. M3-14 counted only the
  owner's own items, so a set that converts his chest AND the vault's shoulders
  was shown as spending the charge once.
- **Every conversion is counted now, the vault's included.** A tier item the
  export flags as a vault option is a charge unless the vault is offering that
  very item ID - a reward that arrives as a tier piece already converts
  nothing. With no vault snapshot to compare against, a vault tier item counts
  as a charge: calling a conversion free is the one mistake worth avoiding.
- **On the owner's own week the honest answer is an absence.** All three sets
  the old count offered also convert the vault's Scavenger's Spaulders, so the
  line now reads "not in QE Live's export - no set he ranked spends the charge
  just once" on both the Dungeon and the Raid document.
- **The scenario lines say when a vault reward is converted**, in the same
  sentence as the owner's own conversions - "and catalyze your Hide of
  Pestilence (302) into the tier chest and the vault's Scavenger's Spaulders
  (308) into the tier shoulder" - so the count of charges on screen no longer
  understates what QE Live told the owner to do. That half is said even with no
  bags read: the vault snapshot alone is enough to name it.

### M5-1 (WKE-550) - Equip Now, drawn as items

- **Every row is the item, not a sentence about it.** A row now shows the
  item's own icon with a quality-coloured border, its item level in the icon's
  corner, its name in quality colour and a grey line under it saying where it
  is - the shape Blizzard's Adventure Guide and every popular bag addon use. A
  swap reads left to right: what you are wearing, an arrow, what QE Live wants,
  the Equip button. An already-best row is one icon with a green tick. Hovering
  the icon or the name opens the item's own tooltip, with the shopping compare.
- **The five counts are chips above the list**, each in its status colour, so
  "5 to swap" is legible before a single row is read.
- **A verdict badge on the right, in QE Live's own colours** - gold when his
  number says better, burnt orange when it says worse, grey when he did not
  rank it. It is always text: a bar's length would be arithmetic on his
  numbers, and Lootpath never computes a healer value.
- **The list scrolls** rather than the window growing.
- **An item the client has not loaded yet is still a readable row.** It keeps
  its own icon (static data answers before the load) and says
  "Retrieving item information", exactly as Blizzard's journal does; Lootpath
  asks the client for the item once and fills the row in when it answers, and
  leaves the row alone if it never does. A row handed another item stops
  waiting for the first, so a late answer can never land on the wrong line.
- **One loader, shared.** The request-and-re-read the Vault tab got in M3-12 is
  now `ns.ItemData` and every tab uses it. The Vault tab behaves exactly as it
  did.

### M5-2 (WKE-551) - the chrome: a portrait ring, a status strip, and the paste box behind a dialog

- **The window wears Blizzard's portrait frame, and the ring says whose answer
  this is.** `PortraitFrameTemplate` in place of `BasicFrameTemplateWithInset`,
  with the player's current specialization icon in the ring - the class icon
  when the client names no spec, and an empty ring rather than a guess when it
  names neither. It is redrawn when the player changes specialization. Escape
  still closes the window, and it still drags and clamps.
- **The tabs moved to the frame's bottom edge**, where the Encounter Journal
  puts them, so the body above them is one uninterrupted rectangle.
- **One status strip in place of the paste box.** `QE Live - Restoration Druid
  - Dungeon Top Gear - companion, written 4 minute(s) ago - vault pick: as
  offered`, on one line under the title. The age turns amber when the export
  is older than the client's own weekly reset, which is what a dead companion
  watcher looks like. The sentence the window used to keep under the status
  line, the other stored export and the reason an age is amber are all in the
  strip's tooltip.
- **The paste box is now an Import dialog** behind the strip's `Import...`
  button, with the editbox, Import, Clear and the import status line inside it.
  Nothing about importing changed: the same routing, the same parsers, the same
  refusals shown verbatim. Options is still one click from the strip.
- **A launcher.** An AddOn Compartment entry (`## AddonCompartmentFunc` in the
  `.toc`, no library) and a minimap button drawn natively: left-click toggles
  the window, right-click opens the options page, and dragging moves it around
  the ring with the angle saved in the profile.
- **Two settings**: a window scale slider (0.7 to 1.3, applied with
  `SetScale` on the window alone) and a "compact rows" checkbox, which is
  stored for the item line M5-1 draws and changes nothing on screen yet.
- The Import dialog closes with the window, so a paste box never floats on
  with nothing behind it.
- The window size is unchanged at 620 x 640: WKE-549 has not answered the
  size question.

### M3-12 (WKE-547) - vault rewards read before their item data is cached

- **No more `[] (nil)` on the Vault tab after a client restart.** Right after
  logging in, the client hands over a reward's link with an empty name and
  answers nothing for its item level; the tab printed both. A reward like that
  is now `pending`: its row reads `name pending (item 275547) - level pending`
  in the panel's grey - or `Preyhunter's Lantern (from the last capture) -
  level pending` when an earlier vault snapshot named the same reward - and the
  headline uses the same words. Its key is intact, so every QE Live line under
  it, the counts and the pick are exactly what they were.
- **Lootpath asks the client for the item and reads it again.** One
  `C_Item.RequestLoadItemDataByID` per pending item, a second read on the
  client's load event (or on a bounded timer, 8 x 0.25 s, like the journal's),
  and one redraw of the Vault tab when it is the tab on screen. A reward the
  client never describes stays pending in words and is asked for again on the
  next look; nothing is guessed.

### M2-4 (WKE-541) - Equip Now says plainly when the best set is in the vault

- **A Great Vault option in QE Live's best set is not a "not owned" swap.** The
  tab used to draw it in the same red as a real gap -
  `[Lightgrasp Worldroot] -> item 251935 (ilvl 321) (not found: it is a Great
  Vault option you have not taken yet)` - for an item that is not missing at
  all, only unclaimed. The row now shows the piece you are wearing meanwhile,
  and a line under it says
  `QE Live's best set has a Great Vault option in this slot: Lightgrasp
  Worldroot (QE Live's level 321) - see the Vault tab`. The summary counts it
  apart: `14 already best, 0 to swap, 1 waiting in the Great Vault, 0 not
  owned, 0 without a verdict`.
- **Nothing is cut off at the frame's edge any more.** Every sentence a row has
  to say - the vault line, and the reason an item really was not found - now
  goes on its own wrapping line whose width comes from the row rather than from
  a fixed number.
- The Equip button is unchanged, and a vault row offers none: nothing here
  equips anything new.

### M3-7 (WKE-538) - the Vault panel against the real reward shape

- **The Mythic Keystone is no longer listed as gear.** The client hands one over
  in the same rewards list as every gear reward (and row 217 a Thalassian Token
  of Merit as well), and the panel showed it as "Mythic Keystone (1)" beside a
  305 weapon, where the 1 reads as an item level. Anything with no equippable
  slot is now named in words on the gear's own line - "+ Mythic Keystone" - with
  no level and never a value, and it is neither counted as an option nor
  eligible for QE Live's pick.
- **A row with rewards says "rewards ready".** After the weekly reset the client
  puts every activity's progress back to 0 while the rewards sit there
  claimable, so "unlocked" (progress >= threshold) read false on exactly the
  rows you can collect from. A row with no reward still shows its progress.
- **Both item levels, when they differ.** QE Live can be asked to value a vault
  option at its assumed upgrade, so the same link is 305 in the client and 321
  in the export that ranked it. The line now reads
  `Lightgrasp Worldroot (305; QE Live valued it at 321)`, and names which
  upgrade assumption produced his number when the companion recorded it
  (`qeSettings`, C-5). Neither number is adjusted and neither is chosen over the
  other; nothing is inferred from the difference.
- The rows carry the Great Vault window's own names - **Dungeons**, **Raids**,
  World - so one vocabulary covers both screens. `ns.Vault` keeps the measured
  enum's, and is untouched by all of the above.

### C-5 (WKE-539) - the companion asks QE Live for both upgrade settings

- **The companion no longer inherits QE Live's asymmetric import defaults.** His
  dialog opens with "Upgrade Vault to Max Level" on and "Upgrade ALL to Max
  Level" off, which values a vault option at the top of its upgrade track and
  the gear on your back where the client reports it - so a 305 vault weapon was
  ranked above the 308 copy already equipped. The driver now sets both boxes on
  every run, by the label each is rendered with, reads them back, and fails the
  run rather than reporting a setting it did not get.
- **Both default off**, which asks one answerable question: what is best out of
  what you have, at the levels the client reports. `qeAutoUpgradeVault` /
  `qeAutoUpgradeAll` in `config.json` set the other consistent pair (both on)
  for a "what if I upgraded everything" run. "Auto Catalyze" is not touched.
- `Data/QEVerdict.lua` records the pair as `qeSettings`, so a verdict is
  readable next to the question that produced it. M3-7 is what reads it: the
  Vault panel names the assumption behind QE Live's item level.
- Changing either setting changes the fingerprint, so the next run goes to QE
  Live even though no gear moved.

### M3-6 (WKE-535) - the Upgrade Finder import

- `ns.UFImport`: QE Live's `qe-live-upgradefinder` v1 export - the one that
  values drops you do **not** own - parsed and stored. Its own module, because
  its sign convention is the opposite of Top Gear's while the constant is the
  same `+1`: `upgradePercent` and `hpsGain` are positive when the drop is
  BETTER. Refuses the wrong schema (naming both), a `version` that is not the
  number `1`, a missing `items` list and a non-Retail export; warns on a
  character mismatch, an empty export, skipped drops and a drop listed twice
  with different values. Entries key on **itemID + item level**, because the
  stored report carries no bonus IDs; a drop several drop types list is one
  entry with several `sources`. Filed per content type in `db.char.ufImports`
  beside `db.char.qeImport`, so neither kind can overwrite the other.
- **One paste box, two schemas.** `UI.DetectSchema` reads the `schema` string
  without decoding the blob and `UI.ImportAny` routes it; the status line says
  which kind was imported and, when the character has both for that content
  type, shows the other one's age too. A third schema is refused by name.
  `UI.ActiveUpgradeFinder()` picks the export the content-type setting asks for,
  exactly as `UI.ActiveVerdict()` does for Top Gear.
- **The Upgrade Map has a second path to a number**, and it is still QE Live's
  own: a row whose itemID and item level the Upgrade Finder ranked shows his
  percentage. Measured over the committed fixtures - the 2026-09-06 20:09 cold
  walk against the 2026-09-07 Dungeon export - **30 of 478 rows gained a
  number**; 218 rows over 97 distinct drops are ranked at another item level,
  show nothing, and are counted with a line saying so. A zero reads "no change"
  rather than a direction QE Live did not give, `hpsGain` never reaches a row,
  and a pending row is never joined because its level is unknown, not wrong.
- **The companion's Upgrade Finder documents are read, not refused.** C-2 left
  `ns.Companion` refusing a `qe-live-upgradefinder` entry by name; it now picks
  the importer by schema and calls only `Parse`, `ContentTypeKey`,
  `ForContentType` and `Store` on it, so the staleness check compares like with
  like - a Top Gear import is never made stale by an Upgrade Finder one for the
  same content type - and the chat line names the kind, as the window does.

### C-2 (WKE-534) - the addon side of the local companion

- `Lootpath/Data/QEVerdict.lua`, listed in the `.toc` after `Core.lua`: the one
  file besides a paste that QE Live's answers reach the addon through. The
  committed copy is a placeholder that sets nothing and ships with the addon,
  because the `.toc` names it; the companion overwrites it on the owner's own
  machine. Its contract is one assignment - `ns.companionVerdict = { writtenAt,
  companionVersion, exports = { { schema, contentType, json } } }`, Lua strings,
  numbers and tables only.
- `ns.Companion` imports it at load: every field type-checked and passed through
  `ns.Safe`, nothing in the chunk called, no `loadstring`, and each export run
  through **the same `ns.QEImport.Parse` a paste goes through**, so every
  schema, version and `gameType` refusal applies word for word and is reported
  in chat with the file's age. A `qe-live-upgradefinder` document is refused by
  name until M3-6 can read one.
- The later of the file and what is stored wins: a paste made after the
  companion wrote its file is kept and says so, and reading the same file again
  on the next `/reload` imports nothing and says nothing.
- The window's verdict line and `/lootpath status` say where the verdict came
  from - "pasted", or "companion, written 4 minute(s) ago".
- `/lootpath refresh`: one word for the reload the loop needs, refused in combat
  because `ReloadUI` is protected there.
- `tools\sync.ps1` no longer overwrites the game's `Data\QEVerdict.lua` with
  the repo placeholder; `-IncludeData` does it deliberately.

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
