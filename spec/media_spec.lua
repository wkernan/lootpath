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
    -- The 16-point Waymark is two files since UX-4c (WKE-612): the keyline
    -- silhouette and the chevron bodies, tinted separately and drawn at one
    -- anchor. The single `mark16` it replaced is proved gone below.
    { name = "mark16-edge", width = 16, height = 16 },
    { name = "mark16-fill", width = 16, height = 16 },
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

    -- UX-4c (WKE-612). The single chevron is not deprecated, it is GONE: a
    -- stale `mark16.tga` left in the folder is a file the packager would ship,
    -- the client would happily load, and a half-finished edit would point back
    -- at - the whole failure this guard exists for.
    it("has taken the old single-chevron mark out of the shipped art and out of the sources", function()
        assert.is_false(exists(MEDIA .. "mark16.tga"))
        assert.is_false(exists(MEDIA .. "mark16.blp"))
        assert.is_false(exists("tools/media/svg/mark16.svg"))

        -- And nothing in the addon still names it. The path is spelled out in
        -- exactly one table, so the table is where it is looked for.
        local ns = H.load()
        for key, path in pairs(ns.UI.MEDIA) do
            assert.is_nil(path:match("mark16$"), key .. " still points at the single-chevron mark")
        end
        H.unload()
    end)

    -- The keyline is why there are two files at all, and it only works if the
    -- edge file's shape is the WIDER of the two: it is the same drawing dilated
    -- by half a stroke on every side, so at the same anchor it shows all the way
    -- round as an outline. A fill accidentally rendered from the edge source, or
    -- the two swapped, would draw a mark with no keyline and pass every path
    -- test. This reads the alpha of both files and compares them texel by texel.
    --
    -- UX-4d changed how that comparison has to be written. UX-4c's bands were
    -- thin enough that the dilation reached texels the fill never touched, so
    -- counting texels with any alpha was enough (edge 168, fill 110). The
    -- round-two bands are a unit thicker inside the same 16-unit box, and the
    -- dilation now lands mostly INSIDE texels the fill's own antialiasing
    -- already tints: both files cover the same 126 texels, and the keyline is
    -- carried in how much alpha each one has there. So the guard is per texel
    -- and alpha-weighted, which is strictly the stronger statement: the edge is
    -- at least as opaque as the fill EVERYWHERE, and more opaque somewhere.
    it("renders the keyline at least as strong as the fill at every texel, and stronger somewhere", function()
        local function alpha(name)
            local path = MEDIA .. name .. ".tga"
            local bytes = readFile(path)
            local header = readTGAHeader(path)
            local a, covered, opaque = {}, 0, 0
            for i = 1, header.width * header.height do
                -- BGRA: the alpha is the fourth byte of each pixel, after the
                -- 18-byte header.
                local value = bytes:byte(18 + (i - 1) * 4 + 4)
                a[i] = value
                if value > 0 then
                    covered = covered + 1
                end
                if value == 255 then
                    opaque = opaque + 1
                end
            end
            return a, covered, opaque
        end

        local edge, edgeCovered, edgeOpaque = alpha("mark16-edge")
        local fill, fillCovered, fillOpaque = alpha("mark16-fill")

        -- Both are drawings, not empty files and not solid squares.
        assert.is_true(edgeCovered > 0 and edgeCovered < 256, "edge covers " .. edgeCovered .. " of 256")
        assert.is_true(fillCovered > 0 and fillCovered < 256, "fill covers " .. fillCovered .. " of 256")
        assert.is_true(edgeOpaque > 0 and fillOpaque > 0)

        local stronger = 0
        for i = 1, 256 do
            assert.is_true(
                edge[i] >= fill[i],
                "texel " .. i .. ": fill alpha " .. fill[i] .. " over edge " .. edge[i] .. "; fill outside its keyline"
            )
            if edge[i] > fill[i] then
                stronger = stronger + 1
            end
        end
        assert.is_true(stronger > 0, "the edge is nowhere stronger than the fill; there is no keyline to see")
    end)

    -- UX-4d (WKE-613). The owner saw UX-4c's double chevron in his full bags and
    -- asked for more of it: "let's increase the thickness of both chevrons by a
    -- bit more and let's also keep them the same color". Both halves of that are
    -- measurable in the rendered files and neither is visible in the SVG paths
    -- alone, because what matters is what resvg put on a 16-texel grid.
    --
    -- The thickness, as INK rather than as coverage: a band a unit thicker turns
    -- antialiased edge texels into solid ones. Measured on the committed files,
    -- fully opaque texels went 14 -> 52 in the fill and 18 -> 100 in the edge.
    -- The thresholds below sit well under those and well over UX-4c's, so a
    -- re-render that quietly went back to the thin bands fails here.
    it("draws the round-two bands: far more solid ink than UX-4c's thin ones", function()
        local function opaqueTexels(name)
            local path = MEDIA .. name .. ".tga"
            local bytes = readFile(path)
            local header = readTGAHeader(path)
            local opaque = 0
            for i = 1, header.width * header.height do
                if bytes:byte(18 + (i - 1) * 4 + 4) == 255 then
                    opaque = opaque + 1
                end
            end
            return opaque
        end

        local fillOpaque = opaqueTexels("mark16-fill")
        local edgeOpaque = opaqueTexels("mark16-edge")
        assert.is_true(fillOpaque > 40, "the fill has " .. fillOpaque .. " solid texels; UX-4c had 14")
        assert.is_true(edgeOpaque > 80, "the edge has " .. edgeOpaque .. " solid texels; UX-4c had 18")
    end)

    -- The same colour, both chevrons. UX-4c drew the lower BODY at 65% alpha, so
    -- every texel of it topped out at 166 and the bottom rows of the fill never
    -- went past 156. The owner asked for one colour, so the lower body is at
    -- full alpha now and those rows reach 255. Rows 13 to 15 (counting from the
    -- top of the image) are the lower chevron's alone - the upper chevron's
    -- lowest point is y=12.5 on the 16-unit grid, so nothing of it reaches row
    -- 13 - which makes them the rows where a 65% body has nowhere to hide.
    it("draws both chevrons of the fill at one alpha: the lower body is no longer at 65%", function()
        local path = MEDIA .. "mark16-fill.tga"
        local bytes = readFile(path)
        local header = readTGAHeader(path)
        assert.equal(16, header.width)
        assert.equal(16, header.height)

        local best = 0
        -- The TGA is bottom-left origin, so image row `y` from the top is file
        -- row `15 - y`.
        for y = 13, 15 do
            local fileRow = 15 - y
            for x = 0, 15 do
                local a = bytes:byte(18 + (fileRow * 16 + x) * 4 + 4)
                if a > best then
                    best = a
                end
            end
        end
        assert.equal(255, best, "the lower chevron's own rows top out at " .. best .. "; 65% alpha caps them at 166")
    end)

    -- UX-4d moved the brand colour, and it lives in three places that CANNOT be
    -- checked against each other by reading Lua alone: the one Lua constant, and
    -- the hex baked into the two SVGs whose textures are displayed untinted.
    -- `tools/media/README.md` says they must move together; this is that
    -- sentence as a test. The Lua value is pinned as a literal too, because the
    -- owner picked #FFB3DB off the brand page (rung 5, UX-4d), saw it read as
    -- pink-white in a full bag, and on round three chose the original #FF1A8C
    -- with the thicker, same-colour double chevron - "let's try this one and
    -- then just call it for now" (UX-4e, 2026-09-17). A silent drift either
    -- way would look like a merge, not a decision.
    it("carries the owner's brand colour in the one constant and in both baked sources", function()
        local ns = H.load()
        assert.equal("FF1A8C", ns.UI.BRAND_HEX)
        H.unload()

        for _, source in ipairs({ "mark64", "icon256" }) do
            local svg = readFile("tools/media/svg/" .. source .. ".svg")
            assert.is_truthy(
                svg:find("#FF1A8C", 1, true),
                source .. ".svg does not bake #FF1A8C, so its texture is a different brand than the Lua constant"
            )
            assert.is_nil(svg:find("#FFB3DB", 1, true), source .. ".svg still bakes the pale round-two colour")
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
        for _, key in ipairs({ "MARK16_EDGE", "MARK16_FILL", "MARK64", "WORDMARK", "ICON256" }) do
            local path = media[key]
            assert.is_string(path)
            -- The in-game path, turned back into a repo path.
            local file = path:gsub("\\", "/"):gsub("^Interface/AddOns/Lootpath/", "Lootpath/")
            assert.is_true(exists(file .. ".tga"), key .. " points at " .. file .. ", which is not there")
        end
        H.unload()
    end)
end)
