-- spec/fixtures/engine/itemstats-placeholder.lua (E-0b, WKE-671)
--
-- PLACEHOLDER. Every number and every key in this file is invented in the
-- SHAPE the Warcraft Wiki gives for C_Item.GetItemStats (grade (ii)): a table
-- keyed by global-string stat names. None of it was read from a client.
-- E-0a's `capture itemstats` transcript (WKE-675) is not committed yet; when it
-- is, a fixture read from it replaces this one. It fills the `world` tables
-- of the item-stat stubs E-0a and E-0b share (spec/stubs/wow.lua, see
-- `world.itemStats`), in their shapes.
--
-- The item IDs are the owner's helm and gem IDs from earlier fixtures, used as
-- labels only; the stats are not theirs.

local F = {}

F.HELM_ID = 271528
F.GEM_ID = 240892
F.GEM2_ID = 240983

-- A worn link with an enchant (7364) and one gem in socket 1, and its body
-- with fields 2-6 blanked: the key and the link the client is asked about.
F.HELM_LINK = "|cffa335ee|Hitem:271528:7364:240892:0:0:0:0:0:90:105:0:0:2:12345:6652:0|h[Placeholder Hood]|h|r"
F.HELM_STRIPPED = "|cffa335ee|Hitem:271528::::::0:0:90:105:0:0:2:12345:6652:0|h[Placeholder Hood]|h|r"
F.HELM_KEY = "item:271528::::::0:0:90:105:0:0:2:12345:6652:0"
-- The same item with another gem and no enchant: the same key.
F.HELM_LINK_OTHER_GEM = "|cffa335ee|Hitem:271528::240983:0:0:0:0:0:90:105:0:0:2:12345:6652:0|h[Placeholder Hood]|h|r"

F.GEM_LINK = "|cff0070dd|Hitem:240892::::::::90:105:::::|h[Placeholder Gem]|h|r"
F.GEM2_LINK = "|cff0070dd|Hitem:240983::::::::90:105:::::|h[Placeholder Diamond]|h|r"

-- PLACEHOLDER stat tables, the wiki's keys.
F.HELM_STATS = {
    ITEM_MOD_INTELLECT_SHORT = 1001, -- PLACEHOLDER
    ITEM_MOD_STAMINA_SHORT = 2002, -- PLACEHOLDER
    ITEM_MOD_CRIT_RATING_SHORT = 303, -- PLACEHOLDER
    ITEM_MOD_HASTE_RATING_SHORT = 404, -- PLACEHOLDER
    ITEM_MOD_MASTERY_RATING_SHORT = 0, -- PLACEHOLDER (absent stats may read 0)
    ITEM_MOD_VERSATILITY = 0, -- PLACEHOLDER
    ITEM_MOD_CR_LIFESTEAL_SHORT = 55, -- PLACEHOLDER
    ITEM_MOD_CR_AVOIDANCE_SHORT = 0, -- PLACEHOLDER
    ITEM_MOD_CR_SPEED_SHORT = 0, -- PLACEHOLDER
    RESISTANCE0_NAME = 606, -- PLACEHOLDER
    EMPTY_SOCKET_PRISMATIC = 1, -- PLACEHOLDER (a socket count, not a stat)
    ITEM_MOD_SOMETHING_NEW_SHORT = 7, -- PLACEHOLDER: a key the map does not name
}
F.GEM_STATS = {
    ITEM_MOD_HASTE_RATING_SHORT = 71, -- PLACEHOLDER
    ITEM_MOD_MASTERY_RATING_SHORT = 29, -- PLACEHOLDER
}
F.GEM2_STATS = {
    ITEM_MOD_INTELLECT_SHORT = 83, -- PLACEHOLDER
}

F.HELM_LEVEL = 318 -- PLACEHOLDER
F.HELM_SET_ID = 1990 -- PLACEHOLDER
F.HELM_SOCKETS = 1 -- PLACEHOLDER
-- isUnique, limitCategoryName, limitCategoryCount, limitCategoryID (the
-- exported order, ItemDocumentation.lua:381-387).
F.HELM_UNIQUENESS = { true, "Placeholder Category", 2, 515 } -- PLACEHOLDER

-- Registers the fixture on a stub world: the helm loaded (GetItemInfo's
-- sixteenth return is setID), its stats under the STRIPPED link only, its gem
-- in socket 1 of each worn link.
function F.install(world)
    local info = { "Placeholder Hood", F.HELM_STRIPPED, 4, 318, 90, "Armor", "Cloth", 1, "INVTYPE_HEAD", 1, 0, 4, 1, 1, 11 }
    info[16] = F.HELM_SET_ID
    info.n = 18
    world.items[F.HELM_STRIPPED] = { info = info, level = F.HELM_LEVEL }
    world.itemStats[F.HELM_STRIPPED] = F.HELM_STATS
    world.itemSockets[F.HELM_STRIPPED] = F.HELM_SOCKETS
    world.itemUniquenessByID[F.HELM_ID] = F.HELM_UNIQUENESS
    world.itemGems[F.HELM_LINK] = { { name = "Placeholder Gem", link = F.GEM_LINK, id = F.GEM_ID } }
    world.itemGems[F.HELM_LINK_OTHER_GEM] = { { name = "Placeholder Diamond", link = F.GEM2_LINK, id = F.GEM2_ID } }
    world.itemStats[F.GEM_LINK] = F.GEM_STATS
    world.itemStats[F.GEM2_LINK] = F.GEM2_STATS
end

return F
