-- Lootpath/UI/MainFrame.lua (M2-2, WKE-520)
-- The one window: the paste editbox that QE Live's answer arrives through, the
-- import status line, and the Equip Now panel. Native frames and Blizzard's own
-- templates only (decision 2026-09-05: Ace3 is AceDB, nothing else).
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
--
-- Nothing here reads the client in combat: the scan behind the panel is
-- ns.Inventory.Scan, which refuses in combat, and the refusal is what shows.

local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.FRAME_NAME = "LootpathMainFrame"
UI.WIDTH = 620
UI.HEIGHT = 640
UI.PASTE_INSTRUCTIONS = "Paste your QE Live Top Gear JSON here"

-- ISO 8601 in UTC, which is what QE Live's exportedAt is
-- ("2026-09-06T21:14:24.465Z", read from the committed export). Returns the
-- age in seconds, or nil when the string is not one of those.
function UI.AgeSeconds(iso, now)
    if type(iso) ~= "string" then
        return nil
    end
    local year, month, day, hour, minute, second = iso:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if not year then
        return nil
    end
    now = now or time()
    local fields = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second),
    }
    -- `time(t)` reads its fields as LOCAL time and `date("!*t", t)` writes UTC
    -- ones, so the difference between the two is this machine's offset from
    -- UTC, and adding it back turns UTC fields into an epoch. Nothing here
    -- assumes a timezone.
    local utcNow = date("!*t", now)
    if type(utcNow) ~= "table" then
        return nil
    end
    local offset = now - time(utcNow)
    return now - (time(fields) + offset)
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
    local line = string.format(
        "|cff40c057Imported|r %s, %s, exported %s, %d items",
        verdict.spec or "unknown spec",
        verdict.contentType or "unknown content type",
        UI.AgeText(verdict.exportedAt, now),
        #(verdict.topSet.order or {})
    )
    for _, warning in ipairs(result.warnings or {}) do
        line = line .. "\n|cffffd43bNote:|r " .. warning
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

function UI.VerdictNoteText()
    local verdict, contentType, fellBack = UI.ActiveVerdict()
    if not verdict then
        return "No QE Live export on this character yet."
    end
    if fellBack then
        return string.format(
            "|cffffd43bShowing the %s export|r - nothing has been pasted for %s yet.",
            contentType,
            UI.Options.Get()
        )
    end
    return string.format("Showing the %s export.", contentType)
end

function UI.Import(text)
    local result = ns.QEImport.Import(text)
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

function UI.Refresh()
    local frame = UI.frame
    if not frame then
        return nil
    end
    local verdict = UI.ActiveVerdict()
    frame.verdictNote:SetText(UI.VerdictNoteText())
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

    local panel = UI.EquipPanel.Create(frame)
    panel.rowWidth = UI.WIDTH - 32
    panel:SetPoint("TOPLEFT", frame.verdictNote, "BOTTOMLEFT", 0, -14)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    frame.equipPanel = panel

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
