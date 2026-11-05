"""Judge of the Elise loop: decides whether a take of one of her lines is good enough. READ-ONLY for the loop (sealed).

The actor has ElevenLabs read a line in her voice (data/voices/samples/elise/candidates/<line>_s<seed>.wav and .json)
and runs this judge: Whisper large-v3 hears the take once, and the take passes on the voice judge's thresholds
(tools/voices/judge.py: English, misread words, speed). Her voice is always the same, so there is no similarity
check. A good take becomes the quest's audio, like an NPC reading (game ogg addon/ForeverSpeech/audio/<id>/,
FLAC master data/audio/<zone>/<id>/, the zone's audio.json with engine "elevenlabs", her voice ID and the text's
hash). A failed take is deleted, unless it is the line's best so far (data/voices/samples/elise/review/<line>.wav).
After MAX_TRIES failed takes in one run, the line is "not_found" until the next run (never abandoned).
State: data/elise/state.json ({"lines": {<line id>: {zone, tries, campaign_tries, seeds, status, best}}});
every verdict goes to data/cache/loops/elise/tries.jsonl.
"""

from __future__ import annotations

import json
import shutil
import time
from pathlib import Path

from pipeline import narrator
from tools.elise import frame
from tools.voices import judge as voice_judge

MAX_TRIES = voice_judge.MAX_TRIES
ROOT = voice_judge.ROOT
ZONES = ROOT / "data" / "zones"
STATE = ROOT / "data" / "elise" / "state.json"
SAMPLES = ROOT / "data" / "voices" / "samples" / "elise"
CANDIDATES = SAMPLES / "candidates"
REVIEW = SAMPLES / "review"
GAME_AUDIO = ROOT / "addon" / "ForeverSpeech" / "audio"
MASTERS = ROOT / "data" / "audio"
TRIES_LOG = ROOT / "data" / "cache" / "loops" / "elise" / "tries.jsonl"
# audio.json section of each kind; "zone": her zone introductions, in the intro folders (data/zones/<group>/@intros/)
# "level": her level-up lines (data/zones/@elise/levels/); "companion": her companion lines (data/zones/@elise/companions/)
SECTION = {"detail": "audio", "complete": "complete", "zone": "zone", "level": "level", "companion": "companion"}
ENGINE = "elevenlabs"
REASONS = voice_judge.REASONS
verdict = voice_judge.verdict
badness = voice_judge.badness


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def voice_id(voices: dict | None = None) -> str | None:
    """Her ElevenLabs voice (tools/elise/voice.py), or None while she has none."""
    voices = voices if voices is not None else _read(voice_judge.VOICES_FILE, {"npcs": {}})["npcs"]
    return ((voices.get(str(narrator.NARRATOR_ID)) or {}).get("elevenlabs") or {}).get("voice_id")


def game_file(unit_id: str) -> str:
    return f"Interface\\AddOns\\ForeverSpeech\\audio\\{narrator.NARRATOR_ID}\\{unit_id}.ogg"


def audio_file(zone: str) -> Path:
    return ZONES / zone / "audio.json"


def accept(zone: str, take: Path, meta: dict, scores: dict, when: str) -> dict:
    """Puts a good take in place (game ogg, master FLAC) and returns its audio.json variant entry."""
    from pipeline.voices import audio
    unit = meta["id"]
    ogg = GAME_AUDIO / str(narrator.NARRATOR_ID) / f"{unit}.ogg"
    master = MASTERS / zone / str(narrator.NARRATOR_ID) / f"{unit}.flac"
    ogg.parent.mkdir(parents=True, exist_ok=True)
    master.parent.mkdir(parents=True, exist_ok=True)
    audio.to_ogg(take, ogg)
    audio.to_flac(take, master)
    return {"file": game_file(unit), "master": str(master.relative_to(ROOT)), "dur": scores["secs"],
            "cps": scores["cps"], "model": meta["model"], "engine": ENGINE, "voice_id": meta["voice_id"],
            "seed": meta["seed"], "scores": scores, "text": meta["text"], "text_hash": frame.text_hash(meta["text"]),
            "stamp": {"voice": meta["voice_id"]}, "created_at": when}


def candidates() -> list[Path]:
    return sorted(p for p in CANDIDATES.glob("*.wav") if p.with_suffix(".json").exists())


def _log(line: dict) -> None:
    TRIES_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(TRIES_LOG, "a", encoding="utf-8") as log:
        log.write(json.dumps(line, ensure_ascii=False) + "\n")


def judge_take(take: Path, hear, now=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"), say=print) -> str:
    """Judges one take (hear: Whisper's (probs, transcript, seconds)); saves the verdict at once. Returns the
    line's new status."""
    meta = _read(take.with_suffix(".json"), None)
    unit, zone = meta["id"], meta["zone"]
    probs, heard, seconds = hear(take)
    scores = voice_judge.scores_of(probs, heard, meta["text"], seconds)
    failed, when = verdict(scores), now()
    state = _read(STATE, {"schema": 1, "lines": {}})
    entry = state["lines"].get(unit) or {}
    entry = {**entry, "zone": zone, "quest": meta["quest"], "kind": meta["kind"], "sex": meta["sex"],
             "tries": entry.get("tries", 0) + 1, "campaign_tries": entry.get("campaign_tries", 0) + 1,
             "seeds": entry.get("seeds", []) + [meta["seed"]]}
    if not failed:
        data = _read(audio_file(zone), {"schema": 1, "audio": {}, "complete": {}})
        item = data.setdefault(SECTION[meta["kind"]], {}).setdefault(str(meta["quest"]),
                                                                     {"npc": narrator.NARRATOR_ID})
        item[meta["sex"]] = accept(zone, take, meta, scores, when)
        _write(audio_file(zone), data)
        (REVIEW / f"{unit}.wav").unlink(missing_ok=True)
        entry.pop("best", None)
        entry.update(status="ok", seed=meta["seed"], scores=scores)
        take.unlink()
    else:
        best = entry.get("best")
        if best is None or badness(scores) < badness(best["scores"]):
            REVIEW.mkdir(parents=True, exist_ok=True)
            shutil.move(take, REVIEW / f"{unit}.wav")
            entry["best"] = {"seed": meta["seed"], "scores": scores, "failed": failed, "text": meta["text"],
                             "take": str((REVIEW / f"{unit}.wav").relative_to(ROOT))}
        else:
            take.unlink()
        entry["status"] = "not_found" if entry["campaign_tries"] >= MAX_TRIES else "pending"
    state["lines"][unit] = entry
    _write(STATE, state)
    take.with_suffix(".json").unlink()
    _log({"at": when, "zone": zone, "line": unit, "seed": meta["seed"], "scores": scores, "failed": failed,
          "status": entry["status"], "heard": heard, "chars": len(meta["text"])})
    say(f"judge: {unit} s{meta['seed']}: English {scores['en'] * 100:.2f} %, misread {scores['wer'] * 100:.0f} %, "
        f"{scores['cps']} chars/s -> " + (", ".join(REASONS[f] for f in failed) or "ok")
        + ("; not found in this run" if entry["status"] == "not_found" else ""))
    return entry["status"]
