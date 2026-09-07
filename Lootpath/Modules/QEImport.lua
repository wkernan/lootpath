-- Lootpath/Modules/QEImport.lua (M2-1, WKE-518)
-- The one place QE Live's answers enter the addon: pasted Top Gear JSON in,
-- a verdict model out, or a plain refusal. Pure Lua over Libs/json.lua; the
-- only client read is UnitName, for the character-mismatch warning.
--
-- This module transports QE Live's numbers. It never adjusts them, never
-- averages them, never fills a gap with one of its own. Every field below is
-- carried through from the export or dropped.
--
-- Schema, read from QE Live's public source on 2026-09-06 (branch `dev`,
-- src/General/Modules/TopGear/Report/TopGearJSONExport.ts; no licence file, so
-- it is read and never copied):
--
--   { schema: "qe-live-droptimizer", version: 1, exportedAt: ISO,
--     player: { name, realm, region, spec, gameType: "Retail"|"Classic" },
--     contentType, reportId,
--     topSet: { score, stats, items: [Item] },
--     differentials: [ { scorePercent, hpsDifference, items: [Item], gems: [int] } ] }
--   Item = { slot, id, level, bonusIDs: [int], gems: [int], enchant, tertiary,
--            setId, isVault, isExclusive, source: {} }
--
-- `topSet.items` is the chosen set (it falls back to the full item list when
-- nothing is flagged `isChosen`). A differential is an *alternative* set,
-- carrying only the items that differ from the top set.

local _, ns = ...

ns.QEImport = {}
local QEImport = ns.QEImport

QEImport.SCHEMA = "qe-live-droptimizer"
QEImport.VERSION = 1
QEImport.GAME_TYPE = "Retail"

-- QE Live's own content types, read from its source on 2026-09-06:
-- `src/globalTypes.d.ts` line 130 declares `contentTypes = "Raid" | "Dungeon"`,
-- its content toggle (`SetupAndMenus/Header/ContentToggle.js`) offers exactly
-- those two values, and the exporter writes `result.contentType || ""`. There
-- is no "Mythic+" string anywhere in it: "Dungeon" IS the Mythic+ side.
QEImport.CONTENT_TYPES = { "Dungeon", "Raid" }
QEImport.UNKNOWN_CONTENT_TYPE = "Unknown"

-- Sign conventions, the whole failure mode of this module. Pinned twice from
-- QE Live's source (2026-09-06):
--   TopGearJSONExport.ts:42-43 states them - "scoreDifference: number (% -
--   positive means alt is worse), rawDifference: number (HPS - negative means
--   alt is worse)" - and TopGearEngineShared.js:50-51 computes them, with
--   `itemSet` the alternative and `primeSet` the top set:
--     scoreDifference = (prime.hardScore - alt.hardScore) / prime.hardScore * 100
--     rawDifference   =  alt.hardScore - prime.hardScore
-- The exporter renames them `scorePercent` and `hpsDifference`. Every consumer
-- reads the direction from AlternativeIsBetter, never from its own arithmetic.
QEImport.ALT_WORSE_SCORE_PERCENT_SIGN = 1
QEImport.ALT_WORSE_HPS_DIFFERENCE_SIGN = -1

-- true when the alternative beats the top set, false when it is worse or ties,
-- nil when the alternative carries no comparable score.
function QEImport.AlternativeIsBetter(alternative)
    if type(alternative) ~= "table" then
        return nil
    end
    local percent = tonumber(alternative.scorePercent)
    if not percent then
        return nil
    end
    return percent * QEImport.ALT_WORSE_SCORE_PERCENT_SIGN < 0
end

-- Renders a value seen in the export for a refusal message. Strings are quoted
-- and clipped so a pasted blob cannot become a wall of chat text.
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

