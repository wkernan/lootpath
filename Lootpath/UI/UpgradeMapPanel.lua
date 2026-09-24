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
Panel.NOTE = "Rated drops show their value. Other drops are listed by item level only."

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
Panel.LEVEL_MISMATCH_NOTE = "%d drops are rated at another item level, so they show no value."

-- Every sentence the two badge builders below can write, in one place, in the
-- source-free voice (V-1, WKE-569). They are named constants rather than
-- literals inside the branches because `spec/voice_spec.lua` walks this table:
-- a branch the committed fixtures never reach - a zero percent, a rating with
-- no delta - would otherwise be the one place a source could creep back in
-- unwatched.
Panel.BADGE_IN_BEST_SET = "in your best set"
Panel.BADGE_NO_DELTA = "rated, no delta given"
Panel.BADGE_DELTA = "%s%s by %.2f%% (%+.1f score)"
Panel.BADGE_PERCENT = "%s%s by %.2f%%"
Panel.BADGE_NO_VALUE = "rated, no value given"
Panel.BADGE_NO_CHANGE = "no change"
Panel.BADGE_UPGRADE_PERCENT = "%s by %.2f%%"
Panel.BADGE_BETTER = "better"
Panel.BADGE_WORSE = "worse"
Panel.BADGE_LEAD = "%s: "

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
-- `prefix` is a lead the caller may put in front of the rating, and there is
-- none by default: no surface names where a rating came from (the 2026-09-11
-- decision, ARCHITECTURE.md 7). The Vault tab passes a scenario's name (C-6,
-- WKE-540), because what each of its lines has to say is WHICH of the
-- questions it answers.
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
    local lead = type(prefix) == "string" and string.format(Panel.BADGE_LEAD, prefix) or ""
    if coverage.where == "topSet" then
        return { text = lead .. Panel.BADGE_IN_BEST_SET, tone = "neutral" }
    end
    local percent = tonumber(coverage.scorePercent)
    local hps = tonumber(coverage.hpsDifference)
    if not percent then
        return { text = lead .. Panel.BADGE_NO_DELTA, tone = "none" }
    end
    local direction = coverage.isBetter and Panel.BADGE_BETTER or Panel.BADGE_WORSE
    if hps then
        return {
            text = string.format(Panel.BADGE_DELTA, lead, direction, math.abs(percent), hps),
            tone = direction,
        }
    end
    return { text = string.format(Panel.BADGE_PERCENT, lead, direction, math.abs(percent)), tone = direction }
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
        return { text = Panel.BADGE_NO_VALUE, note = note, tone = "none" }
    end
    if percent == 0 then
        -- 94 of the 357 drops in the 2026-09-07 Dungeon export sit here. "No
        -- change" is what his zero says; "worse by 0.00%" would be this panel
        -- inventing a direction he did not give.
        return { text = Panel.BADGE_NO_CHANGE, note = note, tone = "none" }
    end
    local direction = ns.UFImport.IsUpgrade(entry) and Panel.BADGE_BETTER or Panel.BADGE_WORSE
    return {
        text = string.format(Panel.BADGE_UPGRADE_PERCENT, direction, math.abs(percent)),
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

-- What a hover says when the row has no link of its own. The client would
-- draw the item as it exists in its own expansion - the base level and the
-- stats that came with it - and nothing on that tooltip would say so, which is
-- how a 305 row read as Item Level 28 (M5-3a). The row says it instead, and
-- names the one thing that fixes it. No link is ever synthesised from an ID
-- and a level: a made-up link would be a made-up item.
Panel.BASE_LEVEL_NOTE = "shown at its base level - /lootpath capture journal to read it at +%d"
Panel.BASE_LEVEL_NOTE_PLAIN = "shown at its base level - /lootpath capture journal to read it at this row's level"

-- The keystone level is only part of the sentence where the row has one: a
-- raid drop gets the plain form rather than a number that means nothing there.
-- `Panel.RunKeyLevel` is the one place that answers "was this read at a key
-- level, and which one" - the same question the hover-time line asks (M5-3b),
-- and the one that already honours an entry carrying its own level - so
-- neither hover can drift into calling a raid drop a +10. An entry with no
-- difficulty at all names no key level either: it would be a guess.
function Panel.BaseLevelNote(entry, previewLevel)
    local level = Panel.RunKeyLevel(entry and entry.difficultyID, previewLevel, entry)
    if type(level) == "number" then
        return string.format(Panel.BASE_LEVEL_NOTE, level)
    end
    return Panel.BASE_LEVEL_NOTE_PLAIN
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
        -- The link the walk read this row's item level off, carried so the
        -- hover shows the item AT that level (M5-3a). A walk taken before the
        -- link was kept has none, and then the row carries the note that says
        -- so instead: an old-expansion base tooltip is never left to pass for
        -- the level the row prints.
        link = entry.link,
        levelNote = entry.link == nil and entry.pending ~= true and Panel.BaseLevelNote(entry, previewLevel) or nil,
        -- What the hover needs to catch the other half of the same problem
        -- (M5-3b): the level this row prints and the key level the walk
        -- previewed it at, so a tooltip drawn at the link's own level can say
        -- so in the row's words instead of quietly disagreeing with it.
        keyLevel = Panel.RunKeyLevel(entry.difficultyID, previewLevel, entry),
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
    -- A Crafted or Delves row (R-4) has no boss and no difficulty to name, so
    -- its second line says what it is and what has not been read instead.
    local second = row.sourceKind and Panel.ExportSecondText(row) or Panel.SourceSecondText(row)
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

-- ---------------------------------------------------------------------------
-- Crafting and Delves as runs (R-4, WKE-565).
--
-- The by-run view lists what the Encounter Journal walk found, because a boss
-- drop is the only thing the walk can find. Every Upgrade Finder document the
-- companion writes also carries rows the walk never sees - 18 `Crafted` and 33
-- `Delves` in each of the eight committed exports - and nothing ever asked the
-- view about them. BY SLOT they are ns.Roads' own rows and R-3 draws them
-- (ns.Roads.ForSlot builds a craft and a delve road per slot, and the slot's
-- `Other rated sources` group renders them); this file adds the half R-3 does
-- not have, which is the two CARDS the by-run view was missing.
--
-- What is new here is a PLACE for them, never a number: the rows are his, the
-- percent on a badge is his, and a card's order is his percent's. Nothing is
-- added, averaged or scaled.
--
-- What these cards cannot say, and say so instead:
--   * no boss, no instance, no difficulty - the export gives none, so they
--     carry no difficulty, gain no entry in the difficulty dropdown and are
--     shown whatever it is filtered to (there is nothing to filter them by),
--     and the card draws the plain dark strip where art would be.
--   * no crafting cost: the spark count is readable only once its item ID is
--     captured, and materials and orders need the crafter's own open window
--     (docs/ROADS-UX.md Buildability).
--   * no delve key and no Bountiful state: the key is a currency whose ID no
--     capture has read, and no `C_DelvesUI` function exposes which delves are
--     Bountiful. R-1 says the same thing on a road's step; this is the by-run
--     view's wording of it.
--   * no name of its own: an Upgrade Finder row is an itemID and an item level
--     and nothing else, so a drawn row asks the client for the name through
--     ns.ItemData (the M3-12 pending pattern, inside UI/ItemLine) and the
--     printed line says `item 237849` until the client answers.

-- The tag a row leads its second line with. R-1's own words for the two
-- sources (ns.Roads.TAG_CRAFTED / TAG_DELVES), so a Roads row and an Upgrade
-- Map row cannot end up calling one source two things.
Panel.SOURCE_TAG = {
    [ns.UFImport.SOURCE_KIND_CRAFT] = ns.Roads.TAG_CRAFTED,
    [ns.UFImport.SOURCE_KIND_DELVE] = ns.Roads.TAG_DELVES,
}

-- What the by-run card is called. "Crafting" rather than "Crafted" because the
-- card names the thing you would go and do, the way "Ara-Kara, City of Echoes"
-- does; a row's tag stays the export's own word.
Panel.SOURCE_RUN_NAME = {
    [ns.UFImport.SOURCE_KIND_CRAFT] = "Crafting",
    [ns.UFImport.SOURCE_KIND_DELVE] = "Delves",
}

-- The second line of a Crafted row under a card, with and without the stats
-- line the export's own settings name. `spark and materials not read` is R-1's
-- ns.Roads.CRAFT_NOT_READ, shared rather than retyped.
Panel.CRAFT_SECOND = "%s - " .. ns.Roads.CRAFT_NOT_READ
Panel.CRAFT_SECOND_STATS = "%s, %s - " .. ns.Roads.CRAFT_NOT_READ

-- The second line of a Delves row. R-1's step under its Delves tag is the bare
-- "not read"; on a row that is read on its own the two things that are not
-- read are named, because "Delves - not read" does not say what was not.
Panel.DELVE_SECOND = "%s - key and Bountiful state not read"

Panel.EXPORT_NOTE = "Crafting and Delves are rated rather than walked in the Adventure Guide: they carry no "
    .. "difficulty, so they are shown whatever the difficulty filter is set to, and their counts are of rated "
    .. "items rather than of a run's drops."

-- A run card's denominator is every drop the journal lists for the run. These
-- two have no journal behind them, so theirs is every row the export ranks -
-- which is not every crafted item or every delve reward in the game, and the
-- wording says "ranked" rather than "drops" for exactly that reason.
Panel.EXPORT_RUN_COUNT_TEXT = "%d of %d ranked items are upgrades"

-- The second line of the two cards: what the source is and what is not read
-- about it, the same facts their rows carry.
--
-- Since UX-5 (WKE-614) it does NOT lead with "No difficulty - ". The control
-- row says which difficulty the map is filtered to, and a tile that answered a
-- question the header already answers is a word spent on a state (deliverable
-- 4). What is left is the two facts nobody else says.
Panel.EXPORT_RUN_SECOND = {
    [ns.UFImport.SOURCE_KIND_CRAFT] = ns.Roads.CRAFT_NOT_READ,
    [ns.UFImport.SOURCE_KIND_DELVE] = "key and Bountiful state not read",
}

-- The second line of one Crafted or Delves row: the source, what the export
-- says about it, and what has not been read.
function Panel.ExportSecondText(row)
    local tag = Panel.SOURCE_TAG[row.sourceKind] or tostring(row.sourceKind)
    if row.sourceKind == ns.UFImport.SOURCE_KIND_CRAFT then
        return row.craftedStats and string.format(Panel.CRAFT_SECOND_STATS, tag, row.craftedStats)
            or string.format(Panel.CRAFT_SECOND, tag)
    end
    return string.format(Panel.DELVE_SECOND, tag)
end

-- One entry of ns.UFImport.SourceRows as a row of the same shape a journal
-- candidate has, so a card's list and a run's list treat them alike. No
-- instance, no encounter and no difficulty, because the export carries none;
-- no name, because it carries none of those either.
function Panel.ExportRow(kind, held, owned)
    local entry = held.entry
    local ownedRecord = owned and owned[entry.itemID] or nil
    -- The grey "(at +6)" on a drop row names WHICH stored document valued it,
    -- because for a drop that is a real choice between documents. It is not one
    -- here: every document of one companion run carries these rows identically
    -- (ns.UFImport.SourceRows), so naming a key level would tell the reader a
    -- crafted item's value depends on a Mythic+ key, which his own files deny.
    -- The note comes back the moment two stored documents really do disagree.
    local keyLevel = held.disagrees and held.keyLevel or nil
    local row = {
        itemID = entry.itemID,
        itemLevel = entry.level,
        slot = entry.slot,
        sourceKind = kind,
        sourceLabel = Panel.SOURCE_TAG[kind] or tostring(kind),
        -- Carried, never rendered: an index into QE Live's own profession
        -- table, which this addon does not restate (ns.UFImport, R-4).
        professionIndex = entry.professionIndex,
        craftedStats = held.crafted and held.crafted.stats or nil,
        upgrade = entry,
        upgradeKeyLevel = keyLevel,
        -- The document this row came from, named or not: the age and the
        -- provenance are facts even when the row does not print them.
        documentKeyLevel = held.keyLevel,
        documentsCarrying = held.documents,
        upgradeValue = Panel.UpgradeText(entry, keyLevel),
        owned = ownedRecord ~= nil or nil,
        ownedItemLevel = ownedRecord and ownedRecord.itemLevel or nil,
    }
    return Panel.FinishRow(row)
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
        -- Which picture the walk recorded for each instance, so a road card can
        -- draw its instance's art (UX-6). Read off the whole walk: the picture
        -- is the instance's, whatever difficulty filter is on.
        model.instanceImages = Panel.InstanceImages(sources)
        model.chargeText = ns.Roads.ChargeText(ns.Roads.Charge(opts.currencies))
        for _, section in ipairs(model.slots) do
            section.roads = ns.Roads.ForSlot(section.slot, inputs)
            -- The slot's own line, in the same voice as the week's: built from
            -- the slot's roads, so the header and the rows cannot disagree.
            section.plan = section.roads.plan
            -- Whether this slot's bags are ahead of the document (R-3b).
            section.staleBags = section.roads.staleBags == true
            section.roadGroups = Panel.RoadGroups(section.roads, previewLevel)
            -- Why each no-rating road has none (UX-6b): what the cards draw.
            -- roadGroups is untouched, so the printed lines are too.
            section.noRating = Panel.SortNoRating(section, documents, opts.specFit)
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
        add("No import yet, so no drop carries a value. Paste a Top Gear export to change that.")
    end
    -- Which Upgrade Finder documents these rows were joined against (M3-10).
    -- Above the rows, because it is true of all of them; which document a
    -- particular row's number came from is on the row itself.
    if model.upgradeDocumentsNote then
        add(model.upgradeDocumentsNote)
    end
    for _, section in ipairs(model.slots) do
        add(Panel.SectionHeaderText(section))
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

Panel.RUN_NOTE = "Two facts side by side: the best single upgrade in a run, and how many of that run's drops are "
    .. "rated upgrades. Neither is weighted by drop chance - the Adventure Guide gives none, and Lootpath will not "
    .. "invent one - so the odds are yours to judge."

Panel.RUN_NO_IMPORT_NOTE =
    "No Upgrade Finder import yet, so no run can be ranked. Paste an Upgrade Finder export to change that."

-- The denominator is every drop the journal lists for the run, so the reader
-- can see how thin a "best upgrade" is spread.
Panel.RUN_COUNT_TEXT = "%d of %d drops rated upgrades"
Panel.RUN_NO_UPGRADE_TEXT = "no drop rated yet"

-- The answer, first, in a guildmate's words (UX-5, WKE-614; the voice rule,
-- 2026-09-16). It replaces the three "Best run right now (by best upgrade): ..."
-- forms, which named the sort order before they named the run and read like a
-- report rather than like chat.
--
-- ONE FORM PER SOURCE KIND, and none is left to improvise: a player does not
-- "run" a delve card or a crafting order, so a single shape with the run's name
-- poured into it would have written "Run Crafting - ...". They live in one table
-- keyed by kind so a test can enumerate every form rather than reach whichever
-- ones a fixture happens to produce.
--
-- Every number in them is the run's own `bestPercent`, printed exactly as the
-- tile's badge prints it - his sign, his magnitude - and the item is named
-- through `ns.Roads.ShortName`, which is the one place that turns an item into
-- the words a player uses for it. Nothing here is computed.
Panel.RUN_ANSWER_DUNGEON = "dungeon"
Panel.RUN_ANSWER_RAID = "raid"
Panel.RUN_ANSWER_DELVE = "delve"
Panel.RUN_ANSWER_CRAFT = "craft"
Panel.RUN_ANSWER_COUNT = "count"
Panel.RUN_ANSWER_COUNT_EXPORT = "countExport"
Panel.RUN_ANSWER_NONE = "none"
Panel.RUN_ANSWER = {
    dungeon = "Run %s - %s there is %+.2f%%, your best drop right now.",
    raid = "Raid %s - %s there is %+.2f%%, your best drop right now.",
    delve = "Do a delve - %s is %+.2f%%, your best drop right now.",
    craft = "Get %s crafted - it's %+.2f%%, your best right now.",
    -- Under the other sort the subject is the count, so the sentence is about
    -- the count. The export's two runs count RATED ITEMS rather than a run's
    -- drops (Panel.EXPORT_RUN_COUNT_TEXT says the same on the tile), and the
    -- denominator's wording follows the thing it counts.
    count = "%s has the most upgrades for you - %d of %d drops.",
    countExport = "%s has the most upgrades for you - %d of %d rated items.",
    none = "Nothing on this map is an upgrade right now.",
}

