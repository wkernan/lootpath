-- spec/fixtures/engine/weights-simc-e7.lua (E-6, WKE-712)
-- tools/simc's OWN OUTPUT, committed unedited below this header, so the E-6
-- specs load a real E-7 (WKE-710) file rather than a hand-made one. Written on
-- origin/main c73bf5e by the same commands tools/simc/test/writer.test.js runs
-- over the committed SimC reports (spec/fixtures/simc/reports):
--   node run-scale-factors.js <102|103|104> [--fight DungeonSlice]
--        [--tank-value dps for 104's DungeonSlice] --from-reports
--        spec/fixtures/simc/reports --derived-at 2026-10-15T15:00:00Z
--   node write-weights.js 102 103 104
-- Every weight is SimulationCraft's scale factor per POINT of the stat; the
-- engine converts a rating's to per percent (EngineScore.WeightsPerPercent).
-- Developer-only data; never shipped.
--
-- DEV ONLY - never ship.
--
-- Written by tools/simc/write-weights.js (E-7, WKE-710): stat weights from
-- SimulationCraft's own scale factors over its sample profiles, run by us. Weights
-- are per POINT of each stat (`unit`), baseValue 0, no tier bonus measured (set
-- -1). Gitignored; .pkgmeta never packages tools/. Regenerate it; never edit it.
--
-- From:
--   102-Patchwerk.json  sha256 470935d2cd370cf9dfe04374da9d2fea0adde59dbd9f4a7fdaff3213f7a4f7f6
--   102-DungeonSlice.json  sha256 01f2061016c81bf7628ceafb7b8e51f276d3f141340f4140b6f6f355162074b7
--   103-Patchwerk.json  sha256 93608d337f4a5f77704200d09f30dc0e7c84ee9b7036d9de97cf5a1b550182ff
--   103-DungeonSlice.json  sha256 023e3720f0b43d089856678accda798c01fb16ab43aa57097fd7fbeaf2b7d224
--   104-Patchwerk.json  sha256 a2c90dc237bbc69513184082a1794eeeb41d4f126930a1520025dd1fa93bdb75
--   104-DungeonSlice.json  sha256 713fdb233850aa4393e065058971fea932ad4a713b1c93d14d5d72df4efa29ac

local _, ns = ...

ns.engineWeights = {
    schema = "lootpath-engine-weights",
    version = 2,
    devOnly = true,
    patch = "12.1.5",
    specs = {
        [102] = {
            role = "DAMAGER",
            primaryStat = "int",
            stats = {
                "int",
                "haste",
                "crit",
                "mastery",
                "vers",
            },
            method = "simc",
            derivedAt = "2026-10-15T15:00:00Z",
            source = "simc-sample-profile",
            simc = {
                version = "1210-01",
                gitRevision = "2358079",
                wowVersion = "12.1.5.70391",
            },
            Raid = {
                bands = {
                    all = {
                        baseValue = 0,
                        unit = "per point",
                        weights = {
                            int = 47.24663479484855,
                            haste = 26.379059421733118,
                            crit = 22.985176489612673,
                            mastery = 22.206384866812318,
                            vers = 22.16052311203252,
                        },
                        errors = {
                            int = 0.26201291312431396,
                            haste = 0.25811749484866947,
                            crit = 0.25818438015517425,
                            mastery = 0.2590849856899603,
                            vers = 0.25854781458011555,
                        },
                        value = {
                            metric = "dps",
                            mean = 127385.92188744998,
                            error = 27.780241776610588,
                        },
                        fight = "Patchwerk",
                        iterations = 100000,
                        profile = "31ee99e7f131bc49ceda2edf60d5ce32b207edd90285907979a6f1738d5e761b",
                        assumedFinish = {},
                        assumedBuffs = {},
                    },
                },
            },
            Dungeon = {
                bands = {
                    all = {
                        baseValue = 0,
                        unit = "per point",
                        weights = {
                            int = 43.7541004107723,
                            haste = 23.680488618891104,
                            crit = 20.339427213245674,
                            mastery = 19.06368044090305,
                            vers = 21.518855354995388,
                        },
                        errors = {
                            int = 0.3915104376976366,
                            haste = 0.38639031703729665,
                            crit = 0.38633865844359727,
                            mastery = 0.3858212070875245,
                            vers = 0.38657289237128384,
                        },
                        value = {
                            metric = "dps",
                            mean = 117079.7870115856,
                            error = 41.492421766883865,
                        },
                        fight = "DungeonSlice",
                        iterations = 100000,
                        profile = "31ee99e7f131bc49ceda2edf60d5ce32b207edd90285907979a6f1738d5e761b",
                        assumedFinish = {},
                        assumedBuffs = {},
                    },
                },
            },
            tiers = {
                [-1] = {
                    [2] = {
                        mult = 1,
                    },
                    [4] = {
                        mult = 1,
                    },
                },
            },
        },
        [103] = {
            role = "DAMAGER",
            primaryStat = "agi",
            stats = {
                "agi",
                "haste",
                "crit",
                "mastery",
                "vers",
            },
            method = "simc",
            derivedAt = "2026-10-15T15:00:00Z",
            source = "simc-sample-profile",
            simc = {
                version = "1210-01",
                gitRevision = "2358079",
                wowVersion = "12.1.5.70391",
            },
            Raid = {
                bands = {
                    all = {
                        baseValue = 0,
                        unit = "per point",
                        weights = {
                            agi = 61.88572059614397,
                            haste = 45.17118037546899,
                            crit = 42.788897038826924,
                            mastery = 37.40397455540785,
                            vers = 38.71717503004614,
                        },
                        errors = {
                            agi = 0.48037620241423834,
                            haste = 0.4760638187824499,
                            crit = 0.477219099232311,
                            mastery = 0.47823935914215493,
                            vers = 0.47808100923497204,
                        },
                        value = {
                            metric = "dps",
                            mean = 251459.6544987818,
                            error = 51.5706789546483,
                        },
                        fight = "Patchwerk",
                        iterations = 100000,
                        profile = "ad95e5d1a396b44dc1e72a6bcff38ef2b27cc8b17b4664cd4e17ff13bb7c1550",
                        assumedFinish = {},
                        assumedBuffs = {},
                    },
                },
            },
            Dungeon = {
                bands = {
                    all = {
                        baseValue = 0,
                        unit = "per point",
                        weights = {
                            agi = 43.843529127388905,
                            haste = 35.647955654566395,
                            crit = 30.40892818153612,
                            mastery = 25.38993062348012,
                            vers = 28.85060372560545,
                        },
                        errors = {
                            agi = 0.5096080021509933,
                            haste = 0.505183167936852,
                            crit = 0.5065783649678435,
                            mastery = 0.5063121688977005,
                            vers = 0.5064717100931148,
                        },
                        value = {
                            metric = "dps",
                            mean = 179101.6476716334,
                            error = 54.448751992918666,
                        },
                        fight = "DungeonSlice",
                        iterations = 100000,
                        profile = "ad95e5d1a396b44dc1e72a6bcff38ef2b27cc8b17b4664cd4e17ff13bb7c1550",
                        assumedFinish = {},
                        assumedBuffs = {},
                    },
                },
            },
            tiers = {
                [-1] = {
                    [2] = {
                        mult = 1,
                    },
                    [4] = {
                        mult = 1,
                    },
                },
            },
        },
        [104] = {
            role = "TANK",
            primaryStat = "agi",
            stats = {
                "agi",
                "haste",
                "crit",
                "mastery",
                "vers",
            },
            method = "simc",
            derivedAt = "2026-10-15T15:00:00Z",
            source = "simc-sample-profile",
            simc = {
                version = "1210-01",
                gitRevision = "2358079",
                wowVersion = "12.1.5.70391",
            },
            Raid = {
                bands = {
                    all = {
                        baseValue = 0,
                        unit = "per point",
                        weights = {
                            agi = 6.483390873056052,
                            haste = 4.919427949197491,
                            crit = 5.633619996938286,
                            mastery = 0.08303372428989471,
                            vers = 7.108811649571263,
                        },
                        errors = {
                            agi = 0.1874930489897397,
                            haste = 0.18592689093648346,
                            crit = 0.18783172439451784,
                            mastery = 0.18763109074552428,
                            vers = 0.18619353878602868,
                        },
                        value = {
                            metric = "dtps",
                            mean = 68715.16634065754,
                            error = 20.409448779361473,
                        },
                        fight = "Patchwerk",
                        iterations = 100000,
                        profile = "770a0b676c67f690c02c6781e34d4357c957157d46b8acf6c2e0cb76132c08ea",
                        assumedFinish = {},
                        assumedBuffs = {},
                    },
                },
            },
            Dungeon = {
                bands = {
                    all = {
                        baseValue = 0,
                        unit = "per point",
                        weights = {
                            agi = 24.79839250775269,
                            haste = 16.42409847519461,
                            crit = 11.549053830530815,
                            mastery = 11.204840393401508,
                            vers = 11.506106520544185,
                        },
                        errors = {
                            agi = 0.22373361467324873,
                            haste = 0.22130256602054818,
                            crit = 0.22064538061969824,
                            mastery = 0.22041906194633773,
                            vers = 0.22046674131738114,
                        },
                        value = {
                            metric = "dps",
                            mean = 69668.13091543569,
                            error = 23.697770991664292,
                        },
                        fight = "DungeonSlice",
                        iterations = 100000,
                        profile = "770a0b676c67f690c02c6781e34d4357c957157d46b8acf6c2e0cb76132c08ea",
                        assumedFinish = {},
                        assumedBuffs = {},
                    },
                },
            },
            tiers = {
                [-1] = {
                    [2] = {
                        mult = 1,
                    },
                    [4] = {
                        mult = 1,
                    },
                },
            },
        },
    },
    dr = {
        source = "maxroll.gg/wow/resources/stat-diminishing-returns, read 2026-09-30 (page: patch 12.0.1)",
        haste = {
            ratingPerPercent = 44,
            brackets = {
                {
                    from = 1320,
                    penalty = 0.1,
                },
                {
                    from = 1760,
                    penalty = 0.2,
                },
                {
                    from = 2200,
                    penalty = 0.3,
                },
                {
                    from = 2640,
                    penalty = 0.4,
                },
                {
                    from = 3080,
                    penalty = 0.5,
                },
                {
                    from = 8800,
                    penalty = 1,
                },
            },
        },
        crit = {
            ratingPerPercent = 46,
            brackets = {
                {
                    from = 1380,
                    penalty = 0.1,
                },
                {
                    from = 1840,
                    penalty = 0.2,
                },
                {
                    from = 2300,
                    penalty = 0.3,
                },
                {
                    from = 2760,
                    penalty = 0.4,
                },
                {
                    from = 3220,
                    penalty = 0.5,
                },
                {
                    from = 9200,
                    penalty = 1,
                },
            },
        },
        vers = {
            ratingPerPercent = 54,
            brackets = {
                {
                    from = 1620,
                    penalty = 0.1,
                },
                {
                    from = 2160,
                    penalty = 0.2,
                },
                {
                    from = 2700,
                    penalty = 0.3,
                },
                {
                    from = 3240,
                    penalty = 0.4,
                },
                {
                    from = 3780,
                    penalty = 0.5,
                },
                {
                    from = 10800,
                    penalty = 1,
                },
            },
        },
        mastery = {
            ratingPerPercent = 46,
            brackets = {
                {
                    from = 1380,
                    penalty = 0.1,
                },
                {
                    from = 1840,
                    penalty = 0.2,
                },
                {
                    from = 2300,
                    penalty = 0.3,
                },
                {
                    from = 2760,
                    penalty = 0.4,
                },
                {
                    from = 3220,
                    penalty = 0.5,
                },
                {
                    from = 9200,
                    penalty = 1,
                },
            },
            assumed = "crit's rating per point and brackets; the page says mastery varies by specialization - the 2026-10-01 transcript answered crit's figure at all seven points for spec 105",
        },
        leech = {
            ratingPerPercent = 69,
            brackets = {
                {
                    from = 690,
                    penalty = 0.2,
                },
                {
                    from = 1035,
                    penalty = 0.4,
                },
                {
                    from = 1380,
                    penalty = 0.6,
                },
                {
                    from = 3381,
                    penalty = 1,
                },
            },
        },
    },
}
