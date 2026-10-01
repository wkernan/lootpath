-- Lootpath/Data/EngineWeights.lua (E-0c, WKE-672)
-- The weights, the diminishing-returns brackets and the tier multipliers that
-- ns.EngineScore (Lootpath/Modules/EngineScore.lua) turns a set of item stats
-- into a value with. Developer-only: nothing a player sees reads it, behind
-- `db.global.developer.engine` (docs/ARCHITECTURE.md 7, 2026-09-30, E-0 and
-- E-0c; CLAUDE.md's scoped exception).
--
-- THIS COMMITTED COPY IS A SYNTHETIC PLACEHOLDER. Every number under `specs`
-- and `tiers` is invented and visibly so (weights of 1, a base of 12345, a set
-- ID of -1 that no item carries); `method = "placeholder"` says it, and the
-- loader says it again in its developer line. No value made from this file
-- means anything. The first real weights are E-0e's fit to QE Live's own
-- exports (WKE-674, dev-only, never shipped); later ones come from logs.
--
-- The `dr` brackets are NOT invented: they are E-0e's `tools/engine/lib/dr.js`
-- numbers (maxroll.gg's Stat Diminishing Returns summary, read 2026-09-30, the
-- page at patch 12.0.1): rating per percent at level 90 and, per bracket, the
-- penalty applied to the rating that falls inside it. Mastery is crit's table,
-- an assumption dr.js names (the page says mastery varies by specialization).
-- EngineScore uses them only when asked to (`opts.dr == "table"`); by default
-- each rating is converted by the client (`ns.EngineStats.Rating`), and E-0a's
-- transcript (WKE-675) says whether the client applies DR at all.
--
-- The shape, and nothing beyond it - the Data/QEVerdict.lua pattern: listed in
-- the .toc, assigns exactly one field, guards `type(ns) == "table"`, contains
-- no call, no loop and no function:
--
--   ns.engineWeights = {
--       schema = "lootpath-engine-weights", version = 1,
--       method = "placeholder" | "fit-to-qe-exports" | "logs" | "synthetic",
--       patch = "12.1.0",            -- GetBuildInfo()'s first return it is for;
--                                    -- any other client refuses the file
--       derivedAt = "never",
--       specs = { [specID] = { [contentType] = { bands = { [band] = {
--           baseValue = number,
--           weights = { int, haste, crit, mastery, vers, leech },  -- per point
--                                    -- of Intellect, per percent of a rating
--           assumedFinish = {        -- QE Live's rule: every set fully finished
--               gemVector = { <stat> = n },             -- times the socket count
--               enchantBySlot = { [slot] = { <stat> = n } },
--           },
--           assumedBuffs = { <stat> = n },  -- added to every set's totals
--       } } } } },
--       dr = { [stat] = { ratingPerPercent = n, brackets = { { from, penalty } } } },
--       tiers = { [setID] = { [pieces] = { mult = n } } },
--   }
--
-- A tier multiplier is the one bonus at that piece count, and the bonuses a
-- set has reached ADD before they multiply: 1 + (m2 - 1) + (m4 - 1) at four
-- pieces, QE Live's own rule (its set bonuses sum into one `bonusHPS` and the
-- score is multiplied by 1 + bonusHPS, fork TopGearEngine.ts:981, :1084-1085).
local _, ns = ...
if type(ns) ~= "table" then
    return
end
ns.engineWeights = {
    schema = "lootpath-engine-weights",
    version = 1,
    method = "placeholder",
    patch = "12.1.0",
    derivedAt = "never",
    specs = {
        [105] = {
            Dungeon = {
                bands = {
                    ["10+"] = {
                        baseValue = 12345,
                        weights = { int = 1, haste = 1, crit = 1, mastery = 1, vers = 1, leech = 1 },
                        assumedFinish = {
                            gemVector = { haste = 1 },
                            enchantBySlot = {
                                Chest = { int = 1 },
                                Legs = { int = 1 },
                                Finger = { haste = 1 },
                            },
                        },
                        assumedBuffs = { int = 1 },
                    },
                },
            },
            Raid = {
                bands = {
                    all = {
                        baseValue = 12345,
                        weights = { int = 1, haste = 1, crit = 1, mastery = 1, vers = 1, leech = 1 },
                        assumedFinish = {
                            gemVector = { haste = 1 },
                            enchantBySlot = {
                                Chest = { int = 1 },
                                Legs = { int = 1 },
                                Finger = { haste = 1 },
                            },
                        },
                        assumedBuffs = { int = 1 },
                    },
                },
            },
        },
    },
    dr = {
        haste = {
            ratingPerPercent = 44,
            brackets = {
                { from = 1320, penalty = 0.1 },
                { from = 1760, penalty = 0.2 },
                { from = 2200, penalty = 0.3 },
                { from = 2640, penalty = 0.4 },
                { from = 3080, penalty = 0.5 },
                { from = 8800, penalty = 1 },
            },
        },
        crit = {
            ratingPerPercent = 46,
            brackets = {
                { from = 1380, penalty = 0.1 },
                { from = 1840, penalty = 0.2 },
                { from = 2300, penalty = 0.3 },
                { from = 2760, penalty = 0.4 },
                { from = 3220, penalty = 0.5 },
                { from = 9200, penalty = 1 },
            },
        },
        mastery = {
            ratingPerPercent = 46,
            brackets = {
                { from = 1380, penalty = 0.1 },
                { from = 1840, penalty = 0.2 },
                { from = 2300, penalty = 0.3 },
                { from = 2760, penalty = 0.4 },
                { from = 3220, penalty = 0.5 },
                { from = 9200, penalty = 1 },
            },
        },
        vers = {
            ratingPerPercent = 54,
            brackets = {
                { from = 1620, penalty = 0.1 },
                { from = 2160, penalty = 0.2 },
                { from = 2700, penalty = 0.3 },
                { from = 3240, penalty = 0.4 },
                { from = 3780, penalty = 0.5 },
                { from = 10800, penalty = 1 },
            },
        },
        leech = {
            ratingPerPercent = 69,
            brackets = {
                { from = 690, penalty = 0.2 },
                { from = 1035, penalty = 0.4 },
                { from = 1380, penalty = 0.6 },
                { from = 3381, penalty = 1 },
            },
        },
    },
    tiers = {
        [-1] = {
            [2] = { mult = 1.111 },
            [4] = { mult = 1.222 },
        },
    },
}
