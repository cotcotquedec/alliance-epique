// The medallion's ring without its dark centre (2026-11-08): media/ui/ring.tga (uncompressed 32-bit TGA, written by
// tools/ui_icons.ts) becomes media/ui/ring_band.tga, its centre transparent up to the gold band, so the ring can be
// drawn above the talking NPC's 3D model (a model cannot be masked round) and hide the corners of its square.
// The band's inner edge: from the centre, the first pixel whose luminance passes LUMA_GOLD, along 64 directions; the
// median radius (the ornaments on the axes reach further in). A 1-pixel ramp softens the edge.
//   node tools/ring_band.ts
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const UI = join(dirname(fileURLToPath(import.meta.url)), "..", "addon", "ForeverSpeech", "media", "ui");
const HEADER = 18;
const LUMA_GOLD = 70;

const tga = readFileSync(join(UI, "ring.tga"));
const [idLength, type, bits] = [tga[0], tga[2], tga[16]];
const width = tga.readUInt16LE(12);
const height = tga.readUInt16LE(14);
if (type !== 2 || bits !== 32) {
  throw new Error(`ring.tga: not an uncompressed 32-bit TGA (type ${type}, ${bits} bits)`);
}
const start = HEADER + idLength;
const at = (x: number, y: number) => start + (y * width + x) * 4;
const luma = (x: number, y: number) => {
  const i = at(x, y);
  return 0.299 * tga[i + 2] + 0.587 * tga[i + 1] + 0.114 * tga[i];
};
const cx = (width - 1) / 2;
const cy = (height - 1) / 2;
const radii = Array.from({ length: 64 }, (_, k) => [Math.cos((k * Math.PI) / 32), Math.sin((k * Math.PI) / 32)]).map(([dx, dy]) => {
  for (let r = 0; r < width / 2; r++) {
    const x = Math.round(cx + dx * r);
    const y = Math.round(cy + dy * r);
    if (luma(x, y) > LUMA_GOLD) return r;
  }
  return -1; // no gold this way (a dark stretch of the band): not counted
}).filter((r) => r >= 0);
if (radii.length < 32) throw new Error(`ring.tga: gold band found in ${radii.length} directions of 64`);
const inner = [...radii].sort((a, b) => a - b)[radii.length >> 1];
const out = Buffer.from(tga);
for (let y = 0; y < height; y++) {
  for (let x = 0; x < width; x++) {
    const d = Math.hypot(x - cx, y - cy);
    const keep = Math.max(0, Math.min(1, d - (inner - 1))); // 0 inside, a 1-pixel ramp to the band
    const i = at(x, y);
    out[i + 3] = Math.round(out[i + 3] * keep);
  }
}
writeFileSync(join(UI, "ring_band.tga"), out);
console.log(`ring_band.tga ${width}x${height}, hole radius ${inner} px (from ${Math.min(...radii)} to ${Math.max(...radii)})`);
