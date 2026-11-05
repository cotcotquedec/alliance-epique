// Cut the five quest difficulty badges (2026-10-18) out of their painted sheet into the addon's textures.
// Master: data/icons/difficulty/sheet.png (not in git), ChatGPT image, five shields in a row on flat magenta, from
// left to right: trivial (gray), standard (green), difficult (yellow), verydifficult (orange), impossible (red).
// Each badge: the magenta keyed out (alpha and despill), a square crop centered on its dark center plate (where the
// addon writes the quest level), the same scale for all five (the biggest one fills its square, so a humble badge
// stays small), then SIZE x SIZE (128) uncompressed 32-bit TGA, bottom-left origin like tools/tab_icons.sh
// (media/difficulty/<key>.tga). Also writes a preview (data/icons/difficulty/preview.png) and prints each plate's
// size in the texture, for the number's font size. ffmpeg decodes the PNG; nothing else is needed.
//   node tools/difficulty_badges.ts
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SHEET = join(ROOT, "data/icons/difficulty/sheet.png");
const PREVIEW = join(ROOT, "data/icons/difficulty/preview.png");
const OUT = join(ROOT, "addon/ForeverSpeech/media/difficulty");
const KEYS = ["trivial", "standard", "difficult", "verydifficult", "impossible"];
const SIZE = 128;
const MARGIN = 0.02; // of the square, around the biggest badge
const NOISE = 30; // pixels: a smaller group is dropped

type Image = { width: number; height: number; data: Float64Array }; // RGBA, 0..1, not premultiplied

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
    const m = Math.min(r, b) - g;
    const a = Math.min(1, Math.max(0, (HIGH - m) / (HIGH - LOW)));
    if (a < 1) {
      // c = a * fg + (1 - a) * magenta
      d[i] = a > 0 ? Math.min(1, Math.max(0, (r - (1 - a)) / a)) : 0;
      d[i + 1] = a > 0 ? Math.min(1, Math.max(0, g / a)) : 0;
      d[i + 2] = a > 0 ? Math.min(1, Math.max(0, (b - (1 - a)) / a)) : 0;
    }
    d[i + 3] = a;
  }
}

type Box = { x0: number; y0: number; x1: number; y1: number }; // inclusive

// The badges: the KEYS.length biggest groups of connected opaque pixels, left to right (their columns overlap: a
// sword tip under the next badge's horn). A small group (an ember, a spark) joins the badge whose box is nearest, and
// only its pixels are kept in that badge (label): a neighbour's sword tip stays out of the crop.
function findBadges(img: Image): { boxes: Box[]; label: Int32Array } {
  const { width, height, data } = img;
  const label = new Int32Array(width * height).fill(-1);
  const groups: (Box & { n: number })[] = [];
  for (let start = 0; start < width * height; start++) {
    if (label[start] !== -1 || data[start * 4 + 3] <= 0.05) continue;
    const g = groups.length, box = { x0: width, y0: height, x1: 0, y1: 0, n: 0 };
    const stack = [start];
    label[start] = g;
    while (stack.length) {
      const p = stack.pop()!, x = p % width, y = (p - x) / width;
      box.n++;
      box.x0 = Math.min(box.x0, x);
      box.x1 = Math.max(box.x1, x);
      box.y0 = Math.min(box.y0, y);
      box.y1 = Math.max(box.y1, y);
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy, q = ny * width + nx;
          if (nx >= 0 && ny >= 0 && nx < width && ny < height && label[q] === -1 && data[q * 4 + 3] > 0.05) {
            label[q] = g;
            stack.push(q);
          }
        }
      }
    }
    groups.push(box);
  }
  const big = groups.map((b, g) => g).sort((a, b) => groups[b].n - groups[a].n).slice(0, KEYS.length)
    .sort((a, b) => groups[a].x0 - groups[b].x0);
  const owner = groups.map((b, g) => {
    const k = big.indexOf(g);
    if (k !== -1) return k;
    if (b.n < NOISE) return -1;
    let best = 0, bestDist = Infinity;
    big.forEach((h, j) => {
      const o = groups[h];
      const dx = Math.max(0, o.x0 - b.x1, b.x0 - o.x1), dy = Math.max(0, o.y0 - b.y1, b.y0 - o.y1);
      if (dx + dy < bestDist) {
        bestDist = dx + dy;
        best = j;
      }
    });
    return best;
  });
  const boxes = big.map((h) => ({ x0: groups[h].x0, y0: groups[h].y0, x1: groups[h].x1, y1: groups[h].y1 }));
  groups.forEach((b, g) => {
    if (owner[g] === -1) return;
    const box = boxes[owner[g]];
    box.x0 = Math.min(box.x0, b.x0);
    box.x1 = Math.max(box.x1, b.x1);
    box.y0 = Math.min(box.y0, b.y0);
    box.y1 = Math.max(box.y1, b.y1);
  });
  for (let p = 0; p < label.length; p++) {
    if (label[p] !== -1) label[p] = owner[label[p]];
  }
  return { boxes, label };
}

