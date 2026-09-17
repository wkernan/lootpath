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
| `mark16.tga` | 16 x 16 | white + alpha, **tinted in Lua** | the bag mark in both bag adapters, and the drift badge on the launcher |
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
Candidate A of the WKE-602 proposal, picked by the owner on 2026-09-16. The
full form is the two chevrons; the reduced form - one thick chevron, redrawn on
a 16-unit grid rather than shrunk - is what `mark16.tga` is, because R-2b
settled that a mark is drawn at the size it will be seen at.
