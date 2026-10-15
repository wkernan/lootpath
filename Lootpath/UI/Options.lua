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
-- and, added in M5-2 (WKE-551, read under .luals on 2026-09-09):
--   Settings.CreateSliderOptions(minValue, maxValue, rate) -> options, whose
--     `steps` is (maxValue - minValue) / rate and whose SetLabelFormatter takes
--     a MinimalSliderWithSteppersMixin.Label value
--   Settings.CreateSlider(category, setting, options, tooltip)
--   Settings.CreateCheckbox(category, setting, tooltip)

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.Options = {}
local Options = UI.Options

Options.VARIABLE = "LootpathContentType"
Options.LABEL = "Content type"
Options.TOOLTIP = "Which export the panels read when you have pasted more than one. "
    .. 'The Mythic+ side is called "Dungeon"; the value is compared to the export\'s own contentType.'

Options.CHOICE_LABEL = {
    Dungeon = "Dungeon (Mythic+)",
    Raid = "Raid",
}

-- The second setting (C-6, WKE-540): which named scenario the
-- Vault tab's "the pick" line follows. The owner can point the highlight at any
-- of them, and the tab says on the line which question the pick came from
-- whichever it is. It changes the HIGHLIGHT and nothing else - every stored
-- scenario is shown on the option, whatever this is set to, and `asOffered`
-- stays first in that list so "nothing beats your set as offered" is never
-- hidden.
--
-- `thisWeek` by DEFAULT since M3-13 (WKE-548; decision 2026-09-09, §7), because
-- it is the question the vault poses: one option taken, that option upgraded,
-- the one Catalyst charge spent. `asOffered` was the default under C-6 and is
-- still what Equip Now and the Upgrade Map read - but on the Vault tab it
-- answers "what if I take this and change nothing", and nobody with a charge and
-- a pile of crests is asking that. When no `thisWeek` answer is stored the
-- highlight falls back to `asOffered` and says so on its own line.
Options.SCENARIO_VARIABLE = "LootpathVaultScenario"
Options.SCENARIO_LABEL = "Vault highlight"
Options.SCENARIO_TOOLTIP = "Which what-if answer the Vault tab's pick follows. "
    .. "Every scenario the companion has run is listed on each option whatever this is set to; "
    .. 'Equip Now and the Upgrade Map always read "as offered".'

Options.SCENARIO_CHOICE_LABEL = {
    asOffered = "As offered (what the vault gives you)",
    catalyzed = "Catalyzed (through the Catalyst)",
    thisWeek = "This week (take one option, upgrade it, use the charge once)",
    maxed = "Everything upgraded (Catalyst and full upgrade tracks)",
}

-- The two chrome settings (M5-2, WKE-551). The scale is applied with
-- `frame:SetScale` on the window and nothing else, so it never fights the
-- player's own UI scale; "compact rows" is stored here and read by the item
-- line M5-1 builds, which is why it changes nothing on screen in this issue.
--
-- The slider's bounds are Lootpath's own and deliberately narrow: this is a
-- window, not a HUD, and a scale that makes the verdict unreadable or pushes
-- the frame off the edge is not a setting worth offering. The step is 0.05.
Options.SCALE_VARIABLE = "LootpathScale"
Options.SCALE_LABEL = "Window scale"
Options.SCALE_TOOLTIP = "How large the Lootpath window is drawn, on top of your own UI scale."
Options.SCALE_MIN = 0.7
Options.SCALE_MAX = 1.3
Options.SCALE_STEP = 0.05

-- M5-5 (WKE-661): the window's size, set by dragging its corner and kept
-- here beside the scale as `windowWidth` / `windowHeight`. Nil is the default
-- size (ns.UI.WIDTH x ns.UI.HEIGHT), which is also the smallest the window may
-- be. The one word the page gains is the reset button's.
Options.RESET_SIZE_LABEL = "Reset size"

Options.COMPACT_VARIABLE = "LootpathCompactRows"
Options.COMPACT_LABEL = "Compact rows"
Options.COMPACT_TOOLTIP = "Draw the item rows in a shorter line, so more of them fit without scrolling."

-- Explain (R-3, WKE-564; docs/ROADS-UX.md principle 11). One plain sentence
-- under the first visible use of a system word in an expanded slot on the
-- Upgrade Map, in the note colour. Off by default: the default is dense, and a
-- sentence the reader already knows is noise. Each sentence states only what
-- the client says or what the rating names - never a cadence and never a
-- promise - which is why the table lives beside the rows that show it
-- (`ns.UpgradeMapPanel.EXPLAIN`) rather than here.
Options.EXPLAIN_VARIABLE = "LootpathExplain"
Options.EXPLAIN_LABEL = "Explain"
Options.EXPLAIN_TOOLTIP = "Add one plain sentence under the first use of a system word - track, crest, Catalyst, "
    .. "Bountiful, spark, picks - in an expanded slot on the Upgrade Map."