// The dark center plate: the charcoal pixels connected to the badge's center (flood fill). Charcoal: dark grey, not
// black (the black outlines would lead the fill all around the badge), hardly any color.
function findPlate(img: Image, box: Box): Box {
  const dark = (x: number, y: number) => {
    const i = (y * img.width + x) * 4, [r, g, b] = [img.data[i], img.data[i + 1], img.data[i + 2]];
    const luma = 0.299 * r + 0.587 * g + 0.114 * b;
    return img.data[i + 3] > 0.9 && luma > 0.09 && luma < 0.34 && Math.max(r, g, b) - Math.min(r, g, b) < 0.1;
  };
  let sx = Math.round((box.x0 + box.x1) / 2), sy = Math.round((box.y0 + box.y1) / 2);
  // start on a dark pixel near the center
  outer: for (let r = 0; r < 60; r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        if (dark(sx + dx, sy + dy)) {
          sx += dx;
          sy += dy;
          break outer;
        }
      }
    }
  }
  const seen = new Uint8Array(img.width * img.height);
  const stack = [sx, sy];
  const plate: Box = { x0: sx, y0: sy, x1: sx, y1: sy };
  while (stack.length) {
    const y = stack.pop()!, x = stack.pop()!;
    if (x < box.x0 || x > box.x1 || y < box.y0 || y > box.y1 || seen[y * img.width + x] || !dark(x, y)) continue;
    seen[y * img.width + x] = 1;
    plate.x0 = Math.min(plate.x0, x);
    plate.x1 = Math.max(plate.x1, x);
    plate.y0 = Math.min(plate.y0, y);
    plate.y1 = Math.max(plate.y1, y);
    stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1);
  }
  return plate;
}

// Area resampling of the square (cx, cy, side) to SIZE x SIZE, premultiplied alpha; only the pixels of badge k
// (label), the rest transparent.
function resample(img: Image, label: Int32Array, k: number, cx: number, cy: number, side: number): Float64Array {
  const out = new Float64Array(SIZE * SIZE * 4);
  const step = side / SIZE, x0 = cx - side / 2, y0 = cy - side / 2;
  for (let oy = 0; oy < SIZE; oy++) {
    for (let ox = 0; ox < SIZE; ox++) {
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      const ya = Math.floor(y0 + oy * step), yb = Math.floor(y0 + (oy + 1) * step);
      const xa = Math.floor(x0 + ox * step), xb = Math.floor(x0 + (ox + 1) * step);
      for (let y = ya; y < yb; y++) {
        for (let x = xa; x < xb; x++) {
          n++;
          if (x < 0 || y < 0 || x >= img.width || y >= img.height || label[y * img.width + x] !== k) continue;
          const i = (y * img.width + x) * 4, al = img.data[i + 3];
          r += img.data[i] * al;
          g += img.data[i + 1] * al;
          b += img.data[i + 2] * al;
          a += al;
        }
      }
      const o = (oy * SIZE + ox) * 4;
      out[o] = a > 0 ? r / a : 0;
      out[o + 1] = a > 0 ? g / a : 0;
      out[o + 2] = a > 0 ? b / a : 0;
      out[o + 3] = n > 0 ? a / n : 0;
    }
  }
  return out;
}

