-- Lootpath/UI/UpgradeMapPanel.lua (M3-3, WKE-524)
-- The second promise: for each gear slot, what you are wearing and which boss
-- drops a candidate, at what item level, from the Encounter Journal walk.
--
-- THE RULE THIS FILE EXISTS TO KEEP (decision 2026-09-05, option A):
-- QE Live's Upgrade Finder - the module that values drops you do not own - has
-- no export. Only Top Gear exports, and Top Gear ranks what you own plus your
-- vault. So this panel is VALUES-FREE: a candidate shows a number only where
-- the Top Gear verdict covers that exact item key, and every other candidate
-- shows where it drops and at what item level and nothing about how good it is.
-- `row.value` is nil unless `row.qe` is, and there is no other path to a number
-- in this file. If a gap tempts you to estimate, stop.
--
-- Measured 2026-09-06, and it is why the values-free half is the normal case:
-- every keyed row of the committed journal walk carries exactly ONE bonus ID
-- (3524 on all 189 of them), while the items in the committed Top Gear export
-- carry two to seven. One itemID appears in both (251153, Arctic Explorer's
-- Legwraps, Feet, from Sentinel of Winter in Den of Nalorakk) and even there
-- the keys differ - "251153:3524" against the owned copy's five bonus IDs - so
-- the exact-key join covers nothing on that pair. The join is still the right
-- one and is kept: it is what the vault and a re-export will match on, and a
-- looser join would put a number about one item next to a different item.
--
-- Model(opts) is pure Lua over data the caller gathered; Create/Refresh are the
-- frames. Nothing here runs in combat, because the scanners it reads refuse to.

local _, ns = ...

ns.UpgradeMapPanel = {}
local Panel = ns.UpgradeMapPanel

-- Pinned wording (decision 2026-09-05). A test asserts this string exactly.
Panel.NOTE = "Values shown are QE Live's, for items it has ranked. Other drops are listed by item level only."

-- Pinned too, because getting it wrong is the one way this panel can lie about
-- an item: a row the client had not sent yet is unknown, never zero.
Panel.PENDING_NOTE = "%d drops are not identified yet: their item data had not arrived. Unknown, not item level 0."

Panel.EMPTY_NOTE = "No loot map yet. Run /lootpath capture journal out of combat to walk the Adventure Guide."

-- QE Live's slot vocabulary, in the order a character sheet reads. Inventory
-- and Journal both speak it (ns.Inventory.SLOT_BY_EQUIPLOC), which is what
-- makes this join a join.
Panel.SLOT_ORDER = {
    "Head",
    "Neck",
    "Shoulder",
    "Back",
    "Chest",
    "Wrist",
    "Hands",
    "Waist",
    "Legs",
    "Feet",
    "Finger",
    "Trinket",
    "1H Weapon",
    "2H Weapon",
    "Offhand",
    "Shield",
}

-- Fallback difficulty names, keyed by the IDs ns.JournalAdapter.DIFFICULTY
-- reads from Blizzard's own DifficultyUtil.lua. GetDifficultyInfo wins when the
-- client has it, because its name is the localised one; these exist so a
-- headless run and a client without that function still say something true.
Panel.DIFFICULTY_NAME = {
    [1] = "Normal dungeon",
    [2] = "Heroic dungeon",
    [8] = "Mythic+",
    [14] = "Normal raid",
    [15] = "Heroic raid",
    [16] = "Mythic raid",
    [23] = "Mythic dungeon",
}

local function mythicPlusDifficulty()
    return ns.JournalAdapter and ns.JournalAdapter.DifficultyID("DungeonChallenge") or 8
end

-- The M+ row is the only one whose item levels mean nothing without the
-- keystone level the walk previewed, so that number is part of its label.
function Panel.DifficultyLabel(difficultyID, previewMythicPlusLevel)
    local name
    if type(_G.GetDifficultyInfo) == "function" then
        local ok, live = pcall(_G.GetDifficultyInfo, difficultyID)
        if ok then
            local safe = ns.Safe(live)
            if type(safe) == "string" and safe ~= "" then
                name = safe
            end
        end
    end
    name = name or Panel.DIFFICULTY_NAME[difficultyID] or ("Difficulty " .. tostring(difficultyID))
    if difficultyID == mythicPlusDifficulty() and previewMythicPlusLevel then
        return string.format("%s %d", name, previewMythicPlusLevel)
    end
    return name
end

