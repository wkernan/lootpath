-- Lootpath/UI/VaultPanel.lua (M3-3, WKE-524)
-- The third promise: which Great Vault option to take this week.
--
-- Every number on this panel is QE Live's, joined to the vault by the exact
-- item key (itemID plus sorted bonus IDs). That join is sound here in a way it
-- is not on the Upgrade Map: a vault reward's hyperlink is a real item link
-- with real bonus IDs, and QE Live learns the same options from the
-- SimulationCraft export, so both sides speak the same key. An option QE Live
-- has not ranked shows its item level and its progress and no verdict at all.
--
-- Three things this panel says about a REAL vault, measured 2026-09-08 and
-- fixed in M3-7 (WKE-538). Every gear reward the client hands over rides with a
-- Mythic Keystone in the same rewards list, so anything with no equippable slot
-- is named in words beside the gear rather than listed as an item at level 1.
-- After the reset every `progress` is 0 while the rewards are claimable, so a
-- row that HAS a reward is presented as claimable and only a row without one
-- keeps the progress wording (`Modules/Vault.lua` still records exactly what the
-- client said). And QE Live's item level for a vault option can differ from the
-- client's - 321 against 305 on the measured pair, because his SimC importer can
-- be asked to value a vault option at its assumed upgrade - so both numbers are
-- shown, with the setting that produced his when the companion recorded it.
--
-- The highlight is QE Live's ordering, not this addon's: an option in his top
-- set outranks one that appears only in an alternative, and among alternatives
-- the order is QEImport.AlternativeRank, which reads his sign convention from
-- the pinned constant. An option nothing covers is never highlighted.

local _, ns = ...

ns.VaultPanel = {}
local Panel = ns.VaultPanel

-- The legend that used to sit here - "Rated options show their value. Other
-- options are listed by item level only." - is gone (V-5, WKE-600). It
-- explained a badge that says it itself, and it cost the grid a line of the
-- panel's own height on a tab whose whole subject is nine cells. Nothing
-- replaced it: the tab's header is the header, and the answer sentence is the
-- first thing under it.

-- The game's own words for the vault's rows. The owner's Great Vault screenshot
-- (2026-09-08) names them "Dungeons" ("Complete 1/4/8 Heroic, Mythic, or
-- Timewalking Dungeons"), "Raids" and "World", where `Vault.TYPE_LABEL` - the
-- measured enum's own vocabulary - says "Mythic+" and "Raid". A reader with
-- both screens open should see one set of words, so the panel translates and
-- the module keeps what it measured. Keyed by the enum NAME, resolved through
-- `Vault.ThresholdType`, so a client that numbers the enum differently still
-- lands on the right row; anything this table does not name keeps the module's
-- label.
Panel.ROW_LABEL_BY_ENUM = {
    Activities = "Dungeons",
    Raid = "Raids",
    World = "World",
}

-- ---------------------------------------------------------------------------
-- The vault drawn as the vault (M5-4, WKE-553). Three rows of three cells, in
-- Blizzard's own order and under Blizzard's own words.
--
-- The order is read off Blizzard's shipped frame rather than chosen here:
-- `WeeklyRewardsFrame:SetUpActivities` calls SetUpActivity for RAIDS, then
-- DUNGEONS, then WORLD (Blizzard_WeeklyRewards.lua under .luals/, the three
-- consecutive lines), and the PvP row is set up separately and only when the
-- client says to show it. Lootpath draws the three, and every option the
-- client lists outside them - a Concession row, an "Also receive" row - keeps
-- its place in the text list and is named under the grid rather than dropped.
Panel.ROW_ORDER = { "Raid", "Activities", "World" }
Panel.ROW_CELLS = 3

-- The FrameXML global each row's own heading comes from, when the client has
-- one. Their VALUES are not written down anywhere this repo can read - there
-- is no GlobalStrings transcript under `.luals/` - so the global is asked for
-- at runtime and ROW_LABEL_BY_ENUM above (the owner's own screenshot,
-- 2026-09-08) is what a client without it falls back to. Nothing here claims
-- to know what RAIDS says.
Panel.ROW_GLOBAL = {
    Raid = "RAIDS",
    Activities = "DUNGEONS",
    World = "WORLD",
}

-- What a cell with no reward says, in the client's own sentence. Blizzard's
-- `WeeklyRewardsActivityMixin:Refresh` picks the pattern by threshold type -
-- the activity's own `raidString` for a Raid row when it has one, else
-- WEEKLY_REWARDS_THRESHOLD_RAID; WEEKLY_REWARDS_THRESHOLD_DUNGEONS for the
-- Activities row; WEEKLY_REWARDS_THRESHOLD_WORLD for World - and formats it
-- with the threshold. The same three globals are asked for here and formatted
-- the same way; a client that has none of them leaves the cell with the
-- progress wording the text panel already prints.
Panel.THRESHOLD_GLOBAL = {
    Raid = "WEEKLY_REWARDS_THRESHOLD_RAID",
    Activities = "WEEKLY_REWARDS_THRESHOLD_DUNGEONS",
    World = "WEEKLY_REWARDS_THRESHOLD_WORLD",
}

-- The glow Blizzard's own vault puts on the option you have chosen
-- (`evergreen-weeklyrewards-reward-selected`, the SelectedTexture of
-- WeeklyRewardsActivityTemplate in Blizzard_WeeklyRewards.xml). Asked for
-- through C_Texture.GetAtlasInfo at draw time, because an atlas that has gone
-- from the client must not leave the pick unmarked: a gold border in QE Live's
-- own accent is drawn instead.
Panel.SELECTED_ATLAS = "evergreen-weeklyrewards-reward-selected"
Panel.SELECTED_HEX = "FFDF14"

-- ---------------------------------------------------------------------------
-- V-5 (WKE-600): the cell drawn as Blizzard draws it.
--
-- Blizzard's own vault gives a cell exactly two backgrounds, chosen in
-- `WeeklyRewardsActivityMixin:Refresh` (Blizzard_WeeklyRewards.lua under
-- `.luals/`) by one line - `self.unlocked or self.hasRewards` - and nothing
-- else. The same two atlases are named here and the same one line chooses
-- between them, so a reader with both windows open sees one answer twice.
-- Every atlas goes through `ns.UI.ItemLine.Atlas` at draw time, so a build
-- that has dropped one loses the art and keeps the words.
Panel.CELL_ATLAS = {
    locked = "evergreen-weeklyrewards-reward-locked",
    unlocked = "evergreen-weeklyrewards-reward-unlocked",
}

-- The tick Blizzard puts on a cell it has unlocked (the CompletedIcon of
-- WeeklyRewardActivityTemplate, Blizzard_WeeklyRewards.xml).
Panel.COMPLETED_ATLAS = "activities-icon-checkmark"

-- The row art, and it IS reachable by atlas: Blizzard's own frame passes these
-- three strings to `WeeklyRewardsMixin:SetUpActivity`, which sets them on the
-- row header's Background (Blizzard_WeeklyRewards.lua, the three consecutive
-- lines of `WeeklyRewardsMixin:OnLoad`). The XML declares that texture with no
-- atlas and no file, so the Lua strings are the whole source.
Panel.ROW_ATLAS = {
    Raid = "evergreen-weeklyrewards-category-raids",
    Activities = "evergreen-weeklyrewards-category-dungeons",
    World = "evergreen-weeklyrewards-category-world",
}

-- A locked cell's own corner, in the client's own fraction string when it has
-- one (`GENERIC_FRACTION_STRING`, which is what Blizzard formats
-- progress/threshold with) and in plain figures when it does not. Never a
-- number this addon worked out: both figures are the client's.
Panel.FRACTION_GLOBAL = "GENERIC_FRACTION_STRING"
Panel.FRACTION_FALLBACK = "%d/%d"

-- What an UNLOCKED cell says where the fraction was, per row, exactly as
-- `WeeklyRewardsActivityMixin:SetProgressText` says it: the raid difficulty's
-- own name for a Raids row, Heroic or Mythic <level> for a Dungeons row - told
-- apart by the client's own difficulty ID, not by the level - and the world
-- tier for a World row. Each is a FrameXML global asked for at runtime; a
-- client without one leaves that cell with no level text rather than a word
-- this addon invented.
Panel.LEVEL_GLOBAL = {
    heroic = "WEEKLY_REWARDS_HEROIC",
    mythic = "WEEKLY_REWARDS_MYTHIC",
    world = "GREAT_VAULT_WORLD_TIER",
}

-- What the mark on that cell says. The grey one is the `nothing beats your
-- set` case: the closest option is still named, and is still not called a pick
-- on a screen that says there is not one.
Panel.PICK_LABEL = "the pick"
Panel.CLOSEST_LABEL = "closest"

-- The cell's own last line. A cell whose option has more than one scenario to
-- report says where the rest of them are; the tooltip carries exactly the
-- lines `Panel.ScenarioLine` built, so the cell and the text panel cannot
-- disagree about what QE Live said.
Panel.CELL_HOVER_TEXT = "hover for the other scenarios"
Panel.CELL_NO_VERDICT_TEXT = "no rating in any scenario"
Panel.CELL_SECOND_SEPARATOR = " - "
-- A row the client generated more than one gear reward for. Not measured on
-- any transcript (every rewarded activity carried exactly one), so the cell
-- draws the first and says how many it is not drawing rather than pretending
-- the others are not there.
Panel.CELL_MORE_TEXT = "+%d more in this option"
-- The options the client lists outside the three rows Blizzard draws.
Panel.OTHER_OPTIONS_TEXT = "Also in this vault: %s"

-- The currency strip under the grid. The scenario lines above it already say
-- how many of a thing the player has, in words; this names each currency with
-- the client's own `name` and draws the client's own `iconFileID` beside it,
-- so "needs crests" has a face. No arithmetic: a chip is a name, an icon and
-- the client's number, and the Catalyst's chip carries its `maxQuantity` the
-- same way the sentence above does.
Panel.CURRENCY_UNNAMED = "currency %s"
Panel.CURRENCY_OF_TEXT = "%s of %s"
Panel.CURRENCY_NOTE = "Currency counts need /lootpath capture currencies."

-- The scenario dropdown on the tab's own header row. The Settings page keeps
-- its copy of the same setting, and both write through
-- `ns.UI.Options.SetVaultScenario`, so there is one stored answer and two
-- ways to reach it.
Panel.SCENARIO_DROPDOWN_LABEL = "Vault highlight"

-- What a row says about itself once the vault has generated its rewards. After
-- the reset the client sets every `progress` back to 0 while the rewards sit
-- there claimable (measured 2026-09-08: `HasAvailableRewards` and
-- `CanClaimRewards` both true, every progress 0), so `unlocked`
-- (`progress >= threshold`, `Modules/Vault.lua`) reads false on exactly the
-- rows the owner can collect from. The module's field is what the client said
-- and is left alone; the panel presents a row that HAS a reward as claimable
-- and says nothing about progress it no longer has.
Panel.CLAIMABLE_TEXT = "rewards ready"
Panel.UNLOCKED_TEXT = "unlocked"

-- QE Live's assumed item level, when it disagrees with the client's. Neither
-- number is chosen over the other and neither is adjusted: the client says what
-- the vault is offering, QE Live says what it valued, and the reader is told
-- both. Measured 2026-09-08: the vault's Lightgrasp Worldroot is 305 in the
-- client's own link and 321 in the export that ranked it, because QE Live's
-- SimC importer had "auto-upgrade vault" on.
Panel.QE_LEVEL_TEXT = "rated at %d"

-- Which of QE Live's two upgrade assumptions produced that number, when the
-- companion recorded them (`qeSettings` in Data/QEVerdict.lua, C-5/WKE-539). A
-- pasted export carries none, and then the difference is reported without a
-- reason rather than with a guessed one.
Panel.SETTINGS_PHRASE = {
    both = "with vault and all upgrades assumed",
    vault = "with vault upgrades assumed",
    all = "with all upgrades assumed",
    neither = "with no upgrades assumed",
}
-- The named scenarios, in the owner's words (C-6, WKE-540). QE Live's engine
-- answers three questions about the same vault - what each option is now, what
-- it becomes through the Catalyst, and what it becomes if everything is upgraded
-- as well - and each answer is shown under its own name. The keys are
-- ns.QEImport.SCENARIOS; the words are this panel's, and nothing but the words.
Panel.SCENARIO_LABEL = {
    asOffered = "as offered",
    catalyzed = "catalyzed",
    -- M3-13 (WKE-548): the fourth question, and the one the vault poses. The
    -- label spells out both halves of it, because "this week" alone would not
    -- say what was assumed and this line is read before anything else on the tab.
    thisWeek = "this week (vault upgraded, Catalyst used)",
    maxed = "everything upgraded",
}

-- The same names inside the headline's own first line, which already says "this
-- week" in its own words: "The pick this week (this week (vault upgraded,
-- Catalyst used))" is what the plain label produced, and a stutter inside nested
-- brackets is not a sentence anyone reads. Only the scenarios that need a
-- shorter form are here; the rest fall through to SCENARIO_LABEL.
Panel.SCENARIO_HEADLINE_LABEL = {
    thisWeek = "vault upgraded, Catalyst used",
}

-- M5-2b (WKE-601): the four plain names, and nothing else, for the one place
-- that has no room for a sentence - the CLOSED scenario dropdown on the tab's
-- header row. The owner's screen on 2026-09-16 read
-- `Everything upgraded (Catalyst and f...`: the control is as wide as the
-- header lets it be, and the Settings page's explaining label does not fit in
-- it. The menu's own rows keep that label, so the explanation is one click
-- away and this table is only the caption.
Panel.SCENARIO_SHORT_LABEL = {
    asOffered = "as offered",
    catalyzed = "catalyzed",
    thisWeek = "this week",
    maxed = "everything upgraded",
}

-- The plain name, or the scenario's own key when this build does not know it -
-- the same rule ScenarioLabel follows, for the same reason.
function Panel.ScenarioShortLabel(scenario)
    return Panel.SCENARIO_SHORT_LABEL[scenario] or tostring(scenario)
end

-- What a line says when the number on it is about QE Live's catalyzed copy of
-- the option rather than the option as the vault hands it over. His clone keeps
-- the slot, the level and the bonus IDs and changes the item ID, so the reader
-- has to be told which item the percentage is about.
Panel.CATALYZED_SUFFIX = ", as tier"

-- His `catalyzed` run made no tier copy of this option, which means his own
-- `Item.canBeCatalyzed()` said no. Read off the absence in his output rather
-- than restated from his rules: Lootpath does not know what can be catalyzed and
-- does not want to.
Panel.NOT_CATALYZED_TEXT = "the Catalyst run made no tier version of this item"

-- Which scenario the "<- the pick" highlight follows, said on the line, so
-- a pick that came from a what-if is never mistaken for what you have now.
Panel.PICK_TEXT = "  <- the pick (%s)"

-- ---------------------------------------------------------------------------
-- The headline block (M3-9, WKE-544). The owner's words, 2026-09-08, after the
-- first in-game run of this tab: it "doesn't do a good job of telling me what my
-- top pick is and why - the catalyst example: it should guide me that I would
-- need to get the shoulders, then use the catalyst (which we should know how
-- many charges I have), then upgrade with crests (which we should know how many
-- the player has and what type)".
--
-- So the block leads with the pick under the scenario the owner asked for,
-- and then lists every scenario he has an answer for, in QE Live's own order,
-- with what that answer assumed and how many of the thing it assumed the player
-- has. Three kinds of words and no others: a QE Live verdict, a client number,
-- and a fixed phrase naming what a scenario assumed. Nothing is computed - not a
-- cost, not a count of upgrades a pile of crests would buy, not a preference
-- between two of his answers.
Panel.HEADLINE_TEXT = "The pick this week (%s): %s"
Panel.HEADLINE_WHERE = " (%s)"
Panel.HEADLINE_NO_PICK = "The pick this week (%s): no option in this vault is in the answer"
-- When the best he said about any option under the highlighted scenario is
-- still "worse than your set", it is not a pick, and the first line must not
-- call it one on the same screen that says nothing beats the set.
Panel.HEADLINE_CLOSEST = "The pick this week (%s): none - nothing in the vault beats your set; closest: %s"

-- What one scenario's own pick is, said in his terms. "In your best set" is the
-- top-set case; anything else is an alternative, and an alternative in a Top
-- Gear export is by construction not better than the set it is measured
-- against, which is what the second phrase says. The per-option lines below the
-- block still carry his percentages; this is the summary, not a second source.
Panel.IN_BEST_SET = "in your best set"
Panel.NOTHING_BEATS = "nothing in the vault beats your set"
Panel.SCENARIO_SILENT = "none of these options is in this answer"

-- The scenario's pick is a different item from the headline's, so it is named.
Panel.INSTEAD_TEXT = "%s instead - "

-- What each scenario ASSUMED, as a fixed phrase per scenario. These are not
-- derived from anything and are not a model of either system: `catalyzed` was
-- QE Live's Catalyst box, `maxed` was his upgrade boxes, and `asOffered`
-- assumed nothing, which is why it has no phrase. Lootpath does not know what
-- the Catalyst costs, which items it takes, or what a crest buys.
Panel.NEEDS_TEXT = {
    catalyst = "needs a Catalyst charge",
    crests = "needs crests",
}

