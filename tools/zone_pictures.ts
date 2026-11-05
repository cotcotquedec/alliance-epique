// Paint a picture for each zone Elise introduces (D16), for the zone story panel beside the world map (2026-10-21).
// One Codex image per zone (image generation, gpt-image), from the zone's English and French names and Elise's own
// text (data/zones/<group>/@intros/scripts.json): a landscape, no people, no text. Masters in data/icons/zones/
// <mapID>.png (not in git; an existing master is kept, delete it to paint it again), then the addon's texture:
// media/zones/<mapID>.tga, 512 x 256 (cover crop), uncompressed 24-bit TGA, bottom-left origin like
// tools/tab_icons.sh (not in git either: made again from the masters by this tool).
//   node tools/zone_pictures.ts [--jobs 3] [--only <mapID>,...] [--convert-only]
import { execFile, execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ZONES = join(ROOT, "data/zones");
const MASTERS = join(ROOT, "data/icons/zones");
const OUT = join(ROOT, "addon/ForeverSpeech/media/zones");
const W = 512, H = 256;

const args = process.argv.slice(2);
const opt = (name: string) => {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args[i + 1];
};
const jobs = Number(opt("--jobs") ?? 3);
const only = opt("--only")?.split(",").map(Number);
const convertOnly = args.includes("--convert-only");

type Zone = { map: number; name: string; nameEn: string; text: string };

function zones(): Zone[] {
  const out: Zone[] = [];
  for (const group of readdirSync(ZONES)) {
    const path = join(ZONES, group, "@intros/scripts.json");
    if (!existsSync(path)) continue;
    for (const z of Object.values<any>(JSON.parse(readFileSync(path, "utf8")).zones ?? {})) {
      if (z.map && (!only || only.includes(z.map))) {
        out.push({ map: z.map, name: z.name, nameEn: z.name_en ?? z.name, text: z.text ?? "" });
      }
    }
  }
  return out.sort((a, b) => a.map - b.map);
}

function prompt(z: Zone): string {
  return [
    "Use your image generation tool to create ONE image, then reply only with the saved file path.",
    "Image: a wide landscape painting, 1536x1024, for a fantasy game's lore book.",
    `The place: "${z.nameEn}" (French name "${z.name}") from World of Warcraft Classic, as it looks in the game.`,
    `The narrator describes it like this (French): """${z.text}"""`,
    "Paint the place itself: a characteristic vista with its landmarks, light and weather; no people, no",
    "creatures in the foreground, no text, no letters, no frame, no border, no logo. Hand-painted Blizzard",
    "concept-art style, warm and atmospheric, clear readable composition, the main subject in the central band",
    "(the top and bottom will be cropped to a 2:1 strip).",
  ].join(" ");
}

const run = promisify(execFile);

async function paint(z: Zone): Promise<void> {
  const master = join(MASTERS, `${z.map}.png`);
  if (existsSync(master)) return;
  const call = run("codex", ["exec", "--skip-git-repo-check", "-s", "read-only", prompt(z)],
    { maxBuffer: 1 << 24, timeout: 15 * 60 * 1000 });
  call.child.stdin?.end(); // codex exec reads a piped stdin until it closes
  const { stdout } = await call;
  const made = stdout.split("\n").map((l) => l.trim()).filter((l) => /^\/.*\.png$/.test(l)).pop();
  if (!made || !existsSync(made)) throw new Error(`${z.map} ${z.nameEn}: no image in Codex's answer`);
  copyFileSync(made, master);
  console.log(`painted ${z.map} ${z.nameEn}`);
}

function convert(z: Zone): void {
  const master = join(MASTERS, `${z.map}.png`);
  if (!existsSync(master)) return;
  const tga = join(OUT, `${z.map}.tga`);
  // ffmpeg writes top-left rows (descriptor 0x20): flip the rows, then mark the origin bottom-left (0x00, 24-bit)
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-i", master, "-vf",
    `scale=${W}:${H}:force_original_aspect_ratio=increase:flags=lanczos,crop=${W}:${H},vflip,format=bgr24`,
    "-rle", "0", tga]);
  execFileSync("dd", [`of=${tga}`, "bs=1", "seek=17", "conv=notrunc", "status=none"], { input: Buffer.from([0x00]) });
}

async function main(): Promise<void> {
  mkdirSync(MASTERS, { recursive: true });
  mkdirSync(OUT, { recursive: true });
  const list = zones();
  if (!convertOnly) {
    const queue = [...list];
    const failed: string[] = [];
    await Promise.all(Array.from({ length: jobs }, async () => {
      for (let z = queue.shift(); z; z = queue.shift()) {
        try {
          await paint(z);
        } catch (e) {
          failed.push(`${z.map} ${z.nameEn}: ${(e as Error).message.split("\n")[0]}`);
        }
      }
    }));
    if (failed.length) console.log(`failed (run again to retry):\n  ${failed.join("\n  ")}`);
  }
  list.forEach(convert);
  const done = list.filter((z) => existsSync(join(OUT, `${z.map}.tga`))).length;
  console.log(`${done}/${list.length} zone pictures in ${OUT}`);
}

main();
