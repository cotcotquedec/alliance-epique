// Draw the emote wheel's own textures (2026-10-21), in the style of the game's ping wheel, whose 8-wedge art the
// Forever client does not have (T60: only Radial_Wheel_BG and Radial_Wheel_Select_Pointer). Drawn by code, nothing
// painted or copied:
//   media/ui/wheel_disc.tga   256 x 256  the wheel's dark disc, soft edge
//   media/ui/wheel_wedge.tga  256 x 256  the aimed wedge: a 45-degree gold cone from the center button to the rim,
//                                        pointing east (the wheel turns it with SetRotation, counterclockwise)
//   media/ui/wheel_center.tga  64 x 64   the center button: a dark disc in a grey ring
// Each pixel is supersampled (SS x SS) for smooth edges. Written as uncompressed 32-bit TGA, bottom-left origin, like
// tools/ui_icons.ts, plus a preview of the assembled wheel on a mid grey ground (data/icons/ui/wheel_preview.png).
//   node tools/wheel_art.ts
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const MEDIA = join(ROOT, "addon/ForeverSpeech/media/ui");
const SS = 4;
const HALF_WEDGE = Math.PI / 8; // 45 degrees wide
const GOLD = [1.0, 0.78, 0.24];

type Px = Float64Array; // RGBA 0..1, not premultiplied, top-left origin
type Shader = (r: number, a: number) => [number, number, number, number]; // r: 0..0.5 of the size, a: radians

function draw(size: number, shade: Shader): Px {
  const px = new Float64Array(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let cr = 0, cg = 0, cb = 0, ca = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const u = (x + (sx + 0.5) / SS) / size - 0.5, v = 0.5 - (y + (sy + 0.5) / SS) / size; // v up
          const [r, g, b, a] = shade(Math.hypot(u, v), Math.atan2(v, u));
          cr += r * a; cg += g * a; cb += b * a; ca += a;
        }
      }
      const i = (y * size + x) * 4, n = SS * SS;
      px[i + 3] = ca / n;
      if (ca > 0) {
        px[i] = cr / ca; px[i + 1] = cg / ca; px[i + 2] = cb / ca;
      }
    }
  }
  return px;
}

// 0 below e0, 1 above e1, smooth between.
function smooth(e0: number, e1: number, t: number): number {
  const k = Math.min(1, Math.max(0, (t - e0) / (e1 - e0)));
  return k * k * (3 - 2 * k);
}

const disc: Shader = (r) => {
  const alpha = (0.8 - 0.12 * (r / 0.5)) * (1 - smooth(0.455, 0.5, r));
  return [0.05, 0.05, 0.06, alpha];
};

const wedge: Shader = (r, a) => {
  const off = Math.abs(a); // the cone points east: a in -pi..pi
  if (off > HALF_WEDGE) {
    return [0, 0, 0, 0];
  }
  const inner = smooth(0.085, 0.1, r), outer = 1 - smooth(0.47, 0.49, r);
  const side = 1 - smooth(HALF_WEDGE - 0.012, HALF_WEDGE, off); // a soft angular edge
  const edge = smooth(HALF_WEDGE - 0.05, HALF_WEDGE - 0.012, off); // brighter along both sides
  const fade = 0.62 - 0.32 * smooth(0.1, 0.49, r); // stronger near the center, lighter at the rim
  const alpha = Math.min(1, (fade + 0.3 * edge) * inner * outer * side);
  return [GOLD[0], GOLD[1], GOLD[2], alpha];
};

const center: Shader = (r) => {
  const ring = smooth(0.36, 0.39, r) * (1 - smooth(0.45, 0.48, r));
  const fill = 1 - smooth(0.36, 0.39, r);
  if (ring > 0) {
    const g = 0.42;
    return [g, g, g, 0.9 * ring + 0.85 * fill];
  }
  return [0.06, 0.06, 0.07, 0.85 * fill];
};

function writeTga(path: string, px: Px, size: number): void {
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(size, 12);
  header.writeUInt16LE(size, 14);
  header[16] = 32;
  header[17] = 0x08;
  const body = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4, o = ((size - 1 - y) * size + x) * 4;
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

// The wheel as the addon lays it out (ui/emote_wheel.lua: 300 px, lines from 26 px, wedge 3 aimed), over grey.
function writePreview(path: string, discPx: Px, wedgePx: Px, centerPx: Px): void {
  const W = 300, out = new Float64Array(W * W * 3).fill(0.35);
  const over = (src: Px, size: number, scale: number, rot: number) => {
    for (let y = 0; y < W; y++) {
      for (let x = 0; x < W; x++) {
        const u = (x + 0.5 - W / 2) / scale, v = (W / 2 - y - 0.5) / scale; // in texture units, v up
        const ru = u * Math.cos(-rot) - v * Math.sin(-rot), rv = u * Math.sin(-rot) + v * Math.cos(-rot);
        const sx = Math.floor((ru + 0.5) * size), sy = Math.floor((0.5 - rv) * size);
        if (sx < 0 || sy < 0 || sx >= size || sy >= size) continue;
        const i = (sy * size + sx) * 4, a = src[i + 3], o = (y * W + x) * 3;
        for (let c = 0; c < 3; c++) out[o + c] = out[o + c] * (1 - a) + src[i + c] * a;
      }
    }
  };
  over(discPx, 256, W, 0);
  over(wedgePx, 256, W, Math.PI / 2 + 2 * (Math.PI / 4));
  for (let k = 0; k < 8; k++) { // the 8 lines, as the addon draws them
    const ang = Math.PI / 2 + k * (Math.PI / 4) + Math.PI / 8;
    for (let d = 26; d < W / 2 - 6; d += 0.25) {
      const x = Math.round(W / 2 + Math.cos(ang) * d), y = Math.round(W / 2 - Math.sin(ang) * d), o = (y * W + x) * 3;
      for (let c = 0; c < 3; c++) out[o + c] = out[o + c] * 0.65 + 0.55 * 0.35;
    }
  }
  over(centerPx, 64, 52, 0);
  const raw = Buffer.alloc(W * W * 3);
  out.forEach((v, i) => { raw[i] = Math.round(Math.min(1, v) * 255); });
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", `${W}x${W}`,
    "-i", "-", path], { input: raw });
  console.log(`wrote ${path}`);
}

const discPx = draw(256, disc), wedgePx = draw(256, wedge), centerPx = draw(64, center);
writeTga(join(MEDIA, "wheel_disc.tga"), discPx, 256);
writeTga(join(MEDIA, "wheel_wedge.tga"), wedgePx, 256);
writeTga(join(MEDIA, "wheel_center.tga"), centerPx, 64);
writePreview(join(ROOT, "data/icons/ui/wheel_preview.png"), discPx, wedgePx, centerPx);
