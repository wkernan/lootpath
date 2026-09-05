-- Lootpath/Modules/Journal.lua (stub; built in M3-1, WKE-522)
-- Contract: ns.JournalAdapter (every Encounter Journal call, raw, secret-guarded)
-- and ns.Journal:Build(opts) -> { [itemID] = { { instanceID, instanceName, encounterID,
--   encounterName, difficultyID, itemLevel, slot, isRaid } ... } }, cached in
-- db.global.journalCache keyed (build, seasonID, specID, difficultyID).
-- Item level is not a field of EncounterJournalItemInfo (Blizzard docs, checked
-- 2026-09-05); it comes from C_Item.GetDetailedItemLevelInfo on the loot link.
local _, ns = ...

ns.JournalAdapter = {}
ns.Journal = {}
