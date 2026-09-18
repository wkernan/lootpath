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
-- R-6 (WKE-578): the badge on the launcher, in points. Small enough to be a
-- mark on a 31-point button and not a second icon.
UI.MINIMAP_DOT_SIZE = 9
-- UX-4b (WKE-611): the name-mark on the window's title. The ratio is the
-- texture's own - 256 x 64 - and drawing it at anything else would stretch the
-- word. The ink inside that texture measures 240 x 36 (read off the file's own
-- alpha, `tools/media/README.md`), so the letters stand 36/64 of this height.
UI.TITLE_WORDMARK_HEIGHT = 22
UI.TITLE_WORDMARK_RATIO = 4
-- M5-2c (WKE-609). The owner answered M5-0's window question on WKE-598,
-- 2026-09-16 night - "keep it dark and grow to 760" - so the window is finally
-- the width its mockups were drawn at, rather than the M2-2 size it had kept
-- while nobody had answered. The height is unchanged: no panel asked for more,
-- and the answer was about width. There is no light skin and none is built;
-- this addon is dark, the way the client is.
UI.WIDTH = 760
UI.HEIGHT = 640
-- The air a tab's panel leaves on each side of the window, and the only numbers
-- in this addon's panel widths that are not derived from one of them. They are
-- margins, not widths: the strip starts UI.STRIP_INSET in from the frame
-- (buildStatusStrip), a panel's TOPLEFT hangs off the strip's BOTTOMLEFT two
-- points further in, and a panel's BOTTOMRIGHT is UI.PANEL_INSET_RIGHT in from
-- the frame's right edge.
UI.STRIP_INSET = 12
UI.PANEL_INSET_LEFT = UI.STRIP_INSET + 2
UI.PANEL_INSET_RIGHT = 12
-- What a tab's panel is actually given, and the one width every panel derives
-- its own default from. In the client the two corner anchors are what size a
-- panel; this is the same arithmetic done ahead of them, so a panel built on
-- its own - which is what the render tests do - is the size the window would
-- have made it. `spec/ui_spec.lua` proves the anchors and this number agree.
UI.PANEL_WIDTH = UI.WIDTH - UI.PANEL_INSET_LEFT - UI.PANEL_INSET_RIGHT
UI.DIALOG_WIDTH = 520
UI.DIALOG_HEIGHT = 260
UI.PASTE_INSTRUCTIONS = "Paste your Top Gear or Upgrade Finder JSON here"

-- Which build this is (UX-4b, WKE-611). The window's title carries the
-- name-mark now and no words, so the version lives at the foot of the status
-- strip's tooltip - which is where a reader already goes to ask how old any of
-- this is. `ns.VERSION` is `dev` when the packager's token was never replaced
-- (Core.lua), so this never prints `@project-version@`.
function UI.VersionText()
    return "Lootpath " .. tostring(ns.VERSION)
end

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

-- "1 hour", "4 hours". English's own plural, written once, because every
-- surface that prints an age reads it through `UI.AgeText` and the voice rule
-- is that it sounds like a person: "4 hour(s) ago" is a format string that
-- escaped onto a screen (R-2a, WKE-571; the owner read it on a tooltip,
-- 2026-09-14). Only the four nouns below are ever counted here, and none of
-- them is irregular, so an "s" is the whole rule.
function UI.Plural(count, noun)
    return string.format("%d %s", count, count == 1 and noun or (noun .. "s"))
end

function UI.AgeText(iso, now)
    local seconds = UI.AgeSeconds(iso, now)
    if not seconds then
        return type(iso) == "string" and iso or "at an unknown time"
    end
    return UI.AgeTextFromSeconds(seconds)
end

-- The same words off an elapsed count rather than a stamp (R-7c, WKE-594). A
-- capture snapshot records `capturedAt` as the client's own epoch and nothing
-- else, so a surface asking how old the last good read is has the seconds
-- already and no ISO string to hand `UI.AgeText`. One formatter, two ways in;
-- `nil` for a count that is not a number, which is the caller's "say nothing".
function UI.AgeTextFromSeconds(seconds)
    if type(seconds) ~= "number" then
        return nil
    end
    if seconds < 5 then
        return "just now"
    end
    if seconds < 90 then
        return UI.Plural(math.floor(seconds), "second") .. " ago"
    end
    if seconds < 5400 then
        return UI.Plural(math.floor(seconds / 60 + 0.5), "minute") .. " ago"
    end
    if seconds < 172800 then
        return UI.Plural(math.floor(seconds / 3600 + 0.5), "hour") .. " ago"
    end
    return UI.Plural(math.floor(seconds / 86400 + 0.5), "day") .. " ago"
end

-- The two exports the paste box takes, and what each is called on screen. The
-- kind travels on the import result so the status line can name it: the two
-- exports answer different questions, and an owner who pasted the wrong one has
-- to be able to see that from the line. The line names the export, never the
-- engine that wrote it (V-1, WKE-569).
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
-- written 4 minutes ago" (C-2). The source is on the line the window keeps,
-- not the status line the next paste overwrites.
--
-- Since V-2 (WKE-573) the sentence names the EXPORT as well as the content
-- type - "the Dungeon Top Gear export" - because the strip's line no longer
-- does and this sentence is where the strip's tooltip keeps it. Nothing is
-- lost, only moved: the same two words, one surface further in.
function UI.VerdictNoteText(now)
    local verdict, contentType, fellBack = UI.ActiveVerdict()
    if not verdict then
        return "No export on this character yet."
    end
    local source = ns.Companion.SourceText(verdict, now)
    local export = string.format("%s %s", contentType or "unknown content type", UI.KIND_LABEL[UI.KIND_TOP_GEAR])
    if fellBack then
        return string.format(
            "|cffffd43bShowing the %s export|r (%s) - nothing has been imported for %s yet.",
            export,
            source,
            UI.Options.Get()
        )
    end
    return string.format("Showing the %s export (%s).", export, source)
end

-- ---------------------------------------------------------------------------
-- M5-2 (WKE-551): the status strip.

-- The separator between the strip's facts. One glyph rather than a dash so the
-- five facts read as five; whether it renders on the owner's screen is an eye
-- test (M5-5, WKE-554), not something this file can claim.
UI.SEPARATOR = " \194\183 "

-- R-6 (WKE-578): the strip is one row of facts, and the nudge is a SECOND row
-- under it - a clause that can be clicked. It is its own row rather than a
-- fifth fact on the first, because the first row is already four facts wide and
-- R-3a's lesson (WKE-570, the owner's screen 2026-09-14) is that a fact past
-- the window's width is a fact nobody reads. The strip grows by the row's
-- height when there is something to say, and every tab's panel hangs off the
-- strip's BOTTOMLEFT, so the body moves down with it and nothing overlaps.
UI.STRIP_HEIGHT = 22
UI.NUDGE_HEIGHT = 18

