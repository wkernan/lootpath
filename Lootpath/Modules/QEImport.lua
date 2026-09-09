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

-- The named what-if scenarios (C-6, WKE-540; decision 2026-09-08). A vault
-- option is not the item as it is offered: put the 308 Scavenger's Spaulders
-- through the Catalyst and they are tier shoulders at 308, and upgrade tracks
-- move the level the same way. QE Live models both through his import dialog's
-- three checkboxes, so Lootpath models neither: the companion asks him each
-- question by name and this module files each answer by name.
--
-- The strings are the companion's verbatim (`tools/companion/lib/config.js`,
-- `SCENARIOS`), because they are what lands in Data/QEVerdict.lua.
QEImport.SCENARIOS = { "asOffered", "catalyzed", "maxed" }

-- What a document that names no scenario is. Everything written before C-6 -
-- the committed placeholder, every paste, the two exports of 2026-09-07 - says
-- nothing, and every one of them IS the character as it stands; treating a
-- silent document as anything else would change what Equip Now means.
QEImport.DEFAULT_SCENARIO = "asOffered"

-- A scenario string this build does not know. It is given a shelf of its own
-- rather than being read as the default, because a name nobody here recognises
-- is not evidence that the answer is the one Equip Now reads.
QEImport.UNKNOWN_SCENARIO = "unknown"

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

-- How far from the top set an alternative sits, in QE Live's own direction:
-- lower is better, because a positive scorePercent means the alternative is
-- worse. Sorting on this is reading his sign convention through the constant
-- rather than re-deciding it, which is the whole point of the constant.
function QEImport.AlternativeRank(alternative)
    local percent = type(alternative) == "table" and tonumber(alternative.scorePercent) or nil
    if not percent then
        return math.huge
    end
    return percent * QEImport.ALT_WORSE_SCORE_PERCENT_SIGN
end

-- Coverage(verdict, key) -> what QE Live has said about this exact item, or
-- nil when it has said nothing. The one lookup both M3-3 panels use, so
-- "covered" means the same thing on the Upgrade Map and in the Vault:
--
--   { key, item, where = "topSet"|"alternative", isVault,
--     scorePercent, hpsDifference, isBetter }
--
-- `where = "topSet"` carries NO numbers, and that is not an omission: the
-- export gives per-item deltas only on its differentials, and inventing one for
-- a top-set item would be Lootpath computing a healer value. The panels say
-- "QE Live put this in your best set" there and show a number nowhere else.
--
-- An item that appears in several alternatives is reported through the best of
-- them, ordered by AlternativeRank.
function QEImport.Coverage(verdict, key)
    if type(verdict) ~= "table" or type(key) ~= "string" then
        return nil
    end
    local topSet = type(verdict.topSet) == "table" and verdict.topSet or {}
    local inTopSet = type(topSet.items) == "table" and topSet.items[key] or nil
    if inTopSet then
        return {
            key = key,
            item = inTopSet,
            where = "topSet",
            isVault = inTopSet.isVault == true,
        }
    end
    local best, bestItem
    for _, alternative in ipairs(verdict.alternatives or {}) do
        for _, item in ipairs(alternative.items or {}) do
            if item.key == key then
                if not best or QEImport.AlternativeRank(alternative) < QEImport.AlternativeRank(best) then
                    best, bestItem = alternative, item
                end
            end
        end
    end
    if not best then
        return nil
    end
    return {
        key = key,
        item = bestItem,
        where = "alternative",
        isVault = bestItem.isVault == true,
        scorePercent = best.scorePercent,
        hpsDifference = best.hpsDifference,
        isBetter = QEImport.AlternativeIsBetter(best),
    }
end

