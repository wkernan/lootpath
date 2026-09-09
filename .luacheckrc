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

-- Globals the addon defines (its slash command) or mutates. UISpecialFrames is
-- FrameXML's list of frame NAMES that Escape closes (Blizzard_UIParentPanelManager
-- iterates it); appending the main frame's name is how a panel opts in, so this
-- one is mutated rather than only read.
-- LootpathToggle is the AddOn Compartment's entry point: `## AddonCompartmentFunc`
-- names a GLOBAL function, which Blizzard's AddonCompartmentMixin looks up in
-- _G, so this global is defined rather than only read.
globals = {
    "LootpathToggle",
    "SLASH_LOOTPATH1",
    "SlashCmdList",
    "UISpecialFrames",
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
    "C_CurrencyInfo",
    "C_DateAndTime",
    "C_EncounterJournal",
    "C_Item",
    "C_MythicPlus",
    "C_Secrets",
    -- Blizzard's replacement for the GetSpecialization/GetSpecializationInfo
    -- pair, which its own annotations mark deprecated; MainFrame asks for this
    -- first and the two globals second, so both are listed.
    "C_SpecializationInfo",
    "C_Timer",
    "C_WeeklyRewards",
    "Enum",
    -- Blizzard API, globals
    "CreateFrame",
    "GetBuildInfo",
    "GetCurrentRegion",
    "GetCurrentRegionName",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "GetLocale",
    "GetCursorPosition",
    "GetRealmName",
    "GetSpecialization",
    "GetSpecializationInfo",
    "InCombatLockdown",
    "ItemLocation",
    -- Protected in combat, which is why Companion.Refresh checks
    -- InCombatLockdown before it calls this.
    "ReloadUI",
    "UnitClass",
    "UnitLevel",
    "UnitName",
    "UnitRace",
    -- Encounter Journal globals (Modules/Journal.lua names every one it calls;
    -- they are not in Blizzard's generated docs, but the 12.1.0 client lists
    -- all of them - transcript 2026-09-05, capture env, globals.EJ)
    "EJ_GetCurrentTier",
    "EJ_GetDifficulty",
    "EJ_GetEncounterInfo",
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
    "CLASS_ICON_TCOORDS",
    "GameTooltip",
    -- The minimap frame the launcher hangs off (M5-2); read through a nil check,
    -- because a client without one is a client with no minimap button.
    "Minimap",
    "MinimalSliderWithSteppersMixin",
    "Settings",
    "UIParent",
    "DifficultyUtil",
    "GetDifficultyInfo",
    -- Blizzard_SharedXML/SharedUIPanelTemplates.lua, which PanelTabButtonTemplate
    -- comes with; MainFrame calls both through a type check so a client without
    -- them still tabs.
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
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
