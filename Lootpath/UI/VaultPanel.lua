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

Panel.NOTE = "Values shown are QE Live's, for options it has ranked. Other options are listed by item level only."

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

-- What the mark on that cell says. The grey one is the `nothing beats your
-- set` case: the closest option is still named, and is still not called a pick
-- on a screen that says there is not one.
Panel.PICK_LABEL = "QE Live's pick"
Panel.CLOSEST_LABEL = "closest"

-- The cell's own last line. A cell whose option has more than one scenario to
-- report says where the rest of them are; the tooltip carries exactly the
-- lines `Panel.ScenarioLine` built, so the cell and the text panel cannot
-- disagree about what QE Live said.
Panel.CELL_HOVER_TEXT = "hover for the other scenarios"
Panel.CELL_NO_VERDICT_TEXT = "not ranked by QE Live in any scenario"
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
Panel.QE_LEVEL_TEXT = "QE Live valued it at %d"

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
-- week" in its own words: "QE Live's pick this week (this week (vault upgraded,
-- Catalyst used))" is what the plain label produced, and a stutter inside nested
-- brackets is not a sentence anyone reads. Only the scenarios that need a
-- shorter form are here; the rest fall through to SCENARIO_LABEL.
Panel.SCENARIO_HEADLINE_LABEL = {
    thisWeek = "vault upgraded, Catalyst used",
}

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

-- Which scenario the "<- QE Live's pick" highlight follows, said on the line, so
-- a pick that came from a what-if is never mistaken for what you have now.
Panel.PICK_TEXT = "  <- QE Live's pick (%s)"

-- ---------------------------------------------------------------------------
-- The headline block (M3-9, WKE-544). The owner's words, 2026-09-08, after the
-- first in-game run of this tab: it "doesn't do a good job of telling me what my
-- top pick is and why - the catalyst example: it should guide me that I would
-- need to get the shoulders, then use the catalyst (which we should know how
-- many charges I have), then upgrade with crests (which we should know how many
-- the player has and what type)".
--
-- So the block leads with QE Live's pick under the scenario the owner asked for,
-- and then lists every scenario he has an answer for, in QE Live's own order,
-- with what that answer assumed and how many of the thing it assumed the player
-- has. Three kinds of words and no others: a QE Live verdict, a client number,
-- and a fixed phrase naming what a scenario assumed. Nothing is computed - not a
-- cost, not a count of upgrades a pile of crests would buy, not a preference
-- between two of his answers.
Panel.HEADLINE_TEXT = "QE Live's pick this week (%s): %s"
Panel.HEADLINE_WHERE = " (%s)"
Panel.HEADLINE_NO_PICK = "QE Live's pick this week (%s): no option in this vault is in his answer"
-- When the best he said about any option under the highlighted scenario is
-- still "worse than your set", it is not a pick, and the first line must not
-- call it one on the same screen that says nothing beats the set.
Panel.HEADLINE_CLOSEST = "QE Live's pick this week (%s): none - nothing in the vault beats your set; closest: %s"

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
Panel.CATALYZE_OWNED_UNKNOWN = "a %s you own (QE Live did not say which)"
Panel.CATALYZE_OWNED_SLOT_UNKNOWN = "item"

-- The same sentence for the other side of the same charge (M3-15, WKE-556). The
-- Catalyst spends a charge on ANY item, a Great Vault reward included, so a best
-- set that converts a reward is spending a charge the line above would otherwise
-- never mention - and the count of charges on screen would understate what he
-- told the owner to do. The words differ only in whose item it is.
Panel.CATALYZE_VAULT_TEXT = "the vault's %s (%s) into the tier %s"
Panel.CATALYZE_VAULT_UNKNOWN = "a %s the vault is offering (QE Live did not say which)"

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
Panel.ONE_CHARGE_NONE = "not in QE Live's export - no set he ranked spends the charge just once"

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

Panel.NO_REWARDS_NOTE =
    "The vault has not generated this week's rewards yet. Progress is shown so you can see what is still unearned."
