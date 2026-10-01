-- Lootpath/Data/EngineEffects.lua (E-3a, WKE-679)
-- The effects table: which items carry an effect that their stats do not
-- describe, what KIND of effect it is, and - later - the numbers a generic
-- rule needs to turn it into stats or healing. ns.EngineEffects
-- (Lootpath/Modules/EngineEffects.lua) reads it; ns.EngineScore asks it about
-- every item it scores. Developer-only, like everything the engine makes
-- (docs/ARCHITECTURE.md section 7, 2026-09-30, E-0; 2026-10-01, E-3a).
--
-- THIS FILE SHIPS CLASSIFIED AND EMPTY OF NUMBERS. Every entry carries
-- `params = nil` and `confidence = "not_modelled"`: the kind is the
-- classification, read from docs/OWN-ENGINE.md section 4; the per-item
-- numbers (a proc's amount at the link's level, its cooldown, its RPPM) come
-- from the tooltip at the link's level and are a later capture. Until one
-- arrives, every item here is `not modelled`: its stats still count, the
-- result says the effect is missing, and the compare leaves the row out.
--
-- Every itemID below was checked against the repo's own data on 2026-10-01:
-- the committed journal walk (spec/fixtures/captures/Lootpath-20260916-162655.lua,
-- `journalCache`, slot from its rows) and the Upgrade Finder / Top Gear exports
-- under spec/fixtures/qe/ (`slot` from their rows). Forgotten Farstrider's
-- Insignia is in the walk and in no export (QE Live does not carry it). Ten
-- trinkets are in the exports and not the walk (delve and other sources); of
-- those, the names of 248583, 251792, 251789, 274493 and 274495 are read from
-- earlier committed captures' links (Lootpath-20260905-133449.lua,
-- Lootpath-20260908-124527.lua); the names of 251788, 252957, 264701, 274494
-- and 280091 are the memo's (no committed capture names them) - the ID is the
-- key, the name a label.
--
-- The tier set's multipliers stay in Data/EngineWeights.lua's `tiers`: the
-- fit (tools/engine/fit-weights.js, lib/luaout.js) writes them into the
-- weights file it fits them with, so moving them here would split one fitted
-- model across two files. `sets` here is empty and is the one place a set
-- EFFECT beyond a multiplier would go.
--
-- The shape, and nothing beyond it - the Data/QEVerdict.lua pattern: listed in
-- the .toc, assigns exactly one field, guards `type(ns) == "table"`, contains
-- no call, no loop and no function:
--
--   ns.engineEffects = {
--       schema = "lootpath-engine-effects", version = 1,
--       patch = "12.1.0", season = 2, derivedAt = "...", source = "...",
--       items = { [itemID] = {
--           name = "...", slot = "Trinket" | <Inventory slot vocabulary>,
--           kind = "passive_stat" | "stat_proc" | "stat_on_use" | "flat_heal"
--                | "heal_on_use" | "unique" | "unknown" | "damage_only",
--           confidence = "generic" | "not_modelled",
--           params = nil,   -- the rule's numbers; nil until a capture
--       } },
--       sets = {},
--   }
--
-- The memo's error bands per kind are ESTIMATES (iii), not measurements:
-- stat procs +-5-10% of the effect, stat on-use +-15-25%, flat heals and
-- absorbs +-30-100%, unique items +-50-100% (docs/OWN-ENGINE.md section 4).
local _, ns = ...
if type(ns) ~= "table" then
    return
