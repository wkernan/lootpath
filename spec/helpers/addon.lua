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
-- ns.onReady first.
function H.load(opts)
    opts = opts or {}
    local world = Stub.install()
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

return H