-- The same things said second, after an "and": "needs a Catalyst charge (you
-- have 1 of 8) and needs crests" is not English, and the verb only wants saying
-- once.
Panel.NEEDS_ALSO_TEXT = {
    catalyst = "a Catalyst charge",
    crests = "crests",
}

-- Which of those a scenario assumed, in the order they are said. `thisWeek`
-- (M3-13) assumed BOTH - one charge spent and the one thing taken upgraded - so
-- it says both, each with its own client number after it, and still computes
-- nothing: "needs a Catalyst charge (you have 1 of 8) and needs crests (you
-- have Runed 12)" is four client numbers side by side and no arithmetic over
-- any of them. `asOffered` assumed nothing, which is why it is absent.
-- `maxed` gained its Catalyst half in M3-13 and it is a correction, not a new
-- assumption: its boxes have had `autoCatalyze` on since C-6, and now that the
-- line under it can read "and catalyze your Venom-Cursed Lynx's Spaulders into
-- the tier shoulder", saying only "needs crests" beside it would contradict the
-- sentence next to it.
Panel.NEEDS_PARTS = {
    catalyzed = { "catalyst" },
    thisWeek = { "catalyst", "crests" },
    maxed = { "catalyst", "crests" },
}

-- The other half of the fourth question's answer (M3-13, WKE-548). QE Live's
-- `thisWeek` top set on the owner's own profile takes the vault's weapon AND
-- catalyzes a pair of shoulders he was already carrying in a bag - so "take the
-- weapon" is only half of what he said, and the other half is about an item the
-- vault is not offering at all. The sentence names it: the owned item's own name
-- and the item level the client reports for it, and the slot QE Live's clone
-- carries, in his own vocabulary lowercased so it reads inside the sentence.
--
-- When his top set holds such a clone but nothing in the scan matches it, the
-- second phrase is used and says exactly that. It is never filled in with a
-- guess at which of the owner's shoulders he meant: he did not say, so neither
-- does this.
Panel.CATALYZE_OWNED_LEAD = "and catalyze "
Panel.CATALYZE_OWNED_TEXT = "your %s (%s) into the tier %s"
Panel.CATALYZE_OWNED_UNKNOWN = "a %s you own (which one is not said)"
Panel.CATALYZE_OWNED_SLOT_UNKNOWN = "item"

-- The same sentence for the other side of the same charge (M3-15, WKE-556). The
-- Catalyst spends a charge on ANY item, a Great Vault reward included, so a best
-- set that converts a reward is spending a charge the line above would otherwise
-- never mention - and the count of charges on screen would understate what he
-- told the owner to do. The words differ only in whose item it is.
Panel.CATALYZE_VAULT_TEXT = "the vault's %s (%s) into the tier %s"
Panel.CATALYZE_VAULT_UNKNOWN = "a %s the vault is offering (which one is not said)"

-- The fifth question (M3-14, WKE-555). The line above says his `thisWeek` best
-- set catalyzes two of the owner's items; the owner holds one charge. So: with
-- one charge, which single conversion does QE Live rate best?
--
-- Every word of the answer is read off the `thisWeek` document itself. A Top
-- Gear export carries the top set plus up to twelve alternative sets HE built
-- and HE scored; `ns.QEImport.OneChargeCandidates` keeps the ones that spend
-- exactly one charge on an item the owner owns and orders them by his own
-- `scorePercent`. This line prints the first of them. Lootpath does not choose
-- the item, does not compare two of his answers and adds no number of its own:
-- the percentage is his `scorePercent` for that set, printed at his magnitude.
--
-- When no set in the document qualifies, that IS the answer and it is said in
-- those words, never filled in with the two-charge set from the line above.
--
-- The scenario whose document is read, named here rather than spelled inline:
-- the fifth question is the fourth question's own leftover, so it is asked of
-- the fourth question's document and of no other.
Panel.ONE_CHARGE_SCENARIO = "thisWeek"
Panel.ONE_CHARGE_LABEL = "one charge (this week, Catalyst used once)"
Panel.ONE_CHARGE_LEAD = "catalyze "
Panel.ONE_CHARGE_IN_BEST_SET = "in your best set"
Panel.ONE_CHARGE_BEHIND = "%.2f%% behind"
Panel.ONE_CHARGE_NONE = "no rating - no rated set spends the charge just once"

-- The client's count beside the assumption, or the honest absence of one.
-- `/lootpath capture currencies` has to have run for there to be a number, and
-- which currencies these are is read from that transcript by ID and never
-- guessed (Modules/Currencies.lua). HAVE_OF_TEXT carries the client's own
-- `maxQuantity` beside its `quantity` when the client gives one - two numbers
-- printed, nothing computed from them.
Panel.HAVE_TEXT = " (you have %s)"
Panel.HAVE_OF_TEXT = " (you have %s of %s)"
Panel.COUNT_UNKNOWN = " (unknown - run /lootpath refresh)"
Panel.CATALYST_NOT_READABLE = " (Catalyst charges: not readable)"
Panel.CRESTS_NONE = " (you have none of them)"

-- The scenario the owner asked to be highlighted has no stored answer, so the
-- highlight fell back. Said rather than silently substituted.
Panel.HIGHLIGHT_FALLBACK_NOTE = "No %s answer is stored yet, so the pick below follows %s."

-- A reward the client has not loaded the item data for yet (M3-12, WKE-547).
-- The owner's screenshot of 2026-09-09, right after a client restart, read
-- `[] (nil)` on four of five options and `[] instead - in your best set` in the
-- headline: the link's brackets were empty and GetItemInfo answered nil. The
-- key was intact, so every verdict line under those rows was right. A pending
-- reward is therefore counted, valued and eligible for the pick like any
-- other; only its words change - "name pending (item 275547) - level
-- pending", in the panel's note colour, never `[]` and never `nil`. When the
-- newest stored vault snapshot carries a name for the same itemDBID, that name
-- is shown instead, labelled: it is a fact the client stated in an earlier
-- session, not a guess, and it is what the client will say again once the
-- item is loaded. The level is never taken from a snapshot: the row would then
-- read as the client's current answer.
Panel.NOTE_COLOR = "|cff909296"
Panel.PENDING_NAME_TEXT = "name pending (item %s)"
Panel.PENDING_LEVEL_TEXT = "level pending"
Panel.FROM_CAPTURE_TEXT = "%s (from the last capture)"
Panel.PENDING_NOTE = "%d reward(s) are waiting for the client to load their item data. "
    .. "Lootpath has asked for it; this tab redraws when it arrives."

-- V-3 (WKE-587): the remedy was added to this sentence for the same reason
-- M3-16b added OPEN_VAULT_NOTE. `HasGeneratedRewards()` false is a vault the
-- client has not been given this week's rewards for, and what generates them is
-- the Great Vault window being opened (ARCHITECTURE.md 7, 2026-09-15) - so the
-- sentence that reports the state now also names the one thing that changes it,
-- rather than leaving the player to read the empty cells and guess.
--
-- V-5 (WKE-600) reworded it, because the owner read it on 2026-09-16 with the
-- Great Vault itself open on the other monitor. "Open the Great Vault once,
-- then refresh" is the remedy for M3-16b's state - rewards the client has been
-- told about but not given - and this sentence is the OTHER one: a week that
-- has generated nothing because nothing has been earned yet. Since this issue
-- the grid under it draws every cell's own progress, so the sentence says what
-- is true and points at the cells rather than sending anyone to a window that
-- would change nothing. The remedy for the state that does have one still
-- lives on OPEN_VAULT_NOTE below, which is chosen first.
Panel.NO_REWARDS_NOTE = "Nothing to take from the vault yet this week. Each cell below shows what it still needs."

-- V-5 (WKE-600): rewards the client is holding that belong to an earlier week.
-- Blizzard's own frame puts its PreviousRewardNotification up on exactly this
-- reading - `HasAvailableRewards()` true and `AreRewardsForCurrentRewardPeriod()`
-- false (WeeklyRewardsMixin:UpdatePreviousClaim) - and the tab had no way to
-- say it at all. Said and not acted on: what happens to them is the client's
-- business, and nothing here claims to know it.
Panel.PREVIOUS_PERIOD_NOTE = "The rewards waiting in the vault are from an earlier week, not this one."
-- V-3 (WKE-587): the FOURTH reading of the same empty list, and the one the
-- owner read as a lie. Minutes after he claimed the Enigmatic Dreamwatcher's
-- Leggings on 2026-09-15 the tab told him the vault had not generated this
-- week's rewards; it had generated nine, and he was wearing one of them. The
-- live read cannot tell "nothing yet" from "all taken" - both answer
-- `CanClaimRewards` false, `HasAvailableRewards` false and an empty reward list,
-- and the client's documented six functions (Ketho's
-- WeeklyRewardsDocumentation.lua) carry no "claimed this period" read;
-- `AreRewardsForCurrentRewardPeriod()` is about rewards the client is holding,
-- which after a claim there are none of, so it is not that read either and is
-- not guessed at here. What tells them apart is the addon's own memory: a vault
-- snapshot taken inside THIS reward period that carried reward links
-- (`Panel.ClaimedThisPeriod`). No deadline is written and no "before reset" -
-- the countdown is the client's own `secondsUntilWeeklyReset`, said as the next
-- vault's opening rather than this one's ending (principle 9).
Panel.CLAIMED_REWARDS_NOTE = "You've taken this week's reward. The next vault opens in %s."
Panel.CLAIMED_REWARDS_NOTE_NO_CLOCK = "You've taken this week's reward."
-- M3-16 (WKE-557): the SAME empty list, for the opposite reason. When
-- `HasAvailableRewards()` is true the vault HAS generated rewards and the
-- client simply did not answer with them - after the week's first progress
-- `GetActivities()` drops last week's unclaimed ones until something interacts
-- with the vault (ARCHITECTURE.md §9). Until this issue the tab printed the
-- sentence above at that moment, which is the one thing that is not true, so
-- the two cases are told apart by the client's own `HasAvailableRewards` and
-- the remedy is named rather than left to be guessed at.
Panel.WITHHELD_REWARDS_NOTE = "The client says vault rewards are waiting but did not answer with them. "
    .. "Run /lootpath refresh: it asks for them the way the Great Vault window does."
-- M3-16b (WKE-583): the SAME empty list again, for a third reason, and the one
-- the sentence above was wrong about on reset day. `HasAvailableRewards()` true
-- with `HasGeneratedRewards()` FALSE is a vault the client has not been given
-- this week's rewards for at all, and `/lootpath refresh` cannot fetch them:
-- measured on 2026-09-15, the refresh asked, `WEEKLY_REWARDS_UPDATE` came back
-- in 113.2 ms, and the read after it was the read before it - 10 activities, 0
-- reward links. The owner then opened the Great Vault window and the very next
-- capture carried 11 activities, 5 with rewards and 9 links. So the remedy
-- named here is the window, because the window is what generated them, and the
-- addon does not get a second exception to try to do it without one
-- (ARCHITECTURE.md 7, 2026-09-15).
Panel.OPEN_VAULT_NOTE = "This week's vault rewards have not been generated yet. "
    .. "Open the Great Vault, then refresh: opening it is what makes the client fetch them."
Panel.NO_VERDICT_NOTE = "No import yet, so no option carries a value. Paste a Top Gear export to change that."
Panel.STALE_NOTE = "This export predates this week's vault reset, so it does not know these options. Re-export it."

-- A reset week, in seconds. Used only to place an export before or after the
-- most recent reset; the client's own GetSecondsUntilWeeklyReset supplies the
-- boundary, so nothing here assumes when reset day is.
Panel.WEEK_SECONDS = 7 * 24 * 60 * 60

-- Local time minus UTC, from the client's own clock: time() is now, and
-- time(date("!*t")) reads the current UTC wall clock as if it were local, so
-- the difference is the offset. Any DST edge is at most an hour, and the only
-- comparison made with it is against a week boundary.
local function utcOffsetSeconds()
    local okUTC, utc = pcall(date, "!*t")
    if not okUTC or type(utc) ~= "table" then
        return 0
    end
    utc.isdst = false
    local okLocal, asLocal = pcall(time, utc)
    if not okLocal or type(asLocal) ~= "number" then
        return 0
    end
    return time() - asLocal
end

-- QE Live's exportedAt is an ISO 8601 UTC stamp ("2026-09-06T21:14:24Z" in the
-- committed export). Returns the epoch second, or nil for anything else - a
-- stamp this cannot read produces no staleness claim rather than a wrong one.
function Panel.EpochFromISO(text)
    if type(text) ~= "string" then
        return nil
    end
    local y, mo, d, h, mi, s = text:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
    local year, month, day = tonumber(y), tonumber(mo), tonumber(d)
    if not (year and month and day) then
        return nil
    end
    local ok, epoch = pcall(time, {
        year = year,
        month = month,
        day = day,
        hour = tonumber(h),
        min = tonumber(mi),
        sec = tonumber(s),
        isdst = false,
    })
    if not ok or type(epoch) ~= "number" then
        return nil
    end
    return epoch + utcOffsetSeconds()
end

-- true when the verdict was exported before the most recent weekly reset, false
-- when it was exported after it, nil when there is not enough to say. The
-- boundary is the client's: nextReset = now + secondsUntilWeeklyReset, and the
-- reset before it is one week earlier.
function Panel.IsVerdictStale(exportedAt, nowEpoch, secondsUntilWeeklyReset)
    local exported = Panel.EpochFromISO(exportedAt)
    local seconds = tonumber(secondsUntilWeeklyReset)
    local now = tonumber(nowEpoch)
    if not exported or not seconds or not now then
        return nil
    end
    return exported < (now + seconds - Panel.WEEK_SECONDS)
end

-- true when this week's vault reward has been claimed (V-3, WKE-587).
--
-- The live read alone cannot say so: an emptied vault and a vault that never
-- filled answer identically. The evidence is one of the addon's own stored vault
-- snapshots - taken inside the reward period the client is in now, and carrying
-- reward links. The client refuses a claim, says nothing is waiting, and a
-- snapshot from this same period saw rewards: the rewards left, and the only way
-- they leave is the player taking them.
--
-- The period boundary is the one `IsVerdictStale` uses, from the same client
-- fact: nextReset = now + secondsUntilWeeklyReset, and this period began a week
-- before that. Anything missing - no clock, no snapshots, a caller that passed
-- `false` to read nothing - answers false, so a missing fact never produces the
-- claim.
function Panel.ClaimedThisPeriod(vault, captures, nowEpoch)
    if type(vault) ~= "table" then
        return false
    end
    if vault.canClaimRewards == true or vault.hasAvailableRewards == true then
        return false
    end
    local seconds = tonumber(vault.secondsUntilWeeklyReset)
    local now = tonumber(nowEpoch)
    if not seconds or not now then
        return false
    end
    local periodStart = now + seconds - Panel.WEEK_SECONDS
    if captures == nil then
        local db = ns.db
        captures = db and db.global and db.global.captures and db.global.captures.vault or nil
    end
    if type(captures) ~= "table" then
        return false
    end
    for index = #captures, 1, -1 do
        local snapshot = captures[index]
        local at = type(snapshot) == "table" and tonumber(snapshot.capturedAt) or nil
        if at and at >= periodStart and #Panel.SnapshotRewardLinks(snapshot) > 0 then
            return true
        end
    end
    return false
end

-- The claimed sentence, with the client's countdown when the client gave one.
function Panel.ClaimedNote(secondsUntilWeeklyReset)
    local countdown = ns.Roads and ns.Roads.CountdownText and ns.Roads.CountdownText(secondsUntilWeeklyReset)
    if not countdown then
        return Panel.CLAIMED_REWARDS_NOTE_NO_CLOCK
    end
    return string.format(Panel.CLAIMED_REWARDS_NOTE, countdown)
end

local function progressText(option)
    local text = string.format("%d/%d", option.progress or 0, option.threshold or 0)
    if (option.level or 0) > 0 then
        text = text .. string.format(" (level %d)", option.level)
    end
    return text
end

-- A FrameXML global's value, or nil when this client does not have it. Every
-- word this panel takes from the client goes through here, so a build that has
-- dropped a global loses a word rather than rendering its NAME.
local function globalString(name)
    local value = type(name) == "string" and _G[name] or nil
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end
Panel.GlobalString = globalString

-- The row's name in the game's words: the client's own global first (M5-4 -
-- RAIDS, DUNGEONS, WORLD, the three Blizzard's own vault frame passes to
-- SetUpActivity), then the label measured off the owner's vault screen, then
-- the module's own for every threshold type this panel does not translate
-- (Concession, Ranked PvP, Also receive) - which is honest: those rows are not
-- on the owner's vault screen under another name.
function Panel.RowLabel(option)
    local activityType = option and option.type
    if activityType ~= nil and ns.Vault then
        for name, label in pairs(Panel.ROW_LABEL_BY_ENUM) do
            if ns.Vault.ThresholdType(name) == activityType then
                return globalString(Panel.ROW_GLOBAL[name]) or label
            end
        end
    end
    return (option and option.typeLabel) or "Unknown"
end

-- The heading of one grid row, whether or not the client listed any option
-- under it. Same two sources in the same order as RowLabel.
function Panel.GridRowLabel(enumName)
    return globalString(Panel.ROW_GLOBAL[enumName]) or Panel.ROW_LABEL_BY_ENUM[enumName] or tostring(enumName)
end