Panel.NO_VERDICT_NOTE = "No QE Live import yet, so no option carries a value. Paste a Top Gear export to change that."
Panel.STALE_NOTE =
    "This QE Live export predates this week's vault reset, so it does not know these options. Re-export it."

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
        local data = type(snapshot) == "table" and snapshot.data or nil
        for _, entry in ipairs(data and data.rewardLinks or {}) do
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
-- its row's Blizzard enum name, `highlight` the scenario the pick follows.
--
-- A cell with a gear reward draws that reward as an M5-1 item line and says
-- ONE verdict line - the highlighted scenario's, the same string
-- `Panel.ScenarioLine` put on the option below - with every scenario's line
-- kept in `tooltipLines` for the hover. A cell with no gear reward is locked
-- and says what the client says it needs.
function Panel.Cell(option, enumName, highlight)
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
    if not reward then
        cell.kind = "locked"
        cell.thresholdText = Panel.ThresholdText(option, enumName)
        cell.text = cell.thresholdText or option.progressText
        return cell
    end
    cell.kind = "reward"
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
    for _, enumName in ipairs(Panel.ROW_ORDER) do
        local activityType = ns.Vault and ns.Vault.ThresholdType(enumName) or nil
        local row = { key = enumName, type = activityType, label = Panel.GridRowLabel(enumName), cells = {} }
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
                local cell = Panel.Cell(option, enumName, highlight)
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
        -- Kept for the headless tests that pin the wording; the frame's header
        -- is what prints it, and Lines does not repeat it.
        note = Panel.NOTE,
        ok = vault.ok == true,
        reason = vault.reason,
        hasVerdict = verdict ~= nil,
        hasAvailableRewards = vault.hasAvailableRewards == true,
        canClaimRewards = vault.canClaimRewards == true,
        qeSettings = qeSettings,
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

    -- The headline block. Only when there is something to head: a verdict, a
    -- vault that could be read, and at least one gear option on it. Everything
    -- else on the tab already says why there is not.
    if model.hasVerdict and #scenarios > 0 and model.counts.rewards > 0 then
        local pick = model.best
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
            closest = closest and true or false,
            text = Panel.HeadlineText(highlight, pick, headlineCoverage),
            lines = {},
        }
        local thisWeekVerdict
        for _, entry in ipairs(scenarios) do
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
        model.rewardsNote = Panel.NO_REWARDS_NOTE
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
    if model.pendingNote then
        lines[#lines + 1] = Panel.NOTE_COLOR .. model.pendingNote .. "|r"
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
        add(model.headline.text)
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
-- Only a default; the window anchors this panel by two corners. See the same
-- note in UI/UpgradeMapPanel.lua.
local PANEL_WIDTH = 560
local PANEL_HEIGHT = 420

local ROW_LABEL_WIDTH = 74
local CELL_GAP = 8
local CELL_HEIGHT = 92
local GRID_ROW_GAP = 8
local CELL_ICON_SIZE = 32
local CHIP_ICON_SIZE = 14
local CHIP_GAP = 12

-- QE Live's gold as the three numbers a texture tint wants, off the same hex
-- the badge uses. Read from the constant rather than written out again, so the
-- accent has exactly one definition in this addon.
local function toneRGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- A flat 1-pixel texture Blizzard ships and every addon tints; used for the
-- fallback border, and only ever with SetVertexColor over it.
local WHITE_TEXTURE = [[Interface\Buttons\WHITE8X8]]

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

function Panel.ScenarioChoiceLabel(scenario)
    local labels = ns.UI and ns.UI.Options and ns.UI.Options.SCENARIO_CHOICE_LABEL or nil
    return (type(labels) == "table" and labels[scenario]) or Panel.ScenarioLabel(scenario)
end

local function buildScenarioDropdown(frame)
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, frame, Panel.DROPDOWN_TEMPLATE)
    if not ok or type(dropdown) ~= "table" or type(dropdown.SetupMenu) ~= "function" then
        return nil
    end
    dropdown:SetSize(Panel.DROPDOWN_WIDTH, Panel.DROPDOWN_HEIGHT)
    dropdown:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    -- The words on the closed dropdown. `SetDefaultText` belongs to
    -- DropdownSelectionTextMixin, which WowStyle1DropdownTemplate mixes in
    -- through its own XML; Blizzard's generated annotations do not record that
    -- inheritance, and a template's own method is a thing to call defensively
    -- in any case - a dropdown with no caption is still a dropdown.
    pcall(dropdown.SetDefaultText, dropdown, Panel.SCENARIO_DROPDOWN_LABEL)
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

function Panel.Create(parent)
    local frame = CreateFrame("Frame", "LootpathVaultPanel", parent or UIParent)
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:Hide()

    frame.header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.header:SetJustifyH("LEFT")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetText("Vault")

    frame.scenarioDropdown = buildScenarioDropdown(frame)

    frame.note = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.note:SetJustifyH("LEFT")
    frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
    frame.note:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame.note:SetText(Panel.NOTE)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -12)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 4)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(PANEL_WIDTH - 40, PANEL_HEIGHT - 60)
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
        text:SetWidth(PANEL_WIDTH - 60)
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

