// White versions of the addon's glyphs (2026-11-05), for FlareUI's theme: FlareUI's struck bronze (its
// BronzeIcon gradient, a vertex colour) tints a white icon; on the gold glyphs it came out grey. Each
// media/ui/glyph_<name>.tga (uncompressed 32-bit TGA, as tools/ui_icons.ts writes them) becomes
// media/ui/glyph_<name>_white.tga: its luminance, stretched so its brightest opaque pixel is white, its alpha kept.
//   node tools/white_glyphs.ts
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const UI = join(dirname(fileURLToPath(import.meta.url)), "..", "addon", "ForeverSpeech", "media", "ui");
const GLYPHS = ["play", "stop", "next", "replay", "list"];
const HEADER = 18;

for (const name of GLYPHS) {
  const tga = readFileSync(join(UI, `glyph_${name}.tga`));
  const idLength = tga[0];
  const type = tga[2];
  const bits = tga[16];
  if (type !== 2 || bits !== 32) {
    throw new Error(`glyph_${name}.tga: not an uncompressed 32-bit TGA (type ${type}, ${bits} bits)`);
  }
  const start = HEADER + idLength;
  const out = Buffer.from(tga);
  let brightest = 0;
  const luma: number[] = [];
  for (let i = start; i + 3 < tga.length; i += 4) {
    const [b, g, r, a] = [tga[i], tga[i + 1], tga[i + 2], tga[i + 3]];
    const l = 0.299 * r + 0.587 * g + 0.114 * b;
    luma.push(l);
    if (a > 0 && l > brightest) brightest = l;
  }
  const scale = brightest > 0 ? 255 / brightest : 1;
  for (let i = start, k = 0; i + 3 < tga.length; i += 4, k++) {
    const v = Math.min(255, Math.round(luma[k] * scale));
    out[i] = v;
    out[i + 1] = v;
    out[i + 2] = v;
  }
  writeFileSync(join(UI, `glyph_${name}_white.tga`), out);
  console.log(`glyph_${name}_white.tga (brightest ${brightest.toFixed(0)} -> 255)`);
}
