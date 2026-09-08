-- Lootpath/Modules/Companion.lua (C-2, WKE-534)
-- The addon half of the local companion (decision 2026-09-07,
-- docs/ARCHITECTURE.md 7). The companion writes QE Live's exports into
-- Lootpath/Data/QEVerdict.lua as Lua string literals; the client loads that
-- file at login or /reload like any other addon file, and this module carries
-- what it set through the SAME parser a paste goes through.
--
-- It moves bytes. It computes no healer value, adjusts no number QE Live
-- wrote, and refuses anything QEImport would refuse from the editbox: the
-- companion is a courier, not a second source of truth.
--
-- The chunk is Lua the companion authored on the owner's own machine, and it
-- is still treated as data: every field is type-checked, every value read
-- passes ns.Safe, nothing in it is called, and there is no loadstring
-- anywhere. A malformed file is a chat message and an untouched database.

local _, ns = ...

ns.Companion = {}
local Companion = ns.Companion

-- The schema strings this module knows how to hand on, and which importer
-- takes each. QE Live's Top Gear export is ns.QEImport's; the Upgrade Finder
-- export (`qe-live-upgradefinder`, the fork's own, docs/qe-live-pr.md) is
-- ns.UFImport's, since M3-6 - until that module existed an entry carrying it
-- was refused by name rather than handed to a parser that would have called it
-- a bad Top Gear export.
--
-- The two importers share the four calls this file makes of them - Parse,
-- ContentTypeKey, ForContentType, Store - and NOTHING here reaches past that
-- into either verdict's shape, because the two shapes disagree and their sign
-- conventions are opposites (decision 2026-09-08). A schema that is in neither
-- table is still refused by name; this module never guesses at an importer.
Companion.TOP_GEAR_SCHEMA = "qe-live-droptimizer"
Companion.UPGRADE_FINDER_SCHEMA = "qe-live-upgradefinder"

-- Resolved at call time, not at load: the module tables are built by files the
-- `.toc` lists before this one, but a name looked up now cannot be a stale
-- reference to a table that was replaced.
function Companion.ImporterFor(schema)
    if schema == Companion.TOP_GEAR_SCHEMA then
        return ns.QEImport
    end
    if schema == Companion.UPGRADE_FINDER_SCHEMA then
        return ns.UFImport
    end
    return nil
end

-- How many things a verdict carries, for the chat line, in each verdict's own
-- words. A Top Gear export names a set; an Upgrade Finder export ranks drops.
function Companion.CountOf(schema, verdict)
    if type(verdict) ~= "table" then
        return 0, "items"
    end
    if schema == Companion.UPGRADE_FINDER_SCHEMA then
        return #(verdict.order or {}), "ranked drops"
    end
    local topSet = type(verdict.topSet) == "table" and verdict.topSet or {}
    return #(topSet.order or {}), "items"
end

-- Where the verdict on screen came from. Stored on the verdict at import time
-- so it survives /reload in SavedVariables.
Companion.SOURCE_PASTE = "paste"
Companion.SOURCE_COMPANION = "companion"

-- The window already names the two kinds on the status line (ns.UI.KIND_LABEL);
-- the chat line says the same words, so an owner reading either sees one
-- vocabulary. Keyed by schema, because that is what the file carries.
Companion.KIND_OF = {
    ["qe-live-droptimizer"] = "topgear",
    ["qe-live-upgradefinder"] = "upgradefinder",
}

-- An export text longer than this is refused unread. A real Top Gear export is
-- tens of kilobytes (the committed one is 21 KB); a megabyte of Lua string in
-- the addon folder is a broken companion, and decoding it would freeze the
-- client rather than say so.
Companion.MAX_JSON_BYTES = 4 * 1024 * 1024

local function refuse(fmt, ...)
    return { ok = false, reason = string.format(fmt, ...) }
end

-- ns.Safe first, type after. A secret value coerces to nil through tonumber
-- and answers no type honestly, so the guard runs before anything looks at the
-- value - the same order Vault.lua settled on in M3-3.
local function safeString(value)
    local safe, sawSecret = ns.Safe(value)
    if sawSecret or type(safe) ~= "string" or safe == "" then
        return nil
    end
    return safe
end

local function shown(value)
    if value == nil then
        return "missing"
    end
    local kind = type(value)
    if kind == "string" then
        if #value > 40 then
            return '"' .. value:sub(1, 40) .. '..."'
        end
        return '"' .. value .. '"'
    end
    if kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    return "a " .. kind
end

-- The Mythic+ key level an Upgrade Finder document was run at (C-7, WKE-543).
-- Optional: a Top Gear document never has one, and neither does a file written
-- before C-7 or the committed placeholder. Whole and non-negative or nothing -
-- half a key level is not a key level, and the addon would rather file a
-- document as "does not say" than under a number it made up.
local function safeKeyLevel(value)
    local safe, sawSecret = ns.Safe(value)
    if sawSecret or type(safe) ~= "number" or safe < 0 or safe % 1 ~= 0 then
        return nil
    end
    return safe
end

-- Which of QE Live's own import settings produced the exports in the file
-- (C-5, WKE-539: the companion sets both checkboxes explicitly and records what
-- it asked for). Optional: a file written before C-5, and the committed
-- placeholder, carry none, and a missing pair is silence rather than a refusal.
-- Only the two booleans are read, and only when they really are booleans; the
-- addon never infers a setting from a number it sees elsewhere.
Companion.QE_SETTING_KEYS = { "autoUpgradeVault", "autoUpgradeAll" }

function Companion.Settings(raw)
    local safe, sawSecret = ns.Safe(raw)
    if sawSecret or type(safe) ~= "table" then
        return nil
    end
    local settings = {}
    for _, key in ipairs(Companion.QE_SETTING_KEYS) do
        local value, secret = ns.Safe(safe[key])
        if secret or type(value) ~= "boolean" then
            return nil
        end
        settings[key] = value
    end
    return settings
end

-- Validate(raw) -> { ok = true, writtenAt, writtenAtEpoch, companionVersion,
-- exports } or { ok = false, reason }. `raw` is whatever the chunk assigned to
-- ns.companionVerdict; nil means the committed placeholder is still in place,
-- which is not an error and is answered with `absent`, not a refusal to shout
-- about at every login.
function Companion.Validate(raw, now)
    if raw == nil then
        return { ok = false, absent = true, reason = "no companion file has been written yet" }
    end
    local safe, sawSecret = ns.Safe(raw)
    if sawSecret or type(safe) ~= "table" then
        return refuse("Data\\QEVerdict.lua set %s, not a table", shown(raw))
    end
    local writtenAt = safeString(safe.writtenAt)
    if not writtenAt then
        return refuse("Data\\QEVerdict.lua carries no writtenAt string (it is %s)", shown(safe.writtenAt))
    end
    local writtenAtEpoch = ns.EpochFromISO(writtenAt, now)
    if not writtenAtEpoch then
        return refuse(
            "Data\\QEVerdict.lua's writtenAt is %s, which is not an ISO 8601 UTC stamp like 2026-09-08T14:05:11Z",
            shown(writtenAt)
        )
    end
    local exports = ns.Safe(safe.exports)
    if type(exports) ~= "table" then
        return refuse("Data\\QEVerdict.lua carries no exports list (it is %s)", shown(safe.exports))
    end
    if #exports == 0 then
        return refuse("Data\\QEVerdict.lua's exports list is empty")
    end
    return {
        ok = true,
        writtenAt = writtenAt,
        writtenAtEpoch = writtenAtEpoch,
        companionVersion = safeString(safe.companionVersion),
        qeSettings = Companion.Settings(safe.qeSettings),
        exports = exports,
    }
end

-- One entry of the exports list -> { ok = true, schema, contentType, json } or
-- a refusal naming what was wrong with it. `contentType` is advisory: it is
-- what the companion ASKED QE Live for. The content type an import is filed
-- under is always the one inside the JSON (QEImport.ContentTypeKey), because
-- that is the one QE Live actually answered.
function Companion.Entry(raw, index)
    local safe = ns.Safe(raw)
    if type(safe) ~= "table" then
        return refuse("export %d is %s, not a table", index, shown(raw))
    end
    local json = safeString(safe.json)
    if not json then
        return refuse("export %d carries no json string (it is %s)", index, shown(safe.json))
    end
    if #json > Companion.MAX_JSON_BYTES then
        return refuse("export %d is %d bytes, past the %d Lootpath will read", index, #json, Companion.MAX_JSON_BYTES)
    end
    local schema = safeString(safe.schema)
    if not schema then
        return refuse("export %d carries no schema string (it is %s)", index, shown(safe.schema))
    end
    if not Companion.ImporterFor(schema) then
        return refuse(
            'export %d declares schema %s; Lootpath reads "%s" (Top Gear) and "%s" (Upgrade Finder)',
            index,
            shown(schema),
            Companion.TOP_GEAR_SCHEMA,
            Companion.UPGRADE_FINDER_SCHEMA
        )
    end
    return {
        ok = true,
        schema = schema,
        contentType = safeString(safe.contentType),
        keyLevel = safeKeyLevel(safe.keyLevel),
        json = json,
    }
end

-- When the stored verdict for a content type was written or pasted, in epoch
-- seconds. A companion import is dated by the file that carried it, a paste by
-- the moment it was pasted; the two are compared so the later one wins
-- whichever way round they happened.
local function storedAt(verdict)
    if type(verdict) ~= "table" then
        return nil
    end
    local written = verdict.companionWrittenAt and ns.EpochFromISO(verdict.companionWrittenAt) or nil
    return written or tonumber(verdict.importedAt)
end

-- Import every export the file carries. Returns
--   { ok, writtenAt, writtenAtEpoch, companionVersion, qeSettings,
--     imported = { { contentType, spec, items, warnings } },
--     skipped  = { { index, reason, contentType, stale } },
--     unchanged = { contentType } }
-- or the file-level refusal unchanged. Nothing it could not parse is stored,
-- and a refusal never disturbs what already is: the paste path stays the
-- fallback for a broken companion.
function Companion.ImportAll(raw, now)
    local file = Companion.Validate(raw, now)
    if not file.ok then
        return file
    end
    local result = {
        ok = true,
        writtenAt = file.writtenAt,
        writtenAtEpoch = file.writtenAtEpoch,
        companionVersion = file.companionVersion,
        qeSettings = file.qeSettings,
        imported = {},
        skipped = {},
        unchanged = {},
    }
    for index = 1, #file.exports do
        local entry = Companion.Entry(file.exports[index], index)
        -- The same parser the editbox calls - whichever of the two that is -
        -- so every schema, version and gameType refusal applies here word for
        -- word. Entry has already refused a schema neither importer owns, so
        -- the nil branch below is reachable only if the two ever drift apart:
        -- it says so rather than indexing nil.
        local importer = entry.ok and Companion.ImporterFor(entry.schema) or nil
        if not entry.ok then
            result.skipped[#result.skipped + 1] = { index = index, reason = entry.reason }
        elseif not importer then
            result.skipped[#result.skipped + 1] = {
                index = index,
                reason = string.format("export %d has no importer for schema %s", index, shown(entry.schema)),
            }
        else
            local parsed = importer.Parse(entry.json)
            if not parsed.ok then
                result.skipped[#result.skipped + 1] = { index = index, reason = parsed.reason }
            else
                local verdict = parsed.verdict
                -- Set BEFORE anything asks what this verdict replaces: since
                -- C-7 an Upgrade Finder verdict is identified by content type
                -- AND key level, so a verdict that does not yet carry its level
                -- would be compared against the wrong shelf and every document
                -- after the first would be imported again on every /reload.
                -- The number is the companion's report of which button it
                -- clicked on QE Live's own key selector; nothing here derives
                -- it from the export.
                verdict.keyLevel = entry.keyLevel
                local contentType = importer.ContentTypeKey(verdict)
                -- The counterpart of the SAME kind, never the other kind's:
                -- a Top Gear import and an Upgrade Finder import for one
                -- content type are two different answers and neither is stale
                -- because of the other.
                -- Since C-7 a companion file carries one Upgrade Finder
                -- document per key level, so "what does this replace" is the
                -- importer's question and not this file's: asking by content
                -- type alone would let the +4 document look like a repeat of
                -- the +2 one, and four of five answers would be dropped as
                -- unchanged.
                local existing = importer.Existing(verdict)
                local existingAt = storedAt(existing)
                if existing and existing.companionWrittenAt == file.writtenAt then
                    -- The same file, read again on the next /reload. Nothing
                    -- has changed, so nothing is said.
                    result.unchanged[#result.unchanged + 1] = contentType
                elseif existingAt and file.writtenAtEpoch < existingAt then
                    result.skipped[#result.skipped + 1] = {
                        index = index,
                        contentType = contentType,
                        stale = true,
                        reason = string.format(
                            "the companion's %s export was written %s, older than the %s import already stored;"
                                .. " keeping the stored one",
                            contentType,
                            ns.UI.AgeText(file.writtenAt, now),
                            contentType
                        ),
                    }
                else
                    verdict.source = Companion.SOURCE_COMPANION
                    verdict.companionWrittenAt = file.writtenAt
                    verdict.companionVersion = file.companionVersion
                    -- Carried onto the verdict, not left in the file's result:
                    -- the Vault panel reads it off whichever verdict is on
                    -- screen, which may have come back from SavedVariables
                    -- reloads after the file that wrote it was replaced.
                    verdict.qeSettings = file.qeSettings
                    local stored = importer.Store(verdict)
                    if not stored.ok then
                        result.skipped[#result.skipped + 1] = { index = index, reason = stored.reason }
                    else
                        local count, noun = Companion.CountOf(entry.schema, verdict)
                        result.imported[#result.imported + 1] = {
                            schema = entry.schema,
                            contentType = contentType,
                            keyLevel = entry.keyLevel,
                            spec = verdict.spec,
                            items = count,
                            noun = noun,
                            warnings = parsed.warnings,
                        }
                    end
                end
            end
        end
    end
    return result
end

-- Where a verdict came from, for the window's line and /lootpath status. A
-- verdict stored before C-2 carries no `source` field and was pasted, which is
-- what the fallback says.
function Companion.SourceOf(verdict)
    if type(verdict) ~= "table" then
        return nil
    end
    if verdict.source == Companion.SOURCE_COMPANION then
        return Companion.SOURCE_COMPANION
    end
    return Companion.SOURCE_PASTE
end

-- The phrase the window and /lootpath status use to say where the verdict on
-- screen came from: "pasted", or "companion, written 4 minute(s) ago" through
-- the same UI.AgeText every other age on screen goes through. A companion
-- import whose stamp cannot be read still says who carried it.
function Companion.SourceText(verdict, now)
    local source = Companion.SourceOf(verdict)
    if not source then
        return nil
    end
    if source ~= Companion.SOURCE_COMPANION then
        return "pasted"
    end
    local writtenAt = verdict.companionWrittenAt
    if type(writtenAt) ~= "string" then
        return "companion"
    end
    return string.format("companion, written %s", ns.UI.AgeText(writtenAt, now))
end

-- Runs at load, once the DB exists. Chat is the only output: at login the
-- window has not been built, and building it here would put a frame on screen
-- nobody asked for. If it IS open (a /lootpath refresh with the window up),
-- it is redrawn.
function Companion.Startup(now)
    local result = Companion.ImportAll(ns.companionVerdict, now)
    if result.absent then
        return result
    end
    if not result.ok then
        ns.Log("companion file refused: %s. The paste box still works.", result.reason)
        return result
    end
    for _, entry in ipairs(result.imported) do
        ns.Log(
            "companion import: %s, %s, %s%s, %d %s, written %s.",
            ns.UI.KIND_LABEL[Companion.KIND_OF[entry.schema]] or entry.schema,
            entry.spec or "unknown spec",
            entry.contentType,
            entry.keyLevel and string.format(" +%d", entry.keyLevel) or "",
            entry.items,
            entry.noun or "items",
            ns.UI.AgeText(result.writtenAt, now)
        )
        for _, warning in ipairs(entry.warnings or {}) do
            ns.Log("note: %s", warning)
        end
    end
    for _, skip in ipairs(result.skipped) do
        ns.Log("companion export %d refused: %s", skip.index, skip.reason)
    end
    if #result.imported > 0 and ns.UI.frame then
        ns.UI.Refresh()
    end
    return result
end

-- `/lootpath refresh` - the loop from inside the game, in one word. It takes
-- the three snapshots the companion's profile is built from, then flushes
-- SavedVariables by reloading so the companion can read them; the second
-- `/lootpath refresh`, once the companion says it is done, loads the file it
-- wrote. There is no third step: the startup import above is the rest. Two
-- reloads is the floor and is said out loud rather than hidden (decision
-- 2026-09-07).
--
-- The captures are C-3's (WKE-536). Before them, refresh reloaded and nothing
-- else, so `tools/companion/lib/simc-profile.js` built its profile from
-- whatever the owner had last CAPTURED - on 2026-09-07 that was the 09-05
-- Guardian-spec snapshot, and the companion valued a set the character had not
-- worn in two days. Nothing else in the addon writes gear to SavedVariables,
-- and the companion cannot make the client read anything, so the capture has
-- to happen here (decision 2026-09-08).
--
-- Out of combat only. ReloadUI is protected in combat, the captures refuse
-- there too, and the standing rule is that nothing Lootpath does runs in
-- combat anyway.
--
-- `journal` is deliberately not in this list: it is the one asynchronous
-- capture (it waits on EJ_LOOT_DATA_RECIEVED, 434-869 ms in the committed
-- walks), the SimC profile reads none of it, and a reload while it is running
-- would abandon it. The loot map's own cache (`db.global.journalCache`) is
-- untouched by a refresh.
Companion.REFRESH_CAPTURES = { "env", "inventory", "vault" }

Companion.REFRESH_CAPTURED_LINE = "captured %s - reloading so the companion can read them."
Companion.REFRESH_SECOND_LINE = "reload again when it says done; that second /lootpath refresh is all that is "
    .. "left - the file it writes is imported as the game comes back."
Companion.REFRESH_REFUSED_LINE = "/lootpath refresh stopped: capture '%s' refused: %s. Not reloading."
Companion.REFRESH_COMBAT_REASON = "/lootpath refresh does nothing in combat: reloading is blocked there, and so "
    .. "are the captures. Try again once the fight is over."
Companion.REFRESH_NO_RELOAD_REASON = "this client has no ReloadUI"

-- What the three snapshots hold, in the owner's words rather than the capture
-- names. The bank half is read back out of the snapshot that was just taken -
-- `C_Bank.CanViewBank` for the character's own bank, which the 2026-09-05
-- transcript showed answers true only while the bank frame is open - rather
-- than asking the client a second time: the capture is the one reader, and a
-- second read could disagree with the snapshot the companion will get.
function Companion.RefreshSummary(snapshots)
    local bank = "closed"
    local inventory = type(snapshots) == "table" and snapshots.inventory or nil
    local data = type(inventory) == "table" and type(inventory.data) == "table" and inventory.data or nil
    local bankData = data and type(data.bank) == "table" and data.bank or nil
    local predicates = bankData and type(bankData.predicates) == "table" and bankData.predicates or nil
    local canView = predicates and type(predicates.CanViewBank) == "table" and predicates.CanViewBank or nil
    local character = canView and type(canView.Character) == "table" and canView.Character or nil
    if character and ns.Safe(character[1]) == true then
        bank = "open"
    end
    return string.format("gear, bags, bank (%s), vault", bank)
end

function Companion.Refresh()
    if InCombatLockdown() then
        ns.Log("%s", Companion.REFRESH_COMBAT_REASON)
        return { ok = false, reason = "combat" }
    end
    -- Checked before anything is captured: three snapshots the owner cannot
    -- flush are three snapshots written for nothing.
    if type(ReloadUI) ~= "function" then
        ns.Log("%s", Companion.REFRESH_NO_RELOAD_REASON)
        return { ok = false, reason = Companion.REFRESH_NO_RELOAD_REASON }
    end
    local snapshots = {}
    for _, name in ipairs(Companion.REFRESH_CAPTURES) do
        local result = ns.RunCapture(name)
        local ok = type(result) == "table" and result.ok == true
        if not ok then
            local reason = (type(result) == "table" and result.reason) or "no result"
            ns.Log(Companion.REFRESH_REFUSED_LINE, name, tostring(reason))
            return { ok = false, reason = reason, capture = name, captured = snapshots }
        end
        snapshots[name] = result.snapshot
    end
    ns.Log(Companion.REFRESH_CAPTURED_LINE, Companion.RefreshSummary(snapshots))
    ns.Log("%s", Companion.REFRESH_SECOND_LINE)
    ReloadUI()
    return { ok = true, reloaded = true, captured = snapshots }
end

ns.onReady[#ns.onReady + 1] = function()
    Companion.Startup()
end