-- The line a covered row shows. Numbers are QE Live's, transported: the
-- percentage magnitude is his, the score delta is his sign and all, and the
-- direction word is read from QEImport.AlternativeIsBetter rather than from
-- arithmetic here. A top-set item carries no delta in the export, so it gets
-- words and no number rather than a number this addon made up.
--
-- `hpsDifference` is NOT labelled "HPS", whatever its name says: QE Live's
-- conversion to real HPS is commented out in his own source, so the field is a
-- raw hardScore delta (verified 2026-09-06, ARCHITECTURE.md 9). Calling it HPS
-- on screen would be this addon inventing a healing number.
function Panel.ValueText(coverage)
    if type(coverage) ~= "table" then
        return nil
    end
    if coverage.where == "topSet" then
        return "QE Live: in your best set"
    end
    local percent = tonumber(coverage.scorePercent)
    local hps = tonumber(coverage.hpsDifference)
    if not percent then
        return "QE Live: ranked, no delta given"
    end
    local direction = coverage.isBetter and "better" or "worse"
    if hps then
        return string.format("QE Live: %s by %.2f%% (%+.1f score)", direction, math.abs(percent), hps)
    end
    return string.format("QE Live: %s by %.2f%%", direction, math.abs(percent))
end

local function sourceLabel(entry)
    local instance = entry.instanceName or ("Instance " .. tostring(entry.instanceID))
    if entry.encounterName then
        return instance .. " - " .. entry.encounterName
    end
    if entry.encounterID then
        return instance .. " - encounter " .. tostring(entry.encounterID)
    end
    return instance
end

-- itemID -> the best copy the character owns, so a row can say "you own one"
-- without saying anything about how good it is. Ownership is a fact read from
-- the client; it is not a ranking and never becomes one.
local function ownedByItemID(inventory)
    local owned = {}
    for _, record in ipairs((inventory and inventory.records) or {}) do
        local existing = owned[record.itemID]
        if not existing or (record.itemLevel or 0) > (existing.itemLevel or 0) then
            owned[record.itemID] = record
        end
    end
    return owned
end

