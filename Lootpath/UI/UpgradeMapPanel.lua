-- Lootpath/UI/UpgradeMapPanel.lua (M3-3, WKE-524)
-- The second promise: for each gear slot, what you are wearing and which boss
-- drops a candidate, at what item level, from the Encounter Journal walk.
--
-- THE RULE THIS FILE EXISTS TO KEEP (decision 2026-09-05, option A):
-- a candidate shows a number only where QE Live has ranked THAT EXACT ITEM, and
-- every other candidate shows where it drops and at what item level and nothing
-- about how good it is. There are now exactly two paths to a number here, and
-- both are QE Live's own, transported unchanged:
--   `row.value`   - the Top Gear verdict covers this item KEY (itemID + bonus
--                   IDs). That is the vault and the gear you own.
--   `row.upgradeValue` - an Upgrade Finder export (M3-6, WKE-535) ranks this
--                   itemID AT THIS ITEM LEVEL. That is the drop you do not own.
--                   Since M3-10 (WKE-545) "an export" is EVERY Upgrade Finder
--                   document stored for the content type, because the companion
--                   writes one per Mythic+ key level: the row takes its number
--                   from whichever document carries this exact itemID at this
--                   exact item level, and says which one that was. Still exact
--                   on both keys inside one document - nothing is interpolated
--                   between two of them, and no key level is inferred here.
-- `row.value` is nil unless `row.qe` is, `row.upgradeValue` is nil unless
-- `row.upgrade` is, and there is no third path. A row QE Live ranked at ANOTHER
-- item level gets no number at all - it is counted, not estimated. If a gap
-- tempts you to estimate, stop.
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

-- The item widget every tab draws an item with (M5-1, UI/ItemLine.lua), which
-- the .toc loads before this file.
local UI = ns.UI

-- Pinned wording (decision 2026-09-05). A test asserts this string exactly.
Panel.NOTE = "Values shown are QE Live's, for items it has ranked. Other drops are listed by item level only."

-- Pinned too, because getting it wrong is the one way this panel can lie about
-- an item: a row the client had not sent yet is unknown, never zero.
Panel.PENDING_NOTE = "%d drops are not identified yet: their item data had not arrived. Unknown, not item level 0."

Panel.EMPTY_NOTE = "No loot map yet. Run /lootpath capture journal out of combat to walk the Adventure Guide."

-- An Upgrade Finder document values a drop at the item level ITS OWN settings
-- assume - his +10 dungeon rows come back at 311/321/334 - while the walk lists
-- whatever level the Adventure Guide previews (305 at keystone 10). Since
-- M3-10 every stored document is asked, so this counts the rows NO document
-- carries at the walk's level, which is a narrower and more honest figure than
-- it was: the owner can see the remaining disagreement rather than wonder why
-- an import changed nothing (ARCHITECTURE.md 11).
Panel.LEVEL_MISMATCH_NOTE = "%d drops are ranked by QE Live at another item level, so they show no value."

