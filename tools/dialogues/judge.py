"""Judge of the dialogues loop: decides whether a dialogue reading is good enough. READ-ONLY for the loop (sealed).

Same judge as the quest readings (tools/readings/judge.py, unchanged and reused): Whisper large-v3 hears the take,
ECAPA compares its timbre with the NPC's model voice; it passes on the voice judge's thresholds (English, misread
words, speed) and a similarity of at least readings' MIN_SIM. A good take becomes the page's audio:
- the game file addon/ForeverSpeech/audio/<npc>/dialogue_<page>[_f].ogg and the master
  data/audio/<zone>/<npc>/dialogue_<page>[_f].flac;
- its entry in the zone's dialogue_audio.json ({"dialogues": {<npc>_<page>: {npc, page, m, f}}}), with its scores.
The dialogues have their own files (dialogue_audio.json, dialogue_readings.json): this loop never writes a file of
the readings or Elise loops. A failed take is deleted, unless it is the reading's best so far (kept in
dialogue_review/); after MAX_TRIES failed takes in one run, the reading is "not_found" until the next run.
Every verdict goes to data/cache/loops/dialogues/tries.jsonl.
"""

from __future__ import annotations

import json
import shutil
import time
from pathlib import Path

from tools.readings import judge as reading_judge

MAX_TRIES = reading_judge.MAX_TRIES
MODEL = reading_judge.MODEL
ROOT = reading_judge.ROOT
ZONES = ROOT / "data" / "zones"
SAMPLES = reading_judge.SAMPLES
CANDIDATES = SAMPLES / "dialogue_candidates"
REVIEW = SAMPLES / "dialogue_review"
GAME_AUDIO = ROOT / "addon" / "ForeverSpeech" / "audio"
MASTERS = ROOT / "data" / "audio"
TRIES_LOG = ROOT / "data" / "cache" / "loops" / "dialogues" / "tries.jsonl"
SECTION = "dialogues"
REASONS = reading_judge.REASONS
verdict, badness, flat, Ears = reading_judge.verdict, reading_judge.badness, reading_judge.flat, reading_judge.Ears
voice_judge = reading_judge.voice_judge


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def state_file(zone: str) -> Path:
    return ZONES / zone / "dialogue_readings.json"


def audio_file(zone: str) -> Path:
    return ZONES / zone / "dialogue_audio.json"


def file_name(unit_id: str) -> str:
    """'197_7590' -> 'dialogue_7590', '197_7590_f' -> 'dialogue_7590_f' (the NPC is the folder)."""
    _, rest = unit_id.split("_", 1)
    return f"dialogue_{rest}"


def game_file(npc: int, unit_id: str) -> str:
    return f"Interface\\AddOns\\ForeverSpeech\\audio\\{npc}\\{file_name(unit_id)}.ogg"


def candidates(zone: str) -> list[Path]:
    folder = CANDIDATES / flat(zone)
    return sorted(p for p in folder.glob("*.wav") if p.with_suffix(".json").exists())


def accept(zone: str, take: Path, meta: dict, scores: dict, when: str) -> dict:
    from pipeline.voices import audio
    npc, unit = meta["npc"], meta["id"]
    ogg = GAME_AUDIO / str(npc) / f"{file_name(unit)}.ogg"
    master = MASTERS / zone / str(npc) / f"{file_name(unit)}.flac"
    ogg.parent.mkdir(parents=True, exist_ok=True)
    master.parent.mkdir(parents=True, exist_ok=True)
    audio.to_ogg(take, ogg)
    audio.to_flac(take, master)
    return {"file": game_file(npc, unit), "master": str(master.relative_to(ROOT)), "dur": scores["secs"],
            "cps": scores["cps"], "model": MODEL, "engine": meta["engine"], "seed": meta["seed"], "scores": scores,
            "text": meta["text"], "stamp": {"voice": f"q{meta['voice_seed']}", "voice_seed": meta["voice_seed"]},
            "created_at": when}


def _log(line: dict) -> None:
    TRIES_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(TRIES_LOG, "a", encoding="utf-8") as log:
        log.write(json.dumps(line, ensure_ascii=False) + "\n")


def judge_take(zone: str, take: Path, ears, now=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"), say=print) -> str:
    """Judges one candidate take; saves the verdict at once. Returns the reading's new status."""
    meta = _read(take.with_suffix(".json"), None)
    unit = meta["id"]
    scores, heard = ears.scores(take, meta["text"], ROOT / meta["voice_ref"])
    failed, when = verdict(scores), now()
    state = _read(state_file(zone), {"schema": 1, "readings": {}})
    entry = state["readings"].get(unit) or {}
    entry = {**entry, "key": meta["key"], "page": meta["page"], "sex": meta["sex"], "npc": meta["npc"],
             "tries": entry.get("tries", 0) + 1, "campaign_tries": entry.get("campaign_tries", 0) + 1,
             "seeds": entry.get("seeds", []) + [meta["seed"]]}
    if not failed:
        data = _read(audio_file(zone), {"schema": 1, SECTION: {}})
        item = data.setdefault(SECTION, {}).setdefault(meta["key"], {"npc": meta["npc"], "page": meta["page"]})
        item[meta["sex"]] = accept(zone, take, meta, scores, when)
        _write(audio_file(zone), data)
        shutil.rmtree(REVIEW / flat(zone) / unit, ignore_errors=True)
        entry.pop("best", None)
        entry.update(status="ok", seed=meta["seed"], scores=scores)
        take.unlink()
    else:
        best = entry.get("best")
        if best is None or badness(scores) < badness(best["scores"]):
            folder = REVIEW / flat(zone) / unit
            folder.mkdir(parents=True, exist_ok=True)
            shutil.move(take, folder / "best.wav")
            entry["best"] = {"seed": meta["seed"], "scores": scores, "failed": failed,
                             "take": str((folder / "best.wav").relative_to(ROOT)), "engine": meta["engine"],
                             "text": meta["text"], "voice_seed": meta["voice_seed"]}
        else:
            take.unlink()
        entry["status"] = "not_found" if entry["campaign_tries"] >= MAX_TRIES else "pending"
    state["readings"][unit] = entry
    _write(state_file(zone), state)
    take.with_suffix(".json").unlink()
    _log({"at": when, "zone": zone, "reading": unit, "npc": meta["npc"], "seed": meta["seed"], "scores": scores,
          "failed": failed, "status": entry["status"], "heard": heard})
    say(f"judge: {unit} s{meta['seed']}: English {scores['en'] * 100:.2f} %, misread {scores['wer'] * 100:.0f} %, "
        f"{scores['cps']} chars/s, voice {scores['sim']:.2f} -> " + (", ".join(REASONS[f] for f in failed) or "ok")
        + ("; not found in this run" if entry["status"] == "not_found" else ""))
    return entry["status"]
