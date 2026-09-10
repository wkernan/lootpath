-- Lootpath/UI/MainFrame.lua (M2-2, WKE-520; the three tabs added in M3-3,
-- WKE-524; the chrome rebuilt in M5-2, WKE-551)
-- The one window: a portrait frame whose ring carries the spec the verdict is
-- for, a one-line status strip saying whose numbers these are and how old, the
-- paste editbox demoted to a dialog behind that strip's Import... button, and
-- one tab per promise on the frame's bottom edge - Equip Now, the Upgrade Map
-- and the Vault. Native frames and Blizzard's own templates only (decision
-- 2026-09-05: Ace3 is AceDB, nothing else).
--
-- Templates used, each read from Blizzard's shipped XML under .luals rather
-- than remembered (BasicFrameTemplateWithInset and InputScrollFrameTemplate on
-- 2026-09-06; the rest on 2026-09-09):
--   PortraitFrameTemplate (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:631)
--     inherits PortraitFrameTemplateNoCloseButton -> PortraitFrameTexturedBaseTemplate
--     -> PortraitFrameBaseTemplate, which is where `PortraitContainer` (with the
--     `portrait` texture at 62 x 62 and a circular mask), `TitleContainer` and
--     its `TitleText` come from; the close button is the one thing
--     PortraitFrameTemplate itself adds, at parentKey `CloseButton`. It carries
--     NO inset frame - BasicFrameTemplateWithInset's `InsetBg` has no
--     counterpart here - so the panels anchor to the frame's own edges.
--   InputScrollFrameTemplate (Blizzard_SharedXML/SecureUIPanelTemplates.xml)
--     a ScrollFrame whose scroll child is a multiLine EditBox at parentKey
--     `EditBox`, with `maxLetters` defaulting to 0 and a `CharCount` label.
--     Its OnTextChanged writes `GetMaxLetters() - GetNumLetters()` into that
--     label, which is meaningless at maxLetters 0, so the label is hidden.
--   PanelTabButtonTemplate (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:905)
--     carries `parentArray="Tabs"`, so each tab appends itself to `frame.Tabs`.
--     WHICH tab is selected is Lootpath's own state (`UI.SelectTab`), because
--     that is what decides which panel is on screen; `PanelTemplates_SetTab`
--     and `PanelTemplates_SetNumTabs` are called for the selected/deselected
--     ARTWORK only, guarded, because a client without them must still tab.
--   BasicFrameTemplateWithInset (Blizzard_UIPanelTemplates/UIPanelTemplates.xml)
--     the import dialog's frame, and what the main window was until M5-2.
--
-- The portrait is filled by this file rather than by PortraitFrameMixin's own
-- `SetPortraitToSpecIcon` (Blizzard_SharedXML/PortraitFrame.lua:78), which does
-- the same two steps - the spec's icon, the class icon when there is no spec -
-- so that both paths are one guarded piece of code a headless test can drive.
-- Blizzard's annotations mark `GetSpecialization` and `GetSpecializationInfo`
-- deprecated in favour of `C_SpecializationInfo` (Blizzard_Deprecated/
-- Deprecated_Specialization_Standard.lua), so the namespaced pair is tried
-- first and the globals are the fallback; a client that answers neither gets
-- the class icon, and one that answers nothing at all gets no portrait and no
-- error.
--
-- Nothing here reads the client in combat: the scan behind the panel is
-- ns.Inventory.Scan, which refuses in combat, and the refusal is what shows.

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.FRAME_NAME = "LootpathMainFrame"
UI.DIALOG_NAME = "LootpathImportDialog"
UI.MINIMAP_BUTTON_NAME = "LootpathMinimapButton"
-- M5-0 (WKE-549) has not answered the window-size question, so the size is the
-- one the window has had since M2-2; the mockups are drawn at 760.
UI.WIDTH = 620
UI.HEIGHT = 640
UI.DIALOG_WIDTH = 520
UI.DIALOG_HEIGHT = 260
UI.PASTE_INSTRUCTIONS = "Paste your QE Live Top Gear or Upgrade Finder JSON here"

-- One tab per promise, in the order the product states them (ARCHITECTURE.md
-- 1). `key` is the field on the frame that holds that tab's panel; `refresh` is
-- how that panel is redrawn. Only the visible one is refreshed: rebuilding the
-- journal map on every BAG_UPDATE_DELAYED would walk 613 rows to redraw a panel
-- nobody is looking at.
UI.TABS = {
    { id = 1, key = "equipPanel", label = "Equip Now" },
    { id = 2, key = "upgradeMapPanel", label = "Upgrade Map" },
    { id = 3, key = "vaultPanel", label = "Vault" },
}
UI.VAULT_TAB = 3

-- ISO 8601 in UTC, which is what QE Live's exportedAt is
-- ("2026-09-06T21:14:24.465Z", read from the committed export). Returns the
-- age in seconds, or nil when the string is not one of those.
-- The stamp reader is ns.EpochFromISO (Core), shared with the companion's
-- writtenAt so an age on screen and a freshness decision never disagree about
-- what a timestamp means.
function UI.AgeSeconds(iso, now)
    local epoch = ns.EpochFromISO(iso, now)
    if not epoch then
        return nil
    end
    return (now or time()) - epoch
