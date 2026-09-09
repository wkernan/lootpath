-- Lootpath/Modules/UFImport.lua (M3-6, WKE-535)
-- The second door QE Live's answers come through: an Upgrade Finder export,
-- which values drops the character does NOT own. Top Gear ranks what you have;
-- this ranks what you might get, which is exactly what the Upgrade Map lists.
--
-- This module transports QE Live's numbers. It never adjusts them, never
-- averages them, never fills a gap with one of its own.
--
-- WHY THIS IS ITS OWN FILE and not a second schema inside QEImport.lua:
-- the two exports disagree about what a positive number means. Top Gear's
-- `scorePercent` is positive when the alternative is WORSE; the Upgrade
-- Finder's `upgradePercent` is positive when the drop is BETTER. Sharing a file
-- would put ALT_WORSE_SCORE_PERCENT_SIGN next to UPGRADE_BETTER_PERCENT_SIGN
-- with nothing but a comment keeping a reader from grabbing the wrong one, and
-- reading the sign backwards is the one failure this pair of modules has. They
-- also key differently (itemID + bonus IDs there, itemID + item level here),
-- store separately, and refuse with different words. One file each.
--
-- Schema, read from the owner's fork on 2026-09-07 (branch
-- `lootpath/upgrade-finder-export`,
-- src/General/Modules/UpgradeFinder/UpgradeFinderJSONExport.ts; QE Live's repo
-- has no licence file, so it is read and never copied):
--
--   { schema: "qe-live-upgradefinder", version: 1, exportedAt: ISO,
--     player: { name, realm, region, spec, gameType: "Retail"|"Classic" },
--     contentType, reportId, settings (the report's ufSettings),
--     equipped: [Item]  (Top Gear's item shape),
--     items: [ { id, level, slot, source: { instanceId, encounterId },
--                dropLoc, dropType, dropDifficulty,
--                upgradePercent, hpsGain, score } ] }
--
-- An `items` entry carries NO bonus IDs, because the report the export is built
-- from has none: QE Live's stored Upgrade Finder report identifies a drop by
-- itemID and the item level its settings assume. So the key here is itemID and
-- item level, and the Upgrade Map joins on exactly that (ARCHITECTURE.md 7,
-- 2026-09-06).

local _, ns = ...

ns.UFImport = {}
local UFImport = ns.UFImport

UFImport.SCHEMA = "qe-live-upgradefinder"
UFImport.VERSION = 1
UFImport.GAME_TYPE = "Retail"

-- Sign conventions, the whole failure mode of this module, and the OPPOSITE of
-- QEImport's. Pinned twice from the fork's source (read 2026-09-07):
--   UpgradeFinderJSONExport.ts states it - "rawDiff and percDiff are
--   (new - base), so POSITIVE MEANS AN UPGRADE" - and
--   UpgradeFinderEngine.js:372-373 computes them, with `newScore` the score of
--   the set that includes the drop and `baseScore` the set without it:
--     rawDiff  = round(((newScore - baseScore) / baseScore) * baseHPS * modelDiff)
--     percDiff = round(((newScore - baseScore) / baseScore) * modelDiff * 100000) / 1000
-- The exporter renames them `hpsGain` and `upgradePercent`. Every consumer
-- reads the direction from IsUpgrade, never from its own arithmetic.
UFImport.UPGRADE_BETTER_PERCENT_SIGN = 1
UFImport.UPGRADE_BETTER_HPS_GAIN_SIGN = 1

-- true when QE Live ranked this drop above the set the character has now,
-- false when it ties or is worse, nil when the entry carries no percentage.
function UFImport.IsUpgrade(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local percent = tonumber(entry.upgradePercent)
    if not percent then
        return nil
    end
    return percent * UFImport.UPGRADE_BETTER_PERCENT_SIGN > 0
end

-- The join key: itemID and the item level QE Live valued the drop at. A journal
-- row at another level is a different item to QE Live and gets no number
-- (ARCHITECTURE.md 7, 2026-09-06). Returns nil for anything that is not a
-- positive integer itemID with a numeric level.
function UFImport.Key(itemID, level)
    local id = tonumber(itemID)
    if not id or id <= 0 or id % 1 ~= 0 then
        return nil
    end
    local itemLevel = tonumber(level)
    if not itemLevel then
        return nil
    end
    return string.format("%d@%d", id, itemLevel)
end

local function shown(value)
    if value == nil then
        return "missing"
    end
    local kind = type(value)
    if kind == "string" then
        if #value > 40 then
            return '"' .. value:sub(1, 40) .. '..."'
        end
        return '"' .. value .. '"'
    end
    if kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    return "a " .. kind
end

local function refuse(fmt, ...)
    return { ok = false, reason = string.format(fmt, ...) }
end

local function stringOrNil(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

-- `dropLoc` is a string in the fork's real exports ("Dungeon", "Raid",
-- "Delves", "Crafted") and a number in its unit test, so whichever arrives is
-- carried through rather than one of them being made to look like the other.
local function stringOrNumber(value)
    return stringOrNil(value) or tonumber(value)
end

-- One export item -> one verdict entry, or nil when it carries no usable
-- identity. `dropDifficulty` is a number in a real export and the empty string
-- on a crafted or Delve drop, which tonumber turns into nil - absent, not zero.
function UFImport.Item(raw)
    if type(raw) ~= "table" then
        return nil
    end
    local key = UFImport.Key(raw.id, raw.level)
    if not key then
        return nil
    end
    local source = type(raw.source) == "table" and raw.source or {}
    return {
        key = key,
        itemID = tonumber(raw.id),
        level = tonumber(raw.level),
        slot = stringOrNil(raw.slot),
        instanceID = tonumber(source.instanceId),
        encounterID = tonumber(source.encounterId),
        dropLoc = stringOrNumber(raw.dropLoc),
        dropType = stringOrNumber(raw.dropType),
        dropDifficulty = tonumber(raw.dropDifficulty),
        upgradePercent = tonumber(raw.upgradePercent),
        hpsGain = tonumber(raw.hpsGain),
        score = tonumber(raw.score),
        count = 1,
        sources = {},
    }
end

-- One drop that several bosses (or several drop types of one boss) can give is
-- listed once per way of getting it: the 2026-09-07 Dungeon export lists 357
-- entries over 315 distinct itemID + level pairs, the repeats being the same
-- item as `drop`, `max` and `bonus`. They are kept as sources of ONE entry
-- rather than as several entries, because the number is the same on all of them
-- and a map row would otherwise be handed an arbitrary one of them.
local function addSource(entry, item)
    local candidate = {
        instanceID = item.instanceID,
        encounterID = item.encounterID,
        dropLoc = item.dropLoc,
        dropType = item.dropType,
        dropDifficulty = item.dropDifficulty,
    }
    for _, existing in ipairs(entry.sources) do
        if
            existing.instanceID == candidate.instanceID
            and existing.encounterID == candidate.encounterID
            and existing.dropLoc == candidate.dropLoc
            and existing.dropType == candidate.dropType
            and existing.dropDifficulty == candidate.dropDifficulty
        then
            return
        end
    end
    entry.sources[#entry.sources + 1] = candidate
end

function UFImport.Parse(text)
    if type(text) ~= "string" or text:match("^%s*$") then
        return refuse("nothing to import: paste QE Live's Upgrade Finder JSON (its Download JSON button) here")
    end
    local decoded
    do
        local ok, result = pcall(ns.json.decode, text)
        if not ok then
            return refuse("that is not JSON: %s", (tostring(result):gsub("^.-:%d+: ", "")))
        end
        decoded = result
    end
    if type(decoded) ~= "table" then
        return refuse("that JSON is %s, not a QE Live export", shown(decoded))
    end
    if decoded.schema ~= UFImport.SCHEMA then
        return refuse(
            'not a QE Live Upgrade Finder export: its schema is %s, Lootpath reads "%s"',
            shown(decoded.schema),
            UFImport.SCHEMA
        )
    end
    -- The JSON number 1, never the string "1": a changed type means the schema
    -- moved, and the pin exists to fail loudly rather than wrongly (decision
    -- 2026-09-06, the same pin QEImport carries).
    if type(decoded.version) ~= "number" or decoded.version ~= UFImport.VERSION then
        return refuse(
            "this export is %s version %s; Lootpath reads version %d. Re-export from QE Live, or update Lootpath.",
            UFImport.SCHEMA,
            shown(decoded.version),
            UFImport.VERSION
        )
    end
    if type(decoded.items) ~= "table" then
        return refuse(
            "this export has no items (it is %s): run the Upgrade Finder on QE Live, then Export > Download JSON",
            shown(decoded.items)
        )
    end
    local player = type(decoded.player) == "table" and decoded.player or {}
    if player.gameType ~= UFImport.GAME_TYPE then
        return refuse(
            "this export's gameType is %s; Lootpath reads %s exports only",
            shown(player.gameType),
            UFImport.GAME_TYPE
        )
    end

    local items, order, byItemID = {}, {}, {}
    local skipped, conflicts = 0, {}
    for _, raw in ipairs(decoded.items) do
        local item = UFImport.Item(raw)
        if item then
            local existing = items[item.key]
            if existing then
                -- Same drop, another way of getting it. The first entry's
                -- numbers stand; a repeat that disagrees about the number is
                -- something QE Live has never produced here, so it is reported
                -- rather than resolved by picking one.
                existing.count = existing.count + 1
                if existing.upgradePercent ~= item.upgradePercent then
                    conflicts[#conflicts + 1] = item.itemID
                end
                addSource(existing, item)
            else
                items[item.key] = item
                addSource(item, item)
                order[#order + 1] = item.key
                local levels = byItemID[item.itemID] or {}
                byItemID[item.itemID] = levels
                levels[#levels + 1] = item.level
            end
        else
            skipped = skipped + 1
        end
    end
    for _, levels in pairs(byItemID) do
        table.sort(levels)
    end

    local warnings = {}
    local character = ns.Safe(UnitName and UnitName("player"))
    local exportName = stringOrNil(player.name)
    if type(character) == "string" and exportName and character:lower() ~= exportName:lower() then
        warnings[#warnings + 1] = string.format("this export is for %s, and you are playing %s", exportName, character)
    end
    if #order == 0 then
        warnings[#warnings + 1] = "this export ranks no drops"
    end
    if skipped > 0 then
        warnings[#warnings + 1] =
            string.format("%d ranked drop(s) carried no usable itemID or item level and were skipped", skipped)
    end
    if #conflicts > 0 then
        warnings[#warnings + 1] = string.format(
            "%d drop(s) were listed twice with different values (first one kept): item %d",
            #conflicts,
            conflicts[1]
        )
    end

    local verdict = {
        schema = decoded.schema,
        version = decoded.version,
        exportedAt = stringOrNil(decoded.exportedAt),
        reportId = stringOrNil(decoded.reportId),
        contentType = stringOrNil(decoded.contentType),
        spec = stringOrNil(player.spec),
        player = {
            name = exportName,
            realm = stringOrNil(player.realm),
            region = stringOrNil(player.region),
            spec = stringOrNil(player.spec),
            gameType = player.gameType,
        },
        settings = type(decoded.settings) == "table" and decoded.settings or {},
        items = items,
        order = order,
        levelsByItemID = byItemID,
        skippedItems = skipped,
    }
    return { ok = true, verdict = verdict, warnings = warnings }
end

-- What QE Live said about this exact drop, or nil when it said nothing about
-- it AT THIS ITEM LEVEL. There is deliberately no itemID-only lookup that
-- returns a number: a value QE Live computed for a 334 drop is not a value for
-- the 305 the journal previews, and showing it there would be this addon making
-- up a healer value (decision 2026-09-05, the identity rule).
function UFImport.Lookup(verdict, itemID, level)
    if type(verdict) ~= "table" or type(verdict.items) ~= "table" then
        return nil
    end
    local key = UFImport.Key(itemID, level)
    if not key then
        return nil
    end
    return verdict.items[key]
end

-- The item levels this export DOES carry for an itemID, ascending, or nil when
-- it does not mention the item at all. This is how a caller tells "QE Live has
-- never seen this drop" from "QE Live valued it at another level", which is a
-- fact worth counting and never a reason to show a number.
function UFImport.LevelsFor(verdict, itemID)
    if type(verdict) ~= "table" or type(verdict.levelsByItemID) ~= "table" then
        return nil
    end
    local id = tonumber(itemID)
    if not id then
        return nil
    end
    return verdict.levelsByItemID[id]
end

-- Filed by content type exactly as a Top Gear import is (decision 2026-09-06):
-- a Dungeon export and a Raid export answer different questions, and importing
-- one must not lose the other.
function UFImport.ContentTypeKey(verdict)
    if type(verdict) ~= "table" then
        return ns.QEImport.UNKNOWN_CONTENT_TYPE
    end
    return stringOrNil(verdict.contentType) or ns.QEImport.UNKNOWN_CONTENT_TYPE
end

-- ---------------------------------------------------------------------------
-- Mythic+ key levels (C-7, WKE-543).
--
-- QE Live's Upgrade Finder values every dungeon drop at ONE key level: the one
-- his `ufSettings.dungeon` names. So "which dungeon at the lowest key level
-- still gives me an upgrade" is not a question one export can answer, and the
-- companion asks him once per level instead (tools/companion, decision
-- 2026-09-08). Each document it writes says which key level it was run at, and
-- this module files it under that level.
--
-- THE ADDON NEVER CONVERTS ONE OF HIS NUMBERS INTO ANOTHER. In particular it
-- never turns `settings.dungeon` into a key level: that field is an INDEX into
-- his MPLUS_KEY_REWARDS table (index 7 is the "+10" button, whose rows come
-- back at 311 / 321 / 334), and the index -> level mapping is his data, read
-- off his own selector labels by the companion and carried here as a number.
-- WKE-543 asked for the addon to derive the level from `settings.dungeon`; it
-- cannot without restating his table, so an export that does not say its key
-- level is filed as not saying, and the panel says so out loud.
UFImport.UNKNOWN_KEY_LEVEL = "unknown"

-- The key level a stored verdict was run at, or nil when it does not say. Only
-- a whole, non-negative NUMBER counts, and the string "10" is not one: this is
-- what decides the shelf a verdict is filed on, and a value that had to be
-- converted first is a value nobody wrote deliberately. The one door a key
-- level comes through is ns.Companion.Entry, which already insists on a number
-- through ns.Safe; this is the same rule read back.
--
-- KeyLevelKey below is the lenient one on purpose: it normalises what a CALLER
-- asks for, and a caller asking about key "10" means key 10.
function UFImport.KeyLevelOf(verdict)
    if type(verdict) ~= "table" or type(verdict.keyLevel) ~= "number" then
        return nil
    end
    local level = verdict.keyLevel
    if level < 0 or level % 1 ~= 0 then
        return nil
    end
    return level
end

-- The table key a level is filed under: the number itself, or the sentinel for
-- a verdict that does not say. Numbers and the sentinel never collide, which is
-- why the sentinel is a string.
function UFImport.KeyLevelKey(keyLevel)
    local level = tonumber(keyLevel)
    if not level or level < 0 or level % 1 ~= 0 then
        return UFImport.UNKNOWN_KEY_LEVEL
    end
    return level
end

-- The label a key level is shown under, and the ONLY place a number becomes a
-- word. `+%d` and nothing else: the companion stamps the level QE Live's own
-- selector was set to, and dressing 6 up as anything but "+6" would be this
-- module having an opinion about his table.
function UFImport.KeyLabel(keyLevel)
    local level = tonumber(keyLevel)
    if not level or level < 0 or level % 1 ~= 0 then
        return nil
    end
    return string.format("+%d", level)
end

function UFImport.Store(verdict)
    if type(verdict) ~= "table" then
        return { ok = false, reason = "no verdict to store" }
    end
    if not ns.db then
        return { ok = false, reason = "database not loaded yet" }
    end
    verdict.importedAt = time()
    local contentType = UFImport.ContentTypeKey(verdict)
    ns.db.char.ufImport = verdict
    ns.db.char.ufImports = ns.db.char.ufImports or {}
    ns.db.char.ufImports[contentType] = verdict
    -- The by-level shelf, added by C-7. `ufImports` above is untouched and
    -- still holds the most recent verdict for the content type, so everything
    -- written before this existed keeps reading what it always read.
    ns.db.char.ufImportsByLevel = ns.db.char.ufImportsByLevel or {}
    local byLevel = ns.db.char.ufImportsByLevel[contentType] or {}
    ns.db.char.ufImportsByLevel[contentType] = byLevel
    byLevel[UFImport.KeyLevelKey(UFImport.KeyLevelOf(verdict))] = verdict
    return { ok = true, verdict = verdict }
end

function UFImport.Current()
    return ns.db and ns.db.char and ns.db.char.ufImport or nil
end

function UFImport.ForContentType(contentType)
    if type(contentType) ~= "string" then
        return nil
    end
    local byType = ns.db and ns.db.char and ns.db.char.ufImports
    return byType and byType[contentType] or nil
end

-- The verdict for one content type at one key level, or nil. `keyLevel` nil
-- asks for the shelf a verdict that does not say its level was filed on, which
-- is a real question and not the same as "any level".
function UFImport.ForContentTypeAndLevel(contentType, keyLevel)
    if type(contentType) ~= "string" then
        return nil
    end
    local byType = ns.db and ns.db.char and ns.db.char.ufImportsByLevel
    local byLevel = byType and byType[contentType]
    return byLevel and byLevel[UFImport.KeyLevelKey(keyLevel)] or nil
end

-- The key levels this character has stored for a content type, ascending, and
-- whether one of them says nothing about its level. Sorted here rather than at
-- every call site, because "the highest key asked about" is the fallback and it
-- has to mean the same thing everywhere.
function UFImport.StoredKeyLevels(contentType)
    local levels, unrecorded = {}, false
    if type(contentType) ~= "string" then
        return levels, unrecorded
    end
    local byType = ns.db and ns.db.char and ns.db.char.ufImportsByLevel
    local byLevel = byType and byType[contentType]
    if type(byLevel) ~= "table" then
        return levels, unrecorded
    end
    for key, verdict in pairs(byLevel) do
        if verdict ~= nil then
            if type(key) == "number" then
                levels[#levels + 1] = key
            else
                unrecorded = true
            end
        end
    end
    table.sort(levels)
    return levels, unrecorded
end

-- ---------------------------------------------------------------------------
-- The cross-level join (M3-10, WKE-545).
--
-- C-7 picked ONE document - the one run at the key level the walk previewed -
-- and asked it about every row. Measured on 2026-09-08 that answered nothing
-- about dungeons: QE Live's +10 document values a dungeon drop at 311 while the
-- client's own keystone-10 preview lists it at 305, so the exact `itemID@level`
-- key missed on every dungeon row and each one read "no drop rated by QE Live
-- yet". Which of the two is right about +10 is not Lootpath's to decide, and
-- adjusting either number would be Lootpath inventing a healer value.
--
-- What both sources DO say without being touched: the client says at what item
-- level a drop drops, and QE Live says what that item is worth at each level he
-- modelled. So the join runs over EVERY stored document for the content type
-- and keeps the exact `itemID@itemLevel` match wherever it is found - the +6
-- document, as it happens, because his +6 dungeon rows come back at 305. No
-- neighbouring level, no interpolation, no key level inferred from an item
-- level: a row still shows a number only where one of his own documents carries
-- that exact item at that exact level, and the row says which document it was.
--
-- Why the tie-break exists: two documents really can carry one drop at one
-- level (his +6 and +7 buttons both end at 305, and every dungeon document
-- carries the same raid rows), and they can disagree, because a level that is a
-- `drop` in one run is an `Upgraded` or `Bonus Roll` listing in another. His
-- own `dropType` settles it; the lowest key level settles what that cannot.

-- QE Live's own word for the item level a run's end-of-dungeon chest gives, as
-- opposed to the upgraded (`max`) and bonus-roll (`bonus`) listings of the same
-- item. Read from the exports, never chosen here.
UFImport.DROP_TYPE_DROP = "drop"

-- Why a matched entry is the matched one, for the row that has to say so.
UFImport.MATCH_ONLY = "only"
UFImport.MATCH_DROP = "drop"
UFImport.MATCH_LOWEST = "lowest"

-- Every stored Upgrade Finder document for a content type, as
-- `{ verdict = <verdict>, keyLevel = <number or nil> }`, ascending by key level
-- with a document that does not name its level last. This is the one place the
-- database is read; every function below is pure over the list it returns, so a
-- panel can be handed documents in a test without a database at all.
function UFImport.Documents(contentType)
    local documents = {}
    local levels, unrecorded = UFImport.StoredKeyLevels(contentType)
    for _, level in ipairs(levels) do
        local verdict = UFImport.ForContentTypeAndLevel(contentType, level)
        if verdict then
            documents[#documents + 1] = { verdict = verdict, keyLevel = level }
        end
    end
    if unrecorded then
        local verdict = UFImport.ForContentTypeAndLevel(contentType, nil)
        if verdict then
            documents[#documents + 1] = { verdict = verdict, keyLevel = nil }
        end
    end
    if #documents == 0 then
        -- SavedVariables written before the by-level shelf existed: the verdict
        -- is there, it simply never said which key it was run at.
        local legacy = UFImport.ForContentType(contentType)
        if legacy then
            documents[#documents + 1] = { verdict = legacy, keyLevel = UFImport.KeyLevelOf(legacy) }
        end
    end
    return documents
end

-- Does QE Live call this entry a `drop` at its level? The entry keeps the
-- dropType of the first listing that produced it and the rest as `sources`
-- (one item can be listed as drop, max and bonus), so both are read: the
-- question is what he says about the item at that level, not which of his
-- listings happened to be parsed first.
function UFImport.IsDropAtLevel(entry)
    if type(entry) ~= "table" then
        return false
    end
    if entry.dropType == UFImport.DROP_TYPE_DROP then
        return true
    end
    for _, source in ipairs(entry.sources or {}) do
        if source.dropType == UFImport.DROP_TYPE_DROP then
            return true
        end
    end
    return false
end

-- The entry any of these documents carries for `itemID` AT `level`, or nil.
--
-- Exact on both keys in every document, and never anything else. When more than
-- one document carries it, the one QE Live's own `dropType` calls a `drop` at
-- that level wins, and the lowest key level wins when none of them does - the
-- documents arrive in ascending order, so "first" is "lowest".
--
-- Returns entry, keyLevel (nil when that document does not name one), how
-- (MATCH_ONLY / MATCH_DROP / MATCH_LOWEST) and the number of documents that
-- carried it.
function UFImport.LookupAcrossLevels(documents, itemID, level)
    if type(documents) ~= "table" then
        return nil
    end
    local key = UFImport.Key(itemID, level)
    if not key then
        return nil
    end
    local found, drop = nil, nil
    local count = 0
    for _, document in ipairs(documents) do
        local verdict = type(document) == "table" and document.verdict or nil
        local entry = type(verdict) == "table" and type(verdict.items) == "table" and verdict.items[key] or nil
        if entry then
            count = count + 1
            found = found or { entry = entry, keyLevel = document.keyLevel }
            if not drop and UFImport.IsDropAtLevel(entry) then
                drop = { entry = entry, keyLevel = document.keyLevel }
            end
        end
    end
    -- `found` is nil exactly when count is 0, and saying it this way is what
    -- lets both this reader and LuaLS see that the returns below are safe.
    if not found then
        return nil
    end
    if count == 1 then
        return found.entry, found.keyLevel, UFImport.MATCH_ONLY, count
    end
    if drop then
        return drop.entry, drop.keyLevel, UFImport.MATCH_DROP, count
    end
    return found.entry, found.keyLevel, UFImport.MATCH_LOWEST, count
end

-- Every item level any of these documents carries for an itemID, ascending, or
-- nil when none of them mentions the item at all. This is how a caller tells
-- "QE Live has never seen this drop" from "QE Live valued it, but never at the
-- level the client lists" - which is a fact worth counting and never a reason
-- to show a number.
function UFImport.LevelsAcrossLevels(documents, itemID)
    if type(documents) ~= "table" then
        return nil
    end
    local seen, levels = {}, {}
    for _, document in ipairs(documents) do
        local verdict = type(document) == "table" and document.verdict or nil
        for _, level in ipairs(UFImport.LevelsFor(verdict, itemID) or {}) do
            if not seen[level] then
                seen[level] = true
                levels[#levels + 1] = level
            end
        end
    end
    if #levels == 0 then
        return nil
    end
    table.sort(levels)
    return levels
end

-- The sentence the panel puts under its header: which documents are being
-- joined, so a reader knows the numbers on the rows came from several runs of
-- QE Live's Upgrade Finder and which ones. It replaces C-7's "these numbers are
-- its +8 run" line, because no single run is what is on screen any more.
UFImport.DOCUMENTS_NOTE = "QE Live's Upgrade Finder at %s (%d document%s)."
UFImport.DOCUMENTS_NOTE_UNNAMED = "QE Live's Upgrade Finder, with no Mythic+ key level named (%d document%s)."
UFImport.DOCUMENTS_NOTE_MIXED = "QE Live's Upgrade Finder at %s, and %d that name no key level (%d documents)."
UFImport.DOCUMENTS_JOIN_SENTENCE =
    " A drop takes its number from whichever of them values it at the item level the loot map lists."

function UFImport.DocumentsNote(documents)
    local labels, unnamed = {}, 0
    for _, document in ipairs(documents or {}) do
        local label = type(document) == "table" and UFImport.KeyLabel(document.keyLevel) or nil
        if label then
            labels[#labels + 1] = label
        else
            unnamed = unnamed + 1
        end
    end
    local count = #labels + unnamed
    if count == 0 then
        return nil
    end
    local plural = count == 1 and "" or "s"
    local note
    if #labels == 0 then
        note = string.format(UFImport.DOCUMENTS_NOTE_UNNAMED, count, plural)
    elseif unnamed == 0 then
        note = string.format(UFImport.DOCUMENTS_NOTE, table.concat(labels, ", "), count, plural)
    else
        note = string.format(UFImport.DOCUMENTS_NOTE_MIXED, table.concat(labels, ", "), unnamed, count)
    end
    -- Only worth saying when there is a choice to explain.
    if count > 1 then
        note = note .. UFImport.DOCUMENTS_JOIN_SENTENCE
    end
    return note
end

-- The stored verdict this one would replace: the same content type AND the same
-- key level, never merely the same content type. A companion file now carries
-- one Upgrade Finder document per key level, and treating the +4 document as a
-- repeat of the +2 one would throw four answers away and keep one.
--
-- ns.Companion calls this on whichever importer owns the schema, so the two
-- importers answer "what does this replace" in their own terms without
-- Companion.lua reaching into either shape.
function UFImport.Existing(verdict)
    return UFImport.ForContentTypeAndLevel(UFImport.ContentTypeKey(verdict), UFImport.KeyLevelOf(verdict))
end

function UFImport.StoredContentTypes()
    local byType = ns.db and ns.db.char and ns.db.char.ufImports or {}
    local out, seen = {}, {}
    for _, known in ipairs(ns.QEImport.CONTENT_TYPES) do
        if byType[known] then
            out[#out + 1] = known
            seen[known] = true
        end
    end
    local extra = {}
    for name in pairs(byType) do
        if not seen[name] then
            extra[#extra + 1] = name
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        out[#out + 1] = name
    end
    return out
end

function UFImport.Import(text)
    local parsed = UFImport.Parse(text)
    if not parsed.ok then
        return parsed
    end
    local stored = UFImport.Store(parsed.verdict)
    if not stored.ok then
        return stored
    end
    return parsed
end
