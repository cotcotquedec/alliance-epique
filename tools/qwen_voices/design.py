#!/usr/bin/env python3
"""NPC voices designed by Qwen3-TTS VoiceDesign from what we know of each NPC (2026-10-07).

For each NPC, a French voice description is built (the frame, tools/qwen_voices/frame.py) from its record
(data/voices.json: name, persona, race) and the accent of its race (data/accents.json), framed as a World of
Warcraft Alliance NPC, with a strong native-French opening: Qwen3 otherwise gives many voices an English accent. Qwen3-TTS VoiceDesign then reads the NPC's sample line
(or one of its quest texts, --text quest), a few seeds per NPC. With --score, Whisper large-v3 rates how French
each take sounds (p(en), the probability it hears English: a proxy for an English accent) and the page lists the
most French take first.

Output, per set (--set): data/voices/samples/qwen/<set>/<npc>/s<seed>.wav (mono 24 kHz, -20 LUFS) and voice.json
(description, text, engine, scores), then data/voices/samples/qwen/<set>/index.html. A take is regenerated only if
missing, if its description or text changed, or with --force.

Description only (any Python, no model):
  python3 -m tools.qwen_voices.design --npc 823 --dry-run
Generation (needs .venv-voices, tools/voices/setup.sh: MLX on the Mac, PyTorch on a CUDA box):
  .venv-voices/bin/python -m tools.qwen_voices.design --npc 823 --npc 9296 --npc 247
  ... -m tools.qwen_voices.design --per-race --text quest --set races --score
"""
import argparse
import datetime
import html
import json
import re
from pathlib import Path

from tools.qwen_voices import backend
from tools.qwen_voices.frame import LANGUAGE, LOUDNESS, REPO, SR, TEMPERATURE, describe, race_of

ROOT = Path(__file__).resolve().parents[2]
VOICES = ROOT / "data" / "voices.json"
ACCENTS = ROOT / "data" / "accents.json"
ZONES = ROOT / "data" / "zones"
OUT = ROOT / "data" / "voices" / "samples" / "qwen"
SEEDS = [11, 22, 33]
QUEST_CHARS = 380  # --text quest: the NPC's quest text closest to this length (~25 s)


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def detail_scripts(zones=ZONES):
    """npc id -> its quest acceptance scripts (scripts.json of every zone)."""
    out = {}
    for path in sorted(zones.glob("**/scripts.json")):
        for script in load(path).get("scripts", {}).values():
            if script.get("npc_id") and script.get("text"):
                out.setdefault(str(script["npc_id"]), []).append(script)
    return out


def quest_script(scripts):
    """The quest to read: not gendered (one text for every player), length closest to QUEST_CHARS."""
    plain = [s for s in scripts if not s.get("gendered")] or scripts
    return min(plain, key=lambda s: (abs(len(s["text"]) - QUEST_CHARS), s["quest_id"]))


def pick_per_race(records, accents, scripts):
    """One NPC per (race, sex) with a persona and a quest: confident persona, a quest of about QUEST_CHARS
    (within 150), adult, then the quest closest to QUEST_CHARS. Returns [(race, sex, npc id)] in the order of
    accents.json."""
    best = {}
    for npc_id, npc in records.items():
        persona, race = npc.get("persona") or {}, race_of(npc, accents)
        if not race or persona.get("sex") not in ("male", "female") or npc_id not in scripts:
            continue
        quest = quest_script(scripts[npc_id])
        gap = abs(len(quest["text"]) - QUEST_CHARS)
        rank = (persona.get("confidence") != "haute", gap > 150, persona.get("age") not in ("adulte", "mûr"),
                gap, int(npc_id))
        key = (race, persona["sex"])
        if key not in best or rank < best[key][0]:
            best[key] = (rank, npc_id)
    return [(race, sex, best[(race, sex)][1]) for race in accents["races"] for sex in ("male", "female")
            if (race, sex) in best]


