-- spec/fixtures/engine/itemstats-synthetic.lua (E-0d, WKE-673)
--
-- SYNTHETIC. No number here was read from a client. E-0a's `capture
-- itemstats` transcript (WKE-675) is not committed, so the compare's fixture
-- run answers C_Item.GetItemStats for every link it asks about from a rule:
-- Intellect and two secondaries that grow with the item level the client
-- itself listed for the link (the journal row's `itemLevel`, the inventory
-- record's `itemLevel`), the pair of secondaries chosen by the itemID. The KEYS
-- are E-0b's placeholder map (the wiki's, spec/fixtures/engine/
-- itemstats-placeholder.lua), so this file goes when E-0a's transcript lands.
--
-- It exists so the compare's joins, metrics, store and print run end to end
-- over the owner's real walk, documents and inventory; the figures it yields
-- measure the plumbing, never an engine.

local F = {}

-- Rating per 1% at level 90, no diminishing returns (the stub's own
-- GetCombatRatingBonusForCombatRatingValue is a straight division). SYNTHETIC:
-- the same first-bracket numbers the shipped placeholder's `dr` table carries.
F.RATING_PER_PERCENT = { [11] = 46, [17] = 69, [20] = 44, [26] = 46, [29] = 54 }

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
-- SYNTHETIC gem link with one stat. The compare scores in the parity mode,
-- which ignores the item's own gems, but EngineStats reads them all the same.
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
            gems[i - 2] = { "Synthetic Gem", gemLink }
            world.itemStats[gemLink] = { ITEM_MOD_HASTE_RATING_SHORT = 50 }
        end
    end
    if next(gems) then
        world.itemGems[link] = gems
    end
end

-- Registers `{ link, level }` entries on a stub world: the stripped link
-- loaded (a name, and GetItemInfo's setID kept when the replay already holds
-- the client's info), its level, its stats; and the rating conversion.
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
    for index, per in pairs(F.RATING_PER_PERCENT) do
        world.ratingPerPercent[index] = per
    end
end

return F
