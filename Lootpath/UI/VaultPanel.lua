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

-- Model(opts) -> the panel as plain data.
--
-- opts.vault    ns.Vault.Options()'s result
-- opts.verdict  ns.QEImport.Current()
-- opts.now      epoch second (default time()); only used for the stale note
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
    local verdict = opts.verdict
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
        options = {},
        counts = { options = 0, rewards = 0, extras = 0, covered = 0 },
    }

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
                local coverage = reward.key and ns.QEImport.Coverage(verdict, reward.key) or nil
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

    -- The extras fragment rides on the first gear option of its row, so name,
    -- level and "+ Mythic Keystone" stay one unit; a row with extras and no gear
    -- keeps the fragment on a line of its own rather than losing it.
    for _, option in ipairs(model.options) do
        for index, reward in ipairs(option.rewards) do
            local text = string.format("%s (%s)", rewardName(reward), reward.levelText)
            if index == 1 and option.extrasText then
                text = text .. " " .. option.extrasText
            end
            if reward.best then
                text = text .. "  <- QE Live's pick"
            end
            reward.text = text
            reward.verdictLines = reward.value and { reward.value } or {}
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
    if model.staleNote then
        add(model.staleNote)
    end
    if model.rewardsNote then
        add(model.rewardsNote)
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

function Panel.Gather(opts)
    opts = opts or {}
    return {
        vault = ns.Vault.Options(),
        verdict = activeVerdict(),
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