def spoken(text):
    return re.sub(r"\s*\n+\s*", " ", text).strip()


class Designer:
    """Qwen3-TTS VoiceDesign on this machine's backend (tools/qwen_voices/backend.py), loaded on first use; or
    `qwen`, the loop's model server (tools/qwen_voices/server.py RemoteQwen)."""

    def __init__(self, qwen=None):
        import numpy as np
        import pyloudnorm as pyln
        import soundfile as sf
        import soxr
        self.np, self.pyln, self.sf, self.soxr = np, pyln, sf, soxr
        self.qwen = qwen or backend.Qwen(REPO)
        self.engine = self.qwen.engine

    def write(self, dest, text, instruct, seed):
        return self.save(dest, *self.qwen.design(text, instruct, LANGUAGE, TEMPERATURE, seed))

    def write_many(self, takes, seed):
        """Takes [(dest, text, instruct)] generated in one batch (backend.batch_size), the batch seeded with
        `seed`. Returns their durations."""
        results = self.qwen.design_many([(text, instruct) for _, text, instruct in takes], LANGUAGE, TEMPERATURE,
                                        seed)
        return [self.save(dest, audio, sr) for (dest, _, _), (audio, sr) in zip(takes, results)]

    def save(self, dest, audio, sr):
        np = self.np
        if sr != SR:
            audio = self.soxr.resample(audio, sr, SR)
        meter = self.pyln.Meter(SR)
        audio = np.clip(self.pyln.normalize.loudness(audio, meter.integrated_loudness(audio), LOUDNESS), -1, 1)
        self.sf.write(dest, audio.astype(np.float32), SR)
        return len(audio) / SR


class Scorer:
    """Whisper large-v3 language identification: p(fr) and p(en) of a take."""

    def __init__(self):
        import soundfile as sf
        import soxr
        self.sf, self.soxr = sf, soxr
        print("loading Whisper large-v3...", flush=True)
        self.model = backend.whisper("large-v3")

    def __call__(self, path):
        audio, sr = self.sf.read(path, dtype="float32")
        _, _, probs = self.model.detect_language(self.soxr.resample(audio, sr, 16000))
        probs = dict(probs)
        return {"fr": round(probs.get("fr", 0.0), 4), "en": round(probs.get("en", 0.0), 4)}


