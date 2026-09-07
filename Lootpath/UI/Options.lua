-- Lootpath/UI/Options.lua (M2-2, WKE-520)
-- The options page, through the modern Settings API. InterfaceOptions_AddCategory
-- was removed in 10.0 (decision 2026-09-05), and this is its replacement.
--
-- One setting for now: which content type's verdict the panels show when both a
-- Dungeon export and a Raid export have been pasted. The values are QE Live's
-- own strings, not labels of our own - `src/globalTypes.d.ts` declares
-- `contentTypes = "Raid" | "Dungeon"` and the export carries one of them
-- verbatim, so the setting is compared to `verdict.contentType` with no
-- translation in between.
--
-- Every function used here is named in Blizzard's shipped Blizzard_Settings.lua
-- (read under .luals on 2026-09-06):
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterProxySetting(categoryTbl, variable, variableType, name,
--                                 defaultValue, getValue, setValue)
--   Settings.CreateControlTextContainer() -> container:Add(value, label, tooltip)
--   Settings.CreateDropdown(category, setting, options, tooltip)
--   Settings.RegisterAddOnCategory(category)
--   Settings.OpenToCategory(categoryID)

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.Options = {}
local Options = UI.Options

Options.VARIABLE = "LootpathContentType"
Options.LABEL = "Content type"
Options.TOOLTIP = "Which QE Live export the panels read when you have pasted more than one. "
    .. 'QE Live calls the Mythic+ side "Dungeon"; the value is compared to the export\'s own contentType.'

Options.CHOICE_LABEL = {
    Dungeon = "Dungeon (Mythic+)",
    Raid = "Raid",
}

function Options.Get()
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    return (settings and settings.contentType) or ns.DB_DEFAULTS.profile.settings.contentType
end

function Options.Set(value)
    if type(value) ~= "string" or value == "" then
        return
    end
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.contentType = value
    end
    if UI.Refresh then
        UI.Refresh()
    end
end

-- Registers the page. Returns false (never an error) when the client has no
-- Settings API, so a missing function is a missing options page and not a
-- broken addon.
function Options.Register()
    if Options.category then
        return true
    end
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        return false
    end
    local category = Settings.RegisterVerticalLayoutCategory("Lootpath")
    local setting = Settings.RegisterProxySetting(
        category,
        Options.VARIABLE,
        Settings.VarType.String,
        Options.LABEL,
        ns.DB_DEFAULTS.profile.settings.contentType,
        Options.Get,
        Options.Set
    )
    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs(ns.QEImport.CONTENT_TYPES) do
            container:Add(value, Options.CHOICE_LABEL[value] or value, Options.TOOLTIP)
        end
        return container:GetData()
    end, Options.TOOLTIP)
    Settings.RegisterAddOnCategory(category)
    Options.category = category
    Options.setting = setting
    return true
end

function UI.OpenOptions()
    if not Options.Register() then
        ns.Log("this client has no Settings API, so there is no options page.")
        return false
    end
    if Settings.OpenToCategory and Options.category.GetID then
        Settings.OpenToCategory(Options.category:GetID())
        return true
    end
    return false
end
