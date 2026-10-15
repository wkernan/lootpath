-- Lootpath/Data/EngineEffects.lua (E-3a, WKE-679)
-- The effects table: which items carry an effect that their stats do not
-- describe, what KIND of effect it is, and - later - the numbers a generic
-- rule needs to turn it into stats or healing. ns.EngineEffects
-- (Lootpath/Modules/EngineEffects.lua) reads it; ns.EngineScore asks it about
-- every item it scores. Developer-only, like everything the engine makes
-- (docs/ARCHITECTURE.md section 7, 2026-09-30, E-0; 2026-10-01, E-3a).
--
-- The kind is the classification, read from docs/OWN-ENGINE.md section 4.
-- The NUMBERS (E-3c, WKE-686) come from one place only: the owner's `capture
-- effects` transcript (spec/fixtures/captures/Lootpath-20261005-163103.lua,
-- 2026-10-05, client 12.1.0 build 69933), extracted unedited into
-- spec/fixtures/engine/effects-real.lua. Every number below is a string the
-- client wrote in an item's "Use:" or "Equip:" line, cited by itemID and the
-- tooltip's own "Item Level" line; spec/engineeffects_spec.lua finds each one
-- in that file. An amount that follows the item level is kept per level READ
-- under `byLevel` - never interpolated, never the nearest level: a level the
-- capture did not read is `not modelled` (ns.EngineEffects.ParamsAt). The one
-- conversion is a cooldown's minutes and seconds written as seconds ("1 Min
-- 30 Sec" is 90).
--
-- `confidence = "generic"` only where every field the kind's rule reads is
-- in the tooltip: three trinkets (Pulse Seeker's Oculus, Freightrunner's
-- Flask, Stormbound Emblem of Dazar). No tooltip carries an RPPM, an overheal
-- share or a target count, so every stat proc, flat heal and heal-on-use stays
-- `not_modelled` with the numbers the tooltip DID give; their gaps are named
-- in docs/ARCHITECTURE.md section 11 (E-3c). The eight trinkets the capture
-- found nowhere (`missing` in the transcript) keep `params = nil`; so do the
-- unique, unknown and damage-only kinds, which no rule reads.
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
--           params = nil | { <the rule's level-independent fields>,
--                            byLevel = { [itemLevel] = { <fields> } } },
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
    derivedAt = "2026-10-05",
    source = "docs/OWN-ENGINE.md section 4 (kinds); spec/fixtures/engine/effects-real.lua (numbers)",
    items = {
        -- Passive stat (1).
        [274495] = {
            name = "Pulse Seeker's Oculus",
            slot = "Trinket",
            kind = "passive_stat",
            confidence = "generic",
            -- "Equip: Your Mastery is increased by 92, plus an additional 29
            -- while a party member is below 65% health. ... increasing these
            -- effects by 100% for 12 sec. This can only occur every 5 min."
            -- (308; 91 and 28 at 305). The always-on Mastery only: how often a
            -- party member is below 65% or 35% is not in a tooltip.
            params = {
                byLevel = {
                    [305] = { stat = { mastery = 91 } },
                    [308] = { stat = { mastery = 92 } },
                },
            },
        },
        -- Stat proc, RPPM (5).
        [250214] = {
            name = "Lightspire Core",
            slot = "Trinket",
            kind = "stat_proc",
            confidence = "not_modelled",
            -- "Equip: You are embraced by the Light, increasing Mastery by 88.
            -- ... Your damaging spells and abilities can call a beam of radiant
            -- light nearby. Standing in the light blesses you with 153 Mastery
            -- while you stand in it." (276). The beam's amount per level; no
            -- RPPM and no duration in the text. The always-on "increasing
            -- Mastery by" part (88, 89, 95, 96, 101, 102 at the levels below)
            -- is a passive the stat_proc classification does not hold.
            params = {
                stat = "mastery",
                byLevel = {
                    [276] = { amount = 153 },
                    [279] = { amount = 156 },
                    [292] = { amount = 166 },
                    [295] = { amount = 169 },
                    [305] = { amount = 177 },
                    [308] = { amount = 179 },
                },
            },
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
            confidence = "generic",
            -- "Use: ... increasing your Critical Strike by 528 for 15 sec.
            -- (1 Min 30 Sec Cooldown)" (276).
            params = {
                stat = "crit",
                duration = 15,
                cooldown = 90,
                byLevel = {
                    [276] = { amount = 528 },
                    [279] = { amount = 536 },
                    [292] = { amount = 572 },
                    [295] = { amount = 581 },
                    [305] = { amount = 608 },
                    [308] = { amount = 617 },
                    [331] = { amount = 680 },
                    [334] = { amount = 689 },
                },
            },
        },
        [273649] = {
            name = "Stormbound Emblem of Dazar",
            slot = "Trinket",
            kind = "stat_on_use",
            confidence = "generic",
            -- "Use: Channel for 2 sec as the wind answers Dazar's command,
            -- increasing your Haste by 806 up to 20 sec. (2 Min Cooldown)"
            -- (276). The 2 s channel is not counted.
            params = {
                stat = "haste",
                duration = 20,
                cooldown = 120,
                byLevel = {
                    [276] = { amount = 806 },
                    [279] = { amount = 819 },
                    [292] = { amount = 874 },
                    [295] = { amount = 887 },
                },
            },
        },
        [273796] = {
            name = "Vile Vial of Volatile Venom",
            slot = "Trinket",
            kind = "stat_on_use",
            confidence = "not_modelled",
            -- "Use: Take a small sip of venom, gaining 739 of a random
            -- secondary stat for 15 sec. Afterwards, a random secondary stat
            -- is reduced by 105 for 15 sec. (2 Min Cooldown)" (276). A random
            -- stat is not one stat: no `stat`, so the rule does not run.
            params = {
                duration = 15,
                cooldown = 120,
                byLevel = {
                    [276] = { amount = 739 },
                    [279] = { amount = 750 },
                    [292] = { amount = 801 },
                    [295] = { amount = 813 },
                    [305] = { amount = 851 },
                    [308] = { amount = 863 },
                },
            },
        },
        -- Flat heal proc (5).
        [193748] = {
            name = "Kyrakka's Searing Embers",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            -- "Equip: Your helpful spells and abilities have a high chance to
            -- create a Burning Ember on an ally. The ember flares up after 1
            -- sec, cauterizing wounds to heal for 34,166 ..." (276). No proc
            -- rate, overheal or targets in the text.
            params = {
                byLevel = {
                    [276] = { heal = 34166 },
                    [279] = { heal = 35221 },
                    [292] = { heal = 40182 },
                    [295] = { heal = 41422 },
                    [305] = { heal = 45837 },
                    [308] = { heal = 47250 },
                },
            },
        },
        [250248] = {
            name = "Mycolic Medicine",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            -- "Equip: ... Your healing spells and abilities have a chance to
            -- instantly heal your target for 47,169 and spawn a glowing
            -- mushroom ... healed for an additional 26,954." (276). The
            -- instant heal per level; the mushroom heals only an ally who
            -- steps on it. No proc rate, overheal or targets in the text.
            params = {
                byLevel = {
                    [276] = { heal = 47169 },
                    [279] = { heal = 49430 },
                    [292] = { heal = 60315 },
                    [295] = { heal = 63097 },
                    [305] = { heal = 73182 },
                    [308] = { heal = 76467 },
                    [311] = { heal = 79880 },
                },
            },
        },
        [270171] = {
            name = "Preternatural Antivenom",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            -- "Equip: Your healing has a high chance to infuse the target with
            -- Preternatural Antivenom for 30 sec, healing your ally for 75% of
            -- any damage they take until 247,668 health has been restored."
            -- (308). The cap per level; how much of it heals depends on the
            -- damage taken. No proc rate, overheal or targets in the text.
            params = {
                byLevel = {
                    [308] = { heal = 247668 },
                    [311] = { heal = 255303 },
                    [315] = { heal = 265848 },
                    [321] = { heal = 282482 },
                    [324] = { heal = 291183 },
                    [328] = { heal = 303200 },
                },
            },
        },
        [251789] = {
            name = "Consecrated Chalice",
            slot = "Trinket",
            kind = "flat_heal",
            confidence = "not_modelled",
            -- "Equip: Your healing spells and abilities have a high chance to
            -- fill the chalice with Hope, drop by drop, up to 15 times." and
            -- "Use: Empty the chalice upon an ally granting them 15,766 absorb
            -- for each drop spilled for 20 sec. (20 Sec Cooldown)" (298). The
            -- absorb per drop; how fast the chalice fills is not in the text.
            params = {
                byLevel = {
                    [298] = { heal = 15766 },
                    [302] = { heal = 16730 },
                },
            },
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
            -- "Use: Call forth 5 Soulcoiler Cultist spirits over 2 sec ...,
            -- each granting an ally a barrier reducing damage taken by 50% for
            -- 20 sec or until 198,462 damage has been prevented. ... (2 Min
            -- Cooldown)" (305). ONE barrier's cap per level, under `barrier`,
            -- not `amount`: five capped barriers are not one amount the text
            -- states. No waste share in the text.
            params = {
                cooldown = 120,
                byLevel = {
                    [305] = { barrier = 198462 },
                    [308] = { barrier = 207371 },
                    [318] = { barrier = 239633 },
                    [321] = { barrier = 250131 },
                },
            },
        },
        [250254] = {
            name = "Seed of Radiant Hope",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            -- "Use: Surround your target ally with Lightblossoms, healing them
            -- for 122,946 over 12 sec. If their health falls below 50%, the
            -- Lightblossoms fully bloom ..., instantly healing them for
            -- 138,332. (1 Min Cooldown)" (276). The heal over time per level;
            -- the bloom is conditional. No overheal in the text.
            params = {
                cooldown = 60,
                byLevel = {
                    [276] = { amount = 122946 },
                    [279] = { amount = 128839 },
                    [292] = { amount = 157209 },
                    [295] = { amount = 164460 },
                    [305] = { amount = 190748 },
                    [308] = { amount = 199310 },
                    [311] = { amount = 208205 },
                },
            },
        },
        [250255] = {
            name = "Unstable Felheart Crystal",
            slot = "Trinket",
            kind = "heal_on_use",
            confidence = "not_modelled",
            -- "Use: ... sacrificing 11,044 of your health to infuse a target
            -- ally for 10 sec, absorbing 360,808 damage. (1 Min 30 Sec
            -- Cooldown)" (276). The absorb per level. No waste share in the
            -- text.
            params = {
                cooldown = 90,
                byLevel = {
                    [276] = { amount = 360808 },
                    [279] = { amount = 378103 },
                    [292] = { amount = 461359 },
                    [295] = { amount = 482640 },
                    [305] = { amount = 559787 },
                    [308] = { amount = 584914 },
                },
            },
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
