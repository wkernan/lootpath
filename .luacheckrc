-- luacheck configuration. Lua 5.1 (the client's dialect) with every WoW global
-- the addon touches listed explicitly. No allow_defined_top and no wildcard
-- std: an undeclared global is a real failure, which is the point of the gate.
std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
    "Lootpath/Libs/**",
    "spec/fixtures/**", -- raw SavedVariables transcripts and QE exports, never linted or formatted
    ".luals/**",
    ".release/**",
    ".lua/**",
    ".luarocks/**",
}

-- Globals the addon defines (its slash command) or mutates.
globals = {
    "SLASH_LOOTPATH1",
    "SlashCmdList",
}

read_globals = {
    -- Lua extensions the client adds
    "date",
    "time",
    "debugprofilestop",
    "issecretvalue",
    "issecrettable",
    -- Blizzard API, by namespace
    "C_AddOns",
    "C_Bank",
    "C_ChallengeMode",
    "C_Container",
    "C_DateAndTime",
    "C_EncounterJournal",
    "C_Item",
    "C_MythicPlus",
    "C_Secrets",
    "C_Timer",
    "C_WeeklyRewards",
    "Enum",
    -- Blizzard API, globals
    "CreateFrame",
    "GetBuildInfo",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "GetLocale",
    "GetRealmName",
    "GetSpecialization",
    "GetSpecializationInfo",
    "InCombatLockdown",
    "ItemLocation",
    "UnitClass",
    "UnitName",
    -- Encounter Journal globals (Modules/Journal.lua names every one it calls;
    -- they are not in Blizzard's generated docs, but the 12.1.0 client lists
    -- all of them - transcript 2026-09-05, capture env, globals.EJ)
    "EJ_GetCurrentTier",
    "EJ_GetDifficulty",
    "EJ_GetEncounterInfoByIndex",
    "EJ_GetInstanceByIndex",
    "EJ_GetInstanceForMap",
    "EJ_GetInstanceInfo",
    "EJ_GetLootFilter",
    "EJ_GetNumLoot",
    "EJ_GetNumTiers",
    "EJ_GetTierInfo",
    "EJ_InstanceIsRaid",
    "EJ_IsLootListOutOfDate",
    "EJ_IsValidInstanceDifficulty",
    "EJ_ResetLootFilter",
    "EJ_SelectInstance",
    "EJ_SelectTier",
    "EJ_SetDifficulty",
    "EJ_SetLootFilter",
    -- FrameXML
    "BankFrame",
    "DifficultyUtil",
    "WeeklyRewardsFrame",
    "INVSLOT_FIRST_EQUIPPED",
    "INVSLOT_LAST_EQUIPPED",
    "NUM_BAG_SLOTS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    -- Libraries
    "LibStub",
}

files["spec/**/*.lua"] = {
    std = "lua51+busted",
    -- Specs reach the stubbed client through _G; the stub installs via _G too.
}
