// Cut the interface textures (2026-10-21) out of their painted masters into the addon's textures.
// Masters (data/icons/ui/, not in git), Codex image generation (gpt-image), flat magenta background:
//   glyphs.png  five gold glyphs in a row, left to right: play, stop, next, replay, list
//   ring.png    the round button frame: a bronze-gold ring around a dark disc
//   icon.png    the addon's icon, a full-bleed painting (no magenta), masked round by the game where needed
//   parchment.png  an aged parchment page, full bleed: the zone story panel's background
//   divider.png    a thin ink divider with a small flourish, on magenta: under the panel's title
// Each glyph: the magenta keyed out (alpha and despill), the glyphs told apart by the empty columns between them (a
// glyph made of two parts, like next, stays one), centered in a square, the same scale for all five (the biggest one
// fills its square), GLYPH x GLYPH. The ring: cropped to its own box, RING x RING. The icon: ICON x ICON. The
// parchment: PARCHMENT x PARCHMENT. The divider: cropped to its own box, DIVIDER_W x DIVIDER_H, centered.
// Written as uncompressed 32-bit TGA, bottom-left origin like tools/tab_icons.sh (media/ui/*.tga, media/icon.tga),
// plus a preview on a dark ground (data/icons/ui/preview.png). ffmpeg decodes the PNGs; nothing else is needed.
//   node tools/ui_icons.ts
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "data/icons/ui");
const MEDIA = join(ROOT, "addon/ForeverSpeech/media");
const GLYPHS = ["play", "stop", "next", "replay", "list"];
const GLYPH = 64, RING = 128, ICON = 64, PARCHMENT = 256, DIVIDER_W = 512, DIVIDER_H = 32;
const MARGIN = 0.04; // of the square, around the biggest glyph
const GAP = 40; // empty columns: fewer than this between two parts keeps them in one glyph

type Image = { width: number; height: number; data: Float64Array }; // RGBA, 0..1, not premultiplied
type Box = { x0: number; y0: number; x1: number; y1: number }; // inclusive

function readPng(path: string): Image {
  const probe = execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries",
    "stream=width,height", "-of", "csv=p=0", path]).toString().trim();
  const [width, height] = probe.split(",").map(Number);
  const raw = execFileSync("ffmpeg", ["-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
    { maxBuffer: 1 << 28 });
  const data = new Float64Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    data[i * 4] = raw[i * 3] / 255;
    data[i * 4 + 1] = raw[i * 3 + 1] / 255;
    data[i * 4 + 2] = raw[i * 3 + 2] / 255;
    data[i * 4 + 3] = 1;
  }
  return { width, height, data };
}

// Magenta (r and b high, g low) becomes transparent; the edges in between are unmixed from the magenta.
function keyMagenta(img: Image): void {
  const LOW = 0.3, HIGH = 0.75; // magenta-ness: opaque under LOW, transparent over HIGH
  const d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    const [r, g, b] = [d[i], d[i + 1], d[i + 2]];
    const a = Math.min(1, Math.max(0, (HIGH - (Math.min(r, b) - g)) / (HIGH - LOW)));
    if (a < 1) {
      // c = a * fg + (1 - a) * magenta
      d[i] = a > 0 ? Math.min(1, Math.max(0, (r - (1 - a)) / a)) : 0;
      d[i + 1] = a > 0 ? Math.min(1, Math.max(0, g / a)) : 0;
      d[i + 2] = a > 0 ? Math.min(1, Math.max(0, (b - (1 - a)) / a)) : 0;
    }
    d[i + 3] = a;
  }
}

const opaque = (img: Image, x: number, y: number) => img.data[(y * img.width + x) * 4 + 3] > 0.05;

// The opaque box of the columns x0..x1.
function boxOf(img: Image, x0: number, x1: number): Box {
  const box = { x0: img.width, y0: img.height, x1: 0, y1: 0 };
  for (let y = 0; y < img.height; y++) {
    for (let x = x0; x <= x1; x++) {
      if (opaque(img, x, y)) {
        box.x0 = Math.min(box.x0, x);
        box.x1 = Math.max(box.x1, x);
        box.y0 = Math.min(box.y0, y);
        box.y1 = Math.max(box.y1, y);
      }
    }
  }
  return box;
}

// The glyphs: runs of columns holding an opaque pixel, runs closer than GAP merged, left to right.
function findGlyphs(img: Image, count: number): Box[] {
  const runs: [number, number][] = [];
  for (let x = 0; x < img.width; x++) {
    let any = false;
    for (let y = 0; y < img.height && !any; y++) any = opaque(img, x, y);
    if (!any) continue;
    const last = runs[runs.length - 1];
    if (last && x - last[1] <= GAP) last[1] = x;
    else runs.push([x, x]);
  }
  if (runs.length !== count) throw new Error(`expected ${count} glyphs, found ${runs.length}`);
  return runs.map(([x0, x1]) => boxOf(img, x0, x1));
}

// Area resampling of the square (cx, cy, side) to size x size, premultiplied alpha.
function resample(img: Image, cx: number, cy: number, side: number, size: number): Float64Array {
  return resampleRect(img, cx - side / 2, cy - side / 2, side / size, size, size);
}