end

function UI.AgeText(iso, now)
    local seconds = UI.AgeSeconds(iso, now)
    if not seconds then
        return type(iso) == "string" and iso or "at an unknown time"
    end
    if seconds < 5 then
        return "just now"
    end
    if seconds < 90 then
        return string.format("%d second(s) ago", math.floor(seconds))
    end
    if seconds < 5400 then
        return string.format("%d minute(s) ago", math.floor(seconds / 60 + 0.5))
    end
    if seconds < 172800 then
        return string.format("%d hour(s) ago", math.floor(seconds / 3600 + 0.5))
    end
    return string.format("%d day(s) ago", math.floor(seconds / 86400 + 0.5))
end

-- The two exports the paste box takes, and what each is called on screen. The
-- kind travels on the import result so the status line can name it: two files
-- that both say "QE Live" answer different questions, and an owner who pasted
-- the wrong one has to be able to see that from the line.
UI.KIND_TOP_GEAR = "topgear"
UI.KIND_UPGRADE_FINDER = "upgradefinder"
UI.KIND_LABEL = {
    [UI.KIND_TOP_GEAR] = "Top Gear",
    [UI.KIND_UPGRADE_FINDER] = "Upgrade Finder",
}

-- The schema a pasted blob names, read WITHOUT decoding it. A Top Gear export
-- is tens of kilobytes and an Upgrade Finder export is over a hundred, and
-- decoding twice - once to route, once to parse - would double that for no
-- gain. Nothing is trusted to this match: it only chooses which parser sees the
-- text, and that parser checks the schema, the version and the game type
-- properly. Returns nil when the text names no schema at all.
function UI.DetectSchema(text)
    if type(text) ~= "string" then
        return nil
    end
    return text:match('"schema"%s*:%s*"([^"]*)"')
end

-- Routes a paste to the parser that reads it. Text naming neither schema goes
-- to QEImport, so "that is not JSON" and "nothing to import" still come from a
-- parser rather than from here; text naming a schema that is neither is refused
-- by name, because "not a Top Gear export" would be a half-truth once there are
-- two kinds.
function UI.ImportAny(text)
    local schema = UI.DetectSchema(text)
    if schema and schema ~= ns.QEImport.SCHEMA and schema ~= ns.UFImport.SCHEMA then
        return {
            ok = false,
            reason = string.format(
                'that export carries schema "%s"; Lootpath reads "%s" (Top Gear) and "%s" (Upgrade Finder)',
                schema,
                ns.QEImport.SCHEMA,
                ns.UFImport.SCHEMA
            ),
        }
    end
    local result
    if schema == ns.UFImport.SCHEMA then
        result = ns.UFImport.Import(text)
        result.kind = UI.KIND_UPGRADE_FINDER
    else
        result = ns.QEImport.Import(text)
        result.kind = UI.KIND_TOP_GEAR
    end
    return result
end

-- The other kind of export stored for the same content type, as one line, or
-- nil when there is none. Both ages on screen is what tells the owner that the
-- Upgrade Map's numbers and the Equip Now list came from two different runs.
function UI.OtherImportLine(kind, verdict, now)
    local module = kind == UI.KIND_UPGRADE_FINDER and ns.QEImport or ns.UFImport
    local otherKind = kind == UI.KIND_UPGRADE_FINDER and UI.KIND_TOP_GEAR or UI.KIND_UPGRADE_FINDER
    local contentType = type(verdict) == "table" and verdict.contentType or nil
    local other = contentType and module.ForContentType(contentType) or nil
    if not other then
        return nil
    end
    return string.format(
        "|cff868e96Also stored:|r %s (%s), exported %s",
        UI.KIND_LABEL[otherKind],
        other.contentType or "unknown content type",
        UI.AgeText(other.exportedAt, now)
    )
end

-- The import status line. A refusal is shown verbatim - the parser's message
-- already names what it saw, and rewording it here would hide that.
function UI.StatusText(result, now)
    if type(result) ~= "table" then
        return ""
    end
    if not result.ok then
        return "|cffff6b6b" .. tostring(result.reason) .. "|r"
    end
    local verdict = result.verdict
    local kind = result.kind or UI.KIND_TOP_GEAR
    local count, noun
    if kind == UI.KIND_UPGRADE_FINDER then
        count, noun = #(verdict.order or {}), "ranked drops"
    else
        count, noun = #(verdict.topSet.order or {}), "items"
    end
    local line = string.format(
        "|cff40c057Imported|r %s: %s, %s, exported %s, %d %s",
        UI.KIND_LABEL[kind] or kind,
        verdict.spec or "unknown spec",
        verdict.contentType or "unknown content type",
        UI.AgeText(verdict.exportedAt, now),
        count,
        noun
    )
    for _, warning in ipairs(result.warnings or {}) do
        line = line .. "\n|cffffd43bNote:|r " .. warning
    end
    local other = UI.OtherImportLine(kind, verdict, now)
    if other then
        line = line .. "\n" .. other
    end
    return line
