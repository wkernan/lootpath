// Decode Lootpath's rendered TGAs and look at them the way the client will.
//
//   cd tools/media && node contact-sheet.mjs [outDir]
//
// UX-4c built this by hand in a scratch directory and lost it; UX-4d (WKE-613)
// puts it in the repo, because "render it and then look at it" is the only
// check on the art that is not a screenshot the owner has to take.
//
// For every texture in `Lootpath/Media` it writes one PNG: the texture
// composited over a flat near-black ground and over a busy, saturated ground
// that stands in for item art, each at 1x, 3x and 6x, nearest-neighbour so a
// texel stays a texel. The 16-point Waymark also gets `mark16-pair.png`: the
// edge tinted with `ns.UI.MARK_EDGE_COLOR` under the fill tinted with
// `ns.UI.BRAND_HEX`, at one anchor with no offset, which is what the bag corner
// and the drift badge actually draw. Those two constants are read out of
// `Lootpath/UI/ItemLine.lua` rather than typed here, so this tool cannot drift
// from the addon.
//
// PNG is written here with node's own zlib: nothing is installed for this.

import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const MEDIA = resolve(HERE, "..", "..", "Lootpath", "Media");
const ITEM_LINE = resolve(HERE, "..", "..", "Lootpath", "UI", "ItemLine.lua");
const OUT = resolve(process.argv[2] ?? join(HERE, "contact-sheet"));

const SCALES = [1, 3, 6];
const PAD = 8;
const DARK = [0x16, 0x17, 0x1c, 255];

// ---------------------------------------------------------------- TGA in ----

// The inverse of `render.mjs`: uncompressed 32-bit BGRA, bottom-left origin.
// Anything else here is a file nobody in this repo wrote, so it throws.
function readTGA(path) {
  const bytes = readFileSync(path);
  if (bytes.length < 18) throw new Error(`${path}: too short to be a TGA`);
  const imageType = bytes[2];
  const width = bytes.readUInt16LE(12);
  const height = bytes.readUInt16LE(14);
  const bpp = bytes[16];
  const descriptor = bytes[17];
  if (imageType !== 2 || bpp !== 32) {
    throw new Error(`${path}: image type ${imageType} at ${bpp} bpp, wanted uncompressed 32-bit`);
  }
  const expected = 18 + width * height * 4;
  if (bytes.length !== expected) {
    throw new Error(`${path}: ${bytes.length} bytes, wanted ${expected}`);
  }
  const topDown = (descriptor & 0x20) !== 0;
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    const src = 18 + (topDown ? y : height - 1 - y) * width * 4;
    const dst = y * width * 4;
    for (let x = 0; x < width; x++) {
      rgba[dst + x * 4 + 0] = bytes[src + x * 4 + 2]; // R
      rgba[dst + x * 4 + 1] = bytes[src + x * 4 + 1]; // G
      rgba[dst + x * 4 + 2] = bytes[src + x * 4 + 0]; // B
      rgba[dst + x * 4 + 3] = bytes[src + x * 4 + 3]; // A
    }
  }
  return { width, height, rgba };
}

// --------------------------------------------------------------- PNG out ----

function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

function writePNG(path, image) {
  const { width, height, rgba } = image;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // truecolour with alpha
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0; // filter: none
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  writeFileSync(
    path,
    Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      chunk("IHDR", ihdr),
      chunk("IDAT", deflateSync(raw, { level: 9 })),
      chunk("IEND", Buffer.alloc(0)),
    ]),
  );
}

// -------------------------------------------------------------- compose ----

const surface = (width, height, fill) => {
  const rgba = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    rgba[i * 4 + 0] = fill[0];
    rgba[i * 4 + 1] = fill[1];
    rgba[i * 4 + 2] = fill[2];
    rgba[i * 4 + 3] = fill[3];
  }
  return { width, height, rgba };
};