-- One option cell. Its regions are created once and re-bound on every refresh,
-- the way every list in this addon works: a cell that stops being the pick must
-- lose its glow, and a cell that stops holding an item must cancel what that
-- item was waiting for.
local function createCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetHeight(CELL_HEIGHT)
    cell:EnableMouse(true)

    cell.background = cell:CreateTexture(nil, "BACKGROUND")
    cell.background:SetAllPoints()
    cell.background:SetTexture(WHITE_TEXTURE)
    cell.background:SetVertexColor(0.07, 0.07, 0.08, 0.8)

    -- Blizzard's own selected art, when the client still has the atlas.
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

    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.label:SetPoint("BOTTOMLEFT", cell, "TOPLEFT", 4, -1)
    cell.label:SetJustifyH("LEFT")
    cell.label:SetWordWrap(false)
    cell.label:Hide()

    -- The badge column is zero here: a third of a panel is too narrow for a
    -- badge beside the name, so the verdict is its own line underneath, which
    -- is also where Blizzard's own vault cell puts its progress.
    cell.line = ns.UI.ItemLine.Create(cell, { size = CELL_ICON_SIZE, badgeWidth = 0 })
    cell.line:SetPoint("TOPLEFT", cell, "TOPLEFT", 6, -6)
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
    cell.locked:SetPoint("TOPLEFT", cell, "TOPLEFT", 6, -6)
    cell.locked:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -6, 6)
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
    GameTooltip:Show()
    return true
end

local function gridRow(frame, index)
    local existing = frame.gridRows[index]
    if existing then
        return existing
    end
    local rowFrame = CreateFrame("Frame", nil, frame.content)
    rowFrame:SetHeight(CELL_HEIGHT)
    rowFrame.label = rowFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rowFrame.label:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, -6)
    rowFrame.label:SetWidth(ROW_LABEL_WIDTH)
    rowFrame.label:SetJustifyH("LEFT")
    rowFrame.label:SetWordWrap(false)
    rowFrame.cells = {}
    for cellIndex = 1, Panel.ROW_CELLS do
        local cell = createCell(rowFrame)
        if cellIndex == 1 then
            cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", ROW_LABEL_WIDTH, 0)
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
    local atlas = selected and ns.UI.ItemLine.Atlas(Panel.SELECTED_ATLAS) or nil
    if atlas then
        cell.selectedTexture:SetAtlas(atlas)
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

local function bindCell(cell, data, cellWidth)
    cell:SetWidth(cellWidth)
    cell.data = data
    if not data or data.kind == "empty" then
        ns.UI.ItemLine.Clear(cell.line)
        cell:Hide()
        markCell(cell, false)
        return
    end
    cell:Show()
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
end

function Panel.Refresh(self, opts)
    self = self or Panel.frame
    if not self then
        return nil
    end
    local model = Panel.Model(Panel.Gather(opts))
    self.model = model

    local width = math.max(1, self.content:GetWidth())
    local gaps = CELL_GAP * (Panel.ROW_CELLS - 1)
    local cellWidth = math.max(60, math.floor((width - ROW_LABEL_WIDTH - gaps) / Panel.ROW_CELLS))

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
        headline.text:SetText(block.text)
        local height = CELL_ICON_SIZE
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
        headline:SetHeight(height + 8)
        used = used + height + 8
    else
        headline:Hide()
        ns.UI.ItemLine.ClearIcon(headline.icon)
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

    -- The currency strip, under the grid.
    local chips = model.currencyChips or {}
    local previous
    for index, data in ipairs(chips) do
        local entry = chip(self, index)
        entry:ClearAllPoints()
        if previous then
            entry:SetPoint("LEFT", previous, "RIGHT", CHIP_GAP, 0)
        else
            entry:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -GRID_ROW_GAP)
        end
        if data.icon then
            entry.icon:SetTexture(data.icon)
            entry.icon:Show()
        else
            entry.icon:Hide()
        end
        entry.text:SetText(data.text)
        entry:SetWidth(CHIP_ICON_SIZE + 4 + math.max(40, #data.text * 6))
        entry:Show()
        previous = entry
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
    used = used + CHIP_ICON_SIZE + GRID_ROW_GAP * 2

    -- Everything the client offers outside the three rows Blizzard draws.
    self.other:ClearAllPoints()
    self.other:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -GRID_ROW_GAP - CHIP_ICON_SIZE - GRID_ROW_GAP)
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