-- Blizzard's own threshold sentence for a row with no reward on it, or nil
-- when this client has neither the activity's `raidString` nor the global.
-- Formatted with the threshold exactly as `WeeklyRewardsActivityMixin:Refresh`
-- formats it, inside a pcall: a pattern this addon did not write must not be
-- able to throw the panel.
function Panel.ThresholdText(option, enumName)
    if type(option) ~= "table" then
        return nil
    end
    local pattern
    if enumName == "Raid" and type(option.raidString) == "string" and option.raidString ~= "" then
        pattern = option.raidString
    end
    pattern = pattern or globalString(Panel.THRESHOLD_GLOBAL[enumName])
    if not pattern then
        return nil
    end
    local ok, text = pcall(string.format, pattern, option.threshold or 0)
    if not ok or type(text) ~= "string" then
        return nil
    end
    return text
end

-- V-5 (WKE-600). The fraction in a locked cell's corner, in the client's own
-- fraction string when it has one. Blizzard formats exactly these two figures
-- with exactly this global (`WeeklyRewardsActivityMixin:SetProgressText`, the
-- `GENERIC_FRACTION_STRING` branch); a client without it gets plain figures,
-- which is the same two numbers and no third one.
function Panel.FractionText(option)
    if type(option) ~= "table" then
        return nil
    end
    local progress, threshold = option.progress or 0, option.threshold or 0
    local pattern = globalString(Panel.FRACTION_GLOBAL)
    if pattern then
        local ok, text = pcall(string.format, pattern, progress, threshold)
        if ok and type(text) == "string" then
            return text
        end
    end
    return string.format(Panel.FRACTION_FALLBACK, progress, threshold)
end

-- The difficulty's own name for a level the client reports, through Blizzard's
-- own DifficultyUtil - which is what its vault frame asks for a Raids row. A
-- client without the helper, or one that answers nothing for this level, gets
-- no name rather than a difficulty this addon named itself.
local function difficultyName(level)
    if type(DifficultyUtil) ~= "table" or type(DifficultyUtil.GetDifficultyName) ~= "function" then
        return nil
    end
    local ok, name = pcall(DifficultyUtil.GetDifficultyName, level)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

-- True when the client says this activity's tier is the Heroic dungeon one.
-- Blizzard asks the same question the same way and for the same reason: in the
-- activity data a Heroic week and a Mythic week are BOTH level 0, and only the
-- difficulty ID tells them apart (WeeklyRewardsUtil's own comment under
-- `.luals/`). Unknown answers false, and false only costs the cell a word.
local function isHeroicTier(option)
    local difficultyID = type(option) == "table" and option.difficultyID or nil
    if difficultyID == nil or type(DifficultyUtil) ~= "table" or type(DifficultyUtil.ID) ~= "table" then
        return false
    end
    return difficultyID == DifficultyUtil.ID.DungeonHeroic
end

-- What an unlocked cell says in place of the fraction, per row, exactly as
-- `WeeklyRewardsActivityMixin:SetProgressText` chooses it. nil whenever the
-- client cannot say it: a cell with no level text is still a cell with the
-- tick and the threshold sentence on it.
function Panel.UnlockedLevelText(option, enumName)
    if type(option) ~= "table" then
        return nil
    end
    local level = tonumber(option.level) or 0
    if enumName == "Raid" then
        return difficultyName(level)
    elseif enumName == "Activities" then
        if isHeroicTier(option) then
            return globalString(Panel.LEVEL_GLOBAL.heroic)
        end
        local pattern = globalString(Panel.LEVEL_GLOBAL.mythic)
        if not pattern then
            return nil
        end
        local ok, text = pcall(string.format, pattern, level)
        return (ok and type(text) == "string") and text or nil
    elseif enumName == "World" then
        local pattern = globalString(Panel.LEVEL_GLOBAL.world)
        if not pattern then
            return nil
        end
        local ok, text = pcall(string.format, pattern, level)
        return (ok and type(text) == "string") and text or nil
    end
    return nil
end

-- The phrase naming which QE Live upgrade assumptions produced a number, or nil
-- when the verdict does not say. Reads the two booleans the companion records
-- and nothing else; it never infers a setting from a level difference.
function Panel.SettingsPhrase(qeSettings)
    if type(qeSettings) ~= "table" then
        return nil
    end
    local vault, all = qeSettings.autoUpgradeVault, qeSettings.autoUpgradeAll
    if type(vault) ~= "boolean" or type(all) ~= "boolean" then
        return nil
    end
    if vault and all then
        return Panel.SETTINGS_PHRASE.both
    end
    if vault then
        return Panel.SETTINGS_PHRASE.vault
    end
    if all then
        return Panel.SETTINGS_PHRASE.all
    end
    return Panel.SETTINGS_PHRASE.neither
end

-- What goes in the brackets after a gear option's name: the client's item level,
-- and QE Live's beside it whenever the two disagree. Nothing is computed from
-- the pair - no difference, no preference, no "real" level. A pending reward
-- has no client level yet and says so; QE Live's own level for the exact key
-- is still his fact and is still shown beside it.
function Panel.LevelText(clientLevel, qeLevel, qeSettings, pending)
    local text
    if type(clientLevel) == "number" then
        text = tostring(clientLevel)
    elseif pending then
        text = Panel.PENDING_LEVEL_TEXT
    else
        text = "level unknown"
    end
    if type(qeLevel) ~= "number" or qeLevel == clientLevel then
        return text
    end
    local phrase = Panel.SettingsPhrase(qeSettings)
    text = text .. "; " .. string.format(Panel.QE_LEVEL_TEXT, qeLevel)
    if phrase then
        text = text .. " " .. phrase
    end
    return text
end

-- The newest stored vault snapshot's name for an itemDBID, or nil. Walks
-- `db.global.captures.vault` newest first and takes the first snapshot whose
-- probe of that itemDBID's link carried a name (`item.info[1]`, GetItemInfo's
-- first return, as Captures.lua recorded it). The itemDBID is the vault's own
-- identity for the reward and is what the same reward carries all week, so a
-- match is the same reward and not the same item ID on another week's vault.
--
-- M3-16 (WKE-557): a snapshot that asked the client for the rewards carries
-- two reads - the top-level lists are the BEFORE one and `interact.after` the
-- one taken once `WEEKLY_REWARDS_UPDATE` fired. The after list is the answer
-- when it is there; the before list is what every snapshot to date has, and is
-- what a snapshot whose wait timed out still has. Neither is merged into the
-- other: `Panel.SnapshotRewardLinks` is the one place that chooses.
function Panel.SnapshotRewardLinks(snapshot)
    local data = type(snapshot) == "table" and snapshot.data or nil
    if type(data) ~= "table" then
        return {}
    end
    local interact = type(data.interact) == "table" and data.interact or nil
    local after = interact and type(interact.after) == "table" and interact.after or nil
    if after and type(after.rewardLinks) == "table" then
        return after.rewardLinks
    end
    return type(data.rewardLinks) == "table" and data.rewardLinks or {}
end

function Panel.NameFromCaptures(itemDBID, captures)
    if itemDBID == nil then
        return nil
    end
    if captures == nil then
        local db = ns.db
        captures = db and db.global and db.global.captures and db.global.captures.vault or nil
    end
    if type(captures) ~= "table" then
        return nil
    end
    for index = #captures, 1, -1 do
        local snapshot = captures[index]
        for _, entry in ipairs(Panel.SnapshotRewardLinks(snapshot)) do
            if entry.itemDBID == itemDBID then
                local info = type(entry.item) == "table" and entry.item.info or nil
                local name = type(info) == "table" and info[1] or nil
                if type(name) == "string" and name ~= "" then
                    return name, snapshot.capturedAtLocal or snapshot.capturedAt
                end
            end
        end
    end
    return nil
end

-- The words a reward is shown under. A resolved reward is its client name; a
-- pending one is the last capture's name for it, labelled, or "name pending
-- (item N)". Never the link - a pending link prints as `[]` - and never nil.
function Panel.RewardName(reward, captures)
    if type(reward) ~= "table" then
        return "item ?"
    end
    if reward.pending then
        local fromCapture = reward.nameFromCapture
        if fromCapture == nil and captures ~= false then
            fromCapture = Panel.NameFromCaptures(reward.itemDBID, captures)
        end
        if type(fromCapture) == "string" and fromCapture ~= "" then
            return string.format(Panel.FROM_CAPTURE_TEXT, fromCapture)
        end
        return string.format(Panel.PENDING_NAME_TEXT, tostring(reward.itemID or "?"))
    end
    if type(reward.name) == "string" and reward.name ~= "" then
        return reward.name
    end
    if ns.Vault and ns.Vault.LinkName and ns.Vault.LinkName(reward.link) then
        return reward.link
    end
    return "item " .. tostring(reward.itemID)
end

local function rewardName(reward)
    return reward.displayName or Panel.RewardName(reward)
end

-- Lower sorts better, and every number in it is QE Live's. Ranks are only ever
-- compared with each other; none of them is shown.
local function coverageRank(coverage)
    if not coverage then
        return math.huge
    end
    if coverage.where == "topSet" then
        return -math.huge
    end
    return ns.QEImport.AlternativeRank(coverage)
end

-- The scenarios this panel has answers for, as { verdict, scenario } (C-6,
-- WKE-540). `opts.scenarios` is what ns.UI.ActiveVerdictScenarios hands over; a
-- caller with only one verdict - a test, or a panel built without the window
-- around it - gets that verdict under whichever scenario it names, which for a
-- paste and for everything written before C-6 is `asOffered`.
function Panel.ScenarioList(opts)
    local given = opts and opts.scenarios
    if type(given) == "table" and #given > 0 then
        return given
    end
    if opts and opts.verdict then
        return { { verdict = opts.verdict, scenario = ns.QEImport.ScenarioKey(opts.verdict) } }
    end
    return {}
end

-- Which scenario the highlight follows: the owner's setting when there is an
-- answer stored for it, `asOffered` when there is not, and whatever there IS
-- when even that is missing. Returns the name and whether it fell back, because
-- a highlight that quietly answered a different question would be the exact
-- thing this feature exists to stop.
function Panel.HighlightScenario(scenarios, wanted)
    local have = {}
    for _, entry in ipairs(scenarios or {}) do
        have[entry.scenario] = true
    end
    if type(wanted) == "string" and have[wanted] then
        return wanted, false
    end
    local fellBack = type(wanted) == "string"
    if have[ns.QEImport.DEFAULT_SCENARIO] then
        return ns.QEImport.DEFAULT_SCENARIO, fellBack and wanted ~= ns.QEImport.DEFAULT_SCENARIO
    end
    local first = scenarios and scenarios[1] or nil
    if first then
        return first.scenario, fellBack and wanted ~= first.scenario
    end
    return nil, false
end

-- The name a scenario is shown under. An unknown name is shown as itself rather
-- than translated into one of the three: a document filed under a name this
-- build does not know is exactly the thing not to relabel.
function Panel.ScenarioLabel(scenario)
    return Panel.SCENARIO_LABEL[scenario] or tostring(scenario)
end

-- The same name in the headline's first line, which supplies "this week" itself.
function Panel.ScenarioHeadlineLabel(scenario)
    return Panel.SCENARIO_HEADLINE_LABEL[scenario] or Panel.ScenarioLabel(scenario)
end

-- Did the run behind this verdict have QE Live's Catalyst box on? Read off the
-- `qeSettings` the companion recorded (C-5/C-6), never guessed from the scenario
-- name: the name is a label, the setting is what QE Live was actually asked.
-- nil when the file does not say, and then nothing is claimed either way.
local function askedToCatalyze(verdict)
    local settings = type(verdict) == "table" and verdict.qeSettings or nil
    if type(settings) ~= "table" or type(settings.autoCatalyze) ~= "boolean" then
        return nil
    end
    return settings.autoCatalyze
end

-- What QE Live said about one gear option under one scenario: the option itself
-- by the exact key, or his own catalyzed copy of it, whichever he ranked higher.
-- Nothing here is computed - both are lookups into his export, and the choice
-- between them is his own ordering through coverageRank.
function Panel.ScenarioCoverage(verdict, reward)
    local direct = reward.key and ns.QEImport.Coverage(verdict, reward.key) or nil
    local catalyzed = ns.QEImport.CatalyzedCoverage(verdict, {
        itemID = reward.itemID,
        slot = reward.slot,
        bonusIDs = ns.BonusIDsFromKey(reward.key),
    })
    if catalyzed and coverageRank(catalyzed) < coverageRank(direct) then
        return catalyzed, true, catalyzed
    end
    return direct, false, catalyzed
end

-- One line, in QE Live's words and numbers, under the scenario's name.
function Panel.ScenarioLine(entry, reward)
    local coverage, viaCatalyst, catalyzed = Panel.ScenarioCoverage(entry.verdict, reward)
    if not coverage then
        return nil
    end
    local label = Panel.ScenarioLabel(entry.scenario) .. (viaCatalyst and Panel.CATALYZED_SUFFIX or "")
    return {
        scenario = entry.scenario,
        label = label,
        coverage = coverage,
        viaCatalyst = viaCatalyst,
        -- His catalyze box was on and his run produced no tier copy of this
        -- item, which is `Item.canBeCatalyzed()` answering no. That is HIS
        -- answer, read off the absence in his own output rather than restated
        -- from his rules - and it is read off `qeSettings`, the boxes the
        -- companion recorded, never inferred from the scenario's name.
        notCatalyzed = not catalyzed and askedToCatalyze(entry.verdict) == true,
        text = ns.UpgradeMapPanel.ValueText(coverage, label),
    }
end

-- How many of the thing a scenario assumed the player has, as the client says
-- it. Three answers and no fourth: the number - with the client's own maximum
-- after it when there is one, "you have 1 of 8" - "unknown" when nobody has
-- captured the currency list yet or no currency is configured, and - for the
-- Catalyst alone - "not readable" when the ID probe answered nothing for it.
-- M3-11 is what made that last phrase mean something: before it, "not readable"
-- meant "the currency tab did not list it", and the tab decides that by which
-- headers are expanded. There is no arithmetic here and no cost table anywhere
-- in this file - "1 of 8" is two client numbers side by side, and the cost of a
-- transform is not one of them.
local function catalystCount(currencies, ok)
    if not ok or not currencies.catalystKnown then
        return Panel.COUNT_UNKNOWN
    end
    if currencies.catalystCharges == nil then
        return Panel.CATALYST_NOT_READABLE
    end
    if currencies.catalystMax then
        return string.format(Panel.HAVE_OF_TEXT, tostring(currencies.catalystCharges), tostring(currencies.catalystMax))
    end
    return string.format(Panel.HAVE_TEXT, tostring(currencies.catalystCharges))
end

