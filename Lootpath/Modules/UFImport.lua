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

-- Why the verdict on screen is the one on screen, for the line the panel draws.
UFImport.PICK_WANTED = "wanted"
UFImport.PICK_HIGHEST = "highest"
UFImport.PICK_UNRECORDED = "unrecorded"

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

-- Which stored Upgrade Finder verdict answers for `wantedLevel`.
--   the one at that exact key level, when it is stored;
--   else the highest key level stored, because a higher key is the answer the
--   owner is most likely to have asked for and never a level made up here;
--   else a verdict that does not say its level at all - a paste, or a file
--   written before C-7.
-- Returns verdict, keyLevel (nil when it does not say), how.
function UFImport.PickForLevel(contentType, wantedLevel)
    local want = tonumber(wantedLevel)
    if want then
        local exact = UFImport.ForContentTypeAndLevel(contentType, want)
        if exact then
            return exact, UFImport.KeyLevelOf(exact) or want, UFImport.PICK_WANTED
        end
    end
    local levels, unrecorded = UFImport.StoredKeyLevels(contentType)
    if #levels > 0 then
        local highest = levels[#levels]
        local verdict = UFImport.ForContentTypeAndLevel(contentType, highest)
        if verdict then
            return verdict, highest, UFImport.PICK_HIGHEST
        end
    end
    if unrecorded then
        local verdict = UFImport.ForContentTypeAndLevel(contentType, nil)
        if verdict then
            return verdict, nil, UFImport.PICK_UNRECORDED
        end
    end
    -- SavedVariables written before the by-level shelf existed: the verdict is
    -- there, it simply never said which key it was run at.
    local legacy = UFImport.ForContentType(contentType)
    if legacy then
        return legacy, UFImport.KeyLevelOf(legacy), UFImport.PICK_UNRECORDED
    end
    return nil
end

-- The sentence the panel puts under its header, so a reader is never shown a
-- +2 answer while thinking about their +10 key. One place, because the Upgrade
-- Map and the window's own note have to say the same thing.
function UFImport.KeyLevelNote(keyLevel, how, wantedLevel)
    if how == UFImport.PICK_WANTED then
        return string.format("QE Live ran these numbers on a +%d key, the level the loot map previews.", keyLevel)
    end
    if how == UFImport.PICK_HIGHEST then
        if tonumber(wantedLevel) then
            return string.format(
                "QE Live has no +%d run stored, so these numbers are its +%d run - the highest key it was asked about.",
                wantedLevel,
                keyLevel
            )
        end
        return string.format("QE Live ran these numbers on a +%d key, the highest it was asked about.", keyLevel)
    end
    if how == UFImport.PICK_UNRECORDED then
        return "This Upgrade Finder export does not say which Mythic+ key level QE Live ran it on."
    end
    return nil
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
