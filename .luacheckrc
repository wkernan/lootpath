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
    -- FrameXML
    "BankFrame",
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
