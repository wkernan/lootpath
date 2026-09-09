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
    maxed = "everything upgraded",
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
    catalyzed = "needs a Catalyst charge",
    maxed = "needs crests",
}

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

-- The row's name in the game's words. Falls back to the module's measured label
-- for every threshold type this panel does not translate (Concession, Ranked
-- PvP, Also receive), which is honest: those rows are not on the owner's vault
-- screen under another name.
function Panel.RowLabel(option)
    local activityType = option and option.type
    if activityType ~= nil and ns.Vault then
        for name, label in pairs(Panel.ROW_LABEL_BY_ENUM) do
            if ns.Vault.ThresholdType(name) == activityType then
                return label
            end
        end
    end
    return (option and option.typeLabel) or "Unknown"
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
-- the pair - no difference, no preference, no "real" level.
function Panel.LevelText(clientLevel, qeLevel, qeSettings)
    local text = tostring(clientLevel)
    if type(clientLevel) ~= "number" or type(qeLevel) ~= "number" or qeLevel == clientLevel then
        return text
    end
    local phrase = Panel.SettingsPhrase(qeSettings)
    text = text .. "; " .. string.format(Panel.QE_LEVEL_TEXT, qeLevel)
    if phrase then
        text = text .. " " .. phrase
    end
    return text
end

local function rewardName(reward)
    return reward.name or reward.link or ("item " .. tostring(reward.itemID))
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
function Panel.CountText(scenario, currencies)
    local ok = type(currencies) == "table" and currencies.ok == true
    if scenario == "catalyzed" then
        if not ok or not currencies.catalystKnown then
            return Panel.COUNT_UNKNOWN
        end
        if currencies.catalystCharges == nil then
            return Panel.CATALYST_NOT_READABLE
        end
        if currencies.catalystMax then
            return string.format(
                Panel.HAVE_OF_TEXT,
                tostring(currencies.catalystCharges),
                tostring(currencies.catalystMax)
            )
        end
        return string.format(Panel.HAVE_TEXT, tostring(currencies.catalystCharges))
    end
    if scenario == "maxed" then
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
    return ""
end

-- The fixed phrase naming what a scenario assumed, with the client's count
-- after it, or nil for a scenario that assumed nothing.
function Panel.NeedsText(scenario, currencies)
    local needs = Panel.NEEDS_TEXT[scenario]
    if not needs then
        return nil
    end
    return needs .. Panel.CountText(scenario, currencies)
end

-- One line of the headline block: what QE Live picked under this scenario, and
-- what that answer assumed. `pick` is { reward, coverage, viaCatalyst } - the
-- best-ranked thing he said about any option in this vault under this scenario,
-- by his own ordering - and `headlinePick` is the reward the block leads with,
-- so the item is named only when the two differ.
function Panel.HeadlineLine(scenario, pick, headlinePick, currencies)
    local label = Panel.ScenarioLabel(scenario) .. ((pick and pick.viaCatalyst) and Panel.CATALYZED_SUFFIX or "")
    if not pick then
        return { scenario = scenario, text = label .. ": " .. Panel.SCENARIO_SILENT }
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
        text = label .. ": " .. prefix .. answer .. (needs and (" - " .. needs) or ""),
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
    local label = Panel.ScenarioLabel(scenario)
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