-- QE Live's own catalyzed copy of a vault option, when his `catalyzed` or
-- `maxed` run made one (C-6, WKE-540).
--
-- `autoCatalyze` does not change an item: `SimCImportEngine.ts` keeps the
-- original in the listing and ADDS a clone, and `Item.convertToTier` gives that
-- clone the tier piece's item ID and set ID while keeping everything else the
-- original had - the same slot, the same level, the same bonus IDs, the same
-- `vaultItem` flag. So the catalyzed form of a vault option is a DIFFERENT item
-- ID and the exact-key join can never find it, and a Vault tab that only ever
-- joined on the key would answer "if I catalyze these shoulders" with what QE
-- Live said about the shoulders he did not catalyze. Measured 2026-09-08: the
-- vault's 251146 becomes 271526 and enters the top set, while 251146 itself sits
-- in an alternative.
--
-- This is a JOIN, not a model of the Catalyst. Nothing here knows which items
-- can be catalyzed, what a tier piece is, or what the conversion costs: it
-- recognises the copy QE Live himself put in the export, by the fields he
-- copied. When his run made no copy - because his own `canBeCatalyzed()` said no
-- - there is nothing to find and the caller is told that in those words.
local function sameBonusIDs(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
        return false
    end
    for index = 1, #a do
        if a[index] ~= b[index] then
            return false
        end
    end
    -- An item with no bonus IDs at all is not identified by them: two different
    -- plain items would match each other. The vault's own links always carry
    -- some, so this costs nothing real and closes the hole.
    return #a > 0
end

-- Every item the export mentions, top set first and then alternatives ordered by
-- QE Live's own rank, so the first match found is the best thing he said.
local function eachItem(verdict, visit)
    local topSet = type(verdict) == "table" and type(verdict.topSet) == "table" and verdict.topSet or {}
    local items = type(topSet.items) == "table" and topSet.items or {}
    for _, key in ipairs(topSet.order or {}) do
        local item = items[key]
        if item and visit(item, "topSet", nil) then
            return true
        end
    end
    local ranked = {}
    for _, alternative in ipairs(verdict.alternatives or {}) do
        ranked[#ranked + 1] = alternative
    end
    table.sort(ranked, function(left, right)
        return QEImport.AlternativeRank(left) < QEImport.AlternativeRank(right)
    end)
    for _, alternative in ipairs(ranked) do
        for _, item in ipairs(alternative.items or {}) do
            if visit(item, "alternative", alternative) then
                return true
            end
        end
    end
    return false
end

-- CatalyzedCoverage(verdict, option) -> coverage in Coverage's own shape, plus
-- `catalyzedFrom` (the option's own itemID) and `item` (his clone), or nil.
-- `option` is `{ itemID, slot, bonusIDs }` - what the vault reward carries.
function QEImport.CatalyzedCoverage(verdict, option)
    if type(verdict) ~= "table" or type(option) ~= "table" then
        return nil
    end
    local itemID, slot = tonumber(option.itemID), option.slot
    if not itemID or type(slot) ~= "string" then
        return nil
    end
    local found
    eachItem(verdict, function(item, where, alternative)
        if
            item.isVault == true
            and item.slot == slot
            and item.itemID ~= itemID
            and sameBonusIDs(item.bonusIDs, option.bonusIDs)
        then
            found = {
                key = item.key,
                item = item,
                where = where,
                isVault = true,
                catalyzedFrom = itemID,
                scorePercent = alternative and alternative.scorePercent or nil,
                hpsDifference = alternative and alternative.hpsDifference or nil,
            }
            -- Assigned on its own line, not through `and ... or nil`: a
            -- perfectly good `false` collapses to nil in that idiom, and this
            -- field is the direction word on screen.
            if alternative then
                found.isBetter = QEImport.AlternativeIsBetter(alternative)
            end
            return true
        end
        return false
    end)
    return found
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
-- Which named scenario a verdict answers (C-6, WKE-540). A verdict that does not
-- say is `asOffered`, so every paste and every file written before C-6 keeps
-- meaning exactly what it meant. A verdict that names something this build does
-- not know is filed as unknown rather than read as the default.
function QEImport.ScenarioKey(verdict)
    local scenario = type(verdict) == "table" and verdict.scenario or nil
    if scenario == nil then
        return QEImport.DEFAULT_SCENARIO
    end
    if type(scenario) ~= "string" then
        return QEImport.UNKNOWN_SCENARIO
    end
    for _, name in ipairs(QEImport.SCENARIOS) do
        if name == scenario then
            return name
        end
    end
    return QEImport.UNKNOWN_SCENARIO
end

function QEImport.Store(verdict)
    if type(verdict) ~= "table" then
        return { ok = false, reason = "no verdict to store" }
    end
    if not ns.db then
        return { ok = false, reason = "database not loaded yet" }
    end
    verdict.importedAt = time()
    local contentType = QEImport.ContentTypeKey(verdict)
    local scenario = QEImport.ScenarioKey(verdict)
    ns.db.char.qeImportsByScenario = ns.db.char.qeImportsByScenario or {}
    local byScenario = ns.db.char.qeImportsByScenario
    byScenario[contentType] = byScenario[contentType] or {}
    byScenario[contentType][scenario] = verdict
    -- `qeImport` and `qeImports` are the `asOffered` shelves and nothing else.
    -- Equip Now, the Upgrade Map and every fallback in the window read them, and
    -- WKE-540's second deliverable is that those two tabs NEVER change meaning:
    -- a `catalyzed` answer landing here would tell the owner to equip an item
    -- the Catalyst has not been used on yet.
    if scenario == QEImport.DEFAULT_SCENARIO then
        ns.db.char.qeImport = verdict
        ns.db.char.qeImports = ns.db.char.qeImports or {}
        ns.db.char.qeImports[contentType] = verdict
    end
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

-- The stored verdict this one would replace. For a Top Gear import that is
-- simply the one for the same content type; ns.UFImport answers the same
-- question in its own terms, because since C-7 an Upgrade Finder verdict is
-- identified by content type AND Mythic+ key level. ns.Companion asks whichever
-- importer owns the schema, so it never reaches into either shape itself.
function QEImport.Existing(verdict)
    local contentType = QEImport.ContentTypeKey(verdict)
    local scenario = QEImport.ScenarioKey(verdict)
    local stored = QEImport.ForContentTypeAndScenario(contentType, scenario)
    if stored then
        return stored
    end
    -- Nothing on the scenario shelf yet. An `asOffered` import still replaces
    -- whatever a pre-C-6 build filed under the content type alone, so the first
    -- companion file after an upgrade is not read as a repeat of itself.
    if scenario == QEImport.DEFAULT_SCENARIO then
        return QEImport.ForContentType(contentType)
    end
    return nil
end

-- The stored verdict for one content type under one named scenario.
function QEImport.ForContentTypeAndScenario(contentType, scenario)
    if type(contentType) ~= "string" or type(scenario) ~= "string" then
        return nil
    end
    local byScenario = ns.db and ns.db.char and ns.db.char.qeImportsByScenario
    local shelf = byScenario and byScenario[contentType]
    return shelf and shelf[scenario] or nil
end

-- Every stored answer for one content type, in the order the scenarios are
-- asked, with any name this build does not know appended. This is the ONE place
-- the scenario shelf is read, so the Vault panel is pure over what it is handed.
--
-- A character with nothing on the shelf but a pre-C-6 import for that content
-- type gets that import back as `asOffered`, which is what it is: a document
-- that named no scenario.
function QEImport.Scenarios(contentType)
    if type(contentType) ~= "string" then
        return {}
    end
    local byScenario = ns.db and ns.db.char and ns.db.char.qeImportsByScenario
    local shelf = (byScenario and byScenario[contentType]) or {}
    local out, seen = {}, {}
    for _, name in ipairs(QEImport.SCENARIOS) do
        if shelf[name] then
            out[#out + 1] = { verdict = shelf[name], scenario = name }
            seen[name] = true
        end
    end
    local extra = {}
    for name in pairs(shelf) do
        if not seen[name] then
            extra[#extra + 1] = name
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        out[#out + 1] = { verdict = shelf[name], scenario = name }
    end
    if #out == 0 then
        local legacy = QEImport.ForContentType(contentType)
        if legacy then
            out[#out + 1] = { verdict = legacy, scenario = QEImport.ScenarioKey(legacy) }
        end
    end
    return out
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