local function equippedBySlot(inventory)
    local bySlot = {}
    for _, record in ipairs((inventory and inventory.records) or {}) do
        if record.location == "equipped" and record.slot then
            local list = bySlot[record.slot] or {}
            bySlot[record.slot] = list
            list[#list + 1] = record
        end
    end
    for _, list in pairs(bySlot) do
        table.sort(list, function(a, b)
            return (a.slotIndex or 0) < (b.slotIndex or 0)
        end)
    end
    return bySlot
end

-- Item level descending is what the issue asks for; the rest of the order is
-- there so the same map always renders the same way.
local function sortCandidates(rows)
    table.sort(rows, function(a, b)
        if (a.itemLevel or 0) ~= (b.itemLevel or 0) then
            return (a.itemLevel or 0) > (b.itemLevel or 0)
        end
        if (a.name or "") ~= (b.name or "") then
            return (a.name or "") < (b.name or "")
        end
        if a.itemID ~= b.itemID then
            return a.itemID < b.itemID
        end
        if (a.instanceID or 0) ~= (b.instanceID or 0) then
            return (a.instanceID or 0) < (b.instanceID or 0)
        end
        if (a.encounterID or 0) ~= (b.encounterID or 0) then
            return (a.encounterID or 0) < (b.encounterID or 0)
        end
        return (a.difficultyID or 0) < (b.difficultyID or 0)
    end)
end

-- Model(opts) -> the whole panel as plain data, so every rule above is a test
-- over fixtures rather than a claim about frames.
--
-- opts.sources     ns.Journal:Build's map (required for candidates)
-- opts.summary     its summary (previewMythicPlusLevel is read from here)
-- opts.inventory   ns.Inventory.Scan's result
-- opts.verdict     ns.QEImport.Current()
-- opts.difficultyIDs  show only these difficulties (nil or empty = all)
function Panel.Model(opts)
    opts = opts or {}
    local sources = opts.sources or {}
    local summary = opts.summary or {}
    local verdict = opts.verdict
    local previewLevel = opts.previewMythicPlusLevel or summary.previewMythicPlusLevel

    local wanted
    for _, id in ipairs(opts.difficultyIDs or {}) do
        wanted = wanted or {}
        wanted[id] = true
    end

    local owned = ownedByItemID(opts.inventory)
    local bySlot, pendingRows = {}, {}
    local difficultyCounts = {}
    local model = {
        note = Panel.NOTE,
        previewMythicPlusLevel = previewLevel,
        hasMap = false,
        hasVerdict = verdict ~= nil,
        slots = {},
        difficulties = {},
        pending = { count = 0, rows = pendingRows },
        counts = { candidates = 0, covered = 0, owned = 0, slots = 0 },
    }

    local itemIDs = {}
    for itemID in pairs(sources) do
        model.hasMap = true
        itemIDs[#itemIDs + 1] = itemID
    end
    table.sort(itemIDs)

    for _, itemID in ipairs(itemIDs) do
        for _, entry in ipairs(sources[itemID]) do
            difficultyCounts[entry.difficultyID] = (difficultyCounts[entry.difficultyID] or 0) + 1
            if not wanted or wanted[entry.difficultyID] then
                local ownedRecord = owned[itemID]
                local row = {
                    itemID = itemID,
                    itemKey = entry.itemKey,
                    name = entry.name,
                    itemLevel = entry.itemLevel,
                    slot = entry.slot,
                    instanceID = entry.instanceID,
                    instanceName = entry.instanceName,
                    encounterID = entry.encounterID,
                    encounterName = entry.encounterName,
                    difficultyID = entry.difficultyID,
                    isRaid = entry.isRaid == true,
                    pending = entry.pending == true,
                    sourceLabel = sourceLabel(entry),
                    difficultyLabel = Panel.DifficultyLabel(entry.difficultyID, previewLevel),
                    owned = ownedRecord ~= nil or nil,
                    ownedItemLevel = ownedRecord and ownedRecord.itemLevel or nil,
                }
                -- The only path to a number on a candidate row. `qe` is nil
                -- whenever the verdict does not carry this exact key, and
                -- `value` is nil whenever `qe` is.
                row.qe = entry.itemKey and ns.QEImport.Coverage(verdict, entry.itemKey) or nil
                row.value = row.qe and Panel.ValueText(row.qe) or nil
                if row.owned then
                    model.counts.owned = model.counts.owned + 1
                end
                if row.qe then
                    model.counts.covered = model.counts.covered + 1
                end
                model.counts.candidates = model.counts.candidates + 1
                if row.pending or not row.slot then
                    -- No slot means the item data never arrived, so there is no
                    -- slot to file it under. It is listed, not dropped, and it
                    -- is listed as unknown rather than as a zero.
                    pendingRows[#pendingRows + 1] = row
                else
                    local list = bySlot[row.slot] or {}
                    bySlot[row.slot] = list
                    list[#list + 1] = row
                end
            end
        end
    end

    model.pending.count = #pendingRows
    model.pending.note = string.format(Panel.PENDING_NOTE, model.pending.count)
    sortCandidates(pendingRows)

    local equipped = equippedBySlot(opts.inventory)
    for _, slot in ipairs(Panel.SLOT_ORDER) do
        local candidates = bySlot[slot]
        local worn = equipped[slot]
        if candidates or worn then
            sortCandidates(candidates or {})
            model.slots[#model.slots + 1] = {
                slot = slot,
                equipped = worn or {},
                candidates = candidates or {},
            }
            model.counts.slots = model.counts.slots + 1
        end
    end

    local ids = {}
    for id in pairs(difficultyCounts) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        model.difficulties[#model.difficulties + 1] = {
            difficultyID = id,
            label = Panel.DifficultyLabel(id, previewLevel),
            count = difficultyCounts[id],
            selected = (not wanted) or wanted[id] == true,
        }
    end
    return model
end

-- The model as display lines, which is what the frames put on screen and what
-- the render tests read. Keeping it a pure function is what lets a test prove
-- that an uncovered candidate renders no number at all.
function Panel.Lines(model)
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end
    add(model.note)
    if not model.hasMap then
        add(Panel.EMPTY_NOTE)
        return lines
    end
    if not model.hasVerdict then
        add("No QE Live import yet, so no drop carries a value. Paste a Top Gear export to change that.")
    end
    for _, section in ipairs(model.slots) do
        add(section.slot)
        for _, record in ipairs(section.equipped) do
            add(string.format("  equipped: %s (%s)", record.name or record.link or "?", tostring(record.itemLevel)))
        end
        for _, row in ipairs(section.candidates) do
            local text = string.format(
                "  %s (%s) - %s, %s",
                row.name or ("item " .. tostring(row.itemID)),
                tostring(row.itemLevel),
                row.sourceLabel,
                row.difficultyLabel
            )
            if row.owned then
                text = text .. string.format(" [owned %s]", tostring(row.ownedItemLevel))
            end
            if row.value then
                text = text .. " - " .. row.value
            end
            add(text)
        end
    end
    if model.pending.count > 0 then
        add("Unidentified drops")
        add("  " .. model.pending.note)
        for _, row in ipairs(model.pending.rows) do
            add(
                string.format(
                    "  item %d - %s, %s - item data not arrived",
                    row.itemID,
                    row.sourceLabel,
                    row.difficultyLabel
                )
            )
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Frames. Native only, no AceGUI (decision 2026-09-05).

local ROW_HEIGHT = 14
-- Only a default: the window anchors this panel by two corners (M3-3 wiring in
-- UI/MainFrame.lua), which is what actually sizes it. The size matters for a
-- panel built on its own, which is what the render tests do.
local PANEL_WIDTH = 560
local PANEL_HEIGHT = 420

local function fontString(parent, template)
    local text = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    return text
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

-- The newest journal walk the addon has stored. `capture journal` is the only
-- thing that produces one today (M3-1), so the panel says so when there is none
-- rather than rendering an empty map as if the season had no loot.
function Panel.LatestWalk(db)
    db = db or ns.db
    local list = db and db.global and db.global.captures and db.global.captures.journal
    if type(list) ~= "table" then
        return nil
    end
    return list[#list]
end

-- Everything Model needs, read from the client and the database. Out of combat
-- only, because Inventory.Scan refuses in combat and a half-scanned panel is
-- worse than a panel that says why it is empty. There is no "walk now" button:
-- `/lootpath capture journal` is still the only thing that produces a walk, and
-- putting one behind a button is its own decision (it moves the Adventure
-- Guide's view state and takes seconds), which M3-4 is what settles.
function Panel.Gather(opts)
    opts = opts or {}
    local snapshot = opts.snapshot or Panel.LatestWalk(opts.db)
    local sources, summary
    if snapshot then
        sources, summary = ns.Journal:Build({ snapshot = snapshot, db = opts.db })
    end
    local inventory = ns.Inventory.Scan()
    return {
        sources = sources,
        summary = type(summary) == "table" and summary.ok and summary or nil,
        inventory = inventory.ok and inventory or nil,
        verdict = activeVerdict(),
        difficultyIDs = opts.difficultyIDs,
        inCombat = inventory.ok ~= true and inventory.reason == "combat" or nil,
    }
end

function Panel.Create(parent)
    local frame = CreateFrame("Frame", "LootpathUpgradeMapPanel", parent or UIParent)
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:Hide()

    frame.header = fontString(frame, "GameFontNormal")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetText("Upgrade Map")

    frame.note = fontString(frame, "GameFontNormalSmall")
    frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
    frame.note:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame.note:SetText(Panel.NOTE)

    frame.filterLabel = fontString(frame)
    frame.filterLabel:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -8)
    frame.filterLabel:SetText("Difficulty:")

    frame.filterButtons = {}
    frame.difficultyIDs = nil

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame.filterLabel, "BOTTOMLEFT", 0, -24)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 4)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(PANEL_WIDTH - 40, PANEL_HEIGHT - 90)
    frame.scroll:SetScrollChild(frame.content)
    frame.rows = {}

    frame.Refresh = Panel.Refresh
    Panel.frame = frame
    return frame
end

local function filterButton(frame, index)
    local button = frame.filterButtons[index]
    if not button then
        button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(120, 20)
        if index == 1 then
            button:SetPoint("LEFT", frame.filterLabel, "RIGHT", 6, 0)
        else
            button:SetPoint("LEFT", frame.filterButtons[index - 1], "RIGHT", 4, 0)
        end
        frame.filterButtons[index] = button
    end
    button:Show()
    return button
end

local function row(frame, index)
    local text = frame.rows[index]
    if not text then
        text = fontString(frame.content)
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

-- Rebuilds the panel from the client. `self` is the frame Create returned.
function Panel.Refresh(self, opts)
    self = self or Panel.frame
    if not self then
        return nil
    end
    opts = opts or {}
    opts.difficultyIDs = opts.difficultyIDs or self.difficultyIDs
    local gathered = Panel.Gather(opts)
    local model = Panel.Model(gathered)
    self.model = model
    self.difficultyIDs = opts.difficultyIDs

    local index = 0
    for _, difficulty in ipairs(model.difficulties) do
        index = index + 1
        local button = filterButton(self, index)
        button:SetText(string.format("%s (%d)", difficulty.label, difficulty.count))
        button:SetScript("OnClick", function()
            self.difficultyIDs = { difficulty.difficultyID }
            Panel.Refresh(self)
        end)
    end
    index = index + 1
    local all = filterButton(self, index)
    all:SetText("All")
    all:SetScript("OnClick", function()
        self.difficultyIDs = nil
        Panel.Refresh(self)
    end)
    for i = index + 1, #self.filterButtons do
        self.filterButtons[i]:Hide()
    end

    local lines = Panel.Lines(model)
    if gathered.inCombat then
        lines = { Panel.NOTE, "Lootpath does not read the client in combat. Leave combat and reopen this panel." }
    end
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
