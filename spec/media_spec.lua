-- spec/media_spec.lua (UX-4b, WKE-611)
-- The art the addon ships, checked as files rather than as pixels.
--
-- Nothing here can say whether the Waymark READS at 16 points on a real slot -
-- that is the owner's screen and it is filed in ARCHITECTURE.md §11. What it
-- can say is everything a wrong file would fail on and a screenshot would not
-- explain: that each texture exists, that it is an uncompressed 32-bit TGA and
-- never a .blp, that its sides are powers of two, that the sizes are the ones
-- the Lua constants draw at, that the `.toc` names the icon it means to name,
-- that the packager ships the folder, and that the font's licence line is in
-- `Lootpath/Libs/LICENSES.md` - which the rule says comes before the font does.
--
-- Paths are relative to the repo root, which is where busted runs (`.busted`).

local H = require("spec.helpers.addon")

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
        return true
    end
    return false
end

-- The TGA header, the 18 bytes every TGA opens with. Little-endian.
local function readTGAHeader(path)
    local bytes = readFile(path)
    assert(#bytes >= 18, path .. " is too short to be a TGA")
    local b = { bytes:byte(1, 18) }
    return {
        idLength = b[1],
        colourMapType = b[2],
        imageType = b[3],
        width = b[13] + b[14] * 256,
        height = b[15] + b[16] * 256,
        bitsPerPixel = b[17],
        descriptor = b[18],
        size = #bytes,
    }
end

local function isPowerOfTwo(n)
    if n < 1 then
        return false
    end
    while n > 1 do
        if n % 2 ~= 0 then
            return false
        end
        n = n / 2
    end
    return true
end

local MEDIA = "Lootpath/Media/"
local EXPECTED = {
    { name = "mark16", width = 16, height = 16 },
    { name = "mark64", width = 64, height = 64 },
    { name = "wordmark", width = 256, height = 64 },
    { name = "icon256", width = 256, height = 256 },
}

describe("the addon's own art", function()
    it("ships four TGAs, each an uncompressed 32-bit image at the size it claims", function()
        for _, asset in ipairs(EXPECTED) do
            local path = MEDIA .. asset.name .. ".tga"
            assert.is_true(exists(path), path .. " is missing")
            local header = readTGAHeader(path)

            -- Type 2 is uncompressed true-colour. The client reads TGA without
            -- conversion; type 10 (RLE) would also be legal but nothing here
            -- writes it, and a 0 here would mean an empty image.
            assert.equal(2, header.imageType)
            assert.equal(0, header.colourMapType)
            assert.equal(32, header.bitsPerPixel)
            -- 0x08: eight alpha bits, origin bottom-left. The alpha is the whole
            -- point - every one of these is drawn over something else.
            assert.equal(0x08, header.descriptor)

            assert.equal(asset.width, header.width)
            assert.equal(asset.height, header.height)
            assert.is_true(isPowerOfTwo(header.width), asset.name .. " width is not a power of two")
            assert.is_true(isPowerOfTwo(header.height), asset.name .. " height is not a power of two")

            -- Header plus four bytes a pixel, exactly: a file bigger than that
            -- carries something nobody put there.
            assert.equal(18 + header.width * header.height * 4, header.size)
        end
    end)

    it("ships no .blp, and keeps the sources and the renderer beside them", function()
        for _, asset in ipairs(EXPECTED) do
            assert.is_false(exists(MEDIA .. asset.name .. ".blp"))
            assert.is_true(exists("tools/media/svg/" .. asset.name .. ".svg"))
        end
        assert.is_true(exists("tools/media/render.mjs"))
        assert.is_true(exists("tools/media/README.md"))
        assert.is_true(exists("tools/media/fonts/AlegreyaSC-Bold.ttf"))
        assert.is_true(exists("tools/media/fonts/OFL.txt"))
    end)

    it("names the addon's icon in the .toc, and the file it names is there", function()
        local keys = {}
        for line in io.lines(H.TOC) do
            local key, value = line:match("^##%s*([%w_]+):%s*(.-)%s*$")
            if key then
                keys[key] = value
            end
        end
        -- Blizzard reads this one metadata key for both the AddOn List
        -- (`AddonList.lua:376`) and the AddOn Compartment entry
        -- (`AddonCompartment.lua:86`), and the compartment draws it at 16 x 16,
        -- which is why it is the mark and never the listing tile.
        assert.equal([[Interface\AddOns\Lootpath\Media\mark64]], keys.IconTexture)
        assert.is_true(exists(MEDIA .. "mark64.tga"))
        -- No extension in the path: the client appends it.
        assert.is_nil(keys.IconTexture:find("%."))
        -- The compartment's function is still named, so the entry that gets the
        -- icon still exists.
        assert.equal("LootpathToggle", keys.AddonCompartmentFunc)
    end)

    it("is packaged: nothing in .pkgmeta ignores the Media folder", function()
        local pkgmeta = readFile(".pkgmeta")
        for entry in pkgmeta:gmatch("\n%s*%-%s*([^\r\n]+)") do
            entry = entry:gsub("%s+$", "")
            -- An ignore entry covers a path when the path starts with it.
            local covers = ("Lootpath/Media"):sub(1, #entry) == entry
            assert.is_false(covers, ".pkgmeta ignores " .. entry .. ", which would drop the art")
        end
        -- And the folder is inside the addon folder the packager lifts, so it
        -- needs no entry of its own to be shipped.
        assert.is_truthy(pkgmeta:find("Lootpath/Lootpath: Lootpath", 1, true))
    end)

    it("records the font's licence, and ships no font inside the addon", function()
        local licences = readFile("Lootpath/Libs/LICENSES.md")
        assert.is_truthy(licences:find("Alegreya SC Bold", 1, true))
        assert.is_truthy(licences:find("SIL Open Font License 1.1", 1, true))
        -- The renderer is a dependency too, and the same rule covers it.
        assert.is_truthy(licences:find("@resvg/resvg-js", 1, true))
        assert.is_truthy(licences:find("MPL-2.0", 1, true))

        -- The face is a dev-time file. Nothing under the shipped folder is one.
        for _, asset in ipairs(EXPECTED) do
            assert.is_false(exists(MEDIA .. asset.name .. ".ttf"))
        end
        assert.is_false(exists("Lootpath/Media/AlegreyaSC-Bold.ttf"))
        assert.is_false(exists("Lootpath/Libs/AlegreyaSC-Bold.ttf"))
    end)

    it("points every texture constant at a file that exists", function()
        local ns = H.load()
        local media = ns.UI.MEDIA
        for _, key in ipairs({ "MARK16", "MARK64", "WORDMARK", "ICON256" }) do
            local path = media[key]
            assert.is_string(path)
            -- The in-game path, turned back into a repo path.
            local file = path:gsub("\\", "/"):gsub("^Interface/AddOns/Lootpath/", "Lootpath/")
            assert.is_true(exists(file .. ".tga"), key .. " points at " .. file .. ", which is not there")
        end
        H.unload()
    end)
end)
