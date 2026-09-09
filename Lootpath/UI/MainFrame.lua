-- Lootpath/UI/MainFrame.lua (M2-2, WKE-520; the three tabs added in M3-3, WKE-524)
-- The one window: the paste editbox that QE Live's answer arrives through, the
-- import status line, and one tab per promise - Equip Now, the Upgrade Map and
-- the Vault. Native frames and Blizzard's own templates only (decision
-- 2026-09-05: Ace3 is AceDB, nothing else).
--
-- Templates used, each read from Blizzard's shipped XML under .luals on
-- 2026-09-06 rather than remembered:
--   BasicFrameTemplateWithInset (Blizzard_UIPanelTemplates/UIPanelTemplates.xml)
--     inherits BasicFrameTemplate -> BaseBasicFrameTemplate, which is where
--     `TitleText` and `CloseButton` come from.
--   InputScrollFrameTemplate (Blizzard_SharedXML/SecureUIPanelTemplates.xml)
--     a ScrollFrame whose scroll child is a multiLine EditBox at parentKey
--     `EditBox`, with `maxLetters` defaulting to 0 and a `CharCount` label.
--     Its OnTextChanged writes `GetMaxLetters() - GetNumLetters()` into that
--     label, which is meaningless at maxLetters 0, so the label is hidden.
--   PanelTabButtonTemplate (Blizzard_SharedXML/SharedUIPanelTemplates.xml:905)
--     carries `parentArray="Tabs"`, so each tab appends itself to `frame.Tabs`.
--     WHICH tab is selected is Lootpath's own state (`UI.SelectTab`), because
--     that is what decides which panel is on screen; `PanelTemplates_SetTab`
--     and `PanelTemplates_SetNumTabs` are called for the selected/deselected
--     ARTWORK only, guarded, because a client without them must still tab.
--
-- Nothing here reads the client in combat: the scan behind the panel is
-- ns.Inventory.Scan, which refuses in combat, and the refusal is what shows.

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.FRAME_NAME = "LootpathMainFrame"
UI.WIDTH = 620
UI.HEIGHT = 640
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
    frame.verdictNote:SetText(UI.VerdictNoteText())
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

local function buildImportSection(frame)
    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32)
    label:SetText(UI.PASTE_INSTRUCTIONS)
    frame.pasteLabel = label

    local scroll = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -8)
    scroll:SetSize(UI.WIDTH - 40, 90)
    -- InputScrollFrame_OnTextChanged writes `maxLetters - numLetters` into
    -- CharCount, which is a large negative number once maxLetters is 0.
    scroll.hideCharCount = true
    if scroll.CharCount then
        scroll.CharCount:Hide()
    end
    frame.pasteScroll = scroll

    local editBox = scroll.EditBox
    editBox:SetAutoFocus(false)
    -- 0 = no limit. A Top Gear export is tens of kilobytes and WeakAuras moves
    -- strings that size through an editbox, so nothing here chunks the paste.
    editBox:SetMaxLetters(0)
    editBox:SetMultiLine(true)
    editBox:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)
    frame.pasteBox = editBox

    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(90, 22)
    importButton:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", -4, -10)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        UI.Import(editBox:GetText())
    end)
    frame.importButton = importButton

    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(90, 22)
    clearButton:SetPoint("LEFT", importButton, "RIGHT", 8, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        editBox:SetText("")
        frame.status:SetText("")
    end)
    frame.clearButton = clearButton

    local optionsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    optionsButton:SetSize(90, 22)
    optionsButton:SetPoint("LEFT", clearButton, "RIGHT", 8, 0)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function()
        UI.OpenOptions()
    end)
    frame.optionsButton = optionsButton

    local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", importButton, "BOTTOMLEFT", 4, -10)
    status:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    status:SetJustifyH("LEFT")
    status:SetText("")
    frame.status = status

    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -6)
    note:SetJustifyH("LEFT")
    frame.verdictNote = note
end

-- One tab per promise. The button art is Blizzard's; which panel it shows is
-- UI.SelectTab's.
local function buildTabs(frame)
    frame.tabs = {}
    for index, tab in ipairs(UI.TABS) do
        local button = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
        button:SetID(tab.id)
        button:SetText(tab.label)
        button:SetSize(110, 24)
        if index == 1 then
            button:SetPoint("TOPLEFT", frame.verdictNote, "BOTTOMLEFT", 0, -10)
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

local function onEvent(frame)
    if frame:IsShown() then
        UI.Refresh()
    end
end

function UI.Frame()
    if UI.frame then
        return UI.frame
    end
    local frame = CreateFrame("Frame", UI.FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
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
    if frame.TitleText then
        frame.TitleText:SetText("Lootpath " .. ns.VERSION)
    end

    buildImportSection(frame)
    buildTabs(frame)

    local panel = UI.EquipPanel.Create(frame)
    panel.rowWidth = UI.WIDTH - 32
    frame.equipPanel = panel
    frame.upgradeMapPanel = ns.UpgradeMapPanel.Create(frame)
    frame.vaultPanel = ns.VaultPanel.Create(frame)
    -- Every tab's panel fills the same rectangle; only one is shown at a time.
    for _, tab in ipairs(UI.TABS) do
        local tabPanel = frame[tab.key]
        tabPanel:SetPoint("TOPLEFT", frame.tabs[1], "BOTTOMLEFT", 4, -8)
        tabPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    end
    UI.ShowTab(frame, 1)

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
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
end