// Area resampling from (x0, y0), `step` source pixels per output pixel, to outW x outH.
function resampleRect(img: Image, x0: number, y0: number, step: number, outW: number, outH: number): Float64Array {
  const out = new Float64Array(outW * outH * 4);
  for (let oy = 0; oy < outH; oy++) {
    for (let ox = 0; ox < outW; ox++) {
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      const ya = Math.floor(y0 + oy * step), yb = Math.max(ya + 1, Math.floor(y0 + (oy + 1) * step));
      const xa = Math.floor(x0 + ox * step), xb = Math.max(xa + 1, Math.floor(x0 + (ox + 1) * step));
      for (let y = ya; y < yb; y++) {
        for (let x = xa; x < xb; x++) {
          n++;
          if (x < 0 || y < 0 || x >= img.width || y >= img.height) continue;
          const i = (y * img.width + x) * 4, al = img.data[i + 3];
          r += img.data[i] * al;
          g += img.data[i + 1] * al;
          b += img.data[i + 2] * al;
          a += al;
        }
      }
      const o = (oy * outW + ox) * 4;
      out[o] = a > 0 ? r / a : 0;
      out[o + 1] = a > 0 ? g / a : 0;
      out[o + 2] = a > 0 ? b / a : 0;
      out[o + 3] = n > 0 ? a / n : 0;
    }
  }
  return out;
}

// Uncompressed 32-bit TGA, bottom-left origin (descriptor 0x08).
function writeTga(path: string, px: Float64Array, size: number, height = size): void {
  const width = size;
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(width, 12);
  header.writeUInt16LE(height, 14);
  header[16] = 32;
  header[17] = 0x08;
  const body = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4, o = ((height - 1 - y) * width + x) * 4;
      body[o] = Math.round(px[i + 2] * 255);
      body[o + 1] = Math.round(px[i + 1] * 255);
      body[o + 2] = Math.round(px[i] * 255);
      body[o + 3] = Math.round(px[i + 3] * 255);
    }
  }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, Buffer.concat([header, body]));
  console.log(`wrote ${path}`);
}

// Every texture side by side on a dark ground, as RGBA raw frames through ffmpeg.
function writePreview(tiles: { px: Float64Array; size: number }[]): void {
  const cell = 128, w = cell * tiles.length, h = cell;
  const raw = Buffer.alloc(w * h * 4);
  tiles.forEach(({ px, size }, t) => {
    for (let y = 0; y < cell; y++) {
      for (let x = 0; x < cell; x++) {
        const sx = Math.floor((x * size) / cell), sy = Math.floor((y * size) / cell), i = (sy * size + sx) * 4;
        const a = px[i + 3], o = (y * w + t * cell + x) * 4, ground = 0.16;
        raw[o] = Math.round((px[i] * a + ground * (1 - a)) * 255);
        raw[o + 1] = Math.round((px[i + 1] * a + ground * (1 - a)) * 255);
        raw[o + 2] = Math.round((px[i + 2] * a + ground * (1 - a)) * 255);
        raw[o + 3] = 255;
      }
    }
  });
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", `${w}x${h}`, "-i", "-",
    join(SRC, "preview.png")], { input: raw });
}

const tiles: { px: Float64Array; size: number }[] = [];

const glyphs = readPng(join(SRC, "glyphs.png"));
keyMagenta(glyphs);
const boxes = findGlyphs(glyphs, GLYPHS.length);
const side = Math.max(...boxes.map((b) => Math.max(b.x1 - b.x0 + 1, b.y1 - b.y0 + 1))) / (1 - 2 * MARGIN);
boxes.forEach((b, k) => {
  const px = resample(glyphs, (b.x0 + b.x1 + 1) / 2, (b.y0 + b.y1 + 1) / 2, side, GLYPH);
  writeTga(join(MEDIA, "ui", `glyph_${GLYPHS[k]}.tga`), px, GLYPH);
  tiles.push({ px, size: GLYPH });
});

const ring = readPng(join(SRC, "ring.png"));
keyMagenta(ring);
const rb = boxOf(ring, 0, ring.width - 1);
const ringPx = resample(ring, (rb.x0 + rb.x1 + 1) / 2, (rb.y0 + rb.y1 + 1) / 2,
  Math.max(rb.x1 - rb.x0 + 1, rb.y1 - rb.y0 + 1), RING);
writeTga(join(MEDIA, "ui", "ring.tga"), ringPx, RING);
tiles.push({ px: ringPx, size: RING });

const icon = readPng(join(SRC, "icon.png"));
const iconPx = resample(icon, icon.width / 2, icon.height / 2, Math.min(icon.width, icon.height), ICON);
writeTga(join(MEDIA, "icon.tga"), iconPx, ICON);
tiles.push({ px: iconPx, size: ICON });

const parchment = readPng(join(SRC, "parchment.png"));
const parchmentPx = resample(parchment, parchment.width / 2, parchment.height / 2,
  Math.min(parchment.width, parchment.height), PARCHMENT);
writeTga(join(MEDIA, "ui", "parchment.tga"), parchmentPx, PARCHMENT);
tiles.push({ px: parchmentPx, size: PARCHMENT });

const divider = readPng(join(SRC, "divider.png"));
keyMagenta(divider);
const db = boxOf(divider, 0, divider.width - 1);
const dstep = (db.x1 - db.x0 + 1) / DIVIDER_W;
const dividerPx = resampleRect(divider, db.x0, (db.y0 + db.y1 + 1) / 2 - (DIVIDER_H * dstep) / 2, dstep, DIVIDER_W,
  DIVIDER_H);
writeTga(join(MEDIA, "ui", "divider.tga"), dividerPx, DIVIDER_W, DIVIDER_H);


writePreview(tiles);