-- Model(opts) -> the panel as plain data.
--
-- opts.vault       ns.Vault.Options()'s result
-- opts.verdict     ns.QEImport.Current()
-- opts.currencies  ns.Currencies.Read()'s result; only the headline block reads
--                  it, and only to say how many of a thing the player has
-- opts.now         epoch second (default time()); only used for the stale note
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
        counts = { options = 0, rewards = 0, extras = 0, covered = 0, scenarios = #scenarios },
    }
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
            if reward.slot == nil then
                -- Not gear: no equippable slot, so no item level worth showing
                -- and nothing QE Live could have ranked. A reward whose link
                -- never arrived lands here too, and is named by whatever it has.
                local extra = {
                    itemID = reward.itemID,
                    itemDBID = reward.itemDBID,
                    link = reward.link,
                    name = reward.name,
                }
                extra.text = "+ " .. rewardName(reward)
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
                    itemLevel = reward.itemLevel,
                    slot = reward.slot,
                    -- QE Live's own assumed level for this exact item, carried
                    -- beside the client's rather than instead of it.
                    qeLevel = qeItem and tonumber(qeItem.level) or nil,
                    -- The only path to a number on a vault row: nil `qe` means nil
                    -- `value`, and there is no other assignment to `value` here.
                    qe = coverage,
                    qeViaCatalyst = viaCatalyst,
                    value = coverage and ns.UpgradeMapPanel.ValueText(coverage) or nil,
                }
                row.levelText = Panel.LevelText(row.itemLevel, row.qeLevel, qeSettings)
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
            local text = string.format("%s (%s)", rewardName(reward), reward.levelText)
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
        model.headline = {
            scenario = highlight,
            pick = pick,
            text = Panel.HeadlineText(
                highlight,
                pick,
                bestByScenario[highlight] and bestByScenario[highlight].coverage
            ),
            lines = {},
        }
        for _, entry in ipairs(scenarios) do
            model.headline.lines[#model.headline.lines + 1] =
                Panel.HeadlineLine(entry.scenario, bestByScenario[entry.scenario], pick, opts.currencies)
        end
    end

    if model.counts.rewards == 0 and model.counts.extras == 0 then
        model.rewardsNote = Panel.NO_REWARDS_NOTE
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

-- The pinned note is NOT one of these lines: the panel header draws it once,
-- above the list, and until WKE-530 the list printed it again as its first row
-- (seen in game 2026-09-06 on this tab and the Upgrade Map). The model still
-- carries `note` for the headless tests that pin the wording.
function Panel.Lines(model)
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end
    if not model.ok then
        add(string.format("The vault could not be read: %s", tostring(model.reason)))
        return lines
    end
    if model.verdictNote then
        add(model.verdictNote)
    end
    if model.highlightNote then
        add(model.highlightNote)
    end
    if model.staleNote then
        add(model.staleNote)
    end
    if model.rewardsNote then
        add(model.rewardsNote)
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

local ROW_HEIGHT = 14
-- Only a default; the window anchors this panel by two corners. See the same
-- note in UI/UpgradeMapPanel.lua.
local PANEL_WIDTH = 560
local PANEL_HEIGHT = 420

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

function Panel.Gather(opts)
    opts = opts or {}
    return {
        vault = ns.Vault.Options(),
        verdict = activeVerdict(),
        scenarios = activeScenarios(),
        -- The only client numbers on this tab that are not the vault's own.
        -- Read here rather than inside Model so a headless test drives them.
        currencies = ns.Currencies and ns.Currencies.Read() or nil,
        highlightScenario = ns.UI
                and ns.UI.Options
                and ns.UI.Options.GetVaultScenario
                and ns.UI.Options.GetVaultScenario()
            or nil,
        now = opts.now,
    }
end

function Panel.Create(parent)
    local frame = CreateFrame("Frame", "LootpathVaultPanel", parent or UIParent)
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:Hide()

    frame.header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.header:SetJustifyH("LEFT")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetText("Vault")

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

function Panel.Refresh(self, opts)
    self = self or Panel.frame
    if not self then
        return nil
    end
    local model = Panel.Model(Panel.Gather(opts))
    self.model = model
    local lines = Panel.Lines(model)
    for i, line in ipairs(lines) do
        row(self, i):SetText(line)
    end
    for i = #lines + 1, #self.rows do
        self.rows[i]:SetText("")
        self.rows[i]:Hide()
    end
    self.content:SetHeight(math.max(1, #lines * ROW_HEIGHT))
    self.lines = lines
    return model
end
