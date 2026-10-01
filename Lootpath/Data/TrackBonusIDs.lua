-- Lootpath/Data/TrackBonusIDs.lua (E-0g, WKE-677)
-- The bonus IDs that put an item on one of the season's upgrade tracks at one
-- step, and the item level each step draws. Developer-only: read by
-- ns.EngineStats.TrackBonusesAt (the one place a journal link is rebuilt at a
-- level) and by `/lootpath capture linklevel`, which asks the client whether a
-- link rebuilt with one of these draws the level the Adventure Guide previewed.
-- Nothing a player sees reads it, and nothing here is a healer value.
--
-- SOURCE (Blizzard's data, read through SimulationCraft's extracted OUTPUT,
-- never its code - docs/OWN-ENGINE.md section 2c): `engine/dbc/generated/
-- item_bonus.inc` and `engine/dbc/generated/item_scaling.inc` of
-- simulationcraft/simc, branch `midnight`, commit ddbd93b4b1494a5791b2db5ad1c90f550dc6e327
-- ("[live] Game data update (Build 69933)", 2026-09-29), both headed
-- "wow build 12.1.0.69933" - the owner's client build on 2026-10-01. Per bonus
-- ID: its type-34 entry (ITEM_BONUS upgrade: upgrade group 614..618, track
-- 971/972/973/974/978) and its type-49 entry (ITEM_BONUS_SCALE_CONFIG), whose
-- config row in item_scaling.inc carries the item level. The numbers were read
-- on 2026-10-01 and written here by hand; no file of SimulationCraft's is
-- copied or shipped.
--
-- WHAT THE OWNER'S OWN CLIENT CONFIRMS, independently of SimulationCraft:
--   * the level of every bonus ID marked `client = true`: an item the owner
--     owned on 2026-10-01 whose link carries it answered this level in
--     spec/fixtures/captures/Lootpath-20261001-092631.lua - through
--     `C_Item.GetDetailedItemLevelInfo` in `capture itemstats` (worn and bag
--     rows) or as `currentLevel` in `capture upgrade`. spec/enginestats_spec.lua
--     re-reads that transcript and holds every mark, and holds that no owned
--     link carrying any ID here answered another level;
--   * the step and the track's range for 12818-12820, 12834-12836 and
--     12842-12843: the same `capture upgrade` read `GetItemUpgradeItemInfo` as
--     2/6..4/6 of [266-282], [292-308] and [305-321].
-- The rest (no `client` mark) is SimulationCraft's word only until the
-- `capture linklevel` transcript reads a link rebuilt with it.
--
-- Six steps per track: the client answered `maxUpgrade = 6` on every owned
-- upgradeable item, and the tops are the season's (docs/ROADS-UX.md:
-- Adventurer 282 / Veteran 295 / Champion 308 / Hero 321 / Myth 334). The
-- extracted data carries two more IDs per group (12823-12824, 12831-12832,
-- 12839-12840, 12847-12848, 12855-12856) at the levels above each top; no
-- client answer names them, so they are left out.
--
-- The shape, and nothing beyond it - the Data/QEVerdict.lua pattern: listed in
-- the .toc, assigns exactly one field, guards `type(ns) == "table"`, contains
-- no call, no loop and no function.

local _, ns = ...
if type(ns) ~= "table" then
    return
end

ns.trackBonusIDs = {
    schema = "lootpath-track-bonus-ids",
    version = 1,
    build = "12.1.0.69933",
    source = "simulationcraft/simc midnight ddbd93b4b1494a5791b2db5ad1c90f550dc6e327 "
        .. "engine/dbc/generated/item_bonus.inc + item_scaling.inc (wow build 12.1.0.69933)",
    readAt = "2026-10-01",
    tracks = {
        {
            name = "Adventurer",
            trackID = 971,
            upgradeGroup = 614,
            steps = {
                { bonusID = 12817, itemLevel = 266 },
                { bonusID = 12818, itemLevel = 269, client = true },
                { bonusID = 12819, itemLevel = 272, client = true },
                { bonusID = 12820, itemLevel = 276, client = true },
                { bonusID = 12821, itemLevel = 279 },
                { bonusID = 12822, itemLevel = 282, client = true },
            },
        },
        {
            name = "Veteran",
            trackID = 972,
            upgradeGroup = 615,
            steps = {
                { bonusID = 12825, itemLevel = 279, client = true },
                { bonusID = 12826, itemLevel = 282 },
                { bonusID = 12827, itemLevel = 285 },
                { bonusID = 12828, itemLevel = 289 },
                { bonusID = 12829, itemLevel = 292 },
                { bonusID = 12830, itemLevel = 295, client = true },
            },
        },
        {
            name = "Champion",
            trackID = 973,
            upgradeGroup = 616,
            steps = {
                { bonusID = 12833, itemLevel = 292, client = true },
                { bonusID = 12834, itemLevel = 295, client = true },
                { bonusID = 12835, itemLevel = 298, client = true },
                { bonusID = 12836, itemLevel = 302, client = true },
                { bonusID = 12837, itemLevel = 305 },
                { bonusID = 12838, itemLevel = 308, client = true },
            },
        },
        {
            name = "Hero",
            trackID = 974,
            upgradeGroup = 617,
            steps = {
                { bonusID = 12841, itemLevel = 305 },
                { bonusID = 12842, itemLevel = 308, client = true },
                { bonusID = 12843, itemLevel = 311, client = true },
                { bonusID = 12844, itemLevel = 315 },
                { bonusID = 12845, itemLevel = 318, client = true },
                { bonusID = 12846, itemLevel = 321, client = true },
            },
        },
        {
            name = "Myth",
            trackID = 978,
            upgradeGroup = 618,
            steps = {
                { bonusID = 12849, itemLevel = 318 },
                { bonusID = 12850, itemLevel = 321 },
                { bonusID = 12851, itemLevel = 324 },
                { bonusID = 12852, itemLevel = 328 },
                { bonusID = 12853, itemLevel = 331 },
                { bonusID = 12854, itemLevel = 334, client = true },
            },
        },
    },
}