-- M5-2b (WKE-601): how far below the frame's own top edge the strip's row
-- starts. The owner's screen on 2026-09-16 read the strip's first characters
-- UNDER the portrait ring - "the copy is being covered by the Spec symbol in
-- the top left corner - let's move it down" - so the strip is a full-width row
-- BELOW the ring rather than a line that starts beside it. It costs the body a
-- row of height and the owner priced that in.
--
-- The ring's bottom edge is Blizzard's geometry, read from the template this
-- frame inherits: in PortraitFrameBaseTemplate the `PortraitContainer` is
-- anchored to the frame's TOPLEFT at (0, 0) and its `portrait` texture is
-- 62 x 62 anchored TOPLEFT at (-5, 7) - Blizzard_SharedXML/Mainline/
-- SharedUIPanelTemplates.xml:544-566, the same file and the same read as the
-- 58-point title inset this file already records. So the ring's bottom sits
-- 7 - 62 = 55 points under the frame's top. The air under it is this addon's.
UI.RING_BOTTOM = 55
UI.STRIP_GAP = 4
UI.STRIP_TOP = UI.RING_BOTTOM + UI.STRIP_GAP
UI.NO_VERDICT_STRIP = "No export on this character yet \194\183 Import... to paste one"
UI.STALE_STRIP_TOOLTIP =
    "This export was made before the last weekly reset. If the companion is running it should be newer than that."

-- Which named scenario the Vault tab's pick follows, in the
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