local function numbersOf(value)
    local out = {}
    if type(value) ~= "table" then
        return out
    end
    for i = 1, #value do
        local n = tonumber(value[i])
        if n then
            out[#out + 1] = n
        end
    end
    return out
end

local function arrayOf(value)
    if type(value) == "table" then
        return value
    end
    return {}
end

-- One export item -> one verdict item, or nil when it carries no usable
-- identity (ns.ItemKey refuses a non-integer id or a non-numeric bonus ID).
-- `bonusIDs` is stored sorted, the same shape Inventory records carry, so
-- Match (M2-2) compares like with like.
function QEImport.Item(raw)
    if type(raw) ~= "table" then
        return nil
    end
    local key = ns.ItemKey(raw.id, raw.bonusIDs)
    if not key then
        return nil
    end
    local bonusIDs = numbersOf(raw.bonusIDs)
    table.sort(bonusIDs)
    return {
        key = key,
        itemID = tonumber(raw.id),
        slot = stringOrNil(raw.slot),
        level = tonumber(raw.level),
        bonusIDs = bonusIDs,
        gems = numbersOf(raw.gems),
        enchant = stringOrNil(raw.enchant),
        tertiary = stringOrNil(raw.tertiary),
        setId = tonumber(raw.setId) or 0,
        isVault = raw.isVault == true,
        isExclusive = raw.isExclusive == true,
        source = type(raw.source) == "table" and raw.source or nil,
        count = 1,
    }
end

-- Vault options can be ranked into the top set or left out of it, so they are
-- harvested from every item the export mentions, top set and alternatives
-- alike; without that, an option QE Live rejected would never reach the Vault
-- panel, which is exactly the option the owner needs told about.
local function harvestVault(vault, item)
    if item.isVault and not vault[item.key] then
        vault[item.key] = item
    end
end

function QEImport.Parse(text)
    if type(text) ~= "string" or text:match("^%s*$") then
        return refuse("nothing to import: paste QE Live's Top Gear JSON (its Download JSON button) here")
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
    if decoded.schema ~= QEImport.SCHEMA then
        return refuse(
            'not a QE Live Top Gear export: its schema is %s, Lootpath reads "%s"',
            shown(decoded.schema),
            QEImport.SCHEMA
        )
    end
    if type(decoded.version) ~= "number" or decoded.version ~= QEImport.VERSION then
        return refuse(
            "this export is %s version %s; Lootpath reads version %d. Re-export from QE Live, or update Lootpath.",
            QEImport.SCHEMA,
            shown(decoded.version),
            QEImport.VERSION
        )
    end
    local topSet = decoded.topSet
    if type(topSet) ~= "table" then
        return refuse(
            "this export has no topSet (it is %s): run Top Gear on QE Live and download the JSON from its report",
            shown(topSet)
        )
    end
    local player = type(decoded.player) == "table" and decoded.player or {}
    if player.gameType ~= QEImport.GAME_TYPE then
        return refuse(
            "this export's gameType is %s; Lootpath reads %s exports only",
            shown(player.gameType),
            QEImport.GAME_TYPE
        )
    end

    local vault, skipped = {}, 0

    local items, order = {}, {}
    for _, raw in ipairs(arrayOf(topSet.items)) do
        local item = QEImport.Item(raw)
        if item then
            local existing = items[item.key]
            if existing then
                -- Two copies of the same item at the same upgrade level share a
                -- key (a matched pair of rings); the count keeps the pair
                -- visible instead of silently collapsing it to one.
                existing.count = existing.count + 1
            else
                items[item.key] = item
            end
            order[#order + 1] = item.key
            harvestVault(vault, items[item.key])
        else
            skipped = skipped + 1
        end
    end

    local alternatives = {}
    for _, raw in ipairs(arrayOf(decoded.differentials)) do
        if type(raw) == "table" then
            local altItems = {}
            for _, rawItem in ipairs(arrayOf(raw.items)) do
                local item = QEImport.Item(rawItem)
                if item then
                    altItems[#altItems + 1] = item
                    harvestVault(vault, item)
                else
                    skipped = skipped + 1
                end
            end
            alternatives[#alternatives + 1] = {
                scorePercent = tonumber(raw.scorePercent) or 0,
                hpsDifference = tonumber(raw.hpsDifference) or 0,
                items = altItems,
                gems = numbersOf(raw.gems),
            }
        end
    end

    local warnings = {}
    local character = ns.Safe(UnitName and UnitName("player"))
    local exportName = stringOrNil(player.name)
    if type(character) == "string" and exportName and character:lower() ~= exportName:lower() then
        warnings[#warnings + 1] = string.format("this export is for %s, and you are playing %s", exportName, character)
    end
    if #order == 0 then
        warnings[#warnings + 1] = "this export's topSet lists no items"
    end
    if skipped > 0 then
        warnings[#warnings + 1] = string.format("%d item(s) carried no usable itemID and were skipped", skipped)
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
        topSet = {
            score = tonumber(topSet.score) or 0,
            stats = type(topSet.stats) == "table" and topSet.stats or {},
            items = items,
            order = order,
        },
        alternatives = alternatives,
        vault = vault,
        skippedItems = skipped,
    }
    return { ok = true, verdict = verdict, warnings = warnings }
end

-- The content type an export is filed under. An export with no contentType
-- string still has to be storable, so it lands under "Unknown" rather than
-- being dropped or pretending to be one of QE Live's two.
function QEImport.ContentTypeKey(verdict)
    if type(verdict) ~= "table" then
        return QEImport.UNKNOWN_CONTENT_TYPE
    end
    return stringOrNil(verdict.contentType) or QEImport.UNKNOWN_CONTENT_TYPE
end

-- The last successful import lives in db.char.qeImport, keeping its exportedAt
-- so the UI can say how old the verdict is; importedAt records when it was
-- pasted. It is ALSO filed by content type in db.char.qeImports, because a
-- Dungeon export and a Raid export answer different questions and pasting one
-- must not lose the other (M2-2's content-type setting is what chooses between
-- them). SavedVariables flush on /reload or logout, not here.
function QEImport.Store(verdict)
    if type(verdict) ~= "table" then
        return { ok = false, reason = "no verdict to store" }
    end
    if not ns.db then
        return { ok = false, reason = "database not loaded yet" }
    end
    verdict.importedAt = time()
    ns.db.char.qeImport = verdict
    ns.db.char.qeImports = ns.db.char.qeImports or {}
    ns.db.char.qeImports[QEImport.ContentTypeKey(verdict)] = verdict
    return { ok = true, verdict = verdict }
end

function QEImport.Current()
    return ns.db and ns.db.char and ns.db.char.qeImport or nil
end

-- The stored verdict for one content type, or nil when nothing of that kind has
-- been pasted on this character.
function QEImport.ForContentType(contentType)
    if type(contentType) ~= "string" then
        return nil
    end
    local byType = ns.db and ns.db.char and ns.db.char.qeImports
    return byType and byType[contentType] or nil
end

-- Every content type this character has an import for, in QE Live's order with
-- anything unexpected appended.
function QEImport.StoredContentTypes()
    local byType = ns.db and ns.db.char and ns.db.char.qeImports or {}
    local out, seen = {}, {}
    for _, known in ipairs(QEImport.CONTENT_TYPES) do
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

-- Parse then store. The refusal from either step is returned unchanged, so the
-- editbox (M2-2) has one call and one message to show.
function QEImport.Import(text)
    local parsed = QEImport.Parse(text)
    if not parsed.ok then
        return parsed
    end
    local stored = QEImport.Store(parsed.verdict)
    if not stored.ok then
        return stored
    end
    return parsed
end