-- Which form a run takes. The raid/dungeon split is the model's own `isRaid`,
-- and the two export runs are known by the `sourceKind` they already carry
-- (R-4); there is no fifth kind, because there is no fifth thing a run can be.
function Panel.RunAnswerKind(run)
    if type(run) ~= "table" then
        return nil
    end
    if run.sourceKind == ns.UFImport.SOURCE_KIND_DELVE then
        return Panel.RUN_ANSWER_DELVE
    end
    if run.sourceKind == ns.UFImport.SOURCE_KIND_CRAFT then
        return Panel.RUN_ANSWER_CRAFT
    end
    if run.isRaid then
        return Panel.RUN_ANSWER_RAID
    end
    return Panel.RUN_ANSWER_DUNGEON
end

-- What a player calls the run's best drop. `ns.Roads.ShortName` already carries
-- its own "the", so the sentence shapes above never write one; the full name is
-- never wrong, only long, so it is the fallback, and an item the client cannot
-- name yet is its ID rather than a blank.
function Panel.RunBestName(run)
    local best = type(run) == "table" and run.best or nil
    if type(best) ~= "table" then
        return nil
    end
    return ns.Roads.ShortName({ name = best.name, slot = best.slot }) or best.name or ("item " .. tostring(best.itemID))
end

-- The whole sentence, over the model that is on screen. The top run under the
-- chosen sort is the subject, because it is the run the list puts first.
function Panel.RunAnswer(model)
    if type(model) ~= "table" then
        return nil
    end
    local top = model.runs and model.runs[1] or nil
    if not (top and top.best) then
        return model.hasMap and Panel.RUN_ANSWER[Panel.RUN_ANSWER_NONE] or nil
    end
    local name = top.instanceName or top.name or top.label
    if model.sort == Panel.SORT_COUNT then
        local shape = top.sourceKind and Panel.RUN_ANSWER[Panel.RUN_ANSWER_COUNT_EXPORT]
            or Panel.RUN_ANSWER[Panel.RUN_ANSWER_COUNT]
        return string.format(shape, name, top.rated, top.drops)
    end
    local kind = Panel.RunAnswerKind(top)
    local what = Panel.RunBestName(top)
    if kind == Panel.RUN_ANSWER_DELVE or kind == Panel.RUN_ANSWER_CRAFT then
        return string.format(Panel.RUN_ANSWER[kind], what, top.bestPercent)
    end
    return string.format(Panel.RUN_ANSWER[kind], name, what, top.bestPercent)
end

-- One key level exists today: the one the walk previewed. The companion now
-- asks QE Live at several of them (C-7) and each drop is valued by whichever
-- document carries it at the level the walk lists (M3-10), but the WALK is
-- still a single preview level, so a Mythic Keystone run is still shown at that
-- one level. This line says which, rather than inventing item levels for the
-- others; a walk per key level is its own question (ARCHITECTURE.md 11).
Panel.KEY_LEVEL_NOTE = "Mythic Keystone runs are shown at key %s, which is what the walk previewed. "
    .. "A key level with no walk and no export of its own is not shown."

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

-- One run's own figures, once every drop it can give has been looked at. Both
-- kinds of card come through here - the walk's runs and R-4's two export cards
-- - so a card says its best and its count the same way whatever produced it.
-- The only difference is the denominator's WORDING: a walked run counts the
-- drops the Adventure Guide lists for it, and an export card counts the rows
-- the export ranks, which is not the same claim (Panel.EXPORT_RUN_COUNT_TEXT).
local function finishRun(model, run)
    sortRunUpgrades(run.upgrades)
    run.best = run.upgrades[1]
    run.bestPercent = run.best and tonumber(run.best.upgrade.upgradePercent) or nil
    run.countText = run.sourceKind and string.format(Panel.EXPORT_RUN_COUNT_TEXT, run.rated, run.drops)
        or string.format(Panel.RUN_COUNT_TEXT, run.rated, run.drops)
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
    return run
end

-- The two cards the export gives and the walk never can (R-4): one for
-- Crafting and one for Delves, built out of the rows every Upgrade Finder
-- document carries beside its drops. They sit beside the instance cards and
-- sort against them under both orders, because the question the view answers -
-- what is the best thing I could go and do right now - is not about bosses.
--
-- Neither card has a difficulty, so neither is filtered by one: the difficulty
-- dropdown is built from the walk's own difficulties and gains no entry here,
-- and these two are shown whatever it is set to.
local function exportRuns(model, documents, owned)
    for _, kind in ipairs(ns.UFImport.SOURCE_KINDS) do
        local held = ns.UFImport.SourceRows(documents, kind)
        if #held > 0 then
            local name = Panel.SOURCE_RUN_NAME[kind]
            local run = {
                key = "export:" .. kind,
                sourceKind = kind,
                instanceName = name,
                label = name,
                name = name,
                difficultyLabel = Panel.EXPORT_RUN_SECOND[kind],
                isRaid = false,
                -- The denominator: every row the export ranks for this source,
                -- which is not every crafted item or every delve reward in the
                -- game. No instance art, because there is no instance.
                drops = #held,
                pendingDrops = 0,
                rated = 0,
                upgrades = {},
            }
            for _, entry in ipairs(held) do
                -- The one path to a number here is the slot view's own: HIS
                -- number, and his own IsUpgrade saying it means better.
                if ns.UFImport.IsUpgrade(entry.entry) then
                    run.rated = run.rated + 1
                    run.upgrades[#run.upgrades + 1] = Panel.ExportRow(kind, entry, owned)
                end
            end
            finishRun(model, run)
            model.counts.exportRuns = model.counts.exportRuns + 1
        end
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
        -- `runs` and `ratedRuns` count every card on screen, R-4's two
        -- included; `exportRuns` says how many of them the export gave rather
        -- than the walk. `drops` and `rated` stay the WALK's own figures: an
        -- export row is not a drop the Adventure Guide lists, and adding it to
        -- that total would make the denominator mean two things.
        counts = {
            runs = 0,
            ratedRuns = 0,
            drops = 0,
            rated = 0,
            keyLevels = 0,
            upgradeDocuments = #documents,
            exportRuns = 0,
        },
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
        finishRun(model, runs[key])
    end
    -- Only when there IS a walk, for the reason Panel.Model gives: with no map
    -- this view stops at EMPTY_NOTE and draws no card at all.
    if model.hasMap then
        exportRuns(model, documents, owned)
    end
    if model.counts.exportRuns > 0 then
        model.exportNote = Panel.EXPORT_NOTE
    end
    table.sort(model.runs, runComparator(sort))

    -- The answer, in one sentence, before anything else (UX-5). It is the same
    -- string the panel draws above the list and the same one `RunLines` prints
    -- first, so the screen and `/lootpath status` cannot say two things.
    model.headline = Panel.RunAnswer(model)

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
    if model.exportNote then
        add(model.exportNote)
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

-- The one part of a group header that belongs to THIS surface: the middle
-- group's header already names its scale (ns.Roads.GROUP_HEADER), and the set
-- group's says which plan it is under and how its rows are arranged.
Panel.GROUP_SET_TAIL = "the pick first, then the rated alternatives"
Panel.ROAD_SEPARATOR = " · "

-- What a slot whose bags have moved past the plan says about itself (R-3b,
-- WKE-576, defect 4). The same words the tooltip's header carries
-- (`ns.UI.Tooltip.REFRESH`), in the same place - the header that already says
-- how old the answer is - so the two surfaces say one thing.
--
-- It is text rather than a button because a slot header has one column beside
-- its name and the drop count is in it; the rows below carry the Refresh VERB,
-- which is where principle 9's button belongs.
Panel.SECTION_REFRESH = "/lootpath refresh"

-- The slot header's own line: the slot, and the refresh when the slot holds
-- something the plan has not seen.
function Panel.SectionHeaderText(section)
    local slot = type(section) == "table" and section.slot or nil
    if type(slot) ~= "string" then
        return ""
    end
    if type(section) == "table" and section.staleBags == true then
        return slot .. Panel.ROAD_SEPARATOR .. Panel.SECTION_REFRESH
    end
    return slot
end

-- ---------------------------------------------------------------------------
-- Roads at a glance (UX-6, WKE-637). The owner, on the by-slot list: "this also
-- seems to be looking very messy ... simple, visual, warm, easy to understand".
-- His answers off the direction page: roads as CARDS - the Run Tile, which is
-- what a card is, so nothing new is drawn; the slot line carries the slot's
-- name alone; the first slot worth taking starts open and the rest shut; the
-- explanations come off the screen. Every sentence that left is one hover
-- away (Panel.SlotTooltipLines, Panel.CardTooltipLines), and every string the
-- printed lines carry - `/lootpath status` - is unchanged: SectionHeaderText,
-- GroupHeaderText and RoadLineText still say exactly what they said.
Panel.ELEMENT_CARD_ROW = "cardRow"
-- The fold line (UX-6b, widened by UX-6c): one per slot, the count on it.
Panel.ELEMENT_FOLD = "fold"

-- The divider over a group of cards: an eyebrow, not a sentence. The two
-- scales still never sort together (docs/ROADS-UX.md principle 2); the long
-- forms (ns.Roads.GROUP_HEADER, GroupHeaderText) stay for the printed lines
-- and the slot line's hover.
Panel.GROUP_EYEBROW = {
    [ns.Roads.GROUP_SET] = "In your best set",
    [ns.Roads.GROUP_ITEM] = "Rated against what you wear",
    [ns.Roads.GROUP_NONE] = "No rating",
}

-- The one line the tab says when any slot's bags have moved past the rating,
-- in the strip's shape, under the header and drawn once - where SECTION_REFRESH
-- used to ride on every stale slot's line. `Refresh` names the button on the
-- strip; nothing here says `click` about a line with no edges (R-8b).
Panel.STALE_BAGS_TEXT = "your bags changed since this rating"
Panel.STALE_NUDGE = Panel.STALE_BAGS_TEXT .. Panel.ROAD_SEPARATOR .. "Refresh"
-- The strip's own amber for an age that has gone stale (UI/MainFrame.lua,
-- `ffd43b`), so the two surfaces say "behind" in one colour.
Panel.STALE_HEX = "ffd43b"

-- Where a card's click goes, said on its hover. Only the two verbs a card can
-- follow: a whole card that reloads the interface on a stray click would be a
-- trap, so the Refresh verb stays with the strip's button and the nudge above.
Panel.CARD_CLICK_TEXT = {
    [ns.Roads.VERB_SHOW_RUN] = "click: show the run",
    [ns.Roads.VERB_SHOW_IN_VAULT] = "click: show in vault",
}

-- Whether a step is one the answer goes forward on: a `do:` line that survived
-- ns.Roads.GateImperatives (R-3a's bound), other than the refresh, which is a
-- step for the rating rather than for the player.
function Panel.IsImperative(todo)
    return type(todo) == "string"
        and todo ~= ns.Roads.TODO_REFRESH
        and todo:sub(1, #ns.Roads.TODO_PREFIX) == ns.Roads.TODO_PREFIX
end

-- The first slot, in the model's own order, that draws a card (UX-7a,
-- WKE-642): one road Panel.CardWorthDrawing passes - the pick, a road with an
-- imperative, a whole-set verdict in the best set, or a road whose worn row is
-- above zero. The one slot that starts open. nil when no slot draws anything.
-- UX-6 asked for an imperative instead, and R-3a's bound (ns.Roads.
-- GateImperatives) puts one only on a road the slot's answer goes forward on:
-- on a character whose every answer is a keep nothing opened, while the same
-- slots drew upgrade cards. An imperative passes the same test, so a slot that
-- opened before still opens.
function Panel.FirstWorthTaking(model)
    if type(model) ~= "table" then
        return nil
    end
    for _, section in ipairs(model.slots or {}) do
        if Panel.EachSlotCard(section, model.upgradeDocuments, Panel.CardWorthDrawing) then
            return section.slot
        end
    end
    return nil
end

-- Whether a slot is open. `saved` is the character's own click
-- (`db.char.upgradeMap.collapsedSlots[slot]`): true is shut, false is opened,
-- and nil - no click - is the default, the pattern Equip Now's fold uses
-- (M5-1b). The default for a slot with roads is the first-worth-taking rule; a
-- slot with none is the M5-3 candidate list, open as it always was. A save from
-- before UX-6 only ever held `true`, so it still reads as shut.
function Panel.SlotOpen(saved, section, firstWorth)
    if saved == true then
        return false
    end
    if saved == false then
        return true
    end
    if type(section) == "table" and section.roadGroups then
        return section.slot ~= nil and section.slot == firstWorth
    end
    return true
end

