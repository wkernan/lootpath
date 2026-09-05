-- Lootpath/Modules/Inventory.lua (stub; built in M1-1, WKE-516)
-- Contract: ns.Inventory:Scan() -> { ok = true, records = { record... }, bankAvailable = bool }
--   record = { itemID, link, itemLevel, bonusIDs (sorted), slot, location = "equipped"|"bag"|"bank",
--              bag, slotIndex, name, quality }
-- or { ok = false, reason = "combat" }. Every read passes ns.Safe; the bank is
-- reported unavailable (never a silent empty list) unless the bank frame is open.
-- The normaliser is written against the M1-2 capture transcript, not from memory.
local _, ns = ...

ns.Inventory = {}