-- The Adventure Guide lists cosmetic and quest drops beside real loot, and
-- C_Item.GetDetailedItemLevelInfo answers 1 for them: measured over the
-- 2026-09-06 20:09 transcript, 87 rows of the cold walk's final read and 86 of
-- the warm one came back {1, false, 1} (e.g. Hex Lord's Gaze, itemID 275938),
-- of which 6 and 5 respectively were gear and reached a slot, sorting to the
-- bottom of it. The owner's decision (WKE-530) is to hide them and say how
-- many, because 1 is the CLIENT's own figure - hiding on it is a filter on a
-- fact, not an estimate this addon made. Exactly 1 and no other threshold: a
-- row at 44 is real loot and stays. Pending rows are untouched, because their
-- level is unknown rather than 1 (see PENDING_NOTE).
Panel.HIDDEN_ITEM_LEVEL = 1
Panel.LEVEL_ONE_NOTE = "%d drops at item level 1 hidden: cosmetic and quest items"

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

-- One label per difficulty in a map, and no two the same.
--
-- GetDifficultyInfo hands back the bare localised word for dungeon Heroic (2)
-- and raid Heroic (15) alike, and for dungeon Mythic (23) and raid Mythic (16)
-- alike. Measured in game 2026-09-06 (WKE-530 finding 1): the filter row read
-- "Heroic (67)", "Mythic Keystone 10 (54)", "Heroic (38)", "Mythic (39)" - two
-- pairs of buttons that named different content identically. So when two IDs in
-- the SAME map answer to one name, both fall back to Panel.DIFFICULTY_NAME,
-- which already carries the qualified forms; a name nothing else shares keeps
-- the client's own localised word, which is the reason to prefer it.
--
-- The set is the whole map's difficulties, not the filtered subset, so clicking
-- a filter never renames the buttons.
function Panel.DifficultyLabels(difficultyIDs, previewMythicPlusLevel)
    local ids, labels, sharing = {}, {}, {}
    for _, id in ipairs(difficultyIDs or {}) do
        if labels[id] == nil then
            ids[#ids + 1] = id
            local name = Panel.DifficultyLabel(id, nil)
            labels[id] = name
            local list = sharing[name] or {}
            sharing[name] = list
            list[#list + 1] = id
        end
    end
    table.sort(ids)
    for _, shared in pairs(sharing) do
        if #shared > 1 then
            for _, id in ipairs(shared) do
                -- Every member of a colliding group is qualified, so the row
                -- that has a fallback name and the row that does not never end
                -- up as "Brutal" beside "Brutal (difficulty 901)".
                labels[id] = Panel.DIFFICULTY_NAME[id] or string.format("%s (difficulty %d)", labels[id], id)
            end
        end
    end
    -- The qualified fallbacks are unique on this client's five difficulties,
    -- and nothing promises that of a client with others, so the ID itself is
    -- the last word. Sorted, so the same map always labels the same way.
    local taken = {}
    for _, id in ipairs(ids) do
        if taken[labels[id]] then
            labels[id] = string.format("%s (difficulty %d)", labels[id], id)
        end
        taken[labels[id]] = true
    end
    -- The M+ row is the only one whose item levels mean nothing without the
    -- keystone level the walk previewed, so that number stays part of its label.
    local mythicPlus = mythicPlusDifficulty()
    if labels[mythicPlus] and previewMythicPlusLevel then
        labels[mythicPlus] = string.format("%s %d", labels[mythicPlus], previewMythicPlusLevel)
    end
    return labels
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
--
-- `prefix` names who is speaking and defaults to "QE Live", which is still the
-- only answer this function ever renders. The Vault tab passes a scenario's name
-- instead (C-6, WKE-540): there the whole panel is his, and what each line has
-- to say is WHICH of the three questions it answers.
-- Since M5-3 this is the text half of Panel.ValueBadge below, so the words on
-- a drawn badge and the words `/lootpath status` prints cannot drift apart:
-- there is one place they are written.
function Panel.ValueText(coverage, prefix)
    local badge = Panel.ValueBadge(coverage, prefix)
    return badge and badge.text or nil
end

-- The same sentence as a badge: the words, and which of QE Live's two tones
-- they are his verdict in. `better` and `worse` are his own colours (M5-1);
-- anything that is not one of his verdicts stays grey, because inventing a
-- third colour of his would be inventing. A top-set item is `neutral` for
-- exactly that reason - it carries no delta, so it is a status word rather
-- than a number of his to colour.
function Panel.ValueBadge(coverage, prefix)
    if type(coverage) ~= "table" then
        return nil
    end
    local who = type(prefix) == "string" and prefix or "QE Live"
    if coverage.where == "topSet" then
        return { text = who .. ": in your best set", tone = "neutral" }
    end
    local percent = tonumber(coverage.scorePercent)
    local hps = tonumber(coverage.hpsDifference)
    if not percent then
        return { text = who .. ": ranked, no delta given", tone = "none" }
    end
    local direction = coverage.isBetter and "better" or "worse"
    if hps then
        return {
            text = string.format("%s: %s by %.2f%% (%+.1f score)", who, direction, math.abs(percent), hps),
            tone = direction,
        }
    end
    return { text = string.format("%s: %s by %.2f%%", who, direction, math.abs(percent)), tone = direction }
end

-- The line an Upgrade-Finder-ranked row shows. QE Live's percentage, his sign,
-- his magnitude; the direction word is read from ns.UFImport.IsUpgrade rather
-- than from arithmetic here, because his two exports disagree about what a
-- positive number means and this is the file that could get it backwards.
--
-- `hpsGain` is NOT shown. It is carried in the model because it is his number,
-- but the Upgrade Finder's own report offers percent or HPS as alternative
-- metrics and the panel picks the one that needs no explanation. See
-- ARCHITECTURE.md 9 for what hpsGain actually is - unlike Top Gear's
-- TopGearEngineShared arithmetic, UpgradeFinderEngine DOES scale it by the
-- player's modelled HPS - and it is the owner's call whether it reaches a row.
-- `keyLevel` is the Mythic+ key of the DOCUMENT the number came from, and it is
-- part of the sentence rather than a footnote: since M3-10 the rows on one
-- screen can be valued by different documents, and a percentage whose run is
-- not named is a number the reader cannot check.
--
-- Since M5-3 the sentence is assembled from Panel.UpgradeBadge below: the same
-- words in the same order, split where the drawn row splits them - his verdict
-- in the badge, the document's key level in grey after it. A line and a badge
-- that disagreed about a number would be two answers to one question, so there
-- is one place the words are written and this is the join of it.
function Panel.UpgradeText(entry, keyLevel)
    local badge = Panel.UpgradeBadge(entry, keyLevel)
    if not badge then
        return nil
    end
    if badge.note then
        return badge.text .. " " .. badge.note
    end
    return badge.text
end

-- `text` is his verdict, `note` is the grey "(at +6)" that names WHICH stored
-- document said it, and `tone` is which of his two colours the verdict is in.
-- A zero and a missing number are both grey: neither is a direction he gave.
function Panel.UpgradeBadge(entry, keyLevel)
    if type(entry) ~= "table" then
        return nil
    end
    local label = ns.UFImport.KeyLabel(keyLevel)
    local note = label and string.format("(at %s)", label) or nil
    local percent = tonumber(entry.upgradePercent)
    if not percent then
        return { text = "QE Live: ranked, no value given", note = note, tone = "none" }
    end
    if percent == 0 then
        -- 94 of the 357 drops in the 2026-09-07 Dungeon export sit here. "No
        -- change" is what his zero says; "worse by 0.00%" would be this panel
        -- inventing a direction he did not give.
        return { text = "QE Live: no change", note = note, tone = "none" }
    end
    local direction = ns.UFImport.IsUpgrade(entry) and "better" or "worse"
    return {
        text = string.format("QE Live: %s by %.2f%%", direction, math.abs(percent)),
        note = note,
        tone = direction,
    }
end

-- The Upgrade Finder documents a model was handed, always as a list, so there
-- is ONE join below rather than a single-document path beside a several-document
-- one. A paste really is one document, and one that does not name its key level
-- at that; the companion writes one per level. `opts.upgrades` is that single
-- document, kept because a caller with one verdict in hand should not have to
-- wrap it to ask a question about it.
function Panel.UpgradeDocuments(opts)
    local documents = opts.upgradeDocuments
    if type(documents) == "table" and #documents > 0 then
        return documents
    end
    if opts.upgrades then
        return { { verdict = opts.upgrades, keyLevel = ns.UFImport.KeyLevelOf(opts.upgrades) } }
    end
    return {}
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

-- One journal entry as a candidate row, without any number on it. Both views
-- build their rows here, so a row means the same thing in the slot view and in
-- the run view and neither can drift into saying something the other does not.
local function candidateRow(itemID, entry, owned, difficultyLabels, previewLevel)
    local ownedRecord = owned[itemID]
    return {
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
        difficultyLabel = difficultyLabels[entry.difficultyID]
            or Panel.DifficultyLabel(entry.difficultyID, previewLevel),
        owned = ownedRecord ~= nil or nil,
        ownedItemLevel = ownedRecord and ownedRecord.itemLevel or nil,
        -- What the drawn row needs and the printed line does not (M5-3): the
        -- icon the walk recorded off the journal's own loot row, and the art
        -- the Adventure Guide draws this instance with. Both are the client's
        -- file IDs, carried; nil on a walk taken before they were recorded.
        icon = entry.icon,
        instanceImage = entry.instanceImage,
    }
end

-- The second line of a drawn item row: where the drop comes from, in the
-- order the mockup reads it - boss first, because that is what the reader is
-- choosing between once the slot is settled. The printed line keeps its own
-- "instance - boss" order (Panel.Lines below), which is what /lootpath status
-- and every render test read; this is the same three facts, laid out for a
-- row that already has the item's name above it.
function Panel.SourceSecondText(row)
    local instance = row.instanceName or ("Instance " .. tostring(row.instanceID))
    local where = instance
    if row.encounterName then
        where = string.format("%s - %s", row.encounterName, instance)
    elseif row.encounterID then
        where = string.format("encounter %s - %s", tostring(row.encounterID), instance)
    end
    if row.difficultyLabel then
        return string.format("%s, %s", where, row.difficultyLabel)
    end
    return where
end

-- Everything a drawn row shows that is not the item itself, filled in once
-- the row's two possible numbers are known. Nothing new is computed here: the
-- badge is one of QE Live's own sentences, the tag is the ownership fact the
-- printed line writes as "[owned 305]", and the second line is the source.
--
-- A row can carry BOTH of his numbers at once (you own a copy of a drop AND an
-- Upgrade Finder document ranks the drop). There is one badge, so the Upgrade
-- Finder verdict takes it - it is the one about THIS drop at THIS item level -
-- and the Top Gear sentence joins the second line rather than being dropped.
function Panel.FinishRow(row)
    local second = Panel.SourceSecondText(row)
    local badge = row.upgrade and Panel.UpgradeBadge(row.upgrade, row.upgradeKeyLevel) or nil
    if badge then
        if row.value then
            second = second .. " - " .. row.value
        end
    else
        badge = row.qe and Panel.ValueBadge(row.qe) or nil
    end
    row.second = second
    row.badge = badge
    row.keyLabel = ns.UFImport.KeyLabel(row.upgradeKeyLevel)
    if row.owned then
        row.tags = { "owned" }
    end
    return row
end

-- Which difficulties a map holds and how many rows each carries. The counts are
-- of the WHOLE map, before any filter, so clicking a filter never renames or
-- renumbers a button. Shared by both views for exactly that reason.
local function difficultySurvey(sources, itemIDs)
    local counts, ids = {}, {}
    for _, itemID in ipairs(itemIDs) do
        for _, entry in ipairs(sources[itemID]) do
            if counts[entry.difficultyID] == nil then
                ids[#ids + 1] = entry.difficultyID
            end
            counts[entry.difficultyID] = (counts[entry.difficultyID] or 0) + 1
        end
    end
    return counts, ids
end

local function difficultyList(counts, labels, wanted, previewLevel)
    local ids, list = {}, {}
    for id in pairs(counts) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        list[#list + 1] = {
            difficultyID = id,
            label = labels[id] or Panel.DifficultyLabel(id, previewLevel),
            count = counts[id],
            selected = (not wanted) or wanted[id] == true,
        }
    end
    return list
end

-- Model(opts) -> the whole panel as plain data, so every rule above is a test
-- over fixtures rather than a claim about frames.
--
-- opts.sources     ns.Journal:Build's map (required for candidates)
-- opts.summary     its summary (previewMythicPlusLevel is read from here)
-- opts.inventory   ns.Inventory.Scan's result
-- opts.verdict     ns.QEImport.Current()      (Top Gear)
-- opts.upgradeDocuments  ns.UFImport.Documents(contentType)  (M3-10, WKE-545)
-- opts.upgrades    one Upgrade Finder verdict, when that is all the caller has
-- opts.difficultyIDs  show only these difficulties (nil or empty = all)
function Panel.Model(opts)
    opts = opts or {}
    local sources = opts.sources or {}
    local summary = opts.summary or {}
    local verdict = opts.verdict
    local documents = Panel.UpgradeDocuments(opts)
    local previewLevel = opts.previewMythicPlusLevel or summary.previewMythicPlusLevel

    local wanted
    for _, id in ipairs(opts.difficultyIDs or {}) do
        wanted = wanted or {}
        wanted[id] = true
    end

    local owned = ownedByItemID(opts.inventory)
    local bySlot, pendingRows, hiddenBySlot = {}, {}, {}
    -- itemID -> { itemID, itemLevel, rankedLevels, rows }, for drops the
    -- Upgrade Finder ranked at some OTHER item level. Deduplicated, so the list
    -- is one entry per drop and counts.rankedAtAnotherLevel is one per row.
    local mismatches, mismatchOrder = {}, {}
    local difficultyCounts
    local model = {
        -- The model keeps the pinned note so a headless test can read it; the
        -- frame prints it once, in its header, and Lines does NOT repeat it
        -- (WKE-530 finding 3).
        note = Panel.NOTE,
        previewMythicPlusLevel = previewLevel,
        upgradeDocuments = documents,
        upgradeDocumentsNote = ns.UFImport.DocumentsNote(documents),
        hasMap = false,
        hasVerdict = verdict ~= nil,
        hasUpgrades = #documents > 0,
        slots = {},
        difficulties = {},
        pending = { count = 0, rows = pendingRows },
        upgradeLevelMismatches = {},
        counts = {
            candidates = 0,
            covered = 0,
            owned = 0,
            slots = 0,
            hiddenLevelOne = 0,
            ranked = 0,
            rankedAtAnotherLevel = 0,
            upgradeDocuments = #documents,
        },
    }

    local itemIDs = {}
    for itemID in pairs(sources) do
        model.hasMap = true
        itemIDs[#itemIDs + 1] = itemID
    end
    table.sort(itemIDs)

    -- First pass: which difficulties this map holds, and how many rows each
    -- one carries. The counts are of the WHOLE map, before any filter, and the
    -- labels are made unique against each other here rather than row by row, so
    -- that two difficulties the client names identically end up on two
    -- different buttons (finding 1).
    local difficultyIDs
    difficultyCounts, difficultyIDs = difficultySurvey(sources, itemIDs)
    local difficultyLabels = Panel.DifficultyLabels(difficultyIDs, previewLevel)

    for _, itemID in ipairs(itemIDs) do
        for _, entry in ipairs(sources[itemID]) do
            if not wanted or wanted[entry.difficultyID] then
                local row = candidateRow(itemID, entry, owned, difficultyLabels, previewLevel)
                -- The only path to a number on a candidate row. `qe` is nil
                -- whenever the verdict does not carry this exact key, and
                -- `value` is nil whenever `qe` is.
                row.qe = entry.itemKey and ns.QEImport.Coverage(verdict, entry.itemKey) or nil
                row.value = row.qe and Panel.ValueText(row.qe) or nil
                -- The second path, and the only one that reaches a drop the
                -- character does not own: one of QE Live's Upgrade Finder
                -- documents ranks this itemID AT THIS ITEM LEVEL. A row with no
                -- item level (pending) is never joined, because there is
                -- nothing to join on - the level is unknown, not wrong.
                if #documents > 0 and row.itemLevel then
                    local ranked, keyLevel, pick = ns.UFImport.LookupAcrossLevels(documents, row.itemID, row.itemLevel)
                    if ranked then
                        row.upgrade = ranked
                        row.upgradeKeyLevel = keyLevel
                        row.upgradeKeyPick = pick
                        row.upgradeValue = Panel.UpgradeText(ranked, keyLevel)
                        model.counts.ranked = model.counts.ranked + 1
                    else
                        local levels = ns.UFImport.LevelsAcrossLevels(documents, row.itemID)
                        if levels and #levels > 0 then
                            row.rankedAtAnotherLevel = levels
                            model.counts.rankedAtAnotherLevel = model.counts.rankedAtAnotherLevel + 1
                            local seen = mismatches[itemID]
                            if seen then
                                seen.rows = seen.rows + 1
                            else
                                mismatches[itemID] = {
                                    itemID = itemID,
                                    itemLevel = row.itemLevel,
                                    rankedLevels = levels,
                                    rows = 1,
                                }
                                mismatchOrder[#mismatchOrder + 1] = itemID
                            end
                        end
                    end
                end
                Panel.FinishRow(row)
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
                    -- is listed as unknown rather than as a zero. A pending row
                    -- is never hidden below: unknown is not item level 1.
                    pendingRows[#pendingRows + 1] = row
                elseif row.itemLevel == Panel.HIDDEN_ITEM_LEVEL then
                    -- Hidden, and counted so the slot can say so (finding 4).
                    -- It is still a candidate in model.counts, because the map
                    -- keeps the fact; only this panel declines to list it.
                    hiddenBySlot[row.slot] = (hiddenBySlot[row.slot] or 0) + 1
                    model.counts.hiddenLevelOne = model.counts.hiddenLevelOne + 1
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

    -- itemIDs are walked in sorted order above, so this list is already stable.
    for _, itemID in ipairs(mismatchOrder) do
        model.upgradeLevelMismatches[#model.upgradeLevelMismatches + 1] = mismatches[itemID]
    end
    if model.counts.rankedAtAnotherLevel > 0 then
        model.levelMismatchNote = string.format(Panel.LEVEL_MISMATCH_NOTE, model.counts.rankedAtAnotherLevel)
    end

    local equipped = equippedBySlot(opts.inventory)
    for _, slot in ipairs(Panel.SLOT_ORDER) do
        local candidates = bySlot[slot]
        local worn = equipped[slot]
        local hidden = hiddenBySlot[slot] or 0
        if candidates or worn or hidden > 0 then
            sortCandidates(candidates or {})
            model.slots[#model.slots + 1] = {
                slot = slot,
                equipped = worn or {},
                -- The one the section header is drawn with (M5-3). Finger and
                -- Trinket have two; the header shows the first, and both stay
                -- in `equipped` where the printed lines list them.
                worn = worn and worn[1] or nil,
                candidates = candidates or {},
                hiddenLevelOne = hidden,
                hiddenNote = hidden > 0 and string.format(Panel.LEVEL_ONE_NOTE, hidden) or nil,
            }
            model.counts.slots = model.counts.slots + 1
        end
    end

    model.difficulties = difficultyList(difficultyCounts, difficultyLabels, wanted, previewLevel)

    -- Roads (R-3, WKE-564). A road is a way into a slot, and the set group of
    -- one is the plan's own answer for it, so the roads are built only when the
    -- caller has said which plans are stored: with no plan there is no set
    -- group, and the tab is exactly the list M5-3 shipped. `Panel.Gather` always
    -- hands the scenarios over, so in the client the roads are always there.
    local scenarios = type(opts.scenarios) == "table" and opts.scenarios or {}
    if #scenarios > 0 then
        -- The difficulty dropdown narrows the roads exactly as it narrows the
        -- candidates above: a reader who filtered to one difficulty is asking
        -- one question, and a road from a difficulty they filtered out would be
        -- a second answer to it.
        local roadSources = sources
        if wanted then
            roadSources = {}
            for _, itemID in ipairs(itemIDs) do
                local kept = {}
                for _, entry in ipairs(sources[itemID]) do
                    if wanted[entry.difficultyID] then
                        kept[#kept + 1] = entry
                    end
                end
                if #kept > 0 then
                    roadSources[itemID] = kept
                end
            end
        end
        local inputs = Panel.RoadInputs(opts, {
            ufDocuments = documents,
            sources = roadSources,
            difficultyLabels = difficultyLabels,
        })
        model.hasRoads = true
        model.roadInputs = inputs
        model.chargeText = ns.Roads.ChargeText(ns.Roads.Charge(opts.currencies))
        for _, section in ipairs(model.slots) do
            section.roads = ns.Roads.ForSlot(section.slot, inputs)
            -- The slot's own line, in the same voice as the week's: built from
            -- the slot's roads, so the header and the rows cannot disagree.
            section.plan = section.roads.plan
            section.roadGroups = Panel.RoadGroups(section.roads, previewLevel)
        end
    end
    return model
end

-- The model as display lines, which is what the frames put on screen and what
-- the render tests read. Keeping it a pure function is what lets a test prove
-- that an uncovered candidate renders no number at all.
--
-- The pinned note is NOT one of these lines. The panel header draws it once,
-- above the list, and until WKE-530 the list printed it again as its first row
-- - seen in game 2026-09-06 on both this tab and the Vault tab. The model still
-- carries `note` for the headless tests that pin the wording.
function Panel.Lines(model)
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end
    if not model.hasMap then
        add(Panel.EMPTY_NOTE)
        return lines
    end
    if not model.hasVerdict then
        add("No QE Live import yet, so no drop carries a value. Paste a Top Gear export to change that.")
    end
    -- Which Upgrade Finder documents these rows were joined against (M3-10).
    -- Above the rows, because it is true of all of them; which document a
    -- particular row's number came from is on the row itself.
    if model.upgradeDocumentsNote then
        add(model.upgradeDocumentsNote)
    end
    for _, section in ipairs(model.slots) do
        add(section.slot)
        for _, record in ipairs(section.equipped) do
            add(string.format("  equipped: %s (%s)", record.name or record.link or "?", tostring(record.itemLevel)))
        end
        -- Roads (R-3). When the slot has them they ARE the slot's rows, here
        -- and on screen: the same sentence, the same three headers, the same
        -- rows in the same order, so the printed and the drawn views cannot
        -- drift. The candidate list below is what a map with no stored plan
        -- still prints.
        if section.roadGroups then
            if section.plan then
                add("  " .. section.plan)
            end
            for _, group in ipairs(section.roadGroups) do
                add("  " .. group.header)
                for _, row in ipairs(group.rows) do
                    add("    " .. Panel.RoadLineText(row))
                end
            end
        else
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
                -- Both numbers can be true of one row at once (you own a copy
                -- of a drop AND QE Live ranked the drop), and neither is
                -- derived from the other, so both are shown rather than one
                -- being picked.
                if row.upgradeValue then
                    text = text .. " - " .. row.upgradeValue
                end
                add(text)
            end
        end
        -- The one thing neither list carries, said the way it always was
        -- (WKE-530 finding 4).
        if section.hiddenNote then
            add("  " .. section.hiddenNote)
        end
    end
    if model.levelMismatchNote then
        add(model.levelMismatchNote)
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
-- The by-run view (M3-8, WKE-542).
--
-- The slot view above answers "what could fill this slot". The owner's question
-- on the first day of real use was a different one: "what would be the best run
-- for me to do right now". That is this view, and it is a second model over the
-- SAME two inputs - the journal walk and QE Live's Upgrade Finder export - with
-- no new number of its own.
--
-- THE RULE, stated before the sorting: ranking runs by QE Live's own
-- `upgradePercent`, and counting how many of a run's drops carry a positive one
-- out of how many drops the journal lists, are display over his numbers and the
-- client's facts. A probability-weighted "expected upgrade" is NOT: the
-- Adventure Guide gives no drop rates, "1 in N" would be Lootpath's own
-- assumption, and multiplying his number by it would produce a number he never
-- gave. So the two rankings the owner named are offered as facts side by side -
-- the best single upgrade, and the count of rated upgrades over the run's whole
-- drop list - and the reader judges the odds. RUN_NOTE says so on screen.
Panel.MODE_SLOT = "slot"
Panel.MODE_RUN = "run"
Panel.MODE_LABEL = { [Panel.MODE_SLOT] = "By slot", [Panel.MODE_RUN] = "By run" }

Panel.SORT_BEST = "best"
Panel.SORT_COUNT = "count"
Panel.SORT_LABEL = { [Panel.SORT_BEST] = "best upgrade", [Panel.SORT_COUNT] = "most upgrades" }
Panel.SORTS = { Panel.SORT_BEST, Panel.SORT_COUNT }
Panel.MODES = { Panel.MODE_SLOT, Panel.MODE_RUN }

Panel.RUN_NOTE = "Two facts side by side: QE Live's best single upgrade in a run, and how many of that run's drops he "
    .. "rates as upgrades. Neither is weighted by drop chance - the Adventure Guide gives none, and Lootpath will not "
    .. "invent one - so the odds are yours to judge."

Panel.RUN_NO_IMPORT_NOTE =
    "No QE Live Upgrade Finder import yet, so no run can be ranked. Paste an Upgrade Finder export to change that."

-- The denominator is every drop the journal lists for the run, so the reader
-- can see how thin a "best upgrade" is spread.
Panel.RUN_COUNT_TEXT = "%d of %d drops rated upgrades"
Panel.RUN_NO_UPGRADE_TEXT = "no drop rated by QE Live yet"

Panel.RUN_HEADLINE_BEST = "Best run right now (by best upgrade): %s - %+.2f%% for %s."
Panel.RUN_HEADLINE_COUNT = "Best run right now (by most upgrades): %s - %s."
Panel.RUN_HEADLINE_NONE = "No run in this map has a drop QE Live rates as an upgrade."

-- One key level exists today: the one the walk previewed. The companion now
-- asks QE Live at several of them (C-7) and each drop is valued by whichever
-- document carries it at the level the walk lists (M3-10), but the WALK is
-- still a single preview level, so a Mythic Keystone run is still shown at that
-- one level. This line says which, rather than inventing item levels for the
-- others; a walk per key level is its own question (ARCHITECTURE.md 11).
Panel.KEY_LEVEL_NOTE = "Mythic Keystone runs are shown at key %s, which is what the walk previewed. "
    .. "A key level with no walk and no QE Live export of its own is not shown."

-- The keystone level a run's item levels mean nothing without. Only the Mythic
-- Keystone difficulty has one, and it comes from the entry itself when the
-- entry carries one - the field a walk of several key levels will set (WKE-543)
-- - and from the walk's single previewed level otherwise, which is every walk
-- that exists today.
function Panel.RunKeyLevel(difficultyID, previewMythicPlusLevel, entry)
    if difficultyID ~= mythicPlusDifficulty() then
        return nil
    end
    local own = entry and tonumber(entry.mythicPlusLevel)
    return own or previewMythicPlusLevel
end

-- A run is what the owner actually chooses to do: a dungeon at a difficulty
-- (you run the whole dungeon, so every boss in it is one run) or a raid boss at
-- a difficulty (you pick the boss). The key level is part of a Mythic Keystone
-- run's identity, so one dungeon at two key levels is two runs and they sort
-- against each other - the shape WKE-543 fills in.
function Panel.RunKey(entry, keyLevel)
    if entry.isRaid then
        return table.concat({
            "raid",
            tostring(entry.instanceID),
            tostring(entry.encounterID),
            tostring(entry.difficultyID),
        }, ":")
    end
    return table.concat({
        "dungeon",
        tostring(entry.instanceID),
        tostring(entry.difficultyID),
        tostring(keyLevel or "-"),
    }, ":")
end

local function runParts(run)
    local parts = { run.instanceName or ("Instance " .. tostring(run.instanceID)) }
    if run.isRaid then
        parts[#parts + 1] = run.encounterName or ("encounter " .. tostring(run.encounterID))
    end
    parts[#parts + 1] = run.difficultyLabel
    return parts
end

-- The difficulty word plus THIS run's key level, so two key levels of one
-- dungeon read as the two different runs they are. The filter buttons keep the
-- whole map's labels (Panel.DifficultyLabels with the walk's preview level), so
-- the row and the button agree whenever there is only one key level, which is
-- every walk that exists today.
local function runDifficultyLabel(baseLabels, difficultyID, keyLevel)
    local base = baseLabels[difficultyID] or Panel.DifficultyLabel(difficultyID, nil)
    if keyLevel then
        return string.format("%s %d", base, keyLevel)
    end
    return base
end

-- Best first, and then a stable order so the same map always reads the same.
local function sortRunUpgrades(rows)
    table.sort(rows, function(a, b)
        local ap = tonumber(a.upgrade.upgradePercent) or 0
        local bp = tonumber(b.upgrade.upgradePercent) or 0
        if ap ~= bp then
            return ap > bp
        end
        if (a.name or "") ~= (b.name or "") then
            return (a.name or "") < (b.name or "")
        end
        if a.itemID ~= b.itemID then
            return a.itemID < b.itemID
        end
        return (a.encounterID or 0) < (b.encounterID or 0)
    end)
end

-- A run with nothing rated sorts last under BOTH orders, and it needs no clause
-- of its own to do it: only a drop QE Live's own IsUpgrade calls an upgrade is
-- ever counted, so a rated run always has a positive `bestPercent` and a `rated`
-- above zero, and an unrated run loses on the first comparison either way. A
-- guard here that no test could turn red would be a claim rather than a rule.
local function runComparator(sort)
    return function(a, b)
        if sort == Panel.SORT_COUNT then
            if a.rated ~= b.rated then
                return a.rated > b.rated
            end
            if (a.bestPercent or 0) ~= (b.bestPercent or 0) then
                return (a.bestPercent or 0) > (b.bestPercent or 0)
            end
        else
            if (a.bestPercent or 0) ~= (b.bestPercent or 0) then
                return (a.bestPercent or 0) > (b.bestPercent or 0)
            end
            if a.rated ~= b.rated then
                return a.rated > b.rated
            end
        end
        if a.label ~= b.label then
            return a.label < b.label
        end
        return a.key < b.key
    end
end

-- RunModel(opts) takes exactly what Model does, plus opts.runSort, and is pure
-- over it in the same way. It walks `sources` itself rather than regrouping
-- Model's output, because the denominator has to be every drop the journal
-- lists for the run - including the cosmetics the slot view hides and the rows
-- whose item data never arrived - and a filtered list cannot say that.
function Panel.RunModel(opts)
    opts = opts or {}
    local sources = opts.sources or {}
    local summary = opts.summary or {}
    local documents = Panel.UpgradeDocuments(opts)
    local previewLevel = opts.previewMythicPlusLevel or summary.previewMythicPlusLevel
    local sort = (opts.runSort == Panel.SORT_COUNT) and Panel.SORT_COUNT or Panel.SORT_BEST

    local wanted
    for _, id in ipairs(opts.difficultyIDs or {}) do
        wanted = wanted or {}
        wanted[id] = true
    end

    local owned = ownedByItemID(opts.inventory)
    local model = {
        note = Panel.NOTE,
        runNote = Panel.RUN_NOTE,
        mode = Panel.MODE_RUN,
        sort = sort,
        sortLabel = Panel.SORT_LABEL[sort],
        previewMythicPlusLevel = previewLevel,
        upgradeDocuments = documents,
        upgradeDocumentsNote = ns.UFImport.DocumentsNote(documents),
        hasMap = false,
        hasVerdict = opts.verdict ~= nil,
        hasUpgrades = #documents > 0,
        runs = {},
        difficulties = {},
        keyLevels = {},
        counts = { runs = 0, ratedRuns = 0, drops = 0, rated = 0, keyLevels = 0, upgradeDocuments = #documents },
    }

    local itemIDs = {}
    for itemID in pairs(sources) do
        model.hasMap = true
        itemIDs[#itemIDs + 1] = itemID
    end
    table.sort(itemIDs)

    local difficultyCounts, difficultyIDs = difficultySurvey(sources, itemIDs)
    -- Two label sets. The filter buttons keep the whole map's labels, key level
    -- and all, exactly as the slot view draws them; the run rows take the bare
    -- difficulty word and append their OWN key level.
    local difficultyLabels = Panel.DifficultyLabels(difficultyIDs, previewLevel)
    local baseLabels = Panel.DifficultyLabels(difficultyIDs, nil)

    local runs, order, keyLevels = {}, {}, {}
    for _, itemID in ipairs(itemIDs) do
        for _, entry in ipairs(sources[itemID]) do
            if not wanted or wanted[entry.difficultyID] then
                local keyLevel = Panel.RunKeyLevel(entry.difficultyID, previewLevel, entry)
                local key = Panel.RunKey(entry, keyLevel)
                local run = runs[key]
                if not run then
                    run = {
                        key = key,
                        instanceID = entry.instanceID,
                        instanceName = entry.instanceName,
                        encounterID = entry.isRaid and entry.encounterID or nil,
                        encounterName = entry.isRaid and entry.encounterName or nil,
                        difficultyID = entry.difficultyID,
                        difficultyLabel = runDifficultyLabel(baseLabels, entry.difficultyID, keyLevel),
                        isRaid = entry.isRaid == true,
                        keyLevel = keyLevel,
                        -- The art the Adventure Guide draws this instance
                        -- with, for the card's left strip. nil on every walk
                        -- taken before the recording landed, and a card with
                        -- no art draws a plain strip rather than a guess.
                        instanceImage = entry.instanceImage,
                        instanceBackground = entry.instanceBackground,
                        drops = 0,
                        pendingDrops = 0,
                        rated = 0,
                        upgrades = {},
                    }
                    local parts = runParts(run)
                    run.label = table.concat(parts, " - ")
                    run.name = table.concat(parts, ", ")
                    runs[key] = run
                    order[#order + 1] = key
                    if keyLevel and not keyLevels[keyLevel] then
                        keyLevels[keyLevel] = true
                        model.keyLevels[#model.keyLevels + 1] = keyLevel
                        model.counts.keyLevels = model.counts.keyLevels + 1
                    end
                end
                run.drops = run.drops + 1
                model.counts.drops = model.counts.drops + 1
                if entry.pending then
                    run.pendingDrops = run.pendingDrops + 1
                end
                -- The one path to a number here, and it is the slot view's own:
                -- one of QE Live's documents ranked THIS itemID AT THIS item
                -- level, and his own IsUpgrade says the number means better.
                -- Nothing else counts.
                local ranked, upgradeKeyLevel, upgradePick
                if #documents > 0 and entry.itemLevel then
                    ranked, upgradeKeyLevel, upgradePick =
                        ns.UFImport.LookupAcrossLevels(documents, itemID, entry.itemLevel)
                end
                if ranked and ns.UFImport.IsUpgrade(ranked) then
                    local row = candidateRow(itemID, entry, owned, difficultyLabels, previewLevel)
                    row.upgrade = ranked
                    row.upgradeKeyLevel = upgradeKeyLevel
                    row.upgradeKeyPick = upgradePick
                    row.upgradeValue = Panel.UpgradeText(ranked, upgradeKeyLevel)
                    Panel.FinishRow(row)
                    run.rated = run.rated + 1
                    run.upgrades[#run.upgrades + 1] = row
                    model.counts.rated = model.counts.rated + 1
                end
            end
        end
    end

    for _, key in ipairs(order) do
        local run = runs[key]
        sortRunUpgrades(run.upgrades)
        run.best = run.upgrades[1]
        run.bestPercent = run.best and tonumber(run.best.upgrade.upgradePercent) or nil
        run.countText = string.format(Panel.RUN_COUNT_TEXT, run.rated, run.drops)
        if run.best then
            local what = run.best.name or ("item " .. tostring(run.best.itemID))
            if run.best.slot then
                what = what .. ", " .. run.best.slot
            end
            -- His sign, his magnitude, and no direction word: only a drop his
            -- own IsUpgrade calls an upgrade ever reaches this line.
            run.bestText = string.format("best %+.2f%% (%s)", run.bestPercent, what)
            run.text = string.format("%s: %s; %s", run.label, run.bestText, run.countText)
            -- The card's badge, in his gold: only a drop his own IsUpgrade
            -- calls an upgrade ever reaches a run's list, so a run with a best
            -- is a run whose best is better, and there is no other tone to
            -- pick between.
            run.badge = { text = string.format("best %+.2f%%", run.bestPercent), tone = "better" }
            model.counts.ratedRuns = model.counts.ratedRuns + 1
        else
            run.text = string.format("%s: %s; %s", run.label, Panel.RUN_NO_UPGRADE_TEXT, run.countText)
            run.badge = { text = Panel.RUN_NO_UPGRADE_TEXT, tone = "none" }
        end
        model.runs[#model.runs + 1] = run
        model.counts.runs = model.counts.runs + 1
    end
    table.sort(model.runs, runComparator(sort))

    local top = model.runs[1]
    if top and top.best then
        if sort == Panel.SORT_COUNT then
            model.headline = string.format(Panel.RUN_HEADLINE_COUNT, top.name, top.countText)
        else
            model.headline =
                string.format(Panel.RUN_HEADLINE_BEST, top.name, top.bestPercent, top.best.slot or top.best.name)
        end
    elseif model.hasMap then
        model.headline = Panel.RUN_HEADLINE_NONE
    end

    if model.counts.keyLevels > 0 then
        table.sort(model.keyLevels)
        local shown = {}
        for index, level in ipairs(model.keyLevels) do
            shown[index] = tostring(level)
        end
        model.keyLevelNote = string.format(
            Panel.KEY_LEVEL_NOTE,
            string.format("%s %s", #shown == 1 and "level" or "levels", table.concat(shown, ", "))
        )
    end

    model.difficulties = difficultyList(difficultyCounts, difficultyLabels, wanted, previewLevel)
    return model
end

-- The by-run model as display lines. The pinned note is still the header's and
-- is not repeated here (WKE-530 finding 3); RUN_NOTE is not the pinned note and
-- the header does not draw it, so it belongs to the list.
function Panel.RunLines(model)
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end
    if not model.hasMap then
        add(Panel.EMPTY_NOTE)
        return lines
    end
    if model.headline then
        add(model.headline)
    end
    add(Panel.RUN_NOTE)
    if not model.hasUpgrades then
        add(Panel.RUN_NO_IMPORT_NOTE)
    end
    if model.keyLevelNote then
        add(model.keyLevelNote)
    end
    -- The walk's key level is one thing; the keys QE LIVE was run at are
    -- another, and they differ (M3-10: his +10 dungeon rows are 311, the walk's
    -- keystone-10 rows are 305, so it is his +6 document that values them).
    -- Both are said, in that order, rather than one standing for the other.
    if model.upgradeDocumentsNote then
        add(model.upgradeDocumentsNote)
    end
    for _, run in ipairs(model.runs) do
        add(run.text)
        for _, row in ipairs(run.upgrades) do
            local what = row.name or ("item " .. tostring(row.itemID))
            local level = row.slot and string.format("%s, %s", row.slot, tostring(row.itemLevel))
                or tostring(row.itemLevel)
            add(
                string.format(
                    "  %s (%s) - %s - %s",
                    what,
                    level,
                    row.encounterName or row.sourceLabel,
                    row.upgradeValue
                )
            )
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Roads, as the slot's row (R-3, WKE-564; docs/ROADS-UX.md surface 2).
--
-- `ns.Roads.ForSlot` is the model and this is the only thing that turns it into
-- words. Every string a road row shows is the road's own - its tag, its badge,
-- its steps, its "do:" line - or one of the constants below, and nothing here
-- reads a document, joins a key or computes a figure. The three groups are
-- rendered in `ns.Roads.GROUP_ORDER` and never sorted: a whole-set verdict and a
-- per-item percent are two scales (principle 2), so the order of the groups is
-- fixed and is not a ranking.
--
-- NO SOURCE IS NAMED IN ANY STRING BELOW (owner's decision, 2026-09-11,
-- ARCHITECTURE.md 7). The older wording on this tab - Panel.NOTE, the value
-- badges - is 569's (V-1) sweep and is deliberately left alone here; what this
-- issue adds says the rating, its plan and what to do, and names nobody.

Panel.ELEMENT_GROUP = "group"
Panel.ELEMENT_ROAD = "road"

-- The one part of a group header that belongs to THIS surface: the middle
-- group's header already names its scale (ns.Roads.GROUP_HEADER), and the set
-- group's says which plan it is under and how its rows are arranged.
Panel.GROUP_SET_TAIL = "the pick first, then the rated alternatives"
Panel.ROAD_SEPARATOR = " · "

-- The muted second figures a rated row carries, in his own words for them:
-- `bonus` is the upgraded listing and `max` is the track's cap for that run
-- (ns.Roads' `extraLevelLabel`). "upgraded 321 at +0.38%" reads with the "at";
-- "at its cap 334 +4.70%" reads without one, so the label chooses the sentence.
Panel.ROAD_ALSO_AT_TEXT = {
    ["upgraded"] = "%s %d at %s",
    ["at its cap"] = "%s %d %s",
}
Panel.ROAD_ALSO_AT_DEFAULT = "%s %d %s"

-- What a road's second line says about the item on its way in. Every clause is
-- a fact of the road: what it becomes, the level the rating assumed when that is
-- above what it arrives at, and where it drops.
Panel.ROAD_BECOMES_TEXT = "into the tier %s"
Panel.ROAD_UPGRADED_TEXT = "upgraded to %d"
Panel.ROAD_WORN_TEXT = "what you wear now"

-- Explain (principle 11). One plain sentence under the FIRST VISIBLE USE of a
-- system word in the expanded slot, in the note colour, off by default. Each
-- says only what the client says or what the rating names: no cadence, no
-- promise, no deadline, and no source.
Panel.EXPLAIN_WORDS = { "plan", "Catalyst", "crest", "track", "spark", "Bountiful" }
Panel.EXPLAIN = {
    plan = "plan: which assumptions a rating was made under: as offered, catalyzed, this week's plan,"
        .. " everything upgraded.",
    Catalyst = "Catalyst: converts one piece into your tier set and spends one charge.",
    crest = "crest: what an upgrade costs at the upgrade vendor; the type and the cost are not read from the client.",
    track = "track: how far a piece can be upgraded; the client does not say which track an item here is on.",
    spark = "spark: the crafting item a high-level craft needs; its count is not read.",
    Bountiful = "Bountiful: a delve that hands over a better reward; which delves are Bountiful is not read.",
}
-- The one figure an Explain sentence is allowed to carry, because the client
-- answered it: "1 held, 8 max". Absent when no currency read did.
Panel.EXPLAIN_CHARGE = " The client says %s."
Panel.EXPLAIN_TONE = "explain"

-- The sentence for one word, with the client's own charge count behind the
-- Catalyst's when there is one. A word this table does not know has no
-- sentence, which is how a new word reaches the screen unexplained rather than
-- explained wrongly.
function Panel.ExplainText(word, chargeText)
    local sentence = Panel.EXPLAIN[word]
    if not sentence then
        return nil
    end
    if word == "Catalyst" and type(chargeText) == "string" and chargeText ~= "" then
        return sentence .. string.format(Panel.EXPLAIN_CHARGE, chargeText)
    end
    return sentence
end

-- Whether a piece of text uses a word as a word. The frontier pattern is what
-- keeps "crest" out of "crested" and "plan" out of "planned"; the comparison is
-- lowercased so "Catalyst it" and "the catalyzed shoulders" are one word to the
-- reader and one word here.
function Panel.UsesWord(text, word)
    if type(text) ~= "string" or type(word) ~= "string" then
        return false
    end
    return text:lower():find("%f[%a]" .. word:lower() .. "%f[%A]") ~= nil
end

-- The header over a group. The middle and last groups carry exactly what the
-- road model says; the set group's names the plan its rows were read under and
-- how they are arranged, which is true of this surface and of no other.
function Panel.GroupHeaderText(group, plan)
    local head = ns.Roads.GROUP_HEADER[group]
    if not head then
        return nil
    end
    if group ~= ns.Roads.GROUP_SET then
        return head
    end
    local parts = { head }
    if type(plan) == "string" and plan ~= "" then
        parts[#parts + 1] = plan
    end
    parts[#parts + 1] = Panel.GROUP_SET_TAIL
    return table.concat(parts, Panel.ROAD_SEPARATOR)
end

-- The plain name of the plan the slot's set group was read under, off the roads
-- themselves rather than off the setting, so the header and the rows under it
-- can never disagree about which answer is on screen.
function Panel.RoadPlanName(roads)
    for _, road in ipairs(type(roads) == "table" and roads.groups and roads.groups[ns.Roads.GROUP_SET] or {}) do
        if road.plan then
            return road.plan
        end
    end
    return nil
end

-- The row's leading word, with the vault's own "open now" behind it: the vault
-- is open NOW and the countdown is the client's, which is the whole of what
-- principle 5 allows a vault road to say about time.
function Panel.RoadTag(road)
    local tag = type(road) == "table" and road.tag or nil
    if not tag then
        return nil
    end
    if road.openNow then
        return tag .. Panel.ROAD_SEPARATOR .. road.openNow
    end
    return tag
end

-- The grey line under the name: what the item becomes, the level the rating
-- assumed when it is above the level it arrives at, and where it comes from.
function Panel.RoadSecond(road)
    if type(road) ~= "table" then
        return nil
    end
    local parts = {}
    if road.becomes and road.catalyzed then
        parts[#parts + 1] = string.format(Panel.ROAD_BECOMES_TEXT, ns.Roads.SlotWord(road.slot) or "piece")
    end
    local rating = road.rating
    if rating and rating.level and road.arrivesAt and rating.level > road.arrivesAt then
        parts[#parts + 1] = string.format(Panel.ROAD_UPGRADED_TEXT, rating.level)
    end
    if road.kind == ns.Roads.KIND_KEEP then
        parts[#parts + 1] = Panel.ROAD_WORN_TEXT
    end
    if road.source then
        parts[#parts + 1] = Panel.SourceSecondText({
            encounterName = road.source.encounterName,
            encounterID = road.source.encounterID,
            instanceName = road.source.instanceName,
            instanceID = road.source.instanceID,
            difficultyLabel = road.source.difficultyLabel,
        })
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, Panel.ROAD_SEPARATOR)
end

-- Everything muted that rides beside the badge: what a "behind" is measured
-- against, the other item levels this one run values it at, the road that wants
-- the same weekly resource, what the client says you hold and what is not
-- readable, and the client's own countdown. Every entry is the road's own
-- string; nothing here is assembled out of a field name.
function Panel.RoadFacts(road)
    local facts = {}
    if type(road) ~= "table" then
        return facts
    end
    local rating = road.rating
    if rating and rating.referent then
        facts[#facts + 1] = rating.referent
    end
    for _, also in ipairs((rating and rating.alsoAt) or {}) do
        if also.label and also.level and also.badge then
            local shape = Panel.ROAD_ALSO_AT_TEXT[also.label] or Panel.ROAD_ALSO_AT_DEFAULT
            facts[#facts + 1] = string.format(shape, also.label, also.level, also.badge)
        end
    end
    if road.rivalText then
        facts[#facts + 1] = road.rivalText
    end
    for _, text in ipairs(ns.Roads.Facts(road)) do
        facts[#facts + 1] = text
    end
    local reset = ns.Roads.ResetText(road.resetSeconds)
    if reset then
        facts[#facts + 1] = reset
    end
    return facts
end

-- Which of QE Live's two colours the badge is in, by the same rule the rest of
-- this panel uses (Panel.ValueBadge): a verdict that carries no delta is a
-- status word and stays grey, a zero is not a direction, and everything else
-- takes the sign he gave it.
function Panel.RoadBadgeTone(road)
    local rating = type(road) == "table" and road.rating or nil
    if type(rating) ~= "table" or rating.kind == ns.Roads.RATING_NONE then
        return "none"
    end
    if rating.kind == ns.Roads.RATING_SET then
        return rating.inTopSet and "neutral" or "worse"
    end
    local percent = tonumber(rating.percent)
    if not percent or percent == 0 then
        return "none"
    end
    return percent > 0 and "better" or "worse"
end

-- The run a "Show run" goes to, as the by-run view's own key, so the verb can
-- never point at a run that view does not have. nil for a road that is not a
-- drop, which is exactly the set of rows that carry no button.
function Panel.RoadRunKey(road, previewMythicPlusLevel)
    local source = type(road) == "table" and road.source or nil
    if type(source) ~= "table" or source.difficultyID == nil then
        return nil
    end
    return Panel.RunKey(source, Panel.RunKeyLevel(source.difficultyID, previewMythicPlusLevel))
end

-- One road, as the row that is drawn and as the line that is printed. Pure, so
-- "this row has no button" and "this row says exactly these words" are headless
-- assertions.
function Panel.RoadRow(road, previewMythicPlusLevel)
    local facts = Panel.RoadFacts(road)
    local badge = road.rating and road.rating.badge or road.phrase
    local row = {
        road = road,
        kind = road.kind,
        group = road.group,
        slot = road.slot,
        tag = Panel.RoadTag(road),
        planPick = road.planPick == true,
        itemID = road.item and road.item.itemID or nil,
        name = road.item and road.item.name or nil,
        icon = road.item and road.item.icon or nil,
        quality = road.item and road.item.quality or nil,
        itemLevel = road.arrivesAt,
        second = Panel.RoadSecond(road),
        badge = badge and { text = badge, tone = Panel.RoadBadgeTone(road) } or nil,
        facts = facts,
        factsText = #facts > 0 and table.concat(facts, Panel.ROAD_SEPARATOR) or nil,
        todo = road.todo,
        verb = road.verb,
    }
    if road.verb == ns.Roads.VERB_SHOW_RUN then
        row.runKey = Panel.RoadRunKey(road, previewMythicPlusLevel)
        -- A verb that cannot go anywhere is not a verb (principle 9): with no
        -- run to scroll to there is no button, only the words.
        if not row.runKey then
            row.verb = nil
        end
    elseif road.verb == ns.Roads.VERB_SHOW_IN_VAULT then
        row.vaultKey = road.item and road.item.key or road.keys[1] or nil
        if not row.vaultKey then
            row.verb = nil
        end
    end
    return row
end

-- The row as one printed line, so `/lootpath status` and the drawn row read the
-- same strings in the same order and a forbidden word cannot hide in one of
-- them.
function Panel.RoadLineText(row)
    local parts = {}
    if row.tag then
        parts[#parts + 1] = row.tag
    end
    parts[#parts + 1] = string.format("%s (%s)", row.name or ("item " .. tostring(row.itemID)), tostring(row.itemLevel))
    if row.second then
        parts[#parts + 1] = row.second
    end
    if row.badge then
        parts[#parts + 1] = row.badge.text
    end
    if row.factsText then
        parts[#parts + 1] = row.factsText
    end
    if row.todo then
        parts[#parts + 1] = row.todo
    end
    return table.concat(parts, Panel.ROAD_SEPARATOR)
end

-- The slot's roads as the groups a surface walks: three of them, in the model's
-- fixed order, each with its header and its rows. A group with no road is left
-- out entirely rather than headed and empty.
--
-- The one filter is the owner's own (WKE-530 finding 4): a journal drop the
-- client answers item level 1 for is a cosmetic or a quest item, and the
-- section says how many it hid rather than listing them. Nothing else is
-- dropped and nothing is re-sorted.
function Panel.RoadGroups(roads, previewMythicPlusLevel)
    local groups = {}
    if type(roads) ~= "table" or type(roads.groups) ~= "table" then
        return groups
    end
    local plan = Panel.RoadPlanName(roads)
    for _, group in ipairs(ns.Roads.GROUP_ORDER) do
        local rows = {}
        for _, road in ipairs(roads.groups[group] or {}) do
            if not (road.kind == ns.Roads.KIND_DROP and road.arrivesAt == Panel.HIDDEN_ITEM_LEVEL) then
                rows[#rows + 1] = Panel.RoadRow(road, previewMythicPlusLevel)
            end
        end
        if #rows > 0 then
            groups[#groups + 1] = { group = group, header = Panel.GroupHeaderText(group, plan), rows = rows }
        end
    end
    return groups
end

-- How many roads a slot opens onto, over all three groups.
function Panel.RoadCount(groups)
    local count = 0
    for _, group in ipairs(groups or {}) do
        count = count + #group.rows
    end
    return count
end

-- Everything `ns.Roads.ForSlot` and `ns.Roads.PlanSentence` need, gathered from
-- what this panel was already handed. Pure and separate so the Vault tab and
-- the tooltip can be given the same table and cannot end up reading a different
-- week from the one on screen.
function Panel.RoadInputs(opts, extra)
    extra = extra or {}
    local inputs = {
        verdicts = opts.scenarios,
        highlightedScenario = opts.highlightScenario,
        ufDocuments = extra.ufDocuments,
        inventory = opts.inventory,
        vault = opts.vault,
        currencies = opts.currencies,
        journal = { sources = extra.sources, summary = opts.summary },
        difficultyLabels = extra.difficultyLabels,
        excluded = opts.excluded,
        now = opts.now,
    }
    -- The leftover list belongs to the document the roads are read under, and
    -- it travels on that document: taking it from anywhere else would be a
    -- second answer to "was this item left out" (C-10, WKE-567).
    if inputs.excluded == nil then
        local entry = ns.Roads.Plan(inputs)
        inputs.excluded = entry and entry.verdict and entry.verdict.excluded or nil
    end
    return inputs
end

-- ---------------------------------------------------------------------------
-- The list as ELEMENTS (M5-3, WKE-552).
--
-- Panel.Lines and Panel.RunLines above stay exactly what they were: the pure
-- text `/lootpath status` prints and the render tests read. What the panel
-- DRAWS is no longer that text in a column of font strings but a
-- WowScrollBoxList over a data provider, and this is the list it is handed -
-- one entry per row of the list, each naming its kind, its height and the
-- model table it binds. Pure, so which rows a map produces, in what order,
-- collapsed or not, is a headless assertion rather than a claim about frames.
--
-- The heights are here rather than in the frame code because the scroll box
-- asks for an element's extent BEFORE it has a frame for it
-- (ScrollBoxListView's element extent calculator, read under .luals/), so the
-- number has to come from the data.

Panel.ELEMENT_SECTION = "section"
Panel.ELEMENT_ITEM = "item"
Panel.ELEMENT_NOTE = "note"
Panel.ELEMENT_RUN = "run"

Panel.SECTION_HEIGHT = 30
-- A road row is built out of its parts, because a row with a wrapping fact
-- line and a button is twice the height of one with neither and the scroll box
-- asks for the extent before it has a frame to measure.
Panel.GROUP_HEIGHT = 20
Panel.ROAD_TAG_HEIGHT = 14
Panel.ROAD_ITEM_HEIGHT = 38
Panel.ROAD_TODO_HEIGHT = 14
Panel.ROAD_VERB_HEIGHT = 22
Panel.ROAD_PADDING = 6
-- The item line's own icon (M5-1) plus the gap under it.
Panel.ITEM_HEIGHT = 42
Panel.NOTE_LINE_HEIGHT = 14
Panel.RUN_HEIGHT = 46
-- Roughly how many characters of the panel's note font fit one line at the
-- window's width. Headless there is no font to ask, and a note that wraps to
-- three lines in a one-line slot is the one way this list can overlap itself,
-- so the estimate is deliberate and generous rather than absent.
Panel.NOTE_CHARS_PER_LINE = 78

-- The rows whose item data never arrived get a section of their own, headed
-- by the same words the printed list heads them with.
Panel.PENDING_SECTION = "Unidentified drops"

function Panel.NoteHeight(text)
    local lines = math.max(1, math.ceil(#tostring(text or "") / Panel.NOTE_CHARS_PER_LINE))
    return lines * Panel.NOTE_LINE_HEIGHT + 4
end

-- A slot header is the worn item plus, since R-3, the slot's own plan sentence
-- under it. A slot with no sentence is the header M5-3 shipped, exactly.
function Panel.SectionHeight(plan)
    if type(plan) ~= "string" or plan == "" then
        return Panel.SECTION_HEIGHT
    end
    return Panel.SECTION_HEIGHT + Panel.NoteHeight(plan)
end

function Panel.GroupHeight(text)
    return math.max(Panel.GROUP_HEIGHT, Panel.NoteHeight(text))
end

function Panel.RoadHeight(row)
    local height = Panel.ROAD_TAG_HEIGHT + Panel.ROAD_ITEM_HEIGHT + Panel.ROAD_PADDING
    if row.factsText then
        height = height + Panel.NoteHeight(row.factsText)
    end
    if row.todo then
        height = height + Panel.ROAD_TODO_HEIGHT
    end
    if row.verb then
        height = height + Panel.ROAD_VERB_HEIGHT
    end
    return height
end

-- Which slot sections are collapsed and which runs are expanded. Kept per
-- character in the database (`db.char.upgradeMap`), because which slot the
-- owner cares about is about the character and not the account.
function Panel.CollapseState(db)
    db = db or ns.db
    local char = db and db.char
    if type(char) ~= "table" then
        return { slots = {}, runs = {} }
    end
    char.upgradeMap = char.upgradeMap or {}
    char.upgradeMap.collapsedSlots = char.upgradeMap.collapsedSlots or {}
    char.upgradeMap.expandedRuns = char.upgradeMap.expandedRuns or {}
    return { slots = char.upgradeMap.collapsedSlots, runs = char.upgradeMap.expandedRuns }
end

-- The by-slot list. A section is drawn whether or not it is open; its
-- candidates are listed only when it is. Every note the printed lines carry
-- is here too, in the same order and with the same words.
function Panel.Elements(model, state)
    state = state or {}
    local collapsed = state.slots or {}
    local elements = {}
    local function add(element)
        elements[#elements + 1] = element
        return element
    end
    local function note(text, tone)
        if text then
            add({ kind = Panel.ELEMENT_NOTE, text = text, tone = tone, height = Panel.NoteHeight(text) })
        end
    end

    if not model.hasMap then
        note(Panel.EMPTY_NOTE)
        return elements
    end
    if not model.hasVerdict then
        note("No QE Live import yet, so no drop carries a value. Paste a Top Gear export to change that.")
    end
    note(model.upgradeDocumentsNote)

    -- Explain (principle 11), when the reader has asked for it: one sentence
    -- under the first VISIBLE use of a system word in the expanded slot. "First
    -- visible" is why this is counted here, over the elements as they are added,
    -- rather than off the model: a collapsed slot shows nothing and explains
    -- nothing, and the word that earns the sentence is whichever one the reader
    -- meets first.
    local explained = {}
    local function explain(...)
        if not state.explain then
            return
        end
        for _, word in ipairs(Panel.EXPLAIN_WORDS) do
            if not explained[word] then
                for index = 1, select("#", ...) do
                    local text = (select(index, ...))
                    if Panel.UsesWord(text, word) then
                        local sentence = Panel.ExplainText(word, model.chargeText)
                        if sentence then
                            explained[word] = true
                            note(sentence, Panel.EXPLAIN_TONE)
                        end
                        break
                    end
                end
            end
        end
    end

    for _, section in ipairs(model.slots) do
        local shut = collapsed[section.slot] == true
        add({
            kind = Panel.ELEMENT_SECTION,
            height = Panel.SectionHeight(not shut and section.plan or nil),
            slot = section.slot,
            worn = section.worn,
            -- The count names what the section opens onto: its roads once it
            -- has them, the drops it listed before.
            count = section.roadGroups and Panel.RoadCount(section.roadGroups) or #section.candidates,
            plan = not shut and section.plan or nil,
            collapsed = shut,
            section = section,
        })
        if not shut and section.roadGroups then
            explain(section.plan)
            for _, group in ipairs(section.roadGroups) do
                add({
                    kind = Panel.ELEMENT_GROUP,
                    height = Panel.GroupHeight(group.header),
                    group = group.group,
                    text = group.header,
                })
                explain(group.header)
                for _, row in ipairs(group.rows) do
                    add({ kind = Panel.ELEMENT_ROAD, height = Panel.RoadHeight(row), row = row })
                    explain(row.tag, row.second, row.badge and row.badge.text or nil, row.factsText, row.todo)
                end
            end
            note(section.hiddenNote)
        elseif not shut then
            for _, row in ipairs(section.candidates) do
                add({ kind = Panel.ELEMENT_ITEM, height = Panel.ITEM_HEIGHT, row = row })
            end
            note(section.hiddenNote)
        end
    end
    note(model.levelMismatchNote)

    if model.pending.count > 0 then
        local shut = collapsed[Panel.PENDING_SECTION] == true
        add({
            kind = Panel.ELEMENT_SECTION,
            height = Panel.SECTION_HEIGHT,
            slot = Panel.PENDING_SECTION,
            count = model.pending.count,
            collapsed = shut,
        })
        if not shut then
            note(model.pending.note)
            for _, row in ipairs(model.pending.rows) do
                add({ kind = Panel.ELEMENT_ITEM, height = Panel.ITEM_HEIGHT, row = row })
            end
        end
    end
    return elements
end

-- The by-run list. A card per run, and its rated drops under it only when the
-- reader has opened it: 48 runs of one to a dozen drops each is a list nobody
-- can scan, and the card already says the two facts the sort is about.
function Panel.RunElements(model, state)
    state = state or {}
    local expanded = state.runs or {}
    local elements = {}
    local function add(element)
        elements[#elements + 1] = element
        return element
    end
    local function note(text)
        if text then
            add({ kind = Panel.ELEMENT_NOTE, text = text, height = Panel.NoteHeight(text) })
        end
    end

    if not model.hasMap then
        note(Panel.EMPTY_NOTE)
        return elements
    end
    note(model.headline)
    note(Panel.RUN_NOTE)
    if not model.hasUpgrades then
        note(Panel.RUN_NO_IMPORT_NOTE)
    end
    note(model.keyLevelNote)
    note(model.upgradeDocumentsNote)

    for _, run in ipairs(model.runs) do
        local open = expanded[run.key] == true
        add({ kind = Panel.ELEMENT_RUN, height = Panel.RUN_HEIGHT, run = run, expanded = open })
        if open then
            for _, row in ipairs(run.upgrades) do
                add({ kind = Panel.ELEMENT_ITEM, height = Panel.ITEM_HEIGHT, row = row })
            end
        end
    end
    return elements
end

-- ---------------------------------------------------------------------------
-- Frames. Native only, no AceGUI (decision 2026-09-05).
-- Only a default: the window anchors this panel by two corners (M3-3 wiring in
-- UI/MainFrame.lua), which is what actually sizes it. The size matters for a
-- panel built on its own, which is what the render tests do.
local PANEL_WIDTH = 560
local PANEL_HEIGHT = 420
local WHITE_TEXTURE = [[Interface\Buttons\WHITE8X8]]

-- The gold the Vault tab marks its pick with (ns.VaultPanel.SELECTED_HEX,
-- FFDF14), as the three components a texture takes.
Panel.ROAD_PICK_COLOR = { 1, 0.8745, 0.0784 }

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

-- The Upgrade Finder export the window is showing, chosen by the same content
-- type setting and with the same fallback, so a Dungeon Top Gear verdict and a
-- Raid Upgrade Finder export can never end up on one row without the window
-- saying so. The direct call is the fallback for a panel built without the
-- window around it, exactly as activeVerdict above.
--
-- Since C-7 (WKE-543) the companion asks QE Live about several key levels and
-- the addon files one verdict per level; since M3-10 (WKE-545) the panel reads
-- ALL of them and joins each row to whichever one values it at the level the
-- walk lists, so what the panel asks for is the whole set rather than one pick.
local function activeUpgradeDocuments()
    if ns.UI and ns.UI.ActiveUpgradeFinderDocuments then
        return (ns.UI.ActiveUpgradeFinderDocuments())
    end
    return ns.UFImport.Documents(ns.UFImport.ContentTypeKey(ns.UFImport.Current()))
end

-- The plans the window is showing and which of them it is following, both
-- through the window's own resolvers so that every tab is reading one answer.
-- The direct calls are the fallback for a panel built without the window around
-- it, exactly as activeVerdict above.
local function activeScenarios()
    if ns.UI and ns.UI.ActiveVerdictScenarios then
        return (ns.UI.ActiveVerdictScenarios())
    end
    local current = ns.QEImport.Current()
    return current and ns.QEImport.Scenarios(ns.QEImport.ContentTypeKey(current)) or {}
end

local function activeHighlight()
    if ns.UI and ns.UI.Options and ns.UI.Options.GetVaultScenario then
        return ns.UI.Options.GetVaultScenario()
    end
    return ns.QEImport.DEFAULT_SCENARIO
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
    -- Everything the roads are read over (R-3). The scenarios and the highlight
    -- are the Vault tab's own - `ns.VaultPanel.HighlightScenario` resolves the
    -- setting against what is actually stored - so the slot's plan sentence and
    -- the Vault tab's headline can never be about two different answers. The
    -- vault and the currencies are read here for the same reason they are read
    -- there: a road that spends a charge says what the client says you hold.
    local scenarios = activeScenarios()
    local vault = ns.Vault.Options()
    local currencies = ns.Currencies.Read()
    return {
        sources = sources,
        summary = type(summary) == "table" and summary.ok and summary or nil,
        inventory = inventory.ok and inventory or nil,
        verdict = activeVerdict(),
        upgradeDocuments = activeUpgradeDocuments(),
        difficultyIDs = opts.difficultyIDs,
        scenarios = scenarios,
        highlightScenario = (ns.VaultPanel.HighlightScenario(scenarios, activeHighlight())),
        vault = vault.ok and vault or nil,
        currencies = currencies.ok and currencies or nil,
        inCombat = inventory.ok ~= true and inventory.reason == "combat" or nil,
    }
end

-- The controls. Two toggles and one dropdown, on two rows, none of which
-- wraps: what used to be here was a row of UIPanelButtonTemplate buttons, one
-- per difficulty, packed by Panel.FilterLayout because five of them overflowed
-- the window (WKE-530 finding 2). A dropdown holds any number of difficulties
-- in the same space, so the packer and its estimator retire with the buttons
-- (M5-3).
Panel.CONTROL_ROW_HEIGHT = 22
Panel.CONTROL_GAP = 6
Panel.CONTROL_MIN_WIDTH = 60
-- The UIPanelButtonTemplate's own inset, left and right together.
Panel.CONTROL_PADDING = 20
-- Headless there is no font loaded, so a character costs a fixed number of
-- points and a layout test can reproduce a button's width exactly. In the
-- client the button's own font string measures itself, which is the real one.
Panel.CONTROL_CHAR_WIDTH = 6
Panel.DROPDOWN_WIDTH = 200

-- The badge column an item row keeps for QE Live's sentence. Wider than the
-- item line's own default because the sentence is his whole verdict - "QE
-- Live: better by 1.83%" - and truncating a number is not an option.
Panel.BADGE_WIDTH = 190
Panel.SECTION_ICON_SIZE = 24
Panel.RUN_ART_WIDTH = 56
Panel.ELEMENT_SPACING = 2

-- What a collapsed and an open section are marked with. Text rather than an
-- atlas: every atlas this addon draws is checked against the client first
-- (ItemLine.Atlas), and a marker that silently disappears on a client without
-- the art would take the whole affordance with it.
Panel.SECTION_OPEN_MARK = "-"
Panel.SECTION_SHUT_MARK = "+"

Panel.DIFFICULTY_ALL_LABEL = "All difficulties"
-- The dropdown's template: the one whose mixin has SetDefaultText (see the
-- comment where it is created). The Vault's dropdown uses the same.
Panel.DROPDOWN_TEMPLATE = "WowStyle1DropdownTemplate"

local function estimateLabelWidth(label)
    return #tostring(label) * Panel.CONTROL_CHAR_WIDTH + Panel.CONTROL_PADDING
end

-- The client's own measurement of a label, when the button has a font string
-- to ask; the character estimate otherwise, which is the headless path.
local function labelWidth(button, label)
    local text = button and type(button.GetFontString) == "function" and button:GetFontString() or nil
    if text and type(text.GetStringWidth) == "function" then
        local ok, measured = pcall(text.GetStringWidth, text)
        if ok and type(measured) == "number" and measured > 0 then
            return measured + Panel.CONTROL_PADDING
        end
    end
    return estimateLabelWidth(label)
end

-- The dropdown's rows, as data. One per difficulty the WHOLE map holds, in the
-- model's own order and with the model's own labels and counts, plus the "all"
-- row in front - so the menu can never offer a difficulty the map does not
-- have, or name one differently from the row it filters to. Pure, so "the
-- options are the model's difficulties" is an assertion rather than a hope.
function Panel.DifficultyOptions(model)
    local options = {
        {
            label = Panel.DIFFICULTY_ALL_LABEL,
            difficultyID = nil,
            selected = true,
        },
    }
    for _, difficulty in ipairs((model and model.difficulties) or {}) do
        if not difficulty.selected then
            options[1].selected = false
        end
        options[#options + 1] = {
            label = string.format("%s (%d)", difficulty.label, difficulty.count),
            difficultyID = difficulty.difficultyID,
            count = difficulty.count,
            -- `selected` on a model difficulty means "this one is in the
            -- filter". Every difficulty is in it when there is no filter,
            -- which is the "all" row's business rather than each row's, so a
            -- row reads as picked only when it is the ONLY one picked.
            selected = false,
        }
    end
    local wanted = {}
    for _, id in ipairs(model and model.filteredDifficultyIDs or {}) do
        wanted[id] = true
    end
    if next(wanted) then
        options[1].selected = false
        for index = 2, #options do
            options[index].selected = wanted[options[index].difficultyID] == true
        end
    end
    return options
end

-- The text the dropdown shows when it is shut: what is being filtered to.
function Panel.DifficultyText(options)
    for _, option in ipairs(options or {}) do
        if option.selected and option.difficultyID then
            return option.label
        end
    end
    return Panel.DIFFICULTY_ALL_LABEL
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

    -- Row one: which view, and - in the run view - which of the two orders.
    frame.viewLabel = fontString(frame)
    frame.viewLabel:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -8)
    frame.viewLabel:SetText("View:")

    frame.modeButtons = {}
    frame.sortButtons = {}
    frame.sortLabel = fontString(frame)
    frame.sortLabel:SetText("Sort:")

    -- Row two: one dropdown, whatever the map's difficulties turn out to be.
    frame.filterLabel = fontString(frame)
    frame.filterLabel:SetPoint("TOPLEFT", frame.viewLabel, "BOTTOMLEFT", 0, -8)
    frame.filterLabel:SetText("Difficulty:")

    -- The SELECTION template, not the filter one. Both are DropdownButtons
    -- over the 11.0 menu API, but only WowStyle1DropdownTemplate mixes in
    -- DropdownSelectionTextMixin (Blizzard_Menu/MenuTemplates.lua:753), which
    -- is where SetDefaultText lives and what lets the closed control say which
    -- difficulty is chosen; WowStyle1FilterDropdownTemplate (:776) has a fixed
    -- FILTER caption and no SetDefaultText - the owner's client said so with
    -- "attempt to call a nil value" at line 1865, 2026-09-09 23:10.
    frame.difficultyDropdown = CreateFrame("DropdownButton", nil, frame, Panel.DROPDOWN_TEMPLATE)
    frame.difficultyDropdown:SetSize(Panel.DROPDOWN_WIDTH, Panel.CONTROL_ROW_HEIGHT)
    frame.difficultyDropdown:SetPoint("LEFT", frame.filterLabel, "RIGHT", Panel.CONTROL_GAP, 0)
    -- The 11.0 menu API: the generator runs every time the menu opens and
    -- reads the model that is on screen at that moment, which is why the rows
    -- follow a refresh without anything having to rebuild them.
    -- `UIDropDownMenu` is deprecated and is not used anywhere in this addon.
    frame.difficultyDropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetTag("LOOTPATH_UPGRADE_MAP_DIFFICULTY")
        for _, option in ipairs(Panel.DifficultyOptions(frame.model)) do
            local id = option.difficultyID
            rootDescription:CreateRadio(option.label, function()
                return option.selected
            end, function()
                frame.difficultyIDs = id and { id } or nil
                Panel.Refresh(frame)
            end, id)
        end
    end)

    frame.difficultyIDs = nil
    frame.mode = Panel.MODE_SLOT
    frame.runSort = Panel.SORT_BEST

    -- The list. A WowScrollBoxList over a data provider, so a map of 478 drops
    -- costs the frames that fit on screen and not one per drop; the element
    -- kinds are Panel.Elements' own (section, item, note, run).
    frame.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    frame.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    frame.scrollBox:SetPoint("TOPLEFT", frame.filterLabel, "BOTTOMLEFT", 0, -Panel.CONTROL_ROW_HEIGHT - 6)
    frame.scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 4)
    frame.scrollBar:SetPoint("TOPLEFT", frame.scrollBox, "TOPRIGHT", 4, 0)
    frame.scrollBar:SetPoint("BOTTOMLEFT", frame.scrollBox, "BOTTOMRIGHT", 4, 0)

    frame.scrollView = CreateScrollBoxListLinearView(0, 0, 0, 0, Panel.ELEMENT_SPACING)
    -- The extent comes from the data, because the box asks for it before it
    -- has a frame to measure.
    frame.scrollView:SetElementExtentCalculator(function(_, elementData)
        return (elementData and elementData.height) or Panel.NOTE_LINE_HEIGHT
    end)
    -- One frame type for every kind. The factory's first argument is a frame
    -- TYPE or an XML template, and this addon ships no XML, so a kind cannot
    -- have a pool of its own; each element frame therefore builds the widgets
    -- of whichever kinds it has been asked to be, and shows only this one's.
    frame.scrollView:SetElementFactory(function(factory)
        factory("Frame", function(element, data)
            Panel.InitElement(frame, element, data)
        end)
    end)
    frame.scrollView:SetElementResetter(function(element)
        Panel.ResetElement(element)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(frame.scrollBox, frame.scrollBar, frame.scrollView)

    frame.Refresh = Panel.Refresh
    Panel.frame = frame
    return frame
end

-- The view row: two buttons naming the two views, and - in the run view only -
-- two more naming the two sort orders. The button for what is on screen now is
-- disabled, so the row says where you are as well as where you can go.
local function viewButton(list, frame, index)
    local button = list[index]
    if not button then
        button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        list[index] = button
    end
    return button
end

local function sizeViewButton(button, label, anchor, gap)
    button:SetText(label)
    button:SetSize(
        math.max(Panel.CONTROL_MIN_WIDTH, math.ceil(labelWidth(button, label))),
        Panel.CONTROL_ROW_HEIGHT - 2
    )
    button:ClearAllPoints()
    button:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
end

local function placeViewRow(frame, mode, runSort)
    local previous = frame.viewLabel
    for index, name in ipairs(Panel.MODES) do
        local button = viewButton(frame.modeButtons, frame, index)
        sizeViewButton(button, Panel.MODE_LABEL[name], previous, Panel.CONTROL_GAP)
        button:SetShown(true)
        button:SetEnabled(mode ~= name)
        button:SetScript("OnClick", function()
            frame.mode = name
            Panel.Refresh(frame)
        end)
        previous = button
    end

    frame.sortLabel:ClearAllPoints()
    frame.sortLabel:SetPoint("LEFT", previous, "RIGHT", 12, 0)
    frame.sortLabel:SetShown(mode == Panel.MODE_RUN)
    previous = frame.sortLabel
    for index, name in ipairs(Panel.SORTS) do
        local button = viewButton(frame.sortButtons, frame, index)
        sizeViewButton(button, Panel.SORT_LABEL[name], previous, Panel.CONTROL_GAP)
        button:SetShown(mode == Panel.MODE_RUN)
        button:SetEnabled(mode == Panel.MODE_RUN and runSort ~= name)
        button:SetScript("OnClick", function()
            frame.runSort = name
            Panel.Refresh(frame)
        end)
        previous = button
    end
end

-- ---------------------------------------------------------------------------
-- The four element kinds. Each `ensure` builds its widgets once, on the first
-- element frame that is asked to be that kind, and every element frame hides
-- the kinds it is not: the scroll box pools frames by template and this addon
-- ships one template, so a frame that was a section can come back as an item.

local function ensureNote(element)
    if not element.noteText then
        element.noteText = element:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        element.noteText:SetPoint("TOPLEFT", element, "TOPLEFT", 2, -2)
        element.noteText:SetPoint("RIGHT", element, "RIGHT", -4, 0)
        element.noteText:SetJustifyH("LEFT")
        element.noteText:SetWordWrap(true)
    end
    return element.noteText
end

local function ensureSection(element)
    if not element.sectionButton then
        local button = CreateFrame("Button", nil, element)
        button:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        button:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.sectionButton = button

        -- Anchored to the TOP of the section rather than its middle, because
        -- since R-3 the section is as tall as its plan sentence and the worn
        -- item has to stay where it was above it.
        element.sectionIcon = UI.ItemLine.CreateIcon(button, { size = Panel.SECTION_ICON_SIZE })
        element.sectionIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 16, -3)

        element.sectionMark = button:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        element.sectionMark:SetPoint("RIGHT", element.sectionIcon, "LEFT", -4, 0)
        element.sectionMark:SetWidth(12)
        element.sectionMark:SetJustifyH("CENTER")

        element.sectionName = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        element.sectionName:SetPoint("LEFT", element.sectionIcon, "RIGHT", 6, 0)
        element.sectionName:SetJustifyH("LEFT")

        element.sectionCount = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        element.sectionCount:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -8)
        element.sectionCount:SetJustifyH("RIGHT")

        -- The slot's own part of this week's plan, in chat voice (principle 16).
        element.sectionPlan = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        element.sectionPlan:SetPoint("TOPLEFT", element.sectionIcon, "BOTTOMLEFT", 0, -2)
        element.sectionPlan:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        element.sectionPlan:SetJustifyH("LEFT")
        element.sectionPlan:SetWordWrap(true)
    end
    return element.sectionButton
end

local function ensureItem(element)
    if not element.line then
        element.line = UI.ItemLine.Create(element, { badgeWidth = Panel.BADGE_WIDTH })
        element.line:SetPoint("TOPLEFT", element, "TOPLEFT", 14, -2)
        element.line:SetPoint("RIGHT", element, "RIGHT", -4, 0)
    end
    return element.line
end

local function ensureRun(element)
    if not element.runButton then
        local button = CreateFrame("Button", nil, element)
        button:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        button:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.runButton = button

        -- The instance's own art as a left strip, when the walk recorded one.
        -- The strip is drawn either way: dark where there is no art, so the
        -- card is the same shape whether or not the capture has been redone.
        element.runArt = button:CreateTexture(nil, "ARTWORK")
        element.runArt:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -2)
        element.runArt:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 2)
        element.runArt:SetWidth(Panel.RUN_ART_WIDTH)

        element.runMark = button:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        element.runMark:SetPoint("LEFT", element.runArt, "RIGHT", 4, 0)
        element.runMark:SetWidth(12)
        element.runMark:SetJustifyH("CENTER")

        element.runName = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        element.runName:SetPoint("TOPLEFT", element.runMark, "TOPRIGHT", 4, -4)
        element.runName:SetJustifyH("LEFT")
        element.runName:SetWordWrap(false)

        element.runSecond = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        element.runSecond:SetPoint("TOPLEFT", element.runName, "BOTTOMLEFT", 0, -1)
        element.runSecond:SetJustifyH("LEFT")
        element.runSecond:SetWordWrap(false)

        element.runBadge = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        element.runBadge:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -6)
        element.runBadge:SetWidth(Panel.BADGE_WIDTH)
        element.runBadge:SetJustifyH("RIGHT")

        element.runCount = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        element.runCount:SetPoint("TOPRIGHT", element.runBadge, "BOTTOMRIGHT", 0, -2)
        element.runCount:SetWidth(Panel.BADGE_WIDTH)
        element.runCount:SetJustifyH("RIGHT")
    end
    return element.runButton
end

-- A group header: one line of words over the roads it heads, in the panel's
-- normal font so the three groups read as three groups rather than as notes.
local function ensureGroup(element)
    if not element.groupText then
        element.groupText = element:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        element.groupText:SetPoint("TOPLEFT", element, "TOPLEFT", 4, -4)
        element.groupText:SetPoint("RIGHT", element, "RIGHT", -4, 0)
        element.groupText:SetJustifyH("LEFT")
        element.groupText:SetWordWrap(true)
    end
    return element.groupText
end

-- One road. The tag over an M5-1 item line, the muted facts under it, the
-- "do:" line under those, and - only where a verb goes somewhere - one button.
-- Every region is re-anchored on every bind, because which of them a road has
-- is what decides where the next one sits.
local function ensureRoad(element)
    if not element.roadFrame then
        local frame = CreateFrame("Frame", nil, element)
        frame:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.roadFrame = frame

        -- The plan's own pick, marked the way the Vault tab marks it: one edge
        -- in the same gold, and never colour alone - the row also says "in your
        -- best set" in its badge (principle 14).
        element.roadEdge = frame:CreateTexture(nil, "OVERLAY")
        element.roadEdge:SetTexture(WHITE_TEXTURE)
        element.roadEdge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        element.roadEdge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        element.roadEdge:SetWidth(2)
        element.roadEdge:SetVertexColor(unpack(Panel.ROAD_PICK_COLOR))
        element.roadEdge:Hide()

        element.roadTag = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        element.roadTag:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -2)
        element.roadTag:SetJustifyH("LEFT")
        element.roadTag:SetWordWrap(false)

        element.roadLine = UI.ItemLine.Create(frame, { badgeWidth = Panel.BADGE_WIDTH })

        element.roadFacts = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        element.roadFacts:SetJustifyH("LEFT")
        element.roadFacts:SetWordWrap(true)

        element.roadTodo = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        element.roadTodo:SetJustifyH("LEFT")
        element.roadTodo:SetWordWrap(false)

        element.roadVerb = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        element.roadVerb:SetHeight(Panel.ROAD_VERB_HEIGHT - 4)
        element.roadVerb:Hide()
    end
    return element.roadFrame
end

local function hideKinds(element, keep)
    if element.noteText and keep ~= Panel.ELEMENT_NOTE then
        element.noteText:SetText("")
        element.noteText:Hide()
    end
    if element.sectionButton and keep ~= Panel.ELEMENT_SECTION then
        element.sectionButton:Hide()
    end
    if element.line and keep ~= Panel.ELEMENT_ITEM then
        UI.ItemLine.Clear(element.line)
    end
    if element.runButton and keep ~= Panel.ELEMENT_RUN then
        element.runButton:Hide()
    end
    if element.groupText and keep ~= Panel.ELEMENT_GROUP then
        element.groupText:SetText("")
        element.groupText:Hide()
    end
    if element.roadFrame and keep ~= Panel.ELEMENT_ROAD then
        UI.ItemLine.Clear(element.roadLine)
        element.roadVerb:Hide()
        element.roadFrame:Hide()
    end
end

-- One element of the data provider, drawn onto one pooled frame. Called by the
-- scroll box every time a frame is bound to a row, which is what makes the
-- pool safe to be smaller than the list.
function Panel.InitElement(panel, element, data)
    hideKinds(element, data and data.kind)
    if type(data) ~= "table" then
        return element
    end
    element.kind = data.kind

    if data.kind == Panel.ELEMENT_NOTE then
        local text = ensureNote(element)
        text:SetText(data.text or "")
        text:Show()
    elseif data.kind == Panel.ELEMENT_SECTION then
        local button = ensureSection(element)
        element.sectionMark:SetText(data.collapsed and Panel.SECTION_SHUT_MARK or Panel.SECTION_OPEN_MARK)
        if data.worn then
            UI.ItemLine.SetIcon(element.sectionIcon, {
                itemID = data.worn.itemID,
                link = data.worn.link,
                name = data.worn.name,
                quality = data.worn.quality,
                itemLevel = data.worn.itemLevel,
                icon = data.worn.icon,
            })
        else
            UI.ItemLine.ClearIcon(element.sectionIcon)
        end
        element.sectionName:SetText(data.slot)
        element.sectionCount:SetText(string.format("%d drop(s)", data.count or 0))
        element.sectionPlan:SetText(data.plan or "")
        element.sectionPlan:SetShown(data.plan ~= nil)
        button:SetScript("OnClick", function()
            local state = Panel.CollapseState(panel.db)
            state.slots[data.slot] = (state.slots[data.slot] ~= true) or nil
            Panel.Refresh(panel)
        end)
        button:Show()
    elseif data.kind == Panel.ELEMENT_ITEM then
        local row = data.row or {}
        UI.ItemLine.Set(ensureItem(element), {
            itemID = row.itemID,
            name = row.name,
            itemLevel = row.itemLevel,
            icon = row.icon,
            second = row.second,
            badge = row.badge,
            tags = row.tags,
        })
    elseif data.kind == Panel.ELEMENT_GROUP then
        local text = ensureGroup(element)
        text:SetText(data.text or "")
        text:Show()
    elseif data.kind == Panel.ELEMENT_ROAD then
        Panel.InitRoad(panel, element, data.row or {})
    elseif data.kind == Panel.ELEMENT_RUN then
        local run = data.run or {}
        local button = ensureRun(element)
        if run.instanceImage then
            element.runArt:SetTexture(run.instanceImage)
            element.runArt:SetVertexColor(1, 1, 1, 1)
        else
            -- No art recorded for this instance. A plain dark strip, not a
            -- stand-in picture of some other place.
            element.runArt:SetTexture(nil)
            element.runArt:SetVertexColor(0.1, 0.1, 0.12, 1)
        end
        element.runMark:SetText(data.expanded and Panel.SECTION_OPEN_MARK or Panel.SECTION_SHUT_MARK)
        element.runName:SetText(run.isRaid and run.name or (run.instanceName or run.label))
        element.runSecond:SetText(run.difficultyLabel or "")
        element.runBadge:SetText(UI.ItemLine.BadgeText(run.badge))
        element.runCount:SetText(run.countText or "")
        button:SetScript("OnClick", function()
            local state = Panel.CollapseState(panel.db)
            state.runs[run.key] = (state.runs[run.key] ~= true) or nil
            Panel.Refresh(panel)
        end)
        button:Show()
    end
    return element
end

-- One road on one pooled frame. Every region is anchored here rather than in
-- `ensureRoad` because which of them this road has decides where the next one
-- sits: a road with no facts closes the gap, a road with no verb has no button.
function Panel.InitRoad(panel, element, row)
    local frame = ensureRoad(element)
    element.roadEdge:SetShown(row.planPick == true)
    element.roadTag:SetText(row.tag or "")

    local anchor, gap = element.roadTag, -2
    element.roadLine:ClearAllPoints()
    element.roadLine:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
    element.roadLine:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    UI.ItemLine.Set(element.roadLine, {
        itemID = row.itemID,
        name = row.name,
        itemLevel = row.itemLevel,
        icon = row.icon,
        quality = row.quality,
        second = row.second,
        badge = row.badge,
    })
    anchor = element.roadLine

    element.roadFacts:ClearAllPoints()
    element.roadFacts:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    element.roadFacts:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    element.roadFacts:SetText(row.factsText or "")
    element.roadFacts:SetShown(row.factsText ~= nil)
    if row.factsText then
        anchor = element.roadFacts
    end

    element.roadTodo:ClearAllPoints()
    element.roadTodo:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    element.roadTodo:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    element.roadTodo:SetText(row.todo or "")
    element.roadTodo:SetShown(row.todo ~= nil)
    if row.todo then
        anchor = element.roadTodo
    end

    -- One verb, and only where it goes somewhere (principle 9). A road whose
    -- next step is the Catalyst, a craft, a delve or a vendor has no button at
    -- all: the client offers no call for those and a dead button is worse.
    local verb = element.roadVerb
    verb:ClearAllPoints()
    verb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    if row.verb then
        verb:SetText(row.verb)
        verb:SetWidth(math.max(Panel.CONTROL_MIN_WIDTH, math.ceil(labelWidth(verb, row.verb))))
        verb:SetScript("OnClick", function()
            Panel.FollowVerb(panel, row)
        end)
        verb:Show()
    else
        verb:SetScript("OnClick", nil)
        verb:Hide()
    end
    frame:Show()
    return element
end

-- Where a verb goes. Both destinations are Lootpath's own screens; neither
-- touches the character, its items or its money.
function Panel.FollowVerb(panel, row)
    if row.verb == ns.Roads.VERB_SHOW_RUN and row.runKey then
        return Panel.ShowRun(panel, row.runKey)
    end
    if row.verb == ns.Roads.VERB_SHOW_IN_VAULT and row.vaultKey then
        return ns.VaultPanel.ShowReward(row.vaultKey)
    end
    return false
end

-- "Show run": the by-run view, opened at that run. The card is expanded first
-- so the run's own drops are under it when the box scrolls, and the scroll is
-- asked for by predicate over the data provider the refresh has just set -
-- `ScrollBoxListMixin:ScrollToElementDataByPredicate`, which is the call
-- Blizzard's own collections use for exactly this.
function Panel.ShowRun(panel, runKey)
    panel = panel or Panel.frame
    if not (panel and runKey) then
        return false
    end
    local state = Panel.CollapseState(panel.db)
    state.runs[runKey] = true
    Panel.Refresh(panel, { mode = Panel.MODE_RUN })
    panel.scrollBox:ScrollToElementDataByPredicate(function(elementData)
        return type(elementData) == "table"
            and elementData.kind == Panel.ELEMENT_RUN
            and elementData.run
            and elementData.run.key == runKey
    end)
    return true
end

-- A frame going back to the pool waits for nothing: an item line's pending
-- request is cancelled, so a late answer never redraws a row that has moved on.
function Panel.ResetElement(element)
    if element.line then
        UI.ItemLine.Clear(element.line)
    end
    if element.roadLine then
        UI.ItemLine.Clear(element.roadLine)
    end
    if element.sectionIcon then
        UI.ItemLine.ClearIcon(element.sectionIcon)
    end
    element.kind = nil
end

-- Rebuilds the panel from the client. `self` is the frame Create returned.
function Panel.Refresh(self, opts)
    self = self or Panel.frame
    if not self then
        return nil
    end
    opts = opts or {}
    opts.difficultyIDs = opts.difficultyIDs or self.difficultyIDs
    local mode = opts.mode or self.mode or Panel.MODE_SLOT
    local runSort = opts.runSort or self.runSort or Panel.SORT_BEST
    local gathered = Panel.Gather(opts)
    gathered.runSort = runSort
    -- Two models over one gather. The slot view is the one M3-3 shipped and
    -- nothing here changes what it renders; the run view is its sibling.
    local model
    if mode == Panel.MODE_RUN then
        model = Panel.RunModel(gathered)
    else
        model = Panel.Model(gathered)
    end
    -- Which difficulties the reader asked for, carried on the model so the
    -- dropdown's rows and the rows on screen are answering one question.
    model.filteredDifficultyIDs = opts.difficultyIDs
    self.model = model
    self.mode = mode
    self.runSort = runSort
    self.difficultyIDs = opts.difficultyIDs
    self.db = opts.db or self.db
    placeViewRow(self, mode, runSort)

    local options = Panel.DifficultyOptions(model)
    self.difficultyOptions = options
    -- Shown in both views: a difficulty narrows the slot list and the run list
    -- alike, so the control never leaves the row.
    self.difficultyDropdown:Show()
    self.difficultyDropdown:SetDefaultText(Panel.DIFFICULTY_ALL_LABEL)
    self.difficultyDropdown:SetText(Panel.DifficultyText(options))
    -- The real menu regenerates itself when it opens; this is so a menu that
    -- is already built reflects the map that is now on screen.
    self.difficultyDropdown:GenerateMenu()

    -- The printed text is unchanged and still the model's own (it is what
    -- `/lootpath status` and the render tests read); what is DRAWN is the
    -- element list beside it.
    local lines = (mode == Panel.MODE_RUN) and Panel.RunLines(model) or Panel.Lines(model)
    local state = Panel.CollapseState(self.db)
    -- Explain is a profile setting, not per-character state, so it rides on the
    -- table the element list already takes rather than becoming a third argument.
    state.explain = ns.UI.Options and ns.UI.Options.GetExplain and ns.UI.Options.GetExplain() or false
    local elements = (mode == Panel.MODE_RUN) and Panel.RunElements(model, state) or Panel.Elements(model, state)
    if gathered.inCombat then
        lines = { "Lootpath does not read the client in combat. Leave combat and reopen this panel." }
        elements = {
            { kind = Panel.ELEMENT_NOTE, text = lines[1], height = Panel.NoteHeight(lines[1]) },
        }
    end
    -- The pinned note is the header's, drawn once; it is not a row of the
    -- list, in combat or out of it (WKE-530 finding 3).
    self.lines = lines
    self.elements = elements
    self.scrollBox:SetDataProvider(CreateDataProvider(elements))
    return model
end
