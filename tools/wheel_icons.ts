// Cut the emote wheel's icons (2026-10-21) out of their painted sheet into the addon's textures. Master
// (data/icons/wheel/sheet.jpg, not in git): openrouter-images skill, google/gemini-3.1-flash-image-preview, 16:9, 2K,
// eight flat "World of Warcraft emoji" icons in the ping wheel's style on flat magenta, 4 columns x 2 rows, in the
// wheel's order: hello, thanks, congrats, applaud / laugh, dance, bow, sit.
// Each cell: the magenta keyed out (alpha and despill; the sheet is a JPEG, so the key is soft), cropped to what is
// left, centered in a square with a small margin, ICON x ICON, written as uncompressed 32-bit TGA, bottom-left origin
// (media/wheel/<key>.tga), plus a preview on a dark ground (data/icons/wheel/preview.png). ffmpeg decodes the sheet.
//   node tools/wheel_icons.ts
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "data/icons/wheel/sheet.jpg");
const MEDIA = join(ROOT, "addon/ForeverSpeech/media/wheel");
const KEYS = ["hello", "thanks", "congrats", "applaud", "laugh", "dance", "bow", "sit"];
const COLS = 4, ROWS = 2, ICON = 64, MARGIN = 0.05;

type Image = { width: number; height: number; data: Float64Array }; // RGBA 0..1

function readImage(path: string): Image {
  const probe = execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
    "-of", "csv=p=0", path]).toString().trim().split(",").map(Number);
  const [width, height] = probe;
  const raw = execFileSync("ffmpeg", ["-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
    { maxBuffer: 1 << 28 });
  const data = new Float64Array(width * height * 4);
  for (let i = 0; i < data.length; i++) data[i] = raw[i] / 255;
  return { width, height, data };
}

function smooth(e0: number, e1: number, t: number): number {
  const k = Math.min(1, Math.max(0, (t - e0) / (e1 - e0)));
  return k * k * (3 - 2 * k);
}

// Magenta out: how magenta a pixel is (red and blue above green) sets its transparency; what is left of the magenta
// in a soft edge is taken off its red and blue.
function keyMagenta(img: Image): void {
  const d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    const m = Math.min(d[i], d[i + 2]) - d[i + 1];
    const alpha = 1 - smooth(0.3, 0.62, m);
    d[i + 3] = alpha;
    if (m > 0) {
      const spill = m * (1 - alpha * 0.5);
      d[i] = Math.max(0, d[i] - spill);
      d[i + 2] = Math.max(0, d[i + 2] - spill);
    }
  }
}

// The box of a cell's visible pixels.
function boxOf(img: Image, x0: number, y0: number, x1: number, y1: number) {
  let bx0 = x1, by0 = y1, bx1 = x0, by1 = y0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      if (img.data[(y * img.width + x) * 4 + 3] > 0.15) {
        bx0 = Math.min(bx0, x); by0 = Math.min(by0, y); bx1 = Math.max(bx1, x); by1 = Math.max(by1, y);
      }
    }
  }
  return { x0: bx0, y0: by0, x1: bx1, y1: by1 };
}

// The square around a box, resampled to ICON x ICON by area averaging (alpha-weighted colors).
function cut(img: Image, b: { x0: number; y0: number; x1: number; y1: number }): Float64Array {
  const side = Math.max(b.x1 - b.x0 + 1, b.y1 - b.y0 + 1) / (1 - 2 * MARGIN);
  const cx = (b.x0 + b.x1 + 1) / 2, cy = (b.y0 + b.y1 + 1) / 2;
  const step = side / ICON, out = new Float64Array(ICON * ICON * 4);
  for (let y = 0; y < ICON; y++) {
    for (let x = 0; x < ICON; x++) {
      let r = 0, g = 0, bl = 0, a = 0, n = 0;
      const sx0 = cx - side / 2 + x * step, sy0 = cy - side / 2 + y * step;
      for (let sy = Math.floor(sy0); sy < Math.ceil(sy0 + step); sy++) {
        for (let sx = Math.floor(sx0); sx < Math.ceil(sx0 + step); sx++) {
          n++;
          if (sx < 0 || sy < 0 || sx >= img.width || sy >= img.height) continue;
          const i = (sy * img.width + sx) * 4, w = img.data[i + 3];
          r += img.data[i] * w; g += img.data[i + 1] * w; bl += img.data[i + 2] * w; a += w;
        }
      }
      const o = (y * ICON + x) * 4;
      out[o + 3] = a / n;
      if (a > 0) {
        out[o] = r / a; out[o + 1] = g / a; out[o + 2] = bl / a;
      }
    }
  }
  return out;
}

function writeTga(path: string, px: Float64Array): void {
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(ICON, 12);
  header.writeUInt16LE(ICON, 14);
  header[16] = 32;
  header[17] = 0x08;
  const body = Buffer.alloc(ICON * ICON * 4);
  for (let y = 0; y < ICON; y++) {
    for (let x = 0; x < ICON; x++) {
      const i = (y * ICON + x) * 4, o = ((ICON - 1 - y) * ICON + x) * 4;
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

function writePreview(path: string, icons: Float64Array[]): void {
  const cell = 96, w = cell * icons.length, h = cell, raw = Buffer.alloc(w * h * 3);
  icons.forEach((px, t) => {
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < cell; x++) {
        const sx = Math.floor(((x - 16) * ICON) / 64), sy = Math.floor(((y - 16) * ICON) / 64);
        const o = (y * w + t * cell + x) * 3;
        let c = [0.12, 0.12, 0.13];
        if (sx >= 0 && sy >= 0 && sx < ICON && sy < ICON) {
          const i = (sy * ICON + sx) * 4, a = px[i + 3];
          c = c.map((v, k) => v * (1 - a) + px[i + k] * a);
        }
        for (let k = 0; k < 3; k++) raw[o + k] = Math.round(c[k] * 255);
      }
    }
  });
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", `${w}x${h}`, "-i", "-",
    path], { input: raw });
  console.log(`wrote ${path}`);
}

const sheet = readImage(SRC);
keyMagenta(sheet);
const cw = sheet.width / COLS, ch = sheet.height / ROWS, icons: Float64Array[] = [];
KEYS.forEach((key, k) => {
  const col = k % COLS, row = Math.floor(k / COLS);
  const b = boxOf(sheet, Math.round(col * cw), Math.round(row * ch), Math.round((col + 1) * cw),
    Math.round((row + 1) * ch));
  const px = cut(sheet, b);
  writeTga(join(MEDIA, key + ".tga"), px);
  icons.push(px);
});
writePreview(join(ROOT, "data/icons/wheel/preview.png"), icons);