-- The one line under the title: what is on screen, whose it is, how old, and
-- what the companion last did - `spec | source, age | scenario tag |
-- companion` since V-2 (WKE-573) dropped the content type and the export's
-- name off it into the tooltip, from the same facts
-- UI.VerdictNoteText states in a sentence, ns.Companion.SourceText names the
-- source with and ns.Companion.StatusText reads out of the companion's own
-- status file. Returns a model rather than a string so the age can be toned
-- amber without the tests reading colour codes: { text, stale, companion,
-- tooltip }.
--
-- `stale` is VaultPanel.IsVerdictStale over the client's own reset boundary -
-- an export older than the last weekly reset, which is the tell ARCHITECTURE.md
-- 11 named for a companion watcher that has died. Since C-9 (WKE-559) the
-- companion clause says it outright instead, and the amber age is the second
-- opinion. nil (not false) when the client does not say when the reset is; only
-- a true makes the age amber.
--
-- **M3-16b (WKE-583): while a refresh is out there, the WAIT is the line.** R-6
-- put it on the strip's second row and the owner never found it - his screen on
-- 2026-09-15 read `...on Druid - companion, written 4 hours ago - vault pick:
-- everything upgraded - companion: run st...`, cut at the window's width, and
-- the one line that would have told him the rating was still being made was
-- below it and past the cut. So the wait line replaces the facts
-- on the strip's own row - first, alone, and short enough not to be cut - and
-- the four facts go one surface in, to this tooltip, the way V-2 moved the
-- content type. Nothing is lost and the wait cannot be scrolled off the end.
-- It is the row the mouse already takes, so it is also the row that carries the
-- click while the wait is on (`UI.StripClick`).
function UI.StatusStripModel(now)
    -- The wait, and only the wait: the `behind` nudge stays on its own row,
    -- where a player who has not acted yet reads it. One model for both, so the
    -- strip, the row and the minimap badge cannot disagree (R-6).
    local drift = ns.Drift and ns.Drift.Model and ns.Drift.Model(now) or nil
    local wait = drift and drift.kind == "wait" and drift or nil
    -- The strip's line, out of the facts it would carry and the wait that
    -- displaces them. The displaced facts go to the TOP of the tooltip, under
    -- the wait's own sentence: they are the line the reader was looking at a
    -- moment ago, and the sentence says what took their place.
    --
    -- **R-7b (WKE-591): the spec disagreement displaces them the same way, and
    -- the wait wins over it.** A plan rated for a spec the player is not in is
    -- a plan about gear he is not wearing, and every fact on the line is a fact
    -- about that plan - so the sentence that says which spec it is for belongs
    -- where the facts were, not a surface in, for the same reason M3-16b moved
    -- the wait there. It is rare by construction: it says nothing at all unless
    -- the two specs genuinely disagree.
    --
    -- **R-7c (WKE-594): the gear the plan is about can be older than the plan,
    -- and that displaces the facts the same way.** A logout never reads the
    -- gear, so the newest stored read can be a day behind what the player is
    -- wearing; every fact on the line is then a fact about a plan for gear he
    -- took off yesterday. It goes AHEAD of the spec clause, because a plan
    -- rated for the wrong gear is wrong whichever spec it was rated in, and
    -- behind the wait, because a player who has already clicked is owed the
    -- news about the run he asked for.
    -- **H-1 (WKE-596): when the Coming soon screen is up, the spec clause is
    -- not.** The screen names the spec, says what Lootpath rates and names the
    -- spec to switch to; the strip's clause would say the same thing a second
    -- time, one row above it. The strip keeps its four facts - they are true in
    -- any spec - and one thing says the rest.
    local gated = ns.Companion.Gate and ns.Companion.Gate() ~= nil or false
    local specClause = (not gated) and ns.Companion.SpecClauseNow and ns.Companion.SpecClauseNow() or nil
    local gearClause = ns.Drift and ns.Drift.GearUnreadText and ns.Drift.GearUnreadText(now) or nil
    local clauses = {}
    if gearClause then
        clauses[#clauses + 1] = gearClause
    end
    if specClause then
        clauses[#clauses + 1] = specClause
    end
    -- Returns the line AND the clauses it is made of, in the order they are
    -- written. M5-2b (WKE-601): the drawer fits that list to the strip's real
    -- width by dropping whole clauses from the right, so the model owes it the
    -- list rather than only the sentence.
    local function lineFrom(parts, tooltip)
        if not wait and #clauses == 0 then
            return table.concat(parts, UI.SEPARATOR), parts
        end
        table.insert(tooltip, 1, table.concat(parts, UI.SEPARATOR))
        if wait then
            table.insert(tooltip, 1, wait.tooltip)
            for _, clause in ipairs(clauses) do
                tooltip[#tooltip + 1] = clause
            end
            return wait.text, { wait.text }
        end
        -- The first clause takes the line; a second goes under the facts it
        -- displaced, where the reader was looking a moment ago.
        for index = 2, #clauses do
            tooltip[#tooltip + 1] = clauses[index]
        end
        return clauses[1], { clauses[1] }
    end
    -- The content type is deliberately dropped on the floor here: since V-2 it
    -- is the tooltip's, through UI.VerdictNoteText, and not the line's.
    local verdict, _, fellBack = UI.ActiveVerdict()
    local tooltip = { UI.VerdictNoteText(now) }
    -- C-9 (WKE-559): the sixth fact, and the only one that is about the
    -- companion rather than the export - what its last run did. It is on the
    -- line even with no export at all, because "companion: FAILED at profile"
    -- is exactly what an empty window needs to say.
    local companion = ns.Companion.StatusText(ns.companionStatus, now)
    -- Last of the facts, always: the lines above it are about the export on
    -- screen, and a reader looking for why there is no newer one reads down.
    -- (Since UX-4b the version sits one line below it, which is a label rather
    -- than a fact about the export, and so does not displace it.)
    local companionNote = ns.Companion.StatusTooltip(ns.companionStatus, now)
    -- R-2 (WKE-563): which bag window the mark is drawn in, or that this one is
    -- not a window Lootpath can mark. It is on the tooltip rather than the line
    -- because it is about a surface outside this window, and a reader only
    -- looks for it when the mark is missing; it goes ABOVE the companion's
    -- sentence, which stays last for the reason given above it.
    local bagNote = ns.UI.Bags and ns.UI.Bags.StatusText() or nil
    if not verdict then
        if bagNote then
            tooltip[#tooltip + 1] = bagNote
        end
        if companionNote then
            tooltip[#tooltip + 1] = companionNote
        end
        tooltip[#tooltip + 1] = UI.VersionText()
        local emptyText, emptyParts = lineFrom({ UI.NO_VERDICT_STRIP, companion }, tooltip)
        return {
            text = emptyText,
            parts = emptyParts,
            companion = companion,
            wait = wait,
            specClause = specClause,
            gearClause = gearClause,
            tooltip = tooltip,
        }
    end
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
    -- V-2 (WKE-573): FOUR facts, not five. `Dungeon Top Gear` used to sit
    -- second and the line was cut at the window's width with C-9's companion
    -- clause - the one fact on it a player acts on - the half lost (R-3a,
    -- WKE-570; the owner's screen, 2026-09-14). The content type is already on
    -- the Vault tab's dropdown and the Upgrade Map's filter, and both words are
    -- kept in this strip's own tooltip through UI.VerdictNoteText, so dropping
    -- them here moves a fact rather than losing one (owner's decision,
    -- 2026-09-14 evening).
    local parts = {
        verdict.spec or "unknown spec",
        source,
        UI.SCENARIO_TAG[scenario] or ("vault pick: " .. tostring(scenario)),
        companion,
    }
    local other = UI.OtherImportLine(UI.KIND_TOP_GEAR, verdict, now)
    if other then
        tooltip[#tooltip + 1] = other
    end
    if bagNote then
        tooltip[#tooltip + 1] = bagNote
    end
    if companionNote then
        tooltip[#tooltip + 1] = companionNote
    end
    tooltip[#tooltip + 1] = UI.VersionText()
    local text, shown = lineFrom(parts, tooltip)
    return {
        text = text,
        parts = shown,
        stale = stale,
        fellBack = fellBack,
        companion = companion,
        wait = wait,
        specClause = specClause,
        gearClause = gearClause,
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

-- The window's title (UX-4b, WKE-611). PortraitFrameTemplate centres a
-- TitleContainer 58 points in, clear of the portrait ring, with TitleText inside
-- it; the name-mark is a texture in that container and TitleText is blanked, so
-- the template still owns the layout and nothing draws twice.
--
-- The version it used to carry is the last line of the status strip's tooltip
-- now (UI.VersionText), which is where a reader already goes to ask how old any
-- of this is.
--
-- Returns "wordmark" or "text", so a test can say which way it went. The text
-- way is the guard, not a design: a client with no TitleContainer to hang a
-- texture on gets the name in words, because a window with a plain title is a
-- better answer than a window with no title.
function UI.ApplyTitle(frame)
    frame = frame or UI.frame
    if not (frame and frame.TitleText) then
        return nil
    end
    local container = frame.TitleContainer
    if not (container and type(container.CreateTexture) == "function") then
        frame.TitleText:SetText("Lootpath")
        return "text"
    end
    local wordmark = container:CreateTexture(nil, "OVERLAY")
    wordmark:SetSize(UI.TITLE_WORDMARK_HEIGHT * UI.TITLE_WORDMARK_RATIO, UI.TITLE_WORDMARK_HEIGHT)
    wordmark:SetPoint("CENTER", container, "CENTER", 0, 0)
    wordmark:SetTexture(UI.MEDIA.WORDMARK)
    wordmark:SetVertexColor(ns.UI.ItemLine.RGB(UI.BRAND_HEX))
    frame.titleWordmark = wordmark
    frame.TitleText:SetText("")
    return "wordmark"
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

-- M5-2a (WKE-593): what the minimap button shows, in the same three steps
-- ApplyPortrait takes and from the same two readers - the spec icon, else the
-- class circle with its four coordinates, else the question mark. Returns the
-- texture, its coordinates (nil meaning the whole texture), and which of the
-- three it is, so the button and the window can never disagree about the spec
-- and a question mark is only ever a client that names neither spec nor class.
UI.MINIMAP_FALLBACK_ICON = "Interface/Icons/INV_Misc_QuestionMark"

function UI.MinimapIcon()
    local icon = UI.SpecIcon()
    if icon then
        return icon, nil, "spec"
    end
    local coords = UI.ClassIconCoords()
    if coords then
        return UI.CLASS_ICON_FILE, coords, "class"
    end
    return UI.MINIMAP_FALLBACK_ICON, nil, "fallback"
end

-- LibDBIcon trims 5% off each edge of whatever coordinates an icon carries
-- (`updateCoord`, LibDBIcon-1.0 minor 55), which is what keeps a square icon's
-- outer edge from touching the tracking ring. The 5% is of the RANGE, not of
-- the axis, so a class circle's quarter of the sheet is trimmed by a quarter as
-- much and stays centred on its own art.
UI.MINIMAP_ICON_TRIM = 0.05

function UI.TrimIconCoords(coords)
    local c = coords or { 0, 1, 0, 1 }
    local dx = (c[2] - c[1]) * UI.MINIMAP_ICON_TRIM
    local dy = (c[4] - c[3]) * UI.MINIMAP_ICON_TRIM
    return c[1] + dx, c[2] - dx, c[3] + dy, c[4] - dy
end

-- Puts that icon on the button, trimmed. Called at creation and from every
-- event that can change the answer, on the button itself and in the window's
-- handler, so the icon is right without the window ever having been opened.
function UI.ApplyMinimapIcon(button)
    button = button or UI.minimapButton
    local icon = button and button.icon
    if not icon then
        return nil
    end
    local texture, coords, kind = UI.MinimapIcon()
    icon:SetTexture(texture)
    icon:SetTexCoord(UI.TrimIconCoords(coords))
    return kind
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
    -- H-1 (WKE-596): in a non-healer spec the body is the screen and no panel
    -- is drawn at all - not even the one that was on top when the spec changed.
    -- `ShowTab` is called rather than only hiding, so the tabs and the screen
    -- follow the gate in one place; it is also what puts them back.
    if ns.Companion.Gate and ns.Companion.Gate() then
        UI.ShowTab(frame, frame.selectedTab or 1)
        return nil
    end
    if frame.comingSoon and frame.comingSoon:IsShown() then
        UI.ShowTab(frame, frame.selectedTab or 1)
    end
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
    -- H-1 (WKE-596): the healing gate. The tab the player last had open is
    -- still `frame.selectedTab` - nothing forgets where he was - but in a
    -- non-healer spec no panel is shown, the tabs cannot be clicked, and the
    -- Coming soon screen has the body to itself. Read live on every call, so
    -- changing spec back and calling this again puts the tabs on screen with no
    -- reload.
    local gated = ns.Companion.Gate and ns.Companion.Gate() ~= nil or false
    for _, tab in ipairs(UI.TABS) do
        local panel = frame[tab.key]
        if panel then
            panel:SetShown(not gated and tab.id == wanted)
        end
    end
    for _, button in ipairs(frame.tabs or {}) do
        if type(button.SetEnabled) == "function" then
            button:SetEnabled(not gated)
        end
    end
    -- H-1a (WKE-606): the strip is part of what the screen replaces, so it is
    -- shown and hidden here beside it - `UI.Frame` opens the window through
    -- this function and nothing else, and a redraw that comes in through
    -- `UI.RefreshStrip` sets the same flag from the same read.
    if frame.statusStrip then
        frame.statusStrip:SetShown(not gated)
        -- R-8a (WKE-618): a show is the one moment the row's order could change,
        -- so the buttons are put back above the strip right after it. This is
        -- the show a TAB CLICK goes through, which reaches no other redraw.
        UI.RaiseStripButtons(frame)
    end
    if frame.comingSoon then
        frame.comingSoon:SetShown(gated)
        if gated then
            UI.RefreshComingSoon(frame)
        end
    end
    if type(_G.PanelTemplates_SetTab) == "function" then
        PanelTemplates_SetTab(frame, wanted)
    end
    -- Equip Now opens at its first row: the scroll frame keeps its offset while
    -- the tab is hidden, so a player who scrolled down, switched tab and came
    -- back would otherwise find the list already part way through
    -- (M5-1a, WKE-597).
    if wanted == 1 and frame.equipPanel and UI.EquipPanel then
        UI.EquipPanel.ScrollToTop(frame.equipPanel)
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
        dialog.TitleText:SetText("Import an export")
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

-- R-6 (WKE-578): the nudge. One clause, on its own row under the strip, that
-- the player can click - the only place in the addon a click reloads, and the
-- only place it needs to be, because `ReloadUI` is allowed from a hardware
-- event and nowhere else.
--
-- A bare Button with its own font string rather than UIPanelButtonTemplate: it
-- is a sentence the reader acts on, not a control, and the Upgrade Map's
-- section and run cards are built the same way.
local function buildNudgeRow(frame, strip)
    local button = CreateFrame("Button", nil, strip)
    button:SetPoint("TOPLEFT", strip, "TOPLEFT", 2, -UI.STRIP_HEIGHT)
    button:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -2, -UI.STRIP_HEIGHT)
    button:SetHeight(UI.NUDGE_HEIGHT)
    frame.nudgeButton = button

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture("Interface/Buttons/WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.08)

    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("LEFT", button, "LEFT", 0, 0)
    label:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    button.label = label

    button:SetScript("OnClick", function()
        ns.Drift.Click()
        UI.RefreshStrip(frame)
    end)
    button:SetScript("OnEnter", function(self)
        if not (GameTooltip and frame.nudgeModel) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(frame.nudgeModel.text)
        if frame.nudgeModel.tooltip then
            GameTooltip:AddLine(frame.nudgeModel.tooltip, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    button:Hide()
    return button
end

-- The status strip: one line of facts under the title, and the two buttons that
-- used to sit under the paste box. The strip itself takes the mouse so the
-- facts that do not fit on one line - the sentence UI.VerdictNoteText states,
-- the other stored export, why an amber age is amber - are one hover away.
local function buildStatusStrip(frame)
    local strip = CreateFrame("Frame", nil, frame)
    -- Below the ring, full width, on its own row (M5-2b): UI.STRIP_TOP is the
    -- ring's own bottom edge plus the air under it.
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.STRIP_INSET, -UI.STRIP_TOP)
    strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.STRIP_INSET, -UI.STRIP_TOP)
    strip:SetHeight(UI.STRIP_HEIGHT)
    strip:EnableMouse(true)
    frame.statusStrip = strip

    -- H-1a (WKE-606): the two buttons are the FRAME's children, anchored to the
    -- strip's row. They were the strip's own, and a child of a hidden frame is
    -- hidden with it - so taking the strip off the screen over the Coming soon
    -- screen would have taken Import and Options with it. A point is resolved
    -- whether or not the frame it hangs off is shown, so the row they sit on is
    -- exactly where it was.
    local optionsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    optionsButton:SetSize(74, 20)
    optionsButton:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function()
        UI.OpenOptions()
    end)
    frame.optionsButton = optionsButton

    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(80, 20)
    importButton:SetPoint("RIGHT", optionsButton, "LEFT", -6, 0)
    importButton:SetText("Import...")
    importButton:SetScript("OnClick", function()
        UI.ToggleImportDialog()
    end)
    frame.openImportButton = importButton

    -- R-8 (WKE-616): the third button on the row, and the one the strip's own
    -- sentences used to spell out as a command. It is a FRAME child like the
    -- other two (H-1a) and for the same reason: a refresh is never wrong to
    -- offer, so it stays on screen over the Coming soon screen as well, where
    -- its click reaches `Companion.Refresh` and gets that screen's own refusal
    -- instead of a rating nobody asked for. The click is `ns.Drift.Click` - the
    -- same function the strip's wait click and `/lootpath refresh` reach, so a
    -- rating that is ready loads and anything else refreshes - and an OnClick is
    -- the hardware event `ReloadUI` requires (M3-16a).
    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshButton:SetSize(74, 20)
    refreshButton:SetPoint("RIGHT", importButton, "LEFT", -6, 0)
    refreshButton:SetText(ns.Drift.REFRESH_LABEL)
    refreshButton:SetScript("OnClick", function()
        ns.Drift.Click()
        UI.RefreshStrip(frame)
    end)
    -- The hover says what THIS press will do, in this state (Drift.RefreshTooltip),
    -- including the one state in which it will do nothing: combat, where the
    -- button is greyed out the way the Equip buttons are. A disabled button gets
    -- no OnEnter unless it is told to take one - `SetMotionScriptsWhileDisabled`
    -- is Blizzard's own, read in the exported documentation under `.luals/`
    -- (SimpleButtonAPIDocumentation:395, Core/Widget/Frame/Button/Button.lua:170)
    -- - so the combat line has a surface to be read on. Guarded: a client that
    -- does not carry it loses the hover, not the button.
    if type(refreshButton.SetMotionScriptsWhileDisabled) == "function" then
        refreshButton:SetMotionScriptsWhileDisabled(true)
    end
    refreshButton:SetScript("OnEnter", function(button)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.Drift.RefreshTooltip(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    refreshButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    frame.refreshButton = refreshButton

    local text = strip:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", strip, "LEFT", 2, 0)
    text:SetPoint("RIGHT", refreshButton, "LEFT", -8, 0)
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
    -- The wait's click (M3-16b). While the wait is the strip's first clause it
    -- is also the strip's click, so the sentence `click to load it` is true of
    -- the row it is written on; with no wait on the strip the row is facts and
    -- the press does nothing. `OnMouseUp` rather than an OnClick because the
    -- strip is a Frame with two buttons of its own on it, and it is a hardware
    -- event either way, which is what `ReloadUI` requires (M3-16a).
    strip:SetScript("OnMouseUp", function()
        UI.StripClick(frame)
    end)

    buildNudgeRow(frame, strip)
    -- R-8a (WKE-618): and the three of them come up one level, once they all
    -- exist. The nudge row's button is not in that list: it is the STRIP's own
    -- child, so the client already puts it a level above its parent, and it sits
    -- on the row below rather than under the strip's mouse.
    UI.RaiseStripButtons(frame)
end

-- R-8a (WKE-618): the strip's buttons sit ABOVE the strip.
--
-- Since H-1a (WKE-606) `Options` and `Import...` - and since R-8 `Refresh` - are
-- the FRAME's children rather than the strip's, for a reason that stands: a
-- child of a hidden frame is hidden with it, and those three stay on screen over
-- the Coming soon screen. But a frame's default level is its parent's plus one,
-- so the strip and the three buttons all came out at the SAME level, and the
-- strip - which takes the mouse, for M3-16b's wait click - swallowed every press
-- on them. The owner's `/fstack` over `Refresh` on `main` `4279b37` read the
-- strip above the button, both at 2.
--
-- One list, so a fourth button on this row cannot forget it: every key it names
-- is put one level above the strip, and it is re-asserted wherever the strip is
-- shown again, because nothing in Blizzard's exported documentation says what a
-- re-show does to the order of two siblings that share a level.
UI.STRIP_BUTTON_KEYS = { "refreshButton", "openImportButton", "optionsButton" }

function UI.RaiseStripButtons(frame)
    frame = frame or UI.frame
    local strip = frame and frame.statusStrip
    if not (strip and type(strip.GetFrameLevel) == "function") then
        return nil
    end
    local level = strip:GetFrameLevel() + 1
    for _, key in ipairs(UI.STRIP_BUTTON_KEYS) do
        local button = frame[key]
        if button and type(button.SetFrameLevel) == "function" then
            button:SetFrameLevel(level)
        end
    end
    return level
end

-- What a press on the strip does: the wait's own click when the strip is
-- carrying the wait, and nothing at all otherwise. Returns what `Drift.Click`
-- returned, or nil.
function UI.StripClick(frame)
    frame = frame or UI.frame
    if not (frame and frame.stripModel and frame.stripModel.wait) then
        return nil
    end
    return ns.Drift.Click()
end

-- M5-2b (WKE-601): the line the strip can actually show. The facts are in the
-- order M3-16b / V-2 settled - spec, source and age, vault pick, companion -
-- and the last of them is the one a player acts on, so a line too long for the
-- row loses WHOLE clauses from the right rather than half a word: the owner's
-- screen on 2026-09-16 ended `... companion: pr...` and that half-word said
-- nothing. Every clause dropped here is already in the strip's tooltip, which
-- the model built from the same facts, so nothing is lost by the drop.
--
-- Pure: `measure` answers the width of a candidate line (the client's own
-- GetStringWidth, in the drawer below), `width` is the room the row has.
-- With no width to fit into, or nothing that can measure, the whole line is
-- returned unchanged - a headless caller and a client that has not laid the
-- row out yet both read the same as before this issue.
--
-- Returns the text and how many clauses it carries.
function UI.FitStripText(parts, width, measure)
    parts = parts or {}
    local whole = table.concat(parts, UI.SEPARATOR)
    if #parts == 0 then
        return "", 0
    end
    if type(measure) ~= "function" or type(width) ~= "number" or width <= 0 then
        return whole, #parts
    end
    for count = #parts, 2, -1 do
        local candidate = table.concat(parts, UI.SEPARATOR, 1, count)
        local measured = measure(candidate)
        if type(measured) ~= "number" or measured <= width then
            return candidate, count
        end
    end
    -- The first clause always stays, even when it is too wide for the row: a
    -- strip with nothing on it says less than one that is cut.
    return parts[1], 1
end

-- What the strip's own row can hold, and how to measure a line against it: the
-- font string's width once the client has laid the row out, and the client's
-- own GetStringWidth (FontString.lua:115). Both guarded - a headless run has
-- neither and gets nil, which UI.FitStripText reads as "do not shorten".
local function stripFitter(text)
    local width
    if type(text.GetWidth) == "function" then
        local ok, value = pcall(text.GetWidth, text)
        if ok and type(value) == "number" then
            width = value
        end
    end
    if type(text.GetStringWidth) ~= "function" then
        return width, nil
    end
    return width,
        function(candidate)
            text:SetText(candidate)
            local ok, measured = pcall(text.GetStringWidth, text)
            if ok and type(measured) == "number" then
                return measured
            end
            return nil
        end
end

-- Redraws the strip from the facts as they are now. Its own function because
-- UI.Refresh calls it on every redraw and the launcher's toggle does not.
function UI.RefreshStrip(frame)
    frame = frame or UI.frame
    if not frame or not frame.stripText then
        return nil
    end
    -- R-8 (WKE-616): the Refresh button is on screen in every state the strip
    -- can be in, INCLUDING the gated one below, so its combat lock is set here,
    -- ahead of the gate's early return. `PLAYER_REGEN_DISABLED` and
    -- `PLAYER_REGEN_ENABLED` both reach `UI.Refresh` while the window is up, so
    -- the grey arrives with the fight and leaves with it.
    if frame.refreshButton and type(frame.refreshButton.SetEnabled) == "function" then
        frame.refreshButton:SetEnabled(not (type(InCombatLockdown) == "function" and InCombatLockdown()))
    end
    -- H-1a (WKE-606): while the Coming soon screen is up the strip is not.
    -- H-1 left its four facts on the row over a screen that has just said the
    -- one fact a player who is not healing is owed - the age of the rating - and
    -- the owner read `Restoration Druid - companion, written 3 minutes ago` over
    -- `Coming soon for Guardian.`: the healing set's facts, shown to a tank.
    -- The row comes off, and the model with it, so the tooltip and the click
    -- have nothing to say either (a hidden frame gets no OnEnter in the client;
    -- `stripModel` nil is what makes `UI.StripClick` return nothing here). Read
    -- live, never remembered: the spec change back puts the row on screen with
    -- the tabs, with no reload.
    local gated = ns.Companion.Gate and ns.Companion.Gate() ~= nil or false
    frame.statusStrip:SetShown(not gated)
    UI.RaiseStripButtons(frame)
    if gated then
        frame.stripModel = nil
        frame.stripText:SetText("")
        UI.RefreshNudge(frame)
        return nil
    end
    local model = UI.StatusStripModel()
    frame.stripModel = model
    local width, measure = stripFitter(frame.stripText)
    local parts = model.parts or { model.text }
    local text, shown = UI.FitStripText(parts, width, measure)
    model.shownClauses = shown
    -- What came off the row goes one surface in, the way M3-16b and V-2 moved a
    -- fact before it: the WHOLE line heads the tooltip, so a clause the row
    -- could not hold is one hover away and the drop loses nothing.
    if shown < #parts then
        table.insert(model.tooltip, 1, model.text)
    end
    frame.stripText:SetText(text)
    UI.RefreshNudge(frame)
    return model
end

-- Draws, or takes away, the second row. The strip's own height carries it, so
-- the tabs' panels - anchored to the strip's BOTTOMLEFT - move with it, and the
-- window has no gap when there is nothing to nudge about.
--
-- Since M3-16b (WKE-583) the row is the NUDGE's alone: the wait is the strip's
-- own first clause, where it cannot be missed, and drawing it here as well
-- would say one thing twice.
function UI.RefreshNudge(frame)
    frame = frame or UI.frame
    if not (frame and frame.nudgeButton) then
        return nil
    end
    -- H-1a (WKE-606): and the row under the strip goes with the strip. Drift
    -- already takes the nudge down on the spec change itself (H-1), so this is
    -- the second lock rather than the first: a redraw that arrives from any
    -- other direction while the gate is up still finds the row off.
    local gated = ns.Companion.Gate and ns.Companion.Gate() ~= nil or false
    local drift = not gated and ns.Drift.Model() or nil
    local model = drift and drift.kind == "behind" and drift or nil
    frame.nudgeModel = model
    if not model then
        frame.nudgeButton:Hide()
        frame.statusStrip:SetHeight(UI.STRIP_HEIGHT)
        UI.RefreshMinimapDot()
        return nil
    end
    frame.nudgeButton.label:SetText(model.text)
    frame.nudgeButton:Show()
    frame.statusStrip:SetHeight(UI.STRIP_HEIGHT + UI.NUDGE_HEIGHT)
    UI.RefreshMinimapDot()
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
-- H-1 (WKE-596): the window in a non-healer spec.
--
-- **Three lines and nothing else.** The owner's words, 2026-09-16: "Lootpath is
-- strictly to help healers... I'd like a Coming Soon screen for any other spec,
-- and nothing about healing items when I'm not healing." So the three tab
-- panels are hidden, the three tabs are disabled, and this fills the body:
-- which spec he is in, what Lootpath rates and which spec of his class rates it,
-- and how old the rating waiting for him is. Import and Options stay reachable -
-- they sit on the strip, not in the body - and the strip stays, because its four
-- facts are true whichever spec he is standing in.
--
-- The age is read exactly as the strip reads it: the companion's `writtenAt`
-- when the file wrote this one and the export's own `exportedAt` otherwise
-- (`ns.Companion.SourceText` reads the same pair), through `UI.AgeText` so one
-- formatter says every age on screen.
UI.COMING_SOON_TITLE = "Coming soon for %s."
UI.COMING_SOON_BODY = "Lootpath rates healing gear for now. Switch to %s and it's all here."
UI.COMING_SOON_BODY_NO_HEALER = "Lootpath rates healing gear for now."
UI.COMING_SOON_AGE = "Last rated %s."
UI.COMING_SOON_NO_AGE = "Not rated yet."

-- nil when the gate is down and the tabs are the window, or the three lines.
-- Pure over the client's role read and the rating on screen, so a test drives it
-- with no frame at all.
function UI.ComingSoonModel(now)
    local gate = ns.Companion.Gate and ns.Companion.Gate() or nil
    if not gate then
        return nil
    end
    local verdict = UI.ActiveVerdict()
    local stamp = verdict and (verdict.companionWrittenAt or verdict.exportedAt) or nil
    local age = UI.COMING_SOON_NO_AGE
    if type(stamp) == "string" then
        age = string.format(UI.COMING_SOON_AGE, UI.AgeText(stamp, now))
    end
    return {
        title = string.format(UI.COMING_SOON_TITLE, gate.spec),
        body = gate.healer and string.format(UI.COMING_SOON_BODY, gate.healer) or UI.COMING_SOON_BODY_NO_HEALER,
        age = age,
        spec = gate.spec,
        healer = gate.healer,
    }
end

local function buildComingSoon(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame.statusStrip, "BOTTOMLEFT", 2, -6)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -60)
    title:SetPoint("LEFT", panel, "LEFT", 20, 0)
    title:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    title:SetJustifyH("CENTER")
    panel.title = title

    local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOP", title, "BOTTOM", 0, -12)
    body:SetPoint("LEFT", panel, "LEFT", 30, 0)
    body:SetPoint("RIGHT", panel, "RIGHT", -30, 0)
    body:SetJustifyH("CENTER")
    panel.body = body

    local age = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    age:SetPoint("TOP", body, "BOTTOM", 0, -16)
    age:SetPoint("LEFT", panel, "LEFT", 30, 0)
    age:SetPoint("RIGHT", panel, "RIGHT", -30, 0)
    age:SetJustifyH("CENTER")
    panel.age = age

    panel:Hide()
    frame.comingSoon = panel
    return panel
end

-- Writes the three lines, or leaves the screen alone when the gate is down.
-- Returns the model it drew, or nil.
function UI.RefreshComingSoon(frame, now)
    frame = frame or UI.frame
    local panel = frame and frame.comingSoon or nil
    if not panel then
        return nil
    end
    local model = UI.ComingSoonModel(now)
    if not model then
        return nil
    end
    panel.title:SetText(model.title)
    panel.body:SetText(model.body)
    panel.age:SetText(model.age)
    return model
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
-- M5-2a (WKE-593): the margin is LibDBIcon's `lib.radius`, 5, not 10. Every
-- other addon's minimap button is a LibDBIcon button and sits at
-- `width / 2 + 5`; at 10 ours sat five points further out on every angle and
-- read as off the ring the others share (the owner's screenshot, 2026-09-16).
UI.MINIMAP_MARGIN = 5
UI.MINIMAP_DEFAULT_SIZE = 140
UI.MINIMAP_RADIUS = UI.MINIMAP_DEFAULT_SIZE / 2 + UI.MINIMAP_MARGIN
UI.MINIMAP_BUTTON_SIZE = 31
-- The square minimap's diagonal reach is pulled back by a flat 10 points, which
-- is the literal LibDBIcon uses (`sqrt(2*w^2)-10`, LibDBIcon-1.0 minor 55, read
-- from the installed DandersFrames copy). It is NOT the margin: the two were
-- equal by accident while the margin was 10, and the corner is clamped to the
-- edge anyway, so tying them would move the corners for no reason.
UI.MINIMAP_DIAGONAL_INSET = 10
-- The three files LibDBIcon's retail branch draws with, by path rather than by
-- the file IDs it hardcodes (136430, 136467), and the circle mask
-- PortraitFrameTemplate puts on its portrait.
UI.MINIMAP_BORDER_TEXTURE = "Interface/Minimap/MiniMap-TrackingBorder"
UI.MINIMAP_BACKGROUND_TEXTURE = "Interface/Minimap/UI-Minimap-Background"
-- The two events that can answer the spec read after the button is built at
-- ADDON_LOADED, registered on the BUTTON so the icon is right whether or not
-- the window has ever been created. Which of the two first answers
-- C_SpecializationInfo.GetSpecialization() on a real client is not measured
-- here (ARCHITECTURE.md §7, M5-2a): both are taken, and applying the icon twice
-- costs two texture sets.
UI.MINIMAP_ICON_EVENTS = { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED" }

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
        local dw = math.sqrt(2 * w * w) - UI.MINIMAP_DIAGONAL_INSET
        local dh = math.sqrt(2 * h * h) - UI.MINIMAP_DIAGONAL_INSET
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

    -- M5-2a (WKE-593): LibDBIcon's RETAIL geometry, point for point, so this
    -- button reads as one of the row it sits in - a dark disc, a small icon
    -- trimmed off its own edge, and the tracking ring around both. Ours had the
    -- library's CLASSIC branch: a 20-point icon in the BACKGROUND with no disc
    -- behind it under a 53-point border, which is what made a square spec icon
    -- overrun the ring (the owner's screenshot, 2026-09-16).
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER", button, "CENTER", 0, 0)
    background:SetTexture(UI.MINIMAP_BACKGROUND_TEXTURE)
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon = icon
    -- NOT masked round. M5-2a first put PortraitFrameTemplate's circular mask on
    -- this texture, and the client refused the trim below on the owner's screen
    -- - `Texture:SetTexCoord(): Cannot set tex coords when texture has mask.`,
    -- 2026-09-16 14:39:48 - which stopped this function half way, before the
    -- border, the badge and the events. The trim is what LibDBIcon does and what
    -- the neighbouring buttons look like; the trim also carries the class-circle
    -- fallback's quarter-sheet coords, so it cannot be given up for a mask. A
    -- round icon, if wanted, is a MaskTexture (`AddMaskTexture`) tried on a real
    -- client first (ARCHITECTURE.md §11).
    -- The spec the verdict is for, the same fact the portrait ring carries;
    -- the class circle when the client names no spec, and the question mark
    -- only when it names neither.
    UI.ApplyMinimapIcon(button)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture(UI.MINIMAP_BORDER_TEXTURE)
    button.border = border

    for _, event in ipairs(UI.MINIMAP_ICON_EVENTS) do
        button:RegisterEvent(event)
    end
    button:SetScript("OnEvent", function(self)
        UI.ApplyMinimapIcon(self)
    end)

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
    -- R-6 (WKE-578): the badge. A small square in the button's top-right
    -- corner while the gear has moved past the plan, drawn by the addon out of
    -- Blizzard's flat WHITE8X8 in two layers, exactly as R-2b settled the bag
    -- mark (docs/ROADS-UX.md): a mark is drawn at the size it will be seen at,
    -- and an atlas made for a bigger frame is a smear at this one. No sound, no
    -- popup, no flashing.
    --
    -- UX-4b (WKE-611): the square is the Waymark now, and the accent is the
    -- brand colour rather than QE Live's gold - the same two changes the bag
    -- mark took, for the same reason, so the one shape a reader learns once is
    -- the same shape in both places. The texture is the 16-point drawing, NOT
    -- `mark64`: R-2b is the rule that a mark is drawn at the size it will be
    -- seen at, this badge is 9 points, and the 16 is the nearer of the two
    -- drawings to that. The badge's size, corner and offsets are R-6's and are
    -- untouched. The launcher's own icon is the spec icon and is not touched
    -- either (593, and the owner's answer 3 on WKE-602).
    --
    -- UX-4c (WKE-612): the badge draws the same PAIR the bag corner does -
    -- `mark16-edge` under `mark16-fill`, the double chevron with a keyline all
    -- round and no plate, the owner's "Fix E at 16" of 2026-09-17. Three things
    -- follow and all three are the point. The two layers are now the same size,
    -- because the keyline is dilated into the edge file and no longer needs the
    -- accent shrunk by two points to show a rim. They sit at the same anchor
    -- with no offset. And the keyline is `UI.MARK_EDGE_COLOR`, the near-black
    -- every tinted Waymark is outlined in, rather than the flat black this
    -- badge alone used to carry - one mark, one pair of colours, everywhere.
    local dot = button:CreateTexture(nil, "OVERLAY")
    dot:SetSize(UI.MINIMAP_DOT_SIZE, UI.MINIMAP_DOT_SIZE)
    dot:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -4)
    dot:SetTexture(UI.MEDIA.MARK16_EDGE)
    dot:SetVertexColor(unpack(UI.MARK_EDGE_COLOR))
    local dotAccent = button:CreateTexture(nil, "OVERLAY")
    dotAccent:SetSize(UI.MINIMAP_DOT_SIZE, UI.MINIMAP_DOT_SIZE)
    dotAccent:SetPoint("CENTER", dot, "CENTER", 0, 0)
    dotAccent:SetTexture(UI.MEDIA.MARK16_FILL)
    dotAccent:SetVertexColor(ns.UI.ItemLine.RGB(UI.BRAND_HEX))
    button.driftDot = dot
    button.driftDotAccent = dotAccent
    dot:Hide()
    dotAccent:Hide()

    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Lootpath")
        GameTooltip:AddLine(UI.StatusStripModel().text)
        -- The same words the strip's second row carries, from the same builder,
        -- so the two surfaces cannot say different things about one fact. The
        -- WAIT is not added again: since M3-16b it is already the strip line
        -- above (`UI.StatusStripModel`).
        local nudge = ns.Drift.Model()
        if nudge and nudge.kind == "behind" then
            GameTooltip:AddLine(nudge.text)
        end
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
    UI.RefreshMinimapDot()
    return button
end

-- The badge, for both states, read off the same model every other surface is
-- drawn from.
--
-- R-6 kept the WAIT off the minimap on the argument that a player who is
-- waiting has already clicked. M3-16b (WKE-583) overturns it on the owner's own
-- evidence: with the window shut - which is where he is, because he has just
-- reloaded and gone back to playing - the minimap button is the only surface
-- Lootpath has, and "the refresh is still happening" is exactly what he said he
-- had no way to know. The badge goes out the moment the wait does, which is
-- what keeps it from becoming a mark that is always up.
function UI.RefreshMinimapDot()
    local button = UI.minimapButton
    if not (button and button.driftDot) then
        return nil
    end
    local model = ns.Drift.Model()
    if model then
        button.driftDot:Show()
        button.driftDotAccent:Show()
    else
        button.driftDot:Hide()
        button.driftDotAccent:Hide()
    end
    return model
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
        -- The ring only. The minimap button carries this same event itself
        -- (M5-2a, WKE-593), because it has to answer it before this window has
        -- ever been created; a second call from here would be a second path to
        -- one fact, which is what M5-2a took out.
        UI.ApplyPortrait(frame)
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
    --
    -- UX-4b (WKE-611): the title is the name-mark - `Lootpath` set in Alegreya
    -- SC Bold and rendered to `Media/wordmark.tga` - rather than a font string,
    -- and the version it used to carry is the last line of the status strip's
    -- tooltip. A version belongs where someone goes to ask how old this is, and
    -- that is the strip; it was on the title because there was nowhere else to
    -- put it.
    --
    -- The texture is white with alpha and tinted here, so the brand colour stays
    -- one Lua string. It is drawn at UI.TITLE_WORDMARK_HEIGHT with the width the
    -- texture's own 4:1 ratio gives, because a name-mark stretched is a
    -- different name-mark. TitleText is blanked rather than removed: the
    -- template owns it, and it is what draws if this client has no
    -- TitleContainer to hang a texture on.
    UI.ApplyTitle(frame)
    UI.ApplyPortrait(frame)

    buildImportDialog(frame)
    buildStatusStrip(frame)
    buildTabs(frame)

    -- No width is handed to the panel here any more (M5-2c, WKE-609): every
    -- panel derives its own from UI.PANEL_WIDTH, so the window setting a second
    -- copy of the same number would only be a place for the two to disagree.
    local panel = UI.EquipPanel.Create(frame)
    frame.equipPanel = panel
    frame.upgradeMapPanel = ns.UpgradeMapPanel.Create(frame)
    frame.vaultPanel = ns.VaultPanel.Create(frame)
    -- Every tab's panel fills the same rectangle; only one is shown at a time.
    -- The tabs are on the frame's bottom edge now (M5-2), so the body runs from
    -- under the status strip to the frame's own bottom border: PortraitFrame
    -- has no inset frame to sit inside.
    for _, tab in ipairs(UI.TABS) do
        local tabPanel = frame[tab.key]
        tabPanel:SetPoint("TOPLEFT", frame.statusStrip, "BOTTOMLEFT", UI.PANEL_INSET_LEFT - UI.STRIP_INSET, -6)
        tabPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PANEL_INSET_RIGHT, 12)
    end
    -- H-1 (WKE-596): the same rectangle again, for the screen that replaces all
    -- three. Built last so it is drawn over them, and hidden until `ShowTab`
    -- reads the gate.
    buildComingSoon(frame)
    UI.ShowTab(frame, 1)
    -- The scale the owner chose (M5-2). Applied to the window only: the dialog
    -- and the minimap button are Blizzard-sized and are not part of it.
    frame:SetScale(UI.Options.GetScale())

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    -- V-5 (WKE-600): the Great Vault's own event. The Vault tab reads the live
    -- activities on every refresh, and this is what makes "every refresh"
    -- include the moment the vault itself changed - a boss down, a key timed,
    -- a reward taken - while the window is open in front of the player.
    -- Reading activities costs nothing and asks the client for nothing:
    -- `OnUIInteract` is what GENERATES rewards, it stays where M3-16a put it
    -- (once, at login), and nothing on this path calls it.
    frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    frame:SetScript("OnEvent", onEvent)

    -- Escape closes it, the way every Blizzard panel does. UISpecialFrames keys
    -- on the frame's global name, which is why this frame has one.
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = UI.FRAME_NAME
    end

    frame:Hide()
    return frame
end

-- The destination the tooltip's last line names (R-2a, WKE-571). "Why this?"
-- cannot be clicked on a tooltip, so it says `/lootpath map` instead, and this
-- is where that goes: the window, open, on the Upgrade Map. It shows rather
-- than toggles, because a reader who typed the command from a tooltip asked to
-- see the tab, never to close a window he was not looking at.
UI.UPGRADE_MAP_TAB = 2

function UI.ShowUpgradeMap()
    local frame = UI.Frame()
    frame:Show()
    UI.SelectTab(frame, UI.UPGRADE_MAP_TAB)
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
