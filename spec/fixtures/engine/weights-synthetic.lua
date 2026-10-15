-- spec/fixtures/engine/weights-synthetic.lua (E-0c, WKE-672)
-- SYNTHETIC. No figure here is a game value. A Data/EngineWeights.lua-shaped
-- table the EngineScore tests score with, built so the numbers match the model
-- of E-0e's score fixture (spec/fixtures/engine/score-fixture.json, copied
-- verbatim from origin/lp-e0e-fit-weights at c76a26a (main 2a6932e), its
-- tools/engine/test/fixtures/score-fixture.json):
--
--   baseValue 1000; weights int 1, haste 20, crit 15, mastery 18, vers 12,
--   leech 5; tier set 2057 at 2 pieces +3% and 4 pieces +5.5%.
--
-- One translation, said here and in the PR: score.js adds its
-- `assumedFinish` (int 100, haste 50) to EVERY set as one flat vector, which
-- is what this file's `assumedBuffs` is. This file's own `assumedFinish` (a gem
-- per socket, an enchant per slot - the issue's shape) is used only by the
-- parity-mode tests, and none of the fixture's items has a socket.
--
-- Schema version 2 (E-4, WKE-708): the spec entry carries Restoration's role,
-- primary stat, stat list, method, derivedAt and tier set; the numbers are
-- unchanged from version 1.
--
-- The `dr` table is E-0e's lib/dr.js DEFAULT_DR, the same brackets the shipped
-- placeholder carries (maxroll.gg, read 2026-09-30, patch 12.0.1; mastery is
-- crit's table, an assumption dr.js names).
--
-- Loaded with dofile: it returns the table rather than setting a field.
return {
    schema = "lootpath-engine-weights",
    version = 2,
    patch = "12.1.0",
    specs = {
        [105] = {
            role = "HEALER",
            primaryStat = "int",
            stats = { "int", "haste", "crit", "mastery", "vers", "leech" },
            method = "synthetic",
            derivedAt = "never",
            Dungeon = {
                bands = {
                    ["10+"] = {
                        baseValue = 1000,
                        weights = { int = 1, haste = 20, crit = 15, mastery = 18, vers = 12, leech = 5 },
                        assumedFinish = {
                            gemVector = { haste = 10 },
                            enchantBySlot = { Finger = { mastery = 5 }, Chest = { int = 7 } },
                        },
                        assumedBuffs = { int = 100, haste = 50 },
                    },
                },
            },
            tiers = {
                [2057] = {
                    [2] = { mult = 1.03 },
                    [4] = { mult = 1.055 },
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
}
