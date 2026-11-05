// Builds a shareable archive of the addon (2026-10-20): only what the game loads and plays, nothing of the pipeline.
// Kept: the files the TOC loads (minus dev\, the API dump tool), media\ (textures), and of audio\ only the files the
// index plays (data/index.lua: every `file`/`fileF`) and the test sound (core/player.lua, fallback "test"). Left out:
// the voice models and FLAC masters (data/, never in the addon), any audio the index does not name (the NPC dialogues
// are in since the index names them, v9, 2026-10-21: D14). In the archive's index, the `voice` fields are dropped (the pipeline's record of
// the voice a file was made with, §8; the addon never reads them). A LISEZMOI.txt (install, credits) goes next to the folder.
// Out: dist/ForeverSpeech-<version>-<date>.zip (dist/ is not versioned), its staging folder dist/ForeverSpeech.
// Needs the generated data/index.lua and data/game_voices.lua (pipeline/build_index.py, pipeline/game_voices.py).
// --tag: an annotated git tag archive-<version>-<date>[-n] on HEAD, once the zip is built (not pushed); refused while
// the addon's tracked files have uncommitted changes (the tag names the code; audio and index are not in git). The
// commit and the tag are written in LISEZMOI.txt either way: the archive tag, else a release tag on HEAD (v<version>,
// 2026-10-21: the GitHub releases).
//   node tools/package_addon.ts [--dry-run] [--tag]
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ADDON = join(ROOT, "addon/ForeverSpeech");
const DIST = join(ROOT, "dist");
const STAGE = join(DIST, "ForeverSpeech");
const TEST_SOUNDS = ["audio/test/test_1.ogg", "audio/test/test_2.ogg"];
const DRY = process.argv.includes("--dry-run");
const TAG = process.argv.includes("--tag");

const git = (...args: string[]) => execFileSync("git", args, { cwd: ROOT, encoding: "utf8" }).trim();

const mb = (bytes: number) => `${(bytes / 1024 / 1024).toFixed(0)} Mo`;

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)],
  );
}

// The TOC without the dev tools, and the files it loads (relative to the addon, forward slashes).
const toc = readFileSync(join(ADDON, "ForeverSpeech.toc"), "utf8");
const tocLines = toc.split("\n").filter((line) => !/^dev\\/.test(line.trim()));
const loaded = tocLines.map((l) => l.trim()).filter((l) => l && !l.startsWith("#")).map((l) => l.replace(/\\/g, "/"));
const version = (toc.match(/^## Version:\s*(\S+)/m) ?? [])[1] ?? "0";

// The audio the index plays.
const index = readFileSync(join(ADDON, "data/index.lua"), "utf8");
const played = new Set<string>();
for (const m of index.matchAll(/file[F]? = "Interface\\\\AddOns\\\\ForeverSpeech\\\\([^"]+)"/g)) {
  played.add(m[1].replace(/\\\\/g, "/"));
}

// Bindings.xml: loaded by the client from the addon's folder, not listed in the TOC (2026-10-21).
const files = new Set<string>([...loaded, ...TEST_SOUNDS, ...played, "Bindings.xml"]);
for (const f of walk(join(ADDON, "media"))) files.add(relative(ADDON, f));

const missing = [...files].filter((f) => !existsSync(join(ADDON, f)));
const kept = [...files].filter((f) => existsSync(join(ADDON, f))).sort();
const size = kept.reduce((sum, f) => sum + statSync(join(ADDON, f)).size, 0);
const allAudio = walk(join(ADDON, "audio"));
const leftOut = allAudio.filter((f) => !files.has(relative(ADDON, f)));
const leftOutSize = leftOut.reduce((sum, f) => sum + statSync(f).size, 0);

console.log(`addon v${version}: ${kept.length} files, ${mb(size)} (audio played by the index: ${played.size})`);
console.log(`left out: ${leftOut.length} audio files the index does not play (${mb(leftOutSize)}), dev/`);
if (missing.length) {
  console.log(`missing (named but absent): ${missing.length}, e.g. ${missing.slice(0, 5).join(", ")}`);
}
const date = new Date().toISOString().slice(0, 10);
const commit = git("rev-parse", "--short", "HEAD");
let tag = "";
const release = git("tag", "--points-at", "HEAD").split("\n").find((t) => /^v\d/.test(t)) ?? "";
if (TAG) {
  if (git("status", "--porcelain", "--", "addon")) {
    console.error("--tag: the addon has uncommitted changes; commit them first (nothing built)");
    process.exit(1);
  }
  const taken = new Set(git("tag", "--list", `archive-${version}-${date}*`).split("\n").filter(Boolean));
  tag = `archive-${version}-${date}`;
  for (let n = 2; taken.has(tag); n++) tag = `archive-${version}-${date}-${n}`;
  console.log(`tag: ${tag} on ${commit}`);
}
if (DRY) process.exit(0);

rmSync(STAGE, { recursive: true, force: true });
for (const f of kept) {
  mkdirSync(dirname(join(STAGE, f)), { recursive: true });
  copyFileSync(join(ADDON, f), join(STAGE, f));
}
writeFileSync(join(STAGE, "ForeverSpeech.toc"), tocLines.join("\n"));
const stripped = index.replace(/voice = "[^"]*",[ \t]*/g, "");
if (/voice = "/.test(stripped)) throw new Error("index.lua: a voice field left (its shape changed)");
writeFileSync(join(STAGE, "data/index.lua"), stripped);

writeFileSync(
  join(DIST, "LISEZMOI.txt"),
  `Alliance Épique ${version} (${date}) — ton compagnon pour l'Alliance sur WoW Forever : les quêtes lues à voix haute,
en français, une voix par PNJ ; Elise la narratrice ; du confort sans changer le jeu.
Version : ${tag || release || "sans tag"}, commit ${commit}.

Installation
  1. Fermer le jeu.
  2. Copier le dossier « ForeverSpeech » dans le dossier des addons :
       World of Warcraft/_forever_/Interface/AddOns/
  3. Lancer le jeu ; à la sélection du personnage, « AddOns » : Alliance Épique coché.

Utilisation
  /fs          ouvre la fenêtre de lecture
  /fs options  les options
  /fs help     toutes les commandes

Pour le client français, quêtes de l'Alliance. Projet de fan, sans garantie et sans lien avec Blizzard.

Crédits
  Données des quêtes et des PNJ : Forever Database (github.com/Stein-N/WoW-Quest-Database, GPL-3.0),
  d'après QuestieDB (GPL-3.0), VMaNGOS (GPL-2.0) et AzerothCore.
  Voix : Qwen3-TTS (génération locale) ; Elise : ElevenLabs.
  Textes des quêtes : Blizzard Entertainment. World of Warcraft est une marque de Blizzard Entertainment.
`,
);

const zip = join(DIST, `${tag ? tag.replace(/^archive-/, "ForeverSpeech-") : `ForeverSpeech-${version}-${date}`}.zip`);
rmSync(zip, { force: true });
// .ogg and .tga already compact or small: stored as they are (-n), the Lua compressed
execFileSync("zip", ["-q", "-r", "-X", "-n", ".ogg", zip, "ForeverSpeech", "LISEZMOI.txt"], { cwd: DIST });
console.log(`archive: ${relative(ROOT, zip)} (${mb(statSync(zip).size)})`);
if (tag) {
  git("tag", "-a", tag, "-m", `Shared archive ${tag}: ${kept.length} files, ${mb(statSync(zip).size)}, ${played.size} audio files`);
  console.log(`tagged ${tag} (local; to share it: git push origin ${tag})`);
}