end

-- Which verdict the panels read: the one matching the content-type setting when
-- this character has one, otherwise the most recent import - said out loud, so
-- a Raid answer is never shown under a Dungeon setting without a word about it.
function UI.ActiveVerdict()
    local wanted = UI.Options and UI.Options.Get() or nil
    local verdict = wanted and ns.QEImport.ForContentType(wanted) or nil
    if verdict then
        return verdict, wanted, false
    end
    local current = ns.QEImport.Current()
    if current then
        return current, ns.QEImport.ContentTypeKey(current), true
    end
    return nil, wanted, false
end

-- Every named scenario stored for the content type on screen (C-6, WKE-540),
-- chosen the way ActiveVerdict chooses one verdict: the setting's content type
-- when this character has anything for it, otherwise whatever the most recent
-- import was, said out loud.
--
-- It is its own function rather than a second return from ActiveVerdict for the
-- reason ActiveUpgradeFinderDocuments is: `asOffered` is what Equip Now and the
-- Upgrade Map read and the ONLY thing they read, and a caller that could get the
-- whole set back from the same call is a caller that could show a `maxed` answer
-- on a tab that promises what you own now.
--
-- Returns scenarios (a list of { verdict, scenario }, possibly empty, never
-- nil), contentType, fellBack.
function UI.ActiveVerdictScenarios()
    local wanted = UI.Options and UI.Options.Get() or nil
    if wanted then
        local scenarios = ns.QEImport.Scenarios(wanted)
        if #scenarios > 0 then
            return scenarios, wanted, false
        end
    end
    local current = ns.QEImport.Current()
    if current then
        local contentType = ns.QEImport.ContentTypeKey(current)
        local scenarios = ns.QEImport.Scenarios(contentType)
        if #scenarios > 0 then
            return scenarios, contentType, true
        end
        return { { verdict = current, scenario = ns.QEImport.ScenarioKey(current) } }, contentType, true
    end
    return {}, wanted, false
end

-- The Upgrade Finder export the panels read, chosen exactly as ActiveVerdict
-- chooses a Top Gear one. Kept as its own function rather than a flag on
-- ActiveVerdict so a caller cannot get both verdicts back in one call and treat
-- them as one thing: they are different schemas with opposite sign conventions.
--
-- Since C-7 (WKE-543) there can be SEVERAL Upgrade Finder exports for one
-- content type, one per Mythic+ key level the companion asked QE Live about,
-- and since M3-10 (WKE-545) the loot map reads ALL of them: a drop is valued by
-- whichever document carries it at the item level the client lists, because his
-- +10 dungeon rows (311) and the client's keystone-10 preview (305) disagree by
-- six item levels and neither side is Lootpath's to adjust. So this hands back
-- the whole set for the content type rather than one pick of it, and the panel
-- says which documents they are.
--
-- Returns documents (possibly empty, never nil), contentType, fellBack.
function UI.ActiveUpgradeFinderDocuments()
    local wanted = UI.Options and UI.Options.Get() or nil
    if wanted then
        local documents = ns.UFImport.Documents(wanted)
        if #documents > 0 then
            return documents, wanted, false
        end
    end
    local current = ns.UFImport.Current()
    if current then
        local contentType = ns.UFImport.ContentTypeKey(current)
        local documents = ns.UFImport.Documents(contentType)
        if #documents > 0 then
            return documents, contentType, true
        end
        -- Stored, but on neither shelf UFImport.Documents reads: it is still an
        -- answer, and it is shown as the one document it is.
        return { { verdict = current, keyLevel = ns.UFImport.KeyLevelOf(current) } }, contentType, true
    end
    return {}, wanted, false
end

-- Which import is on screen and where it came from - "pasted", or "companion,
-- written 4 minute(s) ago" (C-2). The source is on the line the window keeps,
-- not the status line the next paste overwrites.
function UI.VerdictNoteText(now)
    local verdict, contentType, fellBack = UI.ActiveVerdict()
    if not verdict then
        return "No QE Live export on this character yet."
    end
    local source = ns.Companion.SourceText(verdict, now)
    if fellBack then
        return string.format(
            "|cffffd43bShowing the %s export|r (%s) - nothing has been imported for %s yet.",
            contentType,
            source,
            UI.Options.Get()
        )
    end
    return string.format("Showing the %s export (%s).", contentType, source)
end

-- ---------------------------------------------------------------------------
-- M5-2 (WKE-551): the status strip.

-- The separator between the strip's facts. One glyph rather than a dash so the
-- five facts read as five; whether it renders on the owner's screen is an eye
-- test (M5-5, WKE-554), not something this file can claim.
UI.SEPARATOR = " \194\183 "
UI.NO_VERDICT_STRIP = "QE Live \194\183 no export on this character yet \194\183 Import... to paste one"
UI.STALE_STRIP_TOOLTIP =
    "This export was made before the last weekly reset. If the companion is running it should be newer than that."

