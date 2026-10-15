-- spec/fixtures/engine/linklevel-real.lua (E-0g step 2, WKE-677)
--
-- GENERATED - do not edit. `node tools/engine/extract-linklevel.js` wrote it
-- from spec/fixtures/captures/Lootpath-20261001-200927.lua
-- (sha256 455e02d9e17a9014bfc978e8da57ab6b34b502ffbbb4821a17d68af092f3ec42, 5693314 bytes as committed),
-- the owner's `capture linklevel` on the Druid, 2026-10-01. Every value is the
-- client's answer copied through tools/companion/lib/lua-savedvariables.js:
-- nothing computed, rounded or invented. tools/engine/test/extract.test.js
-- re-runs the script and compares the bytes.

local F = {}

F.SOURCE = "spec/fixtures/captures/Lootpath-20261001-200927.lua"
F.SHA256 = "455e02d9e17a9014bfc978e8da57ab6b34b502ffbbb4821a17d68af092f3ec42"
F.BYTES = 5693314
F.CAPTURED_AT = 1790903358
F.CAPTURED_AT_LOCAL = "2026-10-01T20:09:18"
F.BUILD = {
    [1] = "12.1.0",
    [2] = "69933",
    [3] = "Sep 18 2026",
    [4] = 120100,
    [5] = "",
    [6] = " ",
    n = 6,
}
F.TRIGGER = "command"
F.DURATION_MS = 156.6505999565125
F.SAW_SECRET = false
F.JOURNAL = {
    cacheEntries = {
        {
            build = "69933",
            key = "69933|18|105|2:8:15:16:23",
            walkAt = 1790381953,
        },
    },
    differing = 101,
    differingByDifficulty = {
        [8] = 54,
        [15] = 27,
        [16] = 20,
    },
    max = 12,
    rowsWithLink = 266,
    taken = 12,
}
F.WALK = {
    durationMs = 130.845300078392,
    itemDataTimeouts = 0,
    pendingRowsFinalRead = 0,
    secretsSeen = 0,
    targets = 8,
    timeouts = 0,
}
F.VIEW_STATE_BEFORE = {
    difficulty = {
        [1] = 14,
        n = 1,
    },
    lootFilter = {
        [1] = 11,
        [2] = 0,
        n = 2,
    },
    tier = {
        [1] = 13,
        n = 1,
    },
}
F.SELECTED_TIER = 13

