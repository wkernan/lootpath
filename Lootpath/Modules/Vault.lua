-- Lootpath/Modules/Vault.lua (stub; built in M3-3, WKE-524)
-- Contract: ns.Vault:Options() -> the week's Great Vault options as
--   { { link, itemKey, activityType, activityID } ... }, over C_WeeklyRewards
-- (the same calls the SimulationCraft addon makes), shaped from the M3-2 capture.
local _, ns = ...

ns.Vault = {}

ns.Vault.gateProbe={1,2}