-- The roads a group draws as cards: all of them but the Keep row, whose item
-- is the slot line's own icon.
function Panel.CardRows(group)
    local rows = {}
    for _, row in ipairs(type(group) == "table" and group.rows or {}) do
        if row.kind ~= ns.Roads.KIND_KEEP then
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- Whether a road is drawn as a card at all (UX-6c, WKE-640). The owner: "a
-- player only ever wants to see items that would be an upgrade or a
-- sidegrade, but never a downgrade." The source's own line for an upgrade is a
-- score above zero - his Upgrade Finder counts a slot's upgrades as
-- `filter((item) => item.score > 0)` (PanelSlots.js:102) - and the export
-- carries that score's sign as `upgradePercent`, which ns.UFImport.IsUpgrade
-- reads. "Sidegrade" has no figure behind it: a band around zero would be a
-- threshold he never set, so there is none. Drawn:
--   * a road with an imperative the answer goes forward on - the pick, a vault
--     take, a Catalyst, a crest - because the answer sentence names it
--     (ns.Roads.GateImperatives has already taken the imperative off every
--     road that is not forward);
--   * the set group's pick, and a whole-set verdict that puts the road IN the
--     best set (a later pass's `rated · better than what you wear` too);
--   * a per-item road whose carried document row - the drop row, or the
--     crested row - IsUpgrade calls an upgrade.
-- Not drawn: a tie, a downgrade, `not in your best set`, and every road with
-- no figure. They are not dropped: the slot's one fold counts them.
-- A figure off a road, read the way IsUpgrade reads an entry's: the road
-- carries his `upgradePercent` unchanged, so it is handed back in the entry's
-- own shape (one table, reused, because this runs for every road of every open
-- slot on every draw).
local percentEntry = {}
local function isUpgradePercent(percent)
    if percent == nil then
        return false
    end
    percentEntry.upgradePercent = percent
    return ns.UFImport.IsUpgrade(percentEntry) == true
end

-- The two document rows a per-item card can carry, each `{ percent, level }`
-- as his document gave it: the drop row and the crested (`max`) row - the item
-- with its crests spent, out of the same document (UpgradeFinderEngine.js:
-- 259-260; `bonus` is the vault-track copy and is not it). A drop rated at
-- another level carries both whole (UX-6b's `otherLevel`); a road rated where
-- it drops carries its own rating and the `max` entry of its `alsoAt` (`at its
-- cap 334 +0.72%`). nil, nil for every other card. No table is built: this
-- runs for every road of every open slot on every draw.
function Panel.CardRatingRows(row)
    if type(row) ~= "table" then
        return nil, nil
    end
    local other = row.otherLevel
    if type(other) == "table" then
        return other.drop, other.max
    end
    local road = type(row.road) == "table" and row.road or nil
    local rating = road and type(road.rating) == "table" and road.rating or nil
    if not rating or rating.kind ~= ns.Roads.RATING_ITEM then
        return nil, nil
    end
    for _, also in ipairs(rating.alsoAt or {}) do
        if also.dropType == ns.UFImport.DROP_TYPE_MAX then
            return rating, also
        end
    end
    return rating, nil
end

-- The row a card wears (UX-6b's choice, widened by UX-6d, WKE-641): the drop
-- row if it is an upgrade, else the crested row if it is, else the drop row -
-- and with no drop row, the crested row. The owner, of the cards drawn only
-- for their crested row: "badge them and show the player it would be better
-- if they [crested] it." One pure choice, read both by what is drawn
-- (Panel.CardWorthDrawing) and by what the card says (Panel.OtherLevelRow,
-- Panel.CardFace), so the two cannot disagree. It picks one of his rows; it
-- never computes one.
function Panel.WornRow(drop, max)
    if drop ~= nil and isUpgradePercent(drop.percent) then
        return drop
    end
    if max ~= nil and isUpgradePercent(max.percent) then
        return max
    end
    if drop ~= nil then
        return drop
    end
    return max
end

function Panel.CardWorthDrawing(row)
    if type(row) ~= "table" then
        return false
    end
    if Panel.IsImperative(row.todo) or row.planPick == true then
        return true
    end
    local road = type(row.road) == "table" and row.road or {}
    if road.phrase == ns.Roads.PHRASE_RATED_LATER then
        return true
    end
    -- A per-item card - a drop rated at another level (UX-6b) or where it
    -- drops - is drawn when the row it wears is an upgrade: its drop row, or
    -- the same drop with its crests spent, a reason to run it.
    local drop, max = Panel.CardRatingRows(row)
    if drop ~= nil or max ~= nil then
        return isUpgradePercent(Panel.WornRow(drop, max).percent)
    end
    local rating = type(road.rating) == "table" and road.rating or {}
    if rating.kind == ns.Roads.RATING_SET then
        return rating.inTopSet == true
    end
    return false
end

-- Every road a slot with roads could draw as a card, in the order the list
-- sorts them (UX-7a): the set and item groups' own roads, then the drops rated
-- at another level (UX-6b, they join the item group), then the unknown ones.
-- The ones the client says are not for this spec are never drawn and are not
-- visited. `visit(row, group)` is called for each; the walk stops at the first
-- that answers true and hands that true back, so one pure walk serves both
-- what the list draws (Panel.Elements) and which slot starts open
-- (Panel.FirstWorthTaking). A slot with no roads is visited for nothing.
function Panel.EachSlotCard(section, documents, visit)
    if type(section) ~= "table" or type(section.roadGroups) ~= "table" then
        return false
    end
    for _, group in ipairs(section.roadGroups) do
        if group.group ~= ns.Roads.GROUP_NONE then
            for _, row in ipairs(Panel.CardRows(group)) do
                if visit(row, group.group) then
                    return true
                end
            end
        end
    end
    local sorted = section.noRating or Panel.SortNoRating(section, documents)
    for _, row in ipairs(sorted.otherLevel) do
        if visit(row, ns.Roads.GROUP_ITEM) then
            return true
        end
    end
    for _, row in ipairs(sorted.unknown) do
        if visit(row, ns.Roads.GROUP_NONE) then
            return true
        end
    end
    return false
end

-- What a card drawn for its crested row says (UX-6d, WKE-641). The face line
-- is the todo's place in the todo's voice (`do: Catalyst it`, `do: equip it`,
-- stripped as a card strips them), and it is only on the card: the road keeps
-- its own step, so ns.Roads.GateImperatives and the printed line are untouched.
-- The hover names both of his rows: where it drops and that the drop row is
-- not better there, then the crested row and its figure.
Panel.CREST_IT = "crest it to %d"
Panel.CRESTED_HOVER = "drops at %d · %s · crested to %d, %s"
Panel.CRESTED_NOT_AS_DROPS = "not better as it drops"
Panel.CRESTED_NOT_AT = "not better at %d"

-- Puts the crested row on a card copy: the badge its figure in its own tone,
-- the face line, the one hover line. `dropClause` says what the drop row was.
local function wearCrested(copy, max, dropClause, dropsAt)
    local badge = ns.Roads.ItemBadge(max.percent)
    copy.badge = badge and { text = badge, tone = "better" } or nil
    copy.levelLine = string.format(Panel.CREST_IT, max.level)
    copy.otherLevelHover = {
        string.format(Panel.CRESTED_HOVER, tonumber(dropsAt) or 0, dropClause, max.level, badge or ""),
    }
    copy.wearsCrested = true
end

-- The slot line's badge: the best road's own badge, in that road's tone. A
-- whole-set pick that is not what you wear is the answer and wins; otherwise
-- the highest per-item percent that is forward; otherwise nothing, because no
-- road beats what is worn. Nothing is computed - it is one road's badge, chosen
-- by ns.Roads.IsForward, and two scales are never compared: the set group is
-- asked first because it comes first in the fixed order.
function Panel.SlotBadge(section)
    local groups = type(section) == "table" and section.roadGroups or nil
    if type(groups) ~= "table" then
        return nil
    end
    local best, bestPercent
    for _, group in ipairs(groups) do
        for _, row in ipairs(Panel.CardRows(group)) do
            if row.badge and ns.Roads.IsForward(row.road) then
                if group.group == ns.Roads.GROUP_SET then
                    return row.badge
                end
                local percent = tonumber(row.road.rating.percent)
                if group.group == ns.Roads.GROUP_ITEM and percent and (not bestPercent or percent > bestPercent) then
                    best, bestPercent = row.badge, percent
                end
            end
        end
    end
    return best
end

-- The badge on a card's plate. A no-rating road has none: its phrase is its
-- second line instead, and a plate of grey words over art reads as a verdict.
function Panel.CardBadge(row)
    if type(row) ~= "table" or row.group == ns.Roads.GROUP_NONE then
        return nil
    end
    return row.badge
end

-- A card's second line: where it comes from, or for a no-rating road its phrase.
function Panel.CardSecond(row)
    if type(row) ~= "table" then
        return nil
    end
    if row.group == ns.Roads.GROUP_NONE then
        return row.badge and row.badge.text or nil
    end
    return row.second
end

-- A card's last line: the step without its `do: ` (the card is the imperative),
-- or with no step, the road's first fact.
function Panel.CardLine(row)
    if type(row) ~= "table" then
        return nil
    end
    if row.levelLine then
        return row.levelLine
    end
    local todo = row.todo
    if type(todo) == "string" and todo ~= "" then
        local prefix = ns.Roads.TODO_PREFIX
        if todo:sub(1, #prefix) == prefix then
            return todo:sub(#prefix + 1)
        end
        return todo
    end
    return row.facts and row.facts[1] or nil
end

-- What a card's hover says under the item's own tooltip: the badge against its
-- scale, the facts a tooltip may carry, the cost, and where a click goes.
function Panel.CardTooltipLines(row)
    local lines = {}
    if type(row) ~= "table" then
        return lines
    end
    local badge = Panel.CardBadge(row)
    if row.otherLevelHover then
        for _, line in ipairs(row.otherLevelHover) do
            lines[#lines + 1] = line
        end
    elseif badge and badge.text then
        if row.group == ns.Roads.GROUP_ITEM then
            lines[#lines + 1] = badge.text .. Panel.ROAD_SEPARATOR .. ns.Roads.ITEM_SCALE_TEXT
        else
            lines[#lines + 1] = badge.text
        end
    end
    if row.tooltipFactsText then
        lines[#lines + 1] = row.tooltipFactsText
    end
    if row.costText then
        lines[#lines + 1] = row.costText
    end
    if Panel.CardClicks(row) then
        lines[#lines + 1] = Panel.CARD_CLICK_TEXT[row.verb]
    end
    return lines
end

-- Whether a click on the card goes anywhere: the two verbs a card follows, and
-- only where RoadRow found the destination.
function Panel.CardClicks(row)
    if type(row) ~= "table" then
        return false
    end
    return (row.verb == ns.Roads.VERB_SHOW_RUN and row.runKey ~= nil)
        or (row.verb == ns.Roads.VERB_SHOW_IN_VAULT and row.vaultKey ~= nil)
end

-- The one lookup a card's art needs: which picture the walk recorded for an
-- instance. The walk's entries carry it (Modules/Journal.lua); no road does.
-- A walk taken before the art was recorded answers an empty table.
function Panel.InstanceImages(sources)
    local images = {}
    for _, list in pairs(type(sources) == "table" and sources or {}) do
        for _, entry in ipairs(list) do
            if entry.instanceID ~= nil and entry.instanceImage ~= nil and images[entry.instanceID] == nil then
                images[entry.instanceID] = entry.instanceImage
            end
        end
    end
    return images
end

function Panel.CardArt(row, images)
    local source = type(row) == "table" and type(row.road) == "table" and row.road.source or nil
    if type(source) ~= "table" or source.instanceID == nil or type(images) ~= "table" then
        return nil
    end
    return images[source.instanceID]
end

-- The slot line's hover: the slot, its sentence, the long group headers (the
-- two scale clauses, the set group's arrangement), the Keep row as printed,
-- and the count of hidden level-1 drops. Everything the line stopped saying.
function Panel.SlotTooltipLines(section)
    if type(section) ~= "table" or type(section.slot) ~= "string" then
        return {}
    end
    local lines = { section.slot }
    if section.plan then
        lines[#lines + 1] = section.plan
    end
    for _, group in ipairs(section.roadGroups or {}) do
        if group.header then
            lines[#lines + 1] = group.header
        end
    end
    for _, group in ipairs(section.roadGroups or {}) do
        for _, row in ipairs(group.rows or {}) do
            if row.kind == ns.Roads.KIND_KEEP then
                lines[#lines + 1] = Panel.RoadLineText(row)
            end
        end
    end
    if section.hiddenNote then
        lines[#lines + 1] = section.hiddenNote
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- The `No rating` flood, sorted before it is folded (UX-6b, WKE-639). The owner
-- (WKE-592, 2026-09-23 night): "We should look at capping no-rating cards" and
-- "Is there any way of us knowing if these no rating items are even worth the
-- player trying to get?"
--
-- What "no rating" means is the source's own: the Upgrade Finder rates every
-- item it builds and keeps every result, whatever its sign
-- (UpgradeFinderEngine.js:105-135, UpgradeFinderResult.js:1-13,
-- UpgradeFinderFront.js:157, UpgradeFinderJSONExport.ts:16-31), so a drop with
-- no row was never rated - it is never "rated and not worth it". Why it was
-- not is one of three things, and each is drawn differently:
--
--   * otherLevel - his documents DO carry the item, at another level: a raid
--     item is rated at ONE difficulty and a dungeon item at ONE key level per
--     run (UpgradeFinderEngine.js:143-177, :256-288). The card carries that row
--     whole, and says at which level (Panel.OtherLevelRating).
--   * offspec - the client says the item is not for this spec
--     (ns.ItemData.SpecFit): what his `checkItemViable` throws out before
--     rating (:381-404). Not drawn; `/lootpath status` still prints it.
--   * unknown - neither. Folded behind one line per slot, shut by default.
Panel.NO_RATING_OTHER_LEVEL = "otherLevel"
Panel.NO_RATING_OFFSPEC = "offspec"
Panel.NO_RATING_UNKNOWN = "unknown"

-- The row his documents carry for a drop at another level, or nil: the `drop`
-- row at the lowest level any document carries one, and the `max` row - the
-- item with its crests spent - OUT OF THE SAME DOCUMENT, because a card's
-- figures all come from one run (ns.Roads' `otherLevels`, docs/ROADS-UX.md
-- surface 2). With no drop row, the lowest `max` row any document carries.
-- Each is his entry and its level, unchanged (ns.UFImport.OtherLevelEntry);
-- nothing is scaled toward the level the drop arrives at.
function Panel.OtherLevelRating(documents, itemID)
    if type(documents) ~= "table" or itemID == nil then
        return nil
    end
    local function row(list, dropType)
        local entry, level, keyLevel, document = ns.UFImport.OtherLevelEntry(list, itemID, dropType)
        if not entry then
            return nil
        end
        return { entry = entry, level = level, keyLevel = keyLevel, percent = entry.upgradePercent }, document
    end
    local drop, document = row(documents, ns.UFImport.DROP_TYPE_DROP)
    local max = row(drop and { document } or documents, ns.UFImport.DROP_TYPE_MAX)
    if not drop and not max then
        return nil
    end
    return { drop = drop, max = max }
end

-- Which of the three a no-rating road is. Pure: `specFit(road)` is the
-- caller's client answer (true, false, or nil for "cannot tell"). Only a
-- journal drop can be either of the first two - the documents rate drops, and
-- a vault reward or a piece you own is yours whatever spec it names. A drop
-- his documents carry was viable to him by construction, so otherLevel is
-- asked first.
function Panel.NoRatingKind(road, documents, specFit)
    if type(road) ~= "table" or road.group ~= ns.Roads.GROUP_NONE then
        return nil
    end
    if road.kind == ns.Roads.KIND_DROP then
        local itemID = road.item and road.item.itemID or nil
        if Panel.OtherLevelRating(documents, itemID) then
            return Panel.NO_RATING_OTHER_LEVEL
        end
        if type(specFit) == "function" and specFit(road) == false then
            return Panel.NO_RATING_OFFSPEC
        end
    end
    return Panel.NO_RATING_UNKNOWN
end

-- What an other-level card says. `rated at` for his drop row, `crested to` for
-- the row with the crests spent; the hover adds where the drop arrives.
Panel.OTHER_LEVEL_DROP = "rated at %d"
Panel.OTHER_LEVEL_MAX = "crested to %d"
Panel.OTHER_LEVEL_HOVER = "%s · %s, drops at %d"
Panel.OTHER_LEVEL_ALSO = "%s · %s"

-- A no-rating row as the card its other-level rating draws: the same row, in
-- the rated group, its badge the figure of the row it carries - the drop row
-- when there is one, else the max row - and the level on its own line. When
-- both exist the max row rides on the hover: the rule a rated row's own
-- `at its cap 334 +0.72%` follows (ns.Roads' `otherLevels`,
-- Panel.RoadFactEntries), where the drop figure is the badge and the cap is
-- the muted second figure. Since UX-6d (WKE-641) a drop row that is not an
-- upgrade beside a crested row that is gives the card to the crested row
-- (Panel.WornRow): its figure on the badge, `crest it to 308` on the face.
function Panel.OtherLevelRow(row, rating)
    if type(row) ~= "table" or type(rating) ~= "table" then
        return nil
    end
    local shown = rating.drop or rating.max
    local shape = rating.drop and Panel.OTHER_LEVEL_DROP or Panel.OTHER_LEVEL_MAX
    local copy = {}
    for key, value in pairs(row) do
        copy[key] = value
    end
    copy.group = ns.Roads.GROUP_ITEM
    copy.otherLevel = rating
    if rating.drop and rating.max and Panel.WornRow(rating.drop, rating.max) == rating.max then
        wearCrested(copy, rating.max, string.format(Panel.CRESTED_NOT_AT, rating.drop.level), row.itemLevel)
        return copy
    end
    local badge = ns.Roads.ItemBadge(shown.percent)
    local percent = tonumber(shown.percent)
    local tone = "none"
    if percent and percent ~= 0 then
        tone = percent > 0 and "better" or "worse"
    end
    copy.badge = badge and { text = badge, tone = tone } or nil
    copy.levelLine = string.format(shape, shown.level)
    local hover = {}
    if badge then
        hover[#hover + 1] = string.format(Panel.OTHER_LEVEL_HOVER, badge, copy.levelLine, tonumber(row.itemLevel) or 0)
    end
    local max = rating.drop and rating.max or nil
    if max and max.level ~= rating.drop.level then
        local maxBadge = ns.Roads.ItemBadge(max.percent)
        if maxBadge then
            hover[#hover + 1] =
                string.format(Panel.OTHER_LEVEL_ALSO, string.format(Panel.OTHER_LEVEL_MAX, max.level), maxBadge)
        end
    end
    copy.otherLevelHover = hover
    return copy
end

-- Every no-rating row of a slot, sorted into the three (Panel.NoRatingKind).
-- The other-level rows come back as their cards (Panel.OtherLevelRow), best
-- figure first - his number's order, the rated group's own rule - and the
-- model's order behind it; the other two keep the model's order.
function Panel.SortNoRating(section, documents, specFit)
    local sorted = { otherLevel = {}, offspec = {}, unknown = {} }
    for _, group in ipairs(type(section) == "table" and section.roadGroups or {}) do
        if group.group == ns.Roads.GROUP_NONE then
            for _, row in ipairs(Panel.CardRows(group)) do
                local kind = Panel.NoRatingKind(row.road, documents, specFit)
                if kind == Panel.NO_RATING_OTHER_LEVEL then
                    local itemID = row.road.item and row.road.item.itemID or nil
                    sorted.otherLevel[#sorted.otherLevel + 1] =
                        Panel.OtherLevelRow(row, Panel.OtherLevelRating(documents, itemID))
                elseif kind == Panel.NO_RATING_OFFSPEC then
                    sorted.offspec[#sorted.offspec + 1] = row
                else
                    sorted.unknown[#sorted.unknown + 1] = row
                end
            end
        end
    end
    local position = {}
    for index, row in ipairs(sorted.otherLevel) do
        position[row] = index
    end
    -- The figure the card wears (Panel.WornRow), so the badges read in order.
    local function figure(row)
        local shown = Panel.WornRow(row.otherLevel.drop, row.otherLevel.max)
        return tonumber(shown.percent) or 0
    end
    table.sort(sorted.otherLevel, function(left, right)
        local a, b = figure(left), figure(right)
        if a ~= b then
            return a > b
        end
        return position[left] < position[right]
    end)
    return sorted
end

-- The card a road rated where it drops is drawn as (UX-6d, WKE-641): the row
-- itself, unless the row it wears (Panel.WornRow) is its crested row - the
-- drop row not an upgrade, the `max` row of the same document one - and then
-- a copy wearing it: the crested figure on the badge, `crest it to 334` on the
-- face, and the hover naming both rows. The cap clause leaves that copy's
-- hover facts, because the hover's first line now says it. The road, the row
-- the model keeps and its printed line (`at its cap 334 +0.31%` already on
-- it) are untouched. A drop rated at another level is already its card
-- (Panel.OtherLevelRow), and comes back as it is.
function Panel.CardFace(row)
    if type(row) ~= "table" or row.otherLevel ~= nil then
        return row
    end
    local drop, max = Panel.CardRatingRows(row)
    if drop == nil or max == nil or Panel.WornRow(drop, max) ~= max then
        return row
    end
    local copy = {}
    for key, value in pairs(row) do
        copy[key] = value
    end
    wearCrested(copy, max, Panel.CRESTED_NOT_AS_DROPS, row.itemLevel)
    local shape = Panel.ROAD_ALSO_AT_TEXT[max.label] or Panel.ROAD_ALSO_AT_DEFAULT
    local capFact = max.label and max.badge and string.format(shape, max.label, max.level, max.badge) or nil
    local facts = {}
    for _, text in ipairs(row.tooltipFacts or {}) do
        if text ~= capFact then
            facts[#facts + 1] = text
        end
    end
    copy.tooltipFacts = facts
    copy.tooltipFactsText = #facts > 0 and table.concat(facts, Panel.ROAD_SEPARATOR) or nil
    return copy
end

-- The fold over everything a slot does not draw (UX-6c, WKE-640; it absorbs
-- UX-6b's `No rating` fold): Equip Now's pattern (M5-1b) - the mark, then the
-- line with its count - one per slot, shut by default. The count is how much
-- was left out, so nothing leaves the screen silently (docs/ROADS-UX.md
-- principle 3); the hover splits it into the two reasons, each counted once:
-- rated, and not above what you wear; and never rated at all.
Panel.FOLD_TEXT = "%d more %s"
Panel.FOLD_NOUN = { drop = { "drop", "drops" }, item = { "item", "items" } }
Panel.FOLD_RATED = "%d rated below what you wear"
Panel.FOLD_UNRATED = "%d not rated"

-- Whether a folded road was rated: a document row carried whole (UX-6b's
-- other-level cards) or any rating ns.Roads.IsRated counts, which includes
-- `not in your best set`.
function Panel.FoldIsRated(row)
    return type(row) == "table" and (row.otherLevel ~= nil or ns.Roads.IsRated(row.road))
end

-- The fold's counts: every row, the rated ones, the unrated ones, and whether
-- every one of them is a drop (the noun is the rows' own).
function Panel.FoldCounts(rows)
    local count, rated, allDrops = 0, 0, true
    for _, row in ipairs(rows or {}) do
        count = count + 1
        if Panel.FoldIsRated(row) then
            rated = rated + 1
        end
        if row.kind ~= ns.Roads.KIND_DROP then
            allDrops = false
        end
    end
    return count, rated, count - rated, allDrops
end

function Panel.FoldText(rows, open)
    return Panel.FoldTextOf(open, Panel.FoldCounts(rows))
end

function Panel.FoldTextOf(open, count, _, _, allDrops)
    local noun = Panel.FOLD_NOUN[allDrops and "drop" or "item"]
    local mark = open and Panel.SECTION_OPEN_MARK or Panel.SECTION_SHUT_MARK
    return mark .. " " .. string.format(Panel.FOLD_TEXT, count, noun[count == 1 and 1 or 2])
end

-- The fold's hover: the two counts, a zero one not printed.
function Panel.FoldHover(rows)
    return Panel.FoldHoverOf(Panel.FoldCounts(rows))
end

function Panel.FoldHoverOf(_, rated, unrated)
    local parts = {}
    if rated > 0 then
        parts[#parts + 1] = string.format(Panel.FOLD_RATED, rated)
    end
    if unrated > 0 then
        parts[#parts + 1] = string.format(Panel.FOLD_UNRATED, unrated)
    end
    return #parts > 0 and table.concat(parts, Panel.ROAD_SEPARATOR) or nil
end

-- Whether a slot's fold is open: true is opened by a click, and nil - no
-- click - is the default, shut. Kept per character beside collapsedSlots
-- (`db.char.upgradeMap.foldOpen`).
function Panel.FoldOpen(saved)
    return saved == true
end

function Panel.ToggleFold(db, slot)
    local state = Panel.CollapseState(db)
    -- `nil` rather than `false` when it shuts again, as Equip Now's fold does:
    -- the default leaves nothing behind in the saved variables.
    state.fold[slot] = (state.fold[slot] ~= true) or nil
    return state.fold[slot] == true
end

-- The nudge. The one no-rating road a player can act on is one a refresh would
-- rate: a vault reward the run never saw (`not rated · new since the last
-- refresh`, the only phrase ns.Roads.ForSlot gives that tail). It is counted
-- once for the tab, beside the stale-bags words, and never said on a card.
Panel.NOT_RATED_YET = "%d %s not rated yet"
Panel.NOT_RATED_NOUN = { vault = { "vault reward", "vault rewards" }, item = { "item", "items" } }

function Panel.NotRatedYetText(model)
    local count, allVault = 0, true
    for _, section in ipairs(type(model) == "table" and model.slots or {}) do
        local groups = type(section.roads) == "table" and section.roads.groups or {}
        for _, group in ipairs(ns.Roads.GROUP_ORDER) do
            for _, road in ipairs(groups[group] or {}) do
                if road.phrase == ns.Roads.PHRASE_NOT_RATED_NEW then
                    count = count + 1
                    if road.kind ~= ns.Roads.KIND_VAULT then
                        allVault = false
                    end
                end
            end
        end
    end
    if count == 0 then
        return nil
    end
    local noun = Panel.NOT_RATED_NOUN[allVault and "vault" or "item"]
    return string.format(Panel.NOT_RATED_YET, count, noun[count == 1 and 1 or 2])
end

-- The nudge, when any slot's bags are ahead of the rating or any road is new
-- since it; nil when neither. The stale-bags line alone is byte-identical to
-- UX-6's.
function Panel.StaleNudge(model)
    local parts = {}
    for _, section in ipairs(type(model) == "table" and model.slots or {}) do
        if section.staleBags == true then
            parts[1] = Panel.STALE_BAGS_TEXT
            break
        end
    end
    parts[#parts + 1] = Panel.NotRatedYetText(model)
    if #parts == 0 then
        return nil
    end
    parts[#parts + 1] = ns.Roads.VERB_REFRESH
    return table.concat(parts, Panel.ROAD_SEPARATOR)
end

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
-- Which plan rated it, said on the row of the one road whose plan is not the
-- group's (R-3c, WKE-580): the Upgrade road is always the `maxed` run's answer,
-- because that is the run that asked what your gear is worth upgraded.
Panel.ROAD_CREST_PLAN_TEXT = "rated under %s"

-- Explain (principle 11). One plain sentence under the FIRST VISIBLE USE of a
-- system word in the expanded slot, in the note colour, off by default. Each
-- says only what the client says or what the rating names: no cadence, no
-- promise, no deadline, and no source.
Panel.EXPLAIN_WORDS = { "picks", "Catalyst", "crest", "track", "spark", "Bountiful" }
Panel.EXPLAIN = {
    picks = "picks: which assumptions a rating was made under: as offered, catalyzed, this week's picks,"
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
        -- Except the Upgrade road, which since R-3c (WKE-580) reads the `maxed`
        -- document whatever plan the screen is following: it is a whole-set
        -- verdict and belongs in this group, but it answers a different
        -- question and must not be what the group's header names. Its own row
        -- says which question it answers (Panel.RoadSecond).
        if road.plan and road.kind ~= ns.Roads.KIND_CREST then
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
    -- Once the reward is in the bags the vault road says so instead of saying
    -- the vault is open (R-3b, WKE-576): the reader already walked it.
    local when = road.claimed or road.openNow
    if when then
        return tag .. Panel.ROAD_SEPARATOR .. when
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
    -- The Upgrade road's verdict comes from the `maxed` run and no other, so it
    -- says so on its own line rather than borrowing the group header's plan
    -- (R-3c, WKE-580).
    if road.kind == ns.Roads.KIND_CREST and road.plan then
        parts[#parts + 1] = string.format(Panel.ROAD_CREST_PLAN_TEXT, road.plan)
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
    for _, entry in ipairs(Panel.RoadFactEntries(road)) do
        facts[#facts + 1] = entry.text
    end
    return facts
end

-- The same list, each entry saying whether the TOOLTIP may carry it (R-2a,
-- WKE-571). Two of them may not, and for the same reason in two shapes: the
-- surface the clause is true on is not the surface the reader is looking at.
--
--   * a cost clause ("crest type and cost not readable") is 568's vendor-window
--     gate. On the Upgrade Map row it answers "what will this cost me", beside
--     the crest counts the reader can see. On a tooltip nobody asked, there are
--     no counts beside it, and it can never become readable.
--   * a rival clause ("the same charge as the vault Spaulders road") is a
--     reference to another row. Principle 6's own rule is that a reference is
--     never to a road that is not on the same screen - and a tooltip about one
--     item is never that screen.
--
-- The panel carries both, because on the panel both referents are visible.
function Panel.RoadFactEntries(road)
    local facts = {}
    if type(road) ~= "table" then
        return facts
    end
    local function note(text, offTooltip)
        if text then
            facts[#facts + 1] = { text = text, offTooltip = offTooltip or nil }
        end
    end
    local rating = road.rating
    if rating and rating.referent then
        note(rating.referent)
    end
    for _, also in ipairs((rating and rating.alsoAt) or {}) do
        if also.label and also.level and also.badge then
            local shape = Panel.ROAD_ALSO_AT_TEXT[also.label] or Panel.ROAD_ALSO_AT_DEFAULT
            note(string.format(shape, also.label, also.level, also.badge))
        end
    end
    note(road.rivalText, true)
    local cost = {}
    for _, text in ipairs(ns.Roads.CostFacts(road)) do
        cost[text] = true
    end
    for _, text in ipairs(ns.Roads.Facts(road)) do
        note(text, cost[text])
    end
    note(ns.Roads.ResetText(road.resetSeconds))
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
    local entries = Panel.RoadFactEntries(road)
    local facts, tooltipFacts = {}, {}
    for _, entry in ipairs(entries) do
        facts[#facts + 1] = entry.text
        if not entry.offTooltip then
            tooltipFacts[#tooltipFacts + 1] = entry.text
        end
    end
    local cost = ns.Roads.CostFacts(road)
    local badge = road.rating and road.rating.badge or road.phrase
    local row = {
        road = road,
        kind = road.kind,
        group = road.group,
        slot = road.slot,
        tag = Panel.RoadTag(road),
        planPick = road.planPick == true,
        itemID = road.item and road.item.itemID or nil,
        -- A drop road draws a journal entry, so it has the same hover as the
        -- map's own rows: the client's link where the walk kept one, and the
        -- base-level note where it did not (M5-3a). A road that is not a drop
        -- carries neither - its item is named by a document, not by a walk.
        link = road.item and road.item.link or nil,
        levelNote = (road.kind == ns.Roads.KIND_DROP and not (road.item and road.item.link))
                and Panel.BaseLevelNote(road.source, previewMythicPlusLevel)
            or nil,
        -- Only a drop arrives at a level a walk previewed, so only a drop can
        -- disagree with what its link draws on its own (M5-3b).
        keyLevel = road.kind == ns.Roads.KIND_DROP
                and Panel.RunKeyLevel(road.source and road.source.difficultyID, previewMythicPlusLevel, road.source)
            or nil,
        dropLevel = road.kind == ns.Roads.KIND_DROP and tonumber(road.arrivesAt) or nil,
        name = road.item and road.item.name or nil,
        icon = road.item and road.item.icon or nil,
        quality = road.item and road.item.quality or nil,
        itemLevel = road.arrivesAt,
        second = Panel.RoadSecond(road),
        badge = badge and { text = badge, tone = Panel.RoadBadgeTone(road) } or nil,
        facts = facts,
        factsText = #facts > 0 and table.concat(facts, Panel.ROAD_SEPARATOR) or nil,
        -- What the cost clauses say on their own, so a surface can name them
        -- without re-deriving which of the facts they were (R-2a, WKE-571).
        costFacts = cost,
        costText = #cost > 0 and table.concat(cost, Panel.ROAD_SEPARATOR) or nil,
        -- The facts a tooltip may carry: everything above minus the cost and
        -- rival clauses, whose referents are only on the panel.
        tooltipFacts = tooltipFacts,
        tooltipFactsText = #tooltipFacts > 0 and table.concat(tooltipFacts, Panel.ROAD_SEPARATOR) or nil,
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
        -- What the crest vendor told the owner about the pieces he owns
        -- (M3-17b, WKE-588). A capture rather than a read, because the client
        -- answers about one item at a time and only in the vendor's own
        -- window; nil until he has stood at one.
        upgradeRows = opts.upgradeRows,
        journal = { sources = extra.sources, summary = opts.summary },
        difficultyLabels = extra.difficultyLabels,
        excluded = opts.excluded,
        passes = opts.passes,
        now = opts.now,
    }
    -- The leftover list belongs to the document the roads are read under, and
    -- it travels on that document: taking it from anywhere else would be a
    -- second answer to "was this item left out" (C-10, WKE-567).
    --
    -- The later passes belong to the same document for the same reason (C-11,
    -- WKE-572): they are the rest of THAT run, filed under that run's content
    -- type and scenario, and a pass from another scenario's run rated a
    -- different question.
    if inputs.excluded == nil or inputs.passes == nil then
        local entry = ns.Roads.Plan(inputs)
        -- The passes FIRST, because the leftover list is read off them (C-11a,
        -- WKE-586): what nothing in the run was asked about is what the LAST
        -- pass left out, and pass 1's own list is what the later passes went on
        -- to rate. `beyond the rating's item limit` is the one tail that may be
        -- read off it, and it is the same list the two tab headers count.
        if inputs.passes == nil and entry and entry.verdict then
            inputs.passes =
                ns.QEImport.Passes(ns.QEImport.ContentTypeKey(entry.verdict), ns.QEImport.ScenarioKey(entry.verdict))
        end
        if inputs.excluded == nil and entry and entry.verdict then
            inputs.excluded = ns.Companion.Unrated(entry.verdict, inputs.passes)
        end
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
-- Run Tiles (UX-5, WKE-614). The by-run list is no longer one card per run: one
-- element is a ROW of up to four tiles, and the drawer an open tile opens is one
-- element of its own, sitting directly under the row that tile is in.
Panel.ELEMENT_RUN_ROW = "runRow"
Panel.ELEMENT_DRAWER = "drawer"

-- A slot is one line (UX-6, WKE-637): the worn item's icon at the item line's
-- own size, three points clear above and below it, and nothing under it.
Panel.SLOT_ICON_X = 4
Panel.SLOT_ICON_SIZE = UI.ItemLine.ICON_SIZE
Panel.SLOT_LINE_HEIGHT = Panel.SLOT_ICON_SIZE + 6
-- The eyebrow over a group of cards.
Panel.GROUP_HEIGHT = 20
-- The item line's own icon (M5-1) plus the gap under it.
Panel.ITEM_HEIGHT = 42
Panel.NOTE_LINE_HEIGHT = 14
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

-- ---------------------------------------------------------------------------
-- The tile grid (UX-5, WKE-614).
--
-- Four across, which is the owner's answer and also the Adventure Guide's own
-- count: `CreateScrollBoxListGridView(4, ...)` in Blizzard_EncounterJournal.lua
-- (the Dungeons/Raids list, read under .luals/). Its instance button is 174 x 96
-- (Blizzard_EncounterJournal.xml:320) and draws the SAME file this walk
-- recorded - `button.bgImage:SetTexture(elementData.buttonImage)` at :379 - with
-- one fixed crop, `<TexCoords left="0" right="0.68359375" top="0"
-- bottom="0.7421875"/>` at :328. So the crop below is not a guess about what
-- shape the art is: it is the crop the client itself uses on that exact file,
-- and the tile takes the button's own 174:96 proportion so the cropped art is
-- never stretched into it (V-5a's rule).
--
-- No width is written down. The tile is (list width - three gaps) / four, so a
-- window that changes width moves the tiles rather than leaving them behind
-- (M5-2c). At the panel's own 734 less the scrollbar's room, that arithmetic
-- lands on 172 wide - the size the direction page was drawn at - and 95 tall,
-- which is what 174:96 makes of 172 rather than the page's rounder 97.
Panel.TILES_PER_ROW = 4
Panel.TILE_GAP = 8
Panel.TILE_ART_RATIO = 174 / 96
Panel.TILE_ART_TEX_COORD = { 0, 0.68359375, 0, 0.7421875 }
-- The room the scroll bar takes on the right, the same number the scroll box is
-- anchored with.
Panel.SCROLLBAR_ROOM = 22
-- The air under a row of tiles, so two rows do not touch.
Panel.TILE_ROW_PADDING = 6
-- One pip per drop, lit per rated drop. Six points, because it is a mark and
-- not a bar: no pip's SIZE is ever arithmetic on a rating - there are as many of
-- them as the journal lists drops, and as many lit as the export rated.
Panel.TILE_PIP_SIZE = 6
Panel.TILE_PIP_GAP = 2
Panel.TILE_PIP_MAX = 12
-- How far a run with nothing rated is drawn down. The same half weight a
-- settled row is dimmed to on Equip Now (ns.UI.ItemLine.DIM_ALPHA).
Panel.TILE_DIM_ALPHA = 0.5
-- The shade the words sit on: ONE texture up the bottom TILE_SHADE_FRACTION of
-- the tile, a vertical gradient from TILE_SHADE_ALPHA black at the bottom edge
-- to clear at its top (UX-5a, WKE-634), so a name in white is legible over
-- whatever the art happens to be there and no edge crosses the picture. It was
-- two flat bands until UX-5a, and their two hard edges were the lighter stripe
-- the owner saw across every tile with art. Lootpath's one drawn element, and
-- it says nothing about any item.
Panel.TILE_SHADE_ALPHA = 0.75
Panel.TILE_SHADE_FRACTION = 0.5
Panel.TILE_SHADE_ORIENTATION = "VERTICAL"
Panel.TILE_INSET = 4
Panel.TILE_NAME_HEIGHT = 14
Panel.TILE_SECOND_HEIGHT = 12
-- Blizzard's own square button highlight, drawn additively, which is what its
-- own buttons use for exactly this: `self:SetHighlightTexture([[Interface\
-- Buttons\ButtonHilight-Square]], "ADD")` in Blizzard_ActionBar's
-- VehicleLeaveButton, read under .luals/.
Panel.TILE_HIGHLIGHT_TEXTURE = [[Interface\Buttons\ButtonHilight-Square]]
Panel.TILE_HIGHLIGHT_BLEND = "ADD"
-- The frame an OPEN tile wears: the gold the Vault tab marks its pick with
-- (Panel.ROAD_PICK_COLOR), never the brand pink - the brand is the addon's own
-- mark and says nothing about a run.
Panel.TILE_OPEN_EDGE = 2
-- The mosaic: the four best rated rows' own item icons, two by two, under the
-- shade, behind the two tiles that have no instance - Crafting and Delves. A
-- Delves tile drew the `ui-journeys-delve-card` atlas until UX-5c (WKE-636),
-- and that atlas is not a picture: it is `RewardCardBG`, the background of
-- Blizzard's 317 x 106 reward card, hollow in the middle for an icon and a name
-- (`Blizzard_Journeys.xml:268-300`, under .luals/). The client names no scenic
-- art for a delve, and nothing draws a texture the client did not name. The
-- icons are at reduced alpha because they are a backdrop and not a list - the
-- rows themselves are in the drawer.
Panel.MOSAIC_COUNT = 4
Panel.MOSAIC_ALPHA = 0.55

Panel.TILE_SEPARATOR = " · "
Panel.TILE_COUNT_TEXT = "%d of %d"
-- What a run with nothing rated says on its second line, in place of the
-- difficulty. It is still clickable and its drawer still says the same thing:
-- a dim tile is a run that was looked at, not one that was left out.
Panel.TILE_NO_UPGRADE = "no drop is an upgrade"

Panel.DRAWER_CLOSE_TEXT = "click the tile to close"
Panel.DRAWER_NONE_TEXT = "no drop here is rated as an upgrade"
Panel.DRAWER_HEADER_HEIGHT = 20
Panel.DRAWER_PADDING = 6
Panel.DRAWER_POINTER_SIZE = 8

-- Road cards (UX-6, WKE-637): a road is a Run Tile. The item's own icon on the
-- shade, smaller than the slot line's so the card stays the art's; and the
-- cards start one TILE_GAP past the slot line's icon column, so they read as
-- that slot's.
Panel.CARD_ICON_SIZE = 28
Panel.CARD_INDENT = Panel.SLOT_ICON_X + Panel.SLOT_ICON_SIZE + Panel.TILE_GAP

-- How wide the list itself is. In the client the scroll box is sized by its two
-- anchors and only answers once the client has laid it out; until it does - and
-- headless, where nothing lays anything out - the panel's own width less the
-- scroll bar's room is the same arithmetic done ahead of it (M5-2c).
function Panel.ListWidth(width)
    width = tonumber(width)
    if width and width > 0 then
        return width
    end
    return (ns.UI and ns.UI.PANEL_WIDTH or 0) - Panel.SCROLLBAR_ROOM
end

-- One tile, in points. Derived from the list, never written down.
function Panel.TileSize(listWidth)
    local room = Panel.ListWidth(listWidth) - Panel.TILE_GAP * (Panel.TILES_PER_ROW - 1)
    local width = math.max(1, math.floor(room / Panel.TILES_PER_ROW))
    local height = math.max(1, math.floor(width / Panel.TILE_ART_RATIO + 0.5))
    return width, height
end

-- One road card, in points: the tile's own derivation - four across at the
-- art's proportion - over the list less the indent past the slot's icon.
function Panel.CardSize(listWidth)
    return Panel.TileSize(Panel.ListWidth(listWidth) - Panel.CARD_INDENT)
end

-- One pip per drop the journal lists for this run, true where the export rated
-- one. Capped, because forty pips is a texture rather than a count, and the
-- whole figure is on the tile's hover either way.
--
-- The two export runs have NO pips: their denominator is rated items and not a
-- run's drops (Panel.EXPORT_RUN_COUNT_TEXT), and a row of pips that meant two
-- different things on two tiles would be worse than none.
function Panel.TilePips(run)
    if type(run) ~= "table" or run.sourceKind then
        return nil
    end
    local drops = math.min(tonumber(run.drops) or 0, Panel.TILE_PIP_MAX)
    if drops <= 0 then
        return nil
    end
    local lit = math.min(tonumber(run.rated) or 0, drops)
    local pips = {}
    for index = 1, drops do
        pips[index] = index <= lit
    end
    return pips
end

-- The tile's second line: the difficulty it is run at, or - when nothing in it
-- is rated - the one thing the reader needs to know about it.
function Panel.TileSecondText(run)
    if type(run) ~= "table" then
        return ""
    end
    if (tonumber(run.rated) or 0) == 0 then
        return Panel.TILE_NO_UPGRADE
    end
    return run.difficultyLabel or ""
end

-- Name · difficulty · n of m. The tile's hover and the drawer's header line are
-- the same three facts, so there is one place they are written.
function Panel.TileDetailText(run)
    if type(run) ~= "table" then
        return ""
    end
    local parts = { run.instanceName or run.name or run.label or "" }
    if run.difficultyLabel and run.difficultyLabel ~= "" then
        parts[#parts + 1] = run.difficultyLabel
    end
    parts[#parts + 1] = string.format(Panel.TILE_COUNT_TEXT, run.rated or 0, run.drops or 0)
    return table.concat(parts, Panel.TILE_SEPARATOR)
end

-- The four best rated rows' own icons, for the mosaic behind a Crafting or a
-- Delves tile. The rows are already best first, so this is the top of the list
-- and no re-sorting.
function Panel.TileMosaic(run)
    local icons = {}
    for _, row in ipairs((type(run) == "table" and run.upgrades) or {}) do
        local icon = row.icon
        if icon == nil and row.itemID then
            local instant = ns.ItemData.Instant(row.itemID)
            icon = instant and instant.icon or nil
        end
        if icon then
            icons[#icons + 1] = icon
            if #icons == Panel.MOSAIC_COUNT then
                break
            end
        end
    end
    return icons
end

-- The part of a square item icon one mosaic cell shows (UX-5b, WKE-635), as
-- `{ left, right, top, bottom }` tex coords. A cell is half the tile each way -
-- 86 x 47 on the 172 x 95 tile - and an item icon is square, so drawn whole it
-- was stretched to nearly twice as wide as tall: the owner's "the Crafting box
-- is smooshed". V-5a's rule (§7, 2026-09-16) is that art is drawn at its own
-- proportion or cropped, never stretched, so the cell crops: a wide cell keeps
-- the icon's full width and the middle `height / width` of its height, centred;
-- a tall cell the same the other way; a square cell, or one with no size yet,
-- the whole icon. Pure: nothing here reads a frame.
function Panel.MosaicTexCoord(cellWidth, cellHeight)
    local width, height = tonumber(cellWidth) or 0, tonumber(cellHeight) or 0
    if width <= 0 or height <= 0 or width == height then
        return { 0, 1, 0, 1 }
    end
    if width > height then
        local keep = height / width
        return { 0, 1, (1 - keep) / 2, (1 + keep) / 2 }
    end
    local keep = width / height
    return { (1 - keep) / 2, (1 + keep) / 2, 0, 1 }
end

-- How tall the drawer under an open tile is: its header, then one item line per
-- rated drop, or one note line when there are none.
function Panel.DrawerHeight(run)
    local rows = #((type(run) == "table" and run.upgrades) or {})
    local body = rows > 0 and rows * Panel.ITEM_HEIGHT or Panel.NOTE_LINE_HEIGHT
    return Panel.DRAWER_HEADER_HEIGHT + body + Panel.DRAWER_PADDING * 2
end

function Panel.GroupHeight(text)
    return math.max(Panel.GROUP_HEIGHT, Panel.NoteHeight(text))
end

-- Which slot sections are collapsed and which runs are expanded. Kept per
-- character in the database (`db.char.upgradeMap`), because which slot the
-- owner cares about is about the character and not the account.
function Panel.CollapseState(db)
    db = db or ns.db
    local char = db and db.char
    if type(char) ~= "table" then
        return { slots = {}, runs = {}, fold = {} }
    end
    char.upgradeMap = char.upgradeMap or {}
    char.upgradeMap.collapsedSlots = char.upgradeMap.collapsedSlots or {}
    char.upgradeMap.expandedRuns = char.upgradeMap.expandedRuns or {}
    -- Which slots' fold the character opened (UX-6c; UX-6b kept the narrower
    -- `No rating` fold under `noRatingOpen`, which nothing reads any more and
    -- nothing migrates - a nil reads as shut): true is opened, nil the
    -- default, shut (Panel.FoldOpen).
    char.upgradeMap.foldOpen = char.upgradeMap.foldOpen or {}
    return {
        slots = char.upgradeMap.collapsedSlots,
        runs = char.upgradeMap.expandedRuns,
        fold = char.upgradeMap.foldOpen,
    }
end

-- The by-slot list. A slot is one line whether or not it is open; what it
-- opens onto is drawn only when it is. Since UX-6 (WKE-637) a slot with roads
-- opens onto its roads as cards under a short eyebrow per group, and the notes
-- that were conditions on the answer - the documents note, the slot's
-- sentence, the refresh on its line, the count of hidden drops - are on the
-- hovers instead. The printed lines (Panel.Lines) keep every one of them.
function Panel.Elements(model, state)
    state = state or {}
    local collapsed = state.slots or {}
    local foldState = state.fold or {}
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
        note("No import yet, so no drop carries a value. Paste a Top Gear export to change that.")
    end
    -- The documents note is on no surface of this view since UX-6: it names a
    -- source's documents (the voice rule, 2026-09-11), and UX-5 already took it
    -- off the by-run view for that reason. It stays in the printed lines.

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

    local firstWorth = Panel.FirstWorthTaking(model)
    local cardWidth, cardHeight = Panel.CardSize(state.listWidth)
    for _, section in ipairs(model.slots) do
        local open = Panel.SlotOpen(collapsed[section.slot], section, firstWorth)
        add({
            kind = Panel.ELEMENT_SECTION,
            height = Panel.SLOT_LINE_HEIGHT,
            slot = section.slot,
            -- The slot's name alone (the owner's answer); the refresh that used
            -- to ride on it is the tab's one nudge (Panel.StaleNudge).
            header = section.slot,
            worn = section.worn,
            badge = Panel.SlotBadge(section),
            collapsed = not open,
            section = section,
        })
        if open and section.roadGroups then
            -- Up to four cards a row, filled across in the group's own order:
            -- the order is the model's and is not re-sorted.
            local function cards(rows, group)
                local cardRow
                for _, row in ipairs(rows) do
                    if not cardRow or #cardRow.cards >= Panel.TILES_PER_ROW then
                        cardRow = add({
                            kind = Panel.ELEMENT_CARD_ROW,
                            height = cardHeight + Panel.TILE_ROW_PADDING,
                            tileWidth = cardWidth,
                            tileHeight = cardHeight,
                            gap = Panel.TILE_GAP,
                            indent = Panel.CARD_INDENT,
                            group = group,
                            cards = {},
                        })
                    end
                    cardRow.cards[#cardRow.cards + 1] = { row = row, art = Panel.CardArt(row, model.instanceImages) }
                    local badge = Panel.CardBadge(row)
                    explain(Panel.CardSecond(row), badge and badge.text or nil, Panel.CardLine(row))
                end
            end
            local function eyebrow(group)
                local text = Panel.GROUP_EYEBROW[group]
                add({ kind = Panel.ELEMENT_GROUP, height = Panel.GroupHeight(text), group = group, text = text })
                explain(text)
            end
            -- The no-rating roads, sorted (UX-6b): the ones rated at another
            -- level join the rated group after its own roads, and the ones the
            -- client says are not for this spec are not drawn. Then only what
            -- is worth drawing is drawn (UX-6c, Panel.CardWorthDrawing), in
            -- each group's own order and under its own eyebrow, so the two
            -- scales still never share a row; everything else is behind the
            -- slot's one fold, counted.
            local drawn, folded, foldRows = {}, {}, {}
            for _, group in ipairs(ns.Roads.GROUP_ORDER) do
                drawn[group], folded[group] = {}, {}
            end
            -- Each card as it is drawn: a road drawn only for its crested row
            -- wears it (UX-6d, Panel.CardFace); the choice is the one
            -- CardWorthDrawing reads.
            Panel.EachSlotCard(section, model.upgradeDocuments, function(row, group)
                local into = Panel.CardWorthDrawing(row) and drawn or folded
                into[group][#into[group] + 1] = Panel.CardFace(row)
            end)
            for _, group in ipairs(ns.Roads.GROUP_ORDER) do
                if #drawn[group] > 0 then
                    eyebrow(group)
                    cards(drawn[group], group)
                end
                for _, row in ipairs(folded[group]) do
                    foldRows[#foldRows + 1] = row
                end
            end
            if #foldRows > 0 then
                local foldOpen = Panel.FoldOpen(foldState[section.slot])
                local count, rated, unrated, allDrops = Panel.FoldCounts(foldRows)
                local text = Panel.FoldTextOf(foldOpen, count, rated, unrated, allDrops)
                add({
                    kind = Panel.ELEMENT_FOLD,
                    height = Panel.GroupHeight(text),
                    slot = section.slot,
                    open = foldOpen,
                    count = count,
                    rated = rated,
                    unrated = unrated,
                    text = text,
                    hover = Panel.FoldHoverOf(count, rated, unrated),
                })
                explain(text)
                -- Open, the folded cards draw as they always have, each group
                -- under its own eyebrow; shut, none of them is built.
                if foldOpen then
                    for _, group in ipairs(ns.Roads.GROUP_ORDER) do
                        if #folded[group] > 0 then
                            eyebrow(group)
                            cards(folded[group], group)
                        end
                    end
                end
            end
        elseif open then
            for _, row in ipairs(section.candidates) do
                add({ kind = Panel.ELEMENT_ITEM, height = Panel.ITEM_HEIGHT, row = row })
            end
            note(section.hiddenNote)
        end
    end
    -- It says a drop rated at another level shows no value, which the road
    -- cards stopped being true of (UX-6b); the candidate list and the printed
    -- lines keep it.
    if not model.hasRoads then
        note(model.levelMismatchNote)
    end

    if model.pending.count > 0 then
        local open = Panel.SlotOpen(collapsed[Panel.PENDING_SECTION], {}, firstWorth)
        add({
            kind = Panel.ELEMENT_SECTION,
            height = Panel.SLOT_LINE_HEIGHT,
            slot = Panel.PENDING_SECTION,
            header = Panel.PENDING_SECTION,
            collapsed = not open,
        })
        if open then
            note(model.pending.note)
            for _, row in ipairs(model.pending.rows) do
                add({ kind = Panel.ELEMENT_ITEM, height = Panel.ITEM_HEIGHT, row = row })
            end
        end
    end
    return elements
end

-- Every note that is a CONDITION on the answer rather than part of it, in the
-- order it was written, for the hint icon's tooltip (UX-5, WKE-614; the pattern
-- is M5-1b's, built for Equip Now). Six paragraphs stood between the header and
-- the first run before this; none of them is an answer to "what should I run",
-- and none of them is lost - they are one hover away, verbatim.
--
-- `upgradeDocumentsNote` is NOT here and is on no surface of this view any more:
-- it names a source's documents, which the voice rule forbids (2026-09-11). It
-- stays on the model and in the printed lines, which is what `/lootpath status`
-- reads.
function Panel.HintLines(model, mode)
    local lines = { Panel.NOTE }
    if mode ~= Panel.MODE_RUN then
        return lines
    end
    lines[#lines + 1] = Panel.RUN_NOTE
    if type(model) == "table" then
        if model.keyLevelNote then
            lines[#lines + 1] = model.keyLevelNote
        end
        if model.exportNote then
            lines[#lines + 1] = model.exportNote
        end
    end
    return lines
end

function Panel.HintText(model, mode)
    return table.concat(Panel.HintLines(model, mode), "\n\n")
end

-- The by-run list, as Run Tiles (UX-5, WKE-614). One element is a ROW of up to
-- four tiles, best first under the chosen sort; the drawer an open tile opens is
-- one element, sitting directly under the row that tile is in.
--
-- The notes are gone from here: the answer is one sentence the panel draws above
-- the list, and everything that was a condition on it is on the hint. The two
-- that stay are the two that ARE the answer in their own state - there is no
-- map, or there is nothing to rank it by - and each is then the list's only
-- element.
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
    if not model.hasUpgrades then
        note(Panel.RUN_NO_IMPORT_NOTE)
    end

    local tileWidth, tileHeight = Panel.TileSize(state.listWidth)
    local rows = {}
    local openRun, openRow, openIndex
    for _, run in ipairs(model.runs) do
        local row = rows[#rows]
        if not row or #row.runs >= Panel.TILES_PER_ROW then
            row = {
                kind = Panel.ELEMENT_RUN_ROW,
                height = tileHeight + Panel.TILE_ROW_PADDING,
                tileWidth = tileWidth,
                tileHeight = tileHeight,
                gap = Panel.TILE_GAP,
                runs = {},
            }
            rows[#rows + 1] = row
        end
        row.runs[#row.runs + 1] = run
        if expanded[run.key] == true and not openRun then
            -- One at a time, whatever the database happens to hold: a second
            -- open key from an older build draws no second drawer.
            openRun, openRow, openIndex = run, row, #row.runs
        end
    end

    for _, row in ipairs(rows) do
        add(row)
        if row == openRow then
            add({
                kind = Panel.ELEMENT_DRAWER,
                height = Panel.DrawerHeight(openRun),
                run = openRun,
                -- Which tile of the row the pointer sits under, and how wide a
                -- tile is, so the drawer can point at the tile that opened it.
                tileIndex = openIndex,
                tileWidth = tileWidth,
                gap = Panel.TILE_GAP,
            })
        end
    end
    return elements
end

-- ---------------------------------------------------------------------------
-- Frames. Native only, no AceGUI (decision 2026-09-05).
-- Only a default: the window anchors this panel by two corners (M3-3 wiring in
-- UI/MainFrame.lua), which is what actually sizes it. The size matters for a
-- panel built on its own, which is what the render tests do - so since M5-2c
-- (WKE-609) the default is ns.UI.PANEL_WIDTH, exactly what those anchors
-- produce, rather than a 620-era number of this file's own. Read at Create
-- time, not at load: this file loads after UI/MainFrame.lua but nothing here
-- should depend on that.
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
    local upgradeRows = ns.UpgradeCost.Read()
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
        upgradeRows = upgradeRows,
        specFit = Panel.ClientSpecFit(ns.Companion.CurrentSpecID()),
        inCombat = inventory.ok ~= true and inventory.reason == "combat" or nil,
    }
end

-- What the client says about a drop's spec, as Panel.NoRatingKind asks it: the
-- journal's own link when the walk kept one, else the itemID
-- (ns.ItemData.SpecFit). nil for every drop when the client names no spec.
function Panel.ClientSpecFit(specID)
    return function(road)
        local item = type(road) == "table" and road.item or nil
        if type(item) ~= "table" then
            return nil
        end
        return ns.ItemData.SpecFit(item.link or item.itemID, specID)
    end
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
-- The sort control is narrower than the difficulty control because its two
-- captions are shorter than a difficulty's, and the row has to hold both.
Panel.SORT_DROPDOWN_WIDTH = 150
-- The gap between the controls on the header row: the Adventure Guide's own,
-- read rather than chosen - `lootContainer.slotFilter:SetPoint("LEFT",
-- lootContainer.filter, "RIGHT", 10, 0)` in Blizzard_EncounterJournal.lua:453,
-- where the two loot filters sit beside each other. Those two dropdowns carry no
-- label words either (Blizzard_EncounterJournal.xml:1956-1957 declares them as
-- two bare WowStyle1DropdownTemplates), which is why this row has none: each
-- control's caption is its label.
Panel.HEADER_GAP = 10
-- The hint icon beside the title, and the art it wears. The same glyph and the
-- same grey Equip Now's hint wears (M5-1b), because they are the same thing on
-- two tabs: the conditions on the answer, one hover away.
Panel.HINT_SIZE = 12
Panel.HINT_ATLAS = "transmog-icon-warning-small"
Panel.HINT_HEX = UI.ItemLine.GREY

-- The badge column an item row keeps for QE Live's sentence. Wider than the
-- item line's own default because the sentence is his whole verdict - "QE
-- Live: better by 1.83%" - and truncating a number is not an option.
Panel.BADGE_WIDTH = 190
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
            caption = Panel.DIFFICULTY_ALL_LABEL,
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
            -- What the SHUT control says (UX-5, WKE-614): the difficulty, key
            -- level and all, without the row count. The count answers "how many
            -- rows would this leave me", which is a question you ask while
            -- choosing - so it belongs on the menu row and nowhere else.
            caption = difficulty.label,
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
            return option.caption or option.label
        end
    end
    return Panel.DIFFICULTY_ALL_LABEL
end

-- The sort control's rows (UX-5, WKE-614). Two of them, and the shut control
-- says which order is on, the way the difficulty control says which difficulty
-- is on; the two buttons that used to say it - and the word "Sort:" in front of
-- them - are gone with the label words.
Panel.SORT_MENU_LABEL = {
    [Panel.SORT_BEST] = "Best upgrade first",
    [Panel.SORT_COUNT] = "Most upgrades first",
}

function Panel.SortOptions(sort)
    local options = {}
    for _, name in ipairs(Panel.SORTS) do
        options[#options + 1] = {
            sort = name,
            label = Panel.SORT_MENU_LABEL[name],
            selected = name == sort,
        }
    end
    return options
end

function Panel.SortText(sort)
    return Panel.SORT_MENU_LABEL[sort] or Panel.SORT_MENU_LABEL[Panel.SORT_BEST]
end

function Panel.Create(parent)
    local frame = CreateFrame("Frame", "LootpathUpgradeMapPanel", parent or UIParent)
    frame:SetSize(ns.UI.PANEL_WIDTH, PANEL_HEIGHT)
    frame:Hide()

    -- ONE header row (UX-5, WKE-614): the title and its hint at the left edge,
    -- every control right-packed on the same row. What was here before was a
    -- title, a paragraph under it, and then two rows of controls chained off a
    -- "View:" label - which is what the owner saw as "smooshed" to the left with
    -- a lot of text above the first run.
    frame.header = fontString(frame, "GameFontNormal")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetText("Upgrade Map")

    -- The conditions on the answer, as an icon with the words on hover - the
    -- pattern M5-1b built for Equip Now. Nothing is lost: Panel.HintText is
    -- those notes, verbatim.
    frame.hint = CreateFrame("Button", nil, frame)
    frame.hint:SetSize(Panel.HINT_SIZE, Panel.HINT_SIZE)
    frame.hint:SetPoint("LEFT", frame.header, "RIGHT", 6, 0)
    frame.hint.icon = frame.hint:CreateTexture(nil, "ARTWORK")
    frame.hint.icon:SetAllPoints()
    frame.hint:SetScript("OnEnter", function(button)
        if GameTooltip then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            for index, line in ipairs(Panel.HintLines(frame.model, frame.mode)) do
                if index == 1 then
                    GameTooltip:SetText(line, 1, 1, 1, 1, true)
                else
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
            GameTooltip:Show()
        end
    end)
    frame.hint:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- The answer, in one sentence, under the header row and above the list. It
    -- belongs to the by-run view; in the other one the answer is each slot's
    -- line, and this line is used only for the stale-bags nudge (UX-6).
    frame.answer = fontString(frame, "GameFontNormal")
    -- Under the whole header ROW, not under the title: the controls are taller
    -- than the words beside them, and the row is one row.
    frame.answer:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -Panel.CONTROL_ROW_HEIGHT - 8)
    frame.answer:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.answer:SetWordWrap(true)
    frame.answer:SetText("")

    frame.modeButtons = {}

    -- The SELECTION template, not the filter one. Both are DropdownButtons
    -- over the 11.0 menu API, but only WowStyle1DropdownTemplate mixes in
    -- DropdownSelectionTextMixin (Blizzard_Menu/Mainline/MenuTemplates.xml:3
    -- declares `mixin="WowStyle1DropdownMixin"`; MenuTemplates.lua:753 composes
    -- that mixin from ButtonStateBehaviorMixin and DropdownSelectionTextMixin),
    -- which is where SetDefaultText lives and what lets the closed control say
    -- which difficulty is chosen; WowStyle1FilterDropdownTemplate
    -- (MenuTemplates.xml:66, MenuTemplates.lua:776) is ButtonStateBehaviorMixin
    -- + DropdownTextMixin + WowFilterButtonMixin, with a fixed FILTER caption
    -- (the KeyValue at MenuTemplates.xml:69) and no SetDefaultText - the
    -- owner's client said so with "attempt to call a nil value" at line 1865,
    -- 2026-09-09 23:10. Since T-1 (WKE-560) the headless stub says the same:
    -- `spec/stubs_spec.lua` fails if a filter dropdown ever answers it.
    frame.difficultyDropdown = CreateFrame("DropdownButton", nil, frame, Panel.DROPDOWN_TEMPLATE)
    frame.difficultyDropdown:SetSize(Panel.DROPDOWN_WIDTH, Panel.CONTROL_ROW_HEIGHT)
    -- Flush with the panel's right edge, on the header's own row: the control
    -- row is right-packed from here leftwards (UX-5).
    frame.difficultyDropdown:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
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

    -- The sort control, beside it, and shown in the by-run view alone: there is
    -- nothing to order in the other one.
    frame.sortDropdown = CreateFrame("DropdownButton", nil, frame, Panel.DROPDOWN_TEMPLATE)
    frame.sortDropdown:SetSize(Panel.SORT_DROPDOWN_WIDTH, Panel.CONTROL_ROW_HEIGHT)
    frame.sortDropdown:SetPoint("TOPRIGHT", frame.difficultyDropdown, "TOPLEFT", -Panel.HEADER_GAP, 0)
    frame.sortDropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetTag("LOOTPATH_UPGRADE_MAP_SORT")
        for _, option in ipairs(Panel.SortOptions(frame.runSort)) do
            local name = option.sort
            rootDescription:CreateRadio(option.label, function()
                return option.selected
            end, function()
                frame.runSort = name
                Panel.Refresh(frame)
            end, name)
        end
    end)
    frame.sortDropdown:Hide()

    frame.difficultyIDs = nil
    frame.mode = Panel.MODE_SLOT
    frame.runSort = Panel.SORT_BEST

    -- The list. A WowScrollBoxList over a data provider, so a map of 478 drops
    -- costs the frames that fit on screen and not one per drop; the element
    -- kinds are the element lists' own (section, item, note, run row, drawer).
    frame.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    frame.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    -- Its top is re-anchored on every refresh (Panel.AnchorList): it clears the
    -- answer sentence in the by-run view and the header row in the other one,
    -- and the sentence is one line as often as two.
    Panel.AnchorList(frame)
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

-- The header row (UX-5, WKE-614). Two buttons naming the two views, packed
-- against each other as one segment, then the sort control and the difficulty
-- control, each Panel.HEADER_GAP apart and the last one flush with the panel's
-- right edge. Both buttons stay enabled and the one for the view on screen now
-- is LIT (UX-6a, WKE-638): the template's own highlight texture held on with
-- Blizzard's `LockHighlight` (`.luals/.../Widget/Frame/Frame.lua:339`), the
-- lock R-6c put on `Load rating`, while the other wears none - so the segment
-- lights where you are, as every segmented control in Blizzard's UI does, and
-- the view you can go to is the plain one. A click on the lit one is a no-op.
-- Guarded like R-6c: a client without the lock loses the look, never the row.
local function markCurrentView(button, current)
    if current then
        if type(button.LockHighlight) == "function" then
            button:LockHighlight()
        end
    elseif type(button.UnlockHighlight) == "function" then
        button:UnlockHighlight()
    end
end

local function viewButton(list, frame, index)
    local button = list[index]
    if not button then
        button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        list[index] = button
    end
    return button
end

local function sizeViewButton(button, label)
    button:SetText(label)
    button:SetSize(math.max(Panel.CONTROL_MIN_WIDTH, math.ceil(labelWidth(button, label))), Panel.CONTROL_ROW_HEIGHT)
end

local function placeHeaderRow(frame, mode, runSort)
    -- The sort control belongs to the by-run view alone, so what the segment
    -- anchors to is whichever control is actually on the row.
    frame.sortDropdown:SetShown(mode == Panel.MODE_RUN)
    frame.sortDropdown:SetDefaultText(Panel.SortText(Panel.SORT_BEST))
    frame.sortDropdown:SetText(Panel.SortText(runSort))
    frame.sortDropdown:GenerateMenu()
    local anchor = mode == Panel.MODE_RUN and frame.sortDropdown or frame.difficultyDropdown

    -- Placed from the right, so the two buttons read left to right as one
    -- segment: By slot | By run.
    for index = #Panel.MODES, 1, -1 do
        local name = Panel.MODES[index]
        local button = viewButton(frame.modeButtons, frame, index)
        sizeViewButton(button, Panel.MODE_LABEL[name])
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", anchor, "TOPLEFT", index == #Panel.MODES and -Panel.HEADER_GAP or 0, 0)
        button:SetShown(true)
        button:SetEnabled(true)
        markCurrentView(button, mode == name)
        button:SetScript("OnClick", function()
            if frame.mode == name then
                return
            end
            frame.mode = name
            Panel.Refresh(frame)
        end)
        anchor = button
    end
end

-- Where the list starts: under the answer sentence when there is one, under the
-- header row when there is not. Both points every time, because the top one
-- moves and a stale anchor would leave the box hanging off the old one.
function Panel.AnchorList(frame)
    frame.scrollBox:ClearAllPoints()
    local answer = frame.answer
    if answer and answer:IsShown() and (answer:GetText() or "") ~= "" then
        frame.scrollBox:SetPoint("TOPLEFT", answer, "BOTTOMLEFT", 0, -8)
    else
        frame.scrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -Panel.CONTROL_ROW_HEIGHT - 8)
    end
    frame.scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Panel.SCROLLBAR_ROOM, 4)
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

-- The slot line (UX-6, WKE-637): the worn item's icon - its own hover is the
-- worn item's tooltip - the slot's name in the panel's gold, the best road's
-- badge at the right, and the open/shut mark at the far right. No sentence;
-- the line's hover carries what the sentence said.
local function ensureSection(element)
    if not element.sectionButton then
        local button = CreateFrame("Button", nil, element)
        button:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        button:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.sectionButton = button

        element.sectionIcon = UI.ItemLine.CreateIcon(button, { size = Panel.SLOT_ICON_SIZE })
        element.sectionIcon:SetPoint("TOPLEFT", button, "TOPLEFT", Panel.SLOT_ICON_X, -3)

        element.sectionName = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        element.sectionName:SetPoint("LEFT", element.sectionIcon, "RIGHT", 8, 0)
        element.sectionName:SetJustifyH("LEFT")

        element.sectionMark = button:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        element.sectionMark:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        element.sectionMark:SetWidth(12)
        element.sectionMark:SetJustifyH("CENTER")

        element.sectionBadge = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        element.sectionBadge:SetPoint("RIGHT", element.sectionMark, "LEFT", -8, 0)
        element.sectionBadge:SetJustifyH("RIGHT")
        element.sectionBadge:SetWordWrap(false)
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

-- The shade's paint (UX-5a, WKE-634). `TextureBase:SetGradient(orientation,
-- minColor, maxColor)` takes two `colorRGBA`s from `CreateColor` (Ketho,
-- Core/Widget/Base/TextureBase.lua:130-134 and Blizzard_SharedXML/Color.lua:25).
-- Which end is which is Blizzard's own to say: its nameplate border draws its
-- Bottom edge solid and its Top clear, and paints the two sides between them
-- `SetGradient("VERTICAL", CreateColor(r, g, b, a), CreateColor(r, g, b, 0))`
-- (Blizzard_NamePlates.lua:517-520, under .luals/) - so minColor is the BOTTOM.
-- A client without either function keeps the flat band at the same alpha, which
-- is what every tile drew before. Answers whether the gradient was drawn.
local function paintShade(texture)
    texture:SetTexture(WHITE_TEXTURE)
    if type(texture.SetGradient) == "function" and type(CreateColor) == "function" then
        texture:SetGradient(
            Panel.TILE_SHADE_ORIENTATION,
            CreateColor(0, 0, 0, Panel.TILE_SHADE_ALPHA),
            CreateColor(0, 0, 0, 0)
        )
        return true
    end
    texture:SetVertexColor(0, 0, 0, Panel.TILE_SHADE_ALPHA)
    return false
end

-- One tile (UX-5, WKE-614): the instance's own art filling it under a shade,
-- the run's name and its difficulty on the shade, the badge top right and the
-- pips top left. Built once per tile position on the row's element frame and
-- re-bound on every pass, the way every list in this addon works.
local function createTile(parent)
    local tile = CreateFrame("Button", nil, parent)

    -- The art, in its own layer under everything. It is cropped by Blizzard's
    -- own tex coords for this file rather than stretched to the tile; a run
    -- whose walk recorded none draws the flat back below and no picture of
    -- somewhere else.
    tile.back = tile:CreateTexture(nil, "BACKGROUND")
    tile.back:SetAllPoints()
    tile.back:SetTexture(WHITE_TEXTURE)
    tile.back:SetVertexColor(0.1, 0.1, 0.12, 1)

    tile.art = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.art:SetAllPoints()
    tile.art:Hide()

    -- The Crafting and Delves mosaic: four item icons, two by two, at reduced
    -- alpha under the shade.
    tile.mosaic = {}
    for index = 1, Panel.MOSAIC_COUNT do
        local cell = tile:CreateTexture(nil, "BACKGROUND", nil, 2)
        cell:SetAlpha(Panel.MOSAIC_ALPHA)
        cell:Hide()
        tile.mosaic[index] = cell
    end

    -- The shade: one gradient up the bottom of the tile, darkest at the bottom
    -- edge and clear where it ends (UX-5a). Lootpath's one drawn element - it
    -- is what makes a white name legible over art nobody chose, and it says
    -- nothing about any run.
    tile.shade = tile:CreateTexture(nil, "ARTWORK", nil, 1)
    paintShade(tile.shade)

    tile.name = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.name:SetJustifyH("LEFT")
    tile.name:SetWordWrap(false)

    tile.second = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tile.second:SetJustifyH("LEFT")
    tile.second:SetWordWrap(false)

    -- The badge, on a dark plate so his gold is readable over the art. The
    -- string is the card's own - `UI.ItemLine.BadgeText(run.badge)` - and
    -- nothing here formats a number.
    tile.badgePlate = tile:CreateTexture(nil, "ARTWORK", nil, 2)
    tile.badgePlate:SetTexture(WHITE_TEXTURE)
    tile.badgePlate:SetVertexColor(0, 0, 0, 0.7)
    tile.badge = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.badge:SetJustifyH("RIGHT")
    tile.badge:SetWordWrap(false)

    tile.pips = {}
    for index = 1, Panel.TILE_PIP_MAX do
        local pip = tile:CreateTexture(nil, "OVERLAY")
        pip:SetTexture(WHITE_TEXTURE)
        pip:SetSize(Panel.TILE_PIP_SIZE, Panel.TILE_PIP_SIZE)
        pip:SetPoint(
            "TOPLEFT",
            tile,
            "TOPLEFT",
            Panel.TILE_INSET + (index - 1) * (Panel.TILE_PIP_SIZE + Panel.TILE_PIP_GAP),
            -Panel.TILE_INSET
        )
        pip:Hide()
        tile.pips[index] = pip
    end

    -- The open tile's gold frame, four edges of it.
    tile.edges = {}
    for index = 1, 4 do
        local edge = tile:CreateTexture(nil, "OVERLAY", nil, 1)
        edge:SetTexture(WHITE_TEXTURE)
        edge:SetVertexColor(unpack(Panel.ROAD_PICK_COLOR))
        edge:Hide()
        tile.edges[index] = edge
    end

    -- Blizzard's own square highlight, additively, which is what its own
    -- buttons wear on hover.
    tile:SetHighlightTexture(Panel.TILE_HIGHLIGHT_TEXTURE, Panel.TILE_HIGHLIGHT_BLEND)
    return tile
end

local function sizeTile(tile, width, height)
    tile:SetSize(width, height)
    local shade = math.max(1, math.floor(height * Panel.TILE_SHADE_FRACTION))
    tile.shade:ClearAllPoints()
    tile.shade:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    tile.shade:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    tile.shade:SetHeight(shade)

    tile.second:ClearAllPoints()
    tile.second:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", Panel.TILE_INSET, Panel.TILE_INSET)
    tile.second:SetPoint("RIGHT", tile, "RIGHT", -Panel.TILE_INSET, 0)
    tile.second:SetHeight(Panel.TILE_SECOND_HEIGHT)
    tile.name:ClearAllPoints()
    tile.name:SetPoint("BOTTOMLEFT", tile.second, "TOPLEFT", 0, 1)
    tile.name:SetPoint("RIGHT", tile, "RIGHT", -Panel.TILE_INSET, 0)
    tile.name:SetHeight(Panel.TILE_NAME_HEIGHT)

    tile.badge:ClearAllPoints()
    tile.badge:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -Panel.TILE_INSET, -Panel.TILE_INSET)
    tile.badgePlate:ClearAllPoints()
    tile.badgePlate:SetPoint("TOPLEFT", tile.badge, "TOPLEFT", -3, 2)
    tile.badgePlate:SetPoint("BOTTOMRIGHT", tile.badge, "BOTTOMRIGHT", 3, -2)

    local mosaicWidth = math.max(1, math.floor(width / 2))
    local mosaicHeight = math.max(1, math.floor(height / 2))
    -- Each cell shows its icon cropped to the cell's own proportion, never
    -- stretched into it (UX-5b). The crop is kept on the cell so InitTile puts
    -- it back after SetTexture: nothing under .luals/ says whether the client
    -- keeps tex coords across a new texture, and this is right either way.
    local crop = Panel.MosaicTexCoord(mosaicWidth, mosaicHeight)
    for index, cell in ipairs(tile.mosaic) do
        cell:SetSize(mosaicWidth, mosaicHeight)
        cell.mosaicTexCoord = crop
        cell:SetTexCoord(unpack(crop))
        cell:ClearAllPoints()
        local left = (index == 1 or index == 3)
        local top = index <= 2
        cell:SetPoint(
            top and "TOPLEFT" or "BOTTOMLEFT",
            tile,
            top and "TOPLEFT" or "BOTTOMLEFT",
            left and 0 or mosaicWidth,
            0
        )
    end

    local thickness = Panel.TILE_OPEN_EDGE
    local top, bottom, left, right = tile.edges[1], tile.edges[2], tile.edges[3], tile.edges[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", tile, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    left:SetWidth(thickness)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", tile, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(thickness)
end

-- A card is a tile (UX-6): the same art, shade, badge plate, open edge and
-- highlight, plus the road's own item icon and one more line on the shade.
local function ensureCardRow(element)
    if not element.cardRow then
        local row = CreateFrame("Frame", nil, element)
        row:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        row:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.cardRow = row
        element.cards = {}
        for index = 1, Panel.TILES_PER_ROW do
            local tile = createTile(row)
            -- The item's icon, a picture on the card and not a target of its
            -- own: the card is one hover and one click.
            tile.cardIcon = UI.ItemLine.CreateIcon(tile, { size = Panel.CARD_ICON_SIZE })
            tile.cardIcon:EnableMouse(false)
            tile.cardLine = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tile.cardLine:SetJustifyH("LEFT")
            tile.cardLine:SetWordWrap(false)
            element.cards[index] = tile
        end
    end
    return element.cardRow
end

-- A card going back to the pool waits for nothing: its pending name request is
-- cancelled, so a late answer never redraws a card that has moved on.
local function clearCard(tile)
    tile.card = nil
    ns.ItemData.Cancel(tile.request)
    tile.request = nil
    UI.ItemLine.ClearIcon(tile.cardIcon)
end

-- The tile's own sizing, then the card's three lines stacked up the shade
-- beside the icon: the step at the bottom, `second` above it, the name above.
local function sizeCard(tile, width, height)
    sizeTile(tile, width, height)
    tile.cardIcon:ClearAllPoints()
    tile.cardIcon:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", Panel.TILE_INSET, Panel.TILE_INSET)
    tile.cardLine:ClearAllPoints()
    tile.cardLine:SetPoint("BOTTOMLEFT", tile.cardIcon, "BOTTOMRIGHT", Panel.TILE_INSET, 0)
    tile.cardLine:SetPoint("RIGHT", tile, "RIGHT", -Panel.TILE_INSET, 0)
    tile.cardLine:SetHeight(Panel.TILE_SECOND_HEIGHT)
    tile.second:ClearAllPoints()
    tile.second:SetPoint("BOTTOMLEFT", tile.cardLine, "TOPLEFT", 0, 1)
    tile.second:SetPoint("RIGHT", tile, "RIGHT", -Panel.TILE_INSET, 0)
    tile.second:SetHeight(Panel.TILE_SECOND_HEIGHT)
end

local function ensureRunRow(element)
    if not element.runRow then
        local row = CreateFrame("Frame", nil, element)
        row:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        row:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.runRow = row
        element.tiles = {}
        for index = 1, Panel.TILES_PER_ROW do
            element.tiles[index] = createTile(row)
        end
    end
    return element.runRow
end

-- The drawer: one header line and one item line per rated drop. It is one
-- element, so its lines are built on it and the ones this run does not need are
-- hidden - a drawer for a six-drop run after a twelve-drop one shows six.
local function ensureDrawer(element)
    if not element.drawerFrame then
        local frame = CreateFrame("Frame", nil, element)
        frame:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.drawerFrame = frame

        frame.back = frame:CreateTexture(nil, "BACKGROUND")
        frame.back:SetAllPoints()
        frame.back:SetTexture(WHITE_TEXTURE)
        frame.back:SetVertexColor(0.07, 0.07, 0.08, 0.85)

        -- The pointer: a small square of the same fill at the tile's centre, so
        -- the drawer reads as belonging to the tile that opened it.
        frame.pointer = frame:CreateTexture(nil, "ARTWORK")
        frame.pointer:SetTexture(WHITE_TEXTURE)
        frame.pointer:SetVertexColor(0.07, 0.07, 0.08, 0.85)
        frame.pointer:SetSize(Panel.DRAWER_POINTER_SIZE, Panel.DRAWER_POINTER_SIZE)

        frame.head = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        frame.head:SetPoint("TOPLEFT", frame, "TOPLEFT", Panel.TILE_INSET, -Panel.DRAWER_PADDING)
        frame.head:SetJustifyH("LEFT")
        frame.head:SetWordWrap(false)

        frame.close = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Panel.TILE_INSET, -Panel.DRAWER_PADDING)
        frame.close:SetJustifyH("RIGHT")
        frame.close:SetWordWrap(false)

        frame.empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        frame.empty:SetPoint("TOPLEFT", frame.head, "BOTTOMLEFT", 0, -4)
        frame.empty:SetJustifyH("LEFT")
        frame.empty:Hide()

        element.drawerLines = {}
    end
    return element.drawerFrame
end

local function drawerLine(element, index)
    local line = element.drawerLines[index]
    if not line then
        line = UI.ItemLine.Create(element.drawerFrame, { badgeWidth = Panel.BADGE_WIDTH })
        element.drawerLines[index] = line
    end
    line:ClearAllPoints()
    local previous = index > 1 and element.drawerLines[index - 1] or nil
    if previous then
        line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(Panel.ITEM_HEIGHT - UI.ItemLine.ICON_SIZE - 2))
    else
        line:SetPoint("TOPLEFT", element.drawerFrame.head, "BOTTOMLEFT", 0, -4)
    end
    line:SetPoint("RIGHT", element.drawerFrame, "RIGHT", -Panel.TILE_INSET, 0)
    return line
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

-- The `No rating` fold line (UX-6b): Equip Now's fold, in the eyebrow's place
-- and font, the whole line the click target.
local function ensureFold(element)
    if not element.foldButton then
        local button = CreateFrame("Button", nil, element)
        button:SetPoint("TOPLEFT", element, "TOPLEFT", 0, 0)
        button:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 0, 0)
        element.foldButton = button
        element.foldText = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        element.foldText:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
        element.foldText:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        element.foldText:SetJustifyH("LEFT")
        element.foldText:SetWordWrap(false)
    end
    return element.foldButton
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
    if element.runRow and keep ~= Panel.ELEMENT_RUN_ROW then
        element.runRow:Hide()
    end
    if element.drawerFrame and keep ~= Panel.ELEMENT_DRAWER then
        for _, line in ipairs(element.drawerLines or {}) do
            UI.ItemLine.Clear(line)
        end
        element.drawerFrame:Hide()
    end
    if element.groupText and keep ~= Panel.ELEMENT_GROUP then
        element.groupText:SetText("")
        element.groupText:Hide()
    end
    if element.foldButton and keep ~= Panel.ELEMENT_FOLD then
        element.foldText:SetText("")
        element.foldButton:Hide()
    end
    if element.cardRow and keep ~= Panel.ELEMENT_CARD_ROW then
        for _, tile in ipairs(element.cards) do
            clearCard(tile)
        end
        element.cardRow:Hide()
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
        element.sectionName:SetText(data.header or data.slot)
        element.sectionBadge:SetText(UI.ItemLine.BadgeText(data.badge))
        -- A click saves which way the reader left it, per character: true is
        -- shut, false is opened, so the first-worth-taking default (nil) never
        -- overrides a choice he made (Panel.SlotOpen).
        button:SetScript("OnClick", function()
            local state = Panel.CollapseState(panel.db)
            state.slots[data.slot] = data.collapsed ~= true
            Panel.Refresh(panel)
        end)
        local tooltip = Panel.SlotTooltipLines(data.section)
        if #tooltip > 0 then
            button:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    for index, line in ipairs(tooltip) do
                        if index == 1 then
                            GameTooltip:SetText(line, 1, 1, 1, 1, true)
                        else
                            GameTooltip:AddLine(line, 1, 1, 1, true)
                        end
                    end
                    GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function()
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end)
        else
            button:SetScript("OnEnter", nil)
            button:SetScript("OnLeave", nil)
        end
        button:Show()
    elseif data.kind == Panel.ELEMENT_ITEM then
        local row = data.row or {}
        UI.ItemLine.Set(ensureItem(element), {
            itemID = row.itemID,
            link = row.link,
            levelNote = row.levelNote,
            -- Every row of this list is a journal drop, so the level it prints
            -- is the level it drops at: what the hover checks the link's own
            -- tooltip against (M5-3b).
            dropLevel = row.itemLevel,
            keyLevel = row.keyLevel,
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
    elseif data.kind == Panel.ELEMENT_FOLD then
        local button = ensureFold(element)
        element.foldText:SetText(data.text or "")
        -- A click saves which way the reader left it, per character (nil is
        -- the default, shut), and draws the list again.
        button:SetScript("OnClick", function()
            Panel.ToggleFold(panel.db, data.slot)
            Panel.Refresh(panel)
        end)
        -- The hover splits the count into its two reasons (UX-6c).
        if data.hover then
            button:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(data.hover, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function()
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end)
        else
            button:SetScript("OnEnter", nil)
            button:SetScript("OnLeave", nil)
        end
        button:Show()
    elseif data.kind == Panel.ELEMENT_CARD_ROW then
        Panel.InitCardRow(panel, element, data)
    elseif data.kind == Panel.ELEMENT_RUN_ROW then
        Panel.InitRunRow(panel, element, data)
    elseif data.kind == Panel.ELEMENT_DRAWER then
        Panel.InitDrawer(element, data)
    end
    return element
end

-- One row of up to four tiles (UX-5, WKE-614). Every tile is re-bound here and
-- the positions this row does not fill are hidden, because the scroll box pools
-- frames: a row of two after a row of four must not still show four.
function Panel.InitRunRow(panel, element, data)
    local row = ensureRunRow(element)
    local width = data.tileWidth or select(1, Panel.TileSize())
    local height = data.tileHeight or select(2, Panel.TileSize())
    local gap = data.gap or Panel.TILE_GAP
    local state = Panel.CollapseState(panel and panel.db)
    for index, tile in ipairs(element.tiles) do
        local run = data.runs and data.runs[index] or nil
        if run then
            sizeTile(tile, width, height)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", row, "TOPLEFT", (index - 1) * (width + gap), 0)
            Panel.InitTile(panel, tile, run, state.runs[run.key] == true)
            tile:Show()
        else
            tile:Hide()
        end
    end
    row:Show()
    return element
end

-- One tile. Every string on it is the run's own and every number is the one the
-- card printed; the pips are a count of the journal's drops and of the export's
-- ratings, and nothing here is arithmetic on a rating.
function Panel.InitTile(panel, tile, run, open)
    tile.run = run
    local rated = (tonumber(run.rated) or 0) > 0

    -- The art. A walked run draws the instance's own file, cropped exactly as
    -- the Adventure Guide crops it; Crafting and Delves, which have no
    -- instance, draw the mosaic of their own four best drops (UX-5c). A run
    -- with no rated rows draws the flat back and its name. Nothing draws a
    -- texture the client did not name.
    local mosaic = nil
    if run.instanceImage then
        tile.art:SetTexture(run.instanceImage)
        tile.art:SetTexCoord(unpack(Panel.TILE_ART_TEX_COORD))
        tile.art:Show()
    else
        tile.art:Hide()
        if run.sourceKind then
            mosaic = Panel.TileMosaic(run)
        end
    end
    for index, cell in ipairs(tile.mosaic) do
        local icon = mosaic and mosaic[index] or nil
        if icon then
            cell:SetTexture(icon)
            if cell.mosaicTexCoord then
                cell:SetTexCoord(unpack(cell.mosaicTexCoord))
            end
            cell:Show()
        else
            cell:Hide()
        end
    end

    tile.name:SetText(run.instanceName or run.name or run.label or "")
    tile.second:SetText(Panel.TileSecondText(run))

    -- The badge is the card's own sentence, and only where there IS one: a run
    -- with nothing rated says so on its second line instead, because a state is
    -- never a word on a tile.
    local badgeText = rated and UI.ItemLine.BadgeText(run.badge) or ""
    tile.badge:SetText(badgeText)
    tile.badgePlate:SetShown(badgeText ~= "")

    local pips = Panel.TilePips(run)
    for index, pip in ipairs(tile.pips) do
        local lit = pips and pips[index]
        if lit == nil then
            pip:Hide()
        else
            local r, g, b = UI.ItemLine.RGB(lit and UI.ItemLine.TONE.better.hex or UI.ItemLine.GREY)
            pip:SetVertexColor(r, g, b, lit and 1 or 0.4)
            pip:Show()
        end
    end

    for _, edge in ipairs(tile.edges) do
        edge:SetShown(open == true)
    end
    tile:SetAlpha(rated and 1 or Panel.TILE_DIM_ALPHA)

    local detail = Panel.TileDetailText(run)
    tile:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(detail, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    tile:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    tile:SetScript("OnClick", function()
        local state = Panel.CollapseState(panel and panel.db)
        local wasOpen = state.runs[run.key] == true
        -- One run open at a time (the owner's answer): opening one shuts every
        -- other, and clicking the open one shuts it.
        for key in pairs(state.runs) do
            state.runs[key] = nil
        end
        if not wasOpen then
            state.runs[run.key] = true
        end
        Panel.Refresh(panel)
    end)
    return tile
end

-- The drawer under an open tile: the run's three facts, the way out, and one
-- item line per rated drop in the model's own order. Nothing else.
function Panel.InitDrawer(element, data)
    local frame = ensureDrawer(element)
    local run = data.run or {}
    frame.head:SetText(Panel.TileDetailText(run))
    frame.close:SetText(Panel.DRAWER_CLOSE_TEXT)

    local width = data.tileWidth or select(1, Panel.TileSize())
    local gap = data.gap or Panel.TILE_GAP
    local index = math.max(1, tonumber(data.tileIndex) or 1)
    frame.pointer:ClearAllPoints()
    frame.pointer:SetPoint(
        "BOTTOM",
        frame,
        "TOPLEFT",
        (index - 1) * (width + gap) + width / 2,
        -Panel.DRAWER_POINTER_SIZE / 2
    )

    local rows = run.upgrades or {}
    frame.empty:SetShown(#rows == 0)
    frame.empty:SetText(#rows == 0 and Panel.DRAWER_NONE_TEXT or "")
    for position, row in ipairs(rows) do
        UI.ItemLine.Set(drawerLine(element, position), {
            itemID = row.itemID,
            link = row.link,
            levelNote = row.levelNote,
            dropLevel = row.itemLevel,
            keyLevel = row.keyLevel,
            name = row.name,
            itemLevel = row.itemLevel,
            icon = row.icon,
            second = row.second,
            badge = row.badge,
            tags = row.tags,
        })
    end
    for position = #rows + 1, #element.drawerLines do
        UI.ItemLine.Clear(element.drawerLines[position])
    end
    frame:Show()
    return element
end

-- One row of up to four road cards (UX-6, WKE-637), placed exactly as the
-- by-run tiles are, from the indent past the slot line's icon.
function Panel.InitCardRow(panel, element, data)
    local row = ensureCardRow(element)
    local width = data.tileWidth or select(1, Panel.CardSize())
    local height = data.tileHeight or select(2, Panel.CardSize())
    local gap = data.gap or Panel.TILE_GAP
    local indent = data.indent or Panel.CARD_INDENT
    for index, tile in ipairs(element.cards) do
        local card = data.cards and data.cards[index] or nil
        if card then
            sizeCard(tile, width, height)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", row, "TOPLEFT", indent + (index - 1) * (width + gap), 0)
            Panel.InitCard(panel, tile, card)
            tile:Show()
        else
            clearCard(tile)
            tile:Hide()
        end
    end
    row:Show()
    return element
end

-- One road card. Every string on it is the road's own (RoadRow's), every number
-- is the one the road carries, and nothing is drawn that a Run Tile does not
-- draw but the item's icon and one more line.
function Panel.InitCard(panel, tile, card)
    local row = card.row or {}
    tile.card = card
    tile.run = nil

    -- The item first, so the art can fall back to its icon.
    UI.ItemLine.SetIcon(tile.cardIcon, {
        itemID = row.itemID,
        link = row.link,
        levelNote = row.levelNote,
        dropLevel = row.dropLevel,
        keyLevel = row.keyLevel,
        name = row.name,
        quality = row.quality,
        itemLevel = row.itemLevel,
        icon = row.icon,
    })
    local resolved = tile.cardIcon.resolved or {}
    -- A name the client has not sent yet: ask once, and re-draw the whole card
    -- when it arrives, so its name and its icon art follow (the M3-12 pending
    -- pattern the item line already uses). A card bound to another road since
    -- then is left alone.
    ns.ItemData.Cancel(tile.request)
    tile.request = nil
    if resolved.pending and resolved.itemID then
        tile.request = ns.ItemData.Request(resolved.itemID, function()
            if tile.card == card then
                Panel.InitCard(panel, tile, card)
            end
        end)
    end

    -- The art: the instance's own picture, cropped as the tiles crop it, when
    -- the walk recorded one; otherwise the item's own icon behind the shade,
    -- cropped to the card's proportion as the mosaic crops (UX-5b) and at the
    -- mosaic's alpha. Never a picture of somewhere else.
    if card.art then
        tile.art:SetTexture(card.art)
        tile.art:SetTexCoord(unpack(Panel.TILE_ART_TEX_COORD))
        tile.art:SetAlpha(1)
    else
        tile.art:SetTexture(resolved.icon)
        tile.art:SetTexCoord(unpack(Panel.MosaicTexCoord(tile:GetWidth(), tile:GetHeight())))
        tile.art:SetAlpha(Panel.MOSAIC_ALPHA)
    end
    tile.art:Show()
    for _, cell in ipairs(tile.mosaic) do
        cell:Hide()
    end
    for _, pip in ipairs(tile.pips) do
        pip:Hide()
    end

    tile.name:SetText(resolved.name or row.name or "")
    tile.second:SetText(Panel.CardSecond(row) or "")
    tile.cardLine:SetText(Panel.CardLine(row) or "")

    local badgeText = UI.ItemLine.BadgeText(Panel.CardBadge(row))
    tile.badge:SetText(badgeText)
    tile.badgePlate:SetShown(badgeText ~= "")

    -- The answer's own pick wears the gold edge, as it did on the row (R-3) and
    -- as an open tile does; never colour alone - its badge says it too.
    for _, edge in ipairs(tile.edges) do
        edge:SetShown(row.planPick == true)
    end
    tile:SetAlpha(row.group == ns.Roads.GROUP_NONE and Panel.TILE_DIM_ALPHA or 1)

    local lines = Panel.CardTooltipLines(row)
    tile:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        if not UI.ItemLine.ShowTooltip(tile.cardIcon, self) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(resolved.name or "", 1, 1, 1, 1, true)
        end
        for _, line in ipairs(lines) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    -- The click does what the Show run / Show in vault button did; the button
    -- is gone. A card whose step is not a screen - a craft, the Catalyst, a
    -- delve - takes no click (principle 9: a dead button is worse than none).
    if Panel.CardClicks(row) then
        tile:SetScript("OnClick", function()
            Panel.FollowVerb(panel, row)
        end)
    else
        tile:SetScript("OnClick", nil)
    end
    return tile
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
    -- The one row whose destination is not a screen: a claimed pick the plan
    -- has not seen yet, whose next step is the refresh itself (R-3b, WKE-576).
    -- It is `/lootpath refresh` and nothing else - the same captures, the same
    -- two reloads, the same combat refusal (principle 15).
    if row.verb == ns.Roads.VERB_REFRESH and ns.Companion and ns.Companion.Refresh then
        ns.Companion.Refresh()
        return true
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
    -- One open at a time (UX-5), here as well: arriving from a verb opens the
    -- run it names and shuts whatever was open before it.
    for key in pairs(state.runs) do
        state.runs[key] = nil
    end
    state.runs[runKey] = true
    Panel.Refresh(panel, { mode = Panel.MODE_RUN })
    -- The row the run's TILE is in, since UX-5: a run is no longer an element
    -- of its own, so what the box is asked to put on screen is the row that
    -- carries it.
    panel.scrollBox:ScrollToElementDataByPredicate(function(elementData)
        if type(elementData) ~= "table" or elementData.kind ~= Panel.ELEMENT_RUN_ROW then
            return false
        end
        for _, run in ipairs(elementData.runs or {}) do
            if run.key == runKey then
                return true
            end
        end
        return false
    end)
    return true
end

-- A frame going back to the pool waits for nothing: an item line's pending
-- request is cancelled, so a late answer never redraws a row that has moved on.
function Panel.ResetElement(element)
    if element.line then
        UI.ItemLine.Clear(element.line)
    end
    for _, tile in ipairs(element.cards or {}) do
        clearCard(tile)
    end
    if element.sectionIcon then
        UI.ItemLine.ClearIcon(element.sectionIcon)
    end
    for _, line in ipairs(element.drawerLines or {}) do
        UI.ItemLine.Clear(line)
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
    placeHeaderRow(self, mode, runSort)

    -- The answer, above the list and in the by-run view alone (UX-5): a
    -- sentence, not a paragraph, and everything that was a condition on it is
    -- on the hint icon beside the title.
    local answer = mode == Panel.MODE_RUN and model.headline or nil
    -- The slot view's one line up here is the stale-bags nudge (UX-6), in the
    -- strip's amber, and only when a slot's bags are ahead of the rating.
    if mode ~= Panel.MODE_RUN then
        local nudge = Panel.StaleNudge(model)
        answer = nudge and ("|cff" .. Panel.STALE_HEX .. nudge .. "|r") or nil
    end
    self.answer:SetText(answer or "")
    self.answer:SetShown(answer ~= nil)
    self.hintText = Panel.HintText(model, mode)
    local hintAtlas = UI.ItemLine.Atlas(Panel.HINT_ATLAS)
    if hintAtlas then
        self.hint.icon:SetAtlas(hintAtlas)
    else
        self.hint.icon:SetColorTexture(UI.ItemLine.RGB(Panel.HINT_HEX))
    end
    self.hint.icon:SetVertexColor(UI.ItemLine.RGB(Panel.HINT_HEX))
    self.hint:Show()
    Panel.AnchorList(self)

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
    -- How wide the tiles may be (UX-5). Asked of the box at layout time, the way
    -- every width in this addon is since M5-2c; until the client has laid it out
    -- - and headless - Panel.ListWidth does the same arithmetic ahead of it.
    state.listWidth = self.scrollBox:GetWidth()
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
