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
-- The highlight is QE Live's ordering, not this addon's: an option in his top
-- set outranks one that appears only in an alternative, and among alternatives
-- the order is QEImport.AlternativeRank, which reads his sign convention from
-- the pinned constant. An option nothing covers is never highlighted.

local _, ns = ...

ns.VaultPanel = {}
local Panel = ns.VaultPanel

Panel.NOTE = "Values shown are QE Live's, for options it has ranked. Other options are listed by item level only."
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
function Panel.Model(opts)
    opts = opts or {}
    local vault = opts.vault or {}
    local verdict = opts.verdict
    local model = {
        note = Panel.NOTE,
        ok = vault.ok == true,
        reason = vault.reason,
        hasVerdict = verdict ~= nil,
        hasAvailableRewards = vault.hasAvailableRewards == true,
        canClaimRewards = vault.canClaimRewards == true,
        options = {},
        counts = { options = 0, rewards = 0, covered = 0 },
    }

    local best, bestRank
    for _, option in ipairs(vault.options or {}) do
        local rewards = {}
        for _, reward in ipairs(option.rewards or {}) do
            local coverage = reward.key and ns.QEImport.Coverage(verdict, reward.key) or nil
            local row = {
                itemID = reward.itemID,
                itemDBID = reward.itemDBID,
                key = reward.key,
                link = reward.link,
                name = reward.name,
                itemLevel = reward.itemLevel,
                slot = reward.slot,
                -- The only path to a number on a vault row: nil `qe` means nil
                -- `value`, and there is no other assignment to `value` here.
                qe = coverage,
                value = coverage and ns.UpgradeMapPanel.ValueText(coverage) or nil,
            }
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
        local entry = {
            type = option.type,
            typeLabel = option.typeLabel,
            index = option.index,
            id = option.id,
            threshold = option.threshold,
            progress = option.progress,
            level = option.level,
            unlocked = option.unlocked == true,
            progressText = progressText(option),
            rewards = rewards,
        }
        model.options[#model.options + 1] = entry
        model.counts.options = model.counts.options + 1
    end

    if best then
        best.best = true
        model.best = best
    end

    if model.counts.rewards == 0 then
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

function Panel.Lines(model)
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end
    add(model.note)
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
        add(
            string.format(
                "%s %d: %s%s",
                option.typeLabel,
                option.index or 0,
                option.progressText,
                option.unlocked and " - unlocked" or ""
            )
        )
        for _, reward in ipairs(option.rewards) do
            local text = string.format(
                "  %s (%s)",
                reward.name or reward.link or ("item " .. tostring(reward.itemID)),
                tostring(reward.itemLevel)
            )
            if reward.value then
                text = text .. " - " .. reward.value
            end
            if reward.best then
                text = text .. "  <- QE Live's pick"
            end
            add(text)
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Frames. Native only, no AceGUI (decision 2026-09-05).

local ROW_HEIGHT = 14
local PANEL_WIDTH = 560
local PANEL_HEIGHT = 420

function Panel.Gather(opts)
    opts = opts or {}
    return {
        vault = ns.Vault.Options(),
        verdict = ns.QEImport.Current(),
        now = opts.now,
    }
end

function Panel.Create(parent)
    local frame = CreateFrame("Frame", "LootpathVaultPanel", parent or UIParent)
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:Hide()

    frame.note = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.note:SetJustifyH("LEFT")
    frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.note:SetWidth(PANEL_WIDTH - 16)
    frame.note:SetText(Panel.NOTE)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -12)
    frame.scroll:SetSize(PANEL_WIDTH - 40, PANEL_HEIGHT - 60)
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