-- Which of QE Live's named scenarios the Vault tab's pick follows, in the
-- strip's words. The setting is C-6's (WKE-540); the strip only says it.
UI.SCENARIO_TAG = {
    asOffered = "vault pick: as offered",
    catalyzed = "vault pick: catalyzed",
    thisWeek = "vault pick: this week",
    maxed = "vault pick: everything upgraded",
}

-- The client's own seconds-to-weekly-reset, or nil when it does not answer.
-- Guarded and passed through ns.Safe like every other client read: a secret
-- value here would otherwise reach tonumber.
function UI.SecondsUntilWeeklyReset()
    local fn = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    if type(fn) ~= "function" then
        return nil
    end
    local ok, seconds = pcall(fn)
    if not ok then
        return nil
    end
    return tonumber((ns.Safe(seconds)))
end

-- The one line under the title: what is on screen, whose it is and how old.
-- `QE Live | spec | content type kind | source, age | scenario tag`, from the
-- same facts UI.VerdictNoteText states in a sentence and ns.Companion.SourceText
-- names the source with. Returns a model rather than a string so the age can be
-- toned amber without the tests reading colour codes: { text, stale, tooltip }.
--
-- `stale` is VaultPanel.IsVerdictStale over the client's own reset boundary -
-- an export older than the last weekly reset, which is the tell ARCHITECTURE.md
-- 11 names for a
-- companion watcher that has died. nil (not false) when the client does not say
-- when the reset is; only a true makes the age amber.
function UI.StatusStripModel(now)
    local verdict, contentType, fellBack = UI.ActiveVerdict()
    local tooltip = { UI.VerdictNoteText(now) }
    if not verdict then
        return { text = UI.NO_VERDICT_STRIP, tooltip = tooltip }
    end
    local kind = UI.KIND_LABEL[UI.KIND_TOP_GEAR]
    local source = ns.Companion.SourceText(verdict, now) or "imported"
    if not source:find("written", 1, true) then
        source = source .. ", exported " .. UI.AgeText(verdict.exportedAt, now)
    end
    local stale = ns.VaultPanel.IsVerdictStale(verdict.exportedAt, now or time(), UI.SecondsUntilWeeklyReset())
    if stale then
        source = "|cffffd43b" .. source .. "|r"
        tooltip[#tooltip + 1] = UI.STALE_STRIP_TOOLTIP
    end
    local scenario = ns.UI.Options.GetVaultScenario()
    local parts = {
        "QE Live",
        verdict.spec or "unknown spec",
        string.format("%s %s", contentType or "unknown content type", kind),
        source,
        UI.SCENARIO_TAG[scenario] or ("vault pick: " .. tostring(scenario)),
    }
    local other = UI.OtherImportLine(UI.KIND_TOP_GEAR, verdict, now)
    if other then
        tooltip[#tooltip + 1] = other
    end
    return {
        text = table.concat(parts, UI.SEPARATOR),
        stale = stale,
        fellBack = fellBack,
        tooltip = tooltip,
    }
end

-- ---------------------------------------------------------------------------
-- M5-2 (WKE-551): the portrait ring.

-- The player's current specialization icon, or nil when the client does not
-- name one. C_SpecializationInfo is what Blizzard's own annotations deprecate
-- the two globals in favour of, so it is asked first and the globals answer for
-- a client that has not got it.
function UI.SpecIcon()
    local index, info
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecialization) == "function" then
        index = C_SpecializationInfo.GetSpecialization()
        info = C_SpecializationInfo.GetSpecializationInfo
    end
    if index == nil and type(_G.GetSpecialization) == "function" then
        index = GetSpecialization()
        info = _G.GetSpecializationInfo
    end
    if index == nil or type(info) ~= "function" then
        return nil
    end
    local icon = select(4, info(index))
    icon = (ns.Safe(icon))
    if type(icon) ~= "number" and type(icon) ~= "string" then
        return nil
    end
    return icon
end

-- The class icon's file and its four texture coordinates in the shared
-- UI-Classes-Circles sheet, exactly as PortraitFrameMixin:SetPortraitToClassIcon
-- reads them (Blizzard_SharedXML/PortraitFrame.lua:72). nil when the client
-- names no class or has no coordinate table.
UI.CLASS_ICON_FILE = "Interface/TargetingFrame/UI-Classes-Circles"

function UI.ClassIconCoords()
    local coords = _G.CLASS_ICON_TCOORDS
    if type(_G.UnitClass) ~= "function" or type(coords) ~= "table" then
        return nil
    end
    local fileName = select(2, UnitClass("player"))
    fileName = (ns.Safe(fileName))
    if type(fileName) ~= "string" then
        return nil
    end
    return coords[fileName:upper()]
end

-- Fills the frame's portrait ring with the spec the verdict is for, so the
-- window says whose answer this is before a word is read. Returns "spec",
-- "class" or nil - nil being a client that named neither, which leaves the ring
-- empty rather than guessing at one.
function UI.ApplyPortrait(frame)
    frame = frame or UI.frame
    local container = frame and frame.PortraitContainer
    local portrait = container and container.portrait
    if not portrait then
        return nil
    end
    local icon = UI.SpecIcon()
    if icon then
        portrait:SetTexCoord(0, 1, 0, 1)
        portrait:SetTexture(icon)
        return "spec"
    end
    local coords = UI.ClassIconCoords()
    if coords then
        portrait:SetTexture(UI.CLASS_ICON_FILE)
        portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return "class"
    end
    return nil
end

function UI.Import(text)
    local result = UI.ImportAny(text)
    if UI.frame then
        UI.frame.status:SetText(UI.StatusText(result))
    end
    if not result.ok then
        ns.Log("%s", result.reason)
        return result
    end
    for _, warning in ipairs(result.warnings) do
        ns.Log("note: %s", warning)
    end
    UI.Refresh()
    return result
end

-- The Equip Now tab. Kept as its own function so UI.Refresh can redraw one tab
-- without touching the other two.
function UI.RefreshEquip(frame)
    local verdict = UI.ActiveVerdict()
    local match
    if verdict then
        match = ns.Match.Build(ns.Inventory.Scan(), verdict)
        -- Combat stops the scan, not the window. Blanking the panel the moment
        -- a pull starts would throw away the answer the user opened it for, so
        -- the last scan stays on screen, marked stale, with every button off.
        local previous = frame.equipPanel.match
        if not match.ok and match.reason == "combat" and previous and previous.ok then
            previous.stale = true
            match = previous
        end
    end
    UI.EquipPanel.Refresh(frame.equipPanel, match)
    return match
end

-- Redraws the tab that is on screen and no other. Still returns the match when
-- the Equip tab is showing, because that is what M2-2's callers read.
function UI.Refresh()
    local frame = UI.frame
    if not frame then
        return nil
    end
    UI.RefreshStrip(frame)
    local selected = frame.selectedTab or 1
    if selected == 2 then
        ns.UpgradeMapPanel.Refresh(frame.upgradeMapPanel)
        return nil
    end
    if selected == 3 then
        ns.VaultPanel.Refresh(frame.vaultPanel)
        return nil
    end
    return UI.RefreshEquip(frame)
end

-- Where the Vault module's second read lands (M3-12, WKE-547): a reward whose
-- item data arrived after the tab was drawn. Redraws the Vault tab if, and
-- only if, the window is open on it - the same "only the visible tab redraws"
-- rule as UI.Refresh, without touching the other two tabs at all. Returns
-- whether it drew.
function UI.RefreshVault()
    local frame = UI.frame
    if not frame or not frame:IsShown() or (frame.selectedTab or 1) ~= UI.VAULT_TAB then
        return false
    end
    ns.VaultPanel.Refresh(frame.vaultPanel)
    return true
end

-- Shows one tab's panel and hides the other two. `frame.selectedTab` is
-- Lootpath's own state; PanelTemplates_SetTab is called for the tab artwork
-- when the client has it, and its absence changes nothing about which panel is
-- visible. Split from UI.SelectTab so UI.Frame can pick the first tab without
-- scanning the client before the window has ever been opened.
function UI.ShowTab(frame, id)
    local wanted = 1
    for _, tab in ipairs(UI.TABS) do
        if tab.id == id then
            wanted = id
        end
    end
    frame.selectedTab = wanted
    for _, tab in ipairs(UI.TABS) do
        local panel = frame[tab.key]
        if panel then
            panel:SetShown(tab.id == wanted)
        end
    end
    if type(_G.PanelTemplates_SetTab) == "function" then
        PanelTemplates_SetTab(frame, wanted)
    end
    return wanted
end

-- Switching tab: show it, then draw it. Only the tab now on screen is drawn.
function UI.SelectTab(frame, id)
    frame = frame or UI.frame
    if not frame then
        return nil
    end
    local wanted = UI.ShowTab(frame, id)
    UI.Refresh()
    return wanted
end

-- The Import dialog (M5-2). Everything the top third of every tab used to
-- carry - the instructions, the editbox, Import, Clear and the import status
-- line - moved here whole: UI.Import and UI.ImportAny are untouched, and the
-- status line they write is the same font string it always was, now inside the
-- dialog instead of behind three tabs.
--
-- Built with the window rather than on first click so that `frame.pasteBox`,
-- `frame.importButton`, `frame.clearButton` and `frame.status` mean exactly what
-- they meant before this issue: the keys are aliases onto the dialog's widgets,
-- which is what lets UI.Import keep writing to `UI.frame.status`.
local function buildImportDialog(frame)
    local dialog = CreateFrame("Frame", UI.DIALOG_NAME, UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(UI.DIALOG_WIDTH, UI.DIALOG_HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    if dialog.TitleText then
        dialog.TitleText:SetText("Import a QE Live export")
    end

    local label = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", dialog, "TOPLEFT", 14, -32)
    label:SetText(UI.PASTE_INSTRUCTIONS)
    dialog.pasteLabel = label

    local scroll = CreateFrame("ScrollFrame", nil, dialog, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -8)
    scroll:SetSize(UI.DIALOG_WIDTH - 40, 90)
    -- InputScrollFrame_OnTextChanged writes `maxLetters - numLetters` into
    -- CharCount, which is a large negative number once maxLetters is 0.
    scroll.hideCharCount = true
    if scroll.CharCount then
        scroll.CharCount:Hide()
    end
    dialog.pasteScroll = scroll

    local editBox = scroll.EditBox
    editBox:SetAutoFocus(false)
    -- 0 = no limit. A Top Gear export is tens of kilobytes and WeakAuras moves
    -- strings that size through an editbox, so nothing here chunks the paste.
    editBox:SetMaxLetters(0)
    editBox:SetMultiLine(true)
    editBox:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)
    dialog.pasteBox = editBox

    local importButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    importButton:SetSize(90, 22)
    importButton:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", -4, -10)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        UI.Import(editBox:GetText())
    end)
    dialog.importButton = importButton

    local clearButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    clearButton:SetSize(90, 22)
    clearButton:SetPoint("LEFT", importButton, "RIGHT", 8, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        editBox:SetText("")
        dialog.status:SetText("")
    end)
    dialog.clearButton = clearButton

    local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    closeButton:SetSize(90, 22)
    closeButton:SetPoint("LEFT", clearButton, "RIGHT", 8, 0)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        dialog:Hide()
    end)
    dialog.closeDialogButton = closeButton

    local status = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", importButton, "BOTTOMLEFT", 4, -10)
    status:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)
    status:SetText("")
    dialog.status = status

    -- Escape closes it, as it does the window; UISpecialFrames keys on the
    -- global name, which is why this frame has one too.
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = UI.DIALOG_NAME
    end
    dialog:Hide()

    frame.importDialog = dialog
    frame.pasteLabel = dialog.pasteLabel
    frame.pasteScroll = scroll
    frame.pasteBox = editBox
    frame.importButton = importButton
    frame.clearButton = clearButton
    frame.status = status
    UI.dialog = dialog
    return dialog
