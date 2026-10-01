-- Lootpath/Modules/EngineStats.lua (E-0b, WKE-671)
-- What the client says an item link carries: its primary and secondary
-- ratings, its sockets and the gems in them, its level, its set and its
-- uniqueness - READ, cached by link, returned. Nothing here computes a value;
-- E-0c (`ns.EngineScore`, behind `db.global.developer.engine`) is where a
-- number is made, and no UI file reads this module (spec/enginestats_spec.lua
-- holds that). The scoped exception is CLAUDE.md's and ARCHITECTURE.md section 7's
-- (2026-09-30, late night); section 1's rule governs every surface a player sees.
--
-- What it reads, and why the enchant is not among it:
--   * `C_Item.GetItemStats(link)` on the link with its enchant and gems
--     blanked (fields 2-6 of the item string), so the vector is the item's
--     own. Bonus IDs and crafted modifiers stay in the link (Core.lua
--     ParseItemLink's layout), so a crafted piece and a raid drop of the same
--     itemID are different keys.
--   * each gem through `C_Item.GetItemGem(link, i)` -> gem link ->
--     `C_Item.GetItemStats(gemLink)`, listed under `gems` and never folded
--     into the base vector: the scorer decides what a gem is worth. On 12.1.0
--     the client answers every gem link with an EMPTY table (all 7 socketed
--     gems in the 2026-10-01 transcript, E-0f), so an empty answer is read as
--     "stats unknown" (`unknown = true`, `stats = {}`), never as a gem worth
--     nothing.
--   * `C_Item.GetItemNumSockets` for the socket count, which is the one part
--     of a finish that moves a score at parity: QE Live scores every set with
--     an ASSUMED best finish per slot (fork `TopGearEngine.ts:565-634`), so
--     the enchant is not needed - and it is not readable by ID anyway (no API;
--     only the tooltip line of type 15 names it).
--   * `C_Item.GetDetailedItemLevelInfo` (level), `C_Item.GetItemInfo`'s
--     sixteenth return (setID), `C_Item.GetItemUniquenessByID` (uniqueness).
--   * the client's own rating conversion, `GetCombatRatingBonusForCombatRatingValue`,
--     and the five current ratings plus `GetMasteryEffect()`'s pair. No
--     diminishing-returns table of our own: the client applies them itself
--     (the 2026-10-01 transcript: haste 1320 -> 30.0, 2640 -> 54.0; E-0f).
--
-- Every value passes ns.Safe / ns.CopyRaw. A read that answers a secret makes
-- the result `{ secret = true, ready = true }` with no vector, never cached.
-- Nothing runs in combat: under InCombatLockdown() every entry point answers
-- nil and asks the client nothing. An item the client has not cached answers
-- `{ ready = false }` after one request through ns.ItemData.Watch; the caller
-- asks again once ITEM_DATA_LOAD_RESULT has fired.

local _, ns = ...

ns.EngineStats = {}
local EngineStats = ns.EngineStats

-- Every client function this file calls, named rather than discovered (the
-- ItemData / JournalAdapter pattern). RequestLoadItemDataByID is not here: the
-- request is ns.ItemData.Watch's, and ItemData names it.
EngineStats.FUNCTION_NAMES = {
    "InCombatLockdown",
    "C_Item.GetItemInfo",
    "C_Item.GetDetailedItemLevelInfo",
    "C_Item.GetItemStats",
    "C_Item.GetItemGem",
    "C_Item.GetItemNumSockets",
    "C_Item.GetItemUniquenessByID",
    "GetCombatRatingBonusForCombatRatingValue",
    "GetCombatRating",
    "GetMasteryEffect",
    -- The one frame that hears ITEM_DATA_LOAD_RESULT and PLAYER_ENTERING_WORLD.
    "CreateFrame",
}

-- The key-name map, READ from the owner's `capture itemstats` transcript
-- (spec/fixtures/captures/Lootpath-20261001-092631.lua, E-0f, WKE-676): every
-- key the client named on 80 items - 15 worn, 25 bag, 40 journal - with how
-- many of them carried it. Versatility has no `_SHORT`; the socket key is a
-- COUNT of prismatic sockets, filled or not (it equals GetItemNumSockets on
-- all 12 socketed items); `ITEM_MOD_MODIFIED_CRAFTING_STAT_1` is on the one
-- world trinket whose tooltip reads "+102 Random Stat 1". Avoidance is the
-- only key here the transcript did not show (no item carried it): it stays at
-- the wiki's name, grade (ii). A key not in this table is kept under
-- `other[key]`, never dropped.
EngineStats.STAT_KEYS = {
    ITEM_MOD_INTELLECT_SHORT = "int", -- 69 items
    ITEM_MOD_STAMINA_SHORT = "stamina", -- 61
    RESISTANCE0_NAME = "armor", -- 41
    ITEM_MOD_HASTE_RATING_SHORT = "haste", -- 39
    ITEM_MOD_CRIT_RATING_SHORT = "crit", -- 35
    ITEM_MOD_MASTERY_RATING_SHORT = "mastery", -- 28
    ITEM_MOD_VERSATILITY = "vers", -- 20, no _SHORT
    EMPTY_SOCKET_PRISMATIC = "prismaticSockets", -- 12, a count
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", -- 7, fractional
    ITEM_MOD_CR_LIFESTEAL_SHORT = "leech", -- 2
    ITEM_MOD_CR_SPEED_SHORT = "speed", -- 1
    ITEM_MOD_MODIFIED_CRAFTING_STAT_1 = "randomStat1", -- 1
    ITEM_MOD_CR_AVOIDANCE_SHORT = "avoidance", -- not seen; the wiki's name
}

-- The vector's fields, in one order, each 0 when the item carries none.
EngineStats.VECTOR = {
    "int",
    "stamina",
    "crit",
    "haste",
    "mastery",
    "vers",
    "leech",
    "avoidance",
    "speed",
    "armor",
    "prismaticSockets",
    "dps",
    "randomStat1",
}

-- The rating indices, read from Blizzard's own constants in
-- PaperDollFrame.lua (under .luals/, Blizzard_UIPanels_Game/Mainline:14, 17,
-- 20, 26, 29 of the annotated copy). Literal here because they are FrameXML
-- globals, not part of the exported API.
EngineStats.RATING_INDEX = {
    crit = 11, -- CR_CRIT_SPELL
    leech = 17, -- CR_LIFESTEAL
    haste = 20, -- CR_HASTE_SPELL
    mastery = 26, -- CR_MASTERY
    vers = 29, -- CR_VERSATILITY_DAMAGE_DONE
}

-- "A few thousand" entries, oldest out first. A bag, a bank, the vault and a
-- whole journal walk at one difficulty stay well under it.
EngineStats.MAX_ENTRIES = 2000

EngineStats.EVENTS = { "ITEM_DATA_LOAD_RESULT", "PLAYER_ENTERING_WORLD" }

-- [key] = result; byItem[itemID] = { [key] = true };
-- gems[gemID] = { stats = <vector or {}>, unknown = true | nil }.
local cache, byItem, gemCache = {}, {}, {}
local order, orderHead, count, seq = {}, 1, 0, 0
local listener

local function inCombat()
    return InCombatLockdown() and true or false
end

-- Blanks fields 2-6 (enchant, four gems) of the item string inside `link`.
-- Answers the stripped link (the client's own form, name and colour kept), the
-- cache key (`item:` plus the stripped body), the itemID, and the four gem
-- fields positionally.
local function strip(link)
    local body = link:match("|Hitem:([^|]+)|h") or link:match("^item:([^|]+)$")
    if not body then
        return nil
    end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local itemID = tonumber(fields[1])
    if not itemID or itemID <= 0 then
        return nil
    end
    local gems = {}
    for i = 3, 6 do
        gems[i - 2] = tonumber(fields[i]) or 0
    end
    for i = 2, 6 do
        if fields[i] ~= nil then
            fields[i] = ""
        end
    end
    local stripped = table.concat(fields, ":")
    local strippedLink
    if link:match("^item:") then
        strippedLink = "item:" .. stripped
    else
        -- Plain find/replace: the body is literal text, never a pattern.
        local s, e = link:find("|Hitem:" .. body .. "|h", 1, true)
        strippedLink = link:sub(1, s - 1) .. "|Hitem:" .. stripped .. "|h" .. link:sub(e + 1)
    end
    return strippedLink, "item:" .. stripped, itemID, gems
end

-- A table the client handed over, through ns.CopyRaw, into a vector: every
-- mapped key into its field, every other key into `other`. Answers nil and
-- true for a secret anywhere in it; the third return is true when the table
-- held no key at all, so a caller can tell "the client named nothing" from zeros.
local function toVector(raw)
    local copy, secret = ns.CopyRaw(raw)
    if secret then
        return nil, true
    end
    if type(copy) ~= "table" then
        return nil, false
    end
    local vector = {}
    for _, field in ipairs(EngineStats.VECTOR) do
        vector[field] = 0
    end
    for key, value in pairs(copy) do
        local field = EngineStats.STAT_KEYS[key]
        if field and type(value) == "number" then
            vector[field] = value
        else
            vector.other = vector.other or {}
            vector.other[key] = value
        end
    end
    return vector, false, next(copy) == nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, ...)
end

-- One guarded scalar read: (value, secret).
local function scalar(ok, value)
    if not ok then
        return nil, false
    end
    local safe, secret = ns.Safe(value)
    if secret then
        return nil, true
    end
    return safe, false
end

local function forget(key)
    local entry = cache[key]
    if not entry then
        return
    end
    cache[key] = nil
    count = count - 1
    local keys = byItem[entry.itemID]
    if keys then
        keys[key] = nil
        if next(keys) == nil then
            byItem[entry.itemID] = nil
        end
    end
end

function EngineStats.Invalidate(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return
    end
    local keys = byItem[itemID]
    if keys then
        local list = {}
        for key in pairs(keys) do
            list[#list + 1] = key
        end
        for _, key in ipairs(list) do
            forget(key)
        end
    end
    gemCache[itemID] = nil
end

function EngineStats.Reset()
    cache, byItem, gemCache = {}, {}, {}
    order, orderHead, count, seq = {}, 1, 0, 0
end

function EngineStats.Count()
    return count
end

local function ensureListener()
    if listener then
        return
    end
    listener = CreateFrame("Frame")
    for _, event in ipairs(EngineStats.EVENTS) do
        listener:RegisterEvent(event)
    end
    listener:SetScript("OnEvent", function(_, event, itemID)
        if event == "PLAYER_ENTERING_WORLD" then
            EngineStats.Reset()
        else
            EngineStats.Invalidate((ns.Safe(itemID)))
        end
    end)
end

local function store(key, entry)
    ensureListener()
    seq = seq + 1
    entry._seq = seq
    cache[key] = entry
    count = count + 1
    byItem[entry.itemID] = byItem[entry.itemID] or {}
    byItem[entry.itemID][key] = true
    order[#order + 1] = { key = key, seq = seq }
    while count > EngineStats.MAX_ENTRIES and orderHead <= #order do
        local oldest = order[orderHead]
        order[orderHead] = nil
        orderHead = orderHead + 1
        local held = cache[oldest.key]
        if held and held._seq == oldest.seq then
            forget(oldest.key)
        end
    end
    -- Compacted when the spent head outgrows what is still held.
    if orderHead > EngineStats.MAX_ENTRIES then
        local kept = {}
        for i = orderHead, #order do
            local o = order[i]
            local held = cache[o.key]
            if held and held._seq == o.seq then
                kept[#kept + 1] = o
            end
        end
        order, orderHead = kept, 1
    end
end

-- One request per item, through the existing loader; the episode is over when
-- the client can name the item.
local function request(itemID)
    if ns.ItemData and ns.ItemData.Watch then
        ns.ItemData.Watch(itemID, function(id)
            return ns.ItemData.IsCached(id)
        end)
    end
end

-- The stats of the gem in socket `index` of `link`, cached by gem ID.
-- Answers (entry, secret, pending), entry = { stats, unknown }. An empty table
-- from the client is `unknown`: on 12.1.0 every gem link answers one (E-0f),
-- and a gem the client says nothing about is not a gem worth nothing.
local function gemVector(link, index, gemID)
    if gemCache[gemID] then
        return gemCache[gemID], false, false
    end
    local ok, _, gemLink = call(C_Item.GetItemGem, link, index)
    local safeLink, secret = scalar(ok, gemLink)
    if secret then
        return nil, true, false
    end
    if type(safeLink) ~= "string" or safeLink == "" then
        request(gemID)
        return nil, false, true
    end
    local okStats, raw = call(C_Item.GetItemStats, safeLink)
    if not okStats or raw == nil then
        request(gemID)
        return nil, false, true
    end
    local vector, statsSecret, empty = toVector(raw)
    if statsSecret then
        return nil, true, false
    end
    if not vector then
        return nil, false, true
    end
    local entry = empty and { stats = {}, unknown = true } or { stats = vector }
    gemCache[gemID] = entry
    return entry, false, false
end

-- A fresh table each time: a caller that writes on one never changes another's.
local function secretResult()
    return { secret = true, ready = true }
end

-- ForLink(link) -> the item's read, or nil.
--
-- `{ itemID, key, int, stamina, crit, haste, mastery, vers, leech, avoidance,
--    speed, armor, prismaticSockets, dps, randomStat1,
--    other = { [key] = value } | nil, sockets,
--    gems = { { id, stats = <vector>, unknown = true | nil }, ... }, level, setID,
--    uniqueness = { category, max, name, isUnique } | nil, ready = true }`
-- `{ ready = false }` while the client fetches the item or a gem (one
-- request made); `{ secret = true, ready = true }` when any read was secret;
-- nil in combat, or for anything that is not an item link. The table
-- answered is the cached one: read it, never change it.
function EngineStats.ForLink(link)
    if inCombat() then
        return nil
    end
    local safeLink, linkSecret = ns.Safe(link)
    if linkSecret then
        return secretResult()
    end
    if type(safeLink) ~= "string" or safeLink == "" then
        return nil
    end
    local strippedLink, key, itemID, gemIDs = strip(safeLink)
    if not strippedLink or not gemIDs then
        return nil
    end

    local entry = cache[key]
    if not entry then
        -- GetItemInfo: the client's own "loaded yet" gate (a name), and the
        -- sixteenth return is setID (ItemDocumentation under .luals/).
        local okInfo, name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID = call(C_Item.GetItemInfo, strippedLink)
        local safeName, nameSecret = scalar(okInfo, name)
        if nameSecret then
            return secretResult()
        end
        if type(safeName) ~= "string" or safeName == "" then
            request(itemID)
            return { ready = false }
        end
        local okStats, raw = call(C_Item.GetItemStats, strippedLink)
        if not okStats or raw == nil then
            request(itemID)
            return { ready = false }
        end
        local vector, statsSecret = toVector(raw)
        if statsSecret then
            return secretResult()
        end
        if not vector then
            return nil
        end
        local anySecret = false
        local function read(ok, value)
            local v, s = scalar(ok, value)
            anySecret = anySecret or s
            return v
        end
        vector.itemID = itemID
        vector.key = key
        vector.setID = tonumber(read(okInfo, setID))
        vector.sockets = tonumber(read(call(C_Item.GetItemNumSockets, strippedLink))) or 0
        vector.level = tonumber(read(call(C_Item.GetDetailedItemLevelInfo, strippedLink)))
        local okUnique, isUnique, categoryName, categoryCount, categoryID = call(C_Item.GetItemUniquenessByID, itemID)
        isUnique = read(okUnique, isUnique)
        categoryName = read(okUnique, categoryName)
        categoryCount = tonumber(read(okUnique, categoryCount))
        categoryID = tonumber(read(okUnique, categoryID))
        if anySecret then
            return secretResult()
        end
        if isUnique or categoryID or categoryCount then
            vector.uniqueness = {
                category = categoryID,
                max = categoryCount,
                name = categoryName,
                isUnique = isUnique == true,
            }
        end
        entry = vector
        store(key, entry)
    end

    -- The gems ride on the link, not on the key: two copies of one item with
    -- different gems share the base read and differ here.
    local gems = {}
    for index, gemID in ipairs(gemIDs) do
        if gemID > 0 then
            local gem, secret, pending = gemVector(safeLink, index, gemID)
            if secret then
                return secretResult()
            end
            if pending or not gem then
                return { ready = false }
            end
            gems[#gems + 1] = { id = gemID, stats = gem.stats, unknown = gem.unknown }
        end
    end

    local result = {}
    for k, v in pairs(entry) do
        if k ~= "_seq" then
            result[k] = v
        end
    end
    result.gems = gems
    result.ready = true
    return result
end

-- ---------------------------------------------------------------------------
-- A link at a level (E-0g, WKE-677).
--
-- The journal walk keeps each drop's link and the level the Adventure Guide
-- PREVIEWED while it read it; the link does not carry that preview. Read later,
-- `GetDetailedItemLevelInfo` and `GetItemStats` answer at the link's OWN level:
-- 17 of the 40 journal rows of the 2026-10-01 transcript (7 keystone rows
-- listed at 305 read 292, 6 raid rows read the difficulty's base level, 4 world
-- rows listed at 44 read 263 / 276; ARCHITECTURE.md section 7, E-0f point 5).
-- So a row is scored at its level only through a link REBUILT for that level,
-- and this is the one place one is made: `RebuildLink` is the only function in
-- the addon that writes a bonus-ID list into a link, `LinkAtLevel` the only one
-- that decides which list, and it decides by a RULE handed in or installed in
-- `EngineStats.linkLevelRule`.
--
-- No rule is installed. Which rule makes the client draw the previewed level
-- is what `/lootpath capture linklevel` asks it (Captures.lua); until that
-- transcript is committed, every ask answers nil and NO_RULE, and nothing is
-- ever scored at a level a link was not proven to draw.
--
-- A rule is `rule(link, level, parsed) -> bonusIDs | nil, reason`: given the
-- link, the level wanted and the link's own fields (`LinkFields`), the list of
-- bonus IDs the rebuilt link carries, in order. It never builds a string.

EngineStats.NO_RULE = "no rule yet"
EngineStats.linkLevelRule = nil

-- The item string's fields, raw and in order, or nil: the same layout as
-- Core.lua's ParseItemLink - numBonusIDs at field 13, the IDs after it, then
-- the modifiers - but the bonus IDs UNSORTED, because a rebuilt link must keep
-- every other field exactly where the client put it.
local function itemFields(link)
    if type(link) ~= "string" then
        return nil
    end
    local body = link:match("|Hitem:([^|]+)|h") or link:match("^item:([^|]+)$")
    if not body then
        return nil
    end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local itemID = tonumber(fields[1])
    if not itemID or itemID <= 0 then
        return nil
    end
    return fields, body, itemID
end

-- LinkFields(link) -> `{ itemID, context, bonusIDs = { <raw order> } }` or nil.
-- A parse of the string in hand; asks the client nothing.
function EngineStats.LinkFields(link)
    local fields, _, itemID = itemFields(link)
    if not fields then
        return nil
    end
    local numBonus = tonumber(fields[13]) or 0
    local bonusIDs = {}
    for i = 1, numBonus do
        local id = tonumber(fields[13 + i])
        if not id then
            return nil
        end
        bonusIDs[i] = id
    end
    return { itemID = itemID, context = tonumber(fields[12]), bonusIDs = bonusIDs }
end

-- RebuildLink(link, bonusIDs) -> the same link with its bonus-ID list replaced
-- by `bonusIDs` and nothing else touched (the colour, the name, the context,
-- the modifiers after the list), or nil for anything that is not an item link
-- or a list that is not all whole positive numbers.
function EngineStats.RebuildLink(link, bonusIDs)
    local fields, body = itemFields(link)
    if not fields or type(bonusIDs) ~= "table" then
        return nil
    end
    for _, id in ipairs(bonusIDs) do
        if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
            return nil
        end
    end
    local numBonus = tonumber(fields[13]) or 0
    local out = {}
    for i = 1, 12 do
        out[i] = fields[i] or ""
    end
    out[13] = #bonusIDs > 0 and tostring(#bonusIDs) or ""
    for _, id in ipairs(bonusIDs) do
        out[#out + 1] = tostring(id)
    end
    for i = 13 + numBonus + 1, #fields do
        out[#out + 1] = fields[i]
    end
    local rebuilt = table.concat(out, ":")
    if link:match("^item:") then
        return "item:" .. rebuilt
    end
    -- Plain find/replace: the body is literal text, never a pattern.
    local s, e = link:find("|Hitem:" .. body .. "|h", 1, true)
    return link:sub(1, s - 1) .. "|Hitem:" .. rebuilt .. "|h" .. link:sub(e + 1)
end

-- TrackBonusesAt(level) -> every step of Data/TrackBonusIDs.lua that draws
-- `level`, as `{ bonusID, track, step, itemLevel, client }`, in the file's
-- track order. Two tracks overlap at most levels (305 is Champion 5/6 and
-- Hero 1/6), so the answer is a list; an empty one when no step draws it.
function EngineStats.TrackBonusesAt(level)
    local out = {}
    local data = ns.trackBonusIDs
    level = tonumber(level)
    if type(data) ~= "table" or type(data.tracks) ~= "table" or not level then
        return out
    end
    for _, track in ipairs(data.tracks) do
        for step, entry in ipairs(track.steps or {}) do
            if entry.itemLevel == level then
                out[#out + 1] = {
                    bonusID = entry.bonusID,
                    track = track.name,
                    step = step,
                    itemLevel = entry.itemLevel,
                    client = entry.client == true,
                }
            end
        end
    end
    return out
end

-- LinkAtLevel(link, level, rule) -> the link rebuilt for `level` | nil, why.
-- `rule` defaults to EngineStats.linkLevelRule; with neither, NO_RULE.
function EngineStats.LinkAtLevel(link, level, rule)
    rule = rule or EngineStats.linkLevelRule
    if type(rule) ~= "function" then
        return nil, EngineStats.NO_RULE
    end
    level = tonumber(level)
    local parsed = EngineStats.LinkFields(link)
    if not parsed or not level then
        return nil, "not an item link at a level"
    end
    local ok, bonusIDs, why = pcall(rule, link, level, parsed)
    if not ok then
        return nil, "the rule failed"
    end
    if type(bonusIDs) ~= "table" then
        return nil, why or ("no rule for " .. level)
    end
    local rebuilt = EngineStats.RebuildLink(link, bonusIDs)
    if not rebuilt then
        return nil, "the rule's bonus IDs are not a list"
    end
    return rebuilt
end

-- AtLevel(read, level) -> read | nil, why: a ready read is kept only when the
-- client drew it at `level`. A rebuilt link the client draws at another level
-- is never scored as if it were the row's.
function EngineStats.AtLevel(read, level)
    if type(read) ~= "table" or read.ready ~= true or read.secret then
        return nil, "not ready"
    end
    if read.level ~= tonumber(level) then
        return nil, string.format("read at %s, not %s", tostring(read.level), tostring(level))
    end
    return read
end

-- ForLinkAtLevel(link, level, rule) -> read, rebuiltLink | nil, why.
-- LinkAtLevel, then ForLink on the rebuilt link, then AtLevel. `{ ready =
-- false }` and the rebuilt link while the client fetches it; nil in combat,
-- like ForLink.
function EngineStats.ForLinkAtLevel(link, level, rule)
    if inCombat() then
        return nil
    end
    local rebuilt, why = EngineStats.LinkAtLevel(link, level, rule)
    if not rebuilt then
        return nil, why
    end
    local read = EngineStats.ForLink(rebuilt)
    if type(read) == "table" and read.ready == false then
        return read, rebuilt
    end
    local kept, notAt = EngineStats.AtLevel(read, level)
    if not kept then
        return nil, notAt
    end
    return kept, rebuilt
end

-- Rating(index, value) -> the client's percent for `value` rating of rating
-- `index`, or nil (in combat, no answer, or secret - then the second return
-- is true).
function EngineStats.Rating(index, value)
    if inCombat() then
        return nil
    end
    local v, secret = scalar(call(GetCombatRatingBonusForCombatRatingValue, index, value))
    if secret then
        return nil, true
    end
    return tonumber(v), false
end

-- CurrentRatings() -> `{ crit, haste, mastery, vers, leech, masteryEffect,
-- masteryCoefficient }` as the client says them now, or nil in combat;
-- `{ secret = true }` when any of them is secret.
function EngineStats.CurrentRatings()
    if inCombat() then
        return nil
    end
    local out, anySecret = {}, false
    for field, index in pairs(EngineStats.RATING_INDEX) do
        local v, secret = scalar(call(GetCombatRating, index))
        anySecret = anySecret or secret
        out[field] = tonumber(v)
    end
    local ok, effect, coefficient = call(GetMasteryEffect)
    local e, s1 = scalar(ok, effect)
    local c, s2 = scalar(ok, coefficient)
    if anySecret or s1 or s2 then
        return { secret = true }
    end
    out.masteryEffect = tonumber(e)
    out.masteryCoefficient = tonumber(c)
    return out
end
