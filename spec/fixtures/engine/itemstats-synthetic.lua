-- spec/fixtures/engine/itemstats-synthetic.lua (E-0d, WKE-673)
--
-- SYNTHETIC NUMBERS, REAL SHAPE. No number here was read from a client. The
-- compare's fixture run is the owner's 2026-09-16 SavedVariables (its walk,
-- documents and dressed inventory), and the one transcript of what the client
-- answers for item stats (spec/fixtures/captures/Lootpath-20261001-092631.lua,
-- extracted to itemstats-real.lua) reads 80 links of 2026-10-01, not that
-- day's - so the run answers C_Item.GetItemStats for every link it asks about
-- from a rule: Intellect and two secondaries that grow with the item level the
-- client itself listed for the link (the journal row's `itemLevel`, the
-- inventory record's `itemLevel`), the pair of secondaries chosen by the
-- itemID. The KEYS are the client's (E-0f confirmed every one used here), a gem
-- link answers the empty table every gem link answered on 2026-10-01, and the
-- rating conversion is the stub's, which applies diminishing returns as the
-- client does.
--
-- It exists so the compare's joins, metrics, store and print run end to end
-- over the owner's real walk, documents and inventory; the figures it yields
-- measure the plumbing, never an engine.

local F = {}

local SECONDARIES = {
    "ITEM_MOD_CRIT_RATING_SHORT",
    "ITEM_MOD_HASTE_RATING_SHORT",
    "ITEM_MOD_MASTERY_RATING_SHORT",
    "ITEM_MOD_VERSATILITY",
}

-- The link with fields 2-6 (enchant, four gems) blanked: what EngineStats
-- asks the client about (Lootpath/Modules/EngineStats.lua `strip`).
function F.strip(link)
    local body = link:match("|Hitem:([^|]+)|h")
    if not body then
        return nil
    end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    for i = 2, 6 do
        if fields[i] ~= nil then
            fields[i] = ""
        end
    end
    local s, e = link:find("|Hitem:" .. body .. "|h", 1, true)
    return link:sub(1, s - 1) .. "|Hitem:" .. table.concat(fields, ":") .. "|h" .. link:sub(e + 1)
end

-- SYNTHETIC stats for one item at one level.
function F.stats(itemID, level)
    local first = SECONDARIES[itemID % 4 + 1]
    local second = SECONDARIES[(math.floor(itemID / 4) + 1) % 4 + 1]
    if second == first then
        second = SECONDARIES[(itemID + 1) % 4 + 1]
    end
    local budget = level * 3
    return {
        ITEM_MOD_INTELLECT_SHORT = level * 2 + itemID % 17,
        ITEM_MOD_STAMINA_SHORT = level * 5,
        [first] = math.floor(budget * 0.6),
        [second] = math.floor(budget * 0.4),
    }
end

-- The gems a link carries (fields 3-6), each answered by GetItemGem as a
-- SYNTHETIC gem link; GetItemStats answers that link with the empty table the
-- client gives every gem link. The compare scores in the parity mode, which
-- ignores the item's own gems, but EngineStats reads them all the same.
function F.installGems(world, link)
    local body = link:match("|Hitem:([^|]+)|h")
    if not body then
        return
    end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local gems = {}
    for i = 3, 6 do
        local gemID = tonumber(fields[i])
        if gemID and gemID > 0 then
            local gemLink = "|cff0070dd|Hitem:" .. gemID .. "::::::::90:105:::::|h[Synthetic Gem]|h|r"
            gems[i - 2] = { name = "Synthetic Gem", link = gemLink, id = gemID }
        end
    end
    if next(gems) then
        world.itemGems[link] = gems
    end
end

-- Registers `{ link, level }` entries on a stub world: the stripped link
-- loaded (a name, and GetItemInfo's setID kept when the replay already holds
-- the client's info), its level, its stats.
function F.install(world, entries)
    for _, entry in ipairs(entries) do
        local stripped = F.strip(entry.link)
        local itemID = tonumber(entry.link:match("item:(%d+)"))
        if stripped and itemID and entry.level then
            local held = world.items[stripped] or {}
            if not held.info then
                local name = entry.link:match("|h%[(.-)%]|h") or ("item " .. itemID)
                held.info = { name, stripped, 4, entry.level, n = 18 }
            end
            held.level = held.level or entry.level
            world.items[stripped] = held
            world.itemStats[stripped] = F.stats(itemID, entry.level)
            F.installGems(world, entry.link)
        end
    end
end

return F