end

function UI.ToggleImportDialog()
    local frame = UI.Frame()
    local dialog = frame.importDialog
    if not dialog then
        return false
    end
    if dialog:IsShown() then
        dialog:Hide()
        return false
    end
    dialog:Show()
    return true
end

-- The status strip: one line of facts under the title, and the two buttons that
-- used to sit under the paste box. The strip itself takes the mouse so the
-- facts that do not fit on one line - the sentence UI.VerdictNoteText states,
-- the other stored export, why an amber age is amber - are one hover away.
local function buildStatusStrip(frame)
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -30)
    strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -30)
    strip:SetHeight(22)
    strip:EnableMouse(true)
    frame.statusStrip = strip

    local optionsButton = CreateFrame("Button", nil, strip, "UIPanelButtonTemplate")
    optionsButton:SetSize(74, 20)
    optionsButton:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function()
        UI.OpenOptions()
    end)
    frame.optionsButton = optionsButton

    local importButton = CreateFrame("Button", nil, strip, "UIPanelButtonTemplate")
    importButton:SetSize(80, 20)
    importButton:SetPoint("RIGHT", optionsButton, "LEFT", -6, 0)
    importButton:SetText("Import...")
    importButton:SetScript("OnClick", function()
        UI.ToggleImportDialog()
    end)
    frame.openImportButton = importButton

    local text = strip:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", strip, "LEFT", 2, 0)
    text:SetPoint("RIGHT", importButton, "LEFT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    frame.stripText = text

    strip:SetScript("OnEnter", function(self)
        if not (GameTooltip and frame.stripModel) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        for _, line in ipairs(frame.stripModel.tooltip or {}) do
            GameTooltip:AddLine(line)
        end
        GameTooltip:Show()
    end)
    strip:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

-- Redraws the strip from the facts as they are now. Its own function because
-- UI.Refresh calls it on every redraw and the launcher's toggle does not.
function UI.RefreshStrip(frame)
    frame = frame or UI.frame
    if not frame or not frame.stripText then
        return nil
    end
    local model = UI.StatusStripModel()
    frame.stripModel = model
    frame.stripText:SetText(model.text)
    return model
end

-- One tab per promise, on the frame's BOTTOM edge (M5-2), the way the Encounter
-- Journal and every Blizzard panel with tabs place them: the first tab's TOPLEFT
-- sits on the frame's BOTTOMLEFT, so the tabs hang below the window and the body
-- above them is one uninterrupted rectangle. The button art is Blizzard's; which
-- panel it shows is UI.SelectTab's.
local function buildTabs(frame)
    frame.tabs = {}
    for index, tab in ipairs(UI.TABS) do
        local button = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
        button:SetID(tab.id)
        button:SetText(tab.label)
        button:SetSize(110, 24)
        if index == 1 then
            button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        else
            button:SetPoint("LEFT", frame.tabs[index - 1], "RIGHT", 3, 0)
        end
        button:SetScript("OnClick", function(self)
            UI.SelectTab(frame, self:GetID())
        end)
        frame.tabs[index] = button
    end
    if type(_G.PanelTemplates_SetNumTabs) == "function" then
        PanelTemplates_SetNumTabs(frame, #UI.TABS)
    end
end

-- ---------------------------------------------------------------------------
-- M5-2 (WKE-551): the launcher. A minimap button drawn natively and an AddOn
-- Compartment entry, both of which do nothing but UI.Toggle. No library: an
-- addon with one user does not need LibDBIcon vendored and licence-recorded to
-- put a 31-point button on a circle.

-- How far outside the minimap's edge the button sits, and where it starts. The
-- minimap is 140 points across at default scale, so the margin puts the button
-- at 80 from the centre there (`UI.MINIMAP_RADIUS`, kept for the tests and as
-- the fallback when there is no minimap to measure) - but addons resize the
-- minimap after login (ElvUI, the owner's, 2026-09-09), so the radius is read
-- off `Minimap:GetWidth()` / `GetHeight()` at every placement, never fixed.
-- The angle is degrees counter-clockwise from east, which is the convention
-- LibDBIcon's saved variables use and the one a dragged position is measured
-- back into.
UI.MINIMAP_MARGIN = 10
UI.MINIMAP_DEFAULT_SIZE = 140
UI.MINIMAP_RADIUS = UI.MINIMAP_DEFAULT_SIZE / 2 + UI.MINIMAP_MARGIN
UI.MINIMAP_BUTTON_SIZE = 31

-- The minimap's shape, as the client's minimap addon publishes it: a global
-- `GetMinimapShape()` returning "ROUND" or "SQUARE" (and, for some addons,
-- corner and side variants) is the convention every minimap-button library
-- reads. Only "SQUARE" changes the placement here; anything else is round.
function UI.MinimapShape()
    local fn = rawget(_G, "GetMinimapShape")
    if type(fn) == "function" then
        local ok, shape = pcall(fn)
        if ok and type(shape) == "string" then
            return shape
        end
    end
    return "ROUND"
end

-- Where a button at this angle goes, relative to the minimap's centre, for a
-- minimap of this size and shape. Pure, so the placement is a test and not a
-- screenshot. On a round map the button rides a circle just outside the edge;
-- on a square one it rides the square, clamped to the edge, so the corners are
-- reachable and the sides are not inside the map.
function UI.MinimapButtonOffset(angle, width, height, shape)
    local radians = math.rad(tonumber(angle) or 0)
    local w = (tonumber(width) or UI.MINIMAP_DEFAULT_SIZE) / 2 + UI.MINIMAP_MARGIN
    local h = (tonumber(height) or UI.MINIMAP_DEFAULT_SIZE) / 2 + UI.MINIMAP_MARGIN
    local cx, cy = math.cos(radians), math.sin(radians)
    if shape == "SQUARE" then
        local dw = math.sqrt(2 * w * w) - UI.MINIMAP_MARGIN
        local dh = math.sqrt(2 * h * h) - UI.MINIMAP_MARGIN
        return math.max(-w, math.min(cx * dw, w)), math.max(-h, math.min(cy * dh, h))
    end
    return cx * w, cy * h
end

-- The minimap as it is right now: its size in points and its published shape.
function UI.MinimapGeometry()
    local width = Minimap and Minimap.GetWidth and Minimap:GetWidth()
    local height = Minimap and Minimap.GetHeight and Minimap:GetHeight()
    return tonumber(width) or UI.MINIMAP_DEFAULT_SIZE, tonumber(height) or UI.MINIMAP_DEFAULT_SIZE, UI.MinimapShape()
end

-- The angle a cursor at (x, y) makes with a minimap centred at (cx, cy),
-- normalised into [0, 360). The inverse of MinimapButtonOffset, and the whole
-- of what dragging the button computes.
function UI.MinimapAngleFrom(cx, cy, x, y)
    local angle = math.deg(math.atan2((y or 0) - (cy or 0), (x or 0) - (cx or 0)))
    return angle % 360
end

function UI.GetMinimapAngle()
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    local angle = settings and tonumber(settings.minimapAngle)
    return angle or ns.DB_DEFAULTS.profile.settings.minimapAngle
end

-- Saves the angle and moves the button to it. The saved value is what survives a
-- reload; the placement is what the eye sees, and they are set together so they
-- can never disagree.
function UI.SetMinimapAngle(angle)
    angle = tonumber(angle)
    if not angle then
        return nil
    end
    angle = angle % 360
    local settings = ns.db and ns.db.profile and ns.db.profile.settings
    if settings then
        settings.minimapAngle = angle
    end
    local button = UI.minimapButton
    if button then
        local x, y = UI.MinimapButtonOffset(angle, UI.MinimapGeometry())
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    return angle
end

-- Follows the cursor while the button is held. The minimap's own centre and
-- effective scale are read every frame rather than cached: the player can move
-- or rescale the minimap between drags.
local function minimapDragUpdate()
    local button = UI.minimapButton
    if not (button and Minimap and type(_G.GetCursorPosition) == "function") then
        return
    end
    local cx, cy = Minimap:GetCenter()
    if not cx then
        return
    end
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale == 0 then
        scale = 1
    end
    local x, y = GetCursorPosition()
    UI.SetMinimapAngle(UI.MinimapAngleFrom(cx, cy, x / scale, y / scale))
end

-- The minimap button itself. Returns nil on a client with no Minimap, which is
-- not an error: the window still opens from the slash command and the AddOn
-- Compartment.
function UI.MinimapButton()
    if UI.minimapButton then
        return UI.minimapButton
    end
    if not Minimap then
        return nil
    end
    local button = CreateFrame("Button", UI.MINIMAP_BUTTON_NAME, Minimap)
    UI.minimapButton = button
    button:SetSize(UI.MINIMAP_BUTTON_SIZE, UI.MINIMAP_BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    -- The spec the verdict is for, the same fact the portrait ring carries; the
    -- question mark until the client names one.
    icon:SetTexture(UI.SpecIcon() or "Interface/Icons/INV_Misc_QuestionMark")
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    button.border = border

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            UI.OpenOptions()
            return
        end
        UI.Toggle()
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", minimapDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Lootpath")
        GameTooltip:AddLine(UI.StatusStripModel().text)
        GameTooltip:AddLine("Left-click to open, right-click for options, drag to move.")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Minimap addons size the minimap after this addon has placed the button,
    -- so the placement follows the minimap's size rather than assuming it.
    if Minimap.HookScript then
        Minimap:HookScript("OnSizeChanged", function()
            UI.SetMinimapAngle(UI.GetMinimapAngle())
        end)
    end

    UI.SetMinimapAngle(UI.GetMinimapAngle())
    return button
end

-- The AddOn Compartment's entry point. `## AddonCompartmentFunc: LootpathToggle`
-- in the .toc names a GLOBAL function, which Blizzard's AddonCompartmentMixin
-- looks up in _G and calls as `_G[func](addonName, buttonName)`
-- (Blizzard_Minimap/Mainline/AddonCompartment.lua:81-105), so this is the one
-- global Lootpath defines and it takes the client's two arguments and ignores
-- them.
function _G.LootpathToggle()
    UI.Toggle()
end

local function onEvent(frame, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        UI.ApplyPortrait(frame)
        if UI.minimapButton and UI.minimapButton.icon then
            UI.minimapButton.icon:SetTexture(UI.SpecIcon() or "Interface/Icons/INV_Misc_QuestionMark")
        end
    end
    if frame:IsShown() then
        UI.Refresh()
    end
end

function UI.Frame()
    if UI.frame then
        return UI.frame
    end
    local frame = CreateFrame("Frame", UI.FRAME_NAME, UIParent, "PortraitFrameTemplate")
    UI.frame = frame
    frame:SetSize(UI.WIDTH, UI.HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetHyperlinksEnabled(true)
    frame:SetScript("OnHyperlinkEnter", function(self, link)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnHyperlinkLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    -- The dialog is parented to UIParent rather than to the window, so that its
    -- own scale and strata are Blizzard's; that means closing the window would
    -- otherwise leave a paste box floating with nothing behind it.
    frame:SetScript("OnHide", function()
        if frame.importDialog then
            frame.importDialog:Hide()
        end
    end)
    -- PortraitFrameTemplate's title is centred in a TitleContainer that starts
    -- 58 points in, clear of the portrait ring; TitleText is the font string
    -- inside it. Both are guarded: a client without them is a window with no
    -- title, not a broken addon.
    if frame.TitleText then
        frame.TitleText:SetText("Lootpath " .. ns.VERSION)
    end
    UI.ApplyPortrait(frame)

    buildImportDialog(frame)
    buildStatusStrip(frame)
    buildTabs(frame)

    local panel = UI.EquipPanel.Create(frame)
    panel.rowWidth = UI.WIDTH - 32
    frame.equipPanel = panel
    frame.upgradeMapPanel = ns.UpgradeMapPanel.Create(frame)
    frame.vaultPanel = ns.VaultPanel.Create(frame)
    -- Every tab's panel fills the same rectangle; only one is shown at a time.
    -- The tabs are on the frame's bottom edge now (M5-2), so the body runs from
    -- under the status strip to the frame's own bottom border: PortraitFrame
    -- has no inset frame to sit inside.
    for _, tab in ipairs(UI.TABS) do
        local tabPanel = frame[tab.key]
        tabPanel:SetPoint("TOPLEFT", frame.statusStrip, "BOTTOMLEFT", 2, -6)
        tabPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    end
    UI.ShowTab(frame, 1)
    -- The scale the owner chose (M5-2). Applied to the window only: the dialog
    -- and the minimap button are Blizzard-sized and are not part of it.
    frame:SetScale(UI.Options.GetScale())

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:SetScript("OnEvent", onEvent)

    -- Escape closes it, the way every Blizzard panel does. UISpecialFrames keys
    -- on the frame's global name, which is why this frame has one.
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = UI.FRAME_NAME
    end

    frame:Hide()
    return frame
end

function UI.Toggle()
    local frame = UI.Frame()
    if frame:IsShown() then
        frame:Hide()
        return false
    end
    frame:Show()
    UI.Refresh()
    return true
end

ns.onReady[#ns.onReady + 1] = function()
    UI.Options.Register()
    -- The launcher is built at load, not on first open: a button that only
    -- appears once you have already found the window is not a launcher. It
    -- costs one frame and reads the saved angle out of the DB, which is why it
    -- runs here rather than at file scope.
    UI.MinimapButton()
end
