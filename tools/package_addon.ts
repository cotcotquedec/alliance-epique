// Builds the release archives of the addon (2026-10-20; two archives since 2026-11-05): only what the game loads and
// plays, nothing of the pipeline. The audio changes little and is heavy, the addon changes often (decided 2026-11-05):
// - the addon: the files the TOC loads (minus dev\, the API dump tool), media\ (textures), the index and the test sounds
//   (core/player.lua, fallback "test"); to publish (GitHub, CurseForge, Wago). Without the audio, every line plays with
//   the client's speech synthesis (the index names files the client does not find: the fallback);
// - the voices: of audio\ only the files the index plays (data/index.lua: every `file`/`fileF`), in their own folder
//   AllianceEpique_Voix (a TOC and audio; the addon reads them there, core/index.lua), to unzip into the AddOns folder
//   next to the addon's: an update of the addon replaces its folder, not this one; shared apart (a Drive link).
// Left out: the voice models and FLAC masters (data/, never in the addon), any audio the index does not name. In the
// addon's index, the `voice` fields are dropped (the pipeline's record of the voice a file was made with, §8; the addon
// never reads them). A LISEZMOI.txt (install, credits) goes in each archive, next to the folder.
// Out (dist/ is not versioned): dist/AllianceEpique-<version>-<date>.zip, staged in dist/addon/, and
// dist/AllianceEpique-audio-<version>-<date>.zip, staged in dist/voices/ (its TOC, and audio\ a link to the addon's:
// nothing copied).
// Needs the generated data/index.lua and data/game_voices.lua (pipeline/build_index.py, pipeline/game_voices.py).
// --no-audio: the addon's archive only (a release whose voices did not change).
// --tag: an annotated git tag archive-<version>-<date>[-n] on HEAD, once the archives are built (not pushed); refused
// while the addon's tracked files have uncommitted changes (the tag names the code; audio and index are not in git). The
// commit and the tag are written in LISEZMOI.txt either way: the archive tag, else a release tag on HEAD (v<version>,
// 2026-10-21: the GitHub releases).
//   node tools/package_addon.ts [--dry-run] [--no-audio] [--tag]
import { execFileSync } from "node:child_process";
import {
  copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync,
} from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ADDON = join(ROOT, "addon/ForeverSpeech");
const DIST = join(ROOT, "dist");
const TEST_SOUNDS = ["audio/test/test_1.ogg", "audio/test/test_2.ogg"];
const DRY = process.argv.includes("--dry-run");
const TAG = process.argv.includes("--tag");
const NO_AUDIO = process.argv.includes("--no-audio");

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
const audioSize = kept.filter((f) => f.startsWith("audio/") && !TEST_SOUNDS.includes(f))
  .reduce((sum, f) => sum + statSync(join(ADDON, f)).size, 0);
console.log(`archives: the addon ${mb(size - audioSize)}, its audio ${mb(audioSize)}${NO_AUDIO ? " (not built: --no-audio)" : ""}`);
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

const name = tag ? tag.replace(/^archive-/, "AllianceEpique-") : `AllianceEpique-${version}-${date}`;
const audioName = name.replace(/^AllianceEpique-/, "AllianceEpique-audio-");
const credits = `Pour le client français, quêtes de l'Alliance. Projet de fan, sans garantie et sans lien avec Blizzard.

Crédits
  Données des quêtes et des PNJ : Forever Database (github.com/Stein-N/WoW-Quest-Database, GPL-3.0),
  d'après QuestieDB (GPL-3.0), VMaNGOS (GPL-2.0) et AzerothCore.
  Voix : Qwen3-TTS (génération locale) ; Elise : ElevenLabs.
  Textes des quêtes : Blizzard Entertainment. World of Warcraft est une marque de Blizzard Entertainment.
`;

