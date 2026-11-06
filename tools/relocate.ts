// After the project folder is moved or renamed (2026-11-06: foreverspeech -> alliance-epique), points everything that
// recorded its old absolute path at the new one, so the tools keep working without reinstalling:
// - text files holding the old path: the launchers of the Python environments (.venv, .venv-voices: shebangs,
//   activate scripts), the luarocks wrappers (.luarocks/bin: busted, luacheck), the loops' journals (data/cache);
// - symbolic links inside the folder that point into the old path (worktree conveniences, dist/ stages);
// - git worktrees under the folder (`git worktree repair`).
// Never read: .git, the audio (addon audio, FLAC masters), files over 256 MB, binary files (a NUL byte in their first
// 8 KB, like grep -I). Outside the folder, nothing is touched: the game's link is redone by tools/link_addon.sh.
// Usage, from anywhere: node tools/relocate.ts <old absolute path> [--dry-run]
import { execFileSync } from "node:child_process";
import {
  closeSync, existsSync, lstatSync, openSync, readdirSync, readFileSync, readlinkSync, readSync, symlinkSync,
  unlinkSync, writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const DRY = args.includes("--dry-run");
const OLD = args.find((a) => !a.startsWith("--"))?.replace(/\/+$/, "");

if (!OLD || !OLD.startsWith("/")) {
  console.error("usage: node tools/relocate.ts <old absolute path> [--dry-run]");
  process.exit(2);
}
if (OLD === ROOT) {
  console.error(`the folder is still at ${OLD}: move it first, then run this from its new place`);
  process.exit(2);
}

const SKIP_DIRS = new Set([".git", "node_modules"]);
const SKIP_PATHS = new Set([join(ROOT, "addon/ForeverSpeech/audio"), join(ROOT, "data/audio")]);
const SKIP_EXT = /\.(ogg|flac|wav|mp3|pyc|so|dylib|safetensors|bin|pt|npz|npy|zip|png|jpe?g|tga|blp)$/i;
const MAX_SIZE = 256 * 1024 * 1024;
const OLD_BYTES = Buffer.from(OLD);

const rewritten: string[] = [];
const relinked: string[] = [];

function isBinary(path: string): boolean {
  const fd = openSync(path, "r");
  try {
    const head = Buffer.alloc(8192);
    const n = readSync(fd, head, 0, head.length, 0);
    return head.subarray(0, n).includes(0);
  } finally {
    closeSync(fd);
  }
}

function visit(dir: string): void {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isSymbolicLink()) {
      const target = readlinkSync(path);
      if (target === OLD || target.startsWith(OLD + "/")) {
        const moved = ROOT + target.slice(OLD.length);
        relinked.push(`${relative(ROOT, path)} -> ${moved}`);
        if (!DRY) {
          unlinkSync(path);
          symlinkSync(moved, path);
        }
      }
    } else if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name) && !SKIP_PATHS.has(path)) visit(path);
    } else if (entry.isFile() && !SKIP_EXT.test(entry.name)) {
      const size = lstatSync(path).size;
      if (size === 0 || size > MAX_SIZE || isBinary(path)) continue;
      const bytes = readFileSync(path);
      if (!bytes.includes(OLD_BYTES)) continue;
      rewritten.push(relative(ROOT, path));
      // latin1 maps each byte to one character and back: the file's bytes are kept exactly, the path is ASCII.
      if (!DRY) writeFileSync(path, Buffer.from(bytes.toString("latin1").split(OLD).join(ROOT), "latin1"));
    }
  }
}

visit(ROOT);

// Linked worktrees inside the folder: their records in .git/worktrees still name the old place.
const worktrees: string[] = [];
const records = join(ROOT, ".git/worktrees");
if (existsSync(records)) {
  for (const id of readdirSync(records)) {
    const gitdirFile = join(records, id, "gitdir");
    if (!existsSync(gitdirFile)) continue;
    const gitdir = readFileSync(gitdirFile, "utf8").trim();
    if (!gitdir.startsWith(OLD + "/")) continue;
    const tree = dirname(ROOT + gitdir.slice(OLD.length));
    if (!existsSync(tree)) continue;
    worktrees.push(relative(ROOT, tree));
    if (!DRY) execFileSync("git", ["worktree", "repair", tree], { cwd: ROOT, stdio: "inherit" });
  }
}

const verb = DRY ? "would" : "did";
console.log(`${OLD} -> ${ROOT}${DRY ? " (dry run)" : ""}`);
console.log(`${verb} rewrite ${rewritten.length} files, relink ${relinked.length} links, repair ${worktrees.length} worktrees`);
const groups = new Map<string, number>();
for (const file of rewritten) {
  const key = file.split("/").slice(0, 2).join("/");
  groups.set(key, (groups.get(key) ?? 0) + 1);
}
for (const [key, n] of [...groups].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(4)}  ${key}`);
for (const link of relinked) console.log(`  link  ${link}`);
for (const tree of worktrees) console.log(`  worktree  ${tree}`);
console.log("then: tools/link_addon.sh (the game's link to addon/ForeverSpeech)");