-- The 12 candidates in the snapshot's order. `walkLevel` is the level the
-- walk listed the row at, `ownLevel` the kept link's level when the capture
-- chose it; each variant carries its three reads.
F.CANDIDATES = {
    {
        bonusIDs = {
            3524,
        },
        context = 16,
        difficultyID = 8,
        encounterID = 2142,
        instanceID = 1030,
        instanceName = "Temple of Sethraliss",
        isRaid = false,
        itemID = 159317,
        link = "|cnIQ4:|Hitem:159317::::::::90:105::16:1:3524:1:28:1279:::::|h[Whirling Dervish Sash]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:159317::::::::90:105::16:1:3524:1:28:1279:::::|h[Whirling Dervish Sash]|h|r",
            previewLevel = 10,
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 305,
                [2] = false,
                [3] = 59,
                n = 3,
            },
        },
        name = "Whirling Dervish Sash",
        ownLevel = 292,
        previewMythicPlusLevel = 10,
        slot = "Waist",
        trackSteps = 2,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 292,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 292",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 49,
                        ITEM_MOD_INTELLECT_SHORT = 96,
                        ITEM_MOD_MASTERY_RATING_SHORT = 76,
                        ITEM_MOD_STAMINA_SHORT = 1805,
                        RESISTANCE0_NAME = 84,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:159317::::::::90:105::16:1:3524:1:28:1279:::::|h[Whirling Dervish Sash]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                link = "|cnIQ4:|Hitem:159317::::::::90:105::16:1:12837:1:28:1279:::::|h[Whirling Dervish Sash]|h|r",
                rule = "track-replace",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:159317::::::::90:105::16:2:3524:12837:1:28:1279:::::|h[Whirling Dervish Sash]|h|r",
                rule = "track-append",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:159317::::::::90:105::16:1:12841:1:28:1279:::::|h[Whirling Dervish Sash]|h|r",
                rule = "track-replace",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 59,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 52,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:159317::::::::90:105::16:2:3524:12841:1:28:1279:::::|h[Whirling Dervish Sash]|h|r",
                rule = "track-append",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
        },
        walkLevel = 305,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 5,
        difficultyID = 15,
        encounterID = 2782,
        instanceID = 1312,
        instanceName = "Midnight",
        isRaid = true,
        itemID = 250461,
        link = "|cnIQ4:|Hitem:250461::::::::90:105::5:1:3524::::::|h[Chain of the Ancient Watcher]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:250461::::::::90:105::5:1:3524::::::|h[Chain of the Ancient Watcher]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 44,
                [2] = false,
                [3] = 197,
                n = 3,
            },
        },
        name = "Chain of the Ancient Watcher",
        ownLevel = 259,
        previewMythicPlusLevel = 10,
        slot = "Neck",
        trackNote = "no track step draws 44",
        trackSteps = 0,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 17,
                        ITEM_MOD_MASTERY_RATING_SHORT = 9,
                        ITEM_MOD_STAMINA_SHORT = 8,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 259,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 259",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 154,
                        ITEM_MOD_MASTERY_RATING_SHORT = 80,
                        ITEM_MOD_STAMINA_SHORT = 910,
                    },
                },
                journal = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 17,
                        ITEM_MOD_MASTERY_RATING_SHORT = 9,
                        ITEM_MOD_STAMINA_SHORT = 8,
                    },
                },
                link = "|cnIQ4:|Hitem:250461::::::::90:105::5:1:3524::::::|h[Chain of the Ancient Watcher]|h|r",
                rule = "kept",
            },
        },
        walkLevel = 44,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 6,
        difficultyID = 16,
        encounterID = 2782,
        instanceID = 1312,
        instanceName = "Midnight",
        isRaid = true,
        itemID = 250461,
        link = "|cnIQ4:|Hitem:250461::::::::90:105::6:1:3524::::::|h[Chain of the Ancient Watcher]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:250461::::::::90:105::6:1:3524::::::|h[Chain of the Ancient Watcher]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 44,
                [2] = false,
                [3] = 197,
                n = 3,
            },
        },
        name = "Chain of the Ancient Watcher",
        ownLevel = 272,
        previewMythicPlusLevel = 10,
        slot = "Neck",
        trackNote = "no track step draws 44",
        trackSteps = 0,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 17,
                        ITEM_MOD_MASTERY_RATING_SHORT = 9,
                        ITEM_MOD_STAMINA_SHORT = 8,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 272,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 272",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 174,
                        ITEM_MOD_MASTERY_RATING_SHORT = 91,
                        ITEM_MOD_STAMINA_SHORT = 1061,
                    },
                },
                journal = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 17,
                        ITEM_MOD_MASTERY_RATING_SHORT = 9,
                        ITEM_MOD_STAMINA_SHORT = 8,
                    },
                },
                link = "|cnIQ4:|Hitem:250461::::::::90:105::6:1:3524::::::|h[Chain of the Ancient Watcher]|h|r",
                rule = "kept",
            },
        },
        walkLevel = 44,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 16,
        difficultyID = 8,
        encounterID = 2485,
        instanceID = 1202,
        instanceName = "Ruby Life Pools",
        isRaid = false,
        itemID = 193763,
        link = "|cnIQ4:|Hitem:193763::::::::90:105::16:1:3524:1:28:1279:::::|h[Fireproof Drape]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:193763::::::::90:105::16:1:3524:1:28:1279:::::|h[Fireproof Drape]|h|r",
            previewLevel = 10,
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 305,
                [2] = false,
                [3] = 250,
                n = 3,
            },
        },
        name = "Fireproof Drape",
        ownLevel = 292,
        previewMythicPlusLevel = 10,
        slot = "Back",
        trackSteps = 2,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 292,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 292",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 35,
                        ITEM_MOD_HASTE_RATING_SHORT = 59,
                        ITEM_MOD_INTELLECT_SHORT = 72,
                        ITEM_MOD_STAMINA_SHORT = 1353,
                        RESISTANCE0_NAME = 60,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:193763::::::::90:105::16:1:3524:1:28:1279:::::|h[Fireproof Drape]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                link = "|cnIQ4:|Hitem:193763::::::::90:105::16:1:12837:1:28:1279:::::|h[Fireproof Drape]|h|r",
                rule = "track-replace",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:193763::::::::90:105::16:2:3524:12837:1:28:1279:::::|h[Fireproof Drape]|h|r",
                rule = "track-append",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:193763::::::::90:105::16:1:12841:1:28:1279:::::|h[Fireproof Drape]|h|r",
                rule = "track-replace",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 250,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 37,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_INTELLECT_SHORT = 81,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                        RESISTANCE0_NAME = 65,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:193763::::::::90:105::16:2:3524:12841:1:28:1279:::::|h[Fireproof Drape]|h|r",
                rule = "track-append",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
        },
        walkLevel = 305,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 5,
        difficultyID = 15,
        encounterID = 2871,
        instanceID = 1320,
        instanceName = "The Venomous Abyss",
        isRaid = true,
        itemID = 268234,
        link = "|cnIQ4:|Hitem:268234::::::::90:105::5:1:3524:1:28:7363:::::|h[Ruthless Slaughtergrips]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:268234::::::::90:105::5:1:3524:1:28:7363:::::|h[Ruthless Slaughtergrips]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 311,
                [2] = false,
                [3] = 219,
                n = 3,
            },
        },
        name = "Ruthless Slaughtergrips",
        ownLevel = 305,
        previewMythicPlusLevel = 10,
        slot = "Hands",
        trackSteps = 1,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 219,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 219",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 26,
                        ITEM_MOD_INTELLECT_SHORT = 48,
                        ITEM_MOD_MASTERY_RATING_SHORT = 55,
                        ITEM_MOD_STAMINA_SHORT = 754,
                        RESISTANCE0_NAME = 53,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 43,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 91,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 43,
                        ITEM_MOD_INTELLECT_SHORT = 108,
                        ITEM_MOD_MASTERY_RATING_SHORT = 91,
                        ITEM_MOD_STAMINA_SHORT = 2096,
                        RESISTANCE0_NAME = 91,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:268234::::::::90:105::5:1:3524:1:28:7363:::::|h[Ruthless Slaughtergrips]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 44,
                        ITEM_MOD_INTELLECT_SHORT = 114,
                        ITEM_MOD_MASTERY_RATING_SHORT = 93,
                        ITEM_MOD_STAMINA_SHORT = 2252,
                        RESISTANCE0_NAME = 95,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 44,
                        ITEM_MOD_INTELLECT_SHORT = 114,
                        ITEM_MOD_MASTERY_RATING_SHORT = 93,
                        ITEM_MOD_STAMINA_SHORT = 2252,
                        RESISTANCE0_NAME = 95,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                bonusID = 12843,
                journal = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 44,
                        ITEM_MOD_INTELLECT_SHORT = 114,
                        ITEM_MOD_MASTERY_RATING_SHORT = 93,
                        ITEM_MOD_STAMINA_SHORT = 2252,
                        RESISTANCE0_NAME = 95,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                link = "|cnIQ4:|Hitem:268234::::::::90:105::5:1:12843:1:28:7363:::::|h[Ruthless Slaughtergrips]|h|r",
                rule = "track-replace",
                step = 3,
                track = "Hero",
                trackLevel = 311,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 44,
                        ITEM_MOD_INTELLECT_SHORT = 114,
                        ITEM_MOD_MASTERY_RATING_SHORT = 93,
                        ITEM_MOD_STAMINA_SHORT = 2252,
                        RESISTANCE0_NAME = 95,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 44,
                        ITEM_MOD_INTELLECT_SHORT = 114,
                        ITEM_MOD_MASTERY_RATING_SHORT = 93,
                        ITEM_MOD_STAMINA_SHORT = 2252,
                        RESISTANCE0_NAME = 95,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                bonusID = 12843,
                journal = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 44,
                        ITEM_MOD_INTELLECT_SHORT = 114,
                        ITEM_MOD_MASTERY_RATING_SHORT = 93,
                        ITEM_MOD_STAMINA_SHORT = 2252,
                        RESISTANCE0_NAME = 95,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:268234::::::::90:105::5:2:3524:12843:1:28:7363:::::|h[Ruthless Slaughtergrips]|h|r",
                rule = "track-append",
                step = 3,
                track = "Hero",
                trackLevel = 311,
            },
        },
        walkLevel = 311,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 6,
        difficultyID = 16,
        encounterID = 2871,
        instanceID = 1320,
        instanceName = "The Venomous Abyss",
        isRaid = true,
        itemID = 268234,
        link = "|cnIQ4:|Hitem:268234::::::::90:105::6:1:3524:1:28:7362:::::|h[Ruthless Slaughtergrips]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:268234::::::::90:105::6:1:3524:1:28:7362:::::|h[Ruthless Slaughtergrips]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 324,
                [2] = false,
                [3] = 219,
                n = 3,
            },
        },
        name = "Ruthless Slaughtergrips",
        ownLevel = 318,
        previewMythicPlusLevel = 10,
        slot = "Hands",
        trackSteps = 1,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 219,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 219",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 26,
                        ITEM_MOD_INTELLECT_SHORT = 48,
                        ITEM_MOD_MASTERY_RATING_SHORT = 55,
                        ITEM_MOD_STAMINA_SHORT = 754,
                        RESISTANCE0_NAME = 53,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 318,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 318",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 45,
                        ITEM_MOD_INTELLECT_SHORT = 122,
                        ITEM_MOD_MASTERY_RATING_SHORT = 96,
                        ITEM_MOD_STAMINA_SHORT = 2440,
                        RESISTANCE0_NAME = 99,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 318,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 318",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 45,
                        ITEM_MOD_INTELLECT_SHORT = 122,
                        ITEM_MOD_MASTERY_RATING_SHORT = 96,
                        ITEM_MOD_STAMINA_SHORT = 2440,
                        RESISTANCE0_NAME = 99,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                link = "|cnIQ4:|Hitem:268234::::::::90:105::6:1:3524:1:28:7362:::::|h[Ruthless Slaughtergrips]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 46,
                        ITEM_MOD_INTELLECT_SHORT = 129,
                        ITEM_MOD_MASTERY_RATING_SHORT = 98,
                        ITEM_MOD_STAMINA_SHORT = 2615,
                        RESISTANCE0_NAME = 103,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 46,
                        ITEM_MOD_INTELLECT_SHORT = 129,
                        ITEM_MOD_MASTERY_RATING_SHORT = 98,
                        ITEM_MOD_STAMINA_SHORT = 2615,
                        RESISTANCE0_NAME = 103,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                bonusID = 12851,
                journal = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 46,
                        ITEM_MOD_INTELLECT_SHORT = 129,
                        ITEM_MOD_MASTERY_RATING_SHORT = 98,
                        ITEM_MOD_STAMINA_SHORT = 2615,
                        RESISTANCE0_NAME = 103,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                link = "|cnIQ4:|Hitem:268234::::::::90:105::6:1:12851:1:28:7362:::::|h[Ruthless Slaughtergrips]|h|r",
                rule = "track-replace",
                step = 3,
                track = "Myth",
                trackLevel = 324,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 46,
                        ITEM_MOD_INTELLECT_SHORT = 129,
                        ITEM_MOD_MASTERY_RATING_SHORT = 98,
                        ITEM_MOD_STAMINA_SHORT = 2615,
                        RESISTANCE0_NAME = 103,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 46,
                        ITEM_MOD_INTELLECT_SHORT = 129,
                        ITEM_MOD_MASTERY_RATING_SHORT = 98,
                        ITEM_MOD_STAMINA_SHORT = 2615,
                        RESISTANCE0_NAME = 103,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                bonusID = 12851,
                journal = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 46,
                        ITEM_MOD_INTELLECT_SHORT = 129,
                        ITEM_MOD_MASTERY_RATING_SHORT = 98,
                        ITEM_MOD_STAMINA_SHORT = 2615,
                        RESISTANCE0_NAME = 103,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                link = "|cnIQ4:|Hitem:268234::::::::90:105::6:2:3524:12851:1:28:7362:::::|h[Ruthless Slaughtergrips]|h|r",
                rule = "track-append",
                step = 3,
                track = "Myth",
                trackLevel = 324,
            },
        },
        walkLevel = 324,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 16,
        difficultyID = 8,
        encounterID = 2679,
        instanceID = 1304,
        instanceName = "Murder Row",
        isRaid = false,
        itemID = 251123,
        link = "|cnIQ4:|Hitem:251123::::::::90:105::16:1:3524:1:28:1279:::::|h[Nibbles' Training Rod]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:251123::::::::90:105::16:1:3524:1:28:1279:::::|h[Nibbles' Training Rod]|h|r",
            previewLevel = 10,
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 305,
                [2] = false,
                [3] = 108,
                n = 3,
            },
        },
        name = "Nibbles' Training Rod",
        ownLevel = 292,
        previewMythicPlusLevel = 10,
        slot = "2H Weapon",
        trackSteps = 2,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 292,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 292",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 101,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 47.91666793823242,
                        ITEM_MOD_HASTE_RATING_SHORT = 66,
                        ITEM_MOD_INTELLECT_SHORT = 567,
                        ITEM_MOD_STAMINA_SHORT = 2406,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:251123::::::::90:105::16:1:3524:1:28:1279:::::|h[Nibbles' Training Rod]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                link = "|cnIQ4:|Hitem:251123::::::::90:105::16:1:12837:1:28:1279:::::|h[Nibbles' Training Rod]|h|r",
                rule = "track-replace",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:251123::::::::90:105::16:2:3524:12837:1:28:1279:::::|h[Nibbles' Training Rod]|h|r",
                rule = "track-append",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:251123::::::::90:105::16:1:12841:1:28:1279:::::|h[Nibbles' Training Rod]|h|r",
                rule = "track-replace",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 108,
                        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 54.02777862548828,
                        ITEM_MOD_HASTE_RATING_SHORT = 70,
                        ITEM_MOD_INTELLECT_SHORT = 640,
                        ITEM_MOD_STAMINA_SHORT = 2794,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:251123::::::::90:105::16:2:3524:12841:1:28:1279:::::|h[Nibbles' Training Rod]|h|r",
                rule = "track-append",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
        },
        walkLevel = 305,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 5,
        difficultyID = 15,
        encounterID = 2827,
        instanceID = 1312,
        instanceName = "Midnight",
        isRaid = true,
        itemID = 250447,
        link = "|cnIQ4:|Hitem:250447::::::::90:105::5:1:3524::::::|h[Radiant Eversong Scepter]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:250447::::::::90:105::5:1:3524::::::|h[Radiant Eversong Scepter]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 44,
                [2] = false,
                [3] = 197,
                n = 3,
            },
        },
        name = "Radiant Eversong Scepter",
        ownLevel = 259,
        previewMythicPlusLevel = 10,
        slot = "Offhand",
        trackNote = "no track step draws 44",
        trackSteps = 0,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 5,
                        ITEM_MOD_INTELLECT_SHORT = 14,
                        ITEM_MOD_STAMINA_SHORT = 7,
                        ITEM_MOD_VERSATILITY = 4,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 259,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 259",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 41,
                        ITEM_MOD_INTELLECT_SHORT = 144,
                        ITEM_MOD_STAMINA_SHORT = 809,
                        ITEM_MOD_VERSATILITY = 30,
                    },
                },
                journal = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 5,
                        ITEM_MOD_INTELLECT_SHORT = 14,
                        ITEM_MOD_STAMINA_SHORT = 7,
                        ITEM_MOD_VERSATILITY = 4,
                    },
                },
                link = "|cnIQ4:|Hitem:250447::::::::90:105::5:1:3524::::::|h[Radiant Eversong Scepter]|h|r",
                rule = "kept",
            },
        },
        walkLevel = 44,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 6,
        difficultyID = 16,
        encounterID = 2827,
        instanceID = 1312,
        instanceName = "Midnight",
        isRaid = true,
        itemID = 250447,
        link = "|cnIQ4:|Hitem:250447::::::::90:105::6:1:3524::::::|h[Radiant Eversong Scepter]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:250447::::::::90:105::6:1:3524::::::|h[Radiant Eversong Scepter]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 44,
                [2] = false,
                [3] = 197,
                n = 3,
            },
        },
        name = "Radiant Eversong Scepter",
        ownLevel = 272,
        previewMythicPlusLevel = 10,
        slot = "Offhand",
        trackNote = "no track step draws 44",
        trackSteps = 0,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 5,
                        ITEM_MOD_INTELLECT_SHORT = 14,
                        ITEM_MOD_STAMINA_SHORT = 7,
                        ITEM_MOD_VERSATILITY = 4,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 272,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 272",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 44,
                        ITEM_MOD_INTELLECT_SHORT = 162,
                        ITEM_MOD_STAMINA_SHORT = 943,
                        ITEM_MOD_VERSATILITY = 32,
                    },
                },
                journal = {
                    detailedLevel = {
                        [1] = 44,
                        [2] = false,
                        [3] = 197,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 44",
                    stats = {
                        ITEM_MOD_HASTE_RATING_SHORT = 5,
                        ITEM_MOD_INTELLECT_SHORT = 14,
                        ITEM_MOD_STAMINA_SHORT = 7,
                        ITEM_MOD_VERSATILITY = 4,
                    },
                },
                link = "|cnIQ4:|Hitem:250447::::::::90:105::6:1:3524::::::|h[Radiant Eversong Scepter]|h|r",
                rule = "kept",
            },
        },
        walkLevel = 44,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 16,
        difficultyID = 8,
        encounterID = 2769,
        instanceID = 1309,
        instanceName = "The Blinding Vale",
        isRaid = false,
        itemID = 250254,
        link = "|cnIQ4:|Hitem:250254::::::::90:105::16:1:3524:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:250254::::::::90:105::16:1:3524:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
            previewLevel = 10,
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 305,
                [2] = false,
                [3] = 108,
                n = 3,
            },
        },
        name = "Seed of Radiant Hope",
        ownLevel = 292,
        previewMythicPlusLevel = 10,
        slot = "Trinket",
        trackSteps = 2,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 292,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 292",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 121,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:250254::::::::90:105::16:1:3524:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 5/6",
                },
                link = "|cnIQ4:|Hitem:250254::::::::90:105::16:1:12837:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
                rule = "track-replace",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12837,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:250254::::::::90:105::16:2:3524:12837:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
                rule = "track-append",
                step = 5,
                track = "Champion",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:250254::::::::90:105::16:1:12841:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
                rule = "track-replace",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Champion 1/6",
                },
                bonusID = 12841,
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 108,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        ITEM_MOD_INTELLECT_SHORT = 137,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:250254::::::::90:105::16:2:3524:12841:1:28:1279:::::|h[Seed of Radiant Hope]|h|r",
                rule = "track-append",
                step = 1,
                track = "Hero",
                trackLevel = 305,
            },
        },
        walkLevel = 305,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 5,
        difficultyID = 15,
        encounterID = 2871,
        instanceID = 1320,
        instanceName = "The Venomous Abyss",
        isRaid = true,
        itemID = 268252,
        link = "|cnIQ4:|Hitem:268252::::::::90:105::5:1:3524:1:28:7363:::::|h[Apex Brute's Claw Ring]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:268252::::::::90:105::5:1:3524:1:28:7363:::::|h[Apex Brute's Claw Ring]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 311,
                [2] = false,
                [3] = 219,
                n = 3,
            },
        },
        name = "Apex Brute's Claw Ring",
        ownLevel = 305,
        previewMythicPlusLevel = 10,
        slot = "Finger",
        trackSteps = 1,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 219,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 219",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 132,
                        ITEM_MOD_HASTE_RATING_SHORT = 26,
                        ITEM_MOD_STAMINA_SHORT = 565,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 283,
                        ITEM_MOD_HASTE_RATING_SHORT = 56,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 305,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 305",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 283,
                        ITEM_MOD_HASTE_RATING_SHORT = 56,
                        ITEM_MOD_STAMINA_SHORT = 1572,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:268252::::::::90:105::5:1:3524:1:28:7363:::::|h[Apex Brute's Claw Ring]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 295,
                        ITEM_MOD_HASTE_RATING_SHORT = 59,
                        ITEM_MOD_STAMINA_SHORT = 1689,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 295,
                        ITEM_MOD_HASTE_RATING_SHORT = 59,
                        ITEM_MOD_STAMINA_SHORT = 1689,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                bonusID = 12843,
                journal = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 295,
                        ITEM_MOD_HASTE_RATING_SHORT = 59,
                        ITEM_MOD_STAMINA_SHORT = 1689,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                link = "|cnIQ4:|Hitem:268252::::::::90:105::5:1:12843:1:28:7363:::::|h[Apex Brute's Claw Ring]|h|r",
                rule = "track-replace",
                step = 3,
                track = "Hero",
                trackLevel = 311,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 295,
                        ITEM_MOD_HASTE_RATING_SHORT = 59,
                        ITEM_MOD_STAMINA_SHORT = 1689,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 295,
                        ITEM_MOD_HASTE_RATING_SHORT = 59,
                        ITEM_MOD_STAMINA_SHORT = 1689,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                bonusID = 12843,
                journal = {
                    detailedLevel = {
                        [1] = 311,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 311",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 295,
                        ITEM_MOD_HASTE_RATING_SHORT = 59,
                        ITEM_MOD_STAMINA_SHORT = 1689,
                    },
                    upgradeLevelLine = "Upgrade Level: Hero 1/6",
                },
                link = "|cnIQ4:|Hitem:268252::::::::90:105::5:2:3524:12843:1:28:7363:::::|h[Apex Brute's Claw Ring]|h|r",
                rule = "track-append",
                step = 3,
                track = "Hero",
                trackLevel = 311,
            },
        },
        walkLevel = 311,
    },
    {
        bonusIDs = {
            3524,
        },
        context = 6,
        difficultyID = 16,
        encounterID = 2871,
        instanceID = 1320,
        instanceName = "The Venomous Abyss",
        isRaid = true,
        itemID = 268252,
        link = "|cnIQ4:|Hitem:268252::::::::90:105::6:1:3524:1:28:7362:::::|h[Apex Brute's Claw Ring]|h|r",
        live = {
            found = true,
            link = "|cnIQ4:|Hitem:268252::::::::90:105::6:1:3524:1:28:7362:::::|h[Apex Brute's Claw Ring]|h|r",
            sameAsKept = true,
            walkDetailedLevel = {
                [1] = 324,
                [2] = false,
                [3] = 219,
                n = 3,
            },
        },
        name = "Apex Brute's Claw Ring",
        ownLevel = 318,
        previewMythicPlusLevel = 10,
        slot = "Finger",
        trackSteps = 1,
        variants = {
            {
                after = {
                    detailedLevel = {
                        [1] = 219,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 219",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 132,
                        ITEM_MOD_HASTE_RATING_SHORT = 26,
                        ITEM_MOD_STAMINA_SHORT = 565,
                    },
                },
                before = {
                    detailedLevel = {
                        [1] = 318,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 318",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 308,
                        ITEM_MOD_HASTE_RATING_SHORT = 61,
                        ITEM_MOD_STAMINA_SHORT = 1830,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                journal = {
                    detailedLevel = {
                        [1] = 318,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 318",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 308,
                        ITEM_MOD_HASTE_RATING_SHORT = 61,
                        ITEM_MOD_STAMINA_SHORT = 1830,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                link = "|cnIQ4:|Hitem:268252::::::::90:105::6:1:3524:1:28:7362:::::|h[Apex Brute's Claw Ring]|h|r",
                rule = "kept",
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 319,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_STAMINA_SHORT = 1962,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 319,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_STAMINA_SHORT = 1962,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                bonusID = 12851,
                journal = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        ITEM_MOD_CRIT_RATING_SHORT = 319,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_STAMINA_SHORT = 1962,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                link = "|cnIQ4:|Hitem:268252::::::::90:105::6:1:12851:1:28:7362:::::|h[Apex Brute's Claw Ring]|h|r",
                rule = "track-replace",
                step = 3,
                track = "Myth",
                trackLevel = 324,
            },
            {
                after = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 319,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_STAMINA_SHORT = 1962,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 3/6",
                },
                before = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 319,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_STAMINA_SHORT = 1962,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                bonusID = 12851,
                journal = {
                    detailedLevel = {
                        [1] = 324,
                        [2] = false,
                        [3] = 219,
                        n = 3,
                    },
                    itemLevelLine = "Item Level 324",
                    stats = {
                        EMPTY_SOCKET_PRISMATIC = 1,
                        ITEM_MOD_CRIT_RATING_SHORT = 319,
                        ITEM_MOD_HASTE_RATING_SHORT = 63,
                        ITEM_MOD_STAMINA_SHORT = 1962,
                    },
                    upgradeLevelLine = "Upgrade Level: Myth 1/6",
                },
                link = "|cnIQ4:|Hitem:268252::::::::90:105::6:2:3524:12851:1:28:7362:::::|h[Apex Brute's Claw Ring]|h|r",
                rule = "track-append",
                step = 3,
                track = "Myth",
                trackLevel = 324,
            },
        },
        walkLevel = 324,
    },
}

-- Registers every REBUILT link (`track-replace`, `track-append`) on a stub
-- world as the client answered it - GetItemInfo's name, link, quality and
-- level, GetDetailedItemLevelInfo's three returns and GetItemStats' table - but
-- only when its three reads (before, journal, after) answered the same level:
-- every rebuilt link in the transcript did, and a read that follows the view
-- is not one a stub can answer with one value. The kept links are not
-- registered: their reads followed the Adventure Guide's view (292 before and
-- 305 during and after for a keystone link, 305 before and 219 after for a
-- raid link) and itemstats-real.lua already holds them as that morning's
-- client read them.
--
-- The socket count is the transcript's `EMPTY_SOCKET_PRISMATIC`: the capture
-- did not ask GetItemNumSockets, and on all 80 items of the 2026-10-01 09:26
-- transcript the two answered the same count (ARCHITECTURE.md section 7, E-0f).
-- An item already on the world is merged into, never replaced.
function F.install(world)
    for _, candidate in ipairs(F.CANDIDATES) do
        for _, variant in ipairs(candidate.variants) do
            local b, j, a = variant.before, variant.journal, variant.after
            local level = b and b.detailedLevel and b.detailedLevel[1]
            if
                variant.rule ~= "kept"
                and level
                and j.detailedLevel[1] == level
                and a.detailedLevel[1] == level
            then
                local entry = world.items[variant.link] or {}
                entry.info = { candidate.name, variant.link, 4, level, n = 18 }
                entry.level = level
                entry.detailed = b.detailedLevel
                world.items[variant.link] = entry
                world.itemStats[variant.link] = b.stats
                world.itemSockets[variant.link] = b.stats.EMPTY_SOCKET_PRISMATIC or 0
                world.itemDataCached[candidate.itemID] = true
            end
        end
    end
end

-- The variant of a candidate by rule and bonus ID (nil for `kept`).
function F.variant(candidate, rule, bonusID)
    for _, variant in ipairs(candidate.variants) do
        if variant.rule == rule and variant.bonusID == bonusID then
            return variant
        end
    end
    return nil
end

return F
