// Render Lootpath's marks from SVG to the TGA files the client reads.
//
//   cd tools/media && npm install && npm run render
//
// resvg (@resvg/resvg-js, MPL-2.0) rasterises; the TGA is written here, because
// resvg writes PNG and the client does not read PNG. Every output is an
// uncompressed 32-bit BGRA TGA with a bottom-left origin - the same shape as the
// TGAs other addons ship (Pawn's `Textures/UpgradeArrow.tga` was read to check:
// type 10 RLE, 32 bpp, descriptor 0x08). We write type 2, uncompressed, which
// the same header describes and every reader takes.
//
// Sizes are powers of two, which is what the client requires. Nothing here
// produces a .blp.

import { Resvg } from "@resvg/resvg-js";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SVG_DIR = join(HERE, "svg");
const FONT = join(HERE, "fonts", "AlegreyaSC-Bold.ttf");
const OUT_DIR = resolve(HERE, "..", "..", "Lootpath", "Media");

const ASSETS = [
  // The 16-point Waymark ships as TWO files (UX-4c): the chevron bodies and the
  // keyline silhouette under them. One texture cannot carry two tints, and the
  // brand colour has to stay a Lua string rather than a re-render.
  { name: "mark16-fill", width: 16, height: 16 },
  { name: "mark16-edge", width: 16, height: 16 },
  { name: "mark64", width: 64, height: 64 },
  { name: "icon256", width: 256, height: 256 },
  { name: "wordmark", width: 256, height: 64 },
];

const isPowerOfTwo = (n) => n > 0 && (n & (n - 1)) === 0;

// Uncompressed 32-bit TGA, BGRA, bottom-left origin (descriptor 0x08 = 8 alpha
// bits, no flip). `rgba` is resvg's top-down RGBA buffer, so the rows go out in
// reverse.
function toTGA(rgba, width, height) {
  const header = Buffer.alloc(18);
  header[2] = 2; // uncompressed true-colour
  header.writeUInt16LE(width, 12);
  header.writeUInt16LE(height, 14);
  header[16] = 32; // bits per pixel
  header[17] = 0x08; // 8 alpha bits, origin bottom-left
  const body = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    const src = (height - 1 - y) * width * 4;
    const dst = y * width * 4;
    for (let x = 0; x < width; x++) {
      body[dst + x * 4 + 0] = rgba[src + x * 4 + 2]; // B
      body[dst + x * 4 + 1] = rgba[src + x * 4 + 1]; // G
      body[dst + x * 4 + 2] = rgba[src + x * 4 + 0]; // R
      body[dst + x * 4 + 3] = rgba[src + x * 4 + 3]; // A
    }
  }
  return Buffer.concat([header, body]);
}

mkdirSync(OUT_DIR, { recursive: true });

for (const asset of ASSETS) {
  if (!isPowerOfTwo(asset.width) || !isPowerOfTwo(asset.height)) {
    throw new Error(`${asset.name}: ${asset.width}x${asset.height} is not a power of two`);
  }
  const svg = readFileSync(join(SVG_DIR, `${asset.name}.svg`), "utf8");
  const resvg = new Resvg(svg, {
    fitTo: { mode: "width", value: asset.width },
    // Only the vendored face is loaded: a render that silently fell back to a
    // system font would look right here and wrong on anyone else's machine.
    font: { loadSystemFonts: false, fontFiles: [FONT] },
    shapeRendering: 2, // geometricPrecision
    textRendering: 2,
  });
  const image = resvg.render();
  if (image.width !== asset.width || image.height !== asset.height) {
    throw new Error(
      `${asset.name}: rendered ${image.width}x${image.height}, wanted ${asset.width}x${asset.height}`,
    );
  }
  const tga = toTGA(image.pixels, image.width, image.height);
  const out = join(OUT_DIR, `${asset.name}.tga`);
  writeFileSync(out, tga);
  console.log(`${asset.name}.tga  ${image.width}x${image.height}  ${tga.length} bytes`);
}