// A stand-in for item art: saturated, high-contrast, and the same every run, so
// two sheets can be compared. Not Blizzard's icons - nothing here ships.
function busy(width, height, seed = 1) {
  const image = surface(width, height, [0, 0, 0, 255]);
  const hash = (x, y) => {
    let h = (x * 374761393 + y * 668265263 + seed * 2654435761) >>> 0;
    h = (h ^ (h >>> 13)) * 1274126177;
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  };
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const cell = hash(Math.floor(x / 9), Math.floor(y / 9));
      const fine = hash(x, y);
      const hue = (cell * 360 + fine * 40) % 360;
      const value = 0.35 + 0.6 * ((cell * 3) % 1);
      const c = value * 0.9;
      const hp = hue / 60;
      const xx = c * (1 - Math.abs((hp % 2) - 1));
      const [r, g, b] =
        hp < 1
          ? [c, xx, 0]
          : hp < 2
            ? [xx, c, 0]
            : hp < 3
              ? [0, c, xx]
              : hp < 4
                ? [0, xx, c]
                : hp < 5
                  ? [xx, 0, c]
                  : [c, 0, xx];
      const m = value - c;
      const i = (y * width + x) * 4;
      image.rgba[i + 0] = Math.round((r + m) * 255);
      image.rgba[i + 1] = Math.round((g + m) * 255);
      image.rgba[i + 2] = Math.round((b + m) * 255);
      image.rgba[i + 3] = 255;
    }
  }
  return image;
}

// Source over destination, nearest-neighbour at `scale`. This is what the
// client does with an alpha texture on a frame, and doing it here is the whole
// point: an alpha channel judged as a grey square tells you nothing.
function draw(dest, src, left, top, scale, tint) {
  for (let y = 0; y < src.height * scale; y++) {
    for (let x = 0; x < src.width * scale; x++) {
      const s = (Math.floor(y / scale) * src.width + Math.floor(x / scale)) * 4;
      const a = src.rgba[s + 3] / 255;
      if (a === 0) continue;
      const dx = left + x;
      const dy = top + y;
      if (dx < 0 || dy < 0 || dx >= dest.width || dy >= dest.height) continue;
      const d = (dy * dest.width + dx) * 4;
      for (let c = 0; c < 3; c++) {
        const value = tint ? src.rgba[s + c] * tint[c] : src.rgba[s + c];
        dest.rgba[d + c] = Math.round(value * a + dest.rgba[d + c] * (1 - a));
      }
      dest.rgba[d + 3] = 255;
    }
  }
}

// One PNG: the layers composited over both grounds, at every scale.
function sheet(layers, width, height) {
  const cellW = SCALES.reduce((sum, s) => sum + width * s + PAD, PAD);
  const cellH = height * Math.max(...SCALES) + PAD * 2;
  const image = surface(cellW, cellH * 2, [0, 0, 0, 255]);
  const grounds = [surface(cellW, cellH, DARK), busy(cellW, cellH)];
  grounds.forEach((ground, row) => {
    ground.rgba.copy(image.rgba, row * cellH * cellW * 4);
    let x = PAD;
    for (const scale of SCALES) {
      for (const layer of layers) {
        draw(image, layer.texture, x, row * cellH + PAD, scale, layer.tint);
      }
      x += width * scale + PAD;
    }
  });
  return image;
}

// --------------------------------------------------- the addon's own hexes ----

const lua = readFileSync(ITEM_LINE, "utf8");
const brandHex = lua.match(/UI\.BRAND_HEX\s*=\s*"([0-9A-Fa-f]{6})"/)?.[1];
if (!brandHex) throw new Error("no ns.UI.BRAND_HEX in " + ITEM_LINE);
const edgeColor = lua
  .match(/UI\.MARK_EDGE_COLOR\s*=\s*\{([^}]*)\}/)?.[1]
  .split(",")
  .map((n) => Number(n.trim()));
if (!edgeColor || edgeColor.length < 3) throw new Error("no ns.UI.MARK_EDGE_COLOR in " + ITEM_LINE);
const brand = [0, 2, 4].map((i) => parseInt(brandHex.slice(i, i + 2), 16) / 255);

mkdirSync(OUT, { recursive: true });

const names = readdirSync(MEDIA)
  .filter((f) => f.endsWith(".tga"))
  .map((f) => f.replace(/\.tga$/, ""));

for (const name of names) {
  const texture = readTGA(join(MEDIA, name + ".tga"));
  const out = join(OUT, name + ".png");
  writePNG(out, sheet([{ texture }], texture.width, texture.height));
  console.log(`${out}  ${texture.width}x${texture.height} at 1x/3x/6x over dark and busy`);
}

const edge = readTGA(join(MEDIA, "mark16-edge.tga"));
const fill = readTGA(join(MEDIA, "mark16-fill.tga"));
const pair = join(OUT, "mark16-pair.png");
writePNG(
  pair,
  sheet(
    [
      { texture: edge, tint: edgeColor },
      { texture: fill, tint: brand },
    ],
    16,
    16,
  ),
);
console.log(`${pair}  the pair as the addon draws it: edge tinted ${edgeColor
  .slice(0, 3)
  .join("/")} under fill tinted #${brandHex}`);
