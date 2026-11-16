// Re-encode the game's audio files from their lossless masters in the game format of pipeline/voices/audio.py
// (2026-11-16: mono, 24 kHz, Vorbis quality 1; formerly stereo 44.1 kHz q6, 3.4 GB -> about 0.93 GB).
//
// Every game file the audio registries name (data/zones/**/audio.json and dialogue_audio.json: any object with `file`
// and `master`) is encoded again from its master, unless its Vorbis header already says mono 24 kHz. Nothing is
// generated, no registry changes (the duration stays). A file is written next to its target then renamed over it.
// Never while a loop that writes audio runs (readings, dialogues, Elise, books). In the game, a rewritten .ogg is heard
// only after a full restart of the client (S2), not after /reload.
//
//   node tools/reencode_audio.ts [--dry-run] [--jobs N] [--limit N] [--root DIR (another checkout)]
import { execFile } from "node:child_process";
import { closeSync, existsSync, openSync, readdirSync, readFileSync, readSync, renameSync, rmSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);
const ROOT_AT = process.argv.indexOf("--root");
const ROOT = ROOT_AT >= 0 ? resolve(process.argv[ROOT_AT + 1]) : resolve(import.meta.dirname, "..");
const ZONES = join(ROOT, "data", "zones");
const ADDONS_PREFIX = "Interface\\AddOns\\";
const CHANNELS = 1;
const RATE = 24000;
const QUALITY = 1;

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const option = (name: string, fallback: number) => {
  const i = args.indexOf(name);
  return i >= 0 ? Number(args[i + 1]) : fallback;
};
const DRY = flag("--dry-run");
const JOBS = option("--jobs", 8);
const LIMIT = option("--limit", Infinity);

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(dir, e.name)) : /^(dialogue_)?audio\.json$/.test(e.name) ? [join(dir, e.name)] : []);
}

// Every {file, master} pair of a registry, wherever it sits (quest, completion, zone, level, book, dialogue...).
function pairs(node: unknown, out: Map<string, string>): void {
  if (Array.isArray(node)) {
    for (const x of node) pairs(x, out);
  } else if (node && typeof node === "object") {
    const o = node as Record<string, unknown>;
    if (typeof o.file === "string" && typeof o.master === "string" && o.file.startsWith(ADDONS_PREFIX)) {
      out.set(join(ROOT, "addon", ...o.file.slice(ADDONS_PREFIX.length).split("\\")), join(ROOT, o.master));
    }
    for (const v of Object.values(o)) pairs(v, out);
  }
}

// The Vorbis identification header (first Ogg page): "\x01vorbis", version (4), channels (1), sample rate (4, LE).
export function vorbisFormat(path: string): { channels: number; rate: number } | null {
  const buf = Buffer.alloc(128);
  const fd = openSync(path, "r");
  try {
    readSync(fd, buf, 0, buf.length, 0);
  } finally {
    closeSync(fd);
  }
  const at = buf.indexOf("\x01vorbis", 0, "latin1");
  if (at < 0 || at + 16 > buf.length) return null;
  return { channels: buf[at + 11], rate: buf.readUInt32LE(at + 12) };
}

const files = new Map<string, string>();
for (const registry of walk(ZONES)) pairs(JSON.parse(readFileSync(registry, "utf8")), files);

let done = 0, already = 0, absent = 0, before = 0, after = 0;
const missing: string[] = [];
const failed: string[] = [];
const todo: [string, string][] = [];
for (const [ogg, master] of files) {
  if (!existsSync(ogg)) {
    absent++; // not on this machine (a worktree has no audio; or the registry is ahead of this machine's audio)
    continue;
  }
  if (!existsSync(master)) {
    missing.push(ogg);
    continue;
  }
  const format = vorbisFormat(ogg);
  if (format && format.channels === CHANNELS && format.rate === RATE) {
    already++;
    continue;
  }
  todo.push([ogg, master]);
}
const batch = todo.slice(0, LIMIT);
console.log(`${files.size} game files in the registries: ${already} already mono ${RATE / 1000} kHz, ` +
  `${todo.length} to re-encode${batch.length < todo.length ? ` (${batch.length} this run)` : ""}, ` +
  `${missing.length} without their master, ${absent} not on this machine`);
if (absent === files.size && files.size) {
  console.log(`no audio under ${join(ROOT, "addon")}: run it in the game folder, or pass --root <game folder>`);
}

async function encode([ogg, master]: [string, string]): Promise<void> {
  const wav = `${ogg}.reencode.wav`;
  const tmp = `${ogg}.reencode.ogg`;
  try {
    await run("ffmpeg", ["-y", "-v", "error", "-i", master, "-ac", String(CHANNELS), "-ar", String(RATE),
      "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", wav]);
    await run("oggenc", ["--quiet", "-q", String(QUALITY), "-o", tmp, wav]);
    before += statSync(ogg).size;
    after += statSync(tmp).size;
    renameSync(tmp, ogg);
    done++;
  } catch (err) {
    failed.push(`${ogg}: ${(err as Error).message.split("\n")[0]}`);
    rmSync(tmp, { force: true });
  } finally {
    rmSync(wav, { force: true });
  }
}

if (!DRY && batch.length) {
  let next = 0;
  const started = Date.now();
  await Promise.all(Array.from({ length: Math.min(JOBS, batch.length) }, async () => {
    while (next < batch.length) {
      await encode(batch[next++]);
      if ((done + failed.length) % 500 === 0) {
        console.log(`  ${done + failed.length}/${batch.length} (${Math.round((Date.now() - started) / 1000)} s)`);
      }
    }
  }));
  const mb = (n: number) => `${(n / 1e6).toFixed(0)} MB`;
  console.log(`re-encoded ${done}: ${mb(before)} -> ${mb(after)}; failed ${failed.length}`);
}
for (const f of failed) console.log(`failed: ${f}`);
if (missing.length) console.log(`without master (left as they are): ${missing.slice(0, 20).join(", ")}${missing.length > 20 ? " ..." : ""}`);
process.exitCode = failed.length ? 1 : 0;
