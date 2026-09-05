-- Lootpath/Modules/QEImport.lua (stub; built in M2-1, WKE-518)
-- Contract: ns.QEImport.Parse(text) -> { ok = true, verdict } | { ok = false, reason }.
-- Accepts only schema "qe-live-droptimizer", version 1, gameType "Retail", with a
-- topSet; any other version is refused with a message naming both versions.
-- This module transports QE Live's numbers; it never adjusts them.
local _, ns = ...

ns.QEImport = {}
