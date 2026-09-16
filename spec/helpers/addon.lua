-- spec/helpers/addon.lua
-- Loads the addon the way the client does: every Lua file named in the .toc,
-- in order, each receiving (addonName, namespace) as its varargs. Library
-- files are skipped except Libs/json.lua (LibStub and AceDB are stubbed).
local Stub = require("spec.stubs.wow")

local H = {}

H.ADDON = "Lootpath"
H.TOC = "Lootpath/Lootpath.toc"

function H.tocFiles()
    local files = {}
    for line in io.lines(H.TOC) do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

-- Returns ns, world. opts.loaded = false skips ADDON_LOADED so a test can hook
-- ns.onReady first. opts.beforeLoad(world) runs after the stub world exists and
-- before any addon file does, which is the only way to change what a file reads
-- AT LOAD TIME - ns.VERSION reads the .toc metadata on Core.lua's first lines.
function H.load(opts)
    opts = opts or {}
    local world = Stub.install()
    if opts.beforeLoad then
        opts.beforeLoad(world)
    end
    local ns = {}
    for _, f in ipairs(H.tocFiles()) do
        local isLib = f:match("^Libs/") ~= nil
        if f:match("%.lua$") and (not isLib or f == "Libs/json.lua") then
            local chunk = assert(loadfile("Lootpath/" .. f))
            chunk(H.ADDON, ns)
        end
    end
    if opts.loaded ~= false then
        world.fireEvent("ADDON_LOADED", H.ADDON)
    end
    return ns, world
end

function H.unload()
    Stub.uninstall()
end

-- The owner's own timezone, as a rule the stub's modelled clock can follow
-- (V-4, WKE-589). US Central: six hours behind UTC in winter, five during
-- daylight time, which in 2026 runs from 2026-03-08T08:00Z to
-- 2026-11-01T06:00Z. The two epochs are the transitions themselves, computed
-- as UTC seconds rather than remembered. Every timezone fault the addon can
-- have is one of these two offsets being used for the other one's instant, so
-- one zone with one rule is the whole harness a test needs.
H.CHICAGO = {
    standard = -6 * 3600,
    daylight = -5 * 3600,
    daylightFrom = 1772956800,
    daylightUntil = 1793512800,
}

-- Puts the stub's modelled clock on `world`, on the Central zone above, with
-- bare `time()` answering `now`. Returns `now` so a test can read it back.
function H.chicagoClock(world, now)
    world.setClock({
        now = now,
        standard = H.CHICAGO.standard,
        daylight = H.CHICAGO.daylight,
        isDaylight = function(epoch)
            return epoch >= H.CHICAGO.daylightFrom and epoch < H.CHICAGO.daylightUntil
        end,
    })
    return now
end

-- R-7b (WKE-591). The stub world starts with `equipped = {}` - a level-90 Druid
-- wearing nothing - and since R-7b that is not a character, it is exactly the
-- empty read the `inventory` capture now refuses (`ns.INVENTORY_EMPTY_REASON`).
-- A test whose subject is a capture CHAIN rather than the gear in it dresses the
-- character first, which is what every real run has; a test that means to see the
-- refusal strips it again.
--
-- One helm, because one is the whole difference between "the client answered"
-- and "the client answered with nothing". A test about gear replays the owner's
-- own transcript instead (`spec/helpers/replay.lua`).
H.HELM = "|cffa335ee|Hitem:210001::::::::80:105::13:2:1:2::::::|h[Test Helm]|h|r"

function H.dress(world)
    world.equipped[1] = { link = H.HELM, id = 210001 }
    return world
end

return H
