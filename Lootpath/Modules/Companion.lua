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
-- M3-6's, and until that module exists an entry carrying it is REFUSED by
-- name rather than passed to a parser that would call it "not a Top Gear
-- export". Guessing at it here would be inventing an importer.
Companion.TOP_GEAR_SCHEMA = "qe-live-droptimizer"
Companion.UPGRADE_FINDER_SCHEMA = "qe-live-upgradefinder"

-- Where the verdict on screen came from. Stored on the verdict at import time
-- so it survives /reload in SavedVariables.
Companion.SOURCE_PASTE = "paste"
Companion.SOURCE_COMPANION = "companion"

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
    if schema == Companion.UPGRADE_FINDER_SCHEMA then
        return refuse(
            "export %d is a %s document, and Lootpath cannot read those yet (M3-6)",
            index,
            Companion.UPGRADE_FINDER_SCHEMA
        )
    end
    if schema ~= Companion.TOP_GEAR_SCHEMA then
        return refuse(
            'export %d declares schema %s; Lootpath reads "%s"',
            index,
            shown(schema),
            Companion.TOP_GEAR_SCHEMA
        )
    end
    return { ok = true, schema = schema, contentType = safeString(safe.contentType), json = json }
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
--   { ok, writtenAt, writtenAtEpoch, companionVersion,
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
        imported = {},
        skipped = {},
        unchanged = {},
    }
    for index = 1, #file.exports do
        local entry = Companion.Entry(file.exports[index], index)
        if not entry.ok then
            result.skipped[#result.skipped + 1] = { index = index, reason = entry.reason }
        else
            -- The same parser the editbox calls, so every schema, version,
            -- gameType and topSet refusal applies here word for word.
            local parsed = ns.QEImport.Parse(entry.json)
            if not parsed.ok then
                result.skipped[#result.skipped + 1] = { index = index, reason = parsed.reason }
            else
                local verdict = parsed.verdict
                local contentType = ns.QEImport.ContentTypeKey(verdict)
                local existing = ns.QEImport.ForContentType(contentType)
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
                    local stored = ns.QEImport.Store(verdict)
                    if not stored.ok then
                        result.skipped[#result.skipped + 1] = { index = index, reason = stored.reason }
                    else
                        result.imported[#result.imported + 1] = {
                            contentType = contentType,
                            spec = verdict.spec,
                            items = #(verdict.topSet.order or {}),
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
            "companion import: %s, %s, %d items, written %s.",
            entry.spec or "unknown spec",
            entry.contentType,
            entry.items,
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

-- `/lootpath refresh` - the loop from inside the game, in one word. It flushes
-- SavedVariables so the companion can read this character's gear, and the
-- second /lootpath refresh, once the companion says it is done, loads the file
-- it wrote. There is no third step: the startup import above is the rest. Two
-- reloads is the floor and is said out loud rather than hidden (decision
-- 2026-09-07).
--
-- Out of combat only. ReloadUI is protected in combat, and the standing rule
-- is that nothing Lootpath does runs in combat anyway.
Companion.REFRESH_LINES = {
    "reloading so the companion can read your gear; reload again when it says done.",
    "(that second /lootpath refresh is all that is left - the file it writes is imported as the game comes back.)",
}
Companion.REFRESH_COMBAT_REASON =
    "/lootpath refresh does nothing in combat: reloading is blocked there. Try again once the fight is over."

function Companion.Refresh()
    if InCombatLockdown() then
        ns.Log("%s", Companion.REFRESH_COMBAT_REASON)
        return { ok = false, reason = "combat" }
    end
    for _, line in ipairs(Companion.REFRESH_LINES) do
        ns.Log("%s", line)
    end
    if type(ReloadUI) ~= "function" then
        return { ok = false, reason = "this client has no ReloadUI" }
    end
    ReloadUI()
    return { ok = true, reloaded = true }
end

ns.onReady[#ns.onReady + 1] = function()
    Companion.Startup()
end