function Options.Get()
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    return (settings and settings.contentType) or ns.DB_DEFAULTS.profile.settings.contentType
end

-- Clamped on the way out as well as on the way in: a SavedVariables file edited
-- by hand, or written by a build with different bounds, must not be able to
-- scale the window off the screen.
function Options.GetScale()
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    local scale = settings and tonumber(settings.scale)
    if not scale then
        return ns.DB_DEFAULTS.profile.settings.scale
    end
    return math.min(Options.SCALE_MAX, math.max(Options.SCALE_MIN, scale))
end

function Options.SetScale(value)
    value = tonumber(value)
    if not value then
        return nil
    end
    value = math.min(Options.SCALE_MAX, math.max(Options.SCALE_MIN, value))
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.scale = value
    end
    if UI.frame then
        UI.frame:SetScale(value)
    end
    return value
end

-- The stored size, clamped to the bounds the window has now (never trusted:
-- a SavedVariables file edited by hand, or written on a larger screen, must
-- not be able to make the window smaller than today's or larger than the
-- screen). With nothing stored, the default size.
function Options.GetWindowSize(frame)
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    local width = settings and tonumber(settings.windowWidth) or UI.WIDTH
    local height = settings and tonumber(settings.windowHeight) or UI.HEIGHT
    return UI.ClampWindowSize(width, height, UI.WindowBounds(frame or UI.frame))
end

-- Stores a size, clamped the same way, as whole points. Returns what it kept.
function Options.SetWindowSize(width, height, frame)
    width, height = UI.ClampWindowSize(width, height, UI.WindowBounds(frame or UI.frame))
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.windowWidth = width
        ns.db.profile.settings.windowHeight = height
    end
    return width, height
end

-- `Reset size`: the stored size is forgotten, the window goes back to the
-- default, and the open tab is laid out again at it.
function Options.ResetSize()
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.windowWidth = nil
        ns.db.profile.settings.windowHeight = nil
    end
    if UI.frame then
        UI.frame:SetSize(UI.WIDTH, UI.HEIGHT)
        UI.Relayout(UI.frame)
    end
    return UI.WIDTH, UI.HEIGHT
end

function Options.GetCompactRows()
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    if settings and settings.compactRows ~= nil then
        return settings.compactRows and true or false
    end
    return ns.DB_DEFAULTS.profile.settings.compactRows
end

function Options.SetCompactRows(value)
    value = value and true or false
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.compactRows = value
    end
    if UI.Refresh then
        UI.Refresh()
    end
    return value
end

function Options.GetExplain()
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    if settings and settings.explain ~= nil then
        return settings.explain and true or false
    end
    return ns.DB_DEFAULTS.profile.settings.explain
end

function Options.SetExplain(value)
    value = value and true or false
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.explain = value
    end
    if UI.Refresh then
        UI.Refresh()
    end
    return value
end

function Options.GetVaultScenario()
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    return (settings and settings.vaultScenario) or ns.DB_DEFAULTS.profile.settings.vaultScenario
end

-- R-2o (WKE-698): the highlighted scenario is read when the roads are BUILT
-- (`UpgradeMapPanel.Gather` resolves it through `VaultPanel.HighlightScenario`),
-- so a change rebuilds them exactly as `Options.Set` does for the content type
-- below (R-2m): at once, before the redraw, deferred by `Rebuild` itself in
-- combat, and not at all when the value is the one already stored. The rule,
-- named once in ARCHITECTURE.md §7: every setting the roads read at build time
-- rebuilds them when it changes. This function is the one writer - the Vault
-- tab's dropdown and the Settings page both call it.
function Options.SetVaultScenario(value)
    if type(value) ~= "string" or value == "" then
        return
    end
    local changed = value ~= Options.GetVaultScenario()
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.vaultScenario = value
    end
    if changed and ns.RoadsCache and ns.RoadsCache.Rebuild then
        ns.RoadsCache.Rebuild()
    end
    if UI.Refresh then
        UI.Refresh()
    end
end