local function crestCount(currencies, ok)
    if not ok or not currencies.crestsKnown then
        return Panel.COUNT_UNKNOWN
    end
    local parts = {}
    for _, crest in ipairs(currencies.crests or {}) do
        parts[#parts + 1] = string.format("%s %s", crest.name, tostring(crest.quantity))
    end
    if #parts == 0 then
        return Panel.CRESTS_NONE
    end
    return string.format(Panel.HAVE_TEXT, table.concat(parts, ", "))
end

function Panel.CountText(scenario, currencies)
    local ok = type(currencies) == "table" and currencies.ok == true
    local counted = type(currencies) == "table" and currencies or {}
    local parts = Panel.NEEDS_PARTS[scenario]
    if not parts then
        return ""
    end
    local out = {}
    for _, part in ipairs(parts) do
        out[#out + 1] = part == "catalyst" and catalystCount(counted, ok) or crestCount(counted, ok)
    end
    return table.concat(out, " ")
end

-- The fixed phrase naming what a scenario assumed, with the client's count
-- after each half of it, or nil for a scenario that assumed nothing.
function Panel.NeedsText(scenario, currencies)
    local parts = Panel.NEEDS_PARTS[scenario]
    if not parts then
        return nil
    end
    local ok = type(currencies) == "table" and currencies.ok == true
    local counted = type(currencies) == "table" and currencies or {}
    local out = {}
    for index, part in ipairs(parts) do
        local count = part == "catalyst" and catalystCount(counted, ok) or crestCount(counted, ok)
        local phrase = index == 1 and Panel.NEEDS_TEXT[part] or Panel.NEEDS_ALSO_TEXT[part]
        out[#out + 1] = phrase .. count
    end
    return table.concat(out, " and ")
end

-- One conversion said in words. Four shapes and no fifth: the item his clone was
-- made FROM, named with the level the client reports for it, or the slot alone
-- when nothing the panel could see matched the clone - each of those for an item
-- the owner owns and for one the vault is offering. `entry` is the shape
-- ns.QEImport.CatalyzedOwned, CatalyzedVault and OneChargeCandidates all carry:
-- `{ item, slot, owned, fromVault }`.
--
-- It is never filled in with a guess at which of the owner's shoulders he meant:
-- he did not say, so neither does this.
local function conversionText(entry)
    local slot = type(entry.slot) == "string" and entry.slot:lower() or Panel.CATALYZE_OWNED_SLOT_UNKNOWN
    local from = entry.owned
    local named = type(from) == "table" and type(from.name) == "string" and from.name ~= ""
    if entry.fromVault == true then
        if named then
            return string.format(Panel.CATALYZE_VAULT_TEXT, from.name, tostring(from.itemLevel), slot)
        end
        return string.format(Panel.CATALYZE_VAULT_UNKNOWN, slot)
    end
    if named then
        return string.format(Panel.CATALYZE_OWNED_TEXT, from.name, tostring(from.itemLevel), slot)
    end
    return string.format(Panel.CATALYZE_OWNED_UNKNOWN, slot)
end

-- The words for the conversions a scenario's best set spends its charges on, or
-- nil when there are none. `found` is ns.QEImport.CatalyzedOwned's list and
-- `vaultFound` ns.QEImport.CatalyzedVault's, said in that order and in one
-- sentence because they are one set: a best set that catalyzes two things says
-- both, and dropping either would be reporting half of what he said - leaving
-- the vault half out would let one sentence describe a two-charge set as though
-- it cost one charge (M3-15, WKE-556).
function Panel.CatalyzeText(found, vaultFound)
    local parts = {}
    for _, list in ipairs({ found or {}, vaultFound or {} }) do
        for _, entry in ipairs(type(list) == "table" and list or {}) do
            parts[#parts + 1] = conversionText(entry)
        end
    end
    if #parts == 0 then
        return nil
    end
    return Panel.CATALYZE_OWNED_LEAD .. table.concat(parts, " and ")
end

-- The one clone a candidate set spends its charge on, in the same four shapes,
-- so the fifth line and the fourth name an item the same way.
local function oneChargeItemText(catalyzed)
    return conversionText(catalyzed)
end

-- The fifth headline line (M3-14, WKE-555): `candidates` is
-- ns.QEImport.OneChargeCandidates' answer over the `thisWeek` document, best
-- first. The first of them is the line; an empty list is the honest absence.
--
-- The magnitude is printed through math.abs and the direction word is the fixed
-- phrase "behind", because every candidate here is a set QE Live ranked BELOW
-- his top set by construction - the top set is the only one that can be level
-- with itself, and it says "in your best set" instead. Nothing decides a
-- direction by looking at the sign of his number; QEImport's own constant did
-- that when it ordered the list.
function Panel.OneChargeLine(candidates)
    local best = type(candidates) == "table" and candidates[1] or nil
    if not best then
        return {
            kind = "oneCharge",
            text = Panel.ONE_CHARGE_LABEL .. ": " .. Panel.ONE_CHARGE_NONE,
        }
    end
    local standing = best.where == "topSet" and Panel.ONE_CHARGE_IN_BEST_SET
        or string.format(Panel.ONE_CHARGE_BEHIND, math.abs(tonumber(best.scorePercent) or 0))
    return {
        kind = "oneCharge",
        candidate = best,
        text = Panel.ONE_CHARGE_LABEL
            .. ": "
            .. Panel.ONE_CHARGE_LEAD
            .. oneChargeItemText(best.catalyzed)
            .. " - "
            .. standing,
    }
end

-- One line of the headline block: what QE Live picked under this scenario, and
-- what that answer assumed. `pick` is { reward, coverage, viaCatalyst } - the
-- best-ranked thing he said about any option in this vault under this scenario,
-- by his own ordering - and `headlinePick` is the reward the block leads with,
-- so the item is named only when the two differ. `catalyzeOwned` is
-- ns.QEImport.CatalyzedOwned's answer for this scenario's own document, said as
-- a step after the assumption it belongs to, and `catalyzeVault` is
-- ns.QEImport.CatalyzedVault's answer for the same set: the rewards this vault
-- is offering that his set converts, which cost a charge each (M3-15, WKE-556).
function Panel.HeadlineLine(scenario, pick, headlinePick, currencies, catalyzeOwned, catalyzeVault)
    local label = Panel.ScenarioLabel(scenario) .. ((pick and pick.viaCatalyst) and Panel.CATALYZED_SUFFIX or "")
    local owned = Panel.CatalyzeText(catalyzeOwned, catalyzeVault)
    local ownedSuffix = owned and (" - " .. owned) or ""
    if not pick then
        return {
            scenario = scenario,
            catalyzeOwned = catalyzeOwned,
            catalyzeVault = catalyzeVault,
            text = label .. ": " .. Panel.SCENARIO_SILENT .. ownedSuffix,
        }
    end
    local coverage = pick.coverage
    local answer, names
    if coverage.where == "topSet" then
        answer, names = Panel.IN_BEST_SET, true
    elseif coverage.isBetter == true then
        -- Not reachable from a Top Gear export as QE Live builds one (an
        -- alternative is the set he did NOT pick), but the sign convention is
        -- read from him rather than assumed here, so if he ever says it his
        -- own words are shown instead of a phrase that would contradict them.
        answer, names = ns.UpgradeMapPanel.ValueText(coverage), true
    else
        answer, names = Panel.NOTHING_BEATS, false
    end
    local prefix = ""
    if names and headlinePick ~= nil and pick.reward ~= headlinePick then
        prefix = string.format(Panel.INSTEAD_TEXT, rewardName(pick.reward))
    end
    local needs = Panel.NeedsText(scenario, currencies)
    return {
        scenario = scenario,
        reward = pick.reward,
        coverage = coverage,
        viaCatalyst = pick.viaCatalyst,
        catalyzeOwned = catalyzeOwned,
        catalyzeVault = catalyzeVault,
        text = label .. ": " .. prefix .. answer .. (needs and (" - " .. needs) or "") .. ownedSuffix,
    }
end

-- Where on the Great Vault screen the pick sits: the row's own name and its
-- index within that row, the same two words the row header uses. Not its
-- progress - after a reset the client zeroes that while the reward is sitting
-- there claimable (finding 2, WKE-538), and "Dungeons 0/1" beside a pick would
-- read as a reason not to take it.
local function pickWhere(reward)
    if type(reward) ~= "table" or not reward.rowLabel then
        return nil
    end
    if reward.rowIndex then
        return string.format("%s %d", reward.rowLabel, reward.rowIndex)
    end
    return reward.rowLabel
end

-- The block's first line: QE Live's pick under the scenario the owner asked
-- for, and which row of the Great Vault screen it is sitting on.
function Panel.HeadlineText(scenario, pick, coverage)
    local label = Panel.ScenarioHeadlineLabel(scenario)
    if not pick then
        return string.format(Panel.HEADLINE_NO_PICK, label)
    end
    local where = pickWhere(pick)
    local suffix = where and string.format(Panel.HEADLINE_WHERE, where) or ""
    if type(coverage) == "table" and coverage.where ~= "topSet" and coverage.isBetter ~= true then
        return string.format(Panel.HEADLINE_CLOSEST, label, rewardName(pick)) .. suffix
    end
    return string.format(Panel.HEADLINE_TEXT, label, rewardName(pick)) .. suffix
end

-- Which of QE Live's two tones one of his answers is drawn in (M5-1's
-- palette, his own two colours and no third). His top set and anything he
-- called better are "better"; anything else he ranked is "worse"; an option he
-- did not rank at all has no tone of his and takes the panels' grey.
function Panel.VerdictTone(coverage)
    if type(coverage) ~= "table" then
        return "none"
    end
    if coverage.where == "topSet" or coverage.isBetter == true then
        return "better"
    end
    return "worse"
end

-- The tag words a cell carries, in QE Live's own vocabulary (M5-1's TAG
-- table). Exactly one thing is said and it is read off HIS output: when the
-- answer on this cell is about his catalyzed copy of the option rather than
-- the option the vault hands over, the cell says Catalyst and Tier. Nothing
-- else is tagged - every option here is a vault option, so a "Vault" tag on
-- all nine of them would say nothing.
function Panel.CellTags(line)
    if type(line) == "table" and line.viaCatalyst then
        return { "catalyst", "tier" }
    end
    return {}
end

-- One cell of the grid, as plain data. `option` is a model option, `enumName`
-- its row's Blizzard enum name, `highlight` the scenario the pick follows, and
-- `state` the one fact about the WEEK a single cell cannot see: `claiming`,
-- the client's own `CanClaimRewards`.
--
-- A cell with a gear reward draws that reward as an M5-1 item line and says
-- ONE verdict line - the highlighted scenario's, the same string
-- `Panel.ScenarioLine` put on the option below - with every scenario's line
-- kept in `tooltipLines` for the hover. A cell with no gear reward is locked
-- and says what the client says it needs.
--
-- V-5 (WKE-600): every cell also carries the four things Blizzard's own cell
-- draws, decided the way `WeeklyRewardsActivityMixin:Refresh` decides them and
-- not a pixel further. `state` is one of locked / unlocked / reward; `atlas`
-- is the background that state wears; `tick` is the CompletedIcon; and
-- `cornerText` is the fraction on a locked cell and the level on an unlocked
-- one.
--
-- There is deliberately no CLAIMED cell state. Two things settled that, both
-- read rather than assumed: Blizzard's own activity mixin has no claimed
-- branch - after `ClaimReward` it hides the whole window instead of repainting
-- one - and a claimed week, by V-3's own definition, is a week whose live
-- option list carries no rewards at all, so there is no cell holding a reward
-- for such a treatment to land on. A claimed week draws nine honest live cells
-- and says what happened in the one line under the grid.
function Panel.Cell(option, enumName, highlight, state)
    state = state or {}
    local cell = {
        index = option.index,
        id = option.id,
        type = option.type,
        threshold = option.threshold,
        progress = option.progress,
        progressText = option.progressText,
        unlocked = option.unlocked == true,
        claimable = option.claimable == true,
        extrasText = option.extrasText,
    }
    local reward = option.rewards and option.rewards[1] or nil
    -- Blizzard's own one line, copied as a line: `self.unlocked or
    -- self.hasRewards` picks the unlocked art, and everything else is locked.
    local hasRewards = reward ~= nil
    cell.unlockedArt = cell.unlocked or hasRewards
    cell.atlas = cell.unlockedArt and Panel.CELL_ATLAS.unlocked or Panel.CELL_ATLAS.locked
    cell.tick = cell.unlockedArt
    -- And its own progress line: nothing on a cell that holds a reward, the
    -- level on an unlocked one, the fraction otherwise - except while the
    -- client says rewards can be claimed, when Blizzard prints no progress on
    -- the incomplete activities at all, and neither does this.
    if hasRewards then
        cell.cornerText = nil
    elseif cell.unlocked then
        cell.levelText = Panel.UnlockedLevelText(option, enumName)
        cell.cornerText = cell.levelText
    elseif state.claiming ~= true then
        cell.cornerText = Panel.FractionText(option)
    end
    if not reward then
        cell.kind = "locked"
        cell.state = cell.unlocked and "unlocked" or "locked"
        cell.thresholdText = Panel.ThresholdText(option, enumName)
        cell.text = cell.thresholdText or option.progressText
        return cell
    end
    cell.kind = "reward"
    cell.state = "reward"
    cell.reward = reward
    cell.pending = reward.pending == true
    cell.name = reward.displayName or Panel.RewardName(reward)
    cell.item = {
        itemID = reward.itemID,
        link = reward.link,
        name = cell.name,
        quality = reward.quality,
        itemLevel = reward.itemLevel,
        icon = reward.icon,
    }
    -- The grey line under the name: what slot it is and what level it is, in
    -- M3-7's own words - the client's number, and QE Live's beside it whenever
    -- the two disagree, with the setting that produced his.
    local parts = {}
    if type(reward.slot) == "string" and reward.slot ~= "" then
        parts[#parts + 1] = reward.slot
    end
    parts[#parts + 1] = reward.levelText
    cell.second = table.concat(parts, Panel.CELL_SECOND_SEPARATOR)
    local highlighted
    for _, line in ipairs(reward.scenarioLines or {}) do
        if line.scenario == highlight then
            highlighted = line
        end
    end
    cell.scenarioLine = highlighted
    cell.verdictText = highlighted and highlighted.text or Panel.CELL_NO_VERDICT_TEXT
    cell.verdictTone = Panel.VerdictTone(highlighted and highlighted.coverage or nil)
    cell.tags = Panel.CellTags(highlighted)
    -- Exactly the strings the text panel indents under this option, so the
    -- hover and `Panel.Lines` can never say different things about one item.
    cell.tooltipLines = reward.verdictLines or {}
    local footer = {}
    if cell.claimable then
        footer[#footer + 1] = Panel.CLAIMABLE_TEXT
    elseif cell.unlocked then
        footer[#footer + 1] = Panel.UNLOCKED_TEXT
    end
    if #cell.tooltipLines > 1 then
        footer[#footer + 1] = Panel.CELL_HOVER_TEXT
    end
    cell.footer = table.concat(footer, Panel.CELL_SECOND_SEPARATOR)
    local more = #option.rewards - 1
    if more > 0 then
        cell.moreText = string.format(Panel.CELL_MORE_TEXT, more)
    end
    return cell
end

-- The grid: three rows of three cells, in Blizzard's order, plus every option
-- the client listed outside them. `best` is the reward the pick highlight
-- follows and `closest` says the headline called it the closest rather than a
-- pick, so exactly one cell is marked and it is marked the way the first line
-- of the block already reads.
function Panel.Grid(model, highlight, best, closest)
    local placed, rows = {}, {}
    -- The one fact about the week a cell cannot see for itself.
    local state = { claiming = model.canClaimRewards == true }
    for _, enumName in ipairs(Panel.ROW_ORDER) do
        local activityType = ns.Vault and ns.Vault.ThresholdType(enumName) or nil
        local row = {
            key = enumName,
            type = activityType,
            label = Panel.GridRowLabel(enumName),
            -- Blizzard's own art for this row, when this build still has it.
            atlas = Panel.ROW_ATLAS[enumName],
            cells = {},
        }
        for index = 1, Panel.ROW_CELLS do
            row.cells[index] = { index = index, kind = "empty" }
        end
        for _, option in ipairs(model.options or {}) do
            local slot = tonumber(option.index)
            if
                activityType ~= nil
                and option.type == activityType
                and slot
                and slot >= 1
                and slot <= Panel.ROW_CELLS
                and row.cells[slot].kind == "empty"
            then
                local cell = Panel.Cell(option, enumName, highlight, state)
                if best ~= nil and cell.reward == best then
                    cell.selected = not closest
                    cell.closest = closest and true or false
                    cell.label = closest and Panel.CLOSEST_LABEL or Panel.PICK_LABEL
                end
                row.cells[slot] = cell
                placed[option] = true
            end
        end
        rows[#rows + 1] = row
    end
    local other = {}
    for _, option in ipairs(model.options or {}) do
        if not placed[option] and ((#option.rewards > 0) or (#option.extras > 0)) then
            other[#other + 1] = option
        end
    end
    local otherText
    if #other > 0 then
        local names = {}
        for _, option in ipairs(other) do
            -- The header AND what the row hands over: a Concession row that is
            -- only ever a Mythic Keystone must still say so, or the grid has
            -- quietly dropped something the client offered.
            names[#names + 1] = option.headerText .. (option.extrasText and (" " .. option.extrasText) or "")
        end
        otherText = string.format(Panel.OTHER_OPTIONS_TEXT, table.concat(names, "; "))
    end
    return { rows = rows, other = other, otherText = otherText }
end

-- The currency strip: one chip per currency a scenario above assumed, with the
-- client's own name, the client's own icon file ID and the client's own count.
-- Empty whenever nothing has read the currencies yet, because a strip of
-- question marks says less than no strip at all - the scenario lines already
-- carry `Panel.COUNT_UNKNOWN` in words.
function Panel.CurrencyChips(currencies)
    if not (type(currencies) == "table" and currencies.ok == true) then
        return {}
    end
    local chips = {}
    local function add(key, record, count)
        local name = type(record.name) == "string" and record.name ~= "" and record.name
            or string.format(Panel.CURRENCY_UNNAMED, tostring(record.currencyID or "?"))
        chips[#chips + 1] = {
            key = key,
            currencyID = record.currencyID,
            name = name,
            icon = record.iconFileID,
            count = count,
            text = name .. " " .. count,
        }
    end
    local catalyst = currencies.catalyst
    if type(catalyst) == "table" and catalyst.quantity ~= nil then
        local count = tostring(catalyst.quantity)
        if catalyst.maxQuantity then
            count = string.format(Panel.CURRENCY_OF_TEXT, count, tostring(catalyst.maxQuantity))
        end
        add("catalyst", catalyst, count)
    end
    for _, crest in ipairs(currencies.crests or {}) do
        add("crest", crest, tostring(crest.quantity))
    end
    return chips
end

-- Model(opts) -> the panel as plain data.
--
-- opts.vault       ns.Vault.Options()'s result
-- opts.verdict     ns.QEImport.Current()
-- opts.currencies  ns.Currencies.Read()'s result; only the headline block reads
--                  it, and only to say how many of a thing the player has
-- opts.now         epoch second (default time()); only used for the stale note
-- opts.captures    the stored vault snapshots a pending reward's name may be
--                  read from (default: db.global.captures.vault; `false` reads
--                  nothing) - M3-12
-- opts.inventory   ns.Inventory.Scan()'s result, read ONLY to name the item a
--                  scenario's best set catalyzed out of the owner's own bags
--                  (M3-13). Nothing on this tab is valued from it.
--
-- A rewarded row is split in two on the way in. `rewards` are the gear options
-- - the things this panel is for - and only they are counted, valued and
-- eligible for the highlight. `extras` are everything the client hands over in
-- the same rewards list that is not gear: measured 2026-09-08, every rewarded
-- activity also carries a Mythic Keystone (180653, INVTYPE_NON_EQUIP_IGNORE,
-- GetDetailedItemLevelInfo = 1) and row 217 a Thalassian Token of Merit as
-- well. The module records them as it must; showing "Mythic Keystone (1)" beside
-- a 305 weapon reads as an item level, so they are named in words on the gear's
-- own line and given no level and never a value.
--
-- Each gear option is built as a unit the C-6 scenarios (WKE-540) can grow into:
-- `text` is the name, the level and any extras fragment, and `verdictLines` is a
-- list of QE Live's lines below it that can lengthen without moving anything.
function Panel.Model(opts)
    opts = opts or {}
    local vault = opts.vault or {}
    -- The scenarios are the answers; `verdict` is still the one the rest of the
    -- panel reads for the level text, the settings phrase and the staleness
    -- check, and it is the highlight's own document rather than a fourth choice.
    local scenarios = Panel.ScenarioList(opts)
    local highlight, highlightFellBack = Panel.HighlightScenario(scenarios, opts.highlightScenario)
    local verdict = opts.verdict
    for _, entry in ipairs(scenarios) do
        if entry.scenario == highlight then
            verdict = entry.verdict
        end
    end
    local qeSettings = type(verdict) == "table" and verdict.qeSettings or nil
    local model = {
        ok = vault.ok == true,
        reason = vault.reason,
        hasVerdict = verdict ~= nil,
        hasAvailableRewards = vault.hasAvailableRewards == true,
        canClaimRewards = vault.canClaimRewards == true,
        -- M3-16b (WKE-583): the third state, and the one the tab used to tell
        -- the player the wrong thing about. See Panel.OPEN_VAULT_NOTE.
        hasGeneratedRewards = vault.hasGeneratedRewards == true,
        -- V-5 (WKE-600): the client's own answer, kept as the client gave it.
        -- nil is a client that does not have the read and is not false.
        currentRewardPeriod = vault.currentRewardPeriod,
        qeSettings = qeSettings,
        -- C-8 (WKE-558): which items the highlighted scenario's own Top Gear
        -- run was never shown. Per scenario and not per file, because the
        -- Catalyst passes have clones to leave out that the base pass never
        -- had, and the tab's whole subject is what the Catalyst would do.
        --
        -- Per RUN and not per document since C-11a (WKE-586): the highlighted
        -- verdict is pass 1, and what pass 1 could not fit is what its later
        -- passes were shown. The Equip Now tab takes its number from the same
        -- `ns.Companion.Unrated`, so the two headers cannot disagree.
        excluded = ns.Companion and ns.Companion.Unrated(verdict) or nil,
        -- C-12 (WKE-577): what the companion's last run did not ask, in its own
        -- words. File-level, not per scenario - it is about the run - and it is
        -- carried onto every Top Gear verdict the file wrote.
        scenarioNote = type(verdict) == "table" and verdict.scenarioNote or nil,
        scenarios = scenarios,
        highlightScenario = highlight,
        highlightFellBack = highlightFellBack == true,
        options = {},
        counts = { options = 0, rewards = 0, extras = 0, covered = 0, pending = 0, scenarios = #scenarios },
    }
    -- `false` means "do not read the database": a headless caller hands the
    -- snapshots in, and a panel with no database shows "name pending".
    local captures = opts.captures
    if highlightFellBack then
        model.highlightNote = string.format(
            Panel.HIGHLIGHT_FALLBACK_NOTE,
            Panel.ScenarioLabel(opts.highlightScenario),
            Panel.ScenarioLabel(highlight)
        )
    end

    local best, bestRank
    for _, option in ipairs(vault.options or {}) do
        local rewards, extras = {}, {}
        for _, reward in ipairs(option.rewards or {}) do
            -- A pending reward is not known yet, and "not known yet" is never
            -- "not gear": the slot GetItemInfoInstant gives (static data, it
            -- answered on every pending reward measured 2026-09-09) decides
            -- as usual, and a pending reward the client has said nothing about
            -- at all stays with the gear rather than vanishing into the
            -- extras, because its key is known and may be valued.
            local isGear = reward.slot ~= nil or (reward.pending == true and reward.equipLoc == nil)
            if reward.pending then
                model.counts.pending = model.counts.pending + 1
            end
            local displayName = Panel.RewardName(reward, captures)
            if not isGear then
                -- Not gear: no equippable slot, so no item level worth showing
                -- and nothing QE Live could have ranked. A reward whose link
                -- never arrived lands here too, and is named by whatever it has.
                local extra = {
                    itemID = reward.itemID,
                    itemDBID = reward.itemDBID,
                    link = reward.link,
                    name = reward.name,
                    pending = reward.pending == true,
                    displayName = displayName,
                    icon = reward.icon,
                    quality = reward.quality,
                }
                extra.text = "+ " .. displayName
                extras[#extras + 1] = extra
                model.counts.extras = model.counts.extras + 1
            else
                -- The highlight scenario's answer, and QE Live's own catalyzed
                -- copy of the option counts as an answer about it: under his
                -- `catalyzed` run the 308 shoulders the vault offers are in the
                -- top set as the tier piece, and reporting only the exact key
                -- would answer the owner's Catalyst question with the shoulders
                -- he did not catalyze.
                local coverage, viaCatalyst = Panel.ScenarioCoverage(verdict, reward)
                local qeItem = coverage and coverage.item or nil
                local row = {
                    itemID = reward.itemID,
                    itemDBID = reward.itemDBID,
                    key = reward.key,
                    link = reward.link,
                    name = reward.name,
                    pending = reward.pending == true,
                    displayName = displayName,
                    itemLevel = reward.itemLevel,
                    slot = reward.slot,
                    -- What the drawn cell needs and the text list never did
                    -- (M5-4): the client's own icon file ID and quality, off
                    -- the vault record M5-1 put them on. Neither is read for
                    -- anything but drawing, and neither is ever guessed.
                    icon = reward.icon,
                    quality = reward.quality,
                    -- QE Live's own assumed level for this exact item, carried
                    -- beside the client's rather than instead of it.
                    qeLevel = qeItem and tonumber(qeItem.level) or nil,
                    -- The only path to a number on a vault row: nil `qe` means nil
                    -- `value`, and there is no other assignment to `value` here.
                    qe = coverage,
                    qeViaCatalyst = viaCatalyst,
                    value = coverage and ns.UpgradeMapPanel.ValueText(coverage) or nil,
                }
                row.levelText = Panel.LevelText(row.itemLevel, row.qeLevel, qeSettings, row.pending)
                rewards[#rewards + 1] = row
                model.counts.rewards = model.counts.rewards + 1
                if coverage then
                    model.counts.covered = model.counts.covered + 1
                    local rank = coverageRank(coverage)
                    if not best or rank < bestRank then
                        best, bestRank = row, rank
                    end
                end
            end
        end
        local extrasText
        for _, extra in ipairs(extras) do
            extrasText = extrasText and (extrasText .. " " .. extra.text) or extra.text
        end
        -- A row the client has generated a reward for is a row the owner can
        -- collect from, whatever `progress` says (finding 2, WKE-538).
        local claimable = (#rewards + #extras) > 0
        local entry = {
            type = option.type,
            typeLabel = option.typeLabel,
            rowLabel = Panel.RowLabel(option),
            index = option.index,
            id = option.id,
            threshold = option.threshold,
            progress = option.progress,
            level = option.level,
            -- The client's own threshold sentence for this row, carried so a
            -- locked cell can say what Blizzard's own vault says (M5-4).
            raidString = option.raidString,
            -- V-5 (WKE-600): the client's own difficulty for this activity's
            -- tier, carried so an unlocked Dungeons cell can say Heroic or
            -- Mythic the way Blizzard's own cell does. In the activity data
            -- both are level 0; only this tells them apart.
            difficultyID = option.difficultyID,
            unlocked = option.unlocked == true,
            claimable = claimable,
            progressText = progressText(option),
            rewards = rewards,
            extras = extras,
            extrasText = extrasText,
        }
        local suffix = ""
        if claimable then
            suffix = " - " .. Panel.CLAIMABLE_TEXT
        elseif entry.unlocked then
            suffix = " - " .. Panel.UNLOCKED_TEXT
        end
        entry.headerText = string.format("%s %d: %s%s", entry.rowLabel, entry.index or 0, entry.progressText, suffix)
        model.options[#model.options + 1] = entry
        model.counts.options = model.counts.options + 1
    end

    if best then
        best.best = true
        model.best = best
    end

    -- Every scenario's own pick, by QE Live's own ordering over the answers he
    -- gave under it. Built out of the lines already on the rows below, so the
    -- headline block and the option list can never disagree about what he said.
    local bestByScenario = {}

    -- The extras fragment rides on the first gear option of its row, so name,
    -- level and "+ Mythic Keystone" stay one unit; a row with extras and no gear
    -- keeps the fragment on a line of its own rather than losing it.
    for _, option in ipairs(model.options) do
        for index, reward in ipairs(option.rewards) do
            -- Which row of the Great Vault screen this option sits on, carried
            -- onto the reward so the headline can point at it without walking
            -- back up to the option.
            reward.rowLabel = option.rowLabel
            reward.rowIndex = option.index
            local text
            if reward.pending then
                -- "name pending (item 275547) - level pending", in the note
                -- colour, so an option the client has not described yet reads
                -- as waiting rather than as a nameless thing at no level.
                text = Panel.NOTE_COLOR .. rewardName(reward) .. " - " .. reward.levelText .. "|r"
            else
                text = string.format("%s (%s)", rewardName(reward), reward.levelText)
            end
            if index == 1 and option.extrasText then
                text = text .. " " .. option.extrasText
            end
            if reward.best then
                text = text .. string.format(Panel.PICK_TEXT, Panel.ScenarioLabel(model.highlightScenario))
            end
            reward.text = text
            -- One line per scenario that has something to say about THIS option,
            -- in the order they are asked. A scenario whose document does not
            -- mention it at all is silent rather than adding a row that says
            -- nothing; when no scenario mentions it, the option keeps its item
            -- level and no verdict, exactly as before C-6.
            reward.scenarioLines = {}
            local saidNotCatalyzed = false
            for _, entry in ipairs(scenarios) do
                local line = Panel.ScenarioLine(entry, reward)
                if line then
                    -- Said once per option, on the first catalyze-on line that
                    -- has to say it: repeating "he made no tier version" under
                    -- every scenario would bury the answer it sits next to.
                    if line.notCatalyzed and not saidNotCatalyzed then
                        line.text = line.text .. " (" .. Panel.NOT_CATALYZED_TEXT .. ")"
                        saidNotCatalyzed = true
                    end
                    reward.scenarioLines[#reward.scenarioLines + 1] = line
                end
            end
            reward.verdictLines = {}
            for _, line in ipairs(reward.scenarioLines) do
                reward.verdictLines[#reward.verdictLines + 1] = line.text
                local rank = coverageRank(line.coverage)
                local current = bestByScenario[line.scenario]
                if not current or rank < current.rank then
                    bestByScenario[line.scenario] = {
                        reward = reward,
                        coverage = line.coverage,
                        viaCatalyst = line.viaCatalyst,
                        rank = rank,
                    }
                end
            end
        end
    end

    -- Whether this week's reward has already been taken (V-3, WKE-587). Settled
    -- here, after the options are counted and before anything reads it: an empty
    -- vault is the only vault this question is ever asked about, and both the
    -- note above the grid and the plan sentence's vault clause turn on it.
    model.claimed = model.counts.rewards == 0
        and model.counts.extras == 0
        and Panel.ClaimedThisPeriod(vault, captures, opts.now or time())

    -- The headline block. Only when there is something to head: a verdict, a
    -- vault that could be read, and at least one gear option on it - or a vault
    -- whose option WAS taken, which still has this week's plan to read out
    -- (V-3). Everything else on the tab already says why there is not.
    if model.hasVerdict and #scenarios > 0 and (model.counts.rewards > 0 or model.claimed) then
        local pick = model.best
        -- A claimed vault has no option to lead with and no scenario to compare
        -- (V-3, WKE-587): the block is the plan and nothing else. The note above
        -- the grid already says the reward is taken, and "no option in this vault
        -- is in the answer" about nine empty cells would be a second, worse way
        -- of saying it. The charge footnote the scenario lines would have carried
        -- is the plan sentence's own footnote, so nothing is lost with them.
        local planOnly = model.counts.rewards == 0
        local headlineCoverage = bestByScenario[highlight] and bestByScenario[highlight].coverage or nil
        -- The same test `Panel.HeadlineText` makes, kept beside it rather than
        -- made twice in two places: when the best he said under the highlighted
        -- scenario is still "worse than your set", the first line refuses to
        -- call it a pick, and the cell below must refuse in the same breath.
        local closest = type(headlineCoverage) == "table"
            and headlineCoverage.where ~= "topSet"
            and headlineCoverage.isBetter ~= true
        model.headline = {
            scenario = highlight,
            pick = pick,
            -- The week's plan, first, in the words a guildmate would type
            -- (principle 16, R-3/WKE-564). It is `ns.Roads.PlanSentence` over
            -- exactly the answer this block is already about - the same
            -- scenarios, the same highlight, the same scan and the same vault -
            -- so the sentence and the lines under it cannot describe two
            -- different weeks. Nothing below it moves.
            plan = ns.Roads.PlanSentence({
                verdicts = scenarios,
                highlightedScenario = highlight,
                inventory = opts.inventory,
                vault = vault,
                currencies = opts.currencies,
                -- So a plan drawn under a fallback scenario says why the one on
                -- the label is missing, rather than reading as this week's plan
                -- (C-12, WKE-577).
                scenarioNote = model.scenarioNote,
                -- V-3 (WKE-587): so the sentence does not send him back to a
                -- vault he has already emptied.
                vaultClaimed = model.claimed,
            }),
            closest = closest and true or false,
            text = Panel.HeadlineText(highlight, pick, headlineCoverage),
            lines = {},
        }
        if planOnly then
            model.headline.text = nil
            model.headline.pick = nil
            model.headline.planOnly = true
        end
        local thisWeekVerdict
        for _, entry in ipairs(planOnly and {} or scenarios) do
            local catalyzeOwned = ns.QEImport.CatalyzedOwned(entry.verdict, opts.inventory)
            local catalyzeVault = ns.QEImport.CatalyzedVault(entry.verdict, vault)
            model.headline.lines[#model.headline.lines + 1] = Panel.HeadlineLine(
                entry.scenario,
                bestByScenario[entry.scenario],
                pick,
                opts.currencies,
                catalyzeOwned,
                catalyzeVault
            )
            -- The fifth line is about the fourth question's own document, and
            -- only arises because that document's best set spends MORE THAN ONE
            -- charge - on the owner's items, on the vault's, or on both, because
            -- the Catalyst does not care whose an item is (M3-15, WKE-556). A
            -- `thisWeek` answer that catalyzes nothing has no charge question
            -- hanging over it, so it gets no line - not even the absence one,
            -- which would be a sentence about a problem the owner does not have.
            if entry.scenario == Panel.ONE_CHARGE_SCENARIO and #catalyzeOwned + #catalyzeVault > 0 then
                thisWeekVerdict = entry.verdict
            end
        end
        -- With no such document stored, or with the Catalyst box off in the run
        -- that produced it, or with no inventory scan to join to, the guards in
        -- CatalyzedOwned above have already emptied that list, so the line is
        -- left off rather than reporting an absence nobody looked for.
        if thisWeekVerdict then
            model.headline.oneCharge =
                Panel.OneChargeLine(ns.QEImport.OneChargeCandidates(thisWeekVerdict, opts.inventory, vault))
            model.headline.lines[#model.headline.lines + 1] = model.headline.oneCharge
        end
    end

    -- The vault drawn as the vault (M5-4). Built last, out of the options and
    -- the headline that are already settled, so the grid is a second view of
    -- the same answer and never a second answer.
    model.grid = Panel.Grid(model, highlight, model.best, model.headline and model.headline.closest)
    model.currencyChips = Panel.CurrencyChips(opts.currencies)

    if model.counts.rewards == 0 and model.counts.extras == 0 then
        if model.hasAvailableRewards and not model.hasGeneratedRewards then
            model.rewardsNote = Panel.OPEN_VAULT_NOTE
        elseif model.hasAvailableRewards then
            model.rewardsNote = Panel.WITHHELD_REWARDS_NOTE
        elseif model.claimed then
            -- V-3 (WKE-587). Ahead of NO_REWARDS_NOTE because an emptied vault
            -- reads as an ungenerated one to the live API, and the addon's own
            -- snapshots are the only thing that tells them apart.
            model.rewardsNote = Panel.ClaimedNote(vault.secondsUntilWeeklyReset)
        else
            model.rewardsNote = Panel.NO_REWARDS_NOTE
        end
    end
    -- V-5 (WKE-600): rewards are waiting and the client says they are not this
    -- week's. Said whether or not there are options on the grid, because it is
    -- about WHICH week the waiting rewards belong to and not about how many
    -- there are - which is also when Blizzard's own frame shows its notice.
    if model.hasAvailableRewards and model.currentRewardPeriod == false then
        model.previousPeriodNote = Panel.PREVIOUS_PERIOD_NOTE
    end
    if model.counts.pending > 0 then
        model.pendingNote = string.format(Panel.PENDING_NOTE, model.counts.pending)
    end
    if not model.hasVerdict then
        model.verdictNote = Panel.NO_VERDICT_NOTE
    else
        local stale = Panel.IsVerdictStale(verdict.exportedAt, opts.now or time(), vault.secondsUntilWeeklyReset)
        model.stale = stale
        if stale then
            model.staleNote = Panel.STALE_NOTE
        end
        -- The same sentence the Equip Now tab prints, from the same function:
        -- one wording for "this answer is about a subset" (C-8).
        model.excludedNote = ns.Companion and ns.Companion.ExcludedText(model.excluded) or nil
    end
    return model
end

-- The notes the drawn panel prints above the grid: everything `Panel.Lines`
-- says that is not an option. Kept as one function so the text list and the
-- drawn panel cannot drift apart about which notes there are.
function Panel.NoteLines(model)
    local lines = {}
    if not model.ok then
        lines[1] = string.format("The vault could not be read: %s", tostring(model.reason))
        return lines
    end
    if model.verdictNote then
        lines[#lines + 1] = model.verdictNote
    end
    if model.highlightNote then
        lines[#lines + 1] = model.highlightNote
    end
    if model.staleNote then
        lines[#lines + 1] = model.staleNote
    end
    if model.rewardsNote then
        lines[#lines + 1] = model.rewardsNote
    end
    if model.previousPeriodNote then
        lines[#lines + 1] = model.previousPeriodNote
    end
    if model.pendingNote then
        lines[#lines + 1] = Panel.NOTE_COLOR .. model.pendingNote .. "|r"
    end
    -- Last, and in the aside grey: it does not change what the grid says, it
    -- says what the grid is an answer ABOUT (C-8).
    if model.excludedNote then
        lines[#lines + 1] = Panel.NOTE_COLOR .. model.excludedNote .. "|r"
    end
    return lines
end

-- The pinned note is NOT one of these lines: the panel header draws it once,
-- above the list, and until WKE-530 the list printed it again as its first row
-- (seen in game 2026-09-06 on this tab and the Upgrade Map). The model still
-- carries `note` for the headless tests that pin the wording.
--
-- Since M5-4 the drawn tab is a grid rather than this list, and this function
-- is the pure text `/lootpath status` and every text test read: the same
-- notes, the same headline block and the same per-option lines, in the same
-- order. The grid renders the same fields; nothing on screen is built here.
function Panel.Lines(model)
    local lines = Panel.NoteLines(model)
    local function add(text)
        lines[#lines + 1] = text
    end
    if not model.ok then
        return lines
    end
    -- The answer first, the evidence under it (M3-9). The option list below is
    -- unchanged; this block is what the owner reads before scrolling.
    if model.headline then
        local plan = model.headline.plan
        if plan and plan.sentence then
            add(plan.sentence)
            if plan.footnote then
                add("  " .. plan.footnote)
            end
        end
        if model.headline.text then
            add(model.headline.text)
        end
        for _, line in ipairs(model.headline.lines) do
            add("  " .. line.text)
        end
    end
    for _, option in ipairs(model.options) do
        add(option.headerText)
        for _, reward in ipairs(option.rewards) do
            add("  " .. reward.text)
            for _, line in ipairs(reward.verdictLines) do
                add("    " .. line)
            end
        end
        if option.extrasText and #option.rewards == 0 then
            add("  " .. option.extrasText)
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Frames. Native only, no AceGUI (decision 2026-09-05).
--
-- Since M5-4 (WKE-553) the tab is drawn as the vault is drawn: the headline
-- block first, then three rows of three option cells in Blizzard's own order,
-- then the currency strip. Every cell is an M5-1 item line; the pick carries
-- Blizzard's own selected glow when the client still has the atlas; each cell
-- says the highlighted scenario's line and keeps the rest one hover away.
-- `Panel.Lines` is untouched and is still the pure text the tests read.

local ROW_HEIGHT = 14
-- Only a default; the window anchors this panel by two corners, and the default
-- is ns.UI.PANEL_WIDTH, read at Create time. See the same note in
-- UI/UpgradeMapPanel.lua.
local PANEL_HEIGHT = 420
-- The room this panel's scroll frame leaves on its right for the scrollbar. It
-- is already in the scroll frame's own BOTTOMRIGHT anchor below, which is why
-- the scroll frame's width IS the width the grid may use and nothing subtracts
-- it twice (M5-2c, WKE-609).
local SCROLL_INSET = 26

-- The row's own left column: Blizzard's category banner with this row's name
-- over its left edge (V-5a, WKE-607). It used to be 74, a column narrower than
-- it was tall, and the art was given exactly that box - which is the squeeze the
-- owner's screenshot of 2026-09-16 caught. Blizzard's own header frame is
-- 326x131 (WeeklyRewardActivityTypeTemplate, Blizzard_WeeklyRewards.xml), so
-- its art is about two and a half times as wide as it is tall; a box that is
-- 132 wide against this row's 104 is the widest this window can give it and
-- still leave three cells that can be read. The trade the issue asked for is
-- taken here and only here: the cells give way, and they give way in WIDTH.
local ROW_BANNER_WIDTH = 132
-- The air inside the banner. Also where the row's name sits in from the art's
-- left edge, as Blizzard insets its own header Name (TOPLEFT x=28 of a 326-wide
-- header, same file).
local ROW_BANNER_INSET = 8
local CELL_GAP = 8
local CELL_HEIGHT = 104
-- The band at the top of every cell that the "the pick" label lives in. It is
-- reserved on every cell, not only the one that has a label: a label drawn
-- above the cell's top edge sat on the bottom of the row above it on the
-- owner's own screen (R-3a, WKE-570), and a band that appears only when there
-- is a label would move a cell's contents as the pick moves. The height is the
-- label's own font row plus the two points it is inset by.
local LABEL_BAND = 12
-- The tick on an unlocked cell (V-5, WKE-600). One label band square, so the
-- corner band holds the tick and the progress side by side and nothing in the
-- cell below it moves.
local CELL_TICK_SIZE = 12
local GRID_ROW_GAP = 8
-- The four widths above, published for spec/vaultpanel_spec.lua: the guard that
-- the row spends the window's width on its cells has to name them, and naming
-- them a second time in the test would be a second copy of each (M5-2c,
-- WKE-609).
Panel.SCROLL_INSET = SCROLL_INSET
Panel.ROW_BANNER_WIDTH = ROW_BANNER_WIDTH
Panel.ROW_BANNER_INSET = ROW_BANNER_INSET
Panel.CELL_GAP = CELL_GAP

local CELL_ICON_SIZE = 32
local CHIP_ICON_SIZE = 14
local CHIP_GAP = 12
-- M5-2b (WKE-601): the strip of currency chips wraps, so it needs a row height
-- and the air between two rows of its own. The chip frame is the icon plus the
-- two points the text sits inside (the height `chip()` gives it); the gap is
-- this file's own.
local CHIP_ROW_HEIGHT = CHIP_ICON_SIZE + 2
local CHIP_ROW_GAP = 4
-- The points between a chip's icon and its words, and the narrowest a chip is
-- drawn - both were already in the width this file set on a chip before it
-- wrapped, and they are named here because the wrap arithmetic needs them.
local CHIP_TEXT_GAP = 4
local CHIP_MIN_TEXT_WIDTH = 40
-- Headless nothing measures a glyph; a character costs this many points, the
-- same estimate the chip's width used before this issue.
local CHIP_CHAR_WIDTH = 6

-- QE Live's gold as the three numbers a texture tint wants, off the same hex
-- the badge uses. Read from the constant rather than written out again, so the
-- accent has exactly one definition in this addon.
local function toneRGB(hex)
    return ns.UI.ItemLine.RGB(hex)
end

-- A flat 1-pixel texture Blizzard ships and every addon tints; used for the
-- fallback border, and only ever with SetVertexColor over it.
local WHITE_TEXTURE = [[Interface\Buttons\WHITE8X8]]
-- The gap under the plan sentence, which is the only thing above the pick, and
-- roughly how many characters of the headline's large font fit on one line of
-- the panel. Headless there is no font to ask, and a two-sentence plan that
-- wrapped onto the pick would be the one way this block can overlap itself, so
-- the estimate is deliberate and generous rather than absent.
local PLAN_GAP = 6
Panel.PLAN_CHARS_PER_LINE = 56

function Panel.PlanHeight(text, rowHeight)
    if type(text) ~= "string" or text == "" then
        return 0
    end
    return math.max(1, math.ceil(#text / Panel.PLAN_CHARS_PER_LINE)) * rowHeight
end

-- M5-2b (WKE-601): where each currency chip goes, and how many rows they take.
-- The owner's screen on 2026-09-16 read
-- `Venomblight Manaflux 2 of 8 · Adventurer Mistcrest 329 · Veteran Mistcrest
-- 35 · Champio`: the chips were laid left to right on ONE row with nothing
-- measuring them, and the fourth and fifth ran off the panel's right edge. So a
-- chip that would cross that edge starts the next row instead. Nothing under
-- the strip needs the space: the grid is above it and the strip's own height
-- follows.
--
-- Pure, so the wrap is an assertion rather than a hope: `width` is the room the
-- panel has and `measure(chip, index)` answers the width of that chip's words
-- (the client's own GetStringWidth in the drawer below; nil headless, where the
-- character estimate stands in). A width of nothing keeps every chip on one
-- row, which is what this did before the issue.
--
-- Returns { placements, rows, height }: one placement per chip, in the chips'
-- own order, each { index, row (1-based), x, width }.
function Panel.ChipLayout(chips, width, measure)
    chips = chips or {}
    local placements = {}
    local row, x = 1, 0
    for index, data in ipairs(chips) do
        local textWidth
        if type(measure) == "function" then
            local measured = measure(data, index)
            if type(measured) == "number" and measured > 0 then
                textWidth = measured
            end
        end
        textWidth = math.max(CHIP_MIN_TEXT_WIDTH, textWidth or (#tostring(data.text) * CHIP_CHAR_WIDTH))
        local chipWidth = CHIP_ICON_SIZE + CHIP_TEXT_GAP + textWidth
        if x > 0 and type(width) == "number" and width > 0 and (x + chipWidth) > width then
            row = row + 1
            x = 0
        end
        placements[index] = { index = index, row = row, x = x, width = chipWidth }
        x = x + chipWidth + CHIP_GAP
    end
    local rows = #placements > 0 and row or 0
    return {
        placements = placements,
        rows = rows,
        height = rows > 0 and (rows * CHIP_ROW_HEIGHT + (rows - 1) * CHIP_ROW_GAP) or 0,
    }
end

local function colored(hex, text)
    return "|cff" .. hex .. tostring(text) .. "|r"
end

local function toneHex(name)
    local tone = ns.UI and ns.UI.ItemLine and ns.UI.ItemLine.TONE[name] or nil
    return tone and tone.hex or "909296"
end

-- The verdict the window is showing. `ns.UI.ActiveVerdict` honours the content
-- type setting and falls back to the most recent import, saying so in the
-- window's own note (M2-2); reaching past it to QEImport.Current would show a
-- Raid answer under a Dungeon setting with nothing said. The direct call is the
-- fallback for a panel built without the window around it.
local function activeVerdict()
    if ns.UI and ns.UI.ActiveVerdict then
        return (ns.UI.ActiveVerdict())
    end
    return ns.QEImport.Current()
end

-- Every named scenario stored for the content type on screen (C-6). Read
-- through the window for the same reason the verdict is: the content-type
-- setting decides which import a panel shows, and reaching past it would answer
-- a Dungeon setting with a Raid export.
local function activeScenarios()
    if ns.UI and ns.UI.ActiveVerdictScenarios then
        return (ns.UI.ActiveVerdictScenarios())
    end
    return {}
end

local function currentScenario()
    if ns.UI and ns.UI.Options and ns.UI.Options.GetVaultScenario then
        return ns.UI.Options.GetVaultScenario()
    end
    return nil
end

function Panel.Gather(opts)
    opts = opts or {}
    return {
        vault = ns.Vault.Options(),
        verdict = activeVerdict(),
        scenarios = activeScenarios(),
        -- The only client numbers on this tab that are not the vault's own.
        -- Read here rather than inside Model so a headless test drives them.
        currencies = ns.Currencies and ns.Currencies.Read() or nil,
        -- The bags and the bank, for one sentence and nothing else: which item
        -- the owner already has that a scenario's best set catalyzed (M3-13).
        -- Scan refuses in combat and the refusal is simply no sentence.
        inventory = ns.Inventory and ns.Inventory.Scan() or nil,
        highlightScenario = currentScenario(),
        now = opts.now,
    }
end

-- The scenario dropdown, on the tab's own header row (M5-4). It writes through
-- `ns.UI.Options.SetVaultScenario`, which is the one place the setting lives,
-- so the Settings page's copy and this one can never disagree; the labels are
-- the Settings page's own words for the same reason.
--
-- `DropdownButton` with `WowStyle1DropdownTemplate` is the 11.0 menu system
-- (Blizzard_Menu/DropdownButton.lua under .luals/: SetupMenu takes a generator
-- of (dropdown, rootDescription) and rootDescription:CreateRadio takes text, an
-- is-selected predicate and a setter). A client without the template gets no
-- dropdown on the tab and keeps the Settings page's, which is why the whole
-- thing is a pcall and a nil return rather than an error.
Panel.DROPDOWN_TEMPLATE = "WowStyle1DropdownTemplate"
Panel.DROPDOWN_TAG = "MENU_LOOTPATH_VAULT_SCENARIO"
Panel.DROPDOWN_WIDTH = 210
Panel.DROPDOWN_HEIGHT = 22
-- What the control needs beyond the words themselves: its arrow and its two
-- insets. This addon's own allowance, not a read of Blizzard's art, and
-- deliberately generous - the cost of too much is white space and the cost of
-- too little is the cut this issue is about.
Panel.DROPDOWN_PADDING = 40
-- Headless nothing measures a glyph, so a character costs a fixed number of
-- points and a layout test reproduces the width exactly; in the client the
-- control's own font string measures itself, which is the real one. The same
-- pair the Upgrade Map's controls use.
Panel.DROPDOWN_CHAR_WIDTH = 6

-- How wide the scenario dropdown has to be: the longest of the four plain
-- names, plus the arrow and the insets (M5-2b, WKE-601). `measure` is the
-- client's own GetStringWidth when there is a font string to ask; without one,
-- or when it answers nothing, the character estimate stands in.
function Panel.DropdownWidth(measure)
    local widest = 0
    for _, scenario in ipairs(ns.QEImport.SCENARIOS) do
        local label = Panel.ScenarioShortLabel(scenario)
        local width
        if type(measure) == "function" then
            local measured = measure(label)
            if type(measured) == "number" and measured > 0 then
                width = measured
            end
        end
        width = width or (#label * Panel.DROPDOWN_CHAR_WIDTH)
        if width > widest then
            widest = width
        end
    end
    return widest + Panel.DROPDOWN_PADDING
end

function Panel.ScenarioChoiceLabel(scenario)
    local labels = ns.UI and ns.UI.Options and ns.UI.Options.SCENARIO_CHOICE_LABEL or nil
    return (type(labels) == "table" and labels[scenario]) or Panel.ScenarioLabel(scenario)
end

-- The control's own font string, borrowed to measure a label and handed back
-- with the text it was holding (M5-2b, WKE-601). nil when there is nothing to
-- ask - a template with no font string, or a headless widget without the
-- client's own measurement - and then the character estimate stands in.
local function labelMeasure(control)
    local text = type(control.GetFontString) == "function" and control:GetFontString() or nil
    if type(text) ~= "table" or type(text.SetText) ~= "function" or type(text.GetStringWidth) ~= "function" then
        return nil
    end
    return function(label)
        local held = type(text.GetText) == "function" and text:GetText() or nil
        text:SetText(label)
        local ok, width = pcall(text.GetStringWidth, text)
        text:SetText(held)
        return ok and width or nil
    end
end

local function buildScenarioDropdown(frame)
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, frame, Panel.DROPDOWN_TEMPLATE)
    if not ok or type(dropdown) ~= "table" or type(dropdown.SetupMenu) ~= "function" then
        return nil
    end
    dropdown:SetSize(Panel.DropdownWidth(labelMeasure(dropdown)), Panel.DROPDOWN_HEIGHT)
    dropdown:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    -- The words on the closed dropdown. `SetDefaultText` belongs to
    -- DropdownSelectionTextMixin, which WowStyle1DropdownTemplate mixes in
    -- through its own XML (`mixin="WowStyle1DropdownMixin"`,
    -- Blizzard_Menu/Mainline/MenuTemplates.xml:3; MenuTemplates.lua:753
    -- composes that mixin from ButtonStateBehaviorMixin and
    -- DropdownSelectionTextMixin). **The annotations DO record it** - the T-1
    -- audit read it there - so the earlier note here, that they do not, was
    -- wrong; what they do not record is the inheritance in the GENERATED API
    -- documentation, which covers intrinsics and widget classes and not
    -- FrameXML's templates. The pcall stays for the one client this panel must
    -- still work on: a build old enough, or an environment stripped far enough,
    -- that `WowStyle1DropdownTemplate` is not defined at all - there
    -- `CreateFrame` above already returned nil and we never reach here, and if
    -- a future template kept the name but dropped the mixin, a dropdown with no
    -- caption is still a dropdown and the Settings page still carries the
    -- setting. The headless stub cannot paper over either case since T-1: it
    -- gives the caption only to the template whose mixin chain has it.
    pcall(dropdown.SetDefaultText, dropdown, Panel.SCENARIO_DROPDOWN_LABEL)
    -- M5-2b (WKE-601): the words on the closed control are the scenario's SHORT
    -- name. Without this the client writes the SELECTED ROW's own text there -
    -- `DropdownSelectionTextMixin:UpdateToMenuSelections` translates the
    -- selection with `MenuUtil.GetElementText` when no selection function is
    -- set (Blizzard_Menu/MenuTemplates.lua:604-638 under .luals/) - and the
    -- row's text is the Settings page's explaining sentence, which does not fit
    -- and came off the owner's screen as `Everything upgraded (Catalyst and
    -- f...`. `SetSelectionText` (MenuTemplates.lua:591) is the template's own
    -- way to say otherwise: its answer wins over the translation. The menu's
    -- rows are untouched, so the sentence is still one click away.
    --
    -- pcall for the same reason as the line above it: a template that kept the
    -- name and dropped the mixin leaves the caption Blizzard's, which is a long
    -- caption rather than no dropdown.
    pcall(dropdown.SetSelectionText, dropdown, function()
        return Panel.ScenarioShortLabel(currentScenario())
    end)
    dropdown:SetupMenu(function(_, rootDescription)
        if type(rootDescription) ~= "table" or type(rootDescription.CreateRadio) ~= "function" then
            return
        end
        if rootDescription.SetTag then
            rootDescription:SetTag(Panel.DROPDOWN_TAG)
        end
        for _, scenario in ipairs(ns.QEImport.SCENARIOS) do
            rootDescription:CreateRadio(Panel.ScenarioChoiceLabel(scenario), function()
                return currentScenario() == scenario
            end, function()
                if ns.UI and ns.UI.Options and ns.UI.Options.SetVaultScenario then
                    ns.UI.Options.SetVaultScenario(scenario)
                end
            end)
        end
    end)
    return dropdown
end

-- The width the scroll child may use, which is the width of the scroll frame
-- that holds it (M5-2c, WKE-609). Until this issue the content frame was
-- created at a fixed `PANEL_WIDTH - 40` and never resized, so the grid drew
-- itself into 520 points inside a scroll frame that had more - the defect the
-- V-5a agent found on 2026-09-16 and left, because it was sizing and not art.
--
-- The scrollbar's room is already in the scroll frame's own BOTTOMRIGHT anchor,
-- so its width is the usable span and SCROLL_INSET is not taken off it again. A
-- frame sized by anchors answers GetWidth only once the client has laid it out,
-- and headless it never does, so the same arithmetic is done from the panel's
-- own width when the scroll frame has no width to give.
function Panel.ContentWidth(frame)
    local width = frame.scroll and frame.scroll:GetWidth() or 0
    if not width or width <= 0 then
        width = (frame:GetWidth() or 0) - SCROLL_INSET
    end
    return math.max(1, width)
end

function Panel.Create(parent)
    local frame = CreateFrame("Frame", "LootpathVaultPanel", parent or UIParent)
    frame:SetSize(ns.UI.PANEL_WIDTH, PANEL_HEIGHT)
    frame:Hide()

    frame.header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.header:SetJustifyH("LEFT")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetText("Vault")

    frame.scenarioDropdown = buildScenarioDropdown(frame)

    -- No pinned note under the header since V-5 (WKE-600): the legend that sat
    -- here explained a badge that says it itself, and the grid wanted the
    -- height more than the tab wanted the sentence. The scroll starts at the
    -- header.
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -12)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLL_INSET, 4)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(Panel.ContentWidth(frame), PANEL_HEIGHT - 60)
    frame.scroll:SetScrollChild(frame.content)
    frame.rows = {}
    frame.gridRows = {}
    frame.chips = {}

    -- The headline block (M3-9), drawn: the pick's icon, the first line in
    -- GameFontNormalLarge, and one small line per scenario under it, each of
    -- them exactly what `Panel.HeadlineLine` produced.
    local headline = CreateFrame("Frame", nil, frame.content)
    headline:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, 0)
    headline:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
    headline:SetHeight(1)
    -- The week's plan, above everything (R-3): one or two short sentences in
    -- chat voice, then the footnote when a resource is wanted twice. Nothing
    -- below them moved; they were put in front.
    headline.plan = headline:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    headline.plan:SetPoint("TOPLEFT", headline, "TOPLEFT", 0, 0)
    headline.plan:SetPoint("RIGHT", headline, "RIGHT", 0, 0)
    headline.plan:SetJustifyH("LEFT")
    headline.plan:SetWordWrap(true)
    headline.planFootnote = headline:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    headline.planFootnote:SetPoint("TOPLEFT", headline.plan, "BOTTOMLEFT", 0, -2)
    headline.planFootnote:SetPoint("RIGHT", headline, "RIGHT", 0, 0)
    headline.planFootnote:SetJustifyH("LEFT")
    headline.planFootnote:SetWordWrap(true)

    headline.icon = ns.UI.ItemLine.CreateIcon(headline, { size = CELL_ICON_SIZE })
    headline.icon:SetPoint("TOPLEFT", headline, "TOPLEFT", 0, 0)
    headline.text = headline:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    headline.text:SetPoint("TOPLEFT", headline.icon, "TOPRIGHT", 8, -2)
    headline.text:SetPoint("RIGHT", headline, "RIGHT", 0, 0)
    headline.text:SetJustifyH("LEFT")
    headline.text:SetWordWrap(true)
    headline.lines = {}
    frame.headline = headline

    frame.other = frame.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.other:SetJustifyH("LEFT")
    frame.other:SetWordWrap(true)
    frame.other:Hide()

    frame.currencyNote = frame.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.currencyNote:SetJustifyH("LEFT")
    frame.currencyNote:Hide()

    frame.Refresh = Panel.Refresh
    Panel.frame = frame
    return frame
end

local function row(frame, index)
    local text = frame.rows[index]
    if not text then
        text = frame.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetJustifyH("LEFT")
        -- As wide as the frame it wraps inside, rather than a number of its own
        -- (M5-2c, WKE-609).
        text:SetWidth(Panel.ContentWidth(frame))
        text:SetWordWrap(true)
        if index == 1 then
            text:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, 0)
        else
            text:SetPoint("TOPLEFT", frame.rows[index - 1], "BOTTOMLEFT", 0, -2)
        end
        frame.rows[index] = text
    end
    text:Show()
    return text
end

-- One atlas, drawn at its own aspect inside the box it was given (V-5a,
-- WKE-607).
--
-- Blizzard draws every one of these atlases at the size the art was authored:
-- `useAtlasSize = true` in `WeeklyRewardsMixin:SetUpActivity` for the row art
-- and in `WeeklyRewardsActivityMixin:Refresh` for both cell backgrounds
-- (Blizzard_WeeklyRewards.lua under `.luals/`), and `useAtlasSize="true"` on the
-- CompletedIcon and the SelectedTexture of WeeklyRewardActivityTemplate
-- (Blizzard_WeeklyRewards.xml, same folder). That second argument is
-- `TextureBase:SetAtlas(atlas, useAtlasSize, ...)` (Ketho,
-- Core/Widget/Base/TextureBase.lua).
--
-- This window is 760 wide altogether (M5-2c, WKE-609) and Blizzard's boxes are
-- still bigger than anything in it - its activity frame is 219x126 and its row
-- header 326x131 -
-- so art that does not fit at its own size is scaled by ONE factor for both
-- sides. Never two: two factors is the squash, and giving a texture
-- `SetAllPoints` over a cell is two factors. The size is asked of the client
-- (`C_Texture.GetAtlasInfo` through `ns.UI.ItemLine.AtlasInfo`); this addon
-- knows the pixel size of no atlas.
--
-- Returns true when there was art to draw.
local function drawAtlas(texture, name, boxWidth, boxHeight, margin)
    local info = ns.UI.ItemLine.AtlasInfo(name)
    if not info then
        return false
    end
    local inset = margin or 0
    local roomWidth = math.max(1, (boxWidth or 0) - inset * 2)
    local roomHeight = math.max(1, (boxHeight or 0) - inset * 2)
    local width, height = info.width, info.height
    if not width or not height or (width <= roomWidth and height <= roomHeight) then
        -- It fits as it is - or the client will not say how big it is, and its
        -- own size is still the only size this addon may draw it at.
        texture:SetAtlas(info.name, true)
        return true
    end
    local scale = math.min(roomWidth / width, roomHeight / height)
    texture:SetAtlas(info.name)
    texture:SetSize(math.max(1, math.floor(width * scale)), math.max(1, math.floor(height * scale)))
    return true
end

-- One option cell. Its regions are created once and re-bound on every refresh,
-- the way every list in this addon works: a cell that stops being the pick must
-- lose its glow, and a cell that stops holding an item must cancel what that
-- item was waiting for.
local function createCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetHeight(CELL_HEIGHT)
    cell:EnableMouse(true)

    -- The cell's own back. Blizzard's locked/unlocked art when this build has
    -- the atlas (V-5, WKE-600), and the flat dark fill M5-4 drew when it does
    -- not: an atlas that has gone from the client must not leave a cell with
    -- no background at all.
    cell.background = cell:CreateTexture(nil, "BACKGROUND")
    cell.background:SetAllPoints()
    cell.background:SetTexture(WHITE_TEXTURE)
    cell.background:SetVertexColor(0.07, 0.07, 0.08, 0.8)

    -- The tick on an unlocked cell, in Blizzard's own art, in the corner band so
    -- it never sits on the item's name. Blizzard's own CompletedIcon is drawn at
    -- the atlas's size; here it is fitted to the band, at its own aspect.
    cell.tick = cell:CreateTexture(nil, "OVERLAY")
    cell.tick:SetSize(CELL_TICK_SIZE, CELL_TICK_SIZE)
    cell.tick:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -2)
    cell.tick:Hide()

    -- Where Blizzard puts the progress: the cell's own corner. The fraction
    -- while it is locked, the level once it is not, nothing once it holds a
    -- reward. A locked cell has nothing else along its bottom, so there the
    -- fraction goes bottom-right, inside the badge, exactly where Blizzard's
    -- own Progress sits (BOTTOMRIGHT x=-15 y=15 of WeeklyRewardActivityTemplate,
    -- Blizzard_WeeklyRewards.xml); a cell holding a reward keeps it in the top
    -- band, because its footer and its extras own the bottom (V-5a, WKE-607).
    cell.corner = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.corner:SetPoint("TOPRIGHT", cell.tick, "TOPLEFT", -2, 0)
    cell.corner:SetHeight(LABEL_BAND - 2)
    cell.corner:SetJustifyH("RIGHT")
    cell.corner:SetWordWrap(false)
    cell.corner:Hide()

    -- Blizzard's own selected art, when the client still has the atlas. Centred
    -- and at its own aspect like every other atlas here; Blizzard's own
    -- SelectedTexture is anchored CENTER with useAtlasSize too.
    cell.selectedTexture = cell:CreateTexture(nil, "OVERLAY")
    cell.selectedTexture:SetAllPoints()
    cell.selectedTexture:Hide()

    -- The fallback: four tinted edges in QE Live's gold, so a pick is marked on
    -- a client that has dropped the atlas.
    cell.edges = {}
    for index = 1, 4 do
        local edge = cell:CreateTexture(nil, "OVERLAY")
        edge:SetTexture(WHITE_TEXTURE)
        edge:Hide()
        cell.edges[index] = edge
    end
    cell.edges[1]:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
    cell.edges[1]:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
    cell.edges[1]:SetHeight(2)
    cell.edges[2]:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 0, 0)
    cell.edges[2]:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
    cell.edges[2]:SetHeight(2)
    cell.edges[3]:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
    cell.edges[3]:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 0, 0)
    cell.edges[3]:SetWidth(2)
    cell.edges[4]:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
    cell.edges[4]:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
    cell.edges[4]:SetWidth(2)

    -- The transient mark a "Show in vault" leaves (R-3). Its own texture, not
    -- the pick's edges: a cell that is pointed at has not become the pick, and
    -- the mark goes away on its own.
    cell.flash = cell:CreateTexture(nil, "OVERLAY")
    cell.flash:SetAllPoints()
    cell.flash:SetTexture(WHITE_TEXTURE)
    cell.flash:SetVertexColor(1, 0.8745, 0.0784, 0.22)
    cell.flash:Hide()

    -- Inside the cell's own top edge, in the band reserved above the item
    -- line. Anchored TOPLEFT to TOPLEFT so that nothing about this label can
    -- reach a pixel above the cell it belongs to.
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -2)
    cell.label:SetHeight(LABEL_BAND - 2)
    cell.label:SetJustifyH("LEFT")
    cell.label:SetWordWrap(false)
    cell.label:Hide()

    -- The badge column is zero here: a third of a panel is too narrow for a
    -- badge beside the name, so the verdict is its own line underneath, which
    -- is also where Blizzard's own vault cell puts its progress.
    cell.line = ns.UI.ItemLine.Create(cell, { size = CELL_ICON_SIZE, badgeWidth = 0 })
    cell.line:SetPoint("TOPLEFT", cell, "TOPLEFT", 6, -(LABEL_BAND + 6))
    cell.line:SetPoint("RIGHT", cell, "RIGHT", -6, 0)

    cell.tags = cell:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cell.tags:SetPoint("TOPLEFT", cell.line, "BOTTOMLEFT", 0, -2)
    cell.tags:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
    cell.tags:SetJustifyH("LEFT")
    cell.tags:SetWordWrap(false)

    cell.verdict = cell:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cell.verdict:SetPoint("TOPLEFT", cell.tags, "BOTTOMLEFT", 0, -2)
    cell.verdict:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
    cell.verdict:SetJustifyH("LEFT")
    cell.verdict:SetWordWrap(true)

    -- Everything the client hands over on this row that is not gear - the
    -- Mythic Keystone every rewarded activity carries, a Token of Merit - in
    -- the words the text list already gives it (finding 1, WKE-538). It has no
    -- level and never a value; it is here so nothing the vault offers is off
    -- the screen.
    cell.extras = cell:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cell.extras:SetPoint("TOPLEFT", cell.verdict, "BOTTOMLEFT", 0, -2)
    cell.extras:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
    cell.extras:SetJustifyH("LEFT")
    cell.extras:SetWordWrap(false)

    cell.footer = cell:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cell.footer:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 6, 4)
    cell.footer:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
    cell.footer:SetJustifyH("LEFT")
    cell.footer:SetWordWrap(false)

    -- The locked cell's own words, centred, where the item line would be.
    cell.locked = cell:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    -- Inside the badge rather than inside the cell (V-5a, WKE-607): the art is
    -- now drawn at its own size and centred, so a sentence anchored to the cell
    -- would hang off the art it is written on. Anchored to the background it
    -- follows whatever was drawn - and on a client with no atlas the background
    -- still covers the whole cell, which is where this sentence used to be. A
    -- band is left at the top for the corner and one at the bottom for the
    -- fraction, so the sentence shares a line with neither (V-5, WKE-600).
    cell.locked:SetPoint("TOPLEFT", cell.background, "TOPLEFT", 6, -(LABEL_BAND + 4))
    cell.locked:SetPoint("BOTTOMRIGHT", cell.background, "BOTTOMRIGHT", -6, LABEL_BAND + 4)
    cell.locked:SetJustifyH("CENTER")
    cell.locked:SetJustifyV("MIDDLE")
    cell.locked:SetWordWrap(true)
    cell.locked:Hide()

    cell:SetScript("OnEnter", function(self)
        Panel.ShowCellTooltip(self)
    end)
    cell:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return cell
end

-- Every scenario's line for the option in this cell, in the tooltip, built
-- from the same strings `Panel.ScenarioLine` gave the text panel. The item
-- itself is one hover further in - the icon and the name are the item line's
-- own buttons and show the real item tooltip with the shopping compare.
function Panel.ShowCellTooltip(cell)
    local data = cell.data
    if not (GameTooltip and type(data) == "table") then
        return false
    end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetText(data.name or data.text or "", 1, 1, 1, 1, true)
    for _, line in ipairs(data.tooltipLines or {}) do
        GameTooltip:AddLine(line)
    end
    if data.extrasText then
        GameTooltip:AddLine(data.extrasText)
    end
    if data.moreText then
        GameTooltip:AddLine(data.moreText)
    end
    -- The same block Blizzard's own tooltip gets (R-2, WKE-563), through the
    -- same function, so the vault cell and a bag hover cannot say two different
    -- things about one reward. Appended after this cell's own lines, the way
    -- it is appended after the client's.
    Panel.AppendRoads(GameTooltip, data)
    GameTooltip:Show()
    return true
end

-- The item's part of the plan on a vault cell. The key is the reward's own, so
-- nothing is parsed and nothing is read from the client here; the cache is the
-- same one the bag hover reads.
function Panel.AppendRoads(tooltip, data)
    if InCombatLockdown() then
        return false
    end
    local key = type(data) == "table" and data.key or nil
    if type(key) ~= "string" or not (ns.RoadsCache and ns.UI.Tooltip) then
        return false
    end
    local answer = ns.RoadsCache.Lookup(key)
    if not answer then
        return false
    end
    local map = ns.RoadsCache.Map()
    return ns.UI.Tooltip.Append(tooltip, answer, {
        previewMythicPlusLevel = map and map.previewMythicPlusLevel or nil,
    })
end

-- "Show in vault" (R-3, the verb table): the Vault tab, that cell, and a mark
-- on it that fades by itself. Nine cells fit on the tab, so nothing scrolls.
-- The key is the reward's, never its name.
Panel.POINT_SECONDS = 4

function Panel.ShowReward(key)
    if type(key) ~= "string" or key == "" then
        return false
    end
    Panel.pointedAt = key
    if ns.UI and ns.UI.SelectTab then
        ns.UI.SelectTab(ns.UI.frame, ns.UI.VAULT_TAB)
    elseif Panel.frame then
        Panel.Refresh(Panel.frame)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(Panel.POINT_SECONDS, function()
            if Panel.pointedAt == key then
                Panel.pointedAt = nil
                if Panel.frame and Panel.frame:IsShown() then
                    Panel.Refresh(Panel.frame)
                end
            end
        end)
    end
    return true
end

local function gridRow(frame, index)
    local existing = frame.gridRows[index]
    if existing then
        return existing
    end
    local rowFrame = CreateFrame("Frame", nil, frame.content)
    rowFrame:SetHeight(CELL_HEIGHT)
    -- Blizzard's own category art, behind this row's name (V-5, WKE-600). Its
    -- three atlas names are the ones `WeeklyRewardsMixin:OnLoad` passes to
    -- SetUpActivity, asked for at draw time: a build without one shows the
    -- name alone, which is what the tab showed before this issue.
    -- A banner, not a column (V-5a, WKE-607): centred in the row's own left
    -- band, sized at draw time to the art's own aspect, with the row's name over
    -- its left edge the way Blizzard's header carries its Name.
    rowFrame.art = rowFrame:CreateTexture(nil, "BACKGROUND")
    rowFrame.art:SetPoint("CENTER", rowFrame, "LEFT", ROW_BANNER_WIDTH / 2, 0)
    rowFrame.art:Hide()
    rowFrame.label = rowFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rowFrame.label:SetPoint("LEFT", rowFrame.art, "LEFT", ROW_BANNER_INSET, 0)
    rowFrame.label:SetWidth(ROW_BANNER_WIDTH - ROW_BANNER_INSET * 2)
    rowFrame.label:SetJustifyH("LEFT")
    rowFrame.label:SetWordWrap(false)
    rowFrame.cells = {}
    for cellIndex = 1, Panel.ROW_CELLS do
        local cell = createCell(rowFrame)
        if cellIndex == 1 then
            cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", ROW_BANNER_WIDTH, 0)
        else
            cell:SetPoint("TOPLEFT", rowFrame.cells[cellIndex - 1], "TOPRIGHT", CELL_GAP, 0)
        end
        rowFrame.cells[cellIndex] = cell
    end
    frame.gridRows[index] = rowFrame
    return rowFrame
end

local function chip(frame, index)
    local existing = frame.chips[index]
    if existing then
        return existing
    end
    local entry = CreateFrame("Frame", nil, frame.content)
    entry:SetHeight(CHIP_ICON_SIZE + 2)
    entry.icon = entry:CreateTexture(nil, "ARTWORK")
    entry.icon:SetSize(CHIP_ICON_SIZE, CHIP_ICON_SIZE)
    entry.icon:SetPoint("LEFT", entry, "LEFT", 0, 0)
    entry.text = entry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    entry.text:SetPoint("LEFT", entry.icon, "RIGHT", 3, 0)
    entry.text:SetJustifyH("LEFT")
    entry.text:SetWordWrap(false)
    frame.chips[index] = entry
    return entry
end

-- Marks (or unmarks) one cell as the pick. Blizzard's atlas when the client
-- has it, four gold edges when it does not; never nothing.
local function markCell(cell, selected)
    -- Centred and at its own aspect (V-5a, WKE-607), over the badge it marks.
    cell.selectedTexture:ClearAllPoints()
    cell.selectedTexture:SetPoint("CENTER", cell, "CENTER", 0, 0)
    local atlas = selected
        and drawAtlas(cell.selectedTexture, Panel.SELECTED_ATLAS, cell:GetWidth() or 0, CELL_HEIGHT, 0)
    if atlas then
        cell.selectedTexture:Show()
    else
        cell.selectedTexture:Hide()
    end
    local showEdges = selected and not atlas
    local r, g, b = toneRGB(Panel.SELECTED_HEX)
    for _, edge in ipairs(cell.edges) do
        if showEdges then
            edge:SetVertexColor(r, g, b, 1)
            edge:Show()
        else
            edge:Hide()
        end
    end
end

-- The cell's background, its tick and its corner, in Blizzard's own art and by
-- Blizzard's own rule (V-5, WKE-600). Every atlas is asked for first: without
-- it the cell keeps M5-4's flat fill and its words, which is a cell that is
-- plainer rather than a cell that is blank.
local function paintCell(cell, data)
    -- The badge, centred at its own aspect (V-5a, WKE-607). The flat fill still
    -- covers the whole cell, because a cell with no art must not be a hole.
    cell.background:ClearAllPoints()
    cell.background:SetPoint("CENTER", cell, "CENTER", 0, 0)
    local atlas = drawAtlas(cell.background, data.atlas, cell:GetWidth() or 0, CELL_HEIGHT, 0)
    if atlas then
        -- An atlas carries its own colour; the tint the flat fill needed would
        -- darken it to nothing.
        cell.background:SetVertexColor(1, 1, 1, 1)
    else
        cell.background:ClearAllPoints()
        cell.background:SetAllPoints()
        cell.background:SetTexture(WHITE_TEXTURE)
        cell.background:SetVertexColor(0.07, 0.07, 0.08, 0.8)
    end
    local tick = data.tick and drawAtlas(cell.tick, Panel.COMPLETED_ATLAS, CELL_TICK_SIZE, CELL_TICK_SIZE, 0)
    cell.tick:SetShown(tick and true or false)
    -- A locked cell puts the fraction bottom-right inside the badge, as
    -- Blizzard does; a cell with a reward keeps it in the top band, where its
    -- footer and extras are not (V-5a, WKE-607).
    cell.corner:ClearAllPoints()
    if data.kind == "locked" then
        cell.corner:SetPoint("BOTTOMRIGHT", cell.background, "BOTTOMRIGHT", -6, 6)
    else
        cell.corner:SetPoint("TOPRIGHT", cell.tick, "TOPLEFT", -2, 0)
    end
    cell.corner:SetText(data.cornerText or "")
    cell.corner:SetShown(data.cornerText ~= nil)
end

local function bindCell(cell, data, cellWidth)
    cell:SetWidth(cellWidth)
    cell.data = data
    if not data or data.kind == "empty" then
        ns.UI.ItemLine.Clear(cell.line)
        cell:Hide()
        markCell(cell, false)
        cell.tick:Hide()
        cell.corner:Hide()
        return
    end
    cell:Show()
    paintCell(cell, data)
    cell.extras:SetText(data.extrasText or "")
    if data.kind == "locked" then
        ns.UI.ItemLine.Clear(cell.line)
        cell.tags:SetText("")
        cell.verdict:SetText("")
        cell.footer:SetText("")
        cell.locked:SetText(data.text or "")
        cell.locked:Show()
        cell.label:Hide()
        markCell(cell, false)
        return
    end
    cell.locked:Hide()
    ns.UI.ItemLine.Set(cell.line, {
        itemID = data.item.itemID,
        link = data.item.link,
        name = data.item.name,
        quality = data.item.quality,
        itemLevel = data.item.itemLevel,
        icon = data.item.icon,
        second = data.second,
        tags = {},
    })
    cell.tags:SetText(ns.UI.ItemLine.TagText(data.tags))
    cell.verdict:SetText(colored(toneHex(data.verdictTone), data.verdictText))
    cell.footer:SetText(data.footer or "")
    if data.label then
        cell.label:SetText(colored(data.selected and Panel.SELECTED_HEX or toneHex("none"), data.label))
        cell.label:Show()
    else
        cell.label:SetText("")
        cell.label:Hide()
    end
    markCell(cell, data.selected == true)
    -- Pointed at by a "Show in vault" a moment ago. Compared on the item key,
    -- because two rewards of one week can share a name and only the key is
    -- identity.
    cell.flash:SetShown(Panel.pointedAt ~= nil and data.reward ~= nil and data.reward.key == Panel.pointedAt)
end

function Panel.Refresh(self, opts)
    self = self or Panel.frame
    if not self then
        return nil
    end
    local model = Panel.Model(Panel.Gather(opts))
    self.model = model

    -- The scroll child takes its width from the scroll frame that holds it,
    -- every refresh, so a window that has been resized - or laid out for the
    -- first time - gives the grid the whole span (M5-2c, WKE-609). Only the
    -- width: the height is what the layout below works out.
    self.content:SetWidth(Panel.ContentWidth(self))
    local width = math.max(1, self.content:GetWidth())
    local gaps = CELL_GAP * (Panel.ROW_CELLS - 1)
    -- What three cells across are left after the banner. At the width this
    -- content frame now gets on a 760-wide window (a 734-point panel less the
    -- 26 the scrollbar takes = 708) that is (708 - 132 - 16) / 3 = 186 each,
    -- against the 124 it drew at while the content frame was frozen at 520.
    -- The banner keeps the 132 V-5a gave it: the room the window gained goes to
    -- the cells, which is the side V-5a had to squeeze.
    local cellWidth = math.max(60, math.floor((width - ROW_BANNER_WIDTH - gaps) / Panel.ROW_CELLS))

    local lines = Panel.NoteLines(model)
    for i, line in ipairs(lines) do
        row(self, i):SetText(line)
    end
    for i = #lines + 1, #self.rows do
        self.rows[i]:SetText("")
        self.rows[i]:Hide()
    end
    self.lines = lines
    local used = #lines * ROW_HEIGHT

    -- The headline block, under whatever notes there were.
    local headline = self.headline
    headline:ClearAllPoints()
    headline:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
    if #lines > 0 then
        headline:SetPoint("TOPLEFT", self.rows[#lines], "BOTTOMLEFT", 0, -8)
        used = used + 8
    else
        headline:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
    end
    local block = model.headline
    if block then
        headline:Show()
        -- The plan first, then the icon under it. The icon's anchor is set on
        -- every refresh rather than once, because whether there is a sentence
        -- above it is a fact about the week and not about the frame.
        local plan = block.plan or {}
        headline.plan:SetText(plan.sentence or "")
        headline.plan:SetShown(plan.sentence ~= nil)
        headline.planFootnote:SetText(plan.footnote or "")
        headline.planFootnote:SetShown(plan.footnote ~= nil)
        headline.icon:ClearAllPoints()
        if plan.footnote then
            headline.icon:SetPoint("TOPLEFT", headline.planFootnote, "BOTTOMLEFT", 0, -PLAN_GAP)
        elseif plan.sentence then
            headline.icon:SetPoint("TOPLEFT", headline.plan, "BOTTOMLEFT", 0, -PLAN_GAP)
        else
            headline.icon:SetPoint("TOPLEFT", headline, "TOPLEFT", 0, 0)
        end
        if block.pick then
            ns.UI.ItemLine.SetIcon(headline.icon, {
                itemID = block.pick.itemID,
                link = block.pick.link,
                name = block.pick.displayName,
                quality = block.pick.quality,
                itemLevel = block.pick.itemLevel,
                icon = block.pick.icon,
            })
        else
            ns.UI.ItemLine.ClearIcon(headline.icon)
        end
        headline.text:SetText(block.text or "")
        -- A plan-only block (V-3) reserves no icon row: there is no pick line
        -- under the sentence, so the space one would take is not taken.
        local height = block.text and CELL_ICON_SIZE or 0
        for index, line in ipairs(block.lines) do
            local fontString = headline.lines[index]
            if not fontString then
                fontString = headline:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                fontString:SetJustifyH("LEFT")
                fontString:SetWordWrap(true)
                if index == 1 then
                    fontString:SetPoint("TOPLEFT", headline.icon, "BOTTOMLEFT", 0, -4)
                else
                    fontString:SetPoint("TOPLEFT", headline.lines[index - 1], "BOTTOMLEFT", 0, -2)
                end
                fontString:SetPoint("RIGHT", headline, "RIGHT", 0, 0)
                headline.lines[index] = fontString
            end
            fontString:SetText(line.text)
            fontString:Show()
            height = height + ROW_HEIGHT + 2
        end
        for index = #block.lines + 1, #headline.lines do
            headline.lines[index]:SetText("")
            headline.lines[index]:Hide()
        end
        if plan.sentence then
            height = height + Panel.PlanHeight(plan.sentence, ROW_HEIGHT + 4) + PLAN_GAP
        end
        if plan.footnote then
            height = height + Panel.PlanHeight(plan.footnote, ROW_HEIGHT) + 2
        end
        headline:SetHeight(height + 8)
        used = used + height + 8
    else
        headline:Hide()
        ns.UI.ItemLine.ClearIcon(headline.icon)
        headline.plan:SetText("")
        headline.planFootnote:SetText("")
        headline.text:SetText("")
        for _, fontString in ipairs(headline.lines) do
            fontString:SetText("")
            fontString:Hide()
        end
        headline:SetHeight(1)
    end

    -- The grid.
    local anchor, anchorPoint = headline, "BOTTOMLEFT"
    if not block then
        if #lines > 0 then
            anchor, anchorPoint = self.rows[#lines], "BOTTOMLEFT"
        else
            anchor, anchorPoint = self.content, "TOPLEFT"
        end
    end
    local grid = model.grid or { rows = {} }
    for index = 1, #Panel.ROW_ORDER do
        local rowFrame = gridRow(self, index)
        local data = grid.rows[index]
        rowFrame:ClearAllPoints()
        rowFrame:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -GRID_ROW_GAP)
        rowFrame:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
        if data then
            rowFrame:Show()
            rowFrame.label:SetText(data.label)
            -- Blizzard's own art for this row (V-5), as a banner at the art's
            -- own aspect (V-5a), or the name alone. The name hangs off the
            -- art's left edge, so a row with no art anchors it to the row
            -- instead of to a texture that was never given a size.
            local rowArt = drawAtlas(rowFrame.art, data.atlas, ROW_BANNER_WIDTH, CELL_HEIGHT, ROW_BANNER_INSET)
            rowFrame.label:ClearAllPoints()
            if rowArt then
                rowFrame.art:Show()
                rowFrame.label:SetPoint("LEFT", rowFrame.art, "LEFT", ROW_BANNER_INSET, 0)
            else
                rowFrame.art:Hide()
                rowFrame.label:SetPoint("LEFT", rowFrame, "LEFT", ROW_BANNER_INSET, 0)
            end
            for cellIndex, cell in ipairs(rowFrame.cells) do
                bindCell(cell, data.cells[cellIndex], cellWidth)
            end
            used = used + CELL_HEIGHT + GRID_ROW_GAP
            anchor, anchorPoint = rowFrame, "BOTTOMLEFT"
        else
            rowFrame:Hide()
            for _, cell in ipairs(rowFrame.cells) do
                bindCell(cell, nil, cellWidth)
            end
        end
    end

    -- The currency strip, under the grid. Since M5-2b (WKE-601) it wraps: the
    -- chips are given their words first, so the client can measure them, and
    -- Panel.ChipLayout decides which row each one is on.
    local chips = model.currencyChips or {}
    local entries = {}
    for index, data in ipairs(chips) do
        local entry = chip(self, index)
        entry:ClearAllPoints()
        if data.icon then
            entry.icon:SetTexture(data.icon)
            entry.icon:Show()
        else
            entry.icon:Hide()
        end
        entry.text:SetText(data.text)
        entries[index] = entry
    end
    local room = type(self.content.GetWidth) == "function" and self.content:GetWidth() or nil
    local layout = Panel.ChipLayout(chips, room, function(_, index)
        local text = entries[index] and entries[index].text or nil
        if not (text and type(text.GetStringWidth) == "function") then
            return nil
        end
        local ok, measured = pcall(text.GetStringWidth, text)
        return ok and measured or nil
    end)
    for index, entry in ipairs(entries) do
        local place = layout.placements[index]
        entry:SetPoint(
            "TOPLEFT",
            anchor,
            anchorPoint,
            place.x,
            -GRID_ROW_GAP - (place.row - 1) * (CHIP_ROW_HEIGHT + CHIP_ROW_GAP)
        )
        entry:SetWidth(place.width)
        entry:Show()
    end
    for index = #chips + 1, #self.chips do
        self.chips[index]:Hide()
    end
    self.currencyNote:ClearAllPoints()
    self.currencyNote:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -GRID_ROW_GAP)
    if #chips == 0 and model.headline then
        self.currencyNote:SetText(Panel.CURRENCY_NOTE)
        self.currencyNote:Show()
    else
        self.currencyNote:SetText("")
        self.currencyNote:Hide()
    end
    -- The strip's own height is the rows it took (M5-2b); with no chips at all
    -- it is the one row the note sits on, which is what it was before.
    local stripHeight = layout.rows > 0 and layout.height or CHIP_ICON_SIZE
    used = used + stripHeight + GRID_ROW_GAP * 2

    -- Everything the client offers outside the three rows Blizzard draws.
    self.other:ClearAllPoints()
    self.other:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -GRID_ROW_GAP - stripHeight - GRID_ROW_GAP)
    self.other:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
    if grid.otherText then
        self.other:SetText(grid.otherText)
        self.other:Show()
        used = used + ROW_HEIGHT * 2
    else
        self.other:SetText("")
        self.other:Hide()
    end

    self.content:SetHeight(math.max(1, used))
    return model
end
