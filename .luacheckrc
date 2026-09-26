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
-- StaticPopupDialogs is FrameXML's table of dialog definitions, keyed by name;
-- adding an entry to it is how every addon (and Blizzard's own GameDialogDefs)
-- registers a popup, so it is mutated rather than only read (M3-16a, WKE-581).
globals = {
    "LootpathToggle",
    "SLASH_LOOTPATH1",
    "SlashCmdList",
    "StaticPopupDialogs",
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
    -- The upgrade vendor (M3-17, WKE-574). Only in `Captures.lua`, and only
    -- the seven reads and one setter that file names.
    "C_ItemUpgrade",
    "C_MythicPlus",
    "C_Secrets",
    -- Blizzard's replacement for the GetSpecialization/GetSpecializationInfo
    -- pair, which its own annotations mark deprecated; MainFrame asks for this
    -- first and the two globals second, so both are listed.
    "C_SpecializationInfo",
    "C_Texture",
    "C_Timer",
    "C_WeeklyRewards",
    "Enum",
    -- Blizzard API, globals
    "CreateFrame",
    -- UX-5a (WKE-634): the Run Tile's shade is a gradient, and its two colours
    -- are colorRGBAs (Blizzard_SharedXML/Color.lua:25, read under .luals/).
    "CreateColor",
    -- The 11.0 ScrollBox, from Blizzard_SharedXML/Shared/Scroll/ and
    -- Blizzard_SharedXML/DataProvider.lua (both read under .luals/): the data
    -- provider, the linear list view, and the helper that registers a box with
    -- its scroll bar. M5-3 draws the Upgrade Map's two lists with them.
    "CreateDataProvider",
    "CreateScrollBoxListLinearView",
    "ScrollUtil",
    -- The cursor half of equipping by bag and slot (E-1, WKE-604). UI/EquipPanel.lua
    -- names all four functions that path may call; these two are the globals,
    -- read under .luals/ in GameCursorDocumentation.lua (ClearCursor :2-3,
    -- EquipCursorItem :30-32).
    "ClearCursor",
    "EquipCursorItem",
    -- E-1a (WKE-605): where an EMPTY slot's row equips into, asked of the
    -- client rather than read off a table of ours. GetInventoryItemsForSlot is
    -- Blizzard's own paper-doll flyout source (Wiki.lua:5064-5067,
    -- PaperDollFrame.lua:2064-2066) and EquipmentManager_GetLocationData
    -- unpacks what it answers with (Shared/EquipmentManager.lua:1-29); the two
    -- INVSLOT bounds are Constants.lua:153 and :172. The FrameXML function is
    -- called through a type check, so a client without it refuses the row
    -- rather than erroring.
    "EquipmentManager_GetLocationData",
    "GetInventoryItemsForSlot",
    "INVSLOT_FIRST_EQUIPPED",
    "INVSLOT_LAST_EQUIPPED",
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
    -- InCombatLockdown before it calls this. Since M3-16a (WKE-581) it is also
    -- refused outside the player's own hardware event, which is why the
    -- refresh's other path goes through StaticPopup_Show instead.
    "ReloadUI",
    "StaticPopup_Show",
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
    -- The tooltip a clicked chat link opens (R-2c, WKE-646; ItemRef.xml:5).
    "ItemRefTooltip",
    -- The minimap frame the launcher hangs off (M5-2); read through a nil check,
    -- because a client without one is a client with no minimap button.
    "Minimap",
    "MinimalSliderWithSteppersMixin",
    -- The item widget's four FrameXML names (M5-1, WKE-550). Each is reached
    -- through a type check or a pcall, because a client without one must still
    -- draw a row: ColorManager and ITEM_QUALITY_COLORS are the quality colour
    -- Blizzard's own item buttons read, RETRIEVING_ITEM_INFO is the string its
    -- journal shows while an item loads, and GameTooltip_ShowCompareItem is
    -- the shopping compare.
    "ColorManager",
    "ITEM_QUALITY_COLORS",
    "RETRIEVING_ITEM_INFO",
    "GameTooltip_ShowCompareItem",
    "Settings",
    -- Blizzard's tooltip data handler, from
    -- Blizzard_SharedXML/Tooltip/TooltipDataHandler.lua and TooltipUtil.lua
    -- (both read under .luals/). R-0's tooltip measurement (WKE-561) names
    -- AddTooltipPostCall and GetDisplayedItem and nothing else; both are asked
    -- for through a type check, so a client without them still loads. These two
    -- R-2 (WKE-563) kept them: the tooltip block is registered through the
    -- first and reads the hovered item through the second.
    "TooltipDataProcessor",
    "TooltipUtil",
    -- Blizzard's own bag frames and the hook that goes on them (R-2's Blizzard
    -- bag adapter). ContainerFrameMixin and ContainerFrameUtil_Enumerate-
    -- ContainerFrames are Blizzard_UIPanels_Game's, read under .luals/ in
    -- Mainline/ContainerFrame.lua (lines 1030, 522, 759 and 386); both are
    -- reached through a type check, so a client without them still loads.
    "ContainerFrameMixin",
    "ContainerFrameUtil_EnumerateContainerFrames",
    "hooksecurefunc",
    -- **Not Blizzard's.** Baganator is a third-party addon that may or may not
    -- be loaded, and its global is read ONLY behind
    -- `type(Baganator) == "table"` in UI/Bags/Baganator.lua. It is listed here
    -- because the gate cannot otherwise tell a guarded optional global from a
    -- typo; nothing in Lootpath requires it to exist.
    "Baganator",
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
    -- RETRIEVING_ITEM_INFO is the one client global a spec names directly: the
    -- item line draws Blizzard's own string, so the test asserts Blizzard's own
    -- string rather than a copy of it.
    -- E-1a (WKE-605): the stub models Blizzard's packed item location, so it
    -- names the four constants that packing is made of (Constants.lua:146-149)
    -- and the client's `bit` library those lines use.
    read_globals = {
        "RETRIEVING_ITEM_INFO",
        "bit",
        "ITEM_INVENTORY_LOCATION_PLAYER",
        "ITEM_INVENTORY_LOCATION_BAGS",
        "ITEM_INVENTORY_LOCATION_BANK",
        "ITEM_INVENTORY_BAG_BIT_OFFSET",
    },
}
