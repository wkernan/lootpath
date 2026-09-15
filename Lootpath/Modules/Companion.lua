-- Lootpath/Modules/Companion.lua (C-2, WKE-534)
-- The addon half of the local companion (decision 2026-09-07,
-- docs/ARCHITECTURE.md 7). The companion writes QE Live's exports into
-- Lootpath/Data/QEVerdict.lua as Lua string literals; the client loads that
-- file at login or /reload like any other addon file, and this module carries
-- what it set through the SAME parser a paste goes through.
--
-- It moves bytes. It computes no healer value, adjusts no number QE Live
-- wrote, and refuses anything QEImport would refuse from the editbox: the
-- companion is a courier, not a second source of truth.
--
-- The chunk is Lua the companion authored on the owner's own machine, and it
-- is still treated as data: every field is type-checked, every value read
-- passes ns.Safe, nothing in it is called, and there is no loadstring
-- anywhere. A malformed file is a chat message and an untouched database.

local _, ns = ...

ns.Companion = {}
local Companion = ns.Companion

-- The schema strings this module knows how to hand on, and which importer
-- takes each. QE Live's Top Gear export is ns.QEImport's; the Upgrade Finder
-- export (`qe-live-upgradefinder`, the fork's own, docs/qe-live-pr.md) is
-- ns.UFImport's, since M3-6 - until that module existed an entry carrying it
-- was refused by name rather than handed to a parser that would have called it
-- a bad Top Gear export.
--
-- The two importers share the four calls this file makes of them - Parse,
-- ContentTypeKey, ForContentType, Store - and NOTHING here reaches past that
-- into either verdict's shape, because the two shapes disagree and their sign
-- conventions are opposites (decision 2026-09-08). A schema that is in neither
-- table is still refused by name; this module never guesses at an importer.
Companion.TOP_GEAR_SCHEMA = "qe-live-droptimizer"
Companion.UPGRADE_FINDER_SCHEMA = "qe-live-upgradefinder"

-- Resolved at call time, not at load: the module tables are built by files the
-- `.toc` lists before this one, but a name looked up now cannot be a stale
-- reference to a table that was replaced.
function Companion.ImporterFor(schema)
    if schema == Companion.TOP_GEAR_SCHEMA then
        return ns.QEImport
    end
    if schema == Companion.UPGRADE_FINDER_SCHEMA then
        return ns.UFImport
    end
    return nil
end

-- How many things a verdict carries, for the chat line, in each verdict's own
-- words. A Top Gear export names a set; an Upgrade Finder export ranks drops.
function Companion.CountOf(schema, verdict)
    if type(verdict) ~= "table" then
        return 0, "items"
    end
    if schema == Companion.UPGRADE_FINDER_SCHEMA then
        return #(verdict.order or {}), "ranked drops"
    end
    local topSet = type(verdict.topSet) == "table" and verdict.topSet or {}
    return #(topSet.order or {}), "items"
end

-- Where the verdict on screen came from. Stored on the verdict at import time
-- so it survives /reload in SavedVariables.
Companion.SOURCE_PASTE = "paste"
Companion.SOURCE_COMPANION = "companion"

-- The window already names the two kinds on the status line (ns.UI.KIND_LABEL);
-- the chat line says the same words, so an owner reading either sees one
-- vocabulary. Keyed by schema, because that is what the file carries.
Companion.KIND_OF = {
    ["qe-live-droptimizer"] = "topgear",
    ["qe-live-upgradefinder"] = "upgradefinder",
}

-- An export text longer than this is refused unread. A real Top Gear export is
-- tens of kilobytes (the committed one is 21 KB); a megabyte of Lua string in
-- the addon folder is a broken companion, and decoding it would freeze the
-- client rather than say so.
Companion.MAX_JSON_BYTES = 4 * 1024 * 1024

local function refuse(fmt, ...)
    return { ok = false, reason = string.format(fmt, ...) }
end

-- ns.Safe first, type after. A secret value coerces to nil through tonumber
-- and answers no type honestly, so the guard runs before anything looks at the
-- value - the same order Vault.lua settled on in M3-3.
local function safeString(value)
    local safe, sawSecret = ns.Safe(value)
    if sawSecret or type(safe) ~= "string" or safe == "" then
        return nil
    end
    return safe
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

-- The Mythic+ key level an Upgrade Finder document was run at (C-7, WKE-543).
-- Optional: a Top Gear document never has one, and neither does a file written
-- before C-7 or the committed placeholder. Whole and non-negative or nothing -
-- half a key level is not a key level, and the addon would rather file a
-- document as "does not say" than under a number it made up.
local function safeKeyLevel(value)
    local safe, sawSecret = ns.Safe(value)
    if sawSecret or type(safe) ~= "number" or safe < 0 or safe % 1 ~= 0 then
        return nil
    end
    return safe
end

-- Which Top Gear pass a document is (C-11, WKE-572). Whole numbers from 1;
-- anything else is nil, which means pass 1 the way a missing scenario means
-- `asOffered`: every file written before C-11 says nothing and every one of
-- them is a first pass.
local function safePass(value)
    local safe, sawSecret = ns.Safe(value)
    if sawSecret or type(safe) ~= "number" or safe < 1 or safe % 1 ~= 0 then
        return nil
    end
    return safe
end

-- Which of QE Live's own import settings produced the exports in the file
-- (C-5, WKE-539: the companion sets both checkboxes explicitly and records what
-- it asked for). Optional: a file written before C-5, and the committed
-- placeholder, carry none, and a missing pair is silence rather than a refusal.
-- Only the two booleans are read, and only when they really are booleans; the
-- addon never infers a setting from a number it sees elsewhere.
Companion.QE_SETTING_KEYS = { "autoUpgradeVault", "autoUpgradeAll" }

-- The third box (C-6, WKE-540). Optional, because a file written before C-6 has
-- only the pair above and half a stated setting is still not a setting: it is
-- carried when it is really a boolean and left out otherwise, and a file that
-- does not mention the Catalyst says nothing about it rather than "off".
Companion.OPTIONAL_QE_SETTING_KEYS = { "autoCatalyze" }

function Companion.Settings(raw)
    local safe, sawSecret = ns.Safe(raw)
    if sawSecret or type(safe) ~= "table" then
        return nil
    end
    local settings = {}
    for _, key in ipairs(Companion.QE_SETTING_KEYS) do
        local value, secret = ns.Safe(safe[key])
        if secret or type(value) ~= "boolean" then
            return nil
        end
        settings[key] = value
    end
    for _, key in ipairs(Companion.OPTIONAL_QE_SETTING_KEYS) do
        local value, secret = ns.Safe(safe[key])
        if not secret and type(value) == "boolean" then
            settings[key] = value
        end
    end
    return settings
end

-- The items QE Live's Top Gear was never shown (C-8, WKE-558). His Top Gear
-- takes thirty items for a non-patron, the character owns more, and the
-- companion decides which thirty; this is the rest, so the panels can say that
-- the set on screen is an answer about a subset. Optional everywhere: a file
-- written before C-8 carries none, and so does the committed placeholder.
--
-- Nothing is repaired here. An entry with no name is dropped rather than
-- renamed, a level that is not a whole number is left out rather than rounded,
-- and the list stops at MAX_EXCLUDED so a broken writer cannot make the panel
-- print for a page and a half.
Companion.MAX_EXCLUDED = 200

-- The identity half of an entry (C-10, WKE-567). QE Live's own card carries the
-- item ID and the bonus IDs in its `data-wowhead` attribute and the companion
-- copies both into the file, so "was THIS item left out of the pool" is an
-- ns.ItemKey comparison instead of a name comparison - two rings of one name at
-- one item level are one question with two answers otherwise.
--
-- All or nothing, deliberately: a bonusIDs field that is present and unreadable
-- takes the item ID down with it, because ns.ItemKey over a shortened list is a
-- valid key for an item nobody owns, and a wrong match here would put "beyond
-- the rating's item limit" on the wrong item. An entry with no bonusIDs field
-- at all keeps its ID: that is the bare "<itemID>" key ns.ItemKey builds for an
-- item with no bonus IDs, which is what such a card really is.
local function safeItemID(value)
    local safe, sawSecret = ns.Safe(value)
    if sawSecret or type(safe) ~= "number" or safe <= 0 or safe % 1 ~= 0 then
        return nil
    end
    return safe
end

local function safeBonusIDs(value)
    if value == nil then
        return nil, true
    end
    local safe, sawSecret = ns.Safe(value)
    if sawSecret or type(safe) ~= "table" then
        return nil, false
    end
    local list = {}
    for index = 1, #safe do
        local bonus, bonusSecret = ns.Safe(safe[index])
        if bonusSecret or type(bonus) ~= "number" or bonus < 0 or bonus % 1 ~= 0 then
            return nil, false
        end
        list[index] = bonus
    end
    return list, true
end

function Companion.Excluded(raw)
    local safe, sawSecret = ns.Safe(raw)
    if sawSecret or type(safe) ~= "table" then
        return nil
    end
    local list = {}
    for index = 1, math.min(#safe, Companion.MAX_EXCLUDED) do
        local entry, entrySecret = ns.Safe(safe[index])
        if not entrySecret and type(entry) == "table" then
            local name = safeString(entry.name)
            local slot = safeString(entry.slot)
            local level, levelSecret = ns.Safe(entry.level)
            if levelSecret or type(level) ~= "number" or level % 1 ~= 0 or level < 0 then
                level = nil
            end
            local vault, vaultSecret = ns.Safe(entry.vault)
            local catalyst, catalystSecret = ns.Safe(entry.catalyst)
            local bonusIDs, bonusOK = safeBonusIDs(entry.bonusIDs)
            local itemID = bonusOK and safeItemID(entry.itemID) or nil
            if name then
                list[#list + 1] = {
                    name = name,
                    slot = slot,
                    level = level,
                    itemID = itemID,
                    bonusIDs = itemID and bonusIDs or nil,
                    originalItem = itemID and safeItemID(entry.originalItem) or nil,
                    vault = ((not vaultSecret) and vault == true) or nil,
                    catalyst = ((not catalystSecret) and catalyst == true) or nil,
                }
            end
        end
    end
    if #list == 0 then
        return nil
    end
    return list
end

-- The ns.ItemKey of one left-out item, or nil for an entry that carries no
-- identity - every file written before C-10, and the committed placeholder.
-- The key is BUILT here rather than read: the format is Core.lua's one
-- definition and the companion never writes it, so a writer that learned to
-- spell keys differently could not quietly introduce a second one.
function Companion.ExcludedKey(entry)
    if type(entry) ~= "table" or entry.itemID == nil then
        return nil
    end
    return ns.ItemKey(entry.itemID, entry.bonusIDs)
end

-- How a left-out item was recognised. The key is identity; the name is the
-- best a pre-C-10 file can do and is named so a caller can say which it got.
Companion.EXCLUDED_BY_KEY = "key"
Companion.EXCLUDED_BY_NAME = "name+level"

-- Was this item one of the ones QE Live was never shown? -> the entry and how
-- it was recognised, or nil.
--
-- `key` is the ns.ItemKey of the item being asked about; `item` is optional and
-- carries `name` and `level` for the fallback. An entry that has an identity is
-- matched on identity ALONE - a name match against an entry whose key says a
-- different item is a wrong answer, not a second chance - and the name+level
-- fallback is used only for entries that carry no identity at all, which is
-- every file written before C-10.
function Companion.IsExcluded(excluded, key, item)
    if type(excluded) ~= "table" then
        return nil
    end
    local name = type(item) == "table" and item.name or nil
    local level = type(item) == "table" and item.level or nil
    for _, entry in ipairs(excluded) do
        local entryKey = Companion.ExcludedKey(entry)
        if entryKey then
            if key ~= nil and entryKey == key then
                return entry, Companion.EXCLUDED_BY_KEY
            end
        elseif name ~= nil and entry.name == name and entry.level == level then
            return entry, Companion.EXCLUDED_BY_NAME
        end
    end
    return nil
end

-- Was this item one of the ones the pass WAS shown (C-11, WKE-572)? The same
-- question, the same join and the same two ways of recognising an item: a pool
-- is one list of cards, and asking "did this pass see it" differently from "did
-- this pass leave it out" would be two answers to one question.
function Companion.IsConsidered(considered, key, item)
    return Companion.IsExcluded(considered, key, item)
end

-- One left-out item as words: "Lynx Spaulders (Shoulder, 678)". The slot and
-- the level are QE Live's own strings and his own number, and either may be
-- missing, so the brackets appear only when there is something to put in them.
function Companion.ExcludedItemText(entry)
    if type(entry) ~= "table" or type(entry.name) ~= "string" then
        return nil
    end
    local detail = {}
    if entry.slot then
        detail[#detail + 1] = entry.slot
    end
    if entry.level then
        detail[#detail + 1] = tostring(entry.level)
    end
    if entry.vault then
        detail[#detail + 1] = "Great Vault"
    end
    if entry.catalyst then
        detail[#detail + 1] = "Catalyst"
    end
    if #detail == 0 then
        return entry.name
    end
    return string.format("%s (%s)", entry.name, table.concat(detail, ", "))
end

-- Every left-out item as words, in the order the companion wrote them. This is
-- what a tooltip shows; the line below is what a panel prints.
function Companion.ExcludedLines(excluded)
    local lines = {}
    if type(excluded) ~= "table" then
        return lines
    end
    for _, entry in ipairs(excluded) do
        local text = Companion.ExcludedItemText(entry)
        if text then
            lines[#lines + 1] = text
        end
    end
    return lines
end

-- How many names the one-line version says before it counts the rest. Three
-- fits the panel's width at the sizes M5-2 settled on; the tooltip has them all.
Companion.EXCLUDED_NAMED = 3

-- The line both the Equip Now tab and the Vault tab print when the answer on
-- screen was produced over a subset of what the character owns (C-8). One
-- wording, in one place, so the two tabs cannot drift apart about it.
--
-- It says a count and then names, because the count is the part that changes
-- how the set is read and the names are the part that says whether it matters.
-- The wording names no source (owner decision, 2026-09-11, ARCHITECTURE.md §7):
-- the screen says what happened to the player's items, not whose run it was.
function Companion.ExcludedText(excluded)
    local names = Companion.ExcludedLines(excluded)
    if #names == 0 then
        return nil
    end
    local shownNames = {}
    for index = 1, math.min(#names, Companion.EXCLUDED_NAMED) do
        shownNames[index] = names[index]
    end
    local line = string.format("%d of your items weren't rated this time: %s", #names, table.concat(shownNames, ", "))
    if #names > #shownNames then
        line = string.format("%s and %d more", line, #names - #shownNames)
    end
    return line .. "."
end

-- Which named scenario a Top Gear document answers (C-6, WKE-540). Optional in
-- exactly the way the key level is: an Upgrade Finder document never carries
-- one, and a file written before C-6 carries none at all. The name is passed
-- through as the string the companion wrote and is never repaired here -
-- ns.QEImport.ScenarioKey is the one place a name becomes a shelf, and a name it
-- does not know gets a shelf of its own rather than the default's.
local function safeScenario(value)
    return safeString(value)
end

-- Validate(raw) -> { ok = true, writtenAt, writtenAtEpoch, companionVersion,
-- exports } or { ok = false, reason }. `raw` is whatever the chunk assigned to
-- ns.companionVerdict; nil means the committed placeholder is still in place,
-- which is not an error and is answered with `absent`, not a refusal to shout
-- about at every login.
function Companion.Validate(raw, now)
    if raw == nil then
        return { ok = false, absent = true, reason = "no companion file has been written yet" }
    end
    local safe, sawSecret = ns.Safe(raw)
    if sawSecret or type(safe) ~= "table" then
        return refuse("Data\\QEVerdict.lua set %s, not a table", shown(raw))
    end
    local writtenAt = safeString(safe.writtenAt)
    if not writtenAt then
        return refuse("Data\\QEVerdict.lua carries no writtenAt string (it is %s)", shown(safe.writtenAt))
    end
    local writtenAtEpoch = ns.EpochFromISO(writtenAt, now)
    if not writtenAtEpoch then
        return refuse(
            "Data\\QEVerdict.lua's writtenAt is %s, which is not an ISO 8601 UTC stamp like 2026-09-08T14:05:11Z",
            shown(writtenAt)
        )
    end
    local exports = ns.Safe(safe.exports)
    if type(exports) ~= "table" then
        return refuse("Data\\QEVerdict.lua carries no exports list (it is %s)", shown(safe.exports))
    end
    if #exports == 0 then
        return refuse("Data\\QEVerdict.lua's exports list is empty")
    end
    return {
        ok = true,
        writtenAt = writtenAt,
        writtenAtEpoch = writtenAtEpoch,
        companionVersion = safeString(safe.companionVersion),
        qeSettings = Companion.Settings(safe.qeSettings),
        excluded = Companion.Excluded(safe.excluded),
        -- C-12 (WKE-577): the one sentence the companion writes about the
        -- questions it did NOT ask this run, and why. Carried as it was
        -- written; nothing here reasons over it, and its absence means every
        -- configured scenario was asked.
        scenarioNote = safeString(safe.scenarioNote),
        exports = exports,
    }
end

-- One entry of the exports list -> { ok = true, schema, contentType, json } or
-- a refusal naming what was wrong with it. `contentType` is advisory: it is
-- what the companion ASKED QE Live for. The content type an import is filed
-- under is always the one inside the JSON (QEImport.ContentTypeKey), because
-- that is the one QE Live actually answered.
function Companion.Entry(raw, index)
    local safe = ns.Safe(raw)
    if type(safe) ~= "table" then
        return refuse("export %d is %s, not a table", index, shown(raw))
    end
    local json = safeString(safe.json)
    if not json then
        return refuse("export %d carries no json string (it is %s)", index, shown(safe.json))
    end
    if #json > Companion.MAX_JSON_BYTES then
        return refuse("export %d is %d bytes, past the %d Lootpath will read", index, #json, Companion.MAX_JSON_BYTES)
    end
    local schema = safeString(safe.schema)
    if not schema then
        return refuse("export %d carries no schema string (it is %s)", index, shown(safe.schema))
    end
    if not Companion.ImporterFor(schema) then
        return refuse(
            'export %d declares schema %s; Lootpath reads "%s" (Top Gear) and "%s" (Upgrade Finder)',
            index,
            shown(schema),
            Companion.TOP_GEAR_SCHEMA,
            Companion.UPGRADE_FINDER_SCHEMA
        )
    end
    return {
        ok = true,
        schema = schema,
        contentType = safeString(safe.contentType),
        keyLevel = safeKeyLevel(safe.keyLevel),
        scenario = safeScenario(safe.scenario),
        -- Per document since C-6: two Top Gear answers over the same gear
        -- disagree precisely because they were asked with different boxes, so
        -- each one says which. A document that does not carry the pair falls
        -- back to the file's, which is every file written before C-6.
        qeSettings = Companion.Settings(safe.qeSettings),
        -- Per document since C-8, because each Top Gear pass chooses its own
        -- pool: the Catalyst passes have clones to leave out that the base pass
        -- never had. A document that does not carry a list falls back to the
        -- file's, which is every file written before C-8.
        excluded = Companion.Excluded(safe.excluded),
        -- Which Top Gear pass produced this document, and what that pass was
        -- shown (C-11, WKE-572). A run over a character with more than thirty
        -- cards is a sequence of passes: pass 1 is the pool C-8 chooses, and
        -- each later pass keeps the import-time baseline and spends the room on
        -- the cards no pass has asked about yet. An item's rating is read off
        -- the pass that CONSIDERED it, and the plan sentence and the best set
        -- are read off pass 1 and nothing else.
        --
        -- A document that names no pass is pass 1, which is every file written
        -- before C-11 and every paste.
        pass = safePass(safe.pass),
        considered = Companion.Excluded(safe.considered),
        json = json,
    }
end

-- When the stored verdict for a content type was written or pasted, in epoch
-- seconds. A companion import is dated by the file that carried it, a paste by
-- the moment it was pasted; the two are compared so the later one wins
-- whichever way round they happened.
local function storedAt(verdict)
    if type(verdict) ~= "table" then
        return nil
    end
    local written = verdict.companionWrittenAt and ns.EpochFromISO(verdict.companionWrittenAt) or nil
    return written or tonumber(verdict.importedAt)
end

-- Import every export the file carries. Returns
--   { ok, writtenAt, writtenAtEpoch, companionVersion, qeSettings, excluded,
--     scenarioNote,
--     imported = { { contentType, spec, items, warnings } },
--     skipped  = { { index, reason, contentType, stale } },
--     unchanged = { contentType } }
-- or the file-level refusal unchanged. Nothing it could not parse is stored,
-- and a refusal never disturbs what already is: the paste path stays the
-- fallback for a broken companion.
function Companion.ImportAll(raw, now)
    local file = Companion.Validate(raw, now)
    if not file.ok then
        return file
    end
    local result = {
        ok = true,
        writtenAt = file.writtenAt,
        writtenAtEpoch = file.writtenAtEpoch,
        companionVersion = file.companionVersion,
        qeSettings = file.qeSettings,
        excluded = file.excluded,
        scenarioNote = file.scenarioNote,
        imported = {},
        skipped = {},
        unchanged = {},
    }
    for index = 1, #file.exports do
        local entry = Companion.Entry(file.exports[index], index)
        -- The same parser the editbox calls - whichever of the two that is -
        -- so every schema, version and gameType refusal applies here word for
        -- word. Entry has already refused a schema neither importer owns, so
        -- the nil branch below is reachable only if the two ever drift apart:
        -- it says so rather than indexing nil.
        local importer = entry.ok and Companion.ImporterFor(entry.schema) or nil
        if not entry.ok then
            result.skipped[#result.skipped + 1] = { index = index, reason = entry.reason }
        elseif not importer then
            result.skipped[#result.skipped + 1] = {
                index = index,
                reason = string.format("export %d has no importer for schema %s", index, shown(entry.schema)),
            }
        else
            local parsed = importer.Parse(entry.json)
            if not parsed.ok then
                result.skipped[#result.skipped + 1] = { index = index, reason = parsed.reason }
            else
                local verdict = parsed.verdict
                -- Set BEFORE anything asks what this verdict replaces: since
                -- C-7 an Upgrade Finder verdict is identified by content type
                -- AND key level, so a verdict that does not yet carry its level
                -- would be compared against the wrong shelf and every document
                -- after the first would be imported again on every /reload.
                -- The number is the companion's report of which button it
                -- clicked on QE Live's own key selector; nothing here derives
                -- it from the export.
                verdict.keyLevel = entry.keyLevel
                -- Set before Existing for the same reason, and it is the same
                -- failure: since C-6 a Top Gear verdict is identified by content
                -- type AND scenario, so three answers over one content type read
                -- as three repeats of the first and two would be thrown away.
                verdict.scenario = entry.scenario
                -- Set before Existing for the third time and the third reason
                -- (C-11): a Top Gear verdict is identified by content type,
                -- scenario AND pass, so a pass-2 answer that did not carry its
                -- number would look like a repeat of pass 1 and replace the set
                -- the plan is drawn from.
                verdict.pass = entry.pass
                local contentType = importer.ContentTypeKey(verdict)
                -- The counterpart of the SAME kind, never the other kind's:
                -- a Top Gear import and an Upgrade Finder import for one
                -- content type are two different answers and neither is stale
                -- because of the other.
                -- Since C-7 a companion file carries one Upgrade Finder
                -- document per key level, so "what does this replace" is the
                -- importer's question and not this file's: asking by content
                -- type alone would let the +4 document look like a repeat of
                -- the +2 one, and four of five answers would be dropped as
                -- unchanged.
                local existing = importer.Existing(verdict)
                local existingAt = storedAt(existing)
                if existing and existing.companionWrittenAt == file.writtenAt then
                    -- The same file, read again on the next /reload. Nothing
                    -- has changed, so nothing is said.
                    result.unchanged[#result.unchanged + 1] = contentType
                elseif existingAt and file.writtenAtEpoch < existingAt then
                    result.skipped[#result.skipped + 1] = {
                        index = index,
                        contentType = contentType,
                        stale = true,
                        reason = string.format(
                            "the companion's %s export was written %s, older than the %s import already stored;"
                                .. " keeping the stored one",
                            contentType,
                            ns.UI.AgeText(file.writtenAt, now),
                            contentType
                        ),
                    }
                else
                    verdict.source = Companion.SOURCE_COMPANION
                    verdict.companionWrittenAt = file.writtenAt
                    verdict.companionVersion = file.companionVersion
                    -- Carried onto the verdict, not left in the file's result:
                    -- the Vault panel reads it off whichever verdict is on
                    -- screen, which may have come back from SavedVariables
                    -- reloads after the file that wrote it was replaced.
                    verdict.qeSettings = entry.qeSettings or file.qeSettings
                    -- Carried the same way, and for the same reason: the note
                    -- that says which items QE Live never saw is drawn off
                    -- whichever verdict is on screen (C-8). Only a Top Gear
                    -- verdict gets one - an Upgrade Finder document is about
                    -- drops and chose no pool - so an Upgrade Finder verdict
                    -- never inherits the file's list.
                    if entry.schema == Companion.TOP_GEAR_SCHEMA then
                        verdict.excluded = entry.excluded or file.excluded
                        -- What this pass was shown (C-11). Never the file's:
                        -- the file has no such list, and a pool is a property
                        -- of the pass that chose it and of nothing else.
                        verdict.considered = entry.considered
                        -- Carried for the same reason and by the same rule
                        -- (C-12): the Vault tab's plan sentence is drawn off
                        -- whichever verdict is on screen, and it is the one
                        -- surface that can tell the reader his week's question
                        -- was never asked. An Upgrade Finder verdict gets none:
                        -- it is about drops and answers no scenario.
                        verdict.scenarioNote = file.scenarioNote
                    end
                    local stored = importer.Store(verdict)
                    if not stored.ok then
                        result.skipped[#result.skipped + 1] = { index = index, reason = stored.reason }
                    else
                        local count, noun = Companion.CountOf(entry.schema, verdict)
                        result.imported[#result.imported + 1] = {
                            schema = entry.schema,
                            contentType = contentType,
                            keyLevel = entry.keyLevel,
                            scenario = entry.scenario,
                            pass = entry.pass,
                            spec = verdict.spec,
                            items = count,
                            noun = noun,
                            warnings = parsed.warnings,
                        }
                    end
                end
            end
        end
    end
    return result
end

-- Where a verdict came from, for the window's line and /lootpath status. A
-- verdict stored before C-2 carries no `source` field and was pasted, which is
-- what the fallback says.
function Companion.SourceOf(verdict)
    if type(verdict) ~= "table" then
        return nil
    end
    if verdict.source == Companion.SOURCE_COMPANION then
        return Companion.SOURCE_COMPANION
    end
    return Companion.SOURCE_PASTE
end

-- The phrase the window and /lootpath status use to say where the verdict on
-- screen came from: "pasted", or "companion, written 4 minutes ago" through
-- the same UI.AgeText every other age on screen goes through. A companion
-- import whose stamp cannot be read still says who carried it.
function Companion.SourceText(verdict, now)
    local source = Companion.SourceOf(verdict)
    if not source then
        return nil
    end
    if source ~= Companion.SOURCE_COMPANION then
        return "pasted"
    end
    local writtenAt = verdict.companionWrittenAt
    if type(writtenAt) ~= "string" then
        return "companion"
    end
    return string.format("companion, written %s", ns.UI.AgeText(writtenAt, now))
end

-- Runs at load, once the DB exists. Chat is the only output: at login the
-- window has not been built, and building it here would put a frame on screen
-- nobody asked for. If it IS open (a /lootpath refresh with the window up),
-- it is redrawn.
function Companion.Startup(now)
    local result = Companion.ImportAll(ns.companionVerdict, now)
    if result.absent then
        return result
    end
    if not result.ok then
        ns.Log("companion file refused: %s. The paste box still works.", result.reason)
        return result
    end
    for _, entry in ipairs(result.imported) do
        ns.Log(
            "companion import: %s, %s, %s%s%s%s, %d %s, written %s.",
            ns.UI.KIND_LABEL[Companion.KIND_OF[entry.schema]] or entry.schema,
            entry.spec or "unknown spec",
            entry.contentType,
            entry.keyLevel and string.format(" +%d", entry.keyLevel) or "",
            entry.scenario and string.format(" (%s)", entry.scenario) or "",
            (entry.pass and entry.pass > 1) and string.format(" pass %d", entry.pass) or "",
            entry.items,
            entry.noun or "items",
            ns.UI.AgeText(result.writtenAt, now)
        )
        for _, warning in ipairs(entry.warnings or {}) do
            ns.Log("note: %s", warning)
        end
    end
    for _, skip in ipairs(result.skipped) do
        ns.Log("companion export %d refused: %s", skip.index, skip.reason)
    end
    if #result.imported > 0 then
        -- A new verdict is a new answer for every hover and every bag slot
        -- (R-2). The cache is not an event listener for this one: an import is
        -- not something the client announces.
        if ns.RoadsCache then
            ns.RoadsCache.Changed()
        end
        if ns.UI.frame then
            ns.UI.Refresh()
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- C-9 (WKE-559): what the companion last did.
--
-- The verdict file says what QE Live answered. It cannot say that the last run
-- DIED, or that it had nothing to do, because a failed run writes no verdict at
-- all and leaves the previous one in place - so from inside the game a companion
-- that crashed and a companion with nothing to do look identical, which is what
-- they did on 2026-09-09 (docs/ARCHITECTURE.md 11). `Data\CompanionStatus.lua`
-- is the companion saying so, and this is the reader.
--
-- Same rules as the verdict chunk: it is DATA. Every field goes through
-- ns.Safe, nothing in it is called, a field that is missing or unreadable is
-- silence rather than a guess, and a file that is not a table at all is one
-- clause on the strip instead of an error.

Companion.STATUS_STATES = {
    idle = true,
    running = true,
    skipped = true,
    failed = true,
}

-- The clauses, in one place, because the strip is the only thing that says them
-- and a test that spells them out twice can drift.
Companion.STATUS_NEVER = "companion: never seen"
Companion.STATUS_UNREADABLE = "companion: status file not understood"
Companion.STATUS_LOG_HINT = " - see companion.log"

-- Status(raw) -> { absent = true } for the committed placeholder, which is not
-- an error; { ok = false, reason } for a file that is there but says nothing
-- this can read; or the whole record.
function Companion.Status(raw)
    if raw == nil then
        return { absent = true, reason = "the companion has not written a status file yet" }
    end
    local safe, sawSecret = ns.Safe(raw)
    if sawSecret or type(safe) ~= "table" then
        return { ok = false, reason = string.format("Data\\CompanionStatus.lua set %s, not a table", shown(raw)) }
    end
    local state = safeString(safe.state)
    if not state or not Companion.STATUS_STATES[state] then
        return {
            ok = false,
            reason = string.format(
                "Data\\CompanionStatus.lua carries state %s, which is not one it can be in",
                shown(safe.state)
            ),
        }
    end
    local exitCode
    local code, codeSecret = ns.Safe(safe.exitCode)
    if not codeSecret and type(code) == "number" and code >= 0 and code % 1 == 0 then
        exitCode = code
    end
    return {
        ok = true,
        state = state,
        startedAt = safeString(safe.startedAt),
        finishedAt = safeString(safe.finishedAt),
        stage = safeString(safe.stage),
        message = safeString(safe.message),
        profileCapturedAt = safeString(safe.profileCapturedAt),
        verdictWrittenAt = safeString(safe.verdictWrittenAt),
        companionVersion = safeString(safe.companionVersion),
        exitCode = exitCode,
    }
end

-- The wall clock of one of the companion's UTC stamps, in the reader's own
-- timezone, because "(23:06)" is how a person says when something happened and
-- an ISO stamp is not. nil for a stamp ns.EpochFromISO cannot read, and the
-- caller then says the clause without a time rather than with a wrong one.
local function clockText(iso, now)
    local epoch = ns.EpochFromISO(iso, now)
    if not epoch or type(date) ~= "function" then
        return nil
    end
    -- math.floor for the same reason ns.EpochFromISO coerces its fields: an
    -- epoch second is whole already, and `date`'s declared time parameter is an
    -- integer, which a plain number fails the type gate on.
    local text = date("%H:%M", math.floor(epoch))
    if type(text) ~= "string" then
        return nil
    end
    return text
end

local function withClock(text, iso, now)
    local at = clockText(iso, now)
    if not at then
        return text
    end
    return string.format("%s (%s)", text, at)
end

-- The one clause the status strip carries (M5-2's UI.StatusStripModel). One
-- sentence fragment, never two: the strip already says five things.
--
--   waiting for the vault
--   companion: wrote 3 minutes ago
--   companion: profile unchanged, no run (23:06)
--   companion: FAILED at profile (21:06) - see companion.log
--   companion: run started 22:48
--   companion: never seen
--
-- The vault wait comes first and replaces the rest (M3-16): while it lasts,
-- what the companion did on its LAST run is a stale answer to "what is
-- happening", and the refresh that is still going is the live one. It clears
-- itself the moment the refresh reloads or gives up, and the bound is a few
-- seconds, so nothing can leave the strip stuck on it.
function Companion.StatusText(raw, now)
    if Companion.waitingForVault then
        return Companion.WAITING_FOR_VAULT
    end
    local status = Companion.Status(raw)
    if status.absent then
        return Companion.STATUS_NEVER
    end
    if not status.ok then
        return Companion.STATUS_UNREADABLE
    end
    if status.state == "running" then
        local at = clockText(status.startedAt, now)
        if not at then
            return "companion: run started"
        end
        return "companion: run started " .. at
    end
    if status.state == "skipped" then
        return withClock("companion: profile unchanged, no run", status.finishedAt, now)
    end
    if status.state == "failed" then
        local where = status.stage and (" at " .. status.stage) or ""
        return withClock("companion: FAILED" .. where, status.finishedAt, now) .. Companion.STATUS_LOG_HINT
    end
    -- idle: a run that finished. The age is the VERDICT's own writtenAt, so the
    -- strip's "wrote 3 minutes ago" and the verdict line's age are one number
    -- read out of two files rather than two answers.
    if status.verdictWrittenAt then
        return "companion: wrote " .. ns.UI.AgeText(status.verdictWrittenAt, now)
    end
    return withClock("companion: idle", status.finishedAt, now)
end

-- The longer sentence for the strip's tooltip, or nil when the file says
-- nothing the clause did not. The message is the companion's own words for what
-- happened, carried like every other string it writes.
function Companion.StatusTooltip(raw, now)
    local status = Companion.Status(raw)
    if status.absent then
        return "The companion has not written a status file yet. Nothing has run, or it is an older companion."
    end
    if not status.ok then
        return status.reason
    end
    if not status.message then
        return nil
    end
    local when = status.finishedAt or status.startedAt
    return withClock(string.format("The companion's last run: %s", status.message), when, now)
end

-- `/lootpath refresh` - the loop from inside the game, in one word. It takes
-- the three snapshots the companion's profile is built from, then flushes
-- SavedVariables by reloading so the companion can read them; the second
-- `/lootpath refresh`, once the companion says it is done, loads the file it
-- wrote. There is no third step: the startup import above is the rest. Two
-- reloads is the floor and is said out loud rather than hidden (decision
-- 2026-09-07).
--
-- The captures are C-3's (WKE-536). Before them, refresh reloaded and nothing
-- else, so `tools/companion/lib/simc-profile.js` built its profile from
-- whatever the owner had last CAPTURED - on 2026-09-07 that was the 09-05
-- Guardian-spec snapshot, and the companion valued a set the character had not
-- worn in two days. Nothing else in the addon writes gear to SavedVariables,
-- and the companion cannot make the client read anything, so the capture has
-- to happen here (decision 2026-09-08).
--
-- Out of combat only. ReloadUI is protected in combat, the captures refuse
-- there too, and the standing rule is that nothing Lootpath does runs in
-- combat anyway.
--
-- `journal` is deliberately not in this list: it is the one asynchronous
-- capture (it waits on EJ_LOOT_DATA_RECIEVED, 434-869 ms in the committed
-- walks), the SimC profile reads none of it, and a reload while it is running
-- would abandon it. The loot map's own cache (`db.global.journalCache`) is
-- untouched by a refresh.
--
-- `currencies` joined the list in M3-9 (WKE-544) for a different reason from the
-- other three: the SimC profile does not read it and the companion never sees
-- it, but the Vault tab's headline says how many Catalyst charges and crests the
-- player has beside the scenarios that assumed them, and `/lootpath refresh` is
-- the one command the owner already runs every week. It is a synchronous read of
-- C_CurrencyInfo, so it costs the refresh nothing.
Companion.REFRESH_CAPTURES = { "env", "inventory", "vault", "currencies" }

Companion.REFRESH_CAPTURED_LINE = "captured %s - reloading so the companion can read them."
Companion.REFRESH_SECOND_LINE = "reload again when it says done; that second /lootpath refresh is all that is "
    .. "left - the file it writes is imported as the game comes back."
Companion.REFRESH_REFUSED_LINE = "/lootpath refresh stopped: capture '%s' refused: %s. Not reloading."
Companion.REFRESH_COMBAT_REASON = "/lootpath refresh does nothing in combat: reloading is blocked there, and so "
    .. "are the captures. Try again once the fight is over."
Companion.REFRESH_NO_RELOAD_REASON = "this client has no ReloadUI"

-- M3-16 (WKE-557): what the strip and the chat frame say while the vault
-- capture is holding the refresh open. The wait is bounded by
-- `ns.VAULT_INTERACT_TIMEOUT_SECONDS` and happens only when the client says
-- rewards are waiting and lists none of them, so most refreshes never show it.
Companion.WAITING_FOR_VAULT = "waiting for the vault"
Companion.REFRESH_WAITING_LINE = "waiting for the vault: the client is holding the rewards back, so Lootpath "
    .. "asked for them the way the Great Vault window does. The reload follows."

-- True from the moment the vault capture starts waiting until the refresh
-- reloads or gives up. `ns.UI.StatusStripModel` reads it through
-- `Companion.StatusText`, which is why it lives on the module rather than in a
-- local: the strip has no other way to say that the refresh is still going.
Companion.waitingForVault = false

-- M3-16a (WKE-581): the reload the player has to click.
--
-- **Why a click and not a call.** `ReloadUI` is refused - "Interface action
-- failed because of an AddOn" - unless the client can attribute it to the
-- player's own hardware event. Before M3-16 the chain was synchronous, so the
-- `ReloadUI` at its end was still inside the slash command's execution and the
-- client allowed it. M3-16 made the vault capture wait for
-- `WEEKLY_REWARDS_UPDATE`, and a `ReloadUI` called from that event's
-- continuation is no longer the player's: the owner's screen on 2026-09-15
-- printed all three refresh lines and then the refusal, and nothing reloaded
-- (docs/ARCHITECTURE.md 9).
--
-- So: when the chain finishes inside the command it reloads immediately, as it
-- did before M3-16. When it had to wait, it asks instead. A `StaticPopup`
-- button IS a hardware event - Blizzard's own `TOO_MANY_LUA_ERRORS` and
-- `ADDON_ACTION_FORBIDDEN` dialogs call `ReloadUI` from `OnAccept`
-- (`.luals/.../Blizzard_StaticPopup_Game/GameDialogDefs.lua.annotated.lua`
-- lines 482-489 and 568-575, read 2026-09-15) - and this is the same shape.
-- The login ask below is what makes the wait rare in the first place.
Companion.RELOAD_POPUP = "LOOTPATH_RELOAD_AFTER_REFRESH"
Companion.RELOAD_POPUP_TEXT = "Gear captured. Reload to send it?"
Companion.RELOAD_POPUP_ACCEPT = "Reload"
Companion.RELOAD_POPUP_CANCEL = "Not now"
Companion.REFRESH_POPUP_LINE = "captured %s - click Reload to send them. After a wait the reload has to be "
    .. "your own click; the client refuses any other kind."
Companion.REFRESH_POPUP_ABSENT_LINE = "captured %s - type /reload to send them. After a wait the reload has to "
    .. "be your own, and this client cannot show the box that asks."

if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs[Companion.RELOAD_POPUP] = {
        text = Companion.RELOAD_POPUP_TEXT,
        button1 = Companion.RELOAD_POPUP_ACCEPT,
        button2 = Companion.RELOAD_POPUP_CANCEL,
        OnAccept = function()
            if type(ReloadUI) == "function" then
                ReloadUI()
            end
        end,
        -- No timeout: a box that vanished on its own would leave the captures
        -- in memory with nothing on screen saying so. `whileDead` because a
        -- player who died to the pull he refreshed before is still owed the
        -- reload, and `hideOnEscape` because Not now is always allowed - the
        -- strip's R-6 wait line keeps the same click either way.
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

-- Shows it, or says the same thing in chat on a client that has no
-- StaticPopup_Show. Returns "popup" or "chat" so the caller can record which.
function Companion.AskForReload(summary)
    if type(StaticPopup_Show) == "function" then
        ns.Log(Companion.REFRESH_POPUP_LINE, summary)
        StaticPopup_Show(Companion.RELOAD_POPUP)
        return "popup"
    end
    ns.Log(Companion.REFRESH_POPUP_ABSENT_LINE, summary)
    return "chat"
end

-- What the four snapshots hold, in the owner's words rather than the capture
-- names. The bank half is read back out of the snapshot that was just taken -
-- `C_Bank.CanViewBank` for the character's own bank, which the 2026-09-05
-- transcript showed answers true only while the bank frame is open - rather
-- than asking the client a second time: the capture is the one reader, and a
-- second read could disagree with the snapshot the companion will get.
function Companion.RefreshSummary(snapshots)
    local bank = "closed"
    local inventory = type(snapshots) == "table" and snapshots.inventory or nil
    local data = type(inventory) == "table" and type(inventory.data) == "table" and inventory.data or nil
    local bankData = data and type(data.bank) == "table" and data.bank or nil
    local predicates = bankData and type(bankData.predicates) == "table" and bankData.predicates or nil
    local canView = predicates and type(predicates.CanViewBank) == "table" and predicates.CanViewBank or nil
    local character = canView and type(canView.Character) == "table" and canView.Character or nil
    if character and ns.Safe(character[1]) == true then
        bank = "open"
    end
    return string.format("gear, bags, bank (%s), vault, currencies", bank)
end

-- The captures run one after another and the reload is the LAST thing, after
-- all four (M3-16): `vault` can be asynchronous - when the client says rewards
-- are waiting and lists none of them it asks for them and waits a bounded few
-- seconds for `WEEKLY_REWARDS_UPDATE` - and a `ReloadUI()` in the middle of
-- that wait would throw away the very snapshot the refresh exists to take.
--
-- **M3-16a (WKE-581): the reload is never called from that wait's
-- continuation.** It is refused there; see `Companion.RELOAD_POPUP` above. The
-- chain therefore ends in one of two ways:
--
--   * **Nothing had to wait** - the ordinary week, and every week at all once
--     the login ask below has run - so all four captures finished inside the
--     slash command's own execution and `ReloadUI()` is still the player's
--     action. It reloads immediately, exactly as it did before M3-16.
--   * **Something waited** - the login ask failed, timed out, or never ran -
--     so this code is running from an event callback. It asks for the reload
--     with a `StaticPopup` whose button is a hardware event, and returns
--     `reloadPending`.
--
-- `Refresh` returns `{ ok = true, pending = true }` while it is still waiting,
-- the way `ns.RunCapture` does, and `onDone` (optional) is called with the
-- final result exactly once either way.
function Companion.Refresh(onDone)
    Companion.waitingForVault = false
    -- Set the moment a capture answers `pending`, and never cleared: it is what
    -- says this chain left the player's command, which is what decides between
    -- the reload and the popup. Not the same thing as `waitingForVault`, which
    -- is the strip's live clause and goes false again when the wait ends.
    local waited = false
    local settled
    local function done(result)
        if settled then
            return settled
        end
        settled = result
        Companion.waitingForVault = false
        ns.captureTrigger = nil
        if onDone then
            onDone(result)
        end
        return result
    end
    if InCombatLockdown() then
        ns.Log("%s", Companion.REFRESH_COMBAT_REASON)
        return done({ ok = false, reason = "combat" })
    end
    -- Checked before anything is captured: four snapshots the owner cannot
    -- flush are four snapshots written for nothing.
    if type(ReloadUI) ~= "function" then
        ns.Log("%s", Companion.REFRESH_NO_RELOAD_REASON)
        return done({ ok = false, reason = Companion.REFRESH_NO_RELOAD_REASON })
    end
    local snapshots = {}
    local index = 0
    -- R-6 (WKE-578): every snapshot this chain stores is labelled as the
    -- refresh's own, so the companion can tell a write carrying a fresh capture
    -- from a write that is a logout flushing the last one again. Cleared on
    -- every exit from `done` below, so a later `/lootpath capture` is a command
    -- again.
    ns.captureTrigger = "refresh"
    local function step()
        index = index + 1
        local name = Companion.REFRESH_CAPTURES[index]
        if not name then
            Companion.waitingForVault = false
            local summary = Companion.RefreshSummary(snapshots)
            -- R-6 (WKE-578): the stamp the wait line counts from, written
            -- BEFORE the reload, because the reload is what puts it on disk.
            -- Written on the popup path too, and for the same reason: the
            -- reload is still coming, and until it does the strip's wait line
            -- carries the same click the popup's Reload button does, so a
            -- player who dismissed the box is not stranded.
            ns.Drift.RefreshStarting()
            if waited then
                local asked = Companion.AskForReload(summary)
                ns.Log("%s", Companion.REFRESH_SECOND_LINE)
                return done({ ok = true, reloaded = false, reloadPending = asked, captured = snapshots })
            end
            ns.Log(Companion.REFRESH_CAPTURED_LINE, summary)
            ns.Log("%s", Companion.REFRESH_SECOND_LINE)
            ReloadUI()
            return done({ ok = true, reloaded = true, captured = snapshots })
        end
        local result = ns.RunCapture(name, function(final)
            if not final.ok then
                local reason = final.reason or "no result"
                ns.Log(Companion.REFRESH_REFUSED_LINE, name, tostring(reason))
                return done({ ok = false, reason = reason, capture = name, captured = snapshots })
            end
            snapshots[name] = final.snapshot
            step()
        end)
        -- A capture that has not answered yet is the vault asking the server
        -- for the rewards. Said out loud, once, because the refresh looks
        -- stopped otherwise and the reload is genuinely still coming.
        if type(result) == "table" and result.pending and not settled then
            waited = true
            Companion.waitingForVault = true
            ns.Log("%s", Companion.REFRESH_WAITING_LINE)
            if ns.UI and ns.UI.RefreshStrip then
                ns.UI.RefreshStrip()
            end
        end
    end
    step()
    return settled or { ok = true, pending = true }
end

-- ---------------------------------------------------------------------------
-- The capture at the flush (R-7, WKE-579; renamed and relabelled by R-7a,
-- WKE-582).
--
-- Until now the four snapshots were taken only when `/lootpath refresh` ran, so
-- "log out, and your plan is current next time you log in" was true only for a
-- player who refreshed first: the logout flushed whatever was last captured, the
-- companion fingerprinted an unchanged profile and skipped, and the next login
-- loaded the same plan (R-6's finding, docs/ARCHITECTURE.md §7). Taking the same
-- four snapshots at `PLAYER_LOGOUT` is what makes the sentence true, because the
-- logout is the very write the companion wakes on.
--
-- **It is not only a logout, and the label says so (R-7a).** `PLAYER_LOGOUT`
-- fires on `/reload` too - the UI is unloaded either way - and the owner's
-- 2026-09-15 pull had five `env` snapshots stamped `capturedOn = "logout"` for at
-- most one logout, which made the companion print `run after logout` for a plain
-- reload. Nothing at the moment the event fires can tell the two apart; only the
-- next load can, and by then the snapshot is written. So the sequence keeps
-- running on both - it is why the second reload of the refresh loop carries
-- fresh gear - and everything it stores is labelled `flush`, which is true of
-- both and is all this can prove.
--
-- What is different from the refresh, and why:
--
--   * **No reload.** The client is already leaving; `ReloadUI` is never called
--     from here and the sequence does not depend on it existing.
--   * **Nothing asynchronous.** `PLAYER_LOGOUT` is a synchronous event (Ketho's
--     `SystemDocumentation.lua`: `LiteralName = "PLAYER_LOGOUT", SynchronousEvent
--     = true`, read 2026-09-15) and the client stops running Lua after it, so a
--     timer or an event listener registered here would never fire. Every capture
--     therefore has to finish inside this call - which is why the vault is not
--     one of them, below.
--   * **The vault is not captured at all (M3-16b, WKE-583).** M3-16's
--     interaction asks the server for the withheld rewards and waits up to
--     `ns.VAULT_INTERACT_TIMEOUT_SECONDS` for `WEEKLY_REWARDS_UPDATE`, and this
--     event has no time for a wait. R-7 read the vault here plainly and labelled
--     the read; the owner's reset day is what that cost. On 2026-09-15 the
--     refresh at 19:09:29Z asked the client and stored its answer, the flush at
--     the refresh's own reload stored the same read two seconds later, and being
--     the newest snapshot the plain one is what the companion built the profile
--     from - `0 vault`, `warning: no generated Great Vault reward`. A read that
--     cannot ask can only shadow one that did, so `Companion.FLUSH_CAPTURES` is
--     the refresh's four without it, and the vault snapshot stays the refresh's
--     and the login ask's: the reads that ask.
--   * **Nothing here can fail loudly.** Each capture goes through `ns.RunCapture`,
--     which already pcalls the capture body, and through a `pcall` of its own on
--     top, so a capture that throws leaves the ones after it to run and cannot
--     stop the unload.
--
-- Combat: `ns.RunCapture` refuses every capture in combat, so a forced logout in
-- combat captures NOTHING - not even an `env` record saying so - and the last
-- snapshot flushes as it did before. That is the client rule ("nothing runs in
-- combat") and this sequence does not try to work around it; it returns
-- `{ ok = false, reason = "combat" }` and touches nothing.
Companion.FLUSH_TRIGGER = "flush"

-- What the flush takes: the refresh's captures except the vault, for the reason
-- above. Built from `REFRESH_CAPTURES` rather than written out again, so a
-- capture added to the refresh is taken at the flush too unless it is named
-- here.
Companion.FLUSH_SKIPS = { vault = true }
Companion.FLUSH_CAPTURES = {}
for _, name in ipairs(Companion.REFRESH_CAPTURES) do
    if not Companion.FLUSH_SKIPS[name] then
        Companion.FLUSH_CAPTURES[#Companion.FLUSH_CAPTURES + 1] = name
    end
end

function Companion.CaptureAtFlush()
    if InCombatLockdown() then
        return { ok = false, reason = "combat", captured = {} }
    end
    local startedAt = debugprofilestop and debugprofilestop() or nil
    local previousTrigger = ns.captureTrigger
    -- Every snapshot this sequence stores is labelled `flush`, which is what
    -- lets the companion's log say `run after a logout or reload (gear captured
    -- at the flush)` off a label rather than guessing (R-6) - and is all the
    -- label can prove, because `PLAYER_LOGOUT` fires on both (R-7a).
    ns.captureTrigger = Companion.FLUSH_TRIGGER
    local snapshots, failures = {}, {}
    for _, name in ipairs(Companion.FLUSH_CAPTURES) do
        local ok, err = pcall(ns.RunCapture, name, function(final)
            if final.ok then
                snapshots[name] = final.snapshot
            else
                failures[#failures + 1] = { capture = name, reason = final.reason }
            end
        end)
        if not ok then
            failures[#failures + 1] = { capture = name, reason = tostring(err) }
        end
    end
    ns.captureTrigger = previousTrigger
    local elapsedMs = startedAt and debugprofilestop and (debugprofilestop() - startedAt) or nil
    -- Written onto the `env` snapshot after the sequence, because the whole
    -- sequence's cost is not known until it is over and `env` is the record the
    -- companion reads. Both fields are the evidence for "this cost the unload
    -- nothing"; nothing in the addon reads either. R-7a renamed `logoutMs` to
    -- `flushMs` with the label, for the same reason: the owner's five measured
    -- runs were 19.5-33.1 ms and only one of them was a logout.
    if snapshots.env then
        snapshots.env.capturedOn = Companion.FLUSH_TRIGGER
        snapshots.env.flushMs = elapsedMs
    end
    return {
        ok = #failures == 0,
        captured = snapshots,
        failures = failures,
        elapsedMs = elapsedMs,
    }
end

-- ---------------------------------------------------------------------------
-- The vault question, asked once at login (M3-16a, WKE-581).
--
-- M3-16 put the question where the answer was wanted: inside the refresh, which
-- then had to wait for it. That wait is what made the refresh's `ReloadUI` an
-- addon's action rather than the player's, and the client refused it
-- (`Companion.RELOAD_POPUP` above). Asking at login instead costs the same one
-- interaction, happens where nothing is waiting on it, and means that by the
-- time the player types `/lootpath refresh` the client already carries the
-- rewards: `vaultNeedsInteraction` answers "the activities already carry
-- rewards", the vault capture finishes inside the call, and the whole chain is
-- synchronous again.
--
-- What is the same as M3-16, exactly: `OnUIInteract`, a bounded wait of
-- `ns.VAULT_INTERACT_TIMEOUT_SECONDS` for `WEEKLY_REWARDS_UPDATE`, and
-- `CloseInteraction` on every path out including the timeout - one
-- `ns.VaultInteract`, not a copy. What is different: nothing is captured and
-- nothing is reloaded. The client is simply left holding its own data.
--
-- What is NOT asked, and why: the question is only asked in the state the
-- 2026-09-09/10 measurement described - `HasAvailableRewards()` true and not
-- one activity carrying a reward. A vault with nothing waiting, or one whose
-- rewards the client is already carrying, is left alone.
--
-- Combat: nothing runs in combat, so a login that lands in a fight defers to
-- `PLAYER_REGEN_ENABLED` and asks when it is over. Once per session either way.
--
-- **What is NOT verified, and what says so:** whether the client answers
-- `HasAvailableRewards()` truthfully as early as `PLAYER_ENTERING_WORLD`, and
-- whether `WEEKLY_REWARDS_UPDATE` fires at all outside the Great Vault window
-- (M3-16's own open question, never measured). The record below is the whole
-- answer to both - `askedAtLogin` says the login found the state, `updateFired`
-- and `waitedMs` say the client answered and how fast - and the next `env`
-- capture carries it. If the login ask turns out to find nothing, the refresh
-- still works: it captures, waits, and asks for the reload with a click.
Companion.LOGIN_ASK_NOTHING = "the client says no rewards are waiting"
Companion.LOGIN_ASK_CARRIED = "the activities already carry rewards"
Companion.LOGIN_ASK_NO_API = "this client has no C_WeeklyRewards.OnUIInteract"
Companion.LOGIN_ASK_COMBAT = "deferred: the login was in combat"

-- Guards the once-per-session rule. `ns.vaultLoginAsk` is the record itself,
-- which the next `env` capture copies into its snapshot; this is only whether
-- the question has been settled, because a record that says `askedAtLogin =
-- false` still means the login looked.
Companion.loginAsked = false

-- Whether the client is in the state the question is for. Deliberately NOT
-- `Captures.lua`'s `vaultNeedsInteraction`: that one is local to the capture
-- and reads the reward links the capture had just built, while this one asks
-- the client the two questions directly and builds nothing.
local function loginAskNeeded()
    local W = C_WeeklyRewards
    if type(W and W.OnUIInteract) ~= "function" then
        return false, Companion.LOGIN_ASK_NO_API
    end
    if ns.Safe(ns.Probe(W.HasAvailableRewards)[1]) ~= true then
        return false, Companion.LOGIN_ASK_NOTHING
    end
    -- Through `ns.Safe` rather than iterated raw: a secret table comes back as
    -- a marker string and `type` then sends it past the loop, which is the
    -- client rule and not a guess about what the vault returns.
    local activities = ns.Safe(ns.Probe(W.GetActivities)[1])
    if type(activities) == "table" then
        for _, activity in ipairs(activities) do
            local rewards = type(activity) == "table" and ns.Safe(activity.rewards) or nil
            for _, reward in ipairs(type(rewards) == "table" and rewards or {}) do
                if type(reward) == "table" and ns.Safe(reward.itemDBID) ~= nil then
                    return false, Companion.LOGIN_ASK_CARRIED
                end
            end
        end
    end
    return true, "rewards are waiting and no activity carries one"
end

-- Returns the record, or nil when the ask was deferred to the end of combat.
-- `onDone` (optional) is called with the record exactly once, whenever it
-- settles; nothing in the addon needs it, the tests do.
function Companion.AskVaultAtLogin(onDone)
    if Companion.loginAsked then
        return ns.vaultLoginAsk
    end
    if InCombatLockdown() then
        -- Not settled: the session still owes itself the question, and
        -- `PLAYER_REGEN_ENABLED` is what asks it.
        ns.vaultLoginAsk = { askedAtLogin = false, reason = Companion.LOGIN_ASK_COMBAT }
        return nil
    end
    Companion.loginAsked = true
    local needed, reason = loginAskNeeded()
    if not needed then
        ns.vaultLoginAsk = { askedAtLogin = false, reason = reason }
        if onDone then
            onDone(ns.vaultLoginAsk)
        end
        return ns.vaultLoginAsk
    end
    local record = { askedAtLogin = true, reason = reason, updateFired = false, timedOut = false }
    ns.vaultLoginAsk = record
    ns.VaultInteract(record, nil, function()
        if onDone then
            onDone(record)
        end
    end)
    return record
end

ns.onReady[#ns.onReady + 1] = function()
    Companion.Startup()
end