-- R-2m (WKE-696): the content type is read when the roads are BUILT
-- (`RoadsCache.Gather`, through the panel's own resolvers), and the hover, the
-- bag mark and Equip Now's crest line read that built map. A switch therefore
-- rebuilds it, or the tooltip and the mark keep answering for the old content
-- until the next bag change or reload - what the owner saw on 2026-10-07 while
-- Equip Now's rows (matched fresh on every refresh) followed the switch.
-- Rebuilt HERE, before the redraw, and not through the debounced `Invalidate`:
-- the redraw below reads the map for Equip Now's pending crests, and a rebuild
-- half a second later would leave that line on the old content until something
-- else redrew the tab. A switch is one click, not a burst of bag events, so
-- there is nothing to fold. `Rebuild` refuses in combat and defers to the end
-- of it, as for every other caller. A set to the value already stored changes
-- no answer and rebuilds nothing.
function Options.Set(value)
    if type(value) ~= "string" or value == "" then
        return
    end
    local changed = value ~= Options.Get()
    if ns.db and ns.db.profile and ns.db.profile.settings then
        ns.db.profile.settings.contentType = value
    end
    if changed and ns.RoadsCache and ns.RoadsCache.Rebuild then
        ns.RoadsCache.Rebuild()
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
    local scenario = Settings.RegisterProxySetting(
        category,
        Options.SCENARIO_VARIABLE,
        Settings.VarType.String,
        Options.SCENARIO_LABEL,
        ns.DB_DEFAULTS.profile.settings.vaultScenario,
        Options.GetVaultScenario,
        Options.SetVaultScenario
    )
    Settings.CreateDropdown(category, scenario, function()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs(ns.QEImport.SCENARIOS) do
            container:Add(value, Options.SCENARIO_CHOICE_LABEL[value] or value, Options.SCENARIO_TOOLTIP)
        end
        return container:GetData()
    end, Options.SCENARIO_TOOLTIP)
    -- The chrome pair (M5-2). Both are guarded on the control builders rather
    -- than on the category: a client that has RegisterProxySetting but not
    -- CreateSlider keeps the dropdowns and loses only the slider.
    if Settings.CreateSlider and Settings.CreateSliderOptions then
        local scaleSetting = Settings.RegisterProxySetting(
            category,
            Options.SCALE_VARIABLE,
            Settings.VarType.Number,
            Options.SCALE_LABEL,
            ns.DB_DEFAULTS.profile.settings.scale,
            Options.GetScale,
            Options.SetScale
        )
        local sliderOptions = Settings.CreateSliderOptions(Options.SCALE_MIN, Options.SCALE_MAX, Options.SCALE_STEP)
        -- The number beside the slider is a percentage, which is how every
        -- other scale in the game is written. MinimalSliderWithSteppersMixin's
        -- Label enum and SetLabelFormatter come from
        -- Blizzard_SharedXML/Shared/Slider/MinimalSlider.lua; both are guarded,
        -- because a slider with no label is still a slider.
        if sliderOptions.SetLabelFormatter and _G.MinimalSliderWithSteppersMixin then
            sliderOptions:SetLabelFormatter(_G.MinimalSliderWithSteppersMixin.Label.Right, function(value)
                return string.format("%d%%", math.floor(value * 100 + 0.5))
            end)
        end
        Settings.CreateSlider(category, scaleSetting, sliderOptions, Options.SCALE_TOOLTIP)
        Options.scaleSetting = scaleSetting
    end
    -- `Reset size` (M5-5, WKE-661), beside the scale. A button row is
    -- `CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip,
    -- addSearchTags)` added to the category's layout
    -- (Blizzard_Settings_Shared/Blizzard_SettingControls.lua:762, and the
    -- `SettingsPanel:GetLayout(category):AddInitializer` pair Blizzard_Settings
    -- .lua:377-379 uses for its own controls). Guarded like the slider: a
    -- client without them keeps the page and loses the button.
    local panel = _G.SettingsPanel
    if type(_G.CreateSettingsButtonInitializer) == "function" and panel and type(panel.GetLayout) == "function" then
        local layout = panel:GetLayout(category)
        if layout and type(layout.AddInitializer) == "function" then
            Options.resetSizeInitializer = layout:AddInitializer(
                _G.CreateSettingsButtonInitializer("", Options.RESET_SIZE_LABEL, Options.ResetSize, nil, false)
            )
        end
    end
    if Settings.CreateCheckbox then
        local compactSetting = Settings.RegisterProxySetting(
            category,
            Options.COMPACT_VARIABLE,
            Settings.VarType.Boolean,
            Options.COMPACT_LABEL,
            ns.DB_DEFAULTS.profile.settings.compactRows,
            Options.GetCompactRows,
            Options.SetCompactRows
        )
        Settings.CreateCheckbox(category, compactSetting, Options.COMPACT_TOOLTIP)
        Options.compactSetting = compactSetting
        local explainSetting = Settings.RegisterProxySetting(
            category,
            Options.EXPLAIN_VARIABLE,
            Settings.VarType.Boolean,
            Options.EXPLAIN_LABEL,
            ns.DB_DEFAULTS.profile.settings.explain,
            Options.GetExplain,
            Options.SetExplain
        )
        Settings.CreateCheckbox(category, explainSetting, Options.EXPLAIN_TOOLTIP)
        Options.explainSetting = explainSetting
    end
    Settings.RegisterAddOnCategory(category)
    Options.category = category
    Options.setting = setting
    Options.scenarioSetting = scenario
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