// Uncompressed 32-bit TGA, bottom-left origin (descriptor 0x08).
function writeTga(path: string, px: Float64Array): void {
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(SIZE, 12);
  header.writeUInt16LE(SIZE, 14);
  header[16] = 32;
  header[17] = 0x08;
  const body = Buffer.alloc(SIZE * SIZE * 4);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const i = (y * SIZE + x) * 4, o = ((SIZE - 1 - y) * SIZE + x) * 4;
      body[o] = Math.round(px[i + 2] * 255);
      body[o + 1] = Math.round(px[i + 1] * 255);
      body[o + 2] = Math.round(px[i] * 255);
      body[o + 3] = Math.round(px[i + 3] * 255);
    }
  }
  writeFileSync(path, Buffer.concat([header, body]));
}

// The five badges side by side, 4x, over the window's dark background, for a look.
function writePreview(badges: Float64Array[]): void {
  const Z = 4, W = SIZE * Z * badges.length, H = SIZE * Z;
  const raw = Buffer.alloc(W * H * 3);
  badges.forEach((px, k) => {
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < SIZE * Z; x++) {
        const i = (Math.floor(y / Z) * SIZE + Math.floor(x / Z)) * 4, a = px[i + 3];
        const o = (y * W + k * SIZE * Z + x) * 3;
        raw[o] = Math.round((px[i] * a + 0.17 * (1 - a)) * 255);
        raw[o + 1] = Math.round((px[i + 1] * a + 0.15 * (1 - a)) * 255);
        raw[o + 2] = Math.round((px[i + 2] * a + 0.13 * (1 - a)) * 255);
      }
    }
  });
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", `${W}x${H}`, "-i",
    "-", PREVIEW], { input: raw });
}

const img = readPng(SHEET);
keyMagenta(img);
const { boxes, label } = findBadges(img);
if (boxes.length !== KEYS.length) {
  throw new Error(`expected ${KEYS.length} badges, found ${boxes.length}: ${JSON.stringify(boxes)}`);
}
const plates = boxes.map((box) => findPlate(img, box));
const centers = plates.map((p) => ({ x: (p.x0 + p.x1) / 2, y: (p.y0 + p.y1) / 2 }));
// one side for all: the farthest edge of any badge from its plate's center, both ways
let half = 0;
boxes.forEach((box, k) => {
  const c = centers[k];
  half = Math.max(half, c.x - box.x0, box.x1 - c.x, c.y - box.y0, box.y1 - c.y);
});
const side = Math.ceil(2 * half * (1 + MARGIN));
mkdirSync(OUT, { recursive: true });
const badges = KEYS.map((key, k) => {
  const px = resample(img, label, k, centers[k].x, centers[k].y, side);
  writeTga(join(OUT, `${key}.tga`), px);
  const p = plates[k], scale = SIZE / side;
  console.log(`${key}: plate ${((p.x1 - p.x0 + 1) * scale).toFixed(1)} x ${((p.y1 - p.y0 + 1) * scale).toFixed(1)}`
    + ` px of ${SIZE} (badge ${((boxes[k].x1 - boxes[k].x0 + 1) * scale).toFixed(1)}`
    + ` x ${((boxes[k].y1 - boxes[k].y0 + 1) * scale).toFixed(1)})`);
  return px;
});
writePreview(badges);
console.log(`wrote ${OUT}/*.tga, ${PREVIEW} (square side ${side} px of the sheet)`);
