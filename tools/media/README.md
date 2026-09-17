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
then picked **Fix E at 16**, which changes the shape and leaves the colour: the upper chevron solid,
the lower at 65%, a one-unit near-black outline around every edge, and no plate
behind it. The geometry in `mark16-fill.svg` and `mark16-edge.svg` is that
drawing's, path for path - still drawn on a 16-unit grid rather than shrunk from
`mark64`, because R-2b settled that a mark is drawn at the size it will be seen
at.

**Why 16 is two files.** A keyline is a second colour, and one texture carries
one tint. Baking the brand in would cost the one-line colour edit that
`ns.UI.BRAND_HEX` exists for, so the outline silhouette and the chevron bodies
ship separately, both white with alpha:

  * `mark16-edge.svg` is both chevrons filled **and** stroked in white, so what
    comes out is one solid silhouette dilated by half the stroke on every side;
  * `mark16-fill.svg` is the two bodies, the lower at 65% alpha.

Drawn at the **same anchor** with the edge underneath, that dilation is the
keyline, all the way round both chevrons. The mark this replaced had the fill
inset one point inside the edge instead, which is a shadow on one side and not
an outline.

The lower chevron is opaque in the edge file and 65% only in the fill. The
faithful reading of the page puts `opacity` on the path element, so the lower
stroke would be at 65% too; both were rendered and decoded back to a contact
sheet over a dark ground and a busy one at 1x, 3x and 6x, and the 65% keyline
lets the lower chevron dissolve into busy item art - the exact thing the issue
exists to fix. The 65% belongs on the body, where the hierarchy is read.

The lower chevron's bottom edge sits at y=15.5 on a 16-unit canvas, so half of
its 1.1 stroke reaches y=16.05 and the last 0.05 of a unit is clipped. That is
the drawing's own geometry, kept rather than nudged.