// The addon: staged in dist/addon/ (a few Mo), then zipped.
const addonFiles = kept.filter((f) => !f.startsWith("audio/") || TEST_SOUNDS.includes(f));
const audioFiles = kept.filter((f) => f.startsWith("audio/") && !TEST_SOUNDS.includes(f));
const ADDON_STAGE = join(DIST, "addon");
rmSync(ADDON_STAGE, { recursive: true, force: true });
for (const f of addonFiles) {
  mkdirSync(dirname(join(ADDON_STAGE, "ForeverSpeech", f)), { recursive: true });
  copyFileSync(join(ADDON, f), join(ADDON_STAGE, "ForeverSpeech", f));
}
writeFileSync(join(ADDON_STAGE, "ForeverSpeech", "ForeverSpeech.toc"), tocLines.join("\n"));
const stripped = index.replace(/voice = "[^"]*",[ \t]*/g, "");
if (/voice = "/.test(stripped)) throw new Error("index.lua: a voice field left (its shape changed)");
writeFileSync(join(ADDON_STAGE, "ForeverSpeech", "data/index.lua"), stripped);
writeFileSync(
  join(ADDON_STAGE, "LISEZMOI.txt"),
  `Alliance Épique ${version} (${date}) — ton compagnon pour l'Alliance sur WoW Forever : les quêtes lues à voix haute,
en français, une voix par PNJ ; Elise la narratrice ; du confort sans changer le jeu.
Version : ${tag || release || "sans tag"}, commit ${commit}.

Installation
  1. Fermer le jeu.
  2. Copier le dossier « ForeverSpeech » dans le dossier des addons :
       World of Warcraft/_forever_/Interface/AddOns/
  3. Les voix (facultatif, environ 3 Go) : l'archive « ${audioName}.zip », partagée à part. La décompresser dans le
     même dossier AddOns : elle y ajoute le dossier « AllianceEpique_Voix », à côté de « ForeverSpeech » (une mise à
     jour de l'addon n'y touche pas). Sans elle, les textes sont lus par la synthèse vocale du jeu.
  4. Lancer le jeu ; à la sélection du personnage, « AddOns » : Alliance Épique coché.

Conseillé (facultatif) : FlareUI, pour l'interface qui va avec (Alliance Épique en prend l'apparence quand il est là).

Utilisation
  /fs          ouvre la fenêtre de lecture
  /fs options  les options
  /fs help     toutes les commandes

${credits}`,
);
const zip = join(DIST, `${name}.zip`);
rmSync(zip, { force: true });
// .ogg and .tga already compact or small: stored as they are (-n), the Lua compressed
execFileSync("zip", ["-q", "-r", "-X", "-n", ".ogg", zip, "ForeverSpeech", "LISEZMOI.txt"], { cwd: ADDON_STAGE });
console.log(`addon: ${relative(ROOT, zip)} (${addonFiles.length} files, ${mb(statSync(zip).size)})`);

// The voices: their folder AllianceEpique_Voix staged in dist/voices/ (its TOC; audio\ a link to the addon's, followed
// by zip: no copy of 3 Go), with its own LISEZMOI.
const VOICES = "AllianceEpique_Voix";
let audioZip = "";
if (!NO_AUDIO) {
  audioZip = join(DIST, `${audioName}.zip`);
  rmSync(audioZip, { force: true });
  const VOICES_STAGE = join(DIST, "voices");
  rmSync(VOICES_STAGE, { recursive: true, force: true });
  mkdirSync(join(VOICES_STAGE, VOICES), { recursive: true });
  symlinkSync(join(ADDON, "audio"), join(VOICES_STAGE, VOICES, "audio"));
  writeFileSync(
    join(VOICES_STAGE, VOICES, `${VOICES}.toc`),
    [
      `## Interface: ${(toc.match(/^## Interface:\s*(\S+)/m) ?? [])[1] ?? "16001"}`,
      "## Title: Alliance Épique — Voix",
      "## Notes: The voices of Alliance Épique: the addon (ForeverSpeech) plays them from this folder.",
      "## Notes-frFR: Les voix d'Alliance Épique : l'addon (ForeverSpeech) les lit dans ce dossier.",
      "## Author: cotcotquedec",
      `## Version: ${version}`,
      "",
    ].join("\n"),
  );
  const notes = join(DIST, "LISEZMOI-voix.txt");
  writeFileSync(
    notes,
    `Alliance Épique — les voix (${audioFiles.length} fichiers), version ${version} (${date}), commit ${commit}.

Installation
  1. Fermer le jeu (de nouveaux fichiers ne sont vus qu'au lancement du jeu).
  2. Décompresser cette archive dans le dossier des addons :
       World of Warcraft/_forever_/Interface/AddOns/
     Elle y ajoute le dossier « AllianceEpique_Voix », à côté de « ForeverSpeech » (l'addon, installé à part) ; une mise
     à jour de l'addon, par CurseForge ou à la main, n'y touche pas.
  3. Lancer le jeu.

Les voix servent aussi aux versions suivantes de l'addon ; une quête sans sa voix est lue par la synthèse vocale du jeu.

${credits}`,
  );
  const names = [`${VOICES}/${VOICES}.toc`, ...audioFiles.map((f) => `${VOICES}/${f}`)].join("\n");
  execFileSync("zip", ["-q", "-X", "-n", ".ogg", audioZip, "-@"], { cwd: VOICES_STAGE, input: names });
  execFileSync("zip", ["-q", "-j", "-X", audioZip, notes]);
  rmSync(notes, { force: true });
  console.log(`audio: ${relative(ROOT, audioZip)} (${audioFiles.length} files, ${mb(statSync(audioZip).size)})`);
}
if (tag) {
  const what = audioZip ? `, audio ${mb(statSync(audioZip).size)}` : "";
  git("tag", "-a", tag, "-m", `Release archives ${tag}: addon ${mb(statSync(zip).size)}${what}, ${played.size} audio files`);
  console.log(`tagged ${tag} (local; to share it: git push origin ${tag})`);
}
