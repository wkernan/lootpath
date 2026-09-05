-- Lootpath/Modules/Match.lua (stub; built in M2-2, WKE-520)
-- Contract: ns.Match.Build(inventory, verdict) -> per gear slot
--   { slot, equipped, best, verdictItem, status = "equipped_is_best"|"swap"|"best_not_owned"|"no_verdict" }
-- joined by ns.ItemKey; exact key first, itemID+ilvl fallback logged, never silent.
local _, ns = ...

ns.Match = {}