end
ns.engineEffects = {
    schema = "lootpath-engine-effects",
    version = 1,
    patch = "12.1.0",
    season = 2,
    derivedAt = "2026-10-01",
    source = "docs/OWN-ENGINE.md section 4, IDs checked against the committed walk and exports",
    items = {
        -- Passive stat (1).
        [274495] = {
            name = "Pulse Seeker's Oculus",
            slot = "Trinket",
            kind = "passive_stat",
            confidence = "not_modelled",
            params = nil,
        },
        -- Stat proc, RPPM (5).
        [250214] = {
            name = "Lightspire Core",
            slot = "Trinket",
            kind = "stat_proc",
            confidence = "not_modelled",
            params = nil,
        },
        [248583] = {
            name = "Drum of Renewed Bonds",
            slot = "Trinket",
            kind = "stat_proc",
            confidence = "not_modelled",
            params = nil,
        },
        [251792] = {
            name = "Glorious Crusader's Keepsake",
            slot = "Trinket",
            kind = "stat_proc",
            confidence = "not_modelled",
            params = nil,
        },
        [274493] = {
            name = "Effigy of Ula'tek's Faithful",
            slot = "Trinket",
            kind = "stat_proc",
            confidence = "not_modelled",
            params = nil,
        },
        [251788] = {
            name = "Gift of Light",
            slot = "Trinket",
            kind = "stat_proc",
            confidence = "not_modelled",
            params = nil,
        },
        -- Stat on-use (3).
        [250215] = {
            name = "Freightrunner's Flask",
            slot = "Trinket",
            kind = "stat_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        [273649] = {
            name = "Stormbound Emblem of Dazar",
            slot = "Trinket",
            kind = "stat_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        [273796] = {
            name = "Vile Vial of Volatile Venom",
            slot = "Trinket",
            kind = "stat_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        -- Flat heal proc (5).
        [193748] = {
            name = "Kyrakka's Searing Embers",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            params = nil,
        },
        [250248] = {
            name = "Mycolic Medicine",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            params = nil,
        },
        [270171] = {
            name = "Preternatural Antivenom",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            params = nil,
        },
        [251789] = {
            name = "Consecrated Chalice",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            params = nil,
        },
        [252957] = {
            name = "Tangle of Vibrant Vines",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            params = nil,
        },
        -- Heal or absorb on-use (6).
        [270162] = {
            name = "Soulcoiler Ritual Vessel",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        [250254] = {
            name = "Seed of Radiant Hope",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        [250255] = {
            name = "Unstable Felheart Crystal",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        [264701] = {
            name = "Cosmic Bell",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        [274494] = {
            name = "Chiral Marrowgrafter",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        [280091] = {
            name = "Latent Purifier",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            params = nil,
        },
        -- Unique: no generic rule fits (4).
        [270164] = {
            name = "Gebbo's Bottomless Bag",
            slot = "Trinket",
            kind = "unique",
            confidence = "not_modelled",
            params = nil,
        },
        [270167] = {
            name = "Wavecaller's Seastone",
            slot = "Trinket",
            kind = "unique",
            confidence = "not_modelled",
            params = nil,
        },
        [270169] = {
            name = "Hex Lord's Dooming Idol",
            slot = "Trinket",
            kind = "unique",
            confidence = "not_modelled",
            params = nil,
        },
        [193757] = {
            name = "Ruby Whelp Shell",
            slot = "Trinket",
            kind = "unique",
            confidence = "not_modelled",
            params = nil,
        },
        -- Unknown: not in QE Live's data at all (1).
        [250462] = {
            name = "Forgotten Farstrider's Insignia",
            slot = "Trinket",
            kind = "unknown",
            confidence = "not_modelled",
            params = nil,
        },
        -- Effect armour and weapons (4). The memo names them as effect items
        -- without classifying the first three; Polished Lightwood Channeler's
        -- effect deals damage only.
        [271875] = {
            name = "Gaze of the Coiled Watcher",
            slot = "Head",
            kind = "unknown",
            confidence = "not_modelled",
            params = nil,
        },
        [271092] = {
            name = "Jan'thrazet, the Soul Fang",
            slot = "1H Weapon",
            kind = "unknown",
            confidence = "not_modelled",
            params = nil,
        },
        [268265] = {
            name = "Aqirbane Reliquary",
            slot = "Neck",
            kind = "unknown",
            confidence = "not_modelled",
            params = nil,
        },
        [273778] = {
            name = "Polished Lightwood Channeler",
            slot = "1H Weapon",
            kind = "damage_only",
            confidence = "not_modelled",
            params = nil,
        },
    },
    sets = {},
}
