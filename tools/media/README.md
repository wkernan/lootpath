# Lootpath's marks

Everything the addon draws of itself is rendered from the SVG sources in
`svg/` into `Lootpath/Media/*.tga`. The TGAs are committed, because the
packager ships what is in the repo and nobody installing Lootpath should need
Node; the sources and this script are committed so the owner can change the
art and get the same files back.

## Re-render, one command

```powershell
cd tools\media
npm install
npm run render
```

`npm install` fetches [`@resvg/resvg-js`](https://github.com/yisibl/resvg-js)
(MPL-2.0, v2.6.2) with its prebuilt Windows binary. Nothing else is needed:
the machine had no Inkscape, no ImageMagick and no `resvg` on `PATH`
(`C:\WINDOWS\system32\convert.exe` is Windows' NTFS converter, not
ImageMagick's), and Node was already there.

`render.mjs` rasterises each SVG with resvg and writes the TGA itself, because
resvg writes PNG and the client does not read PNG. Every output is an
**uncompressed 32-bit BGRA TGA, bottom-left origin, descriptor `0x08`**, at a
power-of-two size. Never a `.blp`: the client reads TGA without conversion,
and a BLP would need a tool nobody here has.

## What each file is for

| File | Size | Coloured how | Drawn where |
|---|---|---|---|
| `mark16-edge.tga` | 16 x 16 | white + alpha, **tinted in Lua** (near-black) | the keyline under the 16-point mark: the bag corner in both bag adapters, and the drift badge on the launcher |
| `mark16-fill.tga` | 16 x 16 | white + alpha, **tinted in Lua** (the brand) | the two chevron bodies, drawn over the keyline at the same anchor, in the same three places |
| `mark64.tga` | 64 x 64 | brand colour baked in, on its own keyline | `## IconTexture` in the `.toc` - the AddOn List and the AddOn Compartment entry |
| `wordmark.tga` | 256 x 64 | white + alpha, **tinted in Lua** | the window's title |
| `icon256.tga` | 256 x 256 | brand colour baked in, on a near-black ground | the addon site's listing tile |

The two tinted files are white on purpose: the brand colour lives once, in
`Lootpath/UI/ItemLine.lua` as `ns.UI.BRAND_HEX`, so changing it is a one-line
edit and not a re-render. The two baked files cannot be tinted where they are
used - a `.toc` metadata line names a file and nothing else - so their hex is
written into `svg/mark64.svg` and `svg/icon256.svg` and **must be changed in
both places together** if the brand colour ever moves.

Sizes are powers of two because the client requires it; `render.mjs` refuses
any asset that is not, and refuses a render that did not come back at the size
asked for.

## The font

`Lootpath` is set in **Alegreya SC Bold**, SIL Open Font License 1.1, vendored
at `fonts/AlegreyaSC-Bold.ttf` with its `fonts/OFL.txt`, from
`google/fonts/ofl/alegreyasc`. It is a dev-time file: it is rendered into the
textures and is never shipped inside the addon. Its licence line is in
`Lootpath/Libs/LICENSES.md`, which is where a dependency is recorded before it
arrives.

The renderer loads **only** that file (`loadSystemFonts: false`). A render that
quietly fell back to a system font would look right on this machine and wrong
on anyone else's.

## The shape

The mark is the **Waymark**: the double chevron a walked route is blazed with.
Candidate A of the WKE-602 proposal, picked by the owner on 2026-09-16.

At 16 it is the full double chevron too (**UX-4c**, WKE-612). UX-4b drew a
reduced form there - one thick chevron - and the owner opened his full bags on
2026-09-17: "I like it, but the colour makes it a bit hard to see when looking
at your entire bags." He named the colour; the sign-off page argued hue is the
smaller of the two causes, a thin shape with an offset shadow the larger. He
then picked **Fix E at 16**, which changed the shape and left the colour: the
upper chevron solid, the lower at 65%, a one-unit near-black outline around
every edge, and no plate behind it.

**UX-4d (WKE-613) is round two of the same complaint.** The owner saw that
mark in his full bags on 2026-09-17 and said: "let's increase the thickness of
both chevrons by a bit more and let's also keep them the same color. It still
seems difficult to see them, I would say we need to go brighter on the pink."
Section 3b of the brand page drew all three changes and five brightness rungs;
he picked rung 5. So each band is **a unit thicker** on the 16-unit grid, both
chevrons are **one colour at full alpha**, and the brand moved to **`#FFB3DB`**.
The geometry in `mark16-fill.svg` and `mark16-edge.svg` is that section's, path
for path - still drawn on a 16-unit grid rather than shrunk from `mark64`,
because R-2b settled that a mark is drawn at the size it will be seen at.
`mark64.svg` and `icon256.svg` take the same proportion at their own scale: the
upper band's inner edge moved down four units and the lower band's outer edge
moved up four, which is one unit of the 16-point grid at 4x.

**Why 16 is two files.** A keyline is a second colour, and one texture carries
one tint. Baking the brand in would cost the one-line colour edit that
`ns.UI.BRAND_HEX` exists for, so the outline silhouette and the chevron bodies
ship separately, both white with alpha:

  * `mark16-edge.svg` is both chevrons filled **and** stroked in white, so what
    comes out is one solid silhouette dilated by half the stroke on every side;
  * `mark16-fill.svg` is the two bodies, both at full alpha since UX-4d.

Drawn at the **same anchor** with the edge underneath, that dilation is the
keyline, all the way round both chevrons. The mark this replaced had the fill
inset one point inside the edge instead, which is a shadow on one side and not
an outline.

At UX-4c's thickness the dilation reached texels the fill never touched, so the
keyline could be checked by counting texels with any alpha at all (edge 168,
fill 110 of 256). The round-two bands are thicker inside the same box, so the
dilation now lands mostly inside texels the fill's own antialiasing already
tints: both files cover **126** texels and the keyline lives in the alpha, not
in the count (fully solid texels went 14 -> 52 in the fill and 18 -> 100 in the
edge). `spec/media_spec.lua` compares the two files texel by texel instead: the
edge is at least as opaque as the fill everywhere and more opaque somewhere,
which is what an outline all the way round actually means.

The lower chevron's bottom edge sits at y=16 on a 16-unit canvas, so half of
its 1-unit stroke reaches y=16.5 and that half unit is clipped by the canvas;
the upper chevron's arms end at x=0.5 and x=15.5, so their strokes reach the
left and right edges exactly and have no room to dilate outward there. Both are
the drawing's own geometry, kept rather than nudged - UX-4c clipped 0.05 of a
unit at the same edge for the same reason.

## Looking at what was rendered

```powershell
cd tools\media
node contact-sheet.mjs [outDir]
```

`contact-sheet.mjs` decodes every TGA in `Lootpath/Media` - it is `render.mjs`
read backwards - and writes one PNG per texture: the texture composited over a
flat near-black ground and over a busy, saturated stand-in for item art, each at
1x, 3x and 6x, nearest-neighbour so a texel stays a texel. It also writes
`mark16-pair.png`, the edge tinted with `ns.UI.MARK_EDGE_COLOR` under the fill
tinted with `ns.UI.BRAND_HEX` at one anchor with no offset, which is what the
bag corner and the drift badge draw. Both constants are read out of
`Lootpath/UI/ItemLine.lua`, so the sheet cannot show a colour the addon does not
use. Nothing is installed for it: PNG is written with node's own zlib. The
output directory defaults to `tools/media/contact-sheet/`, which is gitignored.

UX-4c wrote this decoder in a scratch directory and lost it; this is the same
tool in the repo, which is what that build's report asked for.
