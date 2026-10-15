-- Lootpath/UI/EngineDevPanel.lua (E-1c, WKE-689)
-- The developer engine's panel: `/lootpath engine` (or `/lootpath engine
-- panel`) toggles a window that shows what the compare has stored - the
-- weeks, the latest week's blocks row by row, the top-set agreement - and the
-- last `/lootpath engine best` of this session. DEVELOPER-ONLY, scoped by
-- CLAUDE.md's scoped exception and docs/ARCHITECTURE.md section 7 (2026-09-30,
-- E-0; 2026-10-09, E-1c): it opens only behind `db.global.developer.engine`,
-- it is built lazily on the first open (a player's client, which never has
-- the switch, never builds it), it hides itself when the switch is turned
-- off, and no other UI file reads it (spec/enginedevpanel_spec.lua).
--
-- "Never in a list with QE Live's numbers", as the issue reads it and the PR
-- asks the owner to confirm: the stored rating's percent and ours for the
-- same row sit in TWO SEPARATE CELLS of a developer table no player can open,
-- as `/lootpath engine compare` already prints them to chat. Nothing here
-- sorts by ours (every row keeps the order it was stored in), nothing combines
-- the two into one number or one string, and nothing here computes a value:
-- every figure is one the compare stored or the search returned. The only
-- module this file reads is ns.EngineCompare (the store's shape, its week
-- states and the bar's verdicts, and the last search it kept in memory).
--
-- Pure model, drawn frame: `Model(stored, lastBest, opts)` turns the store
-- into rows of cells, `Lines(model)` is every string the frame draws in the
-- order it draws them, and the frame draws one font string per cell. Native
-- frames and Blizzard's own templates only (BasicFrameTemplateWithInset and
-- UIPanelScrollFrameTemplate, both already used by MainFrame.lua and
-- VaultPanel.lua).
--
-- Combat: nothing is read or rebuilt in combat. The panel draws the combat
-- line the Upgrade Map draws and nothing else, and redraws once combat ends.

local _, ns = ...

ns.EngineDevPanel = {}
local Panel = ns.EngineDevPanel

-- Every client function this file calls, named rather than discovered.
Panel.FUNCTION_NAMES = {
    "CreateFrame",
    "InCombatLockdown",
}

Panel.FRAME_NAME = "LootpathEngineDevPanel"
Panel.WIDTH = 780
Panel.HEIGHT = 560
Panel.ROW_HEIGHT = 16
Panel.INSET = 14
-- The Upgrade Map's combat line, word for word (UpgradeMapPanel.Refresh).
Panel.COMBAT_LINE = "Lootpath does not read the client in combat. Leave combat and reopen this panel."
-- The compare's own order of content types; any other is listed after them.
Panel.CONTENT_ORDER = { "Dungeon", "Raid" }

Panel.TEXT = {
    title = "Developer engine",
    char = "%s · %d week(s) stored · latest %s",
    nothing = "Run /lootpath engine compare to store a week.",
    weeks = "Stored weeks",
    week = "%s: %s",
    latest = "Latest week, %s",
    provenance = "%s %s - weights %s, patch %s, derived %s, band %s",
    exported = "rated %s",
    noRows = "no row scored",
    agreement = "Top-set agreement",
    noSearch = "%s: no search stored",
    best = "Last best set this session",
    noBest = "Run /lootpath engine best to fill this. It is kept until you reload.",
    topGear = "Top Gear",
    notRated = "not rated: %d (effect not modelled)",
    unknown = "not rated: %d (trinket not in the effects table)",
    generic = "generic: %d (effect from a generic rule)",
}

-- The column layouts, in pixels. A row's `layout` names one; a row without
-- one is a single cell across the width.
Panel.COLUMNS = {
    weeks = { 82, 64, 64, 56, 78, 36, 56, 56, 56, 56 },
    block = { 78, 330, 72, 48, 80, 80 },
}
Panel.WEEKS_HEAD = { "week", "content", "document", "band", "class", "n", "rho", "k", "MAE", "MAE@k" }
-- `theirs` and `ours` are the compare's own words for the two columns.
Panel.BLOCK_HEAD = { "class", "item", "slot", "level", "theirs", "ours" }
Panel.THEIRS_CELL = 5
Panel.OURS_CELL = 6

-- ---------------------------------------------------------------------------
-- The switch.

function Panel.Enabled()
    return ns.EngineCompare ~= nil and ns.EngineCompare.Enabled() == true
end

-- ---------------------------------------------------------------------------
-- The model. Pure over the store and the last search.

local function fmt(x, pattern)
    if type(x) ~= "number" then
        return "-"
    end
    return string.format(pattern, x)
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- The content types of one week, the compare's order first.
local function contentsOf(mine)
    local out, seen = {}, {}
    for _, ct in ipairs(Panel.CONTENT_ORDER) do
        if type(mine[ct]) == "table" then
            out[#out + 1] = ct
            seen[ct] = true
        end
    end
    for _, ct in ipairs(sortedKeys(mine)) do
        if not seen[ct] and type(mine[ct]) == "table" then
            out[#out + 1] = ct
        end
    end
    return out
end

-- The documents of one content type: key levels in number order, the Top
-- Gear shelf last.
local function docsOf(docs)
    local out = {}
    for _, docKey in ipairs(sortedKeys(docs)) do
        if type(docs[docKey]) == "table" then
            out[#out + 1] = docKey
        end
    end
    local tg = ns.EngineCompare.TOP_GEAR_KEY
    table.sort(out, function(a, b)
        if (a == tg) ~= (b == tg) then
            return b == tg
        end
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then
            return na < nb
        end
        if na or nb then
            return na ~= nil
        end
        return tostring(a) < tostring(b)
    end)
    return out
end

local function docLabel(docKey)
    if docKey == ns.EngineCompare.TOP_GEAR_KEY then
        return Panel.TEXT.topGear
    end
    if tonumber(docKey) then
        return "+" .. tostring(docKey)
    end
    return tostring(docKey)
end

-- The classes a block carries, the compare's order, then any other.
local function classesOf(metrics)
    local out = {}
    for _, class in ipairs(ns.EngineCompare.CLASS_ORDER) do
        out[#out + 1] = class
    end
    if type(metrics) == "table" and metrics.other then
        out[#out + 1] = "other"
    end
    return out
end

local function line(rows, text, kind)
    rows[#rows + 1] = { kind = kind or "line", cells = { text } }
end

local function weeksSection(rows, stored, charKey)
    local EC = ns.EngineCompare
    line(rows, Panel.TEXT.weeks, "section")
    rows[#rows + 1] = { kind = "head", layout = "weeks", cells = Panel.WEEKS_HEAD }
    local states = EC.WeekStates(stored, charKey)
    for _, week in ipairs(states) do
        local mine = week.entries
        for _, ct in ipairs(contentsOf(mine)) do
            for _, docKey in ipairs(docsOf(mine[ct])) do
                local entry = mine[ct][docKey]
                local metrics = type(entry.metrics) == "table" and entry.metrics or {}
                for _, class in ipairs(classesOf(metrics)) do
                    local m = metrics[class]
                    if type(m) == "table" then
                        rows[#rows + 1] = {
                            kind = "row",
                            layout = "weeks",
                            cells = {
                                week.week,
                                ct,
                                docLabel(docKey),
                                tostring(entry.band or "-"),
                                class,
                                fmt(m.n, "%d"),
                                fmt(m.rho, "%.3f"),
                                fmt(m.k, "%.3f"),
                                fmt(m.mae, "%.3f"),
                                fmt(m.maeK, "%.3f"),
                            },
                        }
                    end
                end
            end
        end
        local parts = {}
        for _, class in ipairs(EC.CLASS_ORDER) do
            parts[#parts + 1] = class .. " " .. tostring(week.states[class])
        end
        line(rows, string.format(Panel.TEXT.week, week.week, table.concat(parts, " · ")))
    end
    -- The bar's verdict per class: `N/3 weeks`, `ready` or `no`. Printed,
    -- never enforced (memo section 6).
    line(rows, EC.VerdictLine(EC.Verdicts(stored, charKey)))
    return states
end

-- One block of the latest week: its provenance, then its rows by class in
-- the order they were stored, theirs and ours in two cells.
local function blockRows(rows, ct, docKey, entry)
    local T = Panel.TEXT
    line(
        rows,
        string.format(
            T.provenance,
            ct,
            docLabel(docKey),
            tostring(entry.method),
            tostring(entry.weightsPatch),
            tostring(entry.derivedAt),
            tostring(entry.band or "-")
        ),
        "subsection"
    )
    if entry.qeExportedAt then
        line(rows, string.format(T.exported, tostring(entry.qeExportedAt)))
    end
    local stored = type(entry.rows) == "table" and entry.rows or {}
    if #stored == 0 then
        line(rows, T.noRows)
    else
        rows[#rows + 1] = { kind = "head", layout = "block", cells = Panel.BLOCK_HEAD }
    end
    local metrics = type(entry.metrics) == "table" and entry.metrics or {}
    for _, class in ipairs(classesOf(metrics)) do
        local any = false
        for index, row in ipairs(stored) do
            if (row.class or "other") == class then
                any = true
                rows[#rows + 1] = {
                    kind = "row",
                    layout = "block",
                    class = class,
                    storedIndex = index,
                    key = row.key,
                    theirs = row.theirs,
                    ours = row.ours,
                    cells = {
                        class,
                        tostring(row.link or row.key),
                        tostring(row.slot or "-"),
                        fmt(row.level, "%d"),
                        fmt(row.theirs, "%.3f"),
                        fmt(row.ours, "%.3f"),
                    },
                }
            end
        end
        if not any and class == "trinket" and #stored > 0 then
            line(rows, (ns.EngineCompare.TEXT.trinketNone:gsub("^%s+", "")))
        end
    end
    if (entry.generic or 0) > 0 then
        line(rows, string.format(T.generic, entry.generic))
    end
    line(rows, string.format(T.notRated, entry.notRated or 0))
    if (entry.unknown or 0) > 0 then
        line(rows, string.format(T.unknown, entry.unknown))
    end
end

local function latestSection(rows, latest)
    line(rows, string.format(Panel.TEXT.latest, latest.week), "section")
    local mine = latest.entries
    for _, ct in ipairs(contentsOf(mine)) do
        for _, docKey in ipairs(docsOf(mine[ct])) do
            blockRows(rows, ct, docKey, mine[ct][docKey])
        end
    end
end

-- E-1b's agreement, as the compare prints it under its Top Gear block.
local function agreementSection(rows, latest)
    local EC = ns.EngineCompare
    line(rows, Panel.TEXT.agreement, "section")
    local mine = latest.entries
    for _, ct in ipairs(contentsOf(mine)) do
        local entry = mine[ct][EC.TOP_GEAR_KEY]
        if type(entry) == "table" then
            if type(entry.search) == "table" then
                line(rows, ct, "subsection")
                for _, text in ipairs(EC.SearchLines({}, entry.search)) do
                    line(rows, (text:gsub("^%s+", "")))
                end
            else
                line(rows, string.format(Panel.TEXT.noSearch, ct))
            end
        end
    end
end

-- The last `/lootpath engine best` of this session: the lines the search
-- printed, kept in memory by ns.EngineCompare beside the run's result table.
local function bestSection(rows, lastBest)
    line(rows, Panel.TEXT.best, "section")
    if type(lastBest) ~= "table" or type(lastBest.lines) ~= "table" then
        line(rows, Panel.TEXT.noBest)
        return
    end
    for _, text in ipairs(lastBest.lines) do
        line(rows, (tostring(text):gsub("^%s+", "")))
    end
end

-- Model(stored, lastBest, opts) -> { rows, charKey, weeks, latest }.
-- `stored` is `db.global.engineCompare`; `lastBest` is what
-- ns.EngineCompare kept of the session's last search (`{ run, lines }`) or
-- nil; `opts.charKey` the character (default EngineCompare.CharKey()).
-- Every row is `{ kind, layout?, cells }`; a compare row also carries `key`,
-- `class`, `theirs`, `ours` and `storedIndex` (its place in the stored rows).
function Panel.Model(stored, lastBest, opts)
    opts = opts or {}
    stored = type(stored) == "table" and stored or {}
    local charKey = opts.charKey or ns.EngineCompare.CharKey()
    local rows = {}
    line(rows, Panel.TEXT.title, "title")
    local weeks = ns.EngineCompare.WeekStates(stored, charKey)
    local latest = weeks[#weeks]
    if latest then
        line(rows, string.format(Panel.TEXT.char, charKey, #weeks, latest.week))
        weeksSection(rows, stored, charKey)
        latestSection(rows, latest)
        agreementSection(rows, latest)
    else
        line(rows, string.format(ns.EngineCompare.TEXT.weeksNone, charKey))
        line(rows, Panel.TEXT.nothing)
    end
    bestSection(rows, lastBest)
    return { rows = rows, charKey = charKey, weeks = #weeks, latest = latest and latest.week or nil }
end

-- The model the frame draws in combat: the combat line and nothing read.
function Panel.CombatModel()
    return { rows = { { kind = "line", cells = { Panel.COMBAT_LINE } } }, inCombat = true }
end

-- Lines(model) -> every string the frame draws, in the order it draws them:
-- one per cell, so the text tests read is the text on screen.
function Panel.Lines(model)
    local out = {}
    for _, row in ipairs(model and model.rows or {}) do
        for _, cell in ipairs(row.cells) do
            out[#out + 1] = cell
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The frame. Built on the first open and never before.

local FONT_OF_KIND = {
    title = "GameFontNormalLarge",
    section = "GameFontNormal",
    subsection = "GameFontHighlight",
    head = "GameFontNormalSmall",
}
local DEFAULT_FONT = "GameFontHighlightSmall"

local function cellString(frame, index)
    local fs = frame.cells[index]
    if not fs then
        fs = frame.content:CreateFontString(nil, "ARTWORK", DEFAULT_FONT)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        frame.cells[index] = fs
    end
    return fs
end

-- Draw(frame, model): one font string per cell, a row per ROW_HEIGHT; the
-- cells a smaller model leaves over are hidden.
function Panel.Draw(frame, model)
    local used = 0
    local width = Panel.WIDTH - 2 * Panel.INSET - 24
    for index, row in ipairs(model.rows) do
        local y = -(index - 1) * Panel.ROW_HEIGHT
        local columns = row.layout and Panel.COLUMNS[row.layout] or nil
        local x = 0
        for col, text in ipairs(row.cells) do
            used = used + 1
            local fs = cellString(frame, used)
            fs:SetFontObject(FONT_OF_KIND[row.kind] or DEFAULT_FONT)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", frame.content, "TOPLEFT", x, y)
            local w = columns and columns[col] or width
            fs:SetWidth(w)
            fs:SetText(text)
            fs:Show()
            x = x + w
        end
    end
    for i = used + 1, #frame.cells do
        frame.cells[i]:SetText("")
        frame.cells[i]:Hide()
    end
    frame.content:SetSize(width, math.max(1, #model.rows) * Panel.ROW_HEIGHT)
    frame.model = model
    frame.lines = Panel.Lines(model)
end

local function onEvent(frame, event)
    if (event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED") and frame:IsShown() then
        Panel.Refresh()
    end
end

function Panel.Create()
    if Panel.frame then
        return Panel.frame
    end
    local frame = CreateFrame("Frame", Panel.FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
    Panel.frame = frame
    frame:SetSize(Panel.WIDTH, Panel.HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.TitleText then
        frame.TitleText:SetText(Panel.TEXT.title)
    end

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", Panel.INSET, -30)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Panel.INSET - 22, Panel.INSET)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(Panel.WIDTH - 2 * Panel.INSET - 24, Panel.ROW_HEIGHT)
    frame.scroll:SetScrollChild(frame.content)
    -- A compare row's item cell is the link the compare read: hovering it
    -- shows the item, as the main window's links do.
    frame.content:SetHyperlinksEnabled(true)
    frame.content:SetScript("OnHyperlinkEnter", function(self, link)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end
    end)
    frame.content:SetScript("OnHyperlinkLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    frame.cells = {}

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", onEvent)

    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = Panel.FRAME_NAME
    end
    frame:Hide()
    return frame
end

-- Refresh() -> the model drawn, or nil. Never builds the frame: a panel that
-- was never opened stays unbuilt. With the switch off the panel hides; in
-- combat it draws the combat line and reads nothing.
function Panel.Refresh()
    local frame = Panel.frame
    if not frame or not frame:IsShown() then
        return nil
    end
    if not Panel.Enabled() then
        frame:Hide()
        return nil
    end
    local model
    if InCombatLockdown() then
        model = Panel.CombatModel()
    else
        local global = ns.db and ns.db.global or {}
        model = Panel.Model(global.engineCompare, ns.EngineCompare.lastBest)
    end
    Panel.Draw(frame, model)
    return model
end

-- Toggle() -> true when the panel is now shown. Behind the switch: without it
-- the answer is `not on` and nothing is built.
function Panel.Toggle()
    if not Panel.Enabled() then
        ns.Log("%s", ns.EngineCompare.TEXT.notOn)
        return false
    end
    local frame = Panel.Create()
    if frame:IsShown() then
        frame:Hide()
        return false
    end
    frame:Show()
    Panel.Refresh()
    return true
end