def generate(jobs, seeds, force, folder_of):
    """jobs: [(npc id, record, instruct, text, extra card fields)]."""
    designer, engine = None, backend.engine(REPO)
    for npc_id, npc, instruct, text, extra in jobs:
        folder = folder_of(npc_id)
        folder.mkdir(parents=True, exist_ok=True)
        card_path = folder / "voice.json"
        old = load(card_path) if card_path.exists() else {}
        stale = (force or old.get("instruct") != instruct or old.get("text") != text or old.get("engine") != engine
                 or old.get("temperature", 0.9) != TEMPERATURE)
        for seed in seeds:
            dest = folder / f"s{seed}.wav"
            if dest.exists() and not stale:
                continue
            designer = designer or Designer()
            secs = designer.write(dest, text, instruct, seed)
            print(f"[qwen] {npc_id} {npc['name']} s{seed}: {secs:.1f}s", flush=True)
        card_path.write_text(json.dumps(
            {"npc": int(npc_id), "name": npc["name"], **extra, "engine": engine, "temperature": TEMPERATURE,
             "seeds": seeds, "instruct": instruct, "text": text,
             "scores": {} if stale else old.get("scores", {}),
             "created_at": datetime.datetime.now().isoformat(timespec="seconds") if stale else old.get("created_at")},
            ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def score(ids, folder_of):
    scorer = None
    for npc_id in ids:
        card_path = folder_of(npc_id) / "voice.json"
        card = load(card_path)
        for seed in card["seeds"]:
            if str(seed) not in card["scores"]:
                scorer = scorer or Scorer()
                card["scores"][str(seed)] = scorer(folder_of(npc_id) / f"s{seed}.wav")
        card_path.write_text(json.dumps(card, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


SEX_FR = {"male": "homme", "female": "femme"}


def write_page(ids, records, accents, out):
    e = html.escape
    cards = []
    for npc_id in ids:
        card = load(out / npc_id / "voice.json")
        scores = card.get("scores", {})
        seeds = sorted(card["seeds"], key=lambda s: scores.get(str(s), {}).get("en", 1.0)) if scores else card["seeds"]
        tiles = []
        for rank, seed in enumerate(seeds):
            sc = scores.get(str(seed))
            chip = (f'<span class="chip">anglais {sc["en"] * 100:.1f} %</span>' if sc else "")
            best = " best" if sc and rank == 0 else ""
            title = "le plus français" if best else f"essai {seed}"
            tiles.append(f'<div class="tile{best}"><b>{title}</b><small>graine {seed}</small>'
                         f'<audio controls preload="none" src="{npc_id}/s{seed}.wav"></audio>{chip}</div>')
        npc = records[npc_id]
        persona = npc["persona"]
        race = race_of(npc, accents) or accents["default"]
        who = f'{accents["races"][race]["name_fr"]} · {SEX_FR.get(persona.get("sex"), "")} · {persona.get("age") or ""}'
        quest = f' — quête « {e(card["quest"])} »' if card.get("quest") else ""
        cards.append(f'<article class="card"><p class="who">{e(who)}</p>'
                     f'<h2>{e(card["name"])} <small>PNJ {npc_id}</small></h2>'
                     f'<div class="tiles">{"".join(tiles)}</div>'
                     f'<p class="label">Texte lu{quest}</p><p class="line">« {e(card["text"])} »</p>'
                     f'<details><summary>Description envoyée à Qwen3 ({len(card["instruct"].split())} mots)'
                     f'</summary><p class="desc">{e(card["instruct"])}</p></details></article>')
    page = (PAGE.replace("__STYLE__", STYLE).replace("__ENGINE__", e(backend.engine(REPO)))
            .replace("__BODY__", "".join(cards)))
    (out / "index.html").write_text(page, encoding="utf-8")
    print(f"open {out / 'index.html'}")


# Shared with the voice loop's zone pages (tools/voices/page.py).
STYLE = """
:root{--bg:#f5f1e8;--panel:#fffdf8;--ink:#221d16;--muted:#776e60;--line:#e4dccb;--soft:#efe8d9;--accent:#b8325a;
--ref:#5856d6;--best:#2e8b57}
@media (prefers-color-scheme:dark){:root{--bg:#13110e;--panel:#1c1915;--ink:#efe7d8;--muted:#a3998a;--line:#332e26;
--soft:#26221c;--accent:#f06a8f;--ref:#8f8cff;--best:#5cc98c}}
*{box-sizing:border-box}body{margin:0 auto;max-width:1100px;padding:24px 16px 60px;background:var(--bg);
color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif}
h1,h2{font-family:"Iowan Old Style",Palatino,Georgia,serif;font-weight:600;margin:0}h1{font-size:30px}
h2{font-size:21px;margin-bottom:10px}h2 small{color:var(--muted);font:12px system-ui}.intro{color:var(--muted);max-width:850px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:18px;margin-top:20px}
.who{color:var(--accent);font-size:13px;font-weight:600;margin:0 0 2px;text-transform:uppercase;letter-spacing:.04em}
.label{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em;margin:14px 0 2px}
.desc{font-size:14px;margin:6px 0 0}.line{font-style:italic;margin:0}details{margin-top:10px;color:var(--muted);font-size:13px}
summary{cursor:pointer}.tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
.tile{border:1px solid var(--line);border-left:4px solid var(--accent);border-radius:12px;padding:10px;
background:var(--bg);display:flex;flex-direction:column;gap:4px}.tile.ref{border-left-color:var(--ref)}
.tile.best{border-left-color:var(--best)}.tile.best b{color:var(--best)}
.tile small{color:var(--muted);font-size:12px}.tile audio{width:100%}
.chip{align-self:flex-start;font-size:12px;border-radius:6px;padding:1px 7px;background:var(--soft);color:var(--muted);
font-variant-numeric:tabular-nums}
.chips{display:flex;flex-wrap:wrap;gap:5px}.chip.bad{color:#c0392b;font-weight:600}
.note{color:var(--muted);font-size:13px;margin:6px 0 0}
@media (max-width:820px){.tiles{grid-template-columns:1fr 1fr}}@media (max-width:520px){.tiles{grid-template-columns:1fr}}
"""

PAGE = """<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Voix Qwen3 des PNJ</title>
<style>__STYLE__</style></head><body><h1>Voix Qwen3 des PNJ</h1>
<p class="intro">Qwen3-TTS VoiceDesign crée la voix de chaque PNJ à partir d'une description seule : un cadre
« comédien de doublage français natif », le contexte World of Warcraft (Alliance), l'identité du PNJ (race, sexe,
âge), son rôle, son caractère, sa voix et l'accent de sa race (<code>data/accents.json</code>). Plusieurs essais par
PNJ ; <b>anglais</b> : probabilité que Whisper large-v3 entende de l'anglais, un indice d'accent anglais. L'essai le
plus français est en premier ; l'oreille décide. Modèle : __ENGINE__.</p>
__BODY__
</body></html>"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--npc", action="append", default=[], help="NPC id (repeatable)")
    parser.add_argument("--per-race", action="store_true", help="one NPC per race and sex (accents.json)")
    parser.add_argument("--text", choices=["sample", "quest"], default="sample",
                        help="read the persona's sample line or one of the NPC's quest texts")
    parser.add_argument("--set", default="npcs", help="output folder and page under data/voices/samples/qwen/")
    parser.add_argument("--seeds", default=",".join(map(str, SEEDS)))
    parser.add_argument("--score", action="store_true", help="rate each take's French with Whisper large-v3")
    parser.add_argument("--force", action="store_true", help="regenerate every take")
    parser.add_argument("--dry-run", action="store_true", help="print the descriptions, generate nothing")
    args = parser.parse_args(argv)
    records, accents = load(VOICES)["npcs"], load(ACCENTS)
    scripts = detail_scripts() if args.per_race or args.text == "quest" else {}
    ids = list(args.npc)
    if args.per_race:
        picks = pick_per_race(records, accents, scripts)
        ids += [n for _, _, n in picks if n not in ids]
        for race, sex, n in picks:
            print(f"{race} {sex}: {n} {records[n]['name']}")
    if not ids:
        parser.error("--npc or --per-race")
    unknown = [n for n in ids if not (records.get(n) or {}).get("persona")
               or (args.text == "quest" and n not in scripts)]
    if unknown:
        raise SystemExit(f"no persona{' or quest' if args.text == 'quest' else ''} for NPC {', '.join(unknown)}")
    jobs = []
    for n in ids:
        npc, extra = records[n], {}
        text = npc["persona"]["sample_line"]
        if args.text == "quest":
            quest = quest_script(scripts[n])
            text, extra = spoken(quest["text"]), {"quest": quest["name"], "quest_id": quest["quest_id"]}
        jobs.append((n, npc, describe(npc, accents), text, extra))
    if args.dry_run:
        for n, _, instruct, text, _ in jobs:
            print(f"{n} ({len(instruct.split())} words): {instruct}\n  text ({len(text)} chars): {text}\n")
        return
    out = OUT / args.set
    folder_of = lambda n: out / n  # noqa: E731
    generate(jobs, [int(s) for s in args.seeds.split(",")], args.force, folder_of)
    if args.score:
        score(ids, folder_of)
    write_page(ids, records, accents, out)


if __name__ == "__main__":
    main()
